---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-048-TASK-01
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: 迁移 380–384：三列 + skill_usage_event + 三索引
slug: skill-market-migrations
status: pending
estimate: 8h
depends-on: []
created: 2026-08-20T14:32:57+08:00
---

# TASK-01 迁移 380–384

## 任务描述

建立 Skill Market 的数据地基：`skill` 表加三列、建 `skill_usage_event` 遥测表（含 `workspace_id` 租户键）、三个 CONCURRENTLY 索引，并双注册 cleanup map。全部无 FK、每文件一条索引语句。SDD §2.1。

## 涉及文件 / 模块

- `server/migrations/380_skill_visibility.{up,down}.sql`（新建）
- `server/migrations/381_skill_usage_event.{up,down}.sql`（新建）
- `server/migrations/382_skill_usage_event_task_id.{up,down}.sql`（新建）
- `server/migrations/383_skill_usage_event_scope.{up,down}.sql`（新建）
- `server/migrations/384_skill_appeal_activity_index.{up,down}.sql`（新建）
- `server/cmd/migrate/main.go`（改：`concurrentIndexCleanups` + `concurrentDownIndexCleanups` 双注册 382/383/384）

## 实现要点

- 380：`ALTER TABLE skill ADD COLUMN visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','org')), ADD COLUMN version TEXT NOT NULL DEFAULT '0.1.0', ADD COLUMN owner_actor TEXT`；down 三列 DROP。
- 381：建表（SDD §2.1 完整 DDL），`workspace_id UUID NOT NULL`、`skill_ref TEXT NOT NULL`、`task_id UUID`、`project_id UUID`、`used_at TIMESTAMPTZ NOT NULL DEFAULT now()`；**无 FK**；表注释写明"派发时物化"语义（PRD FR-7）。
- 382：`CREATE INDEX CONCURRENTLY skill_usage_event_task_id_idx ON skill_usage_event(task_id)`。
- 383：`CREATE INDEX CONCURRENTLY skill_usage_event_scope_idx ON skill_usage_event(workspace_id, skill_ref, used_at)`。
- 384：照抄迁移 089 形制——`CREATE INDEX CONCURRENTLY skill_appeal_activity_idx ON activity_log ((details->>'appeal_id')) WHERE action IN ('skill_appeal_submitted','skill_appeal_approved','skill_appeal_rejected')`。
- down 文件：382/383/384 均 `DROP INDEX CONCURRENTLY`，381 `DROP TABLE`。
- 每个 CONCURRENTLY 迁移版本在 `concurrentIndexCleanups` / `concurrentDownIndexCleanups` 各注册一条（`"382_skill_usage_event_task_id" -> "skill_usage_event_task_id_idx"` 等），否则 `TestEveryConcurrentUpBuildHasCleanup` 红。
- **开工前置动作（本仓历史高频事故点）**：先确认 380–384 未被上游新迁移占用（`ls server/migrations/38*.sql`）；撞号则按 CUSTOM.md《迁移编号冲突》整体顺延，并同步修改两个 cleanup map 的键名（本仓 159/160/161/162/163 均撞过号）。
- **索引形制以 SDD §2.1 为准**：PRD AC-14 写的是 `(task_id)` 与 `(skill_ref, used_at)` 两索引，技术评审回修后为 `(task_id)`、`(workspace_id, skill_ref, used_at)`、384 申诉部分索引共三条（工作区隔离是硬不变式）。PRD 已审批不回改，**按本卡实施，不按 AC-14 字面**。

## 验收条件

1. （AC-1）真实 PostgreSQL 下 `up → down → up` 全回滚成功（380→384 逆序）。
2. （AC-1）`go test ./cmd/migrate/ -run Concurrent -v` 通过（cleanup 注册齐全）。
3. （AC-1）`information_schema` 查不到本 CR 新增的任何 FK 约束；`skill` 的 visibility CHECK 只有 private/org 两值。
4. （AC-14）382/383/384 三个索引各在独立迁移文件、up/down 均 CONCURRENTLY；固定 fixture 的 `EXPLAIN (FORMAT JSON)` 证明完成任务过滤走 `(task_id)`、排行走 `(workspace_id, skill_ref, used_at)`、申诉查找走 384。
5. （AC-15）在**含存量 skill 行**的库上应用迁移：所有既有 Skill 的 `visibility='private'`、`version='0.1.0'`、`owner_actor IS NULL`；随后跑一次 daemon claim 回归（`go test ./internal/handler/ -run Claim -v`）确认任务物化行为无变化。

## 完成标志

真实 PG 上 up/down/up 全绿 + migrate Concurrent 测试通过 + 无 FK 断言通过 + 存量行默认值断言通过（AC-1/AC-14/AC-15）。

## 接口契约

- 消费：无（根任务）。
- 产出：`skill.visibility/version/owner_actor` 三列、`skill_usage_event` 表、`skill_usage_event_task_id_idx`、`skill_usage_event_scope_idx`、`skill_appeal_activity_idx`——供 TASK-05 sqlc 生成与 TASK-06/07/08 使用。
