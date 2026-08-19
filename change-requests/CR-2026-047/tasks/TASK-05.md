---
id: CR-2026-047-TASK-05
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: CR/Pipeline 指标与治理护栏 SQL
slug: cr-pipeline-metrics-governance-sql
status: pending
estimate: 16h
depends-on: ["CR-2026-047-TASK-01", "CR-2026-047-TASK-04"]
created: 2026-08-20T01:28:00+08:00
---

# TASK-05 CR/Pipeline 指标与治理护栏 SQL

## 任务描述

在 `server/pkg/db/queries/maturity.sql`（TASK-04 同文件后续分区）实现 SDD §4.2 指标 3/4/5/6/8 与 §4.3 治理 6 字段、§4.4 基线样本所需查询。CR 与 pipeline 数据必须经 `cr.workspace_id=:workspace` 先限租户再 join 无租户列的表（`cr_sync_event` 等）。traceability 字段不写查询（CR-C 前恒 unavailable，由 TASK-06 以常量写入）。

## 涉及文件 / 模块

- `server/pkg/db/queries/maturity.sql`（追加；与 TASK-04 分区衔接，不得重写其分区）
- `server/pkg/db/generated/maturity.sql.go`（重新生成）

## 实现要点

- `-- name: MaturityArchivedCRs :many`：窗口内首次进入 archived 的 distinct CR。实现：`cr`（workspace 限定）join `cr_sync_event e ON e.cr_id=cr.cr_id AND e.event_kind='status' AND e.payload->>'to_status'='archived' AND e.occurred_at∈[from,to)`，输出 `cr_id, archived_at`，按 `cr.cr_id` 去重（同日多事件取最早 occurred_at）。
- `-- name: MaturityCRUsers :many`：对窗口内归档 CR 输出 `cr_id, user_id`，user 来源三路 UNION：`cr.owners`（jsonb 数组展开）∪ `comment.author_id`（`comment.issue_id=cr.shell_issue_id AND author_type='member'`，再 join `member` 确认 workspace 成员）∪ `agent_task_queue.initiator_user_id`（`q.cr_id=cr.cr_id OR q.issue_id=cr.shell_issue_id`），NULL 剔除，distinct。
- `-- name: MaturityActiveProjectKeys14d :many`：近 14 本地日窗口（调用方传 `[from,to)`）内 `agent_task_queue`（经 agent 租户 join）`COALESCE(q.project_id, issue.project_id)` 非空集合 ∪ 同期 `cr_sync_event` 状态事件经 `cr.shell_issue_id→issue.project_id` 的集合，输出 distinct project_id。
- `-- name: MaturityPrototypeGates :many`：窗口内归档 CR × 已投影 review gate（`requirement`/`tech-design`/`code`，对应 `governance.ReviewGateNodes` 投影存储）输出 `cr_id, gate, attempt, status`；实施时先核实 `server/internal/governance/gate_projection.go` 的投影表结构与列名（CR-2026-010 已交付），查询以该投影为唯一依据，不另建状态推导。
- `-- name: MaturityPipelineCompletions :many`：窗口内归档 CR × `pipeline_run`（`workspace_id` 限定、`cr_id` join、`status='completed'`）输出 `cr_id, pipeline_id`；调用方检查四元组 `requirement-authoring`/`architecture-design`/`code-implementation`/`feature-writeback`。
- `-- name: MaturityGateFirstPass :one`：窗口内 completed review gate 总数与 `attempt=1 AND status='passed'` 数（同一投影表）。
- `-- name: MaturityEvidenceDriftCount :one` / `-- name: MaturityForbiddenAttemptCount :one`：`activity_log`（`workspace_id` 限定）`action='aifirst.evidence_drift'` / `action='aifirst.gitguard_denied'` 且 `created_at∈[from,to)` 计数。
- `-- name: MaturityApprovalLatencies :many`：窗口内审批时延样本 `stage, latency_ms`：对应 stage 的 review 完成时间（projection/评审记录）→ `approval_record.created_at`（`workspace_id`+`cr_id`+`stage` join，只计 `decision='approve'`），正时长才入样本。
- `-- name: MaturityOrgScoreSamples :many`：取该 workspace 最早的连续 28 个 org bucket（`scope='org'`），按 `bucket_date` 升序输出全部行（样本过滤在调用方/报告层做，SQL 只限 org+最早 28 行）。

## 验收条件

1. fixture：archived 事件同 CR 两条只计最早；`payload->>'to_status'` 过滤生效（`to_status='archived'` 才入集）。
2. `MaturityCRUsers` 三路并集无重复、无 NULL；非成员 comment 不入集；`q.issue_id=cr.shell_issue_id` 路径命中。
3. 治理查询：两个 action 计数互不串；approval 时延只含 approve 决策正样本；`MaturityGateFirstPass` attempt/status 组合正确。
4. 所有 CR 系查询跨 workspace 隔离（fixture 双 workspace 互不可见）。

## 完成标志

sqlc 生成通过、`go build ./...` 通过；上述 fixture 验证在 `server/internal/service/maturity_test.go` 骨架中先绿。

## 接口契约

- 消费（TASK-01/04）：`maturity` 类型常量；同文件 TASK-04 分区。
- 产出（供 TASK-06 编排、TASK-10 基线建议）：
  - `db.Queries.MaturityArchivedCRs(ctx, params) ([]MaturityArchivedCRRow, error)`（Row：`CRID, ArchivedAt`）
  - `db.Queries.MaturityCRUsers(ctx, params) ([]MaturityCRUserRow, error)`（Row：`CRID, UserID`）
  - `db.Queries.MaturityActiveProjectKeys14d(ctx, params) ([]pgtype.UUID, error)`
  - `db.Queries.MaturityPrototypeGates(ctx, params) ([]MaturityPrototypeGateRow, error)`（Row：`CRID, Gate, Attempt, Status`）
  - `db.Queries.MaturityPipelineCompletions(ctx, params) ([]MaturityPipelineCompletionRow, error)`（Row：`CRID, PipelineID`）
  - `db.Queries.MaturityGateFirstPass(ctx, params) (MaturityGateFirstPassRow, error)`（Row：`Completed, FirstPass`）
  - `db.Queries.MaturityEvidenceDriftCount(ctx, params) (int64, error)`
  - `db.Queries.MaturityForbiddenAttemptCount(ctx, params) (int64, error)`
  - `db.Queries.MaturityApprovalLatencies(ctx, params) ([]MaturityApprovalLatencyRow, error)`（Row：`Stage, LatencyMs`）
  - `db.Queries.MaturityOrgScoreSamples(ctx, wsID string) ([]MaturityOrgScoreSampleRow, error)`（Row 含 `BucketDate, Metrics jsonb`）
