---
id: CR-2026-062-prd
type: PRD
cr-ref: CR-2026-062
title: Team Agent 和 Private Ask 发送框 UI 优化
target-version: 0.35
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-09T15:17:26+08:00
updated: 2026-09-09T15:17:26+08:00
---

# 1. 概述

## 1.1 问题陈述

Team Agent（`packages/views/projects/components/project-team-agent-chat.tsx`）与 Private Ask（`packages/views/projects/components/project-private-ask.tsx`）的发送框当前与普通非项目聊天（`packages/views/chat/components/chat-input.tsx` 的 `ChatInput`/`ChatInputCore`）存在两套互不一致的 composer 视觉体系：

- 两侧 composer 包装均为 `shrink-0 border-t px-4 py-3` 固定 padding，不采用 `chat-column.ts` 的 `CHAT_GUTTER`/`CHAT_COLUMN` 容器感知对齐，发送框边缘与消息列边缘在宽面板中不对齐。
- Model Picker / Thinking Mode 以 `*-model-row` 独立一行放在 composer 上方（`mb-1.5 flex items-center gap-1.5 text-xs text-muted-foreground`），而不是普通聊天底部的 `leftAdornment` 工具栏槽位，形成与普通聊天不同的控件层次。
- 输入 surface 的边框、背景、focus-within 状态、圆角与内部滚动等细节与普通非项目聊天不一致，用户在两类聊天间切换时会感到两套输入体验。

来源文档 `docs/product/Multica聊天会话级配置与Discussion方案.md` §12 CR-D 要求：**在不改变业务语义的前提下，将项目聊天发送框的布局和视觉体验对齐普通非项目聊天**。以上现状与 CR-D 目标不符。

## 1.2 解决方案摘要

按来源文档 CR-D 的布局基准重构两侧项目聊天 composer 的视觉层次：

```text
composer wrapper
  -> container-aware gutter（CHAT_GUTTER，复用 chat-column.ts）
  -> centered, width-capped input surface（CHAT_COLUMN）
       -> optional top metadata / attachment area（pending-message / 队列 / presenter 提示保留）
       -> scrollable editor area（长文本内部滚动）
       -> bottom-left add menu + session config controls（leftAdornment 或等价底部工具栏控件）
       -> bottom-right send / stop action
```

具体规则（来源文档 §12 CR-D）：

1. 复用普通聊天的 `CHAT_GUTTER`/`CHAT_COLUMN`，让消息列和发送框边缘对齐；项目窄面板使用容器宽度，不依赖浏览器 viewport 断点。
2. 复用单一输入 surface：边框、背景、focus-within 状态、圆角和内部滚动保持一致。
3. 输入区、附件预览、底部工具栏分层，长文本在输入区内部滚动，不能把发送按钮顶出面板。
4. 左下角复用普通聊天的附件/添加入口，并将 Model Picker、Thinking Mode 作为 `leftAdornment` 或等价底部工具栏控件接入；控件不再单独占据发送框上方的一整行，除非窄屏布局确实需要换行。
5. 右下角复用普通聊天的发送/停止按钮和 loading、上传中、运行中状态。
6. Team Agent 和 Private Ask 继续使用各自的 draft adapter、项目草稿隔离和 pending-message 模式，不接入普通聊天的全局 session store。
7. 配置控件使用已有的 Model Picker/Thinking Picker；控件操作仍调用会话配置接口（`PATCH /chat/config`，CR-2026-056 交付），不得改变 Agent 配置。
8. 保留可访问名称、tooltip、键盘发送、附件上传中禁发、失败可重试和运行中停止。

本 CR 是纯前端体验 CR（来源文档 CR-D）：不新增 API、数据库字段、任务快照或数据模型，不改变 draft/attachment/send/stop/retry 业务行为。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

在不改变业务语义的前提下，将 Team Agent 与 Private Ask 项目聊天发送框的布局和视觉体验对齐普通非项目聊天：复用 CHAT_GUTTER/CHAT_COLUMN 对齐与单一输入 surface，Model Picker/Thinking Mode 控件作为底部工具栏控件接入（仍调用会话配置接口、不改 Agent 配置），附件预览/上传中/发送中/停止/失败/空态视觉一致，Web 与 Desktop 共享组件适配；不新增 API、数据库字段、任务快照或数据模型，不改变 draft/attachment/send/stop/retry 业务行为。

**包含范围**（来源文档 §12 CR-D）：

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
- Discussion UI 变化不得混入本 CR。

**依赖**：依赖 CR-A（CR-2026-056「会话级配置与 Team Agent 闭环」，已归档并回写 specs 基线）提供会话配置控件所需的服务端字段和功能接口（`PATCH /chat/config`）；不依赖 CR-B（CR-2026-059）/CR-C（CR-2026-061）的 Discussion 产出。

**目标仓库**：代码实施在 sibling `../multica/`（`packages/views` 共享组件）；knowledge-base 承载本 PRD 与来源文档；`../tools/` 无实施改动。

`target-version` 继承 `cr.md` 的 `0.35`（注册阶段由 AIFI-18 指定），本文件不得改写该字段。`target-spec-id` 为 `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

**契约说明**：本 CR 不定义新的用户可调用契约（无新增 HTTP API、CLI 或 Skill 契约），PRD 契约确定性四查（幂等/权限/错误闭包/副作用）不适用（N/A）；现有 `PATCH /chat/config` 契约仅作为消费方引用先例，其确定性语义由 CR-2026-056 定义，本 CR 不改变。

## 1.4 当前代码事实（落笔前核实）

基线：multica requirement worktree HEAD `117fc6be657f91d43df5892b52782a18329c7aed`（register 时 ensure 的 requirement/CR-2026-062 worktree，已含 CR-A/CR-B/CR-C 合入产物）。以下结论均在该 SHA 上核实：

| 结论 | 证据 |
|---|---|
| `CHAT_GUTTER`/`CHAT_COLUMN` 定义与容器感知语义 | `packages/views/chat/components/chat-column.ts`：`CHAT_GUTTER = "px-5 @2xl:px-8 @4xl:px-12"`、`CHAT_COLUMN = "mx-auto w-full max-w-4xl"`；文件头注释明确「gutter scales with the CONTAINER, never the viewport」「gutter OUTSIDE the cap」的嵌套顺序语义 |
| 普通聊天 composer 结构（对齐基准） | `packages/views/chat/components/chat-input.tsx` `ChatInput`（L625-770）：wrapper 应用 `CHAT_GUTTER`；surface 应用 `CHAT_COLUMN` + `rounded-lg border border-surface-border bg-surface … focus-within:border-brand focus-within:ring-2`（L659-660）；编辑器区 `flex-1 min-h-0 overflow-y-auto px-3 py-2`（L703）；左下 `absolute bottom-1.5 left-1.5` 为 `ChatAddMenu` + `leftAdornment`（L737-752）；右下 `absolute bottom-1 right-1.5` 为 `SubmitButton`（loading/uploading/running/stop/tooltip，L753-770） |
| `ChatInputCore` 支持 `leftAdornment` 且不接触全局 store | `chat-input.tsx` L829 `interface ChatInputCoreProps extends ChatInputProps`（`leftAdornment?: ReactNode` 定义于 ChatInputProps L123）；`ChatInputCore` 渲染含 `leftAdornment` 底部工具栏（L1127-1136）；L856 注释「this component never touches useChatStore」（由 chat-input.test.tsx 钉住的结构事实） |
| Team Agent 当前 composer 与配置行 | `project-team-agent-chat.tsx`：wrapper `shrink-0 border-t px-4 py-3`（L864）；`project-chat-model-row` 独立行位于 composer 上方（L914-963，`mb-1.5 flex items-center gap-1.5 text-xs text-muted-foreground`），含 `ModelPicker`（L936）与 `ThinkingPicker`（L955）；`ChatInputCore` 使用点（L968，draftAdapter/onSend/onUploadFile/isRunning/mentionItemTypes） |
| Team Agent 会话配置路径与权限门禁 | `project-team-agent-chat.tsx` L686-692 注释：有效模型/思考级别在 active session 上，经 `PATCH /chat/config` 持久化，`api.updateAgent` 不得从聊天路径调用；L920-923：owner/admin 可编辑（`canConfigure`），普通成员显示只读徽标 `project-chat-model-readonly`（L924-933） |
| Private Ask 当前 composer 与配置行 | `project-private-ask.tsx`：wrapper `shrink-0 border-t px-4 py-3`（L392）；`private-ask-model-row` 独立行位于 composer 上方（L401-432），含 `ModelPicker`（L410）与 `ThinkingPicker`（L424），注释明确 creator-only session config（L401-403）；`ChatInputCore` 使用点（L436，draftAdapter/onSend/onUploadFile/onStop/isRunning/disabled=running） |
| `PATCH /chat/config` 已交付（CR-A） | `server/cmd/server/router.go` L2078、`server/internal/handler/project_chat.go` L87 |
| 上传中禁发/发送/停止/失败重试位于 `ChatInputCore` | `chat-input.tsx` L870 `pendingUploads` 显式计数；L1140 `SubmitButton disabled` 含 `pendingUploads > 0`；L1142-1143 `running`/`onStop`；L1144-1147 send/stop tooltip（含快捷键格式化） |
| CR-A 已归档并回写基线 | kb `change-requests/_index.yml`：CR-2026-056「会话级配置与 Team Agent 闭环」status=archived，writeback-spec-id=ai-first-platform；`specs/ai-first-platform/PRD.md`、`SDD.md` 含会话配置内容 |
| 来源文档已入库 | kb `docs/product/Multica聊天会话级配置与Discussion方案.md`：§12 CR-D（FR-29~33、包含/不包含范围、完成标志）、§13「发送框 UI」（AC-30~35） |

## 1.5 修订记录

- 初稿（2026-09-09）：按来源文档 CR-D 段与注册摘要起草，代码事实在 multica requirement worktree HEAD `117fc6be` 核实。

# 2. 用户故事

- **US-1 Team Agent 用户（项目 owner/admin）**：作为项目负责人，我希望 Team Agent 发送框和普通聊天长得一样、模型和思考模式在底部工具栏随手可调，而不是一眼看出两套输入框。
- **US-2 Team Agent 普通成员**：作为项目普通成员，我希望 UI 调整后模型/思考模式仍以只读形式展示，我无法通过 UI 越权修改会话配置（权限仍在服务端强制）。
- **US-3 Private Ask 用户**：作为使用 Private Ask 的项目成员，我希望模型/思考模式调整只影响我自己的会话，UI 重构后这个隔离不因布局变化而改变。
- **US-4 窄面板用户**：作为在窄项目面板或小浮窗里聊天的用户，我希望发送框不横向溢出，输入区、附件预览、配置控件和发送/停止按钮互不遮挡。
- **US-5 键盘/无障碍用户**：作为依赖键盘和屏幕阅读器的用户，我希望发送框保留可访问名称、tooltip、键盘发送（Mod+Enter）和运行中停止能力。
- **US-6 既有用户**：作为已经习惯 Team Agent/Private Ask 的用户，我希望草稿、附件、发送、停止、失败重试行为和以前完全一致，这次升级只是视觉和布局变化。

# 3. 功能需求

## FR-1 发送框布局对齐普通非项目聊天（来源 FR-29）

Team Agent 和 Private Ask 的发送框采用与普通非项目聊天一致的 composer 布局语言：container-aware gutter（`CHAT_GUTTER`）→ centered width-capped input surface（`CHAT_COLUMN`），消息列与发送框边缘对齐；项目窄面板使用容器宽度，不依赖浏览器 viewport 断点。不另建一套并行 composer 视觉体系。实现复用 `chat-column.ts` 的既有定义与容器语义（先例见 §1.4），不复制第二份常量。

## FR-2 单一输入 surface（来源 FR-29、FR-30）

两侧项目聊天发送框复用 `ChatInputCore` 的单一输入 surface：边框、背景、focus-within 状态、圆角和内部滚动与普通非项目聊天保持一致；输入区、附件预览、底部工具栏分层，长文本在输入区内部滚动，不能把发送按钮顶出面板。UI 优化必须保留现有 `ChatInputCore`、draft adapter、草稿附件、上传状态、发送中、停止和失败重试行为。

## FR-3 配置控件作为底部工具栏控件（来源 FR-31）

Model Picker 和 Thinking Mode 控件作为发送框底部工具栏的一部分呈现（`leftAdornment` 或等价底部工具栏 slot，先例见 §1.4）；不再单独占据发送框上方的一整行，除非窄屏布局确实需要换行（换行时保持工具栏整体换行，不挤压输入区）。

控件操作仍调用会话配置接口（`PATCH /chat/config`，CR-2026-056 交付），**不得改变 Agent 配置**：不得从聊天路径调用 `api.updateAgent`，`agent.model`/`agent.thinking_level` 不被聊天操作修改。权限门禁保持不变：Team Agent 中 owner/admin 可编辑、普通成员只读徽标；Private Ask 中 creator-only 会话配置语义不变；runtime 不可用时保持现有 guide 提示行为。

## FR-4 窄屏与双端不溢出、不遮挡（来源 FR-32）

发送框在窄项目聊天面板、桌面端和 Web 端保持内容不横向溢出；输入区、附件状态（预览/上传中）、配置控件和发送/停止按钮不得互相遮挡。窄屏下配置控件在工具栏内换行或折叠，不允许挤压输入区导致其不可用。

## FR-5 视觉状态一致性（来源 FR-30、AC-33）

附件预览、上传中（禁发）、发送中、停止、失败重试、空态等视觉状态与普通非项目聊天保持一致；右下角复用普通聊天的发送/停止按钮及 loading、上传中、运行中状态。Team Agent 和 Private Ask 继续使用各自的 draft adapter、项目草稿隔离和 pending-message 模式，不接入普通聊天的全局 session store（`ChatInputCore` 自身不接触 `useChatStore` 的结构事实保持不变，见 §1.4）。

## FR-6 可访问性保持（来源 AC-35）

可访问名称、tooltip 与键盘发送（Mod+Enter，运行中可停止）行为保持可用；布局调整不得移除或破坏现有控件语义（配置控件仍可通过键盘聚焦与操作）。

## FR-7 不新增数据与业务语义（来源 FR-33、AC-34）

本 CR 不新增会话、任务、附件或 Discussion 数据模型；不新增 API、数据库字段、任务快照逻辑；不改变 draft、attachment、send、stop、retry 的业务行为；不修改 Team Agent、Private Ask、Discussion 的权限和发送事务。业务语义由已归档功能 CR（CR-A/CR-B/CR-C）提供，本 CR 只做视觉与布局。

## FR-8 共享组件适配与测试（来源完成标志）

Web 与 Desktop 共享组件适配（两平台共用 `packages/views` 实现，不做平台分支视觉）；交付对应组件测试与必要的 Playwright 截图/交互验证（含窄面板回归）；并输出与普通非项目聊天布局的差异说明，仅记录必要差异（完成标志）。

# 4. 非功能需求

- **NFR-1 双端一致**：Web 与 Desktop 共享 `packages/views` 组件，行为与视觉一致；mobile 不在本 CR 范围。
- **NFR-2 无障碍**：控件保留可访问名称与 tooltip；键盘发送/停止可用；布局调整不降低焦点可见性与对比度。
- **NFR-3 文案**：优先复用现有控件与文案 key，不为此 UI 调整新增文案；若实现确实需要新 key，须 en/ja/ko/zh-Hans 四语对称且 `packages/views/locales/parity.test.ts` 全绿。
- **NFR-4 性能与依赖**：不引入新 UI 组件库、不引入新状态管理；配置控件状态仍由现有会话配置数据源驱动，不为布局调整新增重复请求。
- **NFR-5 兼容**：不改造普通非项目聊天的现有视觉基线；对共享组件的任何修改只做保证项目聊天兼容所需的最小调整；普通聊天、Team Agent、Private Ask、Discussion 的既有测试不回归。

# 5. 验收标准

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-1 | 来源 AC-30 | Team Agent 和 Private Ask 发送框均复用普通非项目聊天的 composer 布局语言（`CHAT_GUTTER`/`CHAT_COLUMN`），不出现两套互不一致的输入框结构。组件测试断言两处 composer 应用与 `chat-column.ts` 相同的 gutter/column 规则；Playwright 截图对比宽面板下发送框边缘与消息列边缘对齐。 |
| AC-2 | FR-2 | 来源 AC-30 | 单一输入 surface：边框、背景、focus-within、圆角、内部滚动与普通非项目聊天一致；组件测试/截图对照 `chat-input.tsx` 的 surface 结构与状态样式，长文本在输入区内部滚动且发送按钮不被顶出面板。 |
| AC-3 | FR-4 | 来源 AC-31 | 发送框在窄项目面板（含 360px 浮窗场景）中不发生横向溢出；输入区、附件预览、配置控件和发送/停止按钮不重叠。Playwright 窄面板回归 + 截图断言通过。 |
| AC-4 | FR-3 | 来源 AC-32 | Model Picker 和 Thinking Mode 位于底部工具栏或其窄屏换行布局中；功能调用目标仍是会话配置接口：操作后 `agent.model`/`agent.thinking_level` 不变（沿用 CR-2026-056 AC-1/AC-2 口径），会话配置经 `PATCH /chat/config` 持久化生效；普通成员仍为只读徽标，Private Ask 仍 creator-only。 |
| AC-5 | FR-5 | 来源 AC-33 | 普通聊天已有的附件上传、上传中禁发、发送中、停止、失败重试和草稿保留行为不回归：既有 chat-input/项目聊天测试全绿，且新增/更新项目聊天发送框组件测试覆盖上述每个状态。 |
| AC-6 | FR-5、FR-7 | 来源 AC-34 | Team Agent 和 Private Ask 的 draft adapter、项目隔离和 pending-message 状态不因 UI 调整而改用全局聊天 store：代码评审确认两处仍注入各自 draftAdapter，pending-message 渲染行为不变（现有 `project-chat-pending-message`/`private-ask-pending-message` 语义保持）。 |
| AC-7 | FR-6、FR-8 | 来源 AC-35 | Web/Desktop 共享视图通过组件测试和窄面板回归检查；可访问名称、tooltip 和键盘发送行为可用（组件测试/可访问性断言，含运行中停止）。 |
| AC-8 | FR-7、FR-8 | 来源 FR-33、完成标志 | 交付 diff 中无新增 API 路由、无新增 `server/migrations/` 迁移、无任务快照逻辑或数据模型变更；普通非项目聊天视觉基线不变化（截图基线对比）；差异说明文档记录必要差异，且每项差异有明确理由。 |

来源完成标志要求 FR-29 至 FR-33 和 AC-30 至 AC-35 全部满足：AC-1/AC-2 对应来源 AC-30（composer 布局语言复用、单一输入 surface），AC-3 对应 AC-31（窄面板不溢出不重叠），AC-4 对应 AC-32（配置控件入底部工具栏、调用目标仍为会话配置接口），AC-5 对应 AC-33（附件/上传/发送/停止/失败/草稿行为不回归），AC-6 对应 AC-34（draft adapter、项目隔离、pending-message 不用全局 store），AC-7 对应 AC-35（组件测试、窄面板回归、可访问名称/tooltip/键盘发送）。FR-1~FR-8 分别覆盖来源 FR-29~FR-33 及来源「完成标志」的差异说明与测试交付要求。

# 6. 成功指标

- Team Agent 与 Private Ask 发送框与普通非项目聊天 composer 之间的非必要布局差异数 = 0（必要差异以差异说明文档为准，均有明确理由）。
- 窄面板（360px 浮窗/窄项目面板）横向溢出与控件遮挡缺陷数 = 0。
- UI 调整导致的 draft/attachment/send/stop/retry 行为回归数 = 0。
- 因 UI 调整新增的 API / 数据库迁移 / 数据模型 = 0。
- 普通非项目聊天视觉基线变化 = 0。
- 发送框对齐与视觉一致性截图验收通过率 = 100%。

# 7. 范围排除

以下内容明确不做，归属后续 CR 或明确非目标：

- 新增 API、数据库字段或任务快照逻辑（来源 FR-33）。
- 修改 Team Agent、Private Ask、Discussion 的权限和发送事务。
- 改造普通非项目聊天的现有视觉基线。
- 引入新的 UI 组件库或新的状态管理方式。
- 修改普通聊天 `ChatInput` 的既有业务语义；如需改共享组件，只做保证项目聊天兼容所需的最小调整。
- Discussion UI 变化混入本 CR（Discussion 视觉改造不属于 CR-D，来源文档「CR 顺序和边界」）。
- 会话配置服务端字段与功能接口本身（由 CR-2026-056 提供，本 CR 只消费）。
- mobile 端。
- 对 Team Agent / Private Ask 的队列、presenter、附件上传管线等业务逻辑的任何行为改动。
