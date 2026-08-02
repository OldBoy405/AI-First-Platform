---
id: CR-2026-008-prd
type: PRD
cr-ref: CR-2026-008
title: P2 三模式聊天 CR-C — D5 Private Ask（chat_session 项目维度 + 项目内私聊面）
target-version: "0.15"
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-02T10:30:00+08:00"
updated: "2026-08-02T10:30:00+08:00"
revision: "0.1.0"
---

# PRD — P2 三模式聊天 CR-C：D5 Private Ask（含 B2 迁移）

> 依据：`docs/product/P2-三模式聊天窗口主体-交付切分.md` v2（d7e4ece）的 CR-C 节（D5 + B2），
> 交互契约以《P2-三模式聊天交互设计》§2/§4/§6 为准，WS 语义以切分文档 §B「WS 语义修正」为准。
> 前置 CR-A（CR-2026-006，已交付）：三 tab 窗口骨架已就位，Private Ask tab 当前为空态占位；
> 本 PRD 直接引用切分文档 §0/§B 的实证结论，不重复论证。

## 1. 概述

**背景**：CR-A 交付的三模式窗口中，Private Ask tab 只有空态问候语。设计稿 §4 定义的
「个人沙箱」——项目成员在不打扰团队、不占共享队列、不改项目文件的前提下，围绕项目上下文
私下问答——目前没有承载面：既有全局 1:1 chat（浮窗 / /chat 页）无项目维度，会话不隔离到项目，
也进不了项目群聊窗口。

**本 CR 交付**（交付切分 v2 的 CR-C）：
1. **B2 后端**：`chat_session` 加 nullable `project_id` 列 + 按 `(project_id, creator_id)`
   查询会话。Private Ask 会话按项目上下文隔离，与既有全局 1:1 chat（`project_id` 为空）并存，
   迁移量小、既有行为不变。
2. **D5 前端**：窗口第二 tab 从占位变为可用的 Private Ask 面。实现路径**绕开
   `use-chat-controller.ts`**（其耦合全局 `useChatStore` 单例，挂第三个消费者会互抢会话），
   直接组合纯 props 的 `ChatMessageList` + `ChatInput` + `TaskStatusPill`，sessionId 由
   `project-chat-panel` 自管。
3. **语义四差异**（设计稿 §4）：① 个人独立队列（排队数只算自己，他人不可见，不占 D1 的
   项目共享队列）；② 默认 Ask-only 只读（execenv 不给写权限，无 Ask/Coding 切换）；
   ③ 消息仅本人可见；④ 与 Team Agent 并行（一边等 Team Agent 跑，一边私下问答）。

**隐私红线（本 CR 首要验收对象）**：multica 实时层是**单条 workspace 级 socket**（服务端按
workspace fanout、客户端按 payload 字段过滤，无 per-channel 房间——切分文档 §B WS 语义修正）。
因此 Private Ask 的「消息永不进全工作区广播」**只能靠服务端 per-user 推送逻辑保证，
前端过滤不算数**。设计稿 §9.3 的「WS `chat:{sessionId}` 房间」表述按此修正理解。

**技术前提**（SDD 阶段细化）：
- 既有 `chat_session`/`chat_message` 本就是沙箱化模型（Agent 看不到 Issue）+ provider 会话恢复
  保持多轮上下文，语义现成；本 CR 只加项目维度，不动消息模型。
- 不新建 WS 连接、不新建消息表；聊天事件的既有 per-user 推送路径直接沿用（若核实发现既有
  chat 事件走 workspace 广播，则收敛为 per-user 推送是本 CR 的后端必做项）。
- 模型选择器数据源（B5）已由 CR-A 交付，`ChatInput` 复用即得。

## 2. 用户故事

- **US-1** 作为**项目成员**，我希望在项目群聊窗口内有一个只属于我的问答面，围绕本项目上下文
  提问（理解代码、评估方案），而不必切到全局 chat 丢失项目语境，也不在团队面前刷屏。
- **US-2** 作为**项目成员**，我希望 Team Agent 正在跑任务时，我仍能并行地私下问答——
  我的问题走自己的队列，不占项目共享队列的槽位，也不受满队禁用影响。
- **US-3** 作为**项目成员**，我确信 Private Ask 里的提问与回答**只有我自己看得到**——
  其他成员的窗口、通知、WS 事件里永远不出现我的私聊内容。
- **US-4** 作为**项目 Owner**，我确信 Private Ask 是只读探索：Agent 在该面内无法写 worktree、
  无法改项目文件，项目状态不会被私聊行为改变。
- **US-5** 作为**既有 chat 用户**，我希望浮窗 FloatingChat 与全页 /chat 的会话在 B2 迁移后
  完全不受影响（会话不丢、行为不变、不与项目私聊互抢）。

## 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | **B2 迁移**：`chat_session` 加 nullable `project_id` 列（含索引）；既有全局会话 `project_id` 为空、行为不变；提供按 `(project_id, creator_id)` 查询会话的能力 | P0 |
| FR-2 | **会话获取**：进入 Private Ask tab 时按 `(project_id, creator_id)` get-or-create 会话（lazily 创建，本 CR 单活跃会话，不做会话列表/切换）；sessionId 由 `project-chat-panel` 自管，多轮上下文沿既有 provider 会话恢复语义 | P0 |
| FR-3 | **Private Ask 面**：第二 tab 从空态占位变为完整聊天面——直接组合纯 props 的 `ChatMessageList`（消息渲染/工具执行卡现成）+ `ChatInput`（附件/@提及成员/草稿现成）+ `TaskStatusPill`（生成中状态）；**不得**引入 `use-chat-controller.ts` / `useChatStore` 单例 | P0 |
| FR-4 | **个人独立队列**：Private Ask 消息走用户级独立队列（既有 1:1 chat 队列语义），排队/生成状态只对本人展示；不写入 `agent_task_queue` 项目共享队列，不受 D1 项目队列满队 429/禁用态影响 | P0 |
| FR-5 | **Ask-only 只读**：输入区固定 Ask 模式（无 Ask/Coding 切换控件）；该面发起的 Agent 会话 execenv 为只读，无法写 worktree | P0 |
| FR-6 | **隐私推送**：Private Ask 的消息与状态事件由服务端**只向发起用户推送**（per-user 推送逻辑），永不进入 workspace 级广播 payload；不得以前端过滤替代 | P0 |
| FR-7 | **与 Team Agent 并行**：Team Agent 任务运行/排队期间，Private Ask 可正常发送并获得回复，两面互不阻塞、状态互不串扰 | P0 |
| FR-8 | **输入区能力**（设计稿 §6 Private Ask 列）：附件 ✓、@提及仅成员 ✓、技能选择器 ✓、模型选择器 ✓（复用 B5 数据源）、发送/停止 ✓（仅停自己）；无斜杠命令（§0.4 排除） | P1 |
| FR-9 | **停止**：生成中「发送」变「停止」，仅本人可停自己的生成；停止后已生成内容保留 | P1 |

## 4. 非功能需求

- **NFR-1 隐私零泄漏**：任何包含 Private Ask 消息内容或会话标识的 WS payload 不得广播给
  非发起用户；这是安全边界，不接受"前端过滤后不展示"的实现。
- **NFR-2 零回归**：既有浮窗 FloatingChat、全页 /chat 会话在 B2 迁移后行为不变（会话列表、
  多轮恢复、WS 更新均正常）；`useChatStore` 全局单例不被触碰；Team Agent 面（CR-A 交付）行为不变。
- **NFR-3 双端一致**：web 与 desktop（Electron 共享 `packages/views`）行为一致；mobile 不在 P2 范围。
- **NFR-4 四语文案**：新增 UI 文案提供 en/ja/ko/zh-Hans 四语，locale parity 测试全绿。
- **NFR-5 复用优先**：不新建消息表、不新建 WS 连接、不复制 ChatMessageList/ChatInput 组件；
  SDD 若偏离需给出论证。

## 5. 验收标准

- **AC-1**（FR-6/NFR-1，隐私——首要验收）两个浏览器分别以成员 A、B 登录同一项目：A 在
  Private Ask 发消息并获得 Agent 回复全程，B 的窗口、WS 帧（开发者工具抓包核验）与通知中
  均不出现 A 的私聊消息或其会话事件——**验证的是服务端推送逻辑**，非前端渲染结果。
- **AC-2**（FR-4/7，并行）Team Agent 正在执行任务（或队列有排队项）时，同一成员在 Private Ask
  发问可正常入自己队列并获得回复；Private Ask 的排队/生成状态不出现在 Team Agent 面，
  反之亦然；项目队列满队（D1 429）不影响 Private Ask 发送。
- **AC-3**（FR-5，Ask-only）Private Ask 内要求 Agent 修改项目文件：Agent 无法写 worktree
  （execenv 只读约束真机验证），项目文件与 git 状态无任何变更；输入区无 Ask/Coding 切换控件。
- **AC-4**（FR-1/2，会话隔离）同一用户在项目 X、项目 Y 的 Private Ask 与全局 /chat 三处会话
  互相独立：消息不串、上下文不串；刷新后各自会话与历史消息正确恢复（多轮上下文延续）。
- **AC-5**（NFR-2，迁移回归）B2 迁移后：既有浮窗与 /chat 页全量回归通过（会话不丢、收发正常）；
  Team Agent 面收发与工具执行卡回归通过；迁移可在含存量 chat_session 数据的库上无损执行。
- **AC-6**（FR-3/8/9 + NFR-3/4）Private Ask 面消息渲染（含工具执行卡）、附件、@提及成员、
  模型选择器、停止（仅停自己、内容保留）真机可用；web 与 desktop 一致；locale parity 全绿。

## 6. 成功指标

- 三模式窗口的第二面从占位到可用：项目成员获得「不打扰团队、不占共享队列、不改项目」的
  项目内私有问答通道，Team Agent（共享执行）与 Private Ask（私有探索）的分工语义完整成立。
- B2 迁移为 chat_session 建立项目维度，后续凡需"项目上下文私有会话"的能力（如导出 Skill
  草稿的私有沙箱验证）可直接复用，无需再动会话模型。

## 7. 范围排除

- 会话管理增强：会话列表/多会话切换、清空上下文（contextUsageModal，依赖 daemon usage 回调，
  §0.4 排除）、恢复检查点 → 后续交付。
- 消息操作：回复/转发/导出 Skill 草稿/点踩反馈（§0.4 排除）；本面悬浮操作对齐 CR-B 口径（仅复制，随 CR-B 交付节奏）。
- 斜杠命令（含 §6.1 的只读类命令）→ §0.4 排除，独立交付。
- Team Agent 面的队列条完整形态/停止/过滤开关 → **CR-B**；Discussion 内容面 → **CR-D**；
  presenter → **CR-E**；门禁接合 → **CR-F**；DC 与合并转发 → **CR-G**。
- Private Ask 的计费/用量归属展示（设计稿 §2「按项目上下文」）→ 随上下文用量指示一并后续交付。
- mobile（独立 RN 组件集）全程不在 P2 范围。
