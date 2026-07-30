---
id: CR-2026-001-sdd
type: SDD
cr-ref: CR-2026-001
title: AI First 研发协同平台 — M0 地基 技术设计
status: draft
created: "2026-07-30T21:49:02+08:00"
updated: "2026-07-30T22:38:47+08:00"
version: v0.1.1
refs:
  upstream: [CR-2026-001-prd]
  downstream: []
components: [selfhost-compose, tools-consistency-ci, agent-frontmatter-adapter, issue-dispatch-smoke]
---

# AI First 研发协同平台 — M0 地基 技术设计

> 对应 `change-requests/CR-2026-001/prd.md` 的 FR-1~FR-4。范围严格锁定在 PRD 已经收窄过的 M0（地基），不含 P1 的 CR 治理投影（`cr`/`cr_sync_event`/`approval_record`/`pipeline_run`/`pipeline_node_run` 五张表、`issue.cr_id`/`agent_task_queue.cr_id` 两处 ALTER）——那批 schema 变更属于总 PRD P1-F1（CR 事件同步到 PG 投影），本 CR 不涉及，留给 P1 阶段注册的后续 CR。本文档不重写架构约束，因为本仓库还没有 `ARCHITECTURE.md`（M0 完成前平台没有实际代码，架构约束目前就活在 `docs/product/AI-First平台-PRD.md` §3 五方组装 与 `docs/product/P0-数据模型映射表.md` 里）。

## 1. 架构概览

### 1.1 模块边界

M0 只新增/触碰四个边界清晰的模块，互不依赖对方内部实现：

| 组件 | 职责 | 依赖 |
|---|---|---|
| `selfhost-compose` | fork 后的 Multica 在内网起全栈；剥离 Stripe/`mcn_`/多 workspace 注册 | Multica 现有 Docker Compose/Helm 编排（原样复用，只改配置） |
| `agent-frontmatter-adapter` | 把 `tools/agents/*.md`（9 个）注册为 Multica `agent` 表行 | `selfhost-compose` 已起（需要能连上 Postgres/API）；Multica 既有 `multica agent create` CLI 或 `POST /api/agents` |
| `issue-dispatch-smoke` | 冒烟验证：派 Issue → daemon 领取 → 执行完成 | `agent-frontmatter-adapter` 已跑完（需要至少一个已注册 Agent） |
| `tools-consistency-ci` | `dir-graph.yaml#agents.contract` 4 条不变式的 CI 校验 | 无运行时依赖，纯静态校验 tools 包文件本身 |

### 1.2 关键流程

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

## 2. 数据模型

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

## 3. 接口契约

M0 不新增 HTTP/WS 接口。`agent-frontmatter-adapter` 复用 Multica 已有入口：

- **首选**：`multica agent create`（已存在的 CLI，具体参数需在开发计划阶段核对 `server/internal/service/builtin_skills/multica-creating-agents/SKILL.md` 与 `references/creating-agents-source-map.md`——这两份文档是 Multica 仓库里已有的、对 Agent 创建契约做过源码级追溯的参考，比重新读 Go 源码更快）。
- **备选**：直接调 `POST /api/agents`（同一创建路径的 API 形态），仅当 CLI 不支持批量/非交互调用时才切换。

两者选一，不重复实现；具体选型在写开发计划（`write-dev-plan`）时按 CLI 是否支持脚本化调用来定。

**对拆任务阶段的硬性约定（评审建议落地）**：`write-dev-tasks` 产出的任务清单里，必须有一条独立任务是"阅读 `server/internal/service/builtin_skills/multica-creating-agents/SKILL.md` 与 `references/creating-agents-source-map.md`，确认 `multica agent create` 的完整参数面与校验规则，并把结论记入该任务的完成说明"——它是 `agent-frontmatter-adapter` 实现任务的**前置依赖**（先查证、后编码），不能默认开发时顺手就查到。若拆出的任务清单缺这一条，视为未对齐本 SDD。

## 4. 关键算法与流程

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

## 5. 技术选型与替代方案

| 决策点 | 选型 | 备选（未选） | 理由 |
|---|---|---|---|
| Agent 注册方式 | 复用 `multica agent create` CLI（或其 API） | 新写一段 Go 代码直接操作 `agent` 表 | Multica 已有创建路径且经过校验（字段约束、权限检查），绕开它自己写 INSERT 会重复造轮子且可能跳过既有校验；违反 `multica/CONTRIBUTING.AIFIRST.md` 规则四"优先复用上游已有抽象" |
| frontmatter 解析 | 参考 `server/internal/skill/frontmatter.go` 的实现方式扩展字段 | 引入新的 YAML/Markdown 解析库 | 项目已有同类解析代码，字段集小幅扩展（加 mode/permission）不构成新增依赖的理由 |
| `permission.bash: deny` 的处理 | M0 只记录不强制执行 | M0 就实现 execenv 层拦截 | execenv/controlled-shell 下沉是 P1-F5 明确排定的独立工作量（总 PRD §5.2.5），M0 提前做等于把 P1 的活拆进本 CR，违反 PRD §7 的范围排除约定 |
| tools 一致性 CI | 复用本仓库已验证过的 `check-skill-matrix.mjs` 思路，在 Multica fork 仓库接一份等价 CI | 重新设计一套校验规则 | 校验的 4 条不变式与本仓库 `dir-graph.yaml#agents.contract` 是同一件事，没有理由设计两套 |

## 6. FR 到技术实现映射

| FR | 技术方案 | 组件 |
|---|---|---|
| FR-1 | Docker Compose/Helm 配置改动：移除 Stripe 路由挂载、`mcn_` 凭据留空（中间件分支保留，天然 401，零代码改动）、`DISABLE_WORKSPACE_CREATION=true` | `selfhost-compose` |
| FR-2 | `agent-frontmatter-adapter` 脚本，见 §4 伪代码 | `agent-frontmatter-adapter` |
| FR-3 | 无新代码，用 FR-2 注册好的 Agent 做一次端到端冒烟 | `issue-dispatch-smoke` |
| FR-4 | Multica fork 仓库接入等价于 `tools/.github/workflows/check-skill-matrix.yml` 的 CI 步骤 | `tools-consistency-ci` |

## 7. 安全与性能考量

- **安全边界（诚实声明）**：M0 完成后，已注册的 9 个 Agent 尚未受 controlled-shell/execenv 白名单约束（那是 P1-F5）。这意味着 M0 阶段 Agent 理论上仍可执行任意 shell 命令——这不是本 CR 的疏漏，而是 PRD §7 明确排除的范围；**M0 验收通过不代表 Agent 执行是安全的，只代表"能跑通"**，这条边界必须在 M0 验收结论里同样写清楚，不能只写"通过"两个字。
- **幂等性**：`agent-frontmatter-adapter` 重复运行不应重复建行（§4 已设计按 name 查重跳过）；`issue-dispatch-smoke` 是一次性验收动作，不需要幂等设计。
- **性能**：9 个 Agent、一次 Issue 派发，量级微小，无需考虑并发/批量优化。

## 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-07-30 | v0.1.0 | Ray | 初始草稿；Agent 注册模型细节经 Explore 核对 Multica 源码（`server/pkg/db/generated/models.go` 的 `Agent` struct、`server/internal/skill/frontmatter.go`），未凭空假设字段 |
| 2026-07-30 | v0.1.1 | Ray | 采纳技术评审两条非阻塞建议：① §3 增加对拆任务阶段的硬性约定——"核对 multica agent create 参数"必须是独立任务且为适配器实现的前置依赖；② §2 mode/permission "读取不落库"补可验收口径（每 Agent 一行结构化日志，9 缺一即不过），拆任务时验收条件必须引用 |
