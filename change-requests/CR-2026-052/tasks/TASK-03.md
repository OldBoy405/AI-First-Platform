---
id: CR-2026-052-TASK-03
type: TASK
cr-ref: CR-2026-052
plan-ref: "change-requests/CR-2026-052/plan.md"
sdd-ref: "change-requests/CR-2026-052/sdd.md"
title: "TaskService：EnqueueApprovalContinuation + NotifyContinuationTaskEnqueued"
slug: taskservice-approval-continuation-enqueue
status: pending
estimate: 5h
depends-on: ["CR-2026-052-TASK-02"]
created: 2026-08-27T10:44:32+08:00
---

# TASK-03：TaskService 续跑入队方法

## 1. 任务描述

在 `server/internal/service/task.go` 的 `TaskService` 新增两个方法：事务内续跑任务入队（含阶梯 1/2/3 幂等语义）与提交后事件广播。复用既有列与 `EnqueuePipelineTask` 的形态先例（agent.sql:651）。对应 SDD §1.3/§4.1/§4.3，闭合 TD-BL-7/9/10/11 的合并阶梯。

## 2. 涉及文件 / 模块

- 修改 `server/internal/service/task.go`
- 复用既有 `broadcastTaskEvent`（task.go:6941）、`NotifyTaskEnqueued`（task.go:6746）、`priorityToInt`（task.go:6726）

## 3. 实现要点（SDD §4.1/§4.3）

### 类型与枚举

```go
type EnqueueOutcome string
const (
    OutcomeAlreadyQueued     EnqueueOutcome = "already-queued"
    OutcomeMerged            EnqueueOutcome = "merged"
    OutcomeSuccessorEnqueued EnqueueOutcome = "successor-enqueued"
    OutcomeSlotDeferred      EnqueueOutcome = "slot-deferred"
)

type ApprovalContinuationSpec struct {
    WorkspaceID     pgtype.UUID   // 认证 daemon workspace，写入 approval_workspace_id
    AgentID, RuntimeID pgtype.UUID
    IssueID         int64
    SquadID, ProjectID pgtype.UUID
    CrID            string // CR-2026-052 原值，不再拼 CR- 前缀（TD-SUG-3）
    RecordID        string // approval_record.id text
    Stage, Decision string // approve|reject；requirement|tech-design|dev-start|code
    ApproverUserID  pgtype.UUID // originator/accountable（DD-7）
}
```

### EnqueueApprovalContinuation（事务内，纯 DB 写）

签名：`func (s *TaskService) EnqueueApprovalContinuation(ctx context.Context, qtx db.QueryParam, spec ApprovalContinuationSpec) (db.AgentTaskQueue, EnqueueOutcome, error)`

逻辑（SDD §4.3 阶梯）：
1. `CreateApprovalContinuationTask(qtx, …, status='queued', handoff/context approvals[本记录1项])` → `ON CONFLICT DO NOTHING RETURNING *`；命中 → `OutcomeSuccessorEnqueued`，返回新建行（提交后广播）。
2. 0 行 → 阶梯 1：`GetApprovalContinuationTaskByRecord(qtx, ws, recordID)` 命中 → `OutcomeAlreadyQueued`（不广播）。
3. 0 行 → 阶梯 2：`GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate(qtx, ws, crID)`（queued/deferred FOR UPDATE）命中 → `AppendApprovalContinuationEvidence`（NOT EXISTS 防同记录重复追加）→ `OutcomeMerged`（不广播，后继非新建行）。
4. 0 行 → 阶梯 3：`CreateApprovalContinuationTask(qtx, …, status='deferred', fire_at=now())`（257 谓词外）→ 命中 `OutcomeSlotDeferred`；仍 0 行 → `tx-failure` error（不静默降级，纪律 1）。

`handoff_note` 模板（TD-SUG-3，{cr_id} 原值）：`"{cr_id} 的 {stage} 审批已 {decision}（approval_record_id={id}）。请读取 .crctl/grants/ 与 crctl status/next 确定下一步；本提示不携带任何状态→下一步映射。"`

`context` JSON（TD-SUG-4，机器可读，approvals[] 可追加）：`{"type":"approval_continuation","schema":"ai-first.approval-continuation/v1","approvals":[{"cr_id","stage","decision","approval_record_id"}]}`。

`is_leader_task=true`、`squad_id`=spec.SquadID、`originator_user_id`/`accountable_user_id`=spec.ApproverUserID、`originator_source='direct_human'`、`trigger_evidence_kind='approval_continuation'`、`trigger_evidence_ref_id`=spec.RecordID、`cr_id`=spec.CrID、`priority=priorityToInt(issue.Priority)`、`trigger_summary`=`"{cr_id} approval {stage}: {decision}"`。`runtime_mcp_overlay`/`runtime_connected_apps` 留空（仿 CreatePipelineTask，§2.4 注）。

### NotifyContinuationTaskEnqueued（提交后）

签名：`func (s *TaskService) NotifyContinuationTaskEnqueued(ctx context.Context, task db.AgentTaskQueue) error`

逻辑（TD-SUG-1，与 EnqueuePipelineTask 尾部一致 task.go:415-416）：`broadcastTaskEvent(ctx, EventTaskQueued, task)` + `NotifyTaskEnqueued(ctx, task)`。仅对新建行（outcome ∈ successor-enqueued / slot-deferred）调用 `NotifyContinuationTaskEnqueued`（幂等命中 already-queued / 合并 merged 不重复广播，由调用方 TASK-04 按 outcome 决定调用与否）。

## 4. 验收条件

1. `go build ./...` 与 `go vet ./internal/service/...` 通过。
2. 单测覆盖四阶梯返回值（mock qtx）：新建 queued / already-queued / merged（approvals[] 追加 1 项）/ slot-deferred（status=deferred fire_at=now）；阶梯全未命中返回 tx-failure error 不静默。
3. `handoff_note`/`context`/归因字段与 SDD §2.4 行形状表逐字段一致；`{cr_id}` 无 `CR-` 双前缀。

## 5. 完成标志

两方法落盘 + 编译通过 + 单测覆盖四阶梯；不直接读/写受控账本（`_index.yml` 由 crctl 独占）。

## 6. 接口契约

- **消费**：TASK-02 的 `CreateApprovalContinuationTask` / `GetApprovalContinuationTaskByRecord` / `GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate` / `AppendApprovalContinuationEvidence`（经 qtx）；既有 `broadcastTaskEvent` / `NotifyTaskEnqueued` / `priorityToInt`。
- **产出**（供 TASK-04 消费）：
  - `func (s *TaskService) EnqueueApprovalContinuation(ctx context.Context, qtx db.QueryParam, spec ApprovalContinuationSpec) (db.AgentTaskQueue, EnqueueOutcome, error)`
  - `func (s *TaskService) NotifyContinuationTaskEnqueued(ctx context.Context, task db.AgentTaskQueue) error`
  - `type EnqueueOutcome string`（四常量）、`type ApprovalContinuationSpec struct{…}`
