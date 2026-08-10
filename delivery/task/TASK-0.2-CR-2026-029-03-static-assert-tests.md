---
spec-id: ai-first-platform
version: "0.2"
id: CR-2026-029-TASK-03
type: TASK
cr-ref: CR-2026-029
plan-ref: "change-requests/CR-2026-029/plan.md"
sdd-ref: "change-requests/CR-2026-029/sdd.md"
title: 文本静态断言与既有回归
slug: static-assert-tests
status: pending
estimate: 1h
depends-on: [CR-2026-029-TASK-02]
created: "2026-08-10T20:14:00+08:00"
---

# TASK-03 文本静态断言与既有回归

## 1. 任务描述

`crctl.test.mjs` 增加源码/文本静态断言：merge-feature-branch SKILL.md 含 Step 6 联调走查与 merge-verification.md 产出、含发布类任务约定；feature-writeback pipeline merge-feature-branch 节点 prompt 含走查描述；write-dev-tasks/pipeline 无发布联调类 TASK 拆分指引。

## 2. 涉及文件

- tools：`skills/shared/crctl/scripts/test/crctl.test.mjs`

## 3. 实现要点

- 复用既有 AC-8 源码静态断言模式（读文件文本断言）。
- 全量回归：crctl 158 + writeback 9 保持全绿。

## 4. 验收条件

1. 新增静态断言通过；
2. `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿；
3. `node --test skills/writeback/scripts/test/writeback.test.mjs` 全绿。

## 5. 接口契约

- **消费**：TASK-01/02 产物文本。
- **产出**：测试用例。
