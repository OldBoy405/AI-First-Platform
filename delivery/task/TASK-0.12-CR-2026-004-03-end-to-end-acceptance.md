---
id: CR-2026-004-TASK-03
type: TASK
cr-ref: CR-2026-004
plan-ref: "change-requests/CR-2026-004/plan.md"
sdd-ref: "change-requests/CR-2026-004/sdd.md"
title: 端到端验收（AC-1~5 真机）
status: done
estimate: 4h
depends-on: [CR-2026-004-TASK-01, CR-2026-004-TASK-02]
assignee: ""
created: "2026-08-01T00:55:00+08:00"
spec-id: ai-first-platform
version: "0.12"
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

## 完成记录（2026-08-01）

- 详细证据见 `change-requests/CR-2026-004/test-report.md`。要点：
  - 环境刷新：backend `d2c68b46ecc2` + web `2f985eebbc7a`（均自 worktree@da03782a8 构建）；迁移 159 由新后端干净应用。
  - AC-3 ✅（默认 50 / 配置 2 全 API）；AC-1 ✅（满队 member 入队被守卫拒，issue 落库任务零行，backend 拒绝日志留证）；AC-2 ✅（owner priority=100 晚建 90s 仍先被 claim，dispatched_at 时间戳证据）；AC-4 ✅（403 not_task_originator / originator 撤回 / 4 条 cancelled 审计行保留）；AC-5 ⚠️ 双端分别验证，双浏览器观察挂人工补验项（环境无浏览器自动化）。
  - 审计口径达成：数据库全程只 SELECT；造数全走真实 API（含第二个 member 用户的 send-code→验证码 SELECT→verify→邀请→accept 全 API 建立）。
  - 验收编排记录：daemon 停机窗口造 queued fixture → AC-1/3/4 → 重启 daemon 观察 AC-2 claim 顺序 → 立即 cancel 止损；现场已还原（agent 可见性 private、杂项目删除、daemon 保持运行）。
  - 发现（非缺陷）：quick-create 的 runtime 可用性预检（422）先于容量守卫（429）——次序合理，已记录。
