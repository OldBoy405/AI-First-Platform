---
id: CR-2026-056-TASK-03
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M1 sqlc 新查询 / 改造查询与生成
slug: m1-sqlc-session-queries
status: pending
estimate: 6h
depends-on: [CR-2026-056-TASK-02]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

按 SDD §2.4/§2.5 编写新表与既有表的 sqlc 查询（含改造），`make sqlc` 生成 Go 代码。对应 plan.md M1 后半。

输入条件：TASK-02 迁移已落盘（表/列已定义）。

## 涉及文件 / 模块

- `server/pkg/db/queries/project_chat_session.sql`（新文件，新表查询）
- `server/pkg/db/queries/chat.sql`（`GetProjectChatSessionForCreator` 改造 + Private Ask 新查询）
- `server/pkg/db/queries/issue.sql`（`GetProjectChatIssue` 改造 + 收养查询）
- `server/pkg/db/queries/attachment.sql`（草稿三个新查询）
- `make sqlc` 生成物（禁手改）
- 调用方同步：`server/internal/service/autopilot.go` 等 `GetProjectChatSessionForCreator` 调用点的 Params 传入

## 实现要点

1. 新表查询（SDD §2.4 名表，不得占用 `GetProjectChatSessionForCreator`）：
   - `GetActiveProjectChatSession`：`workspace_id + project_id` 且 `status='active'`；
   - `GetProjectChatSessionByID`：按 `id`，带 workspace/project 校验谓词；
   - `LockProjectChatSessionByID`：`FOR UPDATE`；
   - `InsertProjectChatSession`：插入含 `base_model` / `base_thinking_level`（允许空串）、`issue_id=NULL`、`status='active'`、`created_by`；
   - `PatchProjectChatSessionConfig`：写 `model_override` / `thinking_level_override` / `updated_at`；
   - `BindProjectChatSessionIssue`：`UPDATE ... SET issue_id WHERE id AND issue_id IS NULL`（CAS）；
   - `CloseActiveProjectChatSession`：`active -> closed`；
   - `GetLegacyUnboundProjectChatIssue`：`origin_type='project_chat' AND origin_id IS NULL`，按 workspace+project（0 或 1 行）；
   - `CountProjectChatSessions`：`(workspace_id, project_id)` 含 closed。
2. Private Ask（`chat_session`）：`PatchChatSessionConfig`（写 override）、`BackfillChatSessionBaseIfNull`（仅 `base_*` NULL 时写）、`LockChatSessionInWorkspace`（`SELECT * FROM chat_session WHERE id = $1 AND workspace_id = $2 FOR UPDATE`，行锁 + workspace 重读一步完成；与 `GetChatSessionInWorkspace` 同谓词加锁，禁无 workspace 变体——BLOCK-008 消费）。
3. 改造既有查询：`CreateChatSession` / `CreateChatTask` 加参（BLOCK-004/005）：
   - `CreateChatSession`（chat.sql:1）INSERT 列表加 `base_model` / `base_thinking_level`，值取 `sqlc.narg('base_model')` / `sqlc.narg('base_thinking_level')`（沿用该查询既有 `sqlc.narg` 模式）。基线全部调用方（`agent_builder.go:125` / `chat.go:129` / `mika_agent.go:299` / `project_chat.go:205` / channel engine `session.go:330,473` 含 `dbSessionQuery` 接口包装）的 Params 具名字面量**零改动**（新增字段零值 = NULL，行为与今日逐字节一致）；仅 Private Ask get-or-create（TASK-13）传当时 Team Agent 默认，实现 §2.2「新建插入即写 `base_*`」的 INSERT 时原子快照。
   - `CreateChatTask`（chat.sql:1071）INSERT 列表加 `context`，值取 `sqlc.narg('context')`（jsonb）。基线调用方传 NULL（行为不变）；Private Ask 发送（TASK-13）经同一实参点传 `chat_config` 合并快照。
   - 调用方影响核对：逐处确认上述调用方编译与行为零变化（生成 Params 加字段后既有具名字面量原样编译即为证据）。
4. 改造 `GetProjectChatSessionForCreator`：WHERE 增加权威 `workspace_id`（Hard Invariant 1，SDD §2.2）；同步改所有调用方（含 `autopilot.go`）Params，缺 workspace 不得编译通过。
5. 改造 `GetProjectChatIssue`（兼容钉，BLOCK-017）：`ORDER BY created_at ASC, id ASC LIMIT 1`，保持 `:one`；仅转投路径继续调用（SDD §4.13）。
6. 附件（SDD §2.5）：
   - `LockUnboundDraftAttachments`：`WHERE` 五类（`issue_id`/`comment_id`/`chat_session_id`/`chat_message_id`/`task_id`）全空 + `source_context_id IS NULL` + `id = ANY(...)`，`ORDER BY id FOR UPDATE`（与 `LockAttachmentsForIssueLink` 同锁序：attachment id 升序）；
   - `BindUnboundDraftAttachments`：已锁行上 `UPDATE` 写 `issue_id`/`comment_id`/`task_id`，`WHERE` 仍要求五类全空且 `uploader_*` 匹配发送者（0 行由调用方映射 `409 attachment_already_bound`）；
   - `DeleteUnboundDraftAttachment`（sweeper 专用）：`DELETE WHERE id AND workspace_id AND 五类全空 AND source_context_id IS NULL`。
7. `make sqlc` 生成；生成物禁手改（ARCHITECTURE.md Generated sources）。

## 验收条件

1. `make sqlc` 通过；`cd server && go build ./...` 绿（Go 模块在 `server/go.mod`）；生成物无手改。
2. 符号无碰撞：`GetProjectChatSessionForCreator` 仍只服务 `chat_session`，新表查询未占用该名。
3. 编译级确认：`GetProjectChatSessionForCreator` 调用方全部传入 `workspace_id`（不传则编译失败）。
4. 改造查询零回归：`CreateChatSession` / `CreateChatTask` 加参后，基线全部调用方源码零改动且原样编译通过（narg 零值 = NULL，行为与今日一致，BLOCK-004/005）。
5. 跨 workspace 负向用例（单测或并入 TASK-11）：同 `project_id`+`creator_id` 配错误 `workspace_id` 时 `GetProjectChatSessionForCreator` 返回 0 行。

## 完成标志

`make sqlc` + `cd server && go build ./...` 绿，查询文件提交至 multica CR worktree。

## 接口契约

- 消费：TASK-02 表结构（`project_chat_session` 列、`chat_session` 四列、`issue` 部分唯一索引）。
- 产出（sqlc 生成符号，参数列集如上；Go 签名以生成物为准）：`GetActiveProjectChatSession` / `GetProjectChatSessionByID` / `LockProjectChatSessionByID` / `InsertProjectChatSession` / `PatchProjectChatSessionConfig` / `BindProjectChatSessionIssue` / `CloseActiveProjectChatSession` / `GetLegacyUnboundProjectChatIssue` / `CountProjectChatSessions` / `PatchChatSessionConfig` / `BackfillChatSessionBaseIfNull` / `LockChatSessionInWorkspace` / `LockUnboundDraftAttachments` / `BindUnboundDraftAttachments` / `DeleteUnboundDraftAttachment`，改造后的 `GetProjectChatSessionForCreator`（带 `workspace_id`）与 `GetProjectChatIssue`（`ORDER BY created_at ASC, id ASC LIMIT 1`），以及改造加参的 `CreateChatSession`（`base_model` / `base_thinking_level` narg）与 `CreateChatTask`（`context` jsonb narg）——供 TASK-06/07/08/09/13 消费。
