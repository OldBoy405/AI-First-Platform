---
id: CR-2026-050-TASK-03
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: FR-02 product-planning 输入契约修复
slug: fix-product-planning-inputs
status: pending
estimate: 4h
depends-on: [CR-2026-050-TASK-01]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

修复 product-planning 的 topic/竞品输入/回修输入缺失与人工审批越界：node-1/2/4 传 `topic`，node-3 补齐 write-competitive-report 必填输入（SDD §4.3 顺序调用链），node-5 传回修输入，node-6 只传契约输入，node-7 改结构化决定，node-8 删除跨文档写入。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下为该仓根相对路径：

- `repo=tools: pipeline-templates/product-planning.pipeline.json`（8 节点）

本 TASK 只运行现有 `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`，不修改该测试文件；正式新增断言归 TASK-13/14。

## 实现要点

1. node-1/2/4：显式传 `topic: {{inputs.topic}}`，保留各自 skip 标志。
2. node-3：**保留首句 `skip_competitive=true → SKIPPED` 分支**（SDD §4.3）；否则按顺序调用 `fetch-competitor-updates` → `gather-product-context` → `write-competitive-report(updates-block, product-snapshot, confirmed=false)`，输出为草稿正文（非路径）。
3. node-5 `write-planning-report`：传 `prev_outputs`、`review_feedback`、`self_repair_attempt`、`topic`、`target_version`；消费草稿正文而非报告路径。
4. node-6 `review-planning-report`：只传报告路径、reviewer、topic、target version、feedback、attempt；删除评审维度/annotation 路径/`_index.yml` 状态/轮次持久化算法。
5. node-7 human approval：结构化 approve/reject + reason；删除「在报告末尾补 reject_reason」；驳回中止正向链；不迁移到 CR 审批机制。
6. node-8 `write-roadmap`：只传 `topic`、`target_version`、`planning_report_path`；删除「同步更新规划报告 `_index.yml` 为 approved」跨文档写入（SDD DD-8 已知后果）。

## 验收条件

1. `topic` 在 node-1/2/4 的输入映射中显式出现；`skip_competitive` 分支保留。
2. node-3 含三 Skill 顺序调用链与 `confirmed=false`；node-5 传回修输入。
3. node-7 无「在报告末尾补 reject_reason」；node-8 无规划报告 `_index.yml` 写入表述。
4. JSON 可解析；节点数仍为 8；`lint-prompts.mjs` 无新增触发。

## 完成标志

上述 4 条验收全部通过，`git diff` 仅含 product-planning.pipeline.json。

## 接口契约

- 消费：`write-competitive-report` 必填 `updates-block/product-snapshot/confirmed`（SDD §2.3 产出方）、`planning-draft`/`review-planning-report`/`write-roadmap` 现行 SKILL 契约。
- 产出：product-planning 8 节点收敛版 prompt；TASK-13 将在同一文件上做 FR-09 下沉，不得回改本 TASK 的输入映射与 skip 分支。
