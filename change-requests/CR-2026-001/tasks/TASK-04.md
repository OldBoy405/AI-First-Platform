---
id: CR-2026-001-TASK-04
type: TASK
cr-ref: CR-2026-001
plan-ref: "change-requests/CR-2026-001/plan.md"
sdd-ref: "change-requests/CR-2026-001/sdd.md"
title: issue-dispatch-smoke — 派 Issue 给 Agent 的端到端冒烟
status: pending
estimate: 4h
depends-on: [CR-2026-001-TASK-03]
assignee: ""
created: "2026-07-30T22:43:34+08:00"
---

# TASK-04 issue-dispatch-smoke — 派 Issue 给 Agent 的端到端冒烟

## 任务描述

对应 FR-3 / SDD 组件 `issue-dispatch-smoke`。无新代码，是一次可复现的验收动作：验证"派 Issue → daemon 领取 → 本机执行完成"闭环。执行前确认本机 `claude` CLI 可用且 daemon 已配对。

## 涉及文件 / 模块

- Multica Web UI 或 CLI（建 Issue、指派 Agent）
- 观察面：`agent_task_queue` 表（claim 行为）、Issue 状态、执行摘要/task_message

## 实现要点

- Issue 任务描述里**预先写入约定结果标记**（一段可核对文本，如 `SMOKE-CR-2026-001-OK`），要求 Agent 在完成输出中原样回显——这是 PRD AC-3 的判定信号，不靠"看起来跑完了"
- 记录完整时间线：入队时刻、claim 时刻、完成时刻
- 若 daemon/CLI 环境不可用：按 plan.md 风险条目降级为只验证 claim 行为，并在记录中明确"执行段未验证"，不得把降级结果报成全通过

## 验收条件

1. daemon 在无人工干预下领取该 Issue（`agent_task_queue` 出现对应 claim 行）
2. 执行完成后 Issue 状态字段变为 `done`，且执行摘要中出现预先约定的结果标记（AC-3 完整口径）

## 完成标志

两条验收全过；冒烟过程（Issue 链接/ID、时间线、结果标记截图或文本）记录进本 CR 的 test-report.md 素材。
