---
id: CR-2026-052-prd
type: PRD
cr-ref: CR-2026-052
title: Multica 审批后自动续跑 + audit-drift 去重修复
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-27T00:33:18+08:00
updated: 2026-08-27T00:33:18+08:00
---

# 1. 概述

## 1.1 问题陈述

依据《Multica 执行性能分析与模块职责边界》v0.3（本 CR source 文档）对 CR-2026-051 的实测复盘：该 CR 在 Multica 平台全程墙钟 23.5h，其中**人工审批等待 ~11.2h（48%）**为最大单项损失，且审批链路本身存在一个结构性缺口——审批完成后，系统不会自动恢复既有 CR 任务继续推进，必须靠人类在评论里再 @ 一次 Agent，每次审批点都产生一轮新的中继 turn。

具体缺口（source §7.1，已逐项核实，见附录 A）：

1. **审批完成后无自动续跑**：当前 Multica 的 grant 交付链路是「服务端签发签名 grant → daemon 写入 worktree `.crctl/grants/` → 调用 ACK 确认 `delivered_at`」。ACK 回调 `onGrantAck(workspaceID, crID)` 无错误返回值、调用失败仍返回 HTTP 200（`server/internal/governance/approval.go#HandleGrantsAck`），且该回调只被接线到默认关闭的 Architecture Runner（`server/cmd/server/router.go:1408`，`AIFIRST_ARCHITECTURE_RUNNER` 环境变量门控，默认 off），而 Runner 只覆盖已纳入 Runner 的 `architecture-design` 固定切片。因此需求、架构、开发启动、代码四类审批在 ACK 之后均没有任何统一续跑路径。
2. **tools 仓 outbox `audit-drift` 去重缺陷**：crctl outbox 的 `comparable()` 比较含 `payload.detected_at`（每次观测重新生成的当前时间戳），而 `emitDriftAudit` 用确定性 `dedup_name` 落同一文件——同一漂移在被采集走之前再次观测，必然 `OUTBOX_DEDUP_CONFLICT` → `EMIT_FAILED`，与"待采集期间只留一份"的设计语义矛盾（`skills/shared/crctl/scripts/crctl.mjs`）。

修复方向明确：慢不在工具链，而是审批链路缺自动续跑这一环；daemon 与 crctl 状态机均无性能缺陷，禁止重写。

## 1.2 解决方案摘要

一个 CR 覆盖两块可实施范围：

1. **Multica 侧——审批后自动续跑（单一路径最小方案）**：触发点选在「grant 已可靠写入 worktree 后的 ACK」——不是飞书卡片回调、不是新增轮询。ACK 时以 pgx/sqlc 原生事务幂等创建一条续跑任务并更新 `approval_record.delivered_at`，唤醒既有 CR 任务（`cr-coordinator-agent`），覆盖需求/架构/开发启动/代码四类审批；**通过与驳回都续跑**（通过向前推进，驳回进入既有修订/reviewLoop），均持续到下一个人工审批点或明确 blocker。Architecture Runner 保持关闭，不与通用路径并行。
2. **tools 侧——audit-drift 去重修复**：修正 outbox 去重比较语义，观测时点类易变字段（`detected_at`）不参与同一漂移的去重比较，恢复"待采集期间只留一份"语义，消除重复报错。

最小可靠性约束（source §7.1 原样采纳）：pgx/sqlc 原生原子事务、`kind=approval_continuation` + `ref_id=approval_record.id` 窄范围唯一约束、ACK 失败可返回错误并由 daemon 15s 循环重试、同 CR 最多保留一个后继任务、无 leader 不回退、只处理新 ACK 不回填历史、不复制状态机/门禁/Pipeline 语义。

## 1.3 已解决基础设施（只复用，不重做）

以下为已核实的既有事实源，本 CR 直接复用，禁止在其旁边再造一套：

| 能力 | 既有实现（已核实） | 本 CR 处理 |
|---|---|---|
| CR 状态机 + 门禁 + CAS + 审计 + 原子提交 | `../tools/skills/shared/crctl/`（状态机 15 具名状态、gates.json、`.crctl/transactions`、outbox、audit.log） | 零改动（FR-12 的 outbox dedup 缺陷修复除外） |
| 签名 grant 签发与交付 | `server/internal/governance/approval.go`：Ed25519 签名、`approval_record` 落库、daemon `FetchPendingGrants`/`AckGrants`（`server/internal/daemon/crevents.go`） | 仅改 ACK 回调语义与入队，不改签发与验证 |
| daemon 交付重试 | `crEventsLoop` 每 `HeartbeatInterval`（默认 15s）拉取 pending grants、写文件、ACK；ACK 失败 grants 保持 pending、重投递幂等 | 复用同一重试循环，不改周期 |
| 任务队列与窄唯一约束先例 | `agent_task_queue` 含 `trigger_evidence_kind`/`trigger_evidence_ref_id` 列；partial unique index 先例 `idx_agent_task_queue_pipeline_node_active`、`idx_one_pending_task_per_issue_agent_v2`；Runner 入队走 `TaskService.EnqueuePipelineTask` | 复用列与索引惯例，新增一条窄唯一约束 |
| CR → issue 关联 | `cr.shell_issue_id`（投影表，`server/migrations/433_aifirst_cr_projection.up.sql`） | 只读复用，用于定位续跑任务的 issue 落点 |
| CR leader | Multica workspace 内 `squad.leader_id`（`server/migrations/084_squad.up.sql`），平台侧已配置专用 `cr-coordinator-agent`（2026-08-26 落地） | 只读解析；找不到 leader 时 fail-closed（FR-7） |
| 审批提醒触达 | CR-2026-051 交付的飞书提醒卡片 | 零改动，直接复用 |

职责边界保持不变（source §5）：评审/路由/编排在 Agent+Skill 层，状态与账本只在 crctl 层，确定性转换在版本化脚本层；Multica 只负责「接收审批、投递 grant、ACK 后幂等唤醒一个已有 CR 任务」，不复制任何状态机或门禁语义。

## 1.4 需求边界（注册摘要已拍板，原样采纳）

注册阶段已确认边界，本 PRD 不重新定义、不扩大：

- 覆盖四类审批：需求（requirement）、架构（tech-design）、开发启动（dev-start）、代码（code）；通过/驳回均续跑；
- 触发点 = grant 可靠写入 worktree 后的 ACK；不改飞书卡片回调链路；
- 只处理上线后的新 ACK，不回填历史审批；
- 不复制状态机/门禁/Pipeline 语义；唤醒任务不维护「状态 → 下一 Skill」映射，下一步由 Agent 依 `crctl status`/`crctl next` 路由；
- Architecture Runner 保持关闭，不扩建全阶段 Runner、不新增通用工作流引擎、不新增 IM 专用状态机；
- 附件其余范围（§6 已解决基础设施、§7.2 已落地平台配置、§8/§9 整改与不做清单）仅作背景，不在本 CR 重复实施。

# 2. 用户故事

- **US-1（审批人 / CR 流程 owner）**：作为审批人，我希望在 Web 或终端完成审批后，对应 CR 的任务自动续跑到下一个人工审批点或明确阻塞点，这样我不需要在评论里再 @ Agent、也不必担心审批后流程停摆。
- **US-2（CR 协调 Agent / 执行者）**：作为被唤醒的 CR 任务，我希望唤醒时只收到"哪个 CR、哪个阶段、什么审批结果"的最小上下文，然后自己按 `crctl status`/`crctl next` 决定下一步，而不是被注入一套硬编码的状态机副本。
- **US-3（平台运维）**：作为运维，我希望入队失败时 ACK 明确失败并进入 daemon 既有 15s 重试，而不是"HTTP 200 但唤醒静默丢失"。
- **US-4（审批人）**：作为审批人，我不希望同一审批被重复唤醒出多条任务，也不希望驳回后流程直接中断——驳回应自动回到既有修订/reviewLoop。
- **US-5（CR 流程 owner）**：作为流程 owner，我希望 CR 没有可解析的 leader 时系统明确报错并保持未 ACK（等待配置修复），而不是随机派发给任意 Agent 造成越权执行。
- **US-6（crctl 维护者 / 审计）**：作为 crctl 维护者，我希望同一份证据漂移在被采集走之前只留一份 outbox 事件，再观测不冲突、不刷 `EMIT_FAILED`，审计语义与采集窗口计数保持一致。

# 3. 功能需求

> 范围归属：FR-1 ~ FR-11 为 Multica 仓；FR-12 为 tools 仓。所有「已核实」断言见附录 A。

## FR-1 ACK 时点幂等唤醒

在 `HandleGrantsAck` 的 ACK 处理路径中，对每个成功更新 `delivered_at` 的审批记录，幂等创建一条续跑任务唤醒既有 CR 任务。触发点必须是「grant 已可靠写入 worktree 后的 ACK」，不得使用飞书卡片回调、定时轮询或状态事件作为触发源。幂等语义：同一 `approval_record.id` 无论 ACK 重放多少次，最多产生一条续跑任务（由 FR-4 的窄唯一约束兜底，冲突时按已存在处理，不报错不重复入队）。

## FR-2 四类审批统一覆盖，通过/驳回均续跑

续跑路径覆盖 gates.json `approvalStages` 全部四个 stage 键：`requirement`、`tech-design`、`dev-start`、`code`。决策为 `approve` 时向前推进，决策为 `reject` 时由被唤醒的 Agent 依 `crctl status`/`crctl next` 进入既有修订/reviewLoop 路径；两类决策都必须触发续跑，直至下一个人工审批点或明确 blocker。四个 stage 不得各自实现一套唤醒逻辑，必须共享同一 ACK→入队路径。

## FR-3 原生原子事务（入队 + delivered_at 同 commit）

续跑任务创建与 `approval_record.delivered_at` 更新必须使用既有 pgx/sqlc 原生事务作为一个原子提交：要么两者都生效，要么都不生效。禁止引入新事务框架、禁止为续跑新建 outbox/队列表。事务失败时 `delivered_at` 不得被标记（保持 pending，daemon 按 FR-5 重试）。

## FR-4 窄范围唯一约束防重复唤醒

新增一条 partial unique index 于 `agent_task_queue`：以 `trigger_evidence_kind = 'approval_continuation'` 且 `trigger_evidence_ref_id = approval_record.id` 为键，仅覆盖活跃状态（沿用 `idx_agent_task_queue_pipeline_node_active` 的 active-status 口径）。同一审批重复 ACK / 并发入队竞争时，输家按已存在任务处理（幂等重读），不得产生两条续跑任务、不得报 5xx。迁移遵循仓库既有惯例（单语句、`CREATE UNIQUE INDEX CONCURRENTLY`，见附录 A）。

## FR-5 ACK 失败语义与 daemon 重试

入队失败时 ACK 必须返回错误（HTTP 非 2xx），且该审批记录的 `delivered_at` 保持未标记；daemon 沿用既有 `crEventsLoop` 15s 周期重试交付同一批 pending grants（写文件幂等、重投递幂等），无需新增重试机制。ack 数据需携带审批记录 id、stage、decision，供入队与审计使用（补全回调入参，见 FR-10）。成功入队的记录才返回 2xx。

## FR-6 同 CR 最多一个后继任务，不向运行中沙箱注入事件

若同一 CR 已存在活跃任务（queued/deferred/dispatched/running 等活跃状态），本次续跑最多保留一个后继任务——不得向运行中的沙箱注入新事件、不得并发唤醒多份。以"同 CR 最多一个未完成的续跑后继"为上限判定，具体活跃状态口径沿用仓库既有 active-status 口径并在 SDD 明确。

## FR-7 leader 解析 fail-closed

唤醒目标解析为既有 CR leader（经由 `cr.shell_issue_id` → issue → squad `leader_id` 既有关联，或 SDD 论证的等价权威路径）。解析不到 leader（无 shell issue、无 squad、leader 被删）时**不回退到任意 Agent**，保持未 ACK 并记录结构化错误（含 CR、stage、失败原因），等待配置修复后由 daemon 重试补发。禁止硬编码具体 agent id 或 agent 名称（平台配置会变化）。

## FR-8 只处理新 ACK，不回填历史

只对上线后新产生的 ACK 触发续跑；历史上已 `delivered_at` 非空的审批记录不参与回填、不批量补唤醒。无数据迁移回填任务。

## FR-9 不复制状态机/门禁/Pipeline 语义

续跑任务携带的最小上下文仅包含：CR 标识、审批 stage、决策、审批记录引用与既有 issue 落点。不得在 Multica 中维护「状态 → 下一 Skill」映射、不得直接写 CR 受控账本、不得替代 `approve-*` Skill。被唤醒任务的下一步由 Agent 依据 `crctl status`/`crctl next` 自行路由。Architecture Runner 保持默认关闭（`AIFIRST_ARCHITECTURE_RUNNER` 不设置），且本 CR 不得把 ACK 回调接线扩展到 Runner 全阶段或新 Runner。

## FR-10 ACK 回调数据补齐

`onGrantAck` 回调签名由 `(ctx, workspaceID, crID)` 扩展为携带审批记录 id、stage、decision（追加字段或等价结构化入参，SDD 定签名）；`HandleGrantsAck` 在更新 `delivered_at` 时一并取回这些字段并传递给回调。回调需返回 error 并影响 ACK HTTP 状态码（FR-5）。原有唯一消费方（Architecture Runner `WakeGrant`）在 Runner 关闭时不被调用；若未来 Runner 开启，回调接口变更不得破坏其编译契约（SDD 明确兼容方式）。

## FR-11 续跑状态复用现有展示面

续跑任务的执行状态复用既有任务队列、issue 评论与收件箱展示，不得为审批记录新增第二套执行状态机或新的状态字段投影。任务创建与完成仍走既有 `TaskService` 入队与事件广播。

## FR-12 audit-drift 去重修复（tools 仓）

修正 outbox 去重比较语义：观测时点类易变字段（`payload.detected_at`）不得参与同一 `dedup_name` 的 `comparable()` 比较。修复后语义：同一证据漂移（同 cr、stage、expected/actual 摘要）在被采集走之前只留一份事件文件，重复观测不抛 `OUTBOX_DEDUP_CONFLICT`、不产生 `EMIT_FAILED`；漂移被采集后再观测则按观测窗口计数新留一份（保留既有审计语义）。去重键本身（文件名与比较字段集合）必须保持确定性且不引入跨 CR/跨漂移误合并；修复范围只限 outbox dedup 比较，不改事件内容、不改 `dedup_name` 生成规则。

# 4. 非功能需求

## 4.1 可靠性

- **NFR-1**：续跑入队与 delivered_at 更新原子（FR-3），进程在两步之间崩溃时要么重试要么已 ACK，不产生"已 ACK 但无任务"的静默丢失。
- **NFR-2**：幂等（FR-1/FR-4）：ACK 重放、并发竞争、daemon 重复投递均不产生重复续跑任务。
- **NFR-3**：fail-closed（FR-7）：无 leader、无 issue 落点、workspace 不匹配等异常一律不派发、不降级，保持可重试。
- **NFR-4**：不新增重试框架、队列或 outbox（FR-3/FR-5）；可靠性全部落在既有 daemon 15s 循环与原生事务上。

## 4.2 性能

- **NFR-5**：ACK 路径为低频人工审批触发，入队开销必须在单事务内完成，不引入轮询或后台扫描；不得对审批链路热路径（grant 签发、daemon 心跳）增加可感知延迟。
- **NFR-6**：daemon 侧零新增网络往返——沿用既有 pending/ack 两个端点。

## 4.3 兼容性与演进

- **NFR-7**：数据库迁移遵循仓库既有惯例（单语句、CONCURRENTLY、编号顺延、down 幂等），并在 `CUSTOM.md` 台账登记（multica 仓硬规则）。
- **NFR-8**：回调接口变更保持对既有调用点（Architecture Runner）的编译兼容或同批调整；不改 grant 文件 schema v1、不改 `approval_record` 既有列语义。
- **NFR-9**：tools 仓修复不改变 outbox 事件外部 schema（`v`/`event_kind`/`payload` 结构对采集端不变），不要求 daemon/服务端配合升级。

## 4.4 可观测性

- **NFR-10**：所有跳过/失败原因结构化可检索（至少含 CR、stage、decision、原因码，覆盖：leader-missing、issue-missing、workspace-mismatch、already-queued、tx-failure），日志分级合理（失败 WARN/Error，幂等命中 Info）。
- **NFR-11**：不新增用户可见的新审批状态或状态字段；续跑进度通过既有任务与 issue 评论可见（FR-11）。

## 4.5 安全与权限

- **NFR-12**：ACK 端点继续沿用 daemon 凭据解析的 workspace 作用域，不新增开放接口、不放宽调用方；唤醒任务归属沿用既有任务归因（originator/accountable）语义，不伪造人工归因。

# 5. 验收标准

## Multica 侧（对应 FR-1 ~ FR-11）

- **AC-1（FR-1/FR-4）**：对同一条 `approval_record` 连续两次 ACK（模拟重放/并发），`agent_task_queue` 中 `kind=approval_continuation` 且 `ref_id=该记录 id` 的任务恰好 1 条，第二次返回幂等结果而非 5xx。
- **AC-2（FR-2）**：分别在 `requirement`/`tech-design`/`dev-start`/`code` 四个 stage 各制造一次 approve 与一次 reject，每次 ACK 后均产生恰好 1 条续跑任务，任务上下文含对应 stage 与 decision；reject 不产生"流程中断"状态，被唤醒 Agent 可依 `crctl next` 得到修订路径。
- **AC-3（FR-3）**：人为使入队步骤失败（如注入 tx 错误），验证 `approval_record.delivered_at` 仍为 NULL 且 HTTP 返回错误；修复后同一 grant 在下一 daemon 周期被重新交付并成功 ACK+入队。
- **AC-4（FR-5）**：daemon 对 ACK 返回 5xx 的场景，观察 grants 保持 pending 且被 15s 周期重投递（用既有 `deliverGrants` 幂等重投递测试或等价集成测试证明），直至成功。
- **AC-5（FR-6）**：同 CR 已有一条活跃任务时再次 ACK（另一 stage），活跃续跑后继 ≤ 1 条，且运行中任务未收到注入事件（以任务事件流断言）。
- **AC-6（FR-7）**：CR 无 shell issue / 无 squad / leader 已删三种情形，ACK 保持未确认并记录原因，绝不派发到任意 Agent；恢复配置后重试成功。
- **AC-7（FR-8）**：历史已交付（`delivered_at` 非空）的审批记录不产生任何新任务，且无回填迁移。
- **AC-8（FR-9）**：续跑任务上下文不包含任何"状态→下一步"映射内容；`AIFIRST_ARCHITECTURE_RUNNER` 未设置时 Runner 相关路径零调用（以日志/覆盖率断言），ACK 唤醒仍生效（证明唤醒不依赖 Runner）。
- **AC-9（FR-10）**：回调收到的审批数据与 `approval_record` 行一致（id/stage/decision 逐字段断言），编译契约对既有调用点不破坏。
- **AC-10（FR-11）**：审批记录表不新增任何执行状态列；续跑任务完成后其进度在既有任务/issue 展示面可见。

## tools 侧（对应 FR-12）

- **AC-11（FR-12）**：同一漂移（同 cr、stage、expected/actual）连续两次观测（`detected_at` 不同），outbox 中该 `dedup_name` 文件数为 1，第二次无 `EMIT_FAILED` 审计行、无异常抛出。
- **AC-12（FR-12）**：漂移被采集删除后再观测，产生新文件且审计记录按窗口计数（保留既有语义）；不同 CR 或不同摘要的漂移不因修复被误合并（`dedup_name` 生成与比较键确定性回归测试）。

# 6. 成功指标

| 指标 | 度量方式 | 目标 |
|---|---|---|
| 审批后自动续跑命中率 | 四类审批 ACK 后产生续跑任务的比例（不含 FR-7 fail-closed 与幂等命中） | 100%（配置正常前提下） |
| 重复唤醒数 | `kind=approval_continuation` 任务数与审批记录数之比 | = 1（无重复无丢失） |
| 人工审批等待墙钟占比 | 下一 CR 全流程复盘（对照 CR-2026-051 的 48%） | 消除"审批后 @ Agent"环节，审批等待占比显著下降（以实际任务转录验收） |
| audit-drift EMIT_FAILED | outbox 审计 `EMIT_FAILED` 事件（event_kind=audit、trigger=evidence-drift） | 修复后归零 |
| 平台配置故障下的行为 | leader 缺失场景 | 明确报错可检索，等待修复后自动补齐，零误派发 |

# 7. 范围排除

以下明确不做（注册边界 + source §9，原样采纳）：

- 不在 tools 仓新增"Multica 编排层"或任何平台适配抽象（平台差异由平台配置吸收）；
- 不在 tools 仓新增 squad/leader Agent；Multica workspace 只保留一个专用 `cr-coordinator-agent`；
- 不把状态机、门禁、账本逻辑复制进 Multica 或 Agent 提示词（唯一事实源仍是 `../tools/dir-graph.yaml` 与 crctl）；
- 不为审批续跑新建队列/outbox/重试框架（只复用现有任务队列、daemon ACK 重试与 pgx/sqlc 原生事务）；
- 不修改 crctl 的 gate 语义与状态转移（状态机改动是独立 CR 的范畴）；tools 仓仅允许 FR-12 的去重缺陷修复；
- 不改飞书提醒卡片链路、不改 grant 签发与签名格式、不新增 IM 专用状态机；
- 不回填历史审批、不迁移历史数据；
- 不启用 Architecture Runner、不把 Runner 扩建到全阶段；
- 附件其余范围（§6 已解决基础设施、§7.2 已落地平台配置、§8/§9 整改与不做清单）不在本 CR 实施。

# 8. 附录 A：事实核实记录（落笔前已逐项核实）

| # | 断言 | 证据（仓库: 文件: 行/段） | 结论 |
|---|---|---|---|
| A1 | ACK 先写 `delivered_at` 再调无错返回的 `onGrantAck`，失败仍 200 | multica: `server/internal/governance/approval.go:377-425`（`HandleGrantsAck`；`SetGrantAckHandler` 签名 `func(context.Context,string,string)`） | 确认，FR-5/FR-10 改动点 |
| A2 | ACK 回调仅接线 Architecture Runner 且默认关闭 | multica: `server/cmd/server/router.go:1398-1411`（`ArchitectureRunnerEnabled()` 读 `AIFIRST_ARCHITECTURE_RUNNER`，默认 false）；`server/internal/governance/runner.go:54-62` | 确认，FR-9 依据 |
| A3 | daemon 交付循环 15s 且 ACK 失败保持 pending | multica: `server/internal/daemon/config.go:24`（`DefaultHeartbeatInterval=15s`）；`crevents.go:117-155`（`deliverGrants`，ACK 失败仅日志、grants 保持 pending、重投幂等）；`crevents.go:203-219`（`crEventsLoop` 每周期调用） | 确认，FR-5 依据 |
| A4 | `agent_task_queue` 已有 `trigger_evidence_kind`/`trigger_evidence_ref_id` 列 | multica: `server/internal/service/attribution_stamp_test.go:96` 等大量使用；`001_init.up.sql:127` 表定义（后续迁移加列） | 确认，FR-4 复用依据 |
| A5 | 活跃状态 partial unique index 先例 | multica: `443_agent_task_pipeline_node_active_unique.up.sql`（`pipeline_node_run_id`，active 状态口径）；`257_agent_task_queue_channel_media_pending_unique_v2.up.sql` | 确认，FR-4 惯例依据 |
| A6 | 当前无 `approval_continuation` 相关索引/代码 | multica: 全仓 grep `approval_continuation` 零命中；无 `trigger_evidence_kind` 上的既有唯一索引 | 确认，需新迁移 |
| A7 | `cr.shell_issue_id` 关联 CR→issue；squad 有 `leader_id` | multica: `433_aifirst_cr_projection.up.sql:18-32`（cr 表含 `shell_issue_id`）；`084_squad.up.sql:7`（`leader_id NOT NULL`） | 确认，FR-7 解析路径依据 |
| A8 | 四类审批 stage 键 | tools: `skills/shared/crctl/gates.json#approvalStages`：`requirement`/`tech-design`/`dev-start`/`code` | 确认，FR-2 依据 |
| A9 | outbox `comparable()` 含 `payload`（含 `detected_at`），`emitDriftAudit` 用确定性 `dedup_name` 且 `payload.detected_at=nowIso()` | tools: `skills/shared/crctl/scripts/crctl.mjs:321-329`（comparable 含 payload）、`:343-352`（emitDriftAudit 落 `detected_at` + 确定性文件名） | 确认，FR-12 缺陷根因 |
| A10 | 四类审批的 ACK 前状态/触发 | tools: gates.json `approvalStages[*].to/trigger/expect`（如 requirement→`requirement-approved`） | 确认（PRD 不依赖具体状态值，FR-9 禁止复制） |

# 9. 修订记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-08-27 | 初稿：依据 source 文档 v0.3 与附录 A 核实记录起草；边界原样采纳注册摘要 |
