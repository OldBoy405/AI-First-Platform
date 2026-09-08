---
id: CR-2026-061-TASK-01
type: TASK
cr-ref: CR-2026-061
plan-ref: "change-requests/CR-2026-061/plan.md"
sdd-ref: "change-requests/CR-2026-061/sdd.md"
target-version: 0.34
title: multica 数据层：迁移 505/506/507 与 promotion sqlc 查询
slug: multica-db-migrations-and-promotion-sqlc
status: pending
estimate: 12h
depends-on: []
created: 2026-09-08T12:04:37+08:00
---

## 1. 任务描述

在 multica CR worktree（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-061`，基线 HEAD `eafce66b`）落地 promotion 的数据库层：三个迁移（505 scope CHECK 扩展、506 promotion run 部分唯一索引、507 context_refs GIN）与 `promotion.sql` 新 sqlc 查询，供 TASK-02 服务层消费。不写任何业务逻辑。

输入：已审批 SDD v1.1 §2.2/§2.5/§2.6/§4.2/§4.5/§13 + plan.md §6 证据命令表。

## 2. 涉及文件 / 模块

- `server/migrations/505_chat_idempotency_promotion_scope.up.sql` / `.down.sql`（新建）
- `server/migrations/506_pipeline_run_promotion_active_unique.up.sql` / `.down.sql`（新建）
- `server/migrations/507_issue_context_refs_gin.up.sql` / `.down.sql`（新建）
- `server/cmd/migrate/main.go`（`concurrentIndexCleanups` / `concurrentDownIndexCleanups` 登记 506/507）
- `server/pkg/db/queries/promotion.sql`（新建；sqlc 输入）
- `server/pkg/db/generated/`（`sqlc generate` 再生成产物，`server/sqlc.yaml` 输出目录）
- 测试：`server/cmd/migrate/*_test.go` 既有 total-invariant 测试不回归；新增 505 插入/约束名断言与 506 唯一性夹具（本 TASK 只保证 sqlc/迁移可编译可测，业务断言在 TASK-02/03）

## 3. 实现要点（SDD 对应节）

- **505**（SDD §2.2/§2.6）：单条 `ALTER TABLE chat_idempotency DROP CONSTRAINT chat_idempotency_scope_type_check, ADD CONSTRAINT chat_idempotency_scope_type_check CHECK (scope_type IN ('discussion_message','merge_forward_messages','discussion_promotion'))`。实施前先经 `pg_catalog`/测试夹具确认约束名为 PG 默认名 `{table}_{column}_check`（SDD §2.6 明示）。down：反向回旧枚举；前置 = 表内无 `discussion_promotion` 行（SDD §13.1）。
- **506**（SDD §2.5/D-8）：单语句 `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_pipeline_run_promotion_active_issue ON pipeline_run (workspace_id, issue_id) WHERE pipeline_id='requirement-authoring' AND status IN ('running','waiting_approval')`；登记 `concurrentIndexCleanups`（506 → idx_pipeline_run_promotion_active_issue）；down = `DROP INDEX CONCURRENTLY IF EXISTS` + `concurrentDownIndexCleanups` 登记（SDD §2.6）。
- **507**（SDD §2.5/§7.2）：单语句 `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_issue_context_refs_gin ON issue USING GIN (context_refs jsonb_path_ops)`；同上登记两表；模式与 192 `idx_issue_properties_gin` 一致。
- **promotion.sql**（新查询，逐字对齐 SDD §4.2/§4.3/§4.5；无新表，FR-12）：
  - `FindPromotionDuplicateIssue :one`：`SELECT * FROM issue WHERE workspace_id = $1 AND context_refs @> jsonb_build_array(jsonb_build_object('dedupe_key', $2::text)) LIMIT 1;`（SDD §4.2 原文）
  - `AppendIssueContextRefs :exec`：`UPDATE issue SET context_refs = context_refs || $2::jsonb WHERE id = $1;`（幂等追加语义，SDD §2.1）
  - `MergeIssueContextRefPipelineRun :one`：查重回填（SDD §4.3 步骤 10 / §2.1 追加语义）——`UPDATE issue SET context_refs = COALESCE((SELECT jsonb_agg(elem ORDER BY ord) FROM (SELECT t.ord, CASE WHEN t.elem->>'kind'='discussion_promotion' AND t.elem->>'dedupe_key'=$1::text THEN t.elem || jsonb_build_object('pipeline_run_id',$2::text) ELSE t.elem END AS elem FROM jsonb_array_elements(issue.context_refs) WITH ORDINALITY AS t(elem,ord)) AS merged), issue.context_refs) WHERE id=$3 RETURNING context_refs;`——按 `dedupe_key` 元素级原位合并 `pipeline_run_id`，其余数组元素与未知扩展字段逐字节保留（B-CODE-01：不整段覆写、不丢历史）；service 消费 RETURNING 数组做 fail-closed 校验
  - `InsertPipelineRun :one`：451 全字段（`workspace_id/pipeline_id/cr_id NULL/issue_id/status='running'/inputs/execution_context/started_by`），`RETURNING *`（SDD §2.3）
  - `InsertPipelineNodeRun :one`：`run_id/node_id/ref='requirement-register'/kind='skill'/seq=1/attempt=1/status='running'`（node_id=`00000000-0000-0000-0011-000000000001`），`RETURNING *`（SDD §2.3）
  - `FindActiveRequirementRunForIssue :one`：`SELECT * FROM pipeline_run WHERE workspace_id = $1 AND issue_id = $2 AND pipeline_id = 'requirement-authoring' AND status IN ('running','waiting_approval') LIMIT 1;`（506 冲突后重读，SDD §4.3）
  - `FindUnboundPromotionRunByID :one`：`SELECT * FROM pipeline_run WHERE id = $1 AND workspace_id = $2 FOR UPDATE;`（SDD §4.5 步骤 1）
  - `BindPromotionRunIfNull :execrows`：`UPDATE pipeline_run SET cr_id = $2 WHERE id = $1 AND cr_id IS NULL AND pipeline_id = 'requirement-authoring';`（CAS，SDD §4.5 步骤 3）
  - `MarkPipelineNodePassed :execrows`：`UPDATE pipeline_node_run SET status = 'passed' WHERE run_id = $1 AND node_id = $2 AND status = 'running';`（SDD §4.5/D-5）
  - `ListAttachmentsForPromotion :many`：`SELECT a.* FROM attachment a JOIN chat_message m ON m.id = a.chat_message_id WHERE a.id = ANY($1::uuid[]) AND m.chat_session_id = $2 AND a.chat_message_id IS NOT NULL;`（已绑定 session 消息的附件，SDD §4.3 步骤 6）
- 既有查询**零改动**（`idempotency.sql` 四查询、`agent.sql` `LockCrForCrBind`/`BindCrShellIssueIfNull`、`activity.sql` `CreateActivity` 复用不重写）。
- 行尾纪律（AGENTS.md #1）：迁移/查询文件 LF；解析器不涉及。

## 4. 验收条件

1. `cd server && sqlc generate` 零错误；`go build ./...` 通过；`pkg/db/generated` 含全部 10 个新查询的 Go 签名。
2. `go test ./cmd/migrate/ -count=1`（实施期全包专项证据；无 DB 时 DB 项 SKIP 通过）全绿：既有 `TestEveryConcurrentUpBuildHasCleanup` 类 total-invariant 测试不回归，506/507 登记断言通过；真库整包的 2 项上游既有失败不在本 TASK 面，canonical 收敛口径见 §6.2 cmd-02。
3. 迁移夹具：`server/migrations/` 无 `discussion_promotion` 命名迁移（AC-10 grep 断言）；505 后 `scope_type='discussion_promotion'` 可插入、约束名断言成立；506 后同一 `(workspace_id, issue_id)` 两条非终态 requirement-authoring run 插入第二行触发唯一冲突（23505）。
4. 505 down 在无 `discussion_promotion` 行时成功；506/507 down 经 `concurrentDownIndexCleanups` 可清理（夹具验证）。

## 5. 完成标志

- 上述 4 条验收全部通过；`sqlc generate` 与 `go vet ./...`（server 内）零报错；
- 迁移与查询提交落盘 multica CR 分支（commit 独立、可单独 revert）；
- `go test ./cmd/migrate/ -count=1` 与 `go test ./internal/governance/ -count=1`（**非 canonical 实施期全包专项证据**，无 DB 执行口径）；canonical cmd-02 为 §6.2 口径（`-run` 收敛至 AC-13/AC-10 相关 5 项测试函数 + DATABASE_URL 真库，其中 migrate 4 项由本 TASK 产出）。

## 6. 接口契约

**消费**：无上游 TASK。

**产出**（sqlc 生成 Go 签名，供 TASK-02 消费；逐字对齐 SDD）：

```go
// server/pkg/db/generated/promotion.sql.go（package db）
func (q *Queries) FindPromotionDuplicateIssue(ctx context.Context, arg FindPromotionDuplicateIssueParams) (Issue, error)
  // FindPromotionDuplicateIssueParams{ WorkspaceID pgtype.UUID; DedupeKey string }
func (q *Queries) AppendIssueContextRefs(ctx context.Context, arg AppendIssueContextRefsParams) error
  // AppendIssueContextRefsParams{ ID pgtype.UUID; ContextRefs []byte }   // $2::jsonb
func (q *Queries) MergeIssueContextRefPipelineRun(ctx context.Context, arg MergeIssueContextRefPipelineRunParams) ([]byte, error)
  // MergeIssueContextRefPipelineRunParams{ DedupeKey, PipelineRunID string; ID pgtype.UUID }
  // :one，RETURNING context_refs（合并后数组）——TASK-02 消费后必须 fail-closed 校验（B-CODE-01）
func (q *Queries) InsertPipelineRun(ctx context.Context, arg InsertPipelineRunParams) (PipelineRun, error)
  // InsertPipelineRunParams{ WorkspaceID, IssueID pgtype.UUID; PipelineID, CrID *string→sql.NullString;
  //   Status string; Inputs, ExecutionContext []byte; StartedBy pgtype.UUID }
func (q *Queries) InsertPipelineNodeRun(ctx context.Context, arg InsertPipelineNodeRunParams) (PipelineNodeRun, error)
  // InsertPipelineNodeRunParams{ RunID, NodeID pgtype.UUID; Ref string; Kind string; Seq, Attempt int32; Status string }
func (q *Queries) FindActiveRequirementRunForIssue(ctx context.Context, arg FindActiveRequirementRunForIssueParams) (PipelineRun, error)
  // FindActiveRequirementRunForIssueParams{ WorkspaceID, IssueID pgtype.UUID }
func (q *Queries) FindUnboundPromotionRunByID(ctx context.Context, arg FindUnboundPromotionRunByIDParams) (PipelineRun, error)
  // FindUnboundPromotionRunByIDParams{ ID, WorkspaceID pgtype.UUID }   // FOR UPDATE
func (q *Queries) BindPromotionRunIfNull(ctx context.Context, arg BindPromotionRunIfNullParams) (int64, error)
  // BindPromotionRunIfNullParams{ ID pgtype.UUID; CrID string }        // :execrows，返回受影响行数
func (q *Queries) MarkPipelineNodePassed(ctx context.Context, arg MarkPipelineNodePassedParams) (int64, error)
  // MarkPipelineNodePassedParams{ RunID, NodeID pgtype.UUID }          // :execrows，WHERE status='running'
func (q *Queries) ListAttachmentsForPromotion(ctx context.Context, arg ListAttachmentsForPromotionParams) ([]Attachment, error)
  // ListAttachmentsForPromotionParams{ AttachmentIds []pgtype.UUID; ChatSessionID pgtype.UUID }
```

- 既有复用（不改签名）：`LockCrForCrBind` / `BindCrShellIssueIfNull`（agent.sql L1128/L1146）、`CreateActivity`（activity.sql L29）、`InsertChatIdempotencyReservation` / `GetChatIdempotencyByKey` / `FinalizeChatIdempotency` / `DeleteChatIdempotencyByKey`（idempotency.sql）。
- 命名/签名若 sqlc 生成规则产生差异（如 `*string` 可空字段），以生成产物为准并在 TASK-02 接口契约复核时对齐，不得静默改变 SQL 语义。
