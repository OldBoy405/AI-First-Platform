---
id: CR-2026-062-TASK-04
type: TASK
cr-ref: CR-2026-062
plan-ref: "change-requests/CR-2026-062/plan.md"
sdd-ref: "change-requests/CR-2026-062/sdd.md"
target-version: 0.35
title: e2e 交付与差异文档 + 全量回归收尾
slug: project-chat-composer-e2e-and-diff-doc
status: pending
estimate: 16h
depends-on: [CR-2026-062-TASK-02, CR-2026-062-TASK-03]
created: 2026-09-09T21:14:52+08:00
---

## 1. 任务描述

在 multica CR worktree（HEAD 为 TASK-02/03 完成后的分支 HEAD）交付来源完成标志要求的两项收尾产物并做全量回归：① 新增 e2e spec `e2e/project-chat-composer.spec.ts`（宽面板截图对齐、360px 窄面板回归、运行中停止交互、键盘发送）；② 新增差异说明文档 `packages/views/projects/components/project-chat-composer-layout-diff.md`（SDD-CLOSE-04 五项大纲）；③ packages/views 全量回归 + 交付 diff 白名单核对（AC-8）。**不包含任何 pipeline 控制步骤**（merge/writeback/archive 由既有 CR 流程承载，审计走 approval.yml/merge-commits.yml/checkpoint 元数据）。

输入：已审批 SDD §5.6/D-6、SDD-CLOSE-04、§6.9 测试计划 3、§6 AC-1/AC-3/AC-5/AC-7/AC-8、plan.md §6 证据命令表。

## 2. 涉及文件 / 模块

- `e2e/project-chat-composer.spec.ts`（新建；multica 根 playwright.config.ts testDir=./e2e 自动发现）
- `packages/views/projects/components/project-chat-composer-layout-diff.md`（新建，英文，随 multica 仓提交）
- 测试入口（只跑，不改）：`packages/views/chat/components/chat-input.test.tsx`、`packages/views/projects/components/*.test.tsx`、`packages/views/locales/parity.test.ts`、`scripts/check-ui-wildcard-exports.mjs`、`packages/views` typecheck

## 3. 实现要点（SDD 对应节，逐字对齐）

- **e2e spec（§6.9-3）**：四组用例——(a) 宽面板截图：发送框表面边缘与消息列边缘对齐（差 < 1px 容差，AC-1），surface 与普通聊天视觉一致（AC-2）；(b) 窄面板 360px 回归：`scrollWidth <= clientWidth` 无横向溢出，输入区/附件预览/配置控件/发送停止按钮 boundingBox 无重叠 + 截图基线（AC-3）；(c) 运行中停止交互：Team Agent 发送后任务 running 期间右下角 stop 可用（草稿空）、点击后走取消（AC-5/§4.3.1）；(d) 键盘发送 Mod+Enter（AC-7）。复用 `e2e/helpers.ts`/`e2e/fixtures.ts` 既有模式；spec 不引入新依赖。
- **差异文档（SDD-CLOSE-04/D-6，最小内容大纲）**：a) 消息列/队列栏/发送框共用 `CHAT_GUTTER`+`CHAT_COLUMN` 两层嵌套的说明；b) 底栏 flow 布局与普通聊天 absolute 行的等价性；c) surface `max-h-40`（vs 普通聊天 `max-h-96`）保留理由；d) Model/Thinking 可见文字 label 不再常驻、chip+tooltip 承载，类别语义由 sr-only 标签保留；e) Team Agent composer 停止作用于最近一次发送 task 的语义（其余任务仍由队列栏逐条取消），含双源生命周期闭合表（queued/dispatched 由 queue items、running/waiting_local_directory 由任务时间线，终态覆盖）与失败回流可见动作口径（保草稿 → 发送/重试按钮，清空草稿 → stop 重新出现）。每项均须给出「是否必要差异 + 理由」。
- **全量回归**：packages/views 全量 `vitest run`（实施期全包专项证据，canonical 口径见 §6.2）、`node scripts/check-ui-wildcard-exports.mjs`、typecheck、`locales/parity.test.ts` 全绿。
- **交付 diff 白名单核对（AC-8）**：`git diff --name-only`（基线 `117fc6be`）核对改动文件 ∈ SDD §1.1 白名单 ∪ 测试文件 ∪ e2e spec ∪ 差异文档；无 `server/`、无 `server/migrations/`、无 API 路由/数据模型变更；普通非项目聊天视觉基线（`ChatInput` 路径）零 diff。
- 行尾纪律（AGENTS.md #1）：新文件 LF。

## 4. 验收条件

1. `node node_modules/@playwright/test/cli.js test e2e/project-chat-composer.spec.ts --list`（cwd multica 根）exit 0：spec 可解析、四组用例可发现（不启动浏览器/不连 baseURL）。
2. 环境就绪（`FRONTEND_ORIGIN` 指向运行中的前端 + 服务端）时真跑 `playwright test e2e/project-chat-composer.spec.ts`：四组用例全过；环境不可用时按 ENVIRONMENT_MISMATCH 口径记录于 test-report 分析段（功能断言由 cmd-01/02 组件测试承载，不假绿、不阻塞 canonical 证据）。
3. 差异文档存在且含 SDD-CLOSE-04 a~e 五项，每项有「是否必要差异 + 理由」。
4. 交付 diff 白名单核对通过（验收条件见 §3 最后一条）；`scripts/check-ui-wildcard-exports.mjs`、typecheck、parity 全绿。
5. packages/views 全量 `vitest run` 绿（含 TASK-01/02/03 新增套件与全部既有套件，NFR-5 不回归）。

## 5. 完成标志

- 上述 5 条验收全部通过（第 2 条环境不可用时以 ENVIRONMENT_MISMATCH 记录为准，不回退其余验收）；canonical 机器证据 = plan §6.2 cmd-01..06（其中 cmd-06 为 `--list` 口径，真跑 e2e 的实施期证据记录于 test-report 分析段）；
- 提交落盘 multica CR 分支（独立 commit、可单独 revert）；multica `CUSTOM.md` 按当时实际结构登记本 TASK 的新文件（e2e spec、差异文档）；
- 本 TASK 完成边界为 developing 内可被 `crctl task done` 登记的事件（交付物落盘 + 回归证据），**不含** merge/writeback/archive（流程控制 TASK 禁止）。

## 6. 接口契约

**消费**：

- CR-2026-062-TASK-01：`ChatInputCore` surface `data-slot="chat-input-surface"`（e2e 截图/断言共用选择器）、可见动作判定语义。
- CR-2026-062-TASK-02：Team Agent 最终行为口径（双源停止、终态回发送态、失败回流可见动作、`@container` 前置）、`project-queue-bar` 两层结构。
- CR-2026-062-TASK-03：Private Ask 最终行为口径（工具栏 chip、creator-only、停止原样）。
- 既有 e2e 基建：`playwright.config.ts`（testDir=./e2e、baseURL=PLAYWRIGHT_BASE_URL ?? FRONTEND_ORIGIN）、`e2e/env.ts`/`helpers.ts`/`fixtures.ts`。

**产出**（交付物，无代码接口）：

- `e2e/project-chat-composer.spec.ts`：宽面板对齐（AC-1/AC-2）、360px 窄面板（AC-3）、运行中停止（AC-5）、键盘发送（AC-7）四组可发现用例。
- `packages/views/projects/components/project-chat-composer-layout-diff.md`：SDD-CLOSE-04 a~e 五项差异说明。
