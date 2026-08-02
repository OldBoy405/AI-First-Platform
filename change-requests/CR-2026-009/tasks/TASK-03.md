---
id: CR-2026-009-TASK-03
type: TASK
cr-ref: CR-2026-009
plan-ref: "change-requests/CR-2026-009/plan.md"
sdd-ref: "change-requests/CR-2026-009/sdd.md"
title: DiscussionPane（消息流 + 输入区）+ ?mode= 深链 + 四语文案
slug: discussion-pane-frontend
status: done
estimate: 5h
depends-on: [CR-2026-009-TASK-01]
assignee: ""
created: "2026-08-02T11:55:00+08:00"
---

## 任务描述
落地 SDD §5.1：project-chat-panel 的 Discussion 占位替换为实面——纯 comment 流 + 纯人类输入区。

## 涉及文件
- `packages/views/projects/components/project-chat-panel.tsx`：discussion 分支渲染新
  `DiscussionPane`；挂载时读一次 `?mode=` searchParam 设 activeMode（**白名单校验
  team_agent|private_ask|discussion，其余忽略，PSUG-003**）
- 新组件（panel 同目录）`discussion-pane.tsx`：
  - `GET /api/projects/{id}/discussion`（react-query，staleTime Infinity）拿 issueId
  - `useIssueTimeline(issueId)` → 只渲染 comment 条目（防御性过滤一行）→ `CommentCard` 列表
  - 空态复用 CR-A 已落 `heyDiscussion` 问候语（去掉「由后续版本提供」副文案）
  - 输入区 `ReplyInput`（issueId=容器、parentId=root、draftKey=容器 issueId 命名空间）→
    onSubmit 调既有 createComment API
- `packages/views/locales/`：新增/调整文案四语（en/ja/ko/zh-Hans）
- 对应组件测试（参照 project-chat-panel.test.tsx 既有写法）

## 实现要点
- 实时零新增事件：`comment:created` 已被 use-issue-timeline.ts:93 直写缓存，装上即实时。
- 输入区纯人类形态由组件选择天然满足（ReplyInput 仅附件+@），不写任何裁剪代码。
- 提及选择器不做目标过滤（SDD DD-7 定案，服务端红线兜底）。
- 草稿用 ReplyInput 原生 draftKey（SDD DD-6），不动 project-chat-store 的草稿结构。

## 验收条件
1. 组件测试：Discussion tab 渲染 comment 流与输入区；发送成功后输入清空、失败保留（ReplyInput 既有语义）；`?mode=discussion` 深链直达、非法值忽略。
2. 组件测试：无模式/模型/技能/停止控件断言（查询控件不存在）。
3. locale parity 测试全绿。

## 完成标志
`pnpm test`（views 包）+ parity 测试 + lint 全绿；web 与 desktop 目视一致（Electron 共享 views）。
