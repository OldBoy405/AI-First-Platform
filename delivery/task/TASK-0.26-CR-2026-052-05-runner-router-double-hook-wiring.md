---
spec-id: ai-first-platform
version: "0.26"
id: CR-2026-052-TASK-05
type: TASK
cr-ref: CR-2026-052
plan-ref: "change-requests/CR-2026-052/plan.md"
sdd-ref: "change-requests/CR-2026-052/sdd.md"
title: "Runner ValidateGrantAck/WakeGrant 适配 + router 双钩接线"
slug: runner-router-double-hook-wiring
status: pending
estimate: 4h
depends-on: ["CR-2026-052-TASK-04"]
created: 2026-08-27T10:44:32+08:00
---

# TASK-05：Runner 适配与 router 接线

## 1. 任务描述

唯一消费方 Architecture Runner 同批调整：`ValidateGrantAck`（预提交纯校验）注册到 `SetGrantAckHandler`，`WakeGrant`（提交后真实 Reconcile）注册到 `SetGrantAckCommittedHandler`；router.go 接线点替换为两处。对应 SDD §1.3/§3.2，闭合 TD-BL-6/12 消费方约束。

## 2. 涉及文件 / 模块

- 修改 `server/internal/governance/runner.go`（`WakeGrant` 签名扩展、新增 `ValidateGrantAck`）
- 修改 `server/cmd/server/router.go:1399-1408`（接线点）

## 3. 实现要点（SDD §1.3/§3.2）

### runner.go

`WakeGrant` 现签名 `func(ctx, workspaceID pgtype.UUID, crID string) error` → 扩展为 `func(ctx context.Context, ev governance.GrantAckEvent) error`。其内部仍调 `Reconcile(ctx, ev.WorkspaceID, ev.CrID)`（重读 approval_record 为权威，runner.go:764-765 现有语义保留）；error 仅日志、HTTP 2xx（committed 阶段）。

新增 `ValidateGrantAck(ctx context.Context, ev governance.GrantAckEvent) error`：
- 纯校验、零外部副作用——不取 advisory lock、不写 pipeline_run/pipeline_node_run、不入队 task、不调 Reconcile。
- 校验 `ev` 字段：workspaceID/crID 非空、RecordID 可解析为 UUID、stage ∈ 四类、decision ∈ {approve,reject}；只读确认 cr 在该 workspace 存在（复用 `GetCrShellIssueInWorkspaceForShare` 或等价只读）。
- 返回 error → ACK 事务回滚 + HTTP 5xx（FR-10 canonical callback）。

### router.go（§1.3，NFR-8）

现状（router.go:1399-1408）：
```go
if governance.ArchitectureRunnerEnabled() {
    ...
    approvalSvc.SetGrantAckHandler(architectureRunner.WakeGrant)
}
```
改为两处接线（编译契约同批收敛）：
```go
if governance.ArchitectureRunnerEnabled() {
    ...
    approvalSvc.SetGrantAckHandler(architectureRunner.ValidateGrantAck)         // 预提交纯校验
    approvalSvc.SetGrantAckCommittedHandler(architectureRunner.WakeGrant)       // 提交后真实 wake
}
```
Runner 关闭（`AIFIRST_ARCHITECTURE_RUNNER` 未设置）时两钩均无人接线，通用 continuation 入队仍生效（AC-8）——不改 `ArchitectureRunnerEnabled()` 默认关闭语义。

## 4. 验收条件

1. `go build ./...` + `go vet ./internal/governance/... ./cmd/...` 通过；`WakeGrant` 旧签名调用点零残留（grep 确认）。
2. Runner 开启时两钩正确接线（AC-9d）；关闭时 `onGrantAck`/`onGrantAckCommitted` 均为 nil，`HandleGrantsAck` 仍 commit+200（AC-8 断言日志/覆盖）。
3. `ValidateGrantAck` 不触 advisory lock / 不写 pipeline_run / 不入队（单测断言零副作用）。

## 5. 完成标志

runner.go + router.go 改动落盘 + 编译通过 + 接线验证；不启用 Runner（保持默认关闭，FR-9）。

## 6. 接口契约

- **消费**：TASK-04 的 `GrantAckEvent` 类型与 `SetGrantAckHandler`/`SetGrantAckCommittedHandler` 方法；TASK-02 的只读 cr 查询（ValidateGrantAck 校验用）。
- **产出**：
  - `func (r *Runner) ValidateGrantAck(ctx context.Context, ev governance.GrantAckEvent) error`
  - `func (r *Runner) WakeGrant(ctx context.Context, ev governance.GrantAckEvent) error`（签名扩展，NFR-8 编译兼容同批调整）
