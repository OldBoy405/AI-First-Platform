---
id: CR-2026-040-TASK-05
type: TASK
cr-ref: CR-2026-040
plan-ref: "change-requests/CR-2026-040/plan.md"
sdd-ref: "change-requests/CR-2026-040/sdd.md"
title: fault-harness test 记录阶段故障矩阵
slug: fault-harness-test-recovery
status: pending
estimate: 4h
depends-on:
  - CR-2026-040-TASK-03
created: 2026-08-15T12:00:00+08:00
---

## 任务描述

在 `skills/shared/crctl/scripts/test/fault-harness.test.mjs` 增加结构化测试记录阶段的确定性故障注入矩阵，验证 `testCr` 复用既有 write-set 后无半状态、第三值阻断和幂等重试。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/fault-harness.test.mjs`

## 实现要点

- 复用代码仓当前已有的 `runCrctl`、`makeWorkspace`、`dirFingerprint` 与 `CRCTL_FAULT_POINT` 环境注入；不消费 TASK-04 新增的 helper。
- 覆盖：
  - 运行阶段外部中断（无 journal）→ canonical 报告/traceability/review-loop 不变，重试完整 plan；
  - `tx-apply-between-rename` → 恢复后四处文件无半状态、attempt 不重复；
  - `tx-apply-before-complete` → 重放标 complete 且不新增 attempt；
  - 已完成事务重放 `changed=false`。
- 断言 `FAULT_POINTS` 未新增 test 专用点，`UNKNOWN_FAULT_POINT` 契约保持。

## 验收条件

- 注入点命中时 `FAULT_INJECTED` 结构化退出；恢复后报告/日志引用/traceability/review-loop 一致。
- 重放不产生第二条 `review-loop` attempt，也不覆盖第三方修改（第三值 `TX_RECOVERY_CONFLICT`）。

## 完成标志

- `node --test skills/shared/crctl/scripts/test/fault-harness.test.mjs` 全绿，`git diff` 仅命中 `fault-harness.test.mjs`。

## 接口契约

- 消费：TASK-03 产出的 `crctl test --plan` 黑盒 CLI；`durable-tx` 既有 `FAULT_POINTS`/`faultPoint`。
- 产出：故障矩阵测试与恢复断言，不暴露生产函数。
