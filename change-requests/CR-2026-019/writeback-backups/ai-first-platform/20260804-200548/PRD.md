---
id: ai-first-platform-prd
spec-id: ai-first-platform
type: PRD
cr-ref: CR-2026-018
cr-history: [CR-2026-001, CR-2026-002, CR-2026-003, CR-2026-004, CR-2026-005, CR-2026-006, CR-2026-008, CR-2026-009, CR-2026-007, CR-2026-010, CR-2026-011, CR-2026-012, CR-2026-018]
title: AI First 研发协同平台
target-version: "0.20"
owner: Ray
owner-role: requirement
status: ga
created: "2026-07-30T21:27:12+08:00"
updated: "2026-08-04T15:30:00+08:00"
version: v0.9.0
refs:
  upstream:
    - docs/product/AI-First平台-PRD.md
    - docs/product/P0-数据模型映射表.md
    - docs/product/P1-crctl接入设计.md
    - docs/product/P2-三模式聊天交互设计.md
    - docs/product/P3-组织智能设计.md
    - docs/product/Wiki子系统设计.md
  downstream: []
fr-list: [M0-FR-1, M0-FR-2, M0-FR-3, M0-FR-4, P1-FR-1, P1-FR-2, P1-FR-3, P1-FR-4, P1-FR-5, P1-FR-6, P1-FR-7, T1-FR-1, T1-FR-2, T1-FR-3, T1-FR-4, T1-FR-5, T1-FR-6, T1-FR-7, T1-FR-8, T1-FR-9]
---

# AI First 研发协同平台 — PRD 基线

> **累积基线文档**。每个已交付里程碑占一节，节内内容为该 CR 的 PRD 原文（H 级下沉一级）。
> **编号约定**：FR/AC 编号沿用各 CR 原始编号，跨节引用时加里程碑前缀（如 `M0-FR-3`、`P1-AC-5`）；
> 各 CR 目录内的 `prd.md` 仍用不带前缀的原编号，两者按所属里程碑一一对应。
> **回写方式说明**：本基线为累积合并而非整文替换——`writeback-prd-sdd` Skill 字面写的是 `cp` 覆盖，
> 但那会用单一阶段文档覆掉整个平台基线（M0 内容丢失）。历次基线原文备份在
> `change-requests/{CR-ID}/writeback-backups/ai-first-platform/{timestamp}/`。

## 交付里程碑总览

| 里程碑 | 版本 | CR | 状态 | 范围摘要 |
|---|---|---|---|---|
| M0 地基 | 0.10 | CR-2026-001 | archived | fork Multica 并剥离云端专属能力、9 Agent 注册、派单本机执行闭环、tools 一致性 CI |
| P1 治理核心 | 0.11 | CR-2026-002 | 已交付（回写中） | CR 事件同步三层链路（outbox/采集/投影/对账）、Ed25519 签名审批替代 TTY、controlled-shell 下沉 daemon + AI 行为审计 |
| P2 协作体验 | — | 未注册 | 计划中 | 三模式聊天、Presenter、Pipeline Runner 编排 |
| P3 组织智能 | — | 未注册 | 计划中 | AI 成熟度看板、治理板块（数据前置已由 P1 交付） |

---

## M0 — 地基（v0.10 · CR-2026-001 · archived）

> 本 PRD 是 `docs/product/AI-First平台-PRD.md`（v1.2，下称"总 PRD"）在 CR 治理流程下的落地起点，不是对总 PRD 的重写。总 PRD 与 P0–P3、Wiki 子系统设计已经把完整方案讲清楚，本文档只做两件事：① 把总 PRD 的目标转成本 CR 可核查的 FR/AC；② 把"探路"这个决定写明白——为什么 target-version 0.10 只对应总 PRD 的 M0 阶段，而不是试图一次性吃下整个平台。

### 1. 概述

**问题陈述**：`docs/product/` 下已有总 PRD 与 P0–P3、Wiki 子系统设计等六份完整方案文档，但平台目前没有一行实现代码，也没有走过 CR 治理流程——设计和执行之间缺一座桥。

**解决方案摘要**：以 CR-2026-001 作为第一条真正跑通 `crctl` 全流程（注册 → PRD → 评审 → 审批 → 架构 → 编码 → 测试 → 代码评审 → 代码审批 → 回写归档）的变更，验证方法论包 + crctl + worktree 这套机制在这个仓库里确实可用。**本 CR 的可交付范围是总 PRD 里程碑 M0（地基）**：fork Multica、剥离云端专属能力、把 tools 的 9 Agent 注册为可用、验证"派 Issue → daemon 本机执行"闭环、tools 一致性 CI 校验通过。M1（治理核心）、M2（协作体验）、M3（组织智能）在总 PRD 里已经分阶段设计好，将在 M0 验收通过后，按§7"范围排除"里说明的方式拆成独立 CR，不在本 CR 里一次性展开。

### 2. 用户故事

- **US-1（技术负责人）**：作为技术负责人，我希望能在内网 Docker Compose 一次起全栈，以便验证 fork 后的 Multica 底座在自己的环境里可用。
- **US-2（全栈/方法论集成工程师）**：作为负责 tools 集成的工程师，我希望 9 个内置 Agent（product-planning-agent、requirement-writer、dev-agent 等）注册进平台后能被实际调度，以便后续 CR 流程有 Agent 可用而不是空壳。
- **US-3（技术负责人/QA）**：作为需要验证闭环的负责人，我希望能给某个 Agent 派一个 Issue，看它在 daemon 本机领取并跑完，以便确认"本地执行"这条主路径真的通。
- **US-4（全栈/方法论集成工程师）**：作为维护 tools 包一致性的工程师，我希望有一条 CI 检查能自动发现 Agent/Skill/Pipeline 之间的登记不一致，以便这类漂移不需要靠人工巡查。

### 3. 功能需求

| ID | 需求 | 来源 | 优先级 |
|---|---|---|---|
| FR-1 | 内网 Docker Compose（或等价本地编排）一次起全栈：fork 后的 Multica 后端 + 前端 + 依赖服务在本机跑通，且已剥离计费/云节点/多 workspace 注册等云端专属能力 | 总 PRD §5.1.2 步骤 1；P0-F1 | P0 |
| FR-2 | tools 的 9 个内置 Agent（`agents/*.md`）通过 frontmatter 适配器注册为 Multica 可用的 Agent，`{domain}/{skill-id}` 两级目录发现生效 | 总 PRD §5.1.2 步骤 2；P0-F2 | P0 |
| FR-3 | 给已注册的某个 Agent 派发一个 Issue，daemon 能在本机领取并执行完成：任务记录状态为 `completed` 且 Issue 状态进入 `in_review`（Multica 原生语义：Agent 完成 → 待人确认 → 人工关单，`done` 由人关单产生，不是 Agent 自动到达的状态），且执行输出中包含预先约定的结果标记（任务描述里指定的一段可核对文本），不是仅凭"看起来跑完了"判断 | 总 PRD §5.1.4；P0-F3 | P0 |
| FR-4 | tools 包一致性校验接入 CI：`dir-graph.yaml#agents.contract` 的 4 条不变式（Agent 必须先有 `.md` 再登记 `_index.yml`、引用的 Skill 必须 active、Skill 必须同步到 `agent-skill-matrix.yml` 的 owns/can-call、Agent 不得绕过 Skill 直接写受控状态文件）跑通并在 CI 中体现为通过/失败 | 总 PRD §5.1.2 步骤 3；P0-F4 | P0 |

### 4. 非功能需求

- **隐私**：模型凭据与源码不出内网；开发者流量走本人订阅（总 PRD §8）。
- **安全**：本阶段暂不要求签名审批（M1 范围），但 Agent 执行必须走 controlled-shell/gitguard 白名单，不得拿到裸 shell。
- **可部署**：内网 Docker Compose（或等价方案）两条命令内起全栈；端口默认绑 `127.0.0.1`。
- **可维护**：fork 建立 upstream 镜像与双周同步流程；二次开发记录在 `CUSTOM.md` 台账，不散布进上游文件（呼应 `multica/CONTRIBUTING.AIFIRST.md` 规则一、规则二）。

### 5. 验收标准

| ID | 验收项 | 对应 FR |
|---|---|---|
| AC-1 | 内网执行 `make selfhost`（或等价命令）后，Multica 后端、前端、依赖服务全部起来且可访问；Stripe/计费相关路由已摘除，`mcn_` 云节点凭据为空时对应端点天然返回 401 | FR-1 |
| AC-2 | `agents/_index.yml` 中登记的 9 个 Agent 均可在 Multica 的 Agent 注册表里查到，且每个 Agent 引用的 Skill 均能在 `skills/_index.yml` 中找到且状态为 active | FR-2 |
| AC-3 | 对任一已注册 Agent 创建一条 Issue 并指派，daemon 在无人工干预下领取该 Issue、执行完成后任务记录状态为 `completed`、Issue 状态进入 `in_review`（人工确认关单后才是 `done`），且 Issue 评论/执行输出中出现预先约定的结果标记（而非仅凭日志"看起来正常"判断） | FR-3 |
| AC-4 | CI 流水线中存在一致性校验步骤；故意制造一处不一致（例如给某 Skill 引用一个未登记的 owner）后触发 CI 失败；修复后 CI 恢复通过 | FR-4 |

### 6. 成功指标

- **上线后如何度量成功**：M0 阶段没有面向最终用户的量化指标，用二元验收判定——本 CR 的四条 AC 是否全部通过。真正的量化指标（AI 成熟度看板五维十指标）从 M3 阶段才开始有数据源，见总 PRD §5.4.2，不在本 CR 范围内。

### 7. 范围排除

- **P1（治理核心）、P2（协作体验）、P3（组织智能）不在本 CR 范围内**：这三个阶段在总 PRD §5.2–§5.4 已有完整设计（CR 事件同步、签名审批、Pipeline Runner、三模式聊天、Presenter、AI 成熟度看板等），但体量各自需要 4–8 周，硬塞进同一个 CR 会让需求评审门（review-requirement，检查完整性/可测试性/范围/对齐）无法给出有意义的通过判断。约定：M0 本 CR 验收通过并回写归档后，P1/P2/P3 每个阶段（或阶段内进一步拆分的子功能，如 Wiki 子系统、签名审批）各自注册独立 CR，`source` 字段指向对应的 P1/P2/P3/Wiki 设计文档路径。
- **不做本 CR 的一部分**：云端沙箱 SaaS、Token 计费、多组织跨租户、runner 完整档、TicNote 硬件联动、记忆系统具体实现——这些是总 PRD §13"明确不做清单"里平台级别的范围排除，本 CR 直接继承，不重复论证。
- **target-version 说明**：`0.10` 对应总 PRD 里程碑 M0（地基）交付内容，不是"整个平台 0.10 版"的意思；M1 及之后的实际版本号在对应 CR 注册时另行确定。

### 8. 依赖关系

- **FR 内部顺序依赖**：FR-2（Agent 注册）、FR-3（派 Issue 验证执行闭环）都要求 FR-1（fork 后的服务已起来）先完成——daemon 没起来就无法注册 Agent，更谈不上执行 Issue。拆 `write-dev-tasks` 任务时必须把这条顺序显式写进任务依赖关系，不能假设三者可并行开工。
- **对其他 CR 的依赖**：本 CR（CR-2026-001）是本仓库注册的第一个 CR，不依赖任何其他在途 CR。
- **被依赖关系**：本 CR 是 §7 提到的 P1/P2/P3 后续 CR 的前置——那几个 CR 注册时应在各自 `cr.md` 的 `source` 之外，明确写上"依赖 CR-2026-001 已归档"。

### 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-07-30 | v0.1.0 | Ray | 初始草稿，source = `docs/product/AI-First平台-PRD.md` |
| 2026-07-30 | v0.1.1 | Ray | 采纳需求评审的两条非阻塞建议：① FR-3/AC-3 补充具体判定信号（Issue 状态字段 + 约定结果标记），不再靠"看起来跑完了"判断；② 新增第 8 章"依赖关系"，显式写出 FR-1 对 FR-2/FR-3 的顺序依赖，以及本 CR 与后续 P1/P2/P3 CR 的前后依赖 |
| 2026-07-31 | v0.1.2 | Ray | 按 TASK-04 冒烟实测修正 FR-3/AC-3 口径偏差：Agent 执行完成的信号是任务记录 `completed` + Issue 进入 `in_review`，`done` 是人工确认关单后的状态，不是 Agent 自动到达的——v0.1.1 写的"Issue 变为 done"与 Multica 原生语义不符（Agent 完成 → 待人确认 → 人关单），按实测行为修正 |
---

## P1 — 治理核心：crctl 接入（v0.11 · CR-2026-002）

### 1. 概述

**问题陈述**：M0（CR-2026-001）验证了 crctl 状态机可以驱动完整 CR 生命周期，但暴露三个结构性缺口：

1. **治理事实平台不可见**：CR 状态只存在 git（`_backlog.yml`），Multica 的 `cr` 投影表始终为空——看板无法展示在途 CR，P0 定义的"git 权威 / PG 投影"只落地了 Agent 半边。
2. **审批被 TTY 锁死**：`crctl approve` 强制 TTY 交互（M0 四次审批全部依赖本机终端），审批人无法在 Web/桌面端完成审批，团队协作场景不成立。
3. **对模型的 git 约束只有"善意配合"层**：controlled-shell 白名单只在 crctl 内部与 IDE hooks 生效，Agent 子进程仍能拿到裸 git；且白名单规则在 SKILL.md 与 crctl.mjs 硬编码两处漂移（自称 15 条，实际 19 条）。此外 M0 实测发现 `evidence-sha256-16` 写后无人读取——审批后篡改证据无法检出（CR-2026-001 期间以行尾规范化临时修复过其误报，但"批后漂移检测"缺口仍在）。

**解决方案**：按源方案 [P1-crctl接入设计.md](../../docs/product/P1-crctl接入设计.md) 落地三条治理链路，共 D1–D7 七项交付：
- **同步协议**（D1–D3）：crctl outbox（主）→ daemon 采集上报（含 commit 扫描兜底）→ 服务端投影 worker → reconcile 对账（安全网）。
- **签名审批**（D4、D7）：Ed25519 grant 文件替代 TTY，强度不降级；EVIDENCE_DRIFT 检测扩展到 TTY/grant 两轨并持久化留证。
- **controlled-shell 下沉**（D5、D6）：白名单抽成 rules.json 单一事实源，Go 侧 `pkg/gitguard` + execenv 铸造 PATH shim/hooks，越权尝试与工具调用摘要进 `activity_log` 审计。

**前置**：P0-数据模型映射表.md（权威域与五张新表已定）；三仓远端已就位（GitHub：AI-First-Platform / AI-First-multica / AI-First-tools），reconcile 的 server 模式具备实施条件。

### 2. 用户故事

- **US-1** 作为**团队成员**，我想在 Multica 看板上实时看到每个 CR 的状态与负责人，而不必翻 knowledge-base 仓的 git log，以便掌握在途需求全貌。
- **US-2** 作为**审批人**，我想在 Web/桌面端查看证据摘要并点击批准/驳回，而不必登录跑 crctl 的那台机器开终端，以便审批不被物理位置阻塞。
- **US-3** 作为**平台管理员**，我想让 Agent 子进程默认拿不到裸 git、直改受控文件被拦截，且每次越权尝试留下审计记录，以便对"模型漂移/注入越权"有观测和证据。
- **US-4** 作为**测试负责人**，我想在任何审批完成后若证据文件被篡改，gate/validate 能检出漂移并留证，以便审批结论与证据版本强绑定。
- **US-5** 作为**离线/弱网开发者**，我想断网时照常执行 crctl 操作、联网后事件自动补传，以便治理链路不影响本地工作流。

### 3. 功能需求

**交付依赖顺序**（拆任务排序依据）：FR-1 → FR-2 → FR-3 为一条主线；FR-4 依赖 FR-2（evidence digest 从事件通道来）；FR-5 独立可并行；FR-6 依赖 FR-5（gitguard 先存在才有拒绝事件）；FR-7 依赖 FR-4（规范摘要算法先落地），且 FR-7 必须先于 P3 治理板块的 EVIDENCE_DRIFT 指标交付。

#### FR-1 crctl outbox 事件通道（D1）
crctl 在 `advance`、`approve`、`git push` 成功后，向 workspace 根 `.crctl/outbox/` 原子写入结构化事件文件（先写临时名再 rename），文件名 `{utc-ts}-{cr_id}-{event_kind}-{short_sha}.json`，schema 含 `v/event_kind/cr_id/from_status/to_status/trigger/commit_sha/actor/evidence/payload/occurred_at`。outbox 不入 git（复用 `.crctl/` 既有 .gitignore 机制）。`--embedded` 模式下 `commit_sha` 留空，由后续 `git push` 事件补全。crctl 保持零依赖、离线可用。

#### FR-2 daemon 采集与服务端投影（D2）
- daemon 新增 CR 事件收集器（`internal/daemon/crevents.go`，与 heartbeat 同周期）：扫描已知 worktree 与主 workspace 的 outbox；对 knowledge-base 维护 `.crctl/.scan-cursor` 游标做 commit message 兜底扫描（四类 `[cr] ` 前缀正则）；两通道按 `(cr_id, commit_sha, event_kind)` 合并去重。
- 批量上报 `POST /api/daemon/cr-events`（挂既有 DaemonAuth 组，`mdt_` 令牌，单批 ≤100 条）；仅 `accepted` 的 outbox 文件删除，`rejected` 三次后移入 `.crctl/outbox/dead/`；网络失败整批保留、指数退避——离线积压、上线补传。
- 服务端 worker（`internal/service/crsync.go`）：入库 `cr_sync_event`（幂等键 `UNIQUE(cr_id, commit_sha, event_kind)`）；按 cr_id 串行消费；合法转移（对照状态机 23 条转移表只读副本）更新 `cr` 行 + 壳 Issue 7 态映射；非法转移标记 `needs_reconcile` 不强行应用；通过 `events.Bus` → WS 广播到 `workspace:{id}` 与 `issue:{id}`。

#### FR-3 reconcile 对账（D3）
定时任务（复用 `sys_cron_executions` 调度器）对每个非终态 CR 比较 `cr.projected_commit` 与 knowledge-base origin HEAD。`REMOTE_RECONCILE_MODE=server|daemon` 双模式：server 模式（推荐，远端已就位）用只读凭据直接拉 origin；daemon 模式降级为定时全量 `crctl status --json` 快照上报。`needs_reconcile` 的 CR 在下个对账周期自愈。

#### FR-4 签名审批（D4）
- 服务端：审批 API 校验 `RequireHumanActor`（`mat_` 任务令牌 403）+ evidence_digest 与最新事件一致 + 审批人角色策略；通过后写 `approval_record` + Ed25519 签名，签发 grant 文件（schema 见源方案 §B.2，canonical = `v1|{cr_id}|{stage}|{decision}|{approver}|{approved_at}|{evidence_digest}`）。
- 下发：daemon 轮询或任务上下文携带，落盘 `.crctl/grants/{cr_id}-{stage}.grant.json`。
- crctl：`approve --grant <file>` 非 TTY 放行——本地验签（Node 原生 ed25519，公钥从 `{workspace}/.crctl/keys/{key_id}.pub`，公钥提交进 knowledge-base 仓）+ 重算 evidence digest 比对，通过才写 approval.yml 并级联 advance；驳回走状态机既有显式回退转移，`reject_reason` 注入修复节点。
- 私钥存储按源方案 §B.5 落地（文件 0400 或 env base64 注入二选一；启动时公私钥互验 smoke test，不匹配拒绝启动；签名操作单点收口）。

#### FR-5 controlled-shell 白名单下沉（D5）
- 规则抽取为 `skills/shared/controlled-shell/rules.json` 单一事实源（19 条三元组 + forbiddenFlags + protectedPaths），crctl.mjs、Go `pkg/gitguard`、Claude Code hooks 三方消费同一份文件；SKILL.md 降级为解说。
- 新包 `server/pkg/gitguard`：`Check/Run`，错误码沿用 `FORBIDDEN_SUBCOMMAND / FORBIDDEN_FLAG / SHELL_UNAVAILABLE`。
- execenv 四处改造：① 每任务工作目录铸造 `.bin/git` shim（PATH 前插）；② daemon 自身 worktree 操作改走 gitguard（caller=`system-orchestrator`）；③ Agent 上下文注入 git 使用约束；④ Claude 后端自动物化 PreToolUse hooks 到 per-task `.claude/settings.json`，`permission.bash: deny` 的 Agent 追加 `--disallowedTools Bash`。

#### FR-6 AI 行为审计（D6）
- gitguard 的 FORBIDDEN_* 拒绝事件由 daemon 记录（caller/子命令/时间，**不含命令参数正文**），随既有任务回调上报，落 Multica `activity_log`（新增 action 枚举值）。
- 任务完成回调附带工具调用摘要序列（工具名/目标路径/结果码，不含输入输出正文），与 `skills_used[]` 同通道持久化，作为 AI 行为证据链的过程侧。

#### FR-7 EVIDENCE_DRIFT 两轨统一与留证（D7）
- TTY 审批路径改用规范摘要算法（对 `approvalStages[stage].evidence` 全部文件按路径字典序逐个 sha256 拼接再 sha256），写统一字段 `evidence-digest`；废弃 `evidence-sha256-16`，历史字段视为"无摘要"不报错。
- gate 与 validate：只要 `evidence-digest` 存在即重算比对，不符报 `EVIDENCE_DRIFT`（两轨都测）；签名重验证仅对 `server-approve` 生效（两件事分开判断）。
- 漂移事件经 daemon 上报落 `activity_log`（`{cr_id, stage, expected_digest, actual_digest, detected_at}`，不含证据内容）——P3 治理板块 EVIDENCE_DRIFT 计数的唯一数据源，本项不上线则该指标无法区分"从未漂移"与"从未测过"。

### 4. 非功能需求

- **NFR-1 零依赖与离线优先**：crctl 改造后仍零 npm 依赖、无网络调用；断网不阻塞任何 crctl 操作，事件积压补传（at-least-once + 幂等去重）。
- **NFR-2 安全**：私钥不明文入配置文件/日志（启动仅 log key_id）；签名绑定 `cr_id+stage+evidence_digest` 防重放；审批 API 拒绝任务令牌（mat_ → 403）；审计记录不含命令参数正文与证据文件内容。
- **NFR-3 向后兼容**：历史 approval.yml 的 `evidence-sha256-16` 按"无摘要"处理不报错；`[cr] status` commit message 格式为稳定契约（CI 正则依赖）不得变更；gates.json 不改动。
- **NFR-4 性能**：事件采集与 heartbeat 同周期，无独立轮询进程；投影更新经 WS 广播，看板无需刷新拉取。
- **NFR-5 诚实边界（文档化要求）**：签名解决"是不是真人、批的是不是这版证据"，不解决"是否认真看了"；PATH shim 可被绝对路径绕过，须明写并由 CAS+gate（第 4 层）与 CI（第 5 层）兜底；行为审计是观测面不是强制门。产品文案与 SKILL.md 不得夸大。

### 5. 验收标准

- **AC-1**（FR-1）断网执行 `advance` → `.crctl/outbox/` 出现合 schema 的事件文件；联网后 daemon 补传成功且文件被删；`--embedded` 事件的空 `commit_sha` 被后续 push 事件补全。
- **AC-2**（FR-2）同一事件经 outbox 与 commit 扫描双通道到达 → `cr_sync_event` 仅一行；乱序/非法转移 → CR 标记 `needs_reconcile` 而非错误投影；投影更新后看板经 WS 收到刷新事件。
- **AC-3**（FR-3）手工篡改 `cr` 投影行 → 下个对账周期自愈；`REMOTE_RECONCILE_MODE` 两模式均可配置生效（server 模式对 GitHub origin 实测）。**环境前置**：服务端需配置 GitHub 只读凭据——fine-grained PAT，仅授 AI-First-Platform 单仓、仅 Contents: Read-only，不得复用个人全权 token；该前置在对应 TASK 中列为开工条件。
- **AC-4**（FR-4）① 无 TTY 环境 grant 审批走通全链（服务端签发 → daemon 落盘 → `approve --grant` → 级联 advance → 投影更新）；② grant 挪用到别的 CR/阶段 → 验签失败；③ `mat_` 令牌调审批 API → 403；④ 服务端启动公私钥 smoke test 不匹配 → 拒绝启动；⑤ `service/approval.go` 三个拒绝路径（mat_ 403 / 证据漂移 409 / 验签失败 403）单测通过；⑥ crctl `--grant` 验签通过/失败/digest 不符三用例通过。
- **AC-5**（FR-5）① Agent 任务内 `git push --force` → `FORBIDDEN_SUBCOMMAND`；② `git -c core.editor=…` → `FORBIDDEN_FLAG`；③ Write 直改 `_backlog.yml` → hook deny；④ daemon 自身 worktree 操作日志 caller=`system-orchestrator`；⑤ crctl 删除硬编码表后 8 个既有测试仍全通过。
- **AC-6**（FR-6）① 任务内触发一次 FORBIDDEN_* → `activity_log` 出现对应行（不含参数正文）；② 任务详情可查工具调用摘要序列；③ 摘要与 `skills_used[]` 同回调到达，无独立探针。
- **AC-7**（FR-7）① TTY 审批写 `evidence-digest`（非旧字段）；② 历史 `evidence-sha256-16` 不报错；③ TTY 路径批后篡改证据 → `status`/`validate` 检出漂移且 `activity_log` 出现对应行；④ 两轨审批 gate 均能检出同一篡改（非仅 grant 轨）；⑤ 规范摘要（canonical digest）的计算在 crctl 中**仅一处函数实现**，grant 验签路径与 TTY 审批路径调用同一函数（代码评审核查项，防两套哈希逻辑漂移）。

### 6. 成功指标

- 审批在无 TTY 环境（Web/桌面端发起）完成率 100%，M0 式"必须去跑 crctl 的机器开终端"清零。
- 联网状态下 CR 状态变更 → 看板可见延迟 ≤ 2 个 heartbeat 周期；断网积压事件上线后 1 个周期内补齐。
- EVIDENCE_DRIFT 与越权尝试均可在 `activity_log` 按 CR/Agent 维度查询（P3 治理板块数据前置就绪）。
- 上游回馈候选整理成 PR：outbox、rules.json 抽取、EVIDENCE_DRIFT/server-approve 扩展（tools 上游）；gitguard/execenv 留 fork。

### 7. 范围排除

- **P2 三模式聊天**与 Presenter/Pipeline Runner 编排——本 CR 只交付治理数据链路，不做交互层。
- **P3 治理看板 UI**——只交付其数据前置（activity_log 留证），不做看板本体。
- `inbox` 事件的 `handled` 位回写 git——P0 已定 P2 再议。
- 多服务节点的 PG advisory lock——单节点 per-CR 互斥起步，多节点部署时再加。
- 上游 rebase（multica behind 421 / tools 上游演进）——独立于本 CR 的例行事务。
- 内核级沙箱——威胁模型是"防模型不防用户"，PATH shim 绕过路径明写文档，由第 4/5 层兜底。

### 8. 缺陷修补附记（CR-2026-003）

P1 治理核心（CR-2026-002）上线后暴露两处 AC-1/AC-3 未覆盖的边界：多次 `--embedded` 状态推进（空 `commit_sha`）在幂等键上碰撞导致事件被静默丢弃（AC-1 场景遗漏）；CR 归档后错误投影脱离对账覆盖、永久无法自愈（AC-3 场景遗漏，reconcile 快照原只读在途清单）。本 CR 补齐两处边界，不新增 FR/AC，target-version 0.11 → 0.11.1。技术细节见 [SDD.md §9](SDD.md#9-缺陷修补记录cr-2026-003p1-治理核心补丁)。

---

---

## P2 D1 — 三模式聊天：Team Agent 共享队列容量上限（v0.12 · CR-2026-004）

> 来源：docs/product/P2-三模式聊天交互设计.md §11 交付切分 D1（P2 唯一后端待建项）。
> P2 其余交付物（三 tab 窗口主体等）见 docs/product/P2-三模式聊天窗口主体-交付切分.md（D2–D8，未排期）。
> 完整 PRD 见 change-requests/CR-2026-004/prd.md；本节为基线摘要。

### 1. 概述

Team Agent 模式是项目级共享 AI 执行层，此前 `agent_task_queue` 无容量上限概念。本里程碑交付容量治理业务逻辑层：入队前容量校验（默认 50，project 级可配）、owner/admin 插队豁免（priority=100）、排队项撤回（软删除留审计）、队列深度实时可见。机制层（表结构、claim SQL、WS 通道、CancelTask 服务）零改动。

### 2. 功能需求（摘要）

| ID | 需求 | 状态 |
|---|---|---|
| FR-1 | 容量校验：入队前按 project 统计 queued+dispatched，达上限拒绝非 owner/admin（结构化 429） | ✅ |
| FR-2 | owner/admin 插队豁免：不受上限阻塞 + priority=100 经既有 claim 排序先执行 | ✅ |
| FR-3 | 上限 project 级可配（project.settings JSONB 键 team_agent_queue_limit），非法/缺省回退 50 | ✅ |
| FR-4 | 撤回：成员撤自己的项（软删除 status=cancelled 留审计行），owner/admin 撤任意（既有停止语义收紧） | ✅ |
| FR-5 | 实时可见：队列深度经既有 WS task:* 事件驱动刷新；满队输入禁用提示 | ✅ |

### 3. 验收结论

AC-1/2/3/4 真机全过（部署镜像验收，验收全程数据库只 SELECT、造数走真实 API）；AC-5 双端分别验证 + 双浏览器人工补验项挂账。证据：change-requests/CR-2026-004/test-report.md。

### 4. 范围排除（要点）

org 级上限、队列拖拽重排、硬一致容量保证（弱一致口径见 SDD）、计费——均不做；排队项列表 + 逐项撤回的完整聊天窗口 UI 归属 D3（未来 CR）。

---

## 治理工具链补丁 — delivery/task 回写一致性（v0.12.1 · CR-2026-005）

> 本节记录治理工具链自身的缺陷修补，不是平台产品功能；完整 PRD 见 change-requests/CR-2026-005/prd.md。

### 1. 概述

CR-2026-003 归档时，delivery/task 回写（拷贝任务文件 + 更新全局索引）是无 skill 承载、无 gate 校验的纯手工步骤，导致 3 项任务的索引行漏登，直到 CR-2026-004 归档时才偶然发现补registered。本 CR 治理两层：① `crctl` archived 门禁新增 `deliveryIndexComplete` 检查（检测控制，缺失即拒绝归档）；② 重写 `writeback-tasks` skill 为原子操作（预防控制，消除手工分步同步）。

### 2. 验收结论

AC-1~5 全绿；AC-1 用真实历史数据（CR-2026-001~004）重放时发现并修复一处实现 bug（`delivery/task/_index.yaml` 顶层 schema 假设错误）。详见 change-requests/CR-2026-005/test-report.md。

### 3. 范围排除

backlog→history 归档迁移的同类手工空白不在本次范围，留待后续独立评估（可直接复用本 CR 的 gate 检查模式）。

---

## P2 CR-A — 三模式聊天窗口主体：三 tab 骨架 + Team Agent 消息流核心（v0.13 · CR-2026-006）

> 来源：docs/product/P2-三模式聊天窗口主体-交付切分.md v2 的 CR-A 节（D2 全部 + D3 核心）。
> D1（队列容量治理，CR-2026-004）已交付，本里程碑消费其能力不再改动。
> 后续 CR-B~G（队列条完整形态/Private Ask/Discussion/presenter/门禁接合/DC+合并转发）未排期。
> 完整 PRD/SDD 见 change-requests/CR-2026-006/{prd.md, sdd.md}；本节为基线摘要。

### 1. 概述

三模式项目群聊窗口从 0 到可用的第一个 CR：project-detail 主区新增 Issues|Chat tabs，Chat 内三模式 tab
（Team Agent/Private Ask/Discussion）；Team Agent 面消息流最小闭环——落地"隐藏容器 Issue + comment 流"
方案（复用既有 timeline/评论/WS 基础设施，不新建消息表），薄发送端点串联容量守卫→落库→入队→失败补偿。
Private Ask/Discussion 本 CR 仅空态占位。

### 2. 功能需求（摘要）

| ID | 需求 | 状态 |
|---|---|---|
| FR-1 | 入口骨架：project-detail 新增 Issues\|Chat tabs，`?tab=` 深链，切换纯前端零请求 | ✅ |
| FR-2 | 三模式 tab 条 + 空态问候语/教程气泡；Private Ask/Discussion 本 CR 空态占位 | ✅ |
| FR-3 | 输入草稿按 `{projectId}:{mode}` 独立持久化（新建独立 store，未复用既有 chat 全局单例） | ✅ |
| FR-4 | 隐藏容器 Issue（`origin_type='project_chat'`）+ 全部 Issue 查询入口排除（含全局搜索防聊天内容泄漏） | ✅ |
| FR-5 | 薄发送端点：容量守卫前置→落 comment→入队→失败物理补偿，满队同步 429 不落孤儿评论 | ✅ |
| FR-6 | Team Agent 消息流：comment+执行卡按时间交错渲染，历史全量回放 | ✅ |
| FR-7 | 满队/未配置/发送失败三分支反馈，owner/admin 豁免禁用态 | ✅ |
| FR-8 | 模型选择器：绑定 Team Agent 配置模型（非按消息覆盖），编辑权限态与 Runtime 态文案分离 | ✅ |

### 3. 验收结论

AC-1（骨架）/AC-4（满队治理，含并发竞态 429）/AC-5（容器隔离，含全局搜索不泄漏）/AC-6（回归）真机与
API 级验证全过；AC-2（发送闭环）容器创建/守卫/落库/入队/补偿链路 API 级真机验证通过；AC-3/AC-7 的
应用层逻辑（消息流渲染、四态选择器）由单测覆盖，agent 真实执行/daemon 模型上报段待本机 daemon 环境
（部署前独立验收）。证据：change-requests/CR-2026-006/test-report.md。

### 4. 范围排除（要点）

队列条完整形态（常驻计数/展开列表/逐项撤回）、停止、消息过滤开关归 CR-B；Private Ask/Discussion 内容
面归 CR-C/CR-D；presenter 控制权归 CR-E；CR 门禁接合归 CR-F；DC 协调者+合并转发归 CR-G；mobile 全程
不在 P2 范围。

## P2 CR-B — D3 完整形态：队列条 + 逐项撤回 + 停止 + 过滤开关（v0.14 · CR-2026-007）

> 来源：docs/product/P2-三模式聊天窗口主体-交付切分.md v2 的 CR-B 节（D3 完整形态）。
> 前置 CR-A（CR-2026-006）已交付三 tab 骨架与 Team Agent 消息流核心；D1（CR-2026-004）
> 已交付队列容量治理后端全量能力，本 CR 纯前端补全交互，另含一处后端读侧小扩展。
> **回写顺序说明**：本 CR 排期靠前（target-version 0.14）但因故延后完成，实际回写晚于
> CR-C（0.15）/CR-D（0.16）；本节按版本号插入于 CR-A（0.13）与 CR-C（0.15）之间，`基线变更
> 记录`则按回写实际发生顺序追加在表尾，两者不必一致，历史行不重排。
> 完整 PRD/SDD 见 change-requests/CR-2026-007/{prd.md, sdd.md}；本节为基线摘要。

### 1. 概述

Team Agent 面的队列从"黑盒数字"补齐为完整可视/可控形态：队列条常驻「{count} 条排队」+
展开列表逐项显示发起人；发起人撤回自己的排队项（复用 D1 cancel 端点）；停止双权限
（发送者停自己、Owner 停任意，停止后内容保留、下一条自动开始）；「只看 Agent 请求」
本地过滤开关；消息悬浮操作补充复制。含一处后端读侧小扩展
（`queue-status?include=items`），不动 D1 治理语义。

### 2. 功能需求（摘要）

| ID | 需求 | 状态 |
|---|---|---|
| FR-1 | 队列条常驻「{count} 条排队」，count=0 收起，WS 实时无手动刷新 | ✅ |
| FR-2 | 展开列表逐项：发起人、请求摘要、状态、入队时间，顺序同 claim 顺序 | ✅ |
| FR-3 | 逐项撤回：自己 queued/dispatched 项「清除对话」；竞态幂等 200 非静默提示；非发起人 403 | ✅ |
| FR-4 | 停止双权限：发送者停自己（运行中/排队中）、Owner 停任意；内容保留、下一条自动开始 | ✅ |
| FR-5 | 「只看 Agent 请求」本地过滤开关：纯渲染过滤，零网络请求，项目级持久化 | ✅ |
| FR-6 | 队列明细读侧扩展：`GET .../queue-status?include=items`（opt-in，旧调用零变化），LEFT JOIN 保留 NULL originator 任务 | ✅ |
| FR-7 | 消息悬浮复制 | ✅ |

### 3. 验收结论

AC-1~6 全部通过：core/views 单测（803+1813，含本 CR 新增用例）与 Go handler 单测全绿；
`queue-status` 无参调用逐字节零回归对拍通过；代码评审 2 处 Standards 发现（initials 计算
重复、撤回权限判断内一处恒真冗余条件）已修复（`nameToInitials` 抽取、拍平冗余
`if`），1 处 prop-drilling 判断性保留（一跳转发，不引入非必要抽象）。证据：
change-requests/CR-2026-007/test-report.md。

### 4. 范围排除（要点）

消息回复/转发/reaction → CR-G；Private Ask/Discussion 内容面 → CR-C/CR-D（已先行交付）；
presenter 控制权 → CR-E；门禁状态条/审批卡 → CR-F；队列上限配置管理界面不在本 CR。

## P2 CR-C — D5 Private Ask：chat_session 项目维度 + 项目内私聊面（v0.15 · CR-2026-008）

> 来源：docs/product/P2-三模式聊天窗口主体-交付切分.md v2 的 CR-C 节（D5 + B2）。
> 前置 CR-A（CR-2026-006）已交付三 tab 窗口骨架，Private Ask tab 此前仅空态占位。
> 完整 PRD/SDD 见 change-requests/CR-2026-008/{prd.md, sdd.md}；本节为基线摘要。

### 1. 概述

三模式窗口第二 tab 从占位变为可用：B2 后端给 `chat_session` 加 nullable `project_id` 列
（与既有全局 1:1 chat 并存，迁移零改写存量行），前端绕开 `use-chat-controller.ts`/全局
`useChatStore` 单例，纯 props 组合消息流+输入区。语义四差异：个人独立队列、默认 Ask-only
只读、仅本人可见、与 Team Agent 并行。隐私红线（单 socket 架构下"仅本人可见"必须由服务端
per-user 推送保证，前端过滤不算数）是本 CR 首要验收对象，实施中核实发现该红线同时也是
**既有全局 1:1 chat 一直存在但未被发现的泄漏面**，一并收敛修复。

### 2. 功能需求（摘要）

| ID | 需求 | 状态 |
|---|---|---|
| FR-1 | B2 迁移：`chat_session` 加 nullable `project_id` + 按 (project_id, creator_id) 查询会话，与全局 1:1 chat 并存 | ✅ |
| FR-2 | 会话获取：get-or-create（单活跃会话，无则建），并发双开由部分唯一索引兜底 | ✅ |
| FR-3 | Private Ask 面：`ChatMessageList`/`TaskStatusPill` 纯 props 复用；`ChatInput` 因内部读全局 store 未复用，改手写 composer（对齐 CR-A Team Agent 面既有模式） | ✅ |
| FR-4 | 个人独立队列：走既有 1:1 chat 队列语义，不占用/不受 D1 项目共享队列影响 | ✅ |
| FR-5 | Ask-only 只读：`ask_only` 标记贯穿 claim→execenv，brief 省略 Repositories 节 + daemon 拒绝 `repo checkout`（双重强制，checkout 校验含 per-task token 防冒充） | ✅ |
| FR-6 | 隐私推送：含 `ChatSessionID` 的事件一律 per-user 定向推送（`SendToUser`），fail-closed（无收件人即丢弃不回落广播）——同一收敛顺带修复既有全局 1:1 chat 的同一泄漏面 | ✅ |
| FR-7 | 与 Team Agent 并行：两面独立队列/独立任务类型，结构性互不阻塞 | ✅ |
| FR-8 | 输入区能力：模型选择器只读徽标（随 Team Agent 配置）；附件/@提及本 CR 未交付（见范围排除） | 部分 |
| FR-9 | 停止：仅本人可停自己，停止后内容保留 | ✅ |

### 3. 验收结论

AC-1（隐私，首要）：per-user 推送契约与 fail-closed 分支单元层锁定（含真实 chat 任务生命周期
9 处发布点），双浏览器抓包真机验证转人工清单。AC-2（并行）/AC-4（三处会话隔离）/AC-5（迁移
回归）API 级 + 真实 PG 集成测试验证通过。AC-3（Ask-only）：brief 省略与 checkout 拒绝两道防线
单测锁定（含 token 冒充反面用例），真机文件系统验证转人工清单。AC-6（输入区/双端/四语）组件
测试 11/11 通过、四语 parity 全绿。证据：change-requests/CR-2026-008/test-report.md。

### 4. 范围排除（要点）

附件上传、@提及仅成员：实施中核实 `ChatInput` 组件并非纯 props（内部读全局 `useChatStore`
的 draft 键），引入会违反 FR-3/NFR-2"不触碰全局单例"的更高优先级约束，随 `ChatInput` 解耦
后补（技术债已记录于 docs/product/P2-ChatInput组件与全局store解耦-技术债务.md）。技能选择器、
斜杠命令、会话列表/多会话切换、清空上下文、消息回复/转发/导出 Skill 草稿均不在本 CR 范围。

## P2 CR-D — D6 Discussion：discussion 容器 Issue + 纯人类多人聊天（v0.16 · CR-2026-009）

> 来源：docs/product/P2-三模式聊天窗口主体-交付切分.md v2 的 CR-D 节（D6 + B3 的 discussion 容器）。
> 前置 CR-A（CR-2026-006）已交付三 tab 窗口骨架、Discussion 空态占位、容器 Issue 的 origin_type 模式。
> 完整 PRD/SDD 见 change-requests/CR-2026-009/{prd.md, sdd.md}；本节为基线摘要。

### 1. 概述

三模式窗口第三 tab 从占位变为可用：discussion 系统容器 Issue lazily 创建（复用 CR-A 的
origin_type 容器模式，仅新增 discussion 类型值），前端复用 comment-card/reply-input/@提及/
通知/订阅既有基础设施渲染为纯人类多人聊天——无模式/模型/技能下拉、无队列、全员可见。验收
红线：Discussion 消息零 `agent_task_queue` 行、容器 Issue 隐藏于全部列表入口。

### 2. 功能需求（摘要）

| ID | 需求 | 状态 |
|---|---|---|
| FR-1 | discussion 容器 Issue：lazily 创建 + 复用隐藏过滤基建，每项目至多一个（部分唯一索引兜底幂等） | ✅ |
| FR-2 | Discussion 消息流：容器 comment 流为数据源，workspace 级 WS 广播实时上屏，分页历史回放 | ✅ |
| FR-3 | 输入区纯人类形态：仅附件 + @提及，无模式/模型/技能下拉，草稿独立持久化 | ✅ |
| FR-4 | @提及 + 通知 + 订阅：复用既有基础设施，不新建通知类型 | ✅ |
| FR-5 | 零 Agent 触发红线：Discussion comment 不经过入队路径，既有 Issue 页评论豁免不外溢 | ✅ |
| FR-6 | 行内系统条：核实 multica 无项目级成员模型（仅 workspace 级），本 CR 裁剪不实现（SDD §6.3） | 裁剪 |

### 3. 验收结论

AC-1（多人实时）/AC-3（红线，DB 级验证 + migration 161 down→up 往返演练）/AC-4（容器隔离，
逐入口核对）/AC-6（回归 + 四语 parity）真机与 DB 级验证通过；AC-5（输入区形态）组件测试锁定。
AC-2（跨用户提及通知跳转）本轮验证到组件级，真机跨用户端到端待下一次多用户可用测试窗口补验
（不阻塞本次交付）。AC-7 按 SDD §6.3 裁剪结论验收（无实现项——成员唯一模型是 workspace 级、
非项目级，持久化系统条留待未来引入项目级成员模型后再实现）。证据：
change-requests/CR-2026-009/test-report.md。

### 4. 范围排除（要点）

DC 协调者（@提及激活）+ 合并转发/讨论升级 → CR-G（依赖本 CR）；消息回复线程/转发/语音输入、
恢复检查点、导出 Skill 草稿、点踩反馈、斜杠命令、成员管理增强、免打扰设置、项目/消息双入口、
右侧 work-viewer、上下文用量指示器均不在本 CR 范围；mobile 全程不在 P2 范围。

## P2 CR-E — presenter 控制权：claim 串行化键 agent_id→project_id + 单一写者（v0.17 · CR-2026-010）

> 来源：docs/product/P2-三模式聊天窗口主体-交付切分.md v2 的 CR-E / D4 节，交互设计 §2/§3.1。
> 前置 CR-A（CR-2026-006）提供 UI 挂点；D1 队列治理（CR-2026-004）容量/插队/撤回语义不变。
> 完整 PRD/SDD 见 change-requests/CR-2026-010/{prd.md, sdd.md}；本节为基线摘要。

### 1. 概述

项目群聊从"人人可派活"升级为单一写者：presenter 非空时仅其本人的消息被执行，其余成员需申请
控制权；Owner/Admin 默认可驱动且 Agent 空闲时免申请接管，忙时仅排队不抢占。claim SQL 串行化键
从 agent_id 改为 project_id（跨 agent 项目级互斥），是本 CR 独立成 CR 的主因——零回归为硬门槛。

### 2. 功能需求（摘要）

| ID | 需求 | 状态 |
|---|---|---|
| FR-1 | presenter 状态模型：单表 `project_presenter_grant`，六转移（申请/批准/拒绝/转让/撤销/释放），partial unique 索引保证单主持人 | ✅ |
| FR-2 | 入队路径接入 presenter 判定：薄发送端点容量守卫前加控制权守卫，非 presenter 普通成员 403 且不落库不入队 | ✅ |
| FR-3 | claim 串行化键改造：项目共享任务由 `agent_id` 改为 `project_id` 跨 agent 互斥；`chat_session`（Private Ask）分支原样保留不受影响 | ✅ |
| FR-4 | 六种通知卡片：消息流内 PresenterNoticeCard + 定向 inbox（release 无定向对象） | ✅ |
| FR-5 | chatControlPanel 权限面板：按角色渲染操作按钮 | ✅（转让改逐行按钮，未采纳任务文档建议的搜索弹层，理由见 SDD 实现偏差记录） |
| FR-6 | chatHeader 当前主持人：WS 实时更新 | ✅ |
| FR-7 | WS 事件 `project:presenter_changed`：复用既有 `project:` 前缀失效，零新增前端 handler | ✅ |
| FR-8 | 发送端拒绝呈现：与 D1 满队 429 独立的锁定原因，可并存 | ✅ |

### 3. 验收结论

AC-1（单一写者）/AC-3（claim 串行化回归，含 12-agent 并发压测）/AC-4（服务端权威，9 种非法
角色组合真实 HTTP 验证）真机全过。AC-2（状态机全覆盖）核心逻辑真机+自动化全过，WS 双浏览器
会话实时观察未做（环境无可用双用户会话，复用既有生产 `project:` 前缀失效链路，风险评估低）。
AC-5（四语/双端）locale parity 与组件测试全绿，web/Electron 视觉双端人工核对未做（组件树共享，
风险评估低）。两项人工补验均按 CR-2026-004 AC-5 先例降级为低风险挂账，非阻塞。证据：
change-requests/CR-2026-010/test-report.md。

### 4. 范围排除（要点）

队列条完整形态/停止/过滤开关 → CR-B（已交付，互不依赖）；Private Ask 内容面 → CR-C（本 CR 仅
保证 `chat_session` 任务不受串行化键改造影响）；Discussion 面 → CR-D；门禁接合 → CR-F；DC 与
合并转发 → CR-G。计费归属（Owner/Presenter 可配）本 CR 不做，仅留判定基础；presenter 申请的
全局收件箱通知中心不在本 CR，通知触达以消息流内卡片 + WS 实时 + 定向 inbox 为准。

## P2 CR-F — CR 门禁接合：B4 迁移 + 审批卡/blocker/CR 徽标（v0.9.0 · CR-2026-011）

> 来源：docs/product/P2-三模式聊天窗口主体-交付切分.md v2 的 CR-F 节。
> 前置 CR-A（CR-2026-006）提供消息流挂点；P1 治理核心（CR-2026-002）提供 Ed25519 签名审批与
> cr 投影表。完整 PRD/SDD 见 change-requests/CR-2026-011/{prd.md, sdd.md}；本节为基线摘要。

### 1. 概述

CR 治理状态机接入项目群聊消息流：门禁状态条、审批卡（批准/驳回走服务端签名 grant，全程
不落 TTY）、blocker 列表 + reviewLoop 轮次、chatHeader CR 16 态徽标。核心验收是真实 pipeline
网页批准 → 签名 grant → crctl 验签推进的完整闭环。

### 2. 功能需求（摘要）

| ID | 需求 | 状态 |
|---|---|---|
| FR-1 | B4 迁移：`agent_task_queue` 增 `cr_id`/`pipeline_node_run_id` 两列 + `pipeline_run`/`pipeline_node_run` 两表；既有入队路径行为不变 | ✅ |
| FR-2 | 最小节点运行归因：`cr_id` 于 StartTask 后置写入；`pipeline_node_run_id` 本期恒 NULL（收窄，见 SDD §6.1，Runner 未纳入本 CR） | ✅（收窄） |
| FR-3 | 门禁状态条：`pipeline_node_run_id` 非空任务额外渲染节点名/类型/门禁状态，WS 实时刷新 | ✅ |
| FR-4 | 审批卡：human_approval 节点渲染证据摘要 + 批准/驳回；批准走签名 grant 下发 → crctl 验签推进；驳回 `reject_reason` 注入 review_feedback；403/409 结构化呈现 | ✅ |
| FR-5 | blocker 列表 + reviewLoop attempt N/3：review 节点 verdict=block 时显示 | ✅ |
| FR-6 | CR 16 态徽标：chatHeader 直读 `cr` 投影表，WS 实时更新，多 CR 取最新活跃者 | ✅ |

### 3. 验收结论

AC-1（FR-2/3/4 核心链路）与 AC-6（NFR-1 安全回归，403/409）真机完整跑通：网页批准 → Ed25519
签名 grant → 独立 crctl.mjs 交叉验签通过（`TestGrantCrossVerifiesWithCrctl`，此前因环境路径
探测问题被静默跳过多个 CR 周期，本次显式传入 `CRCTL_PATH` 后首次真正跑通并关闭该验证缺口）。
AC-2/3/4/5/7 代码级 + 组件测试全绿，真机浏览器/桌面端人工核对未做，按 CR-2026-004 AC-5 先例
降级为低风险挂账。review-code 阶段发现并修复一项跨 workspace 的 evidence 泄露（详见 SDD
本节 §2 偏差表），修复后合并。证据：change-requests/CR-2026-011/test-report.md。

### 4. 范围排除（要点）

Pipeline Runner（skill 节点首个写者，`pipeline_node_run_id` 才会有真实写入）→ 独立后续 CR；
审批周边批量/委派/超时策略 → 独立后续 CR；见
docs/product/CR-F范围排除项-后续交付规划.md。

## 基线变更记录

| 日期 | 基线版本 | CR | 说明 |
|------|---------|----|------|
| 2026-07-31 | v0.1.2 | CR-2026-001 | 基线建立：M0 地基 PRD 回写（当时为整文 cp） |
| 2026-07-31 | v0.2.0 | CR-2026-002 | 改为累积式基线：保留 M0 全文并新增 P1 治理核心节；FR/AC 引入里程碑前缀约定；target-version 0.10 → 0.11 |
| 2026-07-31 | v0.2.1 | CR-2026-003 | 缺陷修补附记（§8）：AC-1 embedded 幂等碰撞 + AC-3 归档自愈边界；target-version 0.11 → 0.11.1 |
| 2026-08-01 | v0.3.0 | CR-2026-004 | 新增 P2 D1 里程碑节：Team Agent 共享队列容量上限；target-version 0.11.1 → 0.12 |
| 2026-08-01 | v0.3.1 | CR-2026-005 | 治理工具链补丁附记：delivery/task 回写一致性门禁 + writeback-tasks 原子化；target-version 0.12 → 0.12.1 |
| 2026-08-02 | v0.4.0 | CR-2026-006 | 新增 P2 CR-A 里程碑节：三模式聊天窗口骨架 + Team Agent 消息流核心；target-version 0.12.1 → 0.13 |
| 2026-08-02 | v0.5.0 | CR-2026-008 | 新增 P2 CR-C 里程碑节：D5 Private Ask（B2 迁移 + 隐私 per-user 推送收敛 + Ask-only 双重强制）；target-version 0.13 → 0.15 |
| 2026-08-02 | v0.6.0 | CR-2026-009 | 新增 P2 CR-D 里程碑节：D6 Discussion（discussion 容器 Issue + 纯人类多人聊天，FR-6 裁剪留痕）；补齐 frontmatter cr-ref/cr-history/version 此前四次回写（CR-2026-004~006/008）遗漏同步的漂移；target-version 0.15 → 0.16 |
| 2026-08-02 | v0.7.0 | CR-2026-007 | 补跑新增 P2 CR-B 里程碑节：D3 完整形态（队列条常驻+展开列表/逐项撤回/停止双权限/过滤开关/队列明细读侧扩展）；本 CR 排期先于 CR-C/CR-D（target-version 0.14）但实际回写晚于两者，按版本号插入于 CR-A 与 CR-C 之间，本行按回写实际发生顺序追加在表尾；target-version 维持 0.16（0.14 不高于已交付基线，不回退） |
| 2026-08-03 | v0.8.0 | CR-2026-010 | 新增 P2 CR-E 里程碑节：presenter 控制权（单表状态机六转移）+ claim 串行化键 agent_id→project_id 改造（12-agent 并发压测验证恰一 active，chat_session 分支不受影响）；target-version 0.16 → 0.17 |
| 2026-08-03 | v0.9.0 | CR-2026-011 | 新增 P2 CR-F 里程碑节：CR 门禁接合（门禁状态条 + 审批卡 + blocker/reviewLoop + CR 16 态徽标），review-code 阶段发现并修复跨 workspace evidence 泄露；target-version 0.17 → 0.18 |


## P2 CR-G · D8 DC 协调者 + 讨论转执行（合并转发）（v0.19 · CR-2026-012）

> 依据：`docs/product/P2-三模式聊天窗口主体-交付切分.md` v2（d7e4ece）的 CR-G 节（D8），
> 交互契约与字典锚点以《P2-三模式聊天交互设计》§5.1/§5.2 为准（`shadowchat.discussion`、
> `assignAgentTooltip`、`mergedForwardMessage.triggerMessage/chatHistory/messagesInConversation`）。
> **本 CR 是自研设计定位**——切分文档 §0.3 识别的两处偏差（DC 输出可见性、合并转发交互）
> 无 CodeBanana 实物可抄，本 PRD §1 定案。ChatInput 解耦技术债按
> `docs/product/P2-ChatInput组件与全局store解耦-技术债务.md` §4.1 方案 A 随本 CR 一并偿还
> （该文档 §6 约定的触发时机——CR-G 开始设计阶段——即现在）。
> 前置：CR-2026-009（CR-D）已交付 discussion 容器 Issue 与纯人类消息流；
> CR-2026-006（CR-A）已交付 Team Agent 消息流与入队路径（转发目的地）。

### 1. 概述

**背景**：CR-D 交付后，Discussion 是纯人类聊天面，与执行完全隔离（零 Agent 触发红线）；
CR-A 交付的 Team Agent 面是执行现场。两者尚无接合：讨论沉淀了但不能转化为执行——达成共识后
仍要有人手动去 Team Agent 面复述上下文；讨论本身也无人协调（总结、追踪、路由）。本 CR 交付
D8 的两个接合件：DC（Discussion Coordinator）协调者与合并转发（讨论转执行），落地 CodeBanana
核心理念「沟通发生在执行发生的地方」。同时，CR-A/CR-C 两次因 `ChatInput` 全局 store 耦合
而手写降级 composer（纯文本、无附件、无 @提及），技术债文档约定 CR-G 开工即第三次撞坑收敛点——
本 CR 一并偿还并回填两面。

**本 CR 交付**：
1. **DC 特殊 Agent**：默认静默，@提及 DC 或回复 DC 消息激活；只协调不执行——execenv 只读 +
   forbidden 全部写 Skill（服务端强制）；可 `EnqueueTaskForMention`（经 A2A）把任务路由到
   Team Agent；协调输出作为 Discussion 消息**全员可见**。
2. **合并转发（讨论转执行）**：多选 Discussion 消息 → 合并预览 → 生成一个带
   `triggerMessage` + `chatHistory` 汇总结构的 Team Agent 任务；项目尚无关联 CR 时，
   可触发 `requirement-register` 走 P0 的 Issue→CR 升级链路把讨论升级为 CR。
3. **ChatInput 解耦（方案 A，纯前端）**：`ChatInput` 新增可选 prop
   `draftAdapter?: ChatInputDraftAdapter`；未传时落回默认实现（`/chat` 页与浮窗零改动），
   传入时完全按 adapter 渲染/回写、不触碰 `useChatStore`；回填 Team Agent 面与 Private Ask 面
   （附件 + @提及仅成员 + 富文本），接 `project-chat-store` 的 `{projectId}:{mode}` 命名空间；
   新增单测锁定"自定义 adapter 时不触碰 `useChatStore`"。

**两处偏差的定案**（切分文档 D8 节要求 PRD 阶段先定）：
1. **DC 输出可见性 → 定案：可见协调输出**。CodeBanana 的 DC 是静默协调器（消息不出现在聊天中），
   本平台按"过程即记录"审计要求反其道：DC 的总结/追踪/路由动作全部以 Discussion 消息呈现，
   全员可见、可回放。静默协调不可取，此为产品决策，SDD 不得回退。
2. **合并转发交互 → 自研设计**。CodeBanana 实物只有多选逐条转发；"多条合并为一个带上下文任务"
   是本平台增量（字典 `mergedForwardMessage` 存在但无页面实物）。本 PRD 给交互轮廓
   （FR-4：多选态 + 合并预览 + 确认发送），视觉与细节 SDD 自定，无原产品可抄。

**技术前提**（SDD 阶段细化，偏离需论证）：
1. **红线豁免的唯一开口**：CR-2026-009 的零 Agent 触发红线原文即预留"除非 CR-G 的 DC 被显式
   激活"。本 CR 打开且仅打开这一个口子：@提及 DC / 回复 DC 才入队，其余 Discussion 消息
   （含正文出现 DC 名字但未 @ 的）行为与 CR-D 交付态完全一致。
2. **DC 权限是服务端硬约束**：execenv 只读 + forbidden 全部写 Skill 由任务执行环境强制，
   不是 prompt 层的君子约定；DC 的"执行"能力仅剩把任务路由给 Team Agent。
3. **不新增执行通路**：DC 路由与合并转发的目的地都是 CR-A 既有 Team Agent 入队路径
   （`EnqueueTaskForMention`），受 D1 容量守卫与既有 claim 串行化约束，队列语义零改动。
4. **"回复 DC 激活"的落地形态待 SDD 定案**：切分文档 §0.4 写死排除了消息回复（reply）线程，
   而 DC 的第二种激活方式是"回复 DC 的 Discussion 消息"。SDD 需定案最小实现（如仅针对 DC
   消息的轻量 reply-to 引用，不做通用线程），若论证成本过高可降级为仅 @提及激活，留痕即可。
5. ChatInput 改造范围按技术债文档 §4.1 逐行核实结论：`chat-input.tsx` 单文件四处改动点
   （读订阅、restoreDraft effect、handleUpload、handleSend/commitInput），约 230 行机械替换，
   渲染 JSX 与既有 props 接口不变。

### 2. 用户故事

- **US-1** 作为**项目成员**，我希望讨论跑偏或过长时 @DC 得到一份可见的总结/追踪/路由建议，
  而且这份协调记录留在讨论流里全员可查，以便协调过程本身也是可审计的项目记录。
- **US-2** 作为**项目成员**，我希望把达成共识的若干条讨论消息一次多选、合并转发成一个
  Team Agent 任务，而不是自己去 Team Agent 面复述上下文，以便"讨论的地方就是发起执行的地方"。
- **US-3** 作为**项目成员**，我希望一段有价值的讨论在尚无 CR 时能直接升级为合规的 CR，
  以便需求从口头共识进入治理轨道不需要换场景重新录入。
- **US-4** 作为**项目成员**，我希望在 Team Agent 面与 Private Ask 面获得与浮窗同级的输入体验
  （附件、@提及成员、富文本），而不是纯文本框，以便项目内沟通不再是降级体验。
- **US-5** 作为**平台维护者**，我希望 DC 在环境层面就无法写任何文件、`ChatInput` 新消费方
  在组件层面就无法误触全局单例，以便这两条红线靠机制而非靠 code review 记忆维持。

### 3. 功能需求

| ID | 需求 | 优先级 |
|---|---|---|
| FR-1 | **DC 特殊 Agent 角色**：平台内置 DC（Discussion Coordinator）特殊 Agent——execenv 权限只读 + forbidden 全部写 Skill（服务端强制，非 prompt 约束）；具备 `EnqueueTaskForMention`（经 A2A）路由能力；在 Discussion 面可被 @提及（字典 `shadowchat.discussion`/`assignAgentTooltip`） | P0 |
| FR-2 | **静默/激活边界**：DC 默认静默——普通 Discussion 消息（含正文提及 DC 名字但未 @ 的）不触发 DC、不产生 `agent_task_queue` 行（CR-D 红线不变）；@提及 DC 或回复 DC 消息（形态按技术前提 4 SDD 定案）时激活，激活即走既有入队路径（受 D1 容量守卫，满队结构化反馈） | P0 |
| FR-3 | **可见协调输出**：DC 激活后产生的协调输出（总结/追踪/路由说明）作为 Discussion 消息进入消息流，全员实时可见、刷新可回放；DC 路由任务时在 Discussion 内留下可见的路由说明，同时 Team Agent 面出现对应任务；DC 任务全程零文件写入 | P0 |
| FR-4 | **合并转发多选态 + 合并预览**：Discussion 消息流支持进入多选模式勾选若干消息；发起合并转发前展示合并预览——触发消息（`triggerMessage`）+ 聊天记录汇总（`chatHistory`）+ 「对话中的 {count} 条消息」（`messagesInConversation`），确认后发送，可取消退出多选态 | P0 |
| FR-5 | **合并转发生成任务**：确认后生成**一个** Team Agent 任务，prompt 上下文含 `triggerMessage` + `chatHistory` 汇总结构（多选 N 条 → 一个任务，非逐条 N 个）；走 CR-A 既有入队路径，受容量守卫，任务在 Team Agent 面正常呈现与执行 | P0 |
| FR-6 | **讨论升级 CR**：合并转发时项目尚无关联 CR 的场景下，可触发 `requirement-register` 把该段讨论升级为 CR——走 P0 的 Issue→CR 升级链路，产生合规 CR 壳（含讨论上下文）；已有 CR 时不重复创建 | P0 |
| FR-7 | **ChatInput draftAdapter 解耦（方案 A）**：`ChatInput` 新增可选 prop `draftAdapter?: ChatInputDraftAdapter`（`draftKey`/`editorKey`/`draft`/`attachments` + `setDraft`/`setAttachments`/`addAttachment`/`clearDraft`）；未传时落回默认实现（读 `useChatStore` 派生 `draftKey`，`/chat` 页与浮窗零改动）；传入时组件全部草稿/附件读写走 adapter，不触碰 `useChatStore`；新增单测双重锁定（静态断言 + 行为断言）"自定义 adapter 时不触碰 `useChatStore`" | P0 |
| FR-8 | **回填 Team Agent 面与 Private Ask 面**：两面以 `draftAdapter` 接入 `ChatInput`（adapter 落 `project-chat-store` 的 `{projectId}:{mode}` 命名空间，`editorKey` 恒定为 mode），替换手写 composer，补齐附件（文件/图片）、@提及仅成员、富文本；停止/取消、模型只读徽标等既有能力语义不变 | P0 |

### 4. 非功能需求

- **NFR-1 DC 权限硬约束**：只读 execenv 与写 Skill 禁用由服务端任务执行环境强制；DC 任务
  执行后审计验证零文件写入；DC 无审批、无 CR 状态操作能力（权威铁律不因新角色出现豁口）。
- **NFR-2 红线单开口**：Discussion 零 Agent 触发红线仅"DC 显式激活"一处豁免；CR-2026-009 的
  AC-3（普通消息 DB 级零队列行）在本 CR 交付后复验仍成立。
- **NFR-3 队列语义零改动**：DC 路由与合并转发均复用既有入队路径；容量守卫、claim 串行化、
  撤回/停止语义不变；不新增执行通路。
- **NFR-4 既有消费方零回归**：`/chat` 页与浮窗走默认 adapter 路径，行为与既有测试零变化；
  `chat-input.test.tsx` 既有用例全绿。
- **NFR-5 双端一致**：web 与 desktop（Electron 共享 `packages/views`）行为一致；mobile 不在 P2 范围。
- **NFR-6 四语文案**：DC 消息、多选态、合并预览、升级 CR 等全部新增 UI 文案提供
  en/ja/ko/zh-Hans，locale parity 测试全绿（`mergedForwardMessage` 族字典键已存在，沿用）。

### 5. 验收标准

- **AC-1**（FR-2，静默边界）Discussion 内发送多条普通消息，含一条正文出现 DC 名字但未 @ 的：
  DC 零响应，`agent_task_queue` 无新增行（DB 级验证，即 CR-2026-009 AC-3 复验）。
- **AC-2**（FR-2/3，激活与可见输出）@提及 DC → DC 激活，协调输出以 Discussion 消息出现在
  消息流，另一浏览器会话的成员实时可见，刷新后可回放；审计验证该任务全程无任何文件写入。
- **AC-3**（FR-1/3，路由）DC 按协调判断路由任务 → Team Agent 面出现对应任务且正常执行，
  Discussion 内留有可见路由说明；共享队列满时激活 DC 得到结构化满队反馈，不静默失败。
- **AC-4**（FR-4/5，合并转发）多选 N 条 Discussion 消息 → 合并预览呈现 triggerMessage +
  chatHistory + 「对话中的 N 条消息」→ 确认后 Team Agent 面出现**一个**任务，其 prompt 上下文
  含 `triggerMessage` + `chatHistory` 汇总结构；中途取消退出多选态无副作用。
- **AC-5**（FR-6，升级 CR）项目无关联 CR 时合并转发触发 `requirement-register` → 走 P0
  Issue→CR 升级链路产生合规 CR 壳，讨论上下文随升级带入；已有 CR 场景不重复创建。
- **AC-6**（FR-7，解耦锁定）`/chat` 页与浮窗既有测试全绿零回归；新增单测证明传入自定义
  adapter 时 `ChatInput` 不读不写 `useChatStore`（静态 + 行为双重断言）。
- **AC-7**（FR-8，回填）Team Agent 面与 Private Ask 面可上传附件、@提及仅成员（Agent/文件树
  不出现在 Private Ask 建议列表）、富文本输入；跨项目、跨模式真机验证不串草稿、不串附件
  （`{projectId}:{mode}` 隔离语义不变）。
- **AC-8**（NFR-5/6，回归）web 与 desktop 行为一致；locale parity 测试全绿；CR-D Discussion
  面、CR-A Team Agent 面既有回归通过。

### 6. 成功指标

- 讨论转执行闭环打通：从"多选讨论 → 一键生成带上下文的 Team Agent 任务（或升级 CR）"全程
  不离开 Discussion 面，「沟通发生在执行发生的地方」从理念变为可演示路径。
- 协调过程可审计：DC 的每次总结/路由都是消息流里的持久记录，"过程即记录"覆盖到人类讨论层。
- 三次踩坑的耦合债一次性偿清：Team Agent 面与 Private Ask 面输入体验与浮窗对齐（技能选择器
  除外），且单测机制性防止第四次踩坑；后续新聊天面接入成本降为"写一个薄 adapter"。

### 7. 范围排除

- **技能选择器**——独立平台缺口（前后端都缺、语义未定案），按技术债文档 §7 另议，
  不随解耦回填；两面输入区本 CR 交付后仍无技能选择器。
- **ChatInput 方案 B**（完全受控组件）——不做；方案 A 已满足新消费方隔离需求。
- **DC 高级协调能力**（周期性自动总结、无 @ 主动介入、跨项目协调）——本 CR 仅 @提及/回复
  激活的被动协调。
- **通用消息回复（reply）线程与逐条转发**——切分文档 §0.4 写死排除（合并转发除外）；
  技术前提 4 的 DC reply-to 若做也仅限 DC 消息，不外溢为通用能力。
- **presenter 控制权**——CR-E（CR-2026-010，并行 CR），本 CR 不依赖不实现；合并转发入队
  沿当下队列权限语义。
- 切分文档 §0.4 其余写死排除项继续有效（双入口、work-viewer、上下文用量、语音、斜杠命令、
  导出 Skill 草稿、恢复检查点、点踩反馈、mobile）。


---

## 治理工具链 — 状态推进单写 cr.md，_backlog.yml 退化为注册索引（v0.20 · CR-2026-018）

### 1. 概述

#### 1.1 问题陈述

CR-2026-012 收尾复盘（`docs/analysis/CR-2026-012-合并回写归档复盘.md`）确认的最大摩擦源（约占卡点耗时 35%）：`crctl advance` 每次状态推进同时写两处——`change-requests/_backlog.yml` 条目的 `status` + `updated-at` 行，与 `change-requests/{CR-ID}/cr.md` frontmatter 的同名字段。CR 分支与 master 各自积累状态提交后，合并/变基时 `_backlog.yml` 同一条目区域**必然**冲突（CR-2026-012 生命周期 9 个状态提交全部冲突）。更结构性的问题是：`merge-feature-branch` Step 2 规定 dry-run 冲突即中止，因此只要双侧存在状态提交，该 skill 按字面执行对知识库仓**永远走不通**。

#### 1.2 解决方案摘要

状态的单一事实源收敛为 `cr.md` frontmatter：`crctl advance` 只写 `cr.md`，不再写 `_backlog.yml` 的 `status`/`updated-at`；`_backlog.yml` 退化为**注册索引**（保留 id / title / owners / prd-path / merge-commits 等注册与里程碑字段）。CR 分支上的高频状态提交从此只触碰 `change-requests/{CR-ID}/**`——该路径在合并前 master 侧不写，冲突面从源头消除。

**可见性无损失**：现状下在途 CR 的状态提交本来就在 CR 分支上，master 的 `_backlog.yml` 对在途 CR 同样陈旧；改为 cr.md 单一事实源不损失任何现有读取能力。

#### 1.3 事实基线（已核实，纪律 #4）

| 事实 | 位置 |
|---|---|
| `_backlog.yml` status 写入点仅 1 处：`updateBacklogStatus()`，由 `advance` 调用（cr.md summary 中"8 处写入逻辑"系登记时误记，以此为准） | `crctl.mjs:674`（调用点 `:814`） |
| `status` 子命令从 `_backlog.yml` 读权威状态 | `crctl.mjs:335-342` |
| workspace 探测依赖 `change-requests/_backlog.yml` 存在性 | `crctl.mjs:289` |
| `validate` 对 `_backlog.yml` 条目做 schema 校验 | `crctl.mjs:1018-1024` |
| 31 个 skill 文档引用 `_backlog.yml`；其中直接消费条目 `status` 的至少有 cr-dashboard（按 `backlog[].status` 分组）、cr-archive（entry.status→final-status）、merge-feature-branch（Step 5 embedded status patch） | `grep -rln _backlog tools/skills --include=SKILL.md` |
| 状态机 scope 字段写明 `_backlog.yml` | `tools/dir-graph.yaml:210` |
| 适配器读取路径均经 crctl 子命令（claude-code SessionStart 注入 `crctl status`、CI 复用 `crctl gate`/`validate`），随 crctl 升级自然切换，但需回归验证 | `crctl/adapters/` |

### 2. 用户故事

- **US-1** 作为 CR 开发者，我在 CR 分支上推进状态时不产生任何会与 master 冲突的提交，merge-feature-branch 对知识库仓可以按字面流程一次走通。
- **US-2** 作为平台维护者，我通过 `crctl status` 得到的状态读数在改造前后语义一致，不需要改变任何使用习惯。
- **US-3** 作为看板使用者（cr-dashboard / cr-query），我在改造后仍能看到与现在等价的 CR 状态分布。
- **US-4** 作为存量 workspace 的所有者，我有一条明确的一次性迁移路径，且迁移期内新旧布局都能被 crctl 正确读取。

### 3. 功能需求

- **FR-1（advance 单写）**：`crctl advance` 只写 `cr.md` frontmatter 的 `status` 与 `updated-at`；删除对 `updateBacklogStatus()` 的调用路径。CAS 写保护、审计日志、门禁校验、状态事件行为不变。
- **FR-2（读取路径切换 + 兼容读）**：`status` / `advance`（前置读）/ `gate` / `next` / `validate` 的权威状态读取源改为 `cr.md` frontmatter；当 `cr.md` 缺失 status 字段时回退读 `_backlog.yml` 条目并在输出中携带 `legacy-source` 告警。回退路径为迁移期兼容，计划在下一个大版本移除。
- **FR-3（_backlog.yml 退化为注册索引）**：条目保留字段收敛为注册与里程碑类（id、title、owners、submitter、reviewer、opened、prd-path、merge-commits、merge-recovery、archived-at、writeback_spec_id 等低频字段）；`status`/`updated-at` 不再作为权威字段。`validate` 不再要求条目含 `status`；若仍含且与 `cr.md` 不一致，输出漂移告警（迁移期不阻断）。
- **FR-4（workspace 探测不变）**：`_backlog.yml` 文件继续作为 workspace 探测锚点（`crctl.mjs:289` 逻辑不变），文件本身不删除。
- **FR-5（一次性迁移命令）**：提供 `crctl migrate-backlog`（或等价子命令）对存量 workspace 执行：校验各条目 `status` 与 `cr.md` 一致 → 从 `_backlog.yml` 条目中移除 `status`/`updated-at` 行 → 生成迁移报告。不一致时硬失败并列出差异，禁止静默取一侧（纪律 #1 硬失败原则）。
- **FR-6（skill 文档同步修订）**：31 个引用 `_backlog.yml` 的 skill 文档中，凡读取条目 `status` 的段落改为读 `cr.md`（重点：cr-dashboard 状态分组改为扫描 `change-requests/*/cr.md`；merge-feature-branch Step 5 embedded patch 只落 `cr.md` + `merge-commits[]` 仍写 `_backlog.yml`；cr-archive Step 3 移动条目时以 `cr.md` 的 final-status 为准）。仅引用文件路径不消费 status 的文档不改。
- **FR-7（状态机声明同步）**：`tools/dir-graph.yaml#change-request-track.state_machine.scope` 从 `_backlog.yml` 改为 `change-requests/{CR-ID}/cr.md`。
- **FR-8（适配器同版本回归）**：claude-code 适配器（SessionStart/PreCompact 注入）与 CI 适配器（gate/validate）在改造后跑一遍回归：注入输出与 CI 判定在新布局 workspace 上与旧行为等价。
- **FR-9（归档流兼容）**：cr-archive 的 backlog→history 移动逻辑保持——归档发生在 master 单侧、每 CR 一次，不构成冲突面；history 记录的 `final-status` 字段语义不变。

### 4. 非功能需求

- **NFR-1（状态机语义零变更）**：15 个具名状态 + `(new)`、23 条声明转移（wildcard 展开 45 条）完全不变（口径见纪律 #2）；本 CR 只改状态的**存储位置与读写路径**。
- **NFR-2（行尾纪律）**：所有新增/修改的解析与写入代码遵守纪律 #1——读入先 `\r\n → \n` 规范化、`split(/\r?\n/)`、跨行解析失败硬报错；`cr.md` frontmatter 写入保持现有 `updateCrMdStatus()` 的 CAS 模式。
- **NFR-3（原子性）**：单文件写入沿用现有 sha256 CAS（读后被改则 `CAS_CONFLICT` 中止）；advance 从双文件写变为单文件写，原子性只增不减。
- **NFR-4（向后兼容窗口）**：兼容读（FR-2 回退路径）至少保留一个完整 CR 生命周期，供多 workspace 分批迁移。

### 5. 验收标准

- **AC-1**（对应 FR-1）：在测试 workspace 执行一次合法 `advance`，`git diff` 显示仅 `change-requests/{CR-ID}/cr.md` 变更，`_backlog.yml` 无 diff。
- **AC-2**（对应 FR-2）：新布局（_backlog 无 status）下 `crctl status` 返回 `cr.md` 中的状态；构造仅 `_backlog.yml` 有 status 的旧布局，`crctl status` 返回该状态且输出含 `legacy-source` 标记。
- **AC-3**（对应 FR-3）：`crctl validate` 对新布局 workspace 全绿；对 status 双写且不一致的 workspace 输出漂移告警且退出码为 0（迁移期）。
- **AC-4**（对应 FR-4）：在无其他标志文件的目录树中，`crctl --workspace` 缺省探测仍能命中含 `_backlog.yml` 的目录。
- **AC-5**（对应 FR-5）：对含 ≥2 个条目的存量 `_backlog.yml` 执行迁移命令：一致时产出无 status 的注册索引 + 迁移报告；人为制造一处不一致时命令非零退出且不写文件。
- **AC-6**（对应 FR-6）：`grep -rn "backlog\[\].status\|_backlog.*status"` 在修订后的 skill 文档中仅命中"迁移说明/历史注记"类段落；cr-dashboard 按新数据源描述统计逻辑。
- **AC-7**（对应 FR-7）：`dir-graph.yaml#state_machine.scope` 指向 cr.md；`crctl status` 输出的 `source.stateMachine` 不变、状态源指向 cr.md。
- **AC-8**（对应 FR-8）：claude-code 适配器 SessionStart 注入在新布局 workspace 输出正确状态；CI 模板对 `requirement/*` 分支的 gate 判定与改造前一致（用同一组 fixture 对比）。
- **AC-9**（对应 FR-9 与核心目标）：端到端演练一个测试 CR：分支上推进 ≥3 次状态 → master 侧注册另一 CR 制造并行写 → `merge-tree --write-tree` dry-run 对 `_backlog.yml` **零冲突**。
- **AC-10**（回归）：`crctl` 现有测试套件（`scripts/test/crctl.test.mjs`）全绿，新增用例覆盖 FR-1/2/3/5。

### 6. 成功指标

- 下一个走完整生命周期的 CR，在 merge-feature-branch 阶段知识库仓 dry-run 对 `_backlog.yml` 冲突数为 **0**（基线：CR-2026-012 为 9 个提交全冲突）。
- 合并/回写/归档三阶段实际耗时相对 CR-2026-012 的 ~190 min 显著下降（复盘将冲突连环归因为 ~35% 卡点耗时，预期至少消除该部分）。
- 迁移后一个月内无因状态读取源分裂产生的 `CAS_CONFLICT` / 状态漂移工单。

### 7. 范围排除

- **不做 P2**（账本操作 crctl 子命令化：任务 `_index.yml` 标 done、归档移动等）——本 CR 是其前置，P2 待本 CR 定型后另立。
- **不改状态机本身**：不增删状态、不改转移与门禁语义、不动 `gates.json` 的证据映射结构（仅在其引用 `_backlog.yml` 状态源处随 FR-7 同步措辞）。
- **不改 `_history.yml` 结构**与归档记录字段。
- **不处理非知识库仓**：独立代码仓不含 `change-requests/`，本 CR 与其无关。
- **不移除兼容读**：回退路径的删除放到后续版本，本 CR 只标记 deprecated。
- **不解决 cr.md 在 master 侧对未合并 CR 不可见的问题**：这是现状既有行为（_backlog.yml 同样如此），与本 CR 无关。
