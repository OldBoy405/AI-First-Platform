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
- `server/pkg/db/queries/chat.sql`：`GetProjectChatSessionForCreator` 加 `AND kind='private'`（三调用点语义保持，SDD-CLOSE-09）；新增 `GetActiveProjectSharedSession`、`InsertProjectSharedSession`、`GetChatMessageInWorkspace`、`SetChatSessionAgentID`（见「接口契约」）；既有 `CreateChatMessage` INSERT 扩展作者列（`sqlc.narg(author_type)`/`sqlc.narg(author_id)`，既有调用者缺省→NULL，零行为变化）。
- `server/pkg/db/queries/attachment.sql`：新增 `BindDraftAttachmentsToChatMessage`（WHERE 五类绑定全空 + `source_context_id IS NULL` + `uploader_type = sqlc.arg(uploader_type) AND uploader_id = sqlc.arg(uploader_id)`，`RETURNING id`；与 `BindUnboundDraftAttachments` 同构，不复用 `LinkAttachmentsToChatMessage`）。
- 新建 `server/pkg/db/queries/idempotency.sql`：`chat_idempotency` 表 CRUD（见「接口契约」）。
- `make sqlc` 重新生成（生成文件不手改）；`CUSTOM.md` 按当时结构登记本 TASK 全部新文件/挂钩点（编号顺延）。

## 实现要点

- 483/484「先建新名再删旧」保证全程至少一个唯一约束在位（§2.3）；`chat.sql:16` 旧索引名注释同步改新名。
- 487 建表**不内联 PK**；489 `USING INDEX` 前提：目标索引唯一、非部分、列序匹配（488 满足）；挂 PK 时表为空，瞬时完成。
- down 全集按 §4.9 表逐条落地，有损/数据依赖注释逐文件写明，禁止静默吞错。

## 接口契约

**产出（供 TASK-02 消费）** — sqlc 生成函数（`server/pkg/db/queries`，`make sqlc` 后 `server/pkg/db/generated/`）。全部以 Params 结构传参（与基线生成 API 一致，`chat.sql.go`/`attachment.sql.go` 先例）；返回与冲突/无行语义逐项锁定，TASK-02/03 消费签名以本清单为准：

- `GetActiveProjectSharedSession(ctx context.Context, arg GetActiveProjectSharedSessionParams) (db.ChatSession, error)` — `SELECT * FROM chat_session WHERE workspace_id=$1 AND project_id=$2 AND kind='project_shared' AND status='active'`；Params = `{WorkspaceID pgtype.UUID, ProjectID pgtype.UUID}`；无行 → `pgx.ErrNoRows`（§4.1 锁内 reselect 分支）。
- `InsertProjectSharedSession(ctx context.Context, arg InsertProjectSharedSessionParams) (db.ChatSession, error)` — `INSERT INTO chat_session (workspace_id, agent_id, creator_id, title, project_id, kind, base_model, base_thinking_level) VALUES ($1, sqlc.narg('agent_id'), $2, '', $3, 'project_shared', sqlc.narg('base_model'), sqlc.narg('base_thinking_level')) RETURNING *`；Params = `{WorkspaceID pgtype.UUID, AgentID pgtype.UUID(可空), CreatorID pgtype.UUID, ProjectID pgtype.UUID, BaseModel pgtype.Text(可空), BaseThinkingLevel pgtype.Text(可空)}`（`runtime_id` 为既有可空列 [060]，不写= NULL；无 Coordinator 时 `AgentID` 为 Invalid）。唯一索引冲突由 §4.1 锁内 reselect 处理（与 EnsureProjectChatSession 同构）。
- `SetChatSessionAgentID(ctx context.Context, arg SetChatSessionAgentIDParams) (int64, error)` — `UPDATE chat_session SET agent_id=$2 WHERE id=$1`（`:execrows`）；Params = `{ID pgtype.UUID, AgentID pgtype.UUID}`；返回受影响行数，§4.5 投影调用方断言 ==1。
- `GetChatMessageInWorkspace(ctx context.Context, arg GetChatMessageInWorkspaceParams) (db.ChatMessage, error)` — `SELECT message.* FROM chat_message AS message JOIN chat_session AS session ON session.id = message.chat_session_id WHERE message.id=$1 AND session.workspace_id=$2`（`chat_message` 表无 workspace_id 列 [033]，workspace 谓词必须经 session JOIN）；Params = `{ID pgtype.UUID, WorkspaceID pgtype.UUID}`；无行 → `pgx.ErrNoRows`（merge-forward 校验映射 400 `invalid_message_selection`）。
- `BindDraftAttachmentsToChatMessage(ctx context.Context, arg BindDraftAttachmentsToChatMessageParams) ([]BindDraftAttachmentsToChatMessageRow, error)` — `UPDATE attachment SET chat_session_id=$1, chat_message_id=$2, task_id=$3 WHERE workspace_id=$4 AND id = ANY($5::uuid[]) AND issue_id IS NULL AND comment_id IS NULL AND chat_session_id IS NULL AND chat_message_id IS NULL AND task_id IS NULL AND source_context_id IS NULL AND uploader_type=$6 AND uploader_id=$7 RETURNING id`（`:many`）；Params = `{ChatSessionID pgtype.UUID, ChatMessageID pgtype.UUID, TaskID pgtype.UUID, WorkspaceID pgtype.UUID, AttachmentIds []pgtype.UUID, UploaderType string, UploaderID pgtype.UUID}`；生成行类型 = `BindDraftAttachmentsToChatMessageRow{ID pgtype.UUID}`。**uploader 门禁（B-DP-02 修复）**：`UploaderType`/`UploaderID` 由 TASK-02 从请求鉴权身份推导（`requireWorkspaceMember` 的 caller；恒 `"member"`），绝不来自请求体——跨上传者绑定返回 0 行（TASK-02 映射 409 `attachment_already_bound`），AC-12/AC-13 机械可达。
- 既有 `CreateChatMessage` 扩展：Params 增 `AuthorType pgtype.Text`/`AuthorID pgtype.UUID`（`sqlc.narg`，可空）；既有调用者缺省 → NULL，生成列扫描自动更新；`kind=private` 写入路径不传（NFR-6 零变化）。

**幂等 CRUD（`idempotency.sql`，scope_type ∈ `discussion_message` | `merge_forward_messages`）**：

- `InsertChatIdempotencyReservation(ctx context.Context, arg InsertChatIdempotencyReservationParams) (db.ChatIdempotency, error)` — `INSERT INTO chat_idempotency (workspace_id, user_id, scope_type, scope_id, key, fingerprint) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT ON CONSTRAINT chat_idempotency_pkey DO NOTHING RETURNING *`（`:one`）；Params = `{WorkspaceID pgtype.UUID, UserID pgtype.UUID, ScopeType string, ScopeID pgtype.UUID, Key string, Fingerprint string}`；**冲突/无行语义**：唯一冲突 → 无行返回 `pgx.ErrNoRows`（PG 对并发未提交赢家会阻塞至其提交/回滚，§4.6）——调用方转 `GetChatIdempotencyByKey` 读赢家行。
- `GetChatIdempotencyByKey(ctx context.Context, arg GetChatIdempotencyByKeyParams) (db.ChatIdempotency, error)` — `SELECT * FROM chat_idempotency WHERE workspace_id=$1 AND user_id=$2 AND scope_type=$3 AND scope_id=$4 AND key=$5`；Params 同 PK 五列（`ScopeID pgtype.UUID`）；无行 → `pgx.ErrNoRows`。
- `FinalizeChatIdempotency(ctx context.Context, arg FinalizeChatIdempotencyParams) (int64, error)` — `UPDATE chat_idempotency SET response_status=$6, response_body=$7 WHERE workspace_id=$1 AND user_id=$2 AND scope_type=$3 AND scope_id=$4 AND key=$5`（`:execrows`）；Params = `{...PK 五列, ResponseStatus int32, ResponseBody []byte}`（JSONB ↔ `[]byte`）；返回受影响行数，调用方断言 ==1（失败 → 事务回滚）。
- `DeleteChatIdempotencyByKey(ctx context.Context, arg DeleteChatIdempotencyByKeyParams) (int64, error)` — `DELETE FROM chat_idempotency WHERE workspace_id=$1 AND user_id=$2 AND scope_type=$3 AND scope_id=$4 AND key=$5`（`:execrows`）；Params 同 PK 五列；供 merge-forward 执行失败清理预留行（键可复用）。
- `SweepChatIdempotency(ctx context.Context, cutoff time.Time) (int64, error)` — `DELETE FROM chat_idempotency WHERE created_at < $1`（`:execrows`）；参数 `time.Time`（timestamptz），返回删除行数；24h 严格阈值与 `maxPerTick` 形态对齐 `SweepChatDraftAttachments`（§4.6）。

所有新查询写入后 `make sqlc` 再生成；生成文件不手改；新表结构 = §2.6 487 迁移（列名/类型与上列 Params 一一对应）。

## 验收条件

1. `go test ./server/cmd/migrate/ -count=1` 全绿：481–490 up/down 往返可执行（含 482/485/486.down）；`TestEveryConcurrentUpBuildHasCleanup` 通过（登记完整性）。
2. `pg_get_constraintdef` 验证 481 up 后 `chat_session_agent_id_fkey` 为 `ON DELETE SET NULL`；`agent_id` 列可空；483/485/488/490 索引存在且为 CONCURRENTLY 单语句迁移创建；487 表无内联 PK。
3. `make sqlc` 生成无手改残留（生成文件与查询源一致），且生成签名与本 TASK「接口契约」逐项编译对齐：`BindDraftAttachmentsToChatMessageParams` 含 `UploaderType/UploaderID`；幂等 CRUD 的 Params/返回/冲突语义与清单一致；`GetProjectChatSessionForCreator` 含 `kind='private'` 过滤且既有三调用点测试不回归。
4. `CUSTOM.md` 已按当时实际结构登记 **本 TASK** 条目（编号顺延、含 CR 编号与 TASK）：481–490 迁移与 `cmd/migrate` 两 map 钩子、`chat.sql`/`attachment.sql` 查询改动、新建 `idempotency.sql`。TASK-02/03/04 各自登记各自文件（plan §3 关键纪律），本 TASK 不预登记未来结构。

## 完成标志

迁移测试全绿 + 约束/索引形态验证通过 + sqlc 干净生成（与本 TASK 接口契约编译对齐）+ `CUSTOM.md` 本 TASK 条目已按当时实际结构登记，且以上全部已 commit 到 `requirement/CR-2026-059` 分支（`developing` 内可被 `crctl task done` 登记的事件）。
