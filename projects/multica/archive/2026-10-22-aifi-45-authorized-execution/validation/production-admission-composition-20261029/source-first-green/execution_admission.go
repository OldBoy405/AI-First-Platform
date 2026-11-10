// AIFIRST: AIFI-45 (REQ-RUN-001, SC-RUN-003) — one admission decision per effect.
//
// Why this exists: the execution authorization chain issues, delivers and consumes a
// grant, but none of those facts is a dispatch permission. Before this, a wake caused by
// a delivery ACK reached the runner's own walker and the walker advanced the CR on
// whatever it found in approval_record — the new chain was never consulted, so a CR whose
// trusted consumption had not committed yet could still move.
//
// So the decision is deliberately narrow: it answers "may the runner advance this CR's
// actual state", re-reading its inputs in the caller's transaction, and it does nothing
// else. It does not enqueue, notify, commit or run a budget engine of its own.
//
// Two facts are required, both re-read here rather than trusted from the caller:
//
//  1. the CR's current authorization head is an approve record (a revoked head names the
//     revoke record, so it fails this check);
//  2. the CR has a committed consumption receipt (T wrote it after verifying the head).
//
// A CR with no head at all is refused rather than admitted: it is not on the new chain,
// and this decision only ever speaks for the new chain.
package governance

import (
	"context"
	"errors"
	"fmt"
	"reflect"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// ErrAdmissionInvalid marks a malformed decision request: a caller bug, not a refusal.
var ErrAdmissionInvalid = errors.New("EXECUTION_ADMISSION_REQUEST_INVALID")

// AdmissionIntent is the closed set of effects a decision can cover. It stays this small
// on purpose: only the effect this change actually consults is listed, and an unknown
// intent is refused rather than defaulted.
type AdmissionIntent string

const (
	// AdmissionAdvanceActualState asks whether the runner may move the CR to its next
	// state. It covers both halves of a step — marking a node passed and enqueueing its
	// successor — because the legacy walker writes "passed" before it enqueues, so a
	// gate placed at the enqueue would let the status change through unadmitted.
	AdmissionAdvanceActualState AdmissionIntent = "AdvanceActualState"

	// AdmissionReasonAdmitted means the caller may perform the effect.
	AdmissionReasonAdmitted = "ADMITTED"
	// AdmissionReasonWaitConsumption means the head approves but no consumption receipt
	// has committed for this CR yet: wake only, no advance.
	AdmissionReasonWaitConsumption = "WAIT_CONSUMPTION"
	// AdmissionReasonWaitTrustedT means the platform recorded a consumption but the trusted
	// store has not committed the verdict it belongs to. A consumption row on its own says
	// the daemon presented a valid proof; it does not say T committed the work, and the
	// difference is exactly what makes this a permission rather than a delivery fact.
	AdmissionReasonWaitTrustedT = "WAIT_TRUSTED_T_COMMIT"
	// AdmissionReasonHeadUnavailable means the CR carries no execution authorization head.
	AdmissionReasonHeadUnavailable = "HEAD_UNAVAILABLE"
	// AdmissionReasonHeadRejected means the current head is not an approve record.
	AdmissionReasonHeadRejected = "HEAD_REJECTED"
)

// AdmissionRequest names the CR whose advance is in question. It carries identifiers only:
// everything the decision depends on is re-read inside the caller's transaction, so these
// values cannot be used to talk the decider into a different subject.
type AdmissionRequest struct {
	WorkspaceID string
	CRID        string
	Intent      AdmissionIntent
}

// AdmissionDecision is the answer. Reason is a stable string so callers can branch and
// tests can assert it without parsing prose.
type AdmissionDecision struct {
	Allowed bool
	Reason  string
}

// AdmissionDecider is the single admission decision point. It must be called inside the
// transaction that performs the effect, and it never commits, notifies or enqueues.
type AdmissionDecider interface {
	DecideAdmission(context.Context, pgx.Tx, AdmissionRequest) (AdmissionDecision, error)
}

// ErrAdmissionDeciderRequired indicates a missing runner composition dependency.
var ErrAdmissionDeciderRequired = errors.New("EXECUTION_ADMISSION_DECIDER_REQUIRED")

// RequireAdmissionDecider rejects missing or typed-nil dependencies at composition.
// It does not verify the authority or behavior of a non-nil implementation.
func RequireAdmissionDecider(decider AdmissionDecider) error {
	if decider == nil {
		return ErrAdmissionDeciderRequired
	}
	value := reflect.ValueOf(decider)
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Map, reflect.Pointer, reflect.Slice:
		if value.IsNil() {
			return ErrAdmissionDeciderRequired
		}
	}
	return nil
}

// NewAdmissionDecider returns the production decision over the committed facts.
func NewAdmissionDecider() AdmissionDecider { return executionAdmissionDecider{} }

type executionAdmissionDecider struct{}

func (executionAdmissionDecider) DecideAdmission(ctx context.Context, tx pgx.Tx, req AdmissionRequest) (AdmissionDecision, error) {
	if tx == nil {
		return AdmissionDecision{}, fmt.Errorf("%w: no transaction", ErrAdmissionInvalid)
	}
	if req.Intent != AdmissionAdvanceActualState {
		return AdmissionDecision{}, fmt.Errorf("%w: intent %q", ErrAdmissionInvalid, req.Intent)
	}
	workspaceUUID, err := uuid.Parse(req.WorkspaceID)
	if err != nil {
		return AdmissionDecision{}, fmt.Errorf("%w: workspace id", ErrAdmissionInvalid)
	}
	if !executionCRPattern.MatchString(req.CRID) {
		return AdmissionDecision{}, fmt.Errorf("%w: cr id %q", ErrAdmissionInvalid, req.CRID)
	}

	// The head join is scoped to the same workspace and CR, so a pointer naming another
	// tenant's record looks like no head at all instead of borrowing its decision.
	var headDecision string
	var hasHead bool
	err = tx.QueryRow(ctx, `
		SELECT COALESCE(a.decision,''), a.id IS NOT NULL
		FROM cr c
		LEFT JOIN approval_record a ON a.id = c.execution_authorization_head_id
			AND a.workspace_id = c.workspace_id AND a.cr_id = c.cr_id
		WHERE c.workspace_id = $1::uuid AND c.cr_id = $2`, workspaceUUID, req.CRID).
		Scan(&headDecision, &hasHead)
	if errors.Is(err, pgx.ErrNoRows) {
		return AdmissionDecision{}, fmt.Errorf("%w: cr %s not found", ErrAdmissionInvalid, req.CRID)
	}
	if err != nil {
		return AdmissionDecision{}, err
	}
	if !hasHead {
		return AdmissionDecision{Reason: AdmissionReasonHeadUnavailable}, nil
	}
	if headDecision != "approve" {
		return AdmissionDecision{Reason: AdmissionReasonHeadRejected}, nil
	}

	// A consumption row alone is not a permission. It says the daemon presented a valid
	// binding proof for this task; it does not say T committed anything. The trusted store
	// commits a verdict (chained by store/epoch/prev_digest), the channel records the
	// settlement for the request, and the request id is the task the daemon consumed — so
	// all three links have to hold before this counts as a committed business consumption.
	//
	// ponytail: still counted per CR rather than pinned to one generation; naming the
	// generation (task/runtime/dispatched_at) is the RUN-006 resume work, which is the first
	// caller that has a generation to name.
	// The verdict must also be one its store's chain has advanced past: a row alone is a byte
	// blob, and a cursor that never reached its seq never accepted it.
	//
	// This deliberately does NOT compare the verdict's digest with the cursor's. The cursor
	// names the chain's TAIL, so once any later frame is appended the tail digest is no longer
	// this verdict's — comparing them withdraws admission from a consumption that is still
	// committed, and a legitimate walk stalls as soon as the store moves on.
	//
	// Verified here: the three rows name each other, and the store's cursor covers the
	// verdict's position. A premise, not a re-check: AppendVerdictFrameTx is the only
	// production writer of that table (one INSERT, execution_control_store_state.go) and it
	// refuses a frame whose seq is not cursor+1 or whose prev_digest is not the chain's last,
	// under the cursor it advances in the same transaction — so a row that exists did pass that
	// continuity check.
	//
	// Authenticity is verified at write time, not re-checked here. The same writer runs
	// verifyVerdictAttestation before inserting: the envelope must verify against the trust
	// manifest as a verdict, be scoped to the store/lineage it extends, and cover exactly the
	// stored payload bytes. So a row that exists was attested when it was written. What this
	// does not defend against is a party that can write the table directly — that is outside
	// the threat model, as it is for every other ledger here. Note also that the writer has no
	// production caller yet (ControlWorker.ApplyTx is unwired), so until verdict ingest is
	// wired a production decider would wait at WAIT_TRUSTED_T_COMMIT for every CR.
	var consumed, trusted int
	if err := tx.QueryRow(ctx, `
		SELECT count(*), count(*) FILTER (
			WHERE s.kind = 'effect' AND v.id IS NOT NULL AND c.last_seq >= v.seq)
		FROM cr_execution_consumption cc
		LEFT JOIN cr_execution_control_settlement s ON s.request_id = cc.task_id
		LEFT JOIN cr_execution_tool_verdict v ON v.id = s.verdict_id AND v.request_id = s.request_id
		LEFT JOIN cr_execution_tool_cursor c
			ON c.lineage_id = v.lineage_id AND c.store_id = v.store_id AND c.epoch = v.epoch
		WHERE cc.workspace_id = $1::uuid AND cc.cr_id = $2`, workspaceUUID, req.CRID).Scan(&consumed, &trusted); err != nil {
		return AdmissionDecision{}, err
	}
	if consumed == 0 {
		return AdmissionDecision{Reason: AdmissionReasonWaitConsumption}, nil
	}
	if trusted == 0 {
		return AdmissionDecision{Reason: AdmissionReasonWaitTrustedT}, nil
	}
	return AdmissionDecision{Allowed: true, Reason: AdmissionReasonAdmitted}, nil
}
