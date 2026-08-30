# Multica 聊天会话级配置与 Discussion 方案

**文档类型**：产品需求来源文档与架构方案

**状态**：可作为后续需求分析、PRD 编写和 CR 注册的来源文档

**适用仓库**：`multica`

**当前基线**：CR-2026-055 合并后的 Multica，commit `8746add879cbd1c78e573c2a4a1776e16158c00c`

**历史输入**：`Multica聊天会话级模型与ThinkingMode配置方案.md`。历史输入保留原文，不作为当前实现依据。

---

## 1. 文档用途

本文描述 Multica 项目聊天中 Team Agent、Private Ask 和 Discussion 的会话边界、模型配置、Thinking Mode、附件可见性和 Agent 协作规则。

本文同时承担两种职责：

1. 规定后续实现必须满足的产品行为。
2. 为后续 PRD、SDD 和 CR 注册提供稳定的背景、需求编号、验收标准和事实依据。

文中使用以下约定：

- **必须**：产品或安全边界，后续实现不得违反。
- **建议**：当前推荐实现，架构设计阶段可以在不改变产品行为的前提下调整。
- `FR-*`：功能需求编号。
- `AC-*`：验收标准编号。

---

## 2. 背景与问题

当前 Multica 的聊天能力由不同承载模型组成：

```text
Team Agent  -> 隐藏 project_chat Issue + comment + agent task
Private Ask -> creator-scoped chat_session + chat_message + chat task
Discussion   -> 隐藏 project_discussion Issue + comment
```

当前主要问题：

1. Team Agent 和 Private Ask 的模型选择路径会更新共享 `agent.model`，影响 Agent 的其他调用者。
2. Thinking Mode 如果沿用 Agent 配置，会产生相同的跨会话影响。
3. Team Agent 打开面板时会懒创建隐藏 Issue；打开空面板不应产生执行容器。
4. Discussion 的普通沟通、附件和 Agent 协作不应自动创建工作 Issue。
5. 任务排队后如果重新读取可变的 Agent 或会话配置，排队期间修改配置会改变原消息语义。
6. 发送前附件属于用户草稿，不能提前进入项目成员可见范围。

核心原则：

```text
Agent       = 长期共享的智能体基础配置
Chat session = 当前对话的配置和上下文边界
Task        = 一次发送时冻结的不可变执行快照
Issue       = Team Agent 执行容器或用户明确升级后的工作容器
```

---

## 3. 范围

### 3.1 本次范围

本次方案同时澄清并覆盖：

- Team Agent 的会话级模型和 Thinking Mode。
- Private Ask 的会话级模型和 Thinking Mode。
- Team Agent 在无 Issue 时的会话初始化和配置保存。
- 任务入队时的模型与 Thinking Mode 快照。
- Discussion 的无 Issue 项目共享会话。
- Discussion 中的单一 Coordinator Agent 协办。
- Team Agent 和 Discussion 的发送前附件草稿。
- Discussion 显式升级为工作 Issue 或 CR 的边界。
- 单 active session 的第一阶段主题边界。
- Team Agent 和 Private Ask 消息发送框的布局与视觉优化，参考普通非项目聊天发送框。
- runtime 上下文压缩的延期条件。

### 3.2 明确非目标

以下内容不在第一阶段实施：

- Team Agent 多个 active 主题或完整 thread 列表。
- 多个 Discussion Agent 长期协办者及参与者角色表。
- Discussion 消息和附件的历史全量迁移。
- 自定义 promotion 表，除非现有来源引用和并发锁无法满足幂等要求。
- 给 `agent_task_queue` 增加模型和 Thinking Mode 专用列。
- 复制一套独立的 Discussion 消息表。
- 把 `/compact` 作为普通用户消息发送。
- 在 Multica 服务端复制 CR 状态机或直接写 knowledge-base 的 `_backlog.yml`。

---

## 4. 产品规则

### 4.1 配置隔离

**FR-1** 聊天窗口修改模型或 Thinking Mode 时，不得修改 `agent.model`、`agent.thinking_level` 或 Agent 的其他持久化配置。

**FR-2** Team Agent 的配置属于项目共享的 active Team Agent session；第一阶段由项目 owner/admin 修改。

**FR-3** Private Ask 的配置属于当前用户自己的 Private Ask session；其他用户的 session 不受影响。

**FR-4** Discussion 的配置属于项目共享 Discussion session；第一阶段由项目 owner/admin 修改。没有 Coordinator 时，Discussion 仍可作为纯人类会话使用。

### 4.2 默认值和快照

**FR-5** 新建会话时读取绑定 Agent 的默认模型和 Thinking Mode，并保存为会话基础快照。

**FR-6** 会话 override 优先于会话基础快照；没有 override 时使用基础快照；runtime 默认值只作为没有可用会话值时的最后回退。

**FR-7** Agent 默认值变化不改变已经创建会话的基础快照。

**FR-8** Agent 绑定变化不让已有 Team Agent session 静默切换 Agent。旧 session 关闭，新 session 使用新 Agent 创建；旧消息保持只读历史。

### 4.3 Team Agent 创建边界

**FR-9** 打开 Team Agent 面板可以创建或读取 `project_chat_session`，但不得创建隐藏 `project_chat` Issue。

**FR-10** 显式创建主题和首次发送消息都可以创建或补齐 Team Agent session，并且必须经过同一个幂等服务路径。

**FR-11** Team Agent session 在没有 Issue 时也必须能够保存模型和 Thinking Mode 配置。

**FR-12** 首次发送或显式创建聊天容器时，session 才绑定隐藏 `project_chat` Issue。

### 4.4 Discussion 创建和消息

**FR-13** 打开 Discussion、上传附件、发送普通文字消息、添加 Coordinator 或请求 Coordinator 协办，都不得自动创建工作 Issue。

**FR-14** Discussion 使用项目级共享 `chat_session` 和 `chat_message`，而不是隐藏 Issue/comment 作为新消息承载。

**FR-15** 普通 Discussion 消息只写入 shared session，不创建 Agent task。

**FR-16** 明确 `@mention` Coordinator 或点击分析/总结操作时，才创建一个无 Issue 的 chat task；Agent 回复写回同一个 shared session。

**FR-17** 第一阶段每个项目只有一个 active Discussion shared session。`creator_id` 只用于审计和创建者信息，不作为 shared session 的可见性条件。

### 4.5 附件

**FR-18** 发送前附件是当前用户的草稿，只允许上传者访问、删除和重试绑定。

**FR-19** 发送前附件不得出现在项目公共附件列表、Team Agent timeline、Discussion 消息流或团队 WebSocket 事件中。

**FR-20** 发送成功后，附件必须在同一发送事务中绑定到对应消息和执行上下文：

- Team Agent：绑定到 Issue、comment 和 task。
- Discussion：绑定到 `chat_session` 和 `chat_message`；如果触发 Agent 协办，也关联到对应 task。

**FR-21** 发送失败不得删除草稿附件；附件保持未绑定状态，用户可以重试。后台按 TTL 清理长期未绑定附件。

### 4.6 显式升级

**FR-22** 只有用户明确执行“转为工作 Issue”或“升级为 CR”时，才创建正式工作 Issue 或进入 CR 流程。

**FR-23** 升级不得移动或删除原 Discussion 消息和附件。目标 Issue 保存来源 session、消息和附件引用。

**FR-24** 同一来源集合的重复升级请求不得创建重复工作 Issue。

**FR-25** CR 注册继续使用现有 `requirement-register` 流程；Multica 不复制 CR 注册和状态机写入逻辑。

### 4.7 任务一致性

**FR-26** 任务入队前解析有效模型和 Thinking Mode，并将值冻结到任务 context。

**FR-27** 任务执行、重试和重新 claim 只使用任务快照，不重新读取当前会话或 Agent 配置。

**FR-28** 配置更新和发送入队都必须由服务端执行模型目录、runtime 能力和权限校验。

### 4.8 发送框 UI

**FR-29** Team Agent 和 Private Ask 的发送框应参考普通非项目聊天的 `ChatInput` 布局，不另建一套并行 composer 视觉体系。

**FR-30** UI 优化必须保留现有 `ChatInputCore`、draft adapter、草稿附件、上传状态、发送中、停止和失败重试行为。

**FR-31** Model Picker 和 Thinking Mode 控件应作为发送框底部工具栏的一部分呈现；控件操作仍调用会话配置接口，不得改变 Agent 配置。

**FR-32** 发送框必须在窄项目聊天面板、桌面端和 Web 端保持内容不溢出，输入区、附件状态和发送/停止按钮不得互相遮挡。

**FR-33** UI CR 不新增会话、任务、附件或 Discussion 数据模型；业务语义由功能 CR 提供。

---

## 5. 最小数据模型

### 5.1 Team Agent：`project_chat_session`

Team Agent 不能把配置只放在 Issue 上，因为用户可以在 Issue 创建前修改配置。建议新增轻量会话表，不引入多主题 thread 模型：

```text
project_chat_session
- id
- workspace_id
- project_id
- agent_id
- issue_id nullable
- base_model
- base_thinking_level
- model_override nullable
- thinking_level_override nullable
- status: active | closed
- created_by
- created_at
- updated_at
```

约束和语义：

- 第一阶段一个项目最多一个 active session。
- `agent_id` 在 session 生命周期内不可变。
- `issue_id` 在首次发送或显式创建前为空。
- `base_model` 和 `base_thinking_level` 是创建时的 Agent 默认值快照。
- override 为空时回退到基础快照。
- active session 唯一性由数据库部分唯一索引和服务层并发锁共同保证。
- 新迁移遵守 Multica 规则：索引使用 `CREATE UNIQUE INDEX CONCURRENTLY`，并单独放在一个迁移文件中；新关系由应用层校验，不新增数据库外键。

不采用：

- 只给 `issue` 加字段：无法保存无 Issue 状态。
- `project.settings`：会把会话配置错误地变成项目设置。
- `issue.metadata`：缺少专用字段约束，容易与通用 Issue 元数据混用。
- `project_chat_thread`：第一阶段只有一个 active session，暂无必要引入多主题抽象。

### 5.2 Private Ask：扩展 `chat_session`

在现有 `chat_session` 上增加：

```text
base_model
base_thinking_level
model_override nullable
thinking_level_override nullable
```

Private Ask 继续使用现有 `(project_id, creator_id)` active session 查询和用户隔离。创建 session 时保存当前 Team Agent 的默认配置，但不共享 Team Agent 的后续 override。

历史 session 如果无法恢复创建时的默认值，允许一次兼容回退到当前 Agent 默认值；该回退仅用于旧数据，不能用于新 session，也不能改变已入队任务。

### 5.3 Discussion：复用 `chat_session` 和 `chat_message`

为 `chat_session` 增加明确的会话类型：

```text
chat_session.kind
- private
- project_shared
```

Discussion shared session 使用：

```text
chat_session
- workspace_id
- project_id
- kind = project_shared
- creator_id       # 审计字段，不是 ACL
- agent_id nullable
- base_model
- base_thinking_level
- model_override nullable
- thinking_level_override nullable
```

`agent_id` 对 shared session 允许为空，以支持没有 Coordinator 的纯人类 Discussion。配置和 Agent task 只有在 Coordinator 已配置并被明确请求时才需要 Agent。

第一阶段不新增 `discussion_participant`。项目设置中的 `discussion_coordinator_agent_id` 作为唯一默认 Coordinator；后续需要多个长期协办 Agent 时再单独设计参与者模型。

### 5.4 附件

一期复用现有 `attachment` 字段，不新增草稿表：

```text
发送前：
issue_id        = NULL
comment_id      = NULL
chat_session_id = NULL
chat_message_id = NULL
task_id         = NULL
workspace_id    = 当前 workspace
uploader_id     = 当前用户
```

上传接口可以继续生成普通未绑定附件。前端只保存 attachment ID；发送时服务端重新校验 workspace、上传者和所有归属字段为空，然后在发送事务中完成绑定。

发送前下载接口必须执行上传者权限校验，不能因为调用者知道 attachment UUID 就开放读取。

### 5.5 任务快照

一期不修改 `agent_task_queue` 的表结构。复用已有 `context` JSONB，并合并而不是覆盖其他任务上下文：

```json
{
  "chat_config": {
    "model": "claude-sonnet-4",
    "thinking_level": "high"
  }
}
```

`context` 可能已经包含 `head_sha`、附件或其他任务字段；写入 `chat_config` 时必须保留已有字段。该对象由服务端生成，前端不能直接提交任意 task context。

---

## 6. 有效配置规则

### 6.1 读取优先级

```text
model:
  model_override
  -> base_model
  -> Agent 当前默认 model（仅旧 session 兼容）
  -> runtime 默认 model

thinking_level:
  thinking_level_override
  -> base_thinking_level
  -> Agent 当前默认 thinking_level（仅旧 session 兼容）
  -> runtime 默认值
```

### 6.2 空值语义

- 字段未提供：保持当前值。
- `null`：清除 override，回退到基础快照。
- 空字符串：API 归一化为清除 override；不得在不同接口中产生不同含义。
- 非空字符串：设置 override。

### 6.3 校验时机

配置 PATCH 时和发送入队时都必须校验：

- 当前用户是否有配置权限。
- model 是否属于当前 runtime 支持的模型目录。
- Thinking Mode 是否被当前 runtime/provider 支持。
- runtime 是否在线或允许进入队列。
- session 是否仍为 active。

发送时的再次校验用于处理 runtime 切换、能力目录变化和会话关闭等并发情况。

---

## 7. API 设计

一期保留项目路径，响应增加 session 信息；不立即切换到多 thread 路由。

### 7.1 Team Agent

```text
GET   /api/projects/{projectId}/chat
PATCH /api/projects/{projectId}/chat/config
POST  /api/projects/{projectId}/chat/messages
```

GET 响应至少包含：

```json
{
  "session_id": "...",
  "issue_id": null,
  "team_agent_id": "...",
  "model": "...",
  "thinking_level": "...",
  "model_source": "override|session_default|runtime_default",
  "thinking_level_source": "override|session_default|runtime_default"
}
```

PATCH 和发送请求携带 `session_id`。服务端确认该 session 属于当前 workspace/project，处于 active 状态，并且 Agent 绑定没有漂移。

发送请求示例：

```json
{
  "session_id": "...",
  "content": "请分析这个问题",
  "attachment_ids": ["..."]
}
```

### 7.2 Private Ask 和 Discussion

```text
GET   /api/projects/{projectId}/private-chat
PATCH /api/chat/sessions/{sessionId}/config
GET   /api/projects/{projectId}/discussion
POST  /api/chat/sessions/{sessionId}/messages
```

`PATCH /api/chat/sessions/{sessionId}/config` 根据 `kind` 分别执行：

- Private Ask：creator-only 校验。
- Discussion shared：project/workspace 成员和 Discussion 配置权限校验。

不要通过通用 `UpdateAgent` 保存聊天窗口配置。

### 7.3 错误边界

至少保持以下可区分错误：

```text
400 invalid_model_or_thinking_level
403 forbidden_chat_config
404 chat_session_not_found
409 chat_session_closed_or_changed
409 team_agent_not_configured
409 attachment_already_bound
```

前端应根据错误回滚配置控件或保留草稿，不静默丢失输入和附件。

---

## 8. 事务和并发

### 8.1 Team Agent 首次发送

```text
1. 校验项目、session、Agent 和发送权限。
2. 读取会话配置，解析有效 model/thinking_level。
3. 校验 runtime capability。
4. 获取 project_chat_session 行锁或项目级并发锁。
5. 无 issue_id 时幂等创建隐藏 project_chat Issue，并回写 session.issue_id。
6. 校验未绑定附件的 workspace、uploader 和归属状态。
7. 创建 comment。
8. 绑定附件到 Issue/comment。
9. 创建带 chat_config 快照的 Agent task。
10. 提交事务。
11. 提交成功后广播消息和 task 事件。
```

事务失败时，comment、task 和 Issue 绑定不得留下半成品；未绑定附件保留供重试。

### 8.2 Discussion 发送

```text
1. 校验 shared session 和项目成员权限。
2. 读取并校验 session 配置。
3. 校验未绑定附件。
4. 创建 user chat_message。
5. 绑定附件到 chat_session/chat_message。
6. 只有明确 Agent 请求时才创建 chat task，并写入快照。
7. 提交事务。
8. 提交成功后广播消息和 task 事件。
```

普通 Discussion 消息不创建 task，也不创建 Issue。

### 8.3 配置与发送竞态

配置修改只影响尚未入队的消息。发送事务在同一 session 读取并冻结配置；已经入队的任务以后只读 task snapshot。

---

## 9. 权限和可见性

| 操作 | Team Agent | Private Ask | Discussion |
|---|---|---|---|
| 读取会话 | 项目成员 | session creator | 项目成员 |
| 修改配置 | owner/admin | session creator | owner/admin |
| 发送消息 | 现有 Team Agent 发送权限 | session creator | 项目聊天发送权限 |
| 上传草稿附件 | 当前用户 | 当前用户 | 当前用户 |
| 读取发送前附件 | 上传者 | 上传者 | 上传者 |
| 读取已发送消息/附件 | 项目成员 | session creator | 项目成员 |
| 请求 Coordinator | 不适用 | 不适用 | 具备 Agent 调用权限的成员 |
| 创建工作 Issue | 显式操作 | 按现有 Issue 权限 | 显式升级操作 |

presenter 仍然控制 Team Agent 消息的单一写者规则，但不自动改变会话配置权限。

---

## 10. Discussion 升级

### 10.1 转为工作 Issue

```text
Discussion shared session
  -> 用户选择消息和附件
  -> 显式点击“转为工作 Issue”
  -> 创建正式 Issue
  -> 保存 source session/message/attachment 引用
  -> 后续 Agent task 使用 issue_id
```

原 Discussion 消息和附件保持原归属，不移动、不删除、不静默复制。

一期优先复用 Issue 的 `context_refs` 或现有来源引用能力。服务端以规范化的来源集合生成稳定引用，并使用 session/source 集合的项目级并发锁防止重复创建；重复请求返回已经创建的目标 Issue。

只有在现有来源引用无法满足可靠幂等和审计时，才增加 `discussion_promotion` 表。

### 10.2 升级为 CR

```text
Discussion
  -> 用户明确选择升级为 CR
  -> 准备工作 Issue 和来源上下文
  -> 进入 requirement-register
  -> knowledge-base 生成 CR-ID
```

Multica 不直接写 AI First Platform 仓库的 `_backlog.yml`，也不复制 CR 状态机。

---

## 11. 历史数据与兼容

### 11.1 历史 Discussion

现有隐藏 `project_discussion` Issue 保留为只读历史。切换完成后：

- 新 Discussion 消息进入 `project_shared` chat session。
- 不做双写。
- 不立即删除旧 Issue。
- 若未来需要统一回放，再单独设计一次性迁移和权限审计。

### 11.2 历史 Chat Session

新增会话字段后：

- 新 session 必须保存基础快照。
- 旧 session 缺失基础快照时允许兼容读取 Agent 当前默认值。
- 旧任务没有 `chat_config` 时保持既有执行行为，不对历史任务补写或重算配置。
- 新任务一律写入快照。

### 11.3 项目 Agent 更换

项目绑定 Agent 变化时：

```text
旧 active Team Agent session -> closed
新 active Team Agent session -> 绑定新 Agent，复制新默认配置
旧 Issue/session -> 只读历史
```

不自动把旧完整历史传入新 session。若未来需要“基于当前对话继续”，只允许显式传递摘要或用户选择的消息。

---

## 12. CR 注册拆分

本文的五个实施 Phase 不等于五个 CR。为了保持边界清晰、减少跨 CR 反复适配，建议注册为 **3 个功能 CR + 1 个 UI CR**。后续注册 CR 时，以下每个条目都可以直接作为 CR 的范围初稿和任务拆分依据。

### CR-A：会话级配置与 Team Agent 闭环

**目标**：让 Team Agent 和 Private Ask 的模型、Thinking Mode 真正成为会话配置，并在发送时形成不可变任务快照；同时完成 Team Agent 无 Issue 阶段的 session 生命周期。

**包含范围**：

- 新增 `project_chat_session`，支持无 `issue_id` 的 active session。
- Team Agent GET 只创建或读取 session，不创建 `project_chat` Issue。
- Team Agent 显式创建和首次发送复用同一个幂等服务路径。
- Team Agent 首次发送时创建并绑定隐藏 `project_chat` Issue。
- Private Ask `chat_session` 增加基础配置快照和 override。
- Team Agent、Private Ask 的配置读取、更新、权限和 runtime capability 校验。
- Model Picker 和 Thinking Mode 的功能接入；配置写入 session，不调用 `UpdateAgent`。
- 发送入口解析有效配置并写入 `task.context.chat_config`。
- daemon、重试和重新 claim 使用任务快照；旧任务保持既有行为。
- Team Agent 发送前附件作为未绑定草稿，成功发送时与 Issue/comment/task 原子绑定。
- Team Agent 和 Private Ask 的配置刷新、切换和失败回滚。

**不包含范围**：

- Discussion `project_shared` 会话。
- Discussion Coordinator 和 Discussion 附件。
- Discussion 到工作 Issue/CR 的升级。
- 多个 active Team Agent 主题。
- 发送框整体视觉重构；只接入本 CR 必需的功能控件。

**依赖**：无前置功能 CR；需要复用现有 `chat_session`、`ChatInputCore`、任务 context、attachment 和 `EnsureProjectChatIssue` 能力。

**主要交付物**：

- 数据库迁移和 sqlc 查询：`project_chat_session` 及 `chat_session` 配置字段。
- Team Agent、Private Ask 配置 API 和 response schema。
- 有效配置解析和 task snapshot 服务逻辑。
- Team Agent 延迟创建、首次发送和附件绑定逻辑。
- daemon 快照读取适配。
- 后端权限、并发、重试和任务快照测试。
- Team Agent、Private Ask 配置控件的功能测试。

**完成标志**：

- `AC-1` 至 `AC-15` 全部满足。
- 发送时的配置可在任务记录中追溯。
- `agent.model` 和 `agent.thinking_level` 不因聊天操作改变。
- Team Agent 无 Issue 配置刷新后仍可恢复，首次发送只创建一个容器。

### CR-B：Discussion 无 Issue 共享会话

**目标**：将新 Discussion 从隐藏 Issue/comment 承载改为项目级 shared `chat_session`/`chat_message`，支持单一 Coordinator 协办，但不自动创建工作 Issue。

**包含范围**：

- `chat_session.kind = project_shared`。
- 每个项目一个 active Discussion shared session。
- Discussion GET 只创建或读取 shared session，不创建 `project_discussion` Issue。
- 项目成员读取和发送权限；`creator_id` 不作为 shared session ACL。
- Discussion 的会话级模型和 Thinking Mode 配置。
- 普通消息写入 `chat_message`，不创建 Agent task。
- `@mention` Coordinator、分析或总结请求创建无 Issue 的 chat task。
- Coordinator 回复写回同一个 shared session。
- 复用未绑定附件草稿；发送成功后绑定到 `chat_message`/session/task。
- 旧 `project_discussion` Issue 保留只读；新消息不双写。

**不包含范围**：

- 多个长期 Discussion Agent 和 `discussion_participant` 表。
- Discussion 到工作 Issue 或 CR 的升级。
- 历史 `project_discussion` 全量迁移。
- Team Agent 的配置和发送链路。
- runtime 上下文压缩。

**依赖**：依赖 CR-A 提供的会话配置解析、任务快照和未绑定附件校验；如果 CR-A 尚未合入，CR-B 必须复用等价的已审定服务契约，不得各自实现第二套快照逻辑。

**主要交付物**：

- `chat_session.kind` 和 shared session 查询/权限逻辑。
- Discussion chat message 查询、发送和实时事件。
- 单一 Coordinator 的任务触发和回复链路。
- Discussion 附件绑定与下载权限。
- 历史容器只读兼容。
- 项目成员、普通消息、Coordinator、附件和无 Issue task 测试。

**完成标志**：

- `AC-16` 至 `AC-22` 全部满足。
- 打开、发送、上传附件、请求 Coordinator 均不创建 `project_discussion` 或其他工作 Issue。
- Private Ask 的 creator-only 访问规则不被 shared session 分支放宽。

### CR-C：Discussion 显式升级

**目标**：提供从 Discussion 到正式工作 Issue 的明确升级出口，并保持来源可追溯；CR 升级继续进入现有 `requirement-register` 流程。

**包含范围**：

- 用户选择 Discussion 消息和附件并显式执行“转为工作 Issue”。
- 创建正式 Issue，并保存来源 session、消息和附件引用。
- 原 Discussion 消息和附件保持原归属。
- 以规范化来源集合和项目级并发锁保证重复升级不产生重复 Issue。
- 重试请求返回已经创建的目标 Issue。
- “升级为 CR”只负责准备来源上下文并进入 `requirement-register`，不在 Multica 内写 CR 账本。

**不包含范围**：

- 自动把 Discussion 消息升级为 Issue。
- 移动、删除或静默复制原消息和附件。
- 在 Multica 内实现 CR 注册、状态机或 `_backlog.yml` 写入。
- Discussion 多主题和多 Agent 参与者模型。
- 新增 `discussion_promotion` 表，除非实现验证表明现有来源引用和并发锁不足以满足幂等和审计。

**依赖**：依赖 CR-B 的 shared Discussion session、message 和附件来源；依赖现有 Issue 创建能力和 knowledge-base 的 `requirement-register` 流程。

**主要交付物**：

- Discussion promotion API 和来源引用结构。
- 选择消息/附件的前端交互。
- 来源集合规范化、并发锁和重复请求处理。
- 工作 Issue 来源展示或查询能力。
- Issue promotion 和 CR 流程衔接测试。

**完成标志**：

- `AC-23` 至 `AC-27` 全部满足。
- 同一来源集合重复升级只产生一个工作 Issue。
- 工作 Issue 可以回溯来源 Discussion 消息和附件。
- Multica 不直接修改 knowledge-base CR 账本。

### CR-D：Team Agent 和 Private Ask 发送框 UI 优化

**目标**：在不改变业务语义的前提下，将项目聊天发送框的布局和视觉体验对齐普通非项目聊天。

**参考基线**：

- `packages/views/chat/components/chat-input.tsx`：普通聊天的主 composer。
- `packages/views/chat/components/chat-column.ts`：`CHAT_GUTTER` 和 `CHAT_COLUMN` 的统一内容宽度。
- `packages/views/chat/components/chat-window.tsx`：普通聊天中发送框的挂载、Agent/Project 左侧控件和窗口状态。
- `packages/views/projects/components/project-team-agent-chat.tsx`：Team Agent 当前 composer。
- `packages/views/projects/components/project-private-ask.tsx`：Private Ask 当前 composer。

**UI 采用的布局基准**：

```text
composer wrapper
  -> container-aware gutter
  -> centered, width-capped input surface
       -> optional top metadata / attachment area
       -> scrollable editor area
       -> bottom-left add menu + session controls
       -> bottom-right send / stop action
```

具体参考规则：

- 复用普通聊天的 `CHAT_GUTTER`/`CHAT_COLUMN` 思路，让消息列和发送框边缘对齐；项目窄面板使用容器宽度，不依赖浏览器 viewport 断点。
- 复用单一输入 surface：边框、背景、focus-within 状态、圆角和内部滚动保持一致。
- 输入区、附件预览、底部工具栏分层，长文本在输入区内部滚动，不能把发送按钮顶出面板。
- 左下角复用普通聊天的附件/添加入口，并将 Model Picker、Thinking Mode 作为 `leftAdornment` 或等价底部工具栏控件接入。
- 右下角复用普通聊天的发送/停止按钮和 loading、上传中、运行中状态。
- Team Agent 和 Private Ask 继续使用各自的 draft adapter、项目草稿隔离和 pending-message 模式，不接入普通聊天的全局 session store。
- 配置控件使用已有的 Model Picker/Thinking Picker；控件样式融入工具栏，不再单独占据发送框上方的一整行，除非窄屏布局确实需要换行。
- 保留可访问名称、tooltip、键盘发送、附件上传中禁发、失败可重试和运行中停止。

**包含范围**：

- Team Agent 和 Private Ask composer 的结构、间距、边框、背景、焦点和响应式布局。
- Model/Thinking 控件在底部工具栏中的排列和窄屏换行。
- 附件预览、上传中、发送中、停止、失败和空态视觉一致性。
- Web 和 Desktop 共享组件的适配。
- 对应组件测试和必要的 Playwright 截图/交互验证。

**不包含范围**：

- 新增 API、数据库字段或任务快照逻辑。
- 修改 Team Agent、Private Ask、Discussion 的权限和发送事务。
- 改造普通非项目聊天的现有视觉基线。
- 引入新的 UI 组件库或新的状态管理方式。
- 修改普通聊天 `ChatInput` 的既有业务语义；如需改共享组件，只做保证项目聊天兼容所需的最小调整。

**依赖**：依赖 CR-A 提供会话配置控件所需的服务端字段和功能接口；不依赖 CR-B/CR-C 才能开始，但不应把 Discussion UI 变化混入本 CR。

**主要交付物**：

- 项目聊天 composer 的共享布局调整。
- Team Agent/Private Ask 的控件接入和响应式样式。
- Web/Desktop 组件测试、可访问性检查和窄面板回归测试。
- 与普通非项目聊天布局的差异说明，仅记录必要差异。

**完成标志**：

- `FR-29` 至 `FR-33` 和 `AC-30` 至 `AC-35` 满足。
- Team Agent、Private Ask 在窄面板和宽面板中均不溢出、不重叠。
- 样式调整不会改变 draft、attachment、send、stop 和 retry 行为。
- 项目聊天发送框与普通非项目聊天在结构和视觉语言上保持一致。

### CR 顺序和边界

推荐顺序：

```text
CR-A 会话配置与 Team Agent 闭环
  -> CR-B Discussion 无 Issue
  -> CR-C Discussion 显式升级
  -> CR-D 发送框 UI 优化
```

说明：

- CR-A 是最大的功能 CR，但它提供一个完整可验证的会话配置闭环，避免把配置 API、Team Agent session 和 task snapshot 拆成多个半成品 CR。
- CR-B 只负责 Discussion 的新承载和协办，不承担 Issue promotion，避免消息权限和工作流升级互相牵制。
- CR-C 只负责显式升级，便于单独审查来源引用、幂等和 CR 流程边界。
- CR-D 是纯前端体验 CR，参考并复用普通非项目聊天的现有布局，不新增业务抽象。

---

## 13. 验收标准

### 配置隔离

- **AC-1** Team Agent 修改模型后，`agent.model` 不变。
- **AC-2** Team Agent 修改 Thinking Mode 后，`agent.thinking_level` 不变。
- **AC-3** Private Ask 用户 A 的配置不影响用户 B。
- **AC-4** Team Agent session 的配置不影响其他项目或其他 Agent 调用。
- **AC-5** Agent 管理页显示的基础配置不被聊天操作改变。
- **AC-6** 项目 owner/admin 权限在服务端强制执行。

### 快照一致性

- **AC-7** 发送时选择模型 A，之后切换为模型 B，已排队消息仍使用 A。
- **AC-8** 重试和重新 claim 不改变模型和 Thinking Mode。
- **AC-9** 不支持的模型或 Thinking Mode 被服务端拒绝。
- **AC-10** task context 中保留已有字段，并写入统一的 `chat_config`。

### Team Agent 创建边界

- **AC-11** 打开 Team Agent 不创建 `project_chat` Issue。
- **AC-12** 打开 Team Agent 后修改配置，刷新页面仍能恢复配置。
- **AC-13** 显式创建和首次发送最多产生一个 active session 和一个容器 Issue。
- **AC-14** 无 Issue 时上传的附件只有上传者可见。
- **AC-15** 发送成功后附件与 comment/task 一起可见；发送失败时附件仍可重试。

### Discussion 边界

- **AC-16** 打开 Discussion 不创建 `project_discussion` Issue。
- **AC-17** 普通文字或附件消息不创建 Issue。
- **AC-18** 普通 Discussion 消息不创建 Agent task。
- **AC-19** 明确请求 Coordinator 后，task 使用 `chat_session_id` 且 `issue_id` 为空。
- **AC-20** Agent 回复写回同一个 shared session。
- **AC-21** Discussion shared session 对项目成员可见，但不放宽 Private Ask 的 creator-only 规则。
- **AC-22** 旧 `project_discussion` Issue 历史可只读回放，新消息不双写。

### 升级和来源

- **AC-23** 只有显式升级操作才创建工作 Issue。
- **AC-24** 原 Discussion 消息和附件归属不被移动或删除。
- **AC-25** 重复升级请求不会创建重复工作 Issue。
- **AC-26** 工作 Issue 可以追溯到来源 session、消息和附件。
- **AC-27** 升级 CR 继续经过 `requirement-register`，Multica 不直接写 CR 账本。

### 未来能力边界

- **AC-28** runtime 未提供真实压缩协议时，不发送伪 `/compact` 消息。
- **AC-29** 一期不要求多个 active Team Agent 主题或多个长期 Discussion Agent 协办者。

### 发送框 UI

- **AC-30** Team Agent 和 Private Ask 发送框均复用普通非项目聊天的 composer 布局语言，不出现两套互不一致的输入框结构。
- **AC-31** 发送框在窄项目面板中不发生横向溢出；输入区、附件预览、配置控件和发送/停止按钮不重叠。
- **AC-32** Model Picker 和 Thinking Mode 位于底部工具栏或其窄屏换行布局中，功能调用目标仍是会话配置接口。
- **AC-33** 普通聊天已有的附件上传、上传中禁发、发送中、停止、失败重试和草稿保留行为不回归。
- **AC-34** Team Agent 和 Private Ask 的 draft adapter、项目隔离和 pending-message 状态不因 UI 调整而改用全局聊天 store。
- **AC-35** Web/Desktop 共享视图通过组件测试和窄面板回归检查，且可访问名称、tooltip 和键盘发送行为可用。

---

## 14. 当前事实依据

以下结论基于 Multica 基线 `8746add879cbd1c78e573c2a4a1776e16158c00c` 的代码核查，后续 upstream 结构变化后需要重新核对：

| 结论 | 代码位置 |
|---|---|
| Team Agent GET 当前懒创建隐藏 Issue | `server/internal/handler/project_chat.go` 的 `GetProjectChat` |
| Team Agent Issue 创建和并发锁集中在服务层 | `server/internal/service/project_chat.go` 的 `EnsureProjectChatIssue` / `ensureContainerIssue` |
| Team Agent 当前发送依赖 Issue comment 和 Agent task | `server/internal/service/project_chat.go` 的 `SendProjectChatMessage` |
| Private Ask 按项目和创建者懒创建 session | `server/internal/handler/project_chat.go` 的 `GetProjectPrivateChat`；`server/pkg/db/queries/chat.sql` |
| Private Ask 现有 session 使用 creator-only 访问 | `server/internal/handler/chat.go` 的 session gate 方法 |
| Chat task 已支持 `chat_session_id` 且可无 Issue 执行 | `server/migrations/033_chat.up.sql`、`server/pkg/db/queries/agent.sql` |
| attachment 已支持 session/message 关联和未绑定状态 | `server/migrations/029_attachment.up.sql`、`server/migrations/083_attachment_chat_columns.up.sql`、`server/pkg/db/queries/attachment.sql` |
| 当前 Team Agent 模型选择会调用 UpdateAgent | `packages/views/projects/components/project-team-agent-chat.tsx` |
| 当前 Private Ask 模型展示跟随 Agent 且只读 | `packages/views/projects/components/project-private-ask.tsx` |
| 当前 Discussion 基于隐藏 Issue | `server/internal/handler/project_chat.go` 的 `GetProjectDiscussion`；`server/internal/service/project_chat.go` 的 `EnsureProjectDiscussionIssue` |
| 任务已有 context JSONB，可承载非结构化任务上下文 | `server/pkg/db/queries/agent.sql` 的 task 创建和复制查询 |

事实核查的结论是：会话配置应放在会话载体，不能继续写入 Agent；Team Agent 无 Issue 阶段必须有独立持久化对象；Discussion 无 Issue 改造可以复用现有 chat session、chat message、chat task 和 attachment 基础设施，但必须增加 shared session 的访问语义。

---

## 15. 结论

一期采用以下最小闭环：

```text
Team Agent:
  project_chat_session
    -> 无 Issue 时保存配置
    -> 首次发送时绑定 project_chat Issue
    -> comment + task 使用发送时快照

Private Ask:
  现有 chat_session
    -> creator-scoped 配置
    -> task 使用发送时快照

Discussion:
  chat_session(kind=project_shared)
    -> chat_message
    -> 可选 Coordinator chat task
    -> 不自动创建 Issue
    -> 显式升级时才创建工作 Issue
```

实现上优先复用现有 session、message、task、attachment、权限和事件基础设施；不提前引入多主题、参与者表、promotion 表、任务专用配置列或 runtime 压缩协议。任何后续扩展都必须先证明当前模型无法满足需求，再增加新的存储或抽象。
