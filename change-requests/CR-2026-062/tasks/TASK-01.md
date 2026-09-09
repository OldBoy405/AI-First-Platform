---
id: CR-2026-062-TASK-01
type: TASK
cr-ref: CR-2026-062
plan-ref: "change-requests/CR-2026-062/plan.md"
sdd-ref: "change-requests/CR-2026-062/sdd.md"
target-version: 0.35
title: ChatInputCore 共享 composer 视觉对齐（两层 DOM + flow 底栏 + 可访问名称 + allowSubmitWhileRunning）
slug: chat-input-core-composer-alignment
status: pending
estimate: 16h
depends-on: []
created: 2026-09-09T21:14:52+08:00
---

## 1. 任务描述

在 multica CR worktree（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-062`，基线 HEAD `117fc6be657f91d43df5892b52782a18329c7aed`）改造 `ChatInputCore`：wrapper/surface 采用「外层 `CHAT_GUTTER` > 内层 `CHAT_COLUMN`」两层 DOM、surface 类名集合对齐 `ChatInput`、底栏 absolute→flow 布局、`SubmitButton` 调用补传 `ariaLabel`/`stopAriaLabel`、采纳 `ChatInputProps` 既有 `allowSubmitWhileRunning` 字段。**props 签名零变化、`ChatInput`（全局）函数体零 diff**（SDD §9 zero_diff）。本 TASK 产出 TASK-02/03 的对齐基座。

输入：已审批 SDD §3.2、§4.1（规则 1/2）、§4.2、§4.4、§6 AC-1/AC-2/AC-5/AC-7、§6.9 测试计划 1、§9 zero_diff、既有实现依赖 #1/#2/#3/#11、plan.md §6 证据命令表。

## 2. 涉及文件 / 模块

- `packages/views/chat/components/chat-input.tsx`（修改，**仅 `ChatInputCore` 函数体**；`ChatInput`（全局）函数体与 `ChatInputProps` 接口签名零 diff）
- `packages/views/chat/components/chat-input.test.tsx`（修改：ChatInputCore 新增套件 + 既有套件全绿不回归）
- 只读复用（零改动）：`packages/views/chat/components/chat-column.ts`（`CHAT_GUTTER`/`CHAT_COLUMN`）、`packages/ui/components/common/submit-button.tsx`、`packages/ui/.../chat-add-menu`、`packages/views/editor`（ContentEditor）

## 3. 实现要点（SDD 对应节，逐字对齐）

- **wrapper（外层 gutter，§4.1 规则 1）**：`"px-5 pb-3 pt-0"` → `cn(CHAT_GUTTER, "pb-3 pt-0", noAgent && "cursor-not-allowed")`。
- **surface（内层 column，§4.1 规则 2）**：`"relative mx-auto flex min-h-16 max-h-40 w-full max-w-4xl flex-col rounded-lg bg-card pb-9 border-1 border-border transition-colors focus-within:border-brand"` → `cn(CHAT_COLUMN, "relative flex min-h-16 max-h-40 flex-col rounded-lg border border-surface-border bg-surface transition-[border-color,box-shadow] focus-within:border-brand focus-within:ring-2 focus-within:ring-ring/20", noAgent && "pointer-events-none opacity-60")`，并补 `data-slot="chat-input-surface"`（与 `ChatInput` L651 对齐，供截图/测试共用选择器）。wrapper 与 surface 保持两个 DOM 层，**禁止** `cn(CHAT_GUTTER, CHAT_COLUMN, …)` 单元素合并。
- **编辑器区（§4.2）**：`flex-1 min-h-0 overflow-y-auto px-3 py-2` → `flex-1 min-h-8 overflow-y-auto px-3 py-2`（显式 `min-h-8` 地板，底栏换行时输入区仍可操作；不与 `min-h-0` 并写）。
- **底栏 flow（§4.2，替换两处 absolute 行 L1128/L1137）**：surface 由 `pb-9` 改 `pb-0`；底栏 `flex items-center justify-between gap-2 px-1.5 pb-1.5`；左组 `(uploadEnabled || leftAdornment) && <div className="flex min-w-0 flex-1 flex-wrap items-center gap-1">{uploadEnabled && <ChatAddMenu …/>}{leftAdornment}</div>`；右组 `<div className="flex shrink-0 items-center gap-1"><SubmitButton …/></div>`。换行算法 = CSS flex-wrap 自身，无 JS 测量、无 ResizeObserver、无状态机。
- **SubmitButton 调用（§4.2 + §3.2-1，B-002）**：补传 `ariaLabel={t(($) => $.input.send_tooltip)}`、`stopAriaLabel={t(($) => $.input.stop_tooltip)}`（与 `ChatInput` L778/L782 完全同 key 同语义，无新文案 key）；`running={!!isRunning && (!allowSubmitWhileRunning || isEmpty || pendingUploads > 0)}`（可见动作单一判定式，§4.2 口径）；`disabled` 保留 `pendingUploads > 0` 项。
- **`allowSubmitWhileRunning` 采纳（§3.2-2）**：解构 `ChatInputProps` 既有字段 `allowSubmitWhileRunning?: boolean`（L102，此前未使用，签名零变化）；`handleSend` 门禁的 `isRunning` 项改为 `isRunning && !allowSubmitWhileRunning`。可见动作口径（单一事实）：`isRunning=true` 时草稿非空且无上传中 → `running=false` 渲染发送（queue send；失败保草稿后即重试按钮）；草稿空或上传中 → 渲染 stop。
- **zero_diff 红线（§9）**：不改 `ChatInput` 函数体、`ChatInputProps` 签名、`ChatInputCoreProps` 签名、`ChatInputDraftAdapter`、`handleSend` 的业务语义（失败保草稿 catch L1039-1046、成功 `commitInput()`+`setIsEmpty(true)` L1014 原样）；「never touches useChatStore」结构事实（L856）保持。
- 行尾纪律（AGENTS.md #1）：修改文件保持仓库既有行尾（git 检出后按 LF 规范化处理）。

## 4. 验收条件

1. `node node_modules/vitest/vitest.mjs run chat/components/chat-input.test.tsx`（cwd packages/views）全绿：既有 `ChatInput`/`ChatInputCore` 套件零回归 + 新增断言——wrapper（外层）含 `CHAT_GUTTER`、surface（内层）含 `CHAT_COLUMN` 且二者为不同 DOM 节点；`data-slot="chat-input-surface"`；surface token（`border-surface-border`/`bg-surface`/`rounded-lg`/`focus-within:ring-2`）；底栏 flow 结构（左组 wrap + 右组 shrink-0）；`leftAdornment` 渲染于左组。
2. a11y 断言：发送按钮 accessible name = `input.send_tooltip` 文案；`running + onStop` 时停止按钮 accessible name = `input.stop_tooltip` 文案（`submit-button.tsx` ArrowUp/Square 均 aria-hidden，不补传则无名称，§3.2-1）。
3. `allowSubmitWhileRunning` 行为断言：传 `true` 时运行中+有内容 → 发送可用且 `handleSend` 放行、空输入 → 停止；不传 → 运行中发送被拦（现状行为，Private Ask 依赖）。
4. adapter isolation 套件全绿（`useChatStore` 零订阅，AC-6 结构事实不回归）。
5. `node node_modules/typescript/bin/tsc --noEmit -p .`（cwd packages/views）零错误。

## 5. 完成标志

- 上述 5 条验收全部通过；`ChatInput`（全局）函数体与 `ChatInputProps`/`ChatInputCoreProps` 签名零 diff（diff 白名单核对）；
- 提交落盘 multica CR 分支（独立 commit；回滚单元按 plan §4.0 **RU4**——共享基座回滚须连带全部消费者，逆拓扑 revert 04→03→02→01，非单独 revert）；multica `CUSTOM.md` 按当时实际结构登记本 TASK 的修改文件（chat-input.tsx、chat-input.test.tsx，治理 sidecar 受控例外）；
- canonical 证据为 plan §6.2 cmd-01（chat-input.test.tsx 全量）与 cmd-06（packages/views typecheck）。

## 6. 接口契约

**消费**：

- `packages/views/chat/components/chat-column.ts`：`CHAT_GUTTER = "px-5 @2xl:px-8 @4xl:px-12"`、`CHAT_COLUMN = "mx-auto w-full max-w-4xl"`（import 复用，不复制第二份常量，SDD 依赖 #1）。
- `ChatInputProps.leftAdornment?: ReactNode`（L123）、`ChatInputProps.allowSubmitWhileRunning?: boolean`（L102）——既有字段，仅内部采纳。
- locale key：`input.send_tooltip`、`input.stop_tooltip`（四语既有，无新 key，SDD 依赖 #12 口径）。
- `SubmitButton` props：`loading/busy/running/onStop/tooltip/ariaLabel/stopTooltip/stopAriaLabel`（组件本体零改动，SDD 依赖 #11）。

**产出**（供 CR-2026-062-TASK-02/03 消费，props 签名不变）：

```tsx
// ChatInputCore 对外 props 签名保持 ChatInputCoreProps extends ChatInputProps（零变化）
// 新增可观测契约（渲染层）：
// 1) surface 节点带 data-slot="chat-input-surface"（两层 DOM：外层 CHAT_GUTTER、内层 CHAT_COLUMN）
// 2) 底栏左组渲染条件 (uploadEnabled || leftAdornment)；leftAdornment 渲染于左组
// 3) 可见动作判定（单一事实）：running = !!isRunning && (!allowSubmitWhileRunning || isEmpty || pendingUploads > 0)
//    —— isRunning=true 时草稿非空且无上传中 → 渲染发送（queue send / 失败重试）按钮；
//       草稿空或上传中 → 渲染 stop（onClick=onStop）
// 4) a11y 契约：发送/停止按钮 accessible name 恒为 input.send_tooltip / input.stop_tooltip 文案（本 TASK 内部传参）
// 5) handleSend 门禁：isRunning 拦截条件为 isRunning && !allowSubmitWhileRunning（未传字段时与现状逐位一致）
```
