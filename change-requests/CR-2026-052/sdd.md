---
id: CR-2026-052-sdd
type: SDD
cr-ref: CR-2026-052
title: Multica 审批后自动续跑 + audit-drift 去重修复 技术设计
status: draft
created: 2026-08-27T01:47:00+08:00
updated: 2026-08-27T02:40:00+08:00
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
       │    AckApprovalGrants / GetCrShellIssueInWorkspaceForKeyShare / CreateApprovalContinuationTask（
       │    status/fire_at 参数化）/ AppendApprovalContinuationEvidence /
       │    GetApprovalContinuationTaskByRecord / GetApprovalContinuationTaskByCr
       ├─ 复用既有 workspace-scoped 查询 GetSquadInWorkspace / GetAgentInWorkspace 与既有锁查询
       │    LockSquadForAutopilotAssignment / GetAgentForUpdate；新增 2 条锁读查询（issue.sql）：
       │    LockIssueInWorkspaceForKeyShare（FOR KEY SHARE，权威链稳定，§4.2/DD-10）
       ├─ 回调拆双钩（§3.2/DD-5）：SetGrantAckPreflight（预提交纯校验）/ SetGrantAckHandler（提交后唤醒）
       └─ service.TaskService（新方法，FR-11 事件广播唯一通道）
            EnqueueApprovalContinuation(ctx, qtx, spec)   // 纯 DB 写入（事务内）
            NotifyContinuationTaskEnqueued(ctx, task)     // 提交后 = broadcastTaskEvent(EventTaskQueued)
                                                          // + NotifyTaskEnqueued（与 EnqueuePipelineTask 尾部一致，task.go:415-416）
server/migrations/
  ├─ 469_approval_continuation_record_active_unique.up/down.sql   // FR-4
  └─ 470_approval_continuation_cr_queued_unique.up/down.sql        // FR-6
server/cmd/server/router.go
  └─ NewApprovalServiceFromEnv(pool, queries, taskSvc) 依赖注入（两处调用点同步）
server/internal/governance/runner.go
  └─ WakeGrantPreflight（纯校验）+ WakeGrant（Reconcile 唤醒）适配新回调签名 GrantAckEvent（DD-5，唯一消费方同批调整）
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
         （预提交）onGrantAckPreflight 每记录一次：纯校验、零副作用；error → 整批回滚 → 5xx（§3.2）
         COMMIT
         （提交后）TaskService.NotifyContinuationTaskEnqueued 广播 EventTaskQueued（TD-SUG-1）
         （提交后）onGrantAck 每记录一次：真实唤醒（Reconcile），error → Error 日志不置 5xx（§3.2）
       → 2xx：全部记录的 delivered_at 与续跑任务已成对落地（或幂等命中/原子合并）
       → 5xx：仅预提交失败（tx 错误或预提交 preflight error）→ 整批回滚，delivered_at 保持 NULL，
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
| `agent_task_queue` | **零列变更**；新增两条 partial unique index（迁移 469/470）；复用既有 `trigger_evidence_kind`/`trigger_evidence_ref_id`（迁移 184）、`cr_id`（迁移 437）、`handoff_note`（迁移 122，prompt 载体）、`is_leader_task`（迁移 090）+ `squad_id`（迁移 127）列 | FR-4/FR-6/FR-9/FR-11；PRD A4/A5 |

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

## 2.3 迁移 470 — 同 CR 至多一个未开始运行的排队后继（FR-6）

```sql
-- 470_approval_continuation_cr_queued_unique.up.sql（单语句）
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_approval_continuation_cr_queued
    ON agent_task_queue (cr_id)
    WHERE trigger_evidence_kind = 'approval_continuation'
      AND status IN ('queued', 'deferred', 'dispatched', 'waiting_local_directory');
-- 470_…down.sql
DROP INDEX CONCURRENTLY IF EXISTS idx_approval_continuation_cr_queued;
```

谓词口径 = 迁移 443 `idx_agent_task_queue_pipeline_node_active` 的五状态 active 集合**减去 `running`**。这是评审 TD-BL-4 的修正点：SDD 0.1 把 `running` 纳入同 CR 唯一谓词，导致运行中任务期间到达的下一次审批直接被判 already-queued 吞掉——SDD 0.1 §7.5 自认的"窄窗需人工再 @"即源于此，违背 US-1 / FR-1 / FR-6 与自动续跑命中率 100% 目标。

语义（FR-6 新口径）：

- 同 CR 至多 1 条**排队后继**（queued/deferred/dispatched/waiting_local_directory 中任意状态）；
- `running` 不在谓词内：运行中任务**之后允许再入队 1 条排队后继**——持久化排队，不向运行中沙箱注入事件；
- 后继被 claim 后（dispatched→running）谓词释放，下一审批可再入队一条——链式衔接，上限恒为"1 running + 1 queued"；
- 排队后继在运行中任务完成前不会被 claim：`ClaimAgentTask` 对同一 (issue, agent) 串行化（agent.sql:841-862，存在 dispatched/running 任务时不可 claim）——两条续跑任务绝不同时执行；
- 排队后继运行时读 `.crctl/grants/` 目录：grant 文件在 ACK **之前**已写入（crevents.go deliverGrants 顺序），故后继覆盖运行期间到达并 ACK 的全部审批（§7.5 风险 2 的窄窗由此关闭）。

迁移 469（§2.2）的谓词**保持五状态含 running**：同一条 `approval_record.id` 的幂等性不依赖任务是否在运行——重复 ACK 任何时候都只能产生一条任务（FR-4），与 470 的排队后继语义互补不冲突。

另需注意既有 `idx_one_pending_task_per_issue_agent_v2`（迁移 257）：谓词为 `status IN ('queued','dispatched') OR (status='deferred' AND context->>'channel_issue_media_pending'='true')`（257_agent_task_queue_channel_media_pending_unique_v2.up.sql）。若 leader 在该 issue 上已有 pending 普通任务（mention/comment 等），续跑 INSERT 会命中该索引。**不与普通任务合并、不依赖普通任务的 prompt**（其 `buildCommentPrompt` 不渲染 handoff_note，且无读取 `.crctl/grants/` 的约定——评审 TD-BL-7 指出的不可达路径）：改为以 `status='deferred' + fire_at=now()` 让位插入（不含 channel 标志 → 谓词外，索引不冲突；§4.3 阶梯 3）。该 deferred 行由既有 `PromoteDueDeferredTasksForRuntime` 扫塔在 (issue,agent) 槽释放后自动翻为 queued（agent.sql:2255-2323 注释明确：deferred 行不在 257 谓词内、可与 queued 行合法共存、被占槽时跳过且“promoted by a later tick once the slot frees, so nothing is lost”）；`ClaimAgentTask` 仅认 queued（agent.sql:841-862）且 per-(issue,agent) 串行化，故续跑任务恒在普通任务之后串行执行，不并发唤醒多份（FR-6）。

## 2.4 续跑任务行形状（复用既有列，无新列）

| 列 | 值 | 说明 |
|---|---|---|
| `agent_id` / `runtime_id` | CR leader agent 及其 runtime | FR-7 解析结果 |
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
> **prompt 分支保证（评审 TD-BL-7，已核实）**：`BuildPrompt` 的分支选择按 PipelinePrompt → ChatSessionID → TriggerCommentID → AutopilotRunID → QuickCreatePrompt 依次判定（prompt.go:171-186），续跑任务**不写全部五个触发字段** → 恒定走 assignment 默认分支（buildPromptBody，prompt.go:171-201）→ handoff_note 逐字进入 opening prompt。合并后的多行 handoff（§4.3 阶梯 2）在任务尚未 dispatch 时同样逐字可达；已 dispatch/running 的后继 prompt 已生成、handoff 追加无法回改其 prompt，此时的可达路径 = 该后继自身的运行约定（读 `.crctl/grants/`：grant 文件在 ACK 前已写入，crevents.go deliverGrants 先写后 ACK）覆盖新审批的 stage/decision，record-id 级证明落在后继行的 context.approvals[]。grant 文件 schema 不含 approval_record_id（approval.go Grant struct：v/cr_id/stage/decision/approver/approved_at/evidence_digest/key_id/signature），且 NFR-8 禁止改 grant schema v1——record-id 证据只落在后继行，不依赖 grant 文件；运行时路由只需 stage/decision（grant 文件已具备）。**绝不向普通 comment/mention 任务合并证据**（其 prompt 分支不渲染 handoff_note，§2.3）。

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
// SetGrantAckPreflight(fn func(context.Context, GrantAckEvent) error)   // 预提交：纯校验
// SetGrantAckHandler(fn func(context.Context, GrantAckEvent) error)     // 提交后：真实唤醒
```

- 由 `func(context.Context, string, string)` 变更而来；**唯一消费方 Runner** 同批调整为两个方法：`WakeGrantPreflight(ctx, ev) error`（纯校验，见下）与 `WakeGrant(ctx, ev) error`（内部只用 `ev.WorkspaceID/ev.CrID` 触发 Reconcile，重读 approval_record 为权威），满足 NFR-8 编译兼容或同批调整。
- **双钩分阶段契约（评审 TD-BL-6 修正，取代 SDD 0.2 的“同一回调两次调用”），每次 ACK 每记录至多各一次**：
  1. **预提交 preflight**（UPDATE+入队完成后、COMMIT 前，事务内）：**纯校验钩，零副作用**——不得写任何表、不得发事件/入队任务、不得修改自身状态、不得取与本 ACK 事务行锁相交的锁（只允许只读查询与本地校验，且不得依赖本事务未提交的写入）。返回 error → 整批回滚 → HTTP 5xx。此时 `delivered_at` 未提交，pending 端点（approval.go:351，`delivered_at IS NULL`）下轮仍返回该记录，daemon 15s 重投递重 ACK，preflight 被**真正重放**——FR-10 的“回调 error 影响 ACK HTTP 状态码”由此兑现，且失败不产生任何外部副作用（FR-3 / NFR-1）。
  2. **提交后 wake**（真实唤醒语义）：Runner 的审批判定读 `delivered_at IS NOT NULL`（runner.go ~683，`deliveredTechApproval`），真实 Reconcile 在读取前即会取 advisory lock、写 pipeline_run/pipeline_node_run、可入队 pipeline task（runner.go:238-374）——这些外部提交无法随 ACK 回滚撤销，**违反 multica ARCHITECTURE.md 事务约束“Side effects publish only after committed state”（ARCHITECTURE.md 事务节）与 FR-3 原子边界**，故真实 wake 只能在提交后执行。提交后调用的 error **只记结构化 Error 日志（NFR-10，含 cr_id/stage/decision）**，HTTP 保持 2xx——此时 delivered_at 已落库，pending 端点不再返回该记录，daemon 下轮 fetch（crevents.go:117-122，`len==0` 直接 return）根本不会再发此 ACK，**提交后 5xx 是伪可重试失败**。SDD 0.1 的“重放 ACK 收敛 200”与 0.2 的“同一 Reconcile 预提交调用”均作废。
- 消费方契约：**同一事件在两个钩子里语义不同**——preflight 只回答“这个事件当前能否被消费”（校验型，如参数可解析、stage/decision 合法、消费者处于可接收状态），wake 才执行真实副作用。Runner 的 `WakeGrantPreflight` 实现 = 参数校验（parseUUID + stage ∈ 四键 + decision ∈ {approve, reject}）+ 只读确认存在可唤醒目标，**不调用 Reconcile**；`WakeGrant` = Reconcile（幂等：advisory lock + digest 校验 + 重读 approval_record）。
- Runner 关闭（`AIFIRST_ARCHITECTURE_RUNNER` 未设置，router.go:1399）时回调无人接线，两个钩均零调用，续跑能力完全不依赖 Runner（AC-8）。

## 3.3 sqlc 新查询（内部接口，`server/pkg/db/queries/approval.sql`）

| 查询 | 形态 | 用途 |
|---|---|---|
| `AckApprovalGrants` | `:many`，UPDATE … RETURNING `id::text, cr_id, stage, decision, approver_user_id::text` | FR-3 事务内第一步（现内联 SQL 迁入） |
| `GetCrShellIssueInWorkspaceForKeyShare` | `:one`，`SELECT * FROM cr WHERE workspace_id=$1 AND cr_id=$2 FOR KEY SHARE` | 解析第一步并锁定 cr 权威行（评审 TD-BL-5：并发 `cr.shell_issue_id`/status 投影写等到本事务提交，DD-10） |
| `CreateApprovalContinuationTask` | `:one`，guarded INSERT + `ON CONFLICT DO NOTHING RETURNING *`；`status`（`queued`/`deferred`）与 `fire_at` 参数化 | 事务内第二步（仿 `CreatePipelineTask`，agent.sql:651）；deferred 变体用于 257 让位（§4.3 阶梯 3） |
| `AppendApprovalContinuationEvidence` | `:one`，按 470 键 UPDATE 后继行追加 approvals[]/handoff_note（幂等、ON 不重复追加） | 阶梯 2 原子合并（评审 TD-BL-7，§4.3） |
| `GetApprovalContinuationTaskByRecord` | `:one`，按 (kind, ref_id, 五状态含 running) 读回 | 幂等重读阶梯 1（469 键） |
| `GetApprovalContinuationTaskByCr` | `:one`，按 (kind, cr_id, 四状态排队态) 读回 | 幂等重读阶梯 2（470 键，排队后继判定） |

`CreateApprovalContinuationTask` 的守卫 = 单条 INSERT 内联复核**完整权威链**（评审 TD-BL-2/TD-BL-5）：`JOIN agent a ON a.id=$agent AND a.workspace_id=$ws AND a.archived_at IS NULL AND a.runtime_id IS NOT NULL AND a.kind='user'` ∧ `JOIN issue i ON i.id=$issue AND i.workspace_id=$ws` ∧ `JOIN squad s ON s.id=i.assignee_id AND s.workspace_id=$ws AND s.leader_id=a.id AND s.archived_at IS NULL` ∧ `JOIN cr c ON c.workspace_id=$ws AND c.cr_id=$cr AND c.shell_issue_id=i.id`——任一守卫失败插 0 行（不静默，走 §4.3 阶梯 4 回滚）。resolveContinuationTarget 的读在守卫前**已按固定锁序持有锁**（§4.2/DD-10）：守卫是锁之外的复核兜底，不再承担“防陈旧”的唯一职责（SDD 0.2 只靠语句级快照，评审 TD-BL-5 指出其挡不住 INSERT 后、提交前的并发改）。issue 侧锁读新增 `LockIssueInWorkspaceForKeyShare`（issue.sql，仿既有 `LockIssueForChannelMediaBind` 的 FOR KEY SHARE 惯例，返回整行）；squad/agent 复用既有 `LockSquadForAutopilotAssignment`/`GetAgentForUpdate`。

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
    if outcome ∈ {already-queued, merged, slot-deferred}: log.Info(…, reason=outcome)   # 幂等命中/合并/让位，不报错
    if task 为新建行: tasks += task                       # 仅新建行提交后广播（幂等命中/合并不重复广播）
    ackEvents += GrantAckEvent{ws, row.cr_id, row.id, row.stage, row.decision}
  for ev in ackEvents:                                # 预提交 preflight：纯校验、零副作用（TD-BL-6）
    if onGrantAckPreflight != nil: if err := onGrantAckPreflight(ctx, ev); err: rollback; return 500
  commit                                              # 全部成对落地或回滚（DD-3）
  for task in tasks: taskSvc.NotifyContinuationTaskEnqueued(ctx, task)  # 提交后广播（FR-11；TD-SUG-1）
  for ev in ackEvents:                                # 提交后真实唤醒（TD-BL-6，best-effort）
    if onGrantAck != nil: if err := onGrantAck(ctx, ev); err: log.Error(…, reason=ack-wake-failed)  # 不置 5xx
  return 200 {status: ok}
```

## 4.2 resolveContinuationTarget（FR-7，逐级 fail-closed + 权威锁链，每级一个 NFR-10 原因码）

```text
resolveContinuationTarget(qtx, ws, row):              # 全部读与最终 INSERT 同一事务（qtx）
  # 锁链（评审 TD-BL-5）：固定顺序 cr → issue → squad → agent，先锁后读，权威链稳定到提交
  cr := GetCrShellIssueInWorkspaceForKeyShare(qtx, ws, row.cr_id)  # (ws, cr_id) 双键 + FOR KEY SHARE；查不到 → reason=workspace-mismatch
  if cr.shell_issue_id 为空: return reason=issue-missing
  issue := LockIssueInWorkspaceForKeyShare(qtx, cr.shell_issue_id, ws)  # issue.sql 新查询，FOR KEY SHARE；跨 workspace 漂移/不存在 → issue-missing
  if issue.assignee_type != 'squad' 或 assignee_id 空: return reason=leader-missing
  squad := LockSquadForAutopilotAssignment(qtx, issue.assignee_id, ws)  # squad.sql:14-20，FOR SHARE；与 leader 变更的 FOR UPDATE 互斥
  if squad.archived_at 非空: return reason=leader-missing
  leader := GetAgentForUpdate(qtx, squad.leader_id)   # agent.sql:30-35，FOR UPDATE；与 runtime teardown 互斥 → runtime_id 稳定到提交
  if leader.workspace_id != ws 或 leader.archived_at 非空 或 leader.runtime_id 空: return reason=leader-missing
  return target{agent_id, runtime_id, issue_id, squad_id, project_id}
```

权威路径 = `cr.shell_issue_id → issue(assignee_type='squad').assignee_id → squad.leader_id`（迁移 433 + 084；PRD FR-7 允许的“既有关联”路径），**全程按认证 workspace 作用域**（评审 TD-BL-2）。

**锁链为什么闭合 TD-BL-5（权威链稳定到提交）**：FOR KEY SHARE 是 Postgres 行锁矩阵中最弱、且与任何行 UPDATE 互斥的锁级（UPDATE 取 NO KEY UPDATE/FOR UPDATE，两者均与 FOR KEY SHARE 冲突——锁矩阵事实；本仓既有惯例：`LockIssueForChannelMediaBind` FOR KEY SHARE、迁移 284 owner fence 同锁级）。因此：并发 `issue.assignee_id` 重指派或 `cr.shell_issue_id`/投影写要么在本事务取锁前提交（我们读到新值），要么阻塞到本事务提交后（我们派发的就是 ACK 时点的权威值）——“INSERT 后、提交前被并发改写”的陈旧窗口被锁直接消除，SDD 0.2 只靠 guarded INSERT 语句级快照复核的缺口闭合。锁顺序与既有路径无环：crsync 只写 cr（不组合取 issue/squad/agent 锁）；issue 指派先 UPDATE issue 再 squad/agent；autopilot 取 squad→agent、不触 cr/issue。残余理论死锁（如 workspace teardown 扫描顺序）由 Postgres 死锁检测中止本事务 → 回滚 → 5xx → daemon 诚实重试，无部分效果。任何一级缺失都**不回退到任意 Agent**，整批回滚保持未 ACK，等配置修复后 daemon 重试补发（FR-7/AC-6）。禁止硬编码 agent id/名称。

## 4.3 CreateApprovalContinuationTask 幂等语义（FR-1/FR-4/FR-6；评审 TD-BL-7 修正）

```text
insert: INSERT INTO agent_task_queue(agent_id, runtime_id, issue_id, status, priority, fire_at,
          trigger_summary, squad_id, is_leader_task, handoff_note, context,
          originator_user_id, accountable_user_id, originator_source,
          trigger_evidence_kind, trigger_evidence_ref_id, cr_id, project_id)
        VALUES(…,'queued',NULL,…,true, handoff, approvals[本记录],…,'approval_continuation', record_id, cr_id …)
        ON CONFLICT DO NOTHING RETURNING *;
conflict(0 行) → 幂等重读阶梯（同一事务，阶梯 1/2 只读，阶梯 3 补一条 INSERT）：
  1) GetApprovalContinuationTaskByRecord(record_id)   → 命中：already-queued（同审批重放/并发输家；469 键）
  2) GetApprovalContinuationTaskByCr(cr_id)           → 命中：**原子合并**（470 键：已存在排队后继 → 本次审批四字段并入后继，见下）
  3) 阶梯 1/2 均未命中（唯一残余冲突源 = 257 的 (issue,agent) 占槽，如普通 comment/mention 任务）
     → **让位插入**：同形态 INSERT 但 status='deferred' + fire_at=now()（context 无 channel_issue_media_pending 键
       → 257 谓词外，索引不冲突；469/470 已在阶梯 1/2 排除），ON CONFLICT DO NOTHING RETURNING *；
      0 行（并发竞态输家）→ tx-failure 回滚（daemon 重试，下轮阶梯命中 already-queued，诚实重试）
  4) 全未命中且让位插入失败 → tx-failure 回滚（不静默降级，纪律 1）
```

**阶梯 2 原子合并 = `AppendApprovalContinuationEvidence`（同事务 UPDATE，幂等）**：

```sql
UPDATE agent_task_queue
SET context = jsonb_set(COALESCE(context,'{}'::jsonb), '{approvals}',
          COALESCE(context->'approvals','[]'::jsonb) || $new_entry::jsonb),
    handoff_note = COALESCE(handoff_note,'') || E'\n' || $new_line,
    updated_at = now()
WHERE id = $successor_id
  AND trigger_evidence_kind = 'approval_continuation'
  AND status IN ('queued','deferred','dispatched','waiting_local_directory')   -- 470 谓词
  AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(context->'approvals','[]'::jsonb)) e
                  WHERE e->>'approval_record_id' = $record_id)                -- 幂等：同记录不重复追加
RETURNING *;
```

- 0 行 = 该记录已在此前并入（同记录重放/同批重复）→ `already-queued`，幂等 200；多记录并发合并由行锁串行化：UPDATE 在行锁下重读行当前值，两个并发合并先后提交、各自追加、互不丢失（`NOT EXISTS` 防同记录重复）。同批两审批同 CR（如 requirement+tech-design 同次 crctl approve）：第一记录 INSERT、第二记录 470 冲突 → 阶梯 2 合并，同事务可见自己的未提交 INSERT → 后继 context.approvals[]=2 项、handoff 两行。
- **可达契约（TD-BL-7 逐字段）**：后继本身就是 continuation 任务（无 trigger_comment_id 等五触发字段 → prompt 恒定 assignment 分支，§2.4）。未 dispatch（queued/deferred）的后继：claim 时合并后的 handoff_note 全文逐字进入 opening prompt → 四字段可达；已 dispatch/running 的后继：prompt 已生成、handoff 追加不回改，可达路径 = 该任务运行约定读 `.crctl/grants/`（grant 在 ACK 前落盘，crevents.go deliverGrants 先写后 ACK）→ 新审批 stage/decision 运行时可达；`approval_record_id` 级证明落在后继行 context.approvals[]（grant schema 无该字段、NFR-8 禁改，§2.4 注）。**合并绝不落到普通 comment/mention 任务**：其 prompt 分支不渲染 handoff_note（prompt.go:335-365 `buildCommentPrompt` 只渲染评论内容）且无 grants 读取约定——这正是 SDD 0.2 阶梯 3 的“已 ACK、无可证明续跑载体”缺口（评审 TD-BL-7），已由让位插入（阶梯 3）替代。
- **阶梯 3 让位插入语义**：deferred 行不进 257 谓词（迁移 257 谓词 = queued/dispatched 或带 channel 标志的 deferred），与既有普通任务合法共存；`PromoteDueDeferredTasksForRuntime`（agent.sql:2255-2323）在 (issue,agent) 槽释放后的下一 tick 翻为 queued（被占槽时跳过、不丢：注释明确 “promoted by a later tick once the slot frees, so nothing is lost”）；`ClaimAgentTask` 仅认 queued 且 per-(issue,agent) 串行化（agent.sql:841-862）→ 续跑恒在普通任务之后串行执行，FR-6“不并发唤醒多份”保持。runtime 离线时 deferred 等待（同任何任务，NFR 不新增机制）。
- 阶梯 1/2 对应迁移 469/470 的两条唯一索引（469 键五状态含 running、470 键四状态排队态）；全部命中路径都是“已有 continuation 任务（排队或运行中）携带本次审批的完整证据”这一 FR-1/FR-6 前提下的安全结果，日志 Info 级（NFR-10）。

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
- **Consequences**：新增 5 条 sqlc 查询 + 重跑 sqlc generate；形态与仓库既有 `CreatePipelineTask` 先例（agent.sql:651）同构，评审可对照。

### DD-3 批量 ACK 单事务 all-or-nothing（而非逐记录部分成功）
- **Context**：FR-3"要么都生效要么都不生效"、FR-5"入队失败 ACK 返回 HTTP 错误"。
- **Alternatives**：逐 id 独立事务 + 响应携带 per-id 结果——daemon 侧需解析部分成功语义，超出"daemon 零改动"边界。
- **Consequences**：任一记录失败整批回滚、整批重投递（幂等写文件无害）；坏记录（如 leader 未配置）会连带阻塞同批健康 grant，直至配置修复——该 trade-off 由 FR-7"保持未 ACK 等待配置修复"显式背书，5xx 响应体 reasons 列表即为运维修复指引（NFR-10）。评审需确认此残余风险可接受。

### DD-4 双 partial unique index（ref_id 五态 + cr_id 排队四态）而不是应用层检查兜底
- **Context**：FR-4 键 = approval_record.id（幂等，含 running：同记录任何时刻只一条任务）；FR-6 键 = CR 的**排队后继**上限（queued/deferred/dispatched/waiting_local_directory，**不含 running**——running 被纳入会使运行期到达的下一次审批被判 already-queued 吞掉，SDD 0.1 自认的窄窗即源于此，评审 TD-BL-4）；应用层检查存在并发竞态窗口。
- **Alternatives**：仅应用层 COUNT 检查——两个并发 ACK（不同 stage 同 CR）都会通过检查，产生两条续跑任务，违反 AC-5；把 running 纳入 470——运行中任务之后无排队后继，窄窗审批丢唤醒，违反 FR-6 与 100% 命中目标；向运行中沙箱注入事件——PRD 明令禁止（FR-6）。
- **Consequences**：两条单语句 CONCURRENTLY 迁移（仓库惯例，ARCHITECTURE §5.6）；INSERT 的 ON CONFLICT DO NOTHING + 重读阶梯（469 幂等重读 / 470 原子合并 / 257 让位 deferred 插入，§4.3）；排队后继与运行中任务不并发执行由 ClaimAgentTask 的 per-(issue,agent) 串行化保证（agent.sql:841-862）。

### DD-5 onGrantAck 拆为双钩：预提交 preflight（纯校验）+ 提交后 wake（而非同一回调两次调用）
- **Context**：FR-10 要求回调携带 id/stage/decision 且可返回 error；error 契约必须落在可回滚的原子边界内——提交后 5xx 是伪可重试失败（pending 端点按 `delivered_at IS NULL` 过滤，approval.go:351；daemon 对已交付记录不再重发 ACK，crevents.go:117-122）。SDD 0.2 为兼顾“error→5xx”与“唤醒需提交后”，把同一个 `Runner.WakeGrant/Reconcile` 在 COMMIT 前调一次——但真实 Reconcile 在读取 `delivered_at` 前就会取 advisory lock、写 pipeline_run/pipeline_node_run、可入队 pipeline task（runner.go:238-374），这些外部提交不随 ACK 回滚撤销，违反 multica ARCHITECTURE.md“Side effects publish only after committed state”与 FR-3 原子边界（评审 TD-BL-6）。
- **Alternatives**：保留旧回调 + 新增第二个回调——双通道并存，Runner 未来开启时语义分叉；单次提交后调用 + error→5xx——SDD 0.1 方案，制造虚假重试，作废；把 Reconcile 重构成“先校验后副作用”两段式——侵入 Runner 状态机，且校验段与 ACK 事务视图无法对齐；真实持久化重试（notified_at 列 + 服务端扫描）——NFR-4 禁止新重试框架，且唯一消费方 Runner 默认关闭，成本不成比例。
- **Consequences**：钩拆为 `SetGrantAckPreflight`（预提交、契约上零副作用：不写表/不发事件/不取交叉锁；error → 回滚 → 5xx → daemon 真实重试，FR-10 兑现）与 `SetGrantAckHandler`（提交后真实唤醒，error → Error 日志、HTTP 2xx）。唯一消费方 Runner 提供 `WakeGrantPreflight`（参数校验 + 只读目标确认，不调 Reconcile）与 `WakeGrant`（Reconcile，幂等）；每 ACK 每记录至多各一次调用。Runner 关闭时两钩均零调用。新增测试：preflight 失败零外部副作用（§7.4 AC-9b/9d）。

### DD-9 257 占槽时以 deferred 让位插入（而非向普通任务合并证据）
- **Context**：`idx_one_pending_task_per_issue_agent_v2`（迁移 257）谓词 = queued/dispatched 或带 `channel_issue_media_pending` 标志的 deferred。leader 的 (issue, agent) 槽被普通 comment/mention 任务占用时，`status='queued'` 的续跑 INSERT 冲突。SDD 0.2 将其判为 already-queued 跳过——但普通任务的 `buildCommentPrompt` 不渲染 handoff_note、无 grants 读取约定，跳过即“已 ACK、无可证明续跑载体”（评审 TD-BL-7）。
- **Alternatives**：把证据合并进普通任务行——prompt 不可达（上）；取消/顶掉普通 pending 任务——破坏既有任务归属（MUL-4302），越权；savepoint 重试——Postgres 23505 后需 savepoint 才能续事务，增加复杂度且无收益；为普通任务补 grants 读取约定——侵入全部 prompt 契约，超出本 CR 边界。
- **Consequences**：插入参数化 status/fire_at；257 冲突路径改插 `deferred + fire_at=now()`（谓词外，索引不冲突）；既有 `PromoteDueDeferredTasksForRuntime`（agent.sql:2255-2323）在槽释放后自动翻 queued（被占槽时跳过、不丢），`ClaimAgentTask` per-(issue,agent) 串行化保证顺序执行——FR-6 保持，零新增机制、零 prompt 侵入。可观测性新增 `slot-deferred`（Info）原因码。

### DD-10 权威锁链 cr→issue→squad→agent（FOR KEY SHARE 起步，先锁后读）
- **Context**：SDD 0.2 只锁 squad/agent，cr/issue 靠普通 SELECT + guarded INSERT 的语句级快照复核——单语句快照挡不住“INSERT 后、提交前”并发改 `cr.shell_issue_id`/`issue.assignee_id`，仍可能向旧 shell issue/旧 squad leader 落任务（评审 TD-BL-5）。
- **Alternatives**：SERIALIZABLE 隔离——全库语义切换不可控，且 Postgres 需重试循环，超范围；把全部权威校验塞进单条 INSERT——语句级快照仍不持锁，不闭合；应用层悲观锁表——引入新锁基础设施，违反 NFR-4。
- **Consequences**：新增 2 条锁读查询（`GetCrShellIssueInWorkspaceForKeyShare`/`LockIssueInWorkspaceForKeyShare`，FOR KEY SHARE = 与任何行 UPDATE 互斥的最弱锁级，本仓既有惯例：`LockIssueForChannelMediaBind`、迁移 284 owner fence）；固定锁序 cr→issue→squad→agent，先锁后读，与既有路径（crsync 只写 cr；issue 指派 issue→squad→agent；autopilot squad→agent）无环；guarded INSERT 全链 join 保留为复核兜底；新增并发 reassignment/projection race 集成测试（§7.4 AC-6b/6c）。ACK 为低频路径，短事务内多 2 次点锁读，无热路径影响（§7.2）。

### DD-11 排队后继的幂等原子合并（approvals[] 追加 + handoff 追加行）
- **Context**：SDD 0.2 阶梯 2 对已存在的排队后继仅判 already-queued，本次审批四字段不并入，与 TD-BL-7 的“无可证明续跑载体”同源：排队后继后续 ACK 的证据应落在它身上，否则后继运行时只能靠 grants 目录推断、拿不到 approval_record_id。
- **Alternatives**：每个审批必插一条任务（放宽 470 到不含任何活跃态）——违反 FR-6 单后继上限；给 grant 文件加 approval_record_id——违反 NFR-8（grant schema v1 不变）；单独建 evidence 表——新表 + 新读路径，超出 FR-11 复用展示面。
- **Consequences**：`AppendApprovalContinuationEvidence` 同事务 UPDATE：`context.approvals[] || new_entry` + `handoff_note` 追加行 + `NOT EXISTS` 防同记录重复（幂等）；行锁串行化并发合并；未 dispatch 后继经 opening prompt 逐字可达、已 dispatch 后继经 grants 目录运行时可达（record-id 级证明在后继行，§4.3/§2.4 注）。同批多审批同 CR 自然折叠成一条后继多份证据。

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
| FR-3 原生原子事务 | §4.1：pgx `pool.Begin` + `queries.WithTx`，delivered_at 与入队同一 commit；失败回滚不标记 delivered_at；预提交钩只有零副作用 preflight（§3.2），提交后才有事件/唤醒 |
| FR-4 窄唯一约束防重复唤醒 | 迁移 469 + §4.3 阶梯 1 |
| FR-5 ACK 失败语义与 daemon 重试 | §4.1（5xx 仅来自预提交失败：tx 错误或 preflight error → 回滚保持 pending）+ §1.2（crevents.go 既有 15s 重投递，零改动）+ §3.1 错误体；提交后 wake error 不置 5xx（§3.2） |
| FR-6 同 CR 最多一个后继，不注入事件 | 迁移 470（排队四态，不含 running）+ §4.3 阶梯 2/3：排队后继存在→原子合并；普通任务占槽→deferred 让位插入（不并发唤醒、不注入沙箱）；运行中任务后允许 1 条持久化排队后继，ClaimAgentTask per-(issue,agent) 串行化保证不并发执行 |
| FR-7 leader 解析 fail-closed | §4.2 逐级解析（workspace-scoped + 权威锁链 cr→issue→squad→agent）+ 四类原因码；§3.1 reasons 响应体 |
| FR-8 只处理新 ACK | UPDATE 谓词 `delivered_at IS NULL`（既有行为原样保留），无回填路径 |
| FR-9 不复制状态机语义 | §2.4：context JSON（approvals[] 数组，机器可读）+ handoff_note（prompt 实际载体，仅 CR/stage/decision/record 引用，无下一步映射）+ §3.2 回调；Multica 侧无任何“状态→下一步”映射 |
| FR-10 ACK 回调数据补齐 | §3.2 GrantAckEvent + 双钩契约（预提交 preflight error→5xx 真实重试且零副作用；提交后 wake error→日志）+ Runner.WakeGrantPreflight/WakeGrant 同批调整（DD-5） |
| FR-11 复用既有展示面 | §2.4（复用 agent_task_queue 全部既有列）+ NotifyContinuationTaskEnqueued 广播（broadcastTaskEvent+NotifyTaskEnqueued，§1.3/§4.1）；无新状态列/新投影 |
| FR-12 audit-drift 去重修复 | §4.4 comparable() 剥离 detected_at（DD-6）；不改事件内容与文件名规则 |

**FR 覆盖率：12/12**。

# 7. 安全与性能考量

## 7.1 边界条件与安全

- **workspace 隔离**：续跑目标解析全部以 ACK 的 daemon workspace 为根且逐级 workspace-scoped（`GetCrShellIssueInWorkspaceForKeyShare`/`LockIssueInWorkspaceForKeyShare`/`GetSquadInWorkspace` + agent workspace 显式校验 + guarded INSERT 全链 workspace join），shell_issue_id 跨 workspace 漂移一律 0 行 fail-closed；跨 workspace 同名 CR 不可能被唤醒（对照既有 `TestApprovalCardDoesNotLeakEvidenceAcrossWorkspaces` 的防护口径）。
- **越权与陈旧 leader（评审 TD-BL-5 闭合）**：leader 解析走 issue→squad 关联，读-写全程同事务 + **权威锁链 cr→issue→squad→agent 固定顺序先锁后读**（`GetCrShellIssueInWorkspaceForKeyShare`/`LockIssueInWorkspaceForKeyShare` FOR KEY SHARE + 既有 `LockSquadForAutopilotAssignment` FOR SHARE / `GetAgentForUpdate` FOR UPDATE，§4.2/DD-10）：并发重指派 `issue.assignee_id`、投影改 `cr.shell_issue_id`、leader 变更与 runtime 解绑要么在本事务取锁前提交（读到新值），要么阻塞到本事务提交后——陈旧权威窗口消除，不再只靠 guarded INSERT 语句级快照；guarded INSERT 全链 join（`squad.leader_id = agent.id` 等）保留为复核兜底；无 leader 一律失败，不回退任意 Agent（FR-7）；不新增开放端点，ACK 鉴权不变（NFR-12）。
- **并发**：两条 partial unique index 是并发竞态的硬兜底；`ON CONFLICT DO NOTHING` 输家走幂等重读，绝不 5xx；排队后继与运行中任务不并发执行（ClaimAgentTask 串行化）。
- **历史数据**：无回填迁移；旧 `delivered_at` 非空行天然不进 UPDATE 结果集（FR-8/AC-7）。
- **回调失败**：预提交 preflight error → 回滚 → delivered_at 保持 NULL → daemon 真实重试，且 preflight 契约上零外部副作用（§3.2 阶段 1/DD-5）；提交后 wake error → Error 日志、HTTP 2xx、无重复任务、不伪重试（§3.2 阶段 2）。

## 7.2 性能

- ACK 为低频人工触发路径；单事务内完成 1 次 UPDATE + 每记录至多 4 次点查（含 2 次 FOR KEY SHARE 锁读）+ 1 次 INSERT（或 1 次合并 UPDATE / 1 次 deferred 让位插入），无轮询/后台扫描（NFR-5）。锁链只在短事务内持有；crsync 的 cr 投影写若与 ACK 同瞬竞争会等待锁释放，量级毫秒、无热路径影响。
- daemon 侧零改动、零新增往返（NFR-6）；续跑任务与普通任务共用队列与 reclaim 机制。
- tools 侧：`comparable()` 仅多一次对象浅拷贝，仅 dedup 名命中时执行，无热路径影响。

## 7.3 可观测性（NFR-10 原因码全集）

| reason | 触发 | 日志级 |
|---|---|---|
| `workspace-mismatch` | (ws, cr_id) 无投影行 | Error |
| `issue-missing` | shell_issue_id 为空 | Error |
| `leader-missing` | 非 squad 指派 / 无 squad / leader 缺失或未绑定 runtime | Error |
| `already-queued` | 幂等重读阶梯命中（同记录重放 / 已合并记录重放） | Info |
| `merged` | 阶梯 2 原子合并完成（本次审批四字段已并入排队后继） | Info |
| `slot-deferred` | 阶梯 3 让位插入（(issue,agent) 槽被普通任务占用，续跑任务以 deferred 排队等待槽释放） | Info |
| `tx-failure` | 重读阶梯全未命中且让位插入失败或事务错误 | Error |
| `ack-preflight-failed` | 预提交 preflight 返回 error（整批回滚，daemon 重试） | Error |
| `ack-wake-failed` | 提交后 wake（真实唤醒）返回 error | Error（HTTP 仍 2xx，§3.2 阶段 2） |

所有日志携带 cr_id、stage、decision、reason；5xx 响应体 reasons 列表同源（§3.1）。

## 7.4 测试设计（AC 映射）

**multica（Go，DB 集成测试贴包）**：
- `server/internal/governance/approval_continuation_test.go`（新）：AC-1（同记录双 ACK/并发 → 恰 1 条）；AC-2（四 stage × approve/reject 各 1 条，reject 任务 handoff_note 与 context.approvals[] 含 decision=reject）；AC-3（注入事务失败 → delivered_at 仍 NULL + 5xx + 重放成功）；AC-5a（CR 已有 running 续跑任务 → ACK 另一 stage → 新增恰 1 条 queued 后继，运行中任务事件流无注入）；AC-5b（已有排队后继 → ACK 第三 stage → 后继仍为 1、context.approvals[] 恰增 1 项且四字段与 approval_record 行一致、幂等 200）；AC-5c（窄窗集成：running 任务已读 grants 后下一审批才落盘 → 排队后继在 running 完成后被 claim 且读到新 grant）；**AC-5d（TD-BL-7 阶梯 3）**：leader 的 (issue, agent) 槽被普通 comment/mention 任务占用 → ACK → 新增 continuation 任务 status='deferred'（fire_at 已到期）、普通任务行零改动；槽释放后 `PromoteDueDeferredTasksForRuntime` 翻 queued → claim → opening prompt 四字段逐字可达；**AC-5e（TD-BL-7 同批多审批）**：同批两审批同 CR → 恰 1 条后继、approvals[]=2 项、handoff 两行、ref_id=第一记录；**AC-5f（TD-BL-7 合并幂等）**：对已合并记录再次 ACK → 0 新任务、approvals[] 不重复追加、200；AC-6（三种 leader 缺失形态 → 未 ACK + 原因码，配置恢复后重试成功；另加跨 workspace shell_issue_id → fail-closed 用例）；**AC-6b（TD-BL-5 reassignment race）**：ACK 事务持锁期间并发 `UPDATE issue SET assignee_id`（阻塞到 ACK 提交或反之）→ 两种串行化顺序下续跑任务的 issue/squad/leader 均与“ACK 提交时点的权威链”一致，无旧 leader 派发；**AC-6c（TD-BL-5 projection race）**：并发 `UPDATE cr SET shell_issue_id`/status 投影写被 FOR KEY SHARE 串行化（同前断言；cr 写路径当前生产未启用 shell_issue_id 写，测试直接构造 UPDATE 以固化契约）；AC-7（已交付记录 0 任务）；AC-8（context/handoff_note 无映射字段 + Runner 未接线时 ACK 仍成功）；AC-9a（GrantAckEvent 字段与 approval_record 行一致）；**AC-9b（TD-BL-6）**：preflight 返回 error → 5xx + delivered_at 全 NULL + **零外部副作用**（断言 pipeline_run/pipeline_node_run 零新行、agent_task_queue 除回滚的 continuation 外零新行、无事件广播）+ 重放成功且 preflight 再次被调；**AC-9c**：wake（提交后）返回 error → 2xx + Error 日志 + 无重复任务 + 重放 ACK 不再触发任何回调；**AC-9d（TD-BL-6 契约边界）**：注册一个“写表/发事件的 preflight”在测试断言层被拒绝或文档契约检查覆盖（静态约定 + 单测锁定 preflight 实现不触碰写路径）；AC-10（审批表无新列断言可并入迁移评审）。
- `server/internal/daemon/prompt_test.go`（扩展现有 handoff 用例，锁定 TD-BL-1/TD-BL-7 端到端送达）：续跑任务的 handoff_note 内容逐字出现在 opening prompt（assignment 分支）；**合并后多行 handoff 在未 dispatch 后继上逐字出现**；claim 集成断言 `Task.HandoffNote` 含 cr_id/stage/decision/approval_record_id 四字段（含合并追加行）。
- `server/internal/daemon/`（既有 deliverGrants 假 fetcher 测试扩展）：AC-4（ACK 返回 5xx → grants 保持 pending → 下一周期重投递成功）。

**tools（node --test）**：扩展 `skills/shared/crctl/scripts/test/crctl.test.mjs` 既有 drift 用例（:776）：AC-11（连续两次观测 → audit-drift 文件恰 1、无 EMIT_FAILED 审计行、第二次幂等返回）；AC-12（删除文件后再观测 → 新文件按窗口计数；不同 CR/不同摘要不误合并；同名内容真实变化仍冲突）。

**验证顺序**：sqlc generate → `go test ./server/internal/governance/... ./server/internal/daemon/...`；tools 侧 `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`。

## 7.5 残余风险（随评审确认）

1. **DD-3 批次联动阻塞**：坏 grant（leader 未配置）会阻塞同批其余 grant 的 ACK，直至配置修复。FR-7 显式背书该 fail-closed 语义；若评审认为不可接受，可后续追加 daemon 逐 grant ACK 的独立 CR（不在本 CR 范围）。
2. **排队后继的合并语义（TD-BL-7 闭合后）**：运行中任务期间到达的审批并入排队后继（阶梯 2 合并，AC-5b/5e/5f）；后继运行时读 `.crctl/grants/` 覆盖全部已 ACK grant（grant 先于 ACK 落盘）。残余窄窗仅剩“后继被 claim 瞬间与下一 grant 落盘竞态”——若新 grant 的 ACK 早于后继读取 grants 目录，后继会一并读到；若晚于，该 ACK 会产生新的排队后继（470 谓词释放）——链式衔接，不再需要人工 @（SDD 0.1 自认的窄窗已关闭，评审 TD-BL-4）。已 dispatch 后继的 handoff 追加不回改其 prompt（prompt 已生成），record-id 级证据落在后继行 context.approvals[]、运行时路由依赖 grants 目录的 stage/decision——这是 NFR-8（grant schema v1 不变）下的既有事实，非新增缺口。
3. **257 占槽的让位延迟（TD-BL-7 闭合后）**：普通 pending 任务占用 (issue, agent) 槽时，续跑以 deferred 排队，等槽释放后由 sweeper 翻 queued——续跑发生在普通任务之后，符合 FR-6 串行化语义；runtime 离线时 deferred 等待（与任何 deferred 任务一致，不新增机制）。极端情形（普通任务长期 running）下续跑被推迟到其完成——这是“不并发唤醒、不注入沙箱”的直接结果，非缺陷。
4. **双钩回调的消费方约束（TD-BL-6 闭合后）**：preflight 契约上零副作用（不写表/不发事件/不取交叉锁），wake 才是真实副作用执行者；同一事件每 ACK 至多被两钩各调一次。若未来新增非幂等消费方或需要在 preflight 做读写，须先扩展该契约（当前唯一消费方 Runner 满足，§3.2）。
5. **权威锁链的竞争面（TD-BL-5 闭合后）**：FOR KEY SHARE 锁在短事务内持有，阻塞面仅限并发 cr 投影写/issue 重指派/leader 变更——低频路径，等待毫秒级；残余理论死锁由 Postgres 死锁检测中止本事务 → 5xx → daemon 诚实重试（无部分效果）。

# 8. Prompt 采纳影响

**本节省略（条件不满足）**。判定依据（CR-2026-021 FR-25/AC-15）：本 CR 的 tools 侧 diff 仅触及 `crctl.mjs` 内 `emitOutboxEvent` 的 `comparable()` 比较逻辑（§4.4），**不触及** `crctl.mjs` 的 dispatch 分支、**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`——crctl 命令面与 guard deny 面均无新增/变更，无任何 skill 提示词需要改为调用新增/扩展子命令，故无需列出采纳清单。

# 9. 修订记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-08-27 | 初稿（write-tech-design 首轮） |
| 0.2 | 2026-08-27 | reviewLoop attempt 1 回修（quality-reviewer-agent 4 blocker，canonical `review-annotations/sdd.yml`，subject SHA `7e55be83…`）：TD-BL-1 上下文改经 handoff_note 送达 prompt（§2.4、DD-8）；TD-BL-2 解析全链 workspace-scoped + 锁对 + guarded JOIN 复核（§3.3/§4.2/§7.1）；TD-BL-3 回调两阶段契约（§3.2/§4.1、DD-5）；TD-BL-4 迁移 470 排除 running、持久化排队后继（§2.3/§4.3、DD-4、§7.4-7.5）；另采纳 TD-SUG-1（复用 broadcastTaskEvent+NotifyTaskEnqueued 顺序，§1.3/§4.1）与 TD-SUG-2（is_leader_task=true + overlay 留空说明，§2.4） |
| 0.3 | 2026-08-27 | reviewLoop attempt 2 回修（quality-reviewer-agent 3 blocker + 2 suggestions，canonical `review-annotations/sdd.yml`，subject SHA `57ab2fe8…`）：TD-BL-5 权威锁链 cr→issue→squad→agent 固定锁序先锁后读（新查询 `GetCrShellIssueInWorkspaceForKeyShare`/`LockIssueInWorkspaceForKeyShare` FOR KEY SHARE，§3.3/§4.2/§7.1，DD-10）+ reassignment/projection race 测试（AC-6b/6c）；TD-BL-6 回调拆双钩（`SetGrantAckPreflight` 预提交零副作用校验 + `SetGrantAckHandler` 提交后真实唤醒，§3.2/§4.1，DD-5）+ 零副作用与契约边界测试（AC-9b/9d）；TD-BL-7 阶梯 2 改为幂等原子合并（`AppendApprovalContinuationEvidence`：approvals[] 追加 + handoff 追加行 + NOT EXISTS 幂等，§4.3/§2.4，DD-11）、阶梯 3 改为 deferred 让位插入（257 谓词外 + `PromoteDueDeferredTasksForRuntime` 槽释放后翻 queued，§2.3/§4.3，DD-9）+ 冲突路径逐字段可达测试（AC-5d/5e/5f、prompt 层合并 handoff）；另采纳 TD-SUG-3（handoff 模板直接用 `{cr_id}` 原值，免 `CR-CR-` 双前缀）与 TD-SUG-4（context 升级为 approvals[] 可追加结构并固化 prompt 分支保证，§2.4/DD-8） |
