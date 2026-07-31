---
id: CR-2026-002-TASK-05
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: 服务端投影 worker（governance/crsync.go）+ POST /api/daemon/cr-events + WS 广播
status: pending
estimate: 16h
depends-on: [CR-2026-002-TASK-04]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
FR-2 服务端半边：事件入库、幂等去重、per-CR 串行消费、合法转移校验、cr 行与壳 Issue 7 态更新、WS 广播。仓库：multica。

## 涉及文件
- 新增 `server/internal/governance/crsync.go`（+ `crsync_test.go`）
- 修改 `server/cmd/server/router.go`：DaemonAuth 组挂 `POST /api/daemon/cr-events`（AIFIRST 标记，同 M0 模式）
- handler 薄层可放 governance 包内（不新建 handler 目录，减少上游冲突面）

## 实现要点
- 入库 `INSERT ... ON CONFLICT DO NOTHING`，冲突即已处理（幂等）。
- workspace_id 从 DaemonAuth 上下文解析（SDD-SUG-002）；事件体的 workspace_root_hash 仅日志用。
- per-CR 互斥：`sync.Map[string]*sync.Mutex`；`IsLegalTransition`（T04 产物）不合法 → `needs_reconcile=true`。
- commit_sha=="" 事件延迟 60s 处理（等 push 补全事件），用内存定时器即可（单节点起步）。
- 壳 Issue 7 态映射按 P0 §4.1 表；WS 用既有 `events.Bus` → Hub，scope `workspace:{id}` / `issue:{id}`。
- 单批 ≤100 事件；响应 `{accepted:[文件名], rejected:[{file,code}]}`。

## 验收条件
1. 集成测试：同一事件双通道重复提交 → cr_sync_event 仅一行（AC-2①）。
2. 集成测试：乱序注入（先 to=B 后 from 缺失）→ needs_reconcile=true 且投影不变（AC-2②）。
3. 集成测试：合法事件 → cr 行更新 + WS 收到 cr.updated（AC-2③）。
4. mat_ 令牌调 cr-events 端点 → 401/403（DaemonAuth 只认 mdt_）。

## 完成标志
go test ./internal/governance/... 绿 + 既有测试基线不回归（3 个 Traecli/Qoder 已知失败除外）+ 完成记录回填。
