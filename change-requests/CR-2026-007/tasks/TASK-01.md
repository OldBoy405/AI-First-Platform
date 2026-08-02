---
id: CR-2026-007-TASK-01
type: TASK
cr-ref: CR-2026-007
plan-ref: "change-requests/CR-2026-007/plan.md"
sdd-ref: "change-requests/CR-2026-007/sdd.md"
title: queue-status include=items 端点扩展 + AgentTaskResponse originator 字段
slug: queue-items-endpoint
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-02T13:10:00+08:00"
---

## 任务描述
实现 SDD DD-3 的队列明细读侧扩展与 DD-1 的 originator 附加字段。本任务是
**TSUG-001/TSUG-002(后端半边)/TSUG-004(半)/TSUG-005** 的落地点。

## 涉及文件
- `server/pkg/db/queries/agent.sql`：新查询 `ListProjectPendingTasks`
  （**TSUG-005**：放这里、与 agent.sql:1017 的 `CountProjectPendingTasks` 相邻，不放 project.sql）
- `server/internal/handler/project.go`：`GetProjectQueueStatus` 加 `include=items` 分支
- `server/internal/handler/agent.go`：`AgentTaskResponse` 增 `originator_user_id`（omitempty）+ `taskToResponse` 组装
- sqlc 重生成（CRLF 甄别：`git diff --ignore-all-space --numstat` 只保留真变更）

## 实现要点
1. 查询：`agent_task_queue` JOIN issue（project 过滤）**LEFT JOIN users**（技术评审
   blocker 3：INNER JOIN 会丢 originator 为 NULL 的 autopilot/agent 来源任务，
   造成 items 数 < queue_depth）；`status IN ('queued','dispatched')` 与
   `CountProjectPendingTasks` 口径**逐字一致**；`ORDER BY priority DESC, created_at ASC`。
2. **TSUG-001**：items[].summary 直接 SELECT 既有 `agent_task_queue.trigger_summary` 列
   （入队时已截断落库 + 跨 workspace 防泄漏 MUL-4252）——**不** JOIN comment、不在
   handler 二次截断。
3. 响应 shape（SDD DD-3 JSON）：originator 对象可为 null；无参调用走原路径**逐字节不变**。
4. **TSUG-002（后端半边）**：`taskToResponse` 增 `originator_user_id`（omitempty），
   供前端"是我发起的"判定（运行卡停止钮可见性，T05 消费）。
5. 权限：与现端点一致（workspace 成员）。
6. 单测（**TSUG-004 半**）：
   - include 参数向后兼容对拍：无参响应与改动前逐字节一致；
   - 口径断言：造数含 NULL originator 任务，`queue_depth == len(items)`；
   - 顺序断言：owner 插队项（priority 100）排前；
   - trigger_summary 空的任务 summary 为空串（不报错）。
