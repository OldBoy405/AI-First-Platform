# CompleteTaskWithTransition terminal-fence facts (read-only, 2026-10-25)

Source: `C:/Users/GOBAO/Downloads/AI/multica/server/internal/service/task.go`
Function: `CompleteTaskWithTransition` at `task.go:5134`; current transaction body ends around `:5229`, function returns at `:5356`.

## Actual work before `qtx.CompleteAgentTask`

1. `s.runInTx` opens the transaction (`task.go:5140`); `runInTx` is `task.go:7573-7585`.
2. `lockChatSessionForTaskWrite(ctx, qtx, taskID)` at `task.go:5141`:
   - calls `qtx.LockChatSessionForTask` (`pkg/db/queries/chat.sql:1632-1641`): `SELECT cs.id ... FOR UPDATE OF cs`.
   - locks the `chat_session` row, not the task row; `ErrNoRows` is deliberately swallowed when there is no chat session (`task.go:3452-3459`).
3. `qtx.GetAgentTask(ctx, taskID)` at `task.go:5148`:
   - query `agent.sql:813-815`: plain `SELECT * FROM agent_task_queue WHERE id = $1`.
   - no `FOR UPDATE`; this read grants no atomicity and does not fence the later CAS.
4. `persistMaturityReportCompletion` at `task.go:5152`:
   - only for canonical Org Admin maturity tasks; otherwise returns unchanged.
   - observed lock: `qtx.MaturityReportInboxExistsLocked` at `internal/service/maturity_completion.go:84`, whose SQL takes `pg_advisory_xact_lock` on `maturity-report-inbox:<report_key>` (`pkg/db/queries/maturity.sql:399-413`).
   - observed write: conditional `qtx.CreateInboxItem` at `maturity_completion.go:91` (`pkg/db/queries/inbox.sql:92-104`, `INSERT INTO inbox_item`).
   - no report-table write was observed in this helper.
5. Only then `qtx.CompleteAgentTask` at `task.go:5156`:
   - `agent.sql:1221-1243`: `UPDATE agent_task_queue SET status='completed', ... WHERE id=$1 AND status='running' RETURNING *`.
6. After the CAS, still in the same transaction: `SettleTerminalTaskState` (`task.go:5173`), chat-session pointer updates (`:5187`, `:5199`), and `writeChatCompletionOutcome` (around `:5217`).

## ErrNoRows and commit behavior

- Zero-row CAS returns `pgx.ErrNoRows` from `CompleteAgentTask`; the callback returns that error (`task.go:5166-5168`).
- `runInTx` returns the callback error **without calling `tx.Commit`**, and its deferred `tx.Rollback` runs (`task.go:7581-7584`). Therefore the pre-CAS chat-session lock/advisory lock/`CreateInboxItem` insert cannot commit on a zero-row CAS in the normal `TxStarter != nil` path.
- If `TxStarter == nil`, `runInTx` executes the callback directly without a transaction (`task.go:7574-7576`); there is no rollback guarantee. Production relies on the transactional path.
- After rollback, the outer error branch re-reads with `s.Queries.GetAgentTask` **outside** the transaction (`task.go:5231`) and, on `ErrNoRows`, logs “already finalized” and returns `&existing, false, nil` (`:5232-5238`). It does not currently require the existing status to be terminal.
- The `false` return skips the post-commit side effects; successful commit returns `true` only after capture/comment/chat-done/reconcile/broadcast side effects (`task.go:5260-5356`). The idempotent branch returns before those side effects.

## Minimal generation-fence landing point

- Put the optional generation predicate in the existing CAS itself, not in a new pre-CAS task lock:
  - add an optional `dispatched_at`/generation argument to `CompleteAgentTask` and `AND (sqlc.narg('dispatched_at')::timestamptz IS NULL OR dispatched_at = sqlc.narg('dispatched_at'))` in the existing `WHERE id=$1 AND status='running'` at `agent.sql:1242`.
  - keep the existing call position (`task.go:5156`) and existing `runInTx` rollback semantics. A zero-row stale generation then rolls back all pre-CAS writes.
- Do **not** insert `LockAgentTaskStartClaim` before `persistMaturityReportCompletion` as the default fix: that changes the current lock/order timing from chat-session lock → reads/advisory lock → task UPDATE to task lock before the maturity advisory/inbox work. It may be safe only after audit of Task/Chat/Runtime ordering; it is not the minimal no-order-change option.
- The outer `ErrNoRows` branch must be tightened for the fence: only return idempotent `false,nil` if the re-read status is terminal (`completed`/`failed`/`cancelled`). If it is still `running` (or another non-terminal state), a generation mismatch is a stale-claim error/conflict, not “already finalized”; returning `false,nil` would falsely acknowledge an old claim while a newer claim still runs.
- `GetAgentTask` must not be treated as an atomic fence; the CAS remains the atomic transition. Existing `LockAgentTaskStartClaim` can validate generation under `FOR UPDATE`, but using it as a pre-lock is the order-changing option, not the minimal CAS insertion.

## Residual

- Not inspected: `SettleTerminalTaskState` internals, full post-CAS side effects/callers, `FailTaskWithTransition`, daemon paths, sqlc generation. No DB/test execution or source changes.
