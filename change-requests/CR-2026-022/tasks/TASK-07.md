---
id: CR-2026-022-TASK-07
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 2.5 — gates.json review-planning-report 死配置删除 + pipeline node-6 承诺订正（FR-13）
slug: review-loop-dead-config
status: pending
estimate: 3h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-13（2.1-I，D-2 决策）：删 `gates.json` 的 `reviewLoops.review-planning-report` 死配置（从未被 `evaluatePassCondition`/`readAttempts` 消费，且 product-planning 无 CR 上下文）；同步订正 `product-planning.pipeline.json` node-6 的失实承诺。

## 涉及文件 / 模块

- `skills/shared/crctl/gates.json`：`reviewLoops` 段删 `"review-planning-report": { "pipeline": "product-planning" }`
- `pipeline-templates/product-planning.pipeline.json`：node-6 prompt 的"每次评审必须持久化 `review-loop.attempts[]`"改为如实描述——评审注记由 `review-planning-report` 自行落盘 `docs/product-planning/review-annotations/{report-id}.yml`，不经 crctl

## 实现要点

1. 删除前 grep `review-planning-report` 确认 crctl.mjs 无消费方（`evaluatePassCondition`/`readAttempts` 只读 requirement/tech-design/code 三 stage）
2. node-6 prompt 措辞：删"必须持久化"承诺，替换为当前自行落盘机制的准确描述（保留评审输出要求）
3. `skills/planning/review-planning-report/SKILL.md` 若有对应"经 crctl"的表述一并核对订正

## 验收条件

1. `gates.json` 无 `review-planning-report` 条目
2. `product-planning.pipeline.json` node-6 无"必须持久化"字样，含自行落盘机制描述
3. `crctl status`/gate 相关测试不因删条目回归（该 loop 从未被消费）

## 完成标志

验收 1~3 通过 + crctl.test.mjs 全量绿。
