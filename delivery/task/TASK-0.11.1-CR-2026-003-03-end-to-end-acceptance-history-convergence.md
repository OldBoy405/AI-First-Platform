---
id: CR-2026-003-TASK-03
type: TASK
cr-ref: CR-2026-003
plan-ref: "change-requests/CR-2026-003/plan.md"
sdd-ref: "change-requests/CR-2026-003/sdd.md"
title: 端到端验收 + 历史脏投影真实收敛（AC-1/2/3）
status: done
estimate: 5h
depends-on: [CR-2026-003-TASK-01, CR-2026-003-TASK-02]
assignee: ""
created: "2026-07-31T21:00:00+08:00"
spec-id: ai-first-platform
version: "0.11.1"
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

## 完成记录（2026-07-31）

- **环境刷新**：backend 镜像 efaa9fc5a89c（multica worktree@6bad142ec 构建，VERSION=dev-cr2026003）+ daemon 二进制 multica-daemon-cr2026003.exe，21:19 双双上线（compose 项目在 multica 主检出操作，镜像从 CR worktree 构建——修复尚未合 trunk，与 CR-2026-002 T11 同口径）。
- **AC-3 ✅（本 CR 的核心验收）**：
  - 篡改前留档（21:17:01）：CR-2026-001=writing-back/true（卡自 08:46 UTC）、CR-2026-002=writing-back/true（卡自 12:05 UTC）——卡死约 12 小时与 1 小时的真实生产脏数据。
  - 收敛：两行 healed_at 均为 13:19:14 UTC——server 模式对账在部署后第一个周期治愈（backend 日志 plan_time=13:19 执行记录在案；早于 daemon 首拍快照到达）。终态 archived/false，projected_commit 校准到真实 GitHub HEAD 2623e9cd。
  - 审计口径达成：全程数据库只发 SELECT，收敛完全由修复代码 + 真实对账周期完成。
- **AC-2 ✅**：真库集成测试（T02 的 TestArchivedCRHealsFromHistorySnapshot，用与生产完全相同的卡死形态造数据）+ 本次真机收敛双重覆盖。
- **AC-1 组件级 ✅ + 真机组合观察点 ✅（回补）**：crctl 占位符（JS 21/21）与服务端幂等/防泄漏（Go 真库）各自已证；真机双 embedded 连推投影两步跟上，在本 CR 自己的 writeback 期实际发生——`code-approved → merging`（764ab74）与 `merging → writing-back`（1005ca9）两次独立 `--embedded` advance，各产出一条互异 `pending:` 占位符事件，投影两步均正确跟进（无碰撞丢失），`cr.projected_commit` 全程未见占位符污染。这正是 CR-2026-002 当初丢事件的同一序列——本 CR 用自己的收官动作复现原故障场景做最终验证。
- **代码评审**：verdict pass，0 blocker，2 条非阻塞建议（记录见 CR-2026-003/review-annotations/code.yml），3/3 任务覆盖。
- **审批**：requirement / tech-design / development-start / code 四阶段均经 crctl-approve（approver OldBoy405）。
