---
spec-id: ai-first-platform
version: "0.24"
id: CR-2026-050-TASK-12
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: feature-writeback node-1 一行级预检删除
slug: feature-writeback-precheck-removal
status: pending
estimate: 1h
depends-on: [CR-2026-050-TASK-11]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

阶段二第 5 项：删除 feature-writeback node-1 的「校验 cr.md 当前 status=code-approved，否则 abort」预检（已由 merge-feature-branch / crctl merge 承担），保留失败中止；node-2～node-5 零改动（FR-11）。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下为该仓根相对路径：

- `repo=tools: pipeline-templates/feature-writeback.pipeline.json`

## 实现要点

1. node-1 prompt 删除 status=code-approved 预检句；保留「调用 merge-feature-branch、消费结构化结果、失败中止」。
2. node-2～node-5 不做任何改动（PRD FR-11：无需重构）。

## 验收条件

1. node-1 prompt 无 `code-approved` 字面量；仍含 merge-feature-branch 调用与失败中止语义。
2. `git diff` 显示 node-2～node-5 零改动。
3. JSON 可解析；节点数不变。

## 完成标志

上述 3 条验收全部通过。

## 接口契约

- 消费：merge-feature-branch SKILL 契约（状态校验由其/crctl merge 承担）。
- 产出：feature-writeback node-1 收敛版。
