---
id: CR-2026-062-TASK-03
type: TASK
cr-ref: CR-2026-062
plan-ref: "change-requests/CR-2026-062/plan.md"
sdd-ref: "change-requests/CR-2026-062/sdd.md"
target-version: 0.35
title: Private Ask 面板对齐（横幅两层 + leftAdornment 工具栏 + 停止路径原样）
slug: private-ask-chat-composer-alignment
status: pending
estimate: 12h
depends-on: [CR-2026-062-TASK-01, CR-2026-062-TASK-02]
created: 2026-09-09T21:14:52+08:00
---

## 1. 任务描述

在 multica CR worktree（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`）完成 Private Ask 侧对齐：composer wrapper 外层对齐、pending-message 横幅区迁入「外层 `CHAT_GUTTER` > 内层 `CHAT_COLUMN`」两层块；`private-ask-model-row` 独立行移除、Model/Thinking 控件经 `leftAdornment` 进底部工具栏（creator-only 语义与 sr-only 类别标签）；停止路径（`pendingTaskId → api.cancelTaskById`）与 `disabled=running` 原样不动。消费 TASK-01 的 ChatInputCore 对齐基座与 TASK-02 的 `ModePane @container` 前置。

输入：已审批 SDD §3.2（PrivateAskComposer 片段）、§4.1（规则 6）、§4.3（停止路径原样行）、§6 AC-1/AC-4、§6.9 测试计划 2、既有实现依赖 #5/#9、plan.md §6 证据命令表。

## 2. 涉及文件 / 模块

- `packages/views/projects/components/project-private-ask.tsx`（修改：`PrivateAskComposer` wrapper/横幅区、model-row 移除 + `leftAdornment` 工具栏）
- `packages/views/projects/components/project-private-ask.test.tsx`（修改/新增套件）

## 3. 实现要点（SDD 对应节，逐字对齐）

- **composer wrapper（§4.1 规则 6）**：`"shrink-0 border-t px-4 py-3"`（L392）→ `"shrink-0 border-t"`。
- **横幅区两层块（§4.1 规则 6）**：`private-ask-pending-message` 迁入两层块——外层 `cn(CHAT_GUTTER, "pt-3")`、内层 `cn(CHAT_COLUMN)`（无横幅时该块仍渲染，保留 pt-3 顶部间距）；pending-message 的 testid/渲染条件零改动；横幅右缘与 surface 右缘一致。
- **工具栏 leftAdornment（§3.2，B-002）**：按 SDD §3.2 PrivateAskComposer 片段逐字构造 `toolbar`——`agent` 非空渲染 `private-ask-model-picker`；**testid 契约（§9 移除清单第 1 项）**：`private-ask-model-row` testid 随独立行**一并移除、不迁移**，替换锚点为新增 `private-ask-model-picker`；`private-ask-thinking-picker` 保留；可见文字 label 不再渲染，以 `<span className="sr-only">{t(($) => $.chat.stream.model_label)}</span>` / `thinking_label` 补类别语义；`thinkingLevels.length > 0` 条件保留。`persistModel`（L327）/`persistThinking`（L340）函数体零改动（仍走 `patchChatSessionConfig`，creator-only 服务端 403 语义不变）。
- **ChatInputCore 使用点（L436）**：`draftAdapter/onSend/onUploadFile/onStop/isRunning/disabled=running` 原样；**不传** `allowSubmitWhileRunning`（行为与现状逐位一致，§3.2）；停止路径 `pendingTaskId → api.cancelTaskById` 原样不动（§4.3 状态映射表「Private Ask：原样」）。
- **zero_diff 红线（§9）**：`persistModel`/`persistThinking` 函数体、draft adapter、pending-message 语义、testid 系列（除 `private-ask-model-row` 移除对应的 `private-ask-model-picker` 定位调整）零改动。
- 行尾纪律（AGENTS.md #1）：修改文件保持仓库既有行尾（git 检出后按 LF 规范化处理）。

## 4. 验收条件

1. `node node_modules/vitest/vitest.mjs run projects/components/project-private-ask.test.tsx`（cwd packages/views）全绿：`private-ask-model-picker`/`private-ask-thinking-picker` 位于 composer 子树；sr-only 类别标签（model_label/thinking_label 文案）存在；creator-only 可编辑语义与 PATCH 断言（`patchChatSessionConfig`）保持且无 `updateAgent` 调用。
2. 横幅区两层 DOM 断言：外层 GUTTER 节点与内层 COLUMN 节点分离；`private-ask-pending-message` 仍按原条件渲染（AC-6 pending-message 面）。
3. 停止路径回归：`running` 时 `onStop` 仍触发 `api.cancelTaskById`（现状行为逐位一致，无新增 sent 状态/双源逻辑）。
4. 未传 `allowSubmitWhileRunning` 时运行中发送被拦（现状行为，由 TASK-01 判定式保证，此处回归断言）。
5. `node node_modules/typescript/bin/tsc --noEmit -p .`（cwd packages/views）零错误。

## 5. 完成标志

- 上述 5 条验收全部通过；`persistModel`/`persistThinking`/停止路径 diff 白名单核对（零业务语义改动）；
- 提交落盘 multica CR 分支（独立 commit；回滚单元按 plan §4.0 **RU2**——连带消费其行为的 TASK-04，逆拓扑 revert 04→03，非单独 revert）；multica `CUSTOM.md` 按当时实际结构登记本 TASK 的修改文件（project-private-ask.tsx 及测试文件，治理 sidecar 受控例外）；
- canonical 证据为 plan §6.2 cmd-02 与 cmd-06。

## 6. 接口契约

**消费**：

- CR-2026-062-TASK-01 产出：`ChatInputCore` props 签名不变、`leftAdornment?: ReactNode` slot、surface `data-slot="chat-input-surface"`、可见动作判定 `running = !!isRunning && (!allowSubmitWhileRunning || isEmpty || pendingUploads > 0)`（本 TASK 不传 `allowSubmitWhileRunning` → 运行中恒渲染 stop，与现状一致）。
- CR-2026-062-TASK-02 产出：`ModePane` 根 `@container` 祖先（本 TASK gutter 变体生效前提）。
- 既有只读契约（本 TASK 不改，zero_diff）：`patchChatSessionConfig`（client.ts L3783，`PATCH /api/chat/sessions/:id/config`，creator-only 403）；`api.cancelTaskById`（client.ts L3569，POST /api/tasks/:id/cancel）；locale key `chat.stream.model_label`/`thinking_label`。

**产出**（供 CR-2026-062-TASK-04 消费）：

- Private Ask composer 最终行为口径（供 e2e spec/差异文档）：composer surface 与消息列边缘对齐（两层 DOM）；工具栏 Model/Thinking chip 位于底栏左组（creator-only）；运行中 stop 原样（`pendingTaskId → api.cancelTaskById`）；不引入 `allowSubmitWhileRunning`。
