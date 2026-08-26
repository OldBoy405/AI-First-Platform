---
id: CR-2026-052-sdd
type: SDD
cr-ref: CR-2026-052
title: Multica 审批后自动续跑 + audit-drift 去重修复 技术设计
status: draft
created: 2026-08-27T01:47:00+08:00
updated: 2026-08-27T01:47:00+08:00
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
       │    AckApprovalGrants / CreateApprovalContinuationTask /
       │    GetApprovalContinuationTaskByRecord / GetApprovalContinuationTaskByCr
       ├─ 复用既有 GetCr / GetIssue / GetSquad / GetAgent / HasActiveTaskForIssue
       └─ service.TaskService（新方法，FR-11 事件广播唯一通道）
            EnqueueApprovalContinuation(ctx, qtx, spec)   // 纯 DB 写入（事务内）
            PublishTaskEnqueued(ctx, task)                // 提交后事件广播（抽取自 EnqueuePipelineTask）
server/migrations/
  ├─ 469_approval_continuation_record_active_unique.up/down.sql   // FR-4
  └─ 470_approval_continuation_cr_active_unique.up/down.sql       // FR-6
server/cmd/server/router.go
  └─ NewApprovalServiceFromEnv(pool, queries, taskSvc) 依赖注入（两处调用点同步）
server/internal/governance/runner.go
  └─ WakeGrant 适配新回调签名 GrantAckEvent（DD-5，唯一消费方同批调整）
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
             resolveContinuationTarget（FR-7 fail-closed，逐级结构化原因）
             CreateApprovalContinuationTask（guarded INSERT；ON CONFLICT 输家幂等重读）
         COMMIT
         （提交后）TaskService.PublishTaskEnqueued 广播 EventTaskQueued
         （提交后）onGrantAck(GrantAckEvent{…}) 唤醒回调（Runner 关闭时无人消费）
       → 2xx：全部记录的 delivered_at 与续跑任务已成对落地（或幂等命中）
       → 5xx：整批回滚，delivered_at 保持 NULL，daemon 15s 后重投递（FR-5）
  → 续跑任务 = agent_task_queue 一条普通任务（trigger_evidence_kind='approval_continuation'）
      归属 CR leader（cr-coordinator-agent），落点 shell issue
      上下文仅 {cr_id, stage, decision, approval_record_id}（FR-9，无状态机映射）
  → 被唤醒 Agent 自行读 .crctl/grants/ 与 crctl status/next 路由下一步（FR-9）
```

# 2. 数据模型

## 2.1 表变更总览

| 表 | 变更 | 依据 |
|---|---|---|
| `approval_record` | **零结构变更**（AC-10）；`HandleGrantsAck` 的 UPDATE `RETURNING` 扩展为 `id, cr_id, stage, decision, approver_user_id`（现仅 `cr_id`，approval.go:392-395） | 迁移 433 已有全部所需列（stage/decision/delivered_at/approver_user_id） |
| `agent_task_queue` | **零列变更**；新增两条 partial unique index（迁移 469/470），复用既有 `trigger_evidence_kind`/`trigger_evidence_ref_id`（迁移 184）与 `cr_id`（迁移 437）列 | FR-4/FR-6；PRD A4/A5 |

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

## 2.3 迁移 470 — 同 CR 最多一个未完成续跑后继（FR-6）

```sql
-- 470_approval_continuation_cr_active_unique.up.sql（单语句）
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_approval_continuation_cr_active
    ON agent_task_queue (cr_id)
    WHERE trigger_evidence_kind = 'approval_continuation'
      AND status IN ('queued', 'deferred', 'dispatched', 'waiting_local_directory', 'running');
-- 470_…down.sql
DROP INDEX CONCURRENTLY IF EXISTS idx_approval_continuation_cr_active;
```

活跃状态口径 = 迁移 443 `idx_agent_task_queue_pipeline_node_active` 的 canonical 五状态集合，原样沿用（PRD FR-6 明示"沿用仓库既有 active-status 口径并在 SDD 明确"，此处即明确）。两条索引 WHERE 谓词一致、键不同（ref_id vs cr_id），语义互补不冲突；终端状态（completed/failed/cancelled）不在 WHERE 内，故续跑任务完成后同一 CR 的下一审批可正常再入队（AC-2 四阶段顺序流转依赖此点）。

另需注意既有 `idx_one_pending_task_per_issue_agent_v2`（迁移 257，(issue_id, agent_id) pending 唯一）：若 leader 在该 issue 上已有 pending 任务，续跑 INSERT 会命中该索引冲突——按 §4.2 的幂等重读阶梯处理为 already-queued（该任务运行时 Agent 同样会重读 crctl 状态，不并发唤醒多份，符合 FR-6 意图）。

## 2.4 续跑任务行形状（复用既有列，无新列）

| 列 | 值 | 说明 |
|---|---|---|
| `agent_id` / `runtime_id` | CR leader agent 及其 runtime | FR-7 解析结果 |
| `issue_id` | `cr.shell_issue_id` | 既有投影关联（迁移 433） |
| `status` | `queued` | 走既有 claim 路径 |
| `priority` | `priorityToInt(issue.Priority)` | 与 mention 任务一致（task.go:1472） |
| `trigger_evidence_kind` / `trigger_evidence_ref_id` | `'approval_continuation'` / `approval_record.id` | 直接证据指针（迁移 184 语义），AC-1 断言键 |
| `cr_id` | approval_record.cr_id | 迁移 437 列 |
| `context` | `{"type":"approval_continuation","schema":"ai-first.approval-continuation/v1","cr_id","stage","decision","approval_record_id"}` | FR-9 最小上下文；**不含任何状态→下一步映射**（AC-8） |
| `trigger_summary` | `"CR-{cr} approval {stage}: {decision}"` | 展示与 brief 注入 |
| `squad_id` | issue 的 squad id | 归因钩子（迁移 127 列） |
| `originator_user_id` / `accountable_user_id` | `approver_user_id` | DD-7：审批人是真实人工动作主体，不伪造归因（NFR-12） |
| `originator_source` | `'direct_human'` | attribution 既有词汇表（attribution.go:26-60），不新增 source 标签 |

# 3. 接口契约

## 3.1 HTTP：POST /api/daemon/approvals/ack（既有端点，语义升级）

- 请求不变：`{"ids": ["<approval_record.id>", …]}`（daemon 侧零改动，NFR-6）。
- 成功（2xx，所有匹配记录均完成「delivered_at + 续跑任务」成对落地或幂等命中）：`{"status":"ok"}` 形态不变。
- 失败（5xx，任一记录 resolve/入队失败 → 整批回滚）：新增结构化错误体，供运维检索（NFR-10）：

```json
{"error":"approval continuation failed",
 "reasons":[{"cr_id":"CR-2026-052","stage":"tech-design","reason":"leader-missing"}]}
```

- 幂等重放：已交付记录再 ACK → UPDATE 匹配 0 行 → 200（沿用现有 0 行分支行为）。
- 鉴权不变：仍经 `resolveDaemonWorkspace`（DaemonAuth 组，NFR-12），请求体 ids 无法越权指定 workspace。

## 3.2 Go 回调：GrantAckEvent（FR-10）

```go
// server/internal/governance/approval.go
type GrantAckEvent struct {
    WorkspaceID string // daemon workspace
    CrID        string
    RecordID    string // approval_record.id（text 形态，与 pending 端点一致）
    Stage       string // requirement | tech-design | dev-start | code
    Decision    string // approve | reject
}
// SetGrantAckHandler(fn func(context.Context, GrantAckEvent) error)
```

- 由 `func(context.Context, string, string)` 变更而来；**唯一消费方** `Runner.WakeGrant`（runner.go:767）同批调整为 `func(ctx, ev GrantAckEvent) error`，内部仍只用 `ev.WorkspaceID/ev.CrID` 触发 Reconcile（重读 approval_record 为权威），满足 NFR-8 编译兼容或同批调整。
- 回调在事务提交后按记录逐个调用；返回 error 时 HTTP 置 5xx——此时 delivered_at 已落库，daemon 重放 ACK 走 0 行幂等分支收敛为 200，不会重复入队（AC-1）。
- Runner 关闭（`AIFIRST_ARCHITECTURE_RUNNER` 未设置，router.go:1399）时回调无人接线，续跑能力完全不依赖 Runner（AC-8）。

## 3.3 sqlc 新查询（内部接口，`server/pkg/db/queries/approval.sql`）

| 查询 | 形态 | 用途 |
|---|---|---|
| `AckApprovalGrants` | `:many`，UPDATE … RETURNING `id::text, cr_id, stage, decision, approver_user_id::text` | FR-3 事务内第一步（现内联 SQL 迁入） |
| `CreateApprovalContinuationTask` | `:one`，guarded INSERT + `ON CONFLICT DO NOTHING RETURNING *` | 事务内第二步（仿 `CreatePipelineTask`，agent.sql:651） |
| `GetApprovalContinuationTaskByRecord` | `:one`，按 (kind, ref_id, active) 读回 | 幂等重读阶梯 1 |
| `GetApprovalContinuationTaskByCr` | `:one`，按 (kind, cr_id, active) 读回 | 幂等重读阶梯 2 |

guarded INSERT 的守卫与 `CreatePipelineTask` 同构：agent 必须 `archived_at IS NULL AND runtime_id IS NOT NULL`、cr 投影存在、issue 存在——守卫不满足插 0 行。

## 3.4 tools 侧：无外部接口变化（NFR-9）

outbox 事件文件 schema（`v`/`event_kind`/`cr_id`/`payload` 等）与 `dedup_name` 生成规则均不变，仅 `emitOutboxEvent` 内部 `comparable()` 对 payload 的比较剔除 `detected_at`（DD-6）。采集端（daemon）无感知。

# 4. 关键算法与流程

## 4.1 HandleGrantsAck（multica 侧核心，伪代码）

```text
HandleGrantsAck(req {ids}):
  ws := resolveDaemonWorkspace(r)                    # 既有鉴权，403 不变
  tx  := pool.Begin(ctx)                             # pgx 原生事务（FR-3）
  qtx := queries.WithTx(tx)
  rows := qtx.AckApprovalGrants(ctx, ws, ids)        # UPDATE … RETURNING 六字段
  ackEvents, tasks := [], []
  for row in rows:
    target, reason := resolveContinuationTarget(qtx, ws, row)   # FR-7 fail-closed
    if target == nil:
      log.Warn("approval continuation skipped", cr, stage, decision, reason)
      rollback; return 500 {error, reasons:[…]}       # delivered_at 保持 NULL（FR-5）
    task, skip := taskSvc.EnqueueApprovalContinuation(ctx, qtx, spec(row, target))
    if skip == already-queued: log.Info(…, reason=already-queued)   # 幂等命中，不报错
    tasks += task; ackEvents += GrantAckEvent{ws, row.cr_id, row.id, row.stage, row.decision}
  commit                                              # 全部成对落地或回滚（DD-3）
  for task in tasks: taskSvc.PublishTaskEnqueued(ctx, task)   # 提交后广播（FR-11）
  for ev in ackEvents:
    if onGrantAck != nil: if err := onGrantAck(ctx, ev); err: return 500   # 重放收敛为 200
  return 200 {status: ok}
```

## 4.2 resolveContinuationTarget（FR-7，逐级 fail-closed，每级一个 NFR-10 原因码）

```text
resolveContinuationTarget(qtx, ws, row):
  cr := GetCr(ws, row.cr_id)                          # 查不到 → reason=workspace-mismatch
  if cr.shell_issue_id 为空: return reason=issue-missing
  issue := GetIssue(cr.shell_issue_id)
  if issue.assignee_type != 'squad' 或 assignee_id 空: return reason=leader-missing
  squad := GetSquad(issue.assignee_id)                # 查不到 → reason=leader-missing
  leader := GetAgent(squad.leader_id)
  if leader.archived_at 非空 或 leader.runtime_id 空: return reason=leader-missing
  return target{agent_id, runtime_id, issue_id, squad_id, project_id}
```

权威路径 = `cr.shell_issue_id → issue(assignee_type='squad').assignee_id → squad.leader_id`（迁移 433 + 084；PRD FR-7 允许的"既有关联"路径）。任何一级缺失都**不回退到任意 Agent**，整批回滚保持未 ACK，等配置修复后 daemon 重试补发（FR-7/AC-6）。禁止硬编码 agent id/名称。

## 4.3 CreateApprovalContinuationTask 幂等语义（FR-1/FR-4/FR-6）

```text
insert: INSERT INTO agent_task_queue(agent_id, runtime_id, issue_id, status, priority,
          trigger_summary, squad_id, context, originator_user_id, accountable_user_id,
          originator_source, trigger_evidence_kind, trigger_evidence_ref_id, cr_id, project_id)
        VALUES(…,'queued',…,'approval_continuation', record_id, cr_id …)
        ON CONFLICT DO NOTHING RETURNING *;
conflict(0 行) → 幂等重读阶梯（同一事务内，全部只读）：
  1) GetApprovalContinuationTaskByRecord(record_id)   → 命中：already-queued（同审批重放/并发输家）
  2) GetApprovalContinuationTaskByCr(cr_id)           → 命中：already-queued（FR-6 每 CR 上限）
  3) HasActiveTaskForIssue(issue_id) / 既有 pending 索引冲突 → 命中：already-queued（§2.3 注）
  4) 全未命中 → tx-failure 回滚（不静默降级，纪律 1）
```

阶梯 1/2 对应迁移 469/470 的两条唯一索引；阶梯 3 承接 257 索引的并发冲突面。全部命中路径都是"已有活跃任务会读到最新 crctl 状态"这一 FR-6 前提下的安全跳过，日志 Info 级（NFR-10）。

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

> 按决策记录三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代）仅记录以下 7 条；不新增 ADR、不新增审批节点。

### DD-1 触发点 = grant 已写入 worktree 后的 ACK
- **Context**：PRD 已拍板（FR-1），此处记录技术含义：ACK 是系统中唯一"grant 已可靠落盘"的确认信号；ACK 时点 grant 文件必已存在于 worktree，被唤醒 Agent 读取 `.crctl/grants/` 时数据已在位。
- **Alternatives**：飞书卡片回调（链路未封闭）、定时轮询（NFR-5 禁止）、状态事件（会复制状态机语义）。
- **Consequences**：daemon 交付与唤醒严格串行；ACK 失败整体可重试。

### DD-2 专用 guarded INSERT（CreateApprovalContinuationTask）而非复用 mention 路径（CreateAgentTask）
- **Context**：FR-3 要求与 `delivered_at` 同事务；FR-4/FR-6 需要 ON CONFLICT 语义；FR-7 需要逐级结构化原因。
- **Alternatives**：复用 `CreateAgentTask`/`EnqueueTaskForSquadLeader`（task.go:1406）——其归因瀑布、GetAgent 预载、无事务注入点、无 ON CONFLICT 处理，改造成本与侵入面更大，且会把审批归因引入 trigger-comment 语义，不合 FR-9 最小上下文。
- **Consequences**：新增 4 条 sqlc 查询 + 重跑 sqlc generate；形态与仓库既有 `CreatePipelineTask` 先例（agent.sql:651）同构，评审可对照。

### DD-3 批量 ACK 单事务 all-or-nothing（而非逐记录部分成功）
- **Context**：FR-3"要么都生效要么都不生效"、FR-5"入队失败 ACK 返回 HTTP 错误"。
- **Alternatives**：逐 id 独立事务 + 响应携带 per-id 结果——daemon 侧需解析部分成功语义，超出"daemon 零改动"边界。
- **Consequences**：任一记录失败整批回滚、整批重投递（幂等写文件无害）；坏记录（如 leader 未配置）会连带阻塞同批健康 grant，直至配置修复——该 trade-off 由 FR-7"保持未 ACK 等待配置修复"显式背书，5xx 响应体 reasons 列表即为运维修复指引（NFR-10）。评审需确认此残余风险可接受。

### DD-4 双 partial unique index（ref_id + cr_id）而不是应用层检查兜底
- **Context**：FR-4 键 = approval_record.id（幂等）；FR-6 键 = CR（上限）；应用层检查存在并发竞态窗口。
- **Alternatives**：仅应用层 COUNT 检查——两个并发 ACK（不同 stage 同 CR）都会通过检查，产生两条续跑任务，违反 AC-5。
- **Consequences**：两条单语句 CONCURRENTLY 迁移（仓库惯例，ARCHITECTURE §5.6）；INSERT 的 ON CONFLICT DO NOTHING + 三阶梯幂等重读（§4.3）。

### DD-5 onGrantAck 签名改为 GrantAckEvent（而非保留旧签名另加回调）
- **Context**：FR-10 要求回调携带 id/stage/decision 且可返回 error。
- **Alternatives**：保留旧回调 + 新增第二个回调——双通道并存，Runner 未来开启时语义分叉。
- **Consequences**：唯一消费方 `Runner.WakeGrant` 同批调整（约 5 行）；Runner 关闭时零影响。

### DD-6 FR-12 在 comparable() 内剥离 payload.detected_at（而非为 drift 事件单独传比较副本）
- **Context**：`comparable()` 是 dedup 名冲突时的内容一致性守卫；`detected_at` 是唯一的观测时点易变字段（顶层 `occurred_at` 本就不参与比较）。
- **Alternatives**：`emitDriftAudit` 单独传 `comparable_payload`——把易变字段清单推给每个调用方，未来新事件易再犯；改 `dedup_name` 生成规则——违反 FR-12"不改文件名规则"。
- **Consequences**：一行级改动 + 注释说明易变字段白名单语义；新事件若引入其它时点字段需同步维护该剥离逻辑（SDD 明确，实施期加注释）。

### DD-7 续跑任务归因 = approver（originator_source='direct_human'）
- **Context**：MUL-4302 归因契约要求每个 run 可追溯到一个人；审批记录携带 `approver_user_id`（真实人工）。
- **Alternatives**：新增 source 标签（如 `approval_continuation`）——184 迁移允许无迁移加标签，但"审批人"就是直接人工动作，落入既有 `direct_human` 语义（attribution.go:26-33），无需扩词汇表；`owner_fallback` 会降级为 Agent 属主，不合 NFR-12"不伪造人工归因"。
- **Consequences**：不新增归因词汇；审批人可在既有归因 UI 看到自己审批触发的续跑。

# 6. FR 到技术实现映射

| FR | SDD 落点 |
|---|---|
| FR-1 ACK 时点幂等唤醒 | §1.4 流程、§4.1（UPDATE RETURNING 驱动入队）、§4.3（ON CONFLICT + 重读阶梯）；迁移 469 |
| FR-2 四类审批覆盖，通过/驳回均续跑 | §4.1：stage/decision 直接来自 `approval_record` 行（DD 无 stage 分支），approve/reject 均入队；驳回后的修订路由由被唤醒 Agent 依 crctl next 执行（不在 Multica 内） |
| FR-3 原生原子事务 | §4.1：pgx `pool.Begin` + `queries.WithTx`，delivered_at 与入队同一 commit；失败回滚不标记 delivered_at |
| FR-4 窄唯一约束防重复唤醒 | 迁移 469 + §4.3 阶梯 1 |
| FR-5 ACK 失败语义与 daemon 重试 | §4.1（5xx + 回滚保持 pending）+ §1.2（crevents.go 既有 15s 重投递，零改动）+ §3.1 错误体 |
| FR-6 同 CR 最多一个后继，不注入事件 | 迁移 470 + §4.3 阶梯 2/3；续跑任务是普通队列行，无运行中沙箱注入机制存在 |
| FR-7 leader 解析 fail-closed | §4.2 逐级解析 + 四类原因码；§3.1 reasons 响应体 |
| FR-8 只处理新 ACK | UPDATE 谓词 `delivered_at IS NULL`（既有行为原样保留），无回填路径 |
| FR-9 不复制状态机语义 | §2.4 context schema（仅 4 字段）+ §3.2 回调；Multica 侧无任何"状态→下一步"映射 |
| FR-10 ACK 回调数据补齐 | §3.2 GrantAckEvent + Runner.WakeGrant 同批调整（DD-5） |
| FR-11 复用既有展示面 | §2.4（复用 agent_task_queue 全部既有列）+ TaskService.PublishTaskEnqueued 广播（§1.3）；无新状态列/新投影 |
| FR-12 audit-drift 去重修复 | §4.4 comparable() 剥离 detected_at（DD-6）；不改事件内容与文件名规则 |

**FR 覆盖率：12/12**。

# 7. 安全与性能考量

## 7.1 边界条件与安全

- **workspace 隔离**：续跑目标解析全部以 ACK 的 daemon workspace 为根（`GetCr(ws, cr_id)`），跨 workspace 同名 CR 不可能被唤醒（对照既有 `TestApprovalCardDoesNotLeakEvidenceAcrossWorkspaces` 的防护口径）。
- **越权**：leader 解析走 issue→squad 关联；无 leader 一律失败，不回退任意 Agent（FR-7）；不新增开放端点，ACK 鉴权不变（NFR-12）。
- **并发**：两条 partial unique index 是并发竞态的硬兜底；`ON CONFLICT DO NOTHING` 输家走幂等重读，绝不 5xx。
- **历史数据**：无回填迁移；旧 `delivered_at` 非空行天然不进 UPDATE 结果集（FR-8/AC-7）。
- **回调失败**：提交后回调 error → 5xx → daemon 重放走 0 行幂等分支 → 200，无重复任务（§3.2）。

## 7.2 性能

- ACK 为低频人工触发路径；单事务内完成 1 次 UPDATE + 每记录至多 4 次点查 + 1 次 INSERT，无轮询/后台扫描（NFR-5）。
- daemon 侧零改动、零新增往返（NFR-6）；续跑任务与普通任务共用队列与 reclaim 机制。
- tools 侧：`comparable()` 仅多一次对象浅拷贝，仅 dedup 名命中时执行，无热路径影响。

## 7.3 可观测性（NFR-10 原因码全集）

| reason | 触发 | 日志级 |
|---|---|---|
| `workspace-mismatch` | (ws, cr_id) 无投影行 | Error |
| `issue-missing` | shell_issue_id 为空 | Error |
| `leader-missing` | 非 squad 指派 / 无 squad / leader 缺失或未绑定 runtime | Error |
| `already-queued` | 幂等重读阶梯任一命中 | Info |
| `tx-failure` | 重读阶梯全未命中或事务错误 | Error |

所有日志携带 cr_id、stage、decision、reason；5xx 响应体 reasons 列表同源（§3.1）。

## 7.4 测试设计（AC 映射）

**multica（Go，DB 集成测试贴包）**：
- `server/internal/governance/approval_continuation_test.go`（新）：AC-1（同记录双 ACK/并发 → 恰 1 条）；AC-2（四 stage × approve/reject 各 1 条，reject 任务上下文含 decision=reject）；AC-3（注入事务失败 → delivered_at 仍 NULL + 5xx + 重放成功）；AC-5（先造活跃续跑任务再 ACK 另一 stage → 后继 ≤1，无事件注入——以任务事件流断言）；AC-6（三种 leader 缺失形态 → 未 ACK + 原因码，配置恢复后重试成功）；AC-7（已交付记录 0 任务）；AC-8（context 无映射字段 + Runner 未接线时 ACK 仍成功）；AC-9（GrantAckEvent 字段与 approval_record 行一致）；AC-10（审批表无新列断言可并入迁移评审）。
- `server/internal/daemon/`（既有 deliverGrants 假 fetcher 测试扩展）：AC-4（ACK 返回 5xx → grants 保持 pending → 下一周期重投递成功）。

**tools（node --test）**：扩展 `skills/shared/crctl/scripts/test/crctl.test.mjs` 既有 drift 用例（:776）：AC-11（连续两次观测 → audit-drift 文件恰 1、无 EMIT_FAILED 审计行、第二次幂等返回）；AC-12（删除文件后再观测 → 新文件按窗口计数；不同 CR/不同摘要不误合并；同名内容真实变化仍冲突）。

**验证顺序**：sqlc generate → `go test ./server/internal/governance/... ./server/internal/daemon/...`；tools 侧 `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`。

## 7.5 残余风险（随评审确认）

1. **DD-3 批次联动阻塞**：坏 grant（leader 未配置）会阻塞同批其余 grant 的 ACK，直至配置修复。FR-7 显式背书该 fail-closed 语义；若评审认为不可接受，可后续追加 daemon 逐 grant ACK 的独立 CR（不在本 CR 范围）。
2. **FR-6 跳过的极端时序**：续跑 #1 运行中时 ACK #2 被跳过（阶梯 2/3 命中）。由于 grant 文件在 ACK 之前已写入 worktree，续跑 #1 的 Agent 运行时若 grant #2 已在 `.crctl/grants/`，将一并读到；仅在"Agent 读取早于 grant #2 落盘、且 ACK #2 又早于 #1 完成"的窄窗内，唤醒 #2 需要人工补一个 @（与现状一致）。AC-5 断言的就是该跳过行为本身，不引入注入机制。
3. **257 索引交互**：leader 在 issue 上有 pending mention 任务时续跑被合并跳过（阶梯 3）——语义上等价于"已有活跃任务将读到最新状态"，但该任务的 trigger 上下文不含审批字段，Agent 依 crctl status/grants 目录路由，与 FR-9 一致。

# 8. Prompt 采纳影响

**本节省略（条件不满足）**。判定依据（CR-2026-021 FR-25/AC-15）：本 CR 的 tools 侧 diff 仅触及 `crctl.mjs` 内 `emitOutboxEvent` 的 `comparable()` 比较逻辑（§4.4），**不触及** `crctl.mjs` 的 dispatch 分支、**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`——crctl 命令面与 guard deny 面均无新增/变更，无任何 skill 提示词需要改为调用新增/扩展子命令，故无需列出采纳清单。
