---
id: CR-2026-040-TASK-04
type: TASK
cr-ref: CR-2026-040
plan-ref: "change-requests/CR-2026-040/plan.md"
sdd-ref: "change-requests/CR-2026-040/sdd.md"
title: crctl.test.mjs 结构化测试矩阵
slug: crctl-test-structured-matrix
status: pending
estimate: 6h
depends-on:
  - CR-2026-040-TASK-03
created: 2026-08-15T12:00:00+08:00
---

## 任务描述

在 `skills/shared/crctl/scripts/test/crctl.test.mjs` 增加结构化测试计划的正常/边界/安全/幂等测试，覆盖 plan 合同、argv 安全、失败分流、machine zone、marker、digest 和重复执行。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点

- 复用现有 `makeWorkspace`、`runCrctl`、`writeEvidence` 与 fixture helper，不新增测试框架。
- 覆盖：合法 plan、command 顺序、`command-digest` 可复算；`--cmd` 拒绝；shell 元字符/空格/Unicode 不触发 shell；schema/字段/repo/cwd/executable 非法零 canonical 变化；non-zero/timeout 继续并原子 block；marker 缺失/重复硬失败；完成事务重放 `changed=false`。
- CRLF 与 LF plan 生成相同 digest；Windows/Ubuntu 路径回归。
- 断言报告 machine zone 字段、日志引用和 `traceability.yml#tests`、`review-loop.yml` 同步更新，且 `write-test-report` 只改 analysis suffix（静态文本断言）。

## 验收条件

- 新增测试在旧实现下按预期失败，在 TASK-03 后全绿；既有 `crctl.test.mjs` 用例不回归。
- `--cmd` 分支被移除后无测试依赖 shell 字符串；无新增第三方依赖。

## 完成标志

- `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿，`git diff` 仅命中 `crctl.test.mjs`。

## 接口契约

- 消费：`crctl.mjs` 的 `test --plan` 黑盒 CLI；TASK-03 产出的 `TestResponse`。
- 产出：测试 fixture/helper（复用现有 `makeWorkspace`/`runCrctl`），不暴露生产函数。
