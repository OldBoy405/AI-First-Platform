---
id: CR-2026-061-prd
type: PRD
cr-ref: CR-2026-061
title: Discussion 显式升级
target-version: 0.34
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-07T12:00:41+08:00
updated: 2026-09-07T14:32:14+08:00
---

# 1. 概述

## 1.1 问题陈述

CR-2026-059（CR-B）已把 Discussion 改为项目级 shared `chat_session` / `chat_message`，打开、发送、附件、Coordinator 协办均不再创建隐藏 Issue。但 Discussion 目前没有任何「把讨论内容变成正式工作」的出口：

- 没有「转为工作 Issue」端点或前端入口；用户要把讨论内容落成工作项只能手工开 Issue 并手工复制内容。
- 即使将来人工复制，目标 Issue 与来源 session / 消息 / 附件之间没有任何引用关系，无法回溯。
- 没有幂等保障：同一批消息被两次升级会创建两个重复 Issue；网络重试语义未定义。
- 「升级为 CR」路径不存在：来源文档 §10.2 要求升级只准备来源上下文并进入现有 `requirement-register`，Multica 不得写 CR 账本——目前该边界没有代码约束，也没有触发入口。
- `issue.context_refs`（`001_init.up.sql`：`JSONB NOT NULL DEFAULT '[]'`）在响应中已读出（`handler/issue.go`），但全仓没有结构化写入路径，前端 schema 也未暴露。

以上事实已在来源文档 §10 / §14 记录，并在本 CR 落笔前按 multica trunk `b5bf30ca`（CR-2026-059 已合入、AIFI-21 已合入）复核（见 §1.4）。本 CR 只做 Discussion → 工作 Issue 的显式升级与来源追溯，不改 CR-B 已交付的 Discussion 会话内核，不自动升级，不迁移历史。

## 1.2 解决方案摘要

在 Discussion 上增加唯一的显式升级出口：

```text
Discussion shared session
  -> 用户选择消息和附件
  -> 显式点击「转为工作 Issue」
  -> 创建正式 Issue + 写入来源引用（issue.context_refs）
  -> 重复升级 / 重试返回同一个目标 Issue
  -> 原 Discussion 消息与附件保持原归属，不移动、不删除、不复制

「升级为 CR」
  -> 先得到目标 Issue + 来源上下文
  -> 触发现有 requirement-authoring 流程（CreatePipelineTask 携带 Issue 上下文）
  -> CR 注册与状态机仍由 knowledge-base 的 requirement-register 完成
  -> Multica 不写 CR 账本、不复制状态机
```

本 CR（来源文档 CR-C，注册摘要已拍板）交付一个可独立验收的闭环：

1. 只有用户显式执行升级操作才创建正式工作 Issue；打开、发送、附件、协办均不得创建（FR-22）。
2. 升级请求携带所选消息与附件，服务端校验它们同属当前项目 active shared session。
3. 创建正式 Issue，并把规范化来源集合写入 `issue.context_refs`；原消息与附件归属不变（FR-23）。
4. 以「规范化来源集合 + 项目级并发锁 + 幂等记录」保证同一来源集合只产生一个工作 Issue；重试返回已创建的目标 Issue（FR-24）。
5. 工作 Issue 可回溯来源 session、消息与附件。
6. 「升级为 CR」只准备来源上下文并进入现有 `requirement-register` 流程；Multica 不写 `_backlog.yml` 等 CR 账本（FR-25 / AC-27）。
7. 一期不新增 `discussion_promotion` 表，除非实现验证表明现有 `context_refs` 与并发锁无法满足幂等与审计（来源文档 §10.1）。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

提供 Discussion 到正式工作 Issue 的显式升级出口：用户选择消息和附件并显式执行「转为工作 Issue」后创建正式 Issue，保存来源 session/消息/附件引用，原消息与附件保持原归属；以规范化来源集合与项目级并发锁保证重复升级不产生重复 Issue，重试返回既有目标 Issue。「升级为 CR」只准备来源上下文并进入现有 requirement-register 流程，Multica 不写 CR 账本。

不含自动升级、原消息/附件移动删除或静默复制、Discussion 多主题与多 Agent 参与者模型、新增 `discussion_promotion` 表（除非验证表明现有引用与锁不足）。依赖已归档 CR-2026-059 的 shared Discussion session、消息与附件来源，以及现有 Issue 创建能力和 knowledge-base 的 `requirement-register` 流程。

目标仓库为 sibling `../multica/`。knowledge-base 承载本 PRD 与来源文档；`../tools/` 无实施改动。

`target-version` 继承 `cr.md` 的 `0.34`（注册阶段已确定），本文件不得改写该字段。`target-spec-id` 为 `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

## 1.4 当前代码事实（落笔前核实）

基线：multica trunk `b5bf30ca32d13f0001149cf6b38cd21f5876b53d`（含 CR-2026-059 Discussion shared session 与 AIFI-21 熔断；本 CR 的 multica requirement worktree 已同步至该 SHA）。以下结论均在该 SHA 上核实。

| 结论 | 证据 |
|---|---|
| Discussion 已是 shared session，不再懒创建隐藏 Issue | `handler/project_chat.go` `GetProjectDiscussion`（L233）；服务层注释「EnsureProjectDiscussionIssue is no longer called from this path」（L231） |
| `chat_session.kind` 已交付 | `server/migrations/482_chat_session_kind.up.sql`：`ADD COLUMN kind TEXT NOT NULL DEFAULT 'private'`（CR-2026-059 TASK-01） |
| Discussion 消息为 `chat_message`，附件可绑 session/message/task | `033_chat.up.sql`（`chat_message` 表）；`083_attachment_chat_columns.up.sql`；`164_attachment_task_id.up.sql` |
| `issue.context_refs` 存在但无写入路径 | `001_init.up.sql` L67：`context_refs JSONB NOT NULL DEFAULT '[]'`；`handler/issue.go`（L877/L968 读出）；`pkg/db/queries/issue.sql` 无 context_refs 写入语句；前端 `packages/core/api/schemas.ts` 无对应字段 |
| Idempotency-Key 基础设施已存在 | `server/pkg/publicapi/v1/foundation.go`：`HeaderIdempotencyKey = "Idempotency-Key"`、`MaxIdempotencyBytes = 255`；CR-B 幂等表 `487-490_chat_idempotency*`（scope 枚举 `discussion_message`/`merge_forward_messages`，含 `response_status`/`response_body` 回放能力） |
| 项目级 advisory lock 先例已存在 | `service/project_chat.go` `ensureContainerIssueLocked` 经 `qtx.LockIssueDuplicateKey(ctx, lockKey)`（L110-111），锁键 `prefix|workspace|project` |
| 旧 `project_discussion` Issue 保留只读 | `service/project_chat.go` `EnsureProjectDiscussionIssue`（L58）仍在，仅供历史容器路径；新路径不调用（L231） |
| 前端 Discussion 面板已走 shared session | `packages/views/projects/components/discussion-pane.tsx`（CR-B 交付，携带 `session_id` 渲染分页消息） |
| 平台已有 pipeline 任务创建与 CR 绑定能力 | `service/task.go` `CreatePipelineTask`（L410，创建 pipeline task 并原子写入可信来源上下文）；`handler/cr_bind.go` `HandleBindCurrentTask`（`POST /api/crs/{crID}/bind-current-task`）；`gate_nodes_gen.go` 已注册 `requirement-authoring` 节点（含 human_approval 节点） |
| pipeline 任务唯一性 guard 先例 | `443_agent_task_pipeline_node_active_unique.up.sql`：`agent_task_queue(pipeline_node_run_id)` 部分唯一索引（active 状态仅一条）；`437_aifirst_pipeline_runs.up.sql`：`pipeline_run`/`pipeline_node_run` 表（`UNIQUE (run_id, node_id, attempt)`） |
| `chat_idempotency` 幂等键作用域 | `488_chat_idempotency_scope_key_unique.up.sql`：唯一键 `(workspace_id, user_id, scope_type, scope_id, key)`；`487_chat_idempotency.up.sql`：`scope_type` CHECK 仅 `('discussion_message','merge_forward_messages')`——本 CR 新增 `discussion_promotion` scope 需扩展该 CHECK（迁移号 ≥ 491） |
| 固定错误体 `{code, error}` 与 502 先例 | `handler/project_chat.go` `writeErrorCode`（固定 code+error 字段）；`writeProjectChatSendError` 默认分支：事务已整体回滚后统一 502 `enqueue_failed` |
| CR-B 项目路径成员门禁口径 | `handler/project_chat.go` `GetProjectDiscussion`（L233）成员门禁（SDD §3.1/FR-25）：项目路径（project 存在性已确认）非成员返回 **403** `forbidden_project_discussion`；**404 `chat_session_not_found` 只用于 session 级失败**（不存在/跨项目/归档） |
| 当前最大迁移编号 | **490**（`490_idx_chat_idempotency_created.up.sql`） |
| CR 注册与状态机在 knowledge-base，不在 Multica | KB `dir-graph.yaml#repositories`；`../tools/` 的 `requirement-register` Skill 经 `crctl register` 深原语写 `change-requests/`；Multica 无该账本写入路径 |

## 1.5 修订记录

- 初稿（2026-09-07）：按来源文档 CR-C 段与注册摘要起草，代码事实在 multica trunk `b5bf30ca` 核实。
- v0.2（2026-09-07）：按 review-requirement 第 1 轮 BLOCK（B-API-01~04）定点修复：①按分支拆分默认/`upgrade_to_cr=true` 条件副作用，明确 pipeline task 输入/响应、同事务边界、失败 502 零残留与唯一 task 语义（FR-10、契约、AC-8）；②定义 canonical fingerprint 算法、key 作用域与输入限制，确定 key 冲突优先于来源查重的确定性规则（FR-6/FR-7、契约、AC-5）；③权限判定固定为四步顺序，成员缺失唯一 403、session 级失败唯一 404，AC-6 与之一致（FR-8）；④补齐逐类错误闭包表（状态/固定 code/错误体/零写入范围/客户端动作）（FR-3/FR-13、契约、AC-2/AC-11）。

# 2. 用户故事

- **US-1 讨论参与者**：作为项目成员，我希望选中讨论里的一段消息和附件后点「转为工作 Issue」，就能得到一个可执行的工作项，而不是手工复制粘贴。
- **US-2 讨论参与者**：作为项目成员，我希望升级后的 Issue 上能看到它来自哪次讨论、哪些消息、哪些附件，审计时有据可查。
- **US-3 讨论参与者**：作为项目成员，我希望重复点击升级或网络重试不会产生一堆重复 Issue，返回的始终是同一个目标 Issue。
- **US-4 原消息读者**：作为项目成员，我希望升级动作不搬走、不删掉、不复制我在 Discussion 里的消息和附件，它们还留在原处。
- **US-5 项目 owner/admin**：作为项目负责人，我希望「升级为 CR」走现有 requirement 流程，Multica 服务端不会越过边界直接去改知识库的 CR 账本。
- **US-6 未授权成员**：作为没有 Issue 创建权限的成员，我希望能看到讨论，但升级入口对我关闭或返回明确错误，不会悄悄越权创建。

# 3. 功能需求

## FR-1 只有显式升级才创建工作 Issue

打开 Discussion、发送普通消息、上传附件、请求 Coordinator 协办、读取消息列表，均不得创建任何工作 Issue（含 `origin_type='project_discussion'` 的历史容器）。唯一创建正式工作 Issue 的路径是用户显式执行「转为工作 Issue」。来源 FR-22、AC-23。

## FR-2 升级入口契约

新增 `POST /api/projects/{projectId}/discussion/promote`。完整 HTTP 契约见下节「Discussion promotion HTTP 契约」。创建正式 Issue 使用现有 Issue 创建能力，禁止为升级另建一套 Issue 写入路径。

## FR-3 来源选择校验

请求体 `message_ids` 与 `attachment_ids` 必须满足：均为 UUID 字符串数组（元素非 UUID 或类型非字符串数组即拒绝）；至少一个 message 或一个 attachment（两数组同时为空即拒绝）；无重复 UUID；全部消息属于当前项目唯一的 active `project_shared` session（即 Discussion GET 返回的 `session_id`）；全部附件已绑定到该 session 的 `chat_message`（发送成功后的附件，不是未绑定草稿）。以上任一失败返回 400 `invalid_promotion_selection`，零写入。`session_id` 缺失/非 UUID 返回 400 `invalid_promotion_selection`；`title` 非字符串或超 200 字符返回 400 `invalid_promotion_title`；`description` 非字符串或超 10,000 字符返回 400 `invalid_promotion_description`。来源 §10.1。错误码、错误体与客户端动作的完整映射见 HTTP 契约「错误闭包」表。

## FR-4 创建 Issue 并写入来源引用

校验通过后创建正式 Issue，并把规范化来源集合写入 `issue.context_refs`（JSONB 数组，条目至少含 `session_id`、`message_ids[]`、`attachment_ids[]`、`promoted_by`、`promoted_at`）。`message_ids`/`attachment_ids` 为排序去重后的 UUID 列表。`upgrade_to_cr=true` 且 pipeline task 创建成功后，条目额外回写 `pipeline_task_id`（同一事务，FR-10）。目标 Issue 的标题、描述可由用户提供；未提供时服务端生成默认值（标题含项目名与升级时间，描述含来源消息摘要）。来源 FR-23、AC-26。

## FR-5 原 Discussion 消息与附件保持原归属

升级不得移动、删除、复制或改绑原 `chat_message` 与附件；附件仍绑定原 `chat_session_id`/`chat_message_id`；Discussion 消息流与附件列表不因升级发生变化。来源 FR-23、AC-24。

## FR-6 幂等：同一来源集合只产生一个工作 Issue

以规范化来源集合作为查重键：`session_id`（小写 UUID 规范形式）+ 排序去重后的 `message_ids` + 排序去重后的 `attachment_ids`。服务端在项目级并发锁下先查后建：已存在以该来源集合升级的目标 Issue 时直接返回它（`created=false`），不创建新 Issue、不覆盖既有 Issue 的 `title`/`description`（这两个字段只在首次创建时生效，不参与指纹与查重）。并发同源升级必须收敛到同一目标 Issue。来源 FR-24、AC-25。

**判定优先级（确定性规则）**：在项目级并发锁内，同 key 指纹冲突检查（FR-7，409）先于来源查重命中（本 FR，返回既有 Issue）；两者都不命中才创建。组合规则（含 `upgrade_to_cr`）见 HTTP 契约「幂等与查重优先级」表。

## FR-7 幂等键：canonical fingerprint 与重放语义

**指纹算法（canonical fingerprint）**：对请求做规范化后取 SHA-256：`projectId`、`session_id` 统一为小写 UUID 字符串；`message_ids`/`attachment_ids` 排序去重；`upgrade_to_cr` 规范为布尔值（缺省 false）。按固定键序 JSON 序列化后计算：

```text
fingerprint = SHA256(hex) of canonical JSON:
{"projectId":"<小写>","session_id":"<小写>","message_ids":[排序去重小写],"attachment_ids":[排序去重小写],"upgrade_to_cr":true|false}
```

`title`/`description` **不参与指纹**：同一来源集合不同标题/描述不构成指纹差异，也不构成查重差异（见 FR-6），标题/描述只在首次创建时生效。

**key 作用域**：`Idempotency-Key` 的作用域为 `(workspace_id, user_id, scope_type='discussion_promotion', scope_id=project_id, key)`，复用 CR-B `chat_idempotency` 表（新增 `discussion_promotion` scope，需扩展 scope CHECK 约束，迁移号 ≥ 491）。同一 key 在不同项目、不同调用者之间互不影响。

**key 输入限制**：必填、非空、≤ 255 字节（`pkg/publicapi/v1/foundation.go` `MaxIdempotencyBytes`）。缺失返回 400 `idempotency_key_required`；空串/纯空白/超 255 字节返回 400 `invalid_idempotency_key`。

**重放语义**：同 key + 同指纹重放（含响应丢失后重试）→ 201 且回放首次响应（`created=false`，`upgrade_to_cr=true` 时回放首次返回的 `pipeline_task_id`，不新建 task）；同 key + 不同指纹 → 409 `idempotency_key_reused`，零写入（优先级先于 FR-6 查重）。同源不同 key 的重试经 FR-6 的查重返回同一目标 Issue；若先普通升级（`upgrade_to_cr=false`）后以新 key 再发 `upgrade_to_cr=true`，返回同一目标 Issue 并只补建一次 pipeline task（FR-10）。

## FR-8 权限边界（固定判定顺序）

权限相关判定按下列固定顺序执行，每一步失败即返回、零写入，前面步骤不依赖后面步骤的结果（因此同输入只产生唯一响应）：

1. **项目解析**：`projectId` 非 UUID → 400 `invalid_project_id`；UUID 合法但 workspace 内无此项目 → 404 `project_not_found`。
2. **成员门禁**：非 workspace 成员 / 已被移出 workspace → 403 `forbidden_promotion`（项目路径口径：project 存在性已在第 1 步确认，与 CR-B `GetProjectDiscussion` 成员门禁 403 保持一致；不向非成员透露 session 存在性）。
3. **Issue 创建权限**：workspace 成员但不具备现有 Issue 创建权限（沿用现有 Issue 权限口径，不新造权限模型）→ 403 `forbidden_promotion`。
4. **session 解析**：session 不存在 / 不属于本 project / `kind` 非 `project_shared` / 已归档或非 active → 404 `chat_session_not_found`（口径与 CR-B session 路径一致；仅 session 级失败用 404）。

以上 1–4 步全部零写入。发起升级不要求 Coordinator 或 Agent 配置；纯人类 Discussion 同样可升级（FR-11）。

## FR-9 工作 Issue 可回溯来源

目标 Issue 详情与 API 响应可读到来源 `session_id`、消息与附件引用（经 `context_refs` 解析），前端在 Issue 详情页展示「来自 Discussion 升级」的来源入口，可跳转回 Discussion 定位消息。来源 AC-26。

## FR-10 升级为 CR：只准备上下文，不写 CR 账本

「升级为 CR」复用 FR-2 的 promotion 得到目标 Issue 与来源上下文，随后触发现有 requirement 流程：以目标 Issue 为来源上下文创建 `requirement-authoring` pipeline task（复用 `CreatePipelineTask` 与 CR-2026-053 FR-B12 的 Issue 上下文继承）。CR 注册（`crctl register` / `requirement-register`）与状态机仍在 knowledge-base 由 requirement 流程完成。Multica 服务端代码不得读写 knowledge-base `_backlog.yml` / `_history.yml` / `cr.md`，不得复制 CR 状态机与门禁。来源 FR-25、AC-27。

**条件副作用与事务边界（`upgrade_to_cr=true` 分支）**：

- pipeline task 行（`pipeline_run` + `pipeline_node_run` + `agent_task_queue`）与目标 Issue、`context_refs`、幂等记录在**同一 DB 事务**内写入；task 入队/事件通知（`issue:created`、`EventTaskQueued` 等）在**事务提交后**按现有事件模式发出，提交前不得泄漏。
- pipeline task 创建失败（含 task 上下文校验失败、attribution guard 失败、DB/入队失败）→ **整个事务回滚** → 502 `pipeline_task_create_failed`，**零残留**（无 Issue、无 `context_refs`、无幂等记录、无 task 行）；客户端动作：以同一 key 整体重试（FR-7 幂等安全）。
- **唯一的 task 语义**：每个目标 Issue 至多创建一个 `requirement-authoring` pipeline task。同 key 同指纹重放回放首次返回的 `pipeline_task_id`；同源不同 key 的请求在锁内查重命中后：既有 `context_refs` 条目已含 `pipeline_task_id` → 直接返回该值；未含（先普通升级后升级为 CR）→ 在同一事务内补建一次并回写 `pipeline_task_id`。并发同源升级为 CR 在项目级锁下串行化，第二个请求只会拿到已存在的 task，不建第二个。
- promotion 的 HTTP 响应额外携带 `pipeline_task_id`；CR 注册结果不在本端点返回（异步由 requirement 流程产出），Multica 不轮询也不写 CR 账本。

## FR-11 前端交互

`discussion-pane.tsx` 提供多选消息与附件的交互，以及「转为工作 Issue」「升级为 CR」两个显式操作入口（样式复用现有 Discussion 面板与 Issue 创建弹层，不新造组件体系）。升级成功后展示目标 Issue 链接并保留 Discussion 内容不变；失败时保留选择状态并展示错误，可重试。未配置 Coordinator、纯人类 Discussion 同样可用升级入口。

## FR-12 不新增 `discussion_promotion` 表（默认）

一期默认复用 `issue.context_refs` + 项目级并发锁 + 幂等记录实现 FR-6/FR-7 的查重与审计。仅当实现验证（可复现的并发/查询测试）表明现有机制无法可靠满足「同源唯一」与「审计可查」时，才允许引入最小 `discussion_promotion` 表，且必须在 SDD 中附验证证据说明为何 context_refs 不足。来源文档 §10.1。

## FR-13 可区分错误与零残留

升级请求失败（校验失败、权限失败、key 冲突、并发/锁/数据库/事务失败、pipeline task 创建失败）不得留下半成品 Issue、半写 `context_refs`、半绑定附件或孤立幂等记录。错误体固定为 `{ "code", "error" }`（复用 CR-B `writeErrorCode` 形状），逐类错误的 HTTP 状态、固定 code、零写入范围与客户端动作见 HTTP 契约「错误闭包」表；前端按该表可区分并给出正确恢复动作（保留选择 / 换 key / 原 key 直接重试）。500 `internal_error` 与 502 `pipeline_task_create_failed` 均为可安全重试错误（幂等语义保证重试不产生重复 Issue 或重复 pipeline task）。

## Discussion promotion HTTP 契约（可执行，覆盖 FR-2 / FR-3 / FR-4 / FR-6 / FR-7 / FR-8 / FR-10 / FR-13）

```text
POST /api/projects/{projectId}/discussion/promote
```

### 请求

| 字段 | 类型 | 约束 |
|---|---|---|
| `projectId`（path） | UUID | 非 UUID → 400 `invalid_project_id`；合法但 workspace 无此项目 → 404 `project_not_found` |
| `Idempotency-Key`（header） | string | 必填、非空、≤ 255 字节；缺失 → 400 `idempotency_key_required`；空/纯空白/超长 → 400 `invalid_idempotency_key` |
| `session_id` | UUID | 必填；缺失/非 UUID → 400 `invalid_promotion_selection` |
| `message_ids` | UUID 字符串数组 | 可空；元素非 UUID 字符串或类型非数组 → 400 `invalid_promotion_selection` |
| `attachment_ids` | UUID 字符串数组 | 可空；元素非 UUID 字符串或类型非数组 → 400 `invalid_promotion_selection` |
| `title` | string | 可选；非字符串或超 200 字符 → 400 `invalid_promotion_title` |
| `description` | string | 可选；非字符串或超 10,000 字符 → 400 `invalid_promotion_description` |
| `upgrade_to_cr` | bool | 可选，默认 false；类型错误 → 400 `invalid_request_body` |

`message_ids` 与 `attachment_ids` 不得同时为空、不得含重复 UUID（均 400 `invalid_promotion_selection`）。非法 JSON / 请求体无法解析 → 400 `invalid_request_body`。所有 400/403/404/409 均零写入。

### canonical fingerprint（FR-7）

```text
fingerprint = SHA256(hex) of canonical JSON（固定键序）:
{"projectId":"<小写 UUID>","session_id":"<小写 UUID>","message_ids":[排序去重的小写 UUID],"attachment_ids":[排序去重的小写 UUID],"upgrade_to_cr":<true|false>}
```

`title`/`description` 不参与指纹（只影响首次创建，见 FR-6）。key 作用域：`(workspace_id, user_id, scope_type='discussion_promotion', scope_id=project_id, key)`。

### 判定顺序（固定，所有校验零写入，仅最终创建步骤落盘）

1. 请求形态校验（400 类：request 表 + FR-3 形状项）。
2. project 解析（400 `invalid_project_id` / 404 `project_not_found`）。
3. 成员门禁（403 `forbidden_promotion`）。
4. Issue 创建权限（403 `forbidden_promotion`）。
5. session 解析（404 `chat_session_not_found`：不存在 / 跨项目 / 非 `project_shared` / 已归档或非 active）。
6. 来源选择校验（FR-3：400 `invalid_promotion_selection`）。
7. 获取项目级 advisory lock（`prefix|workspace|project`，先例 `projectChatSessionAdvisoryKey`）；锁内：
   1. key 冲突检查（FR-7）：同 key 同指纹 → 回放首次响应（201，`created=false`）；同 key 不同指纹 → 409 `idempotency_key_reused`（**优先级先于查重**）。
   2. 来源查重（FR-6）：同源命中 → 返回既有 Issue（`created=false`）；`upgrade_to_cr=true` 时按 FR-10 补建/复用唯一的 pipeline task。
   3. 均未命中 → 创建 Issue + `context_refs` + 幂等记录（`upgrade_to_cr=true` 另含 pipeline task 行），同一事务提交。

### 成功响应（201）

```json
{
  "issue_id": "<UUID>",
  "issue_number": 123,
  "session_id": "<UUID>",
  "source_refs": { "session_id": "<UUID>", "message_ids": ["<UUID>"], "attachment_ids": ["<UUID>"] },
  "created": true,
  "upgrade_to_cr": false,
  "pipeline_task_id": null
}
```

- `created=false`：重放或查重命中。重放回放的响应与首次一致（`issue_id`/`source_refs`/`pipeline_task_id` 同首次），但 `created` 恒为 false（表示本次请求未新建）。
- `upgrade_to_cr=true` 且 pipeline task 已创建/已存在时，`pipeline_task_id` 为任务 UUID，否则为 null（FR-10）。

### 副作用（按分支拆分，FR-10）

| 分支 | 副作用 | 禁止 |
|---|---|---|
| 默认（`upgrade_to_cr=false`） | 同一事务内：新增 Issue 行 + 写入 `context_refs` + 幂等记录 | 不得创建 comment / task；不得修改 `chat_message`、`attachment`、`chat_session` 行 |
| `upgrade_to_cr=true` | 默认分支全部副作用 + 每个目标 Issue 至多一个 `requirement-authoring` pipeline task（`pipeline_run`/`pipeline_node_run`/`agent_task_queue` 行同事务写入，入队/事件通知在提交后发出） | 同上；不得写 knowledge-base CR 账本；task 创建失败 → 事务整体回滚 → 502 `pipeline_task_create_failed` 零残留 |

### 幂等与查重优先级（确定性规则）

| 场景 | 结果 |
|---|---|
| 同 key + 同指纹重放 | 201 回放首次响应（`created=false`）；`upgrade_to_cr=true` 回放首次 `pipeline_task_id`，不新建 task |
| 同 key + 不同指纹（含先普通升级后同 key 再 `upgrade_to_cr=true`；指纹含 `upgrade_to_cr`，必不同） | 409 `idempotency_key_reused`，零写入 |
| 同源不同 key，串行/并发 | 201 返回既有 Issue（`created=false`）；`title`/`description` 不覆盖首次值 |
| 同源不同 key，先普通升级、后 `upgrade_to_cr=true` | 返回同一 Issue；锁内查重命中且 `context_refs` 无 `pipeline_task_id` → 同一事务补建一次 task 并回写；已有 → 返回既有值。**至多一个 pipeline task** |
| 同源不同 key 并发 `upgrade_to_cr=true` | 项目级锁串行化：第二个请求拿到的 `pipeline_task_id` 与第一个相同 |

### 错误闭包（逐类：状态 / 固定 code / 错误体 / 零写入范围 / 客户端动作）

错误体统一 `{ "code": "<固定 code>", "error": "<人读文案>" }`。

| 场景 | HTTP | code | 零写入范围 | 客户端动作 |
|---|---|---|---|---|
| 非法 JSON / 请求体无法解析 / `upgrade_to_cr` 类型错误 | 400 | `invalid_request_body` | 全部 | 保留选择，修正后重试 |
| `projectId` 非 UUID | 400 | `invalid_project_id` | 全部 | 停止（调用方 bug） |
| project 不存在 | 404 | `project_not_found` | 全部 | 停止 |
| `session_id` 缺失/非 UUID、数组元素非法、两数组同空、含重复 UUID | 400 | `invalid_promotion_selection` | 全部 | 保留选择，修正后重试 |
| `title` 非字符串/超 200 字符 | 400 | `invalid_promotion_title` | 全部 | 保留选择，修正标题后重试 |
| `description` 非字符串/超 10,000 字符 | 400 | `invalid_promotion_description` | 全部 | 保留选择，修正后重试 |
| `Idempotency-Key` 缺失 | 400 | `idempotency_key_required` | 全部 | 带 key 重试 |
| `Idempotency-Key` 空/纯空白/超 255 字节 | 400 | `invalid_idempotency_key` | 全部 | 换合法 key 重试 |
| 非 workspace 成员 / 已被移出 | 403 | `forbidden_promotion` | 全部 | 展示无权限，不重试 |
| 成员但无 Issue 创建权限 | 403 | `forbidden_promotion` | 全部 | 展示无权限，不重试 |
| session 不存在 / 跨项目 / 非 `project_shared` / 已归档 | 404 | `chat_session_not_found` | 全部 | 刷新 Discussion 后重选 |
| 消息不属于该 session / 附件未绑定该 session 消息（含草稿附件） | 400 | `invalid_promotion_selection` | 全部 | 保留选择，移除非法项后重试 |
| 同 key 不同指纹 | 409 | `idempotency_key_reused` | 全部 | 换新 key 重发（同源由查重收敛） |
| 锁/数据库/事务失败（死锁、超时、连接失败等） | 500 | `internal_error` | 全部（事务回滚） | 原 key 直接重试（幂等安全） |
| `upgrade_to_cr=true` 且 pipeline task 创建失败 | 502 | `pipeline_task_create_failed` | 全部（事务回滚） | 原 key 直接重试（幂等安全，不会产生重复 Issue/task） |
| 其它未预期内部错误 | 500 | `internal_error` | 全部 | 原 key 直接重试 |

状态码总集：201（创建/幂等命中）；400/403/404/409/500/502 如上表；**200 不用于本端点**。

### 验收观察点

- DB：目标 Issue 行 + `context_refs` 含规范化来源集合；Discussion 消息/附件行数与绑定字段升级前后全等。
- 同一来源集合两次升级 Issue 行数只增 1；`chat_idempotency` 存在 `scope_type='discussion_promotion'` 记录且指纹为 canonical fingerprint。
- `upgrade_to_cr=true`：同一目标 Issue 对应的 `pipeline_node_run`/active task 至多 1 条；重放与查重命中均返回相同 `pipeline_task_id`。
- 错误注入夹具：任一类失败后 Issue 表、`context_refs`、`chat_idempotency`、`pipeline_node_run`/`agent_task_queue` 均零残留。

# 4. 非功能需求

- **NFR-1 双端一致**：web 与 desktop 共享 `packages/views` 行为一致；mobile 不在本 CR 范围。
- **NFR-2 四语文案**：新增 UI 文案提供 en/ja/ko/zh-Hans；`packages/views/locales/parity.test.ts` 对新增 key 全绿。
- **NFR-3 复用优先**：复用 `issue.context_refs`、CR-B 的幂等记录模式与 advisory lock 先例、现有 Issue 创建能力与 `CreatePipelineTask`；不复制 Discussion 消息表，不新造 Issue 写入路径，默认不新增 `discussion_promotion` 表（FR-12）。
- **NFR-4 并发与事务**：同源并发升级在项目级锁（`prefix|workspace|project`）下收敛到一次创建；升级事务失败零残留（FR-13）；幂等记录、Issue 创建、`context_refs` 与 `upgrade_to_cr=true` 的 pipeline task 行（`pipeline_run`/`pipeline_node_run`/`agent_task_queue`）**同一事务提交**，提交后广播 `issue:created` 与任务入队等事件，提交前不得泄漏；事件广播失败不回滚已提交数据。
- **NFR-5 安全**：权限校验服务端强制；不得凭 `session_id` 猜测跨项目读取或升级；`context_refs` 只写入可信来源集合，不接受任意 JSON 注入（由服务端生成，前端不能直接提交任意 `context_refs` 内容）。
- **NFR-6 兼容**：旧 `project_discussion` Issue 仍只读回放；CR-B 的 Discussion GET/发送/协办行为除本 CR 明确新增的 promotion 入口外不得改变；Private Ask / Team Agent 路径不受影响。
- **NFR-7 依赖**：必须使用已归档 CR-2026-059 的 shared session、消息与附件来源事实；「升级为 CR」必须走现有 `requirement-authoring` 流程入口，禁止平行实现。

# 5. 验收标准

| ID | 覆盖 FR | 可执行验收 |
|---|---|---|
| AC-1 | FR-1 | 打开 Discussion、发送普通消息、上传附件、请求 Coordinator 后，Issue 表均无新增工作 Issue；只有 promotion 端点成功时才新增。命令：`go test ./server/internal/handler/ ./server/internal/service/ -count=1`。 |
| AC-2 | FR-2、FR-3 | 只选消息、只选附件、消息+附件混合，均 201 且目标 Issue 创建；空选择、含重复 UUID、含未绑定草稿附件、含他项目/Private Ask/另一 session 消息 → 400 `invalid_promotion_selection` 零写入；非法 JSON → 400 `invalid_request_body`；`projectId` 非 UUID → 400 `invalid_project_id`；`session_id` 非 UUID → 400 `invalid_promotion_selection`；`title` 超 200 字符 → 400 `invalid_promotion_title`；`description` 超 10,000 字符 → 400 `invalid_promotion_description`，均零写入。 |
| AC-3 | FR-4 | 目标 Issue 的 `context_refs` 含 `session_id`、排序去重的 `message_ids[]`/`attachment_ids[]`、`promoted_by`/`promoted_at`；未提供 title 时服务端生成默认标题与描述摘要。 |
| AC-4 | FR-5 | 升级前后 `chat_message` 行数、内容、`attachment` 绑定字段（`chat_session_id`/`chat_message_id`）全等；Discussion 消息流与附件列表渲染不变。 |
| AC-5 | FR-6、FR-7 | 同一来源集合串行升级两次：第二次不创建新 Issue，返回与第一次相同的 `issue_id`；同 key+同指纹重放返回同一 Issue 且 `created=false`；同 key 不同指纹 → 409 `idempotency_key_reused` 零写入；同 key 先普通升级（`upgrade_to_cr=false`）后同 key 再发 `upgrade_to_cr=true` → 409 `idempotency_key_reused`（指纹含 `upgrade_to_cr`，必不同）；换新 key 重发 `upgrade_to_cr=true` → 返回同一 Issue 且至多补建一个 pipeline task；缺 `Idempotency-Key` → 400 `idempotency_key_required`；空 key/超 255 字节 → 400 `invalid_idempotency_key`。并发同源升级只产生一个 Issue（handler/service 测试夹具）。 |
| AC-6 | FR-8 | 固定判定顺序，同输入唯一响应：非 workspace 成员 / 已被移出 workspace 升级 → 403 `forbidden_promotion`（唯一，不泄漏 session 存在性）；无 Issue 创建权限成员 → 403 `forbidden_promotion`；session 不存在/跨项目/非 `project_shared`/已归档 → 404 `chat_session_not_found`；project 不存在 → 404 `project_not_found`；以上均零写入。 |
| AC-7 | FR-9 | 目标 Issue API 响应可解析出来源 `session_id` 与消息/附件引用；前端 Issue 详情展示「来自 Discussion」来源入口，点击可跳回 Discussion。 |
| AC-8 | FR-10 | `upgrade_to_cr=true`：promotion 成功后创建 `requirement-authoring` pipeline task，任务上下文携带目标 Issue 与来源上下文；同一目标 Issue 至多一个 pipeline task（同 key 重放返回同一 `pipeline_task_id`；同源不同 key 第二次升级为 CR 不新建）；pipeline task 创建失败注入夹具 → 502 `pipeline_task_create_failed` 且 Issue/`context_refs`/幂等记录/task 行零残留，原 key 重试成功且不产生重复；Multica 代码库无对 knowledge-base `_backlog.yml` / `cr.md` 的写入调用（grep 验证零命中）；后续 CR 注册仍在 knowledge-base 经 `crctl register` 完成。 |
| AC-9 | FR-11 | DiscussionPane 可选择消息与附件并触发两个升级入口；未配置 Coordinator 的纯人类 Discussion 同样可升级；升级成功后目标 Issue 链接可见、Discussion 内容不变；失败时选择保留并可重试。 |
| AC-10 | FR-12 | 一期交付不新增 `discussion_promotion` 表（`server/migrations/` 无该命名迁移）；若 SDD 附验证证据证明 `context_refs` 不足，则该证据与 reviewer 裁决记录在案后方可引入。 |
| AC-11 | FR-13、NFR-4 | 逐类失败夹具（400/403/404/409/500/502 各代表项）下，失败不留下半成品 Issue / 半写 `context_refs` / 孤立幂等记录 / 孤立 pipeline task 行；错误体含固定 `code`（断言「错误闭包」表逐条映射，code 与状态一一对应）；500/502 后以原 key 重试成功且 Issue 数/pipeline task 数不增加；前端按错误类型保留选择或提示重试。 |
| AC-12 | NFR-2、NFR-6 | 新增文案 en/ja/ko/zh-Hans 对称，`parity.test.ts` 全绿；旧 `project_discussion` Issue 只读回放不回归；CR-B Discussion GET/发送测试全绿。 |

来源文档完成标志要求 AC-23 至 AC-27 全部满足；上表 AC-1 对应来源 AC-23（只有显式升级才创建工作 Issue），AC-4 对应 AC-24（原消息附件不被移动或删除），AC-5 对应 AC-25（重复升级不产生重复 Issue），AC-3/AC-7 对应 AC-26（工作 Issue 可回溯来源 session/消息/附件），AC-8 对应 AC-27（升级 CR 继续经过 requirement-register，Multica 不直接写 CR 账本）。AC-2/AC-6/AC-9/AC-10/AC-11/AC-12 覆盖同一闭环中必须可测、但来源完成标志未逐条编号的规则（来源选择校验、权限、前端交互、不新增 promotion 表、零残留与兼容性）。

# 6. 成功指标

- 打开 Discussion、发送、附件、协办产生的正式工作 Issue 数为 **0**；升级产生的 Issue **100%** 来自显式升级操作。
- 同一来源集合升级产生的目标 Issue 数 = **1**。
- 同一目标 Issue 对应的 `requirement-authoring` pipeline task 数 ≤ **1**（重放 / 查重命中 / 并发不产生第二个 task）。
- 原 Discussion 消息与附件被升级动作移动、删除或改绑的次数为 **0**。
- 目标 Issue 可回溯来源（`context_refs` 完整含 session/消息/附件）的比例为 **100%**。
- 升级失败留下半成品（孤立 Issue / 半写引用 / 孤立幂等记录）的次数为 **0**。
- Multica 服务端对 knowledge-base CR 账本的写入调用次数为 **0**。
- 未授权成员成功创建升级 Issue 的次数为 **0**。

# 7. 范围排除

以下内容明确不做，归属后续 CR 或明确非目标：

- 自动把 Discussion 消息升级为 Issue（任何定时/事件驱动升级）。
- 移动、删除或静默复制原 Discussion 消息与附件（FR-5 的反面）。
- 在 Multica 内实现 CR 注册、CR 状态机或 `_backlog.yml` 写入（来源 FR-25、AC-27）。
- 历史 `project_discussion` Issue 的 comment 升级（旧容器只读回放；升级只面向 shared session 消息）。
- Discussion 多主题、多 Agent 参与者模型与 `discussion_participant` 表。
- 新增 `discussion_promotion` 表（默认不做，仅 FR-12 的验证证据路径例外）。
- 给 `agent_task_queue` 增加模型/Thinking Mode 专用列；复制一套独立 Discussion 消息表。
- Team Agent / Private Ask 的发送、配置内核改动。
- 发送框整体视觉重构、对齐普通非项目聊天 composer（来源 CR-D）。
- mobile 端。
- `../tools/` 仓改动。
- 把 `/compact` 作为普通用户消息发送。
