---
id: CR-2026-006-TASK-04
type: TASK
cr-ref: CR-2026-006
plan-ref: "change-requests/CR-2026-006/plan.md"
sdd-ref: "change-requests/CR-2026-006/sdd.md"
title: Team Agent 消息流（timeline+task-runs+TimelineView）+ 输入区 + 满队反馈
slug: team-agent-message-stream
status: done
estimate: 6h
depends-on: [CR-2026-006-TASK-02, CR-2026-006-TASK-03]
assignee: ""
created: "2026-08-02T01:15:00+08:00"
---

## 任务描述
落地 SDD §5.2 的核心：把 T03 交付的 Team Agent tab 空壳接上真实消息流与发送能力，落地 PRD
FR-6/FR-7。

## 涉及文件
- `packages/views/chat/components/chat-message-list.tsx`：**导出 `TimelineView`**（当前是文件内部
  组件，纯导出化，不改动其内部逻辑）
- `packages/views/projects/components/project-chat-panel.tsx`（T03 骨架基础上扩展）：
  组合 `useIssueTimeline(issueId)`（comment 流，WS `comment:created` 直写缓存已有）+
  `api.listTasksByIssue`（Agent 执行卡数据）+ 导出后的 `TimelineView` 渲染工具执行卡
  （running/done/error/interrupted 徽标 + 耗时 + 可折叠输入输出），按时间交错呈现用户消息气泡 /
  Agent 回复 / 执行卡（组合方式对照 `issue-detail.tsx:251-254` 的 coalesce 先例）
- 输入区：复用 `packages/views/chat/components/chat-input.tsx`（纯 props，附件/@提及/草稿现成），
  `onSend` 接 T02 交付的 `POST /api/projects/{id}/chat/messages`

## 实现要点
- 历史回放用 timeline 全量返回（硬帽 2000，DD-5），顶部固定"暂无更早消息"（无需实现分页 UI）。
- 发送响应分支：
  - `429 project_queue_full` → 输入区禁用 + 「Agent 忙，请稍后」+ 展示 depth/limit（写法对照
    quick-create 弹窗的 `project_queue_full` 处理），恢复由 `projectQueueStatusOptions`
    （D1 已有）失效驱动；owner/admin 不进入禁用态（D1 语义，T02 已在服务端保证）。
  - `502 enqueue_failed` → toast「发送失败，请重试」，草稿保留（不清空输入框）。
  - `409 team_agent_not_configured` → 走 T03 已实现的未配置引导态。
- **验收时顺带核对 TSUG-002**：构造同一 team agent 下"群聊任务"与"1:1 chat 任务"同时排队的
  场景，claim 顺序应体现两者同优先级（2），不应出现 1:1 持续插队群聊的现象——这是 T02 后端
  优先级对齐的前端可观察验证点，非本任务代码改动，但需在联调时确认。
- 单测/集成覆盖：发消息→守卫→comment 落库→入队→claim→执行卡渲染全链路（mock WS 事件驱动）；
  刷新后历史消息+执行卡完整回放；三种错误响应分支的 UI 表现；既有浮窗/全页 chat 回归
  （`TimelineView` 导出化不应改变其行为）。
