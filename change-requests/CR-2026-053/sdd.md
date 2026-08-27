---
id: CR-2026-053-sdd
type: SDD
cr-ref: CR-2026-053
title: 独立评审与人工审批命令闭环 — 评审独立路由与审批卡可见性修复 技术设计
status: draft
created: 2026-08-27T19:25:03+08:00
updated: 2026-08-27T19:25:03+08:00
---

# SDD — 独立评审与人工审批命令闭环技术设计

> 输入：`change-requests/CR-2026-053/prd.md`（20 FR / 6 US / 31 AC，commit `a64de76`）+ source 设计稿 `docs/product/独立评审与人工审批命令闭环设计.md` v0.4。
> 本文档只补"技术实现方案"，不重复 PRD 的需求语义；FR 覆盖映射见 §6。

## 1. 架构概览

### 1.1 目标与两条工作轨

一个 CR、两条独立工作轨，共享的只有 CR-ID 与现有执行环境，不建设共同的新框架：

- **Track A（tools 仓）——独立评审最小改造**：把四个 CR 评审 Skill（`review-requirement`/`review-tech-design`/`review-dev-plan`/`review-code`）的唯一 `owns` 收敛到 `quality-reviewer-agent`；作者型 Agent（`requirement-writer`/`dev-agent`）移除 `owns`、保留 `can-call`，其评审意图改为委派路由合同；三条 CR Pipeline 的 review 节点 prompt 明确要求新建独立 reviewer 运行。**不改** Pipeline schema、节点顺序、`reviewLoop`、`onFail`、状态机、gates、`review-record`/`approve` 协议、matrix parser。
- **Track B（Multica 仓）——CR→Issue 绑定与审批卡可见性**：新增 task-scoped 窄接口 `POST /api/crs/{cr_id}/bind-current-task`，在四个 review Skill 写临时评审 payload 之前执行同一平台前置步骤，把当前 task 原子绑定到 CR/Issue；同时新增调度层 reviewer task 创建契约（FR-B12，插入时原子继承 `issue_id`/`project_id`）；前端 gates 改为 `pending_stage` 非空即渲染唯一 `ApprovalCard`。存量 CR-2026-051/052 走同一接口修复，禁用直接 SQL。

### 1.2 模块边界与改动面（跨仓）

| 仓 | 涉及模块 | 改动类型 |
|---|---|---|
| tools | `agent-skill-matrix.yml` + `AGENT-SKILL-MATRIX.md` | owner/can-call 归属调整 + 说明文档同步 |
| tools | `agents/requirement-writer.md`、`agents/dev-agent.md`、`agents/quality-reviewer-agent.md`、`agents/_index.yml` | 评审意图改为委派路由合同 |
| tools | `pipeline-templates/requirement-authoring.pipeline.json`、`architecture-design.pipeline.json`、`code-implementation.pipeline.json` | 仅改四个 review 节点 prompt，schema/节点顺序/`reviewLoop`/`onFail` 不变 |
| tools | `skills/{requirement,develop}/review-*/SKILL.md`（4 个） | 在 `review-record` 之前插入同一平台绑定前置步骤（FR-B7） |
| tools | `pipeline-templates/emit-registry.mjs`、`skills/shared/crctl/scripts/check-skill-matrix.mjs`、`check-agents-contract.mjs`、`lint-prompts.mjs` | 只读校验，不修改，改造后必须通过 |
| multica | `server/cmd/server/router.go` | 新增一条 task-scoped 路由 |
| multica | `server/internal/handler/`（新 handler） + `server/internal/service/task.go`（绑定事务） | 新增绑定接口与事务 |
| multica | `server/pkg/db/queries/agent.sql` + sqlc 生成物 | `CreatePipelineTask` 增加 `issue_id`/`project_id` 继承；新增绑定读写查询 |
| multica | CLI 薄包装命令 | `bind-current-task-to-cr(CR-ID)` |
| multica | `packages/views/projects/components/cr-gate-card.tsx`、`project-team-agent-chat.tsx` | 提取 `ApprovalCard`、改渲染规则 |
| multica | `CUSTOM.md` | 台账登记 |

### 1.3 依赖方向（遵守两仓 ARCHITECTURE.md 硬不变量）

```
Agent（意图路由 + 委派 reviewer）              ← tools/agents/*
   ↓
Pipeline（节点顺序 + reviewLoop + 委派合同）    ← tools/pipeline-templates/*
   ↓
review Skill（业务判断 + task 绑定前置 + review-record）← tools/skills/*/review-*/SKILL.md
   ↓
crctl（状态/账本唯一写入，零改动）             ← tools/skills/shared/crctl/scripts/crctl.mjs

Multica（校验 task token、原子绑定 task→CR→Issue、按 pending_stage 渲染唯一卡片）
   ↓
PostgreSQL（agent_task_queue / cr / issue / project / activity_log，无新表新列）
```

规则：依赖只朝下。Skill 不得绕过 crctl 直接改账本；Multica 不复制状态机、不做评审判断、不猜关联；前端只读 `pending_stage` 渲染、不构造伪 `GateNode`、不直接改状态、不签发新 grant。

### 1.4 关键流程（目标闭环，source §1 原样）

```text
作者 Agent 产出阶段内容 → Pipeline 到达 review-* 节点 → 新建 quality-reviewer-agent 独立任务
（任务插入时从可信来源 task/Issue 原子继承 issue_id/project_id，FR-B12）
→ review Skill 先将当前 Multica task 绑定到 CR/Issue（bind-current-task-to-cr）
→ review Skill 作业务判断 → crctl review-record 原子记录评审证据
→ Pipeline 按现有 reviewLoop 回修或进入 human_approval
→ crctl/Multica 状态投影得到 pending_stage → 项目会话显示唯一 ApprovalCard → 人类批准或驳回
→ 现有 Ed25519 grant 经 daemon 投递 → crctl approve 复核门禁并推进状态
```

## 2. 数据模型

> 全部复用既有表与列（FR-B9：不新增表、不新增列）。改动只体现在"既有列被新写路径使用"与"既有 INSERT 语句补列"。

### 2.1 核心实体与字段（只列本 CR 触及的列）

| 实体（表） | 字段 | 类型 | 本 CR 语义 |
|---|---|---|---|
| `agent_task_queue` | `id` | uuid | task 主键 |
| | `issue_id` | uuid nullable | 任务所属 Issue；FR-B12 要求 reviewer task 在插入时从可信来源继承 |
| | `project_id` | uuid nullable | 任务所属 Project；同上继承 |
| | `cr_id` | text nullable | CR 归属；绑定接口 CAS 写 `NULL → cr_id` 或同值 |
| | `pipeline_node_run_id` | uuid nullable | Runner pipeline 任务幂等键 |
| | `originator_user_id` / `accountable_user_id` / `originator_source` / `delegated_from_task_id` 等 | — | 既有归因快照，`CreatePipelineTask` 已从来源 task 逐字拷贝，本 CR 不改变归因语义 |
| `cr` | `cr_id` | text | CR 标识（workspace 内） |
| | `shell_issue_id` | uuid nullable | CR→Issue 投影链接；绑定接口 CAS 写 `NULL → issue_id` 或同值（列来自 `server/migrations/433_aifirst_cr_projection.up.sql`） |
| | `title` / `status` / `needs_reconcile` / `updated_at` | — | 既有投影字段，gates 查询已消费 |
| `issue` | `id` | uuid | Issue 主键 |
| | `project_id` | uuid | Issue 所属 Project（gates 查询通过 `cr.shell_issue_id → issue.project_id` 限定项目 CR） |
| `project` | `id` / `workspace_id` | uuid | Project 及其 workspace（workspace 隔离权威） |
| `activity_log` | `action` + 结构化字段 | — | 审计：`cr_issue_bound`（成功）、`cr_issue_bind_rejected`（冲突拒绝），FR-B4 |

### 2.2 存储方案

- 无新表/新列/新索引/新外键（遵守 multica CLAUDE.md：不加 FK、新索引必须 `CONCURRENTLY`——本 CR 不新增索引）。
- 绑定三写入（`agent_task_queue.cr_id` + `cr.shell_issue_id` + `activity_log`）在同一数据库事务内完成，任一部分失败整体回滚（NFR-1）。
- CAS 约束（NFR-2）在 SQL `UPDATE ... WHERE <字段> IS NULL OR <字段> = <目标值>` 中表达，由 `rows affected` 区分"成功/同值重放/异值冲突"，不引入应用层读改写竞争。

### 2.3 涉及 sqlc 的变更面

- `server/pkg/db/queries/agent.sql`：
  - `CreatePipelineTask` INSERT 列清单增加 `issue_id`、`project_id`，值从来源 task 行 `s.issue_id`/`s.project_id` 拷贝（FR-B12）。
  - 新增绑定读写查询：读 task（含 issue_id/project_id/cr_id）、按 `(workspace_id, cr_id)` 读 CR、CAS 更新 `task.cr_id`、CAS 更新 `cr.shell_issue_id`、写 `activity_log`。具体 query 命名在实施期确定，遵循既有命名惯例。
- sqlc 生成物 `server/pkg/db/generated/` 由 `make sqlc` 再生成，禁手改（ARCHITECTURE.md 不变量 5）。

### 2.4 PipelineTaskSpec 结构变更（FR-B12）

`server/internal/service/task.go` 的 `PipelineTaskSpec` 增加两个字段（由 Runner 从来源 task 行解析，调用方不直接指定）：

```go
type PipelineTaskSpec struct {
    // ... 既有字段不变 ...
    SourceIssueID   pgtype.UUID // 来源 task 的 issue_id，插入时原子继承
    SourceProjectID pgtype.UUID // 来源 task 的 project_id，插入时原子继承
}
```

## 3. 接口契约

### 3.1 新增 HTTP 接口：绑定当前 task 到 CR

本 CR 新增/修改 HTTP API，故本节为必填（review-tech-design 条件基线 FR-08.2）。契约以 multica 既有 API 风格与 handler/chi 路由惯例为准，不强制复数名/kebab-case/固定状态码。

```http
POST /api/crs/{cr_id}/bind-current-task
Authorization: Bearer mat_<task-scoped token>
X-Workspace-ID: <workspace-uuid>   # 由 auth 中间件从 mat_ token 权威覆盖，客户端不可伪造
Content-Type: application/json
```

请求体：`{}`（或空）。不接受 `task_id`、`agent_id`、`workspace_id`、`issue_id`、`project_id`——这些值全部由服务端获取（FR-B1）。

身份来源（已核实 `server/internal/middleware/auth.go:104-106`）：`mat_` task token 校验后，中间件把 `X-User-ID`/`X-Agent-ID`/`X-Task-ID`/`X-Workspace-ID` 权威写入请求头、覆盖客户端提交值，下游 actor 解析不可被伪造。

成功响应（`200`，同值重放 `changed=false`）：

```json
{
  "cr_id": "CR-2026-052",
  "task_id": "<task-uuid>",
  "issue_id": "<issue-uuid>",
  "project_id": "<project-uuid>",
  "changed": true
}
```

错误响应（FR-B3 七种，均零绑定写入）：

```json
{ "error": "<ERROR_CODE>" }
```

| 错误码 | HTTP 状态 | 含义 |
|---|---|---|
| `TASK_CONTEXT_REQUIRED` | 401 | 不是 task token 调用 |
| `TASK_ISSUE_REQUIRED` | 422 | 当前 task 没有 Issue（创建路径错误，FR-B12） |
| `CR_NOT_FOUND` | 404 | 同 workspace 中不存在该 CR |
| `TASK_PROJECT_MISMATCH` | 422 | task/Issue/Project 关系不闭合 |
| `TASK_CR_CONFLICT` | 409 | task 已绑定另一 CR |
| `CR_ISSUE_CONFLICT` | 409 | CR 已绑定另一 Issue |
| `CR_BIND_FAILED` | 500 | 事务或审计失败，全部回滚 |

### 3.2 前端组件契约（FR-B6）

`GET /api/projects/{id}/gates` 响应模型**不变**（`projectGateCR` 结构已含 `pending_stage`/`can_approve`/`evidence`/`evidence_digest`/`key_id`/`pending_advance`/`gate_nodes`，见 `server/internal/governance/project_gates.go`）。

- 从 `CrGateCard` 内部提取 `ApprovalCard` 为可独立调用的组件，继续消费相同字段：`cr.cr_id`、`cr.pending_stage`、`cr.can_approve`、`cr.evidence`、`cr.evidence_digest`、`cr.pending_advance`。
- `CrGateCard` 现有"`human_approval` + `running` → ApprovalCard"分支不变；新增"无当前 node 但 `pending_stage` 非空 → 直接 ApprovalCard"分支放在 `project-team-agent-chat.tsx` 的渲染循环层（见 §4.3）。
- 批准/驳回仍走现有 API；不构造伪 `GateNode`、不直接改状态、不签发新 grant。

### 3.3 CLI 薄包装命令（FR-B1）

Multica CLI 新增薄包装命令（名由实施期按 CLI 命名惯例定，形如 `multica cr bind-current-task <cr-id>`），仅把 `mat_` task token 与 CR-ID 发给上述接口、透传结构化结果；不做业务判断、不落账本。

## 4. 关键算法与流程

### 4.1 绑定事务（FR-B2，服务端单一事务）

伪代码（Go，`TaskService` 内，复用既有 pgx 事务边界）：

```text
func BindCurrentTaskToCR(ctx, crID):
    actor = task_token_actor_from_context(ctx)            // X-Task-ID/X-Agent-ID/X-Workspace-ID
    if actor == nil: return TASK_CONTEXT_REQUIRED
    begin tx
    task = SELECT ... FROM agent_task_queue WHERE id = actor.task_id
               AND agent_id = actor.agent_id AND workspace_id = actor.workspace_id FOR UPDATE
    if task == nil: return TASK_CONTEXT_REQUIRED            // 未撤销 task token 校验在前，行缺失=无效
    if task.issue_id == NULL: return TASK_ISSUE_REQUIRED    // 硬技术失败，非业务分支
    issue = SELECT ... FROM issue WHERE id = task.issue_id FOR UPDATE
    if issue == nil or issue.workspace_id != task.workspace_id: return TASK_ISSUE_REQUIRED
    if issue.project_id == NULL: return TASK_PROJECT_MISMATCH
    if task.project_id != NULL and task.project_id != issue.project_id: return TASK_PROJECT_MISMATCH
    cr   = SELECT ... FROM cr WHERE cr_id = crID AND workspace_id = task.workspace_id FOR UPDATE
    if cr == nil: return CR_NOT_FOUND
    if task.cr_id != NULL and task.cr_id != crID: return TASK_CR_CONFLICT
    if cr.shell_issue_id != NULL and cr.shell_issue_id != issue.id: return CR_ISSUE_CONFLICT
    # CAS 写（只允许 NULL→值 或同值）
    UPDATE agent_task_queue SET cr_id = crID WHERE id = task.id AND (cr_id IS NULL OR cr_id = crID)
    UPDATE cr SET shell_issue_id = issue.id WHERE cr_id = crID AND (shell_issue_id IS NULL OR shell_issue_id = issue.id)
    INSERT activity_log(action='cr_issue_bound', workspace, issue, project, task, agent, cr)
    commit tx                                                  // 任一步失败 → rollback，两字段零部分更新
    publish cr:updated / project refresh events               // 提交后发布；失败记错误、不 rollback
    return {cr_id, task_id, issue_id, project_id, changed}
```

冲突路径（`TASK_CR_CONFLICT`/`CR_ISSUE_CONFLICT` 等前置条件拒绝）不写绑定字段，改为写 `activity_log(action='cr_issue_bind_rejected', ...)` 后提交/返回，零覆盖（FR-B4）。

### 4.2 review Skill 绑定前置步骤（FR-B7，四个 Skill 同一实现）

插在四个 review Skill"写临时评审 payload / 调用 `crctl review-record` 之前"（以 `review-tech-design` 的 Step 3 为例，其余三个同构）：

```text
若当前运行具有 Multica task-scoped context（存在 mat_ token 注入的 task 上下文）：
    result = bind-current-task-to-cr(CR-ID)
    if result 失败:
        → 按技术失败中止，不写 canonical review，不把失败转成业务 blocker
        （TASK_ISSUE_REQUIRED = 创建路径未按 FR-B12 携带 Issue 上下文，修路径后重试）
否则：
    → 视为普通本地/非 Multica 执行，跳过绑定，继续现有 review-record 行为（FR-A7）
```

位置选择依据：绑定放在 Skill（而非 Agent/Pipeline）——Skill 拥有业务编排步骤和 I/O，Agent 只路由、Pipeline 只循环。绑定放在评审时点（而非注册时点）：此时 CR 已注册、`cr` 投影存在，且审批卡只需在评审通过进入人工审批前可见；本轮 block 也不会显示错误审批卡（非审批状态 `pending_stage` 为空）。

### 4.3 审批卡渲染规则（FR-B6）

`project-team-agent-chat.tsx` 现循环（已核实：`for (const node of cr.gate_nodes) {...}` 只建 `CrGateCard`）改为：

```text
for each cr in crs:
    if cr.pending_stage != "":
        merged.push(ApprovalCard(cr=cr, wsId, projectId))       // 唯一当前审批卡
    for each node in cr.gate_nodes:
        if node.kind == "human_approval" and node.status == "running":
            continue                                           // 跳过当前 human_approval/running 节点
        merged.push(CrGateCard(cr, node))                     // 保留 blocked card 与历史节点
```

`CrGateCard` 保留既有"`human_approval`+`running` → ApprovalCard"分支供"恰好存在该 node"的场景（历史/兼容），但主渲染路径改为以 `pending_stage` 为准。两条路径同时成立时只会渲染一张 ApprovalCard（要么 `pending_stage` 分支、要么 `CrGateCard` 内分支，二者按上述循环逻辑互斥：跳过 `running` node 后由 `pending_stage` 分支唯一渲染当前卡）。

### 4.4 reviewer task 创建契约（FR-B12）

受支持的三条创建路径统一收敛"插入时原子继承 `issue_id`/`project_id`"：

1. **Pipeline review 节点 Runner 调度**：`EnqueuePipelineTask`/`CreatePipelineTask`——`PipelineTaskSpec` 增加 `SourceIssueID`/`SourceProjectID`（Runner 从来源 task 行解析），`CreatePipelineTask` SQL 从来源 task 行 `s.issue_id`/`s.project_id` 逐字拷贝进 INSERT；来源无 `issue_id` 则拒绝创建（`0 rows` → `RUNNER_ATTRIBUTION_INVALID` 或等价技术失败）。
2. **作者 Agent/coordinator 委派路由**：创建 quality-reviewer task 的路径必须携带来源 Issue 或父 task；平台在插入点从该可信来源继承，调用方不直接指定。
3. **issue 评论 mention 入队路径**：从该 Issue 与 `issue.project_id` 派生。

`bind-current-task-to-cr` 不信任调用方字段、仍只从 task 行与数据库关系派生 Issue/Project（FR-B1/B2 不变）；本契约只继承 `issue_id`/`project_id`，不权威写 `cr_id`（`cr_id` 仍由 review Skill 提交并受 workspace+CAS 校验），FR-B11 升级条件不变。

## 5. 技术选型与替代方案

本 CR 是"最小改造"，绝大多数实现复用既有能力，故决策记录只保留满足"难以逆转 + 无上下文会疑惑 + 有真实权衡替代"三判据的项；其余用"复用"表格而非伪造替代方案。

| 决策点 | Decision | Alternatives（真实权衡） | Consequences |
|---|---|---|---|
| 绑定放在 review Skill 还是 Agent/Pipeline | **review Skill**（FR-B7） | Agent 层：路由无 I/O 编排职责；Pipeline 层：会内嵌绑定 API/SQL 细节，违背"Prompt 不内嵌绑定" | Skill 拥有编排步骤与 I/O；代价是四个 review Skill 需同构改一遍（可接受，改动小且一致） |
| 绑定接口是否接受调用方 `issue_id`/`project_id` | **不接受**，全服务端从 task token + 数据库派生 | 接受调用方字段：省一次查询但把"谁绑谁"的权威交给客户端 | 身份不可伪造（NFR-4）；代价是接口必须 task-scoped、非 task 调用一律拒绝 |
| `cr_id` 是否由调度层权威写 | **否**（本 CR 不升级） | 调度层创建 reviewer task 时权威写 `cr_id`：彻底消除同 workspace 错绑，但需改 enqueue 协议/引入签名来源 | 保留残余风险（FR-B11 明示），错绑实际发生才升级；代价是信任上限降低但改动面最小 |
| 审批卡渲染依据 | **`pending_stage` 非空即渲染**（FR-B6） | 继续以 `gate_nodes` 为准：需先修 node 投影，且违背"当前状态足以决定当前审批卡"原则 | 前端只加一个分支 + 提取组件；代价是需保证 `pending_stage` 服务端语义稳定（已由既有 `pendingApprovalStage(status)` 提供） |
| 是否新增 reviewer task 的 Issue 继承为独立协议 | **否**，只补 `PipelineTaskSpec` 两字段 + `CreatePipelineTask` 两列 | 新增 enqueue 协议身份模型：超出本 CR 最小边界，且 PRD 明示不引入签名来源 | 改动面最小；代价是调用方仍可能漏配来源 Issue（由"来源无 issue_id 拒绝创建"兜底） |

复用清单（不重新设计，PRD §1.3 已核实）：

| 能力 | 复用点 |
|---|---|
| 评审落盘 | `crctl review-record`（零改动） |
| 人工审批 | `crctl approve`（零改动） |
| task token 身份 | `mat_` 中间件写入的 `X-Task-ID`/`X-Agent-ID`/`X-Workspace-ID` |
| CR→Issue 归因 | `SetTaskCRAttributionIfValid`（复用其 workspace 校验思想，补齐 CAS/审计/刷新） |
| 项目 gates 与审批卡 | `/api/projects/{id}/gates` 响应模型 + `ApprovalCard`/`CrGateCard` |

## 6. FR 到技术实现映射

### Track A（tools 仓）

| FR | 技术实现条目 |
|---|---|
| FR-A1 | 改 `agent-skill-matrix.yml`：从 `requirement-writer.owns` 删 `review-requirement`；从 `dev-agent.owns` 删 `review-tech-design`/`review-dev-plan`/`review-code`；四个 Skill 加入 `quality-reviewer-agent.owns`；两作者 Agent 保留 `can-call`。同步 `AGENT-SKILL-MATRIX.md` 说明。 |
| FR-A2 | `review-planning-report`（product-planning-agent owns）、`review-alignment`（quality-reviewer-agent owns）不动；改后 `check-skill-matrix.mjs` 仍满足"每个 active Skill 唯一 owns"。 |
| FR-A3 | 重写 `agents/requirement-writer.md`、`agents/dev-agent.md` 评审意图为委派路由合同（读 `crctl next` → 新建 quality-reviewer task（携带来源 Issue/父 task）→ 只传 CR-ID+workspace+Skill 输入 → 等结构化结果 → 只消费 blocker 回修）；`agents/_index.yml` 只同步实际 capability 变化。 |
| FR-A4 | 改 `requirement-authoring`（review-requirement）、`architecture-design`（review-tech-design）、`code-implementation`（review-dev-plan + review-code）四个 review 节点 prompt，明确"新建独立 reviewer task/run、每轮 reviewLoop 重新委派、技术失败 onFail=abort、业务 block 走既有 reviewLoop"；不内嵌绑定 API/SQL/评审维度。 |
| FR-A5 | 独立评审入口只执行一轮；回修/重评仍归 Pipeline `reviewLoop`；不新增 `crctl review` 命令。 |
| FR-A6 | 不支持 subagent 的运行时：Pipeline 停在 review 节点 + 提示另开独立会话，不退化为作者自评。 |
| FR-A7 | 改后 `emit-registry.mjs`/`check-skill-matrix.mjs`/`check-agents-contract.mjs` 通过；无 Multica task context 的本地运行跳过绑定、继续原 `review-record`。 |
| FR-A8 | 不引入 run attestation/`can-delegate`/matrix parser 修改；旧 PASS 不自动作废；`README.md` 仅在需要时补一段人读说明。 |

### Track B（Multica 仓）

| FR | 技术实现条目 |
|---|---|
| FR-B1 | 新增 `POST /api/crs/{cr_id}/bind-current-task`（§3.1）+ CLI 薄包装（§3.3）；handler 只接受 `mat_` task token，身份字段全服务端派生。 |
| FR-B2 | `TaskService.BindCurrentTaskToCR` 单事务九步校验 + 三写入（§4.1）。 |
| FR-B3 | 七种错误语义表（§3.1），零绑定写入，不转业务 blocker、不 bump attempt。 |
| FR-B4 | 冲突路径写 `activity_log(action='cr_issue_bind_rejected', workspace/issue/project/task/agent/cr/当前值/原因)`，不新建审计表。 |
| FR-B5 | 保留 `daemon.go` StartTask → `AttributeTaskToCR` best-effort 归因（兼容/辅助可见性），非审批卡充分条件。 |
| FR-B6 | 提取 `ApprovalCard` 组件 + `project-team-agent-chat.tsx` 渲染规则改（§4.3）；gates API schema 不变。 |
| FR-B7 | 四个 review Skill 在 `review-record` 前插入同一绑定前置步骤（§4.2）。 |
| FR-B8 | 存量 CR-2026-051/052 走受控 task + 同一接口（验收步骤 AC-D1~D6，不在本轮编辑时执行）；禁用直接 SQL。 |
| FR-B9 | 复用 `agent_task_queue.cr_id`、`cr.shell_issue_id`、`activity_log`；改 `agent.sql` + `make sqlc` 再生成；不新增表/列/索引/外键。 |
| FR-B10 | 全部 multica 落代码在 `CUSTOM.md` 对照其当时实际结构登记（编号顺延、原因含 CR-2026-053 + TASK）。 |
| FR-B11 | 在 SDD §7 与代码注释固化信任上限声明：task token 权威证明 task/agent/workspace；CR-ID 由 Skill 提交；同 workspace 内错绑风险存在，CAS/审计/独立路由降概率不构成密码学来源证明。 |
| FR-B12 | `PipelineTaskSpec` 增 `SourceIssueID`/`SourceProjectID` + `CreatePipelineTask` INSERT 从来源 task 行拷贝 `issue_id`/`project_id`；来源无 `issue_id` 拒绝创建（§4.4）。 |

## 7. 安全与性能考量

### 7.1 安全控制点

- **身份不可伪造（NFR-4）**：task/agent/workspace 由 `mat_` task token 中间件权威写入、覆盖客户端头（`auth.go:104-106`）；Issue/Project 由 task 行与数据库关系派生，调用方不能指定。handler 层按 multica CLAUDE.md"Backend UUID Rules"经 `parseUUIDOrBadRequest` 解析路径 `cr_id` 外的 UUID，任务/工作区身份一律来自 actor context。
- **CAS 零覆盖（NFR-2）**：两个绑定字段只允许 `NULL → 值` 或同值；异值拒绝，防止恶意/错误 task 抢先错绑（FR-B11 残余风险受控）。
- **人类审批边界**：Agent 不得代批准；review PASS 与人工批准仍是两个节点；本 CR 不改 `crctl approve` 授权模型（NFR-4，ARCHITECTURE.md 不变量 7）。
- **失败关闭**：认证/workspace/authority 边界 fail closed；绑定失败硬失败、不静默降级写 canonical review（NFR-6）。

### 7.2 性能

- 绑定事务是单行级 `FOR UPDATE` + 两行 CAS 更新 + 一次审计插入，处于 review 时点（低频、非热路径），无吞吐风险。
- `CreatePipelineTask` 增加两列拷贝来自已锁定来源行 `s.*`，无额外 JOIN/索引开销。
- 前端渲染改为每 CR 至多一张 ApprovalCard + 历史节点，复杂度与现有遍历同级，无新增网络请求（复用既有 gates 查询结果）。

### 7.3 边界条件

- `pending_stage` 为空（CR 非审批状态）→ 不渲染当前审批卡；CR 离开审批状态后当前卡自然消失、历史节点保留（AC-C4）。
- 同值重放 → `changed=false`，不破坏绑定（AC-B3）。
- 事务/审计失败 → 两字段零部分更新（AC-B6）。
- 事件发布失败 → 不回滚已提交事务，记错误并依赖既有重查询恢复（NFR-5）。

## 8. Prompt 采纳影响

> 本节为条件性小节（CR-2026-021 FR-25/AC-15）。本 CR 的 diff **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，也**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（范围排除明示 crctl 零改动、不新增 `crctl review` 命令），故本节省略。
> 唯一与 crctl 相关的变化是"review Skill 在 `review-record` 之前插入平台绑定前置步骤"，该变化发生在 Skill 文档层，不影响 crctl 命令面或 guard deny 面。

## 9. 实施文件清单与提交口径

### tools 仓（Track A）

修改：`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`agents/quality-reviewer-agent.md`、`agents/requirement-writer.md`、`agents/dev-agent.md`、`agents/_index.yml`、`pipeline-templates/{requirement-authoring,architecture-design,code-implementation}.pipeline.json`、`skills/requirement/review-requirement/SKILL.md`、`skills/develop/{review-tech-design,review-dev-plan,review-code}/SKILL.md`、（如需）`README.md`。不修改：`dir-graph.yaml`、`gates.json`、`crctl approve`/`review-record` 协议、matrix parser。

### multica 仓（Track B）

修改：`server/cmd/server/router.go`、新增 handler、`server/internal/service/task.go`、`server/pkg/db/queries/agent.sql` + sqlc 生成物、CLI 薄命令、`packages/views/projects/components/cr-gate-card.tsx`、`project-team-agent-chat.tsx`、对应 Go/React 测试、`CUSTOM.md`。

### 提交/checkpoint 口径

- SDD 本文件落盘到 knowledge-base 仓（operational workspace）`change-requests/CR-2026-053/sdd.md`，提交消息 `[cr] write tech design CR-2026-053`。
- 两个目标代码仓的 ARCHITECTURE.md 均已存在（`tools/ARCHITECTURE.md`、`multica/ARCHITECTURE.md`），本轮**不新起草**、只读引用。
- Track A/B 代码变更在 code-implementation 阶段于各自 `resources[].worktreePath` 分别提交；架构审批后由同一批 `crctl checkpoint` 纳入（FR-07.2 口径）。

## 10. 残余风险与升级条件

| 风险 | 当前控制 | 升级条件 |
|---|---|---|
| 作者 Agent 技术仍可直接调用 review Skill | 唯一 owner + Agent 路由 + Pipeline prompt + 结构测试 | 再发真实自评逃逸 → 引入调用级执行身份拦截 |
| CR-ID 由 Skill 提交，同 workspace 内可能错绑 | task token + 数据库派生 Issue/Project + CAS + 审计 | 错绑实发或安全升级 → 调度层权威写 `task.cr_id` |
| 不支持 subagent 的运行时不能单会话跑完 | 停在 review 节点 + 第二独立会话 | 多运行时频繁受阻 → 统一调度 Adapter |
| 成功事务后刷新事件发送失败 | 记错误，依赖现有重查询恢复 | 持续不可见 → 复用现有事件重试能力 |
| 旧 PASS 无独立运行证明 | 保留历史、已知事故 CR 手工重评 | 不批量废止/伪造身份 |

---

**SDD 完成标志**：本文件完整落盘后，将 CR status 从 `requirement-approved` 推进 `tech-designing` → `tech-design-review-pending`，等待 `review-tech-design` 进入。
