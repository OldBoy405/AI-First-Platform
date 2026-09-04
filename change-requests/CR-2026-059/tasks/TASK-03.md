---
id: CR-2026-059-TASK-03
type: TASK
cr-ref: CR-2026-059
plan-ref: "change-requests/CR-2026-059/plan.md"
sdd-ref: "change-requests/CR-2026-059/sdd.md"
target-version: "0.32"
title: 处理层与实时：handler kind 分流 + 事件 + 断连控制
slug: handlers-events-realtime
status: pending
estimate: 20h
depends-on: [CR-2026-059-TASK-01, CR-2026-059-TASK-02]
created: 2026-09-04T16:40:00+08:00
---

# TASK-03 处理层与实时：handler kind 分流 + 事件 + 断连控制

## 任务描述

在 multica CR worktree 落地 SDD §3.1–§3.7、§4.7、§4.8 的 handler/事件/实时层：Discussion 四主 endpoint 按 kind 分流与 PRD 错误码矩阵（FR-17/18/22）、merge-forward `message_ids` 扩展（FR-23/24/27）、`Idempotency-Key` 头门禁、事件 `ChatSessionKind` 标注与 kind 感知路由（FR-20）、`Broadcaster.DisconnectWorkspaceUser` 跨节点断连契约（AC-29）、移出事务挂接、已发送 shared 附件下载门禁（FR-25）。`kind=private` 与 legacy `comment_ids` 路径逐行保留（NFR-6/7）。代码注释英文。

## 涉及文件 / 模块

- `server/internal/handler/project_chat.go`：`GetProjectDiscussion` 重写（`ProjectDiscussionResponse` 新字段，`issue_id` 恒 nil；`legacy_issue_id` 只读 `GetProjectDiscussionIssue`）；`MergeForwardDiscussion` 扩展 `message_ids`（互斥/去重/同 session 校验 → 400 `invalid_merge_forward_selection`/`invalid_message_selection`；`Idempotency-Key` 头必填门禁（缺失/>255B → 400 `idempotency_key_required`）；逐条 `GetChatMessageInWorkspace` 校验；派发前即时成员复核；调扩展后 `IssueService.MergeForwardDiscussion(ctx, ws, project, caller, comments, messages, registerCR, idempotencyKey)`）；错误映射复用 `writeProjectChatSendError`。
- `server/internal/handler/chat.go`：`PatchChatSessionConfig` / `SendChatMessage` / `ListChatMessages` / `ListChatMessagesPage` 按 `session.Kind` 分流（§3.2/§3.3/§3.4/§3.6 闭包表）；`ChatMessageResponse` 增 `author_type`/`author_id` 可空字段，`chatMessageToResponse` 直映 M486 列；shared 分页 `writeErrorCode(..., "invalid_cursor", ...)`。
- `server/internal/handler/project.go`：settings coordinator 三态清除分支（`null`/`""` → 删除 key → `UpdateProjectSettingsWithDiscussionCoordinator`，锁内投影）。
- `server/internal/handler/file.go`：`loadAttachmentForRequest` 扩展——附件 `chat_session_id` 非空且所属 session `kind=project_shared` → 放行条件改为当前 workspace 成员（非成员 404 不确认存在）；private/未绑定草稿行为不变。
- `server/internal/handler/workspace_revoke.go`：`revokeAndRemoveMember` 事务提交后调用 `broadcaster.DisconnectWorkspaceUser(userID, workspaceID)`，独立于 `revocationResult.isEmpty()`。
- `server/internal/handler/daemon.go` + `handler.go`：`publishChat` 增 kind 参（既有调用点传 `private`）；task 流式帧按 session kind 填 `Event.ChatSessionKind`。
- `server/internal/events/bus.go`：`Event` 增 `ChatSessionKind string`（契约注释：生产端必须与 ChatSessionID 同时设置；空值按 private fail-closed）。
- `server/internal/realtime/broadcaster.go`：`Broadcaster` 接口增 `DisconnectWorkspaceUser(userID, workspaceID string)`（纯新增，既有四方法零 diff）；`hub.go` 本地断连实现（房间清理走既有 `removeClient`）。
- `server/internal/realtime/redis_relay.go` / `sharded_stream_relay.go` / `relay_lifecycle.go`：`deliverEnvelope` 唯一新增分支——`EventType == "realtime.control"` → 解析 action → 本地断连，绝不 fanout 客户端；`DualWriteBroadcaster` 本地立即执行 + `PublishWithID(user scope, 控制帧)`，环回幂等。
- `server/cmd/server/listeners.go`：kind 感知路由——`ChatSessionID != ""` 且 `ChatSessionKind == "project_shared"` 且 `WorkspaceID != ""` → `BroadcastToWorkspace`；否则维持现状（`ChatRecipientID` + `SendToUser`，缺失丢弃 + ERROR，fail-closed 不变）。`server/cmd/server` sweeper 接线（TASK-02 的 `SweepChatIdempotency`，每小时，`maxPerTick`）。

## 实现要点

- 控制帧载体：保留类型 `{"type":"realtime.control","action":"disconnect_workspace","workspace_id":"<uuid>"}`，publish 到 `user:{userID}` scope 流（`Hub.Run` register 已自动订阅 user scope [D-26]，持有该用户连接的节点必然消费）；XADD 失败记日志+指标并重试一次，仍失败仅记录（请求级门禁与重连拒绝是安全边界）。
- 错误码矩阵按 PRD FR-18 逐一落点：400 invalid_model_or_thinking_level / invalid_discussion_message / invalid_message_selection / invalid_merge_forward_selection / invalid_cursor / idempotency_key_required；403 forbidden_chat_config / forbidden_project_discussion；404 chat_session_not_found；409 chat_session_closed_or_changed / discussion_coordinator_not_configured / discussion_coordinator_unavailable / attachment_already_bound / idempotency_key_reused。legacy `invalid_comment_selection` 不动。
- §3.6 闭包表逐 endpoint 落实：shared 读=成员、轻量写=owner/admin、DELETE 拒绝 403；任何 `kind=project_shared` 请求不进入 creator-only 分支，任何 `kind=private` 请求不进入成员分支。

## 接口契约

**消费（TASK-01/02 产出，签名逐字一致；B-DP-03/04 修复）**：

- `GetChatMessageInWorkspace`（TASK-01 Params 语义：无行 = `pgx.ErrNoRows` → 400 `invalid_message_selection`）。
- `EnsureProjectDiscussionSession(ctx, deps DiscussionSessionDeps, wsID, projectID, callerID) (ProjectDiscussionSessionView, error)`；`SendDiscussionMessage(ctx, deps DiscussionSessionDeps, wsID, callerID, sessionID, input DiscussionSendInput, idempotencyKey) (DiscussionSendResult, *DiscussionSendError)`；`UpdateProjectSettingsWithDiscussionCoordinator(ctx, deps DiscussionSessionDeps, wsID, projectID, newAgentID *uuid.UUID) error`；`SweepChatIdempotency(ctx, q *db.Queries, cutoff) (int64, error)`。
- `DiscussionSessionDeps{Queries *db.Queries, TxStarter TxStarter, TaskSvc *TaskService}`（handler 组装层以 `TaskService.TxStarter/Queries` 接线，单实例）。
- 事件/队列边界（与 TASK-02 注释同文本）：service 只回结果；本 TASK 在成功后执行 post-commit `publishChat(..., kind=project_shared)`、`task:queued`（kind 标注）与 `NotifyTaskEnqueued`。
- `func buildMergedForwardContentFromMessages(ctx context.Context, taskSvc *TaskService, msgs []db.ChatMessage, registerCR bool) string`（B-DP-04 修复：**带 `taskSvc`，与 SDD §3.5 逐字一致**）——包归属 `server/internal/service`（unexported），本 TASK handler 不直接跨包调用：经扩展后 `func (s *IssueService) MergeForwardDiscussion(ctx context.Context, workspaceID, projectID, callerID pgtype.UUID, comments []db.Comment, messages []db.ChatMessage, registerCR bool, idempotencyKey string) (*SendProjectChatMessageResult, error)` 消费（message_ids 幂等/重放/接管语义见 TASK-02 产出契约，handler 只负责头门禁与传参）。
- `DiscussionSendError.Code` 映射为 HTTP 状态 + error-code（§3.4/FR-18 表）。

**产出（供 TASK-04 消费的 HTTP 契约；B-DP-09 修复：补全 PRD 全部状态/权限/幂等/副作用语义，与 PRD「Discussion HTTP 契约」/「merge-forward HTTP 契约」逐项一致，TASK-04 消费同一份清单）**：

- `GET /api/projects/{projectId}/discussion`：request 无 body；权限 = 当前 workspace 成员，非成员/已移出 → 403 `forbidden_project_discussion`，**项目不存在/不在本 workspace → 404（现有 `project not found`，无 code）**；成功 200 `{session_id, issue_id: null, legacy_issue_id: uuid|null, coordinator_agent_id, model, thinking_level, model_source, thinking_level_source}`；幂等：不要求头，并发 GET 项目锁收敛同一 session；副作用：最多插一行 `chat_session`（kind=project_shared），禁插 Issue、禁补建 legacy。
- `PATCH /api/chat/sessions/{sessionId}/config`（shared）：request 三态 body（省略保持/`null`|`""` 清/非空设）；权限 = owner/admin（成员非 owner/admin → 403 `forbidden_chat_config`），**非 workspace 成员/错 kind/跨项目 → 404 `chat_session_not_found`**；成功 200（同 GET 配置字段）；错误：`status≠active` → 409 `chat_session_closed_or_changed`、400 `invalid_model_or_thinking_level`（§4.4 L1/L2）、非法 JSON 400；幂等：不要求头，末次提交获胜；副作用：只改 session override，绝不 `UpdateAgent`，不影响已入队 task。
- `GET /api/chat/sessions/{sessionId}/messages` 与 `/messages/page`（shared，**同语义**）：request query `limit`（默认 50，1–100）/`before_created_at`+`before_id` 成对；非法 limit/半截 cursor → 400 `invalid_cursor`；权限 = 当前 workspace 成员，**非成员/错 kind/跨项目 → 404 `chat_session_not_found`**；成功 200：**两 endpoint 均恒返回分页对象 `ChatMessagesPageResponse{messages, limit, has_more, next_cursor?}`（绝不裸数组）**，`messages[].{id, chat_session_id, role, content, task_id, created_at, attachments, author_type: "member"|"agent"|null, author_id: uuid|null}`；**已归档 shared session → 200 只读**（可完整回放）；副作用无；不得混入 Private Ask 消息。
- `POST /api/chat/sessions/{sessionId}/messages`（shared）：request `{content, attachment_ids?, coordinator_request?}`；头 `Idempotency-Key` **必填**（缺 → 400 `idempotency_key_required`；>255B → 400）零写入；输入违反（空 content 且无附件 / attachment_ids 重复或非 UUID / 非法 coordinator_request）→ 400 `invalid_discussion_message` 零写入；权限 = 当前 workspace 成员（**非成员 → 404 `chat_session_not_found`**；协办另需 invocation 403 复用）；成功 201 `{session_id, message_id, issue_id: null, task_id: uuid|null}`；错误：归档 409 `chat_session_closed_or_changed`、绑定 409 `attachment_already_bound`（仅非重放）、配置 400 `invalid_model_or_thinking_level`、指纹冲突 409 `idempotency_key_reused`、两个 coordinator 409；重放 201 同 id；副作用：普通消息一条 `chat_message`（role=user，无 task/Issue），协办同事务加无 Issue chat task，附件同事务绑定，失败零残留。
- `POST /api/projects/{id}/chat/merge-forward` `message_ids` 路径：request `{comment_ids?, message_ids?, register_cr?}`；互斥（双非空 → 400 `invalid_merge_forward_selection`）；`message_ids` 空数组 → 400 `invalid_message_selection`；>50/跨 session/跨项目/Private Ask/普通 Issue/非 UUID → 400（`invalid_message_selection`/generic bad request）；重复静默去重（按首次出现，去重后 ≥1 且 ≤50）；权限 = 当前 workspace 成员 + 既有 Team Agent 发送权限（非成员 → 403 `forbidden_project_discussion`；项目不存在 → 404 `project not found`）；成功 201 既有 `SendProjectChatMessageResponse`（Team Agent 侧 comment/task）；`message_ids` 路径要求 `Idempotency-Key`（缺 → 400；冲突 → 409 `idempotency_key_reused`；重放 201 同 comment_id/task_id），**legacy `comment_ids` 路径不要求该头且行为逐字节不变**；内核错误沿用 `writeProjectChatSendError`（403 `presenter_required`/409 `team_agent_not_configured`/429/502 等）；副作用：Discussion 源消息不移动/不删除/不双写。

## 验收条件

1. `go test ./server/internal/handler/ ./server/internal/service/ -count=1` 全绿且覆盖：FR-18 错误码矩阵逐条（AC-20/22/23/24/25/27/28，含 §3.1 项目不存在 404、§3.3 非成员/错 kind/跨项目 404 与归档 200 只读向量）；成员门禁与移出竞态（AC-28）；legacy `comment_ids` 路径与 Private Ask creator-only 夹具零回归（AC-22）；`issue_id` 恒 null（AC-1）。
2. `go test ./server/cmd/server/ ./server/internal/handler/ ./server/internal/service/ ./server/internal/realtime/ -count=1`（= plan cmd-04，B-DP-05 修复：AC-29/FR-20 联合验收，handler/service 不再被 cmd-04 遗漏）全绿且覆盖：`listeners.go` kind 感知路由（shared → `BroadcastToWorkspace`；private/缺失 → 原 recipient 路径 fail-closed）；`DisconnectWorkspaceUser` 断连/房间清理 hub 单测 + 控制信封 relay 消费测（fake 流）+ `revokeAndRemoveMember` 事务提交后挂接测（含 `revocationResult` 空仍断连）+ 发送/移出竞态二择一 + 双节点验收向量（用户 U 连接在节点 B，移出事务落节点 A → B 关闭 U 连接、后续事件不达、成员 B 不受影响）（AC-29）。
3. 事件层 fail-closed 保持：kind 空/未知时走原 recipient 路径或丢弃 + ERROR 日志（§3.7）。
4. 跨层 AC-6/AC-18 前端作者气泡、session 身份与 merge-forward 请求形状归 TASK-04（plan §7：cmd-06）；本 TASK 仅承担后端隔离/门禁/事件部分（cmd-02/cmd-04）。
5. 代码注释英文；无 TBD。

## 完成标志

上述测试命令全绿 + 错误码矩阵与 HTTP 契约（本 TASK「接口契约」完整清单）逐条落点 + 断连契约五形态消费矩阵实现完毕 + `CUSTOM.md` 本 TASK 条目已按当时实际结构登记（handler 六文件改动、events/bus.go、realtime 三文件、listeners.go、sweeper 接线），且全部已 commit 到 `requirement/CR-2026-059`（`developing` 内可被 `crctl task done` 登记的事件）。
