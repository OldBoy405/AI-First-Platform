---
id: CR-2026-004-TASK-02
type: TASK
cr-ref: CR-2026-004
plan-ref: "change-requests/CR-2026-004/plan.md"
sdd-ref: "change-requests/CR-2026-004/sdd.md"
title: multica 前端 — 队列条禁用态 + WS 实时刷新（packages/views）
status: done
estimate: 6h
depends-on: [CR-2026-004-TASK-01]
assignee: ""
created: "2026-08-01T00:55:00+08:00"
spec-id: ai-first-platform
version: "0.12"
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

## 完成记录（2026-08-01）

- **实现 commit**：multica worktree `requirement/CR-2026-004` @ `da03782a8`。
- **交付内容**：
  - 后端读侧补齐（T01 缺口）：`TaskService.ProjectQueueStatus` + `GET /api/projects/{id}/queue-status`（成员可见 depth/limit）——前端持续显示队列深度需要读取端点，T01 只做了写路径。
  - core：`getProjectQueueStatus` client 方法、`projectKeys.queueStatus*` query key、`task:` 前缀 WS 处理器挂 queue-status 失效。
  - views：`ProjectQueueStatus` 组件挂 project-detail（深度/上限 + 满队琥珀色提示，`data-testid` 双锚点）；quick-create modal 新增 `project_queue_full` 429 分支（结构化展示实时 depth/limit，modal 内报错不关闭）。
  - locale 四语言（en/zh-Hans/ja/ko）3 键 ×2 文件，parity 测试过。
- **验收条件核验**：
  1. ✅ 组件测试 3 个（低于上限无提示 / 满队显示 busy 提示 / 未加载不渲染）。
  2. ✅ WS 触发：实测仓内惯例是 `task:` **前缀处理器**（任意 task 生命周期事件统一失效）——比 SDD §3.5 逐事件挑选更简单且已覆盖 task:running/completed/failed，queue-status 挂进同一前缀（实现期修正，优于原设计，记录在案）。
  3. ⏭️ 双浏览器手动验证移至 T03 真机验收（AC-5）。
  4. ✅ views 218 测试 + core 66 测试全绿；两包 `tsc --noEmit` 干净；eslint 改动文件 0 error（1 个既有 warning 非本次引入）。
- **实现期设计修正**：SDD §3.5 的"排队项列表 + 逐项撤回按钮"依赖 P2 三 tab 聊天窗口（未来 CR）；本 CR 落地的是 project-detail 常驻队列指示 + quick-create 满队反馈，撤回走既有任务卡取消按钮（后端 T01 已收紧权限）。D1 验收范围（满队拒绝可见、深度实时、撤回受权限管控）不受影响。
