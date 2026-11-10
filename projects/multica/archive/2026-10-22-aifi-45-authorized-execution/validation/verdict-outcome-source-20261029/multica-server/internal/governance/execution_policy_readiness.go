// AIFIRST: trusted T committed verdict channel — D7 readiness protocol (M003, S8 R2).
//
// 无环顺序：①冻结 request 与它的 observation_slots；②每个登记 observer 只登记一份不可变
// 观测；③全部 slot 齐了才允许写最终 signed verdict，写一次就不再变。
// 这里只做协议与持久化，不做版本/能力求值 —— 那是 T 的唯一 evaluator 的事。
package governance

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	// ErrReadinessInvalid 是请求本身不成立（缺字段、slot 不属于本 request）。
	ErrReadinessInvalid = errors.New("EXECUTION_READINESS_INVALID")
	// ErrReadinessConflict 是第二次写入与已冻结内容冲突。
	ErrReadinessConflict = errors.New("EXECUTION_READINESS_CONFLICT")
	// ErrReadinessIncomplete 是 slot 还没齐。
	ErrReadinessIncomplete = errors.New("EXECUTION_READINESS_INCOMPLETE")
)

// ReadinessActions 是 action 闭集。
var ReadinessActions = map[string]string{
	"verify-channel":      "READY_COMPONENT",
	"enable-policy":       "READY_STRICT",
	"retire-legacy-relay": "READY_TO_RETIRE",
}

// ReadinessSlot 是冻结在 request 里的一个观测位。
type ReadinessSlot struct {
	ID         string `json:"id"`
	InstanceID string `json:"instance_id"`
	Role       string `json:"role"`
}

// ReadinessRequestInput 是写 request 行需要的全部输入。
type ReadinessRequestInput struct {
	RequestID    string
	Scope        string
	Target       string
	Nonce        string
	Generation   int64
	Expiry       time.Time
	CommandBytes []byte
}

// ReadinessRequest 是读回来的 request 行。
type ReadinessRequest struct {
	RequestID  string
	Scope      string
	Target     string
	Nonce      string
	Generation int64
	Expiry     time.Time
	Slots      []ReadinessSlot
	Frames     map[string]ReadinessFrame
	Verdict    []byte
	Digest     string
}

// ReadinessFrame 是一个已登记的观测。
type ReadinessFrame struct {
	Digest string `json:"digest"`
	Bytes  string `json:"payload_b64"`
}

// frozenSlots 只从已冻结的 command 字节里取 slot 名单。
// request 一旦写进库，slot 名单就不可改；任何后来的观测都必须落在其中。
func frozenSlots(commandBytes []byte) ([]ReadinessSlot, error) {
	var parsed struct {
		ObservationSlots []ReadinessSlot `json:"observation_slots"`
	}
	if err := json.Unmarshal(commandBytes, &parsed); err != nil {
		return nil, fmt.Errorf("%w: request 不是合法 JSON: %v", ErrReadinessInvalid, err)
	}
	return parsed.ObservationSlots, nil
}

// OpenReadinessRequestTx 冻结一份 request。同一 request_id 或同一 nonce 再写一律冲突。
func OpenReadinessRequestTx(ctx context.Context, tx pgx.Tx, in ReadinessRequestInput) (ReadinessRequest, error) {
	if in.RequestID == "" || in.Scope == "" || in.Nonce == "" || len(in.CommandBytes) == 0 {
		return ReadinessRequest{}, fmt.Errorf("%w: request/scope/nonce/command 必须有值", ErrReadinessInvalid)
	}
	if in.Generation <= 0 {
		return ReadinessRequest{}, fmt.Errorf("%w: generation 必须为正", ErrReadinessInvalid)
	}
	if _, ok := ReadinessActions[in.Target]; !ok {
		return ReadinessRequest{}, fmt.Errorf("%w: 未知 target %q", ErrReadinessInvalid, in.Target)
	}
	slots, err := frozenSlots(in.CommandBytes)
	if err != nil {
		return ReadinessRequest{}, err
	}
	if len(slots) == 0 {
		// 空 slot 的 request 会让「全部到位」变成空真，等于不核对任何实例。
		return ReadinessRequest{}, fmt.Errorf("%w: observation_slots 不能为空", ErrReadinessInvalid)
	}
	seen := map[string]bool{}
	for _, slot := range slots {
		if slot.ID == "" || slot.InstanceID == "" || slot.Role == "" {
			return ReadinessRequest{}, fmt.Errorf("%w: slot 缺 id/instance/role", ErrReadinessInvalid)
		}
		if seen[slot.ID] {
			return ReadinessRequest{}, fmt.Errorf("%w: slot %s 重复", ErrReadinessInvalid, slot.ID)
		}
		seen[slot.ID] = true
	}
	var existing string
	err = tx.QueryRow(ctx, `SELECT request_id::text FROM cr_execution_policy_readiness WHERE request_id = $1::uuid`,
		in.RequestID).Scan(&existing)
	switch {
	case err == nil:
		return ReadinessRequest{}, fmt.Errorf("%w: request 已冻结，不能重写 slot", ErrReadinessConflict)
	case !errors.Is(err, pgx.ErrNoRows):
		return ReadinessRequest{}, fmt.Errorf("readiness request lookup: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO cr_execution_policy_readiness (
			request_id, scope, target, nonce, generation, expiry, command_bytes, observation_frames
		) VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, '{}'::jsonb)`,
		in.RequestID, in.Scope, in.Target, in.Nonce, in.Generation, in.Expiry, in.CommandBytes); err != nil {
		if isUniqueViolation(err) {
			return ReadinessRequest{}, fmt.Errorf("%w: nonce 已被别的 request 用过", ErrReadinessConflict)
		}
		return ReadinessRequest{}, fmt.Errorf("readiness insert: %w", err)
	}
	return LoadReadinessRequestTx(ctx, tx, in.RequestID)
}

// LoadReadinessRequestTx 读一行并解析冻结的 slot 名单。
func LoadReadinessRequestTx(ctx context.Context, tx pgx.Tx, requestID string) (ReadinessRequest, error) {
	var out ReadinessRequest
	var commandBytes []byte
	var frames []byte
	var verdict []byte
	var digest *string
	err := tx.QueryRow(ctx, `
		SELECT request_id::text, scope, target, nonce, generation, expiry,
		       command_bytes, observation_frames, verdict_bytes, digest
		FROM cr_execution_policy_readiness WHERE request_id = $1::uuid`, requestID).
		Scan(&out.RequestID, &out.Scope, &out.Target, &out.Nonce, &out.Generation, &out.Expiry,
			&commandBytes, &frames, &verdict, &digest)
	if err != nil {
		return ReadinessRequest{}, fmt.Errorf("readiness load: %w", err)
	}
	slots, err := frozenSlots(commandBytes)
	if err != nil {
		return ReadinessRequest{}, err
	}
	out.Slots = slots
	if len(frames) > 0 {
		if err := json.Unmarshal(frames, &out.Frames); err != nil {
			return ReadinessRequest{}, fmt.Errorf("%w: observation_frames 损坏: %v", ErrReadinessInvalid, err)
		}
	}
	if out.Frames == nil {
		out.Frames = map[string]ReadinessFrame{}
	}
	out.Verdict = verdict
	if digest != nil {
		out.Digest = *digest
	}
	return out, nil
}

// ObservationApplied 说明这次观测是新增还是原样重投。
type ObservationApplied struct {
	SlotID   string
	Digest   string
	Replayed bool
}

// RecordObservationTx 登记一个 slot 的观测。每 slot 只接受一份原 payload：
// 同摘要重投返回原记录，异摘要拒绝。signed verdict 落地后不再接受新观测。
func RecordObservationTx(ctx context.Context, tx pgx.Tx, requestID, slotID string, payloadBytes []byte) (ObservationApplied, error) {
	if slotID == "" || len(payloadBytes) == 0 {
		return ObservationApplied{}, fmt.Errorf("%w: slot 与 payload 必须有值", ErrReadinessInvalid)
	}
	var frames []byte
	var verdict []byte
	if err := tx.QueryRow(ctx, `
		SELECT observation_frames, verdict_bytes FROM cr_execution_policy_readiness
		WHERE request_id = $1::uuid FOR UPDATE`, requestID).Scan(&frames, &verdict); err != nil {
		return ObservationApplied{}, fmt.Errorf("readiness observation lock: %w", err)
	}
	if len(verdict) > 0 {
		// 结果已签，观测窗口关闭。
		return ObservationApplied{}, fmt.Errorf("%w: signed result 已落地，不再接受观测", ErrReadinessConflict)
	}
	request, err := LoadReadinessRequestTx(ctx, tx, requestID)
	if err != nil {
		return ObservationApplied{}, err
	}
	member := false
	for _, slot := range request.Slots {
		if slot.ID == slotID {
			member = true
			break
		}
	}
	if !member {
		return ObservationApplied{}, fmt.Errorf("%w: slot %s 不属于该 request", ErrReadinessInvalid, slotID)
	}
	sum := sha256.Sum256(payloadBytes)
	digestHex := hex.EncodeToString(sum[:])
	if existing, ok := request.Frames[slotID]; ok {
		if existing.Digest == digestHex {
			return ObservationApplied{SlotID: slotID, Digest: digestHex, Replayed: true}, nil
		}
		return ObservationApplied{}, fmt.Errorf("%w: slot %s 已登记另一份观测", ErrReadinessConflict, slotID)
	}
	request.Frames[slotID] = ReadinessFrame{Digest: digestHex, Bytes: base64.StdEncoding.EncodeToString(payloadBytes)}
	encoded, err := json.Marshal(request.Frames)
	if err != nil {
		return ObservationApplied{}, fmt.Errorf("readiness frames encode: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE cr_execution_policy_readiness SET observation_frames = $2::jsonb
		WHERE request_id = $1::uuid`, requestID, encoded); err != nil {
		return ObservationApplied{}, fmt.Errorf("readiness observation write: %w", err)
	}
	return ObservationApplied{SlotID: slotID, Digest: digestHex}, nil
}

// ReadinessApplied 是 signed result 的落点。
type ReadinessApplied struct {
	RequestID string
	Digest    string
	Replayed  bool
}

// RecordReadinessTx 写最终 signed verdict。只写一次；原字节重投返回原摘要。
func RecordReadinessTx(ctx context.Context, tx pgx.Tx, requestID string, verdictBytes []byte) (ReadinessApplied, error) {
	if len(verdictBytes) == 0 {
		return ReadinessApplied{}, fmt.Errorf("%w: verdict 不能为空", ErrReadinessInvalid)
	}
	var frames []byte
	var stored []byte
	if err := tx.QueryRow(ctx, `
		SELECT observation_frames, verdict_bytes FROM cr_execution_policy_readiness
		WHERE request_id = $1::uuid FOR UPDATE`, requestID).Scan(&frames, &stored); err != nil {
		return ReadinessApplied{}, fmt.Errorf("readiness verdict lock: %w", err)
	}
	sum := sha256.Sum256(verdictBytes)
	digestHex := hex.EncodeToString(sum[:])
	if len(stored) > 0 {
		if string(stored) == string(verdictBytes) {
			return ReadinessApplied{RequestID: requestID, Digest: digestHex, Replayed: true}, nil
		}
		return ReadinessApplied{}, fmt.Errorf("%w: signed result 已落地且不可改", ErrReadinessConflict)
	}
	request, err := LoadReadinessRequestTx(ctx, tx, requestID)
	if err != nil {
		return ReadinessApplied{}, err
	}
	for _, slot := range request.Slots {
		if _, ok := request.Frames[slot.ID]; !ok {
			return ReadinessApplied{}, fmt.Errorf("%w: slot %s 还没有观测", ErrReadinessIncomplete, slot.ID)
		}
	}
	if _, err := tx.Exec(ctx, `
		UPDATE cr_execution_policy_readiness SET verdict_bytes = $2, digest = $3
		WHERE request_id = $1::uuid`, requestID, verdictBytes, digestHex); err != nil {
		return ReadinessApplied{}, fmt.Errorf("readiness verdict write: %w", err)
	}
	return ReadinessApplied{RequestID: requestID, Digest: digestHex}, nil
}
