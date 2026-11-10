# FailTaskWithTransition retry-overlay facts (read-only, 2026-10-25)

Source: `C:/Users/GOBAO/Downloads/AI/multica/server`
Function: `TaskService.FailTaskWithTransition` at `internal/service/task.go:5601`.

## Call outline before the fail CAS

- `task.go:5653` `s.Queries.GetAgentTask(ctx, taskID)` — parent read only; no lock.
- `task.go:5666` `s.Queries.GetAgent(ctx, parent.AgentID)`.
- `task.go:5669` `retryOverlay = s.buildRuntimeMCPOverlay(ctx, parent.OriginatorUserID, agent)`.
  - This is executed **before** `s.runInTx` (`task.go:5676`) and only when `retryableReasons[failureReason]` and `retryEligible(...)` are true (`task.go:5652-5669`).
- `task.go:5680` `qtx.FailAgentTask(...)` is the fail CAS inside the transaction.
- `task.go:5818` `qtx.CreateRetryTask(...)` consumes `retryOverlay.Overlay` / `retryOverlay.ConnectedApps` (`task.go:5823-5824`).

## What the overlay builder actually does

`buildRuntimeMCPOverlay` (`internal/service/task.go:551-592`) is best-effort:

- nil `s.Composio` or feature flag off -> empty overlay, no call.
- calls `Composio.BuildTaskOverlay` (`task.go:561`); on any error logs and returns empty overlay, never fails the fail/retry transaction.
- `runtimeMCPOverlayData` carries overlay JSON plus connected-apps metadata; it has no Composio session ID.

`composio.Service.BuildTaskOverlay` (`internal/integrations/composio/dispatch.go:86-163`):

- Gate 1 `dispatch.go:89-92`: no agent owner -> no external call.
- Gate 2 `dispatch.go:94-99`: empty `composio_toolkit_allowlist` -> no external call.
- Gate 3 `dispatch.go:102-113`: `ListActiveUserComposioConnections` is a DB read; if the owner has no active connections intersecting the allowlist -> no external call.
- `dispatch.go:122-126`: calls `s.sdk.CreateSession(ctx, ...)`.
- `dispatch.go:128-132`: `MCP` URL empty -> no overlay.
- `dispatch.go:142`: `s.sdk.MCPAuthHeaders()` adds the Composio API-key header to the overlay; this helper itself performs no network call.
- `dispatch.go:144-163`: JSON marshal and connected-app metadata; marshal failure returns an error.

Downstream SDK call is not a GET and not config-only:

- `pkg/composio/sessions.go:78-86`: `CreateSession` validates `UserID`, then `c.do(..., http.MethodPost, "/tool_router/session", &out)`.
- `pkg/composio/client.go:153-164`: `do` executes the POST via resty; transport error or non-2xx returns an error.
- This **creates a real Composio tool-router session** and returns its MCP URL. `BuildTaskOverlay` keeps `resp.MCP.URL` but discards `resp.SessionID`; there is no delete/compensation in this path.
- Errors from `CreateSession` (network, non-2xx, empty URL) are swallowed by `buildRuntimeMCPOverlay` into an empty overlay; the fail still proceeds and the retry child is created without Composio.

## Why the current pre-CAS position is unsafe for strict terminal

- The external POST happens before `FailAgentTask`. A stale claim/generation that makes `FailAgentTask` return `pgx.ErrNoRows`, or any later DB error in the transaction, rolls back the DB but does **not** undo the already-created Composio session.
- `CreateRetryTask` can return `pgx.ErrNoRows` (no retry slot/workspace teardown) or a later transfer/copy can fail; the DB retry child is absent/rolled back while the external session remains orphaned.
- Conversely, moving the call after commit without a claimability gate lets the queued retry be claimed and run before its overlay is backfilled.

## Minimum safe placement

1. For strict terminal handling, do not call `buildRuntimeMCPOverlay` before the fail transaction commits. Build it only after `runInTx` succeeds and `retried != nil`.
2. The retry child must be created without the overlay inside the fail transaction, then backfilled after commit:
   - post-commit, call `buildRuntimeMCPOverlay` for the committed child's agent/originator;
   - persist the result to the child's `runtime_mcp_overlay` / `runtime_connected_apps`;
   - on build or backfill failure, log and leave the child without overlay (same best-effort contract as today), do not fail the parent.
3. A post-commit backfill alone is racy: the child is inserted `queued` and can be claimed before the update. Gate claimability until backfill completes. The least invasive existing mechanism is `CreateRetryTask`'s non-NULL `fire_at` branch, which inserts the child as `deferred` (`pkg/db/queries/agent.sql:584` status CASE, `:599` fire_at), then backfill the overlay and activate/promote the child. If using a new status/flag instead, it must be an explicit two-phase activation, not just “move after commit”.
4. Do not rely on a pre-CAS `GetAgentTask` check or `LockAgentTaskStartClaim` as the default fix for the external call:
   - a plain read is not atomic and still races the CAS;
   - taking a task lock before the existing chat-session/advisory ordering changes Task/Chat/Runtime lock timing and needs separate deadlock review.
5. No existing Composio session-ID cleanup is available in this path (`BuildTaskOverlay` discards it), so compensation-after-failure would require a larger change. Post-commit creation plus deferred activation is the smaller safe direction.

## Residual

- Did not inspect `PromoteDueDeferredTasksForRuntime`/claim promotion internals or other services; no DB/tests/version commands; no source changes.
- `CreateRetryTask` SQL reference lines above are from current `pkg/db/queries/agent.sql`; exact generated method remains `qtx.CreateRetryTask`.
