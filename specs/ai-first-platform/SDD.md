---
id: ai-first-platform-sdd
spec-id: ai-first-platform
type: SDD
cr-ref: CR-2026-019
cr-history: [CR-2026-001, CR-2026-002, CR-2026-003, CR-2026-004, CR-2026-005, CR-2026-006, CR-2026-008, CR-2026-009, CR-2026-007, CR-2026-010, CR-2026-011, CR-2026-012, CR-2026-018, CR-2026-019]
title: AI First 研发协同平台 — 技术设计基线
target-version: "0.20.1"
status: ga
created: "2026-07-30T21:49:02+08:00"
updated: "2026-08-04T20:07:48+08:00"
version: v0.10.0
refs:
  upstream: [ai-first-platform-prd]
  downstream: []
components: [selfhost-compose, tools-consistency-ci, agent-frontmatter-adapter, issue-dispatch-smoke, crctl-outbox, daemon-crevents-collector, governance-crsync, governance-reconcile, governance-approval, pkg-gitguard, execenv-crguard, governance-audit]
---

# AI First 研发协同平台 — 技术设计基线

> **累积基线文档**，与 [PRD.md](PRD.md) 的里程碑分节一一对应。节内内容为该 CR 的 SDD 原文（H 级下沉一级）。
> 组件命名按里程碑归属（M0 四个 + P1 八个，见 frontmatter `components`）。
> 历次基线原文备份在 `change-requests/{CR-ID}/writeback-backups/ai-first-platform/{timestamp}/`。

## 组件总览

| 组件 | 里程碑 | 落点 | 职责 |
|---|---|---|---|
| selfhost-compose | M0 | multica fork | 内网全栈编排、云端能力剥离 |
| agent-frontmatter-adapter | M0 | tools + multica | 9 Agent 注册与 Skill 发现 |
| issue-dispatch-smoke | M0 | 验收动作 | 派单本机执行闭环 |
| tools-consistency-ci | M0 | tools CI | agents.contract 四条不变式 |
| crctl-outbox | P1 | tools crctl.mjs | 事件通道（零依赖、离线优先、原子写） |
| daemon-crevents-collector | P1 | multica internal/daemon | 双通道采集、ack 删除、三振隔离、离线积压 |
| governance-crsync | P1 | multica internal/governance | 投影 worker（幂等账本、合法转移、WS 广播） |
| governance-reconcile | P1 | multica internal/governance | 对账双模式（server GitHub API / daemon snapshot），单实现 ApplySnapshot |
| governance-approval | P1 | multica internal/governance | Ed25519 签名审批、grant 队列、人类身份与漂移门禁 |
| pkg-gitguard | P1 | multica server/pkg | rules.json 的 Go 消费方（三元白名单 + 拒绝留证） |
| execenv-crguard | P1 | multica internal/daemon/execenv | PATH shim 铸造、daemon 自守、IDE hooks 物化、上下文注入 |
| governance-audit | P1 | multica internal/governance | audit 事件直插 activity_log、工具调用摘要聚合 |

---

## M0 — 地基技术设计（v0.10 · CR-2026-001）

> 对应 `change-requests/CR-2026-001/prd.md` 的 FR-1~FR-4。范围严格锁定在 PRD 已经收窄过的 M0（地基），不含 P1 的 CR 治理投影（`cr`/`cr_sync_event`/`approval_record`/`pipeline_run`/`pipeline_node_run` 五张表、`issue.cr_id`/`agent_task_queue.cr_id` 两处 ALTER）——那批 schema 变更属于总 PRD P1-F1（CR 事件同步到 PG 投影），本 CR 不涉及，留给 P1 阶段注册的后续 CR。本文档不重写架构约束，因为本仓库还没有 `ARCHITECTURE.md`（M0 完成前平台没有实际代码，架构约束目前就活在 `docs/product/AI-First平台-PRD.md` §3 五方组装 与 `docs/product/P0-数据模型映射表.md` 里）。

### 1. 架构概览

#### 1.1 模块边界

M0 只新增/触碰四个边界清晰的模块，互不依赖对方内部实现：

| 组件 | 职责 | 依赖 |
|---|---|---|
| `selfhost-compose` | fork 后的 Multica 在内网起全栈；剥离 Stripe/`mcn_`/多 workspace 注册 | Multica 现有 Docker Compose/Helm 编排（原样复用，只改配置） |
| `agent-frontmatter-adapter` | 把 `tools/agents/*.md`（9 个）注册为 Multica `agent` 表行 | `selfhost-compose` 已起（需要能连上 Postgres/API）；Multica 既有 `multica agent create` CLI 或 `POST /api/agents` |
| `issue-dispatch-smoke` | 冒烟验证：派 Issue → daemon 领取 → 执行完成 | `agent-frontmatter-adapter` 已跑完（需要至少一个已注册 Agent） |
| `tools-consistency-ci` | `dir-graph.yaml#agents.contract` 4 条不变式的 CI 校验 | 无运行时依赖，纯静态校验 tools 包文件本身 |

#### 1.2 关键流程

```
fork Multica → selfhost-compose 起服务（FR-1）
                    │
                    ▼
        agent-frontmatter-adapter 读 tools/agents/_index.yml
        逐个 Agent 调 `multica agent create`（FR-2）
                    │
                    ▼
        issue-dispatch-smoke：建 Issue → 指派已注册 Agent
        → daemon 领取（agent_task_queue claim SQL）→ 执行完成（FR-3）

（与上面三步并行、无依赖）
tools-consistency-ci：CI 跑 check-skill-matrix.mjs 等价校验（FR-4）
```

FR-4 与 FR-1~FR-3 之间没有运行时依赖——这条链路已经在本仓库自己的 `tools/.githooks/pre-commit` + `tools/.github/workflows/check-skill-matrix.yml` 里实现并验证过（见评审报告 §5.2 落地记录），本 CR 只需要确认同一套校验在 Multica fork 仓库的 CI 里也接一份，不是从零设计。

### 2. 数据模型

**M0 不新增、不修改任何 Multica 表结构。** 依据 `docs/product/P0-数据模型映射表.md` §1"原样复用的 Multica 表"：`agent`/`agent_skill`/`agent_invocation_target`（FR-2 用）、`issue`/`agent_task_queue`/`task_message`（FR-3 用）全部已经原生存在，DDL 不变。

`agent-frontmatter-adapter` 写入的是**行数据**，不是表结构：

| 目标列（`server/pkg/db/generated/models.go` `Agent` struct） | 来源 | 说明 |
|---|---|---|
| `name` | `agents/{id}.md` frontmatter `name` | 直接映射 |
| `description` | frontmatter `description` | 目录性质字段，≤255 字符（tools 现有 9 个 Agent 描述均在此限内，无需截断逻辑） |
| `instructions` | frontmatter 之后的 Markdown 正文全文 | daemon 领取任务时读取的真实行为契约 |
| `permission_mode` | 不从 `permission.bash: deny` 直接映射 | 语义不同：Multica 的 `permission_mode`（`private`/`public_to`）管"谁能调用这个 Agent"，tools 的 `permission.bash: deny` 管"这个 Agent 能不能执行裸 shell"——后者是 P1 controlled-shell 下沉 daemon 才具备的执行期强制（P1-F5），M0 阶段只能把 `permission.bash: deny` 原样记录在某个可读字段（例如 `custom_env` 或新增一个不影响既有语义的备注列，具体落点留到开发计划阶段核对源码后再定），**不能假装 M0 就已经真正拦截了裸 shell**——这是本 SDD 需要显式承认的能力缺口，不是遗漏 |
| `mode: primary\|subagent` | 无对应列 | Multica 没有持久化的"primary/subagent"概念（`agent_task_queue.is_leader_task` 是运行时角色标记，不是 Agent 表字段）；M0 的适配器读到这个字段但暂不落库，需在适配器代码里显式记一条"字段已读取、未落库"的日志，不能静默丢弃调用方传入的信息（呼应 `multica/CONTRIBUTING.AIFIRST.md` 规则六"API 参数不得静默忽略"）。**可验收口径（评审建议落地）**：适配器每处理一个 Agent，运行输出必须包含一行结构化记录，形如 `{agent: "dev-agent", fieldsReadNotPersisted: {mode: "primary", "permission.bash": "deny"}}`；`write-dev-tasks` 拆任务时该任务的验收条件必须引用这条口径（9 个 Agent → 9 行记录，缺一行即未通过），使"不静默丢弃"从设计意图变成可核查的验收项 |
| `model` / `runtime_mode` / `runtime_id` / `thinking_level` / `custom_args` / `mcp_config` / `max_concurrent_tasks` / `composio_toolkit_allowlist` / `avatar_url` | 不填 | 沿用 Multica 建表默认值；tools 的 Agent 定义本身不携带这些运行时细节（模型由用户本机 Claude Code CLI 决定），M0 不做定制 |

### 3. 接口契约

M0 不新增 HTTP/WS 接口。`agent-frontmatter-adapter` 复用 Multica 已有入口：

- **首选**：`multica agent create`（已存在的 CLI，具体参数需在开发计划阶段核对 `server/internal/service/builtin_skills/multica-creating-agents/SKILL.md` 与 `references/creating-agents-source-map.md`——这两份文档是 Multica 仓库里已有的、对 Agent 创建契约做过源码级追溯的参考，比重新读 Go 源码更快）。
- **备选**：直接调 `POST /api/agents`（同一创建路径的 API 形态），仅当 CLI 不支持批量/非交互调用时才切换。

两者选一，不重复实现；具体选型在写开发计划（`write-dev-plan`）时按 CLI 是否支持脚本化调用来定。

**对拆任务阶段的硬性约定（评审建议落地）**：`write-dev-tasks` 产出的任务清单里，必须有一条独立任务是"阅读 `server/internal/service/builtin_skills/multica-creating-agents/SKILL.md` 与 `references/creating-agents-source-map.md`，确认 `multica agent create` 的完整参数面与校验规则，并把结论记入该任务的完成说明"——它是 `agent-frontmatter-adapter` 实现任务的**前置依赖**（先查证、后编码），不能默认开发时顺手就查到。若拆出的任务清单缺这一条，视为未对齐本 SDD。

### 4. 关键算法与流程

`agent-frontmatter-adapter` 伪代码：

```
读取 tools/agents/_index.yml，取 status=active 的 9 条记录
for each agent_id in active_list:
    读取 tools/agents/{agent_id}.md
    解析 frontmatter（复用 Multica 已有的 YAML frontmatter 解析逻辑，
        参考 server/internal/skill/frontmatter.go 的 ParseSkillFrontmatter 写法，
        只是这次要多取 mode/permission 两个字段，不能照抄"只取 name/description"的版本）
    body = frontmatter 分隔线之后的全文
    若 Multica 中已存在同名 Agent（按 name 查重）：
        跳过并记录一行"已存在，未重复创建"（幂等，避免重复跑 adapter 时报错或建重复行）
    否则：
        调用 multica agent create（或 POST /api/agents），
        name=frontmatter.name, description=frontmatter.description, instructions=body
        记录 mode/permission 字段已读取但未落库（见 §2 说明）
输出：本次新建了几个、跳过了几个（已存在）、失败了几个（附错误）
```

`issue-dispatch-smoke` 就是一次手工/半自动的验收动作，不是需要设计的新算法：建一条 Issue → 指派给上一步注册好的某个 Agent → 观察 `agent_task_queue` 是否出现 claim → 观察 Issue 状态是否变为 `done` 且执行摘要包含约定的结果标记（对应 PRD FR-3/AC-3 的判定信号）。

### 5. 技术选型与替代方案

| 决策点 | 选型 | 备选（未选） | 理由 |
|---|---|---|---|
| Agent 注册方式 | 复用 `multica agent create` CLI（或其 API） | 新写一段 Go 代码直接操作 `agent` 表 | Multica 已有创建路径且经过校验（字段约束、权限检查），绕开它自己写 INSERT 会重复造轮子且可能跳过既有校验；违反 `multica/CONTRIBUTING.AIFIRST.md` 规则四"优先复用上游已有抽象" |
| frontmatter 解析 | 参考 `server/internal/skill/frontmatter.go` 的实现方式扩展字段 | 引入新的 YAML/Markdown 解析库 | 项目已有同类解析代码，字段集小幅扩展（加 mode/permission）不构成新增依赖的理由 |
| `permission.bash: deny` 的处理 | M0 只记录不强制执行 | M0 就实现 execenv 层拦截 | execenv/controlled-shell 下沉是 P1-F5 明确排定的独立工作量（总 PRD §5.2.5），M0 提前做等于把 P1 的活拆进本 CR，违反 PRD §7 的范围排除约定 |
| tools 一致性 CI | 复用本仓库已验证过的 `check-skill-matrix.mjs` 思路，在 Multica fork 仓库接一份等价 CI | 重新设计一套校验规则 | 校验的 4 条不变式与本仓库 `dir-graph.yaml#agents.contract` 是同一件事，没有理由设计两套 |

### 6. FR 到技术实现映射

| FR | 技术方案 | 组件 |
|---|---|---|
| FR-1 | Docker Compose/Helm 配置改动：移除 Stripe 路由挂载、`mcn_` 凭据留空（中间件分支保留，天然 401，零代码改动）、`DISABLE_WORKSPACE_CREATION=true` | `selfhost-compose` |
| FR-2 | `agent-frontmatter-adapter` 脚本，见 §4 伪代码 | `agent-frontmatter-adapter` |
| FR-3 | 无新代码，用 FR-2 注册好的 Agent 做一次端到端冒烟 | `issue-dispatch-smoke` |
| FR-4 | Multica fork 仓库接入等价于 `tools/.github/workflows/check-skill-matrix.yml` 的 CI 步骤 | `tools-consistency-ci` |

### 7. 安全与性能考量

- **安全边界（诚实声明）**：M0 完成后，已注册的 9 个 Agent 尚未受 controlled-shell/execenv 白名单约束（那是 P1-F5）。这意味着 M0 阶段 Agent 理论上仍可执行任意 shell 命令——这不是本 CR 的疏漏，而是 PRD §7 明确排除的范围；**M0 验收通过不代表 Agent 执行是安全的，只代表"能跑通"**，这条边界必须在 M0 验收结论里同样写清楚，不能只写"通过"两个字。
- **幂等性**：`agent-frontmatter-adapter` 重复运行不应重复建行（§4 已设计按 name 查重跳过）；`issue-dispatch-smoke` 是一次性验收动作，不需要幂等设计。
- **性能**：9 个 Agent、一次 Issue 派发，量级微小，无需考虑并发/批量优化。

### 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-07-30 | v0.1.0 | Ray | 初始草稿；Agent 注册模型细节经 Explore 核对 Multica 源码（`server/pkg/db/generated/models.go` 的 `Agent` struct、`server/internal/skill/frontmatter.go`），未凭空假设字段 |
| 2026-07-30 | v0.1.1 | Ray | 采纳技术评审两条非阻塞建议：① §3 增加对拆任务阶段的硬性约定——"核对 multica agent create 参数"必须是独立任务且为适配器实现的前置依赖；② §2 mode/permission "读取不落库"补可验收口径（每 Agent 一行结构化日志，9 缺一即不过），拆任务时验收条件必须引用 |
---

## P1 — 治理核心技术设计（v0.11 · CR-2026-002）

> 输入：[prd.md](prd.md)（0.1.1）＋源方案 [P1-crctl接入设计.md](../../docs/product/P1-crctl接入设计.md)。
> 代码锚点沿用 M0 核实结果：multica fork（main@0980f3bfc 起）、tools（custom/main@5a52cd4 起）。
> fork 隔离约束：自研 Go 代码入新目录（CONTRIBUTING.AIFIRST.md 规则一），上游文件只留 `// AIFIRST:` 标记的最小挂钩。

### 1. 架构概览

#### 1.1 组件与归属

| # | 组件 | 落点（仓/路径） | 新增/修改 | 职责 |
|---|------|----------------|-----------|------|
| C1 | crctl outbox 挂点 | tools `skills/shared/crctl/scripts/crctl.mjs` | 修改（casWrite 收尾 + cmdApprove + cmdGit push 后，约 60 行） | advance/approve/push 成功后原子写 `.crctl/outbox/*.json` |
| C2 | crctl grant 验签 | tools 同上 | 修改（cmdApprove 增 `--grant` 分支；gate/validate 统一摘要比对） | 非 TTY 审批放行；EVIDENCE_DRIFT 两轨检测 |
| C3 | rules.json 单一事实源 | tools `skills/shared/controlled-shell/rules.json` | 新增；crctl.mjs 删硬编码表改加载；hooks 改读 | 19 条三元组 + forbiddenFlags + protectedPaths |
| C4 | daemon CR 事件收集器 | multica `server/internal/daemon/crevents.go` | 新增文件（主循环挂钩一处，AIFIRST 标记） | outbox 扫描 + commit 兜底扫描 + 批量上报 + 确认删除 |
| C5 | 服务端投影 worker | multica `server/internal/governance/crsync.go` | 新增（新包，规则一） | 事件入库/幂等/有序消费/投影更新/WS 广播 |
| C6 | 签名审批服务 | multica `server/internal/governance/approval.go` | 新增（新包） | RequireHumanActor + 证据比对 + Ed25519 签发 grant + approval_record |
| C7 | reconcile 对账 | multica `server/internal/governance/reconcile.go` | 新增（新包，复用 sys_cron_executions 调度） | projected_commit vs origin HEAD；needs_reconcile 自愈 |
| C8 | gitguard | multica `server/pkg/gitguard/` | 新增包（~300 行） | rules.json 的 Go 消费方：Check/Run |
| C9 | execenv 铸造改造 | multica `server/internal/daemon/execenv/{execenv,git,runtime_config_sections}.go` + `crguard_config.go`（新） | 3 处修改（AIFIRST 标记）+ 1 新文件 | PATH shim / daemon 自守白名单 / 上下文注入 / hooks 物化 |
| C10 | 路由挂载 | multica `server/cmd/server/router.go` | 修改 2 行级（AIFIRST 标记，同 M0 模式） | `/api/daemon/cr-events`、审批 API 挂载 |

#### 1.2 关键流程（事件主链路）

```
crctl advance/approve/push（用户机）
  └─ C1 原子写 .crctl/outbox/{ts}-{cr}-{kind}-{sha}.json
daemon 主循环（heartbeat 同周期）
  ├─ C4 outbox 扫描（全部已知 worktree + 主 workspace）
  ├─ C4 commit 兜底扫描（knowledge-base，.crctl/.scan-cursor 游标增量）
  ├─ 合并去重 (cr_id, commit_sha, event_kind)
  └─ POST /api/daemon/cr-events（≤100/批，mdt_）→ accepted 才删文件
server
  ├─ C5 入库 cr_sync_event（幂等键冲突=已处理）
  ├─ C5 per-CR 串行：合法转移→更新 cr 行+壳 Issue 7 态；非法→needs_reconcile
  ├─ C5 events.Bus → WS workspace:{id} / issue:{id}
  └─ C7 定时对账：projected_commit ≠ origin HEAD → 重放修复
```

审批链路（grant）：Web 点击批准 → C6 校验（人类身份/证据摘要/角色）→ 签名生成 grant → daemon 落盘 `.crctl/grants/` → `crctl approve --grant` 验签+重算摘要 → 写 approval.yml → 级联 advance → 回到事件主链路。

### 2. 数据模型

#### 2.1 新表（PG，multica migrations 追加；P0 映射表已定权威域：**git 权威，PG 只是投影**）

```sql
-- cr 投影表（P0 已定义，本 CR 落地）
CREATE TABLE cr (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id  UUID NOT NULL REFERENCES workspace(id),
  cr_id         TEXT NOT NULL,                 -- "CR-2026-002"
  title         TEXT NOT NULL DEFAULT '',
  status        TEXT NOT NULL,                 -- 15 具名态之一（(new) 不入投影；状态机只读副本校验）
  owners        JSONB NOT NULL DEFAULT '{}',
  target_version TEXT NOT NULL DEFAULT '',
  projected_commit TEXT NOT NULL DEFAULT '',   -- 投影所至的 knowledge-base SHA
  needs_reconcile  BOOLEAN NOT NULL DEFAULT FALSE,
  shell_issue_id   UUID REFERENCES issue(id),  -- 壳 Issue（7 态映射目标）
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, cr_id)
);

CREATE TABLE cr_sync_event (
  id           BIGSERIAL PRIMARY KEY,
  cr_id        TEXT NOT NULL,
  commit_sha   TEXT NOT NULL DEFAULT '',       -- embedded 补全前可空串
  event_kind   TEXT NOT NULL,                  -- status|owners|checkpoint|merge|archive|inbox
  payload      JSONB NOT NULL,
  actor        TEXT NOT NULL DEFAULT '',
  occurred_at  TIMESTAMPTZ NOT NULL,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  UNIQUE (cr_id, commit_sha, event_kind)
);

CREATE TABLE approval_record (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cr_id           TEXT NOT NULL,
  stage           TEXT NOT NULL,               -- gates.json#approvalStages 四键
  decision        TEXT NOT NULL,               -- approve|reject
  approver_user_id UUID NOT NULL REFERENCES "user"(id),
  evidence_digest TEXT NOT NULL,
  key_id          TEXT NOT NULL,
  signature       TEXT NOT NULL,               -- base64
  reject_reason   TEXT NOT NULL DEFAULT '',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- approve 幂等、reject 允许多条留痕：同一版证据先 reject 后 approve 不得撞键（SDD-SUG-001）
CREATE UNIQUE INDEX approval_record_approve_uniq
  ON approval_record (cr_id, stage, evidence_digest) WHERE decision = 'approve';
```

`cr.workspace_id` 的解析（SDD-SUG-002）：事件体**不携带、不信任** workspace 标识；C5 从 DaemonAuth 上下文取该 daemon 配对时绑定的 workspace（`workspace_root_hash` 仅用于 daemon 侧多 workspace 区分与日志关联，不作为服务端信任输入）。

`activity_log`：不建新表，新增 action 枚举值 `aifirst.gitguard_denied`、`aifirst.evidence_drift`（Go 侧常量 + 校验放开；表结构不动）。工具调用摘要随任务完成回调入既有 `task` 详情 JSONB（与 `skills_used[]` 同层），不新建表。

#### 2.2 文件侧 schema（git / 本地，权威侧）

| 文件 | 归属 | 说明 |
|---|---|---|
| `.crctl/outbox/{utc-ts}-{cr}-{kind}-{shortsha}.json` | workspace 本地，不入 git | 事件 schema v1（PRD FR-1 字段表）；写临时名再 rename |
| `.crctl/outbox/dead/` | 同上 | rejected×3 的坏事件停靠 |
| `.crctl/.scan-cursor` | knowledge-base worktree 本地 | 上次 commit 扫描 SHA |
| `.crctl/grants/{cr}-{stage}.grant.json` | workspace 本地，不入 git | grant schema v1（源方案 §B.2） |
| `.crctl/keys/{key_id}.pub` | **提交进 knowledge-base 仓** | Ed25519 公钥，换钥有审计痕迹 |
| `skills/shared/controlled-shell/rules.json` | tools 仓 | 白名单单一事实源 v1 |
| `approval.yml` 各段 | knowledge-base 仓 | 新统一字段 `evidence-digest`（替代 `evidence-sha256-16`） |

### 3. 接口契约

#### 3.1 daemon → server（挂既有 DaemonAuth 组，mdt_ 令牌）

```
POST /api/daemon/cr-events
Req : { workspace_root_hash: string, events: OutboxEvent[] }   // ≤100
Resp: 200 { accepted: string[], rejected: [{file, code}] }     // code: BAD_EVENT|UNKNOWN_KIND|SCHEMA
GET  /api/daemon/approvals/pending?workspace_root_hash=…
Resp: 200 { grants: [{ cr_id, stage, grant: GrantFile }] }
POST /api/daemon/approvals/ack        // grant 已落盘确认，服务端标记 delivered
```

#### 3.2 人类审批（挂既有用户会话鉴权；**RequireHumanActor：mat_ 任务令牌一律 403**）

```
GET  /api/workspaces/{wid}/crs                     // 看板列表（cr 投影表）
GET  /api/workspaces/{wid}/crs/{cr_id}/approval    // 审批卡片：证据摘要+digest 指纹
POST /api/workspaces/{wid}/crs/{cr_id}/approve
Req : { stage, decision: "approve"|"reject", reject_reason? }
Resp: 200 { grant: GrantFile }                      // 409=证据漂移, 403=验签/身份
```

#### 3.3 crctl CLI（tools）

```
crctl approve <cr> --stage <s> --grant <path>   # 非 TTY 放行：验签+重算 digest
crctl approve <cr> --stage <s>                  # TTY 路径不变，但改写 evidence-digest 统一字段
```

#### 3.4 WS 事件（复用 events.Bus → Hub）

`{ scope: "workspace:{id}"|"issue:{id}", type: "cr.updated", cr_id, status, needs_reconcile }`

### 4. 关键算法与流程

#### 4.1 canonical evidence digest（唯一实现，AC-7⑤）

```
digest = sha256( concat( for f in sort(approvalStages[stage].evidence):
                           sha256(normalizeEol(read(f))) ) )      // hex 拼接后再 sha256
```
- `normalizeEol` 复用 M0 的 `evidenceSha16` 行尾规范化经验（\r\n→\n），避免 autocrlf 误报。
- crctl 内**仅此一个函数**；TTY 写入、--grant 验证、gate/validate 重算三处调用同一函数。Go 侧 C6 持等价实现，跨语言一致性用共享测试向量固定（tools 测试与 Go 测试引用同一组 fixture：同输入文件集 → 同 digest hex）。

#### 4.2 grant 验签（crctl，Node ≥18 原生）

```
canonical = `v1|${cr_id}|${stage}|${decision}|${approver}|${approved_at}|${evidence_digest}`
crypto.verify('ed25519', Buffer.from(canonical), pubKey(.crctl/keys/{key_id}.pub), signature)
&& recompute_digest() === grant.evidence_digest        // 否则 EVIDENCE_DRIFT
&& grant.cr_id === 当前 CR && grant.stage === 当前 stage // 防挪用（签名已绑定，此为友好报错）
```

#### 4.3 commit 兜底扫描正则（稳定契约，NFR-3）

```
^\[cr\] status (CR-\S+) (\S+) -> (\S+)$      → status
^\[cr\] merge metadata (CR-\S+)              → merge（payload 读该 commit 的 _backlog.yml diff）
^\[cr\] archive (CR-\S+)                     → archive
^\[cr\] inbox-emit (CR-\S+) event=(\S+)      → inbox
```

#### 4.4 投影消费（C5）

```
tx: INSERT cr_sync_event ON CONFLICT DO NOTHING → 冲突则 return（已处理）
per-CR 互斥（sync.Map[cr_id]*sync.Mutex；多节点后备：PG advisory lock hashtext(cr_id)）
if isLegalTransition(cur.status, ev.to_status)：更新 cr 行 + projected_commit + 壳 Issue 7 态映射
else：cr.needs_reconcile = true（不强行应用）
commit_sha == "" 的事件：延迟 60s 处理，等 push 补全事件合并（源方案 §A.5）
```
状态机转移表只读副本（23 条声明，wildcard `any-active` 展开后 45 条）：从 tools `dir-graph.yaml` 生成 Go 常量文件 `transitions_gen.go` 并**提交入库**（文件头注释记录来源 tools commit SHA）；CI 只校验"重新生成 == 已入库"（漂移即红），multica 构建本身不跨仓依赖 tools checkout（SDD-SUG-003）。

#### 4.5 execenv 铸造（C9）

```
每任务 workdir 铸造:
  写 {workdir}/.bin/git → "exec {daemonSelfPath} gitguard-exec git \"$@\" --caller={agent_id}"
  child env: PATH = {workdir}/.bin + PATHSEP + 原 PATH；CRCTL_WORKSPACE=工作区根
  Claude 后端: 物化 per-task .claude/settings.json（PreToolUse: pretooluse-guard.mjs, inject-cr-status.mjs）
             permission.bash=deny → ExecOptions.ExtraArgs += ["--disallowedTools","Bash"]
  其他后端: 仅 shim + 上下文注入（诚实降级）
Windows 注意：.bin/git 需成对物化 git.cmd（cmd/PowerShell）与 git（bash shim），M0 已证本机开发环境为 Git Bash + PowerShell 混用。
```

### 5. 技术选型与替代方案

| 决策 | 选择 | 被否方案与理由 |
|---|---|---|
| crctl→server 通道 | 本地 outbox 文件 + daemon 上报 | crctl 直连 HTTP：破坏零依赖/离线原则；且 token 管理进 crctl 属职责越界 |
| 事件可靠性 | at-least-once + 幂等键去重 | exactly-once：分布式代价不值；去重键天然幂等 |
| 兜底通道 | commit message 正则扫描 | 仅 outbox：覆盖不了旧版 crctl/人工 git/编排器直 commit 三旁路 |
| 签名算法 | Ed25519（Node/Go 原生） | HMAC：对称密钥无法公开验证，公钥进 git 的审计模式不成立；RSA：无必要 |
| 审批下发 | grant 文件落盘 worktree | 长连接在线审批：断网即瘫；文件模式与 outbox 对称，离线补投 |
| 白名单事实源 | rules.json 数据文件三方共读 | 各自维护：M0 已实测漂移（15 vs 19 条）；代码生成：过重 |
| 投影更新范围 | server 持状态机只读副本做合法性校验 | 无校验直写：乱序/漏事件会产生错误投影且无法察觉 |
| 自研代码落点 | `internal/governance/` 新包（规则一） | 源方案原文 `internal/service/`：该包**存在且是上游活跃包**（TASK-04 实施期核实；本行初稿误写"无此包"，0.1.2 更正论据）——把自研代码放进上游活跃包会扩大双周 rebase 冲突面，违反 CONTRIBUTING.AIFIRST.md 规则一，故仍改落新包 `internal/governance/`。**结论不变，论据更正** |

### 6. FR → 技术实现映射

| FR | 组件 | 落点仓 | 交付物 |
|---|---|---|---|
| FR-1 | C1 | tools | crctl.mjs outbox 挂点 + 事件 schema + 单测（断网 advance→文件；embedded 空 SHA） |
| FR-2 | C4+C5+C10 | multica | crevents.go、governance/crsync.go、cr-events 端点、migrations（cr、cr_sync_event）、双通道去重测试 |
| FR-3 | C7 | multica | governance/reconcile.go、REMOTE_RECONCILE_MODE 配置、篡改自愈测试（server 模式对 GitHub origin 实测，PAT 前置见 AC-3） |
| FR-4 | C6+C2 | multica+tools | governance/approval.go、approval_record 迁移、grant 签发 API、crctl --grant、密钥 smoke test、三拒绝路径单测 |
| FR-5 | C3+C8+C9 | tools+multica | rules.json、gitguard 包、execenv 四处、crctl 硬编码表删除（8 测试回归） |
| FR-6 | C8+C4 | multica | gitguard 拒绝事件→任务回调→activity_log；工具摘要随完成回调持久化 |
| FR-7 | C2 | tools+multica | evidence-digest 统一字段、gate/validate 两轨比对、漂移事件上报 activity_log |

### 7. 安全与性能考量

- **私钥**（源方案 §B.5 全采纳）：文件 0400 或 `APPROVAL_SIGNING_KEY` env base64 二选一；启动公私钥互验 smoke test 失败即拒绝启动；签名单点收口在 governance/approval.go；日志只出 key_id。
- **防重放**：签名绑定 `cr_id+stage+evidence_digest`；approval_record 幂等键同三元组。
- **人类身份**：审批 API 中间件级拒绝 `mat_`；grant 内 approver 来自会话用户，不信 crctl `--caller` 自报。
- **审计最小化**：gitguard 拒绝事件不含参数正文；工具摘要不含输入输出正文；漂移事件不含证据内容。
- **性能**：事件采集搭 heartbeat 便车（无新轮询）；单批 ≤100；outbox 文件名含时序天然有序；WS 推送替代看板轮询。
- **诚实边界**（NFR-5 落文档）：PATH shim 可被绝对路径绕过——写入 rules.json 解说与 SKILL.md；第 4 层（CAS+gate）与第 5 层（CI cr-guard）为兜底事实。
- **升级兼容**：旧 approval.yml 的 `evidence-sha256-16` 读到即视为"无摘要"，不报错不阻塞（NFR-3）；`[cr] ` commit 格式冻结。

### 8. 测试设计（对应 AC）

| AC | 验证方式 |
|---|---|
| AC-1 | tools 单测：mock 断网（outbox 写成功即可，无网络调用）+ 文件 schema 断言 + embedded 空 SHA 补全用例 |
| AC-2 | Go 集成测试：同事件双通道注入 → 断言单行；乱序注入 → needs_reconcile；WS 收流断言 |
| AC-3 | 手工+脚本：UPDATE cr SET status='x' → 等对账周期 → 断言恢复；两模式各跑一次 |
| AC-4 | Go 单测三拒绝路径 + tools 三 grant 用例 + 端到端一次（无 TTY 环境实跑） |
| AC-5 | gitguard 表驱动测试（force push/-c/绝对路径声明）+ hook deny 手测 + crctl 8 测试回归 |
| AC-6 | 端到端：任务内故意触发 FORBIDDEN_* → 查 activity_log 行 + 字段断言（无参数正文） |
| AC-7 | tools 测试：TTY 审批→篡改→status/validate 检出；旧字段兼容用例；digest 单一函数由代码评审核查 |

### 9. 缺陷修补记录（CR-2026-003，P1 治理核心补丁）

生产运行后发现 P1 治理核心（CR-2026-002）遗留两个缺陷，均源于 `--embedded` 空 `commit_sha` 与归档后投影两条链路：

- **缺陷 A**（幂等键碰撞）：`cr_sync_event` 幂等键 `(cr_id, commit_sha, event_kind)` 在多次 embedded 事件 `commit_sha` 均为空串时相同，第二条被 `ON CONFLICT DO NOTHING` 静默丢弃，投影卡在中间状态。
  **修复**：crctl 侧改发 `pending:{ms}:{pid}:{seq}` 占位符（跨语言契约字面量，两侧测试锁定）保幂等键唯一；服务端 `projectableSha()` 在写 `cr.projected_commit` 前过滤该前缀，占位符只入幂等键、不进投影指针，避免污染。
- **缺陷 C**（归档 CR 无法自愈）：reconcile 快照只读 `_backlog.yml`，CR 一旦移入 `_history.yml`（归档）即脱离对账覆盖范围，此前的错误投影无法再被治愈。
  **修复**：`ParseHistory()` 解析 `_history.yml` 为 `id → final-status` 映射，`mergeAuthority()` 与 backlog 结果合并（backlog 防御性优先，覆盖崩溃窗口的两种残留形态）；server/daemon 两模式均在快照中携带 history，`ApplySnapshot()` 本体零改动。
- **缺陷 B**（commit-scan 兜底通道不解析 archive 提交的 from/to）：本次明确不修，FR-2 的 outbox 主通道 + 本次 history 自愈已覆盖该场景终态，兜底通道该支路失败不再影响收敛（详见 [CR-2026-003/sdd.md §5](../../change-requests/CR-2026-003/sdd.md)）。

验收：生产环境两条真实卡死投影行（CR-2026-001 卡 12h、CR-2026-002 卡 1h）在修复部署后第一个 server 对账周期内（2026-07-31 13:19:14 UTC）自然收敛为 `archived/false`，全程只 `SELECT`，无手工写入。详见 [CR-2026-003/test-report.md](../../change-requests/CR-2026-003/test-report.md)。

---

---

## P2 D1 — Team Agent 共享队列容量上限 技术设计（v0.12 · CR-2026-004）

> 完整 SDD 见 change-requests/CR-2026-004/sdd.md（含 INSERT 点全量裁决表、接口契约、伪代码）；本节为基线摘要。

### 1. 设计要点

- **纯业务逻辑层**：机制层零改动。守卫 `guardProjectQueueCapacity`（`server/internal/service/task_queue_capacity.go`）只挂在两个用户入队路径（CreateAgentTask / CreateQuickCreateTask）；deferred / retry / autopilot / chat 四条系统路径明确不过守卫（全仓 6 个 INSERT 点逐一裁决，表在 CR SDD §1）。
- **容量口径**：queued + dispatched（与既有 HasPendingTaskForIssue 的 pending 口径一致）；running 排除。新 sqlc 查询 `CountProjectPendingTasks`（JOIN issue 走 idx_issue_project）。
- **插队**：owner/admin（workspace member.role）返回 priority=100 并跳过容量检查；既有档位 0–4（priorityToInt），100 为治理插队档，隔离带明确。
- **配置**：迁移 159 给 project 加 `settings JSONB`（仿 workspace 惯例）；键 `team_agent_queue_limit`，解析失败/≤0 回退常量 50，不阻塞入队。写入口在 UpdateProject，owner/admin 门禁 + 键白名单 + 正整数校验。
- **撤回**：复用 `CancelTaskWithResult`（软删 + WS 广播 + agent 对账全既有），handler 层加权限边界：非 originator 且非 owner/admin → 403 `not_task_originator`。
- **读侧**：`GET /api/projects/{id}/queue-status` → `{queue_depth, queue_limit}`；前端 core 挂 `task:` 前缀 WS 失效（任意任务生命周期事件统一失效，仓内既有惯例）。
- **弱一致界定（NFR-2）**：count-then-insert 无锁，并发窗口可短暂超限 1~2 项，接受；守卫查询失败 fail-open（容量放行）+ fail-closed（不发插队优先级）。

### 2. 实现期与设计的偏差（TASK 完成记录留痕）

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| 评论路径 429 | 入队触达点 handler 统一映射 429 | 评论/指派路径 fire-and-forget（issue 落库、enqueue 拒绝仅日志），429 只在 quick-create 等"入队即请求本体"端点 | 人类发言不应被 Agent 队列满阻断；既有结构如此 |
| 撤回接口 | 新端点 + 409 task_not_queued | 复用既有 POST /api/tasks/{id}/cancel，成员停自己的任务不限 queued | 与 P2 停止语义（发送者停自己运行中/排队中）一致，避免双端点 |
| 前端 WS 触发 | 逐事件挑选（含补 task:running） | `task:` 前缀统一失效 | 仓内既有惯例，天然覆盖全部生命周期事件 |
| 队列条 UI | 聊天窗口队列条 + 排队列表 | project-detail 常驻指示 + quick-create 满队反馈 | 三 tab 聊天窗口尚无（D2/D3 未排期），本 CR 落最小可见验证 UI |

---

## 治理工具链补丁 — delivery/task 回写一致性 技术设计（v0.12.1 · CR-2026-005）

> 完整 SDD 见 change-requests/CR-2026-005/sdd.md；本节为基线摘要。

### 1. 设计要点

- 新 gate check type `deliveryIndexComplete`（`tools/skills/shared/crctl/scripts/crctl.mjs`）：交叉核对 CR 的 `tasks/_index.yml`（status=done）与全局 `delivery/task/_index.yaml`，集合差非空即拒绝 `--to archived`。两份索引 `id` 字段核实同名同值，简单集合差实现，不需映射表。
- `writeback-tasks` skill（`tools/skills/writeback/writeback-tasks/SKILL.md`）：发现该文件早已存在但从未被实际调用（格式与 CR-2026-001~004 实际做法不兼容），按实际数据重写为原子操作；幂等判据是"id 是否已在全局索引"而非文件内容比较。
- `write-dev-tasks` 模板新增可选 `slug` 字段，供回写时派生确定性文件名，未填回退 `task-{NN}`。

### 2. 实现期与设计的偏差

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| 全局索引顶层结构 | 假设裸列表 `- id: ...` | 实为 `{tasks:[...]}` 包裹键，与 `tasks/_index.yml` 同构 | 初版实现 `TypeError`，用真实历史数据（CR-2026-001~004）重放 AC-1 时发现，自造 fixture 因恰好符合错误假设未能测出；修正为 `?.tasks \|\| []` |
| 全局索引不存在时的边界语义 | 笼统"不误报" | 区分两种：doneIds 为空才真正放行；文件不存在但 doneIds 非空时当空集计算、正常报缺失（代码评审阶段发现原注释歧义并修正） | 避免"文件不存在=直接放行"的误读，那样会让门禁形同虚设 |

### 3. 范围排除

backlog→history 归档迁移的同类空白留待独立评估，可复用本 CR 的 gate check 模式。

---

## P2 CR-A — 三模式聊天窗口骨架 + Team Agent 消息流核心 技术设计（v0.13 · CR-2026-006）

> 完整 SDD 见 change-requests/CR-2026-006/sdd.md（含 6 条设计决策 DD-1~DD-6、FR→设计映射表、
> 技术评审 3 条建议 TSUG-001~003 的落地方案）；本节为基线摘要。

### 1. 设计要点

- **容器 Issue 方案（DD-1/DD-3）**：Team Agent 群聊消息不新建消息表，而是复用一个隐藏容器 Issue
  （`origin_type='project_chat'`，migration 160 扩 CHECK 约束 + 部分唯一索引防并发重复创建）——每条
  用户消息即该 Issue 的一条 comment，Agent 回复/工具执行走既有 task-run + timeline 基础设施。全部
  Issue 查询入口（`ListIssues`/`ListGroupedIssues`/`buildSearchQuery`/sqlc 三查询 + 两处统计，共 7 处）
  加排除谓词 `origin_type IS DISTINCT FROM 'project_chat'`；`buildSearchQuery` 含 comment 内容子查询，
  不排除会让聊天内容泄漏进全局搜索——这是本 CR 最大的正确性风险点，已代码落地并真机 SELECT 验证。
- **薄发送端点（DD-3，TSUG-001/002）**：`POST /api/projects/{id}/chat/messages` 顺序执行容量守卫
  （复用 CR-2026-004 `guardProjectQueueCapacity`）→ 落 comment → `EnqueueTaskForMention` 入队；
  入队失败（含并发竞态下内部 guard 二次触发的 `ErrProjectQueueFull`）走 `errors.As` 单独判断映射 429
  （而非笼统 502）+ 物理删除补偿已落库的 comment（comment 无软删除机制）。容器 Issue 固定
  `priority='medium'`（tier 2），使群聊任务与既有 1:1 chat 任务同优先级，避免被后者持续插队。
- **模型选择器（DD-4，TSUG-003）**：绑定 Team Agent 这个 agent 的模型配置（非按消息覆盖——daemon
  claim 时固定读 `agent.Model`，不消费任务级覆盖）。两种禁用态严格区分：无编辑权限（沿
  `useAgentPermissions.canEdit`，与项目 owner/admin 身份独立）→ 只读徽标；无可用 Runtime → 引导文案 +
  发送禁用。判定顺序：先权限、后 Runtime。
- **前端骨架（DD-2 未启用/DD-6）**：project-detail 主区加 Issues\|Chat Tabs；三模式 tab 条 + 独立
  `project-chat-store`（zustand，未复用既有 1:1 chat 的全局单例 store，避免会话互抢）；timeline 无
  分页（硬帽 2000），本期全量回放，ponytail 标注消息量逼近上限时另立分页优化。

### 2. 实现期与设计的偏差 / 代码评审发现（TASK 完成记录留痕）

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| 未配置态 CTA | 内联 agent 选择器，选定即写 `settings.team_agent_id` | 前 4 个开发任务遗留为 disabled 按钮 + TODO，代码评审（Spec 轴）发现后补齐（复用 PropertyPicker/agentListOptions，新增非乐观 `useSetProjectTeamAgent` mutation） | 任务拆分时归入 TASK-05 但实现时被漏项；代码评审兜底发现并当轮修复 |
| 消息发送反馈 | pending-message 模式（可见 pending 态 + 失败重试） | 初版实现只有按钮 spinner，代码评审（Standards 轴）指出后补充可见 pending 气泡 | 遵循 CLAUDE.md "非静默乐观" 规则 |
| 真机 E2E 覆盖 | AC-2/3/7 全链路真机跑通（含 agent 实际执行） | 本机未安装 Claude Code/Codex CLI，agent 真实执行段（toolExecutionCard 流式渲染、daemon 模型上报）改为应用层单测覆盖 + API 级真机验证（容器创建/守卫/入队/补偿链路），daemon 全链路留部署前独立验收 | 环境限制；用户确认后接受该覆盖范围 |

### 3. 范围排除

队列条完整形态/停止/过滤开关（CR-B）、Private Ask/Discussion 内容面（CR-C/D）、presenter（CR-E）、
门禁接合（CR-F）、DC+合并转发（CR-G）——均不在本 CR 范围，见切分文档 v2。

## P2 CR-B — D3 完整形态 技术设计（v0.14 · CR-2026-007）

> 完整 SDD 见 change-requests/CR-2026-007/sdd.md（含 6 条设计决策 DD-1~DD-6、9 条调查结论、
> 技术评审 attempt 0→1 的 3 处 blocker 修复记录）；本节为基线摘要。
> 回写顺序说明同 PRD.md 对应节：本 CR 按版本号插入于 CR-A（0.13）与 CR-C（0.15）之间，
> 实际回写晚于两者。

### 1. 设计要点

- **停止入口与判定（DD-1）**：发送键恒为发送，「停止」按钮放运行中任务卡与队列展开列表项；
  `AgentTaskResponse` 新增只读 `originator_user_id`（omitempty，向后兼容），供前端判定"是我
  发起的"。
- **撤回=停止=同一端点（DD-2）**：全部走既有 `POST /api/tasks/{taskId}/cancel`；服务端对已
  完成任务是幂等 200+原状态（非 400/409），前端三分支处理；`CancelTaskByUser` 唯一写路径
  改动——`originator==caller` 先行放行，修复私有 agent 下"发得进撤不回"的权限不对称，非发
  起人路径校验原样保留。
- **队列明细读侧扩展（DD-3）**：`GET /api/projects/{id}/queue-status?include=items` opt-in
  扩展（不带参逐字节零变化）；新查询 `ListProjectPendingTasks`（agent.sql）LEFT JOIN users
  保留 NULL originator 任务、口径与 `queue_depth` 完全一致；summary 直读既有
  `trigger_summary` 列（已截断落库，跨 workspace 防泄漏），不二次 JOIN comment；query key
  挂 `queueStatus` 前缀下白拿既有 WS 失效覆盖。
- **过滤开关谓词（DD-4）**：开启时 comment 全保留，`TaskExecutionCard` 只渲染卡头+
  `result.output` 最终文本（不渲染 TimelineView）；`project-chat-store` 增
  `agentRequestFilter` map，走既有 `createWorkspaceAwareStorage` 持久化。
- **已撤回标注/摘要复用既有关联（DD-5）**、**被停者对账链路全既有（DD-6）**：零新增写路径，
  复用 WS 队列失效与既有 interrupted 徽标渲染分支。

### 2. 技术评审记录（attempt 0 → 修复映射，摘要）

3 处 blocker 修复：① I-2 幂等 200 假断言（非 400）→ DD-2 竞态语义改按响应状态判定；
② 私有 agent 撤回权限不对称 → `CancelTaskByUser` 服务端小改 + 单测双向覆盖；
③ INNER JOIN 丢 NULL originator → 改 LEFT JOIN + 前端占位 + 口径单测。

### 3. 实现期与设计的偏差 / 代码评审发现（TASK 完成记录留痕）

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| initials 计算 | 未预先设计共享位置 | 代码评审（Standards 轴）发现 `project-queue-bar.tsx` 与 `workspace/hooks.ts` 的 `getActorInitials` 同形重复，抽取 `packages/core/utils.ts` 的 `nameToInitials(name)`，两处改调用共享函数 | Duplicated Code |
| `CancelTaskByUser` 内层条件 | DD-2 决策为"originator==caller 先行放行" | T02 调序后 originator 快速路径内遗留一个条件恒真的冗余 `if`（外层已保证成立），代码评审（Standards 轴）发现后拍平，注释同步说明结论来自外层 else-if | Dead/Redundant Conditional |
| `project-team-agent-chat.tsx` prop 传递 | — | wsId/projectId/canConfigure/filterOn 经 `TeamAgentStreamView` 一跳转发，代码评审识别为轻度 prop-drilling，权衡后判断性保留（一跳转发，引入 context/对象封装属于非必要抽象） | 保留，非缺陷 |

### 4. 范围排除

队列上限配置管理界面（D1 已交付写入口，本 CR 不做界面）；消息回复/转发/reaction → CR-G；
presenter → CR-E；门禁接合 → CR-F。

## P2 CR-C — D5 Private Ask 技术设计（v0.15 · CR-2026-008）

> 完整 SDD 见 change-requests/CR-2026-008/sdd.md（含 7 条设计决策 DD-1~DD-7、FR→设计映射表、
> rev 0.1.1 修订记录 DD-6、代码评审发现 CODE-BLOCK-001~003 的修复方案）；本节为基线摘要。

### 1. 设计要点

- **隐私收敛（DD-1/DD-2）**：核实发现 multica 实时层实为单条 workspace 级 socket、按 payload
  字段过滤，MUL-1138 的 per-channel 订阅基建已存在但客户端未接线，含 `ChatSessionID` 的事件
  （聊天消息/流式转录）当前仍全量走 workspace 广播——这是**既有全局 1:1 chat 一直存在的隐私
  泄漏面**，非本 CR 新增。方案：`events.Event` 加 `ChatRecipientID`，全部 9 处发布点填入会话
  creator（`TaskService.ChatSessionCreatorID` 有界 FIFO 缓存，容量 4096，同 `analyticsContextCache`
  同款模式），WS 桥接层对含 `ChatSessionID` 的事件一律 `SendToUser`，**fail-closed**（无收件人
  直接丢弃+ERROR 日志，不回落广播）——修复面覆盖 CR-2026-008 新增的 Private Ask 与既有全局 chat。
- **Ask-only 双重强制（DD-6 rev 0.1.1 + 代码评审 CODE-BLOCK-001）**：核实发现 chat 任务的
  brief 默认带 Repositories 节、`multica repo checkout` 无任务级只读机制——"Ask-only"最初设计
  假设的"既有语义天然满足"不成立，需本 CR 实现最小强制。首版实现（brief 省略 Repositories 节
  + daemon 拒绝 checkout）在代码评审中发现判定键 `req.TaskID` 由客户端（被限制的 agent 进程
  自身）完全控制，可省略/伪造以绕过；修复为改用服务端已为每个任务铸造的 `MULTICA_TOKEN`
  （claim 时签发、agent 进程自身持有但看不到其他任务的），daemon 侧 `activeTaskAuth` 对**全部
  任务**统一校验 token 匹配后才放行/拒绝，缺省或冒充一律拒绝。
- **B2 迁移 + get-or-create（DD-3/DD-4）**：`chat_session` 加 nullable `project_id` + 部分唯一
  索引（`(project_id, creator_id) WHERE status='active'`）防并发双开创建；get-or-create 取该键
  下最新 active 会话，无则建；全局 chat 列表/pending 聚合加排除谓词防止 Private Ask 会话串入。
- **前端（DD-7）**：`ChatMessageList`/`TaskStatusPill` 纯 props 直接复用；`ChatInput` 实测非纯
  props（内部读全局 `useChatStore` 的 draft 键），改手写 composer（对齐 CR-A Team Agent 面既有
  模式），并按 CLAUDE.md 的 pending-message 模式补本地待发气泡（代码评审 CODE-BLOCK-002 发现
  首版遗漏）。

### 2. 实现期与设计的偏差 / 代码评审发现（TASK 完成记录留痕）

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| Ask-only 强制机制 | 0.1.0 版假设"chat 任务本不做 worktree checkout，语义天然满足" | 核实证伪后 rev 0.1.1：brief 省略 + daemon 拒绝双重强制 | 工程纪律 4（事实断言先核实）：实地读 execenv 代码发现假设不成立 |
| Ask-only checkout 校验键 | daemon 侧按 `task_id` 判定是否限制 | 代码评审发现 `task_id` 客户端可控可伪造，改用服务端签发的 per-task `MULTICA_TOKEN` 校验，全任务统一校验 | CODE-BLOCK-001（严重）：判定键必须是被限制方拿不到的凭证，否则强制形同虚设 |
| 隐私收敛范围 | 仅覆盖 Private Ask 新增事件 | 核实既有全局 1:1 chat 同样受影响，一并收敛（同一处代码分支） | 修复点是共享的 WS 桥接层，无法只修一半 |
| 发送反馈 | 隐含复用 ChatInput 现成能力 | ChatInput 因全局 store 耦合放弃复用，改手写 composer；随即发现遗漏 pending-message 可见态，代码评审补齐 | CODE-BLOCK-002（主要）：CLAUDE.md 明文规则，且同 CR 家族 Team Agent 面已有先例未被沿用 |
| chatCreators 缓存 | 未明确设计缓存淘汰策略 | 代码评审发现进程级 `sync.Map` 无淘汰是慢性内存增长，改为与 `analyticsContextCache` 同款有界 FIFO | CODE-BLOCK-003（次要）：长期运行进程的缓存必须有界 |

### 3. 范围排除

附件/@提及（随 ChatInput 解耦后补，技术债见 docs/product/P2-ChatInput组件与全局store解耦-技术债务.md）、
技能选择器（全平台缺口，含 CR-A，同一文档 §7 记录）、会话列表/多会话切换、清空上下文——均不在
本 CR 范围。

## P2 CR-D — D6 Discussion 技术设计（v0.16 · CR-2026-009）

> 完整 SDD 见 change-requests/CR-2026-009/sdd.md（含 8 条设计决策 DD-1~DD-8、FR→设计映射表、
> AC→验证方式表）；本节为基线摘要。

### 1. 设计要点

- **容器同构（DD-1）**：`origin_type='project_discussion'`，migration 161 照抄 160
  （`project_chat`）的 DROP+ADD CHECK + 部分唯一索引模式；`origin_type` 列可空，谓词必须
  NULL 安全。
- **红线豁免落点（DD-2）**：`computeCommentAgentTriggers`（comment.go）顶部单点短路——该函数
  是 @agent/@squad 提及、父评论续聊路由、squad-leader fallback 四类触发的唯一汇聚点，一处短路
  覆盖全部 3 个调用点，API 直建 comment 的边缘入口同样被覆盖；成员提及通知走独立的
  `notifyMentionedMembers`，不受影响，FR-4 白拿。
- **发送不建新端点（DD-3）**：Discussion 复用既有 `POST /api/issues/{id}/comments`；薄发送端点
  的守卫→入队三段式在 Discussion 无一适用。
- **排除谓词清单化（DD-4）**：单值判断改为 NULL 安全的容器类型清单，8 处同步替换，保持一份
  可 grep 的容器清单。
- **独立入口端点（DD-5）**：`GET /api/projects/{id}/discussion` 与 `GetProjectChat` 同构，
  但不并入 chat 端点——避免打开 Team Agent 面时预创建从不使用的 discussion 容器。
- **草稿复用 ReplyInput 原生 draftKey（DD-6）**：以容器 issueId 为键天然隔离，不复用
  project-chat-store。
- **提及选择器不做前端过滤（DD-7）**：红线由服务端 DD-2 保证；ponytail 标注若实测误 @agent
  频繁，升级路径是 ContentEditor 增加 mention 目标过滤 prop。
- **inbox 跳转条（DD-8）**：容器起源 Issue 的 inbox 预览加「前往项目聊天」跳转条，
  `project_chat`/`project_discussion` 共用，`?tab=chat&mode=discussion` 深链；CR-A 的
  team-agent 提及通知同样受益。

### 2. 实现期与设计的偏差 / 代码评审发现（TASK 完成记录留痕）

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| `IssueResponse` 是否带 `origin_type` | SDD 假设已有该字段可直接读取 | 核实证伪：实际未带，补充 Go `IssueResponse.OriginType` 与 TS `Issue.origin_type` 两处字段 | 工程纪律 4（事实断言先核实）：实施期发现假设不成立，以 revision 修订 |
| `ensureContainerIssue` 抽取签名 | 直接复用 `GetProjectChatIssueParams` 结构体 | sqlc 为每个 origin type 生成独立 Params 结构体，无法直接复用；改为 `(q *db.Queries, ctx, projectID, workspaceID)` 闭包签名，调用方各自传入具体 sqlc 方法闭包 | sqlc 生成机制核实后调整，行为等价，非设计缺陷 |
| down 迁移真机验证 | 设计假设 down.sql 语义正确（先删容器数据再收约束） | 代码评审 SUG-002：在含真实 E2E 数据的隔离库上完整执行 down→up 往返演练，确认 CASCADE 删除评论正确、约束/索引复原、`project_chat` 容器不受影响 | 迁移类改动的 down 路径此前只静态审查未实测，本次补足真机验证闭环 |

### 3. 范围排除

FR-6 行内系统条本 CR 裁剪不实现——已核实 multica 无 project 级成员模型（成员唯一模型是
workspace 级 `member`），仅有瞬时 `member:added` WS 广播、不落任何持久化消息流，把 workspace
级成员变更持久化进每个项目的 Discussion 流属于错误作用域（见 §6.3）。DC 协调者、合并转发、
消息回复线程/转发/语音输入均不在本 CR 范围。

### 4. 数据模型（1 个 migration，无新表新列）

`161_issue_origin_project_discussion.{up,down}.sql`：CHECK 约束追加 `project_discussion`
允许值 + 部分唯一索引 `issue_project_discussion_unique`（每项目至多一个容器，并发 lazy 创建
下由索引兜底幂等）；down 对称回收，先删容器数据（`comment.issue_id` CASCADE 级联）再收紧约束。

## P2 CR-E — presenter 控制权 + claim 串行化键改造 技术设计（v0.17 · CR-2026-010）

> 完整 SDD 见 change-requests/CR-2026-010/sdd.md（含 9 条设计决策 DD-1~DD-9、3 个 migration、
> FR→设计映射表、AC→验证方式表）；本节为基线摘要。

### 1. 设计要点

- **presenter 状态单表（DD-1）**：`project_presenter_grant`，状态即审计（不删除只改状态），
  `(project_id) WHERE status='active'` 部分唯一索引保证单主持人。
- **claim 串行化键改造范围核实（SDD 开篇修正 PRD 前提）**：既有串行化键实为三分支
  （issue/chat_session/全 NULL），非单一 `agent_id`；本 CR 只把 issue 分支从"同 issue"放宽为
  "同 project"且跨 agent 互斥，`chat_session` 分支（Private Ask）原样保留，使 PRD"并行不受
  影响"由结构天然成立而非需要额外设计保证。
- **冗余 `project_id` 列（DD-3）**：入队时从 issue stamp，避免 claim 热路径双侧 JOIN issue。
- **claim 竞态防护三层（DD-4）**：入队守卫 + claim `NOT EXISTS` 谓词 + 提交前 advisory xact
  lock 复核，冲突方走既有 `RequeueAgentTaskAfterClaimFailure` 回队；12-agent 并发压测证明
  任意时刻恰一 active。
- **presenter 非空时插队优先级抑制（DD-6）**：容量豁免保留，priority 100 覆盖降为普通序——
  管理员可发送但不抢占 presenter 的排队消息。
- **撤销/转让不打断运行中任务（DD-7）**：只改 grant 行，运行中任务自然完成；紧急打断走既有
  CR-B 停止能力，未纳入本 CR 范围。
- **通知双通道（DD-8）**：六转移全部写 activity_log（挂容器 Issue，消息流卡片可回放）；
  五种转移另发 `notifyDirect` 定向 inbox（release 无定向对象）。跨包约束
  （`internal/service` 不可导入 `cmd/server`）以事件 payload 携带收件人列表 + `cmd/server`
  侧薄监听器解决，未引入循环依赖。
- **WS 零新增前端 handler（DD-9）**：新事件 `project:presenter_changed` 复用既有 `project:`
  前缀失效；流内卡片复用既有 `activity:created` 直写。

### 2. 实现期与设计的偏差 / 代码评审发现（TASK 完成记录留痕）

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| 发送端控制权守卫 | presenter==null 分支未在设计文档中显式排除全员放行的可能 | 实现期发现草稿版在 presenter==null 时提前放行所有成员（应仅 owner/admin），测试直接抓出后改为始终按完整公式判定 | 测试驱动开发发现的设计歧义：presenter=null 默认态仍需 owner/admin 门禁，不能因"无主持人"而放宽 |
| 权限面板转让交互 | 任务文档建议照抄 CR-A TeamAgentSetupPicker 搜索弹层骨架 | 改为面板内逐行直接放转让按钮 | 面板本身已把全部候选成员渲染成可见行，二次弹层是冗余交互；验收条件未受影响的实现期偏差，非设计缺陷 |
| composer 解锁判定 | 隐含假设 presenter 变为 null 即可视为解锁信号 | 测试驱动发现该假设对普通成员是错误的（null 是永久默认拒绝态非解决），改为仅在"presenter.user_id===本人"时才清除锁定 | 测试驱动开发直接抓出的真实生产 bug（原实现会导致拒绝提示条闪现即消失） |

### 3. 范围排除

presenter 申请的全局收件箱/站内信通知中心（通知触达以消息流卡片 + WS 实时 + 定向 inbox 为准）、
计费归属（Owner/Presenter 可配，仅留判定基础）、清空上下文对接 presenter 权限均不在本 CR。

### 4. 数据模型（3 个 migration，161–163）

`161_agent_task_queue_project_id`：加冗余 `project_id` 列 + 全量回填（含 active 行，使新 claim
SQL 上线即对在途任务生效）。`162_atq_project_active_index`：CONCURRENTLY 部分索引
`(project_id) WHERE status IN (active集)`。`163_project_presenter_grant`：presenter 状态表 +
两个 partial unique 索引（单 active、单 pending-per-user）。

## P2 CR-F — CR 门禁接合 技术设计（v0.9.0 · CR-2026-011）

> 完整 SDD 见 change-requests/CR-2026-011/sdd.md（含 8 条设计决策 DD-1~DD-8、1 个 migration、
> FR→设计映射表、AC→验证方式表）；本节为基线摘要。

### 1. 设计要点

- **门禁节点投影器（DD-1/DD-2）**：CR 状态机的合法转移事件投影为每项目的
  `pipeline_run`/`pipeline_node_run` 两表行（迁移 `162_aifirst_pipeline_runs`，因与
  CR-2026-008/CR-2026-009 撞号从 161 顺延），`detail JSONB` 存 review 节点的
  {verdict, blockers[], reviewer, reviewed_at}；投影更新复用既有 `cr:updated` WS 事件
  （DD-6，零新增事件类型）。
- **review 事件兜底通道（DD-3）**：daemon commit 扫描新增第 5 类正则匹配
  `[cr] review-(requirement|tech-design|code) verdict=...`，读取 `review-annotations/{stage}.yml`
  作为 payload（新 `event_kind=review`），tools/crctl 零改动。
- **cr_id 归因走 StartTask 回调（DD-4）**：daemon 从任务 workdir 的 git 分支派生 cr_id，
  服务端校验 cr 表存在同 workspace 行才落列（不信 daemon 自报）；`pipeline_node_run_id`
  本期无写者、恒 NULL（收窄 PRD FR-2，原因：七路入队点入队时点无 CR 上下文，且审批类
  gate node_run 本质没有对应队列任务，强行 1:1 关联是虚假数据）。
- **审批权限收口单函数（DD-5）**：`canApprove` 定案为 workspace owner/admin 单支，
  `cr.owners` 角色匹配因缺少 crctl 自由文本 `--caller` 到 Multica user id 的身份桥接而收窄
  （详见 change-requests/CR-2026-011/sdd.md §6.4）；`HandleApprove` 与新增的
  `GET /api/projects/{id}/gates` 均只依赖这一单点，升级路径是身份桥接就位后仅改
  `canApprove` 一处。
- **`GET /api/projects/{projectID}/gates`（DD-2 衍生）**：16 态 CR 徽标 + 待审批卡片
  （evidence 摘要 + digest + key_id）+ 各 CR 的 gate node 历史，一把返回；整组端点挂在既有
  `approvalSvc != nil` 条件组下（DD-8），前端 404 静默降级为门禁 UI 不显示。
- **前端消息流三源合并（DD-7 徽标挂点 + §5.2 CrGateCard）**：`CrStatusBadge` 挂在模式
  TabsList 右侧（多 CR 取 `updated_at` 最新的非终态者，popover 列全部在途 CR）；
  `CrGateCard` 三变体（待审批卡/blocked 卡/历史行）按时间戳与评论、Agent 执行卡一起
  合并进 `TeamAgentStreamView` 的同一时间轴。

### 2. 实现期偏差 / 代码评审发现（TASK 完成记录 + review-code 留痕）

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| gate_nodes.detail 序列化 | 未明确类型 | 实现期一度用 `[]byte`（HTTP 响应里被 base64 编码），测试 `TestProjectGatesDetailIsEmbeddedJSONNotBase64` 抓出后改为 `json.RawMessage` | 测试驱动开发发现的真实序列化 bug，非设计缺陷 |
| gate 节点历史标签 | 假设 `passed` 与 `kind===human_approval` 可独立判断标签 | 实现期发现失败/取消节点被先按 `kind` 分支误标成"审批段名"而非"已取消"，改为先判 `!passed` | 前端测试直接抓出的真实文案 bug |
| gate 节点 stage 归属 | 假设可直接复用 CR 当前 `pending_stage` | 实现期发现已通过节点的 stage 标签会被 CR 的"当前阶段"覆盖（同一 CR 多阶段场景下历史行会显示错误阶段名），改为服务端 `Stage` 字段 + `stageForNodeID` 反查 | 双端补测试才抓出的数据关联 bug |
| `TestGrantCrossVerifiesWithCrctl` | 假设路径自动探测能定位 nested worktree 下的 crctl | 该测试因路径不匹配已被静默跳过多个 CR 周期，本次改为显式 `CRCTL_PATH` 环境变量后首次真正跑通 | 关闭一个此前被当作"通过"、实际从未执行的验证缺口 |
| **[review-code 安全发现]** 审批 evidence 查询跨 workspace 泄露 | `latestEvidence` 只按 `cr_id` 查 `cr_sync_event`，未意识到该表无 `workspace_id` 列而 `cr_id` 仅 workspace 内唯一 | 本 CR 新增的 `/api/projects/{id}/gates` 端点复用同一逻辑，把"另一 workspace 同名 CR 的 evidence 可被本 workspace 看到"这一暴露面从"需直调 API"扩大到"任意项目成员"；review-code 阶段发现并修复：`latestEvidence` 改为 `JOIN cr` 按 `cr.workspace_id` 过滤，新增回归测试 `TestApprovalCardDoesNotLeakEvidenceAcrossWorkspaces`（临时回退验证过确实能捕获该泄露） | 独立评审 subagent + 人工复核发现的真实跨租户数据暴露面，非本 CR 引入但由本 CR 扩大，已在合并前修复 |

### 3. 范围排除

Pipeline Runner（首个 skill 节点写者，`pipeline_node_run_id` 才会有真实写入）、
审批周边的批量/委派/超时策略，均不在本 CR；见
`docs/product/CR-F范围排除项-后续交付规划.md` 的后续 CR 规划。

### 4. 数据模型（1 个 migration，162）

`162_aifirst_pipeline_runs`（原编号 161，因与 CR-2026-008/CR-2026-009 撞号顺延）：
`pipeline_run`/`pipeline_node_run` 两表 + `agent_task_queue.cr_id`/`pipeline_node_run_id`
两列。`pipeline_node_run.detail JSONB` 是对 P0 §3.4 的单列增补，存 review 节点的
blocker 明细；`UNIQUE(run_id, node_id, attempt)`。

## 基线变更记录

| 日期 | 基线版本 | CR | 说明 |
|------|---------|----|------|
| 2026-07-30 | v0.1.1 | CR-2026-001 | 基线建立：M0 地基技术设计回写 |
| 2026-07-31 | v0.2.0 | CR-2026-002 | 改为累积式基线：保留 M0 全文并新增 P1 治理核心节；组件表扩至 12 项（M0 4 + P1 8） |
| 2026-07-31 | v0.2.1 | CR-2026-003 | 缺陷修补附记（§9）：embedded 占位符幂等键碰撞（缺陷 A）+ 归档 CR 自愈（缺陷 C）；不新增 FR/AC，缺陷 B 明确不修 |
| 2026-08-01 | v0.3.0 | CR-2026-004 | 新增 P2 D1 里程碑节：共享队列容量治理（守卫/插队/撤回/读侧）；4 项实现期偏差留痕 |
| 2026-08-01 | v0.3.1 | CR-2026-005 | 新增治理工具链补丁节：deliveryIndexComplete 门禁 + writeback-tasks 重写；2 项实现期偏差留痕 |
| 2026-08-02 | v0.4.0 | CR-2026-006 | 新增 P2 CR-A 里程碑节：容器 Issue 方案+薄发送端点+模型选择器技术设计；3 项实现期偏差/代码评审发现留痕 |
| 2026-08-02 | v0.5.0 | CR-2026-008 | 新增 P2 CR-C 里程碑节：B2 迁移 + WS 隐私收敛（含既有全局 chat 同一泄漏面修复）+ Ask-only 双重强制技术设计；5 项实现期偏差/代码评审发现留痕 |
| 2026-08-02 | v0.6.0 | CR-2026-009 | 新增 P2 CR-D 里程碑节：discussion 容器同构方案 + 触发豁免单点短路 + migration down→up 真机演练技术设计；3 项实现期偏差/代码评审发现留痕；补齐 frontmatter cr-ref/cr-history/version 漂移 |
| 2026-08-02 | v0.7.0 | CR-2026-007 | 补跑新增 P2 CR-B 里程碑节：D3 完整形态技术设计（停止入口/撤回=停止同端点+幂等竞态语义/队列明细读侧 opt-in 扩展/过滤开关谓词/既有关联复用）；3 项代码评审发现留痕（initials 去重、冗余条件拍平、prop-drilling 判断性保留）；本 CR 排期先于 CR-C/CR-D（target-version 0.14）但实际回写晚于两者，按版本号插入于 CR-A 与 CR-C 之间，target-version 维持 0.16 不回退 |
| 2026-08-03 | v0.8.0 | CR-2026-010 | 新增 P2 CR-E 里程碑节：presenter 控制权单表状态机 + claim 串行化键 agent_id→project_id 技术设计（三层竞态防护、通知双通道跨包方案）；3 项实现期偏差/测试驱动发现留痕；target-version 0.16 → 0.17 |
| 2026-08-03 | v0.9.0 | CR-2026-011 | 新增 P2 CR-F 里程碑节：CR 门禁接合技术设计（门禁节点投影器 + review 事件兜底通道 + Ed25519 签名审批网页化 + CrStatusBadge/CrGateCard 消息流合并）；4 项实现期偏差留痕 + 1 项 review-code 阶段发现并修复的跨 workspace evidence 泄露（`latestEvidence` 补 workspace 过滤）；target-version 0.17 → 0.18 |
| 2026-08-04 | v0.10.0 | CR-2026-019 | 新增治理工具链里程碑节技术设计：casWriteMulti 双文件原子写 + 三子命令 CLI 契约 + AC-9 merge-tree 演练固化；target-version 0.20 → 0.20.1 |

### 实现期与设计的偏差（已在各 TASK 完成记录留痕）

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| 审计上报通道 | 结构化 stdout 行 → daemon 捕获解析 | 复用 outbox 事件通道（`event_kind: audit`） | 离线积压/ack/三振语义免费复用，daemon 零改动 |
| 工具调用摘要落点 | 与 `skills_used[]` 同层 | 服务端 CompleteTask 聚合进 `result.tool_calls` | multica 上游无 `skills_used[]` 字段；服务端聚合避免信任 daemon 输入 |
| daemon 模式对账 | 定时 `crctl status --json` 快照上报 | daemon 直读 `_backlog.yml` 原文 + HEAD，服务端统一解析 | 避免 daemon 依赖 node 运行时；两模式共用一个解析器 |
| daemon workspace 绑定 | 仅信 `mdt_` daemon-token | `mdt_` 优先 + PAT 回退查 member 表 | 上游 `mdt_` 签发流程尚未接线，真实 daemon 走 PAT 路径（T11 实测暴露） |


## P2 CR-G · D8 DC 协调者 + 讨论转执行 技术设计（v0.19 · CR-2026-012）

> 本 SDD 基于 multica `requirement/CR-2026-012` worktree（44769bbb8，含 CR-2026-009/010/011 全部合并）
> 的实地代码调查编写，所有文件路径/行号均已核实。需求评审 4 条建议（REQ-SUG-001..004）的落地见 §6。
> 路径相对 multica 仓根。
>
> **调查纠正 PRD 两处引用假设**（工程纪律留痕）：① PRD 引用的 `shadowchat.mergedForwardMessage`
> 等字典锚点是 CodeBanana 参考文档的锚点，multica 无 `shadowchat` 命名空间——新增文案按仓内惯例
> 落 `projects.json` 嵌套对象、snake_case、四语同 commit（DD-12）。② PRD FR-6 假设的
> "P0 Issue→CR 升级链路"在服务端不存在（router 全集核实：CR 相关只有 crctl 事件投影摄入 +
> 三个只读/审批端点，无任何 create/promote 路径；158 迁移注释明示权威在 git）——升级为 CR
> 由执行 Agent 按 requirement-register Skill 完成，服务端零 CR 写路径（DD-8）。

### 1. 架构概览

三块工作互相独立、可并行实施，汇合在 Discussion 面与 Team Agent 面：

```
① DC 协调者（后端为主）
   Discussion comment → computeCommentAgentTriggers（comment.go:1579 短路点改造：全拒 → 仅放行 DC）
        └─ @DC 触发 → EnqueueTaskForMention（既有，容量守卫适用）→ DC 任务（挂 discussion 容器）
             ├─ claim：AskOnly=true（新规则：discussion 容器任务一律只读沙箱，复用 CR-C 整链）
             ├─ 完成：CompleteTask → createAgentComment（既有不变量）→ 协调输出=可见 comment
             └─ DC 输出含 @{Team Agent} → enqueue 层 re-target（DD-5）→ 任务落 team-agent-chat 容器
② 合并转发（前后端）
   DiscussionPane 多选态（新，本地 Set state）→ 合并预览 Dialog →
   POST /api/projects/{id}/chat/merge-forward（新端点）
        └─ 校验选中 comment ∈ 本项目 discussion 容器 → 组装合并结构 markdown
           → 复用 SendProjectChatMessage 服务内核（presenter/容量守卫 + comment + enqueue + 补偿删除）
③ ChatInput 解耦（纯前端）
   ChatInput 拆为 ChatInputCore（只认 adapter）+ 默认包装（useChatStore adapter）
        └─ Team Agent 面 / Private Ask 面以 project-chat-store adapter 接入（附件槽扩展 DD-10）
```

### 2. 关键设计决策

| # | 决策 | 依据与替代方案权衡 |
|---|---|---|
| DD-1 | **DC = agent 模板 + project setting**：新增 agenttmpl 模板 `discussion-coordinator`（agenttmpl/templates/*.json，25 个模板同款），项目绑定走 `project.settings` 新 key `discussion_coordinator_agent_id`（镜像 `team_agent_id`，task_queue_capacity.go:35 先例）；创建时 `permission_mode=public_to`+workspace target（全员可 @）。**不引入 DB 级内置 Agent**（全仓无 is_system 先例，agenttmpl 包注释明示模板故意 repo-only） | 替代：agent 表加 is_system 列——为一个角色建新机制，且违背模板先例；弃 |
| DD-2 | **激活口子 = 短路点改造**：`computeCommentAgentTriggers`（comment.go:1579-1590）的 `project_discussion → return nil` 改为：读项目 settings 的 DC id，未配置 → 照旧 return nil；已配置 → 正常计算后**过滤只保留 `agentID == DC`** 的触发。@提及经既有 `canInvokeAgent`（comment.go:1696）鉴权。**v1 仅 @提及激活**：Discussion 是刻意的扁平流（discussion-pane.tsx:25-36 设计注释，无 reply 线程），"回复 DC 激活"裁剪（§6.1）；未来若 reply-to 落地，父评论路由触发天然被同一过滤覆盖，零额外改动 | 单一 choke point 是 CR-D 验证过的豁免面（4 调用点共用），在同点收窄保证"红线单开口"（NFR-2）可测试自证 |
| DD-3 | **DC 只读 = claim 层规则**：issue 任务 claim 响应中，任务所挂 issue 为 `project_discussion` 容器 → `AskOnly=true`（agent.go:329 wire 字段已有，CR-C 整链复用：brief 无 Repositories 段 runtime_config_sections.go:558、checkout 拒绝 daemon.go:2888 activeTaskAuth、health_test.go:437 有测试形态可抄）。DC 模板技能集只配 `mentioning`（builtin） | "forbidden 全部写 Skill"：技能本是白名单制（LoadAgentSkillBundles，daemon.go:2250 不在 allowed 即 404），模板不配写类技能 + AskOnly 沙箱双重达成；不需要新的黑名单机制 |
| DD-4 | **DC 可见输出 = 零新增**：DC 任务是 discussion 容器上的 issue 任务，完成不变量（task.go:1920-1958 CompleteTask→createAgentComment）自动落 agent comment → `comment:created` workspace 广播（listeners.go:209）全员实时可见、刷新回放。失败且不重试 → 既有 `type="system"` comment（task.go:2113）。**trivial 抑制豁免**（评审 TSUG-002）：`isTrivialDoneOutput` 抑制（task.go:1951）对 discussion 容器任务豁免（一行容器判定），保证"激活必有可见输出"（AC-2）是机制保证而非 prompt 约定；DC 模板 instructions 同时要求实质性总结输出，测试补 trivial 输出边界用例 | REQ-SUG-003 所担心的"新增后端接缝"经核实不存在——这正是选择"DC 任务挂 discussion 容器"而非独立会话模型的决定性理由 |
| DD-5 | **DC 路由 = enqueue 层 re-target**：`enqueueSingleCommentTrigger`（comment.go:1540）处新增：触发 comment 所在 issue 为 discussion 容器、作者为 DC、目标为项目 `team_agent_id` 时，改为 `EnsureProjectChatIssue` + 以 DC 身份（authorType=agent）落一条路由 comment 于 chat 容器 + `enqueueMentionTaskWithCommentPlan` 挂 chat 容器——任务与路由说明出现在 **Team Agent 面**（AC-3）；DC 在 Discussion 的完成输出即协调说明。originator 经 trigger comment 链解析为激活 DC 的人类（resolveOriginatorForIssueTask，task.go:863），容量守卫按人类 originator 正常适用 | 替代：放行 DC 的 @团队Agent 就地入队（挂 discussion 容器）——任务/输出全落 Discussion，Team Agent 面不可见，违背 AC-3 与"讨论归讨论、执行归执行"的容器语义；弃 |
| DD-6 | **满队可审计反馈**：discussion 容器上的触发 enqueue 撞 `ErrProjectQueueFull` → 以 system comment 落容器（结构化文案：队列 N/M），不静默（既有普通 Issue 评论触发失败仅日志，本 CR 不改那边）；合并转发端点同步返回 429 `project_queue_full`（复用 writeProjectQueueFull，issue.go:2033），前端保留多选态与预览 | REQ-SUG-004；DC 激活是 fire-and-forget comment 路径，429 无处返回，system comment 是"过程即记录"下唯一诚实呈现 |
| DD-7 | **合并转发 = 新端点复用 Send 内核**：`POST /api/projects/{id}/chat/merge-forward`；服务端取选中 comments（校验全部属于本项目 discussion 容器）按 created_at 排序，组装合并结构 markdown（§4.3），走 `SendProjectChatMessage` 同款服务序（presenter 守卫 → 容量守卫 → CreateComment on chat 容器 → enqueue → 失败补偿删除 → 成功才广播，project_chat.go:191-259 逐步复用）。**不用 `coalesced_comment_ids`**——该机制假设同 issue 的 comment 交付计划，跨容器语义不符 | presenter 守卫在既有路径内自然生效（CR-E 已交付），无需本 CR 关心；上限 `comment_ids ≤ 50` 防 prompt 爆量（ponytail: 超长讨论合并的摘要压缩是升级路径） |
| DD-8 | **升级 CR = prompt 指令，服务端零 CR 写路径**：请求带 `register_cr: true` → 组装内容追加 requirement-register 指令块（要求 Team Agent 按该 Skill 建 CR 并回报 CR-ID）。判定语义（REQ-SUG-002 定案）：**不做服务端强制**——预览内「升级为 CR」复选框由用户决定，默认勾选态 = 前端读 projectGates（project-team-agent-chat.tsx:107 已消费的 `projectGatesOptions`）无在途 gate 时默认勾选，有则默认不勾；cr_id 归因走既有 `AttributeTaskToCR`（daemon.go:2412 StartTask CRID 回传），注册成功后的后续 pipeline 节点任务自然归因，本 CR 不加列不加端点 | CR 权威在 git（158 迁移注释），任何服务端"建 CR"端点都违背权威铁律；指令块随 comment 可见，升级动作本身留在讨论记录里 |
| DD-9 | **ChatInput 拆分而非条件分支**：抽 `ChatInputCore`（props 收 `draftAdapter: ChatInputDraftAdapter`，内部零 useChatStore）+ 既名导出 `ChatInput`（薄包装：内部 hook 构造默认 adapter——读 activeSessionId/selectedAgentId 派生 draftKey/editorKey + 四写方法，语义与今日逐字节一致）。传入自定义 adapter 的消费方直接用 `ChatInputCore` | rules-of-hooks 下"传 adapter 就不订阅 store"无法在单组件内做条件 hook；拆分让"自定义 adapter 时不触碰 useChatStore"成为**结构性事实**，单测静态断言可锁（§5.4）。`/chat` 页与浮窗 import 与 props 零改动 |
| DD-10 | **project-chat-store 扩附件槽**：`draftAttachments: Record<key, Attachment[]>` + `setDraftAttachments/addDraftAttachment`（key 沿 `projectChatDraftKey`），`setDraft("")` 时联动清附件；沿既有 zustand persist（`multica_project_chat`）与 workspace rehydration | 全局 store 有附件持久化先例（store.ts:81-113）；不持久化则切 tab 丢附件，与文本草稿语义不对称 |
| DD-11 | **@提及仅成员 = 编辑器类型过滤**：`MentionSuggestionOptions` 加 `itemTypes?: MentionItem["type"][]`（buildSyncItems 结果按 type 过滤，含 server-search 分支），`ContentEditor` 透传新 prop `mentionItemTypes`；两个回填面传 `["member"]`。Discussion 面维持 CR-D DD-7 现状（不过滤，服务端红线兜底）不动 | 通用 editor 小改（一处过滤点），比在消费方包装 contextItems 干净；CR-D 当时评估的"层层透传"成本因本 CR 本来就动 ContentEditor props 而摊薄 |
| DD-12 | **字典键落位**：`projects.json` 新增嵌套对象 `chat.merged_forward.*`（trigger_message / chat_history / messages_in_conversation / preview_title / confirm / cancel / register_cr_label 等）与 `chat.dc.*`（queue_full_notice 等），snake_case、四语同 commit（CR-D 惯例：git 3bce9ade0，8 文件一次补齐，parity.test.ts 强制） | PRD 引用的 shadowchat.* 是 CodeBanana 锚点非仓内键（§0 纠正①） |

### 3. 数据模型与迁移

**零 migration**。全部落在既有结构：

| 变更 | 载体 |
|---|---|
| DC 绑定 | `project.settings` JSONB 新 key `discussion_coordinator_agent_id`（读法照抄 task_queue_capacity.go:100-114 的 settings 读取，非法值视为未配置） |
| DC Agent 本体 | 普通 agent 行（模板物化，agenttmpl 机制） |
| DC/合并转发任务 | `agent_task_queue` 既有列（trigger_comment_id / project_id / originator_user_id 等，B4 两列不动） |
| 合并转发消息 | chat 容器上的普通 comment（合并结构在 content markdown 内） |
| 回填面附件草稿 | 前端 project-chat-store persist（非 DB） |

### 4. 后端设计

#### 4.1 触发过滤改造（DD-2，本 CR 唯一动既有行为的点之一）

`computeCommentAgentTriggers`（comment.go:1579）：

```go
if issue.OriginType.Valid && issue.OriginType.String == "project_discussion" {
    dcAgentID := h.projectDiscussionCoordinatorID(ctx, issue.ProjectID) // settings 读取，未配置 → 零值
    if !dcAgentID.Valid {
        return nil // CR-2026-009 红线原样
    }
    triggers = computeAsUsual(...)
    // 放行两类并集（SDD-BLOCK-001 修正）：
    //  ① 目标为 DC 的触发（激活：@DC；未来 reply-to 落地则父评论作者=DC 亦命中）
    //  ② 作者为 DC 且目标为项目 team_agent_id 的显式提及触发（路由，交 §4.2 re-target 消费）
    // 其余（成员提及、@第三方 agent、squad、续聊路由）照旧丢弃；DC @DC 自触发按作者=目标排除
    return filterDiscussionTriggers(triggers, dcAgentID, teamAgentID, commentAuthor)
}
```

- 4 个调用点（comment.go:1150/1358/2294、daemon.go:2730）自动继承收窄语义；DC 完成输出中的
  @{team agent} 提及经 daemon.go:2730（completion reconcile）与 comment.go:1358 两路都会命中
  第 ② 类，均汇入 §4.2 的 re-target。
- `discussion_trigger_exemption_test.go` 全量保留（未配置 DC 场景）+ 新增已配置 DC 的分支：
  @DC 放行（①）、成员 @其他 agent 仍拒、正文含 DC 名字无 mention 链接不触发（mention 是
  `[@Label](mention://…)` 结构化链接，纯文本天然不命中）、**DC 作者 @团队Agent 放行（②）、
  DC 作者 @第三方 agent 拒、DC @DC 自触发拒**。

#### 4.2 DC 路由 re-target（DD-5）

`enqueueSingleCommentTrigger`（comment.go:1540）`case commentTriggerSourceMentionAgent` 内：

```go
if isDiscussionContainer(issue) && commentAuthorIsDC && trigger.AgentID == projectTeamAgentID {
    chatIssue := EnsureProjectChatIssue(...)
    routeComment := CreateComment(chatIssue, AuthorType: "agent", AuthorID: dc, content: 原 DC comment 摘录 + 路由标注)
    task := enqueueMentionTaskWithCommentPlan(chatIssue, teamAgentID, routeComment.ID, ...)
    // 满队 → DD-6 system comment 落 discussion 容器；成功 → EventCommentCreated 广播 chat 容器侧
}
```

- 进入本分支的正是 §4.1 第 ② 类触发（DC 作者 × team_agent 目标）；第 ① 类（激活）走普通
  就地入队。DC @成员 / @第三方 agent / DC @DC 均已在 §4.1 过滤，不进本分支。
- **originator 定案**（评审 TSUG-001）：DC 完成 comment 的 `parent_id` = 激活它的人类 @DC
  comment（task.go:1958 createAgentComment 以 TriggerCommentID 为 parent），re-target 分支
  由此链显式解析激活人类并作为路由任务的 originator 传入——容量守卫按人类 originator 生效；
  若链上解析不到人类（异常态），沿 task_queue_capacity.go:49-57 的既有 a2a 直通语义放行并
  记日志，AC-3 验收以显式解析路径为准。任务期核实 `resolveOriginatorForIssueTask` 是否已
  具备穿透能力，不足则在 re-target 处显式计算后透传（enqueue 变体参数或入队后 set，取小者）。

#### 4.3 合并转发端点（DD-7/DD-8）

```
POST /api/projects/{id}/chat/merge-forward        （router.go:1081 旁，user session 鉴权）
req : { comment_ids: string[] (1..50), register_cr?: boolean }
resp: 201 { comment_id, task_id }                  （同 SendProjectChatMessageResponse）
err : 400 invalid_comment_selection（空/超限/含非本项目 discussion 容器的 comment）
      403 presenter_required ｜ 409 team_agent_not_configured ｜ 429 project_queue_full
      502 enqueue_failed（补偿删除后）
```

组装的 comment content（markdown，全员可读即"合并预览"的持久形态）：

```
## {chat.merged_forward.trigger_message}
> {最早一条选中消息全文（作者/时间标注）}

## {chat.merged_forward.chat_history}（{count} 条）
- [{作者} {时间}] {消息内容}
- …（按 created_at 升序）

[register_cr=true 时追加]
## 升级为 CR
请按 requirement-register Skill 将上述讨论注册为 CR（目标 workspace 的 knowledge-base 仓），
完成后在本会话回报 CR-ID。
```

服务函数 `MergeForwardDiscussion`：校验（comments 全属 `GetProjectDiscussionIssue` 的容器）→
复用 `SendProjectChatMessage` 的守卫与补偿序（project_chat.go:191-259 抽公共内核或平行实现，
以抽内核为先）。`trigger_summary` 由既有 `buildCommentTriggerSummary` 自然生成。

#### 4.4 AskOnly claim 规则（DD-3）

issue 任务 claim 组装处（agent.go:312-329 响应体 / daemon.go 对应 handler）：任务 issue 的
`origin_type == 'project_discussion'` → `resp.AskOnly = true`。规则按容器而非按 agent——
**discussion 容器上的任何任务都只读**（当前只有 DC 任务能挂上来，规则面向未来收敛）。
chat session 路径的既有 AskOnly 判定（daemon.go:1846）不动。

#### 4.5 DC settings 读取与配置

- `projectDiscussionCoordinatorID`：settings JSONB 读 key，UUID 解析失败视为未配置（fail-safe 回到红线全拒）。
- 配置入口沿 `team_agent_id` 的既有 project settings 更新端点/UI 面（CR-A 已有），新 key 零后端改动
  （settings 是自由 JSONB）；前端设置面加一个 agent 选择器项。

### 5. 前端设计

#### 5.1 DiscussionPane 多选态 + 合并预览（无先例，自研交互）

- **多选态**：`DiscussionPane` 本地 `useState<Set<string>>`（消息量级小，无需 zustand；
  issue selection-store 是跨组件场景，此处单组件内够用）。入口：消息 hover 操作或工具条
  「选择」按钮进入选择模式 → `DiscussionMessage` 左侧渲染 Checkbox（`@multica/ui`）。
- **底部批量条**：选中 N>0 时浮出（batch-action-toolbar.tsx 视觉惯例）：「已选 {count} 条」+
  「合并转发」+「取消」。
- **合并预览 Dialog**：trigger_message = 最早一条选中消息；chat_history 列表（作者/时间/内容，
  升序）；`messages_in_conversation` 计数文案；「升级为 CR」Checkbox（默认态按 DD-8 读
  projectGates；**gates 端点缺失/报错时回落默认不勾选**——端点受 approvalSvc 特性开关保护，
  签名密钥未配置的环境整组路由不存在，router.go:720-727，评审 TSUG-003）；确认 → POST
  merge-forward → 成功 toast + 退出多选态；429/403 → 结构化错误提示，**保留多选态与预览**（DD-6）。
- DC 绑定后 Discussion 空态/教程文案不动；DC 的 agent comment 用既有 `DiscussionMessage`
  渲染（ActorAvatar 已按 author_type 分支），零新组件。

#### 5.2 ChatInputCore 拆分（DD-9）

`packages/views/chat/components/chat-input.tsx` 内：

```ts
export interface ChatInputDraftAdapter {
  draftKey: string; editorKey: string;
  draft: string; attachments: Attachment[];
  setDraft(draft: string): void;
  setAttachments(attachments: Attachment[]): void;
  addAttachment(attachment: Attachment): void;
  clearDraft(): void;
}
function ChatInputCore(props: ChatInputProps & { draftAdapter: ChatInputDraftAdapter }) { …今日全部实现，store 触点逐一改读 adapter… }
export function ChatInput(props: ChatInputProps) { const adapter = useGlobalChatDraftAdapter(); return <ChatInputCore {...props} draftAdapter={adapter} />; }
```

五处触点全部改经 adapter（技术债文档 §4.1 四处 + 探查补充的 `onUpdate` :387-398 写点）：
读订阅（:112-150）、restore effect（:186-220，`restoreDraftRequest.sessionId !== adapter.draftKey`
判定不变）、`handleUpload`（:231）、`handleSend/commitInput`（:284 keyAtSend 捕获改捕获
adapter 引用 + :309-312 清理，`extraDraftKeys` 语义仅默认 adapter 使用方需要，Core 里保留
回调形态）、`onUpdate`（:389/:395）。JSX（:354-441）与既有 `ChatInputProps` 不变；
`/chat` 页（chat-page.tsx:194）与浮窗（chat-window.tsx:867）零改动。

#### 5.3 两面回填（DD-10/DD-11）

- **project-chat-store 扩展**：`draftAttachments` + 两写法 + `setDraft("")` 联动清理（§2 DD-10）。
- **adapter 构造**（每面约 15 行 hook）：`draftKey = projectChatDraftKey(projectId, mode)`、
  `editorKey = mode`（恒定，项目面无"切 agent 重挂载"语义，技术债文档 §4.3 定案照抄）。
- **Team Agent 面**：`TeamAgentComposer` 的 textarea（project-team-agent-chat.tsx:845-859）
  换 `ChatInputCore`；`onSend` 接既有 `useSendProjectChatMessage` 流（pending bubble/错误分支
  :708-765 不动）；**薄发送端点扩 `attachment_ids?: string[]`**（SendProjectChatMessageRequest
  project_chat.go:214 加可选字段，comment 绑定沿 `POST /api/issues/{id}/comments` 的既有
  attachment 绑定逻辑抽用）；`onUploadFile` 用 `useFileUpload(api).uploadWithToast(file, { issueId: chat容器 })`；
  `mentionItemTypes=["member"]` + `contextItems`（use-chat-context-items 既有）。
- **Private Ask 面**：`PrivateAskComposer` 同款替换；`onSend` 接 `api.sendChatMessage`（附件
  参数沿全局 chat 的既有签名）；`onUploadFile` 绑定已有 session；`mentionItemTypes=["member"]`。
  停止按钮/模型只读徽标等结构不动（只换输入组件）。
- Discussion 面**不接** ChatInput（CR-D DD-6 的 useCommentDraftStore 草稿语义保留）。

#### 5.4 单测锁定（PRD FR-7）

`chat-input.test.tsx` 新增：
- **静态断言**：mock `@multica/core` 的 `useChatStore`，渲染 `ChatInputCore` + 自定义 adapter，
  断言 mock 零调用（拆分后为结构性成立，测试防未来回归）。
- **行为断言**：输入/上传/发送/restore 各动作后断言 adapter 方法按预期调用、全局 store state
  快照不变。
- 既有用例全量跑在 `ChatInput` 默认包装上，证明默认路径零回归。

#### 5.5 locale（DD-12）

`projects.json`：`chat.merged_forward.*`（约 10 键）、`chat.dc.*`（约 3 键）、settings 面
DC 选择器文案；四语同 commit，parity 全绿。

### 6. 需求评审建议落地

#### 6.1 REQ-SUG-001（回复激活）——定案：v1 裁剪为仅 @提及激活

Discussion 是刻意的扁平 comment 流（CR-D 设计注释 discussion-pane.tsx:25-36，reply 线程被
切分文档 §0.4 写死排除）；为 DC 单独引入 reply-to UI 违背该定案且服务端父评论路由需要
parentId 才能命中。**AC-2 按 @提及单一激活方式验收**，本节即裁剪留痕。升级路径：未来 reply-to
落地时，DD-2 的过滤对"父评论作者为 DC"的触发天然放行，零额外后端改动。

#### 6.2 REQ-SUG-002（升级 CR 判定 + 归因）——定案见 DD-8

判定不做服务端强制（用户勾选，前端 projectGates 提供默认态建议）；cr_id 归因依赖既有
StartTask CRID 回传链，注册产生的后续节点任务自然归因；合并转发任务本身注册前无 CR-ID
可归因，属 CR-H（Runner）范围外的已知留白，不在本 CR 造临时机制。

#### 6.3 REQ-SUG-003（DC 输出机制）——定案见 DD-4，接缝不存在

DC 任务挂 discussion 容器 → 完成不变量自动落 agent comment → workspace 广播。零新增通道、
零新增身份机制（author_type=agent 渲染现成）。失败呈现沿 type="system" comment 既有语义。

#### 6.4 REQ-SUG-004（满队反馈）——定案见 DD-6

合并转发：同步 429 + 前端保留选择态。DC 激活：system comment 落容器（唯一可审计的
异步反馈位）。测试计划补两用例（§9 风险表关联）。

### 7. FR → 技术实现映射

| FR | 落点 |
|---|---|
| FR-1 DC 角色 | DD-1（模板+setting）+ §4.5；权限 DD-3（AskOnly claim 规则 + 白名单技能集） |
| FR-2 静默/激活边界 | §4.1 过滤改造（未配置=全拒不变；@提及经 canInvokeAgent；纯文本名字不命中） |
| FR-3 可见输出+路由 | DD-4（完成不变量落 comment）+ §4.2 re-target（路由现身 Team Agent 面） |
| FR-4 多选态+合并预览 | §5.1（本地 Set + 批量条 + 预览 Dialog，自研交互定案） |
| FR-5 合并生成单任务 | §4.3 端点 + 组装结构（一次确认 = 1 comment + 1 task） |
| FR-6 升级 CR | DD-8（register_cr 指令块，服务端零 CR 写路径，判定=用户勾选+gates 默认态） |
| FR-7 draftAdapter 解耦 | DD-9 + §5.2（拆分结构性达成"不触碰"）+ §5.4 双重锁定 |
| FR-8 两面回填 | §5.3（adapter + 端点扩 attachment_ids + mentionItemTypes 过滤） |

### 8. 安全与性能考量

- **红线单开口自证**（NFR-2）：收窄仍在唯一 choke point（4 调用点共用）；未配置 DC 的项目
  行为与 CR-D 交付态逐字节一致；exemption 测试保留 + 扩展。
- **DC 权限硬约束**（NFR-1）：AskOnly 在 claim 响应置位、daemon activeTaskAuth 执行期强制、
  brief 无 Repositories 段——三层同 CR-C 交付链，非 prompt 约束；技能白名单制天然禁写类 Skill。
- **越权面**：merge-forward 校验 comment 归属（跨项目/跨容器 id 混入 → 400）；DC 触发过 canInvokeAgent；
  升级 CR 指令块只是 comment 文本，执行强度由 Team Agent 的既有 execenv/controlled-shell/crctl
  验签链承担，本 CR 不新增执行通路（NFR-3）。
- **性能**：合并转发 ≤50 条上限；组装为一次批量查 comments + 一次 comment 写入；DC 触发过滤
  多一次 settings 读取（GetProject 单行，可与既有 projectTeamAgentID 读取合并）。
- **redaction**：DC/团队 agent 输出沿 redact.Text 既有路径（task.go:1950/2113），无新泄露面。

### 9. 风险与回归面

| 风险 | 缓解 |
|---|---|
| 触发过滤改造误伤普通 Issue 评论触发 | 改动仅在 `project_discussion` 分支内；既有 exemption 测试 + comment 触发全量单测回归 |
| re-target 分支的补偿语义（路由 comment 落了、enqueue 失败） | 沿 SendProjectChatMessage 的补偿删除模式（project_chat.go:236）；失败落 DD-6 system comment |
| ChatInput 拆分回归 /chat 页与浮窗 | 默认包装保持既名导出与 props；既有 chat-input.test.tsx 全量 + 浮窗/全页手测；draftKey/editorKey 派生逻辑原样搬入默认 adapter（含 :114-140 注释语义） |
| project-chat-store 扩附件后 persist 兼容 | 新字段可缺省（旧持久化数据无 draftAttachments → 空 map），rehydration 测试补分支 |
| mentionItemTypes 过滤漏 server-search 分支 | buildSyncItems 与 MentionList 异步搜索两处都过滤；单测断言 agent/squad/issue 不出现 |
| 合并转发长内容 prompt 爆量 | ≤50 条硬上限 + trigger_summary 截断既有机制；`ponytail:` 注释标注摘要压缩为升级路径 |
| parity 漏键 | 四语同 commit（CR-D 惯例），parity.test.ts 门禁 |

### 10. AC → 验证方式

| AC | 方式 |
|---|---|
| AC-1 静默边界 | 未配置 DC 项目 + 已配置 DC 项目各发普通消息/纯文本含 DC 名字消息 → `agent_task_queue` 零增量（DB 级，沿 CR-2026-009 AC-3 口径复验） |
| AC-2 激活与可见输出 | @DC → 任务入队（AskOnly=true 断言）→ 完成 → discussion 容器出现 agent comment，双浏览器实时可见；含 trivial 输出边界用例（DD-4 豁免生效仍落 comment）；审计：任务 work_dir 无写入、checkout 被拒（health_test 形态） |
| AC-3 路由 | DC 输出 @团队Agent → chat 容器出现路由 comment + 任务，Team Agent 面可见并执行；满队场景 → discussion 容器出现 system comment（DD-6） |
| AC-4 合并转发 | 多选 N 条 → 预览含三段结构 → 确认 → chat 容器 1 comment + 1 task，claim 到的 TriggerCommentContent 含完整合并结构；取消退出多选零副作用；429 → 预览保留 |
| AC-5 升级 CR | register_cr=true → comment 含指令块 → Team Agent 执行 requirement-register → knowledge-base 仓出现合规 CR 壳（cr.md + _backlog 条目）、回报 CR-ID；register_cr=false / 已有在途 gate 默认不勾 → 无指令块 |
| AC-6 解耦锁定 | §5.4 静态+行为双断言；既有 chat-input 测试全绿 |
| AC-7 回填 | 两面附件上传/渲染、@列表仅成员、富文本；跨项目跨模式草稿/附件隔离（project-chat-store key 断言 + 真机） |
| AC-8 回归 | parity 全绿；CR-D Discussion / CR-A Team Agent / CR-C Private Ask / 浮窗全页 chat 回归；presenter 与容量守卫回归（merge-forward 走同链路） |


---

## 治理工具链 — 状态推进单写 cr.md 技术设计（v0.20 · CR-2026-018）

> 输入：`change-requests/CR-2026-018/prd.md`（FR-1~9 / AC-1~10）。
> 本设计基于对 `tools/skills/shared/crctl/scripts/crctl.mjs`（1305 行）与全部 skill 文档的实地盘点，所有行号均为当前 tools 包实测值。

### 0. PRD 事实基线修正（纪律 #4 revision）

PRD §1.3 断言"适配器读取路径均经 crctl 子命令，随 crctl 升级自然切换"。实测**不完全成立**：

- claude-code 适配器的 `adapters/claude-code/hooks/inject-cr-status.mjs` 为保持轻量**不依赖 crctl 主程序**，直接行级扫描 `_backlog.yml` 的 `id`/`status`/`updated-at` 行（该文件 :28-:47）。状态字段撤出 `_backlog.yml` 后此 hook 会将所有 CR 读成 `status='?'`。
- CI 适配器（`adapters/ci/cr-guard.template.yml`）确实全部经 `crctl validate`/`crctl gate`，随 crctl 升级自然切换，无需改动。

**影响**：FR-8 范围从"仅回归验证"扩为"修改 inject-cr-status.mjs + 双适配器回归"。PRD 结论（适配器需同版本发布）不受影响，反而强化。

### 1. 架构概览

#### 1.1 现状（改造前）

```
写路径（唯一合法写入 = crctl advance, cmdAdvance :796）
  :814 updateBacklogStatus(:674)  → _backlog.yml 条目 status+updated-at 行   [权威]
  :815 updateCrMdStatus(:708)     → cr.md frontmatter status+updated-at      [尽力写，失败仅返回 {updated:false, why}]

读路径（5 处，全部经 loadBacklogEntry(:334) 取 entry.status）
  cmdStatus  :766   cmdAdvance :800   cmdApprove :857（级联再读 :919）   cmdNext :1140
旁路读（不经 crctl）
  inject-cr-status.mjs 行扫 _backlog.yml
  16 个 skill 文档指示 Agent 读 backlog[].status（清单见 §6 FR-6）
```

#### 1.2 目标（改造后）

```
写路径
  cmdAdvance → updateCrMdStatus（升级为硬失败：cr.md 缺失/无 frontmatter → fail CR_MD_WRITE_FAILED）
  updateBacklogStatus() 整函数删除（唯一调用点 :814 移除）

读路径（新增单一收敛点）
  resolveCrState(ws, cr)  ← 5 处 cmd* 统一改调此函数
    ├─ loadBacklogEntry(ws, cr)      # 继续提供注册字段：owners / merge-commits / prd-path …
    └─ readCrMdStatus(ws, cr)        # 新增：cr.md frontmatter status（权威）
       └─ fallback: entry.status + legacySource=true   # 迁移期兼容读（FR-2）

旁路读
  inject-cr-status.mjs：backlog 行扫只取 id 清单 → 逐 CR 读 cr.md frontmatter status（cr.md 缺失时回退 backlog 行值）
  16 个 skill 文档：读 status 的段落改指向 cr.md（§6）
```

**核心不变量**：`_backlog.yml` 文件继续存在（workspace 探测锚点 :289 不动）；状态机语义零变更（NFR-1）；CAS 写保护与审计日志（auditLog :358）不动。

### 2. 数据模型

#### 2.1 cr.md frontmatter（权威状态载体，字段不变、权威性升级）

`status` / `updated-at` 语义不变。变化仅在写入契约：`updateCrMdStatus` 从"尽力写"升级为"权威写"——cr.md 不存在、无 frontmatter、CAS 冲突均硬失败，advance 整体中止不写任何文件（保持"任何校验失败都不写文件"的既有承诺）。

#### 2.2 `_backlog.yml` 条目 schema v2（注册索引）

```yaml
# 保留（注册与里程碑字段，低频写）
- id, title, summary, owner, owners{...}, owner-history[], handover-history[]
  target-version, source, prd-path, submitter, reviewer, opened,
  created, updated, remote-ref, last-push-at, last-push-by,
  merge-commits[], merge-recovery, archived-at, writeback_spec_id
# 移除（撤出权威地位，由迁移命令物理删除）
- status        # → cr.md frontmatter
- updated-at    # → cr.md frontmatter（每次 advance 都写，是与 status 同级的冲突源）
```

顶层 `schema` 字段从 `cr-backlog/v1`（或缺省）升为 `cr-backlog/v2`，供 `validate` 与兼容读判别布局代际；无 `schema` 或 v1 视为旧布局。

#### 2.3 迁移报告（`crctl migrate-backlog` 产物）

```yaml
# change-requests/{workspace 根}/.crctl/migrate-backlog-report.yml（gitignore 内，审计用）
migrated-at: ISO-8601
entries: [{ id, status-at-migration, consistent: true }]
removed-lines: N
schema: cr-backlog/v1 -> cr-backlog/v2
```

**决策（评审 suggestion #2）**：迁移报告**保持 gitignored**，与既有 `.crctl/audit.log` 约定一致——迁移是一次性运维动作而非 CR 交付物，不进 specs 追溯链。库内可追性由迁移 commit message 承载：`[cr] migrate backlog to v2: {N} entries, status->cr.md`（携带条目数与 schema 版本摘要），不额外将报告文件入库。

### 3. 接口契约

#### 3.1 crctl 子命令行为变化

| 子命令 | 变化 | 输出变化 |
|---|---|---|
| `status` | 状态源 cr.md 优先；检测到混版布局时告警（见 §3.2 `MIXED_LAYOUT_WARN`） | `source` 增加 `crMd: <path>`；回退时增加 `legacySource: "_backlog.yml"` 顶层标记；混版时增加 `warnings: [MIXED_LAYOUT_WARN]` |
| `advance` | 只写 cr.md；前置读走 resolveCrState | `files[]` 只含 cr.md；commit 涉及文件减半 |
| `gate` | 读路径切换，校验逻辑不变 | 无 |
| `approve` | 前置读与级联 advance 随之切换 | 无 |
| `next` | 读路径切换 | 无 |
| `validate` | `_backlog.yml`：v2 条目**不得**含 status/updated-at（含则报 `LEGACY_STATUS_FIELD` 告警）；v1 条目若 status 与 cr.md 不一致报漂移告警（迁移期退出码 0，AC-3） | errors/warnings 分级输出 |
| `migrate-backlog`（新增） | 见 §4.3 | 迁移报告 + 结构化 JSON |

#### 3.2 错误码增量

| 错误码 | 触发 | 级别 |
|---|---|---|
| `CR_MD_WRITE_FAILED` | advance 时 cr.md 缺失/无 frontmatter/CAS 冲突 | fatal（原样保留 `CAS_CONFLICT` 细分） |
| `CR_MD_STATUS_MISSING` | 新布局（backlog v2）下 cr.md 也无 status——无处可读 | fatal |
| `LEGACY_STATUS_FIELD` | v2 schema 但条目仍含 status 行 | warning |
| `MIGRATE_STATUS_MISMATCH` | 迁移预检发现 backlog 与 cr.md 状态不一致 | fatal，不写文件 |
| `MIXED_LAYOUT_WARN` | `status` 命令检测到混版布局迹象：cr.md 与 backlog 双写且不一致、或走了 legacySource 回退（提示 workspace 可能被新旧 crctl 混用，旧版读 v2 布局会静默把 status 读空） | warning（退出码 0，不阻断只读命令） |

#### 3.3 兼容读弃用时间线（评审 suggestion #2 落实）

回退路径标记 `deprecated since v0.2.0`；计划 v0.3.0 移除（至少间隔一个完整 CR 生命周期，NFR-4）。移除时 `CR_MD_STATUS_MISSING` 从回退改为直接抛出。

### 4. 关键算法与流程

#### 4.1 resolveCrState（新增，5 个读取点的唯一收敛）

```js
function resolveCrState(ws, cr) {
  const snap = loadBacklogEntry(ws, cr);            // 注册字段 + CAS snapshot（保留原样）
  const md = readCrMdFrontmatter(ws, cr);            // 纪律#1：先 \r\n→\n，无 frontmatter 返回 null
  if (md && md.status) return { snap, status: md.status, statusSource: 'cr.md' };
  if (snap.entry.status)                             // 迁移期兼容读（FR-2，deprecated）
    return { snap, status: snap.entry.status, statusSource: '_backlog.yml', legacySource: true };
  fail('CR_MD_STATUS_MISSING', `${cr} 在 cr.md 与 _backlog.yml 中均无 status`);
}
```

冲突裁决：cr.md 与 backlog **都有** status 且不一致时，cr.md 胜（权威），不报错——漂移检测归 `validate`（读路径报错会把只读命令变成门禁，越权）。

#### 4.2 advance 写路径（cmdAdvance :810-:816 段改造）

```js
// 删除：updateBacklogStatus(ws, cr, flags.to, snap);
const crmd = updateCrMdStatus(ws, cr, flags.to);     // 升级：内部所有 {updated:false} 分支改为 fail('CR_MD_WRITE_FAILED', why)
// result.files = [crmd.path]；standalone commit 的 add 范围从 'change-requests' 收窄为 'change-requests/{cr}/cr.md'
```

顺带修正：现 standalone 模式 `git add change-requests`（:820）会把工作区内**无关未暂存变更**一起提交——收窄为精确路径，属本次改造的既有隐患修复。

#### 4.3 migrate-backlog（新增子命令）

```
1. 读 _backlog.yml（CAS snapshot），逐条目：
   - 读对应 cr.md frontmatter status
   - entry.status 缺失 → 跳过（已迁移）
   - cr.md 无 status 或与 entry.status 不一致 → 收集差异
2. 差异非空 → fail('MIGRATE_STATUS_MISMATCH', 差异清单)，不写任何文件（纪律#1 硬失败，禁止静默取一侧）
3. 全一致 → 行级定点删除各条目 status:/updated-at: 行（复用 updateBacklogStatus 的条目定位算法 :678-:690），
   顶层 schema 升 v2，CAS 写回；写迁移报告；standalone commit "[cr] migrate backlog to v2 (status -> cr.md)"
```

幂等：v2 + 无 status 行时输出 already-migrated，退出码 0。

#### 4.4 inject-cr-status.mjs 改造

保持"轻量、零依赖、失败静默放行"定位：行扫 `_backlog.yml` 只取 `id` 清单；逐 id 读 `change-requests/{id}/cr.md` 前 60 行扫 frontmatter `status:` 行（复用其现有退化扫描模式）；cr.md 读不到时回退 backlog 行值（旧布局兼容）；终态过滤逻辑不变。注入文案中的数据源说明从 `_backlog.yml` 改为 `cr.md`。

#### 4.5 端到端验证流程（AC-9）

```
fixture workspace → 注册 CR-X（分支）推进 3 次状态 → master 侧注册 CR-Y（写 _backlog 新条目）
→ git merge-tree --write-tree master branch 对 _backlog.yml 零冲突断言（CR-X 的推进只碰 cr.md；CR-Y 的注册在 master 单侧）
```

### 5. 技术选型与替代方案

| 决策 | 选择 | 否决的替代 | 理由 |
|---|---|---|---|
| 权威状态载体 | cr.md frontmatter | 每 CR 独立 status.yml | cr.md 已有字段 + 写入函数（:708），零新文件零新 schema；status.yml 引入第三个副本 |
| _backlog.yml 去留 | 保留为注册索引 | 删除、改由目录扫描 | workspace 探测锚点（:289）+ owners/merge-commits 等注册字段需要一个索引家；删除波及 31 处文档引用而非 16 处 |
| 冲突消除层 | 数据布局（撤出高频字段） | git union merge driver / .gitattributes | merge driver 平台绑定（每 clone 手工配置、Windows 差异）、YAML 语义盲，且 rebase 场景不完全生效 |
| 状态提交位置 | 保持 CR 分支 | 状态统一在 master 单侧提交 | 门禁证据（review-annotations/test-report）在 worktree 分支上，跨 checkout 读写把单命令事务拆成两仓协调，复杂度不成比例 |
| 兼容策略 | 运行时回退读 + 显式迁移命令 | 一刀切、首次运行自动迁移 | 多 workspace 分批迁移需要窗口期；自动迁移在只读命令里做写操作违反最小惊讶 |

### 6. FR 到技术实现映射

| FR | 实现位点 | 变更类型 |
|---|---|---|
| FR-1 advance 单写 | crctl.mjs :814 删调用、:674-:705 删函数、updateCrMdStatus 硬失败化、:820 add 范围收窄 | 代码 |
| FR-2 兼容读 | 新增 resolveCrState + readCrMdFrontmatter；:766/:800/:857/:919/:1140 五处改调；cmdStatus 增混版检测输出 `MIXED_LAYOUT_WARN`（缓解旧版 crctl 读 v2 布局静默读空的运维风险，与 §7 残余风险呼应） | 代码 |
| FR-3 注册索引 schema v2 | validate（:1018-:1024 段）条目规则调整 + `LEGACY_STATUS_FIELD` 告警 | 代码 |
| FR-4 探测不变 | :289 无改动（回归断言覆盖） | 仅测试 |
| FR-5 迁移命令 | 新增 cmdMigrateBacklog + CLI 帮助（:1235 段） | 代码 |
| FR-6 skill 文档修订（**17 个**消费 status；另 14 个仅引用路径不改） | cr-archive（Step 3 条目移动以 cr.md final-status 为准）、cr-dashboard（状态分组改扫 cr.md）、cr-inbox、cr-review-record、cr-status-set（契约描述）、approve-code / approve-dev-start / approve-tech-design / approve-requirement（前置读描述）、analyze-current-product、focus-briefing、requirement-register（**注册时新条目不再写 status/updated-at 字段，status 只落 cr.md**）、review-alignment、crctl SKILL.md、spec-dashboard、merge-feature-branch（Step 5 embedded patch 只落 cr.md，merge-commits[] 仍写 _backlog）、**list-remote-checkpoints**（Step 2 消费字段改读各 CR 的 cr.md status，`filter_status` 参数与输出"状态"列语义不变，仅数据源切换；task-breakdown 阶段核实补入，原 SDD 评审时的 16 项盘点遗漏此项） | 文档 |
| FR-7 状态机声明 | tools/dir-graph.yaml :210 `scope` 改为 `change-requests/{CR-ID}/cr.md`；gates.json 实测无 backlog 引用，不动 | 文档 |
| FR-8 适配器 | inject-cr-status.mjs 改造（§4.4，PRD 假设修正见 §0）；CI 模板零改动 + 双适配器 fixture 回归 | 代码 + 测试 |
| FR-9 归档流 | cr-archive 移动条目逻辑保持；final-status 读取源改 cr.md（并入 FR-6 文档修订） | 文档 |

测试增量（AC-10）：现有 21 个用例全绿为回归线；新增 ≥7：单写 diff 断言（AC-1）、新旧布局双向读（AC-2）、validate 三态（AC-3）、迁移成功/失败/幂等（AC-5）、merge-tree 零冲突端到端（AC-9）、cr.md 缺失硬失败（CR_MD_WRITE_FAILED）、混版布局告警（AC-11）。

**AC-11（对应 FR-2 混版检测）**：构造 cr.md 与 backlog status 双写且不一致的 workspace，`crctl status` 以 cr.md 值为准返回，且输出 `warnings` 含 `MIXED_LAYOUT_WARN`、退出码为 0；构造纯 v2（backlog 无 status、cr.md 有）workspace，`status` 无该告警。

### 7. 安全与性能考量

- **原子性**：advance 从双文件写收敛为单文件写 + CAS，部分写入窗口消失；`CR_ARCHIVE_STATUS_SYNC_FAILED` 类双写不一致错误场景整类消亡。
- **单一写入路径不破坏**：迁移命令与 advance 同经 CAS + 审计日志 + controlledGit 白名单提交，不开旁路（与 P2 的 crctl 子命令化方向一致）。
- **性能**：resolveCrState 每次多读一个 cr.md（数 KB），单 CR 命令无感；cr-dashboard 全量扫描从 1 文件变 N+1 文件（N=在途 CR 数，实测 <20），仍为毫秒级。
- **行尾纪律**：readCrMdFrontmatter 与迁移的行级删除全部先 `\r\n→\n` 规范化、`split(/\r?\n/)`、解析失败硬报错（纪律 #1）；updateCrMdStatus 现有实现已合规，沿用。
- **回滚**：改造本身可整体 revert（crctl 单文件 + 文档）；迁移命令产生的 v2 布局回滚 = revert 迁移 commit，无数据丢失（status 在 cr.md 始终存在）。
- **残余风险**：迁移窗口期内新旧 crctl 混用同一 workspace（旧版仍写 backlog）会重新引入双写——迁移后 v2 schema 会让旧版 `updateBacklogStatus` 定位不到 status 行而硬失败（`BACKLOG_SHAPE` :692），风险自限，但发布说明需明示"迁移后必须统一 crctl 版本"。
## 治理工具链 — YAML 账本操作收敛为 crctl 子命令 技术设计（v0.20.1 · CR-2026-019）

## SDD — YAML 账本操作收敛为 crctl 子命令（P2）+ AC-9 演练入库

### 0. 事实基线（已核实，纪律 #4）

| 事实 | 位置 | 对设计的影响 |
|---|---|---|
| 单文件 CAS 原语 `casWrite(p, expectedHash, newText)`：读→sha256 比对→写，不一致 `CAS_CONFLICT` | `crctl.mjs:667` | 三个子命令的单文件写直接复用 |
| YAML 写入范式 = **定向正则替换指定行**（无序列化器）；`updateCrMdStatus` 即样板 | `crctl.mjs:674-687` | 账本编辑一律行级正则改写 + CAS，匹配不到硬失败（纪律 #1） |
| `auditLog(ws, record)` 追加 JSON 行到 `.crctl/audit.log` | `crctl.mjs:358-364` | 三子命令统一留审计 |
| `loadBacklogEntry` 返回 `{entry, text, hash, path}`，hash=全文 sha256 | `crctl.mjs:334-344` | 直接作为 backlog 写入的 CAS expectedHash |
| outbox 原子写 = temp 文件 + rename | `crctl.mjs:397-399` | archive-move 双文件写沿用 temp+rename 收窄崩溃窗口 |
| dispatch 分发在 `main()` switch | `crctl.mjs:1419-1431` | 新增三个 case |
| `tasks/_index.yml` 结构：`tasks: [{id,title,status,estimate,depends-on}]` | `change-requests/*/tasks/_index.yml` | task done 按 id 锚定块内 `status:` 行改写 |
| **`merge-commits[]` 是结构化条目 `{repo, trunk, sha}`，非裸 sha** | `_backlog.yml:56-59` | **修订 PRD FR-2**：入参细化为 `--repo/--trunk/--sha`；PRD"追加进 merge-commits[]"意图不变，结论不受影响 |
| `_history.yml` 顶层 `history: [...]`，条目含 `final-status/archive-reason/writeback-spec-id/archived-at` | `_history.yml` | archive-move 追加富化条目到 history[]、从 backlog 删除同 id 块 |

### 1. 架构概览

#### 1.1 模块边界

三个子命令全部落在 `crctl.mjs` 单文件内，**不新增文件、不建脚本库**（PRD FR-4）。新增一层"账本写入原语"，位于现有 CAS/审计原语之上、dispatch 之下：

```
main() dispatch (:1419)
  ├── case 'task'          → cmdTaskDone(ws, cr, flags)      ─┐
  ├── case 'merge-metadata'→ cmdMergeMetadata(ws, cr, flags) ─┤ 新增
  └── case 'archive-move'  → cmdArchiveMove(ws, cr, flags)   ─┘
                                    │
              ┌─────────────────────┼─────────────────────┐
      ledger 编辑纯函数        casWrite / casWriteMulti      auditLog
      （行级正则，纯 string→string） （复用 :667 + 新增多文件）  （复用 :358）
```

#### 1.2 单一写入路径不变量（PRD FR-4 / NFR-3）

- **状态写入**唯一入口仍是 `advance`（纪律 #5 不变）——三个子命令**不改 CR status、不发 status 事件**，只做账本编辑。
- **账本写入**收敛为这三个子命令：任何对 `tasks/_index.yml` status / `_backlog.yml` merge-commits / backlog↔history 的写入，改造后都过 CAS + 审计，会话内手写/现写脚本被工具层根除（PRD FR-6 由文档强制）。
- 每个子命令 = 前置态守卫（precondition，不是状态转移）→ 行级编辑纯函数 → CAS 写 → 审计。

#### 1.3 关键流程

```
cmdX(ws, cr, flags):
  1. resolveCrState(ws, cr)            # 读权威状态（复用 :704）
  2. 守卫：status ∈ 合法前置态集合？   # 否 → fail(ILLEGAL_LEDGER_STATE, 当前态/期望态)
  3. 读目标账本文件 text + hash        # readFileChecked + sha256
  4. newText = editPure(text, ...)     # 行级正则；匹配不到 → fail（硬失败，纪律 #1）
  5. casWrite(path, hash, newText)     # 单文件；archive 用 casWriteMulti
  6. auditLog(ws, {kind:'ledger', op, cr, before, after})
  7. ok({...})                         # 不发 status outbox 事件
```

### 2. 数据模型

不新增持久化实体，只编辑既有三类账本文件的既有字段。

| 文件 | 编辑字段 | 编辑语义 |
|---|---|---|
| `change-requests/{cr}/tasks/_index.yml` | `tasks[].status`，追加 `tasks[].done-at` | pending→done + 时间戳 |
| `change-requests/_backlog.yml` | 条目 `merge-commits[]` | 追加 `{repo,trunk,sha}`，按 sha 去重保序 |
| `change-requests/_backlog.yml` + `_history.yml` | 条目整体移动 | backlog 删块 + history 追加富化块（+final-status/archived-at） |

审计记录（`.crctl/audit.log` 追加行）字段：`{at, kind:'ledger', op:'task-done'|'merge-metadata'|'archive-move', cr, actor, before, after}`；`before/after` 为受影响字段摘要（如 task-done 记 `{taskId, from:'pending', to:'done'}`），不含全文。

### 3. 接口契约

CLI 契约（`--workspace` 沿用全局探测，`crctl.mjs:281`）：

```
crctl task done <CR-ID> --task <TASK-ID> [--workspace <dir>]
  前置态: developing（开发中）
  行为  : tasks/_index.yml 中 <TASK-ID> status pending→done + done-at
  错误  : TASK_NOT_FOUND | TASK_ALREADY_DONE | ILLEGAL_LEDGER_STATE

crctl merge-metadata <CR-ID> --repo <r> --trunk <t> --sha <sha> [--workspace <dir>]
  前置态: merging | writing-back（合并/回写期）
  行为  : _backlog.yml 条目 merge-commits[] 追加 {repo,trunk,sha}，sha 去重
  错误  : MERGE_COMMIT_DUP（同 sha 已存在，幂等返回 ok 不重复写）| ILLEGAL_LEDGER_STATE

crctl archive-move <CR-ID> --final-status <status> [--archive-reason <s>] [--spec-id <id>] [--workspace <dir>]
  前置态: archived（advance 已把状态推到 archived 后调用）
  行为  : 原子地 _backlog.yml 删条目 + _history.yml 追加富化条目
  错误  : ENTRY_NOT_IN_BACKLOG | ENTRY_ALREADY_IN_HISTORY | CAS_CONFLICT | ILLEGAL_LEDGER_STATE
```

出参统一 `ok({op, cr, ...摘要})`；失败走既有 `fail(code, message)`（非零退出，`crctl.mjs:29`）。

### 4. 关键算法与流程

#### 4.1 task done — 块内锚定行替换（单文件 CAS）

```js
function editTaskDone(text, taskId) {
  const norm = text.replaceAll('\r\n', '\n');            // 纪律 #1 行尾规范化
  // 锚定 "- id: <taskId>" 起到下一个 "  - id:" 或 EOF 的块
  const block = matchTaskBlock(norm, taskId);
  if (!block) fail('TASK_NOT_FOUND', `${taskId} 不在 tasks/_index.yml`);
  if (/^\s*status:\s*done\b/m.test(block.text)) fail('TASK_ALREADY_DONE', taskId);
  // status 行替换与 done-at 插入一次完成：replace 回调直接产出两行（同缩进）
  let hit = false;
  const nb = block.text.replace(/^(\s*)status:\s*\S.*$/m, (_, indent) => {
    hit = true;
    return `${indent}status: done\n${indent}done-at: "${nowIso()}"`;
  });
  if (!hit) fail('TASK_INDEX_SHAPE', `${taskId} 块内无 status 行`);   // 匹配不到硬失败（纪律 #1）
  return norm.slice(0, block.start) + nb + norm.slice(block.end);
}
```
> matchTaskBlock 用块锚定正则；**匹配失败硬失败**，禁止静默返回原文（纪律 #1，T04 教训）。

#### 4.2 merge-metadata — 幂等追加结构化条目（单文件 CAS）

```
1. loadBacklogEntry(ws, cr) → {entry, text, hash}
2. 若 entry.merge-commits 已含相同 sha → ok(MERGE_COMMIT_DUP 幂等，noop 返回)
3. 定位条目的 merge-commits: 块；无则在条目内创建该键
4. 在块尾按缩进插入 "- repo/trunk/sha" 三行
5. casWrite(backlogPath, hash, newText)  # hash 来自 loadBacklogEntry
```
去重键 = sha；保序追加（不排序，保留合并时间序）。

#### 4.3 archive-move — 双文件原子写（新增 casWriteMulti）

```js
function casWriteMulti(writes) {           // writes: [{path, expectedHash, newText}]
  for (const w of writes)                  // 阶段一：全部 CAS 校验
    if (sha256(readFileChecked(w.path)) !== w.expectedHash)
      fail('CAS_CONFLICT', w.path);
  const staged = writes.map(w => {         // 阶段二：全部写 temp
    const tmp = w.path + `.tmp-${process.pid}`;
    fs.writeFileSync(tmp, w.newText, 'utf8'); return { tmp, dst: w.path };
  });
  for (const s of staged) fs.renameSync(s.tmp, s.dst);  // 阶段三：连续 rename
}
```

archive-move 流程：
```
1. 守卫 status===archived
2. 读 _backlog.yml(text_b,hash_b) + _history.yml(text_h,hash_h)
3. entryBlock = 从 backlog 抽取 "- id: {cr}" 块（抽不到→ENTRY_NOT_IN_BACKLOG）
4. history 已含 {cr} → ENTRY_ALREADY_IN_HISTORY（防重复归档）
5. newBacklog = 删除该块；newHistory = history[] 追加富化块
        （原块缩进下沉一级 + final-status/archive-reason/writeback-spec-id/archived-at）
6. casWriteMulti([{backlog,hash_b,newBacklog},{history,hash_h,newHistory}])
7. auditLog(op:'archive-move', before/after 摘要)
```

> **残余窗口（ponytail 天花板）**：casWriteMulti 的两次 rename 之间若进程崩溃，留 backlog 已删、history 未写的半状态。缓解：① rename 窗口为微秒级；② 账本变更随 `--embedded` 进同一 git 提交，工作树可 `git checkout` 回滚；③ 单写者不变量（纪律 #5）下无并发 crctl。判定为可接受天花板，不引入 WAL/两阶段提交（YAGNI）。升级路径：若未来出现并发写者，改文件锁。

### 5. 技术选型与替代方案

| 决策点 | 选型 | 替代方案与否决理由 |
|---|---|---|
| 账本写入落点 | crctl 子命令 | ❌ 独立脚本库（`tools/skills/shared/scripts/`）——复盘明确否决：开第二写入通道绕开 CAS/审计/门禁，长期必然漂移（PRD §7） |
| YAML 编辑方式 | 行级定向正则 + CAS | ❌ 引入 YAML 序列化库——新依赖（违 NFR-4）、且全量重排会打乱注释/字段序、扩大 diff 面；沿用 `updateCrMdStatus` 既有范式 |
| 双文件原子性 | casWriteMulti（全校验→全 temp→连续 rename） | ❌ WAL / 事务日志——对单写者场景过度设计（YAGNI）；❌ 直接顺序 casWrite×2——窗口更大 |
| 状态职责 | 三子命令不改 status，仅账本 | ❌ 让 archive-move 兼做 advance→archived——破坏 advance 单一状态写者不变量（纪律 #5） |

### 6. FR 到技术实现映射

| FR | 技术实现 | 覆盖 |
|---|---|---|
| FR-1 task done 子命令 | §4.1 `editTaskDone` + case 'task' 分发 + casWrite | ✅ |
| FR-2 merge-metadata 子命令 | §4.2（入参细化为 `--repo/--trunk/--sha`，见 §0 修订） | ✅ |
| FR-3 archive-move 子命令 | §4.3 + casWriteMulti 双文件原子 | ✅ |
| FR-4 单一写入路径不变量 | §1.2 复用 casWrite/casWriteMulti/auditLog，无独立脚本、零新依赖 | ✅ |
| FR-5 门禁与非法调用防护 | §1.3 步骤 2 前置态守卫 + `fail(ILLEGAL_LEDGER_STATE,...)`；缺参/CR 不存在/workspace 失败均硬失败 | ✅ |
| FR-6 skill 文档同步 | implement-code / merge-feature-branch / cr-archive 三 SKILL.md 改调子命令 + 明文禁手写（文档改动，随 TASK 落地） | ✅ |
| FR-7 AC-9 演练入库 | §7.2 固化为 crctl.test.mjs node:test 用例 | ✅ |

### 7. 安全与性能考量

#### 7.1 边界与正确性

- **行尾纪律（纪律 #1）**：所有 edit 纯函数读入先 `replaceAll('\r\n','\n')`；块锚定/字段定位正则**匹配不到一律 fail**，禁止静默返回原文（直接对标 T04"匹配不到→空数组→静默丢数据"）。
- **幂等**：merge-metadata 同 sha、task done 已 done、archive-move 已在 history —— 均检测并给确定性结果（幂等 ok 或专用错误码），不产生重复/破坏写。
- **前置态守卫**引用状态机唯一事实源判断合法态（`../tools/dir-graph.yaml`），本 CR **不复刻**状态机声明（禁止事项）。
- **审计完整性**：每次账本写入前后摘要落 `audit.log`，可追溯 actor/时间/字段变更。

#### 7.2 测试设计（含 AC-9 入库，FR-7）

新增 `skills/shared/crctl/scripts/test/crctl.test.mjs` 用例（node:test，无框架，临时目录 fixture）：

| 用例 | 覆盖 AC | 断言 |
|---|---|---|
| task-done 正常/不存在/已done | AC-1 | status=done+done-at；后两者非零退出且文件无变更 |
| task-done 非法前置态 | AC-5 | fail(ILLEGAL_LEDGER_STATE)，无写 |
| merge-metadata 追加/去重 | AC-2 | merge-commits[] 含 {repo,trunk,sha}；重复 sha 不新增 |
| archive-move 正常 | AC-3 | 条目从 backlog 消失、history 出现带 final-status |
| archive-move history 侧 CAS 冲突 | AC-3 | CAS_CONFLICT 且**两文件均无变更** |
| archive-move 非法前置态 | AC-5 | fail，无写 |
| **AC-9 merge-tree 零冲突**（固化 `_scratch/patch-task10b.mjs` 演练） | AC-7 | 共同祖先注册→分支推 ≥3 次 cr.md→master 注册新 CR→`git merge-tree --write-tree` 对 `_backlog.yml` 冲突数=0、exit 0 |

回归：既有套件（基线 32 用例，CR-018 定型）保持全绿（AC-8）。

#### 7.3 性能

账本文件均为 KB 级、条目数十量级；全量读+正则改写+写回单次 <10ms，无性能约束。casWriteMulti 仅两文件，rename 为文件系统元数据操作，可忽略。

## 治理工具链 — writeback 机械步骤固化为入库脚本（v0.21 · CR-2026-020）

## SDD — writeback 机械步骤固化为入库脚本

### 0. 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| `tools/ARCHITECTURE.md` §6 否决记录："独立**账本操作**脚本库（如 `tools/skills/shared/scripts/`）"——否决对象是账本写入第二通道，但字面点名了 PRD FR-4 拟用的路径 | `tools/ARCHITECTURE.md` §6 第一行 |
| `crctl.mjs` 刻意单文件（1636 行），顶层直接执行 `main()`，无任何 `export`——改造成可导入库需要加 `import.meta` 守卫等结构手术，正是 §3 警告的拆分 | `tools/ARCHITECTURE.md` §3；`crctl.mjs:1636`（`main();`） |
| crctl 自身脚本布局先例：`skills/shared/crctl/scripts/`（skill 组目录内挂 scripts/） | `tools/skills/shared/crctl/` 目录结构 |
| **specs 侧 traceability.yml 是跨 CR 累积文件**（989 行，`milestones[]` 每 CR 一段）：`fr-chain` 的 `sdd:`/`code:` 为编辑性措辞，头部含手工缺口注释（CR-2026-003~006 历史段缺失、无法回填）——**不可全量重建** | `specs/ai-first-platform/traceability.yml` 头部注释与 milestones 结构 |
| `_backlog.yml` 注册条目的 `merge-commits[]` 结构：`repo/trunk/sha/branch/source-sha/merged-at` 六字段列表 | `change-requests/_backlog.yml`（CR-2026-007/008 条目实测） |
| `delivery/task/_index.yaml` 条目七字段（id/file/title/status/cr-ref/target-version/estimate）全部可从 `delivery/task/*.md` frontmatter 与文件名投影——**可全量重建** | `delivery/task/_index.yaml` + 任一 TASK 文件 frontmatter |
| `specs/_index.yml` 的 `features[].brief` 为逐版本累积人工长文、`current` 为编辑字段——只能结构化字段更新，不可重建（PRD §1.3 已核实） | `specs/_index.yml` |
| feature-writeback pipeline 四处 prompt 需同步改：node-2（备份指引）、node-3（作废命名 `TASK-{ver}-{NNN}-{NN}`）、node-4（"与 change-requests 侧保持一致"+作废命名示例） | `tools/pipeline-templates/feature-writeback.pipeline.json` |
| 本 CR 目标代码仓 = tools 仓自身（改 `tools/skills/**`），按 write-tech-design SKILL 例外条款，`tools/ARCHITECTURE.md` 是正确的架构判据 | write-tech-design SKILL Step 1 |

### 1. 架构概览

#### 1.1 模块边界与落点

```
tools/skills/writeback/
├── writeback-prd-sdd/SKILL.md        # 改调：调脚本 + 核对 dry-run diff + 事实基线段
├── writeback-tasks/SKILL.md          # 同上
├── writeback-traceability/SKILL.md   # 同上
└── scripts/                          # ★ 新增（本 CR 唯一新代码目录）
    ├── writeback-prd-sdd.mjs
    ├── writeback-tasks.mjs
    ├── writeback-traceability.mjs
    ├── lib.mjs                       # 三脚本公用：CRLF 归一/frontmatter 读改/锚点断言/dry-run diff/fail
    └── test/writeback.test.mjs       # node --test 自检（NFR-6/AC-8）
```

依赖方向（与 ARCHITECTURE.md §4 一致，脚本层与 crctl 平行、互不依赖）：

```
Pipeline(feature-writeback) → SKILL(writeback/*) → scripts/*.mjs → specs/ + delivery/ 内容文件（写）
                                                 └→ change-requests/_backlog.yml 等账本（只读）
账本写入仍唯一经 crctl（本 CR 不触碰）
```

#### 1.2 架构冲突消解（评审重点，先于一切设计决策）

PRD 与 `tools/ARCHITECTURE.md` 存在三处冲突/事实偏差，本节逐条消解；**详细偏差记录与理由见 §8**：

1. **落点路径**：不用 PRD FR-4 字面路径 `skills/shared/scripts/`（§6 否决条目点名路径，且共享桶目录诱发账本脚本蔓延），改用 `skills/writeback/scripts/`——与 crctl 自身 `skills/shared/crctl/scripts/` 布局对称，按组内聚、目录名即边界。
2. **不抽取 crctl 函数**：FR-4 的"如需抽取 shared 模块"判定为**不需**。crctl.mjs 顶层执行 `main()` 且零导出，改造成库违反其单文件不变量；回写脚本的 YAML 需求（frontmatter 行级读改 + 定向块提取 + 全量生成）远轻于 crctl 通用解析器，由 `lib.mjs` 自带 ~100 行定向实现，与包内"行级定向、非通用序列化器"哲学一致（§6 第三条）。
3. **traceability 处理模式**：FR-3/FR-5 的"全量重建"对该文件不成立（§0 事实基线第 4 行），改为"头部结构化字段更新 + 本 CR milestone 段末尾追加"。

配套按 ARCHITECTURE.md §8 维护规则修订该文档（本 CR 范围内，随本次设计评审确认）：§3 代码地图补 `skills/writeback/scripts/` 条目（职责 + 非账本边界）；§6 否决条目补范围澄清（否决的是"账本操作"脚本库；specs/delivery 内容文件回写脚本落点收窄为 `skills/writeback/scripts/`，防蔓延，ref CR-2026-020）。

#### 1.3 关键流程（feature-writeback pipeline 改后形态）

节点 ②③④ 从"现场写脚本→调试→验证"变为统一三步：`脚本 --dry-run 核对 diff` → `脚本实跑（自带自检）` → `git commit`。节点 ①⑤ 不变（merge/archive 仍走 crctl + controlled-shell）。

### 2. 数据模型

#### 2.1 各脚本读写面

| 脚本 | 读（只读） | 写 |
|---|---|---|
| writeback-prd-sdd | `change-requests/{cr}/prd.md`、`sdd.md`；`specs/{spec}/PRD.md`、`SDD.md`；`specs/_index.yml` | `specs/{spec}/PRD.md`、`SDD.md`（末尾追加里程碑节 + frontmatter 更新）；`specs/_index.yml`（结构化字段更新） |
| writeback-tasks | `change-requests/{cr}/tasks/_index.yml`（账本，只读）、`tasks/TASK-*.md`；`delivery/task/*.md` | `delivery/task/TASK-{version}-{cr}-{NN}-{slug}.md`（新增拷贝）；`delivery/task/_index.yaml`（全量重建） |
| writeback-traceability | `change-requests/{cr}/cr.md`（只读）、`review-annotations/*.yml`、`test-report.md`；`change-requests/_backlog.yml`（账本，只读，定向提取 merge-commits[]）；`delivery/task/_index.yaml` | `specs/{spec}/traceability.yml`（头部字段更新 + milestone 段追加） |

**硬边界（NFR-5）**：三脚本对 `_backlog.yml`/`_history.yml`/`cr.md`/CR `tasks/_index.yml` 只读；lib.mjs 不提供任何指向这四类路径的写函数。

#### 2.2 文件格式契约（脚本内断言的结构）

- **PRD/SDD 里程碑节**：`## {标题}（v{version} · CR-{id}）`，节内原文 H 级整体 +1；幂等判据 = 该标题行已存在。
- **specs/_index.yml**：`features[]` 定位 `- id: {spec_id}` 块；更新 `current`/`cr-ref`/`updated`，`cr-history[]` 按 id 追加去重；`brief` 仅当 `--brief` 传入时整行替换。
- **delivery/task/_index.yaml**：全量重建。条目字段 id/file/title/status/cr-ref/target-version/estimate 全部投影自扫描 `delivery/task/*.md` 的 frontmatter 与文件名；**条目顺序 = 既有文件中已有 id 的原序 + 新增条目按 id 排序追加**（保持 diff 最小、纯增量可读）。
- **traceability.yml**：头部字段 `cr-ref`/`target-version`/`generated-at` 更新、`cr-history[]` 追加去重，**头部手工注释与既有 milestones 段逐字节保留**；本 CR milestone 段追加到文件末尾。段内 `merge-commits` 从 `_backlog.yml` 定向提取（六字段），`fr-chain` 的编辑性内容经 `--milestone-file` 由调用方（Agent 按 SKILL 起草）提供，脚本负责结构校验与放置，不臆造。
- **TASK 命名**：`TASK-{version}-{cr_id}-{NN}-{slug}`（`slug` 取 frontmatter，缺失回退 `task-{NN}`）——三处文档（pipeline node-3、traceability SKILL 示例、writeback-tasks SKILL）统一到此格式（FR-8）。

### 3. 接口契约（CLI）

三脚本统一约定（与 crctl 输出风格对齐，机器可判）：

```
node writeback-prd-sdd.mjs      --workspace <ws> --cr <CR-ID> --spec <spec_id> --version <ver> [--brief "<text>"] [--dry-run]
node writeback-tasks.mjs        --workspace <ws> --cr <CR-ID> --spec <spec_id> --version <ver> [--dry-run]
node writeback-traceability.mjs --workspace <ws> --cr <CR-ID> --spec <spec_id> --version <ver> --milestone-file <path> [--dry-run]
```

- **退出码**：0 = 成功或显式 noop（stdout JSON 含 `"noop": true` 与原因）；非 0 = 硬失败，stderr JSON 含错误码。
- **错误码**（lib.mjs `fail()`，风格同 crctl）：`BAD_ARGS` / `CR_STATUS_MISMATCH`（状态前置不符，读 cr.md 校验但不写）/ `ANCHOR_NOT_FOUND` / `ANCHOR_NOT_UNIQUE`（命中 0 或 ≥2 次，纪律 #1）/ `MERGE_COMMITS_MISSING`（不猜测、不取 trunk 最新提交）/ `STRUCTURE_MISMATCH`（_index/traceability 结构断言失败）/ `SELF_CHECK_FAILED`。
- **dry-run**：打印每个目标文件的变更 diff（旧/新片段），不落盘；实跑末尾执行自检断言（§4.4），失败即 `SELF_CHECK_FAILED` 非零退出（已写入的内容留在工作区由 git 兜底，不自动回滚——工作区未 commit，`git checkout --` 即可复原，不做补偿机制，YAGNI）。
- **状态前置**：prd-sdd 要求 cr.md status=`merging`；tasks/traceability 要求 `writing-back`（与各 SKILL 现行前置一致）。脚本只读校验，状态推进仍由 SKILL 层调 crctl。

### 4. 关键算法与流程

#### 4.1 writeback-prd-sdd

```
读 specs/{spec}/PRD.md：
  不存在 → 首次回写：整份拷贝 CR prd.md + frontmatter 补齐（spec_id/version/status/cr_ref）
  存在   → 增量：
    幂等检查：里程碑标题行已存在 → noop
    构造里程碑节：CR prd.md 去 frontmatter，正文 H 级整体 +1，冠以标题行
    追加到文件末尾（EOF 追加，无中段锚点）
    frontmatter 更新：^version:/^cr_ref: 行（首个 --- 块内，行首锚定，唯一性断言）
SDD.md 同法。specs/_index.yml：定位 "- id: {spec}" 块 → 字段行级更新 + cr-history 追加去重。
```

#### 4.2 writeback-tasks

```
扫描 delivery/task/*.md frontmatter 收集已交付 id 集合（幂等唯一判据，同 PRD FR-2；
  索引全量重建后与"索引 id 集合"等价，且对 slug 后补导致的文件名变化稳健）
读 CR tasks/_index.yml（只读）筛 status=done → 对每个任务：
  其 id ∈ 已交付集合 → 跳过（幂等，不看文件名、不比内容）
  否则拷贝 + frontmatter 闭合 --- 前插入 spec-id/version 两行
全量重建 delivery/task/_index.yaml：扫描 delivery/task/*.md frontmatter 投影七字段，
  顺序 = 既有 id 原序 + 新增按 id 排序（§2.2）
```

#### 4.3 writeback-traceability

```
定向提取 _backlog.yml 中 {cr} 条目的 merge-commits[]（块提取，六字段齐全性断言，缺失硬失败）
读 --milestone-file（Agent 起草的本 CR milestone YAML 段）→ 结构校验（cr/milestone/target-version/
  fr-chain[].fr 必填；merge-commits 由脚本注入提取结果，文件内如有则校验一致）
幂等检查：traceability.yml 已含 "- cr: {cr}" → noop
头部字段更新（行级，行首锚定）+ 注释与既有段逐字节保留 + 末尾追加 milestone 段
```

#### 4.4 自检断言（每脚本实跑末尾，NFR-3）

回读目标文件断言：里程碑标题恰出现 1 次；_index 中目标 id 恰 1 条且字段齐全；traceability 中 `- cr: {cr}` 恰 1 段且 merge-commits 数与提取结果一致；全文件无 `\r`（写出统一 LF）。失败 `SELF_CHECK_FAILED`。

#### 4.5 lib.mjs 公用函数

`normalize()`（`\r\n→\n`，纪律 #1）、`readFrontmatter()/patchFrontmatterField()`（首个 `---` 块内行级改写 + 唯一性断言）、`extractBlock()`（缩进敏感的 YAML 块定向提取，供 _backlog/_index 只读解析）、`unifiedDiff()`（dry-run 输出）、`ok()/fail()`（JSON 输出与退出码）。总量预期 ~120 行，不是通用 YAML 解析器。

### 5. 技术选型与替代方案

| 决策 | 选择 | 已否决的替代及理由 |
|---|---|---|
| 落点 | `skills/writeback/scripts/` | `skills/shared/scripts/`：§6 否决条目点名路径 + 共享桶蔓延风险（§1.2-1） |
| YAML 能力来源 | lib.mjs 自带定向实现（~120 行） | 抽取 crctl 函数：破坏单文件不变量（§1.2-2）；引入 yaml 依赖：违反零依赖不变量（§5-3）与全量重排副作用 |
| traceability 模式 | 头部更新 + 段追加 | 全量重建：摧毁不可再生的历史里程碑与手工注释（§0 第 4 行）；双份同步：FR-7 已废除 |
| 索引重建顺序 | 既有序 + 新增排序追加 | 整表重排序：diff 面扩大，评审不可读 |
| 自检失败处理 | 非零退出 + git 工作区兜底 | 自动回滚/备份：重复实现 git（FR-6 精神），YAGNI |
| 脚本组织 | 三脚本 + lib.mjs | 单文件三子命令：与 PRD FR-1/2/3 三脚本口径不符，且三节点由 pipeline 独立调用，无共享进程需求 |

### 6. FR → 技术实现映射

| FR | 实现 |
|---|---|
| FR-1 | §4.1 脚本 + `--brief` 入参；AC-1 由 test/writeback.test.mjs 断言（含 brief 落位，回应需求评审 suggestion-1） |
| FR-2 | §4.2 脚本（幂等=扫描 delivery/task/*.md frontmatter 的 id 集合，同 FR-2 字面；索引重建天然幂等） |
| FR-3 | §4.3 脚本；**偏差：全量重建→头部更新+段追加**（§8-D3） |
| FR-4 | §1.1 落点 + §5 选型；**偏差：路径与"抽取共享模块"**（§8-D1/D2）；不接 CAS/审计/门禁，账本只读 |
| FR-5 | 三类处理精化为：重建（delivery 索引）/ 结构化字段更新（specs/_index、traceability 头部）/ 锚点追加（PRD/SDD 节、traceability 段——均为 EOF 追加 + 行级 frontmatter 锚点） |
| FR-6 | writeback-prd-sdd SKILL 删 Step 2 备份与 Step 6 备份行；pipeline node-2 prompt 删备份指引；脚本不实现备份 |
| FR-7 | traceability SKILL + pipeline node-4 prompt 删"与 change-requests 侧保持一致"；CR 侧文件定位为开发期工作稿（归档后不再维护） |
| FR-8 | 三份 SKILL 改为"调脚本 + 核对 dry-run diff"+事实基线段；TASK 命名三处统一（pipeline node-3、traceability SKILL 示例、writeback-tasks SKILL 复核） |
| FR-9 | merge-feature-branch SKILL 增事实基线段（tools 仓 trunk=custom/main、空分支跳过、补 push 规则），不动合并/补偿逻辑 |

**frontmatter 合规**（需求评审 suggestion-2 落实）：脚本按 engineering-docs 模板的**字段规则**实现校验（type/spec_id/version/status/cr_ref 存在性与取值），不调用 skill。

### 7. 安全与性能考量

- **信任边界**：脚本只操作本地仓库文件，无网络、无 shell 外呼；入参 workspace/cr/spec 均做存在性校验（`BAD_ARGS`）。
- **账本保护**：账本四类文件只读（§2.1 硬边界），静态可核查（AC-4 的 grep 判据：脚本中不出现对这些路径的写调用）。
- **失败安全**：所有写落在 git 工作区，commit 前可随时复原；锚点 0/多次命中、结构断言失败、merge-commits 缺失均硬失败不落盘（写前先在内存构造全部新内容，校验通过才写文件——先验证后写，天然避免半写状态）。
- **性能**：目标文件最大 ~1000 行、任务数 <100，全部同步 I/O 一次性读写，无性能敏感点。

### 8. 与已审批 PRD 的偏差记录（供 review-tech-design 与人工审批确认）

| # | PRD 原文 | SDD 决策 | 理由 |
|---|---|---|---|
| D1 | FR-4/§1.2：落点 `tools/skills/shared/scripts/` | `tools/skills/writeback/scripts/` | 字面路径撞 ARCHITECTURE.md §6 否决记录；组内聚 + 防蔓延（§1.2-1）。FR-4 实质约束（版本化、非 crctl 子命令、零新依赖）全部保留 |
| D2 | FR-4："复用 crctl 现有 YAML 工具（如需，抽取 shared 模块）" | 不抽取；lib.mjs 自带定向实现 | "如需"条件判定为不需：crctl.mjs 单文件不变量 + 顶层 main() 不可导入；回写 YAML 需求远轻于通用解析（§1.2-2） |
| D3 | FR-3/FR-5/AC-3："traceability.yml 全量重建" | 头部字段更新 + milestone 段末尾追加 | 真实文件为跨 CR 累积（989 行、编辑性 fr-chain、手工注释、4 段历史缺口不可回填）——全量重建会摧毁历史。PRD 该表述沿袭了过时的 SKILL 描述（§0 第 4 行）。AC-3 判据等效替换为：追加后既有段逐字节不变 + 本 CR 段恰 1 处 + 幂等 noop |

配套修正（开发任务内完成）：`docs/product/writeback-流水线耗时分析与优化方案.md` §4.2 表格同错（traceability 列入"全量重建"），随本 CR 在 knowledge-base worktree 修正；三份偏差同步反映到 tools/ARCHITECTURE.md §3/§6 修订（§1.2 末段）。

### 9. 参与仓与交付物清单

| 仓 | 交付物 |
|---|---|
| tools（trunk=custom/main） | `skills/writeback/scripts/`（3 脚本 + lib + test）；3 份 writeback SKILL.md 改调；merge-feature-branch SKILL 事实基线段；`pipeline-templates/feature-writeback.pipeline.json` node-2/3/4 prompt 修订；`ARCHITECTURE.md` §3/§6 修订 |
| knowledge-base（trunk=master） | CR 产物（prd/sdd/tasks/评审记录）；`docs/product/writeback-流水线耗时分析与优化方案.md` §4.2 修正 |
| multica | 不参与（无代码改动，空分支跳过） |

## 治理工具链——prompt 对齐 crctl（v0.22 · CR-2026-021）

## SDD — prompt 对齐 crctl（写入面补齐 + prompt 收敛 + 漂移防线）

> 目标代码仓 = **tools 仓自身**（改 `crctl.mjs` / `skills/**` / `pipeline-templates/**` / `.githooks/`），按 write-tech-design SKILL Step 1 例外条款，`tools/ARCHITECTURE.md` 是本设计的权威架构判据。

### 0. 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| `crctl.mjs` 刻意单文件（ARCHITECTURE §3、§5），顶层执行 `main()`、零导出；新增子命令应写进本文件的 dispatch，不新开脚本 | `crctl.mjs`；`ARCHITECTURE.md:43,83-89` |
| §8 维护规则明列「crctl 新增写入子命令」为触发 ARCHITECTURE.md 修订的变更之一——本 CR 属之，SDD 含配套修订项 | `ARCHITECTURE.md:108` |
| `casWrite(p, expectedHash, newText)`：写前重读文件、`sha256(cur)!==expectedHash` 即 `fail('CAS_CONFLICT')`，**无重试**，重试是调用方责任 | `crctl.mjs:677-682` |
| `casWriteMulti(writes)`：三阶段（全校验 sha256 → 全写 `.tmp-{pid}` → 连续 rename），任一 hash 失配则两侧均不落盘；`expectedHash==null` 语义为「期望目标不存在」，存在即 `CAS_CONFLICT`（创建冲突） | `crctl.mjs:691-705` |
| 门禁唯一事实源 = `dir-graph.yaml` 状态机 + `skills/shared/crctl/gates.json`，经 `crctl gate --for <status>` 执行；**pipeline JSON 不承载门禁** | `ARCHITECTURE.md:26,45-47`；`crctl.test.mjs:177,389` |
| `feature-writeback.pipeline.json` 节点字段仅 `id/kind/label/ref/prompt/onFail/timeoutMinutes`——**无 `passCondition`/`gate`/`precondition` 字段**；前置校验写在自然语言 prompt 里、失败靠 `onFail:"abort"` | `feature-writeback.pipeline.json` nodes[]（node-1:39 ~ node-5:75） |
| 「cr-guard」在仓内的真实存在 = CI 适配器模板 `skills/shared/crctl/adapters/ci/cr-guard.template.yml`（CI 侧远端复核），**不是** pipeline 节点 | `skills/shared/crctl/adapters/ci/cr-guard.template.yml`；`ARCHITECTURE.md:61-63` |
| pre-commit 钩子现状：两行 `node .../check-skill-matrix.mjs \|\| exit 1` + `check-agents-contract.mjs \|\| exit 1`；lint 类检查器落点 = `skills/shared/crctl/scripts/` | `.githooks/pre-commit:4-5` |
| CAS 冲突**黑盒（spawnSync 调 CLI）无法注入读后改时序**；既有范式为组件级——正则抽出 `casWriteMulti` 函数体 + 注入 stub `readFileChecked`/`sha256`/`fs`、令一侧 hash 失配触发 | `crctl.test.mjs:730-731,924-961` |
| 前置态非法测试统一手法：`status===1` + 结构化 `error.code`（如 `ILLEGAL_LEDGER_STATE`/`CR_STATUS_TRANSITION_NOT_ALLOWED`）+ `after===before` 文件快照 | `crctl.test.mjs:809-820,863-873,912-922` |
| 测试基建：`makeWorkspace()`(mkdtemp+`change-requests/`)、`writeCrEntry()`(`_backlog`+`cr.md` 一致)、`runCrctl()`(spawnSync+JSON)，`try/finally` 清理 | `crctl.test.mjs:26-40,105-108` |
| **tools 包无自有 semver**：无根 `package.json`、无 VERSION/CHANGELOG、无 git tag；仓内 `v0.14~v0.16` 均为**使用方产品** target_version（`product-planning-agent.md:105-106` 规划到 v0.15.0；pipeline `placeholder:"v0.16.0"` 仅占位） | 仓根；`product-planning-agent.md:105-106`；`feature-writeback.pipeline.json:30` |
| review-annotations stage→文件名映射（门禁读取口径）：`requirement`→`requirement.yml`、`tech-design`→`sdd.yml`、`code`→`code.yml` | `crctl.mjs:1230,1524,1534,1549/1554`（PRD §1.3 已核实） |
| 硬不变量约束本设计：①状态单一写者(advance)②账本单一通道(crctl CAS+审计)③零第三方依赖④CRLF 归一+硬失败⑥git 权威 outbox 投影⑦人工审批无旁路 | `ARCHITECTURE.md:79-89` |

### 1. 架构概览

#### 1.1 落点与模块边界

本 CR **不新增独立可执行库**，两类新代码各有归属：

```
tools/
├── skills/shared/crctl/scripts/
│   ├── crctl.mjs                 # ★ 扩：+9 写子命令 +2 只读子命令 +1 git commit 分支（写进现有 dispatch，单文件不拆）
│   ├── lint-prompts.mjs          # ★ 新增检查器（非账本脚本，类比 check-agents-contract.mjs）
│   └── test/
│       ├── crctl.test.mjs        # ★ 扩：新子命令用例（黑盒 + 组件级 CAS）
│       └── lint-prompts.test.mjs # ★ 新增：R1~R6 fixture + ignore 豁免用例
├── skills/{requirement,develop,cr,...}/**/SKILL.md   # 改：prompt 收敛为调 crctl（Phase 1~4）
├── pipeline-templates/*.json                          # 改：node prompt 口径修正（Phase 1/4）
├── skills/shared/crctl/adapters/ci/cr-guard.template.yml  # 改：CI 侧接 lint-prompts --enforce（FR-24 硬门禁真实挂点）
├── .githooks/pre-commit                               # 改：+1 行 lint-prompts（分阶段 report→enforce）
└── ARCHITECTURE.md                                    # 改：§3 代码地图 + §8 触发记录（新增写子命令）
```

**为什么新子命令写进 crctl.mjs 而非新脚本**（不变量 2 + §5 单文件哲学）：它们是账本/受控文件的写入,必须与既有 `advance`/`approve`/`task done` 共用同一条「状态机 + CAS + `.crctl/audit.log` 审计」写入路径。另开脚本 = ARCHITECTURE §6 明否的「第二条账本写入通道」。单文件体量增长是刻意接受的代价（改动即全貌可见）。

**为什么 lint-prompts.mjs 是新脚本而非 crctl 子命令**：它**只读** `SKILL.md`/pipeline JSON + `rules.json`/`crctl.mjs`,不写任何账本/受控文件,是**检查器**（与 `check-skill-matrix.mjs`/`check-agents-contract.mjs` 同类同目录）,不触碰不变量 2 的写入通道,故不撞 §6「否决独立**账本操作**脚本库」（否决对象是账本写入,不是只读校验）。

#### 1.2 依赖方向（合 ARCHITECTURE §4，只朝下）

```
Pipeline → SKILL(prompt 收敛后调 crctl) → crctl.mjs(受控文件唯一写者) → 账本/受控文件
                                        └→ lint-prompts.mjs(只读 SKILL/pipeline/rules.json) → 报告(不写)
pre-commit / CI cr-guard → lint-prompts.mjs（gate）
```

#### 1.3 不变量合规自查（评审重点）

| 不变量 | 本 CR 相关点 | 合规论证 |
|---|---|---|
| ①状态单一写者 | S5 `backlog-set` | 白名单硬拒 `status`（§3），状态仍只经 `advance` |
| ②账本单一通道 | S1~S8 + inbox-emit | 全部走 crctl 子命令 + CAS + 审计,无旁路 |
| ③零第三方依赖 | 新子命令 + lint-prompts | 仅 Node 内建;lint-prompts 用行级正则读 SKILL/JSON,不引 YAML 库 |
| ④CRLF+硬失败 | review-record 解析 payload、lint-prompts 扫 prompt | 读入先 `replaceAll('\r\n','\n')`,解析失败 `fail()` 不静默 |
| ⑥git 权威 | 各写子命令 | 复用既有 `emitOutboxEvent`,失败只记审计不阻塞 |
| ⑦审批无旁路 | S2 `review-note` | 只写 `approval.yml#supplemental-reviews[]`,**不碰** `#requirement/#code` 审批段（那仍只经 `crctl approve` TTY） |

### 2. 数据模型

#### 2.1 guard-deny 面 ↔ crctl 写入面（本 CR 后闭合）

| 受控文件 / 字段（guard deny） | 本 CR 前写口 | 本 CR 后写口 |
|---|---|---|
| `review-annotations/{stage}.yml` | 无（孤儿） | **S1 review-record** |
| `approval.yml#supplemental-reviews[]` | 无（孤儿） | **S2 review-note** |
| `_backlog#checkpoints/remote-ref/last-push*` | 无（孤儿） | **S3 checkpoint-add** |
| `_backlog#owners.{role}` | 无（孤儿） | **S4 owner-set** |
| `_backlog#prd-path/sdd-path` | 无（孤儿） | **S5 backlog-set** |
| `_backlog#notify-log/notify-pending` | 无（孤儿） | **inbox-emit** |
| `cr.md`（首次建档）+ `_backlog`/`_index` 登记 | 无（手写 frontmatter） | **S8 cr-init**（原子） |
| `tasks/_index.yml`（TASK-ID 分配） | 无 CAS（手算） | **S7 task allocate** |

#### 2.2 review-record payload schema（S1，判断/写入分离）

agent 判断落**非受控**临时路径 `.crctl/tmp/review-{stage}.yml`（`.gitignore` 补 `.crctl/tmp/`），crctl 校验后写 canonical。payload 必填结构（校验失败 `SCHEMA_INVALID` 非零退出、不写）：

```yaml
verdict: pass | block              # 枚举,其它值拒
blockers: []                       # 必须是列表(可空);block 时非空
dimensions: {结构完整性: ..., ...}  # 该 stage 门禁要求的维度齐全
suggestions: []                    # 可选
```

canonical 目标由 stage 显式映射（**非同名**,`tech-design`→`sdd.yml`）。写入含 crctl 生成的 `reviewer=identity(ws)`/`reviewed-at=nowIso()`。

#### 2.3 分配即写入（S6/S7/S8 的并发安全模型）

CR-ID / TASK-ID 的「不撞号」不来自「读时抢占」,而来自**写时 CAS**：

- **S6 next-cr-id = 纯只读预览（不参与分配）**：扫 `_index.yml`/`_backlog.yml` 现有 max、返回 `CR-{Y}-{NNN+1}` 候选,仅供 prompt/人「看一眼下一个号」。**不写文件、非权威、不是登记依据**——分配权完全不在此命令。
- **S8 cr-init = 唯一权威原子分配（自行分配并返回 id）**：**不取显式 cr-id 入参**,内部读 max → 计算 `CR-{Y}-{NNN+1}` → 以 `casWriteMulti` 一次写 `cr.md`(新建,`expectedHash==null`)+`_backlog`(追加条目)+`_index`(登记),`expectedHash` 取读时 sha256,**成功后在输出 JSON 返回分配到的 `cr-id`**。并发下第二个写者见 `_index`/`_backlog` hash 已变 → `CAS_CONFLICT`,两侧不落盘 → 调用方(requirement-register SKILL)重跑 cr-init(重读 max、自动拿到新号)。**唯一并发冲突码是 `CAS_CONFLICT`**（不存在 TOCTOU 的 `CR_ALREADY_EXISTS` 竞态,因为无人从外部传入 id）;`CR_ALREADY_EXISTS` 仅保留给「误用：显式要求一个已存在号」的边缘接口,不在正常注册路径出现。**与 crctl「无内部重试」惯例一致**（§0：重试是调用方责任）,不在 crctl 内加 retry 循环、不引 WAL（合 §6 YAGNI）。
- **S7 task allocate** 同理：内部分配 `TASK-{NN}` 并以 `casWrite` 写 `tasks/_index.yml`,唯一冲突码 `CAS_CONFLICT`,由调用方重跑。

### 3. 接口契约（CLI）

统一：时间戳/操作者身份一律 crctl 生成（`nowIso()`/`identity(ws)`),拒绝调用方传入；输出 JSON,退出码 0=成功、非 0=结构化 `error.code`。

#### 3.1 写子命令（9）

```
crctl review-record <cr> --stage <requirement|tech-design|code> --from <payload.yml> [--bump-attempt]
crctl review-note   <cr> [--stage <s>] --note <text>                 # 追加 supplemental-reviews[];无 --by
crctl checkpoint-add <cr> --repo <r> --sha <sha> [--remote-ref <ref>]
crctl owner-set     <cr> --role <requirement|development|test> --id <id>   # --id=被指派人(业务数据),非操作者身份
crctl backlog-set   <cr> --field <prd-path|sdd-path> --value <v>     # 白名单标量;硬拒 status/updated-at/owners/merge-commits
crctl inbox-emit    <cr> --event <...>                                # notify-log 事件追加
crctl next-cr-id    [--year Y]                                        # 纯只读预览(§2.3),不写、不参与分配
crctl cr-init       --title <t> --owner-requirement <id> [--year Y]  # 内部分配 max+1 + 原子 casWriteMulti 建档+登记;输出返回分配到的 cr-id(无显式 cr-id 入参)
crctl task allocate <cr> [--slug <s>]                                # 扩展现有 task 族;CAS 写 tasks/_index.yml
```

#### 3.2 只读子命令（2）+ git 扩展（1）

```
crctl worktree-path <cr> --repo <r>            # 派生 bucket/path,不写,无 CAS
crctl report | crctl cr-metrics [--period P]   # 跨 CR 聚合,只读
crctl git commit --template <register|task-breakdown|writeback|...>   # 现有 git commit 加格式化分支,非新顶层命令
```

#### 3.3 lint-prompts（检查器）

```
node skills/shared/crctl/scripts/lint-prompts.mjs [--mode report|enforce] [--json]
```

- `--mode report`（Phase 0~2 默认）：打印 `file:line + 规则 + 级别`,**退出 0**（不阻断提交）。
- `--mode enforce`（Phase 3 漂移清零后 pre-commit 切换 / CI cr-guard 恒用）：命中 CONTRADICTS/STALE-REF 即**退出 1**。
- 段落级豁免：命中处附近有 `<!-- lint-prompts:ignore -->` 则跳过该段。

#### 3.4 错误码（新增,风格同既有 fail()）

`SCHEMA_INVALID`(payload 校验失败) / `STAGE_UNKNOWN` / `FIELD_NOT_ALLOWED`(backlog-set 白名单外) / `CAS_CONFLICT`(复用;cr-init/task-allocate 的**唯一**并发冲突码) / `ILLEGAL_LEDGER_STATE`(前置态非法,复用) / `CR_ALREADY_EXISTS`(**仅**边缘误用——非正常注册路径,正常 cr-init 无显式 id 不触发) / `LINT_DRIFT`(lint-prompts enforce 命中)。

### 4. 关键算法与流程

#### 4.1 review-record（S1，判断/写入分离）

```
读 .crctl/tmp/review-{stage}.yml → CRLF 归一 → schema 校验(verdict 枚举/blockers 列表/dimensions 齐全)
  失败 → SCHEMA_INVALID(不写)
stage → canonical 文件名显式映射(requirement→requirement.yml / tech-design→sdd.yml / code→code.yml)
  未知 → STAGE_UNKNOWN
注入 reviewer=identity(ws)/reviewed-at=nowIso() → casWrite(canonical, sha256(读时), 新内容)
[--bump-attempt] → 级联现有 attempt 记账逻辑
成功 → 删除 .crctl/tmp/review-{stage}.yml(避免残留/跨 CR 串味) → emitOutbox
```

#### 4.2 cr-init 原子分配（S8，唯一权威分配点）

**无显式 cr-id 入参**——分配与写入是同一步,消除「调用方先拿号、cr-init 再建档」的 TOCTOU：

```
读 _index.yml/_backlog.yml → 内部计算 CR-ID = CR-{year}-{max+1}
构造三文件新内容(cr.md 全量 frontmatter: owners/owner-history/时间戳全 crctl 生成)
casWriteMulti([
  {path: cr.md,     expectedHash: null},        # 期望不存在(创建)
  {path: _backlog,  expectedHash: sha256(读时)}, # 追加条目
  {path: _index,    expectedHash: sha256(读时)}, # 登记
])
  成功 → 输出 JSON 返回分配到的 cr-id
  CAS_CONFLICT(唯一并发冲突码) → 两侧不落盘 → 调用方 SKILL 重跑(重读 max,自动拿新号)
```

并发安全论证：两个并发 cr-init 都读到 max=N、都想写 CR-{N+1}。先到者 casWriteMulti 成功;后到者的 `_backlog`/`_index` expectedHash 已失配 → `CAS_CONFLICT`,三文件全不落盘 → 重跑读到 max=N+1 → 写 CR-{N+2}。**不撞号,且不产生半状态**。因无外部传入 id,不存在「校验 id 不存在」与「写入」之间的 TOCTOU,故正常路径不出现 `CR_ALREADY_EXISTS`。

#### 4.3 lint-prompts R1~R6（检测算法）

```
载入判据: rules.json#protectedPaths.deny(R1 面) + rules.json#git(R2) + 字面黑名单(R3 cr-status-set / R4 六字段口径)
遍历 skills/**/SKILL.md + pipeline-templates/*.json:
  按段落切分(标题/JSON node 边界) → 段内若含 <!-- lint-prompts:ignore --> → skip
  R1: 段内出现 write/create/编辑 + deny 文件名,且**同段无** crctl <cmd> 调用 → CONTRADICTS(邻近判定,避免"解释为何不该手写"误报)
  R2: `git <sub>` 字面且非 `crctl git` → CONTRADICTS
  R3: 出现 `cr-status-set` → STALE-REF
  R4: `source-sha`/`merged-at`/"六字段"作为必填 → CONTRADICTS
  R5: `review-loop.current-attempt`/`attempts[]` + 写动词 → OUTDATED
  R6: `test-report.md` + 手写 `status:`/`commands:` → CONTRADICTS
命中输出 file:line+规则+级别; --mode enforce 且有 CONTRADICTS/STALE-REF → exit 1
```

R1 判据直读 `rules.json`——未来 deny 面新增文件,R1 自动覆盖,无需改 linter（判据零派生物,NFR-6）。

#### 4.4 FR-24 两层 gate 分阶段启用（回应 REQ-BLOCK-001）

| 阶段 | pre-commit | CI cr-guard.template.yml | 效果 |
|---|---|---|---|
| Phase 0~2 | `lint-prompts --mode report`（exit 0） | 未接入 | 本 CR 自身开发期 commit 不被存量漂移阻断 |
| Phase 3 起 | 切 `--mode enforce`（exit 1） | 接入 `--mode enforce` | 漂移提交不进来 + CI 远端兜底 |

归档硬门禁的**真实挂点是 CI cr-guard 适配器**,不是 pipeline passCondition（§0 已核实其不存在）；`cr-archive` 节点 prompt 另加一句软提醒(与 node-1 "校验 status 否则 abort" 同形态)。

### 5. 技术选型与替代方案

| 决策 | 选择 | 已否决的替代及理由 |
|---|---|---|
| 新子命令落点 | 写进 crctl.mjs 单文件 | 新独立脚本：撞 §6 第二写入通道否决 + 破坏单文件不变量 |
| lint-prompts 落点 | 独立检查器 `scripts/lint-prompts.mjs` | 做成 crctl 子命令：它只读、不写账本,塞进 crctl 反而混淆「写者」职责 |
| CR-ID 并发安全 | 分配即写(cr-init casWriteMulti,调用方重试) | next-cr-id 读时抢占：纯读不可能防撞号(§2.3);crctl 内 retry 循环：违「无内部重试」惯例;WAL/2PC：§6 YAGNI 否决 |
| 归档 lint gate 挂点 | CI cr-guard 适配器(enforce) + cr-archive prompt(软) | pipeline passCondition：**字段不存在**(§0);硬塞 gates.json：gates.json 是声明式 path/equals 判据,容不下"跑脚本"语义 |
| gate 启用时序 | 分阶段 report→enforce | Phase 0 即 enforce：拦死本 CR 自身开发期 commit(REQ-BLOCK-001) |
| CAS 冲突测试 | 组件级抽函数注入 mismatch hash | 黑盒并发注入：spawnSync 无法注入读后改时序(§0,测试文件自注);篡改真文件走 CLI：不可靠 |
| 通用写入 | 仅 purpose-specific 白名单子命令 | `crctl patch <file> <path> <val>`：万能逃生口,绕过语义/前置/schema 门禁(PRD NFR-3) |

### 6. FR → 技术实现映射

| FR | 实现 | 验收对齐 |
|---|---|---|
| FR-1 review-record | §4.1 + §2.2 payload schema + stage 显式映射 | AC-1(含临时文件删除) |
| FR-2 review-note | §3.1;只写 supplemental-reviews,身份 crctl 生成 | AC-2(拒 --by) |
| FR-3/4/5/6 | §3.1 各子命令 + `_backlog` 定向字段 casWrite | AC-3(backlog-set 硬拒 status) |
| FR-7 next-cr-id+cr-init | §2.3 + §4.2：cr-init 内部分配并返回 id(唯一权威),next-cr-id 纯预览;唯一并发冲突码 CAS_CONFLICT | AC-4(并发两次 cr-init 断言分配到不同 CR-ID、冲突方收 CAS_CONFLICT 重跑得新号;§5 组件级抽函数注入 mismatch hash 构造) |
| FR-8 task allocate | §2.3 casWrite tasks/_index.yml | AC-5 |
| FR-9/10/11 | §3.2 只读派生 + git commit --template | AC-6 |
| FR-12 D13 溯源 | Phase 0 门槛调查,结论二选一(§1.7 PRD);**本 SDD 不预判路线**,调查产出后若"复活"再补设计小节 | AC-7(结论入 SDD) |
| FR-13 文档+白名单 | ARCHITECTURE §3/§8 修订(§9)、`crctl help`、rules.json#git 补 shape | AC-8 |
| FR-14~17 Phase 1 | prompt 改口径(见下 §6.1) | AC-9 |
| FR-18 Phase 2 | cr-status-set 清退(见 §6.1) | AC-10 |
| **FR-19 Phase 3（拆到任务级,回应 suggestion-4,见 §6.1）** | 13 处改点逐条列 | AC-11 |
| FR-20~22 Phase 4 | 状态映射去重 + 工时措辞 + brief 补齐 | AC-12 |
| FR-23 lint-prompts | §4.3 R1~R6 | AC-13(fixture+ignore) |
| FR-24 两层 gate | §4.4 分阶段 | AC-14(Phase0~2 不阻断) |
| FR-25 回写清单项 | feature-writeback 回写清单模板 + SDD「prompt 采纳影响」强制小节 | AC-15 |

#### 6.1 FR-19 Phase 3 改点清单（suggestion-4：单条巨型 FR 拆到任务级）

| # | 文件:锚点 | 现状 | 改为(子命令) | Phase |
|---|---|---|---|---|
| P3-01 | review-code / review-tech-design / review-requirement | 直接 Write review-annotations + 手写 review-loop | S1 review-record --bump-attempt | 3 |
| P3-02 | write-test-report | 手写 review-loop 进 traceability | crctl attempt(既有) | 1/3 |
| P3-03 | cr-review-record:53-54 | 写 approval supplemental + reject/withdraw | S2 review-note + advance | 3 |
| P3-04 | handover-cr:66-68 / resume-from-remote:86 | 手改 owners | S4 owner-set | 3 |
| P3-05 | push-progress:63-77 | 手写 remote-ref/checkpoints | S3 checkpoint-add | 3 |
| P3-06 | write-requirement-prd:87-89 | 手改 prd-path | S5 backlog-set --field prd-path | 3 |
| P3-07 | inbox-emit | 手写 notify-log | inbox-emit | 3 |
| P3-08 | requirement-register:48 | 手算 CR-ID max+1 无 CAS | S6 next-cr-id(预览) + S8 cr-init(权威) | 3 |
| P3-09 | write-dev-tasks:45,64 | 手动分配 TASK-ID + slug | S7 task allocate | 3 |
| P3-10 | requirement-register:53-97 | 手写整份 cr.md frontmatter | S8 cr-init | 3 |
| P3-11 | requirement-register:127-133 / merge-feature-branch / push-progress / resume-from-remote | prose 重复拼 worktree path | S9 worktree-path | 3 |
| P3-12 | requirement-register:114 / write-dev-tasks:80 / writeback-traceability:75 | prose 拼 commit message | S10 git commit --template | 3 |
| P3-13 | cr-dashboard / spec-dashboard Step 2 | 手动统计 | S11 report/cr-metrics | 3 |

Phase 1 独立改点：P1-a D7 merge-commits 3 字段(`writeback-traceability` + pipeline node-4)、P1-b approve-* 折叠 crctl approve、P1-c 裸 git→crctl git(先核 rules.json#git shape,`ls-remote` 反例)、P1-d test-report frontmatter 交 crctl test。Phase 2：cr-status-set legacy 化 + 7 处引用改 advance + cr-archive 删手写 _index/status。

### 7. 安全与性能考量

- **信任边界 / 审批无旁路（不变量 7）**：S2 review-note 仅追加 `supplemental-reviews[]`,SDD 与实现均**不得**让任何新子命令写 `approval.yml#requirement/#tech-design/#dev-start/#code`——那四段只经 `crctl approve` TTY/Ed25519（AC：grep 新子命令实现无对这四段的写路径）。
- **guard-deny 闭合**：本 CR 后 `rules.json#protectedPaths.deny` 每类文件都有对应 crctl 写口(§2.1),消除"锁死但无出口"孤儿态。
- **失败安全**：写子命令一律「先在内存构造全部新内容 → schema/前置校验通过 → 才 casWrite」,前置态非法/schema 失败均硬失败不落盘(§0 前置态测试范式)。
- **CRLF/硬失败（不变量 4）**：review-record 读 payload、lint-prompts 扫 prompt 均先 `\r\n→\n`,解析失败 `fail()` 不静默降级。
- **性能**：目标文件（_backlog/_index/SKILL.md）均 <1000 行,同步一次性读写,无性能敏感点；lint-prompts 全仓扫 ~60 SKILL + 8 pipeline,单次遍历,pre-commit 可接受。

### 8. 与已审批 PRD 的偏差记录（供 review-tech-design 与人工审批确认）

| # | PRD 原文 | SDD 决策 | 理由 |
|---|---|---|---|
| D1 | FR-24：接「feature-writeback 的 cr-guard(或归档前 passCondition)」 | 归档硬门禁挂 **CI cr-guard 适配器 `adapters/ci/cr-guard.template.yml`**（+ cr-archive prompt 软提醒）;pipeline **无 passCondition 字段**（§0 核实） | PRD 措辞把两个不同层混为一物：pipeline JSON 不承载门禁,真实"cr-guard"是 CI 适配器。功能意图(归档前 lint 必过)不变,落点纠正 |
| D2 | FR-7：next-cr-id「CAS 保护抢占式分配、并发失败重试不撞号」 | next-cr-id **降为只读预览(非权威)**;抢占/防撞号由 **cr-init 的 casWriteMulti + 调用方重试**承担（§2.3/§4.2） | 纯读命令不可能"CAS 保护抢占"——两并发读同一 max 必撞;防撞号的唯一正确位置是写时 CAS。功能意图(不撞号)不变,机制归位 |
| D3 | PRD frontmatter `target-version: tbd`（需求评审 suggestion-1：建议定版本号） | **决策：保持不绑产品版本,以治理里程碑 T1.3 追踪**（回应 suggestion-1） | tools 包无自有 semver(§0);仓内 v0.15/v0.16 是**产品** target_version,强套会污染产品 spec 追溯。本 CR 是 tools 治理链改动,不并入产品 v0.x 线,与 CR-2026-019(T1.1)/020(T1.2) 同一治理里程碑序列 |

**其余 3 条需求评审 suggestion 落实位置**：suggestion-2(cr-guard 挂点确证)→ §0 + §8-D1 已确证并纠正;suggestion-3(CAS 冲突测试构造)→ §5 + §0 定为组件级抽函数注入 mismatch hash;suggestion-4(FR-19 拆任务级)→ §6.1 十三行改点表。

### 9. 参与仓与交付物清单 + ARCHITECTURE.md 修订

| 仓 | 交付物 |
|---|---|
| tools（trunk=custom/main） | crctl.mjs 扩(+9 写 +2 读 +1 git 分支);`lint-prompts.mjs` + `lint-prompts.test.mjs`;`crctl.test.mjs` 扩;`.githooks/pre-commit` +1 行;`adapters/ci/cr-guard.template.yml` 接 lint;20+ SKILL.md + pipeline JSON prompt 收敛;`rules.json#git` 补 shape;`ARCHITECTURE.md` 修订;`crctl help`/`skills/_index.yml` brief 补齐 |
| knowledge-base（trunk=master） | 本 CR 产物(prd/sdd/tasks/评审记录) |
| multica | 不参与（无代码改动,空分支跳过） |

**ARCHITECTURE.md 修订项**（§8 维护规则触发「crctl 新增写入子命令」,随本次评审确认）：
- §3 代码地图 `crctl.mjs` 条目补：写入子命令族扩至覆盖 review-annotations/approval supplemental/_backlog 非 status 字段/CR-TASK-ID 分配/首次建档;新增 `scripts/lint-prompts.mjs` 检查器条目（职责 = prompt↔crctl 漂移检测,只读非账本）。
- §7 横切「测试」补 lint-prompts 回归入口。
- **不改不变量条款**（本 CR 全部合现有不变量,§1.3 已逐条论证）——仅登记新增能力面,不动 §5/§6 判据。

## 治理工具链 — tools 包 prompt 审查修复（97 条发现：批 2.5 crctl 核心缺陷修复 + checkpoint-add 承诺兑现 + approve 驳回回退 + lint R6/R7 与豁免修复 + 冗余收敛）（v0.23 · CR-2026-022）

## SDD — tools 包 prompt 审查修复（批 1/2/2.5/3/3.5/4 + 收尾）

### 1. 架构概览

#### 1.1 落点与模块边界

本 CR 全部落点在 tools 仓（本方法论包自身），改动按 ARCHITECTURE.md §4 分层自上而下分布：

```
Pipeline 层   pipeline-templates/{architecture-design, code-implementation,
              requirement-authoring, competitive-radar, market-to-plan,
              resume-cr, product-planning}.pipeline.json   ← UUID 迁移/节点 prompt 订正/onFail 策略
Skill 层      skills/{cr,develop,requirement,writeback,sync,planning,competitive,review,spec}/*
              + skills/_index.yml / agents/_index.yml      ← 批 1/2/3/4 文本修复与冗余收敛
工具层        skills/shared/crctl/scripts/crctl.mjs        ← 批 2.5 核心代码（FR-9~FR-13, FR-21）
              skills/shared/crctl/scripts/lint-prompts.mjs ← 批 3.5（FR-24~FR-25）
声明层        dir-graph.yaml（新增 1 条转移）+ gates.json（删 1 条死配置）
```

依赖方向不变（Pipeline → Skill → crctl 单向朝下）；本 CR 不新增模块、不新增顶层分组、不拆 `crctl.mjs`（§3 单文件哲学维持）。

#### 1.2 关键流程（修复后）

- **注册链**：`requirement-register` → `crctl cr-init --title … --owner-requirement … [--summary --source --target-version]`（一次原子写齐，消灭违纪手写）→ `crctl git commit --template register --cr <cr-id>`（直传已知 CR 号，跳过反向解析）。
- **进度推送链**：pipeline push-progress 节点 → `push-progress` skill Step 3 逐仓 `git rev-parse HEAD` + `crctl checkpoint-add --repo <r> --sha <sha>`（任意非终态可落账）→ `onFail` 产出可见告警（不 skip 不 abort）。
- **审批驳回链**：`crctl approve --stage <s>` 审批人回答非 yes → decline 分支查状态机 `{stage}:reject -> {to}` 回退转换 → `cmdAdvance` 执行回退 + 输出重跑提示（需求阶段经 D-1 新增转换回 `drafting`）。
- **lint 防线**：pre-commit `lint-prompts enforce` 在原 R1~R5 基础上叠加 R6/R7；豁免注释仅对邻近行生效（radius 契约化）。

### 2. 数据模型

本 CR 不新增账本实体，只扩展既有字段写口与声明数据：

#### 2.1 cr.md / _backlog.yml 字段写口扩展（FR-9）

`cr-init` 现硬编码三字段改为旗标可覆写，缺省值与旧值同义（向后兼容）：

| 字段 | 旗标 | 缺省 | 写入位置 |
|---|---|---|---|
| `summary` | `--summary <s>` | `""` | cr.md frontmatter（引号包裹，防 `:` 破坏 YAML） |
| `source` | `--source <s>` | `manual` | cr.md frontmatter + `_backlog` 条目 `source` |
| `target-version` | `--target-version <v>` | `tbd` | cr.md frontmatter + `_backlog` 条目 `target-version` |

三字段与既有 owners/时间戳同一次 `casWriteMulti` 事务写入（cr.md + `_backlog.yml` + `_index.yml` 三文件全有或全无），不引入"先建档再补字段"中间态。`BACKLOG_SET_FIELDS` 白名单**不扩**——这三字段属注册时一次性写入，不是后续可反复 set 的标量字段，语义不同。

#### 2.2 状态机声明变更（FR-12 ①，D-1 决策落地）

`tools/dir-graph.yaml#change-request-track.state_machine.transitions` 新增**两条**转换（均已 grep 核实现状后定稿）：

```yaml
## ① D-1：需求阶段人工审批驳回回退（现状无任何驳回出口，唯一通道是 cr-review-record:reject 判死刑）
- { from: requirement-reviewing, to: drafting, trigger: "approve-requirement:reject -> write-requirement-prd" }
## ② B3 修复：开发启动审批驳回回退（现状 task-breakdown 只有自环与 -> developing，approve-dev-start 驳回无路可退）
- { from: task-breakdown, to: tech-design-reviewed, trigger: "approve-dev-start:reject -> write-dev-plan" }
```

命名与既有 `approve-tech-design:reject -> write-tech-design`、`approve-code:reject -> implement-code` 同构（`{approve-skill}:reject -> {回退目标 skill}`）。需求阶段 `review-requirement:block` 的语义是**保持 `drafting` 不推进**（现有 `drafting→drafting` 自环，:215），与 tech-design 的显式回退不同，无需新增转换。

**口径变更（§5 不变量 5 联动）**：转移声明 23 → **25** 条，wildcard 展开 45 → **47** 条（两条新转换均不含 wildcard）。所有引用该口径的文档/注释/测试断言同步更新：`tools/ARCHITECTURE.md §3`、主仓 AGENTS.md #2、`crctl.test.mjs` 中的口径断言（如有）。

#### 2.3 gates.json 死配置删除（FR-13，D-2 决策落地）

删除 `reviewLoops["review-planning-report"]` 条目（该 loop 从未被 `evaluatePassCondition`/`readAttempts` 消费，且 product-planning 无 CR 上下文、attempts 持久化路径不成立）。`product-planning.pipeline.json` node-6 prompt 的"必须持久化 review-loop.attempts"改为如实描述：评审注记由 `review-planning-report` 自行落盘 `docs/product-planning/review-annotations/{report-id}.yml`，不经 crctl。

#### 2.4 market-insights 统一 schema（FR-19）

`docs/market-insights/_index.yml` 目标契约（三写入方共用）：

```yaml
## 单一事实源：本文件 schema 由 CR-2026-022 统一定义，新增写入方须先对齐本声明
insights:                       # 顶层 key（conduct-market-research 从 entries: 迁入）
  - id: MI-YYYY-NNN
    type: MARKET_INSIGHT        # 下划线（conduct-market-research 从 MARKET-INSIGHT 迁入）
    status: raw                 # 生命周期 raw → briefed → published
    file: docs/market-insights/{id}.md   # 三写入方均必填（conduct-market-research 补）
    created: "..."
```

`market-to-plan.pipeline.json` 节点 5 终态 `planned` → `published`，执行方明确为 `write-planning-entry`（它是规划台账写入方，状态推进随其执行步骤发生，不再只存在于 pipeline prompt）。历史数据若存在旧字段名，用入库版本化脚本一次性迁移（落点 `skills/writeback/scripts/migrate-market-insights.mjs` + 同目录测试——该目录是 ARCHITECTURE.md §6 范围澄清后内容文件脚本的既有先例落点，planning 域无 scripts/ 先例、不新建目录；遵守纪律 #7 会话内不现写脚本）。

#### 2.5 inbox-emit 事件枚举扩展（FR-15）

`inbox-emit/SKILL.md` 的 event 枚举补 `owner-handover`，三处同步（触发意图列表 / 参数表 / 下游消费方声明 handover-cr）。R7 的枚举校验以该 SKILL.md 声明为判据源（直读，不建快照）。

### 3. 接口契约

#### 3.1 crctl 命令面变更（批 2.5 核心，§8 评审对象）

```text
## FR-9（既有命令扩旗标，缺省向后兼容）
crctl cr-init --title <t> --owner-requirement <id> [--year Y]
              [--summary <s>] [--source <s>] [--target-version <v>]

## FR-10（--template 分支扩旗标）
crctl git commit --template <kind> [--cr <cr-id>] [-m <subject>]
  # --cr 提供时：校验格式 ^CR-\d{4}-\d{3}$ + _backlog 存在性，直用，跳过 resolveTemplateCr
  # --cr 缺省时：保留原「分支探测 → subject 正则」兜底路径，存量调用不破坏

## FR-11（LEGAL 白名单扩展，命令签名不变）
crctl checkpoint-add <cr> --repo <r> --sha <sha> [--remote-ref <ref>]
  # 前置态：全部 12 个非终态（实现见 §4.2，从状态机派生不硬编码）

## FR-12（approve 行为扩展，命令签名不变）
crctl approve <cr> --stage <requirement|tech-design|dev-start|code>
  # decline 分支：查回退转换 → 执行回退 → 非零退出（错误码 APPROVAL_DECLINED_ROLLED_BACK，
  # extra 携带 {rolledBackTo, rerunHint}，见 §4.3；无回退转换时维持 APPROVAL_DECLINED）
```

**退出码契约（FR-12 关键点）**：decline 且回退成功时，进程以**非零**退出（审批未通过这一事实对调用方 pipeline 必须可见，`onFail:abort` 语义不变），错误码 `APPROVAL_DECLINED_ROLLED_BACK`，`fail()` 的 extra 字段携带 `{rolledBackTo: <status>, rerunHint: <write-skill>}`，错误消息为"审批未通过，CR 已回退到 {to}，请重跑 {skill}"。无回退转换的 stage 维持现状 `fail('APPROVAL_DECLINED')`（四 stage 经 D-1 + B3 修复后均有回退转换，该兜底理论上不触发）。

#### 3.2 lint-prompts 规则契约（批 3.5）

```text
R6（crctl 命令参数形态）：
  触发面：行内含 crctl advance / backlog-set / git commit --template
  advance：必须匹配 --to\s+\S+ 与 --trigger\s+\S+
  LITERAL_BLACKLIST 追加：trigger=  expected_current_status=  commit_mode=
                            全角 ， 、 ）（在命令行内出现即违例）
  backlog-set：--field 取值 ∈ BACKLOG_SET_FIELDS（直读 crctl.mjs 常量）
  --template：subject 必须含 CR-\d{4}-\d{3} 编号（--cr 显式传入时豁免）
R7（inbox-emit 接口）：
  函数式 inbox-emit( 直接违例
  CLI 形态 --event 取值 ∈ inbox-emit/SKILL.md 声明枚举（直读）
豁免范围契约（FR-25）：
  <!-- lint-prompts:ignore --> 只豁免注释所在行 ± radius 行（radius=1，
  在 lint-prompts.test.mjs 以测试向量固化；pipeline JSON 的 node.prompt
  按行拆分后逐行判定，不再整段豁免）
```

判据全部直读源文件（`crctl.mjs` 常量 / `inbox-emit/SKILL.md` 枚举），符合 CR-2026-021 NFR-6「判据零派生物」。

#### 3.3 pipeline JSON 契约变更

| 文件 | 变更 | 幂等影响 |
|---|---|---|
| architecture-design.pipeline.json | 5 节点 UUID 前缀 `0014-*` → `0016-*`（含 `repairNodeId` 自引用同步） | seed 幂等恢复（与 resume-cr 不再撞前缀）；**已占用前缀表更新至 0016** |
| code-implementation.pipeline.json | 节点 12 prompt 补 checkpoint-add 描述 | 无节点增删，UUID 不动 |
| 三条流水线 push-progress 节点 | `onFail: skip` 维持不变（JSON 仅 skip/abort 二值，abort 会在 git push 已成功时造成更大混乱）；可见告警改由**工具层**承担——FR-11 ② 重写 push-progress Step 3 时，skill 内逐仓调用 `crctl checkpoint-add` 失败即非零退出并在 node-N.md 摘要中强制输出 `CHECKPOINT_ALERT` 段（skill 执行失败本身即告警，不依赖 onFail 语义） | 运行时行为说明在提交信息中标注 |
| competitive-radar / market-to-plan | 镜像节点 `onFail` 统一 `abort`（D-3） | 运行时行为变更：原静默跳过变为中止，提交信息显式标注 |

> `onFail` 告警的设计取舍见 §5 决策 D-4。

### 4. 关键算法与流程

#### 4.1 cr-init 旗标注入（FR-9）

```text
cmdCrInit(ws, gates, flags):
  ... 既有校验 ...
  summary = flags.summary ?? ''
  source  = flags.source ?? 'manual'
  tv      = flags['target-version'] ?? 'tbd'
  fm 中三处硬编码行改为模板注入（summary 引号包裹 + \" 转义，与 title 同款处理）
  backlogEntry 同步注入 source/target-version
  casWriteMulti 一次写三文件（现有事务边界不变）
```

#### 4.2 checkpoint-add LEGAL 派生（FR-11 ①）

**不硬编码 12 态列表**（报告 §4.1 的参考骨架是全量枚举硬编码；本设计改为派生，防止状态机未来增态再次漂移）：

```text
cmdCheckpointAdd:
  const { sm } = loadStateMachine(ws)
  const LEGAL = (sm.states || []).filter(s => !(sm.terminal || []).includes(s))
  // 与 cmdOwnerSet 的终态判断同源（sm.terminal），口径永不错位
```

`cmdOwnerSet` 已用同款 `sm.terminal` 判断，模式既有、无新机制。若 `loadStateMachine` 失败维持硬失败（不静默回退旧列表，纪律 #1/#4）。

#### 4.3 approve decline 回退（FR-12 ②）

```text
cmdApprove 非 TTY-yes 分支（约 :1074）改为：
  auditLog(..., { result: 'declined' })
  const target = REJECT_ROLLBACK[stage]
    // 静态映射表（与 gates.json approvalStages 一一对应，评审逐条对照）：
    //   requirement → drafting            （经 D-1 新增转换）
    //   tech-design → tech-designing      （既有 :220）
    //   dev-start   → tech-design-reviewed（经 B3 修复新增转换）
    //   code        → developing          （既有 :228）
  const trigger = `${approveSkillOf(stage)}:reject -> ${rollbackSkillOf(stage)}`
  const t = findTransition(sm, current, target, trigger)
  if (!t) fail('APPROVAL_DECLINED', '审批人未确认，且状态机未声明回退转换', { stage, current })
  cmdAdvance(ws, cr, gates, { to: target, trigger, expect: current })
  auditLog(..., { kind:'approve', result:'declined-rolled-back', to: target })
  fail('APPROVAL_DECLINED_ROLLED_BACK', `审批未通过，CR 已回退到 ${target}，请重跑 ${rerunSkill}`,
       { rolledBackTo: target, rerunHint: rerunSkill })
```

`REJECT_ROLLBACK`/`approveSkillOf`/`rollbackSkillOf` 为 crctl.mjs 顶部静态常量表。dev-start 的回退目标 `tech-design-reviewed` 是 write-dev-plan 的前置态（订正 approve-dev-start 现错误表中不可达的"重跑 write-dev-plan"建议——回退后重跑对象正是 write-dev-plan，前置态匹配）。

#### 4.4 lint 豁免收窄（FR-25）

```text
isIgnored(lines, i, radius = 1):
  对 k ∈ [i-radius, i+radius]：lines[k] 含 '<!-- lint-prompts:ignore -->' 则豁免
splitPipelineJson 产出的 node.prompt 按 \r?\n 拆行后逐行跑规则，
豁免判断只作用于行索引邻域，不再对整段 prompt 布尔放行
```

#### 4.5 merge-feature-branch HEAD 校验（FR-16）

Step1.4 增补：`git rev-parse HEAD` 与 `git rev-parse origin/requirement/{cr_id}` 比对，不等则 `fail-fast` 提示补跑 push-progress，不进入合并阶段。纯 SKILL 文本变更，无 crctl 改动。

#### 4.6 cmdNext 判断依据修正（FR-21）

`writing-back` 分支（:2219-2222）现状：`fs.existsSync(change-requests/{cr}/traceability.yml)`（开发期工作稿，恒存在）→ 误判"可归档"。改为检查 writeback-traceability 的产物 `specs/{spec_id}/traceability.yml`。

**spec_id 取值来源（已核实）**：`_backlog` 条目**没有** spec-id 字段（grep 坐实）；specId 在 crctl 内一律是**调用方经 `--spec-id` 旗标传入**的参数（`advance --to writing-back/archived` 缺它即 BAD_ARGS fail-fast，:987-991），不落账本。因此 cmdNext 不能从账本读 spec_id，改为**从文件系统推断**：扫描 `specs/` 目录，若存在唯一子目录则取其名；多个子目录时取 `_backlog` 条目 `merge-commits` 所在仓对应的 spec 目录不可行（无映射），此时输出"多 spec 目录，请显式确认"而非猜。实现：

```text
case 'writing-back':
  const specsDir = path.join(ws, 'specs')
  const subs = fs.existsSync(specsDir) ? fs.readdirSync(specsDir, {withFileTypes:true}).filter(d=>d.isDirectory()).map(d=>d.name) : []
  if (subs.length !== 1) return suggest('writeback-prd-sdd', `specs/ 子目录数=${subs.length}，无法唯一确定 spec_id，先完成 PRD/SDD 回写`)
  const trace = fs.existsSync(path.join(specsDir, subs[0], 'traceability.yml'))
  return suggest(trace ? 'cr-archive' : 'writeback-tasks → writeback-traceability', ...)
```

只读逻辑 bug 修复，不新增写口。

### 5. 技术选型与替代方案

| # | 决策 | 取舍 |
|---|---|---|
| D-1 | 新增 `requirement-reviewing:reject -> drafting`（PRD §1.3 已拍板） | 替代方案"维持 CR 死刑"被否：与其余三阶段不对称且过于刚性 |
| D-2 | 删 gates.json 死配置（PRD 已拍板） | 替代方案"新开不依赖 CR 上下文的 attempts 子命令"被否：单消费者收益不成比例，违反 §6 YAGNI |
| D-3 | onFail 统一 abort（PRD 已拍板） | 替代方案"skip + 空文件降级展示"被否：额外复杂度换不来可用性 |
| D-4 | push-progress 节点 onFail 维持 `skip`，可见告警由工具层承担（skill 内 checkpoint-add 失败即非零退出 + 摘要强制 CHECKPOINT_ALERT 段） | pipeline JSON `onFail` 只有 skip/abort 二值；abort 会在 git push 已成功时造成更大状态混乱（报告 2.1-G 明示不宜 abort）。告警不依赖 onFail 语义，由 skill 执行失败本身承担——这是可执行形态，非"等未来 warn 语义"的悬置方案 |
| D-5 | LEGAL 白名单从状态机派生而非硬编码 12 态 | 报告 §4.1 参考骨架为全量硬编码；派生方案与 cmdOwnerSet 同源、未来增态零成本漂移。代价：checkpoint-add 对"语义上不该记账"的状态（如 rejected 前的边界态）也放行——但终态已由 sm.terminal 排除，非终态记 checkpoint 无副作用 |
| D-6 | decline 回退后仍非零退出 | 替代方案"回退成功即零退出"被否：pipeline onFail 依赖退出码区分"审批通过"，零退出会让流水线误入下一节点 |
| D-7 | 迁移脚本落点 `skills/writeback/scripts/` | 该目录是 ARCHITECTURE.md §6 范围澄清（CR-2026-020）后**内容文件脚本**的既有先例落点（writeback-prd-sdd.mjs 等）；market-insights 迁移是内容文件操作不是账本操作，与先例同构。planning 域无 scripts/ 先例，不新建目录 |
| D-8 | UUID 前缀选 `0016-*` | 0002/0003/0010/0011/0013/0014/0015 已占用，取最小未占用值（沿用报告建议） |

### 6. FR 到技术实现映射

| FR | 实现条目 | 批次 |
|---|---|---|
| FR-1~FR-3 | 8 文件 12 处命令串按报告 2.1-A 目标形态逐处替换（review-requirement 省 `--expect`）；3 处豁免注释外移；死引用/措辞订正 | 批 1 |
| FR-4~FR-8 | cr-status-set 文件+条目删除、validate-doc 两处订正、focus-briefing 反向修（status:new/seen 翻转）、降级路径、pending 清空、record-adr 删前引用计数核实 | 批 2 |
| FR-9 | §2.1/§4.1 cr-init 旗标注入 | 批 2.5 |
| FR-10 | §3.1 `--cr` 旗标优先 + 兜底保留 | 批 2.5 |
| FR-11 | §4.2 LEGAL 派生 + push-progress Step 3 逐仓调用 + 节点 12 补齐 + §3.3/D-4 告警 | 批 2.5 |
| FR-12 | §2.2 状态机新增**两条**转移（D-1 需求驳回 + B3 修复 dev-start 驳回）+ §4.3 decline 回退（含 REJECT_ROLLBACK 四 stage 映射）+ 四份 approve-* 错误表订正 + "无旁路"表述修正 | 批 2.5 |
| FR-13 | §2.3 删死配置 + node-6 prompt 如实描述 | 批 2.5 |
| FR-14 | requirement-register 错误表补 STALE_BASE 降级行 | 批 2.5 |
| FR-15 | §2.5 枚举三处同步 + feedback-writeback/handover-cr 迁 CLI 形态 | 批 3 |
| FR-16 | §4.5 HEAD 校验 | 批 3 |
| FR-17 | competitive-radar node-2 写入目标 + confirmed=false 草稿 + 落盘挪审批后 | 批 3 |
| FR-18 | §3.3 UUID 0016 迁移 + repairNodeId 同步 + seed 幂等验证 | 批 3 |
| FR-19 | §2.4 统一 schema + 节点 5 终态订正 + 原子提交 + 迁移脚本（D-7） | 批 3 |
| FR-20 | handover-cr/resume-from-remote 改调 owner-set | 批 3 |
| FR-21 | §4.6 cmdNext 判断依据 + crctl.test.mjs 用例 | 批 3 |
| FR-22 | cr-show 改调 crctl next、删硬编码表 | 批 3 |
| FR-23 | 八项歧义订正逐条按报告 2.4 目标形态落地 | 批 3 |
| FR-24 | §3.2 R6/R7 | 批 3.5 |
| FR-25 | §4.4 豁免收窄（radius=1 契约化） | 批 3.5 |
| FR-26 | lint-prompts.test.mjs 三类向量（含 product-planning:109 复现场景） | 批 3.5 |
| FR-27~FR-32 | approve-* 对齐、writeback 抽 shared、sync 收敛 + worktree-path、constraints 删、push-progress 样板抽取（以 FR-11 为前提）、评估项下线（write-insight-brief/run-competitive-analysis 合并下线 + 去重 + 跳过检查单份化） | 批 4 |
| FR-33 | 三台账同步 + check-skill-matrix + JSON 自检 + crctl.test.mjs 全量回归 + 状态机口径 25/47 全仓引用核查 | 收尾 |
| FR-34 | ARCHITECTURE.md §8 登记本 CR + crctl/SKILL.md 新旗标 + lint 头部说明 + AGENTS.md 抽 shared 原则 | 收尾 |

FR 覆盖率：34/34。

### 7. 安全与性能考量

- **并发安全**：cr-init 扩旗标不改变 `casWriteMulti` 事务边界；checkpoint-add/approve 改动均走既有 CAS + audit 路径，无新写入范式（NFR-1）。
- **状态机回归风险**：D-1 新转移是纯增量，不改任何既有转换；decline 回退只发生在审批人显式回答非 yes 的分支，`--grant` 签名路径不经过该分支（不变量 7 不受影响）。
- **口径同步**：状态机 25/47 口径变更列入 FR-33 核查清单（grep "23 条声明" 全仓清零旧口径）。
- **行尾纪律**：R6/R7 规则与豁免逐行判定前统一 `replaceAll('\r\n','\n')`；`splitPipelineJson` 跨行正则匹配失败维持硬失败（不变量 4）。
- **性能**：lint 新增两规则为行级正则，全仓扫描耗时增量 <10%（现有 R1~R5 同量级）；crctl 改动均为 O(1) 分支，无性能面变化。
- **回滚**：批 2.5 每子项单 commit（cr-init/--cr/LEGAL/approve/gates 各一），任一可独立 revert；dir-graph.yaml 回退转换删除前留存改前对照（NFR-2）。
- **灰度**：批 2.5 落地后先以一次演练注册走通三条新路径（NFR-5，形式参照 CR-2026-019 AC-9），本 CR 自身后续阶段（任务拆分/开发）即天然灰度消费者。

### 8. Prompt 采纳影响（CR-2026-021 FR-25 条件性小节——本 CR diff 触及 crctl.mjs dispatch，必填）

本 CR 扩展/修改的 crctl 能力面与应采纳的 skill 清单（逐条核对，防"新增能力未被采纳"类漂移）：

| crctl 能力变更 | 现状 | 应改为 |
|---|---|---|
| cr-init `--summary/--source/--target-version`（FR-9） | requirement-register Step 2 无字段传参路径，注册实录被迫违纪手写 | requirement-register Step 2 prompt 改为把 summary/source/target-version 作为 cr-init 旗标传入；删 cr_id 僵尸参数 |
| `git commit --template --cr`（FR-10） | requirement-register Step 4 靠 subject 强制带编号 | 改为显式 `--cr {cr-init 返回值}` 直传 |
| checkpoint-add 全非终态可用（FR-11） | push-progress Step 2-3 只调 runGit、展示 YAML 让人抄 | Step 3 改逐仓 `crctl checkpoint-add --repo <r> --sha <sha>`；三流水线节点 prompt 引用 skill 默认说明（FR-31） |
| approve decline 回退（FR-12） | 四份 approve-* 错误表无"回答非 yes"分支 | 各补一行"驳回后 CR 回退到 {to}，请重跑 {skill}"，与 §4.3 映射表逐一对齐 |
| gates.json review-planning-report 删除（FR-13） | product-planning node-6 承诺"必须持久化" | 改为如实描述自行落盘机制 |
| cmdNext writing-back 修正（FR-21） | cr-show 硬编码映射表 | 改调 `crctl next`（FR-22 同步采纳） |

以上采纳动作全部已在本 CR 的 FR 清单内（非欠账），实施顺序上批 2.5 代码先行、对应 prompt 修改同批跟进，不允许"代码上了、prompt 下批再改"。

### 9. 测试设计

| 层 | 内容 |
|---|---|
| crctl.test.mjs | cr-init 三旗标（缺省兼容/覆写/转义）；`--cr` 直传与兜底路径；checkpoint-add 12 非终态参数化 + 3 终态拒绝；approve decline 四 stage 回退（含 requirement 新转换与 dev-start 新转换）+ 回退失败兜底；cmdNext writing-back 三分支（无 specs 目录/唯一目录/多目录）；状态机口径断言更新 25/47 |
| lint-prompts.test.mjs | R6 三类违例 + backlog-set/--template 覆盖；R7 两类违例；豁免 radius 边界（±1 行命中/±2 行不豁免）；product-planning:109 复现场景 |
| writeback/pipeline 自检 | architecture-design/resume-cr JSON 解析 + seed 幂等（重复 seed 无重复节点）；market-insights 迁移脚本 fixture 测试 |
| 端到端（AC-20） | 报告 §6.2 三场景：完整生命周期串联 / 通知链两事件 / lint 三类违规注入 |

### 10. 风险与残余

- **批 4 抽 shared 的引用失效风险**：前置 FR-24 lint「shared 引用一致性」检查必须先落地（NFR-4），否则把 N 处漂移换成引用失效。
- **focus-briefing pipeline 注册表路径**：运行时路径确认不了时整体删除该数据源（文档已声明可选、删除零副作用）——确认动作在实施期向运行时方取证，取证结果记录在任务产出中。
- **record-adr/adrs.yml 删除**：删前必须完成全仓引用计数核实（含前端/agent 读取面），核实记录入任务证据。
- **onFail 语义限制（D-4）**：可见告警由 skill 执行失败（非零退出）承担，pipeline onFail 维持 skip 不升级——这是当前 schema 下的确定方案，非悬置；若未来 pipeline JSON 支持 `warn` 语义可再评估。

## 治理工具链 — 代码评审 LLM 选择暂停节点 + R9 护栏（CR 上下文下一步收敛 crctl next）（v0.24 · CR-2026-023）

## SDD — 代码评审 LLM 选择暂停节点 + R9 护栏 技术设计

> 输入：`prd.md`（14 FR / 8 US / 11 AC）。目标仓：**tools 方法论包**（本 CR 目标代码仓即 tools 仓自身，架构基线读 `tools/ARCHITECTURE.md`，已存在、只读引用）。
> 所有落点行级定位已于技术设计期实跑核对；实施期行号若漂移，以结构锚点为准并在任务内订正（纪律 #4）。

### 1. 架构概览

#### 1.1 改动面与模块边界

本 CR 触及 tools 包四个既有模块，**不新增模块、不改依赖方向**（ARCHITECTURE.md §4：依赖只朝下，Skill 不绕过 crctl）：

```
pipeline-templates/code-implementation.pipeline.json   ← 块 A：inputs + 新 human_approval 节点 + review-code prompt
pipeline-templates/_index.yml · README.md              ← 块 A：台账与文档同步（12→13 节点）
skills/shared/crctl/scripts/lint-prompts.mjs(+test)    ← 块 B：R9 规则 + 测试向量
skills/{requirement,develop,writeback,sync}/*/SKILL.md ← 块 B：17 处存量清零 + push-progress 引导链闭环
agents/requirement-writer.md · AGENTS.md（tools 仓）   ← 块 B：前置注记 + 编辑规则第 7 条
```

硬不变量核对（ARCHITECTURE.md §5）：
- **crctl 单一状态写者**：新 human_approval 节点只做暂停确认，不写 CR 状态、不调 crctl 状态子命令——合规。
- **Skill 文档不得描述账本手工编辑**：17 处改写仅动「下一步」提示行，不涉账本编辑步骤——合规。
- **lint-prompts 与 crctl 平行**：R9 判据源直读 `skills/_index.yml`（台账只读消费），不引入对 crctl 运行时状态的依赖——合规。

#### 1.2 关键流程（改动后）

**流程 A（/coding 评审前暂停）**：

```text
… 0008 push-progress（统一 checkpoint）
 → 0013 选择代码评审 LLM（human_approval：review_llm 已指定→快速确认；留空→三选一询问；驳回→abort）
 → 0009 review-code（prompt 头部承接选择结果，dimensions 记录 reviewer-model）
 → 0010 代码审查通过 → 0011 approve-code → 0012 push-progress
repair 循环：replayNodes 仍为 implement-code→write-test-report→push-progress→review-code（显式 nodeId 引用，0013 不在列表内，天然不被重放）
```

**流程 B（R9 护栏生效路径）**：

```text
pre-commit 钩子 → lint-prompts --mode enforce → runRules 逐段扫描
 → 文件路径 ∈ CR 上下文域 且非 cr-show → 行含「下一步」且不含「crctl next」且含 skill id/pipeline 名 → R9 CONTRADICTS → enforce 阻断提交
```

### 2. 数据模型

本 CR 无数据库/持久化模型变更，以下为改动涉及的结构定义（均为既有 schema 内的增补）：

#### 2.1 pipeline JSON 新增输入（inputs[]）

```json
{ "key": "review_llm", "label": "代码评审 LLM", "type": "text", "required": false,
  "placeholder": "留空则在评审前暂停由人工选择",
  "description": "指定执行 review-code 的模型/runner；留空时节点「选择代码评审 LLM」会暂停等待人工选择" }
```

#### 2.2 pipeline JSON 新增节点（nodes[]，数组位置 = 执行顺序）

```json
{ "id": "00000000-0000-0000-0015-000000000013", "kind": "human_approval", "label": "选择代码评审 LLM",
  "approvalPrompt": "<三分支引导文案，见 §3.1>", "onFail": "abort", "timeoutMinutes": 4320 }
```

插入位置：`nodes[8]`（0008 push-progress）之后、`nodes[9]`（0009 review-code）之前；插入后数组长度 12→13，`nodes[9..12]` 整体后移一位（UUID 不变，仅数组序变化）。

#### 2.3 reviewer-model 留痕字段

写入 review-code 临时 payload `.crctl/tmp/review-code.yml` 的 `dimensions` 映射内（自报字符串，如模型名或 runner 标识），随 `crctl review-record --stage code --bump-attempt` canonical 化进 `review-annotations/code.yml#dimensions`。**不改 crctl 契约**：canonical `reviewer` 字段仍由 crctl 注入 `identity(ws)`，reviewer-model 仅是 dimensions 内的附加留痕维度。

#### 2.4 lint finding 结构（R9 复用既有）

```js
{ rule: 'R9', level: 'CONTRADICTS', file, line, why }
```

### 3. 接口契约

#### 3.1 节点 0013 approvalPrompt（定稿文案契约）

```text
代码与测试证据已推送统一 checkpoint，即将进入代码评审。

若触发参数 review_llm 已指定，请按该模型执行并快速确认；否则请在此暂停并询问用户选择评审 LLM：
① 当前会话默认模型
② 外部 CLI runner（按代码执行设置中可用 runner 列出选项）
③ 其他指定模型

记录用户选择后再勾选继续；驳回则中止本轮评审。
```

契约要点（AC-1 对应）：三分支齐全；**不含「下一步」关键词、不含任何字面 skill id**（approvalPrompt 文本需过 R9 扫面不命中——pipeline-templates/ 本不在 R9 scope，此约束为纵深防御，防止文案被抄入 SKILL.md 后触发）。

#### 3.2 review-code prompt 头部追加段（定稿契约）

```text
执行评审前确认上一节点选定的评审 LLM（触发参数 {{inputs.review_llm}} 或人工审批环节的用户选择）；
按该模型/runner 执行本评审，并在 .crctl/tmp/review-code.yml 的 dimensions 中记录 reviewer-model 留痕（自报），
使评审证据可追溯由哪个模型产出。其余取证与落盘要求不变
（评审判断写临时 payload，经 crctl review-record --stage code --bump-attempt 落盘 review-annotations/code.yml）。
```

追加于现有 prompt **最前面**，其余取证与落盘文本零改动。

#### 3.3 R9 统一改写形态（17 处存量 + 新增提示的行级契约）

```text
下一步 : 以 `crctl next {cr_id}` 为准（PASS→等待人工审批；BLOCK→pipeline 自动回对应修复节点重审）
```

- 有 PASS/BLOCK 分支语义的（review-*/write-test-report）：保留括号内语义方向；
- 纯顺序流转的（register/prd/approve-* 链）：只写「下一步 : 以 `crctl next {cr_id}` 为准」；
- **括号内不得出现任何字面 skill id**（D-4，防自触发；"对应修复节点"是语义方向占位）。

#### 3.4 AGENTS.md（tools 仓）新增条目

「编辑规则 → 修改 Skill」第 7 条：

```markdown
7. CR 上下文 skill（requirement/develop/writeback/sync/cr 域）的输出摘要中「下一步」提示一律写「以 `crctl next {cr_id}` 为准」，不得手写 skill/pipeline 名映射副本（lint-prompts R9 强制）。
```

### 4. 关键算法与流程

#### 4.1 R9 判定算法（lint-prompts.mjs）

落点结构（实跑核对）：常量区在 L27-28（`CRCTL_PATH`/`INBOX_SKILL_PATH` 模式）、`loadJudgements()` L32-46、`runRules(para, ctx)` L116 起、R8 块结束于 L196 附近、`ctx = { ...loadJudgements() }` L238（返回值自动 spread 进 ctx）。

```js
// ① 常量区追加（对齐 CRCTL_PATH 模式，__dirname 固定解析——不随 --root 变，见 §5.2 决策）
const SKILLS_INDEX_PATH = path.resolve(__dirname, '..', '..', '..', '_index.yml'); // R9 判据源：全部 skill id

// ② loadJudgements() 追加（纪律 #1：\r\n 规范化）
const skillIndex = fs.readFileSync(SKILLS_INDEX_PATH, 'utf8').replaceAll('\r\n', '\n');
const skillIds = new Set([...skillIndex.matchAll(/^\s*-\s*id:\s*([\w-]+)/gm)].map((m) => m[1]));
// 返回值追加 skillIds

// ③ runRules() R8 块后追加
const CR_CONTEXT_SCOPE = /^skills\/(requirement|develop|writeback|sync|cr)\//;
const PIPELINE_NAME_HIT = /\b(requirement-authoring|architecture-design|code-implementation|feature-writeback|resume-cr|writeback|coding|architecture)\s+pipeline\b/;
if (CR_CONTEXT_SCOPE.test(ctx.file) && !ctx.file.includes('/cr-show/')) {
  for (let li = 0; li < lines.length; li++) {
    const l = lines[li];
    if (!l.includes('下一步') || l.includes('crctl next')) continue;
    const hit = [...ctx.skillIds].filter((s) => l.includes(s));
    if (hit.length || PIPELINE_NAME_HIT.test(l)) {
      findings.push({ rule: 'R9', level: 'CONTRADICTS', file: ctx.file, line: para.startLine + li,
        why: 'CR 上下文 skill 的「下一步」提示必须写「以 crctl next {cr_id} 为准」，禁止手写副本' });
    }
  }
}
// ④ 文件头注释规则清单追加：+ R9（CR 上下文「下一步」提示收敛 crctl next）
```

行号语义与既有 R7/R8 一致（`para.startLine + li`）；`<!-- lint-prompts:ignore -->` ±1 行豁免由既有的段落级豁免机制自动适用，R9 无需新增豁免代码。

#### 4.2 节点插入流程（块 A）

1. `inputs` 数组追加 review_llm 条目（与既有三条并列，无顺序依赖）；
2. `nodes` 数组在 0008 与 0009 之间插入 0013 节点对象；
3. review-code（0009）节点 `prompt` 字段头部拼接 §3.2 追加段；
4. `reviewLoop.replayNodes` **零改动**（显式 nodeId 引用，插入不影响）；
5. JSON 解析自检 + `_index.yml` nodes 12→13、brief 补环节 + README 两处同步（§6 FR-6：代码编写期节点表 L453 checkpoint 行之后插入新行；mermaid 流程图 L425-426 `D8 --> D9` 直连改为经新节点中转，节点总数描述同步 12→13）。

#### 4.3 提交批次序列（NFR-1 同批约束的执行编排）

```text
commit 1（块 B，原子）：lint-prompts.mjs（R9）+ test 向量 + 17 处 SKILL.md 清零 + push-progress 闭环 + requirement-writer 注记 + AGENTS.md 第 7 条
   ↳ 上线前先跑 --mode report 确认命中恰为 17 处 → 改完跑 enforce 归零 + 测试全绿，同一 commit 过 pre-commit
commit 2（块 A）：code-implementation.pipeline.json + _index.yml + README
   ↳ pipeline-templates/ 不在 R9 scope，块 A 不触发 R9；块 A 亦不依赖 R9，但顺序上护栏先行（批 3.5 先例）
```

**基线协调（NFR-6）**：tools 仓工作区现有 3 个未提交 pipeline JSON 修改（`auto_push_after_task` default true→false ×2、`source` required→true），其中 `code-implementation.pipeline.json` 与本 CR 同文件不同 hunk——commit 2 前须先与用户确认该三处变更的归属（由其自行提交或声明放弃），本 CR 只 add 本 CR 的 hunk，不得混提。

### 5. 技术选型与替代方案

| 决策 | 选择 | 否决的替代 | 理由 |
|---|---|---|---|
| 暂停机制 | 既有 `human_approval` 节点 | 新增 pipeline 运行时暂停指令 / inputs 触发时预选-only | human_approval 是声明式模板唯一合法暂停机制（AGENTS.md）；备选简化方案（只加输入不插节点）无法满足"评审时刻干预"核心诉求（附件1 §四） |
| 选择结果传递 | 会话上下文 | pipeline JSON 新增变量机制 | pipeline 在 Agent 会话内执行，用户答复对下一节点天然可见；新增变量机制属运行时契约变更，超出本 CR 范围 |
| R9 判据源 | `__dirname` 固定解析 `skills/_index.yml` | `--root` 相对解析 | 对齐 R7/R8 判据源固定模式（CRCTL_PATH/INBOX_SKILL_PATH 先例）；黑盒测试用真实 skill id（如 review-requirement）作违例文本即可命中，fixture 无需自带索引；R9 治理对象就是 tools 包自身 skill 名 |
| R9 级别 | CONTRADICTS | OUTDATED / STALE-REF | 仅 CONTRADICTS/STALE-REF 被 enforce 阻断，OUTDATED 只报告起不到护栏作用（附件2 §4.4） |
| reviewer-model 落点 | dimensions 自报留痕 | `crctl review-record --reviewer-model` 机器可读字段 | 后者需 gates.json/digest 联动，属独立 CR 级改动（附件1 §八.3，列入范围排除） |
| replayNodes | 不加入 0013 | 加入重放 | 一次选择全程复用；显式 nodeId 引用下新节点天然不在重放列表，换模型需求由节点 10 驳回重走承接 |

### 6. FR 到技术实现映射

| FR | 技术实现 | 文件 |
|---|---|---|
| FR-1 | inputs 追加 review_llm（§2.1） | `pipeline-templates/code-implementation.pipeline.json` |
| FR-2 | nodes 插入 0013（§2.2 + §3.1 定稿文案） | 同上 |
| FR-3 | review-code prompt 头部追加（§3.2） | 同上 |
| FR-4 | replayNodes 零改动验证（数组 diff 为空） | 同上（验证项） |
| FR-5 | nodes 12→13 + brief 补「选择代码评审 LLM（人工确认）」 | `pipeline-templates/_index.yml` |
| FR-6 | 节点表插行（L453 后）+ mermaid D8→新节点→D9（L425-426）+ 节点数描述 12→13 | `README.md` |
| FR-7 | R9 四处改动（§4.1 ①~④） | `skills/shared/crctl/scripts/lint-prompts.mjs` |
| FR-8 | 附件2 §4.2 表 17 行按 §3.3 形态逐行改写（requirement 4 + develop 9 + writeback 4） | 17 个 `skills/**/SKILL.md` |
| FR-9 | 输出摘要 `last-push-at` 行（L84）后追加「下一步 : 以 crctl next 为准」行 | `skills/sync/push-progress/SKILL.md` |
| FR-10 | 映射表 approve-requirement 行（L33）加前置注记（verdict=pass 且 blockers=[]） | `agents/requirement-writer.md` |
| FR-11 | 「修改 Skill」规则追加第 7 条（§3.4） | tools 仓 `AGENTS.md` |
| FR-12 | 三类向量（§4.1 落点旁测试文件，makeFixture/runLint 既有基建） | `test/lint-prompts.test.mjs` |
| FR-13 | 提交批次序列 §4.3 + 五步自检 | 流程约束 |
| FR-14 | commit message 延续漂移治理编号（R9 条目标注 G5 呼应 + CR-2026-023 溯源） | 提交规范 |

### 7. 安全与性能考量

- **lint 性能**：R9 每行 3 次字符串判定 + 一次 skillIds 过滤（55 元素），相对既有 R7/R8 同量级；skillIds 集合 loadJudgements 一次载入，不逐文件重读。
- **误报边界**：①「下一步」+「crctl next」同行直接 continue（豁免主形态）；②cr-show 路径豁免；③域外文件零命中（planning/spec/competitive 无 CR 上下文，写 crctl next 反而是新漂移——附件2 §4.1）；④确需手写的单行用 `<!-- lint-prompts:ignore -->` ±1 行豁免留痕。
- **漏报边界**：skill id 判定基于子串包含，短名 skill 理论上可能误命中普通文本——17 处清零时逐行人工核对，测试向量含域外反向用例兜底；pipeline 名模式要求 `pipeline` 词尾共现，收窄误报面。
- **回滚**：commit 1 整体 revert 即恢复（规则 + 清零同批，revert 后 enforce 恢复旧基线）；commit 2 revert 后 pipeline 恢复 12 节点。两 commit 无相互依赖，可独立回滚。
- **边界条件**：review_llm 留空是该输入的主路径（现场三选一），非异常态；超时 4320 分钟与节点 4/10 一致；驳回 abort 后无状态残留（该节点不写状态）。

### 8. Prompt 采纳影响

本 CR diff **不触及** `crctl.mjs` dispatch 分支与 `rules.json#protectedPaths.deny`（R9 是 lint-prompts 新增规则，属平行治理工具；pipeline/SKILL 改动不含 crctl 命令面新增）——按 SDD 模板条件性约定，本节无应采纳清单，留此说明备查。

### 9. 风险与残余

| 风险 | 缓解 |
|---|---|
| 17 处改写漏改/多改导致 enforce 自阻断或遗漏 | FR-13 自检①：上线前 `--mode report` 命中数恰为 17（对照附件2 §4.2 表），实施期以实测为准（行号可能已漂移，以内容锚点定位） |
| tools 仓 3 处未提交修改与本 CR 同文件冲突 | §4.3 基线协调：commit 2 前与用户确认归属，按 hunk 拆分 add |
| README mermaid 图遗漏同步（附件1 §2.6 只提了节点表） | 本 SDD §4.2 第 5 步显式列入 mermaid 改动（实跑核对 README L425-426 存在 D8→D9 直连） |
| R9 对既有 `<!-- lint-prompts:ignore -->` 豁免语义理解偏差 | 豁免为段落级既有机制，R9 不新增豁免代码；测试向量补一条豁免生效用例 |
| D4 运行时层缺口（maxAttempts 耗尽行为） | 不在 tools 包管辖，crctl approve 证据门兜底；PRD 范围排除已声明 |

## Phase0 Tools 技能整合（v0.25 · CR-2026-024）

## SDD — 端到端 Pipeline 最佳实践技能整合 技术设计

> 输入：`prd.md`（24 FR / 8 US / 20 AC）。目标仓：**tools 方法论包**（本 CR 目标代码仓即 tools 仓自身，架构基线读 `tools/ARCHITECTURE.md`，已存在、只读引用）。
> 所有落点行级定位已于技术设计期实跑核对（2026-08-08）；实施期行号若漂移，以结构锚点为准并在任务内订正（纪律 #4）。

### 0. 事实订正（技术设计期实跑核对发现的方案漂移）

PRD 与方案 v2.6 的表述与 tools 仓现状不符处共 **5 处**（C-1~C-3 为初稿自查发现；C-4/C-5 依评审 attempt 1 的 blocker M-3/B-3 增补），本 SDD 予以订正，**结论不受影响**：

| # | 方案/PRD 表述 | 实测现状 | SDD 订正 |
|---|---|---|---|
| C-1 | 「implement-code 为 code-implementation pipeline 节点 6、write-dev-tasks 为节点 2」 | CR-2026-023 合入后 pipeline 为 **13 节点**（dev-start 审批与评审 LLM 选择两个 human_approval 插入致数组序漂移）：write-dev-tasks=**nodes[1]**、implement-code=**nodes[5]**、review-code=nodes[9]（恰未漂移） | 实施以实测下标为准；PRD FR-3/FR-19 的节点编号语义不变、下标订正 |
| C-2 | 「删 4 个死声明 external」隐含 4 项均在各 actor `external:` | actor 级 external 死声明实为 **3 项**，全部位于 `system-orchestrator.external`（L217-219：using-superpowers/writing-plans/verification-before-completion）；`systematic-debugging` 仅存在于顶层 `external-skills:` 纯文档块（L229，从未被解析，方案 §4.2 已认定），actor 级无此项 | 批次一清除对象 = `system-orchestrator.external` 三项；顶层 `external-skills:` 块本次**不动**（纯文档、不参与任何校验，整块处置留漂移治理项 D-2） |
| C-3 | 「record-idea 按 AGENTS.md:135 登记要求」 | record-idea 实为 **planning 域**已注册 skill（`skills/planning/record-idea/SKILL.md`，`skills/_index.yml` 在册，planning-agent owns、L153 某 actor 已 can-call）——skill 本体无需新建 | FR-16 仅为 `dev-agent.can-call` 追加引用（跨域调用登记），无新建成本 |
| C-4 | FR-10 落点写 `skills/planning/write-dev-plan/`（PRD FR-10 同错） | 实测在 `skills/develop/write-dev-plan/SKILL.md`（skills/_index.yml:114 path=./develop/write-dev-plan/...，SKILL.md 头部自述 develop 组，agent-skill-matrix.yml:78 dev-agent.owns） | §1.1/§6 路径全部订正为 develop 域（评审 M-3） |
| C-5 | 死声明清单未含 `test-driven-development` | 该名称在 tools 仓共 4 处：implement-code/SKILL.md:75、pipeline nodes[5].prompt、agent-skill-matrix.yml:94（dev-agent.external）、:228（顶层纯文档块）。FR-2/FR-3 删掉前两处后，L94 即零引用，成为**本 CR 新造的 actor 级死声明**——「批次一完成后死声明数为 0」在批次一自身即不成立 | §4.1 步骤 1 追加删除 dev-agent.external 的 test-driven-development（executing-plans/subagent-driven-development 保留，FR-2 降级路径为其真实引用）；AC-1 grep 扩至该名（评审 B-3） |

### 1. 架构概览

#### 1.1 改动面与模块边界

本 CR 触及 tools 包七个既有模块，**新增 1 个 skill（coding-discipline），不新增 actor、不改依赖方向**（ARCHITECTURE.md §4：依赖只朝下，Skill 不绕过 crctl）：

```
skills/develop/coding-discipline/SKILL.md（新建）      ← 批次二：开发纪律兜底事实源（§1/§2/§3）
skills/develop/{implement-code,review-code,write-dev-tasks,approve-code}/SKILL.md  ← 批次一删改 + 批次二内化
skills/develop/write-dev-plan/SKILL.md                 ← 批次二：引用 coding-discipline §2（C-4 订正：develop 域，非 planning 域）
skills/requirement/write-requirement-prd/SKILL.md      ← 批次二：summary 边界采纳
pipeline-templates/code-implementation.pipeline.json   ← 批次一节点5 prompt + 批次二 inputs(suggestion_policy) + 节点1/5/9 prompt
agent-skill-matrix.yml · agents/_index.yml             ← 批次一死声明/capabilities/known-gaps + 批次二 coding-discipline 归属/record-idea 登记
skills/_index.yml · AGENT-SKILL-MATRIX.md · dir-graph.yaml · ARCHITECTURE.md §8 · openwiki · AGENTS.md(tools) ← 台账与文档同步
```

硬不变量核对（ARCHITECTURE.md §5）：
- **crctl 单一状态写者**：本 CR 不触及 `crctl.mjs` 任何子命令与状态机——合规（PRD NFR-3/NFR-5）。
- **owns 唯一性**：`coding-discipline` 唯一 owns = `dev-agent`（既有 actor）——合规。
- **Skill 文档不得描述账本手工编辑**：全部改动为规则文本/配置数据，无账本手工编辑步骤——合规。
- **lint-prompts 平行治理**：新增 SKILL.md 正文以本包语汇书写、可被 lint-prompts 覆盖，不引用未注册技能名作执行前提——合规。

#### 1.2 关键流程（改动后）

**流程 A（suggestion_policy 策略化分流，批次二核心行为变更）**：

```text
/coding 触发 → inputs.suggestion_policy（select，UI 预选中 strict）
 → … nodes[9] review-code（prompt 承载 {{inputs.suggestion_policy}} 插值；B-1 订正：插值只发生在 pipeline JSON，SKILL.md 不含插值语法）：
    ├─ strict（默认）：非阻塞发现一律进 suggestions；verdict 只判 CR 本身
    └─ lenient：非阻塞发现过三条升格判据（不扩 diff / 有明确改法 / 纯实现层）且通过轮次闸
         ├─ 判据全满足且 attempt=1 → 升格进 blockers（同轮多条成批写入）→ verdict=block → 既有 reviewLoop replayNodes 回修
         └─ 任一判据不满足或轮次 ≥2 → suggestions（M-2 轮次闸）
    dimensions 记录 suggestion-policy 留痕（canonical，M-1）；Step 6 输出补「Suggestions : {N} 条」与本轮 policy
 → nodes[11] approve-code：剩余 suggestions 可选经 record-idea 落 docs/ideas/（不设默认、不阻塞）
```

**流程 B（depends-on 拓扑排序，implement-code）**：

```text
nodes[5] implement-code Step 3：
 读 tasks/_index.yml 的 depends-on → 拓扑排序
 → 前置 TASK 未 done → 不启动本 TASK，节点输出注明被阻塞项与等待前置
 → 同层无依赖 TASK：未装 dispatching-parallel-agents → 串行；已装 → 可并发（独立域判据见 §4.3）
 → 回修模式（review_feedback 存在）→ 一律串行（先根因，§4.3）
```

### 2. 数据模型

本 CR 无数据库/持久化模型变更，以下为改动涉及的结构定义（均为既有 schema 内的增删）：

#### 2.1 pipeline JSON 新增输入（inputs[]，code-implementation）

```json
{ "key": "suggestion_policy", "label": "改进建议处置策略", "type": "select",
  "options": ["strict", "lenient"], "required": false, "default": "strict",
  "description": "strict=不升格，所有非阻塞改进建议一律进 suggestions，评审只判 CR 本身的 pass/block（保守交付，默认）；lenient=按三条判据把本 CR 内该修的升格进 blockers，走 reviewLoop 在本 CR 内解决（清技术债场景）" }
```

追加于现有 4 个 inputs（cr_id / target_version / auto_push_after_task / review_llm）之后。形态对齐三个既有 select input（competitive-radar `focus_dimension` / market-to-plan `insight_type` / resume-cr `new_owner_role`，均为 required:false + default）。

#### 2.2 agent-skill-matrix.yml 数据变更

```yaml
## 批次一（删除）
system-orchestrator.external: 移除 using-superpowers / writing-plans / verification-before-completion（L217-219，清后为 []）
known-gaps: 移除前两条（knowledge-agent-write-skills、customer-support-feedback-write，L233-238），保留 writeback-agent-entry

## 批次二（追加）
dev-agent.owns: += coding-discipline
quality-reviewer-agent.can-call: += coding-discipline
dev-agent.can-call: += record-idea
```

顶层 `external-skills:` 块（L222-230）本次不动（C-2 订正）。

#### 2.3 agents/_index.yml capabilities 订正

```yaml
knowledge-agent:          # L175
  capabilities:
    supported: [design-doc-support]            # 移出 tech-note-write, insight-write
    pending: [tech-note-write, insight-write]  # pending 字段从 [] 启用
customer-support-agent:   # L220
  capabilities:
    supported: [product-doc-qa, tech-doc-qa, usage-guidance, implementation-explain]  # 移出 unresolved-feedback-record
    pending: [unresolved-feedback-record]
```

#### 2.4 TASK frontmatter 删字段（write-dev-tasks）

模板（L58-59 区域）删除 `assignee: ""` 一行；`depends-on: []`（L58）保留（批次二拓扑排序的消费对象）。

#### 2.5 review-code 策略留痕（M-1 订正：落 canonical）

策略留痕写入临时 payload `.crctl/tmp/review-code.yml` 的 `dimensions` 映射：`suggestion-policy: {strict|lenient}`（与 CR-2026-023 的 reviewer-model 先例并列；经 `crctl review-record` canonical 化进 `review-annotations/code.yml#dimensions`；crctl 对 dimensions 只校验「是映射」，加键零结构成本）——跨 CR 可比性依赖 canonical 账本，节点输出不是账本。另在 Step 6 输出摘要追加 `Suggestions : {N} 条` 与 `Policy : {strict|lenient}` 两行作人类可读展示。

### 3. 接口契约

#### 3.1 coding-discipline SKILL.md（新建，定稿骨架契约）

```markdown
---
name: coding-discipline
description: 开发纪律兜底事实源：极简阶梯选方案、2-5 分钟步骤粒度、先根因后动手与回归红绿验证。dev-agent 实现 TASK 与自修复时遵循。
---

§1 极简阶梯：需要存在吗（YAGNI）→ 代码库已有 → 标准库 → 平台原生 → 已装依赖 → 一行 → 最小可用实现。
   信任边界校验、错误处理、安全、可访问性不在精简范围内。
§2 执行步骤粒度：单 TASK 内部步骤按 2-5 分钟切分（写验证用例→跑到失败/明确当前状态→实现→复验→提交），
   每步含精确文件路径与验证步骤，禁止 TBD/占位符。TASK 本身粒度（1-3 天）由 write-dev-tasks 定义，不受本节约束。
§3 根因排查 + 回归验证：自修复模式（review_feedback 存在）动手前先定位根因（哪个 TASK/哪一行/什么假设不成立），
   同一根因下所有失败点一次修完；节点输出必须含 root-cause 字段（与 fixed-blockers 并列）。
   修复针对 bug 时回归测试先验红（临时还原修复前代码确认失败）再验绿（恢复修复确认通过），两次结果写入节点输出。

甲路线：目标运行时已装 ponytail / systematic-debugging / writing-plans 完整版时优先走其完整流程，
未装按本 skill 规则执行，二者等价；本 skill 是兜底事实源，不依赖跨运行时探测。
```

契约要点：全文本包语汇，不出现「必须遵循 external X」类悬空句式（批次一删除的失效模式不得复现）；external 技能名仅作来源标注/可选加速器。

#### 3.2 review-code Step 1 无条件重验（定稿句式契约）

替换 L46 现状「若缺失，必须重新运行或要求补齐」为：**无条件重新执行** implement-code 节点输出中的验证命令（lint/test/build）；implement-code 自报结果仅作参考对照，不一致时以本轮重新执行结果为准并在 blockers 注明差异。「测试通过」必须是本轮重新执行的完整命令输出（0 failures），"看起来通过"或"之前跑过"不构成证据。甲路线补充句：已装 `verification-before-completion` 时可用其 Gate Function/Common Failures 表作执行细则参考，未装按本节最低要求执行——**本条不得弱化为"可选加速"**。

#### 3.3 review-code Step 3 升格判据（lenient 生效，定稿契约）

```text
按本轮策略参数执行（缺省 strict）——参数由 nodes[9].prompt 的 {{inputs.suggestion_policy}}
插值承载；SKILL.md 只写模式无关表述，正文不出现 pipeline 插值语法
（B-1 订正：{{inputs.*}} 插值只发生在 pipeline JSON 的 prompt/approvalPrompt，
同源先例 review_llm 亦只写在 code-implementation.pipeline.json，review-code/SKILL.md 零提及）。

lenient 模式下非阻塞发现同时满足三条判据且通过轮次闸才升格进 blockers：
① 改动不超出本 CR 已触碰的文件（不扩大 diff）；
② 有明确的"改成什么"（能写进 repair-instructions，不是"优化一下"）；
③ 不需要产品/架构决策（纯实现层）；
④ 轮次闸（M-2）：仅首轮评审（attempt=1）允许升格；第 2 轮起一律按 suggestions 处理——
   防升格消耗 maxAttempts=3 耗尽轮次、停在 developing 无法进入审批。
任一判据不满足 → suggestions。同一轮多条升格项必须写进同一批 blockers（成批升格）。
留痕：dimensions 写 suggestion-policy: {strict|lenient}（canonical，§2.5）。
语义：blockers=本 CR 内要处理的（不论轻重）；suggestions=本 CR 内不处理的。
```

#### 3.4 implement-code 降级路径 + 拓扑排序（定稿句式契约）

批次一（删 L75 TDD 引用后补降级，比照 brainstorming 样板）：

```text
目标运行时未提供 subagent-driven-development 时，按 TASK 顺序串行实现（等价于降级到
executing-plans 语义），在节点输出注明降级。
```

后半句「两者均未提供时，按 coding-discipline §2 的粒度自行拆解执行」**不落批次一**——coding-discipline 批次二才创建，批次一先落即成悬空引用（正是本 CR 要清除的失效模式），挪入 §4.2 e 同批（B-2 订正）。

批次二（Step 3 追加拓扑排序）：执行前读 `tasks/_index.yml` 的 `depends-on` 拓扑排序；前置 TASK 未 done 不得开始本 TASK，并在节点输出注明被阻塞 TASK 与等待的前置项。并发边界：同一 repo worktree 内会修改同一文件的多个 TASK 必须串行；跨 repo 的 TASK 因 worktree 隔离可并发；回修模式默认串行。已装 `dispatching-parallel-agents` 时同层无依赖 TASK 可并发派发（可选加速器，并发只影响耗时不影响产出）。

#### 3.5 write-dev-tasks 接口契约小节（定稿骨架）

TASK 正文追加：

```markdown
#### 接口契约
- 消费：本 TASK 使用哪些上游 TASK 产出的精确函数名/参数/返回类型
- 产出：本 TASK 暴露给下游 TASK 的精确签名
```

Step 4（生成 `tasks/_index.yml` 后）追加核对：所有 TASK 声明的接口签名一致性，命名对不上输出 WARN 并列出差异（不静默覆盖，由计划负责人决定，比照"估算交叉校验"写法）。「注意事项」的"不得模糊描述"替换为判据清单：禁止 TBD/"待定"；禁止"加适当的错误处理"类空描述；禁止"同 TASK-XX"引用而不给实际签名；禁止引用未在任何 TASK 定义的类型/函数。

#### 3.6 approve-code suggestions 承接（定稿句式契约）

追加：剩余 `suggestions` 可选经 `record-idea`（planning 域 skill）转入 `docs/ideas/`——必须在 approve-code 期做（CR worktree 内随分支合并进 trunk；feature-writeback 硬边界只写 specs/delivery）；不设默认、不阻塞本 CR；不转则仅留档 review-annotations，无损失。

#### 3.7 AGENTS.md（tools 仓）第 56 条修订

```markdown
2. 外部同名技能由目标运行时按需提供；phase0 tools 以自有规则（如 coding-discipline）为兜底事实源，
   外部技能作可选加速器——已装则优先走其完整流程，未装按本包规则执行，二者等价、不要求探测。
```

第 160 条（禁止把外部方法论 Skill 打包进 phase0 tools）保持不变——coding-discipline 是本包语汇重写的自有规则，非复制上游 SKILL.md。

### 4. 关键算法与流程

#### 4.1 批次一执行序列（零行为变更，纯删除/对齐）

```text
1. agent-skill-matrix.yml：system-orchestrator.external 删 3 项（C-2）；dev-agent.external 删 test-driven-development（C-5）；known-gaps 删前两条
2. agents/_index.yml：三项 capabilities supported→pending（§2.3）
3. implement-code/SKILL.md：删 L75 TDD 行，补 §3.4 批次一降级文本（止于串行+注明降级，不含 coding-discipline 引用，B-2）
4. code-implementation.pipeline.json：nodes[5] prompt 同步删 TDD 表述、补同款降级表述（C-1 下标）
5. write-dev-tasks/SKILL.md：删 L59 assignee 行
6. AGENT-SKILL-MATRIX.md + openwiki/architecture/agent-skill-matrix.md：forbidden 性质说明
   （声明性边界，执行靠 agent 自觉 + protectedPaths 文件守卫，不存在调用级拦截；不加运行时钩子）
↳ 验证：check-skill-matrix + check-agents-contract + lint-prompts --mode enforce 全绿；
  状态机回归确认行为零变化（死声明删除仅影响矩阵报告面）
```

#### 4.2 批次二执行序列（同批原子性，FR-22）

```text
commit（同一批）：
  a. 新建 skills/develop/coding-discipline/SKILL.md（§3.1）
  b. skills/_index.yml 登记 active
  c. agent-skill-matrix.yml：dev-agent.owns += coding-discipline；quality-reviewer-agent.can-call += coding-discipline；dev-agent.can-call += record-idea
  d. AGENT-SKILL-MATRIX.md 主责矩阵同步 + dir-graph.yaml 登记路径 + ARCHITECTURE.md §8 代码地图登记
  e. implement-code Step 3 引用 §1+§2、自修复分支引用 §3、追加拓扑排序（§3.4）；降级文本补后半句「两者均未提供时按 coding-discipline §2 粒度自行拆解执行」（与 a 同批落盘，B-2 订正）
  f. write-dev-plan 引用 §2
  g. review-code：「前端质量」维度（SKILL.md 表第 7 行，B-4）+ Step 1 无条件重验（§3.2）+ Step 3 策略化分流模式无关表述与轮次闸（§3.3）+ dimensions.suggestion-policy 留痕与 Step 6 输出两行（§2.5）
  h. approve-code 追加 suggestions 承接（§3.6）
  i. write-dev-tasks 接口契约三处（§3.5）
  j. code-implementation.pipeline.json：inputs += suggestion_policy（§2.1）；nodes[1] prompt 同步接口契约；nodes[5] prompt 同步拓扑排序；nodes[9] prompt 承载 {{inputs.suggestion_policy}} 插值读取并同步「前端质量」维度 ⑤ + 无条件重验 + 升格判据与轮次闸（B-1 订正，C-1 下标）
  k. write-requirement-prd 追加 summary 边界采纳行
  l. AGENTS.md(tools) 第 56 条修订（§3.7）+ openwiki 页面同步
↳ 原子性依据：a~f 拆开则 check-skill-matrix 报「active skill 无 owns」或孤儿引用；
  g~j 的 prompt 引用 coding-discipline/suggestion_policy 与 a/§2.1 同批才不产生悬空引用（批次一删除的失效模式不得复现）
```

#### 4.3 并发独立域判据（implement-code 拓扑排序的并发边界）

```text
可并发 ⇔ 不同拓扑层无依赖 且 独立域：
  独立域 = 跨 repo（worktree 天然隔离），或同 repo 但不触碰同一文件
不可并发：同 repo 同文件多 TASK；回修模式（review_feedback 存在）——多 blocker 常同源，先根因（§3.1 §3）
并发派发仅在已装 dispatching-parallel-agents 时启用，子代理返回后核对改动冲突并重跑全量验证
```

#### 4.4 提交批次编排与基线协调（NFR-10）

```text
tools 仓 commit 1（批次一，§4.1 全量）→ 三件套验证 + 行为回归
tools 仓 commit 2（批次二，§4.2 全量，同批原子）→ 三件套验证 + 1 个真实 CR 回归
基线协调：tools 仓工作区现有大量与本 CR 无关的删除态文件（.qoder/repowiki/、README.pdf、
assets/readme-illustrations/ 等，属用户另行变更）——两 commit 仅 add 本 CR 文件清单，
严禁 git add -A；实施期若发现与本 CR 同文件的外部未提交修改，按 hunk 拆分并与用户确认归属
```

### 5. 技术选型与替代方案

| 决策 | 选择 | 否决的替代 | 理由 |
|---|---|---|---|
| 开发纪律承载 | 新建本包自有 `coding-discipline` skill | 声明 external（ponytail 等）运行时引用 | external 未安装即静默蒸发——正是本 CR 要修的失效模式（implement-code L75 TDD 悬空先例）；内化 30 行文本成本远低于新增跨运行时探测设施 |
| 外部技能定位 | 甲路线可选加速器（措辞级） | 强制前置 / 完全排斥 | 已装完整技能者走完整流程不吃亏，未装者有兜底；不要求探测机制 |
| suggestions 分流控制权 | pipeline 触发参数 suggestion_policy | 评审期人工逐条选 / 审批期处置 | skill 节点中途无可插人工暂停钩子，逐条人选要改 canonical + 再烧一轮 maxAttempts=3；审批期改代码则评审证据（针对当时那份代码）失效——任何"本 CR 内消费"路径最终都回到 reviewLoop 重审，分流点只能前移评审期（方案 §4.9-③ 推理） |
| suggestion_policy 默认值 | strict（不升格） | lenient（积极清债） | 保守交付优先：默认不因改进建议触发额外回修轮次；清技术债是按 CR 显式开启的选项；与 review_llm「一次选择全程复用」同构，零新增节点 |
| 剩余 suggestions 落点 | approve-code 期经 record-idea 落 docs/ideas/ | writeback 期写 delivery/ / 仅留档 | feature-writeback 硬边界只写 specs/delivery；delivery/ 写进去仍无人读（换个目录继续只写不读）；docs/ideas/ 有完整下游通路（ideas→认领→requirement 注册 CR） |
| depends-on 排序执行层 | prompt 层（implement-code 自觉） | crctl task done 加依赖守卫 | 守卫涉及 crctl 新增校验与测试向量，属独立 CR（PRD D-5）；prompt 层先行闭环，守卫登记后续项 |
| capabilities 处置 | Level A 数据订正（supported→pending） | Level C 真闭环（capability→skill[] 映射 + 校验不变式） | Level C 约 40 条目且牵出新 pending 项，自成 CR（PRD D-3）；先消除"声明与事实相反"的即时误导 |
| 顶层 external-skills 块 | 本次不动 | 整块删除/改造 | 从未被解析的纯文档（方案 §4.2），删与不删均无运行时影响；整块处置并入 D-2 漂移治理项，避免本 CR 扩面（C-2 订正） |

### 6. FR 到技术实现映射

| FR | 技术实现 | 文件 |
|---|---|---|
| FR-1 | system-orchestrator.external 删 3 项 + dev-agent.external 删 test-driven-development（C-2/C-5 订正：systematic-debugging 仅在顶层纯文档块不动；tdd 随引用删除会变死声明，同批清除） | `agent-skill-matrix.yml` |
| FR-2 | 删 L75 TDD 行 + 补 §3.4 降级路径 | `skills/develop/implement-code/SKILL.md` |
| FR-3 | nodes[5] prompt 同步（C-1 订正：方案"节点 6"= 现 nodes[5]） | `pipeline-templates/code-implementation.pipeline.json` |
| FR-4 | capabilities 订正（§2.3）+ known-gaps 删前两条（§2.2） | `agents/_index.yml` + `agent-skill-matrix.yml` |
| FR-5 | forbidden 性质说明（声明性边界、无调用级拦截） | `AGENT-SKILL-MATRIX.md` + `openwiki/architecture/agent-skill-matrix.md` |
| FR-6 | 删 L59 assignee 行 | `skills/develop/write-dev-tasks/SKILL.md` |
| FR-7 | 新建 SKILL.md（§3.1 定稿骨架） | `skills/develop/coding-discipline/SKILL.md` |
| FR-8 | 登记 active + owns/can-call + 矩阵/dir-graph/ARCHITECTURE §8（§2.2、§4.2 b~d） | `skills/_index.yml` 等 5 文件 |
| FR-9 | Step 3 引用 §1+§2、自修复引用 §3、拓扑排序（§3.4、§4.3） | `skills/develop/implement-code/SKILL.md` |
| FR-10 | 引用 coding-discipline §2（C-4 订正：develop 域；粒度约束只在实现期生效，nodes[0].prompt 无步骤粒度表述，不需同步，m-2） | `skills/develop/write-dev-plan/SKILL.md` |
| FR-11 | Step 3 维度表追加「前端质量」维度（B-4 订正：现有 6 行表追加第 7 行，按维度名验收；判据：破 WCAG AA 升 blocker、触发 `*.tsx|*.vue|*.css|*.html`；nodes[9].prompt 同步追加 ⑤） | `skills/develop/review-code/SKILL.md` + pipeline nodes[9] |
| FR-12 | Step 1 无条件重验（§3.2，替换 L46 句式） | 同上 |
| FR-13 | inputs += suggestion_policy（§2.1，形态对齐 3 个既有 select） | `pipeline-templates/code-implementation.pipeline.json` |
| FR-14 | Step 3 策略化分流模式无关表述（§3.3；B-1 订正：{{inputs.*}} 插值落 nodes[9].prompt）+ 轮次闸（M-2）+ dimensions.suggestion-policy 留痕与 Step 6 输出两行（§2.5，M-1） | `skills/develop/review-code/SKILL.md` |
| FR-15 | suggestions 承接条款（§3.6） | `skills/develop/approve-code/SKILL.md` |
| FR-16 | dev-agent.can-call += record-idea（C-3 订正：skill 本体已存在于 planning 域，仅登记跨域调用） | `agent-skill-matrix.yml` |
| FR-17 | 接口契约小节 + Step 4 签名核对 + 占位符判据（§3.5） | `skills/develop/write-dev-tasks/SKILL.md` |
| FR-18 | 追加 summary 已确认边界优先采纳行 | `skills/requirement/write-requirement-prd/SKILL.md` |
| FR-19 | nodes[1]/[5]/[9] prompt 同步（C-1 订正下标；nodes[9] 承载 {{inputs.suggestion_policy}} 插值读取，B-1；「前端质量」⑤ + 无条件重验 + 升格判据与轮次闸） | `pipeline-templates/code-implementation.pipeline.json` |
| FR-20 | 第 56 条甲路线修订（§3.7）；第 160 条不动 | tools 仓 `AGENTS.md` |
| FR-21 | forbidden 性质 + 主责矩阵页面同步（实施期按 openwiki 实际页面清单展开） | `openwiki/` |
| FR-22 | 批次一/二分开、批次二内部同批（§4.1/§4.2 编排） | 提交约束 |
| FR-23 | 每批三件套 + 1 个真实 CR 回归（crctl next/status/gate 无越级） | 验证关卡 |
| FR-24 | commit message 注明方案 v2.6 + CR-2026-024 溯源；全改动无本机绝对路径 | 提交规范 |

### 7. 安全与性能考量

- **行为兼容**：批次一零运行时行为变更（纯删除/数据对齐）；批次二中 strict 是默认策略——默认路径下评审行为与改动前一致（非阻塞发现仍进 suggestions、verdict 判据不变），lenient 为显式开启的增量路径。
- **口径留痕**：lenient 模式 blockers 语义扩大，policy 记录于 canonical `review-annotations/code.yml#dimensions.suggestion-policy`（§2.5，M-1 订正：跨 CR 可比性依赖 canonical），避免跨模式数据误比（NFR-7）。
- **悬空引用防线**：批次二所有 prompt/SKILL 引用（coding-discipline / suggestion_policy / record-idea）与被引用对象同批落盘——批次一修复的"声明蒸发"失效模式不得在本 CR 自身复现（§4.2 原子性依据）。
- **回滚**：批次一/二为两个独立 commit，可分别 revert；批次二 revert 后 suggestion_policy input 与 prompt 引用同批消失，无残留悬空（因同批原子）。
- **边界条件**：suggestion_policy 缺省即 strict（required:false + default），旧触发方式零感知；拓扑排序遇 depends-on 环时（validate-doc 只校验引用目标存在、不校验无环，环可以存在，m-1 订正）implement-code 输出 WARN 并退回索引顺序串行，不静默吞环；真正防环属 D-5 依赖守卫范围。
- **基线隔离**：tools 仓大量删除态外部文件（.qoder/repowiki 等）严禁混入本 CR commit（§4.4）。

### 8. Prompt 采纳影响

本 CR diff **不触及** `crctl.mjs` dispatch 分支与 `rules.json#protectedPaths.deny`（无 crctl 命令面新增/变更、无 guard deny 面变更）——按 SDD 条件性小节约定，本节无应采纳清单，留此说明备查。

### 9. 风险与残余

| 风险 | 缓解 |
|---|---|
| 方案文档节点编号陈旧（C-1）导致实施改错节点 | 本 SDD §0 已订正为实测下标（1/5/9）；实施期以 ref 名（write-dev-tasks/implement-code/review-code）为结构锚点，下标二次核对 |
| 死声明分布与方案表述不符（C-2）导致多删/漏删 | 清除对象锁定 system-orchestrator.external 三项；顶层纯文档块不动；实施后 grep 四项名称确认 actor 级零残留、顶层块原样 |
| 批次二同批原子被拆提交触发三件套自阻断 | §4.2 清单作为任务拆分边界——a~l 属同一 TASK 原子单元，禁止跨 commit 拆分 |
| tools 仓删除态外部文件混提 | §4.4：仅 add 本 CR 文件清单，禁 git add -A；提交前 git status --short 核对 |
| openwiki 页面清单未逐一核实（FR-21 较笼统） | 实施期第一步 grep openwiki/ 对 forbidden/主责矩阵的引用点展开清单；评审建议（需求期 suggestion 1）在此承接 |
| depends-on 排序仅 prompt 层、无可执行守卫 | 已登记后续项（crctl task done 依赖守卫，PRD D-5）；本 CR 内 implement-code 节点输出注明被阻塞项提供留痕 |
| capabilities Level A 订正后仍可能再次漂移 | Level C 真闭环已列范围排除与后续项（PRD D-3）；本次先消除即时误导 |
| lenient 升格消耗评审轮次，可能耗尽 maxAttempts=3 停在 developing（M-2） | 轮次闸：仅 attempt=1 允许升格，第 2 轮起一律 suggestions（§3.3）；lenient 清债场景属显式开启，启动人已知喙 |

## crctl 守卫与回显收敛（v0.26 · CR-2026-025）

## SDD — crctl 守卫与回显收敛

> **实施顺序前提（PRD D-3 / NFR-5）**：本 CR 项①的实施与验证必须在 CR-2026-024 批次一合入 `custom/main` 之后进行；否则 B-3 的存量零引用声明会让新规则上线即报红。项②③④与 CR-2026-024 无顺序耦合，可先行。

### 1. 架构概览

#### 1.1 目标仓与改动面

目标代码仓 = **tools 仓自身**（方法论包）。全部改动收敛在四个既有执行面，不新增模块、不新增目录（测试文件落在既有 `scripts/test/`）：

| # | 文件 | 改动性质 | 承载项 |
|---|---|---|---|
| F-1 | `skills/shared/crctl/scripts/check-skill-matrix.mjs` | 修改（新增检查 4 + 解析扩展 + CRLF 规范化） | ① |
| F-2 | `skills/shared/crctl/scripts/crctl.mjs` | 修改（`cmdTaskDone` 守卫 / `evaluatePassCondition` 回显收敛 / `cmdReviewRecord` 三账本一致写 / `cmdNext` drafting 路由） | ②③④ |
| F-3 | `skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs` | **新建**（该脚本首个测试，B-13） | ① |
| F-4 | `skills/shared/crctl/scripts/test/crctl.test.mjs` | 追加向量 | ②③④ |
| F-5 | `agent-skill-matrix.yml` | 顶层 `external-skills:` 块上方加注释（块内容不动，D-2） | ① |
| F-6 | `AGENT-SKILL-MATRIX.md` | L57 声明位置表述收敛（D-2） | ① |
| F-7 | `skills/_index.yml` | L313-317 注释去点名化（FR-4） | ① |
| F-8 | `skills/shared/crctl/SKILL.md` | 用途表补 `task done` 守卫与两错误码（FR-9） | ② |
| F-9 | `skills/develop/implement-code/SKILL.md` | 拓扑排序表述补一句机械强制（FR-9） | ② |
| F-10 | `README.md` | 若含 `task done` 行为描述则同步（FR-9 条件项，实施期确认） | ② |
| F-11 | `ARCHITECTURE.md` | §8 登记本 CR（FR-24） | 收尾 |

**不改动**：`dir-graph.yaml`（状态机）、`gates.json`、`controlled-shell/rules.json`、pipeline JSON——与 NFR-2/NFR-4 一致。FR-24 中"dir-graph.yaml 同步"一项经实测：tools 仓 `dir-graph.yaml` 无脚本级文件清单面（grep `test.mjs`/`scripts/` 零命中），登记落点收敛为 `ARCHITECTURE.md` §8；若实施期发现可登记面再按 PRD 补。

#### 1.2 依赖方向与不变量符合性

改动全部发生在 ARCHITECTURE.md §4 依赖图的最底层（crctl 执行器）与平行的校验脚本层，无向上依赖引入：

- **不变量 1（状态单一写者）**：四项均不写 status。
- **不变量 2（账本单一写入通道）**：项④把 `traceability.yml#reviews.<stage>` 投影**收编进 crctl `review-record`**（CAS + 审计同一条写入路径），正是强化该不变量；收编后三个 review-* SKILL 的手工投影步骤废弃（见 §8）。
- **不变量 3（零第三方依赖）**：全部 `node:` 内置模块；测试仅 `node:test`/`node:assert` + `spawnSync`（B-14）。
- **不变量 4（行尾与硬失败）**：F-1/F-2 所有新增读入点先 `\r\n → \n`，解析失败硬失败（§4 逐项落实）。
- **不变量 7（审批无旁路）**：项②③④不触审批路径。
- **§6 否决面**：不引入独立账本脚本库、不引入 WAL、不引入 YAML 序列化库（项④复用行级定点编辑 + `casWriteMulti`）。

### 2. 数据模型

#### 2.1 项① — `externalByActor`（进程内结构，不持久化）

```js
// check-skill-matrix.mjs 解析期产物
externalSkills: Set<string>            // 既有，保持不变（检查 2 继续消费）
externalByActor: Map<actor, string[]>  // 新增：记录声明来源，仅供检查 4 错误文案
```

持久化数据（`agent-skill-matrix.yml`）结构不变，只加注释行。

#### 2.2 项② — `depends-on`（既有字段，无 schema 变化）

`tasks/_index.yml` 任务条目既有形态（B-7/B-8 实测）：

```yaml
- id: CR-2026-XXX-TASK-02
  slug: xxx
  status: pending
  depends-on: [CR-2026-XXX-TASK-01]      # 内联流式数组；可缺失；可带引号 ["ID"]
```

守卫只消费该字段，不新增字段、不改写形态；`task allocate` 生成的无 `depends-on` 条目按 D-5 视为无依赖。

#### 2.3 项③ — 无数据模型变化

`gate.checks[].detail[]` 的 JSON 结构层级与字段名不变（NFR-3）；仅 `isEmpty` 数组失败分支的 `actual` 元素内容被截断、`why` 改为条数指针。

#### 2.4 项④ — annotation 新增字段与 traceability 投影形态

**requirement annotation**（`review-annotations/requirement.yml`）新增两个向后兼容标量（NFR-2）：

```yaml
subject-file: change-requests/CR-2026-025/prd.md
subject-sha256: "<LF 规范化后全文的 SHA-256 全量 hex>"
```

**traceability 投影**（三 stage 同构，字段集与 review-requirement SKILL.md Step 4 既有模板对齐）：

```yaml
reviews:
  requirement:                      # tech-design / code 同构
    reviewer: "<identity(ws)>"
    verdict: pass | block
    reviewed-at: "<recordedAt>"     # 与 annotation、review-loop 同一时间戳（FR-17）
    blocker-count: <N>
    annotation: "change-requests/{cr}/review-annotations/<stage-file>"
    repair-target: write-requirement-prd | write-tech-design | implement-code
    review-loop:
      current-attempt: <N>
      max-attempts: <M>             # 运行时读自 pipeline JSON reviewLoop.maxAttempts
      attempts:
        - attempt: <N>
          reviewed-at: "<ts>"
          result: pass | block
          blocker-count: <N>
          repair-target: <同上>
```

`review-loop.yml` 形态完全不变（仍由 crctl 全量生成，B-16 后半段只是并入同批写入）。

### 3. 接口契约

#### 3.1 CLI 行为契约（无新增子命令/旗标，NFR-2）

| 命令 | 新增/变更行为 | 错误码 |
|---|---|---|
| `crctl task done <cr> --task <id>` | CAS 写入前校验目标 TASK 直接 `depends-on`（一跳） | `DEPENDS_ON_NOT_DONE`（detail 列出每个未完成前置的 `{id, status}`；message 末尾追加"若前置互相等待，检查 depends-on 是否成环"）；`DEPENDS_ON_UNKNOWN`（引用不存在于 `_index.yml` 的 TASK-ID）；非数组形态复用既有 `SCHEMA_INVALID`（不新增错误码，TD-BL-3） |
| `crctl gate / advance`（失败路径） | `isEmpty` 数组失败 detail：`actual` 保持数组、逐项 ≤120 字符截断；`why` 只给条数与证据文件指针 | 错误码不变（`GATE_BLOCKED` 等） |
| `crctl review-record <cr> --stage <s> [--bump-attempt]` | 一次写入 annotation + review-loop.yml（仅 bump 时）+ traceability 投影；`--stage requirement` 额外写 `subject-file`/`subject-sha256` | 新增结构化失败：`TRACE_SHAPE`（traceability CR-ID 不匹配/无法唯一定位），失败时三文件均不落盘、临时 payload 保留 |
| `crctl next <cr>`（仅 `drafting`） | 按 §4.4 决策表路由 | 只读命令，无错误码变化 |
| `node check-skill-matrix.mjs` | 新增检查 4：external 零引用点报红 | 退出码非 0，stderr 含技能名与声明 actor 列表 |

#### 3.2 调用方兼容承诺

- `actual` 数组类型不变，`.length`/索引取值安全（FR-13/US-6）。
- 缺 `subject-sha256` 的旧 annotation：`cmdNext` 维持改动前行为（PRD 存在即 `review-requirement`），不做历史迁移（FR-20⑤）。
- `equals` 分支、`runGateChecks` 顶层 check、`cmdAdvance` 汇总、`fail()` 输出形态零变化（D-9）。

### 4. 关键算法与流程

#### 4.1 项① — external 引用点扫描（检查 4）

```text
输入: externalByActor（§2.1）
scanRoots = [skills/, pipeline-templates/]
excludeDirs = {openwiki, old, node_modules, .git}           # 目录级排除（FR-2）
selfFiles = {agent-skill-matrix.yml, AGENT-SKILL-MATRIX.md} # 声明面不自证（FR-2）

files = walk(scanRoots) 中扩展名为 .md/.json 且路径不含 excludeDirs 的文件
for name in union(externalByActor.values()):
    refs = files.filter(f => readText(f).includes(name))   # 子串匹配，与 CR-2026-024 口径一致
    if refs.length == 0:
        errors.push(`[零引用点] external "${name}" 由 ${声明 actors 全列} 声明，但扫描范围内无任何引用点`)
```

要点：
- 粒度为**全局名级**（D-1）：任一文件命中即通过，不要求命中位于声明 actor 的 owns 面。
- 文件读入统一经一个 `readNorm(path)` 辅助（readFileSync → `replaceAll('\r\n','\n')`），现有三个解析段的读入点同步改经该函数（FR-3 行尾纪律）；三个逐行解析入口的 `split('\n')` 同步改为 `split(/\r?\n/)`（双保险，FR-3 明文要求）。
- **解析 shape 硬失败（TD-BL-2，纪律 #1/不变量 4）**：三段解析各补一条空结构守卫，匹配不到预期结构即 `console.error + process.exit(1)`，不得静默降级为空集合继续跑：
  - `_index.yml` 段：`activeSkills.size === 0` → 硬失败（仓库不可能无 active skill，必是解析失效）
  - `agent-skill-matrix.yml` 段：`Object.keys(ownsByActor).length === 0` → 硬失败（同上）
  - `AGENT-SKILL-MATRIX.md` 段：`## 主责矩阵` 切分结果缺失或表格行零命中 → 硬失败
  守卫只判"解析产物是否为空"，不新增对单个条目缺失的报错（那是检查 1/2 的既有职责，不重复）。
- 检查 1/2/3 判定逻辑零改动（新增的是解析层守卫，不是检查规则）；文件头注释"检查项"清单补第 4 条。
- 对应夹具进 F-3：CRLF/LF 同内容结果一致 + 三份输入各自空结构时退出码非 0（TD-BL-2 后半）。
- 复杂度：O(文件数 × 平均文本长 × external 名数)，tools 仓当前量级（<500 文件）毫秒级，无缓存需求。

#### 4.2 项② — `task done` 一跳依赖守卫

插入位置：`cmdTaskDone` 既有三项校验（status=developing / 文件存在 / —— TASK 存在与已 done 由 `editTaskDone` 内校验）之后、`casWrite` 之前。守卫读的是**同一份已读入的 `_index.yml` 文本**，不重复读盘：

```text
guardDependsOn(normText, taskId):          # normText = 已 CRLF 规范化的 _index.yml
    idx = parseYaml(normText)              # 复用既有 parseYaml（FR-8/NFR-8，禁新写解析）
    tasks = idx.tasks || []
    byId = Map(tasks.map(t => [t.id, t]))
    target = byId.get(taskId)              # 缺失由后续 editTaskDone 的 TASK_NOT_FOUND 兜底
    deps = target?.['depends-on']
    if deps == null or deps == []: return  # D-5：缺失/空数组 = 无依赖，放行
    unknown = deps.filter(d => !byId.has(d))
    if unknown.length: fail('DEPENDS_ON_UNKNOWN', ..., { unknown })
    notDone = deps.filter(d => byId.get(d).status != 'done')
    if notDone.length:
        fail('DEPENDS_ON_NOT_DONE', `...未完成前置 ${...}。若前置互相等待，检查 depends-on 是否成环`,
             { notDone: notDone.map(d => ({ id: d, status: byId.get(d).status })) })
```

要点：
- 一跳口径（D-6）：不做传递闭包、不检测环；A→B→A 与 A→A 夹具下环上成员直接前置互不 done，天然全部拒写，无遍历死循环（AC-10）。
- 带引号形态 `["ID"]` 由 `parseYaml` 的标量 unquote 路径消化（B-7 实测），测试向量⑤钉住（FR-10）。
- `depends-on` 解析出非数组形态（如标量）时复用既有 `SCHEMA_INVALID`（detail 指向该字段），**不新增 `DEPENDS_ON_SHAPE` 错误码**（TD-BL-3：PRD FR-7/FR-9 只批准 `DEPENDS_ON_NOT_DONE`/`DEPENDS_ON_UNKNOWN` 两个新增码，SDD 不单方面扩面）；F-4 补一条非数组形态向量。

#### 4.3 项③ — `isEmpty` 失败回显收敛

仅改 `evaluatePassCondition` 的 `isEmpty === true` 失败分支（L552-554）：

```js
const ITEM_MAX = 120;
// 纯函数：数组逐项截断；非字符串项原样保留；超长字符串追加 …(+N字)
function briefArray(v) {
  return v.map((x) => (typeof x === 'string' && x.length > ITEM_MAX)
    ? x.slice(0, ITEM_MAX) + `…(+${x.length - ITEM_MAX}字)` : x);
}
// 失败分支改为：
actual: Array.isArray(val) ? briefArray(val) : (val ?? null),
why: Array.isArray(val)
  ? `期望 ${fieldPath} 为空，实际 ${val.length} 条（详见 ${doc.path}）`
  : `期望 ${fieldPath} 为空，实际 ${JSON.stringify(val)}`,
```

改动处注释必须写明（FR-14）：**只封单条长度、不封条数**，条目极多时输出仍线性增长；全量原文唯一来源是 `file` 字段指向的 `review-annotations/{stage}.yml`。`equals` 分支与标量 `isEmpty`（非数组）路径保持现状（D-9）。

#### 4.4 项④ — 三账本一致写与 cmdNext 路由

**a. `cmdReviewRecord` 重构为「全校验 → 一次生成 → `casWriteMulti`」**（FR-17/D-11）：

```text
1. 前置校验（全部在写任何文件之前）：
   stage 映射合法 → 前置态合法（REVIEW_STAGE_EXPECT）→ payload schema（现有三项）
   → --bump-attempt 时 readAttempts 未 exhausted → traceability 若存在则结构校验（§4.4c）
   → CR-ID 一致性（traceability 头 cr-id == cr）
2. const recordedAt = nowIso()                # 一次生成，三账本共用
2b. attempts 历史合并（TD-BL-1：上一轮 result/blocker-count 的唯一来源是 trace 现有投影，
    review-loop.yml 只有 attempt/at/by，canonical annotation 会被覆盖，均不得作为历史数据源）：
    stageNode = trace 存在 ? parseYaml(traceText)?.reviews?.[stage] : undefined
    # TD-BL-4：区分两种情形，不得用宽泛空值兜底掩盖形状损坏：
    #   stageNode === undefined → 目标 stage 首次写入（合法，FR-18 定点新增）：oldAttempts = []
    #   stageNode 存在 → 读 stageNode['review-loop']?.attempts：键缺失 → []；
    #     存在但形状不合 → fail('TRACE_SHAPE')
    shape 校验（仅对存在的 attempts）：列表，且每项含 attempt/result/blocker-count/repair-target；不合 → fail('TRACE_SHAPE')
    bump 时：新条目 { attempt: current+1, reviewed-at: recordedAt, result: verdict,
              blocker-count, repair-target } 追加于尾部；若 oldAttempts 已含同 attempt 号
              → fail('TRACE_SHAPE')（不静默覆盖历史）
    非 bump 时：按 review-loop.yml 的 current-attempt 定位——命中则整条替换，未命中则追加
    （语义 = 刷新当前轮证据，不新增轮次）
    合并后的 attempts 列表进入投影块文本，再交 §4.4c 行级 upsert 渲染
3. 构造三份新文本：
   annotationText  ← 现有 lines 拼装 + requirement 时追加 subject-file/subject-sha256
   traceText       ← upsertReviewsStage(traceText 或最小骨架, stage, 投影块)
   loopText        ← bump 时：基于 readAttempts + recordedAt 生成的新轮次文本
                     非 bump 时：review-loop.yml 不写（保留原文），投影取其当前轮次
4. casWriteMulti([annotation(首建 expectedHash=null), trace, ...(bump?[loop]:[])])
5. 审计 + outbox（现有），删除临时 payload（现有）
```

实施要点：`bumpAttempt` 现读-写一体（L872-892 直接 `writeFileSync`）；拆出纯函数 `nextLoopText(loops, loopRef, recordedAt, identity)` 供 review-record 组装文本，`bumpAttempt` 本体改为「read → nextLoopText → write」组合，`crctl attempt` 独立子命令行为不变。这是消除"annotation 已写而 loop 写失败"半状态（B-16）的最小改法。

**b. `subject-sha256` 计算**（FR-19/D-12）：

```js
sha256(readFileSync(prdPath, 'utf8').replaceAll('\r\n', '\n'))  // 全量 hex
```

仅 `--stage requirement` 写入；tech-design/code 本次不新增摘要消费（PRD §7 排除项）。

**c. `upsertReviewsStage` 行级定点编辑**（FR-18，风格对齐既有 `matchEntryBlock`/`editTaskDone`）：

```text
输入: trace 原文（已 LF 规范化）或 null, stage, 投影块文本（2 空格基准缩进）
- null → 返回最小骨架：`cr-id: {cr}\nreviews:\n` + 投影块
- 顶层 cr-id 解析 != cr → fail('TRACE_SHAPE')
- 定位 `reviews:` 行（顶层，0 缩进）：
    无 → fail('TRACE_SHAPE')（不猜位置插入顶层键，避免破坏未知结构）
- 在 reviews 块内定位 `  {stage}:` 子块（2 缩进，到下一个 ≤2 缩进键为止）：
    命中 → 整块替换为新投影
    未命中 → 在 reviews 块末尾追加
- 其余行逐字节保留：经 LF 规范化后的**非目标文本片段**不变（tests/未知扩展段不受影响；AC-19 "字节不变"口径限定为规范化后文本，TD-SUG-2）
- 投影块文本本身由 §4.4a 步骤 2b 的 attempts 合并结果生成，本函数不关心轮次语义（TD-BL-1 分工：合并规则在 2b，行级渲染在本函数）
- 同一段内出现两个同名 stage 键 → fail('TRACE_SHAPE')（不静默择一）
```

**d. `cmdNext` drafting 决策表**（FR-20，替换 L2215-2218）：

| 优先级 | 条件 | 建议节点 | why 要点 |
|---|---|---|---|
| ① | `prd.md` 缺失 | `write-requirement-prd` | 现状保留 |
| ② | requirement annotation `verdict=block` 或 `blockers` 非空，且 `subject-sha256` == 当前 PRD 规范化摘要 | `write-requirement-prd` | blocker 条数 + annotation 路径 |
| ③ | 同上失败证据但摘要不同（PRD 已变化） | `review-requirement` | 证据已过时，需刷新 |
| ④ | 无失败证据（含 pass/缺失/无摘要旧证据） | `review-requirement` | 现状保留（兼容，FR-20⑤） |

"失败证据"定义 = `verdict=block` 或 `blockers.length>0`；`passAndClean` 语义不受影响。不使用 mtime（D-12）。

#### 4.5 端到端流程（项④闭环示意）

```text
review-requirement(block) → review-record 落盘(annotation 含 prd 摘要)
  → cmdNext: 摘要相同 → write-requirement-prd（回修）
  → PRD 实质修订 → cmdNext: 摘要不同 → review-requirement（重审）
  → review-record(pass, --bump-attempt) → 三账本同批落盘 → advance requirement-reviewing
```

### 5. 技术选型与替代方案

PRD D-1~D-12 已全部拍板，此处不复述理由，只补两个实施级选择：

| # | 选择 | 采纳 | 否决的替代 | 理由 |
|---|---|---|---|---|
| I-1 | `bumpAttempt` 拆读-算-写 | 拆出 `nextLoopText` 纯函数 | review-record 内直接调用现有 `bumpAttempt` | 现有实现读后立即落盘，无法满足"三文件同批 CAS"（FR-17）；拆分后 `crctl attempt` 组合调用行为不变 |
| I-2 | traceability 投影用行级定点编辑 | `upsertReviewsStage`（§4.4c） | parseYaml→改对象→序列化回写 | 违反不变量 3（禁通用序列化器）且全量重排打乱注释/字段序（§6 否决记录） |
| I-3 | 检查 4 用子串匹配 | `text.includes(name)` | 词法级精确匹配（word boundary） | 与 CR-2026-024 认定死声明的口径一致（FR-2）；精确匹配是另一取舍，PRD 已把"引用有效性"列为排除项 |

### 6. FR 到技术实现映射

| FR | 落点 | 测试锚点 |
|---|---|---|
| FR-1 | F-1 检查 4 + 头注释 | AC-1/AC-3，F-3 向量②④ |
| FR-2 | F-1 §4.1 扫描口径 | AC-2，F-3 向量①② |
| FR-3 | F-1 `externalByActor` + `readNorm` + 三段空结构硬失败守卫（§4.1，TD-BL-2） | F-3 向量③④⑤ + 空结构/CRLF 夹具 |
| FR-4 | F-5/F-6/F-7 三处声明面修订 | AC-4 |
| FR-5 | F-3 新建测试文件 | AC-6 |
| FR-6 | F-2 `guardDependsOn`（§4.2） | AC-7/AC-8，F-4 向量①② |
| FR-7 | F-2 缺失/空放行 + `DEPENDS_ON_UNKNOWN` | AC-9，F-4 向量③④ |
| FR-8 | F-2 复用 `parseYaml`，零新解析 | AC-10，F-4 向量⑤ |
| FR-9 | F-8/F-9/F-10 文档同步 | AC-11 |
| FR-10 | F-4 五类向量 | AC-15 |
| FR-11 | F-2 `ITEM_MAX`/`briefArray`（§4.3） | AC-12，F-4 项③向量①② |
| FR-12 | F-2 `why` 收敛（§4.3） | AC-12/AC-13 |
| FR-13 | F-2 数组类型保持 | AC-12，F-4 断言② |
| FR-14 | F-2 改动处注释 | AC-14 |
| FR-15 | F-4 五类向量 | AC-15 |
| FR-16 | F-2 `upsertReviewsStage` 三 stage 同一函数（§4.4c） | AC-19，F-4 项④向量①（含"trace 已有 requirement 投影、首次写 tech-design/code"向量，钉住 §4.4a 步骤 2b 的 stage 缺失合法分支，TD-BL-4） |
| FR-17 | F-2 全校验→单时间戳→attempts 历史合并（§4.4a 步骤 2b）→`casWriteMulti` | AC-20，F-4 向量②④ |
| FR-18 | F-2 骨架创建 + 定点替换 + 硬失败（§4.4c） | AC-21，F-4 向量③④ |
| FR-19 | F-2 `subject-file`/`subject-sha256`（§4.4b） | AC-22 |
| FR-20 | F-2 `cmdNext` drafting 决策表（§4.4d） | AC-22，F-4 向量⑤⑥⑦⑧ |
| FR-21 | F-4 八类向量 | AC-23 |
| FR-22 | 验证关卡（三件套 + 三测试文件） | AC-16 |
| FR-23 | commit 溯源标注 + 无本机绝对路径 | AC-17 |
| FR-24 | F-11 `ARCHITECTURE.md` §8 登记（§1.1 注：dir-graph.yaml 无脚本清单面） | AC-17 |

覆盖率：24/24。

### 7. 安全与性能考量

**一致性/安全**：
- 项④三账本写入沿用 `casWriteMulti` 三阶段语义；连续 rename 间的微秒级崩溃窗口继承 B-18 已接受的判定（§6 否决 WAL），不另造恢复机制。
- 所有新增失败路径走既有 `fail(code, message, extra)`，无裸异常；审计/outbox 挂接现有管道。
- 无新增外部输入面（全部本地文件读写）；`DEPENDS_ON_*` detail 只回显账本内已有 id/status，无信息扩散。

**性能**：
- 检查 4 扫描为 O(文件 × 文本 × 名称数)，tools 仓量级毫秒级，不引入缓存。
- `task done` 守卫复用 `cmdTaskDone` 已读入文本，只增一次 `parseYaml`（同文件），无新增 I/O。
- `cmdNext` 新增一次 annotation 读取与一次 PRD 摘要计算，仅 drafting 态触发，可忽略。

**边界条件清单**（全部进测试向量）：环（A→B→A / A→A）、带引号 TASK-ID、`depends-on` 缺失/空/悬空/非数组（`SCHEMA_INVALID`）、CRLF↔LF 等价、checker 三份输入各自空结构硬失败、traceability 缺失/含未知段/已有其他 stage 时首次写入目标 stage/CR-ID 不匹配/重复 stage/attempts 形状非法或重号、无摘要旧 annotation、CAS 注入失败三文件不动。

**已知文档同步缺口（非 blocker）**：`openwiki/architecture/agent-skill-matrix.md` 描述 checker 为"3 项检查"，项①上线后过时；openwiki 为文档镜像、非门禁面，实施期顺手同步一句，不单独成任务。

### 8. Prompt 采纳影响（必填：触及 crctl.mjs 子命令语义）

本 CR 不新增 crctl dispatch 分支、不触 `rules.json` deny 面，但**三个既有子命令的行为语义扩展**需以下 Skill 采纳核对（lint-prompts 机械抓不到此类）：

| # | Skill | 现状 | 应改为 |
|---|---|---|---|
| P-1 | `skills/develop/implement-code/SKILL.md` | prompt 层拓扑排序建议（CR-2026-024 落） | 补一句「依赖顺序由 `crctl task done` 机械强制」（FR-9，PRD 已列） |
| P-2 | `skills/requirement/review-requirement/SKILL.md` Step 4 | 指导模型手写 `traceability.yml#reviews.requirement` 投影（本 worktree 现存陈旧投影即该手工路径的实证漂移） | 改为「投影由 `crctl review-record` 同步写入，本步骤只做落盘后核对」 |
| P-3 | `skills/develop/review-tech-design/SKILL.md` Step 4（"更新 traceability.yml 并处理 status"） | 同上手写投影语义 | 同 P-2 改法 |
| P-4 | `skills/develop/review-code/SKILL.md` Step 5 | 明文要求向 `traceability.yml` 写入 `reviews.code` 引用（已实测 L103-105，TD-SUG-1） | 同 P-2 改法 |
| P-5 | `skills/shared/crctl/SKILL.md` 用途表 | `task done` 无守卫描述、`review-record` 无投影描述 | 补守卫与两错误码（FR-9）+ review-record 投影语义一句 |

P-2~P-4 的提示词修订随本 CR 代码同批提交（纯 prompt 修改不另开 CR，符合本仓 prompt 免 CR 规范），由 `lint-prompts --mode enforce` 兜底校验无 CONTRADICTS/STALE 残留。`crctl next` 消费方（最小 pipeline-runner 等）按输出字段消费，drafting 路由变化无需 prompt 适配。

### 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿：四项目标落点映射、`guardDependsOn`/`briefArray`/`upsertReviewsStage`/`cmdNext` 决策表设计、I-1~I-3 实施级选型、P-1~P-5 采纳清单；FR 覆盖 24/24 |
| 2026-08-09 | v0.2.0 | Ray | 技术评审 attempt-1 回修（3 blocker）：TD-BL-1 补 §4.4a 步骤 2b attempts 历史合并契约（唯一数据源 = trace 现有投影，shape 校验 + bump 追加/非 bump 按轮替换，禁从 review-loop.yml 臆造）；TD-BL-2 补 §4.1 三段解析空结构硬失败守卫与 `split(/\r?\n/)` 替换，夹具进 F-3；TD-BL-3 删除未授权的 `DEPENDS_ON_SHAPE`，非数组形态复用 `SCHEMA_INVALID` 并补向量。采纳 TD-SUG-1（P-4 确定为事实）、TD-SUG-2（AC-19 口径限定 LF 规范化后非目标片段）。 |
| 2026-08-09 | v0.3.0 | Ray | 技术评审 attempt-2 回修（1 blocker）：TD-BL-4 修正 §4.4a 步骤 2b——区分"目标 stage 缺失（合法，oldAttempts=[]，走 §4.4c 新增分支）"与"stage 存在但 review-loop/attempts 形状损坏（TRACE_SHAPE）"，不用宽泛空值兜底；FR-16 测试锚点与边界清单补"已有其他 stage 时首次写入"向量。 |

## 编码前质量门禁（v0.27 · CR-2026-026）

## SDD — review-dev-plan 编码前质量门禁技术设计

> 上游事实源：PRD v0.2.x（已审批）+ `docs/analysis/开发计划与TASK合并评审门禁方案.md`
> 目标代码仓：tools 仓自身（`../tools`），ARCHITECTURE.md 已存在（CR-2026-021 登记版），本 CR 按 §8 维护规则追加登记
> 口径：状态机 15 具名状态 + (new)；转移 25 声明 / 47 展开（本 CR 新增 2 声明后为 27 / 49，以实现期测试固化为准）

### 1. 架构概览

#### 1.1 模块边界

本 CR 改动分布在 tools 仓四个既有模块，全部复用现有写入路径，不新建模块：

| 模块 | 改动性质 | 关键文件 |
|---|---|---|
| Skill 提示词层 | 新增 1 个 + 修订 2 个 | `skills/develop/review-dev-plan/SKILL.md`（新）、`write-dev-plan/SKILL.md`、`write-dev-tasks/SKILL.md`（回修支持） |
| Pipeline 编排 | 插入 1 个 reviewLoop 节点 | `pipeline-templates/code-implementation.pipeline.json` |
| crctl 治理工具 | 映射扩展（零新增子命令） | `skills/shared/crctl/scripts/crctl.mjs`（REVIEW_STAGE_* 四映射 + 路由判定） |
| 门禁与状态机 | 声明变更 | `skills/shared/crctl/gates.json`、`dir-graph.yaml`（state_machine） |
| 索引与矩阵 | 登记 | `skills/_index.yml`、`agent-skill-matrix.yml` |
| 文档 | 同步 | `README.md`、`ARCHITECTURE.md`（§8 登记）、`skills/shared/crctl/SKILL.md`（用途表） |

#### 1.2 依赖图

```text
write-dev-plan ──> write-dev-tasks ──> review-dev-plan（新增，reviewLoop）──> push-progress ──> human_approval ──> approve-dev-start
                    （status → task-breakdown）        │
                                     ┌─────────────────┴─────────────────┐
                              PASS：保持 task-breakdown            普通 blocker：task-breakdown → tech-design-reviewed
                                                              上游设计疑点：task-breakdown → tech-design-review-pending
```

依赖方向遵守 ARCHITECTURE.md §4：Skill 层只经 crctl 读写账本；crctl 不依赖 Skill/Pipeline 定义；pipeline 的 `reviewLoop.passCondition` 运行时从 pipeline JSON 读取（PRD FR-10/B-15 同口径）。

#### 1.3 关键流程（双轨路由）

```text
review-dev-plan 评审完成
  ├─ verdict=pass && blockers=[]          → PASS：保持 task-breakdown，进入人工开发启动审批
  ├─ blockers 含 repair-target=write-tech-design（upstream-design blocker）
  │                                        → 上游疑点轨：task-breakdown --review-dev-plan:upstream-design-blocker--> tech-design-review-pending
  │                                          停止自动重放，人工走技术设计修订→评审→审批
  └─ 其余 blockers（repair-target=write-dev-plan）
                                           → 普通轨：task-breakdown --review-dev-plan:block--> tech-design-reviewed
                                             重放 write-dev-plan → write-dev-tasks → review-dev-plan（≤3 轮）
```

优先级（PRD FR-6b/D-14）：同一轮同时出现两类 blocker 时，上游疑点优先——进入上游轨，且本轮不消耗普通轨 attempt。

### 2. 数据模型

#### 2.1 阶段证据 `review-annotations/dev-plan.yml`

与既有 stage annotation 同构（verdict/blockers/dimensions/suggestions），crctl `review-record` 注入 reviewer/reviewed-at 后落盘。新增语义字段仅复用既有 `repair-target` 表达分流（PRD D-13）：

```yaml
verdict: pass | block
repair-target: write-dev-plan | write-tech-design   # 顶层可选字段，缺省 write-dev-plan（TD-BL-1 闭合）；pass 轨不写（v0.4.0）
blockers: []                    # 纯字符串列表，不解析结构化路由（D-13 修订）
dimensions:                     # 八类维度 + 元信息（对齐方案 §5.2 临时 payload）
  sdd-to-plan: pass | block
  plan-to-tasks: pass | block
  task-executability: pass | block
  dependency-topology: pass | block
  interface-contracts: pass | block
  acceptance-verifiability: pass | block
  scope-and-simplicity: pass | block
  risk-and-rollback: pass | block
  suggestion-policy: strict
  reviewer-model: "<model self report>"
suggestions: []
```

**关键设计（TD-BL-1 修订，v0.4.0 补充）**：`repair-target` 是 dev-plan payload/annotation 的**顶层可选字段**：缺省 `write-dev-plan`；`verdict=block` 且显式 `repair-target: write-tech-design` 时走上游疑点轨。**pass 轨不落 repair-target**（annotation 与 traceability 投影顶层省略，v0.4.0 code review suggestion-1 落地；attempts 轮次历史条目保留缺省值，schema 稳定）。blockers 保持纯字符串列表，**不在字符串中解析结构化路由**。crctl 对 `--stage dev-plan` 校验该字段枚举（缺省或 ∈ {`write-dev-plan`, `write-tech-design`}），并将解析后的值写入 canonical annotation 顶层与 traceability 投影（替代既有 `REVIEW_REPAIR_TARGETS` 默认值注入：dev-plan stage 下 payload 显式提供时用之，否则用映射默认值）。不新增 blocker-type 字段。

#### 2.2 临时 payload

`.crctl/tmp/review-dev-plan.yml`（非受控路径，`--from` 缺省即此路径），LLM 只写判断，crctl 负责 schema 校验/CAS/身份注入/删除。

#### 2.3 轮次与追溯（零新增账本）

- `review-loop.yml`：`review-record --bump-attempt` 级联写 `loops.review-dev-plan`（复用 025 的 review-loop 记账）。
- `traceability.yml#reviews.dev-plan`：由 crctl 通用投影路径渲染（复用 025 交付的 `renderReviewsStageBlock` + 定点编辑），字段集与 requirement/tech-design/code 一致（reviewer/verdict/reviewed-at/blocker-count/annotation/repair-target/review-loop）。
- **attempt 计费规则**（PRD FR-6b/FR-7，TD-BL-2 修订）：路由判定**发生在 bump 之前**——`cmdReviewRecord` 在读取 payload 后、执行 review-loop 读取/校验/递增之前，先解析顶层 `repair-target` 得出 route（pass/normal/upstream）。NORMAL/PASS 走既有 `--bump-attempt` 记账（current-attempt+1、attempts 追加该轮）；UPSTREAM **跳过 bump**——review-loop.yml 写入块整体不执行（`if (bump)` 分支跳过，文件字节不变），仅写 annotation 与 traceability 投影（attempt=当前值、attempts 保持既有历史），三账本与 audit 保持同批一致（NFR-2）。

### 3. 接口契约

#### 3.1 crctl.mjs — REVIEW_STAGE 四映射扩展（PRD FR-14）

在既有映射（`crctl.mjs:1413-1424`）追加：

```js
REVIEW_STAGE_FILES['dev-plan']    = 'dev-plan.yml';
REVIEW_STAGE_LOOPS['dev-plan']    = 'review-dev-plan';
REVIEW_STAGE_EXPECT['dev-plan']   = ['task-breakdown'];
REVIEW_REPAIR_TARGETS['dev-plan'] = 'write-dev-plan';
```

- `review-record --stage dev-plan`：走既有 `cmdReviewRecord` 通用路径（schema 校验 → traceability 读/合并 → casWriteMulti 三账本），零分支特化。
- `--stage dev-plan` 的 expect 前置态为 `task-breakdown`（与 write-dev-tasks 推进到的状态一致；评审 PASS 不推进、BLOCK 由 advance 级联，因此 expect 校验在 review-record 入口检查当前 status=task-breakdown）。

#### 3.2 路由判定（crctl.mjs，PRD FR-6/FR-6a/FR-6b，TD-BL-1/2 修订）

**判定发生在 `cmdReviewRecord` 内部、bump 之前**。新增纯函数 `resolveDevPlanRoute(payload)`：

```text
输入：临时 payload（verdict + 顶层 repair-target）
判定：
  1. verdict=pass → PASS
  2. verdict=block 且 payload.repair-target === 'write-tech-design' → UPSTREAM
  3. 其余 → NORMAL
输出：{ route: 'pass' | 'upstream' | 'normal' }
```

`cmdReviewRecord` 对 `--stage dev-plan` 的执行顺序（既有通用流程内分支）：

```text
1. 读取临时 payload（.crctl/tmp/review-dev-plan.yml）并做 schema 校验
   （verdict 枚举 / blockers 列表 / dimensions 非空映射 / repair-target 枚举校验：缺省或 ∈ {write-dev-plan, write-tech-design}）
2. resolveDevPlanRoute(payload) → route
3. route === 'upstream'：跳过 bumpAttempt 级联（review-loop current-attempt 不递增、attempts 不追加），
   仅写 canonical annotation（repair-target=write-tech-design）与 traceability 投影（attempt=当前值）
   route === 'normal' 或 'pass'：走既有 --bump-attempt 记账（attempt+1、attempts 追加该轮）
4. casWriteMulti 统一写三账本（NFR-2 同批语义）
```

- 路由结果（route + repair-target）写入 canonical annotation 顶层，随三账本投影。
- 调用方（pipeline/Skill）按 route 推进：PASS → 人工审批；UPSTREAM → `advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker`；NORMAL → `advance --to tech-design-reviewed --trigger review-dev-plan:block`。
- 同轮并存时 UPSTREAM 优先（FR-6b）：payload 顶层 repair-target=write-tech-design 时，普通 blocker 并入 suggestions 摘要展示，路由仍为 UPSTREAM；不消耗普通 attempt（步骤 3）。
- **不解析 blockers 字符串**：LLM 在 payload 顶层写 `repair-target: write-tech-design` 表达上游疑点（Skill 文档定义该写法），crctl 只校验枚举、不解析字符串（D-13）。

#### 3.3 gates.json 变更（PRD FR-10/FR-11/FR-12）

**approvalStages.dev-start**（现状：仅 requireFiles plan.md + tasks/_index.yml）：

```json
"dev-start": {
  "to": "developing",
  "trigger": "approve-dev-start",
  "expect": ["task-breakdown"],
  "approvalSection": "development-start",
  "evidence": {
    "$default": "change-requests/{cr}/review-annotations/dev-plan.yml",
    "plan": "change-requests/{cr}/plan.md",
    "task-index": "change-requests/{cr}/tasks/_index.yml"
  },
  "passCondition": { "pipeline": "code-implementation", "nodeRef": "review-dev-plan" },
  "requireFiles": [
    "change-requests/{cr}/plan.md",
    "change-requests/{cr}/tasks/_index.yml"
  ]
}
```

- `passCondition` 复用既有解释器（运行时读 pipeline JSON 的 reviewLoop.passCondition：verdict=pass && blockers=[]）。
- `evidence` 三键 → canonical evidence digest 覆盖 annotation/plan/task-index（FR-11）；审批后修改三者触发既有 EVIDENCE_DRIFT。TASK-*.md 正文不在 digest（D-9/FR-11 首版边界，AC-12a）。

**statusGates.developing**（现状：仅 approval 一项）→ 按 FR-12 补全（实现期修订：passCondition 引用 `stage=dev-start` 而非 `dev-plan`——`evaluatePassCondition` 从 `approvalStages[stage]` 取 stageCfg（pipeline+evidence），dev-plan 不在 approvalStages（自动评审 stage 非人工审批）；dev-start 的 approvalStages 配置含 evidence 三键 + passCondition，完全复用同一判据与证据）：

```json
"developing": [
  { "type": "fileExists", "path": "change-requests/{cr}/plan.md" },
  { "type": "fileExists", "path": "change-requests/{cr}/tasks/_index.yml" },
  { "type": "globNonEmpty", "dir": "change-requests/{cr}/tasks", "pattern": "^TASK-\\d+.*\\.md$" },
  { "type": "passCondition", "stage": "dev-start" },
  { "type": "approval", "section": "development-start" }
]
```

全部使用现有门禁类型（fileExists/globNonEmpty/passCondition/approval），零新增解释器（FR-12）。

**reviewLoops** 追加：`"review-dev-plan": { "pipeline": "code-implementation" }`。

#### 3.4 状态机变更（dir-graph.yaml，PRD FR-13）

追加两条声明（不新增具名状态）：

```yaml
- { from: task-breakdown, to: tech-design-reviewed, trigger: "review-dev-plan:block -> write-dev-plan" }
- { from: task-breakdown, to: tech-design-review-pending, trigger: "review-dev-plan:upstream-design-blocker" }
```

- 既有 `task-breakdown → tech-design-reviewed`（approve-dev-start:reject）与本 CR 新增的 block 转换目标相同，状态机允许同 from/to 多 trigger。
- 转移口径：25 → 27 声明；47 → 49 展开（wildcard 展开数按既有展开器计算，实现期测试固化，PRD B-7/D-3 已声明）。

#### 3.5 pipeline 节点插入（code-implementation.pipeline.json，PRD FR-1）

在 node-2（write-dev-tasks）之后、node-3（push-progress）之前插入 reviewLoop 节点：

```json
{
  "id": "00000000-0000-0000-0015-000000000099",
  "kind": "skill",
  "label": "开发计划与 TASK 合并评审",
  "ref": "review-dev-plan",
  "prompt": "…（读取 sdd.md/plan.md/tasks/_index.yml/TASK-*/review-annotations/sdd.yml，八类维度评审，判断写 .crctl/tmp/review-dev-plan.yml，经 crctl review-record --stage dev-plan --bump-attempt 落盘；按 §3.2 路由：pass→保持；block 普通轨→advance --to tech-design-reviewed --trigger review-dev-plan:block；上游疑点轨→advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker；输出 verdict/blockers/repair-target/attempt…）",
  "reviewLoop": {
    "repairRef": "write-dev-plan",
    "feedbackInput": "review_feedback",
    "attemptInput": "self_repair_attempt",
    "replayPolicy": "rerun-listed-nodes-in-order",
    "replayNodes": [
      { "ref": "write-dev-plan", "purpose": "repair-plan" },
      { "ref": "write-dev-tasks", "purpose": "regenerate-tasks" },
      { "ref": "review-dev-plan", "purpose": "rerun-current-review" }
    ],
    "maxAttempts": 3,
    "passCondition": {
      "allOf": [
        { "path": "verdict", "equals": "pass" },
        { "path": "blockers", "isEmpty": true }
      ]
    },
    "onBlock": "route-to-repair-node"
  },
  "onFail": "abort",
  "timeoutMinutes": 30
}
```

后续节点（push-progress / human_approval / approve-dev-start / …）顺序后移；UUID 按仓库规则分配（此处为示意值）。

**onBlock 分流契约（TD-BL-3 修订）**：`onBlock: route-to-repair-node` 对 dev-plan 节点按 route 二分：
- NORMAL：按 `replayNodes`（write-dev-plan → write-dev-tasks → review-dev-plan）重放；节点 prompt 先 `advance --to tech-design-reviewed --trigger review-dev-plan:block`（embedded）；
- UPSTREAM：**不进入 replayNodes**——节点 prompt 执行 `advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker`（embedded）后，输出 `upstream-design-blocker` 并 **abort 当前 code-implementation pipeline**（onFail: abort），等待人工走 architecture-design 技术设计修订链路；不在本 pipeline 内消耗 attempt（§2.3/§3.2 步骤 3）。

### 4. 关键算法与流程

#### 4.1 普通轨重放闭环（FR-6/FR-8/FR-9）

```text
review-dev-plan BLOCK（普通轨）
  → advance --to tech-design-reviewed --trigger review-dev-plan:block（embedded，cr.md 状态落盘）
  → reviewLoop 重放：write-dev-plan（消费 review_feedback/self_repair_attempt，输出 fixed-blockers）
    → write-dev-tasks（重新生成 TASK 与 _index.yml，不保留已被删除的旧 TASK）
    → review-dev-plan（重新评审，attempt+1）
  → ≤3 轮；耗尽仍 block → LOOP_EXHAUSTED 停止，不进入 human approval（FR-7/AC-13）
```

空转防线（FR-9）：首版不做 blocker→产物 diff 对账器；下一轮 review-dev-plan 重新读取实际产物，未修复的问题继续 BLOCK（AC-13 兜底）。

#### 4.2 上游疑点轨（FR-6a/AC-8a，TD-BL-1 修订）

```text
发现 SDD 自相矛盾/不可实施/需改已审批设计
  → payload 顶层写 repair-target: write-tech-design（blockers 保持纯字符串）
  → review-record 内 route=upstream：不 bump，annotation 落 repair-target=write-tech-design
  → 节点 prompt advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker
  → abort code-implementation pipeline
  → 人工走既有技术设计修订（write-tech-design 回修）→ review-tech-design → approve-tech-design
  → 审批通过后重新进入 plan → TASK → review（既有 tech-design-reviewed → task-breakdown 转换）
```

本节点不修改/不覆盖 `review-annotations/sdd.yml`（US-5）；`tech-design-review-pending` 是既有具名状态（dir-graph L219-222 已有转换），复用其语义。

#### 4.3 attempt 计费（FR-6b/FR-7/AC-8b，TD-BL-2 修订）

- 路由判定在 bump 之前（§3.2 步骤 2-3）：NORMAL/PASS 走既有 `--bump-attempt`（current-attempt+1，attempts 追加该轮）；UPSTREAM **跳过 bump**——review-loop.yml 不写（字节不变，见 §2.3），仅写 annotation + traceability 投影（attempt=当前值、attempts 保持既有历史）。
- PASS 与既有 stage 一致：bump 一次，attempts 保留 pass 记录（AC-9：第 2 轮通过时同时保留第 1 轮 block 与第 2 轮 pass）。
- UPSTREAM 后的普通回修 attempt 从当前值继续计费（AC-8b：不递增后续普通 dev-plan 回修 attempt）。

#### 4.4 evidence digest（FR-11）

复用既有 `canonicalEvidenceDigest`：按 approvalStages.dev-start.evidence 映射对 dev-plan.yml/plan.md/tasks/_index.yml 计算规范化摘要（CRLF→LF 后哈希），写入 approval.yml#development-start.evidence-digest；审批后任一文件变更 → EVIDENCE_DRIFT（AC-12）。

### 5. 技术选型与替代方案

| 决策 | 本 SDD 选择 | 被否方案与理由 |
|---|---|---|
| 分流表达 | 复用 `repair-target` 字段（D-13） | 新增 `blocker-type`/`upstream-design` 专用字段：改 annotation schema，破坏既有 stage 同构；且 CR-2026-025 已让 repair-target 进三账本投影，零新增字段即达可观测 |
| 上游轨目标态 | `tech-design-review-pending`（既有） | 新增 `plan-reviewing` 类状态：违反 D-3 不新增状态；既有待评审态语义完全匹配 |
| 评审落盘 | 复用 `review-record` 通用路径 | 为 dev-plan 特写落盘实现：违反 ARCHITECTURE.md §4 依赖方向与"通用实现"原则，且 025 已交付通用三账本能力，特化即重复 |
| 轮次上限 | 3 轮（与 requirement/tech-design/code 一致） | 无上限/更高上限：既有 reviewLoop 契约统一为 3，特例需专门文档说明 |
| 首版 TASK 正文 freshness | 不做（D-9/D-12） | 为 dev-plan 特化 glob 摘要协议：AC-12a 显式排除；通用多文件 digest 留跨 stage 统一方案 |
| 评审模型 | 同一模型可执行，reviewer-model 留痕（方案 §10.1） | 模型选择暂停节点：新增人工节点类型，违反 NFR-5 |

### 6. FR 到技术实现映射

| FR | 实现落点 |
|---|---|
| FR-1 | §3.5 pipeline 节点插入（UUID 按仓库规则分配，后续节点顺序后移） |
| FR-2 | §3.5 节点 prompt：强制输入清单（sdd.md/plan.md/tasks/_index.yml/TASK-*/review-annotations/sdd.yml）+ PRD 抽查边界（D-15） |
| FR-3 | review-dev-plan/SKILL.md 八类维度定义 + §2.1 dimensions schema（含估算一致性边界：结构性问题时才 blocker） |
| FR-4 | §3.1 映射扩展 + review-record 通用路径（三账本同批，025 FR-16/17 复用） |
| FR-5 | §3.3 passCondition + pipeline 节点 prompt（PASS 保持 task-breakdown） |
| FR-6 | §3.2 NORMAL 路由 + §3.4 转换 1 + §4.1 重放闭环 |
| FR-6a | §3.2 UPSTREAM 路由（repair-target 顶层字段）+ §3.4 转换 2 + §4.2 人工链路 |
| FR-6b | §3.2 步骤 2-3 优先级判定（bump 前路由）+ §4.3 attempt 计费分支 |
| FR-7 | §3.5 maxAttempts=3 + §4.3 计费 + LOOP_EXHAUSTED 语义 |
| FR-8 | write-dev-plan/write-dev-tasks SKILL 修订：review_feedback/self_repair_attempt 输入 + fixed-blockers 输出 |
| FR-9 | §4.1 空转防线（下一轮重读产物兜底）+ SKILL 固定措辞 |
| FR-10 | §3.3 approvalStages.dev-start（evidence + passCondition + requireFiles） |
| FR-11 | §3.3 evidence 三键 + §4.4 canonicalEvidenceDigest |
| FR-12 | §3.3 statusGates.developing 五条件（全部既有门禁类型） |
| FR-13 | §3.4 两条转换（口径 25→27 声明 / 47→49 展开，测试固化） |
| FR-14 | §3.1 四映射 + §3.2 路由判定（含 repair-target 枚举校验）+ gates.json reviewLoops 追加 |
| FR-15 | 新建 `skills/develop/review-dev-plan/SKILL.md`（§3.5 prompt 为骨架） |
| FR-16 | `skills/_index.yml` 登记 + agent-skill-matrix.yml：dev-agent owns、quality-reviewer-agent can-call |
| FR-17 | README/ARCHITECTURE §8 登记（crctl 命令面语义扩展 + pipeline 结构变化 + 状态机口径变化） |
| FR-18 | 既有四 stage（requirement/tech-design/write-test-report/code）回归测试（AC-14） |
| FR-19 | §8 测试设计 + check-skill-matrix/check-agents-contract/lint-prompts 全绿 |
| FR-20 | commit message 溯源标注（方案文档 + CR 编号） |

### 7. 安全与性能考量

#### 7.1 安全控制点

- **审计**：review-record/advance 全部走既有 `.crctl/audit.log` 审计路径，无旁路（ARCHITECTURE.md §5 不变量 2）。
- **无越权写入**：本 CR 不触碰 sdd.yml/approval.yml 既有段；dev-plan annotation 仅由 review-record 写（模型禁手写，guard deny 面不变）。
- **人工审批无旁路**：dev-start 审批仍只经 `crctl approve`（TTY/签名），本 CR 只升级其校验（不变量 7 保持）。

#### 7.2 性能

- 评审读取文件数：sdd.md + plan.md + tasks/_index.yml + TASK-*（线性于 TASK 数），与 review-code 同量级，无新增热点。
- crctl 侧零新增解析器：路由判定只读已解析的 annotation 对象（O(blockers)），无额外文件 IO。
- traceability 定点编辑复用 025 的行级函数，单 stage 写入 O(文件行数)。

#### 7.3 边界与一致性（行尾纪律 NFR-3）

- 所有涉及哈希/解析的路径（evidence digest、payload 读取、traceability 编辑）沿用 `\r\n → \n` 规范化 + `split(/\r?\n/)` + 硬失败（不变量 4），本 CR 新增代码零例外。

### 8. Prompt 采纳影响（必填：本 CR 触及 crctl REVIEW_STAGE 映射与 gates.json）

本 CR 扩展 `crctl review-record` 的 stage 面（新增 dev-plan）与 `gates.json` 的 dev-start/developing 门禁。需要同步采纳的 Skill/文档清单：

| Skill / 文档 | 现状 | 应改为 |
|---|---|---|
| `skills/develop/write-dev-plan/SKILL.md` | 不消费 review_feedback；写 plan.md 后无回修输出 | 接受 `review_feedback`/`self_repair_attempt` 输入，逐条修复并输出 `fixed-blockers`（FR-8/FR-9） |
| `skills/develop/write-dev-tasks/SKILL.md` | 推进 task-breakdown 后即完成；不消费 review_feedback | 同上；回修时重新生成 TASK 与索引，不保留已删旧 TASK（FR-8） |
| `skills/develop/approve-dev-start/SKILL.md` | 只校验 plan/tasks 文件存在 | 补充：dev-start 审批前须有 dev-plan.yml 且 passCondition 通过；evidence digest 覆盖三键（FR-10/FR-11 的调用方表述） |
| `skills/shared/crctl/SKILL.md` | 用途表无 dev-plan stage | 用途表补 `review-record --stage dev-plan`、两条新 trigger（review-dev-plan:block / :upstream-design-blocker）、reviewLoops 映射（FR-14 配套文档） |
| `skills/develop/implement-code/SKILL.md` | 无涉及 | 不需要改（普通轨重放不含 implement-code；上游轨走既有技术设计链路）——仅确认不回归 |
| `README.md` | 节点流程无 review-dev-plan | 更新 code-implementation 流程、受控评审 stage 列表、状态转换说明（FR-17） |
| `ARCHITECTURE.md` | §3 代码地图无 dev-plan | §8 维护规则登记本 CR（crctl stage 扩展 + pipeline 结构变化 + 状态机口径 27/49） |

### 9. 测试设计（对应 PRD §5 AC）

| 测试文件 | 覆盖 |
|---|---|
| `crctl.test.mjs`（追加向量） | ① REVIEW_STAGE 映射含 dev-plan 且 `review-record --stage dev-plan` 在 task-breakdown 落盘三账本（pass 轨省略 repair-target，suggestion-1）；② repair-target schema 校验（缺省→write-dev-plan、显式 write-tech-design→upstream、非法值→SCHEMA_INVALID 且三账本不变）；③ UPSTREAM 路由判定：payload 顶层 repair-target=write-tech-design → upstream 且 bump 跳过（review-loop.yml 字节不变——current-attempt 不递增、attempts 不追加；traceability 投影同语义，AC-8b）；④ NORMAL/PASS 走既有 bump（attempt+1，普通 block 轨缺省 repair-target 落盘）；⑤ 同轮并存时 UPSTREAM 优先（普通项进 suggestions 摘要）；⑥ dev-start approval 门禁升级生效——grant 非 TTY 通过路径（evidence+passCondition）放行到 developing / passCondition 不过 → GATE_BLOCKED 且不写 approval 段（AC-10，v0.4.0 自动化）；⑦ developing 目标态删 TASK-*.md 或篡改 approval → 门禁拦截，补齐后放行（AC-11a，v0.4.0 自动化）；⑧ evidence digest 覆盖三键，改 dev-plan.yml 后 EVIDENCE_DRIFT（AC-12，v0.4.0 自动化）；⑨ 三轮 BLOCK → LOOP_EXHAUSTED（AC-13，v0.4.0 自动化）；⑩ requirement/tech-design/write-test-report/code 四 stage 回归（AC-14，既有用例全量覆盖） |
| `lint-prompts.test.mjs` / `check-skill-matrix.mjs` / `check-agents-contract.mjs` | 新 Skill 登记、dev-agent owns + quality-reviewer-agent can-call、prompt 无漂移（AC-15/AC-15a） |
| 状态机断言（crctl.test.mjs 内） | 新增两条转换可 advance；口径 27 声明 / 49 展开断言（PRD B-7） |

### 10. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 双轨路由判定歧义（blockers 混写两类） | FR-6b 优先级硬编码 + AC-8b 测试固化；Skill 文档规定上游疑点 blocker 写法 |
| 既有 approve-dev-start 审批流程回归 | FR-18/AC-14 回归测试；gates 变更只增条件不删条件 |
| 状态机口径漂移（25→27 声明的连锁） | PRD B-7 已声明；实现期测试固化精确展开数；ARCHITECTURE §8 登记 |
| 评审轮次空转（回修不改产物） | FR-9 下一轮重读兜底 + AC-13 轮次上限；不引入对账器（YAGNI） |
| traceability 投影与既有三 stage 冲突 | 复用 025 定点编辑（AC-19 语义：非目标段字节保留），测试断言 |

回滚：本 CR 全部改动可经 revert 单次提交回退；gates.json 与 dir-graph.yaml 声明为可逆追加（不删既有条目），无数据迁移。

### 11. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿（基于 PRD v0.2.x + 实测代码基线；双轨路由/attempt 计费/gates 三处变更详设） |
| 2026-08-09 | v0.2.0 | Ray | 技术评审 attempt-1 回修（3 blocker，TD-BL-1/2/3）：repair-target 定为 dev-plan payload/annotation 顶层可选字段（枚举校验，blockers 不解析字符串）；路由判定移到 cmdReviewRecord 内部 bump 之前，UPSTREAM 跳过 bump；pipeline onBlock 分流契约（NORMAL replay / UPSTREAM abort code-implementation） |
| 2026-08-09 | v0.3.0 | Ray | 实现期偏差修订（TASK-01~07 落地后回写）：① §3.3 developing 门禁 passCondition 引用改为 `stage=dev-start`——`evaluatePassCondition` 仅从 `approvalStages[stage]` 取 stageCfg，dev-plan 不在 approvalStages（自动评审 stage），dev-start 配置含同一 evidence/passCondition 完全复用；② §2.3/§4.3 明确 UPSTREAM 时 review-loop.yml 写入块整体跳过（字节不变），不只 traceability 不递增；③ §9 测试③补 review-loop.yml 字节不变断言（测试实际落地为 5 向量 + 加强断言，116 例全绿） |
| 2026-08-09 | v0.4.0 | Ray | code review suggestion-1/2 落地（实现期修订，d395d04）：① §2.1 pass 轨不落 repair-target（annotation 与投影顶层省略，attempts 轮次历史保留缺省，schema 稳定）；② §9 ⑥-⑩ 门禁向量自动化——⑥/⑥b grant 非 TTY 通过/拦截、⑦ developing 目标态删 TASK 拦截+补齐放行、⑧ 篡改 dev-plan.yml → EVIDENCE_DRIFT、⑨ 三轮 BLOCK → LOOP_EXHAUSTED，⑩ 由既有用例全量覆盖（crctl.test 121 例全绿 + lint 19 + checker 8）；结论：不影响既有判据（pass 轨无回修消费方；门禁判据与证据来源不变） |
| 2026-08-09 | v0.4.1 | Ray | 自举例外登记：CR-2026-026 为 review-dev-plan 落地 CR，其 plan/TASK 评审发生于工具落地前（实现前分析型评审，verdict=pass），重评审时因 developing 门禁要求 dev-plan.yml 且 CR 已越过 task-breakdown（review-record 前置态不可达），经用户拍板手工补落盘回顾性证据 `review-annotations/dev-plan.yml`（文件头注释声明例外；review-loop/traceability 不同步，无轮次可计）；仅适用于本演练 CR，工具侧不做豁免——后续 CR 一律经 review-record 落盘 |

## tools 流程优化 Phase 0+1 — 基线事实统一与正确性修复（状态机口径 27/49、approve 原子提交、TASK 归档门禁、archive 原子化、终态查询、review-record 深化）（v0.28 · CR-2026-027）

## SDD — CR-2026-027：tools 流程优化 Phase 0+1

### 1. 架构概览

#### 1.1 改动面分层

本 CR 的目标代码仓是 **tools 仓自身**（修改 `crctl.mjs`、Skills、`ARCHITECTURE.md`）与 workspace 声明层，按 v2 方案 §5.2/§6 的最小修改集合落地：

```text
workspace 声明层（ai-first-platform-docs 仓）
  AGENTS.md                  # 状态机口径 25/47 → 27/49（工程纪律 #2 同步）
  dir-graph.yaml             # repositories 新增 tools（FR-5/FR-15 bootstrap 第一步）
  docs/analysis/tools流程步骤优化v2.md  # 删除旧方案 command module 与通用上下文命令描述（FR-6）
  CONTEXT.md                 # 已随注册前置提交修正，本 CR 复核不动

tools 文档层（tools 仓）
  ARCHITECTURE.md            # §3/§5 状态机口径 27/49；§4 crctl-Pipeline 依赖描述修订（FR-3）；
                             # §3 确认 crctl 单文件（FR-2）；§8 登记本 CR；指标基线固化（FR-7）

tools 执行层（tools 仓 crctl.mjs + crctl.test.mjs）
  approve 原子提交（FR-8）        # 内部 helper，不新增子命令
  archived TASK 门禁修复（FR-9）  # 修复 deliveryIndexComplete checker 实现，不改 gates.json
  幽灵条目迁移清理（FR-10）      # 扩展 cmdMigrateBacklog，不新增独立脚本目录
  archive-move 原子化（FR-11/FR-12 账本面）  # 事件 + 三账本同一 CAS
  终态只读 resolver（FR-12 查询面）          # status/next 专用
  review-record 输出深化（FR-13） # 返回 files/attempt/route/repairTarget
  inbox-emit 空 to 硬失败（FR-11）# BAD_ARGS

tools Skill 提示词层（tools 仓）
  merge-feature-branch/SKILL.md  # 删除 tools 隐藏特例（FR-5）
  四个 review Skill               # 删除 traceability 二次读取（FR-13）
  cr-archive/SKILL.md            # 同步 archive-move 三账本契约（FR-4/FR-11）
```

#### 1.2 关键流程变更（前后对比）

| 流程 | 现状 | 目标 |
|---|---|---|
| approve | 写 approval.yml（一提交）→ cmdAdvance 只 stage cr.md（另一提交）；失败可能单文件半状态 | 预检 → 内存生成两文件 → casWriteMulti → 单次 commit → 成功后发 status outbox（FR-8） |
| 归档 | embedded advance 到 archived → inbox-emit 独立发事件（中文 JSON 转义失败即永久丢失）→ archive-move 只写 backlog/history | embedded advance → archive-move 内存构造事件 + backlog/history/index 三文本 → 同一 casWriteMulti → 成功后发 archive outbox（FR-11） |
| 归档查询 | resolveCrState 强制读 backlog → CR_STATUS_NOT_FOUND | status/next 在 active 未命中时走终态只读 resolver（history final-status 权威，FR-12） |
| TASK 门禁 | deliveryIndexComplete 空 doneIds 放行 | 五步校验：index 存在 → tasks 非空 → 全 done → delivery index → 缺/空不得解释为 no-task（FR-9） |

#### 1.3 执行顺序（实施期依赖）

1. **bootstrap（FR-15）**：workspace `dir-graph.yaml` 先加入 tools repo → 在 `../tools` 仓从 `custom/main` 创建 `requirement/CR-2026-027` worktree（`.rayai-worktrees/tools/requirement/CR-2026-027`，bucket = repo.id）→ 此后全部 tools 改动在该 worktree 提交，禁止直写 custom/main。**调用根固定**：`crctl worktree-path` 一律以 **AI First Platform 主工作区**为 `--workspace` 解析（不从 knowledge-base CR worktree 以 `--workspace .` 调用，避免得到嵌套 `.rayai-worktrees` 路径）；**基线固定**：worktree 创建时记录 `bootstrap-base-sha`（= custom/main HEAD），写入实施记录与 AC-22 验收断言，避免创建与后续 fetch 之间基线含义漂移。
2. Phase 0 文档统一（FR-1~FR-7）→ 3. Phase 1 执行层（FR-8~FR-14）→ 4. 五项最小验证（FR-14/AC-19）。

### 2. 数据模型

#### 2.1 `_index.yml` 终态字段（FR-4/FR-11）

`archive-move` 更新 CR 对应条目，只写三个字段（D-2，全生命周期轻量目录）：

```yaml
status: archived | rejected | withdrawn
archived-at: "<ISO8601+08:00>"
writeback-spec-id: "<spec-id>"   # 有则写，无则不写
```

不复制 history 详情、不新增 `history-ref`、不删除条目；查询事实源不变（仍为 `_backlog.yml + _history.yml` + cr.md）。

#### 2.2 archive event 载荷（FR-11）

归档事件与归档移动是同一业务事实，随三账本 CAS 同批写入。事件条目写入 **history 条目**的 notify-log（CR 已移出 backlog，backlog 无宿主条目），复用 `editInboxEmit` 的日志行格式（提取为共享行生成函数）：

```yaml
- at: "<ISO8601+08:00>"
  event: archived | rejected | withdrawn
  to: ["<owners.requirement.id>", "<owners.development.id>", "<owners.test.id>"]  # 去重后
  payload:
    final-status: archived
    archive-reason: "<reason>"          # 中文原文，不经 Shell 转义
    writeback-spec-id: "<spec-id>"      # 可选
    archived-at: "<ISO8601+08:00>"
```

收件人规则（D-10）：优先 `owners.{requirement,development,test}.id` 去重；条目缺 `owners` 时回退顶层 `owner`；最终为空 → CAS 前 `ARCHIVE_RECIPIENTS_MISSING`。不新增 submitter/reviewer 字段。

#### 2.3 终态查询最小契约（FR-12）

`status`/`next` 对终态 CR 的输出：

```json
{
  "cr": "CR-2026-XXX",
  "status": "archived",
  "terminal": true,
  "source": { "history": "change-requests/_history.yml" },
  "legalNext": [],
  "reviewLoops": {},
  "gateBlockers": {},
  "next": null
}
```

`_history.yml` 条目以 `final-status` 为终态权威；history 重复条目或缺 `final-status` 硬失败（`HISTORY_DUPLICATE_ENTRY` / `HISTORY_FINAL_STATUS_MISSING`）；backlog/history 同存同 CR → `CR_LOCATION_CONFLICT`；cr.md 与 history 不一致时以 history 为准并输出 warning。不新增 archive reason/spec-id 等非必要字段，不新增 `archive-status` 命令。

#### 2.4 review cycle 兼容扩展（FR-16/D-14）

`maxAttempts=3` 按审查 cycle 计数。已 PASS 后发生 upstream 设计修订时开启新 cycle，旧 attempts 不删除：

```yaml
loops:
  review-tech-design:
    current-cycle: 2
    current-attempt: 1
    attempts:
      - { cycle: 1, attempt: 1, at: "...", by: "..." }
      - { cycle: 1, attempt: 2, at: "...", by: "..." }
      - { cycle: 1, attempt: 3, at: "...", by: "..." }
      - { cycle: 2, attempt: 1, at: "...", by: "..." }
```

- legacy `current-cycle` 缺失、attempt 缺 `cycle` 时均按 cycle=1 解释；
- traceability 的技术评审 attempts 同步增加 `cycle`，保留所有历史；
- `current-attempt` 只表示当前 cycle 的轮次，`attemptsWithinLimit` 只检查当前 cycle；
- 不新增账本类型或 crctl 子命令，不允许手工重置 review-loop。

### 3. 接口契约

#### 3.1 内部 helper：approve-and-advance（FR-8，不新增子命令）

TTY 路径（`cmdApprove` 主流程）与 `--grant` 路径（`approveWithGrant`）收敛到同一 helper：

```
approveAndAdvance(ws, cr, gates, stage, stageCfg, { grant, signature, ... })
  1. 预检：current state / transition 合法性 / evidence（stageCfg.requireFiles）/ 签名（grant 验签）/
     passCondition / requireFiles → 任一失败 fail()，零文件写入
  2. 在内存生成 approval.yml 文本（复用 writeApprovalSection 行级生成逻辑）与
     cr.md 新文本（frontmatter status → 目标态）
  3. 按候选 approval 复核目标 gate：runGateChecks 以内存候选文本为证据源（见下 evidence override seam）
  4. casWriteMulti([approval.yml, cr.md])   # 两文件同一 CAS：全校验→全 temp→连续 rename
  5. controlledGit add 两文件
  6. controlledGit commit（单次提交，message 含 CR 号与 stage）
  7. commit 成功后 emitOutboxEvent(status) → auditLog
```

**候选证据 override seam（TD-BL-4 修订，实现零写入的前提）**：`readEvidenceDoc(ws, cr, rel, overrides)` 增加可选第 4 参 `overrides`（`{ [relPath]: { text } }`），命中时用内存文本走同一解析路径（frontmatter/YAML 解析复用现有逻辑），不落盘、不改磁盘读的默认行为。**key 匹配时点（TD2-S1 采纳）**：overrides 的 key 一律使用含 `{cr}` 占位符的规范相对路径（如 `change-requests/{cr}/approval.yml`），匹配发生在路径展开前——调用方与读取方都用占位符形式，避免一处展开一处不展开导致 miss。`runGateChecks(ws, cr, targetStatus, gates, opts)` 的 `opts` 增加 `evidence` 字段，内部把 `opts.evidence` 透传给所有 `readEvidenceDoc` 调用点（approval 文档 checker、passCondition checker 等）。`approveAndAdvance` 第 3 步调用形态：

```
runGateChecks(ws, cr, 目标态, gates, {
  specId,  // 按 stage 需要
  evidence: {
    'change-requests/{cr}/approval.yml': { text: approvalText },
  },
})
```

**候选 cr.md 独立 invariant 校验（TD2-BL-2 修订）**：现有目标态 gate（如 tech-design-reviewed）没有任何 checker 读取 cr.md，`runGateChecks` 只以 targetStatus 选择门禁，因此不得假设 gate 会验证候选 cr.md。新增内部 helper `assertCandidateStatus(crMdText, expectStatus)`：解析 `crMdText` 的 frontmatter `status`，不等于 `stageCfg.to`（目标态）→ `CANDIDATE_STATUS_MISMATCH` 硬失败（零写入），等于则通过。调用顺序固定为：内存生成候选两文件 → `runGateChecks`（evidence 仅 approval.yml）复核目标 gate → `assertCandidateStatus` 校验候选 cr.md → 全部通过才 `casWriteMulti`。

回归测试（§7.3 同步）：候选 approval 缺 `via`/签名 → `GATE_BLOCKED` 且零文件写入；候选 cr.md status ≠ 目标态 → `CANDIDATE_STATUS_MISMATCH` 且零文件写入（AC-9 用例扩展）。

边界：gate/签名预检失败零写入；CAS 冲突两文件均不写；commit 失败两文件共同留在工作区，返回结构化恢复信息（含 `next` 建议），不发 status outbox；拒绝路径不写批准段，继续走既有 reject 转换（REJECT_ROLLBACK 映射不动）。

**受控历史审批迁移 `approve --resign <reason>`（代码评审二轮 b10，不新增子命令）**：gates.json evidence 定义变更（如 dev-start 剔除 task-index）后，既有 approval 段仍按旧证据集签发 digest，门禁复算不一致报 EVIDENCE_DRIFT——这是定义变更而非内容篡改，提供受控迁移路径：

```
approveResign(ws, cr, gates, stage, stageCfg, { reason })
  1. TTY 人类在环硬检查（同 approve，无旁路）；非 TTY 一律 APPROVAL_REQUIRES_HUMAN
  2. 审批段必须已存在且曾由 crctl approve 写入（approver/approved-at/via 齐备）→ 否则 RESIGN_NO_PRIOR_APPROVAL；仅 `via=crctl-approve` 可迁移，`via=server-approve` → RESIGN_SERVER_APPROVAL_UNSUPPORTED（原签名绑定旧 digest，须服务端重签 grant）
  3. 按当前 gates.json evidence 定义重算 canonicalEvidenceDigest；缺失证据文件 → RESIGN_DIGEST_UNAVAILABLE
  4. 新 digest == 旧 digest → ok({ changed: false, reason: 'digest-already-current' }) 幂等返回
  5. 不一致 → 展示旧/新 digest 与原因，人工确认（只有 yes 才写）
  6. 确认后：resignApprovalSectionText 只替换该段 evidence-digest 行（保留 approver/approved-at/via/target-status），
     追加 resign 审计子块（at/by/from-digest/reason）；全部动态字符串经统一 YAML 标量序列化（覆盖双引号、反斜杠、换行）；幂等：先清旧 resign 子块再重建
  7. casWrite（单文件 CAS）→ auditLog(kind: approve-resign) → 单次 commit（不动 cr.md status，不新增子命令）
```

设计约束：① 仅限 TTY，人类在环，无旁路（治理⑤）；② 只迁移本地 `crctl-approve`，服务端签名审批必须重新签发 grant；③ 不改审批本体字段（approver/approved-at 保持历史事实），只迁移 digest 绑定；④ 每次迁移落 resign 审计子块与 audit 事件，可追溯；⑤ 重复 resign 幂等（digest 已一致则 no-op；文本变换先清旧 resign 块）。

#### 3.2 `archive-move`（FR-11/FR-12 账本面）

```
crctl archive-move CR --final-status <archived|rejected|withdrawn> [--archive-reason <s>] [--spec-id <s>]
```

- 前置态放宽：`resolveCrState` 当前 status ∈ {archived, rejected, withdrawn}，且 `--final-status` 必须与当前 status 完全一致，否则 `FINAL_STATUS_MISMATCH` 硬失败（D-8）。
- 重复调用语义（TD-BL-3 拍板，替换「重复归档幂等」的模糊表述）：CR 已移出 backlog 后再次调用时，archive-move 走**受控只读 history 检测**（专用逻辑，不扩大为通用终态可写）：
  - history 存在同 CR 且 `final-status` === `--final-status` → 幂等返回 `{ op: 'archive-move', cr, result: 'already-archived', finalStatus: 'archived' }`（TD2-S2 采纳：携带 finalStatus 便于调用方审计命中哪个终态），零写入、不发 outbox；
  - history 存在同 CR 但 `final-status` ≠ `--final-status` → `FINAL_STATUS_MISMATCH` 硬失败；
  - history 无该 CR → `CR_STATUS_NOT_FOUND`。
  status/next 的终态 fallback（§3.4）与写命令的 active-only 约束不变：archive-move 的 history 检测是其账本移动职责的一部分，不新增其他写命令的终态可写性。
- 流程：读 backlog + history + index 三文本 → 内存构造 archive event 候选条目 → 生成三份新文本（backlog 移除条目、history 追加终态条目+notify-log、index 更新三字段）→ 收件人解析（缺则 `ARCHIVE_RECIPIENTS_MISSING`）→ `casWriteMulti` 三文件 → CAS 成功后 `emitOutboxEvent(archive)` → audit。
- 任一 event/文件结构错误或 CAS 冲突：事件与三份账本均不写。
- 不新增 `inbox-emit --payload-file`、archive 专用幂等键或新命令；普通通知继续用 `inbox-emit`。

#### 3.3 `inbox-emit` 校验修正（FR-11）

`cmdInboxEmit` 增加 `--to` 校验：缺失、解析后非列表、去重后为空 → `BAD_ARGS`，不写无收件人 notify-log（与 Skill 契约对齐，B-13）。

#### 3.4 终态只读 resolver（FR-12，仅供 status/next）

新增 `resolveTerminalCrState(ws, cr)`：仅从 `_history.yml` 读取；`cmdStatus`/`cmdNext` 在 active resolver 报 `CR_STATUS_NOT_FOUND` 时 fallback 调用；写命令（advance/approve/checkpoint-add/owner-set/backlog-set/inbox-emit/merge-metadata/review-record 等）**不** fallback，终态写入维持拒绝。

#### 3.4a `cmdNext` active 路由与 freshness（FR-16）

`task-breakdown` 分支不再只检查 plan/tasks：

```text
读取 dev-plan.yml
  缺失/解析失败/缺 verdict 或 blockers → review-dev-plan
  PASS + blockers=[]                 → crctl approve --stage dev-start
  BLOCK                              → resolveDevPlanRoute(annotation)
    repair                           → write-dev-plan
    upstream                         → write-tech-design
  BLOCK 且当前 cycle exhausted       → next=null, humanApproval=true, why=LOOP_EXHAUSTED
```

route 必须从 canonical annotation 的顶层 `repair-target` 重算，不读取 `review-record` 的瞬时返回对象。

`tech-design-review-pending` 分支新增 freshness：

1. 读取 `sdd.yml#subject-sha256`，与当前 `sdd.md` LF 规范化 SHA-256 比较；
2. 读取 dev-plan annotation；若 `verdict=block`、`repair-target=write-tech-design` 且其 `reviewed-at` 晚于 sdd 技术评审 `reviewed-at`，视为 upstream stale；
3. digest 不一致或 upstream stale → `review-tech-design`；
4. 仅 fresh 且 PASS/无 blocker → `crctl approve --stage tech-design`。

legacy sdd annotation 无 subject digest 时：存在较新 upstream blocker 必须重审；否则保持旧兼容行为，不批量迁移历史 CR。

#### 3.5 `review-record` 输出（FR-13）

保持 `file`、`trace` 兼容，返回对象新增：

```json
{
  "files": ["change-requests/{cr}/review-annotations/{stage-file}", "change-requests/{cr}/traceability.yml"],
  "attempt": { "current": 1, "max": 3, "bumped": false },
  "route": "pass | repair | upstream",
  "repairTarget": "write-requirement-prd | write-tech-design | write-dev-plan | implement-code | null"
}
```

- `files`：只列本次实际写入（annotation + traceability；bumped 时才含 review-loop.yml）。
- `attempt`：从 review-loop 当前轮次读取（复用既有 attempt 记账，bumped 表示本轮是否递增）。
- `tech-design` annotation 新增 `subject-file: change-requests/{cr}/sdd.md` 与 LF 规范化 `subject-sha256`，供 `cmdNext` freshness 判断。
- `route`/`repairTarget` 按**按 stage 判定的真值表**（TD-BL-2 修订，替换原「block 且 repairTarget=write-tech-design → upstream」的统一映射）：

| stage | verdict | 顶层 repairTarget | route | repairTarget 返回 |
|---|---|---|---|---|
| 任意 stage | pass（verdict=pass 且 blockers=[]） | — | `pass` | `null` |
| 任意非 dev-plan stage | block | 任意 | `repair` | `REVIEW_REPAIR_TARGETS[stage]`（既有默认修复目标） |
| dev-plan | block | `write-dev-plan`（默认） | `repair` | `write-dev-plan` |
| dev-plan | block | `write-tech-design`（显式上游设计疑点，resolveDevPlanRoute 既有判定） | `upstream` | `write-tech-design` |

  `upstream` 只适用于 dev-plan 顶层 `repair-target=write-tech-design` 的显式上游设计疑点；review-tech-design 自身的正常 blocker 属 `repair`（回放 `write-tech-design`），不得错分为上游轨。
- `--bump-attempt` 在写入 tech-design 评审前调用 `detectNewTechDesignCycle`：上一 annotation 为 PASS、存在较新的 dev-plan upstream blocker，且当前 SDD digest 与上一 `subject-sha256` 不同（legacy 无 digest 时以上游时间关系兜底）→ `current-cycle+1`、本 cycle attempt=1；旧 attempts 仅补 legacy `cycle=1` 后保留。普通 block→repair 仍在当前 cycle 内计数，达到 3 次继续 `LOOP_EXHAUSTED`。
- 不返回 `verified`（与退出码/CAS 成功重复）、subject digest（内部 freshness 用）、`next`（唯一由 `crctl next` 计算）。

#### 3.6 `migrate-backlog` 扩展（FR-10）

扩展现有 `cmdMigrateBacklog`（v1→v2 布局迁移）增加幽灵条目清理阶段，**不新增子命令**、**不新增独立脚本**：

- 检测：解析 `_backlog.yml`，识别「无 `- id:`/`cr-id:` 归属的续行块」（B-12 形态：列表项字段缩进块后紧跟同缩进但无列表标记的 title 行）。
- 删除依据：`_history.yml` 中存在同 title 的完整归档条目（防误删在途 CR）。
- 执行：删除幽灵块（从幽灵 `title:` 行到块尾），CR-2026-017 条目自动恢复完整。
- 幂等：无幽灵块 → `{ migrated: false, reason: 'already-clean' }`，文件哈希不变。
- 删除依据不满足（history 无对应归档）→ 硬失败 `GHOST_ENTRY_ORPHANED`，不静默删除。
- 审计时序（代码评审二轮 b10）：幽灵清理的 `migrate-backlog-ghost removed:true` 审计事件**不得**在 `migrateGhostCleanup` 内预写——必须先 `casWrite` 成功、后由调用方调 `auditGhostCleanup` 补记。CAS_CONFLICT 时 `_backlog.yml` 保持不变且 audit.log 零成功记录（FR-10 一致性边界：状态机 + CAS + audit 统一写入路径）。

> 实现落点拍板（2026-08-09 用户决策，同步修订 PRD FR-10/D-11）：PRD FR-10 原写 `../tools/skills/shared/scripts/`，但 ARCHITECTURE §6 明确否决「独立账本操作脚本库（如 `tools/skills/shared/scripts/`）」（CR-2026-012 复盘 + CR-2026-020 范围澄清），`_backlog.yml` 属账本四类文件，清理必须经 crctl（CAS + audit）。因此落点定为 crctl.mjs 内 migrate 命令扩展，与既有 `cmdMigrateBacklog` 同路径。**结论不受影响**：清理语义、幂等与验收（AC-14）不变；PRD FR-10 文字已同步为同一落点，PRD/SDD 冲突已消除。

### 4. 关键算法与流程

#### 4.1 archived TASK 门禁（FR-9，修复 `deliveryIndexComplete`）

在 crctl.mjs 的门禁 checker 实现中，将 `deliveryIndexComplete`（及 archived 目标态校验路径）改为五步判定：

```
1. tasks/_index.yml 不存在 → TASK_INDEX_MISSING（fail）
2. tasks[] 为空数组 → TASK_LIST_EMPTY（fail）        # 不得解释为 no-task
3. 任一 TASK status != done → TASK_STATUS_INCOMPLETE（fail，列出未完成 TASK-ID）
4. 全部 done 后：delivery/task/_index.yaml 缺失或空 → DELIVERY_INDEX_MISSING（fail）
5. 全部通过 → 放行
```

gates.json 的 archived 门禁声明结构不动（D-9：不改 gates.json），只修执行层 checker。`rejected`/`withdrawn` 不走 archived 门禁（提前终止语义，D-8）。不新增 no-task 标志与永久 `task reconcile` 命令。

#### 4.2 幽灵条目清理算法（FR-10）

```
normalize CRLF → 逐行解析（复用 parseYaml 的行模型）
定位：在 change-requests 序列中，找到最后一个 id 字段缺失的块起点
      （= 某列表项 map 解析结束后，出现 indent ≥ 列表项字段缩进且非 '- ' 开头的第一行）
判定归属：取该块 title → 在 _history.yml 中检索同名归档条目（final-status 存在）
删除：从该行到 EOF（或到下一个 '  - id:' 前）
校验：删除后重新 parse，CR-2026-017 条目的 title/summary/owners 等字段恢复为归档前形态
审计（b10 时序）：migrateGhostCleanup 只检测不写审计；调用方在 casWrite 成功后调 auditGhostCleanup 补记
      （CAS_CONFLICT → casWrite 抛错终止，audit 不可达 → 零成功审计记录）
```

#### 4.3 终态查询 fallback（FR-12）

```
cmdStatus/cmdNext:
  try { state = resolveCrState(ws, cr) }            # active 路径
  catch (CR_STATUS_NOT_FOUND) { state = resolveTerminalCrState(ws, cr) }
  写命令（cmdAdvance/cmdApprove/...）: 不 catch，维持 CR_STATUS_NOT_FOUND
```

#### 4.4 approve 原子提交流程

见 §3.1 helper 流程；git 提交走 `controlledGit`（与既有 `crctl git` 同一受控通道），单次 commit 保证 approval/status 原子可见；outbox 事件在 commit 成功后发送（git 是权威、outbox 只是投影，ARCHITECTURE §5 不变量 6）。

### 5. 技术选型与替代方案

| 决策点 | 选型 | 否决的替代方案与理由 |
|---|---|---|
| approve 原子性 | 两文件内存生成 + `casWriteMulti` + 单次 commit（D-4） | WAL/两阶段提交：ARCHITECTURE §6 已否决（单写者下窗口足够小，YAGNI） |
| 归档原子性 | archive event 进 archive-move 同一 CAS（D-5） | 独立 inbox-emit + `--payload-file` + 幂等键：接口更多且留下 emit 成功/archive 失败的重复通知窗口 |
| 终态查询 | status/next 内 fallback resolver（D-6） | 新增 `archive-status` 命令：命令面膨胀；仅 status/next 有真实消费者 |
| 幽灵清理落点 | crctl `migrate-backlog` 扩展（已拍板 2026-08-09） | `skills/shared/scripts/` 独立脚本：违反 ARCHITECTURE §6 账本脚本库否决（见 §3.6 拍板说明） |
| review-record 深化 | 只加真实消费者字段（D-7） | 返回整份账本/verified/subject digest：与退出码和 CAS 成功重复 |
| TASK 门禁 | 修 crctl.mjs checker 实现 | 改 gates.json 结构：D-9 约束不改 gates；声明已含 deliveryIndexComplete，缺口在执行 |
| bootstrap | 声明入 repositories 后补建 tools worktree（D-12） | 直写 custom/main：绕过 CR worktree 治理；新增每 CR 仓库选择字段：第二套参与模型（Q3 否决） |

### 6. FR 到技术实现映射

| FR | 实现条目 | 落点 |
|---|---|---|
| FR-1 | 状态机口径 27/49 全量统一 | workspace AGENTS.md；tools ARCHITECTURE.md §3/§5；docs/analysis 复核 |
| FR-2 | crctl 单文件边界 + 删除 command module 描述 | tools ARCHITECTURE.md §3；v2 方案文档 |
| FR-3 | crctl-Pipeline 依赖三句准确描述 | tools ARCHITECTURE.md §4（替换「crctl 不依赖任何 Skill 或 Pipeline 定义」表述） |
| FR-4 | `_index.yml` 生命周期语义固化 | ARCHITECTURE.md + cr-archive SKILL.md；行为实现见 FR-11 |
| FR-5 | tools 入 repositories + merge Skill 特例删除 | workspace dir-graph.yaml；merge-feature-branch SKILL.md |
| FR-6 | 删除旧方案 command module/通用上下文命令描述 | docs/analysis/tools流程步骤优化v2.md |
| FR-7 | 指标基线固化（§16.1/§16.2） | ARCHITECTURE.md 或独立文档表格 |
| FR-8 | approveAndAdvance helper + TTY/grant 收敛 | crctl.mjs cmdApprove/approveWithGrant |
| FR-9 | deliveryIndexComplete 五步判定 | crctl.mjs checker 实现 |
| FR-10 | migrate-backlog 幽灵清理阶段（幂等） | crctl.mjs cmdMigrateBacklog + crctl.test.mjs |
| FR-11 | archive-move 三账本 CAS + archive event + inbox-emit 校验 | crctl.mjs cmdArchiveMove/cmdInboxEmit + 测试 |
| FR-12 | resolveTerminalCrState + status/next fallback | crctl.mjs resolveCrState 侧 + cmdStatus/cmdNext + 测试 |
| FR-13 | review-record 输出 files/attempt/route/repairTarget；review Skill 删二次读取 | crctl.mjs cmdReviewRecord；四个 review SKILL.md |
| FR-14 | 五项最小验证清单 | 实施收尾（见 §7.2） |
| FR-15 | tools worktree bootstrap | workspace dir-graph.yaml 先行 + ../tools 仓 worktree add |
| FR-16 | next freshness/上游重入：task-breakdown 从 dev-plan annotation 重算 route；tech-design-review-pending 校验 SDD subject digest/upstream blocker；review-record 自动开启 post-PASS 新 tech-design cycle | crctl.mjs cmdNext/cmdReviewRecord/readAttempts + crctl.test.mjs |

### 7. 安全与性能考量

#### 7.1 一致性边界

- 两文件/三文件写入全部经 `casWriteMulti`：全校验 → 全 temp → 连续 rename；任一文件 CAS 冲突则全部不写。
- 事件发送严格在 CAS 成功后；commit 失败不发 outbox（FR-8）；CAS 失败不发 archive outbox（FR-11）。
- 终态查询只读不改；写命令对终态维持拒绝（不因 fallback 引入可写性）。

#### 7.2 验证清单（FR-14，五项最小）

1. `git diff --check`（行尾/空白告警零）；
2. `JSON.parse(pipeline-templates/feature-writeback.pipeline.json)`；
3. `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿（含新增：approve 原子提交、archived 门禁、archive-move 三账本、终态查询、review-record 输出、inbox-emit 空 to、migrate 幽灵清理）；
4. `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` 零发现；
5. grep 按 AC-1 判定方式确认 tools 隐藏特例与 25/47「现状」表述清零。

不预跑 agent-skill matrix 检查族、agents contract 检查族、writeback scripts 测试、engineering-docs 测试；实施实际触及再按「改了什么测什么」追加。

#### 7.3 测试设计（crctl.test.mjs 新增用例）

- approve：四 stage 一次提交断言；gate 失败零写入；**候选 approval 缺 via/签名 → GATE_BLOCKED 零写入；候选 cr.md status ≠ 目标态 → CANDIDATE_STATUS_MISMATCH 零写入**（TD2-BL-2）；CAS 冲突两文件均不写；commit 失败两文件共存且无 status outbox（以受控环境模拟）；TTY/grant 同 helper 断言；reject 路径保持。
- archived 门禁：index 缺失 / 空列表 / 全 pending / 部分 done / delivery 缺失五类失败；全 done 放行；rejected/withdrawn 不适用。
- archive-move：三种终态 + final-status 不一致硬失败；中文 reason；收件人去重/legacy 回退/空收件人；可选 spec-id；**重复归档：CR 已移出 backlog 后再次调用 → `already-archived` 幂等返回（零写入）；history 存在但 final-status 不一致 → `FINAL_STATUS_MISMATCH`；history 无 → `CR_STATUS_NOT_FOUND`**（TD-BL-3 拍板）；outbox 时序；CRLF 规范化。
- 终态查询：三种终态 next:null；CR_LOCATION_CONFLICT；history 重复/缺 final-status 硬失败；cr.md 漂移 warning；active 回归。
- next 路由（FR-16/AC-23）：task-breakdown 无/畸形 dev-plan → review-dev-plan；PASS → approve dev-start；repair BLOCK → write-dev-plan；upstream BLOCK → write-tech-design；exhausted BLOCK → next:null + 人工处理。tech-design-review-pending 的 SDD digest 不一致/较新 upstream blocker → review-tech-design，fresh PASS 才允许审批。
- review cycle：legacy cycle=1 兼容；旧 cycle 3/3 PASS 后 SDD upstream revision → cycle=2/attempt=1；旧 attempts 保留；cycle=2 内第 4 次 block 仍 LOOP_EXHAUSTED。
- review-record：files 只列实际写入（未 bump 无 review-loop.yml）；attempt/route/repairTarget 正确性。
- inbox-emit：--to 缺失/非列表/空 → BAD_ARGS。
- migrate-backlog：幽灵块删除 + CR-2026-017 恢复 + already-clean 幂等 + history 无归档时 GHOST_ENTRY_ORPHANED。
- 代码评审 b10/三轮回归：黑盒注入读后并发改写，真实触发幽灵清理 `CAS_CONFLICT`，断言 backlog 除竞争写入外不变且零成功审计；dev-start 本地审批 digest 漂移通过真实 `approve --resign` TTY 路径完成 CAS、审计、受控提交并使 gate 复绿；reason/approver 含双引号、反斜杠、换行时仍为单一 YAML 标量；`server-approve` 明确拒绝本地 resign；非 TTY 一律 APPROVAL_REQUIRES_HUMAN。

### 8. Prompt 采纳影响（必填：本 CR 触及 crctl.mjs dispatch 与命令面）

| Skill 路径 | 现状 | 应改为 |
|---|---|---|
| `skills/cr/cr-archive/SKILL.md` | 描述 archive-move 同步 `_index.yml`（承诺未兑现）；独立 inbox-emit 发归档事件 | 对齐 FR-11：归档事件与三账本同批 CAS；`--final-status` 必须等于 cr.md 当前终态；收件人复用 owners |
| `skills/writeback/merge-feature-branch/SKILL.md` | prose 硬编码 tools 仓特例 | 删除特例，合并/同步只遍历 `dir-graph.yaml#repositories`（FR-5） |
| `skills/requirement/review-requirement/SKILL.md` | review-record 成功后重新读取 traceability 核对投影 | 删除二次读取，按返回 `files`/`route` 组织提交与分流，最后调用 `crctl next`（FR-13） |
| `skills/develop/review-tech-design/SKILL.md`（TD-BL-5 修订：原稿误写 `skills/architecture/`，实测真实路径为 develop 域） | 同上 | 同上 |
| `skills/develop/review-dev-plan/SKILL.md` | 同上（含 route/repairTarget 消费） | 同上 |
| `skills/develop/review-code/SKILL.md` | 同上 | 同上 |
| 四个 approve Skill（requirement/tech-design/dev-start/code） | 只描述「调用 crctl approve 后写审批并级联推进」稳定行为 | **不改**（D-9：分提交细节不在 prompt 中，原子化对它们透明） |
| 普通通知类 Skill（inbox-emit 调用方） | `--to` 契约已要求必填 | **不改**（crctl 校验与契约对齐，行为无变化） |

> 本 CR 不新增 crctl 子命令（NFR-1）：approve 原子化、archive-move 扩展、终态 resolver、review-record 深化、migrate-backlog 幽灵清理均收敛在既有命令内部。

### 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿（基于 PRD v0.2.0 与 v2 方案 §5/§6；FR 全覆盖 15/15；含 FR-10 落点修订说明——幽灵清理从 skills/shared/scripts/ 改为 crctl migrate-backlog 扩展，依据 ARCHITECTURE §6 否决，结论不受影响） |
| 2026-08-09 | v0.2.0 | Ray | 拍板（用户决策）：FR-10 采用本 SDD 方案（crctl migrate-backlog 扩展），§3.6 修订说明升级为拍板，§5 选型表同步；PRD FR-10/D-11 已同步修订，冲突消除 |
| 2026-08-09 | v0.3.0 | Ray | 修订（review-tech-design BLOCK 回修，TD-BL-2~5）：§3.5 真值表按 stage 判定（upstream 仅限 dev-plan 显式上游疑点，pass 时 repairTarget=null）；§3.2 重复归档语义拍板（already-archived 幂等 / FINAL_STATUS_MISMATCH / CR_STATUS_NOT_FOUND，§7.3 同步）；§3.1 新增候选证据 override seam（readEvidenceDoc 第 4 参 + runGateChecks opts.evidence，含调用形态与回归测试）；§8 修正 review-tech-design 路径为 skills/develop/；§1.3 采纳 suggestion（worktree-path 以主工作区解析 + bootstrap-base-sha 固定）；TD-BL-1 已由 PRD v0.3.0 闭环 |
| 2026-08-09 | v0.4.0 | Ray | 修订（review-tech-design 二轮 BLOCK 回修，TD2-BL-2）：候选 cr.md 校验改为独立 invariant helper `assertCandidateStatus`（错误码 CANDIDATE_STATUS_MISMATCH，CAS 前执行），不依赖 gate checker 消费 cr.md；evidence override 仅含 approval.yml；采纳 TD2-S1（override key 占位符匹配时点）、TD2-S2（already-archived 携带 finalStatus）；§7.3 测试同步；PRD AC-14 已由 PRD v0.4.0 闭环（TD2-BL-1） |
| 2026-08-09 | v0.5.0 | Ray | 范围确认（用户决策）：FR-16 纳入——cmdNext task-breakdown 分支补 dev-plan.yml 检查（CR-2026-026 遗留路由缺口，实测无评审记录时误报 approve dev-start）；FR 映射表与 §7.3 测试设计同步；归属 TASK-07 |
| 2026-08-09 | v0.6.0 | Ray | 上游回修（review-dev-plan DP-UP-1/2 + 回退后复验）：§2.4 增加兼容 review cycle；§3.4a 补 task-breakdown canonical route、SDD digest/upstream freshness；§3.5 tech-design subject hash + 自动新 cycle；§6/§7.3 同步 FR-16/AC-23 测试 |
| 2026-08-10 | v0.6.1 | Ray | 代码评审二轮 BLOCK 回修（b10）：§3.1 新增受控历史审批迁移 `approve --resign <reason>`（TTY 人类在环、只重签 digest、保留审批本体、resign 审计子块、幂等）；§3.6/§4.2 幽灵审计时序修正（审计必须在 casWrite 成功后，CAS_CONFLICT 零成功记录）；§7.3 补 b10 回归用例 |
| 2026-08-10 | v0.6.2 | Ray | 代码评审三轮 BLOCK 回修：`server-approve` 禁止本地 resign，改由服务端重签；resign 动态字段统一 YAML 标量序列化；测试改为真实 TTY 成功路径与真实 CAS_CONFLICT 运行时注入，覆盖 CAS/审计/提交/字段保留。 |

## 发布联调移交 merge pipeline（v0.2 · CR-2026-029）

## SDD — 发布联调移交 merge pipeline 完成证据

- **版本**：v0.1.0
- **cr-ref**：CR-2026-029
- **状态**：tech-designing

### 1. 架构概览

#### 1.1 模块边界

本 CR 修改两处 active executable surface（tools 仓）与一处知识库迁移（knowledge-base 仓）：

| 模块 | 文件 | 变更 |
|---|---|---|
| merge 编排 | `skills/writeback/merge-feature-branch/SKILL.md` | 新增"发布联调走查"步骤 + 发布类任务约定 |
| pipeline 模板 | `pipeline-templates/feature-writeback.pipeline.json` | merge-feature-branch 节点 prompt 同步 |
| 迁移对象 | knowledge-base `change-requests/CR-2026-028/`（tasks/_index.yml、TASK-10.md、sdd.md 变更记录） | 移除 TASK-10 |

不新增 crctl 子命令、不改 `task done` 前置态、不改归档门禁判定（PRD 范围排除）。

#### 1.2 关键流程（改动后 merge-feature-branch 完整步骤）

```text
Step 1  前置校验（code-approved、worktree clean、远端新鲜）
Step 2  全仓预检（fetch + merge-tree --write-tree dry-run）
Step 3  全仓本地 no-commit merge + 逐仓 commit
Step 4  远端新鲜度复核 + 统一 push（补偿路径保留）
Step 5  更新 CR status（advance --to merging --embedded + merge-metadata + metadata commit/push）
Step 6  ★ 发布联调走查（本 CR 新增）：
        a. 各仓 trunk 拉取后，主 checkout 与 linked worktree 分别执行
           crctl status / worktree-path / next，确认无 STATUS_DIVERGED、嵌套路径异常
        b. multica CUSTOM.md 台账核账（grep CR-ID 与实际代码一致）
        c. 走查结果结构化写入 change-requests/{cr}/merge-verification.md，
           提交到 knowledge-base trunk
Step 7  输出摘要
```

#### 1.3 依赖方向

merge-feature-branch →（消费）crctl status/worktree-path/next（只读）、merge-metadata（既有）；无新增依赖。迁移 CR-2026-028 不依赖 crctl 新命令（定点账本编辑 + git 提交）。

### 2. 数据与文件契约

#### 2.1 merge-verification.md（新增完成证据）

位置：`change-requests/{cr}/merge-verification.md`（knowledge-base 仓，提交到 trunk）。

frontmatter：

```yaml
---
cr: CR-YYYY-NNN
verified-at: "ISO-8601"
verified-by: {identity}
repos:
  - repo: tools
    trunk: custom/main
    merge-sha: {sha8}
  - repo: multica
    trunk: main
    merge-sha: {sha8}
  - repo: ai-first-platform-docs
    trunk: master
    merge-sha: {sha8}
---
```

正文（`<!-- crctl:analysis-below -->` 以下模型补充）：

- 走查命令与结论：主 checkout `status`、linked worktree `status/next`、三仓 `worktree-path`（确认无 STATUS_DIVERGED/嵌套路径）；
- multica CUSTOM.md 台账核账结论；
- 异常与处理（若走查发现异常，按对应纪律回写：SDD 修订走 review-tech-design；不得手改评审记录）。

#### 2.2 发布类任务约定

merge-feature-branch SKILL.md 明示："发布联调、merge 验证类工作归 merge pipeline（本 Skill 联调走查步骤），不创建开发 TASK；开发期 `task allocate` 不产生发布/联调类任务。"

### 3. 接口契约

#### 3.1 merge-feature-branch skill 步骤变更

- 现有 Step 5 不变（advance --embedded + merge-metadata + metadata commit/push 同批发布）。
- 新增 Step 6（见 §1.2），随后原"输出摘要"顺延为 Step 7。
- Step 6 命令全部为既有只读 crctl 命令 + `git add/commit/push`（受控 shell），无新命令面。

#### 3.2 pipeline prompt 同步

feature-writeback.pipeline.json 中 merge-feature-branch 节点 prompt 增加：

```text
在状态推进与 merge-metadata 发布后执行发布联调走查：
1. 主 checkout 与 linked worktree 分别验证 crctl status / worktree-path / next（无 STATUS_DIVERGED、无嵌套路径）；
2. multica CUSTOM.md 台账核账；
3. 把走查结论写入 change-requests/{cr}/merge-verification.md 并提交 knowledge-base trunk。
```

#### 3.3 迁移 CR-2026-028

实施阶段在 knowledge-base 仓执行（CR-2026-029 分支内，随 CR-2026-029 merge 带至 trunk）：

1. 从 `change-requests/CR-2026-028/tasks/_index.yml` 移除 `CR-2026-028-TASK-10` 条目（定点块删除，保留其余 9 个任务块原样）；
2. 删除 `change-requests/CR-2026-028/tasks/TASK-10.md`；
3. `change-requests/CR-2026-028/sdd.md` 变更记录追加：发布联调移交 merge pipeline（CR-2026-029）——删除的 TASK-10 不再作为 CR-2026-028 交付物；
4. CR-2026-028 test-report.md 的 TASK 覆盖矩阵同步（TASK-10 移除说明）。

> 定点编辑采用与既有 migrate-backlog 一致的 CRLF 容错文本处理（读入后 `\r\n → \n` 归一，编辑后整体落盘；跨行解析失败必须硬失败，禁止静默降级——纪律 #1）。

### 4. 关键算法与流程

#### 4.1 迁移定点编辑

```text
read tasks/_index.yml（CRLF 归一）
删除包含 TASK-10 的条目块：
  - 锚定 `  - id: CR-2026-028-TASK-10` 起始行
  - 块结束 = 下一个 `  - id:` 起始行 或 文件尾
  - 删除后校验：TASK-10 不再出现、其余 id 集合不变（TASK-01..09）
写回（CAS 复核 sha256）
```

#### 4.2 联调走查判定

- `status`：主 checkout 出现 `STATUS_DIVERGED` 属预期（worktree 分支与 trunk 快照分离），不视为异常；**linked worktree 本身**不得有 STATUS_DIVERGED；
- `worktree-path`：三仓路径以主 checkout 为根，`path` 不含 `.rayai-worktrees/.rayai-worktrees` 嵌套；
- `next`：返回结构正常即可（写回期以 `crctl next` 为准，不手写映射）。

### 5. 技术选型与替代方案

| 决策 | 采用 | 否决 | 理由 |
|---|---|---|---|
| 发布联调归属 | merge pipeline 完成证据（merge-verification.md） | 把 `merging` 加入 `task done` LEGAL | 放宽账本语义、掩盖"发布类任务不落开发 TASK"的根因 |
| 证据强制 | skill/pipeline 步骤 + 提交证据，不加门禁 | merging→writing-back 门禁加 fileExists 检查 | 本 CR 范围排除改门禁；证据先落盘，强制留待实际需求 |
| 迁移方式 | 定点编辑 + 提交 | crctl 新增删任务命令 | 一次性迁移，不新增命令面 |

### 6. FR 到技术实现映射

| FR | 实现 |
|---|---|
| FR-1 merge pipeline 联调走查 | merge-feature-branch SKILL.md Step 6 + merge-verification.md 契约 |
| FR-2 pipeline prompt 同步 | feature-writeback.pipeline.json merge-feature-branch 节点 prompt |
| FR-3 发布类任务约定 | SKILL.md 约定段 + write-dev-tasks 无发布类拆分确认 |
| FR-4 迁移 CR-2026-028 TASK-10 | §3.3 定点编辑 + 变更记录 |
| FR-5 验证 | 新增 skill/pipeline 文本静态断言（无 crctl 门禁改动）；既有 158+9 测试回归 |

### 7. 安全与性能考量

- 迁移删除 TASK-10 只影响任务索引与单个任务文件，不触碰 CR-2026-028 的审批/评审证据（approval.yml、review-annotations、traceability）与已 merge 代码；
- 走查全部使用只读 crctl 命令，无副作用；
- merge-verification.md 只含合并事实与走查结论，不含敏感路径（示例相对路径）。

### 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-10 | v0.1.0 | Ray | 初稿 |

## Tools Root 唯一解析与路径统一（CR-2026-028）（v0.29 · CR-2026-028）

## SDD — tools 流程步骤优化 v2：前移优化项

### 1. 架构概览

#### 1.1 模块边界

本 CR 的目标代码仓是 **tools 方法论包自身**（修改 `crctl.mjs`、Skill/Pipeline 提示词、Adapter 模板、`dir-graph.yaml`），另含 knowledge-base 根 `AGENTS.md` 一处入口文档修改。不引入新模块、新公共库、新子命令；全部改动落在既有单文件 `crctl.mjs` 与既有提示词/模板文件内。

| 层 | 改动 | 边界 |
|---|---|---|
| crctl 配置定位 | 新增 module-scope `resolveToolsRoot()` 单值惰性 resolver；四个 loader 改读 Tools Root | 不拆文件、不新增命令面 |
| crctl workspace 语义 | `detectWorkspace` 之上新增 Installation Workspace 派生；`cmdWorktreePath` 改以 Installation Workspace 为根 | 不新增 `--tools-root` |
| Skill/Pipeline/Adapter | 提示词与模板中的路径表达改为 `{TOOLS_ROOT}/...` | 只改 PRD §3.1 白名单 |
| Registration | `requirement-register` 一次传齐 cr-init 元数据；删二次补 frontmatter | 不改 cr-init 实现 |
| tools `dir-graph.yaml` | 删除 `workspace.target_install_path` | 目标 workspace `tools_package_path` 成为唯一声明 |
| multica | 仅 `CUSTOM.md` 台账（已随注册提交） | 代码零改动 |

#### 1.2 双根概念落地

- **Operational Workspace**（OpWS）：`detectWorkspace()` 的返回值——CR 账本文件实际读写位置（主 checkout 或 knowledge-base CR worktree）。
- **Installation Workspace**（InstWS）：Tools Root 相对路径与 `.rayai-worktrees/` 的解析基准。普通 checkout 中 `InstWS = OpWS`；knowledge-base linked worktree 中由 `git rev-parse --git-common-dir` 派生（实测：worktree 内返回主 checkout 的 `.git`，其父目录即主 checkout 根）。

#### 1.3 关键流程（改动后）

```text
crctl <cmd> [--workspace <op-ws>]
  → help 提前返回（不解析 workspace）
  → detectWorkspace()            # OpWS（cwd 向上或显式）
  → loadGates(OpWS)                         # eager；内部调用 resolveToolsRoot(OpWS)
      → deriveInstallRoot(OpWS)              # git common-dir → 主 checkout；非 git 回退 OpWS
      → 读 InstWS/dir-graph.yaml#workspace.tools_package_path
      → 相对 InstWS → realpath → 四标志验证 → 仅缓存成功 toolsRoot
  → loadStateMachine(ws) / loadPipeline(ws,id) / loadGates(ws) / loadShellRules(ws) 全部调用 resolveToolsRoot(ws)
  → 分发子命令（仅 worktree-path 另调用 deriveInstallRoot(OpWS)，以 InstWS 拼接 .rayai-worktrees/...）
```

#### 1.4 依赖方向

不改变 ARCHITECTURE §4 依赖方向：Pipeline → Skill → crctl 单向向下；crctl 仍是最底层执行器。新增的 `git rev-parse --git-common-dir` 只读调用沿用 `identity()` 已有的 `spawnSync('git', ...)` 先例，不引入新依赖。

### 2. 数据模型

#### 2.1 新增/变更的配置契约

| 配置 | 位置 | 变更 |
|---|---|---|
| `workspace.tools_package_path` | 目标 workspace `dir-graph.yaml`（已存在，值 `../tools`） | 从“被 crctl 忽略”变为 Tools Root 唯一事实源；相对路径以 InstWS 为基准 |
| `workspace.target_install_path` | tools 包自身 `dir-graph.yaml` | **删除**（无人消费，FR-7）；同文件“固定挂载到 tools/”描述同步修订 |
| `{toolsRoot}/dir-graph.yaml` | tools 包 | 状态机唯一来源（原：OpWS → OpWS/tools → PACKAGE_ROOT 三候选） |
| `{toolsRoot}/pipeline-templates/*.pipeline.json` | tools 包 | Pipeline 唯一来源（原：OpWS/tools → PACKAGE_ROOT 两候选） |
| `{toolsRoot}/skills/shared/crctl/gates.json` | tools 包 | gates 唯一来源（原：执行脚本旁 `GATES_PATH`） |
| `{toolsRoot}/skills/shared/controlled-shell/rules.json` | tools 包 | 默认 controlled-shell rules（原：执行脚本旁）；`CRCTL_RULES_PATH` 显式覆盖保留 |

#### 2.2 身份标志（不新增存储）

`resolveToolsRoot` 固定验证四个存在性标志，不校验内容、branch、SHA 或版本：

```text
{toolsRoot}/AGENTS.md
{toolsRoot}/dir-graph.yaml
{toolsRoot}/skills/_index.yml
{toolsRoot}/skills/shared/crctl/scripts/crctl.mjs
```

#### 2.3 错误码与 detail 契约（新增）

| 错误码 | 触发 | detail 至少包含 |
|---|---|---|
| `TOOLS_PACKAGE_NOT_FOUND` | 字段缺失/非字符串/空值、解析路径不存在、realpath 失败、四标志任一缺失 | 配置字段名、原始值、解析后路径、缺失标志列表（或 `reason`） |

无新账本文件、无新持久化状态；进程内单值缓存不落盘。

### 3. 接口契约

#### 3.1 crctl 内部函数签名（不导出为公共 API）

```js
// module-scope，仅缓存成功值；失败由 fail() 直接结束进程
let toolsRootCache; // undefined=未解析，string=成功

function deriveInstallRoot(opWs)
  // git rev-parse --git-common-dir（spawnSync，cwd=opWs）
  // 成功 → resolve(opWs, stdout 首行) 的 dirname 即主 checkout 根
  // 失败/非 git → 返回 opWs（普通 checkout 等价）

function resolveToolsRoot(opWs)
  // 1) 成功缓存命中直接返回；失败不缓存（fail() 直接 process.exit(1)）
  // 2) installRoot = deriveInstallRoot(opWs)
  // 3) 读 installRoot/dir-graph.yaml → workspace.tools_package_path
  //    缺失/非字符串/空 → fail('TOOLS_PACKAGE_NOT_FOUND', {instRoot, field, reason})
  // 4) 相对值 → path.resolve(installRoot, v)；绝对值直接用；fs.realpathSync 归一
  // 5) 四标志逐一存在性校验，任一缺失 → fail(..., {instRoot, missing: [...]})
  // 6) 成功后写缓存返回
```

#### 3.2 loader 契约变更

```ts
loadStateMachine(ws): { sm, source }        // source 恒为 {toolsRoot}/dir-graph.yaml
loadPipeline(ws, id): { doc, source }       // 恒为 {toolsRoot}/pipeline-templates/{id}.pipeline.json
loadGates(ws): gates                        // 恒为 {toolsRoot}/skills/shared/crctl/gates.json；ws 供 resolveToolsRoot
loadShellRules(ws): rules                   // 默认 {toolsRoot}/skills/shared/controlled-shell/rules.json；
                                            // CRCTL_RULES_PATH 存在时优先（唯一覆盖入口）；ws 供 resolveToolsRoot
                                            // 删除固定 GATES_PATH 与默认 RULES_PATH 常量
                                            // （相对执行脚本的定位改为 Tools Root 派生）
```

`main()` 保持：`help` 在 workspace 解析前返回；其余命令先 `detectWorkspace` 再 eager `loadGates(ws)`（行为不变，仅来源变化）。`controlledGit` 内 `loadShellRules(ws)` 先按既有 `_shellRules` 独立缓存判断；需读取默认 rules 时调用 `resolveToolsRoot(ws)`，复用其成功值缓存。禁止为补参数引入 module-scope workspace 全局——ws 一律显式入参。状态机/Pipeline 目标文件仍由消费者按需校验，沿用 `PIPELINE_NOT_FOUND`、`GATES_NOT_FOUND` 等既有错误码（FR-3 边界）。

#### 3.3 worktree-path 契约

```ts
cmdWorktreePath(opWs, cr, repo):
  bucket = repo.role === 'knowledge-base' ? 'knowledge-base' : repo.id   // 不变
  path = join(installRoot, '.rayai-worktrees', bucket, 'requirement', cr) // 根改为 InstWS
```

从 knowledge-base linked worktree 调用不再产生 `<worktree>/.rayai-worktrees/...` 嵌套路径。`push-progress`/`pull-progress`/`resume-from-remote` 继续只消费该命令输出，不自行拼接（FR-2）。

#### 3.4 Registration 调用契约

`requirement-register` 的 cr-init 调用改为一次传齐：

```text
crctl cr-init --title "{title}" --owner-requirement {owner}
  [--year Y] --summary "{summary}" --source {source} --target-version {v} --workspace <ws>
```

删除 Skill Step 2 中“建档后直接补全 cr.md frontmatter”的指令；`cr-init` 本身零改动（已支持全部旗标，B-6 核实）。

### 4. 关键算法与流程

#### 4.1 Installation Workspace 派生（伪代码）

```text
function deriveInstallRoot(opWs):
  r = spawnSync('git', ['rev-parse', '--git-common-dir'], {cwd: opWs})
  if r.status == 0 and r.stdout 非空:
    commonDir = path.resolve(opWs, r.stdout.trim())   # worktree 场景 = 主 checkout/.git
    return path.dirname(commonDir)                    # = 主 checkout 根
  return opWs                                          # 非 git 目录（测试/独立检出）
```

实测证据：knowledge-base worktree 内 `git rev-parse --git-common-dir` → `<主checkout>/.git`，`dirname` 即主 checkout。multica worktree 的 common-dir 指向 multica 自身 `.git`——因此 tools/multica worktree 必须以 `--workspace <knowledge_base_worktree>` 显式传入，由该路径派生 InstWS，绝不使用 cwd 的 common-dir（FR-2）。

#### 4.2 Tools Root 解析（伪代码）

```text
function resolveToolsRoot(opWs):
  if toolsRootCache 命中: return toolsRootCache           # 仅成功值缓存，同一成功命令内只解析一次
  inst = deriveInstallRoot(opWs)
  doc = parseYaml(read(inst/dir-graph.yaml))            # CRLF→LF 归一（纪律 #1）
  v = getPath(doc, 'workspace.tools_package_path')
  if typeof v != 'string' || v.trim() == '':
    fail('TOOLS_PACKAGE_NOT_FOUND', {instRoot: inst, field, reason: 'missing-or-invalid'})
  raw = path.isAbsolute(v) ? v : path.resolve(inst, v)
  real = try realpath(raw) else fail(..., {instRoot: inst, reason: 'path-not-exists', resolved: raw})
  missing = 四标志中不存在的列表
  if missing.length > 0: fail(..., {instRoot: inst, reason: 'identity-marker-missing', missing})
  toolsRootCache = real; return real
```

失败路径绝不回退：不尝试 `opWs/tools`、cwd、`PACKAGE_ROOT`（D-3）。

#### 4.3 单值惰性缓存

`resolveToolsRoot` 仅维护 `toolsRootCache`（`undefined=未解析 / string=成功`）：任一 loader 首次成功解析后，同一命令内其余 loader 直接复用；失败调用 `fail()` 后进程立即退出，不设置失败缓存。`loadShellRules` 保留既有独立 `_shellRules`（`undefined=未加载 / null=加载失败 / object=成功`），它缓存的是 rules 解析结果，不与 Tools Root 共享同一槽。两者均无 Map、文件缓存、telemetry 或 module-scope workspace 全局。

#### 4.4 测试设计（FR-9）

1. **fixture tools 包**：`makeToolsFixture()` 生成最小四标志 + `dir-graph.yaml`（含可辨识 sentinel 转换）、`pipeline-templates/sentinel.pipeline.json`、`gates.json`（sentinel evidence 路径）、`controlled-shell/rules.json`（sentinel git shape）；不修改真实 tools checkout。
2. **makeWorkspace 扩展**：默认写入 `dir-graph.yaml` 并声明 `tools_package_path`（相对值指向 fixture）。
3. **表驱动**：相对/绝对路径、空壳 `tools/`、缺配置、非字符串、路径不存在、四标志逐一缺失。
4. **linked-worktree 黑盒**：临时 git 仓建 worktree，断言 `worktree-path` 与 Tools Root 均以 InstWS 为根、无嵌套 `.rayai-worktrees`。
5. **四类 sentinel 行为断言**（AC-6）：状态机用仅 fixture 存在的合法转换（advance 成功）、Pipeline 用仅 fixture 存在的 nodeRef、gates 用仅 fixture 要求的 evidence、rules 用仅 fixture 允许的 git shape；执行脚本换 checkout 结果不变。
6. **CRCTL_RULES_PATH** 覆盖断言（AC-7）。
7. **cr-init metadata**：复用现有用例，断言 summary/source/target-version 一次写齐（AC-11/AC-12）。
8. **代码审查断言**（AC-8）：四个 loader 均显式接收 ws 并调用同一 `resolveToolsRoot(ws)`；`main()`/`controlledGit` 各自调用 `loadGates(ws)`/`loadShellRules(ws)`；`toolsRootCache` 仅缓存成功 string，`_shellRules` 为独立缓存；无 Map/文件/telemetry/module-scope workspace 全局。

### 5. 技术选型与替代方案

| 决策点 | 选择 | 替代方案 | 理由 |
|---|---|---|---|
| resolver 归属 | 留在 `crctl.mjs` 单文件内（D-1） | 公共 `scripts/lib/tools-root.mjs` 共享库 | ARCHITECTURE §5 不变量 1/2/3：单文件强内聚写入路径、零依赖；当前只有一个消费者 |
| 配置基准 | Installation Workspace + git common-dir（D-9） | worktree 内复制/改写 dir-graph、创建 symlink/junction、新增 `--tools-root` | 前两者制造 checkout 特例，后者形成第二路径事实源（ADR-0003） |
| 失败行为 | 硬失败 `TOOLS_PACKAGE_NOT_FOUND`（D-3） | 保留 PACKAGE_ROOT 兼容回退 | 回退掩盖配置错误、使实际 tools 取决于启动入口；违反 NFR-2 |
| 版本绑定 | 只验证四标志身份（D-12） | branch/SHA/version pin | 本 CR 目标是路径确定性，不引入兼容矩阵维护面 |
| 配置修复 | 无自动修复（D-11） | installer/watcher/repairer | tools 移动属低频运维事件，重跑安装步骤即可（YAGNI） |
| 测试框架 | 扩展既有 `crctl.test.mjs` 黑盒套件（D-17） | 独立 resolver/Adapter 跨平台矩阵 | 核心风险在路径与 worktree 边界，黑盒 + sentinel 可覆盖；Adapter 无运行时消费者 |
| 静态物化 | Adapter 模板 `{TOOLS_ROOT}`（D-2/D-16） | 运行时解析 / 提交本机绝对路径 | hooks 启动即需路径，安装时物化一次；仓库不提交机器路径 |

### 6. FR 到技术实现映射

| FR | 实现位置 | 关键点 |
|---|---|---|
| FR-1 Tools Root 唯一契约 | `crctl.mjs` 新增 `resolveToolsRoot` + `deriveInstallRoot`；重构 `loadStateMachine`/`loadPipeline`/`loadGates` | 无隐式回退；detail 区分字段缺失/路径不存在/标志缺失 |
| FR-2 双根语义与 worktree 定位 | `deriveInstallRoot` + `cmdWorktreePath` 改根 | git common-dir 派生 InstWS；worktree-path 以 InstWS 拼接；push/pull/resume 消费不变 |
| FR-3 四标志身份验证 | `resolveToolsRoot` 校验段 | 只证明包身份；目标文件继续按需校验（既有错误码） |
| FR-4 crctl 配置来源收敛 | 四个 loader 改读 `{toolsRoot}/...`，全部显式接收 ws：`loadStateMachine(ws)`/`loadPipeline(ws,id)`/`loadGates(ws)`/`loadShellRules(ws)`；删除固定 `GATES_PATH` 与默认 `RULES_PATH` 常量 | `CRCTL_RULES_PATH` 唯一覆盖；help 不解析 workspace；eager `loadGates(ws)` 不变；`controlledGit` 内 `loadShellRules(ws)` |
| FR-5 active 执行入口统一 | PRD §3.1 白名单文件：`crctl/SKILL.md`、3 个 writeback Skill、feature-writeback pipeline、3 个 sync Skill、requirement-register、requirement-authoring pipeline、Adapter 模板、knowledge-base 根 `AGENTS.md` | `{TOOLS_ROOT}` 占位符；七个禁止模式零命中；CI 可设 TOOLS_ROOT 但命令不硬编码 |
| FR-6 Registration 复用 cr-init | `requirement-register/SKILL.md` Step 2 + `requirement-authoring.pipeline.json` node-1 prompt | 一次传齐元数据；删二次补 frontmatter；合并重复建档描述；cr-init 零改动 |
| FR-7 删除第二安装位置声明 | tools `dir-graph.yaml` | 删 `target_install_path`；修订“固定挂载到 tools/”描述 |
| FR-8 multica 延后项登记 | `CUSTOM.md`（已随注册提交 `cb957b73`） | 本 CR 代码零改动 |
| FR-9 最小回归验证 | `crctl.test.mjs` 扩展 | fixture + 表驱动 + linked worktree + 四 sentinel + CRCTL_RULES_PATH + cr-init metadata 复用 |

### 7. 安全与性能考量

#### 7.1 安全

- **失败即拒绝**：配置缺失/无效时硬失败，杜绝“空壳 `tools/` 被误读”与静默回退引入的配置漂移（NFR-2/NFR-6）。
- **错误详情不泄露敏感路径**：`TOOLS_PACKAGE_NOT_FOUND` detail 只含配置值与解析路径（运行时输出），仓库内不提交本机绝对路径（NFR-3）。
- **无新命令面**：不新增 crctl 子命令、环境变量（除既有 `CRCTL_RULES_PATH`），guard deny 面不变——不需要更新 `lint-prompts` 判据。
- **受控 shell 语义不变**：rules.json 内容不修改，仅默认来源变为 Tools Root；`SHELL_UNAVAILABLE` 拒绝语义保持。

#### 7.2 性能

- 每个 crctl 进程至多一次 `git rev-parse`（common-dir）与一次 realpath + 四标志 stat；单值缓存使同一命令内多 loader 零重复解析。
- 无新增 I/O、无后台任务、无 watcher；`help` 路径保持零 workspace 开销。
- 测试套件新增用例全部走临时目录 fixture，不影响真实仓库。

#### 7.3 兼容性

- 现有状态机转换、gate/passCondition、审批、CAS、账本、worktree bucket 语义不变（NFR-4，AC-16）。
- 历史 CR 与既有 worktree 布局（`.rayai-worktrees/{bucket}/requirement/{cr}`）不迁移；`worktree-path` 输出与既有路径一致（主 checkout 视角下不变）。
- `cr-init` 已支持旗标，向后兼容（不传时缺省语义不变）。

### 8. Prompt 采纳影响

本 CR 不新增/扩展 crctl 子命令面（dispatch 分支无新增 case），不修改 `rules.json#protectedPaths.deny`；但 FR-5 会批量变更 Skill/Pipeline/Adapter 提示词中的**路径表达**（`tools/skills/...` → `{TOOLS_ROOT}/skills/...`），`lint-prompts` 只能机械抓“crctl 已接管却仍在 prompt 里手工做”类问题，抓不到“路径表达仍假设 workspace 内安装”。以下为需按 FR-5 更新的采纳清单（= PRD §3.1 白名单，逐项含现状 → 应改为）：

| 文件 | 现状 | 应改为 |
|---|---|---|
| `skills/shared/crctl/SKILL.md` | `node tools/skills/...` 示例 | `{TOOLS_ROOT}/skills/...`（动态调用方运行时解析） |
| `skills/writeback/writeback-prd-sdd/SKILL.md` | `node tools/skills/...` | 同上 |
| `skills/writeback/writeback-tasks/SKILL.md` | 同上 | 同上 |
| `skills/writeback/writeback-traceability/SKILL.md` | 同上 | 同上 |
| `skills/writeback/scripts/test/writeback.test.mjs` | 注释中运行命令 | 同步为 `{TOOLS_ROOT}/...` 表达 |
| `pipeline-templates/feature-writeback.pipeline.json` | prompt 内 `tools/skills/writeback/scripts/*.mjs` | 改为 `{TOOLS_ROOT}/skills/writeback/scripts/*.mjs` |
| `skills/sync/push-progress/SKILL.md` 等 3 个 | `crctl worktree-path` 消费（不改） | worktree-path 根基准修正后行为自动一致 |
| `skills/requirement/requirement-register/SKILL.md` | Step 2 建档后补 frontmatter | 一次传齐 cr-init 旗标；删二次补写 |
| `pipeline-templates/requirement-authoring.pipeline.json` | node-1 两段重复 cr-init 描述 | 合并为一段、传齐元数据 |
| `skills/shared/crctl/adapters/**`（claude-code/qoder/cursor/codex/ci） | `$CLAUDE_PROJECT_DIR/tools/`、`{TOOLS}/tools/`、`{WORKSPACE}/tools/`、`node tools/skills/` | 统一字面 `{TOOLS_ROOT}/skills/...`，安装说明注明来源 `workspace.tools_package_path` |
| knowledge-base 根 `AGENTS.md` | `node ../tools/skills/shared/crctl/scripts/crctl.mjs` | 不绑定安装位置的口径表达（如“经 Tools Root 解析的 crctl”） |

`ARCHITECTURE.md` 不进白名单：本 CR 无架构级变更（不新增写入子命令、不改状态机口径、不否决方案），按 §8 维护规则无需修订；其历史否决示例中的 `tools/skills/...` 属允许例外。

### 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-10 | v0.1.0 | Ray | 初始草稿：Tools Root 唯一解析、双根语义、loader 收敛、Registration 复用、删除 target_install_path、黑盒测试设计；FR 9/9 映射 |
| 2026-08-10 | v0.2.0 | Ray | 第 1 轮技术评审 TD-B1 回修：四个 loader 显式接收 ws（`loadGates(ws)`/`loadShellRules(ws)`），`main()` eager `loadGates(ws)`、`controlledGit` 内 `loadShellRules(ws)`；删除固定 `GATES_PATH`/默认 `RULES_PATH` 常量；禁止 module-scope workspace 全局 |
| 2026-08-10 | v0.3.0 | Ray | 第 2 轮技术评审 TD-B2 回修：流程图统一为 loader→`resolveToolsRoot(opWs)`→内部唯一派生 InstWS；Tools Root 改为仅成功值缓存（失败即进程退出）；`_shellRules` 明确为独立 rules 缓存；伪签名改用 JavaScript 语义 |
| 2026-08-10 | v0.3.1 | Ray | 发布联调移交 merge pipeline（CR-2026-029）：TASK-10 不再是本 CR 交付物，其实质工作（双仓 merge、真实 worktree 走查、台账核账）由 merge-feature-branch 的发布联调走查步骤与 merge-verification.md 完成证据承担；本 CR 交付物为 TASK-01..09 |

## tools TCA-001～004 最小优化 — cr-init 三 Owner 注册契约 + owner-set 正式移交 + grant reject 验证回退 + review-dev-plan 精确 trigger / R7 字面量校验（v0.3 · CR-2026-030）

## SDD - tools TCA-001～004 最小优化

> 本文设计对应已审批 PRD `CR-2026-030-prd`。实现阶段以 PRD、tools `dir-graph.yaml`、`gates.json`、`controlled-shell/rules.json` 和 grant v1 为权威来源；本文不复制第二份可执行状态机或签名协议。

### 1. 架构概览

#### 1.1 设计目标

本设计在现有模块内闭合四条契约漂移：

1. `cr-init` 显式接收三角色 Owner，注册提交成功后才产生绑定真实 SHA 的注册事件。
2. `owner-set` 同步更新 Owner 双投影、唯一责任历史和通知事实，并形成只含两份受控账本的正式提交。
3. `approve --grant` 对 approve/reject 共用完整验证，合法 reject 执行权威回退并支持紧邻结果态幂等。
4. `review-dev-plan` 使用权威 trigger；R7 直接读取状态机声明并静态拒绝错误字面量。

#### 1.2 已有架构约束

设计逐条遵守 tools `ARCHITECTURE.md`：

- `crctl.mjs` 保持状态与账本唯一写者，不拆分 `commands/` 模块。
- Skill 只做业务编排，Pipeline 只做节点顺序、路由与重放。
- 状态仍只由 `crctl advance` 写入 `cr.md`。
- 账本写入继续使用 CAS 和 `.crctl/audit.log`，不增加会话脚本或第二写入口。
- 仅使用 Node 标准库；YAML 采用现有严格行级解析与定点改写。
- 所有文本解析先执行 `CRLF -> LF` 规范化；结构不完整时硬失败。
- Git 是权威事实，outbox 是可失败、可重放的非阻断投影。
- 状态机保持 15 个具名状态加注册前 `(new)`、27 条声明转移、wildcard 展开 49 条，不新增状态或转换。

Multica 在本 CR 中不是 production 实现目标，只承载既有 Go 到 crctl 的 test-only 跨接缝验证。该仓无 `ARCHITECTURE.md`；按已审批 PRD 的精确白名单，不新增该文件。Multica 改动遵循根 `CLAUDE.md`：Go 标准风格、检查所有错误、代码注释一律英文，并同步 `CUSTOM.md` 台账。

#### 1.3 仓库和文件边界

| 仓库 | 角色 | 设计改动 | 禁止事项 |
|---|---|---|---|
| tools | production 契约与实现 | `crctl.mjs`、R7、测试、8 个 Skill、4 个 Pipeline、3 份人读文档 | 新依赖、新状态、新命令模块、修改 CI |
| knowledge-base | CR 权威文档 | 本 SDD、后续评审与审批证据 | 实现代码、`specs/` 提前回写 |
| Multica | test-only 验证 | 扩展 `approval_crosscheck_test.go`，更新 `CUSTOM.md` | production Go、迁移、handler/service、Runner、owners/inbox 消费 |

#### 1.4 组件划分

| 组件 | 职责 | 现有落点 | 本次变化 |
|---|---|---|---|
| Registration writer | 分配 CR-ID，生成三文件候选并 CAS 写入 | `cmdCrInit()` | 三 Owner、三条初始历史、无 outbox、结构化返回深化 |
| Controlled Git adapter | 白名单校验、执行 Git、提交模板 | `controlledGit()`、`cmdGit()` | 只读无审计查询选项；register commit 返回 SHA 并发 status/owners 事件 |
| Worktree resolver | 生成 bucket/path | `cmdWorktreePath()` | 增加 canonical `branch` |
| Owner handover writer | Owner 变更和正式提交 | `cmdOwnerSet()` | clean 前置、双投影、历史、通知、提交、回滚、owners/inbox outbox |
| Approval consumer | TTY 或签名 grant 审批 | `cmdApprove()`、`approveWithGrant()` | approve/reject 共用验证、业务回退和紧邻结果态幂等 |
| Advance core | 状态机、门禁、状态提交和 status outbox | `cmdAdvance()` | 提取内部可复用执行核心，供 reject 回退复用；外部 CLI 不变 |
| Prompt drift linter | Skill/Pipeline 静态漂移检查 | `lint-prompts.mjs` R7 | 严格读取权威 transitions，校验 `(to, trigger)` 字面量 |
| Skill/Pipeline adapters | 业务入口和流程路由 | 8 个 Skill、4 个 Pipeline | 删除命令复制、无效输入和第二 Owner 写入口 |
| Cross-tool seam test | Go grant 到真实 crctl 验证 | Multica `approval_crosscheck_test.go` | 增加 reject 回退和幂等向量，不新增测试框架 |

#### 1.5 依赖方向

```text
Pipeline templates
       |
       v
Skill contracts
       |
       v
crctl public CLI
       |
       +--> dir-graph.yaml / gates.json / controlled-shell/rules.json
       +--> Git + change-requests ledgers
       +--> .crctl/audit.log + .crctl/outbox

Multica approval_crosscheck_test.go --(signed grant)--> real crctl approve --grant
```

`crctl` 不调用 Skill，不根据自然语言选择下一节点。Skill 和 Pipeline 不解析 Git HEAD、不拼接 branch/path/SHA、不复制状态转换。

#### 1.6 关键流程总览

##### Registration

```text
requirement-register
  -> cr-init(3 owners, one timestamp, CAS 3 files, no outbox)
  -> crctl git add(exact registration files)
  -> crctl git commit --template register --cr CR-ID
       -> real HEAD
       -> status(new -> drafting) outbox
       -> owners(initial-assignment x3) outbox
  -> push trunk
  -> worktree-path(repo) for each active repo
  -> create worktrees
  -> execution_context
```

##### Formal handover

```text
handover-cr
  -> owner-set
       -> tracked clean precheck
       -> owner projection consistency check
       -> one timestamp + two in-memory candidates
       -> casWriteMulti(cr.md, _backlog.yml)
       -> git add(exact two paths)
       -> staged-set + unstaged isolation check
       -> one formal commit
       -> success audit
       -> owners + inbox outbox attempts
  -> push-progress
```

##### Signed reject

```text
approve-* Skill
  -> approve --grant
       -> envelope/ownership/state/evidence/key/signature validation
       -> reject: authoritative rollback transition
       -> APPROVAL_DECLINED_ROLLED_BACK (nonzero business result)
  -> Pipeline aborts current forward flow
```

### 2. 数据模型

#### 2.1 持久化边界

本 CR 不新增持久化文件或 schema。只扩展以下既有结构的写入内容：

| 存储 | 权威性 | 变化 |
|---|---|---|
| `change-requests/{cr}/cr.md` | status、当前 Owner、唯一 Owner 历史 | 三 Owner 初始历史；正式移交当前投影和一条 `formal-handover` 历史 |
| `change-requests/_backlog.yml` | 在途 CR 索引和同步元数据 | 三 Owner 当前投影；handover notify-log/notify-pending |
| `change-requests/_index.yml` | CR 注册索引 | 注册行为不变 |
| `change-requests/{cr}/approval.yml` | approve 审批事实 | approve 路径不变；reject 不新增记录 |
| `.crctl/audit.log` | 本地操作审计 | registration/owner/grant 的结构化结果；不记录证据正文 |
| `.crctl/outbox/*.json` | 非阻断投影 | 新增 `owners`、`inbox` 事件；registration status 事件改由真实 commit 产生 |

#### 2.2 Owner 投影

逻辑类型：

```ts
type OwnerRole = "requirement" | "development" | "test";

type OwnerSlot = {
  id: string;
  "assigned-at": string; // 带偏移 ISO 8601
};

type OwnerProjection = {
  requirement: OwnerSlot;
  development: OwnerSlot;
  test: OwnerSlot;
};

type OwnerChangeFact = {
  role: OwnerRole;
  from: string;
  to: string;
  at: string;
  reason: "initial-assignment" | "formal-handover";
};

type OwnerHistoryEntry = OwnerChangeFact & {
  note?: string; // 仅允许进入 cr.md owner-history 和 inbox 通知事实
};
```

不变量：

1. `cr.md.owner == cr.md.owners.requirement.id`。
2. `_backlog.yml.owner == _backlog.yml.owners.requirement.id`。
3. 两个文件的三个 `owners.{role}` 必须逐项相等。
4. Registration 的三个 `assigned-at` 与三条 initial history 的 `at` 使用同一个 `registrationAt`。
5. Formal handover 的两处 slot、history、notify、audit payload 和 outbox payload 使用同一个 `handoverAt`。
6. `owner-history` 是唯一责任历史；`handover-history` 只读兼容，不再追加。
7. `note` 只存在于 `OwnerHistoryEntry` 和 inbox 通知事实；owners outbox、Owner 成功 audit 和当前 Owner 投影均不得包含 `note`。

#### 2.3 Git clean snapshot

`owner-set` 的 clean 前置和隔离复核使用只读结构：

```ts
type TrackedChangeSet = {
  staged: string[];   // git diff --name-only --cached
  unstaged: string[]; // git diff --name-only -- .
};
```

- 路径统一为 Git 输出的 `/` 分隔形式，过滤空行并去重排序。
- untracked 文件不属于该结构，不阻塞 owner-set。
- 命令开始时必须满足 `staged=[] && unstaged=[]`。
- commit 前必须满足：
  - `staged` 精确等于 `change-requests/{cr}/cr.md` 与 `change-requests/_backlog.yml`；
  - `unstaged=[]`。

#### 2.4 Notification fact

Backlog 中的 handover 通知继续使用既有 notify 结构，不新增第二历史：

```yaml
notify-log:
  - at: "<handoverAt>"
    event: owner-handover
    to: ["<new-owner>"]
    payload:
      role: development
      from: old-owner
      to: new-owner
      handover_at: "<handoverAt>"
      note: "<optional>"
    handled: false
notify-pending: ["<new-owner>"]
```

payload 不含 `subject`/`body`。展示文案由消费者负责。

#### 2.5 Outbox envelope 和 payload

沿用 `emitOutboxEvent()` 的 v1 envelope：

```ts
type OutboxEvent = {
  v: 1;
  event_kind: "status" | "owners" | "inbox" | string;
  cr_id: string;
  from_status: string;
  to_status: string;
  trigger: string;
  commit_sha: string;
  actor: string;
  evidence: Record<string, unknown>;
  payload: Record<string, unknown>;
  occurred_at: string;
};
```

新增 payload：

```ts
type OwnersPayload = {
  owners: OwnerProjection;
  changes: OwnerChangeFact[]; // 明确不含 note
  handover_at?: string;
};

type InboxPayload = {
  event: "owner-handover";
  to: string[];
  role: OwnerRole;
  from: string;
  owner: string;
  handover_at: string;
  note?: string;
};
```

Registration 的 `owners.changes` 固定三项 `initial-assignment`；handover 固定一项不含 `note` 的 `formal-handover`。`note` 只进入 `cr.md#owner-history` 和 inbox payload/backlog notify-log；不得进入 owners payload 或成功 audit。同一业务操作的事件共享真实 commit SHA，envelope `occurred_at` 可不同。

#### 2.6 Grant v1 和审批幂等键

不改变 grant schema。验证和幂等比较使用以下已签名字段：

```ts
type GrantV1 = {
  v: 1;
  cr_id: string;
  stage: "requirement" | "tech-design" | "dev-start" | "code";
  decision: "approve" | "reject";
  approver: string;
  approved_at: string;
  evidence_digest: string;
  key_id: string;
  signature: string;
};
```

approve 紧邻目标态重放时，`approval.yml` 对应 section 必须满足：

- `via == server-approve`；
- `approver == grant.approver`；
- `key-id == grant.key_id`；
- `signature == grant.signature`；
- `grant-approved-at == grant.approved_at`；
- `evidence-digest == grant.evidence_digest`；
- `target-status == stageCfg.to`。

reject 不持久化 approval section；其重放依据是当前状态恰好等于 `REJECT_ROLLBACK[stage].to`，且当前 evidence digest 与签名仍有效。

### 3. 接口契约

#### 3.1 `crctl cr-init`

```text
crctl cr-init \
  --title <text> \
  --owner-requirement <id> \
  --owner-development <id> \
  --owner-test <id> \
  [--year <YYYY>] [--summary <text>] [--source <text>] [--target-version <text>]
```

成功输出：

```json
{
  "op": "cr-init",
  "cr": "CR-2026-031",
  "status": "drafting",
  "owners": {
    "requirement": { "id": "R", "assigned-at": "..." },
    "development": { "id": "D", "assigned-at": "..." },
    "test": { "id": "T", "assigned-at": "..." }
  },
  "files": {
    "crMd": "change-requests/CR-2026-031/cr.md",
    "backlog": ".../_backlog.yml",
    "index": ".../_index.yml"
  }
}
```

错误：

| code | 条件 | 写入 |
|---|---|---|
| `BAD_ARGS` | 缺 title 或任一 Owner | 零写入 |
| `CAS_CONFLICT` | CR-ID 分配或三文件并发冲突 | 三文件零写入 |
| 既有结构错误码 | backlog/index 缺失或结构错误 | 零写入 |

`cr-init` 只写一条成功 audit，不发 outbox。

#### 3.2 Register commit

公开调用保持：

```text
crctl git commit --template register --cr <CR-ID> -m <subject> --cwd <knowledge-base-trunk>
```

register 模板成功时，`cmdGit()` 在 controlled commit 返回后读取真实 HEAD 和 `cr.md` Owner，并扩展输出：

```json
{
  "ok": true,
  "exit": 0,
  "commit": { "sha": "<real-head-sha>" },
  "outbox": {
    "status": "<file-or-null>",
    "owners": "<file-or-null>"
  },
  "warnings": []
}
```

- 非 register 模板和普通 `crctl git commit` 保持现有输出。
- commit 失败不读 HEAD、不发注册事件。
- 单个 outbox 写出失败时对应值为 `null`，`warnings[]` 增加 `{code:"EMIT_FAILED", event_kind}`，commit 仍成功。
- `emitOutboxEvent()` 的失败 audit 增加 `cr`、`event_kind`，不记录 payload 正文。

#### 3.3 `crctl worktree-path`

```text
crctl worktree-path <CR-ID> --repo <repo-id>
```

输出新增：

```json
{
  "op": "worktree-path",
  "cr": "CR-2026-030",
  "repo": "tools",
  "bucket": "tools",
  "branch": "requirement/CR-2026-030",
  "path": "<canonical-absolute-path>"
}
```

branch 只在此处生成，Skill/Pipeline 不再拼接。

#### 3.4 Registration incomplete

`REGISTRATION_INCOMPLETE` 是 `requirement-register` 对原语结果的编排级错误，不新增 crctl 顶层命令：

```ts
type RegistrationIncomplete = {
  code: "REGISTRATION_INCOMPLETE";
  cr_id: string;
  failed_step: "commit" | "push" | "worktree";
  completed_steps: string[];
  commit_sha: string | null;
  created_worktrees: Array<{repo: string; path: string}>;
  warnings: Array<Record<string, unknown>>;
};
```

一旦 `cr-init` 成功，Skill 固定复用返回的 `cr_id`；任何后续失败都不得再次调用 `cr-init`，也不得输出 `execution_context`。

#### 3.5 `crctl owner-set`

```text
crctl owner-set <CR-ID> \
  --role <requirement|development|test> \
  --id <new-owner> \
  [--note <text>]
```

成功变化：

```json
{
  "op": "owner-set",
  "cr": "CR-2026-030",
  "changed": true,
  "role": "development",
  "from": "Old",
  "to": "New",
  "handoverAt": "...",
  "files": [".../cr.md", ".../_backlog.yml"],
  "commit": {"sha": "...", "message": "[cr] owner handover ..."},
  "outbox": {"owners": "...", "inbox": "..."},
  "warnings": []
}
```

同值幂等：

```json
{"op":"owner-set","cr":"CR-2026-030","changed":false,"role":"development","id":"New"}
```

错误矩阵：

| code | 条件 | 副作用 |
|---|---|---|
| `OWNER_WORKTREE_DIRTY` | 开始时存在 tracked staged/unstaged 变更 | YAML/audit/commit/outbox 零新增；返回两个路径数组 |
| `OWNER_PROJECTION_DRIFT` | cr.md 与 backlog 的 owner/owners 不一致 | 零写入 |
| `OWNER_COMMIT_FAILED` | add/commit/commit 前隔离检查失败且成功恢复 clean baseline | `changed=false`、`rolled_back=true`；无成功 audit/outbox |
| `OWNER_COMMIT_ROLLBACK_FAILED` | CAS 恢复、撤销暂存或 clean 复核失败 | 中止并列出受影响文件；不吞掉外部变化 |
| `OWNER_GIT_CHECK_FAILED` | 受控 Git 只读查询无法执行 | 零 YAML 写入，保留底层 code/detail |
| 既有错误码 | 参数错误、终态、账本结构异常、CAS 冲突 | 按现有 fail-fast 语义 |

#### 3.6 受控 Git 内部接口

为满足 dirty 拒绝路径“audit 完全不变”，扩展内部签名，不增加 CLI 旗标：

```ts
controlledGit(
  ws: string,
  sub: string,
  args: string[],
  cwd?: string,
  caller?: string,
  options?: { audit?: boolean }
): ControlledGitResult
```

`options.audit` 缺省 `true`，所有既有调用行为不变。仅 `owner-set` 的纯只读 clean 查询传 `{audit:false}`；白名单、forbidden flags、spawn 参数和 fail-closed 行为仍全部执行。写操作、失败恢复中的 add/commit 和其他调用仍保留 Git audit。

现有 `rules.json` 已允许以下形态，无需修改 guard 文件：

```text
git diff --name-only --cached
git diff --name-only -- .
git add change-requests/<CR>/cr.md change-requests/_backlog.yml
git commit -m [cr] ...
git rev-parse HEAD
```

#### 3.7 `crctl approve --grant`

公开接口不变：

```text
crctl approve <CR-ID> --stage <stage> --grant [<path>]
```

统一结果：

| 决定/状态 | 结果 | exit |
|---|---|---:|
| approve，审批前置态 | 原子写 approval+status，`changed=true` | 0 |
| approve，紧邻目标态、审批字段一致且相关账本已提交到 HEAD | `changed=false` | 0 |
| reject，审批前置态且回退 commit 成功 | 状态回退，`APPROVAL_DECLINED_ROLLED_BACK/changed=true` | 非 0 业务结果 |
| reject，紧邻回退态且 `cr.md` 已提交到 HEAD | `APPROVAL_DECLINED_ROLLED_BACK/changed=false` | 非 0 业务结果 |
| 紧邻结果态但相关账本 staged/unstaged/untracked | `GRANT_STATE_UNCOMMITTED` | 非 0 技术错误 |
| 其他状态 | `GRANT_STATE_MISMATCH` | 非 0 技术错误 |

`APPROVAL_DECLINED_ROLLED_BACK` 输出至少包含：

```json
{
  "code": "APPROVAL_DECLINED_ROLLED_BACK",
  "decision": "reject",
  "stage": "tech-design",
  "rolledBackTo": "tech-designing",
  "trigger": "approve-tech-design:reject -> write-tech-design",
  "changed": true
}
```

不含 `rerunHint`、下一 Skill、未签名 reason 或 annotation 文案。

#### 3.8 `review-dev-plan` 结构化结果

Skill 输出固定为：

```ts
type DevPlanReviewResult =
  | { route: "pass"; verdict: "pass"; blockers: []; status: "task-breakdown" }
  | { route: "normal"; verdict: "block"; review_feedback: object; status: "tech-design-reviewed" }
  | { code: "UPSTREAM_DESIGN_BLOCKER"; route: "upstream"; verdict: "block"; review_feedback: object; status: "tech-design-review-pending" };
```

NORMAL 由 Skill 执行完整 trigger；UPSTREAM 由 Skill 执行 upstream trigger。Pipeline 只判断 route 和 `replayNodes`，不含具体 `advance` 命令。

#### 3.9 R7 输入和输出

R7 从当前 lint root 的 `dir-graph.yaml#change-request-track.state_machine.transitions` 构造只读集合：

```ts
type TransitionLiteral = { to: string; trigger: string };
```

对 Skill 内可静态确定的 `crctl advance` 命令：

- 缺 `--to`/`--trigger`：沿用当前 R7 finding。
- `(to, trigger)` 不在权威集合：输出 `CONTRADICTS`。
- 任一值含 `{...}`、`{{...}}` 或 `$...`：标记为动态并跳过 literal 校验。
- 不推断 `from`；完整合法性仍由运行时 `findTransition()` 裁决。
- 状态机块缺失、重复、空或任一声明无法完整解析：lint 以 `STATE_MACHINE_PARSE_FAILED` 非零退出，禁止空集合继续。

### 4. 关键算法与流程

#### 4.1 三 Owner Registration

伪代码：

```text
cmdCrInit(flags):
  require title + owner-requirement + owner-development + owner-test
  read backlog/index snapshots
  cr = scanMax + 1
  registrationAt = nowIso() exactly once
  owners = build three explicit slots(registrationAt)
  crMdCandidate = render cr.md(owners, three initial histories)
  backlogCandidate = append entry(owners, compatibility owner=requirement)
  indexCandidate = append index entry
  casWriteMulti(cr.md new, backlog hash, index hash)
  audit success with owners + changes
  return owners + files
```

实现要点：

- 将现有局部 `yamlScalar` 提升为文件内通用 helper，继续做最小标量转义，不引入 YAML 库。
- 删除 `ownerId` 复制逻辑和 `event_kind=cr-init` outbox。
- `auditLog` 的业务记录包含 Owner projection 和三项 change，但不写 branch、SHA 或 outbox 成功声明。
- 缺参数检查必须发生在读取/创建 CR 目录之前。

#### 4.2 Register commit 后置事件

`applyCommitTemplate()` 改为返回 `{args, templateContext}`，其中 register context 含已校验 CR-ID；普通模板也可复用该结构，但只对 register 执行后置事件。

```text
cmdGit(commit, template=register):
  context = applyCommitTemplate(...)
  result = controlledGit(commit)
  if failed: return failure, no event
  sha = controlledGit(rev-parse HEAD)
  owners = read + validate cr.md frontmatter
  emit status(new -> drafting, sha)
  emit owners(initial-assignment x3, sha)
  collect null emissions into warnings
  return sha/outbox/warnings
```

如果 HEAD 读取或 `cr.md` Owner 校验失败，commit 已是权威事实，不回滚；返回结构化 warning 并记 audit，后续 registration 结果为 incomplete，不得虚构成功上下文。

#### 4.3 Registration 编排失败边界

`requirement-register` 维护内存 `completedSteps` 和 `createdWorktrees`：

1. `cr-init` 成功后立即锁定 `cr_id`。
2. add/commit 成功后保存真实 SHA 和 warnings。
3. push 成功后追加 `push`。
4. 每个 worktree 创建成功后立即追加 repo/path。
5. 任一步失败组装 `REGISTRATION_INCOMPLETE` 并中止。
6. 只有全部成功时组装 `execution_context`。

Skill 不执行恢复删除，不回收 CR-ID，不做跨进程续跑。

#### 4.4 Owner 双投影解析和候选生成

新增文件内 helper，保持单文件架构：

```ts
readOwnerState(ws, cr): {
  crMd: {path, text, hash, owners, compatibilityOwner},
  backlog: {path, text, hash, owners, compatibilityOwner}
}

assertOwnerProjectionConsistent(state): void
buildOwnerCandidates(state, role, newId, note, handoverAt): {
  crMdText: string,
  backlogText: string,
  ownerChange: OwnerChangeFact,       // owners/audit 使用，不含 note
  historyEntry: OwnerHistoryEntry,    // cr.md history 使用，可含 note
  inboxPayload: InboxPayload,         // inbox/notify 使用，可含 note
  owners: OwnerProjection
}
```

读取用现有 `matchFrontmatter()`、`parseYaml()` 和 `loadBacklogEntry()`；写入仍是严格定点文本改写：

- `editCrOwnerProjection()` 更新一个 slot，requirement 时更新顶层 owner，并向 `owner-history` 追加一项。
- `editBacklogOwnerProjection()` 更新一个 slot，requirement 时更新兼容 owner，并在同一候选中追加 notify-log/notify-pending。
- 所有 editor 显式接收 `handoverAt`，内部不得再次调用 `nowIso()`。
- 每个目标块必须唯一命中；缺失、重复或缩进异常均 `LEDGER_PARSE_FAILED`，不静默创建替代结构。

#### 4.5 Owner clean precheck

```text
queryTrackedChanges(audit=false):
  staged = controlledGit(diff --name-only --cached, audit=false)
  unstaged = controlledGit(diff --name-only -- ., audit=false)
  if query failed -> OWNER_GIT_CHECK_FAILED
  return normalized sets

cmdOwnerSet:
  validate args/status
  dirty = queryTrackedChanges(audit=false)
  if dirty -> OWNER_WORKTREE_DIRTY(changed=false, staged, unstaged)
  read + validate both owner projections
  if target owner equals current -> changed=false
  handoverAt = nowIso() exactly once
  build candidates
  casWriteMulti(two ledgers)
  continue isolated commit
```

clean 查询不写 audit，确保 dirty 和同值重放路径满足零副作用。untracked 文件不会出现在两条 diff 命令中。

#### 4.6 Owner 隔离 commit

```text
expectedPaths = sorted([cr.md relative path, _backlog.yml relative path])
git add expectedPaths
isolation = queryTrackedChanges(audit=false)
if isolation.staged != expectedPaths or isolation.unstaged not empty:
  rollback OWNER_COMMIT_FAILED
commit "[cr] owner handover <CR> <role> <from> -> <to>"
if commit failed:
  rollback OWNER_COMMIT_FAILED
sha = rev-parse HEAD
success audit(handover_at, ownerChange without note)
emit owners(sha, ownerChange without note)
emit inbox(sha, inboxPayload may contain note)
return changed=true
```

commit message 以 `[cr] ` 开头，命中现有 controlled-shell 白名单。成功 audit 必须在 commit 成功后写；outbox 写出在 audit 之后逐项尝试，失败只形成 warning 和 `EMIT_FAILED` audit。

#### 4.7 Owner 失败回滚

开始时 baseline 已被证明 clean，因此恢复目标是 clean，而不是复杂的任意 index 快照：

```text
rollback(originalSnapshots, candidateHashes):
  casWriteMulti(
    cr.md expected=candidateHash -> originalText,
    backlog expected=candidateHash -> originalText
  )
  controlledGit(add exact two paths) // 原文等于 HEAD，清除本次 staged diff
  clean = queryTrackedChanges(audit=true)
  if CAS/add/query failed or clean not empty:
    fail OWNER_COMMIT_ROLLBACK_FAILED(affected files)
  fail OWNER_COMMIT_FAILED(changed=false, rolled_back=true)
```

并发安全：

- 同一目标文件被外部修改时，candidate hash 不匹配，CAS 拒绝覆盖。
- 其他路径出现并发 staged/unstaged 变化时，只撤销本次两个路径；最终 clean 复核失败并报告外部路径。
- 禁止调用 `reset`、`checkout`、stash 或生成补偿 commit。
- 进程在 CAS 后直接崩溃仍属已知窗口；下一次 clean precheck 会以 dirty 暴露，不当作同值成功。

#### 4.8 Approval 公共验证核心

把 `approveWithGrant()` 拆为三个文件内 helper，不新增模块：

```ts
readAndValidateGrantEnvelope(path, cr, stage): GrantV1
classifyGrantState(current, stageCfg, rollback, decision):
  | "fresh"
  | "adjacent-approve"
  | "adjacent-reject"
validateGrantEvidenceAndSignature(...): {digest, signatureOk}
```

固定顺序：

1. JSON/schema v1/decision 枚举。
2. `cr_id` 和 stage 归属。
3. 当前状态分类；非前置态或合法紧邻结果态统一返回 `GRANT_STATE_MISMATCH`。
4. approve 执行 passCondition 和 requireFiles；reject 跳过 passCondition，但仍按 stage evidence 计算 digest。
5. 比对 evidence digest。
6. 查 key 并验证 Ed25519 signature。
7. 根据 decision/state 进入副作用或幂等分支。

伪造、挪用、漂移和错误状态均在写入前失败。

#### 4.9 Advance 内核复用

当前 `cmdAdvance()` 同时做业务逻辑、输出和 `process.exit()`，不能被 grant reject 安全复用。提取内部 `performAdvance()`：

```ts
performAdvance(ws, cr, gates, flags): AdvanceResult
cmdAdvance(...): ok(performAdvance(...))
```

`performAdvance()` 保留现有转换查找、门禁、CAS/状态写入和 commit 语义，但不直接打印 JSON。为落实“Git 是权威”，standalone commit 失败时不得发 status outbox；只有 commit 成功才返回 `committed=true` 并发真实 SHA outbox。`--embedded/--no-commit` 仍按既有 pending SHA 语义由后续 metadata commit/checkpoint 补全。调用方：

- `cmdAdvance()`：正常成功输出；commit 失败输出原结构化技术结果并设置非零退出码，不发 status outbox。
- TTY reject：仅在 `committed=true` 后返回统一业务 decline 结果；否则传播技术失败。
- grant reject：仅在 `committed=true` 后返回统一业务 decline 结果；否则返回 `ADVANCE_COMMIT_FAILED`（含底层 commit detail），不得改写成 `APPROVAL_DECLINED_ROLLED_BACK`。

另增加内部只读 `assertResultLedgersCommitted()`：通过 `controlledGit(status --short, {audit:false})` 检查指定 ledger 路径在 porcelain 输出中不存在。目标文件若 staged、unstaged 或 untracked 均返回 `GRANT_STATE_UNCOMMITTED`；无输出意味着文件受 Git 跟踪且内容等于 HEAD。approve 检查 `approval.yml + cr.md`，reject 检查 `cr.md`。该查询仍走白名单和 fail-closed，且幂等路径不新增 audit。

不新增 public command，不改变 `findTransition()` 或 gates 来源。

#### 4.10 Grant approve/reject 幂等

```text
if decision=approve:
  if state=fresh:
    approveAndAdvance(existing atomic path) // commit failure remains technical failure
  if state=adjacent-approve:
    validate persisted approval exact match
    assertResultLedgersCommitted([approval.yml, cr.md])
    return changed=false, no audit/commit/outbox

if decision=reject:
  if state=fresh:
    result = performAdvance(authoritative rollback)
    if !result.committed: fail ADVANCE_COMMIT_FAILED, no status outbox
    return APPROVAL_DECLINED_ROLLED_BACK changed=true
  if state=adjacent-reject:
    assertResultLedgersCommitted([cr.md])
    return APPROVAL_DECLINED_ROLLED_BACK changed=false
```

幂等路径仍执行 digest 和签名验证，并在最后执行无 audit 的 committed-state 检查，但不写任何持久化副作用。该检查专门防止前一次 `approveAndAdvance()`/`performAdvance()` commit 失败留下的工作区目标态被误认成已完成事实。reject 不创建 `approval.yml` section，也不接受/传播未签名 `reject_reason`。

#### 4.11 Dev-plan 三路路由

`review-dev-plan/SKILL.md` 修改：

- NORMAL 精确命令：
  `crctl advance --to tech-design-reviewed --trigger "review-dev-plan:block -> write-dev-plan" --expect task-breakdown --embedded`。
- UPSTREAM 精确命令保持权威字面量并增加统一结构化业务结果。
- PASS 不推进状态。

`code-implementation.pipeline.json` 删除两个具体 advance，只保留：

- `route=pass` 继续；
- `route=normal` 重放 `write-dev-plan -> write-dev-tasks -> review-dev-plan`；
- `route=upstream` 中止当前 Pipeline。

NORMAL/PASS 按既有 review-record bump；UPSTREAM 沿用现有 `resolveDevPlanRoute()` 跳过 NORMAL attempt。

#### 4.12 R7 权威 transitions 解析

`loadJudgements(root)` 增加严格 loader：

```text
read root/dir-graph.yaml
normalize CRLF -> LF
locate exactly one change-request-track.state_machine.transitions block by indentation
for each non-empty sequence line:
  match complete inline mapping {from,to,trigger}
  decode quoted trigger
  if mismatch -> STATE_MACHINE_PARSE_FAILED
require at least one transition
return Set(to + NUL + trigger)
```

选择严格读取当前权威 inline mapping，而不是引入 YAML 依赖。若权威文件未来改为多行 transition，linter 会硬失败，迫使同次变更更新解析器和测试，不会静默丢转移。

命令字面量解析：

```text
for each paragraph line containing "crctl advance":
  choose containing backtick span when present, else current logical line
  parse --to and --trigger, supporting single quote/double quote/unquoted token
  preserve current missing-flag/full-width checks
  if both values static and pair absent -> R7 CONTRADICTS
```

测试 fixture 的 root 必须包含最小合法 `dir-graph.yaml`；畸形/空/CRLF fixture 分别验证 hard fail 和等价行为。

### 5. 技术选型与替代方案

#### 5.1 采用方案

| 决策 | 采用 | 理由 |
|---|---|---|
| crctl 组织 | 保持单文件，新增少量内部 helper | 符合 tools 架构强内聚约束，避免为四个修复创建模块层 |
| Owner 隔离 | 全仓 tracked clean 前置 | 简化成功提交和失败回滚，不需要保存任意 index/worktree 双层 patch |
| Git 查询 | controlledGit 白名单校验 + 内部 audit=false | 满足 fail-closed 与 dirty 零副作用，既有调用默认不变 |
| 多文件写 | 现有 `casWriteMulti()` | 已有三阶段 CAS 语义和测试，无需 WAL |
| Approval | 复用 grant v1、canonical digest、REJECT_ROLLBACK | 不产生第二协议或 rejection 账本 |
| reject 状态写 | 提取 `performAdvance()` 内核 | 避免复制状态机、门禁、commit/outbox 逻辑，也避免内部调用打印两份结果 |
| R7 parsing | 标准库加严格行级 parser | 零依赖、符合当前 dir-graph 格式和硬失败纪律 |
| Multica 验证 | 扩展既有 Go test | 已有真实 Go 签名到 Node 验签接缝，不新建集成框架 |

#### 5.2 否决方案

| 方案 | 否决原因 |
|---|---|
| 新增 `owner-handover` 命令 | 与 PRD 最小边界冲突；`owner-set` 已是受控原语 |
| owner-set 自动 stash/提交既有变更 | 会改变调用者 index/worktree 分层，失败恢复复杂且有数据损失风险 |
| 只要求两个账本 clean | 其他 tracked 文件仍可能在 owner commit 前并发进入 staged set；全仓 clean 契约更可验证 |
| 回滚使用 `git reset`/`checkout` | 可能吞掉外部并发变化，且 destructive 命令不在受控白名单 |
| 新 grant v2/rejection 文件 | v1 已签 decision；当前缺口只是消费顺序和回退 |
| Pipeline 执行 reject advance | 复制状态机字面量和业务算法，且当前无 Runner 保证分派 |
| linter 复制 transition 常量 | 状态机变化后必漂移，违反单一事实源 |
| 引入 YAML parser | 违反 crctl/tools 零第三方依赖和定点改写原则 |
| 新增 Multica production consumer | 超出 PRD，owners/inbox/reconcile 仍由 CUSTOM-TODO-003～005 承接 |
| 新增 Multica `ARCHITECTURE.md` | Multica 仅 test-only 参与，且文件不在已审批白名单 |

本轮决策均在既有边界内可逆，不新增 ADR。

### 6. FR 到技术实现映射

| FR | 技术实现 | 核心测试 |
|---|---|---|
| FR-1 | `cmdCrInit()` 三 Owner 必填、一次时间戳、三文件 CAS、三条 initial history | 不同 Owner、缺参零写、CAS conflict |
| FR-2 | register template context、commit 后真实 SHA 双事件、worktree branch、Skill incomplete envelope | commit/outbox failure、execution context 来源断言 |
| FR-3 | clean precheck、双投影 parser/editor、唯一 owner-history、同值幂等 | drift、staged/unstaged/并存/untracked、单时间戳 |
| FR-4 | `handover-cr` 只调用 owner-set 后 push；resume 删除 Owner 输入和写入 | Skill/Pipeline 静态断言、push failure 语义 |
| FR-5 | 两文件 CAS、staged-set 复核、正式 commit、CAS 回滚、owners/inbox outbox | add/commit/isolation/rollback failure 注入 |
| FR-6 | grant 公共验证核心、reject 跳过 passCondition 后权威回退 | 四 stage reject、伪造/挪用/漂移 |
| FR-7 | approve 持久化字段精确比较；reject 邻接状态验证 | approve/reject changed=false、其他状态 mismatch |
| FR-8 | review-dev-plan 持有两条 advance；Pipeline 只路由/replay | PASS/NORMAL/UPSTREAM 黑盒与 attempt 断言 |
| FR-9 | R7 strict transition loader 和 literal pair 校验 | 完整/短 trigger、模板跳过、CRLF、parse fail |
| FR-10 | 8 Skill、4 Pipeline、crctl SKILL 与 3 份人读文档同步 | lint-prompts enforce、文件白名单和节点数量检查 |

FR 覆盖率：10/10。

### 7. 测试设计与 AC 追踪

#### 7.1 crctl Node 黑盒测试

在现有 `crctl.test.mjs` 增加表驱动向量，不新增测试文件或框架：

| AC | 向量 |
|---|---|
| AC-1～2 | 三个不同 Owner 的 cr.md/backlog/audit/JSON；逐个缺参零文件/零 audit/outbox |
| AC-3～6 | cr-init 无 outbox；register commit 真实 SHA 双事件；commit/outbox failure；worktree branch；incomplete 由 Skill 静态契约覆盖 |
| AC-7～10 | 双投影 drift；requirement/development/test handover；note 边界；唯一时间戳；同值零副作用 |
| AC-11～12 | handover/resume Skill 与 Pipeline 静态文本断言；节点数不变 |
| AC-13～16 | owners/inbox 同 SHA；outbox failure；add/commit/isolation failure；CAS/unstage/clean failure；dirty 三类与 untracked-only |
| AC-17～22 | 四 stage approve/reject；错误 grant；reject 业务结果；approve/reject 邻接幂等；其他状态 mismatch |
| AC-23～26 | review-dev-plan PASS/NORMAL/UPSTREAM；完整 trigger 可运行；Pipeline 无命令复制 |

Git fixture 必须初始化真实 repo，并提交 clean baseline。dirty 用例分别构造：

1. 仅 staged tracked file。
2. 仅 unstaged tracked file。
3. 同一路径 staged 后再修改，以及不同路径 staged+unstaged。
4. untracked-only。
5. clean 成功后用 `git show --name-only HEAD` 或等价测试取证确认 commit 只含两账本。

失败注入沿用现有 `runCrctlWrapped()`/组件注入模式，不修改 production API 以迎合测试。

#### 7.2 lint-prompts 测试

在现有 `lint-prompts.test.mjs` fixture builder 中写入最小合法 `dir-graph.yaml`，新增：

- 完整 NORMAL `(to,trigger)` 通过。
- 短 trigger 命中 `R7/CONTRADICTS`。
- 存在 trigger 但 to 不匹配时命中。
- 模板变量 to 或 trigger 明确跳过 literal 校验。
- LF/CRLF 同结果。
- transitions 缺失、空、单行畸形、block 截断均以 `STATE_MACHINE_PARSE_FAILED` 非零退出。

#### 7.3 Multica 跨接缝测试

扩展现有 `TestGrantCrossVerifiesWithCrctl`，提取最小 fixture helper，并新增 table/subtests：

1. Go `ApprovalService` 签 approve grant，真实 crctl 推进。
2. Go 签 reject grant，真实 crctl 回退并返回 `APPROVAL_DECLINED_ROLLED_BACK`。
3. 同一 reject grant 在紧邻回退态重放，返回 `changed=false`。
4. 必要时增加 approve 紧邻目标态重放。

测试要求：

- 优先要求显式 `CRCTL_PATH`；保持当前无 Node/crctl 时 skip 的上游兼容行为。
- fixture 创建 `cr.md` 和 v2 backlog 所需最小结构，不能依赖旧 backlog status 回退。
- 所有新增 Go 注释使用英文。
- `CUSTOM.md` 按当时表结构登记 CR-2026-030 和对应 TASK。
- 不修改 Multica production code。

#### 7.4 静态和全量验证

实现完成后必须执行 PRD AC-32 全部命令：

```text
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node --test skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
node -e <parse all pipeline JSON>
```

另在 Multica 执行定向跨接缝测试，必须确认测试未因 `CRCTL_PATH`/Node 缺失而 skip。基线测试数当前为 crctl 189、writeback 9；实现后数量只能按新增向量增加，不能以删除既有测试换绿。

#### 7.5 完整 AC 验证矩阵

| AC | 技术验证点 |
|---|---|
| AC-1 | 三个不同 Owner 在 cr.md、backlog、audit、JSON 中逐项相等；兼容 owner 只取 requirement；三条 history 同时戳 |
| AC-2 | 分别缺 requirement/development/test Owner，断言三文件、audit、outbox 全部不变 |
| AC-3 | cr-init 后 outbox 为空；register commit 后 status+owners 两事件使用同一真实 HEAD，owners changes 恰为三项 |
| AC-4 | 注入 commit 失败断言零注册事件；逐项注入 outbox 失败断言 commit 存在、warning 和 EMIT_FAILED audit 存在 |
| AC-5 | worktree-path 返回 branch/bucket/path；静态扫描 Skill/Pipeline 不含 branch/path/SHA/event 手工拼接 |
| AC-6 | commit/push/第 N 个 worktree 失败分别返回完整 incomplete envelope，不产生第二 CR-ID 或成功 execution_context |
| AC-7 | 两投影任一角色或兼容 owner 漂移，owner-set 零副作用；一致时允许变化/幂等 |
| AC-8 | 三角色 handover 分别验证 owner-history 只加一条、不加 handover-history；note 只出现于 history/inbox，并显式断言 owners outbox/audit 无 note |
| AC-9 | 两投影、history、notify、business audit 和两个 outbox payload 的 handover timestamp 全相等；两账本同 CAS |
| AC-10 | clean 同值重放断言时间、history、notify、audit、commit、outbox 不变；handover Skill 仍进入 push-progress |
| AC-11 | 静态断言 handover 无 skip_push 且顺序唯一；模拟 push 失败保留 owner commit 并返回未完成 |
| AC-12 | resume Skill/Pipeline 输入与正文均不含 new_owner/new_owner_role/owner-set，恢复后调用 crctl next |
| AC-13 | commit 后 owners/inbox 两事件 SHA 相同；payload 无 subject/body，owners change 一项且无 note，时间戳与 AC-9 相同 |
| AC-14 | outbox failure 不回滚；add/commit/isolation failure 成功恢复原文和 clean baseline，返回 OWNER_COMMIT_FAILED |
| AC-15 | 分别注入恢复 CAS、撤销暂存、clean 复核失败，返回 OWNER_COMMIT_ROLLBACK_FAILED；外部变化保持原样 |
| AC-16 | staged-only、unstaged-only、同/异路径 mixed、untracked-only、clean success 五组 Git fixture；成功 commit 只含两账本 |
| AC-17 | 四个 stage 的 approve grant 正常推进；无 grant 非 TTY 拒绝；Pipeline 无 grant path/CLI 拼接 |
| AC-18 | 四个 stage 的 reject 在 schema、decision、归属、状态、digest、key、signature 全部通过后执行各自权威回退 |
| AC-19 | 伪造、跨 CR、跨 stage、证据漂移、错误状态逐项断言 cr.md/approval/audit/outbox 零业务写入 |
| AC-20 | 合法 reject 返回统一 business code、target、trigger、changed；JSON 不含 rerunHint/下一 Skill/reason/annotation 文案 |
| AC-21 | 成功 commit 后 approve 目标态 exact replay 和 reject 回退态 replay 均 changed=false，且仍复核 digest/signature 与 result-ledger committed-state |
| AC-22 | 非邻接状态/approve 字段不一致为 GRANT_STATE_MISMATCH；分别注入 approve/reject commit failure 后重放同 grant，必须 GRANT_STATE_UNCOMMITTED 而非幂等成功，HEAD/audit/outbox 不增加 |
| AC-23 | PASS 仅在 pass+空 blockers，状态保持 task-breakdown 并输出 route=pass |
| AC-24 | NORMAL 完整 trigger 可执行并只进入三节点 replay；短 trigger lint/runtime 双拒；第 4 次 bump LOOP_EXHAUSTED |
| AC-25 | UPSTREAM 回到 tech-design-review-pending，返回业务结果并中止；NORMAL attempt 不增 |
| AC-26 | Skill 中恰有两条具体 advance；Pipeline 中为零，只含 route/replay/abort；节点数与 index 不变 |
| AC-27 | R7 从 fixture dir-graph 读取 transition；完整 pair 通过，短 trigger/to 错配均 CONTRADICTS |
| AC-28 | LF/CRLF 等价；transitions 缺失、空、截断、任一声明畸形均 STATE_MACHINE_PARSE_FAILED |
| AC-29 | to/trigger 模板变量分别跳过 literal 校验；静态 pair 只匹配 to+trigger，不依赖 from 或文件位置 |
| AC-30 | changed-files 与 FR-10.1 白名单精确比较；Multica production 和 CI workflow diff 为空；CUSTOM-TODO 不误报已交付 |
| AC-31 | 四个 Pipeline 分别做 schema/静态断言：输入收敛、Owner 只读、三路 route、审批不复制 CLI；JSON parse 和节点计数通过 |
| AC-32 | PRD 六条全量命令全部退出 0；Multica reject 跨接缝以显式 CRCTL_PATH 真执行且无 skip |

### 8. Prompt 采纳影响

本 CR 修改 `crctl.mjs` 的既有 dispatch 分支和命令语义，因此本节必填。`protectedPaths.deny` 不变，`rules.json` 不修改。

#### 8.1 必须采纳扩展原语的 Skill

| Skill | 现状 | 应改为 |
|---|---|---|
| `skills/requirement/requirement-register/SKILL.md` | 只传 requirement Owner；自行描述 branch/path；注册事件时点失真 | 显式传三 Owner；消费 cr-init/register commit/worktree-path 返回；失败输出 incomplete |
| `skills/sync/handover-cr/SKILL.md` | pre-push、手写双投影步骤、独立 inbox、可 skip push | 唯一调用 `owner-set -> push-progress`；消费 changed/commit/warnings；删除 `skip_push` |
| `skills/sync/resume-from-remote/SKILL.md` | 接受新 Owner 并调用 owner-set | 删除 Owner 输入和写入，仅恢复 worktree、读状态、调用 `crctl next` |
| `skills/requirement/approve-requirement/SKILL.md` | 对平台 reject/技术失败区分不足 | 平台用默认 grant，本地用 TTY；识别 decline 业务结果并中止正向流程 |
| `skills/develop/approve-tech-design/SKILL.md` | 同上 | 同上，stage=`tech-design` |
| `skills/develop/approve-dev-start/SKILL.md` | 同上 | 同上，stage=`dev-start` |
| `skills/develop/approve-code/SKILL.md` | 同上 | 同上，stage=`code` |
| `skills/develop/review-dev-plan/SKILL.md` | NORMAL 使用短 trigger | 持有完整 NORMAL 和 UPSTREAM advance，输出三路结构化结果 |

`skills/shared/crctl/SKILL.md` 同步 public CLI、结果和错误码，但不得复制 helper 算法。

#### 8.2 Pipeline 收敛

| Pipeline | 删除 | 保留 |
|---|---|---|
| `requirement-authoring.pipeline.json` | `cr_id` input/透传、单 Owner cr-init、branch/path/SHA/event 拼接、审批 CLI 算法 | 三 Owner 输入、execution_context 透传、节点数量 |
| `architecture-design.pipeline.json` | approval CLI/reject 回修算法副本 | 决定传递、技术失败 abort、reviewLoop |
| `code-implementation.pipeline.json` | dev-plan 两条 advance、审批 CLI 算法 | PASS/NORMAL/UPSTREAM route、replayNodes、abort |
| `resume-cr.pipeline.json` | `new_owner`、`new_owner_role`、Owner 写入 | 远端检查、worktree 恢复、`crctl next` |

#### 8.3 人读契约

`README.md`、`AGENTS.md`、`ARCHITECTURE.md` 只修正现状描述：

- Registration 三 Owner 与真实 commit 事件。
- 正式移交唯一入口和 resume 只读。
- grant 双模式及当前无 Pipeline Runner 的诚实边界。
- crctl 仍是单文件、状态/账本唯一写者。

不得登记 CUSTOM-TODO-001～006 为已交付。

### 9. 安全、性能与兼容性

#### 9.1 安全

- Owner clean 查询仍经过 controlled-shell 白名单和 forbidden flags；`audit:false` 只关闭只读查询日志，不降低命令校验。
- 不将 `identity(ws)` 解释为强认证；Owner-set 只保证本地可信环境的数据一致性。
- grant 必须在任何写入前完成归属、状态、evidence、key 和签名验证。
- reject reason 未被 v1 签名，本 CR 不持久化或传播。
- 错误输出不包含 evidence 正文、私钥、公钥材料或完整通知正文。
- 回滚不使用 destructive Git 命令，不覆盖并发外部变化。

#### 9.2 性能

- `cr-init` 仍为一次 backlog/index 扫描和一次三文件 CAS。
- `owner-set` clean 成功路径增加两次 preflight diff、一次 add 后两次 isolation diff、一次 commit 和一次 HEAD 查询；CR 仓规模下为常数次本地 Git 调用。
- dirty 快速失败仅执行两次只读 diff，不解析/写入 YAML。
- R7 状态机读取一次并构建 Set；对 prompt 的检查为 O(文件文本长度 + advance 命令数)。
- 无网络同步调用；outbox 继续本地文件写入。

#### 9.3 兼容性

- `controlledGit()` 新参数有缺省值，既有调用行为不变。
- `crctl git` 非 register 模板输出不变。
- approve 成功路径和本地 TTY 人在环保持；TTY reject 可统一结果，但仍执行同一权威回退。
- `inbox-emit` 其他调用方不变。
- Pipeline 节点数量和 `_index.yml#nodes` 不变。
- 不修改 CI workflow、状态机或 gates。
- `cr-init` 三 Owner 是有意的破坏性参数收紧；所有已知调用点在同一 CR 内同步，不保留隐式复制兼容层。

### 10. 可观测性和错误处理

#### 10.1 Audit

| 操作 | 成功 audit | 失败 audit |
|---|---|---|
| cr-init | owner projection + 三项 initial change | 参数/CAS 失败零成功记录 |
| register commit | controlled Git commit；outbox failure 时 EMIT_FAILED | commit failure 仅 controlled Git failure |
| owner dirty/no-op | 无 | dirty 路径无 audit；Git query failure 返回结构化错误 |
| owner change | commit 成功后 business owner-set audit，含 `handover_at` | add/commit/rollback 操作保留技术 Git 记录，不写成功 owner audit |
| grant approve | 沿用 approve audit | 验证失败零 approval 写入 |
| grant reject | fresh 回退记录 advance/decline；幂等无新增 | 验证失败零副作用 |

`emitOutboxEvent` 失败 audit 记录 `event_kind`、`cr` 和错误摘要，不记录 payload。

#### 10.2 错误分类

- 参数/结构：`BAD_ARGS`、`LEDGER_PARSE_FAILED`、`OWNER_PROJECTION_DRIFT`。
- 并发/一致性：`CAS_CONFLICT`、`OWNER_WORKTREE_DIRTY`、`OWNER_COMMIT_ROLLBACK_FAILED`。
- Git 技术错误：`SHELL_UNAVAILABLE`、`OWNER_GIT_CHECK_FAILED`、`OWNER_COMMIT_FAILED`。
- grant 技术错误：`GRANT_*`、`EVIDENCE_DRIFT`、`SIGNATURE_INVALID`、`GRANT_STATE_MISMATCH`、`GRANT_STATE_UNCOMMITTED`、`ADVANCE_COMMIT_FAILED`。
- 人工业务结果：`APPROVAL_DECLINED_ROLLED_BACK`、`UPSTREAM_DESIGN_BLOCKER`。
- 静态治理错误：`LINT_DRIFT`、`STATE_MACHINE_PARSE_FAILED`。

Pipeline 只对业务结果做 route/abort；技术错误一律 abort，不伪装为回修意见。

### 11. 部署与运行时

- 无数据库迁移、服务部署、feature flag 或新环境变量。
- tools 继续要求 Node 标准运行时；CI 入口不变。
- Multica 定向测试需要显式 `CRCTL_PATH=<tools worktree>/skills/shared/crctl/scripts/crctl.mjs`，并确认 Node 可用。
- outbox 新 event_kind 在本 CR 中只保证写出，不保证 Multica 消费；消费者和 reconcile 由既有 CUSTOM-TODO 承接。
- 正式发布仍按仓库既有 merge/writeback 流程，不在技术设计阶段推送主分支。

### 12. 风险与回滚

| 风险 | 控制 | 回滚方式 |
|---|---|---|
| owner-set 在 CAS 后崩溃 | 下一次 tracked clean precheck 暴露脏文件；不误判同值成功 | 人工核对 Git diff 后按权威账本修复，不自动 reset |
| Git 查询 audit 抑制被滥用 | 选项仅内部、缺省 true；只在两条 read-only diff 调用使用，并加静态测试 | 删除该调用点的 `audit:false` 即恢复全审计 |
| register commit 成功但事件失败 | commit 返回 warning + EMIT_FAILED；Git 保持权威 | daemon/reconcile 后续补偿，本 CR 不反转 commit |
| grant reject 状态竞态或 commit 失败 | 状态分类后由 advance 的 expect/CAS 再校验；仅 committed=true 发 outbox/返回业务成功；邻接重放检查 result ledger 已在 HEAD | 返回 mismatch/CAS/ADVANCE_COMMIT_FAILED/GRANT_STATE_UNCOMMITTED，不把工作区目标态当权威事实 |
| R7 parser 对格式变化敏感 | 严格 hard fail 和 malformed fixture | 同次更新 parser；不得空集合降级 |
| Multica test 静默 skip | 实施验证显式设置 CRCTL_PATH，检查 verbose 输出 | 未实际执行则测试报告不得标 pass |
| 文档描述未交付 Runner/consumer | AC-30 静态扫描和 review-tech-design 人工核对 | 删除越界描述，保留 CUSTOM-TODO |

代码回滚按原子提交拆分执行：测试向量、registration、owner handover、grant、Skill/Pipeline、docs 分开提交。若某一能力需撤回，revert 对应提交并同步其契约文本；不得只回滚实现而保留宣称已交付的 Skill/Pipeline 文案。

### 13. 实施顺序

1. 增加 TCA-001～004 红色测试、R7 fixture 和 Multica reject 跨接缝向量。
2. 实现三 Owner cr-init、register commit 事件和 worktree branch。
3. 实现 Owner clean query、双投影候选、隔离 commit、回滚和双 outbox。
4. 提取 advance 内核，实现 grant 公共验证、reject 回退和 approve/reject 幂等。
5. 实现 R7 strict transitions loader 和 literal pair 校验。
6. 更新 8 个 Skill、4 个 Pipeline、crctl Skill 和人读契约。
7. 运行 Node 全量验证与 Multica 定向跨接缝测试。
8. 核对 changed-files 精确白名单、Multica `CUSTOM.md` 和三个 worktree 清洁度。

### 14. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-11 | v0.1.0 | Ray | 初始技术设计：闭合 Registration、Owner 正式移交、grant reject、dev-plan trigger/R7；定义 clean baseline、失败回滚、接口和测试映射 |
| 2026-08-11 | v0.1.1 | Ray | 第 1 轮技术评审 BLOCK 回修：拆分无 note 的 Owner 投影事实与 history/inbox；grant reject 仅在 commit 成功后返回业务结果，邻接幂等增加 HEAD/clean 证明与失败重放向量 |

## crctl 执行层职责边界与事务化（v0.4 · CR-2026-031）

## 1. 架构概览

### 1.1 设计目标

本设计落实 PRD FR-01～FR-10，并以 `docs/analysis/tools-tca-005-009-015-016-merge-workspace-optimization-plan.md` 为详细设计输入。核心目标不是让多个 Git remote 具备不存在的原子性，而是把现有文本拼接流程收敛为：**单仓 ref CAS + 持久化本地 journal + 远端事实 reconcile + 幂等 roll-forward**。

职责和依赖保持单向：

```text
Agent
  └─ 识别意图、选择 Pipeline
      ↓
Pipeline
  └─ 节点顺序、输入传递、reviewLoop、失败中止
      ↓
Skill
  └─ 业务前置、一次深原语调用、结构化结果解释
      ↓
crctl.mjs
  ├─ dispatch、状态/gate、账本、审批、审计
  └─ 调用两个内部模块
      ├─ lib/durable-tx.mjs
      │   lock / journal / recoverable write-set / fsync / fault / blob cleanup
      └─ lib/workspace-transactions.mjs
          repository resolver + 五个具体业务处理器
          registerCr / ensureWorkspace / mergeCr / applyWriteback / archiveCr
              ↓
          Node 标准库 + Git/文件系统原生能力 + remote refs
```

只新增以上两个内部模块。禁止新增 Transaction class、通用 phase engine、handler registry、adapter/plugin、第三方依赖或第三个事务模块。

### 1.2 现有架构基线的显式修订

`tools/ARCHITECTURE.md` 当前仍声明 crctl 刻意单文件且不引入 WAL。本 CR 是经需求审批的架构级变更，实施时必须在最终协议切换提交中同步修订：

1. `crctl.mjs` 仍是唯一公开 CLI 和状态/账本执行入口，但允许把持久化原语与 Git/workspace 事务实现拆入两个内部模块；
2. 将“多文件 WAL 永不需要”改为“只为已观察到的崩溃恢复需求提供最小 recoverable write-set”；
3. 保留零第三方依赖、状态/账本单一写者、CRLF 规范化、硬失败和人工审批无旁路；
4. 不将两个内部模块暴露为第二 CLI 或第二账本写入通道。

该修订与代码、测试、Skill/Pipeline 契约在同一 CR 完成，不提前改变当前 trunk 运行事实。

### 1.3 Authority

| 阶段 | 写 authority | 说明 |
|---|---|---|
| register～code-approved | CR requirement worktree | 现有开发/评审产物 authority |
| merge prepare/publish | crctl journal + remote refs | journal 是恢复指针，remote ref 是发布事实 |
| merge finalize 后 | detached knowledge-base Transaction Workspace | `operational_workspace` 的唯一来源 |
| archive commit origin confirmed 后 | origin knowledge-base trunk | 业务终态不可回退；cleanup 仅是运维阶段 |

用户主 checkout 从不作为事务 workspace。CR worktree 在 merge finalize 后只读，直到 archive cleanup。

## 2. 模块边界与文件变更

### 2.1 `crctl.mjs`

保留：CLI 参数解析、dispatch、现有状态机/gate/approval/audit、确定性输出和两个内部模块的薄接线。

删除或收敛：

- 死代码 `writeApprovalSection()`；
- 无调用别名 `cr-metrics`；
- `casWriteMulti()` / `tryCasWriteMulti()`，全部迁到同一 recoverable write-set；
- 公开 `cr-init`、`worktree-path`、`merge-metadata`、`archive-move`；
- 无真实调用的 `task allocate`、`scanMaxTaskNumber()`、`appendTaskEntry()`；
- `migrate-backlog`、ghost cleanup、v1 fallback/legacy warning；v1 统一返回 `UNSUPPORTED_BACKLOG_SCHEMA`；
- generic Git 中 register/writeback template 和后置特判；
- 公开 `--caller` 与伪造 caller 授权承诺。

保留历史 `evidenceSha16` 兼容和现有 YAML 子集解析器，不引入通用 YAML 库。

### 2.2 `durable-tx.mjs`

仅导出小型函数集合：

```js
acquireLock({ root, scope, op, cr })
loadOrCreateJournal({ root, op, cr, inputDigest, graphDigest, payload })
saveJournal({ path, journal })
recoverWriteSet({ root })
applyWriteSet({ root, txId, entries })
fault(point, context)
cleanupTxBlobs({ root, txId })
```

该模块只理解 envelope、文件锁、hash 和文件替换，不理解 CR status、Git branch、merge phase 或业务 payload。

### 2.3 `workspace-transactions.mjs`

仅导出五个具体函数和少量真实共享 helper：

```js
registerCr(ctx, input)
ensureWorkspace(ctx, input)
mergeCr(ctx, input)
applyWriteback(ctx, input)
archiveCr(ctx, input)

resolveRepositories(workspace)
classifyRemoteCommit(observation)
```

`classifyRemoteCommit()` 只分类 Git 事实，不接受 callback；各业务处理器自行决定 rebuild/finalize/cleanup。

### 2.4 版本化 writeback 脚本

`writeback-prd-sdd.mjs`、`writeback-tasks.mjs`、`writeback-traceability.mjs` 从“直接写 baseline”收敛为“读取 approved artifacts + baseline，生成 candidate manifest 与 content-addressed blobs”。它们不得推进状态、提交、push、创建 worktree 或修改账本。

## 3. 数据模型

### 3.1 公共 journal envelope

路径：`{Installation Workspace}/.crctl/transactions/{op}/{cr-or-key}/{txId}/journal.json`。路径不进入 Git；业务历史以 origin commit 为准。

```json
{
  "v": 1,
  "txId": "sha256-derived-or-random-id",
  "op": "register|workspace|merge|writeback|archive",
  "cr": "CR-2026-031|null-before-allocation",
  "phase": "op-specific-string",
  "graphDigest": "sha256",
  "inputDigest": "sha256",
  "sideEffects": [],
  "commit": null,
  "lastError": null,
  "createdAt": "ISO-8601",
  "updatedAt": "ISO-8601",
  "register": null,
  "workspace": null,
  "merge": null,
  "writeback": null,
  "archive": null
}
```

不变量：

- `op` 对应的一个 payload 非空，其余必须为 null；
- JSON 写入先写同目录 temp、`fsync(file)`、rename、`fsync(parent)`；
- 读入先规范化 CRLF；schema/JSON/必要字段缺失硬失败；
- `graphDigest` 在零副作用时允许重建；出现任一账本/workspace/remote 副作用后 graph 变化返回 `GRAPH_CHANGED_DURING_TRANSACTION`；
- journal 不是远端账本；丢失时通过 trailer、remote refs、approval snapshot 重建，冲突硬阻断。

### 3.2 Lock record

锁目录由原子 `mkdir` 创建，内部 `owner.json`：

```json
{
  "v": 1,
  "token": "random-128-bit",
  "pid": 1234,
  "hostname": "host-a",
  "startedAt": "ISO-8601",
  "op": "merge",
  "cr": "CR-2026-031"
}
```

释放时 token 必须匹配。无 TTL、无 `force-unlock`。同 hostname 下 `process.kill(pid, 0)`：成功或 EPERM 视为存活，ESRCH 视为不存在；foreign hostname、PID 复用证据不一致或 owner 不完整均保守阻断。

锁粒度：operation lock 覆盖单 CR 单事务；Installation Workspace publish lock 只覆盖短时账本/Git stage/commit/push 临界区。先不实现 per-repo publish lock，只有吞吐实测不足后按 CUSTOM-TODO-007 细分。

### 3.3 Recoverable write-set

manifest：

```json
{
  "v": 1,
  "txId": "...",
  "state": "prepared|applying|complete",
  "entries": [
    {
      "path": "workspace-relative-posix-path",
      "beforeSha256": "hex-or-absent",
      "afterSha256": "hex",
      "blob": "blobs/<afterSha256>"
    }
  ]
}
```

恢复规则逐 entry 执行：

- 当前 hash = after：已完成，跳过；
- 当前 hash = before：从 tx blob redo；
- 其余值：返回 `TX_RECOVERY_CONFLICT`，不得覆盖第三方修改；
- 单文件写也使用 one-entry write-set；
- 全部 entry confirmed 后标记 complete，再清理 temp/blob；清理失败不逆转已完成写入。

### 3.4 Signed release snapshot

`review-annotations/code.yml#release-subjects` 由 crctl 机器注入，模型 payload 不得提供或覆盖：

```yaml
release-subjects:
  version: 1
  repositories:
    - repo: tools
      remote-ref: refs/heads/requirement/CR-2026-031
      reviewed-source-sha: <40-hex>
  artifacts:
    algorithm: sha256
    canonicalization: crlf-to-lf+path-sort
    files:
      - { path: change-requests/CR-2026-031/prd.md, sha256: <64-hex> }
      - { path: change-requests/CR-2026-031/sdd.md, sha256: <64-hex> }
    digest: <64-hex>
```

受控 artifact 集合为 PRD、SDD、dev plan、TASK 文件与 task index；路径排序后读取，内容先 `\r\n → \n`。approve-code 重核 ref/HEAD/artifacts，一致后将该块原样复制到 `approval.yml#code.release-subjects`，并由既有 TTY/Ed25519 approval digest 签入。漂移返回 `RELEASE_SUBJECT_DRIFT` 且零写入。

### 3.5 Writeback candidate manifest v1

```json
{
  "v": 1,
  "stage": "baseline|tasks|traceability",
  "cr": "CR-2026-031",
  "specId": "...",
  "targetVersion": "...",
  "inputDigest": "sha256",
  "generator": { "id": "writeback-prd-sdd", "sha256": "sha256" },
  "files": [
    {
      "path": "specs/<spec-id>/PRD.md",
      "beforeSha256": "hex-or-absent",
      "afterSha256": "hex",
      "blob": "blobs/<afterSha256>"
    }
  ]
}
```

`files` 必须唯一且按 POSIX path 字典序排列。v1 仅允许固定 allowlist 中的 create/replace；禁止 absolute、`..`、反斜杠、重复分隔符、symlink parent、delete、rename、chmod 和 executable bit。blob 只能来自当前 tx 的 content-addressed 目录。

### 3.6 Git commit trailer

所有事务 commit 由 crctl 追加，调用方不可覆盖：

```text
AI-First-Op: register|merge|writeback|archive
AI-First-Tx: <txId>
AI-First-CR: CR-2026-031
```

register 增加 `AI-First-Registration-Key-SHA256`；merge 增加 repo/base/approved-source trailer。固定 trailer 是跨机器 journal 重建锚点，不新增 remote journal branch。

## 4. CLI 接口契约

所有写命令成功返回 JSON；失败统一 `{error:{code,message,...}}` 和非零 exit。结构化输出至少含 `op/txId/phase/changed/sideEffects/recoverCommand`。

### 4.1 Register

```text
crctl register --registration-key <opaque-key>
  --title <text>
  --owner-requirement <id> --owner-development <id> --owner-test <id>
  [--summary <text>] [--source <path>] [--target-version <version>]
  --workspace <Installation Workspace>
```

- key 仅按 SHA-256 写入 trailer/journal，不落明文；
- 同 key + 同 inputDigest 复用 CR-ID/txId并续跑；
- 同 key + 不同输入返回 `REGISTRATION_INPUT_MISMATCH`；
- 原子分配 CR-ID、recoverable 三账本写、registration commit/lease push、active repo workspace ensure；
- 默认 roll-forward，不自动删除已健康 workspace/ref。

### 4.2 Workspace

```text
crctl workspace inspect <CR-ID> --workspace <Installation Workspace>
crctl workspace ensure <CR-ID> --mode resume --workspace <Installation Workspace>
crctl workspace cleanup <CR-ID> --mode partial|archived --workspace <Installation Workspace>
```

resolver 唯一读取 workspace `dir-graph.yaml#repositories`，只接受 active、id/path/trunk/role 完整的仓。bucket 由 repo 声明/role 解析，不写死 repo id。canonical path 必须 realpath-contained 于 `.rayai-worktrees/{bucket}`。

workspace 分类：`missing|healthy|branch-only|remote-only|dirty|wrong-branch|path-unregistered`。ensure 只创建/修复能由 Git 和 graph 证明归属的状态；dirty、wrong-branch、unknown 均硬阻断。cleanup 只删除 journal/archive 事实证明归属且 clean 的资源。

### 4.3 Merge

```text
crctl merge <CR-ID> --workspace <Installation Workspace>
crctl merge status <CR-ID> --workspace <Installation Workspace>
```

单入口自动开始或续跑。prepare 阶段无 ref/worktree/账本副作用；publish 逐仓按 `--force-with-lease=<trunk>:<base>` 等价语义更新 ref；部分发布不推进 CR status。所有仓 confirmed 后才执行 knowledge-base finalize。

主要失败码：`RELEASE_SUBJECT_DRIFT`、`APPROVED_ARTIFACT_DRIFT`、`MERGE_PREPARE_CONFLICT`、`MERGE_REMOTE_STALE`、`MERGE_REMOTE_HISTORY_REWRITTEN`、`GRAPH_CHANGED_DURING_TRANSACTION`。

### 4.4 Writeback apply

```text
crctl writeback-apply <CR-ID> --stage baseline|tasks|traceability
  --candidate <manifest-path> --spec-id <id>
  --workspace <operational_workspace>
```

校验 signed snapshot、stage/spec/version/inputDigest/generator hash、manifest schema、blob/before/after hash、allowlist 和 staged set。脚本退出失败或校验失败时 baseline/staged set 保持不变。未发布 candidate 遇 origin trunk 前进时删除旧 candidate，从新 detached origin 基线重新生成，不 rebase/cherry-pick。

### 4.5 Archive

```text
crctl archive <CR-ID> [--spec-id <id>] --workspace <Installation Workspace>
```

单入口续跑状态、四账本/archive event、archive commit/lease push、workspace/ref cleanup。origin 包含 archive commit 后业务状态固定为 archived；cleanup 失败返回 `CR_ARCHIVE_CLEANUP_PENDING`，journal phase=`cleanup-pending`，重跑只续清理。rejected/withdrawn 未合并 remote refs 始终保留并输出 `preservedRefs`。

### 4.6 Upgrade check（临时）

```text
crctl upgrade-check --workspace <Installation Workspace>
```

fetch 后只读 origin trunk 与 active repo remote refs，输出：

```json
{
  "safe": [],
  "requiresReapproval": [],
  "blocksUpgrade": [],
  "canActivate": true
}
```

有 blocker 或事实不确定 exit 1，全程零写入、不创建 workspace、不合成 snapshot。全部安装完成协议切换且无旧事务后，按 CUSTOM-TODO-009 连同 dispatch/help/tests 整体删除。

## 5. 关键算法与流程

### 5.1 远端事实分类

```js
function classifyRemoteCommit({
  remoteSha,
  expectedBase,
  commitSha,
  commitIsRemoteAncestor,
  journalSaysPublished
}) {
  if (commitIsRemoteAncestor) return 'confirmed'
  if (journalSaysPublished) return 'history-rewritten'
  if (remoteSha === expectedBase) return 'pushable'
  return 'rebuild'
}
```

helper 只分类事实。register finalize/writeback/archive 在 `rebuild` 时从新 origin base 重建各自 commit；merge 依 approved source 和新 base 重做无副作用 prepare。`history-rewritten` 一律硬阻断，不猜测、不自动 force。

### 5.2 Merge saga

1. 获取 operation lock，恢复未完成 write-set/journal；
2. 解析 graph 并计算 graphDigest；
3. 校验 status=`code-approved`、approval/test/review gate；
4. 只从 `approval.yml#code.release-subjects` 读取 per-repo approved source 和 artifact digest；
5. 对 remote requirement ref、worktree HEAD、artifact 重核：
   - code/source/TASK drift 且零 trunk publish：原子标记审批 stale，经新增状态转换 `code-approved -> developing`，trigger=`merge-feature-branch:release-drift -> implement-code`；
   - PRD/SDD drift：`APPROVED_ARTIFACT_DRIFT`；
   - 任一 trunk 已 publish 后 drift：保持 blocked，恢复原 ref 后才能续跑；
6. 每仓 fetch base/source，在临时 index/tree 中验证 merge；冲突时 `MERGE_PREPARE_CONFLICT`，零远端副作用；
7. 用 Git `commit-tree` 生成候选 merge commit，parents 固定 base/source，写固定 trailer，不 checkout、不移动本地 trunk；
8. journal 先记 publish intent，再按 lease 逐仓 push，再记 observation；
9. 重入时调用远端分类，confirmed 跳过，pushable 续推，rebuild 重做该仓 candidate，history-rewritten 硬阻断；
10. 所有仓 confirmed 后，在 detached knowledge-base Transaction Workspace 从最新 origin trunk 生成 finalize commit：同一 commit 内写 `status=merging`、完整 `merge-commits[]`、`merge-verification.md` 和事件；
11. origin confirmed 后返回 `operational_workspace`，不再从 CR worktree 或主 checkout 判断 authority。

### 5.3 Writeback

每 stage：

1. crctl 在 Transaction Workspace 读取 signed snapshot 与当前 artifact；
2. 调固定 generator 只生成 candidate/blobs/manifest；
3. 校验 generator SHA 与 manifest/input/before/after；
4. 用 recoverable write-set 应用 candidate；
5. stage 精确 manifest paths，并断言 staged set 完全相等；
6. 由 crctl 生成 commit + trailer 并 lease push；
7. classify remote：confirmed 进入下一 stage，pushable 推送，rebuild 从新 origin baseline 重生成，history-rewritten 硬阻断；
8. 最后状态推进仍由 crctl gate/CAS 完成。

### 5.4 Archive

1. 校验终态前置、TASK done、writeback/traceability/gate；
2. 在 detached Transaction Workspace 用 recoverable write-set 同批生成四账本与 archive event；
3. 生成 archive commit 并 lease push；
4. origin 未 confirmed 前允许 rebuild/续推，业务状态不提前宣称完成；
5. origin confirmed 后将 journal 置 `cleanup-pending`；
6. 删除仅由 graph+journal+Git ancestry 证明归属且 clean 的 archived worktree/local ref；
7. 未合并 rejected/withdrawn remote ref 放入 `preservedRefs`；
8. cleanup 全成功才 complete；失败仍返回 archived + `CR_ARCHIVE_CLEANUP_PENDING`。

## 6. 技术选型与替代方案

| 决策 | 采用 | 拒绝及原因 |
|---|---|---|
| 持久化 | 本地 JSON journal + Git trailer + remote observation | 数据库/队列/远端 tx branch：没有多主机协调需求，新增运维与第二事实源 |
| 跨仓语义 | 单仓 ref CAS + roll-forward saga | 宣称跨 remote 原子：Git 不支持；默认 revert 会保留历史且扩大副作用 |
| 锁 | 原子目录锁 + PID/hostname/token | TTL/force unlock：可能误删仍存活 owner；分布式锁：本轮无共享 `.crctl` 多主需求 |
| 文件事务 | hash 驱动 recoverable write-set | 连续 rename 无恢复：已有半写风险；通用 WAL 框架：超过真实需求 |
| merge candidate | Git `commit-tree`/临时 index | checkout 本地 trunk：污染主工作区并制造恢复状态 |
| writeback | candidate-only generator + crctl apply | 脚本直接改 baseline/commit：越过 authority、gate 与 staged set 校验 |
| 模块化 | 两个内部模块 | commands/、class/factory/plugin：没有第二变化轴，增加导航成本 |
| schema | backlog v2 最低版本 | 永久 v1 migration/fallback：一次性迁移逻辑成为长期分支 |

## 7. FR 到技术实现映射

| FR | 技术实现 | 主要验证 |
|---|---|---|
| FR-01 | `crctl.mjs` 深原语 dispatch；删除旧公开入口；Skill/Pipeline contract 收敛 | static prompt/dispatch contract |
| FR-02 | `durable-tx.mjs` + `workspace-transactions.mjs`；envelope/lock/write-set/fault | kill/restart 与 schema tests |
| FR-03 | `registerCr()`、registration key digest、resolver/workspace classifier | 分配/commit/push/第 N 仓 fault 重入 |
| FR-04 | `mergeCr()`、commit-tree、lease publish、`classifyRemoteCommit()` | 三 bare remote merge matrix |
| FR-05 | detached Transaction Workspace、单 finalize commit、authority resolver | finalize stale/STATUS_DIVERGED tests |
| FR-06 | code review 机器注入、approve 原样签入、release-drift 转换 | TTY/grant/drift 零写入 tests |
| FR-07 | candidate manifest v1、`applyWriteback()`、精确 staged set | path/blob/hash/trunk drift matrix |
| FR-08 | `archiveCr()`、origin-confirmed terminal、cleanup-pending/preservedRefs | cleanup fault 与重复 archive |
| FR-09 | realpath containment、lock owner 验证、删除 caller/generic destructive Git | traversal/symlink/lock tests |
| FR-10 | 只读 `upgrade-check` 与最终协议切换删除计划 | legacy state/partial publish matrix |

## 8. 安全、性能与兼容性

### 8.1 安全

- 所有 path 先转 POSIX workspace-relative，再拒绝 absolute/`..`/反斜杠/空段；parent realpath 必须在声明 bucket/Transaction Workspace 内；
- destructive cleanup 前同时校验 graph repo、canonical path、registered worktree、branch/ref、clean status 和 journal ownership；
- remote push 只允许声明的 origin/trunk/ref，并按 expected SHA lease；不接受调用方任意 refspec；
- release snapshot 字段由 crctl 注入并由 approval digest 签名；模型只能提交 verdict/blockers；
- 保留人工审批 TTY/Ed25519 无旁路；不使用自报 caller 作为身份；
- 不自动 stash/reset 用户内容，不删除未知目录/ref。

### 8.2 性能

- hash/scan 只覆盖 active repos 和受控 artifact/manifest paths；不遍历整个仓库；
- operation lock 串行化同 CR，publish lock 仅覆盖短临界区；不提前拆 per-repo lock；
- content-addressed blob 去重并在 complete 后清理；
- 外部调用量是观测指标，不能通过删 gate/测试/恢复步骤降低。

### 8.3 兼容性和行尾

- Node 标准库、Git CLI，Windows/Ubuntu 双平台；
- 文件哈希和跨行解析统一 `\r\n → \n`，逐行使用 `split(/\r?\n/)`；解析失败硬失败，不回退为空；
- backlog v1 返回 `UNSUPPORTED_BACKLOG_SCHEMA`；
- 新状态转换使正式口径从当前 27 条声明/49 条展开变为 28/50，具名状态仍为 15；同步 `dir-graph.yaml`、断言和文档，禁止 workspace 复制状态机。

## 9. 测试设计与故障注入

### 9.1 最小 fault points

- write-set：manifest durable 后、每个 rename 前/后、complete 前；
- register：CR-ID 分配后、账本 write-set 后、commit 后、push 后、每个 worktree 前/后；
- merge：每仓 prepare 后、intent 后、push 返回前/后、observation 后、finalize commit/push 前后；
- writeback：candidate 后、apply 每 entry、stage 后、commit/push 前后；
- archive：账本 write-set、archive commit/push、每个 cleanup resource 前后。

通过环境变量仅在 test harness 启用确定性 `CRCTL_FAULT_POINT`；生产未设置时零行为。

### 9.2 测试矩阵

1. 三个 bare remote：prepare conflict、第二仓 push 失败、push 成功响应丢失、remote stale、finalize stale、history rewrite；
2. registration：同 key 在每个 fault point 重跑、输入 mismatch、graph 零副作用变化/有副作用变化；
3. workspace：missing/healthy/branch-only/remote-only/dirty/wrong-branch/path-unregistered、symlink escape；
4. write-set：before/after/third value、真实 kill/restart、single-entry 与 multi-entry；
5. release snapshot：payload 注入覆盖、ref/HEAD/artifact drift、TTY 与 Ed25519 approval；
6. manifest：absolute/`..`/反斜杠/乱序/重复/symlink/tx 外 blob/hash/delete/rename/chmod；
7. authority：CR worktree、主 checkout、Transaction Workspace 冲突；
8. archive：origin confirmed 后 cleanup fault、重复调用、preservedRefs；
9. lock：live PID、EPERM、ESRCH、PID reuse、foreign hostname、token mismatch；
10. upgrade-check：developing、旧 code-approved 零 publish、legacy partial merge、authority unknown，全程零写入。

CI 运行 prompt lint、skill/agent/pipeline contracts、crctl tests、writeback tests、JSON parse，并在 Ubuntu/Windows 运行关键 fault vectors。

## 10. 实施切片与提交顺序

在同一 CR 中拆约 12 个 TASK，每个完成即经版本化账本入口登记 done：

1. fault harness 与红测；
2. 删除死代码、重复算法、无调用命令与 v1 永久兼容；
3. repository resolver、containment 和 authority resolver；
4. `durable-tx.mjs`：lock/journal/write-set/fsync/fault；
5. register + workspace inspect/ensure/cleanup；
6. signed release snapshot、approve 重核与 release-drift 转换；
7. recoverable merge + Git fact classification；
8. Transaction Workspace + candidate-only writeback/apply；
9. archive + cleanup-pending/preservedRefs；
10. Skill/Pipeline/Agent/controlled-shell 收敛；
11. 临时 upgrade-check 与激活 preflight；
12. docs/ARCHITECTURE/README/contracts/双平台 CI 与最终统一协议切换。

中间提交不在 trunk 激活半套协议，不添加 feature flag、wrapper 或双写。本 CR 自身继续由旧 Installation Workspace 流程 merge/writeback/archive；origin 全部确认并通过 upgrade-check 后，下一 CR 起使用新协议。

## 11. Prompt 采纳影响

本 CR 修改 `crctl.mjs` dispatch 和 generic Git/guard 命令面，因此本节必填。以下 active Skill 必须从文本算法改为一次深原语调用：

| Skill | 当前问题 | 新调用 |
|---|---|---|
| `skills/requirement/requirement-register/SKILL.md` | 展开 cr-init、commit/push、逐仓 worktree add | `crctl register --registration-key ...` |
| `skills/sync/resume-from-remote/SKILL.md` | 自行 fetch/分类/worktree add | `crctl workspace ensure <CR> --mode resume` |
| `skills/writeback/merge-feature-branch/SKILL.md` | 持有 prepare/push/revert/metadata/finalize 算法 | `crctl merge <CR>`；只解释结构化结果 |
| `skills/writeback/writeback-prd-sdd/SKILL.md` | generator 直接改 baseline，Skill 拼 commit/advance | generator candidate + `crctl writeback-apply --stage baseline` |
| `skills/writeback/writeback-tasks/SKILL.md` | 同上 | generator candidate + `crctl writeback-apply --stage tasks` |
| `skills/writeback/writeback-traceability/SKILL.md` | 同上 | generator candidate + `crctl writeback-apply --stage traceability` |
| `skills/cr/cr-archive/SKILL.md` | 展开状态/账本/push/Remove-Item/prune/report | `crctl archive <CR>` |
| `skills/develop/review-code/SKILL.md` | 模型 payload 未绑定机器 source/artifact snapshot | 仍调 `review-record --stage code`，明确 release-subjects 由 crctl 注入 |
| `skills/develop/approve-code/SKILL.md` | 未描述 approve 重核 snapshot | 仍调 `crctl approve --stage code`，只解释 drift 结果 |
| `skills/shared/controlled-shell/SKILL.md` | caller 三元放行承诺与实现不符 | 删除授权承诺；说明 caller 仅审计标签也一并取消 |

对应 Pipeline：

- `requirement-authoring.pipeline.json` 删除 repo/Git/worktree 算法，只传 register 输入和 execution context；
- `resume-cr.pipeline.json` 删除重复 preflight/worktree add；
- `feature-writeback.pipeline.json` 删除十步 merge、补偿、metadata 和 writeback 内部算法，只保留节点顺序、`operational_workspace` handoff、passCondition/onFail；
- Agent 仅保留 Pipeline 路由，不新增 writeback agent；`requirement-writer` 删除对 Pipeline 内部步骤的复述。

`lint-prompts`/contract tests 必须检查 active prompt 中不再出现裸 `git worktree/merge/revert/push`、手写账本、`--workspace .` 写回、旧命令名或删除后的 `--caller`。

## 12. 风险与恢复边界

- 多 remote 仍可能部分发布；本设计保证可观察和 roll-forward，不承诺瞬时原子；
- `.crctl` 不支持多主机共享；foreign host 锁保守阻断，由操作者回到 owner host 恢复；
- remote history rewrite、第三值文件冲突、无法证明 authority/ownership 都硬阻断，不提供 force；
- release snapshot 协议前的 partial merge/merging/writing-back 不能自动升级；
- 通用事务框架、per-repo lock 和永久 upgrade-check 均延后，分别受 CUSTOM-TODO-008、007、009 约束；
- `tools/CUSTOM.md` 的 TODO/定制登记必须以实施时 tools worktree 实际结构更新，不能依赖主 checkout 未跟踪文件作为交付事实。

## crctl TASK 索引初始化与 task-breakdown 门禁闭环（vtbd · CR-2026-037）

## SDD - crctl TASK 索引初始化与 task-breakdown 门禁闭环

### 1. 架构概览

#### 1.1 已有基础设施（直接复用）

目标仓是 tools 自身，其 `ARCHITECTURE.md` 已存在且不修改。当前已具备：

| 能力 | 现有落点 | 本次用法 |
|---|---|---|
| YAML 子集解析 | `lib/yaml-subset.mjs#parseYaml` | 解析 TASK frontmatter 与已有索引，禁止新解析器 |
| frontmatter 提取 | `workspace-transactions.mjs#matchFrontmatter` | 读取 TASK 卡元数据 |
| 状态权威读取 | `crctl.mjs#resolveCrState` | 限定 init 前置态 |
| 受控文件读取/摘要 | `readFileChecked` / `sha256` | TASK 集合 freshness 与索引 CAS |
| CAS replace | `casWrite` | 刷新全 pending 索引 |
| 原子 create-only | Node `fs.openSync(path, 'wx')` | 首次创建索引；文件已存在则失败重读，不覆盖 |
| 审计/输出 | `auditLog` / `ok` / `fail` | 记录 changed=true 写入与结构化结果 |
| TASK 进度写入 | `cmdTaskDone` + `guardDependsOn` | 保持不变；init 不处理 done |
| 门禁声明 | `gates.json` 既有 `fileExists` | task-breakdown 增一个文件存在检查 |
| 开发计划评审 | `review-dev-plan` | 继续判断业务质量、接口与验收，不下沉 crctl |

#### 1.2 本次最小改造

| 文件 | 改动 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | 增加 `task init` dispatch、TASK 集合机械校验、确定性渲染、create/CAS、审计；`cmdNext(task-breakdown)` 补缺索引恢复建议 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 增加 init/gate/幂等/错误/CRLF 测试 |
| `skills/shared/crctl/gates.json` | task-breakdown 增 `_index.yml` fileExists |
| `skills/shared/crctl/SKILL.md` | 登记命令接口与错误语义 |
| `skills/develop/write-dev-tasks/SKILL.md` | TASK 内容生成后调用 task init，不再手写索引 |
| `pipeline-templates/code-implementation.pipeline.json` | 节点 prompt 只同步调用顺序与失败中止 |

不新增文件、模块、依赖、事务、manifest、状态或 gate type；不修改 README、Agent/matrix、状态机、版本化脚本或 Multica。

#### 1.3 分层与依赖

```text
Agent
  -> 选择 code-implementation Pipeline
Pipeline
  -> write-dev-plan -> write-dev-tasks -> review-dev-plan
write-dev-tasks Skill
  -> 业务拆解并写 TASK-NN.md
  -> crctl task init CR-ID
  -> crctl advance ... task-breakdown
crctl task init
  -> 机械解析 TASK frontmatter
  -> 确定性生成 tasks/_index.yml
  -> create-only / CAS + audit
review-dev-plan
  -> 判断拆分质量、依赖合理性、接口与验收
```

业务判断不进入 crctl；账本算法不留在 Skill/Pipeline；Agent 不拥有状态、Git 或受控写入。

### 2. 数据模型

#### 2.1 TASK 输入投影

仅消费每张 `TASK-NN.md` frontmatter：

```ts
type TaskCardProjection = {
  file: string;             // TASK-NN.md，仅错误 detail 使用
  number: number;           // 文件名 NN
  id: string;               // {CR-ID}-TASK-NN
  title: string;
  status: "pending";
  estimate: `${number}h`;   // 正整数
  dependsOn: string[];
  sourceSha256: string;     // 原始文件字节摘要，仅 freshness 重核
};
```

`slug`、正文、验收条件、plan/sdd ref 不进入索引；`cr-ref`、type 仅校验不投影。

#### 2.2 Canonical `_index.yml`

```yaml
cr-id: CR-2026-037
tasks:
  - id: CR-2026-037-TASK-01
    title: "含冒号: 也安全"
    status: pending
    estimate: 4h
    depends-on: []
  - id: CR-2026-037-TASK-02
    title: "第二项"
    status: pending
    estimate: 6h
    depends-on: [CR-2026-037-TASK-01]
```

约束：

- TASK 按 `number` 数值升序；
- `title` 使用现有 `yamlStringScalar()`（JSON quoted string 是合法 YAML）；
- `id/estimate/depends-on` 已受格式校验，可用 `yamlScalar`/JSON 数组稳定渲染；
- 仅上述字段，末尾单个 LF；
- 无时间戳、hash、schema-version、slug、路径或评审字段；
- 相同 TASK 集合产生逐字节相同文本。

#### 2.3 已有索引进度判定

刷新前解析已有索引：

```text
顶层必须是映射
现有 cr-id 若存在必须等于当前 CR
必须有 tasks 数组
每项必须有 id/status
全部 status 必须精确等于 pending
任何层级出现 done-at 都视为已有进度
```

无法证明“全部 pending”的任何形状都返回 `TASK_INDEX_HAS_PROGRESS`，不尝试修复或迁移。

### 3. 接口契约

#### 3.1 CLI

```text
crctl task init <CR-ID> --workspace <knowledge-base CR worktree>
```

成功响应：

```ts
type TaskInitResult = {
  op: "task-init";
  cr: string;
  file: string;
  taskCount: number;
  totalEstimateHours: number;
  changed: boolean;
};
```

无新增 flags；不接受 TASK 数据、candidate、owner、status、timestamp 或 force。CLI help 与 `crctl/SKILL.md` 同步这一行接口，不复制内部算法。

#### 3.2 允许状态

```text
tech-design-reviewed -> allow create/refresh
 task-breakdown       -> allow pre-development refresh
其他                  -> ILLEGAL_LEDGER_STATE
```

`task init` 不推进 status。Skill 在成功后调用：

```text
crctl advance <CR-ID> --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed
```

当开发启动暂缓后保持 task-breakdown，Skill 只刷新索引，不再次执行该跨态 advance；按状态机现有 `write-dev-tasks` 自环处理，具体状态推进继续由 Skill 调用现有合法转换，不由 init 猜测。

#### 3.3 错误码

| code | 条件 |
|---|---|
| `TASK_SET_EMPTY` | tasks 目录不存在或无 `TASK-NN.md` |
| `TASK_CARD_INVALID` | frontmatter/字段/ID/编号/CR/estimate/status/depends-on 非法 |
| `DEPENDS_ON_UNKNOWN` | 依赖不在本批 TASK 集合（复用既有码） |
| `TASK_DEPENDENCY_CYCLE` | DFS 发现自环或多节点环 |
| `TASK_INDEX_HAS_PROGRESS` | 已有索引不全 pending、含 done-at 或形状损坏 |
| `TASK_SET_CHANGED` | 初读后 TASK 文件集合或任一原始字节摘要变化 |
| `CAS_CONFLICT` | 已有索引在读取后变化（复用既有码） |
| `ILLEGAL_LEDGER_STATE` | 当前状态不允许 init（复用既有码） |

所有失败发生在索引写入和成功审计前。

#### 3.4 幂等与审计

- canonical 文本等于现有索引 LF 规范化文本：返回 `changed=false`，不写文件、不追加成功 audit；
- create/replace 成功：返回 `changed=true`，追加一条 `{kind:'ledger',op:'task-init',cr,actor,taskCount,changed:true}`；
- no-op 不追加审计，保证重复执行没有时间/审计漂移；
- 不发 outbox：TASK 规划索引不是跨设备状态事件，后续 status/checkpoint 走既有通道。

### 4. 关键算法与流程

#### 4.1 读取与校验 TASK 集合

```text
loadTaskCards(ws, cr):
  dir = change-requests/{cr}/tasks
  names = readdir(dir).filter(/^TASK-(\d{2})\.md$/).sort(number)
  if empty -> TASK_SET_EMPTY

  for each name:
    raw = readFileChecked
    norm = raw.replaceAll('\r\n', '\n')
    fm = matchFrontmatter(norm); missing -> TASK_CARD_INVALID(file, frontmatter)
    doc = parseYaml(fm.body); shape invalid -> TASK_CARD_INVALID
    require:
      doc.id == `${cr}-TASK-${NN}`
      doc.type == TASK
      doc['cr-ref'] == cr
      non-empty string title
      doc.status == pending
      estimate matches /^[1-9]\d*h$/
      depends-on is array of strings
    reject duplicate number/id
    collect sourceSha256 = sha256(raw)

  byId = Map(cards)
  for each dependency:
    missing -> DEPENDS_ON_UNKNOWN
  DFS white/gray/black:
    gray revisit -> TASK_DEPENDENCY_CYCLE
  return cards
```

只识别两位编号的 canonical 文件；其他 Markdown 不作为 TASK 输入，也不报错，避免 README/说明文件误入。`write-dev-tasks` 已规定两位编号。

#### 4.2 Freshness 重核

写索引前再次读取目录：

1. 重新计算匹配文件名列表，必须与初读完全相同；
2. 每个文件重新读取原始字节并比较 SHA-256；
3. 任一差异返回 `TASK_SET_CHANGED`。

该重核只防止“解析后、写索引前”的并发陈旧投影，不提供多文件事务，也不锁 TASK 内容文件；调用方重跑即可。

#### 4.3 确定性渲染

局部纯函数 `renderTaskIndex(cr, cards)` 用数组 `join('\n')` 构造 canonical 文本。它不读写文件、不取时间、不访问状态，直接由单元测试覆盖特殊 title、依赖数组和顺序。

#### 4.4 Create / refresh / no-op

```text
cmdTaskInit:
  validate state
  cards = loadTaskCards()
  canonical = renderTaskIndex()
  indexRaw = readFileChecked(indexPath)

  if indexRaw != null:
    validateExistingIndexHasNoProgress(indexRaw)
    expectedHash = sha256(indexRaw)
    recheckTaskCardsFreshness()
    if normalizeLF(indexRaw) == canonical:
      ok(changed=false); return
    casWrite(indexPath, expectedHash, canonical)
  else:
    recheckTaskCardsFreshness()
    try:
      fd = fs.openSync(indexPath, 'wx')
      fs.writeFileSync(fd, canonical, 'utf8')
      fs.closeSync(fd)
    catch EEXIST:
      fail CAS_CONFLICT
    finally close fd if needed

  auditLog(changed=true)
  ok(changed=true)
```

`wx` 是 Node/文件系统原生原子 create-only；不先“exists then write”制造 TOCTOU，不为单文件初始化引入 durable transaction。replace 继续复用现有 CAS。

#### 4.5 门禁与 next

`gates.json`：

```json
"task-breakdown": [
  {"type":"fileExists","path":"change-requests/{cr}/plan.md"},
  {"type":"fileExists","path":"change-requests/{cr}/tasks/_index.yml"},
  {"type":"globNonEmpty","dir":"change-requests/{cr}/tasks","pattern":"^TASK-\\d+.*\\.md$"}
]
```

`cmdNext(task-breakdown)` 在检查 tasks 目录后增加 index 文件检查；缺失时建议 `write-dev-tasks`，why 指明先调用 `crctl task init`。这只修复恢复提示，不复制 gate 判定算法。

#### 4.6 Skill/Pipeline 采纳

`write-dev-tasks`：

```text
生成/回修 TASK-NN.md
-> crctl task init CR
-> 对比 result.totalEstimateHours 与 plan 总估算
-> 初次：advance tech-design-reviewed -> task-breakdown
-> task-breakdown 自环重拆：按现有合法 write-dev-tasks 转换处理
-> crctl git add/commit
```

Pipeline prompt 只保留“写 TASK → 调 task init → advance → 输出列表”的顺序和失败中止；删除“同时生成 `_index.yml`”的直写表述，不嵌入字段校验、DAG、CAS 或 YAML 格式。

#### 4.7 Bootstrap

CR-2026-037 在命令合入前仍需人类一次性创建自身 `_index.yml`。该动作不由 Agent/Skill/脚本执行；内容必须与本 CR 已审批 Plan/TASK frontmatter一致，在开发启动前由人类审阅并提交。例外只覆盖该文件首次创建，不覆盖 status、审批、后续 done 写入或其他 CR；task init 合入后失效。

CR-2026-032 必须等待修复合入 `custom/main`，再从权威 Tools Root 调正式命令，禁止调用候选 worktree 的 crctl。

### 5. 技术选型与替代方案

| 决策 | 采纳 | 否决 | 原因 |
|---|---|---|---|
| 输入来源 | 扫描 TASK frontmatter | JSON/YAML manifest 或 CLI 多参数 | TASK 卡已是唯一业务输入，manifest 会多一份事实源 |
| 代码落点 | 现有 `crctl.mjs` 局部 helper | 新 task-index 模块/版本化脚本 | 改动小、单一调用者；账本写必须留 crctl |
| 创建原语 | Node `openSync('wx')` | durable transaction / exists+write | 单文件 create-only 已由原生原子语义覆盖 |
| 刷新原语 | 现有 `casWrite` | 新 WAL/锁 | 全 pending 单文件替换，CAS 足够 |
| YAML | 现有 parseYaml + 字符串渲染 | 第三方 YAML 库 | 零依赖不变量；输出 shape 固定且很小 |
| DAG | 简单 DFS | 图依赖/拓扑库 | O(n+e) 标准算法，几十行内完成 |
| Gate | 新增 fileExists | 新 gate 类型/深内容校验 | 可信入口 + review-dev-plan 已覆盖语义 |
| generic validate | 不做 | 同 CR 接 PLAN/TASK schema | schema ID 与实际文档冲突，属于独立治理问题 |
| 审计 | changed=true 才写 | no-op 也追加 | 幂等重放不应制造时间/审计漂移 |

### 6. FR 到技术实现映射

| FR | 落点 | 测试 |
|---|---|---|
| FR-01 | §3.1、§4.1、dispatch/help | 创建成功、无数据参数、无状态推进 |
| FR-02 | §2.1、§4.1 | 空集、坏 frontmatter、字段/ID/estimate/depends 错、悬空、环 |
| FR-03 | §2.2、§4.3 | 排序、title 转义、字节稳定、字段白名单 |
| FR-04 | §2.3、§3.2、§4.4 | 两允许态、developing 拒绝、done/损坏拒绝 |
| FR-05 | §3.4、§4.2～4.4 | create-only race、replace CAS、TASK freshness、no-op、audit |
| FR-06 | §4.5 | 缺索引 gate/advance block，补齐后 pass |
| FR-07 | §4.6、§8 | Skill/Pipeline/crctl Skill/help 文案与 JSON parse |
| FR-08 | §4.7 | 人类 bootstrap 边界审计；CR-032 只用已合入 Tools Root |
| FR-09 | §1.2、§5、§7.4 | changed-files 白名单与排除项 |

覆盖率：9/9。

### 7. 安全、性能、兼容与回滚

#### 7.1 安全与一致性

- 路径由固定 CR 根和严格文件名构造，不接受任意 path；
- TASK 文本不进入 audit/outbox；错误只含文件名、字段和 ID；
- create 用 `wx`，refresh 用 hash-CAS；TASK 集合另做 freshness 重核；
- 已有进度 fail-closed，不尝试保留/合并 done 状态；
- parser 读入先 CRLF→LF，解析失败硬失败。

#### 7.2 性能

单次两遍读取 TASK 卡，时间 O(n+e+bytes)，空间 O(n+e+bytes)。TASK 数量小，无缓存、并发或网络需求。

#### 7.3 兼容性

- `task done` 与其一跳依赖守卫零改动；
- 现有索引 reader 继续消费相同 tasks 数组；新增顶层 `cr-id` 已被现有 YAML reader容忍，近期 CR 已使用该字段；
- 老索引只在显式调用 init 且能证明全 pending 时才 canonicalize，不做批量迁移；
- 状态机、reviewLoop、审批和 Pipeline 节点数不变。

#### 7.4 回滚

按单个实现提交 revert 六个白名单文件。回滚后不删除已生成索引：它仍是现有 `task done`/review/writeback 可读的合法账本；只会恢复“无法由 crctl 首次生成”的旧缺口。不得回滚为 Skill 手写索引。

### 8. Prompt 采纳影响

本 CR 新增 `crctl.mjs` dispatch 分支，因此本节必填：

| 消费方 | 现状 | 改为 |
|---|---|---|
| `skills/develop/write-dev-tasks/SKILL.md` | 指导模型生成 TASK 和 `_index.yml` | 只写 TASK 内容卡，然后调用 `crctl task init`；按返回总工时交叉校验，再 advance |
| `pipeline-templates/code-implementation.pipeline.json` 的“拆分开发任务”节点 | prompt 写“同时生成 tasks/_index.yml” | 改为“生成 TASK-NN.md 后调用 task init”；不复制算法 |
| `skills/shared/crctl/SKILL.md` | task 只有 done | 增 init 一行接口、状态与核心错误语义 |
| CLI `HELP` / task dispatch 错误 | 仅列 done | 同步 init 与 done 两个子命令 |

Agent 不需要知道 task-init 算法或新增权限；README 不承担命令细节；其他 Pipeline 不调用该能力。

### 9. 验证计划

定向测试全部追加在现有 `crctl.test.mjs`，复用 fixture helper：

1. 合法 4 卡 create：顺序/字段/总工时/audit；
2. 同内容 no-op：changed=false、字节与 audit 数不变；
3. 全 pending refresh：CAS replace；
4. existing done/done-at/损坏：原字节不变；
5. tech-design-reviewed/task-breakdown 放行，developing 拒绝；
6. 空目录、无 frontmatter、ID/文件/CR/type/title/status/estimate/depends-on 错；
7. 悬空、自环、双节点环；
8. LF/CRLF 等价、特殊 title 安全；
9. TASK 集合/字节 freshness 变化；
10. create EEXIST 与 replace CAS 冲突；
11. task-breakdown 缺 index gate/advance block，补齐 pass；
12. cmdNext 缺 index 建议 write-dev-tasks；
13. 现有 task done/dev-plan/dev-start 回归；
14. lint-prompts、Skill/Agent contract、Pipeline JSON parse。

不新增 production fault point或测试文件。

### 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-13 | v0.1.0 | Ray | 初始设计：单一 task init、原生 create-only + CAS refresh、TASK freshness/DAG/progress guard、索引门禁、Skill/Pipeline 采纳与 bootstrap 边界；FR 9/9 |

## tools Archive 独立小修：cleanup 回显、正常归档 outbox、README 语义（TCA-010 收尾）（vtbd · CR-2026-032）

## SDD - tools Archive 独立小修

### 1. 架构概览

#### 1.1 目标与约束

本设计承接 `CR-2026-032-prd`，只交付来源方案 Phase 1 / 分组 A / T02 的 ARC-03、ARC-04、ARC-05：

1. 将 archive journal 已有的 cleanup 错误与最终 commit 投影到固定返回契约；
2. 正常 `writing-back -> archived` 在 origin 确认后发送 Multica 已支持的 `archive` outbox；
3. 澄清终态 authority 发布与资源 cleanup 是两个阶段。

目标代码仓为 **tools 仓自身**。其 `ARCHITECTURE.md` 已存在，本 CR 直接引用，不修改。设计遵守以下硬不变量：

- `archiveCr()` 继续是 archive 发布、恢复和 cleanup 的单一深模块；不新增 archive 命令、事务框架或账本写入口；
- Git commit 与四账本是 authority，outbox 只是可重建投影；outbox/cleanup 失败不得反转已确认 commit；
- crctl 继续零第三方依赖，新增读入或摘要逻辑遵守 CRLF 规范化和硬失败纪律；
- cleanup 的 clean/dirty/unknown/ancestry/ref 保留算法不变；
- 不修改 `dir-graph.yaml`、`gates.json`、`controlled-shell/rules.json` 或 archive commit trailer；
- 不实施 ARC-02，不检查当前 CR milestone 的 tests/reviews/approval/merge 完整结构。

#### 1.2 改动面与模块边界

| 仓库 | 文件 | 改动性质 | 职责 |
|---|---|---|---|
| tools | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 修改 | 固定 archive 返回字段；在 archive lock/journal 内协调首次 outbox 发送与恢复 |
| tools | `skills/shared/crctl/scripts/crctl.mjs` | 修改 | `cmdArchive()` 注入既有 `emitOutboxEvent()` adapter，构造 schema v1 archive 事件与 warning |
| tools | `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | 修改 | archive 返回、事件、失败、幂等、提前终止和 ARC-02 排除的集成向量 |
| tools | `skills/cr/cr-archive/SKILL.md` | 修改 | 透传固定返回字段和 warning，不复制实现算法 |
| tools | `skills/shared/crctl/SKILL.md` | 条件性小修 | 用途表同步 archive 固定返回/outbox 语义，若现有一行已足够则不改 |
| tools | `README.md` | 修改 | 澄清 authority 已发布与 cleanup-pending 的业务语义 |
| multica | `server/internal/governance/crsync_test.go` | 修改 | 既有 schema 契约测试：archive 投影、run 完成、幂等 |
| multica | `CUSTOM.md` | 修改 | 按当前“代码改动”表顺延登记 CR-2026-032/TASK；测试文件也必须登记 |

Multica production code 保持零 diff。若实现期契约测试证明现有生产代码不能满足 FR-06，应停止并回到设计评审，不得在本 CR 静默扩展生产协议。

#### 1.3 依赖方向

```text
cr-archive Skill / README
          |
          v
cmdArchive() in crctl.mjs
  |       \
  |        +--> emitOutboxEvent(ws, archive event v1)
  v
archiveCr(ctx, input, emitArchiveEvent)
  |
  +--> existing durable archive journal + archive lock
  +--> existing four-ledger write-set / commit / lease push
  +--> existing archiveCleanup()

.crctl/outbox/*.json
          |
          v
Multica daemon collector -> governance.SyncService
          |
          +--> cr_sync_event idempotency ledger
          +--> applyStatus(writing-back, archived, cr-archive)
          +--> complete feature-writeback pipeline_run
```

`workspace-transactions.mjs` 不反向依赖 CLI，也不导入 outbox 文件实现。它只接受一个由调用者提供的窄回调；具体 schema、identity、occurred_at、原子文件写仍留在 `crctl.mjs` 的既有 `emitOutboxEvent()` 中。

#### 1.4 正常归档时序

```text
archiveCr acquire archive lock
  -> load/recover archive journal
  -> build/rebuild four-ledger archive commit
  -> lease push and confirm origin commit SHA
  -> if originalStatus == writing-back and outboxEmitted != true:
       emitArchiveEvent(final confirmed SHA)
       success -> journal.outboxEmitted=true; save journal
       failure -> append EMIT_FAILED warning; keep outboxEmitted=false
  -> archiveCleanup()
  -> return complete or cleanup-pending with the same fixed fields
```

事件发送位于 **origin confirmed 之后、cleanup 之前**。因此它不依赖可能被 cleanup 删除的 Transaction Workspace 或 CR worktree；唯一文件落点是传给 CLI 的 installation/knowledge-base workspace `.crctl/outbox/`。

### 2. 数据模型

#### 2.1 Archive journal payload

在既有 `journal.archive` 上新增一个向后兼容布尔字段；旧 journal 缺失时按 false 解释：

```js
{
  cr: "CR-2026-032",
  phase: "pushed | cleanup-pending | cleanup-attempted | cleanup-failed | complete",
  status: "writing-back | rejected | withdrawn", // 原始状态，既有字段
  commit: "<final confirmed archive commit SHA>", // 既有字段，rebuild 时覆盖
  baseSha: "<lease base SHA>",                    // 既有字段
  pushed: true,                                   // 既有字段
  cleanupDone: false | true | null,               // 既有字段
  lastCleanupError: null | "<structured code>",   // 既有字段，当前未返回
  remaining: [],                                  // 既有字段
  preservedRefs: [],                              // 既有字段
  outboxEmitted: false | true                     // 新增
}
```

`outboxEmitted` 的语义是“本机 archive outbox 文件已由 `emitOutboxEvent()` 成功原子发布”，不是“Multica 已 ACK”。它只阻止同一 journal 在后续 cleanup 重放时主动生成第二份本地事件；服务端 exactly-once 仍由既有 `(cr_id, commit_sha, event_kind)` 唯一键保证。

约束：

- 仅原始 `payload.status === 'writing-back'` 使用该字段；rejected/withdrawn 永不发送且无需置 true；
- outbox 写失败保持 false，使下一次 `recoverCommand` 可重试；
- 远端前进触发 archive commit rebuild 时，在最终 SHA 确认前不得置 true；
- `phase=complete` 但 `outboxEmitted=false` 的历史/失败 journal，幂等重放仍应重试事件，然后固定返回，不新增 commit。

#### 2.2 固定返回模型

所有 `phase=complete`、`phase=cleanup-pending` 和 complete 幂等重放统一返回：

```ts
type ArchiveWarning = {
  code: "EMIT_FAILED";
  event_kind: "archive";
};

type ArchiveRemaining = {
  kind: "txws" | "cr-worktree" | "remote-ref" | "local-ref";
  repo?: string;
  path?: string;
  ref?: string;
  why: "dirty" | "remove-failed" | "not-merged" | "delete-failed";
};

type ArchiveResult = {
  cr: string;
  txId: string;
  phase: "complete" | "cleanup-pending";
  status: "archived" | "rejected" | "withdrawn";
  changed: boolean;
  commit: string;
  lastCleanupError: string | null;
  remaining: ArchiveRemaining[];
  preservedRefs: string[];
  recoverCommand: string;
  warnings: ArchiveWarning[];
  outbox?: string; // 本次成功发送或命中确定性文件时的文件名；未发送/失败时省略
};
```

字段来源固定：

| 返回字段 | 唯一来源 |
|---|---|
| `commit` | `journal.archive.commit`，必须是 classify confirmed 后的最终 SHA |
| `lastCleanupError` | `journal.archive.lastCleanupError ?? null` |
| `remaining` | `journal.archive.remaining ?? []` |
| `preservedRefs` | `journal.archive.preservedRefs ?? []` |
| `recoverCommand` | `archiveCr()` 现有确定性命令生成 |
| `warnings` | 本轮 outbox adapter 返回失败时追加；其他路径为空数组 |
| `outbox` | 既有 `emitOutboxEvent()` 返回的文件名 |

不新增第二份 cleanup error 文件或事件 ledger。

#### 2.3 Outbox schema v1

正常归档复用既有事件结构：

```json
{
  "v": 1,
  "event_kind": "archive",
  "cr_id": "CR-2026-032",
  "from_status": "writing-back",
  "to_status": "archived",
  "trigger": "cr-archive",
  "commit_sha": "<final confirmed archive commit SHA>",
  "actor": "<identity(ws)>",
  "evidence": {},
  "payload": {},
  "occurred_at": "<emitOutboxEvent generated time>"
}
```

文件名使用确定性 `dedup_name`：

```text
archive-<CR-ID>-<final-commit-sha>.json
```

SHA 已由 Git 约束为十六进制，不需要额外可逆编码。确定性文件名处理“文件写成功但 journal 标记前进程终止”的窗口：文件仍在时重放命中同名文件，不增加数量；文件已被 daemon ACK 删除时允许重建同名文件，Multica 的既有数据库唯一键消除重复投影。

#### 2.4 Multica 持久化模型不变

不新增迁移或表字段。继续复用：

```text
cr_sync_event unique key = (cr_id, commit_sha, event_kind)
knownEventKinds["archive"] = true
apply("archive") -> applyStatus(...)
pipelineForStatus("writing-back" | "archived") = feature-writeback
archived -> completeRun(feature-writeback)
```

### 3. 接口契约

#### 3.1 `archiveCr()` 内部接口

现有入口最小扩展为：

```ts
type EmitArchiveEvent = (input: {
  cr: string;
  commit: string;
}) => string | null;

archiveCr(
  ctx,
  {
    cr,
    specId?,
    workspace,
    emitArchiveEvent // 必需；cmdArchive 注入既有 emitOutboxEvent adapter
  }
): Promise<ArchiveResult>
```

实现可直接让回调返回 `string | null`，无需为单一 adapter 新建类、interface 文件或 factory。上面的类型仅用于冻结语义。

`archiveCr()` 在合法 CR-ID 校验之后、获取 archive lock/创建 journal 之前校验 `typeof emitArchiveEvent === 'function'`；缺失或非法以 `ARCHIVE_EMITTER_REQUIRED` 硬失败。该失败必须发生在 commit/push/账本/outbox 等任何 authority 或投影副作用之前。当前生产调用点仅 `cmdArchive()`，因此不保留“无 adapter 仍完成正常归档”的兼容分支。

调用顺序约束：

1. 入口 adapter 已通过 fail-fast 校验；
2. `payload.pushed === true` 且 origin classify confirmed；
3. `payload.status === 'writing-back'`；
4. `payload.outboxEmitted !== true`；
5. 回调参数中的 `commit` 必须等于当前 journal 最终 commit；
6. 回调成功返回非空文件名后，先写 `payload.outboxEmitted=true` 并 `save()`，再进入 cleanup；
7. 回调失败/抛错转换为 `warnings[{code:'EMIT_FAILED', event_kind:'archive'}]`，不抛出 archive 事务失败；
8. rejected/withdrawn 虽接收同一必需 adapter，但由原始状态条件保证不调用。

回调抛错也按发送失败处理，防止测试 adapter 或未来实现绕过 outbox 非阻断不变量。

#### 3.2 `cmdArchive()` adapter

`cmdArchive()` 继续是唯一 CLI adapter：

```js
const result = await runTxAsync(archiveCr(ctx, {
  cr,
  specId,
  workspace: ws,
  emitArchiveEvent: ({ cr, commit }) => emitOutboxEvent(ws, {
    event_kind: 'archive',
    cr_id: cr,
    from_status: 'writing-back',
    to_status: 'archived',
    trigger: 'cr-archive',
    commit_sha: commit,
    actor: identity(ws),
    dedup_name: `archive-${cr}-${commit}.json`,
  }),
}));
```

`occurred_at` 继续由 `emitOutboxEvent()` 生成。`cmdArchive()` 不从已删除的 CR 文件读取 owner/status/commit，不自行解析 journal，也不重复判断 cleanup phase。

CLI 参数、dispatch、退出码保持不变：

```text
crctl archive <cr_id> [--spec-id <id>] --workspace <knowledge-base-main-checkout>
```

`warnings` 是 exit 0 的业务 warning，不新增错误码；cleanup-pending 仍 exit 0。

#### 3.3 幂等与恢复契约

| 场景 | 事件行为 | 返回行为 |
|---|---|---|
| 首次正常 archive，发送成功 | 写一个确定性 archive 文件，journal 标记 true | complete/pending 固定字段，`warnings=[]` |
| cleanup-pending 续跑，已发送 | 不调用 adapter | 固定字段，不新增事件 |
| complete 幂等重放，已发送 | 不调用 adapter，不新增 commit | `changed=false`，固定字段 |
| outbox 写失败 | journal 保持 false | authority 不变，`warnings=[EMIT_FAILED]` |
| outbox 失败后重跑 | 重试同一确定性事件；成功后标 true | 不新增 archive commit |
| 文件写成、journal 标记前中断 | 重跑命中同名文件；若已被采集则服务端唯一键去重 | 不新增 authority commit |
| rejected/withdrawn | 永不调用 adapter | 固定字段，保留既有 `preservedRefs` |
| remote rebuild | 只在最终 confirmed SHA 上发 | `commit` 与事件 SHA 均为最终 SHA |

#### 3.4 文档消费契约

`cr-archive/SKILL.md` 只列固定返回字段和动作：

- `commit`：已确认 authority SHA；
- `lastCleanupError`：cleanup 执行异常码或 null；
- `remaining` / `preservedRefs`：保守保留现场；
- `recoverCommand`：唯一允许的续跑入口；
- `warnings`：投影发送失败，不表示 archive authority 失败。

README 只表达业务阶段，不复制 journal phase、ref ancestry 或 clean 判定算法。

### 4. 关键算法与流程

#### 4.1 统一返回构造

在 `archiveCr()` 内保留一个局部纯函数，所有成功/待清理返回路径复用：

```text
result(phase, changed, warnings=[], outbox=undefined):
  assert payload.commit is non-empty when payload.pushed/complete
  return {
    cr, txId,
    phase,
    status: payload.status == writing-back ? archived : payload.status,
    changed,
    commit: payload.commit,
    lastCleanupError: payload.lastCleanupError ?? null,
    remaining: payload.remaining ?? [],
    preservedRefs: payload.preservedRefs ?? [],
    recoverCommand,
    warnings,
    ...(outbox ? {outbox} : {})
  }
```

该 helper 只消除当前三个返回分支重复，不导出、不新建模块。`commit` 缺失属于 journal 形状损坏，必须以现有 `TxError` 风格硬失败，不得返回空字符串掩盖事实缺口。

#### 4.2 Outbox 发送与 journal 标记

```text
emitArchiveIfNeeded():
  warnings = []
  outbox = undefined

  if payload.status != writing-back:
      return {warnings, outbox}
  if payload.outboxEmitted == true:
      return {warnings, outbox}
  if !payload.pushed or !payload.commit:
      hard fail TX_JOURNAL_INVALID

  try:
      outbox = emitArchiveEvent({cr, commit: payload.commit})
  catch:
      outbox = null

  if outbox:
      payload.outboxEmitted = true
      save(current phase) // 不改变 authority phase，只持久化标记
  else:
      warnings.push({code: EMIT_FAILED, event_kind: archive})

  return {warnings, outbox}
```

调用点有两个：

1. origin 首次 confirmed 后、`save('cleanup-pending')` 之前；
2. `payload.phase === 'complete'` 的早返回之前，用于恢复过去发送失败但 authority 已 complete 的事务。

cleanup-pending 重放会自然经过第一个调用点。发送失败不写 `outboxEmitted`，也不改变 `phase`。

#### 4.3 Cleanup 返回

现有 cleanup 流程保持不动，只改变投影：

```text
before cleanup attempt:
  payload.lastCleanupError = null

archiveCleanup succeeds:
  payload.remaining = result.remaining
  payload.preservedRefs = result.preservedRefs

archiveCleanup/fault throws:
  payload.lastCleanupError = error.code || CLEANUP_FAILED
  save cleanup-failed

if remaining empty and lastCleanupError null:
  save complete
  return result(complete)
else:
  return result(cleanup-pending)
```

因此 dirty/unknown/ref-not-merged 只体现在 `remaining`，`lastCleanupError=null`；执行异常才产生非空错误码。下一次 cleanup attempt 开始前清空旧错误，成功后返回 null。

#### 4.4 Outbox 失败注入

不新增生产 fault point。集成测试在 fixture installation workspace 中预建 `.crctl/outbox` 为普通文件，使既有 `fs.mkdirSync(dir, {recursive:true})` 失败，验证 `emitOutboxEvent()` 返回 null 和 audit `EMIT_FAILED`。测试结束后删除冲突文件并重跑同一 archive，验证事件补发且 commit 数量不变。

该方法覆盖真实文件系统失败路径，避免为一个测试新增环境变量或通用注入框架。既有 `archive-during-cleanup` fault point 继续覆盖 cleanup 异常。

#### 4.5 Multica 契约测试流程

在 `governance/crsync_test.go` 复用当前数据库 fixture 和 `SyncService.ingest/apply` 测试模式：

```text
seed CR status=writing-back
seed active pipeline_run(pipeline_id=feature-writeback, status=running)
construct OutboxEvent v1:
  event_kind=archive
  from=writing-back
  to=archived
  trigger=cr-archive
  commit_sha=<fixed real-looking SHA>
ingest once
assert:
  cr.status == archived
  cr.projected_commit == commit SHA
  feature-writeback run == completed
  cr_sync_event count for key == 1
ingest same event again
assert event count still 1 and projection/run unchanged
```

必须在 `go test -v` 输出中看到目标测试实际 RUN/PASS；若 package `TestMain` 因数据库不可达整体 skip，不能把 exit 0 作为 AC-07 证据。

#### 4.6 测试矩阵

| 向量 | 关键断言 | 覆盖 |
|---|---|---|
| tools adapter contract | 缺失/非函数 adapter 在 lock/journal/commit/push/outbox 前以 `ARCHIVE_EMITTER_REQUIRED` 零副作用失败 | FR-03, TD-BL-1 |
| tools happy path | 固定五字段；commit=origin trailer SHA；一个 archive outbox 字段精确 | AC-01/04 |
| tools preexisting dedup file | journal 标记 false 但确定性文件已存在时命中同名文件、补记 true，文件数量不增加 | AC-04, TD-SUG-1 |
| tools cleanup fault | pending、非空 lastCleanupError、真实 commit；重跑不增 commit/event | AC-02 |
| tools dirty worktree | remaining 有资源、lastCleanupError=null、现场保留；处理后 complete | AC-03 |
| tools outbox failure | exit 0；authority 已发布；warning 精确；重跑补发且零新 commit | AC-05 |
| tools complete replay | changed=false；固定字段；outbox 文件数量不增加 | AC-01/04 |
| tools rejected/withdrawn | 无 archive/status 新事件；preservedRefs 行为不变 | AC-06 |
| tools remote rebuild | 返回 commit 与事件 commit_sha 均等于最终 origin SHA | FR-01/03, R-03 |
| tools current trace fixture | 不新增严格 milestone 结构要求，既有可归档 fixture 继续通过 | AC-09 |
| Multica contract | known kind、合法转换、archived 投影、writeback run 完成、重复 key 幂等 | AC-07 |
| docs/contract | README/Skill 语义，无 cleanup 算法复制；lint-prompts enforce | AC-08/10 |
| Multica diff policy | production code diff 为空；CUSTOM.md 有 CR/TASK 追溯 | AC-11 |

### 5. 技术选型与替代方案

| 决策 | 采纳方案 | 否决方案 | 理由 |
|---|---|---|---|
| outbox 调用位置 | origin confirmed 后、cleanup 前 | cleanup 后在 `cmdArchive()` 发 | cleanup 可能已删 CR/transaction worktree；发送应依赖事务结果和 installation workspace |
| 发送依赖注入 | `archiveCr()` 接受一个必需的窄回调，入口 fail-fast | 可选回调或 lib 导入 CLI `emitOutboxEvent()` | 必需回调封闭 FR-03 不变量；同时保持 lib 不反向依赖 CLI，接口仍小 |
| 首次发送事实 | journal `outboxEmitted` + 确定性文件名 | 仅看 `result.changed` | cleanup 续跑也可能 changed；不能证明事件是否已发 |
| 端到端幂等 | 本地 journal/文件名 + Multica 既有唯一键 | 新建 outbox ACK ledger / exactly-once 协议 | 既有投影通道已接受 at-least-once，新增协议超范围 |
| 发送失败恢复 | warning + 重跑同一 archive | 回滚 archive commit或补偿 commit | 违反 Git authority 不变量，并可能制造更严重漂移 |
| cleanup 错误模型 | 返回 journal 既有错误码 | 新建 error 文件/错误表 | 第二事实源无必要 |
| Multica 验证 | 只加契约测试 | 新增 archive production 分支 | 现有 known kind、applyStatus、transition 和 run completion 已具备 |
| 测试 outbox 失败 | 文件系统冲突 fixture | 新生产 fault point | 用既有失败路径即可，最小改动 |
| ARC-02 | 保持现状 | 本 CR 同时收紧 traceability gate | generator 尚未产出完整结构，会阻断合法归档；按依赖留给 T10A |

### 6. FR 到技术实现映射

| FR | 技术落点 | 验证锚点 |
|---|---|---|
| FR-01 | §2.2 固定模型；§4.1 统一返回 helper | happy path、pending、complete replay、remote rebuild |
| FR-02 | §4.3 直接投影 `lastCleanupError`，区分异常与资源保留 | cleanup fault + dirty worktree |
| FR-03 | §2.3 schema v1；§3.1/3.2 adapter；§4.2 首次发送 | 正常 archive outbox 字段与 SHA、重放数量 |
| FR-04 | §3.3/§4.2 warning 和失败重试；authority 不回滚 | outbox 路径冲突 + 重跑补发 |
| FR-05 | §2.1 状态条件；§3.1 rejected/withdrawn 不调用回调 | 两类终态无 archive/第二 status 事件 |
| FR-06 | §2.4 既有模型；§4.5 Multica 契约测试 | archived 投影、run completion、数据库唯一键幂等 |
| FR-07 | §3.4 README/Skill 消费契约 | 文案评审 + lint-prompts |
| FR-08 | §1.1/§1.2 排除面；§4.6 当前 trace fixture | gates/generator 零 diff，既有归档 fixture 通过 |

覆盖率：8/8。

### 7. 安全、性能与兼容性

#### 7.1 一致性与恢复

- archive lock 覆盖 outbox 判断、发送和 journal 标记，同进程并发不会双发；
- journal 保存使用既有原子 `saveJournal()`，不新建 WAL；
- “文件写成功、标记前崩溃”是 at-least-once 窗口，由确定性文件名和服务端唯一键共同闭合；
- outbox failure 不清除 journal，`recoverCommand` 可重试；
- `commit` 只在 confirmed 后暴露，remote rebuild 的旧 SHA 不进入事件；
- cleanup 删除条件完全不变，不因 outbox 成功而放宽资源删除安全条件。

#### 7.2 安全

- 新事件不含 PRD、审批、路径、cleanup error 正文等敏感内容；只含既有 schema 字段；
- `actor` 继续由 `identity(ws)` 生成，不接受用户 flag；
- outbox 文件名只使用经 CR-ID/SHA 格式约束的值；
- 不修改审批、controlled-shell、状态机或 gate；
- Multica 测试代码和注释遵守英文规则，production code 零 diff。

#### 7.3 性能

每个正常 archive 仅增加一次小 JSON 原子写和一次 journal 保存，复杂度 O(1)。幂等重放仅做布尔判断；不扫描 outbox 目录、不查询网络、不增加数据库调用。archive 主成本仍是现有 Git fetch/push/worktree cleanup。

#### 7.4 兼容性

- CLI 命令和 flags 不变；返回只新增/固定字段，现有消费者可忽略；
- `archiveCr()` 是内部接口且当前只有 `cmdArchive()` 一个生产调用者；本 CR 要求该调用者同步传入必需 adapter，不提供无 adapter 兼容模式；
- 旧 archive journal 缺 `outboxEmitted` 时按 false，若为 writing-back complete journal，首次重放会补事件；
- rejected/withdrawn 结果也获得固定 `commit/lastCleanupError/warnings`，但事件行为不变；
- Multica schema v1、known kind、状态机、数据库结构不变；
- Node 标准库和现有 Go 测试工具链足够，不新增依赖。

### 8. 验证与交付边界

#### 8.1 Tools 最小验证

```text
node --test skills/shared/crctl/scripts/test/archive-tx.test.mjs
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node -e "JSON.parse(require('node:fs').readFileSync('pipeline-templates/feature-writeback.pipeline.json','utf8'))"
```

实施期以仓库实际 package/script 名称为准；不得修改旧断言来掩盖失败。新增行为测试须先在旧实现上证明按预期失败，再实现至绿。

#### 8.2 Multica 最小验证

```text
cd server
go test -count=1 -v ./internal/governance/ -run '<CR-2026-032 archive contract test name>'
```

必须确认输出含目标 test 的 `=== RUN` 与 `--- PASS`。随后按风险运行 governance/daemon 相关既有测试；数据库不可达导致 package skip 时记录为未验证，不得宣称通过。

#### 8.3 Diff 守卫

- tools production diff 只允许 §1.2 列出的 archive 模块；
- Multica 只允许 `crsync_test.go`（或实现期核实后同职责的既有 governance test 文件）与 `CUSTOM.md`；
- Multica `server/internal/**/*.go` 非测试文件、migration、query/generated 文件 diff 必须为空；
- `gates.json`、`dir-graph.yaml`、writeback traceability generator diff 必须为空。

### 9. Prompt 采纳影响

本 CR 不新增或删除 `crctl.mjs` dispatch 分支，也不修改 `rules.json#protectedPaths.deny`，因此 `write-tech-design` 所定义的强制“Prompt 采纳影响”条件不触发。

仍需消除直接消费者的文案漂移：`skills/cr/cr-archive/SKILL.md` 输出补齐固定字段、warning 与 recoverCommand；这不是新命令采纳，而是既有 archive 接口文档同步。`feature-writeback.pipeline.json` 继续只调用同一 `cr-archive` Skill，无节点或参数变化。

### 10. 风险与残余

| 风险 | 控制 |
|---|---|
| R-01 cleanup 后工作树已删 | 事件在 cleanup 前从 journal 结果 + installation workspace 发送 |
| R-02 changed 导致重复发 | 不消费 changed；使用 `outboxEmitted` 与确定性文件名 |
| R-03 remote rebuild 使用旧 SHA | 只在 classify confirmed 后读取当前 `payload.commit` |
| R-04 commit-scan subject 不匹配 | 显式 outbox 是主路径；不改 commit subject，不依赖 fallback |
| R-05 Go package 假绿 | `-v` 核对目标 test 的 RUN/PASS；skip 记未验证 |
| outbox 文件被 ACK 后 journal 标记前崩溃 | 重跑可能重建同名文件，但数据库唯一键幂等，投影不重复；这是既有 at-least-once 边界 |
| journal 成功标记但 daemon 永久未消费文件 | daemon 保留/重试既有 outbox 文件；snapshot reconcile 是最终兜底，不在 archive 内另建 ACK 协议 |

残余工作明确归后续 CR：ARC-02/TRA-03/T10A、checkpoint、test record、traceability/feedback 和静态治理均不在本设计实施。

### 11. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-13 | v0.1.0 | Ray | 初始设计：冻结 archive 固定返回、journal `outboxEmitted`、origin-confirmed 后 cleanup 前显式 archive outbox、失败 warning/恢复、README/Skill 语义和 Multica test-only 契约；FR 覆盖 8/8，排除 ARC-02 |
| 2026-08-13 | v0.2.0 | Ray | 技术评审 attempt-1 回修 TD-BL-1：`emitArchiveEvent` 从可选改为必需，修正返回类型为 `string|null`，入口在任何副作用前以 `ARCHIVE_EMITTER_REQUIRED` fail-fast，删除静默跳过分支并补 adapter 零副作用测试；采纳 TD-SUG-1，增加确定性文件已存在但 journal 未标记的崩溃窗测试 |

## tools Checkpoint 收敛：单一深原语 + latest-checkpoint + 多仓恢复（TCA-011）（vtbd · CR-2026-033）

## 1. 架构概览

### 1.1 设计目标

本设计落实 PRD FR-01～FR-09，将 checkpoint 从 `push-progress` Skill 和 Pipeline prompt 中的逐仓 Git 算法收敛为一个可重入的 `crctl checkpoint` 深原语。目标不是伪造多仓 ACID，而是以 **逐仓 lease publish + exact-head freshness + 持久化 journal + knowledge-base metadata commit** 建立唯一完整批次可见点。

核心不变量：

1. 一次 checkpoint 覆盖 `dir-graph.yaml#repositories` 中全部 active repo；repo、branch、worktree、remote 与 knowledge-base 身份全部由既有 resolver 派生。
2. 所有本地 tracked/untracked 未忽略变化均进入对应 source commit；clean repo 不造空 commit，但仍进入当前批次。
3. 只有 knowledge-base metadata commit 被 origin 精确确认后，`latest-checkpoint` 才成为完整 checkpoint authority。
4. `latest-checkpoint` 只有一个当前快照；Git log 保留历史，journal 只保留未完成事务恢复状态。
5. Skill/Pipeline 只调用一次 `crctl checkpoint`，不拥有 Git、账本编辑或恢复分类。

### 1.2 分层与依赖

```text
Pipeline（是否调用、message、失败中止）
  ↓
push-progress Skill（一次 crctl checkpoint 调用 + 结果解释）
  ↓
crctl.mjs
  ├─ 非终态守卫、CLI 参数、固定 JSON 输出、audit、checkpoint outbox
  └─ checkpointCr(ctx, input)
       ├─ repository/worktree resolver + Git/source commit/publish
       ├─ latest-checkpoint 账本候选与 metadata commit
       ├─ checkpoint-specific exact-head 分类
       └─ durable-tx.mjs
            lock / journal / fault points / durable write
  ↓
Node 标准库 + Git + origin requirement/{CR-ID}
```

依赖保持单向：`workspace-transactions.mjs` 不反向依赖 `crctl.mjs`，也不直接发 outbox；它返回 metadata commit 与结构化结果，由 CLI 层沿用现有 `emitOutboxEvent()` 和 `auditLog()`。

### 1.3 Authority 与完整批次可见点

| 阶段 | Authority | 说明 |
|---|---|---|
| preflight/no-op | 当前 worktree、origin refs、现有 `latest-checkpoint` | 只读/fetch；未创建 journal |
| source committed/published | 各 repo local commit + remote ref | 是可恢复资源，不是完整 checkpoint |
| metadata committed | KB local metadata commit | 尚未被 origin 确认，不供 reader 消费 |
| metadata confirmed | KB remote HEAD = metadata commit | 完整 checkpoint 唯一可见点 |
| complete | metadata-confirmed Git 事实 + audit/outbox 投影 | journal 可清理；outbox 失败不反转 Git authority |

非 KB repo 的完整条件是 remote HEAD 精确等于 source SHA。KB 的完整条件是 remote HEAD 精确等于 metadata commit，且 metadata commit 的直接父提交等于 `latest-checkpoint.repositories` 中 KB 的 source SHA。

### 1.4 模块边界与文件落点

#### 既有模块修改

| 文件 | 变更 |
|---|---|
| `skills/shared/crctl/scripts/lib/durable-tx.mjs` | 增加 `checkpoint` op/payload 与 checkpoint fault points；复用现有锁、journal 与 durable write |
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 增加 `checkpointCr()`、batch/editor/classifier 纯函数和敏感文件预检；不新增第二模块 |
| `skills/shared/crctl/scripts/lib/yaml-subset.mjs` | 将 `matchEntryBlock()` 从 crctl 私有作用域最小下沉并导出，供旧账本命令与 checkpoint editor 共享 |
| `skills/shared/crctl/scripts/crctl.mjs` | 增加 `cmdCheckpoint`、help/dispatch/import/audit/outbox；删除 `checkpoint-add` 及旧 editor/help/dispatch/tests |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 新增三 bare remote、多仓恢复与 exact-head 集成测试 |
| `skills/shared/crctl/scripts/test/durable-tx.test.mjs` | checkpoint envelope/fault point 单元测试 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | CLI 输出/状态守卫/outbox 测试；删除旧 checkpoint-add 契约测试 |

#### T05 caller/reader 迁移

- `skills/sync/push-progress/SKILL.md`
- `skills/sync/list-remote-checkpoints/SKILL.md`
- `skills/sync/resume-from-remote/SKILL.md`
- `skills/sync/pull-progress/SKILL.md`（只移除已删除 `last-push-*` 的摘要依赖，ff-only 算法不变）
- `pipeline-templates/requirement-authoring.pipeline.json`
- `pipeline-templates/architecture-design.pipeline.json`
- `pipeline-templates/code-implementation.pipeline.json`
- `pipeline-templates/resume-cr.pipeline.json`
- `README.md`、`skills/_index.yml`、`ARCHITECTURE.md`

`ARCHITECTURE.md` 在 SDD 撰写期只读；实现期 T05 随新增 crctl 写命令同步更新其入口点/代码地图/运行事实，不另开审批节点。

## 2. 数据模型

### 2.1 `_backlog.yml#latest-checkpoint`

每个 CR 的 `_backlog.yml` 条目只保留一个当前快照：

```yaml
latest-checkpoint:
  batch-id: 0123456789abcdef
  repositories:
    - repo: ai-first-platform-docs
      source-sha: <40-hex>
      remote-ref: refs/heads/requirement/CR-2026-033
    - repo: multica
      source-sha: <40-hex>
      remote-ref: refs/heads/requirement/CR-2026-033
    - repo: tools
      source-sha: <40-hex>
      remote-ref: refs/heads/requirement/CR-2026-033
```

约束：

- `repositories` 按 repo id 字典序稳定排序，数量与事务启动时 active repository graph 完全一致；
- `repo` 唯一，`source-sha` 必须为 40 位小写 hex，`remote-ref` 固定为 `refs/heads/requirement/{cr}`；
- 不持久化 message、actor、时间、本地路径、txId、pushed-at/by/summary；
- editor 每次整块替换 `latest-checkpoint`，同一 metadata commit 删除 `_backlog.yml` 当前 CR 条目中的旧 `checkpoints[]`、`remote-ref`、`last-push-at`、`last-push-by`；
- editor 不修改 `cr.md`，也不改 `_backlog.yml` 其他 CR、未知字段或注释；输入先 CRLF→LF，目标条目/owned key 重复或结构异常时硬失败。

### 2.2 batch-id canonical encoding

为避免字符串拼接歧义，PRD 公式在实现中固定为无空白 canonical JSON：

```js
const input = {
  cr: "CR-2026-033",
  graphDigest: "<64-hex>",
  repositories: [
    { repo: "<id>", sourceSha: "<40-hex>", remoteRef: "refs/heads/requirement/CR-2026-033" }
  ]
};
const batchId = sha256(JSON.stringify(input)).slice(0, 16);
```

对象键顺序按上例固定，repositories 先按 repo id 排序。message、actor、时间、本地路径、txId 不进入 input。同 graph/source facts 重放得到同 id；任一 source SHA、remote-ref 或 graphDigest 变化得到新 id。

### 2.3 checkpoint journal payload

`durable-tx.mjs` 的 `OPS`/`PAYLOAD_KEYS` 增加 `checkpoint`，envelope 增加 `checkpoint: null`。不修改现有 register/merge/writeback/archive/ledger payload。

```json
{
  "v": 1,
  "txId": "<32-hex>",
  "op": "checkpoint",
  "cr": "CR-2026-033",
  "phase": "prepared|sources-committed|repos-confirmed|metadata-committed|metadata-pushed|complete",
  "graphDigest": "<64-hex>",
  "inputDigest": "sha256(JSON.stringify({cr,graphDigest}))",
  "sideEffects": [],
  "lastError": null,
  "checkpoint": {
    "repositories": [
      {
        "repo": "tools",
        "remoteRef": "refs/heads/requirement/CR-2026-033",
        "baseSha": "<40-hex>",
        "sourceSha": "<40-hex-or-null>",
        "remoteBefore": "<40-hex-or-null>",
        "phase": "prepared|committed-local|pushed|confirmed"
      }
    ],
    "batchId": null,
    "kbSourceSha": null,
    "metadataCommit": null
  }
}
```

journal 可记录本机恢复细节，但这些字段不进入 batch-id 或公开 snapshot。`inputDigest` 只绑定 CR 与 repository graph，source facts 由 journal 内各 repo 字段绑定，并允许在 metadata commit 前因恢复重扫而前进。graph 在首个 source commit/push 后变化返回 `GRAPH_CHANGED_DURING_TRANSACTION`。metadata commit 是 source 集合冻结点；其后出现的本地变化属于下一批，不改写已生成的 metadata commit。metadata confirmed 后把 phase 写为 complete；确认 authority 后可删除该 completed checkpoint tx 目录。若进程死在 complete 后、删除前，下一次非 no-op 调用先验证该 batch 仍为 authority，再清理旧 complete journal 并创建新事务。

### 2.4 fault points

一次登记以下固定 point；未知 point 继续 `UNKNOWN_FAULT_POINT`：

- `checkpoint-after-source-commit`
- `checkpoint-after-push`
- `checkpoint-after-confirm`
- `checkpoint-after-metadata-commit`
- `checkpoint-after-metadata-push`

point 只用于确定性测试，不成为公共恢复 API。

## 3. 接口契约

### 3.1 公共 CLI

```text
crctl checkpoint <cr_id> [--message <text>] --workspace <installation-workspace>
```

输入只接受 CR-ID 与可选 message。repo、branch、worktree、trunk、remote、batch-id、actor、时间均内部派生；不接受 files/glob/staged-only/ignore/allow-sensitive/status 等参数。

成功固定输出：

```json
{
  "op": "checkpoint",
  "cr": "CR-2026-033",
  "txId": "<32-hex>",
  "batchId": "0123456789abcdef",
  "phase": "complete",
  "repositories": [
    {
      "repo": "tools",
      "sourceSha": "<40-hex>",
      "remoteRef": "refs/heads/requirement/CR-2026-033",
      "confirmed": true
    }
  ],
  "metadataCommit": "<40-hex>",
  "changed": true,
  "recoverCommand": "crctl checkpoint CR-2026-033 --workspace <workspace>"
}
```

no-op 返回当前 batch、`txId=null`、`changed=false`；`txId` 字段仍存在，但 null 明确表示 journal 前快速路径，不伪造可恢复事务身份。no-op 不建 journal、不更新时间、不 push。失败在 journal 创建后返回非空 `txId/phase/sideEffects/recoverCommand`；零副作用 preflight 错误可省 sideEffects。所有事务错误经既有 `TxError → runTxAsync() → fail()` 转换。

不新增 `checkpoint status`。只读远端查询继续由 `list-remote-checkpoints` Skill 提供。

### 3.2 内部函数

`workspace-transactions.mjs` 新增：

```js
checkpointCr(ctx, { cr, message, workspace })
editLatestCheckpoint(backlogText, cr, snapshot)
checkpointBatchId({ cr, graphDigest, repositories })
classifyCheckpointRemote({ remoteSha, sourceSha, remoteIsSourceAncestor, sourceIsRemoteAncestor, journalSaysPublished })
```

后三个为无 I/O 纯函数并直接单测。`checkpointCr` 是唯一 Git/账本事务处理器；不建 interface/class/factory/registry。

`yaml-subset.mjs` 新增导出：

```js
matchEntryBlock(text, id)
```

`crctl.mjs` 现有 task/owner/backlog/inbox editor 改为 import 该函数，避免复制跨行条目定位器。

### 3.3 exact-head 分类

| Git 事实 | 分类/动作 |
|---|---|
| remote == source | `confirmed` |
| remote 不存在 | 以“ref 必须仍不存在”的 lease 创建，随后精确确认 |
| remote 是 source 祖先 | `pushable`，以当前 remote SHA 做 lease fast-forward，随后精确确认 |
| source 是 remote 祖先且不等 | `CHECKPOINT_REMOTE_ADVANCED`；不写 metadata，提示先同步后重做 |
| 双方分叉 | `CHECKPOINT_REMOTE_DIVERGED`；不 merge、不 push |
| journal 标记已发布，但 remote 不再包含 source | `CHECKPOINT_REMOTE_HISTORY_REWRITTEN` |

该分类独立于既有 `classifyRemoteCommit()`，不得修改 register/merge/writeback/archive 的“commit 是 remote 祖先即可 confirmed”语义。

### 3.4 checkpoint outbox

现有 Multica `server/internal/governance/crsync.go` 消费 `event_kind=checkpoint` 以补全 embedded status 的 `projected_commit`，因此该事件不能随 `cmdGit` 迁移而丢失。

新契约：

- 仅在完整批次 metadata confirmed 后，由 `cmdCheckpoint` 发一次 checkpoint 事件；
- `commit_sha` 固定为 KB metadata commit；payload 可带 `batch_id` 和已确认 repo 摘要；
- `dedup_name` 固定为 `checkpoint-{cr}-{metadataCommit}.json`，复用现有 emitter 的原子写入与同名去重；恢复可重复调用 emitter，但同一 metadata 只留一份待采集事件；
- no-op 不创建新事件；事务中间逐仓 push 不发事件，避免 projected_commit 指向半批次；
- outbox 失败只写 audit，不回滚 Git authority，也不改变公共成功字段。

Multica 不改代码；现有 `TestCheckpointFillsProjectedCommitForEmbedded` 保持通过，tools 侧增加“完整批次确定性去重/no-op 不新增事件”契约测试。

### 3.5 错误码与恢复契约

| code | 触发条件 | 副作用与恢复 |
|---|---|---|
| `CHECKPOINT_WORKTREE_MISSING` | active repo 的 `{repo.worktreePath}/{cr}` 不存在 | 初始 preflight 零副作用；恢复期保留既有 `sideEffects` 并返回同一 `recoverCommand` |
| `CHECKPOINT_WORKTREE_UNREGISTERED` | 路径存在但不在该 repo `git worktree list` | 同上；不自动 adopt/remove |
| `CHECKPOINT_BRANCH_MISMATCH` | worktree 当前分支不是 `requirement/{cr}` | 同上；不自动 checkout |
| `CHECKPOINT_SNAPSHOT_INVALID` | `latest-checkpoint` 缺字段、重复 repo、SHA/ref/graph 集合非法 | journal 前零副作用；不静默降级为“无 snapshot” |
| `CHECKPOINT_SENSITIVE_PATH` | 固定敏感路径或私钥头命中 | 全仓零 add/commit/push，返回命中 repo/path，不输出文件内容 |
| `CHECKPOINT_WORKTREE_CHANGED_DURING_TRANSACTION` | source commit/hook/push 后 worktree 或 index 又变化，metadata 前最终检查不静稳 | 不生成 metadata；保留已有 local commit/push 于 `sideEffects`，返回同一 `recoverCommand`，重跑重做受影响 source |
| `CHECKPOINT_REMOTE_ADVANCED` | source 是 remote 祖先且不等 | 不写 metadata；保留先前 repo 副作用，提示先同步后重做 |
| `CHECKPOINT_REMOTE_DIVERGED` | source 与 remote 分叉 | 不 merge/push/metadata；保留先前副作用并返回恢复命令 |
| `CHECKPOINT_REMOTE_HISTORY_REWRITTEN` | journal 已发布的 source 不再被 remote 包含 | 不继续 publish/metadata；人工确认 remote 历史后重跑 |
| `GRAPH_CHANGED_DURING_TRANSACTION` | 首个 source 副作用后 repository graph digest 变化 | 保留 sideEffects，禁止用新 graph 完成旧 journal |
| `TX_LOCK_HELD` | 同 CR checkpoint 锁已被持有 | 本调用零新副作用；稍后原命令重试 |
| `TX_INPUT_CONFLICT` / `TX_RECOVERY_CONFLICT` / `TX_WRITESET_INVALID` / `TX_BLOB_MISMATCH` | 既有 journal/write-set 与当前事实不一致 | 透传既有 durable-tx 语义，不覆盖第三值；返回 txId、phase、sideEffects、recoverCommand |
| `TX_GIT_FAILED` | 固定 argv 的 Git 操作失败 | journal 前为零副作用；journal 后返回已记录副作用与恢复命令 |
| `UNKNOWN_FAULT_POINT` / `FAULT_INJECTED` | 测试故障点未登记 / 已命中 | 前者零写入；后者保留命中前 journal 与 sideEffects，仅测试使用 |

所有 journal 后错误固定返回 `txId`、`phase`、`sideEffects`、`recoverCommand`；journal 前错误返回 `txId=null` 且不伪造恢复状态。错误表不新增通用错误框架，只冻结 checkpoint 对现有 `TxError`/`runTxAsync()` 的使用。

## 4. 关键算法与流程

### 4.1 全仓 preflight 与敏感文件检查

在任何 `git add/commit/push` 和新 journal 创建之前：

1. 以公共参数 `--workspace=<installation-workspace>` 调用 `resolveRepositories(workspace)`，只用它派生 Installation Root、active repo graph 与 worktree roots；不要求 `ctx.cr` 非空或 operation workspace 自身位于 CR worktree；
2. 以显式 `cr` 对每仓定位 `{repo.worktreePath}/{cr}`，验证真实路径受 containment、路径存在且已登记在该 repo `git worktree list`、当前分支恰为 `requirement/{cr}`；
3. 从 knowledge-base 的 `{kb.worktreePath}/{cr}/change-requests/{cr}/cr.md` 读取 status；`cmdCheckpoint` 复用状态机事实源，只允许非终态；
4. fetch 每仓 `origin requirement/{cr}` 并记录精确 remote HEAD（允许首次不存在）；
5. 以 `git diff --name-only -z --diff-filter=ACMR HEAD --` 收集 tracked 新增/修改/rename 目标，以 `git ls-files --others --exclude-standard -z` 收集未忽略 untracked；对 NUL path 去重，不自行解析 porcelain rename 双路径；
6. 先对全部候选 Git POSIX path 执行固定路径规则，再只读取其中当前存在的普通文件检查 `-----BEGIN ... PRIVATE KEY-----` 头；
7. 任一仓失败则全仓零 add/commit/push，敏感命中统一 `CHECKPOINT_SENSITIVE_PATH`。

固定路径规则与 PRD FR-02 完全一致。路径比较大小写精确；symlink/目录/已删除文件不做内容读取，仍由 Git path 与 repo containment 约束。恢复调用在任何新 add/commit/push 前执行同一全仓敏感预检。扫描复杂度为本轮变化普通文件总字节数，不引入 scanner 依赖、porcelain parser 或例外配置。

### 4.2 journal 前 no-op

仅当以下条件全部成立才返回 no-op：

- 现有 `latest-checkpoint` schema 合法；以当前 graphDigest 与 snapshot repositories 重算 batch-id，结果等于存量 batch-id（由此证明 graph/source facts 一致）；
- 所有 worktree 无未忽略变化；
- 每个非 KB repo：本地 HEAD、remote HEAD、snapshot source SHA 三者精确相等；
- KB：本地/remote HEAD 均为当前 metadata commit，metadata commit 的直接父提交等于 snapshot KB source SHA，remote commit 内的 `_backlog.yml` 包含同一 snapshot；
- repositories 集合、顺序和 remote-ref 完全一致。

满足时返回当前 batch、metadataCommit=KB remote HEAD、`changed=false`；不调用 `loadOrCreateJournal()`，不更新时间、不写 audit/outbox、不 push。message 变化不影响判定。

### 4.3 source commit

no-op 不成立后创建 checkpoint journal，并按 repo id 稳定顺序处理：

```text
git add -A
git diff --cached --quiet
  exit 0 -> sourceSha = HEAD
  exit 1 -> git commit --no-gpg-sign --file=-，sourceSha = new HEAD
  其他   -> TX_GIT_FAILED
durable save sourceSha + local-commit sideEffect（若有）
复核 worktree/index clean；dirty -> CHECKPOINT_WORKTREE_CHANGED_DURING_TRANSACTION
journal repo.phase = committed-local
```

commit message 保持 `wip: {cr} {repo} checkpoint{messageSuffix}`。journal 在每个本地 commit 后 durable 保存；崩溃重跑时若 `HEAD == sourceSha` 且 worktree/index clean 则不重复 commit。若 hook 或外部写入使其再次 dirty，本次不得沿用旧 sourceSha 进入 metadata，按 §4.6 在恢复调用中重新 capture；不在单次命令内无限循环等候外部写入停止。

### 4.4 非 KB publish

对非 KB repo 按 id 排序：

1. fetch 并重读 remote HEAD；
2. 用 checkpoint-specific classifier 判定；
3. `pushable` 时只在 ancestry 已证明 fast-forward 后执行带精确 expected SHA 的 lease push；首次创建要求 ref 仍不存在；
4. push 后再次 fetch/ls-remote，只有 remote HEAD == sourceSha 才记 `confirmed`；
5. push 响应丢失时，重跑通过 remote == source 判 confirmed，不重复 push；
6. 任一 advanced/diverged/history-rewritten 立即中止，不生成 metadata。

已发布 repo 是可恢复副作用，失败 JSON 必须列在 sideEffects 中。

### 4.5 KB metadata commit

所有非 KB repo confirmed 后：

1. 重新检查全部 active repo：`HEAD == journal.sourceSha` 且 worktree/index clean；任一 repo 不满足则抛 `CHECKPOINT_WORKTREE_CHANGED_DURING_TRANSACTION`，不生成 metadata，交由下一次同命令按 §4.6 重新 capture/publish；
2. 将当前 KB HEAD 固定为 `kbSourceSha`；确认 KB remote 等于它或是它的祖先，其他关系按 exact-head 错误阻断；
3. 以所有 repo source facts 生成 batch-id 与完整 snapshot；从此 source 集合冻结，metadata commit 后的新变化属于下一批；
4. `editLatestCheckpoint()` 生成 `_backlog.yml` after image，并用既有 one-entry `applyWriteSet()` 绑定 before/after hash durable 应用；
5. 只 stage `change-requests/_backlog.yml`，复核 staged set 恰为该文件；
6. commit message：`[cr] checkpoint {cr} batch {batchId}`，并带 `AI-First-Op: checkpoint` / `AI-First-Tx` / `AI-First-CR` trailer；
7. 复核 `metadataCommit^ == kbSourceSha`；
8. 以 KB remoteBefore 做 lease push；push 后精确确认 remote HEAD == metadataCommit，且直接父提交 == kbSourceSha；
9. journal phase=complete，返回完整结果；随后 best-effort 清理 completed journal。

只有其他 repo 变化时，KB 不造空 source commit；`kbSourceSha` 可以是上一轮 metadata HEAD，新 metadata commit 直接接在其上，不形成无业务变化的 M1→M2→M3 自循环。

### 4.6 中断恢复

同一 `crctl checkpoint` 入口恢复时，先完成 §4.1 的全仓只读/敏感预检，再按 journal phase 处理：

- metadata 尚未 commit：重扫每个 repo；若 dirty，则执行一次 `git add -A`/source commit，把 `sourceSha` 更新为新 HEAD、`phase` 置回 `committed-local`，即使该 repo 旧 source 曾 confirmed 也必须按 exact-head 再次 publish；若 clean 但 `HEAD != journal.sourceSha`，视为第三值并报 `TX_RECOVERY_CONFLICT`；
- `prepared`：补 source commit；
- `committed-local`：按 remote facts push/confirm；
- `pushed`：先观察 remote，响应丢失时转 confirmed；
- `confirmed`：仅在 `HEAD == sourceSha` 且 clean 时跳过；否则走上述重新 capture；
- 全 repo confirmed 后执行 §4.5 第 1 步最终静稳检查；失败返回 `CHECKPOINT_WORKTREE_CHANGED_DURING_TRANSACTION`，不创建 metadata；下一次原命令会重扫并推进受影响 repo，不要求 stash/reset；
- `metadata-committed`：source 集合已经冻结，只验证 commit、直接父与 snapshot，不重复/改写 commit；此后出现的本地变化留给下一批；
- `metadata-pushed`：确认 remote authority；
- `complete`：返回同一 batch；若另有本地变化，清理已确认的 complete journal 后由下一次 checkpoint 创建新事务。

恢复不 reset/checkout/rebase/cherry-pick/force，不补偿 revert。journal 中任一记录与 Git 第三值冲突即硬失败。该规则只增加 resume 重扫与 phase 回退，不引入后台 watcher、编辑器锁或通用 phase engine。

### 4.7 reader 迁移

`list-remote-checkpoints` 以 KB remote requirement branch 为入口：

1. status 只从该 branch 的 `change-requests/{cr}/cr.md` 读取，不回退 backlog status；
2. 从同一 KB remote branch 的 `_backlog.yml` 读取单个 `latest-checkpoint`；
3. KB remote HEAD 必须是 metadata commit且直接父为 snapshot KB source SHA；非 KB remote HEAD 必须精确等于各自 source SHA；
4. 任一缺仓、超前、分叉、结构错误均标 drift/unknown，不把祖先关系当 synced；
5. “最后推送时间/人”从 KB metadata commit 的 Git author/committer 事实派生，不读取已删除字段。

`resume-from-remote` 在 list 验证完整批次后调用既有 `workspace ensure --mode resume`；`pull-progress` 保留全仓 clean + ff-only 行为，仅调整摘要字段。

## 5. 技术选型与替代方案

| 决策 | 采用 | 否决及原因 |
|---|---|---|
| 多仓一致性 | 可恢复 saga + KB metadata 可见点 | 2PC/数据库/消息队列：不存在共同事务资源，成本与需求不匹配 |
| 当前快照 | 单个 `latest-checkpoint` | `checkpoint-batches[] + latest pointer`：与 Git history/journal 重复事实源 |
| 事务实现 | 扩展既有 durable-tx + 一个 `checkpointCr()` | 新 saga engine/provider/class：只有一个新处理器，无抽象收益 |
| 账本编辑 | 行级定向 editor + 共享 `matchEntryBlock` | 通用 YAML serializer/patch CLI：会重排注释字段且引入第二写入口 |
| freshness | checkpoint-specific exact-head classifier | 修改共享 `classifyRemoteCommit()`：会回归 archive/writeback 的发布证明语义 |
| 敏感检测 | 固定路径 + 私钥头 | gitleaks/熵扫描/例外系统：新增依赖与配置面，超出当前边界 |
| outbox | metadata confirmed 后一次 batch 事件 | 沿用每仓 `cmdGit push` 事件：会把 projected_commit 指向半批次 |
| 查询 | 既有 list Skill | 新 `checkpoint status`：重复公共查询模型并暴露 journal 内部细节 |

## 6. FR 到技术实现映射

| FR | 技术方案 | 主要验证 |
|---|---|---|
| FR-01 | `cmdCheckpoint` + `checkpointCr`；从 Installation Workspace + cr 派生全仓 worktree；状态守卫；固定输出 | 安装根 CLI 黑盒、worktree missing/unregistered/branch mismatch、tracked/untracked/ignored fixture |
| FR-02 | preflight 固定路径与私钥头扫描 | 敏感路径零 index/commit/push；放行 example/sample/template 与普通 pem/key |
| FR-03 | `editLatestCheckpoint` + canonical batch-id | editor LF/CRLF、旧字段一次删除、同 facts 同 id/变化 facts 新 id |
| FR-04 | journal 前 no-op + KB parent/metadata 算法 | 零 journal/no push；KB direct-parent；仅非 KB 变化 |
| FR-05 | checkpoint journal + resume 重扫/re-source + exact-head classifier + lease publish | kill/restart、source/部分 push 后新增变化、response lost、advanced/diverged/history rewrite |
| FR-06 | 4 个 Pipeline 文件共 6 个 checkpoint/remote-compare 节点收缩 | prompt 静态 contract：无 Git/账本算法 |
| FR-07 | push/list/resume/pull Skill 迁移 | remote branch reader、drift、ff-only 恢复摘要 |
| FR-08 | T05 同提交删除 checkpoint-add 与旧 reader/caller | dispatch/help/tests/docs 全仓零残留（历史文档/CUSTOM 除外） |
| FR-09 | T01 红测→T03 pure/editor→T04 transaction→T05 migration | 253 crctl + 10 writeback 基线保持；Ubuntu/Windows CI |

## 7. 安全、性能与可观测性

### 7.1 安全

- 所有 repo/worktree/ref 来自 resolver 与固定 `requirement/{cr}`，不接受任意路径/refspec；
- 敏感扫描在全仓任何 add/commit/push 前完成；命中不提供绕过；
- push 只在 ancestry 证明 fast-forward 后使用精确 lease，不使用无条件 force；
- metadata stage 精确复核 staged set，防止把 source commit 后新出现的文件混入账本 commit；
- 行尾规范化、重复 key、跨行条目定位失败均硬失败，不静默生成空 snapshot。

### 7.2 性能

- no-op 快速路径仍需 fetch 与 remote exact-head 核对，这是正确性成本；但不创建 journal/commit/push；
- repo 数量按当前 active graph 线性处理；不并行 push，避免并发错误与恢复顺序复杂化；
- 敏感内容扫描为 O(本轮变化普通文件总字节数)，使用 Node 标准库，不维护缓存；
- 不为当前三仓规模增加 worker pool、锁分片或增量索引。

### 7.3 审计与观测

- `cmdCheckpoint` 成功/失败沿用 `.crctl/audit.log`，记录 cr/txId/batchId/phase/changed/repo 摘要，不写文件内容或 secret；
- 完整批次成功后一次 checkpoint outbox；失败只审计、不回滚；
- 错误 JSON 公开 phase/sideEffects/recoverCommand，journal 路径和本地绝对路径不进入 `latest-checkpoint`。

## 8. Prompt 采纳影响

本 CR 新增 `crctl.mjs` dispatch `checkpoint`，因此本节必填。T05 必须逐项迁移：

| 调用方 | 现状 | 改为 |
|---|---|---|
| `skills/sync/push-progress/SKILL.md` | Skill 手写 inspect/add/commit/push/rev-parse，并逐仓 checkpoint-add | 一次 `crctl checkpoint {cr_id} [--message ...] --workspace <ws>`，只解释 phase/batch/repos/errors |
| `skills/sync/list-remote-checkpoints/SKILL.md` | 读 `checkpoints[]`、last-push、status fallback | 读 remote KB `latest-checkpoint` + cr.md status，exact-head 判 synced/drift |
| `skills/sync/resume-from-remote/SKILL.md` | 依赖 list 验证但未声明 metadata-confirmed snapshot | 明确只恢复 list 已确认的完整 batch；workspace ensure 算法不变 |
| `skills/sync/pull-progress/SKILL.md` | 摘要读取 `last-push-at/by` | 从 KB metadata commit 派生时间/人；ff-only Git 流程不变 |
| `requirement-authoring.pipeline.json` checkpoint 节点 | 复制全仓 push 与 checkpoint-add 字段 | 只传 cr_id/message，消费 batchId/repositories/phase |
| `architecture-design.pipeline.json` checkpoint 节点 | 复制 git add/commit/push/checkpoint-add | 同上 |
| `code-implementation.pipeline.json` 任务/代码/审批 3 节点 | 三次复制逐仓 Git 与旧账本字段 | 三节点各只调用 push-progress 并消费结构化输出 |
| `resume-cr.pipeline.json` 远端比对节点 | 复制旧字段比较算法 | 只调用 list-remote-checkpoints 并消费 synced/drift/unknown |
| `README.md` | 多处承诺 `checkpoints[]`、last-push 字段 | 只保留完整 checkpoint 定义、阶段用途与失败语义 |
| `skills/_index.yml` | crctl/push-progress brief 仍列 checkpoint-add | 更新为单一 checkpoint 深原语 |
| `ARCHITECTURE.md` | 未列 checkpoint 写事务 | 增加 checkpoint 到 crctl/durable transaction 运行事实与测试入口 |

不修改 `controlled-shell/rules.json#protectedPaths.deny`。新 Git 副作用位于既有 workspace transaction 内部，走固定 argv 的 `gitMust()`，不扩大 Skill 可执行白名单。

## 9. 测试与故障注入

### 9.1 基线

SDD 撰写时已在 tools CR worktree 实跑：

- `node --test skills/shared/crctl/scripts/test/*.test.mjs`：253/253 pass；
- `node --test skills/writeback/scripts/test/*.test.mjs`：10/10 pass。

实施不得放宽旧断言。T01 先提交在旧实现下预期失败的 checkpoint 契约测试，再实施 T03/T04/T05。

### 9.2 三 bare remote 最小矩阵

1. 从 Installation Workspace 根调用成功；worktree missing/unregistered/branch mismatch 使用冻结错误码且全仓零 add/commit/push；
2. 敏感路径/私钥头：index 原样、全仓零 commit/push；例外文件不误拦；含空格与 rename 目标 path 不漏扫；
3. tracked + untracked + ignored：source commit 完整包含前两类、排除 ignored；
4. 三仓有变化与单仓 clean；
5. existing snapshot 完全未变：journal 目录数、commit 数、remote refs、outbox 均不变；
6. source commit/hook 后新增变化：本轮不生成 metadata，重跑更新 sourceSha 后完成；
7. 第二仓 push 后进程退出并新增变化：重跑不重复未变化 repo，受影响 repo 重新 source/publish，metadata 只引用新 SHA；
8. push 响应丢失，重跑观察 remote 收敛；
9. remote ancestor source：lease fast-forward 后精确相等；
10. remote advanced/diverged/history-rewritten：冻结错误码、对应 sideEffects 且零 metadata；
11. metadata commit/push 前后故障与响应丢失：单 metadata commit，direct-parent 正确；
12. 只有非 KB repo 变化：KB source 为上一 HEAD，不造空 source commit；
13. malformed snapshot、CRLF backlog、Windows path、未知 fault point 使用冻结错误码硬失败；
14. 完整批次按 `checkpoint-{cr}-{metadataCommit}.json` 去重，no-op 不新增事件；
15. T05 静态扫描证明 active Skill/Pipeline/README/help 无旧 checkpoint-add 算法/字段。

## 10. 实施顺序、回滚与风险

### 10.1 提交顺序

1. **T01**：冻结 schema/错误码/fault points，新增旧实现下失败的测试；保留 253+10 绿基线。
2. **T03**：durable checkpoint payload、共享 `matchEntryBlock`、latest editor、batch/classifier 纯函数及单测。
3. **T04**：`checkpointCr`、CLI dispatch/help/audit/outbox、多仓 publish/recover 集成测试。旧 push-progress/readers 仍使用旧入口。
4. **T05**：同一可回滚提交迁移 4 个 Skill、4 个 Pipeline 文件（6 节点）、README/index/ARCHITECTURE，并删除 checkpoint-add/旧 tests/旧文案。T05 完成即切换，不双读。

### 10.2 回滚

- T03/T04 尚未迁移 caller，可独立 revert，新命令无人消费；
- T05 必须整提交 revert，不能只恢复 reader 或只恢复 writer；
- metadata-confirmed 的新 snapshot 不回迁旧 `checkpoints[]`。若代码回滚到旧协议，必须先停止新调用并按 Git 历史人工选择协议版本，不生成伪 legacy 数据；
- 事务失败不自动 revert 远端 source commit，恢复方向只有继续完成或在 remote drift 时硬阻断。

### 10.3 风险

| 风险 | 控制 |
|---|---|
| remote 在 preflight 与 push 间前进 | 精确 lease + push 后再次 fetch 确认 |
| metadata commit 自引用或空转 | snapshot KB source 固定为 metadata 直接父，batch 排除 metadata SHA |
| 旧 complete journal 阻塞下一批 | authority 确认后清理；残留时下次先验证再清理 |
| 迁移时 writer/reader 协议错位 | T05 同一提交切换 caller/reader并删除旧入口 |
| checkpoint outbox 丢失/重复 | CLI 层在 metadata-confirmed 后按 cr+metadataCommit 确定性去重；Multica 现有消费者契约测试保持 |
| `pull-progress` 读取已删除字段 | T05 仅改摘要为 metadata Git 事实，不改 ff-only 行为 |
| ARCHITECTURE 与新写命令漂移 | T05 同步更新；本轮 SDD 不借道提前改 living baseline |

## 11. 不做事项

- 不新增数据库、消息队列、分布式锁、2PC、第三方 secret scanner 或 npm 依赖；
- 不新增通用 saga/phase runner、repository interface、provider、registry、plugin、第二事务模块；
- 不新增 checkpoint history 数组、status API、文件选择参数或敏感绕过配置；
- 不自动 merge/rebase/force/reset/补偿 revert；
- 不永久双读旧 `checkpoints[]`，不伪造 legacy batch；
- 不修改 Multica 代码或 `CUSTOM.md`；本 CR 只保持其既有 checkpoint outbox 消费契约；
- 不实施 Test/Traceability/feedback/静态治理后续分组 T06～T16。

## tools CR 生命周期最小优化 1/5 — Writeback 原子化（vtbd · CR-2026-038）

## 1. 架构概览

### 1.1 设计目标

本设计落实 PRD FR-01～FR-04，在现有 `crctl writeback-apply` 和 `crctl merge` 内闭合两个边界：

1. baseline 文件、`merging -> writing-back` 状态、commit、lease push、status outbox 和 advance audit 成为一个可恢复发布单元；
2. `_backlog.yml` 合并只采用 CR source 中目标 CR 的完整条目，其他内容以最新 trunk 为准并逐字保留。

本 CR 不重建 durable transaction、状态机、YAML parser、generator 平台或 Git adapter。实现优先级固定为：复用现有能力 > Node 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码。当前 tools worktree 已核实存在以下可复用能力：

- `workspace-transactions.mjs#applyWriteback()`：manifest 校验、recoverable write-set、精确 stage、commit、lease push 和远端事实分类；
- `crctl.mjs#performAdvance()` / `runGateChecks()`：状态机转换与目标态门禁；
- `durable-tx.mjs`：lock、journal、write-set、fault point；
- `workspace-transactions.mjs#matchEntryBlockTx()` 与 `crctl.mjs#matchEntryBlock()` 同类条目块定位逻辑；
- `skills/writeback/scripts/`：三个 candidate-only 确定性 generator；
- `mergeCr()`：`merge-tree --write-tree`、`commit-tree`、lease publish 和 rebuild；
- archive 的 origin-confirmed 后 outbox、journal marker 和 warning 恢复模式。

### 1.2 逻辑分层与职责边界

```text
Agent
  路由、职责判断、选择 feature-writeback Pipeline / writeback Skill
  不保存状态机，不执行 Git 算法，不写受控文件
    ↓
feature-writeback Pipeline
  节点顺序、业务输入传递、失败中止
  不展开 generator、candidate、manifest、advance、journal、commit/push 算法
    ↓
writeback-* Skill
  前置业务判断、一次 writeback-apply 调用、结果分类、失败语义
  不手写 candidate 路径、账本、状态或 Git
    ↓
crctl.mjs
  CLI 业务参数、状态/门禁适配、outbox/audit adapter、结构化结果
    ↓
workspace-transactions.mjs
  固定 generator 调用、manifest preflight、merge/writeback Git 事务与恢复
    ├─ durable-tx.mjs：lock / journal / recoverable write-set
    ├─ skills/writeback/scripts/：PRD/SDD/TASK/traceability 确定性转换
    └─ Node 标准库 + 原生 Git
```

各层严格遵循以下边界：

| 模块 | 应拥有 | 本 CR 明确不放入 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | Skill 完整算法、账本拼接、candidate/manifest 路径 |
| Skill | 业务判断、步骤编排、输入输出、失败语义 | 原子账本逻辑、重复实现 crctl、手写 commit/push |
| `crctl` | 状态、门禁、CAS、受控账本、审计、原子提交和恢复 | PRD/SDD 内容判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 确定性转换 | 状态推进、人工审批、Git 发布 |
| README | 人读流程总览和权威入口 | 可执行算法、状态机或错误矩阵副本 |

`workspace-transactions.mjs` 继续不反向依赖 `crctl.mjs`。状态门禁、outbox 和 audit 通过与 archive 相同的窄 callback 注入；不为此新增 service/interface/factory。

### 1.3 核心不变量

1. `writeback-apply --stage baseline` 是 `merging -> writing-back` 的唯一生产组合入口；调用方不能传任意 `to` 或 `trigger`。
2. 新事务的完整 generator/manifest/before/snapshot/gate preflight 必须发生在 writeback lock 和 journal 创建之前。
3. 只有 manifest 完整验证后的精确目标路径可作为 `fileExists` 的 planned-existing；其他 gate 类型只读当前 authority。
4. baseline manifest 文件与 `cr.md` 状态候选进入同一 `applyWriteSet()`、同一 staged set、同一 commit 和同一次 lease push。
5. status outbox 与 `kind: advance` success audit 只能在 origin 已确认包含 writeback commit 后发送，并携带该真实 SHA。
6. candidate 是 `.crctl/` 下可丢弃派生物，不是 authority、恢复账本或公共接口。
7. `_backlog.yml` 合并以最新 trunk 完整文本为基底，只替换目标 CR 的唯一完整条目；不读取或生成 backlog status。
8. merge 最终 commit 的两个 parent 仍是最新 trunk 和原始 CR source；内部 synthetic commit 只用于计算 tree，不成为发布 parent 或 ref。
9. 所有文本解析先按 `CRLF -> LF` 建立解析视图；结构未唯一命中必须硬失败，禁止返回空结果或整文件回退。
10. 不增加 npm 依赖、后台清理器、candidate manager、generator registry、通用 YAML patch 或第二事务框架。

### 1.4 Authority 与副作用边界

| 阶段 | Authority | 允许副作用 |
|---|---|---|
| 新事务 preflight | txws 当前 HEAD、origin refs、CR canonical 文件 | fetch；`.crctl/candidates/` 可丢弃输出；无 lock/journal/target write/audit/outbox |
| journal created | 预检通过的 manifest digest + canonical business-input digest；journal `createdAt` 同时冻结为 transitionAt | writeback journal 与 lock |
| write-set applied | txws 工作树/index | recoverable baseline + status after image |
| committed | txws commit | 本地 commit；尚未发送 success 投影 |
| origin confirmed | origin trunk 包含 commit | Git 权威事实成立 |
| projections emitted | origin-confirmed commit + journal marker | status outbox、advance audit；失败只 warning |
| complete replay | origin + journal | 只补缺失投影，零新 commit/push |

已存在 journal 的调用属于恢复，不是新事务：先只读识别既有事务，再在原 lock 下恢复持久化 write-set 和 phase；不得清理固定 candidate 后生成不同输入。该分支不违反“非法新输入零 journal”，因为它不创建新 journal，也不把调用方输入写入既有事务。

### 1.5 文件改动边界

#### 生产代码与契约

| 文件 | 设计变更 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | 收缩 `writeback-apply` 公共参数；提炼无写入的 advance preflight；`runGateChecks` 增加仅供 `fileExists` 使用的 planned-existing；注入 status outbox / advance audit adapter；更新 help |
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 固定 generator map/candidate path、完整 preflight、baseline 复合 write-set、projection marker；增加 backlog 条目替换纯函数和 semantic merge tree 构造；初次与 rebuild 共用同一 prepare helper |
| `skills/shared/crctl/scripts/lib/durable-tx.mjs` | 仅登记 journal-created 与 projection writeback 故障点；不改事务模型 |
| `skills/writeback/writeback-prd-sdd/SKILL.md` | 收缩为业务输入 + 一次 `writeback-apply` + 结果分类；删除 generator、candidate 和独立 advance |
| `skills/writeback/writeback-tasks/SKILL.md` | 删除 generator/candidate 路径；一次深原语调用 |
| `skills/writeback/writeback-traceability/SKILL.md` | 保留 milestone 业务草稿；删除 generator/candidate 路径；一次深原语调用 |
| `pipeline-templates/feature-writeback.pipeline.json` | 三个 writeback 节点只传业务输入并调用 Skill；baseline 节点删除独立 advance |
| `skills/shared/crctl/SKILL.md`、`skills/_index.yml` | 同步既有命令接口与深原语职责，不增加新 Skill |

#### 测试

- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`
- `skills/shared/crctl/scripts/test/merge-tx.test.mjs`
- `skills/shared/crctl/scripts/test/archive-tx.test.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`
- `skills/writeback/scripts/test/writeback.test.mjs`（generator 内部 ABI 保持时只补固定路径/调用边界断言，不重写算法测试）

本 CR 不修改 Agent、README、状态机、`gates.json`、`rules.json`、三个 generator 的内容转换算法、Multica 代码或 knowledge-base baseline 文档。

## 2. 数据模型

### 2.1 公共业务输入

`writeback-apply` 仅接受业务输入：

```text
cr_id
target stage: baseline | tasks | traceability
spec_id
target_version
baseline optional: milestone_name, brief
traceability required: milestone_file
workspace
```

删除公共生产参数：

```text
--candidate
--candidate-out
--generator
--manifest
```

stage 到 generator 的映射是 `workspace-transactions.mjs` 内固定常量，不做可注册配置：

```js
const WRITEBACK_GENERATORS = {
  baseline: "writeback-prd-sdd.mjs",
  tasks: "writeback-tasks.mjs",
  traceability: "writeback-traceability.mjs"
};
```

三个版本化脚本保留内部进程 ABI `--candidate-out`，但只有 `crctl` 可以构造和调用；它不是 Agent/Pipeline/Skill/公共 CLI 接口。

### 2.2 Candidate 路径

固定路径：

```text
{operational_workspace}/.crctl/candidates/{CR-ID}/{stage}/
  manifest.json
  blobs/{sha256}
  specs/... 或 delivery/...
```

约束：

- 根由 `resolveOperationalWorkspace()` 返回的 txws 派生，不接受调用方路径；
- `realpath(txws)` 与 candidate 已存在父链逐段检查，任何 symlink/junction 越界返回 `WRITEBACK_CANDIDATE_OUTSIDE_TX` 或 `WRITEBACK_SYMLINK_PARENT`；
- 调用 generator 前确保 txws 的 `.crctl/.gitignore` 使用既有 `*` 规则，`git check-ignore` 必须确认 candidate 被忽略；
- 新事务可清空本 stage 目录后重建；既有 journal 恢复必须复用原固定 candidate，不得重生成不同 manifest；
- archive/workspace 现有 txws 清理会连同 `.crctl/candidates` 删除，不新增清理状态或后台任务。

### 2.3 Manifest 内存快照

preflight 只读一次 `manifest.json`：

```js
{
  textLf,          // 原文 CRLF -> LF，一次读入
  digest,          // sha256(textLf)
  parsed,          // manifest v1
  files: [
    {
      path,
      beforeSha256,
      afterSha256,
      blobText      // 校验 blob hash 时一次读入，apply 阶段复用
    }
  ],
  plannedExisting  // Set<POSIX workspace-relative path>
}
```

`plannedExisting` 只能由 `parsed.files[].path` 生成，且生成前必须已完成 schema、stage、CR、spec-id、path safety、containment、symlink parent、allowlist、before/after hash、blob hash、generator hash、input digest 和 stage 目标矩阵校验。

manifest 文本、blob 文本和 digest 在事务期不二次读取。candidate 后续被修改不影响已通过 preflight 的内存快照；txws 目标仍由 before hash 和 recoverable write-set CAS 保护。

### 2.4 Baseline 状态候选

advance preflight 返回无副作用候选描述：

```js
{
  from: "merging",
  to: "writing-back",
  trigger: "writeback-prd-sdd",
  path: "change-requests/{CR-ID}/cr.md",
  beforeSha256: "<64-hex>",
  beforeText: "<canonical current text>"
}
```

目标文本使用共享的 `crMdStatusText(text, newStatus, { at })` 状态 writer 生成。baseline 固定传入 `at=journal.createdAt`：journal envelope 已先原子持久化，因此即使进程死在 journal 创建后、状态 after image 保存前，恢复也能以同一个 `transitionAt` 确定性重建完全相同的 after text/after hash。首次生成后把完整 after image交给 recoverable write-set，并把 transitionAt/beforeSha256/afterSha256 写入 payload；后续恢复优先复用已持久化事实。受控时间字段的名称、兼容读取和渐进迁移继续由同一共享 writer 决定：本 CR 只增加可选 `at` 注入，不复制 `updated`/`updated-at` 分支，也不抢占 CR-2026-039 的时间字段统一范围；若该切片先合入，本设计自动消费其统一后的 writer。`performAdvance()` 与 baseline writeback 共用同一无写入 advance preflight；前者不传 `at` 时保持现有当前时间语义，后者把候选转成 write-set entry。不得复制状态转换表或在 `applyWriteback()` 内硬编码门禁。

baseline staged set 固定为：

```text
manifest.files[].path
+ change-requests/{CR-ID}/cr.md
```

staged set 必须精确相等，多一项或少一项均 `WRITEBACK_STAGED_MISMATCH`。

### 2.5 Writeback journal 增量

沿用现有 writeback payload，只增加 baseline 投影和状态事实：

```json
{
  "cr": "CR-2026-038",
  "stage": "baseline",
  "phase": "start|committed|pushed|complete",
  "specId": "tools-cr-lifecycle",
  "targetVersion": "0.1.0",
  "businessInputDigest": "<64-hex>",
  "manifestDigest": "<64-hex>",
  "committed": false,
  "commit": null,
  "baseSha": null,
  "pushed": false,
  "files": null,
  "statusTransition": {
    "from": "merging",
    "to": "writing-back",
    "trigger": "writeback-prd-sdd",
    "path": "change-requests/CR-2026-038/cr.md",
    "transitionAt": "<journal.createdAt>",
    "beforeSha256": "<64-hex>",
    "afterSha256": "<64-hex>"
  },
  "outboxEmitted": false,
  "auditEmitted": false
}
```

- `businessInputDigest` 使用固定键序无空白 JSON：`{cr,stage,specId,targetVersion,milestoneName,brief,milestoneFile}`；不适用字段显式为 null，targetVersion 先去可选 `v` 前缀，milestoneFile 规范化为 operational-workspace-relative POSIX path；
- journal envelope 的 `inputDigest = sha256(JSON.stringify({businessInputDigest,manifestDigest}))`，新事务创建与恢复都按同一公式计算；任一公共业务参数漂移返回既有 `TX_INPUT_CONFLICT`，不得误续旧 candidate；
- manifest 的 `targetVersion` 必须等于规范化后的公共 `targetVersion`，不是只检查非空；
- milestone 文件内容不单独进入 business input：新事务的内容已经进入 generator 输出和 manifestDigest；既有事务恢复以已冻结 candidate roll-forward，源文件后续变化留给下一事务；
- tasks/traceability 的 `statusTransition` 为 null，不发送 status outbox 或 advance audit；
- 旧 journal 缺新布尔字段按 false 读取；旧 journal 缺 businessInputDigest/manifestDigest 时，只有现有 envelope inputDigest 与固定 candidate 可按旧公式证明一致才允许完成既有事务，不静默嫁接新参数；
- `outboxEmitted` 和 `auditEmitted` 只在 adapter 成功后 durable save；
- outbox 文件名与 audit dedup key 均由 `{cr, from, to, commit}` 确定，关闭“发送成功、marker 保存前崩溃”的重复窗口；
- journal 不保存第二份状态机、gate 或 candidate registry。

### 2.6 Backlog 条目块

纯函数接口：

```js
replaceBacklogEntry(trunkText, sourceText, crId) -> mergedText
```

契约：

1. 对 trunk/source 建立 LF 解析视图，但使用原始行偏移切片，保证 trunk 非目标前缀/后缀字节不变；
2. 目标条目由同缩进 `- id: {CR-ID}` 起始，结束于下一个同级条目、同级注释边界或 EOF；边界外空行/注释属于 trunk，不被替换；
3. trunk 和 source 各自必须且只能命中一次目标 ID；0 次/多次均硬失败；
4. replacement 使用 source 目标条目的全部字段和嵌套块，包括 `owners`、`latest-checkpoint` 和未知字段；
5. 函数不 parse、不读取、不生成 `status`，也不修改其他条目；
6. 输出相同则允许 merge 继续，不制造额外提交层。

错误码固定为：

- `MERGE_BACKLOG_ENTRY_MISSING`：trunk 或 source 缺目标条目；
- `MERGE_BACKLOG_ENTRY_DUPLICATE`：trunk 或 source 目标条目重复；
- `MERGE_BACKLOG_STRUCTURE_INVALID`：缩进/边界无法唯一确定。

## 3. 接口契约

### 3.1 公共 CLI

```text
crctl writeback-apply <cr_id>
  --stage <baseline|tasks|traceability>
  --spec-id <id>
  --target-version <version>
  [--milestone-name <name>]
  [--brief <text>]
  [--milestone-file <workspace-relative-path>]
  --workspace <installation-workspace>
```

规则：

- baseline 接受可选 `milestone-name` / `brief`；
- tasks 不接受 milestone 参数；
- traceability 必须提供 `milestone-file`，其真实路径必须位于 operational workspace 内且父链无 symlink；
- 不接受任意状态、trigger、generator、candidate、manifest 或 output path；
- `--target-version` 缺失在入口 `BAD_ARGS` fail-fast；不从 README、文件名或 branch 猜测；
- `--candidate` / `--candidate-out` 作为未知或明确废弃参数返回 `BAD_ARGS`，不保留双入口。

成功输出保持既有主字段并增加状态/投影可观测字段：

```json
{
  "op": "writeback-apply",
  "cr": "CR-2026-038",
  "stage": "baseline",
  "txId": "<32-hex>",
  "phase": "complete",
  "changed": true,
  "commit": "<origin-confirmed-40-hex>",
  "status": "writing-back",
  "files": ["specs/...", "change-requests/CR-2026-038/cr.md"],
  "warnings": [],
  "recoverCommand": "crctl writeback-apply CR-2026-038 --stage baseline --spec-id ... --target-version ... --workspace ..."
}
```

幂等完成重放返回同一 commit、`changed=false`；可补发 warning 对应的投影，但不得新增 commit/push。

### 3.2 内部 `applyWriteback` 接口

```js
applyWriteback(ctx, {
  cr,
  stage,
  specId,
  targetVersion,
  milestoneName,
  brief,
  milestoneFile,
  workspace,
  validateBaselineAdvance,
  emitStatusEvent,
  emitAdvanceAudit
})
```

三个 callback 只由 `cmdWritebackApply()` 注入：

- `validateBaselineAdvance({ workspace: txws, plannedExisting })`：复用状态机与 gate，返回 §2.4 候选；
- `emitStatusEvent({ cr, from, to, trigger, commit, dedupName }) -> string|null`；
- `emitAdvanceAudit({ cr, from, to, trigger, commit, dedupKey }) -> boolean`。

非 baseline 不调用三个 callback。callback 缺失在任何 transaction/Git 副作用前 fail-fast，避免“生产调用者忘记注入却静默成功”。

### 3.3 `runGateChecks` planned-existing

```js
runGateChecks(ws, cr, targetStatus, gates, {
  specId,
  plannedExisting: Set<string>
})
```

仅 `check.type === "fileExists"` 分支执行：

```text
ok = fs.existsSync(path) || plannedExisting.has(normalizedRelativePath)
```

以下分支禁止读取 planned-existing：`globNonEmpty`、`passCondition`、`approval`、`deliveryIndexComplete`、`attemptsWithinLimit` 以及未知 gate。`plannedExisting` 非 `Set`、含 absolute/`..`/反斜杠或未落在当前 workspace 时直接 `GATE_PLANNED_PATH_INVALID`，不做字符串宽松匹配。

### 3.4 版本化 generator 内部调用

`runFixedGenerator()` 使用 `process.execPath` + `spawnSync(..., {shell:false})`，固定脚本路径由当前 Tools Root 派生。argv 只由 stage 配置和已校验业务输入组成：

| stage | 固定脚本 | 业务 argv |
|---|---|---|
| baseline | `writeback-prd-sdd.mjs` | workspace/cr/spec/version，可选 milestone-name/brief，内部 candidate-out |
| tasks | `writeback-tasks.mjs` | workspace/cr/spec/version，内部 candidate-out |
| traceability | `writeback-traceability.mjs` | workspace/cr/spec/version/milestone-file，内部 candidate-out |

不通过 shell 字符串、不读取脚本 stdout 返回的 manifest 路径作为信任输入；成功后只读取固定 `{candidateDir}/manifest.json`。generator 非零退出原样映射其结构化 error code；stdout 非法不影响固定路径判定。

### 3.5 Projection adapter

status outbox 固定：

```json
{
  "event_kind": "status",
  "cr_id": "CR-2026-038",
  "from_status": "merging",
  "to_status": "writing-back",
  "trigger": "writeback-prd-sdd",
  "commit_sha": "<origin-confirmed-sha>"
}
```

- `commit_sha` 禁止 `pending:`、空值或 txws 本地未确认 SHA；
- `dedup_name = status-{cr}-{commit}.json`；
- outbox 失败返回 `EMIT_FAILED` warning，不反转 Git 成功。

advance audit 固定记录 `kind=advance`、from/to/trigger/by/commit/result=success 和 `dedup_key=advance:{cr}:{commit}`。`auditLogOnce()` 在 append 前按 dedup key 检查现有 JSONL；命中即视为成功并补记 journal marker。audit 文件不可读/不可追加返回 warning，不抛出导致 Git 成功被报告为失败。

### 3.6 错误与恢复

| code/结果 | 触发 | 副作用与恢复 |
|---|---|---|
| `BAD_ARGS` | 缺业务参数、传废弃 candidate/generator 参数 | 零 candidate/journal/authority 写入 |
| generator 结构化错误 | 源文档/业务输入不合法 | 可有可丢弃 candidate；零 lock/journal/authority |
| `WRITEBACK_MANIFEST_*` | JSON/schema/stage/CR/spec/path/hash/digest/矩阵失败 | 零 lock/journal/authority；修正源后同命令重跑 |
| `WRITEBACK_GENERATOR_MISMATCH` | manifest 脚本 hash 与固定脚本不符 | 同上 |
| `GATE_BLOCKED` | baseline advance gate 未通过 | 同上；planned-existing 不扩展其他 gate |
| `TX_INPUT_CONFLICT` | 既有 CR/stage journal 的 composite inputDigest 与当前 businessInputDigest + manifestDigest 不一致 | 不覆盖旧事务；以原业务输入和固定 candidate 续跑，禁止手改 journal |
| `WRITEBACK_REMOTE_STALE` | preflight 后或 commit 前 origin 前进 | 未发布 txws 回到新 origin；删除未发布 journal；同业务命令重生成 candidate |
| `WRITEBACK_REMOTE_HISTORY_REWRITTEN` | 已发布 commit 从 origin 历史消失 | 硬阻断，禁止 force/rebuild |
| `FAULT_INJECTED` | write-set/commit/push/projection 测试点 | 同命令按 journal 续跑 |
| `EMIT_FAILED` warning | origin confirmed 后 outbox/audit 失败 | exit 0；重放只补缺失投影 |
| baseline no-op + status=`merging` + 无匹配 journal | 检测到旧协议或不完整外部写入，无法证明同批发布 | `WRITEBACK_ATOMIC_FACT_MISSING` 硬失败；不制造状态单独提交 |
| complete replay | journal + origin 证明已完成 | exit 0、changed=false、零新 commit/push，仅补投影 |

## 4. 关键算法与流程

### 4.1 新 Writeback 事务 preflight

```text
resolve repositories + operational workspace
validate business args and current stage
canonicalize businessInput with fixed keys/nulls/POSIX milestone path
businessInputDigest = sha256(JSON.stringify(businessInput))
read-only detect existing writeback journal
  existing -> enter §4.5 recovery branch and compare businessInputDigest
  none     -> continue new transaction

candidateDir = txws/.crctl/candidates/{cr}/{stage}
assert containment + no symlink parent + Git ignored
clear only this stage candidate directory
spawn fixed generator with shell=false
if generator noop:
  validate legal no-op state and return changed=false
read manifest exactly once, normalize CRLF -> LF, JSON.parse
validate manifest schema/stage/cr/spec-id/normalized target-version/generator id/hash
manifestDigest = sha256(the single normalized manifest read)
validate candidate containment/path safety/allowlist/sorted/unique
read each blob once, validate ref/hash, retain blobText
validate inputDigest
validate every target beforeSha256 against txws disk
verify release-subjects snapshot
fetch origin and compare txws HEAD
  stale -> reset detached txws to new origin, return WRITEBACK_REMOTE_STALE
if baseline:
  plannedExisting = exact validated manifest paths
  validate fixed merging -> writing-back transition
  run writing-back gate with plannedExisting

journalInputDigest = sha256(JSON.stringify({businessInputDigest,manifestDigest}))
only now acquire writeback lock and create journal
fault: writeback-after-journal-create
if baseline:
  transitionAt = journal.createdAt
  build deterministic status after image through shared writer
  persist transition metadata before applyWriteSet
```

候选目录、fetch 和 stale reset 不是 authority 发布；非法 manifest 不创建 journal、lock 残留、target file、commit、push、outbox 或 success audit。

### 4.2 Baseline 复合 write-set

journal 创建后，使用共享状态 writer 和 `transitionAt=journal.createdAt` 生成 `cr.md` after image并随事务持久化；若崩溃发生在 after image 首次保存前，恢复用同一 journal.createdAt 确定性重建；一旦持久化则只复用该 after image，不重新生成时间字段：

```text
entries = manifest files with cached blobText
entries += cr.md {beforeSha256, afterSha256, content=status writing-back}
applyWriteSet(txws, txRoot, txId, entries)
fault: writeback-after-apply

git add -- <exact entries paths>
assert staged names == exact entries paths
git commit with existing writeback trailers
persist commit/base/files/statusTransition
fault: writeback-after-commit
```

commit message 继续使用：

```text
writeback baseline {CR-ID}

AI-First-Op: writeback
AI-First-Tx: {txId}
AI-First-CR: {CR-ID}
AI-First-Writeback-Stage: baseline
```

不增加状态专用第二 commit，不调用 `performAdvance()` 的写入/commit/outbox 分支。

### 4.3 Lease push 与 origin-confirmed

沿用既有三分类：

- `confirmed`：remote 包含 journal commit；
- `pushable`：remote 仍为 expected base，执行精确 lease push；
- `rebuild`：未发布且 origin 前进，txws reset 后返回 `WRITEBACK_REMOTE_STALE`；
- `history-rewritten`：journal 认为已发布但 commit 不在 remote 历史，硬阻断。

每次 push 后 fetch 并确认 origin 包含 commit，确认前不得设置 `outboxEmitted`/`auditEmitted`，也不得调用 projection callback。

### 4.4 Origin-confirmed 后投影

```text
if stage == baseline and origin confirmed:
  if !outboxEmitted:
    emit deterministic status outbox(real commit)
    success -> save outboxEmitted=true
    failure -> warnings += EMIT_FAILED
  fault: writeback-after-status-outbox

  if !auditEmitted:
    auditLogOnce(dedup_key=advance:{cr}:{commit})
    success -> save auditEmitted=true
    failure -> warnings += EMIT_FAILED
  fault: writeback-after-advance-audit

save phase=complete
return success + warnings
```

两项投影彼此独立：outbox 失败不阻止 audit 尝试，audit 失败也不删除 outbox。重放按各自 marker 补缺项。确定性 outbox 名和 audit dedup key 处理 callback 成功后、journal marker 保存前崩溃窗口。

### 4.5 恢复与幂等

1. 命令先 canonicalize 当前公共业务输入并只读固定 key 的现有 journal；存在时不清空 candidate、不运行 generator，先比较 businessInputDigest，漂移立即 `TX_INPUT_CONFLICT`。
2. 读取原固定 candidate 一次并重算 manifestDigest；与 journal 共同重算 envelope inputDigest，任何第三值硬失败。
3. 获取同一 writeback lock，`recoverWriteSet({txId})` 只恢复该事务。
4. `committed=false`：使用原固定 candidate 和 journal digest重新验证；若仅有 journal envelope 而 statusTransition 尚未保存，以 `journal.createdAt` 确定性生成 after image；write-set 已部分应用时由 before/after 三值恢复，不生成新时间戳。
5. `committed=true,pushed=false`：不重新应用/commit，按 journal commit 续推。
6. `pushed=true/phase=complete`：fetch 确认 commit 仍在 origin；不重新生成 candidate，不新增 commit/push。
7. baseline 依次补 `outboxEmitted` / `auditEmitted`；全部完成返回 `changed=false`。
8. candidate 在需要恢复 apply 且固定目录缺失时返回 `WRITEBACK_CANDIDATE_RECOVERY_MISSING`，禁止从已部分写入的 txws 反向猜 manifest；正常 archive 清理只发生事务完成后，不触发此路径。

### 4.6 `_backlog.yml` 语义合并纯函数

伪代码：

```text
replaceBacklogEntry(trunkRaw, sourceRaw, cr):
  trunkView = locateUniqueEntry(trunkRaw.replace(CRLF, LF), cr)
  sourceView = locateUniqueEntry(sourceRaw.replace(CRLF, LF), cr)
  assert each count == 1 and boundaries valid

  trunkOriginalRange = map normalized line range -> trunkRaw byte offsets
  sourceBlock = source normalized target block
  targetEol = detect EOL at trunk target range
  replacement = sourceBlock joined with targetEol

  return trunkRaw.prefix + replacement + trunkRaw.suffix
```

断言：

```text
result prefix before target === trunk prefix
result suffix after target === trunk suffix
extract(result, cr) === source target entry (EOL-normalized)
all non-target entry IDs/order === trunk
```

函数位于现有 `workspace-transactions.mjs`，直接提炼并复用当前 `matchEntryBlockTx()` 的条目定位语义；若需跨 `crctl.mjs` 共用，只把 locator 最小下沉到既有 `yaml-subset.mjs`，不再写第三份正则，也不新建 YAML patch 模块。现有 archive 条目读取继续复用同一 locator，但本 CR 不借机重写无关 archive editor。

### 4.7 Knowledge-base semantic merge tree

普通 repo 继续直接执行：

```text
git merge-tree --write-tree <baseSha> <sourceSha>
```

knowledge-base repo 在 initial prepare 和 remote rebuild 都调用同一个 `prepareMergeTree()`：

```text
trunkBacklog  = gitReadBlobRaw(<baseSha>, "change-requests/_backlog.yml")
sourceBacklog = gitReadBlobRaw(<sourceSha>, "change-requests/_backlog.yml")
mergedBacklog = replaceBacklogEntry(trunkBacklog, sourceBacklog, cr)

trunkBlob = git hash-object -w --stdin <<< trunkBacklog
mergedBlob = git hash-object -w --stdin <<< mergedBacklog
create temporary GIT_INDEX_FILE under installation .crctl/tmp
## 第一步：中和 source 的 backlog 变更，让 Git 只合并其他文件
GIT_INDEX_FILE=... git read-tree <sourceSha>
GIT_INDEX_FILE=... git update-index --cacheinfo <source-mode>,<trunkBlob>,change-requests/_backlog.yml
neutralTree = GIT_INDEX_FILE=... git write-tree
syntheticCommit = git commit-tree <neutralTree> -p <sourceSha>
mergeTree = git merge-tree --write-tree <baseSha> <syntheticCommit>
## 第二步：在已成功合并的 tree 上写入语义合并 backlog blob
GIT_INDEX_FILE=... git read-tree <mergeTree>
GIT_INDEX_FILE=... git update-index --cacheinfo <source-mode>,<mergedBlob>,change-requests/_backlog.yml
finalTree = GIT_INDEX_FILE=... git write-tree
finalMergeCommit = git commit-tree <finalTree> -p <baseSha> -p <sourceSha>
remove temporary index in finally
```

`gitRun/gitMust` 仅增加内部 `opts.env` 透传以设置固定 `GIT_INDEX_FILE`；不开放给 CLI/Skill。backlog 内容不得通过现有会对 stdout 执行 `trim()` 的 `gitMust()` 读取；增加一个仅封装固定 `git cat-file blob` argv 的 `gitReadBlobRaw()`，保留首尾空行、CRLF 与末尾换行，并以 Buffer/未裁剪 UTF-8 stdout 返回。source 文件 mode 由 `git ls-tree` 读取并要求为普通 blob，`update-index --cacheinfo` 沿用该 mode。临时 index 位于 `.crctl/tmp`，不入 Git。`hash-object`、synthetic `commit-tree` 只产生不可达对象，不移动 ref、不 checkout、不发布；最终 merge commit 的第二 parent 仍是原始 source SHA，release-subjects 和 ancestry 契约不变。

**实施期 revision（v0.3.0）**：原 v0.2.0 直接把 `mergedBacklog` 放进 parent=source 的 synthetic commit，Git 实测仍会把 backlog 判为双方修改并产生冲突。修订为上述“两段式中和再回填”：synthetic tree 先使用 trunk backlog，使 `merge-tree` 只处理其他文件；成功后再对 merge tree 写入 semantic merged blob。该修订只改变不可达 synthetic tree 的内部计算顺序，最终 tree、最终双亲、lease publish、错误边界和 FR/AC 结论均不受影响。

source backlog path 缺失、不是普通 blob、目标条目缺失/重复或 `merge-tree` 仍冲突时，在任何 repo publish 前硬失败。不得回退到整份 trunk、整份 source、行号拼接或 `-X ours/theirs`。

### 4.8 Caller 收缩

#### Pipeline baseline 节点

```text
输入: cr_id, spec_id, target_version, optional milestone_name/brief
调用: writeback-prd-sdd Skill
成功: phase=complete，向 tasks 节点传递结构化结果
失败: abort；WRITEBACK_REMOTE_STALE 可重跑同一节点
```

删除 generator 命令、candidate_dir、manifestPath、独立 `advance --embedded` 和内部校验列表。

#### 三个 Skill

每个 Skill 只保留：

1. 业务前置和必填参数；
2. 一次 `crctl writeback-apply` 调用；
3. `complete/noop/stale/history-rewritten/业务源错误` 分类；
4. “下一步以 `crctl next {cr_id}` 为准”。

traceability Skill 仍负责 milestone 业务内容草稿，因为这是业务判断；但不选择 generator 或 candidate 路径。

## 5. 技术选型与替代方案

| 决策 | 采用 | 否决及原因 |
|---|---|---|
| 原子边界 | 深化现有 `applyWriteback()` | baseline 后再 advance：远端可见事实分裂 |
| 状态校验复用 | 提炼 `performAdvance` 的无写入 preflight + callback | 在 transaction lib 复制状态机/gates：第二事实源；lib 反向 import CLI：循环依赖 |
| planned-existing | `Set<validated manifest path>`，只给 fileExists | 虚拟文件系统/候选内容 override：扩大 gate 信任面 |
| generator 选择 | 固定三项对象常量 | plugin/registry/factory：只有三个固定实现且无扩展需求 |
| candidate 生命周期 | txws `.crctl/candidates/{cr}/{stage}` + txws 现有清理 | manager/数据库/后台 GC/公共 query：重复 authority |
| 投影幂等 | journal marker + 确定性 outbox 名/audit key | exactly-once 协议或新 ledger：现有 at-least-once 投影已足够 |
| backlog 编辑 | 条目块纯函数，trunk 原文切片 | YAML serializer/第三方 parser：重排注释字段并增加依赖；模糊字符串：无法硬失败 |
| merge tree | 原生 Git 临时 index + hash-object/read-tree/update-index/write-tree/commit-tree | checkout/rebase/cherry-pick：增加工作树副作用；`-X ours/theirs`：丢目标或其他 CR 数据 |
| synthetic commit | 仅作 merge-tree 输入，最终 parent 仍原 source | 发布 synthetic parent：改变 release-subject ancestry 与审计语义 |
| stale 恢复 | reset detached txws 后同业务命令重生成 | rebase/cherry-pick candidate：candidate 不是 authority |
| no-op legacy | 无原子事实则硬失败 | 单独补状态 commit：继续制造本 CR 要消除的分裂事实 |

## 6. FR 到技术实现映射

| FR | 技术方案 | 主要验收 |
|---|---|---|
| FR-01 | §2.4 baseline 状态候选、§2.5 journal marker、§4.2 同一 write-set/commit、§4.3 origin confirmed、§4.4 投影补发 | AC-01～AC-04 |
| FR-02 | §2.3 manifest 一次读入、§3.4 固定 generator、§4.1 lock/journal 前完整 preflight、§4.5 recovery | AC-05～AC-07 |
| FR-03 | §2.6 条目模型、§4.6 纯函数、§4.7 原生 Git semantic tree、initial/rebuild 共用 helper | AC-08～AC-10 |
| FR-04 | §2.1 公共输入收缩、§2.2 固定 candidate、§3.1 无路径 CLI、§4.8 Caller 收缩 | AC-07、AC-11 |

覆盖率：4/4 FR；12/12 AC 均有设计落点。

### 6.1 AC 验收追溯

| AC | 设计锚点 | 自动验证 |
|---|---|---|
| AC-01 | §4.2 baseline 复合 write-set、§4.3 origin-confirmed | origin 同一 commit 的 tree 同时含 specs 目标与 `cr.md status=writing-back`；随后 tasks 不回退状态 |
| AC-02 | §2.3 `plannedExisting`、§3.3 gate 限权 | 精确 manifest 路径仅放行 `fileExists`；额外路径和其他 gate 类型拒绝且零写入 |
| AC-03 | §2.5 marker、§4.4 projection、§4.5 recovery | apply/commit/push/outbox/audit fault matrix，最终一 commit/一 status event/一 advance audit |
| AC-04 | §4.8 Caller 收缩、§8 Prompt 采纳 | Pipeline/Skill/生产测试零独立 writing-back advance；公共接口无任意状态参数 |
| AC-05 | §4.1 完整 preflight、§9.1 失败矩阵 | 每种 manifest/gate 错误断言零 journal/lock/target/commit/push/outbox/audit |
| AC-06 | §4.1 新事务与 §4.5 recovery 分流 | 非法输入失败后修正源并同命令成功，不出现前次输入导致的 `TX_INPUT_CONFLICT` |
| AC-07 | §2.1、§3.1、§3.4、§4.8 | active 公共 CLI/Skill/Pipeline 静态扫描无 candidate/manifest/generator 路径 |
| AC-08 | §2.6 纯函数、§9.3 参数矩阵 | 首/中/末条和 trunk 前后新增 CR；非目标字节、顺序、注释、空行不变 |
| AC-09 | §2.6 错误码、§4.7 publish 前 prepare | trunk/source 目标缺失/重复硬失败，所有 repo remote refs 不前进 |
| AC-10 | §2.6 source 完整块替换 | owners/latest-checkpoint/未知 v2 字段保留；helper 不读写 backlog status |
| AC-11 | §2.2 candidate 约定、§9.2 ignore/cleanup | 三 stage 只在固定目录生成、`git check-ignore` 通过、commit tree 无 candidate、txws 清理无残留 |
| AC-12 | §9.5 全量回归 | crctl/writeback 全套在 Ubuntu、Windows 全绿，旧 gate/assertion 不放宽 |

## 7. 安全、性能与兼容性

### 7.1 安全

- 所有 repo/trunk/txws/Tools Root 继续来自 workspace `dir-graph.yaml` resolver；
- public CLI 不接受 generator、candidate、manifest、任意 ref/status/trigger；
- generator 使用 argv + `shell:false`，不执行 shell 拼接；
- candidate、milestone-file、manifest target 都做 containment 和 symlink parent 校验；
- manifest allowlist、blob hash、before hash、input digest 和真实 generator hash全部保留；
- planned-existing 不提供内容，只提供已验证精确路径，且不影响非 `fileExists` gate；
- semantic merge 对缺失/重复/边界异常硬失败；不解析或传播 backlog status；
- push 继续使用精确 `--force-with-lease`，禁止 force push/自动 revert。

### 7.2 性能

- preflight 对 manifest 和每个 blob各读取一次，复杂度 O(candidate 总字节数)；
- backlog 替换对 trunk/source 各线性扫描一次，复杂度 O(backlog 字节数)；
- knowledge-base prepare 比现有流程增加固定数量本地 Git plumbing 命令，不增加网络往返；
- repo publish 保持串行，避免并发 lease 和恢复状态膨胀；
- 不增加 cache、worker pool、数据库或长期索引。

### 7.3 Windows / CRLF

- JSON/YAML/Markdown 解析前统一 `replaceAll('\r\n','\n')`；逐行解析使用 `split(/\r?\n/)`；
- manifest digest 使用一次规范化后的文本，blob/before hash继续锚定 generator 与磁盘约定的真实 UTF-8 内容；
- backlog matcher 使用 LF 解析视图和原始偏移，非目标 trunk 字节不因 CRLF 解析被重写；
- `spawnSync` 使用 `shell:false`、`process.execPath` 和 argv，路径含空格时无需 shell quote；
- 临时 index 路径由 `path.join()` 构造，通过 `env.GIT_INDEX_FILE` 传给 Git。

### 7.4 兼容与迁移

- `writeback-apply` 命令名和三 stage 不变，调用方一次性切换参数，不保留生产双入口；
- generator 的 deterministic transformation 和内部 `--candidate-out` ABI 不变，现有 generator 单测可继续直接调用；
- 旧 writeback journal 缺 projection marker 按 false；只有能证明既有 commit 和固定 candidate 的事务才恢复；
- 不迁移历史 baseline、旧 candidate 或旧分裂 commit；baseline noop 但仍在 merging 且无 journal 时硬失败并报告原子事实缺失；
- tasks/traceability 的状态和 commit 语义不变，仅由 crctl 内部代调 generator；
- 状态机、gates、archive、checkpoint 和 traceability schema 均不变。

### 7.5 可观测性

成功输出公开 stage、txId、phase、commit、status、files、warnings 和 recoverCommand，不公开 candidate 路径、generator 路径、journal 路径或本机临时 index。错误保留 code、phase、已确认 side effects 和 recovery command。status outbox 与 `kind: advance` success audit 都绑定 origin-confirmed commit；既有 `kind: writeback` 诊断审计也必须记录返回的 commit，但不替代前述状态审计。candidate 失败不产生 success audit。

## 8. Prompt 采纳影响

本 CR 不新增/删除 `crctl.mjs` dispatch `writeback-apply` 分支，也不修改 `controlled-shell/rules.json#protectedPaths.deny`；但会修改既有命令面参数和职责，因此按强约束主动列出所有直接生产调用方，评审时逐项核对：

| 调用方 | 现状 | 应改为 |
|---|---|---|
| `skills/writeback/writeback-prd-sdd/SKILL.md` | Skill 调 generator、选择 candidate_dir、传 manifestPath，再独立 advance | 一次 `crctl writeback-apply {cr} --stage baseline --spec-id {id} --target-version {ver} ...`；消费 phase/commit/status/warnings |
| `skills/writeback/writeback-tasks/SKILL.md` | Skill 调 tasks generator并传 candidate | 一次 `writeback-apply --stage tasks`，只传业务输入 |
| `skills/writeback/writeback-traceability/SKILL.md` | Skill 调 trace generator并传 candidate | Skill 只起草 milestone_file，然后一次 `writeback-apply --stage traceability` |
| `pipeline-templates/feature-writeback.pipeline.json` baseline 节点 | 复制 generator/apply/advance 三段算法 | 只传业务输入、调用 Skill、按结构化结果中止或进入下一节点 |
| 同 Pipeline tasks/traceability 节点 | 复制 generator/candidate/apply 算法 | 各调用一次对应 Skill，不消费内部路径 |
| `skills/shared/crctl/SKILL.md` | help 契约仍公开 `--candidate` | 更新为业务参数和原子 baseline 语义 |
| `skills/_index.yml` crctl/writeback brief | 描述 candidate manifest 由调用方提供 | 描述 crctl 内部固定 generator 与复合 writeback |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | baseline 后测试独立 `advance --embedded` | 直接断言 baseline 返回 writing-back 且同一 commit，无第二 advance |
| `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | 测试从外部构造 candidate 并传路径 | 黑盒生产测试只传业务输入；恶意 manifest 通过测试 seam/内部 validator 单测覆盖，不恢复公共 candidate 参数 |

README 和 Agent 的全面职责文本收敛属于 CR-2026-042，本 CR 不借机改写；但本 CR 修改的 Skill/Pipeline 不得继续保留与新命令冲突的算法副本。

## 9. 测试与故障注入

### 9.1 Writeback preflight 零副作用矩阵

逐项制造：非法 JSON、manifest v、stage、CR、spec-id、absolute/`..`/反斜杠/重复路径、symlink parent、allowlist、排序、重复路径、before/after hash、blob ref/missing/hash、generator id/hash、input digest、目标矩阵和 baseline gate 失败。

每例断言：

```text
writeback journal count unchanged
writeback lock 不存在
txws target files/hash/index unchanged
txws staged set empty
origin commit count unchanged
status outbox count unchanged
advance success audit count unchanged
```

随后修正同一业务源并重跑，必须成功且不得出现由失败输入产生的 `TX_INPUT_CONFLICT`。

### 9.2 Baseline 原子与恢复矩阵

1. happy path：origin 单个 commit 同时含 specs 三目标和 `cr.md status=writing-back`；
2. planned-existing：两个 specs 路径通过 `fileExists`，额外/未验证路径拒绝；非 fileExists gate 不受 Set 影响；
3. `writeback-after-journal-create` 中断后重跑，`transitionAt` 恒等于原 journal.createdAt，`cr.md` after text/hash 完全一致；
4. 同一既有 journal 分别改变 target_version、milestone_name、brief、milestone_file path，均 `TX_INPUT_CONFLICT` 且旧事务不变；恢复使用同一业务输入成功；
5. `writeback-after-apply`、`writeback-after-commit`、`writeback-after-push` 各中断一次后重跑；
6. origin confirmed 后 outbox 写失败、audit 写失败，命令 exit 0 + warning；修复后重放只补缺项；
7. `writeback-after-status-outbox` / `writeback-after-advance-audit` 崩溃窗重放，确定性去重；
8. complete replay：changed=false，commit/status/event/audit 各自唯一；
9. baseline 后立即执行 tasks，状态保持 writing-back，不 reset 到 merging；
10. origin preflight 前进、commit 后前进、push response lost、history rewrite；
11. candidate 目录 `git check-ignore` 为真，commit tree 不含 `.crctl/candidates`；
12. archive/workspace 清理后 txws candidate 随资源删除，无独立 cleanup 任务。

### 9.3 Backlog 纯函数参数化矩阵

- 目标 CR 位于首条、中间、末条；
- trunk 在目标前、后、前后同时新增 CR；
- trunk 其他条目含注释、空行、未知字段、嵌套列表；
- source 目标含三 owners、latest-checkpoint、未知 v2 字段；
- LF、CRLF 和含空格/引号标量；
- trunk/source 目标缺失和重复；
- 结果逐字比较：prefix/suffix、非目标条目、顺序、注释、空行完全等于 trunk；目标块等于 source 的 LF 语义；
- 静态断言 semantic merge helper 不访问 `.status`、`status:` 或 parseYaml 后的条目字段。

### 9.4 Merge 集成矩阵

1. 三 bare remote，knowledge-base backlog 冲突但目标条目可唯一替换，merge 成功；
2. 最终 tree 保留 trunk 新 CR，并采用 source 目标条目；
3. 最终 merge commit parents 精确为最新 base + 原 source，synthetic commit 不在 parent/ref；
4. initial prepare 和 remote stale rebuild 产生相同语义；
5. trunk/source 目标缺失/重复时 `MERGE_BACKLOG_ENTRY_*`，所有 repo remote ref 均不前进；
6. 其他文件真实冲突仍 `MERGE_PREPARE_CONFLICT`，不被 semantic backlog 逻辑吞掉；
7. multica/tools repo 继续使用普通 merge-tree，无 backlog 特例。

### 9.5 静态契约与全量回归

- active Agent/Pipeline/Skill/crctl help 不出现公共 `--candidate`、`--candidate-out`、manifestPath、generator path；
- feature-writeback baseline 后不存在 `advance --to writing-back`；
- Pipeline 节点不含 journal/CAS/merge/stage/commit/push 算法；
- generator unit tests仍覆盖确定性转换和 manifest canonical 公式；
- `node --test skills/shared/crctl/scripts/test/*.test.mjs`；
- `node --test skills/writeback/scripts/test/*.test.mjs`；
- `node skills/shared/crctl/scripts/check-skill-matrix.mjs`；
- `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`；
- 所有 Pipeline JSON `JSON.parse`；
- Ubuntu 与 Windows CI 全绿，不删除测试、不放宽 gate/assertion。

## 10. 实施顺序与回滚

### 10.1 最小提交顺序

1. **T01 红测**：冻结新 CLI、preflight 零 journal、planned-existing、同 commit 状态、backlog 纯函数与 merge 集成失败用例。
2. **T02 纯函数**：advance 无写入 preflight、`fileExists` planned-existing、backlog locator/replacer、固定 generator map/candidate resolver。
3. **T03 Writeback 深化**：内部 generator/preflight、baseline write-set、projection callback/marker/fault points、恢复测试。
4. **T04 Merge 接入**：临时 index semantic tree，initial/rebuild 共用 helper，缺失/重复硬失败集成测试。
5. **T05 调用方切换**：同一提交修改三个 Skill、feature-writeback Pipeline、crctl Skill/help/index 和旧测试调用；删除独立 advance 与公共 candidate 参数。

T02～T04 期间新路径尚无生产调用方，便于独立验证；T05 必须同提交切换接口，不留双入口。

### 10.2 回滚

- T02/T03/T04 在 T05 前可独立 revert，旧调用方仍使用旧接口；
- T05 必须整体 revert，不能只恢复 Skill 或只恢复 CLI；
- 已由新 baseline 事务发布的 commit 包含状态和 specs，代码回滚不拆分该事实，也不生成补偿 revert；
- in-flight journal 按其记录的代码版本完成或人工阻断，禁止删除 journal/手改账本；
- semantic merge 已发布的 commit 是普通双亲 merge commit，可由 Git 历史审计；不回写旧全文件冲突模型。

## 11. 风险、残余与不做事项

| 风险 | 控制 |
|---|---|
| preflight 与 lock 间 txws/origin 变化 | before hash、HEAD/base 复核、lease push；第三值 stale/recovery，不接受旧 candidate |
| candidate 同 stage 并发生成 | manifest/blob 一次读入与 hash 校验；authority lock在 apply 前串行化；竞争最多导致 preflight hard fail |
| callback 成功、marker 保存前崩溃 | outbox deterministic name + audit dedup key + journal marker |
| synthetic tree 改变 ancestry | 最终 commit parents 显式使用 base 和原 source；测试锁 parent |
| matcher 把条目间注释算入目标 | 同级注释/空行边界规则 + prefix/suffix 字节测试 |
| Windows autocrlf 造成误报 | Git blob读取用于 merge、LF 解析视图、原始偏移替换、双平台测试 |
| 旧协议已回写 baseline 但未推进状态 | 不伪造原子事实；`WRITEBACK_ATOMIC_FACT_MISSING` 硬失败，作为显式迁移事件另行处理 |
| public 参数收缩遗漏调用方 | 全仓静态扫描 + T05 同提交切换；历史文档不作为 active 契约 |

明确不做：

- 不实施来源规格 FR-04～FR-09、FR-11～FR-16 或 Phase E；
- 不新增任意复合状态 API、generator/candidate manager、plugin/schema/error registry、YAML patch 框架或 workflow engine；
- 不修改状态机、gates、人工审批、测试执行、review canonical、CR 时间字段、traceability evidence 或 archive 严格门；
- 不修改 Agent/README/CI 全面职责文本；这些属于 CR-2026-042；
- 不增加后台清理、数据库、消息队列、分布式锁、2PC、npm 依赖；
- 不允许 force push、force rollback、自动补偿 revert、rebase/cherry-pick candidate、手工编辑 `_backlog.yml`/`cr.md`/journal；
- 不批量迁移历史 baseline、candidate、journal 或旧分裂 commit。

## 12. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-14 | v0.1.0 | Ray | 初始设计：固定 generator/candidate 内部化、lock/journal 前完整 preflight、baseline 状态同 write-set/commit/push、origin-confirmed status outbox与 advance audit、目标 CR backlog 条目语义合并及 Git synthetic tree；FR 覆盖 4/4，AC 覆盖 12/12 |
| 2026-08-14 | v0.2.0 | Ray | 技术评审 attempt 1 回修 TD-BL-1/2：以 journal.createdAt 冻结 transitionAt 并由共享 writer 确定性重建状态 after image；新增 canonical businessInputDigest，与 manifestDigest 共同绑定 journal inputDigest；补 journal-create 崩溃窗和参数漂移 TX_INPUT_CONFLICT 测试 |
| 2026-08-14 | v0.3.0 | Ray | 实施期事实修订：Git 实测直接 merged-backlog synthetic commit 仍冲突，改为 trunk backlog 中和 source → merge 其他文件 → 回填 semantic merged blob；最终 tree/parents/发布与 FR/AC 结论不变 |

## tools CR 生命周期最小优化 2/5 — 生命周期证据规范化（v0.20.1 · CR-2026-039）

## 1. 架构概览

### 1.1 设计目标

本设计落实 PRD FR-01～FR-05，将四类生命周期证据漏洞收敛到既有深原语的既有缝（seam）中，不新增命令、账本、schema 或状态：

1. **FR-01**：code Pipeline 在 review-code 与人工审批之间结构性插入一个现有 `push-progress` 节点（一次 `crctl checkpoint` 调用），以节点顺序本身作为"PASS 后必 checkpoint"的强制机制。
2. **FR-02**：`crctl review-record --stage dev-plan` 复用现有 `subject-sha256` 字段写入 plan+TASK composite digest；消费缝只有两处——`cmdNext` 的 task-breakdown 分支与 `runGateChecks` 的 `passCondition(dev-start)` 分支——共用同一个重算 helper。
3. **FR-03**：时间字段收敛为三个 writer 的纯函数级修改（`crMdStatusText`、register 渲染、`editCrOwnerProjection`）；现有 reader 只做通用 frontmatter 解析、不消费时间字段，因此不新增无调用方的兼容 helper，兼容读取规则固定为 `updated ?? updated-at`。
4. **FR-04**：canonical 字段收敛是纯文本契约修订（三个 CR Pipeline JSON + 相关 Skill），零 crctl 代码变更——`review-record` 现有 schema 校验即为准绳。
5. **FR-05**：职责边界不产生运行时代码，体现为上述每个修改点的落点选择（见 §6 映射表"落点模块"列）与 §9 静态测试。

核心不变量：

1. digest 的权威定义只有一个（§4.1 `devPlanCompositeDigest`），写入点与所有消费点都调用它，禁止任何调用方自行拼接。
2. PASS 结论（annotation verdict）与被评审内容（digest）分离存储、消费时绑定；内容漂移使结论失效，而不是覆盖结论。
3. Pipeline 的强制性来自节点顺序与 `onFail: abort`，不来自 prompt 中的告诫文字。
4. legacy 数据（无 digest、旧 `updated-at`）永远走保守路径（重审 / 兼容读），不做批量迁移。

### 1.2 分层与依赖

```text
code-implementation.pipeline.json（节点顺序：review-code → [新]checkpoint → human_approval → approve-code）
  ↓ 一次调用
push-progress Skill（现状已收敛为一次 crctl checkpoint，不改）
  ↓
crctl.mjs + lib/workspace-transactions.mjs（本 CR 只在四个既有 seam 内扩展，无新 dispatch 分支）
  ├─ cmdReviewRecord: dev-plan 分支追加 subject-sha256（复用 sha256 + LF 规范化）
  ├─ cmdNext: task-breakdown PASS 分支追加 digest 重算
  ├─ runGateChecks: passCondition(dev-start) 分支追加 digest 重算
  └─ crMdStatusText / editCrOwnerProjection: updated 字段统一
  ↓
Node 标准库（fs/path/crypto）+ 现有 readEvidenceDoc / readFileChecked / casWrite
```

依赖方向不变：`workspace-transactions.mjs` 中的 `crMdStatusText` 被 `crctl.mjs` 单向引用（merge finalize 亦复用该纯函数，禁止复刻——本次修改该函数即同时覆盖 approve/advance 与 merge 两条状态写入路径）。

### 1.3 与 CR-2026-038 的共享文件集成

CR-2026-038 已合入 tools `custom/main`（merge `162fdf0`）；其实际 diff 修改 `crctl.mjs`、`workspace-transactions.mjs`、durable/writeback 测试与 `feature-writeback.pipeline.json`，**未修改** `code-implementation.pipeline.json`。本 CR 与其共享 crctl 核心文件，但功能边界独立（本 CR 不触碰 writeback preflight/write-set/merge prepare/candidate 路径，CR-2026-038 不触碰 review-record/next/dev-plan freshness/时间字段）。当前 CR-2026-039 tools worktree 仍基于旧 HEAD `c790b7e`，实施约定：

- T1 开工前先通过现有 CR worktree 集成方式把最新 `origin/custom/main`（当前 `162fdf0`）合入该分支：当前 tools 分支无自身提交时只允许 fast-forward；若届时已有已发布提交则使用普通 merge commit。禁止 rebase 已发布分支、force push、逐提交 cherry-pick 或手工重放 CR-2026-038 实现。
- 后续每个 TASK 开工前确认 `origin/custom/main` 未前进；若前进则先按同一非改写历史方式集成，再改共享文件。该集成是实施前置，不进入 Pipeline/Skill prompt，也不在调用层复制 Git 算法。
- `code-implementation.pipeline.json` 没有 CR-2026-038 冲突面；新增 checkpoint 节点只按现有节点 id 定位，禁止依赖数组行号。

## 2. 数据模型

### 2.1 dev-plan annotation（review-annotations/dev-plan.yml）

仅在现有结构上追加一个字段，无新文件、无新账本：

```yaml
cr-id: CR-2026-XXX
reviewer: "..."
reviewed-at: "..."
verdict: pass            # 或 block（block 轨同样写 digest：评审时刻的内容快照同样需要绑定）
blockers: []
dimensions: { ... }
suggestions: []
repair-target: write-dev-plan   # 仅 block 轨，现状保留
subject-sha256: <64-hex>        # 新增：plan+TASK composite digest（LF canonical）
```

- **不写** `subject-file`：composite digest 对应文件集合不是单文件，写 plan.md 会误导消费者把该字段当完整 subject（PRD FR-02）。requirement/tech-design 两阶段的 `subject-file` 现状不动。
- legacy annotation 无 `subject-sha256` 不构成读取错误；消费点按 §4.3 保守路径处理。

### 2.2 composite digest 的 canonical 编码

digest 输入序列（确定性，跨平台一致）：

```text
entries = [
  { path: "change-requests/{cr}/plan.md", content: LF(plan.md) },
  { path: "change-requests/{cr}/tasks/TASK-*.md", content: LF(...) },  # 全部 TASK，按 path 字符串升序
]
canonical = JSON.stringify(entries)   # 键序固定 path→content（对象字面量插入序），无空白
digest = sha256(utf8(canonical))
```

- `path` 为 workspace-relative POSIX 路径；`content` 为 `\r\n → \n` 规范化后的全文。
- TASK 匹配严格按 PRD 的全部 `TASK-*.md`：`/^TASK-.*\.md$/`，只扫 `change-requests/{cr}/tasks/` 一层。现有 `gates.json#statusGates.task-breakdown` 的数字前缀 glob 只负责最低存在性门禁，不是 digest 文件集合的事实源，不得据此收窄 subject。
- `tasks/_index.yml` 不进入（实现期 TASK 状态正常变动）；这是与 task-breakdown 门禁存在性检查的刻意差异，注释写明依据（PRD FR-02 / 规格 FR-05）。
- JSON 编码天然把 path 与 content 都纳入且带长度边界，不同文件集合不可能拼接出相同串（防 `a`+`bc` vs `ab`+`c` 类碰撞）。

### 2.3 cr.md frontmatter 时间字段

目标形态：单一 `updated` 字段。

| writer | 现状 | 目标 |
|---|---|---|
| register（workspace-transactions.mjs 渲染） | 已写 `updated` | 不变 |
| 状态推进（`crMdStatusText`，advance/approve/reject 与 merge finalize 共用） | 仅当 `updated-at:` 行存在时替换 | 统一维护 `updated`：有 `updated-at:` → 替换为 `updated:`；有 `updated:` → 刷新；两者皆无 → 追加。任何情况下不得双字段共存 |
| Owner 正式移交（`editCrOwnerProjection`） | 不触碰时间字段 | 修改 cr.md 时同样按上述规则刷新 `updated` |

其他写入（PRD/SDD/TASK/评审/测试/checkpoint）不经过这三个函数，结构上不可能触碰 `updated`——不靠纪律靠缝。

## 3. 接口契约

### 3.1 CLI（全部为现有命令，无新增/无签名变更）

| 命令 | 行为变化 | 输出变化 |
|---|---|---|
| `crctl review-record {cr} --stage dev-plan --bump-attempt` | 落盘前计算 §2.2 digest 写入 annotation；plan.md 缺失或 TASK 集为空 → 硬失败 `SUBJECT_NOT_FOUND`（与 requirement/tech-design 同错误码，禁止静默降级为空 digest） | 返回 JSON 不变 |
| `crctl next {cr}` | status=task-breakdown 且 annotation PASS 时先重算 digest（§4.3） | 字段不变；`next`/`why` 文本按分流变化 |
| `crctl approve --stage dev-start` | 目标态 `developing` 门禁的 `passCondition(dev-start)` 检查追加 digest 重算；漂移 → 该 check `ok:false`，approve 硬失败 | gateBlockers 文案说明 dev-plan subject digest 不一致；不新增错误码 |
| `crctl advance` / `crctl approve`（状态写入） | cr.md 候选文本经修订后的 `crMdStatusText` 生成 | 不变 |
| `crctl owner-set` | cr.md 投影同时刷新 `updated`（`owner-handover` 为 inbox 事件名，非命令名） | 不变 |

### 3.2 Pipeline 节点契约（code-implementation.pipeline.json 新增节点）

```json
{
  "id": "00000000-0000-0000-0015-000000000015",
  "kind": "skill",
  "label": "代码评审 PASS 后审批前 checkpoint",
  "ref": "push-progress",
  "prompt": "执行 push-progress：cr_id={{inputs.cr_id}}，message=代码评审通过后审批前 checkpoint。\n\n在节点输出中记录 batchId、repositories、phase；phase 非 complete 时中止，不得进入人工审批。",
  "onFail": "abort",
  "timeoutMinutes": 15
}
```

- 插入位置：`review-code`（…0009）之后、human_approval `代码审查通过`（…0010）之前。
- 回修循环无需改 `reviewLoop.replayNodes`：重放序列 implement-code → write-test-report → push-progress → review-code 再次 PASS 后，控制权自然落到 review-code 的下一节点，即本新节点——"再次 PASS 后重新 checkpoint" 由顺序结构性保证。
- human_approval（…0010）的 approvalPrompt 追加一句："且评审后 checkpoint phase=complete"。
- 同时删除该 pipeline `inputs` 中的 `suggestion_policy` 输入定义（FR-04）。

### 3.3 release-subjects 与 PASS 后 checkpoint 的兼容边界

`review-record --stage code` 在写 annotation 前调用现有 `buildReleaseSubjects`：每个 active repo 的 requirement 远端必须等于当前 worktree HEAD，然后把这些 reviewed SHA 与 PRD/SDD/plan/TASK artifact digest 写入 `code.yml`。PASS 后 checkpoint **不得重算或覆盖**该快照；approve-code 继续用原快照执行现有 `verifyReleaseSubjects`：

- knowledge-base 仓允许 reviewed SHA 是当前 HEAD 的祖先，但两者之间只能出现既有白名单路径（`review-annotations/`、`cr.md`、`traceability.yml`、`review-loop.yml`、`approval.yml`、`_backlog.yml`）；因此 review-record/status/checkpoint metadata 导致的 KB 后继提交合法。
- 非 knowledge-base 仓仍要求当前 HEAD 与 reviewed SHA 精确相等；若 review PASS 后出现未评审代码并被 checkpoint 提交，approve-code 必须以 release subject drift 拒绝。
- PRD/SDD/plan/TASK 内容仍按 snapshot artifact 集逐文件和集合 digest 重核；KB HEAD 虽允许前移，也不能借白名单提交改变被审批业务产物。

该边界解释了 FR-01 为何能复用现有 checkpoint 而不放宽 approve-code：正常路径只发布评审账本与状态；任何未评审代码或业务产物变化仍被既有 release-subjects 拦截。

### 3.4 review_feedback 合同（FR-04 收敛后）

```text
review_feedback = { blockers: string[], suggestions: string[], dimensions: {}, repair-target?: string }
```

- 可执行的回修说明直接写在 blocker 字符串内（一句话 blocker + 怎么改），不再有 `repair-instructions` 并列字段。
- 修复结果由下一轮 review 的 blockers 差异自然体现，不再有 `fixed-blockers` 输出义务；各 write/implement Skill 的"逐条消费 blockers"语义不变。

## 4. 关键算法与流程

### 4.1 devPlanCompositeDigest(ws, cr)（新增唯一 helper，crctl.mjs 内部函数）

```text
function devPlanCompositeDigest(ws, cr) -> { ok, digest?, why? }:
  planRel = `change-requests/${cr}/plan.md`
  planRaw = readFileChecked(join(ws, planRel))
  if planRaw == null: return { ok:false, repairTarget:'write-dev-plan', why:'plan.md 缺失' }
  tasksDir = join(ws, `change-requests/${cr}/tasks`)
  if tasksDir 不存在: return { ok:false, repairTarget:'write-dev-tasks', why:'tasks/ 缺失' }
  names = readdirSync(tasksDir).filter(f => /^TASK-.*\.md$/.test(f)).sort()   # 字符串升序
  if names.length == 0: return { ok:false, repairTarget:'write-dev-tasks', why:'TASK-*.md 集合为空' }
  entries = [{ path: planRel, content: lf(planRaw) }]
  for f of names:
    taskRaw = readFileChecked(join(tasksDir, f))
    if taskRaw == null: return { ok:false, repairTarget:'write-dev-tasks', why:`TASK 文件缺失: ${f}` }
    entries.push({ path:`change-requests/${cr}/tasks/${f}`, content:lf(taskRaw) })
  return { ok:true, digest:sha256(utf8(JSON.stringify(entries))) }
```

- `lf = t => t.replaceAll('\r\n', '\n')`（行尾纪律）。读取沿用 `readFileChecked`；任一缺失都返回带明确 why 的失败结果，不跳过、不降级为空集合。
- review-record 调用方见 §4.2：失败结果统一 `fail('SUBJECT_NOT_FOUND', why)`，保证零账本写；freshness 只读调用方见 §4.3：失败结果明确判 stale 并路由重审。仅对预期缺失做结构化转换，权限/I/O 等异常继续抛出，不宽泛 catch。
- 排序以完整相对路径字符串比较，跨平台一致（不依赖 readdir 顺序）。

### 4.2 review-record 写入点

在现有 `if (stage === 'requirement')` / `if (stage === 'tech-design')` 分支序列后追加：

```text
if (stage === 'dev-plan'):
  subject = devPlanCompositeDigest(ws, cr)
  if !subject.ok: fail('SUBJECT_NOT_FOUND', subject.why)
  lines.push(`subject-sha256: ${subject.digest}`)
```

block 轨与 pass 轨同写（评审时刻内容快照对两轨都有意义：block 回修后重审，digest 自然刷新）。

### 4.3 消费点分流（两处共用 freshness 判定）

```text
function devPlanFreshness(ws, cr, annData) -> { fresh, repairTarget?, why? }:
  rec = annData['subject-sha256']
  if rec == null: return { fresh:false, repairTarget:'review-dev-plan', why:'legacy 无 digest，需重审刷新证据' }
  cur = devPlanCompositeDigest(ws, cr)
  if !cur.ok: return { fresh:false, repairTarget:cur.repairTarget, why:`dev-plan subject 不完整：${cur.why}` }
  return cur.digest === rec
    ? { fresh:true }
    : { fresh:false, repairTarget:'review-dev-plan', why:'plan/TASK 已修订，subject digest 不一致' }
```

- **cmdNext（task-breakdown，PASS 分支）**：现行为 `verdict=pass && blockers=[] → suggest approve-dev-start`；改为先 `devPlanFreshness`——不 fresh 则 `suggest(freshness.repairTarget, why)`：plan 缺失→write-dev-plan，TASK 缺失/为空→write-dev-tasks，legacy 或 digest 漂移→review-dev-plan。block 分支与 annotation 畸形判定不变。
- **runGateChecks（passCondition 分支）**：`evaluatePassCondition` 返回 pass 且 `check.stage === 'dev-start'` 时追加 freshness 判定；不 fresh → 该 check `ok:false, why`，使 `approve-dev-start`（目标态 `developing` 门禁）与一切以 developing 为目标的 advance 硬失败。复用现有 gate 失败通道，不新增错误码。
- requirement/tech-design/code 三阶段的 passCondition 评估路径不进入该分支，零影响。

### 4.4 crMdStatusText 修订（workspace-transactions.mjs 纯函数）

```text
现状：仅在 /^updated-at:/m 存在时替换该行
目标：
  fm = fm.replace(/^updated-at:\s*.*$/m, '')        # 旧字段先清除（若存在）
  ts = `updated: "${opts.at || nowIso()}"`
  fm = /^updated:\s*.*$/m.test(fm) ? fm.replace(/^updated:\s*.*$/m, ts) : fm + `\n${ts}`
```

- 替换后需清理可能产生的空行（保持 frontmatter 规整）。
- `editCrOwnerProjection`（crctl.mjs）在生成新 cr.md 文本后，复用同一规则刷新 `updated`（提取为共享小函数 `refreshCrMdUpdated(fm)` 置于 workspace-transactions.mjs 并导出，避免两处复刻）。
- 兼容读：任何需要"最后受控修改时间"的读者按 `updated ?? updated-at` 读取；当前 crctl 无此类消费点，该规则写入代码注释作为 reader 契约。

### 4.5 FR-04 文本契约修订清单（零代码）

修订原则：删除对不存在 canonical 字段的引用；可执行回修说明并入 blocker 文本；不改变 reviewLoop 结构与 passCondition。

| 文件 | 修订内容 |
|---|---|
| `pipeline-templates/requirement-authoring.pipeline.json` | write-requirement-prd / review-requirement 两节点 prompt：删 `repair-instructions`、`fixed-blockers` 引用；回修语义改为"逐条消费 review_feedback.blockers（blocker 内含可执行修复说明）" |
| `pipeline-templates/architecture-design.pipeline.json` | write-tech-design / review-tech-design 两节点 prompt 同上 |
| `pipeline-templates/code-implementation.pipeline.json` | 删 `inputs.suggestion_policy` 定义；implement-code prompt 删 `fixed-blockers` 输出义务与 `repair-instructions` 引用；write-test-report prompt 删 `repair-instructions` 输出；review-code prompt 删 suggestion_policy 全段（strict/lenient、升格判据、dimensions 记录）与 `repair-instructions` 输出 |
| `skills/requirement/{write-requirement-prd,review-requirement}/SKILL.md` | 删 repair-instructions / fixed-blockers 引用，回修步骤改为按 blockers 定点修复 |
| `skills/develop/{write-tech-design,review-tech-design,write-dev-plan,write-dev-tasks,review-dev-plan,implement-code,review-code,write-test-report,coding-discipline}/SKILL.md` | 同上；review-code 删升格判据一节；coding-discipline 的 root-cause 要求保留（不与 fixed-blockers 并列表述） |
| `agents/quality-reviewer-agent.md` 等 Agent 文档、README 中的残留引用 | **不在本 CR 范围**（归实施 CR 5，见 §10 风险） |

`product-planning.pipeline.json` 与 `skills/planning/*` 不动（无 CR 上下文，独立合同，PRD FR-04 明确排除）。

## 5. 技术选型与替代方案

| 决策 | 选择 | 否决的替代 | 理由 |
|---|---|---|---|
| PASS 后 checkpoint 的强制机制 | Pipeline 节点顺序 + onFail:abort | 在 approve-code 门禁里校验 latest-checkpoint 时间戳 | 顺序即机制，零新门禁、零时间比较逻辑；时间戳比较引入时钟与阈值问题 |
| digest 绑定字段 | 复用 annotation `subject-sha256` | 新 freshness ledger / `input-subjects` 数组 | 与 requirement/tech-design 同构，next/gate 消费路径已被验证；新账本违反 PRD NFR-01 |
| composite 编码 | canonical JSON entries（path+content） | 逐文件 sha256 再拼接 / tar 风格串接 | JSON 自带边界，防拼接歧义；Node JSON.stringify 确定性够用，不引依赖 |
| 消费点挂钩 | cmdNext + runGateChecks(passCondition) 各一行调用同一 helper | 新增独立 gate type（如 subjectFreshness） | 两处即全部消费缝；新 gate type 需 gates.json 声明 + checker 实现，浅模块 |
| 时间字段迁移 | writer 侧渐进收敛 | 一次性批量迁移历史 CR | 规格明令不批量迁移；writer 收敛后双字段共存数自然归零 |
| suggestion_policy 移除 | 直接删除输入与 prompt 段 | 保留参数但固定 strict | 保留无用参数是死配置；删除后 review-code 语义更简（verdict 只判 CR 本身） |

## 6. FR 到技术实现映射

| PRD FR | 落点模块（职责边界） | 技术条目 |
|---|---|---|
| FR-01 PASS 后审批前 checkpoint | Pipeline（节点顺序/失败中止）；push-progress Skill 不改 | §3.2 新节点 …0015；human_approval prompt 一句；回修由顺序保证 |
| FR-02 dev-plan digest | crctl（受控证据写入与门禁） | §4.1 helper、§4.2 写入、§4.3 双消费点 |
| FR-03 updated 统一 | crctl（`workspace-transactions.mjs` 内部共享纯函数，仍属受控账本写入边界） | §4.4 三个 writer（register 渲染、`crMdStatusText`、`editCrOwnerProjection`）+ reader 契约；不落到版本化文档转换脚本 |
| FR-04 canonical 收敛 | Pipeline/Skill 文本契约（业务语义层） | §4.5 清单；review-record schema 校验现状即准绳 |
| FR-05 职责边界与 ponytail | 全部（落点选择即实现） | §1.2 分层、§5 选型、§9.2 静态测试 |

## 7. 安全与性能考量

- **安全**：不新增任何执行入口；approve-dev-start 的 digest 门禁只收紧不放宽；legacy 无 digest 一律保守重审，不存在"绕过 digest 的旧通道"。canonical JSON 仅用于哈希输入，不反序列化外部数据。
- **性能**：digest 重算 = plan+TASK 全文读取与一次 sha256（数十 KB 量级，毫秒级）；消费点每次 next/approve 各一次，无缓存需求（YAGNI）。
- **行尾与失败纪律**：所有 digest 与 frontmatter 处理先 LF 规范化（§4.1/§4.4）；预期 subject 缺失返回明确 repairTarget（review-record 转为硬失败，next 转为可执行恢复路由，gate 转为阻断），权限/I/O/解析异常继续硬失败，禁止静默降级（T04 教训）。
- **跨平台**：路径比较用 POSIX 相对路径字符串；Windows autocrlf 检出由 LF 规范化吸收；测试在 Ubuntu/Windows 双跑。

## 8. Prompt 采纳影响

本 CR 不新增 crctl 子命令、不改 `controlled-shell/rules.json` deny 面，但既有命令行为变化，以下 Skill/文档必须同步采纳（随实施 TASK 一并修订，review-tech-design 与人工审批逐条核对）：

| Skill / 文档 | 现状 | 应改为 |
|---|---|---|
| `skills/shared/crctl/SKILL.md`（review-record 行） | 只描述 requirement 阶段写 subject-sha256 | 补注 dev-plan 阶段写 plan+TASK composite digest，next/approve-dev-start 消费前重算 |
| `skills/develop/review-dev-plan/SKILL.md` | PASS 描述不含证据绑定 | 注明 PASS 绑定 plan+TASK digest，正文修订后旧 PASS 自动失效 |
| `skills/sync/push-progress/SKILL.md` | 不变 | 不变（code Pipeline 新节点只是多一个调用方） |
| §4.5 清单全部文件 | 引用不存在的 canonical 字段 | 按清单修订 |

## 9. 测试设计

### 9.1 基线

远端快照 crctl 测试全绿为前置；本 CR 新增用例全部进 `skills/shared/crctl/scripts/test/crctl.test.mjs`（pipeline 结构测试可独立小文件，复用现有 fixture 机制），Ubuntu/Windows 双跑。

### 9.2 用例矩阵

| 需求 | 用例 |
|---|---|
| FR-02 写入 | review-record dev-plan（pass 轨与 block 轨）annotation 含 `subject-sha256`；独立复算相等；修改 plan / 修改任一 TASK / 增删 TASK 文件 → digest 变化；仅改 `_index.yml` → digest 不变；LF 与 CRLF 检出 → 相同 digest；TASK 集为空 → `SUBJECT_NOT_FOUND` 硬失败且零账本写入 |
| FR-02 next | PASS+fresh → suggest approve-dev-start；PASS+drift/legacy → suggest review-dev-plan；plan 缺失→write-dev-plan；TASK 缺失/为空→write-dev-tasks |
| FR-02 gate | approve-dev-start：fresh → 放行；drift/subject 缺失 → gateBlockers 明确说明 digest 不一致或 subject 不完整且零写入；删除全部 TASK 时 `next` 结构化路由重建 TASK/重审，不抛裸错误 |
| FR-03 | `crMdStatusText`：含 `updated-at` 的旧 frontmatter → 输出仅单一 `updated`；含 `updated` → 刷新；皆无 → 追加；CRLF 输入一致。`owner-set` 后 `updated` 刷新。register/advance/approve 产物不含双字段 |
| FR-01 | code Pipeline JSON 结构断言：节点 id 全局唯一；节点序 review-code < 新 push-progress(…0015) < human_approval(approve-code)；新节点 onFail=abort、ref=push-progress；reviewLoop.replayNodes 未被破坏。release-subjects 回归：仅 KB 白名单后继提交仍可审批；非 KB HEAD 前移、KB 非白名单路径变化或 artifact digest 漂移均拒绝 |
| FR-04 | 三个 CR Pipeline JSON 全文扫描零命中 `repair-instructions`/`fixed-blockers`/`suggestion_policy`；`product-planning.pipeline.json` 不在扫描范围；相关 Skill 同口径扫描；既有 review-record schema 校验用例（SCHEMA_INVALID 等）保持全绿 |
| 回归 | 既有全量测试不回归；requirement/tech-design/code 三阶段 passCondition 行为不变 |

## 10. 实施顺序、回滚与风险

### 10.1 TASK 切分（每 TASK 一个可回滚提交）

1. **T1**：`devPlanCompositeDigest` + review-record dev-plan 写入 + 单测（红→绿）。
2. **T2**：cmdNext 与 runGateChecks 双消费点接入 + 单测。
3. **T3**：`refreshCrMdUpdated` 提取、`crMdStatusText` 与 `editCrOwnerProjection` 接入 + 单测。
4. **T4**：code Pipeline 新 checkpoint 节点 + suggestion_policy 删除 + 结构测试。
5. **T5**：§4.5 全部文本契约修订 + 扫描测试。
6. **T6**：`crctl SKILL.md` / review-dev-plan SKILL 采纳修订（§8），全量双平台回归。

### 10.2 回滚

每个 TASK 独立 commit，按序 revert 即可；digest 字段对旧 reader 不可见即无影响（annotation 多一个键），pipeline 新节点 revert 后恢复现状漏洞但不破坏流程。

### 10.3 风险

| 风险 | 缓解 |
|---|---|
| 当前 tools CR worktree 落后于已合入 CR-2026-038 的 custom/main | T1 前按 §1.3 fast-forward/普通 merge 集成且不改写已发布历史；共享 crctl 文件按功能 seam 集成，code Pipeline 无 CR-2026-038 冲突面 |
| legacy 在途 CR（dev-plan 已 PASS 无 digest）合入后 next 建议重审 | 保守路径是有意设计：一次额外 review-dev-plan 即补齐 digest，无数据迁移；在合并说明中提示 |
| Agent 文档 / README 残留旧字段引用（本 CR 范围外） | 显式归 CR 5；§9.2 扫描测试只覆盖本 CR 范围，不回潮由 CR 5 的 lint 规则承接 |
| suggestion_policy 删除影响既有触发习惯 | 该参数本无实现支撑（strict 为缺省且无升格代码路径），删除不改变任何实际评审行为 |

## 11. 不做事项

- 不新增 CLI 子命令、gate type、错误码、账本或 schema（freshness 判定复用 gate 失败通道与 `SUBJECT_NOT_FOUND`）。
- 不为 requirement/tech-design/code 三阶段改动 digest 逻辑；不动 `product-planning` 合同；不改 merge/writeback/archive/checkpoint 任何算法。
- 不实现缓存、批量迁移、Agent/README 整体收敛（CR 5）、测试执行结构化（CR 3）、traceability 证据（CR 4）。

## tools CR 生命周期最小优化 3/5 — 结构化测试闭环（v0.20.2 · CR-2026-040）

## 1. 架构概览

### 1.1 当前实现与问题定位

目标代码仓是 Tools，目标基线为当前 Tools Root 的 `custom/main`。该仓的 `ARCHITECTURE.md` 已存在，本 CR 不修改它。当前测试入口位于 `skills/shared/crctl/scripts/crctl.mjs#cmdTest`，实际行为为：

1. 从 `flags.cmdList` 读取一个或多个 shell 命令字符串；
2. 以 `spawnSync(command, { shell: true })` 执行；
3. 逐条写入 `test-evidence/cmd-NN.log` 和 `.crctl/audit.log`；
4. 重新生成 `test-report.md`，覆盖已有机器区和人工分析内容；
5. 以进程 exit code 表达测试是否全部通过。

现有 `skills/shared/crctl/scripts/lib/durable-tx.mjs` 已提供 journal envelope、目录锁、durable write-set、第三值检测和恢复；`workspace-transactions.mjs` 已承载 `register`、`merge`、`checkpoint`、`writeback`、`archive` 等业务事务。当前没有测试业务事务，也没有结构化测试计划或测试结果到 `traceability.yml#tests` 的统一原子发布。

### 1.2 目标架构

```text
Agent
  -> 选择 code-implementation Pipeline / write-test-report / review-code
Pipeline
  -> implement-code
  -> write-test-report
       -> 生成临时 cr-test-plan/v1
       -> 调用一次 crctl test
       -> 只写 test-report marker 后分析区
  -> push-progress
  -> review-code
       -> 只读取最终测试证据，不重新执行测试
  -> post-review push-progress
  -> human approval

crctl CLI
  -> 解析 test 子命令参数
  -> resolve workspace / CR / Tools Root
  -> 调用 workspace-transactions.testCr()
  -> 输出结构化业务结果或技术错误

workspace-transactions.testCr
  -> 只读预检 plan / repo / cwd / owner / state / marker
  -> 运行阶段：spawnSync(executable, args, { shell: false })
  -> 暂存原始日志到非 authority 临时目录
  -> 记录阶段：构造 report machine zone / tests projection / review-loop
  -> 复用 durable-tx 的 test journal + recoverable write-set 一次发布

durable-tx
  -> 提供既有 journal / lock / write-set / recovery 原语
  -> 新增 test payload 槽位和 test 锁 scope
  -> 不理解测试业务、TASK 覆盖或评审结论
```

执行和记录是同一个公共 `crctl test` 接口内部的两个顺序阶段。运行阶段不创建 durable journal、不持有账本写锁；记录阶段才创建既有事务，并将所有机器事实一次性提交。

### 1.3 模块职责与深模块边界

| 模块 | 接口/职责 | 明确不拥有 |
|---|---|---|
| Agent | 根据 `crctl next` 和职责选择 Pipeline/Skill，传递 CR 上下文 | 状态机、Git 算法、测试命令表、受控文件写入 |
| Pipeline | 节点顺序、输入传递、测试/代码 reviewLoop、失败中止 | `spawnSync`、事务、YAML、日志和账本算法 |
| `write-test-report` | 依据 TASK 与实现输出选择正式命令，生成临时 plan，调用 `crctl test`，维护 marker 后业务分析 | machine zone、traceability tests、review-loop、CAS、事务和命令执行 |
| `review-code` | 读取真实 diff、最终报告、digest、日志和 TASK/SDD，作 LLM 评审判断 | 重新执行 lint/test/build、修改测试证据 |
| `crctl.mjs` | 参数解析、状态/owner 前置校验接线、调用深接口、结构化输出 | 测试业务判断、事务内部算法、人工评审结论 |
| `workspace-transactions.mjs` | `testCr` 的 plan 校验、执行、结果建模和原子发布编排 | LLM 判断、Pipeline 路由、独立 CLI、第二事务框架 |
| `durable-tx.mjs` | 既有 test journal、锁、write-set 和恢复 | 测试发现、命令语义、报告内容判断 |
| 版本化脚本 | 本 CR 不新增脚本；后续仅承载确定性文档转换 | 状态推进、测试运行、人工审批 |
| README | 本 CR 不复制执行算法，只保留入口和权威链接 | CLI 参数细节、事务状态机、错误矩阵 |

`workspace-transactions.testCr` 是本 CR 的深模块：调用方只掌握 CR、workspace、临时 plan 和结构化结果；计划解析、worktree containment、argv 执行、日志、机器报告、traceability、review-loop 和可恢复发布均隐藏在其实现中。删除该模块会使上述复杂度重新散落到 Skill、Pipeline 和测试调用者，因此该 seam 有实际 leverage。

### 1.4 改动范围

实现期预期修改：

- `skills/shared/crctl/scripts/crctl.mjs`：保留 `test` 子命令，改为解析 `--plan` 并调用 `testCr`；删除 `--cmd`/shell 字符串执行路径。
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：新增测试计划解析、执行结果建模、marker 解析和 `testCr` 业务事务编排；复用现有 repository resolver、`readCrMdStatus`、hash 和 transaction 原语。
- `skills/shared/crctl/scripts/lib/durable-tx.mjs`：在既有 journal/lock/write-set 模型中增加 `test` op/payload，复用同一恢复实现，不新增事务框架。
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：增加结构化 plan、argv 安全、结果分类、report/digest 和重复执行测试。
- `skills/shared/crctl/scripts/test/fault-harness.test.mjs`：增加 test 记录阶段故障恢复与零半状态测试。
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`：更新测试节点和 reviewLoop 的静态契约断言。
- `skills/shared/crctl/SKILL.md`：登记新的 `crctl test --plan` 输入、输出和失败语义。
- `skills/develop/write-test-report/SKILL.md`：删除 `--cmd`/直接 traceability 写入说明，改为临时 plan + `crctl test` + marker 后分析。
- `skills/develop/review-code/SKILL.md`：删除无条件重新执行测试的第二入口，改为读取 canonical 证据并在缺失/漂移时 blocker。
- `pipeline-templates/code-implementation.pipeline.json`：收缩测试和代码评审节点 prompt，保留既有 replayNodes 与 checkpoint 顺序。

不修改 `dir-graph.yaml` 状态机、`gates.json` 状态门禁、Agent/matrix、README、版本化 writeback 脚本、Multica 或其他生命周期切片。

## 2. 数据模型

### 2.1 结构化测试计划

临时 plan 文件由 `write-test-report` 写入 `.crctl/tmp/test-plan.json`，只作为一次调用输入，不进入 CR authority。`crctl` 读入后立即规范化 CRLF 为 LF，并按固定 schema 校验：

```ts
type CrTestPlan = {
  schema: "cr-test-plan/v1";
  commands: CrTestCommand[]; // non-empty
};

type CrTestCommand = {
  repo: string;           // dir-graph active repository id
  cwd: string;            // repo CR worktree-relative, default "."
  executable: string;     // non-empty executable name/path fragment
  args: string[];         // argv; empty allowed
  timeoutSeconds: number; // positive integer
};
```

计划不得包含 shell 字符串、`command` 字段、环境变量覆盖、pipe、redirect、`continueOnError`、absolute cwd、status、owner、attempt、日志路径或 traceability payload。允许的 `repo` 必须来自当前 workspace `dir-graph.yaml#repositories` active 项，cwd 解析后必须位于该 repo 的 `requirement/{CR-ID}` worktree 内。

### 2.2 Command canonicalization

计划 digest 只绑定规范化的命令集合，不绑定临时文件路径、执行时间、模型、owner、stdout/stderr 或本地绝对路径：

```js
const commandSubject = {
  schema: "cr-test-plan/v1",
  commands: plan.commands.map(({ repo, cwd, executable, args, timeoutSeconds }) => ({
    repo,
    cwd: cwd || ".",
    executable,
    args,
    timeoutSeconds,
  })),
};
const commandDigest = sha256(JSON.stringify(commandSubject));
```

`JSON.stringify` 使用固定对象键序和数组顺序；不对 commands 排序，因为计划顺序就是执行顺序。所有字符串已在 LF 规范化 plan 上解析。报告机器区保存完整规范化 command 对象和 `command-digest`，不另存 canonical `plan.json`。

### 2.3 Command result

每条命令的结果只由 `crctl` 生成：

```ts
type CrTestResult = {
  repo: string;
  cwd: string;             // workspace-relative POSIX path
  executable: string;
  args: string[];
  timeoutSeconds: number;
  exitCode: number | null;
  signal: string | null;
  timedOut: boolean;
  started: boolean;
  log: string;             // CR-relative POSIX path
};
```

`started=false` 只用于技术失败诊断，不进入业务 block 报告；已启动命令的 non-zero/timeout 进入 `status: block`。计划校验、executable 启动、repo/cwd 解析和事务错误不生成新的 canonical attempt。

### 2.4 `test-report.md` machine zone

机器区由 `crctl` 生成，形式固定为：

```yaml
---
cr: CR-2026-040
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-15T..."
command-digest: <64-hex>
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, test/example.test.mjs]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-040/test-evidence/cmd-01.log
---

## 测试报告 · CR-2026-040

<!-- crctl:analysis-below -->
```

上述字段和 marker 之前的全部内容是 crctl authority，实际输出必须使用现有安全 YAML scalar 渲染器生成合法 YAML。marker 之后原样视为 analysis zone。

每次新的完整 attempt 使用固定的 `cmd-NN.log` 目标路径，使报告只引用当前 canonical 结果；旧日志若不在当前 command 集合中不被 traceability 消费。报告不复制完整 stdout/stderr。

### 2.5 Traceability tests projection

`change-requests/{CR-ID}/traceability.yml#tests` 只保存最小机器摘要，完整 command 结果和分析保留在 test report：

```yaml
tests:
  report: change-requests/CR-2026-040/test-report.md
  status: pass
  tester: Ray
  owner-assigned-at: "2026-08-14T19:45:43+08:00"
  generated-at: "2026-08-15T..."
  command-digest: <64-hex>
  review-loop: write-test-report
```

写入时保留 traceability 的其他顶层段；`tests` 缺失时新增，`tests` 不是映射、报告路径不一致或已有机器字段形状无法证明时硬失败。测试命令数组不复制到 traceability，避免第二份事实源。

### 2.6 Review-loop 与 test journal

review-loop 继续使用既有 `change-requests/{CR-ID}/review-loop.yml` schema，`write-test-report` 作为 loop key。一次完整运行完成后才递增当前 cycle 的 attempt；非零测试结果也会记录一次 `block` attempt。

在既有 `durable-tx` journal envelope 中增加 `test` payload 槽位，不新增 journal 格式：

```json
{
  "v": 1,
  "op": "test",
  "cr": "CR-2026-040",
  "phase": "prepared|written|complete",
  "graphDigest": "...",
  "inputDigest": "<plan + result facts>",
  "test": {
    "targetRoot": "<CR worktree>",
    "commandDigest": "...",
    "attempt": 1,
    "entries": ["test-report.md", "test-evidence/cmd-01.log", "traceability.yml", "review-loop.yml"]
  }
}
```

真实内容通过既有 write-set blobs 保存，journal 不保存 stdout/stderr 全文。运行阶段不创建 journal；只在完整计划完成并准备发布时创建。若记录阶段中断，下一次同命令先恢复该 test transaction；若中断发生在运行阶段且没有 journal，临时结果丢弃并重新执行完整计划。

## 3. 接口契约

### 3.1 CLI 外部接口

```text
crctl test <CR-ID> --plan <workspace-relative-or-absolute-temp-json> --workspace <knowledge-base-worktree>
```

`--plan` 只允许指向当前 workspace 内的非 authority 临时目录（推荐 `.crctl/tmp/test-plan.json`）；`--cmd`、`--cwd`、`--timeout` 不再接受。CR-ID、workspace 和 Tools Root 仍由既有 CLI 解析器和 `dir-graph.yaml` resolver 提供。

成功时 stdout 返回 JSON，进程 exit code 为 0，包括业务测试失败：

```ts
type TestResponse = {
  op: "test";
  cr: string;
  status: "pass" | "block";
  commandDigest: string;
  attempt: number;
  commands: CrTestResult[];
  report: string;
  traceability: string;
  reviewLoop: string;
  changed: boolean;
  recoverCommand: string;
};
```

`status:block` 是已完成执行的业务结果，Pipeline 据此路由；schema/path/executable/transaction/CAS 错误通过现有 `fail(code, message, extra)` 输出 stderr JSON、非零退出。技术错误不产生新的 canonical attempt。

### 3.2 内部深模块接口

`workspace-transactions.mjs` 新增一个业务处理器：

```ts
export async function testCr(ctx, {
  cr,
  workspace,
  planPath,
}) -> Promise<TestResponse>
```

该接口内部完成 state/owner 校验、计划加载、repository resolver、执行、机器区构造、traceability/review-loop 投影和 test journal/write-set。CLI 不传入执行器、状态、owner、attempt、logs、digest 或 output paths。

内部纯函数使用最小 seam：

```ts
parseTestPlan(raw, ctx, cr) -> NormalizedPlan
canonicalCommandSubject(plan) -> { subject, digest }
runTestPlan(plan, ctx, cr) -> { results, tempLogs }
parseAnalysisMarker(existingReport) -> { machinePrefix, analysisSuffix }
renderTestMachineReport(input) -> string
renderTestsTraceability(existing, input) -> string
```

这些函数不成为新的公共命令或插件接口；测试通过同一 CLI seam 和少量纯函数直接覆盖。

### 3.3 `write-test-report` Skill 接口

Skill 接收 `cr_id`、`source_node`、`tester` 和可选 `self_repair_attempt`，执行：

1. 读取 CR/PRD/SDD/TASK 和 implement-code 输出；
2. 生成 `.crctl/tmp/test-plan.json`；
3. 调用一次 `crctl test --plan ...`；
4. 根据返回的机器结果在 marker 后更新 TASK 覆盖、未覆盖风险和结果分析；
5. 返回 `status`、`blockers`、`repair-target=implement-code`、attempt 和分析路径。

Skill 不直接编辑 machine zone、traceability tests 或 review-loop。分析区写入失败时返回技术失败，Pipeline 当前节点中止；已发布的机器证据保留，重试时不改变旧 machine zone 直到下一次完整 `crctl test` 成功。

### 3.4 Pipeline contract

`code-implementation.pipeline.json` 保持现有节点数量和 reviewLoop 最大 3 次，仅修改 prompt 的职责描述：

- 测试节点：`implement-code -> write-test-report`，测试 Skill 自己构造 plan 并调用 `crctl test`；`status=block` 回到 implement-code；技术异常 abort。
- 代码评审节点：读取最终 `test-report.md`、日志和 digest，不执行命令；block 时按现有 `[implement-code, write-test-report, push-progress, review-code]` 重放。
- 代码评审 PASS 后仍调用现有 `push-progress`，phase 非 complete 不进入 human approval。

Pipeline 不传 `--cmd`、命令数组、traceability payload、review-loop 数值或 test journal 参数。

### 3.5 错误语义

| 错误/结果 | 类型 | 行为 |
|---|---|---|
| `TEST_PLAN_NOT_FOUND` | 技术错误 | 零 canonical 变化，修复临时 plan 后完整重试 |
| `TEST_PLAN_SCHEMA_INVALID` | 技术错误 | 零 canonical 变化，指出字段和路径 |
| `TEST_REPO_NOT_FOUND` / `TEST_REPO_INACTIVE` | 技术错误 | 拒绝未声明/inactive repo |
| `TEST_CWD_ESCAPE` | 技术错误 | 拒绝 absolute、`..`、跨 worktree 或 symlink escape |
| `TEST_EXECUTABLE_INVALID` | 技术错误 | 命令未启动，零 canonical 变化 |
| `TEST_LOOP_EXHAUSTED` | 技术错误 | 不运行计划，不新增 attempt |
| `TEST_MARKER_INVALID` | 技术错误 | marker 缺失/重复，零 canonical 变化 |
| `TEST_TRANSACTION_CONFLICT` / `CAS_CONFLICT` | 技术错误 | 不覆盖第三值，使用同一入口恢复/重试 |
| 已启动命令 non-zero | 业务结果 | 继续剩余命令，最终原子发布 `status:block` |
| 已启动命令 timeout | 业务结果 | 记录 timeout，继续剩余命令，最终原子发布 `status:block` |
| 全部命令 exit 0 | 业务结果 | 原子发布 `status:pass`，进入后续 checkpoint/review |
| 外部中断 | 技术中断 | 运行阶段不发布；记录阶段依赖既有 journal 恢复，不产生部分 attempt |

## 4. 关键算法与流程

### 4.1 前置校验与计划规范化

```text
loadAndValidatePlan(ctx, cr, planPath):
  assert CR status == developing
  assert owners.test.id and owners.test.assigned-at exist
  assert planPath is inside workspace/.crctl/tmp or allowed non-authority temp root
  raw = readFileChecked(planPath)
  norm = raw.replaceAll("\\r\\n", "\\n")
  doc = parseJson(norm); parse failure -> TEST_PLAN_SCHEMA_INVALID
  assert doc.schema == "cr-test-plan/v1"
  assert non-empty commands array
  for command in commands:
    assert exact field types and no forbidden fields
    repo = getRepository(ctx, command.repo)
    wt = repo.worktreePath/requirement/{cr}
    assert wt exists and branch == requirement/{cr}
    cwd = resolve(wt, command.cwd || ".")
    assert realpath(cwd) remains within realpath(wt)
    normalize command to POSIX-relative cwd
  assert review-loop current attempt < maxAttempts
  return normalized plan + commandDigest
```

任何失败发生在运行前，不能创建 test journal、lock、canonical log、report、traceability 或 review-loop。计划 JSON 解析使用结构化 JSON parser，不使用跨行正则或字符串拆字段。

### 4.2 运行阶段

```text
runTestPlan(plan):
  tempRoot = .crctl/tmp/test/{cr}/{process-random-token}
  for command in plan.commands:
    result = spawnSync(
      command.executable,
      command.args,
      { cwd: command.absoluteCwd, encoding: "utf8", shell: false,
        timeout: command.timeoutSeconds * 1000 }
    )
    write stdout/stderr to tempRoot/cmd-NN.log
    collect exitCode, signal, timedOut, started
    if started and (exitCode != 0 or timedOut): overall = block
  continue until every planned command has a result
  return results, tempRoot, overall
```

`spawnSync` 返回启动失败时视为技术失败并停止，不将未执行命令伪造为业务结果。已启动命令的 non-zero/timeout 不停止后续命令。tempRoot 不在 `test-evidence/` authority 目录下，运行阶段中断只留下可清理临时物，不改变 canonical 文件。

### 4.3 机器区构造与 marker 保护

```text
prepareReport(existingRaw, normalizedPlan, results):
  if missing:
    analysis = ""
  else:
    norm = existingRaw.replaceAll("\\r\\n", "\\n")
    markerMatches = exactMarkerPositions(norm)
    if markerMatches.length != 1: TEST_MARKER_INVALID
    analysis = text after marker, including its content but excluding marker
  machine = renderReportFrontmatterAndBody(normalizedPlan, results, commandDigest)
  return machine + marker + analysis
```

marker 必须是现有唯一 literal `<!-- crctl:analysis-below -->`；不接受旧的带说明文本作为第二种 canonical marker。为兼容已有报告，迁移实现可在一次明确的 reader 规则中识别当前报告中的 marker 前缀，但输出统一使用唯一 literal；缺失、重复和跨行匹配失败均硬失败，禁止猜测分界。

### 4.4 原子记录事务

```text
recordTestResult(ctx, cr, plan, results, tempRoot):
  inputDigest = sha256(commandDigest + canonical result metadata + owner assignment)
  existing = loadExistingJournal({ op: "test", cr, inputDigest })
  if existing incomplete:
    recover/apply existing write-set first
    return recorded response without rerunning commands
  if existing complete:
    return idempotent response changed=false

  read current report/traceability/review-loop and validate marker/shape
  compute next attempt and all four after texts before any authority write
  loadOrCreateJournal({ op: "test", cr, graphDigest, inputDigest })
  entries = [
    test-report.md,
    test-evidence/cmd-01.log ... cmd-NN.log,
    traceability.yml,
    review-loop.yml,
  ] with beforeSha256, afterSha256 and temp content
  applyWriteSet({ root: crWorktree, txId, entries })
  mark test journal complete and clean blobs/tempRoot
  audit one test record with status/attempt/digest; no per-command audit
  return structured response
```

写集建立前重新读取所有 authority 文件并进行 CAS；发生第三值或 marker/traceability 形状异常时不进入 apply。原始日志内容从 tempRoot 进入既有 write-set blob，不先写入 canonical `test-evidence/`。`traceability.yml#tests`、`review-loop.yml` 和 machine report 使用同一 `recordedAt`/attempt 事实。

本 CR 对 `durable-tx` 只做三项最小扩展：

1. `OPS` 与 `PAYLOAD_KEYS` 增加 `test`，复用同一 journal envelope 校验；
2. test scope 复用现有目录锁和 PID/hostname 保守阻断；
3. test transaction 的恢复继续调用已有 `applyWriteSet`/`recoverWriteSet`，不新增 test-specific WAL、saga 或补偿逻辑。

### 4.5 Review-loop 与业务分流

`testCr` 在完整命令结束后读取 code-implementation pipeline 中 `write-test-report.reviewLoop.maxAttempts`，并将下一 attempt 以同一写集投影到 `review-loop.yml`。当前 attempt 已达上限时在运行前返回 `TEST_LOOP_EXHAUSTED`。

- `status=pass`：Pipeline 允许写分析区，随后 push-progress 和 review-code。
- `status=block`：Pipeline 允许写分析区，但不得 checkpoint/review；按 `replayNodes` 返回 implement-code。
- 分析区写入失败：不删除已发布 machine record，当前 Pipeline 节点 abort；下一次流程从既有 report machine zone 读取并重新完成分析。
- `review-code` blocker：完整重放 implement、test、checkpoint、review；不在 review Skill 内直接执行命令。

### 4.6 故障恢复矩阵

| 故障点 | 首次结果 | 同一入口重试 |
|---|---|---|
| plan parse/repo/cwd/schema | 无 journal、无 authority | 修正 plan 后完整运行 |
| executable 无法启动 | 无 canonical attempt | 修正 executable 后完整运行 |
| 运行阶段进程中断 | 无 journal、canonical 旧值 | 完整 plan 重跑 |
| journal 创建后、write-set 前中断 | test journal/incomplete | 读取 journal；若无完整结果则使用持久化 payload 或硬失败要求完整重试 |
| 多文件 rename 间中断 | 可能部分 authority 文件 | `recoverWriteSet` 按 before/after 恢复，第三值硬失败 |
| complete 标记前中断 | 文件均可能为 after | journal/write-set 恢复并标 complete，不重复 attempt |
| 已完成记录后进程退出 | authority 已完整 | 返回 `changed=false`，不重复 attempt |
| 命令 non-zero/timeout | 完整 `block` 业务证据 | 修复代码后新完整 attempt |
| marker 缺失/重复 | 零写入 | 人工修 marker 后重试 |

“运行阶段不建 journal”意味着命令执行过程不能依赖 durable resume；它只保证不会把半次运行误记为 canonical attempt。记录阶段则完全由既有 write-set 恢复。

## 5. 技术选型与替代方案

| 决策 | 采用 | 不采用 | 原因 |
|---|---|---|---|
| 测试接口 | 一个 `crctl test --plan` | `test run` + `test record` 公共双接口 | 保持深接口，避免调用方协调运行/记录事务 |
| 参数传递 | `spawnSync(executable, args, {shell:false})` | shell 字符串、`exec`、`shell:true` | 原生 argv 安全，复用 Node 标准库 |
| 事务落点 | `workspace-transactions.testCr` + 既有 durable-tx | 新 test runner/service/WAL | 与 Tools 现有架构和单一 crctl 写者一致 |
| test journal | 既有 journal envelope 新增 payload slot | 把 test 伪装成 checkpoint/ledger 或新 journal 格式 | 事务恢复语义集中，业务 op 可审计 |
| 原始日志 | 运行阶段临时目录，记录阶段写入现有 test-evidence | 运行阶段直接写 authority | 中断时不会产生半套 canonical 证据 |
| report 更新 | 机器 prefix 重建、marker suffix 保留 | 全文覆盖、宽松首/末 marker | 防止丢失人工分析，异常硬失败 |
| traceability | 最小 tests 投影 | 复制完整 commands/logs | 单一事实源，减小回写和漂移面 |
| loop 投影 | 复用现有 maxAttempts/renderer，和写集同批发布 | Skill 手写 attempt、独立 loop ledger | 保持 crctl 唯一账本写入者 |
| 测试验证 | 现有 Node `node:test` 与 fault harness | 新测试框架/第三方 runner | 零依赖、现有 fixture 可复用 |
| 并发策略 | 运行阶段允许并行尝试，记录阶段锁/CAS 阻止覆盖 | 全程全局锁或自动合并 | 不长时间持锁；冲突显式失败更简单可恢复 |

### 5.1 被否决的过度设计

- 不增加 `test-run`、`test-record`、`test status` 命令。
- 不增加 provider/adapter/plugin registry；当前只有 Node `spawnSync` 一种执行器，尚无第二 adapter。
- 不增加环境变量 allowlist、配额服务、远程日志上传、完整 workspace digest 或数据库。
- 不把测试业务命令发现下沉到 crctl；命令选择仍由 `write-test-report` 负责。
- 不让 `review-code` 重新执行验证命令；证据不可信就 blocker，回到既有闭环。

## 6. FR 到技术实现映射

| PRD FR | 技术实现 | 验证 |
|---|---|---|
| FR-01 单一深接口 | `crctl.mjs` test dispatch + `workspace-transactions.testCr` | `--plan` 成功；`--cmd` 拒绝；不推进 status |
| FR-02 plan contract | `parseTestPlan`、resolver、cwd containment、commandDigest | schema/字段/repo/cwd/CRLF/digest 测试 |
| FR-03 安全执行与结果语义 | `spawnSync(executable,args,{shell:false})`、结果分类 | shell metachar、argv、non-zero、timeout、启动错误 |
| FR-04 原子发布 | durable-tx test payload + `applyWriteSet` | report/logs/traceability/loop 同批；第三值和 fault matrix |
| FR-05 marker 分区 | `parseAnalysisMarker` + machine renderer | 多行保留、缺失/重复/CRLF 硬失败 |
| FR-06 分层采用 | Skill/Pipeline/crctl/review-code prompt 收敛 | lint-prompts、pipeline structure、文本 contract |
| FR-07 评审审批门禁 | 复用现有 `reviewLoop`、`push-progress`、`approve-code` | block 不进 review/approval；PASS 后 checkpoint |
| FR-08 幂等跨平台 | input digest、journal recovery、LF canonicalization | 重试、中断、Windows/Ubuntu、无重复 attempt |

覆盖率：8/8。

## 7. 安全、性能、兼容性与回滚

### 7.1 安全

- 只允许 `dir-graph.yaml` 声明的 active repo；不接受调用方自报仓库路径。
- cwd 先做 lexical normalize，再做 realpath containment，禁止 absolute、`..`、末段 symlink escape 和跨仓访问。
- executable/args 分离传给 `spawnSync`，固定 `shell:false`，不接受 shell 语法开关。
- plan、report、traceability 和 journal 读取均先 CRLF→LF；跨行/marker 失败硬失败。
- machine zone、traceability tests 和 review-loop 只能由 crctl 写入；Skill 只写 analysis suffix。
- stdout/stderr 不进入 audit 或 traceability，避免把敏感输出复制到多个 authority。

### 7.2 性能

若计划含 `n` 条命令、输出总量为 `B`，预检为 `O(plan-size + n)`，执行成本由命令本身决定，记录阶段为 `O(B + n)`。不并行启动命令，不缓存跨 CR 结果，不计算完整工作树 hash。stdout/stderr 已由 `spawnSync` 返回并写入临时日志；实现不得为保存结果再构建第二份 canonical plan。

### 7.3 兼容与迁移

- 旧 `--cmd` 调用不提供永久兼容分支；合入后返回 `BAD_ARGS`，Skill/Pipeline 在同一 CR 内同步迁移。
- 已有 `test-report.md` 若使用当前 marker，重跑保留 marker 后内容；缺失或重复 marker 按新硬失败规则处理，不自动猜测历史分析边界。
- 旧 traceability 无 `tests` 时首次成功 test 创建；已有非映射/冲突 tests 硬失败，不批量迁移历史。
- 不修改状态机、gate 数量、审批接口和既有 checkpoint 语义。

### 7.4 回滚

代码提交按 `crctl.mjs`/workspace transaction、durable-tx、测试、Skill/Pipeline 文档分为可回滚 TASK。回滚实现前必须先停止新 `--plan` 调用并确认没有未完成 test journal；按既有事务恢复清理后再 revert。不得恢复 Skill 手写机器报告、traceability 或 review-loop 的旁路。回滚不删除已生成的合法 test evidence，只恢复 CLI/调用方兼容性需另行审批的历史行为。

## 8. Prompt 采纳影响

本 CR 修改 `skills/shared/crctl/scripts/crctl.mjs` 的既有 `test` dispatch 分支，因此本节按 Skill 契约列出所有必须同步采纳的调用方：

| 文件 | 当前状态 | 必须改为 |
|---|---|---|
| `skills/develop/write-test-report/SKILL.md` | 接受 `--cmd` 字符串，直接描述 traceability/review-loop 写入 | 生成临时 `cr-test-plan/v1`，一次调用 `crctl test --plan`，只写 marker 后分析 |
| `pipeline-templates/code-implementation.pipeline.json` | 测试节点按文字传递命令，代码评审 prompt 要求无条件重跑 lint/test/build | 只传 CR/source node；reviewLoop 重放 `implement-code -> write-test-report`，代码评审只读证据 |
| `skills/develop/review-code/SKILL.md` | 评审阶段重新执行实现期验证命令 | 删除执行入口；将测试缺失、漂移和不可信证据作为 blocker |
| `skills/shared/crctl/SKILL.md` | CLI 表格仍登记 `--cmd` | 更新 `--plan` 输入、结构化输出、业务 block/技术 error 语义 |
| `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | 断言旧测试节点 prompt/结构 | 断言节点仍有既有 replayNodes，且 prompt 不含 shell 字符串执行或评审重跑算法 |

Agent、agent-skill-matrix、README、状态机、gates 和 versioned writeback scripts 不需要变化。没有新的 Skill owner、Pipeline 节点或 crctl 公共子命令，因此不新增权限声明。

## 9. 验证计划

全部测试使用 Node 内置 `node:test`/`node:assert` 和现有黑盒 runner；不引入第三方依赖。至少覆盖：

1. 合法 plan 执行、command 顺序、repo/cwd canonicalization、`command-digest` 可复算；
2. `--cmd`、shell metachar、空格、Unicode、引号、pipe、redirect 不被执行为 shell；
3. schema 缺失、字段类型错误、未知/inactive repo、缺失 worktree、absolute/escape cwd、symlink escape、非正 timeout；
4. executable 启动技术失败零 canonical 变化；
5. non-zero 和 timeout 继续剩余命令，并最终原子发布 `block`；
6. 全部成功发布 `pass`；report/status/commands 由 crctl 生成；
7. machine zone command 对象、日志路径和 digest；修改 plan 后旧 digest 不匹配；
8. 新报告 marker、已有 marker 后多行分析保留；marker 缺失/重复/CRLF 边界硬失败；
9. traceability tests、review-loop 和 report 同一 write-set；traceability 其他段保留；
10. `tx-apply-between-rename`、`tx-apply-before-complete` 和已有 recovery 路径下无半状态、第三值阻断、重试不重复 attempt；
11. 运行阶段外部中断不产生 journal/attempt，记录阶段中断可从 test journal 恢复；
12. 同一完成事务重放 `changed=false`，不重复命令账本发布；
13. `write-test-report` 只改 analysis suffix，`review-code` 不执行测试，Pipeline JSON 与 reviewLoop 仍可解析；
14. block 不进入 checkpoint/review/approval；PASS 后 checkpoint 非 complete 不进入人工审批；
15. Ubuntu 与 Windows 的 CRLF/LF、路径和 argv 回归。

验证命令由实现期 `write-test-report` 依据仓库原生测试配置选择；最低定向命令为：

```text
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
node --test skills/shared/crctl/scripts/test/fault-harness.test.mjs
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
```

## 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-15 | v0.1.0 | Ray | 初始设计：单一结构化 test 深接口、shell:false、test journal/write-set 原子发布、marker 分区、reviewLoop 和调用方收敛 |

## 归档可信化（v0.20.3 · CR-2026-041）

## 1. 架构概览

### 1.1 当前实现与问题定位

目标代码仓是 Tools（`dir-graph.yaml#repositories.tools`，`trunk: custom/main`）。本 CR 只改该仓的方法论包代码，故其 `ARCHITECTURE.md` 是正确的架构基线（已存在，只读引用，不改）。

当前 `specs/{spec}/traceability.yml` 的新 milestone 段由 `skills/writeback/scripts/writeback-traceability.mjs`（candidate-only 固定 generator）构造，只含 `merge-commits`（从 `merge-commits.yml` 提取）与 `fr-chain`（从 milestone-file 读取），**没有测试/评审/审批/merge 的最小证据摘要**。`crctl archive` 在 `archiveCr` 的 writing-back 前置只校验 tasks 全 done、`specs/{spec}/traceability.yml` 存在、`approval.yml` 存在，**不校验证据真实、完整、可复算**。由此产生两类生命周期漏洞：

1. **证据投影缺失**：baseline 承诺"里程碑含测试、评审、审批证据"，但 generator 从未生成，archive 也不拦。
2. **事实源与文案漂移**：generator 的 trunk 提取仍带 `|| 'master'` 回退（`writeback-traceability.mjs:79`），头注释、`fromBacklog` 变量名与错误文案仍声称 merge 来源为 `_backlog.yml`（实际自 TASK-08 起已改读 `merge-commits.yml`）。
3. **虚假能力声明**：`change-impact-analysis` 建立在不存在的 `requirements[].reviews.*.result=stale` schema 上；`feedback-writeback` 只有 prompt 契约、直接手写 `traceability.yml`/`tech-notes` 并发送与 canonical 语义冲突的 inbox。二者作为 active Skill 存在于索引/矩阵/Agent/README/dir-graph hint/inbox allowlist 中。

### 1.2 目标架构

```text
writeback-traceability.mjs（版本化脚本，确定性转换）
  -> 读 milestone-file（业务正文）
  -> 读 merge-commits.yml（merge 事实，trunk 硬失败无 master 回退）
  -> 读 7 份 canonical 证据文件（test/reviews/approval/merge）
  -> 唯一 validateMilestoneEvidence 自检通过
  -> buildSegment 注入 evidence 块、不写 status
  -> candidate-only 输出（复用既有 writeCandidate / manifest / SELF_CHECK）

archiveCr（crctl 深模块）
  -> acquireLock（既有 archive lock）
  -> loadExistingJournal 只读分流：
       已 commit/push 或 cleanup/complete -> 既有恢复，跳过证据门
       无 journal / pre-authority journal -> 调用固定 generator 的 --validate-evidence 模式
  -> 通过后 loadOrCreateJournal + 四账本 write-set + commit + lease push + cleanup
```

generator 与 archive gate 复用同一份**确定性证据校验函数**：函数保留在已有版本化 generator `writeback-traceability.mjs` 内，正常生成时校验自身输出，archive 通过该 generator 的内部 `--validate-evidence` 模式调用同一函数。`crctl` 只负责固定脚本调用、门禁时序、错误映射与事务，不新增共享模块，不破坏 writeback/crctl 平行依赖方向。

### 1.3 模块职责与深模块边界

| 模块 | 职责/接口 | 明确不拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | Skill 完整算法、账本拼接、Git 恢复 |
| `writeback-traceability` Skill | 起草 milestone 业务正文，调用一次 `crctl writeback-apply` | 证据算法、digest、账本/CAS/事务 |
| `writeback-traceability.mjs`（版本化脚本） | milestone 段确定性构造、evidence 注入、唯一证据校验函数与内部校验模式 | 状态推进、审批、Git 发布 |
| `crctl.mjs` | 参数解析、`archive` 子命令接线、结构化输出 | 证据业务判断、事务内部算法 |
| `workspace-transactions.mjs` | `archiveCr` 证据门时序、固定 generator 调用、错误映射 | 复制证据校验算法、LLM 评审结论、里程碑业务内容 |
| `durable-tx.mjs` | 既有 journal/锁/write-set/恢复 | 证据语义、Git、状态机 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

本 CR 的深模块是 `archiveCr` 的证据门：调用方（`crctl archive`）只掌握 CR、spec-id 与结构化错误；证据定位、digest 重算、grant/merge 校验、pre-authority 分流都隐藏在 `archiveCr` 内。不新增 `traceability-record`、evidence registry、archive gate plugin 或第二事务框架。

### 1.4 已解决基础设施（只复用，不重做）

| 能力 | 现有实现 | 本 CR 处理 |
|---|---|---|
| durable transaction | `durable-tx.mjs`：journal envelope、目录锁、recoverable write-set、`loadExistingJournal`/`loadOrCreateJournal` | 全量复用；证据门在锁内、新 journal 前 |
| archive 四账本事务 | `archiveCr`：backlog/history/index/cr.md 同批 write-set + commit + lease push + cleanup-pending + outbox | 复用；只插入 pre-authority 证据门 |
| writeback-apply | `applyWritebackAtomic`：固定 generator、manifest 全矩阵校验、真实 generator hash、CAS、commit/push | 全量复用；本 CR 不做生产改动，只补回归 |
| 固定 generator 映射/hash | `WRITEBACK_GENERATORS`（`baseline/tasks/traceability`）+ `actualGeneratorSha` 比对 | 复用；FR-03 只回归确认 |
| review-record | 四份 `review-annotations/{requirement,sdd,dev-plan,code}.yml` | 复用为 review 证据事实源 |
| merge/approval/test 事实源 | `merge-commits.yml`、`approval.yml`、`test-report.md` 机器区 | 复用为证据事实源 |
| `parseYaml`/`matchEntryBlock`/`sha256`/`readHashRaw` | `yaml-subset.mjs`、`lib.mjs` | 复用为解析与 digest 原语 |
| CONTEXT.md / CUSTOM.md | 终态反馈事实 + `CUSTOM-TODO-010` | 保留，不新建实现 |

### 1.5 本次最小改造

| 改造点 | 文件 | 性质 |
|---|---|---|
| 注入 `evidence` 块 + 不写 status | `skills/writeback/scripts/writeback-traceability.mjs` | 版本化脚本确定性转换 |
| trunk 去 `master` 回退 + backlog 文案清理 | 同上 | 事实源修正（删一行 fallback + 改文案） |
| 证据门 | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 复用既有固定 generator 执行路径调用唯一 validator；crctl 只做时序/错误映射 |
| milestone-file 契约去掉 `status: writing-back` | `skills/writeback/writeback-traceability/SKILL.md` | 文本契约同步 |
| 删除两个退役 Skill + 清理 active 引用 | 见 §6 | 删除 |

## 2. 数据模型

### 2.1 evidence 块 schema（milestone 级，canonical 契约）

```yaml
evidence:
  test: { status: pass, path: change-requests/CR-.../test-report.md, sha256: ... }
  reviews:
    requirement: { verdict: pass, path: change-requests/CR-.../review-annotations/requirement.yml, sha256: ... }
    tech-design: { verdict: pass, path: change-requests/CR-.../review-annotations/sdd.yml, sha256: ... }
    dev-plan: { verdict: pass, path: change-requests/CR-.../review-annotations/dev-plan.yml, sha256: ... }
    code: { verdict: pass, path: change-requests/CR-.../review-annotations/code.yml, sha256: ... }
  approval: { status: approved, path: change-requests/CR-.../approval.yml, sha256: ... }
  merge: { status: merged, path: change-requests/CR-.../merge-commits.yml, sha256: ... }
```

字段语义（固定，不允许模型誊抄）：

| key | `status`/`verdict` 派生 | 门禁附加校验 |
|---|---|---|
| `test` | `test-report.md` frontmatter `status` | 必须 `pass` |
| `reviews.requirement` | `requirement.yml` `verdict` | 必须 `pass` |
| `reviews.tech-design` | `sdd.yml` `verdict` | 必须 `pass` |
| `reviews.dev-plan` | `dev-plan.yml` `verdict` | 必须 `pass` |
| `reviews.code` | `code.yml` `verdict` | 必须 `pass` |
| `approval` | 派生 `approved`（四段齐全） | `requirement/tech-design/development-start/code` 四段均存在且 `via ∈ {crctl-approve, server-approve}` |
| `merge` | 派生 `merged`（合并事实存在） | `schema=merge-commits/v1` 且 `repositories[]` 非空、每项含 `repo`+`merge-sha` |

### 2.2 固定 path map 与 digest 规范化（与 CAS 锚点区分）

固定 path map（generator 与 archive gate 必须逐项使用，evidence 中的 `path` 不得只做目录 containment）：

| evidence key | 唯一允许的 path |
|---|---|
| `test` | `change-requests/{cr}/test-report.md` |
| `reviews.requirement` | `change-requests/{cr}/review-annotations/requirement.yml` |
| `reviews.tech-design` | `change-requests/{cr}/review-annotations/sdd.yml` |
| `reviews.dev-plan` | `change-requests/{cr}/review-annotations/dev-plan.yml` |
| `reviews.code` | `change-requests/{cr}/review-annotations/code.yml` |
| `approval` | `change-requests/{cr}/approval.yml` |
| `merge` | `change-requests/{cr}/merge-commits.yml` |

path 校验先要求与 map 精确相等，再读取对应文件并重算 LF digest；containment 只是额外防护，不是 key 绑定。

- **证据 `sha256`**：`sha256(normalize(fileBytesUtf8))`，`normalize` 只做 `\r\n -> \n`。跨平台（Windows/Ubuntu）对同一语义内容得到相同值。
- **before/after CAS 锚点**：沿用既有 `readHashRaw`（磁盘字节哈希，不 CRLF 归一）。二者语义不同，不得混用：证据 digest 是跨平台可比的内容摘要，CAS 锚点是本地磁盘字节锚点。

### 2.3 milestone 段变化

- 新 milestone 段结构 = `cr` + `milestone` + `target-version` + `merge-commits` + `frs` + `evidence`（追加在 `frs` 之后）。
- **删除 `status` 字段**（FR-05）：新 milestone 不写瞬时 `writing-back`、不提前写 `archived`。CR 状态继续只由 `cr.md`/`_history.yml` 表达。
- 既有历史 milestone 段（含 CR-2026-038/039/040 已写入的 `status: writing-back`）作为 opaque 段逐字节保留。

## 3. 接口契约

### 3.1 generator 侧（`writeback-traceability.mjs`）

- `readEvidenceInputs(crDir)`：读取 7 份 canonical 文件，按 §2.2 固定 path map 生成 evidence 对象与 LF digest；输入缺失/状态不通过/结构非法时 `fail('EVIDENCE_INVALID', ...)`。
- `validateMilestoneEvidence({ traceText, cr, specId, editRoot })`：唯一证据校验函数。按固定 path map 定位当前 milestone，重读 canonical 文件、重算 digest，校验 status/verdict/grant/merge 事实。
- `buildSegment()` 在 `frs` 后追加 `evidence:` 块；不再输出 `status` 行；生成 candidate 后调用上述 validator 自检。
- 支持仅供 `crctl archive` 内部调用的 `--validate-evidence --workspace <ws> --cr <cr> --spec <spec>` 模式：读取既有 `specs/{spec}/traceability.yml`，调用同一 validator，只输出 JSON 结果，不生成 candidate、不推进状态、不写文件。
- trunk 提取：`trunkOf(repo)` 返回 `null` 时 `fail('TRUNK_UNKNOWN', ...)`，删除 `|| 'master'`。
- 文案清理：头注释、`fromBacklog` 变量、`MERGE_COMMITS_MISSING` 相关错误文案中的 `_backlog.yml` 全部改为 `merge-commits.yml`。
- SELF_CHECK 增加断言：candidate 内 `evidence:` 块恰好出现一次、`test/reviews(4)/approval/merge` 七项齐全、path map 精确、无 `\r`、既有段字节不变。

### 3.2 archive gate 侧（`workspace-transactions.mjs`）

`workspace-transactions.mjs` 不复制证据校验算法，只新增一个很薄的固定脚本调用适配：

```text
runFixedEvidenceValidator({ editRoot, cr, specId }) -> { ok: true } | throw TxError
```

行为：

1. 复用现有 `WRITEBACK_GENERATORS.traceability` 固定映射与脚本路径解析，调用 `writeback-traceability.mjs --validate-evidence`，执行器使用既有 Node `spawnSync(..., { shell: false })` 路径。
2. 将 generator 的 JSON 成功结果转为 `{ ok: true }`；非零退出或 JSON error 映射为 `ARCHIVE_EVIDENCE_MISSING`、`ARCHIVE_EVIDENCE_DUPLICATE`、`ARCHIVE_EVIDENCE_PATH_INVALID`、`ARCHIVE_EVIDENCE_DRIFT` 或 `ARCHIVE_EVIDENCE_STATE`。
3. 不传 candidate/manifest/generator 外部路径，不创建 journal，不写 authority，不新增 crctl 子命令；`crctl` 仍拥有 archive gate 的调用时序和失败中止。

### 3.3 `archiveCr` 插入点（pre-authority 分流）

在 `acquireLock` 之后、`loadOrCreateJournal` 之前插入只读分流：

```text
existing = loadExistingJournal({ op: 'archive', key: cr, inputDigest })
p = existing?.journal?.archive
needsEvidence = !existing
  || !(p && (p.committed || p.pushed || p.phase === 'cleanup-pending' || p.phase === 'complete'))
if needsEvidence:
    opWs = resolveOperationalWorkspace(ctx, cr)   # 只读
    if opWs.phase === 'writing-back':
        if !specId -> TxError ARCHIVE_SPEC_REQUIRED
        runFixedEvidenceValidator({ editRoot: opWs.path, cr, specId })
    # rejected/withdrawn：无 writing-back milestone，跳过
## 之后沿用既有 loadOrCreateJournal + 四账本流程（其内部 status 判定不变，重复 resolve 只读幂等）
```

失败语义：证据门失败释放 lock，不创建/不修改 journal，零 authority 写入、零审计，可补齐后同一命令重试。已 commit/push 或 cleanup/complete 的恢复路径跳过证据门，避免 cleanup 续跑时 CR worktree 已删导致解析失败。

### 3.4 错误码

| 错误码 | 触发 | 层 |
|---|---|---|
| `EVIDENCE_INVALID` | generator 侧输入状态不通过/缺失 | 版本化脚本 |
| `TRUNK_UNKNOWN` | trunk resolver 缺条目 | 版本化脚本 |
| `ARCHIVE_EVIDENCE_MISSING` | 当前 CR milestone/evidence 缺失 | crctl |
| `ARCHIVE_EVIDENCE_DUPLICATE` | milestone/evidence key 重复 | crctl |
| `ARCHIVE_EVIDENCE_PATH_INVALID` | 路径越界/跨 CR/非本 CR 前缀 | crctl |
| `ARCHIVE_EVIDENCE_DRIFT` | digest 重算不一致 | crctl |
| `ARCHIVE_EVIDENCE_STATE` | verdict/status/grant/merge 事实不通过 | crctl |

既有 `ARCHIVE_TASKS_PENDING`/`ARCHIVE_TRACEABILITY_MISSING`/`ARCHIVE_APPROVAL_MISSING` 保持不变。

## 4. 关键算法与流程

### 4.1 证据生成（generator）

```text
crDir = workspace/change-requests/{cr}
test    = readFrontmatter(crDir/test-report.md).status            # 必须 'pass'
reviews = for file in [requirement, sdd, dev-plan, code]:
            verdict = parseYaml(crDir/review-annotations/{file}.yml).verdict   # 必须 'pass'
approval= parseYaml(crDir/approval.yml)                            # 四段齐全 => 'approved'
merge   = parseYaml(crDir/merge-commits.yml)                       # repositories[] 有 merge-sha => 'merged'
evidence = { test: {status, path, sha256(归一内容)}, reviews: {...}, approval: {...}, merge: {...} }
buildSegment 追加 evidence 块
validateMilestoneEvidence({ traceText: generatedTraceText, cr, specId, editRoot: workspace })  # 同一函数自检
```

digest 用 `sha256(normalize(readFile(p)))`；路径为 workspace 相对 POSIX 路径 `change-requests/{cr}/...`。

### 4.2 证据校验（archive gate）

与 §4.1 同一个 `validateMilestoneEvidence` 函数：archive adapter 只通过固定 generator 的内部 `--validate-evidence` 模式调用它。函数从既有 `traceability.yml` 读 evidence 块 → 按固定 path map 重读 canonical 文件 → 重算 → 逐项比对；generator 与 archive 不各自复制规则。

### 4.3 archive pre-authority 分流

```text
lock(archive-{cr})
existing = loadExistingJournal(...)
if 无 journal 或 pre-authority journal:
    if writing-back: runFixedEvidenceValidator(...)   # 失败 -> 释放 lock, 零写入
    # rejected/withdrawn: 跳过
loadOrCreateJournal(...)     # 通过后才创建/修改 journal
recoverWriteSet / 四账本编辑 / commit / lease push / cleanup   # 既有流程不变
```

## 5. 技术选型与替代方案

| 决策 | 选择 | 理由 / 弃用 |
|---|---|---|
| 共享证据校验的实现方式 | 已有 generator 内唯一 validator + crctl 固定脚本调用适配 | 满足 PRD 的同一函数要求，同时保持 writeback/crctl 平行依赖；不新增共享模块、registry 或第二事务层 |
| 证据门位置 | archive lock 内、`loadOrCreateJournal` 前 | 弃用锁外预检：锁外无法串行化 journal 竞态；弃用新建"事务前置层"：只需把只读 `resolveOperationalWorkspace` 提前一次 |
| digest 语义 | LF 归一内容哈希 | 弃用 raw-bytes 哈希：证据要跨平台可比；raw 保留给 CAS 锚点 |
| 历史 milestone | opaque 逐字节保留，不迁移 | 弃用批量回填/伪 digest |
| 退役 | 删除文件 + active 引用，Git 历史兜底 | 弃用 retired stub / 占位 Skill |

## 6. FR 到技术实现映射

| FR | 实现条目 | 落点 |
|---|---|---|
| FR-01 最小证据摘要 | `readEvidenceInputs` + `buildSegment` 注入 `evidence` 块 | `writeback-traceability.mjs` |
| FR-02 事实源修正 | `trunkOf` 硬失败删 `master` 回退；`fromBacklog`→`fromMergeCommits`；注释/错误文案改 `merge-commits.yml` | `writeback-traceability.mjs` |
| FR-03 generator 身份既有回归 | 不改生产；补回归测试断言 `WRITEBACK_GENERATORS` 与 `actualGeneratorSha` | `test/` |
| FR-04 archive 证据门 | `runFixedEvidenceValidator` + `archiveCr` pre-authority 分流；唯一校验函数在固定 generator 内 | `workspace-transactions.mjs` + `writeback-traceability.mjs` |
| FR-05 历史 opaque / 无 status | `buildSegment` 删 `status` 行；历史段字节保留断言不变；SKILL.md 去 `status: writing-back` | `writeback-traceability.mjs` + 其 SKILL.md |
| FR-06 change-impact 退役 | 删 `skills/review/change-impact-analysis/SKILL.md`；清 `skills/_index.yml`、`agent-skill-matrix.yml`（quality-reviewer owns）、`AGENT-SKILL-MATRIX.md`、`agents/quality-reviewer-agent.md`、`agents/_index.yml`、`dir-graph.yaml#skill_context.change-impact-analysis`、`README.md`、`docs/QODER-使用指南.md`、`openwiki/architecture/agent-skill-matrix.md`；`review-alignment/SKILL.md` 删 AL-07 与"与其他 Skill 关系"中的 change-impact 行 | 删除+编辑 |
| FR-07 feedback 退役 | 删 `skills/cr/feedback-writeback/SKILL.md`；清 `skills/_index.yml`、矩阵/Agent/README/docs/openwiki；`inbox-emit/SKILL.md` 删 `feedback-writeback-done` allowlist 项；保留 `CUSTOM.md#CUSTOM-TODO-010` 与 CONTEXT.md | 删除+编辑 |
| FR-08 职责边界 | 不新增模块；改动只落版本化脚本与 `crctl` 深模块 | 全仓约束 |

退役引用边界：`docs/二开修改报告_v2.html`、`docs/AI-First-研发协同平台-架构讲解.html` 属历史报告/快照，保留不改（PRD FR-06.4/FR-07.5）。

## 7. 安全与性能考量

- **零副作用失败**：证据门在 journal 创建/修改前执行，失败释放 lock，无 journal/authority/审计残留。
- **路径绑定与 containment**：先按 §2.2 固定 map 要求 evidence key/path 精确相等，再拒绝绝对路径、`..`、反斜杠与跨 CR 前缀；目录 containment 只是第二层防护。
- **digest 不可伪造**：digest 由代码重算，不信任 milestone-file/manifest 自报；generator hash 由 `writeback-apply` 对固定脚本计算。
- **CRLF 纪律**：所有解析与 digest 输入先 LF 归一；跨行正则/解析失败硬失败（对齐工程纪律第 1 条）。
- **性能**：证据门为 7 个小文件的常数次读+hash，不引入额外持久化模型或后台任务；不缓存、不并行。
- **极简**：不新增 npm 依赖、schema registry、错误码中心、通用 traceability 接口、事务框架或强授权字符串模型。

## 8. 测试设计（与 §12 测试矩阵对齐）

- generator/validator：正常生成与内部 `--validate-evidence` 模式调用同一 `validateMilestoneEvidence`；证据七项齐全、固定 path map 精确、digest 可复算、CRLF/LF 同 digest、trunk 缺条目硬失败、merge 缺字段硬失败、新 milestone 无 status、历史段字节不变、SELF_CHECK。
- archive gate：固定 path map 精确绑定；证据齐全归档成功；milestone/evidence 重复、同 CR 内错误 path、跨 CR 路径、digest 漂移、verdict/status 非 pass、approval 缺 grant、merge 缺事实均由唯一 validator 硬失败且零 journal/authority 写入。
- pre-authority 分流：无 journal 校验；pre-authority journal 校验且失败不改 journal；已 commit/push 与 cleanup/complete 恢复跳过；rejected/withdrawn 跳过。
- FR-03 回归：`WRITEBACK_GENERATORS` 与 `actualGeneratorSha` 既有测试保持通过。
- 退役：静态扫描证明 active 路径零 `change-impact-analysis`/`feedback-writeback`/`feedback-writeback-done` 引用，且 `CUSTOM-TODO-010` 保留。
- 跨平台：Ubuntu/Windows 全量通过，不引入新生产依赖。

## 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-15 | v0.1.0 | Ray | 初始草稿：evidence 注入、archive 证据门、事实源修正、双 Skill 退役、职责边界 |
| 2026-08-15 | v0.1.1 | Ray | 按技术评审回修：固定 evidence path map；唯一 validator 保留在既有 generator，archive 通过内部校验模式调用，不新增共享模块 |

## Workspace 基线新鲜度与 CR Worktree 同步治理（v0.20.4 · CR-2026-043）

## 1. 架构概览

### 1.1 目标仓与架构基线

目标代码仓是 Tools（`dir-graph.yaml#repositories.tools`，`trunk: custom/main`）。本 CR 只改方法论包代码（`skills/shared/crctl/scripts/**`、`skills/sync/**`、`pipeline-templates/**` 与索引/README），故 `tools/ARCHITECTURE.md` 是正确的架构基线（已存在，只读引用，不改）。本设计遵守其硬不变量：零第三方依赖（不变量 3）、状态单一写者（不变量 1）、账本单一写入通道（不变量 2）、CRLF→LF 硬失败纪律（不变量 4）、durable-tx 唯一事务框架（§6 刻意不做）。

### 1.2 目标架构

```text
code-implementation.pipeline.json（Pipeline：节点顺序 / 输入传递 / reviewLoop / 失败中止）
  approve-dev-start
    → workspace-freshness(gate=implement-start)          【新增节点 ...016】
    → implement-code → write-test-report → push-progress
    → workspace-freshness(gate=review-start)             【新增节点 ...017】
    → [选择评审 LLM human_approval] → review-code → push-progress → approve-code

workspace-freshness Skill（业务判断：continue / sync / replay / manual）
  → crctl workspace freshness <CR-ID>        【新增窄 CLI，只读业务检查】
  → crctl workspace sync <CR-ID>             【新增窄 CLI，显式 ff-only 同步事务】

crctl.mjs cmdWorkspace（dispatch：inspect|ensure|cleanup|freshness|sync）
  → workspace-transactions.mjs
      classifyWorkspaceFreshness(ctx, cr)    【新增：第二层 freshness 分类，只读】
      syncWorkspaceToTrunk(ctx, { cr })      【新增：lock + journal + 逐仓 ff-only】
        ├─ classifyRepoWorkspace（复用：基础分类事实）
        ├─ gitRun/gitMust（复用：argv、shell:false）
        └─ durable-tx.mjs（复用：acquireLock op=workspace、journal envelope workspace payload、durableWriteFile）
```

### 1.3 模块职责与深模块边界

| 模块 | 职责/接口 | 明确不拥有 |
|---|---|---|
| Agent（dev-agent） | 路由、职责判断、选择 Pipeline/Skill；can-call workspace-freshness | 状态机、Git 算法、受控文件写入 |
| Pipeline（code-implementation） | 两个 gate 节点的位置、输入传递、reviewLoop replayNodes、失败中止 | Skill 完整算法、git 命令、手写账本 |
| `workspace-freshness` Skill | 读 crctl 结构化结果做业务路由；编排 freshness→条件 sync→重核；定义输入输出与失败语义 | ancestry/锁/journal/CAS 算法、重复实现 crctl |
| `crctl.mjs` | `workspace freshness|sync` 参数解析、TxError→fail、audit 登记、HELP 文本 | 业务设计判断、LLM 评审结论、状态推进 |
| `workspace-transactions.mjs` | freshness 分类与同步事务的唯一实现：resolver 复用、preflight、重核、ff-only、journal、恢复 | 状态机、业务账本、远端分支发布 |
| `durable-tx.mjs` | 既有锁/journal/write-set/故障注入登记 | workspace 业务语义 |
| 版本化脚本 | 本 CR 不新增 | — |
| README | 命令入口、结果含义、人工动作索引 | 分类算法或恢复状态机的另一份事实源 |

深模块是 `syncWorkspaceToTrunk`：调用方（CLI/Skill）只掌握 CR-ID 与结构化错误；preflight、锁、逐仓重核、ff-only、journal 与恢复全部隐藏其中。不新增第二事务框架、branch manager 或通用同步接口。

### 1.4 已解决基础设施（只复用，不重做）

| 能力 | 现有实现（已核实） | 本 CR 处理 |
|---|---|---|
| Repository/worktree resolver | `workspace-transactions.mjs#resolveRepositories`：dir-graph 唯一解析、repo id 稳定排序、realpath 身份校验、graphDigest | 全量复用；不新增 repo 配置 |
| Workspace 基础分类 | `classifyRepoWorkspace`：`missing/healthy/branch-only/remote-only/dirty/wrong-branch/path-unregistered`；`WORKSPACE_CLASSIFICATIONS` | freshness 为第二层关系；基础分类与 `ensureRepoWorkspace` 零改动 |
| 受控 Git | `gitRun/gitMust`（`spawnSync('git', args, {shell:false})`），事务处理器独占 Git 副作用 | 复用 fetch、`merge-base --is-ancestor`、`rev-parse`、`merge --ff-only` |
| Durable transaction | `durable-tx.mjs`：`OPS`/`PAYLOAD_KEYS` 已含 `workspace`；`acquireLock({scope,op})`（scope 正则 `[A-Za-z0-9:_-]+`）；journal envelope；`loadOrCreateJournal`（inputDigest 漂移→TX_INPUT_CONFLICT）；`durableWriteFile`；`FAULT_POINTS` 全仓唯一登记表 | 同步事务沿用 op=`workspace`；新增 2 个故障点登记进 FAULT_POINTS |
| Audit 与结构化错误 | `auditLog`（`.crctl/audit.log` JSONL）；`TxError`；`fail(code)` | 复用；freshness/sync 在局部 catch 中先 audit 再 fail，不修改全局 runTxAsync |
| Source 发布与重核 | checkpoint、review-record release-subjects、approve-code/merge 重核 | 零改动；sync 不发布远端分支 |
| Pipeline 自修复 | code-implementation reviewLoop（maxAttempts=3、replayNodes、passCondition） | 扩展 review-code 节点 replayNodes 插入 freshness 重放 |
| 契约台账 | `skills/_index.yml`、`agent-skill-matrix.yml`、`pipeline-templates/_index.yml` | 新增 Skill 登记与节点数同步（13→15） |

### 1.5 本次最小改造

| 改造点 | 文件 | 性质 |
|---|---|---|
| `classifyWorkspaceFreshness(ctx, cr)` | `lib/workspace-transactions.mjs` | 新增只读分类函数（复用 classifyRepoWorkspace + ancestry） |
| `syncWorkspaceToTrunk(ctx, { cr })` | `lib/workspace-transactions.mjs` | 新增同步事务（lock + journal + 逐仓 ff-only + 只向前恢复） |
| `workspace freshness|sync` 子命令 | `crctl.mjs`（cmdWorkspace dispatch + HELP） | 窄 CLI 接线，不含算法 |
| 故障点登记 | `lib/durable-tx.mjs#FAULT_POINTS` | 追加 2 条（`ws-sync-after-preflight`、`ws-sync-after-repo`） |
| `workspace-freshness` Skill | `skills/sync/workspace-freshness/SKILL.md` | 新增窄 Skill（业务路由） |
| 两个 gate 节点 + replayNodes | `pipeline-templates/code-implementation.pipeline.json` | 插入 ...016/...017，扩展 ...009 replayNodes |
| 台账同步 | `skills/_index.yml`、`agent-skill-matrix.yml`、`pipeline-templates/_index.yml` | 登记 |
| README 人读段 | `README.md` | 入口与人工动作索引 |
| 测试 | `test/workspace-freshness.test.mjs`（新增）、契约断言并入现有 contract 测试 | 分类/事务/契约/集成 |

`gates.json`、`dir-graph.yaml#change-request-track.state_machine`、`rules.json`（controlled-shell 白名单）均**零改动**：freshness 是 pipeline 节点级门禁而非状态机门禁；`merge --ff-only` 发生在 crctl 深原语内部（gitMust 不经 rules.json 白名单），不扩展 `crctl git` 面。

## 2. 数据模型

### 2.1 每仓 freshness 事实（只读输出）

```typescript
interface RepoFreshnessFact {
  repo: string;                    // repository id
  trunkRef: string;                // 如 "custom/main"
  trunkSha: string | null;         // fetch 后捕获的 refs/remotes/origin/{trunk}
  branch: string;                  // 固定 requirement/{CR-ID}
  headSha: string | null;
  worktreePath: string;
  workspaceClassification: 'missing'|'healthy'|'branch-only'|'remote-only'|'dirty'|'wrong-branch'|'path-unregistered';
  freshness: 'fresh'|'behind-clean'|'diverged'|'unknown';  // 不可比较时 unknown
  dirty: boolean;
  canFastForward: boolean;         // freshness==='behind-clean' 的机械投影
  reason?: string;                 // unknown/blocked 时的结构化原因
}

interface FreshnessResult {
  cr: string;
  repositories: RepoFreshnessFact[];   // 按 repo id 排序
  allFresh: boolean;
  syncable: boolean;                   // 无阻断项且至少一仓 behind-clean（或全 fresh 时 false）
}
```

### 2.2 同步结果与 journal payload

```typescript
interface RepoSyncRecord {
  repo: string;
  beforeSha: string;
  targetTrunkSha: string;
  afterSha: string | null;
  action: 'unchanged'|'fast-forwarded'|'pending'|'blocked';
  reason?: string;
}

interface SyncResult {
  cr: string;
  txId: string | null;      // 全 fresh no-op 时为 null（不创建空 journal）
  phase: 'complete';
  changed: boolean;
  repositories: RepoSyncRecord[];
  recoverCommand: string;
}
```

journal（op=`workspace`，key=`{CR-ID}`）的 `workspace` payload：

```json
{
  "phase": "preflight | syncing | complete",
  "repos": [
    { "repo": "tools", "beforeSha": "...", "targetTrunkSha": "...", "afterSha": "...", "action": "fast-forwarded" }
  ]
}
```

journal 创建与 intent 绑定遵循以下唯一顺序：

1. 获取 lock 后先用 `loadExistingJournal({ op:'workspace', cr })` 只读分流；存在非 complete journal 时，只按该 journal 已记录的 `repos[].beforeSha/targetTrunkSha` 恢复，禁止基于部分完成后的新 HEAD 重新生成 intent。
2. 无在途 journal（含 latest 为 complete）时先执行全仓 preflight；`allFresh` 直接返回 `txId:null`，阻断结果直接抛错，两者均不创建 journal。
3. 仅 syncable 时生成 `intentDigest = sha256(canonicalJson({ graphDigest, cr, repos:[{repo,beforeSha,targetTrunkSha}] }))`（repos 按 id 排序），再调用 `loadOrCreateJournal({ op:'workspace', cr, graphDigest, inputDigest:intentDigest, createAfterComplete:true })`。
4. latest complete 后 trunk 再前进会产生不同 intentDigest，从而创建新事务；若外部操作把 HEAD 回退到旧 complete journal 的 beforeSha，不复用旧 complete 结果，按 `WORKSPACE_FRESHNESS_CHANGED` 保守阻断。

这样同一在途 intent 重跑可续接，不同 trunk 目标不会误命中旧 complete journal，并兑现“全 fresh 不创建空 journal”。

### 2.3 audit 记录

| kind | 记录时机 | 字段 |
|---|---|---|
| `workspace-freshness` | 仅阻断或技术失败（成功只读不逐次写） | cr、actor、失败 code、阻断 repo 列表 |
| `workspace-sync` | 每次 sync 调用（含 no-op 与失败） | cr、txId、phase、changed、每仓 action/beforeSha/targetSha/afterSha、actor |

不新建 workspace ledger；成功 fast-forward 的业务提交本身即 Git 权威事实（不变量 6）。

## 3. 接口契约

### 3.1 CLI（crctl.mjs）

```text
crctl workspace freshness <CR-ID> [--workspace <path>]
crctl workspace sync      <CR-ID> [--workspace <path>]
```

- cmdWorkspace dispatch 白名单由 `inspect|ensure|cleanup` 扩展为 `inspect|ensure|cleanup|freshness|sync`；freshness/sync 不接受任何其他 flag（多余 flag → `BAD_ARGS`），CR-ID 复用既有 `/^CR-\d{4}-\d{3,}$/` 校验。
- freshness：局部 `try/catch` 调用 `classifyWorkspaceFreshness(ctx, cr)`；成功且 `allFresh=true` 不写 audit，成功但存在 non-fresh 业务阻断时先写 `workspace-freshness` audit 再 `ok(...)`；TxError 在 `fail(...)` 前写失败 audit。
- sync：局部 `try/catch` 调用 `syncWorkspaceToTrunk(ctx, { cr })`；成功/no-op 均先写 `workspace-sync` audit 再 `ok(...)`；TxError 在 `fail(...)` 前写失败 audit（携带 `e.extra` 中的 repo/SHA/txId）。不得把这两个分支交给现有 `runTxAsync` 后再审计，因为其错误路径会直接 `fail`；其他 workspace 子命令继续复用 `runTxAsync`，不修改全局语义。
- HELP 文本追加两行用法说明（不写算法细节）。

### 3.2 深模块函数（workspace-transactions.mjs）

```typescript
/** 只读业务检查：零写入（fetch 更新 remote-tracking 元数据除外）。 */
export function classifyWorkspaceFreshness(ctx, cr): FreshnessResult

/** 显式 ff-only 同步事务：lock(op=workspace, scope=workspace-sync-{cr}) + journal + 逐仓重核。 */
export async function syncWorkspaceToTrunk(ctx, { cr }): Promise<SyncResult>
```

错误码（TxError，经 cmdWorkspace freshness/sync 的局部 catch 先 audit、再映射为 fail）：

| code | 语义 |
|---|---|
| `WORKSPACE_FRESHNESS_DIVERGED` | 双方互不为祖先，人工处理 |
| `WORKSPACE_FRESHNESS_CHANGED` | preflight 与写入间 trunk/HEAD/branch/dirty 漂移 |
| `WORKSPACE_TRUNK_UNAVAILABLE` | fetch 或 origin/{trunk} 不可确认 |
| `WORKSPACE_SYNC_BLOCKED` | 基础分类/路径/分支/注册不满足（携带 workspaceClassification） |
| `WORKSPACE_SYNC_CONFLICT` | ff-only 失败或 afterSha≠targetSha |
| 既有复用 | `TX_LOCK_HELD`、`TX_GIT_FAILED`、`REPO_GRAPH_*`、`TX_INPUT_CONFLICT`、`WORKSPACE_CR_INVALID` |

`WORKSPACE_FRESHNESS_STALE` 不是错误码：`behind-clean` 是 freshness 输出中的正常业务事实，由 Skill 决定是否 sync（PRD FR-02：只读检查不得把可同步状态表达为失败）。

### 3.3 Skill 契约（skills/sync/workspace-freshness/SKILL.md）

输入：

| 参数 | 必填 | 说明 |
|---|---|---|
| `cr_id` | ✅ | 目标 CR-ID |
| `gate` | ✅ | `implement-start` \| `review-start` |

输出（供 Pipeline 分流）：`route` ∈ `continue`、`synced-continue`、`replay`、`manual`；`facts`（freshness 结构化结果摘要）；`blockers`（manual 时逐仓原因）。

路由规则：

| gate | freshness 结果 | route |
|---|---|---|
| implement-start | allFresh | `continue` |
| implement-start | syncable | 调 sync → 重跑 freshness → allFresh ? `synced-continue` : `manual` |
| implement-start | 其余 | `manual`（abort，不进入 implement-code） |
| review-start | allFresh | `continue` |
| review-start | syncable | 调 sync → `replay`（review_feedback：基线已前进，需重建实现/测试/checkpoint 证据） |
| review-start | 其余 | `manual`（abort，不盲目消耗 reviewLoop） |

Skill 只调用 `crctl workspace freshness|sync`；不出现 git 命令、锁、journal、CAS、状态推进或账本编辑步骤。

台账登记：`skills/_index.yml` 新增 active 条目；`agent-skill-matrix.yml` 中 `system-orchestrator.owns += workspace-freshness`（唯一 owner）、`dev-agent.can-call += workspace-freshness`。

### 3.4 Pipeline 契约（code-implementation.pipeline.json）

| 新节点 | id | 位置 | ref / 输入 | onFail |
|---|---|---|---|---|
| Workspace freshness（实施前） | `00000000-0000-0000-0015-000000000016` | `approve-dev-start`(...005) 之后、`implement-code`(...006) 之前 | workspace-freshness，`gate=implement-start` | abort |
| Workspace freshness（评审前） | `00000000-0000-0000-0015-000000000017` | 统一 checkpoint `push-progress`(...008) 之后、「选择代码评审 LLM」human_approval(...013) 之前 | workspace-freshness，`gate=review-start` | abort |

`review-code` 节点(...009) 的 `reviewLoop.replayNodes` 由 4 项扩为 5 项：

```text
implement-code(...006) → write-test-report(...007) → push-progress(...008)
  → workspace-freshness(...017, purpose: re-verify-baseline) → review-code(...009)
```

write-test-report 节点(...007) 的测试证据闭环 replayNodes（`implement-code → write-test-report`）不变。`pipeline-templates/_index.yml` 的 code-implementation `nodes: 13 → 15`。

节点 prompt 只描述：读取输入、调用一次 Skill、按 route 分流、失败中止；不复制 Skill 步骤全文，不出现 git/journal 字样。

## 4. 关键算法与流程

### 4.1 classifyWorkspaceFreshness（只读）

```text
for repo of ctx.repositories（已按 id 排序）:
  info = classifyRepoWorkspace(ctx, repo, cr)          # 复用，零改动
  if info.classification != 'healthy':
    emit freshness='unknown', reason=classification     # 不猜测
    continue
  headSha = gitMust(wt, ['rev-parse','HEAD'])
  status = gitMust(wt, ['status','--porcelain'])
  if status 非空: emit freshness='unknown', reason='dirty-during-check'; continue
  gitMust(repo.rootPath, ['fetch','origin'])            # 仅更新 remote-tracking 元数据
  trunkSha = gitMust(repo.rootPath, ['rev-parse', `refs/remotes/origin/${repo.trunk}`])
      # 失败 → WORKSPACE_TRUNK_UNAVAILABLE（该仓 unknown，整体不可 fresh）
  if headSha == trunkSha                              → fresh
  elif isAncestorOrThrow(repo, trunkSha, headSha)     → fresh        # ahead-only 是正常开发态
  elif isAncestorOrThrow(repo, headSha, trunkSha)     → behind-clean, canFastForward=true
  else                                                → diverged

isAncestorOrThrow(repo, a, b):
  r = gitRun(wt, ['merge-base','--is-ancestor', a, b])
  if r.status == 0: return true
  if r.status == 1: return false                       # Git 对“非祖先”的唯一正常否定
  throw TxError('TX_GIT_FAILED', ..., {repo,args,status,stderr})

allFresh = 全部 fresh；syncable = allFresh ? false : 无阻断项 && 存在 behind-clean
```

禁止用时间戳、commit message、`log` 计数等启发式替代 ancestry；尤其不得把 `merge-base` 的 status>1 降级为 diverged/unknown 空结果（PRD FR-01.5、FR-02.4）。

### 4.2 syncWorkspaceToTrunk（事务）

```text
lock = acquireLock({ root, scope: `workspace-sync-${cr}`, op: 'workspace' })
existing = loadExistingJournal({ op:'workspace', cr })

## 1) existing 非 complete：恢复已记录 intent
##    校验 graphDigest 未漂移；直接使用 payload.repos 的 beforeSha/targetTrunkSha；
##    已在 targetSha 的仓 confirmed，仍在 beforeSha 的仓 pending，其余事实 WORKSPACE_FRESHNESS_CHANGED。

## 2) 无在途 journal：锁内全仓 preflight（任何 worktree 写入前）
##    allFresh → changed=false, txId=null 直接返回（不创建 journal）
##    任一仓非 fresh 且非 behind-clean → 零仓写入，抛对应 TxError（不创建 journal）
##    syncable → 以 graphDigest + 排序后的 repo/beforeSha/targetTrunkSha 生成 intentDigest；
##               若 latest complete.inputDigest == intentDigest 但当前又回到 syncable，说明已完成结果被外部回退，
##                 → WORKSPACE_FRESHNESS_CHANGED（禁止复用旧 complete）；
##               否则 loadOrCreateJournal({op:'workspace',cr,inputDigest:intentDigest,createAfterComplete:true})，
##               写入 workspace payload 并 save('preflight')
##    faultPoint('ws-sync-after-preflight')

## 3) 逐仓（repo id 顺序，跳过已 confirmed/fast-forwarded 的仓）：
for repo of pending behind-clean 仓:
  重核：branch、status --porcelain 为空、HEAD==beforeSha、重新 fetch 并比对 origin/{trunk} SHA
  任一漂移 → WORKSPACE_FRESHNESS_CHANGED（停止后续仓）
  gitMust(wt, ['merge','--ff-only', targetSha])        # 唯一允许的 worktree 写操作
  afterSha = gitMust(wt, ['rev-parse','HEAD'])
  if afterSha != targetSha → WORKSPACE_SYNC_CONFLICT
  payload.repos[i].action='fast-forwarded'; save('syncing')
  faultPoint('ws-sync-after-repo')

## 4) save('complete') → 返回 SyncResult（recoverCommand = 同一 sync 命令）
finally lock.release()
```

恢复语义：非 complete journal 只恢复原始 intent，不根据部分完成后的新 HEAD 重算 digest；已到 targetSha 的仓标 `confirmed`，仍在 beforeSha 的仓继续，其余漂移硬失败。latest complete 不阻止后续新 trunk intent：新 preflight 产生不同 intentDigest，经 `createAfterComplete:true` 创建新事务。不 reset/revert/删除 journal（PRD FR-04）；多仓只向前，不承诺跨仓 ACID 回滚。

### 4.3 Skill 编排（review-start 同步后重放）

sync 改变了 source HEAD，既有测试/评审/checkpoint 证据全部失效。Skill 返回 `replay` 并附 review_feedback；Pipeline 按 reviewLoop 从 implement-code 顺序重放到 review-code（§3.4）。diverged/manual 场景不进入 replay（避免用自动重试掩盖人工冲突），输出每仓 repo/path/SHA 供人工处理；人工把事实恢复为可比较状态（如提交、pull-progress 或重开 worktree）后重新走 gate。

### 4.4 实施顺序（同一 CR 内，无 feature flag）

1. Phase A：`classifyWorkspaceFreshness` + freshness 子命令 + 分类测试（只读，先落地最安全）。
2. Phase B：`syncWorkspaceToTrunk` + sync 子命令 + 故障注入/恢复测试。
3. Phase C：Skill + Pipeline 两个 gate + replayNodes + 契约测试 + 台账同步。
4. Phase D：README 人读段。

## 5. 技术选型与替代方案

| 被审查方案 | 结论 | 原因 |
|---|---|---|
| 第二套事务框架/WAL/branch manager | 删除 | durable-tx 已有 workspace op、锁、journal、恢复（ARCHITECTURE §6 明确否决） |
| 扩展 `pull-progress` 处理 trunk freshness | 删除 | 其事实源是远端 requirement checkpoint，方向与语义不同，混用会产生两个 trunk 事实源 |
| `ensureRepoWorkspace` 自动同步 | 删除 | 会把注册/resume 的只读补齐扩权成隐式写操作 |
| 自动 merge/rebase/冲突解决 | 删除 | 无法机械判断独有提交的业务取舍；违反零覆盖承诺 |
| 检查远端 requirement 分支一致性 | 删除 | checkpoint/push-progress 既有职责，两个能力不得重复拥有同一远端事实 |
| ahead/behind commit count | 延后 | ancestry 足够 gate 与 sync；count 只增加解析与测试矩阵 |
| 四处 freshness gate | 收敛两处 | implement 前 + review 前覆盖关键边界；测试/checkpoint/审批已有既有重核 |
| 每次成功 freshness 写 audit | 删除 | 审计噪声；只持久化 sync、阻断、竞态与失败 |
| feature flag / 观察期账本 / daemon | 删除 | Phase A→D 的 CR 内顺序已提供安全落地路径 |
| 新增 Agent / npm 依赖 / 版本化脚本 | 删除 | 现有 actor、Node 标准库与 crctl 深原语足够 |

## 6. FR 到技术实现映射

| PRD | 实现落点 |
|---|---|
| FR-01 分层分类 | §4.1 classifyWorkspaceFreshness；freshness 与 WORKSPACE_CLASSIFICATIONS 分层输出 |
| FR-02 只读检查 | §3.1 freshness 子命令；§4.1（fetch 边界、unknown 不降级、allFresh 成功不写 audit、阻断/失败先 audit） |
| FR-03 显式同步 | §4.2 syncWorkspaceToTrunk（全仓 preflight、唯一 ff-only、白名单外参数 BAD_ARGS） |
| FR-04 幂等/竞态/恢复 | §4.2（inputDigest、逐仓重核、fault points、只向前恢复、多仓顺序语义） |
| FR-05 生命周期 gate | §3.4 两个节点 + replayNodes 扩展；gate 是 Pipeline 编排而非状态机门禁（gates.json 零改动） |
| FR-06 Skill/Agent/crctl/文档 | §3.3 Skill 契约与台账登记；§1.3 职责表；§8 采纳清单；README 人读段 |

## 7. 安全与性能考量

### 7.1 安全边界

- 唯一 worktree 写操作是 `git merge --ff-only <captured-sha>`；代码中不得出现 reset/clean/stash/rebase/force/普通 merge 的 sync 路径（契约测试扫描）。
- dirty/diverged/unknown/wrong-branch/missing/branch-only/remote-only/path-unregistered 在全仓 preflight 即零写入硬失败。
- ff-only 前逐仓重核四项事实；锁只串行化本地 crctl 事务，不假设锁住远端 trunk——trunk 前进靠重核与既有 release-subjects 重核兜底。
- `crctl git` 白名单（rules.json）不扩展：sync 的 Git 写发生在深原语 gitMust 内部；Skill 侧只读需求由 freshness 子命令满足，无需新增白名单形态。

### 7.2 性能

- 每 gate 每仓成本：1×classify + 1×fetch + ≤2×ancestry；无缓存、无后台扫描、无并发。
- freshness 无锁；sync 独占 `workspace-sync-{cr}` 锁，冲突返回既有 TX_LOCK_HELD。
- 无新增生产依赖（不变量 3）；全部解析先 CRLF→LF、`split(/\r?\n/)`、失败硬失败（不变量 4）。

### 7.3 测试设计

| 层 | 用例 |
|---|---|
| 分类单元 | fresh（HEAD==trunk）、fresh（ahead-only）、behind-clean、diverged、六类非 healthy 基础分类→unknown、trunk 缺失/fetch 失败→WORKSPACE_TRUNK_UNAVAILABLE、`merge-base` status>1→TX_GIT_FAILED（不得变 diverged）、多仓稳定排序、Windows 路径身份与 CRLF |
| 事务（`test/workspace-freshness.test.mjs`，复用现有 fixture） | ff-only 成功且 afterSha==target；全 fresh no-op 不建 journal；dirty/diverged/unknown 零写入；preflight 阻断全仓零写入；`ws-sync-after-repo` 故障注入后续跑只使用 journal 原始 intent；latest complete 后 trunk 再前进创建新事务；trunk 变化→WORKSPACE_FRESHNESS_CHANGED；HEAD/branch/dirty 变化→硬失败；并发锁→TX_LOCK_HELD；重跑幂等不重复提交；freshness/sync 技术失败与业务阻断均在 fail 前写 audit |
| 契约 | workspace-freshness active 且 system-orchestrator 唯一 owns、dev-agent can-call；两节点位于 implement-code 前与 review-code 前；replayNodes 含 ...017；`_index.yml nodes=15`；Pipeline prompt 无 git/journal 字样；SKILL.md 无 Git 算法/账本编辑步骤 |
| 集成 | implement gate：behind-clean→sync→继续；diverged→abort；review gate：trunk 前进→拦截→按 replayNodes 重建证据；Windows 与 Ubuntu 各一遍 active repository 矩阵 |

## 8. Prompt 采纳影响

本 CR 触及 `crctl.mjs` 的 dispatch 分支（cmdWorkspace 新增 freshness|sync），本节必填；不触及 `rules.json#protectedPaths.deny`。

| Skill / 文档 | 现状 | 应改为 |
|---|---|---|
| `skills/sync/workspace-freshness/SKILL.md` | 不存在 | 新增：唯一调用方，`crctl workspace freshness` + 条件 `crctl workspace sync`，按 §3.3 路由 |
| `skills/shared/crctl/SKILL.md` | brief 未含 workspace freshness/sync | brief/能力描述补充两个窄子命令（能力面声明，不含算法） |
| `pipeline-templates/code-implementation.pipeline.json` | 无 freshness gate | 按 §3.4 插入两节点并扩展 review-code replayNodes |
| `README.md` | 无 freshness 入口 | 增加命令入口、结果含义与人工处理动作一段，链接 Skill/crctl 权威契约 |

明确不采纳（防止过度扩散）：`implement-code`/`review-code`/`pull-progress`/`push-progress`/`write-test-report` 的 SKILL.md 均不改动——gate 是独立 Pipeline 节点，review-code 的 merge-base diff range、checkpoint 与 pull-progress 的远端 requirement 语义保持原样。

## 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.1.0 | Ray | 初始设计：两层分类、显式 ff-only 同步事务、双 gate 与 reviewLoop 重放、职责边界与采纳清单 |
| 2026-08-16 | v0.1.1 | Ray | 按技术评审 attempt 1 回修：preflight 前不建 journal、intentDigest 绑定 before/target、在途只按原 intent 恢复、失败 audit 前置、ancestry 退出码硬区分 |

## tools CR 生命周期最小优化 5/5 — 职责边界清理（vtbd · CR-2026-042）

## 1. 架构概览

### 1.1 设计目标

本 CR 只收缩 Tools 包的调用方合同，不改 CR 生命周期执行层。目标是让每层只保留调用者真正需要知道的 interface：

- Agent 只决定路由和职责归属；
- Pipeline 只表达节点顺序、输入传递、reviewLoop 和失败中止；
- Skill 只表达业务判断、编排步骤、公开输入输出和失败语义；
- `crctl` 继续作为状态、门禁、CAS、受控账本、Git 发布、审计和恢复的深模块；
- 版本化脚本继续只做确定性内容转换；
- README 只做面向人的总览和权威入口。

实现以删除重复文本为主，不新增运行时进程、公共命令、账本、schema、依赖或事务层。

### 1.2 现有深模块与 seam

现有外部 seam 保持不变：

```text
Agent/runtime
  -> Pipeline JSON（顺序、输入、reviewLoop）
    -> Skill（业务判断与公开调用）
      -> crctl CLI（状态、账本、Git、事务、审计）
        -> Node 标准库 + 现有 durable/workspace modules
```

`crctl` 的 interface 是公开命令、前置条件、结构化结果和错误语义；journal、write-set、CAS、lease、candidate、manifest、detached workspace 等均属于 implementation。删除调用方中的 implementation 复述后，复杂度不会扩散到其他调用方，反而集中回 `crctl`，因此不需要新增 adapter、factory 或第二个 module。

静态治理继续复用现有 `lint-prompts.mjs` seam：命令保持 `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`，只扩展扫描对象和少量确定性判据。

### 1.3 已解决基础设施与本次边界

| 能力 | 权威实现 | 本次动作 |
|---|---|---|
| 状态机与门禁 | `dir-graph.yaml`、`gates.json`、`crctl status/next/advance` | 不改 |
| 人工审批 | `crctl approve` TTY / 签名 grant | 不改 |
| durable transaction | `durable-tx.mjs`、`workspace-transactions.mjs` | 不改 |
| register/checkpoint/merge/writeback/archive | 现有 `crctl` 深命令 | 只删除调用方算法副本 |
| review canonical 字段 | CR-2026-039 已收敛的 `review-record` 合同 | 只清理残留，不改 schema |
| 结构化测试 | CR-2026-040 的 `crctl test --plan` | 只收缩重复说明 |
| baseline evidence/archive gate | CR-2026-041 的版本化脚本与 `crctl archive` | 只收缩重复说明 |
| Agent/Skill 权限 | `agent-skill-matrix.yml` | Agent 文档改为引用 |
| Pipeline 顺序/reviewLoop | `pipeline-templates/*.pipeline.json` | 除 reviewer 暂停节点外不改行为 |

## 2. 模块设计与依赖

### 2.1 Agent 文档

9 个 active Agent 文档统一收敛为以下最小结构，不新增模板生成器：

1. 角色定位；
2. 可处理意图与路由表；
3. 人工决策边界；
4. 权限事实源链接；
5. 禁止绕过 Skill / `crctl` 的一句约束。

Agent 文档不得包含：

- 三个及以上具体 CR 状态组成的状态链或状态表；
- “从 `_backlog.yml` 读取 status 决定下一步”的说明；
- worktree、commit、push、merge、CAS、journal 或账本字段写入算法；
- 完整 owns/can-call/forbidden 清单副本。

已知重点文件：

| 文件 | 当前问题 | 收敛方式 |
|---|---|---|
| `agents/requirement-writer.md` | 保存 drafting 到 requirement-approved 的流程和 backlog/status 写入描述 | 改为 requirement-authoring 路由 + `crctl next` |
| `agents/dev-agent.md` | 保存 architecture/coding 状态链和逐节点推进说明 | 改为两条 Pipeline 路由 + 评审/审批边界 |
| `agents/quality-reviewer-agent.md` | 保存状态到 review Skill 的映射表 | 只保留评审类型到 Skill 的职责路由 |
| `agents/delivery-agent.md` | 直接判断 code-approved/writeback 状态 | 改为由 feature-writeback 调用的角色说明 |
| 其余 active Agent | 存在落盘步骤、重复能力清单或过长交互脚本时 | 仅删除越界段，保留领域判断 |

`agents/_index.yml` 与 `agent-skill-matrix.yml` 不因文档缩短改变机器可读关系；只有发现当前 brief/reference 与实际删改冲突时才做定点同步。

### 2.2 Pipeline

8 个 active Pipeline 逐节点审计 prompt，统一保留以下字段语义：

```text
输入 -> 调用哪个 Skill/公开命令 -> 结构化结果分类 -> reviewLoop/失败动作
```

删除以下内容：

- journal、write-set、CAS、candidate、manifest、lease、逐仓 Git 和账本拼接算法；
- 直接写受控文件的指令；
- Skill 正文已经拥有的完整业务算法副本；
- 会漂移的内部字段、实现阶段和恢复步骤枚举。

节点的 `id`、`kind`、`ref`、`reviewLoop`、`onFail`、`timeoutMinutes` 除明确列出的 reviewer 节点删除外保持不变。

#### 2.2.1 code Pipeline 结构变更

当前 `code-implementation.pipeline.json`：

- inputs 为 `cr_id`、`target_version`、`auto_push_after_task`、`review_llm`；
- nodes 为 17 个；
- node `00000000-0000-0000-0015-000000000013` 是“选择代码评审 LLM”人工暂停；
- `workspace-freshness` 评审前节点为 `...0017`；
- `review-code` 节点为 `...0009`。

目标结构：

```text
inputs: cr_id, target_version, auto_push_after_task

... -> workspace-freshness(...0017)
    -> review-code(...0009)
    -> PASS 后 checkpoint(...0015)
    -> 代码人工审批(...0010)
    -> approve-code(...0011)
```

具体变更：

1. 删除 input `review_llm`；
2. 删除 human approval node `...0013`；
3. `...0017` 后直接进入 `...0009`；
4. `review-code` prompt 改为读取 runtime 当前实际 reviewer，并在临时 payload 的 `dimensions.reviewer-model` 中自报留痕；不新增 Pipeline input、状态字段或 reviewer registry；
5. review-code 的 `reviewLoop.replayNodes` 保持现状，因为当前列表本来就是 implement-code -> write-test-report -> checkpoint -> workspace-freshness -> review-code，不依赖 `...0013`；
6. `pipeline-templates/_index.yml` 的 code-implementation `nodes` 从 17 改为 16；
7. 旧调用方若仍传 `review_llm`，由调用方在进入 Pipeline 前完成 runner 选择；不保留隐藏兼容字段。

合法的需求、架构、开发启动、代码四个人工审批节点全部保留。

### 2.3 Skill

Skill 收缩遵循“业务 interface 保留，深模块 implementation 删除”。首轮已核实的修改对象：

| Skill | 保留 | 删除/收缩 |
|---|---|---|
| `write-requirement-prd` | PRD 输入、章节、frontmatter、回修语义、`backlog-set prd-path` | 失效的 engineering-docs、MCP/owClient、`change-requests/_config.yml`、validate-doc 依赖声明 |
| `write-tech-design` | PRD/ARCHITECTURE 读取、SDD 内容、状态前后置、回修 | 手工 commit 配方；ARCHITECTURE 缺失时的真实懒加载行为保留 |
| `write-dev-tasks` | TASK 内容和 `crctl task init`/状态语义 | 手工 `crctl git commit` 配方 |
| `review-code` | diff 与 canonical 测试证据质量判断、LLM verdict | 任何 lint/test/build 执行入口；reviewer 选择暂停依赖 |
| `write-test-report` | 验证范围选择、临时 plan、一次 `crctl test --plan`、分析区 | 机器区/traceability/review-loop 手写说明 |
| `requirement-register` | 业务参数、一次 `crctl register`、结果分类 | 三账本、journal、write-set、lease 等内部步骤复述 |
| `push-progress` | 一次 `crctl checkpoint`、公开 phase/result | 逐仓提交、lease publish、metadata commit 和 journal 算法复述 |
| `merge-feature-branch` | 一次 `crctl merge`、公开错误分类 | prepare/publish/finalize 内部算法展开 |
| 三个 writeback Skill | 业务参数、一次 `crctl writeback-apply`、公开结果分类 | generator/candidate/manifest/journal/Git 内部路径与步骤 |
| `cr-archive` | 一次 `crctl archive`、complete/cleanup-pending 结果 | 四账本 write-set、commit/push、cleanup 实现步骤 |

`inbox-emit`、`cr-dashboard` 中对 `_config.yml` 的 SLA 读取属于真实业务输入，不因 `write-requirement-prd` 的失效引用一并删除。

规划域的 `repair-instructions` / `fixed-blockers` 是非 CR product-planning 自有合同，本 CR 不将其错误套入 CR review canonical 清理；只在 README 重写时不复制节点级字段。

### 2.4 README 与 ARCHITECTURE

README 重写为短的人读入口，目标章节固定为：

1. Tools 定位；
2. 概念生命周期；
3. Owner 职责；
4. 8 条 Pipeline 入口；
5. 自动评审与人工审批；
6. checkpoint / merge / operational workspace / archive 人读区别；
7. 恢复与 `crctl status/next`；
8. 权威事实源链接。

README 不再维护节点表、完整状态转移、门禁表达式、账本字段、内部算法、完整错误矩阵、动态测试数量或默认值。

`ARCHITECTURE.md` 因 code Pipeline 结构发生变化，做一处定点更新：在 Pipeline 模块说明中声明 reviewer runner 由 Agent/runtime 在进入 Pipeline 前选择，Pipeline 不设置额外人工暂停节点。其余架构不变量不改。

OpenWiki 页面不手工改写。权威源修改后由现有 `openwiki-update.yml` 生成/刷新；实施验收扫描生成结果是否仍引用旧 reviewer 节点或废弃命令。

### 2.5 静态治理与 CI

#### 2.5.1 `lint-prompts.mjs`

CLI interface 不变。`walkFiles` 扩展为扫描：

- `skills/**/SKILL.md`；
- `pipeline-templates/*.pipeline.json`；
- `agents/*.md`；
- `README.md`。

现有规则直接复用：

- R1：受控文件手写；
- R2：裸 Git；
- R3：废弃 `cr-status-set`；
- R7：`advance` 参数与权威 trigger；
- R9：CR Skill 下一步映射副本。

新增少量确定性规则，不做自然语言分类：

- **R10 废弃公开 interface**：命中可执行形态的 `cr-init`、`crctl test --cmd/--cwd/--timeout`、Pipeline input `review_llm`；禁止性说明或历史说明只通过现有局部 `lint-prompts:ignore` 豁免。
- **R11 已退役 Skill active 引用**：在 Agent/Skill/Pipeline/README 中命中 `change-impact-analysis` 或 `feedback-writeback` 即阻断；历史 CR、CUSTOM TODO 和 Git 历史不在扫描范围。
- **R12 Agent/README 状态机副本**：从权威 transitions 同次加载得到具名状态集合；同一段出现三个及以上不同状态时阻断。Skill/Pipeline 因需要表达合法前后置状态不适用本规则。
- **R13 Agent backlog 状态推断**：Agent 同段同时出现 `_backlog.yml` 与 status/状态判断时阻断；只读产品上下文说明若不推断 CR 状态不命中。

所有文本先 CRLF -> LF。权威状态机解析继续复用 `loadAuthorityTransitions`，缺失、重复、截断或无法解析保持 `STATE_MACHINE_PARSE_FAILED` 硬失败。

#### 2.5.2 Pipeline 固定结构检查

保留 CI 中 Node 标准库的 JSON 检查，扩展当前 `JSON.parse` 步骤为固定断言：

- `id`、`triggerCommand`、`inputs[]`、`nodes[]` 存在；
- node id 唯一；
- Skill node 必须有 active `ref`；
- `reviewLoop.repairNodeId` 和 `replayNodes[].nodeId` 必须指向同 Pipeline 现存节点；
- 不解释 prompt，不模拟状态机，不执行 Pipeline。

code Pipeline 的 16 节点、`review_llm` 缺失和 `...0013` 缺失另由静态回归测试精确断言。

#### 2.5.3 Workflow 合并

- 保留 `.github/workflows/crctl-ci.yml`；
- 删除 `.github/workflows/check-skill-matrix.yml`；
- `check-skill-matrix.mjs` 与 `check-agents-contract.mjs` 仍由 `crctl-ci.yml` 调用；
- `openwiki-update.yml` 保留，因其不是治理 workflow；
- push/pull_request paths 增加 `README.md`、`AGENT-SKILL-MATRIX.md`，并明确覆盖 `agent-skill-matrix.yml`、`dir-graph.yaml`、`agents/**`、`skills/**`、`pipeline-templates/**`、`skills/shared/controlled-shell/rules.json` 和 workflow 自身；
- Ubuntu/Windows matrix 与现有测试命令保持不变。

## 3. 数据模型

本 CR 不修改任何持久化账本或业务 schema。

唯一结构变化是 Pipeline JSON：

```text
code-implementation.inputs:
  before: [cr_id, target_version, auto_push_after_task, review_llm]
  after : [cr_id, target_version, auto_push_after_task]

code-implementation.nodes:
  before: 17
  after : 16
```

以下均保持不变：

- `cr.md`、`_backlog.yml`、`_history.yml`、approval、review-loop、traceability；
- review annotation canonical 字段；
- test-report 机器区与分析区；
- writeback candidate/manifest/evidence；
- state machine、gates、reviewLoop passCondition。

## 4. 接口契约

### 4.1 Agent interface

输入：用户意图、工作区上下文、`crctl status/next` 或只读 Skill 结果。

输出：选中的 Pipeline/Skill、必要业务参数、是否需要人工决策。

失败：权限矩阵不允许、所需上下文缺失或 `crctl next` 返回人工节点时停止路由；不得自行写状态或账本。

### 4.2 Pipeline interface

输入：模板 `inputs[]` 和前序节点结构化输出。

输出：下一节点所需业务结果；review 节点输出 canonical verdict/blockers/suggestions/dimensions/repair-target。

失败：`onFail=abort|skip` 与 reviewLoop 负责中止/回修；不得在 prompt 内实现恢复算法。

### 4.3 Skill interface

输入：业务参数与 CR 产物。

输出：业务文档、临时判断 payload 或公开深原语结果摘要。

失败：透传/解释公开结构化错误；不得通过手改 authority 补偿。

### 4.4 `crctl` interface

本 CR 不新增、删除或修改 `crctl` 命令、参数、结果字段和错误码。调用方只依赖当前公开 interface，不依赖内部 transaction phase。

### 4.5 lint interface

```text
node skills/shared/crctl/scripts/lint-prompts.mjs --mode report|enforce [--root <dir>]
```

命令和退出语义不变；只增加扫描范围与规则编号。`enforce` 命中阻断项仍以 `LINT_DRIFT` 非零退出。

## 5. 关键流程

### 5.1 文本职责收敛

```text
读取权威文件与当前 active 文档
  -> 删除实现副本
  -> 保留业务 interface
  -> lint-prompts enforce
  -> matrix/agent contract
  -> Pipeline JSON 固定断言
```

不进行全仓机械改写；只有命中越界规则或本 SDD 文件映射表的文件才编辑。

### 5.2 reviewer 选择

```text
Agent/runtime 在 Pipeline 启动前选择评审 runner
  -> code Pipeline 正常执行到 review-code
  -> review-code 使用当前 runner
  -> dimensions.reviewer-model 记录实际事实
  -> reviewLoop / PASS checkpoint / 人工代码审批保持不变
```

runner 选择不是 CR 状态，不写账本，不新增 human approval。

### 5.3 CI

```text
相关路径变化
  -> crctl-ci（Ubuntu + Windows）
  -> lint-prompts
  -> check-skill-matrix
  -> check-agents-contract
  -> Pipeline JSON 固定断言
  -> crctl tests
  -> writeback tests
```

重复 workflow 删除后不减少任何检查项。

## 6. 技术选型与替代方案

| 方案 | 结论 | 原因 |
|---|---|---|
| 扩展现有 `lint-prompts.mjs` | 采用 | 已有 CLI、规则结构、CRLF 纪律和测试 fixture，改动最小 |
| 新建通用文档合同引擎 | 拒绝 | 会形成第二套 parser/registry，且需求只需少量确定性规则 |
| 新建 Pipeline 解释器 | 拒绝 | JSON.parse + 固定字段断言已足够，不需要执行语义 |
| 为 reviewer 建 registry/config/input | 拒绝 | runtime 已能选择模型；Pipeline 不应拥有 runner 选择暂停 |
| 修改 `crctl` 承担文档治理 | 拒绝 | `crctl` 不拥有 LLM 文本与业务设计判断 |
| 全量重写所有 Skill | 拒绝 | 只改命中越界的 Skill，避免无关 churn |
| 保留旧 `review_llm` 兼容字段 | 拒绝 | 字段无状态价值且会继续制造第二入口；调用方迁移到 runtime 选择 |
| 手工编辑 OpenWiki 生成页 | 拒绝 | 由既有 workflow 从权威源刷新 |

## 7. FR 到技术实现映射

| PRD FR | 技术实现 |
|---|---|
| FR-01 Agent 文档收敛 | §2.1；`agents/*.md` 定点缩短；R12/R13 防回潮 |
| FR-02 Pipeline prompt/reviewer | §2.2；code Pipeline 删除 input/node；节点数 17 -> 16；固定结构断言 |
| FR-03 Skill 收敛 | §2.3；CR write、review/test、register/checkpoint/merge/writeback/archive Skill 定点清理 |
| FR-04 README | §2.4；README 8 节人读入口；ARCHITECTURE 定点更新；OpenWiki workflow 刷新 |
| FR-05 静态治理/CI | §2.5；lint R10-R13；删除重复 workflow；补 paths 与双平台测试 |
| FR-06 已解决能力保护 | §1.3、§3、§4.4；零 crctl/state/gate/schema 生产改动 |

## 8. 安全、性能与兼容性

- **安全**：不扩大 shell/Git 权限，不修改 `rules.json#protectedPaths.deny`，不增加账本写入口。
- **一致性**：状态和账本仍只由 `crctl` 写；文档收缩不改变 authority。
- **性能**：lint 新增扫描仅覆盖少量 Markdown/JSON，复杂度为文件总字节线性扫描；无需缓存或并发。
- **跨平台**：所有新增文本读取先 CRLF -> LF；CI 在 Ubuntu/Windows 双跑。
- **兼容性**：唯一删除的外部输入是可选 `review_llm`；调用方必须在 Pipeline 前选择 runner，不提供兼容 shim。其余公开命令和 Pipeline 业务输入不变。
- **可审计性**：reviewer 实际身份继续写 `dimensions.reviewer-model`；删除暂停节点不删除评审证据。

## 9. 测试设计

### 9.1 `lint-prompts.test.mjs`

新增最小向量：

1. Agent/README 中受控文件手写与裸 Git 命中现有 R1/R2；
2. `cr-init`、旧 `crctl test` flags、`review_llm` 命中 R10；
3. 两个 retired Skill active 引用命中 R11；
4. Agent/README 同段三个状态命中 R12，两个状态不误报；
5. Agent 从 `_backlog.yml` 推断 status 命中 R13，只读产品上下文不误报；
6. 每条规则 LF/CRLF 结果一致；
7. `lint-prompts:ignore` 仍只覆盖所在行 ±1 行。

### 9.2 `crctl.test.mjs` 静态合同

追加 CR-2026-042 向量：

1. code Pipeline inputs 不含 `review_llm`；
2. node `...0013` 不存在，总节点数为 16；
3. `...0017` 后是 `...0009`；
4. review-code replayNodes 全部指向现存节点，且顺序不变；
5. `_index.yml` nodes=16；
6. `check-skill-matrix.yml` 不存在，`crctl-ci.yml` 仍调用两个 checker；
7. CI paths 覆盖 PRD FR-05.2；
8. README 必需章节/权威链接存在，禁止内容零命中；
9. 已知 Skill 越界文本零命中。

### 9.3 全量验证

```text
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
Pipeline JSON parse + fixed field assertions
```

全部命令在 Ubuntu/Windows CI 运行；不新增 npm 依赖。

## 10. 文件变更矩阵

| 路径 | 动作 |
|---|---|
| `agents/*.md` | 定点缩短 active Agent 文档 |
| `pipeline-templates/*.pipeline.json` | 收缩越界 prompt；code Pipeline 删除 reviewer input/node |
| `pipeline-templates/_index.yml` | code-implementation nodes 17 -> 16 |
| `skills/requirement/**/SKILL.md` | 清理 PRD 失效模板引用和 register 深算法复述 |
| `skills/develop/**/SKILL.md` | 清理 commit 配方、测试第二入口和 reviewer 暂停依赖 |
| `skills/writeback/**/SKILL.md` | 保留一次公开调用，删除内部算法复述 |
| `skills/sync/push-progress/SKILL.md` | 收缩 checkpoint 内部算法 |
| `skills/cr/cr-archive/SKILL.md` | 收缩 archive 内部算法 |
| `README.md` | 重写为人读总览与权威链接 |
| `ARCHITECTURE.md` | 定点记录 reviewer runner 选择边界 |
| `skills/shared/crctl/scripts/lint-prompts.mjs` | 扩扫描范围，新增 R10-R13 |
| `skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | 新规则正反例与 CRLF 测试 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | Pipeline/CI/README/Skill 静态合同测试 |
| `.github/workflows/crctl-ci.yml` | paths 与固定结构断言 |
| `.github/workflows/check-skill-matrix.yml` | 删除 |
| `openwiki/**` | 不手工编辑；由现有 workflow 刷新 |

不修改 multica 或 knowledge-base 业务代码；knowledge-base worktree 只新增本 CR SDD 与评审证据。

## 11. 风险与回滚

| 风险 | 控制 |
|---|---|
| 文本缩短删除真实业务判断 | 按“保留 interface、删除 implementation”逐文件评审；FR 映射和现有行为测试兜底 |
| lint 扩面误报 | 新规则限定文件类型/段落/字面形态，提供正反例和局部 ignore |
| reviewer 节点删除破坏 reviewLoop | node ID 顺序和 replayNodes 静态断言；现有 code pipeline 行为测试全量回归 |
| README 过薄 | 固定保留 Owner、入口、审批、恢复、四个关键概念和权威链接 |
| CI 合并减少检查 | 主 workflow 明确保留两个 checker 和全部测试；双平台矩阵不变 |
| OpenWiki 未同步 | 合并后由现有 workflow 刷新，并扫描旧 reviewer/命令引用 |

回滚按普通 Git commit 回滚文档/JSON/lint/workflow 变更即可；本 CR 不迁移数据、不改变状态机或账本，因此无数据回滚和兼容迁移步骤。

## 12. Prompt 采纳影响

本 CR 不修改 `skills/shared/crctl/scripts/crctl.mjs` dispatch，也不修改 `skills/shared/controlled-shell/rules.json#protectedPaths.deny`，因此不需要新增/扩展 crctl 子命令，也不存在“某 Skill 必须改用新命令”的采纳清单。

本 CR 的 Prompt 变化只是在现有公开 interface 上删除重复 implementation 文本，并删除 code Pipeline 的 reviewer 选择暂停。

## 13. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.1.0 | Ray | 初始设计：职责分层、code Pipeline 17->16、Skill/README 收敛、lint R10-R13、CI workflow 合并 |

## Tools 本地业务门禁、远端发布与人工审批确认方案（v0.20.5 · CR-2026-044）

## 1. 背景与约束

本设计承接 `CR-2026-044-prd`。当前 Tools 基线为 `8f530589a0ae395f44760f4965a225ea9ac698d6`，已核实：

- `buildReleaseSubjects` 会 fetch origin，并要求远端 requirement ref 精确等于本地 worktree HEAD。
- `verifyReleaseSubjects` 同时检查本地 source/artifact 与 remote-tracking requirement ref，并可能返回 `remote-ref-drift`。
- `mergeCr` 在逐仓 prepare 循环内才检查远端 source，因此前仓可已生成 candidate、后仓才暴露 publication lag。
- `workspace inspect` 当前只返回 `resources[]`，尚未返回 `resolveOperationalWorkspace` 的 authority path。
- requirement/architecture/code 三条 Pipeline 的审批后 checkpoint 完成合同不一致；architecture 仍有 `auto_push_after_sdd`，code 最终 checkpoint 仍为 `onFail=skip`。
- `cmdApprove` 的共享 TTY 判断当前只接受 `yes`。

### 1.1 不变量

1. 保持 release-subjects v1、approval、review annotation、checkpoint ledger、merge journal 与状态机 schema 不变。
2. 保持当前 15 个具名状态 + `(new)`、28 条声明转移、wildcard 展开 50 条。
3. `crctl` 继续只依赖 Node 标准库，Git 调用继续走 `gitRun/gitMust` 与 `shell:false`。
4. 所有摘要继续先做 CRLF 到 LF；逐行解析继续使用 `split(/\r?\n/)`，解析失败硬失败。
5. checkpoint、freshness/sync、merge、writeback、archive 的 lease、CAS、journal、远端确认与恢复语义不得削弱。
6. 本设计不新增状态、账本、公共 CLI、snapshot schema、事务层、版本化转换脚本或第三方依赖。

## 2. 设计原则与职责边界

### 2.1 Ponytail 选择顺序

实现选择固定为：复用现有能力 > Node 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码。首个足够方案即停止，不建设 verifier/publication registry、provider、adapter、缓存、daemon 或通用 Pipeline context 框架。

### 2.2 模块职责

| 模块 | 本次职责 | 明确禁止 |
|---|---|---|
| Agent | 选择 architecture/coding/writeback Pipeline，传递 CR-ID | 保存状态机、计算 SHA、写受控文件 |
| Pipeline | 固定节点顺序、传递 `operational_workspace`、声明 checkpoint 完成条件与失败中止 | 复制 Git/ref/journal 算法、手写账本 |
| Skill | 解释 local drift/publication lag、调用现有深原语、输出恢复入口 | 自行 fetch、计算 ancestry、实现事务或直接写账本 |
| `crctl` | 本地证据校验、publication preflight、状态/门禁/CAS/账本/审计/原子提交 | 需求价值判断、LLM 评审结论 |
| 版本化脚本 | 保持现有 PRD/SDD/TASK/traceability 确定性转换 | 状态推进、审批、publication 判定 |
| README | 说明事实边界、节点完成条件与 recoverCommand | 复制 verifier、checkpoint 或 merge 算法 |

## 3. 已有基础设施与最小改造

### 3.1 已有基础设施

| 能力 | 现有入口 | 复用方式 |
|---|---|---|
| Repo/worktree 解析 | `resolveRepositories` | active repo、trunk、KB id 与 worktree 路径唯一来源 |
| 本地 workspace 分类 | `classifyRepoWorkspace(ctx, repo, cr)` | build/verify 每仓先要求 `classification=healthy` |
| Phase authority | `resolveOperationalWorkspace(ctx, cr)` | `workspace inspect` 直接暴露其 `path`，不建新 resolver |
| release snapshot | `buildReleaseSubjects` / `verifyReleaseSubjects` / v1 renderer | 保留签名与 schema，只移除远端依赖 |
| checkpoint | `checkpointCr` | requirement ref 发布与跨环境交接唯一入口 |
| merge saga | `mergeCr` + `prepareMergeTree` + `classifyRemoteCommit` | preflight 后继续原 prepare/publish/rebuild/finalize |
| Durable transaction | `loadOrCreateJournal`、lock、write-set、fault recovery | 不新增 payload 字段或第二事务层 |
| Freshness | `classifyWorkspaceFreshness` / `syncWorkspaceToTrunk` | 保持远端 trunk 预检职责和既有节点位置 |
| 审批 | `cmdApprove` / `approveAndAdvance` | 只改共享 affirmative 判断与 prompt |
| 测试 fixture | `crctl.test.mjs`、`merge-tx.test.mjs`、`checkpoint-tx.test.mjs`、`pipeline-structure.test.mjs` | 扩现有 fixture，不建新框架 |

### 3.2 最小改造

1. 在 `workspace-transactions.mjs` 内收窄 build/verify 的事实来源，并在现有 `mergeCr` 内增加一次全仓 publication preflight。
2. 在 `crctl.mjs#cmdWorkspace` 的 inspect 返回中复用 `resolveOperationalWorkspace` 增加 `operationalWorkspace`；不改变 `ensureWorkspace` 的接口。
3. 在 `crctl.mjs#cmdApprove` 一处把 affirmative 判断改为 `['y', 'yes'].includes(...)`。
4. 调整三条现有 Pipeline 的 workspace 传递与审批后 checkpoint；同步 `_index.yml`。
5. 更新直接消费这些合同的既有 Skill 和人读文档。

## 4. 架构与数据流

### 4.1 本地评审与审批路径

```text
review-record --stage code
  -> resolveRepositories
  -> buildReleaseSubjects
      -> classifyRepoWorkspace(each active repo) == healthy
      -> local worktree HEAD
      -> local controlled artifact digest
      -> release-subjects v1
  -> review-annotations/code.yml

approve --stage code
  -> verifyReleaseSubjects
      -> local classifier + HEAD + artifact only
  -> approval.yml#code.release-subjects
  -> approval + status existing atomic commit
```

该路径不 fetch、不读取 remote-tracking ref，不判断 origin 是否存在。

### 4.2 Checkpoint 与 merge 发布路径

```text
checkpoint
  -> existing source commit / lease publish / KB metadata / remote confirmation

merge
  -> local signed snapshot verification
  -> publication preflight for all active repos
      -> fetch origin
      -> freeze localHead / remoteSourceSha / trunkSha in memory
      -> all remoteSourceSha == localHead
  -> existing prepare / publish / rebuild / finalize saga
```

publication preflight 失败只表示未发布，状态保持 `code-approved`；本地 verifier 失败才按既有 drift kind 回修或阻断。

### 4.3 Pipeline workspace 传递

```text
requirement: register.knowledgeBaseWorktree -> operational_workspace
architecture/code entry:
  crctl workspace inspect CR-ID
    -> resolveOperationalWorkspace.path
    -> operationalWorkspace
subsequent nodes:
  pass same operational_workspace unchanged
```

完整 repo map 仍只由每次 `crctl` 深原语内部的 `resolveRepositories` 解析。

## 5. 数据模型

### 5.1 持久化模型

无新增持久化模型。以下结构保持不变：

- release-subjects v1；
- approval.yml 各 section；
- review annotation；
- latest-checkpoint；
- merge journal `payload.repos[]` 的 `baseSha/sourceSha/mergeSha/pushed/confirmed`；
- 状态机与 gates。

### 5.2 仅内存 publication facts

`mergeCr` 新事务在首次 prepare 前构造局部数组，不写入 journal：

```js
publicationFacts = [{
  repo,             // repo.id
  localHead,        // 当前本地 CR worktree HEAD
  remoteSourceSha,  // fetch 后 origin/requirement/{CR-ID}
  trunkSha,         // fetch 后 origin/{trunk}
}]
```

约束：

1. 按 `ctx.repositories` 稳定顺序收集。
2. 任一事实不可读时立即硬失败。
3. 数组全部验证通过后才进入首次 prepare。
4. 首次 prepare 将 `remoteSourceSha` 复制到既有 `payload.repos[].sourceSha`；之后恢复只使用 journal 已持久化的 `sourceSha`，不新增 publication 字段。

## 6. 接口契约

### 6.1 `buildReleaseSubjects(ctx, cr)`

输入和 v1 输出不变。

逐仓算法：

1. `info = classifyRepoWorkspace(ctx, repo, cr)`。
2. `info.classification !== 'healthy'` 时抛结构化 `RELEASE_WORKSPACE_INVALID`，附 `repo/classification/worktreePath/branch/dirty`；不得降级为空仓或跳过。
3. 从 `info.worktreePath` 执行 `rev-parse HEAD` 得到 `reviewedSourceSha`。
4. `remoteRef` 继续渲染 `refs/heads/requirement/{CR-ID}`。
5. 不执行 remote get-url、fetch 或 remote ref 验证。
6. artifact 收集与 canonical digest 保持现有实现。

### 6.2 `verifyReleaseSubjects(ctx, cr, snapshot)`

返回合同继续为 `{ok:true}` 或 `{ok:false, kind:'code'|'task'|'prd'|'sdd', details}`。

校验顺序（失败 kind 优先级服从 PRD §7：受控 artifact 漂移先给精确 kind，不被 kind=code 覆盖）：

1. snapshot v1 形状与 active repo 集合。
2. 受控 artifact 逐文件哈希、集合与 digest（prd/sdd/task 精确 kind，含未提交篡改；PRD/SDD 漂移无条件硬阻断）。
3. 每仓 `classifyRepoWorkspace(...).classification === 'healthy'`；非 healthy 返回 kind=code（workspace-invalid）。
4. non-KB：当前 HEAD 精确等于 reviewed SHA。
5. KB：reviewed SHA 是当前 HEAD 祖先；区间变更只允许：
   - `change-requests/{CR-ID}/approval.yml`
   - `change-requests/{CR-ID}/cr.md`
   - `change-requests/{CR-ID}/traceability.yml`
   - `change-requests/{CR-ID}/review-loop.yml`
   - `change-requests/_backlog.yml`
   - `change-requests/{CR-ID}/review-annotations/` 前缀
删除 remote get-url、remote ref 读取与 `remote-ref-drift` 返回分支。白名单保留为现有函数内局部 `Set` + prefix，不抽配置或 helper。

### 6.3 `mergeCr(ctx, input)`

公开输入输出不变。

#### 所有 merge 调用的共同前置

无论 `payload.repos` 是否为空，每次调用都必须先：

1. 读取 `approval.yml#code.release-subjects` 并执行纯本地 `verifyReleaseSubjects`。
2. PRD/SDD drift 始终返回 `APPROVED_ARTIFACT_DRIFT`。
3. code/TASK drift 且 `payload.repos` 中尚无 pushed 仓时返回既有 `release-drift`；已有任一 pushed 仓时返回 `RELEASE_SUBJECT_DRIFT` 并保持 blocked。
4. 只有本地 verifier 通过后，才进入下述 publication preflight 或 journal 续跑分支。

此共同前置保证已有 prepared/published journal 的续跑同样受本地 signed snapshot 约束；publication preflight 的有无不改变本地证据门禁。

#### 新事务 / 零 prepare journal

当 `payload.repos.length === 0` 时才执行 publication preflight。函数内构造两个不同的恢复命令：

```js
const mergeRecoverCommand = `crctl merge ${cr} --workspace ${JSON.stringify(input.workspace || ctx.installRoot)}`;
const checkpointRecoverCommand = `crctl checkpoint ${cr} --workspace ${JSON.stringify(ctx.installRoot)}`;
```

随后：

1. 对全部 active repo fetch origin，读取本地 CR worktree HEAD、remote requirement source 和 trunk SHA。
2. source ref 缺失：抛 `MERGE_SOURCE_MISSING`，payload 附 `repo/ref/recoverCommand: checkpointRecoverCommand`。
3. `remoteSourceSha !== localHead`：抛 `RELEASE_REMOTE_NOT_PUSHED`，payload 附 `repo/head/remote/recoverCommand: checkpointRecoverCommand`。
4. 任一失败时 `payload.repos` 保持空，不调用 `prepareMergeTree` 或 `commit-tree`。
5. 全仓通过后，用同一批 facts 逐仓首次 prepare；`sourceSha=remoteSourceSha`，`baseSha=trunkSha`。

`mergeRecoverCommand` 继续只用于 prepare/publish/finalize、journal 或 lease 等 merge saga 技术失败；publication lag 不得返回它。

#### 已有 prepare/publish journal

当 `payload.repos.length > 0` 且共同本地 verifier 已通过时，按既有 journal 恢复合同继续：

- 不清空或重建既有事务事实；
- 已 pushed/confirmed 仓不重做 prepare；
- trunk 前进仍走现有 rebuild；
- rebuild 使用 `rec.sourceSha` 作为冻结 source，不重新采纳移动的 requirement ref；
- journal 声称已发布但远端事实不符仍按既有 history-rewritten 硬阻断；
- 任一 trunk publish 后的本地 signed snapshot drift 保持 blocked。

#### 错误到状态的映射

| 结果 | 状态动作 | 恢复 |
|---|---|---|
| local code/TASK drift，零 publish | 既有 `release-drift` 回退 developing | 重建测试/评审/审批 |
| PRD/SDD drift | 保持并硬阻断 | 回上游审批链 |
| remote source missing/stale | 保持 `code-approved` | checkpoint 后重跑 merge |
| remote advanced/diverged/history-rewritten | 保持当前状态 | 由 checkpoint 既有分类给出 pull/manual |
| 任一 publish 后 source drift | 保持 blocked | 恢复原 ref 后续跑原事务；新改动拆新 CR |

### 6.4 `workspace inspect`

`ensureWorkspace(ctx, {mode:'inspect'})` 继续返回 `{resources, changed:false}`，不修改 lib 合同。`cmdWorkspace` 在 `sub==='inspect'` 时额外调用：

```js
const authority = resolveOperationalWorkspace(ctx, cr);
return ok({
  op: 'workspace-inspect',
  cr,
  mode: 'inspect',
  ...result,
  operationalWorkspace: authority.path,
});
```

resolver 抛出的 missing/inconsistent 错误转为 `operationalWorkspace: null` + `operationalWorkspaceError: {code, message}` 结构化字段（inspect 本身保持只读诊断，不命令级失败）；调用方（Pipeline 入口）见 null/非 healthy 必须中止并指向 resume，不 fallback 到 `resources[]`、主 checkout 或目录猜测。

### 6.5 `cmdApprove`

仅修改共享 TTY prompt 和一行判断：

```js
rl.question(`以 approver=${approver} 批准该阶段？只有输入 y 或 yes 才会写入 approval.yml [y/N] `, async (answer) => {
  if (!['y', 'yes'].includes(answer.trim().toLowerCase())) {
    // existing reject rollback
  }
});
```

不新增 helper。TTY 检查、passCondition、evidence digest、reject rollback、grant、resign 和 `approveAndAdvance` 调用位置不变。

## 7. Pipeline 与 Skill 设计

### 7.1 requirement-authoring

- 保留 PRD 草稿 checkpoint 及 `auto_push_after_prd` 可选输入。
- 在 `approve-requirement` 后新增一个强制 `push-progress` 节点，message=`需求审批结果`，`onFail=abort`。
- 节点总数 6 -> 7，并同步 `_index.yml`。
- 阶段终点 checkpoint 失败保持 `requirement-approved`；重跑同一 checkpoint，不重新审批。

### 7.2 architecture-design

- 首节点先调用 `workspace inspect`，要求所有 `resources[].classification=healthy`，再消费 `operationalWorkspace` 并传给后续节点；任一资源非 healthy 时中止并指向 resume，不自动 ensure。
- 删除 `auto_push_after_sdd` 输入和 skip 分支。
- 保留现有审批后 `push-progress` 节点，改为无条件执行且 `onFail=abort`。
- 节点总数仍为 5。

### 7.3 code-implementation

- 首节点先调用 `workspace inspect`，要求所有 `resources[].classification=healthy`，再消费并传递 `operationalWorkspace`；任一资源非 healthy 时中止并指向 resume，后续文档节点不从目录命名猜路径。
- TASK checkpoint 保持可选。
- 代码/测试统一 checkpoint、评审 PASS 后审批前 checkpoint 保持强制。
- 审批后 checkpoint 的 `onFail` 从 `skip` 改为 `abort`。
- freshness 两个节点的位置和算法不变。
- 节点总数维持 trunk 基线 16（CR-2026-042 已删除评审 LLM 选择节点 17→16；本 CR 只改审批后 checkpoint `onFail`，不增删节点）。

### 7.4 Skill 文本

只更新直接消费者：

- `review-code`：snapshot 来自 healthy committed 本地 worktree，不要求远端已同步。
- 四个 `approve-*`：TTY 提示接受 `y|yes`，不自行读 stdin；checkpoint 不进入审批事务。
- `crctl` Skill：同步 local evidence/publication boundary 与 inspect 输出。
- `push-progress`：按 Pipeline 位置区分可选草稿和强制阶段交接。
- `workspace-freshness`：明确只负责 origin trunk 新鲜度，失败零业务状态副作用。
- `merge-feature-branch`：publication lag 保持 `code-approved` 并指向 checkpoint。

## 8. FR 到技术实现映射

| PRD FR | 技术落点 | 验证 |
|---|---|---|
| FR-01 | build/verify 移除 remote；Pipeline 传 operational workspace | 离线与静态调用测试 |
| FR-02 | `buildReleaseSubjects` + classifier | healthy/dirty/missing 测试 |
| FR-03 | `verifyReleaseSubjects` + 精确 KB 白名单 | HEAD/artifact/白名单参数化测试 |
| FR-04 | `approveAndAdvance(code)` 保持接口，消费本地 verifier | remote stale approve 测试 |
| FR-05 | `mergeCr` 零 prepare preflight + 既有 saga | remote missing/stale、checkpoint 后重跑、partial publish 测试 |
| FR-06 | `cmdWorkspace inspect` 暴露 authority path；Pipeline 原样传递 | resolver 与结构测试 |
| FR-07 | 三条 Pipeline 审批后 checkpoint | pipeline structure 测试 |
| FR-08 | freshness 实现不改，只更新职责文本与回归 | freshness 零状态副作用回归 |
| FR-09 | `cmdApprove` 一行判断与 prompt | 四 stage TTY 参数化测试 |
| FR-10 | 既有文件内最小修改；契约 lint | prompt/matrix/pipeline lint |
| FR-11 | `upgrade-check` 只读；在途状态说明与 journal 版本边界 | 兼容矩阵测试/文档断言 |

FR 覆盖率：11/11。

## 9. 安全、性能与一致性

### 9.1 安全

- local verifier 对非 healthy workspace fail closed。
- publication preflight 全仓通过前不产生 candidate。
- remote lag 不写 review/approval/traceability，也不触发业务回退。
- TTY 扩展不改变非 TTY 硬拒、grant 验签与 reject 权威回退。
- 不接受调用方任意 repo、path、ref、SHA 或 refspec。

### 9.2 性能

- status/gate/review/approve 删除 fetch，减少网络调用。
- merge 仍每仓一次必要 fetch；preflight 读取结果直接供首次 prepare 使用，不做第二轮 source fetch。
- 不增加缓存、watcher、后台任务或 commit count 计算。

### 9.3 一致性

- 本地 snapshot 绑定 worktree HEAD 与 artifact digest。
- publication preflight 绑定当前 local HEAD 与 remote source exact equality。
- 首次 prepare 后 source SHA 进入既有 journal，恢复不采纳移动 ref。
- repository graph digest、lease 与 journal 约束保持现有实现。

## 10. 测试设计

只扩现有测试文件。

### 10.1 `crctl.test.mjs`

1. origin 不存在/不可达时，healthy committed worktree 可 build snapshot。
2. dirty/wrong-branch/missing/path-unregistered 零 snapshot 失败。
3. remote requirement stale 但 local 未漂移时 verifier 与 approve-code 通过。
4. non-KB HEAD 漂移失败。
5. KB 白名单六类逐项通过，白名单外路径逐项失败。
6. plan/TASK/_index 集合或 digest 漂移失败；CRLF/LF 等价。
7. `workspace inspect` 返回 resolver 的 `operationalWorkspace`，missing/inconsistent 不猜路径。
8. 四个 stage 参数化验证 `y/Y/yes/YES/YeS` 与空白输入批准。
9. 空输入、no/其他输入继续 reject 回退；非 TTY、grant、resign 回归不变。

### 10.2 `merge-tx.test.mjs`

1. 任一 repo remote source missing：全仓 `payload.repos=[]`、无 candidate、状态 `code-approved`。
2. 任一 repo remote source stale：同上，错误为 `RELEASE_REMOTE_NOT_PUSHED`；两类 publication lag 的 `recoverCommand` 均精确等于 checkpoint 命令，不得等于 merge 命令。
3. checkpoint 后重跑进入 prepare/publish/finalize。
4. 本地 code/TASK drift 零 publish 仍 release-drift；PRD/SDD 漂移硬阻断。
5. 已有 prepared journal 续跑前仍执行本地 verifier；零 publish drift 回退，已有 publish drift 保持 blocked。
6. 已有 prepare/publish journal 按原合同恢复；trunk rebuild 使用冻结 `sourceSha`。
7. merge saga 自身的 prepare/publish/finalize/lease 故障继续返回 merge recoverCommand。

### 10.3 `checkpoint-tx.test.mjs`

保持并重跑 remote advanced/diverged/history-rewritten、lease、metadata commit 与幂等恢复测试；merge 不复制这些分类。

### 10.4 `pipeline-structure.test.mjs`

1. requirement 审批后强制 checkpoint，节点数 7；草稿 checkpoint 仍可选。
2. architecture 无 `auto_push_after_sdd`，审批后 checkpoint `onFail=abort`，节点数 5。
3. code 审批后 checkpoint `onFail=abort`，TASK checkpoint 仍可选，节点数维持 trunk 基线 16（CR-2026-042 已删评审 LLM 选择节点）。
4. architecture/code 首节点要求全部 `resources[].classification=healthy`，取得并后续传递 `operationalWorkspace`；非 healthy 时 abort 并指向 resume。
5. Pipeline 不含 fetch、SHA、Git、CAS、journal 算法文本。

### 10.5 回归命令

```text
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
node --test skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs
node --test skills/shared/crctl/scripts/test/merge-tx.test.mjs
node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs
node --test skills/shared/crctl/scripts/test/archive-tx.test.mjs
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs
```

## 11. 兼容、启用与回滚

1. release-subjects v1 与账本 schema 不迁移。
2. `developing` 及更早 CR 直接采用新本地 verifier。
3. `code-reviewing` 重跑 review-code 生成当前本地 snapshot。
4. `code-approved` 且 snapshot 与本地一致时，先 checkpoint 再 merge，不重新审批。
5. 已有 candidate 或 trunk publish 的 merge 事务使用启动版本按原 journal 完成；不跨版本切换。
6. 启用前复用现有 `upgrade-check` 只读确认，无新 CLI。
7. TTY 变更可独立回滚；Pipeline/Skill/README 可独立回滚且无数据迁移。
8. local verifier/merge 分类回滚会恢复旧远端依赖，但不会产生 schema 不兼容。

## 12. Prompt 采纳影响

本 CR 不新增 crctl dispatch 分支，也不修改 `rules.json#protectedPaths.deny`，因此不触发强制的“新增命令采纳”场景。但既有命令合同发生收敛，以下 Skill 必须同步：

| Skill | 当前描述 | 应改为 |
|---|---|---|
| `skills/develop/review-code/SKILL.md` | code snapshot 依赖已推送 source | healthy committed 本地 source；发布由 checkpoint/merge 处理 |
| 四个 `approve-*` | TTY 仅 `yes` 或未统一说明 | 共享入口接受 `y|yes`，Skill 不解析 stdin |
| `skills/shared/crctl/SKILL.md` | verifier 混合本地/远端 | 本地证据与 publication 边界分离；inspect 返回 authority path |
| `skills/sync/push-progress/SKILL.md` | checkpoint 普遍可选 | 草稿可选、阶段终点强制，取决于 Pipeline 位置 |
| `skills/sync/workspace-freshness/SKILL.md` | 易被理解为通用 gate | 仅远端 trunk 新鲜度预检，失败零业务证据变化 |
| `skills/writeback/merge-feature-branch/SKILL.md` | remote drift 可进入 release drift | publication lag 保持状态并指向 checkpoint |

## 13. 技术选型与替代方案

| 方案 | 结论 | 原因 |
|---|---|---|
| release-subjects v2 增加 published SHA | 否决 | 本地与发布事实可由现有 snapshot + checkpoint/merge 分层表达，无需迁移 schema |
| 新 publication registry/账本 | 否决 | checkpoint 与 merge journal 已拥有发布事实 |
| approve 内原子 push | 否决 | 把网络事务并入人工审批，扩大失败与恢复边界 |
| merge 自动 checkpoint | 否决 | 隐藏发布动作并复制 checkpoint 分类 |
| 为 affirmative 新建 helper/依赖 | 否决 | 一行数组 includes 足够 |
| 修改 `ensureWorkspace` 返回 authority | 否决 | inspect 命令层复用 resolver 即可，避免污染 workspace 生命周期接口 |

## 14. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.2.0 | Ray | 回修 B-01/B-02：本地 verifier 提升为所有 merge 调用共同前置；区分 checkpoint 与 merge recoverCommand；补充非 healthy workspace 入口阻断 |
| 2026-08-16 | v0.1.0 | Ray | 初始设计：本地 release verifier、merge publication preflight、Operational Workspace 连续性、阶段终点 checkpoint 与共享 TTY `y|yes` |

## Runner Core：architecture-design 自动调度纵切（v0.20.6 · CR-2026-045）

## 1. 架构概览

### 1.1 目标

本设计只实现 `architecture-design` 五节点纵切，不实现通用工作流引擎：

```text
write-tech-design
→ review-tech-design / write-tech-design 回修
→ human_approval
→ approve-tech-design
→ push-progress
```

核心方案是一个幂等 `Reconcile(run)`：启动、CR/review 投影、Agent task terminal、grant ACK 和进程启动恢复都只唤醒同一 reconcile。reconcile 读取固定生成 registry、现有 run/node/task/CR 投影和审批记录，最多执行一个确定的下一动作；所有业务状态与 Git 副作用仍由 Agent 执行对应 Skill，再由 Skill 调用 `crctl`。

```text
路由 Agent（选择 architecture-design）
  → StartArchitecture API
  → Runner.Reconcile
  → 现有 TaskService / agent_task_queue
  → Agent 执行固定 Pipeline prompt + 已绑定 Skill
  → Skill 调用 crctl
  → daemon 上报 CR/review/checkpoint 事件
  → 现有 projector + Runner.Reconcile
  → human_approval 时暂停
  → 网页审批 → signed grant → daemon ACK
  → approve-tech-design task → crctl approve --grant
  → push-progress task → crctl checkpoint
```

### 1.2 Ponytail 决策

| 需求 | 采用 | 不采用 |
|---|---|---|
| 运行状态 | 现有 `pipeline_run` / `pipeline_node_run` | 新 run/幂等/恢复表 |
| 并发唯一性 | PostgreSQL partial unique indexes | 新 lease/WAL/分布式锁 |
| Pipeline 合同 | tools JSON 的生成快照 | server 自建 DSL/运行时读取任意模板 |
| digest | 现有 `execution_context` JSONB | 模板版本表/对象存储 |
| 任务执行 | 现有 TaskService、claim/start/complete/fail | 第二任务队列 |
| 唤醒 | 现有 event bus + grant ACK 直接唤醒 + 启动扫描 | 新消息总线/轮询系统 |
| 状态/Git | Skill → `crctl` | Runner 直接写 CR/Git |
| 前端 | 现有 CR gate UI | Runner 控制台 |

### 1.3 模块职责

| 模块 | 本 CR 中拥有 | 明确不拥有 |
|---|---|---|
| Agent | 选择 `architecture-design`；以 task-token 身份启动 run；执行 Skill | 状态机、Git、受控账本 |
| Pipeline | 五节点顺序、prompt、`reviewLoop.replayNodes`、abort | Skill 算法、运行事务 |
| Skill | 业务判断、文档编写/评审、调用 `crctl` | run 调度、账本算法 |
| `crctl` | 状态、门禁、attempt、approval、checkpoint、Git | Pipeline 选择、Agent task |
| 版本化脚本 | 从 tools 权威合同生成 canonical registry | 状态推进、人工审批 |
| Multica Runner | run/node 生命周期、幂等调度、等待和失败 | CR 业务状态、Git、签名、自然语言判断 |
| README | 启动/等待/恢复的人读入口 | registry、SQL、状态机副本 |

## 2. 已经解决的基础设施

| 已有能力 | 权威位置 | 直接复用方式 |
|---|---|---|
| architecture Pipeline 五节点 | `tools/pipeline-templates/architecture-design.pipeline.json` | 生成固定 Core registry |
| Skill owner/can-call | `tools/agent-skill-matrix.yml` | 生成时校验 logical owner 和 pipeline owner 权限 |
| Agent/Skill 定义 | `tools/agents/_index.yml`、`tools/skills/_index.yml` | 校验 active 状态，不在 server 复制台账 |
| 状态、门禁、review attempt | `crctl` + gates/Pipeline | Runner 只消费投影结果 |
| run/node 表 | Multica migration 162 | 原表复用；只增加正确性索引 |
| CR/review/approval projector | `internal/governance/gate_projection.go` | 与 Runner 更新同一逻辑 run |
| Agent task 生命周期 | `internal/service/task.go` | 新增一种窄 task context，不复制 claim/runtime/retry |
| 任务归因列 | `agent_task_queue.cr_id/pipeline_node_run_id` | 入队时直接关联，不再依赖 StartTask 后置猜测 |
| in-process event bus | `internal/events/bus.go` | 订阅既有 task terminal 和 `cr:updated` |
| 网页审批与 grant | `internal/governance/approval.go` | ACK 后直接唤醒 Runner；Runner 不签名/验签 |
| daemon task-token | Auth middleware 的 `mat_` 绑定 | Start API 只接受受信 `X-Agent-ID/X-Task-ID` |
| daemon CR roots | `MULTICA_CR_WORKSPACES` | pipeline task 在本机唯一解析对应 CR root |
| checkpoint | `push-progress` → `crctl checkpoint` | 只认 checkpoint 事件完成，不重建发布算法 |
| CR gate UI | `CrGateCard` / gates API | 无新前端 |

## 3. 本次应复用的最小改造

### 3.1 tools 合同

修改 `architecture-design.pipeline.json`：

1. 在 `review-tech-design.reviewLoop` 增加既有 schema：

```json
{
  "replayPolicy": "rerun-listed-nodes-in-order",
  "replayNodes": [
    {
      "nodeId": "00000000-0000-0000-0016-000000000001",
      "ref": "write-tech-design",
      "purpose": "repair-sdd"
    },
    {
      "nodeId": "00000000-0000-0000-0016-000000000002",
      "ref": "review-tech-design",
      "purpose": "rerun-current-review"
    }
  ]
}
```

2. 保留 5 个节点和所有 `onFail=abort`。
3. `review-tech-design`、`approve-tech-design`、`push-progress` 不再依赖某个本地 `node-1.md` 文件；每个任务只消费 `cr_id`，并通过现有 `crctl workspace inspect` 取得本机 operational workspace。这样服务重启或独立 Agent task 不需要新建节点输出文件协议。
4. requirement/code/writeback Pipeline 不变。

新增 `pipeline-templates/emit-registry.mjs`，使用 tools 已有 `yaml-subset.mjs` 读取 matrix/index，输出 canonical JSON：

```json
{
  "schema": "ai-first.pipeline-registry/architecture-core-v1",
  "pipeline": { "...": "architecture-design.pipeline.json 的 Core 字段" },
  "pipelineOwner": "dev-agent",
  "nodePermissions": [
    { "ref": "write-tech-design", "owner": "dev-agent", "pipelineOwnerCanCall": true }
  ]
}
```

该脚本只做确定性转换与硬校验：CRLF→LF、Pipeline active、Skill active、每个 Skill 恰有一个 owner、pipeline owner 对每个 Skill 有 `owns` 或 `can-call`。prompt 渲染只允许 `{{inputs.cr_id}}` 与 `{{inputs.tech_context}}` 两个字面 token，使用 `String.replaceAll`，`tech_context` 作为有长度上限的数据块附加；生成后仍有 `{{`/`}}` 即硬失败，不实现表达式解释器。失败非零退出，不输出空 registry。

### 3.2 单一生成 registry

扩展现有 `generate-gate-nodes.mjs`，调用 tools 的 `emit-registry.mjs --pipeline architecture-design`：

- 继续刷新 `ApprovalGateNodes` / `ReviewGateNodes`，修正旧 `0014` UUID 为当前 `0016`。
- 在同一个 `gate_nodes_gen.go` 中新增 `ArchitectureCoreRegistryJSON` 与其 canonical SHA-256。
- build/runtime 不读取 tools checkout；Multica 只消费已提交生成物。
- `--check` 忽略 source SHA 注释差异，但必须比较节点、prompt、permissions、replayLoop 和 digest。

不创建第二个 registry 生成器或运行时模板 loader。

### 3.3 数据库正确性约束

不新增表、列或外键。使用两个单语句 migration，均按仓库规则 `CONCURRENTLY`：

```sql
CREATE UNIQUE INDEX CONCURRENTLY ...
ON pipeline_run (workspace_id, pipeline_id, cr_id)
WHERE cr_id IS NOT NULL AND status IN ('running', 'waiting_approval');
```

```sql
CREATE UNIQUE INDEX CONCURRENTLY ...
ON agent_task_queue (pipeline_node_run_id)
WHERE pipeline_node_run_id IS NOT NULL
  AND status IN ('queued', 'deferred', 'dispatched', 'waiting_local_directory', 'running');
```

第一条保证 Runner start 与 projector find/create 竞态最多产生一个非终态 run；第二条保证同一 node attempt 最多一个有效任务，并允许既有 retry 在父任务终态后创建子任务。

`pipeline_node_run` 已有 `UNIQUE(run_id,node_id,attempt)`，直接复用。

### 3.4 Runner reconcile

新增 `internal/governance/runner.go`，只支持 compiled `architecture-design`。

#### Start

固定 endpoint：

```http
POST /api/workspaces/{workspaceID}/pipeline-runs
{
  "pipeline_id": "architecture-design",
  "cr_id": "CR-YYYY-NNN",
  "inputs": { "tech_context": "optional" }
}
```

约束：

- 只接受 `X-Actor-Source=task_token`；`X-Agent-ID/X-Task-ID/X-Workspace-ID` 由现有 Auth middleware 盖写。
- CR 投影必须为 `requirement-approved` 且 `needs_reconcile=false`。
- source task、executor Agent 和 CR 必须属于同一 workspace。
- executor Agent 必须 active、runtime-bound，并启用 registry 中所有 Skill ref。
- registry 的 `pipelineOwner=dev-agent` 必须对每个节点拥有 `owns|can-call` 权限；节点 logical owner 单独写入 detail，用于审计，不拿 logical actor 字符串猜 Agent UUID。

run 输入：

```json
{
  "inputs": { "cr_id": "...", "tech_context": "..." },
  "execution_context": {
    "runner": "architecture-core/v1",
    "template_digest": "sha256:...",
    "pipeline_owner": "dev-agent",
    "executor_agent_id": "uuid",
    "source_task_id": "uuid"
  }
}
```

`started_by` 使用 task-token 已绑定的 `X-User-ID`。INSERT 依赖 partial unique index；唯一冲突后重读同一 run，不重试生成第二条。

#### Reconcile

入口：`Reconcile(ctx, workspaceID, crID)`。步骤固定：

1. 读取该 CR 的唯一非终态 architecture run；无 run 则返回。
2. 对比 compiled digest 与 `execution_context.template_digest`；不同则将 run failed，错误 `TEMPLATE_DIGEST_MISMATCH`。
3. `SELECT ... FOR UPDATE` 当前 run，重读 CR、node、task、review、approval、checkpoint 投影。
4. 根据 §5 后置条件矩阵确定当前节点。
5. 若当前节点 task 尚在 active 状态，返回。
6. 若 task terminal 但权威后置条件尚未到，保持 node running，在 `detail.wait_reason=authority_postcondition` 后返回。
7. 若节点满足双重成功条件，mark passed 并创建/唤醒下一个节点。
8. task 最终失败且无 active retry 时，node/run failed。
9. 每次调用最多入队一个新 task；提交后依赖现有 TaskService 唤醒 daemon。

Runner 不解析 Agent final text、blocker 文本或 `crctl` stderr 来决定路由。

### 3.5 Pipeline task carrier

新增 `TaskService.EnqueuePipelineTask`，复用现有 Agent/runtime readiness、task queue、claim、retry、broadcast 和 daemon wakeup，只增加固定 context：

```json
{
  "type": "pipeline_node",
  "schema": "ai-first.pipeline-task/v1",
  "workspace_id": "uuid",
  "cr_id": "CR-YYYY-NNN",
  "run_id": "uuid",
  "node_id": "uuid",
  "pipeline_id": "architecture-design",
  "attempt": 1,
  "prompt": "registry 中固定 prompt 经声明输入替换后的文本"
}
```

入队时直接写现有 `cr_id` 与 `pipeline_node_run_id`。新增唯一 sqlc 查询 `CreatePipelineTask`，不是通用 enqueue builder：

1. 以 task-token 盖写的 `source_task_id` 为唯一 attribution 来源；source task 必须属于同一 workspace，且 `source_task.agent_id=executor_agent_id`。
2. 从 source task 原样复制 `originator_user_id`、`accountable_user_id`、`originator_source`、`delegated_from_task_id`、`rule_version_id`、`trigger_evidence_kind`、`trigger_evidence_ref_id`。Pipeline 后继节点是同一用户意图的系统延续，不重新分类 attribution，也不把 logical owner 当用户。
3. executor Agent/runtime 从同 workspace active Agent 行重读；`cr_id` 必须存在于同 workspace `cr` 投影；任一 JOIN/guard 不满足则 INSERT 0 行并返回 `RUNNER_ATTRIBUTION_INVALID`。
4. context、`cr_id`、`pipeline_node_run_id` 与完整 attribution snapshot 在同一 INSERT 中写入。当前 strict `originator→accountable` CHECK 继续机械兜底。
5. 既有 `CreateRetryTask` 已原样继承 attribution、`cr_id` 和 `pipeline_node_run_id`，不新增 retry 分支；只增加合同测试锁定其列清单仍完整。

handler claim path识别 `context.type=pipeline_node` 后填充 task wire 的 `Pipeline*` 字段。daemon 增加 `kindPipeline`：

- `BuildPrompt` 对 pipeline task 直接返回固定 `PipelinePrompt`，不进入 issue/chat/quick-create prompt。
- slim runtime brief 只保留 workspace context、Agent instructions、已绑定 Skills、受控 shell和通用安全规则；不渲染 Issue Metadata、comment workflow 或 quick-create 命令。
- 在 `CRWorkspaceRoots` 中按 `cr_id` 查找唯一 CR root；0 或多于 1 个均 fail closed。
- 复用 `MULTICA_CONTROLLED_SHELL_RULES`：按现有 `prepareCRGuard` 的同一相对关系从 `rules.json` 派生 `crctl.mjs`，不新增第二个路径配置；未配置/文件不存在时仅 pipeline task 返回 `PIPELINE_CRCTL_UNAVAILABLE`，普通任务不变。
- daemon 以 `spawnSync` 等价的 Go `exec.CommandContext(node, crctl, workspace, inspect, ...)` 形态（argv、`shell=false` 语义）对唯一 root 执行一次 `crctl workspace inspect`，要求全部 resources healthy 且 `operationalWorkspace` 非空、realpath 位于该 CR root 内。
- 将 `operationalWorkspace` 作为现有 `PrepareParams.LocalWorkDir`；给 pipeline task 合成 `localDirectoryAssignment` 后复用 `normalizeLocalPath`、realpath、`localPathLocks.Acquire`、local-directory sidecar/runtime-config cleanup，不开第二套路径锁。
- `CRCTL_WORKSPACE` 仍指向唯一 CR root；Agent cwd 为 operational workspace，现有 Pipeline prompt 再执行 inspect 取得同一权威路径。
- GC 继续使用 task-id 查询现有 task terminal 状态，不增加 GC 账本。

### 3.6 唤醒接线

复用现有同步 event bus：

- `cr:updated` → 从 payload 取 `cr_id` 调 `Reconcile`。
- `task:completed` / `task:failed` → 仅当 task 有 `pipeline_node_run_id` 时查 run 并 `Reconcile`。
- `HandleGrantsAck` 更新 `delivered_at` 后，按 ACK IDs 查询受影响 CR，直接调用 `Reconcile`；不新增会被 WS `SubscribeAll` 外发的内部事件。
- server 启动后一次性扫描 `runner=architecture-core/v1` 的非终态 run 并 `Reconcile`。

现有 review event 契约需要一个确定性扩充，且 outbox/commit-scan 两条既有来源必须 parity：

- `crctl review-record` 已经计算 canonical annotation、attempt、blockers、reviewed-at 和 LF-normalized subject digest，因此由它在同一 `event_kind=review` payload 写入 `attempt`、`blockers`、`reviewed_at`、`subject_sha256`。
- daemon `buildReviewPayload` 使用显式 stage→文件映射：`requirement→requirement.yml`、`tech-design→sdd.yml`、`code→code.yml`；读取先 CRLF→LF，再用现有安全 YAML 解析。
- blocker 读取兼容 canonical scalar 字符串和历史结构化对象，归一化为字符串列表；commit-scan 产生的 payload 字段集合与 crctl outbox 完全一致。
- outbox 优先仍保留；两来源同一 commit 的 payload parity 由测试锁定。旧 payload 缺任一 Core 字段时 projector 可维持旧 UI，但 Runner 必须以 `RUNNER_REVIEW_EVIDENCE_INCOMPLETE` fail closed。

这不新增事件通道、命令、状态、账本或判断；只是让同一既有 review 事件的两个采集来源投影相同的已持久化事实。

事件只是唤醒，不是权威事实；丢失唤醒由后续事件或启动扫描恢复。

### 3.7 E2E hardening

#### 3.7.1 Review evidence outbox

`crctl review-record` 在 canonical annotation、review-loop、traceability 同批写成功后，复用现有 `collectOutboxEvidence` 读取 `gates.approvalStages[stage].evidence`，把同一份 `{path: sha256:<hex>}` 放入 `event_kind=review` 的 `evidence` 字段。Agent、Pipeline、daemon 和 server 不实现第二套 digest。server 继续原样落入既有 `cr_sync_event.evidence`，grant crosscheck 只消费最新非空 evidence。

#### 3.7.2 Active pipeline snapshot guard

daemon 仍只从 installation root 收集 snapshot；不扫描全部 worktree、不解析状态机。server `ApplySnapshot` 在已有 projection 入口读取 `pipeline_run` active 事实：CR 存在 active architecture run 时，root snapshot 不覆盖该 CR 的 live status；无 active run 的 CR 保持现有 snapshot healing 和幂等行为。Runner/live cr events 仍是 active pipeline 的投影来源，checkpoint 完成后 pipeline 才结束。

#### 3.7.3 Workspace contract

architecture-design 的 push-progress 节点只传递 `cr_id` 与 message，调用 `crctl checkpoint` 时不嵌入 `<installation-workspace>` 等未解析 token。daemon 已通过 `CRCTL_WORKSPACE`/`CRCTL_OPERATIONAL_WORKSPACE` 提供受控运行环境，crctl 复用现有 repository/worktree resolver；Skill 的 standalone 示例与 pipeline 场景分开说明。生成 registry 必须与 tools source 同步，结构测试拒绝未解析 workspace placeholder。

#### 3.7.4 Origin constraint repair

不修改历史 259/263 migration；新增 267/268 向前修复 migration，使用 `NOT VALID` + 独立 `VALIDATE` 恢复完整九值 `issue_origin_type_check`。服务层不增加 fallback，project_chat/project_discussion 继续复用既有 container issue 创建路径。

## 4. 数据模型

### 4.1 run/node

现有字段分工：

| 字段 | 用法 |
|---|---|
| `pipeline_run.inputs` | `cr_id`、`tech_context` |
| `pipeline_run.execution_context` | runner schema、digest、pipeline owner、executor Agent、source task |
| `pipeline_run.status` | running / waiting_approval / completed / failed / cancelled |
| `pipeline_node_run.attempt` | 只投影 `crctl` review attempt；初始 write/approval/checkpoint 为 1 |
| `pipeline_node_run.detail` | review 顶层投影 + `runner` 命名空间；见下方多写规则 |
| `pipeline_node_run.output_note` | Core 不使用；不创建 node-N 文件协议 |

projector 与 Runner 共用同一 row，采用字段级 merge 而不是整段替换：

```json
{
  "verdict": "pass|block",
  "blockers": [],
  "attempt": 1,
  "reviewed_at": "...",
  "subject_sha256": "...",
  "runner": {
    "logical_owner": "dev-agent",
    "task_id": "uuid",
    "wait_reason": "authority_postcondition",
    "error": { "code": "...", "message": "..." }
  }
}
```

- Runner 只用 `jsonb_set(COALESCE(detail,'{}'), '{runner}', ...)` 更新 `detail.runner`。
- `applyReview` 用 `COALESCE(pipeline_node_run.detail,'{}') || $reviewPayload` 合并 review 顶层字段；payload schema 禁止 `runner` 键，因此保留 Runner 数据。
- review payload 右侧覆盖旧 verdict/blockers/attempt；Runner 从不覆盖这些键。
- terminal node/run 的 SQL predicate 禁止迟到 projector 或 Runner wake 重开。

两种写入顺序（Runner→review、review→Runner）与 projector replay 都必须得到同一 JSON。

### 4.2 attempt

- 初始 `write-tech-design` 与第一次 review 使用 attempt 1。
- review block 事件 attempt=N 后，`replayNodes` 的 repair/review 使用 attempt=N+1。
- Runner 不自增 canonical attempt；创建 repair node 前必须已观察 `crctl` 投影的 attempt=N。
- 当 projected canonical review 同时满足 `verdict=block`、`attempt=registry.maxAttempts` 时，Runner 标记 `RUNNER_LOOP_EXHAUSTED` 并停止，不创建 attempt+1。Runner只比较 crctl 已持久化的 attempt 与 Pipeline max，不递增账本、不解析 task stderr；tools 集成测试另行证明真实 `crctl attempt` 的 attempt+1 返回 `LOOP_EXHAUSTED`。

## 5. 节点后置条件

| 节点 | task/人类结果 | CR 权威事实 | 后继 |
|---|---|---|---|
| write | task completed | status=`tech-design-review-pending` | review |
| review pass | task completed | sdd review payload 字段齐全、pass、blockers=[]、attempt 当前，且 `subject_sha256` 等于当前 SDD LF digest 对应的 canonical 事件证据 | human approval |
| review block | task completed | sdd review payload 字段齐全、block、status=`tech-designing`、attempt=N；N=max 时 exhausted | N<max 才 replay write/review attempt N+1 |
| human approval | grant delivered | pass review 当前、status=`tech-design-review-pending` | approve Skill |
| approve | task completed | approval.yml 投影存在、status=`tech-design-reviewed` | push-progress |
| reject | task failed/business reject | approval decision=reject、status=`tech-designing` | run failed，不 checkpoint |
| push-progress | task completed | task started_at 后存在 checkpoint event，commit SHA 非空 | run completed |

任何只有 task completed、没有右侧权威事实的情况都只记录 `wait_reason`，不调度后继。checkpoint 关联必须晚于 push node `started_at`，避免误用需求阶段旧 checkpoint。

## 6. 接口与错误

| Code | 条件 | 副作用 |
|---|---|---|
| `RUNNER_UNSUPPORTED_PIPELINE` | 非 architecture | 零写入 |
| `RUNNER_REQUIRES_AGENT_ROUTE` | 非 task-token | 零写入 |
| `RUNNER_CR_NOT_READY` | CR 非 requirement-approved / needs_reconcile | 零任务 |
| `RUNNER_AGENT_NOT_READY` | executor 缺失、archived、无 runtime | 零任务 |
| `RUNNER_SKILL_MISSING` | 任一节点 Skill 未启用 | 零任务 |
| `RUNNER_CONTRACT_INVALID` | registry/node/matrix 不一致 | server 启动失败或 start 零写入 |
| `TEMPLATE_DIGEST_MISMATCH` | 恢复 digest 不同 | run failed，无新任务 |
| `RUNNER_AUTHORITY_MISMATCH` | task 与 CR 后置条件冲突 | 当前 node 停止，detail.runner 留证 |
| `RUNNER_ATTRIBUTION_INVALID` | source task / Agent / CR workspace guard 或 strict attribution 失败 | 零任务，node failed |
| `RUNNER_REVIEW_EVIDENCE_INCOMPLETE` | review payload 缺 attempt/blockers/subject | 不进入 repair/approval |
| `PIPELINE_CRCTL_UNAVAILABLE` | daemon 无法从现有 rules 路径派生 crctl | task failed，不降级 scratch 写入 |
| `RUNNER_TASK_FAILED` | 无有效 retry 的 task failed/cancelled | node/run failed |
| `RUNNER_LOOP_EXHAUSTED` | `crctl` 权威耗尽 | run failed，保留 blocker |

HTTP 重放同 start 返回同一 run 和 `changed=false`。

## 7. 安全、性能与恢复

- Runner start 只信 Auth middleware 盖写的 task-token headers，不信 body Agent/user/workspace ID。
- Runner 不读取私钥、不生成/验签 grant；只检查 `approval_record.delivered_at`，最终证据由 `crctl approve --grant` 验证。
- fixed registry prompt 只替换 `cr_id`/`tech_context` 两个声明 token；`tech_context` 做长度上限并作为数据块附加，不参与模板/节点选择。
- pipeline task 只在 `workspace inspect` 返回的 operational workspace 中运行，沿用现有 realpath/path lock/sidecar cleanup；绝不降级到 scratch 跨目录写。
- `Reconcile` 以 indexed run/CR/node/task 查询为主，每次最多入队一个 task，无后台全表轮询。
- startup scan 只取 Core 非终态 run；数量与在途 architecture CR 同阶。
- DB unique violation是正常竞态输家路径：重读，不循环重试。
- server crash 在 node upsert 与 task enqueue 之间时，下一次 reconcile 看到“running node 无 task”并补入队。
- task terminal 与 CR event 任意顺序到达都只形成部分后置条件；第二个唤醒完成推进。

## 8. 技术选型与替代方案

| 方案 | 决定 | 原因 |
|---|---|---|
| 通用 DAG/workflow 库 | 否 | Core 只有固定 5 节点，新增依赖和抽象无价值 |
| 独立 runner 表/事务层 | 否 | 现有 run/node + DB constraints 已足够 |
| server 运行时读取 tools | 否 | 部署不保证 sibling checkout；生成快照可审计 |
| 多版本 registry 存储 | 否 | Core digest 漂移直接 fail closed |
| polling worker | 否 | 已有 task/CR event + grant ACK + startup scan |
| logical owner 名称解析 Agent | 否 | system actor 无 Agent UUID，名称可改；使用 route Agent + Skill binding |
| node-N 本地文件 | 否 | 跨 task/重启不稳定；每节点 prompt 自足 |
| hidden Issue 承载 Pipeline task | 否 | 会污染产品域；task queue 已允许无 issue task |

## 9. FR 到技术实现映射

| FR | 技术条目 |
|---|---|
| FR-01 | §3.4 Start endpoint + 固定 registry |
| FR-02 | §3.1/3.2 tools emitter + generated digest |
| FR-03 | §3.3 indexes + §3.4 run upsert |
| FR-04 | §3.5 task context + §5 双重后置条件 |
| FR-05 | §3.1 replayNodes + §4.2 attempt |
| FR-06 | §3.6 grant ACK + §5 approval flow |
| FR-07 | §5 checkpoint correlation |
| FR-08 | §3.4 reconcile + §3.6 startup scan |
| FR-09 | 现有 projector/UI；Runner feature off 时无接管 |
| FR-10 | §1.2、§8 negative decisions |
| FR-11 | §3.7 hardening：review evidence、active snapshot guard、workspace contract、origin migration repair |

覆盖率：11/11。

## 10. 变更面

### tools

- `pipeline-templates/architecture-design.pipeline.json`
- `pipeline-templates/emit-registry.mjs` + 窄测试
- `skills/shared/crctl/scripts/crctl.mjs`：review outbox evidence 与 developing 期 `task append` 确定性账本入口 + 回归测试
- `skills/develop/write-dev-tasks/SKILL.md`、`skills/shared/crctl/SKILL.md`：追加 hardening TASK 的受控账本入口说明
- `pipeline-templates/architecture-design.pipeline.json`、`skills/sync/push-progress/SKILL.md`：去除未解析 workspace placeholder
- 现有 Pipeline/contract tests

不改 Agent、公共状态机、gates、审批签名协议或 README 可执行事实；`crctl` 只新增 developing 期 TASK 追加原语，不改变既有状态推进/审批语义。

### Multica

- `server/internal/governance/runner.go` + tests
- `server/internal/governance/gen/generate-gate-nodes.mjs`、生成物与现有 projector 小修
- 两个 CONCURRENTLY 单索引 migrations
- `server/internal/service/task.go`、`server/pkg/db/queries/agent.sql` + sqlc 生成物
- `server/internal/handler/daemon.go` claim context hydration
- `server/internal/daemon/{types.go,prompt.go,daemon.go}` 与 `execenv` pipeline kind
- `server/internal/governance/reconcile.go` + tests：active pipeline snapshot guard
- `server/migrations/267_issue_origin_type_restore.*.sql`、`268_issue_origin_type_restore_validate.*.sql` + project container migration/integration tests
- `CUSTOM.md`：新增 hardening migration/行为台账

不改前端、移动端、CR gate UI、公共状态机和审批签名协议。

## 11. 测试设计

1. tools registry snapshot：replay schema、node UUID、owner/can-call、CRLF canonical digest。
2. generator `--check`：当前 tools 生成 `0016`，registry/digest 不漂移。
3. DB integration：双 start；start 与 projector 并发；同 node 双 enqueue；retry 父终态后可创建。
4. Runner table tests：happy path、block→repair→pass、canonical attempt=max exhausted、reject、checkpoint。
5. 双重后置条件：task terminal 与 CR/review/checkpoint 事件两种顺序；只到一半不前进；subject digest 缺失/陈旧阻断。
6. attribution：source snapshot 全字段复制、strict CHECK 通过、source/Agent/CR 任一跨 workspace 时 INSERT 0 行；retry 列清单保持。
7. detail merge：Runner→review、review→Runner、projector replay 三种顺序结果相同，`runner` 与 verdict/blockers 均不丢。
8. grant：记录未 delivered 不入队；ACK 后一次入队；坏 grant 由 Skill/`crctl` 拒绝后 run failed。
9. review event：commit-scan-only、outbox-only、同一 commit 双来源 parity；tech-design 必须读取 `sdd.yml`，scalar/structured blockers 归一化，digest/attempt 缺失硬失败；review outbox 必须携带同一 stage evidence。
10. daemon：pipeline context hydration、prompt 不含 issue/quick-create workflow、CR root 0/1/2 匹配、inspect 非 healthy、rules/crctl 缺失；LocalWorkDir 与现有 path lock/cleanup 生效；active pipeline 期间 stale snapshot 不覆盖 projection。
11. restart：四个 PRD AC 指定窗口启动扫描，只有一个有效 task。
12. migration：clean upgrade 与 affected upgrade 均验证九种 origin constraint，project_chat/project_discussion 容器创建通过。

数据库测试必须在真实 PostgreSQL 下看到 `=== RUN` / `--- PASS`，不能把 TestMain skip 当通过。

## 12. 风险与缓解

| 风险 | 缓解 |
|---|---|
| projector 覆盖 run waiting/running | Runner 不以单一 run.status 决定业务后继；每次重算节点/CR事实，UPDATE 不回开 terminal |
| Agent task 完成早于 CR event | 双重后置条件等待第二个唤醒 |
| attribution 新写路径漂移 | 单一 INSERT 从 source task 复制完整 snapshot，strict DB CHECK + 列清单测试 |
| detail 多写覆盖 | review 顶层 merge + `detail.runner` 命名空间，双顺序/replay 测试 |
| matrix logical owner 无 runtime Agent | registry 保留 logical owner；route Agent UUID 作为 executor，并校验 Skill bindings |
| 多个 CR roots 命中同 ID | daemon fail closed，不取第一个 |
| provider sandbox 拒绝跨目录写 | inspect 后 operational workspace 作为现有 LocalWorkDir，并复用 realpath lock/cleanup |
| review outbox 信息不足 | crctl review-record 复用同一 stage evidence；server 只存储/投影，不重算 | 旧 payload 继续由现有 fail-closed/legacy 规则处理 |
| active pipeline 被 root snapshot 覆盖 | ApplySnapshot 复用 active pipeline_run guard；checkpoint 完成后再接受 root snapshot | 删除 guard 恢复旧 snapshot 行为 |
| workspace placeholder 被 Agent 当路径 | pipeline 只传业务输入，daemon 环境和 crctl resolver 提供 workspace | 回滚模板/生成物，standalone 显式路径不变 |
| origin constraint 在 rebase/migration 中丢值 | 新增向前 repair migration，完整集合 + NOT VALID/VALIDATE | down migration fail closed，不静默保留非法历史数据 |

## 13. Prompt 采纳影响

本次 hardening 不新增业务判断或新状态机：`review-record` 只投影它刚刚原子持久化的 canonical evidence；ApplySnapshot 只复用已有 active pipeline_run 事实做冲突保护；Pipeline prompt 只传递 `cr_id`/message，workspace 由 daemon 环境和 crctl resolver 提供；migration 只修复数据库约束。`task append` 是 developing 期新增 TASK 的确定性账本入口，不允许手写 `_index.yml`。

## 14. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-17 | v0.3.0 | Ray | 回修 SDD-B05：commit-scan 与 outbox review payload parity、显式 stage 文件映射和 blocker 归一化 |
| 2026-08-17 | v0.2.0 | Ray | 回修 SDD-B01～B04：source attribution snapshot、detail.runner merge、operational LocalWorkDir、canonical review outbox |
| 2026-08-18 | v0.4.0 | Ray | E2E hardening scope amendment：review evidence、active snapshot guard、workspace contract、origin migration repair、developing task append |

## CR 合并与新注册 Worktree 同步治理优化方案（v0.20.7 · CR-2026-046）

## SDD — CR 合并与新注册 Worktree 同步治理优化方案

> 目标代码仓：`tools`（本 CR 只改 `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 与两个测试文件）。
> 架构基线：`tools/ARCHITECTURE.md`（已存在，只读引用；本 CR 不修订它——不新增分组、Pipeline 结构、写入子命令、状态机口径，不构成架构级变更）。

### 1. 架构概览

#### 1.1 模块边界与依赖方向

本 CR 严格落在 crctl 执行层，不触及上层：

```text
Skill（write/register/merge 调用点不变，一次深原语）
   ↓ 调用
crctl.mjs（dispatch 分支零改动；merge 输出经 ...result 透传）
   ↓ import
lib/workspace-transactions.mjs   ← 本 CR 唯一实现落点
   ├─ ensureRepoWorkspace（missing 分支修正）
   └─ reconcileLocalTrunks（新增模块内 helper，mergeCr 调用；导出仅供既有测试模式）
   ↓ import（既有）
lib/durable-tx.mjs（TxError/faultPoint/lock——只复用，不改）
```

不新增文件、不新增依赖、不改状态机/gates/Pipeline/README/Skill/Agent。两个测试文件 `test/register-tx.test.mjs`、`test/merge-tx.test.mjs` 追加用例。

#### 1.2 两个修改点的位置与关系

| 修改 | 位置（现有代码） | 性质 |
|---|---|---|
| A：注册基点取远端事实 | `ensureRepoWorkspace` 的 `case 'missing'`（现约 L501-524） | 事务内（register journal 恢复语义不变，失败抛 TxError 中断重跑） |
| B：merge 后本地同步 | `mergeCr` 返回前（现约 L1491-1497）新增 helper 调用 | 非事务化（不写 journal/账本，结果只进输出） |

两者共享的既有能力（PRD §1.3）：`classifyRepoWorkspace` 七分类、`gitRun`/`gitMust`、`TxError`、`faultPoint`、register/merge journal envelope 与目录锁。全部直接复用，不改签名。

#### 1.3 关键流程

```text
注册（缺口 A）：
  ensureRepoWorkspace 首次 classify = missing
    → git fetch --prune origin（失败 → WORKSPACE_TRUNK_UNAVAILABLE，不创建/修改 CR branch/worktree）
    → classifyRepoWorkspace 重新分类
       → remote-only：git branch --track + worktree 挂接（既有逻辑）
       → branch-only：挂接并发出现的既有本地 CR branch（既有逻辑）
       → missing：解析 refs/remotes/origin/{trunk} 存在后 git branch {cr} <该 ref> + worktree
       → 其他：WORKSPACE_ENSURE_BLOCKED 硬阻断

合并（缺口 B）：
  mergeCr 现有事务（preflight → prepare → lease publish → finalize）不变
    → finalizePushed 确认、journal save('complete')
    → reconcileLocalTrunks(ctx) 逐仓 8 判据（结果只入返回对象）
    → return { ..., localTrunkSync }
```

#### 1.4 Prompt 采纳影响判定

本 CR 不触及 `crctl.mjs` 的 dispatch 分支（不新增/重命名子命令，flag 面不变；`localTrunkSync` 经 `ok({ op:'merge', ...result })` 自动透传）与 `skills/shared/controlled-shell/rules.json` 的 deny 面（无新受控路径）。SDD 第 8 节（Prompt 采纳影响）条件不成立，省略。

### 2. 数据模型

#### 2.1 无新增持久化结构

- register journal / merge journal：字段不变（PRD FR-6）。
- 无新账本文件、无新 `.crctl` 目录。
- 唯一新增数据形态是 `crctl merge` 成功输出的内存数组 `localTrunkSync`（非持久化、不写 audit、不写 journal）：

```ts
type LocalTrunkSyncRow = {
  repo: string;                       // repositories[].id
  trunk: string;                      // repositories[].trunk
  before: string | null;              // 进入 helper 时可解析的本地 HEAD，否则 null
  remote: string | null;              // fetch 成功后捕获的 origin/{trunk} SHA，否则 null
  after: string | null;               // helper 返回时可解析的本地 HEAD，否则 null
  status: 'synced' | 'unchanged' | 'skipped' | 'failed';
  reason: 'dirty' | 'wrong-branch' | 'diverged' | 'fetch-failed' | 'trunk-unavailable' | 'ff-only-failed' | null;
};
```

#### 2.2 字段取值规则（PRD FR-9，实现按此逐字段落值）

| 结果 | status | reason | before | remote | after |
|---|---|---|---|---|---|
| wrong-branch（含 detached/读取失败） | skipped | wrong-branch | 可解析 HEAD 或 null | null | = before |
| dirty | skipped | dirty | HEAD | null | = before |
| fetch 失败 | failed | fetch-failed | HEAD | null | = before |
| trunk 不可解析 | failed | trunk-unavailable | HEAD | null | = before |
| 已一致 | unchanged | null | HEAD | = before | = before |
| 非祖先 | skipped | diverged | HEAD | 已捕获 SHA | = before |
| ff-only 成功 | synced | null | HEAD | 捕获 SHA | 新 HEAD |
| ff-only 失败 | failed | ff-only-failed | HEAD | 捕获 SHA | 失败后实际 HEAD（可解析） |

### 3. 接口契约

#### 3.1 `ensureRepoWorkspace(ctx, repo, cr)`（内部函数，行为契约变更）

- 签名不变。`healthy` / `branch-only` / `dirty` / `wrong-branch` / `path-unregistered` 行为不变，且不触发 fetch。
- `missing`：先 `git fetch --prune origin`，清理已从远端删除的 stale tracking refs，再重新分类，按 1.3 流程创建或阻断。
- 新结构化错误 `WORKSPACE_TRUNK_UNAVAILABLE`（TxError），extra 携带 `{ repo, ref?, cause? }`；`ref` 为 trunk 不可解析时的 refs/remotes/origin/{trunk}，`cause` 为 fetch 失败时底层 git 错误摘要。
- 保证：错误路径不创建/修改/删除 `requirement/{CR-ID}` branch 与 worktree；fetch 已更新的 remote-tracking refs 不回滚；不回退本地 trunk；无 reset/stash/rebase。

#### 3.2 `reconcileLocalTrunks(ctx)`（新增导出函数，供 mergeCr 与单元测试调用）

- 输入：`ctx`（`resolveRepositories` 产物，含 `repositories[]`：`id/trunk/rootPath`）。
- 输出：`LocalTrunkSyncRow[]`，每仓一行，顺序与 `ctx.repositories` 一致。
- 错误语义：**绝不抛出**。只读判定使用 `gitRun`；有副作用的 `fetch --prune` 与 `merge --ff-only` 均按模块不变量经 `gitMust` 执行，并在局部 try/catch 中转换为 `failed/fetch-failed` 或 `failed/ff-only-failed`（PRD FR-10 的 exit 0 前提）。

#### 3.3 `mergeCr(ctx, input)` 返回契约（增量）

- 现有字段全部不变（`cr/txId/phase/changed/sideEffects/recoverCommand/operationalWorkspace/mergedStatus`）。
- 新增 `localTrunkSync: LocalTrunkSyncRow[]`，在 `save('complete')` 之后、return 之前计算。
- helper 只在本次 `mergeCr` 远端 finalize 确认并 `save('complete')` 后执行一次。若进程在 complete 后、helper 前或执行中退出，不提供自动恢复，也不承诺重跑 `crctl merge`（finalize 后 authority/status 门禁会阻止该命令重入）；用户按 PRD FR-10 使用原生 `git pull --ff-only`。
- `crctl merge status` 只读快照、`workspace inspect`、`crctl status` 输出面均不变（PRD NFR-5）。

#### 3.4 错误码新增

| code | 触发 | 携带 | 语义 |
|---|---|---|---|
| `WORKSPACE_TRUNK_UNAVAILABLE` | fetch 失败或 origin/{trunk} 不可解析 | repo/ref/cause | 注册事务中断，重跑幂等续跑；不回退本地 trunk |

### 4. 关键算法与流程

#### 4.1 ensureRepoWorkspace missing 分支（伪代码）

```text
case 'missing':
  try:
    gitMust(rootPath, ['fetch', '--prune', 'origin'])
  catch e:
    throw TxError('WORKSPACE_TRUNK_UNAVAILABLE', '{repo}: fetch origin 失败（不创建 CR branch/worktree）', { repo, cause: e.message })

  re = classifyRepoWorkspace(ctx, repo, cr)      # 复用既有分类，不新写逻辑

  if re.classification == 'remote-only':
    gitMust(rootPath, ['branch', '--track', branch, 'origin/' + branch])
    return create('from-remote')                 # 既有 create 闭包

  if re.classification == 'branch-only':
    return create('from-local-branch')           # 并发出现本地 CR branch，复用既有恢复

  if re.classification != 'missing':
    throw TxError('WORKSPACE_ENSURE_BLOCKED', 'fetch 后重新分类={cls}，硬阻断', { ...re })

  trunkRef = 'refs/remotes/origin/' + repo.trunk
  trunk = gitRun(rootPath, ['rev-parse', '--verify', '-q', trunkRef])
  if trunk.status != 0 or trunk.stdout == '':
    throw TxError('WORKSPACE_TRUNK_UNAVAILABLE', '{trunkRef} 不可解析，不回退本地 trunk', { repo, ref: trunkRef })

  gitMust(rootPath, ['branch', branch, trunkRef])   # 起点=远端 trunk ref，不再是本地 trunk
  return create('from-remote-trunk')
```

要点：
- `git branch <name> refs/remotes/origin/{trunk}` 是 git 原生起点语义（等价 `git branch <name> <SHA>`，不设置 upstream——CR 分支本就不跟踪 trunk）。
- `classifyRepoWorkspace` 在 worktree 缺失时提前返回，故 fetch 后重新分类只会出现 `branch-only`（并发建分支）、`remote-only`、`missing` 三类；前两者显式复用既有恢复路径，其余（不可达但防御性）硬阻断。
- `--prune` 是满足“远端事实”与 trunk-unavailable 合同的一项原生 Git 参数：远端已删除 trunk/CR 分支时清理 stale `refs/remotes/origin/*`，不新增查询算法或事务。
- 失败发生在 register 事务的 worktree 阶段（账本已提交/push），重跑同命令按 journal `worktrees[]` 续跑，幂等（PRD NFR-2）。

#### 4.2 reconcileLocalTrunks（8 判据，PRD FR-8 逐条落位）

```text
for repo in ctx.repositories:
  row = { repo, trunk, before:null, remote:null, after:null, status:null, reason:null }
  before = gitRun(rootPath, ['rev-parse', '-q', 'HEAD'])          # 判据 0（取值）
  row.before = before.status == 0 ? before.stdout : null

  cur = gitRun(rootPath, ['symbolic-ref', '--short', '-q', 'HEAD'])
  if cur.status != 0 or cur.stdout != repo.trunk:                 # 判据 1
    row = { ...row, status:'skipped', reason:'wrong-branch', after: row.before }; continue

  st = gitRun(rootPath, ['status', '--porcelain'])
  if st.status != 0 or st.stdout != '':                           # 判据 2
    row = { ...row, status:'skipped', reason:'dirty', after: row.before }; continue

  try:
    gitMust(rootPath, ['fetch', '--prune', 'origin'])              # 判据 3；副作用只经 gitMust
  catch e:
    row = { ...row, status:'failed', reason:'fetch-failed', after: row.before }; continue

  rr = gitRun(rootPath, ['rev-parse', '--verify', '-q', 'refs/remotes/origin/' + repo.trunk])
  if rr.status != 0 or rr.stdout == '':                           # 判据 4
    row = { ...row, status:'failed', reason:'trunk-unavailable', after: row.before }; continue
  row.remote = rr.stdout                                          # 捕获 SHA，此后不再重新解析

  if row.before == row.remote:                                    # 判据 5
    row = { ...row, status:'unchanged', after: row.before }; continue

  anc = gitRun(rootPath, ['merge-base', '--is-ancestor', row.before, row.remote])
  if anc.status != 0:                                             # 判据 6（before=null 时命令必失败，同归 diverged）
    row = { ...row, status:'skipped', reason:'diverged', after: row.before }; continue

  try:
    faultPoint('local-sync-ff-only-failed', { repo: repo.id })    # 复用既有测试故障注入；仅匹配测试环境变量时抛出
    gitMust(rootPath, ['merge', '--ff-only', row.remote])         # 判据 7：用捕获 SHA，不重解析移动 ref
    h1 = gitRun(rootPath, ['rev-parse', '-q', 'HEAD'])
    row = { ...row, status:'synced', after: h1.status == 0 ? h1.stdout : null }
  catch e:                                                        # 判据 8
    h1 = gitRun(rootPath, ['rev-parse', '-q', 'HEAD'])
    row = { ...row, status:'failed', reason:'ff-only-failed', after: h1.status == 0 ? h1.stdout : null }
```

安全属性：只读判定经 `gitRun`；两条 Git 副作用命令仅为 `git fetch --prune origin`（remote-tracking refs）与 `git merge --ff-only <捕获 SHA>`（本地 trunk），均经 `gitMust` 且局部捕获；无 reset/stash/rebase/普通 merge/checkout；失败即本仓终止，不影响其他仓与远端结果。

#### 4.3 调用点（mergeCr）

```text
payload.finalizePushed 确认后（现有代码不变）
  payload.operationalWorkspace = txws
  await save('complete')
  const localTrunkSync = reconcileLocalTrunks(ctx)   ← 新增两行（含 return 里的字段）
  return { ..., localTrunkSync }
```

helper 在 merge 目录锁内执行（return 在 `finally` 释放锁之前）：与既有 merge 事务互斥，无需新锁；不写 journal。进程在 `save('complete')` 后、helper 前或执行中退出时不补偿，且 finalize 后 authority/status 门禁不允许重跑 `crctl merge`；用户按 PRD FR-10 原生执行 `git pull --ff-only`。

### 5. 技术选型与替代方案

| 决策 | 选择 | 替代方案与否决理由 |
|---|---|---|
| 注册基点 | `fetch --prune` + 重新分类 + `git branch <cr> refs/remotes/origin/{trunk}` | register journal 记录 `base-sha/source`（PRD §4.3 否决：本地 ref 已是基点权威事实，journal 复制 Git 事实且跨仓无共享 SHA） |
| 重新分类 | 复用 `classifyRepoWorkspace` 二次调用 | 新写 fetch 后专用分类函数（重复逻辑，违反复用优先） |
| 本地同步 | 非事务化 best-effort ff-only | 本地同步事务/durable journal/intent digest/恢复命令（PRD §6.3 否决：远端事务已完成，本地补偿无同级原子性要求，且再造第二套事务违反 ARCHITECTURE §6） |
| 合并算法 | `git merge --ff-only <捕获 SHA>`（CR-2026-043 workspace sync 已验证模式） | 自写 merge 语义/二次解析移动 ref（捕获 SHA 是 FR-8 明确要求，且已有先例） |
| ff-only-failed 测试 | 复用 `faultPoint('local-sync-ff-only-failed')` 注入 TxError，断言 catch 转换 | 文件系统破坏性构造（index.lock/hook 干扰，脆弱且污染其他判据） |
| 依赖 | Node 标准库（fs/path/crypto/spawnSync）+ 原生 git | 任何新依赖（违反 ARCHITECTURE 不变量 3） |

### 6. FR 到技术实现映射

| FR | 实现位置 | 方式 |
|---|---|---|
| FR-1 | `workspace-transactions.mjs#ensureRepoWorkspace` `case 'missing'` | `fetch --prune` → `classifyRepoWorkspace` 重新分类；首次分类 healthy/branch-only 路径零改动（天然不 fetch） |
| FR-2 | 同上 | 重新分类 `remote-only` 分支复用既有 `--track` + `create('from-remote')` |
| FR-3 | 同上 | `rev-parse --verify -q refs/remotes/origin/{trunk}` 成功后 `git branch <cr> <trunkRef>`；删除原 `git branch <cr> {repo.trunk}` 路径 |
| FR-4 | 同上 | fetch 失败/trunk 不可解析均 `TxError('WORKSPACE_TRUNK_UNAVAILABLE')`；无回退分支 |
| FR-5 | 同上 | 重新分类 branch-only → 复用 `create('from-local-branch')`；dirty/wrong-branch/path-unregistered 等非恢复分类 → `WORKSPACE_ENSURE_BLOCKED` 硬阻断 |
| FR-6 | 无改动 | register journal 结构零变更（`register-tx.test.mjs` 既有 journal 断言回归） |
| FR-7 | `mergeCr` 返回前 + 新 `reconcileLocalTrunks(ctx)` | 逐 `ctx.repositories` 处理 `repo.rootPath`；不遍历 worktree list、不碰 CR worktree |
| FR-8 | `reconcileLocalTrunks` 判据 1-8 | 见 §4.2 伪代码逐条对应 |
| FR-9 | 同上 + `mergeCr` return | `LocalTrunkSyncRow` 字段按 §2.2 表落值 |
| FR-10 | `reconcileLocalTrunks` 不抛 + `mergeCr` 不改 exit 语义 | 任何结果均返回完整数组；`crctl.mjs` 零改动，`ok()` 照常 exit 0 |
| FR-11 | 无改动 | writeback 继续只使用 `operationalWorkspace`（本 CR 不触碰该路径） |

### 7. 安全与性能考量

#### 7.1 安全

- **现场零破坏**（PRD NFR-1）：两个修改点合计的写命令仅 `git fetch --prune origin`（更新/清理 remote-tracking refs）、`git branch`（新分支/--track）、`git worktree add`（既有 create 闭包）、`git merge --ff-only <捕获 SHA>`。无 reset/stash/rebase/普通 merge/强制 checkout/本地分支删除；无回滚或补偿事务。
- **不回退本地 trunk**：`WORKSPACE_TRUNK_UNAVAILABLE` 与 `trunk-unavailable` 都是终止/跳过，绝不 fallback 到 `repo.trunk` 本地 ref。
- **并发**：register 修改在 register 事务锁内；helper 在 merge 事务锁内，与其他 merge 互斥。helper 无共享状态。
- **历史重写防护**：注册/merge 事务既有的 `classifyRemoteCommit` 历史重写硬阻断不受影响；helper 只做 ff-only，祖先判定由 git 原生 `merge-base --is-ancestor` 承担，不新增自定义算法。
- **错误输出与观察面**：新增错误码沿既有 `TxError` → `fail` 结构化错误路径返回；本 CR 不新增失败审计能力。`localTrunkSync` 刻意不写 audit/journal（PRD NFR-5 唯一观察面 = merge 输出）。

#### 7.2 性能

- 新增 git 调用：注册 missing 仓 +1 fetch、+1 重新分类（4 次只读 git）；merge helper 成功路径每仓最多 8 次 git（before、branch、status、fetch、remote、ancestor、merge、after），各跳过/失败路径提前结束。
- 对照 ARCHITECTURE §7a 外部调用量基线（merge 目标 2-4）：本次每仓 +1 fetch 属必要远端事实刷新，不删除任何 gate/测试/审批。
- 无大文件 IO、无 YAML 解析新增（不触碰行尾纪律敏感面；新增代码不含跨行正则/哈希解析）。

#### 7.3 失败模式

| 失败 | 系统行为 |
|---|---|
| 注册 fetch 失败 | `WORKSPACE_TRUNK_UNAVAILABLE`，事务中断，重跑幂等续跑 |
| 注册 trunk 缺失 | 同上，不创建 branch/worktree |
| helper fetch 失败 | 该仓 `failed/fetch-failed`，merge 仍 `phase=complete`、exit 0 |
| helper ff-only 失败 | 该仓 `failed/ff-only-failed`，远端发布不受影响 |
| 进程在 save('complete') 后、helper 前或执行中退出 | 同步不补偿；finalize 后不得重跑 merge，用户原生 `git pull --ff-only` |

### 8. 测试设计（写入两个既有测试文件，不新增文件）

#### 8.1 register-tx.test.mjs（单元级：直接 import `ensureRepoWorkspace`/`resolveRepositories`，先例同 `merge-tx` import lib 函数）

1. **stale local trunk**：origin master 推进后本地落后，`ensureRepoWorkspace`（missing）→ 本地 `requirement/{CR}` HEAD == 新 origin master SHA（AC-1）。
2. **远端 CR 分支恢复**：仅远端有 `requirement/{CR}`、本地无任何 ref → 分类 `from-remote`，tracking 正确（AC-2）。
3. **fetch 失败**：`git remote set-url origin <bogus>` → 抛 `WORKSPACE_TRUNK_UNAVAILABLE`，无本地 branch/worktree（AC-3）。
4. **trunk 缺失且本地存在 stale tracking ref**：保留本地 `refs/remotes/origin/master`，仅在 bare origin 执行 `update-ref -d refs/heads/master` → `fetch --prune` 清理 stale ref，随后抛 `WORKSPACE_TRUNK_UNAVAILABLE`（AC-3）。
5. **healthy/branch-only 不 fetch**：bogus url 下 `healthy` 返回 `none`、`branch-only` 返回 `from-local-branch` 不抛错（证明无 fetch，AC-4）。
6. 既有七分类/幂等/fault 测试零回归（AC-4/5）。

#### 8.2 merge-tx.test.mjs

1. **happy path 追加断言**：现有三仓 happy path 测试追加 `r.json.localTrunkSync` 断言——三仓 `status=synced`、`before`=fixture 初始 HEAD、`remote`=origin master SHA、`after`=remote；主 checkout `rev-parse master` == origin master（AC-6/7）。
2. **表驱动单元测试**（直接调 `reconcileLocalTrunks`，复用 `merge-fixture.mjs` 已导出的 `makeFixture` bare 三仓）：wrong-branch（checkout 其他分支）、dirty（未提交文件）、diverged（本地前进且 origin 也前进）、fetch-failed（bogus url）、trunk-unavailable（远端删 master、本地保留 stale tracking ref，验证 `--prune` 清理）、unchanged（已同步）→ 断言 status/reason/before/remote/after 按 §2.2 表取值（AC-6）。
3. **ff-only-failed 集成**：helper 的 ff-only try/catch 内调用既有 `faultPoint('local-sync-ff-only-failed')`；以 `CRCTL_FAULT_POINT=local-sync-ff-only-failed` 跑完整 merge → exit 0、`phase=complete`、kb 行 `failed/ff-only-failed`、远端 master 已含 merge commit（AC-6/7）。
4. 既有 journal/lease/finalize/重入测试零回归（AC-8）。

#### 8.3 不做的测试

- 不测试"helper 前进程中断"恢复（明确不提供恢复，语义测试覆盖即可）。
- 不引入 mock 框架：全部用真实 git 命令 + 既有 faultPoint 注入。

## P3 组织智能 CR-A：AI 成熟度看板（E1 快照 / E2 看板 / E3 周报）（v0.21 · CR-2026-047）

## SDD — P3 组织智能 CR-A：AI 成熟度看板

> 本文档以 `prd.md` 为输入，描述 CR-A 的模块边界、数据模型、接口契约、关键算法、测试方案与技术选型。权威约束见 multica 根目录 `ARCHITECTURE.md`（硬不变量 1–9）与 `CLAUDE.md`（迁移/代码规则）。本 CR 修改 multica 自研代码时同步登记 `CUSTOM.md`；代码注释一律英文。
>
> **首轮评审回修**：本文已消费 `review-annotations/sdd.yml` attempt 1 的 B1–B6：迁移并发索引、历史快照边界、8 项公式、治理三态、完整 API 类型、daemon→server 周报回传与测试矩阵。

---

### 1. 架构概览

#### 1.1 交付物、仓与模块边界

| 交付物 | 内容 | 落点仓 | 关键模块 |
|---|---|---|---|
| E1 | 口径配置 + 生成器 + 日快照 rollup | 声明落 **knowledge-base 本仓**；生成器与任务落 **multica** | `maturity-config.yaml`、可选 `model-prices.yaml`、`server/internal/maturity/gen/generate-config.mjs`、`server/internal/maturity/config_gen.go`、`server/internal/scheduler/jobs_maturity.go`、迁移 375–379 |
| E2 | 看板读 API + 共享视图 + Web/Desktop 接线 | **multica** | `server/internal/handler/maturity.go`、`server/internal/service/maturity*.go`、`server/pkg/db/queries/maturity.sql`、`packages/core` schema/client、`packages/views/dashboard/maturity/` |
| E3 | Org Admin Workspace + 周报 Autopilot | **multica**；报告原文落 daemon 绑定目录、不经 git | `server/internal/service/org_admin_*.go`、内置 skill `multica-maturity-weekly-report`、`agent_task_queue.result` 报告回执、`docs/org-admin/maturity-review-{YYYY-Www}.md` |

依赖方向（不引入反向依赖）：

```text
packages/views/dashboard/maturity/
  -> packages/views/dashboard/components/  # 复用 sibling 组件 dim-segmented / usage-trend-card / leaderboard
  -> packages/core                         # API client、query keys、zod schema
  -> packages/ui                           # 上述 views 组件内部使用的 UI 原语

server/cmd/server/router.go                # composition root
  -> server/internal/handler/maturity.go   # auth / request validation / response encoding
  -> server/internal/service/maturity*.go  # workspace-scoped business logic
  -> server/internal/maturity/             # 纯类型、生成配置、计分函数；不访问 DB
  -> server/pkg/db/queries/maturity.sql    # sqlc
  -> PostgreSQL

server/internal/scheduler/jobs_maturity.go
  -> scheduler/service.NextOccurrencesUTC  # 既有 cron 求解
  -> service.RollupMaturitySnapshot         # advisory lock + 单事务

server/internal/maturity/gen/generate-config.mjs
  -> knowledge-base maturity-config.yaml (+ optional model-prices.yaml)
  -> server/internal/maturity/config_gen.go # committed generated source；构建不读 sibling repo
```

#### 1.2 三条运行链路

1. **E1 快照**：scheduler 用 `PlansForScope` 枚举 Asia/Shanghai 每日 00:30 plan → handler 以 `PlanTime` 唯一推导前一自然日 `bucket_date` → 一次事务内按 org/user/project 写 `maturity_snapshot`。8 项原始值、治理护栏、8 项分/5 维分/总分都在 rollup 时固化；观察期或基线未批准时只写 `metrics`，`scores={}`。
2. **E2 读取**：`GET /api/maturity/*` → workspace 鉴权 → 读已存 snapshot 返回 overall/项目排名/项目与用户趋势。**不得从原始事件重算历史分数**；只有不参与成熟度分数的 model Token 明细可按范围读 `task_usage`。
3. **E3 周报**：既有 schedule Autopilot 在绑定 Org Admin 项目的 daemon `local_directory` 内写 markdown；同一任务完成时把结构化 report envelope 放进既有 `agent_task_queue.result` 并产生既有 assistant chat message。server API 只读数据库里的 envelope，**不跨进程直读 daemon 文件系统**；目录文件是原文历史，result/chat 是可查询投影与追问入口。

#### 1.3 权威与投影边界

- `maturity-config.yaml` 是口径声明权威；`config_gen.go` 是 committed 只读副本。
- `maturity_snapshot` 是可重建的操作态投影，但每行代表**该日、该 `config_rev` 下已固化的历史事实**；常规查询不得重算覆盖。
- CR 状态权威仍是 knowledge-base 的 `_backlog.yml`/`cr.md`/审批证据；CR-A 只读 multica 中的 `cr`/pipeline 投影，绝不反写 CR 状态。
- 周报原文权威是 Org Admin 项目目录文件；`agent_task_queue.result`/chat message 是 server 可见投影，按 `report_key` 去重展示。

---

### 2. 数据模型

#### 2.1 `maturity_snapshot`：唯一新表，迁移 375–379

PRD 的业务键 `(bucket_date, scope, scope_id)` 在多 workspace 架构下会让所有 org 行以 `scope_id='·'` 冲突；SDD 增补必需租户键 `workspace_id`，物理主键为 `(workspace_id, bucket_date, scope, scope_id)`。这是对 FR-4 的租户隔离细化，不新增业务实体、无 FK。

```sql
-- 375_maturity_snapshot_table.up.sql：仅建表，不在 CREATE TABLE 内隐式建任何索引
CREATE TABLE maturity_snapshot (
    workspace_id UUID        NOT NULL,
    bucket_date  DATE        NOT NULL,
    scope        TEXT        NOT NULL CHECK (scope IN ('org','user','project')),
    scope_id     TEXT        NOT NULL,
    metrics      JSONB       NOT NULL DEFAULT '{}',
    scores       JSONB       NOT NULL DEFAULT '{}',
    config_rev   TEXT        NOT NULL CHECK (config_rev ~ '^[0-9a-f]{40}$'),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
      (scope = 'org' AND scope_id = '·') OR
      (scope IN ('user','project') AND scope_id <> '·')
    )
);
```

迁移严格遵守“每个索引 CONCURRENTLY、单文件一语句，包括新表”：

```sql
-- 376_maturity_snapshot_identity.up.sql
CREATE UNIQUE INDEX CONCURRENTLY maturity_snapshot_identity_uidx
ON maturity_snapshot (workspace_id, bucket_date, scope, scope_id);

-- 377_maturity_snapshot_primary_key.up.sql
ALTER TABLE maturity_snapshot
ADD CONSTRAINT maturity_snapshot_pkey
PRIMARY KEY USING INDEX maturity_snapshot_identity_uidx;

-- 378_maturity_snapshot_scope_date.up.sql
CREATE INDEX CONCURRENTLY maturity_snapshot_scope_date_idx
ON maturity_snapshot (workspace_id, scope, scope_id, bucket_date DESC);

-- 379_maturity_report_history.up.sql：既有 369 仅覆盖 active project task，不能服务 completed report history
CREATE INDEX CONCURRENTLY idx_atq_maturity_report_history
ON agent_task_queue (project_id, completed_at DESC, id DESC)
WHERE status = 'completed'
  AND project_id IS NOT NULL
  AND result->>'schema' = 'ai-first.maturity-report/v1';
```

Down 顺序：379 `DROP INDEX CONCURRENTLY` → 378 `DROP INDEX CONCURRENTLY` → 377 `DROP CONSTRAINT`（同步移除其 index）→ 376 `DROP INDEX CONCURRENTLY IF EXISTS` → 375 `DROP TABLE`。每个 migration 仍只有一条 statement；所有文件先过现有 migration lint，再在真实 PostgreSQL 执行 up/down/up。

#### 2.2 JSON 契约

`metrics` 固化 8 项原始值和治理护栏；`scores` 固化 8 项分、5 维分与总分。键集合由生成配置与 Go 类型共同约束，写入前 service 校验，不接收外部任意 JSON。

```ts
type DataStatus = 'ready' | 'empty' | 'unavailable' | 'not_applicable'
type MetricValue = {
  value: number | null
  numerator: number | null
  denominator: number | null
  unit: 'tokens_per_member_day' | 'ratio' | 'cr_per_member' | 'members_per_cr'
      | 'count' | 'milliseconds'
  data_status: DataStatus
  reason: string | null
  attribution: {
    attributed_count: number
    unattributed_count: number
    coverage: number | null
  } | null
}

type SnapshotMetricsV1 = {
  schema: 'ai-first.maturity-metrics/v1'
  headline: {
    active_members: number
    total_tokens: number
    cost_usd: number | null
    cost_status: 'authoritative' | 'mixed' | 'estimated' | 'unavailable'
  }
  metric_values: Record<MetricKey, MetricValue> // 8 个固定 MetricKey，完整不缺键
  governance: Record<GovernanceMetricKey, MetricValue> // 6 个固定 key
}

type SnapshotScoresV1 = {
  schema: 'ai-first.maturity-scores/v1'
  metric_scores: Record<MetricKey, number>       // 8 项，0..100
  dimension_scores: Record<DimensionKey, number> // AIF/SII/OFI/EPC/ACM，0..100
  total_score: number                            // 0..100
}
```

- **观察期/未校准**：`metrics` 正常写全；`scores` 必须为 JSON 对象 `{}`，不是带 `null` 的伪分数。
- **治理未测量**：`metrics.governance.<key>` 仍有完整键，但 `value=null,data_status='unavailable',reason=<machine-readable reason>`；“未测量”绝不伪装成 0。
- **scope 适用性**：org/project 固化可计算指标；user 仅用于 Token/任务趋势，CR-A 不暴露 user ranking 或 user score，非适用指标写 `not_applicable`，`scores={}`。CR-D 若启用个人榜必须另行设计/审批，不复用 CR-A API 偷开能力。

#### 2.3 既有数据源与 join 键

| 数据源 | CR-A 使用方式 |
|---|---|
| `member(workspace_id,user_id)` | v1 “活跃成员”定义为 rollup 时仍存在的 member 行；表无 active/status 历史，离组即删除。该限制写入指标定义页；快照固化后不追溯重算 |
| `task_usage` + `agent_task_queue` + `agent` | `task_usage.task_id=agent_task_queue.id`；队列表本身无 `workspace_id`，必须 `agent_task_queue.agent_id=agent.id AND agent.workspace_id=:workspace` 限租户；四列 Token 全计；`initiator_user_id` 归人；`project_id` 或 `issue_id→issue.project_id` 归项目 |
| `project` / `issue` / `comment` | CR 项目归属：`cr.shell_issue_id→issue.project_id`；评论者：`comment.issue_id=cr.shell_issue_id` 且 `author_type='member'`；Org Admin 系统项目通过 `project.settings.system_key` 排除业务项目分母 |
| `cr` + `cr_sync_event` | 先 `cr.workspace_id=:workspace`，再以 `cr.cr_id=cr_sync_event.cr_id` 读归档/状态时间；不可只按无 workspace_id 的 `cr_sync_event.cr_id` 裸查。`cr.owners` 当前是 crctl 自报的 free-text JSON；CR-A 不做名称匹配、不强转 UUID、不引入身份桥，只检测 unresolved owner 并按 §4.2.4 传播 unavailable |
| `pipeline_run` / `pipeline_node_run` | 以 `pipeline_run.workspace_id=:workspace AND pipeline_run.cr_id=cr.cr_id` 限租户；Review gate 与 4 pipeline 完成情况 |
| `approval_record` | 以 `workspace_id+cr_id+stage` join 审批；只计 `decision='approve'` |
| `activity_log` | `workspace_id` 限租户；`action='aifirst.evidence_drift'` 和 `action='aifirst.gitguard_denied'` |
| `agent_task_queue.result` + chat | E3 report envelope/server 查询投影与追问入口；不新增报告表 |

#### 2.4 配置声明与生成器

`maturity-config.yaml` 的精确类型如下；SDD 不发明实现阈值，具体数值只能由该声明文件提供：

```ts
type MetricConfig = { weight: number; floor: number; target: number }
type MaturityConfigV1 = {
  schema: 'ai-first.maturity-config/v1'
  observation_weeks: 4
  calibration_status: 'observing' | 'calibrated' // CR-D 人审后才能改 calibrated
  dimensions: {
    AIF: ['token_intensity', 'ai_penetration']
    SII: ['cr_throughput_per_capita']
    OFI: ['project_collab_scale', 'project_active_rate']
    EPC: ['prototype_direct_rate']
    ACM: ['team_agent_depth', 'process_completion_rate']
  }
  metrics: Record<MetricKey, MetricConfig> // 恰好覆盖 8 个固定 MetricKey
}
```

生成器硬校验：8 key 齐全且无未知 key；每项 `0<weight<=1`；`sum(weights)=1`（允许 `1e-9` 浮点误差）；`target>floor`；`observation_weeks=4`；`calibration_status∈{observing,calibrated}`。读取文本先 `\r\n→\n`；解析不到必填块直接 hard fail，不得降级为空；`--check` 重生成后字节 diff 非零退出。`config_rev` 由 `git -C <source-repo> rev-parse HEAD` 取得，若源文件相对 HEAD dirty/untracked 则生成器拒绝，避免 SHA 与内容不匹配。

成本优先使用既有 `task_usage.cost_usd_ticks`（provider-reported，单位 `1e-10 USD`）；仅对该列为 NULL 的 usage 行，用可选 `model-prices.yaml` 估算。该文件与 config 同仓、同生成器生成只读 price map；未知模型或文件缺失时未计价部分保持 `cost_usd=null,data_status='unavailable'`，UI 显示“估算不可用”，不得猜价格。最终成本 = authoritative ticks 换算值 + 仅针对 uncosted Token 的估算，严禁对已带 authoritative cost 的 Token 二次计价。改价目表同样走 CR + 生成副本。

---

### 3. 接口契约

#### 3.1 通用类型

所有端点注册在 `server/cmd/server/router.go` 的 **Auth + RequireWorkspaceMember** 受保护路由组内，位置靠近既有 `/api/dashboard`；不得注册到 `/api/config` 所在 public 区。请求用户必须属于 `X-Workspace-ID` 指定 workspace；query key 必含 `workspaceId`。日期为 Asia/Shanghai 自然日的 ISO `YYYY-MM-DD`；日期范围两端含、默认最近 28 天、最大 366 天。响应由 `packages/core/api/schema.ts` zod schema 解析，`parseWithFallback` 覆盖 malformed payload。

```ts
type MetricKey =
  | 'token_intensity' | 'ai_penetration' | 'cr_throughput_per_capita'
  | 'project_collab_scale' | 'project_active_rate' | 'prototype_direct_rate'
  | 'team_agent_depth' | 'process_completion_rate'
type DimensionKey = 'AIF' | 'SII' | 'OFI' | 'EPC' | 'ACM'
type GovernanceMetricKey =
  | 'gate_first_pass_rate' | 'evidence_drift_count' | 'traceability_complete_rate'
  | 'approval_latency_p50_ms' | 'approval_latency_p90_ms' | 'forbidden_attempt_count'
type Observation = {
  active: boolean
  calibration_status: 'observing' | 'calibrated'
  observation_weeks: 4
  first_bucket_date: string
  elapsed_days: number
}
type ApiError = { error: string; message: string; request_id: string }
```

通用错误：`401 unauthenticated`、`403 workspace_forbidden`、`500 internal_error`。空数据是 200 + 结构化 empty，不用 404。

#### 3.2 `GET /api/maturity/overall`

Query：`date?: YYYY-MM-DD`（缺省取该 workspace 最新 org bucket）。

```ts
type MaturityOverallResponse = {
  bucket_date: string | null
  config_rev: string | null
  observation: Observation | null
  headline: {
    active_members: number
    total_tokens: number
    cost_usd: number | null
    cost_status: 'authoritative' | 'mixed' | 'estimated' | 'unavailable'
  } | null
  total_score: number | null
  dimensions: Array<{
    key: DimensionKey
    score: number | null
    data_status: DataStatus
    metrics: Array<{ key: MetricKey; raw: MetricValue; score: number | null }>
  }>
  governance: Array<{ key: GovernanceMetricKey; datum: MetricValue }>
  data_status: 'ready' | 'empty'
}
```

观察期、`calibration_status!='calibrated'`，或任一计分 raw 非 ready/null（包括 unresolved owner）时 `total_score=null`、所有 score=null、raw 正常；不得临时重算或部分权重重归一化。

#### 3.3 `GET /api/maturity/token-trend`

Query：`dimension=project|user|model`，`dimension_id?: UUID|string`，`from?`，`to?`，`include_cost?: boolean`。project 可指定 id 或返回项目系列；**user 必须 `dimension_id=self`，未传或传任意用户 UUID 均返回 400 `unsupported_user_dimension`，绝不返回 all-user 系列**；model 可选具体 model。project/self-user 读 snapshot raw；model 明细按范围读 `task_usage`，只算 Token/成本，不生成成熟度分。

```ts
type TokenTrendResponse = {
  dimension: 'project' | 'user' | 'model'
  from: string
  to: string
  series: Array<{
    id: string
    label: string
    points: Array<{
      date: string
      tokens: number
      cost_usd: number | null
      cost_status: 'authoritative' | 'mixed' | 'estimated' | 'unavailable'
    }>
  }>
  data_status: 'ready' | 'empty'
}
```

无效日期/范围/维度返回 400 `invalid_query`；user 非 self 查询返回 400 `unsupported_user_dimension`。服务端测试断言任何响应都不能枚举、排序或返回其他用户 ID/姓名。

#### 3.4 `GET /api/maturity/rankings`

Query：`scope=project`（唯一合法值）、`date?`、`metric?: MetricKey|'total'`、`limit?:1..100`（默认20）、`cursor?: opaque`。观察期 UI 默认按选中 raw metric 排名；`metric=total` 且 scores 为空时 200 返回 item `value=null,data_status='unavailable'`，不伪造总分。

```ts
type ProjectRankingsResponse = {
  scope: 'project'
  bucket_date: string | null
  metric: MetricKey | 'total'
  items: Array<{
    rank: number
    project_id: string
    project_name: string
    value: number | null
    data_status: DataStatus
  }>
  next_cursor: string | null
  data_status: 'ready' | 'empty'
}
```

`scope=user` 或任意其他值返回 400 `ApiError{error:'unsupported_scope',message:'only project rankings are available'}`，`request_id` 填当前请求 ID；服务层没有 user rankings query，不能只靠 UI 隐藏。

#### 3.5 `GET /api/maturity/suggestions` 与 `/history`

server 查询完成态 `agent_task_queue.result` 中 `schema='ai-first.maturity-report/v1'` 的 envelope，不读取 daemon path。

```ts
type MaturityReport = {
  report_key: string                 // `${workspace_id}:${YYYY-Www}`
  week: string                       // ISO YYYY-Www
  generated_at: string               // RFC3339
  relative_path: string              // docs/org-admin/maturity-review-{YYYY-Www}.md
  markdown: string                   // 与落盘内容同 SHA-256
  content_sha256: string
  source_task_id: string
  chat_session_id: string            // “追问”跳转既有 Team Agent 对话
  config_revs: string[]
}
type SuggestionResponse = { latest: MaturityReport | null; data_status: 'ready'|'empty' }
type SuggestionHistoryResponse = {
  items: MaturityReport[]
  next_cursor: string | null
  data_status: 'ready'|'empty'
}
```

history query：`limit?:1..52`（默认12）、`cursor?:opaque`。重复 `report_key` 取 `completed_at` 最新且 SHA 有效的一条；目录文件仍保留，数据库不新增唯一约束。

#### 3.6 `GET /api/maturity/config`

```ts
type MaturityConfigResponse = {
  config_rev: string
  observation_weeks: 4
  calibration_status: 'observing' | 'calibrated'
  dimensions: Array<{ key: DimensionKey; metrics: MetricKey[] }>
  metrics: Array<{
    key: MetricKey
    weight: number
    floor: number
    target: number
    unit: MetricValue['unit']
    known_gameability: string
  }>
  price_config_rev: string | null
}
```

全员可读，无 Owner-only 分支；无 user ranking 开关字段。

#### 3.7 调度与报告 envelope 契约

- **快照 JobSpec**：`Name='maturity_snapshot'`、`Cadence:0`、`PlansForScope=maturityPlansForScope`、`MaxPlansPerTick:7`、`StaticScopes(global)`；timeout/retry/heartbeat 照抄 `AutopilotScheduleDispatchJob`。虽然声明保留 `CatchUpMode:CatchUpEveryPlan` 与 `CatchUpWindow:7*24h` 以表达业务意图，`scheduler.JobSpec` 明确规定：一旦设置 `PlansForScope`，这两字段**不参与规划**；真实补偿逻辑必须完全实现在 hook 内，不能把正确性归因给被忽略字段。
- **Hook 算法**：先用新增 sqlc 只读查询从既有 `sys_cron_executions` 取窗口内所有 retry-eligible 行：`job_name='maturity_snapshot' AND scope_kind='global' AND scope_id='global' AND status='FAILED' AND attempt<max_attempts AND next_retry_at<=now AND plan_time>now-7d`，oldest-first、limit 7；`latest.RetryEligible(now)` 必须包含在该集合（单测钉死）。再令 `after=latest.PlanTime`；若从无执行记录，则 `after=now-24h`，使首次部署只生成最近一个已到期 plan、不伪造上线前观察期；已有记录时令 `after=max(after,now-7d)`。调用 `NextOccurrencesUTC('30 0 * * *','Asia/Shanghai',after,now)` 得到新 occurrence；把 retry plan 与新 plan 去重合并、oldest-first，截到 7 个返回。这样同 tick 的较新 plan 成功后，较老 FAILED 也不会因不再是 latest 而永久搁浅。hook 直接返回 canonical UTC，不做 latest-only collapse。
- **PlanTime 语义**：每个 plan 只负责 `plan_time.In(Asia/Shanghai)` 所在本地日的**前一日** bucket；handler 不再从水位循环到“当前日”，避免 hook 与 handler 双重补偿。`MAX(bucket_date WHERE workspace_id=:workspace)` 仅作 target 已存在 no-op 判断；缺口由 hook 自己的 7 日枚举补齐。
- **周报 schedule**：Org Admin 项目每周一 09:00 Asia/Shanghai 触发（运营可在既有 Autopilot UI 改 cron）；复用 `sys_cron_executions(job_name,scope_kind,scope_id,plan_time)` 幂等。
- **Report result**：schedule enqueue 必须把 `agent_task_queue.project_id` 设为 Org Admin 项目 ID，并绑定该项目的 `chat_session_id`；任务结束返回 `result={schema,report_key,week,generated_at,relative_path,markdown,content_sha256,chat_session_id,config_revs}`。daemon 先原子写临时文件并 rename，再完成任务；server 验证 SHA 后持久化 result/chat。重试使用同一 `report_key`，API 以 `project_id + schema + completed_at/id` 查询并去重。

---

### 4. 关键算法与流程

#### 4.1 时间窗、租户与空分母统一规则

- `bucket_date=d`：Asia/Shanghai `[d 00:00, d+1 00:00)`，SQL 参数预先转换成 UTC `[from_utc,to_utc)`，所有 timestamp 过滤左闭右开。
- 每个 SQL 必须先建立租户边界：有 `workspace_id` 的表直接谓词过滤；无该列的 `agent_task_queue` 必须先 join `agent.workspace_id=:workspace`，无该列的 `cr_sync_event` 必须先 join 已限定 workspace 的 `cr`。
- “活跃成员数”v1 = rollup 时 `member` 当前行数（表无历史 active 字段）；“全体成员数”同义。`0` 分母返回 `value=null,data_status='empty'`，不做除零、不把 null 当 0。
- `agent_task_queue.initiator_user_id` 是 nullable/best-effort：NULL 行仍计入组织总 Token 和全部任务分母，但不归给任何 user，也不进入 distinct initiator 分子；每个相关 `MetricValue.attribution` 记录 attributed/unattributed/coverage。覆盖率低于 95% 时，所有依赖发起人归因的 user breakdown、AI 渗透率和协作参与人数均标 `data_status='unavailable'`；org Token 总量仍可 ready，不得用低覆盖数据输出看似精确的个人值。历史 terminal task 的 `project_id` 可能未回填，项目归属先 `q.project_id`、再 `q.issue_id→issue.project_id`；两者皆空则只计 org、不计 project。
- `cr.owners` 的 `owners.*.id` 在当前投影中来自 crctl `--caller`，是 free-text 而非可验证的 `member.user_id`。CR-A 不按名称匹配、不尝试 UUID 强转，也不新建跨仓身份桥。对窗口内归档 CR：存在非空 owner id 即记为 unresolved；`project_collab_scale` 的对应 scope/date 写 `value=null,data_status='unavailable',reason='cr_owner_identity_unresolved'`，评论者和任务发起者集合仍可作为诊断数据返回但不得填补该指标；org scope 受任一 unresolved owner 影响，project scope 只受该 project 的 unresolved CR 影响。该样本不进入基线分位数。
- 项目集合 = 该 workspace `project.status!='cancelled'` 且 `settings->>'system_key' IS NULL` 的业务项目；Org Admin 系统项目不进入成熟度分母。
- CR 项目归属 = `cr.shell_issue_id→issue.project_id`；无法归属的 CR 只计 org，不计 project。

#### 4.2 八项子指标（rollup 时计算并固化）

1. **Token 强度**：本地日内 `SUM(input_tokens+output_tokens+cache_read_tokens+cache_write_tokens) / member_count / 1天`；`task_usage.task_id=agent_task_queue.id`，并经 `agent_task_queue.agent_id=agent.id AND agent.workspace_id=:workspace` 限租户；按 `initiator_user_id` 归人、按 `COALESCE(agent_task_queue.project_id,issue.project_id)` 归项目；不读无 user 维的 `task_usage_hourly`。
2. **AI 渗透率**：同样先经 `agent.workspace_id=:workspace` 限租户；本地日内 `COUNT(DISTINCT initiator_user_id) / member_count`；“发起过”按 task `created_at`，不以最终成功状态过滤。
3. **人均 CR 吞吐**：本地日内首次进入 `archived` 的 distinct CR 数 / member_count；从 `cr_sync_event.event_kind='status' AND payload->>'to_status'='archived'` 取 `occurred_at`，先 join workspace-scoped `cr` 去重。
4. **项目协作规模**：对窗口内归档 CR 分别取 canonical user 集合并求人数，再平均：可验证的 owner user id（当前 CR-A 不存在该身份桥，故不填入）∪ `comment.author_id`（member only）∪ `agent_task_queue.initiator_user_id`（`q.cr_id=cr.cr_id OR q.issue_id=cr.shell_issue_id`）。project scope 再按 canonical `cr→issue.project_id` 过滤；人数 `<2` 的 raw 仍存，计分由配置 floor/target 使其不加分。若该 scope/date 的归档 CR 存在非空 `cr.owners.*.id`，因 owner 身份 unresolved，整个该 scope/date 的 `MetricValue` 固化为 `value=null,data_status='unavailable',reason='cr_owner_identity_unresolved'`，不得以评论者/任务发起者子集伪造完整值；org scope 任一归档 CR 命中即 unavailable，project scope 按所属 project 独立传播。
5. **项目活跃率**：近 14 个本地自然日内存在 task `created_at` 或 CR status `occurred_at` 的 distinct 业务 project / 全部业务 project；任务项目优先 `q.project_id`，缺失时 `q.issue_id→issue.project_id`；CR 项目走 shell issue。
6. **原型直出率**：当期归档 CR 中，**全部已投影 review gate**（`requirement`、`tech-design`、`code`，对应 `governance.ReviewGateNodes`）均在 `attempt=1,status='passed'` 的 CR 数 / 当期归档 CR 数。不是 passed node/全部 node；缺任一必需 review gate 即不计一次通过。
7. **Team Agent 使用深度**：先以 `agent.workspace_id=:workspace` 限租户；当期 `agent_task_queue` 中 `(cr_id IS NOT NULL OR issue_id IS NOT NULL)` 的任务数 / 全部任务数；按共享队列来源键，**不用 `pipeline_node_run_id` 替代 `issue_id`**。
8. **流程完整率**：当期归档 CR 中同时存在 status=`completed` 的 4 个 `pipeline_run.pipeline_id`：`requirement-authoring`、`architecture-design`、`code-implementation`、`feature-writeback` 的 CR 数 / 当期归档 CR 数。

#### 4.3 治理护栏（存入 org snapshot，不进总分）

| key | 口径 | 可用性 |
|---|---|---|
| `gate_first_pass_rate` | 当期 completed review gate 中 attempt=1 且 passed / 当期 completed review gate 数 | 当前 ready |
| `evidence_drift_count` | `activity_log.workspace_id=:ws AND action='aifirst.evidence_drift' AND created_at∈window` | 当前 ready |
| `traceability_complete_rate` | `traceability.yml` 五段齐全的归档 CR / 归档 CR | **CR-C trace event 通道未交付前 unavailable**，reason=`trace_channel_pending_cr_c`；CR-A 不扫描 daemon/git、不实现 CR-C |
| `approval_latency_p50_ms` / `p90` | 对当期 approval：对应 stage review node `completed_at` → `approval_record.created_at` 的正时长分位数 | 当前 ready；无样本 empty |
| `forbidden_attempt_count` | `activity_log.workspace_id=:ws AND action='aifirst.gitguard_denied' AND created_at∈window` | 当前 ready |

UI 始终渲染 6 个字段（审批时延 P50/P90 可合并一张卡）；unavailable 显示“未测量/数据通道待 CR-C”，不显示 0，不影响 `total_score`。

#### 4.4 计分与观察期

```text
metric_score_i = clamp(100 * (x_i - floor_i) / (target_i - floor_i), 0, 100)
dimension_score_d = Σ(metric_score_i * metric_weight_i) / Σ(metric_weight_i in dimension d)
total_score = Σ(metric_score_i * metric_weight_i)  # 全局 weight 和=1
```

`observation_active = elapsed_days < 28 OR calibration_status != 'calibrated'`。只要为 true，rollup 写 `scores={}`。校准后若某 scope/date 的任一计分指标不是 `ready` 或其 value 为 null（包括 `project_collab_scale` 的 unresolved owner），该 scope/date 仍保留完整 raw metrics，但整体写 `scores={}`，不做部分权重重归一化。第 4 周基线对每个 MetricKey 只取**首个连续 28 个 org snapshot 的 ready raw value**，忽略 null/empty/unavailable；样本少于 21 个时该指标建议为 unavailable。样本充足时用 PostgreSQL `percentile_cont(0.10)` 与 `percentile_cont(0.75)`（线性插值）分别得到 floor/target 建议；若 `P75<=P10` 则标记 degenerate_distribution、不得给可写值。建议只进报告，不写 config。CR-D 人审配置改为 calibrated 后，**仅新 bucket** 写分数；旧行保持 `{}`，趋势跨 `config_rev` 标断点。

#### 4.5 Rollup 事务与幂等

```text
GlobalHandler(planTime):
  list active workspaces in stable ID order
  for each workspace call RollupWorkspace(planTime, workspace)
  # 每 workspace 独立事务；前序成功、后序失败时任务整体报错，重试对前序 workspace 按水位 no-op

RollupWorkspace(planTime, workspace):
  target = previousLocalDate(planTime, Asia/Shanghai)
  BEGIN
  pg_try_advisory_xact_lock(hash('maturity_snapshot', workspace)) or return retryable-busy
  if MAX(bucket_date WHERE workspace_id=workspace) >= target: COMMIT no-op
  compute all org/user/project SnapshotMetricsV1 for target
  validate metric keys/status/config_rev
  scores = observation_active || anyScoringMetricUnavailable(metrics) ? {} : Score(metrics, generatedConfig)
  INSERT rows with ON CONFLICT (workspace_id,bucket_date,scope,scope_id) DO NOTHING
  assert org row inserted-or-existed and all planned scope rows are valid
  COMMIT
```

- 同一 workspace+target 的所有 scope 行在一个事务；任一 SQL/JSON 校验失败则该 workspace 全部回滚，`MAX(bucket_date)` 不前移。不同 workspace 不做跨租户大事务；任务重试靠已成功 workspace 的水位 no-op 收敛。
- handler 每 plan 只写一个 target；停机 3 天由 scheduler 枚举 3 个 plan，最多 7 个，不在 handler 二次扩窗。
- 历史不可变：常规路径禁止 `DO UPDATE`；配置变化只影响后续行。

#### 4.6 Org Admin 初始化与周报闭环

- `project.settings.system_key='org-admin-workspace'` 作为逻辑幂等键；初始化事务按 workspace 取 advisory lock，SELECT 后 INSERT，避免标题重名误认。项目无新增列/索引。
- Agent `system_key='org-admin'`，复用 `CreateMikaAgent` 的 `(workspace,owner,runtime,system_key)` 幂等语义；项目 lead 指向该 Agent。
- 部署/首次使用通过既有 project-resource API 为项目绑定 `type='local_directory'`（daemon_id + local_path）。未绑定时周报状态为 unavailable 并在 UI 给出现有绑定入口，不假装已生成。
- schedule task 写 `docs/org-admin/maturity-review-{YYYY-Www}.md`，模板固定为个人效率/团队交付/知识复利/风险收益/成本五节；第 4 周附 8 项 P10/P75 建议。
- 完成 envelope 进入 `agent_task_queue.result` 与 assistant chat；建议 API 从 result 读，追问按钮用 `chat_session_id` 进入既有 Team Agent 消息流。

---

### 5. 技术选型与替代方案

| 决策 | 选择 | 否决方案与原因 |
|---|---|---|
| 配置消费 | knowledge-base yaml → 零依赖生成器 → committed Go（CRLF 规范化、hard fail、dirty guard、`--check`） | runtime 读 sibling repo：破坏独立构建；手维版本号：易漂移 |
| 快照主键 | 375 表、376 unique concurrent、377 PK using index、378 query index | inline PRIMARY KEY：隐式非 concurrent index，违反 CLAUDE.md |
| 调度 | `Cadence:0 + PlansForScope`；hook 自己实现 retry-eligible + 7日 oldest-first 枚举，manager 以 MaxPlansPerTick=7 截断；每 plan 一日 | 依赖 CatchUpEveryPlan/CatchUpWindow：设置 hook 后两字段被 scheduler 忽略；固定24h：本地时区漂移；LatestOnly：永久缺桶；handler再循环：双重补偿 |
| 历史读取 | rollup 固化 metrics/scores；overall/ranking/report 读 snapshot | 读时重算分数：口径变更会改写历史，是建快照表要解决的问题 |
| 报告跨进程 | daemon 写文件 + 既有 task result/chat 回传；API 读 DB envelope | server 直读 daemon `local_directory`：跨进程/跨机器不可达；新增报告表：违反唯一新表 |
| 治理追溯 | CR-C 前显式 unavailable | CR-A 扫 git/新增 trace event：侵入 CR-C 边界且重复建设 |
| 成本 | provider `task_usage.cost_usd_ticks` 优先；仅 NULL 行用 knowledge-base `model-prices.yaml` 生成价目估算，未知=null | 对全部Token统一估算：会覆盖/重复计算权威成本；硬编码/猜价：不可治理且误导 |
| CR owner 归因 | 不匹配名称、不强转 UUID；检测 free-text owner 并将受影响 `project_collab_scale` scope/date 标 `unavailable`，样本跳过基线 | 在 CR-A 新建 owner→member 身份桥：扩大 crctl 事件协议、历史回填和跨仓治理边界，应另立 CR |

---

### 6. FR 到技术实现映射

| FR | 技术实现 |
|---|---|
| FR-1 | §2.4 `maturity-config.yaml` schema + generated Go；权重/阈值/观察期集中 |
| FR-2 | `server/internal/maturity/gen/generate-config.mjs`：CRLF→LF、结构 hard fail、dirty guard、`--check` |
| FR-3 | source repo clean HEAD SHA 写 `config_rev`；每行固化 |
| FR-4 | §2.1 迁移 375–379；技术补充 `workspace_id` 租户键；无 FK；379 为E3 completed report history索引 |
| FR-5 | §3.7 JobSpec + hook 精确算法：retry-eligible、7日 oldest-first、MaxPlansPerTick=7、Asia/Shanghai、global scope；不依赖被忽略的 CatchUpMode/Window |
| FR-6 | §4.5 workspace advisory lock、单日 bounded plan、单事务、`MAX(bucket_date)` no-op 水位 |
| FR-7 | §1.3/§4.4 历史不可变、观察期 `{}`、config 断点 |
| FR-8 | 一 plan 一事务，内部遍历 org/user/project，调度器不展开用户 scope |
| FR-9 | 看板头部显示范围、Owner mode、`每日00:30更新前一日`、data_status |
| FR-10 | 统计条读 snapshot；authoritative cost 优先、可选 prices 只估算 uncosted Token，未知 cost=null/“估算不可用” |
| FR-11 | §3.3 project/user snapshot 趋势 + model raw Token 明细；不重算分数 |
| FR-12 | §3.4 仅 project query，user scope 服务端 400 |
| FR-13 | maturity view 复用 `packages/views/dashboard/components/` 三件式；观察期无雷达 |
| FR-14 | §4.2 精确 8 公式、字段、窗口、空分母、项目映射；`cr.owners` unresolved 时 project_collab_scale 按 scope/date 固化 unavailable；§4.4 计分 |
| FR-15 | §4.3 6 字段三态治理护栏，trace CR-C 前 unavailable，全部不进总分 |
| FR-16 | 数量/质量成对布局、定义页公开 v1 member 口径与可刷性、页脚反 Goodhart |
| FR-17 | §3.2–§3.6 精确 request/response/error/empty 合同 |
| FR-18 | `packages/views` 共享 route + Web/Desktop platform wiring；无 iframe/新写通路 |
| FR-19 | §4.6 project.settings system key + Agent system_key 幂等初始化、local_directory 绑定 |
| FR-20 | §3.7/§4.6 周 schedule、文件落盘、result/chat 回传、inbox 通知 |
| FR-21 | §4.6 五节模板，每节引用 snapshot/governance 指标 |
| FR-22 | §3.5 从 result envelope 渲染最新/历史，目录文件为原文 |
| FR-23 | report envelope 返回 chat_session_id，追问进入既有 Team Agent 对话 |
| FR-24 | 第4周按8项四周分布算 P10/P75，仅报告建议、不写 config |

FR 覆盖率：**24/24**。

---

### 7. 安全、性能与测试设计

#### 7.1 安全与性能

- **租户隔离**：snapshot 物理键含 `workspace_id`；全部原始表 query 先限定 workspace；`cr_sync_event` 必须经已限定的 `cr` join；query key 含 workspaceId。
- **隐私/反 Goodhart**：无 user ranking SQL/API/UI/开关；Token 为行为数据非绩效；user snapshot 不暴露个人 score。
- **数据库安全**：无新 FK；每索引 CONCURRENTLY 单文件；advisory lock 按 workspace，避免不同 workspace 相互阻塞。
- **查询成本**：overall/ranking 只读日快照；report history 用 migration 379 的 `(project_id,completed_at DESC,id DESC)` partial index，不能误用仅覆盖 active task 的 migration 369 索引；原始表大范围聚合只在每日 rollup 和 model 明细发生。API 日期最多 366 天、ranking limit≤100、history limit≤52。
- **成本完整性**：`cost_status=authoritative` 表示全部 usage 有 provider ticks；`mixed` 表示一部分 authoritative、其余全部被价目覆盖；`estimated` 表示无 authoritative 但全部可估；只要仍有未知模型的 uncosted Token，`cost_status=unavailable` 且 `cost_usd=null`，不展示不完整小计。
- **兼容性**：新增响应 additive；zod enum 有 fallback；desktop 对未知字段容忍；空/不可用是显式状态。
- **代码治理**：所有注释英文；实现涉及 migration、scheduler、handler/service、builtin skill、前端 route/组件、生成器，逐项登记 multica `CUSTOM.md`，编号/表格格式以实施时文件现状为准。

#### 7.2 可执行测试矩阵

| 范围 | 测试落点/方式 | 必须证明 |
|---|---|---|
| 配置生成器 | Node 单测 + `--check` CLI fixture | LF/CRLF 同输出；缺块/未知key/weight和≠1/target≤floor hard fail；dirty source 拒绝；漂移非零；clean source SHA 入头 |
| 迁移 | `server/internal/migrations` lint + 真实 PostgreSQL up/down/up + EXPLAIN | 375 无隐式 index；376 unique concurrent；377 PK using index；378 snapshot query index；379 completed report partial index；无 FK；org sentinel CHECK；重复逻辑键失败；history query命中379而非369 active index |
| 计分纯函数 | `server/internal/maturity/score_test.go` table-driven | floor/target/夹断/浮点边界；8→5→total；observing 返回空 scores；缺 key 或任一计分 raw 非 ready/null 时拒绝，rollup 固化空 scores |
| 8 项 SQL | `server/internal/service/maturity_test.go` PostgreSQL fixtures | 四类 Token 含 cache_write；workspace 隔离；member=0 空态；CR→project join；EPC 三 review gate attempt=1；Team Agent 用 cr_id/issue_id；4 pipeline 完整率；free-text owner 不做名称匹配/UUID 强转，命中时 project_collab_scale 按 org/project scope 写 unavailable |
| 治理 | DB fixtures | 两个 activity action 精确计数；审批 P50/P90；CR-C 前 trace unavailable≠0；治理不改变 total |
| Scheduler | fixed DB clock/Asia-Shanghai + sys_cron fixtures | latest失败返回同plan；较老FAILED+较新SUCCESS仍重试老plan；首次仅最近一个已到期plan；停3天合并返回3plan；超7天仅窗口内最多7个；00:30→前一日；同plan no-op；断言CatchUpMode/Window不参与hook规划 |
| Rollup | 真实 PG 并发/故障注入 | 同 workspace 双执行只一组行；不同 workspace 并行；中途失败全回滚；重跑不改历史；配置变更仅新行 rev 变化 |
| API | handler/service tests | 完整 schema；401/403；invalid range 400；user rankings 400；观察期 total null；empty 200；cursor/limit；任何 query 不跨 workspace |
| Core schema | Vitest zod malformed fixtures | 每个端点正常/缺字段/错误枚举/新增字段；`parseWithFallback` 不崩溃 |
| UI | views component tests | loading/empty/error/unavailable；观察期无雷达；项目排名无个人入口；数量与治理同屏；跨 config_rev 断点 |
| E3 | service + daemon integration | 未绑 local_directory 显式 unavailable；同 ISO week 重试 API 仅一报告；落盘 SHA= result markdown SHA；周报4/4；第4周8项建议且 config 零写入；chat_session_id 可追问 |
| CUSTOM | repo test/人工 diff gate | 所有 `// AIFIRST:` 挂钩点、新 migration/生成器/自研模块在 `CUSTOM.md` 可追溯 CR-2026-047/TASK |

#### 7.3 AC 到验证项映射

| AC | 验证项 |
|---|---|
| AC-1 | 配置类型/8 key/weight/floor/target/观察期校验；`config_rev` 等于 clean source HEAD SHA |
| AC-2 | 生成器 `--check` 一致为 0、漂移非 0；生成文件头含源 SHA |
| AC-3 | 迁移 375–379 真实 PG up/down/up；仅新增 snapshot 表、无 FK、所有索引 concurrent 单文件；租户前缀后的业务键满足 FR-4；EXPLAIN证明report history命中379 |
| AC-4 | fixed clock 跨 00:30 仅产生前一日 global plan；事务内写三 scope，cron scope 不按用户/项目增长 |
| AC-5 | 同桶重跑/双并发/故障注入，验证唯一行、advisory lock 与全事务回滚 |
| AC-6 | 连续 3 天 metrics 完整/scores 空；改 config 后只新行 rev 变化；历史摘要不变且 API 返回 revision 断点 |
| AC-7 | hook fixed-clock：首次仅最近plan；停机3天补3plan；超过7天只补窗口内最多7plan；latest/非latest retry-eligible FAILED 均返回原PlanTime |
| AC-8 | 首屏断言日期/Owner mode/更新说明/成员/Token；provider成本标authoritative，混合成本标mixed，纯估算标estimated，未知价空态 |
| AC-9 | project/self-user snapshot 与 model raw 三组 fixture，日期总量守恒；user非self/全量枚举均400且响应不含他人ID |
| AC-10 | route、DOM、API/service 均无 user ranking/开关/通知；user scope 400 |
| AC-11 | observing fixture 断言无雷达，仅三件式组件 |
| AC-12 | 8 公式逐项 DB fixture + score 0/100/线性边界 + total 只含 8 项；owner unresolved fixture 断言 org/project 协作规模不可用且不进入 baseline |
| AC-13 | 5 类治理卡（6 字段）ready/empty/unavailable；修改治理值不改变 total |
| AC-14 | Token 与质量护栏同屏；定义页含 8 项可刷性；页脚含非绩效声明 |
| AC-15 | 6 个 HTTP 合约的 schema/status/auth/empty 测试；config 全员可读；user rankings 不泄露 |
| AC-16 | Web/Desktop route smoke test；复用 views；无 iframe/独立域名 |
| AC-17 | 初始化两次后 project.settings system key 与 Agent system_key 各唯一一行 |
| AC-18 | 周任务生成同周唯一 report_key/文件/result/inbox；文件未进入 git |
| AC-19 | 报告五节均存在并各引用对应指标 key |
| AC-20 | suggestions 最新/历史按 ISO week 排序；无报告 200 empty |
| AC-21 | report chat_session_id 连续两轮追问仍带报告上下文 |
| AC-22 | 首28个org日样本按ready过滤，≥21时 percentile_cont P10/P75、退化分布显式不可用；8项建议生成前后 config 字节与 HEAD SHA 不变 |

无未映射 AC。

### 8. Prompt 采纳影响

本 CR 不触及 `skills/shared/crctl/scripts/crctl.mjs` dispatch 或 `skills/shared/controlled-shell/rules.json#protectedPaths.deny`，无需列 skill prompt 采纳清单；本维度按条件跳过。

## P3 组织智能 CR-B：内部 Skill Market（E6）（v0.22 · CR-2026-048）

## SDD — CR-2026-048 内部 Skill Market 技术设计

> 依据：`change-requests/CR-2026-048/prd.md`（23 FR / 16 AC）、multica `ARCHITECTURE.md`（已存在，直接引用其第 4/5 节依赖方向与硬不变式）。
> 设计取向（用户明确指令）：**复用现有能力 > 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码**。每处选型按此阶梯决策，新增代码只出现在"没有现成件可用"的接缝上。

### 1. 架构概览

改动全部落在 multica 仓，分六个接缝，每个接缝都钉在既有结构上：

```text
[认领路径] handler/daemon.go buildClaimedTaskResponse（useSkillRefs 分支）
   └─ 已算出的 skillRefs ──> 循环 INSERT skill_usage_event（best-effort，不阻断认领）

[发布路径] handler/skill.go UpdateSkill（唯一写入口，不加新 route）
   └─ visibility private→org 时调 internal/skill.PublishGate（纯函数）
        ├─ ParseSkillMetadata（扩展既有 frontmatter 解析）
        ├─ redact.Findings（扩展既有 patterns，零新正则表）
        └─ 失败 → 422 结构化 findings；成功 → 同一事务更新 skill 行

[申诉] 2 个新端点 POST /api/skills/{id}/appeals[/decide]
   └─ activity_log 记账（复用既有表 + 封闭 action 白名单模式），appeal_id=内容哈希绑定

[Market 读] 1 个新端点 GET /api/skills/market
   └─ 新 sqlc 聚合查询（join agent_task_queue status=completed，按 skill_ref 去重计数）

[数据面] 迁移 380–383（三列 + 一表 + 两索引，各文件一条 CONCURRENTLY 索引）

[前端] packages/views/skills 既有 SkillsPage / SkillDetailPage 扩展（不新增页面/路由）
```

依赖方向遵守 ARCHITECTURE.md 第 4 节：handler → service/queries；`internal/skill` 纯函数包被 handler 调用；`packages/views` 只消费 `packages/core` 的查询方法。不新建事务/队列/outbox 抽象（PRD §7 已排除）。

### 2. 数据模型

#### 2.1 迁移（编号从 380 起，CR-2026-047 已占 375–379）

| 迁移 | 内容 | down |
|---|---|---|
| `380_skill_visibility` | `ALTER TABLE skill ADD COLUMN visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','org')), ADD COLUMN version TEXT NOT NULL DEFAULT '0.1.0', ADD COLUMN owner_actor TEXT` | 三列 DROP |
| `381_skill_usage_event` | 建表（见下，含 `workspace_id` 租户键） | DROP TABLE |
| `382_skill_usage_event_task_id` | `CREATE INDEX CONCURRENTLY skill_usage_event_task_id_idx ON skill_usage_event(task_id)` | DROP INDEX CONCURRENTLY |
| `383_skill_usage_event_scope` | `CREATE INDEX CONCURRENTLY skill_usage_event_scope_idx ON skill_usage_event(workspace_id, skill_ref, used_at)` | DROP INDEX CONCURRENTLY |
| `384_skill_appeal_activity_index` | `CREATE INDEX CONCURRENTLY skill_appeal_activity_idx ON activity_log ((details->>'appeal_id')) WHERE action IN ('skill_appeal_submitted','skill_appeal_approved','skill_appeal_rejected')` | DROP INDEX CONCURRENTLY |

- 382/383/384 各自独立文件、各一条索引语句（仓规约）；并**同步注册** `cmd/migrate/main.go` 的 `concurrentIndexCleanups` 与 `concurrentDownIndexCleanups` 两个 map（CR-2026-047 对 376/378/379 的同款处理，`TestEveryConcurrentUpBuildHasCleanup` 会强制校验）。
- **无外键**：`skill_usage_event.task_id`/`skill_ref` 均无 FK（PRD FR-2，仓硬规则）；`workspace_id` 同样不加 FK。
- **384 的先例**：迁移 089 已在 `activity_log` 上建过 `((details->>'task_id'))` 表达式部分索引，本条照抄同一形制，不发明新存储。

```sql
CREATE TABLE skill_usage_event (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,     -- 租户键（硬不变式 1）；agent_task_queue 无此列，因此必须自带
    skill_ref TEXT NOT NULL,        -- workspace skill 的 uuid 文本，或 'builtin:<name>'
    task_id UUID,                   -- 无 FK：append-only 审计行，指向已删 Skill 的历史行应保留
    project_id UUID,
    used_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`workspace_id` 的数据来源是现成的：`buildClaimedTaskResponse` 签名已带 `runtimeWorkspaceID string` 形参，直接落列，**零额外查询**。不靠 `agent_task_queue` 反查——该表只有 `agent_id`/`issue_id`/`project_id`（`project_id` 由迁移 368 加入），没有 workspace 列。

#### 2.2 申诉账本 = activity_log（不建新表）

`activity_log`（001_init）已有全部所需列（workspace_id/actor_type/actor_id/action/details JSONB）。申诉三种行用三个封闭 action 值：

- `skill_appeal_submitted`（作者提交）——details: `{appeal_id, skill_id, content_hash, file, line, pattern_id}`
- `skill_appeal_approved` / `skill_appeal_rejected`（Owner 逐条决定）——details: `{appeal_id, decided_by, ...}`

`appeal_id = sha256(skill_ref | content_hash | file | line | pattern_id)`（十六进制）。内容哈希复用 `skillbundle.BuildManifest(skill).Hash`（`server/pkg/skillbundle/hash.go:43`，标准库 sha256，上游已用于包变更判定）——不新写哈希。**内容变更自动使旧放行失效**：发布门禁每次对当前内容重算 hash，旧 appeal_id 必然不再命中，无需任何失效代码。

幂等 = 提交前 `SELECT` 已有同 `appeal_id` 行则 no-op；极端并发下的重复行由 activity_log 的 append-only 审计语义容忍（与 `governance.ingestAudit` 注释明示的 crash-window 重复同款先例）。

**查找路径必须走索引**：activity_log 现有索引全部以 `issue_id` 打头（068 的 `idx_activity_log_issue_keyset`、089 的 `idx_activity_log_squad_no_action_task`），而申诉行 `issue_id` 为 NULL——不建专用索引则退化为热表全表扫描。因此迁移 384（§2.1）是本方案的必需项，不是优化项；验收同样用 `EXPLAIN (FORMAT JSON)` 固定 fixture 断言命中。

### 3. 接口契约

#### 3.1 UpdateSkillRequest 扩展（发布 = 复用既有更新端点）

```go
type UpdateSkillRequest struct {
    // ...既有字段不动
    Visibility *string `json:"visibility"` // 仅接受 "private" | "org"
    OwnerActor *string `json:"owner_actor"`
    Version    *string `json:"version"`    // 纯展示，不参与内容身份
}
```

`UpdateSkill` sqlc 查询对应加三列 `COALESCE(sqlc.narg(...))`。**门禁触发条件（两条，缺一则有绕过口）**：

1. `skill.Visibility='private'` 且请求置 `org`——发布时首次把关；
2. `skill.Visibility='org'` 且本次请求改变 `content` 或 `files`——**发布后的内容更新重扫**，否则密钥可以在发布之后夹带进组织可见资产（US-2/NFR-4 隐私红线）。

其余情况（org→private、仅改 version/描述、私有 Skill 编辑）零额外行为——私有创建/编辑路径完全不动。**同一条规则适用于 runtime-local 覆盖导入路径**（`canOverwriteSkillByLocalImport`）：该路径也会改写 org Skill 的 content/files，必须调同一个 `PublishGate`（复用同一函数，不新增机制）。

#### 3.2 发布门禁失败响应（422）

```json
{
  "code": "skill_publish_blocked",
  "reasons": ["frontmatter_name_missing", "owner_actor_missing", ...],
  "findings": [
    {"file": "SKILL.md", "line": 12, "pattern_id": "github_token",
     "excerpt": "api_key=[REDACTED GITHUB TOKEN]  ← 已经 Text() 脱敏，绝不含明文"}
  ],
  "warnings": ["permission_declaration_touches_protected_paths"]
}
```

#### 3.3 新端点（skill 路由组内，鉴权沿用既有 requireWorkspaceRole）

| 端点 | 权限 | 行为 |
|---|---|---|
| `POST /api/skills/{id}/appeals` | canManageSkill（作者或 admin） | body `{file, line, pattern_id}`；计算 appeal_id，幂等写 `skill_appeal_submitted` |
| `POST /api/skills/{id}/appeals/decide` | workspace owner/admin | body `{appeal_id, approve: bool}`；写 `skill_appeal_approved/rejected`；非 owner 403 |
| `GET /api/skills/market` | 工作区成员 | 见下（**只返回调用方当前 workspace 内 `visibility='org'` 的 skill + builtin**） |

Market 响应（一次请求给全排行）：

```ts
type SkillMarketResponse = {
  workspace: { id, name, description, version, owner_actor, visibility, usage_count }[]
  builtin:   { name, description, usage_count }[]   // 来自 TaskService.BuiltinSkills()
}
```

workspace 部分由新 sqlc 聚合查询产生（按认证上下文的 workspace 过滤 + `visibility='org'`）；builtin 部分用 `loadBuiltinSkills()`（既有）列出名称/描述，usage 同样只统计该 workspace 内 `skill_ref='builtin:<name>'` 的行。请求体里的任何 workspace 标识一律不取信（硬不变式 1）。

#### 3.4 frontmatter 解析扩展

`internal/skill/frontmatter.go` 现有 `ParseSkillFrontmatter` 已把整个 frontmatter 解进泛型 map（内部 `coerceFrontmatterValue`）。**新增**：

```go
type SkillMetadata struct {
    Name, Description string
    Fields map[string]string // 全部标量字段（元数据卡四字段、source、requirements 等）
}
func ParseSkillMetadata(content string) SkillMetadata
```

`ParseSkillFrontmatter` 保留为薄包装（现有调用方零改动）。四字段（`applicable-scenarios`/`context-dependencies`/`permission-declaration`/`failure-handling`）、`source: session-export` 标记、运行时要求标签全部从 `Fields` 读取——**零新列、零新解析器**。

### 4. 关键算法与流程

#### 4.1 认领遥测（buildClaimedTaskResponse，handler/daemon.go:2067）

```text
useSkillRefs 分支内，resp.Agent.SkillRefs = skillRefs 之后：
for _, ref := range skillRefs:
    INSERT skill_usage_event(workspace_id, skill_ref, task_id, project_id)
    ← workspace_id = runtimeWorkspaceID（函数形参，现成）
    ← skill_ref = ref.ID（workspace 为 uuid 文本；builtin 为 "builtin:<name>"，BuildAgentSkillBundles 已合成，零转换）
任何写入错误：slog.Error，不触碰 claim 结果（遥测是观测面，不是门禁）
```

两个调用方都是认领端点（`ClaimTasksByRuntime` 批量 / `ClaimTaskByRuntime` 单条），不存在非认领路径误写。插入点位于 `claimResponseAgentIdentityMatches` 校验**之前**，因此构建后被跳过/取消的任务也会留下遥测行——这类任务永远到不了 `completed`，§4.3 的过滤自然把它们排除，**不要为此加补偿逻辑**。

每 claim 一轮写一次（重试=再 claim=再加行），`used_at` 语义"派发时物化"。查询侧去重（§4.3）保证计数正确。循环单行 INSERT，任务典型 <10 个 Skill，不加批处理框架。

#### 4.2 发布门禁（internal/skill/publish_gate.go，新纯函数）

```text
PublishGate(skill 行, 请求增量, 全部 skill_file 内容) → (findings, reasons, warnings)
触发：private→org（首次发布），或 visibility 已是 org 且本次改 content/files（发布后重扫）
1. 有效 content = req.Content ?? skill.Content
2. meta = ParseSkillMetadata(content)
   ├─ meta.Name / meta.Description 空 → reason frontmatter_name_missing / frontmatter_description_missing
   ├─ 四字段任一空 → reason metadata_<field>_missing
   └─ meta.Fields["permission-declaration"] ∩ protectedPaths 非空 → warnings（不阻断）
3. owner = req.OwnerActor ?? skill.OwnerActor；空 → reason owner_actor_missing
4. findings = redact.Findings(content) ∪ ⋃ redact.Findings(each skill_file.content)
   （超集扫描：现有文件全扫 + 请求替换文件全扫，零簿记）
5. findings 非空 → 阻断，返回每处 {file, line, pattern_id, 脱敏 excerpt}
6. 任一 finding 存在 appeal_id 的 skill_appeal_approved 行 → 该条放行（按条，不是整包）
```

`protectedPaths` 以门禁包内常量维护（`change-requests/`、`specs/`、`delivery/`、`docs/`、`dir-graph.yaml`、`AGENTS.md`），注释标明权威源是 tools 仓 `skills/shared/controlled-shell/rules.json#protectedPaths.deny`，以门禁测试与 tools 清单对拍防漂移。服务端进程内没有 tools checkout，不发明跨包读取通道。

#### 4.3 使用量聚合（新 sqlc 查询）

```sql
-- MarketSkillUsage :many
SELECT e.skill_ref, COUNT(DISTINCT e.task_id) AS usage_count
FROM skill_usage_event e
JOIN agent_task_queue t ON t.id = e.task_id
WHERE e.workspace_id = $1 AND t.status = 'completed'
GROUP BY e.skill_ref;
```

重复 claim 行按 `task_id` 去重；最终失败任务整体不进计数（join + status 过滤）；跨工作区不混算（`workspace_id` 过滤，硬不变式 1）。走 `(workspace_id, skill_ref, used_at)` 索引；`EXPLAIN (FORMAT JSON)` 固定 fixture 断言（AC-15）。

#### 4.4 redact.Findings（server/pkg/redact，扩展而非平行）

- 每个 `secretPattern` 加 `name` 字段（16 条既有 + 新增第 17 条 `personal_path`：`/Users/<x>`、`C:\Users\<x>`、`/home/<x>`）——**同一份 `patterns` 变量**，`Text()` 与新函数共用。
- `Findings(s string) []Finding`：按行切分，逐行跑 patterns 的 `FindStringIndex` 取行号；`excerpt = Text(line)` 截断到 ~120 字符——直接复用 `Text()`，响应天然无明文（NFR-4）。
- 单一定义防平行表：patterns 保持未导出 + 测试断言 17 条且 name 唯一非空（AC-10 的可行形态；"无第二份正则表"同时靠 code review 以 diff 为证）。

### 5. 技术选型与替代方案（按阶梯逐条记录）

| 决策 | 选的 | 否决的替代 | 阶梯位置 |
|---|---|---|---|
| 遥测写入 | claim 路径循环单行 INSERT（sqlc 既有生成模式） | 批处理/COPY/新 outbox 表 | 已有依赖（sqlc）> 最小新增 |
| 遥测表 | 1 张 append-only 表 + 2 索引 | 物化视图/分区表 | YAGNI，数据量按任务×Skill 同阶 |
| 内容哈希 | 复用 `BuildManifest().Hash` | 新写哈希函数 | 复用现有能力 |
| 敏感扫描 | 扩展 `redact` 同份 patterns | 新正则表/引入检测库 | 复用现有能力（新依赖=阶梯最底） |
| 申诉账本 | `activity_log` + 封闭 action + 迁移 384 部分表达式索引（照抄 089） | 新 appeal 表 | 复用现有能力 |
| 遥测租户键 | 表内 `workspace_id` 列（claim 形参现成） | join agent→workspace 反查 | 一列换一次 join，且 agent_task_queue 无 workspace 列 |
| 发布后重扫 | 同一 `PublishGate` 多一个触发条件 | 定时全量扫描/独立扫描服务 | 一个条件判断，零新机制 |
| 发布入口 | 扩展 `UpdateSkill` | 新 /publish 端点 | 复用现有能力 |
| 内容变化使放行失效 | 哈希绑定自然失效 | 失效扫描任务 | 零代码（不做） |
| frontmatter | 扩展既有解析器（泛型 map 已就位） | 新解析库 | 复用现有能力 |
| 排名去重 | 查询侧 `COUNT(DISTINCT task_id)` | 采集侧幂等键/upsert | 一个 WHERE/GROUP BY 换掉跨进程复杂化 |
| 前端 | 扩展既有 SkillsPage/SkillDetailPage | 新 Market 页面/路由 | 复用现有能力 |
| protectedPaths | 门禁包内常量 + 对拍测试 | 读 tools checkout | 服务端无该 checkout，常量是唯一诚实选项 |

**明确不引入**：无新依赖（全部标准库 + 仓内既有件）；无新事务框架；无新表（除 PRD 已批准的 1 张）；无 daemon 协议字段（`TaskCompleteRequest` 零改动，AC-4 以 diff 为证）。

### 6. FR 到技术实现映射（23/23）

| FR | 实现条目 |
|---|---|
| FR-1 | 迁移 380（三列 + 两值 CHECK，无 builtin 枚举） |
| FR-2 | 迁移 381（skill_usage_event，含 workspace_id 租户键，无 FK） |
| FR-3 | claim 写入 ref.ID 原样落库（builtin 合成 id 已有，零转换） |
| FR-4 | version 仅 UpdateSkill 读写；无任何比较逻辑（diff 评审锚点） |
| FR-5 | §4.1 buildClaimedTaskResponse 循环 INSERT，失败仅日志 |
| FR-6 | `TaskCompleteRequest`/`sanitizeTaskCompleteRequest` 不进 diff（AC-4） |
| FR-7 | 表注释（迁移 381 内 `COMMENT ON`）+ §4.3 查询语义 |
| FR-8 | §4.2 门禁整体 fail-closed，可见性翻转在同一事务 |
| FR-9 | meta.Name/Description 非空校验 |
| FR-10 | owner 空 → 拒；单值即可（不要求全局唯一） |
| FR-11 | 四字段逐一校验，错误带字段名 |
| FR-12 | 结构校验 = ParseSkillMetadata 成功 + 必填字段（tools validate-doc 是 CR 文档校验器，不适用于 SKILL.md；不做跨包调用） |
| FR-13 | protectedPaths 常量比对 → warnings（不阻断、不改写声明） |
| FR-14 | 无 is_builtin 特判（builtin 无 skill 行，天然不可达） |
| FR-15 | §4.4 Findings + name 字段 + 单一定义测试 |
| FR-16 | 第 17 条 personal_path 模式 |
| FR-17 | 门禁扫描 content + 全部 skill_file，返回 file/line/pattern_id；**org Skill 的后续内容更新（含 runtime-local 覆盖导入）同样重扫**（§3.1 触发条件 2） |
| FR-18 | §2.2 申诉端点 + appeal_id 哈希 + activity_log 三 action |
| FR-19 | §3.3 market 端点：workspace（当前工作区 + org 可见，含 version）+ builtin 排行 |
| FR-20 | SkillDetailPage 渲染四字段（org workspace Skill） |
| FR-21 | Fields 中 requirements 类字段确定性提取，缺失则无标签不报错 |
| FR-22 | 发布确认框文案（前端） |
| FR-23 | `source` 字段经 ParseSkillMetadata 读取 → 列表筛选，零新列 |

### 7. 安全与性能考量

- **迁移合规**：380 起、无 FK、每文件一条 CONCURRENTLY 索引、cleanup map 双注册（NFR-1/2，AC-1）。
- **工作区隔离**：遥测表自带 `workspace_id`，market 读路径按认证上下文过滤，请求体 workspace 标识不取信（硬不变式 1，与 CR-2026-047 的 `maturity_snapshot` 租户键同口径）。
- **隐私红线**：findings 响应一律经 `Text()` 脱敏（NFR-4）；扫描是默认拦截，放行是逐条留痕例外（AC-11）；**发布不是一锤子买断**——org Skill 的内容每次变更都重跑同一道门禁。
- **权限**：申诉决定仅 owner/admin（403 测试）；发布沿用 canManageSkill；工作区隔离沿用 requireWorkspaceRole（ARCHITECTURE.md 硬不变式 1）。
- **性能**：claim 路径每 Skill 一行 INSERT（同阶 <10 行/任务，NFR-3）；排行聚合走 `(workspace_id, skill_ref, used_at)` 索引、完成过滤走 `task_id` 索引、申诉查找走 384 部分索引（三条均有 EXPLAIN 断言，AC-15）。
- **任务单路径**：遥测挂在既有 claim 装配点，不新增任何任务执行通道（硬不变式 3）。
- **回滚**：380–384 逆序 down 可全回滚；`skill_usage_event` 是纯观测数据，回滚丢弃无业务影响。
- **台账**：全部改动按 NFR-6/AC-17 登记 `../multica/CUSTOM.md`（新增一行：迁移 380–384 + 门禁/遥测/申诉挂钩点 + 验证命令），`make sqlc` 生成物提交生成器真实输出，不手补。
- **残余风险**（实施时留意）：① claim 循环 INSERT 与 claim 事务的关系——若 claim 本体有事务，遥测写入放事务内随它提交，不回滚单独补偿；② sqlc 重生成会带出新列相关 generated diff，按 CUSTOM.md 规则提交生成器真实输出；③ builtin 计数依赖 `buildClaimedTaskResponse` 的 builtin ref 合成规则，需在 skill_bundle 测试中加一条断言锁住（与 `TestBuildAgentSkillBundlesAssignsBuiltinID` 同款）；④ 迁移 384 建在热表 activity_log 上，必须 CONCURRENTLY 且单语句单文件，与 089 同款。

### 8. Prompt 采纳影响

本节按 CR-2026-021 FR-25 条件触发：本 CR **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（§4.2 的门禁包常量是 multica 服务端内部数据，不改变 crctl 命令面或 guard deny 面）。故本节省略。

## P3 组织智能 CR-C：跨 CR 追溯与漂移检测（E4 追溯 + E5 漂移）（v0.23 · CR-2026-049）

## SDD — P3 组织智能 CR-C：跨 CR 追溯与漂移检测

> 对应 PRD FR-1~FR-16。E4 复用 crctl outbox → `cr_sync_event`；E5 使用服务端确定性 `sys_cron` job。Git/crctl 继续是 CR 权威；Multica 只保存投影与治理 finding；不建 `spec_trace`，不新增 Agent/LLM/daemon 扫描。

### 0. 第 1 轮评审回修摘要

| Blocker | 回修结论 |
|---|---|
| TD-B1 canonical payload 被改写 | 恢复批准的 `{spec_id, traceability}`；traceability generator 产出受 candidate digest 保护的完整语义对象，crctl 不做第二次自由解析 |
| TD-B2 pending 在归档后可能丢失 | writeback journal 保存完整 trace intent；`writeback-apply` complete replay 前置；archive 在任何 authority/cleanup 前强制补发，失败硬阻断并保留现场 |
| TD-B3 冲突重投误 ack | `trace` 使用事务内 insert-or-load + `FOR UPDATE` + processed 标记；只有 committed processed 行才 ack |
| TD-B4 workspace 回填/切换不确定 | 显式多归属/孤儿 preflight；维护窗口下按 new-index-before-old-drop 切换；覆盖 ingest、lock、processed、runner、maturity、approval 全 seam；完整编号 385–397 |
| TD-B5 per-workspace repo access 未闭环 | 三仓 remote 已核实；generated declaration 与 `workspace.repos` 精确绑定；复用 workspace GitHub installation + `ghsnapshot.Client`，缺绑定/权限即 FAILED |
| TD-B6 GitHub 增量不能证明不漏扫 | 固定本轮 HEAD=B，以 `sha=B` 分页直到精确 A；任何截断/未命中/限流失败均不推进 cursor |
| TD-B7 API/测试契约不足 | 补版本化 DTO、错误码、keyset、状态 CAS、malformed fallback、权限矩阵及 AC-1~AC-15 分层测试矩阵 |

### 1. 架构概览

#### 1.1 三仓职责

| 仓 | 职责 | 主要产物 |
|---|---|---|
| knowledge-base | 产品级仓库声明单一事实源 | `dir-graph.yaml#repositories[].remote/commit_prefixes` |
| tools | trace semantic candidate、writeback journal/outbox、archive pending gate | `writeback-traceability.mjs`、`yaml-subset.mjs`、`workspace-transactions.mjs`、`crctl.mjs` callback adapter、两个 writeback/archive Skill 契约 |
| multica | trace tenant-safe ledger/读侧、commit scan、finding/API/UI | migrations 385–397、governance/commitprefix/drift/scheduler、core schema/client、views |

目标代码仓根目录 `ARCHITECTURE.md` 均已存在并已核对：tools 保持 crctl CLI→lib 单向依赖和零第三方依赖；multica 保持 handler→service/query、workspace 隔离、generated file 不手改、索引独立 `CONCURRENTLY` migration。

#### 1.2 E4 trace 写入流

```text
writeback-traceability.mjs
  生成 LF traceability.yml
  → 用加固后的版本化 YAML subset parser 解析完整受控文档
  → validateTraceSemantic（spec-id、cr-ref、milestones、当前 CR 唯一段、段数）
  → candidate manifest v2.event = {kind:'trace', payload:{spec_id, traceability}, payload_sha256}
  → manifest inputDigest 覆盖 event
        │
crctl writeback-apply --stage traceability
  validate manifest/event → commit/push
  → journal.traceOutbox={state:'pending',commit,dedupName,payload,payloadSha256}
  → 通过 cmdWritebackApply 注入的 emitTraceEvent callback 写 outbox
  → 成功 state=emitted；失败 warning + 保持 pending
        │
daemon collector（既有，at-least-once）
        │ POST /api/daemon/cr-events
server governance.crsync
  workspace 来自 daemon auth（不信任 body）
  → trace payload schema 校验
  → transaction: insert-or-load → row lock → processed_at → commit
  → committed processed 后才 Accepted
        │
cr_sync_event(workspace_id,event_kind='trace',payload canonical JSON)
        │
trace API / spec 详情页 / 全局搜索
```

`workspace-transactions.mjs` 不反向 import CLI：`cmdWritebackApply` 与 `cmdArchive` 分别注入 `emitTraceEvent`/`replayTraceEvent` callback，均复用 `crctl.mjs#emitOutboxEvent`。

#### 1.3 E4 pending 生命周期（最终交付门禁）

1. trace commit 确认后，journal 先保存完整 canonical payload/commit/dedupName，再尝试 outbox；因此 txws/candidate 不是补发所需输入。
2. `applyWritebackAtomic` 在 `resolveOperationalWorkspace` 和 candidate 读取**之前**先读取 `{cr}-traceability` writeback journal；若 `phase=complete && state=pending`，仅用 journal intent 补发，成功置 `emitted` 后返回，不要求 txws 仍存在。
3. `archiveCr` 在创建 archive journal、写 authority commit、清理任何 worktree **之前**读取同一 writeback journal：
   - `emitted`：继续；
   - `pending`：调用 `replayTraceEvent`；成功持久化 `emitted` 后继续；
   - 仍失败：抛 `ARCHIVE_TRACE_PENDING`，零 archive 写入、零 cleanup，保留可恢复现场；
   - journal 缺失/commit 或 payload digest 不完整：`ARCHIVE_TRACE_FACT_MISSING` 硬失败。
4. `writeback-traceability` Skill 必须把 `EMIT_FAILED(event_kind=trace)` 输出为“writeback 已完成、trace pending”；`cr-archive` Skill 对 `ARCHIVE_TRACE_PENDING` 只提示重跑同一 archive，不绕门。collector 只负责已落盘文件重试。

#### 1.4 E5 扫描流与 workspace 绑定

```text
knowledge-base dir-graph.yaml
  repositories[].{id,remote,trunk,commit_prefixes}
      │ generator --source / --check
      v
multica server/internal/commitprefix/config_gen.go
  {repo_id, canonical_url, owner, repo, trunk, prefixes, config_rev}
      │
workspace scope provider：枚举 workspace；workspace.repos 含 knowledge-base canonical URL 才 eligible
      │
RepositoryBindingResolver
  generated repo canonical_url 必须逐一存在于 workspace.repos
  → workspace GitHub installations 中解析出对 owner/repo 有 Contents:Read 的唯一 installation
  → ghsnapshot.Client mint/cache installation token
      │
commit_prefix_scan（每小时、scope=workspace/{uuid}）
  固定各仓 HEAD B → 从 B 分页到上一成功 cursor A → 分类 → upsert findings
  → 全仓成功才让 scheduler success result 写新 scan_cursors/config_rev/repository_ids
      │
/api/drift/* + maturity 治理卡 + finding 下钻页
```

0.23 只支持生成声明中的 GitHub HTTPS remote；SSH URL 在 `workspace.repos` 先 canonicalize 为同一 owner/repo；非 GitHub provider 返回 `repository_provider_unsupported` 并令 plan FAILED，不静默跳仓。扫描仍是服务端纯 Go，无 daemon/LLM。

#### 1.5 Multica 模块边界

- `internal/governance`：事件 ingestion/projection + `trace.go` 读服务；`trace` ledger-only，不改变 `cr.status`。
- `internal/commitprefix`：声明 DTO、generated file、严格 generator；不运行时读取 knowledge-base 文件。
- `internal/integrations/ghsnapshot`：复用 App JWT/installation token 缓存，扩展 `ResolveRepositoryAccess`/`ListCommits`，不记录 token。
- `internal/drift`：finding repository、状态 CAS、overview/health pure functions。
- `internal/scheduler/jobs_commit_prefix.go`：每 workspace job orchestration；不承载 HTTP DTO。
- `internal/handler`：workspace membership + 参数/DTO/error envelope。
- `packages/core`：Zod schema、`parseWithFallback` client；`packages/views`：spec trace、global search result、drift card/list。

### 2. 数据模型与迁移

#### 2.1 `drift_finding`

```sql
CREATE TABLE drift_finding (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  workspace_id UUID NOT NULL,
  repository_id TEXT NOT NULL,
  spec_id TEXT,
  cr_id TEXT,
  kind TEXT NOT NULL CHECK (kind IN ('alignment-drift','impact-stale','bypass-commit','wip-on-trunk')),
  severity TEXT NOT NULL CHECK (severity IN ('info','warn','block')),
  summary TEXT NOT NULL,
  evidence JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved','wontfix')),
  found_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  CHECK (
    kind NOT IN ('bypass-commit','wip-on-trunk') OR
    (COALESCE(evidence->>'repository_id','') <> '' AND
     COALESCE(evidence->>'trunk','') <> '' AND
     COALESCE(evidence->>'commit_sha','') <> '' AND
     COALESCE(evidence->>'commit_subject','') <> '' AND
     COALESCE(evidence->>'scanned_at','') <> '')
  )
);
```

E5 行固定 `spec_id=NULL, cr_id=NULL`；应用层先做同样 evidence 校验，DB CHECK 是最后防线。无 FK。

#### 2.2 `cr_sync_event` / approval workspace contract

- `cr_sync_event.workspace_id UUID NOT NULL` 由 daemon auth context 注入；event body 不含可信 workspace。
- 事件唯一键：`(workspace_id, cr_id, commit_sha, event_kind)`。
- trace 查询索引：`(workspace_id,(payload->>'spec_id'),occurred_at,id) WHERE event_kind='trace'`。
- unprocessed 索引改为 `(workspace_id,cr_id,received_at) WHERE processed_at IS NULL`。
- approval approve 幂等索引改为 `(workspace_id,cr_id,stage,evidence_digest) WHERE decision='approve'`；所有 conflict/select 都加 workspace。
- in-process mutex key 改为 `workspaceID + "\x00" + crID`，避免两个租户同名 CR 串行/互扰。

#### 2.3 迁移清单（当前最大 384，完整编号）

| 编号 | 内容 |
|---|---|
| 385 | 建 `drift_finding` 表（无 inline PK/FK/index） |
| 386 | `CREATE UNIQUE INDEX CONCURRENTLY drift_finding_id_uidx ...` |
| 387 | `ADD CONSTRAINT drift_finding_pkey PRIMARY KEY USING INDEX ...` |
| 388 | PRD 固定 `drift_finding_dedup_idx`（CONCURRENTLY） |
| 389 | finding keyset：`CREATE INDEX CONCURRENTLY ... (workspace_id,status,found_at DESC,id DESC)` |
| 390 | `cr_sync_event` 加 nullable `workspace_id`；先 preflight，再确定性回填、零 NULL 断言、SET NOT NULL |
| 391 | 新 workspace event unique index（CONCURRENTLY） |
| 392 | trace spec expression index（CONCURRENTLY） |
| 393 | workspace unprocessed index（CONCURRENTLY） |
| 394 | 删除旧 `cr_sync_event_cr_id_commit_sha_event_kind_key`（新 unique 已存在） |
| 395 | `DROP INDEX CONCURRENTLY idx_cr_sync_event_unprocessed` |
| 396 | 新 approval workspace approve unique index（CONCURRENTLY） |
| 397 | `DROP INDEX CONCURRENTLY approval_record_approve_uniq` |

每个 CREATE/DROP INDEX migration 只有一条索引语句；386/388/389/391/392/393/396 均在 `cmd/migrate` concurrent invalid-index cleanup registry 登记并由现有 migration test 扫描。down migration 反向恢复时也遵守先建旧 index、再删新 index 的可用顺序。

#### 2.4 workspace 回填的确定性 preflight

迁移 390 在 UPDATE 前执行：

```sql
DO $$
BEGIN
  IF EXISTS (
    SELECT e.cr_id
    FROM cr_sync_event e
    LEFT JOIN cr c ON c.cr_id=e.cr_id
    GROUP BY e.cr_id
    HAVING count(DISTINCT c.workspace_id) <> 1
  ) THEN RAISE EXCEPTION 'cr_sync_event workspace backfill is ambiguous or orphaned';
  END IF;
END $$;

UPDATE cr_sync_event e
SET workspace_id=(SELECT c.workspace_id FROM cr c WHERE c.cr_id=e.cr_id);

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM cr_sync_event WHERE workspace_id IS NULL)
  THEN RAISE EXCEPTION 'cr_sync_event workspace backfill left null rows'; END IF;
END $$;
ALTER TABLE cr_sync_event ALTER COLUMN workspace_id SET NOT NULL;
```

`count != 1` 同时阻断孤儿（0）与多归属（>1），不会由 `UPDATE ... FROM` 任意选行。

#### 2.5 schema/code 切换顺序

这是一次短维护窗口切换（未要求零停机）：

1. 暂停旧 server 的 `/api/daemon/cr-events` 与 approval 写入口；daemon outbox 保留文件，不丢事实。
2. 执行 385–397：新 index 始终先于旧 index/constraint 删除；390 任一断言失败则停止且不启动新代码。
3. 启动已切到 workspace conflict target 的新 server；运行启动 smoke：两个 workspace 同名 CR、trace ingest、approval idempotency。
4. 恢复入口，daemon at-least-once 重投。

受影响 seam 全量清单：`crsync.go` INSERT/ON CONFLICT/processed UPDATE/mutex；`runner.go` checkpoint join；`maturity.sql` 全部七处 event join；`approval.go` latestEvidence、approve conflict/idempotent select；governance/maturity/runner 测试 fixture；daemon commit-scan/reconcile 若写 event 也必须传 auth workspace。未列出的 `cr_id` 单键 event 查询由静态 grep contract test 阻断。

#### 2.6 trace canonical payload 与 candidate manifest v2

批准的 event payload 不变：

```json
{
  "spec_id": "ai-first-platform",
  "traceability": {
    "spec-id": "ai-first-platform",
    "cr-ref": "CR-2026-049",
    "cr-history": ["CR-2026-001", "CR-2026-049"],
    "target-version": "0.23",
    "baseline-since": "0.10",
    "generated-at": "2026-08-20T20:00:00+08:00",
    "milestones": []
  }
}
```

实现契约：

- `yaml-subset.mjs` 修正“以 `{` 开头但不是合法 flow map 的 plain scalar”并将无法解释的结构硬失败；fixture 覆盖当前 191KB 累积 traceability、CRLF、plain scalar、flow map/seq、嵌套 milestones。
- generator 对 `newText` 解析后运行 `validateTraceSemantic`：顶层键、`spec-id==specId`、`cr-ref==cr`、milestones 为数组、YAML 中 `- cr:` 数量等于对象数组长度、当前 CR 恰一段、该段含 `frs|fr-chain` 与 evidence。
- traceability candidate 使用 manifest v2；`event.kind/event.payload/event.payloadSha256` 纳入 canonical `inputDigest`。baseline/tasks 继续接受 v1；traceability stage 必须 v2，validator 重新计算 payload SHA 并校验 `payload.spec_id==payload.traceability['spec-id']`。
- journal 保存 manifest 已验证 payload，不从发布后的文件重新自由解析。

### 3. 事件、调度与 API 契约

#### 3.1 outbox / server trace schema

- v1 顶层沿用：`event_kind='trace'`、`cr_id`、writeback `commit_sha`、`actor`、`occurred_at`；`dedup_name=trace-{cr_id}-{commit_sha}.json`。
- `knownEventKinds` 增加 trace；`ledgerlessKinds` 不增加 trace；`apply()` 对 trace 不调用状态转换。
- payload 校验失败返回 rejected `{file,code:'BAD_TRACE_PAYLOAD'}`，文件保留；最大 payload 2 MiB，超过返回 `TRACE_PAYLOAD_TOO_LARGE`（当前基线约 192 KiB）。
- trace transaction：
  1. `BEGIN`；`INSERT ... ON CONFLICT (workspace_id,cr_id,commit_sha,event_kind) DO NOTHING`；
  2. `SELECT id,processed_at,payload FROM cr_sync_event WHERE workspace_id=$1 ... FOR UPDATE`；
  3. 已 processed 且数据库 JSONB `payload = incoming::jsonb` 语义相等 → commit 幂等成功；payload 不同 → `EVENT_IDEMPOTENCY_CONFLICT`、rollback/reject（不依赖 JSON 对象键顺序）；
  4. 未 processed → schema validate + `UPDATE ... SET processed_at=now()`；commit；
  5. `HandleCREvents` 仅在 commit 后加入 Accepted。

#### 3.2 `commit_prefix_scan` JobSpec

```text
Name              commit_prefix_scan
Cadence           1h
ScheduleDelay     0
CatchUpMode       CatchUpLatestOnly
Scopes            activePlatformWorkspaceScopes(pool)
RunTimeout        10m
StaleTimeout      15m
HeartbeatInterval 30s（每一 GitHub page 后显式 Heartbeat）
AllowStaleReentry true（finding insert 幂等，cursor 只在 SUCCESS result 中推进）
MaxAttempts       3
RetryBackoff      1m, 5m, 15m
```

scope provider 枚举 workspace，解析 `workspace.repos`；含 canonical knowledge-base URL 的 workspace 才进入 scope。没有平台 repo 配置的普通 Multica workspace 不制造失败计划，治理页显示 `uninitialized/not_configured`。进入 scope 后三仓必须全部绑定成功，否则 plan FAILED。

成功 result v1：

```json
{
  "v": 1,
  "config_rev": "<dir-graph source commit sha>",
  "repository_ids": ["ai-first-platform-docs", "multica", "tools"],
  "scan_cursors": {
    "ai-first-platform-docs": "sha",
    "multica": "sha",
    "tools": "sha"
  },
  "finding_count": 2
}
```

#### 3.3 repo binding 与真实初始声明

已用 `git remote -v` 核实：

| repo id | canonical remote | trunk |
|---|---|---|
| ai-first-platform-docs | `https://github.com/OldBoy405/AI-First-Platform.git` | `master` |
| multica | `https://github.com/OldBoy405/AI-First-multica.git` | `main` |
| tools | `https://github.com/OldBoy405/AI-First-tools.git` | `custom/main` |

初始 `commit_prefixes` 使用大小写敏感 `strings.HasPrefix`；值含分隔符，禁止用裸 `feat` 误匹配 `feature`：

```yaml
## knowledge-base
commit_prefixes: ["[cr] ", "register ", "archive ", "writeback ", "merge ", "Merge ", "feat(", "fix(", "docs(", "chore(", "test(", "refactor(", "perf("]
## multica（含上游 MUL-123: 格式）
commit_prefixes: ["MUL-", "Merge ", "merge ", "feat(", "fix(", "docs(", "chore(", "test(", "refactor(", "perf(", "build(", "ci(", "style(", "revert:", "[cr] "]
## tools
commit_prefixes: ["[cr] ", "Merge ", "merge ", "feat(", "feat:", "fix(", "fix:", "docs(", "docs:", "chore(", "chore:", "test(", "test:", "refactor(", "perf("]
```

`wip:` 是优先分类保留字，不进入合法白名单；classifier 在白名单判断前产生 `wip-on-trunk`。generator 以各仓 trunk 最近 200 条 subject 运行 coverage fixture；任何当前 subject 未匹配必须在提交声明前被人工分类（新增白名单或作为预期 finding），AC-10 不靠猜测。普通 Multica build 只编译已提交的 Go 副本、不 checkout knowledge-base；独立 generator-sync CI job 显式 checkout knowledge-base 源 SHA 后运行 `--check`，pre-commit 则由开发工作区传 `--source`。

绑定算法：generated canonical URL 与 `workspace.repos[].url` 规范化后精确相等；现有持久化契约只有 URL/description，因此 trunk 只取 generated declaration，不虚构 `workspace.repos.ref`。加载当前 workspace 的 `github_installation`，用 `ghsnapshot.Client` 对 owner/repo 检查 Contents:Read；零个可用 installation → `repository_access_missing`，多于一个 → `repository_access_ambiguous`。token 只在 client 内存缓存且从不落日志/result。

#### 3.4 精确增量算法

对每仓：

1. `GET /repos/{owner}/{repo}/commits?sha=<url.Values 编码的 trunk>&per_page=1`，固定响应首 SHA 为 B；`custom/main` 仅作为 query value 编码，不拼 path。
2. 首次（无 A）：仅设置 candidate cursor=B，不生成 finding。
3. 非首次：从 `GET .../commits?sha=B&per_page=100&page=1` 起分页；分页根固定 SHA B，因此扫描期间 trunk 前进不进入本轮。
4. 按 API 顺序收集，直到**精确 SHA==A**；分类 A 之前的 `[B..A)`；同一页也保持新→旧顺序，写 finding 与顺序无关。
5. 每页 heartbeat；403/429/5xx、timeout、malformed JSON、空页未命中 A、100 页（10,000 commit）仍未命中均返回明确 error，plan FAILED、cursor 不推进。429/403 的 rate-limit 元数据只进结构化 error，不记录 token。
6. cursor 未命中视为历史重写/非祖先，不自动 baseline；人工修复后才可清 cursor。
7. 全仓 walk 成功后，在 DB transaction 中 `INSERT ... ON CONFLICT DO NOTHING` findings；handler 返回 candidate cursors。若 insert 后、scheduler success 更新前崩溃，下次从旧 A 重读，唯一索引去重且不漏提交。

分类先判断 `strings.HasPrefix(subject,"wip:")` → `wip-on-trunk/info`；否则任一白名单前缀命中为合法；否则 `bypass-commit/warn`。subject 为 commit message LF 规范化后的第一行。

#### 3.5 trace API（v1）

所有端点使用 `X-Workspace-ID` + `workspaceMember`；body/query workspace 不取信。

##### `GET /api/cr/specs/{spec_id}/trace`

```json
{
  "v": 1,
  "workspace_id": "uuid",
  "spec_id": "ai-first-platform",
  "events": [{
    "event_id": 123,
    "cr_id": "CR-2026-049",
    "commit_sha": "abc",
    "occurred_at": "RFC3339",
    "state": "ok",
    "milestone": {
      "cr": "CR-2026-049",
      "frs": [],
      "merge_commits": [],
      "evidence": {}
    }
  }]
}
```

查询按 `(occurred_at,id)` 升序加载事件，并用**最新有效完整 snapshot** 的全部 milestones 作为展示集合，不能只取当前事件 CR（首个 trace 必须把 CR-C 之前的累积历史带入）。投影规则：以 `(milestone.cr,milestone.milestone)` 去重；将所有有效 trace event 的 `cr_id→(occurred_at,id)` 映射回对应 milestone；有事件的条目按 `(occurred_at,id)` 排序，首个 snapshot 导入但没有独立 trace event 的历史条目标记 `source='baseline-imported'` 并保持文档顺序、排在事件条目前。`frs` 与历史 `fr-chain` 统一规范为响应字段 `frs`；同 key 在两个 snapshot 的语义 hash 不同则该条标记 `trace_snapshot_conflict`，不静默覆盖。新事件 ingestion 仍要求 `event.cr_id` 在 payload 中恰一段。历史坏行不泄漏 raw payload，返回该 event `state='malformed', error_code='trace_payload_invalid'`，其余时间线仍可读。evidence 缺失返回显式 `null/missing`，不回退 trunk HEAD。

commit 跳转 DTO 包含 `{repo,trunk,sha,repository_url}`；证据跳转包含 `{path,sha256,commit_sha}`。前端仅用这些字段构造 GitHub commit/blob 或内部 evidence 链接。

##### `GET /api/cr/spec-search?q=&owner=&limit=&cursor=`

```json
{"v":1,"specs":[{"spec_id":"ai-first-platform","latest_cr_id":"CR-2026-049","owners":["Ray"],"updated_at":"RFC3339"}],"next_cursor":null}
```

- `owner` 对 `jsonb_each(cr.owners).value->>'id'` 做大小写不敏感**精确**匹配；owner 是 crctl free-text identity，不宣称等同 Multica user UUID。
- `q` 对 spec_id 与 owner id 做转义后的 ILIKE；结果由 workspace-scoped trace events 与 `cr` 按 `(workspace_id,cr_id)` join。
- 全局 `packages/views/search/search-command.tsx` 与 issue/project 请求并行调用 `searchSpecs`，增加“Specs”分组；选择后进入 `/{slug}/governance/specs/{specId}`。spec 详情页与搜索复用同一 trace API。

#### 3.6 drift API（v1）

##### `GET /api/drift/overview`

```json
{
  "v":1,
  "scan_health":"ok",
  "last_plan_status":"SUCCESS",
  "last_success_at":"RFC3339",
  "repository_ids":["ai-first-platform-docs","multica","tools"],
  "bypass_count":1,
  "wip_on_trunk_count":2,
  "resolve_latency_ms":{"sample_count":3,"p50":1000,"p90":5000}
}
```

`scan_health`：无平台 repo 配置=`not_configured`；有配置无成功=`uninitialized`；最新 plan FAILED=`failed`；最新成功超过 2h、`config_rev` 不等于当前或 cursor 未覆盖全部 repo=`stale`；否则 `ok`。只有 `ok && unresolved finding=0` 显示“无漂移”。计数含 `open|acknowledged`；解决时延只取 `resolved` 且 `resolved_at` 非空的 `resolved_at-found_at`，空样本 p50/p90=`null`。

##### `GET /api/drift/findings?status=&kind=&repository_id=&limit=&cursor=`

limit 1..100，默认 50；排序 `(status_rank ASC, found_at DESC, id DESC)`，rank=`open 0, acknowledged 1, resolved 2, wontfix 3`；cursor 是 base64url JSON `{rank,found_at,id}` 并经 schema/长度校验。响应：

```json
{"v":1,"findings":[{"id":"uuid","repository_id":"tools","spec_id":null,"cr_id":null,"kind":"bypass-commit","severity":"warn","summary":"...","evidence":{},"status":"open","found_at":"RFC3339","resolved_at":null}],"next_cursor":null}
```

##### `PATCH /api/drift/findings/{id}`

request `{ "from_status":"open", "to_status":"acknowledged" }`。允许：

- open → acknowledged | resolved | wontfix
- acknowledged → resolved | wontfix
- resolved/wontfix 为终态；同状态重放 200 幂等；其他 409 `invalid_transition`

单 SQL CAS：`WHERE id=$id AND workspace_id=$ws AND status=$from`；零行时重读区分 404/409。进入 resolved 写 `resolved_at=now()`；wontfix 保持 NULL。所有 workspace member 可读/流转（对应 QA user story）；跨 workspace id 恒 404。

#### 3.7 统一错误与前端兼容

错误 envelope：`{"error":"code","message":"safe text","request_id":"uuid"}`。400=`invalid_query|invalid_cursor|invalid_payload`，401/403=认证/成员失败，404=`not_found`，409=`invalid_transition|state_conflict`，500=`internal_error`。

`packages/core` 为 Trace/SpecSearch/Drift DTO 建 Zod schema；network client 全部 `parseWithFallback`。前端 enum 额外接受 `unknown` fallback，未知 `scan_health/kind/status/severity` 不 crash；malformed response 返回空安全 envelope并上报 endpoint tag。web/desktop 共享 `packages/views` 页面，不复制业务状态。

### 4. 查询、健康与幂等流程

#### 4.1 finding 幂等

E5 不先查再插：

```sql
INSERT INTO drift_finding (...)
VALUES (...)
ON CONFLICT DO NOTHING;
```

DB CHECK 保证 E5 commit_sha 非空，使 expression unique index 不会被 NULL 绕过。同 workspace/repository/kind/commit 24h 重扫仍一行；不同 workspace/repository 分开。

#### 4.2 health 查询事实源

只读 `sys_cron_executions`：先取最新 plan（任何状态），再取最新 SUCCESS result。最新 FAILED 优先显示 failed；旧 success 不能掩盖新失败。成功 result 的 `config_rev/repository_ids/scan_cursors` 一起验证，声明增仓后旧 result 自动 stale。

#### 4.3 owner/spec 与 timeline 去重

trace event 是完整累计 snapshot；读侧取最新有效 snapshot 的全部 milestones，再用事件元数据赋时并按 `(cr,milestone)` 去重，历史 baseline 不因缺独立 trace event 而丢失。unique key 防同 commit 重复。owner/spec 查询通过同 workspace 的 `cr` 连接，不从 milestone 文本猜 owner。表达式索引先定位 spec，再按 event id/occurred_at 排序。

### 5. 技术选型与替代方案

| 决策 | 选择 | 原因 / 否决替代 |
|---|---|---|
| canonical trace object | generator + manifest v2 | 保持 PRD payload，不让 CLI/读 API重解释；否决 raw YAML transport |
| YAML | 加固现有 zero-dep subset + 当前累积 fixture | tools 继续零第三方依赖；任何未知结构硬失败 |
| trace retry | journal intent + writeback complete replay + archive gate | collector 看不到未落盘 pending，单靠人工重跑不足 |
| trace ingest | 专用事务 insert-or-load/processed | ledger-only 无状态投影，最小范围消除 INSERT 后故障缝隙 |
| workspace migration | 维护窗口，new index before old drop | 不要求零停机；daemon outbox天然缓存；避免双版本 conflict target 不兼容 |
| repo access | workspace.repos + GitHub installation + ghsnapshot | 复用现有 workspace access；否决全局 PAT/reconcile 单 remote、否决 server bare clone |
| cursor | SUCCESS result.scan_cursors | 复用 scheduler 审计/lease；否决平行 scan_state 表 |
| scan upper bound | 固定 HEAD SHA B | trunk 扫描中前进不会改变本轮集合 |
| API pagination | keyset | finding 流持续写入时 offset 会漂移 |

### 6. FR → 实现映射

| FR | 技术落点 |
|---|---|
| FR-1 | tools trace generator semantic object + manifest v2 + emit callback |
| FR-2 | multica `crsync.go` trace schema/transaction/processed；daemon schema fixture |
| FR-3 | journal trace intent、complete replay、archive pre-gate、deterministic file |
| FR-4 | migrations 390–397；crsync/runner/maturity/approval 全 workspace seam |
| FR-5 | migration 392 + governance trace query；无 spec_trace |
| FR-6 | 当前 CR milestone 投影 + spec detail route |
| FR-7 | evidence/merge DTO，缺失显式显示，不猜 HEAD |
| FR-8 | spec-search + global search Specs 分组 + free-text owner 语义 |
| FR-9 | JobSpec + workspace scope/binding resolver |
| FR-10 | case-sensitive prefix classifier；wip 优先；完整 evidence |
| FR-11 | dir-graph 真实 remote/prefixes + generator/config_gen.go/--check |
| FR-12 | migration 385–387 + evidence CHECK |
| FR-13 | migration 388 + ON CONFLICT DO NOTHING |
| FR-14 | 固定 B、分页至 A、SUCCESS result cursor |
| FR-15 | overview health + maturity drift card |
| FR-16 | finding keyset list + PATCH CAS 状态流 |

FR 覆盖率：**16/16**。

### 7. 安全、性能与可测试性

#### 7.1 安全/性能不变量

- 所有 event/finding/query/unique/CAS 都以 auth workspace 为第一条件；跨 workspace finding id 返回 404。
- `cr_sync_event` payload 最大 2 MiB；trace 索引按 workspace/spec/order 覆盖；finding keyset 有 389 索引。
- GitHub token 由 `ghsnapshot.Client` 内存缓存，日志/result/error 不含 token；扫描只读 SHA + subject。
- 每页 heartbeat，10m timeout、10k commit fail-safe；失败不推进 cursor，不伪装“零 finding”。
- Git 仍为 CR 权威；trace ledger-only；扫描只读远端。
- multica 新源码注释英文；generated Go 不手改；改 multica 必登记当时 `CUSTOM.md`。

#### 7.2 AC 分层测试矩阵

| AC | 测试层与关键断言 |
|---|---|
| AC-1 | tools generator fixture：191KB full semantic JSON；跨语言 golden 由 Go `yaml.v3` 解析同一 YAML 后与 Node event payload 深比较；multica governance DB：trace accepted/processed、status 不变 |
| AC-2 | tools fault injection：outbox mkdir/write fail、journal pending、complete replay、archive gate fail/recover、重复文件/ledger 一行 |
| AC-3 | migration PG test：唯一回填成功、孤儿/多 workspace 同名回填非零；两 workspace 同名 CR ledger 隔离 |
| AC-4 | schema grep/migration test：无 spec_trace；EXPLAIN trace expression index |
| AC-5 | handler/service：首个完整 snapshot 导入历史 milestones，后续两个同 spec trace 以 `(cr,milestone)` 去重并按事件赋时；稳定时序、跨 workspace 不泄漏 |
| AC-6 | view：merge/test/review/approval link；缺 evidence 显式 missing、不取 latest trunk |
| AC-7 | spec-search handler + search-command：owner exact、spec query、跨 workspace；owner free-text 不误当 user UUID |
| AC-8 | scheduler fake DB/GitHub：per-workspace hourly、missing repo FAILED、首次三仓 baseline 零 finding |
| AC-9 | classifier table test：wip 优先、合法 prefix、bypass；evidence DB CHECK |
| AC-10 | generator fixture：三仓非空、最近 200 subject coverage、source SHA、dirty source/--check drift 非零 |
| AC-11 | PG migration introspection：字段/check/default、NULL spec/cr、无 FK、PK/dedup concurrent migration + cleanup hook |
| AC-12 | fake GitHub：100+ 多页 A→B、HEAD 中途前进、cursor missing、page 429/500、heartbeat、中断重试不漏 |
| AC-13 | PG integration：24 次重复一行；workspace/repo 不同各一行；静态检查无 select-before-insert |
| AC-14 | health pure/DB tests：not_configured/uninitialized/failed/stale/config drift/ok+zero；counts/latency 空样本 |
| AC-15 | handler CAS matrix：合法流转、同状态幂等、并发 409、resolved_at、wontfix NULL、跨 workspace 404；view 下钻同步 |

横切测试：

- `crsync` fault point 在 INSERT 后/processed 前中断，重投必须最终一行且 processed；payload 同 key 不同 digest 必须 reject。
- `runner.go`、`maturity.sql`、`approval.go` contract grep/SQL tests 禁止 `cr_sync_event` join 缺 workspace。
- `packages/core` 每个新 endpoint 都有 valid、malformed response、unknown enum fallback；views 覆盖 web/desktop 共用组件。
- migrations 386/388/389/391/392/393/396 通过 invalid concurrent index retry registry test。

#### 7.3 残余风险

- 前缀可伪造，仍只是可见性信号；通路层对账按 PRD 延后。
- 单次 >10k 新提交会 fail-safe，不自动跳过；运维需人工确认后重建 baseline。
- 当前 trace baseline 会继续增长；达到 2 MiB 前需另立压缩/归档 CR，本 CR 不引入第二投影。

### 8. Prompt 采纳影响

条件性检查结论：本 CR 不新增/修改 `crctl.mjs` dispatch 子命令，也不改 `controlled-shell/rules.json#protectedPaths.deny`，因此不存在“新增命令未被 Skill 采用”的 blocker。

但 TD-B2 要求既有流程识别新增生命周期结果，作为普通行为契约同步：

| Skill / Pipeline | 修改 |
|---|---|
| `writeback-traceability/SKILL.md` 与 feature-writeback 对应 prompt | 输出 `EMIT_FAILED(trace)` 为 pending，不宣称 trace 已交付；允许 archive gate 做确定性补发 |
| `cr-archive/SKILL.md` 与对应 prompt | `ARCHIVE_TRACE_PENDING` 时仅重跑同一 archive；禁止跳门/手工清 journal |

以上只采纳既有 `writeback-apply`/`archive` 深原语的新结果，不新增 CLI 命令面。

## Pipeline 流程优化 — 职责边界与契约漂移修复（先正确性后职责收敛，P0/P1/P2 单 CR）（v0.24 · CR-2026-050）

## 1. 架构概览

本 SDD 落地 PRD（change-requests/CR-2026-050/prd.md）13 条 FR 的技术实现。改动本质是**文本契约收敛与最小输入契约扩展**：不新增事务框架、状态投影、通用 Runner、crctl 子命令或账本结构；净效果以删除重复合同为主，辅以少量既有 Skill 输入字段的显式化。

### 1.1 变更对象总览

| 仓库 | 变更对象 | 变更性质 |
|---|---|---|
| tools | `pipeline-templates/*.pipeline.json`（8 条） | prompt 收敛：P0 契约修复 + P1/P2 重复删除；机器字段（node/ref/reviewLoop/replayNodes/passCondition/onFail/timeout）不动 |
| tools | `skills/planning/extract-market-insight/SKILL.md` | FR-03.2 最小输入扩展（`mode=brief`、`raw_insight_path`） |
| tools | `skills/competitive/report-to-planning-suggestion/SKILL.md` | FR-04.3 输入扩展（`reportDraft`）+ 同步修订前置条件、错误处理表首行（reportPath 缺失即中止）、读写清单；保留「前端按 reportPath 触发」入口契约 |
| tools | `skills/develop/write-tech-design/SKILL.md` | **FR-07.1/FR-07.2 的真实漂移落点**：删除 Step 1 的 `.rayai-worktrees/{repo.id}/requirement/{cr_id}` 路径约定，改消费 `operational_workspace`/`resources[].worktreePath`；把「ARCHITECTURE.md 与 sdd.md 同一 commit 提交」改为「各仓在所属 worktreePath 分别提交，架构审批后由同一批 checkpoint 纳入」；FR-08.1~3 三项能力收窄；提交前缀对齐（§5 DD-7） |
| tools | `skills/develop/review-tech-design/SKILL.md` | FR-06.3/FR-08.4 评审维度扩展 |
| tools | `skills/cr/cr-show/SKILL.md` | FR-10.1 输出契约补「最近三次 checkpoint」展示项 |
| tools | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | FR-12/AC-12 扩展确定性断言 + 按 §5 DD-4 处置既有冲突断言（不新建测试框架） |
| tools | `skills/develop/write-dev-plan/SKILL.md`、`skills/planning/write-roadmap/SKILL.md` | DD-7 同类提交前缀漂移（`feat(` / `[planning] ` 均不在白名单）一并对齐 |
| tools | `skills/{requirement/approve-requirement,develop/approve-tech-design,develop/approve-dev-start,develop/approve-code}/SKILL.md` | §3.4 配套：Step 命令补 `--approver {cr.md owners.{角色}.id}`，使 Pipeline 停传 approver 后 TTY 路径仍落角色 owner |
| multica | `server/internal/governance/gate_nodes_gen.go` | **再生**（architecture-design pipeline prompt 变更后，嵌入 registry + digest 必须同步，§4.2） |
| multica | `CUSTOM.md` | 登记再生变更（台账纪律，AGENTS.md 第 10 条） |
| ai-first-platform-docs | `change-requests/CR-2026-050/*` | 本 SDD 及后续 plan/tasks/评审证据 |

**不修改**：`crctl.mjs` dispatch 面、`gates.json`、`dir-graph.yaml#change-request-track.state_machine`、`controlled-shell/rules.json#protectedPaths`、审批 grant、reviewLoop 业务语义、traceability evidence 结构、pipeline 节点数量与 UUID（competitive-radar node-5 无需加节点，§5 DD-2）。

**`tools/ARCHITECTURE.md` 不修订**：本 CR 无 skills 顶层分组变化、无 Pipeline 结构（节点数/依赖方向）变化、无 crctl 写入子命令变化、无状态机口径变化；DD-1~DD-3 是本 CR 的实现选择而非仓库级长期否决项，按该文档「维护规则」不触发修订条件。

### 1.2 模块边界（继承 PRD §1）

| 模块 | 本 CR 之后的职责 |
|---|---|
| Pipeline JSON | 节点顺序、ref、输入传递、reviewLoop、失败中止；每节点 prompt 最多五要素（调哪个 Skill、传什么、依赖哪些前序输出、消费哪些结果、失败去哪） |
| Skill | 业务判断、编排步骤、输入输出、失败语义 |
| crctl | 状态、门禁、账本、CAS、审批、审计（本 CR 零改动） |
| 版本化脚本 | 确定性文档转换（本 CR 零改动） |
| multica Runner | 消费嵌入 registry（gate_nodes_gen.go）执行 architecture Core（本 CR 只再生其输入，不改逻辑） |

### 1.3 依赖图

```text
tools/pipeline-templates/architecture-design.pipeline.json
   ├─(emit-registry.mjs --pipeline architecture-design)→ registry JSON + digest
   │        └─(multica gen/generate-gate-nodes.mjs)→ gate_nodes_gen.go（嵌入 + digest 校验）
   └─(Agent 执行其余 7 条 pipeline prompt)→ skills/{组}/{name}/SKILL.md → crctl（只读+受控写入）
tools/skills/**/SKILL.md —— 被 pipeline prompt 引用，输入契约以 SKILL.md 为唯一事实源
multica/server/internal/governance/runner.go —— 只消费 gate_nodes_gen.go 常量，零逻辑改动
```

### 1.4 关键流程

1. **两阶段实施**（AC-14）：阶段一先完成 FR-01～FR-05 且对应契约断言通过（§4.4 的 gate 清单），再进入阶段二按 `architecture-design → requirement-authoring → code-implementation → resume-cr → feature-writeback → 规划类` 顺序完成 FR-06～FR-13。AC-14 的验收证据形态 = TASK 顺序 + 各阶段 checkpoint/commit 时序（阶段一 gate 通过的 checkpoint 早于阶段二首个实现 commit）。
2. **competitive-radar 闭环**（FR-04）：node-2 草稿（confirmed=false）→ node-3 消费 reportDraft → node-4 人工确认 → node-5 confirmed=true 落盘正式报告再落规划条目（§4.1）。
3. **registry 再生链**（FR-07/FR-12 的隐式依赖）：architecture-design.pipeline.json 任何变更 → 重跑 multica 生成器 → 提交 gate_nodes_gen.go（§4.2）。

## 2. 数据模型

本 CR **不新增数据库表、迁移、账本文件或 crctl 字段**。仅有的「数据结构」变化是两处既有 Skill 的输入契约显式化：

### 2.1 reportDraft 最小结构（FR-04.3）

`report-to-planning-suggestion` 新增可选输入，与 `reportPath` 二选一：

```yaml
reportDraft:            # node-2 write-competitive-report(confirmed=false) 的结构化草稿
  body: <草稿正文 markdown>
  competitorId: <competitor-id>
  reportDate: YYYY-MM-DD
  sourceNodeId: <node-2 UUID>
  sourceRef: write-competitive-report
```

规则：`reportPath` 与 `reportDraft` 同时存在时优先 `reportPath`；草稿模式只消费输入生成规划建议，不落盘竞品报告。

### 2.2 extract-market-insight 简报模式（FR-03.2）

新增两个可选输入：

```yaml
mode: insight | brief        # 可选，默认 insight（缺省行为与现状完全一致）
raw_insight_path: <简报原始洞察文件路径>   # mode=brief 时必填
```

`mode=brief` 复用同一 Skill 现有 Step 3.5「简报附加区块」，该步骤的触发条件由 `mode` 驱动（不再靠调用方措辞推断）；`mode=brief` 且 `raw_insight_path` 缺失或不可读时按该 Skill 现有错误码风格硬失败（`INSIGHT_SOURCE_EMPTY` 同族，不静默降级为 insight 模式）。Pipeline 只传这两个业务参数，brief 正文/路径/index 状态仍由 Skill 负责。废除 Pipeline 中未声明的 `source` 伪造参数。

### 2.3 上游上下文输入的产出方（BLK-1 修复）

`updates-block` 与 `product-snapshot` 不是本 CR 新增结构，而是既有 Skill 的既有输出，本 CR 只固定「谁产出、谁消费」：

| 输入 | 结构与产出方 | 消费方 |
|---|---|---|
| `updates-block` | `fetch-competitor-updates` 输出的 competitor 条目（含 `updates[]`/`source-urls`） | `write-competitive-report`（必填） |
| `product-snapshot` | `gather-product-context` 输出的 Markdown 快照或其结构化摘要 | `write-competitive-report`（必填） |
| `context` | `gather-product-context` 输出的产品上下文快照（Markdown） | `planning-draft`（必填） |

三者的取得方式见 §4.3（在不增节点前提下由节点 prompt 顺序调用既有 Skill）。

### 2.4 保持不动的机器字段

- reviewLoop：`repairNodeId/repairRef/feedbackInput/attemptInput/replayPolicy/replayNodes/passCondition/onBlock/maxAttempts`（原样保留，不搬回 Skill 文本）；
- execution_context：传递语义不变，但**字段集按 pipeline 不同**——requirement-authoring 含 `cr_id/owners/knowledge_base_worktree/repo_worktrees`；architecture-design 与 code-implementation 只含 `cr_id/operational_workspace`[/`resources`]，**不含 owners**（直接影响 approver 取值，见 §3.4）；
- node UUID 与 `_index.yml#nodes` 计数（本 CR 不增删节点）。

## 3. 接口契约

### 3.0 五要素之外的机器契约保留项（BLK-2 修复）

以下内容**不属于**被收敛的「重复算法」，收敛时必须逐字保留，且已有确定性断言守护：

| 保留项 | 适用范围 | 现有断言 |
|---|---|---|
| `crctl workspace inspect` 入口校验（全部 `resources[].classification=healthy`、消费 `operationalWorkspace`、非 healthy 指向 `/resume`） | architecture-design **每个**节点（CR-2026-045 每节点独立 inspect），code-implementation 首节点 | `pipeline-structure.test.mjs:165-183` |
| 不依赖 `node-1.md`（architecture-design 后续节点） | architecture-design nodes[1..] | 同上 `:179` |
| `execution_context.operational_workspace` 消费 | code-implementation 后续节点 | 同上 `:176-183` |
| `execution_context.resources[].worktreePath` 且不得出现 `.rayai-worktrees/` 拼接 | code-implementation `implement-code` | 同上 `:185-188` |
| 代码审批节点（`…0010`）approvalPrompt 含「评审后 checkpoint phase=complete」前提 | code-implementation | 同上 `:114-117` |

### 3.1 收敛后节点 prompt 五要素模板

```text
调用 {skill-name}：
- 业务输入：{…}（参数名以该 Skill 的 SKILL.md 为唯一事实源）
- 前序依赖：{node-N.md 的结构化输出 / execution_context}
消费 {结构化结果字段}；失败按 {abort|skip|route} 处理。
```

反模式（一律删除并加负向测试断言）：评审维度正文、临时 payload 与 review-record 调用、`crctl` 命令细节、TTY/grant/CAS 流程、账本与 annotation 写入、Git 命令序列、章节/路径/索引规则、写死下一 pipeline 名。

> **删除要彻底（lint R1 风险，直接影响 AC-13）**：收敛后的节点 prompt **不得残留任何 deny 路径字面量**（`review-annotations/*.yml`、`approval.yml`、`review-loop.yml`、`_backlog.yml`、`cr.md` 等）。`lint-prompts.mjs` R1 的判据是「同段出现 deny 文件 + 写动词 + **同段无 crctl 调用**」；当前 review 类节点因同段含 `crctl review-record` 而豁免，FR-06 删除 crctl 命令细节后若仍保留 annotation 路径字样，将**新触发 R1** 使 `lint-prompts` enforce 失败。

### 3.2 逐 Pipeline 关键节点契约

| Pipeline | 节点 | 收敛后输入 | 消费结果 |
|---|---|---|---|
| architecture-design | write-tech-design | cr_id、tech_context、operational_workspace、resources、review_feedback、self_repair_attempt | execution_context（SDD 路径、FR 覆盖率） |
| architecture-design | review-tech-design | cr_id、workspace、review_feedback、attempt | verdict/blockers/repair-target/current-attempt |
| architecture-design | human approval | cr_id + sdd.yml verdict | approve/reject 结构化决定（不改 annotation） |
| architecture-design | approve-tech-design | cr_id（+ workspace inspect 入口，见 §3.0）；**approver 不由 Pipeline 取值** | 审批记录、当前 status |
| architecture-design | push-progress | cr_id、message=架构设计已审批（+ workspace inspect 入口） | batchId、repositories、phase（保留「阶段终点/phase=complete/失败只重跑」语义） |
| requirement-authoring | register/PRD/review/approve | 同 skill 输入表，删除命令/路径/章节副本 | execution_context / verdict / 审批记录 |
| code-implementation | plan/TASK/review-dev-plan/approve-dev-start/implement/test-report/review-code/freshness/approve-code | 见 PRD FR-06/FR-07 | 结构化结果 + reviewLoop 路由 |
| product-planning | feedback/market/current-product | topic、skip 标志 | 结构化分析结果 |
| product-planning | node-3 write-competitive-report | 顺序调用链（§4.3）：`fetch-competitor-updates` → `gather-product-context` → `write-competitive-report(updates-block, product-snapshot, confirmed=false)` | **草稿正文（非路径）**：confirmed=false 不落盘，故无报告路径（本 pipeline 人工节点在 node-7） |
| product-planning | write-planning-report | prev_outputs、review_feedback、self_repair_attempt、topic、target_version | 报告路径 + reviewLoop 消费字段 |
| product-planning | review-planning-report | 报告路径、reviewer、topic、target_version、feedback、attempt | approved/blockers/repair-target/current-attempt |
| product-planning | node-7 human approval | 结构化 approve/reject+reason | 决定（不改报告文件；驳回中止正向链） |
| product-planning | node-8 write-roadmap | topic、target_version、planning_report_path | roadmap 更新结果（不写规划报告 `_index.yml`） |
| market-to-plan | extract-market-insight（node-1/2） | insight_source、insight_type、target_version；node-2 加 mode=brief、raw_insight_path | 洞察/简报结构化结果 |
| market-to-plan | node-3 planning-draft | 顺序调用链（§4.3）：`gather-product-context` → `planning-draft(context=快照, intent=从简报提炼的一句话意图, target_version)` | 草稿路径 |
| market-to-plan | write-planning-entry | source、target_version | 规划条目（不碰 market-insights index） |
| competitive-radar | node-1 | competitor-id/competitor-ids[]、lookback-days（Pipeline 只做参数名映射；`slug → competitor-id` 的索引解析归 `fetch-competitor-updates`，Pipeline 不读竞品索引） | updates 结构化输出 |
| competitive-radar | node-2 | 顺序调用链（§4.3）：`gather-product-context` → `write-competitive-report(updates-block, product-snapshot, confirmed=false)` | 草稿（不落盘） |
| competitive-radar | node-3 | reportDraft（或 reportPath） | 规划建议 |
| competitive-radar | node-5 | updates-block、product-snapshot、confirmed=true → write-competitive-report；再 write-planning-entry(source=node-3 输出) | 正式报告 + 规划条目 |
| feature-writeback | node-1 | cr_id（删除 status=code-approved 预检文本） | merge 事务结果 |
| resume-cr | node-3 | cr-id、section=all（调用 cr-show） | cr-show 结构化详情（含最近三次 checkpoint，由 cr-show 输出契约承载） |

补充：product-planning node-3 在 `confirmed=false` 下**无落盘路径**，其输出是草稿正文；node-5 `write-planning-report` 必须消费草稿正文而非引用报告路径，避免聚合节点取到空路径。

### 3.3 不新增的接口

- 不新增 crctl 子命令/参数（FR-13）；
- 不新增 Skill；`skills/_index.yml` 无新增 ref，零改动；
- `agent-skill-matrix.yml` **零改动**：product-planning node-3 调用 `fetch-competitor-updates`/`write-competitive-report` 属跨域调用（两者归 competitive-analyst-agent，product-planning-agent 无 owns/can-call），但这是**现 node-3 prompt 已存在的既有偏差**；本 CR 只补齐必填输入，不扩大也不修复该偏差，FR-13.5/AC-13 的 matrix 自检口径为「与本 CR 前持平」；如需补 can-call 另开 CR；
- 不修改 controlled-shell `rules.json`（deny/白名单零改动）。

### 3.4 approve-* 节点的 approver 取值（含对 PRD 的显式偏离记录，BLK-5 修复）

**实际机制（已核实，不得误写）**：`crctl.mjs:1177`（以及 grant 路径同位逻辑）为 `flags.approver || identity(ws)`——crctl **不**从 owners 回退，缺省值是 `identity(ws)`（`.crctl/config.json#identity` 或 git `user.name`）；owners 回退只存在于 `approve-*` 的 SKILL.md 契约（approve-requirement:26、approve-tech-design:20、approve-code:20、approve-dev-start:24）。

**本 CR 采用的规则**：

1. Pipeline 节点只传 `cr_id`，不在 prompt 里解析或拼接 owners；
2. `approve-*` Skill 按其 SKILL.md 现有契约从 `cr.md owners.{角色}.id` 解析 approver 并**显式传给** `crctl approve`——该 owners 解析是**必需项，不得删除**，否则审批身份退化为本机 git 用户（审计身份漂移）。

**显式偏离记录**：PRD FR-05.2/AC-05 字面要求节点同时传入 `cr_id` 与 `approver`（取自 `execution_context.owners.*.id`）；本 SDD **偏离该项**，理由：

- architecture-design 与 code-implementation 的 `execution_context` 实际只含 `cr_id`/`operational_workspace`[/`resources`]，**无 owners**，PRD 字面路径仅 requirement-authoring 可满足；
- 让 Pipeline 自行解析 owners 恰好违反 FR-05.1（不在 prompt 复制 Skill/crctl 已承担的逻辑）与 §3.0 的「architecture 后续节点不依赖 node-1.md」既有断言。

**Skill 侧配套改动（否则规则 2 无落点）**：四个 `approve-*` SKILL.md 的**执行步骤命令行**现为 `crctl approve {cr_id} --stage X [--grant]`，**未带 `--approver`**（approve-tech-design:25/30、approve-requirement:33/38、approve-code:25/30、approve-dev-start:30/35），owners 回退仅写在各自参数表。因此本 CR 将这四个 SKILL.md 纳入变更对象（§1.1），在其 Step 命令补 `--approver {cr.md owners.{角色}.id}`；否则 Pipeline 停传 approver 后，**本地 TTY 路径**的 `approval.yml` 会落 `identity(ws)`。grant 路径不受影响（approver 取自 `grant.approver`，`crctl.mjs:1301`）。

**AC-05 改判口径**（代码评审期按此判定）：四个 approve 节点含完整 `cr_id`、不含 `crctl approve` 命令细节/TTY/grant/CAS/状态级联文本、且 prompt 不出现 owners 解析与 approver 拼接；approver 由 Skill 侧承担，`approval.yml` 可验证为对应角色 owner（以上述 Skill 命令补 `--approver` 为前提）。**回写期须以 revision 修订 PRD FR-05.2/AC-05 措辞**（工程纪律 4），或以本轮评审记录作为偏离确认依据。

## 4. 关键算法与流程

本 CR 无新增算法；三个关键流程如下。

### 4.1 competitive-radar 草稿/落盘闭环

```text
node-1 fetch-competitor-updates → updates-block（结构化）
node-2 write-competitive-report(confirmed=false) → 仅生成草稿，不落盘
node-3 report-to-planning-suggestion(reportDraft) → 规划建议（无合法 reportPath 时不再报错）
node-4 human_approval 人工确认
node-5 顺序调用：
     ① write-competitive-report(confirmed=true, updates-block, product-snapshot) → 正式报告落盘 + reports index
     ② write-planning-entry(source=node-3 输出) → 规划条目落盘
```

实现要点：node-5 的 prompt 按顺序描述两次 Skill 调用与各自的输入传递（含 node-2 已取得的 `updates-block`/`product-snapshot`）。competitive-radar 无 server Runner（multica Runner 仅 architecture Core，已核实 `runner.go` 只有 `StartArchitecture`），由 Agent 依 prompt 执行，单节点顺序调用两个 Skill 不需要运行时改动；因此不触发 FR-04.4 的「运行时显式支持」分支（该分支为条件性兜底，本 CR 不落地）。

### 4.2 multica registry 再生链（architecture-design 变更的硬依赖）

已核实的事实：

1. `multica/server/internal/governance/gate_nodes_gen.go` 嵌入 `ArchitectureCoreRegistryJSON`（architecture-design 全部 5 节点含 **prompt 全文**、permissions、reviewLoop 契约）与 `ArchitectureCoreRegistryDigest`；
2. `runner.go#parseCoreRegistry` 对 digest 与 5 节点结构 fail-closed；
3. 生成链：`tools/pipeline-templates/emit-registry.mjs --pipeline architecture-design` → registry JSON + `sha256:` digest → `multica gen/generate-gate-nodes.mjs` → 重写 `gate_nodes_gen.go`；
4. `--check` 模式由 multica CI 守卫漂移（比对时剥离 `// Source: tools@<sha>` 行，SHA 变化本身不误报）。
5. **prompt token 硬约束**：`emit-registry.mjs` 的 `ALLOWED` 白名单只放行 `{{inputs.cr_id}}` 与 `{{inputs.tech_context}}`，architecture prompt 重写若引入任何新 `{{…}}` token 会 `REGISTRY_PROMPT_TOKEN_INVALID` 硬失败——这是 architecture-design 收敛的实施前置约束。

结论：**修改 architecture-design.pipeline.json 的 prompt（本 CR FR-01/05/06/07/08/09 必改）后，必须在 multica worktree 重跑生成器并提交 gate_nodes_gen.go**，否则服务器端 Runner 执行的是旧 prompt——FR-01 的受保护路径修复在运行时不会生效，且 CI 漂移检查失败。本 CR 不改 runner 逻辑与 registry schema，只更新其生成产物。

实施顺序约束：architecture-design 的 pipeline 修改与 gate_nodes_gen.go 再生同批完成（阶段二第 1 项内闭环）；再跑 multica 既有 governance 测试（`runner_contract_test.go`、`gate_nodes_gen --check`）。

### 4.3 上游上下文取得：单节点顺序调用既有 Skill（BLK-1 修复）

三条规划 Pipeline 都缺少 `fetch-competitor-updates` / `gather-product-context` 节点，而下游 Skill 的必填输入正来自它们；PRD FR-12.4 又要求节点数不变。采用与 §4.1/DD-2 相同的模式：**在既有节点的 prompt 内按顺序调用既有 Skill**，不新增节点、不新增 Skill、不改运行时（三条规划 Pipeline 均无 server Runner）。

```text
product-planning node-3：
  fetch-competitor-updates(竞品范围, lookback) → updates-block
  gather-product-context()                    → product-snapshot
  write-competitive-report(updates-block, product-snapshot, confirmed=false)
  # confirmed 固定 false：本 pipeline 的人工节点在 node-7，node-3 阶段无人工确认，按 Skill 两阶段协议只出草稿

competitive-radar node-2：
  gather-product-context() → product-snapshot
  write-competitive-report(updates-block=node-1 输出, product-snapshot, confirmed=false)

market-to-plan node-3：
  gather-product-context() → context
  planning-draft(context, intent=从洞察简报提炼的一句话规划意图, target_version)
```

**必须保留的 skip 分支**：product-planning node-3 首句 `若 {{inputs.skip_competitive}}=true 则输出 SKIPPED 并 return` 不得删除（否则 `inputs.skip_competitive` 悬空）——PRD FR-02.1 只对 node-1/2/4 明写保留 skip 标志，此处一并声明；其余 pipeline 的现有分支条件同样不因本次收敛而变。

**跨域调用范围核实**：`gather-product-context` 与 `write-planning-entry` 已在 competitive-analyst-agent 的 can-call 内，故 competitive-radar node-2/node-5 与 market-to-plan node-3 的顺序调用**不引入新的 matrix 偏差**；唯一既有偏差在 product-planning node-3（见 §3.3）。

各 Skill 的落盘、索引与业务算法仍归其自身；Pipeline 只声明调用顺序与参数传递（仍在五要素范围内："调用哪些 Skill、传什么、消费什么"）。

### 4.4 两阶段实施 gate（AC-14）

阶段一完成判定（全部满足才进入阶段二）：

- AC-01（受保护账本指引为 0）、AC-02、AC-03、AC-04、AC-05（approve 节点契约）对应断言通过；
- 8 条 JSON 可解析、`lint-prompts.mjs` 通过、pipeline-structure 测试通过；
- product-planning / market-to-plan / competitive-radar 三条规划的必填输入映射齐全。

### 4.5 reviewLoop 回修语义（不变）

本 CR 不修改任何 reviewLoop 的 `replayPolicy/replayNodes/maxAttempts/passCondition`；review-tech-design 的回修语义（block → write-tech-design 回修 → 重审）原样保留。PRD FR-08.4 的评审维度扩展只进入 `review-tech-design` SKILL.md 的评审维度正文，不新增评审节点。

## 5. 技术选型与替代方案

- **DD-1 修改面 = prompt 文本 + Skill 最小输入扩展**（不写运行时拦截器）。替代：在 runner/gitguard 加校验拦截越权提示——否决，多一份可执行事实源且触及受控面；现状问题全部可通过收敛文本消除。
- **DD-2 node-5 顺序双 Skill 用 prompt 表达**（不新增节点、不改 multica runner）。替代：拆分两个节点或扩展 runner 支持多 ref——否决，competitive-radar 无 server runner，新增节点会连锁改动 `_index.yml` 与 gate-nodes 生成器；prompt 顺序调用已是 Agent 执行的现有能力。
- **DD-3 multica gate_nodes_gen.go 再生为必经路径**（FR-07 的隐式技术依赖）。替代：改 runner 使其运行时读 tools 文件——否决，破坏「构建 multica 无需 tools checkout」的既有设计（生成器头注释明示），且 digest fail-closed 是安全特性。
- **DD-4 自检防线 = 复用并扩展 `pipeline-structure.test.mjs`**（node --test，零依赖）。替代：新建语义解释器/通用检查框架——否决（PRD FR-13.1 明确禁止）。扩展内容：requirement-authoring 关键顺序与 auto_push 分支断言、code-implementation 两条关键顺序与 reviewLoop replayNodes 断言、P0/P1 收敛的负向文本断言（受保护账本指引/评审维度正文/crctl 命令细节/写死 next 等）。

  **既有断言处置清单（BLK-2 修复，实施必读）**：

  | 位置 | 现有断言 | 处置 | 理由 |
  |---|---|---|---|
  | `:149` | architecture push 节点 prompt 必须匹配 `/crctl checkpoint \{\{inputs\.cr_id\}\} --message/` | **修订**为「prompt 不含 `crctl checkpoint` 命令字面量，且含 `phase` 消费与阶段终点语义」；**修订时必须在用例内保留 CR-2026-044 FR-07 溯源注释**（说明语义改由 `onFail=abort` + phase 断言承载） | 与 FR-07.3 直接互斥；CR-2026-044 FR-07 要保的是「架构终点 checkpoint 不可跳过、失败只重跑」，不回退前序 CR 验收 |
  | `:141-153` 其余项（唯一 push 节点、`onFail=abort`、无 skip 分支、无未解析 workspace 占位符、5 节点） | — | **逐字保留** | 均为本 CR 明确不改的语义 |
  | `:165-183` | 首节点 inspect/healthy/resume/execution_context；architecture 后续节点必须含 `crctl workspace inspect` 且不得含 `node-1.md`；code 后续节点含 `execution_context.operational_workspace` | **逐字保留** | CR-2026-045 设计；§3.0 已把它列为五要素之外的保留项 |
  | `:185-188` | `implement-code` 用 `resources[].worktreePath`；`:188` 断言不得出现 `.rayai-worktrees/` | **逐字保留** | 与 FR-07.6 同向 |
  | `:114-117` | code 审批节点（`…0010`）approvalPrompt 含评审后 checkpoint `phase=complete` 前提 | **逐字保留**（FR-01 改写该 approvalPrompt 时保留该句） | 审批前置证据语义 |
  | `:77-89` | pipeline prompt 无 git/journal 字样；write-test-report replayNodes 未改动 | **逐字保留** | 与 FR-06/FR-07 同向 |
  | `:73-74`、`:133`、`:157`、`:160`、`:38`（同形断言另在 `:65`） | 保留型 prompt 字面量：workspace-freshness 两节点的 `implement-start`/`review-start` gate 名；requirement-authoring 草稿 checkpoint 的 `auto_push_after_prd`；code 终点 checkpoint 的「审批结果」label；TASK checkpoint 的 `auto_push_after_task`；checkpoint/freshness 节点 prompt 的 `cr_id` 引用 | **逐字保留** | FR-07.7/FR-09 收敛时最易被顺手删除 |
  | `:91-107` | `_index.yml#nodes` 与 JSON 一致；`node.ref` 全为 active；gates/状态机零耦合 | **逐字保留** | FR-12.5/FR-13.2 |
- **DD-5 「最近三次 checkpoint」保留展示、写入 cr-show 输出契约**。替代：删除展示项——否决，属 resume-cr 的产品展示需求；留在 pipeline prompt——正是本次要消灭的重复。
- **DD-6 术语硬化/REST/决策收窄写入 SKILL.md 正文**（按 PRD FR-08 收窄范围文案）。替代：独立术语中心/ADR——否决（PRD FR-13.1）。
- **DD-8 market-insights 生命周期终态暂无写者**：FR-03.3 删除 `write-planning-entry` 对 `docs/market-insights/_index.yml` 的 `published` 写入后，生命周期 `raw → briefed → published` 失去终态写者（`extract-market-insight` 只推进到 `briefed`）。这是 PRD 保守删除的**已知后果而非漏改**：跨文档写入不在该 Skill 契约内，待真实需求出现时再为其设计明确写者。替代：保留现状跨文档写入——否决（越界且不可验收）。
- **DD-7 提交前缀对齐**：`controlled-shell/rules.json` commit 白名单仅允许 `wip: `、`[cr] `、`merge(`，而三处 Skill 指引越界——`write-tech-design/SKILL.md:88` `feat({cr_id}): draft SDD - tech design`、`write-dev-plan/SKILL.md:70` `feat({cr_id}): draft dev plan`、`write-roadmap/SKILL.md:64` `[planning] …`。同属「命令契约漂移」，归入 FR-07 一并改为白名单内前缀（CR 类用 `[cr] `；本 CR 自身即按 `[cr] draft SDD CR-2026-050` 提交）。承载断言：在 `pipeline-structure.test.mjs` 增加一条扫描——所有 `SKILL.md` 的 `Commit：` 指引前缀必须命中 `rules.json` 的 commit shapes（读文件先 CRLF 归一，匹配失败硬失败）。替代：扩展白名单接受 `feat(`/`[planning] `——否决，白名单最小化优先，`[cr] ` 已满足审计需求。

## 6. FR 到技术实现映射

| FR | 技术实现条目 |
|---|---|
| FR-01 | requirement-authoring（`…0011-…0005`）、architecture-design（`…0016-…0003`）、code-implementation **代码审批节点 `…0015-…0010`**（不动 `…0004` 开工确认语义）的 human approval prompt 改为「人工只提交 approve/reject 决定及理由；reject 走 approve-* reject 流程；证据/CAS/回退由 crctl approve 完成」；删除 review-annotations/*.yml 编辑指引，保留 `…0010` 的 checkpoint `phase=complete` 前提句（§3.0）；负向断言覆盖。multica 侧随 architecture 再生生效。 |
| FR-02 | product-planning.pipeline.json：node-1/2/4 传 topic；node-3 按 §4.3 顺序调用 fetch-competitor-updates→gather-product-context→write-competitive-report(confirmed=false)；node-5 传 prev_outputs/review_feedback/self_repair_attempt；node-6 只传契约输入；**node-7（human approval）**改结构化 approve/reject+reason、驳回中止正向链；**node-8（write-roadmap）**只传 topic/target_version/planning_report_path 并删除规划报告 `_index.yml` 跨文档写入。 |
| FR-03 | market-to-plan.pipeline.json：node-3 按 §4.3 顺序调用 gather-product-context→planning-draft(context,intent)；node-2 传 mode=brief、raw_insight_path（extract-market-insight SKILL.md 同步增加两个输入、默认值与缺参硬失败，见 §2.2）；node-5 删 market-insights/_index.yml published 写入。 |
| FR-04 | competitive-radar.pipeline.json：node-1 只做参数名映射（competitor_slug→competitor-id、since_days→lookback-days），slug→id 的索引解析归 fetch-competitor-updates；node-2 按 §4.3 补 product-snapshot 并 confirmed=false；node-3 支持 reportPath/reportDraft 二选一（report-to-planning-suggestion SKILL.md 增加 reportDraft 输入契约 + 优先级规则 + 同步修订前置条件/错误处理表/读写清单）；node-5 顺序双 Skill 并传递 updates-block/product-snapshot/confirmed=true（§4.1）。 |
| FR-05 | 四条 JSON 的 approve-requirement/approve-tech-design/approve-dev-start/approve-code 节点收敛为「传 cr_id、消费结构化结果、下一步以 crctl next 为准」；approver 按 §3.4 由 approve-* Skill 从 owners 解析后显式传给 crctl（Skill 侧 owners 解析为必需项），Pipeline 不拼 owners；删除命令细节/TTY/grant/CAS/状态级联文本。**本项对 PRD FR-05.2/AC-05 有显式偏离，理由与 AC-05 改判口径见 §3.4。** |
| FR-06 | 三条 JSON 的 review 节点 + code-implementation 的 write-test-report/review-code 节点：删除评审维度正文、payload 与 review-record 调用、annotation/traceability 写入、取证命令、测试机器区算法；保留 reviewLoop 机器字段与 replayNodes；review-tech-design SKILL.md 补 FR-08.4 维度。 |
| FR-07 | **SKILL.md 侧（BLK-3 真实落点）**：`write-tech-design/SKILL.md` 删除 Step 1 的 `.rayai-worktrees/...` 路径约定改消费 `operational_workspace`/`resources[].worktreePath`（FR-07.1）、把「与 sdd.md 同一 commit 提交」改为各仓分别提交 + 同批 checkpoint（FR-07.2）、显式声明两个输入、提交前缀对齐（DD-7）。**Pipeline 侧**：architecture-design push-progress 节点删 checkpoint 命令只传 cr_id/message 消费 phase（FR-07.3，配合 DD-4 的 `:149` 断言修订）；requirement-authoring register/PRD 节点删命令与路径副本（FR-07.4/07.5）；code-implementation implement/freshness/write-dev-plan/write-dev-tasks 节点收敛（FR-07.6~07.9）。全程保留 §3.0 的 inspect 入口与 authority path 契约。 |
| FR-08 | write-tech-design SKILL.md：术语硬化收窄（仅模型/状态机/接口契约且歧义/别名/边界风险，每风险术语至少一个代表性边界场景，预检在首次 crctl advance 前）、HTTP/REST 条件触发基线（仓库约定优先）、决策记录三判据；review-tech-design SKILL.md：四维度扩展（数据模型完整性/接口契约/架构合理性/多仓约束）。 |
| FR-09 | 8 条 JSON 删除固定章节、slug 派生、_index.yml 字段/排序、annotation 文件结构、roadmap 幂等追加、竞品报告固定章节描述（并入各 FR 的节点收敛中一次性完成）。 |
| FR-10 | resume-cr.pipeline.json node-3 收敛为调用 cr-show(section=all)；cr-show SKILL.md 输出契约补「最近三次 checkpoint」；四个 CR approve 节点输出不写死下一 pipeline。 |
| FR-11 | feature-writeback.pipeline.json node-1 删除 status=code-approved 预检文本，保留失败中止。 |
| FR-12 | pipeline-structure.test.mjs 按 §5 DD-4 处置既有断言并扩展新断言；机器字段零改动、节点数/UUID 零改动；§3.0 保留项纳入断言面。 |
| FR-13 | 实施期运行三条自检命令 + Skill 自检清单（index/matrix 不漂移、validate-doc 等价校验、controlled-shell、crctl next、受保护账本、CRLF/硬失败）；不新增任何禁止项。 |

## 7. 安全与性能考量

- **受保护面零扩张**：`protectedPaths.deny` 与受控 shell 白名单零改动；所有账本/annotation 写入仍唯一经 crctl；human approval 不再引导直接编辑受保护文件（FR-01 的核心安全修复）。
- **registry 完整性**：architecture-design 变更与 gate_nodes_gen.go 再生同批提交，digest fail-closed 防止运行时执行漂移 prompt；multica CI `--check` 兜底。
- **CRLF/硬失败纪律**：pipeline-structure.test.mjs 读取 JSON 先 `replaceAll('\r\n','\n')`；任何新增解析失败必须硬失败，禁止静默降级（tools ARCHITECTURE.md 硬不变量 4）。
- **性能**：纯文本/契约变更，无运行时开销；唯一执行面影响是 architecture Runner 后续任务使用更新后的嵌入 prompt（同等模型调用成本）。
- **lint 防线**：`lint-prompts.mjs` 现有 R9（下一步统一 crctl next）等规则继续约束 Skill 侧；本 CR 不新增 lint 规则，负向断言与提交前缀扫描（DD-7）由 pipeline-structure 测试承担。
- **非确定性验收项的证据形态**：AC-08（Skill 正文收窄质量）由 `review-tech-design` 对应维度结论 + SKILL.md diff 作证；AC-12（每节点收敛到五要素内）由「负向断言清单全绿 + §3.0 保留项全绿 + review-tech-design 人工判定」三者合成作证（单靠负向断言不足以证明「在五要素内」）；AC-14（两阶段顺序）由 TASK 顺序与 commit/checkpoint 时序作证（§1.4）；AC-05 按 §3.4 改判口径；DD-7 由新增提交前缀扫描断言作证。

## 8. Prompt 采纳影响（条件性评估）

按 write-tech-design SKILL.md 规定，本节在「触及 crctl.mjs dispatch 或 rules.json protectedPaths.deny」时必填。**本 CR 不触及二者**：不新增/修改任何 crctl 子命令、参数或 dispatch 分支；deny 面零改动；Skill 输入扩展（mode/reportDraft）不改变 crctl 命令面。因此本节不列「应改为调用新增子命令」的采纳清单。

但存在一个**非 crctl 面的采纳依赖**，已在 §4.2 单列为硬依赖：architecture-design.pipeline.json 的 prompt 变更必须通过 emit-registry.mjs → generate-gate-nodes.mjs 再生 multica 嵌入 registry——这是「生成链漂移」而非「crctl 命令面采纳」，由实施 TASK 与 CI --check 覆盖。

## 9. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 过度删除真实业务判断（PRD R-01） | 每节点保留五要素；负向断言只针对明确列出的禁止文本 |
| 规划流程闭环破坏（PRD R-03） | competitive-radar 按 §4.1 顺序验证：draft 不落盘、reportDraft 可消费、confirmed=true 落盘在前 |
| multica registry 漂移 | 与 architecture JSON 同批再生 + digest 校验 + --check |
| 测试断言过严导致误报 | 断言面向 machine fields（顺序/ref/onFail/replayNodes）与明确反模式文本；正例反例成对 |
| 与既有断言冲突（BLK-2） | 按 §5 DD-4 的既有断言处置清单逐条修订或保留，禁止为让测试通过而回退 CR-2026-044/045 的语义 |
| 部署新 digest 时在跑的 architecture run 命中 `RunnerErrTemplateDigestMismatch`（`runner.go:574-581`） | 该错误按设计保持 run 存活（非终态）：选择等待在跑 run 收敛后再部署，或临时回滚到其 digest 恢复；本 CR 不改该语义 |
| architecture prompt 引入新 `{{…}}` token 触发 `REGISTRY_PROMPT_TOKEN_INVALID` | 重写时只使用既有两个 token（§4.2 第 5 条），再生前先本地跑 `emit-registry.mjs` 验证 |

## 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-21 | v0.1.3 | Ray | 第 3 轮评审（pass）同步采纳建议：§3.4 补 approve-* SKILL.md 命令补 `--approver` 的配套改动与 AC-05 前提（S4）；§3.1 补 lint R1 风险——收敛后禁残留 deny 路径字面量（S6）；§4.3 补 skip_competitive 保留与跨域调用范围核实（S5）；修正 §3.0 `:114-117` 与 DD-4 `:38`/`:65` 行号（S1/S2） |
| 2026-08-21 | v0.1.2 | Ray | 第 2 轮评审回修（attempt 2，BLK-5）：新增 §3.4 approver 取值与对 PRD FR-05.2/AC-05 的显式偏离记录（更正「crctl 从 owners 回退」事实错误）；修正 DD-4 行号并补保留型 prompt 字面量；限定 execution_context 字段集；补 AC-12 证据形态、matrix 跨域调用口径、DD-8、node-3 草稿输出形态 |
| 2026-08-21 | v0.1.1 | Ray | 首轮技术评审回修（attempt 1，4 条 blocker）：新增 §2.3 上游输入产出方与 §4.3 单节点顺序调用链（BLK-1）；新增 §3.0 机器契约保留项与 DD-4 既有断言处置清单（BLK-2）；FR-07.1/07.2 改到 write-tech-design SKILL.md 真实落点（BLK-3）；修正 product-planning 节点编号与代码审批节点 UUID（BLK-4）；并收纳 approver 取值、token 白名单、digest 风险、DD-7 扩面等建议 |
| 2026-08-21 | v0.1.0 | Ray | 初始 SDD：两阶段实施、8 pipeline 收敛契约、competitive-radar 闭环、multica registry 再生链、DD-1~DD-7 决策 |

## IM 渠道审批接入 — 飞书审批提醒卡片（通知型 MVP）（v0.25 · CR-2026-051）

## 0. 输入与前置事实

| 项 | 值 |
|---|---|
| PRD | `change-requests/CR-2026-051/prd.md`，sha256 `b64a92cfe182…`（33911 B，已核） |
| CR 状态 | 进入本 Skill 前 `requirement-approved` → 已 `crctl advance --to tech-designing --trigger write-tech-design` |
| operational workspace | `…\.rayai-worktrees\knowledge-base\requirement\CR-2026-051`（`crctl workspace inspect` 原样值） |
| 目标代码仓 | `multica` → `…\.rayai-worktrees\multica\requirement\CR-2026-051`（`resources[].worktreePath`），三仓 resources 全 `healthy`、`dirty=false` |
| 架构基线 | 上述 multica worktree 根 `ARCHITECTURE.md`（**已存在，直接引用，未改**）。`tools` 仓本 CR 零改动，其 `ARCHITECTURE.md` 与本设计无关、未参考 |
| 本文引用的 multica 代码事实 | 均在上述 multica worktree（分支 `requirement/CR-2026-051`）内当场核实，非照抄 PRD 措辞 |
| 评审回修输入 | `change-requests/CR-2026-051/review-annotations/sdd.yml`：`verdict: block`，BL-1～BL-4 全 P1，`review-loop.review-tech-design.current-attempt: 1`，`subject-sha256 f56d38e9…`（= 本次修订前的 sdd.md，已当场核对一致，LF 口径） |
| 本次修订模式 | reviewLoop 回修（Skill Step 1/Step 2 自修复分支，允许 status = `tech-designing`）：按 BL-1～BL-4 逐条定点修复 + 三项评审定案落地 + 三条非阻塞建议处理；整体方案骨架不重写 |

本 SDD 只做技术方案，不改 PRD 的 FR/AC 与范围红线（设计稿 §2.2 排除项）。**一处需要审批确认的边界**：BL-4 要求事件契约必须在跨包可编译位置，落点为 `server/pkg/protocol/events.go`（+1 常量 +1 载荷类型），这比 PRD FR-10 的字面改动清单多一个文件。本 SDD **不自行改 PRD 字面**，而是把该 delta 显式列出（§5 DD-4、§6 FR-10 行、§8），供 `approve-tech-design` 确认或驳回（驳回则退化为 DD-4 备选 1）。

---

## 1. 架构概览

### 1.1 模块边界

新增**两个自研文件**（全部在 multica 仓），加**五处最小挂钩**（其中 `pkg/protocol/events.go` 为 BL-4 修复新增，见 §5 DD-4）：

```text
server/pkg/protocol/events.go                            [改：挂钩点，~2 行 —— BL-4]
  ├─ EventCRApprovalGateEntered      事件名唯一声明（governance 与 lark 共同引用）
  └─ ApprovalGateEnteredPayload      载荷类型唯一声明（canonical JSON 形状）
        ▲ 被 import（governance / lark 均已 import pkg/protocol，无新依赖方向）
server/internal/governance/crsync.go                    [改：挂钩点，~18 行]
  └─ applyStatus() 可信转换分支 → publishApprovalGateEntered()
        │ events.Bus.Publish（同步、进程内）
        ▼
server/internal/integrations/lark/approval_reminder.go   [新：自研，提醒器]
  ├─ Register(bus)                     订阅 cr:approval-gate-entered（无条件注册）
  ├─ handleEvent(e)                    ★ bus 回调：仅解析 + 信号量 TryAcquire + go
  └─ deliver(ctx, ev)                  异步：读链 → 收件人 → 逐个单次发送 → 日志
        │
        ├──► reminderReader（同文件内私有）  workspace-closed 只读链（pgx，分类用）
        ├──► installationCredentialSource   InstallationService.GetInWorkspace（凭据水化，
        │                                   workspace+channel_type 由上游查询闭合）→ DecryptAppSecret
        └──► approvalCardSender             APIClient.SendApprovalReminderCard

server/internal/integrations/lark/approval_reminder_card.go [新：自研，卡片与传输]
  ├─ ApprovalReminderParams            最小参数类型
  ├─ approvalReminderTemplate()        卡片 JSON 模板
  ├─ (*httpAPIClient) SendApprovalReminderCard()   真实传输（open_id 私聊）
  └─ (*stubAPIClient) SendApprovalReminderCard()   stub：Warn + ErrAPIClientNotConfigured

server/internal/integrations/lark/client.go              [改：挂钩点，1 行接口方法]
server/internal/integrations/lark/http_client.go         [改：挂钩点，传输段提取为私有 helper]
server/cmd/server/router.go                              [改：挂钩点，~12 行 wiring]
```

依赖方向（不新增反向依赖）：

```text
cmd/server/router.go            composition root：构造 + 订阅（在飞书密钥条件块之外）
  → integrations/lark（提醒器 + 卡片 + 传输）
  → internal/events.Bus（只订阅，不改）
  → pgxpool（只读）、InstallationService（workspace-scoped 安装读取 + 解密凭据）
governance/crsync.go            只发布事件，不认识 lark 包（单向）
  ↘
   pkg/protocol（叶子包，零 internal 依赖）← lark 也 import 同一个包
```

`governance` 不 import `lark`，`lark` 不 import `governance`：两侧的编译期共同点只有叶子包 `pkg/protocol`（事件名 + 载荷类型），运行期只通过 `events.Bus` 传递。这是 `ARCHITECTURE.md` §4「fork governance may consume existing services and events, but must not duplicate task execution / Git transactions / CR state machines」的合规形态，也是 BL-4 要求的「可编译跨包契约」——**不再依赖字符串字面量与 `any` 断言的隐式约定**（原设计把常量与载荷类型放在 `governance/crsync.go`，lark 侧无从类型断言，正是 BL-4 指出的缺陷）。

### 1.2 关键流程

```text
daemon POST /api/daemon/cr-events
  → HandleCREvents（workspaceID 来自 DaemonAuth，唯一可信锚点）
  → ingest（cr_sync_event 幂等入账 ON CONFLICT DO NOTHING）
  → applyStatus
       ├─ curStatus == ev.FromStatus && KnownStatuses[ev.ToStatus] && IsLegalTransition(...)   ← 唯一可信分支
       │    ├─ UPDATE cr SET status = ev.ToStatus
       │    ├─ projectGateTransition(...)
       │    └─ publishApprovalGateEntered(ws, ev)     ← ★ 本 CR 唯一新增发布点
       │         └─ 仅当 ev.FromStatus != ev.ToStatus 且 ev.ToStatus ∈ 四门禁
       └─ else → needs_reconcile = TRUE（不发布）
  → publish（既有 cr:updated，未改）
  → HTTP 200 返回（r.Context() 随响应写出被取消）

  ┌─ 同步（bus 回调，零 I/O，微秒级）────────────────────────┐
  │ handleEvent(e): 解析 payload → 校验字段 → sem TryAcquire  │
  │   acquire 失败 → 记 reason=overloaded 事件级日志 → return  │
  │   acquire 成功 → go deliver(...) → 立即 return             │
  └────────────────────────────────────────────────────────────┘

  ┌─ 异步（独立 goroutine，context.Background() 派生）────────┐
  │ defer recover()（自持）；defer sem 释放                    │
  │ ctx, cancel = WithTimeout(Background(), 60s)               │
  │ 1. 飞书可用性判定（零 DB）    不可用 → feishu-disabled     │
  │ 2. appURL 判定（零 DB）       空串 → app-url-missing       │
  │ 3. 读链（每跳带 workspace_id = 锚点，fail-closed）         │
  │      cr → issue → project → workspace.slug                 │
  │      → member(role ∈ owner/admin) → binding ⋈ installation │
  │      DB 报错（非零行）→ 事件级 result=failed（不是 skip）  │
  │ 4. 逐收件人：分类 → 登记 attemptedOpenIDs（发送前！）      │
  │      → GetInWorkspace 水化凭据 + 状态/租户复核             │
  │      → WithTimeout(ctx, 10s) → SendApprovalReminderCard    │
  │ 5. 三类结果日志 sent/failed/skipped（§4.6 字段口径）       │
  └────────────────────────────────────────────────────────────┘
```

`HandleCREvents` 的响应时延只增加"bus 回调内的解析 + 一次非阻塞 channel send"，不含任何 I/O 等待——这是 AC-11 可断言的边界。

### 1.3 已核实的既有事实（本设计的地基）

| 事实 | 核实位置 |
|---|---|
| `events.Bus.Publish` 逐个**同步**调用订阅者；recover 只包住同步 handler，**不覆盖派生 goroutine** | `server/internal/events/bus.go`（`for _, h := range handlers { func(){ defer recover(); h(e) }() }`） |
| 状态消费走请求 ctx | `crsync.go#HandleCREvents` 传 `r.Context()` 进 `ingest` |
| 唯一可信转换分支持有 `FromStatus`/`ToStatus` | `crsync.go#applyStatus` 第 435 行的 `if curStatus == ev.FromStatus && KnownStatuses[...] && IsLegalTransition(...)` |
| 事件幂等键 | 迁移 391 `cr_sync_event_workspace_dedup_idx UNIQUE (workspace_id, cr_id, commit_sha, event_kind)` |
| `--embedded` 占位 sha 形状 | `crsync.go` 常量 `pendingShaPrefix = "pending:"`，crctl 侧 `pending:{ms}:{pid}:{seq}` |
| `channel_installation.status` CHECK | 迁移 124 `CHECK (status IN ('active','revoked'))`；撤销保留行（`handler/lark.go#RevokeLarkInstallation`） |
| channel_* 无外键、无 cascade，完整性归应用层 | 迁移 124 文件头两条硬规则 |
| 按 open_id 私聊发卡已有先例 | `http_client.go#SendBindingPromptCard`（`receive_id_type=open_id`）；`SendInteractiveCard` 走 `outboundMessageRequest` 固定 `receive_id_type=chat_id`，**不能**用于 open_id 私聊 |
| 有界超时同口径先例 | `outbound.go#Patcher.handleEvent`：`context.WithTimeout(context.Background(), 10*time.Second)`，注释明写"bus 同步投递，卡住的 Lark HTTP 会 wedge 整个 publish 调用点" |
| 飞书为条件装配；stub 零 HTTP | `router.go` 第 468 行 `if larkKey, err := secretbox.LoadKey("MULTICA_LARK_SECRET_KEY"); err == nil`，else 第 639 行 `lark integration disabled`；`client.go#stubAPIClient` 所有方法 Warn + `ErrAPIClientNotConfigured`；`ChannelRouter` 为无条件构建先例 |
| appURL 解析 | `router.go#appURLFromEnv()`：`MULTICA_APP_URL` → `FRONTEND_ORIGIN` → `""`，均 `TrimRight(…, "/")` |
| 现有查询确有"仅按外键"路径 | `governance/project_gates.go` 的 `cr JOIN issue ON issue.id = cr.shell_issue_id` 未比对 `cr.workspace_id = issue.workspace_id` |
| 可复用的绑定查询与其缺口 | `queries/channel.sql#FindChannelBindingForMember`（workspace + user + channel_type + `ci.status='active'` + `ORDER BY b.bound_at DESC LIMIT 1`）——**缺** `ci.workspace_id`/`ci.channel_type` 闭合，且"无行"无法区分 missing/revoked/orphan（详见 §5 DD-2） |
| 凭据水化路径（BL-1 的答案） | `InstallationService.GetInWorkspace(ctx, id, workspaceID)`（`installation.go:110`）→ `ChannelStore.GetLarkInstallationInWorkspace`（`channel_store.go:89`）→ sqlc `GetChannelInstallationInWorkspace`（`queries/channel.sql:82`，**WHERE id + workspace_id + channel_type 三条均带**）→ `installationFromRow`（`store.go:144`）把 JSONB `config` 解成 `AppID`/`AppSecretEncrypted`/`TenantKey`/`BotOpenID`/`Region`；无行返回 `ErrInstallationNotFound`。**已有上游查询，本 CR 不新增 sqlc** |
| 凭据组装现成 helper | `installationCredentialsFor(inst, resolver)`（`feishu_channel.go:104`，包内私有，**零改动直接复用**）：resolver 为 nil 报错、`DecryptAppSecret(inst)` 解密、把 `AppID`/`TenantKey`/`RegionOrDefault(Region)` 装成 `InstallationCredentials`（`client.go:341`） |
| 安装凭据存在 JSONB `config` 里，裸 SQL 取不到平展字段 | `store.go` 文件头 + `feishuInstallConfig`（`store.go:127`）：`app_id`/`app_secret_encrypted`（base64）/`tenant_key`/`bot_open_id`/`region` 全在 `config` JSONB；`decodeSecret` 还需容忍迁移回填的 MIME 折行 base64。这正是 BL-1 指出的缺口：分类用的裸 SQL **不应**自己解 config，而应走上游已有解码入口 |
| 事件契约共享的既有先例（BL-4 的答案） | `pkg/protocol/events.go:191-196` 已有 fork 新增的 `// AIFIRST:` 常量 `EventCRUpdated = "cr:updated"`，注释明写「governance.EventCRUpdated references this constant rather than duplicating the string literal」；`governance/crsync.go:48` 就是 `const EventCRUpdated = protocol.EventCRUpdated`。CUSTOM.md #22/#23（CR-2026-010 / CR-2026-011 TASK-05）已登记对 `pkg/protocol/events.go` 的同类改动 |
| 两侧均已 import `pkg/protocol` | `governance/crsync.go`（同上）；lark 包在 `outbound.go` / `registration_service.go` 已 import。`pkg/protocol` 自身零 `internal/` 依赖（叶子包）——把契约放进去**不新增任何依赖方向、无环风险** |
| 总线事件会被 WS 广播（决定载荷形状） | `cmd/server/listeners.go:207` 的 `bus.SubscribeAll` 把**每个**非 personal / 非 chat-scoped 事件经 `projectOutbound` + `json.Marshal` 广播到 workspace 房间；`projectOutbound`（`listeners.go:51`）对未登记 `internalOnlyPayloadKeys` 的类型原样返回，所以结体载荷按 json tag 序列化——载荷的 JSON 形状本身就是一份对外契约（§3.2.1 固定之） |
| 前端对未知事件类型免疫 | `packages/core/api/ws-client.ts:102-141`：无 string `type` 的帧丢弃，否则 `handlers.get(msg.type)` 为空即不处理；`use-realtime-sync.ts:960` 的 `onAny` 按前缀查 `refreshMap`，而 `refreshMap` **无 `cr` 键**（仅 inbox/agent/member/…/task）。新事件对前端是 **no-op**，本 CR 前端零 diff（与 CUSTOM #23 需成对贴回 `core/types/events.ts` 的情形不同） |
| `applyStatus` 手上的 cr 字段（BL-3 的可行性） | `crsync.go:399-401` 的 `SELECT status FROM cr WHERE workspace_id = $1 AND cr_id = $2`——现只取 status；带上 `shell_issue_id` 只需把该既有查询扩为两列（同文件内，零新增往返） |
| 字符串 → `pgtype.UUID` | `internal/util.ParseUUID`（`util/pgx.go:19`）；lark 包已 import `internal/util` |
| 飞书未启用时 `h.LarkAPIClient` 是 **nil 而非 stub**（修正初稿的措辞） | `router.go:502` 是全文唯一赋值点且在 `MULTICA_LARK_SECRET_KEY` 成功分支内，`handler.New` 不给默认 stub；`h.LarkInstallations` 同理保持 nil。故 `feishu-disabled` 判定必须先接 nil，且要防 typed-nil 接口陷阱（§3.2.3）；stub 仅作测试替身（AC-12） |

---

## 2. 术语硬化（Step 2.5 前置，首次状态推进前完成）

只处理进入数据模型 / 状态机 / 接口契约、且存在歧义或别名的术语。`CONTEXT.md` 与 PRD §1.3 术语表只读沿用。

| PRD canonical term | 代码别名 / 取值 | 边界场景（已验证） | 硬化结论 |
|---|---|---|---|
| 飞书渠道 | Go 包名 `lark`；DB 判别值 `channel_type = 'feishu'`；`Installation.Region` 区分 Feishu 大陆 / Lark 国际 | 迁移 124 把既有行 backfill 成 `channel_type='feishu'`；`'lark'` **不是**合法判别值 | 一切 DB 谓词写 `'feishu'`；包名/类型名沿用 `lark` 前缀（传输族），二者不互推 |
| **stage（审批阶段）** | ① `approval_record.stage` = `gates.json#approvalStages` 四键（`requirement`/`tech-design`/`dev-start`/`code`）；② PRD §4.4 的日志 `stage` = **事件的新状态**（`requirement-reviewing` 等） | 两者一一对应但**字面不同**，混用会让日志检索与审批账本对不上 | 日志字段 `stage` **一律取 CR status 字面值**（`requirement-reviewing`/`tech-design-review-pending`/`task-breakdown`/`code-reviewing`）；卡片上的中文阶段名是**展示层映射**（§4.3 表），不落日志、不与 `approval_record.stage` 混用；本 CR 不读写 `approval_record` |
| 有效（飞书）绑定 | 代码无此概念；最近似的 `FindChannelBindingForMember` 只校验 `b.workspace_id` + `b.channel_type` + `ci.status='active'` | 安装被撤销后绑定行保留（`status='revoked'`）；`installation_id` 可悬空（无外键）；`ci.workspace_id` 未被校验 | SDD 定义 `effectiveFeishuBinding` = PRD FR-5 三条件，**不**把 `FindChannelBindingForMember` 当唯一判据（§5 DD-2） |
| event_id | `events.Event` 无此字段；`cr_sync_event` 有 PK `id BIGSERIAL` 与幂等键 `(workspace_id, cr_id, commit_sha, event_kind)` | `--embedded` 模式 `commit_sha` 为 `pending:{ms}:{pid}:{seq}` 占位符——仍逐事件唯一，幂等键不退化；不同 workspace 可存在同名 CR（`cr` 的唯一键是 `(workspace_id, cr_id)`），故三段投影**全局不唯一** | `event_id = "{cr_id}:{event_kind}:{commit_sha}"`；**检索与对账的完整相关键是二元组 `(workspace_id, event_id)`**（`workspace_id` 既在事件 envelope 也是必填日志字段）——日志检索/文档/测试一律写二元组口径，不得单拿 `event_id` 当全局唯一键（§5 DD-1） |
| shell_issue_id（新增，BL-3） | `cr.shell_issue_id`（迁移 362，可 NULL）；载荷字段 `shell_issue_id *string`（JSON **键恒在、无值为 `null`**，即**不加** `omitempty`——dev-plan 评审已定案，初稿此处的 `omitempty` 括注是笔误，见 §9） | 历史 CR 为 NULL；跨 workspace 异常关联时该 issue 可能不属于锚点 workspace（PRD 澄清 4） | 载荷携带它以满足 FR-1 的「CR/issue 关联标识」，但它**只作相关/诊断字段，不得作为查询输入**；目标项目仍按 FR-3 从 PG 事实（`cr` 行）重新解析（ARCHITECTURE §7：bus 是通知不是持久权威，handler 必须可重放） |
| recipient | Multica `user.id`（权威）vs 飞书 `open_id`（= `channel_user_binding.channel_user_id`） | PRD §4.4 已定口径 | 日志 `recipient_user_id` 必填、`recipient_open_id` 仅发送成功/失败时出现；去重第一键是 user id |
| workspace 锚点 | `HandleCREvents` 中 `resolveDaemonWorkspace(r, s.pool)` 的返回值 | 请求体 `workspace_root_hash` 仅日志用，不可作信任输入（既有 SDD-SUG-002） | 锚点只能来自 DaemonAuth；`events.Event.WorkspaceID` 承载它，消费侧不得用读到的任何 `workspace_id` 覆盖锚点 |

**无语义冲突需要需求负责人裁决**，故未中断流程。

**HTTP/REST 契约：不触发。** 本 CR 不新增或修改任何 HTTP API（无新路由、无新请求/响应体、无鉴权面变化）；`router.go` 的改动只是进程内 wiring 与事件订阅。故本 SDD 不含接口契约中的 HTTP 章节，§3 只写进程内接口。

---

## 3. 数据模型与接口契约

### 3.1 数据模型：零 DDL

**不新增表、不新增列、不新增索引、不新增 migration。** 全部为只读消费既有表：

| 表 | 读取列 | 用途 | 读取方式 | 归属 |
|---|---|---|---|---|
| `cr` | `status`、`shell_issue_id`（发布侧）；`cr_id`、`workspace_id`、`title`、`shell_issue_id`（提醒器侧） | 载荷 issue 关联 + 事件锚定 + 卡片标题 | 发布侧：`applyStatus` 既有 SELECT 扩为两列；提醒器侧：§4.4 第一条 SQL | fork（迁移 362） |
| `issue` | `id`、`workspace_id`、`project_id` | 项目解析 | §4.4 第一条 SQL | 上游 |
| `project` | `id`、`workspace_id` | 项目存在性 + CTA projectID | §4.4 第一条 SQL | 上游 |
| `workspace` | `id`、`slug` | CTA workspaceSlug | §4.4 第一条 SQL | 上游 |
| `member` | `workspace_id`、`user_id`、`role` | owner/admin 收件人集合 | 成员查询（§4.2 步骤 3） | 上游（`role CHECK IN ('owner','admin','member')`） |
| `channel_user_binding` | `id`、`workspace_id`、`multica_user_id`、`installation_id`、`channel_type`、`channel_user_id`、`bound_at` | 绑定与 open_id | §4.4 第二条 SQL | 上游（迁移 124） |
| `channel_installation` | 分类：`id`、`workspace_id`、`channel_type`、`status`（均为平展列）；凭据：整行含 `config` JSONB | 有效性分类 + 发送凭据 | 分类走 §4.4 第二条裸 SQL；**凭据走既有 sqlc `GetChannelInstallationInWorkspace`**（`GetInWorkspace`），`config` 由 `installationFromRow` 解码，不在裸 SQL 里解 | 上游（迁移 124） |

索引覆盖核实：`cr` 有 `UNIQUE (workspace_id, cr_id)`；`issue`/`project`/`member` 主键与 workspace 列既有索引足够（单次门禁收件人规模为个位数，读放大可忽略）；`channel_user_binding` 有 `UNIQUE (installation_id, channel_user_id)`。**无需新索引**。

### 3.2 进程内接口契约

#### 3.2.1 事件契约（governance → bus → lark）

```go
// server/pkg/protocol/events.go  —— BL-4：事件名与载荷类型的唯一声明处
// （先例：同文件 191-196 行的 AIFIRST 常量 EventCRUpdated，governance 侧取别名）

// AIFIRST: CR-2026-051 FR-1 — dedicated approval-gate semantic event.
// Deliberately NOT EventCRUpdated: that one is published from 5 sites
// (3x crsync, gate_projection, reconcile) and would fire on projection
// maintenance, not on a fresh approval request. Declared here (not in
// internal/governance) because BOTH the producer (internal/governance)
// and the consumer (internal/integrations/lark) must share one
// compile-time contract without importing each other.
EventCRApprovalGateEntered = "cr:approval-gate-entered"

// ApprovalGateEnteredPayload carries only location identifiers. Approval
// evidence, titles, project ids and recipients are deliberately absent —
// the consumer re-reads them from PostgreSQL so handlers stay replayable
// (ARCHITECTURE.md §7: the bus is notification, not durable authority).
//
// This struct is ALSO the outbound WS frame shape: listeners.go
// SubscribeAll marshals every bus payload to the workspace room, so the
// json tags below are a client-visible contract — additive changes only.
// ShellIssueID is a pointer because cr.shell_issue_id is nullable
// (migration 362); it is a correlation field only and MUST NOT be used
// as a query input (FR-3 resolves the project chain from PostgreSQL).
type ApprovalGateEnteredPayload struct {
    CRID         string  `json:"cr_id"`
    Status       string  `json:"status"`         // ev.ToStatus, one of the four gates
    EventID      string  `json:"event_id"`       // "{cr_id}:{event_kind}:{commit_sha}"
    ShellIssueID *string `json:"shell_issue_id"` // nullable; correlation only
}
```

`governance` 侧只保留别名与四门禁集合（与既有 `EventCRUpdated` 完全同构）：

```go
// server/internal/governance/crsync.go

// AIFIRST: CR-2026-051 FR-1 — alias of the shared protocol constant,
// same shape as EventCRUpdated above (line 48): the string literal is
// declared once, in pkg/protocol.
const EventCRApprovalGateEntered = protocol.EventCRApprovalGateEntered

// approvalGateStatuses are the four human-approval gates (PRD FR-1 cond. 4),
// verified against ../tools/dir-graph.yaml#change-request-track.state_machine.
var approvalGateStatuses = map[string]bool{
    "requirement-reviewing":      true, // 需求审批
    "tech-design-review-pending": true, // 架构审批
    "task-breakdown":             true, // 开发启动审批
    "code-reviewing":             true, // 代码审批
}
```

消费侧（lark）的解析因此是**真正的类型断言**，而不是 map 取键：

```go
// server/internal/integrations/lark/approval_reminder.go
func parsePayload(v any) (protocol.ApprovalGateEnteredPayload, bool) {
    p, ok := v.(protocol.ApprovalGateEnteredPayload)   // compile-time contract
    if !ok || p.CRID == "" || p.Status == "" || p.EventID == "" {
        return protocol.ApprovalGateEnteredPayload{}, false
    }
    return p, true
}
```

上游若改字段名/类型，两侧同时 build 失败（而不是运行时静默停摆）——这是 BL-4 要求的可编译契约。**不支持** map 形态回退解析（不写 `map[string]any` 分支）：多一条宽容路径就多一个无人覆盖的静默降级面。

发布点（`applyStatus` 可信分支内，`projectGateTransition` 之后）：

```go
// AIFIRST: CR-2026-051 FR-1/FR-2 — publish only from the trusted branch,
// only on a real status change, only for the four approval gates.
// shellIssueID comes from the same SELECT that already read curStatus
// (one query, two columns) — no extra round trip, no signature change
// on ingest/apply.
func (s *SyncService) publishApprovalGateEntered(workspaceID string, ev OutboxEvent, shellIssueID *string) {
    if s.bus == nil || ev.FromStatus == ev.ToStatus || !approvalGateStatuses[ev.ToStatus] {
        return
    }
    s.bus.Publish(events.Event{
        Type:        EventCRApprovalGateEntered,
        WorkspaceID: workspaceID,
        ActorType:   "system",
        Payload: protocol.ApprovalGateEnteredPayload{
            CRID:         ev.CRID,
            Status:       ev.ToStatus,
            EventID:      ev.CRID + ":" + ev.EventKind + ":" + ev.CommitSHA,
            ShellIssueID: shellIssueID,
        },
    })
}
```

`shellIssueID` 的取值方式（BL-3 的最小改法）：把 `applyStatus` 开头那条既有查询从 `SELECT status` 扩为 `SELECT status, shell_issue_id`（`crsync.go:399`，同一 workspace 谓词不变），扫进 `*string`。`found == false` 分支不用该值（也不发布）。**不**在发布点另开一次查询：那样会多一次往返，也会引入一个与本次转换不同时点的读取。

契约不变量（供 AC-1/AC-2 断言）：

1. 只在 `applyStatus` 的可信分支调用——`found == false` 的首次见闻分支**不**调用（`legalFresh` 为真也不调用：注册转移的目标状态不可能是四门禁之一，且首次见闻本身可能缺历史）；
2. `else` 分支（乱序 / 非法，只置 `needs_reconcile`）不调用；
3. `apply` 的 `checkpoint` / `review` / `trace` / default 分支不调用；
4. `reconcile.go`、`gate_projection.go` 不调用；
5. 自环（`from == to`）被条件 1 过滤；
6. **canonical JSON 形状**：`{"cr_id":"…","status":"…","event_id":"…","shell_issue_id":"…"|null}`——由 `pkg/protocol` 的 json tag 唯一定义，同时是 WS 广播帧的 payload（§1.3 已核：`listeners.go` 的 `SubscribeAll` 会把它广播到 workspace 房间）；只允许加字段，不得改/删现有键名（ARCHITECTURE §5 不变量 8：客户端容忍加法漂移）；
7. 载荷只做定位与相关：`shell_issue_id` **不进任何 SQL 参数**，消费侧仍按 FR-3 从 `cr` 行重新解析（AC-10 的跨 workspace 负向断言因此对载荷伪造也成立）。

#### 3.2.2 传输契约（lark 包内）

```go
// server/internal/integrations/lark/approval_reminder_card.go

// ApprovalReminderParams is the minimal input for the approval reminder
// card. Mirrors BindingPromptParams: credentials + open_id + one CTA URL,
// plus the three display fields FR-6 allows. No approval evidence, no diff.
type ApprovalReminderParams struct {
    InstallationID InstallationCredentials
    OpenID         OpenID
    CRID           string // "CR-2026-051"
    CRTitle        string // cr.title; empty renders CRID only
    StageLabel     string // display-only Chinese label (§4.3 map)
    ApproveURL     string // {appURL}/{slug}/projects/{projectID}?tab=chat
}
```

`client.go` 的 `APIClient` 接口新增一行（唯一的接口面改动，带 `// AIFIRST:` 标记）：

```go
// AIFIRST: CR-2026-051 FR-9 — dedicated approval reminder outbound.
// Separate from SendInteractiveCard because that one hard-codes
// receive_id_type=chat_id (outboundMessageRequest) and cannot address an
// open_id p2p chat; separate from SendBindingPromptCard because the card
// body and CTA differ. Implementations live in approval_reminder_card.go.
SendApprovalReminderCard(ctx context.Context, p ApprovalReminderParams) error
```

实现均落在自研文件 `approval_reminder_card.go`（Go 允许同包跨文件定义方法，故 `client.go` / `http_client.go` 正文零改动）：

- `func (c *httpAPIClient) SendApprovalReminderCard(...) error` — 复用私有 helper `sendCardToOpenID(ctx, creds, openID, cardJSON)`（由 `SendBindingPromptCard` 的既有逻辑提取，见 §4.5）；
- `func (s *stubAPIClient) SendApprovalReminderCard(...) error` — `Warn` + `ErrAPIClientNotConfigured`，零 HTTP。

#### 3.2.3 提醒器构造契约

```go
// server/internal/integrations/lark/approval_reminder.go

// installationCredentialSource is the narrow seam the reminder needs from
// InstallationService: the workspace-scoped installation read (which also
// fences channel_type) plus app_secret decryption. *InstallationService
// satisfies it as-is; no upstream signature changes (BL-1).
type installationCredentialSource interface {
    CredentialsResolver // DecryptAppSecret(inst Installation) (string, error)
    GetInWorkspace(ctx context.Context, id, workspaceID pgtype.UUID) (Installation, error)
}

type ApprovalReminderConfig struct {
    Pool        *pgxpool.Pool                 // read-only; nil ⇒ reminder degrades to no-op
    Client      APIClient                     // nil or !IsConfigured() ⇒ feishu-disabled
    Credentials installationCredentialSource  // nil ⇒ feishu-disabled
    AppURL      string                        // appURLFromEnv(); "" ⇒ app-url-missing
    Logger      *slog.Logger
    // MaxInFlight bounds concurrent deliveries (FR-8.1). 0 ⇒ default 8.
    MaxInFlight int
    // EventTimeout / RecipientTimeout default to 60s / 10s (FR-8.1).
    EventTimeout     time.Duration
    RecipientTimeout time.Duration
}

// NewApprovalReminder never returns nil: Register/handleEvent must be safe
// to call on any construction outcome (a nil return would panic at the
// unconditional Register call site required by FR-8.3).
func NewApprovalReminder(cfg ApprovalReminderConfig) *ApprovalReminder
func (r *ApprovalReminder) Register(bus *events.Bus)  // Subscribe(EventCRApprovalGateEntered, r.handleEvent)
```

**API 参数不得静默忽略（CONTRIBUTING.AIFIRST 规则六）**：`MaxInFlight` / `EventTimeout` / `RecipientTimeout` 只有“0 值走文档化默认”这一种退化，非零值一律生效。

**依赖缺失的处理（评审非阻塞建议②：不得 panic）**：

- `Pool == nil` / `Credentials == nil` / `Client == nil`：构造函数记一条 `Error` 并返回一个 **标记为 unusable 的真实对象**（不返回 nil）；`Register` 照常订阅（FR-8.3 要求无条件注册），`deliver` 在步骤 1 即以事件级 `feishu-disabled` 返回（处于任何 DB 查询之前）。**不新增第 10 个跳过原因**：FR-8.2 的 9 项枚举是已审批口径，而“依赖未装配”语义与 `feishu-disabled`（飞书 integration 不可用）一致。
- **typed-nil 接口陷阱（只能在 wiring 层防，提醒器内检不出）**：`h.LarkInstallations` 是 `*lark.InstallationService`，飞书未启用时为 nil 指针。直接赋给接口字段会得到一个 `!= nil` 但调用即 panic 的接口值，所以 `router.go` 必须显式判空后才赋值（下方 wiring 片段），提醒器内部不依赖反射。
  - **口径硬化（dev-plan 评审 BL-3）**：§4.2 步骤 1 的 `r.credentials == nil` 对 typed-nil **为假**，这是**已知且有意**的设计选择（不反射 = 规则五「不为边缘情形引入运行时类型窥探」）。因此**提醒器侧不承诺、也不得被要求**「灌 typed-nil 仍得到 `feishu-disabled`」——那个断言在本设计下不可满足（依赖健康时会穿到方法调用后由 goroutine 的 `recover` 变成 panic 日志；靠另一个 nil 依赖短路则根本没验到 typed-nil）。
  - **typed-nil 的回归锁唯一落在 wiring 层**（§7.4 `cmd/server` 行）：正向断言「条件赋值后接口字段 `== nil` 为真」+ 承重性断言「无条件赋值时接口字段 `== nil` 为假」。后者是**执行断言**而非注释，否则「判空是必要的」这条前提永远无人证明，重构时会被当成冗余代码删掉。
  - **两个依赖的 typed-nil 风险不对称（回修期新核实）**：`h.LarkInstallations` 是**具体指针** `*lark.InstallationService`（`internal/handler/handler.go:223`）——typed-nil 陷阱真存在，判空承重；而 `h.LarkAPIClient` 本身就是**接口** `lark.APIClient`（`handler.go:239`）——它为 nil 时赋值得到的仍是 nil 接口，判空对 typed-nil **不承重**，保留只为两个字段形态统一 + 上游日后改成具体类型时不静默退化。因此 §7.4 的承重性断言**只能对 `Credentials` 写**（对 `Client` 写同型断言会失败）。

`Register` 的调用点在 `router.go` 中**飞书密钥条件块之外**（FR-8.3）：

```go
// AIFIRST: CR-2026-051 FR-8.3 — registered unconditionally, OUTSIDE the
// MULTICA_LARK_SECRET_KEY block, so a disabled Lark integration still
// consumes the event and logs a feishu-disabled skip instead of the
// subscription being absent. h.LarkAPIClient / h.LarkInstallations are
// nil in that case: assign them only when non-nil, otherwise the config
// would hold a typed-nil interface that panics on first use.
reminderCfg := lark.ApprovalReminderConfig{
    Pool: pool, AppURL: appURLFromEnv(), Logger: slog.Default(),
}
if h.LarkAPIClient != nil {
    reminderCfg.Client = h.LarkAPIClient
}
if h.LarkInstallations != nil {
    reminderCfg.Credentials = h.LarkInstallations
}
lark.NewApprovalReminder(reminderCfg).Register(bus)
```

飞书未启用时两个依赖均为 nil（§1.3 已核：`router.go:502` 是 `h.LarkAPIClient` 唯一赋值点，**默认不是 stub 而是 nil**）：提醒器在**任何 DB 查询之前**判定不可用（§4.2 步骤 1），故两种形态都收敛到 `feishu-disabled`；测试里可换成 `lark.NewStubAPIClient`（`IsConfigured() == false`）断言零真实请求（AC-12）。

---

## 4. 关键算法与流程

### 4.1 同步侧（bus 回调）：零 I/O + 非阻塞

```text
handleEvent(e events.Event):
    # 只做解析与校验，禁止 DB / HTTP —— AC-11 用零调用替身断言
    p, ok := parsePayload(e.Payload)            # protocol.ApprovalGateEnteredPayload 类型断言 + 字段非空
    if !ok:            log(warn, "malformed payload"); return
    if _, ok := approvalGateStageLabels[p.Status]; !ok:  return   # 防御性二次过滤（lark 侧闭集 = §4.3 展示映射同一份声明）
    if e.WorkspaceID == "":                     log(warn); return

    select:
      case r.sem <- struct{}{}:                 # 非阻塞获取
          go r.deliver(p, e.WorkspaceID)        # 立即返回，不等待
      default:
          logSkip(event, reason="overloaded", p, e.WorkspaceID)   # 丢弃，不排队
    return
```

`sem` 是 `chan struct{}`（容量 `MaxInFlight`，默认 8）。非阻塞 `select` + `default` 是"有上限、过载丢弃、不排队"的最小实现——**不新增队列表、不新增任务框架、不重试**（PRD §7 范围排除）。回调总耗时 = 一次类型断言 + 一次 map 查 + 一次 channel send，无 I/O，故 `HandleCREvents` 时延与"无提醒器"基线同量级。

### 4.2 异步侧（deliver）：fail-closed 读链 + 单次投递

```text
deliver(p, anchorWorkspaceID):
    defer func(){ if v := recover(); v != nil { log(error, "panic recovered", v) } }()   # 自持，bus 的 recover 覆盖不到
    defer func(){ <-r.sem }()                                                            # 释放并发额度
    ctx, cancel := context.WithTimeout(context.Background(), r.eventTimeout)              # 脱离请求 ctx；60s
    defer cancel()

    # ── 1. 飞书可用性（零 DB，最先判）───────────────────────────
    if r.pool == nil || r.client == nil || !r.client.IsConfigured() || r.credentials == nil:
        logSkip(event, "feishu-disabled"); return            # AC-12：零真实请求、零收件人查询；也覆盖依赖未装配（§3.2.3）

    # ── 2. CTA 基地址（零 DB）──────────────────────────────────
    if r.appURL == "":
        logSkip(event, "app-url-missing"); return            # 不发无效链接；不新增 URL 合法性校验器

    # ── 3. workspace-closed 读链（每跳带 workspace_id = 锚点）──
    ctx1 := 单条 SQL（§4.4）：cr ⋈ issue ⋈ project ⋈ workspace，三处 workspace_id = $1
    switch:
      db 报错（非 ErrNoRows）→ logFailEvent(step="project-chain", errClass(err)); return   # 不当 skip
      no rows          → logSkip(event, "project-unresolved" | "workspace-mismatch"); return
      slug == ""       → logSkip(event, "workspace-mismatch"); return

    approvers, err := SELECT user_id FROM member WHERE workspace_id = $1 AND role IN ('owner','admin')
    if err != nil:
        logFailEvent(step="approver-query", errClass(err)); return                         # 不当 skip
    if len(approvers) == 0:
        logSkip(event, "no-approver"); return                                             # AC-4 情形①的原因载体（事件级，见下）

    approveURL := r.appURL + "/" + slug + "/projects/" + projectID + "?tab=chat"

    # ── 4. 逐收件人：分类 → 发送前登记 → 水化凭据 → 单次发送 ──
    attemptedOpenIDs := {}                        # BL-2：语义是"已尝试"，不是"已成功"
    for userID in approvers:                      # 个位数规模，顺序执行
        rows, err := 有效绑定候选（§4.4 第二条 SQL，LEFT JOIN installation）
        if err != nil:
            logFail(userID, "", step="binding-query", errClass(err)); continue              # 不当 skip
        if len(rows) == 0:
            logSkip(recipient, userID, "binding-missing"); continue
        pick, reason := chooseEffective(rows)     # §4.3
        if pick == nil:
            logSkip(recipient, userID, reason); continue      # installation-revoked / -missing / workspace-mismatch

        # ★ BL-2：登记必须早于任何可失败动作（水化 / 解密 / 发送）
        if pick.OpenID in attemptedOpenIDs:
            continue                              # 同一 open_id 单次事件只尝试一次（FR-5/AC-3、FR-8.2）
        attemptedOpenIDs.add(pick.OpenID)

        # ★ BL-1：workspace-scoped 完整安装读取（config JSONB 由上游解码）
        inst, err := r.credentials.GetInWorkspace(ctx, pick.InstallationID, anchorWorkspaceUUID)
        switch:
          errors.Is(err, ErrInstallationNotFound) → logSkip(recipient, userID, "installation-missing"); continue
          err != nil                              → logFail(userID, pick.OpenID, step="credential-hydrate", errClass(err)); continue
        # 租户 / 状态复核（水化后再校一次，封住"分类 → 发送"之间的 TOCTOU 窗）
        if UUIDToString(inst.WorkspaceID) != anchorWorkspaceID:
            logSkip(recipient, userID, "workspace-mismatch"); continue
        if inst.Status != "active":
            logSkip(recipient, userID, "installation-revoked"); continue

        creds, err := installationCredentialsFor(inst, r.credentials)   # 既有 helper：解密 + AppID/TenantKey/Region
        if err != nil:
            logFail(userID, pick.OpenID, step="credential-decrypt", errClass(err)); continue

        rctx, rcancel := context.WithTimeout(ctx, r.recipientTimeout)   # 10s
        err = r.client.SendApprovalReminderCard(rctx, ApprovalReminderParams{...})
        rcancel()
        if err != nil: logFail(userID, pick.OpenID, step="send", errClass(err))   # 单收件人失败不影响同批其他人
        else:          logSent(userID, pick.OpenID)
```

**关键约束的落点**：

- 异步开始时**不重新读 CR 状态**（FR-8.4）——语义是"曾实际进入该门禁"；不做消息撤回、不做补偿；
- `ctx` 由 `context.Background()` 派生，与 `r.Context()` 的生命周期完全解耦；
- 进程退出时在飞 goroutine 允许丢失，**不做 drain/join**（FR-8.4，与既有 crash window 口径一致）；
- 全链只读，无事务、无写入；
- **失败与跳过不同类（评审非阻塞建议③）**：DB 报错、凭据水化/解密报错、发送报错一律记 `result=failed`（带 `error_class` + `step`），**不**占用 FR-8.2 的 9 项 `reason` 枚举；`reason` 只给“按设计不发”的确定态（零行 / 角色不符 / 安装失效 / 未启用 / 过载）。字段口径见 §4.6；
- **尝试登记早于任何可失败动作**（BL-2）：同一 `open_id` 在单次事件内无论首次结果如何，都不会被后续用户再次尝试（卸掉了旧设计“失败就不登记 → 重复发”的退回行为）。

### 4.3 有效绑定选择与去重（`chooseEffective`）

输入是同一 `(workspace 锚点, userID, channel_type='feishu')` 下的全部绑定候选（每行带 LEFT JOIN 到的**安装标识与校验列**：`ci.id`/`ci.workspace_id`/`ci.channel_type`/`ci.status`，可为 NULL）。本函数**只做分类**，不取凭据；凭据由 §4.2 的 `GetInWorkspace` 水化（BL-1）。

```text
chooseEffective(rows):                 # rows 已按 bound_at DESC, id ASC 排序（确定性）
    seenRevoked, seenMissing, seenMismatch := false, false, false
    for row in rows:
        if row.InstallationID is NULL or row.Inst is NULL:  seenMissing  = true; continue
        if row.Inst.WorkspaceID != anchor or row.Inst.ChannelType != 'feishu':
                                                            seenMismatch = true; continue
        if row.Inst.Status != 'active':                      seenRevoked  = true; continue
        return row, ""                 # 第一条命中即 bound_at 最新的有效绑定 → 每用户一张卡
    # 无有效绑定：按"最具体优先"给出唯一可区分原因
    if seenMismatch: return nil, "workspace-mismatch"
    if seenRevoked:  return nil, "installation-revoked"
    if seenMissing:  return nil, "installation-missing"
    return nil, "binding-missing"      # 理论不可达（rows 非空必落入上面某一支），兜底
```

排序键 `bound_at DESC, id ASC` 是 PRD FR-5 的确定性口径，与既有 `FindChannelBindingForMember` / `FindReusableChannelUserBinding` 的 `bound_at DESC` tiebreak 一致（后者无二级键，本设计补上 `id ASC` 消除并列不确定性）。

**分类结果不是最终授权（BL-1 的双层闭合）**：`chooseEffective` 选中的只是一个 `installation_id`；真正取凭据时再走一次 `GetInWorkspace(id, 锚点)`——该上游查询自带 `workspace_id` 与 `channel_type` 谓词（§1.3 已核），因此租户闭合在“分类”与“取凭据”两道各自成立；水化后再对 `inst.WorkspaceID` / `inst.Status` 做一次显式复核，封住两次读取之间的撤销窗。分类与水化不一致时（例：分类时 active、水化时 revoked）**以水化结果为准**并记对应 reason。

**卡片阶段名映射（展示层，不落日志）**：

| CR status（日志 `stage` 取值） | 卡片展示 |
|---|---|
| `requirement-reviewing` | 需求审批 |
| `tech-design-review-pending` | 架构审批 |
| `task-breakdown` | 开发启动审批 |
| `code-reviewing` | 代码审批 |

映射的语义是**闭集查表 + 未命中回退 status 原文**：新增门禁状态时不会渲染空白（枚举分支必须有 default，`ARCHITECTURE.md` §5 不变量 8 的同款纪律）。

**声明形态已定案为「一份 map + 查表函数」（dev-plan 评审采纳，见 §9）**：`lark` 包内本表与 §4.1 回调里的过滤闭集是**同一个四元集合**，故合并为一份声明 `approvalGateStageLabels map[string]string` + `stageLabel(status string) string`（命中返回中文名，未命中返回 `status` 原文 = 上述 default 语义）；§4.1 的防御性二次过滤改用 `_, ok := approvalGateStageLabels[p.Status]`。这样四个门禁状态字面量在 `lark` 包内**只出现一次**，语义与「switch + 另一个 map」完全等价。

**边界（不得扩大化）**：该收敛**只在 `lark` 包内**；`governance` 侧的 `approvalGateStatuses`（§3.2.1，发布侧过滤）保持**独立声明**——两包不共享该集合是 DD-4 刻意留下的边界（共享包 `pkg/protocol` 只放事件名与载荷类型，不放业务过滤集）。展示映射**只供卡片**，不落日志（日志 `stage` 恒为 `p.Status`，§2 术语硬化）。

### 4.4 SQL：workspace 闭合的两条只读查询

第一条（CR → issue → project → workspace.slug，一次往返，三处 workspace 谓词）：

```sql
-- AIFIRST: CR-2026-051 FR-3 — every hop carries workspace_id = $1 (the
-- DaemonAuth anchor). Deliberately NOT the project_gates.go join shape:
-- that one joins issue by primary key only, which cannot detect a
-- cross-workspace shell_issue_id. No fallback re-query on miss.
SELECT p.id::text, w.slug, c.title
  FROM cr c
  JOIN issue   i ON i.id = c.shell_issue_id AND i.workspace_id = $1
  JOIN project p ON p.id = i.project_id     AND p.workspace_id = $1
  JOIN workspace w ON w.id = $1
 WHERE c.workspace_id = $1 AND c.cr_id = $2;
```

`INNER JOIN` + 全跳 workspace 谓词即 fail-closed：`shell_issue_id IS NULL`、issue/project 跨 workspace、或任一行缺失都返回零行，一律跳过。**零行时的原因判定**：再查一次 `SELECT shell_issue_id IS NULL FROM cr WHERE workspace_id=$1 AND cr_id=$2`——为真或无行 ⇒ `project-unresolved`；否则 ⇒ `workspace-mismatch`。这**不是**"放宽条件重查"（FR-3 禁止项）：该查询仍带 `workspace_id = $1`，且只用于选日志原因，不产生任何收件人或发送。

第二条（每收件人一次，候选 + 安装联查）：

```sql
-- AIFIRST: CR-2026-051 FR-5 — effective-binding candidates for one member.
-- LEFT JOIN (not INNER) so a dangling installation_id (channel_* has NO
-- foreign keys, migration 124) is observable as installation-missing
-- instead of silently collapsing into binding-missing.
SELECT b.id, b.channel_user_id, b.installation_id,
       ci.id, ci.workspace_id, ci.channel_type, ci.status
  FROM channel_user_binding b
  LEFT JOIN channel_installation ci ON ci.id = b.installation_id
 WHERE b.workspace_id = $1 AND b.multica_user_id = $2 AND b.channel_type = 'feishu'
 ORDER BY b.bound_at DESC, b.id ASC;
```

注意 `ci.workspace_id` / `ci.channel_type` / `ci.status` 只**取回**不在 SQL 里过滤——过滤放在 `chooseEffective` 里，正是为了产出可区分的跳过原因（若写进 WHERE，三种失效原因会全部退化成“零行”，AC-4 无法验收）。

**两条 SQL 均不取凭据（BL-1 的修正点）**：发送所需的 `app_id` / `app_secret_encrypted` / `tenant_key` / `region` 全在 `channel_installation.config` 这个 JSONB 里，且密文是可能 MIME 折行的 base64（`store.go` 文件头）——拿裸 SQL 自己 `->>` + 手写 base64 宽容解码等于在 fork 侧重实现一份 `installationFromRow`。**正确做法**：拿到 `installation_id` 后调既有的 `InstallationService.GetInWorkspace(ctx, id, workspaceUUID)`（内部就是 sqlc `GetChannelInstallationInWorkspace`，WHERE 带 id + workspace_id + channel_type，返回的 `Installation` 已由 `installationFromRow` 解好 config），再给既有 `installationCredentialsFor(inst, resolver)` 组装成 `InstallationCredentials`。所以：**裸 pgx 只用于“可区分分类”，凭据路径完全走上游已有、已带租户谓词的查询**，既满足 AC-4，也不重实现解码/解密。

**DB 错误不得当零行**：两条查询与成员查询的 `err != nil`（非 `ErrNoRows`）一律进 `result=failed`（带 `step`），不复用任何 `reason`——否则“库挂了”会伪装成“用户未绑定”（§4.6）。

### 4.5 私有 helper 提取（行为等价）

`SendBindingPromptCard` 与 `SendApprovalReminderCard` 的传输部分完全同构（`receive_id_type=open_id` + `msg_type=interactive` + tenant token + 错误码 / token 失效处理）。提取为 `http_client.go` 内私有 helper：

```go
func (c *httpAPIClient) sendCardToOpenID(ctx context.Context, creds InstallationCredentials, openID OpenID, cardJSON, op string) error
```

`SendBindingPromptCard` 改为调用它（**唯一一处对上游函数正文的改动，带 `// AIFIRST:` 标记**）。行为等价由既有测试锁定：`http_client_test.go#TestHTTPClient_SendBindingPromptCard_HappyPath` 及第 1270/1276 行的错误路径断言必须**原样通过、不修改**（§4.3 兼容性要求"现有绑定提示卡片行为不得因私有 helper 提取而改变"）。

> **评审已定案（sdd.yml suggestions 第 2 条）**：采纳 `sendCardToOpenID` 提取；退化方案（在自研文件重写 ~30 行传输逻辑）作废。评审同时要求：既有绑定提示测试保持不变之外，必须为**审批卡路径**补下列五类测试（“证明复用正确”而不是“推定复用正确”），均写在自研测试文件内：
>
> | # | 测试 | 断言要点 |
> |---|---|---|
> | 1 | 参数校验 | `OpenID == ""` / `ApproveURL == ""` 各返回错误且**零 HTTP**（与 `SendBindingPromptCard` 前两条同口径） |
> | 2 | 成功路径 | 打到 `/open-apis/im/v1/messages`、`receive_id_type=open_id`、`receive_id == open_id`、`msg_type=interactive`、body.content 为审批卡模板 |
> | 3 | token 失效 | 响应 `code` 为 token 类错误时触发 `invalidateToken(creds.AppID)`，下一次调用重新换 token（复用 helper 内的 `isTokenError` 分支） |
> | 4 | JSON 转义 | CR 标题包含 `"` / `\` / 换行 / emoji 时，卡片 JSON 仍可被 `json.Unmarshal` 回解且文本不损（模板不拼字符串，走 `json.Marshal`） |
> | 5 | stub 形态 | `stubAPIClient.SendApprovalReminderCard` 返回 `ErrAPIClientNotConfigured`、零 HTTP（与 AC-12 共用断言） |
>
> 其中第 3 条是“提取后两处 token 失效处理不会漂移”的真正回归锁。

### 4.6 结果日志口径（sent / failed / skipped）

PRD §4.4 已定义必需字段枚举；本节只把它落成三个单一入口，并补齐评审要求的“**DB 读取错误也要有结构化 `failed`**”（非阻塞建议③）。

| 入口 | 使用时机 | 字段 |
|---|---|---|
| `logSent(userID, openID)` | 卡片发送成功 | `cr_id`、`stage`、`workspace_id`、`event_id`、`recipient_user_id`、`recipient_open_id`、`result=sent` |
| `logFail(userID, openID, step, errClass)` | 收件人级失败：绑定查询报错 / 凭据水化报错 / 解密报错 / 发送报错或超时 | 同上 + `result=failed` + `error_class` + `step`（`openID` 尚未取到时缺省） |
| `logFailEvent(step, errClass)` | **事件级**失败：项目链查询 / 成员查询报错（尚无收件人） | `cr_id`、`stage`、`workspace_id`、`event_id`、`result=failed`、`error_class`、`step`；**无** recipient 字段 |
| `logSkip(scope, [userID], reason)` | 按设计不发 | 事件级：四个必填 + `result=skipped` + `reason`；收件人级额外带 `recipient_user_id` |

口径固定点：

1. `stage` = CR status 字面值（§2 术语硬化），**不**取卡片上的中文阶段名、不取 `approval_record.stage`；
2. `reason` 取值严格限于 FR-8.2 的 9 项枚举（集中声明为常量，不散拼字符串），**不新增第 10 项**；
3. `error_class` 取值为 PRD §4.4 括号内的四类：`timeout` / `rate-limited` / `not-configured` / `other`（DB 与解密错误归 `other`）；
4. `step` 是本 SDD 新增的**可选定位字段**（`project-chain` / `approver-query` / `binding-query` / `credential-hydrate` / `credential-decrypt` / `send`），取值是闭集常量、不含任何响应体或凭据文本——目的是让“库挂了”与“飞书报错”在日志里可区分；
5. **事件级 `failed` 无 recipient 字段**：与 PRD §4.4 “事件级跳过无 `recipient_open_id`” 同一条例外模式（字段按作用域条件出现）；这是对 PRD 可观测表的**加法细化**，不删不改已有必需字段，已列入 §8 供审批可见；
6. 日志里永不出现审批证据、签名材料、token、diff、飞书响应体原文（PRD §4.2/§4.4）。
7. **AC-4 四情形 → 枚举取值与作用域的一一对应（dev-plan 评审 BL-1 回修，本节为唯一口径）**：PRD AC-4 要求四种情形「均不收到卡片且各留下可区分跳过原因」。四者在本设计下的落点如下，**全部在 FR-8.2 已有 9 项枚举与 PRD §4.4 的事件级/收件人级 partition 内，无需第 10 个 reason、无需改 PRD**：

   | AC-4 情形 | reason 取值 | 作用域 | 触发点 |
   |---|---|---|---|
   | ① 非 owner/admin | `no-approver` | **事件级**（PRD §4.4 已将 `no-approver` 列入事件级） | §4.2 步骤 3 成员查询零行 |
   | ② 无 `feishu` 绑定行 | `binding-missing` | 收件人级 | §4.2 步骤 4 候选查询零行 |
   | ③ 安装 `revoked` | `installation-revoked` | 收件人级 | `chooseEffective` / 水化后复核 |
   | ④ `installation_id` 悬空 orphan | `installation-missing` | 收件人级 | `chooseEffective` / `ErrInstallationNotFound` |

   情形①与其余三项的**作用域不同，这是设计结论而非缺口**：收件人集合的唯一来源是 `role IN ('owner','admin')` 这条查询（FR-4），非 owner/admin 的用户**从未进入循环**，因此不存在一个能挂在其身上的收件人级记录。该情形的可观测形态因而是**两条互补断言**（§7.4 对应行逐条列出）：

   - **可区分原因**：目标 workspace 无任何 owner/admin（成员均为 `member`）时，成员查询零行 → 一条**事件级** `result=skipped reason=no-approver`；
   - **零发送**：混合 workspace（1 名 admin + 1 名 `member`，**两人都有有效飞书绑定**）时，客户端只被调用一次、`receive_id` = admin 的 `open_id`，且全部日志中不出现 `member` 的 `recipient_user_id`。

   **硬约束（防实施期漂移）**：① **不得**为每个非 owner/admin 成员记一条收件人级 `no-approver`——那会把 `no-approver` 从事件级搬到收件人级（违反 PRD §4.4 partition），且要求额外查询全量 `member` 集合（超出 FR-4 声明的读面，日志量随 workspace 规模膨胀）；② **不得**新增 `role-ineligible` 一类第 10 个 reason（第 2 条已硬约束）。

---

## 5. 技术选型与决策记录

只记录同时满足「难以逆转 + 无上下文会疑惑 + 有真实权衡替代」的四条。事件类型隔离（专用事件 vs `cr:updated`）已由 PRD FR-1/FR-2 拍板，不在此复述。

### DD-1 `event_id` 绑定到账本幂等键的字符串投影

- **Decision**：`event_id = "{cr_id}:{event_kind}:{commit_sha}"`，在 `publishApprovalGateEntered` 内由手上的 `OutboxEvent` 直接拼出，贯穿事件级与收件人级全部日志。
- **Context**：quality-reviewer 需求评审 attempt 2 的实现期建议①要求 `event_id` 绑定**稳定的来源事件标识**并贯穿日志。`events.Event` 无此字段；来源侧唯一稳定标识是 `cr_sync_event` 的幂等键 `(workspace_id, cr_id, commit_sha, event_kind)`（迁移 391 唯一索引）。`workspace_id` 已是独立日志字段，故投影为三段字符串即可唯一定位一次来源事件。`--embedded` 模式的 `commit_sha` 是 `pending:{ms}:{pid}:{seq}` 占位符——**仍逐事件唯一**（CR-2026-003 修的正是占位符互撞问题），幂等键不退化。
- **Alternatives**：
  1. `cr_sync_event.id`（BIGSERIAL）——更短，但 `ingest` 的 INSERT 是 `ON CONFLICT DO NOTHING` 无 `RETURNING`，要把 id 从 `ingest` 一路传到 `applyStatus` 再传进发布点，属为一个日志字段改动治理核心的调用签名；
  2. 每次发布新生成 UUID——能串起一次投递的多条日志，但**不指向来源事件**，重放或双通道上报时无法与账本对账，达不到建议①的要求。
- **Consequences**：日志可直接与 `cr_sync_event` 三列对账，零 schema 改动、零额外查询；代价是 `event_id` 较长且含冒号分隔（检索需整串匹配，不做子串解析）。
- **相关键口径（评审非阻塞建议①）**：三段投影**不是全局唯一的**——`cr` 的唯一键是 `(workspace_id, cr_id)`，两个 workspace 完全可以各有一个 `CR-2026-051`，幂等键本身也是四列含 workspace。本设计**不**把 `workspace_id` 拼进 `event_id` 字符串（会与已有的独立日志字段重复、且把一个可对账投影变成四段不可读串），而是**显式声明检索与对账键为二元组 `(workspace_id, event_id)`**：`workspace_id` 在事件 envelope（`events.Event.WorkspaceID`）与三类日志里均为必填字段（PRD §4.4），所以二元组在日志侧是现成可用的。文档/断言/运维检索一律写二元组口径，禁止把 `event_id` 当全局主键用。

### DD-2 提醒器自带只读 pgx seam，不新增 sqlc 查询（评审已采纳）

- **Status**：`review-annotations/sdd.yml` suggestions 第 1 条明确「accept the raw pgx seam rather than expanding FR-10 into channel.sql/sqlc」，同时附三条强制条件：① 补全安装凭据读取；② 补租户闭合检查；③ 把 lark 裸 SQL 的列依赖登记进 `CUSTOM.md`（CUSTOM #5 只覆盖 governance 包，不能代替本 CR）。三条已分别落到 §4.2/§4.4（凭据路径）、§4.3+§4.4（双层租户闭合）、§7.3（CUSTOM.md 新增条目）。

- **Decision**：提醒器的读链（§4.4 两条 SQL）用 `*pgxpool.Pool` 直接执行，写在自研文件内；**不**往 `server/pkg/db/queries/channel.sql` 加查询、不重跑 `make sqlc`。
- **Context**：需要一条现有 sqlc 查询集里没有的读——"某 workspace 某成员的全部 feishu 绑定候选 + LEFT JOIN 安装"。最近似的 `FindChannelBindingForMember` 有两处不够：它不闭合 `ci.workspace_id` / `ci.channel_type`（PRD 澄清 4 指出的正是这类漏洞），且 `LIMIT 1` + `INNER JOIN ci … status='active'` 把 missing / revoked / orphan 三种失效**全部压成"零行"**，AC-4 要求的可区分跳过原因无法实现。加 sqlc 查询要改上游 `channel.sql` 并重生成 `pkg/db/generated/*.go`——CUSTOM.md 明列这两类文件是 fork 最大的合并冲突面，且**超出 PRD FR-10 声明的改动文件集合**（AC-8 逐条核对改动面）。
- **Alternatives**：
  1. `channel.sql` 加 `-- AIFIRST:` 查询 + `make sqlc`——编译期列名安全（上游改列名会 build 失败），先例充分（CUSTOM #17 起、#48）；但突破 FR-10 改动面，需求侧要重新确认，且吃进生成物冲突面；
  2. 只用现有 `FindChannelBindingForMember` + `GetChannelInstallationInWorkspace` 两步——零新查询，但如上所述放弃 AC-4 的可区分原因，等于降级已审批的验收标准。
- **Consequences**：改动面严格落在 FR-10 内，`governance` 包既有"fork 代码直接用 pgx 以避开上游 query 文件"的同款先例（CUSTOM.md #5）。**代价与缓解**：裸 SQL 失去 sqlc 的编译期列名校验，上游若重命名 `member.role` / `channel_user_binding.bound_at` 这类列会在**运行时**才暴露——缓解手段是 §7 的真库测试全部覆盖这两条 SQL（`ARCHITECTURE.md` §7 已要求 DB 测试真跑 PostgreSQL 而非 skip 假绿），并在 CUSTOM.md 登记行的"合并注意"里写明这两条 SQL 依赖的列清单。
- **范围收紧（本次回修）**：裸 pgx 的职责从“读链 + 凭据”收窄为仅“**可区分分类**”——凭据一步改走既有上游 `GetInWorkspace`（sqlc）。这同时解了 BL-1 与“裸 SQL 列依赖面”两个问题：安装侧只剩 `ci.id`/`ci.workspace_id`/`ci.channel_type`/`ci.status` 四个**平展列**被裸 SQL 引用，`config` JSONB 的内部形状（`app_id`/`app_secret_encrypted`/`tenant_key`/`region` + base64 宽容解码）完全不进 fork 代码，上游改 config 形状时本 CR 零改动。

### DD-3 `SendApprovalReminderCard` 进 `APIClient` 接口

- **Decision**：在 `client.go` 的 `APIClient` 接口加一行方法声明（唯一接口面改动，带 `// AIFIRST:`），实现与参数类型全部落在自研文件 `approval_reminder_card.go`（含 `*httpAPIClient` 与 `*stubAPIClient` 两个方法，Go 同包跨文件定义方法，故 `http_client.go` 正文只动 §4.5 的 helper 提取）。
- **Context**：`SendInteractiveCard` 走 `outboundMessageRequest`，`receive_id_type` 固定 `chat_id`，无法寻址 open_id 私聊；`SendBindingPromptCard` 的卡片体与 CTA 不同。所以必须有新方法。放接口上会连带要求 4 个上游测试替身（`outbound_test.go#fakeAPIClient`、`outcome_replier_test.go#stubAPIClientWithRecorder`、`typing_indicator_test.go#fakeTypingAPIClient`、`inbound_enricher_test.go#enricherFakeClient`）各补一个空实现。
- **Alternatives**：不进接口——`NewHTTPAPIClient` 返回的是 `APIClient` 接口值，提醒器只能对自研窄接口做**运行时类型断言**取能力。零上游文件改动，但断言失败是静默的：上游哪天给 `APIClient` 套一层装饰器，提醒功能会无声停摆而不是编译报错。对一个审批感知链路，"静默停摆"比"多改 4 个测试替身"贵得多。
- **Consequences**：编译期保证 wiring 正确；代价是 5 个上游文件（`client.go` + 4 个测试文件）各有一处最小改动，全部 `// AIFIRST:` 标记并登记 CUSTOM.md，双周 rebase 时逐条核对。

### DD-4 事件名与载荷类型放在共享 `pkg/protocol`（BL-4）

- **Decision**：`EventCRApprovalGateEntered` 与 `ApprovalGateEnteredPayload` 声明在 `server/pkg/protocol/events.go`；`governance` 侧取常量别名（`const EventCRApprovalGateEntered = protocol.EventCRApprovalGateEntered`）并发布该结体，lark 侧直接 `v.(protocol.ApprovalGateEnteredPayload)` 类型断言。
- **Context**：初稿把常量与载荷类型放在 `governance/crsync.go`，同时又要求 lark 不依赖 governance——这两条同时成立时，`events.Event.Payload` 是 `any`，lark **既无法断言该类型，也没有稳定的事件名来源**（BL-4 原文）。fork 自己已有现成口径：`protocol/events.go:191-196` 的 `EventCRUpdated` 就是为此而存，注释明写「governance.EventCRUpdated references this constant rather than duplicating the string literal」。另一个硬事实：总线事件会经 `listeners.go` 的 `SubscribeAll` 广播到 workspace 房间，所以载荷**本身就是一份 WS 帧契约**——`pkg/protocol` 正是全仓存放 WS 契约类型的包（`messages.go` 里已有 20+ 个 `*Payload` 结体）。
- **Alternatives**：
  1. **map/JSON envelope 契约**（BL-4 允许的第二选项）：发布 `map[string]any`，两侧各自维护键名常量 + 回归测试锁形状。FR-10 文件集不动，但键名契约仍靠两处字面量对齐，上游/本侧任一侧改键名不会 build 失败——只会在运行时静默不发卡。**若审批驳回 DD-4，退化到本选项**，并须补两侧契约测试（生产侧断言 map 键集与值类型、消费侧断言缺键/错类型时走 malformed 分支）；
  2. lark 直接 import governance：也能得到编译期契约且不动 FR-10 文件集（已核当前无循环：governance 只依赖 events/middleware/scheduler/service，且这些包不依赖 lark），但把主体为上游的 `integrations/lark` 变成依赖 fork 专有包的 sibling——与 `ARCHITECTURE.md` §4 的分层方向相背，且一旦 governance 的依赖闭包将来碰到 lark 就是循环；
  3. 结构式接口断言（lark 本地宣告一个带 getter 的接口，governance 载荷实现它）：无需共享包，但方法名漂移时仍是运行时静默失败，与 DD-3 已否决的"运行时断言"同一类风险。
- **Consequences**：两侧获得真正的编译期契约（字段/类型/事件名任一处漂移 → build 失败），且不引入新依赖方向（两侧均已 import `pkg/protocol`，它自身零 `internal/` 依赖）。**代价与边界**：① 改动文件集多一个 `server/pkg/protocol/events.go`，超出 FR-10 字面清单，已在 §0/§6/§8 显式标出供 `approve-tech-design` 确认（本 SDD 不自行改 PRD）；② CUSTOM.md 需新增一行登记该常量与载荷类型（先例 #22/#23 同文件）；③ 载荷 json tag 成为客户端可见契约，今后只允许加字段（§3.2.1 不变量 6）。

---

## 6. FR 到技术实现映射

| FR | 技术实现 | 落点 |
|---|---|---|
| FR-1 门禁进入语义事件 | `protocol.EventCRApprovalGateEntered` + `protocol.ApprovalGateEnteredPayload`（共享包声明）+ governance 侧常量别名 + `approvalGateStatuses` + `publishApprovalGateEntered`，仅在 `applyStatus` 可信分支、`from != to`、目标 ∈ 四门禁时发布；载荷四字段含可空 `shell_issue_id`（= FR-1 的「CR/issue 关联标识」） | §3.2.1 / `pkg/protocol/events.go` + `governance/crsync.go` |
| FR-2 触发面隔离 | 不订阅 `EventCRUpdated`；不在 `found==false` 首见分支、`else`（needs_reconcile）分支、`checkpoint`/`review`/`trace`/default 分支、`reconcile.go`、`gate_projection.go` 发布；自环由 `from != to` 过滤 | §3.2.1 五条契约不变量 |
| FR-3 项目/workspace 解析 + 跨 workspace fail-closed | 单条 INNER JOIN SQL，`cr`/`issue`/`project`/`workspace` 四跳全带 `workspace_id = $1`；零行→跳过；原因判定的第二次查询仍带 workspace 谓词，且不产出收件人 | §4.4 第一条 SQL / §4.2 步骤 3 |
| FR-4 收件人角色筛选 | `SELECT user_id FROM member WHERE workspace_id = $1 AND role IN ('owner','admin')`，与 Web 侧 `roleAllowed(role,"owner","admin")` 同口径；空集 → 事件级 `no-approver`（= AC-4 情形①的可区分原因，§4.6 第 7 条）；**非 owner/admin 成员从不进入收件人集合，故不产生收件人级记录**——收件人集合的唯一来源就是这条查询的结果集 | §4.2 步骤 3 / §4.6 第 7 条 |
| FR-5 有效绑定、去重、可区分跳过 | LEFT JOIN 候选查询 + `chooseEffective`（三条件判定，产出 4 种原因）+ 水化后租户/状态复核；`bound_at DESC, id ASC` 取最新 ⇒ 每用户一张卡；**`attemptedOpenIDs` 在发送前登记**做 open_id 级二次去重（BL-2） | §4.2 / §4.3 / §4.4 第二条 SQL |
| FR-6 卡片最小内容 | `approvalReminderTemplate`：header `待人工审批` + CR ID/标题 + 阶段名 + 固定说明 + 单一 button `前往审批`；模板内无 approve/reject action、无正文/证据/diff | §3.2.2 / `approval_reminder_card.go` |
| FR-7 CTA 与基地址 | `appURL + "/" + slug + "/projects/" + projectID + "?tab=chat"`；`appURL == ""` → `app-url-missing` 且零发送；**不新增** URL 合法性校验器 | §4.2 步骤 2/3 |
| FR-8.1 非阻塞边界 | 回调零 I/O；`chan struct{}` 非阻塞信号量（默认 8，过载 `overloaded` 丢弃不排队）；`context.Background()` 派生；60s/10s 有界超时；goroutine 自持 `recover` | §4.1 / §4.2 |
| FR-8.2 结构化可观测 | `logSent` / `logFail` / `logFailEvent` / `logSkip` 四入口，字段按 PRD §4.4 表（落地口径见 §4.6）；`reason` 受限于 9 项枚举常量；DB / 凭据 / 发送错误一律进 `failed` + `error_class` + `step`，不占用 `reason` | §4.2 / §4.6 / §7.3 |
| FR-8.3 未启用仍消费 | `Register` 调用点在 `MULTICA_LARK_SECRET_KEY` 条件块**之外**；步骤 1 在任何 DB 查询前判 `client==nil / !IsConfigured() / credentials==nil` → `feishu-disabled` 返回；stub 方法零 HTTP | §3.2.3 / §4.2 步骤 1 |
| FR-8.4 失败隔离与 crash window | 全链只读、无事务、发布点之后；发送失败/超时只记日志；不做异步前状态二次校验、不做撤回、不做 drain/join、不引入 outbox/幂等键 | §4.2 关键约束 |
| FR-9 发送能力复用边界 | 单一用途 `ApprovalReminder`（只做解析/收件人/发送/记账）+ `SendApprovalReminderCard` + `ApprovalReminderParams`；模板封装在 client 侧；`sendCardToOpenID` 私有 helper 与绑定提示共用；**不**公开卡片 JSON 接口、**不**抽象跨渠道 notifier | §3.2.2 / §4.5 |
| FR-10 零改动边界 | 改动面：`governance/crsync.go`、`lark/approval_reminder.go`（新）、`lark/approval_reminder_card.go`（新）、`lark/client.go`（1 行接口）、`lark/http_client.go`（helper 提取）、`cmd/server/router.go`（wiring）、**`pkg/protocol/events.go`（+1 常量 +1 载荷类型，BL-4 回修新增，超 FR-10 字面清单一处——待审批确认）**、6 个测试文件（4 个替身补空实现 + 2 个新测试文件）、`CUSTOM.md` 登记。零改动：`tools/` 全部、schema/migration、CR 账本、`governance/approval.go`、Web 审批页与 API、grant daemon、`pkg/db/queries/*`、`pkg/db/generated/*`、`packages/`（前端对未知事件类型 no-op，§1.3 已核） | §5 DD-2/DD-3/DD-4 |
| FR-11 启用条件不新增配置 | 无新环境变量、无 feature flag、无用户通知偏好；启用条件全部由既有事实（密钥/角色/绑定/项目链/基地址）判定，不满足即按枚举原因跳过 | §4.2 |

**FR-1 载荷字面：初稿的“有意收窄”已被评审驳回，本次改回携带（BL-3）**。初稿的 `Payload` 只带 `cr_id`/`status`/`event_id`，并自行裁定不带 issue 标识“符合最小标识”。评审结论（sdd.yml BL-3）：**SDD 不得自行把已审批的 FR 改成“有意收窄”**。现采纳评审给出的第一选项：载荷增加可空 `shell_issue_id *string`，取值来自 `applyStatus` 开头那条既有 `SELECT`（扩为两列，零额外往返，§3.2.1）。

两个必须同时成立的约束（否则违反 FR-3 与 ARCHITECTURE §7）：

1. 该字段**只作相关/诊断**，永不作为查询输入；目标项目仍由 §4.4 第一条 SQL 从 `cr` 行重新解析（bus 不是持久权威，handler 必须可重放）；
2. 它可为 `null`（历史 CR 的 `shell_issue_id IS NULL`），消费侧不得把 `null` 当错误——仍走 `project-unresolved` 跳过口径。

回归锁：AC-10 的跨 workspace 负向测试新增一项“**载荷的 `shell_issue_id` 被伪造成另一个 workspace 的 issue 时仍零发送**”（证明它真的没进查询路径，§7.4）。

---

## 7. 安全与性能考量

### 7.1 安全控制点

| 风险 | 控制 |
|---|---|
| CR 标题跨 workspace 外泄 | 唯一锚点来自 DaemonAuth（`resolveDaemonWorkspace`）；读链四跳 + 成员 + 绑定 + 安装**每跳**带 `workspace_id = 锚点`；任一跳不符即整体跳过、不放宽重查、不跨 workspace 兜底。审计口径：提醒器的全部 DB 访问面 = §4.4 两条裸 SQL + 成员查询 + `GetInWorkspace`（后者自带 id+workspace_id+channel_type 三谓词），**不存在**仅按主键/仅按外键的查询路径，可静态核对 |
| 凭据读取的租户闭合（BL-1） | 凭据不由裸 SQL 组装，而走 `InstallationService.GetInWorkspace(id, 锚点)`；水化后额外复核 `inst.WorkspaceID == 锚点` 与 `inst.Status == 'active'`。即“分类”与“取凭据”两次都带租户谓词，任一跳失效即零发送 |
| 新事件经 WS 扇出到 workspace 房间 | 已核实：`listeners.go` 的 `SubscribeAll` 会把本事件广播给该 workspace 的客户端（不跨 workspace）。载荷只有 `cr_id`/`status`/`event_id`/`shell_issue_id`——**无标题、无评审证据、无收件人、无凭据**，而同房间既有 `cr:updated` 已广播 CR 状态，故**未新增外泄面**；Web 审批页本身就向 workspace 成员展示这些标识。不为此改 `listeners.go` 的 `personalEvents`/`internalOnlyPayloadKeys`（那才是真正超 FR-10 改动面） |
| 越权收到提醒 | 收件人只取 `role IN ('owner','admin')`；`member` 角色与未绑定用户零发送 |
| 卡片成为绕过签名审批的入口 | 卡片只有一个 `url` 类型 button，无 action/callback、无 token；审批权威仍在 Web 签名链路与 `crctl` 门禁，点 CTA 后由既有链路重新校验（`governance/approval.go` 零改动） |
| 凭据泄漏 | `InstallationCredentials.AppSecret` 只在单次调用在飞期间存在，不落日志、不落库；日志只出 `recipient_open_id`，不出凭据、token、签名材料、diff、飞书响应体原文（`error_class` 只记类别） |
| 撤销安装后仍可发送 | 有效绑定强制 `installation.status = 'active'` + 同 workspace + `channel_type='feishu'`；revoked / orphan / mismatch 三类各自跳过并留可区分原因 |
| 恶意/异常 payload | `handleEvent` 只做类型断言与非空校验，字段异常直接丢弃记 warn；防御性二次过滤 `approvalGateStageLabels`（lark 侧闭集，§4.3） |

### 7.2 性能目标与边界

| 指标 | 目标 | 保障手段 |
|---|---|---|
| `HandleCREvents` 时延增量 | 与"无提醒器"基线同量级（仅解析开销） | 回调零 I/O + 非阻塞信号量；AC-11 用阻塞替身 + 零调用断言 |
| 单收件人发送 | ≤ 10s | `WithTimeout(ctx, 10s)`，与 `Patcher.handleEvent` 同口径 |
| 单事件整体 | ≤ 60s | `WithTimeout(Background(), 60s)`；超时按失败记日志，不重试 |
| 在飞提醒并发 | ≤ `MaxInFlight`（默认 8） | 容量固定的 `chan struct{}` + 非阻塞 acquire；过载丢弃记 `overloaded` |
| 单事件 DB 往返 | 2 + 2N 次（链路 1 + 成员 1 + 每收件人：候选查询 1 + `GetInWorkspace` 1；链路零行时 +1 次原因判定） | N = owner/admin 数，正常个位数；凭据水化只对**选中**的安装做一次（BL-1 引入的额外往返上限） |
| 进程崩溃/退出 | 允许在飞提醒丢失 | 不引入 outbox / 持久化 / drain / 补偿 |

### 7.3 工程纪律落点（CONTRIBUTING.AIFIRST）

- **规则一/二**：自研逻辑集中在两个新文件；上游文件只留最小挂钩（`client.go` 1 行、`http_client.go` helper 提取、`router.go` wiring、4 个测试替身），每处 `// AIFIRST: CR-2026-051 …` 标记；
- **规则五**：两个新文件预算内（预估各 < 400 行），远低于 800 行提醒线；不新增包级可变全局状态（`MaxInFlight` / 超时 / 依赖全走构造注入）；
- **规则六**：9 个跳过原因 + 4 类 `error_class` + 6 个 `step` 均集中声明为常量（不散拼字符串）；构造参数不静默忽略、依赖缺失不返回 nil（§3.2.3）；卡片模板、`chooseEffective`、`parsePayload` 均为独立可单测的小单元；
- **CLAUDE.md**：multica 仓内新增/改动的代码注释一律英文（本 SDD 中文，代码英文）；
- **CUSTOM.md（评审强制项，不得拿 CUSTOM #5 顶替）**：本 CR 落码后按彼时 CUSTOM.md 现状顺延登记**一行新条目**（#5 只覆盖 governance 包的 pgx 例外，不覆盖 lark 包），"合并注意"列写明：① `crsync.go` 发布点需随上游事件机制改名跟改；② **§4.4 两条裸 SQL 依赖的列清单**（`cr.shell_issue_id`/`cr.title`、`issue.project_id`、`project.id`、`workspace.slug`、`member.role`、`channel_user_binding.bound_at`/`channel_user_id`/`multica_user_id`/`installation_id`/`channel_type`/`workspace_id`、`channel_installation.id`/`status`/`channel_type`/`workspace_id`——注明 `config` JSONB **不**在裸 SQL 依赖面内，由 `installationFromRow` 解码）；③ `APIClient` 接口新方法与 4 个测试替身空实现须整组保留；④ `pkg/protocol/events.go` 的常量与载荷类型（与 #22/#23 同文件，上游新增事件类型时取并集）；⑤ 依赖的上游凭据入口（`InstallationService.GetInWorkspace` / `installationCredentialsFor`）——上游改签名则跟改。

### 7.4 测试设计（对齐 AC-1～AC-13）

| 测试 | 覆盖 AC | 要点 |
|---|---|---|
| `governance`：四门禁 × 合法转换各发布一次 | AC-1 | 真库；断言事件类型、`workspace_id`、payload 三字段与 `event_id` 形状 |
| `governance`：误触发隔离 | AC-2 | 通用 `cr:updated` 不触发；重放（`curStatus != FromStatus`）、自环（`from == to`）、checkpoint/review/trace、首见分支、reconcile/gate_projection 均零发布；断言订阅集合不含 `EventCRUpdated`。<br>**每条零发布用例必须附一条「链路确实跑了」的 liveness probe，但 probe 形态按路径选（dev-plan 评审 BL-2 回修）**：见下表 |
| `governance`：零发布用例的 **liveness probe 口径**（BL-2 回修，与代码事实逐条对齐） | AC-2 | ① **进 `apply()` → `publish()` 的路径**（非门禁 status 目标 / 两种自环 / 两种首见分支 / 乱序非法的 `else` 分支 / `checkpoint` / `review`且 `payload.stage ∈ ReviewGateNodes`）→ probe = `cr:updated` 收集器 **> 0**；② **ledger-only 路径**：`trace` 在 `HandleCREvents` 就被分流到 `ingestTrace`（`crsync.go:162`），**根本不进 `apply()/publish()`** → probe = `resp.Accepted` 含该 `file` + `cr_sync_event` 存在 `(workspace_id, cr_id, commit_sha, event_kind='trace')` 行且 `processed_at IS NOT NULL`，**不得断言 `cr:updated > 0`**；③ **reconcile**（`ApplySnapshot`）→ probe = 返回的 `healed >= 1`（该路径自己会逐 CR `publish`，故 `cr:updated > 0` 也成立）；最强形态：快照把某 CR 的状态治成**门禁状态**时仍零发布；④ **gate_projection**（`projectGateTransition`）→ probe = `pipeline_run` / `pipeline_node_run` 行变化。<br>**两个已核实的例外，写用例时不得误用 probe ①**：`review` 事件当 `payload.stage ∉ ReviewGateNodes`（如 `dev-start`）时 `applyReview` 提前 `return nil`、**不** publish（`gate_projection.go:285`）；`ToStatus ∉ KnownStatuses` 走 `flagUnknownCR` 同样**不** publish（`crsync.go:415`）。这两种形态如果进矩阵，只能用 `cr_sync_event` 行 + `processed_at` 作 probe |
| `lark`：happy path 多收件人 | AC-3 | 每个有效绑定 owner/admin 一张卡；同用户多绑定只发一张（取 `bound_at` 最新）；同 open_id 只发一次 |
| `lark`：**首个尝试失败 + 重复 open_id**（BL-2 回归） | AC-3、FR-8.2 | 两个不同 user 指向同一 `open_id`，第一个发送返错：断言客户端**只被调用一次**、第二个用户无发送且无日志重复尝试；同型用例覆盖“首次凭据解密失败”与“首次超时” |
| `lark`：**凭据水化四态**（BL-1 回归） | AC-3、AC-4、AC-10 | ① happy：`GetInWorkspace` 返回完整安装 → 发送时 `InstallationCredentials` 的 `AppID`/`AppSecret`/`TenantKey`/`Region` 均与库里一致（真库 + 真 secretbox）；② `ErrInstallationNotFound` → `installation-missing` 跳过；③ 水化后 `status='revoked'` → `installation-revoked`（分类后被撤销的 TOCTOU 窗）；④ 水化后 `workspace_id` 不符 → `workspace-mismatch`。另断言安装属另一 workspace 时 `GetInWorkspace` 本身就查不到 |
| `governance`+`lark`：**共享契约**（BL-4 回归） | AC-1、AC-9 | 生产侧发布的 `Payload` 可被消费侧 `v.(protocol.ApprovalGateEnteredPayload)` 直接断言成功（同一包类型）；golden JSON：`json.Marshal(payload)` 等于 `{"cr_id":…,"status":…,"event_id":…,"shell_issue_id":…}`（`null` 形态单独一例）；递交 `map[string]any` 或异类型时 `parsePayload` 返回 false 且零 DB/HTTP |
| `lark`：**载荷 shell_issue_id 不参与解析**（BL-3 回归） | AC-10 | 载荷带上另一 workspace 的 issue id（伪造）时，仍以 `cr` 行为准解析；当 CR 本身的 `shell_issue_id IS NULL` 时 → 零发送 + `project-unresolved`（证明载荷未进查询路径） |
| `lark`：**事件级/收件人级 failed 日志** | AC-7、FR-8.2 | 注入 pool 报错替身：链路查询失败 → 一条 `result=failed`、`step=project-chain`、无 recipient 字段、**不出现任何 `reason`**；绑定查询失败 → 收件人级 `failed`（`step=binding-query`）而非 `binding-missing` |
| `lark`：**依赖缺失不 panic（逐依赖隔离，真 nil 接口）** | AC-12、AC-13 | `NewApprovalReminder` 在 `Pool`/`Client`/`Credentials` 任一为 nil 时返回非 nil 对象；`Register(bus)` + 发布一条真事件后进程存活、一条 `feishu-disabled`、零 DB。<br>**四个子用例必须逐依赖隔离（dev-plan 评审 BL-3 回修）**：分别只置 nil `Credentials` / 只置 nil `Client` / `Client` 非 nil 但 `IsConfigured()==false` / 只置 nil `Pool`，**其余依赖均健康**。否则一次性把三个依赖都置 nil 时，`feishu-disabled` 只能证明「四条条件里至少一条命中」，单条分支全部未被证明。<br>**本行不得包含 typed-nil 用例**：typed-nil 在提醒器内本就检不出（§3.2.3 口径硬化），回归锁在下一行的 wiring 层 |
| `cmd/server`：**typed-nil 防护的唯一验证点**（BL-3 回修新增） | AC-12 | ① **承重性断言（必须执行，不得降为注释）**：`var s *lark.InstallationService; cfg.Credentials = s` 后 `cfg.Credentials == nil` 为 **false**——证明 typed-nil 陷阱真存在、wiring 层判空是承重而非冗余；**只对 `Credentials` 写**（`h.LarkInstallations` 是具体指针；`h.LarkAPIClient` 是接口，写同型断言会失败，见 §3.2.3）；② **正向断言**：按 §3.2.3 wiring 形态（`if h.LarkAPIClient != nil` / `if h.LarkInstallations != nil` 才赋值）处理 nil 依赖后，`cfg.Client == nil && cfg.Credentials == nil` 为 **true**；③ **端到端**：该 config 造出的提醒器 `Register(bus)` + 发一条真事件 → 恰一条事件级 `feishu-disabled`、零真实飞书请求、pool 替身零调用、进程存活 |
| `lark`：AC-4 四情形不发送（**情形① 与 ②③④ 作用域不同**，BL-1 回修） | AC-4 | 按 §4.6 第 7 条的一一对应表取证，四条 `reason` 互不相同：<br>**情形①（非 owner/admin）= 两条互补断言**：(a) *可区分原因* —— workspace 内成员均为 `role='member'`（`member` 表无「必须存在 owner」约束，`001_init.up.sql:26-33` 只有 `CHECK (role IN ('owner','admin','member'))` + `UNIQUE(workspace_id,user_id)`，真库可直接造数）→ 成员查询零行 → 恰一条**事件级** `result=skipped reason=no-approver`，且无任何 `recipient_*` 字段；(b) *零发送* —— 混合 workspace（1 admin + 1 `member`，**两人都有有效飞书绑定**）→ 客户端恰被调用 1 次、`receive_id` = admin 的 `open_id`，且全部日志不出现 `member` 的 `recipient_user_id`（证明它从未进入收件人集合）。<br>**情形②③④ = 收件人级**：`binding-missing` / `installation-revoked` / `installation-missing` 各留一条带 `recipient_user_id` 的记录。<br>**反向断言（防漂移）**：全部用例的日志中不得出现收件人级 `reason=no-approver`，也不得出现 9 项枚举之外的任何 `reason` |
| `lark`：卡片与 CTA | AC-5 | 模板断言五项最小内容 + 无 approve/reject action；CTA 等于 `{appURL}/{slug}/projects/{projectID}?tab=chat`；`appURL==""` 零发送 |
| `governance`：Web 审批链路回归 | AC-6 | 既有 `approval*_test.go` / `project_gates_test.go` 原样通过，不修改 |
| `lark`：三类日志字段 + 无回滚 | AC-7 | 断言 §4.4 必需字段齐全、`reason` 落在 9 项枚举内；失败/跳过下投影仍成功 |
| 静态改动面核对 | AC-8 | `git diff --name-only` 与 FR-10 声明集合逐条比对；断言无新 migration、`pkg/db/queries`/`generated` 零改动、`tools/` 零改动 |
| `lark`：跨 workspace 负向 | AC-10 | issue/project/绑定/安装任一层 workspace 不符 → 零发送 + `workspace-mismatch`；静态核对提醒器内无"仅按主键/仅按外键"查询 |
| `lark`+`governance`：阻塞替身 | AC-11 | 客户端替身阻塞至超时：`HandleCREvents` 时延与无提醒器基线同量级、投影不变、无回滚；bus 回调内 DB/HTTP 替身零调用 |
| `lark`：stub 形态 | AC-12 | 未设 `MULTICA_LARK_SECRET_KEY`：事件被消费、一条 `feishu-disabled` 事件级跳过、`NewStubAPIClient` 零真实请求、读链零查询（pool 替身零调用） |
| `lark`：panic 与过载 | AC-13 | goroutine 内注入 panic → 被自持 recover 记日志、进程存活；`MaxInFlight=1` 占满后新事件记 `overloaded`、不排队、不重试 |
| `lark`：绑定提示行为等价 + 审批卡五类 | §4.3 兼容性、FR-9 | `http_client_test.go` 三处既有 `SendBindingPromptCard` 断言**不修改**即通过（helper 提取的回归锁）；另补审批卡的参数校验 / 成功 / token 失效 / JSON 转义 / stub 五类（§4.5 表） |

DB 相关测试须在可用 PostgreSQL 环境取到无 skip 的 `=== RUN` / `--- PASS` 证据（CUSTOM.md C6：包级 `TestMain` 在 DB 不可达时整包 skip，会产生 exit 0 假绿；**不得为此改 TestMain**）。

---

## 8. 残余风险与未决项

| 项 | 说明 | 处置 |
|---|---|---|
| **FR-10 改动面 +1 文件（需审批确认）** | BL-4 的修复把事件名与载荷类型放进 `server/pkg/protocol/events.go`（+1 常量 +1 结构），而 FR-10 字面清单未列该文件（AC-8 逐条核改动面） | 本 SDD **不自行改 PRD**。请 `approve-tech-design` 二选一：① 确认该 delta（AC-8 核对时计入合法改动集）；② 驳回 → 退化到 DD-4 备选 1（map/JSON envelope + 两侧契约测试），改动面回到 FR-10 字面内，代价是失去编译期契约 |
| 事件级 `failed` 日志无 recipient 字段 | PRD §4.4 把 `recipient_*` 挂在“成功/失败”上，而链路/成员查询报错发生在收件人集合存在之前 | 沿用 PRD 自己的条件字段模式（事件级跳过已无 `recipient_open_id`），属**加法细化**、不删不改已有必需字段（§4.6 第 5 条）；审批可见，若不接受则改为输出空值 recipient 字段 |
| 新事件会进 WS workspace 扇出 | `listeners.go` 的 `SubscribeAll` 对所有事件生效，本事件因此成为一份客户端可见的加法契约（前端当前 no-op） | 载荷无标题/证据/收件人，与同房间已有 `cr:updated` 同级别（§7.1）；本 CR 不改 `listeners.go`、不改前端；今后只允许加字段 |
| DD-2 的运行时列名风险 | 裸 SQL 无编译期列名校验（本次已把 `config` JSONB 形状排出裸 SQL 依赖面，风险面缩到四个平展列） | 真库测试覆盖两条 SQL + CUSTOM.md 登记列清单（§7.3）；评审已采纳该 seam（DD-2 Status） |
| `MaxInFlight` 默认 8 | 无生产数据支撑的经验值 | 收件人规模个位数、单事件 ≤60s，8 足以覆盖正常并发；构造参数可调，不新增环境变量（FR-11） |
| `cr.title` 可能为空 | 迁移 362 默认 `''`，由 reconcile 回填 | 卡片模板空标题时只渲染 CR ID，不渲染空行 |
| 凭据水化多一次往返 | 每个有效收件人 +1 次 `GetInWorkspace`（§7.2） | 收件人个位数、均为主键+租户索引命中；**不**做安装级缓存（缓存会把刚被撤销的安装变成可用凭据） |

**上一轮的三项未决点已关闭**（attempt 1 评审已给结论，不再作风险留存）：DD-2 裸 pgx seam = 采纳（附三条强制条件，已落地）；§4.5 helper 提取 = 采纳（附五类测试，已落地）；载荷收窄 = 驳回（已改回携带可空 `shell_issue_id`）。

**§8「Prompt 采纳影响」不触发**：本 CR 不改 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，也不改 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（`tools/` 整包零改动），crctl 命令面与 guard deny 面均无新增或变更，故条件性小节按 Skill 规则省略。

---

## 9. 修订记录

| 版本 | 时间 | 变更 |
|---|---|---|
| 初稿 | 2026-08-25T20:34:02+08:00 | 首版。基于 PRD `b64a92cf…`（11 FR / 5 US / 13 AC）与 multica worktree 实地核实的 15 条既有事实；含 6 项术语硬化、3 条决策记录（DD-1 event_id / DD-2 pgx 读 seam / DD-3 接口方法）、FR-1～FR-11 全映射、13 项 AC 测试设计。已收 quality-reviewer 两条实现期建议：① `event_id` 绑定账本幂等键投影并贯穿三类日志（DD-1、§4.4 字段）；② CTA 按锚定 `workspace_id` 读 `workspace.slug`（§4.4 第一条 SQL 的 `JOIN workspace w ON w.id = $1`）并补跨 workspace slug 回归断言（AC-10 测试项）。 |
| 技术评审 attempt 1 回修 | 2026-08-25T21:33:00+08:00 | 按 `review-annotations/sdd.yml`（verdict `block`，BL-1～BL-4 均 P1）定点修复，方案骨架（专用事件 → 非阻塞回调 → 异步 fail-closed 读链 → 单次投递）未变。<br>① **BL-1 凭据路径**：裸 SQL 职责收窄为“可区分分类”，凭据改走既有 `InstallationService.GetInWorkspace`（id+workspace_id+channel_type 三谓词，`installationFromRow` 解 `config` JSONB）+ `installationCredentialsFor`；新增窄接口 `installationCredentialSource`、水化后租户/状态复核、查询与解密失败的结构化 `failed` 日志（§1.1、§1.3、§3.2.3、§4.2、§4.3、§4.4、§4.6）。<br>② **BL-2 去重语义**：`sentOpenIDs` → `attemptedOpenIDs`，登记提到任何可失败动作之前；补“首个尝试失败 + 重复 open_id”回归（§4.2、§6 FR-5 行、§7.4）。<br>③ **BL-3 载荷**：撤销初稿的“有意收窄”，载荷新增可空 `shell_issue_id`（取自 `applyStatus` 既有 SELECT 扩为两列，零额外往返），并硬约束“只作相关、不作查询输入” + 伪造载荷的负向断言（§2、§3.2.1、§6、§7.4）。<br>④ **BL-4 跨包契约**：事件名与载荷类型上提到共享叶子包 `pkg/protocol`（先例：同文件的 `EventCRUpdated`、CUSTOM #22/#23），两侧真类型断言 + canonical JSON 契约 + 两侧契约测试（新增 DD-4）；同时把“FR-10 改动面 +1 文件”显式列入 §0/§6/§8 供审批裁定，**未自行改 PRD 字面**。<br>三项评审定案已内化：DD-2 采纳（附凭据读取、租户闭合、CUSTOM.md 新增条目三条强制条件）、§4.5 提取采纳（附参数校验/成功/token 失效/JSON 转义/stub 五类测试）、§8 Prompt 跳过确认成立。<br>三条非阻塞建议已处理：相关键口径 `(workspace_id, event_id)`（DD-1）、依赖缺失不返 nil + typed-nil 接口防护（§3.2.3）、DB 读错统一进结构化 `failed`（§4.6）。<br>另修正/新增两条核实事实：飞书未启用时 `h.LarkAPIClient` 是 **nil 而非 stub**（初稿措辞错）；本事件会经 `listeners.go#SubscribeAll` 进 WS workspace 扇出（已评估：无新增外泄面、前端 no-op、前端零 diff）。 |
| 上游设计回修（dev-plan 评审 upstream route） | 2026-08-26T00:30:00+08:00 | 按 `review-annotations/dev-plan.yml`（verdict `block`、route `upstream`、repair-target `write-tech-design`）的三条 blocker 定点修订，**方案骨架与改动面未变**（无新增文件、无新增 reason/step/error_class、无 DDL）。<br>① **BL-1 AC-4 情形①可实现口径**：评审指出「非 owner/admin」被 `role IN ('owner','admin')` 提前排除后无可区分原因。本次**不改 PRD、不加第 10 个 reason**，而是把该情形的可观测形态硬化为事件级 `no-approver`（FR-8.2 枚举已有、PRD §4.4 已列入事件级 partition）+ 混合 workspace 的零发送负向断言，并新增 §4.6 第 7 条「AC-4 四情形 → reason 与作用域一一对应表」与两条硬约束（不得改成收件人级 `no-approver`、不得新增 `role-ineligible`）（§4.2 步骤 3、§4.6、§6 FR-4 行、§7.4）。<br>② **BL-2 零发布用例的 liveness probe 按路径选**：原 §7.4 把 `checkpoint/review/trace` 并列而未交代存活证据形态，导致计划层统一用 `cr:updated > 0`；已核实 `trace` 在 `HandleCREvents` 就分流到 `ingestTrace`（`crsync.go:162`）、**不进 `apply()/publish()`**。新增四类 probe 口径（publish 路径 / ledger-only / reconcile `healed` / gate_projection 行变化）及两个已核实的不-publish 例外（`applyReview` 在 `stage ∉ ReviewGateNodes` 时提前返回；`flagUnknownCR`）（§7.4）。<br>③ **BL-3 typed-nil 验证归 wiring 层**：原 §7.4 把「灌 typed-nil 也不 panic」放在提醒器自身的用例行，与 §3.2.3「不反射、wiring 层判空」相矛。现将提醒器侧改为**逐依赖隔离的四个真 nil 子用例**（防“其他 nil 依赖短路”假证），typed-nil 回归锁单独落到 `cmd/server` wiring 行，且「无条件赋值 → `iface == nil` 为假」升为**执行断言**（原为注释，无人证明判空承重）；§3.2.3 同步硬化「`r.credentials == nil` 对 typed-nil 为假是已知且有意」（§3.2.3、§7.4）。<br>**两项评审采纳口径已落地**：① §2 术语表 `shell_issue_id` 的 `omitempty` 括注按笔误纠正为「键恒在、无值为 `null`」，与 §3.2.1 结构体 / 不变量 6 / §7.4 golden 三处一致；② `lark` 包内 `approvalGateStageLabels + stageLabel()` 收敛写进 §4.3（并同步 §4.1 伪代码与 §7.1），**边界明写**：只在 lark 包内，`governance` 侧 `approvalGateStatuses` 保持独立声明。<br>**本次未动**：FR 映射、两条 SQL、`chooseEffective`、凭据水化链、DD-1~DD-4、§8 残余风险、改动文件集（含已审批的 `pkg/protocol/events.go` +1）均原样。 |

## Multica 审批后自动续跑 + audit-drift 去重修复（v0.26 · CR-2026-052）

## 1. 架构概览

### 1.1 范围与仓归属

| 仓 | 角色 | 本 CR 改动 |
|---|---|---|
| multica（`server/` Go 服务端） | 代码仓 | FR-1 ~ FR-11：ACK 时点幂等唤醒 + 原子事务 + 两条 partial unique index + 回调签名扩展 |
| tools（`skills/shared/crctl/scripts/crctl.mjs`） | 代码仓 | FR-12：outbox `audit-drift` 去重比较语义修复（单点，不改事件 schema） |
| knowledge-base | 知识仓 | 仅本 SDD 与状态推进账本（经 crctl） |

两仓改动互不依赖、可独立上线：multica 侧唤醒能力不要求 tools 侧升级；tools 侧去重修复不要求 daemon/服务端配合（NFR-9）。

### 1.2 既有模块边界（只读复用，见 PRD §1.3）

- **crctl（tools）**：CR 状态机/门禁/账本的唯一写者，本 CR 除 FR-12 外零改动；
- **approval.go（multica governance）**：签名 grant 签发与 daemon 交付队列（`server/internal/governance/approval.go`），本 CR 只改 `HandleGrantsAck` 的 ACK 后处理与回调签名；
- **crevents.go（multica daemon）**：`crEventsLoop` 每 `HeartbeatInterval`（默认 15s，`server/internal/daemon/config.go:24`）拉取 pending grants → 写 `.crctl/grants/{CRID}-{Stage}.grant.json` → 批量 ACK（`server/internal/daemon/crevents.go:107-155`），本 CR **零改动**——ACK 失败时 grants 保持 pending、重投递幂等，天然满足 FR-5 重试；
- **agent_task_queue + TaskService**：任务执行唯一通道，续跑任务走同一条队列与事件广播（FR-11）。

### 1.3 新增/修改组件

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

### 1.4 关键流程（AC-1~AC-8 覆盖）

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

## 2. 数据模型

### 2.1 表变更总览

| 表 | 变更 | 依据 |
|---|---|---|
| `approval_record` | **零结构变更**（AC-10）；`HandleGrantsAck` 的 UPDATE `RETURNING` 扩展为 `id, cr_id, stage, decision, approver_user_id`（现仅 `cr_id`，approval.go:392-395） | 迁移 433 已有全部所需列（stage/decision/delivered_at/approver_user_id） |
| `agent_task_queue` | 新增 nullable `approval_workspace_id UUID`（无 FK，仅 `approval_continuation` 行必填；迁移 470 CHECK 强制）；新增两条 partial unique index（迁移 469/471）；复用既有 `trigger_evidence_kind`/`trigger_evidence_ref_id`（迁移 184）、`cr_id`（迁移 437）、`handoff_note`（迁移 122，prompt 载体）、`is_leader_task`（迁移 090）+ `squad_id`（迁移 127）列 | FR-4/FR-6/FR-7/FR-9/FR-11；TD-BL-10；PRD A4/A5 |

### 2.2 迁移 469 — 单审批记录幂等（FR-4）

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

### 2.3 迁移 470/471 — workspace-qualified 排队后继（FR-6/FR-7，TD-BL-10/11）

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

### 2.4 续跑任务行形状（仅新增 tenant carrier，其余复用既有列）

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

## 3. 接口契约

### 3.1 HTTP：POST /api/daemon/approvals/ack（既有端点，语义升级）

- 请求不变：`{"ids": ["<approval_record.id>", …]}`（daemon 侧零改动，NFR-6）。
- 成功（2xx，所有匹配记录均完成「delivered_at + 续跑任务」成对落地或幂等命中）：`{"status":"ok"}` 形态不变。
- 失败（5xx，任一记录 resolve/入队失败或预提交回调 error → 整批回滚）：新增结构化错误体，供运维检索（NFR-10）：

```json
{"error":"approval continuation failed",
 "reasons":[{"cr_id":"CR-2026-052","stage":"tech-design","reason":"leader-missing"}]}
```

- 幂等重放：已交付记录再 ACK → UPDATE 匹配 0 行 → 200（沿用现有 0 行分支行为）。
- 鉴权不变：仍经 `resolveDaemonWorkspace`（DaemonAuth 组，NFR-12），请求体 ids 无法越权指定 workspace。

### 3.2 Go 回调：GrantAckEvent + 双钩契约（FR-10，评审 TD-BL-6 修正）

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

### 3.3 sqlc 新查询（内部接口，`server/pkg/db/queries/approval.sql`）

| 查询 | 形态 | 用途 |
|---|---|---|
| `AckApprovalGrants` | `:many`，UPDATE … RETURNING `id::text, cr_id, stage, decision, approver_user_id::text` | FR-3 事务内第一步（现内联 SQL 迁入） |
| `GetCrShellIssueInWorkspaceForShare` | `:one`，`SELECT * FROM cr WHERE workspace_id=$1 AND cr_id=$2 FOR SHARE` | 解析第一步并锁定 cr 权威行（评审 TD-BL-5/TD-BL-8：并发 `cr.shell_issue_id`/status 投影写等到本事务提交，DD-10） |
| `CreateApprovalContinuationTask` | `:one`，guarded INSERT + `ON CONFLICT DO NOTHING RETURNING *`；`status`（`queued`/`deferred`）与 `fire_at` 参数化 | 事务内第二步（仿 `CreatePipelineTask`，agent.sql:651）；deferred 变体用于 257 让位（§4.3 阶梯 3） |
| `AppendApprovalContinuationEvidence` | `:one`，按 `(id, approval_workspace_id)` UPDATE 后继行追加 approvals[]/handoff_note（行锁已由阶梯 2 锁读持有，无 status 谓词；NOT EXISTS 幂等防同记录重复追加） | 阶梯 2 原子合并（TD-BL-7/9/10，§4.3） |
| `GetApprovalContinuationTaskByRecord` | `:one`，按 `(approval_workspace_id, kind, ref_id)` + 五状态含 running 读回 | 幂等重读阶梯 1（469 键；workspace 防御性限定） |
| `GetMergeableApprovalContinuationTaskByWorkspaceAndCrForUpdate` | `:one`，按 `(approval_workspace_id, kind, cr_id)` + `status IN ('queued','deferred')` 执行 `SELECT … FOR UPDATE` | 阶梯 2：仅 prompt 未快照的后继可合并（471 键；TD-BL-9/10/11，§4.3） |

`CreateApprovalContinuationTask` 显式写 `approval_workspace_id=$ws`，并在单条 INSERT 内联复核**完整权威链**（评审 TD-BL-2/5/10）：`JOIN agent a ON a.id=$agent AND a.workspace_id=$ws AND a.archived_at IS NULL AND a.runtime_id IS NOT NULL AND a.kind='user'` ∧ `JOIN issue i ON i.id=$issue AND i.workspace_id=$ws` ∧ `JOIN squad s ON s.id=i.assignee_id AND s.workspace_id=$ws AND s.leader_id=a.id AND s.archived_at IS NULL` ∧ `JOIN cr c ON c.workspace_id=$ws AND c.cr_id=$cr AND c.shell_issue_id=i.id`——任一守卫失败插 0 行（不静默，走 §4.3 阶梯 4 回滚）。后续按 CR 重读、锁读和合并均同时限定同一个 `$ws`，不能从冲突 fallback 越过 tenant fence。resolveContinuationTarget 的读在守卫前**已按固定锁序持有锁**（§4.2/DD-10）：守卫是锁之外的复核兜底，不再承担“防陈旧”的唯一职责（SDD 0.2 只靠语句级快照，评审 TD-BL-5 指出其挡不住 INSERT 后、提交前的并发改）。issue 侧锁读新增 `LockIssueInWorkspaceForShare`（issue.sql，FOR SHARE，返回整行；锁级理由见 §4.2/DD-10——不再仿既有 `LockIssueForChannelMediaBind` 的 FOR KEY SHARE：其只与删除方 FOR UPDATE 互斥、与普通非键 UPDATE 不互斥，评审 TD-BL-8）；squad/agent 复用既有 `LockSquadForAutopilotAssignment`/`GetAgentForUpdate`。

### 3.4 tools 侧：无外部接口变化（NFR-9）

outbox 事件文件 schema（`v`/`event_kind`/`cr_id`/`payload` 等）与 `dedup_name` 生成规则均不变，仅 `emitOutboxEvent` 内部 `comparable()` 对 payload 的比较剔除 `detected_at`（DD-6）。采集端（daemon）无感知。

## 4. 关键算法与流程

### 4.1 HandleGrantsAck（multica 侧核心，伪代码）

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

### 4.2 resolveContinuationTarget（FR-7，逐级 fail-closed + 权威锁链，每级一个 NFR-10 原因码）

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

### 4.3 CreateApprovalContinuationTask 幂等语义（FR-1/FR-4/FR-6；评审 TD-BL-7 修正）

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

### 4.4 tools 侧 FR-12 修复（comparable 剥离观测时点字段）

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

## 5. 技术选型与替代方案

> 按决策记录三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代）仅记录以下 11 条；不新增 ADR、不新增审批节点。

#### DD-1 触发点 = grant 已写入 worktree 后的 ACK
- **Context**：PRD 已拍板（FR-1），此处记录技术含义：ACK 是系统中唯一"grant 已可靠落盘"的确认信号；ACK 时点 grant 文件必已存在于 worktree，被唤醒 Agent 读取 `.crctl/grants/` 时数据已在位。
- **Alternatives**：飞书卡片回调（链路未封闭）、定时轮询（NFR-5 禁止）、状态事件（会复制状态机语义）。
- **Consequences**：daemon 交付与唤醒严格串行；ACK 失败整体可重试。

#### DD-2 专用 guarded INSERT（CreateApprovalContinuationTask）而非复用 mention 路径（CreateAgentTask）
- **Context**：FR-3 要求与 `delivered_at` 同事务；FR-4/FR-6 需要 ON CONFLICT 语义；FR-7 需要逐级结构化原因。
- **Alternatives**：复用 `CreateAgentTask`/`EnqueueTaskForSquadLeader`（task.go:1406）——其归因瀑布、GetAgent 预载、无事务注入点、无 ON CONFLICT 处理，改造成本与侵入面更大，且会把审批归因引入 trigger-comment 语义，不合 FR-9 最小上下文。
- **Consequences**：新增 6 条 approval.sql 查询 + 1 条 issue 锁查询并重跑 sqlc generate；形态与仓库既有 `CreatePipelineTask` 先例（agent.sql:651）同构，评审可对照。

#### DD-3 批量 ACK 单事务 all-or-nothing（而非逐记录部分成功）
- **Context**：FR-3"要么都生效要么都不生效"、FR-5"入队失败 ACK 返回 HTTP 错误"。
- **Alternatives**：逐 id 独立事务 + 响应携带 per-id 结果——daemon 侧需解析部分成功语义，超出"daemon 零改动"边界。
- **Consequences**：任一记录失败整批回滚、整批重投递（幂等写文件无害）；坏记录（如 leader 未配置）会连带阻塞同批健康 grant，直至配置修复——该 trade-off 由 FR-7"保持未 ACK 等待配置修复"显式背书，5xx 响应体 reasons 列表即为运维修复指引（NFR-10）。评审需确认此残余风险可接受。

#### DD-4 workspace-qualified 双唯一键（record 五态 + `(workspace,cr)` queued/deferred）而不是全局 cr_id
- **Context**：FR-4 的 record id 幂等索引（469）保持五态；FR-6 的后继上限必须按 CR 权威键 `(workspace_id, cr_id)`，不能按全局 cr_id。只有 queued/deferred 尚未快照 prompt，可安全合并；dispatched/waiting/running 必须视为 in-flight 前驱并另建后继（TD-BL-10/11）。
- **Alternatives**：`(agent_id,cr_id)` 或 `(issue_id,cr_id)` 会在 leader/shell issue 重指派后失去同 CR 约束；把 workspace 放 `context` 会扩张 FR-9 prompt-adjacent schema 且 JSON 可变；全局 cr_id 会跨租户冲突与泄漏；把 in-flight 纳入 471 又无法保留下一后继。
- **Consequences**：迁移 470 增加 nullable `approval_workspace_id` + continuation 必填 CHECK（无 FK），迁移 471 用 `(approval_workspace_id,cr_id)` 对 queued/deferred 建 CONCURRENTLY partial unique index；普通任务零改动。469/471 + 257 共同收敛并发，ClaimAgentTask 保证同 target 串行。

#### DD-5 保留 FR-10 `onGrantAck` 为预提交 error→HTTP 钩，另设显式 committed wake
- **Context**：FR-10 要求回调携带 id/stage/decision 且可返回 error；error 契约必须落在可回滚的原子边界内——提交后 5xx 是伪可重试失败（pending 端点按 `delivered_at IS NULL` 过滤，approval.go:351；daemon 对已交付记录不再重发 ACK，crevents.go:117-122）。SDD 0.2 为兼顾“error→5xx”与“唤醒需提交后”，把同一个 `Runner.WakeGrant/Reconcile` 在 COMMIT 前调一次——但真实 Reconcile 在读取 `delivered_at` 前就会取 advisory lock、写 pipeline_run/pipeline_node_run、可入队 pipeline task（runner.go:238-374），这些外部提交不随 ACK 回滚撤销，违反 multica ARCHITECTURE.md“Side effects publish only after committed state”与 FR-3 原子边界（评审 TD-BL-6）。
- **Alternatives**：保留旧回调 + 新增第二个回调——双通道并存，Runner 未来开启时语义分叉；单次提交后调用 + error→5xx——SDD 0.1 方案，制造虚假重试，作废；把 Reconcile 重构成“先校验后副作用”两段式——侵入 Runner 状态机，且校验段与 ACK 事务视图无法对齐；真实持久化重试（notified_at 列 + 服务端扫描）——NFR-4 禁止新重试框架，且唯一消费方 Runner 默认关闭，成本不成比例。
- **Consequences**：原 `SetGrantAckHandler`/`onGrantAck` 仅扩展签名并返回 error，预提交纯校验，error → 回滚/5xx；新增 `SetGrantAckCommittedHandler`/`onGrantAckCommitted` 专门在 COMMIT 后调用 `WakeGrant`，error → 日志/2xx。Runner 以 `ValidateGrantAck` + `WakeGrant` 分别接线。命名、FR 映射与 AC-9 均能机械指出“哪个 callback error 影响 HTTP”（TD-BL-12）。

#### DD-9 257 占槽时以 deferred 让位插入（而非向普通任务合并证据）
- **Context**：`idx_one_pending_task_per_issue_agent_v2`（迁移 257）谓词 = queued/dispatched 或带 `channel_issue_media_pending` 标志的 deferred。leader 的 (issue, agent) 槽被普通 comment/mention 任务占用时，`status='queued'` 的续跑 INSERT 冲突。SDD 0.2 将其判为 already-queued 跳过——但普通任务的 `buildCommentPrompt` 不渲染 handoff_note、无 grants 读取约定，跳过即“已 ACK、无可证明续跑载体”（评审 TD-BL-7）。
- **Alternatives**：把证据合并进普通任务行——prompt 不可达（上）；取消/顶掉普通 pending 任务——破坏既有任务归属（MUL-4302），越权；savepoint 重试——Postgres 23505 后需 savepoint 才能续事务，增加复杂度且无收益；为普通任务补 grants 读取约定——侵入全部 prompt 契约，超出本 CR 边界。
- **Consequences**：插入参数化 status/fire_at；257 冲突路径改插 `deferred + fire_at=now()`（谓词外，索引不冲突）；既有 `PromoteDueDeferredTasksForRuntime`（agent.sql:2255-2323）在槽释放后自动翻 queued（被占槽时跳过、不丢），`ClaimAgentTask` per-(issue,agent) 串行化保证顺序执行——FR-6 保持，零新增机制、零 prompt 侵入。可观测性新增 `slot-deferred`（Info）原因码。

#### DD-10 权威锁链 cr→issue→squad→agent（FOR SHARE 起步，先锁后读；锁级经评审 TD-BL-8 修正）
- **Context**：SDD 0.2 只锁 squad/agent，cr/issue 靠普通 SELECT + guarded INSERT 的语句级快照复核——单语句快照挡不住“INSERT 后、提交前”并发改 `cr.shell_issue_id`/`issue.assignee_id`，仍可能向旧 shell issue/旧 squad leader 落任务（评审 TD-BL-5）。SDD 0.3 给 cr/issue 加 FOR KEY SHARE，但该锁级**不与 FOR NO KEY UPDATE 冲突**（只与 FOR UPDATE 冲突）——而既有 `UpdateIssue`（issue.sql:164-257，改 assignee_id/assignee_type/status 等非键列）、crsync 的 cr 投影写（crsync.go:397/458/477）与 shell_issue_id upsert 都是普通非键 UPDATE（取 FOR NO KEY UPDATE）；`LockIssueForChannelMediaBind` 的既有用途仅是与删除方 `LockIssueForDelete` 的 FOR UPDATE 互斥（issue.sql:89-95/128-135）——故 FOR KEY SHARE 挡不住重指派/投影改（评审 TD-BL-8）。
- **Alternatives**：SERIALIZABLE 隔离——全库语义切换不可控，且 Postgres 需重试循环，超范围；把全部权威校验塞进单条 INSERT——语句级快照仍不持锁，不闭合；应用层悲观锁表——引入新锁基础设施，违反 NFR-4。
- **Consequences**：新增 2 条锁读查询（`GetCrShellIssueInWorkspaceForShare`/`LockIssueInWorkspaceForShare`，**FOR SHARE** = 与普通非键 UPDATE（FOR NO KEY UPDATE）及行 DELETE（FOR UPDATE）均互斥的最弱锁级；先例 = 既有 `LockSquadForAutopilotAssignment` FOR SHARE，squad.sql:12-20 注释“conflicts with an ordinary leader_id update”；FOR SHARE 与 FOR KEY SHARE 互相兼容，与既有 `LockIssueForChannelMediaBind`/迁移 284 的 KEY SHARE 持有方不新增冲突面）；固定锁序 cr→issue→squad→agent，先锁后读，与既有路径（crsync 只写 cr；issue 指派 issue→squad→agent；autopilot squad→agent）无环；guarded INSERT 全链 join 保留为复核兜底；新增并发 reassignment/projection race 集成测试（§7.4 AC-6b/6c，含“FOR KEY SHARE 下不成立”的锁级回归断言）。ACK 为低频路径，短事务内多 2 次点锁读，无热路径影响（§7.2）。

#### DD-11 排队后继的幂等原子合并（approvals[] 追加 + handoff 追加行）
- **Context**：SDD 0.2 阶梯 2 对已存在的排队后继仅判 already-queued，本次审批四字段不并入，与 TD-BL-7 的“无可证明续跑载体”同源：排队后继后续 ACK 的证据应落在它身上，否则后继运行时只能靠 grants 目录推断、拿不到 approval_record_id。
- **Alternatives**：每个审批必插一条任务会违反 FR-6 单后继上限；给 grant 文件加 approval_record_id 违反 NFR-8；向 dispatched/waiting/running 行追加 handoff 无法更新 daemon 已持有的 Task 快照（TD-BL-11）。
- **Consequences**：阶梯 2 只锁 `(approval_workspace_id,cr_id,status∈queued/deferred)` 并追加 approvals[]/handoff；claim 若先把 queued 推为 dispatched，锁读即 0 行并由阶梯 3 创建新后继。锁读若先持锁，claim 阻塞到合并提交后才构造 response，opening prompt 可执行地包含新增行。所有查询/UPDATE 带 workspace，跨租户不可读写（TD-BL-10）。

#### DD-6 FR-12 在 comparable() 内剥离 payload.detected_at（而非为 drift 事件单独传比较副本）
- **Context**：`comparable()` 是 dedup 名冲突时的内容一致性守卫；`detected_at` 是唯一的观测时点易变字段（顶层 `occurred_at` 本就不参与比较）。
- **Alternatives**：`emitDriftAudit` 单独传 `comparable_payload`——把易变字段清单推给每个调用方，未来新事件易再犯；改 `dedup_name` 生成规则——违反 FR-12"不改文件名规则"。
- **Consequences**：一行级改动 + 注释说明易变字段白名单语义；新事件若引入其它时点字段需同步维护该剥离逻辑（SDD 明确，实施期加注释）。

#### DD-7 续跑任务归因 = approver（originator_source='direct_human'）
- **Context**：MUL-4302 归因契约要求每个 run 可追溯到一个人；审批记录携带 `approver_user_id`（真实人工）。
- **Alternatives**：新增 source 标签（如 `approval_continuation`）——184 迁移允许无迁移加标签，但“审批人”就是直接人工动作，落入既有 `direct_human` 语义（attribution.go:26-33），无需扩词汇表；`owner_fallback` 会降级为 Agent 属主，不合 NFR-12“不伪造人工归因”。
- **Consequences**：不新增归因词汇；审批人可在既有归因 UI 看到自己审批触发的续跑。

#### DD-8 审批上下文经 handoff_note 送达 prompt（而非依赖 context JSON 水合）
- **Context**：claim/prompt 链路只对 `context.type=pipeline_node` 做专门 hydration（handler/agent.go:482），普通 issue 任务的 `buildPromptBody` 不读原始 context（daemon/prompt.go:171-201）；SDD 0.1 把审批上下文写进 context 却无任何可达 prompt 路径，Agent 实际收不到（评审 TD-BL-1）。`handoff_note`（迁移 122）是既有的、全链路已接线的 prompt 载体：claim 响应（handler/agent.go:789-790, 820）→ `Task.HandoffNote`（daemon.go:6767）→ opening prompt + issue_context.md（prompt.go:193-196）。
- **Alternatives**：为 `approval_continuation` 新增 claim→daemon→prompt 水合契约——侵入 daemon 侧 prompt 构建，超出“daemon 零改动”边界（DD-1）；把上下文塞进 issue 描述/评论——污染既有展示面，违反 FR-11/NFR-11；向普通 pending 任务合并证据——其 `buildCommentPrompt` 不渲染 handoff_note（prompt.go:335-365），不可达（评审 TD-BL-7，已由 DD-9 替代）。
- **Consequences**：多写一列既有列（handoff_note）；context JSON 保留为机器可读证据并升级为 approvals[] 可追加数组（TD-SUG-4）；handoff 模板直接用 `{cr_id}` 原值避免 `CR-CR-` 双前缀（TD-SUG-3）；续跑任务不写五个触发字段 → prompt 恒定 assignment 分支（§2.4 注）；新增 prompt 层测试锁定“四字段（含合并追加行）实际出现在 opening prompt”（§7.4）。

## 6. FR 到技术实现映射

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

## 7. 安全与性能考量

### 7.1 边界条件与安全

- **workspace 隔离（TD-BL-10）**：续跑目标以认证 daemon workspace 为根；任务行以 `approval_workspace_id` 承载 tenant authority，migration 470 CHECK 强制 continuation 非 NULL，migration 471 唯一键 `(approval_workspace_id,cr_id)`。Create/record-read/CR-lock-read/append 全部显式带同一 `$ws`，guarded INSERT 再复核 agent/issue/squad/cr 全链 workspace join。两个 workspace 的同名 CR 可并发各建一条后继，互不冲突、互不可读写；shell_issue_id 跨 workspace 漂移仍 0 行 fail-closed。
- **越权与陈旧 leader（评审 TD-BL-5/TD-BL-8 闭合）**：leader 解析走 issue→squad 关联，读-写全程同事务 + **权威锁链 cr→issue→squad→agent 固定顺序先锁后读**（`GetCrShellIssueInWorkspaceForShare`/`LockIssueInWorkspaceForShare` FOR SHARE——与普通非键 UPDATE（FOR NO KEY UPDATE）互斥，§4.2/DD-10；既有 `LockSquadForAutopilotAssignment` FOR SHARE / `GetAgentForUpdate` FOR UPDATE）：并发重指派 `issue.assignee_id`、投影改 `cr.shell_issue_id`、leader 变更与 runtime 解绑要么在本事务取锁前提交（读到新值），要么阻塞到本事务提交后——陈旧权威窗口消除，不再只靠 guarded INSERT 语句级快照；guarded INSERT 全链 join（`squad.leader_id = agent.id` 等）保留为复核兜底；无 leader 一律失败，不回退任意 Agent（FR-7）；不新增开放端点，ACK 鉴权不变（NFR-12）。
- **并发**：469 record-id 五态索引 + 471 `(workspace,cr)` queued/deferred 索引是硬兜底；`ON CONFLICT DO NOTHING` 输家只在本 workspace 重读。仅 queued/deferred 可合并；in-flight 状态另建后继，ClaimAgentTask 串行执行。
- **历史数据**：无回填迁移；旧 `delivered_at` 非空行天然不进 UPDATE 结果集（FR-8/AC-7）。
- **回调失败（TD-BL-12）**：FR-10 `onGrantAck` handler 在预提交返回 error → 回滚、delivered_at NULL、HTTP 5xx、daemon 真实重试；该 handler 契约上零外部副作用。`onGrantAckCommitted` wake error → Error 日志、HTTP 2xx，不伪造可重试结果。

### 7.2 性能

- ACK 为低频人工触发路径；单事务内完成 1 次 UPDATE + 每记录至多 4 次点查（含 2 次 FOR SHARE 锁读）+ 1 次 INSERT（或 1 次锁读+合并 UPDATE / 1 次 deferred 让位插入），无轮询/后台扫描（NFR-5）。锁链只在短事务内持有；crsync 的 cr 投影写若与 ACK 同瞬竞争会等待锁释放，量级毫秒、无热路径影响。
- daemon 侧零改动、零新增往返（NFR-6）；续跑任务与普通任务共用队列与 reclaim 机制。
- tools 侧：`comparable()` 仅多一次对象浅拷贝，仅 dedup 名命中时执行，无热路径影响。

### 7.3 可观测性（NFR-10 原因码全集）

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

### 7.4 测试设计（AC 映射）

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

### 7.5 残余风险（随评审确认）

1. **DD-3 批次联动阻塞**：坏 grant（leader 未配置）会阻塞同批其余 grant 的 ACK，直至配置修复。FR-7 显式背书该 fail-closed 语义；若评审认为不可接受，可后续追加 daemon 逐 grant ACK 的独立 CR（不在本 CR 范围）。
2. **排队后继的状态边界（TD-BL-11 闭合后）**：queued/deferred 尚未 claim，允许锁行合并并由后续 claim 快照完整 handoff；dispatched/waiting_local_directory/running 已快照或启动，永不追加新审批证据，而是建立独立 queued/deferred 后继。claim 与 ACK 的唯一竞态由 471 + FOR UPDATE 收敛为“合并后再 claim”或“先 claim、再建 successor”两种可测试顺序（AC-5g/5i），不依赖修改 daemon 内存 Task，也不再把 grants 目录当作 opening prompt 可达证明。
3. **257 占槽的让位延迟（TD-BL-7 闭合后）**：普通 pending 任务占用 (issue, agent) 槽时，续跑以 deferred 排队，等槽释放后由 sweeper 翻 queued——续跑发生在普通任务之后，符合 FR-6 串行化语义；runtime 离线时 deferred 等待（与任何 deferred 任务一致，不新增机制）。极端情形（普通任务长期 running）下续跑被推迟到其完成——这是“不并发唤醒、不注入沙箱”的直接结果，非缺陷。
4. **双钩回调的消费方约束（TD-BL-6/12 闭合后）**：FR-10 原名 `onGrantAck` 保持预提交 error→HTTP 契约且必须零副作用；`onGrantAckCommitted` 才执行真实 wake。若未来需要在 canonical handler 中写入副作用，必须先修订 PRD/事务边界，不能偷换两个名字的错误语义。
5. **权威锁链的竞争面（TD-BL-5/TD-BL-8 闭合后）**：FOR SHARE 锁在短事务内持有，阻塞面 = 并发 cr 投影写/issue 重指派/leader 变更（FOR NO KEY UPDATE/FOR UPDATE 持有方）——低频路径，等待毫秒级；FOR SHARE 与 FOR KEY SHARE 互相兼容，与既有 `LockIssueForChannelMediaBind`/迁移 284 owner fence 的 KEY SHARE 持有方不新增冲突面；残余理论死锁由 Postgres 死锁检测中止本事务 → 5xx → daemon 诚实重试（无部分效果）。

## 8. Prompt 采纳影响

**本节省略（条件不满足）**。判定依据（CR-2026-021 FR-25/AC-15）：本 CR 的 tools 侧 diff 仅触及 `crctl.mjs` 内 `emitOutboxEvent` 的 `comparable()` 比较逻辑（§4.4），**不触及** `crctl.mjs` 的 dispatch 分支、**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`——crctl 命令面与 guard deny 面均无新增/变更，无任何 skill 提示词需要改为调用新增/扩展子命令，故无需列出采纳清单。

## 9. 修订记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-08-27 | 初稿（write-tech-design 首轮） |
| 0.2 | 2026-08-27 | reviewLoop attempt 1 回修（quality-reviewer-agent 4 blocker，canonical `review-annotations/sdd.yml`，subject SHA `7e55be83…`）：TD-BL-1 上下文改经 handoff_note 送达 prompt（§2.4、DD-8）；TD-BL-2 解析全链 workspace-scoped + 锁对 + guarded JOIN 复核（§3.3/§4.2/§7.1）；TD-BL-3 回调两阶段契约（§3.2/§4.1、DD-5）；TD-BL-4 迁移 470 排除 running、持久化排队后继（§2.3/§4.3、DD-4、§7.4-7.5）；另采纳 TD-SUG-1（复用 broadcastTaskEvent+NotifyTaskEnqueued 顺序，§1.3/§4.1）与 TD-SUG-2（is_leader_task=true + overlay 留空说明，§2.4） |
| 0.3 | 2026-08-27 | reviewLoop attempt 2 回修（quality-reviewer-agent 3 blocker + 2 suggestions，canonical `review-annotations/sdd.yml`，subject SHA `57ab2fe8…`）：TD-BL-5 权威锁链 cr→issue→squad→agent 固定锁序先锁后读（新查询 `GetCrShellIssueInWorkspaceForKeyShare`/`LockIssueInWorkspaceForKeyShare` FOR KEY SHARE，§3.3/§4.2/§7.1，DD-10）+ reassignment/projection race 测试（AC-6b/6c）；TD-BL-6 回调拆双钩（`SetGrantAckPreflight` 预提交零副作用校验 + `SetGrantAckHandler` 提交后真实唤醒，§3.2/§4.1，DD-5）+ 零副作用与契约边界测试（AC-9b/9d）；TD-BL-7 阶梯 2 改为幂等原子合并（`AppendApprovalContinuationEvidence`：approvals[] 追加 + handoff 追加行 + NOT EXISTS 幂等，§4.3/§2.4，DD-11）、阶梯 3 改为 deferred 让位插入（257 谓词外 + `PromoteDueDeferredTasksForRuntime` 槽释放后翻 queued，§2.3/§4.3，DD-9）+ 冲突路径逐字段可达测试（AC-5d/5e/5f、prompt 层合并 handoff）；另采纳 TD-SUG-3（handoff 模板直接用 `{cr_id}` 原值，免 `CR-CR-` 双前缀）与 TD-SUG-4（context 升级为 approvals[] 可追加结构并固化 prompt 分支保证，§2.4/DD-8） |
| 0.4 | 2026-08-27 | reviewLoop attempt 3 回修（quality-reviewer-agent 2 blocker，canonical `review-annotations/sdd.yml`，subject SHA `83ba3b0d…`；评审循环经 squad leader 扩展一轮，attempt 4 复评）：TD-BL-8 锁级修正——cr/issue 锁读从 FOR KEY SHARE 改 FOR SHARE（`GetCrShellIssueInWorkspaceForShare`/`LockIssueInWorkspaceForShare`：与普通非键 UPDATE 的 FOR NO KEY UPDATE 互斥，锁矩阵误读更正；先例 `LockSquadForAutopilotAssignment`，§1.3/§3.3/§4.2/§7.1/§7.2/§7.5，DD-10）+ AC-6b/6c 重做为非键 UPDATE 阻塞断言（含 FOR KEY SHARE 下不成立的锁级回归守卫）；TD-BL-9 阶梯 2 收敛为锁读选中即锁行（`GetApprovalContinuationTaskByCrForUpdate` FOR UPDATE + 合并 UPDATE 去掉 status 谓词），0 行歧义消除：合并 0 行 ⟺ record 已含 → already-queued；锁读 0 行 ⟺ 状态离开谓词（claim 已推进 running）→ 阶梯 3 补插 deferred 新后继（§1.3/§3.3/§4.3/§6/§7.3，DD-11）+ claim-vs-append 并发测试（AC-5g/5h） |
| 0.5 | 2026-08-27 | cycle 2 / attempt 1 回修（canonical subject SHA `6dd72e9e…`）：TD-BL-10 新增 migration 470 `approval_workspace_id` carrier + CHECK、migration 471 `(workspace,cr)` queued/deferred 唯一索引，所有 fallback/merge 查询按 workspace 限定，并新增同名 CR 跨 workspace 并发隔离 AC-6d；TD-BL-11 仅合并 queued/deferred，dispatched/waiting/running 一律补插独立后继，AC-5g/5i 改为真实 claim-response 快照时序；TD-BL-12 保留 `onGrantAck`/`SetGrantAckHandler` 为预提交 error→5xx canonical callback，新增显式 committed wake 钩；采纳 TD-SUG-5，Go 验证改为 server module 目录执行。 |

## 独立评审与人工审批命令闭环 — 评审独立路由与审批卡可见性修复（v0.27 · CR-2026-053）

## SDD — 独立评审与人工审批命令闭环技术设计

> 输入：`change-requests/CR-2026-053/prd.md`（20 FR / 6 US / 31 AC，commit `a64de76`）+ source 设计稿 `docs/product/独立评审与人工审批命令闭环设计.md` v0.4。
> 本文档只补"技术实现方案"，不重复 PRD 的需求语义；FR 覆盖映射见 §6。

### 1. 架构概览

#### 1.1 目标与两条工作轨

一个 CR、两条独立工作轨，共享的只有 CR-ID 与现有执行环境，不建设共同的新框架：

- **Track A（tools 仓）——独立评审最小改造**：把四个 CR 评审 Skill（`review-requirement`/`review-tech-design`/`review-dev-plan`/`review-code`）的唯一 `owns` 收敛到 `quality-reviewer-agent`；作者型 Agent（`requirement-writer`/`dev-agent`）移除 `owns`、保留 `can-call`，其评审意图改为委派路由合同；三条 CR Pipeline 的 review 节点 prompt 明确要求新建独立 reviewer 运行。**不改** Pipeline schema、节点顺序、`reviewLoop`、`onFail`、状态机、gates、`review-record`/`approve` 协议、matrix parser。
- **Track B（Multica 仓）——CR→Issue 绑定与审批卡可见性**：新增 task-scoped 窄接口 `POST /api/crs/{cr_id}/bind-current-task`，在四个 review Skill 写临时评审 payload 之前执行同一平台前置步骤，把当前 task 原子绑定到 CR/Issue；同时新增调度层 reviewer task 创建契约（FR-B12，插入时原子继承 `issue_id`/`project_id`）；前端 gates 改为 `pending_stage` 非空即渲染唯一 `ApprovalCard`。存量 CR-2026-051/052 走同一接口修复，禁用直接 SQL。

#### 1.2 模块边界与改动面（跨仓）

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

#### 1.3 依赖方向（遵守两仓 ARCHITECTURE.md 硬不变量）

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

#### 1.4 关键流程（目标闭环，source §1 原样）

```text
作者 Agent 产出阶段内容 → Pipeline 到达 review-* 节点 → 新建 quality-reviewer-agent 独立任务
（任务插入时从可信来源 task/Issue 原子继承 issue_id/project_id，FR-B12）
→ review Skill 先将当前 Multica task 绑定到 CR/Issue（bind-current-task-to-cr）
→ review Skill 作业务判断 → crctl review-record 原子记录评审证据
→ Pipeline 按现有 reviewLoop 回修或进入 human_approval
→ crctl/Multica 状态投影得到 pending_stage → 项目会话显示唯一 ApprovalCard → 人类批准或驳回
→ 现有 Ed25519 grant 经 daemon 投递 → crctl approve 复核门禁并推进状态
```

### 2. 数据模型

> 全部复用既有表与列（FR-B9：不新增表、不新增列）。改动只体现在"既有列被新写路径使用"与"既有 INSERT 语句补列"。

#### 2.1 核心实体与字段（只列本 CR 触及的列）

| 实体（表） | 字段 | 类型 | 本 CR 语义 |
|---|---|---|---|
| `agent_task_queue` | `id` | uuid | task 主键 |
| | `issue_id` | uuid nullable | 任务所属 Issue；FR-B12 要求 reviewer task 在插入时从可信来源继承 |
| | `project_id` | uuid nullable | 任务所属 Project；同上继承 |
| | `cr_id` | text nullable | CR 归属；绑定接口 CAS 写 `NULL → cr_id` 或同值 |
| | `pipeline_node_run_id` | uuid nullable | Runner pipeline 任务幂等键 |
| | `originator_user_id` / `accountable_user_id` / `originator_source` / `delegated_from_task_id` 等 | — | 既有归因快照，`CreatePipelineTask` 已从来源 task 逐字拷贝，本 CR 不改变归因语义 |
| | —（无 `workspace_id` 列） | — | **本表没有 workspace 列**；task 的 workspace 隔离只能经 `agent_task_queue.agent_id → agent.workspace_id` 取得（已核实 `GetAgentTaskInWorkspace`、`SetTaskCRAttributionIfValid` 均以此方式做租户隔离） |
| `agent` | `id` / `workspace_id` / `archived_at` / `runtime_id` | uuid / uuid / timestamptz / uuid | Agent 及其所属 workspace（`workspace_id` NOT NULL）；task 的 workspace 权威来源，绑定事务据此校验 `agent.workspace_id = actor.workspace_id` |
| `cr` | `cr_id` | text | CR 标识（workspace 内） |
| | `shell_issue_id` | uuid nullable | CR→Issue 投影链接；绑定接口 CAS 写 `NULL → issue_id` 或同值（列来自 `server/migrations/433_aifirst_cr_projection.up.sql`） |
| | `title` / `status` / `needs_reconcile` / `updated_at` | — | 既有投影字段，gates 查询已消费 |
| `issue` | `id` | uuid | Issue 主键 |
| | `project_id` | uuid | Issue 所属 Project（gates 查询通过 `cr.shell_issue_id → issue.project_id` 限定项目 CR） |
| `project` | `id` / `workspace_id` | uuid | Project 及其 workspace（workspace 隔离权威） |
| `activity_log` | `action` + 结构化字段 | — | 审计：`cr_issue_bound`（成功）、`cr_issue_bind_rejected`（冲突拒绝），FR-B4 |

#### 2.2 存储方案

- 无新表/新列/新索引/新外键（遵守 multica CLAUDE.md：不加 FK、新索引必须 `CONCURRENTLY`——本 CR 不新增索引）。
- 绑定三写入（`agent_task_queue.cr_id` + `cr.shell_issue_id` + `activity_log`）在同一数据库事务内完成，任一部分失败整体回滚（NFR-1）。
- CAS 约束（NFR-2）**不**在 `rows affected` 上区分——`UPDATE ... WHERE <字段> IS NULL OR <字段> = <目标值>` 对"NULL→值"与"同值重放"都会命中并更新 1 行，无法靠影响行数区分两者。绑定事务用 `FOR UPDATE` 锁住 task 行与 cr 行后，直接读锁内旧值（`task.cr_id` / `cr.shell_issue_id`）判定 `changed`（§4.1）：同值重放 `changed=false`，不重复写成功审计、不重复发刷新事件（AC-B3）。

#### 2.3 涉及 sqlc 的变更面

- `server/pkg/db/queries/agent.sql`：
  - `CreatePipelineTask`（现 INSERT 列不含 `issue_id`/`project_id`）追加这两列，值在 SQL 内从来源 task 行 `s.issue_id`/`s.project_id` 直接拷贝，并追加 `s.issue_id IS NOT NULL` 守卫（FR-B12，§4.4 路径 1）。
  - 新增绑定读写查询：按 `(task_id, agent_id)` 读 task 并 JOIN `agent` 校验 `agent.workspace_id`（复用 `GetAgentTaskInWorkspace` 模式）、按 `issue_id` 读 issue（`GetIssue`）、按 `(project_id, workspace_id)` 读并锁 project（`GetProjectInWorkspace`/`LockProjectForDelete` 模式）、按 `(workspace_id, cr_id)` 读并锁 CR（`GetCrShellIssueInWorkspaceForShare` 模式）、锁内旧值判定后更新 `task.cr_id` / `cr.shell_issue_id`、写 `activity_log`。具体新 query 命名在实施期确定，遵循既有命名惯例。
- sqlc 生成物 `server/pkg/db/generated/` 由 `make sqlc` 再生成，禁手改（ARCHITECTURE.md 不变量 5）。

#### 2.4 PipelineTaskSpec 不改（FR-B12）

`PipelineTaskSpec` **不新增** `SourceIssueID`/`SourceProjectID` 字段——`issue_id`/`project_id` 的继承在 `CreatePipelineTask` SQL 内完成：`FROM agent_task_queue s ... SELECT s.issue_id, s.project_id` 直接从来源 task 行读值（§4.4 路径 1）。调用方（Runner）既不提供、也不能覆盖这两个字段，从协议层杜绝"调用方直接指定"（FR-B12 第 1 条）。

### 3. 接口契约

#### 3.1 新增 HTTP 接口：绑定当前 task 到 CR

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
| `TASK_ISSUE_REQUIRED` | 422 | 当前 task 没有 Issue，或 Issue 不存在/与 task workspace 不一致（根因均为创建路径错误，FR-B12） |
| `CR_NOT_FOUND` | 404 | 同 workspace 中不存在该 CR |
| `TASK_PROJECT_MISMATCH` | 422 | task/Issue/Project 关系不闭合 |
| `TASK_CR_CONFLICT` | 409 | task 已绑定另一 CR |
| `CR_ISSUE_CONFLICT` | 409 | CR 已绑定另一 Issue |
| `CR_BIND_FAILED` | 500 | 事务或审计失败，全部回滚 |

#### 3.2 前端组件契约（FR-B6）

`GET /api/projects/{id}/gates` 响应模型**不变**（`projectGateCR` 结构已含 `pending_stage`/`can_approve`/`evidence`/`evidence_digest`/`key_id`/`pending_advance`/`gate_nodes`，见 `server/internal/governance/project_gates.go`）。

- 从 `CrGateCard` 内部提取 `ApprovalCard` 为可独立调用的组件，继续消费相同字段：`cr.cr_id`、`cr.pending_stage`、`cr.can_approve`、`cr.evidence`、`cr.evidence_digest`、`cr.pending_advance`。
- `CrGateCard` 现有"`human_approval` + `running` → ApprovalCard"分支不变；新增"无当前 node 但 `pending_stage` 非空 → 直接 ApprovalCard"分支放在 `project-team-agent-chat.tsx` 的渲染循环层（见 §4.3）。
- 批准/驳回仍走现有 API；不构造伪 `GateNode`、不直接改状态、不签发新 grant。

#### 3.3 CLI 薄包装命令（FR-B1）

Multica CLI 新增薄包装命令（名由实施期按 CLI 命名惯例定，形如 `multica cr bind-current-task <cr-id>`），仅把 `mat_` task token 与 CR-ID 发给上述接口、透传结构化结果；不做业务判断、不落账本。

### 4. 关键算法与流程

#### 4.1 绑定事务（FR-B2，服务端单一事务）

伪代码（Go，`TaskService` 内，复用既有 pgx 事务边界）：

```text
func BindCurrentTaskToCR(ctx, crID):
    actor = task_token_actor_from_context(ctx)            // X-Task-ID/X-Agent-ID/X-Workspace-ID（auth.go:103-106）
    if actor == nil: return TASK_CONTEXT_REQUIRED
    begin tx
    // 1) 锁 task 行（经 task→agent 校验 workspace；agent_task_queue 无 workspace_id 列）
    task = SELECT t.*, a.workspace_id AS agent_ws
           FROM agent_task_queue t JOIN agent a ON a.id = t.agent_id
           WHERE t.id = actor.task_id AND t.agent_id = actor.agent_id
           FOR UPDATE OF t, a
    if task == nil: return TASK_CONTEXT_REQUIRED          // 行缺失/未撤销 token 校验在前=无效
    if task.agent_ws != actor.workspace_id: return TASK_CONTEXT_REQUIRED  // token↔agent workspace 不一致
    if task.issue_id == NULL: return TASK_ISSUE_REQUIRED  // 硬技术失败=创建路径未按 FR-B12
    // 2) 锁 issue，校验 workspace
    issue = SELECT ... FROM issue WHERE id = task.issue_id FOR UPDATE
    if issue == nil or issue.workspace_id != task.agent_ws: return TASK_ISSUE_REQUIRED
    if issue.project_id == NULL: return TASK_PROJECT_MISMATCH
    // 3) 锁 project，校验 workspace + 归属闭合（FR-B2 第 4/5 条）
    project = SELECT ... FROM project WHERE id = issue.project_id FOR UPDATE
    if project == nil or project.workspace_id != task.agent_ws: return TASK_PROJECT_MISMATCH
    if task.project_id != NULL and task.project_id != issue.project_id: return TASK_PROJECT_MISMATCH
    // 4) 锁 cr，校验 workspace
    cr = SELECT ... FROM cr WHERE cr_id = crID AND workspace_id = task.agent_ws FOR UPDATE
    if cr == nil: return CR_NOT_FOUND
    // 5) CAS 冲突检查（非空异值拒绝）
    if task.cr_id != NULL and task.cr_id != crID: return TASK_CR_CONFLICT
    if cr.shell_issue_id != NULL and cr.shell_issue_id != issue.id: return CR_ISSUE_CONFLICT
    // 6) changed 由锁内旧值判定（不依赖 rows affected——WHERE IS NULL OR 同值 对
    //    NULL→值 与同值重放都返回 1 行，无法区分）
    taskChanged = (task.cr_id IS NULL)
    crChanged   = (cr.shell_issue_id IS NULL)
    changed     = taskChanged OR crChanged
    if taskChanged: UPDATE agent_task_queue SET cr_id = crID WHERE id = task.id
    if crChanged:  UPDATE cr SET shell_issue_id = issue.id WHERE id = cr.id
    if changed:    INSERT activity_log(action='cr_issue_bound', details={workspace,issue,project,task,agent,cr})
    commit tx                                              // 任一步失败 → rollback，两字段零部分更新
    if changed: publish cr:updated / project refresh events // 提交后发布；失败记错误、不 rollback
    return {cr_id, task_id, issue_id, project_id, changed}  // 同值重放 changed=false、无新审计、无事件
```

锁顺序固定为 agent → task → issue → project → cr（全部按主键等值查找，同一全局顺序避免死锁）。CAS 语义由第 5 步的旧值校验 + `FOR UPDATE` 排他锁共同保证：第 6 步的 UPDATE 因已持锁且已校验"NULL 或同值"，必命中且只写一行。`changed` 直接取自锁内旧值而非 `rows affected`，因此能区分"NULL→值（changed=true）"与"同值重放（changed=false）"，并覆盖部分已绑定组合（task 已绑 CR 但 CR 未绑 Issue、或反之——只要任一字段从 NULL 落值即 `changed=true`）；同值重放不重复写成功审计、不重复发刷新事件（AC-B3）。

冲突路径（`TASK_CR_CONFLICT`/`CR_ISSUE_CONFLICT` 等前置条件拒绝）不写绑定字段，改为写 `activity_log(action='cr_issue_bind_rejected', details={workspace, issue, project, task, agent, cr, 当前值, 拒绝原因})` 后提交/返回，零覆盖（FR-B4）。`activity_log` 只有 `workspace_id`/`issue_id`/`actor_type`/`actor_id`/`action`/`details` 列（已核实无 Project/task/CR 专用列），Project/task/CR/当前值/原因均进 `details` JSONB（不新增列，FR-B9）。

#### 4.2 review Skill 绑定前置步骤（FR-B7，四个 Skill 同一实现）

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

#### 4.3 审批卡渲染规则（FR-B6）

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

#### 4.4 reviewer task 创建契约（FR-B12，三条路径的可执行契约）

三条受支持路径在"插入时原子继承 `issue_id`/`project_id`"上收敛，各自落点到具体 service/query，调用方一律不能指定这两个字段：

1. **Pipeline review 节点 Runner 调度**（`task.go:374 EnqueuePipelineTask` → `agent.sql:651 CreatePipelineTask`）：
   - 现 INSERT 列不含 `issue_id`/`project_id`——本轮在列清单追加二者，值在 SQL 内从来源 task 行 `s.issue_id`/`s.project_id` 直接拷贝（`FROM agent_task_queue s ... SELECT s.issue_id, s.project_id`），并追加守卫 `s.issue_id IS NOT NULL`。
   - 原子拒绝：来源 task 无 `issue_id` 时 INSERT 写 0 行 → `pgx.ErrNoRows` → `EnqueuePipelineTask` 先按既有幂等逻辑 `GetActivePipelineTask` 复查，仍未命中即返回 `ErrRunnerAttributionInvalid`（技术失败，不落 NULL task）。
   - 调用方屏蔽：`PipelineTaskSpec` 不新增任何 Issue/Project 字段（§2.4），Runner 传不了也覆盖不了这两个值。
2. **作者 Agent/coordinator 委派路由**（issue 评论 mention `@quality-reviewer-agent`，`task.go:1385 EnqueueTaskForMention` → `enqueueMentionTaskWithCommentPlanAndOriginator` → `agent.sql:312 CreateAgentTask`）：
   - 插入点已把 `issue_id`/`project_id` 从入参 `issue` 继承：`CreateAgentTask` 参数 `IssueID = issue.ID`、`ProjectID = issue.ProjectID`（CR-2026-010 起已 stamp `project_id`）。
   - 原子拒绝：该路径以 `issue db.Issue` 整行为输入，`issue.ID` 恒非空（mention 只发生在某个 Issue 上），故不存在"来源缺 issue_id"的失败态；`project_id` 继承 `issue.project_id`（可为 NULL，FR-B2 只强制 `issue_id` 非空，`project_id` NULL 由绑定事务第 3 步校验闭合）。
   - 调用方屏蔽：`issue`/`agent_id` 由评论处理器从评论的 `issue_id` 与 mention 目标解析，评论作者不能指定 task 的 `issue_id`/`project_id`。
3. **issue 评论 mention 入队路径**（成员/人工在 Issue 评论中 `@quality-reviewer-agent`）：与路径 2 共用同一插入点 `enqueueMentionTaskWithCommentPlanAndOriginator` → `CreateAgentTask`，`issue_id`/`project_id` 同从该 Issue 派生（`attribution.SourceDelegation` vs `direct_human` 只影响归因快照，不影响 Issue/Project 继承）。

**负向测试锚点（覆盖 AC-B10/AC-B11，三条路径都要有）**：
- Runner 路径：来源 task `issue_id IS NULL` 时 `CreatePipelineTask` 返回 `ErrNoRows` 且 `agent_task_queue` 无新增行；来源 task 有值时新行 `issue_id`/`project_id` 与来源行逐位相等。
- mention/委派路径：`issue.project_id IS NULL` 时新 task 行 `project_id` 为 NULL 但 `issue_id` 非空；`issue.ID` 为有效 UUID 时新行 `issue_id = issue.ID`；构造性反例测试断言"不存在 issue_id 为 NULL 的 reviewer task 能经 mention 路径创建"。
- 违规兜底（AC-B11）：若某实现绕过上述路径硬造出 `issue_id IS NULL` 的 reviewer task，`bind-current-task-to-cr` 在绑定前置步骤返回 `TASK_ISSUE_REQUIRED` 且零绑定写入、不写 canonical review、不静默降级。

`bind-current-task-to-cr` 不信任调用方字段、仍只从 task 行与数据库关系派生 Issue/Project（FR-B1/B2 不变）；本契约只继承 `issue_id`/`project_id`，不权威写 `cr_id`（`cr_id` 仍由 review Skill 提交并受 workspace+CAS 校验），FR-B11 升级条件不变。

### 5. 技术选型与替代方案

本 CR 是"最小改造"，绝大多数实现复用既有能力，故决策记录只保留满足"难以逆转 + 无上下文会疑惑 + 有真实权衡替代"三判据的项；其余用"复用"表格而非伪造替代方案。

| 决策点 | Decision | Alternatives（真实权衡） | Consequences |
|---|---|---|---|
| 绑定放在 review Skill 还是 Agent/Pipeline | **review Skill**（FR-B7） | Agent 层：路由无 I/O 编排职责；Pipeline 层：会内嵌绑定 API/SQL 细节，违背"Prompt 不内嵌绑定" | Skill 拥有编排步骤与 I/O；代价是四个 review Skill 需同构改一遍（可接受，改动小且一致） |
| 绑定接口是否接受调用方 `issue_id`/`project_id` | **不接受**，全服务端从 task token + 数据库派生 | 接受调用方字段：省一次查询但把"谁绑谁"的权威交给客户端 | 身份不可伪造（NFR-4）；代价是接口必须 task-scoped、非 task 调用一律拒绝 |
| `cr_id` 是否由调度层权威写 | **否**（本 CR 不升级） | 调度层创建 reviewer task 时权威写 `cr_id`：彻底消除同 workspace 错绑，但需改 enqueue 协议/引入签名来源 | 保留残余风险（FR-B11 明示），错绑实际发生才升级；代价是信任上限降低但改动面最小 |
| 审批卡渲染依据 | **`pending_stage` 非空即渲染**（FR-B6） | 继续以 `gate_nodes` 为准：需先修 node 投影，且违背"当前状态足以决定当前审批卡"原则 | 前端只加一个分支 + 提取组件；代价是需保证 `pending_stage` 服务端语义稳定（已由既有 `pendingApprovalStage(status)` 提供） |
| 是否新增 reviewer task 的 Issue 继承为独立协议 | **否**，只补 `CreatePipelineTask` 两列（从来源 task 行拷贝）+ 复用 mention 路径既有 `CreateAgentTask` 的 Issue 继承 | 新增 enqueue 协议身份模型：超出本 CR 最小边界，且 PRD 明示不引入签名来源 | 改动面最小；代价是调用方仍可能漏配来源 Issue（由"来源无 issue_id 拒绝创建"兜底） |

复用清单（不重新设计，PRD §1.3 已核实）：

| 能力 | 复用点 |
|---|---|
| 评审落盘 | `crctl review-record`（零改动） |
| 人工审批 | `crctl approve`（零改动） |
| task token 身份 | `mat_` 中间件写入的 `X-Task-ID`/`X-Agent-ID`/`X-Workspace-ID` |
| CR→Issue 归因 | `SetTaskCRAttributionIfValid`（复用其 workspace 校验思想，补齐 CAS/审计/刷新） |
| 项目 gates 与审批卡 | `/api/projects/{id}/gates` 响应模型 + `ApprovalCard`/`CrGateCard` |

### 6. FR 到技术实现映射

#### Track A（tools 仓）

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

#### Track B（Multica 仓）

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
| FR-B12 | `CreatePipelineTask` INSERT 从来源 task 行 `s.issue_id`/`s.project_id` 直接拷贝并加 `s.issue_id IS NOT NULL` 守卫；mention/委派路径 `CreateAgentTask` 已从 Issue 继承 `issue_id`/`project_id`（`PipelineTaskSpec` 不改，§4.4）。 |

### 7. 安全与性能考量

#### 7.1 安全控制点

- **身份不可伪造（NFR-4）**：task/agent/workspace 由 `mat_` task token 中间件权威写入、覆盖客户端头（`auth.go:103-106`）；Issue/Project 由 task 行与数据库关系派生，调用方不能指定。绑定事务内再以 `agent.workspace_id` 与 `project.workspace_id` 交叉校验（§4.1），token 携带的 workspace 与 DB 行不一致即拒绝。handler 层按 multica CLAUDE.md"Backend UUID Rules"经 `parseUUIDOrBadRequest` 解析路径 `cr_id` 外的 UUID，任务/工作区身份一律来自 actor context。
- **CAS 零覆盖（NFR-2）**：两个绑定字段只允许 `NULL → 值` 或同值；异值拒绝，防止恶意/错误 task 抢先错绑（FR-B11 残余风险受控）。
- **人类审批边界**：Agent 不得代批准；review PASS 与人工批准仍是两个节点；本 CR 不改 `crctl approve` 授权模型（NFR-4，ARCHITECTURE.md 不变量 7）。
- **失败关闭**：认证/workspace/authority 边界 fail closed；绑定失败硬失败、不静默降级写 canonical review（NFR-6）。

#### 7.2 性能

- 绑定事务是 `FOR UPDATE` 锁定 task（JOIN agent）、issue、project、cr 四行 + 至多两行绑定更新 + 一次审计插入，处于 review 时点（低频、非热路径），无吞吐风险。
- `CreatePipelineTask` 增加两列拷贝来自来源行 `s.issue_id`/`s.project_id`（这两个列在 task 插入后不变，读无需加锁），无额外 JOIN/索引开销。
- 前端渲染改为每 CR 至多一张 ApprovalCard + 历史节点，复杂度与现有遍历同级，无新增网络请求（复用既有 gates 查询结果）。

#### 7.3 边界条件

- `pending_stage` 为空（CR 非审批状态）→ 不渲染当前审批卡；CR 离开审批状态后当前卡自然消失、历史节点保留（AC-C4）。
- 同值重放 → `changed=false`，不破坏绑定（AC-B3）。
- 事务/审计失败 → 两字段零部分更新（AC-B6）。
- 事件发布失败 → 不回滚已提交事务，记错误并依赖既有重查询恢复（NFR-5）。

### 8. Prompt 采纳影响

> 本节为条件性小节（CR-2026-021 FR-25/AC-15）。本 CR 的 diff **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，也**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（范围排除明示 crctl 零改动、不新增 `crctl review` 命令），故本节省略。
> 唯一与 crctl 相关的变化是"review Skill 在 `review-record` 之前插入平台绑定前置步骤"，该变化发生在 Skill 文档层，不影响 crctl 命令面或 guard deny 面。

### 9. 实施文件清单与提交口径

#### tools 仓（Track A）

修改：`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`agents/quality-reviewer-agent.md`、`agents/requirement-writer.md`、`agents/dev-agent.md`、`agents/_index.yml`、`pipeline-templates/{requirement-authoring,architecture-design,code-implementation}.pipeline.json`、`skills/requirement/review-requirement/SKILL.md`、`skills/develop/{review-tech-design,review-dev-plan,review-code}/SKILL.md`、（如需）`README.md`。不修改：`dir-graph.yaml`、`gates.json`、`crctl approve`/`review-record` 协议、matrix parser。

#### multica 仓（Track B）

修改：`server/cmd/server/router.go`、新增 handler、`server/internal/service/task.go`、`server/pkg/db/queries/agent.sql` + sqlc 生成物、CLI 薄命令、`packages/views/projects/components/cr-gate-card.tsx`、`project-team-agent-chat.tsx`、对应 Go/React 测试、`CUSTOM.md`。

#### 提交/checkpoint 口径

- SDD 本文件落盘到 knowledge-base 仓（operational workspace）`change-requests/CR-2026-053/sdd.md`，提交消息 `[cr] write tech design CR-2026-053`。
- 两个目标代码仓的 ARCHITECTURE.md 均已存在（`tools/ARCHITECTURE.md`、`multica/ARCHITECTURE.md`），本轮**不新起草**、只读引用。
- Track A/B 代码变更在 code-implementation 阶段于各自 `resources[].worktreePath` 分别提交；架构审批后由同一批 `crctl checkpoint` 纳入（FR-07.2 口径）。

### 10. 残余风险与升级条件

| 风险 | 当前控制 | 升级条件 |
|---|---|---|
| 作者 Agent 技术仍可直接调用 review Skill | 唯一 owner + Agent 路由 + Pipeline prompt + 结构测试 | 再发真实自评逃逸 → 引入调用级执行身份拦截 |
| CR-ID 由 Skill 提交，同 workspace 内可能错绑 | task token + 数据库派生 Issue/Project + CAS + 审计 | 错绑实发或安全升级 → 调度层权威写 `task.cr_id` |
| 不支持 subagent 的运行时不能单会话跑完 | 停在 review 节点 + 第二独立会话 | 多运行时频繁受阻 → 统一调度 Adapter |
| 成功事务后刷新事件发送失败 | 记错误，依赖现有重查询恢复 | 持续不可见 → 复用现有事件重试能力 |
| 旧 PASS 无独立运行证明 | 保留历史、已知事故 CR 手工重评 | 不批量废止/伪造身份 |

---

**SDD 完成标志**：本文件完整落盘后，将 CR status 从 `requirement-approved` 推进 `tech-designing` → `tech-design-review-pending`，等待 `review-tech-design` 进入。
