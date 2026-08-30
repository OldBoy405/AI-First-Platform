---
id: CR-2026-056-TASK-08
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M3 转投兼容钉 + 任务快照 / daemon claim / presenter
slug: m3-redirect-compat-task-snapshot
status: pending
estimate: 4h
depends-on: [CR-2026-056-TASK-07]
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

两块收尾：① 转投侧唯一允许的兼容钉（`EnsureProjectChatIssue` 内部 `lockKeyPrefix` 一行，BLOCK-016）；② 任务快照链路：`task.go` 入队 merge `context.chat_config`、`daemon.go` claim 读快照、`project_presenter.go` 活动解析改读 active session。对应 plan.md M3 第 7–8 项、SDD §2.3/§4.8/§4.13。

输入条件：TASK-06/07 的 advisory 协议与发送事务已落盘。

## 涉及文件 / 模块

- `server/internal/service/project_chat.go`（`EnsureProjectChatIssue` 传给 `ensureContainerIssue` 的 `lockKeyPrefix`，今日 `"project-chat"` 改 `"project-chat-session"`，仅一行）
- `server/internal/service/task.go`（enqueue merge `chat_config`）
- `server/internal/handler/daemon.go`（claim 组装 `TaskAgentData`）
- `server/internal/service/project_presenter.go`（活动记录容器解析）
- 零改动核对对象：`server/internal/handler/comment.go`、`server/internal/service/discussion_coordinator.go`

## 实现要点

1. **转投兼容钉（§4.13 / BLOCK-016）**：`EnsureProjectChatIssue` 的 `lockKeyPrefix` 从 `"project-chat"` 改为 `"project-chat-session"`（`ensureContainerIssue` 仍拼接 `lockKeyPrefix|ws|project`），使转投创建/查询与 GET 收养、Bind 共享同一把项目级 advisory。函数签名、创建路径、新建行 `origin_id=NULL` 全部保持现状；`comment.go:retargetDiscussionCoordinatorRoute` 与 `RouteDiscussionToTeamAgent` **零改动**；`GetProjectChatIssue` 的 `ORDER BY created_at ASC, id ASC LIMIT 1` 兼容钉已在 TASK-03 落 sqlc，本 TASK 只核对转投调用方行为。转投不走 §4.3 校验、不 Bind、不 merge `chat_config`（KG-1/KG-2 归 CR-B/CR-C，不在本 CR 修）。
2. **入队快照（§2.3，FR-13）**：merge 点在 TASK-07 定义的 tx-aware 接缝 `enqueueMentionTaskWithCommentPlanTx` 内（queue INSERT 之前、同一 `qtx`），把 `chat_config` merge 进 `agent_task_queue.context` JSONB：`{"chat_config":{"model":"<id>","thinking_level":"<level-or-empty>"}}`；merge 语义（保留 `head_sha` 等既有键，禁止整对象覆盖）；`thinking_level=""` 表示不注入。既有非事务调用方（转投 / mention 路径）经原 `enqueueMentionTaskWithCommentPlan` wrapper，不 merge（转投无快照即 KG-1，归 CR-B/CR-C）。
3. **daemon claim（§4.8，FR-14）**：`handler/daemon.go` 组装 `TaskAgentData` 时：`context.chat_config` 解析成功且键存在则 `Model`/`ThinkingLevel` 用快照（允许 `model=""`），否则保持 `agent.Model` / `agent.ThinkingLevel`（旧任务，不回填）；重试 / 重新 claim 读同一 task 行，不 SELECT session / agent 配置。
4. **presenter 活动记录（§9 #35）**：`project_presenter.go` 由 `GetProjectChatIssue` 改为读 active `project_chat_session.issue_id`；未绑定则跳过（与今日「issue not found」行为一致）。

## 验收条件

1. `git diff` 核对：`handler/comment.go` 与 `service/discussion_coordinator.go` 零改动（本 CR 全程）；`EnsureProjectChatIssue` 的改动仅 `lockKeyPrefix` 一处。
2. 入队夹具：`context` 同时含 `head_sha`（或既有键）与 `chat_config`（AC-10，含 merge-forward 路径，后者由 TASK-07 夹具覆盖）。
3. claim 夹具：有 `chat_config` 的任务重试后 model / thinking 与入队时相同（AC-8）；无 `chat_config` 的旧任务走 agent 列（FR-14）；`model=""` 原样进入 `TaskAgentData.Model`。
4. §4.14 夹具 3：同 `created_at`、不同 `id` 的两行 `project_chat`，`GetProjectChatIssue` 的 `:one` 固定返回较小 `id`，重复查询稳定（BLOCK-017）。
5. presenter：未绑定容器时无活动记录（行为与今日一致）；已绑定按 `session.issue_id` 记录。

## 完成标志

上述夹具绿并提交；零改动核对结果留档。

## 接口契约

- 消费：TASK-03 的 `GetProjectChatIssue`（新排序）、TASK-06 的项目级 advisory 协议、TASK-07 的发送事务（`chat_config` 值来源 = `ResolveChatConfig` 输出）、基线 `ensureContainerIssue` / `enqueueMentionTaskWithCommentPlan`。
- 产出：
  - 转投与新模型共享的锁协议（唯一键 `project-chat-session|{workspace_id}|{project_id}`）全路径闭合；
  - `agent_task_queue.context.chat_config` 快照格式（`{"model": string, "thinking_level": string}`）——daemon claim 的消费契约，无新增导出符号。
