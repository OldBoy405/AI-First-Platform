---
id: CR-2026-053-TASK-10
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 集成测试与验收
slug: integration-test
status: pending
estimate: 4h
depends-on: [CR-2026-053-TASK-04, CR-2026-053-TASK-05, CR-2026-053-TASK-06, CR-2026-053-TASK-07]
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

端到端集成测试，验证完整闭环：
1. tools 仓改造与 Multica 绑定接口联调
2. review Skill 绑定前置步骤与审批卡可见性联动
3. 人工审批流程闭环验证

## 涉及文件 / 模块

- 测试文件（按既有测试惯例）

## 实现要点

验收清单（按 SDD AC-B 系列、AC-C 系列）：
- AC-B1~B11: 绑定接口测试覆盖
- AC-C1~C6: 审批卡可见性测试覆盖
- AC-D1~D6: 存量 CR 修复验收

## 验收条件

1. 所有测试用例通过
2. 端到端闭环验证成功
3. `crctl approve` 人工审批流程可用

## 完成标志

- 测试文件已 commit
- CI 通过

## 接口契约

无接口产出。
