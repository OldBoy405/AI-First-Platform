---
id: ai-first-platform-sdd
spec-id: ai-first-platform
type: SDD
cr-ref: CR-2026-002
cr-history: [CR-2026-001, CR-2026-002]
title: AI First 研发协同平台 — 技术设计基线
target-version: "0.11"
status: ga
created: "2026-07-30T21:49:02+08:00"
updated: "2026-07-31T19:35:26+08:00"
version: v0.2.0
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

## 基线变更记录

| 日期 | 基线版本 | CR | 说明 |
|------|---------|----|------|
| 2026-07-30 | v0.1.1 | CR-2026-001 | 基线建立：M0 地基技术设计回写 |
| 2026-07-31 | v0.2.0 | CR-2026-002 | 改为累积式基线：保留 M0 全文并新增 P1 治理核心节；组件表扩至 12 项（M0 4 + P1 8） |
| 2026-07-31 | v0.2.1 | CR-2026-003 | 缺陷修补附记（§9）：embedded 占位符幂等键碰撞（缺陷 A）+ 归档 CR 自愈（缺陷 C）；不新增 FR/AC，缺陷 B 明确不修 |
| 2026-08-01 | v0.3.0 | CR-2026-004 | 新增 P2 D1 里程碑节：共享队列容量治理（守卫/插队/撤回/读侧）；4 项实现期偏差留痕 |
| 2026-08-01 | v0.3.1 | CR-2026-005 | 新增治理工具链补丁节：deliveryIndexComplete 门禁 + writeback-tasks 重写；2 项实现期偏差留痕 |
| 2026-08-02 | v0.4.0 | CR-2026-006 | 新增 P2 CR-A 里程碑节：容器 Issue 方案+薄发送端点+模型选择器技术设计；3 项实现期偏差/代码评审发现留痕 |

### 实现期与设计的偏差（已在各 TASK 完成记录留痕）

| 项 | 设计 | 实现 | 原因 |
|---|---|---|---|
| 审计上报通道 | 结构化 stdout 行 → daemon 捕获解析 | 复用 outbox 事件通道（`event_kind: audit`） | 离线积压/ack/三振语义免费复用，daemon 零改动 |
| 工具调用摘要落点 | 与 `skills_used[]` 同层 | 服务端 CompleteTask 聚合进 `result.tool_calls` | multica 上游无 `skills_used[]` 字段；服务端聚合避免信任 daemon 输入 |
| daemon 模式对账 | 定时 `crctl status --json` 快照上报 | daemon 直读 `_backlog.yml` 原文 + HEAD，服务端统一解析 | 避免 daemon 依赖 node 运行时；两模式共用一个解析器 |
| daemon workspace 绑定 | 仅信 `mdt_` daemon-token | `mdt_` 优先 + PAT 回退查 member 表 | 上游 `mdt_` 签发流程尚未接线，真实 daemon 走 PAT 路径（T11 实测暴露） |
