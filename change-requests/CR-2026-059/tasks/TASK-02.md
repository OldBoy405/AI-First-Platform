---
id: CR-2026-059-TASK-02
type: TASK
cr-ref: CR-2026-059
plan-ref: "change-requests/CR-2026-059/plan.md"
sdd-ref: "change-requests/CR-2026-059/sdd.md"
target-version: "0.32"
title: 服务层：Discussion 会话/发送/协办/投影/幂等
slug: discussion-session-service
status: pending
estimate: 24h
depends-on: [CR-2026-059-TASK-01]
created: 2026-09-04T16:40:00+08:00
---

# TASK-02 服务层：Discussion 会话/发送/协办/投影/幂等

## 任务描述

在 multica CR worktree 实现 SDD §4.1–§4.6 的服务层：`EnsureProjectDiscussionSession`（FR-1/3/8/16）、`SendDiscussionMessage` 事务（FR-10/11/12/15/17/24，B-AUTH-2 锁序）、`detectCoordinatorTrigger`（FR-11，B-COORD-1 配置身份匹配）、Coordinator 写权威投影（FR-26）、幂等收敛与 24h sweeper（FR-24）。全部复用既有实现（`mergeChatConfigContext`/`CreateChatTask`/`ResolveChatConfig`/`LoadChatCatalogForConfig`/`ValidateResolvedChatConfig`），禁止第二套规则表；`sendProjectChatCore` 零改动（NFR-7）。代码注释英文。

## 涉及文件 / 模块

- 新建 `server/internal/service/discussion_session.go`：ensure/send/trigger/投影/幂等指纹与重放（§4.1/§4.2/§4.3/§4.5/§4.6）。
- 新建 `server/internal/service/chat_idempotency_cleanup.go`：`SweepChatIdempotency`（每小时、`created_at < now()-24h`、`maxPerTick` 形态对齐 `SweepChatDraftAttachments`）。
- `server/internal/service/project_chat.go`：GET 路径解除 `EnsureProjectDiscussionIssue` 调用（保留函数）；新增 `buildMergedForwardContentFromMessages`（平行函数，署名读作者列，legacy 路径字节级不变）；`RouteDiscussionToTeamAgent` 触发源从 Discussion Issue comment 改为 shared session 消息（入参适配，内核零 diff，KG-1/KG-2 保持）。
- `server/internal/service/task.go`：复用 `mergeChatConfigContext` / `CreateChatTask` 组合；`ChatSessionCreatorID` 辅助扩展为同时返回 kind（§3.7）；`writeChatCompletionOutcome` 写 shared 回复时补作者列（`author_type='agent', author_id=task.agent_id`）。
- `server/internal/service/project_chat_session.go`（参照模板，不新增文件）：`SnapshotAgentDefaults` 复用。

## 实现要点

- §4.2 事务锁序（固定，禁止重排）：`LockSubscriberWrites(ws, caller)`（第一把锁，与 `revokeAndRemoveMember` 同锁 [D-27]）→ 事务内 `GetMemberByUserAndWorkspace` 成员复核（幂等插入等任何写入之前）→ `project-discussion-session|{ws}|{project}` advisory → `LockChatSessionInWorkspace` 会话行锁 → 幂等键/附件行锁。移出竞态二择一、失败零残留（§4.2 块）。
- §4.3 触发判定同时携带 settings `configured` UUID 与 `routable` 状态；先识别配置身份 mention（UUID 归一化比较，`util.ParseMentions` 复用），再分 `not_configured`/`unavailable`（两个 409 均零写入）；`analyze/summarize` 优先于 mention 推导；其它 Agent mention 走普通消息。
- §4.4 authority 阶梯：L1 已配置且 agent 行存在 → `LoadChatCatalogForConfig` + `ValidateResolvedChatConfig` 逐字复用（归档 Blocked → 400）；L2 未配置或 hard-delete → `ListAgentRuntimes`（created_at ASC）+ `runtimeVerdict().Ready()` 过滤 + 逐 runtime 校验（纯 sentinel 恒过；至多 1 次 30s LiveLoad round；全拒 → 400 fail-closed）。绝不调用 `UpdateAgent`。
- §4.6 指纹：`POST messages` = trim(content) + 重复校验后**稳定排序**的 attachment_ids + coordinator_request 的规范 JSON sha256；merge-forward = 去重后顺序保留的 message_ids + register_cr。重放直接回存 `{status, body}`，不进附件绑定路径。
- §4.5 投影事务：settings 写权威先行 → 锁内投影 `session.agent_id`（首次绑定且 `base_*` 全 NULL 补写 `SnapshotAgentDefaults`；替换不重取快照；解绑置 NULL）；GET 侧自愈先修复再返回；不复制 Team Agent「关旧建新」语义（D-5）。

## 接口契约

**消费（TASK-01 产出）**：`GetActiveProjectSharedSession` / `InsertProjectSharedSession` / `GetChatMessageInWorkspace` / `BindDraftAttachmentsToChatMessage` / `InsertChatIdempotencyReservation` / `GetChatIdempotencyByKey` / `FinalizeChatIdempotency` / `SweepChatIdempotency`（签名以 TASK-01 为准，sqlc 生成后对齐）。

**产出（供 TASK-03 消费）**：

```go
// discussion_session.go（新文件）
type ProjectDiscussionSessionView struct {
    SessionID           string
    LegacyIssueID       *string
    CoordinatorAgentID  string
    Model               string
    ThinkingLevel       string
    ModelSource         string
    ThinkingLevelSource string
}
func EnsureProjectDiscussionSession(ctx context.Context, deps DiscussionSessionDeps, wsID, projectID, callerID uuid.UUID) (ProjectDiscussionSessionView, error)

type DiscussionSendInput struct {
    Content            string
    AttachmentIDs      []uuid.UUID
    CoordinatorRequest string // "none" | "mention" | "analyze" | "summarize"
}
type DiscussionSendResult struct {
    MessageID uuid.UUID
    TaskID    *uuid.UUID // 普通消息 nil；协办为 task UUID
}
func SendDiscussionMessage(ctx context.Context, deps DiscussionSessionDeps, wsID, callerID, sessionID uuid.UUID, input DiscussionSendInput, idempotencyKey string) (DiscussionSendResult, *DiscussionSendError)
// DiscussionSendError{Code string}：code ∈ chat_session_not_found | chat_session_closed_or_changed |
//   discussion_coordinator_not_configured | discussion_coordinator_unavailable |
//   invalid_model_or_thinking_level | attachment_already_bound |
//   idempotency_key_reused | replay（重放时 Result 为首次响应、Error=nil）

func detectCoordinatorTrigger(content, coordinatorRequest string, configured uuid.UUID, routable *db.Agent) triggerDecision
// triggerDecision{NeedTask bool, Reason string}：Reason ∈ none|not_configured|unavailable

func UpdateProjectSettingsWithDiscussionCoordinator(ctx context.Context, deps DiscussionSessionDeps, wsID, projectID uuid.UUID, newAgentID *uuid.UUID) error // nil=解绑

// project_chat.go
func buildMergedForwardContentFromMessages(ctx context.Context, msgs []db.ChatMessage, registerCR bool) (string, error)

// chat_idempotency_cleanup.go
func SweepChatIdempotency(ctx context.Context, q *db.Queries, cutoff time.Time) (int64, error)
```

`DiscussionSessionDeps` 汇总本 TASK 服务所需依赖（queries/tx/ports/agent 服务），不依赖 handler 包（层次合规 handler → service）。

## 验收条件

1. `go test ./server/internal/handler/ ./server/internal/service/ -count=1` 全绿且覆盖：并发 GET 收敛同一 session（AC-8）；普通消息无 task/Issue（AC-3）；协办 task `issue_id=NULL` + `context.chat_config`（AC-4）；回复写回同 session（AC-5）；发送失败零残留 + 附件原子绑定（AC-13）；幂等重放/冲突/并发单提交（AC-26）；移出先提交 → 404 零写入（AC-28 竞态向量）；归档后 409 `unavailable`（AC-31）；hard-delete 保留与回放（AC-32）。
2. `go test ./server/internal/handler/ ./server/pkg/agent/ -count=1` 覆盖 AC-10 入队臂与 AC-21（单一实现复用，无第二套规则表）。
3. 本 TASK diff 不含 `sendProjectChatCore` 任何改动（`git diff` 审查该函数零行变化）。
4. 服务注释一律英文；无 TBD。

## 完成标志

上述测试命令全绿 + zero_diff 审查通过 + 所有服务函数已落盘并 commit 到 `requirement/CR-2026-059`（`developing` 内可被 `crctl task done` 登记的事件）。
