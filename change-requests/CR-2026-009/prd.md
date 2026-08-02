---
id: CR-2026-009-prd
type: PRD
cr-ref: CR-2026-009
title: P2 三模式聊天 CR-D — D6 Discussion（discussion 容器 Issue + 纯人类多人聊天）
target-version: "0.16"
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-02T10:45:00+08:00"
updated: "2026-08-02T10:52:00+08:00"
revision: "0.1.1"
---

# PRD — P2 三模式聊天 CR-D：D6 Discussion（discussion 容器 Issue + 纯人类多人聊天）

> 依据：`docs/product/P2-三模式聊天窗口主体-交付切分.md` v2（d7e4ece）的 CR-D 节（D6 + B3 的 discussion 容器），
> 交互契约与字典锚点以《P2-三模式聊天交互设计》§5（DC 部分除外，归 CR-G）/§6 输入区差异表为准。
> CodeBanana 快照实证（Discussion 输入区无模式/模型下拉，切分文档 §0.1 表）与 multica 前端复用面调查
> 已固化在切分文档 §0/§B，本 PRD 直接引用不重复论证。
> 前置：CR-2026-006（CR-A）已交付——三 tab 窗口骨架、Discussion 空态占位、`team-agent-chat` 容器
> Issue 的 origin_type 容器模式与列表/看板隐藏过滤基建，本 CR 直接复用。

## 1. 概述

**背景**：CR-A 交付的三模式窗口中，Discussion tab 目前只是空态占位（heyDiscussion 问候语）。
项目成员的人类沟通仍散落在 Issue 评论与平台外 IM，没有"沟通发生在执行发生的地方"的团队讨论面。
Discussion 是三模式中的**人类沟通层**：无队列、无 Agent 驱动、全员可见（交互设计 §2 对照表），
也是 CR-G（DC 协调者 + 讨论转执行）的唯一前置。

**本 CR 交付**（交付切分 v2 的 CR-D）：
1. **B3 后端（discussion 容器 Issue）**：项目首次打开 Discussion 面时 lazily 创建 `discussion`
   系统容器 Issue——复用 CR-2026-006 已落地的 origin_type 容器模式与列表/看板/搜索隐藏过滤基建，
   仅新增 discussion 类型值，不新建过滤机制。
2. **前端第三 tab（纯人类多人聊天）**：容器 Issue 的 comment 流即消息流。复用清单（切分文档 D6 节）：
   `comment-card.tsx`（ActorAvatar + ReadonlyContent + ReactionBar + 附件）、`reply-input.tsx`、
   @提及 + 通知 + 订阅基础设施；成员变更等行内系统条。输入区**无**模式/模型/技能下拉、无上下文
   用量——纯人类输入仅留附件 + @（CodeBanana 实证，切分文档 §0.1）。

**验收红线**（cr.md 明示）：Discussion 消息不产生任何 `agent_task_queue` 行（除非 CR-G 的 DC 被
显式激活）；容器 Issue 不出现在 Issue 列表/看板。

**技术前提**（切分文档 §B 已定，SDD 阶段细化）：
- 实时通道走既有单 workspace socket 广播（无 per-channel 房间），Discussion 全员可见语义与
  workspace fanout 天然一致，新增事件只加 handler。
- 既有 Issue 页评论 @提及入队路径是 fire-and-forget；discussion 容器 Issue 上的 comment **不得**
  进入该入队路径（红线 FR-5），豁免方式（按容器类型短路 / 提及解析跳过 Agent）SDD 定案。

## 2. 用户故事

- **US-1** 作为**项目成员**，我希望在项目群聊窗口的 Discussion tab 与其他成员实时讨论，
  讨论记录沉淀在项目内可回放，以便沟通与执行记录同处一地，不再流失到平台外 IM。
- **US-2** 作为**项目成员**，我希望在讨论中 @某位成员时对方收到通知，以便异步协作时不漏关键讨论。
- **US-3** 作为**项目成员**，我希望 Discussion 里的发言纯粹是人对人的——不会意外触发 Agent
  跑任务、不占用 Team Agent 共享队列，以便放心地自由讨论半成品想法。
- **US-4** 作为**平台维护者**，我希望 Discussion 完全复用评论/通知/WS 既有基础设施与 CR-A 的
  容器 Issue 模式，不引入平行消息模型，以便 CR-G 在同一套模型上叠加 DC 与合并转发。

## 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | **discussion 容器 Issue（B3）**：项目首次打开 Discussion tab 时 lazily 创建 discussion 系统容器 Issue，复用 CR-A 的 origin_type 容器模式，新增 discussion 类型值；该 Issue 不出现在 Issue 列表、看板、泳道、甘特、my-issues 与搜索（复用既有隐藏过滤基建，不新建机制）；每项目至多一个（幂等创建） | P0 |
| FR-2 | **Discussion 消息流**：容器 Issue 的 comment 流为数据源；消息以 `comment-card.tsx` 渲染（ActorAvatar + ReadonlyContent markdown + ReactionBar + 附件）；workspace 级 WS 广播实时上屏（全员可见）；分页加载历史（"暂无更早消息"边界），刷新后全量可回放 | P0 |
| FR-3 | **输入区（纯人类形态）**：复用 `reply-input.tsx`——仅附件 + @提及（成员）；**无**模式/模型/技能下拉、无 Ask/Coding 切换、无上下文用量指示、无停止按钮（仅发送）；草稿沿 CR-A 的 `{projectId}:{mode}` 命名空间独立持久化 | P0 |
| FR-4 | **@提及 + 通知 + 订阅**：@成员触达站内通知，复用既有提及/通知/订阅基础设施，不新建通知类型 | P0 |
| FR-5 | **零 Agent 触发红线**：Discussion 消息（含正文出现 @Agent 字样的情形）不产生任何 `agent_task_queue` 行、不经过队列容量守卫；发送路径为直接落 comment，不走 CR-A 的薄发送端点；既有 Issue 页评论 @提及入队路径对 discussion 容器豁免且行为不变 | P0 |
| FR-6 | **行内系统条**：成员变更（邀请/退出/移除）等系统事件在 Discussion 消息流中以行内系统条呈现（复用既有系统消息渲染能力；若既有基建不产生对应事件流，最小实现范围 SDD 定案，缺口不阻塞本 CR 其余验收） | P1 |

## 4. 非功能需求

- **NFR-1 双端一致**：web 与 desktop（Electron 共享 `packages/views`）行为一致；mobile 不在 P2 全程范围。
- **NFR-2 四语文案**：全部新增 UI 文案提供 en/ja/ko/zh-Hans 四语，locale parity 测试全绿。
- **NFR-3 零回归**：CR-A 已交付的 Team Agent 面、`team-agent-chat` 容器隐藏过滤、Issue 页评论与
  @提及入队路径、浮窗/全页 chat 行为均不变；隐藏过滤扩展 discussion 类型值不改变既有 Issue 查询语义。
- **NFR-4 复用优先**：不新建消息表、不新建 WS 连接、不新建通知类型、不新建隐藏过滤机制；
  SDD 若偏离需给出论证。

## 5. 验收标准

- **AC-1**（FR-2，多人实时）两个浏览器会话以不同成员进入同一项目 Discussion tab：A 发消息 B 实时
  可见（无手动刷新），消息卡含头像/markdown/附件/reaction；刷新后历史完整回放，分页可达最早消息。
- **AC-2**（FR-4，提及通知）讨论中 @成员，被提及者收到站内通知且可点击跳转到该讨论。
- **AC-3**（FR-5，红线）在 Discussion 发送多条消息（含一条正文带 @Agent 提及的消息）后，
  `agent_task_queue` 无任何新增行（DB 级验证）；同场景下 Issue 页评论 @提及仍正常触发入队（豁免不外溢）。
- **AC-4**（FR-1，容器隔离）discussion 容器 Issue 不出现在 Issue 列表/看板/泳道/甘特/my-issues/搜索；
  与 `team-agent-chat` 容器并存互不干扰；重复进入 Discussion tab 不重复创建容器。
- **AC-5**（FR-3，输入区形态）Discussion 输入区无模式/模型/技能下拉、无上下文用量、无停止按钮，
  仅附件 + @提及可用；草稿独立保留且刷新后仍在（与其他两 tab 草稿互不串扰）。
- **AC-6**（NFR-2/3，回归）locale parity 测试全绿；Team Agent 面收发、Issue 页评论、浮窗/全页 chat
  回归通过。
- **AC-7**（FR-6，行内系统条）按 SDD 定案的事件范围，触发一次成员变更（如邀请新成员）后 Discussion
  消息流出现对应行内系统条；若 SDD 论证既有基建无对应事件流并裁剪该项，须在 SDD 与评审记录中留痕
  裁剪结论，本 AC 按裁剪后范围验收。

## 6. 成功指标

- 三模式窗口第三面从空态占位到可用：项目成员可在项目内完成多人实时讨论，讨论记录持久沉淀于项目上下文。
- CR-G（DC 协调者 + 合并转发）可在 discussion 容器与消息流之上直接开工，无需再动消息模型。

## 7. 范围排除

- **DC 协调者**（@提及激活、只协调不执行）与**合并转发/讨论升级 CR** → **CR-G**（依赖本 CR）。
- 消息回复（reply）线程、消息转发、语音输入 → 切分文档 §0.4 写死排除。
- 恢复检查点、导出 Skill 草稿、点踩反馈、斜杠命令 → §0.4 沿 v1 排除项。
- 成员管理增强（邮件邀外部好友/解散群组/头像编辑器）、免打扰/静音设置 → §0.4（设计稿 §8 后续另议）。
- 项目/消息双入口、右侧 work-viewer、上下文用量指示器 → §0.4 写死排除。
- mobile（独立 RN 组件集）→ P2 全程不在范围。
