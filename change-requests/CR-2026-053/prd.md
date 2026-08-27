---
id: CR-2026-053-prd
type: PRD
cr-ref: CR-2026-053
title: 独立评审与人工审批命令闭环 — 评审独立路由与审批卡可见性修复
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-27T17:35:57+08:00
updated: 2026-08-27T17:35:57+08:00
---

# 1. 概述

## 1.1 问题陈述

依据《独立评审与人工审批命令闭环设计》v0.4（本 CR source 文档）对 CR-2026-051/052 的实测复盘，评审与审批链路存在两个已确认缺口（source §3，逐项核实见附录 A）：

1. **独立评审路由缺口（缺口 A）**：`quality-reviewer-agent.md` 已把需求、技术设计、开发计划、代码四类评审写进自己的路由表，但 `agent-skill-matrix.yml` 仍把四个 review Skill 的 `owns` 放在作者型 Agent（`review-requirement` 归 `requirement-writer`，`review-tech-design`/`review-dev-plan`/`review-code` 归 `dev-agent`），`requirement-writer.md` 与 `dev-agent.md` 仍把评审写成当前 Agent 可直接执行的意图，三条 CR Pipeline 的 review 节点 prompt 也未要求新建独立 reviewer 任务。因此 annotation 存在、`verdict=pass`、`blockers=[]` 只能证明评审证据**形状**满足门禁，不能证明作者与 reviewer 是两个独立运行——CR-2026-052 的直接根因是 owner 与路由合同错误（作者 Agent 在同一运行中完成"写 + 评"逃逸），不是 `review-record` 缺事务或签名协议。
2. **审批卡可见性缺口（缺口 B）**：项目 gates 查询通过 `cr.shell_issue_id → issue.project_id` 限定项目 CR，但真实注册流程没有稳定填充 `cr.shell_issue_id`（CR-2026-051/052 该字段为 `NULL`），CR 即使在审批状态也会在 gates 查询阶段被过滤；且前端 `ProjectTeamAgentChat` 只遍历 `cr.gate_nodes` 创建 `CrGateCard`，即使服务端已按 `cr.status` 返回非空 `pending_stage`，只要没有当前 `human_approval/running` node，审批卡仍不显示——违反"当前状态足以决定当前审批卡，节点只提供历史和 blocker 增强"的既有设计原则。

修复方向明确：慢不在 `crctl` 或审批协议本身，而是"作者可自评"与"CR 未进入项目审批读路径"两个断点；`crctl` 状态机、门禁、`review-record`、`approve` 协议均无结构性缺陷，禁止重写。

## 1.2 解决方案摘要

一个 CR、两条独立工作轨，共享的只有 CR-ID 与现有执行环境，不建设共同的新框架：

1. **Track A（tools 仓）——独立评审最小改造**：四个 CR 评审 Skill（`review-requirement`/`review-tech-design`/`review-dev-plan`/`review-code`）的唯一 `owns` 收敛为 `quality-reviewer-agent`；作者型 Agent（`requirement-writer`/`dev-agent`）移除 `owns`、保留 Pipeline registry 所需的 `can-call`，其评审意图改为委派路由合同（创建新的 quality reviewer 任务 → 只传 CR-ID、权威 workspace 与 Skill 已声明输入 → 等待结构化评审结果 → 只消费 blocker 回修）；三条 CR Pipeline 的 review 节点 prompt 明确要求新建独立 quality reviewer task/run，每轮 reviewLoop 重新委派。Pipeline schema、节点顺序、`reviewLoop`、`onFail`、状态机、gates、`review-record`/`approve` 协议全部保持不变。
2. **Track B（Multica 仓）——CR→Issue 绑定与审批卡可见性**：新增一个 task-scoped 窄接口 `POST /api/crs/{cr_id}/bind-current-task`，在四个 review Skill 写临时评审 payload 之前执行同一平台前置步骤，把当前 task 原子绑定到 CR/Issue（同事务写 `agent_task_queue.cr_id` + `cr.shell_issue_id` + `activity_log`，CAS 只允许 `NULL → 值` 或同值）；前端 gates 改为 `pending_stage` 非空即渲染唯一 `ApprovalCard`（从 `CrGateCard` 提取组件，保留 blocked 卡与历史节点）；存量 CR-2026-051/052 经受控 task 走同一接口修复，禁止直接 SQL。

目标闭环（source §1 原样）：

```text
作者 Agent 产出阶段内容 → Pipeline 到达 review-* 节点 → 新建 quality-reviewer-agent 独立任务
→ review Skill 先将当前 Multica task 绑定到 CR/Issue → review Skill 作业务判断
→ crctl review-record 原子记录评审证据 → Pipeline 按现有 reviewLoop 回修或进入 human_approval
→ crctl/Multica 状态投影得到 pending_stage → 项目会话显示唯一 ApprovalCard → 人类批准或驳回
→ 现有 Ed25519 grant 经 daemon 投递 → crctl approve 复核门禁并推进状态
```

本设计不创建第二套评审凭证、来源证明、审批主体、状态机或事务框架。

## 1.3 已核实能力（只复用，不重复建设）

| 能力 | 既有实现（已核实，见附录 A） | 本 CR 处理 |
|---|---|---|
| 评审落盘 | `crctl review-record`：payload schema 校验、subject digest、attempt/review-loop、canonical annotation、traceability 投影、审计/outbox、CAS 与 durable transaction | 零改动；review Skill 继续只做业务判断 + 调用 |
| 人工审批 | `crctl approve`：TTY 审批与 Web/Desktop Ed25519 grant 统一入口、门禁重验、evidence freshness、CAS、审批账本与状态原子推进 | 零改动；不新增第三套审批协议 |
| Pipeline 编排 | 三条 CR Pipeline 的节点顺序、输入传递、`reviewLoop`、blocker 回修、技术失败中止、`human_approval → approve-*` 顺序 | 仅改四个 review 节点 prompt 的委派要求；schema/Runner 不动 |
| Multica task 上下文 | `agent_task_queue.issue_id`/`project_id`/`cr_id`、task claim 时签发的 `mat_` task-scoped token、认证中间件从 token 权威恢复 `user_id`/`agent_id`/`task_id`/`workspace_id` | 复用为新绑定接口的身份来源 |
| 既有 CR→Issue 归因 | `TaskService.AttributeTaskToCR` / `SetTaskCRAttributionIfValid`（CR-2026-011）、`cr.shell_issue_id` 列（migrations/433） | 补齐其不足（权威 task 身份、Issue/Project 闭合校验、CAS、事务审计、刷新事件），不重写 enqueue 路径 |
| 项目 gates 与审批卡 | `/api/projects/{id}/gates`（`pending_stage`/`can_approve`/evidence/`pending_advance`/`gate_nodes`）、`CrGateCard`/`ApprovalCard`、批准/驳回 API、grant 签发、daemon 投递与 ACK、`activity_log`、`cr:updated`/项目刷新事件 | 只改前端渲染规则与新增一个窄绑定接口；响应 schema 不变 |
| 权限矩阵与契约校验 | `agent-skill-matrix.yml`（每 active Skill 唯一 `owns`）、`emit-registry.mjs`、`check-skill-matrix.mjs`、`check-agents-contract.mjs` | 只调整 owner 与 can-call 归属；不新增 `can-delegate` 关系、不改 matrix parser |

职责边界保持不变（source §4）：评审/路由在 Agent+Skill 层，状态与账本只在 `crctl` 层，确定性转换在版本化脚本层；Multica 只负责「校验 task token 上下文、原子绑定 task→CR→Issue、按既有 `pending_stage` 显示唯一当前卡片」，不复制状态机、不做评审判断、不猜关联。

## 1.4 需求边界（注册摘要已拍板，原样采纳）

- 只覆盖与 CR 审批门禁直接相关的四个 review Skill；`review-planning-report` 与 `review-alignment` 保持现状；
- 只补齐两个已确认缺口，不新增评审凭证/来源证明/审批主体/状态机/事务框架；
- 保留 `can-call` 是兼容要求（registry 与 Agent contract 校验现状），不代表允许作者同运行自评；实际独立性由「唯一 owner + Agent 路由 + Pipeline 委派合同 + 结构测试」共同约束；
- 本设计提供组织性强制，不提供密码学运行身份证明（不新增 run attestation；旧 PASS 不自动作废、不回填历史身份）；
- 存量 CR-2026-051/052 修复走受控 task + 同一绑定接口，禁用会话内直接 SQL；
- 文档性质：source 文档是平台级最小改造设计，本轮实现仍须通过本 CR 完成 PRD、SDD、TASK、开发、评审与人工审批全流程。

# 2. 用户故事

- **US-1（CR 流程 owner / 平台维护者）**：作为流程 owner，我希望四类评审证据的 reviewer 与作者是两个独立运行，这样"写 + 评"的逃逸不再可能，评审结论才值得进入人工审批。
- **US-2（作者型 Agent / requirement-writer、dev-agent）**：作为产出阶段内容的作者，我希望到达 review 节点时创建新的独立 quality reviewer 任务、只传最小输入并等待结构化评审结果，然后只消费 blocker 执行回修，而不是在同一运行中自己评审自己。
- **US-3（quality-reviewer-agent）**：作为唯一评审 owner，我希望在写评审 payload 前先把当前 Multica task 绑定到 CR/Issue（成功才继续 `review-record`，失败按技术失败中止），这样评审证据与 CR 的项目上下文同步建立，且绑定失败不会污染 canonical 评审。
- **US-4（审批人 / 项目成员）**：作为项目会话里的审批人，我希望 CR 进入任一审批状态时都能看到唯一一张审批卡（即使当前没有 `human_approval/running` gate node），批准或驳回的操作方式与今天完全一致。
- **US-5（存量 CR 维护者）**：作为 CR-2026-051/052 的维护者，我希望从已核实的来源 Issue 启动一次受控 task 就能修复 CR→Issue 关联，并且该操作有审计、不需要直接碰共享数据库。
- **US-6（本地 IDE 用户）**：作为不支持 subagent 的运行时用户，我希望流程停在 review 节点并提示我另开独立会话以 reviewer 身份完成评审，而不是静默退化为作者自评。

# 3. 功能需求

> 范围归属：FR-A1 ~ FR-A8 为 tools 仓；FR-B1 ~ FR-B11 为 Multica 仓。所有「已核实」断言见附录 A。

## Track A —— 独立评审最小改造（tools）

## FR-A1 四个评审 Skill 唯一 owner 收敛

`agent-skill-matrix.yml` 中 `review-requirement`、`review-tech-design`、`review-dev-plan`、`review-code` 四个 Skill 的 `owns` 必须且只属于 `quality-reviewer-agent`；`requirement-writer` 与 `dev-agent` 不再 `owns` 这四个 Skill，但保留对相应 review Skill 的 `can-call`（兼容 `emit-registry.mjs` 对 Pipeline owner 的 `owns|can-call` 要求与 `check-agents-contract.mjs` 的引用校验）。`AGENT-SKILL-MATRIX.md` 同步更新说明，不得只改 YML 不改说明文档。

## FR-A2 评审范围锁定

`review-planning-report` 与 `review-alignment` 的 owner、can-call 关系与流程保持现状，不在本 CR 顺带调整。改造后 `check-skill-matrix.mjs` 必须仍满足"每个 active Skill 有且只有一个 `owns` owner"。

## FR-A3 作者型 Agent 委派路由合同

`agents/requirement-writer.md` 与 `agents/dev-agent.md` 的评审意图改为委派路由合同（source §5.3）：

```text
读取 crctl next / 当前 Pipeline review 节点
→ 创建新的 quality-reviewer-agent 任务
→ 只传 CR-ID、权威 workspace 和该 review Skill 已声明的输入
→ 等待结构化评审结果
→ 作者 Agent 只消费 blocker 并执行回修，不代替 reviewer 判断
```

独立入口"独立评审 `<CR-ID>`"遵守相同合同：路由 Agent 先调用 `crctl next` 确认当前合法 review Skill，再委派给 `quality-reviewer-agent`。不新增 `crctl review` 包装命令。`agents/_index.yml` 只同步实际 capability/reference 变化。

## FR-A4 Pipeline 委派合同（只改 review 节点 prompt）

三条 CR Pipeline（`requirement-authoring`、`architecture-design`、`code-implementation`）的 schema、节点顺序、`reviewLoop`、`onFail`、状态转换全部保持不变，只修改四个 review 节点的 prompt，明确要求：

- reviewer 必须是新建的 `quality-reviewer-agent` task/run，不得恢复作者会话执行评审；
- 每轮 review loop 都是一次新的 reviewer 执行，不复用作者会话；
- 技术失败按现有 `onFail=abort` 中止；
- 业务 `verdict=block` 继续按既有 `reviewLoop` 返回 writer/implementation 节点；
- Pipeline prompt 不内嵌 task binding API、SQL、评审维度或 `crctl` 落盘算法。

## FR-A5 一次独立评审一轮制

一次独立评审入口只执行一轮评审（一个 review Skill 一次 `review-record`）；重复回修与重评仍归 Pipeline `reviewLoop` 持有，独立入口不得自建循环。

## FR-A6 不支持 subagent 的运行时不降级自评

目标 IDE/runtime 不能从作者会话创建独立 subagent 时：

1. Pipeline 停在当前 review 节点；
2. 不得退化为作者直接评审；
3. 提示用户另开独立会话，以 `quality-reviewer-agent` 身份运行同一个 review Skill；
4. canonical review 结果完成后，原 Pipeline 再继续。

此路径允许多一次人工启动，不改变状态机、不破坏 CR 数据。

## FR-A7 结构测试与本地路径兼容

- `emit-registry.mjs`、`check-skill-matrix.mjs`、`check-agents-contract.mjs` 及既有 matrix/Agent contract/Pipeline structure 测试在改造后全部通过；
- 普通本地 pi/Claude/IDE 运行（无 Multica task-scoped context）跳过平台绑定步骤，继续按现有方式调用 `crctl review-record`，行为与改造前一致。

## FR-A8 诚实边界固化

本工作轨提供组织性强制，不提供密码学运行身份证明：`crctl` 不新增 run attestation 校验；旧 PASS 不自动作废；不伪造或回填历史 reviewer 身份；不新增 `can-delegate` 关系、不修改 matrix parser；`README.md` 仅在需要时补一段人读兼容说明，不复制实现合同。若未来出现结构约束仍无法控制的真实逃逸，再独立设计运行身份与调用拦截层（升级条件见附录 B）。

## Track B —— CR→Issue 绑定与审批卡可见性（Multica）

## FR-B1 task-scoped 窄绑定接口

新增 `POST /api/crs/{cr_id}/bind-current-task`（`Authorization: Bearer mat_...`）：

- 请求不接受 `task_id`、`agent_id`、`workspace_id`、`issue_id`、`project_id`——这些值全部由服务端获取：`task_id`/`agent_id`/`workspace_id` 来自 task token 认证中间件写入的权威 actor context，`issue_id`/`project_id` 来自 `agent_task_queue` 与对应 Issue/Project；
- 调用方只提供需要绑定的 CR-ID；
- 成功响应 `{ "cr_id", "task_id", "issue_id", "project_id", "changed": true }`；同值重放返回 `changed=false`；
- 附 Multica CLI 薄包装命令。

## FR-B2 校验与单一事务绑定

服务端在一个数据库事务中锁定并校验 task、Issue、Project 和 CR（source §6.3）：

1. 请求必须由有效、未撤销的 task token 发起；
2. token 中的 task 必须存在且属于 token workspace/agent；
3. task 必须有 `issue_id`；
4. Issue 必须属于同一 workspace 且属于一个有效 Project；
5. task 已有 `project_id` 时，必须与 `issue.project_id` 相同；
6. CR 必须存在于同一 workspace；
7. `agent_task_queue.cr_id` 只允许 `NULL → cr_id` 或同值；
8. `cr.shell_issue_id` 只允许 `NULL → issue_id` 或同值；
9. 非空异值一律拒绝，不覆盖、不猜测。

成功路径在同一事务内完成：更新 `task.cr_id` + 更新 `cr.shell_issue_id` + 写 `activity_log(action=cr_issue_bound)`。任一写入或审计失败，整个事务回滚（两个绑定字段均不得部分更新）。事务提交后再发布现有 `cr:updated`/项目刷新事件；事件发布失败不回滚已提交事务，但必须记录错误并依赖现有重新查询机制恢复 UI。

## FR-B3 错误语义（七种，零绑定写入）

| 错误 | 含义 | 结果 |
|---|---|---|
| `TASK_CONTEXT_REQUIRED` | 不是 task token 调用 | 零绑定写入 |
| `TASK_ISSUE_REQUIRED` | 当前 task 没有 Issue | 零绑定写入，review Skill 中止 |
| `CR_NOT_FOUND` | 同 workspace 中不存在该 CR | 零绑定写入 |
| `TASK_PROJECT_MISMATCH` | task/Issue/Project 关系不闭合 | 零绑定写入 |
| `TASK_CR_CONFLICT` | task 已绑定另一 CR | 零覆盖 |
| `CR_ISSUE_CONFLICT` | CR 已绑定另一 Issue | 零覆盖 |
| `CR_BIND_FAILED` | 事务或审计失败 | 全部回滚 |

这些错误是技术失败，不得转换成业务 blocker，也不得递增一次成功评审的 attempt。

## FR-B4 冲突审计

冲突（前置条件拒绝）不执行绑定写入，平台使用现有 `activity_log` 记录 `cr_issue_bind_rejected`，字段含 workspace、Issue、Project、task、Agent、CR、当前值与拒绝原因；不为此新建审计表。

## FR-B5 现有 StartTask 归因处置

现有 daemon `StartTask` 分支自报 CR-ID 的 best-effort 归因保留（用于兼容和辅助可见性），但不是审批卡绑定的充分条件；新接口复用其 workspace 校验思想并补齐权威 task 身份、Issue/Project 闭合校验、`cr.shell_issue_id` CAS、事务审计与成功后的项目刷新。不要求重写全部任务 enqueue 路径。

## FR-B6 审批卡渲染规则

`GET /api/projects/{id}/gates` 保持现有响应模型，不新增 `pending_approval`、`gate_history` 或另一套 status→stage 映射。前端改为：

```text
对每个 CR：
  pending_stage 非空 → 直接渲染一个 ApprovalCard
  遍历 gate_nodes → 跳过当前 human_approval/running 节点 → 保留 blocked card 与已完成/失败历史
```

`ApprovalCard` 从 `CrGateCard` 内部实现中提取为可直接调用的组件，继续消费相同字段（`cr.cr_id`、`cr.pending_stage`、`cr.can_approve`、`cr.evidence`、`cr.evidence_digest`、`cr.pending_advance`）。批准/驳回仍调用现有 API；前端不构造伪 `GateNode`、不直接改状态、不签发新类型 grant。

该规则保证：有审批状态、无 gate node 时显示一张当前审批卡；同时有 `human_approval/running` node 时仍只显示一张当前审批卡；blocker 和历史节点继续显示；`pending_stage` 为空时不显示当前审批卡；CR 离开审批状态后当前卡片自然消失。

## FR-B7 review Skill 绑定前置步骤（四个 Skill 同一实现）

四个 review Skill（`review-requirement`/`review-tech-design`/`review-dev-plan`/`review-code`）在写临时评审 payload、调用 `crctl review-record` **之前**增加同一个平台前置步骤：

```text
若当前运行具有 Multica task-scoped context：
  调用 bind-current-task-to-cr(CR-ID)
  成功后继续 review-record
  失败则按技术失败中止，不写 canonical review
否则：
  视为普通本地/非 Multica 执行，保持现有 review-record 行为
```

绑定放在 review Skill（不是 Agent 或 Pipeline）：Skill 拥有业务编排步骤和 I/O；Agent 只负责路由，Pipeline 只负责节点与循环。选择评审时点是因为此时 CR 已完成注册（CR-ID 与 `cr` 投影存在）且审批卡只需在评审通过、进入人工审批前可见；本轮评审为 block 也不会显示错误审批卡（非审批状态 `pending_stage` 为空）。

## FR-B8 存量 CR 修复路径（CR-2026-051/052）

1. 人类确认各自来源 Issue；
2. 从该 Issue 启动一次受控 Multica task；
3. task 调用同一个 `bind-current-task-to-cr(CR-ID)`；
4. 服务端执行相同校验、CAS 和审计；
5. 项目 gates 重新查询后验证卡片可见。

这是后续实现 CR 的验收步骤，不在本轮设计文档编辑时立即执行。禁止用会话内直接 SQL 代替该路径。不新增 `reconcile-cr-origin` 或通用 reconcile 子系统。

## FR-B9 不新增表与列

不新增数据库列或新表；复用 `agent_task_queue.cr_id`、`cr.shell_issue_id` 和 `activity_log`。`server/pkg/db/queries/agent.sql` 及项目要求的 sqlc 生成物按仓库既有惯例更新。

## FR-B10 CUSTOM.md 台账登记

凡在 multica 仓落代码（API 路由与 handler、TaskService 绑定事务、agent.sql 与生成物、CLI 薄命令、前端两个组件文件与对应测试），必须在 `CUSTOM.md` 对照其当时实际结构登记（编号顺延、原因追溯含 CR 编号与 TASK）。

## FR-B11 信任上限与残余风险声明

本最小方案明确接受（source §6.8）：task token 可以权威证明 task、Agent 和 workspace；Issue/Project 由 task 行和数据库关系派生，不能由调用方伪造；CR-ID 仍由 review Skill 提交，服务端只能校验该 CR 属于同一 workspace——因此同 workspace 内恶意或错误的 task 理论上可能抢先把尚未绑定的 CR 绑定到错误 Issue。CAS、独立 reviewer 路由、结构测试和 `activity_log` 降低概率并提供追责，但不构成 CR→Issue 的密码学来源证明。本 CR 不为该风险改造 enqueue 协议或引入签名来源；只有在实际发生错绑或风险评估升级时，才把合同升级为"调度层创建 reviewer task 时权威写入 `cr_id`"。

# 4. 非功能需求

- **NFR-1 原子性**：绑定三写入（`task.cr_id`、`cr.shell_issue_id`、`activity_log`）同一事务，任一部分失败全部回滚，无中间可见状态。
- **NFR-2 零覆盖（CAS）**：两个绑定字段只允许 `NULL → 值` 或同值重放；异值一律拒绝，不覆盖既有事实。
- **NFR-3 兼容性**：`crctl` 状态机、gates、`advance`、`approve` 协议、grant schema、daemon 投递与 ACK、gates API 响应 schema、Pipeline schema 与 `reviewLoop`、TTY/Web 审批授权模型全部保持不变；旧评审 annotation 保持可读、旧 PASS 不自动作废。
- **NFR-4 安全**：调用方不得伪造身份字段（task/agent/workspace/Issue/Project 一律服务端从 token 与数据库派生）；Agent 不得代表人点击或批准；review PASS 与人工批准仍是两个不同节点。
- **NFR-5 可观测**：绑定成功与拒绝均落 `activity_log` 审计；成功绑定后发布既有刷新事件；事件发布失败必须记录错误。
- **NFR-6 诚实降级**：无 task context 的本地执行跳过绑定步骤照常评审；有 context 但绑定失败必须硬失败，不得静默降级为"跳过绑定继续写 canonical review"。

# 5. 验收标准

## Track A（对应 FR-A1 ~ FR-A8，源自 source §11.1）

- [ ] **AC-A1**（FR-A1/A2）：四个 CR review Skill 各自只有一个 owner，且均为 `quality-reviewer-agent`；`requirement-writer`、`dev-agent` 不再 owns 四个 review Skill，但保留 Pipeline registry 所需的 `can-call`。
- [ ] **AC-A2**（FR-A2）：`review-planning-report` 与 `review-alignment` 的 owner/流程未被本 CR 改动。
- [ ] **AC-A3**（FR-A7）：`emit-registry.mjs`、`check-skill-matrix.mjs`、`check-agents-contract.mjs` 继续通过。
- [ ] **AC-A4**（FR-A3/A4）：`requirement-writer.md`、`dev-agent.md` 的评审意图为委派路由合同；三条 CR Pipeline 的 review 节点 prompt 明确要求新建独立 quality reviewer task/run。
- [ ] **AC-A5**（FR-A4）：每轮 `reviewLoop` 都重新委派 reviewer，不复用作者会话；原 Pipeline 节点顺序、`reviewLoop`、`onFail` 和状态转换保持不变。
- [ ] **AC-A6**（FR-A5/A6）：一次独立评审入口只执行一轮 review，回修循环仍由 Pipeline 持有；运行时不支持 subagent 时停在 review 节点并提示独立会话，不直接自评。
- [ ] **AC-A7**（FR-A7）：普通本地 pi/Claude/IDE 路径仍可按原方式调用 `crctl review-record`。
- [ ] **AC-A8**（FR-A8）：改造不引入 run attestation、`can-delegate` 关系或 matrix parser 修改；旧评审证据保留原样。

## Track B 绑定（对应 FR-B1 ~ FR-B5、FR-B7 ~ FR-B11，源自 source §11.2）

- [ ] **AC-B1**（FR-B1）：handler 只接受 task token，不信任调用方提交的 task/agent/workspace/Issue/Project ID。
- [ ] **AC-B2**（FR-B2）：同 workspace、有效 Issue/Project 的 task 可以绑定同 workspace CR；成功事务同时写 `task.cr_id`、`cr.shell_issue_id` 和 `activity_log`。
- [ ] **AC-B3**（FR-B1/B2）：同值重放返回 `changed=false`，不破坏现有绑定。
- [ ] **AC-B4**（FR-B3）：task 无 Issue 时拒绝且零绑定写入；task、Issue、Project、CR 任一跨 workspace 或关系不一致时拒绝。
- [ ] **AC-B5**（FR-B2/B3）：task 已绑定另一 CR、CR 已绑定另一 Issue 时均拒绝且零覆盖。
- [ ] **AC-B6**（FR-B2）：事务或审计写入失败时两个绑定字段均不发生部分更新。
- [ ] **AC-B7**（FR-B2/B4）：绑定成功后发布现有刷新事件，项目 gates 可重新查询到 CR；冲突被拒时落 `cr_issue_bind_rejected` 审计。
- [ ] **AC-B8**（FR-B7）：review Skill 在绑定失败时不调用 `review-record`，也不把失败写成业务 blocker；无 task context 时跳过绑定、现有行为不变。
- [ ] **AC-B9**（FR-B9/B10）：不新增数据库表/列；multica 落代码在 `CUSTOM.md` 登记。

## Track B 审批卡（对应 FR-B6，源自 source §11.3）

- [ ] **AC-C1**：`pending_stage` 非空且 `gate_nodes=[]` 时显示一张 ApprovalCard。
- [ ] **AC-C2**：同时存在 `human_approval/running` node 时仍只显示一张 ApprovalCard。
- [ ] **AC-C3**：blocked review card 与已完成/失败历史继续显示。
- [ ] **AC-C4**：`pending_stage` 为空时不显示当前审批卡；CR 离开审批状态后当前审批卡消失，历史节点保留。
- [ ] **AC-C5**：原 `can_approve`、evidence、`pending_advance` 展示行为保持不变；原批准、驳回、权限拒绝、evidence drift 和 grant 测试继续通过。
- [ ] **AC-C6**：gates API 响应 schema 保持兼容。

## 存量验证（对应 FR-B8，源自 source §11.4）

- [ ] **AC-D1**：从 CR-2026-051 的已核实来源 Issue 启动受控 task，并通过同一接口建立关联。
- [ ] **AC-D2**：从 CR-2026-052 的已核实来源 Issue 启动受控 task，并通过同一接口建立关联。
- [ ] **AC-D3**：两次操作均有 activity audit，且未直接执行共享数据库 SQL。
- [ ] **AC-D4**：绑定后对应项目 gates 能查询到 CR。
- [ ] **AC-D5**：CR 位于审批状态时，即使当前 approval node 缺失也能显示唯一卡片。

# 6. 成功指标

- **评审独立性**：本 CR 合入后新产生的四类评审证据，其 reviewer 运行与作者运行为两个独立 task/run（作者只消费 blocker 回修）；已知作者自评逃逸次数 = 0，再次发生即触发附录 B 升级条件。
- **审批卡可见性**：处于四个审批门禁状态的 CR 在对应项目会话中 100% 显示唯一当前审批卡（含 `gate_nodes=[]` 场景）。
- **存量修复**：CR-2026-051/052 通过受控 task 绑定后，各自项目 gates 查询可见。
- **零回归**：三条 CR Pipeline 结构测试与三个契约校验脚本全部通过；gates API schema 兼容性测试通过。
- **审计闭环**：每次绑定成功/拒绝均有 `activity_log` 记录，可追溯 workspace/Issue/Project/task/Agent/CR。

# 7. 范围排除（source §9 非目标，原样）

本 CR 不实施：

- `registration-origin` 签名协议；run attestation；`artifact-record`；artifact/review provenance 新账本；Multica Registration Origin Adapter；
- 新 Approval Read Model；新 stage evaluator 或状态映射生成系统；
- `can-delegate` matrix 关系；Pipeline schema/Runner 改造；`crctl review` 包装命令；
- delegated approval Agent；agent grant v2；审批委托表、风险分级或新 `approval_gate`；
- PowerShell 审批命令生成与展示；标题、时间、评论或 Agent 名称模糊匹配 CR→Issue；
- 新 reconcile 框架、finding 系统或审计表；直接 SQL 修复 CR-2026-051/052；
- 修改现有 TTY/Web 审批授权模型；
- `dir-graph.yaml` 状态机、`skills/shared/crctl/gates.json`、`crctl approve` 协议、`crctl review-record` 落盘与事务模型。

---

# 附录 A：已核实事实（2026-08-27）

以下事实断言在落笔前用命令核实，实施期若发现不符须以 revision 修订并注明"结论是否受影响"：

1. **matrix 现状**：`tools/agent-skill-matrix.yml` 中 `requirement-writer.owns` 含 `review-requirement`/`approve-requirement`；`dev-agent.owns` 含 `review-tech-design`/`review-dev-plan`/`review-code`（缺口 A 的直接证据）；`quality-reviewer-agent.owns` 仅 `review-alignment`，四个 review Skill 在其 `can-call`。
2. **Agent 路由现状**：`agents/requirement-writer.md` 意图表"需求评审 → `review-requirement`"；`agents/dev-agent.md` 意图表"技术方案评审 → `review-tech-design`"、"代码评审 → `review-code`"；`agents/quality-reviewer-agent.md` 已路由全部四类评审（与设计稿 §3.1 断言一致）。
3. **Pipeline 现状**：`pipeline-templates/requirement-authoring.pipeline.json`（7 节点）、`architecture-design.pipeline.json`、`code-implementation.pipeline.json` 均存在 review 节点与 `reviewLoop`；review 节点 prompt 未要求新建独立 reviewer 任务。
4. **契约校验脚本**：`tools/skills/shared/crctl/scripts/` 下 `emit-registry.mjs`、`check-skill-matrix.mjs`、`check-agents-contract.mjs`、`lint-prompts.mjs` 均存在。
5. **Multica task 归因**：`server/internal/service/task.go:4221` 起 `AttributeTaskToCR` 调用 `SetTaskCRAttributionIfValid`（CR-2026-011）；`server/internal/handler/daemon.go:3659` 起为 StartTask 归因路径（best-effort 分支自报）。
6. **投影列与查询**：`server/migrations/433_aifirst_cr_projection.up.sql` 定义 `cr.shell_issue_id`（nullable）；`server/internal/governance/project_gates.go:142` 起 gates 查询以 `cr.shell_issue_id → issue.project_id` 限定项目 CR，返回 `pending_stage`/`can_approve`/`evidence`/`pending_advance`/`gate_nodes`。
7. **前端现状**：`packages/views/projects/components/project-team-agent-chat.tsx:247` 起只遍历 `cr.gate_nodes` 渲染 `CrGateCard`（缺口 B 第二断点）；`cr-gate-card.tsx` 内含 `ApprovalCard` 实现（可提取复用）。
8. **队列字段**：`server/pkg/db/queries/agent.sql` 的 `agent_task_queue` 写路径含 `issue_id`、`project_id`、`cr_id` 字段（CR-2026-010 起 stamp `project_id`）。
9. **台账**：`multica/CUSTOM.md` 存在，为双周 rebase 前核对 fork 定制的唯一清单。

# 附录 B：已知风险与升级条件（source §12）

| 风险 | 当前控制 | 升级条件 |
|---|---|---|
| 作者 Agent 技术上仍可直接调用 review Skill | 唯一 owner、Agent 路由、Pipeline prompt、结构测试 | 再次发生真实自评逃逸时，引入调用级执行身份拦截 |
| CR-ID 由 Skill 提交，可能在同 workspace 内错绑 | task token、数据库派生 Issue/Project、CAS、审计 | 出现错绑或安全等级提升时，由 enqueue/调度层权威写 task.cr_id |
| 不支持 subagent 的运行时不能单会话跑完 | 停在 review 节点，第二独立会话完成评审 | 多运行时频繁受阻时，再设计统一调度 Adapter |
| 成功事务后刷新事件发送失败 | 记录错误，依赖现有重新查询恢复 | 发生持续不可见时，复用现有事件重试能力，不新建审批队列 |
| 旧 PASS 无独立运行证明 | 保留历史、对已知事故 CR 手工重评 | 不在本 CR 批量废止或伪造历史身份 |
