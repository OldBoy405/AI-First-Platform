---
id: CR-2026-018-TASK-05
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: crctl 测试套件扩展（AC-1/2/3/5/9/10/11 汇总回归）
slug: crctl-test-suite-expansion
status: pending
estimate: 8h
depends-on: ["CR-2026-018-TASK-04"]
assignee: ""
created: "2026-08-04T16:50:00+08:00"
---

## 1. 任务描述

TASK-01~04 各自已在验收条件中要求新增对应单元测试，本任务做汇总性收口：确认现有 21 个用例 + 各任务新增用例合计 ≥7 条新用例（AC-10）全部纳入 `crctl.test.mjs` 统一维护，补齐尚未覆盖的边界（AC-2 新旧布局双向读的组合场景、AC-11 混版告警的两种对照场景）。不新增功能代码，只做测试补全与整理。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/test/crctl.test.mjs`

## 3. 实现要点

- 按 SDD §6 测试增量清单逐条核对：AC-1（单写 diff）、AC-2（新旧布局双向读）、AC-3（validate 三态）、AC-5（迁移成功/失败/幂等）、AC-9（端到端零冲突，本任务只覆盖单元/集成层面，端到端演练留 TASK-10）、AC-10（回归线）、AC-11（混版告警）。
- 若 TASK-01~04 已各自补了对应用例，本任务重点是查漏补缺 + 跑一次全量确认没有重复/遗漏。

## 4. 验收条件

- `crctl.test.mjs` 全量用例数 ≥ 28（21 现有 + 7 新增）。
- 全量测试命令一次通过，无 flaky。
- SDD §6 测试增量清单中列出的 7 项逐一有对应用例可追溯（用例名或注释标注对应 AC 编号）。

## 5. 完成标志

测试套件扩展完成并全绿；每条新用例可追溯到对应 AC 编号；lint 零报错。
