---
id: CR-2026-007-TASK-05
type: TASK
cr-ref: CR-2026-007
plan-ref: "change-requests/CR-2026-007/plan.md"
sdd-ref: "change-requests/CR-2026-007/sdd.md"
title: 消息流增强：运行卡停止钮 + 过滤摘要形态 + 已撤回角标 + 复制
slug: stream-enhancements
status: done
estimate: 5h
depends-on: [CR-2026-007-TASK-03]
assignee: ""
created: "2026-08-02T13:10:00+08:00"
spec-id: ai-first-platform
version: "0.14"
---

## 任务描述
`project-team-agent-chat.tsx` 的四项增强，实现 PRD FR-4/5/7 与 SDD DD-1/DD-4/DD-5。
本任务是 **TSUG-003** 的落地点。

## 涉及文件
- `packages/views/projects/components/project-team-agent-chat.tsx`
- `packages/views/locales/{en,ja,ko,zh-Hans}.json`
- views 测试文件

## 实现要点
1. **运行卡停止钮（DD-1）**：`TaskExecutionCard` 头部，`status === 'running'` 且
   （`task.originator_user_id === currentUserId` 或 workspace owner/admin）时显示
   「停止」→ T03 mutation。发送键**不**变停止（SDD DD-1 对交互稿 §3.4 的已论证偏离）；
   `chat.agentGenerating` 字典用作运行卡状态文案。
2. **过滤开关摘要形态（DD-4，TSUG-003）**：tab 旁迷你开关绑 store
   `agentRequestFilter[projectId]`。开启时 TaskExecutionCard 只渲染卡头（agent 名+
   状态徽标+耗时）+ 完成态 **`result.output`** 文本（**不是** result 整包 JSON——
   那是 `{output, pr_url, tool_calls,…}`，整包渲染会出 JSON 垃圾）；output 空串 →
   占位「（无文本回复）」；**不渲染 TimelineView**。comment 气泡全部保留。
   纯 render 分支：不动缓存、不发请求。
3. **已撤回角标（DD-5）**：stream 中 `status === 'cancelled'` 的 task，其
   `trigger_comment_id` 对应 comment 气泡加「已撤回」角标——纯前端 join，数据全在缓存。
4. **复制（FR-7）**：comment 气泡悬浮「复制」按钮，`navigator.clipboard.writeText`
   取消息完整文本，成功短 toast「已复制」。
5. 四语文案齐上。
6. 测试：停止钮可见性（自己 running 显示/他人不显示/owner 显示）、过滤开启后 DOM
   无 TimelineView 节点 + result.output 正确渲染 + JSON 整包不出现、开关往返幂等、
   已撤回角标、复制调用。
