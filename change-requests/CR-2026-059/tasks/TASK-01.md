---
id: CR-2026-059-TASK-01
type: TASK
cr-ref: CR-2026-059
plan-ref: "change-requests/CR-2026-059/plan.md"
sdd-ref: "change-requests/CR-2026-059/sdd.md"
target-version: "0.32"
title: 迁移与数据层：481–490 迁移 + sqlc 查询扩展
slug: migrations-and-data-layer
status: pending
estimate: 16h
depends-on: []
created: 2026-09-04T16:40:00+08:00
---

# TASK-01 迁移与数据层：481–490 迁移 + sqlc 查询扩展

## 任务描述

在 multica CR worktree（`server/migrations/`、`server/pkg/db/queries/`）落地 SDD §2.1–§2.6 的十个迁移（481–490，各有 down）与 `cmd/migrate` 钩子登记，并扩展 sqlc 查询供 TASK-02 消费。迁移编号即部署序；每个索引迁移 `CREATE [UNIQUE] INDEX CONCURRENTLY`、一文件一条语句；不新增任何 FOREIGN KEY / REFERENCES（481 属已批 PRD 的「转换既有约束」唯一例外，SQL 与 PRD FR-21 逐字一致）。代码注释一律英文。

## 涉及文件 / 模块

- 新建 `server/migrations/481_chat_session_agent_nullable_set_null.up.sql`（+ `.down.sql`）：`DROP NOT NULL` → `DROP CONSTRAINT chat_session_agent_id_fkey` → `ADD CONSTRAINT ... ON DELETE SET NULL`；down 逆序恢复 CASCADE + `SET NOT NULL`，注释写明「先清理 NULL 行再回滚」。
- 新建 `482_chat_session_kind.up.sql`（+ down）：`kind TEXT NOT NULL DEFAULT 'private' CHECK (kind IN ('private','project_shared'))`；down 有损注记（§2.2）。
- 新建 `483_chat_session_private_active_unique.up.sql`（+ down）：`CREATE UNIQUE INDEX CONCURRENTLY ... WHERE project_id IS NOT NULL AND status='active' AND kind='private'`。
- 新建 `484_drop_chat_session_project_creator_active_unique.up.sql`（+ down：以旧宽谓词 `CREATE UNIQUE INDEX CONCURRENTLY` 重建）。
- 新建 `485_chat_session_project_shared_active_unique.up.sql`（+ down）：`(workspace_id, project_id) WHERE kind='project_shared' AND status='active'`。
- 新建 `486_chat_message_author.up.sql`（+ down）：`author_type TEXT`、`author_id UUID`，可空、无 FK；down 有损注记。
- 新建 `487_chat_idempotency.up.sql`（仅建表，不内联 PK）+ `488_chat_idempotency_scope_key_unique.up.sql`（CONCURRENTLY 唯一索引）+ `489_chat_idempotency_pkey.up.sql`（`USING INDEX` 挂 PK）+ `490_idx_chat_idempotency_created.up.sql`（CONCURRENTLY 辅助索引）+ 四个 down（逆序，§2.6）。
- `server/cmd/migrate`：`concurrentIndexCleanups` 登记 **up = 483/485/488/490**；`concurrentDownIndexCleanups` 登记 **仅 484.down**（唯一 down 方向 CONCURRENTLY 构建；§4.9 total 不变量）。
- `server/pkg/db/queries/chat.sql`：`GetProjectChatSessionForCreator` 加 `AND kind='private'`（三调用点语义保持，SDD-CLOSE-09）；新增见「接口契约」。
- `server/pkg/db/queries/attachment.sql`：新增 `BindDraftAttachmentsToChatMessage`（WHERE 五类绑定全空 + `source_context_id IS NULL` + uploader=调用者，`RETURNING id`；与 `BindUnboundDraftAttachments` 同构，不复用 `LinkAttachmentsToChatMessage`）。
- 新建 `server/pkg/db/queries/idempotency.sql`：`chat_idempotency` 表 CRUD（见「接口契约」）。
- `make sqlc` 重新生成（生成文件不手改）；`CUSTOM.md` 按当时结构登记本 TASK 全部新文件/挂钩点（编号顺延）。

## 实现要点

- 483/484「先建新名再删旧」保证全程至少一个唯一约束在位（§2.3）；`chat.sql:16` 旧索引名注释同步改新名。
- 487 建表**不内联 PK**；489 `USING INDEX` 前提：目标索引唯一、非部分、列序匹配（488 满足）；挂 PK 时表为空，瞬时完成。
- down 全集按 §4.9 表逐条落地，有损/数据依赖注释逐文件写明，禁止静默吞错。

## 接口契约

**产出（供 TASK-02 消费）** — sqlc 生成函数（`server/pkg/db/queries`，`make sqlc` 后）：

- `GetActiveProjectSharedSession(ctx, workspaceID uuid.UUID, projectID uuid.UUID) (db.ChatSession, error)` — `WHERE workspace_id=$1 AND project_id=$2 AND kind='project_shared' AND status='active'`。
- `InsertProjectSharedSession(ctx, workspaceID, projectID uuid.UUID, agentID pgtype.UUID, creatorID uuid.UUID, baseModel, baseThinkingLevel pgtype.Text) (db.ChatSession, error)` — `kind='project_shared'`。
- `GetChatMessageInWorkspace(ctx, id uuid.UUID, workspaceID uuid.UUID) (db.ChatMessage, error)` — merge-forward `message_ids` 逐条校验用。
- `BindDraftAttachmentsToChatMessage(ctx, workspaceID uuid.UUID, attachmentIDs []uuid.UUID, chatSessionID, chatMessageID uuid.UUID, taskID pgtype.UUID) ([]uuid.UUID, error)`。
- `InsertChatIdempotencyReservation(ctx, ...) (db.ChatIdempotency, error)` — `ON CONFLICT ON CONSTRAINT chat_idempotency_pkey DO NOTHING`；`GetChatIdempotencyByKey(ctx, workspaceID, userID uuid.UUID, scopeType string, scopeID uuid.UUID, key string) (db.ChatIdempotency, error)`；`FinalizeChatIdempotency(ctx, ..., responseStatus int32, responseBody []byte) error`；`SweepChatIdempotency(ctx, cutoff time.Time) (int64, error)` — `DELETE ... WHERE created_at < $1`。

## 验收条件

1. `go test ./server/cmd/migrate/ -count=1` 全绿：481–490 up/down 往返可执行（含 482/485/486.down）；`TestEveryConcurrentUpBuildHasCleanup` 通过（登记完整性）。
2. `pg_get_constraintdef` 验证 481 up 后 `chat_session_agent_id_fkey` 为 `ON DELETE SET NULL`；`agent_id` 列可空；483/485/488/490 索引存在且为 CONCURRENTLY 单语句迁移创建；487 表无内联 PK。
3. `make sqlc` 生成无手改残留（生成文件与查询源一致）；`GetProjectChatSessionForCreator` 含 `kind='private'` 过滤且既有三调用点测试不回归。
4. `CUSTOM.md` 已按当时结构登记本 TASK 条目（编号顺延、含 CR 编号与 TASK）。

## 完成标志

迁移测试全绿 + 约束/索引形态验证通过 + sqlc 干净生成 + CUSTOM.md 已登记，且以上全部已 commit 到 `requirement/CR-2026-059` 分支（`developing` 内可被 `crctl task done` 登记的事件）。
