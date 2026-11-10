# terminal callback generation fencing — read-only facts

- at: 2026-10-25T05:26:46Z
- scope: terminalTaskReport → reportTerminalTask/sendTerminalTaskReport → Client.FailTask/CompleteTask → handler /fail//complete → TaskService → SQL; plus prepare/start-claim seam and existing test seams
- constraints: read-only source inspection. No DB, container, test run, product/source/test/fixture edit. Not a TC pass, not authorization, not a claim the whole chain is fixed.
- request config context: balanced Gobao/deepseek-flash/max (configured schema1), actual unknown.

## 1. Verdict

**Confirmed fencing gap at the terminal callback boundary.** Complete/fail requests carry only the task ID (plus payload/session metadata). They carry neither `runtime_id` nor `dispatched_at` generation, and the SQL CAS is status-only. A delayed stale delivery can match a newer claim of the **same task row** and terminalize it.

Qualifications checked against actual code:

1. The specific `StartTask` stale-claim error (`errStartClaimRejected`) is **not** sent as a terminal callback today: `handleTask` discards it explicitly (daemon.go 5885-5889). That exact path is safe.
2. The real pre-ack window remains: failures in `prepareClaimedPipelineTask` or in `runTask` **before** the `StartTask` call follow `handleTask`'s taskID-only fail (daemon.go 5780-5788 and pre-8631 returns). Those paths have not learned the claim generation; a stale delivery failing there can kill a newer claim.
3. `GetTaskExecutionClaim` (execution_task_claim.go 23-86) validates exact generation but has **no non-test caller** today. If wired into prepare and its error is allowed to fall through, the suspected path becomes real unless the callback is also generation-aware.

## 2. Actual chain and predicates

### Daemon report value

- `type terminalTaskReport struct` — daemon.go:258-279. Fields: kind, taskID, output, branchName, errorMessage, sessionID, workDir, durableWorkDir, failureReason, sessionRolloutMissing, retiredSessionID, recovery. **No runtimeID / dispatchedAt.**
- `reportTerminalTask` — daemon.go:6457; dedupe via `beginTerminalReportDelivery(report.taskID)` — daemon.go:6508; keyed by **taskID only**.
- `sendTerminalTaskReport` — daemon.go:6533-6545 — dispatches to `client.completeTaskWithRetrySchedule` / `client.failTaskWithRetrySchedule` with only report fields.

### Client HTTP body

- `Client.CompleteTask` — client.go:649; `completeTaskWithRetrySchedule` — client.go:653.
  Body from client.go:654: `{"output": ...}` plus optional branch_name/session_id/work_dir/durable_work_dir/session_rollout_missing/retired_session_id. **No runtime_id / dispatched_at.** Path `/api/daemon/tasks/{taskID}/complete`.
- `Client.FailTask` — client.go:685; `failTaskWithRetrySchedule` — client.go:689.
  Body from client.go:690: `{"error": ...}` plus same optional fields. **No runtime_id / dispatched_at.** Path `/api/daemon/tasks/{taskID}/fail`.
- Contrast: `Client.StartTask` — client.go:508 — sends `runtime_id` and `dispatched_at` (client.go:543-547) when `StartClaimSupported`.

### Handler and access check

- `Handler.CompleteTask` — handler/daemon.go:4758; `Handler.FailTask` — handler/daemon.go:5549; shared `failTask` — handler/daemon.go:5576.
- Neither request struct parses a claim generation.
- `requireDaemonTaskAccessWithWorkspace` — handler/daemon.go:127-176 — checks task existence and workspace authorization only; no runtime_id/dispatched_at comparison.
- `StartTask` is the only endpoint parsing `runtime_id` + `dispatched_at` — handler/daemon.go:4531-4585; calls `StartTaskForClaim` at 4577.

### Service and SQL CAS

- `StartTaskForClaim` — service/task.go:4637; `LockAgentTaskStartClaim` — service/task.go:4659.
  SQL agent.sql:1196-1202: `WHERE id=$1 AND runtime_id=$2 AND dispatched_at=$3 AND status IN ('dispatched','waiting_local_directory','running') FOR UPDATE`. The only generation-aware row lock on this path.
- `CompleteTaskWithTransition` — service/task.go:5134; `qtx.CompleteAgentTask` — 5156.
  SQL agent.sql:1221-1243: `UPDATE ... SET status='completed' ... WHERE id=$1 AND status='running'`. **No runtime_id / dispatched_at.**
- `FailTaskWithTransition` — service/task.go:5584; `qtx.FailAgentTask` — 5659.
  SQL agent.sql:1374-1403: `UPDATE ... SET status='failed' ... WHERE id=$1 AND status IN ('dispatched','running','waiting_local_directory')`. **No runtime_id / dispatched_at.**
- Consequence: a stale callback against a newer claim sees status dispatched/running and updates it. The no-row replay path cannot distinguish "already terminal" from "newer generation" because generation never reaches the service/SQL.

### Reclaim is the same row, with new dispatched_at

- `ReclaimStaleDispatchedTaskForRuntime` — agent.sql:994-1032; batch variant 1039-1087. Both `UPDATE agent_task_queue SET dispatched_at = now(), ... WHERE id = (SELECT ... same row ...)`.
- Task ID is stable across generations; `dispatched_at` is the generation token. Only StartTask checks it; terminal callbacks do not.

## 3. Prepare/start seam — what is and is not mitigated

- `handleTask` — daemon.go:5737.
- `prepareClaimedPipelineTask` failure — daemon.go:5780-5788 — sends `reportTerminalTask{kind=fail, taskID=task.ID, ...}` before any StartTask. Definition execution_verifier.go:23-49; can fail on binding/trust/static preflight before StartTask.
- Then `runner.run` → `runTask` — daemon.go:7900+.
- `runTask` performs substantial preparation before its first `StartTask` at daemon.go:8631-8634. Early returns before that include 7913, 7917, 7924, 8054, 8093, 8114, 8291, 8435-8462, 8592; none carries the claim generation, and each becomes a taskID-only fail in `handleTask`.
- Safe case: StartTask's stale error is wrapped at 8634 but `errors.Is(err, errStartClaimRejected)` still matches; `handleTask` returns at 5885-5889 without callback. So the exact StartTask-stale path is not the bug.
- New `GetTaskExecutionClaim` — execution_task_claim.go:23-86 — checks workspace/project/task/runtime and exact canonical `dispatched_at`, returns `EXECUTION_TASK_CLAIM_UNAVAILABLE` (line 20) on mismatch. No non-test caller today. Wiring it into prepare without guarding the fallthrough would create the suspected failure mode.

## 4. Hidden maps/outbox do not fence generations

- `terminalReportFlight` — daemon.go:6508-6528 — keyed by taskID only; serializes/dedupes per task, not per generation.
- Durable outbox — terminal_report_queue.go: record version 2 at line 22; struct at 47; no runtime_id/dispatched_at; `terminalReportFileName(taskID)` at 136 hashes taskID only; `enqueue` at 362; conflict rejection at 384; completion-failure fallback at ~823-840 also taskID-only.
- These are crash-replay/dedupe features. A stale persisted fail can replay after a newer claim unless generation is in the record and request.

## 5. Minimal fix plan (legacy preserved)

1. Add `runtimeID`, `dispatchedAt` to `terminalTaskReport`; set from `Task` on every new-claim report. Persist with version bump (v3); keep v1/v2 decodable with empty generation = legacy.
2. Add optional `runtime_id` / `dispatched_at` to complete/fail bodies (omitempty). New daemon sends both when `StartClaimSupported`; legacy/old server gets byte-identical old body. Handler rejects one-without-the-other.
3. Add new queries `CompleteAgentTaskForClaim` / `FailAgentTaskForClaim` with `AND runtime_id=$n AND dispatched_at=$m` on the existing id/status predicate; keep old queries for legacy. (Nullable-parameter widening is also possible, but separate queries keep old plans/tests intact.)
4. New-claim read/prepare failure must not emit taskID-only callback: if generation is required but unavailable (`EXECUTION_TASK_CLAIM_UNAVAILABLE`), return without `reportTerminalTask`; let server lease/reclaim recover. Legacy claims (`StartClaimSupported=false`) keep current callback.
5. Stale generation CAS returns zero rows: treat as idempotent no-op success, but run post-update side effects (chat outcome, retry child, token revoke, notifications) only when a row actually updated. FailTask retry insert is inside the tx after CAS.
6. Persist generation in outbox and compare before send; v2 records with empty generation stay legacy taskID-only. Complete→fail compensation and failed-queue replay must carry the same generation.
7. Do not change `LockAgentTaskStartClaim`, legacy `{}` start bodies, or old terminal bodies.

## 6. Suggested public tests

- handler (DB fixture): `TestTerminalCallbackStaleGenerationDoesNotFinalizeNewClaim` — same task row, gen1 dispatched; POST `/fail` with gen1 while row is gen2 running; assert 200/no-op and row still gen2 running; then gen2 succeeds. Repeat for `/complete`.
- service/SQL: `TestFailAgentTaskGenerationCAS` / `TestCompleteAgentTaskGenerationCAS` — wrong generation leaves status/result/error and retry-child count unchanged; right generation transitions once.
- daemon: `TestHandleTaskRejectedStartClaimSendsNoTerminalReport` using `terminalReportSend` seam; assert zero sends for `errStartClaimRejected`.
- daemon (after fix): `TestHandleTaskPreStartPrepareFailureOnStaleClaimSendsNoCallback` — claim generation known, prepare fails before StartTask; assert no taskID-only fail; legacy claim still sends old callback.
- compatibility: `TestTerminalCallbackLegacyBodyUnchanged` — `StartClaimSupported=false` body omits runtime_id/dispatched_at and still finalizes; v2 terminal record decodes/replays.
- existing seams: `StartClaimSupported` (client.go:508-549), `daemon.terminalReportSend` (daemon.go:6533), `daemon_start_claim_test.go:62` `TestStartClaimReclaimedGeneration`, terminal_report_queue_test.go.
- Current coverage: StartTask stale generation is covered; terminal complete/fail generation is not.

## 7. Non-claims

- No DB/container/test run; no product/source/test/fixture/plan/ledger/approval modified.
- Fact/fix-proposal only. Does not pass a TC, close a major, authorize Gate 3, commit/push/release or any admission.
