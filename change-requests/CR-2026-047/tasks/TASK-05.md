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

- `-- name: MaturityArchivedCRs :many`：窗口内首次进入 archived 的 distinct CR。实现：`cr`（workspace 限定）join `cr_sync_event e ON e.cr_id=cr.cr_id AND e.event_kind='status' AND e.payload->>'to_status'='archived' AND e.occurred_at∈[from,to)`，再 `LEFT JOIN issue ON cr.shell_issue_id=issue.id AND issue.workspace_id=cr.workspace_id`；输出 `cr_id, archived_at, project_id`（nullable），按 `cr.cr_id` 去重（同日多事件取最早 occurred_at）。TASK-06 以这一个 canonical CR→project 映射给吞吐/协作/EPC/流程完整率分组；project_id NULL 的 CR 只计 org。
- `-- name: MaturityCRUsers :many`：对窗口内归档 CR 输出 `cr_id,user_id`。评论分支=`comment.issue_id=cr.shell_issue_id AND author_type='member'` 再 join `member(workspace_id,user_id)`；任务分支必须 `JOIN agent qa ON qa.id=q.agent_id AND qa.workspace_id=:workspace` 后再按 `(q.cr_id=cr.cr_id OR q.issue_id=cr.shell_issue_id)` 取 `q.initiator_user_id`，NULL 剔除、distinct。`cr.owners` 身份处理由上游 SDD 修订决定：当前 git owner 是 free-text，禁止在本 TASK 名称匹配或强转 UUID；在上游决议前不得把 owner 分支写入 SQL。
- `-- name: MaturityActiveProjectKeys14d :many`：近 14 本地日窗口（调用方传 `[from,to)`）内 `agent_task_queue`（经 agent 租户 join）`COALESCE(q.project_id, issue.project_id)` 非空集合 ∪ 同期 `cr_sync_event` 状态事件经 `cr.shell_issue_id→issue.project_id` 的集合，输出 distinct project_id。
- `-- name: MaturityPrototypeGates :many`：窗口内归档 CR 先 join `pipeline_run pr ON pr.workspace_id=:workspace AND pr.cr_id=cr.cr_id`，再 join `pipeline_node_run pnr ON pnr.run_id=pr.id`，并以 `pnr.node_id = ANY(sqlc.arg(review_node_ids)::uuid[])` 过滤。`review_node_ids` 由 service 从 `governance.ReviewGateNodes["requirement"|"tech-design"|"code"].NodeID` 转为 UUID 传入，禁止在 SQL 复制 UUID 常量；输出 `cr_id,pnr.node_id,pnr.attempt,pnr.status,pnr.completed_at`。投影精确来源是 `server/internal/governance/gate_projection.go#applyReview` 与 migration 366 的 `pipeline_node_run`，不另建状态推导。
- `-- name: MaturityPipelineCompletions :many`：窗口内归档 CR × `pipeline_run`（`workspace_id` 限定、`cr_id` join、`status='completed'`）输出 `cr_id, pipeline_id`；调用方检查四元组 `requirement-authoring`/`architecture-design`/`code-implementation`/`feature-writeback`。
- `-- name: MaturityGateFirstPass :one`：参数同样含 `review_node_ids uuid[]`，以 `pnr.completed_at∈[from,to)` 统计 completed review gate 总数与 `attempt=1 AND status='passed'` 数；join `pipeline_run.workspace_id` 先限租户。
- `-- name: MaturityEvidenceDriftCount :one` / `-- name: MaturityForbiddenAttemptCount :one`：`activity_log`（`workspace_id` 限定）`action='aifirst.evidence_drift'` / `action='aifirst.gitguard_denied'` 且 `created_at∈[from,to)` 计数。
- `-- name: MaturityApprovalLatencies :many`：窗口内审批时延样本 `stage, latency_ms`：对应 stage 的 review 完成时间（projection/评审记录）→ `approval_record.created_at`（`workspace_id`+`cr_id`+`stage` join，只计 `decision='approve'`），正时长才入样本。
- `-- name: MaturityBaselinePercentiles :many`：CTE 取该 workspace 最早 28 个 org bucket；只有 `COUNT(DISTINCT bucket_date)=28 AND MAX(bucket_date)-MIN(bucket_date)=27` 才继续。`jsonb_each(metrics->'metric_values')` 展开 8 key，仅保留 `data_status='ready' AND value IS NOT NULL`；按 metric key 分组且 `HAVING COUNT(*)>=21`，返回 `metric_key,sample_count,percentile_cont(0.10) WITHIN GROUP (ORDER BY value),percentile_cont(0.75) ...`。第4周基线必须消费该 PostgreSQL 结果，不在 Go/LLM 内重实现分位数。

## 验收条件

1. fixture：archived 事件同 CR 两条只计最早；`payload->>'to_status'` 过滤生效；映射 CR 同时贡献 org + 对应 project，`shell_issue_id` 为空/跨 workspace issue 的 CR 只贡献 org。
2. `MaturityCRUsers` 已决议分支无重复、无 NULL；非成员 comment 不入集；`q.issue_id=cr.shell_issue_id` 路径命中；两个 workspace 使用相同 `cr_id` 时 foreign workspace queue initiator 不得进入集合。
3. 治理查询：两个 action 计数互不串；approval 时延只含 approve 决策正样本；`MaturityGateFirstPass` 仅命中 `governance.ReviewGateNodes` 三个 node_id，attempt/status 组合正确。
4. 所有 CR 系查询跨 workspace 隔离（fixture 双 workspace 互不可见）。
5. 基线 fixture：28 个连续 bucket 且某 metric 25 个 ready → 返回与 PostgreSQL `percentile_cont` 一致的 P10/P75；只有 20 个 ready、缺一天或 P75<=P10 的输入分别由调用方得到 unavailable/不产出可写建议。

## 完成标志

sqlc 生成通过、`go build ./...` 通过；上述 fixture 验证在 `server/internal/service/maturity_test.go` 骨架中先绿。

## 接口契约

- 消费（TASK-01/04）：`maturity` 类型常量；同文件 TASK-04 分区。
- 产出（供 TASK-06 编排、TASK-10 基线建议；`ctx` 均为 `context.Context`，窗口 params 统一具名字段 `WorkspaceID pgtype.UUID,FromUTC/ToUTC pgtype.Timestamptz`）：
  - `func (q *db.Queries) MaturityArchivedCRs(ctx context.Context, arg db.MaturityArchivedCRsParams) ([]db.MaturityArchivedCRsRow, error)`（Row：`CRID string,ArchivedAt pgtype.Timestamptz,ProjectID pgtype.UUID`，`.Valid=false` 表示仅org）
  - `func (q *db.Queries) MaturityCRUsers(ctx context.Context, arg db.MaturityCRUsersParams) ([]db.MaturityCRUsersRow, error)`（Row：`CRID string,UserID pgtype.UUID`）
  - `func (q *db.Queries) MaturityActiveProjectKeys14d(ctx context.Context, arg db.MaturityActiveProjectKeys14dParams) ([]pgtype.UUID, error)`
  - `func (q *db.Queries) MaturityPrototypeGates(ctx context.Context, arg db.MaturityPrototypeGatesParams) ([]db.MaturityPrototypeGatesRow, error)`；Params 另含 `ReviewNodeIDs []pgtype.UUID`，Row=`CRID string,NodeID pgtype.UUID,Attempt int32,Status string,CompletedAt pgtype.Timestamptz`。
  - `func (q *db.Queries) MaturityPipelineCompletions(ctx context.Context, arg db.MaturityPipelineCompletionsParams) ([]db.MaturityPipelineCompletionsRow, error)`（Row：`CRID string,PipelineID string`）
  - `func (q *db.Queries) MaturityGateFirstPass(ctx context.Context, arg db.MaturityGateFirstPassParams) (db.MaturityGateFirstPassRow, error)`；Params 含 `ReviewNodeIDs []pgtype.UUID`，Row=`Completed/FirstPass int64`。
  - `func (q *db.Queries) MaturityEvidenceDriftCount(ctx context.Context, arg db.MaturityEvidenceDriftCountParams) (int64, error)`
  - `func (q *db.Queries) MaturityForbiddenAttemptCount(ctx context.Context, arg db.MaturityForbiddenAttemptCountParams) (int64, error)`
  - `func (q *db.Queries) MaturityApprovalLatencies(ctx context.Context, arg db.MaturityApprovalLatenciesParams) ([]db.MaturityApprovalLatenciesRow, error)`（Row：`Stage string,LatencyMs int64`）
  - `func (q *db.Queries) MaturityBaselinePercentiles(ctx context.Context, workspaceID pgtype.UUID) ([]db.MaturityBaselinePercentilesRow, error)`（Row：`MetricKey string,SampleCount int64,P10/P75 float64`）。
