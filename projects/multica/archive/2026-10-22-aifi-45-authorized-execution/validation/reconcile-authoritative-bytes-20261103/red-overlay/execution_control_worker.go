// AIFIRST: trusted T committed verdict channel — daemon control worker (M003, S4).
//
// 一个 lineage/store 在任意时刻只有一个合法 owner。重启不清 epoch、不跳 seq：
// 接管只把 owner_fence 加一，last_seq/last_digest 原样保留。
// 恢复只判定「本地 checkpoint 与链尾的关系」，不一致就冻结，绝不续写。
package daemon

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/multica-ai/multica/server/internal/governance"
)

var (
	// ErrWorkerFenceRejected 是旧 owner 还想写。
	ErrWorkerFenceRejected = errors.New("EXECUTION_CONTROL_FENCE_REJECTED")
	// ErrWorkerFrozen 是恢复判定为不可续写。
	ErrWorkerFrozen = errors.New("EXECUTION_CONTROL_WORKER_FROZEN")
	// ErrWorkerInvalid 是调用参数不成立。
	ErrWorkerInvalid = errors.New("EXECUTION_CONTROL_WORKER_INVALID")
)

// OwnerFence 是一次接管的身份。Epoch 与 Fence 不同：Epoch 标识存储世代，
// Fence 标识当前 owner。重启只换 Fence。
type OwnerFence struct {
	LineageID  string
	StoreID    string
	Epoch      int64
	Fence      int64
	OwnerID    string
	LastSeq    int64
	LastDigest string
}

// BeginOwnerTx 接管该 lineage/store 的最新 epoch。没有 cursor 时建 epoch 1。
// 已有 cursor 时只把 owner_fence 加一，epoch 与链尾不动。
func BeginOwnerTx(ctx context.Context, tx pgx.Tx, scope, lineageID, storeID, ownerID string) (OwnerFence, error) {
	if lineageID == "" || storeID == "" || ownerID == "" {
		return OwnerFence{}, fmt.Errorf("%w: lineage/store/owner 都必须有值", ErrWorkerInvalid)
	}
	var epoch, fence, lastSeq int64
	var lastDigest *string
	err := tx.QueryRow(ctx, `
		SELECT epoch, owner_fence, last_seq, last_digest
		FROM cr_execution_tool_cursor
		WHERE lineage_id = $1::uuid AND store_id = $2
		ORDER BY epoch DESC
		LIMIT 1
		FOR UPDATE`, lineageID, storeID).Scan(&epoch, &fence, &lastSeq, &lastDigest)
	if errors.Is(err, pgx.ErrNoRows) {
		if scope == "" {
			return OwnerFence{}, fmt.Errorf("%w: 冷启动必须给出 scope", ErrWorkerInvalid)
		}
		if err := tx.QueryRow(ctx, `
			INSERT INTO cr_execution_tool_cursor (scope, lineage_id, store_id, epoch, owner_fence, owner_id)
			VALUES ($1, $2::uuid, $3, 1, 1, $4)
			RETURNING epoch, owner_fence`, scope, lineageID, storeID, ownerID).Scan(&epoch, &fence); err != nil {
			return OwnerFence{}, fmt.Errorf("worker begin owner: %w", err)
		}
		return OwnerFence{LineageID: lineageID, StoreID: storeID, Epoch: epoch, Fence: fence, OwnerID: ownerID}, nil
	}
	if err != nil {
		return OwnerFence{}, fmt.Errorf("worker begin owner: %w", err)
	}
	// 接管：fence 单调加一，epoch 与链尾原样保留。
	if err := tx.QueryRow(ctx, `
		UPDATE cr_execution_tool_cursor
		SET owner_fence = owner_fence + 1, owner_id = $4, updated_at = now()
		WHERE lineage_id = $1::uuid AND store_id = $2 AND epoch = $3
		RETURNING owner_fence`, lineageID, storeID, epoch, ownerID).Scan(&fence); err != nil {
		return OwnerFence{}, fmt.Errorf("worker take over: %w", err)
	}
	digest := ""
	if lastDigest != nil {
		digest = *lastDigest
	}
	// 回读整行：epoch/链尾必须来自库里真实的行，不能只看本地变量。
	if err := tx.QueryRow(ctx, `
		SELECT epoch, last_seq, COALESCE(last_digest, '')
		FROM cr_execution_tool_cursor
		WHERE lineage_id = $1::uuid AND store_id = $2 AND owner_fence = $3`,
		lineageID, storeID, fence).Scan(&epoch, &lastSeq, &digest); err != nil {
		return OwnerFence{}, fmt.Errorf("worker read back: %w", err)
	}
	return OwnerFence{
		LineageID: lineageID, StoreID: storeID, Epoch: epoch, Fence: fence,
		OwnerID: ownerID, LastSeq: lastSeq, LastDigest: digest,
	}, nil
}

// PreparedJournal 是 worker 本地已备好的那一帧。Complete 表示 bundle 齐全、原 bytes 可用。
type PreparedJournal struct {
	VerdictID    string
	RequestID    string
	Seq          int64
	PayloadBytes []byte
	Envelope     []byte
	CommitRef    string
	ReceiptRef   string
	Complete     bool
}

// ReconcileCheckpoint 是重启时本地磁盘上的进度。
type ReconcileCheckpoint struct {
	LineageID  string
	StoreID    string
	Epoch      int64
	LastSeq    int64
	LastDigest string
	Journal    *PreparedJournal
}

const (
	ReconcileReady  = "ready"
	ReconcileFrozen = "frozen"
)

// ReconcileResult 说明能否继续服务，以及要继续的头在哪。
type ReconcileResult struct {
	State        string
	Epoch        int64
	Fence        int64
	LastSeq      int64
	LastDigest   string
	FrozenReason string
	// Imported 非空表示 T 恰好领先一格，本地补上这一帧后可以继续。
	Imported *governance.VerdictFrameApplied
	// Replayed 非空表示 journal 已完整，直接重发这些原 bytes，不重算。
	Replayed []byte
}

// ReconcileOwnerTx 判定本地 checkpoint 能否续写。四个出口：
// 链尾相同→继续；T 领先一格→补一格后继续；journal 已备且完整→重发原 bytes；
// 其余（缺 store、epoch 不符、落后多格、分叉）一律冻结。
func ReconcileOwnerTx(ctx context.Context, tx pgx.Tx, checkout ReconcileCheckpoint) (ReconcileResult, error) {
	if checkout.LineageID == "" || checkout.StoreID == "" {
		return ReconcileResult{}, fmt.Errorf("%w: checkpoint 缺 lineage/store", ErrWorkerInvalid)
	}
	var epoch, fence, lastSeq int64
	var lastDigest *string
	err := tx.QueryRow(ctx, `
		SELECT epoch, owner_fence, last_seq, last_digest
		FROM cr_execution_tool_cursor
		WHERE lineage_id = $1::uuid AND store_id = $2
		ORDER BY epoch DESC
		LIMIT 1
		FOR UPDATE`, checkout.LineageID, checkout.StoreID).Scan(&epoch, &fence, &lastSeq, &lastDigest)
	frozen := func(reason string) (ReconcileResult, error) {
		return ReconcileResult{
			State: ReconcileFrozen, Epoch: epoch, Fence: fence,
			LastSeq: lastSeq, FrozenReason: reason,
		}, nil
	}
	if errors.Is(err, pgx.ErrNoRows) {
		// 没有 store 就无法核实本地进度，不能当作「从头开始」续写。
		return ReconcileResult{State: ReconcileFrozen, FrozenReason: "missing_store"}, nil
	}
	if err != nil {
		return ReconcileResult{}, fmt.Errorf("worker reconcile: %w", err)
	}
	digest := ""
	if lastDigest != nil {
		digest = *lastDigest
	}
	ready := func() (ReconcileResult, error) {
		return ReconcileResult{
			State: ReconcileReady, Epoch: epoch, Fence: fence,
			LastSeq: lastSeq, LastDigest: digest,
		}, nil
	}
	if checkout.Epoch != epoch {
		return frozen("epoch_mismatch")
	}
	// journal 已备且 bundle 完整：重发原 bytes，不重算摘要。
	if checkout.Journal != nil {
		journal := checkout.Journal
		if !journal.Complete {
			return frozen("journal_incomplete")
		}
		if journal.Seq > lastSeq {
			// 本地有链上还没有的帧，不能拿它当已提交。
			return frozen("journal_ahead")
		}
		var storedDigest string
		err := tx.QueryRow(ctx, `SELECT digest FROM cr_execution_tool_verdict WHERE request_id = $1::uuid`,
			journal.RequestID).Scan(&storedDigest)
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return ReconcileResult{}, fmt.Errorf("worker journal lookup: %w", err)
		}
		if err == nil && journal.Seq == lastSeq && storedDigest == digest {
			result, err := ready()
			if err != nil {
				return result, err
			}
			result.Replayed = journal.PayloadBytes
			return result, nil
		}
		if err == nil {
			return frozen("journal_divergent")
		}
	}
	switch {
	case checkout.LastSeq == lastSeq && checkout.LastDigest == digest:
		return ready()
	case checkout.LastSeq+1 == lastSeq:
		// T 恰好领先一格：把这一帧补进本地，然后继续。
		var frame governance.VerdictFrameApplied
		var frameDigest, prev string
		if err := tx.QueryRow(ctx, `
			SELECT id::text, digest, COALESCE(prev_digest, '')
			FROM cr_execution_tool_verdict
			WHERE lineage_id = $1::uuid AND store_id = $2 AND epoch = $3 AND seq = $4`,
			checkout.LineageID, checkout.StoreID, epoch, lastSeq).Scan(&frame.VerdictID, &frameDigest, &prev); err != nil {
			return ReconcileResult{}, fmt.Errorf("worker import head: %w", err)
		}
		if prev != checkout.LastDigest {
			return frozen("chain_gap")
		}
		frame.Digest = frameDigest
		result, err := ready()
		if err != nil {
			return result, err
		}
		result.Imported = &frame
		return result, nil
	default:
		return frozen("divergent")
	}
}

// sameVerdictID 比较两个 UUID 文本的值；任一侧无法解析时按不同处理。
func sameVerdictID(left, right string) bool {
	leftID, leftErr := uuid.Parse(left)
	rightID, rightErr := uuid.Parse(right)
	if leftErr != nil || rightErr != nil {
		return false
	}
	return leftID == rightID
}

// ControlWorker 是持有当前 fence 的写入者。
type ControlWorker struct {
	fence OwnerFence
}

// NewControlWorker 绑定一次接管得到的 fence。
func NewControlWorker(fence OwnerFence) *ControlWorker {
	return &ControlWorker{fence: fence}
}

// Fence 返回当前身份，供调用方记录。
func (w *ControlWorker) Fence() OwnerFence { return w.fence }

// assertFenceTx 确认自己仍是 owner。旧 fence 一律拒绝，不「尽力而为」。
func (w *ControlWorker) assertFenceTx(ctx context.Context, tx pgx.Tx) error {
	var current int64
	err := tx.QueryRow(ctx, `
		SELECT owner_fence FROM cr_execution_tool_cursor
		WHERE lineage_id = $1::uuid AND store_id = $2 AND epoch = $3
		FOR UPDATE`, w.fence.LineageID, w.fence.StoreID, w.fence.Epoch).Scan(&current)
	if err != nil {
		return fmt.Errorf("worker fence read: %w", err)
	}
	if current != w.fence.Fence {
		return fmt.Errorf("%w: 当前 owner_fence=%d，本 worker 持 %d", ErrWorkerFenceRejected, current, w.fence.Fence)
	}
	return nil
}

// ApplyTx 在持锁事务内追加一帧。旧 fence 直接拒绝。
func (w *ControlWorker) ApplyTx(ctx context.Context, tx pgx.Tx, in governance.VerdictFrameInput) (governance.VerdictFrameApplied, error) {
	if err := w.assertFenceTx(ctx, tx); err != nil {
		return governance.VerdictFrameApplied{}, err
	}
	if in.Now.IsZero() {
		in.Now = time.Now().UTC()
	}
	in.LineageID = w.fence.LineageID
	in.StoreID = w.fence.StoreID
	in.Epoch = w.fence.Epoch
	// prev 指向本 worker 见过的链尾；链尾由 cursor 决定，不由调用方自报。
	if in.PrevDigest == "" {
		in.PrevDigest = w.fence.LastDigest
	}
	applied, err := governance.AppendVerdictFrameTx(ctx, tx, in)
	if err != nil {
		return applied, err
	}
	if !applied.Replayed {
		w.fence.LastSeq = in.Seq
		w.fence.LastDigest = applied.Digest
	}
	return applied, nil
}
