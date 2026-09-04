---
id: CR-2026-059-sdd
type: SDD
cr-ref: CR-2026-059
title: Discussion 无 Issue 共享会话 技术设计
target-version: 0.32
status: draft
created: 2026-09-04T01:50:00+08:00
updated: 2026-09-04T09:43:00+08:00
---

> 输入：`change-requests/CR-2026-059/prd.md`（选项 A 定点修订后版本，cycle 3 复评 PASS）。成员口径 = 「项目成员 := 当前 workspace 成员」（PRD FR-25 成员口径段，选项 A 裁决，2026-09-03，AIFI-16）。
>
> 所有既有实现断言均按 multica 仓 CR-2026-059 requirement worktree HEAD `e8b252597a6d21718c2533d497fba4109a79b37b` 逐项核实，证据清单见第 10 节（`sdd.explicit_existing_dependencies`），正文引用按首次出现顺序编号 [D-xx]。

# 1. 架构概览

## 1.1 目标

把项目 Discussion 从隐藏 `project_discussion` Issue + comment 承载，切换为 `chat_session(kind='project_shared')` + `chat_message` 承载：打开/发送/附件/协办均不创建工作 Issue；协办任务是无 Issue 的 chat task；旧容器 Issue 只读回放、不双写。

## 1.2 模块边界与改动面（multica 仓；`../tools/` 零改动）

```text
server/migrations/            481–487（7 个新迁移，各有 down）
server/pkg/db/queries/        chat.sql（1 条收窄 + 若干新查询）、attachment.sql（1 条新绑定查询）、
                              idempotency.sql（新）、chat_message 相关插入查询扩展作者列
server/internal/service/      discussion_session.go（新：ensure/send/coordinator/投影/幂等）、
                              task.go（复用 mergeChatConfigContext / CreateChatTask 组合）、
                              chat_idempotency_cleanup.go（新 sweeper）、
                              project_chat.go（GET 不再调 EnsureProjectDiscussionIssue；merge-forward 消息路径）
server/internal/handler/      project_chat.go（GetProjectDiscussion 重写、merge-forward 扩展）、
                              chat.go（config/messages/send/list 按 kind 分流）、
                              project.go（coordinator settings 清除分支 + 锁内投影）、
                              file.go（已发送 shared 附件下载门禁扩展）、
                              daemon.go + handler.go（事件生产端 kind 标注）、
                              workspace_revoke.go（移出事务挂接退订）
server/internal/events/       bus.go（Event 增 ChatSessionKind 字段）
server/internal/realtime/     hub.go / broadcaster.go（新增按 (user, workspace) 断开连接）
server/cmd/server/            listeners.go（kind 感知路由）、sweeper 接线
packages/core/api/            schemas.ts（Discussion 入口/消息/发送响应 schema）、client
packages/views/projects/      discussion-pane.tsx（session 身份重写）、locales 四语 key
```

依赖方向遵守 ARCHITECTURE.md §4：handler → service → db queries；实时路由在 `cmd/server` 组装层；前端 `views → core → ui`。

## 1.3 两张项目会话表的口径（防混淆）

- `project_chat_session`（迁移 472，CR-2026-056）：**Team Agent 群聊**专用表，本 CR **零改动**（NFR-7）。
- `chat_session(kind='project_shared')`：本 CR 的 **Discussion 共享会话**，与 Private Ask / 1:1 同表，靠 `kind` 分流（PRD FR-2、NFR-3「不复制 Discussion 消息表」）。

## 1.4 关键流程

```text
打开      GET /api/projects/{id}/discussion
            └─ EnsureProjectDiscussionSession：advisory + 部分唯一索引收敛 → session 行（不建 Issue）
               └─ 响应 session_id + legacy_issue_id(只读) + coordinator + 解析后配置

普通发送  POST /api/chat/sessions/{sid}/messages (kind=project_shared)
            └─ SendDiscussionMessage 事务：幂等预留 → 锁会话 → 写 chat_message(带作者)
               → 绑定草稿附件 →（无 task、无 Issue）→ 提交 → workspace 广播

协办发送  同上 + coordinator 触发（@mention 可路由 Coordinator 或 analyze/summarize）
            └─ 同事务追加 CreateChatTask(issue_id=NULL, chat_session_id=sid, context.chat_config 快照)
               → daemon 执行 → writeChatCompletionOutcome 把回复写回同一 session [D-11]

配置      PATCH /api/chat/sessions/{sid}/config（kind 分流：private=creator-only 不变；
          project_shared=owner/admin）→ 仅改 session override，绝不 UpdateAgent

协办绑定  PATCH /api/projects/{id}（settings.discussion_coordinator_agent_id）
            └─ 写权威 + 同事务项目锁内投影 session.agent_id（含清除/解绑分支，新增）

转投/转发  RouteDiscussionToTeamAgent / merge-forward：Discussion 侧入参适配，
          不改 sendProjectChatCore（NFR-7、zero_diff）
```

# 2. 数据模型

新迁移从 **481** 起（现最大编号 480 已核实 [D-03]）。编号 481–487 连续，每个文件一条主语句（索引类一律 `CREATE [UNIQUE] INDEX CONCURRENTLY`、一文件一条，PRD FR-21 / ARCHITECTURE 不变量 6），不新增任何 FOREIGN KEY / REFERENCES（481 属「转换既有约束」，是唯一例外且由 PRD 明批——授权段落引注见 §2.1）。

## 2.1 M481 — `agent_id` 可空 + 既有 FK CASCADE→SET NULL（落地 FR-7/FR-21/FR-26）

> **授权引注（FR↔SDD 映射自证；cycle 3 attempt 2 blocker 定点回修）**：本节的 FK 转换（既有约束 `chat_session_agent_id_fkey` 由 `ON DELETE CASCADE` → `ON DELETE SET NULL`）属已批 PRD 的**显式授权范围**，非 SDD 新引入的设计变更：
>
> - **授权段落 1 — PRD FR-7**（`prd.md` `## FR-7`，§3 功能需求，L127/L129）：「列级 NOT NULL 与既有 CASCADE FK 的改动由 481 迁移落地（FR-21）：Coordinator Agent 被 hard-delete 时 session/message 行必须保留（不得级联删除）、`agent_id` 由 FK 置 NULL（AC-31/AC-32 验收）」；
> - **授权段落 2 — PRD FR-21**（`prd.md` `## FR-21`，§3 功能需求，L234–L249）：将 481 迁移定为「**唯一允许的既有 FK 生命周期改动**（这是『转换既有约束』，不是新增 FK）」（L236/L238），并给出完整 `up` SQL（L241–L246：`DROP NOT NULL` → `DROP CONSTRAINT` → `ADD CONSTRAINT ... ON DELETE SET NULL`），与下方本节 SQL **逐字一致**；
> - **基线区分（防误读）**：PRD L74 出现的 `agent_id UUID NOT NULL REFERENCES agent(id) ON DELETE CASCADE` 位于 `## 1.4 当前代码事实（落笔前核实）` 基线表内，是 `033_chat.up.sql` **现状实现的引用**（现有实现基线描述），不是目标态；目标态以上述两个授权段落为准，二者不构成矛盾。

`481_chat_session_agent_nullable_set_null.up.sql`（同文件按序，与 PRD FR-21 给出的 SQL 一致）：

```sql
ALTER TABLE chat_session ALTER COLUMN agent_id DROP NOT NULL;
ALTER TABLE chat_session DROP CONSTRAINT chat_session_agent_id_fkey;
ALTER TABLE chat_session ADD CONSTRAINT chat_session_agent_id_fkey
    FOREIGN KEY (agent_id) REFERENCES agent(id) ON DELETE SET NULL;
```

- 约束名沿用 PostgreSQL 对 `033_chat.up.sql:7` 内联 FK 的自动命名；全量迁移核查确认 033 之后**无任何迁移引用**该约束或改写 `chat_session.agent_id` [D-03]，转换前提成立。
- `ADD CONSTRAINT` 不自动建索引；基线该列亦无独立索引，本 CR 不新增（PRD FR-21）。
- Agent hard-delete 时 DB 把 `agent_id` 置 NULL，session/message 行保留（AC-31/AC-32）。
- `down`：`DROP CONSTRAINT` → 重建 `ON DELETE CASCADE` → `SET NOT NULL`；最后一步在存在 NULL 行时失败，注释写明「先清理 NULL 行再回滚」（数据依赖回滚，不静默吞错）。

## 2.2 M482 — `chat_session.kind`（落地 FR-2）

`482_chat_session_kind.up.sql`：

```sql
ALTER TABLE chat_session
    ADD COLUMN kind TEXT NOT NULL DEFAULT 'private'
    CHECK (kind IN ('private', 'project_shared'));
```

存量行（1:1 与 Private Ask）经列默认值成为 `private`；ADD COLUMN 带常量默认不重写表。新 Private Ask / 1:1 插入继续走默认或显式 `private`（既有 `CreateChatSession` 无需改签名，sqlc 参数缺省即默认值）。

## 2.3 M483/M484 — Private Ask 唯一索引谓词收窄（落地 FR-6/FR-5）

`483_...drop.up.sql`：

```sql
DROP INDEX CONCURRENTLY IF EXISTS chat_session_project_creator_active_unique;
```

`484_...private_active_unique.up.sql`：

```sql
CREATE UNIQUE INDEX CONCURRENTLY chat_session_project_creator_active_unique
    ON chat_session (project_id, creator_id)
    WHERE project_id IS NOT NULL AND status = 'active' AND kind = 'private';
```

- **沿用原索引名**：代码中仅 `chat.sql:16` 注释与 sqlc 生成注释引用该名字 [D-04]，同名重建零代码联动；谓词加 `kind='private'` 即 PRD FR-6 的「收窄为仅 kind='private'」。
- 483→484 窗口内 Private Ask 并发 get-or-create 暂失唯一兜底：`GetProjectChatSessionForCreator` 的 `ORDER BY created_at DESC LIMIT 1` 保证读侧收敛，多余行不产生功能故障；484 落地后恢复唯一收敛。**窗口量化（上界）**：483/484 由同一次 `cmd/migrate up` 运行按版本序逐条应用（迁移循环持会话级 advisory lock、文件按版本排序后顺序执行，且在服务启动前跑完——`server/cmd/migrate/main.go`、`server/internal/migrations.Files`），故窗口仅存在于**同一 deploy batch 内**两条迁移之间，上界 = 迁移循环执行间隔 + 484 `CREATE INDEX CONCURRENTLY` 构建时长；该索引谓词窄、表小，构建秒级，正常情形远小于 5 分钟，取 **≤5 分钟**作为含重试的保守上界；不存在跨部署批次的长窗口。

## 2.4 M485 — shared session 每项目一个 active（落地 FR-3）

`485_chat_session_project_shared_active_unique.up.sql`：

```sql
CREATE UNIQUE INDEX CONCURRENTLY chat_session_project_shared_active_unique
    ON chat_session (workspace_id, project_id)
    WHERE kind = 'project_shared' AND status = 'active';
```

`chat_session.project_id` 为软引用（迁移 214，无 FK [D-05]），shared session 复用该列；项目删除走既有 `ClearChatSessionProjectByProject`（置 NULL）——置 NULL 行自动落出谓词，不产生悬挂唯一键。

## 2.5 M486 — `chat_message` 作者列（落地群聊展示与 merge-forward 署名）

`486_chat_message_author.up.sql`：

```sql
ALTER TABLE chat_message
    ADD COLUMN author_type TEXT,
    ADD COLUMN author_id UUID;
```

- 可空、无 FK（不变量 6：应用层校验）。存量 Private Ask / 1:1 行保持 NULL（creator-only 语义下作者恒为 creator，前端维持现状渲染，不回填）。
- 写入规则：`kind=project_shared` 的 `role=user` 消息写 `author_type='member', author_id=发送者`；assistant 回复（`writeChatCompletionOutcome` [D-11]）写 `author_type='agent', author_id=task.agent_id`；`kind=private` 路径**不写**（零行为变化，NFR-6）。
- merge-forward 署名直接读作者列；NULL 时退化为 `role` 字面（对齐 `commentAuthorDisplayName` 的 best-effort 语义 [D-20]）。

## 2.6 M487 — 幂等记录表（落地 FR-24）

`487_chat_idempotency.up.sql`：

```sql
CREATE TABLE chat_idempotency (
    workspace_id UUID NOT NULL,
    user_id      UUID NOT NULL,
    scope_type   TEXT NOT NULL CHECK (scope_type IN ('discussion_message', 'merge_forward_messages')),
    scope_id     UUID NOT NULL,      -- discussion_message: session_id; merge_forward_messages: project_id
    key          TEXT NOT NULL,      -- Idempotency-Key 原值（<=255B，入口已限长）
    fingerprint  TEXT NOT NULL,
    response_status INT NOT NULL,
    response_body   JSONB,           -- 事务提交前为占位（与消息/任务同事务写入）
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (workspace_id, user_id, scope_type, scope_id, key)
);
CREATE INDEX idx_chat_idempotency_created ON chat_idempotency (created_at);
```

- 无 REFERENCES（不变量 6）；`created_at` 普通索引供 24h sweeper 范围删（见 §4.6）。索引与建表分两个迁移文件（一文件一条索引语句）：`487` 建表，`488` 建 `idx_chat_idempotency_created`——**编号因此延伸到 488**，即本 CR 迁移区间为 **481–488**（PRD「481 起」的下界不变）。
- 收敛语义：同一 (workspace, user, scope, key) 的并发请求在 PK 上串行，算法见 §4.6。

# 3. 接口契约

HTTP 八项细节（精确状态码、错误体、幂等语义）以 PRD「Discussion HTTP 契约」「merge-forward HTTP 契约」为准（FR-22/FR-23 闭合口径）；本节给出服务端落点与类型。公共错误体沿用 `writeErrorCode`（`{code, error}`）[D-31]。

## 3.1 GET `/api/projects/{projectId}/discussion`（重写，落地 FR-1/FR-4/FR-16/FR-25/FR-26）

- 权限：`requireWorkspaceMember` [D-30]；非成员/已移出 → 403 `forbidden_project_discussion`（新 code，PRD FR-18 已列）；项目不在本 workspace → 404（现有 `project not found`，无 code）。
- 行为：`EnsureProjectDiscussionSession`（§4.1）创建或读取唯一 active `project_shared` session；**不调用** `EnsureProjectDiscussionIssue`（该服务函数保留但 GET 路径解除调用 [D-02]）。
- `legacy_issue_id`：`GetProjectDiscussionIssue` **只读**查询 [D-34]，有则 UUID，无则 `null`；GET 不插入、不补建。
- `coordinator_agent_id`：settings 原值（失效也回原 UUID；未配置为空串），规则见 §4.5。
- 配置字段：`ResolveChatConfig(base, override, agentDefault=pgtype.Text{})`——shared 路径恒传无效 `agentDefault`，`agent_default` source 不可能出现（FR-8/PRD GET 契约）[D-17]。

```go
type ProjectDiscussionResponse struct {
    SessionID           string  `json:"session_id"`
    IssueID             *string `json:"issue_id"`        // 恒 nil（JSON null）
    LegacyIssueID       *string `json:"legacy_issue_id"` // 只读回放身份
    CoordinatorAgentID  string  `json:"coordinator_agent_id"`
    Model               string  `json:"model"`
    ThinkingLevel       string  `json:"thinking_level"`
    ModelSource         string  `json:"model_source"`          // override|session_default|runtime_default
    ThinkingLevelSource string  `json:"thinking_level_source"`
}
```

## 3.2 PATCH `/api/chat/sessions/{sessionId}/config`（kind 分流，落地 FR-9/FR-5）

`PatchChatSessionConfig` [D-14] 加载 `GetChatSessionInWorkspace` 后按 `session.Kind` 分流：

- `kind=private`：**逐行保持**现行为（creator-only 403 `forbidden_chat_config`；无 `project_id` 的 1:1 → 404 `chat_session_not_found`；agent provider/catalog 校验）。
- `kind=project_shared`：
  - 门禁：当前 workspace 成员（否则 404 `chat_session_not_found`，FR-17）；PATCH 另需 `requireWorkspaceRole(owner|admin)` [D-30]，非 owner/admin 成员 → 403 `forbidden_chat_config`。
  - 会话状态：`status≠active` → 409 `chat_session_closed_or_changed`；kind/项目不符 → 404。
  - 校验：有可路由 Coordinator 时，按其 runtime 走 `LoadChatCatalogForConfig` + `ValidateResolvedChatConfig`（与现 Private Ask 同一实现，禁止第二套 [D-17]）；**无 Coordinator 时不存在可加载 catalog，PATCH 接受 override 落库、不做目录校验**，校验推迟到协办入队（§4.4，决策 D-6）。
  - 写入：`LockChatSessionInWorkspace` [D-07] 下三态写 override（复用 `parseChatConfigFieldPatch`）；无 Coordinator 不走「创建者 Agent」路径、绝不调用 `UpdateAgent`（FR-9）。
  - 已入队 task 不受影响（快照已在 `task.context`，FR-11/FR-26 表）。

## 3.3 GET 消息列表（落地 FR-22）

`ListChatMessages` 与 `ListChatMessagesPage` [D-16] 同样按 `kind` 分流：

- `kind=private`：裸数组 / 分页对象各自保持现状。
- `kind=project_shared`：两个 endpoint **同语义**，一律返回 `ChatMessagesPageResponse` 分页对象（`messages/limit/has_more/next_cursor`），绝不裸数组；门禁为成员级（非成员/错 kind/跨项目 → 404 `chat_session_not_found`）；已归档 session → **200 只读**。
- 分页解析复用 `parseChatMessagesPageParams`；shared 路径错误改为 `writeErrorCode(..., "invalid_cursor", ...)`（`limit` 越界、`before_created_at`/`before_id` 缺一半 → 400 `invalid_cursor`）。
- SQL 复用 `ListChatMessagesPage`（session 作用域 + `message_kind != 'channel_command'` + (created_at,id) 游标）[D-09]；页内反转保持时间正序（现有行为）。

## 3.4 POST `/api/chat/sessions/{sessionId}/messages`（kind 分流 + 幂等，落地 FR-10/FR-11/FR-15/FR-17/FR-24）

`SendChatMessage` [D-15] 前置加载后按 `kind` 分流；`kind=project_shared` 委托 `SendDiscussionMessage`（§4.2）。输入校验（400 `invalid_discussion_message`，零写入）：

- `content` trim 后为空 且 `attachment_ids` 缺省/空 → 拒绝；
- `attachment_ids` 重复 → 拒绝（不静默去重）；非 UUID → 现有 `parseUUIDSliceOrBadRequest` 400；
- `coordinator_request ∈ {none, mention, analyze, summarize}`，缺省 `none`，非法枚举拒绝；
- 缺 `Idempotency-Key` → 400 `idempotency_key_required`；>255B → 400（`MaxIdempotencyBytes` [D-29]）。

成功 **201**，响应体：

```go
type DiscussionSendResponse struct {
    SessionID string  `json:"session_id"`
    MessageID string  `json:"message_id"`
    IssueID   *string `json:"issue_id"` // 恒 nil
    TaskID    *string `json:"task_id"`  // 普通消息 nil；协办为 task UUID
}
```

## 3.5 POST `/api/projects/{id}/chat/merge-forward`（message_ids 扩展，落地 FR-13/FR-23/FR-24）

互斥/选择校验与错误码全按 PRD「merge-forward HTTP 契约」：`invalid_merge_forward_selection` / `invalid_message_selection` / legacy `invalid_comment_selection` 不变。实现：

- `message_ids` 路径：逐条 `GetChatMessageInWorkspace`（新 sqlc 查询：`id + workspace_id`）校验「同属本项目唯一 active/已归档 `project_shared` session」（跨 session/跨项目/`kind=private`/普通 Issue → 400）；重复 id 按首次出现去重（与 comment 路径一致）；去重后 1–50。
- 渲染：新增 `buildMergedForwardContentFromMessages(ctx, taskSvc, msgs []db.ChatMessage, registerCR bool)`——结构对齐 `buildMergedForwardContent`（Trigger message + Conversation history + 可选 registerCR 块）[D-20]，署名改读作者列（§2.5）；**不**抽公共接口泛化，legacy comment 路径保持字节级不变。
- 内核：仍调 `sendProjectChatCore`（零改动，NFR-7）；`message_ids` 路径要求 `Idempotency-Key`（scope_type=`merge_forward_messages`，scope_id=project_id），legacy `comment_ids` 路径不要求（PRD FR-24）。
- 权限：成员 + 既有 Team Agent 发送权限（presenter 规则在内核内，零改动）；非成员 → 403 `forbidden_project_discussion`。

## 3.6 其余 session 级 endpoint 的 kind 闭合（接口闭包，SDD-CLOSE-04）

`/api/chat/sessions/{sessionId}/*` 现全部按 creator 门禁 [D-15]。`kind=project_shared` 统一规则：

| 类别 | endpoint | project_shared 行为 |
|---|---|---|
| 读 | `GET /`、`GET /pending-task`、`GET /draft-restores`、`POST /read` | 当前 workspace 成员（非成员 404 `chat_session_not_found`） |
| 轻量写 | `PATCH /`（title）、`PATCH /pin`、`PATCH /archive` | owner/admin（否则 403 `forbidden_chat_config`） |
| 删除 | `DELETE /` | 拒绝：403 `forbidden_chat_config`（「project shared session 不可删除」；历史保留是 FR-16 语义） |
| 其余 | `/quick-actions/*`、`/queued-tasks`、`/onboarding` | 不适用/不改：quick-actions 与 onboarding 是 Private Ask 面，shared 会话不产生该请求（前端不渲染）；`/queued-tasks` 成员可读 |

该表是 FR-17「不得落到 Private Ask 行上 / 不得静默另开 session」的完整闭包：任何携带 `kind=project_shared` 的请求都不进入 creator-only 分支，任何携带 `kind=private` 的请求都不进入成员分支。

## 3.7 实时事件契约（落地 FR-20）

`events.Event` 新增字段（`server/internal/events/bus.go` [D-25]）：

```go
// ChatSessionKind mirrors chat_session.kind at production time. Realtime
// routing uses it to fan shared-session events out to the workspace room.
// Producers MUST set it together with ChatSessionID; the bridge treats an
// empty value as private (fail-closed toward the narrower delivery).
ChatSessionKind string
```

- 路由规则（`listeners.go` [D-24]）：`ChatSessionID != ""` 时，`ChatSessionKind == "project_shared"` 且 `WorkspaceID != ""` → `BroadcastToWorkspace`；否则维持现状（要求 `ChatRecipientID`，`SendToUser`，缺失即丢弃并 ERROR 日志——fail-closed 不变）。
- 生产端：`publishChat` 增 kind 参（调用点 `chat.go`/`chat_title.go`/`mika_onboarding.go` 全部传 `private`，行为不变）[D-27]；`daemon.go` task 流式帧与 `service/task.go` 的 4 处任务事件按 session kind 填 [D-26][D-28]。kind 解析复用会话加载（各生产端本已读 session 行，无新增 DB 往返；`service/task.go` 的 `ChatSessionCreatorID` 辅助扩展为同时返回 kind）。

# 4. 关键算法与流程

## 4.1 EnsureProjectDiscussionSession（落地 FR-1/FR-3/FR-8/FR-16）

```text
tx begin
  LockIssueDuplicateKey("project-discussion-session|{ws}|{project}")   // 专用前缀，与 team-agent 前缀隔离（D-9）
  project ← GetProjectInWorkspace(锁内重读)
  coordinatorUUID ← settings.discussion_coordinator_agent_id
  session ← GetActiveProjectSharedSession(ws, project)                 // 新查询：kind+status 过滤
  if 无:
      base_model/base_thinking ← 可路由 Coordinator ? SnapshotAgentDefaults(agent) : NULL
      InsertProjectSharedSession(ws, project, agent_id=可路由?UUID:NULL,
                                 creator_id=caller, kind='project_shared', base_*)
      唯一索引冲突(并发首开) → 锁内 reselect（与 EnsureProjectChatSession 同构 [D-19]）
  legacyIssueID ← GetProjectDiscussionIssue(只读, 事务外亦可)
  view ← ResolveChatConfig(base, override, agentDefault=无效) + coordinator 原值
commit
```

- 并发 GET 收敛：advisory + M485 部分唯一索引双保险（与 436 注释描述的 Private Ask insert-conflict+reselect 模式同构）。
- 仅有已归档 shared session 时：本流程新建 active 行（M485 谓词含 `status='active'`，不冲突），不自动解档（PRD GET 契约幂等行）。
- 纯人类 Discussion：无 Coordinator 时 `agent_id=NULL` 合法（M481 后）；不要求任何 Agent 存在。

## 4.2 SendDiscussionMessage 事务（落地 FR-10/FR-11/FR-12/FR-15/FR-17/FR-24）

形态对齐 `SendDirectChatMessage`（事务内 task+消息+附件原子提交、提交后才通知/广播 [D-13]），但无 channel/quick-actions 分支：

```text
pre-tx: 头/体校验（§3.4）；成员门禁（非成员 → 404）
tx begin
  advisory "project-discussion-session|{ws}|{project}"
  session ← LockChatSessionInWorkspace(sid, ws) FOR UPDATE [D-07]
      不存在/跨项目/kind≠project_shared → 404 chat_session_not_found
      status≠active → 409 chat_session_closed_or_changed
  idem ← INSERT chat_idempotency(fingerprint, response_body=NULL) ON CONFLICT DO NOTHING
      冲突 → 读赢家行（MVCC：并发未提交则 ON CONFLICT 阻塞至其提交/回滚）
          指纹同 → 直接返回其 response_body（201 重放，事务只读回滚）
          指纹异 → 409 idempotency_key_reused（零写入）
  trigger ← detectCoordinatorTrigger(content, coordinator_request, 可路由 Coordinator)   // §4.3
      需要协办且未绑定 → 409 discussion_coordinator_not_configured
      已绑定不可路由   → 409 discussion_coordinator_unavailable
      需要协办且调用者无 invocation 权限 → 403（复用 canInvokeAgent/ReasonInvocationNotAllowed，不新造枚举）
  message ← InsertChatMessage(session, role=user, content, task_id=NULL,
                              author_type='member', author_id=caller)                    // M486
  if trigger.needTask:
      resolved ← ResolveChatConfig(session, agentDefault=无效)
      context ← mergeChatConfigContext(nil, resolved.Model, resolved.ThinkingLevel)      // 单一 merge 缝 [D-12]
      task ← CreateChatTask(agent=可路由 Coordinator, runtime=其 runtime_id, issue_id=NULL,
                            priority=2, chat_session_id=sid, initiator/originator/accountable=caller,
                            originator_source/trigger_evidence 同 chat 路径签章, Context=context)  // [D-08]
      UPDATE chat_message SET task_id = task.id WHERE id = message.id
  attachments:
      LockUnboundDraftAttachments(ws, ids)            // 现有锁序 [D-10]
      bound ← BindDraftAttachmentsToChatMessage(ws, ids, session_id, message_id, task_id?) // 新查询，见下
      len(bound) < len(ids) → 409 attachment_already_bound
  UPDATE chat_session SET updated_at = now()
  UPDATE chat_idempotency SET response_body=…, response_status=201（同事务）
commit
post-commit: publishChat(EventChatMessage, kind=project_shared)（workspace 广播）
             协办时再发 task:queued（kind 标注）+ NotifyTaskEnqueued（daemon 唤醒）
```

新 sqlc 查询 `BindDraftAttachmentsToChatMessage`（`attachment.sql`）：对已锁行写 `chat_session_id/chat_message_id/task_id(可空)`，WHERE 保持五类绑定全空 + `source_context_id IS NULL` + uploader=调用者，`RETURNING id`——与 `BindUnboundDraftAttachments`（issue/comment/task 三靶）同构 [D-10]；不复用 `LinkAttachmentsToChatMessage`（其允许 `chat_session_id` 已等于目标且不写 `task_id`，语义不满足 FR-15 协办绑定）。

协办回复：`writeChatCompletionOutcome` 按 `task.ChatSessionID` 写 assistant 行 [D-11]——shared session 的回复**自动**落回同一 session（FR-12），仅需在该写路径补作者列（§2.5）；执行/重试读 `task.context.chat_config`（既有 claim 行为，零改动）。

## 4.3 detectCoordinatorTrigger（落地 FR-11）

```text
输入: content, coordinator_request, routable(可路由 Coordinator, 可空)
1. coordinator_request ∈ {analyze, summarize} → needTask=true（优先于 mention 推导）
2. 否则 mentions ← util.ParseMentions(content) [D-22]
   - 命中 type=agent 且 id == 当前可路由 Coordinator → needTask=true
   - @mention 其它 Agent → 非协办（走普通消息，FR-11 末句）
3. coordinator_request=mention 且正文含 Coordinator @mention → 仍只建一个 task（1/2 同源）
4. 无 Coordinator 绑定时：1/2 任一命中 → 409 not_configured（由调用方映射）
```

旧 comment 触发路径 `handleDiscussionContainerMentionTrigger` [D-23] **不删不改**：新消息不再写 comment，该路径对存量只读容器不再有新增触发面；保留以兼容任何遗留写入路径。

## 4.4 配置写入（有/无 Coordinator 两分支）

```text
有可路由 Coordinator:
    provider ← coordinator.runtime.provider; catalog ← LoadChatCatalogForConfig(coordinator)
    ValidateResolvedChatConfig(resolved after patch) → 400 invalid_model_or_thinking_level（AC-10）
无 Coordinator:
    无 catalog 可加载 → 接受 override 落库（FR-8「没有 Coordinator 时仍可保存配置」）
    校验推迟：协办入队（§4.2）时对 resolved 值做同一校验 → 400
```

两分支都**不**调用 `UpdateAgent`、**不**改 Agent 行（AC-9）。

## 4.5 Coordinator 写权威、投影与生命周期（落地 FR-7/FR-26）

settings PATCH（`project.go` coordinator 分支 [D-18]）扩展：

```text
值类型分派（三态）:
  非空字符串 → 现有校验（本 workspace Agent 存在，否则 400）→ 绑定/替换
  null 或 ""  → 新增清除分支：从 settings bag 删除 key（FR-26 解绑）
  其它类型    → 400（现状）
绑定/替换/解绑统一走新服务函数
  UpdateProjectSettingsWithDiscussionCoordinator(ws, project, newUUID|空, patch):
    tx begin
      LockIssueDuplicateKey("project-discussion-session|{ws}|{project}")   // 与 GET/发送同一把锁
      写 settings（先写权威）
      session ← GetActiveProjectSharedSession(锁内)
      if session 存在:
          首次绑定且 base_* 全 NULL → 补写 SnapshotAgentDefaults(新 Agent)（FR-26 表）
          UPDATE session.agent_id = 新值或 NULL（投影；替换不重取 base_*，不清空）
    commit
```

- 与 Team Agent 的 `UpdateProjectSettingsWithTeamAgentRebind`（关旧会话建新的 [D-35]）**刻意不同**：Discussion 历史必须留在同一 session，投影 in-place（决策 D-5）。
- GET 侧自愈：`EnsureProjectDiscussionSession` 锁内发现 `session.agent_id` 与可路由解析不一致时，先修复再返回（FR-26 竞态规则 4）。
- Agent 归档/移出 workspace：settings 保留原 UUID、GET 原样回；投影为 NULL（不可路由）；新协办 409 `discussion_coordinator_unavailable`（AC-31）。
- Agent hard-delete：M481 FK `ON DELETE SET NULL` 在 DB 层置空 `session.agent_id`，session/message 保留；GET `coordinator_agent_id` 仍回 settings 原 UUID（AC-32）。

## 4.6 幂等收敛（落地 FR-24/NFR-4）

- 指纹：`POST messages` = trim(content) + 排序去重前的原始 `attachment_ids` 序列化（重复已在校验期 400）+ `coordinator_request`；merge-forward = 去重后顺序保留的 `message_ids` + `register_cr`。指纹为规范 JSON 的 sha256 hex。
- 并发：PK `(ws,user,scope,key)` + `ON CONFLICT DO NOTHING`；PostgreSQL 对唯一冲突的等待语义保证并发同 key 串行见到已提交赢家 → 同指纹重放 / 异指纹 409，**恰好一次提交**。
- 赢家事务回滚时其行不可见，输家插入成功——无死锁残留。
- 重放不重新执行副作用：直接回存储的 `{status, body}`，已绑定附件不再进入绑定路径（不会 409 `attachment_already_bound`，AC-26）。
- 保留：`SweepChatIdempotency` 每小时删 `created_at < now()-24h`（严格：恰好 24h 的行本轮保留，语义与 `SweepChatDraftAttachments` 的 168h 边界一致 [D-33]）。**口径澄清**：PRD FR-24「记录至少保留 24h」取**保留下限**语义——sweeper 只删严格超过 24h 的行，实际保留时长 ∈ [24h, 25h)（每小时清扫一次）；本 CR 实现为**固定 24h 阈值、不引入可配置保留期**，可配置化如有需要属后续事项（见 §9 follow_up ⑤）。

## 4.7 实时投递与移出退订（落地 FR-20/FR-25/AC-29）

- shared 事件走 `BroadcastToWorkspace`（hub 房间按连接建立时的成员资格进入，`HandleWebSocket` 逐连接 `MembershipChecker.IsMember` [D-28]）——「当前 workspace 成员可见」由连接级成员资格 + 请求级门禁共同成立。
- Private Ask 投递逐字节不变（kind 缺省 → 原 fail-closed recipient 路径）。
- 移出 workspace：`revokeAndRemoveMember` [D-31] 事务提交后新增一步——调用 `realtime` 新方法 `DisconnectWorkspaceUser(userID, workspaceID)`（hub 遍历该用户连接，关闭属于该 workspace 的连接并清理房间；多服务器经既有 relay 广播断连指令）。连接被断后：重连走 `IsMember` → 拒绝；后续广播自然不达。该成员已订阅的 scope（若客户端启用）同断。

## 4.8 已发送附件下载门禁（落地 FR-25 表）

`loadAttachmentForRequest` [D-32] 现按上传者门放行未绑定草稿；扩展：附件 `chat_session_id` 非空且所属 session `kind=project_shared` 时，放行条件改为「当前 workspace 成员」（非成员 → 404，不确认存在）；`kind=private` 与未绑定草稿行为不变。

## 4.9 迁移与部署顺序

481 → 482 → 483 → 484 → 485 → 486 → 487 → 488（编号即部署序）。服务端 kind 分流代码在 482 之后生效；482 落地但代码未上线期间不存在 `project_shared` 行（无创建者），窗口安全。sqlc：新/改查询后 `make sqlc` 再生成（不变量 5，生成文件不手改）。`CUSTOM.md` 登记（编号顺延）：481–488 迁移、`discussion_session.go`、handler kind 分流、settings 清除分支、事件 kind 字段与路由、hub 断连、幂等表与 sweeper、新绑定查询、前端 discussion-pane 与 schema。

# 5. 技术选型与替代方案（决策记录）

**D-1 承载表：`chat_session` 加 `kind` vs 新建 `discussion_session` 表** — 选前者（PRD FR-2/NFR-3 已拍板）。替代方案需要第二套消息/附件/事件管道；代价是 `kind` 分流侵入既有 chat handler，以 §3.6 闭包表控制风险。

**D-2 FK 生命周期：CASCADE→SET NULL vs 删 FK+纯应用层校验** — 选 SET NULL（PRD FR-21 已按评审推荐拍板）。保留 DB 级引用完整性；应用层方案在 hard-delete 并发下需自己保证不悬挂。

**D-3 Private Ask 唯一索引：同名收窄重建 vs 新名** — 同名（§2.3）。代码仅注释引用；新名徒增对照成本。替代方案的代价：436 注释与生成文件注释需联动改名，无收益。

**D-4 实时路由：生产端携带 `ChatSessionKind` vs listener 按 session_id 查库** — 生产端携带。listener 查库给每个事件加 DB 往返且与「事件层不重反序列化」的 scope-hint 设计相悖；fail-closed 缺省（kind 空 → 原 recipient 路径）保证漏填不泄漏。

**D-5 Coordinator 重绑：in-place 投影 vs Team Agent 式关旧建新** — in-place。Discussion 单一 session 承载全部历史（FR-16/FR-26 表），关旧建新会切断回放并违反「每项目一个 active」。

**D-6 无 Coordinator 配置校验：接受 override、推迟到入队校验 vs 拒绝保存** — 接受。FR-8 明确「没有 Coordinator 时仍可保存配置」；无 agent 即无 runtime/catalog，目录校验在物理上不可执行，拒绝保存与需求直接冲突。代价：非法值可在配置态停留至首次协办（409/400 在入队点暴露，AC-10 的入队分支覆盖）。

**D-7 幂等存储：专用 `chat_idempotency` 表 vs 复用现有存储** — 专用表。现有仅头常量基建（无存储）[D-29]；内存方案不满足重启后 24h 保留。

**D-8 作者归属：`chat_message` 加可空作者列 vs 渲染期推导** — 加列。shared 会话多发送者，推导只能得到 session creator（错误归属）；列在插入时即真。

**D-9 Discussion advisory 前缀独立（`project-discussion-session`）vs 复用 team-agent 前缀** — 独立。两类会话生命周期无关，共用前缀会让无关操作互相串行。

**D-10 merge-forward 消息渲染：平行函数 `...FromMessages` vs 泛化公共接口** — 平行函数。legacy comment 路径字节级不变是 NFR-6 硬要求；泛化需同时改两路、扩大回归面。

# 6. FR/AC 映射与 SDD-CLOSE

## 6.1 FR → 技术实现映射

| FR | 技术落点 |
|---|---|
| FR-1 | §3.1 GET 重写；`EnsureProjectDiscussionIssue` 解除调用 [D-02]；无其它 `origin_type='project_discussion'` 写入路径 |
| FR-2 | §2.2 M482 kind 列；CHECK 枚举；存量默认 `private` |
| FR-3 | §2.4 M485 部分唯一索引 + §4.1 advisory 收敛 |
| FR-4 | §3.1/§4.2 门禁一律成员资格；`creator_id` 仅审计列；消息查询不按 creator 过滤 |
| FR-5 | §2.3 M483/M484 谓词收窄 + `GetProjectChatSessionForCreator` 加 `kind='private'` 过滤（§6.3 SDD-CLOSE-09，三处调用点 [D-06] 语义全部保持）+ §3.6 闭包表 |
| FR-6 | §2.3（同 FR-5 的索引改写）+ §2.4 |
| FR-7 | §2.1 M481 + §4.1/§4.5 NULL 合法 + INNER JOIN agent 查询盘点：均为 agent 作用域路径（builder 列表/系统 runtime/creator 待办），不被 NULL 带崩、不参与 Discussion 查询 |
| FR-8 | §3.1 base_* 快照规则 + §4.4 无 Coordinator 分支 |
| FR-9 | §3.2 kind 分流；`ResolveChatConfig`/`ValidateResolvedChatConfig`/`LoadChatCatalogForConfig` 单一实现复用 [D-17] |
| FR-10 | §4.2 普通消息只写 `chat_message`（无 task/Issue/comment） |
| FR-11 | §4.2/§4.3 触发判定 + `CreateChatTask(issue_id=NULL)` [D-08] + `mergeChatConfigContext` 快照 [D-12] + 两个 409 + invocation 403 复用 |
| FR-12 | §4.2 末：`writeChatCompletionOutcome` 按 `task.ChatSessionID` 写回 [D-11]；重试读 `context.chat_config`（既有 claim 行为） |
| FR-13 | §3.5 message_ids 路径 + `RouteDiscussionToTeamAgent` 触发源改为 shared 消息（入参适配，内核不动）[D-21]；KG-1/KG-2 明示不修 |
| FR-14 | 复用 CR-2026-056 草稿契约：五空上传、上传者门（`loadAttachmentForRequest` 不变部分）、168h sweeper 谓词不改 [D-33] |
| FR-15 | §4.2 同事务绑定（`BindDraftAttachmentsToChatMessage`）+ 失败零残留 + 草稿保留重试 |
| FR-16 | §3.1 `legacy_issue_id` 只读 [D-34]；不双写、不删除、不补建 |
| FR-17 | §3.2/§3.4/§3.6 固定状态映射表（404/409/200 只读）+ `LockChatSessionInWorkspace` 锁内复验 [D-07] |
| FR-18 | 全部 code 落点：§3.1–§3.5 + `writeErrorCode`/`writeProjectChatSendError` [D-31][D-21]；legacy `invalid_comment_selection` 不动 |
| FR-19 | 前端：schema 重写（`session_id` 硬降级只读）、discussion-pane session 身份、legacy 只读流、配置控件走 PATCH config（不 `UpdateAgent`） |
| FR-20 | §3.7 事件 kind 字段 + §4.7 路由与退订 |
| FR-21 | §2.1 M481（SQL 与 PRD 逐字一致）+ §4.9 编号/CONCURRENTLY/CUSTOM.md/英文注释 |
| FR-22 | §3.1–§3.4 八项闭合（精确状态 + code + 权限 + 幂等 + 副作用 + 观察点引 PRD 表） |
| FR-23 | §3.5 修改契约闭合（互斥/空/重复/顺序/跨 session/权限/幂等） |
| FR-24 | §2.6 M487/488 + §4.6 收敛算法 + §3.4/§3.5 缺头/冲突错误 |
| FR-25 | §3.1/§3.2/§3.4 成员门禁 + §4.7 实时拒绝/退订 + §4.8 附件 404 + 草稿仍仅上传者 |
| FR-26 | §4.5 写权威/投影/读规则/竞态/归档/hard-delete 全表落地 |

## 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §3.1 GET 重写；`EnsureProjectDiscussionIssue` 调用移除 | GET 后 `issue` 表无新 `origin_type='project_discussion'` 行；响应 `issue_id=null`、无历史则 `legacy_issue_id=null` | GET 是面板唯一入口，无其它创建路径（代码级核查） |
| AC-2 | §4.2 事务无 Issue 写入；§4.5 绑定/解绑无 Issue | 四类操作后 `issue` 行计数不变 | 发送/绑定路径全部经新服务函数，无旁路 |
| AC-3 | §4.2 普通分支不调 `CreateChatTask` | 响应 `task_id=null`；`agent_task_queue` 无新行 | 触发判定为唯一 task 入口（§4.3） |
| AC-4 | §4.2/§4.3 task 参数 | `chat_session_id=sid`、`issue_id` NULL、`context.chat_config` 存在 | 协办分支在同一事务写，提交即可查 |
| AC-5 | §4.2 末 `writeChatCompletionOutcome` [D-11] | assistant `chat_message.chat_session_id=sid`；session 无对应 Issue | 回复路径只读 `task.ChatSessionID` |
| AC-6 | §4.2 成员门禁 + §3.6 闭包 + §3.2 private 分支不变 | 成员 B 见 A 的 shared 消息；B 的 Private Ask 对 A 403/404 不变 | 两条门禁互不交叉（kind 分流） |
| AC-7 | §3.1 只读查询 [D-34]；新消息不写 comment | 旧 Issue comment 流冻结在切换点 | 无任何双写代码路径 |
| AC-8 | §2.3/§2.4 索引 + §4.1 锁 | 并发首开仅 1 行 active shared；同 creator 的 Private Ask 并存 | 两个谓词互斥（`kind` 区分），并发由 advisory 串行 |
| AC-9 | §3.2 角色门禁 + §4.4 不调 `UpdateAgent` | 非 owner/admin 403 `forbidden_chat_config`；`agent.model/thinking_level` 不变 | 门禁在 provider 解析之前（错误序与现 Private Ask 一致） |
| AC-10 | §4.4 有 Coordinator 分支 + §4.2 入队校验 | PATCH/入队 400 `invalid_model_or_thinking_level`；已入队 `chat_config` 不变 | 校验在事务前/事务内两处，覆盖两个时点；命令 `go test ./server/internal/handler/ ./server/pkg/agent/ -count=1` |
| AC-11 | §4.3/§4.2 未绑定分支 | 409 `discussion_coordinator_not_configured`；无 task/Issue | 触发判定先于任何写入 |
| AC-12 | 复用 CR-2026-056 草稿门（§4.8 不变部分） | 非上传者下载/列表/流均不可见 | 未绑定行五空谓词不变 |
| AC-13 | §4.2 `BindDraftAttachmentsToChatMessage` | 成功行 `chat_session_id/chat_message_id`（+协办 `task_id`）非空；失败五空可重试 | 绑定与消息同事务，回滚即全空 |
| AC-14 | §2.1 M481 + §4.1/§4.5 | 无 Coordinator GET/发送成功、`agent_id` 空；绑定后可协办；解绑回空、历史可读 | NULL 合法贯穿查询（无 INNER JOIN 阻挡，FR-7 盘点） |
| AC-15 | §3.5 message_ids 路径 | 201 + Team Agent 侧一对 comment/task；源消息不动；legacy 路径与原 400 不变 | 两路径代码分离，legacy 字节级保留 |
| AC-16 | §3.5 内核复用 `sendProjectChatCore`（zero_diff） | 转投仍走既有内核；本 CR diff 不含该函数 | diff 审查 + 既有内核测试全绿 |
| AC-17 | 前端 schema 硬降级（`session_id` 缺失/空/非 UUID → 只读） | `packages/core/api/schemas.test.ts` 用例；`legacy_issue_id` 不参与发送 | schema 是响应唯一解析入口（NFR-8） |
| AC-18 | discussion-pane session 身份 + 四语 key | pane 不依赖可写 `issue_id`；`parity.test.ts` 全绿 | 文案经 locales 单一出口 |
| AC-19 | §2.1–§2.6 + §4.9 | `pg_get_constraintdef` 见 `ON DELETE SET NULL`；down 往返全绿；索引全 `CONCURRENTLY` 一文件一条；`CUSTOM.md` 登记 | 迁移测试直查约束定义；481 前提已核（无后续引用 [D-03]） |
| AC-20 | §3.2/§3.4 状态映射 + §3.3 归档只读 200 | 成员对归档 session PATCH/POST 409；错 kind/跨项目/非成员 404；列表仍 200 | 映射集中在一个分流函数，无二义分支 |
| AC-21 | §3.2/§4.2 只调 `ResolveChatConfig`/`LoadChatCatalogForConfig` [D-17] | 测试不出现第二套规则表 | 单一实现函数签名不变，新调用点只是新 caller |
| AC-22 | §3.6 闭包 + NFR-6/7 零改动面 | Team Agent GET 仍不建 Issue；Private Ask 夹具全绿；`go test ./server/internal/handler/ ./server/internal/service/ -count=1` 无新增无关失败 | private 分支逐行保留，回归基线可比 |
| AC-23 | §3.3 shared 恒分页对象 | 无 cursor 200 分页对象；`limit=0`/半截 cursor → 400 `invalid_cursor`；页内 `created_at` 非递减 | SQL 取降序窗、序列化前反转（现有 `ListChatMessagesPage` 行为） |
| AC-24 | §3.4 输入校验 | 空/重复/非法枚举 400 `invalid_discussion_message` 零写入；仅附件 201 且 `task_id=null`；成功恒 201 | 校验在事务前，拒绝即零副作用 |
| AC-25 | §3.5 互斥/选择校验 | 双非空 400 `invalid_merge_forward_selection` 且 Team Agent 侧零新行；跨源 400 `invalid_message_selection`；重复只合并一条 | 校验先于内核调用；去重与 comment 路径同语义 |
| AC-26 | §2.6/§4.6 | 缺头 400 零写入；同指纹重放两次 201 同 id、附件不 409、DB 单条；异指纹 409 零写入；并发单次提交 | PK 冲突收敛由数据库唯一性保证（§4.6） |
| AC-27 | §3.5 message_ids 幂等 | 缺头 400；重放 201 同 `comment_id/task_id`；legacy 无头仍 201 | 幂等仅挂 message_ids 分支 |
| AC-28 | §3.1 403 + §3.2/§3.4 404 + §4.8 附件 404 | 非成员：项目路径 403 `forbidden_project_discussion`、session 路径 404、附件 404 无字节；移出 workspace 即时同效 | 门禁读 `member` 表实时资格，无历史缓存 |
| AC-29 | §4.7 断连 + 拒绝重连 | 非成员/移出者订阅被拒；移出后不再收到；成员 B 不受影响；`go test ./server/internal/handler/ ./server/internal/service/ -count=1` | 断连挂接 `revokeAndRemoveMember` 事务后钩子 [D-31] |
| AC-30 | §4.5 投影事务 | 首绑 settings=session.agent_id 同值、空 `base_*` 补写；替换只动 `agent_id`、已入队不变；解绑回空、历史可读 | 写权威与投影同一事务同一锁，无分叉窗口 |
| AC-31 | §4.5 归档行 + §4.3 409 | GET 仍回原 UUID；新协办 409 `discussion_coordinator_unavailable` 零写入；settings 不被清；并发后投影一致 | 读规则 1–3 集中在一个解析函数 |
| AC-32 | §2.1 SET NULL + §4.5 hard-delete 行 | agent 行删后 session/message 全保留、`agent_id` NULL、GET 回 settings 原值、回放 200、新协办 409 零写入 | FK 在 DB 层执行，无应用层竞态窗口 |

## 6.3 SDD-CLOSE（PRD 延后项逐项关闭）

| 编号 | PRD 延后项 | 关闭结论 |
|---|---|---|
| SDD-CLOSE-01 | FR-24 幂等记录存储（「仅有头常量基建」） | §2.6 `chat_idempotency` 表（487/488）+ §4.6 PK 冲突收敛 + 24h sweeper；指纹定义、重放语义、并发收敛全部落地 |
| SDD-CLOSE-02 | FR-20 kind 感知多成员实时投递（「设计工作」） | §3.7 `Event.ChatSessionKind` + §4.7 路由/断连；fail-closed 缺省保持 private 语义 |
| SDD-CLOSE-03 | 群聊作者归属（`chat_message` 无作者列） | §2.5 M486 作者列 + 写入规则（§2.5/§4.2）+ merge-forward 署名消费（§3.5） |
| SDD-CLOSE-04 | FR-17/FR-22 session 身份与接口闭包 | §3.1–§3.4 + §3.6 全 endpoint kind 分流表；固定错误映射无二义分支 |
| SDD-CLOSE-05 | FR-23 merge-forward 修改契约 | §3.5 + §4.2（幂等复用）；八项全闭合，legacy 零变化 |
| SDD-CLOSE-06 | FR-26 解绑/投影数据模型 | §4.5 settings 三态清除分支 + 锁内投影事务 + 归档/硬删生命周期 |
| SDD-CLOSE-07 | FR-8/FR-9 无 Coordinator 配置边界 | §4.4 + 决策 D-6：接受保存、入队校验，与「仍可保存」一致 |
| SDD-CLOSE-08 | FR-21/FR-6 迁移序列 | §2.1–§2.6 + §4.9：481–488 全序列、CONCURRENTLY 窗口说明、down 数据依赖注记 |
| SDD-CLOSE-09 | FR-5 `GetProjectChatSessionForCreator` 泄漏点 | 查询加 `AND kind = 'private'`；三调用点（`project_chat.go:343/378`、`autopilot.go:990` [D-06]）语义全部保持——它们都只要 Private Ask |
| SDD-CLOSE-10 | FR-16 legacy 回放身份 | §3.1 `legacy_issue_id`（只读 `GetProjectDiscussionIssue`，不补建） |

# 7. 安全与性能考量

## 7.1 安全

- **授权模型**：请求时 `member` 表实时资格（无缓存旁路）；session 路径对非成员一律 404（不确认存在）；项目路径 403。`creator_id` 永不作 ACL（FR-4）。
- **UUID 猜测**：`GetChatSessionInWorkspace` 强制 `workspace_id` 谓词 [D-07]；shared 附件下载 404；实时连接经 `IsMember` [D-28]。
- **fail-closed 实时**：kind 缺省/未知 → 维持 recipient-only 或丢弃（§3.7），漏填的最坏结果是少投递不是泄漏。
- **事务完整性**：发送/绑定/协办单事务零残留（§4.2）；settings 写权威与投影同事务（§4.5）。
- **越权面**：session 级未列举 endpoint 全部在 §3.6 表中显式定权（无默认放行）；`DELETE` shared 会话直接拒绝。
- **代码纪律**：multica 注释一律英文（CLAUDE.md）；`CUSTOM.md` 登记（§4.9）。

## 7.2 性能

- advisory 锁粒度 = 单项目（`{ws}|{project}`），跨项目无串行；锁内操作均为索引点查。
- 索引全部 `CONCURRENTLY`，部署不锁表；483→484 窗口语义见 §2.3。
- 幂等表按 PK 点查点写，`created_at` 辅助索引供范围删；行尺寸有界（响应体为小 JSON）。
- 实时：生产端填 kind 零新增 DB 往返（各生产端本已持有 session 行）；shared 广播复用既有 workspace fanout 基建，无新协议。
- sweeper 每小时、批量上限（对齐 `SweepChatDraftAttachments` 的 `maxPerTick` 形态 [D-33]）。
- `chat_session` 增列（`kind` 常量默认、可空作者列于 `chat_message`）均不重写表。

# 8. Prompt 采纳影响

**省略**——本 CR 目标仓为 multica，diff 不触及 `skills/shared/crctl/scripts/crctl.mjs` dispatch 分支与 `skills/shared/controlled-shell/rules.json` `protectedPaths.deny`（tools 仓零改动，PRD §7 范围排除）。

# 9. 批准范围

- **scope_in**（本 CR 必须交付）：FR-1–FR-26 / AC-1–AC-32 全量，即：481–488 迁移；`chat_session.kind` 与 shared session 生命周期；Discussion GET/PATCH config/GET messages/POST messages 的 kind 分流与成员门禁；协办触发/无 Issue chat task/回复写回；草稿附件原子绑定；merge-forward `message_ids` 扩展；`Idempotency-Key` 幂等；settings 解绑与投影；实时 kind 感知投递与移出退订；旧容器只读回放；前端 discussion-pane session 身份化与四语文案；`CUSTOM.md` 登记。
- **scope_out**（明确排除）：项目级成员模型（PRD §7 排除项，成员口径=当前 workspace 成员）；Discussion → Issue/CR 升级；历史 comment 全量迁移；Team Agent 配置与发送内核；CR-2026-056 KG-1/KG-2；`agent_task_queue` 模型/Thinking 专用列；`discussion_participant` 表；mobile；`../tools/` 改动；发送框视觉重构。
- **zero_diff**（不得改动的调用点/签名）：`sendProjectChatCore` 全函数（NFR-7）；`ResolveChatConfig`/`ValidateResolvedChatConfig`/`LoadChatCatalogForConfig`/`mergeChatConfigContext`/`SnapshotAgentDefaults` 签名与语义；`LockUnboundDraftAttachments`/`BindUnboundDraftAttachments`/`LinkAttachmentsToChatMessage` 既有查询；`CreateChatTask` 查询本身；`kind=private` 的 `PatchChatSessionConfig`/`SendChatMessage`/`ListChatMessages`/`GetChatSession` 行为（逐行保留）；`EnsureProjectChatSession`（Team Agent 表路径）；`handleDiscussionContainerMentionTrigger`（保留不删）；168h 草稿 sweeper 谓词；legacy merge-forward `comment_ids` 路径与 `invalid_comment_selection`。
- **follow_up**（发现但留给后续）：① 项目级成员模型引入后，FR-25 负向契约从 workspace 口径升级（KB 延期清单第 10 项）；② 客户端 scope 订阅落地后，shared 事件从 workspace fanout 迁到 `BroadcastToScope("chat", ...)`（`listeners.go` 现有注释已预留一行切换点）；③ `project_chat_session`（Team Agent）与 `chat_session(kind=project_shared)` 两表并存的长期收敛评估；④ Discussion 会话的主动归档/关闭管理面（本 CR 仅定义权限，不提供入口）；⑤ 幂等记录保留期可配置化（本 CR 固定 24h 阈值，口径见 §4.6 澄清）。

# 10. 既有实现依赖与事实

> 按正文首次出现顺序。repo 均为 `multica`，commit SHA 均为 `e8b252597a6d21718c2533d497fba4109a79b37b`（本 CR requirement worktree HEAD）。

1. repo: multica
   relative path: server/internal/handler/project_chat.go
   stable symbol/对象: GetProjectDiscussion (L224)、ProjectDiscussionResponse (L215)、L250 对 EnsureProjectDiscussionIssue 的调用
   commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
   依赖结论: GET 现行为即「懒创建隐藏 Issue」，本 CR 的改写对象与响应契约基线
2. repo: multica
   relative path: server/internal/service/project_chat.go
   stable symbol/对象: EnsureProjectDiscussionIssue (L55)、ensureContainerIssue 的 "project-discussion" advisory 前缀与 origin_type='project_discussion' 容器机制
   commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
   依赖结论: GET 解除调用后不得再有其它创建入口；函数保留供存量语义
3. repo: multica
   relative path: server/migrations/033_chat.up.sql
   stable symbol/对象: chat_session 表 L7 `agent_id UUID NOT NULL REFERENCES agent(id) ON DELETE CASCADE`（内联 FK，自动命名 chat_session_agent_id_fkey）；chat_message 基础列
   commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
   依赖结论: 481 转换的唯一目标约束；全量迁移核查确认其后无迁移引用/改写该约束
4. repo: multica
   relative path: server/migrations/436_chat_session_project.up.sql
   stable symbol/对象: chat_session_project_creator_active_unique（谓词 `project_id IS NOT NULL AND status='active'`，不区分 kind）
   commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
   依赖结论: FR-6 必须收窄的现存索引；代码仅注释引用其名（可同名重建）
5. repo: multica
   relative path: server/migrations/214_chat_session_project.up.sql
   stable symbol/对象: chat_session.project_id（软引用，无 FK）
   commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
   依赖结论: shared session 复用该列；项目删除经 ClearChatSessionProjectByProject 置 NULL
6. repo: multica
   relative path: server/pkg/db/queries/chat.sql
   stable symbol/对象: GetProjectChatSessionForCreator (L12)；GetChatSessionInWorkspace、LockChatSessionInWorkspace（FOR UPDATE，L~40）；ListChatMessagesPage (L1065)；CreateChatTask (L1107, issue_id 恒 NULL)；chat_session_project_creator_active_unique 注释 (L16)
   commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
   依赖结论: 泄漏点收窄对象、会话锁读、分页复用、协办入队 INSERT、索引名引用盘点
7. repo: multica
   relative path: server/internal/handler/project_chat.go + server/internal/service/autopilot.go
   stable symbol/对象: GetProjectChatSessionForCreator 三处调用点（project_chat.go:343/378、autopilot.go:990）
   commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
   依赖结论: 加 `kind='private'` 过滤后三处语义全部保持（均只要 Private Ask）
8. repo: multica
   relative path: server/pkg/db/queries/attachment.sql
   stable symbol/对象: LockUnboundDraftAttachments (L188)、BindUnboundDraftAttachments (L205)、LinkAttachmentsToChatMessage (~L107)、DetachAttachmentsFromUserChatMessageByTask、CountUnboundChatAttachmentsForTask、BindChatAttachmentsToMessage
   commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
   依赖结论: 草稿锁序与既有绑定语义；新查询与其同构且不改动既有查询
9. repo: multica
   relative path: server/internal/service/task.go
   stable symbol/对象: writeChatCompletionOutcome (L5057)
   commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
   依赖结论: FR-12 回复按 task.ChatSessionID 自动写回同 session；仅需补作者列
10. repo: multica
    relative path: server/internal/service/task.go
    stable symbol/对象: mergeChatConfigContext (L1478)、其在 L1559（mention 路径）与 L2572（SendDirectChatMessage）的两处调用
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: chat_config 快照的单一 merge 缝，FR-11 直接复用，不新增第二套
11. repo: multica
    relative path: server/internal/service/task.go
    stable symbol/对象: EnqueueChatTask (L2069)、enqueueChatTaskTx (L2159)、SendDirectChatMessage (L2479) 的事务形态（CreateChatTask+Context、SetChatTaskInputOwnerSelf、提交后通知）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: Discussion 发送事务的结构模板与归因字段参照（priority=2、chat 路径签章）
12. repo: multica
    relative path: server/internal/handler/chat.go
    stable symbol/对象: PatchChatSessionConfig (L858)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: kind 分流的宿主；private 分支逐行保留
13. repo: multica
    relative path: server/internal/handler/chat.go
    stable symbol/对象: SendChatMessage (L955)、gatePublicChatSessionForUser (L306)、ListChatMessages (L1301)、ListChatMessagesPage (L1334)、parseChatMessagesPageParams (L1174)、ChatMessageResponse (L2175)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 消息/列表入口与门禁现状；kind 分流与 shared 分页对象化的基线
14. repo: multica
    relative path: server/internal/service/chat_config.go
    stable symbol/对象: ResolveChatConfig (L50)、resolveChatConfigValue 的四级优先、ValidateResolvedChatConfig (L88)、LoadChatCatalogForConfig (L125)、ChatConfigSource 枚举（含 agent_default 仅 legacy 语义）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 配置解析/校验单一实现；shared 路径以无效 agentDefault 杜绝 agent_default
15. repo: multica
    relative path: server/internal/handler/project.go
    stable symbol/对象: settings PATCH 分支 (L547 起)、discussion_coordinator 校验分支 (L592–613)、requireWorkspaceRole 门禁 (L549)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: FR-26 写权威入口；现无清除/解绑分支（非字符串即 400），本 CR 新增
16. repo: multica
    relative path: server/internal/service/project_chat_session.go
    stable symbol/对象: EnsureProjectChatSession、ProjectChatSessionAdvisoryPrefix ("project-chat-session")、LockIssueDuplicateKey advisory 用法、SnapshotAgentDefaults、insert-conflict+reselect 模式
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: Discussion ensure 的同构模板；advisory 前缀隔离的依据；Team Agent 表（project_chat_session）与本 CR 表不同
17. repo: multica
    relative path: server/internal/service/project_chat.go
    stable symbol/对象: SendProjectChatMessage、MergeForwardDiscussion (L176)、sendProjectChatCore、buildMergedForwardContent (L492)、commentAuthorDisplayName、错误契约注释（403/409/429/502 映射）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: FR-13 适配对象；内核零改动约束；消息渲染平行函数的结构参照
18. repo: multica
    relative path: server/internal/handler/project_chat.go
    stable symbol/对象: MergeForwardDiscussion handler（comment_ids 校验/去重/容器校验）、writeProjectChatSendError (L589)、PatchProjectChatConfig（owner/admin+三态 PATCH 参照）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: merge-forward 扩展宿主与错误映射复用
19. repo: multica
    relative path: server/internal/util/mention.go
    stable symbol/对象: Mention 结构、ParseMentions (L24)、MentionRe（`mention://agent/<id>` 语法）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: FR-11 @mention Coordinator 检测直接复用现有解析器
20. repo: multica
    relative path: server/internal/handler/comment.go
    stable symbol/对象: handleDiscussionContainerMentionTrigger (L2664)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 旧 comment 触发路径保留不删；新承载不经过它
21. repo: multica
    relative path: server/cmd/server/listeners.go
    stable symbol/对象: chat 事件路由（L253–270 区段：ChatSessionID 非空必须带 ChatRecipientID，SendToUser，缺失丢弃+ERROR 的 fail-closed 语义）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: FR-20 的改造点；private 语义与 fail-closed 缺省必须保持
22. repo: multica
    relative path: server/internal/events/bus.go
    stable symbol/对象: events.Event 的 TaskID/ChatSessionID/ChatRecipientID 字段与其契约注释（生产者必须同时设置、桥层 fail-closed）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 新增 ChatSessionKind 字段的宿主与既有契约边界
23. repo: multica
    relative path: server/internal/handler/daemon.go
    stable symbol/对象: task 流式帧的 chatSessionID/chatRecipientID 解析与 events.Event 发布（L4690–4800 区段）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 生产端 kind 标注改造点（其本已加载 session 行）
24. repo: multica
    relative path: server/internal/handler/handler.go
    stable symbol/对象: publishChat (L747)、requireWorkspaceMember (L923)、requireWorkspaceRole (L943)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 事件发布助手扩参；成员/角色门禁的唯一复用入口
25. repo: multica
    relative path: server/internal/service/task.go
    stable symbol/对象: ChatSessionCreatorID 的四处消费（L6938/L7249/L7327/L7447）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 任务事件生产端 kind 标注的扩展面（辅助函数同时返回 kind）
26. repo: multica
    relative path: server/internal/realtime/hub.go
    stable symbol/对象: MembershipChecker (L23–26)、HandleWebSocket (L775, L803/L835 IsMember)、BroadcastToWorkspace (L566)、SendToUser (L572)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: workspace fanout 的成员资格前提；新增按 (user, workspace) 断连的宿主
27. repo: multica
    relative path: server/internal/handler/workspace_revoke.go
    stable symbol/对象: revokeAndRemoveMember (L43)、publishRevocation (L269)、LockSubscriberWrites 锁序
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 「已被移出 workspace」的挂接点（AC-28/AC-29）；断连在事务提交后执行
28. repo: multica
    relative path: server/pkg/publicapi/v1/foundation.go
    stable symbol/对象: HeaderIdempotencyKey (L4)、MaxIdempotencyBytes=255 (L6)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: FR-24 头与长度约束的既有基建
29. repo: multica
    relative path: server/internal/handler/file.go
    stable symbol/对象: loadAttachmentForRequest (L728) 及其两处消费 (L650/L1299)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 已发送 shared 附件「非成员 404」的扩展点；草稿上传者门不变
30. repo: multica
    relative path: server/internal/service/chat_draft_attachment_cleanup.go
    stable symbol/对象: SweepChatDraftAttachments（168h、严格边界、maxPerTick）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 幂等 24h sweeper 的模式参照（谓词不改）
31. repo: multica
    relative path: server/pkg/db/queries/issue.sql
    stable symbol/对象: GetProjectDiscussionIssue (L622)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: legacy_issue_id 只读回放查询；无创建副作用
32. repo: multica
    relative path: server/internal/service/discussion_coordinator.go
    stable symbol/对象: ProjectSettingDiscussionCoordinatorID (L22)、RouteDiscussionToTeamAgent (L103)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: coordinator settings key 常量与转投路由的 Discussion 侧适配对象
33. repo: multica
    relative path: packages/core/api/schemas.ts
    stable symbol/对象: ProjectDiscussion/ProjectDiscussionSchema/EMPTY_PROJECT_DISCUSSION (L1400–1416)、parseWithFallback (client.ts:242/862)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: FR-19/NFR-8 的前端契约基线；新 schema 独立定义并硬降级
34. repo: multica
    relative path: packages/views/projects/components/discussion-pane.tsx
    stable symbol/对象: 以 discussion.issue_id 为可写身份的现结构（L80/L90 等）、useIssueTimeline、草稿 key 约定
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: FR-19 重写对象；草稿上传既有机制复用
35. repo: multica
    relative path: server/internal/service/project_chat_session.go
    stable symbol/对象: UpdateProjectSettingsWithTeamAgentRebind (L462)（换绑即关旧会话语义）
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 决策 D-5 的对照项——Discussion 投影刻意不复制该「关旧建新」语义
36. repo: multica
    relative path: server/cmd/server/router.go
    stable symbol/对象: /api/chat/sessions/{sessionId} 路由块 (L2316–2344)、/api/projects/{id}/chat/merge-forward (L2014)、/api/projects/{id}/discussion (L2022)
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 端点挂载现状；本 CR 不新增平行 URL（PRD 契约前言行）
37. repo: multica
    relative path: CUSTOM.md
    stable symbol/对象: 按 CR 里程碑分组、行号稳定 ID、合并核对口径的台账结构
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: FR-21 登记义务的结构基线（登记在代码实施期按其当时结构执行）
38. repo: multica
    relative path: server/migrations/472_project_chat_session.up.sql + server/pkg/db/queries/project_chat_session.sql
    stable symbol/对象: project_chat_session 表与 GetProjectChatSessionByID/LockProjectChatSessionByID
    commit SHA: e8b252597a6d21718c2533d497fba4109a79b37b
    依赖结论: 口径澄清——Team Agent 会话是独立表，本 CR 零改动，防与 chat_session(kind=project_shared) 混淆
