---
id: ai-first-platform-sdd
spec-id: ai-first-platform
type: SDD
cr-ref: CR-2026-012
cr-history: [CR-2026-001, CR-2026-002, CR-2026-003, CR-2026-004, CR-2026-005, CR-2026-006, CR-2026-008, CR-2026-009, CR-2026-007, CR-2026-010, CR-2026-011, CR-2026-012]
title: AI First 研发协同平台 — 技术设计基线
target-version: "0.19"
status: ga
created: "2026-07-30T21:49:02+08:00"
updated: "2026-08-04T01:30:00+08:00"
version: v0.9.0
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

