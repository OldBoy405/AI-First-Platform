---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-14
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 1-C — 裸 git 迁移为 crctl git
slug: phase1c-bare-git-migration
status: pending
estimate: 4h
depends-on: ["CR-2026-021-TASK-10"]
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-16：`review-code:37-42`、`write-dev-plan:58-60`、`write-dev-tasks:81`、`writeback-{prd-sdd,tasks,traceability}` 提交步、`resume-cr` node-1:40 一律改 `crctl git <sub> --cwd`。**依赖 TASK-10**——必须先确认 `rules.json#git` 白名单已放行全部目标命令（已知反例：`resume-cr` node-1:40 的 `git ls-remote --heads origin '<branch>'` 带分支参数，当前白名单只有不带参数形态）。

## 涉及文件 / 模块

- `skills/develop/review-code/SKILL.md`、`write-dev-plan/SKILL.md`、`write-dev-tasks/SKILL.md`
- `skills/writeback/{writeback-prd-sdd,writeback-tasks,writeback-traceability}/SKILL.md`
- `skills/cr/resume-cr/SKILL.md`（node-1）

## 实现要点

1. 逐文件改前先跑一遍 TASK-10 补齐后的 `rules.json#git`，确认目标命令 shape 已放行，不能假设"改成 crctl git 就必然放行"。
2. 统一改法与 sync/merge SKILL 现有 `runGit` 风格一致。

## 验收条件

- AC-9（PRD，部分）：Phase 1-C 覆盖的裸 git 命令全部替换为 `crctl git`，且实际执行不被 guard 拒绝（在真实/临时 workspace 跑一次验证，不仅是文本替换）。

## 完成标志

`grep -rn "^\s*git " skills --include=SKILL.md`（排除 `crctl git`/代码块示例说明）对本任务涉及文件无残留裸 git 调用。
