---
id: CR-2026-056-sdd
type: SDD
cr-ref: CR-2026-056
title: 会话级配置与 Team Agent 闭环 技术设计
status: draft
created: 2026-08-30T18:00:00+08:00
updated: 2026-08-30T19:55:00+08:00
---

# SDD — 会话级配置与 Team Agent 闭环技术设计

> 输入：已审批 `change-requests/CR-2026-056/prd.md`（21 FR / 6 US / 28 AC）。
> 目标代码仓：sibling `../multica/`（`resources[].repo=multica`）。knowledge-base 只承载本 SDD；`../tools/` **零实施改动**。
> 本文只补技术实现方案，不复述 PRD 需求语义。FR 映射见 §6，AC 闭环见 §6.2。

## 0. 术语预检（FR-08，写状态推进前）

进入数据模型 / 状态机 / 接口契约、且存在歧义或别名风险的术语如下。**无语义冲突**，不要求需求负责人澄清；命名冲突只记录映射。

| PRD canonical | 代码别名 / 既有符号 | 边界场景 | 结论 |
|---|---|---|---|
| Team Agent **session** | 新表 `project_chat_session` | 与 Private Ask 的 `chat_session` 并存 | **新表**；不得复用 `chat_session` |
| Private Ask **session** | 表 `chat_session`（已有 `(project_id, creator_id)` active 唯一） | sqlc 已有 `GetProjectChatSessionForCreator` | **保持该符号专指 Private Ask `chat_session`**；新表查询必须用不同名字（§2.4） |
| 隐藏执行容器 Issue | `issue.origin_type='project_chat'` 且 `origin_id=project_chat_session.id` | GET vs 首次发送；换绑新旧隔离 | GET 不得创建；**每个 session 至多一容器**；旧 session 的 Issue 不得被新 session 复用 |
| Task 快照 | `agent_task_queue.context` JSONB 的 `chat_config` | 入队后改 session 不得影响已入队行 | 新任务必写；旧任务缺字段保持既有执行 |
| `override` / `session_default` / `agent_default` / `runtime_default` | 响应字段 `model_source` / `thinking_level_source` | `base_*` SQL NULL vs 空字符串 | NULL=未快照（仅历史 Private Ask）；`''`=已快照「跟随 runtime 默认」 |
| session `status=closed` | `project_chat_session.status` | Private Ask `chat_session.status` 是 `active\|archived` | **两套枚举互不混用** |
| presenter | `guardProjectChatPresenter` | 消息单一写者 vs 配置写权限 | presenter **不**改变配置 PATCH 权限（仍 owner/admin） |
| 容器唯一键 | 今日 `issue_project_chat_unique(project_id)` | AC-18 换绑后双容器 | **废除**按 project 唯一；改为 `(workspace_id, origin_id)` 部分唯一。Discussion 的 `issue_project_discussion_unique` **不动** |
| `thinking_level` 空串 | 既有 ThinkingPicker 哨兵 | 空=不注入、跟随 CLI/runtime | 与 Agent 配置页同一哨兵，不另造语义 |
| `model` 空串 | 既有 `agent.Model` 空值 | GET/PATCH/发送有效值可为 `""`；catalog 无此 ID | **合法 runtime-default 哨兵**（§4.2.1）；不是 catalog 条目；daemon 把 `""` 交给 provider CLI |

CONTEXT.md 无「project_chat_session / chat_config / model_source」条目；本 CR 沿用上表，不把这些词写进 CONTEXT.md（跨 CR 术语表只在含义已平台级敲定时扩展）。

---

## 1. 架构概览

### 1.1 设计目标

把「这一次对话用的模型 / Thinking Mode」从 Agent 持久化配置拆到会话，把「这一次发送用的值」冻结进任务：

```text
Agent            长期共享基础配置（聊天窗口禁止 UpdateAgent）
project_chat_session / chat_session
                 当前对话的 override + 创建时 base_* 快照
agent_task_queue.context.chat_config
                 入队瞬间冻结的不可变执行值
issue (origin_type=project_chat)
                 Team Agent 消息流容器；首次发送或 POST .../chat/container 才绑定
```

打开 Team Agent 面板只 get-or-create `project_chat_session`，**不**调用 `EnsureProjectChatIssue`。

### 1.2 模块边界与改动面

全部实施在 `multica` 仓。`tools` 仓无 diff。

| 模块 | 本 CR 变化 | 责任边界 |
|---|---|---|
| `server/migrations/` 472 起 | 新表 `project_chat_session`；`chat_session` 加四列；CONCURRENTLY 索引 | 无新 FK；一文件一条语句 |
| `server/pkg/db/queries/` + sqlc | 新表 CRUD / 行锁；`chat_session` 配置列读写；未绑定附件绑定与 sweeper | 生成物 `make sqlc`，禁手改 |
| `server/internal/service/project_chat.go` | GET 不再创建 Issue；抽出 session 作用域 `BindProjectChatContainer`（接受外层 tx）。Team Agent 路径禁止按 project 调 `EnsureProjectChatIssue`；该函数留给转投（§4.13）。**仅改** `EnsureProjectChatIssue` 传入 `ensureContainerIssue` 的 `lockKeyPrefix`：`"project-chat"` → `"project-chat-session"`（BLOCK-016） | 服务层事务与幂等；handler 不复制第二套创建；`comment.go` 调用点零改动 |
| `server/internal/service/chat_config.go` | `ResolveChatConfig` + 薄包装 `ValidateResolvedChatConfig` + 接口 `ChatCatalogPort` | 校验算法在 `pkg/agent.ValidateChatConfig`；**禁止** service import handler 或复制归一化 |
| `server/pkg/agent/` | 导出 `ModelIDForCapabilityLookup`、`StaticCatalog`、`ValidateChatConfig` | 空模型哨兵、Claude 变体、Thinking 矩阵的**单一实现**；不得在 service 复制 |
| `server/internal/handler/` catalog 适配 | `ModelCatalogCache` / `InitiateListModels` **留在 handler**；新增 `LiveLoad` 同步等待（30s），picker HTTP 仍异步 | composition root（`cmd/server`）把适配器注入 service；不改 picker/daemon 协议 |
| `server/internal/service/task.go` | 入队前 merge `context.chat_config`；发送事务内绑定附件 | 禁止整对象覆盖 context |
| `server/internal/handler/project_chat.go` | GET 响应扩展；新增 PATCH config、POST container；messages 带 `session_id`，成功体带回 `session_id`/`issue_id` | 错误走 `writeErrorCode` |
| `server/internal/handler/daemon.go` | claim 组装 `TaskAgentData` 时：有 `chat_config` 则用快照，否则保持 `agent.Model` / `agent.ThinkingLevel` | 重试/重新 claim 同一 task 行，不重读 session |
| `server/internal/handler/file.go` | 未绑定草稿：下载/GET/删除仅上传者；Team Agent 上传省略 `issue_id` | 知道 UUID ≠ 可读 |
| `server/cmd/server/runtime_sweeper.go` | 1h ticker 调草稿 sweeper，不在请求路径扫表 | 与 30s 心跳解耦 |
| `packages/core/api/` | 独立 zod schema + `UNSAFE_CHAT_CONFIG_FALLBACK`；client 方法 | `parseWithFallback`，禁止 `session_id` 默认伪造 UUID |
| `packages/views/projects/components/project-team-agent-chat.tsx` | `persistModel` 改 PATCH session config；接入 ThinkingPicker；无 Issue 时仍可改配置、上传草稿 | 不重做 composer 视觉 |
| `packages/views/projects/components/project-private-ask.tsx` | 只读模型徽章改为可写 Model/Thinking，走 session PATCH | 不写 Team Agent session |
| `CUSTOM.md` | 编号顺延登记本 CR 文件与挂钩 | 双周 rebase 核对清单 |

**明确不改**：`GetProjectDiscussion` / `EnsureProjectDiscussionIssue`、Discussion 发送、Discussion Coordinator→Team Agent 转投的 **调用点与签名**（`retargetDiscussionCoordinatorRoute` / `RouteDiscussionToTeamAgent` / `comment.go` 上的 `EnsureProjectChatIssue` 调用）、`UpdateAgent` 管理页路径、`agent_task_queue` 专用模型列、mobile。`EnsureProjectChatIssue` **内部**锁键见 §2.1（BLOCK-016），不是转投改造。

### 1.3 关键流程

```text
打开 Team Agent
  GET /api/projects/{id}/chat
    → advisory lock 内重读 project.team_agent_id（禁止锁前快照）
    → get-or-create active project_chat_session（插入时写 base_*）
    → 禁止 EnsureProjectChatIssue / 新建 Issue；升级遗留行仅在「项目第一行 session」时收养（§2.1 / §4.1）
    → 返回 session_id + 可空 issue_id + 有效 model/thinking + source（model 允许 ""）

改配置（owner/admin）
  PATCH .../chat/config { session_id, model?, thinking_level? }
    → 同一 advisory + session FOR UPDATE + active/agent_id CAS（§4.7.1）
    → AgentReadiness + §4.3（ChatCatalogPort + ValidateResolvedChatConfig）
    → 只写 override（或按 FR-6 清除）；空串 model 不得写入 override
    → 禁止 UpdateAgent

显式创建 / 首次发送（与消息写者同一权限：presenter 规则）
  POST .../chat/container | POST .../chat/messages | merge-forward
    → ResolveChatConfig + AgentReadiness + catalog（失败则不建 Issue）
    → BindProjectChatContainer（session FOR UPDATE；origin_id=session.id；发送路径在同一 tx）
    → 发送/转发：merge chat_config → 同事务绑定附件 → 2xx
    → 换绑后新 session 新建容器，不复用旧 Issue

执行
  daemon claim 读 task.context.chat_config（缺则回退 agent 列）
  重试 / 重新 claim 不重读 session / agent 配置
```

### 1.4 依赖方向

```text
packages/views  (Team Agent / Private Ask UI)
  -> packages/core (API client + zod)
  -> handler (校验、编码、错误码)
  -> service (会话、容器幂等、配置解析、入队、附件绑定)
  -> sqlc queries / PostgreSQL
  -> daemon claim 只读 task 行 + agent 基础字段
```

遵守 `ARCHITECTURE.md`：handler 调 service，service 不反向依赖 handler；任务仍走 `agent_task_queue`；无新 FK；sqlc 生成物不手改；前端 TanStack Query 管服务端状态。

### 1.5 架构不变量核对

| 不变量 | 设计保证 |
|---|---|
| Workspace isolation | 所有查询带权威 `workspace_id`（含改造后的 `GetProjectChatSessionForCreator` 与 Private Ask PATCH）；请求体 workspace 不得覆盖认证上下文 |
| Dependency direction | service 只依赖 `ChatCatalogPort` + `pkg/agent`；不 import handler；catalog 适配器在 handler/`cmd/server` |
| Server/client state split | 配置以 GET/PATCH 为权威；客户端乐观更新失败回滚 |
| Task single path | 不新开队列；只在既有 enqueue 上 merge `chat_config` |
| CR authority split | Multica 不写 knowledge-base 账本 |
| Generated sources | 只改 `.sql` 后 `make sqlc` |
| Migration safety | 无 REFERENCES；索引 `CONCURRENTLY`；一文件一句 |
| API compatibility | 独立 schema + `parseWithFallback`；硬降级禁用写操作 |
| English comments | 新/改 Go/TS 注释英文 |

### 1.6 Merge-forward、换绑隔离与容器唯一性

今日 `EnsureProjectChatIssue` / `GetProjectChatIssue` 按 `(project_id, workspace_id, origin_type='project_chat')` 查找，且 `issue_project_chat_unique` 按 `project_id` 唯一、`origin_id` 恒为 NULL。换绑后若仍走该路径，新 session 会拿到旧 Issue，AC-18 失败。

本 CR 把 Team Agent 容器从「每项目一个」改为「每个 `project_chat_session` 一个」：

- 新容器 `origin_type='project_chat'` 且 **`origin_id = session.id`**（应用层关联，无 FK）；
- 废除 `issue_project_chat_unique`；新建部分唯一索引 `(workspace_id, origin_id) WHERE origin_type='project_chat' AND origin_id IS NOT NULL`；
- **Team Agent GET / PATCH / container / messages / merge-forward / presenter 活动记录**：解析容器只走 `session.issue_id` 或 `GetIssueByOrigin(workspace, 'project_chat', session.id)`，**禁止**再按 project 调 `GetProjectChatIssue` / `EnsureProjectChatIssue`（否则换绑后会拿到旧 Issue，AC-18 失败）；
- `EnsureProjectDiscussionIssue` / `issue_project_discussion_unique` 零改（NFR-7：Discussion 面板 GET/发消息）；
- **Discussion Coordinator→Team Agent 转投不在本 CR**（PRD §1.3 / §7 / NFR-7）：继续走今日 `EnsureProjectChatIssue`。`comment.go` 调用、函数签名、新建行 `origin_id=NULL` 不变。**仅**内部 advisory 锁键并入项目级协议（§2.1 / §4.13，BLOCK-016）。换绑只关闭/新建 `project_chat_session` 及其绑定容器，不改转投解析。兼容钉与已知缺口见 §4.13。

`POST /api/projects/{id}/chat/merge-forward` 仍复用 `sendProjectChatCore`，且 **仍是 Team Agent 发送**（FR-13/AC-7）。PRD 不要求请求带 `session_id`。服务端必须：

1. 用认证上下文的 `workspace_id` Ensure 当前项目 active session（无则按 FR-5 插入并写 `base_*`）；
2. `ResolveChatConfig` + §4.3 catalog/readiness（失败则不建 Issue、不入队）；
3. 与 messages 共用同一发送事务（含 Bind，见 §4.5）；
4. enqueue 前 merge `context.chat_config`（保留已有键）。

FR-13 / AC-7 的「发送」适用边界：**仅** Team Agent `POST .../chat/messages`、Private Ask 发送、以及上列 merge-forward。**不含** Coordinator 转投（§4.13）。Presenter 活动记录改为读 **active session 的 `issue_id`**（尚未绑容器则跳过，与今日「issue not found」一致）。

---

## 2. 数据模型

### 2.1 新表 `project_chat_session`

字段语义与 PRD FR-19 一致，列名不减：

| 列 | 类型 | 约束（应用层，无 FK） | 语义 |
|---|---|---|---|
| `id` | UUID | PK（CONCURRENTLY unique index 再 USING INDEX） | session 身份，PATCH/发送凭据 |
| `workspace_id` | UUID NOT NULL | 应用校验 ∈ workspace | 租户 |
| `project_id` | UUID NOT NULL | 应用校验 ∈ project | 项目 |
| `agent_id` | UUID NOT NULL | 生命周期内不可变 | 创建时的 Team Agent；绑定漂移 → 409 |
| `issue_id` | UUID NULL | 空=尚未绑容器；非空时对本表部分唯一 | 首次发送或 POST container 回写；等于该 session 的容器 Issue |
| `base_model` | TEXT NULL | 新建必非 NULL（可 `''`） | 创建时 Agent.model 快照 |
| `base_thinking_level` | TEXT NULL | 同上 | 创建时 Agent.thinking_level 快照；`''`=跟随 runtime |
| `model_override` | TEXT NULL | NULL=无 override | 非空=override |
| `thinking_level_override` | TEXT NULL | 同上；`''` 与 JSON null 在 PATCH 上均=清除 | 见 §4.2 |
| `status` | TEXT NOT NULL | `active` \| `closed` | 换绑 Agent 时旧行 closed |
| `created_by` | UUID NOT NULL | 首次打开/创建者 | 审计，不作配置权限 |
| `created_at` / `updated_at` | TIMESTAMPTZ | DEFAULT now() | |

一期每个项目最多一个 active 行，由部分唯一索引保证：

```sql
CREATE UNIQUE INDEX CONCURRENTLY project_chat_session_project_active_unique
  ON project_chat_session (workspace_id, project_id)
  WHERE status = 'active';
```

同一 Issue 不得挂两个 session（AC-18）：

```sql
CREATE UNIQUE INDEX CONCURRENTLY project_chat_session_issue_uidx
  ON project_chat_session (issue_id)
  WHERE issue_id IS NOT NULL;
```

容器 Issue 侧（替换 `435_issue_origin_project_chat` 引入的按 project 唯一）：

```sql
-- 独立迁移，一文件一句
DROP INDEX CONCURRENTLY IF EXISTS issue_project_chat_unique;

CREATE UNIQUE INDEX CONCURRENTLY issue_project_chat_session_origin_uidx
  ON issue (workspace_id, origin_id)
  WHERE origin_type = 'project_chat' AND origin_id IS NOT NULL;
```

新容器创建时必须写 `origin_id = session.id`。`GetIssueByOrigin` 已按 `(workspace_id, origin_type, origin_id)` 查询，可复用。废除 `issue_project_chat_unique` 后同项目可有多行 `project_chat`：`GetProjectChatIssue` 必须改为 `ORDER BY created_at ASC, id ASC LIMIT 1`（§4.13，BLOCK-017），否则 sqlc `:one` 在多行下失败或同时间戳漂移，转投路径会回归。Team Agent 自身解析不得再走该查询。

**项目级 advisory 协议（BLOCK-016）**：GET Ensure、收养检查、Bind、以及 legacy `EnsureProjectChatIssue` 必须共享同一把项目级锁，禁止 session 路径用 `project-chat-session|{ws}|{project}`、转投仍用 `project-chat|{ws}|{project}`。权威键：

```text
project-chat-session|{workspace_id}|{project_id}
```

落点：`EnsureProjectChatIssue` 传给 `ensureContainerIssue` 的 `lockKeyPrefix` 从 `"project-chat"`（今日 `project_chat.go:41`）改为 `"project-chat-session"`。`ensureContainerIssue` 仍拼接 `lockKeyPrefix|ws|project`（`project_chat.go:109`）。`EnsureProjectDiscussionIssue` 继续 `"project-discussion"`。`comment.go:2745` 与 `RouteDiscussionToTeamAgent` **零改动**。Bind 内部另可持 `project-chat|{ws}|{session.id}`，只串行同一 session 的 container/messages，**不是**项目级协议、不得替代上面那把锁。

**升级期遗留行（BLOCK-009 谓词 + BLOCK-016 执行点）**：现网 `project_chat` Issue 的 `origin_id` 为 NULL。收养窗口的**持久化判定**仍是（不是「本 session 第一次发送」口语）：

1. `CountProjectChatSessions(workspace, project) == 1`（含 closed）
2. 当前 session.`issue_id` IS NULL
3. `GetLegacyUnboundProjectChatIssue` 恰好 0 或 1 行

**执行点**：GET Ensure 插入该项目第一行 session 的同一事务，**以及**该第一行 session 的 Bind 在 `createContainerInOuterTx` 之前。后者堵住「GET 检查 legacy=0 并提交 → 转投插入 `origin_id=NULL` → Bind 再按 session.id 新建」的双容器分裂；谓词仍是 COUNT==1，换绑后 COUNT≥2 的 session B 不得收养（AC-18 不回退）。

```text
# 已持有 project-chat-session|{ws}|{project} advisory
# —— GET Ensure 与 Bind 共用；EnsureProjectChatIssue 内部也拿这一把
InsertProjectChatSession(...)          # GET：issue_id=NULL；Bind 则 session 已存在
sessions = COUNT(*) WHERE workspace_id AND project_id
legacy = GetLegacyUnboundProjectChatIssue  # 恰好 0 或 1 行
if sessions == 1 AND session.issue_id IS NULL AND legacy:
    UPDATE issue SET origin_id = session.id
      WHERE id = legacy.id AND origin_id IS NULL AND origin_type='project_chat'
    CAS BindProjectChatSessionIssue
# GET 仍不 INSERT 新 issue；Bind 仅在未收养时才 create origin_id=session.id
```

谓词 `sessions == 1`：一旦存在任何 **closed** 行或第二个 session，收养窗口关闭。「升级后先 GET session A、未发送即换绑、再 GET session B」时 B **不得**收养（COUNT≥2），Bind 只能新建 `origin_id=B.id` 的 Issue；遗留行若已在 A 被收养，则挂在 closed A 上（新旧 timeline 隔离）。

实施期夹具（映射 AC-18，不新增 AC 编号）：升级 fixture（`origin_id` NULL 的 `project_chat`）→ GET A（可带回旧 `issue_id`）→ 改 `team_agent_id` 且不发送 → GET B 的 `session_id`≠A 且不得返回 A 的 `issue_id` → B 首次发送得到 **新** Issue。并发与同时间戳夹具见 §4.14。

拒绝的替代（PRD 已排除）：只给 `issue` 加列、写入 `project.settings`、写入 `issue.metadata`、引入 `project_chat_thread`。

### 2.2 扩展既有 `chat_session`（Private Ask）

加四列，不新表：`base_model`、`base_thinking_level`、`model_override`、`thinking_level_override`（类型与上表相同）。

历史行四列均为 NULL。兼容规则（FR-11）：

- GET：`base_*` NULL 且无 override → 有效值=Agent **当前**默认，`*_source=agent_default`，**不写库**；
- 该 session 首次 PATCH 或首次发送才把当时 Agent 默认写入 `base_*`；
- 新建 Private Ask session 插入时必须写 `base_*`（来源=当时 Team Agent 默认，之后 Team Agent override 不影响）。

`chat_session.status` 仍为 `active|archived`，与 Team Agent 的 `closed` 无关。

**Hard Invariant 1**：既有 `GetProjectChatSessionForCreator`（`chat.sql`）WHERE 只有 `project_id`/`creator_id`，**必须**改为同时匹配权威 `workspace_id`。Private Ask GET get-or-create、PATCH、发送与 `autopilot.go` 调用方一律传入认证上下文的 workspace，禁止只靠上游 project 过滤。跨 workspace 负向：同一 `project_id`+`creator_id` 配错误 `workspace_id` 必须 0 行。`GetChatSession`（无 workspace）不得用于本 CR 的配置 PATCH；用已有 `GetChatSessionInWorkspace`。

### 2.3 任务快照（无新列）

`agent_task_queue.context` JSONB 增加键（merge，禁止整对象覆盖）：

```json
{
  "chat_config": {
    "model": "<id>",
    "thinking_level": "<level-or-empty>"
  }
}
```

`thinking_level` 为 `""` 表示不注入。旧任务无此键：claim 继续用 `agent.model` / `agent.thinking_level`（FR-14），不得回填。

### 2.4 sqlc 命名（避免与既有符号碰撞）

既有 `GetProjectChatSessionForCreator`（`server/pkg/db/queries/chat.sql`）**继续只服务 Private Ask `chat_session`**，但 WHERE 增加 `workspace_id = $n`（参数顺序实施期与 sqlc 生成一致；调用点同步改 Params）。

新表查询建议名（实施期可微调，不得占用上名）：

| 建议名 | 用途 |
|---|---|
| `GetActiveProjectChatSession` | `(workspace_id, project_id)` 且 `status=active` |
| `GetProjectChatSessionByID` | 按 id + workspace/project 校验 |
| `LockProjectChatSessionByID` | `FOR UPDATE` |
| `InsertProjectChatSession` | 新建（含 base_*） |
| `PatchProjectChatSessionConfig` | 写 override / updated_at |
| `BindProjectChatSessionIssue` | `WHERE issue_id IS NULL` CAS 回写 |
| `CloseActiveProjectChatSession` | 换绑 Agent：active → closed |
| `GetLegacyUnboundProjectChatIssue` | 升级收养：`origin_type='project_chat' AND origin_id IS NULL AND project_id AND workspace_id`；GET Ensure **或** 第一行 session 的 Bind，且仅当 `COUNT(session)=1` 且 `issue_id` NULL |
| `CountProjectChatSessions` | `(workspace_id, project_id)` 含 closed；收养窗口判定 |

Private Ask：为 `chat_session` 增加 `PatchChatSessionConfig`、`BackfillChatSessionBaseIfNull`（仅 NULL 时写 base_*）。配置读路径只用 workspace-scoped 查询。

### 2.5 附件

不新表。发送前草稿：`issue_id`/`comment_id`/`chat_session_id`/`chat_message_id`/`task_id` **全部 SQL NULL**。

发送成功：同一事务把上述字段写到 Issue + comment + task（Team Agent 路径无 `chat_session_id`/`chat_message_id`，保持 NULL 合法；谓词「五类全空」仍成立于发送前）。

`LinkAttachmentsToComment` 现要求 `issue_id = $2` 已存在，**不能**用于未绑定草稿。新增 sqlc：

- `LockUnboundDraftAttachments`：`WHERE` 五类全空 + `source_context_id IS NULL` + `id = ANY(...)`，`ORDER BY id FOR UPDATE`（与既有 `LockAttachmentsForIssueLink` 同锁序：attachment id 升序）。
- `BindUnboundDraftAttachments`：在已锁行上 `UPDATE` 写入 `issue_id`/`comment_id`/`task_id`，`WHERE` 仍要求五类全空且 `uploader_*` 匹配发送者。0 行 → `409 attachment_already_bound`。
- `DeleteUnboundDraftAttachment`（sweeper 专用，**不用**现有 `DeleteAttachment`）：`DELETE WHERE id AND workspace_id AND 五类全空 AND source_context_id IS NULL`。现有 `DeleteAttachment` 只排除 `source_context_id`，绑定后仍会删行（BLOCK-011）。

### 2.6 迁移编号（从 472）

当前最大已核实为 `471_approval_continuation_workspace_cr_pending_unique.up.sql`。建议拆分（一文件一句，无 REFERENCES）：

| 号 | 语句 |
|---|---|
| 472 | `CREATE TABLE project_chat_session (...);` 含 CHECK status；**无** PK/UNIQUE/FK |
| 473 | `CREATE UNIQUE INDEX CONCURRENTLY project_chat_session_id_uidx ON project_chat_session (id);` |
| 474 | `ALTER TABLE project_chat_session ADD CONSTRAINT project_chat_session_pkey PRIMARY KEY USING INDEX project_chat_session_id_uidx;` |
| 475 | active 部分唯一索引（§2.1） |
| 476 | `CREATE UNIQUE INDEX CONCURRENTLY project_chat_session_issue_uidx ON project_chat_session (issue_id) WHERE issue_id IS NOT NULL;` |
| 477 | `CREATE INDEX CONCURRENTLY ... ON project_chat_session (workspace_id, project_id);`（含 closed 历史） |
| 478 | `ALTER TABLE chat_session ADD COLUMN base_model TEXT, ADD COLUMN base_thinking_level TEXT, ADD COLUMN model_override TEXT, ADD COLUMN thinking_level_override TEXT;`（单语句四列） |
| 479 | `DROP INDEX CONCURRENTLY IF EXISTS issue_project_chat_unique;` |
| 480 | `CREATE UNIQUE INDEX CONCURRENTLY issue_project_chat_session_origin_uidx ON issue (workspace_id, origin_id) WHERE origin_type = 'project_chat' AND origin_id IS NOT NULL;` |

down 文件按仓惯例配对。禁止新 FK / 级联。

---

## 3. 接口契约

本 CR 新增/修改 HTTP API，本节必填。风格对齐既有 `writeErrorCode`（`{"error","code"}`）与 chi 项目路径，不强制 201+Location。

### 3.1 Team Agent

```text
GET    /api/projects/{projectId}/chat
PATCH  /api/projects/{projectId}/chat/config
POST   /api/projects/{projectId}/chat/container
POST   /api/projects/{projectId}/chat/messages
```

鉴权：项目成员（与现 GET 相同）。配置写：服务端强制 owner/admin，否则 `403 forbidden_chat_config`。发送/container：沿用 presenter 单一写者（`ErrPresenterRequired` → 403 `presenter_required`），**不是**配置 PATCH 的 owner/admin。

#### GET（不得创建 Issue）

成功 200，至少：

```json
{
  "session_id": "<uuid>",
  "issue_id": null,
  "team_agent_id": "<uuid>",
  "model": "<id>",
  "thinking_level": "<level-or-empty>",
  "model_source": "override|session_default|agent_default|runtime_default",
  "thinking_level_source": "override|session_default|agent_default|runtime_default"
}
```

- 未配置 Team Agent：保持现有引导语义；与发送相同，配置类操作返回 `409 team_agent_not_configured`（AC-20）。GET 空面板若项目无绑定，沿用现前端 CTA，不创建 session。
- 已绑容器：`issue_id` 为 UUID 字符串。绿场首次 GET 为 null。升级后该项目第一行 session 若收养遗留容器，GET 可返回已有 UUID（不是本请求新建的 Issue）。
- Team Agent 路径 **不得** 出现 `agent_default`（新建必写 `base_*`）。有效 `model` 允许 `""`（§4.2.1）。
- GET 必须在 `project-chat-session|{ws}|{project}` advisory **之内**重读 `settings.team_agent_id` 再 insert/返回，禁止用锁前的项目绑定快照插入 session（§4.1 / BLOCK-010）。
- **破坏性变化**：现 `ProjectChatResponse.IssueID` 为必填字符串且 GET 必建 Issue。本 CR 改为可空；客户端用新 schema，旧桌面客户端走 §3.4 硬降级（无 `session_id` 则只读）。

#### PATCH `/chat/config`

请求：

```json
{
  "session_id": "<uuid>",
  "model": "<id>|null|\"\"|省略",
  "thinking_level": "<level>|null|\"\"|省略"
}
```

字段语义 FR-6：省略=保持；JSON `null` 或 `""`=清除该字段 override；非空字符串=设 override。响应形状同 GET。`issue_id` 可仍为 null。`model=""` 只会出现在解析后的有效值里（`session_default`/`runtime_default`），**不会**作为 override 存库。

Handler 必须在写库前走 §4.7.1：项目 advisory → session `FOR UPDATE` → 事务内重读 `project.team_agent_id` → `UPDATE ... WHERE status='active' AND agent_id=$current`（0 行 → 409 `chat_session_closed_or_changed`）。锁外预检查不足以挡住换绑。

#### POST `/chat/container`

请求：`{ "session_id": "<uuid>" }`。幂等键即 `session_id`，不要求 `Idempotency-Key`。成功 **200**，形状同 GET 且 `issue_id` 非空。重复调用仍 200 + 同一 `issue_id`。

Handler 顺序（FR-10/FR-4，失败不得创建 Issue）：

1. 鉴权 / presenter（与发送相同，非 PATCH 的 owner/admin）；
2. session 归属：workspace/project/active/`agent_id` 与当前绑定一致，否则 404/409；
3. `ResolveChatConfig`；
4. §4.3 `AgentReadiness` + online catalog / Waitable 24h cache（与 PATCH/发送同一函数）；非法 model/Thinking → `400 invalid_model_or_thinking_level`；`AgentBlocked` → 与发送相同拒绝映射；
5. 仅校验通过后才调用 Bind（自己的短事务；空容器是本接口的成功产物）。

AC-24 的三夹具 **同时覆盖 PATCH、messages 与 container**；container 失败路径断言：无新 `project_chat` Issue、session.`issue_id` 仍为 NULL。

#### POST `/chat/messages`

请求在现有 `content` + `attachment_ids` 上 **必加** `session_id`。无容器时先 Bind 再入队。成功 **201**（允许保持现有 201；禁止 204/空 body）：

```json
{
  "session_id": "<uuid>",
  "issue_id": "<uuid>",
  "comment_id": "<uuid>",
  "task_id": "<uuid>"
}
```

`session_id` 必须等于请求值；`issue_id` 等于 session 行已回写值，且与同一 session 的 container 成功体相同。可选带回 model/source（AC-13 不依赖）。

现有 403 presenter / 429 queue full / 502 enqueue_failed 保留。

#### POST `/chat/merge-forward`（不改路径/请求字段）

请求体保持现有 `comment_ids`（+ 可选 `register_cr`），**不**新增 `session_id`。服务端解析 active session 后走 §4.12。成功体在现有 comment/task 字段上 **增加** `session_id` 与绑定后的 `issue_id`（与 messages 交叉断言一致）。失败码与 messages 对齐：`400 invalid_model_or_thinking_level`、Blocked 拒绝、`409 chat_session_closed_or_changed` / `team_agent_not_configured`、403 presenter、429、502。校验失败不得创建容器、不得入队、context 无 `chat_config`。

### 3.2 Private Ask

```text
GET    /api/projects/{projectId}/private-chat
PATCH  /api/chat/sessions/{sessionId}/config
```

GET 响应在既有 `ChatSession` 上 **附加** `model` / `thinking_level` / `model_source` / `thinking_level_source`（可用独立 schema，避免把这些字段塞进 `ChatSessionSchema` 的 `z.string().default("")` 伪造 session）。`session_id` 即既有 `id`。

PATCH：creator-only；加载 session 必须 `GetChatSessionInWorkspace`（或带 workspace 的 get-or-create）；`project_id IS NULL` 的普通 1:1 `chat_session` **拒绝**（本 CR 只对 Private Ask 生效）；不得改 `project_chat_session`。非创建者 `403 forbidden_chat_config`。请求体与 Team Agent PATCH 相同（无 `session_id` 字段，以路径为准）。历史缺 `base_*` 允许 `agent_default`，首次 PATCH/发送回填。

### 3.3 错误码（FR-17）

沿用 `writeErrorCode`。至少：

| HTTP | code | 何时 |
|---|---|---|
| 400 | `invalid_model_or_thinking_level` | 非空 model 未命中 catalog；空 model+非空 thinking 不被 `ValidateThinkingLevelWith` 接受（含 Codex 空模型 fail-closed）；Waitable 无可用缓存；Available 且 cache miss 后 LiveLoad 超时/失败 |
| 403 | `forbidden_chat_config` | Team Agent 非 owner/admin PATCH；Private Ask 非创建者 PATCH |
| 404 | `chat_session_not_found` | session 不存在或不属于本 project/workspace |
| 409 | `chat_session_closed_or_changed` | closed，或 `agent_id` ≠ 当前项目绑定 |
| 409 | `team_agent_not_configured` | 无 Team Agent（已有） |
| 409 | `attachment_already_bound` | 草稿已被绑定 |

`AgentBlocked` → 拒绝 PATCH/发送（与现入队「unusable runtime」一致；具体 HTTP 对齐 `agent_ready` 调用方既有映射，测试夹具覆盖「拒绝且不写 override、不入队」）。

### 3.4 前端 schema 硬/软降级（NFR-8）

新增独立 zod schema（不要把 `session_id` 做成 `z.string().default("")`）。

`UNSAFE_CHAT_CONFIG_FALLBACK`：

```text
session_id: ""
issue_id: null
model: ""
thinking_level: ""
model_source: "runtime_default"
thinking_level_source: "runtime_default"
```

1. **硬降级**：缺 `session_id` / 空 / 非 UUID → 整个 body `parseWithFallback` 到 fallback；UI 只读，禁用 picker/PATCH/发送，重试 GET。messages 成功体缺 `session_id` 或 `issue_id` 同样硬降级。
2. **软默认**：合法 UUID 但缺 model/source/`issue_id` → 字段级默认 `model=""`、`thinking_level=""`、`*_source=session_default`、`issue_id=null`；控件可写。

夹具：`packages/core/api/schemas.test.ts`。

---

## 4. 关键算法与流程

### 4.1 Ensure session（打开面板）

```text
advisory lock project-chat-session|{ws}|{project}     # 先锁，再读绑定
  project = 事务内重读 settings.team_agent_id         # 禁止用锁前快照
  if team_agent_id empty → 未配置（不建 session）
  active = GetActiveProjectChatSession
  if miss:
    read Agent.model / thinking_level（当前绑定，允许 model=""）
    InsertProjectChatSession(agent_id, base_*=those values, issue_id=NULL, status=active)
    # §2.1 升级收养：COUNT(session)==1 且 issue_id NULL 时认领 origin_id NULL 遗留行
    # 与 EnsureProjectChatIssue 共用 project-chat-session|{ws}|{project}（BLOCK-016）
  # 不调用 EnsureProjectChatIssue，不 INSERT 新 issue
ResolveChatConfig(session, agent) → 响应   # GET 本身不做 §4.3（只读展示）；写路径才校验
```

并发两个 GET：部分唯一索引 + advisory lock，最多一行 active。与换绑/PATCH/Bind/`EnsureProjectChatIssue` 共用同一把项目级 advisory（BLOCK-010 / BLOCK-016），避免 GET 按旧 agent 插入 session，也避免转投与收养交错各建一容器。

### 4.2 ResolveChatConfig

对 `model` 与 `thinking_level` **分别**解析（来源可不同）。

```text
if override IS NOT NULL and (thinking: 非「清除后的 NULL」):
    value = override; source = override
    # 空串 override 在 PATCH 后被写成 NULL，不会落到这里
else if base_* IS NOT NULL:          # 含 base='' 
    value = base_*; source = session_default
else if agent 当前默认可用:          # 仅历史 Private Ask
    value = agent.model / thinking_level; source = agent_default
else:
    value = ""; source = runtime_default
```

PATCH 空值：用指针/三态（omitted / null-or-empty / non-empty），Go 用 `json.RawMessage` 或 `*string` + `omitempty` 不够区分 omit 与 null；采用显式 `json.RawMessage` 按键是否存在判定（与 FR-6 全接口一致）。

`null` 与 `""` 都把对应 `*_override` 设为 SQL NULL（清除）。不要把 `""` 存进 override 列（否则会与「空串哨兵有效值」混淆）；有效空 thinking / 有效空 model 只来自 `base_* = ''` 或 runtime_default。

#### 4.2.1 空模型哨兵与 provider 规则（BLOCK-008）

空 `model`（`""`）是合法哨兵，语义与既有 `agent.Model` 空值相同（`pkg/agent.Model` 注释）：daemon 把 `""` 传给 provider CLI，由 CLI/config 选默认。**它不是 catalog 条目**，`ValidateResolvedChatConfig` **不得**要求 `"" ∈ Models`。

| 有效值 | 何时 | `model_source` | 是否合法 |
|---|---|---|---|
| `model=""` | 新建时 Agent.model 为空 → `base_model=''` | `session_default` | 是 |
| `model=""` | 无 override、无 `base_*`、无 Agent 默认 | `runtime_default` | 是 |
| `model=""` 写入 `model_override` | PATCH `""` | — | **否**（FR-6：`""`=清除 override） |

`ValidateResolvedChatConfig` 是 service 薄包装；**算法唯一实现**在 `pkg/agent.ValidateChatConfig`（BLOCK-014）。service **不得**引用未导出符号，**不得**复制 Claude 变体正则 / provider 别名 / Thinking 矩阵。

`pkg/agent` 本 CR 导出/下沉（既有未导出逻辑升格，不写第二套规则）：

```go
// ModelIDForCapabilityLookup is the catalog identity for a runtime-native
// model string. It never changes the persisted or CLI-passed value.
// Claude context-window variants (e.g. claude-opus-5[1m]) share the base
// model's capabilities; every other provider keeps exact match.
func ModelIDForCapabilityLookup(providerType, model string) string

// StaticCatalog adapts an already-loaded Catalog to the loader shape
// required by ValidateThinkingLevelWith. No I/O.
func StaticCatalog(c Catalog) func() (Catalog, error)

// ValidateChatConfig is the SINGLE domain check for session/task
// chat-config. Empty model is a legal runtime-default sentinel (not a
// catalog ID). Thinking uses ValidateThinkingLevelWith; model membership
// uses ModelIDForCapabilityLookup against catalog.Models.
func ValidateChatConfig(catalog Catalog, providerType, model, thinking string) (ok bool, err error)
```

未导出 `modelIDForCapabilityLookup` 改为调用导出符号（或等名升格）；`claudeContextWindowTagRe` **只**留在 `pkg/agent`。既有 `ValidateThinkingLevelWith` 签名不变：第一个参数是 `func() (Catalog, error)`，**不是** `Catalog`。已加载目录必须经 `StaticCatalog` 适配，禁止把 `Catalog` 当 loader 传入。

`ValidateChatConfig` 伪代码（与 `ValidateThinkingLevelWith` 共用同一套规则）：

```text
thinkingOK, err = ValidateThinkingLevelWith(StaticCatalog(catalog), provider, model, thinking)
# 既有规则（不得在 service 重写）：
#   thinking=="" → true（不注入）
#   codex + model=="" + 非空 thinking → false（fail-closed，用户须显式选模型）
#   其他 provider：空 model 解析到 catalog.Default（opencode 为「任一模型支持该 level」）
#   Claude 变体经 ModelIDForCapabilityLookup 命中能力矩阵

if err != nil: 400 invalid_model_or_thinking_level
if model == "":
    modelOK = true                             # 跳过 ID ∈ Models；哨兵不是 catalog 条目
else:
    lookup = ModelIDForCapabilityLookup(provider, model)
    modelOK = lookup 命中 catalog.Models[].ID   # 只比导出 lookup 后的 ID，不复制正则

if !modelOK or !thinkingOK: 400 invalid_model_or_thinking_level
```

service：

```go
func ValidateResolvedChatConfig(model, thinking, provider string, catalog agent.Catalog) error {
    ok, err := agent.ValidateChatConfig(catalog, provider, model, thinking)
    if err != nil || !ok {
        return errInvalidModelOrThinking // handler maps to 400
    }
    return nil
}
```

cache / live 两路都把已加载的 `agent.Catalog` 交给这一处；handler 只做 `ModelEntry`→`Catalog` 适配与 `writeErrorCode`。

进入 `context.chat_config`：允许 `"model":""`。daemon claim（§4.8）原样写入 `TaskAgentData.Model`，与今日空 `agent.Model` 相同。

夹具矩阵（handler+service，映射 AC-9/AC-24，不新增 AC 编号）：`model=""` + thinking `""`（各 provider 通过）；`model=""` + 非空 thinking × `codex` → 400；同组合 × `claude`/`opencode` 按 `ValidateThinkingLevelWith`；非空未知 model → 400。

### 4.3 catalog + readiness（PATCH、container、messages、merge-forward 共用；不含转投）

**模块边界（BLOCK-007 / BLOCK-014）**：领域校验算法在 `pkg/agent.ValidateChatConfig`；service 持有 `ChatCatalogPort` 与薄包装，**不**复制归一化。目录存储与 daemon 发现留在 handler。ARCHITECTURE.md §4：handler 调 service，service **不得** import `internal/handler`。因此：

- 领域类型与校验：`pkg/agent.Catalog` / `Model` / `ValidateThinkingLevelWith` / **`ModelIDForCapabilityLookup` / `StaticCatalog` / `ValidateChatConfig`**（本 CR 导出/下沉，§4.2.1）。`handler.ModelEntry` 只是 wire 镜像，由 handler 适配成 `agent.Catalog`。
- service 接口（handler 注入，`cmd/server` 接线）：

```go
// ChatCatalogPort is owned by service. Handler implements it.
type ChatCatalogPort interface {
    // CacheLoad returns a usable last-known-good catalog
    // (cacheable && Age(now) < 24h). ok=false means no usable snapshot.
    CacheLoad(ctx context.Context, runtimeID string) (cat agent.Catalog, ok bool, err error)
    // LiveLoad performs ONE synchronous discovery round. It must not
    // return a pending/202 state to this caller. Timeout = 30s
    // (handler.modelListPendingTimeout). Reuses daemon pending-work /
    // ModelListStore internals; HTTP InitiateListModels stays async
    // (PRD FR-4：不改 picker/daemon 协议).
    LiveLoad(ctx context.Context, runtimeID string) (agent.Catalog, error)
}
```

- service `ValidateResolvedChatConfig` 只转发 `agent.ValidateChatConfig`；**四入口**（PATCH / messages / container / merge-forward）只调这一处。handler 只做鉴权与 `writeErrorCode` 映射。转投不走本校验（§4.13）。

**同步判定契约**（`loadCatalogForChatConfig`，同一函数）：

```text
verdict = AgentReadiness(agent)
if Blocked(): reject（不写 override、不建 Issue、不入队）

if Waitable:
    cat, ok, err = port.CacheLoad(runtimeID)
    if err != nil or !ok: 400 invalid_model_or_thinking_level
    # 禁止 LiveLoad；离线无法完成 daemon 往返
else: # Available
    cat, ok, _ = port.CacheLoad(runtimeID)
    if ok:
        用该目录                          # 与 picker 快路径一致
        Age ≥ modelCatalogRevalidateAfter(60s) 时可后台 revalidate，不挡本请求
    else:
        cat, err = port.LiveLoad(ctx with 30s deadline)
        if err != nil or !cacheable(cat): 400
        # cacheable = supported && !fallback && len(models)>0
        # timeout / transport / empty / fallback / unsupported → 400
        # handler 侧成功后 Put cache（既有 cacheable 规则）

ValidateResolvedChatConfig → agent.ValidateChatConfig(cat, provider, model, thinking)  # §4.2.1
```

`cacheable` 复用既有 `cacheableModelCatalog` 语义（适配后在 handler 实现里调用，或把布尔判断下沉为 `pkg/agent` 小函数，避免 service 引用 handler 符号）。禁止 fallback stand-in。`modelCatalogRevalidateAfter` **不是**拒绝门槛。

LiveLoad 错误语义（测试夹具必须覆盖）：

| LiveLoad 结果 | HTTP | 写 override / 建 Issue / 入队 |
|---|---|---|
| 30s 内 cacheable catalog | 继续校验 | 命中才成功 |
| 超时（pending 未完成） | 400 `invalid_model_or_thinking_level` | 否 |
| daemon Fail / empty / fallback | 400 同上 | 否 |
| Waitable 无 cache | 400 | 否（不调用 LiveLoad） |

### 4.4 BindProjectChatContainer（幂等，session 作用域）

取代 Team Agent 路径上的 `EnsureProjectChatIssue`。**仅** container / messages / merge-forward 调用；GET 禁止。Discussion 容器仍走 `EnsureProjectDiscussionIssue`。Coordinator 转投仍走既有 `EnsureProjectChatIssue`（§4.13），**不**改调 Bind。

今日 `ensureContainerIssue` 自开事务并 `Commit`，且 getter 按 project 查 `GetProjectChatIssue`。本 CR：

- getter 改为 `GetIssueByOrigin(workspace, 'project_chat', session.id)`（或读已锁 session 行的 `issue_id`）；
- **项目级** advisory 已由调用方持有：`project-chat-session|{ws}|{project}`（与 GET/换绑/PATCH/`EnsureProjectChatIssue` 同一把，BLOCK-016）。Bind **不得**改用另一把项目级锁；
- Bind 内部可另加 `project-chat|{ws}|{session.id}`，只串行同一 session 的 container+messages，避免换绑后新 session 与旧容器创建在 session 粒度上交错；这把锁 **不是** 项目级协议，也不得改回 `project-chat|{ws}|{project}`（那是今日 Ensure 的旧键，改完后 Ensure 不再使用）；
- **必须接受外层 tx**：发送路径把 Bind 放进发送事务；container 显式创建用自己的短事务。禁止在发送路径上先 Commit 容器再开第二个事务。

```text
# 调用方已持有：project-chat-session|{ws}|{project} advisory（与 GET/换绑/PATCH/Ensure 同一把）
# 然后：
LockProjectChatSessionByID FOR UPDATE
assert status=active
assert session.agent_id == project.team_agent_id  else 409 chat_session_closed_or_changed
  # project.team_agent_id 必须在本事务、advisory 内重读，禁止用请求入口处的旧值
if session.issue_id set: return that issue
issue = GetIssueByOrigin(workspace, 'project_chat', session.id)
if found: CAS Bind if needed; return
# §2.1 收养（COUNT==1 且 issue_id NULL）：转投可能已插入 origin_id=NULL
legacy = GetLegacyUnboundProjectChatIssue
if sessions==1 AND legacy:
    UPDATE issue SET origin_id = session.id WHERE id=legacy.id AND origin_id IS NULL
    CAS BindProjectChatSessionIssue
    return legacy
issue = createContainerInOuterTx(...)   # origin_id=session.id；ON CONFLICT origin 回读
BindProjectChatSessionIssue CAS
return issue
```

同 `session_id` 并发 container+messages：session 行锁串行化，最多一个 Issue。换绑后新旧 session 各一 Issue，由 `issue_project_chat_session_origin_uidx` 与 `project_chat_session_issue_uidx` 兜底。

### 4.5 发送（Team Agent messages）

FR-16：失败不得留下 `session.issue_id` 与空容器半成品。因此 **首次绑定与 comment/enqueue/附件绑定必须同一 PostgreSQL 事务**。显式 POST container 已成功提交的空容器不算半成品。

```text
validate session_id（同 PATCH）
advisory lock project-chat-session|{ws}|{project}
guard presenter + queue capacity（现 sendProjectChatCore 前半；失败则无 Issue）
ResolveChatConfig + catalog/readiness（失败则无 comment、无 Bind）
tx:
  BindProjectChatContainer(outerTx)   # 含 FOR UPDATE；已有 issue_id 则只读
  CreateComment
  enqueueMentionTaskWithCommentPlan
  merge chat_config into task.context   # 保留 head_sha 等已有键
  BindUnboundDraftAttachments
commit
# rollback：Issue 行、session.issue_id、comment、task、附件绑定全部撤销
# 仅当 enqueue 在 commit 之后仍可能失败（现状补偿删 comment）：若 Bind 已随 tx 提交，
# 本 CR 把 enqueue 留在同一 tx 内（sqlc 已在 tx 上跑）；禁止「先 Commit 容器再 enqueue」。
broadcast after commit
```

**锁序**（固定，防与 GET/PATCH/换绑/sweeper 死锁）：① `project-chat-session|{ws}|{project}` advisory → ② session 行 `FOR UPDATE` → ③ 创建 Issue → ④ 附件 `LockUnboundDraftAttachments`（`ORDER BY id`）。禁止先建 Issue 再锁 session；禁止先锁附件再拿 session/advisory。完整表见 §4.14。

**相对现状的关键差**：今日 `linkAttachmentsByIDs` 在 enqueue **成功之后**、事务外调用，且 SQL 要求 `issue_id` 已在附件上。本 CR 改为发送事务内绑定未绑定草稿；composer 上传 **省略** `issue_id`（`TeamAgentComposer.handleComposerUpload` 今日传 `{ issueId }`）。今日 `ensureContainerIssue` 内部 `Commit` 必须从发送路径移除。

### 4.6 Private Ask 发送

既有 chat 入队路径增加：缺 `base_*` 则一次回填；Resolve + 校验；merge `chat_config`。不经 `project_chat_session`。加载 session：`GetProjectChatSessionForCreator`（含 workspace）或 `GetChatSessionInWorkspace`，禁止无 workspace 的 `GetChatSession`。

### 4.7 换绑 Team Agent（FR-7 / AC-18）

`PATCH /api/projects/{id}` 写 `settings.team_agent_id` 的现有分支（`handler/project.go`）与 close 必须在 **同一把** `project-chat-session|{ws}|{project}` advisory 下提交：

```text
advisory lock project-chat-session|{ws}|{project}
  update project.settings.team_agent_id
  CloseActiveProjectChatSession          # 行锁在 advisory 之后
commit
# 不在此处创建新 session 或新 Issue
# 下一次 GET 按新 agent_id 插入新行并复制新默认；issue_id=NULL（除非 §2.1 已在该新行收养——换绑后 COUNT>1，不会）
# 旧 issue_id 仍挂在 closed session 上（origin_id=旧 session.id），只读
# 新 session Bind 只新建 origin_id=新 session.id，不得收养
```

GET timeline / 评论列表只读 **当前 session.issue_id**，不得 `GetProjectChatIssue` 按 project 拉评论。测试：换绑后旧 comment 不出现在新 GET；两 Issue 的 `origin_id` 不同；`issue_project_chat_unique` 已不存在故允许同 project 两行 `project_chat`。另测：升级后未发送即换绑（§2.1 夹具）。

#### 4.7.1 GET / PATCH 换绑栅栏与 CAS（BLOCK-010）

GET、配置 PATCH、发送、container、merge-forward、换绑、**以及** `EnsureProjectChatIssue`（转投创建/查询）**全部**先拿同一把项目 advisory `project-chat-session|{ws}|{project}`，再在事务内重读绑定与 session / 重检 `GetProjectChatIssue`。禁止「锁外读项目绑定 / 锁外读 session 再写」。转投 **加入**本栅栏的方式是改 Ensure **内部**锁键（§2.1），不是改 `comment.go` 或 `RouteDiscussionToTeamAgent`。

PATCH config（Team Agent；Private Ask 无换绑但仍要 session 行锁）：

```text
advisory lock project-chat-session|{ws}|{project}
  project = 重读 team_agent_id
  session = LockProjectChatSessionByID FOR UPDATE
  if status != active OR session.agent_id != project.team_agent_id:
      409 chat_session_closed_or_changed
  ResolveChatConfig + §4.3
  UPDATE project_chat_session SET overrides...
    WHERE id=$id AND status='active' AND agent_id=$current
  if RowsAffected == 0: 409 chat_session_closed_or_changed
commit
```

GET 并发换绑：若 GET 已持锁则换绑等待；GET 用锁内 `team_agent_id` 插入，不会写入已关闭 agent 的 session。PATCH 并发 close：FOR UPDATE 看到 closed 或 CAS 0 行 → 409，不会把 override 写进 closed session。

### 4.8 daemon claim（FR-14）

`handler/daemon.go` 组装 `TaskAgentData` 处现为 `Model: agent.Model.String`、`ThinkingLevel: agent.ThinkingLevel.String`。

改为：

```text
model, thinking = agent.Model, agent.ThinkingLevel
if parse context.chat_config 成功且键存在:
    model = chat_config.model
    thinking = chat_config.thinking_level   # 允许 ""
# 缺 chat_config：保持 agent 列（旧任务）
```

重试/重新 claim 读同一 task 行，不 SELECT session。daemon 内 `resolveTaskModelSelection` 对 catalog miss 的 pass-through **不是** AC-9 通过条件（PRD 已写明）。

### 4.9 未绑定附件可见性

`loadAttachmentForRequest` / `loadAttachmentForDownload` 今日：workspace 内按 id 读到即返回。对五类绑定全空的行，追加：调用者必须是 `uploader_type=member` 且 `uploader_id=caller`。否则 404（不泄露存在性）。项目附件列表（`ListAttachmentsByIssue`）因 `issue_id` 为空本来就不会出现。禁止把草稿 id 打进团队 WebSocket。

删除/重试绑定：同一上传者门。

### 4.10 草稿 TTL sweeper

新 service 函数（测试文件 `chat_draft_attachment_cleanup_test.go`），注入 `storage.Storage`（`*storage.S3Storage` / `*storage.LocalStorage` 均满足；与 `handler.deleteS3Object` / channel-media reconciler 同一接口）。

删除谓词（同时满足）：五类绑定全空 **且** `created_at < now() - interval '168 hours'`（恰好 168h00s **本轮不删**）。

**不得**只 DELETE attachment 行。每条候选必须在 **同一事务的行锁覆盖下** 完成对象删除与条件删行（BLOCK-011）。现有 `DeleteAttachment` **禁止**用于 sweeper。

```text
unlocked = SELECT id WHERE 五类全空 AND created_at < now()-168h LIMIT 100
for id in unlocked:
  tx:
    row = SELECT ... FOR UPDATE SKIP LOCKED
      WHERE id AND workspace AND 五类全空 AND source_context_id IS NULL
           AND created_at < now()-168h
    if miss: continue                    # 发送已 Bind，或其它 sweeper 已拿走
    if Storage==nil or url empty:
      ROLLBACK; log; continue            # 不删行
    err = Storage.DeleteObject(...)       # 持有行锁；发送方 Bind 等待本行
    if err: ROLLBACK; log; continue       # 下一 tick 重试
    DELETE via DeleteUnboundDraftAttachment  # WHERE 再次要求五类全空
    COMMIT
```

与 `BindUnboundDraftAttachments` 的锁序：双方都按 `attachment.id` 升序加行锁；发送路径先拿项目 advisory + session，再锁附件（§4.14）。sweeper **不**拿项目 advisory，故不会与发送形成环：发送最多等待 sweeper 的对象删除（≤30s）。`FOR UPDATE SKIP LOCKED` 让其它 tick/并发 sweeper 跳过已锁行。

测试：年龄边界（AC-28）+ fake Storage：对象失败则行仍在；成功则行与对象都消失；`Storage=nil` 不删行。**并发夹具**：sweeper 已选出候选后、删对象前，发送完成 Bind → sweeper 锁内重读 miss 或条件 DELETE 0 行，对象**不得**删除、已绑定行仍在。

挂到 `runRuntimeSweeper` **旁路**的独立 1h ticker（同进程，`main.go` 再开 goroutine，或 sweeper 内 `lastDraftSweep` 节流）。**禁止**在 GET/PATCH/发送路径扫全表。未满 168h 即使多次发送失败也保留。

### 4.11 前端接入（不重做 composer）

- 复用 `ChatInputCore`、draft adapter、`useFileUpload`、停止/重试。
- 复用 `ModelPicker`、`ThinkingPicker`（Agent inspector），值绑定 session 有效值而非 `agent.model`。
- Team Agent：`persistModel` **删除** `api.updateAgent`；改为 `PATCH .../chat/config`。Thinking 同样。非 owner/admin：控件只读（AC-6 仍以后端 403 为准）。
- 无 `issue_id`：composer 仍可用；上传不传 `issue_id`；timeline 空态。
- Private Ask：去掉只读徽章，同样 PATCH `/api/chat/sessions/{id}/config`。
- 硬降级：picker/发送 disabled + 错误提示。
- 文案四语：`packages/views/locales/parity.test.ts`。

### 4.12 merge-forward 发送（无 session_id 请求）

Handler `MergeForwardDiscussion` 在现有 comment 选择校验之后，**不再**调用 `EnsureProjectChatIssue`。

```text
Ensure active project_chat_session（§4.1，含 workspace；无则插入 base_*）
# 若并发换绑导致刚读到的 session 已 closed → 409 chat_session_closed_or_changed
ResolveChatConfig(session, agent)
§4.3 catalog + readiness
  fail → 对应 400 / Blocked 映射；断言无新 Issue、无 enqueue
进入与 §4.5 同一 sendProjectChatCore(tx 含 Bind)
  merge context.chat_config（夹具含 head_sha）
成功体带回 session_id + issue_id
```

测试（`merge_forward_test.go` 扩展，或 `project_chat_test.go`）：

- 无 session 时 merge-forward 创建 session+容器且任务带 `chat_config`；
- 已有 override 的 active session：入队快照为 override，随后 PATCH 改模型不影响该任务（AC-7）；
- Waitable 无 cache / Blocked：不建 Issue、不入队；
- 换绑后 merge-forward 写入**新** session 的 Issue，旧 timeline 不变。

### 4.13 Discussion 转投兼容边界与已知缺口（BLOCK-013）

**裁定**：对齐已审批 PRD §1.3 / §7 / NFR-7。本 CR **不**改造 Discussion Coordinator→Team Agent 转投。

`comment.go` / `RouteDiscussionToTeamAgent` 保持不变：

- `handler/comment.go` `retargetDiscussionCoordinatorRoute` 继续调用 `EnsureProjectChatIssue`（按 project）；
- `TaskService.RouteDiscussionToTeamAgent(ctx, chatIssue, ...)` 签名不变，继续 `CreateComment` + `enqueueMentionTaskWithCommentPlanAndOriginator`；
- **不**走 §4.3 catalog/readiness、**不** Bind-in-tx、**不** merge `chat_config`。
- 允许的唯一内部改动：`EnsureProjectChatIssue` 的 `lockKeyPrefix`（§2.1 / BLOCK-016）。

**换绑作用域（新 session/容器模型 vs 转投旧容器）**：

```text
换绑 Team Agent
  → 只 close 当前 project_chat_session，下一次 GET 插入新 session
  → Bind / messages / merge-forward 只写 session.issue_id 指向的新容器
  → 转投仍调 EnsureProjectChatIssue，不读 project_chat_session

废除 `issue_project_chat_unique` 后，同项目可有多行 `origin_type='project_chat'`。
GetProjectChatIssue 今日 :one 无 ORDER，多行会炸；仅 `ORDER BY created_at ASC LIMIT 1` 在相同 `created_at`（同事务 `now()` 或微秒碰撞）下仍非稳定总序（BLOCK-017）。
兼容钉（sqlc，不是转投改造）：
  GetProjectChatIssue = 同 project+workspace 的 project_chat
                        ORDER BY created_at ASC, id ASC LIMIT 1
  即「该项目最早的 project_chat 容器」；`id` 为稳定第二键。
EnsureProjectChatIssue 函数签名、ensureContainerIssue 创建路径、新建行 origin_id=NULL
均保持现状；**仅**内部 lockKeyPrefix `"project-chat"` → `"project-chat-session"`（BLOCK-016），
使转投创建/查询与 GET 收养、Bind 共享项目级 advisory。
Team Agent GET/send/container/merge-forward/presenter **禁止**再调这两函数。
```

绿场（均在同一把 `project-chat-session|{ws}|{project}` 下）：

- **转投先**：Ensure 创建 `origin_id` NULL 行；随后第一次 GET 或该第一行 session 的首次 Bind 在 COUNT==1 窗口内认领（§2.1）。
- **Team Agent 先发送**：Bind 创建 `origin_id=session.id`；随后转投 `GetProjectChatIssue` 解析到同一最早容器。
- **GET 先于转投、尚未 Bind**：GET 检查 legacy=0 并提交后，转投与 Bind 仍串行在同一把锁上；Bind 走 §4.4 收养，不得再建第二容器。

这些是兼容行为，不是新功能。换绑后 COUNT≥2：新 session 不收养，转投仍写最早容器（KG-2）。

**已知缺口（本 CR 不修，归属 CR-B / CR-C；实施期/验收期不得当本 CR 缺陷打回）**：

| ID | 缺口 | 现状后果 | 归属 |
|---|---|---|---|
| KG-1 | 转投任务无 `chat_config` 不可变快照 | 转投入队后改 Team Agent session 配置，或 Agent 列变化，可能改变该转投任务执行语义 | CR-B / CR-C |
| KG-2 | 换绑后转投仍写旧 Issue | 新 session 的 Team Agent timeline 看不到转投评论；转投继续写入 `GetProjectChatIssue` 解析到的最早容器 | CR-B / CR-C |

AC-24 **不**覆盖转投。FR-13 / AC-7 的发送边界见 §1.6。

### 4.14 并发协议表（GET / PATCH / 发送 / 换绑 / 转投 Ensure / sweeper）

全局锁序，禁止颠倒（SUG-003）。**项目级**权威键只有一把：`project-chat-session|{ws}|{project}`。

| 路径 | ① | ② | ③ | ④ |
|---|---|---|---|---|
| GET Ensure | advisory `project-chat-session\|{ws}\|{project}` | 事务内重读 `team_agent_id`；insert session；可选收养 | — | — |
| PATCH config | 同 advisory | session `FOR UPDATE` | active+agent_id CAS UPDATE | — |
| 发送 / container / merge-forward | 同 advisory | session `FOR UPDATE` | Bind（含 COUNT==1 收养） | `LockUnboundDraftAttachments` `ORDER BY id` |
| 换绑 close | 同 advisory | `CloseActiveProjectChatSession` | 不建 Issue | — |
| 转投 `EnsureProjectChatIssue` | **同** advisory（内部 lockKeyPrefix 改为 `project-chat-session`） | 锁内 `GetProjectChatIssue` 重检 | 未命中则创建 `origin_id=NULL` | — |
| 草稿 sweeper | **不**拿 advisory | attachment `FOR UPDATE SKIP LOCKED` | 持锁 `DeleteObject` | `DeleteUnboundDraftAttachment` |

Bind 可选的 session 键 `project-chat|{ws}|{session.id}` 只出现在 ① 之后，不与转投抢项目级锁。`EnsureProjectDiscussionIssue` 仍用 `project-discussion|{ws}|{project}`，与上表无关。

sweeper 不参与项目 advisory，故与发送不成环：发送等待附件行锁即可。

实施期竞态夹具（映射 AC-18 / NFR-7，不新增 AC 编号）：

1. **GET 收养检查 ∥ 转投 Ensure**：无遗留 Issue 时并发打开面板与 `EnsureProjectChatIssue`；结束后至多一行 `project_chat`，第一行 session 若已存在则 `issue_id` 指向该行（收养或随后 Bind 收养），不得一转投旧容器 + 一 session 新容器。
2. **转投创建后首次 Bind**：Ensure 先提交 `origin_id=NULL`，再对该项目第一行 session 调 Bind；必须 CAS 收养同一 Issue，禁止第二行。
3. **同 `created_at` 双行 `GetProjectChatIssue`**（BLOCK-017）：插入两行相同 `created_at`、不同 `id` 的 `project_chat`；`:one` 固定返回 `id` 较小者；重复查询稳定。

---

## 5. 技术选型与决策记录

仅记录同时满足「难以逆转 + 无上下文会疑惑 + 有真实权衡」的决策。

### D-1 新表 `project_chat_session` vs 复用 `chat_session`

- **Decision**：Team Agent 用新表；Private Ask 扩展 `chat_session`。
- **Context**：Private Ask 已是 `(project_id, creator_id)` 一人一行；Team Agent 是项目共享、可空 `issue_id`、换绑需 closed 历史。`chat_session.status` 已是 `archived`，与 `closed` 冲突；sqlc 已有 `GetProjectChatSessionForCreator`。
- **Alternatives**：全部塞进 `chat_session`（要用 `kind` 区分，污染 1:1 聊天与唯一约束）；配置写入 `project.settings` / `issue.metadata`（PRD 已禁，且无 Issue 时不可保存）。
- **Consequences**：两套 PATCH 路径；后续 CR-B Discussion 可再挂同类配置契约，不必回头拆表。

### D-2 发送时冻结 `context.chat_config` vs 给队列加列

- **Decision**：JSONB merge，不加 `agent_task_queue` 列。
- **Context**：NFR-3；context 已承载 `head_sha` 等。
- **Alternatives**：专用列（迁移面大、与「任务单一路径」相比无收益）；claim 时现读 session（排队改配置会改语义，违反 FR-14）。
- **Consequences**：claim 必须会解析 JSON；旧任务无键则回退 agent 列。

### D-3 离线校验用 `ModelCatalogCache` 24h 窗口；在线走同步 LiveLoad

- **Decision**：Waitable 只用 last-known-good cacheable 快照（24h）；Available 先 cache 快路径，miss 则 `ChatCatalogPort.LiveLoad` 同步等 30s。领域校验在 `pkg/agent.ValidateChatConfig`；cache/live 适配器留在 handler。
- **Context**：PRD B-004 / FR-4；`InitiateListModels` 对 picker 仍异步；四入口不能 202。
- **Alternatives**：service 直接依赖 `handler.ModelCatalogCache`（违反 handler→service）；无目录放行（不可验收）；静态 catalog（PRD 禁止）；Available 每次强制 live（PATCH 常等 30s）。
- **Consequences**：长时间离线且无 cache 无法改配置或发送；Available cache miss 最坏阻塞 30s。

不单独开 ADR 文件，不新增审批节点。

---

## 6. FR 到技术实现映射

| FR | 技术方案条目 |
|---|---|
| FR-1 | UI 去掉 `updateAgent`；服务端配置写只碰 session 列；管理页仍走 `UpdateAgent` |
| FR-2 | 一项目一 active `project_chat_session`；PATCH 服务端 owner/admin；presenter 只管发送 |
| FR-3 | Private Ask 仍按 `(workspace_id, project_id, creator_id)`；override 不写 Team Agent 表 |
| FR-4 | §4.3 `ChatCatalogPort` + `agent.ValidateChatConfig`；PATCH + messages + container + merge-forward（**不含转投**）；Waitable+cache / Waitable+no-cache / Available+LiveLoad 超时 / Blocked |
| FR-5 | Insert 时写 `base_*`（允许 `base_model=''`）；Private Ask 新建同样 |
| FR-6 | §4.2 / §4.2.1 优先级、空模型哨兵与 PATCH 三态；source 与有效值一致 |
| FR-7 | §4.7 close 旧 session；§4.7.1 GET/PATCH CAS；新 session 新 Issue |
| FR-8 | GET 只 Ensure session；响应含可空 `issue_id` 与 source |
| FR-9 | PATCH 不要求 `issue_id` |
| FR-10 | §4.4 共用 Bind；POST container 先 §4.3 再 Bind |
| FR-11 | `chat_session` 四列 + GET 不回写 + 首次 PATCH/发送回填 |
| FR-12 | `PATCH /api/chat/sessions/{id}/config` creator-only；`GetChatSessionInWorkspace` |
| FR-13 | enqueue merge `chat_config`；含 merge-forward（§4.12）。**不含** Coordinator 转投（§4.13 KG-1） |
| FR-14 | §4.8 claim 读快照；旧任务不回填 |
| FR-15 | 上传省略 issue_id；§4.9 上传者门 |
| FR-16 | §4.5 首次绑定与发送同事务；失败 rollback；§4.10 行锁覆盖对象删除与条件删行 |
| FR-17 | §3.3 + 前端按 code 回滚控件/保留草稿 |
| FR-18 | 复用 ChatInputCore + Picker；只改数据源 |
| FR-19 | §2.1 新表 + 容器 `origin_id` |
| FR-20 | §2.6 迁移 472–480 + CUSTOM.md |
| FR-21 | PATCH/发送必带 session_id；校验 workspace/project/active/agent_id |

### 6.2 AC 闭环（设计落点 / 可观察结果 / 可达性）

| AC | 设计落点 | 可观察结果 | 可达性 |
|---|---|---|---|
| AC-1 | `project-team-agent-chat.tsx` persist → PATCH；禁 `updateAgent` | `agent.model` 不变；spy 无 UpdateAgent | 有 Team Agent 的 owner/admin |
| AC-2 | 同上 Thinking PATCH | `agent.thinking_level` 不变 | 同 AC-1 |
| AC-3 | Private Ask session 按 creator | 用户 B 的 GET/快照不变 | 两成员各有 Private Ask |
| AC-4 | session 按 project_id | 他项目 session/agent 不变 | 两项目 |
| AC-5 | 管理页仍读 agent 列 | 管理页展示不变 | 改聊天配置后打开 Agent 页 |
| AC-6 | handler 角色检查 | 403 `forbidden_chat_config` | 非 owner/admin 调 PATCH |
| AC-7 | context merge 在入队时（messages **与** merge-forward；**不含转投**） | 排队任务 JSON `chat_config.model` 仍为 A | 先发送/转发再 PATCH |
| AC-8 | claim 读 task 行 | 重试后 model/thinking 与入队时相同 | 有 `chat_config` 的任务 |
| AC-9 | handler 测试 catalog miss | 400；已入队 context 不变 | **不以** daemon pass-through 为通过条件；命令见 PRD |
| AC-10 | merge 保留既有键 | 夹具含 `head_sha` + `chat_config`（含 merge-forward） | 入队路径 |
| AC-11 | GET 不调 EnsureIssue | 绿场响应 `issue_id=null`、无**新** `project_chat` 行；升级第一行 session 可带回已有遗留 Issue（§2.1） | 打开空面板（绿场） |
| AC-12 | PATCH 持久化 session | 刷新 GET 同 `session_id` 同 override | 无 Issue 亦可 |
| AC-13 | 并发 container+messages 测 | 两成功体 `issue_id` 相同且非空；读响应 JSON 不事后只 GET | 无 Issue 的 active session |
| AC-14 | 上传无 issue_id + 上传者门 | 其他成员 GET/download 404；列表无 | 无容器时上传 |
| AC-15 | 同事务 Bind+comment；失败 rollback | 成功后成员可见；失败：无 `session.issue_id`、无空容器、五类空 | 首次发送失败夹具（enqueue/附件错误） |
| AC-16 | Insert 写 base_* | 改 Agent 后 GET source=`session_default` 且值为旧快照 | 新建 session |
| AC-17 | PATCH 三态 | null/"" 清 override；省略不改 | 有 override 的 session |
| AC-18 | §4.7 + `origin_id=session.id` + §2.1 收养窗口（COUNT==1 的 GET 或 Bind） | 旧 session closed；新 GET 新 session id **且新 issue_id**；旧评论不在新 timeline；升级后未发送即换绑不得把遗留 Issue 交给 B | 改 `team_agent_id` 后 GET + 发一条；另见升级 fixture 与 §4.14 夹具 1–2 |
| AC-19 | GET 不写 base；首次 PATCH/发送才写 | 中间改 Agent，GET 仍 `agent_default`；回填后跟 base | 历史 NULL 行夹具 |
| AC-20 | closed / 未配置 | 409 对应 code | closed session 与无绑定项目 |
| AC-21 | 两入口可写 picker | 无 UpdateAgent；draft/附件/发送/停止/重试不回归 | 现有 ChatInputCore 测 |
| AC-22 | 472–480 迁移 + CUSTOM.md | 无 FK；CONCURRENTLY；一文件一句；已 DROP `issue_project_chat_unique` | 读迁移文件与台账 |
| AC-23 | POST container | GET `issue_id` 变同一 UUID；缺 session_id 不建 Issue；§4.3 失败不建 Issue | 无 Issue session |
| AC-24 | 三夹具覆盖 PATCH、messages、container、**merge-forward**（**不含转投**） | Waitable+cache 成功；无 cache 全部 400 且不建 Issue；Available LiveLoad 超时 400；Blocked 拒绝；空 model 矩阵见 §4.2.1 | handler+service 测试，命令见 PRD |
| AC-25 | Private Ask PATCH 鉴权 | 非创建者 403 | 与 AC-6 分工 |
| AC-26 | locale keys | `parity.test.ts` 绿 | 新增文案 |
| AC-27 | schemas.test.ts | 硬降级 fallback；软默认 source=`session_default` | 无伪造 UUID |
| AC-28 | sweeper 单测 + 与 Bind 并发 | 167h59m 留 / 168h00s 留 / 168h01s 删对象+行；对象失败保留行；Storage=nil 不删行；Bind 抢先则 sweeper 不得删已绑定行/对象 | `go test ... -run ChatDraftAttachment` |

无「过滤条件使 AC 不可达」：Waitable 离线发送在 AC-24① 明确允许；AC-9 明确排除 daemon 降级路径。另需实施期夹具（映射到上表，不新增 AC 编号）：换绑双容器唯一性（AC-18）、升级后未发送即换绑（AC-18）、GET/PATCH 与换绑并发 CAS（AC-20/FR-21）、首次发送失败回滚（AC-15）、POST container 校验失败不建 Issue（AC-23/24）、merge-forward `chat_config`（AC-7/10）、sweeper 与 Bind 竞态（AC-28）、空 model provider 矩阵（AC-9/24）、catalog LiveLoad 超时（AC-24）、Private Ask 跨 workspace 0 行（FR-3/Hard Invariant 1）、`GetProjectChatIssue` 多行时仍 `:one` 且 **同 `created_at` 双行固定较小 `id`**（§4.13 / §4.14 夹具 3）、GET 收养 ∥ 转投 Ensure 与转投后首次 Bind 均收敛到单容器（§4.14 夹具 1–2）。转投无 `chat_config`、换绑后转投仍写旧 Issue **不是**本 CR 验收项（§4.13 KG-1/KG-2）。

---

## 7. 安全与性能考量

### 7.1 安全控制点

- **配置写权限服务端强制**（NFR-5）：前端隐藏不足够（AC-6/AC-25）。
- **session 归属**：`session_id` 必须匹配 workspace/project/active/`agent_id`；漂移 409，不静默切 Agent（FR-21）。
- **未绑定附件**：上传者门 + 不进项目列表/WS；UUID 猜测无效（FR-15）。今日 `loadAttachmentForRequest` 仅 workspace 范围，本 CR 收紧未绑定分支。
- **task context**：客户端不得提交任意 `chat_config`；只服务端 Resolve 后写入。
- **Workspace isolation**：所有查询带权威 `workspace_id`；`GetProjectChatSessionForCreator` 改造后缺 workspace 不得编译通过；请求体 workspace 不得覆盖认证上下文。跨 workspace 负向测试必写。
- **UpdateAgent**：聊天路径零调用，避免跨项目污染 Agent。
- **换绑历史隔离**：timeline 只读当前 session.`issue_id`，禁止按 project 拉 `project_chat` 评论。GET/PATCH 必须在 advisory 内重读绑定并用 active+agent_id CAS，避免向 closed session 写配置或按旧 agent 插入 session。

### 7.2 性能

- GET 打开面板：一次 get-or-create session，不再创建 Issue（减少 issue 计数/position 热路径）。
- catalog：Waitable 只读 24h cache，不 LiveLoad。Available cache 命中不挡请求；cache miss 同步 LiveLoad 最多 30s。handler 适配器，service 不依赖 `ModelCatalogCache` 类型。
- sweeper：1h 一次；持行锁删对象。谓词可用五类空 + `created_at`；若缺复合索引，一期全表扫描草稿量可接受；若实施期 EXPLAIN 显示过热，再加 **单独** CONCURRENTLY 部分索引（不在请求路径建）。
- Bind 行锁范围：单 session 行 + 项目 advisory `project-chat-session|{ws}|{project}`（与转投 Ensure 共享）+ 附件 id 升序。容器可选 session 锁 `project-chat|{ws}|{session.id}` 不与 Discussion 的 `project-discussion` lock 冲突。

### 7.3 边界条件

- 空 `thinking_level`：不注入；catalog 即使无 Thinking 也接受。
- 空 `model`：合法哨兵（§4.2.1）；Codex 空模型 + 非空 thinking 拒绝。
- `base_*` NULL vs `''`：见 §0 / §4.2。
- 旧任务无 `chat_config`：claim 用 agent 列。
- 发送失败：整个发送事务 rollback（含尚未提交的容器）；附件草稿保留；不返回半成品 `issue_id`。POST container 成功提交的空容器除外。
- 硬降级：禁止用空 `session_id` 发 PATCH/发送。
- merge-forward 无 session_id：服务端 Ensure active session + 同一校验/Bind/`chat_config` 内核。Coordinator 转投无 session_id：**不**走该内核（§4.13）。

---

## 8. Prompt 采纳影响

本 CR **不触及** `crctl.mjs` dispatch，也 **不触及** `controlled-shell/rules.json` 的 `protectedPaths.deny`。本节省略。

---

## 9. 既有实现依赖与事实

目标仓 `multica` HEAD（本 CR worktree，BLOCK-015 本轮复核）：`8746add879cbd1c78e573c2a4a1776e16158c00c`。

证据：`crctl git rev-parse HEAD --cwd` → 资源 `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-056` 输出该 SHA，与 PRD §1.4 基线声明一致。上一轮评审读到的 `0b7687b554a8b2f51afa740ffb95c4a06e27e272` **不是**当前 authority HEAD；资源已定位到声明 commit，下列依赖均在该 SHA 重新核验（路径存在、符号可定位）。本 CR 新增符号（`ValidateChatConfig` / 导出 `ModelIDForCapabilityLookup` / `StaticCatalog`）仍为设计落点，基线仓尚未实现——这与 BLOCK-014 的「下沉到 pkg/agent、service 只转发」一致，不是基线漂移。

按正文首次依赖顺序：

| # | repo | relative path | stable symbol/对象 | 依赖结论 |
|---|---|---|---|---|
| 1 | multica | `server/internal/handler/project_chat.go` | `GetProjectChat` / `EnsureProjectChatIssue` | 今日 GET 懒创建隐藏 Issue；本 CR 改为只 Ensure session |
| 2 | multica | `server/internal/service/project_chat.go` | `EnsureProjectChatIssue` / `ensureContainerIssue` / `sendProjectChatCore` | 今日按 project 查并自 Commit；锁键 `project-chat\|ws\|project`（`:41` 传入 `"project-chat"`，`:109` 拼接）。**Team Agent 路径**改为 session 作用域 Bind，接受外层 tx；GET 禁止调用。`EnsureProjectChatIssue` 函数本身保留给转投（§4.13）；本 CR **只改** `lockKeyPrefix` 为 `"project-chat-session"`，使与 GET/Bind 共享项目级协议（BLOCK-016） |
| 3 | multica | `packages/views/projects/components/project-team-agent-chat.tsx` | `persistModel` → `api.updateAgent`；`TeamAgentComposer` `uploadWithToast(file, { issueId })` | 模型写 Agent；上传绑定 issue。改为 session PATCH；无 Issue 时省略 issue_id |
| 4 | multica | `packages/views/projects/components/project-private-ask.tsx` | 只读 `ModelPicker` / `agent.model` | 改为 session 可写配置 |
| 5 | multica | `server/pkg/db/queries/chat.sql` | `GetProjectChatSessionForCreator` | **专指** Private Ask；WHERE **必须加 `workspace_id`**（今日只有 project/creator）；新表不得占用此名 |
| 6 | multica | `server/migrations/033_chat.up.sql` | `chat_session` 表；`agent_task_queue.issue_id` 可空 | Private Ask 扩展四列；任务可无 Issue |
| 7 | multica | `server/migrations/436_chat_session_project.up.sql` 及相关 unique | `(project_id, creator_id)` active 唯一 | 保留该索引；查询另加 workspace 谓词 |
| 8 | multica | `server/migrations/471_approval_continuation_workspace_cr_pending_unique.up.sql` | 当前最大迁移号 471 | 本 CR 从 **472** 起到 **480** |
| 9 | multica | `server/internal/service/agent_ready.go` | `AgentReadiness` / `AgentAvailable` / `AgentWaitable` / `AgentBlocked` | PATCH/发送 readiness；Waitable 仍可入队 |
| 9a | multica | `server/internal/service/chat_config.go` | `ResolveChatConfig` / `ChatCatalogPort` / `ValidateResolvedChatConfig` | **本 CR 新增**；四入口唯一校验入口。`ValidateResolvedChatConfig` 只转发 `agent.ValidateChatConfig`，不复制归一化 |
| 10 | multica | `server/internal/handler/runtime_model_catalog.go` | `ModelCatalogCache` / `modelCatalogServeWindow` / `cacheableModelCatalog` | **留在 handler**；经 `ChatCatalogPort.CacheLoad` 注入 service；24h；禁止 fallback |
| 11 | multica | `server/pkg/agent/thinking.go` | `ValidateThinkingLevelWith` / **新增** `StaticCatalog` / **新增** `ValidateChatConfig` | 空 thinking 接受；codex 空 model + 非空 thinking fail-closed。`ValidateChatConfig` 经 `StaticCatalog` 调用前者；service 不得自己写 loader 或第二套规则 |
| 11a | multica | `server/pkg/agent/models.go` | `Catalog` / `Model` / **导出** `ModelIDForCapabilityLookup` | 领域类型；空 model 交给 CLI 默认。未导出 `modelIDForCapabilityLookup` 升格为导出符号；`claudeContextWindowTagRe` 只留本包。handler `ModelEntry` 只做 wire 适配 |
| 12 | multica | `server/internal/handler/daemon.go` | `TaskAgentData.Model` / `ThinkingLevel` ← `agent.Model` | claim 改为优先 `context.chat_config`（允许 model=""） |
| 13 | multica | `server/internal/daemon/daemon.go` | `resolveTaskModelSelection` catalog miss pass-through | **不是** AC-9 验收路径 |
| 14 | multica | `server/internal/service/task.go` | `enqueueMentionTaskWithCommentPlan`；`agent_task_queue.context` JSONB | merge `chat_config`，禁止整对象覆盖 |
| 15 | multica | `server/pkg/db/queries/attachment.sql` | `DeleteAttachment` 只排除 `source_context_id`；`LockAttachmentsForIssueLink` | 草稿 Bind 用新五类空锁查询；sweeper **禁用** `DeleteAttachment`，改 `DeleteUnboundDraftAttachment` |
| 16 | multica | `server/internal/handler/file.go` | `UploadFile` form `issue_id`；`loadAttachmentForRequest` 仅 workspace | 草稿省略 issue_id；未绑定行加上传者门 |
| 17 | multica | `server/internal/handler/file.go` | `linkAttachmentsByIDs` 在发送成功后事务外调用 | 改为发送事务内绑定 |
| 18 | multica | `server/cmd/server/runtime_sweeper.go` | `runRuntimeSweeper` 30s 心跳 | 草稿清理用独立 1h 节流；注入 `storage.Storage` |
| 19 | multica | `server/internal/handler/handler.go` | `writeErrorCode` | FR-17 稳定 `code` 字段 |
| 20 | multica | `server/cmd/server/router.go` | `GET /chat`、`POST /chat/messages`、`GET /private-chat` | 增 PATCH config、POST container；messages 扩展 body |
| 21 | multica | `server/internal/handler/project.go` | `settings.team_agent_id` PATCH | 换绑与 close 同一 advisory；不建新 Issue |
| 22 | multica | `packages/core/api/schema.ts` | `parseWithFallback` | NFR-8 硬/软降级 |
| 23 | multica | `packages/core/api/schemas.ts` | `ChatSessionSchema` / `EMPTY_CHAT_SESSION` | **不要**给 `session_id` 加 default `""` 当已登录；配置响应用独立 schema |
| 24 | multica | `packages/core/api/schemas.test.ts` | 现有 fallback 夹具模式 | AC-27 追加 |
| 25 | multica | `packages/views` ChatInputCore / draft adapter | `project-team-agent-chat.tsx` `useTeamAgentDraftAdapter` | 功能接入不重做视觉 |
| 26 | multica | `packages/views/agents/components/inspector/thinking-picker.tsx` | `ThinkingPicker` | 空串哨兵与 Agent 页一致 |
| 27 | multica | `CUSTOM.md` | 台账末号当前 #58（CR-2026-054） | 本 CR 编号顺延登记 |
| 28 | multica | `ARCHITECTURE.md` | Hard Invariant 1 Workspace isolation | 每个查询带权威 workspace；`GetProjectChatSessionForCreator` 今日违规，本 CR 改造。不变量 6：新索引 CONCURRENTLY 单语句 |
| 29 | multica | `server/internal/service/project_chat.go` | `MergeForwardDiscussion` / `sendProjectChatCore` | §4.12：Ensure session + Resolve + Bind-in-tx + `chat_config`；不改 Discussion GET/发消息 |
| 30 | multica | `server/migrations/435_issue_origin_project_chat.up.sql` | `issue_project_chat_unique` on `project_id`；`origin_id` NULL | **DROP** 该索引；容器改 `origin_id=session.id` |
| 31 | multica | `server/pkg/db/queries/issue.sql` | `GetProjectChatIssue` / `GetIssueByOrigin` | 今日 `:588-592` 无 ORDER，依赖 `issue_project_chat_unique`。Team Agent 解析改用 origin/session。`GetProjectChatIssue` 加 `ORDER BY created_at ASC, id ASC LIMIT 1`（§4.13 / BLOCK-017）；**仅**转投继续调用。升级收养用 `GetLegacyUnboundProjectChatIssue`（§2.4） |
| 32 | multica | `server/internal/handler/file.go` | `deleteS3Object` → `Storage.Delete` | sweeper 必须用 `DeleteObject`（返回 error）以便重试 |
| 33 | multica | `server/internal/storage/storage.go` | `Storage.DeleteObject` | sweeper 的对象存储依赖；nil Storage 本 tick 跳过 |
| 34 | multica | `server/internal/handler/comment.go` | `retargetDiscussionCoordinatorRoute` → `EnsureProjectChatIssue`（`:2713-2753` / 调用 `:2745`） | **本 CR 零改动**。继续 Ensure；不改调 Bind / 新签名（§4.13）。锁协议收敛在 `project_chat.go` 内部 |
| 35 | multica | `server/internal/service/project_presenter.go` | `GetProjectChatIssue` | 改读 active session.`issue_id`；未绑定则跳过（Team Agent 活动记录，不是转投改造） |
| 36 | multica | `server/internal/service/autopilot.go` | `GetProjectChatSessionForCreator` | 传入权威 `workspace_id` |
| 37 | multica | `server/internal/service/discussion_coordinator.go` | `RouteDiscussionToTeamAgent` | **本 CR 零改动**。签名与无快照 enqueue 保持现状（§4.13 KG-1） |
| 38 | multica | `server/internal/handler/runtime_models.go` | `InitiateListModels` / `modelListPendingTimeout=30s` | picker 仍异步；`ChatCatalogPort.LiveLoad` 同步等待同一 pending-work，超时 30s |

`tools` 仓：本 CR 无实施依赖（PRD 范围排除）。不得把 `tools/ARCHITECTURE.md` 的「零依赖 / crctl 单一写者」抄进本设计。

---

## 10. 实施文件清单与提交口径

### knowledge-base

本文件：`change-requests/CR-2026-056/sdd.md`。提交：`[cr] write tech design CR-2026-056`。

### multica（code-implementation 阶段）

迁移 472–480、sqlc（含 `GetProjectChatIssue` `ORDER BY created_at ASC, id ASC LIMIT 1`）、`project_chat.go` handler/service（Bind 接受外层 tx；**Ensure 仅改 lockKeyPrefix**）、`chat_config.go`（Resolve + `ChatCatalogPort` + 转发 `agent.ValidateChatConfig`）、`pkg/agent`（导出 `ModelIDForCapabilityLookup` / `StaticCatalog` / `ValidateChatConfig`）、task enqueue merge、daemon claim、file 上传者门、sweeper+Storage（条件删行）、router、project settings 换绑挂钩、presenter 活动 issue 查找、Private Ask workspace 查询、zod/client、Team Agent / Private Ask UI、locale、Go/React 测试（含 §4.14 三夹具）、`CUSTOM.md`。

**不改**：`comment.go` 转投、`discussion_coordinator.go` 签名与事务。

ARCHITECTURE.md 已存在，本轮只读不改。

各仓在所属 `resources[].worktreePath` 分别提交；架构审批后同一批 `crctl checkpoint` 纳入。

### 测试命令（实施/验收，非本节点执行）

```text
go test ./server/internal/handler/ ./server/pkg/agent/ ./server/internal/service/ -count=1
go test ./server/internal/service/ -count=1 -run ChatDraftAttachment
# 前端：packages/core/api/schemas.test.ts 与 views locales parity、team-agent / private-ask 组件测
# 实施期必须覆盖 §4.14 夹具 1–3（GET∥转投、转投后首次 Bind、同 created_at 双行 :one）
```

---

## 11. 残余风险

| 风险 | 控制 |
|---|---|
| 已安装桌面客户端仍把 GET `issue_id` 当必填字符串 | 独立 schema 硬降级只读 + 重试 GET；不伪造 session |
| merge-forward 无 session_id | §4.12 Ensure session + Resolve + 同事务 Bind + `chat_config` |
| Coordinator 转投无 `chat_config`（KG-1） | **已知缺口**，归属 CR-B/CR-C；本 CR 不修、验收不打回 |
| 换绑后转投仍写旧 Issue（KG-2） | **已知缺口**，归属 CR-B/CR-C；换绑只作用于 `project_chat_session` 新容器 |
| `LinkAttachmentsToComment` 误用于草稿 | 新 Bind 查询；测试覆盖无 issue_id 上传 |
| daemon 仍读 agent.model | claim 单点改 `TaskAgentData`；AC-7/8 读 context 与 claim 夹具 |
| 历史 Private Ask GET 跟随 Agent 直到首次写 | FR-11/AC-19 明确；新 session 禁止 `agent_default` |
| 升级前遗留 `origin_id` NULL 容器 | GET Ensure **或** 第一行 session 的 Bind 在 `COUNT(session)==1` 且 `issue_id` NULL 时收养；换绑后 COUNT≥2 新建 Issue（BLOCK-009 谓词不回退） |
| GET 与转投、转投与首次 Bind 竞态 | 共享 `project-chat-session|{ws}|{project}`；§4.14 夹具 1–2 |
| `GetProjectChatIssue` 同时间戳多行 | `ORDER BY created_at ASC, id ASC LIMIT 1` + 夹具 3 |
| GET/PATCH 相对换绑的 stale read | §4.7.1 同一 advisory + 事务内重读 + active/agent CAS |
| sweeper 与 Bind 竞态 | §4.10 行锁覆盖 DeleteObject + 条件 DELETE；禁用 `DeleteAttachment` |
| target-version 仍为 tbd | 人工架构审批前由需求负责人补（SUG-001，非本轮 blocker） |
