---
id: ai-first-platform-prd
spec-id: ai-first-platform
type: PRD
cr-ref: CR-2026-019
cr-history: [CR-2026-001, CR-2026-002, CR-2026-003, CR-2026-004, CR-2026-005, CR-2026-006, CR-2026-008, CR-2026-009, CR-2026-007, CR-2026-010, CR-2026-011, CR-2026-012, CR-2026-018, CR-2026-019]
title: AI First 研发协同平台
target-version: "0.20.1"
owner: Ray
owner-role: requirement
status: ga
created: "2026-07-30T21:27:12+08:00"
updated: "2026-08-04T20:07:48+08:00"
version: v0.10.0
refs:
  upstream:
    - docs/product/AI-First平台-PRD.md
    - docs/product/P0-数据模型映射表.md
    - docs/product/P1-crctl接入设计.md
    - docs/product/P2-三模式聊天交互设计.md
    - docs/product/P3-组织智能设计.md
    - docs/product/Wiki子系统设计.md
  downstream: []
fr-list: [M0-FR-1, M0-FR-2, M0-FR-3, M0-FR-4, P1-FR-1, P1-FR-2, P1-FR-3, P1-FR-4, P1-FR-5, P1-FR-6, P1-FR-7, T1-FR-1, T1-FR-2, T1-FR-3, T1-FR-4, T1-FR-5, T1-FR-6, T1-FR-7, T1-FR-8, T1-FR-9, T1.1-FR-1, T1.1-FR-2, T1.1-FR-3, T1.1-FR-4, T1.1-FR-5, T1.1-FR-6, T1.1-FR-7]
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
| 2026-08-04 | v0.10.0 | CR-2026-019 | 新增治理工具链里程碑节：YAML 账本操作收敛为 crctl 子命令（task done / merge-metadata / archive-move + casWriteMulti 双文件原子写 + AC-9 merge-tree 演练入库）；target-version 0.20 → 0.20.1 |


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
## 治理工具链 — YAML 账本操作收敛为 crctl 子命令（v0.20.1 · CR-2026-019）

## PRD — YAML 账本操作收敛为 crctl 子命令（P2）+ AC-9 演练入库

### 1. 概述

#### 1.1 问题陈述

CR-2026-012 收尾复盘（`docs/analysis/CR-2026-012-合并回写归档复盘.md` §3.2 P2）确认：状态推进已由 CR-2026-018（T1-full）收敛为 `crctl advance` 单写 `cr.md`，但**三类账本写入操作仍靠 Agent 手工编辑 YAML**——

1. 任务 `change-requests/{CR-ID}/tasks/_index.yml` 的 `status: pending → done`；
2. `_backlog.yml` 注册条目的 `merge-commits[]` 追加；
3. 归档时把注册条目从 `_backlog.yml` 移动到 `_history.yml`（附 `final-status`）。

这三处是本轮转义事故的高发区：CR-2026-012 一次会话内现写的坏脚本把 9 个 rebase 冲突块原样提交进历史，事后手工修复（纪律 #7 由此固化）。手工/现写脚本编辑绕开了 crctl 已有的 **CAS 写保护 + 审计日志 + 门禁校验**单一写入路径。

同时，CR-2026-018 测试报告 §5.1 / §6 记录：AC-9 的 `git merge-tree --write-tree` 对 `_backlog.yml` 零冲突演练当前是会话内一次性脚本（`_scratch/patch-task10b.mjs` 变体），未纳入 CI 回归，核心不变量缺自动化守护。

#### 1.2 解决方案摘要

把上述三类账本操作补成 crctl 子命令（`crctl task done` / `crctl merge-metadata` / `crctl archive-move`），复用 `advance` 已有的写入基础设施（sha256 CAS、`.crctl/audit.log` 追加、门禁校验），**不新建独立脚本库**——复盘明确否决"脚本入库 `tools/skills/shared/scripts/`"方案，因其会在 crctl 之外开第二条账本写入通道，长期必然漂移。账本从此只有一条写入路径：crctl。

配套把 AC-9 merge-tree 零冲突演练从会话内一次性脚本固化为入库测试用例，纳入 `crctl.test.mjs` 回归套件。

#### 1.3 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| crctl 现有子命令：`status/gate/advance/approve/validate/attempt/test/next/migrate-backlog/git`——**无** `task`/`merge-metadata`/`archive-move` | `crctl.mjs:1419-1431`（dispatch case） |
| `tasks/_index.yml` 当前仅被**读取**用于 delivery/task 一致性校验，crctl 无写入路径 | `crctl.mjs:560-562` |
| `merge-commits[]` 是 `_backlog.yml` 注册条目字段（CR-018 已定型），当前由 `merge-feature-branch` 手工/embedded patch 写入 | `crctl.mjs:690` 注释 + `merge-feature-branch` SKILL |
| 归档 backlog→history 移动当前由 `cr-archive` skill 手工编辑两个账本文件 | `cr-archive` SKILL；worktree 存在 `_history.yml` |
| `advance` 已具备 CAS（读后被改则 `CAS_CONFLICT`）+ 审计日志 + 门禁，可复用 | CR-2026-018 SDD / `cmdAdvance` |
| AC-9 演练为会话内一次性脚本，未入 CI | `_scratch/patch-task10b.mjs`；CR-018 测试报告 §5.1(1) |
| 前置依赖满足：T1-full（CR-2026-018）已定型；主仓 `_backlog.yml` 已迁移 v2 注册索引布局 | CR-018 测试报告 §6；`_backlog.yml` v2 |

### 2. 用户故事

- **US-1** 作为 CR 开发者，我完成一个任务后用一条 crctl 子命令把 `tasks/_index.yml` 标 done，写入经 CAS 复核并留审计记录，不再手写 YAML（纪律 #8 落到工具层）。
- **US-2** 作为执行合并的维护者，我用一条 crctl 子命令把 merge-commits 追加进注册条目，转义事故高发的手写编辑从流程中消失。
- **US-3** 作为归档执行者，我用一条 crctl 子命令原子完成 backlog→history 的条目移动（附 final-status），任一侧 CAS 冲突则整体中止，绝不产生半移动的账本。
- **US-4** 作为平台维护者，账本只有 crctl 一条写入通道，任何写入都过 CAS + 审计 + 门禁，不存在绕开复核的第二通道。
- **US-5** 作为 CI/回归的维护者，AC-9 merge-tree 零冲突不变量由入库测试用例守护，回归自动执行而非依赖会话内一次性脚本。

### 3. 功能需求

- **FR-1（`crctl task done` 子命令）**：新增 `crctl task done <CR-ID> --task <TASK-ID> [--workspace .]`，把 `change-requests/{CR-ID}/tasks/_index.yml` 中对应任务 `status` 置为 `done` 并记录完成时间戳。经 sha256 CAS 写保护、追加 `.crctl/audit.log`；`--task` 不存在或已 done 时硬失败并说明（不静默）。
- **FR-2（`crctl merge-metadata` 子命令）**：新增 `crctl merge-metadata <CR-ID> --add-commit <sha>[,<sha>...]`，把提交 SHA 追加进 `_backlog.yml` 注册条目的 `merge-commits[]`（去重、保序），经 CAS + 审计。取代 `merge-feature-branch` 手工/embedded 编辑该字段的路径。
- **FR-3（`crctl archive-move` 子命令）**：新增 `crctl archive-move <CR-ID> --final-status <status>`，**原子**地把注册条目从 `_backlog.yml` 移除并写入 `_history.yml`（携带 `final-status` 与归档时间戳）。两个文件均纳入本次 CAS 快照，任一侧读后被改则整体 `CAS_CONFLICT` 中止、不落任何一侧。`final-status` 语义与结构沿用现状（CR-018 FR-9），不新增字段。
- **FR-4（单一写入路径不变量）**：三个子命令一律复用现有账本写入基础设施（CAS 读→写、审计追加、YAML 解析/序列化），**不引入独立脚本库**、不新增第三方依赖、不开第二条写入通道。会话内现写脚本处理账本被工具层面根除。
- **FR-5（门禁与非法调用防护）**：`archive-move` 仅在 CR 处于可归档态时合法（非法态硬失败并给出当前态与期望态）；`task done` 仅在开发相关态合法；所有子命令对缺参、CR 不存在、workspace 探测失败均硬失败。门禁语义引用状态机唯一事实源（`../tools/dir-graph.yaml`），不在本 CR 复刻声明（纪律：禁止复制状态机）。
- **FR-6（skill 文档同步收敛调用）**：`implement-code`（任务标 done）、`merge-feature-branch`（merge-commits 写入）、`cr-archive`（归档移动）三个 SKILL.md 改为调用对应新子命令，并显式禁止会话内手写/现写脚本编辑账本（纪律 #7 从文档约定落为工具强制）。仅引用账本路径而不写入的文档不改。
- **FR-7（AC-9 演练入库为测试用例）**：把 `_scratch/patch-task10b.mjs` 的 merge-tree 零冲突演练（共同祖先注册 → 分支推进 ≥3 次 `cr.md` → master 侧注册另一 CR → `git merge-tree --write-tree` 对 `_backlog.yml` 零冲突）固化为 `skills/shared/crctl/scripts/test/crctl.test.mjs` 的入库用例，纳入 `node --test` 回归。

### 4. 非功能需求

- **NFR-1（行尾纪律，纪律 #1）**：三个子命令对账本文件的读入先 `\r\n → \n` 规范化、解析用 `split(/\r?\n/)`；YAML/跨行解析匹配失败一律**硬失败报错**，禁止静默降级为空/取一侧。
- **NFR-2（原子性）**：`archive-move` 的双文件写入是全有或全无——沿用 `advance` 的 CAS 模式对每个目标文件做读后校验，任一冲突整体回退，绝不产生 backlog 已删而 history 未写（或反之）的半状态。
- **NFR-3（单一写入通道）**：账本写入在改造后有且仅有 crctl 一条路径；审计日志可完整追溯每次账本变更的 actor / 时间 / 前后差异。
- **NFR-4（零新增依赖）**：完全复用 crctl 现有 YAML/CAS/审计工具函数与 Node 标准库，不加第三方包。
- **NFR-5（回归可执行）**：新增用例与 AC-9 入库用例纳入既有 `crctl.test.mjs`，`node --test` 一次运行全绿，不依赖临时目录外部状态。

### 5. 验收标准

- **AC-1**（对应 FR-1）：`crctl task done <CR> --task <TASK-ID>` 后 `tasks/_index.yml` 该任务 `status=done` 且含完成时间戳，`audit.log` 新增一条对应记录；对不存在的 `--task` 与已 done 任务均非零退出且不写文件。
- **AC-2**（对应 FR-2）：`crctl merge-metadata <CR> --add-commit <sha>` 后注册条目 `merge-commits[]` 含该 sha；重复追加同一 sha 不产生重复项；写入经 CAS，`audit.log` 有记录。
- **AC-3**（对应 FR-3）：`crctl archive-move <CR> --final-status archived` 后条目从 `_backlog.yml` 消失、在 `_history.yml` 出现且带 `final-status`；构造 history 侧读后被改场景，命令 `CAS_CONFLICT` 中止且**两个文件都无变更**。
- **AC-4**（对应 FR-4）：`grep` 三个子命令实现，账本写入全部经既有 CAS/审计工具函数；仓库内无为这三类操作新建的独立脚本库目录。
- **AC-5**（对应 FR-5）：对非可归档态 CR 执行 `archive-move`、对非法态执行 `task done`、对不存在 CR 执行任一子命令，均非零退出并打印当前态/期望态或缺失原因；无任何账本文件被写。
- **AC-6**（对应 FR-6）：`implement-code` / `merge-feature-branch` / `cr-archive` 三个 SKILL.md 中账本写入步骤改为调用新子命令，且含"禁止会话内手写/现写脚本编辑账本"明文；`grep` 三文档无残留"手工编辑 YAML"类指引。
- **AC-7**（对应 FR-7 与核心目标）：`crctl.test.mjs` 含 AC-9 merge-tree 零冲突用例，`node --test` 运行该用例 PASS；用例内 `git merge-tree --write-tree` 对 `_backlog.yml` 冲突数为 0、exit 0。
- **AC-8**（回归）：`crctl` 现有测试套件（基线 32 用例，CR-018 定型）全绿，新增用例覆盖 FR-1/2/3/5 与 AC-9 入库。

### 6. 成功指标

- 三类账本操作（任务标 done / merge-commits 写入 / 归档移动）经 crctl 子命令执行的比例达 **100%**；流程文档中手工编辑 YAML 账本的指引数降为 **0**。
- 下一个走完整生命周期的 CR，账本写入相关的转义类返工事故数为 **0**（基线：CR-2026-012 一次坏脚本把 9 个冲突块提交进历史）。
- AC-9 merge-tree 零冲突不变量由 CI 回归用例守护，回归自动执行，不再依赖会话内一次性脚本。

### 7. 范围排除

- **不建独立脚本库**：明确否决"脚本入库 `tools/skills/shared/scripts/`"，账本写入只保留 crctl 单一通道。
- **不改状态机本身**：不增删状态、不改转移与门禁语义、不在本仓复刻状态机/gates 声明（唯一事实源在 `../tools/`）。
- **不改 `_backlog.yml` v2 schema 与 `_history.yml` 结构**：注册索引布局由 CR-2026-018 定型，本 CR 只补写入子命令，不动字段集合与归档记录结构。
- **不重跑迁移**：`crctl migrate-backlog` 与存量 workspace 迁移是 CR-2026-018 的发布动作，不在本 CR 范围。
- **不改兼容读**：CR-018 的 `legacy-source` / `MIXED_LAYOUT_WARN` 回退读路径与其去留由后续版本处理，本 CR 不触碰。
- **不处理非知识库仓**：独立代码仓不含 `change-requests/`，与本 CR 无关。

## 治理工具链 — writeback 机械步骤固化为入库脚本（v0.21 · CR-2026-020）

## PRD — writeback 机械步骤固化为入库脚本

### 1. 概述

#### 1.1 问题陈述

CR-2026-019 走完整 writeback 流水线实测约 **30 min**，其中纯执行（git 合并/推送、advance、子命令调用、账本提交）约 10 min，而 **"会话内现写回写脚本 + 调试"约 20 min，占三分之二**（实测拆解见 `docs/product/writeback-流水线耗时分析与优化方案.md` §2，本 CR 按其 §7 落地建议立项）。

根因是回写期三个节点——`writeback-prd-sdd` / `writeback-tasks` / `writeback-traceability`——的机械操作**至今没有入库脚本，全靠每次会话现写一次性脚本并试错**。三份 SKILL.md 只给描述性步骤，精确文件结构、字段名、锚点、格式每次都要现场勘察。CR-2026-019 由此踩了三次"跑→报错→改→重跑"调试循环：

| 坑 | 表现 | 根因归类 |
|---|---|---|
| 锚点语义措辞不匹配 | 脚本断言的 brief 措辞与实际文本不符 | 增量文本补丁模式 |
| 锚点命中多次 | `target-version` 在 `_index.yml` 顶层与既有条目重复命中 | 增量文本补丁模式 |
| 脚本非幂等 | 首跑成功、重跑失败，需另写补丁脚本 | 增量文本补丁模式 |
| 编辑器转义 | `\n` 字面被转成真实换行 | 现写脚本的一次性脆弱性 |

前三个坑同源：对结构化文件采用**"读旧文件→找锚点→局部改写"的增量文本补丁**，位置判断一旦偏离实际文本就出错。这与纪律 #7（YAML 账本类操作禁止会话内现写脚本）同源——账本操作已由 CR-2026-018/019 收敛为 crctl 子命令，但 specs/delivery 回写这一类"机械 + 易错"操作仍在纪律覆盖之外，靠每次现写。

此外流水线存在两处冗余设计，持续制造维护面与调试面：
- **writeback-backups**：`writeback-prd-sdd` 回写前把旧版 `specs/{spec_id}/{PRD,SDD}.md` 拷入 `change-requests/{cr_id}/writeback-backups/{spec_id}/{timestamp}/` 并写含 SHA 的 `metadata.yml`——在 git 仓库里手工重复实现 git 自带的历史与审计能力。
- **双份 traceability.yml**：`change-requests/{cr_id}/traceability.yml`（开发期工作稿）与 `specs/{spec_id}/traceability.yml`（回写节点产物）并存，pipeline 节点 prompt 约定二者"保持一致、后者权威"——标准的"两份数据、一份权威"反模式，无机制检测分叉。

#### 1.2 解决方案摘要

把三个节点的机械步骤固化为 `tools/skills/shared/scripts/` 下**版本化的独立脚本**，SKILL.md 改为"调用脚本 + 核对 dry-run diff"，并把已核实事实写进 SKILL 的事实基线段；同时**删除 writeback-backups 步骤**（git commit 即备份与审计）、**收敛双份 traceability.yml 为 specs 侧单一权威文件**。

消除调试循环的关键不是"把补丁脚本写得更稳"，而是**从"增量文本补丁"改为"结构化处理"**，按文件性质分三类（详见 FR-5）：可从其他来源推导的文件全量重建（天然幂等、无锚点）；累积性结构化字段用"解析→改对象→重序列化"（幂等、无文本锚点）；只有真正的累积性正文（PRD/SDD 里程碑节）保留锚点追加，并以行首/字段名结构锚点 + 锚点唯一性硬失败兜底。

**与 CR-2026-019 边界（关键，避免误读为推翻刚定型的决策）**：CR-2026-019 曾**否决**"账本操作脚本入库 `tools/skills/shared/scripts/`"，理由是账本（`_backlog.yml` / `_history.yml` / 各 CR `tasks/_index.yml`）承载状态机、有并发写入语义，第二条脚本通道会绕开 crctl 的 CAS + 审计 + 门禁而长期漂移。**本 CR 的对象不同**：specs/`{PRD,SDD,traceability}`、`specs/_index.yml`、`delivery/task/` 及其 `_index.yaml` 是 git 跟踪的内容文件，无状态机、无并发写语义，**git commit 本身就是它们的 CAS 与审计**；它们当前唯一的写入通道恰恰是"每次会话现写的一次性脚本"（N 条临时通道），固化为版本化脚本是把 N 条收敛为 1 条，方向与账本场景相反。因此本 CR **不做成 crctl 子命令、不接入 casWriteMulti / CAS 审计基础设施**，脚本一律**不触碰**账本文件（`_backlog.yml` / `_history.yml` / `cr.md` / 各 CR `tasks/_index.yml`）——那些仍只走 crctl。

#### 1.3 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| 三份 writeback SKILL 均只提供描述性步骤，无入库脚本；精确字段/锚点/格式靠每次现场勘察 | `tools/skills/writeback/{writeback-prd-sdd,writeback-tasks,writeback-traceability}/SKILL.md` |
| `writeback-prd-sdd` SKILL Step 2 要求回写前备份到 `writeback-backups/{spec_id}/{timestamp}/` 并写 `metadata.yml`（含原文件 SHA） | `writeback-prd-sdd/SKILL.md` Step 2；CR-2026-019 目录存在 `writeback-backups/` |
| `writeback-tasks` SKILL **已规定** id 判重幂等（Step 2）+ 拷贝/frontmatter/索引一步原子（Step 4-5）；真实命名 `TASK-{version}-{cr_id}-{NN}-{slug}` | `writeback-tasks/SKILL.md` Step 2-5 |
| `writeback-traceability` SKILL **已是全量生成**（`# auto-generated — do not edit manually`），仅写 specs 侧 | `writeback-traceability/SKILL.md` Step 3 |
| pipeline 第 4 节点 prompt 要求 specs 侧 traceability 与 `change-requests/{cr_id}/traceability.yml` 保持一致、后者为"权威版本"；二者实际并存 | `tools/pipeline-templates/feature-writeback.pipeline.json` node-4；CR-2026-019 目录并存两份 |
| 命名不一致：pipeline 模板用 `TASK-{target_version}-{NNN}-{NN}-*`、`writeback-traceability` SKILL 示例用 `TASK-{ver}-{CR-NNN}-01`，均与 `writeback-tasks` SKILL 自述的实际格式（且真实数据）不符 | pipeline node-3；`writeback-traceability/SKILL.md` Step 3；`delivery/task/_index.yaml` 实际条目 |
| `specs/_index.yml` 的 `features[].brief` 为逐版本累积的人工长文、`current` 为编辑性字段——**不可全量重建**，只能解析后改结构化字段（`cr-history[]` 追加、`current`/`cr-ref`/`updated` 更新） | `specs/_index.yml`（`ai-first-platform` 条目 brief 已累积 0.10→0.20.1 多版本描述） |
| `delivery/task/_index.yaml` 可由扫描 `delivery/task/*.md` frontmatter 完全推导；`specs/{spec_id}/traceability.yml` 可由证据源完全重建 | `delivery/task/_index.yaml`；`writeback-traceability/SKILL.md` Step 2 证据源表 |
| crctl.mjs 已含可复用的 YAML 解析函数（`parseYaml`/`parseMap`/`parseSeq` 等），但当前未导出（CLI 内部） | `tools/skills/shared/crctl/scripts/crctl.mjs`（`parseYaml` 起） |
| `merge-feature-branch` 参与仓规则靠每次对照先例推断（tools 仓 trunk=custom/main、空分支跳过、开发期未 push 需补齐 `origin/requirement/{cr_id}`），SKILL 无事实基线段 | CR-2026-019 §2 ① 调研耗时；`merge-feature-branch` SKILL |
| 前置依赖满足：CR-2026-019 已归档定型，账本三子命令（`task done`/`merge-metadata`/`archive-move`）已入库 | CR-2026-019 归档；`crctl.mjs` dispatch |

### 2. 用户故事

- **US-1** 作为执行 writeback 的维护者，我调用一条入库脚本即可完成 PRD/SDD 回写与 `specs/_index.yml` 字段更新，不再会话内现写脚本、不再逐个踩锚点/转义/幂等的坑。
- **US-2** 作为执行 writeback 的维护者，我调用入库脚本完成 tasks 回写，重跑同一 CR 是 noop（幂等），不会产生"首跑成功、重跑失败"的补丁脚本。
- **US-3** 作为执行 writeback 的维护者，traceability 由脚本从证据源全量重建为**唯一**的 specs 侧文件，我不再需要维护两份、也不再有"两份是否一致"的校验负担。
- **US-4** 作为平台维护者，回写脚本版本化、可测试、可复用，且明确不与账本共用 CAS/审计机制——specs/delivery 内容文件的审计由 git 历史承担，账本写入仍只走 crctl 单一通道。
- **US-5** 作为流水线的执行者，我在节点启动时读到 SKILL 里已核实的事实基线（里程碑命名、索引格式、参与仓规则），不再每节点重复现场调研与对照先例。
- **US-6** 作为平台维护者，回写前不再产生 `writeback-backups/` 冗余备份目录，旧版本经 `git log`/`git show`/`git revert` 追溯，CR 目录不再堆积无人查阅的备份文件。

### 3. 功能需求

- **FR-1（`writeback-prd-sdd.mjs` 入库脚本）**：新增脚本完成 PRD/SDD 回写：首次回写整份落地；增量回写按里程碑分节追加（原文 H 级整体下沉一级、既有里程碑节原样保留、跨节编号加里程碑前缀）；通过 `engineering-docs` 约定补齐/更新 frontmatter（`spec_id`/`version`/`status`/`cr_ref`）；并对 `specs/_index.yml` 做结构化字段更新（`features[]` 对应 id 的 `cr-history[]` 按 id 追加去重、`current`/`cr-ref`/`updated` 更新，`since` 首次创建时写入）。`brief` 一句话描述为编辑性内容，由调用方作为入参传入，脚本负责放置，不臆造。脚本**不再实现** writeback-backups 备份步骤（见 FR-6）。
- **FR-2（`writeback-tasks.mjs` 入库脚本）**：新增脚本把 `change-requests/{cr_id}/tasks/` 下 `status=done` 的任务原子回写到 `delivery/task/`：按真实命名 `TASK-{version}-{cr_id}-{NN}-{slug}`（slug 取 frontmatter `slug:`，缺失回退 `task-{NN}`）拷贝、注入 `spec-id`/`version` frontmatter、并维护 `delivery/task/_index.yaml`。幂等依据为**目标索引中的 `id` 集合**（已登记则整体跳过，不重写文件、不重复追加索引行）——把 SKILL 现有的口头约定固化为脚本行为。
- **FR-3（`writeback-traceability.mjs` 入库脚本）**：新增脚本从证据源（`cr.md` / specs 侧 `PRD.md`·`SDD.md` frontmatter / `review-annotations/*` / `test-report.md` / `delivery/task/_index.yaml` / `_backlog.yml` 的 `merge-commits[]`）**全量重建** `specs/{spec_id}/traceability.yml`（保持 `# auto-generated — do not edit manually` 语义）。tasks 条目命名与 FR-2 一致，修正 SKILL Step 3 示例中作废的 `TASK-{ver}-{CR-NNN}-01` 写法。`merge-commits[]` 缺失或 repo SHA 不完整时硬失败，不猜测、不自动取 trunk 最新提交。
- **FR-4（独立脚本、不并入 crctl、不接 CAS/审计）**：三个脚本作为 `tools/skills/shared/scripts/` 下的独立 `.mjs` 落地，复用 crctl 现有的 YAML 解析/序列化工具（如需，将相关函数抽取为 shared 模块由 crctl 与本脚本共用，不复制第二份实现），**不新增第三方依赖**。脚本**不做成 crctl 子命令、不调用 casWriteMulti、不写审计日志、不做门禁校验**；specs/delivery 内容文件的可追溯性由 git commit 承担。
- **FR-5（结构化处理取代增量文本补丁）**：按文件性质分三类处理，禁止对结构化文件做"读旧文件→找语义锚点→局部改写"式补丁——

  | 文件 | 处理方式 | 幂等/锚点性质 |
  |---|---|---|
  | `delivery/task/_index.yaml`、`specs/{spec_id}/traceability.yml` | 全量重建（扫描 delivery 目录 / 汇集证据源整份生成） | 天然幂等、无锚点、不存在"命中多次" |
  | `specs/_index.yml` | 解析→改结构化字段→重序列化（`cr-history[]` 按 id 追加去重、`current`/`cr-ref`/`updated` 更新）；`brief` 由入参提供 | 幂等（重复 CR-id 不追加）、无文本锚点 |
  | `specs/{spec_id}/{PRD,SDD}.md` 里程碑节追加 | 保留锚点追加：锚定 frontmatter 字段名 + 行首/缩进，不做语义措辞匹配；锚点唯一性断言失败即硬失败（纪律 #1） | 累积性正文、历史节不可重建，只能追加 |

- **FR-6（删除 writeback-backups 步骤）**：`writeback-prd-sdd.mjs` 与其 SKILL 不再实现回写前的 `writeback-backups/{spec_id}/{timestamp}/` 备份与 `metadata.yml`。旧版本经 git 历史追溯。SKILL Step 2 与 Step 6 输出中的"备份位置"一并删除。
- **FR-7（收敛 traceability.yml 为单一权威文件）**：`specs/{spec_id}/traceability.yml` 是唯一的、跨 CR 累积的权威文件，由 `writeback-traceability.mjs` 全量重建生成。`change-requests/{cr_id}/traceability.yml` 降级为该 CR 开发期工作稿，归档后不再维护、不再要求与 specs 侧同步；`writeback-traceability` 节点及 pipeline node-4 prompt 移除"与 change-requests 侧保持一致"的一致性校验语义。
- **FR-8（三份 SKILL.md 改调 + 事实基线段）**：`writeback-prd-sdd` / `writeback-tasks` / `writeback-traceability` 三份 SKILL.md 改为"调用对应脚本 + 核对 dry-run diff"，删除现场现写脚本的描述性指引，并新增"已核实事实基线"段（参照 SDD §0 先例），固化里程碑命名惯例（`## {标题}（v{version} · CR-{id}）`、节内 H 下沉一级）、`specs/_index.yml` 与 `delivery/task/_index.yaml` 字段格式、以及统一的 task 命名格式（消除 pipeline 模板 / traceability 示例与实际写法的三处不一致）。
- **FR-9（merge-feature-branch 参与仓规则固化）**：在 `merge-feature-branch` SKILL 的事实基线段固化：tools 仓（`phase0-tools`，dir-graph.yaml 自声明）参与合并且 trunk=`custom/main`（非 main）；无提交的分支（如 CR 无该仓代码改动时的空分支）自动跳过合并与 merge-commits 记录；合并前需补齐开发期未 push 的 `origin/requirement/{cr_id}`。免去每次对照先例推断。（本 FR 仅补 SKILL 事实，不改 merge-feature-branch 的合并/补偿逻辑。）

### 4. 非功能需求

- **NFR-1（行尾纪律，纪律 #1）**：脚本对文件读入先 `\r\n → \n` 规范化、解析用 `split(/\r?\n/)`；YAML/跨行解析或（PRD/SDD 追加场景的）锚点匹配失败一律**硬失败报错**，禁止静默降级为空/取一侧。
- **NFR-2（幂等）**：同一 CR 对同一脚本重跑为 noop 并显式输出（已应用则跳过），不产生"首跑成功、重跑失败"，无需补丁脚本。
- **NFR-3（自带 dry-run + 自检，不另写 verify）**：脚本提供 dry-run 模式（打印将产生的 diff 不落盘）与末尾自检断言（回写后校验关键字段），取代 CR-2026-019 中另写、且断言文本自身写错过的一次性 verify 脚本。
- **NFR-4（零新增依赖）**：仅用 Node 标准库与复用的 crctl YAML 工具函数，不加第三方包。
- **NFR-5（与账本机制解耦）**：脚本不触碰 `_backlog.yml` / `_history.yml` / `cr.md` / 各 CR `tasks/_index.yml`（这些仍只走 crctl），不引入 CAS/审计/门禁；仅写 specs/ 与 delivery/ 内容文件。
- **NFR-6（可测试、可回归）**：三个脚本各自留一个可运行自检（最小化，dry-run 断言或独立 test），一次运行验证核心机械逻辑不回归；不引入测试框架/fixture，不搞逐函数套件。

### 5. 验收标准

- **AC-1**（FR-1/FR-5）：对已存在基线的 spec 调用 `writeback-prd-sdd.mjs`，PRD/SDD 新增里程碑节且既有节原样保留、H 下沉一级；`specs/_index.yml` 对应 `features[]` 的 `cr-history[]` 追加本 CR、`current`/`cr-ref`/`updated` 更新；重复运行同一 CR，`cr-history[]` 不产生重复项。
- **AC-2**（FR-2/FR-5）：调用 `writeback-tasks.mjs` 后，done 任务按 `TASK-{version}-{cr_id}-{NN}-{slug}` 落地 `delivery/task/`、frontmatter 含 `spec-id`/`version`、`delivery/task/_index.yaml` 追加对应条目；重跑为 noop（已登记 id 全部跳过，文件与索引无变化）。
- **AC-3**（FR-3/FR-7）：调用 `writeback-traceability.mjs` 后 `specs/{spec_id}/traceability.yml` 由证据源全量重建、tasks 条目命名与 AC-2 一致；`change-requests/{cr_id}/traceability.yml` 未被要求同步，流程无"两份一致性校验"步骤；`merge-commits[]` 缺失时脚本非零退出。
- **AC-4**（FR-4/NFR-5）：`grep` 三脚本实现，均不含 casWriteMulti/审计/门禁调用、不写 `_backlog.yml`/`_history.yml`/`cr.md`/CR `tasks/_index.yml`；脚本不以 crctl 子命令形式注册（`crctl help` 无新增子命令）。
- **AC-5**（FR-6）：回写一个 spec 后 `change-requests/{cr_id}/` 下**不产生** `writeback-backups/` 目录；三份 SKILL.md `grep` 无"备份/metadata.yml/writeback-backups"残留指引。
- **AC-6**（FR-8/FR-9）：三份 writeback SKILL.md 与 `merge-feature-branch` SKILL.md 含"调用脚本 + 核对 dry-run diff""事实基线"段；task 命名在 pipeline 模板、traceability SKILL、writeback-tasks SKILL 三处一致（`grep` 无 `TASK-{ver}-{CR-NNN}` 类作废格式）。
- **AC-7**（NFR-2/NFR-3）：每个脚本 dry-run 输出预期 diff 不落盘；无 dry-run 时落盘后自检断言通过；对同一 CR 连续运行两次，第二次显式输出 noop。
- **AC-8**（NFR-1/NFR-6）：脚本对含 `\r\n` 的输入正确规范化，PRD/SDD 追加锚点命中 0 次或多次时硬失败（非零退出）；三脚本自检一次运行通过。

### 6. 成功指标

- 下一个走完整 writeback 的 CR，流水线总耗时 **≤15 min**（基线 CR-2026-019：~30 min），回写环节**零脚本调试循环**（基线：3 次）。
- 回写期"造工具/调试"时间从约 20 min 降至仅"调用脚本 + 核对 dry-run 输出"。
- 冗余数据清零：新 CR 不产生 `writeback-backups/` 目录；traceability 仅 specs 侧单一权威文件，无"两份一致性"步骤。
- 会话内现写脚本处理 specs/delivery 回写的次数降为 **0**（纪律 #7 适用范围从账本扩展到回写产物，落到工具层）。

### 7. 范围边界

**本 CR 包含**：三个入库脚本 + 三份 writeback SKILL.md 改调与事实基线段 + `merge-feature-branch` SKILL 事实基线段 + 删除 writeback-backups 步骤 + 收敛 traceability 为单一权威 + task 命名三处一致化 + 脚本自检。

**本 CR 不包含**：状态机与账本结构改动；crctl 子命令新增；CAS/审计基础设施接入；`merge-feature-branch` 合并/补偿逻辑改动（仅补其 SKILL 事实基线）；merge/archive 的 git 网络往返耗时优化（~8 min 为流程刚性成本）。

## 治理工具链——prompt 对齐 crctl（v0.22 · CR-2026-021）

## PRD — prompt 对齐 crctl（写入面补齐 + prompt 收敛 + 漂移防线）

### 1. 概述

#### 1.1 问题陈述

crctl（CR-2026-019 账本子命令 / CR-2026-020 回写脚本）与 `controlled-shell` 的 PreToolUse guard 的能力扩张跑在了 SKILL/pipeline prompt 前面，导致两类问题：

**guard 锁死但无工具出口（孤儿写入）**：`rules.json#protectedPaths.deny` 锁死 `_backlog.yml`（整文件）、`review-annotations/*.yml`、`cr.md`、`approval.yml`、`review-loop.yml`、`_history.yml`，但 crctl 现有写口只覆盖其中一部分。`_backlog` 的 `prd-path`/`owners`/`checkpoints`/`remote-ref`/`notify-log` 字段、`review-annotations/{stage}.yml` 整文件、`approval.yml` 的 `supplemental-reviews[]` 段均属 deny 但无对应 crctl 写命令——prompt 只能手写这些文件，当场被 guard 拦截。生命周期最前端的 CR-ID/TASK-ID 顺序分配同样无 CAS 保护，并发注册会撞号。

**已有工具但 prompt 未采纳（漂移）**：20+ SKILL/pipeline prompt 仍手把手教手动操作——手写 `approval.yml`、裸 `git` 命令、引用已被 `crctl advance` 取代的 `cr-status-set`、按已作废的 6 字段口径校验 `merge-commits`——即便 crctl 已提供对应能力。此漂移积累了三个 CR（CR-2026-019/020/021）才被审计发现，说明"清理一次"不治本，需要机械化的漂移检测防线，而非再靠人工记性。

#### 1.2 解决方案摘要

分两大块，①先行、②依赖①：

**① crctl 补齐写入面**：新增 purpose-specific、字段白名单的子命令族（而非通用 `patch`，避免退化为绕过治理模型的第二条不受控写入通道），每个自带前置态守卫 + CAS + 审计，与现有 `task done`/`merge-metadata`/`archive-move` 同构。共 9 个写子命令（`review-record`/`review-note`/`checkpoint-add`/`owner-set`/`backlog-set`/`next-cr-id`/`task allocate`/`cr-init`/`inbox-emit`）+ 2 个只读子命令（`worktree-path`/`report`+`cr-metrics`）+ 1 处既有 `git commit` 扩展（`--template`）。`next-cr-id`/`cr-init` 因处于同一注册流程相邻两步，合并实现共享一个 `casWrite` 事务。`review-record` 采用"判断/写入分离"：agent 把评审判断写成非受控临时 payload，crctl 只做 schema 校验后的确定性 canonical 写入。PRD/SDD schema 校验（`validate-doc`）不直接开新命令，先溯源调查 engineering-docs 的 `prd.schema.json`/`sdd.schema.json` 在 v0.4.0 下线的原因，再决定复活路线或维持现状。

**② prompt 分阶段收敛为调用 crctl**：不依赖新命令、当场会失败的问题（`merge-commits` 字段口径、`approve-*` 手写 `approval.yml`、裸 `git`、`test-report.md` frontmatter）先改（Phase 1）；`cr-status-set` 全仓系统性清退（Phase 2）；依赖新子命令的账本写入迁移到 Phase 0 产出的命令（Phase 3）；冗余精简与文档 staleness 收尾（Phase 4）。

**③ 根治机制**：新增 `lint-prompts` 漂移 linter（R1~R6 规则，判据直接读 `rules.json`/`crctl.mjs` 源码，不设专门的能力快照测试——git diff 本身就是"crctl 能力面变了"的信号）接入 pre-commit 钩子（提交时拦截）与 feature-writeback 归档前 gate（CI 侧兜底）两层机械防线；linter 覆盖不到的"crctl 新增能力、某 skill 该采纳但还没采纳"这类，交由 SDD 强制小节 + 评审兜底的人工残余清单项承接。

#### 1.3 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| `rules.json#protectedPaths.deny` 锁死 `_backlog.yml`/`review-annotations/*.yml`/`cr.md`/`approval.yml`/`review-loop.yml`/`_history.yml` 六类文件 | `tools/skills/shared/controlled-shell/rules.json` |
| crctl 现有写口（`advance`/`approve`/`attempt`/`merge-metadata`/`archive-move`）已覆盖 `cr.md` status、`approval.yml` 门禁段、`review-loop.yml`、`_backlog` merge-commits/归档移除、`_history.yml`；`_backlog` 的 prd-path/owners/checkpoints/notify-log 与整个 `review-annotations/{stage}.yml` 无写口 | `crctl.mjs` dispatch（`status`/`gate`/`advance`/`approve`/`validate`/`attempt`/`task`/`merge-metadata`/`archive-move`/`test`/`next`/`migrate-backlog`/`git`） |
| review-annotations 文件名与评审阶段非同名映射：`requirement`→`requirement.yml`、`tech-design`→**`sdd.yml`**（非 `tech-design.yml`）、`code`→`code.yml`，门禁读取即按此口径 | `crctl.mjs:1230,1524,1534,1549/1554` |
| `requirement-register/SKILL.md:48` 由 agent 读 `_index.yml` 扫最大编号手算 `+1` 分配 CR-ID，无 CAS，并发注册可撞号；`:53-97` 全量手写 cr.md 初始 frontmatter；`:127-133` 手工拼接 worktree bucket/path；`:114` 手拼 commit message | `requirement-register/SKILL.md` |
| `write-dev-tasks/SKILL.md:45,64` 手动顺序分配 TASK-ID 并拼 slug 兜底命名；`:80` 手拼 commit message；`:87` 手动加总 TASK 估时 | `write-dev-tasks/SKILL.md` |
| `merge-feature-branch`/`push-progress`/`resume-from-remote` 各自用 prose 重复描述同一条 worktree 拼接规则（4+ 处） | 对应 SKILL.md |
| `cr-dashboard`/`spec-dashboard` Step 2 手动统计状态直方图/SLA 阈值/周期活动计数 | 对应 SKILL.md |
| `validate-doc/SKILL.md` 教 agent 用眼睛核对 PRD/SDD frontmatter/命名/路径；engineering-docs 自带 `prd.schema.json`/`sdd.schema.json` + `validateFrontmatter`/`validateNaming` 在 v0.4.0 已下线，下线原因未知 | `validate-doc/SKILL.md`；engineering-docs 包 |
| 生产者（`merge-feature-branch`/FR-8）已产出 `merge-commits` 3 字段 `{repo,trunk,sha}`（branch 可选），但 `writeback-traceability/SKILL.md:84,107,120`、`feature-writeback.pipeline.json` node-4:67 仍按旧 6 字段校验，必然失败 | 对应 SKILL.md / pipeline JSON |
| `resume-cr` node-1:40 用裸 `git ls-remote --heads origin 'requirement/...'` 带分支名参数，但 `controlled-shell/rules.json#git` 当前只放行 `^--heads origin$`（不带参数固定形态）——迁移到 `crctl git` 前必须先补白名单 shape，否则当场被拒 | `rules.json#git`；`resume-cr/SKILL.md` node-1 |
| `cr-status-set` 已被 `crctl advance` 取代，但 `approve-*`、`review-code:132-133`、`review-tech-design:95`、`review-requirement:111`、`write-dev-tasks:79`、`cr-review-record:53-54`、`cr-archive:54` 仍引用 | 对应 SKILL.md |
| `resume-cr` node-3 与 `resume-from-remote:99-113` 各自硬编码一张 status→下一节点映射表，`crctl next` 已存在但未被两处采纳 | 对应 SKILL.md / pipeline JSON |
| tools 仓 `.githooks/pre-commit` 已有先例：每次 commit 跑 `check-skill-matrix.mjs` + `check-agents-contract.mjs`，新增检查项成本低 | `tools/.githooks/pre-commit` |
| 本次漂移历时 CR-2026-019/020/021 三个 CR 才被审计发现（`docs/analysis/tools包-prompt过时冗余审计.md`），证明纯人工"记得扫一遍"不可持续 | `docs/analysis/tools包-prompt过时冗余审计.md` |

### 2. 用户故事

- **US-1** 作为评审 agent，我执行 `crctl review-record` 把评审判断写入 `review-annotations/{stage}.yml`，不再被 guard 当场拦截，也不再有 stage→文件名映射错误导致门禁读不到评审结论的风险。
- **US-2** 作为评审流程的执行者，我用 `crctl review-note` 追加 `approval.yml` 的 `supplemental-reviews[]`，不再手写受控文件。
- **US-3** 作为推送进度的维护者，我用 `crctl checkpoint-add` 记录推送元数据（checkpoints/remote-ref/last-push），不再手改 `_backlog`。
- **US-4** 作为交接 CR 的维护者，我用 `crctl owner-set` 变更 owners 字段，不再手改 `_backlog`。
- **US-5** 作为登记 PRD 路径的维护者，我用 `crctl backlog-set --field prd-path` 写入白名单标量字段，不误碰 status/owners/merge-commits 等有专命令的字段。
- **US-6** 作为发起新 CR 注册的 agent，我用 `crctl next-cr-id` 拿到 CAS 保护的编号、用 `crctl cr-init` 生成初始 `cr.md`，不再手算 max+1、不再有并发撞号风险。
- **US-7** 作为拆分开发任务的 agent，我用 `crctl task allocate` 拿到 CAS 保护的 TASK-ID 与 slug，不再手动顺序分配。
- **US-8** 作为多处需要 worktree 路径的 SKILL 作者，我调用 `crctl worktree-path` 得到统一派生结果，不再各自维护一份拼接 prose。
- **US-9** 作为需要生成 commit message 的 agent，我用 `crctl git commit --template <kind>` 得到规范格式，不再各自拼 prose。
- **US-10** 作为查看治理仪表盘的维护者，我用 `crctl report`/`crctl cr-metrics` 得到跨 CR 统计，不再手动统计状态直方图/SLA。
- **US-11** 作为发起 inbox 通知的 agent，我用 `crctl inbox-emit` 追加 notify-log，不再手写 `_backlog`。
- **US-12** 作为处理 PRD/SDD 校验的维护者，我知道 `validate-doc` 是否应复活 engineering-docs 的 schema validator 有明确结论（复活或记录暂缓原因），不必臆测。
- **US-13** 作为执行 Phase 1~3 prompt 改造的维护者，我改完的 SKILL/pipeline 不再有 `merge-commits` 6 字段校验、手写 `approval.yml`、裸 `git`、`cr-status-set` 引用等会当场失败或已被取代的操作。
- **US-14** 作为治理工具链的维护者，我在 pre-commit 阶段就能拦住"prompt 又开始教手写 deny 文件/裸 git/引用 deprecated 机制"的漂移，不必等下一次人工审计才发现。
- **US-15** 作为归档 CR 的评审者，我在 CR 归档前有一道 `lint-prompts` gate 兜底，即使有人绕开本地 pre-commit 钩子，漂移的 prompt 也无法归档。
- **US-16** 作为 SDD 撰写者，当我的 CR 改动了 `crctl.mjs` dispatch 或 `rules.json` deny 面时，我在 SDD 中有一个强制小节列出"应改为调用新命令的 skill 清单"，不靠回写期临时记性。

### 3. 功能需求

#### Phase 0：crctl 写入面补齐（前置）

- **FR-1（`crctl review-record`）**：`review-record <cr> --stage <requirement|tech-design|code> --from <payload.yml> [--bump-attempt]`。schema 校验 payload（`verdict∈{pass,block}`、`blockers` 为列表、`dimensions` 齐全）后写入对应文件（CAS+审计），可选级联 `attempt`。stage→文件名映射显式实现为 `requirement`→`review-annotations/requirement.yml`、`tech-design`→`review-annotations/sdd.yml`、`code`→`review-annotations/code.yml`，与门禁读取口径一致。payload 落点统一为非受控的 `.crctl/tmp/review-{stage}.yml`（`.gitignore` 补一条 `.crctl/tmp/`），消费成功后自动删除，避免残留误提交或跨 CR 串味。
- **FR-2（`crctl review-note`）**：`review-note <cr> [--stage <s>] --note <text>`。向 `approval.yml` 的 `supplemental-reviews[]` 追加一条记录（CAS+审计）；操作者身份由 crctl `identity(ws)` 生成，不接受 `--by` 参数。
- **FR-3（`crctl checkpoint-add`）**：`checkpoint-add <cr> --repo <r> --sha <sha> [--remote-ref <ref>]`。`_backlog` 条目 `checkpoints[]` 追加 + 更新 `remote-ref`/`last-push-at`（crctl 生成）/`last-push-by`（identity）。
- **FR-4（`crctl owner-set`）**：`owner-set <cr> --role <requirement|development|test> --id <id>`。写 `_backlog` 条目 `owners.{role}.id` + `assigned-at`（crctl 生成）；`--id` 是被指派人身份（业务数据），由调用方传入，不违反"操作者身份必须 crctl 生成"原则。
- **FR-5（`crctl backlog-set`）**：`backlog-set <cr> --field <name> --value <v>`。白名单标量字段：仅 `prd-path`、`sdd-path`（及未来静态注册字段）；硬拒 `status`/`updated-at`/`owners`/`merge-commits`（各有专命令）。
- **FR-6（`crctl inbox-emit`）**：`inbox-emit <cr> --event ...`。专命令处理 `_backlog` 的 `notify-log`/`notify-pending` 事件追加（不复用 `backlog-set`，因事件追加语义比标量 set 重）。
- **FR-7（`crctl next-cr-id` + `crctl cr-init`，合并实现）**：`next-cr-id [--year Y]` 做 CAS 保护的 CR-ID 分配（读 `_index.yml`/`_backlog.yml` 现有最大编号抢占式返回下一个，并发请求失败重试不撞号）；`cr-init <cr-id> --title <t> --owner-requirement <id>` 生成初始 `cr.md`（owners/owner-history/时间戳全部 crctl 生成）+ 级联首次登记进 `_backlog`。二者共享同一个 `casWrite` 事务，减少中间态窗口。
- **FR-8（`crctl task allocate`）**：`task allocate <cr> [--slug <s>]`，扩展现有 `task` 子命令族。CAS 保护的 TASK-ID 分配，`TASK-{NN}` + slug 兜底命名。
- **FR-9（`crctl worktree-path`，只读）**：`worktree-path <cr> --repo <r>`。只读派生输出 worktree bucket/path（`role==knowledge-base?"knowledge-base":repo.id` + 固定模板拼接），不写文件、无需 CAS。
- **FR-10（`crctl git commit --template`，既有命令扩展）**：给现有 `git commit` 加 `--template <kind>` 分支（`register`/`task-breakdown`/`writeback`/…），按 kind 生成规范 commit message。不是新增顶层子命令，同现有 git commit 白名单前置态。
- **FR-11（`crctl report` / `crctl cr-metrics`，只读）**：跨 CR 状态直方图、SLA 阈值比较、周期活动计数聚合，`--period P` 可选。
- **FR-12（D13 溯源调查与条件实现）**：Phase 0 门槛任务，可与 FR-1~FR-11 并行：① 查 engineering-docs `v0.4.0` changelog/commit 历史，确认 `prd.schema.json`/`sdd.schema.json` + `validateFrontmatter`/`validateNaming` 下线的具体原因；② 若原因已解决或不再成立，复活并二选一：(a) 并入 `crctl validate --doc-type prd|sdd`，或 (b) `validate-doc` 改为直接调用 engineering-docs 自身 CLI（更合适，PRD/SDD 校验不属于 CR 账本类产物）；③ 若原因仍成立，本轮不复活，在 SDD 中记录排查结论（已排查、暂缓、原因 XXX），不写代码。
- **FR-13（配套：文档更新 + 白名单补齐）**：更新 `crctl help`、`ARCHITECTURE.md §3 code map`、`skills/_index.yml:274` 的 crctl brief（补全 CR-2026-019 已加但漏列的 `task done`/`merge-metadata`/`archive-move`/`migrate-backlog` + 本轮全部新增/扩展子命令）；逐条核对 Phase 1-C 待迁移的裸 git 命令是否已在 `controlled-shell/rules.json#git` 白名单内，补齐缺失 shape（含 `ls-remote` 带分支参数的形态）。

#### Phase 1：P0 prompt 修正（不依赖新命令，当场会失败）

- **FR-14（D7 merge-commits 3 字段）**：`writeback-traceability/SKILL.md:84,107,120`、`feature-writeback.pipeline.json` node-4:67 的 6 字段校验改为 `{repo,trunk,sha}` 必填、`branch` 可选。
- **FR-15（approve-* 折叠为 `crctl approve`）**：`approve-code`/`approve-tech-design`/`approve-dev-start`/`approve-requirement` 删手写 `approval.yml` 段、删 `cr-status-set` 步、删"回滚 approval.yml"错误处理，改为运行 `crctl approve --stage X`（TTY），由其校验证据、写 `approval.yml`、级联 `advance`。
- **FR-16（裸 git → `crctl git`）**：`review-code:37-42`、`write-dev-plan:58-60`、`write-dev-tasks:81`、`writeback-{prd-sdd,tasks,traceability}` 提交步、`resume-cr` node-1:40 一律改 `crctl git <sub> --cwd`；改前逐条核对 `rules.json#git` shape 白名单是否已放行目标命令，缺的随 FR-13 一并补齐。
- **FR-17（D3 test-report frontmatter）**：`write-test-report:51-84` 的 frontmatter 交 `crctl test --cmd` 生成，模型只写 `<!-- crctl:analysis-below -->` 以下分析段。

#### Phase 2：系统性清理 `cr-status-set`

- **FR-18**：`cr-status-set/SKILL.md` 标注 legacy/deprecated，正文改述"状态推进见 crctl advance"，保留仅为历史兼容。全仓引用（`approve-*`/`review-code:132-133`/`review-tech-design:95`/`review-requirement:111`/`write-dev-tasks:79`/`cr-review-record:53-54`/`cr-archive:54`）改指 `crctl advance --to X --trigger Y --expect Z`。`cr-archive/SKILL.md:84-93` 删 Step 5 手写 `_index.yml`（`archive-move` 已一并更新）与 `:92` 手改 status。

#### Phase 3：账本写入改走新子命令（依赖 Phase 0）

- **FR-19**：`review-code`/`review-tech-design`/`review-requirement` 改调 `crctl review-record`（FR-1）；`write-test-report` 改调 `crctl attempt`；`cr-review-record` 改调 `crctl review-note`（FR-2），reject/withdraw 走 `advance`，重新定位该 skill 为"补充意见记录 + 状态推进转发"；`handover-cr:66-68`/`resume-from-remote:86` 改调 `crctl owner-set`（FR-4）；`push-progress:63-77` 改调 `crctl checkpoint-add`（FR-3）；`write-requirement-prd:87-89` 改调 `crctl backlog-set --field prd-path`（FR-5）；`inbox-emit` 改调 `crctl inbox-emit`（FR-6）；`requirement-register:48` 改调 `crctl next-cr-id`（FR-7）；`write-dev-tasks:45,64` 改调 `crctl task allocate`（FR-8）；`requirement-register:53-97` 改调 `crctl cr-init`（FR-7）；`requirement-register:127-133`/`merge-feature-branch`/`push-progress`/`resume-from-remote` 改调 `crctl worktree-path`（FR-9）；`requirement-register:114`/`write-dev-tasks:80`/`writeback-traceability:75` 改调 `crctl git commit --template`（FR-10）；`cr-dashboard`/`spec-dashboard` Step 2 改调 `crctl report`/`crctl cr-metrics`（FR-11）；`validate-doc` 视 FR-12 结论决定是否及如何改。

#### Phase 4：冗余精简 + 文档 staleness

- **FR-20（D8 状态映射去重）**：`resume-cr` node-3、`resume-from-remote:99-113`、`pull-progress:64-66`、`implement-code:67` 收敛为"跑 `crctl status`（含 STATUS_DIVERGED）+ `crctl next`"，删两处重复硬编码状态表。
- **FR-21（D15 工时求和精简）**：`write-dev-tasks:87` 手动加总 TASK 估时的措辞改为"按 TASK 列表求和"一句话带过或直接删，不开新命令。
- **FR-22（其余冗余）**：`feature-writeback.pipeline.json` inputs/node-2/node-3 冗长"必须显式提供否则空路径" prose 精简（缺参现 BAD_ARGS fail-fast 兜底）；`skills/_index.yml` 各 brief 补齐（含全部新增/扩展子命令）；`AGENTS.md（主仓）#6` 把"cp 覆盖"危害降为历史注脚；writeback 系 brief 补提 CR-2026-020 脚本。

#### 根治机制：prompt↔crctl 漂移防线（归入 Phase 0）

- **FR-23（`lint-prompts` 漂移 linter）**：新增 `crctl lint-prompts`（或独立 `lint-prompts.mjs`，复用 `check-agents-contract.mjs` 模式），扫 `skills/**/SKILL.md` + `pipeline-templates/*.json` 的 prompt 串，按 R1~R6 规则集判漂移，命中即输出 `file:line` + 规则 + 非零退出：

  | 规则 | 检测 | 判据来源 | 级别 |
  |---|---|---|---|
  | R1 手写 guard-deny 文件 | 指示 write/create/编辑 deny 文件，且附近无对应 `crctl <cmd>` 调用 | `rules.json` deny 面（直读） | CONTRADICTS |
  | R2 裸 git | prompt 内 `git <sub>` 字面且非 `crctl git` | `rules.json#git` | CONTRADICTS |
  | R3 引用 deprecated 机制 | 出现 `cr-status-set` | `crctl advance` 已取代 | STALE-REF |
  | R4 merge-commits 过时口径 | `source-sha`/`merged-at`/"六字段"作为必填 | FR-8（CR-2026-020）契约 | CONTRADICTS |
  | R5 手写 review-loop 记账 | `review-loop.current-attempt`/`attempts[]` 配合 write/持久化动词 | `crctl attempt` 独占 | OUTDATED |
  | R6 手写 test-report frontmatter | `test-report.md` 配合手写 `status:`/`commands:` | `crctl test` 生成 | CONTRADICTS |

  判据直接读 `rules.json`/`crctl.mjs` 源码，不经过任何派生快照（`crctl capabilities` 之类），与 crctl 能力面变更天然解耦——deny 面/dispatch 改了，linter 判据自动跟着变。R1 用"提及 deny 文件写动作且同段无 crctl 调用"的邻近判定而非裸关键词，避免"教手写"和"解释为什么不该手写"的说明性文本混淆。提供显式豁免：`<!-- lint-prompts:ignore -->` 注释使 linter 跳过该段落检测。
- **FR-24（两层机械防线接入，分阶段启用）**：`lint-prompts` 接入两处 gate，但**强制阻断模式的启用有严格时序，避免与 Phase 0→3 依赖顺序自举冲突**：
  - **pre-commit 钩子**（tools 仓 `.githooks/pre-commit`，已有 `check-skill-matrix`/`check-agents-contract` 先例）：**Phase 0~2 期间以 report-only / warn 非阻断模式运行**（输出 `file:line` 漂移清单但不 fail 提交），使本 CR 自身开发期（含 tools 仓 crctl.mjs/skills/pipeline 的增量提交）不被尚未清理的存量漂移拦死；**Phase 3 漂移清零后转为硬阻断模式**，此后漂移提交不进来。
  - **feature-writeback 归档 gate**（cr-guard 或归档前 passCondition）：CR 归档前 `lint-prompts` 必须 pass。此 gate 不受上述分阶段影响——归档必然发生在 Phase 3 漂移清零之后，天然安全，作为兜住绕过本地钩子的 CI 侧兜底。
  - 不设专门的"crctl 能力快照测试"层——git diff 本身即"能力面变了"的信号。
- **FR-25（人工残余回写清单项）**：feature-writeback 回写清单新增一条：「本 CR 若 diff 触及 `crctl.mjs` 的 dispatch 或 `rules.json` 的 `protectedPaths.deny`：① 跑 `crctl lint-prompts` 清零 CONTRADICTS/STALE；② 对新增子命令，在 SDD『prompt 采纳影响』小节列出应改为调用它的 skill 清单并逐一改，由评审兜底。」该清单项承接 linter 抓不到的"新增能力未被采纳"类漂移。

### 4. 非功能需求

- **NFR-1（前置态守卫一致性）**：所有新写子命令必须复用现有 `matchEntryBlock` + `casWrite`/`casWriteMulti` + `auditLog` + `nowIso`，与既有 `task done`/`merge-metadata`/`archive-move` 同一前置态校验模式，不引入第二套写入范式。
- **NFR-2（时间戳/身份一律 crctl 生成）**：所有操作者身份（`--by` 类）与时间戳字段一律由 crctl 内部生成（`identity(ws)`/`nowIso()`），拒绝调用方传入；仅"指派给谁"这类业务身份（如 `owner-set --id`）例外，由调用方传入。
- **NFR-3（不做通用 patch）**：不提供 `crctl patch <file> <dotpath> <value>` 或等价的任意路径写入通道；所有写口均为 purpose-specific + 字段白名单。
- **NFR-4（零新增第三方依赖）**：新增子命令与 `lint-prompts` 均只用 Node 标准库与 crctl 既有工具函数。
- **NFR-5（只读命令无副作用）**：`worktree-path`/`report`/`cr-metrics` 不修改任何受保护文件，不需要 CAS/审计。
- **NFR-6（linter 判据零派生物）**：`lint-prompts` 的判据直接读源文件（`rules.json`/`crctl.mjs`），不依赖任何需要手工同步维护的中间快照/生成物。
- **NFR-7（CAS 并发安全）**：`next-cr-id`/`task allocate` 在并发调用下必须通过重试机制保证不产生重复编号（撞号）。

### 5. 验收标准

- **AC-1**（FR-1）：对同一 stage 连续两次调用 `review-record`（一次 requirement、一次 tech-design），生成的文件分别是 `review-annotations/requirement.yml` 与 `review-annotations/sdd.yml`（非 `tech-design.yml`）；payload 中 `verdict` 非法值时非零退出且不写入；成功后 `.crctl/tmp/review-{stage}.yml` 被自动删除。
- **AC-2**（FR-2）：调用 `review-note` 后 `approval.yml.supplemental-reviews[]` 追加一条含操作者身份（crctl 生成）的记录；传入 `--by` 参数报错拒绝。
- **AC-3**（FR-3/FR-4/FR-5/FR-6）：`checkpoint-add`/`owner-set`/`backlog-set`/`inbox-emit` 分别正确更新 `_backlog` 对应字段；`backlog-set --field status` 硬拒（非零退出，提示改用 `advance`）。
- **AC-4**（FR-7）：并发调用 `next-cr-id` 两次，两次返回不同编号（无撞号）；`cr-init` 生成的 `cr.md` frontmatter 完整（owners/owner-history/时间戳）且已登记进 `_backlog`。
- **AC-5**（FR-8）：并发调用 `task allocate` 两次，TASK-ID 不重复；slug 缺失时按兜底命名生成。
- **AC-6**（FR-9/FR-10/FR-11）：`worktree-path` 给定输入返回确定性路径且不写任何文件；`git commit --template register` 生成的 message 符合约定格式；`report`/`cr-metrics` 输出的统计与手动核对的账本状态一致。
- **AC-7**（FR-12）：D13 溯源结论已写入 SDD（复活路线或暂缓原因二选一），若选择复活，对应 `crctl validate --doc-type` 或 `validate-doc` 改调用行为已实现并有测试。
- **AC-8**（FR-13）：`crctl help` 输出含全部新增/扩展子命令；`rules.json#git` 白名单已补齐 Phase 1-C 迁移所需的全部裸 git shape（含 `ls-remote` 带分支参数形态）。
- **AC-9**（FR-14~FR-17，Phase 1）：`writeback-traceability` 对 3 字段 `merge-commits` payload 校验通过；`approve-*` 系列 SKILL.md 不再含手写 `approval.yml` 的 YAML 段；Phase 1-C 覆盖的裸 git 命令全部替换为 `crctl git`；`write-test-report` 不再手写 frontmatter。
- **AC-10**（FR-18，Phase 2）：`grep -r "cr-status-set"` 除 `cr-status-set/SKILL.md` 自身的 legacy 说明外无其他 SKILL 引用；`cr-archive/SKILL.md` 不含手写 `_index.yml`/status 的步骤。
- **AC-11**（FR-19，Phase 3）：Phase 3 表内列出的每个文件均已改调对应新子命令，`grep` 相应 SKILL.md 不再含手写受控文件的指引。
- **AC-12**（FR-20~FR-22，Phase 4）：`resume-cr`/`resume-from-remote`/`pull-progress`/`implement-code` 不再各自硬编码状态映射表；`write-dev-tasks:87` 措辞已精简；`skills/_index.yml` brief 含全部新增子命令。
- **AC-13**（FR-23）：对 6 类规则各构造一个已知漂移的 fixture prompt，`lint-prompts` 全部命中且输出 `file:line`；对含 `<!-- lint-prompts:ignore -->` 的段落不误报；对 Phase 1~3 改造完成后的仓库运行 `lint-prompts`，CONTRADICTS/STALE-REF 计数为 0。
- **AC-14**（FR-24）：`.githooks/pre-commit` 新增 `lint-prompts` 步骤；**Phase 0~2 期间对 tools 仓的 commit（即使存量漂移未清）不被阻断**（report-only 模式，非零退出仅出现在归档 gate）；**Phase 3 漂移清零并将钩子转为硬阻断模式后**，构造一个带漂移的 commit 尝试被本地钩子拦截（非零退出）；feature-writeback 归档前 passCondition 含 `lint-prompts` 校验，任意阶段带漂移的 CR 无法归档。
- **AC-15**（FR-25）：feature-writeback 回写清单模板中存在该新增条目文本；对一个 diff 触及 `crctl.mjs` dispatch 的测试 CR，SDD 模板渲染出"prompt 采纳影响"小节。

### 6. 成功指标

- crctl 写入面与 guard deny 面完全对齐：`grep` `rules.json#protectedPaths.deny` 六类文件，每一类都有对应 crctl 写口（无孤儿写入）。
- 全仓 `lint-prompts` 扫描 CONTRADICTS/STALE-REF 计数为 0（Phase 1~3 改造完成后）。
- CR-ID/TASK-ID 分配从"手算 + 无 CAS"变为 100% 走 `next-cr-id`/`task allocate`，并发注册不再有撞号风险（此前为已知风险，未发生过真实撞号事故，但无防护）。
- 下一次 prompt↔crctl 漂移不再需要等到"审计三个 CR 后才发现"——pre-commit 与归档 gate 在漂移引入的第一次 commit/归档即拦截。

### 7. 范围排除

**本 CR 包含**：Phase 0（crctl 新增 9 个写子命令 + 2 个只读子命令 + 1 处既有命令扩展 + D13 溯源调查）+ Phase 1~4（全部 SKILL/pipeline prompt 收敛）+ `lint-prompts` 漂移 linter + 两层机械防线接入（pre-commit + feature-writeback gate）+ 人工残余回写清单项。D9~D16 已按决定并入本轮单次施工，不再拆分下一轮。

**本 CR 不包含**：
- 通用 `crctl patch <file> <dotpath> <value>` 命令（已否决，见 §1.1/NFR-3）。
- `crctl capabilities` 派生快照测试层（已在方案中砍除，git diff 本身即触发信号，见 FR-24）。
- D13 若溯源结论为"不复活"，则不实现 PRD/SDD schema 校验代码，仅记录排查结论。
- 账本状态机/CAS 基础设施本身的重新设计（复用 CR-2026-018/019 已定型的 `casWrite`/`casWriteMulti`/`auditLog` 机制，不改造）。
- 与本次治理无关的 crctl 既有子命令行为变更（`status`/`gate`/`validate`/`test`/`next`/`migrate-backlog` 等维持现状）。
- `merge-feature-branch` 的合并/补偿逻辑本身（CR-2026-020 已固化其 SKILL 事实基线，本 CR 不改）。

## 治理工具链 — tools 包 prompt 审查修复（97 条发现：批 2.5 crctl 核心缺陷修复 + checkpoint-add 承诺兑现 + approve 驳回回退 + lint R6/R7 与豁免修复 + 冗余收敛）（v0.23 · CR-2026-022）

## PRD — tools 包 prompt 审查修复（97 条发现全量落地）

### 1. 概述

#### 1.1 问题陈述

tools 包 prompt 审查（`docs/analysis/prompt-audit-report-2026-08-05.md`，97 条发现 = 原稿 75 + CR-2026-022 注册实录补 4 + 7 条流水线执行走查补 18）揭示的问题已从"文档写错了"升级为**crctl 代码本身存在没被兑现的承诺**：

- **命令串畸形与接口漂移**：12 处 `crctl advance` 坏形态命令串（全角分隔符、旗标用反引号包裹）、`inbox-emit` 函数式调用与缺必填字段，AI 照抄必失败、通知链实际断裂。
- **crctl 本体缺陷**（7 条流水线逐节点模拟执行走查坐实）：`push-progress` 从未真正调用它承诺的 `crctl checkpoint-add`（且 `LEGAL` 状态白名单覆盖不到 push-progress 实际被调用的阶段）；`cmdApprove` 的驳回分支从不执行状态机已声明的 `{stage}:reject -> write-{stage}` 回退转换，四个人工审批门禁驳回后无路可退；`gates.json` 的 `reviewLoops.review-planning-report` 是从未被任何门禁调用的死配置；`cr-init` 硬编码 `summary/source/target-version` 无旗标写口，逼出违纪手写 cr.md。
- **lint 防线自身有洞**：`lint-prompts` 不校验命令参数形态（R6/R7 缺位）；且 `<!-- lint-prompts:ignore -->` 豁免判断对整段 `node.prompt` 生效，一条无关豁免注释可连带放行 R5 违规。
- **死内容与大段样板重复**：`cr-status-set` 等废弃残留、8 类死引用/僵尸产物、多组逐字重复的样板（改一处要改 N 处）。

#### 1.2 解决方案摘要

按审查报告批次结构全量实施（批 1 → 2 → 2.5 → 3 → 3.5 → 4 → 收尾）：

1. **批 1/2**：零风险机械修正与死内容清理（纯文本）。
2. **批 2.5**（新，最高优先级）：crctl 核心能力补齐与缺陷修复，全部触发 ARCHITECTURE.md §8 评审门槛，合并成一份技术设计一次评审通过。
3. **批 3**：功能正确性修复（接口/枚举/结构约定对齐），功能断裂者优先。
4. **批 3.5**：lint 护栏先行（R6/R7 + 豁免范围 bug 修复），必须在批 4 之前落地。
5. **批 4**：冗余收敛，按「先对齐、必要才抽」原则；抽 push-progress 样板必须以批 2.5 修对为前提。
6. **收尾**：三台账同步 + 自检 + `crctl.test.mjs` 全量回归 + 端到端验收。

**范围口径（本 CR 的既定决策）**：审查报告「CR 必要性判据」一节建议批 1/2/3.5/4 可现场直改、不必走 CR；**本 CR 决定不采纳该分流建议——97 条发现全部在本 CR 内落地**，以获得统一的状态机追踪、评审记录与回写基线。报告 §三 的批次时序与前置约束（批 3.5 先于批 4、批 2.5 先于批 4 样板抽取等）仍全部遵守。

#### 1.3 报告遗留决策点（本 PRD 拍板）

报告中有三处"需要决策"的开放项，本 PRD 直接给出决定，SDD/实施期不得再次悬置：

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 需求阶段状态机是否新增 `requirement-reviewing:reject -> drafting` 转换 | **新增**该转换（`dir-graph.yaml` 状态机声明 + crctl approve decline 分支联动） | 与 tech-design/code 阶段对齐；"需求驳回=CR 死刑"过于刚性，打回重写 PRD 是常态诉求；`cr-review-record:reject → rejected` 仍保留为终止通道 |
| D-2 | review-planning-report 的 attempts 记账：接入 crctl 还是删死配置 | **删除 `gates.json` 死配置**，如实描述当前自行落盘机制（`docs/product-planning/review-annotations/{report-id}.yml`）；同步删除 `product-planning.pipeline.json:109` 的"必须持久化"失实承诺 | product-planning 全程主分支运行、无 CR 上下文，为它新开一条 crctl 持久化子命令收益不成比例 |
| D-3 | competitive-radar/market-to-plan 镜像节点 `onFail` 相反（skip vs abort） | **统一为 abort**；同时删除 competitive-radar 下游节点对 node-3.md 的写死读取依赖检查（abort 后不会读到空文件） | skip 分支读空文件的降级展示是额外复杂度，abort 语义与 human_approval 前置失败处理一致 |

另两处报告"建议评估"项，本 PRD 一并定案：**`write-insight-brief` 合并进 `extract-market-insight` 附加区块后下线**（唯一硬性增量 ≤800 字约束与 `raw→briefed` 状态推进并入）；**`run-competitive-analysis` Step4 摘要并入 `write-planning-report`「市场与竞品信号」章节后下线**该封装层。

#### 1.4 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| 12 处 `crctl advance` 坏形态命令串（8 个文件），权威旗标为 `--to <s> --trigger <t> [--expect <cur>] [--embedded]`，`--expect` 单值比较 | 审查报告 2.1-A；`crctl.mjs` `cmdAdvance`（`flags.expect !== current`） |
| `cmdCheckpointAdd` `LEGAL` 白名单仅 `['developing','code-reviewing','code-approved','merging','writing-back']`，不含 push-progress 实际被调用的 `drafting`/`task-breakdown` 等阶段 | `crctl.mjs:1578-1579` |
| `push-progress/SKILL.md` Step 2-3 全程只调 `runGit`，无一行 `checkpoint-add`；三条流水线节点 prompt 却写「经 crctl checkpoint-add 更新 _backlog」 | `push-progress/SKILL.md:47-81`；三条 pipeline JSON |
| `cmdApprove` 非 TTY-yes 分支只 `fail('APPROVAL_DECLINED')`，从不调用已声明的 `{stage}:reject -> write-{stage}` 回退转换；需求阶段状态机完全没有驳回转换 | `crctl.mjs:1072-1077`；`dir-graph.yaml:212-220` |
| `cmdCrInit` 硬编码 `summary:""`/`source:manual`/`target-version:tbd`；`BACKLOG_SET_FIELDS` 白名单仅 `prd-path\|sdd-path` | `crctl.mjs:1711-1751, 1564` |
| `resolveTemplateCr` 靠「分支探测→subject 正则兜底」反向解析 CR 号；注册场景在 master 分支必然落空（本 CR 注册实录首次提交即 BAD_ARGS） | `crctl.mjs:1953-1961`；`docs/analysis/CR-2026-022-注册流程复盘.md` |
| `architecture-design.pipeline.json` 5 个节点 UUID 前缀 `0014-*` 与 `resume-cr.pipeline.json` 撞号，且 `repairNodeId` 是 node-1 自引用 | `architecture-design.pipeline.json:36,45,51,74,82,91` |
| `lint-prompts` 豁免判断对整段 `node.prompt` 生效，`product-planning.pipeline.json:109` 一条无关豁免注释连带放行 R5 违规 | `lint-prompts.mjs:86-110` |
| `gates.json:100` `reviewLoops.review-planning-report` 从未被 `evaluatePassCondition`/`readAttempts` 引用（死配置） | `gates.json`；`crctl.mjs` |
| `cmdNext` 的 `writing-back` 分支检查开发期工作稿 `change-requests/{cr}/traceability.yml` 而非 writeback 产物 `specs/{spec_id}/traceability.yml`，误判"可归档" | `crctl.mjs` `cmdNext`（约 :2220） |

### 2. 用户故事

- **US-1** 作为执行任意 SKILL 的 agent，我照抄正文里的 `crctl advance` 命令串即可成功执行，不再撞上全角字符/反引号旗标导致的参数解析失败。
- **US-2** 作为推送进度的维护者，我照 `push-progress` SKILL 逐仓调用 `crctl checkpoint-add` 即完成记账，且在任何存在 push-progress 节点的非终态（含 `drafting`/`task-breakdown`）都不再炸 `ILLEGAL_LEDGER_STATE`。
- **US-3** 作为审批人，我在终端回答非 `yes` 时 CR 自动回退到前一阶段并提示重跑哪个 write skill，不再无路可退；需求阶段驳回可回到 `drafting` 重写 PRD。
- **US-4** 作为注册新 CR 的 agent，我用 `cr-init --summary --source [--target-version]` 一次原子写齐字段，用 `git commit --template register --cr <cr-id>` 直传已知 CR 号，不再违纪手写 cr.md、不再因 subject 缺编号首次提交失败。
- **US-5** 作为发起 inbox 通知的 agent，我按对齐后的 `inbox-emit` 接口（`cr-id`/`event`/`to`/`payload`）发送 `feedback-writeback-done` 与 `owner-handover` 事件，通知链真实可达。
- **US-6** 作为合并 feature 分支的执行者，merge 前有本地/远端 HEAD 一致性校验，不会把"缺最后一次提交"的远端分支合进 trunk。
- **US-7** 作为治理工具链维护者，`lint-prompts` 的 R6/R7 能拦住命令参数形态漂移，豁免注释不再连带放行无关违规行，批 4 大改动引入的新漂移不会无人发现。
- **US-8** 作为查阅 CR 进度的维护者，`cr-show`/`crctl next` 对 writeback 期状态给出正确建议，不再误判"可归档"。
- **US-9** 作为修改任一 prompt 的维护者，改完一处不再需要同步改 N 处逐字重复的样板；共享片段有 lint 引用一致性检查兜底。
- **US-10** 作为阅读 `agents/_index.yml`/`skills/_index.yml` 的维护者，台账不再有死引用、僵尸产物与长期挂空的 pending 能力。

### 3. 功能需求

#### 批 1 —— 零风险机械修正

- **FR-1（命令串畸形 12 处）**：按审查报告 2.1-A 目标形态修正 8 个文件的 12 处 `crctl advance` 命令串；其中 `review-requirement/SKILL.md:91` **省略 `--expect`**（需求阶段存在 `drafting→requirement-reviewing` 与自环两条合法转换，`--expect` 单值写死会误拒合法自环）。
- **FR-2（frontmatter 豁免注释外移）**：`review-code`/`requirement-register:17`/`implement-code:77` 共 3 处 `<!-- lint-prompts:ignore -->` 移出 YAML frontmatter / 删孤立行。
- **FR-3（死引用与措辞订正）**：删 `pipeline-templates/_index.yml:118` 的 `tools/old/` 死引用行；修 `agents/knowledge-agent.md:39` validate-doc 死路径为 `tools/skills/shared/validate-doc/SKILL.md`；requirement-register「三件事→四件事」编号补齐、merge-feature-branch「两阶段→四阶段」措辞澄清、spec-dashboard 状态分布表补齐六个漏列状态。

#### 批 2 —— 死内容清理

- **FR-4（cr-status-set 整体下线）**：删除 `skills/cr/cr-status-set/SKILL.md` 与 `skills/_index.yml:287` 条目；`skills/_index.yml:281` cr-review-record brief 改「经 crctl advance 推进」。
- **FR-5（validate-doc 订正）**：删除维度 2「gate 合规性」（无排期背书不留）；移除 writeback-* 写入后「自动调用本 Skill」的失实声明。
- **FR-6（focus-briefing 反向修）**：竞品报告过滤改为由 `write-competitive-report` 写索引时补 `status: new`、消费后翻转为 `seen`（不直接去掉过滤）；pipeline 注册表数据源先向运行时确认真实路径，确认不了即整体删除该可选数据源。
- **FR-7（降级路径与 pending 清空）**：`report-to-planning-suggestion` 补「目标运行时未提供 brainstorming 时直接委托 planning-draft」降级路径（不移除 external delegate）；`agents/_index.yml` 5 处 `pending` 能力清空为 `[]`（保留键不删）。
- **FR-8（record-adr 下线）**：确认 `constraints/adrs.yml` 无读者后，连 `record-adr` skill 一并删除。

#### 批 2.5 —— crctl 核心能力补齐与缺陷修复（一次设计评审过 ARCHITECTURE.md §8）

- **FR-9（cr-init 字段写口，2.1-F）**：`cr-init` 补 `--summary <s> --source <s> [--target-version <v>]` 三个可选旗标（缺省值与现硬编码同义，向后兼容），注册时一次原子写齐；删除 `requirement-register/SKILL.md:28` 的 `cr_id` 僵尸参数与其格式/占用校验。
- **FR-10（--template 显式 CR 号，2.1-F）**：`resolveTemplateCr` 补显式 `--cr <cr-id>` 旗标，优先取旗标值、跳过「分支探测→subject 正则」反向解析；原路径保留为兜底，不破坏存量调用。
- **FR-11（checkpoint-add 承诺兑现，2.1-G，一处改动惠及 3 条流水线）**：① `cmdCheckpointAdd` `LEGAL` 白名单扩至全部非终态：`drafting/requirement-reviewing/requirement-approved/tech-designing/tech-design-review-pending/tech-design-reviewed/task-breakdown/developing/code-reviewing/code-approved/merging/writing-back`（全量列出，不用枚举省略式）；② `push-progress/SKILL.md` Step 3 改为对每个 active repo 循环 `git rev-parse HEAD` + `crctl checkpoint-add --repo <r> --sha <sha>`，删除「展示 YAML 让人抄」；③ `code-implementation.pipeline.json` 节点 12 补齐 checkpoint-add 描述（与节点 3/8 一致）；④ 三条流水线 push-progress 节点 `onFail` 从 `skip` 改为产出可见告警（不 abort——git push 可能已成功）。
- **FR-12（approve 驳回回退，2.1-H）**：① `dir-graph.yaml` 新增 `requirement-reviewing:reject -> drafting` 转换（D-1 决策）；② `cmdApprove` decline 分支查表执行已声明的 `{stage}:reject -> write-{stage}` 回退转换并输出回退提示，无回退转换时才 `fail`；③ 四份 `approve-*/SKILL.md` 错误处理表补「审批人回答非 yes」分支（与状态机实际转换逐一对齐；approve-dev-start 现有"重跑 write-dev-plan"的不可达建议订正）；④ approve-requirement 改正"无旁路"表述为「交互式终端或 Ed25519 签名授权（`--grant`）二选一，两者都不可绕过审批本身」。
- **FR-13（review-loop 死配置，2.1-I）**：按 D-2 决策删除 `gates.json:100` 的 `review-planning-report` 死配置；`product-planning.pipeline.json:109` 删"必须持久化 review-loop.attempts"承诺、改为如实描述 skill 自行落盘 `docs/product-planning/review-annotations/{report-id}.yml` 的机制。
- **FR-14（fetch 失败降级，2.4 Step 5）**：`requirement-register/SKILL.md` 错误表补：单仓 `fetch` 失败时降级为「从本地 trunk 派生 worktree，并在摘要输出中标注 `STALE_BASE`」——不直接 abort，也不静默视为成功。

#### 批 3 —— 功能正确性修复（功能断裂者优先）

- **FR-15（inbox-emit 接口对齐，2.1-B）**：`feedback-writeback/SKILL.md:98-108` 迁到 `crctl inbox-emit <cr> --event feedback-writeback-done --to ... --payload ...` 形态（补必填 `to`，取值来源写明为 CR `owners.*.id` 或 feedback 发起人）；`handover-cr/SKILL.md:77-84` 补 `owner-handover` 事件并迁 CLI 形态（`subject/body` 进 payload）；`inbox-emit/SKILL.md` 三处同步补 `owner-handover`：触发意图列表 + 参数表 event 枚举 + 下游消费方声明。
- **FR-16（HEAD 一致性校验，2.1-J）**：`merge-feature-branch/SKILL.md` Step1.4 增加 `git rev-parse HEAD` vs `git rev-parse origin/requirement/{cr_id}` 比对，不一致时先要求 push-progress 补跑再合并。
- **FR-17（write-competitive-report 订正，2.1-K）**：`competitive-radar.pipeline.json` 节点 2 写入目标改为 `docs/competitive/reports/_index.yml`（与 SKILL 读写清单一致）；node-2 prompt 显式传 `confirmed=false` 出草稿，真正落盘挪到 human_approval 通过之后。
- **FR-18（pipeline UUID 撞号，2.1-C）**：`architecture-design.pipeline.json` 全部 5 个节点统一迁到未占用前缀 `0016-*`（不只改撞号的 3 个），同步 `repairNodeId` 自引用；改后跑 JSON 解析自检 + 两条流水线 seed 幂等验证。
- **FR-19（market-insights 索引统一，2.1-D）**：三个写入方统一目标 schema——顶层 `insights:`、type `MARKET_INSIGHT`、生命周期 `raw → briefed → published`、conduct-market-research 补 `file:` 字段、索引头补「单一事实源」声明；`market-to-plan.pipeline.json` 节点 5 的终态 `planned` 改为 `published` 并明确执行方；三份 SKILL.md 同一 commit 原子提交，若 `docs/market-insights/_index.yml` 有旧字段名历史数据则一次性迁移并在提交说明写清。
- **FR-20（sync owner 改调 crctl，2.1-E）**：`handover-cr` Step3/4 与 `resume-from-remote` Step4 的手写 owners 段统一改为调用 `crctl owner-set`。
- **FR-21（cmdNext 误判修复，2.4）**：`cmdNext` 的 `writing-back` 分支改查 writeback 产物 `specs/{spec_id}/traceability.yml`，不再以开发期工作稿判断"可归档"；`crctl.test.mjs` 补对应用例。
- **FR-22（cr-show 收敛）**：`cr-show/SKILL.md` 删硬编码 status→下一节点映射表，改调 `crctl next`（一步到位覆盖 merging/writing-back/archived/rejected/withdrawn）。
- **FR-23（planning 域歧义订正）**：`write-planning-report` SKIPPED 占位文案统一（部分跳过与全部跳过同一表述）；competitive-radar/market-to-plan 镜像节点 `onFail` 统一 abort（D-3 决策）；`report-to-planning-suggestion` 委托 planning-draft 参数改为如实传 `intent`/`context`；`market-to-plan.pipeline.json` 节点 3 输出格式描述改为 planning-draft 真实的 6 章节 DESIGN-DOC + P0-P2 优先级；`resume-cr.pipeline.json:44` 给 `list-remote-checkpoints` 补可选 `cr_id` 过滤参数并如实调用；`resume-from-remote` 错误表补「worktree 元数据残留（非 already-exists）」分支指引 `git worktree prune`；write-dev-plan 与 write-dev-tasks 工时估算补交叉校验（不一致 WARN）。

#### 批 3.5 —— lint 护栏先行（先于批 4）

- **FR-24（R6/R7 规则）**：`lint-prompts.mjs` 补 R6（`crctl advance` 必须匹配 `--to\s+\S+` 与 `--trigger`；`trigger=`/`expected_current_status=`/`commit_mode=`/全角 `，、）` 进 `LITERAL_BLACKLIST`；校验范围同时覆盖 `backlog-set` 字段白名单与 `--template` subject 编号规则）与 R7（函数式 `inbox-emit(` 直接判违例；CLI 形态校验 `--event` 取值属于 `inbox-emit/SKILL.md` 声明枚举）。
- **FR-25（豁免范围 bug 修复）**：`<!-- lint-prompts:ignore -->` 豁免判断从"整段 `node.prompt` 生效"收窄到"只豁免注释所在行的邻近范围"（`radius` 取值在测试向量中固化为契约）。
- **FR-26（测试向量）**：`lint-prompts.test.mjs` 补三类向量：R6 违规（全角字符/反引号旗标/缺 `--to` 或 `--trigger`）、R7 违规（函数式调用/枚举外 event）、豁免范围（豁免注释与违规行同段时违规行仍须命中，复现 `product-planning.pipeline.json:109` 场景）。

#### 批 4 —— 冗余收敛（先对齐、必要才抽）

- **FR-27（approve-* 四兄弟对齐）**：删 approve-dev-start 独有的「前置条件」节与「读取 AGENTS.md/dir-graph.yaml 解析路径」段，四者对齐一致；对齐后样板仍长才评估抽 `shared/approve-common`。
- **FR-28（writeback 三兄弟抽 shared）**：抽「writeback 脚本执行约定」（机械步骤由入库脚本执行 + `crctl git commit --template writeback` 骨架 + BAD_ARGS/CR_STATUS_MISMATCH/SELF_CHECK_FAILED 错误表）为一处引用。
- **FR-29（sync 免责收敛 + bucket 改调）**：「受控 shell + 禁手工指引 + SHELL_UNAVAILABLE」样板收敛到 `controlled-shell/SKILL.md` 单点引用，但各 skill 保留一行「SHELL_UNAVAILABLE 禁止降级为手工指引」摘要；bucket/worktreePath 计算三处改调 `crctl worktree-path`。
- **FR-30（台账冗余删除）**：删 `agents/_index.yml` 各 agent `constraints:` prose（机读台账只留 id/path/status/consumers/capabilities，禁止行为以 md 为唯一来源）。
- **FR-31（pipeline push-progress 样板抽取）**：三条流水线 push-progress 节点 prompt 抽成 push-progress skill 默认说明、节点只传差异参数；**前置：FR-11 已把 push-progress 本身修对**。
- **FR-32（评估项落地，D-3 后两项决策）**：`write-insight-brief` 合并进 `extract-market-insight` 附加区块后下线；`run-competitive-analysis` Step4 并入 `write-planning-report` 后下线；`list-remote-checkpoints`/`resume-from-remote` 存在性校验去重（节点 2 复用节点 1 结论）；`product-planning` 四调研节点「跳过检查」逻辑只在 SKILL.md 保留一份、pipeline node prompt 改引用。

#### 收尾 —— 台账同步与验收

- **FR-33（台账与自检）**：同步 `skills/_index.yml`/`agents/_index.yml`/`agent-skill-matrix.yml` 三台账；跑 `check-skill-matrix.mjs`；对改过 UUID/节点数的 pipeline 做 JSON 解析自检；批 2.5 落地后跑 `crctl.test.mjs` 全量回归（LEGAL 扩展与 decline 分支必须有测试覆盖新路径）。
- **FR-34（文档更新）**：按报告 §6.4 时机表更新 ARCHITECTURE.md §8 评审记录、`crctl/SKILL.md`（cr-init 新旗标与 `--cr` 旗标）、`lint-prompts.mjs` 头部规则说明、AGENTS.md 抽 shared 原则。

### 4. 非功能需求

- **NFR-1（评审门槛）**：批 2.5 全部项目（FR-9~FR-14）触发 ARCHITECTURE.md §8「crctl 新增写入子命令/状态机语义变化」评审门槛，合并为一份技术设计一次评审通过；SDD 必须包含报告 §四 参考实现骨架的取舍说明。
- **NFR-2（可回滚）**：批 2.5 所有 crctl.mjs 核心改动保持单 commit 可 revert；`dir-graph.yaml` 状态机改动前留存改前版本对照；不另制备份目录（git commit 本身即历史与审计）。
- **NFR-3（原子提交）**：FR-19 的三份 SKILL.md + 索引迁移必须同一 commit 原子提交；market-insights 旧字段历史数据迁移用入库版本化脚本，禁止会话内现写脚本（纪律 #7）。
- **NFR-4（护栏时序）**：FR-24~FR-26（批 3.5）必须先于批 4 落地；抽 shared 前先给 lint 补「shared 引用一致性」检查，防止把「N 处漂移」换成「引用失效」。
- **NFR-5（灰度）**：批 2.5 先以测试 CR（或一次完整演练注册，形式参照 CR-2026-019 AC-9）走通「push-progress → checkpoint-add 落账」「approve 驳回 → 回退转换」「cr-init 新旗标原子写入」三条新路径，验证通过后再对全部在途 CR 生效。
- **NFR-6（零新增第三方依赖）**：crctl.mjs 与 lint-prompts.mjs 改动只用 Node 标准库与既有工具函数。
- **NFR-7（行尾纪律）**：凡涉及哈希/跨行解析的新代码（lint 规则、测试向量）遵守纪律 #1：读入先 `\r\n → \n` 规范化，跨行匹配失败硬失败不静默降级。
- **NFR-8（multica 仓注释英文）**：本 CR 落点全部在 tools 仓，不涉 multica；若实施期发现需联动，先读其 CLAUDE.md。

### 5. 验收标准

- **AC-1**（FR-1）：12 处命令串逐一与报告 2.1-A 目标形态 diff 为空；`review-requirement` 在 `requirement-reviewing` 自环场景重跑不被 `CR_STATUS_CURRENT_MISMATCH` 误拒。
- **AC-2**（FR-2/FR-3）：三份 SKILL.md frontmatter 内无豁免注释；`grep "tools/old"` 在 pipeline-templates/_index.yml 零命中；knowledge-agent 引用的 validate-doc 路径真实存在。
- **AC-3**（FR-4~FR-8）：`grep -r "cr-status-set"` 除 lint 黑名单定义外零引用；validate-doc 无未执行维度与失实自动调用声明；focus-briefing 竞品过滤可命中（补 status 后）；`agents/_index.yml` 各 `pending` 为 `[]` 且键保留；record-adr/adrs.yml 删除前有"无读者"核实记录。
- **AC-4**（FR-9/FR-10）：`cr-init --summary S --source X --target-version v` 一次写齐三字段（缺省值与旧硬编码同义）；`git commit --template register --cr CR-2026-NNN` 在 master 分支直传成功、不触发反向解析；`requirement-register` 参数表无 `cr_id`。
- **AC-5**（FR-11）：在 `drafting`/`task-breakdown` 等非终态调用 `checkpoint-add` 成功落账；push-progress 按新 Step 3 执行后 `_backlog` checkpoints 与远端 SHA 一致；节点 12 prompt 含 checkpoint-add；三处 `onFail` 失败时产出可见告警且不 abort。
- **AC-6**（FR-12）：四个 stage 各模拟一次 decline，CR 分别回退到对应前一阶段（requirement 回 `drafting`）并输出重跑提示；四份 approve-* 错误表含该分支且与状态机一致；approve-requirement 无"无旁路"失实表述。
- **AC-7**（FR-13）：`gates.json` 无 `review-planning-report` 条目；`product-planning.pipeline.json` node-6 无"必须持久化"承诺、含自行落盘机制的准确描述。
- **AC-8**（FR-14）：模拟单仓 fetch 失败，注册流程从本地 trunk 派生 worktree 且摘要输出含 `STALE_BASE` 标记，不 abort。
- **AC-9**（FR-15）：`feedback-writeback-done` 与 `owner-handover` 各发送一次，接收方收件可见；inbox-emit/SKILL.md 三处（触发意图/参数表/消费方）均含 `owner-handover`。
- **AC-10**（FR-16）：构造本地 HEAD ≠ 远端 HEAD 场景，merge-feature-branch 在 Step1.4 拦截并提示补跑 push-progress，不执行合并。
- **AC-11**（FR-17）：competitive-radar 节点 2 写入目标为 `reports/_index.yml`；human_approval 驳回（abort）时无已落盘的报告/索引残留。
- **AC-12**（FR-18）：`architecture-design.pipeline.json` 5 节点全在 `0016-*` 前缀、`repairNodeId` 指向新 node-1；两条流水线 JSON 解析通过、seed 幂等（重复 seed 不产生重复节点）。
- **AC-13**（FR-19）：三个写入方按统一 schema 读写 `docs/market-insights/_index.yml` 互不破坏；索引头含单一事实源声明；market-to-plan 节点 5 终态为 `published`；三份 SKILL.md 在同一 commit。
- **AC-14**（FR-20）：handover-cr/resume-from-remote 不再手写 owners 字段，owner 变更全部经 `crctl owner-set` 落账。
- **AC-15**（FR-21/FR-22）：writeback-traceability 未跑时 `crctl next` 在 `writing-back` 态不建议归档；跑完后建议正确；cr-show 无硬编码映射表。
- **AC-16**（FR-23）：八项歧义订正逐条对照报告 2.4 目标形态验证通过；competitive-radar 镜像节点 `onFail` 统一 abort 且在提交说明中标注运行时行为变化。
- **AC-17**（FR-24~FR-26）：三类测试向量全部通过；故意注入全角字符命令串/函数式 inbox-emit/豁免同段 R5 违规行，R6/R7/R5 分别命中且不被连带豁免；对批 1/批 3 改动面复扫零误报。
- **AC-18**（FR-27~FR-32）：approve-* 四者结构一致；writeback 三兄弟引用同一 shared 片段；sync 各 skill 保留 SHELL_UNAVAILABLE 一行摘要；`agents/_index.yml` 无 constraints prose；push-progress 节点样板抽取后三流水线行为等价；write-insight-brief/run-competitive-analysis 下线后引用计数清零且下游（briefed 状态推进、市场信号章节）功能不丢失。
- **AC-19**（FR-33）：`check-skill-matrix.mjs` 通过；`crctl.test.mjs`/`lint-prompts.test.mjs` 全量绿；改过的 pipeline JSON 全部可解析。
- **AC-20**（端到端，报告 §6.2）：场景 1 完整 CR 生命周期串联通过（注册新旗标 → checkpoint-add 真被调用 → 需求驳回回退 → 代码驳回回退 developing → HEAD 不一致拦截 → writeback 未完不误判可归档）；场景 2 通知链两条事件可达；场景 3 lint 护栏三类违规命中。

### 6. 成功指标

- 97 条发现全部关闭（逐项对照报告清单勾验），无"现场直改绕过本 CR"的分流。
- 全仓 `lint-prompts` 扫描 R6/R7 命中数在本 CR 完成后收敛为 0，且豁免范围 bug 复现场景转为命中。
- `checkpoint-add` 在所有非终态可用；approve 驳回回退转换执行率 100%（状态机声明转换的 stage）。
- 注册新 CR 一次成功（cr-init 三字段一次写齐 + `--cr` 直传），不再复现本 CR 注册实录中的 BAD_ARGS 重试与违纪手写。

### 7. 范围排除

**本 CR 包含**：审查报告 97 条发现对应的批 1/2/2.5/3/3.5/4 全部修复项 + 收尾台账同步与端到端验收（报告「CR 必要性判据」建议的"批 1/2/3.5/4 可现场直改不走 CR"分流**不采纳**，全部纳入本 CR，见 §1.2 范围口径）。

**本 CR 不包含**：
- `controlled-shell/rules.json` 提交白名单新增"分析文档入库"形态（注册复盘缺陷 3，非纯 prompt、涉及三方消费的运行时放行行为，留待后续单独决策）。
- 为 product-planning 新开 crctl 持久化子命令（D-2 已决策为删死配置路线）。
- 账本状态机/CAS 基础设施本身的重新设计（复用既有 `casWrite`/`casWriteMulti`/`auditLog` 机制）。
- multica 仓 SSL 证书环境配置（运维事项，不入 CR）。
- 与本审查无关的 crctl 既有子命令行为变更（`status`/`gate`/`validate` 等维持现状；`cmdNext` 仅修 writing-back 判断依据这一只读 bug）。

## 治理工具链 — 代码评审 LLM 选择暂停节点 + R9 护栏（CR 上下文下一步收敛 crctl next）（v0.24 · CR-2026-023）

## PRD — 代码评审 LLM 选择暂停节点 + R9 护栏（两份分析方案合一落地）

### 1. 概述

#### 1.1 问题陈述

本 CR 合并两份分析文档（`docs/analysis/code-review-llm-selection-plan-2026-08-06.md` 与 `docs/analysis/review-skip-drift-and-r9-guard-2026-08-06.md`）揭示的两个 tools 包治理缺口：

- **问题 A（评审模型不可干预）**：code-implementation pipeline（`/coding`，12 节点）在节点 8（push-progress 统一 checkpoint）推送完成后**直接进入节点 9（review-code）自动评审**，中间没有任何暂停点。执行者无法决定由哪个 LLM/runner 执行评审；`pipeline inputs` 只能触发时预选，`code_generation` 的 runtime 选择机制又仅适用于节点 6 不适用 skill 节点——"评审前停下来让我选择"的诉求没有任何合法承载。
- **问题 B（需求期跳评审提示链漂移）**：观测到 CR 在写完 PRD 后有时未执行 `review-requirement` 就"进入下一环节"。逐层核查证实机器门禁 fail-closed 无旁路（`crctl advance` 进评审态有 GATE_BLOCKED 门禁、`crctl approve` 三重硬检查、passCondition 解析无 fail-open 路径）——**漂移发生在提示链层**：需求期各 skill 输出摘要手写「下一步」副本（D1 主因 `write-requirement-prd` 给出"review-requirement 或 push-progress"等价分叉、D2 `push-progress` 无下一步指引、D3 `requirement-writer` 映射表无前置条件、D4 reviewLoop 耗尽无机器停止、D5 未收敛到 `crctl next` 权威推荐）。全库 grep 证实 develop/writeback 域存在完全同构的手写副本共 **17 处**，漂移风险一致（跳过 review-tech-design / review-code 直接审批等）。

两个问题同属 tools 包 prompt/pipeline 模板治理，合并为一个 CR 落地以获得统一的评审记录与回写基线。

#### 1.2 解决方案摘要

**块 A —— 代码评审 LLM 选择暂停节点**：在节点 8 与节点 9 之间插入 `human_approval` 节点「选择代码评审 LLM」（id `0015-000000000013`），作为声明式模板中唯一合法暂停机制的暂停确认点；新增可选触发输入 `review_llm`（熟手触发 `/coding` 时一次选定，暂停节点快速确认；留空则现场三选一：会话默认模型 / 外部 CLI runner / 其他指定模型）；review-code prompt 头部承接选择结果并在 dimensions 记录 reviewer-model 留痕；repair 循环 replayNodes 不加入选择节点（一次选择、全程复用）。

**块 B —— R9 护栏 + 存量清零**：`lint-prompts` 新增 R9 规则——CR 上下文域（`skills/(requirement|develop|writeback|sync|cr)/`，cr-show 豁免）skill 的「下一步」提示必须收敛到 `crctl next {cr_id}`，禁止手写 skill/pipeline 名映射副本，级别 CONTRADICTS（enforce 阻断）；判据源直读 `skills/_index.yml` 提取全部 skill id（对齐 R7/R8 直读模式，新增 skill 自动覆盖零维护副本）；17 处存量手写副本改写为统一形态（分支语义保留、权威指针收敛）；配套 push-progress 引导链闭环、requirement-writer 前置注记、AGENTS.md 编辑规则条目。

**范围口径（本 CR 的既定决策）**：两份分析文档 §流程决策 均写有「不开 CR，直接提交 tools 仓」；**按用户决策，本次改走 CR 流程**——两块改动全部在本 CR 内落地，tools 仓改动经 CR worktree 流程追踪、合入 `custom/main`。原文档的流程决策不再执行。

#### 1.3 方案遗留决策点（本 PRD 拍板）

两份分析文档中的开放项，本 PRD 直接给出决定，SDD/实施期不得再次悬置：

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 附件1 §6.1 建议 `review_llm` 输入可按 YAGNI 缓上 | **本 CR 即实现**该输入 | 节点 approvalPrompt 含「若触发参数 review_llm 已指定，请按该模型执行」分支，不加输入则该分支成为死文本；输入改动成本极小（一个 inputs 数组条目），缓上反而留下"暂停节点无快速确认路径"的半成品形态 |
| D-2 | 附件1 §6.1 建议 reviewer-model 措辞改"留痕（自报）" | **采纳**：reviewer-model 记录在 review-code dimensions 内，由执行评审的 Agent 自报，不改 crctl `review-record` 契约（canonical 文件 `reviewer` 字段仍由 crctl 注入 `identity(ws)`） | 机器可读的评审模型审计（按模型统计 blocker 率）需要扩 `--reviewer-model` 旗标 + gates/digest 联动，属独立 CR 级改动，列入范围排除 |
| D-3 | 附件2 §4.6 AGENTS.md「修改 Skill」规则条目标注"可选" | **实现**：tools 仓 AGENTS.md 追加第 7 条（CR 上下文 skill「下一步」一律写「以 crctl next 为准」） | 只有机器护栏（R9）没有文字规范，新增 skill 的作者无从知晓约定；条目一行，成本可忽略 |
| D-4 | 附件2 §4.3 统一改写形态的 `{修复节点}` 占位 | 落地时 `{修复节点}` 必须是占位文本或语义方向（PASS/BLOCK 走向），**不得写字面 skill id**，否则新形态自身命中 R9（附件2 §6.4③ 自触发风险） | 已在附件2 实测确认，固化为验收项 |

#### 1.4 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| code-implementation pipeline 12 节点、序列与附件1 §一 完全一致（0001–0012 严格按数组序）；inputs 现为 `cr_id, target_version, auto_push_after_task` | `pipeline-templates/code-implementation.pipeline.json`（注册当日实跑核对） |
| review-code `reviewLoop.replayNodes` = `implement-code → write-test-report → push-progress → review-code`，**按显式 nodeId 引用而非位置序**——新节点 0013 不在任何 replay 列表内，天然不被重放 | 同上（实跑核对） |
| `pipeline-templates/_index.yml` 该条 `nodes: 12`，需同步改 13 | `pipeline-templates/_index.yml:52` |
| lint-prompts 现有规则 R1/R2/R5/R6/R7/R8，**R9 编号空闲可用** | `skills/shared/crctl/scripts/lint-prompts.mjs`（实跑核对） |
| `skills/_index.yml` 共 55 个 skill id，可作 R9 判据源（对齐 R7 直读 crctl.mjs 常量、R8 直读 inbox-emit 枚举模式） | `skills/_index.yml`（实跑核对） |
| 存量手写「下一步」副本实测 **17 处**（附件2 §4.2 表，含初版遗漏的 `write-dev-plan/SKILL.md:69`）；另有 push-progress 缺下一步指引、cr-show 为权威本体豁免、planning/spec/competitive 域不适用 | 附件2 §4.2、§6.4② |
| gates fail-closed 三重硬检查在位（`APPROVAL_REQUIRES_HUMAN`/`CR_STATUS_CURRENT_MISMATCH`/`GATE_BLOCKED`），机器门禁无旁路——漂移定性为提示链层 | 附件2 §2、§6.4① |
| `human_approval` 不得替代状态写入——本方案该节点只做暂停确认，不写 CR 状态，合规 | tools AGENTS.md 约束 |
| **tools 仓本地存在 3 个未提交 pipeline JSON 修改**（code-implementation/architecture-design 的 `auto_push_after_task` default true→false、requirement-authoring 的 `source` required→true 与 `auto_push_after_task` default→false），属用户另行变更、非本 CR 范围；本 CR 对 `code-implementation.pipeline.json` 的改动必须以包含该未提交修改的工作区为基线叠加，不得覆盖 | tools 仓 `git status`（注册当日核实） |

### 2. 用户故事

- **US-1** 作为代码评审的发起者，代码与测试证据推送统一 checkpoint 后，流水线在评审前暂停并询问我用哪个模型执行评审，我可以选当前会话默认模型、外部 CLI runner 或其他指定模型。
- **US-2** 作为熟手执行者，我触发 `/coding` 时在 `review_llm` 输入框一次选定评审模型，暂停节点快速确认即过，不必每轮现场选择。
- **US-3** 作为审计评审证据的维护者，`review-annotations/code.yml` 的 dimensions 里能看到 reviewer-model 留痕，知道这份评审判断由哪个模型产出。
- **US-4** 作为审批人，我在评审模型选择节点驳回时本轮评审即中止（abort），不会出现"无选择进入评审"的状态。
- **US-5** 作为执行需求/开发/回写期 skill 的 Agent，我读到的「下一步」指引一律指向 `crctl next {cr_id}` 权威推荐，不再有"执行 X 或 Y"的等价分叉把我引向跳过评审的路径。
- **US-6** 作为治理工具链维护者，任何人日后在 CR 上下文域 SKILL.md 手写「下一步：执行 xxx-skill」都会被 lint-prompts R9 以 CONTRADICTS 阻断，17 处存量清零后不再复燃。
- **US-7** 作为 requirement-writer 的对话方，我说"批准需求"时映射表先检查评审 verdict=pass 且 blockers=[]，不再被直连 approve-requirement 后遭拒、又被降级翻译成"那先讨论架构"。
- **US-8** 作为推完 checkpoint 的 Agent，push-progress 输出摘要明确告诉我下一步以 `crctl next` 为准，引导链不再在推送后断裂。

### 3. 功能需求

#### 块 A —— 代码评审 LLM 选择暂停节点（附件1 §二）

- **FR-1（新增触发输入 `review_llm`）**：`pipeline-templates/code-implementation.pipeline.json` 的 `inputs` 数组追加 `{ key: review_llm, label: 代码评审 LLM, type: text, required: false }`，placeholder/description 写明"留空则在评审前暂停由人工选择"（D-1 决策：本 CR 即实现）。
- **FR-2（插入 human_approval 节点「选择代码评审 LLM」）**：在节点 8（`0015-000000000008` push-progress）之后、节点 9（`0015-000000000009` review-code）之前插入 `{ id: 00000000-0000-0000-0015-000000000013, kind: human_approval, label: 选择代码评审 LLM, onFail: abort, timeoutMinutes: 4320 }`；`approvalPrompt` 覆盖三分支：① 触发参数 `review_llm` 已指定 → 按该模型执行并快速确认；② 留空 → 暂停询问三选一（当前会话默认模型 / 外部 CLI runner 按代码执行设置列出 / 其他指定模型）；③ 驳回 → 中止本轮评审。该节点**不写 CR 状态**（AGENTS.md 合规）。
- **FR-3（review-code prompt 头部承接选择）**：节点 9 prompt 最前面追加一段：执行评审前确认上一节点选定的评审 LLM（`{{inputs.review_llm}}` 或人工审批环节的用户选择），按该模型/runner 执行本评审，并在 `.crctl/tmp/review-code.yml` 的 dimensions 中记录 reviewer-model 留痕（自报，D-2 决策）；其余取证与落盘要求不变（评审判断写临时 payload，经 `crctl review-record --stage code --bump-attempt` 落盘 canonical），不改 crctl 契约。
- **FR-4（replayNodes 不加入选择节点）**：review-code 的 `reviewLoop.replayNodes` 保持现状（`implement-code → write-test-report → push-progress → review-code`），**不加入 0013**——原则"一次选择、全程复用"，避免每轮自修复重复询问；确需换模型重审时由人工在节点 10（代码审查通过）驳回后重走。write-test-report 的 reviewLoop（006→007）不受影响。
- **FR-5（台账同步）**：`pipeline-templates/_index.yml` 该条 `nodes: 12 → 13`，brief 补「选择代码评审 LLM（人工确认）」环节描述。
- **FR-6（README 同步）**：tools 仓 `README.md` 代码编写期节点表在「推送代码+文档统一 checkpoint」与「代码评审」两行之间插入新节点行（输入/行为/状态写入=无/是否可跳过=否）。

#### 块 B —— R9 护栏 + 存量清零（附件2 §四/§六）

- **FR-7（R9 规则实现）**：`skills/shared/crctl/scripts/lint-prompts.mjs`——① `loadJudgements()` 直读 `skills/_index.yml` 提取全部 skill id 入判据集（读入 `\r\n → \n` 规范化，纪律 #1）；② `runRules()` 在 R8 块后追加 R9 块：scope `^skills/(requirement|develop|writeback|sync|cr)/` 且非 cr-show，命中条件 = 行含「下一步」且不含 `crctl next` 且含任一 skill id 或 pipeline 名模式（`requirement-authoring|architecture-design|code-implementation|feature-writeback|resume-cr|writeback|coding|architecture` + `pipeline`），级别 **CONTRADICTS**（enforce 阻断）；③ `<!-- lint-prompts:ignore -->` ±1 行豁免自动适用；④ 文件头注释规则清单追加 R9。
- **FR-8（17 处存量副本清零）**：按附件2 §4.2 表逐行改写为 §4.3 统一形态「下一步 : 以 `crctl next {cr_id}` 为准（PASS→等待人工审批；BLOCK→pipeline 自动回 {修复节点} 修复重审）」——分支语义保留、权威指针收敛；`{修复节点}` 必须是占位文本或语义方向，不得写字面 skill id（D-4 决策）。涉及 17 个 SKILL.md（requirement 4 + develop 9 + writeback 4）。
- **FR-9（push-progress 引导链闭环）**：`skills/sync/push-progress/SKILL.md` 输出摘要 `last-push-at` 行后追加「下一步 : 以 `crctl next {cr_id}` 为准」（R9 scope 内 sync 域，闭环 D2 断链）。
- **FR-10（requirement-writer 前置注记）**：`agents/requirement-writer.md` Skill 映射表「批准需求 / 推进状态 → approve-requirement」行加前置注记——仅当 `review-annotations/requirement.yml` verdict=pass 且 blockers=[] 时映射生效（D3 修复）。
- **FR-11（AGENTS.md 编辑规则条目）**：tools 仓 `AGENTS.md`「编辑规则 → 修改 Skill」追加第 7 条：CR 上下文 skill（requirement/develop/writeback/sync/cr 域）输出摘要「下一步」一律写「以 `crctl next {cr_id}` 为准」，不得手写 skill/pipeline 名映射副本（lint-prompts R9 强制）（D-3 决策）。
- **FR-12（测试向量）**：`skills/shared/crctl/scripts/test/lint-prompts.test.mjs` 按既有 R7/R8 fixture 模式追加：① 正向——CR 上下文域（fixture 路径必须落在 `skills/requirement/…`）手写 skill 副本命中 R9 CONTRADICTS，`crctl next` 形态不报；② 反向——域外（`skills/planning/…`）「下一步」不受约束；③ pipeline 名模式捕获（approve-code「下一步：writeback pipeline」类）。

#### 收尾 —— 台账同步与验收

- **FR-13（同批 commit 纪律 + 自检）**：R9 规则 + 测试向量 + 17 处存量清零必须在**同一 commit**（否则 enforce 钩子阻断自身）；自检顺序：① 规则上线前 `--mode report` 确认存量命中恰为附件2 §4.2 表所列 17 处（不多不少）；② 测试向量全绿；③ 清零后 `--mode enforce` 归零；④ pipeline JSON 解析自检；⑤ pre-commit 三件套（`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce`）全绿。
- **FR-14（溯源标注）**：commit message 与代码注释延续「漂移治理」编号风格（R9 条目与 `docs/prompt-audit-report-2026-08-05.md` G5 项呼应），注明需求来源为本 CR 两份分析文档；全部改动不引入本机绝对路径（可移植性）。

### 4. 非功能需求

- **NFR-1（同批原子性）**：FR-13 的同批 commit 纪律是硬约束——R9 enforce 级别意味着规则上线与存量清零拆成两个 commit 会让前一个 commit 的 pre-commit 钩子自阻断。
- **NFR-2（零新增第三方依赖）**：lint-prompts.mjs 与测试向量只用 Node 标准库与既有工具函数；pipeline JSON 改动只增节点/输入/prompt 文本。
- **NFR-3（行尾纪律，纪律 #1）**：R9 读 `skills/_index.yml` 先 `\r\n → \n` 规范化；跨行解析失败硬失败，禁止静默降级（T04 教训）。
- **NFR-4（可移植性）**：approvalPrompt 中外部 CLI runner 枚举"按代码执行设置列出"，由目标运行时提供，tools 包不硬编码模型名；全部改动不含本机绝对路径。
- **NFR-5（human_approval 合规边界）**：新插入节点只做暂停确认与选择记录，不写 CR 状态、不替代 `crctl advance`（AGENTS.md 约束）；选择结果通过会话上下文传给下一节点，不新增 pipeline JSON 层变量机制。
- **NFR-6（基线协调）**：实施期对 `code-implementation.pipeline.json` 的改动必须叠加在 tools 仓工作区现有未提交修改（`auto_push_after_task` default false 等 3 处，属用户另行变更）之上，提交时按变更归属拆分 commit，不得把他人变更混入本 CR 提交、也不得覆盖丢失（见 §1.4 事实基线末行）。
- **NFR-7（流程决策留痕）**：两份附件文档原「不开 CR，直接提交 tools 仓」的流程决策已被用户决策覆盖，本 PRD §1.2 已记录；实施期 commit message 注明 CR-2026-023 溯源。

### 5. 验收标准

- **AC-1**（FR-1/FR-2）：`inputs` 含 `review_llm`（required=false）；pipeline 节点数 = 13，数组顺序上「选择代码评审 LLM」（0013，human_approval，onFail=abort，timeoutMinutes=4320）位于 push-progress（0008）与 review-code（0009）之间；approvalPrompt 覆盖三分支（已指定快速确认 / 留空三选一 / 驳回中止）；节点无状态写入描述。
- **AC-2**（FR-3）：review-code prompt 首段含评审 LLM 确认与 reviewer-model dimensions 留痕要求；落盘链路文字不变（临时 payload → `crctl review-record --stage code --bump-attempt`）；reviewer-model 措辞为"留痕（自报）"，无修改 crctl 契约的表述。
- **AC-3**（FR-4）：review-code `reviewLoop.replayNodes` 恰为 4 项（implement-code/write-test-report/push-progress/review-code），不含 0013；write-test-report 的 reviewLoop 未变。
- **AC-4**（FR-5/FR-6）：`pipeline-templates/_index.yml` 该条 `nodes: 13` 且 brief 含选择节点描述；README 节点表新行位于正确位置且列齐（输入/行为/无状态写入/不可跳过）。
- **AC-5**（FR-7）：R9 上线后对构造违例（CR 上下文域「下一步 : 执行 review-requirement」）命中 CONTRADICTS；对 `crctl next` 形态零误报；对域外（planning/spec/competitive）零命中；cr-show 引用 skill 名合法；`<!-- lint-prompts:ignore -->` ±1 行豁免生效；头注释规则清单含 R9。
- **AC-6**（FR-8）：17 处存量逐一改写为统一形态，逐行 diff 核对分支语义保留；改写文本中 `{修复节点}` 均为占位/语义方向，grep 证实改写后的行不含任何字面 skill id（不自触发 R9）；规则上线前 `--mode report` 命中恰为 17 处（对照附件2 §4.2 表不多不少）。
- **AC-7**（FR-9/FR-10）：push-progress 输出摘要含「下一步 : 以 `crctl next {cr_id}` 为准」；requirement-writer 映射表 approve-requirement 行含前置注记（verdict=pass 且 blockers=[]）。
- **AC-8**（FR-11）：tools AGENTS.md「修改 Skill」规则含第 7 条且与 R9 scope 表述一致（五域枚举相同）。
- **AC-9**（FR-12）：三类测试向量全绿（正向命中 / 域外不报 / pipeline 名捕获）；fixture 路径落在 CR 上下文域。
- **AC-10**（FR-13/FR-14）：R9 + 测试 + 清零同一 commit；`lint-prompts --mode enforce` 全库归零；pre-commit 三件套全绿；pipeline JSON 全部可解析；commit message 含漂移治理编号与 CR 溯源。
- **AC-11**（端到端）：① 场景 A——模拟 `/coding` 走到节点 8 后暂停询问评审模型，选择后 review-code 按所选模型执行且 dimensions 含 reviewer-model；留空与预选两条路径各走一次；repair 循环重放不重复询问。② 场景 B——对整改后任一新写 PRD 的在途 CR，`crctl next` 推荐 review-requirement，且 write-requirement-prd/push-progress 输出提示链无等价分叉直达评审；`crctl status/gate` 佐证台账未越级。

### 6. 成功指标

- 全库 `lint-prompts --mode enforce` R9 命中数在本 CR 完成后收敛为 0，且后续新增手写副本在 pre-commit 即被阻断（复燃率 0）。
- 代码评审暂停选择节点在 `/coding` 全量触发路径可用：留空现场选择与 `review_llm` 预选两条路径均可走通；repair 循环零重复询问。
- 每份代码评审证据（`review-annotations/code.yml`）dimensions 含 reviewer-model 留痕，评审模型可追溯率 100%。
- 需求期"写完 PRD 未评审就到下一步"的提示链漂移不复现：需求期四份 SKILL.md + push-progress 的「下一步」全部指向 `crctl next` 权威推荐。

### 7. 范围排除

**本 CR 包含**：附件1 §二 完整方案（2.1~2.6 四步改动 + 两项同步）+ 附件2 §四/§六 全部落地项（R9 规则 + 17 处清零 + push-progress 闭环 + requirement-writer 注记 + AGENTS.md 条目 + 测试向量），以及收尾自检与端到端验收。

**本 CR 不包含**：
- `crctl.mjs`、`gates.json`、`rules.json` 本体改动（附件1 §五 明确不在范围；reviewer 字段仍由 crctl 注入 `identity(ws)` 不改契约）。
- `agent-skill-matrix.yml`、`skills/_index.yml` 增删（未新增/删除 skill 无需变更）。
- 其他 7 条 pipeline 模板、develop/ 域 skill 文档的无关修订。
- 机器可读的评审模型审计（`crctl review-record --reviewer-model` 旗标 + gates.json/digest 联动——附件1 §八.3 明确属独立 CR 级改动）。
- D4 的运行时层缺口（reviewLoop maxAttempts 耗尽后 pipeline 运行时行为）——不在 tools 包管辖范围，需向平台运行时方确认耗尽语义；tools 侧以 `crctl approve` 证据门兜底（附件2 §七.1）。
- tools 仓现有 3 个未提交 pipeline JSON 修改（`auto_push_after_task` default、`source` required）——属用户另行变更，本 CR 仅按其基线叠加、不代为提交（NFR-6）。
- spec/ 域 R9 白名单扩展评估（附件2 §七.2，后续按需）。
