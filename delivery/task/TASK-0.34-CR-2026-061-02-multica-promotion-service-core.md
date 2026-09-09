---
spec-id: ai-first-platform
version: "0.34"
id: CR-2026-061-TASK-02
type: TASK
cr-ref: CR-2026-061
plan-ref: "change-requests/CR-2026-061/plan.md"
sdd-ref: "change-requests/CR-2026-061/sdd.md"
target-version: 0.34
title: multica 服务内核：createInTx 提取与 PromoteDiscussion 全流程
slug: multica-promotion-service-core
status: pending
estimate: 24h
depends-on: ["CR-2026-061-TASK-01"]
created: 2026-09-08T12:04:37+08:00
---

## 1. 任务描述

在 multica CR worktree（基线 HEAD `eafce66b`）实现 promotion 服务内核：把 `IssueService.Create` 的事务体机械提取为 `createInTx`（D-7，唯一 Issue 写入路径），并新增 `IssueService.PromoteDiscussion`（SDD §4.3 全流程：幂等四分支、查重、创建/补建、预建 run、默认标题描述）。本 TASK 不写 HTTP handler（TASK-03）、不改迁移/sqlc（TASK-01 已产出）。

输入：已审批 SDD v1.1 §2.1/§2.3/§2.4/§4.1/§4.2/§4.3/§4.6/§7.3/D-1/D-6/D-7/D-8 + TASK-01 产出。

## 2. 涉及文件 / 模块

- `server/internal/service/issue.go`（`createInTx` 提取；`IssueCreateParams` 增 `ContextRefs json.RawMessage`、`PromotionRun *PromotionRunPlan`）
- `server/internal/service/promotion.go`（新建：纯函数 + `PromoteDiscussion` + `PromotionResult` + sentinel errors）
- `server/internal/service/promotion_test.go`（新建）
- `server/internal/service/issue_test.go`（zero_diff 回归，既有测试不动、全绿）
- 复用不改：`issue_limit.go`（`CheckIssueCreateCapacity` L67 / `ResolveIssueCountPolicy` L34 / `AllocateIssueNumber` L87）、`project_chat.go`（`chatMessageAuthorDisplayName` L739/L760）、`dbid.NewV7`（dbid.go L51）

## 3. 实现要点（SDD 对应节）

- **createInTx 提取（D-7）**：`Create` 保持原签名行为（Begin→createInTx→Commit→事件）；`createInTx(ctx, qtx, p, opts)` 承载原事务体全部逻辑；新字段零值下与今天逐字节一致（zero_diff 回归由既有 issue_test 全绿证明）。
- **纯函数（§4.1，单测覆盖大小写/乱序/重复）**：
  - `canonicalUUIDs(ids []pgtype.UUID) []string`：小写排序去重。
  - `promotionFingerprint(projectID, sessionID pgtype.UUID, msg, att []pgtype.UUID, upgradeToCR bool) string`：`SHA256({"projectId","session_id","message_ids","attachment_ids","upgrade_to_cr"})`，固定键序；title/description 不参与。
  - `promotionDedupeKey(sessionID pgtype.UUID, msg, att []pgtype.UUID) string`：`SHA256({"session_id","message_ids","attachment_ids"})`，不含 projectId/upgrade_to_cr（FR-6）。
- **`PromoteDiscussion` 主流程（§4.3 步骤 7–12）**：
  - 前置 1–6 由 handler（TASK-03）完成；service 事务内：`qtx.LockIssueDuplicateKey(ctx, "project-discussion-promotion|{ws}|{project}")`（新前缀 D-4）→ 锁内 `GetMemberByUserAndWorkspace` 复核 → `InsertChatIdempotencyReservation(scope='discussion_promotion', scope_id=projectID, key, fingerprint)` 四分支（同 fingerprint+NULL body 接管；异 fingerprint → `ErrIdempotencyKeyReused`；ResponseBody 非空 → 重放回放）→ `FindPromotionDuplicateIssue(dedupe_key)` 分支：
    - 未命中（创建分支）：`runID := upgradeToCR ? dbid.NewV7() : 无效`；构建 §2.1 条目（upgradeToCR 时含 `pipeline_run_id`）；`createInTx(..., AllowDuplicate:true, ContextRefs:[entry], PromotionRun: upgradeToCR ? &PromotionRunPlan{RunID, Inputs, ExecutionContext} : nil)`；`createInTx` 内注入 `AppendIssueContextRefs` 与 `InsertPipelineRun`+`InsertPipelineNodeRun`。
    - 命中（查重分支）：source_refs 从条目还原；`upgradeToCR && 条目无 pipeline_run_id` → 补建 run + `MergeIssueContextRefPipelineRun`（按 `dedupe_key` 元素级原位合并 `pipeline_run_id`，其余元素与未知扩展字段逐字节保留，`RETURNING` 合并后数组）；service 对 RETURNING 结果 **fail-closed 校验**（匹配条目必须携带预期 `pipeline_run_id`，否则报错整体回滚）；506 唯一冲突（23505）→ `FindActiveRequirementRunForIssue` 重读采用既有 id，不报错；已有 → 直接返回既有值。
  - `FinalizeChatIdempotency(key, 201, body=result)` 同一事务；`PromotionRun` 任何写入错误 → sentinel `ErrPromotionRunCreateFailed`（handler 映射 502，§4.4），整事务回滚零残留。
  - **FR-5 零写不变量**：本 service 事务对 `chat_message`/`attachment`/`chat_session` 零 UPDATE/DELETE/INSERT（结构测试 grep 断言）。
  - 提交后事件（`publishIssueCreated`/`captureCreatedAnalytics`）由 `Create` 的提交后路径承接（`IssueCreateOpts.BroadcastPayload`），promotion 不新增事件类型（§4.3 步骤 12/SDD-CLOSE-05）。
- **默认标题/描述（§4.6/AC-3）**：title 缺省 `Discussion promotion — {project.name} {YYYY-MM-DD HH:mm}`（project 名自 `GetProjectInWorkspace`）；description 缺省 = 来源消息摘要（每条 `作者: 摘要（≤120 rune）`，≤5 条，超出加 `…`，复用 `chatMessageAuthorDisplayName`）+ 来源标注块；仅创建分支生效。
- **防御边界（§7.3）**：`promotionMaxItems=50`（同值 `mergeForwardMaxComments`），超限 `ErrInvalidPromotionSelection`。

## 4. 验收条件

1. 纯函数单测：`canonicalUUIDs` 乱序/重复/大小写归一；`promotionFingerprint` 与 `promotionDedupeKey` 的固定向量断言（含 `upgrade_to_cr` 差异矩阵、title/description 不影响）。
2. `go test ./internal/service/ -count=1` 全绿：既有 `IssueService.Create` 测试零改动全绿（zero_diff）；新增 promotion service 测试覆盖 AC-1（issue 行数 +1/不变）、AC-3（context_refs 条目字段）、AC-4（chat_* 行全等 + 结构 grep）、AC-5（重放/409/查重/并发夹具）、AC-8（同事务 run/首节点、无 agent_task_queue、502 夹具零残留、原 key 重试、506 冲突重读）。
3. 事务失败夹具（`CreatePipelineNodeRun` 注入错误）→ `ErrPromotionRunCreateFailed`，issue/context_refs/chat_idempotency/pipeline_run/pipeline_node_run 零残留。
4. 结构断言：promotion.go 与 promotion.sql 的写语句不含对 `chat_message`/`attachment`/`chat_session` 的 UPDATE/DELETE/INSERT（grep/测试断言）。

## 5. 完成标志

- 上述 4 条全部通过；`go vet ./...`（server）零报错；
- 提交落盘 multica CR 分支（独立 commit）；
- `go test ./internal/service/ -count=1` 全绿（**非 canonical 实施期全包专项证据**）；canonical cmd-01 为 §6.2 口径（21 项 promotion `-run` 过滤 + DATABASE_URL 真库，其中 service 13 项由本 TASK 产出，完成时先行跑通）。

## 6. 接口契约

**消费**（TASK-01 产出，逐字对齐）：

```go
q.FindPromotionDuplicateIssue(ctx, db.FindPromotionDuplicateIssueParams{WorkspaceID, DedupeKey}) (db.Issue, error)
q.AppendIssueContextRefs(ctx, db.AppendIssueContextRefsParams{ID, ContextRefs []byte}) error
q.MergeIssueContextRefPipelineRun(ctx, db.MergeIssueContextRefPipelineRunParams{DedupeKey, PipelineRunID string; ID pgtype.UUID}) ([]byte, error)
  // :one，RETURNING context_refs（合并后数组）。fail-closed 消费契约（B-CODE-01）：解析返回数组并校验
  // 匹配条目（kind='discussion_promotion' 且 dedupe_key 相等）已携带预期 pipeline_run_id，任一不满足即报错回滚，不得静默降级。
q.InsertPipelineRun(ctx, db.InsertPipelineRunParams{...}) (db.PipelineRun, error)
q.InsertPipelineNodeRun(ctx, db.InsertPipelineNodeRunParams{...}) (db.PipelineNodeRun, error)
q.FindActiveRequirementRunForIssue(ctx, db.FindActiveRequirementRunForIssueParams{WorkspaceID, IssueID}) (db.PipelineRun, error)
q.ListAttachmentsForPromotion(ctx, db.ListAttachmentsForPromotionParams{AttachmentIds, ChatSessionID}) ([]db.Attachment, error)
q.InsertChatIdempotencyReservation / q.GetChatIdempotencyByKey / q.FinalizeChatIdempotency（既有，idempotency.sql）
q.LockIssueDuplicateKey(ctx, key string)（既有，issue.sql，项目级 advisory lock 原语）
q.GetMemberByUserAndWorkspace（member.sql L15）、q.GetProjectInWorkspace（project.sql L8）、dbid.NewV7()（dbid.go L51）、chatMessageAuthorDisplayName（project_chat.go L739/L760）
```

**产出**（供 TASK-03 handler 消费，逐字对齐 SDD）：

```go
// server/internal/service/promotion.go
func canonicalUUIDs(ids []pgtype.UUID) []string
func promotionFingerprint(projectID, sessionID pgtype.UUID, msg, att []pgtype.UUID, upgradeToCR bool) string
func promotionDedupeKey(sessionID pgtype.UUID, msg, att []pgtype.UUID) string

type PromoteDiscussionParams struct {
    WorkspaceID   pgtype.UUID
    ProjectID     pgtype.UUID
    SessionID     pgtype.UUID
    CallerID      pgtype.UUID
    MessageIDs    []pgtype.UUID
    AttachmentIDs []pgtype.UUID
    Title         *string
    Description   *string
    UpgradeToCR   bool
    IdempotencyKey string
}
type PromotionSourceRefs struct {
    SessionID     pgtype.UUID
    MessageIDs    []pgtype.UUID
    AttachmentIDs []pgtype.UUID
}
type PromotionResult struct {
    IssueID     pgtype.UUID
    IssueNumber int32
    Created     bool
    UpgradeToCR bool
    RunID       pgtype.UUID // Valid 当 UpgradeToCR=true 且 run 已存在/已建
    SourceRefs  PromotionSourceRefs
}
func (s *IssueService) PromoteDiscussion(ctx context.Context, p PromoteDiscussionParams) (PromotionResult, error)
// 错误语义：ErrPromotionRunCreateFailed（→502 pipeline_run_create_failed，TASK-03 映射）、
//           ErrIdempotencyKeyReused（既有，project_chat.go，→409 idempotency_key_reused）、
//           ErrInvalidPromotionSelection（→400 invalid_promotion_selection）、
//           其它事务错误（→500 internal_error，TASK-03 映射）

// server/internal/service/issue.go
type PromotionRunPlan struct {
    RunID            pgtype.UUID
    Inputs           json.RawMessage
    ExecutionContext json.RawMessage
}
type IssueCreateParams struct { /* 既有字段不变；新增： */
    ContextRefs  json.RawMessage
    PromotionRun *PromotionRunPlan
}
func (s *IssueService) createInTx(ctx context.Context, qtx *db.Queries, p IssueCreateParams, opts IssueCreateOpts) (db.Issue, error)
// IssueService.Create 公开签名与行为不变（zero_diff）
```

- 错误→HTTP 映射职责在 TASK-03；本 TASK 只返回 typed sentinel，不直接写 HTTP。
