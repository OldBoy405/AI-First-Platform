---
id: CR-2026-003-TASK-03
type: TASK
cr-ref: CR-2026-003
plan-ref: "change-requests/CR-2026-003/plan.md"
sdd-ref: "change-requests/CR-2026-003/sdd.md"
title: 端到端验收 + 历史脏投影真实收敛（AC-1/2/3）
status: pending
estimate: 5h
depends-on: [CR-2026-003-TASK-01, CR-2026-003-TASK-02]
assignee: ""
created: "2026-07-31T21:00:00+08:00"
---

## 任务描述
环境刷新（重建 backend 镜像 + 重启 daemon，均含 T01/T02 修复）后，真机串联三条 AC，重点是 AC-3：CR-2026-001 与 CR-2026-002 两条卡了一天的脏投影行，必须由修复代码在真实对账周期内自然收敛，不允许手工 UPDATE。

## 涉及文件
- 无新代码（验收动作）；证据记录到本文件完成记录 + test-report.md

## 实现要点
- 环境刷新在 multica 主检出操作（compose 项目已迁离 CR worktree，见 CR-2026-002 cleanup-report side-effects-handled）。
- AC-1 真机：本 CR 自己后续的 embedded 推进（writeback 期两连推）就是天然测试场——留意投影是否两步都跟上。
- AC-3 观察窗：RECONCILE_INTERVAL=1m（验收环境现配），一个周期内应可见收敛。server 模式与 daemon snapshot（5m 或重启首拍）谁先到都算——两模式共用合并快照逻辑。

## 验收条件
1. AC-1：真机双 embedded 推进后，`cr_sync_event` 出现两条 `pending:` 前缀事件且投影两步到位；`cr.projected_commit` 无占位符污染。
2. AC-3：`SELECT status, needs_reconcile FROM cr WHERE cr_id IN ('CR-2026-001','CR-2026-002')` → 两行均 `archived / false`，且有对账周期时间线证据（篡改前查询 + 周期后查询 + backend 日志 rows_affected）。
3. 全程无手工数据库写入（审计口径：本任务只允许 SELECT）。

## 完成标志
三条 AC 证据记录 + 完成记录回填 → write-test-report。
