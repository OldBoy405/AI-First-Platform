---
id: CR-2026-002-TASK-05
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: 服务端投影 worker（governance/crsync.go）+ POST /api/daemon/cr-events + WS 广播
status: done
estimate: 16h
depends-on: [CR-2026-002-TASK-04]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
spec-id: ai-first-platform
version: "0.11"
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

## 完成记录（2026-07-31）

- **提交**：multica worktree c23748904（requirement/CR-2026-002，已推 fork）。
- **crsync.go**（~280 行，纯 governance 包 + router 1 处 AIFIRST 挂载）：批量 ≤100 校验 → 逐事件 schema 校验（BAD_EVENT/UNKNOWN_KIND 按 file 回执）→ `ON CONFLICT DO NOTHING` 幂等入账（重复到达仍 ack accepted，daemon 才会删两个通道的源文件）→ per-CR `sync.Map` 互斥 → `IsLegalTransition` 校验（T04 产物）→ 合法更新 / 乱序或非法只置 `needs_reconcile` 不强写 → `cr:updated` 发 events.Bus（`SubscribeAll` 既有监听自动广播 workspace 房间，零接线）。
- **信任边界**（SUG-002 落实）：workspace 绑定只取 `middleware.DaemonWorkspaceIDFromContext`；缺失 → 403；请求体 `workspace_root_hash` 仅日志。测试助手用上游现成 `WithDaemonContext`。
- **有意简化（偏离源方案一处，记录在案）**：§A.5 的"空 SHA 事件延迟 60s"未实现——状态应用从不依赖 SHA，checkpoint 事件到达时补写 `projected_commit` 即可，延迟机制无存在必要（代码注释同步说明）。
- **测试 9/9**（6 新集成 + 3 个 T04）：合法链投影+WS 双事件、双通道单行、乱序→needs_reconcile 且状态不变、非法转移同、checkpoint 补全空 SHA、403/400/逐条拒绝码。跑在真实 PG 上（socat 边车把容器 5432 发布到宿主；迁移 158 已按 runner 口径应用到本机库并记 schema_migrations）。
- **sqlc 决策**：governance 直接用 pgx，不动上游 sqlc query 文件（规则一冲突面考量，代码注释注明）。
- **全量基线 A/B**：新发现 `cmd/multica` 7 项 + `internal/cli` 4 项失败，在未改动的 main 检出复跑**完全一致**→ 上游既有（Windows 环境类），已扩充 CUSTOM.md 基线表；另记录本机 gofmt 对上游 794 文件报格式差异（工具链版本差异，fork 新文件必须过本机 gofmt，上游文件不动）。
