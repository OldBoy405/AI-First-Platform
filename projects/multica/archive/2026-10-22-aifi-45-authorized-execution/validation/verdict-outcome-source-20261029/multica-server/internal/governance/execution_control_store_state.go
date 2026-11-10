// AIFIRST: trusted T committed verdict channel — control store state machine (M003, S3).
//
// 这一层只做四件事，顺序都是契约的一部分：
//  1. One record per request: replay verifies against the supplied trust inputs and requires
//     identical immutable fields; trusted historical replay policy remains unresolved.
//  2. 每条 lineage 同时只有一个 open request：结算才释放槽位，`uncertain` 不放（未知结果必须占位）;
//  3. 帧链按 cursor 走：seq 连续、prev_digest 指向上一条的 digest，占位签名一律拒;
//  4. 撤销/停止按 seq 线性化：只挡住它之后的 command，不回撤已经发生的事实。
//
// 触发器已经保证行不可改、不可删；这里负责「允许写什么」。
package governance

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

var (
	ErrControlStoreInvalid  = errors.New("EXECUTION_CONTROL_STORE_INVALID")
	ErrControlStoreConflict = errors.New("EXECUTION_CONTROL_STORE_CONFLICT")
)

const (
	controlCommandCreated         = "created"
	controlCommandIssued          = "issued"
	controlCommandResultReady     = "result_ready"
	controlCommandSettledEffect   = "settled_effect"
	controlCommandSettledNoEffect = "settled_no_effect"
	controlCommandUncertain       = "uncertain"

	controlOperationCommand = "command"
	controlOperationRevoke  = "revoke"
	controlOperationStop    = "stop"
)

var controlOpenStates = []string{controlCommandCreated, controlCommandIssued, controlCommandResultReady, controlCommandUncertain}

type ControlCommandInput struct {
	RequestID      string
	Scope          string
	LineageID      string
	ReservationID  string
	OwnerFence     int64
	EffectiveFence int64
	Seq            int64
	PrevDigest     string
	CommandBytes   []byte
	Envelope       []byte
	Operation      string
	Now            time.Time
	// The caller must obtain the manifest and expected scope from a trusted source.
	Manifest         *ControlTrustManifest
	AttestationScope ControlScope
}

type ControlCommandApplied struct {
	CommandID string
	State     string
	Replayed  bool
}

// verifyControlCommand checks the signature and the subset of the signed subject represented
// by this writer's columns. It does not establish the complete B from authoritative records;
// production callers must resolve that identity and the trust root independently.
func verifyControlCommand(in ControlCommandInput) error {
	if in.AttestationScope["lineage_id"] != in.LineageID {
		return fmt.Errorf("%w: command attestation is not bound to the lineage", ErrControlStoreInvalid)
	}
	verified, err := VerifyControlEnvelope(in.Envelope, "command", ControlCommandDomain, in.AttestationScope, in.Manifest, in.Now)
	if err != nil {
		return fmt.Errorf("%w: command verification: %w", ErrControlStoreInvalid, err)
	}
	if !bytes.Equal(verified.PayloadBytes, in.CommandBytes) {
		return fmt.Errorf("%w: stored command differs from signed bytes", ErrControlStoreInvalid)
	}
	operation, ok := rawString(verified.Payload, "operation")
	if !ok {
		return fmt.Errorf("%w: command operation missing", ErrControlStoreInvalid)
	}
	switch operation {
	case "execution-consume", "repair-admit", "repair-outcome", "repair-assess", "repair-resume", "sensitive-consume", "evidence-delivery":
	default:
		return fmt.Errorf("%w: unknown command operation", ErrControlStoreInvalid)
	}
	requestID, ok := rawString(verified.Payload, "request_id")
	if !ok || requestID != in.RequestID {
		return fmt.Errorf("%w: command request mismatch", ErrControlStoreInvalid)
	}
	seq, ok := rawInt(verified.Payload, "expected_seq")
	if !ok || seq != in.Seq {
		return fmt.Errorf("%w: command sequence mismatch", ErrControlStoreInvalid)
	}
	var prev *string
	rawPrev, ok := verified.Payload["previous_verdict_digest"]
	if !ok || json.Unmarshal(rawPrev, &prev) != nil || prev == nil || *prev != in.PrevDigest {
		return fmt.Errorf("%w: command predecessor mismatch", ErrControlStoreInvalid)
	}
	var binding map[string]json.RawMessage
	if err := json.Unmarshal(verified.Payload["B"], &binding); err != nil || binding == nil {
		return fmt.Errorf("%w: command binding missing", ErrControlStoreInvalid)
	}
	lineage, ok := rawString(binding, "lineage_id")
	if !ok || lineage != in.LineageID {
		return fmt.Errorf("%w: command lineage mismatch", ErrControlStoreInvalid)
	}
	fence, ok := rawInt(binding, "owner_fence")
	if !ok || fence != in.OwnerFence {
		return fmt.Errorf("%w: command owner fence mismatch", ErrControlStoreInvalid)
	}
	var candidate map[string]json.RawMessage
	if err := json.Unmarshal(binding["candidate"], &candidate); err != nil || candidate == nil {
		return fmt.Errorf("%w: command candidate missing", ErrControlStoreInvalid)
	}
	reservation, ok := rawString(candidate, "reservation_id")
	if !ok || reservation != in.ReservationID {
		return fmt.Errorf("%w: command reservation mismatch", ErrControlStoreInvalid)
	}
	return nil
}

// lockControlLineage serializes command insertion and policy events that share a lineage.
// All participants must acquire it before inspecting stop events or inserting a new event.
func lockControlLineage(ctx context.Context, tx pgx.Tx, lineageID string) error {
	// A snapshot fixed before waiting could miss the policy event that held the lock.
	var isolation string
	if err := tx.QueryRow(ctx, `SHOW transaction_isolation`).Scan(&isolation); err != nil {
		return fmt.Errorf("control transaction isolation: %w", err)
	}
	if isolation != "read committed" {
		return fmt.Errorf("%w: control writer requires read committed isolation", ErrControlStoreInvalid)
	}
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended('aifi45-control:' || ($1::uuid)::text, 0))`, lineageID); err != nil {
		return fmt.Errorf("control lineage lock: %w", err)
	}
	return nil
}

// ApplyControlCommandTx 追加一条 command，或在同一 request 重放时返回原记录。
func ApplyControlCommandTx(ctx context.Context, tx pgx.Tx, in ControlCommandInput) (ControlCommandApplied, error) {
	if in.RequestID == "" || in.LineageID == "" || in.Scope == "" || in.ReservationID == "" {
		return ControlCommandApplied{}, fmt.Errorf("%w: request/scope/lineage/reservation 必须有值", ErrControlStoreInvalid)
	}
	if in.Seq <= 0 || in.OwnerFence <= 0 || in.EffectiveFence <= 0 {
		return ControlCommandApplied{}, fmt.Errorf("%w: seq 与 fence 必须为正", ErrControlStoreInvalid)
	}
	if in.Operation != controlOperationCommand {
		return ControlCommandApplied{}, fmt.Errorf("%w: 该入口只接受 command", ErrControlStoreInvalid)
	}
	if err := verifyControlCommand(in); err != nil {
		return ControlCommandApplied{}, err
	}
	if err := lockControlLineage(ctx, tx, in.LineageID); err != nil {
		return ControlCommandApplied{}, err
	}

	var storedState string
	var same bool
	err := tx.QueryRow(ctx, `SELECT state,
		scope=$2 AND lineage_id=$3::uuid AND reservation_id=$4::uuid AND owner_fence=$5
		AND seq=$6 AND COALESCE(prev_digest,'')=$7 AND command_bytes=$8 AND envelope=$9::jsonb
		FROM cr_execution_control_command WHERE request_id=$1::uuid`,
		in.RequestID, in.Scope, in.LineageID, in.ReservationID, in.OwnerFence,
		in.Seq, in.PrevDigest, in.CommandBytes, in.Envelope).Scan(&storedState, &same)
	switch {
	case err == nil:
		if !same {
			return ControlCommandApplied{}, fmt.Errorf("%w: command replay differs from the committed record", ErrControlStoreConflict)
		}
		return ControlCommandApplied{CommandID: in.RequestID, State: storedState, Replayed: true}, nil
	case !errors.Is(err, pgx.ErrNoRows):
		return ControlCommandApplied{}, fmt.Errorf("control command replay lookup: %w", err)
	}

	// 撤销/停止只挡它之后的 command；已经发生的事实不回撤。
	if err := controlAssertNoEarlierStop(ctx, tx, in.LineageID, in.Seq); err != nil {
		return ControlCommandApplied{}, err
	}

	var open int
	if err := tx.QueryRow(ctx, `
		SELECT count(*) FROM cr_execution_control_command
		WHERE lineage_id = $1::uuid AND state = ANY($2)`, in.LineageID, controlOpenStates).Scan(&open); err != nil {
		return ControlCommandApplied{}, fmt.Errorf("control command open slot: %w", err)
	}
	if open > 0 {
		return ControlCommandApplied{}, fmt.Errorf("%w: 该 lineage 已有未结算的 command", ErrControlStoreConflict)
	}

	// Waiting for the lineage lock may outlive the signing key's validity.
	current := in
	current.Now = time.Now().UTC()
	if err := verifyControlCommand(current); err != nil {
		return ControlCommandApplied{}, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO cr_execution_control_command (
			request_id, scope, lineage_id, reservation_id, owner_fence, effective_fence,
			seq, prev_digest, command_bytes, envelope, state, created_at
		) VALUES ($1::uuid, $2, $3::uuid, $4::uuid, $5, $6, $7, NULLIF($8, ''), $9, $10::jsonb, $11, COALESCE($12::timestamptz, now()))`,
		in.RequestID, in.Scope, in.LineageID, in.ReservationID, in.OwnerFence, in.EffectiveFence,
		in.Seq, in.PrevDigest, in.CommandBytes, in.Envelope, controlCommandCreated, nilIfZeroTime(in.Now)); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "cr_execution_control_command_pkey" {
			return ControlCommandApplied{}, fmt.Errorf("%w: request already exists: %w", ErrControlStoreConflict, err)
		}
		return ControlCommandApplied{}, fmt.Errorf("control command insert: %w", err)
	}
	return ControlCommandApplied{CommandID: in.RequestID, State: controlCommandCreated}, nil
}

// controlAssertNoEarlierStop 读「撤销/停止」事实。它们存放在同一命令表里，用 `admission_event_ref`
// 之外的字段不可表达，所以这里以 state=settled_no_effect + 专门的 operation 记录判定。
func controlAssertNoEarlierStop(ctx context.Context, tx pgx.Tx, lineageID string, seq int64) error {
	var kind string
	err := tx.QueryRow(ctx, `
		SELECT COALESCE(e->>'operation', '')
		FROM cr_execution_control_command c
		LEFT JOIN LATERAL (SELECT c.envelope->'payload' AS e) AS p ON true
		WHERE c.lineage_id = $1::uuid AND c.seq < $2 AND c.state = 'settled_no_effect'
		  AND e->>'operation' IN ('revoke', 'stop')
		ORDER BY c.seq DESC
		LIMIT 1`, lineageID, seq).Scan(&kind)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("control command stop ordering: %w", err)
	}
	if kind == controlOperationRevoke {
		return fmt.Errorf("%w: 该 lineage 在此 seq 之前已撤销", ErrControlStoreConflict)
	}
	if kind == controlOperationStop {
		return fmt.Errorf("%w: 该 lineage 在此 seq 之前已停止", ErrControlStoreConflict)
	}
	return nil
}

// ApplyControlPolicyEventTx 记录一次撤销或停止。它立刻是终态（不占 open 槽），
// 但只对之后的 seq 生效。
func ApplyControlPolicyEventTx(ctx context.Context, tx pgx.Tx, in ControlCommandInput) (ControlCommandApplied, error) {
	if in.Operation != controlOperationRevoke && in.Operation != controlOperationStop {
		return ControlCommandApplied{}, fmt.Errorf("%w: 只接受 revoke/stop", ErrControlStoreInvalid)
	}
	if in.RequestID == "" || in.LineageID == "" || in.Seq <= 0 {
		return ControlCommandApplied{}, fmt.Errorf("%w: request/lineage/seq 必须有值", ErrControlStoreInvalid)
	}
	if err := lockControlLineage(ctx, tx, in.LineageID); err != nil {
		return ControlCommandApplied{}, err
	}
	envelope, err := json.Marshal(map[string]any{
		"payload": map[string]string{"operation": in.Operation},
	})
	if err != nil {
		return ControlCommandApplied{}, err
	}
	// 策略事件没有「命令字节」，但列是 NOT NULL：用它自己冻结后的 envelope 作为不可变记录，
	// 而不是塞空数组——空的记录以后没法证明当初发生过什么。
	commandBytes := in.CommandBytes
	if len(commandBytes) == 0 {
		commandBytes = envelope
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO cr_execution_control_command (
			request_id, scope, lineage_id, reservation_id, owner_fence, effective_fence,
			seq, prev_digest, command_bytes, envelope, state, verdict_id, created_at
		) VALUES ($1::uuid, $2, $3::uuid, $4::uuid, $5, $6, $7, NULLIF($8, ''), $9, $10::jsonb,
		          'settled_no_effect', $11::uuid, COALESCE($12::timestamptz, now()))`,
		in.RequestID, in.Scope, in.LineageID, in.ReservationID, in.OwnerFence, in.EffectiveFence,
		in.Seq, in.PrevDigest, commandBytes, envelope, in.ReservationID, nilIfZeroTime(in.Now)); err != nil {
		return ControlCommandApplied{}, fmt.Errorf("control policy event insert: %w", err)
	}
	return ControlCommandApplied{CommandID: in.RequestID, State: controlCommandSettledNoEffect}, nil
}

// TransitionControlCommandTx 只允许文档化的转换；`admission` 只记一次。
func TransitionControlCommandTx(ctx context.Context, tx pgx.Tx, requestID, from, to, verdictID, admissionEventRef string, admissionSeq int64) error {
	allowed := map[string]map[string]bool{
		controlCommandCreated:         {controlCommandIssued: true, controlCommandSettledNoEffect: true, controlCommandUncertain: true},
		controlCommandIssued:          {controlCommandResultReady: true, controlCommandUncertain: true},
		controlCommandResultReady:     {controlCommandSettledEffect: true, controlCommandSettledNoEffect: true, controlCommandUncertain: true},
		controlCommandSettledEffect:   {controlCommandUncertain: true},
		controlCommandSettledNoEffect: {},
		controlCommandUncertain:       {},
	}
	if !allowed[from][to] {
		return fmt.Errorf("%w: 不允许的转换 %s -> %s", ErrControlStoreInvalid, from, to)
	}
	needsVerdict := to == controlCommandSettledEffect || to == controlCommandSettledNoEffect
	tag, err := tx.Exec(ctx, `
		UPDATE cr_execution_control_command
		SET state = $3,
		    verdict_id = CASE WHEN $4::uuid IS NULL THEN verdict_id ELSE $4::uuid END,
		    admission_event_ref = CASE WHEN $5::uuid IS NULL THEN admission_event_ref ELSE $5::uuid END,
		    admission_seq = CASE WHEN $6::bigint IS NULL THEN admission_seq ELSE $6::bigint END,
		    issued_at = CASE WHEN $3 = 'issued' THEN COALESCE(issued_at, now()) ELSE issued_at END
		WHERE request_id = $1::uuid AND state = $2`,
		requestID, from, to, nullableString(verdictID), nullableString(admissionEventRef),
		nullableInt64(admissionSeq))
	if err != nil {
		return fmt.Errorf("control command transition: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("%w: command %s 不在状态 %s", ErrControlStoreConflict, requestID, from)
	}
	if needsVerdict && verdictID == "" {
		return fmt.Errorf("%w: 结算必须有 verdict", ErrControlStoreInvalid)
	}
	return nil
}

type VerdictFrameInput struct {
	VerdictID    string
	Scope        string
	LineageID    string
	RequestID    string
	StoreID      string
	Epoch        int64
	Seq          int64
	PrevDigest   string
	PayloadBytes []byte
	Envelope     []byte
	CommitRef    string
	ReceiptRef   string
	Now          time.Time
	// Manifest and AttestationScope are what the envelope is verified against. A nil
	// manifest refuses the frame: an attestation that cannot be verified is not a verdict.
	Manifest         *ControlTrustManifest
	AttestationScope ControlScope
}

type VerdictFrameApplied struct {
	VerdictID string
	Digest    string
	Replayed  bool
}

// verifyVerdictAttestation is what lets a verdict row be read as "T committed": the envelope
// verifies against the trust manifest as a verdict, it is scoped to the chain the frame lands
// on, and the stored payload is exactly the signed bytes. Checking only that a signature field
// is present would let a well-shaped envelope carrying any bytes become an admission fact.
//
// The scope binding is checked here rather than left to the caller because the caller is not
// trusted to pick it: a correctly signed verdict for another lineage verifies on its own
// terms, and only the writer knows which chain it is about to extend.
func verifyVerdictAttestation(in VerdictFrameInput) error {
	if in.AttestationScope["store_id"] != in.StoreID || in.AttestationScope["lineage_id"] != in.LineageID {
		return fmt.Errorf("%w: attestation scope 未绑定本帧所在的 store/lineage", ErrControlStoreInvalid)
	}
	verified, err := VerifyControlEnvelope(in.Envelope, "verdict", VerdictDomain, in.AttestationScope, in.Manifest, in.Now)
	if err != nil {
		return fmt.Errorf("%w: verdict 验签失败: %w", ErrControlStoreInvalid, err)
	}
	if !bytes.Equal(verified.PayloadBytes, in.PayloadBytes) {
		return fmt.Errorf("%w: 入链 payload 不是被签名的字节", ErrControlStoreInvalid)
	}
	if err := verifyVerdictSubject(verified, in); err != nil {
		return err
	}
	return nil
}

// verifyVerdictSubject binds the signed subject to the frame it lands as.
//
// The three checks above authenticate the bytes and the chain the frame extends, but the
// writer still takes RequestID, epoch and seq from its own inputs. Without this binding a
// correctly signed verdict can be relabelled: a payload signed as being about one request can
// be stored as the trusted commit for a different one, at a different position, with no forged
// signature and no direct table write. That is precisely the row the admission decider credits
// to a consumption (v.request_id = s.request_id = cc.task_id), so the trust would rest on a
// column the caller chose rather than on the signature. The signer must name the frame.
func verifyVerdictSubject(verified ControlVerification, in VerdictFrameInput) error {
	requestID, ok := rawString(verified.Payload, "request_id")
	if !ok || requestID != in.RequestID {
		return fmt.Errorf("%w: 被签名的 request 与入链 request 不一致", ErrControlStoreInvalid)
	}
	epoch, ok := rawInt(verified.Payload, "epoch")
	if !ok || epoch != in.Epoch {
		return fmt.Errorf("%w: 被签名的 epoch 与入链 epoch 不一致", ErrControlStoreInvalid)
	}
	seq, ok := rawInt(verified.Payload, "sequence")
	if !ok || seq != in.Seq {
		return fmt.Errorf("%w: 被签名的 seq 与入链 seq 不一致", ErrControlStoreInvalid)
	}
	var prev *string
	raw, ok := verified.Payload["previous_verdict_digest"]
	if !ok || json.Unmarshal(raw, &prev) != nil || prev == nil || *prev != in.PrevDigest {
		return fmt.Errorf("%w: signed prev_digest does not match the frame", ErrControlStoreInvalid)
	}
	return nil
}

// AppendVerdictFrameTx 追加一帧：先验签（见 verifyVerdictAttestation 与 verifyVerdictSubject），
// 再要求 seq 连续、prev 指向上一条 digest。它是 cr_execution_tool_verdict 唯一的生产写入者，
// The signed previous_verdict_digest must bind the stored frame's prev_digest.
func AppendVerdictFrameTx(ctx context.Context, tx pgx.Tx, in VerdictFrameInput) (VerdictFrameApplied, error) {
	if in.VerdictID == "" || in.LineageID == "" || in.StoreID == "" || in.RequestID == "" {
		return VerdictFrameApplied{}, fmt.Errorf("%w: 帧缺少 id/lineage/store/request", ErrControlStoreInvalid)
	}
	if in.Epoch <= 0 || in.Seq <= 0 {
		return VerdictFrameApplied{}, fmt.Errorf("%w: epoch 与 seq 必须为正", ErrControlStoreInvalid)
	}
	if err := verifyVerdictAttestation(in); err != nil {
		return VerdictFrameApplied{}, err
	}
	digest := sha256.Sum256(in.PayloadBytes)
	digestHex := hex.EncodeToString(digest[:])

	lookupReplay := func() (VerdictFrameApplied, bool, error) {
		var storedID, storedDigest string
		var exact bool
		err := tx.QueryRow(ctx, `
			SELECT id::text, digest,
			       id = $2::uuid AND scope = $3 AND lineage_id = $4::uuid
			       AND store_id = $5 AND epoch = $6 AND seq = $7
			       AND COALESCE(prev_digest, '') = $8 AND payload_bytes = $9
			       AND envelope = $10::jsonb AND digest = $11 AND commit_ref = $12
			       AND COALESCE(receipt_ref, '') = $13
			FROM cr_execution_tool_verdict WHERE request_id = $1::uuid`,
			in.RequestID, in.VerdictID, in.Scope, in.LineageID, in.StoreID, in.Epoch, in.Seq,
			in.PrevDigest, in.PayloadBytes, in.Envelope, digestHex, in.CommitRef, in.ReceiptRef,
		).Scan(&storedID, &storedDigest, &exact)
		if errors.Is(err, pgx.ErrNoRows) {
			return VerdictFrameApplied{}, false, nil
		}
		if err != nil {
			return VerdictFrameApplied{}, false, fmt.Errorf("verdict replay lookup: %w", err)
		}
		if !exact {
			return VerdictFrameApplied{}, true, fmt.Errorf("%w: verdict replay differs from committed frame", ErrControlStoreConflict)
		}
		return VerdictFrameApplied{VerdictID: storedID, Digest: storedDigest, Replayed: true}, true, nil
	}
	if result, found, err := lookupReplay(); found || err != nil {
		return result, err
	}

	var lastSeq int64
	var lastDigest *string
	if err := tx.QueryRow(ctx, `
		SELECT last_seq, last_digest FROM cr_execution_tool_cursor
		WHERE lineage_id = $1::uuid AND store_id = $2 AND epoch = $3 FOR UPDATE`,
		in.LineageID, in.StoreID, in.Epoch).Scan(&lastSeq, &lastDigest); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return VerdictFrameApplied{}, fmt.Errorf("%w: cursor 不存在", ErrControlStoreInvalid)
		}
		return VerdictFrameApplied{}, fmt.Errorf("verdict cursor: %w", err)
	}
	// Another writer may have committed the same request while this transaction waited.
	if result, found, err := lookupReplay(); found || err != nil {
		return result, err
	}
	expectedPrev := ""
	if lastDigest != nil {
		expectedPrev = *lastDigest
	}
	if in.Seq != lastSeq+1 {
		return VerdictFrameApplied{}, fmt.Errorf("%w: 帧 seq %d 不是 cursor 的下一格 %d", ErrControlStoreInvalid, in.Seq, lastSeq+1)
	}
	if in.PrevDigest != expectedPrev {
		return VerdictFrameApplied{}, fmt.Errorf("%w: prev_digest 不是链上最后一条", ErrControlStoreInvalid)
	}

	// Recheck new frames against the server clock after waiting for the cursor lock.
	current := in
	current.Now = time.Now().UTC()
	if err := verifyVerdictAttestation(current); err != nil {
		return VerdictFrameApplied{}, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO cr_execution_tool_verdict (
			id, scope, lineage_id, request_id, store_id, epoch, seq, prev_digest,
			payload_bytes, envelope, digest, commit_ref, receipt_ref, created_at
		) VALUES ($1::uuid, $2, $3::uuid, $4::uuid, $5, $6, $7, NULLIF($8, ''),
		          $9, $10::jsonb, $11, $12, NULLIF($13, ''), COALESCE($14::timestamptz, now()))`,
		in.VerdictID, in.Scope, in.LineageID, in.RequestID, in.StoreID, in.Epoch, in.Seq,
		in.PrevDigest, in.PayloadBytes, in.Envelope, digestHex, in.CommitRef, in.ReceiptRef,
		nilIfZeroTime(in.Now)); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" && pgErr.ConstraintName == "cr_execution_tool_verdict_request_once" {
			return VerdictFrameApplied{}, fmt.Errorf("%w: request already exists: %w", ErrControlStoreConflict, err)
		}
		return VerdictFrameApplied{}, fmt.Errorf("verdict insert: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE cr_execution_tool_cursor
		SET last_seq = $4, last_digest = $5, open_request_id = NULL, updated_at = now()
		WHERE lineage_id = $1::uuid AND store_id = $2 AND epoch = $3`,
		in.LineageID, in.StoreID, in.Epoch, in.Seq, digestHex); err != nil {
		return VerdictFrameApplied{}, fmt.Errorf("verdict cursor update: %w", err)
	}
	return VerdictFrameApplied{VerdictID: in.VerdictID, Digest: digestHex}, nil
}

// OpenControlRequestTx 占用单 open 槽位；已有 open request 时冲突。
func OpenControlRequestTx(ctx context.Context, tx pgx.Tx, lineageID, storeID string, epoch int64, requestID string, fence int64) error {
	tag, err := tx.Exec(ctx, `
		UPDATE cr_execution_tool_cursor
		SET open_request_id = $4::uuid, owner_fence = $5, updated_at = now()
		WHERE lineage_id = $1::uuid AND store_id = $2 AND epoch = $3
		  AND open_request_id IS NULL`, lineageID, storeID, epoch, requestID, fence)
	if err != nil {
		return fmt.Errorf("control store open request: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("%w: 已有 open request 或 cursor 不存在", ErrControlStoreConflict)
	}
	return nil
}

func nilIfZeroTime(at time.Time) any {
	if at.IsZero() {
		return nil
	}
	return at
}

func nullableString(value string) any {
	if value == "" {
		return nil
	}
	return value
}

func nullableInt64(value int64) any {
	if value == 0 {
		return nil
	}
	return value
}
