---
id: CR-2026-052-TASK-04
type: TASK
cr-ref: CR-2026-052
plan-ref: "change-requests/CR-2026-052/plan.md"
sdd-ref: "change-requests/CR-2026-052/sdd.md"
title: "HandleGrantsAck 事务核心 + GrantAckEvent + 双钩（TD-BL-12）"
slug: handle-grants-ack-tx-double-hook
status: pending
estimate: 8h
depends-on: ["CR-2026-052-TASK-02", "CR-2026-052-TASK-03"]
created: 2026-08-27T10:44:32+08:00
---

# TASK-04：HandleGrantsAck 事务核心与双钩

## 1. 任务描述

重写 `server/internal/governance/approval.go#HandleGrantsAck` 为单事务「delivered_at + 续跑入队」原子编排，定义 `GrantAckEvent`，保留 `SetGrantAckHandler` 为预提交 error→5xx canonical callback 并新增 `SetGrantAckCommittedHandler` 提交后 wake。对应 SDD §1.3/§3.2/§4.1/§4.2，闭合 TD-BL-12 双钩与 TD-BL-5/8/10 锁链。

## 2. 涉及文件 / 模块

- 修改 `server/internal/governance/approval.go`（`HandleGrantsAck`、`GrantAckEvent`、`SetGrantAckHandler`、`SetGrantAckCommittedHandler`、`resolveContinuationTarget`）

## 3. 实现要点

### GrantAckEvent + 双钩（SDD §3.2，TD-BL-12）

```go
type GrantAckEvent struct {
    WorkspaceID string
    CrID        string
    RecordID    string // approval_record.id text 形态
    Stage       string // requirement | tech-design | dev-start | code
    Decision    string // approve | reject
}
// 原 onGrantAck func(context.Context,string,string) 扩展为 func(context.Context, GrantAckEvent) error
func (a *ApprovalService) SetGrantAckHandler(fn func(context.Context, GrantAckEvent) error)         // 预提交纯校验，error->回滚/5xx
func (a *ApprovalService) SetGrantAckCommittedHandler(fn func(context.Context, GrantAckEvent) error) // 提交后真实 wake，error->日志/2xx
```

保留 `onGrantAck`/`SetGrantAckHandler` 原名以机械对应 PRD FR-10（不把该名挪给 committed wake，TD-BL-12）。

### HandleGrantsAck（SDD §4.1 伪代码）

```text
ws := resolveDaemonWorkspace(r)
tx := pool.Begin(ctx); qtx := queries.WithTx(tx)
rows := qtx.AckApprovalGrants(ctx, ws, ids)   // UPDATE RETURNING 五字段
ackEvents, tasks := [], []
for row in rows:
    target, reason := resolveContinuationTarget(qtx, ws, row)
    if target==nil: rollback; return 500 {error, reasons:[{cr,stage,reason}]}
    task, outcome := taskSvc.EnqueueApprovalContinuation(ctx, qtx, spec(row,target))
    if task 为新建行(outcome∈{successor-enqueued,slot-deferred}): tasks += task
    ackEvents += GrantAckEvent{ws, row.cr_id, row.id, row.stage, row.decision}
for ev in ackEvents: if onGrantAck!=nil: err->rollback; return 500   // 预提交零副作用
commit
for task in tasks: taskSvc.NotifyContinuationTaskEnqueued(ctx, task) // 提交后广播 FR-11
for ev in ackEvents: if onGrantAckCommitted!=nil: err->log.Error(…reason=ack-wake-failed) // 不置 5xx
return 200 {status: ok}
```

幂等重放：`AckApprovalGrants` 匹配 0 行 → 200（沿用现有 0 行分支）。

### resolveContinuationTarget（SDD §4.2，TD-BL-5/8/10 锁链）

固定锁序 cr→issue→squad→agent，先锁后读，全程同事务（qtx），全部带 `$ws`：
1. `GetCrShellIssueInWorkspaceForShare(qtx, ws, row.cr_id)`（FOR SHARE）→ 0 行 reason=`workspace-mismatch`；shell_issue_id 空 → `issue-missing`。
2. `LockIssueInWorkspaceForShare(qtx, cr.shell_issue_id, ws)`（issue.sql，FOR SHARE）→ 0 行 `issue-missing`；assignee_type≠'squad'/assignee_id 空 → `leader-missing`。
3. `LockSquadForAutopilotAssignment(qtx, issue.assignee_id, ws)`（squad.sql:12，FOR SHARE）→ archived → `leader-missing`。
4. `GetAgentForUpdate(qtx, squad.leader_id)`（agent.sql:30，FOR UPDATE）→ workspace 不匹配/archived/runtime_id 空 → `leader-missing`。
返回 `target{agent_id, runtime_id, issue_id, squad_id, project_id}`。任一级缺失不回退任意 Agent，整批回滚（FR-7）。

### 5xx 错误体（SDD §3.1，NFR-10）

```json
{"error":"approval continuation failed",
 "reasons":[{"cr_id":"CR-2026-052","stage":"tech-design","reason":"leader-missing"}]}
```

## 4. 验收条件

1. `go build ./...` 通过；`HandleGrantsAck` 现仅 5xx 来自预提交 tx/onGrantAck error，committed wake error 不置 5xx（AC-9a~c）。
2. resolveContinuationTarget 四级原因码 `workspace-mismatch`/`issue-missing`/`leader-missing` 结构化可检索；`grep` 确认无硬编码 agent id/名称。
3. 幂等：同记录两次 ACK → 第二次走阶梯 1 `already-queued`，HTTP 200，不重复入队（AC-1）。
4. `onGrantAck` handler 零外部副作用（不写表/不发事件/不入队/不取相交锁）——契约注释固化。

## 5. 完成标志

`HandleGrantsAck`/`GrantAckEvent`/双钩/`resolveContinuationTarget` 落盘 + 编译通过 + 单测覆盖幂等与 fail-closed 路径；Router 接线由 TASK-05 完成。

## 6. 接口契约

- **消费**：TASK-02 的 `AckApprovalGrants`/`GetCrShellIssueInWorkspaceForShare`/`LockIssueInWorkspaceForShare` 与既有 `LockSquadForAutopilotAssignment`/`GetAgentForUpdate`；TASK-03 的 `EnqueueApprovalContinuation`/`NotifyContinuationTaskEnqueued`/`ApprovalContinuationSpec`/`EnqueueOutcome`。
- **产出**（供 TASK-05 消费）：
  - `type GrantAckEvent struct{ WorkspaceID, CrID, RecordID, Stage, Decision string }`
  - `func (a *ApprovalService) SetGrantAckHandler(fn func(context.Context, GrantAckEvent) error)`
  - `func (a *ApprovalService) SetGrantAckCommittedHandler(fn func(context.Context, GrantAckEvent) error)`
