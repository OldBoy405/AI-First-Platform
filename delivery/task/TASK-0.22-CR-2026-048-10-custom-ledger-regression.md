---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-048-TASK-10
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: 收口：CUSTOM.md 台账 + 全量回归矩阵
slug: custom-ledger-regression
status: pending
estimate: 4h
depends-on: [CR-2026-048-TASK-01, CR-2026-048-TASK-02, CR-2026-048-TASK-03, CR-2026-048-TASK-04, CR-2026-048-TASK-05, CR-2026-048-TASK-06, CR-2026-048-TASK-07, CR-2026-048-TASK-08, CR-2026-048-TASK-09]
created: 2026-08-20T14:32:57+08:00
---

# TASK-10 收口

## 任务描述

按 CUSTOM.md 现状登记本 CR 全部改动，跑全量回归，产出证据供 code review。SDD §7、PRD NFR-6/AC-16。

## 涉及文件 / 模块

- `../multica/CUSTOM.md`（改：新增一行台账，编号顺延，含迁移 380–384、门禁/遥测/申诉/market 挂钩点、验证命令）
- `server/internal/governance/`（若 `TaskCompleteRequest` 相关测试受 skill 列扩展影响则补 fixture）

## 实现要点

- CUSTOM.md 表格按现状结构登记（编号顺延、原因含 CR-2026-048 与 TASK 号、验证命令写全）。
- 全量回归命令：`cd server && go test ./... -count=1`（真实 PG 下 `-v` 取 `--- PASS`，避免 CUSTOM.md C6 的假绿）；`pnpm -C packages/core typecheck && pnpm -C packages/views typecheck` + 相关 vitest。
- 记录已知失败基线（CUSTOM.md「已知测试失败基线」表），确认名单无新增回归。

## 验收条件

1. （AC-16）CUSTOM.md 已登记本 CR 全部改动，含验证命令与上游冲突面说明。
2. （AC-16）本 CR 新增的全部 Go/SQL 文件注释为英文且带 `AIFIRST:`（`.sql` 用 `-- AIFIRST:`）标记；以 `git diff --stat` + 逐文件 grep 为证。
3. `go test ./... -count=1` 失败名单与既有基线一致（无新增回归）。
4. （AC-4）diff 中 `TaskCompleteRequest`/`sanitizeTaskCompleteRequest` 零改动（最终确认）。

## 完成标志

CUSTOM.md 台账完成 + 全量回归无新增失败 + 三仓 worktree 干净可交 code review。

## 接口契约

- 消费：TASK-01～09 全部产物。
- 产出：CUSTOM.md 台账行、回归证据（供 review-code 与回写期消费）。
