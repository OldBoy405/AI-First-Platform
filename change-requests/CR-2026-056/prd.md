---
id: CR-2026-056-prd
type: PRD
cr-ref: CR-2026-056
title: 会话级配置与 Team Agent 闭环
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-30T16:45:00+08:00
updated: 2026-08-30T16:45:00+08:00
---

# 1. 概述

## 1.1 问题陈述

当前项目聊天把「Agent 长期基础配置」和「这一次对话要用的模型 / Thinking Mode」绑在同一条写路径上：

- Team Agent 发送框选择模型会调用 `UpdateAgent`，直接改写共享的 `agent.model`，影响该 Agent 的其他调用者。
- Team Agent 发送框没有 Thinking Mode 控件；若沿用 Agent 配置页的 `thinking_level`，会产生同样的跨会话污染。
- Private Ask 的模型展示只读跟随 Team Agent，用户无法在自己的会话里独立选择模型或 Thinking Mode。
- `GET /api/projects/{id}/chat` 打开面板就会 `EnsureProjectChatIssue`，空面板也会留下隐藏 `project_chat` 容器。
- 任务入队后若重新读取可变的 Agent 或会话配置，排队期间改配置会改变原消息语义。
- 发送前附件如果提前进入项目可见范围，草稿会在发送成功前泄露给其他成员。

以上事实已在来源文档 §14 记录，并在本 CR 落笔前按当前 `../multica` 工作区复核（见 §1.4）。本 CR 不处理 Discussion 共享会话。

## 1.2 解决方案摘要

把配置从 Agent 挪到会话，把执行值冻结到任务：

```text
Agent          = 长期共享的智能体基础配置（聊天窗口不得改写）
Chat session   = 当前对话的配置和上下文边界
Task           = 一次发送时冻结的不可变执行快照
Issue          = Team Agent 首次发送或显式创建后才绑定的执行容器
```

本 CR（来源文档 CR-A，注册摘要已拍板）交付一个可独立验收的闭环：

1. 新增 `project_chat_session`，支持无 `issue_id` 的 active session；打开 Team Agent 只创建或读取 session，不创建隐藏 Issue。
2. 显式创建聊天容器与首次发送走同一幂等服务路径；首次发送时才绑定隐藏 `project_chat` Issue。
3. Private Ask 现有 `chat_session` 增加基础快照与 override；配置按创建者隔离。
4. Model Picker / Thinking Mode **功能接入**会话配置接口，不调用 `UpdateAgent`；不重做发送框视觉体系。
5. 发送入队前解析有效配置，合并写入 `task.context.chat_config`；daemon / 重试 / 重新 claim 只读快照。
6. Team Agent 发送前附件保持未绑定草稿，发送成功时与 Issue / comment / task 同事务绑定。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

让 Team Agent 和 Private Ask 的模型与 Thinking Mode 成为会话级配置，发送时冻结为不可变任务快照；Team Agent 打开面板只创建/读取 session，不创建隐藏 `project_chat` Issue，首次发送或显式创建才绑定容器。不含 Discussion 共享会话、Coordinator、Discussion 附件/升级，以及发送框整体视觉重构。

目标仓库为 sibling `../multica/`。knowledge-base 承载本 PRD 与来源文档；`../tools/` 无实施改动。

## 1.4 当前代码事实（落笔前核实）

基线声明来自来源文档：CR-2026-055 合并后的 Multica，commit `8746add879cbd1c78e573c2a4a1776e16158c00c`。本工作区复核结论：

| 结论 | 证据 |
|---|---|
| Team Agent GET 懒创建隐藏 Issue | `server/internal/handler/project_chat.go` `GetProjectChat` 调用 `EnsureProjectChatIssue` |
| 容器创建集中在服务层 | `server/internal/service/project_chat.go` `EnsureProjectChatIssue` / `ensureContainerIssue` |
| Team Agent 模型选择写 Agent | `packages/views/projects/components/project-team-agent-chat.tsx` `persistModel` → `api.updateAgent` |
| Team Agent 无 Thinking Mode 控件 | 同文件无 `thinking` / `ThinkingPicker` 引用 |
| Private Ask 模型只读跟随 Team Agent | `packages/views/projects/components/project-private-ask.tsx` |
| 不存在 `project_chat_session` 表 | 全仓 SQL/Go 无该标识符 |
| Private Ask 已有 `(project_id, creator_id)` active 唯一约束 | `server/migrations/436_chat_session_project.up.sql` |
| `chat_session` 无模型/Thinking 快照字段、无 `kind` | `033_chat.up.sql` 及后续迁移未增加这些列 |
| 任务 `context` 为 JSONB，可无 Issue 的 chat task | `033_chat.up.sql`；`server/pkg/db/queries/agent.sql` |
| attachment 已支持未绑定及 session/message/task 关联 | `029_attachment.up.sql`、`083_attachment_chat_columns.up.sql`、`164_attachment_task_id.up.sql` |
| 当前最大迁移编号 **471** | `server/migrations/471_approval_continuation_workspace_cr_pending_unique.up.sql` |

# 2. 用户故事

- **US-1 项目 owner/admin**：作为项目管理员，我希望在 Team Agent 窗口改模型和 Thinking Mode 只影响当前项目的这条对话，从而不会改掉 Agent 管理页里的基础配置，也不会影响其他项目或其他调用者。
- **US-2 项目成员**：作为项目成员，我希望打开 Team Agent 面板时不会悄悄创建一个隐藏 Issue，只有我真正发第一条消息或显式创建聊天容器时才出现执行容器。
- **US-3 Private Ask 用户**：作为项目内私聊用户，我希望自己的模型与 Thinking Mode 独立于其他用户和 Team Agent 会话，从而可以按自己的问题选择配置。
- **US-4 发送者**：作为发送者，我希望发出去的消息在排队、重试、重新 claim 时仍使用发送当时的模型和 Thinking Mode，从而排队期间改配置不会改写原意。
- **US-5 附件上传者**：作为附件上传者，我希望发送前的草稿只有我能看见、删除和重试绑定；发送失败时草稿还在，发送成功后才和消息一起对项目成员可见。
- **US-6 平台维护者**：作为平台维护者，我希望复用现有 `chat_session`、`ChatInputCore`、任务 `context`、attachment 和 `EnsureProjectChatIssue`，不把配置写进 `agent`、`project.settings` 或 `issue.metadata`，从而后续 CR-B/C/D 能在同一套会话配置契约上扩展。

# 3. 功能需求

## FR-1 聊天窗口不得改写 Agent 持久化配置

Team Agent 和 Private Ask 修改模型或 Thinking Mode 时，服务端与客户端都不得调用 `UpdateAgent`，也不得修改 `agent.model`、`agent.thinking_level` 或 Agent 的其他持久化字段。Agent 管理页展示的基础配置必须保持不变。来源 FR-1。

## FR-2 Team Agent 配置属于项目共享 active session

第一阶段每个项目最多一个 active Team Agent session。修改配置的权限为项目 owner/admin，必须在服务端强制；presenter 仍控制 Team Agent 消息的单一写者规则，但不自动改变会话配置权限。来源 FR-2、§9。

## FR-3 Private Ask 配置按创建者隔离

Private Ask 配置属于当前用户自己的 Private Ask session。用户 A 的 override 不得影响用户 B，也不得写回 Team Agent session。继续使用现有 `(project_id, creator_id)` active session 查询。来源 FR-3。

## FR-4 配置 PATCH 与发送入队都必须做服务端校验

两次校验都至少包括：当前用户是否有配置/发送权限；model 是否属于当前 runtime 支持的模型目录；Thinking Mode 是否被当前 runtime/provider 支持；runtime 是否在线或允许进入队列；session 是否仍为 active。前端不得直接提交任意 task context。来源 FR-28、§6.3。

## FR-5 新建会话必须保存基础快照

新建 Team Agent `project_chat_session` 或 Private Ask `chat_session` 时，读取绑定 Agent 当时的默认 `model` 与 `thinking_level`，写入 `base_model` / `base_thinking_level`。Private Ask 创建时保存当前 Team Agent 的默认值，但不共享 Team Agent 之后的 override。来源 FR-5。

## FR-6 读取优先级与空值语义

有效值优先级：

```text
override → 会话基础快照 →（仅旧 session 兼容）Agent 当前默认 → runtime 默认
```

PATCH 空值语义必须全接口一致：字段未提供 = 保持当前值；JSON `null` 或空字符串 = 清除 override，回退到基础快照；非空字符串 = 设置 override。Agent 默认值事后变化不得改写已创建会话的基础快照。来源 FR-6、FR-7、§6。

## FR-7 项目绑定 Agent 变化时关闭旧 session

项目 Team Agent 绑定变化时：旧 active `project_chat_session` 置 `closed`；为新 Agent 创建新 active session 并复制新默认值；旧 Issue/session 保持只读历史。不得静默把旧完整历史灌入新 session。来源 FR-8、§11.3。

## FR-8 打开 Team Agent 不得创建隐藏 Issue

`GET /api/projects/{projectId}/chat` 可以创建或读取 `project_chat_session`，但不得调用 `EnsureProjectChatIssue`，也不得以任何其他路径创建隐藏 `project_chat` Issue。响应必须包含 `session_id`、可空的 `issue_id`、`team_agent_id`、有效 `model` / `thinking_level` 及其来源（`override|session_default|runtime_default`）。未配置 Team Agent 时保持现有未配置错误/引导语义。来源 FR-9、§7.1。

## FR-9 无 Issue 时也必须能保存配置

Team Agent session 在 `issue_id` 为空时必须能 PATCH 并持久化模型和 Thinking Mode。刷新页面后配置可从同一 active session 恢复。来源 FR-11。

## FR-10 显式创建与首次发送共用幂等容器路径

显式创建聊天容器和首次发送消息都必须经过同一个幂等服务路径：校验项目、session、Agent 与权限 → 解析有效配置并做 runtime capability 校验 → 对 `project_chat_session` 行锁或项目级并发锁 → 无 `issue_id` 时幂等创建隐藏 `project_chat` Issue 并回写 `session.issue_id`。并发请求最多产生一个 active session 和一个容器 Issue。来源 FR-10、FR-12、§8.1。

## FR-11 Private Ask 扩展现有 chat_session

在现有 `chat_session` 上增加 `base_model`、`base_thinking_level`、`model_override`、`thinking_level_override`。不新增 Private Ask 表。历史 session 缺失基础快照时允许一次兼容回退到当前 Agent 默认值；该回退不得用于新 session，也不得改写已入队任务。来源 §5.2、§11.2。

## FR-12 Private Ask 配置 API

Private Ask 通过现有项目入口读取 session，并通过 `PATCH /api/chat/sessions/{sessionId}/config` 更新配置。该通用 PATCH 在本 CR 只对 Private Ask（creator-only）生效；不得用它改 Team Agent 或 Discussion。不要通过 `UpdateAgent` 保存聊天窗口配置。来源 §7.2。

## FR-13 发送时冻结 chat_config 快照

Team Agent 与 Private Ask 发送入队前，服务端解析有效 model / thinking_level，将值写入任务 `context.chat_config`：

```json
{ "chat_config": { "model": "<id>", "thinking_level": "<level-or-empty>" } }
```

写入时必须合并保留 `context` 中已有字段（例如 `head_sha`、附件相关字段），禁止整对象覆盖。`thinking_level` 为空表示「不注入、跟随 CLI/runtime 默认」，与现有 Agent ThinkingPicker 的空字符串哨兵一致。来源 FR-26、§5.5。

## FR-14 执行、重试、重新 claim 只读任务快照

任务执行、重试和重新 claim 只使用该任务入队时的 `chat_config` 快照，不得重新读取当前会话或 Agent 配置。旧任务没有 `chat_config` 时保持既有执行行为，不对历史任务补写或重算配置。新任务一律写入快照。来源 FR-27、§11.2。

## FR-15 Team Agent 发送前附件是上传者草稿

发送前附件复用现有 `attachment` 行，不新增草稿表。发送前 `issue_id`、`comment_id`、`chat_session_id`、`chat_message_id`、`task_id` 必须全部为空。只有上传者可以访问、下载、删除和重试绑定；不得因为调用者知道 attachment UUID 就开放读取。不得出现在项目公共附件列表、Team Agent timeline 或团队 WebSocket 事件中。来源 FR-18、FR-19。

## FR-16 发送成功原子绑定，失败保留草稿

Team Agent 发送成功时，附件必须在同一发送事务中绑定到 Issue、comment 和 task。事务失败时 comment、task 和 Issue 绑定不得留下半成品；未绑定附件保留供重试。发送失败不得删除草稿附件。后台按既有或本 CR 声明的 TTL 清理长期未绑定附件。来源 FR-20（Team Agent 分支）、FR-21、§8.1。

## FR-17 可区分错误与前端回滚

至少保持以下可区分错误，前端根据错误回滚配置控件或保留草稿，不静默丢失输入和附件：

```text
400 invalid_model_or_thinking_level
403 forbidden_chat_config
404 chat_session_not_found
409 chat_session_closed_or_changed
409 team_agent_not_configured
409 attachment_already_bound
```

来源 §7.3。

## FR-18 Model / Thinking 功能接入，不重做 composer

Team Agent 和 Private Ask 必须提供可写的 Model Picker 与 Thinking Mode 控件，调用会话配置接口（Team Agent：`PATCH /api/projects/{projectId}/chat/config`；Private Ask：`PATCH /api/chat/sessions/{sessionId}/config`）。须保留现有 `ChatInputCore`、draft adapter、草稿附件、上传状态、发送中、停止和失败重试行为。本 CR 只接入功能控件，不把发送框整体视觉对齐普通非项目聊天（该工作属 CR-D）。来源 FR-29 至 FR-33 中与功能接入相关的部分，以及来源 CR-A「不包含发送框整体视觉重构」。

## FR-19 project_chat_session 最小数据模型

新增表（字段名可在 SDD 微调，语义不得减）：

```text
project_chat_session
- id
- workspace_id
- project_id
- agent_id            # session 生命周期内不可变
- issue_id            # 可空；首次发送或显式创建前为空
- base_model
- base_thinking_level
- model_override      # 可空
- thinking_level_override  # 可空
- status              # active | closed
- created_by
- created_at
- updated_at
```

第一阶段一个项目最多一个 active session，由部分唯一索引 + 服务层并发锁共同保证。不采用：只给 `issue` 加字段、写入 `project.settings`、写入 `issue.metadata`、引入 `project_chat_thread`。来源 §5.1。

## FR-20 迁移、sqlc 与定制台账

新迁移从下一个可用编号 **472** 起。禁止新增 FOREIGN KEY / REFERENCES / 级联删除或更新；每个索引必须 `CREATE [UNIQUE] INDEX CONCURRENTLY` 且一个迁移文件一条语句；新建表的主键/唯一约束同样遵守该索引纪律。本 CR 在 multica 仓落地的新文件、挂钩点和迁移必须登记 `CUSTOM.md`。代码注释一律英文。

## FR-21 PATCH/发送携带 session_id 并防漂移

Team Agent 的 PATCH 与发送请求必须携带 `session_id`。服务端确认该 session 属于当前 workspace/project、处于 active，并且 `agent_id` 与项目当前 Team Agent 绑定一致；绑定漂移按 `409 chat_session_closed_or_changed` 或等价已列错误拒绝，不得静默切 Agent。来源 §7.1。

# 4. 非功能需求

- **NFR-1 双端一致**：web 与 desktop 共享 `packages/views` 行为一致；mobile 不在本 CR 范围。
- **NFR-2 四语文案**：新增 UI 文案提供 en/ja/ko/zh-Hans，locale parity 测试全绿。
- **NFR-3 复用优先**：复用 `chat_session`、`ChatInputCore`、任务 `context` JSONB、attachment 未绑定状态、`EnsureProjectChatIssue`。不给 `agent_task_queue` 增加模型/Thinking 专用列，不复制一套消息表。
- **NFR-4 并发与事务**：首次发送的容器创建必须在行锁/项目锁下幂等；配置修改只影响尚未入队的消息。
- **NFR-5 安全**：未绑定附件下载必须校验上传者；配置写权限不得只靠前端隐藏控件。
- **NFR-6 兼容**：旧 session 缺快照、旧任务缺 `chat_config` 的兼容路径仅用于历史数据，禁止成为新写入的默认路径。
- **NFR-7 零 Discussion 回归**：本 CR 不改变 `GetProjectDiscussion` / `EnsureProjectDiscussionIssue`、Discussion 发送路径、Private Ask 的 creator-only 访问规则（除按 FR-11/FR-12 增加配置字段和可写配置控件外）。
- **NFR-8 API 兼容**：新增响应字段必须经 `parseWithFallback` + zod schema；前端对缺失字段防御性默认。

# 5. 验收标准

| ID | 覆盖 FR | 可执行验收 |
|---|---|---|
| AC-1 | FR-1 | Team Agent 修改模型后，同一 Agent 的 `agent.model` 不变；`UpdateAgent` 不被该操作调用。 |
| AC-2 | FR-1 | Team Agent 修改 Thinking Mode 后，`agent.thinking_level` 不变。 |
| AC-3 | FR-3、FR-12 | Private Ask 用户 A 的配置不影响用户 B 的 session 与发送快照。 |
| AC-4 | FR-2、FR-21 | Team Agent session 的配置不影响其他项目或其他 Agent 调用。 |
| AC-5 | FR-1 | Agent 管理页显示的基础配置不被聊天操作改变。 |
| AC-6 | FR-2、FR-4 | 非 owner/admin 调用 Team Agent 配置 PATCH 被服务端拒绝（403 `forbidden_chat_config`），仅隐藏前端控件不足够。 |
| AC-7 | FR-13、FR-14 | 发送时选择模型 A，之后切换为模型 B，已排队消息的 `context.chat_config.model` 仍为 A。 |
| AC-8 | FR-14 | 重试和重新 claim 不改变该任务的模型和 Thinking Mode。 |
| AC-9 | FR-4、FR-17 | 不支持的模型或 Thinking Mode 被服务端拒绝（400 `invalid_model_or_thinking_level`），已入队任务不受影响。 |
| AC-10 | FR-13 | 入队后 `context` 保留已有字段（夹具含 `head_sha`），并写入统一的 `chat_config`。 |
| AC-11 | FR-8 | 打开 Team Agent 面板不创建 `project_chat` Issue；`GET` 响应 `issue_id` 为 null 且数据库无新 `origin_type='project_chat'` 行。 |
| AC-12 | FR-9 | 打开 Team Agent 后修改配置，刷新页面仍能从同一 `session_id` 恢复配置。 |
| AC-13 | FR-10 | 显式创建和首次发送并发或重复调用后，最多一个 active session 和一个容器 Issue。 |
| AC-14 | FR-15 | 无 Issue 时上传的附件只有上传者可见；其他项目成员下载/列表均不可见。 |
| AC-15 | FR-16 | 发送成功后附件与 comment/task 一起对项目成员可见；发送失败时附件仍未绑定且可重试。 |
| AC-16 | FR-5、FR-6 | 新建 session 的 `base_*` 等于创建时 Agent 默认值；之后改 Agent 默认值，已有 session 的 `base_*` 不变，无 override 时有效值仍为旧快照。 |
| AC-17 | FR-6 | PATCH `null` 与空字符串都清除 override；省略字段不改当前值。 |
| AC-18 | FR-7 | 更换项目 Team Agent 后旧 session 为 `closed` 且只读，新 session 绑定新 Agent；旧消息不自动进入新 session。 |
| AC-19 | FR-11 | 旧 Private Ask session 缺 `base_*` 时可读当前 Agent 默认值完成一次会话；新 session 必须写入 `base_*`；旧任务不被回填 `chat_config`。 |
| AC-20 | FR-17、FR-21 | 对已关闭 session 的 PATCH/发送返回 409；未配置 Team Agent 返回 409 `team_agent_not_configured`。 |
| AC-21 | FR-18 | Team Agent 与 Private Ask 均可在不调用 `UpdateAgent` 的前提下改模型与 Thinking Mode；现有 draft / 附件 / 发送 / 停止 / 重试行为不回归。 |
| AC-22 | FR-19、FR-20 | 从 472 起的迁移只新增约定表/列/索引；无新 FK；索引均为 `CONCURRENTLY` 且一文件一条；`CUSTOM.md` 已按当时结构登记本 CR 条目。 |

来源文档完成标志要求 AC-1 至 AC-15 全部满足；AC-16 至 AC-22 覆盖同一闭环中必须可测、但来源完成标志未逐条编号的规则。

# 6. 成功指标

- 聊天窗口内任意模型和 Thinking Mode 变更导致 `agent.model` / `agent.thinking_level` 变化的次数为 **0**。
- 打开 Team Agent 面板（不发送、不显式创建）产生新 `project_chat` Issue 的次数为 **0**。
- 新发送任务 **100%** 带有 `context.chat_config`；抽检重试/重新 claim 后快照与入队时一致率为 **100%**。
- 发送前未绑定附件被非上传者读取的次数为 **0**。
- 同一项目并发首次发送后 active `project_chat_session` 数 = **1**，绑定容器 Issue 数 = **1**。

# 7. 范围排除

以下内容明确不做，归属后续 CR 或明确非目标：

- Discussion `project_shared` 会话、Coordinator、Discussion 附件、Discussion 到工作 Issue/CR 的升级（来源 CR-B/CR-C；对应来源 AC-16 至 AC-27）。
- 多个 active Team Agent 主题或完整 thread 列表（来源 AC-29）。
- 发送框整体视觉重构、对齐普通非项目聊天 composer 布局（来源 CR-D；AC-30 至 AC-35）。本 CR 只接入功能控件。
- 给 `agent_task_queue` 增加模型和 Thinking Mode 专用列。
- 把 `/compact` 作为普通用户消息发送；runtime 未提供真实压缩协议时不发送伪 `/compact`（来源 AC-28）。
- 在 Multica 服务端复制 CR 状态机或直接写 knowledge-base 的 `_backlog.yml`。
- 自定义 promotion 表、`discussion_participant` 表、复制一套独立 Discussion 消息表。
- 历史 Discussion 全量迁移；本 CR 也不迁移历史 Team Agent 容器 Issue。
- mobile 端。
- `../tools/` 仓改动。
