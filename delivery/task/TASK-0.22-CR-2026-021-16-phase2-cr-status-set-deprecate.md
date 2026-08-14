---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-16
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 2 — cr-status-set 系统性清理
slug: phase2-cr-status-set-deprecate
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-18：`cr-status-set/SKILL.md` 标注 legacy/deprecated，正文改述"状态推进见 crctl advance"，保留仅为历史兼容。全仓引用改指 `crctl advance --to X --trigger Y --expect Z`：`approve-*`（删独立推进步，approve 已级联）、`review-code:132-133`、`review-tech-design:95`、`review-requirement:111`、`write-dev-tasks:79`、`cr-review-record:53-54`（reject/withdraw）、`cr-archive:54`。`cr-archive/SKILL.md:84-93` 删 Step 5 手写 `_index.yml`（`archive-move` 已一并更新）与 `:92` 手改 cr.md status。

## 涉及文件 / 模块

- `skills/cr/cr-status-set/SKILL.md`
- `skills/develop/review-code/SKILL.md`、`review-tech-design/SKILL.md`
- `skills/requirement/review-requirement/SKILL.md`
- `skills/develop/write-dev-tasks/SKILL.md`
- `skills/cr/cr-review-record/SKILL.md`、`cr-archive/SKILL.md`

## 实现要点

不依赖 Phase 0 任何新命令（`crctl advance`/`archive-move` 均已存在），可与 Phase 0/1 并行执行。

## 验收条件

- AC-10（PRD）：`grep -r "cr-status-set"` 除 `cr-status-set/SKILL.md` 自身的 legacy 说明外无其他 SKILL 引用；`cr-archive/SKILL.md` 不含手写 `_index.yml`/status 的步骤。

## 完成标志

grep 校验通过，7 处引用点全部改为 `crctl advance`。
