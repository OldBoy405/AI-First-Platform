---
id: CR-2026-006-prd
type: PRD
cr-ref: CR-2026-006
title: P2 三模式聊天 CR-A — 三 tab 窗口骨架 + Team Agent 消息流核心（D2+D3 核心）
target-version: "0.13"
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-01T23:40:00+08:00"
updated: "2026-08-01T23:48:00+08:00"
revision: "0.1.1"
---

# PRD — P2 三模式聊天 CR-A：三 tab 窗口骨架 + Team Agent 消息流核心

> 依据：`docs/product/P2-三模式聊天窗口主体-交付切分.md` v2（d7e4ece）的 CR-A 节（D2 全部 + D3 核心 + B1/B3/B5），
> 交互契约与字典锚点以《P2-三模式聊天交互设计》§1/§3.2–§3.3/§9 为准。
> CodeBanana 快照实证与 multica 前端现状调查结论已固化在切分文档 §0/§B，本 PRD 直接引用不重复论证。

## 1. 概述

**背景**：P2 的后端地基（D1 队列容量治理：守卫/插队/撤回/queue-status/429）已由 CR-2026-004 交付，
但**三模式项目群聊窗口本身不存在**——目前驱动 Team Agent 只能走 Issue 页评论 @提及或 quick-create
弹窗，执行过程要到任务详情里看，没有"项目内聊天式协作"的体验主体。这是平台 PRD 人力表中
「前端 2 人 · P2–P3 重」的核心缺口，也是 CR-B/C/D/E/F/G 全部后续交付的唯一硬前置。

**本 CR 交付**（交付切分 v2 的 CR-A）：
1. **D2 窗口骨架**：project-detail 主区新增 Issues | Chat 两个 tab（`?tab=` 深链）；Chat tab 内为
   三模式 tab 条（Team Agent / Private Ask / Discussion，空态问候语 + 首次教程气泡）；切换纯前端、
   三面独立 query key；输入草稿按 `{projectId}:{mode}` 独立持久化。Private Ask 与 Discussion 本 CR
   只交付空态占位，内容面分别归 CR-C / CR-D。
2. **D3 核心（Team Agent 消息流最小闭环）**：落地 B1 方案甲——`team-agent-chat` 隐藏容器 Issue（B3）
   + 薄发送端点（容量守卫 → 落 comment → enqueue，满队同步 429，评论不落库）；消息流复用既有
   issue-timeline 基础设施渲染用户消息与 Agent 工具执行卡（实时 + 历史回放）。

**明确不做**（归属后续 CR，见 §7）：队列条完整形态、停止、过滤开关（CR-B）；Private Ask/Discussion
内容面（CR-C/D）；presenter（CR-E）；门禁接合（CR-F）；DC 与合并转发（CR-G）。

**技术前提**（切分文档 §B 已定，SDD 阶段细化）：
- B1 采用方案甲（复用 comment + 容器 Issue + 薄发送端点），不新建消息表；偏离需 SDD 论证。
- multica 实时层是单 workspace socket + payload 字段过滤（无 per-channel 房间），新增事件只加 handler。
- 队列治理逻辑完全消费 CR-2026-004 已交付端点（`guardProjectQueueCapacity`、queue-status、429 结构化响应），不改动。

## 2. 用户故事

- **US-1** 作为**项目成员**，我希望在项目页内直接以聊天方式给 Team Agent 派活，并在同一窗口实时看到
  它的工具执行过程（而不是建 Issue 后跳任务详情页），以便"沟通发生在执行发生的地方"。
- **US-2** 作为**项目成员**，我希望刷新或次日再进入项目群聊时，看到完整的历史消息与执行记录，
  以便群聊成为团队共享的工作记忆而非一次性会话。
- **US-3** 作为**普通成员**，我希望队列满时发送立即得到明确反馈（禁用 + 原因 + 当前深度/上限），
  而不是消息静默消失；作为 **owner/admin**，我希望不受此限制（D1 插队语义在聊天入口同样生效）。
- **US-4** 作为**平台维护者**，我希望群聊不引入平行的消息基础设施（复用评论/时间线/WS 既有能力），
  以便后续 CR-B~G 在同一套模型上叠加。

## 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | **入口与骨架**：`project-detail` 主区新增 Tabs（Issues \| Chat），`?tab=` 参数深链可达；Chat tab 渲染项目群聊容器（三模式 tab 条 + 消息流区 + 输入区三段式），右侧既有 sidebar（含 D1 的 ProjectQueueStatus）保留 | P0 |
| FR-2 | **三模式 tab**：Team Agent / Private Ask / Discussion 三个平铺 tab（激活态 + 下划线指示，对齐 CodeBanana 实证样式）；切换纯前端不触发网络请求（三面独立 query key）；各 tab 空态问候语（heyTeamAgent/heyPrivateAsk/heyDiscussion 三条）+ 首次进入教程气泡；Private Ask 与 Discussion 本 CR 为空态占位 | P0 |
| FR-3 | **草稿持久化**：输入草稿按 `{projectId}:{mode}` 命名空间存独立 zustand store（参照 useChatStore 的持久化写法但不复用该 store），切 tab / 刷新后草稿保留 | P1 |
| FR-4 | **容器 Issue（B3）**：项目首次进入 Chat tab 时 lazily 创建 `team-agent-chat` 系统容器 Issue（专用类型或 label 标记）；该 Issue 不出现在 Issue 列表、看板、泳道、甘特与 my-issues 中 | P0 |
| FR-5 | **薄发送端点（B1）**：`POST /api/projects/{id}/chat/messages`，服务端顺序执行：容量守卫（复用 D1 `guardProjectQueueCapacity`）→ 落 comment（挂容器 Issue）→ enqueue；满队时同步返回 429 `project_queue_full`（含 depth/limit），**评论不落库**；既有 Issue 页评论 @提及的 fire-and-forget 路径保持不动 | P0 |
| FR-6 | **Team Agent 消息流**：容器 Issue 的 timeline 作为消息流数据源——用户消息以聊天气泡呈现（复用 CommentCard 能力：头像/markdown/附件），Agent 执行过程以工具执行卡呈现（复用 buildTimeline/TimelineView：running/done/error/interrupted 徽标 + 耗时 + 可折叠输入输出）；WS 实时渲染 + 分页加载历史（"暂无更早消息"边界） | P0 |
| FR-7 | **发送与满队反馈**：输入区复用既有 ChatInput（附件/@提及/草稿现成）；收到 429 时输入区禁用 + 「Agent 忙，请稍后」（展示 depth/limit），由 queue-status（D1 端点）驱动恢复；owner/admin 不进入禁用态（D1 插队语义） | P0 |
| FR-8 | **模型选择器（B5）**：输入区模型选择器数据源 = daemon 上报的本机 Runtime 可用模型（既有 chat 输入区已有则复用，无则新建下拉读 runtimes 数据）；无可用 Runtime 时提示「请先在设置中启动本地 Agent」 | P1 |

## 4. 非功能需求

- **NFR-1 双端一致**：web 与 desktop（Electron 共享 `packages/views`）行为一致；mobile（独立 RN 组件集）不在 P2 全程范围。
- **NFR-2 四语文案**：全部新增 UI 文案提供 en/ja/ko/zh-Hans 四语，locale parity 测试全绿。
- **NFR-3 零回归**：既有浮窗 FloatingChat、全页 /chat、Issue 页评论与 @提及路径行为不变；不触碰 `useChatStore` 全局单例；容器 Issue 的隐藏过滤不改变既有 Issue 查询语义。
- **NFR-4 复用优先**：消息基础设施复用 comment/timeline/WS 既有能力（B1 方案甲），不新建消息表、不新建 WS 连接；SDD 若偏离需给出论证。
- **NFR-5 队列治理不动**：容量/插队/撤回/queue-status 语义完全消费 CR-2026-004 已交付实现，本 CR 不修改 task_queue_capacity 相关代码路径（薄发送端点仅调用）。

## 5. 验收标准

- **AC-1**（FR-1/2/3，D2 骨架）项目页经 Chat tab 进入群聊窗口：三模式 tab 可切换且切换不触发网络请求（缓存命中验证）；`?tab=` 深链直达；各 tab 空态问候语正确；草稿按 tab 独立保留且刷新后仍在；web 与 desktop 行为一致。
- **AC-2**（FR-5/6，D3 闭环）在 Team Agent tab 发消息 → 容量守卫 → comment 落库 → 入队 → claim → 工具执行卡逐个实时渲染 → 完成回复，全链路在窗口内可见，无需手动刷新。
- **AC-3**（FR-6，持久化回放）刷新页面 / 重新进入项目，历史消息与工具执行卡完整回放，分页加载可达最早消息。
- **AC-4**（FR-5/7，满队路径）队列满（利用 D1 的 project 级 limit 配置压低上限构造）时：普通成员发送同步收到 429 且消息不落库、输入区禁用并展示 depth/limit、队列释放后恢复；owner/admin 同场景仍可正常发送入队。
- **AC-5**（FR-4，容器隔离）`team-agent-chat` 容器 Issue 不出现在 Issue 列表/看板/泳道/甘特/my-issues；群聊消息不在 Issue 面板产生可见噪音。
- **AC-6**（NFR-2/3，回归）locale parity 测试全绿；既有浮窗 chat、全页 /chat、Issue 页评论 @提及路径回归通过。
- **AC-7**（FR-8，模型选择器）输入区模型选择器展示 daemon 上报的本机 Runtime 可用模型列表（与 runtimes 页数据一致）；无可用 Runtime 时展示「请先在设置中启动本地 Agent」引导且发送不可用。

## 6. 成功指标

- P2 窗口主体从 0 到可用：项目成员可全程在项目页内以聊天方式驱动 Team Agent 并看到执行过程，
  不再依赖 Issue 页 / quick-create 弹窗间接派单。
- CR-B/C/D（队列完整形态、Private Ask、Discussion）可在本 CR 的骨架与数据模型上直接并行开工，
  无需再动窗口容器与消息持久化层。

## 7. 范围排除

- 队列条完整形态（常驻计数、展开排队列表、逐项撤回）、停止按钮、「只看 Agent 请求」过滤开关、消息复制操作 → **CR-B**。
- Private Ask 内容面（B2 chat_session 项目维度）→ **CR-C**；Discussion 内容面（discussion 容器 Issue）→ **CR-D**。
- presenter 控制权（claim 串行化键改造）→ **CR-E**；CR 门禁接合（B4 迁移 + 审批卡）→ **CR-F**；DC 协调者 + 合并转发 → **CR-G**。
- 切分文档 §0.4 的全部写死排除项：项目/消息双入口、work-viewer、上下文用量指示、语音输入、消息回复/转发线程、成员管理增强、斜杠命令、导出 Skill 草稿、恢复检查点、点踩反馈、mobile。
- chatHeader 右侧抽屉本 CR 只留入口占位（成员抽屉复用既有 member 组件即可挂上，其余不实现）。
