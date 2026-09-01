# Multica Team Agent 与 Discussion 会话级配置方案

**文档类型**：架构分析与方案建议  
**状态**：待评审，未进入代码实施  
**适用仓库**：`multica`  由 AI First Platform 工作区引用  
**基线版本**：CR-2026-055 合并后的 Multica 状态，commit `8746add879cbd1c78e573c2a4a1776e16158c00c`

## 1. 背景

本方案针对 Multica 项目聊天窗口中的 Team Agent、Discussion 和 Private Ask，重点解决模型选择、Thinking Mode、附件共享和工作 Issue 边界问题。

其中 Team Agent 保持现有方案：项目聊天主题继续使用隐藏 `project_chat` Issue 作为执行和时间线容器；Discussion 则单独设计为真正的项目级共享 Chat Session，不因讨论、附件发送或 Agent 协办自动创建 Issue。

目标不是修改项目绑定的智能体，而是让用户在聊天窗口中调整当前对话的执行配置。聊天窗口中的选择只影响当前会话或当前聊天主题，不应改变智能体本身的持久化配置，也不应影响其他项目、其他用户或其他聊天会话。

当前仓库的聊天能力由多个 CR 逐步构建而成：

| Git 提交 | 主要能力 |
|---|---|
| `620cb8d22` | CR-2026-006 TASK-01：Team Agent 隐藏 `project_chat` Issue、项目绑定的 `team_agent_id` 和容器唯一约束 |
| `b2b6b44b4` | CR-2026-006 TASK-02：Team Agent 发送接口、队列和失败补偿 |
| `1663ac81c` | CR-2026-006 TASK-04：Team Agent 消息流和输入框 |
| `3373f75af` | CR-2026-006 TASK-05：模型选择器、runtime 状态和 Agent 权限判断 |
| `7a9bf1860`、`d6c8e2535` | CR-2026-008：项目维度 Private Ask `chat_session`，按用户隔离并懒创建 |
| `59b4c9063` | CR-2026-009：Discussion 隐藏容器 Issue和纯人类讨论流 |
| `f806e60af`、`e92aba3b3` | CR-2026-010/011：presenter 单写者控制和审批卡 |
| `8d2e6ab9a`、`2f3715bc5` | CR-2026-012：附件、富文本、草稿附件和复合输入框 |

当前目标基线已经包含三种聊天模式，但 Team Agent、Discussion 和 Private Ask 的会话承载模型不同，不能用同一个存储对象直接替代现有结构。

本方案的边界是：

- Team Agent：保留 Issue-backed 聊天主题设计，仅将模型和 Thinking Mode 改为会话级配置。
- Discussion：改造为 project-scoped shared Chat Session，不创建 Issue；只有显式升级为工作任务时才创建 Issue。
- Private Ask：继续使用 creator-scoped `chat_session`，配置只属于当前用户的会话。

## 2. 当前实现与问题定位

### 2.1 Team Agent 的当前结构

当前 Team Agent 的关系是：

```text
project.settings.team_agent_id
        -> agent.id
        -> hidden issue(origin_type = 'project_chat')
        -> issue comments
        -> agent_task_queue
```

相关代码位于：

- `server/internal/handler/project_chat.go`
- `server/internal/service/project_chat.go`
- `packages/views/projects/components/project-chat-panel.tsx`
- `packages/views/projects/components/project-team-agent-chat.tsx`

`GET /api/projects/{id}/chat` 当前调用 `IssueService.EnsureProjectChatIssue`。因此打开 Team Agent 面板会触发隐藏 `project_chat` Issue 的懒创建。

`EnsureProjectChatIssue` 本身包含正确的并发控制：

- 快速查询已有容器
- 未找到时使用项目级 advisory lock
- lock 内二次检查
- 创建 Issue
- partial unique index 作为最终保护

这个服务能力应继续复用，但不能再由普通 GET 自动触发。

### 2.2 当前模型选择器的配置归属

Team Agent 当前输入区的模型选择器使用：

```ts
api.updateAgent(agent.id, { model })
```

位置：`packages/views/projects/components/project-team-agent-chat.tsx`。

这条路径更新的是 Agent 实体的 `agent.model` 字段，而不是当前聊天会话。Thinking Mode 如果沿用当前 Agent 配置，也会写入 `agent.thinking_level`。

项目绑定的 Agent 还可能被其他入口使用，因此这会影响：

- 当前项目的其他 Team Agent 消息
- 使用同一个 Agent 的 Private Ask
- 其他项目对该 Agent 的调用
- 后续自动化或显式 Agent 任务

这与本方案目标不一致。

### 2.3 Private Ask 的当前结构

Private Ask 使用 `chat_session`：

```text
chat_session.project_id
chat_session.creator_id
chat_session.agent_id
chat_session.runtime_id
```

当前实现按 `(project_id, creator_id)` 查找或创建 active session。它天然具备用户级隔离，适合作为 Private Ask 的会话配置载体。

当前 Private Ask 的模型显示跟随项目 Team Agent，且是只读状态。要实现本方案，需要将其改为只修改当前用户的 Private Ask session，而不是修改共享 Agent。

### 2.4 Claim 与模型配置的边界

`server/pkg/db/queries/agent.sql` 中的 `ClaimAgentTask` 主要负责：

- 根据 `agent_id`、`runtime_id` 查找可执行任务
- 检查 runtime 在线状态和绑定关系
- 检查 Issue、Project、Chat Session 的并发串行规则
- 将任务从 queued 更新为 dispatched

claim SQL 并不是聊天模型设置的存储位置。当前任务的核心关联是 `agent_id` 和 `runtime_id`，模型与 Thinking Mode属于 Agent 或任务执行上下文。

因此不能依赖 daemon 在任务真正执行时重新读取可变的 Agent 配置。发送时选择的配置应在任务入队时冻结，保证排队期间修改会话设置不会改变已经发送消息的语义。

## 3. 要实现的目标效果

### 3.1 用户可见效果

1. 打开 Team Agent 聊天窗口不创建空 Issue。
2. 用户点击“创建聊天主题/创建 Issue”时，才创建 Team Agent 聊天容器。
3. 用户直接发送第一条文本时，也可以作为明确操作触发容器创建。
4. 尚未创建 Team Agent 容器时仍允许上传附件，但附件先作为当前用户的未绑定草稿附件保存，不出现在团队时间线，也不触发团队广播。
5. 在 Team Agent 中发送消息时，服务端才将草稿附件正式绑定到 Team Agent Issue、comment 和 task；发送失败时附件保留供重试。
6. Team Agent 输入框中的模型选择只修改当前项目聊天主题。
7. Private Ask 输入框中的模型选择只修改当前用户的 Private Ask session。
8. Thinking Mode 与模型使用相同的会话级配置范围。
9. 不调用 `UpdateAgent`，不修改 `agent.model`、`agent.thinking_level` 或其他 Agent 配置。
10. 已排队任务使用发送时确定的模型和 Thinking Mode，不受之后配置变化影响。
12. Discussion 消息、附件和 Agent 协办都不创建 Issue。
13. 用户明确执行“转为工作 Issue”或“升级为 CR”时，才创建真实 Issue，并保存 Discussion 来源引用。

### 3.2 配置继承效果

Agent 仍可作为新会话的默认来源：

```text
新建会话
    -> 读取 Agent 当前默认配置
    -> 保存为会话初始配置或默认快照
    -> 用户只修改会话覆盖值
```

建议已经开始使用的会话保存初始默认值，避免管理员后来修改 Agent 默认值时，历史会话的行为发生隐式变化。

## 4. 总体架构

建议采用四层配置架构：

```text
Agent 基础配置
    -> 当前聊天会话/聊天主题配置
        -> 发送时形成 task 执行快照
            -> daemon 使用快照调用 runtime
```

### 4.1 Agent 层

`agent` 继续保存智能体本身的长期配置：

- Agent 身份和名称
- instructions
- skills、MCP 和工具
- invocation 权限
- runtime 绑定
- 默认 model
- 默认 thinking_level

聊天窗口不再直接写入这一层。

### 4.2 会话/聊天主题层

Team Agent 和 Private Ask 分别使用适合自己的会话载体：

```text
Team Agent:
project_chat_thread -> hidden project_chat Issue

Private Ask:
chat_session -> project + creator scoped session
```

这一层保存当前对话的模型和 Thinking Mode 选择。

### 4.3 任务快照层

每次发送消息时，将有效配置冻结到任务：

```text
effective_model
 effective_thinking_level
 effective_runtime_id
```

任务执行不依赖之后发生的 Agent 或会话配置变化。

### 4.4 Runtime 层

daemon 根据 task 的：

- `agent_id` 获取 Agent 身份、指令、工具等基础信息
- `runtime_id` 确定执行 runtime
- task 中的 model override 决定模型
- task 中的 thinking override 决定 Thinking Mode

如果 task 没有会话覆盖，则使用发送时解析出的 Agent 默认值或 runtime 默认值。

## 5. Team Agent 设计

### 5.1 推荐的数据模型

建议增加显式的 `project_chat_thread`，而不是把配置塞进通用 `issue.metadata`：

```text
project_chat_thread
- id
- project_id
- issue_id
- agent_id
- base_model
- base_thinking_level
- model_override
- thinking_level_override
- status
- title
- created_by
- created_at
- updated_at
- closed_at
```

字段含义：

- `project_id`：归属项目。
- `issue_id`：消息时间线和 Agent task 的真实承载 Issue。
- `agent_id`：创建主题时绑定的 Agent 快照。
- `base_model`、`base_thinking_level`：创建主题时从 Agent 复制的默认值。
- `model_override`、`thinking_level_override`：当前主题的用户选择，可为空。
- `status`：active、closed、archived 等主题状态。
- `title`：未来支持多个主题时用于显示。

第一阶段可以继续保证每个项目只有一个 active Team Agent thread。第二阶段再开放多个 active 或历史 thread。

选择独立表的原因：

- 不污染通用 Issue 模型。
- 可以自然支持一个项目多个聊天主题。
- 可以保存 Agent 默认配置快照。
- 可以为会话配置增加结构化校验。
- 可以将“聊天主题”与“执行 Issue”明确区分。

### 5.2 Team Agent 的读取和创建边界

建议接口语义：

```text
GET  /api/projects/{projectId}/chat
POST /api/projects/{projectId}/chat
PATCH /api/projects/{projectId}/chat/config
```

第一阶段可以继续以项目为路径，不暴露 thread ID；内部返回：

```json
{
  "thread_id": "...",
  "issue_id": "...",
  "agent_id": "...",
  "model": "...",
  "thinking_level": "...",
  "model_source": "override|agent_default|runtime_default",
  "thinking_level_source": "override|agent_default|runtime_default"
}
```

行为规则：

- GET 只读，不创建 thread，不创建 Issue。
- POST 是显式创建操作，复用现有 `EnsureProjectChatIssue` 的并发安全能力。
- 首次发送可以在服务层幂等创建 thread 和 Issue。
- POST 与首次发送都必须使用数据库唯一约束或幂等键防止重复创建。
- `issue_id` 为空时，附件可以上传为当前用户的未绑定草稿附件，但不能进入团队可见的 Issue 附件列表，也不能触发团队广播。
- 发送消息时，服务端在同一发送事务中将已校验的草稿附件绑定到 Issue、comment 和 task。
- 发送失败时不能丢弃附件；附件保留为当前用户可重试的未绑定附件。
- 发送成功后，附件通过 Team Agent Issue、comment 和 task 对团队和 Agent 可见。
- 附件 ID 必须由服务端校验 workspace、上传者和未绑定状态，不能信任前端提交的任意 ID。

如果未来支持多个主题，接口扩展为：

```text
GET  /api/projects/{projectId}/chat/threads
POST /api/projects/{projectId}/chat/threads
GET  /api/projects/{projectId}/chat/threads/{threadId}
PATCH /api/projects/{projectId}/chat/threads/{threadId}/config
POST /api/projects/{projectId}/chat/threads/{threadId}/messages
```

### 5.3 Team Agent 的配置共享范围

当前 Team Agent 的隐藏 Issue 是项目级共享对话。因此推荐定义为：

```text
Team Agent 主题配置 = 项目成员共同看到的共享配置
```

模型选择权限不能继续简单复用“是否有权编辑 Agent”的判断。应增加会话配置权限：

- 有权发送 Team Agent 消息的成员可以读取配置。
- 是否允许修改共享主题配置由项目角色或 presenter 规则决定。
- 如果只有 owner/admin 可以修改，应在服务端强制校验。
- 如果 presenter 是当前唯一写入者，配置修改也应遵循相同的项目控制规则。

如果产品实际要求“每个用户在同一个 Team Agent 对话中使用自己的模型偏好”，那就不是 thread 级配置，而应另建：

```text
project_chat_user_preference
- project_id
- user_id
- model
- thinking_level
```

发送时按发送者读取，并将结果冻结到 task。这个方案不改变共享 Issue 的消息流，但配置不再是团队共享的。

## 6. Private Ask 设计

### 6.1 推荐的数据模型

在现有 `chat_session` 上增加会话级字段：

```text
chat_session
- model_override
- thinking_level_override
- base_model
- base_thinking_level
```

Private Ask 当前已经按 `(project_id, creator_id)` 隔离，这个模型与“当前用户的当前对话配置”完全匹配。

### 6.2 Private Ask 的行为

- 创建 Private Ask session 时读取项目绑定 Agent 的默认配置。
- 保存 `base_model` 和 `base_thinking_level`。
- 用户在 Private Ask 输入框中选择模型时，只更新当前 `chat_session`。
- 用户在 Private Ask 输入框中选择 Thinking Mode 时，只更新当前 `chat_session`。
- 不再显示“跟随 Team Agent 且不可编辑”的模型徽标。
- Private Ask 仍然使用项目绑定 Agent 的 instructions、skills、权限和 runtime 能力。

建议接口：

```text
GET   /api/projects/{projectId}/private-chat
PATCH /api/chat/sessions/{sessionId}/config
```

请求示例：

```json
{
  "model": "claude-sonnet-4",
  "thinking_level": "high"
}
```

接口只允许修改当前用户拥有的 session，不允许通过该接口更新 Agent。

## 7. 有效配置和优先级

建议定义统一的有效配置解析规则：

```text
有效模型：
    conversation.model_override
    -> conversation.base_model
    -> Agent 当前默认 model（仅兼容旧会话）
    -> runtime 默认模型

有效 Thinking Mode：
    conversation.thinking_level_override
    -> conversation.base_thinking_level
    -> Agent 当前默认 thinking_level（仅兼容旧会话）
    -> runtime 默认值
```

对于新建会话，优先保存 Agent 默认值快照，避免长期会话随 Agent 默认配置变化而漂移。

空值语义需要固定：

- 字段未提供：不改变当前会话配置。
- 空字符串：清除会话 override，回退到会话基础值。
- 非空字符串：设置会话 override。
- `null`：API 层应明确约定为清除，不能在不同接口中产生不同语义。

model 和 Thinking Mode 必须由服务端校验：

- model 必须属于当前 runtime 支持的模型目录。
- thinking_level 必须符合当前 runtime/provider 的能力。
- runtime 不支持该能力时返回明确的 400 错误。
- 不能只依赖前端 capability 列表校验。

## 8. 任务入队和执行快照

当前 Team Agent 发送链路在：

```text
SendProjectChatMessage
    -> IssueService.EnsureProjectChatIssue
    -> TaskService.SendProjectChatMessage
    -> enqueueMentionTaskWithCommentPlan
```

建议将会话配置解析放在服务端发送入口和 task enqueue 之间：

```text
1. 校验项目、thread/session 和调用者权限
2. 读取聊天主题或 chat_session 配置
3. 读取 Agent 基础配置和当前 runtime
4. 计算 effective model/thinking_level
5. 校验 runtime capability
6. 创建 comment 和 task
7. 将 effective 配置写入 task snapshot
8. 事务提交并广播事件
```

task snapshot 有两种实现方式：

### 方案 A：增加结构化 task 字段

```text
agent_task_queue.model_override
agent_task_queue.thinking_level_override
```

优点：

- 数据库约束和查询更加清晰。
- daemon 不需要解析任意 JSON。
- 便于审计、重试和问题排查。

缺点是需要迁移、sqlc 重生成和所有 task 创建路径适配。

### 方案 B：使用现有 task context

将字段放入现有 `context` JSON：

```json
{
  "chat_config": {
    "model": "claude-sonnet-4",
    "thinking_level": "high",
    "source": "conversation_override"
  }
}
```

优点是迁移较小，适合先做验证。

缺点是类型约束较弱，容易出现不同任务路径使用不同 JSON 结构。

**建议**：如果该能力确定为长期产品能力，使用方案 A；如果只是先验证 UX，可以使用方案 B，但必须定义统一的服务端 schema 和 daemon 解析函数，禁止前端直接拼接未定义 JSON。

无论采用哪种存储，任务执行都必须使用发送时的快照，而不是执行时重新读取当前 Agent 或会话配置。

## 9. 输入框和前端组件设计

现有 `ChatInputCore` 已支持 `leftAdornment`，应复用这一扩展点，将模型和 Thinking Mode 放置在输入框底部左侧。

建议组件结构：

```text
ChatInputCore
  leftAdornment = ChatConversationConfigControls
    ModelPicker
    ThinkingPicker
```

`ModelPicker` 可以继续复用：

```text
当前：ModelPicker -> api.updateAgent -> agent.model
目标：ModelPicker -> updateConversationConfig -> session/thread config
```

`ThinkingPicker` 使用现有 runtime/model capability 数据，但保存目标改为 session/thread。

前端状态要求：

- 初始值来自服务端当前会话配置。
- 选择后调用会话配置 PATCH 接口。
- 可以使用 optimistic update，但失败时必须回滚并提示。
- 不把选择结果只放在 Zustand 草稿状态中。
- 切换项目、切换主题和刷新页面后仍能恢复服务端配置。
- 当前聊天输入的 query key 必须包含 `projectId + mode + threadId/sessionId`。

模型选择权限要求：

- Team Agent 使用会话配置权限，不再使用 Agent 编辑权限作为唯一依据。
- Private Ask 只允许 session creator 修改自己的会话配置。
- 所有权限和 capability 校验由服务端执行，前端状态只负责展示。

## 10. Team Agent 附件生命周期

### 10.1 产品语义

本方案采用以下明确规则：

```text
打开聊天窗口
    -> 不创建 Issue，不上传文件

用户选择附件
    -> 允许上传
    -> 生成当前用户的未绑定草稿附件
    -> 不向团队广播，不进入团队聊天时间线

用户发送消息
    -> 创建或获取 Team Agent Issue
    -> 将草稿附件绑定到 Issue 和当前 comment
    -> 创建 Agent task
    -> 发送成功后团队和 Agent 才能看到附件
```

“团队共享”发生在消息发送成功之后。发送前的附件只是当前用户正在编辑的消息草稿组成部分，不是项目共享文件。

### 10.2 复用当前上传链路

当前 `POST /api/upload-file` 已允许 workspace 上传不带 `issue_id`、`comment_id` 或 `chat_session_id` 的附件。该能力可以用于 Team Agent 的发送前草稿附件：

```text
attachment.issue_id = NULL
attachment.comment_id = NULL
attachment.task_id = NULL
attachment.uploader_type = 当前调用者
attachment.uploader_id = 当前调用者
```

前端只保存返回的 attachment ID 作为当前 composer 草稿的一部分。服务端不能把这个 ID 当作已经属于某个 Issue，发送时必须再次验证：

- attachment 属于当前 workspace
- uploader 是当前发送者
- attachment 仍未绑定到 Issue、comment、task 或其他 source context
- attachment 没有被其他请求抢先绑定

未绑定附件不应出现在 Issue attachment 列表、Team Agent timeline 或 WebSocket 团队事件中。若下载接口允许通过 ID 访问，还应确保只有上传者在发送前能读取该附件，避免将草稿附件变成隐式共享资源。

### 10.3 发送时的原子绑定

当前发送链路大致是：

```text
SendProjectChatMessage
    -> EnsureProjectChatIssue
    -> 创建 comment
    -> 创建 Agent task
    -> 广播 comment
```

应将附件绑定纳入同一个服务事务：

```text
1. 校验 attachment IDs
2. 获取或创建 Team Agent Issue
3. 创建 comment
4. 将未绑定附件绑定到 Issue + comment
5. 创建 task，并将附件信息纳入 task 执行上下文
6. 提交事务
7. 发布带附件引用的 comment/task 事件
```

推荐新增一个面向聊天发送的服务层绑定操作，而不是让 handler 在发送成功后单独调用通用 `linkAttachmentsByIDs`。现有 `LinkAttachmentsToComment` 要求附件已经属于同一个 Issue，无法直接处理未绑定附件；可以新增一个带 workspace/uploader/未绑定条件的原子 SQL，或在同一事务中先执行 `LinkAttachmentsToIssue` 再执行 comment 绑定。

事务失败时：

- comment 不提交
- task 不提交
- 附件重新保持未绑定状态
- 已上传的对象保留，用户可以重试

事务成功后才允许广播附件已经可见的消息事件。这样团队成员不会看到“附件已出现但消息发送失败”的中间状态。

### 10.4 草稿附件清理

未发送的附件不能永久保留。建议使用以下清理规则：

- 前端删除草稿附件时调用现有删除接口，并校验上传者权限。
- 发送成功后附件不再是未绑定附件。
- 用户取消或关闭草稿后可以主动清理。
- 后台定时清理超过 TTL 的未绑定 workspace attachments。
- 清理前应确认 attachment 仍未绑定到任何 Issue、comment、task 或 session。

### 10.5 与未来多主题的关系

如果后续引入 `project_chat_thread`，未发送附件可以增加 `thread_id` 作为草稿归属，但仍不应在发送前变成团队共享附件：

```text
attachment.thread_id = 当前草稿主题
attachment.issue_id = NULL
```

发送时根据 thread 找到目标 Issue，再完成正式绑定。

## 11. Discussion 无 Issue 共享会话方案

### 11.1 当前实现与改造边界

当前仓库的 Discussion 并不是无 Issue 讨论。CR-2026-009 将其实现为：

```text
project
    -> hidden project_discussion Issue
    -> comment
    -> attachment.issue_id
    -> useIssueTimeline(issueId)
```

当前 Discussion 的 Issue 对用户不可见，普通讨论默认不触发 Agent，但数据库和服务层仍然创建了 `project_discussion` Issue。当前 Discussion Coordinator 也通过 Issue comment 和 Agent task 工作，CR-2026-012 的 merge-forward 最终会将内容转发到 Team Agent 的 `project_chat` Issue。

因此，如果要求“Discussion 中发送附件和 Agent 协办都不创建 Issue”，不能只调整附件绑定；需要将 Discussion 的消息承载从 Issue/comment 改为项目级共享 `chat_session`/`chat_message`。

Team Agent 不采用本节的无 Issue 改造，继续使用本方案前文定义的隐藏 `project_chat` Issue。Discussion 和 Team Agent 是两个不同的产品边界：

```text
Discussion：沟通、附件共享、Agent 协作，不自动创建工作 Issue
Team Agent：项目执行对话，继续使用隐藏 project_chat Issue
```

### 11.2 目标产品语义

Discussion 定义为项目级共享讨论会话，不直接代表工作任务：

```text
打开 Discussion
    -> 不创建 Issue

用户上传附件
    -> 暂存为当前用户草稿附件
    -> 不向团队广播

用户发送消息
    -> 写入共享 Discussion chat session
    -> 附件绑定到 chat_message
    -> 团队成员和协办 Agent 可见
    -> 不创建 Issue

用户明确点击“转为工作 Issue”
    -> 创建真实 Issue
    -> 引用 Discussion 消息和附件
    -> Agent 在 Issue 上执行
```

“团队共享”发生在消息发送成功之后。发送前的附件只是当前用户的消息草稿；发送后附件属于 Discussion 消息，项目成员和已授权 Agent 才能读取。

### 11.3 会话承载模型

推荐复用现有 `chat_session` 和 `chat_message`，增加明确的共享会话类型，而不是复制一套新的消息表：

```text
chat_session.kind
    private          # 当前 Private Ask 和普通私有聊天
    project_shared   # 项目共享 Discussion
```

项目共享 Discussion session 可以使用：

```text
chat_session
- id
- workspace_id
- project_id
- agent_id nullable
- creator_id       # 创建者和审计信息，不作为唯一访问控制
- runtime_id
- kind = 'project_shared'
- status
- created_at
- updated_at
```

如果多个 Agent 可以协办，`agent_id` 不应被当作唯一协办者。Agent 参与关系单独存储：

```text
discussion_participant
- session_id
- actor_type       # member / agent
- actor_id
- role             # member / coordinator / collaborator
- added_by
- created_at
- removed_at
```

第一阶段可以只有一个项目共享 Discussion session。后续需要多主题时，再增加 `project_chat_thread` 或让多个 `chat_session` 通过 thread 归属项目。

### 11.4 消息和附件模型

Discussion 消息使用现有 `chat_message`：

```text
chat_message
- chat_session_id
- role
- content
- task_id nullable
- created_at
```

发送前附件保持未绑定：

```text
attachment.issue_id = NULL
attachment.comment_id = NULL
attachment.chat_message_id = NULL
attachment.task_id = NULL
attachment.chat_session_id = NULL 或草稿会话标识
attachment.uploader_id = 当前用户
```

用户发送成功后：

```text
attachment.chat_message_id = 当前用户消息
attachment.chat_session_id = Discussion session
```

发送前不应将附件放到项目公共附件列表，也不应发送团队事件。服务端必须校验：

- 附件属于当前 workspace。
- 上传者是当前用户。
- 附件仍未绑定到其他对象。
- 附件 ID 没有被其他请求抢先使用。

如果现有附件表无法同时记录草稿归属和 `chat_message_id`，可以增加 `draft_id`，或增加单独的 `chat_draft_attachment` 关联表。不要直接把草稿附件写入 `issue_id`，否则在发送前就具有 Issue 归属。

### 11.5 Discussion 的访问权限

现有 Private Ask 查询通常按 `creator_id` 限制访问，不能直接放宽为所有项目成员。应为 `kind = 'project_shared'` 增加独立的访问判断：

```text
当前用户是 workspace/project 成员
    -> 可以读取项目共享 Discussion

当前用户有项目聊天发送权限
    -> 可以发送消息和上传附件

当前用户具备 Discussion 配置权限
    -> 可以添加或移除 Agent 协办者
```

`creator_id` 继续保留用于审计、创建者信息和清理，但不能成为 shared session 的可见性条件。

Agent 协办者也必须经过服务端授权：

- Agent 属于当前 workspace。
- 当前用户有权调用该 Agent。
- Agent runtime 可用或任务可以进入既有队列。
- Agent 被移除后不能继续接收新消息，但历史回复仍保留。

### 11.6 添加 Agent 协办者

“添加 Agent 协办者”本身不创建 Issue。它只建立 Discussion 和 Agent 的参与关系：

```text
添加 Agent 协办者
    -> 写入 discussion_participant
    -> Agent 可以接收后续明确指派的消息
    -> Agent 回复写入同一个 project_shared chat session
    -> 不创建 Issue
```

建议区分以下行为：

| 操作 | 是否创建 Issue | 结果 |
|---|---:|---|
| 添加 Agent 协办者 | 否 | 建立参与关系 |
| @mention Agent | 否 | 创建无 Issue 的 Agent chat task，Agent 回复 Discussion |
| 请求 Agent 总结/分析附件 | 否 | Agent 在 Discussion 中回复 |
| 转为工作 Issue | 是 | 创建正式执行 Issue |
| 升级为 CR | 是 | 进入现有 CR 注册流程 |

当前 `discussion_coordinator_agent_id` 可以作为默认协办 Agent 的项目级绑定，但不应继续把“绑定 Coordinator”和“创建 Issue”绑定在一起。

### 11.7 Agent 协办任务

Agent 在 Discussion 中回复时，任务可以使用现有 Chat task 结构：

```text
agent_task_queue.issue_id = NULL
agent_task_queue.chat_session_id = Discussion session
agent_task_queue.project_id = 当前项目
agent_task_queue.agent_id = 协办 Agent
agent_task_queue.runtime_id = Agent runtime
```

当前 claim SQL 已经包含 `chat_session_id` 的串行分支，也使用 `project_id` 处理项目级并发控制。改造时应保留：

- 同一 Discussion session 的上下文串行。
- 同一项目的 Team/Discussion 执行队列限制。
- 现有 task claim、重试、取消和 completion 机制。
- 任务模型和 Thinking Mode 的会话级快照。

任务发送时读取 Discussion session 的配置并冻结：

```text
Discussion session config
    -> effective model/thinking_level
    -> task snapshot
    -> daemon 执行
```

daemon 不应在执行时重新读取可变的 Agent 或 Discussion 配置。

### 11.8 讨论转工作 Issue

只有用户明确执行升级操作时才创建 Issue：

```text
Discussion session
    -> 用户选择消息、附件和协办 Agent
    -> 点击“转为工作 Issue”
    -> 创建真实 Issue
    -> 保存来源 session/message/attachment 引用
    -> 创建 Issue-backed Agent task
```

建议增加 promotion 记录：

```text
discussion_promotion
- id
- session_id
- source_message_ids
- source_attachment_ids
- target_issue_id
- promoted_by
- created_at
```

通过 promotion 的幂等键或唯一约束防止用户重复点击导致多个相同 Issue。

新 Issue 不应移动或删除原 Discussion 消息。原讨论保持完整，工作 Issue 只引用来源上下文。

### 11.9 协办附件与工作 Issue 的关系

附件已经属于 Discussion `chat_message` 后，不建议直接把同一条 attachment 记录搬到 Issue，因为当前附件归属字段是单对象模型：

```text
attachment.chat_message_id
attachment.issue_id
```

直接移动会导致原 Discussion 消息失去附件。推荐使用来源引用：

```text
new Issue
    -> source discussion session
    -> source message IDs
    -> source attachment IDs
```

如果工作 Issue 必须拥有自己的 Issue attachment，可以增加引用表：

```text
issue_context_reference
- issue_id
- source_type
- source_id
- attachment_id
```

只有在确实需要独立 Issue 附件生命周期时，才复制附件记录或创建显式多对多关系。不要在升级时静默改变原 Discussion 附件的归属。

### 11.10 与当前 Discussion Coordinator 和 merge-forward 的关系

当前 Discussion Coordinator 的实际流程是：

```text
Discussion comment
    -> Coordinator 路由
    -> Team Agent project_chat Issue
    -> Agent task
```

无 Issue Discussion 方案中应改为：

```text
Discussion chat_message
    -> Coordinator/协办 Agent task
    -> Discussion chat_message assistant reply
```

如果用户需要正式执行，再执行：

```text
Discussion
    -> 选择消息
    -> 转为工作 Issue
    -> Agent 在目标 Issue 上执行
```

原有 CR-2026-012 merge-forward 可以保留为一种“显式升级”入口，但目标不应再是自动创建或获取 `project_chat` Issue，而应先让用户选择：

- 仅让 Agent 在 Discussion 中总结，不创建 Issue。
- 创建一个正式工作 Issue。
- 进入 CR 注册流程。

### 11.11 实施阶段

**Phase D1：共享 Discussion 会话模型**

- 增加 `chat_session.kind = 'project_shared'`。
- 为项目创建/读取共享 Discussion session。
- 保留 Private Ask 的 creator-scoped 查询不变。
- 增加 project-scoped shared session 的权限判断。

**Phase D2：消息和附件迁移**

- Discussion 从 `useIssueTimeline` 切换为 `chat_message` 查询。
- 发送消息使用 shared session。
- 附件发送前保持未绑定，发送成功后绑定到 `chat_message`。
- 建立未绑定附件清理任务。
- 不发布发送前附件事件。

**Phase D3：Agent 协办**

- 增加 `discussion_participant`。
- 支持添加/移除 Agent 协办者。
- `@mention` 或明确请求创建无 Issue 的 Chat task。
- Agent 回复写回 Discussion shared session。
- 保留项目队列和 presenter 权限边界。

**Phase D4：显式升级**

- 增加 Discussion 到工作 Issue 的 promotion 接口。
- 保存消息和附件来源引用。
- 处理 Issue 创建幂等性。
- 保留现有 requirement-register 流程作为 CR 升级出口。

**Phase D5：历史兼容**

- 现有 `project_discussion` Issue 保留只读历史。
- 新消息进入 shared session，或提供一次性迁移脚本将历史 comment 转为 chat_message。
- 迁移前确保附件、事件和权限不会重复暴露。
- 不删除历史 Issue，直到所有引用和回放能力完成迁移。

### 11.12 Discussion 验收标准

- 打开 Discussion 不创建 `project_discussion` Issue。
- 上传附件不创建 Issue。
- 发送文字或附件消息不创建 Issue。
- 发送成功后，项目成员可以看到消息和附件。
- 发送前其他成员看不到附件，也不会收到附件广播。
- 添加 Agent 协办者不创建 Issue。
- Agent 可以在 Discussion 中回复而不创建 Issue。
- Agent task 使用 `chat_session_id`，`issue_id` 为空。
- 用户明确执行“转为工作 Issue”后才创建 Issue。
- Issue 创建后可以追溯来源 Discussion 消息和附件。
- 重复点击升级操作不会创建重复 Issue。
- Private Ask 的 creator-only 访问规则不被 shared Discussion 放宽。

## 12. Issue 和多轮对话边界

### 12.1 第一阶段规则

第一阶段不做自动主题识别，规则保持简单：

- 一个 active Team Agent thread 对应一个隐藏 `project_chat` Issue。
- 连续多轮消息继续进入当前 thread/Issue。
- 打开窗口不创建 thread/Issue。
- 点击“创建聊天主题”或发送第一条消息时创建。
- 新建主题是明确用户操作。
- 新主题默认不继承旧主题的完整历史。
- 如果用户选择“基于当前对话继续”，只传递明确生成的摘要或选中消息。

### 12.2 多 Issue 支持

当前 `project_chat` Issue 具有每项目唯一约束，因此不能直接通过重复插入支持多个主题。开放多主题时需要：

1. 增加 `project_chat_thread`。
2. 将 `issue_id` 绑定到 thread。
3. 将当前唯一约束从“项目只能有一个容器”调整为“一个 thread 只能有一个容器”。
4. 所有 timeline、task、附件和发送接口都通过 thread 解析 Issue。
5. 前端服务端保存当前 thread 指针，不能只依赖本地状态。

### 12.3 拆分和合并

拆分：

- 用户选择消息。
- 执行“转为新 Issue/新主题”。
- 新 Issue 保存来源 thread 和来源消息 ID。
- 原消息不移动，不在两个 Issue 间重复归属。

合并：

- 不直接修改历史 comment 的 Issue 归属。
- 创建一个新的合并 Issue，保存源 Issue/thread 关系。
- 将选中消息按固定格式汇总为一条新消息。
- 可以复用 CR-2026-012 的 Discussion merge-forward 思路，但必须是明确用户操作。

### 12.4 防止重复创建和状态漂移

- 创建接口使用数据库唯一约束。
- 首次发送和显式创建使用同一个幂等服务函数。
- 需要跨请求重试时增加 `Idempotency-Key`。
- 服务端响应返回 `thread_id` 和 `issue_id`。
- 前端收到响应后以服务端 ID 更新当前会话指针。
- 不根据前端“是否已经渲染过空态”判断 Issue 是否存在。

## 13. 上下文压缩

当前仓库没有发现统一的 runtime 主动压缩 API、daemon control command 或 provider capability。不能把 `/compact` 当普通用户消息发送，因为它会污染聊天历史，并且不能保证 runtime 执行真实压缩。

建议将上下文压缩作为独立的 runtime 控制能力，后续再实施：

```text
POST /api/chat/sessions/{sessionId}/compact
```

Team Agent 如果使用 thread，则对应：

```text
POST /api/projects/{projectId}/chat/threads/{threadId}/compact
```

执行流程：

```text
前端点击压缩
    -> 服务端验证用户、会话、当前任务和 runtime
    -> 检查 supports_compaction
    -> 发送 runtime control command: compact
    -> daemon 调用 runtime 原生压缩能力
    -> 保存摘要或更新 runtime session pointer
    -> 通过 task/session/WebSocket 返回结果
```

需要先明确：

- runtime capability：`supports_compaction`
- control command 协议
- 压缩期间是否禁止发送新消息
- 压缩失败是否保留原上下文
- 摘要存储位置
- Team Agent Issue 和 Private Ask session 的上下文生命周期

在底层协议完成前，不建议实现一个看似可用但实际发送普通文本的压缩按钮。

## 14. 实施阶段建议

### Phase 0：确认产品语义

明确两件事：

1. Team Agent 的会话配置是项目成员共享，还是每个用户独立。
2. Agent 默认值变化是否影响已经创建的旧会话。

推荐答案：

- Team Agent：项目共享聊天主题配置。
- Private Ask：用户自己的 session 配置。
- 旧会话保存 Agent 默认值快照，新会话继承最新默认值。

### Phase 1：会话级配置最小闭环

- 增加 Team Agent thread/config 数据模型，或在单主题阶段提供等价的结构化配置表。
- 给 Private Ask `chat_session` 增加配置字段。
- 增加读取和更新会话配置接口。
- 将 Team Agent 和 Private Ask 的模型选择器改为调用会话配置接口。
- 增加 Thinking Mode 选择和服务端 capability 校验。
- 严格禁止聊天输入框调用 `UpdateAgent`。

### Phase 2：任务快照

- 在消息发送服务中解析有效配置。
- 将配置冻结到 task。
- 修改 daemon/runtime 执行入口使用 task snapshot。
- 覆盖任务重试、重新 claim、延迟任务和失败恢复路径。
- 明确旧任务没有 snapshot 时的兼容 fallback。

### Phase 3：Team Agent 创建边界

- GET `/chat` 改为只读。
- POST `/chat` 作为显式创建入口。
- 首次发送继续调用幂等创建服务。
- 空态显示创建操作。
- 既有上传接口扩展为发送前未绑定草稿附件模式；发送成功后才绑定到 Issue、comment 和 task。

### Phase 4：Team Agent 多主题和 Discussion 会话

- Team Agent 开放 thread 列表和切换，继续以隐藏 `project_chat` Issue 作为执行容器。
- Discussion 增加 `project_shared` Chat Session，消息和附件不依赖 Issue。
- Discussion 增加 Agent 协办者和无 Issue Chat task。
- 增加 Discussion 到工作 Issue/CR 的显式 promotion。
- 增加 Team Agent 的新主题、关闭主题和归档主题。
- 用服务端 thread/session ID 管理上下文隔离。

### Phase 5：runtime 上下文压缩

- 先定义 runtime control protocol。
- 增加 capability 声明和 daemon 支持。
- 再接入 Team Agent 和 Private Ask 的压缩按钮。

## 15. 验收标准

### 配置隔离

- 在 Team Agent 输入框修改模型后，`agent.model` 数据库值不变。
- 在 Team Agent 输入框修改 Thinking Mode 后，`agent.thinking_level` 数据库值不变。
- Private Ask 修改配置后，其他用户的 Private Ask 不受影响。
- 修改一个 Team Agent thread 后，其他项目的 Agent 调用不受影响。
- Agent 管理页显示的原始 Agent 配置不被聊天操作改变。

### 任务一致性

- 发送消息时选择模型 A，之后切换到模型 B，已排队消息仍使用 A。
- 重试和重新 claim 不改变任务的模型和 Thinking Mode。
- 不支持的模型或 Thinking Mode 被服务端拒绝。
- runtime 更换后，旧会话配置不会静默使用不兼容的模型。

### 创建边界

- GET `/api/projects/{id}/chat` 不产生 `project_chat` Issue。
- 显式 POST 创建操作只创建一个容器。
- 并发首次发送最多产生一个 thread/Issue。
- 无 Issue 时允许上传未绑定附件，但发送前不进入团队时间线、不广播；发送成功后才成为团队和 Agent 可见内容。

### Discussion 边界

- 打开 Discussion 不创建 `project_discussion` Issue。
- 上传附件不创建 Issue，发送前附件仅属于当前用户草稿。
- 发送文字或附件消息不创建 Issue。
- 发送成功后，项目成员可以看到消息和附件。
- 添加 Agent 协办者或 `@mention` Agent 不创建 Issue。
- Agent 可以通过 `chat_session_id` 在 Discussion 中回复。
- 用户明确执行“转为工作 Issue”后才创建 Issue。
- Issue 创建后可以追溯来源 Discussion 消息和附件。
- Private Ask 的 creator-only 访问规则不被 shared Discussion 放宽。

### 上下文隔离

- 新主题不会自动携带旧主题完整历史。
- 切换 thread 后 timeline、task、附件和草稿不会串线。
- 刷新页面后服务端仍能恢复当前主题和配置。
- 拆分和合并保留来源关系，不改变历史消息原始归属。

## 16. 结论

本方案的核心原则是：

```text
Agent 是长期共享的智能体配置。
会话/聊天主题是当前对话的配置。
Task 是一次发送的不可变执行快照。
```

因此，聊天窗口中的模型和 Thinking Mode 选择不应再调用 `UpdateAgent`。Team Agent 继续使用项目聊天主题配置和隐藏 `project_chat` Issue，Private Ask 使用当前用户的 `chat_session` 配置，Discussion 使用项目级 shared `chat_session`；所有模式在发送时将有效配置冻结到 task，daemon 只执行任务快照。

这样既保留当前 Multica 的 Agent、Team Agent Issue、Private Ask `chat_session` 和 task 架构，又为 Discussion 增加不创建 Issue 的项目共享会话，满足“只修改当前对话、不修改已配置 Agent、讨论和附件发送不自动创建 Issue”的产品要求，并为未来的多 Issue、多主题、工作升级和上下文压缩留出清晰扩展边界。
