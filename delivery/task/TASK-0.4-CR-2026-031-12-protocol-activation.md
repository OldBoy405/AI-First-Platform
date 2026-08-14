---
spec-id: ai-first-platform
version: "0.4"
id: CR-2026-031-TASK-12
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 完成架构文档 contracts 双平台 CI 与协议切换
slug: protocol-activation
status: pending
estimate: 16h
depends-on: [CR-2026-031-TASK-01, CR-2026-031-TASK-02, CR-2026-031-TASK-03, CR-2026-031-TASK-04, CR-2026-031-TASK-05, CR-2026-031-TASK-06, CR-2026-031-TASK-07, CR-2026-031-TASK-08, CR-2026-031-TASK-09, CR-2026-031-TASK-10, CR-2026-031-TASK-11]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

完成最终统一激活：同步 ARCHITECTURE/README/AGENTS/CUSTOM 台账，补齐 contracts 与 Windows/Ubuntu CI，运行 upgrade-check 后确认下一 CR 使用新协议。本 CR 本身仍走旧流程收尾。

# 2. 涉及文件 / 模块

- `ARCHITECTURE.md`、`README.md`、`AGENTS.md`、`CUSTOM.md`
- `scripts/lint-prompts.mjs` 与 skill/agent/pipeline contract tests
- `.github/workflows/` 相关 CI
- 所有本 CR 修改文件的最终一致性检查

# 3. 实现要点

- 修订 ARCHITECTURE.md 的单文件/WAL negative space，记录两个内部模块与新状态机口径 28/50。
- 文档只给总览和权威入口，不复制算法/命令计数。
- CI 执行 prompt lint、全部 contracts、crctl/writeback tests、JSON parse 与双平台 fault vectors。
- 检查 CUSTOM-TODO-007～009 及本 CR 定制登记；不得依赖主 checkout 未跟踪文件。
- 不添加 feature flag/wrapper/双写；最终切换前运行 upgrade-check。

# 4. 验收条件

1. PRD AC-01～AC-12 均有可执行证据；全部 test/lint/contract/JSON parse 在本地及 Windows/Ubuntu CI 通过。
2. ARCHITECTURE.md 与实现不再冲突，状态机口径和公共入口全仓唯一。
3. upgrade-check `canActivate=true`；本 CR 旧流程自举约束和“下一 CR 起新协议”在发布记录中明确。
4. `git diff` 无半协议、旧命令 consumer、未登记 CUSTOM 定制或 pending 已完成 TASK。

# 5. 完成标志

所有前置 TASK done，统一协议切换可评审、可回滚到 requirement branch 前一 commit，本 TASK 状态即时登记 done。

# 6. 接口契约

消费：TASK-10 execution context `{cr_id,operational_workspace,tx_id,phase,recover_command}`；TASK-11 `checkUpgrade()` 输出；TASK-01～09 的测试命令和结构化结果。

产出：CI contract `npm/Node scripts exit 0`；发布门禁 `{canActivate:true, allTasksDone:true, contractsPass:true, dualPlatformPass:true}`，供 test-report、review-code 和旧 feature-writeback 流程消费。
