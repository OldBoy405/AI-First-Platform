---
id: CR-2026-052-TASK-02
type: TASK
cr-ref: CR-2026-052
plan-ref: "change-requests/CR-2026-052/plan.md"
sdd-ref: "change-requests/CR-2026-052/sdd.md"
title: "sqlc 查询：approval.sql 6 条 + issue.sql 2 条 FOR SHARE 锁读 + 重生成"
slug: sqlc-approval-queries-regen
status: pending
estimate: 6h
depends-on: ["CR-2026-052-TASK-01"]
created: 2026-08-27T10:44:32+08:00
---

# TASK-02：sqlc 查询与重生成

## 1. 任务描述

新增 `server/pkg/db/queries/approval.sql`（6 条查询）与 `issue.sql` 的 2 条 FOR SHARE 锁读查询，重跑 `make sqlc` 生成 Go 绑定。禁止手改 `pkg/db/generated/*.go`（ARCHITECTURE §5.5 / SDD §1.3）。对应 SDD §3.3，闭合 TD-BL-2/5/8/10 的查询层 workspace 限定与锁级。

## 2. 涉及文件 / 模块

- 新建 `server/pkg/db/queries/approval.sql`
- 修改 `server/pkg/db/queries/issue.sql`（追加 2 条锁读）
- 生成 `server/pkg/db/generated/*.go`（`make sqlc`，预期只含新增查询绑定）

## 3. 实现要点（SDD §3.3/§4.2/§4.3）

### approval.sql（新文件）

```sql
-- name: AckApprovalGrants :many
UPDATE approval_record
SET delivered_at = now()
WHERE workspace_id = $1 AND id = ANY($2::text[]) AND delivered_at IS NULL
RETURNING id::text, cr_id, stage, decision, approver_user_id::text;

-- name: GetCrShellIssueInWorkspaceForShare :one
SELECT * FROM cr WHERE workspace_id = $1 AND cr_id = $2 FOR SHARE;

-- name: LockIssueInWorkspaceForShare :one   -- 注：放 issue.sql（见下），此处仅列示
-- name: CreateApprovalContinuationTask :one
-- guarded INSERT：workspace-qualified authority joins 复核 + ON CONFLICT DO NOTHING
-- status('queued'/'deferred') 与 fire_at 参数化；SELECT ... FROM join 链
-- (agent/issue/squad/cr 全 workspace=$ws) ON CONFLICT DO NOTHING RETURNING *;
-- name: AppendApprovalContinuationEvidence :one
-- UPDATE ... SET context=jsonb_set(...), handoff_note=COALESCE(...)||E'\n'||$line
--   WHERE id=$successor AND approval_workspace_id=$ws AND kind='approval_continuation'
--   AND NOT EXISTS(... approval_record_id 去重) RETURNING *;
-- name: GetApprovalContinuationTaskByRecord :one
-- SELECT * WHERE approval_workspace_id=$1 AND trigger_evidence_kind='approval_continuation'
--   AND trigger_evidence_ref_id=$2 AND status IN (五态) ;
-- name: GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate :one
-- SELECT * WHERE approval_workspace_id=$1 AND trigger_evidence_kind='approval_continuation'
--   AND cr_id=$2 AND status IN ('queued','deferred') FOR UPDATE;
```

### issue.sql（追加）

```sql
-- name: LockIssueInWorkspaceForShare :one
SELECT * FROM issue WHERE id = $1 AND workspace_id = $2 FOR SHARE;
```

注意：`GetCrShellIssueInWorkspaceForShare` 归属 approval.sql（cr 表，FOR SHARE）；`LockIssueInWorkspaceForShare` 归属 issue.sql（FOR SHARE，非既有 `LockIssueForChannelMediaBind` 的 FOR KEY SHARE——锁级经 TD-BL-8 修正，§4.2/DD-10）。

所有查询的 `$ws` 均为 daemon 认证 workspace，由调用层注入；无 workspace 的 fallback 路径。

### 重生成

```bash
make sqlc   # 仓库根
```
校验 `git diff pkg/db/generated/` 只含新增查询的绑定函数，无意外漂移；`go build ./...` 通过。

## 4. 验收条件

1. `make sqlc` 成功，生成产物可编译 `go build ./...`。
2. 六条 approval.sql 查询 + 一条 issue.sql 锁读在生成 Go 代码中可见，签名与 §3 接口契约一致（`:many`/`:one` 形态正确）。
3. 所有查询均显式带 `workspace_id = $ws` 限定；`grep` 确认无遗漏 workspace 的 fallback 查询。

## 5. 完成标志

queries 落盘 + `make sqlc` 生成 + `go build ./...` 通过；生成物 git diff 仅新增预期函数。

## 6. 接口契约

- **消费**：TASK-01 的 `approval_workspace_id` 列与 469/471 索引。
- **产出**（Go 函数名，供下游消费）：
  - `AckApprovalGrants(ctx, ws pgtype.UUID, ids []string) ([]db.AckApprovalGrantsRow, error)`
  - `GetCrShellIssueInWorkspaceForShare(ctx, ws pgtype.UUID, crID string) (db.Cr, error)`
  - `LockIssueInWorkspaceForShare(ctx, issueID int64, ws pgtype.UUID) (db.Issue, error)`（issue.sql）
  - `CreateApprovalContinuationTask(ctx, spec ...) (db.AgentTaskQueue, error)`
  - `AppendApprovalContinuationEvidence(ctx, ws, successorID, newEntry, newLine, recordID) (db.AgentTaskQueue, error)`
  - `GetApprovalContinuationTaskByRecord(ctx, ws, recordID) (db.AgentTaskQueue, error)`
  - `GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate(ctx, ws, crID) (db.AgentTaskQueue, error)`
