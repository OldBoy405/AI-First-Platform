---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-01
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: D13 溯源调查 — engineering-docs schema validator v0.4.0 下线原因
slug: d13-schema-validator-investigation
status: pending
estimate: 3h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-12（SDD §6 / PRD §1.7）：Phase 0 的门槛调查任务，不阻塞其余 TASK-02~09 的并行实现，但 TASK-21（validate-doc 处理）依赖本任务的结论分支。查清 engineering-docs 的 `prd.schema.json`/`sdd.schema.json` + `validateFrontmatter`/`validateNaming` 在 v0.4.0 被下线的具体原因。

## 涉及文件 / 模块

- `skills/shared/engineering-docs/`（changelog、commit 历史、schema 文件是否仍在但未被调用）
- `skills/requirement/validate-doc/SKILL.md`（现状：教 agent 用眼睛核对）

## 实现要点

1. 查 engineering-docs 目录内 CHANGELOG / git log（`git log --follow` 定位 v0.4.0 前后改动），确认下线的具体原因（已知 bug？被更大改造取代？性能问题？）。
2. 结论落两种之一：
   - **复活**：产出二选一路线建议——(a) 并入 `crctl validate --doc-type prd|sdd`；(b) `validate-doc` 改为直接调用 engineering-docs 自身 CLI（SDD/PRD 均倾向 (b)，因 PRD/SDD 校验不属 CR 账本类产物）。
   - **不复活**：记录排查结论（原因仍成立，具体是什么），不写代码。
3. 结论写入本 CR 的一份调查记录（建议落 `change-requests/CR-2026-021/investigations/d13-schema-validator.md`），供 TASK-21 引用。

## 验收条件

- AC-7（PRD）：结论已产出并可被 TASK-21 引用，二选一（复活路线 / 不复活+原因）明确无歧义。
- 若结论为复活，需附路线 (a)/(b) 的取舍理由，供 TASK-21 直接执行，不留待实现期臆断。

## 完成标志

调查记录文件存在且结论明确；TASK-21 可据此判断 validate-doc 的处理范围。
