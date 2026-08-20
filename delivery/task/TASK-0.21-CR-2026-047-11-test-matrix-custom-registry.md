---
spec-id: ai-first-platform
version: "0.21"
id: CR-2026-047-TASK-11
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: 测试矩阵收口与 CUSTOM.md 治理登记
slug: test-matrix-custom-registry
status: pending
estimate: 12h
depends-on: ["CR-2026-047-TASK-01", "CR-2026-047-TASK-02", "CR-2026-047-TASK-03", "CR-2026-047-TASK-04", "CR-2026-047-TASK-05", "CR-2026-047-TASK-06", "CR-2026-047-TASK-07", "CR-2026-047-TASK-08", "CR-2026-047-TASK-09", "CR-2026-047-TASK-10"]
created: 2026-08-20T01:31:00+08:00
---

# TASK-11 测试矩阵收口与 CUSTOM.md 治理登记

## 任务描述

按 SDD §7.2/§7.3 收口全量测试矩阵（各 TASK 已内置的测试除外，本 TASK 补齐跨层与集成用例），并把 CR-A 全部 multica 自研代码登记进 `CUSTOM.md`（工作区 AGENTS.md 纪律10）。完成后 AC-1~AC-22 无未映射。

## 涉及文件 / 模块

- `server/internal/service/maturity_test.go`（补齐：8 项 + 治理 DB fixtures、租户隔离、空分母）
- `server/cmd/migrate/`：复用 `migrate_concurrent_test.go` 与 `migrate_mul5999_index_retry_test.go`，新增 `maturity_migrations_test.go` 覆盖 375–379 真实 PG up/down/up + EXPLAIN
- `packages/core` zod malformed fixtures（`packages/core/api/*.test.ts`）
- `packages/views` UI 断言测试（观察期无雷达、无个人入口、四态、断点）
- E3 integration（daemon fixture：文件落盘、envelope、inbox、同周去重）
- `CUSTOM.md`（登记表以文件现状为准：编号顺延、原因追溯含 CR-2026-047 与对应 TASK 编号）

## 实现要点

- 逐行对照 SDD §7.2 矩阵核对哪些已由 TASK-01/03/07/08/09 内置测试覆盖，本 TASK 只补缺失行：迁移（含 EXPLAIN 命中 378/379）、8 项 SQL fixtures（AC-12，含 free-text owner unresolved 的 org/project 传播与 baseline 排除）、治理三态（AC-13）、rollup 并发/故障（AC-5，若 TASK-06 已含则核对即可）、E3 全链路（AC-18~22）、zod malformed（AC-15 前端侧）、UI（AC-10/11/14）。
- 全量跑一次 `go test ./...`、`pnpm test`（views/core 相关 scope）、migration lint，形成 AC-1~AC-22 → 测试名/用例映射清单，固定落 `change-requests/CR-2026-047/test-mapping.md`（不允许只留在提交说明）。
- `CUSTOM.md` 登记条目至少包含：迁移 375–379、`server/internal/maturity/*`、`server/internal/scheduler/jobs_maturity.go`、`server/internal/service/maturity*.go`、`server/internal/handler/maturity.go`、内置 skill `multica-maturity-weekly-report`、`packages/views/dashboard/maturity/*`、`packages/core` 追加、所有 `// AIFIRST:` 挂钩点。逐条核对“当时实际结构”，不臆造表头。

## 验收条件

1. `go test ./...`、views/core 测试、migration lint 全绿；AC-1~AC-22 每条至少对应一个可执行用例。
2. 跨层回归：改一个治理 fixture 值 → 总分不变（AC-13）；插入 unresolved free-text owner → 对应 org/project `project_collab_scale` unavailable、scores 为空且 baseline 排除；user scope 请求 400 且响应不含他人 ID（AC-10）。
3. `CUSTOM.md` diff 中每条登记能反查 CR-2026-047 与对应 TASK 编号，无遗漏新文件（用 `git diff --name-only` 与登记清单对拍）。

## 完成标志

全量测试绿 + AC 映射清单完整 + CUSTOM.md 登记完成并提交。

## 接口契约

- 消费：TASK-01~10 全部产出（测试与被测对象）。
- 产出：`CUSTOM.md` 新增条目、`test-mapping.md`（AC↔用例映射清单，供 review-code 与人工审批引用）。
