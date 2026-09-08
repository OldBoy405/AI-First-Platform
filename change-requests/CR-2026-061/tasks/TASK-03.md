---
id: CR-2026-061-TASK-03
type: TASK
cr-ref: CR-2026-061
plan-ref: "change-requests/CR-2026-061/plan.md"
sdd-ref: "change-requests/CR-2026-061/sdd.md"
target-version: 0.34
title: multica HTTP/绑定/CLI：promotion 端点、错误闭包与 bind-promotion-run 链路
slug: multica-promotion-http-bind-cli
status: pending
estimate: 20h
depends-on: ["CR-2026-061-TASK-02"]
created: 2026-09-08T12:04:37+08:00
---

## 1. 任务描述

在 multica CR worktree 落地 promotion 的 HTTP 面与 AC-13 绑定链路：`POST /api/projects/{projectId}/discussion/promote` handler + 路由 + 错误闭包（§4.4）；`IssueResponse.context_refs` 暴露（§3.4）；`POST /api/crs/{crID}/bind-promotion-run` handler + `BindPromotionRunToCR` service（§3.2/§4.5）；`multica cr bind-promotion-run` 薄命令（§3.3）。前端与 tools 不在此 TASK（TASK-04）。

输入：已审批 SDD v1.1 §3.1/§3.2/§3.3/§3.4/§4.4/§4.5 + TASK-02 产出。

## 2. 涉及文件 / 模块

- `server/internal/handler/promotion.go`（新建：`HandlePromoteProjectDiscussion` + 形状校验纯函数）
- `server/internal/handler/promotion_test.go`（新建）
- `server/cmd/server/router.go`（注册 `POST /discussion/promote` 与 `POST /api/crs/{crID}/bind-promotion-run`；前者紧邻 `GET /discussion` L2088 块）
- `server/internal/handler/issue.go`（`IssueResponse` 增 `ContextRefs []IssueContextRef \`json:"context_refs,omitempty"\``；`issueToResponse` 解析 JSONB；解析失败降级空数组+日志不 500）
- `server/internal/handler/cr_bind.go`（新增 `HandleBindPromotionRun`，与 `HandleBindCurrentTask` 同族独立）
- `server/internal/service/task.go`（新增 `BindPromotionRunToCR`，§4.5）
- `server/cmd/multica/cmd_cr.go`（新增 `crBindPromotionRunCmd` 薄命令）
- 复用不改：`handler.go` `writeErrorCode`（L578，`{code,error}`）/ `writeError`（L570，`{error}`）/ `parseUUIDOrBadRequest`（L669）/ `getWorkspaceMember`；`gate_projection.go` 零改动（§9 scope_out）

## 3. 实现要点（SDD 对应节）

- **`HandlePromoteProjectDiscussion`（§4.3 前置 1–6，零写入固定顺序）**：
  1. 请求形态校验（§3.1 request 表；`upgrade_to_cr` 用 `*bool` 区分缺省/错型；形状校验器为纯函数可单测）；
  2. project 解析（`parseUUIDOrBadRequest` → 400 `invalid_project_id`；`GetProjectInWorkspace` ErrNoRows → 404 `project_not_found`）；
  3. 成员门禁 `getWorkspaceMember` → 403 `forbidden_promotion`（先于 session 解析，不泄漏存在性）；
  4. Issue 创建权限 `CheckIssueCreateCapacity` → 403 `forbidden_promotion`（D-6；事务内 `AllocateIssueNumber` 权威判定同映射）；
  5. session 解析 `GetActiveProjectSharedSession` 且 == 请求 session_id → 404 `chat_session_not_found`；
  6. 来源选择：消息 `GetChatMessageInWorkspace` + session Join；附件 `ListAttachmentsForPromotion`；双空/重复/元素非 UUID → 400 `invalid_promotion_selection`。
  然后调 `IssueService.PromoteDiscussion`，按 typed sentinel 映射：`ErrIdempotencyKeyReused`→409 `idempotency_key_reused`；`ErrPromotionRunCreateFailed`→**502 `pipeline_run_create_failed`**；`ErrInvalidPromotionSelection`→400；其余→500 `internal_error`。全部经 `writeErrorCode`（`{code,error}`）。
- **成功响应 201（§3.1）**：`{issue_id, issue_number, session_id, source_refs, created, upgrade_to_cr, run_id}`；重放路径解析存储响应 + `created=false`。
- **`IssueResponse.context_refs`（§3.4）**：`IssueContextRef{Kind *string; SessionID *pgtype.UUID; MessageIDs []pgtype.UUID; AttachmentIDs []pgtype.UUID; PipelineRunID *pgtype.UUID; PromotedBy *pgtype.UUID; PromotedAt *time.Time}`，`omitempty` 形状；`issueToResponse` 解析失败 → 空数组 + 日志（API 兼容规则）。
- **`HandleBindPromotionRun`（§3.2，bind-current-task 同族独立）**：`X-Actor-Source != "task_token"` → 401 `{"error":"TASK_CONTEXT_REQUIRED"}`；body `{run_id}`；错误表逐行（400 `INVALID_RUN_ID` / 404 `RUN_NOT_FOUND` / 404 `CR_NOT_FOUND` / 409 `RUN_CR_CONFLICT` / 409 `CR_ISSUE_CONFLICT` / 500 `CR_BIND_FAILED`）；**错误体形状 = `{"error":...}` 族（writeJSON/writeError），不经 writeErrorCode**；200 响应 `{cr_id, run_id, issue_id, changed}`。
- **`BindPromotionRunToCR`（§4.5，service/task.go）**：`FindUnboundPromotionRunByID FOR UPDATE`（ErrNoRows→`ErrPromotionRunNotFound`；`run.CrID.Valid && != crID`→`ErrPromotionRunCRConflict`；`== crID`→changed=false）→ `LockCrForCrBind`（→`ErrPromotionCRNotFound`）→ `BindPromotionRunIfNull`（CAS）+ `BindCrShellIssueIfNull`（既有复用）+ `MarkPipelineNodePassed(run, node_id='00000000-0000-0000-0011-000000000001')` + `CreateActivity(action='promotion_run_bound')` → commit；changed 时 `publishCRUpdated`。任一失败整体回滚（含审计行）。
- **投影协作（零改动验证）**：集成测试断言绑定后注入 `requirement-reviewing`/review 状态事件 → `gate_projection.findOrCreateRun` 按 `cr_id` 命中同一行不新建（`pipeline_run` 行数不增）；`upsertNodeRunning`/`applyReview` 只写 seq5/seq4；seq1 保持 passed。
- **CLI 薄命令（§3.3）**：`multica cr bind-promotion-run <cr-id> --run-id <uuid>`，只中继 mat_ task token 与 body，透传结构化结果，`--output json|table`，无业务判断（同 `crBindCurrentTaskCmd` 实现契约）。

## 4. 验收条件

1. `go test ./internal/handler/ -count=1` 全绿：AC-2 选择矩阵（只消息/只附件/混合 201；空/重复/草稿附件/他 session → 400 `invalid_promotion_selection`；非法 JSON → `invalid_request_body`；projectId/session_id 非 UUID；title>200/description>10000 各自 400，均零写入）；AC-6 固定顺序（非成员 403 不泄漏 session 存在性；limit 夹具 403；session 四类 404；project 404）；AC-11 逐类错误夹具零残留 + 500/502 原 key 重试成功。
2. 绑定端点错误矩阵：401 `TASK_CONTEXT_REQUIRED`（错误体 `{"error":...}` 形状断言）/400 `INVALID_RUN_ID`/404 `RUN_NOT_FOUND`/404 `CR_NOT_FOUND`/409 `RUN_CR_CONFLICT`（二次绑定异 CR）/200 `changed=false` 幂等重放/审计行 `promotion_run_bound`；`IssueResponse.context_refs` 透出与解析失败降级。
3. `go test ./internal/governance/ -count=1`（实施期全包专项证据；无 DB 时 DB 项 SKIP 通过）全绿：投影协作集成（绑定后注入 requirement-reviewing/review 事件 → 行数不增、seq1 保持 passed）；真库整包的 5 项上游既有失败不在本 TASK 面，canonical 收敛口径见 §6.2 cmd-02。
4. `multica cr bind-promotion-run --output json` 端到端（受控夹具）：成功透传、task token 缺失 401 形状、`--run-id` 非法 400。

## 5. 完成标志

- 上述 4 条全部通过；`go vet ./...`（server）零报错；
- 提交落盘 multica CR 分支（独立 commit）；
- `go test ./internal/handler/ ./internal/service/ -count=1` 全绿（**非 canonical 实施期全包专项证据**）；`go test ./internal/governance/ ./cmd/migrate/ -count=1`（**非 canonical 实施期全包专项证据**）；canonical cmd-01 为 §6.2 口径（21 项 promotion `-run` 过滤 + DATABASE_URL 真库，其中 handler 8 项由本 TASK 产出）；canonical cmd-02 为 §6.2 口径（`-run` 收敛至 AC-13/AC-10 相关 5 项测试函数 + DATABASE_URL 真库，其中 governance 1 项由本 TASK 产出）。

## 6. 接口契约

**消费**（TASK-02 产出，逐字对齐）：

```go
s.PromoteDiscussion(ctx, service.PromoteDiscussionParams{WorkspaceID, ProjectID, SessionID, CallerID, MessageIDs, AttachmentIDs, Title *string, Description *string, UpgradeToCR bool, IdempotencyKey string}) (service.PromotionResult, error)
// PromotionResult{IssueID pgtype.UUID; IssueNumber int32; Created bool; UpgradeToCR bool; RunID pgtype.UUID; SourceRefs service.PromotionSourceRefs}
// sentinels：service.ErrPromotionRunCreateFailed / service.ErrIdempotencyKeyReused / service.ErrInvalidPromotionSelection
q.GetActiveProjectSharedSession（chat.sql L1723）/ q.GetChatMessageInWorkspace（chat.sql L1748）
q.CheckIssueCreateCapacity（issue_limit.go L67）
h.getWorkspaceMember / writeErrorCode（handler.go L578）/ writeError（handler.go L570）/ parseUUIDOrBadRequest（handler.go L669）
q.LockCrForCrBind（agent.sql L1128）/ q.BindCrShellIssueIfNull（agent.sql L1146）/ q.CreateActivity（activity.sql L29）
q.FindUnboundPromotionRunByID / q.BindPromotionRunIfNull / q.MarkPipelineNodePassed（TASK-01 产出）
```

**产出**（供 TASK-04 前端与 tools 消费，逐字对齐 SDD §3.1/§3.2/§3.3）：

```text
POST /api/projects/{projectId}/discussion/promote
  请求头 Idempotency-Key 必填（≤255B）
  请求体 {"session_id","message_ids","attachment_ids","title","description","upgrade_to_cr"}
  201 {"issue_id","issue_number","session_id","source_refs":{"session_id","message_ids","attachment_ids"},"created","upgrade_to_cr","run_id"}
  错误体 {"code","error"}：400 invalid_request_body|invalid_project_id|invalid_promotion_selection|invalid_promotion_title|invalid_promotion_description|idempotency_key_required|invalid_idempotency_key；
        403 forbidden_promotion；404 project_not_found|chat_session_not_found；409 idempotency_key_reused；500 internal_error；502 pipeline_run_create_failed

POST /api/crs/{crID}/bind-promotion-run
  仅 task token（401 {"error":"TASK_CONTEXT_REQUIRED"}）
  请求体 {"run_id"}；200 {"cr_id","run_id","issue_id","changed"}
  错误体 {"error":"<code>"}：400 INVALID_RUN_ID；404 RUN_NOT_FOUND|CR_NOT_FOUND；409 RUN_CR_CONFLICT|CR_ISSUE_CONFLICT；500 CR_BIND_FAILED

multica cr bind-promotion-run <cr-id> --run-id <uuid> [--output json|table]
GET issue 响应新增 "context_refs": [{"kind","session_id","message_ids","attachment_ids","pipeline_run_id","promoted_by","promoted_at"}]
```
