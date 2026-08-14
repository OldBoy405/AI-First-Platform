---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-20
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 3/4 — write-dev-tasks 改造（S7+S10+D15）+ worktree-path 剩余去重（S9）
slug: phase3-write-dev-tasks-worktree-dedup
status: pending
estimate: 5h
depends-on: ["CR-2026-021-TASK-07", "CR-2026-021-TASK-08", "CR-2026-021-TASK-09"]
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

P3-09/P3-11（剩余）/P3-12（剩余）+ FR-21（D15）：
- `write-dev-tasks:45,64` 手动分配 TASK-ID + 拼 slug → `crctl task allocate`（不显式传编号，同 TASK-19 的原则）。
- `write-dev-tasks:80` 手拼 commit message → `crctl git commit --template task-breakdown`。
- `write-dev-tasks:87` 手动加总 TASK 估时 → 措辞精简为"按 TASK 列表求和"一句话带过（FR-21/D15，不开新命令）。
- `merge-feature-branch`/`push-progress`/`resume-from-remote` 剩余的 worktree bucket/path prose → `crctl worktree-path`（S9，requirement-register 一处已在 TASK-19 处理）。
- `writeback-traceability:75` 手拼 commit message → `crctl git commit --template writeback`。

## 涉及文件 / 模块

- `skills/develop/write-dev-tasks/SKILL.md`
- `skills/cr/merge-feature-branch/SKILL.md`、`skills/sync/push-progress/SKILL.md`、`skills/sync/resume-from-remote/SKILL.md`
- `skills/writeback/writeback-traceability/SKILL.md`

## 实现要点

`task allocate` 调用方式与 TASK-19 的 `cr-init` 同一原则：不传显式编号,从命令输出读取分配结果。

## 验收条件

- AC-11（部分）+ AC-12（PRD，D15 部分）：`write-dev-tasks:87` 措辞已精简；4 处 worktree-path 引用统一改调新命令；2 处 commit message 改调 `--template`。

## 完成标志

5 份 SKILL.md 修订完成并 grep 校验。
