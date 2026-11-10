// AIFIRST: AIFI-45 (SC-RUN-003) — one admission decision per effect, under the head lock.
//
// This is the runner side of the admission boundary. Two of the effects that move a CR
// forward are gated here: marking a node passed, and enqueueing a node's executor task.
// Each takes its own decision, and each does it while holding the CR's authorization head
// lock, so the answer cannot go stale between the decision and the effect.
//
// Gated today: markNode(passed), passHumanApprovalNode (the three stage runners'
// human_approval writes), enqueueNodeFor, and enqueueRequirementNode's own dispatch.
//
// Still NOT gated, and this must stay written down:
//
//   - run completion (runner.go) and the ensure-writeback handoff, which create or close
//     work rather than pass a gate;
//   - settlement paths that finish without passing any gated effect at all — the
//     completion shortcut when the CR is already approved is the example.
//
// Those do not grant new execution authority, but they are the reason the gate proves only
// "this effect was not applied without admission", never "the CR did not advance".
//
// Why the lock and not a shared transaction: the enqueue goes through
// TaskService.EnqueuePipelineTask, which has no transaction-carrying entry point, so the
// decision and the INSERT cannot live in one transaction without changing the service
// layer. Holding `cr` FOR SHARE across the enqueue gives the property that actually
// matters instead — revocation's first lock is `cr` FOR UPDATE, so it waits here. Either
// the revoke commits first and this decision sees the revoked head, or the enqueue
// finishes first. That is linearisable against revocation; it is NOT one atomic step, and
// the ledger records it that way.
//
// The premise this rests on: NOTHING reached from here may write the `cr` row. The enqueue
// runs on its own pooled connection while this transaction holds the row, so a write to
// `cr` in that path would block on our own lock — an application-level deadlock Postgres
// cannot detect or break. Today's enqueue only reads `cr` (plain JOIN in
// CreatePipelineTask, no FOR UPDATE/FOR SHARE) and no trigger on agent_task_queue or
// pipeline_node_run writes `cr`.
package governance

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/multica-ai/multica/server/internal/util"
)

// admissionWaitReason is the runner detail a not-admitted effect leaves behind, so an
// operator sees "waiting for admission" instead of a node that silently stopped moving.
const admissionWaitReason = "admission"

// ExecutionAdmissionTestHook runs while the head lock is held and the decision has been
// taken, before the caller performs the effect. Nil outside tests. It exists so a lock
// probe can prove the window is really closed: the probe's conflicting statement comes
// from an independent connection, so it either blocks here or the lock was not taken.
var ExecutionAdmissionTestHook func()

// errAdmissionWaiting stops the walk. A wake that is merely waiting for a signature must
// not continue into the rest of the walk — the legacy walker treats "the effect was a
// no-op" as "the effect succeeded", so anything that reads nil as success would go on to
// the human gates, the handoff and run completion. It travels as an error only so that the
// existing `if err != nil { return err }` chains stop where they already stop; the public
// entry points turn it back into a nil result, because waiting is not a failure.
var errAdmissionWaiting = errors.New("EXECUTION_ADMISSION_WAITING")

// admissionSettled maps "waiting for admission" to a successful wake at the entry points.
func admissionSettled(err error) error {
	if errors.Is(err, errAdmissionWaiting) {
		return nil
	}
	return err
}

// decideUnderHeadLock takes the one decision for an effect while holding the CR's head
// lock. The returned transaction is non-nil only when the decision allowed the effect, and
// is then still open and still holding the lock: the caller performs exactly one effect
// and closes it. A refusal is returned as a nil transaction with the decision, already
// released — so "tx != nil" and "Allowed" cannot disagree, and a refused caller never
// holds a row lock while it writes its waiting annotation.
func (r *Runner) decideUnderHeadLock(ctx context.Context, workspaceID pgtype.UUID, crID string) (pgx.Tx, AdmissionDecision, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
	if err != nil {
		return nil, AdmissionDecision{}, err
	}
	if err := lockExecutionAuthorizationHead(ctx, tx, workspaceID, crID); err != nil {
		_ = tx.Rollback(ctx)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, AdmissionDecision{Reason: AdmissionReasonHeadUnavailable}, nil
		}
		return nil, AdmissionDecision{}, err
	}
	decision, err := r.decider.DecideAdmission(ctx, tx, AdmissionRequest{
		WorkspaceID: util.UUIDToString(workspaceID),
		CRID:        crID,
		Intent:      AdmissionAdvanceActualState,
	})
	if err != nil {
		_ = tx.Rollback(ctx)
		return nil, AdmissionDecision{}, err
	}
	// The transaction is released on every path that does not hand it out, including an
	// abnormal one: the hook below runs while this frame owns the transaction, so a Goexit
	// or panic inside it would otherwise leave the row lock held by nobody the caller can
	// see, and the next DELETE on the same row would block instead of reporting the failure.
	handed := false
	defer func() {
		if !handed {
			_ = tx.Rollback(context.Background())
		}
	}()
	if ExecutionAdmissionTestHook != nil {
		ExecutionAdmissionTestHook()
	}
	if !decision.Allowed {
		// Release before returning. A caller that is about to record why nothing moved
		// needs its own connection, and holding this one while acquiring another from the
		// same pool is how a wake with background context waits on itself.
		return nil, decision, nil
	}
	handed = true
	return tx, decision, nil
}

// markNodeAdmitted is markNode for the admitted path: the same statement, run in the
// transaction that took the decision, so the node cannot pass on an answer that stopped
// being true in between. A refusal writes the wait reason and passes no node.
func (r *Runner) markNodeAdmitted(ctx context.Context, runID pgtype.UUID, node coreNode, attempt int, status string) error {
	var workspaceID pgtype.UUID
	var crID string
	if err := r.pool.QueryRow(ctx, `SELECT workspace_id, cr_id FROM pipeline_run WHERE id=$1`, runID).Scan(&workspaceID, &crID); err != nil {
		return err
	}
	tx, decision, err := r.decideUnderHeadLock(ctx, workspaceID, crID)
	if err != nil {
		return err
	}
	if tx != nil {
		defer func() { _ = tx.Rollback(ctx) }()
	}
	if !decision.Allowed {
		return r.waitAdmission(ctx, runID, node, attempt, decision)
	}
	if _, err := tx.Exec(ctx, `UPDATE pipeline_node_run SET status=$4,completed_at=now(),detail=jsonb_set(COALESCE(detail,'{}'),'{runner}',COALESCE(detail->'runner','{}') - 'wait_reason',true) WHERE run_id=$1 AND node_id=$2 AND attempt=$3 AND status NOT IN ('failed','skipped')`,
		runID, node.ID, attempt, status); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// waitAdmission records why nothing moved. It writes runner detail on the node run — an
// annotation, never an advance.
//
// "Not an error" is a statement about the business meaning, not about the Go return value:
// this returns errAdmissionWaiting, which is non-nil, and every caller has to recognise it
// (errors.Is) rather than treat it as a reconcile failure. "Not admitted yet" is a normal
// wake outcome; reporting it as a failure would turn a pending authorization into a broken
// run. The write it does perform is that annotation — so a refusal is "no refused business
// effect, no new dispatch", never "nothing was written".
func (r *Runner) waitAdmission(ctx context.Context, runID pgtype.UUID, node coreNode, attempt int, decision AdmissionDecision) error {
	return r.waitAdmissionAt(ctx, `WHERE run_id=$1 AND node_id=$2 AND attempt=$3`, []any{runID, node.ID, attempt}, decision)
}

// waitAdmissionRow is the same annotation addressed by node run id, for the effects that
// hold that id rather than the (node, attempt) pair.
func (r *Runner) waitAdmissionRow(ctx context.Context, nodeRunID pgtype.UUID, decision AdmissionDecision) error {
	return r.waitAdmissionAt(ctx, `WHERE id=$1`, []any{nodeRunID}, decision)
}

func (r *Runner) waitAdmissionAt(ctx context.Context, where string, args []any, decision AdmissionDecision) error {
	raw, err := json.Marshal(map[string]any{"wait_reason": admissionWaitReason, "admission": decision.Reason})
	if err != nil {
		return err
	}
	query := `UPDATE pipeline_node_run SET detail=jsonb_set(COALESCE(detail,'{}'),'{runner}',$` + strconv.Itoa(len(args)+1) + `::jsonb,true) ` + where
	if _, err := r.pool.Exec(ctx, query, append(args, raw)...); err != nil {
		return err
	}
	return fmt.Errorf("%w: %s", errAdmissionWaiting, decision.Reason)
}

// passHumanApprovalNode settles a human_approval node. These nodes used to write
// `status='passed'` straight through the pool, which is a forward gate completion that
// never met the admission boundary: a human decision delivered while the trusted
// consumption had not committed still passed the gate. Now it takes the same decision,
// under the same lock, and the row count is returned because one caller distinguishes
// "already passed" from "just passed".
func (r *Runner) passHumanApprovalNode(ctx context.Context, runID, nodeRunID, approvalID pgtype.UUID) (int64, error) {
	const stmt = `UPDATE pipeline_node_run SET status='passed', completed_at=now(), approval_id=$2 WHERE id=$1 AND status IN ('pending','running','passed')`
	if r.decider == nil {
		tag, err := r.pool.Exec(ctx, stmt, nodeRunID, approvalID)
		if err != nil {
			return 0, err
		}
		return tag.RowsAffected(), nil
	}
	var workspaceID pgtype.UUID
	var crID string
	if err := r.pool.QueryRow(ctx, `SELECT workspace_id, cr_id FROM pipeline_run WHERE id=$1`, runID).Scan(&workspaceID, &crID); err != nil {
		return 0, err
	}
	tx, decision, err := r.decideUnderHeadLock(ctx, workspaceID, crID)
	if err != nil {
		return 0, err
	}
	if !decision.Allowed {
		return 0, r.waitAdmissionRow(ctx, nodeRunID, decision)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	tag, err := tx.Exec(ctx, stmt, nodeRunID, approvalID)
	if err != nil {
		return 0, err
	}
	if err := tx.Commit(ctx); err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}
