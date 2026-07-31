---
id: CR-2026-004-TASK-03
type: TASK
cr-ref: CR-2026-004
plan-ref: "change-requests/CR-2026-004/plan.md"
sdd-ref: "change-requests/CR-2026-004/sdd.md"
title: 端到端验收（AC-1~5 真机）
status: pending
estimate: 4h
depends-on: [CR-2026-004-TASK-01, CR-2026-004-TASK-02]
assignee: ""
created: "2026-08-01T00:55:00+08:00"
---

## 任务描述
环境刷新（重建 backend 镜像 + 前端构建，daemon 无改动不换）后，真机串联 PRD 五条 AC。证据记录到本文件完成记录 + test-report.md。

## 涉及文件
- 无新代码（验收动作）

## 实现要点
- 验收顺序（plan §5）：AC-1 满队拒绝 → AC-3 配置上限生效（设为 2 快速触发满队）→ AC-2 owner/admin 插队先被 claim → AC-4 撤回软删 + 审计行保留 → AC-5 WS 双会话实时更新。
- 用 AC-3 的小上限（2）做 AC-1/AC-2 的触发条件，避免真造 50 条排队。
- 数据库全程只 SELECT（平台审计口径）；队列造数走真实入队 API。

## 验收条件
1. AC-1：满队时 member 入队 → HTTP 429 `project_queue_full` + `agent_task_queue` 无新行 + 前端禁用态。
2. AC-2：满队时 owner 入队落库 priority=100，且先于更早的 member 任务被 claim（查 `dispatched_at` 顺序）。
3. AC-3：project settings `team_agent_queue_limit=2` 后按新值生效；未配置项目按 50。
4. AC-4：撤回后行保留 `status='cancelled'`（SELECT 取证）；容量统计减一（后续入队成功）。
5. AC-5：双浏览器会话队列数实时一致。

## 完成标志
五条 AC 证据记录 + 完成记录回填 → write-test-report。
