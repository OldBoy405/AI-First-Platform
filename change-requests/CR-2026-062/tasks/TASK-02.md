---
id: CR-2026-062-TASK-02
type: TASK
cr-ref: CR-2026-062
plan-ref: "change-requests/CR-2026-062/plan.md"
sdd-ref: "change-requests/CR-2026-062/sdd.md"
target-version: 0.35
title: Team Agent 面板对齐与运行中停止（消息流/队列栏/横幅两层 + @container + 工具栏 + 双源停止）
slug: team-agent-chat-composer-alignment
status: pending
estimate: 20h
depends-on: [CR-2026-062-TASK-01]
created: 2026-09-09T21:14:52+08:00
---

## 1. 任务描述

在 multica CR worktree（HEAD `117fc6be657f91d43df5892b52782a18329c7aed`）完成 Team Agent 侧对齐：消息流根/队列栏/横幅区全部改为「外层 `CHAT_GUTTER` > 内层 `CHAT_COLUMN`」两层 DOM；`ModePane` 根加 `@container`；`project-chat-model-row` 独立行移除、Model/Thinking 控件经 `leftAdornment` 进底部工具栏（三态与 testid 保留、sr-only 类别标签）；接入**可执行的运行中停止路径**（双源活动性判定：queue items ∪ 容器 Issue 任务时间线），消费 TASK-01 的 ChatInputCore 对齐基座。

输入：已审批 SDD §3.2（Team Agent 工具栏）、§4.1（规则 3/4/5/6）、§4.3/§4.3.1、§4.4、D-7、§6 AC-1/AC-3/AC-4/AC-5、§6.9 测试计划 2、既有实现依赖 #4/#7/#8/#13~#21、plan.md §6 证据命令表。

## 2. 涉及文件 / 模块

- `packages/views/projects/components/project-team-agent-chat.tsx`（修改：`TeamAgentStreamView` 根两层、`TeamAgentComposer` wrapper/横幅区、model-row 移除 + `leftAdornment` 工具栏、停止路径状态与双源判定）
- `packages/views/projects/components/project-chat-panel.tsx`（修改一行：`ModePane` 根 `"flex h-full flex-col p-4"` → 加 `@container`）
- `packages/views/projects/components/project-queue-bar.tsx`（修改最小：根 `px-4` 移除、内部两层 DOM）
- 测试：`packages/views/projects/components/project-team-agent-chat.test.tsx`、`project-chat-panel.test.tsx`、`project-queue-bar.test.tsx`（修改/新增套件）

## 3. 实现要点（SDD 对应节，逐字对齐）

- **消息流根两层（§4.1 规则 3，B-001）**：`"mx-auto flex w-full max-w-3xl flex-col gap-4 px-4 py-3"` 拆为外层 `<div className={cn(CHAT_GUTTER)}>` + 内层 `<div className={cn(CHAT_COLUMN, "flex flex-col gap-4 py-3")}>`。**禁止** `cn(CHAT_GUTTER, CHAT_COLUMN, …)` 单元素合并（gutter 计入 max-w-4xl 封顶的历史错位形态）。
- **`ModePane` @container（§4.1 规则 4）**：`project-chat-panel.tsx` L199 根 div 加 `@container`（`@2xl`/`@4xl` 变体按面板宽度生效；Discussion 面板同用 ModePane，无 @ 变体使用方，零影响）。
- **队列栏两层（§4.1 规则 5）**：根 `"shrink-0 border-t px-4 py-2"` → 根保持 `shrink-0 border-t`（`data-testid="project-queue-bar"` 保留），内部外层 `<div className={cn(CHAT_GUTTER)}>` + 内层 `<div className={cn(CHAT_COLUMN, "py-2")}>`（toggle + expanded list 内容与交互零改动）。
- **composer 外层与横幅区（§4.1 规则 6）**：wrapper `"shrink-0 border-t px-4 py-3"` → `"shrink-0 border-t"`；横幅区（pending-message / presenter-required / queue-full）迁入两层块：外层 `cn(CHAT_GUTTER, "pt-3")`、内层 `cn(CHAT_COLUMN)`（无横幅时该块仍渲染，保留 pt-3 顶部间距）；横幅右缘与 surface 右缘一致。
- **工具栏 leftAdornment（§3.2，B-002）**：按 SDD §3.2 TeamAgentComposer 片段逐字构造 `toolbar`——三态分支（`project-chat-model-readonly` / `project-chat-model-picker` / `project-chat-model-runtime-guide`）与 `project-chat-thinking-picker` 全部保留；可见文字 label 不再渲染，以 `<span className="sr-only">{t(($) => $.chat.stream.model_label)}</span>` / `thinking_label` 补类别语义（只读 chip 为纯 `<span>`+title，无类别可访问名称）；`thinkingLevels.length > 0` 条件保留。`persistModel`/`persistThinking` 函数体零改动（仍走 `patchProjectChatConfig`，不得从聊天路径调用 `api.updateAgent`）。
- **停止路径（§4.3.1，B-003 v2）**：
  - `sentTaskId`/`sentIssueId`：`useSendProjectChatMessage(...).mutateAsync()` 成功返回值 `ProjectChatSendResult.task_id`/`issue_id`（schemas.ts L1524-1529），组件内 `useState` 保存。**确定性转移**：发送成功且任一 ID 无效（空）→ **原子清空两个 ID**；发送失败（mutation reject，`handleSend` catch 返回 false，成功行 setState 未执行）→ **保留**旧值。
  - `taskInItems`：`useQuery(projectQueueItemsOptions(wsId, projectId)).data.items` 中是否存在 `task_id === sentTaskId`（items 服务端过滤 queued/dispatched，依赖 #16/#21）。
  - `taskEntry`：`useQuery({ queryKey: issueKeys.tasks(sentIssueId), queryFn: () => api.listTasksByIssue(sentIssueId), staleTime: 30_000, enabled: !!sentIssueId })`（与 TeamAgentStreamView L98-102 同 query key，缓存收敛去重；`sentIssueId` 取自发送响应，不依赖面板 `chat.issue_id` 刷新）。
  - `taskActive`：`taskEntry != null && ACTIVE.has(taskEntry.status)`，`ACTIVE = { queued, dispatched, waiting_local_directory, running }`；`taskTerminal`：`TERMINAL = { completed, failed, cancelled }`（与 types/agent.ts L286-298 分桶口径一致，依赖 #18）。
  - `trackedActive = (taskInItems || taskActive) && !taskTerminal`；`isRunning = trackedActive`；`onStop = handleStop`：`cancelTask.mutateAsync(sentTaskId)`（`useCancelProjectQueueTask`，TSUG-007 三支：cancelled → 静默成功；其他终态 → `toast.error(chat.stream.cancel_already_finished)`；ApiError → `toast.error(e.message)`）。
  - 传 `allowSubmitWhileRunning={true}`（运行中可续发，FR-7 不回归）。入队窗口（mutation in-flight）：`isRunning=false`，ChatInputCore 内部 `isSubmitting` 显示 loading。
  - **可见动作（与 TASK-01 判定式一致）**：发送失败保草稿（`isEmpty=false`）+ `allowSubmitWhileRunning=true` ⇒ `running=false` → 渲染发送（重试）按钮；**清空草稿后 stop 重新出现**并可取消保留的旧目标（AC-5(h)/§6.9(iii) 落点）。
- **zero_diff 红线（§9）**：`handleComposerUpload`/`persistModel`/`persistThinking` 函数体、`handleSend` 业务语义（唯一新增：成功后按确定性转移记录 `sentTaskId`/`sentIssueId`）、既有 testid 系列零改动。
- 行尾纪律（AGENTS.md #1）：修改文件保持仓库既有行尾（git 检出后按 LF 规范化处理）。

## 4. 验收条件

1. `node node_modules/vitest/vitest.mjs run projects/components/project-team-agent-chat.test.tsx projects/components/project-chat-panel.test.tsx projects/components/project-queue-bar.test.tsx`（cwd packages/views）全绿：消息流根/队列栏「外层 GUTTER 节点与内层 COLUMN 节点分离」两层断言；控件 testid（`project-chat-model-picker`/`project-chat-model-readonly`/`project-chat-model-runtime-guide`/`project-chat-thinking-picker`）位于 composer 子树；既有三态与 PATCH 断言保持；sr-only 类别标签（model_label/thinking_label 文案）存在。
2. 双源矩阵七态（§6.9-2）：mock `listTasksByIssue` 返回含 `sentTaskId` 的 task-runs（queued/dispatched/**running**/waiting_local_directory/completed/failed/cancelled 各一例），mock queue items 按服务端口径只放 queued/dispatched——断言 queued/dispatched 时 stop 出现（发送成功后草稿已清空、`isEmpty=true`）；**running 且 items 不含该 task 时 stop 仍出现**（任务时间线单独支撑）；终态时按钮回发送态（终态覆盖陈旧 items 残留）；点击 stop 调用 `cancelTaskById(task_id)`；非 cancelled 终态 → `cancel_already_finished` toast。
3. 硬降级矩阵（§6.9-2，cycle 2）：（i）首次发送即返回空 `task_id`/`issue_id` → 两个 sent ID 原子清空、不渲染死按钮；（ii）**顺序分支**：活动 A（有效 sent ID、stop 渲染）→ 下一次发送成功返回空 `task_id` → stop 消失、发送态恢复且**不调用 `cancelTaskById(A)`**；（iii）发送失败（mutateAsync reject）→ 草稿保留、旧活动目标保留；断言渲染**发送（重试）按钮**（无 stop Square/stop_tooltip 名称）；随后清空草稿 → stop 重新渲染、点击仍调用 `cancelTaskById(A)`。
4. `ModePane` 根含 `@container`；queue-bar 既有 toggle/展开/取消交互与 chat-panel 既有测试零回归。
5. `node node_modules/typescript/bin/tsc --noEmit -p .`（cwd packages/views）零错误。

## 5. 完成标志

- 上述 5 条验收全部通过；`persistModel`/`persistThinking`/`handleComposerUpload`/`handleSend` 业务语义 diff 白名单核对（仅新增 sent 状态记录语句）；
- 提交落盘 multica CR 分支（独立 commit、可单独 revert）；multica `CUSTOM.md` 按当时实际结构登记本 TASK 的修改文件（project-team-agent-chat.tsx、project-chat-panel.tsx、project-queue-bar.tsx 及对应测试文件）；
- canonical 证据为 plan §6.2 cmd-02 与 cmd-05。

## 6. 接口契约

**消费**：

- CR-2026-062-TASK-01 产出：`ChatInputCore` props 签名不变、`leftAdornment?: ReactNode` slot（渲染于底栏左组）、surface `data-slot="chat-input-surface"`、可见动作判定 `running = !!isRunning && (!allowSubmitWhileRunning || isEmpty || pendingUploads > 0)`、发送/停止按钮 accessible name 已由 ChatInputCore 内部传参补齐。
- 既有只读契约（本 TASK 不改，zero_diff）：`useSendProjectChatMessage` → `{ mutateAsync, isPending }`（mutations.ts L63-77）；`ProjectChatSendResult.task_id`/`issue_id`（schemas.ts L1524-1529）；`projectQueueItemsOptions`（queries.ts L59）；`issueKeys.tasks(issueId)`（issues/queries.ts L179）；`api.listTasksByIssue`（client.ts L2478）；`useCancelProjectQueueTask.mutateAsync(taskId)`（mutations.ts L93-106，TSUG-007 三支）；`patchProjectChatConfig`（client.ts L3722）；`AgentTask.status` 联合（types/agent.ts L291-298）。

**产出**（供 CR-2026-062-TASK-03/04 消费）：

- `ModePane` 根 `@container` 祖先（项目面板级容器查询前提；TASK-03 的 gutter 变体依赖此前置）。
- Team Agent composer 最终行为口径（供 e2e spec）：queued/dispatched/running/waiting_local_directory 期间草稿空/上传中渲染 stop、草稿非空渲染发送（queue send）；终态回发送态；发送失败保草稿 → 发送（重试）按钮、清空草稿 → stop 重新出现并取消保留目标；硬降级（空 ID）→ 无运行态不渲染死按钮。
- 工具函数形态（组件内，非导出契约）：`handleStop = () => cancelTask.mutateAsync(sentTaskId)`；判定式 `trackedActive = (taskInItems || taskActive) && !taskTerminal`。
