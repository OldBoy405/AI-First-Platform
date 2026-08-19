---
id: CR-2026-047-TASK-04
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: Token/Agent 类指标 SQL（token_intensity、ai_penetration、team_agent_depth、headline、model 明细）
slug: token-agent-metrics-sql
status: pending
estimate: 16h
depends-on: ["CR-2026-047-TASK-01"]
created: 2026-08-20T01:27:30+08:00
---

# TASK-04 Token/Agent 类指标 SQL

## 任务描述

在 sqlc 源文件 `server/pkg/db/queries/maturity.sql` 中实现 SDD §4.2 指标 1/2/7、§2.3 数据源规则与 §3.3 model 明细所需的查询。只写查询与生成 Go（`sqlc generate`），不写业务编排（TASK-06）与 HTTP（TASK-08）。所有查询左闭右开时间窗 `[from_utc,to_utc)`；无 `workspace_id` 的表必须经 `agent_task_queue.agent_id=agent.id AND agent.workspace_id=:workspace` 限租户。

## 涉及文件 / 模块

- `server/pkg/db/queries/maturity.sql`（新建；TASK-05 追加同文件，本 TASK 先占 1–3 段注释分区）
- `server/pkg/db/generated/maturity.sql.go`（sqlc 生成）

## 实现要点

- `-- name: MaturityMemberCount :one` → `SELECT count(*)::bigint AS n FROM member WHERE workspace_id=$1`。
- `-- name: MaturityTaskTokenRows :many`：窗口内 `task_usage` join `agent_task_queue q ON task_usage.task_id=q.id` join `agent a ON q.agent_id=a.id AND a.workspace_id=$1`，返回 `task_id, initiator_user_id, project_key, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, cost_usd_ticks`，`project_key=COALESCE(q.project_id, issue.project_id)`（`LEFT JOIN issue ON q.issue_id=issue.id`）；按 `q.created_at∈[from,to)` 过滤（usage 归属以 task created_at 定桶）。
- `-- name: MaturityBusinessProjects :many`：`SELECT id FROM project WHERE workspace_id=$1 AND status!='cancelled' AND settings->>'system_key' IS NULL ORDER BY id`。
- `-- name: MaturityInitiatorDistinct :one`：窗口内 `COUNT(DISTINCT q.initiator_user_id)::bigint`（同上租户 join，按 `q.created_at` 过滤）。
- `-- name: MaturityAttributionCounts :one`：返回 `attributed`（initiator 非 NULL 任务数）与 `unattributed`（NULL 任务数）两列。
- `-- name: MaturityTeamAgentCounts :one`：窗口内 `COUNT(*) FILTER (WHERE q.cr_id IS NOT NULL OR q.issue_id IS NOT NULL)::bigint AS deep`、`COUNT(*)::bigint AS total`。
- `-- name: MaturityModelCostRows :many`：窗口内按 `task_usage.model` 分组 `SUM(input/output/cache_read/cache_write tokens)` 与 `SUM(cost_usd_ticks)`（NULL 聚合为 NULL），供 TASK-08 model 维度；同样经 agent join 限租户。

## 验收条件

1. PostgreSQL fixture：四列 Token（含 cache_write）各自聚合正确；两个 workspace 数据互不可见。
2. `MaturityTaskTokenRows` 对 `q.project_id` 为 NULL 的历史行正确回退 `issue.project_id`；两者皆空返回 NULL project_key（不炸查询）。
3. `MaturityAttributionCounts` 对 initiator NULL 与非 NULL 任务计数正确；`MaturityTeamAgentCounts` 只认 `cr_id`/`issue_id`，不认 `pipeline_node_run_id`。

## 完成标志

`sqlc generate` 后 `go build ./...` 通过；三条验收 fixture 测试写入 `server/internal/service/maturity_test.go` 骨架（本 TASK 不要求全套矩阵，仅本查询的单元验证）。

## 接口契约

- 消费（TASK-01）：`maturity.MetricKey` 常量用于结果映射（仅引用，不在 SQL 内）。
- 产出（供 TASK-06 编排、TASK-08 model 明细）：
  - `db.Queries.MaturityMemberCount(ctx, wsID string) (int64, error)`
  - `db.Queries.MaturityTaskTokenRows(ctx, params MaturityTaskTokenRowsParams) ([]MaturityTaskTokenRow, error)`，Row 含 `TaskID, InitiatorUserID *pgtype.UUID, ProjectKey *pgtype.UUID, InputTokens, OutputTokens, CacheReadTokens, CacheWriteTokens int64, CostUSD *int64`（命名以 sqlc 生成实际为准，字段含义不得偏离本条）
  - `db.Queries.MaturityBusinessProjects(ctx, wsID string) ([]pgtype.UUID, error)`
  - `db.Queries.MaturityInitiatorDistinct(ctx, params) (int64, error)`
  - `db.Queries.MaturityAttributionCounts(ctx, params) (MaturityAttributionCountsRow, error)`
  - `db.Queries.MaturityTeamAgentCounts(ctx, params) (MaturityTeamAgentCountsRow, error)`
  - `db.Queries.MaturityModelCostRows(ctx, params) ([]MaturityModelCostRow, error)`
