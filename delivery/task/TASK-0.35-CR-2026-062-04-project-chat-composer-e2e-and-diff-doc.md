---
spec-id: ai-first-platform
version: "0.35"
id: CR-2026-062-TASK-04
type: TASK
cr-ref: CR-2026-062
plan-ref: "change-requests/CR-2026-062/plan.md"
sdd-ref: "change-requests/CR-2026-062/sdd.md"
target-version: 0.35
title: e2e 真跑交付与差异文档 + 全量回归与交付 diff 白名单核对
slug: project-chat-composer-e2e-and-diff-doc
status: pending
estimate: 16h
depends-on: [CR-2026-062-TASK-02, CR-2026-062-TASK-03]
created: 2026-09-09T21:14:52+08:00
---

## 1. 任务描述

在 multica CR worktree（HEAD 为 TASK-02/03 完成后的分支 HEAD）交付来源完成标志要求的两项收尾产物并做全量回归与范围核对：① 新增 e2e spec `e2e/project-chat-composer.spec.ts`（宽面板截图对齐、360px 窄面板回归、运行中停止交互、键盘发送），**必须真跑**作为 AC-1/AC-3/AC-5/AC-7 的浏览器行为证据；② 新增差异说明文档 `packages/views/projects/components/project-chat-composer-layout-diff.md`（SDD-CLOSE-04 五项大纲）；③ packages/views 全量 `vitest run`（稳定证据命令 cmd-04）；④ 交付 diff 白名单核对（受控 `crctl git diff --name-only`，cmd-08，**仅文件级职责**，AC-8）；⑤ **符号级 zero_diff 复核（cmd-09，B-006）**——name-only 文件清单不承担符号级证明，符号级证据由 TASK-01 入库的版本化检查器唯一承担。**不包含任何 pipeline 控制步骤**（merge/writeback/archive 由既有 CR 流程承载，审计走 approval.yml/merge-commits.yml/checkpoint 元数据）。

输入：已审批 SDD（`review-annotations/sdd.yml` PASS、subject-sha256 `5259087713930e7eee00bb6074ae0d4a3d78f9df4eb18d1256401e6afb5fdf28`）§5.6/D-6、SDD-CLOSE-04、§6.9-3 证据契约、§6 AC-1/AC-3/AC-5/AC-7/AC-8、§9 治理 sidecar（`CUSTOM.md` 受控例外）、plan.md §5/§6.2 证据命令表（cmd-03/04/05/06/07/08/09）。

## 2. 涉及文件 / 模块

- `e2e/project-chat-composer.spec.ts`（新建；multica 根 playwright.config.ts testDir=./e2e 自动发现）
- `packages/views/projects/components/project-chat-composer-layout-diff.md`（新建，英文，随 multica 仓提交）
- `CUSTOM.md`（multica 仓根，修改：登记本 TASK 新文件台账，治理 sidecar 受控例外）
- 测试入口（只跑，不改）：`packages/views` 全量 vitest、`packages/views/locales/parity.test.ts`、`scripts/check-ui-wildcard-exports.mjs`、`packages/views` typecheck、`packages/views/chat/components/chat-input-zero-diff.test.ts`（cmd-09）

## 3. 实现要点（SDD 对应节，逐字对齐）

- **e2e spec（§6.9-3，真跑口径）**：四组用例——(a) 宽面板截图：发送框表面边缘与消息列边缘对齐（差 < 1px 容差，AC-1），surface 与普通聊天视觉一致（AC-2）；(b) 窄面板 360px 回归：`scrollWidth <= clientWidth` 无横向溢出，输入区/附件预览/配置控件/发送停止按钮 boundingBox 无重叠 + 截图基线（AC-3）；(c) 运行中停止交互：Team Agent 发送后任务 running 期间右下角 stop 可用（草稿空）、点击后走取消（AC-5/§4.3.1）；(d) 键盘发送 Mod+Enter（AC-7）。复用 `e2e/helpers.ts`/`e2e/fixtures.ts` 既有模式；spec 不引入新依赖。**证据契约（B-002 上游已修）**：spec 必须**真跑**（`node node_modules/@playwright/test/cli.js test e2e/project-chat-composer.spec.ts`，cwd multica 根 = plan §6.2 cmd-07）作为 AC-1/AC-3/AC-5/AC-7 的浏览器行为证据；`--list` 仅用于实施期自检 spec 可解析/可发现，**不是证据、不得写入完成依据**。
- **环境契约（SDD §6.9-3）**：实施期在 `FRONTEND_ORIGIN`（或 `PLAYWRIGHT_BASE_URL`，playwright.config.ts baseURL 链）指向运行中的前端+服务端时真跑四组用例；环境无法建立 → 按 `ENVIRONMENT_MISMATCH` **技术中止**（implement-code Skill 有界验证口径）：AC-1/AC-3/AC-5/AC-7 的浏览器行为面**不得记为完成**，test-report 分析段记录未执行原因，不假绿、不把未执行的关键 AC 记为完成、不允许本 TASK 在缺真跑证据时标 done。
- **差异文档（SDD-CLOSE-04/D-6，最小内容大纲）**：a) 消息列/队列栏/发送框共用 `CHAT_GUTTER`+`CHAT_COLUMN` 两层嵌套的说明；b) 底栏 flow 布局与普通聊天 absolute 行的等价性；c) surface `max-h-40`（vs 普通聊天 `max-h-96`）保留理由；d) Model/Thinking 可见文字 label 不再常驻、chip+tooltip 承载，类别语义由 sr-only 标签保留；e) Team Agent composer 停止作用于最近一次发送 task 的语义（其余任务仍由队列栏逐条取消），含双源生命周期闭合表（queued/dispatched 由 queue items、running/waiting_local_directory 由任务时间线 `AgentTask[]` 数组、`tasks.find(task => task.id === sentTaskId)` 唯一选取、未命中回落 items-only，终态覆盖）与失败回流可见动作口径（保草稿 → 发送/重试按钮，清空草稿 → stop 重新出现，§4.2 判定式）。每项均须给出「是否必要差异 + 理由」。
- **全量回归（B-002）**：packages/views 全量 `vitest run`（无文件参数，= plan §6.2 cmd-04，含 TASK-01/02/03 新增套件、cmd-09 检查器与全部既有套件）；`node scripts/check-ui-wildcard-exports.mjs`（cmd-05）、typecheck（cmd-06）、`locales/parity.test.ts`（cmd-03）全绿。**不得以 cmd-01/02/03/09 定向套件替代 cmd-04 全量回归证据**。
- **交付 diff 白名单核对（AC-8，B-003 + B-006 职责收窄：仅文件级）**：只用受控命令，**禁止原生 git**（deny-closed gateway 会拒绝）：

  ```text
  node <resources[].tools.worktreePath>/skills/shared/crctl/scripts/crctl.mjs git diff --name-only 117fc6be657f91d43df5892b52782a18329c7aed --cwd <resources[].multica.worktreePath> --workspace <resources[].ai-first-platform-docs.worktreePath>
  ```

  （= plan §6.2 cmd-08；`--cwd`/`--workspace`/crctl.mjs 路径一律从 `execution_context.resources` 解析，**不硬编码、不拼接、不回退主工作区**；args 形态命中 controlled-shell 白名单 `^--name-only .+$`。）核对输出清单 ∈ 白名单：SDD §1.1 表（6 个 packages/views 修改/新增文件 + `CUSTOM.md` 治理 sidecar 受控例外）+ 测试文件（含 `chat-input-zero-diff.test.ts`）+ `e2e/project-chat-composer.spec.ts` + 差异文档；**无 `server/`、无 `server/migrations/`、无 API 路由/数据模型变更**。**B-006 职责收窄：本命令只证明「改动文件集合 ∈ 白名单」，不证明任何符号级 zero_diff——`chat-input.tsx` 因修改 `ChatInputCore` 必然出现在清单，不得据此声称 `ChatInput`/props 签名未变；符号级证据由 cmd-09 唯一承担**。
- **符号级 zero_diff 复核（AC-8，B-006）**：`node node_modules/vitest/vitest.mjs run chat/components/chat-input-zero-diff.test.ts`（cwd packages/views，= plan §6.2 cmd-09）全绿——`ChatInput`（全局）函数体、`ChatInputProps`/`ChatInputCoreProps`/`ChatInputDraftAdapter` 四段基线快照（TASK-01 从 `117fc6be` 修改前逐字提取）逐字命中、五个符号锚点各恰出现一次（检查器对读取内容先 `\r\n → \n` 规范化，读取/解析失败硬失败，AGENTS.md #1）。评审侧可审计辅助判定（非 cmd）：经受控 `crctl git diff --unified=3 117fc6be… -- packages/views/chat/components/chat-input.tsx`（白名单形态 `^--unified=\d+ .+$`）人工核对全部 hunk 仅落在 `ChatInputCore` 区域。
- 行尾纪律（AGENTS.md #1）：新文件 LF。

## 4. 验收条件

1. **e2e 真跑**（plan §6.2 cmd-07，无 `--list`）：`node node_modules/@playwright/test/cli.js test e2e/project-chat-composer.spec.ts`（cwd multica 根，FRONTEND_ORIGIN/PLAYWRIGHT_BASE_URL 指向运行中的前端+服务端）四组用例全过；环境无法建立 → 按 SDD §6.9-3 以 ENVIRONMENT_MISMATCH 技术中止（本 TASK 不得标 done、浏览器行为面不得记为完成）。`--list` 仅作 spec 可解析自检，不作为完成依据。
2. **packages/views 全量回归**（plan §6.2 cmd-04）：`node node_modules/vitest/vitest.mjs run`（cwd packages/views）全绿，含 TASK-01/02/03 新增套件、cmd-09 检查器与全部既有套件（NFR-5 不回归）。
3. 差异文档存在且含 SDD-CLOSE-04 a~e 五项，每项有「是否必要差异 + 理由」。
4. **交付 diff 白名单核对通过（文件级）**（§3 受控命令 = plan §6.2 cmd-08）：输出清单全部 ∈ 白名单（§1.1 表 + 测试文件 + e2e spec + 差异文档 + `CUSTOM.md` 受控例外），无 server/迁移/API/数据模型变更；`scripts/check-ui-wildcard-exports.mjs`（cmd-05）、typecheck（cmd-06）、parity（cmd-03）全绿。
5. **符号级 zero_diff 复核通过（B-006）**（= plan §6.2 cmd-09）：`chat-input-zero-diff.test.ts` 全绿——`ChatInput`（全局）函数体、`ChatInputProps`/`ChatInputCoreProps`/`ChatInputDraftAdapter` 四段基线快照逐字命中、符号锚点唯一；**不得以 cmd-08 name-only 清单「符号零出现」充当本条证据**。

## 5. 完成标志

- 上述 5 条验收全部通过（第 1 条为**必要条件**——无真跑 e2e 证据时本 TASK 不得标 done，不得以 `--list` 或组件测试替代；第 5 条为符号级 zero_diff 的机器证据，name-only 清单不替代）；canonical 机器证据 = plan §6.2 cmd-03/04/05/06/07/08/09；
- 提交落盘 multica CR 分支（独立 commit；回滚单元按 plan §4.0 **RU1**——叶子交付，可单独 revert）；multica `CUSTOM.md` 按当时实际结构登记本 TASK 的新文件（e2e spec、差异文档，治理 sidecar 受控例外）；
- 本 TASK 完成边界为 developing 内可被 `crctl task done` 登记的事件（交付物落盘 + 全部证据命令全绿），**不含** merge/writeback/archive（流程控制 TASK 禁止）。

## 6. 接口契约

**消费**：

- CR-2026-062-TASK-01：`ChatInputCore` surface `data-slot="chat-input-surface"`（e2e 截图/断言共用选择器）、可见动作判定语义 `running = !!isRunning && (!allowSubmitWhileRunning || isEmpty || pendingUploads > 0)`；**`chat-input-zero-diff.test.ts`（cmd-09，符号级 zero_diff 检查器，B-006）**。
- CR-2026-062-TASK-02：Team Agent 最终行为口径（双源停止、终态回发送态、失败回流可见动作、`@container` 前置）、`project-queue-bar` 两层结构、四个内部 testid 的 composer 子树定位；任务时间线 `AgentTask[]` + `tasks.find(task => task.id === sentTaskId)` 唯一选取 + 未命中回落 items-only（B-005 口径，差异文档条目 e 引用）。
- CR-2026-062-TASK-03：Private Ask 最终行为口径（工具栏 chip、creator-only、停止原样、`private-ask-model-picker` 新锚点）。
- 既有 e2e 基建：`playwright.config.ts`（testDir=./e2e、baseURL=`PLAYWRIGHT_BASE_URL ?? FRONTEND_ORIGIN ?? http://localhost:3000`）、`e2e/env.ts`/`helpers.ts`/`fixtures.ts`。
- 受控 shell：`crctl git diff --name-only <sha> --cwd <path>`（白名单形态 `^--name-only .+$`；原生 git 被 deny）；`crctl git diff --unified=3 <sha> -- <path>`（白名单形态 `^--unified=\d+ .+$`，评审侧审计辅助，非证据命令）。

**产出**（交付物，无代码接口）：

- `e2e/project-chat-composer.spec.ts`：宽面板对齐（AC-1/AC-2）、360px 窄面板（AC-3）、运行中停止（AC-5）、键盘发送（AC-7）四组可发现且**真跑通过**的用例。
- `packages/views/projects/components/project-chat-composer-layout-diff.md`：SDD-CLOSE-04 a~e 五项差异说明。
- 交付 diff 白名单核对清单（cmd-08 输出，文件级）+ 符号级 zero_diff 复核日志（cmd-09 输出）+ `CUSTOM.md` 台账登记（治理 sidecar）。
