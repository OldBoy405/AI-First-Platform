---
id: CR-2026-004-TASK-02
type: TASK
cr-ref: CR-2026-004
plan-ref: "change-requests/CR-2026-004/plan.md"
sdd-ref: "change-requests/CR-2026-004/sdd.md"
title: multica 前端 — 队列条禁用态 + WS 实时刷新（packages/views）
status: pending
estimate: 6h
depends-on: [CR-2026-004-TASK-01]
assignee: ""
created: "2026-08-01T00:55:00+08:00"
---

## 任务描述
在 `packages/views`（web + desktop 自动共享）实现队列深度显示与满队禁用态。SDD §3.5 为实现依据；依赖 TASK-01 的 API 契约（429 响应体、queue_depth/queue_limit）。

## 涉及文件
- `packages/views` 内项目聊天/任务相关组件（队列条显示 + 输入区禁用态；具体组件实现期定位，改动收敛在 views 包内）
- WS 事件订阅处：把 `task:running`、`task:completed`、`task:failed` 加入队列数 query 失效触发（`task:queued`/`task:cancelled` 既有基础上；`task:dispatch` 明确不监听——SDD §3.5）

## 实现要点
- 满 & 非 owner/admin → 输入区禁用 + 「Agent 忙，请稍后」；收到 429 `project_queue_full` 同样进禁用态；深度 < limit 自动恢复。
- 权限裁决在服务端，前端禁用态只是体验优化——不做前端侧角色判断的安全假设。
- 排队项显示发起人，发起人可撤回自己的排队项（调 TASK-01 撤回端点），403/409 用 toast 呈现。
- mobile 不在范围（RN 不共享 views 包）。

## 验收条件
1. 组件测试（vitest）：深度=limit 且角色 member → 输入禁用 + 提示文案；角色 owner/admin → 不禁用。
2. 组件测试：模拟 WS `task:running` 事件 → 队列数 query 失效重取（深度 -1 正确反映）。
3. 手动验证：双浏览器会话，一侧入队/撤回，另一侧队列数无刷新自动更新。
4. `pnpm test`（views 包）+ lint + typecheck 零报错。

## 完成标志
测试全绿 + worktree commit + 完成记录回填本文件。
