---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-019-TASK-07
type: TASK
cr-ref: CR-2026-019
plan-ref: "change-requests/CR-2026-019/plan.md"
sdd-ref: "change-requests/CR-2026-019/sdd.md"
title: 回归与 AC 逐条验收收口
slug: regression-and-acceptance
status: pending
estimate: 4h
depends-on: ["CR-2026-019-TASK-05", "CR-2026-019-TASK-06"]
assignee: ""
created: "2026-08-04T17:36:00+08:00"
---

## 任务描述

全量回归并按 PRD 验收标准 AC-1..9 逐条核对，产出 test-report 依据，作为进入代码评审前的收口。

## 涉及文件 / 模块

- 无新增代码；执行验证命令并汇总证据

## 实现要点（参考 plan.md §5 发布前 checklist）

1. `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` — 既有 32 + 新增用例全绿。
2. AC-1..9 逐条核对（对照 sdd.md §7.2 测试矩阵与 PRD 验收标准）。
3. `grep` 三份 SKILL.md 确认无"手工编辑 YAML"残留（FR-6）。
4. 确认 `crctl.mjs` 顶部 import 仅 `node:*`（NFR-4 零依赖不变量）。

## 验收条件

1. 测试套件全绿，输出用例总数与通过数。
2. AC-1..9 每条给出通过/证据位置（测试用例名或命令输出）。
3. FR-6 与 NFR-4 两项 grep 检查通过并留证。

## 完成标志

全部 AC 有据可查、回归全绿，可进入 write-test-report / review-code。
