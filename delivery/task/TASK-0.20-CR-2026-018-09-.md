---
id: CR-2026-018-TASK-09
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: 双适配器回归验证（claude-code + CI，含混版 fixture）
slug: dual-adapter-regression
status: pending
estimate: 6h
depends-on: ["CR-2026-018-TASK-05", "CR-2026-018-TASK-06"]
assignee: ""
created: "2026-08-04T17:10:00+08:00"
---

## 1. 任务描述

对 claude-code 适配器（TASK-06 改造后的 `inject-cr-status.mjs`）与 CI 适配器（`cr-guard.template.yml`，全部经 `crctl validate`/`crctl gate`，随 crctl 升级自然切换、无需改动但需回归确认）分别做 fixture 对比回归，确保新布局下两者行为与改造前等价，并补充评审 suggestion #1 要求的"迁移后统一 crctl 版本"提示的可观测性验证（混版场景下两个适配器均能正常工作或明确降级，不静默产生错误状态）。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/adapters/claude-code/hooks/inject-cr-status.mjs`（验证对象，不改代码）
- `tools/skills/shared/crctl/adapters/ci/cr-guard.template.yml`（验证对象，不改代码）
- 回归 fixture（可临时构造于测试目录，不需入库，除非发现需要固化为长期回归用例）

## 3. 实现要点

- 用同一组 fixture workspace（v1 布局、v2 布局、混版布局各一份）分别跑 claude-code 注入与 CI gate/validate，对比改造前后输出是否等价（v1/v2 场景）以及混版场景下的可观测行为（`MIXED_LAYOUT_WARN` 是否被两个适配器合理呈现或至少不掩盖）。
- CI 适配器预期零改动即可通过——本任务是确认预期成立，而非新增功能。

## 4. 验收条件

- v1 布局 fixture：两个适配器输出与改造前一致。
- v2 布局 fixture：两个适配器输出正确反映 cr.md 状态。
- 混版布局 fixture：两个适配器不静默产生错误结果（至少一方能暴露 `MIXED_LAYOUT_WARN` 或等价信号）。

## 5. 完成标志

三种 fixture 场景 × 两个适配器共 6 组对比全部通过；CI 适配器确认零代码改动即可兼容。
