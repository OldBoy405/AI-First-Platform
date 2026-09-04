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

- `server/internal/handler/project_chat.go`：`GetProjectDiscussion` 重写（`ProjectDiscussionResponse` 新字段，`issue_id` 恒 nil；`legacy_issue_id` 只读 `GetProjectDiscussionIssue`）；`MergeForwardDiscussion` 扩展 `message_ids`（互斥/去重/同 session 校验 → 400 `invalid_merge_forward_selection`/`invalid_message_selection`；派发前即时成员复核）；错误映射复用 `writeProjectChatSendError`。
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

**消费（TASK-02 产出，签名逐字一致）**：`EnsureProjectDiscussionSession(ctx, deps, wsID, projectID, callerID) (ProjectDiscussionSessionView, error)`；`SendDiscussionMessage(ctx, deps, wsID, callerID, sessionID, input, idempotencyKey) (DiscussionSendResult, *DiscussionSendError)`；`UpdateProjectSettingsWithDiscussionCoordinator(ctx, deps, wsID, projectID, newAgentID *uuid.UUID) error`；`buildMergedForwardContentFromMessages(ctx, msgs, registerCR) (string, error)`；`SweepChatIdempotency(ctx, q, cutoff) (int64, error)`。`DiscussionSendError.Code` 映射为 HTTP 状态 + error-code。

**产出（供 TASK-04 消费的 HTTP 契约，与 PRD 逐字一致）**：

- `GET /api/projects/{projectId}/discussion` → 200 `{session_id, issue_id: null, legacy_issue_id: uuid|null, coordinator_agent_id, model, thinking_level, model_source, thinking_level_source}`；非成员 403 `forbidden_project_discussion`。
- `PATCH /api/chat/sessions/{sessionId}/config`（shared）→ 200 同 GET 配置字段；403 `forbidden_chat_config` / 404 `chat_session_not_found` / 409 `chat_session_closed_or_changed` / 400 `invalid_model_or_thinking_level`。
- `GET /api/chat/sessions/{sessionId}/messages` 与 `.../messages/page`（shared）→ 200 分页对象 `ChatMessagesPageResponse`（`messages[].{id, chat_session_id, role, content, task_id, created_at, attachments, author_type: "member"|"agent"|null, author_id: string|null}`、`limit`、`has_more`、`next_cursor?`）；400 `invalid_cursor`。
- `POST /api/chat/sessions/{sessionId}/messages`（shared）→ 201 `{session_id, message_id, issue_id: null, task_id: uuid|null}`；头 `Idempotency-Key` 必填（缺 → 400 `idempotency_key_required`；>255B → 400）；409 `attachment_already_bound`/`idempotency_key_reused`；重放 201 同 id。
- `POST /api/projects/{id}/chat/merge-forward` `message_ids` 路径 → 201 既有 `SendProjectChatMessageResponse`；400 `invalid_message_selection`/`invalid_merge_forward_selection`/`idempotency_key_required`；409 `idempotency_key_reused`；内核错误沿用 `writeProjectChatSendError`。

## 验收条件

1. `go test ./server/internal/handler/ ./server/internal/service/ -count=1` 全绿且覆盖：FR-18 错误码矩阵逐条（AC-20/22/23/24/25/27/28）；成员门禁与移出竞态（AC-6/28）；legacy `comment_ids` 路径与 Private Ask creator-only 夹具零回归（AC-22）；`issue_id` 恒 null（AC-1）。
2. `go test ./server/internal/realtime/ -count=1` 全绿且覆盖：`DisconnectWorkspaceUser` 断连/房间清理 hub 单测 + 控制信封 relay 消费测（fake 流）+ handler 级挂接测（含 `revocationResult` 空仍断连）+ 双节点验收向量（用户 U 连接在节点 B，移出事务落节点 A → B 关闭 U 连接、后续事件不达、成员 B 不受影响）（AC-29）。
3. 事件层 fail-closed 保持：kind 空/未知时走原 recipient 路径或丢弃 + ERROR 日志（§3.7）。
4. 代码注释英文；无 TBD。

## 完成标志

上述测试命令全绿 + 错误码矩阵与 HTTP 契约逐条落点 + 断连契约五形态消费矩阵实现完毕，且全部已 commit 到 `requirement/CR-2026-059`（`developing` 内可被 `crctl task done` 登记的事件）。
