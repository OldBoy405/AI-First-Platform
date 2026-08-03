---
id: CR-2026-012-TASK-03
type: TASK
cr-ref: CR-2026-012
plan-ref: "change-requests/CR-2026-012/plan.md"
sdd-ref: "change-requests/CR-2026-012/sdd.md"
title: DC 路由 re-target + originator 显式解析 + 满队 system comment
slug: dc-route-retarget-originator
status: done
estimate: 6h
depends-on: [CR-2026-012-TASK-02]
assignee: ""
created: "2026-08-03T18:45:31+08:00"
spec-id: ai-first-platform
version: "0.19"
---

## 任务描述
落地 SDD §4.2 + DD-5/DD-6：T02 放行的第②类触发（DC 作者 × team_agent 目标）在 enqueue
层翻译为"chat 容器路由 comment + 入队"，任务现身 Team Agent 面；满队走可审计反馈。

## 涉及文件
- `server/internal/handler/comment.go`（:1540 `enqueueSingleCommentTrigger` 的
  `commentTriggerSourceMentionAgent` case）：新增 re-target 分支——
  `EnsureProjectChatIssue` → 以 DC 身份落路由 comment（authorType=agent，内容=DC 原
  comment 摘录 + 路由标注）→ `enqueueMentionTaskWithCommentPlan` 挂 chat 容器
- originator（评审 TSUG-001 定案）：先核实 `resolveOriginatorForIssueTask`（task.go:863）
  对"路由 comment（agent 作者）"的穿透能力；不足则在 re-target 处沿 DC 完成 comment 的
  `parent_id` 链（task.go:1958 以 TriggerCommentID 为 parent）显式解析激活人类并透传
  （enqueue 变体参数或入队后 set，取改动小者）；解析失败 → 沿 a2a 直通语义 + 日志
- 满队反馈（DD-6）：re-target 与 DC 激活两处 enqueue 撞 `*ErrProjectQueueFull` → 以
  system comment 落 discussion 容器（type="system"，作者 DC，文案含队列 N/M——文案键
  `chat.dc.queue_full_notice`，T07 落 locale）；enqueue 失败且路由 comment 已落 → 沿
  project_chat.go:236 补偿删除模式

## 实现要点
- 路由 comment 经 service 层直建（不过 handler 触发链），无二次触发风险；chat 容器侧
  `EventCommentCreated` 广播使 Team Agent 面实时可见。
- 该分支仅在 T02 第②类触发到达时进入，普通路径零改动。

## 验收条件
1. 单测：DC 作者 @团队Agent 的 discussion comment → chat 容器出现路由 comment + 队列
   出现挂 chat 容器的 team agent 任务；originator 为激活人类（或明确落 a2a 直通分支断言）。
2. 单测：满队场景 → discussion 容器出现 system comment（结构化文案），无 ghost 路由 comment。
3. 回归：SendProjectChatMessage 既有单测（守卫/补偿/优先级）全绿。

## 完成标志
单测全绿 + lint 零报错 + originator 核实结论写进代码注释（TSUG-001 留痕）。
