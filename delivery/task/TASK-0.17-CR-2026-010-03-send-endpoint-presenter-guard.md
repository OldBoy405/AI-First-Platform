---
id: CR-2026-010-TASK-03
type: TASK
cr-ref: CR-2026-010
plan-ref: "change-requests/CR-2026-010/plan.md"
sdd-ref: "change-requests/CR-2026-010/sdd.md"
title: 发送端点控制权守卫接入（403 presenter_required）+ 插队优先级抑制
slug: send-endpoint-presenter-guard
status: done
estimate: 3h
depends-on: [CR-2026-010-TASK-02]
assignee: ""
created: "2026-08-02T13:57:20+08:00"
spec-id: ai-first-platform
version: "0.17"
---

## 实现状态（2026-08-02）

代码已在 multica worktree（`requirement/CR-2026-010`，commit `f806e60af`）落地：
`service/project_chat.go` 新增 `guardProjectChatPresenter`（`ErrPresenterRequired`
错误类型）：`active=nil` 时 `role∈{owner,admin}` 才放行（**行为变化**：CR-A 现状该
端点在路由层只挂了 `RequireWorkspaceMember`，任何成员都能发送，此前没有角色门槛——
本任务补齐这道门槛，而非"沿用现状"）；`active!=nil` 时 presenter 本人或
owner/admin 放行，owner/admin 额外被标记"抑制插队优先级"，其余成员一律 403。

优先级抑制的关键实现点：`guardProjectQueueCapacity` 的 owner/admin 100 优先级覆盖
实际发生在 `enqueueMentionTaskWithCommentPlan` 内部（按 `resolveOriginatorForIssueTask`
重新计算一次，而不是复用 `SendProjectChatMessage` 外层已丢弃的返回值），因此新增
`suppressPreemptPriority bool` 参数贯穿 `enqueueMentionTask`/
`enqueueMentionTaskWithCommentPlan`（其余 4 个调用点补 `false`），
`SendProjectChatMessage` 改为直接调用 `enqueueMentionTaskWithCommentPlan`
（绕开 `EnqueueTaskForMention` 包装，因为该包装签名被其他非 presenter 场景共用，
不能塞入这个新参数）。

`handler/project_chat.go` 加 `writePresenterRequired`（403，body 含
`presenter_user_id`，仅当 presenter 非空时非空）。

**已用真实 DB 验证**：新测试 `TestSendProjectChatMessagePresenterGuard`（6 个子用例：
无 presenter 时 owner 发送成功且保留插队优先级 100、无 presenter 时普通成员 403；
有 presenter 时 presenter 本人发送成功且优先级非 100、owner 发送成功但优先级被抑制、
admin 同上、其余成员 403 且响应体带 presenter_user_id）全部 PASS；403 场景通过
before/after 行数断言确认未落 comment、未入队。`go build`/`go vet`/`gofmt`（限定
改动文件）全绿；`internal/service`+`internal/handler` 全量套件回归结果与
TASK-01/02 完成时一致（12 个与本 CR 无关的预置环境问题，未受影响）。

## 任务描述

在 multica 落地 SDD §4.3/DD-6：在薄发送端点的容量守卫**之前**插入控制权守卫，实现单一写者
语义；并在 presenter 非空时抑制 owner/admin 的插队优先级（不抢占 presenter 的排队消息）。

## 涉及文件

- `server/internal/service/project_chat.go`：`SendProjectChatMessage`（:139）在
  `guardProjectQueueCapacity`（既有调用，:140）**之前**插入：
  ```
  role   = GetMemberByUserAndWorkspace(caller)
  active = GetPresenterState(projectID).presenter   // T02 提供
  allowed = active!=nil ? (caller==active.user_id || role∈{owner,admin})
                        : (role∈{owner,admin})
  !allowed → 403 presenter_required { presenter_user_id?: string }
  ```
  不通过时直接返回，**不落 comment、不调用容量守卫**（消息不落库不入队，PRD FR-2）。
- `server/internal/service/project_chat.go`：守卫通过且
  `active!=nil && caller!=active.user_id`（即 owner/admin 在 presenter 存在时发送）场景，
  把 `guardProjectQueueCapacity` 返回的插队优先级 100 覆盖压回 0（DD-6：容量豁免保留，
  插队优先级抑制——owner/admin 仍不受满队限制入队，但不再抢占 presenter 的排队顺序）。
- `server/internal/handler/project_chat.go`：`SendProjectChatMessage` handler 的错误码
  映射表加 `presenter_required` → 403（沿既有 `project_queue_full`/`team_agent_not_configured`
  的错误码 → HTTP 状态映射写法）。

## 实现要点

- 守卫顺序是本任务的核心正确性要求：控制权守卫 → 容量守卫 → 落 comment → 入队。颠倒顺序
  会导致普通成员在满队时先看到"队列已满"而非"需要主持人权限"，掩盖真实拒绝原因。
- presenter 为 null 时的默认态 = 现状 CR-A 行为的严格子集（owner/admin 可发、其余成员被拒），
  **不需要**额外的兼容分支——本任务上线前 CR-A 环境里没有 grant 表数据，`GetPresenterState`
  对无表记录的项目返回 `presenter=null`，天然等价于"未启用 presenter"的默认态。
- 优先级抑制只影响 claim 顺序（`ORDER BY priority DESC`），不影响 T01 的容量豁免判断——
  两者是 `guardProjectQueueCapacity` 返回值的两个独立维度，不要合并成一个分支。

## 验收条件

1. 单测矩阵：presenter=null 时，owner/admin 发送入队成功、普通成员发送 403；presenter=X 时，
   X 发送入队成功（默认优先级）、owner/admin 发送入队成功但优先级=0（非插队）、其余成员 403。
2. 403 响应体含 `presenter_user_id`（当 presenter 非空时），供前端呈现"当前主持人是谁"。
3. 集成测试：403 场景下 SELECT 验证 comment 表未新增行、agent_task_queue 表未新增行。

## 完成标志

上述测试全绿；`go vet`/`go build` 零报错；与 T01 的并发 claim 单测组合跑一次全链路
（presenter 消息 vs owner/admin 排队消息，claim 顺序符合优先级预期）无异常。
