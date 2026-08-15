---
spec-id: ai-first-platform
version: "0.20.3"
id: CR-2026-041-TASK-05
type: TASK
cr-ref: CR-2026-041
plan-ref: "change-requests/CR-2026-041/plan.md"
sdd-ref: "change-requests/CR-2026-041/sdd.md"
title: milestone-file 契约去掉 status
slug: milestone-file-contract-no-status
status: pending
estimate: 1h
depends-on: []
created: 2026-08-15T22:05:40+08:00
---

# TASK-05 milestone-file 契约去掉 status

## 1. 任务描述

同步 `writeback-traceability` Skill 的 milestone-file 契约：起草里程碑文件时不再要求 `status: writing-back`。对应 FR-05（契约侧）。

## 2. 涉及文件 / 模块

- `skills/writeback/writeback-traceability/SKILL.md`（唯一改动文件）

## 3. 实现要点

- 第 21 行「至少含 `cr`、`milestone`、`target-version`、`status: writing-back` 和非空 `fr-chain`」改为「至少含 `cr`、`milestone`、`target-version` 和非空 `fr-chain`」（删除 `status: writing-back`）。
- 检查 SKILL.md 其余位置是否仍要求 milestone 文件带 status，一并删除或改为「新 milestone 不写 status」。
- 不动 `writeback-traceability.mjs` 的 `if (ms.status)` 分支（TASK-01 已删）；本任务只改 SKILL.md 文本契约。

## 4. 验收条件

1. `rg -n "status.*writing-back|status: writing-back" writeback-traceability/SKILL.md` 在 milestone-file 契约段无命中。
2. Skill 起草的 milestone 文件样例与 `buildSegment()` 的无 status 输出一致。

## 5. 完成标志

`node lint-prompts.test.mjs`（或等价 Skill 文本校验）通过。

## 6. 接口契约

- **消费**：无（纯文档契约同步）。
- **产出**：milestone-file 契约（`cr`/`milestone`/`target-version`/`fr-chain[]`，无 `status`），供 `writeback-traceability.mjs` 与下游 Skill 消费。
