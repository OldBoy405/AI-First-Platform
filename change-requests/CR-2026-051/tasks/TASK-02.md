---
id: CR-2026-051-TASK-02
type: TASK
cr-ref: CR-2026-051
plan-ref: "change-requests/CR-2026-051/plan.md"
sdd-ref: "change-requests/CR-2026-051/sdd.md"
title: governance 门禁进入事件发布点（含 shell_issue_id 扩列）
slug: governance-approval-gate-publish
status: pending
estimate: 5h
depends-on: [CR-2026-051-TASK-01]
created: 2026-08-25T23:20:00+08:00
---

## 任务描述

在 `internal/governance` 的 CR 投影链路里加**唯一一个**发布点：只有当状态转换走到 `applyStatus` 的可信分支、且 `from != to`、且目标状态属于四个人工审批门禁时，才发布 `cr:approval-gate-entered`（SDD §3.2.1 / §4.1，FR-1/FR-2）。同时把 `applyStatus` 开头那条既有 `SELECT status` 扩为两列以取得 `shell_issue_id`（BL-3 的最小改法：零额外往返、零签名改动）。

本 TASK 只出生产侧代码；触发/隔离的真库断言归 TASK-03。

## 涉及文件 / 模块

仓根取 `execution_context.resources[]` 中 `repo=multica` 的 `worktreePath`；以下为该仓根相对路径：

- `server/internal/governance/crsync.go`（改：1 个常量别名 + 1 个包内 map + 1 个私有方法 + 既有 SELECT 扩列 + 可信分支内 1 处调用；全部带 `// AIFIRST: CR-2026-051` 英文注释）

零改动：`governance/approval.go`、`reconcile.go`、`gate_projection.go`、任何 sqlc query/生成物、任何迁移。

## 实现要点

1. **常量别名**（与同文件 `:48` 的 `EventCRUpdated` 完全同构）：`const EventCRApprovalGateEntered = protocol.EventCRApprovalGateEntered`。`protocol` 已在 crsync.go import（`:28`），不新增 import。
2. **四门禁集合**（包内私有，值以 `../tools/dir-graph.yaml#change-request-track.state_machine` 为准核对）：

   ```go
   var approvalGateStatuses = map[string]bool{
       "requirement-reviewing":      true,
       "tech-design-review-pending": true,
       "task-breakdown":             true,
       "code-reviewing":             true,
   }
   ```

3. **扩列**：`applyStatus`（`crsync.go:396`）开头的
   `SELECT status FROM cr WHERE workspace_id = $1 AND cr_id = $2`（`:399-401`）
   改为 `SELECT status, shell_issue_id::text FROM cr WHERE workspace_id = $1 AND cr_id = $2`，扫描目标为 `curStatus string` + 新增局部 `shellIssueID *string`。`::text` 显式转换 + `*string` 目标：pgx v5.9.2 的 `pointerPointerScanPlan`（`pgtype/pgtype.go:491-515`）在 NULL 时把指针置 nil，**无需新增 import**（不引 `pgtype`、不引 `internal/util`）。`pgx.ErrNoRows` 分支（`found=false`）逻辑与错误返回路径保持原样。
4. **发布方法**（签名固定，见接口契约）：`if s.bus == nil || ev.FromStatus == ev.ToStatus || !approvalGateStatuses[ev.ToStatus] { return }`，随后 `s.bus.Publish(events.Event{Type: EventCRApprovalGateEntered, WorkspaceID: workspaceID, ActorType: "system", Payload: protocol.ApprovalGateEnteredPayload{CRID: ev.CRID, Status: ev.ToStatus, EventID: ev.CRID + ":" + ev.EventKind + ":" + ev.CommitSHA, ShellIssueID: shellIssueID}})`。`event_id` 三段投影口径见 SDD DD-1；不拼 `workspace_id`（检索键是二元组 `(workspace_id, event_id)`）。
5. **唯一调用点**：`applyStatus` 的可信分支（`crsync.go:435` 的 `if curStatus == ev.FromStatus && KnownStatuses[…] && IsLegalTransition(…)`）内、`s.projectGateTransition(...)` **之后**。禁止在下列位置调用：`found == false` 首见分支（含 `legalFresh == true`）、`else`（`needs_reconcile`）分支、`apply` 的 `checkpoint`/`review`/`trace`/default 分支、`reconcile.go`、`gate_projection.go`。
6. 既有 `s.publish(ctx, workspaceID, ev.CRID)`（`cr:updated`）保持原样，不改其触发面、不删不挪。
7. multica 仓注释英文；发布方法注释须写明"只从可信分支发布、只在真实状态变化、只对四门禁"，以及 `shellIssueID` 来自同一条 SELECT（一次查询两列，不另开往返）。

## 验收条件

1. `cd server && go build ./... && go vet ./internal/governance/` 零报告。
2. `git diff --name-only` 在本 TASK 范围内**只有** `server/internal/governance/crsync.go` 一个文件。
3. `grep -n "publishApprovalGateEntered" server/internal/governance/*.go` 命中恰好 2 处（定义 1 + 可信分支调用 1），且 `reconcile.go`/`gate_projection.go`/`approval.go` 零命中。
4. `grep -n "shell_issue_id::text" server/internal/governance/crsync.go` 命中 1 处，且该 SELECT 仍带 `workspace_id = $1 AND cr_id = $2` 两个谓词（租户闭合未退化）。
5. 既有 governance 回归不因扩列破坏：`go test ./internal/governance/ -run 'TestCRSync|LegalFlowProjectsAndBroadcasts|OutOfOrder|IllegalTransition' -v -count=1` 全部 `--- PASS`（真库，C6 口径；`--- SKIP` 视为未测）。

## 完成标志

上述 5 条验收全通过（含真库 `--- PASS` 证据）；`crctl task done CR-2026-051 --task CR-2026-051-TASK-02 --workspace <kb worktree>` 已登记。发布点的行为断言（四门禁各一次 / 误触发零发布）不在本 TASK，由 TASK-03 取证——本 TASK 不得以"测试在下一个 TASK"为由跳过第 5 条既有回归。

## 接口契约

- **消费**（TASK-01 产出，精确签名）：`protocol.EventCRApprovalGateEntered`（string 常量）；`protocol.ApprovalGateEnteredPayload{CRID string; Status string; EventID string; ShellIssueID *string}`。既有依赖：`events.Event{Type, WorkspaceID, ActorType, Payload}`（`internal/events/bus.go:9`）、`(*events.Bus).Publish(events.Event)`（`bus.go:70`）、`OutboxEvent{CRID, EventKind, CommitSHA, FromStatus, ToStatus}`（`crsync.go:86-99`）。
- **产出**：
  - `const governance.EventCRApprovalGateEntered = protocol.EventCRApprovalGateEntered`（导出，TASK-03 断言用）；
  - `var approvalGateStatuses map[string]bool`（包内私有，TASK-03 可直接引用做全量遍历）；
  - `func (s *SyncService) publishApprovalGateEntered(workspaceID string, ev OutboxEvent, shellIssueID *string)`（包内私有；TASK-03 通过 `HandleCREvents`/`applyStatus` 间接触发，不直接调用私有方法之外的形态）。
