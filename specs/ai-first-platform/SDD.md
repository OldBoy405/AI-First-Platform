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
