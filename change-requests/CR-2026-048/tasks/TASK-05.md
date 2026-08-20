---
id: CR-2026-048-TASK-05
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: sqlc 查询：UpdateSkill 三列 + 遥测 INSERT + market 聚合 + 申诉记账
slug: sqlc-skill-market-queries
status: pending
estimate: 6h
depends-on: [CR-2026-048-TASK-01]
created: 2026-08-20T14:32:57+08:00
---

# TASK-05 sqlc 查询

## 任务描述

在 queries 层补齐 Skill Market 所需全部 SQL，`make sqlc` 重生成。所有生成物提交生成器真实输出，不手补。SDD §2.2、§4.3。

## 涉及文件 / 模块

- `server/pkg/db/queries/skill.sql`（改：UpdateSkill 加三列 narg）
- `server/pkg/db/queries/skill_market.sql`（新建：遥测 INSERT、market 聚合、申诉记账/查找）
- `server/pkg/db/generated/*.go`（`make sqlc` 生成）

## 实现要点

- `UpdateSkill` 增加 `visibility = COALESCE(sqlc.narg('visibility'), visibility)`、`version = COALESCE(sqlc.narg('version'), version)`、`owner_actor = COALESCE(sqlc.narg('owner_actor'), owner_actor)`。
- `InsertSkillUsageEvent :one`——`INSERT INTO skill_usage_event (workspace_id, skill_ref, task_id, project_id) VALUES ($1,$2,$3,$4) RETURNING *`（参数类型随 schema：workspace_id pgtype.UUID，task_id/project_id pgtype.UUID 可空）。
- `MarketSkillUsage :many`——`SELECT e.skill_ref, COUNT(DISTINCT e.task_id) AS usage_count FROM skill_usage_event e JOIN agent_task_queue t ON t.id = e.task_id WHERE e.workspace_id = $1 AND t.status = 'completed' GROUP BY e.skill_ref`。
- `InsertSkillAppealEvent :one`——`INSERT INTO activity_log (workspace_id, actor_type, actor_id, action, details) VALUES ($1,$2,$3,$4,$5) RETURNING *`。
- `GetAppealDecision :one`——`SELECT * FROM activity_log WHERE workspace_id=$1 AND action='skill_appeal_approved' AND details->>'appeal_id'=$2 ORDER BY created_at DESC LIMIT 1`。
- `HasAppealSubmitted :one`——`SELECT EXISTS(SELECT 1 FROM activity_log WHERE workspace_id=$1 AND action='skill_appeal_submitted' AND details->>'appeal_id'=$2)`。
- `ListOrgSkillSummariesByWorkspace :many`——`SELECT id, workspace_id, name, description, version, owner_actor, config, created_by, created_at, updated_at FROM skill WHERE workspace_id=$1 AND visibility='org' ORDER BY name ASC`（供 TASK-08，不读 content 列，对齐 `ListSkillSummariesByWorkspace` 的负载考量）。

## 验收条件

1. `make sqlc` 后 `git diff --stat server/pkg/db/generated/` 只含 skill 相关预期文件。
2. （AC-5）真实 PG 下：`InsertSkillUsageEvent` 落行；`MarketSkillUsage` 对同一 task 两次 claim 只计 1、失败任务不计、跨 workspace 不混算。
3. （AC-11/AC-14）`InsertSkillAppealEvent` 写行、`GetAppealDecision`/`HasAppealSubmitted` 按 appeal_id 命中，且 `EXPLAIN (FORMAT JSON)` 证明命中 384 部分索引（不退化 activity_log 全表扫描）。
4. `go build ./...` 通过。

## 完成标志

`make sqlc` 干净 + 上述语义断言在真实 PG 通过 + `go build ./...`。

## 接口契约

- 消费：TASK-01 的三列/表/索引 schema（sqlc schema 源即 migrations/）。
- 产出（generated，包 db）：`InsertSkillUsageEvent(ctx, workspaceID pgtype.UUID, skillRef string, taskID, projectID pgtype.UUID) (SkillUsageEvent, error)`、`MarketSkillUsage(ctx, workspaceID pgtype.UUID) ([]MarketSkillUsageRow, error)`（行含 `SkillRef string; UsageCount int64`）、`InsertSkillAppealEvent(ctx, workspaceID pgtype.UUID, actorType, actorID, action string, details []byte) (ActivityLog, error)`、`GetAppealDecision(ctx, workspaceID pgtype.UUID, appealID string) (ActivityLog, error)`、`HasAppealSubmitted(ctx, workspaceID pgtype.UUID, appealID string) (bool, error)`、`ListOrgSkillSummariesByWorkspace(...)`、更新后的 `UpdateSkill(...)`——供 TASK-06/07/08 消费。
