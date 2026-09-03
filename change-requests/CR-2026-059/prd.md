---
id: CR-2026-059-prd
type: PRD
cr-ref: CR-2026-059
title: Discussion 无 Issue 共享会话
target-version: 0.32
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-03T20:00:41+08:00
updated: 2026-09-03T21:58:00+08:00
---

# 1. 概述

## 1.1 问题陈述

项目 Discussion 目前仍把普通沟通、附件和 Coordinator 协办挂在隐藏 `project_discussion` Issue 的 comment 流上，与来源文档（`docs/product/Multica聊天会话级配置与Discussion方案.md`，CR-B 段）描述的目标承载不一致：

- `GET /api/projects/{id}/discussion` 打开面板就会 `EnsureProjectDiscussionIssue`，空面板也会留下一个工作容器。
- 普通文字、附件、绑定 Coordinator、@mention 协办都写 comment；协办任务挂在该 Issue 上，而不是无 Issue 的 chat task。
- 前端 `DiscussionPane` 用 Issue timeline 渲染消息，并把 `issue_id` 当作会话身份；发送走 comment API。
- `PATCH /api/chat/sessions/{sessionId}/config` 只对 Private Ask 生效且按 `creator_id` 门禁；Discussion 没有会话级模型 / Thinking Mode。
- `chat_session` 没有 `kind`，`agent_id` 非空，且 `(project_id, creator_id)` 的 active 唯一索引把「项目内任意 active session」都算进去——直接插入项目级 shared session 会与同一创建者的 Private Ask 撞车。

以上事实已在来源文档 §14 记录，并在本 CR 落笔前按当前 `../multica` 的 CR-2026-059 requirement worktree（已同步至 multica main）复核（见 §1.4）。本 CR 不处理 Discussion → 工作 Issue/CR 的显式升级，也不改 Team Agent 配置与发送内核。

## 1.2 解决方案摘要

把新 Discussion 从隐藏 Issue/comment 换成项目级 shared `chat_session` / `chat_message`：

```text
Discussion:
  chat_session(kind=project_shared)
    -> chat_message
    -> 可选 Coordinator chat task（issue_id 为空）
    -> 打开 / 发送 / 附件 / 协办均不创建工作 Issue
    -> 旧 project_discussion Issue 只读，新消息不双写
```

本 CR（来源文档 CR-B，注册摘要已拍板）交付一个可独立验收的闭环：

1. `chat_session.kind` 区分 `private` 与 `project_shared`；每个项目最多一个 active shared session。
2. Discussion GET 只创建或读取 shared session，不得创建 `project_discussion` Issue。
3. 项目成员读写 shared session；`creator_id` 只作审计，不作 ACL。
4. Discussion 会话级模型 / Thinking Mode 复用 CR-2026-056 的解析、校验和任务快照，不得第二套实现。
5. 普通消息只写 `chat_message`，不创建 Agent task、不创建 Issue。
6. 明确 @mention Coordinator 或分析/总结请求才创建无 Issue 的 chat task；回复写回同一 shared session。
7. 发送前附件复用 CR-2026-056 未绑定草稿契约；发送成功绑定到 session / message（协办时也绑 task）。
8. 旧 `project_discussion` Issue 保留只读回放；新消息不双写。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

将新 Discussion 从隐藏 Issue/comment 改为项目级 shared `chat_session`/`chat_message`，支持单一 Coordinator 协办，打开/发送/附件/协办均不自动创建工作 Issue。不含多 Agent 参与者表、Discussion 升级、历史全量迁移，以及 Team Agent 配置与发送链路。依赖已归档 CR-2026-056（来源文档 CR-A）的会话配置解析、任务快照和未绑定附件校验。

目标仓库为 sibling `../multica/`。knowledge-base 承载本 PRD 与来源文档；`../tools/` 无实施改动。

`target-version` 继承 `cr.md` 的 `0.32`（`crctl version-set` 已从 `unassigned` 更正），本文件不得改写该字段。

## 1.4 当前代码事实（落笔前核实）

基线：CR-2026-056 已合入 multica main 并已归档（KB `_history.yml` `final-status: archived`）；本 CR 的 requirement worktree 已于 2026-09-03 同步至 multica main `3759afb68bb76576bf5ec3efe82560cdea8fe132`（迁移最大编号仍为 **480**）。复核命令在 `../multica` 的 CR-2026-059 requirement worktree。

| 结论 | 证据 |
|---|---|
| Discussion GET 懒创建隐藏 Issue | `server/internal/handler/project_chat.go` `GetProjectDiscussion`（L224）调用 `EnsureProjectDiscussionIssue`（L250） |
| 容器创建集中在服务层 | `server/internal/service/project_chat.go` `EnsureProjectDiscussionIssue`（L55）；sqlc `GetProjectDiscussionIssue` |
| GET 响应只有 `issue_id` + `coordinator_agent_id` | `ProjectDiscussionResponse`（`handler/project_chat.go` L215）；前端 schema `packages/core/api/schemas.ts` `ProjectDiscussion`（L1400） |
| 前端按 Issue timeline 渲染 | `packages/views/projects/components/discussion-pane.tsx` |
| Coordinator 绑定已存在 | `project.settings.discussion_coordinator_agent_id`（`service/discussion_coordinator.go` L22 `ProjectSettingDiscussionCoordinatorID`） |
| Coordinator 激活走 comment mention | `comment.go` `handleDiscussionContainerMentionTrigger`（L2664）；任务挂在 Discussion Issue |
| Coordinator 转投 Team Agent 走 Issue comment | `service/discussion_coordinator.go` `RouteDiscussionToTeamAgent`（L103）；`MergeForwardDiscussion` 入参为 `comments []db.Comment`（`service/project_chat.go` L176） |
| `chat_session` 无 `kind` | `033_chat.up.sql` 及后续迁移未增加该列 |
| `chat_session.agent_id` 非空 + FK（CASCADE） | `033_chat.up.sql` L7 `agent_id UUID NOT NULL REFERENCES agent(id) ON DELETE CASCADE`；内联 FK，PostgreSQL 自动命名约束 `chat_session_agent_id_fkey`；同文件 `agent_task_queue.chat_session_id` 已是 `ON DELETE SET NULL`（既有先例） |
| Private Ask active 唯一索引不区分 kind | `436_chat_session_project.up.sql` `chat_session_project_creator_active_unique`（`(project_id, creator_id)`，谓词仅 `project_id IS NOT NULL AND status='active'`） |
| CR-A 配置列已在 `chat_session` | `478_chat_session_chat_config_columns.up.sql`：`base_model` / `base_thinking_level` / `model_override` / `thinking_level_override` |
| 通用配置 PATCH 仅 Private Ask + creator-only | `handler/chat.go` `PatchChatSessionConfig`（L858）：非创建者 403，无 `project_id` 404 |
| chat task 已支持 `chat_session_id` 且 `issue_id` 可空 | `033_chat.up.sql`；`CreateChatTask`（`pkg/db/queries/chat.sql` L1107） |
| 附件已支持未绑定及 session/message/task | `029_attachment` / `083_attachment_chat_columns` / `164_attachment_task_id` 迁移；CR-2026-056 上传者门与 168h sweeper（`service/chat_draft_attachment_cleanup.go`） |
| 当前最大迁移编号 **480** | `server/migrations/480_issue_project_chat_session_origin_uidx.up.sql` |
| 解析/快照/目录校验已落地 | `service/chat_config.go` `ResolveChatConfig`（L50）/ `ValidateResolvedChatConfig`（L88）/ `LoadChatCatalogForConfig`（L125）；`mergeChatConfigContext` |
| Idempotency-Key 基础设施已存在 | `server/pkg/publicapi/v1/foundation.go` `HeaderIdempotencyKey`、`MaxIdempotencyBytes = 255` |
| 错误体与发送错误映射已存在 | `handler.go` `writeErrorCode`（L549）；`handler/project_chat.go` `writeProjectChatSendError`（L589） |
| 同步后 trunk 新增内容不涉及 Discussion 代码路径 | multica main 相对本 CR 原基线（`217b281c`）新增：merge CR-2026-060: multica、`cr-prompts-revised/` Agent 提示词包、服务端 pipeline registry 再生成（`gate_nodes_gen.go`/`transitions_gen.go`） |

# 2. 用户故事

- **US-1 项目成员**：作为项目成员，我希望打开 Discussion 时不会悄悄创建一个隐藏 Issue，从而普通沟通不再污染工作项列表。
- **US-2 项目成员**：作为项目成员，我希望在 Discussion 里发文字和附件，其他成员立刻能看见，而这些消息不会创建 Agent task 或工作 Issue。
- **US-3 项目 owner/admin**：作为项目管理员，我希望 Discussion 的模型和 Thinking Mode 属于这条共享会话，改配置不影响 Agent 管理页，也不影响 Private Ask 或其他项目。
- **US-4 协办请求者**：作为具备 Agent 调用权限的成员，我希望只有明确 @mention Coordinator 或发起分析/总结时才启动 Agent，并且任务挂在会话上、没有 Issue。
- **US-5 协办观察者**：作为项目成员，我希望 Coordinator 的回复出现在同一条 Discussion 时间线里，而不是另开一个工作 Issue。
- **US-6 附件上传者**：作为附件上传者，我希望发送前的草稿只有我能看见；发送成功后才和消息一起对项目成员可见，失败时仍可重试。
- **US-7 历史读者**：作为项目成员，我希望仍能只读回放旧 Discussion Issue 里的历史消息，同时新消息只进入 shared session、不双写。
- **US-8 Private Ask 用户**：作为 Private Ask 用户，我希望 Discussion 的共享可见性不会放宽我的 creator-only 会话。

# 3. 功能需求

## FR-1 打开 Discussion 不得创建工作 Issue

`GET /api/projects/{projectId}/discussion` 可以创建或读取该项目的 active `project_shared` session，但不得调用 `EnsureProjectDiscussionIssue`，也不得以任何其他路径创建 `origin_type='project_discussion'` 的 Issue，或任何其他工作 Issue。未配置 Coordinator 时仍必须能打开纯人类会话。来源 FR-13、FR-14、§7.2、AC-16。

## FR-2 Discussion 使用 `chat_session.kind = project_shared`

为 `chat_session` 增加 `kind`：`private` | `project_shared`。已有行（1:1 聊天与 Private Ask）默认 `private`。新 Discussion 只使用 `project_shared`。不得复制一套 Discussion 消息表。来源 §5.3、FR-14。

## FR-3 每个项目最多一个 active shared session

第一阶段每个 `(workspace_id, project_id)` 最多一个 `kind=project_shared` 且 `status=active` 的 session。由部分唯一索引 + 服务层项目级并发锁共同保证。并发 GET 必须收敛到同一 `session_id`。来源 FR-17。

## FR-4 `creator_id` 不作 shared session ACL

shared session 仍写入 `creator_id`（首次打开者，审计用）。项目成员读取、发送、订阅实时事件不得因 `caller != creator_id` 被拒绝。不得用 `creator_id` 过滤 shared session 消息列表。非成员 / 已移出成员 / 仅持有 UUID 的拒绝规则见 FR-25，不得用「项目成员可读写」一句话代替负向契约。来源 FR-17、§9、AC-21。

## FR-5 Private Ask 与 1:1 的 creator-only 不得被放宽

`kind=private`（含 Private Ask 与无 `project_id` 的 1:1）继续走现有 creator-only 门禁。`PatchChatSessionConfig`、`SendChatMessage`、`GetChatSession`、实时事件不得因为新增 `project_shared` 分支，让非创建者读到或改到 Private Ask。来源 AC-21、§7.2、§9。

## FR-6 必须改写 Private Ask active 唯一索引谓词

现有 `chat_session_project_creator_active_unique`（`436_chat_session_project.up.sql`）在 `project_id IS NOT NULL AND status = 'active'` 上唯一，**不区分 kind**。本 CR 必须把它收窄为仅覆盖 `kind = 'private'`（或等价「非 project_shared」），否则插入 Discussion shared session 会与同一 `creator_id` 的 Private Ask 冲突。另增 `(workspace_id, project_id)` 上 `kind='project_shared' AND status='active'` 的部分唯一索引。索引均 `CREATE [UNIQUE] INDEX CONCURRENTLY`，一文件一条语句。来源 §5.3；本条是落笔前核实出的实施约束，来源文档未单列但属于 FR-3/FR-5 可落地前提。

## FR-7 `agent_id` 对 shared session 可空

shared session 在未绑定 Coordinator 时 `agent_id` 必须允许 NULL，以支持纯人类 Discussion。绑定 Coordinator 后可写入该 Agent id；解绑后回到 NULL，session 行不删。不得对无 Coordinator 的 GET/发送要求 Agent。现有 `INNER JOIN agent` 的 Private Ask / 1:1 查询不得被 NULL `agent_id` 带崩，也不得把无 Coordinator 的 shared session 从 Discussion 查询里滤掉。`agent_id` 是项目设置的**投影**，不是第二套绑定入口；权威源、同步、重绑与失效见 FR-26。列级 NOT NULL 与既有 CASCADE FK 的改动由 481 迁移落地（FR-21）：Coordinator Agent 被 hard-delete 时 session/message 行必须保留（不得级联删除）、`agent_id` 由 FK 置 NULL（AC-31/AC-32 验收）。来源 §5.3、FR-4。

## FR-8 Discussion 配置属于共享 session，owner/admin 可改

第一阶段由项目 owner/admin 修改模型和 Thinking Mode；必须服务端强制，仅隐藏前端控件不足够。没有 Coordinator 时仍可保存配置（基础快照在创建时写入：有 Coordinator 则取其当时默认值；无 Coordinator 则 `base_*` 允许空，有效值按 CR-2026-056 优先级回退到 runtime 默认，source 不得标成 `agent_default`）。来源 FR-4、FR-5、FR-6、§9。

## FR-9 配置 PATCH 按 kind 分流，复用 CR-A 解析与校验

`PATCH /api/chat/sessions/{sessionId}/config`：

- `kind=private`：保持 CR-2026-056 行为（creator-only；无 `project_id` 的 1:1 仍 404）。
- `kind=project_shared`：项目成员可 GET 配置；PATCH 仅 owner/admin。非 owner/admin PATCH 返回 403 `forbidden_chat_config`。

有效值解析、三态 PATCH（省略 / `null` 或空串清除 override / 非空设置 override）、目录与 runtime 校验必须调用 CR-2026-056 已落地的 `ResolveChatConfig` / `ValidateResolvedChatConfig` / `LoadChatCatalogForConfig`，禁止第二套快照逻辑。无 Coordinator（`agent_id` 为空）时不得走「创建者 Agent」路径，也不得调用 `UpdateAgent`。来源 FR-26、FR-28、§6、§7.2；依赖 CR-2026-056。

## FR-10 普通 Discussion 消息只写 chat_message

项目成员发送普通文字或附件消息：只创建 `chat_message`（`role=user`），不创建 Agent task，不创建 Issue，不写 comment。来源 FR-15、AC-17、AC-18、§8.2。

## FR-11 明确请求才创建无 Issue 的 chat task

仅在以下情况创建 chat task：

1. 消息明确 `@mention` **当前可路由 Coordinator**（FR-26 的解析结果）；或
2. 用户点击分析 / 总结（或等价的显式协办操作，`coordinator_request=analyze|summarize`）。

`coordinator_request` 与正文 @mention 不得双建 task：`analyze`/`summarize` 优先于 mention 推导；`mention` 与正文 @mention 只建一个 task。@mention 其它 Agent 不当作协办，走 FR-10。

任务必须：`chat_session_id` = 该 shared session；`issue_id` 为空；`agent_id` = 入队当时可路由 Coordinator；入队前写入 `context.chat_config` 快照（合并保留已有字段，禁止整对象覆盖）。设置未绑定 → 409 `discussion_coordinator_not_configured`；已绑定但 Agent 删除/归档/不在本 workspace → 409 `discussion_coordinator_unavailable`；两者都不创建 task 与 Issue。不具备 Agent 调用权限的成员发起协办被 403（现有 invocation 拒绝，不新造枚举）。来源 FR-16、FR-26、AC-19、§8.2、§9。

## FR-12 Coordinator 回复写回同一 shared session

Coordinator（及由其触发的助手消息）写入同一 `project_shared` session 的 `chat_message`（`role=assistant`），不得创建工作 Issue，不得把新回复写到旧 `project_discussion` Issue。执行、重试、重新 claim 只读该任务的 `chat_config` 快照。来源 FR-16、FR-27、AC-20。

## FR-13 现有 Coordinator 转投与 merge-forward 的 Discussion 侧适配

CR-2026-012 的两条既有能力必须在新承载上继续可触发，但**不得改写** CR-2026-056 的 Team Agent 发送事务：

1. Coordinator 把工作转投到 Team Agent（`RouteDiscussionToTeamAgent` / DD-5）：触发源从 Discussion Issue comment 改为 shared session 消息；之后调用既有 Team Agent 发送内核。
2. 成员多选 Discussion 消息 merge-forward（`POST /api/projects/{id}/chat/merge-forward`）：入参从仅 `comment_ids` 扩展为 shared session 的 `message_ids`。完整 HTTP 八项见「merge-forward HTTP 契约」与 FR-23 / FR-24。

明确不修 CR-2026-056 台账中的 KG-1（转投无 `chat_config` 快照）和 KG-2（换绑后转投仍写旧 Issue）。来源 cr.md「不含 Team Agent 配置与发送链路」；兼容既有 Discussion UI，避免新承载把协办/转投打成死链。

## FR-14 发送前附件是上传者草稿

复用 CR-2026-056 未绑定附件契约：发送前五类绑定字段全空；只有上传者可访问、下载、删除和重试绑定；不得出现在项目公共附件列表、Team Agent timeline、Discussion 消息流或团队 WebSocket。不得另建草稿表。来源 FR-18、FR-19；依赖 CR-2026-056。

## FR-15 发送成功原子绑定，失败保留草稿

Discussion 发送成功时，附件必须在同一发送事务中绑定到 `chat_session` 和 `chat_message`；若本条触发了协办 task，也绑定 `task_id`。事务失败不得留下半成品消息/task/Issue；未绑定附件保留供重试。发送失败不得删除草稿。TTL sweeper 继续用 CR-2026-056 的 168h 周期，本 CR 不改谓词。来源 FR-20 Discussion 分支、FR-21、§8.2。

## FR-16 旧 project_discussion Issue 只读、不双写、不补建

已存在的 `origin_type='project_discussion'` Issue 保留，可供只读回放。切换后：

- 新消息只进入 `project_shared` session。
- 不得把新消息再写进该 Issue（不双写）。
- 不得删除旧 Issue。
- GET Discussion **不得**为「还没有历史容器」的项目补建该 Issue。

GET 响应可带可空 `legacy_issue_id`（已有历史容器则为 UUID，否则 JSON `null`），供只读回放；该字段出现不得被前端当成可写 session 身份。来源 AC-22、§11.1。

## FR-17 GET/PATCH/发送携带 session 身份并防漂移

Discussion 的配置 PATCH 与发送必须针对 GET 返回的 `session_id`。服务端确认该 session 属于当前 workspace/project、`kind=project_shared`。精确状态不得「404/409 二选一」，映射固定为：

| 条件 | 状态 | error-code |
|---|---|---|
| session 不存在、跨 workspace、跨项目、`kind≠project_shared`、调用者不是该项目**当前**成员 | 404 | `chat_session_not_found` |
| 调用者是当前项目成员，但 `status≠active`（已归档/关闭）且操作为 PATCH 或 POST | 409 | `chat_session_closed_or_changed` |
| 同上，但操作为消息列表 GET | 200 | （只读；不创建新 session） |

不得静默另开 session，不得落到 Private Ask 行上。来源 §7.2、§7.3。

## FR-18 可区分错误与前端回滚

至少保持并覆盖 Discussion 路径（状态与 code 一一对应，禁止只写 2xx / 4xx）：

```text
400 invalid_model_or_thinking_level
400 invalid_discussion_message
400 invalid_message_selection
400 invalid_merge_forward_selection
400 invalid_cursor
400 idempotency_key_required
403 forbidden_chat_config
403 forbidden_project_discussion
404 chat_session_not_found
409 chat_session_closed_or_changed
409 discussion_coordinator_not_configured
409 discussion_coordinator_unavailable
409 attachment_already_bound
409 idempotency_key_reused
```

legacy `comment_ids` 路径继续使用既有 400 `invalid_comment_selection`（本 CR 不改该 code）。前端根据错误回滚配置控件或保留草稿，不静默丢失输入和附件。来源 §7.3。

## FR-19 前端 DiscussionPane 改走 shared session

`DiscussionPane` 必须以 `session_id` 为会话身份：拉消息、发送、附件、配置控件、实时更新都走 shared session API，不再把 GET 的 `issue_id` 当作可写容器。硬降级规则对齐 CR-2026-056：`session_id` 缺失 / 空 / 非 UUID 时只读并重试 GET，禁止拿空 id 去 PATCH/发送。只读历史通过 `legacy_issue_id` 渲染旧 Issue timeline，且明确不可在该流发送。Model / Thinking 控件调用会话配置接口，不调用 `UpdateAgent`。来源 FR-29 中与功能接入相关的部分（不重做 composer 视觉，视觉属 CR-D）。

## FR-20 实时事件对项目成员可见

shared session 的新消息、协办 task 事件必须广播给**当前**项目成员，不得沿用 Private Ask 的 per-creator 投递。Private Ask 事件投递保持 per-user。成员被移出后的退订 / 不广播见 FR-25。来源 §9、AC-21。

## FR-21 迁移、sqlc 与定制台账

新迁移从下一个可用编号 **481** 起。禁止新增 FOREIGN KEY / REFERENCES / 级联删除或更新。**唯一允许的既有 FK 生命周期改动**（这是「转换既有约束」，不是新增 FK）：

**481 迁移：`agent_id` 改可空 + 既有 FK `ON DELETE CASCADE` → `ON DELETE SET NULL`**（落地 FR-7 / FR-26 的 Coordinator hard-delete 保留语义；取评审推荐方案——保留 DB 级引用完整性，不采用「删除 FK + 纯应用层校验」）：

- `up`（同一迁移文件按序执行）：
  ```sql
  ALTER TABLE chat_session ALTER COLUMN agent_id DROP NOT NULL;
  ALTER TABLE chat_session DROP CONSTRAINT chat_session_agent_id_fkey;
  ALTER TABLE chat_session ADD CONSTRAINT chat_session_agent_id_fkey
      FOREIGN KEY (agent_id) REFERENCES agent(id) ON DELETE SET NULL;
  ```
  约束名沿用 PostgreSQL 对 `033_chat.up.sql:7` 内联 FK 的自动命名（该文件未显式命名）；引用列与被引用列不变。`ADD CONSTRAINT` 不自动建索引，与基线一致（基线该列亦无独立索引），本 CR 不新增该列索引。
- `down`：反向恢复——`DROP CONSTRAINT chat_session_agent_id_fkey` → 重建为 `... ON DELETE CASCADE` → `ALTER COLUMN agent_id SET NOT NULL`。最后一步在存在 NULL `agent_id` 行时会失败，属**数据依赖回滚**：注释必须写明「先清理 NULL 行再回滚」，禁止静默吞掉或伪造成功。
- 除此之外不新增任何 FK；`chat_message.chat_session_id`、`chat_session.workspace_id/creator_id` 的既有 CASCADE 不属本 CR 范围，不动。

每个新增索引必须 `CREATE [UNIQUE] INDEX CONCURRENTLY` 且一个迁移文件一条语句。本 CR 在 multica 仓落地的新文件、挂钩点和迁移必须登记 `CUSTOM.md`（编号顺延）。代码注释一律英文。

## FR-22 Discussion 四主 endpoint HTTP 八项闭合

`GET /discussion`、`PATCH .../config`、`GET .../messages`（及同语义的 `.../messages/page`）、`POST .../messages` 必须按下方「Discussion HTTP 契约」闭合：endpoint、request、response、精确状态/error-code、权限、幂等、状态副作用、验收观察点。禁止成功只写「2xx」，禁止错误只写「404 或 409」。

## FR-23 merge-forward 入参扩展必须闭合修改契约

`POST /api/projects/{id}/chat/merge-forward` 新增 `message_ids` 后，必须按下方「merge-forward HTTP 契约」闭合互斥、空/重复/顺序/跨 session、权限、响应、错误、成功状态、幂等与副作用。legacy `comment_ids` 行为与 error-code 保持 CR-2026-012（400 `invalid_comment_selection`）。不得改 `sendProjectChatCore`。

## FR-24 有副作用的 Discussion 入口必须可安全重试

`POST .../messages`（`kind=project_shared`）与带 `message_ids` 的 merge-forward 必须接受 `Idempotency-Key`（现有头，`server/pkg/publicapi/v1/foundation.go`，最长 255 字节）。缺头 400 `idempotency_key_required`。同一调用者 + 同一 session/project + 同一 key：指纹相同则重放首次成功响应（201，同一 `message_id`/`task_id` 或 merge-forward 的 `comment_id`/`task_id`），不新建 message/task，已绑定附件不得退化成 409 `attachment_already_bound`；指纹不同则 409 `idempotency_key_reused` 且零写入。并发同一 key 必须收敛到一次提交。记录至少保留 24h。Private Ask `POST .../messages` 与 legacy `comment_ids` merge-forward **不**新要求该头。

## FR-25 shared session 安全负向契约

授权以**请求当时**的项目成员资格为准，不看 `creator_id`，不看历史上是否开过面板。

| 调用者 | 项目路径 `GET /discussion` | session 路径（消息 GET/POST、PATCH config） | 已发送附件下载 | 实时 |
|---|---|---|---|---|
| 当前项目成员 | 按主契约 | 按主契约 | 允许 | 订阅并接收 |
| 同 workspace 非本项目成员 | 403 `forbidden_project_discussion` | 404 `chat_session_not_found` | 404（不确认附件存在） | 拒绝订阅；不广播 |
| 已被移出项目的旧成员 | 同上 403 | 同上 404 | 同上 404 | 成员变更处理中退订；之后不广播 |
| 仅持有 session/message/attachment UUID、无当前成员资格 | 无项目路径则不适用 | 404 `chat_session_not_found` | 404 | 拒绝订阅；不广播 |

未绑定草稿仍仅上传者可访问（FR-14）。Private Ask 维持 creator-only。不得因持有 UUID 而从 shared 分支漏读。

## FR-26 Coordinator 唯一权威源与生命周期

**写权威**：`project.settings.discussion_coordinator_agent_id`（既有项目 settings PATCH，本 CR 不另造绑定 URL）。非法 UUID / 非本 workspace Agent 保持现有 400。

**投影**：active `project_shared` session 的 `agent_id` 必须在项目锁下与写权威对齐，禁止长期分叉。

| 事件 | settings | session.agent_id | `base_*` | 已入队 task |
|---|---|---|---|---|
| 首次 GET 尚无 session | 不变 | 创建时写入当时 settings（可空） | 有可路由 Coordinator 则取其当时默认；否则允许空（FR-8） | 无 |
| 首次绑定（空 → Agent） | 写入 UUID | 同一事务投影 | **补写**当时 Agent 默认（仅当 `base_*` 仍空） | 不变 |
| 替换（Agent A → B） | 写入 B | 投影为 B | **不**重取快照 | 保持旧 `agent_id` 与 `chat_config` |
| 解绑（UUID → 空） | 清除 key | 投影为 NULL | 不变 | 保持旧绑定直到终态 |
| Agent 归档 / 不在 workspace | settings 保留原 UUID，GET 仍回该值；**不**自动清 settings | 投影为 NULL（不可路由） | 不变 | 保持旧绑定直到终态 |
| Agent hard-delete（`agent` 行删除） | settings 保留原 UUID，GET 仍回该值（settings 是 project 级数据，不随 agent 行删除） | **DB 级 FK `ON DELETE SET NULL` 置 NULL**（481 迁移）；session/message 行**保留**（不级联删除） | 不变 | 保持旧绑定直到终态；历史消息与回放完整可读 |

**读规则**（GET / @mention / 新 task 路由，任一入口不得混读）：

1. 可路由 Coordinator = settings UUID，且该 Agent 在本 workspace 存在且未归档。
2. GET `coordinator_agent_id` = settings 原值（未配置则空串）；即使 Agent 已失效也回原 UUID，供 UI 展示坏绑定。
3. @mention 校验与新 task 路由只使用「可路由 Coordinator」。失效时新协办 409 `discussion_coordinator_unavailable`。
4. 竞态：settings PATCH 与 GET/发送必须抢同一项目锁；锁内先写 settings 再投影 `agent_id`，或 GET 发现分叉则先修复再返回。并发 GET 仍收敛到 FR-3 的同一 `session_id`。
5. Agent hard-delete 不得级联删除 `chat_session` / `chat_message`：481 迁移把 FK 改为 `ON DELETE SET NULL` 后，删除 agent 行只把 session.`agent_id` 置 NULL，session/message 行与历史回放完整保留，事务与回放验收见 AC-32。

## Discussion HTTP 契约（可执行，覆盖 FR-1 / FR-8 / FR-9 / FR-10 / FR-11 / FR-17 / FR-22 / FR-24 / FR-25）

一期保留项目路径；`PATCH /config` 与 `GET|POST .../messages` 已存在，按 `kind` 分流，不另造平行 URL。

```text
GET    /api/projects/{projectId}/discussion
PATCH  /api/chat/sessions/{sessionId}/config
GET    /api/chat/sessions/{sessionId}/messages
GET    /api/chat/sessions/{sessionId}/messages/page
POST   /api/chat/sessions/{sessionId}/messages
```

公共错误体：`{ "code": "<error-code>", "error": "<message>" }`（与现有 `writeErrorCode` 一致）。未登录走现有 401，本表不重复。

### GET `/api/projects/{projectId}/discussion`

| 项 | 契约 |
|---|---|
| request | 无 body。`projectId` 为 UUID。 |
| 权限 | 当前项目成员。同 workspace 非成员 / 已移出：403 `forbidden_project_discussion`。项目不在本 workspace：404（现有 `project not found`，无 code）。 |
| 成功 | **200**。创建或读取该项目唯一 active `project_shared` session；不得创建 Issue。 |
| 幂等 | 不要求 `Idempotency-Key`。并发 GET 在项目锁下收敛到同一 `session_id`（FR-3）。若仅有已归档 shared session，本 GET **新建**一条 active session，不自动解档。 |
| 副作用 | 可能插入一行 `chat_session`；禁止插入 `project_discussion` Issue。 |

成功体：

```json
{
  "session_id": "<uuid>",
  "issue_id": null,
  "legacy_issue_id": "<uuid>|null",
  "coordinator_agent_id": "<uuid-or-empty>",
  "model": "<id-or-empty>",
  "thinking_level": "<level-or-empty>",
  "model_source": "override|session_default|runtime_default",
  "thinking_level_source": "override|session_default|runtime_default"
}
```

- `issue_id` 必须为 JSON `null`。
- `legacy_issue_id` 仅回放；无历史则为 `null`；本 GET 不得插入该 Issue。
- `coordinator_agent_id` 按 FR-26 回 settings 原值；未配置时为空字符串，不得伪造 UUID。
- 不得返回 `agent_default`。

### PATCH `/api/chat/sessions/{sessionId}/config`（`kind=project_shared`）

| 项 | 契约 |
|---|---|
| request | 无 `session_id` 字段（id 在 path）。body 三态与 CR-2026-056 FR-6 全等：`model` / `thinking_level` 省略=保持，`null` 或 `""`=清 override，非空=设 override。 |
| 权限 | 当前项目 owner/admin。当前成员但非 owner/admin：403 `forbidden_chat_config`。非成员 / 跨项目 / 错误 kind：404 `chat_session_not_found`（FR-17）。 |
| 成功 | **200**。响应配置字段与 GET Discussion 相同（含 `session_id`；`issue_id` 仍为 null）。 |
| 错误 | 400 `invalid_model_or_thinking_level`；409 `chat_session_closed_or_changed`（成员看到已归档 session）。非法 JSON：400（现有 `invalid request body`）。 |
| 幂等 | 不要求 `Idempotency-Key`；末次提交获胜。不创建 session。 |
| 副作用 | 只改该 session 的 override；不调用 `UpdateAgent`；不影响已入队 task。 |

`kind=private` 保持 CR-2026-056：creator-only；无 `project_id` 的 1:1 仍 404。

### GET 消息列表（`kind=project_shared`）

Discussion **禁止**对 shared session 返回无分页裸数组。`GET .../messages` 与已有 `GET .../messages/page` 对 `kind=project_shared` **同语义**，响应必须是分页对象，不得是 `ChatMessageResponse[]`。`kind=private` 的 `GET .../messages` 仍为现有裸数组，本 CR 不改。

| 项 | 契约 |
|---|---|
| request | query：`limit` 可选，默认 50，范围 1–100；`before_created_at`（RFC3339Nano）与 `before_id`（UUID）必须成对出现或成对省略。非法 limit/缺一半 cursor：400 `invalid_cursor`。无 body。 |
| 排序 | SQL 先取更新窗口，序列化前反转为页内时间正序（与现有 `ListChatMessagesPage` 全等）。 |
| 权限 | 当前项目成员。非成员 / 错误 kind / 跨项目：404 `chat_session_not_found`。已归档 shared session：**200** 只读。 |
| 成功 | **200**。 |
| 幂等 | 只读，无 `Idempotency-Key`。 |
| 副作用 | 无。不得混入 Private Ask 消息。 |

成功体（沿用现有 `ChatMessagesPageResponse`）：

```json
{
  "messages": [
    {
      "id": "<uuid>",
      "chat_session_id": "<uuid>",
      "role": "user|assistant",
      "content": "<string>",
      "task_id": "<uuid>|null",
      "created_at": "<rfc3339>",
      "attachments": []
    }
  ],
  "limit": 50,
  "has_more": false,
  "next_cursor": { "created_at": "<rfc3339nano>", "id": "<uuid>" }
}
```

`has_more=false` 时省略 `next_cursor`。`messages` 可为空数组。

### POST `/api/chat/sessions/{sessionId}/messages`（`kind=project_shared`）

请求头：`Idempotency-Key` 必填（FR-24）。请求体：

```json
{
  "content": "这段讨论请看附件",
  "attachment_ids": ["<uuid>"],
  "coordinator_request": "none|mention|analyze|summarize"
}
```

输入约束（违反一律 400 `invalid_discussion_message`，零写入）：

- `content` 去首尾空白后为空 **且** `attachment_ids` 缺省或长度为 0：拒绝（至少一项）。
- `attachment_ids` 含重复 UUID：拒绝（不静默去重）。
- `attachment_ids` 元素非 UUID：400（现有 `parseUUIDSliceOrBadRequest`）。
- `coordinator_request` 缺省视为 `none`；其它非法枚举：拒绝。
- `content` 可为空字符串，只要有合法附件。

| 项 | 契约 |
|---|---|
| 权限 | 当前项目成员可发普通消息。协办另需 Agent 调用权限，否则 403（现有 invocation）。非成员：404 `chat_session_not_found`。 |
| 成功 | **201 Created**（禁止 200/204/空 body）。 |
| 错误 | FR-17 归档 409 `chat_session_closed_or_changed`；FR-11 两个 409 coordinator code；已绑定附件 409 `attachment_already_bound`（仅当**非**幂等重放）；配置 400 `invalid_model_or_thinking_level`；缺幂等头 400 `idempotency_key_required`；指纹冲突 409 `idempotency_key_reused`。 |
| 幂等 | FR-24。指纹 = trim(`content`) + 稳定排序后的 `attachment_ids` + `coordinator_request`（重复 ID 在校验阶段已 400，进不了指纹）。重放 201 且同一 `message_id`/`task_id`。 |
| 副作用 | 普通消息：一条 `chat_message`（`role=user`），无 task、无 Issue。协办：同一事务再加一条 `issue_id` 为空的 chat task。附件在同一事务绑定。失败零残留。 |

成功体：

```json
{
  "session_id": "<uuid>",
  "message_id": "<uuid>",
  "issue_id": null,
  "task_id": null
}
```

`session_id` 等于 path。普通消息 `task_id` 为 JSON `null`；协办成功为非空 UUID。`issue_id` 恒为 `null`。失败不返回半成品 id。

## merge-forward HTTP 契约（覆盖 FR-13 / FR-23 / FR-24）

`POST /api/projects/{id}/chat/merge-forward`

请求体：

```json
{
  "comment_ids": ["<uuid>"],
  "message_ids": ["<uuid>"],
  "register_cr": false
}
```

互斥与输入：

| 条件 | 状态 | error-code |
|---|---|---|
| `comment_ids` 与 `message_ids` 均非空 | 400 | `invalid_merge_forward_selection` |
| 仅 `comment_ids`（含 `{}` / 空数组 / 省略 `message_ids`，与今日行为一致） | 沿用 CR-2026-012 | `invalid_comment_selection`（空、>50、非本项目 Discussion comment） |
| `message_ids` 键存在且为空数组，且无非空 `comment_ids` | 400 | `invalid_message_selection` |
| `message_ids` 非空：长度 >50；任一 id 非本项目 `kind=project_shared` 的 **同一** session；跨 session；Private Ask / 他项目 / 普通 Issue | 400 | `invalid_message_selection` |
| `message_ids` 含非 UUID | 400 | 现有 generic bad request |
| `message_ids` 重复 | 按首次出现顺序静默去重（与现有 comment 去重一致），去重后仍须 ≥1 且 ≤50 | — |

`register_cr` 缺省 `false`；`true` 时仍只向 Team Agent 合并文本追加 instruction block，零 CR 账本写入。

| 项 | 契约 |
|---|---|
| 权限 | 当前项目成员且具备既有 Team Agent 发送权限（含 presenter 规则）。非成员：403 `forbidden_project_discussion`。项目不存在：404 `project not found`。 |
| 成功 | **201**。体为既有 `SendProjectChatMessageResponse`：`session_id`、`issue_id`、`comment_id`、`task_id`（Team Agent 侧，均非空 UUID）。 |
| 错误 | 内核错误沿用 `writeProjectChatSendError`（403 `presenter_required`、409 `team_agent_not_configured`、429 `project_queue_full`、502 `enqueue_failed` 等）。`message_ids` 路径缺 `Idempotency-Key`：400 `idempotency_key_required`；指纹冲突：409 `idempotency_key_reused`。 |
| 幂等 | **仅** `message_ids` 路径要求 `Idempotency-Key`（FR-24）。指纹 = 去重后顺序保留的 `message_ids` + `register_cr`。重放 201 且同一 `comment_id`/`task_id`。legacy `comment_ids` 不新要求该头。 |
| 副作用 | 调用既有 merge-forward 内核：Team Agent 侧一条合并 comment + 一条 task。Discussion 源 `chat_message` / 旧 comment **不**移动、不删除、不双写回 Discussion。无 Team Agent 容器时由内核按既有规则 ensure（本 CR 不改）。 |

## legacy 响应安全降级（覆盖 NFR-8）

Discussion GET 用独立 zod schema，不要把 `session_id` 做成可写的空默认后继续操作。硬降级 / 软默认对齐 CR-2026-056「legacy 响应安全降级」：缺 `session_id` 则只读；合法 `session_id` 但缺配置字段时可写并重试。`issue_id` 出现非 null 不得被当成可写容器（本 CR 的可写身份只有 `session_id`）。

# 4. 非功能需求

- **NFR-1 双端一致**：web 与 desktop 共享 `packages/views` 行为一致；mobile 不在本 CR 范围。
- **NFR-2 四语文案**：新增 UI 文案提供 en/ja/ko/zh-Hans；`packages/views/locales/parity.test.ts` 对新增 key 全绿。
- **NFR-3 复用优先**：复用 `chat_session` / `chat_message`、CR-2026-056 配置解析与附件草稿、已有 chat task（可无 Issue）。不给 `agent_task_queue` 增加模型/Thinking 专用列，不复制 Discussion 消息表，不新增 `discussion_participant`。
- **NFR-4 并发与事务**：GET 创建 shared session 必须在项目锁下幂等；发送事务失败零残留；配置修改与 Coordinator 重绑只影响尚未入队的协办任务；同一 `Idempotency-Key` 并发必须收敛到一次提交。
- **NFR-5 安全**：未绑定附件下载必须校验上传者；shared session 的成员门禁、配置写权限、已发送附件下载与实时订阅必须服务端强制（FR-25）；不得用 session/message/attachment UUID 猜测读取。
- **NFR-6 兼容**：旧 `project_discussion` 只读；Private Ask / 1:1 / Team Agent 路径除本 CR 明确的索引谓词与 kind 分流外不得改变行为。
- **NFR-7 零 Team Agent 内核回归**：不修改 `sendProjectChatCore` 的配置写入、容器绑定和附件绑定语义；转投/merge-forward 只改 Discussion 侧入参适配。KG-1/KG-2 保持已知缺口。
- **NFR-8 API 兼容**：Discussion GET/发送响应必须经 `parseWithFallback` + zod schema，缺失 `session_id` 不得白屏、不得伪造 UUID。
- **NFR-9 依赖**：必须使用已归档 CR-2026-056 的会话配置解析、任务快照和未绑定附件校验；禁止平行实现。

# 5. 验收标准

| ID | 覆盖 FR | 可执行验收 |
|---|---|---|
| AC-1 | FR-1、FR-16 | 打开 Discussion 面板不创建 `project_discussion` 或其他工作 Issue；`GET` 的 `issue_id` 为 null；无历史容器时 `legacy_issue_id` 为 null 且数据库无新 `origin_type='project_discussion'` 行。 |
| AC-2 | FR-1、FR-10、FR-11 | 发送普通文字、上传附件、绑定/解绑 Coordinator、请求协办后，均不新增工作 Issue。 |
| AC-3 | FR-10、FR-11 | 普通 Discussion 消息不创建 Agent task；`POST .../messages` 成功体 `task_id` 为 null。 |
| AC-4 | FR-11、FR-17 | 明确 @mention Coordinator 或 `coordinator_request=analyze\|summarize` 后，task 的 `chat_session_id` 等于请求 session，`issue_id` 为空；`context.chat_config` 已写入。 |
| AC-5 | FR-12 | Agent 回复作为 `chat_message` 出现在同一 `session_id`；该 session 无对应工作 Issue。 |
| AC-6 | FR-4、FR-5、FR-20 | 项目成员 A 发送的 shared 消息对成员 B 可见；用户 B 的 Private Ask 对 A 仍不可见；Private Ask 非创建者调用配置 PATCH 仍 403。 |
| AC-7 | FR-16 | 旧 `project_discussion` Issue 的历史 comment 可只读回放；其后的新 Discussion 消息不出现在该 Issue 的 comment 流中。 |
| AC-8 | FR-3、FR-6 | 并发打开同一项目 Discussion 只产生一行 active `project_shared` session；同一用户在该项目的 Private Ask active session 仍可独立存在（索引谓词收窄后不再冲突）。 |
| AC-9 | FR-8、FR-9 | 非 owner/admin PATCH shared session 配置返回 403 `forbidden_chat_config`；owner/admin PATCH 不调用 `UpdateAgent`，`agent.model` / `agent.thinking_level` 不变。 |
| AC-10 | FR-9、FR-18 | 不支持的 model / Thinking Mode：PATCH 与协办入队返回 400 `invalid_model_or_thinking_level`；已入队 task 的 `chat_config` 不变。命令：`go test ./server/internal/handler/ ./server/pkg/agent/ -count=1`。 |
| AC-11 | FR-11 | 未绑定 Coordinator 时协办请求不创建 task 与 Issue，返回 409 `discussion_coordinator_not_configured`。 |
| AC-12 | FR-14 | 发送前未绑定附件只有上传者可见；其他项目成员下载/列表/消息流均不可见。 |
| AC-13 | FR-15 | 发送成功后附件绑定 `chat_session_id` 与 `chat_message_id`（协办时还有 `task_id`）并对项目成员可见；发送失败时五类绑定仍为空且可重试。 |
| AC-14 | FR-7 | 无 Coordinator 时 GET/普通发送成功；`agent_id` 为空；绑定 Coordinator 后协办可用，解绑后 `agent_id` 回到空且历史消息仍可读。 |
| AC-15 | FR-13、FR-23 | merge-forward 仅 `message_ids` 且消息均属本项目同一 shared session 时，201 且 Team Agent 侧一条合并 comment+task；Discussion 源消息不被移动或删除。仅 `comment_ids` 的旧 Issue 路径与 400 `invalid_comment_selection` 保持原行为。 |
| AC-16 | FR-13 | Coordinator 转投 Team Agent 仍可触发既有发送内核；本 CR diff 不修改 `sendProjectChatCore` 的容器绑定与 `chat_config` 写入语义。KG-1/KG-2 不得被本 CR 的验收当成新缺陷。 |
| AC-17 | FR-19、NFR-8 | `packages/core/api/schemas.test.ts`：Discussion GET 缺/空/非 UUID `session_id` → 硬降级只读；合法 `session_id` 且 `issue_id` 为 null 时可发送。前端不得用 `legacy_issue_id` 调用发送。 |
| AC-18 | FR-19、NFR-2 | DiscussionPane 在有 `session_id` 时不再依赖可写 `issue_id`；新增文案 en/ja/ko/zh-Hans 对称，`parity.test.ts` 全绿。 |
| AC-19 | FR-21、FR-6 | 从 481 起的迁移：无**新增** FK；481 up 使 `agent_id` 可空并把既有约束 `chat_session_agent_id_fkey` 由 `ON DELETE CASCADE` 改为 `ON DELETE SET NULL`（`pg_get_constraintdef` 验证定义）；481 down 恢复 CASCADE + `SET NOT NULL`（迁移 up/down 往返测试全绿）；新增索引均为 `CONCURRENTLY` 且一文件一条；Private Ask 唯一索引谓词已排除 `project_shared`；`CUSTOM.md` 已按当时结构登记本 CR 条目。 |
| AC-20 | FR-17、FR-18 | 当前成员对已归档 shared session 的 PATCH/发送返回 409 `chat_session_closed_or_changed`；错误 kind / 跨项目 / 非成员的 session 路径返回 404 `chat_session_not_found`；不得写入其他项目或其他 kind 的 session。消息列表对已归档 shared session 仍 200。 |
| AC-21 | FR-9、NFR-9 | 配置解析与协办入队的 catalog / waitable / blocked 判定复用 CR-2026-056 单一实现（`ResolveChatConfig` / `LoadChatCatalogForConfig`）；测试不得再复制第二套规则表。 |
| AC-22 | NFR-6、NFR-7 | Team Agent GET 仍不创建 Issue；Private Ask creator-only 夹具全绿；`go test ./server/internal/handler/ ./server/internal/service/ -count=1` 不新增与 Discussion 无关的失败。 |
| AC-23 | FR-22 | `GET .../messages`（shared）无 cursor 时 200 且 body 为分页对象（含 `messages`/`limit`/`has_more`），不是裸数组；`limit=0` 或只给 `before_id` 返回 400 `invalid_cursor`。页内 `created_at` 非递减。 |
| AC-24 | FR-22 | `POST .../messages`：空 content 且无附件、或 `attachment_ids` 含重复 UUID、或非法 `coordinator_request` → 400 `invalid_discussion_message` 且无新 message/task。仅附件、content 为空 → 201 且 `task_id` 为 null。成功状态码为 201。 |
| AC-25 | FR-23 | merge-forward 同时给非空 `comment_ids` 与 `message_ids` → 400 `invalid_merge_forward_selection` 且 Team Agent 侧无新 comment/task。`message_ids` 含他项目 / Private Ask / 另一 session 的 id → 400 `invalid_message_selection`。重复 `message_ids` 只产生一条合并 comment。 |
| AC-26 | FR-24 | Discussion `POST .../messages` 缺 `Idempotency-Key` → 400 `idempotency_key_required` 零写入。同一 key+同一指纹重试（含响应丢失后重放）→ 两次都 201 且 `message_id`/`task_id` 相同，附件不返回 409 `attachment_already_bound`，DB 仍一条 message。同一 key 不同 content → 409 `idempotency_key_reused` 零写入。并发同一 key 只提交一次。 |
| AC-27 | FR-24、FR-23 | `message_ids` merge-forward 缺 `Idempotency-Key` → 400 `idempotency_key_required`。同一 key 重放 → 201 且同一 `comment_id`/`task_id`，Team Agent 侧不新增第二对 comment/task。legacy `comment_ids` 不带该头仍可 201。 |
| AC-28 | FR-25 | 同 workspace 非项目成员：`GET /discussion` 403 `forbidden_project_discussion`；持有 `session_id` 的消息 GET/POST 与 PATCH → 404 `chat_session_not_found`；已发送附件下载 404 且无文件字节。被移出的旧成员即时失去上述能力。 |
| AC-29 | FR-25、FR-20 | 非成员 / 已移出成员订阅 shared session 实时通道被拒绝；移出后服务端退订，后续 shared 消息/task 事件不再投递给该用户。成员 B 仍能收到。夹具：handler 或 realtime 测试，命令 `go test ./server/internal/handler/ ./server/internal/service/ -count=1`。 |
| AC-30 | FR-26 | 首次绑定 Coordinator：settings 与 active session.`agent_id` 同 UUID；若 `base_*` 为空则被补写为该 Agent 当时默认。替换为另一 Agent：session.`agent_id` 更新，`base_*` 不变；已入队 task 的 `agent_id` 与 `chat_config` 不变。解绑：session.`agent_id` 为空，历史消息仍可读。 |
| AC-31 | FR-26、FR-11 | Coordinator Agent 归档后：GET `coordinator_agent_id` 仍为原 UUID；新的 @mention/analyze 返回 409 `discussion_coordinator_unavailable` 且不建 task；settings 不被 GET 清掉。Agent hard-delete 后的完整验收见 AC-32。并发 settings PATCH 与 GET 后 session.`agent_id` 与 settings 一致。 |
| AC-32 | FR-7、FR-21、FR-26 | Coordinator Agent 行 hard-delete 后：`chat_session` 行与历史 `chat_message` 行**全部保留**（FK 置 NULL 不级联删除）；session.`agent_id` 为 NULL（投影置 NULL）；GET `/discussion` 的 `coordinator_agent_id` 仍返回 settings 原 UUID；消息列表 GET 仍 200 且可完整回放删除前的历史；新 @mention/analyze 409 `discussion_coordinator_unavailable` 零写入。删除事务只移除 agent 行并把 session.`agent_id` 置 NULL，不留半成品、不触碰消息与设置。 |

来源文档完成标志要求 AC-16 至 AC-22 全部满足；上表 AC-1 至 AC-7 对应来源这七条，AC-8 至 AC-22 覆盖同一闭环中必须可测、但来源完成标志未逐条编号的规则（索引撞车、可空 agent、错误码、前端降级、依赖复用）；AC-23 至 AC-31 覆盖此前评审轮次 B-HTTP-1/B-HTTP-2/B-IDEMP-1/B-ACL-1/B-COORD-1 关闭的契约闭合，重生成后全部保留；AC-32 覆盖 cycle 1 第 3/3 轮 blocker B-COORD-2 的 hard-delete FK 生命周期与回放验收。

# 6. 成功指标

- 打开 Discussion、发送普通消息、上传附件、请求 Coordinator 产生新工作 Issue（含 `project_discussion`）的次数为 **0**。
- 普通 Discussion 消息创建 Agent task 的比例为 **0**。
- 明确协办任务 **100%** 满足 `chat_session_id` 非空且 `issue_id` 为空。
- 同一项目 active `project_shared` session 数 = **1**，且与 Private Ask active session 可并存。
- 发送前未绑定附件被非上传者读取的次数为 **0**。
- 非当前项目成员成功读取 shared 消息、已发送附件或实时事件的次数为 **0**。
- Private Ask 非创建者成功读取或 PATCH 的次数为 **0**。

# 7. 范围排除

以下内容明确不做，归属后续 CR 或明确非目标：

- 多个长期 Discussion Agent 和 `discussion_participant` 表（来源 CR-B 不包含；AC-29）。
- Discussion 到工作 Issue 或 CR 的显式升级（来源 CR-C；来源 AC-23 至 AC-27）。
- 历史 `project_discussion` 全量迁移到 `chat_message`。
- Team Agent 的配置和发送内核（来源 CR-A 已交付；本 CR 只做 Discussion 侧转投入参适配）。
- CR-2026-056 KG-1 / KG-2。
- 发送框整体视觉重构、对齐普通非项目聊天 composer（来源 CR-D）。
- 多个 active Team Agent 主题或完整 thread 列表。
- 给 `agent_task_queue` 增加模型和 Thinking Mode 专用列。
- 把 `/compact` 作为普通用户消息发送。
- 在 Multica 服务端复制 CR 状态机或直接写 knowledge-base 的 `_backlog.yml`。
- 自定义 promotion 表；复制一套独立 Discussion 消息表。
- mobile 端。
- `../tools/` 仓改动。
