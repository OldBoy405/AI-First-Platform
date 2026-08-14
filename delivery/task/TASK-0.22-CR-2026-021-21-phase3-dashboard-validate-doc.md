---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-21
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 3 — cr-dashboard/spec-dashboard 改调 S11；validate-doc 视 D13 结论处理
slug: phase3-dashboard-validate-doc
status: pending
estimate: 4h
depends-on: ["CR-2026-021-TASK-08", "CR-2026-021-TASK-01"]
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

P3-13 + FR-12 的消费侧：
- `cr-dashboard`/`spec-dashboard` Step 2 手动统计状态直方图/SLA/周期活动 → `crctl report`/`crctl cr-metrics`。
- `validate-doc`：**分支处理，依赖 TASK-01 结论**——
  - 若 TASK-01 结论为「复活」：按其确定的路线 (a)（并入 `crctl validate --doc-type`）或 (b)（改调用 engineering-docs 自身 CLI，PRD/SDD 均倾向此路线）实现，本任务范围扩大到该实现。
  - 若结论为「不复活」：本任务对 `validate-doc` 不做代码改动，仅在 SKILL.md 补一句指向调查记录的引用（避免下次有人重新翻出同一问题却找不到已有结论）。

## 涉及文件 / 模块

- `skills/cr/cr-dashboard/SKILL.md`、`skills/spec/spec-dashboard/SKILL.md`
- `skills/requirement/validate-doc/SKILL.md`（分支处理）
- 若结论为复活路线 (a)：`skills/shared/crctl/scripts/crctl.mjs`（`validate` 扩展）
- 若结论为复活路线 (b)：`skills/requirement/validate-doc/SKILL.md`（改为调用 engineering-docs CLI 的描述）

## 实现要点

先读 TASK-01 产出的调查记录（`change-requests/CR-2026-021/investigations/d13-schema-validator.md`）再决定本任务的实际范围,不要在未读结论前预先动手实现 validate-doc 的任何代码路径。

## 验收条件

- AC-6（PRD，dashboard 部分）：`report`/`cr-metrics` 输出替代手动统计。
- AC-7（PRD，validate-doc 部分）：按 TASK-01 结论二选一执行，且结论在本任务完成摘要中被引用确认（不重新臆断）。

## 完成标志

dashboard 两份 SKILL.md 改调完成；validate-doc 按结论分支处理完毕（代码实现或仅文档引用，二选一均可算完成，取决于 TASK-01 结论）。
