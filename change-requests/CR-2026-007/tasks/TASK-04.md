---
id: CR-2026-007-TASK-04
type: TASK
cr-ref: CR-2026-007
plan-ref: "change-requests/CR-2026-007/plan.md"
sdd-ref: "change-requests/CR-2026-007/sdd.md"
title: project-queue-bar 组件（常驻/展开/撤回/停止/占位）+ 四语文案
slug: queue-bar
status: in-progress
estimate: 5h
depends-on: [CR-2026-007-TASK-03]
assignee: ""
created: "2026-08-02T13:10:00+08:00"
---

## 任务描述
新组件 `packages/views/projects/components/project-queue-bar.tsx`，实现 PRD FR-1/2/3
与 SDD DD-1（列表项按钮半边）/DD-3（占位）。

## 涉及文件
- `packages/views/projects/components/project-queue-bar.tsx`（新）
- `packages/views/projects/components/project-team-agent-chat.tsx`（挂载点：消息流与输入区之间）
- `packages/views/locales/{en,ja,ko,zh-Hans}.json`（parity 测试强制四语）
- views 测试文件

## 实现要点
1. 常驻条：「{count} 条排队」，count = queue_depth（`projectQueueItemsOptions`，
   WS 前缀失效自动刷新）；count=0 时收起为不占注意力形态（不渲染或极小化，实现取一）。
2. 展开列表逐项：发起人头像+显示名 / 请求摘要（`summary`）/ 状态（排队中|已派发）/
   入队时间；顺序按响应原序（服务端已按 claim 顺序排）。
3. 占位（技术评审 blocker 3 前端半边）：`originator === null` → 「系统任务」占位
   头像+文案；`summary === ""` → 占位文案（如「（无消息摘要）」）。
4. 按钮语义（SDD DD-2）：自己发起（`originator.id === currentUserId`）的
   queued/dispatched 项 →「清除对话」；running 项不在 items 内（口径只含
   queued/dispatched），运行卡停止钮归 T05；owner/admin 对任意项显示「清除对话」。
   点击 → T03 的 `useCancelProjectQueueTask`（三分支反馈已在 mutation 内）。
5. 每条新文案 en/ja/ko/zh-Hans 四语齐上；brand 词 Team Agent 不翻译。
6. 测试：渲染（count/列表/占位）、自己项有按钮他人项没有、点击调 mutation、
   count=0 收起。
