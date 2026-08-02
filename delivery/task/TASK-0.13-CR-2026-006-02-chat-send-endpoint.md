---
id: CR-2026-006-TASK-02
type: TASK
cr-ref: CR-2026-006
plan-ref: "change-requests/CR-2026-006/plan.md"
sdd-ref: "change-requests/CR-2026-006/sdd.md"
title: 薄发送端点（守卫→落库→入队→补偿）+ 优先级对齐 + 双层守卫竞态处理
slug: chat-send-endpoint
status: done
estimate: 5h
depends-on: [CR-2026-006-TASK-01]
assignee: ""
created: "2026-08-02T01:15:00+08:00"
spec-id: ai-first-platform
version: "0.13"
---

## 任务描述
实现 SDD §4.3/§6.2 的 `POST /api/projects/{id}/chat/messages`。本任务是技术评审 **TSUG-001** 与
**TSUG-002** 两条建议的落地点，必须按下面"实现要点"逐条处理，不能只做 SDD 正文的顺序流程。

## 涉及文件
- `server/internal/service/task.go`（或新文件 `server/internal/service/project_chat.go`）：
  新增 `SendProjectChatMessage(ctx, projectID, callerID, content, attachmentIDs)`
- `server/internal/handler/`：新路由 `POST /api/projects/{id}/chat/messages`（`router.go` 注册）
- `server/internal/service/task_queue_capacity.go`：`guardProjectQueueCapacity` 复用（同包私有可直调）

## 实现要点

1. **主流程**（SDD §4.3 步骤 1-4）：项目成员鉴权 → 解析 `settings.team_agent_id`（未配置 →
   `409 team_agent_not_configured`）→ 容量守卫 → `Queries.CreateComment` 落 comment →
   `EnqueueTaskForMention` 入队。

2. **TSUG-002 优先级对齐**：入队时群聊任务优先级设为 **2**（与既有 1:1 chat 任务
   `service/task.go` 固定优先级一致），不要沿用 mention 路径默认的 0——否则同一 agent 混用
   Private Ask（若已存在类似机制）与项目群聊时，1:1 会话会持续插队群聊任务。owner/admin 的
   D1 插队优先级覆盖逻辑不变（仍生效于此值之上）。

3. **TSUG-001 双层守卫竞态**：前置 `guardProjectQueueCapacity` 通过之后，`EnqueueTaskForMention`
   内部原有的 guard 仍可能因并发（两个请求同时通过前置检查、内部入队时才发现已满）冒出
   `*task_queue_capacity.ErrProjectQueueFull`。补偿分支必须先 `errors.As` 判断这个具体错误类型：
   - 是 `ErrProjectQueueFull` → 删除已落库的 comment（同 §6.2 通用补偿）+ 返回 **429
     `project_queue_full`**（复用 `writeProjectQueueFull` 映射，`handler/issue.go:2010-2017`），
     不能落入下面的 502 通用分支——否则并发满队场景会被误报成系统错误。
   - 其他入队失败 → 删除评论 + 返回 **502 `enqueue_failed`**（"未发出，可重试"语义）。
   - 补偿删除本身失败（双重故障）→ ERROR 日志（只记 comment_id/task 意图，**不记消息正文**，
     沿审计脱敏约束）+ 仍返回对应错误码。

4. WS 广播（`comment:created`）放在入队成功之后——失败的发送不会先广播再消失。

5. 单测覆盖：正常闭环、前置 guard 拒绝（429，评论不落库）、模拟内部并发竞态触发的
   `ErrProjectQueueFull`（429，评论已落库后删除）、模拟其他入队异常（502，评论已落库后删除）、
   双重故障日志脱敏（断言日志不含 content 字段）。
