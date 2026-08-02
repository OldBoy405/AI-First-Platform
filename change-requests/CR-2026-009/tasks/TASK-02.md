---
id: CR-2026-009-TASK-02
type: TASK
cr-ref: CR-2026-009
plan-ref: "change-requests/CR-2026-009/plan.md"
sdd-ref: "change-requests/CR-2026-009/sdd.md"
title: 触发豁免短路 + 负向/回归单测（验收红线）
slug: discussion-trigger-exemption
status: pending
estimate: 2h
depends-on: [CR-2026-009-TASK-01]
assignee: ""
created: "2026-08-02T11:55:00+08:00"
---

## 任务描述
落地 SDD §4.3：discussion 容器上的任何 comment 永不触发 agent 入队（cr.md 验收红线）。
本 CR 唯一动既有行为的点，改动一处、测试从重。

## 涉及文件
- `server/internal/handler/comment.go`（:1579 `computeCommentAgentTriggers` 顶部）：
  ```go
  // project_discussion containers are the human-only Discussion surface:
  // no comment on them may ever enqueue an agent run (CR-2026-009 red line).
  if issue.OriginType.Valid && issue.OriginType.String == "project_discussion" {
      return nil
  }
  ```
- 对应单测文件：负向用例 + 既有触发链回归

## 实现要点
- 短路位置在函数最顶部（isNoteComment 判断之前也可，但保持在其后与现有结构一致即可），
  确保四类触发（@agent/@squad 提及、成员提及分支、squad-leader fallback、父评论续聊路由）全部被豁免。
- 不动 `notifyMentionedMembers` 链路（notification_listeners.go:427）——@成员通知是 FR-4 要保留的行为。
- 不动 `filterSuppressedCommentAgentTriggers` / suppressAgentIds。

## 验收条件
1. 新增单测：discussion 容器 Issue 上 @agent / @squad / 回复 agent 评论 / squad-assigned fallback 四种输入 → `computeCommentAgentTriggers` 返回空。
2. 回归单测：非容器 Issue（OriginType NULL 及其他值）的既有触发用例全量通过，行为零变化。
3. 集成级：discussion 容器发含 @agent 的 comment → `agent_task_queue` 零新增行（可并入 T05 真机验证，单测层先行覆盖）。

## 完成标志
`go test ./internal/handler/...` 全绿 + 新增负向用例纳入常规套件。
