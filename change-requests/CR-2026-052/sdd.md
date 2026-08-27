---
id: CR-2026-052-sdd
type: SDD
cr-ref: CR-2026-052
title: Multica 审批后自动续跑 + audit-drift 去重修复 技术设计
status: draft
created: 2026-08-27T01:47:00+08:00
updated: 2026-08-27T07:55:00+08:00
---

# 1. 架构概览

## 1.1 范围与仓归属

| 仓 | 角色 | 本 CR 改动 |
|---|---|---|
| multica（`server/` Go 服务端） | 代码仓 | FR-1 ~ FR-11：ACK 时点幂等唤醒 + 原子事务 + 两条 partial unique index + 回调签名扩展 |
| tools（`skills/shared/crctl/scripts/crctl.mjs`） | 代码仓 | FR-12：outbox `audit-drift` 去重比较语义修复（单点，不改事件 schema） |
| knowledge-base | 知识仓 | 仅本 SDD 与状态推进账本（经 crctl） |

两仓改动互不依赖、可独立上线：multica 侧唤醒能力不要求 tools 侧升级；tools 侧去重修复不要求 daemon/服务端配合（NFR-9）。

## 1.2 既有模块边界（只读复用，见 PRD §1.3）

- **crctl（tools）**：CR 状态机/门禁/账本的唯一写者，本 CR 除 FR-12 外零改动；
- **approval.go（multica governance）**：签名 grant 签发与 daemon 交付队列（`server/internal/governance/approval.go`），本 CR 只改 `HandleGrantsAck` 的 ACK 后处理与回调签名；
- **crevents.go（multica daemon）**：`crEventsLoop` 每 `HeartbeatInterval`（默认 15s，`server/internal/daemon/config.go:24`）拉取 pending grants → 写 `.crctl/grants/{CRID}-{Stage}.grant.json` → 批量 ACK（`server/internal/daemon/crevents.go:107-155`），本 CR **零改动**——ACK 失败时 grants 保持 pending、重投递幂等，天然满足 FR-5 重试；
- **agent_task_queue + TaskService**：任务执行唯一通道，续跑任务走同一条队列与事件广播（FR-11）。

## 1.3 新增/修改组件

```text
server/internal/governance/approval.go
  └─ HandleGrantsAck：单事务内「delivered_at + 续跑入队」编排（DD-3）
       ├─ sqlc 新查询（server/pkg/db/queries/approval.sql，新文件）
       │    AckApprovalGrants / GetCrShellIssueInWorkspaceForShare / CreateApprovalContinuationTask（
       │    status/fire_at 参数化）/ AppendApprovalContinuationEvidence /
       │    GetApprovalContinuationTaskByRecord / GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate
       ├─ 复用既有 workspace-scoped 查询 GetSquadInWorkspace / GetAgentInWorkspace 与既有锁查询
       │    LockSquadForAutopilotAssignment / GetAgentForUpdate；新增 2 条锁读查询（approval.sql 的
       │    cr 锁读 + issue.sql 的 issue 锁读）：LockIssueInWorkspaceForShare（FOR SHARE，权威链稳定，§4.2/DD-10）
       ├─ 回调拆双钩（§3.2/DD-5）：SetGrantAckHandler（预提交纯校验，保留 FR-10 onGrantAck 契约）/
       │    SetGrantAckCommittedHandler（提交后唤醒）
       └─ service.TaskService（新方法，FR-11 事件广播唯一通道）
            EnqueueApprovalContinuation(ctx, qtx, spec)   // 纯 DB 写入（事务内）
            NotifyContinuationTaskEnqueued(ctx, task)     // 提交后 = broadcastTaskEvent(EventTaskQueued)
                                                          // + NotifyTaskEnqueued（与 EnqueuePipelineTask 尾部一致，task.go:415-416）
server/migrations/
  ├─ 469_approval_continuation_record_active_unique.up/down.sql    // FR-4
  ├─ 470_approval_continuation_workspace_scope.up/down.sql         // TD-BL-10：任务行承载 authenticated workspace
  └─ 471_approval_continuation_workspace_cr_pending_unique.up/down.sql // FR-6：workspace-qualified 排队后继
server/cmd/server/router.go
  └─ NewApprovalServiceFromEnv(pool, queries, taskSvc) 依赖注入（两处调用点同步）
server/internal/governance/runner.go
  └─ ValidateGrantAck（纯校验，接 FR-10 onGrantAck）+ WakeGrant（接 committed hook，Reconcile 唤醒）适配 GrantAckEvent
skills/shared/crctl/scripts/crctl.mjs（tools）
  └─ emitOutboxEvent 内 comparable()：payload 比较剥离 detected_at（DD-6）
```

依赖方向（对照 multica `ARCHITECTURE.md` §4）：governance 消费 service 与 db 查询，service 不反向依赖 governance；无环。`server/pkg/db/generated` 为 sqlc 生成物，本 CR 改动 queries 后重跑 `sqlc generate`，禁止手改生成文件（ARCHITECTURE §5.5）。

## 1.4 关键流程（AC-1~AC-8 覆盖）

```text
人工审批（Web crctl-approve / --grant 签名）
  → approval_record 落库（既有）
  → daemon deliverGrants：写 .crctl/grants/{CR}-{Stage}.grant.json（既有，幂等）
  → POST /api/daemon/approvals/ack {ids}（既有端点，语义升级）
       HandleGrantsAck：
         BEGIN（pgx 原生事务）
           UPDATE approval_record SET delivered_at=now()
             WHERE … AND delivered_at IS NULL RETURNING id,cr_id,stage,decision,approver_user_id
           for each 返回行：
             resolveContinuationTarget（FR-7 fail-closed：锁链 cr→issue→squad→agent，§4.2）
             CreateApprovalContinuationTask（guarded INSERT；ON CONFLICT 输家幂等重读/合并，§4.3）
         （预提交）onGrantAck 每记录一次：纯校验、零副作用；error → 整批回滚 → 5xx（§3.2，FR-10 原名原契约）
         COMMIT
         （提交后）TaskService.NotifyContinuationTaskEnqueued 广播 EventTaskQueued（TD-SUG-1）
         （提交后）onGrantAckCommitted 每记录一次：真实唤醒（Reconcile），error → Error 日志不置 5xx（§3.2）
       → 2xx：全部记录的 delivered_at 与续跑任务已成对落地（或幂等命中/原子合并）
       → 5xx：仅预提交失败（tx 错误或 FR-10 onGrantAck handler error）→ 整批回滚，delivered_at 保持 NULL，
              daemon 15s 后重投递（FR-5）；提交后无 5xx 路径
  → 续跑任务 = agent_task_queue 一条普通任务（trigger_evidence_kind='approval_continuation'，
      is_leader_task=true——migration 127 的 squad 简报注入契约）
      归属 CR leader（cr-coordinator-agent），落点 shell issue
      上下文仅 {cr_id, stage, decision, approval_record_id}（FR-9，无状态机映射）：
        · context JSON = 机器可读证据（approvals[] 数组，审计/幂等键语义，不进 prompt，§2.4）
        · handoff_note = prompt 实际载体（claim→daemon→opening prompt 全链路已验证，§2.4）
      同 CR 已有 running 任务 → 入队为 queued 后继（持久化排队，不注入运行中沙箱）；
      已存在排队后继 → 幂等重读后把本次审批四字段原子合并进后继（§4.3 阶梯 2）；
      同 (issue, agent) 已被普通任务占槽 → 以 deferred+fire_at 让位插入（§4.3 阶梯 3）
  → 被唤醒 Agent 自行读 .crctl/grants/ 与 crctl status/next 路由下一步（FR-9）
```

# 2. 数据模型

## 2.1 表变更总览

| 表 | 变更 | 依据 |
|---|---|---|
| `approval_record` | **零结构变更**（AC-10）；`HandleGrantsAck` 的 UPDATE `RETURNING` 扩展为 `id, cr_id, stage, decision, approver_user_id`（现仅 `cr_id`，approval.go:392-395） | 迁移 433 已有全部所需列（stage/decision/delivered_at/approver_user_id） |
| `agent_task_queue` | 新增 nullable `approval_workspace_id UUID`（无 FK，仅 `approval_continuation` 行必填；迁移 470 CHECK 强制）；新增两条 partial unique index（迁移 469/471）；复用既有 `trigger_evidence_kind`/`trigger_evidence_ref_id`（迁移 184）、`cr_id`（迁移 437）、`handoff_note`（迁移 122，prompt 载体）、`is_leader_task`（迁移 090）+ `squad_id`（迁移 127）列 | FR-4/FR-6/FR-7/FR-9/FR-11；TD-BL-10；PRD A4/A5 |

## 2.2 迁移 469 — 单审批记录幂等（FR-4）

```sql
-- 469_approval_continuation_record_active_unique.up.sql（单语句，CONCURRENTLY 惯例）
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_approval_continuation_record_active
    ON agent_task_queue (trigger_evidence_ref_id)
    WHERE trigger_evidence_kind = 'approval_continuation'
      AND status IN ('queued', 'deferred', 'dispatched', 'waiting_local_directory', 'running');
-- 469_…down.sql
DROP INDEX CONCURRENTLY IF EXISTS idx_approval_continuation_record_active;
```

同一 `approval_record.id` 在活跃状态下至多一条续跑任务；同一审批 ACK 重放/并发入队竞争时，输家按已存在处理（幂等重读），不产生第二条、不报 5xx（FR-1/FR-4/AC-1）。

## 2.3 迁移 470/471 — workspace-qualified 排队后继（FR-6/FR-7，TD-BL-10/11）

`agent_task_queue` 现无 workspace 列，不能用全局 `cr_id` 表达 CR 权威键 `(workspace_id, cr_id)`。不把 workspace 塞进 prompt/context（FR-9 最小上下文不扩张），而在任务行增加仅供续跑约束使用的 nullable carrier；不加 FK（仓库硬规则），由 CHECK + guarded INSERT 强制：

```sql
-- 470_approval_continuation_workspace_scope.up.sql（单条 ALTER TABLE）
ALTER TABLE agent_task_queue
  ADD COLUMN approval_workspace_id UUID,
  ADD CONSTRAINT agent_task_queue_approval_workspace_ck
  CHECK (trigger_evidence_kind IS DISTINCT FROM 'approval_continuation'
         OR approval_workspace_id IS NOT NULL);
-- down：同一 ALTER TABLE 先 DROP CONSTRAINT，再 DROP COLUMN
```

```sql
-- 471_approval_continuation_workspace_cr_pending_unique.up.sql（单语句，CONCURRENTLY）
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_approval_continuation_workspace_cr_pending
    ON agent_task_queue (approval_workspace_id, cr_id)
    WHERE trigger_evidence_kind = 'approval_continuation'
      AND status IN ('queued', 'deferred');
-- 471_…down.sql
DROP INDEX CONCURRENTLY IF EXISTS idx_approval_continuation_workspace_cr_pending;
```

- `CreateApprovalContinuationTask` 必须把认证 daemon workspace 写入 `approval_workspace_id`；guarded INSERT 同句校验 `agent/issue/squad/cr` 均属于该 workspace。普通任务该列保持 NULL，不改变既有 enqueue/claim 路径。
- 471 的唯一键 = `(approval_workspace_id, cr_id)`，与 migration 433/467 已确认的 CR/approval workspace authority 同构；workspace A/B 的同名 CR 键不同，既不冲突也不能被对方重读/合并。
- 谓词只含 **prompt 尚未快照**的 `queued/deferred`。这两个状态才允许阶梯 2 合并 handoff；`dispatched/waiting_local_directory/running` 已经 claim 或启动，禁止改写为“当前任务可见”，而是补插一条新的 queued/deferred 后继（TD-BL-11）。
- 同一 workspace+CR 至多 1 条未 claim 后继；一条 in-flight（dispatched/waiting_local_directory/running）之后允许 1 条持久化后继。`ClaimAgentTask` 对同一 (issue, agent) 检查 active `dispatched/running/waiting_local_directory`（agent.sql:841-906），后继在前驱结束前不可 claim，不向运行中沙箱注入事件。
- 迁移 469（§2.2）的 record-id 谓词保持五状态含 running；同一审批 ACK 重放仍只能关联一条任务。`GetApprovalContinuationTaskByRecord` 同时带 `approval_workspace_id=$ws`，防御性禁止跨 workspace 读回。

另需注意既有 `idx_one_pending_task_per_issue_agent_v2`（迁移 257）：谓词为 `status IN ('queued','dispatched') OR (status='deferred' AND context->>'channel_issue_media_pending'='true')`。若 leader 的槽被普通任务或刚 claim 的 continuation 占用，queued INSERT 会冲突；阶梯 3 改插 `deferred + fire_at=now()`（不含 channel 标志，位于 257 谓词外）。既有 `PromoteDueDeferredTasksForRuntime` 在槽释放后翻 queued，`ClaimAgentTask` 只认 queued，因此续跑串行且不丢失。

## 2.4 续跑任务行形状（仅新增 tenant carrier，其余复用既有列）

| 列 | 值 | 说明 |
|---|---|---|
| `agent_id` / `runtime_id` | CR leader agent 及其 runtime | FR-7 解析结果 |
| `approval_workspace_id` | 认证 daemon workspace UUID | 迁移 470 新 carrier；仅 continuation 必填，不进入 prompt/context；与 `cr_id` 组成 workspace-qualified authority（TD-BL-10） |
| `issue_id` | `cr.shell_issue_id` | 既有投影关联（迁移 433） |
| `status` | `queued`；阶梯 3 让位时 `deferred`（+`fire_at=now()`，§4.3） | 走既有 claim/sweeper 路径 |
| `priority` | `priorityToInt(issue.Priority)` | 与 mention 任务一致（task.go:1472） |
| `trigger_evidence_kind` / `trigger_evidence_ref_id` | `'approval_continuation'` / `approval_record.id` | 直接证据指针（迁移 184 语义），AC-1 断言键 |
| `cr_id` | approval_record.cr_id | 迁移 437 列 |
| `context` | `{"type":"approval_continuation","schema":"ai-first.approval-continuation/v1","approvals":[{"cr_id","stage","decision","approval_record_id"}, …]}` | FR-9 最小上下文的**机器可读**形态（审计/幂等键语义）；**approvals[] 为可追加数组**（TD-SUG-4）：INSERT 时恰 1 项，合并时追加（§4.3 阶梯 2），同记录幂等不重复追加。本 CR 未上线、无遗留行，无需 v1→v2 数据迁移。**不含任何状态→下一步映射**（AC-8）。⚠️ 不直接进 prompt（见下表后注） |
| `handoff_note` | 首次 INSERT：`"{cr_id} 的 {stage} 审批已 {decision}（approval_record_id={id}）。请读取 .crctl/grants/ 与 crctl status/next 确定下一步；本提示不携带任何状态→下一步映射。"`；合并时逐行追加 | FR-9 上下文的 **prompt 实际载体**（迁移 122 列；claim→daemon→opening prompt 全链路验证，见下表后注）。**{cr_id} 直接用 CR 标识原值（如 `CR-2026-052`，已含 `CR-` 前缀），不再拼接 `CR-{cr_id}`**——避免 `CR-CR-2026-052` 双前缀（TD-SUG-3） |
| `trigger_summary` | `"{cr_id} approval {stage}: {decision}"`（{cr_id} 原值，同 TD-SUG-3） | 展示与 brief 注入 |
| `is_leader_task` / `squad_id` | `true` / issue 的 squad id | leader 角色契约：daemon claim 侧按 squad_id 注入 squad 简报（迁移 127 注释）；与既有 leader enqueue 契约一致（TD-SUG-2） |
| `originator_user_id` / `accountable_user_id` | `approver_user_id` | DD-7：审批人是真实人工动作主体，不伪造归因（NFR-12） |
| `originator_source` | `'direct_human'` | attribution 既有词汇表（attribution.go:26-60），不新增 source 标签 |

> **prompt 透传事实（评审 TD-BL-1，已核实）**：claim/prompt 链路只对 `context.type=pipeline_node` 做专门 hydration（handler/agent.go:482 注释），普通 issue 任务的 `buildPromptBody`（daemon/prompt.go:171-201）不读取原始 context JSON。因此审批上下文经 `handoff_note` 送达：claim 响应携带 handoff_note 字段（handler/agent.go:789-790, 820）→ daemon 装入 `Task.HandoffNote`（daemon.go:6767）→ opening prompt 与 issue_context.md 渲染（prompt.go:193-196；types.go:165）。context JSON 保留为机器可读证据（审计、幂等键、未来水合扩展点）；SDD 0.1 的"context 即上下文送达"断言作废。`runtime_mcp_overlay`/`runtime_connected_apps` 留空（NULL）：续跑任务只跑 crctl/grants 读取，无 composio/MCP 权限面需求；先例 = CreatePipelineTask 不写 overlay 列（agent.sql:651-668）。
>
> **prompt 分支保证（TD-BL-7/11，已核实）**：`BuildPrompt` 的分支选择按 PipelinePrompt → ChatSessionID → TriggerCommentID → AutopilotRunID → QuickCreatePrompt（prompt.go:171-186）；续跑任务不写这五类触发字段，恒定走 assignment 默认分支并渲染 handoff_note。**仅 queued/deferred 尚未 claim，允许合并**；claim 把 queued 更新为 dispatched 后，handler 构造 response 时已快照 handoff_note，随后 waiting_local_directory/running 都沿用该 daemon Task，因此三种 in-flight 状态绝不追加新证据。新审批改由独立后继承载，后继未来 claim 时再把四字段送入自己的 opening prompt。grant 文件仍可供 Agent 读取，但不作为“旧 prompt 能看到新 ACK”的验收替代。普通 comment/mention 任务仍不合并。

# 3. 接口契约

## 3.1 HTTP：POST /api/daemon/approvals/ack（既有端点，语义升级）

- 请求不变：`{"ids": ["<approval_record.id>", …]}`（daemon 侧零改动，NFR-6）。
- 成功（2xx，所有匹配记录均完成「delivered_at + 续跑任务」成对落地或幂等命中）：`{"status":"ok"}` 形态不变。
- 失败（5xx，任一记录 resolve/入队失败或预提交回调 error → 整批回滚）：新增结构化错误体，供运维检索（NFR-10）：

```json
{"error":"approval continuation failed",
 "reasons":[{"cr_id":"CR-2026-052","stage":"tech-design","reason":"leader-missing"}]}
```

- 幂等重放：已交付记录再 ACK → UPDATE 匹配 0 行 → 200（沿用现有 0 行分支行为）。
- 鉴权不变：仍经 `resolveDaemonWorkspace`（DaemonAuth 组，NFR-12），请求体 ids 无法越权指定 workspace。

## 3.2 Go 回调：GrantAckEvent + 双钩契约（FR-10，评审 TD-BL-6 修正）

```go
// server/internal/governance/approval.go
type GrantAckEvent struct {
    WorkspaceID string // daemon workspace
    CrID        string
    RecordID    string // approval_record.id（text 形态，与 pending 端点一致）
    Stage       string // requirement | tech-design | dev-start | code
    Decision    string // approve | reject
}
// SetGrantAckHandler(fn func(context.Context, GrantAckEvent) error)          // 预提交：FR-10 的 onGrantAck，纯校验；error -> 5xx
// SetGrantAckCommittedHandler(fn func(context.Context, GrantAckEvent) error) // 提交后：真实唤醒；error -> 日志
```

- 由 `func(context.Context, string, string)` 变更而来。为与已审批 PRD FR-10 **机械对应**，原字段/注册面 `onGrantAck` / `SetGrantAckHandler` 保留名称，签名扩展为 `func(context.Context, GrantAckEvent) error`，仍在 COMMIT 前调用，其 error 直接导致回滚与 HTTP 5xx；不再把这个名字挪给提交后 wake（TD-BL-12）。
- **双钩分阶段契约（每次 ACK 每记录至多各一次）**：
  1. **`onGrantAck` / `SetGrantAckHandler`（预提交，FR-10 canonical callback）**：UPDATE+入队完成后、COMMIT 前调用；契约为纯校验、零副作用——不得写表、发事件/入队、修改自身状态或取与 ACK 行锁相交的锁，也不得依赖本事务未提交写。返回 error → 整批回滚 → HTTP 5xx；`delivered_at` 仍 NULL，daemon 15s 后真实重试。这一钩明确满足 FR-10“扩展后的 onGrantAck 返回 error 并影响 ACK HTTP 状态码”。
  2. **`onGrantAckCommitted` / `SetGrantAckCommittedHandler`（提交后）**：只承载真实 wake。Runner 的 Reconcile 会取 advisory lock、写 pipeline_run/pipeline_node_run、可能入队 task，这些副作用只能在 committed state 后发布；其 error 仅记结构化 Error 日志，HTTP 保持 2xx，因为 `delivered_at` 已提交且 daemon 不会重发该 ACK。名称显式含 `Committed`，不与 FR-10 的 error→HTTP callback 混淆。
- 唯一消费方 Runner 同批调整：`ValidateGrantAck(ctx, ev) error` 注册到 `SetGrantAckHandler`（只做 UUID/stage/decision 与只读目标校验，不调用 Reconcile）；`WakeGrant(ctx, ev) error` 注册到 `SetGrantAckCommittedHandler`（Reconcile，重读 approval_record 为权威）。router.go 原 `SetGrantAckHandler(architectureRunner.WakeGrant)` 一处接线替换为上述两处，编译契约同批收敛（NFR-8）。
- Runner 关闭（`AIFIRST_ARCHITECTURE_RUNNER` 未设置，router.go:1399）时两个钩均无人接线，通用 continuation 入队仍生效（AC-8）。

## 3.3 sqlc 新查询（内部接口，`server/pkg/db/queries/approval.sql`）

| 查询 | 形态 | 用途 |
|---|---|---|
| `AckApprovalGrants` | `:many`，UPDATE … RETURNING `id::text, cr_id, stage, decision, approver_user_id::text` | FR-3 事务内第一步（现内联 SQL 迁入） |
| `GetCrShellIssueInWorkspaceForShare` | `:one`，`SELECT * FROM cr WHERE workspace_id=$1 AND cr_id=$2 FOR SHARE` | 解析第一步并锁定 cr 权威行（评审 TD-BL-5/TD-BL-8：并发 `cr.shell_issue_id`/status 投影写等到本事务提交，DD-10） |
| `CreateApprovalContinuationTask` | `:one`，guarded INSERT + `ON CONFLICT DO NOTHING RETURNING *`；`status`（`queued`/`deferred`）与 `fire_at` 参数化 | 事务内第二步（仿 `CreatePipelineTask`，agent.sql:651）；deferred 变体用于 257 让位（§4.3 阶梯 3） |
| `AppendApprovalContinuationEvidence` | `:one`，按 `(id, approval_workspace_id)` UPDATE 后继行追加 approvals[]/handoff_note（行锁已由阶梯 2 锁读持有，无 status 谓词；NOT EXISTS 幂等防同记录重复追加） | 阶梯 2 原子合并（TD-BL-7/9/10，§4.3） |
| `GetApprovalContinuationTaskByRecord` | `:one`，按 `(approval_workspace_id, kind, ref_id)` + 五状态含 running 读回 | 幂等重读阶梯 1（469 键；workspace 防御性限定） |
| `GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate` | `:one`，按 `(approval_workspace_id, kind, cr_id)` + `status IN ('queued','deferred')` 执行 `SELECT … FOR UPDATE` | 阶梯 2：仅 prompt 未快照的后继可合并（471 键；TD-BL-9/10/11，§4.3） |

`CreateApprovalContinuationTask` 显式写 `approval_workspace_id=$ws`，并在单条 INSERT 内联复核**完整权威链**（评审 TD-BL-2/5/10）：`JOIN agent a ON a.id=$agent AND a.workspace_id=$ws AND a.archived_at IS NULL AND a.runtime_id IS NOT NULL AND a.kind='user'` ∧ `JOIN issue i ON i.id=$issue AND i.workspace_id=$ws` ∧ `JOIN squad s ON s.id=i.assignee_id AND s.workspace_id=$ws AND s.leader_id=a.id AND s.archived_at IS NULL` ∧ `JOIN cr c ON c.workspace_id=$ws AND c.cr_id=$cr AND c.shell_issue_id=i.id`——任一守卫失败插 0 行（不静默，走 §4.3 阶梯 4 回滚）。后续按 CR 重读、锁读和合并均同时限定同一个 `$ws`，不能从冲突 fallback 越过 tenant fence。resolveContinuationTarget 的读在守卫前**已按固定锁序持有锁**（§4.2/DD-10）：守卫是锁之外的复核兜底，不再承担“防陈旧”的唯一职责（SDD 0.2 只靠语句级快照，评审 TD-BL-5 指出其挡不住 INSERT 后、提交前的并发改）。issue 侧锁读新增 `LockIssueInWorkspaceForShare`（issue.sql，FOR SHARE，返回整行；锁级理由见 §4.2/DD-10——不再仿既有 `LockIssueForChannelMediaBind` 的 FOR KEY SHARE：其只与删除方 FOR UPDATE 互斥、与普通非键 UPDATE 不互斥，评审 TD-BL-8）；squad/agent 复用既有 `LockSquadForAutopilotAssignment`/`GetAgentForUpdate`。

## 3.4 tools 侧：无外部接口变化（NFR-9）

outbox 事件文件 schema（`v`/`event_kind`/`cr_id`/`payload` 等）与 `dedup_name` 生成规则均不变，仅 `emitOutboxEvent` 内部 `comparable()` 对 payload 的比较剔除 `detected_at`（DD-6）。采集端（daemon）无感知。

# 4. 关键算法与流程

## 4.1 HandleGrantsAck（multica 侧核心，伪代码）

```text
HandleGrantsAck(req {ids}):
  ws := resolveDaemonWorkspace(r)                    # 既有鉴权，403 不变
  tx  := pool.Begin(ctx)                             # pgx 原生事务（FR-3）
  qtx := queries.WithTx(tx)
  rows := qtx.AckApprovalGrants(ctx, ws, ids)        # UPDATE … RETURNING 五字段
  ackEvents, tasks := [], []
  for row in rows:
    target, reason := resolveContinuationTarget(qtx, ws, row)   # FR-7 fail-closed + 锁链（§4.2）
    if target == nil:
      log.Warn("approval continuation skipped", cr, stage, decision, reason)
      rollback; return 500 {error, reasons:[…]}       # delivered_at 保持 NULL（FR-5）
    task, outcome := taskSvc.EnqueueApprovalContinuation(ctx, qtx, spec(row, target))
    if outcome ∈ {already-queued, merged, successor-enqueued, slot-deferred}: log.Info(…, reason=outcome) # 幂等/合并/新后继/让位
    if task 为新建行: tasks += task                       # 仅新建行提交后广播（幂等命中/合并不重复广播）
    ackEvents += GrantAckEvent{ws, row.cr_id, row.id, row.stage, row.decision}
  for ev in ackEvents:                                # FR-10 onGrantAck：预提交纯校验、零副作用
    if onGrantAck != nil: if err := onGrantAck(ctx, ev); err: rollback; return 500
  commit                                              # 全部成对落地或回滚（DD-3）
  for task in tasks: taskSvc.NotifyContinuationTaskEnqueued(ctx, task)  # 提交后广播（FR-11；TD-SUG-1）
  for ev in ackEvents:                                # 明确的 post-commit wake（best-effort）
    if onGrantAckCommitted != nil: if err := onGrantAckCommitted(ctx, ev); err: log.Error(…, reason=ack-wake-failed)  # 不置 5xx
  return 200 {status: ok}
```

## 4.2 resolveContinuationTarget（FR-7，逐级 fail-closed + 权威锁链，每级一个 NFR-10 原因码）

```text
resolveContinuationTarget(qtx, ws, row):              # 全部读与最终 INSERT 同一事务（qtx）
  # 锁链（评审 TD-BL-5）：固定顺序 cr → issue → squad → agent，先锁后读，权威链稳定到提交
  cr := GetCrShellIssueInWorkspaceForShare(qtx, ws, row.cr_id)  # (ws, cr_id) 双键 + FOR SHARE；查不到 → reason=workspace-mismatch
  if cr.shell_issue_id 为空: return reason=issue-missing
  issue := LockIssueInWorkspaceForShare(qtx, cr.shell_issue_id, ws)  # issue.sql 新查询，FOR SHARE；跨 workspace 漂移/不存在 → issue-missing
  if issue.assignee_type != 'squad' 或 assignee_id 空: return reason=leader-missing
  squad := LockSquadForAutopilotAssignment(qtx, issue.assignee_id, ws)  # squad.sql:14-20，FOR SHARE；与 leader 变更的 FOR UPDATE 互斥
  if squad.archived_at 非空: return reason=leader-missing
  leader := GetAgentForUpdate(qtx, squad.leader_id)   # agent.sql:30-35，FOR UPDATE；与 runtime teardown 互斥 → runtime_id 稳定到提交
  if leader.workspace_id != ws 或 leader.archived_at 非空 或 leader.runtime_id 空: return reason=leader-missing
  return target{agent_id, runtime_id, issue_id, squad_id, project_id}
```

权威路径 = `cr.shell_issue_id → issue(assignee_type='squad').assignee_id → squad.leader_id`（迁移 433 + 084；PRD FR-7 允许的“既有关联”路径），**全程按认证 workspace 作用域**（评审 TD-BL-2）。

**锁链为什么闭合 TD-BL-5（权威链稳定到提交；锁级经评审 TD-BL-8 修正）**：cr/issue 两级取 **FOR SHARE**——Postgres 行锁矩阵中与普通 UPDATE 互斥的最弱锁级：普通非键列 UPDATE（如 `UpdateIssue` 改 assignee_id/assignee_type/status，issue.sql:164-257；crsync 的 status/projected_commit 投影写，crsync.go:397/458/477；shell_issue_id upsert）取 FOR NO KEY UPDATE，与 FOR SHARE 冲突；行 DELETE/键列 UPDATE 取 FOR UPDATE，亦与 FOR SHARE 冲突。SDD 0.3 用 FOR KEY SHARE 是锁矩阵误读——FOR KEY SHARE **不与 FOR NO KEY UPDATE 冲突**（只与 FOR UPDATE 冲突）：`LockIssueForChannelMediaBind` 的既有用途仅是与删除方 `LockIssueForDelete` 的 FOR UPDATE 互斥（issue.sql:89-95/128-135），迁移 284 owner fence 同理只挡 FOR UPDATE 持有方，二者都不能旁证“挡住普通非键 UPDATE”。FOR SHARE 先例 = 既有 `LockSquadForAutopilotAssignment`（squad.sql:12-20，注释明示 “FOR SHARE conflicts with an ordinary leader_id update”）。因此：并发 `issue.assignee_id` 重指派或 `cr.shell_issue_id`/投影写要么在本事务取锁前提交（我们读到新值），要么阻塞到本事务提交后（我们派发的就是 ACK 时点的权威值）——“INSERT 后、提交前被并发改写”的陈旧窗口被锁直接消除，SDD 0.2 只靠 guarded INSERT 语句级快照复核的缺口闭合。锁顺序与既有路径无环：crsync 只写 cr（不组合取 issue/squad/agent 锁）；issue 指派先 UPDATE issue 再 squad/agent；autopilot 取 squad→agent、不触 cr/issue；FOR SHARE 与 FOR KEY SHARE 互相兼容，与既有 `LockIssueForChannelMediaBind`/迁移 284 的 KEY SHARE 持有方不新增冲突。残余理论死锁（如 workspace teardown 扫描顺序）由 Postgres 死锁检测中止本事务 → 回滚 → 5xx → daemon 诚实重试，无部分效果。任何一级缺失都**不回退到任意 Agent**，整批回滚保持未 ACK，等配置修复后 daemon 重试补发（FR-7/AC-6）。禁止硬编码 agent id/名称。

## 4.3 CreateApprovalContinuationTask 幂等语义（FR-1/FR-4/FR-6；评审 TD-BL-7 修正）

```text
insert: INSERT INTO agent_task_queue(agent_id, runtime_id, approval_workspace_id, issue_id, status, priority, fire_at,
          trigger_summary, squad_id, is_leader_task, handoff_note, context,
          originator_user_id, accountable_user_id, originator_source,
          trigger_evidence_kind, trigger_evidence_ref_id, cr_id, project_id)
        SELECT …,$ws,…,'queued',NULL,…,true, handoff, approvals[本记录],…,'approval_continuation', record_id, cr_id …
        FROM workspace-qualified authority joins（§3.3）
        ON CONFLICT DO NOTHING RETURNING *;
conflict(0 行) → 幂等重读阶梯（所有查询都带 authenticated `$ws`）：
  1) GetApprovalContinuationTaskByRecord(ws, record_id)
     → 命中：already-queued（同审批重放/并发输家；469 键；跨 workspace 0 行）
  2) GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate(ws, cr_id)
     → 仅 queued/deferred 命中并 FOR UPDATE 锁行；本次审批四字段原子合并（471 键）
     → 0 行表示没有“prompt 尚未快照”的后继；不得去读/改另一 workspace，也不得向 dispatched/waiting/running 行追加
  3) 阶梯 1/2 均未命中：原 queued INSERT 已因 in-flight/普通任务占槽或竞态失败，直接改插
     status='deferred' + fire_at=now()（context 无 channel_issue_media_pending，位于 257 谓词外），建立独立后继。
     471 保证同一 workspace+cr 的并发 ACK 只有一个 queued/deferred 后继；输家重跑阶梯 2 合并。
  4) 全未命中且 deferred 插入仍 0 行 → tx-failure 回滚（不静默降级，纪律 1）
```

**阶梯 2 原子合并（TD-BL-9/10/11）**：仅由 `GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate($ws,$cr)`（`SELECT … FOR UPDATE`，471 键，状态仅 queued/deferred）锁住 prompt 尚未快照的后继，再由 `AppendApprovalContinuationEvidence($ws, successor_id, …)` 在同事务追加：

```sql
UPDATE agent_task_queue
SET context = jsonb_set(COALESCE(context,'{}'::jsonb), '{approvals}',
          COALESCE(context->'approvals','[]'::jsonb) || $new_entry::jsonb),
    handoff_note = COALESCE(handoff_note,'') || E'\n' || $new_line,
    updated_at = now()
WHERE id = $successor_id
  AND approval_workspace_id = $workspace_id
  AND trigger_evidence_kind = 'approval_continuation'
  AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(context->'approvals','[]'::jsonb)) e
                  WHERE e->>'approval_record_id' = $record_id)                -- 幂等：同记录不重复追加
RETURNING *;
```

**状态与 0 行判定**：
- 查询命中 queued/deferred 后已持 FOR UPDATE；claim 的 queued→dispatched 被阻塞到 ACK 提交。合并 UPDATE 0 行只能表示该 record 已在 approvals[]，返回 `already-queued`；不存在“状态在选择与 UPDATE 间漂移”的歧义（TD-BL-9）。
- 查询 0 行只表示当前 workspace+CR 没有可合并后继：可能本无后继，也可能已有 dispatched/waiting_local_directory/running 前驱。三种 in-flight 状态的 prompt/daemon Task 都已在 claim 响应阶段快照，数据库追加 handoff 无法回改，因此一律由阶梯 3 建立**新后继**，不宣称当前 in-flight task 可见本次审批（TD-BL-11）。
- 同批/并发多审批：第一条建立 `(ws,cr)` 后继；后续记录由 471 冲突后按同一 `(ws,cr)` 锁读并合并。不同 workspace 的同名 CR 键不同，各自在本 tenant 建行，fallback 查询也只能读本 tenant（TD-BL-10）。
- **可达契约**：只有 queued/deferred 行允许追加 handoff；它们尚未 claim，后续 `taskToResponse` 快照必含合并后的全部行。dispatched/waiting_local_directory/running 不合并；新审批由独立 queued/deferred 后继承载完整四字段，待前驱结束后 claim，其 opening prompt 再逐字获得。grant 目录仅作为运行时事实输入，不再用来证明已快照 prompt 能看到后续 ACK。普通 comment/mention 任务仍不合并。
- **阶梯 3 让位插入语义**：deferred 行不进 257 谓词（迁移 257 谓词 = queued/dispatched 或带 channel 标志的 deferred），与既有普通任务合法共存；`PromoteDueDeferredTasksForRuntime`（agent.sql:2255-2323）在 (issue,agent) 槽释放后的下一 tick 翻为 queued（被占槽时跳过、不丢：注释明确 “promoted by a later tick once the slot frees, so nothing is lost”）；`ClaimAgentTask` 仅认 queued 且 per-(issue,agent) 串行化（agent.sql:841-862）→ 续跑恒在普通任务之后串行执行，FR-6“不并发唤醒多份”保持。runtime 离线时 deferred 等待（同任何任务，NFR 不新增机制）。
- 阶梯 1 对应迁移 469（record-id 五状态幂等）；阶梯 2/3 对应 migration 470 carrier + 471 `(workspace,cr)` queued/deferred 唯一键。所有读写都带 `$ws`，且只有 prompt 未快照的后继可合并。

## 4.4 tools 侧 FR-12 修复（comparable 剥离观测时点字段）

`crctl.mjs:321` 现状：`comparable()` 将整个 `payload`（含每次观测重新生成的 `detected_at`，:351 `nowIso()`）JSON 序列化进比较；`emitDriftAudit`（:353）用确定性 `dedup_name`（cr+stage+两侧摘要前 8 位）落同一文件 → 同一漂移待采集期间二次观测必然 `OUTBOX_DEDUP_CONFLICT` → `EMIT_FAILED` 审计噪声，与"待采集期间只留一份"的设计语义矛盾。

修复（DD-6）：`comparable()` 构造比较对象时，对 payload 做浅拷贝后 `delete detected_at`：

```js
const comparable = (value) => JSON.stringify({
  v: value.v, event_kind: value.event_kind, cr_id: value.cr_id,
  from_status: value.from_status, to_status: value.to_status,
  trigger: value.trigger, commit_sha: value.commit_sha,
  actor: value.actor, evidence: value.evidence,
  payload: (() => { const p = { ...(value.payload || {}) }; delete p.detected_at; return p; })(),
});
```

- 事件文件内容、`dedup_name` 生成规则、`occurred_at` 均不改（FR-12 边界）；
- 摘要字段（`expected_digest`/`actual_digest`/`stage`/`action`）仍在比较内：若同名文件内容真实变化（摘要 8 位截断碰撞等极端情形）仍会冲突报错，确定性守卫不削弱（AC-12 第三分支）；
- 漂移被采集删除后再次观测：文件不存在 → 走全新写入路径，按观测窗口再留一份（既有语义保留，AC-12）。

# 5. 技术选型与替代方案

> 按决策记录三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代）仅记录以下 11 条；不新增 ADR、不新增审批节点。

### DD-1 触发点 = grant 已写入 worktree 后的 ACK
- **Context**：PRD 已拍板（FR-1），此处记录技术含义：ACK 是系统中唯一"grant 已可靠落盘"的确认信号；ACK 时点 grant 文件必已存在于 worktree，被唤醒 Agent 读取 `.crctl/grants/` 时数据已在位。
- **Alternatives**：飞书卡片回调（链路未封闭）、定时轮询（NFR-5 禁止）、状态事件（会复制状态机语义）。
- **Consequences**：daemon 交付与唤醒严格串行；ACK 失败整体可重试。

### DD-2 专用 guarded INSERT（CreateApprovalContinuationTask）而非复用 mention 路径（CreateAgentTask）
- **Context**：FR-3 要求与 `delivered_at` 同事务；FR-4/FR-6 需要 ON CONFLICT 语义；FR-7 需要逐级结构化原因。
- **Alternatives**：复用 `CreateAgentTask`/`EnqueueTaskForSquadLeader`（task.go:1406）——其归因瀑布、GetAgent 预载、无事务注入点、无 ON CONFLICT 处理，改造成本与侵入面更大，且会把审批归因引入 trigger-comment 语义，不合 FR-9 最小上下文。
- **Consequences**：新增 6 条 approval.sql 查询 + 1 条 issue 锁查询并重跑 sqlc generate；形态与仓库既有 `CreatePipelineTask` 先例（agent.sql:651）同构，评审可对照。

### DD-3 批量 ACK 单事务 all-or-nothing（而非逐记录部分成功）
- **Context**：FR-3"要么都生效要么都不生效"、FR-5"入队失败 ACK 返回 HTTP 错误"。
- **Alternatives**：逐 id 独立事务 + 响应携带 per-id 结果——daemon 侧需解析部分成功语义，超出"daemon 零改动"边界。
- **Consequences**：任一记录失败整批回滚、整批重投递（幂等写文件无害）；坏记录（如 leader 未配置）会连带阻塞同批健康 grant，直至配置修复——该 trade-off 由 FR-7"保持未 ACK 等待配置修复"显式背书，5xx 响应体 reasons 列表即为运维修复指引（NFR-10）。评审需确认此残余风险可接受。

### DD-4 workspace-qualified 双唯一键（record 五态 + `(workspace,cr)` queued/deferred）而不是全局 cr_id
- **Context**：FR-4 的 record id 幂等索引（469）保持五态；FR-6 的后继上限必须按 CR 权威键 `(workspace_id, cr_id)`，不能按全局 cr_id。只有 queued/deferred 尚未快照 prompt，可安全合并；dispatched/waiting/running 必须视为 in-flight 前驱并另建后继（TD-BL-10/11）。
- **Alternatives**：`(agent_id,cr_id)` 或 `(issue_id,cr_id)` 会在 leader/shell issue 重指派后失去同 CR 约束；把 workspace 放 `context` 会扩张 FR-9 prompt-adjacent schema 且 JSON 可变；全局 cr_id 会跨租户冲突与泄漏；把 in-flight 纳入 471 又无法保留下一后继。
- **Consequences**：迁移 470 增加 nullable `approval_workspace_id` + continuation 必填 CHECK（无 FK），迁移 471 用 `(approval_workspace_id,cr_id)` 对 queued/deferred 建 CONCURRENTLY partial unique index；普通任务零改动。469/471 + 257 共同收敛并发，ClaimAgentTask 保证同 target 串行。

### DD-5 保留 FR-10 `onGrantAck` 为预提交 error→HTTP 钩，另设显式 committed wake
- **Context**：FR-10 要求回调携带 id/stage/decision 且可返回 error；error 契约必须落在可回滚的原子边界内——提交后 5xx 是伪可重试失败（pending 端点按 `delivered_at IS NULL` 过滤，approval.go:351；daemon 对已交付记录不再重发 ACK，crevents.go:117-122）。SDD 0.2 为兼顾“error→5xx”与“唤醒需提交后”，把同一个 `Runner.WakeGrant/Reconcile` 在 COMMIT 前调一次——但真实 Reconcile 在读取 `delivered_at` 前就会取 advisory lock、写 pipeline_run/pipeline_node_run、可入队 pipeline task（runner.go:238-374），这些外部提交不随 ACK 回滚撤销，违反 multica ARCHITECTURE.md“Side effects publish only after committed state”与 FR-3 原子边界（评审 TD-BL-6）。
- **Alternatives**：保留旧回调 + 新增第二个回调——双通道并存，Runner 未来开启时语义分叉；单次提交后调用 + error→5xx——SDD 0.1 方案，制造虚假重试，作废；把 Reconcile 重构成“先校验后副作用”两段式——侵入 Runner 状态机，且校验段与 ACK 事务视图无法对齐；真实持久化重试（notified_at 列 + 服务端扫描）——NFR-4 禁止新重试框架，且唯一消费方 Runner 默认关闭，成本不成比例。
- **Consequences**：原 `SetGrantAckHandler`/`onGrantAck` 仅扩展签名并返回 error，预提交纯校验，error → 回滚/5xx；新增 `SetGrantAckCommittedHandler`/`onGrantAckCommitted` 专门在 COMMIT 后调用 `WakeGrant`，error → 日志/2xx。Runner 以 `ValidateGrantAck` + `WakeGrant` 分别接线。命名、FR 映射与 AC-9 均能机械指出“哪个 callback error 影响 HTTP”（TD-BL-12）。

### DD-9 257 占槽时以 deferred 让位插入（而非向普通任务合并证据）
- **Context**：`idx_one_pending_task_per_issue_agent_v2`（迁移 257）谓词 = queued/dispatched 或带 `channel_issue_media_pending` 标志的 deferred。leader 的 (issue, agent) 槽被普通 comment/mention 任务占用时，`status='queued'` 的续跑 INSERT 冲突。SDD 0.2 将其判为 already-queued 跳过——但普通任务的 `buildCommentPrompt` 不渲染 handoff_note、无 grants 读取约定，跳过即“已 ACK、无可证明续跑载体”（评审 TD-BL-7）。
- **Alternatives**：把证据合并进普通任务行——prompt 不可达（上）；取消/顶掉普通 pending 任务——破坏既有任务归属（MUL-4302），越权；savepoint 重试——Postgres 23505 后需 savepoint 才能续事务，增加复杂度且无收益；为普通任务补 grants 读取约定——侵入全部 prompt 契约，超出本 CR 边界。
- **Consequences**：插入参数化 status/fire_at；257 冲突路径改插 `deferred + fire_at=now()`（谓词外，索引不冲突）；既有 `PromoteDueDeferredTasksForRuntime`（agent.sql:2255-2323）在槽释放后自动翻 queued（被占槽时跳过、不丢），`ClaimAgentTask` per-(issue,agent) 串行化保证顺序执行——FR-6 保持，零新增机制、零 prompt 侵入。可观测性新增 `slot-deferred`（Info）原因码。

### DD-10 权威锁链 cr→issue→squad→agent（FOR SHARE 起步，先锁后读；锁级经评审 TD-BL-8 修正）
- **Context**：SDD 0.2 只锁 squad/agent，cr/issue 靠普通 SELECT + guarded INSERT 的语句级快照复核——单语句快照挡不住“INSERT 后、提交前”并发改 `cr.shell_issue_id`/`issue.assignee_id`，仍可能向旧 shell issue/旧 squad leader 落任务（评审 TD-BL-5）。SDD 0.3 给 cr/issue 加 FOR KEY SHARE，但该锁级**不与 FOR NO KEY UPDATE 冲突**（只与 FOR UPDATE 冲突）——而既有 `UpdateIssue`（issue.sql:164-257，改 assignee_id/assignee_type/status 等非键列）、crsync 的 cr 投影写（crsync.go:397/458/477）与 shell_issue_id upsert 都是普通非键 UPDATE（取 FOR NO KEY UPDATE）；`LockIssueForChannelMediaBind` 的既有用途仅是与删除方 `LockIssueForDelete` 的 FOR UPDATE 互斥（issue.sql:89-95/128-135）——故 FOR KEY SHARE 挡不住重指派/投影改（评审 TD-BL-8）。
- **Alternatives**：SERIALIZABLE 隔离——全库语义切换不可控，且 Postgres 需重试循环，超范围；把全部权威校验塞进单条 INSERT——语句级快照仍不持锁，不闭合；应用层悲观锁表——引入新锁基础设施，违反 NFR-4。
- **Consequences**：新增 2 条锁读查询（`GetCrShellIssueInWorkspaceForShare`/`LockIssueInWorkspaceForShare`，**FOR SHARE** = 与普通非键 UPDATE（FOR NO KEY UPDATE）及行 DELETE（FOR UPDATE）均互斥的最弱锁级；先例 = 既有 `LockSquadForAutopilotAssignment` FOR SHARE，squad.sql:12-20 注释“conflicts with an ordinary leader_id update”；FOR SHARE 与 FOR KEY SHARE 互相兼容，与既有 `LockIssueForChannelMediaBind`/迁移 284 的 KEY SHARE 持有方不新增冲突面）；固定锁序 cr→issue→squad→agent，先锁后读，与既有路径（crsync 只写 cr；issue 指派 issue→squad→agent；autopilot squad→agent）无环；guarded INSERT 全链 join 保留为复核兜底；新增并发 reassignment/projection race 集成测试（§7.4 AC-6b/6c，含“FOR KEY SHARE 下不成立”的锁级回归断言）。ACK 为低频路径，短事务内多 2 次点锁读，无热路径影响（§7.2）。

### DD-11 排队后继的幂等原子合并（approvals[] 追加 + handoff 追加行）
- **Context**：SDD 0.2 阶梯 2 对已存在的排队后继仅判 already-queued，本次审批四字段不并入，与 TD-BL-7 的“无可证明续跑载体”同源：排队后继后续 ACK 的证据应落在它身上，否则后继运行时只能靠 grants 目录推断、拿不到 approval_record_id。
- **Alternatives**：每个审批必插一条任务会违反 FR-6 单后继上限；给 grant 文件加 approval_record_id 违反 NFR-8；向 dispatched/waiting/running 行追加 handoff 无法更新 daemon 已持有的 Task 快照（TD-BL-11）。
- **Consequences**：阶梯 2 只锁 `(approval_workspace_id,cr_id,status∈queued/deferred)` 并追加 approvals[]/handoff；claim 若先把 queued 推为 dispatched，锁读即 0 行并由阶梯 3 创建新后继。锁读若先持锁，claim 阻塞到合并提交后才构造 response，opening prompt 可执行地包含新增行。所有查询/UPDATE 带 workspace，跨租户不可读写（TD-BL-10）。

### DD-6 FR-12 在 comparable() 内剥离 payload.detected_at（而非为 drift 事件单独传比较副本）
- **Context**：`comparable()` 是 dedup 名冲突时的内容一致性守卫；`detected_at` 是唯一的观测时点易变字段（顶层 `occurred_at` 本就不参与比较）。
- **Alternatives**：`emitDriftAudit` 单独传 `comparable_payload`——把易变字段清单推给每个调用方，未来新事件易再犯；改 `dedup_name` 生成规则——违反 FR-12"不改文件名规则"。
- **Consequences**：一行级改动 + 注释说明易变字段白名单语义；新事件若引入其它时点字段需同步维护该剥离逻辑（SDD 明确，实施期加注释）。

### DD-7 续跑任务归因 = approver（originator_source='direct_human'）
- **Context**：MUL-4302 归因契约要求每个 run 可追溯到一个人；审批记录携带 `approver_user_id`（真实人工）。
- **Alternatives**：新增 source 标签（如 `approval_continuation`）——184 迁移允许无迁移加标签，但“审批人”就是直接人工动作，落入既有 `direct_human` 语义（attribution.go:26-33），无需扩词汇表；`owner_fallback` 会降级为 Agent 属主，不合 NFR-12“不伪造人工归因”。
- **Consequences**：不新增归因词汇；审批人可在既有归因 UI 看到自己审批触发的续跑。

### DD-8 审批上下文经 handoff_note 送达 prompt（而非依赖 context JSON 水合）
- **Context**：claim/prompt 链路只对 `context.type=pipeline_node` 做专门 hydration（handler/agent.go:482），普通 issue 任务的 `buildPromptBody` 不读原始 context（daemon/prompt.go:171-201）；SDD 0.1 把审批上下文写进 context 却无任何可达 prompt 路径，Agent 实际收不到（评审 TD-BL-1）。`handoff_note`（迁移 122）是既有的、全链路已接线的 prompt 载体：claim 响应（handler/agent.go:789-790, 820）→ `Task.HandoffNote`（daemon.go:6767）→ opening prompt + issue_context.md（prompt.go:193-196）。
- **Alternatives**：为 `approval_continuation` 新增 claim→daemon→prompt 水合契约——侵入 daemon 侧 prompt 构建，超出“daemon 零改动”边界（DD-1）；把上下文塞进 issue 描述/评论——污染既有展示面，违反 FR-11/NFR-11；向普通 pending 任务合并证据——其 `buildCommentPrompt` 不渲染 handoff_note（prompt.go:335-365），不可达（评审 TD-BL-7，已由 DD-9 替代）。
- **Consequences**：多写一列既有列（handoff_note）；context JSON 保留为机器可读证据并升级为 approvals[] 可追加数组（TD-SUG-4）；handoff 模板直接用 `{cr_id}` 原值避免 `CR-CR-` 双前缀（TD-SUG-3）；续跑任务不写五个触发字段 → prompt 恒定 assignment 分支（§2.4 注）；新增 prompt 层测试锁定“四字段（含合并追加行）实际出现在 opening prompt”（§7.4）。

# 6. FR 到技术实现映射

| FR | SDD 落点 |
|---|---|
| FR-1 ACK 时点幂等唤醒 | §1.4 流程、§4.1（UPDATE RETURNING 驱动入队）、§4.3（ON CONFLICT + 重读阶梯：同记录幂等重读 / 后继合并 / 让位插入）；迁移 469 |
| FR-2 四类审批覆盖，通过/驳回均续跑 | §4.1：stage/decision 直接来自 `approval_record` 行（DD 无 stage 分支），approve/reject 均入队；驳回后的修订路由由被唤醒 Agent 依 crctl next 执行（不在 Multica 内） |
| FR-3 原生原子事务 | §4.1：pgx `pool.Begin` + `queries.WithTx`，delivered_at 与入队同一 commit；失败回滚不标记 delivered_at；预提交 `onGrantAck` 仅做零副作用校验，提交后才有事件/唤醒 |
| FR-4 窄唯一约束防重复唤醒 | 迁移 469 + §4.3 阶梯 1 |
| FR-5 ACK 失败语义与 daemon 重试 | §4.1（5xx 仅来自预提交 tx/`onGrantAck` error → 回滚保持 pending）+ §1.2（既有 15s 重投递）+ §3.1 错误体；committed wake error 不置 5xx（§3.2） |
| FR-6 同 CR 最多一个后继，不注入事件 | 迁移 470/471：每 `(workspace,cr)` 至多 1 条 queued/deferred 后继；§4.3 仅合并未 claim 后继，dispatched/waiting/running 另建持久化后继；ClaimAgentTask 串行化保证不向前驱沙箱注入、不并发执行 |
| FR-7 leader 解析 fail-closed | §2.3/§3.3/§4.2：`approval_workspace_id` + `(workspace,cr)` 索引/查询、逐级 workspace-scoped 锁链与四类原因码；§3.1 reasons 响应体 |
| FR-8 只处理新 ACK | UPDATE 谓词 `delivered_at IS NULL`（既有行为原样保留），无回填路径 |
| FR-9 不复制状态机语义 | §2.4：context JSON（approvals[] 数组，机器可读）+ handoff_note（prompt 实际载体，仅 CR/stage/decision/record 引用，无下一步映射）+ §3.2 回调；Multica 侧无任何“状态→下一步”映射 |
| FR-10 ACK 回调数据补齐 | §3.2：原 `onGrantAck`/`SetGrantAckHandler` 扩展为 GrantAckEvent + error，预提交 error→回滚/5xx；新增明确命名的 committed wake 钩仅负责提交后 Reconcile、error→日志；Runner.ValidateGrantAck/WakeGrant 同批调整（DD-5，TD-BL-12） |
| FR-11 复用既有展示面 | §2.4（复用 agent_task_queue 全部既有列）+ NotifyContinuationTaskEnqueued 广播（broadcastTaskEvent+NotifyTaskEnqueued，§1.3/§4.1）；无新状态列/新投影 |
| FR-12 audit-drift 去重修复 | §4.4 comparable() 剥离 detected_at（DD-6）；不改事件内容与文件名规则 |

**FR 覆盖率：12/12**。

# 7. 安全与性能考量

## 7.1 边界条件与安全

- **workspace 隔离（TD-BL-10）**：续跑目标以认证 daemon workspace 为根；任务行以 `approval_workspace_id` 承载 tenant authority，migration 470 CHECK 强制 continuation 非 NULL，migration 471 唯一键 `(approval_workspace_id,cr_id)`。Create/record-read/CR-lock-read/append 全部显式带同一 `$ws`，guarded INSERT 再复核 agent/issue/squad/cr 全链 workspace join。两个 workspace 的同名 CR 可并发各建一条后继，互不冲突、互不可读写；shell_issue_id 跨 workspace 漂移仍 0 行 fail-closed。
- **越权与陈旧 leader（评审 TD-BL-5/TD-BL-8 闭合）**：leader 解析走 issue→squad 关联，读-写全程同事务 + **权威锁链 cr→issue→squad→agent 固定顺序先锁后读**（`GetCrShellIssueInWorkspaceForShare`/`LockIssueInWorkspaceForShare` FOR SHARE——与普通非键 UPDATE（FOR NO KEY UPDATE）互斥，§4.2/DD-10；既有 `LockSquadForAutopilotAssignment` FOR SHARE / `GetAgentForUpdate` FOR UPDATE）：并发重指派 `issue.assignee_id`、投影改 `cr.shell_issue_id`、leader 变更与 runtime 解绑要么在本事务取锁前提交（读到新值），要么阻塞到本事务提交后——陈旧权威窗口消除，不再只靠 guarded INSERT 语句级快照；guarded INSERT 全链 join（`squad.leader_id = agent.id` 等）保留为复核兜底；无 leader 一律失败，不回退任意 Agent（FR-7）；不新增开放端点，ACK 鉴权不变（NFR-12）。
- **并发**：469 record-id 五态索引 + 471 `(workspace,cr)` queued/deferred 索引是硬兜底；`ON CONFLICT DO NOTHING` 输家只在本 workspace 重读。仅 queued/deferred 可合并；in-flight 状态另建后继，ClaimAgentTask 串行执行。
- **历史数据**：无回填迁移；旧 `delivered_at` 非空行天然不进 UPDATE 结果集（FR-8/AC-7）。
- **回调失败（TD-BL-12）**：FR-10 `onGrantAck` handler 在预提交返回 error → 回滚、delivered_at NULL、HTTP 5xx、daemon 真实重试；该 handler 契约上零外部副作用。`onGrantAckCommitted` wake error → Error 日志、HTTP 2xx，不伪造可重试结果。

## 7.2 性能

- ACK 为低频人工触发路径；单事务内完成 1 次 UPDATE + 每记录至多 4 次点查（含 2 次 FOR SHARE 锁读）+ 1 次 INSERT（或 1 次锁读+合并 UPDATE / 1 次 deferred 让位插入），无轮询/后台扫描（NFR-5）。锁链只在短事务内持有；crsync 的 cr 投影写若与 ACK 同瞬竞争会等待锁释放，量级毫秒、无热路径影响。
- daemon 侧零改动、零新增往返（NFR-6）；续跑任务与普通任务共用队列与 reclaim 机制。
- tools 侧：`comparable()` 仅多一次对象浅拷贝，仅 dedup 名命中时执行，无热路径影响。

## 7.3 可观测性（NFR-10 原因码全集）

| reason | 触发 | 日志级 |
|---|---|---|
| `workspace-mismatch` | (ws, cr_id) 无投影行 | Error |
| `issue-missing` | shell_issue_id 为空 | Error |
| `leader-missing` | 非 squad 指派 / 无 squad / leader 缺失或未绑定 runtime | Error |
| `already-queued` | 幂等重读阶梯命中（同记录重放 / 已合并记录重放） | Info |
| `merged` | 阶梯 2 在同 workspace 的 queued/deferred 后继上原子合并完成 | Info |
| `successor-enqueued` | 无可合并后继（含 dispatched/waiting/running 前驱）时新建 queued 后继 | Info |
| `slot-deferred` | queued INSERT 被普通任务或 dispatched 前驱占槽时，以 deferred 排队等待槽释放 | Info |
| `tx-failure` | 重读阶梯全未命中且让位插入失败或事务错误 | Error |
| `ack-handler-failed` | FR-10 `onGrantAck`/`SetGrantAckHandler` 预提交返回 error（整批回滚，daemon 重试） | Error |
| `ack-wake-failed` | 提交后 wake（真实唤醒）返回 error | Error（HTTP 仍 2xx，§3.2 阶段 2） |

所有日志携带 cr_id、stage、decision、reason；5xx 响应体 reasons 列表同源（§3.1）。

## 7.4 测试设计（AC 映射）

**multica（Go，DB 集成测试贴包）**：
- `server/internal/governance/approval_continuation_test.go`（新）：保留 AC-1/2/3/5a~f/6~8/10，并新增/修正以下关键断言。
  - **AC-5g（claim-vs-append，可执行时序）**：queued 后继与 ACK 并发。claim 先提交 → 行已 dispatched，ACK 不更新它，创建恰 1 条 deferred 新后继，旧 claim response/handoff 不含新 record；ACK 锁读先持锁 → claim 阻塞，合并提交后 claim response/opening prompt 含两条记录四字段。
  - **AC-5i（dispatched/waiting_local_directory）**：先取得 claim response（并分别停在 dispatched、waiting_local_directory），再 ACK 新审批；断言旧 response/daemon Task 快照不变、旧 DB handoff 不追加，且新 queued/deferred 后继独立承载新 record；前驱完成后新后继 claim 的 opening prompt 才含该四字段。不得以“旧任务读 grants”替代此 prompt 断言。
  - **AC-6d（TD-BL-10 同名 CR 跨 workspace 并发隔离）**：workspace A/B 都创建 `CR-2026-052`，并发 ACK；各自产生 1 条 `approval_workspace_id` 与本 tenant 相等的后继，471 不跨 tenant 冲突。随后在 A 发第二审批，只能合并 A 行；B 行的 approvals[]/handoff/updated_at 均不变。用 A 的 workspace 调 record/CR fallback 查询 B 的 id/cr 均 0 行。
  - **AC-9a（TD-BL-12）**：`SetGrantAckHandler` 收到与 approval_record 一致的 GrantAckEvent；其 error 明确使 HTTP 5xx、事务回滚、delivered_at NULL。**AC-9b**：该 handler 实现零外部副作用并可被 daemon 重放。**AC-9c**：`SetGrantAckCommittedHandler`/WakeGrant error 发生在 COMMIT 后，仅日志且 HTTP 2xx。**AC-9d**：router 在 Runner 开启时按 `ValidateGrantAck→SetGrantAckHandler`、`WakeGrant→SetGrantAckCommittedHandler` 接线；关闭时两钩为空但 continuation 入队仍成功。
  - AC-6b/6c 继续覆盖 FOR SHARE 的 reassignment/projection race；AC-5h 继续区分“合并 0 行=record 已含”与“无 mergeable 后继=另建 successor”。
- `server/internal/daemon/prompt_test.go`：仅对尚未 claim 的 queued/deferred 后继断言合并 handoff 逐字进入 opening prompt；dispatched/waiting 用 AC-5i 的双任务时序断言，不再断言已快照 prompt 会变化。
- `server/internal/daemon/` 既有 deliverGrants fake fetcher：AC-4（ACK 5xx → grants 保持 pending → 下一周期重投递成功）。

**tools（node --test）**：扩展 `skills/shared/crctl/scripts/test/crctl.test.mjs` 既有 drift 用例（:776）：AC-11（连续两次观测 → audit-drift 文件恰 1、无 EMIT_FAILED 审计行、第二次幂等返回）；AC-12（删除文件后再观测 → 新文件按窗口计数；不同 CR/不同摘要不误合并；同名内容真实变化仍冲突）。

**验证顺序**：multica 根执行 `make sqlc`，再执行 `(cd server && go test ./internal/governance/... ./internal/daemon/...)`；tools worktree 执行 `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`。仓库根无 `go.work`、Go module 位于 `server/go.mod`，禁止再写不可执行的 `go test ./server/internal/...`（TD-SUG-5）。

## 7.5 残余风险（随评审确认）

1. **DD-3 批次联动阻塞**：坏 grant（leader 未配置）会阻塞同批其余 grant 的 ACK，直至配置修复。FR-7 显式背书该 fail-closed 语义；若评审认为不可接受，可后续追加 daemon 逐 grant ACK 的独立 CR（不在本 CR 范围）。
2. **排队后继的状态边界（TD-BL-11 闭合后）**：queued/deferred 尚未 claim，允许锁行合并并由后续 claim 快照完整 handoff；dispatched/waiting_local_directory/running 已快照或启动，永不追加新审批证据，而是建立独立 queued/deferred 后继。claim 与 ACK 的唯一竞态由 471 + FOR UPDATE 收敛为“合并后再 claim”或“先 claim、再建 successor”两种可测试顺序（AC-5g/5i），不依赖修改 daemon 内存 Task，也不再把 grants 目录当作 opening prompt 可达证明。
3. **257 占槽的让位延迟（TD-BL-7 闭合后）**：普通 pending 任务占用 (issue, agent) 槽时，续跑以 deferred 排队，等槽释放后由 sweeper 翻 queued——续跑发生在普通任务之后，符合 FR-6 串行化语义；runtime 离线时 deferred 等待（与任何 deferred 任务一致，不新增机制）。极端情形（普通任务长期 running）下续跑被推迟到其完成——这是“不并发唤醒、不注入沙箱”的直接结果，非缺陷。
4. **双钩回调的消费方约束（TD-BL-6/12 闭合后）**：FR-10 原名 `onGrantAck` 保持预提交 error→HTTP 契约且必须零副作用；`onGrantAckCommitted` 才执行真实 wake。若未来需要在 canonical handler 中写入副作用，必须先修订 PRD/事务边界，不能偷换两个名字的错误语义。
5. **权威锁链的竞争面（TD-BL-5/TD-BL-8 闭合后）**：FOR SHARE 锁在短事务内持有，阻塞面 = 并发 cr 投影写/issue 重指派/leader 变更（FOR NO KEY UPDATE/FOR UPDATE 持有方）——低频路径，等待毫秒级；FOR SHARE 与 FOR KEY SHARE 互相兼容，与既有 `LockIssueForChannelMediaBind`/迁移 284 owner fence 的 KEY SHARE 持有方不新增冲突面；残余理论死锁由 Postgres 死锁检测中止本事务 → 5xx → daemon 诚实重试（无部分效果）。

# 8. Prompt 采纳影响

**本节省略（条件不满足）**。判定依据（CR-2026-021 FR-25/AC-15）：本 CR 的 tools 侧 diff 仅触及 `crctl.mjs` 内 `emitOutboxEvent` 的 `comparable()` 比较逻辑（§4.4），**不触及** `crctl.mjs` 的 dispatch 分支、**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`——crctl 命令面与 guard deny 面均无新增/变更，无任何 skill 提示词需要改为调用新增/扩展子命令，故无需列出采纳清单。

# 9. 修订记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-08-27 | 初稿（write-tech-design 首轮） |
| 0.2 | 2026-08-27 | reviewLoop attempt 1 回修（quality-reviewer-agent 4 blocker，canonical `review-annotations/sdd.yml`，subject SHA `7e55be83…`）：TD-BL-1 上下文改经 handoff_note 送达 prompt（§2.4、DD-8）；TD-BL-2 解析全链 workspace-scoped + 锁对 + guarded JOIN 复核（§3.3/§4.2/§7.1）；TD-BL-3 回调两阶段契约（§3.2/§4.1、DD-5）；TD-BL-4 迁移 470 排除 running、持久化排队后继（§2.3/§4.3、DD-4、§7.4-7.5）；另采纳 TD-SUG-1（复用 broadcastTaskEvent+NotifyTaskEnqueued 顺序，§1.3/§4.1）与 TD-SUG-2（is_leader_task=true + overlay 留空说明，§2.4） |
| 0.3 | 2026-08-27 | reviewLoop attempt 2 回修（quality-reviewer-agent 3 blocker + 2 suggestions，canonical `review-annotations/sdd.yml`，subject SHA `57ab2fe8…`）：TD-BL-5 权威锁链 cr→issue→squad→agent 固定锁序先锁后读（新查询 `GetCrShellIssueInWorkspaceForKeyShare`/`LockIssueInWorkspaceForKeyShare` FOR KEY SHARE，§3.3/§4.2/§7.1，DD-10）+ reassignment/projection race 测试（AC-6b/6c）；TD-BL-6 回调拆双钩（`SetGrantAckPreflight` 预提交零副作用校验 + `SetGrantAckHandler` 提交后真实唤醒，§3.2/§4.1，DD-5）+ 零副作用与契约边界测试（AC-9b/9d）；TD-BL-7 阶梯 2 改为幂等原子合并（`AppendApprovalContinuationEvidence`：approvals[] 追加 + handoff 追加行 + NOT EXISTS 幂等，§4.3/§2.4，DD-11）、阶梯 3 改为 deferred 让位插入（257 谓词外 + `PromoteDueDeferredTasksForRuntime` 槽释放后翻 queued，§2.3/§4.3，DD-9）+ 冲突路径逐字段可达测试（AC-5d/5e/5f、prompt 层合并 handoff）；另采纳 TD-SUG-3（handoff 模板直接用 `{cr_id}` 原值，免 `CR-CR-` 双前缀）与 TD-SUG-4（context 升级为 approvals[] 可追加结构并固化 prompt 分支保证，§2.4/DD-8） |
| 0.4 | 2026-08-27 | reviewLoop attempt 3 回修（quality-reviewer-agent 2 blocker，canonical `review-annotations/sdd.yml`，subject SHA `83ba3b0d…`；评审循环经 squad leader 扩展一轮，attempt 4 复评）：TD-BL-8 锁级修正——cr/issue 锁读从 FOR KEY SHARE 改 FOR SHARE（`GetCrShellIssueInWorkspaceForShare`/`LockIssueInWorkspaceForShare`：与普通非键 UPDATE 的 FOR NO KEY UPDATE 互斥，锁矩阵误读更正；先例 `LockSquadForAutopilotAssignment`，§1.3/§3.3/§4.2/§7.1/§7.2/§7.5，DD-10）+ AC-6b/6c 重做为非键 UPDATE 阻塞断言（含 FOR KEY SHARE 下不成立的锁级回归守卫）；TD-BL-9 阶梯 2 收敛为锁读选中即锁行（`GetApprovalContinuationTaskByCrForUpdate` FOR UPDATE + 合并 UPDATE 去掉 status 谓词），0 行歧义消除：合并 0 行 ⟺ record 已含 → already-queued；锁读 0 行 ⟺ 状态离开谓词（claim 已推进 running）→ 阶梯 3 补插 deferred 新后继（§1.3/§3.3/§4.3/§6/§7.3，DD-11）+ claim-vs-append 并发测试（AC-5g/5h） |
| 0.5 | 2026-08-27 | cycle 2 / attempt 1 回修（canonical subject SHA `6dd72e9e…`）：TD-BL-10 新增 migration 470 `approval_workspace_id` carrier + CHECK、migration 471 `(workspace,cr)` queued/deferred 唯一索引，所有 fallback/merge 查询按 workspace 限定，并新增同名 CR 跨 workspace 并发隔离 AC-6d；TD-BL-11 仅合并 queued/deferred，dispatched/waiting/running 一律补插独立后继，AC-5g/5i 改为真实 claim-response 快照时序；TD-BL-12 保留 `onGrantAck`/`SetGrantAckHandler` 为预提交 error→5xx canonical callback，新增显式 committed wake 钩；采纳 TD-SUG-5，Go 验证改为 server module 目录执行。 |
