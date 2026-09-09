---
id: CR-2026-061-sdd
type: SDD
cr-ref: CR-2026-061
title: Discussion 显式升级 技术设计
target-version: 0.34
status: draft
created: 2026-09-08T00:54:52+08:00
updated: 2026-09-08T03:50:09+08:00
---

# Discussion 显式升级（CR-2026-061）技术设计

输入：已审批 PRD v0.3（A 口径）。基线：multica trunk `78e14082` / tools trunk `49c46dd` / docs（knowledge-base）CR 分支含 PRD v0.3 提交 `fc5c3fb` 及后续评审/审批提交。本 SDD 覆盖全部 13 FR、HTTP 契约、AC-13 跨仓消费契约，并逐条处理第 3 轮需求评审的 3 条非阻塞 suggestions（见 §11）。

---

## 0. 术语硬化与基线（Step 2.5 FR-08）

### 0.1 术语表（只进入数据模型/接口契约且有歧义风险的术语）

| PRD canonical term | 代码别名（Go/TS/sqlc） | 硬化结论 |
|---|---|---|
| 升级（promotion） | `promotion` / `PromoteDiscussion` | 指 Discussion → 工作 Issue 的唯一显式出口，不是 merge-forward（那是转发到 Team Agent） |
| 预建 run（promotion 预建 pipeline run） | `promotion run` / `FindActiveRequirementRunForIssue` | `pipeline_run` 行：`pipeline_id='requirement-authoring'`、`cr_id=NULL`（绑定后为 CR-ID）、`issue_id=目标 Issue`、`status='running'`、`started_by=调用者`。**同一行**在绑定前后复用，不新建 |
| 目标 Issue | `target issue` / 响应 `issue_id` | promotion 创建或查重命中的正式工作 Issue（`origin_type` 不设置任何 Discussion 容器标签，避免与历史 `project_discussion` 混淆） |
| canonical fingerprint（FR-7） | `promotionFingerprint()` | 含 `upgrade_to_cr` 的幂等指纹，作用域 `(workspace,user,scope='discussion_promotion',scope_id=project,key)` |
| 查重键（FR-6） | `dedupe_key`（存于 `context_refs` 条目） | 仅由来源集合（session+message set+attachment set）推导，不含 `upgrade_to_cr`；与 fingerprint 是**两个不同摘要**，防止混淆（PRD FR-6/FR-7 分开定义） |
| 绑定（AC-13） | `BindPromotionRunToCR` / `multica cr bind-promotion-run` | 把预建 run 的 `cr_id` 由 NULL 更新为新 CR-ID 的唯一通道；绑定幂等、仅一次 |
| 来源引用 | `issue.context_refs` 条目 `kind='discussion_promotion'` | 规范化来源集合 + `dedupe_key` + `promoted_by/promoted_at`（+ `pipeline_run_id`） |

代表性边界场景验证：同源先普通升级、后 `upgrade_to_cr=true`（新 key）→ 指纹不同（含 `upgrade_to_cr`）所以 409 不触发；查重命中（dedupe_key 相同）→ 补建 run 并回写 `pipeline_run_id`，至多一条 run。该场景在 §4.3 完整推演。

### 0.2 语义冲突检查

对照 PRD v0.3 与 multica `78e14082` 逐条核实，**未发现新的阻塞性语义冲突**（v0.2 的 FR-10 冲突已在 A 口径修订中解决）。第 3 轮评审 3 条 suggestions 均为非阻塞项，本 SDD 全部「已处理」（§11），无需退回需求侧。首次 `crctl advance` 前不设停步点。

### 0.3 既有 CONTEXT.md 沿用

knowledge-base `CONTEXT.md` 与 multica `CONTEXT.md` 若存在均只读沿用；本 CR 不修订。

---

## 1. 架构概览

### 1.1 模块边界

```text
packages/views/projects/components/discussion-pane.tsx   (多选 + 两个升级入口 UI)
  -> packages/core/api/client.ts promoteDiscussion()      (Idempotency-Key 客户端强制)
  -> POST /api/projects/{projectId}/discussion/promote
       server/internal/handler/promotion.go   PromoteProjectDiscussion
         -> server/internal/service/promotion.go  IssueService.PromoteDiscussion
              -> IssueService.createInTx(...)             [自 Create() 提取的既有事务内核，唯一 Issue 写入路径]
              -> db: promotion.sql (新 sqlc) + issue.sql/chat.sql/idempotency.sql 既有查询
              -> events.Bus (issue:created，提交后)

knowledge-base requirement-register Skill（tools 仓）
  -> crctl register（既有深原语，不改）
  -> multica cr bind-promotion-run <cr-id> --run-id <uuid>     [AC-13 消费]
       server/cmd/multica/cmd_cr.go (新子命令，薄转发)
       -> POST /api/crs/{crID}/bind-promotion-run
            server/internal/handler/cr_bind.go  HandleBindPromotionRun
              -> service/task.go TaskService.BindPromotionRunToCR

server/internal/governance/gate_projection.go                [不改：复用语义，见 §4.5]
```

依赖方向保持 ARCHITECTURE.md §4：handler → service → db；`packages/views` 只经 `core` 访问 API；governance 投影不新增写路径。

### 1.2 关键流程总览

1. **升级**：成员 POST promote（固定判定顺序）→ 项目级 advisory lock 内「key 冲突检查 → 来源查重 → 创建/补建」单事务提交 → 提交后广播 `issue:created`。
2. **升级为 CR**：`upgrade_to_cr=true` 分支在同一事务追加预建 `pipeline_run` + 首节点 `pipeline_node_run`（无 `agent_task_queue`），响应携带 `run_id`。
3. **CR 注册消费（AC-13）**：knowledge-base `crctl register` 成功拿到 CR-ID 后，requirement-register 经 `multica cr bind-promotion-run` 绑定预建 run（`cr_id` NULL → CR-ID、`cr.shell_issue_id` 同步 CAS、首节点置 `passed`），之后 CR 状态事件投影 `findOrCreateRun` 按 `cr_id` 命中同一行复用。

### 1.3 涉及仓库

| 仓 | 改动 |
|---|---|
| multica（`resources[].worktreePath` = `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-061`） | handler/service/sqlc/CLI/迁移 505–507/前端/测试 |
| tools（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-061`） | `skills/requirement/requirement-register/SKILL.md` promotion 上下文与绑定步骤（FR-10 配套点）；`crctl.mjs` **零改动** |
| knowledge-base（operational workspace） | 本 sdd.md 与 `_context.md` 导航缓存；不改任何 CR 账本 |

---

## 2. 数据模型

### 2.1 `issue.context_refs` 条目 schema（新写入语义）

```jsonc
// issue.context_refs 是 JSONB 数组；本 CR 追加的 promotion 条目：
{
  "kind": "discussion_promotion",          // 固定机器可读类型标记
  "session_id": "<小写 UUID>",
  "message_ids": ["<排序去重小写 UUID>"],   // 可为空数组
  "attachment_ids": ["<排序去重小写 UUID>"],
  "dedupe_key": "<sha256 hex>",            // FR-6 查重键，见 §4.1
  "promoted_by": "<调用者 UUID>",
  "promoted_at": "<RFC3339 UTC>",
  "pipeline_run_id": "<UUID>"              // 仅 upgrade_to_cr=true 分支，同事务回写
}
```

- 条目由服务端生成（NFR-5），前端不能提交任意 `context_refs`。
- `message_ids`/`attachment_ids` 排序去重（FR-4）。条目是唯一匹配锚点：查重/回写都按 `dedupe_key` 定位该条目。
- 追加语义：`UPDATE issue SET context_refs = context_refs || $jsonb`（幂等追加到数组尾部），不覆盖既有条目；升级不删除任何历史条目。

### 2.2 `chat_idempotency` scope 扩展（迁移 505）

- `scope_type` CHECK 增加 `'discussion_promotion'`；`scope_id` 语义 = **project_id**（FR-7 作用域）。
- 复用既有四查询：`InsertChatIdempotencyReservation` / `GetChatIdempotencyByKey` / `FinalizeChatIdempotency` / `DeleteChatIdempotencyByKey`（`idempotency.sql`）。`response_status` 存 201，`response_body` 存完整成功响应 JSON（重放用）。
- 24h 清理（`SweepChatIdempotency`）自动覆盖新 scope，无需新清理器。

### 2.3 预建 `pipeline_run` / `pipeline_node_run`（复用 451 表结构，新 sqlc INSERT）

| 字段 | 取值 | 依据 |
|---|---|---|
| `workspace_id` | 项目所属 workspace | tenant 隔离 |
| `pipeline_id` | `'requirement-authoring'` | 451 允许任意 pipeline 文本；模板已注册（gate_nodes_gen.go `PipelineIDs.RequirementAuthoring`） |
| `cr_id` | 创建时 **NULL**；绑定后 = 新 CR-ID（同一行） | 451 `cr_id TEXT` 可 NULL（规划类 pipeline 无 CR 的既有语义） |
| `issue_id` | 目标 Issue | 451 `ON DELETE SET NULL`；AC-13 识别键 |
| `status` | `'running'` | CHECK 允许；投影 `findOrCreateRun` 按 `status IN ('running','waiting_approval')` 命中 |
| `started_by` | 调用者 member UUID | 451 `started_by UUID NOT NULL` |
| `inputs` | 来源上下文：`{session_id, message_ids[], attachment_ids[], promoted_by, promoted_at}`（排序去重后） | FR-10；机器可读 |
| `execution_context` | §2.4 注册意图标记 | FR-10；幂等可重放（内容确定性生成） |

首节点 `pipeline_node_run`：`node_id='00000000-0000-0000-0011-000000000001'`（requirement-authoring 模板第 1 节点 requirement-register skill 节点，见 gate_nodes_gen.go `ArchitectureCoreRegistryJSON` 同族常量，ReviewGateNodes/ApprovalGateNodes 已证明该 ID 空间：审批节点 seq5、评审节点 seq4 均已注册）、`ref='requirement-register'`、`kind='skill'`、`seq=1`、`attempt=1`、`status='running'`、`started_at=now()`。不创建 `agent_task_queue` 行。

### 2.4 `execution_context`（注册意图标记，机器可读 + 幂等可重放）

```json
{
  "intent": "discussion-promotion",
  "expect_bind": true,
  "bind_hint": { "endpoint": "POST /api/crs/{crID}/bind-promotion-run", "cli": "multica cr bind-promotion-run" },
  "source": { "project_id": "<UUID>", "session_id": "<UUID>",
              "message_ids": ["<UUID>"], "attachment_ids": ["<UUID>"] }
}
```

确定性：`project_id` 取 `project.id` 规范小写；`source.*` 与 `inputs` 同一规范化结果。重放时生成的 `run_id` 不参与内容（`run_id` 在行上，不在 JSON 里），因此同输入重放不产生内容漂移。

### 2.5 新索引（迁移 506/507）与唯一性 guard

- **506 `idx_pipeline_run_promotion_active_issue`**：部分唯一索引
  `ON pipeline_run (workspace_id, issue_id) WHERE pipeline_id='requirement-authoring' AND status IN ('running','waiting_approval')`。
  作用：①「同一目标 Issue 至多一条 requirement-authoring 非终态 run」的 **DB 级保障**，覆盖绑定前（`cr_id IS NULL`）与绑定后（`cr_id=CR-ID`）同一行两个阶段——PRD「任何情况下同一 promotion 至多存在一条 run（始终同一行）」从应用锁升级为约束；②promotion 识别键查询（`workspace_id, issue_id` 前缀）的索引支撑，解决 suggestion-1（现有 `idx_pipeline_run_workspace_status` 弱覆盖）。`issue_id IS NULL` 的普通注册投影 run 不受影响（PG 唯一索引对 NULL 不冲突）。
- **507 `idx_issue_context_refs_gin`**：`CREATE INDEX ... ON issue USING GIN (context_refs jsonb_path_ops)`，支撑 §4.2 的 `@>` 查重。无新表（FR-12 默认路径）。

### 2.6 迁移清单与 DDL 规范

| 迁移 | 内容 | 说明 |
|---|---|---|
| `505_chat_idempotency_promotion_scope` | 单条 `ALTER TABLE chat_idempotency DROP CONSTRAINT chat_idempotency_scope_type_check, ADD CONSTRAINT chat_idempotency_scope_type_check CHECK (scope_type IN ('discussion_message','merge_forward_messages','discussion_promotion'))` | 一条 ALTER 两动作原子完成，**无约束缺失窗口**；约束名是 PG 默认名 `{table}_{column}_check`，实施时先经 `pg_catalog`/测试夹具确认再 DROP。down：反向回旧枚举（前提：无 `discussion_promotion` 行，见 §13） |
| `506_pipeline_run_promotion_active_unique` | 单语句 `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_pipeline_run_promotion_active_issue ...` | 并发建索引单文件单语句（CLAUDE.md 硬规则）；登记 `cmd/migrate concurrentIndexCleanups`（506 → `idx_pipeline_run_promotion_active_issue`），down 登记 `concurrentDownIndexCleanups` |
| `507_issue_context_refs_gin` | 单语句 `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_issue_context_refs_gin ON issue USING GIN (context_refs jsonb_path_ops)` | 同上登记两表；down `DROP INDEX CONCURRENTLY IF EXISTS` |

迁移号基线：当前最新 **504**，故 promotion 扩展取 **505/506/507**（PRD §1.4 已核实）。三个 up 各有对应 down；down 的数据依赖语义见 §13。

---

## 3. 接口契约

### 3.1 `POST /api/projects/{projectId}/discussion/promote`

路由：`server/cmd/server/router.go` 项目路由块，紧邻 `GET /discussion` 之后注册（与 merge-forward 同处项目成员路由树）。

**请求**

```jsonc
// 头：Idempotency-Key（必填，≤255B，foundation.go HeaderIdempotencyKey/MaxIdempotencyBytes）
{
  "session_id": "<UUID>",                    // 必填
  "message_ids": ["<UUID>"],                 // 可空数组，无重复 UUID
  "attachment_ids": ["<UUID>"],              // 可空数组，无重复 UUID
  "title": "string ≤200",                    // 可选
  "description": "string ≤10000",            // 可选
  "upgrade_to_cr": true|false                // 可选，缺省 false；类型错误 → 400 invalid_request_body
}
```

**成功响应（201）**

```jsonc
{
  "issue_id": "<UUID>", "issue_number": 123,
  "session_id": "<UUID>",
  "source_refs": { "session_id": "<UUID>", "message_ids": ["<UUID>"], "attachment_ids": ["<UUID>"] },
  "created": true|false,
  "upgrade_to_cr": false,
  "run_id": "<UUID>|null"
}
```

- `created=false` 覆盖重放与查重命中两类；重放 = 存储响应回放且强制 `created=false`（其余字段与首次一致，PRD FR-7）。
- `run_id`：`upgrade_to_cr=true` 且 run 已创建/已存在时非空；查重命中补建后返回同一（唯一）run 的 id；`upgrade_to_cr=false` 恒为 null。

**错误闭包**：完全按 PRD「错误闭包」表实现（错误体 `{code, error}` 经 `writeErrorCode`），实现映射见 §4.4 与 §6 FR-13 行。状态码总集 201/400/403/404/409/500/502，无 200、无 402。

### 3.2 `POST /api/crs/{crID}/bind-promotion-run`（AC-13 绑定端点，bind-current-task 同族）

- 路由：`r.Post("/api/crs/{crID}/bind-promotion-run", h.HandleBindPromotionRun)`，与 `bind-current-task` 相邻。
- 鉴权：**仅 task token（mat_）**，与 bind-current-task 同族口径（suggestion-2 已处理）：非 task_token → 401 `{"error":"TASK_CONTEXT_REQUIRED"}`；task/agent/workspace 由 auth 中间件服务端戳记，客户端不可指定。
- 请求体：`{"run_id":"<UUID>"}`（唯一输入；issue_id 由 run 行服务端派生，CR-ID 在路径）。

```jsonc
// 200 成功（幂等重放 changed=false）
{ "cr_id": "<CR-ID>", "run_id": "<UUID>", "issue_id": "<UUID>", "changed": true|false }
```

| 场景 | HTTP | code（错误体 `error` 字段） |
|---|---|---|
| 非 task_token | 401 | `TASK_CONTEXT_REQUIRED` |
| 请求体非法 / run_id 非 UUID | 400 | `INVALID_RUN_ID` |
| run 不存在于 token workspace / 非 promotion 形状（`pipeline_id≠requirement-authoring` 或 `issue_id IS NULL`）/ 已终态 | 404 | `RUN_NOT_FOUND` |
| CR 不存在于 token workspace | 404 | `CR_NOT_FOUND` |
| **run 已绑定到其它 CR（二次绑定，固定冲突响应）** | **409** | **`RUN_CR_CONFLICT`** |
| `cr.shell_issue_id` 已被其它 Issue 占用 | 409 | `CR_ISSUE_CONFLICT` |
| 其它失败（事务/审计） | 500 | `CR_BIND_FAILED` |

> **错误体形状（suggestion-2 已处理）**：本端点所有错误行沿用 bind-current-task 同族形状 `{"error":"<code>"}`（`writeJSON(w, ..., map[string]string{"error": ...})` / `writeError`，见 cr_bind.go L36/L61 与 handler.go `writeError`），**不经** `writeErrorCode` 的 `{code,error}` 形状族（那是 §3.1 promotion 端点的形状）。实施期不得误套 writeErrorCode；契约测试按 `{"error":"TASK_CONTEXT_REQUIRED"}` 等固定形状断言。

- **幂等语义**：同一 run + 同一 CR 重放 → 200 `changed=false`，零写入（CAS 判定来自锁内旧值，同 bind-current-task AC-B3 模式）。
- **二次绑定固定响应**（suggestion-2）：run 已绑定到**不同** CR → 409 `RUN_CR_CONFLICT`；绑定到**相同** CR → 幂等成功。两种结果确定、可测试。
- 绑定事务内同时：`pipeline_run.cr_id` NULL→CR-ID、`cr.shell_issue_id` NULL→run.issue_id（既有 `BindCrShellIssueIfNull` 复用）、首节点 `pipeline_node_run`（seq1）置 `passed`（§4.5）、`activity_log` 审计行（action=`promotion_run_bound`）。任一失败整体回滚。

### 3.3 `multica cr bind-promotion-run <cr-id> --run-id <uuid>`（CLI 薄命令）

- `server/cmd/multica/cmd_cr.go` 新增子命令：只中继 mat_ task token 与 `{run_id}` 到 3.2 端点，透传结构化结果，无业务判断、无账本写入、无 body 构造（同 `bind-current-task` 实现契约）。`--output json|table`。
- knowledge-base 侧调用形态：`multica cr bind-promotion-run {cr_id} --run-id {run_id}`（requirement-register Skill 在 `crctl register` 成功后执行）。

### 3.4 `IssueResponse.context_refs` 暴露（AC-7 可读性）

- Go：`IssueResponse` 增加 `ContextRefs []IssueContextRef \`json:"context_refs,omitempty"\``，`issueToResponse` 从 `i.ContextRefs` JSONB 解析（解析失败→空数组+日志，不回退 500——详情端点本身已有 source-context 的 500 先例，但 context_refs 是附加展示字段，按 API 兼容规则降级为空更安全，见 §7）。
- 其中 `IssueContextRef = { kind?, session_id?, message_ids?, attachment_ids?, pipeline_run_id?, promoted_by?, promoted_at? }`。
- TS：`packages/core/api/schemas.ts` `IssueSchema` 增 `context_refs`（`z.array(...).catch([])`），兼容旧后端缺字段（API 兼容规则：desktop 旧版本前端容忍新增字段，新前端对旧后端回退空数组）。`PromotionResultSchema` 新 schema + `parseWithFallback` + malformed-response 测试（CLAUDE.md API Compatibility）。

---

## 4. 关键算法与流程

### 4.1 两个摘要（fingerprint 与 dedupe_key 分离）

```go
// service/promotion.go，纯函数，单元测试覆盖（含大小写、重复、乱序输入）
func canonicalUUIDs(ids []pgtype.UUID) []string          // 小写排序去重
func promotionFingerprint(projectID, sessionID pgtype.UUID, msg, att []pgtype.UUID, upgradeToCR bool) string
    // = SHA256(canonical JSON, 固定键序):
    // {"projectId":..,"session_id":..,"message_ids":[..],"attachment_ids":[..],"upgrade_to_cr":bool}
func promotionDedupeKey(sessionID pgtype.UUID, msg, att []pgtype.UUID) string
    // = SHA256({"session_id":..,"message_ids":[..],"attachment_ids":[..]}) —— 不含 projectId/upgrade_to_cr（FR-6）
```

`title`/`description` 不参与任何摘要（FR-7）。两摘要用途：fingerprint → `chat_idempotency.fingerprint`（同 key 冲突判定）；dedupe_key → `context_refs` 条目（跨 key 同源查重）。

### 4.2 来源查重 SQL（`promotion.sql`）

```sql
-- name: FindPromotionDuplicateIssue :one
SELECT * FROM issue
WHERE workspace_id = $1
  AND context_refs @> jsonb_build_array(jsonb_build_object('dedupe_key', $2::text))
LIMIT 1;
```

JSONB 包含语义：右对象 `{"dedupe_key":K}` 匹配任何含同值该键的条目（条目可有额外字段），507 GIN 索引加速。命中后条目内 `pipeline_run_id` 是否已存在决定「直接返回」还是「补建」分支。

### 4.3 `PromoteDiscussion` 主流程（service/promotion.go）

```
输入: workspaceID, projectID, sessionID, callerID, messageIDs[], attachmentIDs[],
      title*, description*, upgradeToCR, idempotencyKey   (* 可选，超限已在 handler 拒绝)

前置（handler，零写入，固定顺序 = PRD 判定顺序 1-6）:
 1) 请求形态校验（400 类，§3.1 request 表 + FR-3 形状项）
 2) projectId 解析与存在性（400/404）
 3) 成员门禁 getWorkspaceMember（403 forbidden_promotion）
 4) Issue 创建权限：CheckIssueCreateCapacity（issue_limit 既有口径，见 D-6）→ 超限 403 forbidden_promotion
 5) session 解析：GetActiveProjectSharedSession(ws,project) 且 == 请求 session_id，否则 404 chat_session_not_found
 6) 来源选择：每个 message 经 GetChatMessageInWorkspace + 会话 Join 校验属于该 session；
    每个 attachment 经 ListAttachmentsForPromotion（attachment JOIN chat_message ON chat_session_id）校验绑定该 session 消息；
    message/attachment 至少其一非空

事务（qtx）:
 7) qtx.LockIssueDuplicateKey(ctx, "project-discussion-promotion|{ws}|{project}")   // 项目级 advisory lock（新前缀，D-4）
 8) 锁内成员复核 GetMemberByUserAndWorkspace（鉴权复核在事务内、首次写入前，§13）→ 403
 9) InsertChatIdempotencyReservation(scope='discussion_promotion', scope_id=projectID, key, fingerprint)
    - 成功（本请求持有 key）→ 继续
    - ON CONFLICT → GetChatIdempotencyByKey:
        winner.Fingerprint != fingerprint        → 409 idempotency_key_reused（零写入，优先级先于查重）
        winner.ResponseBody != nil               → 重放：解析存储响应 + created=false，返回（不新建任何东西）
        winner.ResponseBody == nil               → 接管：上次执行中断，本请求以既有 reservation 行继续
10) dedupe 查重 FindPromotionDuplicateIssue(dedupe_key):
    - 未命中 → 创建分支：
        runID := upgradeToCR ? dbid.NewV7() : 无效
        entry := 构建 §2.1 条目（upgradeToCR 时含 pipeline_run_id=runID）
        s.createInTx(ctx, qtx, IssueCreateParams{..., AllowDuplicate:true, ProjectID:projectID,
                              ContextRefs: [entry], PromotionRun: upgradeToCR ? plan(runID, inputs, execCtx) : nil})
        // createInTx 复用既有 Issue 写入路径：duplicate guard（AllowDuplicate 跳过标题查重）、
        // status 校验、project 校验、labels、AllocateIssueNumber（限容权威判定）、
        // NextTopPosition、CreateIssue、AppendIssueContextRefs、CreatePipelineRun+CreatePipelineNodeRun
    - 命中 → 查重分支：
        issue := 既有 Issue；source_refs 从命中条目还原
        if upgradeToCR && 条目无 pipeline_run_id:
            runID := dbid.NewV7()；CreatePipelineRun+CreatePipelineNodeRun；
            SetIssueContextRefPipelineRun(issue, dedupe_key, runID)
            // 若并发补建触发 506 唯一冲突 → FindActiveRequirementRunForIssue 重读既有 run 并采用其 id（不报错）
        else if upgradeToCR: runID := 条目已有 pipeline_run_id
11) 组装响应 result（created 按分支）；FinalizeChatIdempotency(key, 201, body=result)（同一事务）
12) Commit

提交后（post-commit，失败不回滚已提交数据，NFR-4）:
  publishIssueCreated(issue, ..., opts)  // 既有 issue:created 事件；创建分支才发布
  captureCreatedAnalytics(...)
```

**并发收敛推演**（AC-5/AC-8 依赖）：同项目同源并发 → 步骤 7 串行化；第二个事务进入后先命中同 key（若同 key）或 dedupe 查重（异 key）；`upgrade_to_cr` 并发时第二个事务拿到的是**同一行 run**（条目已含 `pipeline_run_id`，或 506 唯一冲突后重读）。绑定与补建不可能交错：绑定只对已存在 run 发生，而已存在 run 意味着其创建事务已把 `pipeline_run_id` 写入条目（同一事务）——补建分支只会出现在「条目无 run」时，此时不存在可绑定的 run。

### 4.4 错误闭包实现映射（FR-13）

| PRD 场景 | HTTP/code | 实现点 |
|---|---|---|
| JSON 非法 / `upgrade_to_cr` 类型错误 | 400 `invalid_request_body` | `json.Decoder` 失败或 `*bool` 解出 null（非指针 bool 无法区分缺省/错型，故用 `*bool`） |
| `projectId` 非 UUID | 400 `invalid_project_id` | `parseUUIDOrBadRequest`（路径参数） |
| project 不存在 | 404 `project_not_found` | `GetProjectInWorkspace` → ErrNoRows |
| session 形状错误 / 数组非法 / 双空 / 重复 | 400 `invalid_promotion_selection` | 形状校验器（纯函数 + 单测） |
| title/description 超限或非字符串 | 400 `invalid_promotion_title` / `invalid_promotion_description` | 形状校验器 |
| Idempotency-Key 缺失 / 非法 | 400 `idempotency_key_required` / `invalid_idempotency_key` | handler 头部校验（≤ `MaxIdempotencyBytes`，空白判定 `strings.TrimSpace`） |
| 非成员 | 403 `forbidden_promotion` | 步骤 3/8 |
| 无 Issue 创建权限（容量门禁） | 403 `forbidden_promotion` | 步骤 4 + 事务内 `AllocateIssueNumber` 的 `IssueLimitReachedError` 映射（D-6） |
| session 不存在/跨项目/非 project_shared/非 active | 404 `chat_session_not_found` | 步骤 5 |
| 消息/附件不属于该 session | 400 `invalid_promotion_selection` | 步骤 6 |
| 同 key 异指纹 | 409 `idempotency_key_reused` | 步骤 9 |
| 锁/死锁/连接/事务失败 | 500 `internal_error` | 事务错误捕获（deferred Rollback，零残留） |
| run 创建失败（含 506 冲突后重读也失败、execution_context 序列化失败） | 502 `pipeline_run_create_failed` | upgrade 分支任何 run/节点写入错误 → 整事务回滚 |
| 其它未预期 | 500 `internal_error` | 默认分支 |

500/502 均整体回滚（事务内无部分提交），原 key 重试幂等安全（同指纹重放或同 reservation 接管）。

### 4.5 绑定与投影协作（suggestion-3 已处理）

```
BindPromotionRunToCR（service/task.go，同族 bind-current-task）:
  tx 开始
  1) FindUnboundPromotionRunByID(runID, workspace) FOR UPDATE   // 锁 run 行
       ErrNoRows → RUN_NOT_FOUND
       run.CrID.Valid && run.CrID != crID → RUN_CR_CONFLICT（固定冲突）
       run.CrID.Valid && == crID    → changed=false 幂等返回
  2) LockCrForCrBind(workspace, crID) → CR_NOT_FOUND
       cr.ShellIssueID.Valid && != run.IssueID → CR_ISSUE_CONFLICT
  3) BindPromotionRunIfNull(run.cr_id = crID)      // CAS：WHERE cr_id IS NULL
     BindCrShellIssueIfNull(cr.shell_issue_id = run.issue_id)   // 既有查询复用
     MarkPipelineNodePassed(run, node_id='...0011...0001')      // 首节点 seq1 running→passed
     CreateActivity(action='promotion_run_bound')               // 同事务审计
  commit；changed 时 publishCRUpdated（既有 cr:updated）
```

**与 `gate_projection` 的协作语义（不改投影代码）**：

- **注册完成前**（run 未绑定）：首节点 `status='running'` = 「注册意图在途」。投影对无 `cr_id` 的 run 无写入（`findOrCreateRun` 按 `cr_id` 查，查不到也不新建——只有 cr 状态事件才触发投影）。
- **绑定时**：`cr_id` 置 CR-ID + 首节点置 `passed`（注册事实落账）——同一事务，与 `cr.shell_issue_id`/审计原子。
- **绑定后**：CR 进入 `requirement-reviewing` 的状态事件 → `projectGateTransition` → `findOrCreateRun(ws, crID, 'requirement-authoring')` **命中绑定后的同一行**（status='running'）→ 复用，不新建；`upsertNodeRunning` 只写审批门节点（seq5），不触碰 seq1；review 事件 `applyReview` 只写 seq4 节点行。→ 满足 AC-13「pipeline_run 行数不增」。
- **护栏**：若 knowledge-base 违约在绑定前推进 `requirement-reviewing`，投影会按 `cr_id` 新建一条 `issue_id=NULL` 的 run（投影无权猜测 Issue）。该违约由 AC-13 在 knowledge-base 侧硬阻止（绑定失败即注册技术失败，不得推进）；SDD 将「绑定完成前不得推进 requirement-reviewing」列为本设计的不变量（§9 scope_in）。
- **违约后果与恢复路径（suggestion-1 已处理）**：投影新建行 `cr_id=CR-ID、pipeline_id='requirement-authoring'、status='running'`（`pipelineForStatus` 把 requirement-reviewing 映射到 requirement-authoring）会先占用 456 部分唯一索引 `(workspace_id,pipeline_id,cr_id)` 的槽位；此时 506 不冲突（506 谓词要求 `issue_id` 非空，投影行 `issue_id IS NULL`），但后续绑定的 `UPDATE pipeline_run SET cr_id=CR-ID WHERE id=<预建 run>` 将撞 456 唯一约束（SQLSTATE 23505）→ 绑定事务整体回滚，端点返回 500 `CR_BIND_FAILED`。恢复路径：按 `pipeline_id='requirement-authoring' AND cr_id=<CR-ID> AND issue_id IS NULL` 定位投影新建行，人工确认后删除（该行无任何绑定/Issue 语义挂靠），再重试绑定（CAS 幂等，重试安全）；绑定成功后再推进 CR 状态。推演依据见 §12 #31（456 谓词）与 §12 #4（pipelineForStatus 映射）。
- 未消费的预建 run：保持 `cr_id=NULL, status='running'`，不影响任何既有路径；过期清理不在本 CR（PRD 范围排除）。

### 4.6 默认标题/描述生成（FR-4/AC-3）

- `title` 缺省：`Discussion promotion — {project.name} {YYYY-MM-DD HH:mm}`（服务端生成；project 名从 `GetProjectInWorkspace` 行读取）。
- `description` 缺省：来源消息摘要（每条 `作者: 摘要（≤120 rune）`，最多 5 条，超出加 `…`；复用 `chatMessageAuthorDisplayName` 与既有 merge-forward 摘要思路），并附来源标注块（session/消息/附件计数）。
- 两者只在创建分支生效；查重命中/重放不覆盖（FR-6）。

---

## 5. 技术选型与替代方案

### D-1 promotion 单事务 reservation+finalize（vs merge-forward 的 reservation/kernel/finalize 三事务）

- Context：merge-forward 用三事务是因为 kernel（sendProjectChatCore）自带事务不可包裹；promotion 的全部副作用（Issue、context_refs、幂等记录、run 行）都在本服务事务内，PRD/NFR-4 明确要求同一事务。
- Decision：promotion 的 reservation、副作用、finalize 全部在一个事务。
- Consequences：崩溃窗口语义比 merge-forward 更干净（无「已提交未 finalize」窗口）；同 key 重试走「同 fingerprint + NULL body 接管」分支，不需要 `DeleteChatIdempotencyByKey` 释放路径（该查询仍被 merge-forward 使用，零改动）。

### D-2 查重键存储与匹配（vs 逐元素全等比较 / 新建 promotion 表）

- Alternatives：A) SQL 逐元素比较 `jsonb_array_elements` 全等——O(n) 且不可索引；B) 新建 `discussion_promotion` 表——PRD FR-12 默认禁止。
- Decision：条目内置 `dedupe_key` + `@>` 包含匹配 + GIN 索引（507）。`dedupe_key` 是 PRD「条目至少含」集合之外的服务端附加字段，不改变 PRD 语义（FR-6 查重键 = 规范化来源集合的摘要形式）。
- Consequences：查重与审计同源（条目即审计）；`@>` 语义对并发键一致（摘要确定性）；代价是一条 GIN 索引（`issue` 表宽 JSONB，写入成本可接受，见 §7）。

### D-3 绑定通道 = 服务端端点 + `multica cr` 薄命令（vs crctl 内嵌 Multica 调用）

- Alternatives：A) crctl register 直接写 Multica DB——跨仓越权，违背 authority 拆分；B) requirement-register 自行拼 HTTP——失去同族审计与错误闭包。
- Decision：`POST /api/crs/{crID}/bind-promotion-run`（task-token）+ `multica cr bind-promotion-run` 薄命令，完全复刻 bind-current-task 族（handler 零业务判断、服务端派生身份、CAS 幂等、activity_log 审计）。
- Consequences：knowledge-base 侧只有一条 shell 调用增量；错误码固定可重试；绑定审计在 Multica 侧可查。

### D-4 独立 promotion 项目级锁前缀（vs 复用 discussion-session 锁）

- Context：send/GET/配置路径共用 `project-discussion-session|ws|project`；promotion 只读 session 行、不写，与发送事务无共享行冲突。
- Decision：新锁键 `project-discussion-promotion|ws|project`（同一 `LockIssueDuplicateKey` 原语，hashtextextended）。同项目 promotions 互斥（收敛到一次创建）；不把 promotion 与消息发送串行化。
- Consequences：并发窗口仅限同项目 promotion（这正是需要串行化的集合）；锁键表在 §7 固化，禁止重排。

### D-5 首节点完成信号由绑定事务置 `passed`（vs 投影自动完成）

- Alternatives：A) 投影在首次 requirement-authoring 事件时补写 seq1——投影写节点状态越界（投影只写门/评审节点，且绑定未发生前投影根本找不到该 run）；B) 节点永留 running——状态失真。
- Decision：绑定事务置 `passed`（§4.5）。
- Consequences：预建节点生命周期 = 「running（在途）→ passed（绑定）」，与 run 行 `cr_id` 赋值同事务原子；投影零改动。

### D-6 步骤 4 的「Issue 创建权限」口径 = 成员 + 既有容量门禁，映射 403

- Context：PRD FR-8 步骤 4 要求「沿用现有 Issue 权限口径，不新造权限模型」；现状 = 所有成员可创建 Issue，唯一硬门禁是 `ResolveIssueCountPolicy`/`CheckIssueCreateCapacity`/`AllocateIssueNumber`（`issue_limit.go`，超限现有路径映射 HTTP 402 `issue_limit_reached`）。
- Decision：promotion 前置 `CheckIssueCreateCapacity`（预检）+ 事务内 `AllocateIssueNumber`（权威）双查；失败统一映射 PRD 错误闭包的 403 `forbidden_promotion`（PRD 闭包表无 402，属 PRD 明示映射）。
- Consequences：不新造权限模型（AC-6 可测：limit 夹具 → 403）；与普通 CreateIssue 的 402 差异属端点级映射选择，在错误闭包表已固定，reviewer 可按 PRD 验收。

### D-7 创建内核提取 `createInTx`（vs 另开 Issue 写入路径 / 回调钩子）

- Context：FR-2 禁止另建 Issue 写入路径；NFR-4 要求同一事务。
- Decision：把 `IssueService.Create` 的事务体机械提取为 `createInTx(ctx, qtx, p, opts)`；`Create` 保持原签名行为（Begin→createInTx→Commit→事件）；`PromoteDiscussion` 在同一事务内调用 `createInTx`，并通过 `IssueCreateParams` 两个新增可选字段（`ContextRefs json.RawMessage`、`PromotionRun *PromotionRunPlan`）注入 promotion 专属副作用。run id 在 Go 侧预生成（`dbid.NewV7()`），故条目可在创建前携带 `pipeline_run_id`。
- Consequences：唯一 Issue 写入路径不变；`IssueService.Create` 的既有调用方与测试全部不变（zero_diff 条目）；新字段零值时行为与今天逐字节一致。

### D-8 506 部分唯一索引覆盖绑定前后两阶段（suggestion-1 已处理）

- Context：456 索引只覆盖 `cr_id IS NOT NULL`；预建 run 在 `cr_id IS NULL` 阶段无唯一性保障；promotion 识别键查询没有匹配索引。
- Decision：§2.5 的 506 索引（`workspace_id, issue_id` + pipeline/status 谓词）同时覆盖绑定前后同一行，并作为识别键查询索引。
- Consequences：跨项目/跨 Issue 互不冲突；普通注册 run（issue_id NULL）不受影响；projection 新建 run（issue_id NULL）不冲突。

---

## 6. FR 到技术实现映射与 AC 级输出合同

### 6.1 FR 映射

| FR | 技术方案条目 |
|---|---|
| FR-1 只有显式升级才创建工作 Issue | 无任何懒创建调用改动；唯一新增 Issue 写入是 `PromoteDiscussion` 的创建分支（经 `createInTx`）；Discussion GET/发送/协办路径零改动（AC-1 以既有测试 + 新增断言覆盖） |
| FR-2 升级入口契约 | §3.1 端点 + `promotion.go` handler + `router.go` 注册；Issue 创建复用 `createInTx`（D-7），无第二写入路径 |
| FR-3 来源选择校验 | handler 形状校验（UUID 数组、去重、双空、标题/描述边界）+ 步骤 5/6 归属校验（`GetChatMessageInWorkspace`、`ListAttachmentsForPromotion`）；`session_id` 必须等于 `GetActiveProjectSharedSession` 结果 |
| FR-4 创建 Issue 并写入来源引用 | §2.1 条目 + `AppendIssueContextRefs`（创建分支同事务）；`pipeline_run_id` 回写见 §4.3；默认标题/描述 §4.6 |
| FR-5 原消息附件保持原归属 | promotion 事务对 `chat_message`/`attachment`/`chat_session` **零 UPDATE/DELETE/INSERT**（唯一读）；AC-4 以升级前后行全等断言 |
| FR-6 同源唯一 | `dedupe_key` + §4.2 查询 + 项目级锁串行；`title`/`description` 只在创建分支生效 |
| FR-7 幂等键 | `promotionFingerprint`（§4.1）+ `discussion_promotion` scope（505）+ reservation/replay/takeover/409 四分支（§4.3 步骤 9） |
| FR-8 权限边界 | 固定顺序 1–6 + 事务内成员复核（§4.3/§4.4）；403 口径 = CR-B 项目路径成员门禁；步骤 4 = D-6 |
| FR-9 可回溯 | §3.4 `context_refs` 暴露 + 前端「来自 Discussion」入口（跳转 DiscussionPane 并定位 session） |
| FR-10 升级为 CR | §2.3/§2.4 预建 run + 同事务 + 502 闭包 + 唯一 run 语义（506）+ 不写 CR 账本（Multica 零 `_backlog.yml`/`cr.md` 写入路径，AC-8 grep 断言）+ AC-13 消费契约（§4.5/§3.2/§3.3） |
| FR-11 前端交互 | §3.4 + discussion-pane 多选/两入口/结果链接/失败保留选择（复用 merge-forward 多选状态与错误分支模式） |
| FR-12 不新增表 | 无 `discussion_promotion` 表（迁移仅 CHECK 扩展 + 2 索引）；AC-10 断言 `server/migrations/` 无该命名迁移 |
| FR-13 可区分错误与零残留 | §4.4 错误闭包表逐条实现 + 前端按表恢复动作 |

### 6.2 AC 级输出合同（每项：设计落点 / 可观测结果 / 可达性）

```text
AC-1
设计落点：promotion 是唯一新增 Issue 写入路径；Discussion GET/send/协办/merge-forward 代码零改动
可观测结果：打开 Discussion、发送、附件、协办后 issue 表行数不变（既有 origin 排除查询 + 新增断言）；promotion 201 后行数 +1
可达性：merge-forward 的 issue 写入是 Team Agent 容器（origin_type='project_chat'），与 promotion 目标 Issue 不重叠；断言按 workspace+origin 过滤

AC-2
设计落点：handler 形状校验器 + 步骤 5/6 归属校验
可观测结果：只选消息 / 只选附件 / 混合 → 201；空选择、重复 UUID、草稿附件（chat_message_id IS NULL）、他 session 消息 → 400 invalid_promotion_selection；非法 JSON → invalid_request_body；projectId 非 UUID → invalid_project_id；session_id 非 UUID → invalid_promotion_selection；标题/描述超限 → 各自 400；全部零写入（issue/context_refs/chat_idempotency 行数不变）
可达性：校验在事务外、任何写之前完成（§4.3 固定顺序），夹具可逐类注入

AC-3
设计落点：§2.1 条目构建（AppendIssueContextRefs）+ §4.6 默认标题/描述
可观测结果：context_refs 含 kind/session_id/排序去重数组/promoted_by/promoted_at/dedupe_key；缺省 title 含项目名与时间、description 含摘要
可达性：创建分支与条目写入同一事务（AppendIssueContextRefs 失败 → 整体回滚）；条目内容由纯函数构建，单测覆盖排序去重

AC-4
设计落点：FR-5 零写不变量
可观测结果：升级前后 chat_message 行数/内容、attachment.chat_session_id/chat_message_id 全等；Discussion 消息流渲染不变（既有组件测试）
可达性：promotion 事务内无任何针对 chat_* 表的写语句（结构测试 grep 断言：promotion.sql/service 不出现 UPDATE/DELETE chat_message|attachment|chat_session）

AC-5
设计落点：§4.1 摘要 + §4.3 四分支 + 项目级锁
可观测结果：同源两次 → 第二次 created=false 同 issue_id；同 key 同指纹 → 回放 created=false；同 key 异指纹（含先普通后升级）→ 409 零写入；换新 key upgrade → 同 Issue + 至多补建一条 run（run_id 一致）；缺 key/空 key/超长 key → 400 三码；并发同源（goroutine 夹具）→ 一个 Issue
可达性：reservation 唯一冲突路径有 pgx.ErrNoRows 分支；并发夹具走真实 DB（testutil），锁串行可观测（第二个事务返回 created=false）

AC-6
设计落点：§4.3 固定顺序 1–6 + 事务内成员复核
可观测结果：非成员/被移出 → 403 forbidden_promotion（不泄漏 session 存在性：顺序先于 session 解析）；无创建权限（limit 夹具）→ 403；session 不存在/跨项目/非 project_shared/归档 → 404 chat_session_not_found；project 不存在 → 404 project_not_found；全部零写入
可达性：固定顺序无分支依赖后续步骤结果（同输入唯一响应）；归档 session 经 GetActiveProjectSharedSession（status='active' 谓词）自然 404

AC-7
设计落点：§3.4 IssueResponse.context_refs + 前端来源入口
可观测结果：GET issue 响应可解析 session/message/attachment 引用；Issue 详情页展示「来自 Discussion」入口并可跳回 Discussion
可达性：context_refs 在 detail 响应透出（issueToResponse 解析 JSONB）；前端 schema fallback [] 保证旧后端不炸（兼容规则）

AC-8
设计落点：§2.3/§4.3 创建分支 + 502 闭包 + 506 唯一索引
可观测结果：upgrade 成功后同事务出现 pipeline_run（cr_id NULL、issue_id、started_by、inputs/execution_context）+ 首节点 + 无 agent_task_queue 行；响应 run_id；同 key 重放同 run_id；同源新 key 第二次不新建（补建一次）；注入夹具失败 → 502 pipeline_run_create_failed 且 issue/context_refs/chat_idempotency/pipeline_run/pipeline_node_run 零残留，原 key 重试成功且不重复；Multica 无 KB 账本写入调用（grep 零命中）
可达性：run 行与节点行与 Issue 同一事务（createInTx 内注入）；506 索引使「并发补建」收敛为唯一冲突重读；失败注入点 = CreatePipelineNodeRun 返回错误夹具

AC-9
设计落点：discussion-pane.tsx 多选与两入口 + 结果/失败状态
可观测结果：可选择消息与附件并触发「转为工作 Issue」「升级为 CR」；未配置 Coordinator 的 Discussion 同样可用（promotion 不依赖 Coordinator，FR-11）；成功后 Issue 链接可见、Discussion 内容不变；失败保留选择可重试
可达性：入口渲染不依赖 coordinator_agent_id 非空；成功回调只导航/展示，不重载 Discussion 流

AC-10
设计落点：迁移 505/506/507（无新表）
可观测结果：server/migrations/ 无 discussion_promotion 命名迁移；无 discussion_promotion 表（测试夹具查询 pg_catalog）
可达性：FR-12 默认路径成立（§2.5/§4.2 验证 context_refs+锁+幂等满足需求），无需走 FR-12 例外路径

AC-11
设计落点：§4.4 逐类映射 + 事务回滚
可观测结果：400/403/404/409/500/502 代表夹具各自零残留；错误体 code 与状态一一对应；500/502 后原 key 重试成功且 Issue/run 数不增；前端按错误类型保留选择或提示重试
可达性：所有写发生在单一事务；错误路径在 commit 前返回（deferred Rollback）；重试走同 fingerprint 重放/接管分支

AC-12
设计落点：locales 四语 + parity.test.ts + 兼容零改动
可观测结果：新增文案 en/ja/ko/zh-Hans 对称，parity 全绿；旧 project_discussion 只读回放不回归；CR-B Discussion GET/发送测试全绿
可达性：只新增 UI key，不改既有 key 与语义；旧容器路径代码零改动

AC-13（跨仓）
设计落点：§3.2 端点 + §3.3 CLI + tools requirement-register SKILL 绑定步骤 + §4.5 投影协作
可观测结果：requirement-register 按 issue_id+pipeline_id 定位 cr_id IS NULL、status=running 的 run 并绑定新 CR-ID（同一行复用；绑定幂等、仅一次——二次绑定异 CR → 409 RUN_CR_CONFLICT）；绑定后 CR 进入 requirement-reviewing 时投影复用同一 run（pipeline_run 行数不增）；绑定失败 → 注册技术失败、registration_key 幂等重试安全；普通注册不定位不绑定
可达性：定位键有 506 索引支撑；绑定 CAS 在锁内旧值判定（同 bind-current-task 模式）；tools 侧集成测试 + multica 侧投影断言（cr 状态事件夹具：绑定后注入 requirement-reviewing 事件 → 投影 findOrCreateRun 命中同一行）
```

### 6.3 AC 反查结论

逐条从 AC 反查正文：AC-8 的「至多补建一次」依赖 §4.3 并发推演（补建与绑定不可交错）+ 506 唯一索引兜底；AC-13 的「行数不增」依赖 §4.5 投影按 `cr_id` 命中的既有逻辑（gate_projection.go `findOrCreateRun`）。权限、状态、空值、过滤与事件顺序均不与 PRD 明文冲突；未发现不可达目标场景。

---

## 7. 安全与性能考量

### 7.1 安全控制点

- 固定判定顺序防泄漏：成员门禁先于 session 解析（非成员拿不到 session 存在性，与 CR-B 口径一致）。
- `context_refs` 只写服务端生成的规范化条目（NFR-5）；请求体不含任何可注入 `context_refs` 字段。
- 绑定端点 task-token 强制（401 fail-closed）；run/CR 全部按 token workspace 谓词校验（跨租户 404 而非存在性泄漏）。
- 事务内鉴权复核：promotion 在锁内、首次写入前复核 `GetMemberByUserAndWorkspace`；绑定端点的 run 行谓词自带 workspace（tenant 不变量 SQL 层保证，ARCHITECTURE.md 硬不变量 1）。
- 摘要算法无歧义：小写 UUID 规范化杜绝大小写变体绕过指纹/查重；`dedupe_key` 与 `fingerprint` 分离杜绝「先普通升级再同 key 升级」绕过（指纹含 `upgrade_to_cr` → 必 409，PRD 明示）。
- `writeErrorCode` 固定 `{code, error}` 形状（无内网细节泄漏）。

### 7.2 性能

- 锁：`LockIssueDuplicateKey`（hashtextextended advisory xact lock）作用域为单项目；promotion 是低频用户动作，锁持有 = 单事务时长；与 Discussion 发送锁前缀分离（D-4）不互相排队。
- 索引：506 支撑识别键点查（workspace_id+issue_id 前缀）；507 GIN `jsonb_path_ops` 支撑 `@>` 查重（`context_refs` 每行条目数通常为个位数，写入放大可接受）。507 与既有 `issue_properties_gin` 模式一致（并发建索引 + cleanup 登记）。
- 查询：查重/归属校验均为 PK/索引点查 + `= ANY(uuid[])`；消息摘要构建最多 5 条截断（默认描述生成 O(选数) 封顶）。
- 重放路径零业务查询（直接解 `response_body`），省去重放时的归属校验。

### 7.3 边界条件

- 消息/附件上限：PRD 未设上限；实施沿用 merge-forward 的 50 条 cap 作为防御（`mergeForwardMaxComments` 同值新常量 `promotionMaxItems=50`，超限 400 `invalid_promotion_selection`）——PRD 未禁止、属防御性边界，记入 scope_in。
- `context_refs` 解析失败：detail 响应降级空数组 + 日志（不 500），符合 API 兼容规则；服务端写侧从不产生不可解析内容。
- 旧 `project_discussion` 容器 Issue：promotion 只面向 shared session（FR-3 session 校验），旧容器不受影响。
- 空 `message_ids` + 空 `attachment_ids` → 400（FR-3）。
- `upgrade_to_cr` 与 Coordinator 配置无关：无 Coordinator 的项目 session 存在（InsertProjectSharedSession 允许 `agent_id=NULL`），promotion 照常。

---

## 8. Prompt 采纳影响

**结论：本节不适用（可省略），评审按省略处理。**

核验：本 CR 的 diff 不触及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支（crctl register/advance 等命令面零变更；binding 走 `multica cr bind-promotion-run` 薄命令与 HTTP 端点），也不触及 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（git 白名单零变更）。因此无「应改为调用新增子命令的 skill 清单」需要登记。requirement-register SKILL.md 的修改是**新增**调用步骤（`multica cr bind-promotion-run`），不是把 crctl 已接管的事改回手工操作，不构成 prompt 采纳缺口。

---

## 9. 批准范围（契约）

### scope_in（本 CR 必须交付）

- multica：`POST /api/projects/{projectId}/discussion/promote` 全链路（handler/service/sqlc/错误闭包/幂等/查重/预建 run）；`POST /api/crs/{crID}/bind-promotion-run` + `multica cr bind-promotion-run` CLI；迁移 505/506/507（含 down、concurrentIndexCleanups/concurrentDownIndexCleanups 登记）；`IssueResponse.context_refs` 暴露；前端 client/schemas/discussion-pane/Issue 详情来源入口 + 四语文案 + parity；FR-1..FR-13 对应测试（AC-1..AC-12）。
- tools：`skills/requirement/requirement-register/SKILL.md` promotion 上下文（可选输入：issue_id+run_id，缺失按普通注册）与绑定步骤（`crctl register` 成功后 `multica cr bind-promotion-run`；失败=注册技术失败、`registration_key` 幂等重试、绑定完成前不得推进 requirement-reviewing）；tools 侧注册集成测试（AC-13）。
- knowledge-base：本 sdd.md 落盘与 `_context.md` 导航缓存刷新（随本 CR 工作流提交）。

### scope_out（明确排除）

- 自动升级（任何定时/事件驱动）；原消息/附件移动删除复制；Multica 内 CR 注册/状态机/`_backlog.yml` 写入；历史 `project_discussion` comment 升级；Discussion 多主题/多 Agent 参与者模型与 `discussion_participant` 表；`discussion_promotion` 表（FR-12 例外路径未触发）；`agent_task_queue` 新列；Team Agent/Private Ask 内核改动；发送框重构；mobile；未消费预建 run 的过期/清理策略；把 `/compact` 当普通消息。
- `crctl.mjs`、`controlled-shell/rules.json`、`gate_projection.go`、`crsync.go` 的任何改动（suggestion-3 以「不改投影、契约协作」处理）。

### zero_diff（不得改动的调用点/签名/行为）

- `IssueService.Create` 对既有调用方的公开行为与签名（内部提取 `createInTx` 后逐字节等价；新增的 `IssueCreateParams.ContextRefs`/`PromotionRun` 零值下无任何行为变化）。
- `sendProjectChatCore`、`MergeForwardDiscussion`（含 message/comment 双臂与 idempotency 三事务协议）、`EnsureProjectDiscussionSession`/`EnsureProjectDiscussionIssue`、`GetProjectDiscussion`、`CreateIssue` HTTP 行为。
- `chat_idempotency` 既有两个 scope 的记录语义与 24h 清理；`idempotency.sql` 四个既有查询的签名。
- 456/457 索引与 451 表结构；`findOrCreateRun`/`upsertNodeRunning`/`markNodePassed`/`applyReview` 投影 SQL 与语义。
- `bind-current-task` 端点/CLI/服务行为（新端点同族但独立，不触碰其分支）。
- `LockIssueDuplicateKey` 原语与既有锁键字符串（新前缀独立新增）。

### follow_up（发现但留给后续 CR）

- 未消费 promotion 预建 run 的过期/清理/对账策略（含 cr_issue 绑定后 run 状态与 Issue 关闭的联动）。
- promotion 条目在 Issue 编辑/删除路径上的保留策略（Issue 删除时 context_refs 随行删除，审计靠历史事件——如需独立审计表，另开 CR）。
- `upgrade_to_cr` 后 requirement 注册入口的一键引导（前端从升级结果直达注册流程的深度集成）。
- promotion 选择上限的正式产品定义（本期防御性 50 条 cap）。

---

## 10. SDD-CLOSE 关闭记录（PRD 延后项逐项关闭）

- **SDD-CLOSE-01 `execution_context` 字段形状（PRD：「字段形状由 SDD 定，必须机器可读且幂等可重放」）**：已关闭 → §2.4。生产（§4.3 步骤 10）、存储（`pipeline_run.execution_context` JSONB）、传输（行内 JSON，无独立传输）、消费（§3.2 端点不读它；requirement-register 读取 promotion 上下文来自升级响应/Issue 条目而非解析 execution_context——消费路径为「可选输入」，兼容降级层 = 缺失时普通注册）逐层判定，关闭成立。
- **SDD-CLOSE-02 绑定端点与鉴权（PRD：「端点与鉴权由 SDD 设计」）**：已关闭 → §3.2/§3.3（task-token 同族、错误闭包、幂等/CAS、CLI）。生产（服务端派生身份）、传输（HTTP JSON）、消费（multica CLI → requirement-register）、兼容降级（任务无 token 环境 → 401，注册按技术失败停止，不降级直写）逐层覆盖。
- **SDD-CLOSE-03 首节点注册完成前的状态语义（suggestion-3）**：已关闭 → §4.5（running=在途 / 绑定置 passed / 投影复用不新建 / 违约护栏）。
- **SDD-CLOSE-04 默认标题/描述（FR-4：「未提供时服务端生成默认值」）**：已关闭 → §4.6。
- **SDD-CLOSE-05 事件通知提交后发出（FR-10/NFR-4）**：已关闭 → §4.3（commit 后 publishIssueCreated/captureCreatedAnalytics；失败不回滚已提交数据；升级为 CR 不新增事件类型）。
- **SDD-CLOSE-06 `context_refs` 响应暴露（FR-9/AC-7）**：已关闭 → §3.4（Go additive 字段 + TS schema fallback + malformed 测试）。
- **SDD-CLOSE-07 AC-13 knowledge-base 消费流程**：已关闭 → §4.5/§3.2/§3.3 + tools SKILL 增量（§9 scope_in）。
- **SDD-CLOSE-08 补建 run 与 `pipeline_run_id` 回写（FR-10 同源不同 key）**：已关闭 → §4.3 查重分支（`SetIssueContextRefPipelineRun` 按 `dedupe_key` 定位条目合并字段，同事务）+ 506 冲突重读。
- **SDD-CLOSE-09 错误闭包逐类实现点**：已关闭 → §4.4 表。

无未关闭项；`review-tech-design` 无需标记待办。

---

## 11. 第 3 轮需求评审 3 条 suggestions 的处理

| # | suggestion | 处置 | 落点 |
|---|---|---|---|
| 1 | 预建 run 识别键的索引设计（`idx_pipeline_run_workspace_status` 弱覆盖） | **已处理**：新增 506 部分唯一索引 `idx_pipeline_run_promotion_active_issue ON pipeline_run(workspace_id, issue_id) WHERE pipeline_id='requirement-authoring' AND status IN ('running','waiting_approval')`，同时承担「识别键点查索引」与「同一 Issue 至多一条非终态 run（绑定前后两阶段）」双重职责（D-8） | §2.5、§4.3、D-8 |
| 2 | AC-13 绑定端点沿用 bind-current-task 同族鉴权口径，并明确二次绑定的固定冲突响应 | **已处理**：绑定端点仅接受 task token（401 `TASK_CONTEXT_REQUIRED`，与 bind-current-task 完全同族）；二次绑定固定响应 = 绑定到不同 CR → 409 `RUN_CR_CONFLICT`；同 CR 重放 → 200 `changed=false` 幂等（CAS 锁内旧值判定，同 AC-B3 模式） | §3.2、§4.5 |
| 3 | 首节点 `pipeline_node_run` 在 CR 注册完成前的状态推进语义与 gate_projection 协作 | **已处理**：预建窗口内首节点 `status='running'`=「注册意图在途」；绑定事务同事务置 `passed`（投影不写 skill 节点，故完成信号由绑定端承担）；绑定后投影 `findOrCreateRun` 按 `cr_id` 命中同一行复用、`upsertNodeRunning`/`applyReview` 只写 seq5/seq4 节点不触碰 seq1；KB 侧「绑定完成前不得推进 requirement-reviewing」列为硬不变量，违约路径与护栏在 §4.5 明示 | §4.5、D-5、§9 |

### 11.1 第 1 轮技术评审 3 条 suggestions 的处理（本次回修）

| # | suggestion | 处置 | 落点 |
|---|---|---|---|
| 1 | §4.5 违约护栏补明后果（投影 run 占用 456 槽位 → 绑定 23505 冲突 500 `CR_BIND_FAILED`）与恢复路径 | **已处理**：§4.5 新增「违约后果与恢复路径」条目（456 谓词 + pipelineForStatus 映射推演；恢复 = 定位 `issue_id IS NULL` 投影行人工确认删除后幂等重试） | §4.5、§12 #4/#31 |
| 2 | §3.2 错误表 401 行实际错误体 `{"error":"TASK_CONTEXT_REQUIRED"}`（bind-current-task 同族），与 promotion `{code,error}` 不同族 | **已处理**：§3.2 表后新增错误体形状注记（全表 `{"error":...}` 同族，不经 writeErrorCode；测试按固定形状断言） | §3.2、§12 #15/#16 |
| 3 | `ArchitectureCoreRegistryJSON` 与 `CreateActivity` 纳入清单或明确归属 | **已处理**：分别并入 §12 #10（gate_nodes_gen.go 符号）与 §12 #29（activity.sql 独立条目） | §12 #10/#29 |

---

## 12. 既有实现依赖清单（按正文首次出现顺序）

> v1.1（第 1 轮 review-tech-design 回修）：8 项漏列事实按正文首现顺序补入并全量重排为 35 项；#13 拆分为 handler/service 与 db queries 两条（现 #16/#17）；suggestion-3 的 `ArchitectureCoreRegistryJSON`/`CreateActivity` 分别并入 #10/#29；`rules.json`、`idx_pipeline_run_workspace_status`、`requirement-authoring.pipeline.json` 等正文事实一并锚定。

```text
1. repo: multica
   relative path: server/internal/service/issue.go
   stable symbol/对象: IssueService.Create / IssueCreateParams.AllowDuplicate / IssueCreateOpts.BroadcastPayload / publishIssueCreated / captureCreatedAnalytics / issueguard.LockAndFindActiveDuplicate
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: createInTx 提取的源（§1.1 唯一 Issue 写入路径的既有内核）；事件发布复用；promotion 以 AllowDuplicate=true 关闭标题查重（查重权威归 dedupe_key）

2. repo: tools
   relative path: skills/requirement/requirement-register/SKILL.md
   stable symbol/对象: crctl register 深原语（registration_key 幂等、CAS_CONFLICT 重跑续跑语义）
   commit SHA: 49c46dd9d77c0e7a5efb519c1cf8485692774f26
   依赖结论: AC-13 在注册成功后追加绑定步骤（§1.1 模块边界）；深原语本身零改动

3. repo: multica
   relative path: server/cmd/multica/cmd_cr.go
   stable symbol/对象: crBindCurrentTaskCmd / newAPIClient / cli.PrintJSON/PrintTable
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: bind-promotion-run 薄命令复刻同族实现（§3.3）

4. repo: multica
   relative path: server/internal/governance/gate_projection.go
   stable symbol/对象: findOrCreateRun（按 (workspace_id, cr_id, pipeline_id) 查 status IN ('running','waiting_approval')，无则新建）/ upsertNodeRunning / markNodePassed / applyReview / pipelineForStatus（requirement-reviewing/requirement-approved → PipelineIDs.RequirementAuthoring）
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: AC-13「投影复用同一 run 不新建」成立的前提（绑定后按 cr_id 命中）；pipelineForStatus 映射是 §4.5 违约后果推演的依据；本 CR 不改投影

5. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: register 深原语入口（--registration-key/--target-spec-id 校验）
   commit SHA: 49c46dd9d77c0e7a5efb519c1cf8485692774f26
   依赖结论: 绑定不进入 crctl 命令面（走 multica CLI），本节仅证明「不改」的边界（§8）

6. repo: multica
   relative path: server/pkg/db/queries/idempotency.sql
   stable symbol/对象: InsertChatIdempotencyReservation / GetChatIdempotencyByKey / FinalizeChatIdempotency / DeleteChatIdempotencyByKey
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: promotion 幂等四分支直接复用（新 scope），不需要新幂等表或查询

7. repo: multica
   relative path: server/internal/service/chat_idempotency_cleanup.go（L17 func）+ server/pkg/db/queries/idempotency.sql（L42 SweepChatIdempotency :execrows；L46 DELETE FROM chat_idempotency WHERE created_at < $1）
   stable symbol/对象: SweepChatIdempotency(ctx, q, cutoff)（service）+ db SweepChatIdempotency
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: 24h 清理按 created_at 全 scope 清理（无 scope_type 谓词），505 新增 'discussion_promotion' 行自动纳入清理，无需新清理器（§2.2）

8. repo: multica
   relative path: server/migrations/501_chat_idempotency.up.sql / 502 / 503 / 504
   stable symbol/对象: chat_idempotency 表 + CHECK scope_type('discussion_message','merge_forward_messages') + PK + created_at 索引
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: 505 扩展 CHECK 枚举；PK 约束名 chat_idempotency_pkey 是 ON CONFLICT 仲裁目标，扩展不得改名

9. repo: multica
   relative path: server/migrations/451_aifirst_pipeline_runs.up.sql
   stable symbol/对象: pipeline_run（cr_id TEXT NULL、issue_id UUID SET NULL、inputs/execution_context JSONB、started_by NOT NULL、status CHECK）/ pipeline_node_run（UNIQUE(run_id,node_id,attempt)、kind CHECK）/ idx_pipeline_run_workspace_status（workspace_id, status）
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: 预建 run 行与首节点行完全落在既有 schema 内（§2.3），无 DDL 变更；idx_pipeline_run_workspace_status 即 suggestion-1 指涉的弱覆盖索引（无 issue_id 前缀），506 补齐识别键点查

10. repo: multica
    relative path: server/internal/governance/gate_nodes_gen.go
    stable symbol/对象: PipelineIDs.RequirementAuthoring（L15）/ ApprovalGateNodes["requirement"]（seq5）/ ReviewGateNodes["requirement"]（seq4）/ ArchitectureCoreRegistryJSON（L57，architecture-core registry 节点 id 空间常量，生成源声明于文件头）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 首节点 node_id 与门/评审节点 id 空间共存不冲突（seq 1/4/5 不同 id）；ArchitectureCoreRegistryJSON 证明同族 registry 常量维护该 id 空间（§2.3）

11. repo: tools
    relative path: pipeline-templates/requirement-authoring.pipeline.json
    stable symbol/对象: nodes[0].id = 00000000-0000-0000-0011-000000000001 / ref requirement-register / kind skill（seq=1 首节点）
    commit SHA: 49c46dd9d77c0e7a5efb519c1cf8485692774f26
    依赖结论: §2.3 首节点 node_id 的生成源（gate_nodes_gen.go 文件头声明生成源为 tools pipeline-templates），预建首节点与模板第 1 节点对齐

12. repo: multica
    relative path: server/cmd/migrate/main.go
    stable symbol/对象: concurrentIndexCleanups / concurrentDownIndexCleanups 登记表与总登记测试
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 506/507 必须登记，否则 `TestEveryConcurrentUpBuildHasCleanup` 类测试失败

13. repo: multica
    relative path: server/cmd/server/router.go
    stable symbol/对象: 项目路由树（GET /discussion、POST /chat/merge-forward 注册处）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: promotion 与 bind-promotion-run 路由注册位置

14. repo: multica
    relative path: server/pkg/publicapi/v1/foundation.go
    stable symbol/对象: HeaderIdempotencyKey / MaxIdempotencyBytes(255)
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 请求头常量与长度上限

15. repo: multica
    relative path: server/internal/handler/handler.go
    stable symbol/对象: writeErrorCode（{code,error}）/ writeError（{error}）/ writeJSON / parseUUIDOrBadRequest / parseUUIDSliceOrBadRequest / requireUserID / getWorkspaceMember
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: promotion 端点错误体（writeErrorCode）与解析/成员门禁辅助函数；writeError 是绑定端点 {error} 形状族（§3.2 形状注记）

16. repo: multica
    relative path: server/internal/handler/cr_bind.go + server/internal/service/task.go
    stable symbol/对象: HandleBindCurrentTask（X-Actor-Source=task_token 门禁，401 {"error":"TASK_CONTEXT_REQUIRED"}）/ BindCurrentTaskToCR / activity_log 审计模式 / publishCRUpdated
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 绑定端点/服务的同族模板（token 校验、CAS、冲突码、审计、刷新事件）；401 错误体形状与 bind-current-task 一致（§3.2 已注明）

17. repo: multica
    relative path: server/pkg/db/queries/agent.sql
    stable symbol/对象: LockCrForCrBind（L1128）/ BindCrShellIssueIfNull（L1146）/ LockAgentTaskForCrBind（L1100）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 绑定事务的 cr 行锁 CAS 与 shell_issue_id 复用的既有查询（§4.5 步骤 2/3），直接复用不新建

18. repo: multica
    relative path: server/internal/handler/issue.go
    stable symbol/对象: IssueResponse / issueToResponse / loadIssueForUser / GetIssue（L2225 起）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: context_refs 当前未透出（issueToResponse 无该字段），本 CR additive 暴露（§3.4）

19. repo: multica
    relative path: packages/views/projects/components/discussion-pane.tsx + packages/core/api/client.ts + packages/core/api/schemas.ts
    stable symbol/对象: DiscussionPane 多选/MergeForwardPreviewDialog 模式、mergeForwardDiscussion()（Idempotency-Key 客户端强制）、ProjectDiscussionSchema、parseWithFallback
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 前端入口复用既有面板与客户端模式；新 schema 走 parseWithFallback + malformed 测试

20. repo: multica
    relative path: server/internal/service/issue_limit.go
    stable symbol/对象: CheckIssueCreateCapacity（L67，只读预检）/ ResolveIssueCountPolicy（L34，policy 决议）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: D-6 步骤 4 预检口径依据（与事务内 AllocateIssueNumber 权威判定双查）；403 forbidden_promotion 映射的既有口径来源（普通 CreateIssue 映射 402 issue_limit_reached 是既有行为，promotion 按 PRD 闭包映射 403）

21. repo: multica
    relative path: server/internal/service/discussion_session.go
    stable symbol/对象: DiscussionSessionAdvisoryPrefix / chatSessionKindProjectShared / discussionIdempotencyScopeMessage / GetActiveProjectSharedSession 消费
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: session kind/active 判定口径与锁前缀命名风格；promotion 不占用 discussion-session 锁（D-4）

22. repo: multica
    relative path: server/pkg/db/queries/chat.sql
    stable symbol/对象: GetActiveProjectSharedSession（L1723，kind='project_shared' AND status='active' 唯一）/ GetChatMessageInWorkspace（L1748，workspace 谓词经 session JOIN）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: FR-3/FR-8 的 session 与消息归属校验查询，直接复用

23. repo: multica
    relative path: server/pkg/db/queries/attachment.sql
    stable symbol/对象: ListAttachmentsByChatMessage / BindDraftAttachmentsToChatMessage（attachment.chat_message_id 列语义）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 附件「已绑定 session 消息」判定（新增 promotion 专用 JOIN 查询，语义同 ListAttachmentsByChatMessage）

24. repo: multica
    relative path: server/pkg/db/queries/issue.sql
    stable symbol/对象: LockIssueDuplicateKey（pg_advisory_xact_lock(hashtextextended)）、CreateIssue、AllocateIssueNumber（issue_limit 服务）、FindActiveDuplicateIssue、CreateIssueWithOrigin
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 项目级锁原语、Issue 创建事务内核（D-7 提取自 Create）、AllowDuplicate 跳过标题查重、容量权威判定

25. repo: multica
    relative path: server/pkg/db/queries/member.sql
    stable symbol/对象: GetMemberByUserAndWorkspace（L15）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: §4.3 步骤 8 / §13.4 事务内鉴权复核查询（锁内、首次写入前，与并发撤销串行）

26. repo: multica
    relative path: server/internal/service/project_chat.go
    stable symbol/对象: projectChatSessionAdvisoryKey / LockIssueDuplicateKey 调用先例 / ErrIdempotencyKeyReused / mergeForwardMessageFingerprint
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 锁键先例与 409 语义先例（§4.3 步骤 9 idempotency_key_reused 同族）；promotion 使用新前缀但同原语（D-4）

27. repo: multica
    relative path: server/pkg/dbid/dbid.go
    stable symbol/对象: NewV7()（L51）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: runID Go 侧预生成，条目在创建前携带 pipeline_run_id（§4.3 步骤 10 / D-7）

28. repo: multica
    relative path: server/pkg/db/queries/project.sql
    stable symbol/对象: GetProjectInWorkspace（L8）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: §4.4 404 project_not_found 映射（ErrNoRows）与 §4.6 默认标题项目名读取（同一查询）

29. repo: multica
    relative path: server/pkg/db/queries/activity.sql
    stable symbol/对象: CreateActivity（L29）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: §4.5 绑定事务审计行（action='promotion_run_bound'）的既有写入查询

30. repo: multica
    relative path: server/internal/service/project_chat.go
    stable symbol/对象: chatMessageAuthorDisplayName（L739 调用 / L760 定义）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: §4.6 默认描述摘要的作者显示名复用，无需新实现

31. repo: multica
    relative path: server/migrations/456_pipeline_run_architecture_active_unique.up.sql
    stable symbol/对象: idx_pipeline_run_architecture_active_cr（(workspace_id,pipeline_id,cr_id) WHERE cr_id IS NOT NULL AND status IN ('running','waiting_approval')）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 绑定后（cr_id 非空）的防重复由 456 与投影 findOrCreateRun 双重保障；506 补齐 cr_id IS NULL 阶段（D-8）；§4.5 违约后果（456 槽位占用 → 绑定 23505 冲突）的推演依据

32. repo: multica
    relative path: server/migrations/192_issue_properties_gin_index.up.sql
    stable symbol/对象: idx_issue_properties_gin（ON issue USING GIN (properties jsonb_path_ops)）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 507（context_refs GIN jsonb_path_ops + 并发建索引单文件单语句 + cleanup 登记）与既有模式一致（§7.2）

33. repo: multica
    relative path: server/internal/handler/project_chat.go
    stable symbol/对象: MergeForwardDiscussion（message_ids 臂的成员门禁、Idempotency-Key 校验、选择校验、409 映射）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: promotion handler 的校验顺序与错误映射先例；mergeForwardMaxComments=50 作为防御 cap 同值（§7.3）

34. repo: multica
    relative path: server/pkg/db/queries/chat.sql
    stable symbol/对象: InsertProjectSharedSession（L1731）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: agent_id=NULL 时无 Coordinator 的 project_shared session 依然可建（481 起合法）——§7.3「promotion 与 Coordinator 配置无关」边界声明的依据

35. repo: tools
    relative path: skills/shared/controlled-shell/rules.json
    stable symbol/对象: protectedPaths（L28，deny 列表始于 L30；git 三元组白名单 + forbiddenFlags 的单一事实源）
    commit SHA: 49c46dd9d77c0e7a5efb519c1cf8485692774f26
    依赖结论: §8「不触及」判定与 §9 scope_out 边界的唯一事实源（本 CR 零变更）
```

无待核实依赖（以上 35 项均在 `78e14082`/`49c46dd` HEAD 上逐项核实；8 项补列、#16/#17 拆分与 3 条 suggestions 采纳项按第 1 轮评审 blocker/suggestions 完成）。

---

## 13. 数据/schema 变更与写路径鉴权完整性

### 13.1 回滚（down）与数据依赖语义

| 变更 | down | 数据依赖 / 部分状态语义 |
|---|---|---|
| 505 CHECK 扩展 | 单条 `ALTER TABLE ... DROP CONSTRAINT chat_idempotency_scope_type_check, ADD CONSTRAINT ... CHECK (scope_type IN ('discussion_message','merge_forward_messages'))` | 前置：表内无 `discussion_promotion` 行（该行 24h 清理器会在一个保留窗口内自然消失；down 时若仍存在，ALTER 验证失败即回滚安全，**不静默删数据**——执行者需先确认保留窗口已过或按审批清理） |
| 506 部分唯一索引 | `DROP INDEX CONCURRENTLY IF EXISTS idx_pipeline_run_promotion_active_issue`（登记 concurrentDownIndexCleanups 的 down 清理钩子） | 无数据依赖；down 后失去唯一性兜底但应用锁仍工作（降级语义明示） |
| 507 GIN 索引 | `DROP INDEX CONCURRENTLY IF EXISTS idx_issue_context_refs_gin` | 无数据依赖；down 后查重回全表扫描（正确性不变） |

### 13.2 无约束缺失窗口

- 505 用一条 `ALTER TABLE ... DROP CONSTRAINT ..., ADD CONSTRAINT ...` 原子完成（PG 对同一 ALTER 的多个 action 原子应用），不存在「CHECK 缺失」中间态。
- 506/507 是纯索引（非约束变更），应用锁 + 既有约束在索引构建期间持续生效；并发构建失败由 `concurrentIndexCleanups` 无效索引清理钩子兜底（MUL-5999/MUL-6288 机制，本 CR 登记即接入）。

### 13.3 DDL 规范

- 新关系不加外键（CLAUDE.md 硬规则）：`pipeline_run.cr_id` 绑定用应用校验（CR 行存在性经 `LockCrForCrBind`），`issue_id` 沿用 451 既有 `ON DELETE SET NULL`（不加新 FK）。
- 所有新索引单语句单文件 `CREATE INDEX CONCURRENTLY` + migrate 登记（§2.6）。
- 不新建表、不以内联方式创建约束绕过迁移（505 的 CHECK 重建是显式迁移 DDL，且实施时经 `pg_catalog` 校验约束名）。

### 13.4 写路径鉴权完整性

- **promotion**：固定顺序 1–6 全部零写入；事务内、首次写入前复核成员行（`GetMemberByUserAndWorkspace`）——与并发撤销串行（成员撤销路径持成员行锁，复核在 promotion 事务内读最新提交态）；容量门禁的权威判定（`AllocateIssueNumber`）在 Issue 行写入前、同一事务内。
- **bind-promotion-run**：task-token 在中间件验签（服务端戳记身份，客户端不可设）；run/CR 全部查询携带 token workspace 谓词；CAS 冲突检查与写入在锁内同一事务，任一失败整体回滚（含审计行，同 bind-current-task BLOCK-③ 模式）。
- 两者均无「先写后鉴权」路径；错误路径零残留由单事务保证（§4.3/§4.4）。

---

## 14. 测试设计

### 14.1 multica Go 测试（`server/internal/handler/*_test.go` + `server/internal/service/*_test.go`，testutil/dbfx 夹具）

- 纯函数：`promotionFingerprint`/`promotionDedupeKey`/形状校验器（大小写、乱序、重复、`upgrade_to_cr` 差异矩阵）。
- handler 契约：AC-2（选择矩阵）、AC-5（重放/409/查重/并发）、AC-6（权限顺序与零写入）、AC-8（同事务 run/节点、无 agent_task_queue、502 夹具零残留、原 key 重试）、AC-11（逐类错误夹具）。
- service：createInTx 提取后既有 `IssueService.Create` 测试全绿（zero_diff 回归）；查重命中补建与 506 冲突重读（唯一索引竞态夹具）。
- 绑定：`BindPromotionRunToCR` 全错误码矩阵（401/400/404/409×2/幂等重放/审计行）；投影协作集成（绑定后注入 requirement-reviewing/review 事件 → `pipeline_run` 行数不增、seq5/seq4 节点正常投影、seq1 保持 passed）。
- 迁移：505 后新 scope 可插入；约束名断言；506/507 的 cleanup 登记测试（既有 total-invariant 测试自动覆盖）。

### 14.2 前端测试

- `packages/core/api/schemas.ts`：`PromotionResultSchema` malformed-response 测试；`IssueSchema.context_refs` fallback。
- `packages/views/projects/components/discussion-pane.*.test.tsx`：多选、两入口、成功链接、失败保留选择（AC-9）。
- `packages/views/locales/parity.test.ts`：四语新 key 全绿（AC-12）。

### 14.3 tools 侧测试（AC-13）

- requirement-register 集成测试：promotion 上下文存在 → 注册成功后调用绑定端点（fake/mock `multica` CLI 或受控集成夹具）→ 断言绑定幂等与「绑定完成前不推进」；无 promotion 上下文 → 不调用绑定（行为不变）。

### 14.4 验证命令

```text
multica: cd server && go test ./internal/handler/ ./internal/service/ ./internal/governance/ ./cmd/migrate/ -count=1
前端: pnpm test --filter 相关包 + pnpm exec playwright test（讨论 pane 冒烟）
tools: 对应 SKILL 集成测试脚本
```

---

## 附：审查要点速览

1. promotion 唯一 Issue 写入路径 = `createInTx`（FR-2/NFR-4），无第二路径。
2. fingerprint 与 dedupe_key 是两个摘要，用途分离（FR-6/FR-7）。
3. 506 索引使「同一目标 Issue 至多一条 requirement-authoring 非终态 run」成为 DB 约束（绑定前后同一行）。
4. 绑定端点 = bind-current-task 同族（task-token/CAS/审计/固定冲突码），投影零改动即复用（AC-13）。
5. 迁移 505/506/507 全部满足并发索引单文件单语句 + 登记 + down 数据依赖语义。
6. 3 条 suggestions 全部「已处理」（§11），无未关闭的 PRD 延后项（§10）。
7. §12 既有实现依赖清单 v1.1 回修后 35 项，按正文首现顺序、全部绑定 repo/path/symbol/结论/commit SHA；第 1 轮技术评审 3 条 suggestions 亦全部「已处理」（§11.1）。
