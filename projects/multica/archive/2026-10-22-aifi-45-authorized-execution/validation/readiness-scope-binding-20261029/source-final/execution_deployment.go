// AIFIRST: trusted T committed verdict channel — D7 activation and stop-new (M003, S8 R3).
//
// T 决定 ready，M 只决定能否原子启用。这里不重写版本/能力求值：
// 它只核对身份、绑定、不可变性、当前 generation、有效期与 CAS。
package governance

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	// ErrDeploymentStale 是签名之后 deployment 变了代：旧 verdict 不再适用。
	ErrDeploymentStale = errors.New("EXECUTION_DEPLOYMENT_STALE")
	// ErrDeploymentNotReady 是该 verdict 不能用于这次动作。
	ErrDeploymentNotReady = errors.New("EXECUTION_DEPLOYMENT_NOT_READY")
	// ErrDeploymentConflict 是 CAS 或一次性约束冲突。
	ErrDeploymentConflict = errors.New("EXECUTION_DEPLOYMENT_CONFLICT")
	// ErrDeploymentInvalid 是输入不成立。
	ErrDeploymentInvalid = errors.New("EXECUTION_DEPLOYMENT_INVALID")
)

// ActivationModes 是 activation event 的闭集。
const (
	ActivationModeActive  = "ACTIVE"
	ActivationModeStopNew = "STOP_NEW"
)

// readinessVerdict 只取做效力检查所需的字段；其余留给 T。
type readinessVerdict struct {
	Schema               string `json:"schema"`
	Action               string `json:"action"`
	ProfilePurpose       string `json:"profile_purpose"`
	TargetPolicyDigest   string `json:"target_policy_digest"`
	TemplateDigest       string `json:"template_digest"`
	ProfileDigest        string `json:"profile_digest"`
	DeploymentGeneration int64  `json:"deployment_generation"`
	Ready                bool   `json:"ready"`
	Code                 string `json:"code"`
	ExpiresAt            int64  `json:"expires_at"`
}

// ActivationRef 是一次 activation 事件的定位。
type ActivationRef struct {
	Scope      string
	Target     string
	Revision   int64
	EventID    string
	Mode       string
	Generation int64
	CutoffSeq  int64
}

// ActivateInput 是启用的入参。
type ActivateInput struct {
	Scope              string
	TargetPolicy       string
	RequestID          string
	ExpectedGeneration int64
	TargetPolicyDigest string
	TemplateDigest     string
	ProfileDigest      string
	Actor              string
	Now                time.Time
}

// signedReadinessTx reads a readiness result within the expected scope.
// It does not verify the signature or bind the action and generation.
func signedReadinessTx(ctx context.Context, tx pgx.Tx, scope, requestID string) (readinessVerdict, time.Time, error) {
	var verdictBytes []byte
	var expiry time.Time
	if err := tx.QueryRow(ctx, `
		SELECT verdict_bytes, expiry FROM cr_execution_policy_readiness
		WHERE request_id = $1::uuid AND scope = $2 FOR UPDATE`, requestID, scope).Scan(&verdictBytes, &expiry); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return readinessVerdict{}, time.Time{}, fmt.Errorf("%w: 没有该 request", ErrDeploymentNotReady)
		}
		return readinessVerdict{}, time.Time{}, fmt.Errorf("activation readiness: %w", err)
	}
	if len(verdictBytes) == 0 {
		return readinessVerdict{}, time.Time{}, fmt.Errorf("%w: request 还没有 signed result", ErrDeploymentNotReady)
	}
	var verdict readinessVerdict
	if err := json.Unmarshal(verdictBytes, &verdict); err != nil {
		return readinessVerdict{}, time.Time{}, fmt.Errorf("%w: verdict 不是合法 JSON: %v", ErrDeploymentInvalid, err)
	}
	return verdict, expiry, nil
}

// deploymentHeadTx 锁住该 scope 的 deployment head。
func deploymentHeadTx(ctx context.Context, tx pgx.Tx, scope string) (generation, registry int64, state string, err error) {
	err = tx.QueryRow(ctx, `
		SELECT generation, registry_revision, state FROM cr_execution_deployment_head
		WHERE scope = $1 FOR UPDATE`, scope).Scan(&generation, &registry, &state)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, 0, "", fmt.Errorf("%w: scope %s 没有 deployment head", ErrDeploymentInvalid, scope)
	}
	if err != nil {
		return 0, 0, "", fmt.Errorf("activation head: %w", err)
	}
	return generation, registry, state, nil
}

// ActivatePolicyTx 用一份 READY_STRICT 的签名裁决原子启用 policy。
// 裁决的 generation 必须等于当前 head，且该裁决此前未被用于启用。
func ActivatePolicyTx(ctx context.Context, tx pgx.Tx, in ActivateInput) (ActivationRef, error) {
	if in.Scope == "" || in.TargetPolicy == "" || in.RequestID == "" {
		return ActivationRef{}, fmt.Errorf("%w: scope/target/request 必须有值", ErrDeploymentInvalid)
	}
	now := in.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}
	verdict, expiry, err := signedReadinessTx(ctx, tx, in.Scope, in.RequestID)
	if err != nil {
		return ActivationRef{}, err
	}
	// 只有 enable-policy × strict-production → READY_STRICT 能启用。
	if verdict.Action != "enable-policy" || verdict.ProfilePurpose != "strict-production" {
		return ActivationRef{}, fmt.Errorf("%w: %s × %s 不能启用", ErrDeploymentNotReady, verdict.Action, verdict.ProfilePurpose)
	}
	if !verdict.Ready || verdict.Code != ReadinessActions["enable-policy"] {
		return ActivationRef{}, fmt.Errorf("%w: code=%s ready=%v", ErrDeploymentNotReady, verdict.Code, verdict.Ready)
	}
	if in.TargetPolicyDigest != "" && verdict.TargetPolicyDigest != in.TargetPolicyDigest {
		return ActivationRef{}, fmt.Errorf("%w: 裁决绑定的 policy 摘要不是这次要启用的", ErrDeploymentNotReady)
	}
	if in.TemplateDigest != "" && verdict.TemplateDigest != in.TemplateDigest {
		return ActivationRef{}, fmt.Errorf("%w: template 摘要不符", ErrDeploymentNotReady)
	}
	if in.ProfileDigest != "" && verdict.ProfileDigest != in.ProfileDigest {
		return ActivationRef{}, fmt.Errorf("%w: profile 摘要不符", ErrDeploymentNotReady)
	}
	// 有效期以 DB 时间为准，不信任进程时钟。
	if now.After(expiry) {
		return ActivationRef{}, fmt.Errorf("%w: 裁决已过期", ErrDeploymentNotReady)
	}
	generation, _, _, err := deploymentHeadTx(ctx, tx, in.Scope)
	if err != nil {
		return ActivationRef{}, err
	}
	// 签名之后 deployment 变了代：这份 verdict 不再适用，不能拿旧代签名启用新代。
	if verdict.DeploymentGeneration != generation || (in.ExpectedGeneration > 0 && in.ExpectedGeneration != generation) {
		return ActivationRef{}, fmt.Errorf("%w: 裁决签于 generation %d，当前 %d", ErrDeploymentStale, verdict.DeploymentGeneration, generation)
	}
	// 同一份裁决只能启用一次（nonce/request 一次性）。
	var consumed int
	if err := tx.QueryRow(ctx, `
		SELECT count(*) FROM cr_execution_policy_activation_event
		WHERE scope = $1 AND target_policy = $2 AND verdict_ref = $3::uuid AND mode = 'ACTIVE'`,
		in.Scope, in.TargetPolicy, in.RequestID).Scan(&consumed); err != nil {
		return ActivationRef{}, fmt.Errorf("activation replay check: %w", err)
	}
	if consumed > 0 {
		return ActivationRef{}, fmt.Errorf("%w: 该裁决已用过，nonce 不能重放", ErrDeploymentConflict)
	}

	var revision int64
	var previousID *string
	err = tx.QueryRow(ctx, `
		SELECT revision, event_id::text FROM cr_execution_policy_activation_head
		WHERE scope = $1 AND target_policy = $2 FOR UPDATE`, in.Scope, in.TargetPolicy).Scan(&revision, &previousID)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		revision = 1
		previousID = nil
	case err != nil:
		return ActivationRef{}, fmt.Errorf("activation head lock: %w", err)
	default:
		revision++
	}
	eventID := ""
	if err := tx.QueryRow(ctx, `
		INSERT INTO cr_execution_policy_activation_event (
			id, scope, target_policy, previous_id, mode, generation, verdict_ref, actor, committed_at
		) VALUES (gen_random_uuid(), $1, $2, NULLIF($3,'')::uuid, $4, $5, $6::uuid, $7, $8)
		RETURNING id::text`,
		in.Scope, in.TargetPolicy, derefOrEmpty(previousID), ActivationModeActive,
		generation, in.RequestID, in.Actor, now).Scan(&eventID); err != nil {
		return ActivationRef{}, fmt.Errorf("activation event insert: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO cr_execution_policy_activation_head (scope, target_policy, revision, event_id, updated_at)
		VALUES ($1, $2, $3, $4::uuid, $5)
		ON CONFLICT (scope, target_policy)
		DO UPDATE SET revision = $3, event_id = $4::uuid, updated_at = $5`,
		in.Scope, in.TargetPolicy, revision, eventID, now); err != nil {
		return ActivationRef{}, fmt.Errorf("activation head write: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE cr_execution_deployment_head SET state = 'READY_STRICT', updated_at = $2 WHERE scope = $1`,
		in.Scope, now); err != nil {
		return ActivationRef{}, fmt.Errorf("deployment head state: %w", err)
	}
	return ActivationRef{
		Scope: in.Scope, Target: in.TargetPolicy, Revision: revision,
		EventID: eventID, Mode: ActivationModeActive, Generation: generation,
	}, nil
}

// StopNewAdmissionsTx 停新准入。不需要 READY：回退不该被「没有裁决」堵死。
// 它固化 cutoff，但不动 selection、不动消费、不动历史。
func StopNewAdmissionsTx(ctx context.Context, tx pgx.Tx, scope, targetPolicy, actor, reason string, now time.Time) (ActivationRef, error) {
	if scope == "" || targetPolicy == "" {
		return ActivationRef{}, fmt.Errorf("%w: scope/target 必须有值", ErrDeploymentInvalid)
	}
	if now.IsZero() {
		now = time.Now().UTC()
	}
	var revision, cutoff int64
	var previousID string
	err := tx.QueryRow(ctx, `
		SELECT revision, event_id::text, last_issued_admission_seq
		FROM cr_execution_policy_activation_head
		WHERE scope = $1 AND target_policy = $2 FOR UPDATE`, scope, targetPolicy).Scan(&revision, &previousID, &cutoff)
	if errors.Is(err, pgx.ErrNoRows) {
		return ActivationRef{}, fmt.Errorf("%w: 没有可停用的 activation", ErrDeploymentInvalid)
	}
	if err != nil {
		return ActivationRef{}, fmt.Errorf("stop new lock: %w", err)
	}
	revision++
	eventID := ""
	if err := tx.QueryRow(ctx, `
		INSERT INTO cr_execution_policy_activation_event (
			id, scope, target_policy, previous_id, mode, generation, actor, reason, cutoff_admission_seq, committed_at
		) VALUES (gen_random_uuid(), $1, $2, $3::uuid, $4,
		          (SELECT generation FROM cr_execution_policy_activation_event WHERE id = $3::uuid),
		          $5, $6, $7, $8)
		RETURNING id::text`,
		scope, targetPolicy, previousID, ActivationModeStopNew, actor, reason, cutoff, now).Scan(&eventID); err != nil {
		return ActivationRef{}, fmt.Errorf("stop new event insert: %w", err)
	}
	// cutoff 与 head 同锁写死；admission 计数不清零、不回退。
	if _, err := tx.Exec(ctx, `
		UPDATE cr_execution_policy_activation_head
		SET revision = $3, event_id = $4::uuid, updated_at = $5
		WHERE scope = $1 AND target_policy = $2`, scope, targetPolicy, revision, eventID, now); err != nil {
		return ActivationRef{}, fmt.Errorf("stop new head write: %w", err)
	}
	return ActivationRef{
		Scope: scope, Target: targetPolicy, Revision: revision,
		EventID: eventID, Mode: ActivationModeStopNew, CutoffSeq: cutoff,
	}, nil
}

// IssuedAdmission 是一次 created→issued 的结果。
type IssuedAdmission struct {
	AdmissionSeq     int64
	AdmissionEventID string
	IssuedAt         time.Time
	ExpiresAt        time.Time
}

// IssueAdmissionTx 在 activation 锁内签发 admission seq。
// 只有当前事件为 ACTIVE 且未过期才允许；STOP_NEW 之后一律拒绝新签发。
func IssueAdmissionTx(ctx context.Context, tx pgx.Tx, scope, targetPolicy string, now time.Time) (IssuedAdmission, error) {
	if scope == "" || targetPolicy == "" {
		return IssuedAdmission{}, fmt.Errorf("%w: scope/target 必须有值", ErrDeploymentInvalid)
	}
	var revision, seq int64
	var eventID string
	if err := tx.QueryRow(ctx, `
		SELECT revision, event_id::text, last_issued_admission_seq
		FROM cr_execution_policy_activation_head
		WHERE scope = $1 AND target_policy = $2 FOR UPDATE`, scope, targetPolicy).
		Scan(&revision, &eventID, &seq); err != nil {
		return IssuedAdmission{}, fmt.Errorf("%w: 没有 activation head", ErrDeploymentNotReady)
	}
	var mode string
	var verdictRef *string
	if err := tx.QueryRow(ctx, `
		SELECT mode, verdict_ref::text FROM cr_execution_policy_activation_event WHERE id = $1::uuid`,
		eventID).Scan(&mode, &verdictRef); err != nil {
		return IssuedAdmission{}, fmt.Errorf("issue admission event: %w", err)
	}
	if mode != ActivationModeActive || verdictRef == nil {
		return IssuedAdmission{}, fmt.Errorf("%w: 当前不是 ACTIVE", ErrDeploymentNotReady)
	}
	_, expiry, err := signedReadinessTx(ctx, tx, scope, *verdictRef)
	if err != nil {
		return IssuedAdmission{}, err
	}
	if now.IsZero() {
		now = time.Now().UTC()
	}
	if now.After(expiry) {
		return IssuedAdmission{}, fmt.Errorf("%w: activation 已过期", ErrDeploymentNotReady)
	}
	seq++
	if _, err := tx.Exec(ctx, `
		UPDATE cr_execution_policy_activation_head
		SET last_issued_admission_seq = $3, updated_at = $4
		WHERE scope = $1 AND target_policy = $2`, scope, targetPolicy, seq, now); err != nil {
		return IssuedAdmission{}, fmt.Errorf("issue admission write: %w", err)
	}
	return IssuedAdmission{AdmissionSeq: seq, AdmissionEventID: eventID, IssuedAt: now, ExpiresAt: expiry}, nil
}

func derefOrEmpty(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

// LegacyWorkset 是退役前必须收敛的旧接力工作集快照。
// 它是「仍有资格处理该 scope 的旧入口/未决结果」的实测值，不是声明值。
type LegacyWorkset struct {
	LiveRuns       int
	UnknownPending int
	WorksetDigest  string
}

// DrainResult 是一次进入 DRAINING 的结果。
type DrainResult struct {
	Scope        string
	WorkRevision int64
	Workset      LegacyWorkset
}

// BeginLegacyDrainTx 在 deployment 锁内把 legacy_gate 置 DRAINING。
// 只要还有活的旧 run 或无法核实的未决结果，就不许进入 drain ——
// 先证明收敛，再谈退役。
func BeginLegacyDrainTx(ctx context.Context, tx pgx.Tx, scope string, workset LegacyWorkset, expectedGeneration int64, now time.Time) (DrainResult, error) {
	if scope == "" || workset.WorksetDigest == "" {
		return DrainResult{}, fmt.Errorf("%w: scope 与 workset digest 必须有值", ErrDeploymentInvalid)
	}
	if now.IsZero() {
		now = time.Now().UTC()
	}
	generation, _, _, err := deploymentHeadTx(ctx, tx, scope)
	if err != nil {
		return DrainResult{}, err
	}
	if expectedGeneration > 0 && expectedGeneration != generation {
		return DrainResult{}, fmt.Errorf("%w: 观测时的 generation %d 已不是当前 %d", ErrDeploymentStale, expectedGeneration, generation)
	}
	if workset.LiveRuns > 0 {
		return DrainResult{}, fmt.Errorf("%w: 还有 %d 个存活的旧 run", ErrDeploymentNotReady, workset.LiveRuns)
	}
	if workset.UnknownPending > 0 {
		return DrainResult{}, fmt.Errorf("%w: 有 %d 个无法核实的未决结果", ErrDeploymentNotReady, workset.UnknownPending)
	}
	var revision int64
	if err := tx.QueryRow(ctx, `
		UPDATE cr_execution_deployment_head
		SET legacy_gate = 'DRAINING', registry_revision = registry_revision + 1, updated_at = $2
		WHERE scope = $1
		RETURNING legacy_work_revision`, scope, now).Scan(&revision); err != nil {
		return DrainResult{}, fmt.Errorf("legacy drain: %w", err)
	}
	return DrainResult{Scope: scope, WorkRevision: revision, Workset: workset}, nil
}

// BumpLegacyWorkTx 在旧 run/未决集变化时递增 legacy_work_revision。
// 任何纳管 writer 都必须调用；漏调的后果是退役看到一个过时的空集。
func BumpLegacyWorkTx(ctx context.Context, tx pgx.Tx, scope string, now time.Time) (int64, error) {
	var revision int64
	if err := tx.QueryRow(ctx, `
		UPDATE cr_execution_deployment_head
		SET legacy_work_revision = legacy_work_revision + 1, updated_at = $2
		WHERE scope = $1
		RETURNING legacy_work_revision`, scope, now).Scan(&revision); err != nil {
		return 0, fmt.Errorf("legacy work bump: %w", err)
	}
	return revision, nil
}

// FinalizeLegacyRetirementTx 把 DRAINING 收成 RETIRED。
// 必须 CAS：仍是 DRAINING、work revision 未漂移、generation/snapshot 未变、retirement verdict 有效。
func FinalizeLegacyRetirementTx(ctx context.Context, tx pgx.Tx, scope, requestID, worksetDigest string, expectedWorkRevision, expectedGeneration int64, now time.Time) (ActivationRef, error) {
	if scope == "" || requestID == "" || worksetDigest == "" {
		return ActivationRef{}, fmt.Errorf("%w: scope/request/workset digest 必须有值", ErrDeploymentInvalid)
	}
	if now.IsZero() {
		now = time.Now().UTC()
	}
	// 一次加锁就把需要核对的全部事实取齐：重复加同一行会让阻塞点变得难以定位。
	var generation, revision int64
	var gate string
	if err := tx.QueryRow(ctx, `
		SELECT legacy_gate, legacy_work_revision, generation FROM cr_execution_deployment_head
		WHERE scope = $1 FOR UPDATE`, scope).Scan(&gate, &revision, &generation); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ActivationRef{}, fmt.Errorf("%w: scope %s 没有 deployment head", ErrDeploymentInvalid, scope)
		}
		return ActivationRef{}, fmt.Errorf("legacy retirement read: %w", err)
	}
	if gate != "DRAINING" {
		return ActivationRef{}, fmt.Errorf("%w: gate 是 %s，不是 DRAINING", ErrDeploymentConflict, gate)
	}
	if expectedWorkRevision != revision {
		return ActivationRef{}, fmt.Errorf("%w: 观测后旧工作 revision 从 %d 漂到 %d", ErrDeploymentStale, expectedWorkRevision, revision)
	}
	if expectedGeneration > 0 && expectedGeneration != generation {
		return ActivationRef{}, fmt.Errorf("%w: generation 漂移", ErrDeploymentStale)
	}
	verdict, expiry, err := signedReadinessTx(ctx, tx, scope, requestID)
	if err != nil {
		return ActivationRef{}, err
	}
	// 退役只能由 retire-legacy-relay × strict-production 的 READY_TO_RETIRE 兑现。
	if verdict.Action != "retire-legacy-relay" || verdict.ProfilePurpose != "strict-production" {
		return ActivationRef{}, fmt.Errorf("%w: %s × %s 不能退役", ErrDeploymentNotReady, verdict.Action, verdict.ProfilePurpose)
	}
	if !verdict.Ready || verdict.Code != ReadinessActions["retire-legacy-relay"] {
		return ActivationRef{}, fmt.Errorf("%w: code=%s", ErrDeploymentNotReady, verdict.Code)
	}
	if now.After(expiry) {
		return ActivationRef{}, fmt.Errorf("%w: 退役裁决已过期", ErrDeploymentNotReady)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE cr_execution_deployment_head SET legacy_gate = 'RETIRED', updated_at = $2
		WHERE scope = $1`, scope, now); err != nil {
		return ActivationRef{}, fmt.Errorf("legacy retire: %w", err)
	}
	return ActivationRef{
		Scope: scope, Mode: "RETIRED", Generation: generation, CutoffSeq: revision,
	}, nil
}

// Access 闭集。
const (
	AccessNewAdmission  = "NewAdmission"
	AccessExactRecovery = "ExactRecovery"
	AccessAuditOnly     = "AuditOnly"
	AccessDenied        = "Denied"
)

// DeploymentAccessInput 由服务端路由 op + DB 原事实解析，不信 caller 自称的 is_recovery。
type DeploymentAccessInput struct {
	Scope        string
	TargetPolicy string
	Op           string
	RequestID    string
	AdmissionSeq int64
	IssuedAt     time.Time

	PersistedOriginRef  string
	OriginRef           string
	PersistedDigest     string
	Digest              string
	PersistedGeneration int64
	Generation          int64
	Now                 time.Time
}

// denyOps 是 STOP_NEW/过期之后一律拒绝的动作。
var denyOps = map[string]bool{
	"new_admission": true, "new_selection": true, "command_issue": true,
	"new_candidate": true, "new_effect": true,
}

// auditOps 是只允许收集/补证据、不产生新业务 request 的动作。
var auditOps = map[string]bool{
	"checkpoint_ingest": true, "verdict_ingest": true, "original_bytes_query": true,
	"no_effect_settlement": true, "resume_intent": true,
}

// CheckDeploymentAccessTx 决定一个 op 在当前的 deployment/activation 状态下算什么。
func CheckDeploymentAccessTx(ctx context.Context, tx pgx.Tx, in DeploymentAccessInput) (string, error) {
	if in.Scope == "" || in.TargetPolicy == "" || in.Op == "" {
		return "", fmt.Errorf("%w: scope/target/op 必须有值", ErrDeploymentInvalid)
	}
	now := in.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}
	var revision, cutoff int64
	var eventID string
	err := tx.QueryRow(ctx, `
		SELECT revision, event_id::text, last_issued_admission_seq
		FROM cr_execution_policy_activation_head
		WHERE scope = $1 AND target_policy = $2`, in.Scope, in.TargetPolicy).Scan(&revision, &eventID, &cutoff)
	if errors.Is(err, pgx.ErrNoRows) {
		// 没有 activation 就没有准入；审计类仍可读。
		if auditOps[in.Op] {
			return AccessAuditOnly, nil
		}
		return AccessDenied, nil
	}
	if err != nil {
		return "", fmt.Errorf("deployment access head: %w", err)
	}
	var mode string
	var verdictRef *string
	if err := tx.QueryRow(ctx, `
		SELECT mode, verdict_ref::text FROM cr_execution_policy_activation_event WHERE id = $1::uuid`,
		eventID).Scan(&mode, &verdictRef); err != nil {
		return "", fmt.Errorf("deployment access event: %w", err)
	}
	if mode != ActivationModeActive && mode != ActivationModeStopNew {
		return AccessDenied, nil
	}
	expired := false
	var expiresAt time.Time
	if verdictRef != nil {
		_, expiresAt, err = signedReadinessTx(ctx, tx, in.Scope, *verdictRef)
		if err != nil {
			return "", err
		}
		expired = now.After(expiresAt)
	} else {
		expired = true
	}
	if mode == ActivationModeActive && !expired {
		if auditOps[in.Op] {
			return AccessAuditOnly, nil
		}
		if denyOps[in.Op] || in.Op == "complete_unsettled_request" || in.Op == "bind_existing_mapping" {
			return AccessNewAdmission, nil
		}
		return AccessDenied, nil
	}
	if denyOps[in.Op] {
		return AccessDenied, nil
	}
	// 以下都是 STOP_NEW 或已过期：只允许「原 request 的精确恢复」。
	if auditOps[in.Op] {
		return AccessAuditOnly, nil
	}
	if in.AdmissionSeq <= 0 || in.AdmissionSeq > cutoff {
		// created 未 issued（或晚于 cutoff）不在例外内。
		return AccessDenied, nil
	}
	if in.IssuedAt.IsZero() || (!expiresAt.IsZero() && in.IssuedAt.After(expiresAt)) {
		return AccessDenied, nil
	}
	switch in.Op {
	case "complete_unsettled_request", "bind_existing_mapping":
		// 恢复须逐字段相等：换 origin、换摘要、换 generation 都不是恢复。
		if in.PersistedOriginRef == "" || in.PersistedDigest == "" ||
			in.PersistedOriginRef != in.OriginRef || in.PersistedDigest != in.Digest {
			return AccessDenied, nil
		}
		if in.PersistedGeneration <= 0 || in.Generation <= 0 || in.PersistedGeneration != in.Generation {
			return AccessDenied, nil
		}
		return AccessExactRecovery, nil
	default:
		return AccessDenied, nil
	}
}
