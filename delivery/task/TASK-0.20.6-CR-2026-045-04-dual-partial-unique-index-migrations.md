---
spec-id: ai-first-platform
version: "0.20.6"
id: CR-2026-045-TASK-04
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: 双 partial unique index migration
slug: dual-partial-unique-index-migrations
status: pending
estimate: 3h
depends-on: []
created: 2026-08-17T20:39:31+08:00
---

# TASK-04 双 partial unique index migration

## 1. 任务描述

新增两个单语句 migration，用 PostgreSQL partial unique index 关闭并发竞态：① 同一 `(workspace_id,pipeline_id,cr_id)` 最多一个非终态 run；② 同一 `pipeline_node_run_id` 最多一个有效 task。不新增表、列或外键；沿用 Multica 迁移编号顺延规则（`CUSTOM.md` 台账登记撞号）。数据库集成测试必须在真实 PostgreSQL 下 `=== RUN`/`--- PASS`。

## 2. 涉及文件 / 模块

- `server/migrations/265_pipeline_run_architecture_active_unique.up.sql` / `.down.sql`（当前 CR 基线最新迁移为 264，使用 265）
- `server/migrations/266_agent_task_pipeline_node_active_unique.up.sql` / `.down.sql`（使用 266）
- `server/internal/governance/runner_index_test.go` 或既有 governance DB 集成测试（新增双 start / start-vs-projector / 双 enqueue / retry 后创建断言）

## 3. 实现要点

- 两条均为单语句 `CREATE UNIQUE INDEX CONCURRENTLY`，WHERE 分别限定 run 非终态与 task 有效态集合（SDD §3.3 精确状态枚举）；索引名固定为 `idx_pipeline_run_architecture_active_cr` 与 `idx_agent_task_queue_pipeline_node_active`，down 文件对应 `DROP INDEX CONCURRENTLY`。
- 若实施前 freshness gate 发现上游基线已新增迁移，先按 Multica 迁移纪律重新确认唯一编号，再保持两个文件相邻、单语句和 CUSTOM 登记；不得保留 `{NNN}` 占位。
- `pipeline_node_run` 已有 `UNIQUE(run_id,node_id,attempt)`，直接复用，不重复建。
- 集成测试覆盖：双 start 只产生一个非终态 run；start 与 projector find/create 并发只一个；同 node 双 enqueue 只一个有效 task；retry 在父任务终态后可创建子任务。

## 4. 验收条件

1. `265`/`266` 两条 migration 的 `up`/`down` 均可在真实 PostgreSQL 执行，down 用 `DROP INDEX CONCURRENTLY`；文件均保持单语句，不包事务。
2. 四类并发断言在真实库 `=== RUN`/`--- PASS`，无 TestMain skip 假绿。
3. 无新增表/列/外键；`CUSTOM.md` 登记迁移编号与撞号处置。

## 5. 完成标志

两条索引 migration 落地 + 并发集成测试真实库通过 + CUSTOM 台账登记。

## 6. 接口契约

- 消费：无上游 TASK。
- 产出：`pipeline_run` 非终态唯一索引、`agent_task_queue` 有效态唯一索引；TASK-07 的 Start upsert 与 enqueue 依赖这两条索引兜底竞态（DB unique violation 即竞态输家路径）。
