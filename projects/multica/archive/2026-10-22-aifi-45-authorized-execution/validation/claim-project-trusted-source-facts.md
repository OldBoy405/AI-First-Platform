# Claim / project trusted-source facts (AIFI-45 read-only)

Source root: `C:/Users/GOBAO/Downloads/AI/multica/server` (current source lines below).

## 1. There is no `protocol.TaskData` / SDK `GetTask`

- No `TaskData` or `Client.GetTask` symbol exists in current `pkg/protocol` or `internal/daemon`. The daemon claim DTO is `daemon.Task` (`internal/daemon/types.go:77`); `ProjectID` is an optional claim JSON field (`types.go:113`).
- Claim SDK is `internal/daemon/client.go:258-270`: `Client.ClaimTask` POSTs `/api/daemon/runtimes/{runtimeID}/tasks/claim`, decodes `{"task": Task}`. Batch claim is `/api/daemon/tasks/claim` (`client.go:325-339`). `GetTaskStatus` (`client.go:744`) returns only status, not a task DTO.

## 2. Claim response fields and real sources

- Handler entry: `ClaimTaskByRuntime` (`internal/handler/daemon.go:4168`) and `ClaimTasksByRuntime` (`:1800`) both reach `buildClaimedTaskResponse` (`:2708`, batch call `:1953`, single call `:4236`).
- `taskToResponse` (`internal/handler/agent.go:842`) sets `ID/AgentID/RuntimeID/IssueID/WorkspaceID` from the task row/runtime workspace at `agent.go:881-885`; `DispatchedAt` in the claim path is overwritten from `task.DispatchedAt` with `StartClaimSupported=true` (`daemon.go:2732-2735`). It does **not** assign `ProjectID`.
- Project is applied later from the live source entity:
  - issue: `issue.ProjectID` → `resolveClaimProjectContext` (`daemon.go:3187`, apply at `:3199`)
  - chat: `cs.ProjectID` (`daemon.go:3554`, apply `:3566`)
  - autopilot: `ap.ProjectID` (`:3806`, apply `:3818`)
  - quick-create: parsed `qc.ProjectID` (`:3878`, apply `:3890`)
- `claimProjectContext.applyTo` copies `ProjectID` (`internal/handler/project_resource.go:994`). `resolveClaimProjectContext` reads `GetProjectInWorkspace` and workspace-scoped resources (`project_resource.go:1026-1056`); missing/deleted/foreign project (or read failure classified as no row) **degrades to workspace context without error**. So claim `project_id` can be empty even when the task row has one, and it is the live issue/chat/autopilot project, not the queued task's frozen project.
- `StartTask` handler returns `taskToResponse(*task, workspaceID)` (`daemon.go:4606`, `:4658`) using workspace from `requireDaemonTaskAccessWithWorkspace`; because `taskToResponse` does not populate `ProjectID`, the StartTask response has no project binding. It does carry task/runtime/workspace/dispatched_at from the row/auth guard.
- These claim fields come from server DB/handler assembly, not from `TriggerCommentContent` or another message wrapper. Transport/auth trust is separate and not established by the DTO.

## 3. Task-row project seam and NULL/delete semantics

- `agent_task_queue.project_id` is nullable (`disposable-db...schema.sql:1389`); FK `agent_task_queue_project_id_fkey` references `project(id) ON DELETE SET NULL` (`schema.sql:8090`).
- `issue.project_id` is nullable (`schema.sql:2567`); FK `issue_project_id_fkey` is also `ON DELETE SET NULL` (`schema.sql:8458`). Therefore task→issue→project is present only while both references resolve; project deletion clears both.
- `project.workspace_id` is NOT NULL (`schema.sql:3416-3418`); `project_resource.project_id` is `ON DELETE CASCADE` (`schema.sql:8746`) and `project_resource` carries its own `workspace_id`.
- Issue-task enqueue freezes `CreateAgentTaskParams.ProjectID = issue.ProjectID` (`internal/service/task.go:1487-1494`, `:1761-1768`); SQL comment says nullable from caller `issue.ProjectID`, used so `ClaimAgentTask` can serialize without joining issue (`pkg/db/queries/agent.sql:337-338`, insert `:353`, `:384`; claim ordering uses `atq.project_id` at `:909`; claim returns `RETURNING *` at `:933`).
- Pipeline tasks copy `s.issue_id, s.project_id` from the trusted source task row, not from caller input (`agent.sql:617-650`).
- Reusable seams: `agent_task_queue.project_id` (frozen enqueue-time identity), `GetProjectInWorkspace` (`pkg/db/queries/project.sql:8-10`), `ListProjectResourcesInWorkspace` (`pkg/db/queries/project_resource.sql:6-13`), `agent.sql:ClaimAgentTask`/`LockAgentTaskStartClaim`.

## 4. Current pipeline claim path

- `Daemon.handleTask` (`internal/daemon/daemon.go:5737`) calls `prepareClaimedPipelineTask` before running (`:5780`).
- `prepareClaimedPipelineTask` (`internal/daemon/execution_verifier.go:23`) calls `preparePipelineTask`, then reads `task.TriggerCommentContent` for `strictExecutionContract` (`:27`); strict mode requires `task.PipelineWorkspace != ""` (`:31`), opens the trust store with `task.WorkspaceID/PipelineWorkspace/PipelineLocalWorkDir` (`:38`), and calls `InstallExecutionAuthorization(..., task.PipelineCrID, task.PipelineWorkspace)` (`:42`).
- `preparePipelineTask` (`internal/daemon/pipeline_task.go:636`) computes the pipeline root. In strict mode it scopes snapshot views with `viewsForTaskProject(views, task.ProjectID)` (`:687`); that helper explicitly says `taskProjectID` is server-verified and ignores the trigger comment (`:607-635`). However the root itself comes from `pipelineRootViews`/daemon snapshot entries (`:774-788`; `internal/daemon/crevents.go:442-455`, snapshot ProjectID/ResourceID at `:596-617`), and `resolveTaskWorkspaceBinding` still parses `TriggerCommentContent` for declared context (`pipeline_task.go:401-412`). `PipelineWorkspace`/`PipelineLocalWorkDir` are daemon-derived task locals, not claim-response fields.
- Consequence: `task.ProjectID` is the server-verified project source for pipeline root scoping; `resp.ProjectID` in the claim payload is a different, source-live projection. They can disagree after issue/project moves or project deletion, and `StartTask` has no project field.

## 5. Minimum recommendation (no new wire signature)

- Use `agent_task_queue.project_id` (frozen at enqueue, server-stamped, FK-scoped) as the claim/project binding source, not `TriggerCommentContent`, `PipelineWorkspace`, or live issue/chat/autopilot project. The minimal claim tuple is the existing row fields: `{task id, workspace id, task.project_id, runtime_id, dispatched_at}`; `workspace` must still be verified from the task's agent/issue and runtime binding.
- Expose that same tuple through the existing claim response/`Client.ClaimTask` path; if the live source project and `task.project_id` disagree, or either is NULL where a project is required, fail the claim closed. No new signature, nonce, or activation is proposed.
- Test entry should remain the existing `ClaimTaskByRuntime`/`ClaimTasksByRuntime` route and `Client.ClaimTask` fake-transport tests. Transport tests can prove only field carriage; the DB/handler trust test for task-row `project_id` mismatch/NULL belongs to the main session's DB-enabled suite.
- Do not treat MDT, message text, or a daemon-derived pipeline root as isolation/current-head evidence.

## 6. Not inspected / residual

- Did not inspect `StartTask` service body (main session owns it), all claim subpath bodies, batch/WS claim finalization, or project-move/delete transactions beyond the schema FKs above.
- Schema facts are from the disposable DB schema dump, not a live DB query. No DB/container/test execution, no product changes, no MDT isolation claim.
