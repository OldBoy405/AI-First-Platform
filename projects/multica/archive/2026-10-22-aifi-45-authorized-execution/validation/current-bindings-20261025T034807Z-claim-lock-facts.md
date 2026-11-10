# AIFI-45 claim/lock facts (read-only, 2026-10-25)

Source root: `C:/Users/GOBAO/Downloads/AI/multica`

## 1. `StartAgentTaskWithSupplement`

- Not in `pkg/db/queries/agent.sql`; exact definition is `pkg/db/queries/supplement.sql:1`.
- It is a sqlc-generated query method: `task.go:4665` calls `qtx.StartAgentTaskWithSupplement(ctx, db.StartAgentTaskWithSupplementParams{...})`, not a service function.
- SQL shape (`supplement.sql:1-34`): CTE `candidate` selects `agent_task_queue t JOIN agent_runtime r ON r.id = t.runtime_id WHERE t.id = @task_id AND t.status IN ('dispatched','waiting_local_directory') FOR UPDATE OF t`; then inserts `task_supplement_capability`; then `UPDATE agent_task_queue t SET status='running', started_at=now(), wait_reason=NULL, prepare_lease_expires_at=NULL FROM candidate WHERE t.id = candidate.id`.
- It locks only the target task row (`FOR UPDATE OF t`). It reads `agent_runtime` via join but names no `FOR UPDATE` on `agent_runtime` or `agent`, so there is no runtime/agent row-level lock in this query.

## 2. `ClaimTask` / `claimTask`

- `TaskService.ClaimTask` `internal/service/task.go:3871` -> `claimTask` `task.go:3880`.
- Agent row lock first: `qtx.GetAgentForClaimUpdate` (`task.go:3892`; query `agent.sql:1843-1846`: `SELECT * FROM agent WHERE id=$1 FOR UPDATE`).
- Then `qtx.ClaimAgentTask` (`task.go:3931`; query `agent.sql:854`): `UPDATE agent_task_queue SET status='dispatched', dispatched_at=now(), prepare_lease_expires_at=... WHERE id=(...)`; `runtime_id=@runtime_id` is only a WHERE/fence (`agent.sql:883`), not written.
- No `LockAgentRuntime` or `LockAgentRuntimeForAccessChange` call exists in either `ClaimTask` or `claimTask`; the only `LockAgentRuntime` call in `internal/service/task.go` is line 4650 inside `StartTaskForClaim`.
- Therefore this path holds the agent row then the task row, and does not subsequently lock the runtime row. `ClaimAgentTask` reads `agent`/`agent_runtime` in subqueries but does not lock them. Project-linked claims take `LockIssueDuplicateKey` (advisory key `claim-project|<id>`) after the task claim, not a runtime lock.

## 3. Real schema names (dump, read-only)

File: `validation/disposable-db-20261024T162608Z-balanced3-governance.schema.sql`

- FK: `agent_task_queue_runtime_id_fkey`; `agent_task_queue.runtime_id REFERENCES public.agent_runtime(id) ON DELETE CASCADE` (dump lines 8094-8098).
- CHECK: `agent_task_queue_active_requires_runtime`; `(runtime_id IS NOT NULL) OR (completed_at IS NOT NULL)` (dump line 4241).
- Trigger: `trg_atq_dirty_hourly`; `BEFORE DELETE OR UPDATE OF runtime_id, issue_id ON public.agent_task_queue FOR EACH ROW ... EXECUTE FUNCTION public.enqueue_task_usage_hourly_dirty_for_atq()` (dump line 7899; function at line 382). Observed function body inserts into `task_usage_hourly_dirty`; no `agent_runtime` row lock seen in the inspected slice.
- Other `agent_task_queue` triggers, not `runtime_id`-write related: `agent_task_comment_thread` (7808), `capture_task_wakeup` (7857), `trg_clear_runtime_mcp_overlay` (7906).
- Runtime-related indexes seen: `idx_agent_task_queue_claim_candidates`, `idx_agent_task_queue_deferred_fire`, `idx_agent_task_queue_dispatched_reclaim_v2`, `idx_agent_task_queue_runtime_id`, `idx_agent_task_queue_runtime_pending`.

## Limits

No DB/test execution, no security PASS, no deadlock or no-deadlock conclusion. Not inspected: full body/tail of `enqueue_task_usage_hourly_dirty_for_atq`, generated Go SQL source beyond symbols, and other claim wrappers such as `ClaimTaskForRuntime`/`ClaimTasksForRuntimes`.
