---
id: CR-2026-045-TASK-09
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: 唤醒接线、grant ACK 与 router wiring
slug: wakeup-wiring-grant-ack-router
status: pending
estimate: 6h
depends-on:
  - CR-2026-045-TASK-07
created: 2026-08-17T20:39:31+08:00
---

# TASK-09 唤醒接线、grant ACK 与 router wiring

## 1. 任务描述

把 Reconcile 接上四类唤醒来源：`cr:updated` 事件、`task:completed`/`task:failed` 事件、`HandleGrantsAck` 直接唤醒、server 启动后一次性扫描。并在 router 挂载 Start endpoint。事件只是唤醒，不是权威事实；丢失唤醒由后续事件或启动扫描恢复。

## 2. 涉及文件 / 模块

- `server/internal/events/bus.go` 或现有订阅处（`cr:updated`、task terminal 订阅调 Reconcile）
- `server/internal/governance/approval.go`（`HandleGrantsAck` 更新 `delivered_at` 后按 ACK IDs 查受影响 CR 并调 Reconcile）
- `server/cmd/server/router.go`（`POST /api/workspaces/{workspaceID}/pipeline-runs` 挂载）
- `server/cmd/server/main.go` 或启动流程（启动扫描非终态 Core run）
- 相应测试（唤醒/ACK/启动扫描断言）

## 3. 实现要点

- `cr:updated`：从 payload 取 `cr_id` 调 `Reconcile`；`task:completed`/`task:failed`：仅当 task 有 `pipeline_node_run_id` 时查 run 并 `Reconcile`。
- `HandleGrantsAck` 更新 `delivered_at` 后直接调 `Reconcile`，不新增会被 WS `SubscribeAll` 外发的内部事件。
- 启动扫描只取 `runner=architecture-core/v1` 的非终态 run，数量与在途 architecture CR 同阶。
- Router 的 Start 只接受 task-token（TASK-07 已定义 handler 约束），零额外鉴权旁路。
- 重复投递幂等：同一事件多次触发 Reconcile 不产生重复 run/node/task（AC-11）。

## 4. 验收条件

1. 四类唤醒均能驱动 Reconcile；grant 记录未 delivered 不入队，ACK 后一次入队。
2. 重复投递 task terminal/review/approval/CR status 各至少两次，最终有效 run/node/task 数量与单次相同（AC-11）。
3. 启动扫描在四窗口（首 task 入队后 / review block 后 / grant ACK 后 / checkpoint 后）继续同一 run 且无重复有效 task（AC-12）。
4. 关闭 Runner（feature off）时事件与扫描零接管，手动路线不变（AC-15）。

## 5. 完成标志

四类唤醒接线 + ACK 唤醒 + router 挂载 + 启动扫描落地 + 幂等/恢复断言通过。

## 6. 接口契约

- 消费：TASK-07 的 `Reconcile(ctx, wsID, crID)` 与 `StartArchitecture`。
- 产出：事件/ACK/启动扫描到 Reconcile 的接线；`POST /api/workspaces/{workspaceID}/pipeline-runs` 端点；TASK-11 的 E2E 依赖完整唤醒链。
