---
id: CR-2026-059-TASK-04
type: TASK
cr-ref: CR-2026-059
plan-ref: "change-requests/CR-2026-059/plan.md"
sdd-ref: "change-requests/CR-2026-059/sdd.md"
target-version: "0.32"
title: 前端：DiscussionPane session 身份 + merge-forward 适配 + schemas + 四语文案
slug: discussion-pane-session-identity
status: pending
estimate: 12h
depends-on: [CR-2026-059-TASK-02, CR-2026-059-TASK-03]
created: 2026-09-04T16:40:00+08:00
---

# TASK-04 前端：DiscussionPane session 身份 + merge-forward 适配 + schemas + 四语文案

## 任务描述

在 multica CR worktree 重写前端 Discussion 面（SDD §3.3 前端部分、FR-19/NFR-1/NFR-2/NFR-8）：`DiscussionPane` 以 `session_id` 为唯一可写会话身份，消息/发送/附件/配置控件/实时更新全走 shared session API；旧 Discussion Issue 历史经 `legacy_issue_id` 只读渲染且不可在该流发送；**merge-forward 前端适配（B-DP-07）**：shared 流改选 `chat_message` 并发送 `message_ids` + `Idempotency-Key`，legacy Issue 流继续 `comment_ids` 不带头；响应 schema 独立 zod 定义并硬降级；消息气泡按 M486 作者字段解析展示（NULL/malformed 回退现状渲染）；新增文案 en/ja/ko/zh-Hans 对称。不重做 composer 视觉（CR-D 范围）。

## 涉及文件 / 模块

- `packages/core/api/schemas.ts`：`ProjectDiscussion`/`ProjectDiscussionSchema`/`EMPTY_PROJECT_DISCUSSION` 重定义（`session_id` 必填、`issue_id` nullable、`legacy_issue_id` nullable、配置四字段）；`ChatMessageSchema` 增 `author_type: z.enum(["member","agent"]).nullable().catch(null).optional()`、`author_id: z.string().nullable().catch(null).optional()`（malformed 独立降级，不毒化整条消息，与 `quick_actions` 策略同构）；新增 `DiscussionSendResponse` schema（`session_id`/`message_id`/`issue_id`/`task_id`）。
- `packages/core/api/client.ts`：Discussion 入口/消息发送调用点走新 schema（`parseWithFallback` 复用）；`sendChatMessage` 增可选参数 `opts?: { coordinatorRequest?: "none"|"mention"|"analyze"|"summarize"; idempotencyKey?: string }`（缺省行为不变；`idempotencyKey` 非空时加 `Idempotency-Key` 请求头；body 增 `coordinator_request`）；**`mergeForwardDiscussion` 扩展为选择对象（B-DP-07）**：`mergeForwardDiscussion(projectId: string, selection: { commentIds: string[] } | { messageIds: string[] }, registerCr: boolean, idempotencyKey?: string)`——`messageIds` 分支 body = `{message_ids, register_cr}` 且必须带 `Idempotency-Key` 头（调用方职责，缺失时 client 直接抛错，不发送）；`commentIds` 分支 body = `{comment_ids, register_cr}` 不带头（legacy 契约逐字节保持）。
- `packages/core/types/chat.ts`：`ChatMessage` 增 `author_type?: "member" | "agent" | null; author_id?: string | null`。
- `packages/views/projects/components/discussion-pane.tsx`：以 `session_id` 为会话身份重写（拉消息走 shared 分页 API；发送走 `POST .../messages` 带 `Idempotency-Key`；附件草稿机制复用；配置控件调 `PATCH .../config`，绝不 `UpdateAgent`）；`session_id` 缺失/空/非 UUID → 硬降级只读并重试 GET，禁止拿空 id PATCH/发送；`legacy_issue_id` 只读时间线渲染且不可发送；作者解析/展示（member 缓存/agent 缓存/NULL/已移出成员四语回退）；**MergeForwardPreviewDialog 消息源切换（B-DP-07）**：shared 会话选择 `ChatMessage`（`message.id`），legacy Issue 流仍选 `comment.id`；确认时分别走 `messageIds`/`commentIds` 分支；`messageIds` 分支生成一次性 `Idempotency-Key`（同一预览重试复用同一 key）；CR 开关 `register_cr` 两分支都生效。
- `packages/views/projects/components/discussion-pane.test.tsx`（既有文件，扩展）：覆盖 session 身份、作者气泡回退、旧流只读、不调 `UpdateAgent` 与 merge-forward 请求形状（见验收 3）。
- `packages/views/locales/{en,ja,ko,zh-Hans}`：新增文案 key（含「未知成员」回退文案与错误提示），四语对称。

## 实现要点

- 硬降级规则对齐 CR-2026-056「legacy 响应安全降级」：缺 `session_id` 只读；合法 `session_id` 但缺配置字段可写并重试；`issue_id` 出现非 null 不当可写容器。
- 作者展示回退表：`role=user` + `author_type='member'` → workspace 成员缓存解析显示名（与现 comment 作者渲染同一数据源）；成员行已删 → 四语「未知成员」回退；`author_type='agent'` → agent 缓存解析、缺失回退通用标签；NULL/降级 → 保持现状渲染（不显示作者标签），private/legacy 零行为变化。assistant 气泡维持既有 task/agent 渲染。
- merge-forward 分支规则：Discussion 面板当前身份 = shared session → 多选对象是 `chat_message`；当前身份 = legacy Issue 只读流 → 多选对象是 `comment`（该流本来就以 comment 为单位）。两分支互斥，绝不混送（后端 400 `invalid_merge_forward_selection` 对应前端禁用态）。
- `parity.test.ts` 对新 key 全绿；`schemas.test.ts` 覆盖 AC-17 向量；`discussion-pane.test.tsx` 扩展覆盖 pane 行为向量（见验收 3）。

## 接口契约

**消费（TASK-03 产出的 HTTP 契约，与 TASK-03「接口契约」同一份完整清单；B-DP-09 修复）**：

- `GET /api/projects/{projectId}/discussion` → 200 `{session_id, issue_id: null, legacy_issue_id: uuid|null, coordinator_agent_id, model, thinking_level, model_source, thinking_level_source}`；403 `forbidden_project_discussion`（非成员）；**404（项目不存在，无 code）→ 前端不白屏、可重试**。
- `GET /api/chat/sessions/{sessionId}/messages` 与 `/messages/page`（shared，同语义）→ 200 恒分页对象 `{messages[], limit, has_more, next_cursor?}`（绝不裸数组）；`messages[]` 含可空 `author_type`/`author_id`；400 `invalid_cursor`（limit 越界/半截 cursor）；**404 `chat_session_not_found`（非成员/错 kind/跨项目）；归档 → 200 只读可回放**。
- `POST /api/chat/sessions/{sessionId}/messages`（shared）→ 201 `{session_id, message_id, issue_id: null, task_id: uuid|null}`；请求头 `Idempotency-Key` 必填；错误体 `{code, error}`：400 `idempotency_key_required`/`invalid_discussion_message`/`invalid_model_or_thinking_level`、403（invocation）、404 `chat_session_not_found`（非成员）、409 `chat_session_closed_or_changed`/`attachment_already_bound`/`idempotency_key_reused`/两个 coordinator code——前端据此回滚配置控件或保留草稿。
- `PATCH /api/chat/sessions/{sessionId}/config`（shared）→ 200 配置字段（三态 PATCH：省略保持 / `null` 或 `""` 清 override / 非空设置）；403 `forbidden_chat_config`（非 owner/admin）、404（非成员/错 kind/跨项目）、409 `chat_session_closed_or_changed`、400 `invalid_model_or_thinking_level`。
- `POST /api/projects/{id}/chat/merge-forward`：`message_ids` 路径 201 既有 `SendProjectChatMessageResponse`（Team Agent 侧 comment/task）；头 `Idempotency-Key` 必填；400 `invalid_message_selection`/`invalid_merge_forward_selection`/`idempotency_key_required`；403 `forbidden_project_discussion`（非成员）+ 内核 `presenter_required`；409 `idempotency_key_reused`/`team_agent_not_configured`；legacy `comment_ids` 路径无头、行为不变。

**产出**：前端类型与 schema（zod 定义见「涉及文件」），供 pane 与后续消费；不发散服务端契约。client 方法：

```ts
sendChatMessage(sessionId: string, content: string, attachmentIds?: string[],
  opts?: { coordinatorRequest?: "none"|"mention"|"analyze"|"summarize"; idempotencyKey?: string }): Promise<SendChatMessageResponse>
mergeForwardDiscussion(projectId: string,
  selection: { commentIds: string[] } | { messageIds: string[] },
  registerCr: boolean, idempotencyKey?: string): Promise<ProjectChatSendResult>
```

## 验收条件

1. `node node_modules/vitest/vitest.mjs run api/schemas.test.ts`（cwd `packages/core`）全绿：GET 缺/空/非 UUID `session_id` → 硬降级只读；合法 `session_id` 且 `issue_id` 为 null 时可发送；`author_type` 缺失/非枚举/非字符串 → 消息仍可解析（作者落 null）；前端不得用 `legacy_issue_id` 调用发送（AC-17）。
2. `node node_modules/vitest/vitest.mjs run locales/parity.test.ts`（cwd `packages/views`）全绿：新增 key en/ja/ko/zh-Hans 对称（AC-18/NFR-2）。
3. `node node_modules/vitest/vitest.mjs run projects/components/discussion-pane.test.tsx`（cwd `packages/views`；与 2 同属 plan cmd-07，B-DP-06 修复）全绿且覆盖：有 `session_id` 时不再依赖可写 `issue_id`；user 气泡作者展示（member/agent 解析，NULL/已移出成员回退）；旧 Issue 流只读（不可发送）；配置控件不调 `UpdateAgent`；**merge-forward 请求形状（B-DP-07）：shared 会话确认 → `mergeForwardDiscussion(projectId, {messageIds: [...]}, registerCr, key)` 且请求带 `Idempotency-Key` 头与 `message_ids` body；legacy 流确认 → `{commentIds: [...]}` 不带头；失败保留多选与预览（DD-6）**（AC-6/AC-18 前端闭合）。
4. `pnpm typecheck` 相关包无新增错误（web 与 desktop 共享 `packages/views`，NFR-1）。

## 完成标志

schemas.test.ts + parity.test.ts + discussion-pane.test.tsx 全绿（= plan cmd-06/cmd-07 覆盖面）+ pane 行为核对通过 + 四语 key 齐全 + `CUSTOM.md` 本 TASK 条目已按当时实际结构登记（schemas.ts/client.ts/types/chat.ts、discussion-pane.tsx、locales 四语 key），且全部已 commit 到 `requirement/CR-2026-059`（`developing` 内可被 `crctl task done` 登记的事件）。
