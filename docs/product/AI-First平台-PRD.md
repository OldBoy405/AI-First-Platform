# AI First 平台 · 产品需求文档（PRD）

| 项目 | 内容 |
|---|---|
| **文档名称** | AI First 平台 产品需求文档（PRD） |
| **版本** | v1.2（2026-07-29 修订：吸收《AI-First 研发协同平台》理念对比的 S1–S6 改进——知识消费层、超级个体协同层补全、交付效能度量、场景工坊、AI 行为审计、发布材料位置；2026-07-30 修订：Wiki 子系统落地设计——wiki-maintain 维护、wiki-first 问答、双信号知识晋升，详见《Wiki 子系统设计》；2026-08-07 修订：对照已落地代码核实追认——壳 Issue 设计废止（ADR-0001）、cr 投影表以事件账本为历史权威（ADR-0002）、状态数口径标注） |
| **编制日期** | 2026-07-28 |
| **产品定位** | 企业内部自托管的 AI 原生研发协同平台 |
| **底座** | Multica（fork，长期跟随上游） |
| **智能内核** | Claude（本机 CLI + Agent SDK） |
| **数据模型** | 方案 B（Issue / CR / TASK 两层） |
| **交付节奏** | 内部可用 ≈10–12 周 · 完整形态 ≈5–6 月 |
| **配套文档** | 《CodeBanana 产品解析报告》《Multica 架构解析》《P0 数据模型映射表》《P1 crctl 接入设计》《P2 三模式聊天交互设计》《P3 组织智能设计》《Wiki 子系统设计》《完整技术方案》《对比分析-AI-First研发协同理念与当前方案》 |

> **文档说明**：本 PRD 整合了从产品调研、竞品解析、五方组装论证、P0–P3 分阶段设计、Claude 接入到 runner 轻量档的全部讨论产出。所有技术事实均基于对 Multica 真实源码（396 个迁移文件）、tools 方法论包（9 个 Agent / 59 个 Skill / 8 条 Pipeline / crctl 1006 行）与 CodeBanana 产品快照（86 个 i18n 命名空间）的核对。

---

## 目录

- [1. 文档目的与范围](#1-文档目的与范围)
- [2. 产品解析](#2-产品解析)
  - [2.1 核心功能](#21-核心功能)
  - [2.2 目标用户](#22-目标用户)
  - [2.3 市场定位](#23-市场定位)
  - [2.4 价值主张](#24-价值主张)
  - [2.5 竞品对标：与 CodeBanana 的功能差异](#25-竞品对标与-codebanana-的功能差异)
- [3. 五方组装](#3-五方组装)
  - [3.1 组装总览与分工](#31-组装总览与分工)
  - [3.2 Multica 底座](#32-multica-底座)
  - [3.3 tools 方法论包](#33-tools-方法论包)
  - [3.4 OpenClaw 渠道生态](#34-openclaw-渠道生态)
  - [3.5 Claude 智能内核](#35-claude-智能内核)
  - [3.6 自研协作与治理层](#36-自研协作与治理层)
  - [3.7 组件接口与协作机制](#37-组件接口与协作机制)
- [4. 数据模型（方案 B）](#4-数据模型方案-b)
- [5. P0–P3 四份设计方案](#5-p0p3-四份设计方案)
  - [5.1 P0 地基](#51-p0-地基)
  - [5.2 P1 治理核心](#52-p1-治理核心)
  - [5.3 P2 协作体验](#53-p2-协作体验)
  - [5.4 P3 组织智能](#54-p3-组织智能)
- [6. Claude 接入方案](#6-claude-接入方案)
- [7. runner 轻量档方案](#7-runner-轻量档方案)
- [8. 非功能性需求](#8-非功能性需求)
- [9. 里程碑与开发计划](#9-里程碑与开发计划)
- [10. 人力配置](#10-人力配置)
- [11. 风险评估](#11-风险评估)
- [12. 验收标准](#12-验收标准)
- [13. 明确不做清单（范围边界）](#13-明确不做清单范围边界)
- [14. 术语表](#14-术语表)

---

## 1. 文档目的与范围

### 1.1 目的

本文档定义 AI First 平台的完整产品需求，作为研发、测试、运维团队的实现依据与验收基线。目标是把三份来源——CodeBanana 的协作体验、Multica 的本地执行底座、自研 tools 的工程治理方法论——整合为一个企业内部可自托管、隐私优先、工程可追溯的 AI 原生研发协同平台。

### 1.2 范围

**在范围内**：本地执行的 Agent 协作、CR 工程治理、三模式聊天、组织/项目/Issue 协作、AI 成熟度看板（含交付效能板块）、共享 runner 轻量档（含 LLM Wiki 知识问答）、场景工坊角色化视图、Skill Market（含资产元数据卡）、Claude 接入、IM 渠道、自托管部署。

**不在范围内**（详见 [第 13 章](#13-明确不做清单范围边界)）：云端沙箱 SaaS、Token 计费、多组织跨租户、runner 完整档（代码执行/预览/部署，观察后独立立项）、TicNote 硬件、记忆系统具体实现（仅预留 MCP 端点）。

### 1.3 三项已锁定决策

| 决策 | 结论 | 理由 |
|---|---|---|
| **Multica fork 策略** | 长期跟随上游 | 上游迭代快（3 个月 10.7k star），持续吸收 Agent 后端适配、渠道引擎、安全修复；按 `CUSTOM.md` 台账管理二开 |
| **CR 与 Issue 关系** | 两层（方案 B） | Issue = 统一轻量入口；CR = 可选治理信封；TASK = 子 Issue。协作原语免费复用，门禁复杂度封装在 CR 内 |
| **共享 runner 池规模** | 先上轻量档 | 只承载只读/文档 Agent，威胁面低、Token 省，覆盖非技术人员 60–70% 场景 |

---

## 2. 产品解析

### 2.1 核心功能

平台的核心功能可归纳为六大能力域：

#### 2.1.1 实时协作编程
- 团队在同一"项目容器"内协作，项目容器 = 专属 Agent + 群聊空间 + 执行环境的三位一体。
- 三模式群聊：Team Agent（共享 AI 执行层）、Private Ask（个人只读探索）、Discussion（人类沟通层 + DC 协调者）。
- 单一写者并发控制 + 50 槽 FIFO 共享队列，解决多人共用一个 AI 执行体的冲突问题。

#### 2.1.2 AI 作为自主队友
- 每个项目自带同名 Agent，作为一等成员参与执行、评审、协作。
- 9 个内置方法论 Agent（规划、需求、开发、评审、交付、竞品、知识、客服、spec 查询）覆盖需求→设计→编码→回写全流程。
- A2A 跨项目 Agent 协作；Discussion Coordinator（DC）路由协调。

#### 2.1.3 工程治理与可追溯（差异化核心）
- CR（变更请求）16 态门禁状态机（口径：15 个具名状态 + 注册前 (new)，见 CONTEXT.md），5 道质量门（需求/技术设计/测试证据/代码/规划评审）。
- traceability 五段链路：需求 FR ↔ 技术设计 SDD ↔ 交付 TASK ↔ 代码 merge SHA ↔ CR-ID。
- 漂移检测：基线对齐扫描 + 变更影响分析 + 绕过流程的直接提交（bypass-commit）探测。

#### 2.1.4 本地执行环境
- Agent 跑在用户本机 daemon 上，模型凭据与源码不出内网。
- execenv 每任务隔离 worktree；controlled-shell git 白名单网关；Dev Tools（Terminal/Service/Git/Deploy）。

#### 2.1.5 组织智能与度量
- AI 成熟度看板：五维九指标（AIF/SII/OFI/EPC/ACM）+ 治理板块。
- 周报 Autopilot 自动产出组织 AI 转型诊断。
- Skill Market：把个人工作流沉淀为可版本化、可发布的组织资产。

#### 2.1.6 全渠道接入
- Web 工作台、Electron 桌面端（本地自动化）、Expo/RN 移动端、IM 渠道（飞书/Slack/Telegram/Discord/企微/QQ/钉钉）、CLI、Webhook。

#### 2.1.7 知识层三分工（v1.1 增补，S1；Wiki 子系统详见《Wiki 子系统设计》）
- **事实生产**：Git 版本库负责可信、可审、可回滚的主事实源（specs/ delivery/ change-requests/），已由 2.1.3 治理能力承载。
- **知识消费（Wiki 子系统）**：① **维护**——`wiki-maintain` Skill（owner=knowledge-agent）在 daemon 本机生成并增量维护代码 Wiki（`wiki/` 衍生解释层：gitHead 差量、外科手术式更新、写白名单、确定性三段式校验）；② **查询**——Wiki 问答走 wiki-first 三层检索（wiki/ → 事实源原文 → 代码），回答强制带出处（文件路径+行号），P2.5 轻量档承载；治理事实（CR 状态/追溯/审批）直查投影表不经 Wiki 转述；探索型知识（竞品/访谈/纪要）落 `docs/research|notes|minutes` 目录契约，按 confirmed/source-backed/contested/watchlist 标注置信度。
- **知识晋升**：双信号源——同类问题被反复问到（≥3 次，问答日志）或 Wiki 生成时发现答不上（open-questions.md）→ 巡检自动开 Issue 建议回写事实源——"Git 负责让事实可信，Wiki 负责让知识好用"，缺口不停留在问答记录里。
- **关系索引（预留）**：知识图谱与记忆系统同走 MCP 预留端点，定位为**可删除、可重建的衍生索引**，永不作状态权威（详见第 13 章 N8）。**Wiki 即图谱的种子**：页面 frontmatter 是节点属性、正文概念链接是语义边，将来接图谱 MCP 时从 Wiki 解析即可重建全图，无需独立图数据库。

### 2.2 目标用户

| 用户角色 | 核心诉求 | 主要使用场景 |
|---|---|---|
| **技术负责人 / Tech Lead** | 团队 AI 协作、工程质量可控 | 配置项目 Agent、把关质量门、看治理看板 |
| **开发工程师** | AI 辅助全栈开发、可追溯变更 | Team Agent 编码、走 CR 流程、代码评审 |
| **产品经理** | 无门槛参与、需求可落地追溯 | 规划报告、提需求、审批、看进度 |
| **测试 / QA** | 测试证据入链、质量门参与 | 写测试报告、质量门评审 |
| **设计师** | 参与讨论、提供视觉参考 | Discussion 讨论、附件交流 |
| **客服** | 依据文档答疑、反馈落盘 | customer-support Agent 问答、记录未解决反馈 |
| **管理层** | 看到 AI 转型量化进度 | AI 成熟度看板、周报诊断 |
| **运维 / DevOps** | 内网自托管、可控成本 | 部署、runner 池运维、配额管理 |

**关键区分**：技术角色走本机 daemon（主路径）；非技术角色走共享 runner 轻量档参与只读/文档场景。

### 2.3 市场定位

- **不是**云端 SaaS 编程平台（区别于 CodeBanana 云端形态）。
- **是**企业内部自托管的 AI 原生研发协同平台。
- **定位坐标**：本地执行 × 工程治理 × 全员协作。在"AI 编程工具"与"研发管理平台"之间，以"AI 原生的工程可追溯"作为独特站位。
- **对标参照**：产品体验对标 CodeBanana，工程治理深度超越它；底座能力对标 Multica，协作与治理能力在其之上扩展。

### 2.4 价值主张

> **让非技术角色能参与、让 AI 大胆执行、让每一次变更都留下可追溯的证据链。**

| 价值维度 | 具体主张 | 差异化来源 |
|---|---|---|
| **隐私** | 模型凭据与源码不出内网，Agent 本地执行 | Multica 本地执行路线 |
| **可追溯** | 每次 AI 产出有证据链、过质量门、可回滚 | tools 治理方法论 |
| **包容** | 非技术角色经轻量档 runner 无门槛参与 | 共享 runner 池 |
| **智能** | Agent 作为自主队友，人类专注决策 | Claude + 9 内置 Agent |
| **组织** | AI 原生转型可量化、可诊断 | AI 成熟度看板 |
| **自主** | 内网两命令起全栈，不依赖外部 SaaS | Multica 自托管 |

### 2.5 竞品对标：与 CodeBanana 的功能差异

#### 2.5.1 我们多出的能力（差异化）

| 能力 | CodeBanana 现状 | 本平台 |
|---|---|---|
| CR 工程治理 | Approval Workflow 仅空壳内置项目 | 16 态状态机 + 5 道质量门 + crctl 强制执行 |
| 证据链与可追溯 | 无 | traceability 五段链路 + evidence digest + EVIDENCE_DRIFT 检测 |
| 漂移与影子工程检测 | 无 | review-alignment 周巡检 + bypass-commit 探测 |
| 看板 / Issue 协作 | 无看板 | 完整 Issue 体系（看板/子 Issue/依赖/订阅/收件箱/Squad） |
| 方法论资产 | Skill Market 空市场 | 开箱 9 Agent + 59 Skill + 8 Pipeline |
| 移动端 | 无 | Expo/RN 移动端 |
| CLI 与自托管 | 无 | multica CLI + Compose/Helm |

#### 2.5.2 放弃或降级的（本地执行路线的代价）

- 云端沙箱即开即用（非技术零安装参与）→ 靠共享 runner 池缓解，体验有差距。
- 平台托管 30+ 模型 + Auto 路由 → 模型列表 = 用户本机 CLI 可用模型。
- Token 计费/套餐/按量付费 → 内部版降级为用量展示。
- 多组织与 External 可见性 → 单组织。
- TicNote 硬件联动 → 不可复制。
- 多端实时预览 + 永久部署 URL → 预览在开发者本机，无平台托管 URL。

#### 2.5.3 同名但实现不同的

三模式聊天、Presenter 控制权、50 槽队列、IM 渠道、Cron 三形态、恢复检查点、AI 成熟度看板、Basic Info——功能面对齐原产品，但执行位置从云端沙箱换成本地 daemon，审批从"云端点一下"换成服务端签名 grant。

---

## 3. 五方组装

### 3.1 组装总览与分工

平台由五个来源组装而成，遵循"组装而非造轮子"的设计原则（Multica 上游自身也是这么做的——它已内建 OpenClaw 后端）。

| 来源 | 承担 | 集成方式 |
|---|---|---|
| **Multica（fork）** | Go 后端骨架、Issue/看板体系、任务队列与租约、pkg/agent 后端抽象、execenv、渠道引擎、令牌权限、WS 实时层、三端共享包、部署 | fork + 长期跟随上游 |
| **tools（本地包）** | 方法论层：9 Agent、59 Skill、8 Pipeline、CR 状态机、5 质量门、crctl、controlled-shell、traceability | 装入目标 workspace 的 `tools/` |
| **OpenClaw** | 补齐 IM 渠道插件、心跳守护范式、Markdown 记忆约定、A2A 协议 | Multica 上游同源，低摩擦 |
| **Claude** | Agent 智能内核：本机 CLI + Agent SDK + Anthropic API SDK | pkg/agent/claude.go 已接 |
| **自研** | 三模式聊天 UI、Presenter 状态机、Pipeline Runner、签名审批、组织治理、成熟度看板、Skill Market、runner 池、cr 投影同步 worker | 基于上述底座开发 |

### 3.2 Multica 底座

**技术栈**：Go 1.26 + Chi + sqlc + PostgreSQL 17；Next.js 16 前端；Electron 桌面端；Expo/RN 移动端；pnpm + Turborepo monorepo。

**核心可复用资产**：
- **pkg/agent 后端抽象**（66 文件，14 种 CLI）：统一 `Backend` 接口 `Execute(ctx, prompt, ExecOptions) (*Session, error)`，全部子进程包装器。`ExecOptions` 已归一化 Model / SystemPrompt / Timeout / ResumeSessionID（会话恢复）/ McpConfig / ThinkingLevel（effort）。
- **agent_task_queue 的原子 claim SQL**：`NOT EXISTS` 子句实现同 Agent 串行化、不同 Agent 并行，无需分布式锁。附带 `prepare_lease_expires_at`（准备租约）、`dispatched_at` CAS、claim_recovery（失联回收）。
- **令牌前缀分派**：`mat_`(任务) / `mul_`(PAT) / `mdt_`(daemon) / `mcn_`(云节点) / JWT 五类；任务令牌硬绑单一 workspace，`RequireHumanActor` 拒绝其访问审批端点。
- **实时系统**：两个独立 WS Hub（浏览器 Hub + daemon Hub），Redis Streams 8 分片扇出，作用域房间。
- **integrations**（~120 文件）：平台无关渠道引擎 + 飞书 WS 长连接 + Slack Socket Mode + Composio MCP。

### 3.3 tools 方法论包

**结构**：9 个 Agent（`agents/*.md`）+ 59 个 Skill（`skills/{domain}/{skill-id}/SKILL.md`）+ 8 条 Pipeline（`pipeline-templates/*.pipeline.json`）+ 权限矩阵（`agent-skill-matrix.yml`）+ 目录契约（`dir-graph.yaml`）。

**9 个 Agent**：product-planning-agent、requirement-writer、dev-agent、spec-agent、delivery-agent、quality-reviewer-agent、knowledge-agent、competitive-analyst-agent、customer-support-agent，加上系统编排器 system-orchestrator（承接 git/shell/状态写入等 21 个基础 Skill）。

**权限矩阵四关系**：`owns`（主责，每 Skill 唯一 owner）/ `can-call`（边界内可调）/ `external`（运行时提供的外部方法论）/ `forbidden`（明确禁止跨域越权）。以 actor 侧邻接表编码。

**crctl（核心执行器）**：单文件 `crctl.mjs`（1006 行，纯 Node ESM，零依赖），是唯一真正可执行的门禁引擎。命令面：`status / gate / advance / approve / validate / attempt / test / next / git`。单一事实源设计——状态机从 `dir-graph.yaml` 解析，passCondition 从 pipeline JSON 解析，gates.json 只声明证据映射，改声明不改代码。

**运行时依赖**：文件系统、git（含 worktree + 远端，多仓能力）、Node ≥18、交互式 TTY（审批，本方案改为签名审批替代）。

### 3.4 OpenClaw 渠道生态

补齐 Multica 未覆盖的 IM 平台（Telegram/Discord/企微/QQ/钉钉），提供心跳守护范式、Markdown 记忆文件约定、A2A 协议插件。因 Multica 上游已内建 OpenClaw 后端（`internal/daemon/execenv/openclaw_config.go`、`skills/shared/crctl/adapters` 亦引用 OpenClaw 命名），两者同源，集成摩擦低。

### 3.5 Claude 智能内核

四条接入路径（详见 [第 6 章](#6-claude-接入方案)）：
- **① Claude Code CLI**（主）：本机 Agent 执行，Multica `pkg/agent/claude.go` 已接。
- **② Claude Agent SDK**：共享 runner 池载体。
- **③ Anthropic API SDK**：平台内部轻量 LLM 功能。
- **④ Managed Agents**：不用（与本地执行前提冲突）。

### 3.6 自研协作与治理层

在底座之上自研的部分：
- 三模式聊天 UI（以 CodeBanana i18n 字典为功能清单）。
- Presenter 控制权状态机（复用 claim SQL 串行化，键换 project_id）。
- Pipeline Runner（补 tools 承认未实现的 P6）。
- 服务端签名审批（替代 crctl TTY 审批）。
- cr 投影同步 worker（git 权威 → PG 投影）。
- 组织/部门治理、AI 成熟度看板、Skill Market、runner 轻量档编排。

### 3.7 组件接口与协作机制

#### 3.7.1 关键接口定义

| 接口 | 提供方 → 消费方 | 契约 |
|---|---|---|
| **Agent 执行** | daemon → Claude CLI | `Execute(ctx, prompt, ExecOptions)`，NDJSON 流式返回六类 Message（text/thinking/tool-use/tool-result/status/error） |
| **CR 事件上报** | daemon → 服务端 | `POST /api/daemon/cr-events`（DaemonAuth 组），批量事件数组，幂等键 `cr_id+commit_sha+event_kind` |
| **签名审批下发** | 服务端 → daemon → crctl | grant JSON（Ed25519 签名 + evidence_digest）→ `crctl approve --grant` |
| **git 网关** | Agent → gitguard | 三元白名单（子命令 + 形态正则 + 调用者），`spawnSync(shell:false)` |
| **MCP 记忆** | Agent → 记忆服务 | `ExecOptions.McpConfig` 注入端点，三操作（写入/检索/反思） |
| **实时推送** | 服务端 → 客户端 | WS 作用域房间（workspace/user/task/chat） |

#### 3.7.2 协作机制

```
crctl advance/approve/git push（写 git + CAS）
        ↓ outbox 主通道 + [cr] commit 兜底通道
daemon 采集 → POST /api/daemon/cr-events
        ↓ 幂等去重
同步 worker → 更新 cr 投影 + issue.metadata + WS 推送
        ↑ reconcile 定时对账（漂移则重投影）
```

**权威铁律**：CR 状态权威在 git，PG 只读投影，服务端永不写 CR 状态。全表仅一处反向流动（PG→git）：pipeline runner 的 reviewLoop 轮次经 crctl 回写 `review-loop.yml`。

---

## 4. 数据模型（方案 B）

基于 Multica 真实 schema（396 迁移文件逐列核对）。方案 B 的直接收益是改动量极小。

### 4.1 改动量总览

| 类别 | 数量 | 内容 |
|---|---|---|
| **原样复用** | ≈30 张 | workspace(=组织)、issue 全家桶、agent_task_queue、chat_session、comment、daemon/runtime、channel/lark、autopilot/sys_cron、inbox_item、skill、squad |
| **改动** | 2 张 | `issue` 加 `cr_id TEXT`（部分唯一索引）；`agent_task_queue` 加 `cr_id` + `pipeline_node_run_id`（2026-08-07 核实修正：`issue.cr_id` 未落地且已废止，改由 `cr.shell_issue_id` 反向引用承担关联，见 ADR-0001；`agent_task_queue` 两列已由迁移 162 落地） |
| **新增** | 7 张 | cr、cr_sync_event、approval_record、pipeline_run、pipeline_node_run、spec_trace、department + maturity_snapshot（2026-08-07 核实：前 5 张已落地；cr 表落地列少于设计稿，checkpoint/merge 历史由 cr_sync_event 事件账本承载，见 ADR-0002；spec_trace/department/maturity_snapshot 属 P3，未落地） |

### 4.2 权威归属

| 数据 | git 权威 | PG 投影 |
|---|---|---|
| CR 生命周期 | `_backlog.yml` + `cr.md`（CAS 双写） | `cr` 表 |
| CR ≈ Issue | `cr.md#origin={type:issue,ref}` | ~~`issue.cr_id`（唯一索引）+ 壳 Issue~~ **已废止**（ADR-0001）：改为 `cr.shell_issue_id`（CR 关联 Issue，crsync 从 origin 回填） |
| TASK 子任务 | `tasks/TASK-NN.md` | 子 Issue（`parent_issue_id` = CR 壳 Issue）（锚点随壳 Issue 废止悬置，未实施，见 P0 §3.5） |
| 16 态 → 7 态看板 | 状态机权威 | ~~`issue.metadata.cr_status_bucket`（禁拖拽 CR 壳）~~ **已废止**（ADR-0001）：CR 状态呈现走聊天窗口门禁徽标 |
| 可追溯 | `specs/{id}/traceability.yml` | `spec_trace` |

### 4.3 CR 16 态 → Issue 7 态映射

> 2026-08-07：本节属已废止的壳 Issue 三件套（ADR-0001），从未实施，保留作历史设计记录；详见《P0 数据模型映射表》§4.1。

| CR 状态 | Issue status |
|---|---|
| drafting / requirement-reviewing | todo |
| requirement-approved ~ developing | in_progress |
| code-reviewing / code-approved / merging / writing-back | in_review |
| archived | done |
| rejected / withdrawn | cancelled |

**双编号并存**：`CR-2026-001`（git 自增权威）与 `AIF-42`（PG 计数器权威）不统一——合并两个自增源需分布式协调，收益为零。

---

## 5. P0–P3 四份设计方案

### 5.1 P0 地基

**优先级**：P0（必做，阻塞后续一切）
**周期**：3–4 周
**目标**：把三份来源在本地跑成一个可派任务的最小闭环。

#### 5.1.1 技术架构
- fork Multica → `custom/main`；建立 upstream 镜像与双周同步流程。
- 剥离计费/云节点/多 workspace 注册（环境变量关闭）。
- Agent 注册表替换为 tools 9 Agent（写 frontmatter 适配器）。

#### 5.1.2 实现路径
1. **fork 与剥离**：`make selfhost` 内网跑通；摘除 Stripe 路由；`mcn_` 配置为空天然 401。
2. **Agent 注册表替换**：frontmatter 适配器（`mode:primary/subagent` + `permission` → 目标格式；`{domain}/{skill-id}` 两级目录发现）；导入 9 Agent + 59 Skill + project_resource。
3. **tools 一致性修复**：修 8 项内部不一致（2 Agent 缺 name、CLAUDE.MD 读取顺序漏 matrix、knowledge-agent 陈旧路径、2 Agent owns 为空等）；把 `dir-graph.yaml#agents.contract` 4 条不变式写成 CI 校验。
4. **数据模型 P0 迁移**：2 条 ALTER + 5 张新表 CREATE，过 Multica 迁移运行器（advisory lock）。
5. **Claude CLI 接入验证**：确认 `pkg/agent/claude.go` 拉起 `claude --output-format stream-json`；`ExecOptions` 映射通。

#### 5.1.3 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| P0-F1 | 内网 Docker Compose 起全栈 | P0 |
| P0-F2 | 9 个 tools Agent 注册为可用 | P0 |
| P0-F3 | 给 Agent 派 Issue，daemon 领取并本机执行 | P0 |
| P0-F4 | tools 一致性 CI 校验通过 | P0 |

#### 5.1.4 预期效果 / 验收（M0）
给一个 Agent 派 Issue，daemon 领取并在本机跑完；一致性 CI 绿。

---

### 5.2 P1 治理核心

**优先级**：P1（必做，产品差异化所在）
**周期**：6–8 周
**目标**：CR 门禁 + 质量门 + 追溯链在本地执行下强制生效。

#### 5.2.1 技术架构
- crctl 保持状态权威（git），Postgres 做只读投影。
- 同步走三层防漏通道：outbox 主 + commit 扫描兜底 + reconcile 对账安全网。
- 签名审批替代 TTY；controlled-shell 下沉 daemon execenv。

#### 5.2.2 实现路径
1. **crctl outbox**：advance/approve/git push 三挂点原子写 `.crctl/outbox/*.json`（断网积压、上线补传）。
2. **daemon 采集 + worker**：`POST /api/daemon/cr-events`；双通道幂等合并；worker 更新 cr 投影 + issue.metadata + WS 推送；reconcile 定时对账。
3. **Pipeline Runner**：线性 nodes + reviewLoop 回边 + 3 kind；passCondition（equals/isEmpty）解释器；prompt 自然语言条件提升为显式 `when`；持久化 pipeline_run/pipeline_node_run。
4. **签名审批**：服务端 Ed25519 签发 grant（evidence_digest）；crctl 加 `--grant` 分支跳 TTY；gate + validate 扩展承认 `via:server-approve` + 每次重算 digest；RequireHumanActor 拒任务令牌。
5. **controlled-shell 下沉**：抽 `rules.json` 单一事实源；Go `pkg/gitguard`（三元白名单移植）；execenv 四改（PATH shim、daemon 自身走 gitguard、per-task 物化 Claude Code hooks、`--disallowedTools Bash`）。
6. **AI 行为审计**（v1.1 增补，S5）：gitguard 拒绝事件计数上报（落 activity_log，供治理板块"越权尝试次数"）；工具调用摘要持久化（工具名/目标路径/结果码，不含正文）——补全五类质量门中"AI 行为门"的留证一半。详见《P1 crctl 接入设计》§C.5。
7. **发布材料位置**（v1.1 增补，S6）：`delivery/release/` 目录契约（发布记录 + 检查单）；writeback pipeline 补"发布材料回写"节点声明——测试→发布段在事实源中获得一等公民位置。详见《P0 数据模型映射表》§6.1。

#### 5.2.3 CR 状态机（权威定义）

16 态主链 + 3 终态，23 条转移（2026-08-07 口径修正：按 AGENTS.md 工程纪律 2 与 tools 仓当前声明，状态机 = 15 个具名状态 + 注册前 (new)（口语「16 态」含 (new)），转移 = 25 条声明、wildcard 展开后 47 条；以 `../tools/dir-graph.yaml#change-request-track.state_machine` 为唯一事实源）：
```
drafting → requirement-reviewing → requirement-approved
  → tech-designing → tech-design-review-pending → tech-design-reviewed
  → task-breakdown → developing → code-reviewing → code-approved
  → merging → writing-back → archived
终态：archived | rejected | withdrawn
```

trigger 字符串编码回退语义（如 `approve-code:reject -> implement-code`），必须精确匹配。

#### 5.2.4 五道质量门

| 门 | Skill | 必读 | 必产出 |
|---|---|---|---|
| 需求质量门 | review-requirement | prd.md + 规划 source | review-annotations/requirement.yml |
| 技术设计质量门 | review-tech-design | prd.md + sdd.md | review-annotations/sdd.yml |
| 测试证据门 | write-test-report | TASK 验收条件 + 验证输出 | test-report.md |
| 代码质量门 | review-code | 真实 diff + TASK + SDD + test-report | review-annotations/code.yml |
| 规划评审门 | review-planning-report | 规划报告 | approved + blockers[] |

**硬约束**：仅有 diff stat、commit log 或口头测试结论不足以通过代码质量门。

#### 5.2.5 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| P1-F1 | CR 事件从 git 同步到 PG 投影（三通道 + 幂等） | P1 |
| P1-F2 | Pipeline Runner 跑通四条主 pipeline | P1 |
| P1-F3 | 服务端签名审批（无 TTY 环境可用） | P1 |
| P1-F4 | gate 每次重算 evidence digest（EVIDENCE_DRIFT 检测） | P1 |
| P1-F5 | controlled-shell 白名单下沉 daemon | P1 |
| P1-F6 | AI 行为审计：越权拦截计数 + 工具调用摘要持久化 | P1 |

#### 5.2.6 预期效果 / 验收（M1 · 内部可用）
一条需求走完 `/requirement→/architecture→/coding→/writeback` 产出完整 traceability；无 TTY 环境 grant 审批走通；批后篡改证据触发 EVIDENCE_DRIFT；任务内 `git push --force` 报 FORBIDDEN_SUBCOMMAND。

---

### 5.3 P2 协作体验

**优先级**：P2（团队日常协作，M2 交付）
**周期**：6–8 周
**目标**：团队在平台内完成日常协作，不再靠 IDE 各自为战。

#### 5.3.1 技术架构
- 三模式聊天以 CodeBanana i18n 字典（86 命名空间，shadowchat 646 键）为功能清单。
- Presenter 复用 claim SQL 串行化，键换 project_id。
- A2A 与 Team Agent 共用 50 槽 FIFO 队列语义。

#### 5.3.2 三模式对照

| 维度 | Team Agent | Private Ask | Discussion |
|---|---|---|---|
| 定位 | 共享 AI 执行层 | 个人只读探索 | 人类沟通层（+DC） |
| 并发 | 单一写者 | 用户级独立队列 | 全员自由 |
| 后端 | agent_task_queue | chat_session（沙箱） | comment |
| WS 房间 | workspace+task | chat（仅本人） | workspace |

#### 5.3.3 实现路径
1. **三模式聊天 UI**：Team Agent/Private Ask/Discussion tab；toolExecutionCard 消费六类 Message 流；输入区差异化能力；模型列表来自 daemon 上报 Runtime。
2. **Presenter 控制权**：6 态通知（申请/批准/撤销/转让/释放）；Admin 空闲接管。
3. **门禁接合聊天**：pipeline 任务在消息流渲染审批卡 + blocker 列表 + reviewLoop attempt + CR 16 态徽标。
4. **A2A 跨项目**：成员面板 Add Agent；`@agent` 派单；A2A 记录面板。
5. **IM 渠道**：Multica 飞书长连接 + Slack Socket Mode；OpenClaw 补其余；1 Bot:1 Project 绑定。
6. **恢复检查点**：三态回滚（worktree git 快照 + 消息树截断 + session 版本）。
7. **斜杠命令入口**（v1.1 增补，S4）：输入框 `/` 唤起命令面板（`/需求`、`/评审摘要`、`/进度`、`/工作流`），映射既有 Pipeline 触发与查询 API，不新增执行通路——补齐资源四分类中的 Command 层，高频动作对全员一键可达。详见《P2 三模式聊天交互设计》§6.1。
8. **导出为 Skill 草稿**（v1.1 增补，S2）：Team Agent 会话多选（含工具调用序列）→ 生成 SKILL.md 草稿入私有技能库——过程记录到资产沉淀之间的那一跳。详见《P2 三模式聊天交互设计》§7。

#### 5.3.4 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| P2-F1 | 三模式聊天切换（保留各自草稿） | P2 |
| P2-F2 | Presenter 控制权状态机 | P2 |
| P2-F3 | 工具执行卡（toolExecutionCard）实时渲染 | P2 |
| P2-F4 | A2A 跨项目派单 + 队列 | P2 |
| P2-F5 | 7 平台 IM 渠道接入 | P2 |
| P2-F6 | 恢复检查点三态回滚 | P2 |
| P2-F7 | 斜杠命令面板（Command 层，映射 Pipeline API） | P2 |
| P2-F8 | 会话多选导出 Skill 草稿 | P2 |

#### 5.3.5 预期效果 / 验收（M2）
团队在平台完成一轮真实协作（讨论→转执行→审批→归档）；三模式切换保留草稿；恢复检查点三态一致。

---

### 5.4 P3 组织智能

**优先级**：P3（管理层价值，M3 交付）
**周期**：4–6 周
**目标**：管理层看到 AI 原生转型量化进度；追溯与漂移可查。

#### 5.4.1 技术架构
- P3 不采集新数据，只做 P0–P2 已有结构化行的读侧聚合。
- 度量任务挂 sys_cron_executions；照抄 task_usage_rollup 的水位线增量模式。

#### 5.4.2 五维十指标 + 两个护栏板块

| 维度 | 子指标 | 数据源 |
|---|---|---|
| AIF · AI First | Token 强度 / AI 渗透率 / AI 效率系数 | task_usage_daily + member + cr |
| SII · 超级个体 | 超级个体占比 / 人均 CR 吞吐 / **资产复用率**（v1.1 增补：发布的 Skill 被他人使用） | cr.owners + cr_sync_event + skill_usage_event |
| OFI · 组织扁平化 | 项目协作规模 / 项目活跃率 | cr.owners + comment + agent_task_queue |
| EPC · 原型直出 | 原型直出率 / 规划转化率 | pipeline_node_run(attempt) |
| ACM · Agent 协作 | Team Agent 使用深度 / 流程完整率 / Cron·A2A 采用 | agent_task_queue + pipeline_run |

**治理板块**（不进总分，单列）：门禁一次通过率、EVIDENCE_DRIFT 次数、追溯完整率、审批时延 P50/P90、越权尝试次数（v1.1 增补，数据源 P1 行为审计）。

**交付效能板块**（v1.1 增补，S3；不进总分，单列）：CR Lead Time P50/P90（cr_sync_event 时间戳）、Review 负担（reviewLoop 平均 attempt）、变更失败率（归档后 14 天内同 spec fix 类 CR 占比）——治理板块回答"守不守规矩"，本板块回答"交付有没有变好"，全部从既有表计算。看板顶部以 **AI 净价值**（时间+质量+知识+风险四收益−成本）为叙事框架组织上述指标，只改信息架构不加数据管道。

#### 5.4.3 实现路径
1. **成熟度看板**：department 表 + maturity_snapshot + maturity-config.yaml（公式/权重版本化）；个人排名默认关闭。
2. **周报 Autopilot**：Org Admin Workspace 内置项目挂周 Autopilot，读 snapshot 生成诊断落 `docs/org-admin/`。
3. **追溯查询 + 漂移**：spec_trace 投影（加 trace 事件走 outbox 通道）；review-alignment 周巡检 + change-impact-analysis + bypass-commit 探测 → drift_finding。
4. **Skill Market**：skill 加 visibility/version/owner_actor；skill_usage_event 排行；发布门禁；builtin 不可编辑。**v1.1 增补（S2）**：资产元数据卡 4 必填字段（适用场景/依赖上下文/权限声明/失败处理）进发布门禁；"发布 = 授权"明示 + 敏感信息扫描。
5. **场景工坊**（v1.1 增补，S4）：需求工坊（PM：我的 CR + 待审批）、质量中心（QA：治理指标 + blocker + drift 流）、效能驾驶舱（=成熟度看板）三个 route 级角色化视图；同数据不同投影，读侧 + 入口，写操作跳既有交互。开发工坊 = 三模式聊天本身，不重做。
6. **知识晋升巡检**（v1.1 增补，S1；2026-07-30 扩为双信号）：信号一 = Wiki 问答日志（只记问题与命中路径）语义聚类，同类问题 ≥3 次；信号二 = `wiki/open-questions.md` 的 Active 条目（Wiki 生成时发现的缺口）→ 两路汇总自动开 Issue 建议回写事实源——事实源 → 消费 → 晋升的知识回路闭环。
7. **代码 Wiki 维护**（2026-07-30 增补，详见《Wiki 子系统设计》）：`wiki-maintain` Skill + Autopilot 定时增量维护（daemon 侧 gitHead no-op 门槛，无新 commit 零 token）；写白名单（execenv 工具层只放行 `wiki/**`）+ 确定性三段式校验（frontmatter 迁移 / 写后即时校验回注 / mermaid 降级 + index 确定性生成）。

#### 5.4.4 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| P3-F1 | AI 成熟度看板五维十指标 + 治理板块 | P3 |
| P3-F2 | 周报 Autopilot 自动诊断（按 AI 净价值四收益一成本框架） | P3 |
| P3-F3 | 追溯查询（FR 一跳到 merge SHA + 测试证据） | P3 |
| P3-F4 | 漂移巡检 + bypass-commit 探测 | P3 |
| P3-F5 | Skill Market 发布/版本/排行 + 元数据卡 + 发布授权与敏感扫描 | P3 |
| P3-F6 | 交付效能板块（Lead Time / Review 负担 / 变更失败率）+ AI 净价值叙事条 | P3 |
| P3-F7 | 场景工坊三视图（需求工坊 / 质量中心 / 效能驾驶舱） | P3 |
| P3-F8 | 知识晋升巡检（高频问答 + open-questions 双信号 → 建议回写 Issue） | P3 |
| P3-F9 | 代码 Wiki 增量维护（wiki-maintain Skill + Autopilot + 写白名单 + 确定性校验） | P3 |

#### 5.4.5 预期效果 / 验收（M3 · 完整形态）
连续 3 天快照；看板数量指标与质量护栏同屏；人为 PRD 改动不改 SDD → 周扫描出 alignment-drift；直接向 trunk 提交 → bypass-commit 进治理板块。**v1.1 增补**：他人使用某成员 Skill 后其资产复用率变化；缺元数据卡字段的 org 发布被拒；PM 在需求工坊一键达待审批；重复提问 3 次触发知识晋升 Issue。增补项约 +3–4 周（场景工坊可与看板前端并行），P3 周期相应放宽为 5–7 周或将工坊/晋升列为 P3.5 尾批。

---

## 6. Claude 接入方案

### 6.1 四路径总览

| 路径 | 形态 | 用途 | 凭据 |
|---|---|---|---|
| **① Claude Code CLI** | 本地 CLI 子进程 | 开发者本机 Agent 执行，覆盖 90% 流量 | 用户本人订阅 |
| **② Claude Agent SDK** | Claude Code 打包成库 | 共享 runner 池载体（Personal Agent/customer-support/DC/周报） | 组织 API Key |
| **③ Anthropic API SDK** | 单次调用/Tool Runner | 平台内部轻量 LLM（聊天标题/看板建议/敏感判定） | 组织 API Key |
| **④ Managed Agents** | Anthropic 托管循环+沙箱 | 不用（与本地执行前提冲突） | — |

**推荐组合**：① 为主 + ② runner 池与内置 Agent + ③ 零散内部功能。④ 不用。

### 6.2 技术方案

#### 6.2.1 路径①（主）
Multica `pkg/agent/claude.go` 已接：daemon 拉起 `claude --output-format stream-json` 解析 NDJSON。`ExecOptions` 已映射：
- `Model`（模型选择）
- `SystemPrompt`（系统提示）
- `ResumeSessionID`（会话恢复，支持多轮上下文）
- `McpConfig`（MCP 记忆端点注入通道）
- `ThinkingLevel`（effort：low→max 五档）

平台不感知 CLI 版本——跟随用户本机安装的 Claude Code。

#### 6.2.2 路径②③（服务端）
服务器端直连默认 `claude-opus-5`（$5/$25 每百万 token，1M 上下文，思维默认开启，`output_config.effort` 调深度）。路径②用 Claude Agent SDK 的 `query(prompt, options)`，可注入 hooks 做 gitguard 拦截；路径③用 Anthropic API SDK 的 Messages API / Tool Runner。

### 6.3 数据流

```
[路径①] 用户本机：daemon → claude CLI（本人订阅）→ NDJSON 流 → WS → toolExecutionCard
[路径②] runner 池：Agent SDK query() → 组织 Key → 结果回传 → 用量按用户归因上报
[路径③] 平台内部：Messages API → 组织 Key → 聊天标题/看板建议
```

### 6.4 安全考虑

1. **凭据两本账**：开发者流量走本人订阅（隐私边界严格成立），平台侧流量（runner 池 + 内部功能）走组织 Key。看板用量必须分列统计。
2. **组织 Key 保护**：路径②③的组织 Key 是高价值目标——不明文进容器，经代理注入或短时签发。
3. **Tool Runner ≠ Agent SDK**：路径②需要完整 harness（Agent SDK）；路径③单功能用 Tool Runner 或裸 Messages API 即可。
4. **MCP 记忆天然可用**：路径①②原生消费 MCP，`ExecOptions.McpConfig` 通道已存在，记忆端点接上即可，无需为 Claude 特殊适配。
5. **版本漂移防护**：路径①平台不感知版本；服务端直连用 claude-api 规范核对，封装薄适配层。

---

## 7. runner 轻量档方案

### 7.1 设计定位

共享 runner 池只承载**只读与文档类 Agent**——无代码执行、无预览、威胁面低、Token 省。覆盖非技术人员 60–70% 的参与场景。完整档（代码执行/预览/部署）观察 1–2 月真实用量后再评估，作为独立 P2.5+ 轨道，不阻塞主线。

### 7.2 承载范围

| 承载（轻量档） | 不承载（留完整档） |
|---|---|
| customer-support 问答 | dev-agent 代码执行 |
| spec-query / spec-show 查询 | 端口预览 |
| **LLM Wiki 知识问答**（v1.1 增补，S1：wiki-first 三层检索——wiki/ → 事实源原文 → 代码，回答强制带出处；治理事实直查投影表分流；问答日志落 wiki_query_log 供 P3 知识晋升巡检。详见《Wiki 子系统设计》§4） | 一键部署 |
| 规划草稿（planning-draft） | implement-code |
| Discussion 的 DC 协调者 | 任何写 worktree 的 Coding 模式 |
| 审批操作 | — |
| Personal Agent 只读应答 | — |

### 7.3 设计与部署策略

- **载体**：Claude Agent SDK（可编程、可注入 hooks）。
- **凭据**：组织 API Key 经代理注入或短时签发，不明文进节点；用量按用户归因上报（供看板分列）。
- **配额**：接 P3 配额与余量预警（≤10% 通知）；非技术用户入口引导。
- **部署**：与 P2 并行的 P2.5 轨道（≈3 周），DevOps 主导。

### 7.4 性能指标与资源占用

| 指标 | 轻量档目标 |
|---|---|
| 单会话资源 | 低（只读/文档，无构建链、无代码执行） |
| 并发模型 | 复用 Multica claim 队列调度 |
| 威胁面 | 低（无写权限、无 shell、无越权风险） |
| Token 成本 | 低（只读/文档 Agent 输出短） |
| 冷启动 | 无容器隔离要求，快 |

**成本估算参照**（若未来扩全员）：轻度使用约 $10–30/活跃用户/月，重度可达 $50+。100 用户 30% 月活约 $500–2000/月起步——故轻量档只跑省 Token 的 Agent，且配额预警先行。

### 7.5 判断上完整档的标准
轻量档运行期间，非技术用户"想让 Agent 直接建页面/工具给我看"的请求频率。零星几次 → 让技术同事代跑更便宜；日常高频 → 才值得花 9–13 周和每月四位数美元建完整档（届时已有真实用量数据做容量规划）。

**注**：完整档的额外代价——威胁模型从"防模型"升级为"防租户"（多用户共享主机需真容器隔离）、9–13 周工程量、每月四位数美元账单、从桌面软件变成内部 PaaS 的运维性质变化。

---

## 8. 非功能性需求

| 类别 | 需求 |
|---|---|
| **隐私** | 模型凭据与源码不出内网；开发者流量走本人订阅 |
| **安全** | 五类令牌前缀分派；任务令牌硬绑 workspace + RequireHumanActor；gitguard 白名单；签名审批不可伪造；输出脱敏（pkg/redact） |
| **可用性** | daemon WS 断连不影响正确性（唤醒是提示，领取走 HTTP claim + 轮询兜底） |
| **一致性** | git 权威 + PG 投影；幂等去重 + reconcile 对账；仅一处反向流动 |
| **可部署** | Docker Compose / Helm 内网两命令起全栈；端口默认绑 127.0.0.1 |
| **可维护** | 上游双周同步；CUSTOM.md 台账；治理层做成新增文件/表降低合并冲突 |
| **国际化** | 中英双语（CodeBanana i18n 字典已备） |
| **可观测** | WS 作用域房间；Prometheus 指标；活动日志；AI 成熟度看板 |

---

## 9. 里程碑与开发计划

### 9.1 里程碑

| 里程碑 | 时点（2026-08 起） | 交付标志 |
|---|---|---|
| **M0 地基就绪** | 第 4 周（≈8/28） | 派 Issue 本机跑完；9 Agent 注册；一致性 CI 通过 |
| **M1 内部可用** | 第 12 周（≈10/26） | 一条需求走完四主 pipeline + 完整 traceability；签名审批跑通 |
| **M2 协作体验** | 第 20 周（≈12/21） | 三模式聊天 + Presenter + A2A + IM 渠道；团队日常协作 |
| **M3 完整形态** | 第 26 周（≈次年 2/1） | 成熟度看板 + 追溯查询 + 漂移检测 + runner 轻量档 |

### 9.2 阶段周期

| 阶段 | 周期 | 说明 |
|---|---|---|
| P0 地基 | 3–4 周 | 阻塞后续 |
| P1 治理核心 | 6–8 周 | 差异化所在 |
| P2 协作体验 | 6–8 周 | M2 |
| P2.5 runner 轻量档 | ≈3 周 | 与 P2 并行 |
| P3 组织智能 | 4–6 周 | M3 |
| 上游同步 | 贯穿 | 双周 merge |

---

## 10. 人力配置

| 角色 | 人数 | 主要职责 | 关键阶段 |
|---|---|---|---|
| 技术负责人 / 架构师 | 1 | fork 治理、权威边界把关、五方组装决策、上游同步评审 | 全程 |
| Go 后端 | 2 | Multica fork 改造、cr 投影同步 worker、gitguard、Pipeline Runner 宿主、签名审批 API | P0–P1 重 |
| 前端 | 2 | Next.js Web、三模式聊天 UI、Presenter 状态机、看板、Electron 桌面端 | P2–P3 重 |
| 全栈 / 方法论集成 | 1 | tools 集成、frontmatter 适配器、crctl 接入、Pipeline JSON 落地、一致性 CI | P0–P1 重 |
| DevOps / 基础设施 | 1 | 自托管、runner 轻量档池编排、短时凭据、CI/CD、上游镜像 | P2.5 重 |
| QA | 1 | 端到端验证、门禁/回滚/越权测试、验收清单执行 | P1 起 |
| PM（兼） | 0.5 | 需求节奏、用量观察（决定 runner 完整档时机） | 全程 |

**核心 6–8 人**。峰值在 P1（后端 + 方法论集成）与 P2（前端）。

---

## 11. 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|---|---|---|---|
| 上游 Multica 大重构导致合并冲突激增 | 中 | 高 | 治理层做成新增文件/表；双周同步及时消化；CUSTOM.md 台账；通用增强回馈 PR |
| 权威 split-brain：git 与 PG 状态不一致 | 中 | 高 | 铁律"服务端永不写 CR 状态"；幂等去重；reconcile 对账自愈；乱序事件标 needs_reconcile |
| tools 是 OpenCode 风格 + 8 项内部不一致 | 高 | 中 | P0 先做 frontmatter 适配器 + 修复不一致 + agents.contract 4 不变式接 CI |
| Pipeline 条件分支写在自然语言 prompt 里 | 高 | 中 | Runner 支持显式 when 字段；pipeline JSON 逐步补写；过渡期交模型处理 |
| 非技术角色参与被本地执行削弱 | 高 | 中 | runner 轻量档覆盖只读/文档（60–70%）；重度需求观察后再上完整档 |
| runner 池组织 API Key 成本失控 | 中 | 中 | 轻量档只跑省 Token 的只读/文档 Agent；P3 配额预警先行；用量分列监控 |
| runner 池多用户越权（提示注入读他人数据） | 低 | 高 | 轻量档无代码执行/写权限，威胁面天然低；短时凭据不明文进容器；完整档才需真容器隔离 |
| 签名审批被绕过 / 弱化人在环 | 低 | 高 | Ed25519 服务端签发不可伪造；gate 每次重算 digest；RequireHumanActor 拒任务令牌 |
| Claude API 版本漂移 | 中 | 低 | 本机 CLI 路径平台不感知版本；服务端直连核对规范；封装薄适配层 |
| 治理强度上限 = "证据的形状" | — | — | 明示诚实边界：crctl 只校验证据存在与形状不校验真伪；审批保证有人按键不保证认真看。产品文案不夸大 |

---

## 12. 验收标准

### 12.1 整体验收基线

| ID | 验收项 | 对应里程碑 |
|---|---|---|
| A1 | 内网自托管两命令起全栈 | M0 |
| A2 | 一条需求端到端走完四主 pipeline + 完整 traceability | M1 |
| A3 | 签名审批不可绕过、批后改证据即失效（EVIDENCE_DRIFT） | M1 |
| A4 | Agent 拿不到裸 shell（gitguard 生效，`git push --force` 报错） | M1 |
| A5 | CR 状态 git↔PG 投影一致、篡改自愈 | M1 |
| A6 | 三模式协作 + Presenter 跑通 | M2 |
| A7 | 非技术用户经轻量档 runner 参与（含 LLM Wiki 带出处问答） | M2.5 |
| A8 | 成熟度看板 + 漂移检测上线 | M3 |
| A9 | 交付效能与资产复用可见：Lead Time / Review 负担 / 变更失败率三卡可下钻；资产复用率随他人使用变化（v1.1，S2/S3） | M3 |
| A10 | **价值复盘**：M3 上线满 3 个月，按四类指标（个人效率 / 团队交付 / 知识复利 / 风险收益）产出季度复盘报告——回答"平台值不值"，而不止"功能跑没跑通"（v1.1，S3） | M3 + 3 个月 |

### 12.2 分阶段验收（详见各设计方案末节）
- **M0**：派 Issue 本机跑完；一致性 CI 绿。
- **M1**：需求走完四 pipeline；grant 审批走通；证据篡改触发 EVIDENCE_DRIFT；越权 git 被拦。
- **M2**：真实协作一轮（讨论→执行→审批→归档）；草稿保留；回滚三态一致。
- **M3**：连续 3 天快照；数量指标与质量护栏同屏；人为漂移被周扫描发现；bypass-commit 进治理板块。

---

## 13. 明确不做清单（范围边界）

| ID | 不做项 | 说明 |
|---|---|---|
| N1 | 云端沙箱 SaaS 与 Token 计费 | 走本地执行路线，内部版降级为用量展示 |
| N2 | runner 完整档（代码执行/预览/部署） | 观察 1–2 月真实用量后独立立项 |
| N3 | 多组织与 External 跨组织可见性 | 单组织 |
| N4 | 多供应商 Auto 模型路由 | 组织 Key 只有 Claude |
| N5 | TicNote 硬件联动 | 依赖自有硬件，不可复制 |
| N6 | 指标实时化 | 日粒度足够，实时化复杂度翻倍价值为零 |
| N7 | Skill 付费/积分机制 | 内部资产，流通靠可见性与排行 |
| N8 | 记忆系统具体实现 | 仅预留 MCP 端点 |

**记忆系统预留边界（重要）**：只定 MCP 接口契约——通过 `ExecOptions.McpConfig` 注入端点，约定写入/检索/反思三操作。**钉死边界：记忆层只做非结构化召回，结构化事实一律留在 specs/traceability，记忆永不作为状态权威**——否则 crctl 单一事实源设计作废。将来接 GBrain/Zep/Mem0 皆可，无需改 Claude 侧。

**知识图谱同走此预留（v1.1 增补，S1）**：本地知识图谱定位为"关系索引与上下文装配"，与记忆系统共用 MCP 端点契约，并追加两条安全条款——**索引可删除、可重建**（衍生数据：不备份、不跨用户共享、删除后可从事实源全量重建）；图谱只回答"哪些文件/实体相关"，AI 先查关系、再读最相关的事实源原文，图谱内容本身不作为回答依据。文档与源码是事实源，图谱永远是索引。

---

## 14. 术语表

| 术语 | 含义 |
|---|---|
| **CR（Change Request）** | 变更请求，工程治理的"信封"，含 16 态门禁状态机（口径：15 个具名状态 + 注册前 (new)，见 CONTEXT.md） |
| **Issue** | 统一工作入口，万物先是 Issue（反馈/杂事/咨询）；「CR 壳 Issue」概念已废止（ADR-0001），CR 经 `cr.shell_issue_id` 关联既有 Issue |
| **TASK** | CR 的 git 侧子任务（tasks/TASK-NN.md）；子 Issue 投影锚点随壳 Issue 废止悬置，未实施 |
| **crctl** | tools 的门禁引擎（1006 行零依赖 Node CLI），状态权威执行器 |
| **traceability** | 五段可追溯链路：FR ↔ SDD ↔ TASK ↔ merge SHA ↔ CR-ID |
| **daemon** | 用户本机的 Agent 运行守护进程 |
| **execenv** | daemon 的每任务隔离执行环境 |
| **Team Agent / Private Ask / Discussion** | 三种聊天模式：共享执行 / 个人只读 / 人类沟通 |
| **DC（Discussion Coordinator）** | Discussion 内的协调者 Agent，只协调不执行 |
| **A2A** | Agent-to-Agent 跨项目协作 |
| **Presenter** | Team Agent 的单一写者控制权 |
| **Pipeline** | tools 的工作流编排（8 条：规划/需求/架构/编码/回写等） |
| **reviewLoop** | Pipeline 的自修复回路（评审 block → 回修复节点重放） |
| **gitguard** | controlled-shell 白名单的 Go 移植（git 网关） |
| **EVIDENCE_DRIFT** | 审批后证据被篡改的检测错误码 |
| **bypass-commit** | 绕过 CR 流程直接提交 trunk 的"影子工程"探测 |
| **AIF/SII/OFI/EPC/ACM** | AI 成熟度看板五维：AI First / 超级个体 / 组织扁平化 / 原型直出 / Agent 协作 |
| **Basic Info** | Agent 行为的七维配置（Agent/Soul/Identity/User/Memory/Teams/Tools） |
| **Skill** | 可复用的 Agent 能力模块（SKILL.md + 脚本/参考/资产） |
| **LLM Wiki（最小版）** | 轻量档承载的跨目录只读知识问答，回答强制带出处；"Git 负责可信，Wiki 负责好用" |
| **Wiki 子系统** | 维护（wiki-maintain）+ 查询（wiki-first 问答）+ 晋升（双信号巡检）三块业务的统称；`wiki/` 为衍生解释层，可整目录删除重建 |
| **wiki-maintain** | 维护代码 Wiki 的 Skill（owner=knowledge-agent）：init/update 双模式、gitHead 差量、外科手术式更新纪律、写白名单 |
| **wiki-first** | Wiki 问答的三层检索纪律：先查 wiki/，缺了才窄下探事实源原文，最后才读代码 |
| **知识晋升** | 双信号（高频重复问答 + open-questions 缺口）自动开 Issue 建议回写事实源的巡检回路 |
| **资产元数据卡** | org 可见 Skill 的 4 必填复用授权字段：适用场景/依赖上下文/权限声明/失败处理 |
| **交付效能板块** | 看板第七组（不进总分）：CR Lead Time / Review 负担 / 变更失败率 |
| **AI 净价值** | 看板叙事框架：时间+质量+知识+风险四收益 − 模型与重跑成本（管理口径，非财务核算） |
| **场景工坊** | 角色化 route 视图：需求工坊（PM）/ 质量中心（QA）/ 效能驾驶舱（管理者）；开发工坊=三模式聊天 |

---

*本 PRD 由 Claude Code 基于整场技术调研与方案讨论整合生成 · 2026-07-28 初版 · 2026-07-29 v1.1 修订*
