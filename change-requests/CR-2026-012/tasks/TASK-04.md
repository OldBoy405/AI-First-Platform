---
id: CR-2026-012-TASK-04
type: TASK
cr-ref: CR-2026-012
plan-ref: "change-requests/CR-2026-012/plan.md"
sdd-ref: "change-requests/CR-2026-012/sdd.md"
title: merge-forward 端点 + 薄发送端点扩 attachment_ids
slug: merge-forward-endpoint
status: pending
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-03T18:45:31+08:00"
---

## 任务描述
落地 SDD §4.3 + DD-7/DD-8：合并转发新端点（复用 Send 内核的守卫/补偿序），含 register_cr
指令块组装；顺带给薄发送端点补 `attachment_ids`（T06 回填的后端前提）。

## 涉及文件
- `server/cmd/server/router.go`（:1081 旁）：`r.Post("/chat/merge-forward", h.MergeForwardDiscussion)`
- `server/internal/handler/project_chat.go`：handler——请求体
  `{ comment_ids: string[] (1..50), register_cr?: bool }`；校验空/超限/归属（全部属于
  `GetProjectDiscussionIssue` 的容器）→ 400 `invalid_comment_selection`；错误映射沿
  SendProjectChatMessage（403 presenter_required / 409 team_agent_not_configured /
  429 project_queue_full / 502 enqueue_failed）；响应 201 `{comment_id, task_id}`
- `server/internal/service/project_chat.go`：`MergeForwardDiscussion` 服务函数——取
  comments 按 created_at 升序 → 组装合并结构 markdown（SDD §4.3 三段式：trigger_message
  引用块 / chat_history 列表 / register_cr=true 时追加 requirement-register 指令块）→
  复用 `SendProjectChatMessage` 内核序（presenter 守卫 → 容量守卫 → CreateComment on
  chat 容器 → enqueue → 失败补偿删除 → 成功才广播；抽公共内核函数优先）
- 薄发送端点扩展：`SendProjectChatMessageRequest`（project_chat.go:214）加可选
  `attachment_ids?: string[]`，comment 落库后沿 `POST /api/issues/{id}/comments` 的
  既有 attachment 绑定逻辑抽用（handler/comment.go 内绑定段）

## 实现要点
- **不用 `coalesced_comment_ids`**（跨容器语义不符，SDD DD-7）；合并结构全部在 comment
  content 内，`trigger_summary` 由 `buildCommentTriggerSummary` 自然生成。
- `ponytail:` 注释：≤50 上限，超长讨论的摘要压缩是升级路径。
- register_cr 指令块只是 comment 文本（可见、可审计），服务端零 CR 写路径。

## 验收条件
1. 单测：合法 N 条 → 1 comment + 1 task，comment content 含三段结构与 {count}；
   register_cr=true 追加指令块、false 无。
2. 单测：越权面——空选/51 条/混入普通 Issue comment/混入他项目 discussion comment →
   400；presenter 非本人 → 403；满队 → 429（无 ghost comment）。
3. 单测：薄发送端点带 attachment_ids → comment 关联附件；不带 → 行为逐字节不变。

## 完成标志
单测全绿 + lint 零报错 + 429/403 结构与既有 writer 输出一致（复用断言）。
