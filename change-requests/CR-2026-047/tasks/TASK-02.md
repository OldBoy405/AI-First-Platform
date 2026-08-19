---
id: CR-2026-047-TASK-02
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: 迁移 375–379 maturity_snapshot 表与周报历史索引
slug: migrations-375-379-snapshot
status: pending
estimate: 6h
depends-on: []
created: 2026-08-20T01:26:30+08:00
---

# TASK-02 迁移 375–379

## 任务描述

新增 CR-A 唯一新表 `maturity_snapshot` 与 4 个索引，严格遵守 multica CLAUDE.md：新表内不得内联隐式建索引；每个索引 `CREATE [UNIQUE] INDEX CONCURRENTLY` 且一文件一语句；down 全部可逆。SDD §2.1。

## 涉及文件 / 模块

- `server/migrations/375_maturity_snapshot_table.up.sql` / `.down.sql`
- `server/migrations/376_maturity_snapshot_identity.up.sql` / `.down.sql`
- `server/migrations/377_maturity_snapshot_primary_key.up.sql` / `.down.sql`
- `server/migrations/378_maturity_snapshot_scope_date.up.sql` / `.down.sql`
- `server/migrations/379_maturity_report_history.up.sql` / `.down.sql`
- 迁移注册清单（若 repo 有 migrations 索引/README，同步登记；以实施时现状为准）

## 实现要点

- 375 仅 `CREATE TABLE maturity_snapshot (workspace_id UUID NOT NULL, bucket_date DATE NOT NULL, scope TEXT NOT NULL CHECK(scope IN ('org','user','project')), scope_id TEXT NOT NULL, metrics JSONB NOT NULL DEFAULT '{}', scores JSONB NOT NULL DEFAULT '{}', config_rev TEXT NOT NULL CHECK(config_rev ~ '^[0-9a-f]{40}$'), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), CHECK((scope='org' AND scope_id='·') OR (scope IN ('user','project') AND scope_id<>'·')))`。表内无 PRIMARY KEY、无任何 index。
- 376 `CREATE UNIQUE INDEX CONCURRENTLY maturity_snapshot_identity_uidx ON maturity_snapshot (workspace_id, bucket_date, scope, scope_id);`
- 377 `ALTER TABLE maturity_snapshot ADD CONSTRAINT maturity_snapshot_pkey PRIMARY KEY USING INDEX maturity_snapshot_identity_uidx;`
- 378 `CREATE INDEX CONCURRENTLY maturity_snapshot_scope_date_idx ON maturity_snapshot (workspace_id, scope, scope_id, bucket_date DESC);`
- 379 `CREATE INDEX CONCURRENTLY idx_atq_maturity_report_history ON agent_task_queue (project_id, completed_at DESC, id DESC) WHERE status='completed' AND project_id IS NOT NULL AND result->>'schema'='ai-first.maturity-report/v1';`（369 仅覆盖 active task，不得误用）
- down 顺序 379→378→377→376→375（377 用 `DROP CONSTRAINT`，其 index 随 constraint 移除；376 用 `DROP INDEX CONCURRENTLY IF EXISTS`）。

## 验收条件

1. 真实 PostgreSQL up/down/up 三遍全通过；migration lint 零错。
2. 插入重复 `(workspace_id,bucket_date,scope,scope_id)` 报唯一冲突；org 行 `scope_id='·'` 合法、user 行 `scope_id='·'` 被 CHECK 拒绝。
3. `EXPLAIN` 证明 `agent_task_queue` 上 `status='completed' AND project_id=… AND result->>'schema'='ai-first.maturity-report/v1'` 的查询命中 `idx_atq_maturity_report_history` 而非 369 的 active partial index。

## 完成标志

10 个 SQL 文件全部提交；真实 PG up/down/up + EXPLAIN 证据写入本 TASK 提交说明。

## 接口契约

- 产出：`maturity_snapshot` 表物理结构（PK=`(workspace_id,bucket_date,scope,scope_id)`）与 `idx_atq_maturity_report_history`，供 TASK-06 插入、TASK-08 读取、TASK-10 历史查询。
- 消费：无上游代码接口。
