---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-10
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: 文档更新 + rules.json#git 白名单补齐（FR-13，收尾核对）
slug: crctl-docs-whitelist-closeout
status: pending
estimate: 4h
depends-on: ["CR-2026-021-TASK-02", "CR-2026-021-TASK-03", "CR-2026-021-TASK-04", "CR-2026-021-TASK-05", "CR-2026-021-TASK-06", "CR-2026-021-TASK-07", "CR-2026-021-TASK-08", "CR-2026-021-TASK-09"]
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-13：TASK-02~09 全部落地后的收尾核对——更新 `crctl help`、`ARCHITECTURE.md §3/§8`、`skills/_index.yml:274` 的 crctl brief（补全 CR-2026-019 已加但漏列的 `task done`/`merge-metadata`/`archive-move`/`migrate-backlog` + 本轮全部新增/扩展子命令）；逐条核对 Phase 1-C（TASK-14）待迁移的裸 git 命令是否已在 `controlled-shell/rules.json#git` 白名单内，补齐缺失 shape（含 `ls-remote` 带分支参数的形态）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（help 文本）
- `tools/ARCHITECTURE.md`（§3 代码地图、§8 触发记录，按 SDD §9 修订项）
- `skills/_index.yml`
- `skills/shared/controlled-shell/rules.json`（`#git` 白名单）

## 实现要点

1. `ARCHITECTURE.md` §3 的 `crctl.mjs` 条目补写入子命令族扩至覆盖范围；§8 登记本次「crctl 新增写入子命令」触发的修订（不改 §5/§6 判据本身，SDD §9 已论证）。
2. `rules.json#git` 白名单核对清单需覆盖 TASK-14 迁移目标：`review-code:37-42`/`write-dev-plan:58-60`/`write-dev-tasks:81`/`writeback-{prd-sdd,tasks,traceability}` 提交步/`resume-cr` node-1:40（已知反例：`git ls-remote --heads origin '<branch>'` 带分支参数，当前白名单只有不带参数的 `^--heads origin$`）。

## 验收条件

- AC-8（PRD）：`crctl help` 输出含全部新增/扩展子命令；`rules.json#git` 白名单已补齐 TASK-14 所需的全部裸 git shape。

## 完成标志

`crctl help` 与 `ARCHITECTURE.md`/`skills/_index.yml` 更新完毕；TASK-14 可以直接开始不再需要额外补白名单。
