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
