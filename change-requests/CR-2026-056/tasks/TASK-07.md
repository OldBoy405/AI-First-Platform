---
id: CR-2026-056-TASK-07
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M3 发送内核：container / messages / merge-forward / 换绑
slug: m3-container-send-rebind
status: pending
estimate: 8h
depends-on: [CR-2026-056-TASK-06]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

POST `/chat/container`、POST `/chat/messages`（首次绑定与发送同一事务）、merge-forward 接入同一内核、换绑 close。对应 plan.md M3 第 4–6 项、SDD §4.5/§4.7/§4.12、§3.1。

输入条件：TASK-06 的 Bind / Ensure / 校验内核已就绪。

## 涉及文件 / 模块

- `server/internal/handler/project_chat.go`（container / messages / merge-forward handler）
- `server/internal/service/project_chat.go`（`sendProjectChatCore` 事务改造、`MergeForwardDiscussion` 改走 Ensure session）
- `server/internal/handler/project.go`（换绑分支挂钩 `CloseActiveProjectChatSession`）
- `server/cmd/server/router.go`（注册 `POST /api/projects/{projectId}/chat/container`）

## 实现要点

1. **POST `/chat/container`（§3.1，FR-10/FR-4）**：presenter 鉴权（与发送相同，非 owner/admin）→ session 归属（workspace/project/active/agent_id 与当前绑定一致，否则 404/409）→ `ResolveChatConfig` → §4.3 `AgentReadiness` + catalog（失败不建 Issue）→ 自己的短事务调 `BindProjectChatContainer`。成功 200，形状同 GET 且 `issue_id` 非空；重复调用仍 200 + 同一 `issue_id`（幂等键即 `session_id`）。
2. **POST `/chat/messages`（§4.5，FR-16）**：请求必加 `session_id`；流程：校验 `session_id` → 项目 advisory → presenter + queue capacity（失败则无 Issue）→ Resolve + §4.3（失败无 comment、无 Bind）→ **单一 PostgreSQL 事务**：`BindProjectChatContainer(outerTx)` → `CreateComment` → `enqueueMentionTaskWithCommentPlan` → merge `context.chat_config` → `BindUnboundDraftAttachments`（TASK-09 的挂钩点，本 TASK 先接入调用）→ commit → 成功后 broadcast。成功 **201**，体为 `{session_id, issue_id, comment_id, task_id}`（`session_id` 等于请求值，`issue_id` 等于 session 行回写值）；保留既有 403 presenter / 429 queue full / 502 enqueue_failed。移除发送路径上 `ensureContainerIssue` 的内部 Commit（禁止先 Commit 容器再入队）。锁序固定（§4.14）：advisory → session `FOR UPDATE` → 创建 Issue → 附件 `ORDER BY id`，禁止颠倒。
3. **失败原子性**：发送任一步失败整体 rollback——Issue 行、`session.issue_id`、comment、task、附件绑定全部撤销（附件草稿保留为五类全空）。显式 POST container 已成功提交的空容器不算半成品。
4. **merge-forward（§4.12）**：请求体不变（`comment_ids` + 可选 `register_cr`，无 `session_id`）；handler `MergeForwardDiscussion` 不再调 `EnsureProjectChatIssue`：Ensure active session（含 workspace；并发换绑导致刚读 session 已 closed → 409）→ Resolve → §4.3（失败不建 Issue、不入队）→ 复用与 messages 同一发送事务 → 成功体在现有字段上增加 `session_id` 与绑定后的 `issue_id`；失败码与 messages 对齐。
5. **换绑（§4.7，FR-7）**：`handler/project.go` 写 `settings.team_agent_id` 的现有分支与 `CloseActiveProjectChatSession` 在**同一把** `project-chat-session|{ws}|{project}` advisory 下提交；不在此处创建新 session / 新 Issue；下一次 GET 按新 `agent_id` 插入新行。

## 验收条件

1. 并发 `container` + `messages`：两成功体 `issue_id` 相同且非空（AC-13，直接读响应 JSON 断言）。
2. container 校验失败（非法 model / Waitable 无 cache / Blocked）：无新 `project_chat` Issue、`session.issue_id` 仍 NULL（AC-23/AC-24）。
3. 首次发送失败（注入 enqueue / 附件绑定错误）：无 `session.issue_id`、无空容器、草稿五类全空（AC-15）。
4. merge-forward：无 session 时创建 session + 容器且任务带 `chat_config`；已有 override 的 session 入队快照为 override，随后 PATCH 不影响该任务（AC-7）；Waitable 无 cache / Blocked 不建 Issue、不入队；换绑后写**新** session 的 Issue，旧 timeline 不变。
5. 换绑：旧 session closed、新 GET 得新 `session_id` 且后续发送得**新** `issue_id`，旧评论不出现在新 timeline（AC-18）；两容器行 `origin_id` 不同。
6. `go test ./server/internal/handler/ ./server/internal/service/ -count=1` 相关夹具绿。

## 完成标志

上述夹具绿并提交；发送事务锁序与 §4.14 表逐条核对记录留档。

## 接口契约

- 消费：TASK-06 的 `service.BindProjectChatContainer`（外层 tx 语义）、GET/PATCH 内核与项目级 advisory、TASK-05 的 `ResolveChatConfig` / `ValidateResolvedChatConfig` / `ChatCatalogPort`、TASK-03 的 `CloseActiveProjectChatSession`、基线 `sendProjectChatCore` / `enqueueMentionTaskWithCommentPlan`。
- 产出：
  - 发送事务（Bind + comment + enqueue + `chat_config` merge + 附件绑定，单 tx）——TASK-09 的 `BindUnboundDraftAttachments` 挂钩点；
  - messages / merge-forward 成功体形状 `{session_id, issue_id, comment_id, task_id}`（merge-forward 为现有字段附加）——TASK-10 前端 client 消费；
  - 换绑事务（`team_agent_id` 更新 + `CloseActiveProjectChatSession` 同 advisory）。
