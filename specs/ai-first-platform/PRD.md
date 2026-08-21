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

## Phase0 Tools 技能整合（v0.25 · CR-2026-024）

## PRD — 端到端 Pipeline 最佳实践技能整合（方案 v2.6 落地）

### 1. 概述

#### 1.1 问题陈述

社区涌现大量 Agent Skills 生态项目（superpowers、mattpocock skills、ponytail、taste-skill 等），覆盖需求、设计、计划、开发、审查全研发链路。本工具包（Phase0 Tools）已具备完整编排层（pipeline + crctl 状态机 + agent-skill-matrix 治理 + engineering-docs 文档体系）。《端到端Pipeline最佳实践技能整合方案》v1.0 提出以 external 身份注入外部方法论；经逐轮拷问评审（v2.0–v2.6），多数注入点被证明与本包既有机制冲突、重复或建立在错误事实上，最终按同一判据——**能否被本包既有的可执行守卫（crctl CAS、guard deny、lint-prompts、check-skill-matrix、check-agents-contract）验证，以及是否对应一处真实存在的机制空白**——筛出两类真实缺口：

- **外部技能对照发现的六条内化项**（§4.3–§4.9-③）：`coding-discipline`（极简阶梯/步骤粒度/根因排查）、TASK 接口契约与类型一致性、评审证据无条件重新验证、TASK 依赖拓扑排序、suggestions 策略化分流。三次全文重读（`systematic-debugging` → 根因排查；`writing-plans`/`verification-before-completion` → 接口契约与独立重验；`dispatching-parallel-agents` → 依赖排序）各挖出一处被 v1.0 误判为"纯重复"的真实空白——它们的共同特征不是"缺少某个外部工具"，而是**本包自己已声明了一半的机制没有闭环**（TDD 引用悬空、`depends-on` 无消费方、验证结果自报即采信）。
- **本包自查发现的四条存量缺口**（§4.9，与外部技能无关）：`capabilities` 声明与事实相反、`forbidden` 性质误导（像闸实为文档）、`suggestions` 只写不读、`assignee` 死字段。

核心结论不变：外部技能只填补方法论空缺，**不新增 owns、不改状态机、不破坏单一事实源**；已安装的同名外部技能（ponytail / writing-plans / systematic-debugging / verification-before-completion / dispatching-parallel-agents）全部降级为**可选加速器**，不构成执行前提，也不要求任何跨运行时探测机制。

#### 1.2 解决方案摘要

按方案 v2.6 分两批实施：

**批次一 · 收口（纯删除与对齐，零新增行为）**：删 actor 级零引用 external 死声明（`system-orchestrator.external`：`using-superpowers` / `writing-plans` / `verification-before-completion`；`dev-agent.external`：`test-driven-development`——随本 CR 删其唯一真实引用即变零引用，须同批清除；`systematic-debugging` 仅存于顶层纯文档块不动，见 SDD §0 C-2/C-5）；`implement-code` 与 `code-implementation.pipeline.json` 节点 6 删 TDD 悬空引用并补 `executing-plans`/`subagent-driven-development` 降级路径；`agents/_index.yml` 三项 capabilities 从 `supported` 挪进 `pending` 且 `known-gaps` 前两条删除；`AGENT-SKILL-MATRIX.md` 与 openwiki 写明 `forbidden` 为声明性边界（无调用级拦截）；`write-dev-tasks` 删 `assignee` 死字段。

**批次二 · 内化（真实行为变更）**：新建 `coding-discipline` skill（§1 极简阶梯 + §2 步骤粒度 + §3 根因排查与回归验证）并完成登记/矩阵/消费方引用闭环；`review-code` 新增「前端质量」维度（仅可验证项）与 Step 1 无条件重新执行验证命令；`write-dev-tasks` 追加接口契约小节、类型一致性自查与占位符判据；`implement-code` 追加 `depends-on` 拓扑排序与并发边界；`code-implementation.pipeline.json` 新增触发参数 `suggestion_policy`（select，strict/lenient，default strict）驱动评审期 suggestions 策略化分流，`approve-code` 追加 suggestions 经 `record-idea` 落 `docs/ideas/`；`write-requirement-prd` 优先采纳 summary 已确认边界；AGENTS.md 第 56 条修订为甲路线表述。

**范围口径**：全部改动对象位于 tools 包（`../tools/`），经本 CR worktree 流程追踪，tools 仓提交带 CR 编号溯源、合入 `custom/main`（对齐 CR-2026-021/022/023 先例）。

#### 1.3 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 依据 |
|---|---|
| `agent-skill-matrix.yml` 的 `external:` 字段只被 `check-skill-matrix.mjs` 用作"豁免 owns 唯一性检查"，从未校验外部技能是否存在或被引用；4 个死声明多 CR 周期零引用点、CI 从未报警 | `check-skill-matrix.mjs` + 方案 §4.2 取证 |
| `implement-code/SKILL.md` 第 75 行要求遵循未安装的 external `test-driven-development`，规则静默蒸发，下游 `test-report.status=pass` 门禁照常要求证据——纪律与门禁脱钩的悬空引用 | 方案 §4.3 问题根源 |
| `depends-on` 已声明（`write-dev-tasks/SKILL.md:41`）、已写入 frontmatter（:58）、已汇总进 `tasks/_index.yml`（:75）、已被 `validate-doc` 校验指向有效（`validate-doc/SKILL.md:15`），但**无任何消费方用它决定执行顺序** | 方案 §4.8 表格 |
| `agents/_index.yml` 的 `capabilities.supported` 宣称三项能力而 `agent-skill-matrix.yml` 的 `known-gaps` 同时承认其无对应 Skill；`pending` 字段 9 个 agent 全为 `[]` | 方案 §4.9-① |
| `check-agents-contract` 白名单校验只作用于 `references[]`，不覆盖 SKILL.md 正文让 agent 调用什么；`pretooluse-guard.mjs` 只管文件路径不管技能调用——`forbidden` 想管的运行时调用面无人看守 | 方案 §4.9-② |
| 三个 review skill 声明 `suggestions`、crctl 落盘进 `review-annotations/{stage}.yml`，但回修链只读 `blockers`/`repair-instructions`，`approve-code` 全文零次提及、`writeback-*` 零消费 | 方案 §4.9-③ |
| `review-code/SKILL.md:46` 现状"若缺失必须重新运行或要求补齐"——implement-code 自报即采信 | 方案 §4.7 问题根源 |
| `assignee: ""` 全仓仅 1 处（`write-dev-tasks/SKILL.md:59` 模板自身），零读取方，连 `tasks/_index.yml` 汇总都不含它 | 方案 §4.9-④ |
| 现有三个 `select` 型 input（`focus_dimension`/`insight_type`/`new_owner_role`）全部为 `required: false` + `default` 组合，全仓 `required: true` 与 `default` 并存零先例 | 方案 §4.9-③ 形态对齐依据 |
| `review-code` 的 `reviewLoop.replayNodes` 按显式 nodeId 引用而非位置序，新增 input 不在任何 replay 列表内，天然不被重放 | CR-2026-023 PRD §1.4 同源事实 |
| 本工具包是文档驱动（SDD：技术设计文档驱动）而非测试驱动；测试报告在代码之后，测试角色是证明 TASK 验收条件而非驱动实现 | 方案 §2 术语澄清 |

#### 1.4 方案遗留决策点（本 PRD 拍板）

方案 v2.6 §7 的待定项中，与 PRD 范围直接相关的由本 PRD 给出决定，SDD/实施期不得再次悬置：

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 方案 §7"CR 交付方式未定" | **沿用 knowledge-base 注册模式**（已在 CR-2026-024 注册时落地），tools 仓改动经 CR 编号溯源合入 `custom/main` | 与 CR-2026-021/022/023 一致，零新机制 |
| D-2 | `check-skill-matrix.mjs` 增强（external 声明必须有真实引用） | **不做，列入范围排除** | 独立漂移治理项；本次不做避免让当前改动背负存量债务（死声明清理后不会触发新检查报红） |
| D-3 | `capabilities` 真闭环（Level C，约 40 条目） | **不做，列入范围排除** | 工作量自成一个 CR；本次只做数据订正（Level A） |
| D-4 | `requirement`/`tech-design` 阶段的 suggestions 分流 | **不做，本次只做 code 阶段** | 另两阶段机制同构，且其 suggestions 更可能在当轮被吸收进 PRD/SDD 迭代，优先级低 |
| D-5 | `crctl task done` 依赖守卫（§4.8 的可执行化） | **不做，列入后续项** | 涉及 crctl 新增校验逻辑与测试向量，属独立 CR；本次 §4.8 落在 prompt 层 |
| D-6 | TDD 铁律 / superpowers requesting·receiving-code-review | **不采用，列入范围排除** | TDD 与本包 SDD 驱动主链矛盾且不可验证；社交纪律与既有 reviewLoop 账本重复且后者更强（有留痕） |
| D-7 | ocr / taste-skill 审美 / `redesign-existing-projects` | **不引入，列入范围排除** | ocr 与 CR-2026-023 评审模型留痕冲突；审美不可验证；redesign 属投机需求（详见范围排除） |

### 2. 用户故事

- **US-1** 作为 `dev-agent`（实现者），实现单个 TASK 时按 `coding-discipline` §1 极简阶梯选方案、§2 按 2-5 分钟粒度切分步骤、自修复分支先按 §3 定位根因再动手，不再逐条症状打补丁。
- **US-2** 作为 `dev-agent`（实现者），开始某 TASK 前先读 `tasks/_index.yml` 的 `depends-on` 做拓扑排序，前置 TASK 未 done 时不启动并留痕，不再按索引顺序撞序实现导致上游断裂。
- **US-3** 作为 `quality-reviewer-agent`（评审者），评审前端 diff 时有「前端质量」维度（a11y 对比度/组件状态完整性/构建体积），评审证据 Step 1 无条件重新执行验证命令而非采信 implement-code 自报。
- **US-4** 作为流水线启动者，触发 `/coding` 时通过 `suggestion_policy` 选择交付节奏——默认 strict 只判 CR 本身 pass/block，想清技术债时改选 lenient 把该修的升格进 blockers。
- **US-5** 作为审批人，评审输出能看到本轮所用 policy 与 Suggestions 条数；剩余 suggestions 可经 `record-idea` 转入 `docs/ideas/`，不再"只写不读"静默丢失。
- **US-6** 作为计划编写者（`write-dev-tasks`），TASK 正文含「接口契约」小节（消费/产出精确签名），Step 4 核对跨 TASK 签名一致性，命名对不上时输出 WARN 而非静默覆盖。
- **US-7** 作为维护者，`agents/_index.yml` 的 capabilities 与 `agent-skill-matrix.yml` 的 known-gaps 不再自相矛盾；`forbidden` 的性质被文档写明是声明性边界而非闸。
- **US-8** 作为需求撰写者（`write-requirement-prd`），当 `summary` 已携带拷问阶段确认的边界与排除项时，优先采纳不再重新询问。

### 3. 功能需求

#### 批次一 · 收口（纯删除与对齐，零新增行为）

- **FR-1（删死声明 external）**：`agent-skill-matrix.yml` actor 级 external 删除五项零引用声明——`system-orchestrator.external` 的 `using-superpowers`、`writing-plans`、`verification-before-completion`（actor 级仅此三项，`systematic-debugging` 仅存于顶层纯文档块，不动，见 SDD §0 C-2）；以及 `dev-agent.external` 的 `test-driven-development`（FR-2/FR-3 删其唯一真实引用后即变零引用，须同批清除，否则本 CR 自造新死声明，见 SDD §0 C-5）；保留 `executing-plans`、`subagent-driven-development`（`implement-code` 有真实引用）；`brainstorming` 不动（唯一四件套齐全的样板）。
- **FR-2（implement-code 删 TDD 引用 + 补降级路径）**：`skills/develop/implement-code/SKILL.md` 删第 75 行「必须遵循目标运行时已安装的 external `test-driven-development`」；`executing-plans`/`subagent-driven-development` 按 `brainstorming` 写法补降级路径——批次一仅落「未提供 subagent-driven-development 时按 TASK 顺序串行实现（等价降级到 executing-plans 语义），节点输出注明降级」；后半句「两者均未提供时按 `coding-discipline` §2 粒度自行拆解执行」归批次二（与 coding-discipline 新建同批，避免批次一携带指向未来产物的悬空引用，批次拆分以 SDD §3.4/§4.1/§4.2 为准）。
- **FR-3（pipeline 节点 6 prompt 同步）**：`pipeline-templates/code-implementation.pipeline.json` 节点 6（implement-code）prompt 同步删除 TDD 表述、补降级路径表述。
- **FR-4（capabilities 订正，§4.9-①）**：`agents/_index.yml` 将 `knowledge-agent` 的 `tech-note-write`/`insight-write` 与 `customer-support-agent` 的 `unresolved-feedback-record` 从 `capabilities.supported` 挪进 `pending`；`agent-skill-matrix.yml` 的 `known-gaps` 前两条删除（`pending` 已表达同一事实），第三条 `writeback-agent-entry` 与 capabilities 无关保留。
- **FR-5（forbidden 性质说明，§4.9-②）**：`AGENT-SKILL-MATRIX.md` 与 `openwiki/architecture/agent-skill-matrix.md` 写明 `forbidden` 的性质——声明性边界，执行靠 agent 自觉 + `protectedPaths` 文件守卫，**不存在调用级拦截**；不加运行时钩子（`protectedPaths` 已覆盖高危面）。
- **FR-6（删 assignee 死字段，§4.9-④）**：`skills/develop/write-dev-tasks/SKILL.md` 删 TASK frontmatter 的 `assignee` 字段；真要多人协作时 `cr.md` 需先支持多开发负责人，不是加字段就够。

#### 批次二 · 内化（真实行为变更）

- **FR-7（新建 coding-discipline skill，§4.3）**：新建 `skills/develop/coding-discipline/SKILL.md`，内容为本包自有、可被 lint-prompts 覆盖的规则（而非指向外部技能名）：
  - **§1 极简阶梯**（源自 ponytail，本包语汇重写）：需要存在吗（YAGNI）→ 代码库已有 → 标准库 → 平台原生 → 已装依赖 → 一行 → 最小可用实现。信任边界校验、错误处理、安全、可访问性不在精简范围内。
  - **§2 执行步骤粒度**（源自 writing-plans）：执行单个 TASK 时内部步骤按 2-5 分钟粒度切分（写验证用例→跑到失败/明确当前状态→实现→复验→提交），每步含精确文件路径与验证步骤，禁止 TBD/占位符。TASK 本身粒度（1-3 天）由 `write-dev-tasks` 定义，不受本节约束。
  - **§3 根因排查 + 回归验证**（源自 systematic-debugging + verification-before-completion）：进入自修复模式（`review_feedback` 存在）时，动手改前先定位根因（哪个 TASK、哪一行、什么假设不成立），同一根因下所有失败点一次修完；节点输出必须含 `root-cause` 字段（与 `fixed-blockers` 并列）。若修复针对 bug（非纯新功能缺口），对应回归测试先验"红"（临时还原修复前代码跑一次确认失败）再验"绿"（恢复修复跑一次确认通过），两次结果写入节点输出。
  - **甲路线措辞**：已装完整 external 技能（ponytail/systematic-debugging/writing-plans）时优先走其完整流程，未装按本节规则执行，二者等价；`coding-discipline` 是兜底事实源，不依赖跨运行时探测。
- **FR-8（coding-discipline 登记与归属）**：`skills/_index.yml` 登记为 active；`agent-skill-matrix.yml` 下 `dev-agent` owns、`quality-reviewer-agent` can-call；`AGENT-SKILL-MATRIX.md` 主责矩阵表格同步；tools 仓 `dir-graph.yaml` 登记路径；`ARCHITECTURE.md` §8 代码地图登记。
- **FR-9（implement-code 消费 coding-discipline，§4.3/§4.8）**：`implement-code/SKILL.md` Step 3 引用 §1+§2，自修复分支额外引用 §3；追加 `depends-on` 拓扑排序规则——执行前读 `tasks/_index.yml` 的 `depends-on` 拓扑排序，前置 TASK 未 done 不得开始并注明被阻塞项与等待的前置项。
- **FR-10（write-dev-plan 消费 coding-discipline）**：`skills/develop/write-dev-plan/SKILL.md` 引用 `coding-discipline` §2（步骤粒度约束）。（路径订正：技术评审 M-3 实测该 skill 在 develop 域，原 planning 域表述错误，以 SDD §0 C-4 为准）
- **FR-11（review-code 前端质量维度，§4.4）**：`review-code/SKILL.md` Step 3 评审维度表新增「前端质量」维度（仅前端 diff 触发；按维度名验收不用序数——实测现有 6 行，新增为第 7 行；`code-implementation.pipeline.json` nodes[9].prompt 的 ①②③④ 枚举同步追加 ⑤，见 SDD §0 B-4）：a11y 对比度达 WCAG AA（破 AA 升 blocker）、组件 loading/empty/error 状态完整覆盖、构建体积在预算内（其余 minor）；触发条件为 diff 命中 `*.tsx`/`*.vue`/`*.css`/`*.html`。`dimensions` 为自由映射（crctl 仅校验非空），加键零结构成本。
- **FR-12（review-code 无条件重验，§4.7）**：`review-code/SKILL.md` Step 1 改为**无条件重新执行**验证命令（lint/test/build），不再是"缺失才补跑"；implement-code 自报结果仅作参考对照，不一致时以本轮重新执行结果为准并在 blockers 注明差异。评审判据细化：「测试通过」必须是本轮重新执行的完整命令输出（0 failures），"看起来通过"或"之前跑过"不构成证据。甲路线措辞：无条件重验是 `review-code` 自身最低要求，不因是否装外部技能而增减，不弱化为"可选加速"；已装 `verification-before-completion` 时可用其 Gate Function/Common Failures 表作补充参考。
- **FR-13（suggestion_policy 触发参数，§4.9-③/v2.6）**：`code-implementation.pipeline.json` `inputs` 新增 `{ key: suggestion_policy, label: 改进建议处置策略, type: select, options: [strict, lenient], required: false, default: "strict", description: strict=不升格（默认，保守交付）；lenient=按三条判据把本 CR 内该修的升格进 blockers（清技术债场景） }`——形态严格对齐包内三个既有 `select` input（required:false + default），UI 预选中 strict。
- **FR-14（review-code 策略化分流，§4.9-③）**：策略参数由 `code-implementation.pipeline.json` nodes[9].prompt 的 `{{inputs.suggestion_policy}}` 插值承载（插值只发生在 pipeline JSON；`review-code/SKILL.md` Step 3 只写模式无关表述「按本轮策略参数执行，缺省 strict」，正文不含插值语法，同源先例 review_llm，见 SDD §0 B-1）。`lenient` 模式下非阻塞发现同时满足三条升格判据且通过轮次闸才进 blockers——① 改动不超出本 CR 已触碰的文件（不扩大 diff）；② 有明确"改成什么"（能写进 `repair-instructions`）；③ 不需要产品/架构决策（纯实现层）；④ 轮次闸：仅首轮评审（attempt=1）允许升格，第 2 轮起一律 suggestions——防升格消耗 maxAttempts=3 耗尽轮次、停在 developing 无法进入审批。同一轮多条升格项写进同一批 blockers（成批升格）。留痕：dimensions 写 `suggestion-policy: {strict|lenient}`，canonical 化进 `review-annotations/code.yml`（跨 CR 可比性依赖 canonical，节点输出不是账本，见 SDD §2.5）；Step 6 输出模板补 `Suggestions : {N} 条` 与本轮 policy。`strict` 模式（默认）所有非阻塞发现一律进 suggestions。语义校准：blockers=本 CR 内要处理的，suggestions=本 CR 内不处理的。
- **FR-15（approve-code 承接 suggestions，§4.9-③）**：`approve-code/SKILL.md` 追加——剩余 `suggestions` 可选经 `record-idea` 转入 `docs/ideas/`（CR worktree 内，随分支合并进 trunk；`feature-writeback` 硬边界只写 specs/delivery，故必须在 approve-code 期做），不设默认、不阻塞本 CR；不转则仅留档 `review-annotations`，无损失。
- **FR-16（agent-skill-matrix 登记 record-idea，§4.9-③）**：`agent-skill-matrix.yml` `dev-agent` can-call 追加 `record-idea`（按 AGENTS.md:135 登记要求，因 FR-15 新增真实引用点）。
- **FR-17（write-dev-tasks 接口契约，§4.6）**：`write-dev-tasks/SKILL.md` 三处修改——① TASK 正文追加「接口契约」小节：**消费**（本 TASK 使用哪些上游 TASK 产出的精确函数名/参数/返回类型）、**产出**（本 TASK 暴露给下游 TASK 的精确签名）；② Step 4（生成 TASK 索引后）追加核对步骤——核对所有 TASK 声明的接口签名是否一致，命名对不上时输出 WARN 并列出差异（比照"估算交叉校验"写法：不静默覆盖，由计划负责人决定）；③ 「注意事项」的"不得模糊描述"替换为具体判据清单（源自 writing-plans No Placeholders）：禁止 TBD/"待定"；禁止"加适当的错误处理"这类无实际内容的描述；禁止"同 TASK-03"这类引用而不给出实际代码/签名；禁止引用未在任何 TASK 中定义的类型或函数。甲路线措辞：以上为自有规则，已装 `writing-plans` 完整版时可引用其 Task Structure 模板作排版参考，两者不冲突不要求探测。
- **FR-18（write-requirement-prd 采纳 summary 边界，§4.1）**：`write-requirement-prd/SKILL.md` 追加一行——若 `summary` 携带已确认的边界与排除项，优先采纳，不再重新询问。
- **FR-19（pipeline prompt 同步，§4.8/§4.6/§4.9-③）**：`code-implementation.pipeline.json` 节点 9（review-code）prompt 同步第五维度、无条件重验与策略化升格判据；节点 2（write-dev-tasks）prompt 同步接口契约要求；节点 6（implement-code）prompt 同步拓扑排序规则。
- **FR-20（AGENTS.md 第 56 条修订，§4.5）**：tools 仓 `AGENTS.md` 第 56 条「外部 superpowers 能力由目标运行时提供，phase0 tools 不复制同名 SKILL.md，只在需要处声明依赖」改为甲路线表述——本包自有规则（`coding-discipline`）为兜底事实源，外部同名技能为可选加速器，二者不冲突、不要求探测。第 160 条「禁止把外部方法论 Skill 打包进 phase0 tools」保持不变（`coding-discipline` 非复制上游 SKILL.md，是本包语汇重写的自有规则）。
- **FR-21（openwiki 同步）**：`openwiki/` 相关页面同步（含 `architecture/agent-skill-matrix.md` 的 forbidden 性质说明与主责矩阵更新）。

#### 收尾 —— 台账同步与验收

- **FR-22（批次原子性）**：批次二内部引用闭环——`coding-discipline` 新建 + `skills/_index.yml` 登记 + `agent-skill-matrix.yml` owns/can-call + `AGENT-SKILL-MATRIX.md` + 消费方引用（FR-9/FR-10）必须在**同一批提交**，否则 check-skill-matrix 报"active skill 无 owns"或"孤儿引用"。批次一与批次二**分开提交**（批次一零行为变更，便于回归定位）。
- **FR-23（验证关卡）**：每批完成后执行 `check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce` 全绿 + 1 个真实 CR 回归验证状态机推进正常（`crctl next`/`crctl status`/`crctl gate` 佐证无越级）。
- **FR-24（溯源标注）**：commit message 与代码注释注明需求来源为《端到端Pipeline最佳实践技能整合方案》v2.6 与本 CR（CR-2026-024）；全部改动不引入本机绝对路径（可移植性）。

### 4. 非功能需求

- **NFR-1（批次一零行为变更）**：批次一所有改动为纯删除与数据对齐，不改变任何运行时行为；回归验证应确认状态机推进、三件套守卫结果与改动前一致（除死声明减少导致的 `check-skill-matrix` 报告差异为预期）。
- **NFR-2（批次二同批原子性）**：FR-22 的同批提交是硬约束——`coding-discipline` 的登记与消费方引用拆开会触发 pre-commit 三件套自阻断（孤儿 skill / 缺失 owns）。
- **NFR-3（不新增 owns、不改状态机）**：`coding-discipline` 的 owns 为 `dev-agent`（既有 actor），不新增 actor；不新增/修改状态机状态与转换（15 具名状态 + 注册前 (new)，25 条声明转移，CR-2026-022 后含两条 reject 转换）。
- **NFR-4（甲路线，零探测依赖）**：外部同名技能全部为可选加速器，`coding-discipline`/拓扑排序/无条件重验等内化规则不依赖任何跨运行时探测机制（本包无此设施且为此新增成本远高于内化文本）。
- **NFR-5（零新增第三方依赖）**：本 CR 全部改动为 SKILL.md 正文、pipeline JSON、YAML 账本与文档，不引入新脚本依赖；不新增 crctl 子命令（D-5 决策：依赖守卫另立项）。
- **NFR-6（suggestion_policy 形态对齐先例）**：新 input 的形态（select + required:false + default）严格对齐包内三个既有 select input，不引入 `required:true + default` 并存的新形态（全仓零先例）。
- **NFR-7（lenient 模式口径留痕）**：`lenient` 模式下 blockers 语义扩大导致 `review-code` 输出的 Critical/Major 计数口径改变，评审输出必须注明本轮所用 policy，避免历史 CR 数据与 strict 模式直接比较时产生误读。
- **NFR-8（行尾纪律，纪律 #1）**：实施期涉及逐行解析/跨行正则的代码或验证，读入后先 `\r\n → \n` 规范化，解析失败硬失败，禁止静默降级。
- **NFR-9（可移植性）**：approvalPrompt/文档描述中的外部 CLI runner、验证命令由目标运行时提供，tools 包不硬编码模型名；全部改动不含本机绝对路径。
- **NFR-10（基线协调）**：若 tools 仓工作区存在与本 CR 无关的未提交修改，实施期对同一文件的改动必须叠加在其上、按变更归属拆分 commit，不得混入或覆盖（对齐 CR-2026-023 NFR-6 先例）。

### 5. 验收标准

- **AC-1**（FR-1）：`agent-skill-matrix.yml` actor 级 external 中 grep 不到 `using-superpowers|writing-plans|systematic-debugging|verification-before-completion|test-driven-development` 任一名称（订正：actor 级前三项位于 system-orchestrator.external，test-driven-development 位于 dev-agent.external，随本 CR 删其唯一真实引用而同批清除，见 SDD §0 C-2/C-5）；`executing-plans`、`subagent-driven-development`、`brainstorming` 保留；`check-skill-matrix.mjs` 通过。
- **AC-2**（FR-2/FR-3）：`implement-code/SKILL.md` grep 不到 `test-driven-development` 引用；含 executing-plans/subagent-driven-development 降级路径文本；`code-implementation.pipeline.json` 节点 6 prompt 同步；JSON 可解析。
- **AC-3**（FR-4）：`agents/_index.yml` 中三项能力位于对应 agent 的 `pending` 而非 `supported`；`agent-skill-matrix.yml` `known-gaps` 恰剩 `writeback-agent-entry` 一条（或与 capabilities 无关的保留项）；`check-agents-contract.mjs` 通过。
- **AC-4**（FR-5）：`AGENT-SKILL-MATRIX.md` 与 `openwiki/architecture/agent-skill-matrix.md` 均含"声明性边界"与"不存在调用级拦截"表述；grep 无"调用级拦截"的错误承诺。
- **AC-5**（FR-6）：`write-dev-tasks/SKILL.md` grep 不到 `assignee` 字段（模板与正文均无）。
- **AC-6**（FR-7/FR-8）：`skills/develop/coding-discipline/SKILL.md` 存在且含 §1 极简阶梯/§2 步骤粒度/§3 根因排查三节与甲路线措辞；`skills/_index.yml` 登记 active；`agent-skill-matrix.yml` `dev-agent` owns、`quality-reviewer-agent` can-call；`AGENT-SKILL-MATRIX.md` 与 tools `dir-graph.yaml`、`ARCHITECTURE.md` §8 同步；三件套通过。
- **AC-7**（FR-9/FR-10）：`implement-code/SKILL.md` Step 3 含 coding-discipline §1+§2 引用、自修复分支 §3 引用、depends-on 拓扑排序规则；`write-dev-plan/SKILL.md` 含 §2 引用。
- **AC-8**（FR-11）：`review-code/SKILL.md` Step 3 维度表含名为「前端质量」的新维度行（订正：按维度名验收，不用序号——实测现有 6 行，新增为第 7 行，见 SDD §0 B-4）且触发条件为 `*.tsx|*.vue|*.css|*.html`；破坏 WCAG AA 判 blocker、其余 minor；`code-implementation.pipeline.json` nodes[9].prompt 同步追加维度 ⑤；不含字体/配色/拨盘等审美主张。
- **AC-9**（FR-12）：`review-code/SKILL.md` Step 1 为无条件重新执行（无"缺失才补跑"表述）；含"0 failures"与"之前跑过不构成证据"判据；甲路线措辞不弱化为"可选加速"。
- **AC-10**（FR-13）：`code-implementation.pipeline.json` `inputs` 含 `suggestion_policy`（type=select，options=[strict,lenient]，required=false，default="strict"）；形态与既有三个 select input 一致；JSON 可解析。
- **AC-11**（FR-14）：验收对象以 pipeline JSON 为主（订正：`{{inputs.*}}` 插值只发生在 pipeline JSON，见 SDD §0 B-1）——`code-implementation.pipeline.json` nodes[9].prompt 含 `{{inputs.suggestion_policy}}` 插值读取与三条升格判据（lenient 才生效）、轮次闸（仅 attempt=1 允许升格）与成批升格要求；`review-code/SKILL.md` Step 3 为模式无关表述且正文不含 `{{inputs.` 插值语法；`review-annotations/code.yml` dimensions 含 `suggestion-policy` 留痕键（M-1）；Step 6 输出模板含 `Suggestions : {N} 条` 与本轮 policy；strict 模式不升格的语义明确。
- **AC-12**（FR-15/FR-16）：`approve-code/SKILL.md` 含 suggestions 经 record-idea 转 docs/ideas/ 的条款（不设默认、不阻塞）；`agent-skill-matrix.yml` `dev-agent` can-call 含 `record-idea`；check-skill-matrix 通过。
- **AC-13**（FR-17）：`write-dev-tasks/SKILL.md` 含接口契约小节（消费/产出）、Step 4 签名一致性核对（WARN 不静默覆盖）、占位符判据清单（TBD/待定/适当错误处理/同 TASK-XX/未定义引用 四类禁止）。
- **AC-14**（FR-18）：`write-requirement-prd/SKILL.md` 含"优先采纳 summary 已确认边界/排除项"条款。
- **AC-15**（FR-19）：pipeline 节点 2/6/9 prompt 分别同步接口契约、拓扑排序、第五维度+无条件重验+策略化升格；JSON 可解析；节点编号不变。
- **AC-16**（FR-20）：tools `AGENTS.md` 第 56 条为甲路线表述（自有规则兜底 + 外部可选加速），第 160 条保持不变。
- **AC-17**（FR-21）：openwiki 相关页面同步 forbidden 性质与主责矩阵。
- **AC-18**（FR-22/FR-23）：批次一与批次二分开提交；每批三件套（check-skill-matrix + check-agents-contract + lint-prompts enforce）全绿；1 个真实 CR 回归验证 `crctl next/status/gate` 无越级。
- **AC-19**（FR-24）：commit message 含方案 v2.6 与 CR-2026-024 溯源；grep 全改动无本机绝对路径（如 `C:\\Users`）。
- **AC-20**（端到端）：① strict 场景——默认触发 `/coding` 走完评审，非阻塞发现全进 suggestions、verdict 不受影响；② lenient 场景——改选 lenient，满足三条判据的发现升格进 blockers 并经 reviewLoop 在本 CR 修复，评审输出注明 policy=lenient；③ 审批场景——approve-code 期 suggestions 经 record-idea 落 docs/ideas/ 成功合并进 trunk。

### 6. 成功指标

- 批次一完成后 `agent-skill-matrix.yml` 死声明数为 0，`capabilities`/`known-gaps` 无自相矛盾，`assignee` 全仓零残留。
- 批次二完成后 `coding-discipline` 三件套全绿且被 implement-code/write-dev-plan 真实引用（非孤儿）。
- 评审证据链"自报即采信"漏洞关闭：`review-code` Step 1 无条件重验，`review-annotations/code.yml` 证据可追溯到本轮执行。
- suggestions 不再"只写不读"：lenient 模式下该修项经 reviewLoop 本 CR 解决，strict 模式下剩余项经 record-idea 进 docs/ideas/，留档率与流转率可观测。
- TASK 跨依赖断裂率下降：`depends-on` 拓扑排序使实现顺序与依赖一致，接口契约 WARN 提前暴露签名不一致。
- 全部改动通过三件套 + 1 个真实 CR 回归，状态机推进零越级。

### 7. 范围排除

**本 CR 包含**：方案 v2.6 §4.3–§4.9 全部落地项（批次一 6 项收口 + 批次二 15 项内化/同步），以及收尾原子性与端到端验收。

**本 CR 不包含**：
- `check-skill-matrix.mjs` 增强（external 声明必须有真实引用点）——独立漂移治理项（D-2）。
- `capabilities` 真闭环 Level C（`capability → 实现 skill[]` 映射 + check-agents-contract 第 5 条不变式，约 40 条目）——工作量自成 CR（D-3）。
- `requirement`/`tech-design` 阶段的 suggestions 分流——另两阶段机制同构，本次只做 code 阶段（D-4）。
- `crctl task done` 依赖守卫（§4.8 的可执行化）——涉及 crctl 新增校验与测试向量，独立 CR（D-5）。
- TDD 铁律 / superpowers requesting·receiving-code-review 社交纪律——与本包 SDD 驱动主链矛盾或与既有 reviewLoop 账本重复（D-6）。
- ocr 确定性预检 / taste-skill 审美规范（字体/配色/拨盘）/ `redesign-existing-projects`——与 CR-2026-023 评审模型留痕冲突 / 不可验证 / 投机需求（D-7）。
- OpenSpec 文档体系 / ECC 全家桶 / CopilotKit / i-have-adhd / 图像生成类技能——与 engineering-docs 同构冲突 / owns 唯一性无法治理 / 非通用方法论 / 产物不可验证（方案 §5）。
- `crctl.mjs`、`gates.json`、`rules.json` 本体改动——本 CR 无状态机/守卫变更需求（NFR-3/NFR-5）。
- 其他 7 条 pipeline 模板、与 CR 上下文无关的 skill 文档修订。

### 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-08 | v0.1.0 | Ray | 初始草稿（方案 v2.6 全量落地） |
| 2026-08-08 | v0.1.1 | Ray | 技术评审回修同步：attempt 1 订正 FR-10 路径与 AC-1/AC-8/AC-11；attempt 2 订正 FR-1/FR-2/FR-11/FR-14 正文与 SDD §0 C-2/C-4/C-5、§3.3/§3.4 对齐（B-5~B-8） |

## crctl 守卫与回显收敛（v0.26 · CR-2026-025）

## PRD — crctl 守卫与回显收敛

### 1. 概述

#### 1.1 问题陈述

本 CR 合并四项独立但同属 Tools 确定性执行层的漂移治理项，它们共享同一个交付面（`crctl.mjs` / `check-skill-matrix.mjs` 本体 + 各自测试向量），且都不改状态机：

**项① — `external` 声明无引用校验（方案 v2.6 §7 的 D-2）**：`agent-skill-matrix.yml` 的 `external:` 字段只被 `check-skill-matrix.mjs` 用作「豁免 owns 唯一性检查」，从不校验被声明的外部技能是否真被引用。后果已由 CR-2026-024 坐实：`using-superpowers` / `writing-plans` / `verification-before-completion` 三个声明多个 CR 周期零引用点、CI 从未报警；`implement-code/SKILL.md:75` 引用未安装的 `test-driven-development` 导致规则静默蒸发。CR-2026-024 清理了存量，但**没有装上防复发的闸**——同一失效模式可以立刻再来一次。

**项② — `depends-on` 无机械强制（方案 v2.6 §4.8/§7 的 D-5）**：`depends-on` 已声明（`write-dev-tasks/SKILL.md:41`）、已写入 TASK frontmatter、已汇总进 `tasks/_index.yml`、已被 `validate-doc` 校验指向有效，CR-2026-024 又给 `implement-code` 补了 prompt 层拓扑排序。但 `crctl task done` 写 `status: done` 时不看依赖——前置 TASK 还是 pending，后继 TASK 照样可以标完成。prompt 层规则靠 agent 自觉，账本层无守卫，这是 CR-2026-024 自己在 §5 决策表里明确留给独立 CR 的部分。

**项③ — gate/advance detail 重复回显 blockers 原文**：`evaluatePassCondition`（`crctl.mjs:551/554`）在失败条件的 detail 中把 `val` 全量写进 `actual`，`why` 又 `JSON.stringify` 一次。`runGateChecks` 生成的 passCondition check 只有 `detail`、没有顶层 `why`；`cmdAdvance` 只汇总顶层 `check.why`，所以 `GATE_BLOCKED` message 本身并不含 blockers 原文，冗余实际位于 `gate.checks[].detail[].actual` 与 `.why` 两处。此项由 CR-2026-024 SDD 评审过程实测发现。

**项④ — `review-record` 追溯投影与 `cmdNext` 回修路由缺口**：三个评审 Skill 均要求将 canonical 评审记录同步投影到 `traceability.yml#reviews.<stage>`，但当前 `review-record` 只写 `review-annotations/<stage>.yml`，再单独写 `review-loop.yml`，既未更新 traceability，也可能在第二步失败时留下半状态；同时 `cmdNext` 在 `drafting` 只看 `prd.md` 是否存在，刚产生 requirement block 时仍错误建议再次评审。若只按“存在 block 就回修”修补，PRD 已回修后旧 block 又会导致永久回修，因此还需以被评审 PRD 的规范化内容摘要判断该证据是否仍然新鲜。

四项的共同点是**本包已有机制但缺最后一环**：①有声明面无校验、②有数据有 prompt 规则无账本守卫、③有单一事实源却重复回显、④有评审证据与最小 runner 却缺投影一致性和回修路由。

#### 1.2 解决方案摘要

- **项①**：`check-skill-matrix.mjs` 新增第 4 项检查——每个 actor 级 `external` 声明必须在 `skills/**/*.md` 或 `pipeline-templates/*.json` 中找到至少一处引用点，零引用即报错退出非 0；`agent-skill-matrix.yml` 顶层从未被解析的 `external-skills:` 块**保留不删**、标记为非权威纯文档参考，并同步 `AGENT-SKILL-MATRIX.md`/`skills/_index.yml` 的声明位置表述，明确 actor 级 `external` 是唯一权威且唯一被程序解析的声明位置；顶层块不参与校验、无同步要求。新建 `check-skill-matrix.test.mjs`。
- **项②**：`crctl task done` 在 CAS 写入前校验目标 TASK 的**直接** `depends-on` 前置项均已 `done`，否则以 `DEPENDS_ON_NOT_DONE` 拒写并列出未完成前置（成环的 TASK 天然互相卡在此错误码上，不做传递闭包遍历、不单独检测环）。复用既有 `parseYaml`（实测已能解析 `depends-on: [A, B]` 内联流式数组），零新增解析代码。
- **项③**：仅收敛 `evaluatePassCondition` 的 `isEmpty` 失败分支——数组型 `actual` 保持数组类型并按 `ITEM_MAX=120` 逐项截断，`why` 只给条数并指向 `file` 字段已有的证据文件路径；不改 `equals`、`cmdAdvance` 或 `fail()`。
- **项④**：`review-record` 按既有 stage 映射一次性生成 canonical annotation、review-loop 与 `traceability.yml#reviews.<stage>` 投影，并经既有 `casWriteMulti` 统一写入；requirement 评审记录增加按 `CRLF → LF` 规范化后的 PRD SHA-256。`cmdNext` 在 `drafting` 下用 verdict/blockers 与该摘要判断“尚未回修→`write-requirement-prd`”或“PRD 已变化→`review-requirement`”。

#### 1.3 事实基线（已核实，纪律 #4）

| # | 事实 | 位置 / 依据 |
|---|---|---|
| B-1 | `check-skill-matrix.mjs` 现有 3 项检查（active skill 恰一个 owns / owns 目标已注册或声明为 external / md 表格与 yml 一致），无任何引用点校验 | `check-skill-matrix.mjs:6-9,66-89` |
| B-2 | 该脚本把 `external` 解析成**全局 Set**（`externalSkills`），不记录声明它的 actor | `check-skill-matrix.mjs:36,46` |
| B-3 | actor 级 `external` 共 8 处声明、跨 4 个 actor（product-planning-agent / dev-agent / competitive-analyst-agent / system-orchestrator）；实测引用点：`brainstorming`(product-planning-agent)=1、`brainstorming`(competitive-analyst-agent)=1、`executing-plans`=2、`subagent-driven-development`=2、`test-driven-development`=2、`using-superpowers`=0、`writing-plans`=0、`verification-before-completion`=0 | 本 CR 需求期实跑扫描（skills/ + pipeline-templates/，排除 openwiki/old） |
| B-4 | `brainstorming` 被两个 actor 声明，但唯一引用点 `skills/competitive/report-to-planning-suggestion/SKILL.md` 归 `competitive-analyst-agent` owns（`agent-skill-matrix.yml:165`、`AGENT-SKILL-MATRIX.md:28`）——actor 级严格口径会把 `product-planning-agent.external.brainstorming` 判为零引用 | 实跑核对 |
| B-5 | 顶层 `external-skills:` 块（`agent-skill-matrix.yml:222-230`）条目缩进 2 空格，而 checker 的条目正则要求 6 空格（`check-skill-matrix.mjs:44`）——**从未被解析**；但 `AGENT-SKILL-MATRIX.md:57` 写明「外部方法论 Skill 只能出现在 `external` 或 `external-skills` 中」，把它当作合法声明位置 → 两份事实源 | 实跑核对 |
| B-6 | `cmdTaskDone`（`crctl.mjs:1298-1310`）只校验 status=developing、TASK 存在、非已 done 三项，**零依赖校验**；审计记录里 `before.from` 硬编码为 `'pending'` | 源码 |
| B-7 | `tasks/_index.yml` 的 `depends-on` 为内联流式数组（如 `depends-on: [CR-2026-001-TASK-01, CR-2026-001-TASK-02]`）；实测既有 `parseYaml` 能正确解析（含空数组 `[]`） | 需求期对 `parseYaml` 的实跑探针 + CR-2026-001/002/003 真实 `_index.yml` 样本 |
| B-8 | `crctl task allocate` 生成的条目只含 `id`/`slug`/`status` 三字段，不含 `depends-on`（`appendTaskEntry`，`crctl.mjs:1854`）——字段缺失是正常形态 | 源码 |
| B-9 | `evaluatePassCondition` 的 `equals` 与 `isEmpty` 两分支各把 `val` 同时写进 detail 的 `actual` 与 `why` | `crctl.mjs:551,554` |
| B-10 | `runGateChecks` 的 passCondition check 写入 `detail`，但没有顶层 `why`；`cmdAdvance` 仅汇总顶层 `check.why`，因此 blockers 原文未进入 `GATE_BLOCKED` message，只存在于序列化的 `gate.checks[].detail[].actual/.why` | `crctl.mjs:600-604,995-998` |
| B-11 | CR-2026-024 的长 blockers 实测证明 detail 中 `actual`/`why` 重复原文并显著放大输出；具体体积受 JSON 缩进、路径与文案影响，不宜作为跨环境百分比验收基线 | 需求期实跑核对 |
| B-12 | `cmdNext` 在 `drafting` 只检查 `prd.md` 是否存在，存在即返回 `review-requirement`，不读取 requirement annotation；而 requirement block 按既有流程保持 `drafting` | `crctl.mjs:2215-2218` + `review-requirement/SKILL.md:91-92` |
| B-13 | `check-skill-matrix.mjs` **无测试文件**：`skills/shared/crctl/scripts/test/` 下只有 `crctl.test.mjs` 与 `lint-prompts.test.mjs` | 目录实测 |
| B-14 | 测试约定：`node --test <file>`，零第三方依赖，仅用 `node:test`/`node:assert`，通过 `spawnSync` 黑盒调用被测脚本 | `ARCHITECTURE.md:104`、`crctl.test.mjs` 头注释 |
| B-15 | `gates.json` 的 `passCondition` 判据不写死在 crctl 里，运行时从 pipeline JSON 的 `reviewLoop.passCondition.allOf` 读取——本 CR 只改回显形态，不触判据来源 | `crctl.mjs:528-536` |
| B-16 | `review-record` 当前先写 canonical annotation，再调用 `bumpAttempt` 单独全量写 `review-loop.yml`，不触及 `traceability.yml`；任一后续步骤失败会留下已更新 annotation、未更新其他投影的半状态 | `crctl.mjs:1394-1423` |
| B-17 | `review-requirement`、`review-tech-design`、`review-code` 均以同一 `review-record --stage` 命令落盘，stage 已有 annotation 文件与 loop 显式映射 | `REVIEW_STAGE_FILES` / `REVIEW_STAGE_LOOPS` |
| B-18 | 既有 `casWriteMulti` 已提供“全校验→全写 temp→连续 rename”的多文件 CAS 语义，并明确接受连续 rename 间进程崩溃的极小窗口 | `crctl.mjs:684-712` |

#### 1.4 决策点（本 PRD 拍板，SDD/实施期不得再次悬置）

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 项①规则粒度：全局名级 vs actor 级 | **全局名级**——同一名称在扫描范围内有 ≥1 引用点即通过，不要求引用点位于声明该 external 的 actor 自己 owns 的 skill 内 | actor 级需新引入「SKILL.md ↔ owns actor」归属映射（当前 checker 无此映射），且按 B-4 会立刻把 `product-planning-agent.external.brainstorming` 判红——而 `brainstorming` 恰是方案认定的「唯一四件套齐全样板」。收紧到 actor 级列为后续项 |
| D-2 | 顶层 `external-skills:` 块处置 | **保留原块**，块上方加注释标记其为纯文档参考、不被任何程序解析；同步修订 `AGENT-SKILL-MATRIX.md:57` 使 actor 级 `external` 成为唯一被 `check-skill-matrix` 解析的声明位置 | 该块从未被解析（B-5），但块内的 `systematic-debugging` 是 CR-2026-024 SDD §0 C-5 明确决定「仅存于顶层纯文档块，不动」的保留位——该名称在仓库内零引用点，整块删除会使其彻底消失，等同静默推翻 024 已拍板的决策。真正的「两份事实源」成因是 `AGENT-SKILL-MATRIX.md:57` 把装饰块写成了合法声明位置，只改这一行即可消除，无需删块 |
| D-3 | 与 CR-2026-024 的实施先后 | **本 CR 必须在 CR-2026-024 批次一合入之后实施** | B-3 实测三处零引用声明由 CR-2026-024 删除；本 CR 若先落，新规则上线即报 3 项红（外加 CR-2026-024 删 `test-driven-development` 引用后的第 4 项），把存量债务算到新守卫头上 |
| D-4 | 项②守卫的失败形态：硬失败 vs WARN | **硬失败拒写**，错误码 `DEPENDS_ON_NOT_DONE`，不提供绕过旗标 | crctl 既有风格一致为拒写（`TASK_ALREADY_DONE`/`ILLEGAL_LEDGER_STATE`/`CAS_CONFLICT` 皆 `fail`）；WARN 会重蹈 `depends-on`「声明了没人消费」的覆辙——本 CR 的存在理由正是把建议升级为强制 |
| D-5 | `depends-on` 字段缺失的语义 | **视为无依赖，放行** | B-8：`task allocate` 生成的条目本就不含该字段，缺失是正常形态而非异常 |
| D-6 | 环检测是否纳入本 CR | **不纳入** | FR-6 校验的是目标 TASK 的**直接** `depends-on`（一跳），不做传递闭包遍历；成环的 TASK（含自引用）里每个成员都在等另一个成员先 done，天然全部卡在 `DEPENDS_ON_NOT_DONE`，依赖顺序已被保证。环检测在一跳口径下是需要额外遍历依赖图才能做到的净新增代码，而非「同一次遍历的副产品」——原决策的前提不成立；提示"这是环"的可读性诉求改由 FR-6 错误文案的一句话覆盖 |
| D-7 | `ITEM_MAX=120` 是否做成可配置项 | **常量，不做配置面** | 包内无同类阈值配置先例；配置项本身要新增读取/校验/文档三处成本，而该值只影响可读性不影响正确性 |
| D-8 | 项①测试形态 | **新建 `check-skill-matrix.test.mjs`**，沿用 `node --test` + `spawnSync` 黑盒（B-14） | 该脚本此前无测试（B-13）；新增可执行规则却不留可执行验证，与本 CR 主题自相矛盾 |
| D-9 | 项③是否修改 `equals`、`cmdAdvance` 或 `fail()` | **不改**——只处理 `isEmpty` 数组失败 detail | B-10 证明 message 没有 blockers 原文；扩大到标量 equals 或错误框架没有收益 |
| D-10 | traceability 投影覆盖范围 | **按既有 stage 映射一次修好 requirement / tech-design / code**，不做 requirement 特判 | 三阶段共享同一 `review-record` 契约；共用一套投影函数比三个阶段分别补丁更小，也避免后续继续漂移 |
| D-11 | `review-record` 多文件一致性 | canonical annotation、`review-loop.yml` 与 `traceability.yml` 在完成全部解析/轮次检查后，使用同一个时间戳生成并交给既有 `casWriteMulti`；不另造事务机制 | 复用 B-18，遵循 tools 账本唯一写入点与失败不写原则 |
| D-12 | `cmdNext` 如何区分“尚未回修”与“已回修” | requirement annotation 记录评审时 `prd.md` 的 LF 规范化 SHA-256；`cmdNext` 比较当前摘要，不使用文件 mtime | 仅检查 block 会形成永久回修；mtime 会被 checkout/autocrlf 扰动，规范化摘要可重复验证且符合行尾纪律 |

### 2. 用户故事

- **US-1** 作为 tools 包维护者，当我在 `agent-skill-matrix.yml` 里声明一个 `external` 技能却没有在任何 SKILL.md 或 pipeline prompt 里真正引用它时，`check-skill-matrix.mjs` 立刻报错，而不是让这条死声明在仓库里躺过多个 CR 周期无人察觉。
- **US-2** 作为 tools 包维护者，我只需在唯一权威位置（actor 级 `external`）声明外部技能依赖；顶层 `external-skills` 仅是非权威历史参考，不参与程序校验，也不要求同步。
- **US-3** 作为 `dev-agent`（实现者），当我试图把一个前置 TASK 尚未完成的 TASK 标记为 done 时，`crctl task done` 拒绝写入并告诉我在等哪几个前置项，而不是静默接受、留下一个依赖顺序被违反却看不出来的账本。
- **US-4** 作为 `dev-agent`，当 `tasks/_index.yml` 的依赖关系意外成环时，环上的每个 TASK 都会因直接前置未 done 被 `crctl task done` 拒写（`DEPENDS_ON_NOT_DONE`），不会出现依赖顺序被违反的账本，命令也不会陷入遍历死循环。
- **US-5** 作为评审者/审批人，当门禁因 blockers 非空而拒绝推进时，`crctl gate` / `crctl advance` 的输出让我一眼看清「哪几条没过」，而不是把同一份长文本 blockers 重复三遍刷屏。
- **US-6** 作为调用 crctl 的上层程序（pipeline runtime / 桌面壳），`gate` 输出的 `actual` 字段仍是数组，我原有的 `.length` 类取值不会因这次改动而失效。
- **US-7** 作为任一评审阶段的执行者，我调用一次 `review-record` 后，annotation、review-loop 与 traceability 的 stage 投影保持一致，不需要模型手改 YAML 账本。
- **US-8** 作为 requirement-authoring 流程执行者，需求评审 block 后 `crctl next` 会先指向 PRD 回修；PRD 内容修订后，同一命令会转为指向重新评审，不会在两个节点间误路由或死循环。

### 3. 功能需求

#### 项① · external 声明引用校验（D-2 落地）

- **FR-1（新增检查 4：external 引用点校验）**：`check-skill-matrix.mjs` 新增第 4 项检查——对每个从 actor 级 `external:` 解析出的技能名，在扫描范围内统计引用点数量；为 0 时记入 `errors`，错误文案须包含技能名、声明它的 actor（复数则全列）与「零引用点」判定语，退出码非 0。文件头部注释的「检查项」清单同步补第 4 条。
- **FR-2（引用点扫描口径）**：扫描范围 = `skills/` 与 `pipeline-templates/` 下的 `*.md` 与 `*.json` 文件（递归），**排除** `openwiki/`、`old/`、`node_modules/`、`.git/`；命中判定为文件文本包含该技能名（子串匹配即可，与 CR-2026-024 认定死声明时所用口径一致）。`agent-skill-matrix.yml` 与 `AGENT-SKILL-MATRIX.md` 自身不计入引用点（声明面不能自证）。
- **FR-3（解析器记录声明 actor + 行尾规范化）**：现有解析把 external 收进全局 `externalSkills` Set（B-2），需扩展为同时记录 `externalByActor`（actor → 技能名[]）以支撑 FR-1 的错误文案；检查 2 继续使用全局集合，行为不变。脚本现有文本读入点统一先执行 `\r\n → \n` 规范化，逐行解析使用 `split(/\r?\n/)`；匹配不到预期结构必须硬失败，不得静默降级为空集合。
- **FR-4（顶层 external-skills 块标记为纯文档 + 声明位置文档统一，D-2）**：`agent-skill-matrix.yml` 的顶层 `external-skills:` 块（L222-230）**保留不删**，块上方新增注释「纯文档参考，不被任何程序解析；唯一被 check-skill-matrix 解析的声明位置是 actor 级 external」；同步修订 `AGENT-SKILL-MATRIX.md:57`「外部方法论 Skill 只能出现在 `external` 或 `external-skills` 中」为「只能出现在 actor 级 `external` 中」。`skills/_index.yml:308-310` 现逐一点名 6 个外部技能，同步删除具体名称列举，改写为不点名的通用说明（指向 `agent-skill-matrix.yml` 的 actor 级 `external`），避免该注释随 external 声明增减而过时。
- **FR-5（新建 check-skill-matrix 测试，D-8）**：新建 `skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs`，`node --test` + `spawnSync` 黑盒，零第三方依赖。至少覆盖：① external 有引用点 → 通过；② external 零引用点 → 退出码非 0 且错误含技能名；③ 同一 external 被多 actor 声明且有引用点 → 通过（`brainstorming` 形态，B-4）；④ 同一 external 被多 actor 声明且零引用 → 错误同时列出全部声明 actor；⑤ CRLF 夹具与同内容 LF 夹具结果一致；⑥ 既有三项检查的回归各至少一条（缺归属 / 目标缺失 / md 漂移）。

#### 项② · depends-on 依赖守卫（D-5 落地）

- **FR-6（task done 依赖守卫，一跳口径，D-6）**：`crctl task done <cr> --task <TASK-ID>` 在 `casWrite` 之前，解析 `tasks/_index.yml`，读取目标 TASK 的 `depends-on`（仅校验**直接**前置，不做传递闭包遍历）；若其中存在 `status != done` 的前置 TASK，以 `DEPENDS_ON_NOT_DONE` 硬失败拒写（D-4），错误 detail 须列出**未完成前置的 id 与当前 status**，message 末尾追加一句「若前置互相等待，检查 depends-on 是否成环」。校验发生在既有三项前置校验（status=developing / TASK 存在 / 非已 done）之后、写入之前。
- **FR-7（缺失与空值语义，D-5）**：`depends-on` 字段缺失或为空数组 `[]` 时视为无依赖，直接放行；`depends-on` 指向 `tasks/_index.yml` 中不存在的 TASK-ID 时以 `DEPENDS_ON_UNKNOWN` 失败（引用悬空本身即缺陷，不静默忽略）。
- **FR-8（复用既有解析器）**：依赖解析必须复用 crctl 既有的 `parseYaml`（B-7 实测已支持内联流式数组与空数组），**不得**新写 YAML 解析或正则提取；读入后先 `\r\n → \n` 规范化（纪律 #1）。
- **FR-9（用途表与文档同步）**：`skills/shared/crctl/SKILL.md` 的用途表补 `task done` 的依赖守卫说明与两个新错误码（`DEPENDS_ON_NOT_DONE` / `DEPENDS_ON_UNKNOWN`）；`README.md` 若含 `task done` 行为描述则同步。CR-2026-024 在 `implement-code/SKILL.md` 落的 prompt 层拓扑排序表述需补一句「依赖顺序由 `crctl task done` 机械强制」，使 prompt 层规则与账本守卫互为印证而非各说各话。
- **FR-10（crctl 测试向量）**：`crctl.test.mjs` 追加向量覆盖：① 前置未 done → `DEPENDS_ON_NOT_DONE` 且退出非 0、`_index.yml` 未被修改；② 前置全 done → 正常写入 `status: done` 与 `done-at`；③ `depends-on` 缺失/空数组 → 放行；④ 指向不存在 TASK → `DEPENDS_ON_UNKNOWN`；⑤ `depends-on` 写成带引号形态（如 `["CR-2026-XXX-TASK-NN"]`，仓内实测 16 处存在此写法）→ 与不带引号等价放行/拒写（钉住 `parseYaml` 的 unquote 路径）。

#### 项③ · gate/advance blockers 回显收敛

- **FR-11（`isEmpty` 数组失败逐项截断）**：在 `evaluatePassCondition` 作用域内引入常量 `ITEM_MAX = 120` 与纯函数 `briefArray(v)`；仅当 `isEmpty` 失败且实际值为数组时，`actual` 保持数组类型并逐项截断，字符串超长时追加 `…(+N字)` 标记，非字符串数组项维持原值。
- **FR-12（`isEmpty` why 收敛）**：仅修改 `isEmpty` 失败分支：数组型实际值的 `why` 写为 `期望 <path> 为空，实际 N 条（详见 <doc.path>）`，不得包含任一完整原文。`equals` 分支、`runGateChecks` 顶层 check、`cmdAdvance` 与 `fail()` 均保持现状。
- **FR-13（`actual` 类型契约不变）**：截断后 `actual` 仍为数组，调用方既有的 `.length`/索引取值不受影响（NFR-3）；全量值仍只存在于 `file` 指向的 canonical 证据文件。
- **FR-14（取舍写进注释）**：改动处须有注释写明——本收敛**只封单条长度、不封条数**，条目数极多时输出仍会线性增长；以及全量原文来源是 `file` 字段指向的 `review-annotations/{stage}.yml`。
- **FR-15（crctl 测试向量）**：`crctl.test.mjs` 追加向量：构造含超长 blockers 的评审证据后跑 `gate --for <评审通过态>` 与失败的 `advance`，断言 ① 退出码非 0；② `checks[].detail[].actual` 仍是数组且每项长度 ≤ `ITEM_MAX + 后缀长度`；③ detail 的 `why` 含条数与 `详见` 指针且不含完整原文；④ `GATE_BLOCKED` message 维持现状且不含 blocker 原文；⑤ 标量 `equals` 失败输出与改动前一致。

#### 项④ · review-record 投影一致性与 cmdNext 回修路由

- **FR-16（三阶段 traceability 投影）**：`crctl review-record` 按既有 stage 映射统一更新 `traceability.yml#reviews.<stage>`：`requirement → reviews.requirement`、`tech-design → reviews.tech-design`、`code → reviews.code`。投影至少包含 reviewer、verdict、reviewed-at、blocker-count、annotation 路径、repair-target 及 review-loop 的 current-attempt/max-attempts/attempts；repair-target 分别为 `write-requirement-prd`、`write-tech-design`、`implement-code`。不为三个 stage 分别实现独立写入流程。
- **FR-17（三账本一致写入）**：`review-record` 在任何受控文件落盘前完成 payload schema、stage、前置状态、轮次上限、traceability 结构与 CR-ID 一致性检查；一次生成 `recordedAt`。带 `--bump-attempt` 时，据此构造 canonical annotation、`review-loop.yml` 与 traceability 投影的新文本，再复用既有 `casWriteMulti` 统一写入；未带该旗标时只对 annotation 与 traceability 做多文件 CAS，`review-loop.yml` 保持不变并将其当前轮次投影到 traceability。任一文件前置校验或 CAS 失败时本次涉及的受控文件均不得变化；保留 B-18 已接受的连续 rename 间进程崩溃窗口，不另造事务/恢复系统。
- **FR-18（traceability 创建与定点更新）**：`traceability.yml` 不存在时，`review-record` 可创建最小 `cr-id + reviews` 骨架；已存在时只定点新增或替换目标 `reviews.<stage>`，必须保留其他 stage、tests 及未知扩展段。CR-ID 不匹配、目标 stage 重复或结构无法唯一定位时硬失败，不得静默重写整份账本。行级处理前执行 `\r\n → \n` 规范化，解析/定位失败不得降级。
- **FR-19（requirement 被评审内容摘要）**：`review-record --stage requirement` 在 canonical annotation 中写入 `subject-file: change-requests/<CR-ID>/prd.md` 与 `subject-sha256`；摘要对 UTF-8 文本先执行 `\r\n → \n` 再 SHA-256，时间戳或文件 mtime 不参与判定。tech-design/code 本次不新增摘要消费逻辑。
- **FR-20（cmdNext drafting 路由）**：`cmdNext` 在 `drafting` 按以下优先级决定下一步：① `prd.md` 缺失 → `write-requirement-prd`；② requirement annotation 为 block 或 blockers 非空，且其 `subject-sha256` 等于当前 PRD 规范化摘要 → `write-requirement-prd`，why 含 blocker 条数与 annotation 路径；③同一失败证据的摘要与当前 PRD 不同 → `review-requirement`（说明 PRD 已变化、需刷新证据）；④无失败证据 → 保持现有 `review-requirement`。不得仅凭旧 block 永久回修，也不得使用 mtime。缺少 `subject-sha256` 的旧证据保持改动前兼容行为（PRD 存在即 `review-requirement`），不在本 CR 做历史迁移。
- **FR-21（项④测试向量）**：`crctl.test.mjs` 至少覆盖：① requirement/tech-design/code 三个 stage 均生成正确 `reviews.<stage>` 投影；② `--bump-attempt` 后三账本 attempt/verdict/blocker-count/时间一致，第二轮替换当前投影并保留 attempts 历史；③ trace 缺失时创建、已有其他段时保留；④ trace 结构错误或注入 CAS 失败时三账本内容均不变且 payload 保留；⑤ `drafting + 同摘要 block → write-requirement-prd`；⑥修改 PRD 实质内容后 → `review-requirement`；⑦仅 LF/CRLF 差异不视为已回修；⑧无摘要旧证据维持兼容行为。

#### 收尾

- **FR-22（验证关卡）**：`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce` 全绿；`node --test` 跑通 `crctl.test.mjs`、`lint-prompts.test.mjs`、新增的 `check-skill-matrix.test.mjs` 三个测试文件全部用例。
- **FR-23（溯源标注）**：commit message 注明来源为方案 v2.6 §7（D-2/D-5）、CR-2026-024 SDD 评审实测与 CR-2026-025 需求评审发现的 Tools 流程缺口，并含 CR-2026-025 编号；全部改动不引入本机绝对路径。
- **FR-24（ARCHITECTURE.md 登记）**：若本 CR 改动落在 `ARCHITECTURE.md` §3/§5/§6 覆盖面（crctl 命令面语义扩展、守卫面新增），按 §8 维护规则登记本 CR；测试文件新增同步 §8 代码地图与 `dir-graph.yaml`。

### 4. 非功能需求

- **NFR-1（零新增第三方依赖）**：四项改动全部使用 `node:` 内置模块，测试仅用 `node:test`/`node:assert`（B-14）。
- **NFR-2（状态机与既有核心 schema 稳定）**：不新增/修改 CR 状态与转换，不改 `tasks/_index.yml` 或 `gates.json` schema。项④只落实既有 traceability review 投影契约，并在 requirement annotation 增加两个向后兼容的标量字段 `subject-file`/`subject-sha256`；不新增状态、转换、CLI 子命令或迁移命令。
- **NFR-3（gate 输出向后兼容）**：`actual` 字段类型契约不变（数组仍是数组）；新增的截断标记只出现在字符串内部，不改变 JSON 结构层级或字段名。
- **NFR-4（判据来源不变）**：项③不触碰 `passCondition` 的判据解析路径（B-15：判据仍运行时读自 pipeline JSON 的 `reviewLoop.passCondition.allOf`），只改结果的呈现。
- **NFR-5（实施顺序依赖，D-3）**：本 CR 的项①实施与验证必须在 CR-2026-024 批次一合入 `custom/main` 之后进行；若 CR-2026-024 未合入，FR-22 的 `check-skill-matrix` 全绿要求无法满足（B-3 的 3~4 项零引用声明会报红）。SDD 需据此排定实施顺序。
- **NFR-6（行尾纪律，纪律 #1）**：项① checker 文本、项② `_index.yml`、项④ PRD 摘要与 traceability 文本读入后均先 `\r\n → \n` 规范化再解析/摘要；逐行解析使用 `split(/\r?\n/)`，解析或跨行定位失败硬失败，不静默降级。
- **NFR-7（可移植性）**：改动与测试不含本机绝对路径；测试用临时目录（`mkdtempSync`）构造夹具，与既有 `crctl.test.mjs` 风格一致。
- **NFR-8（不引入通用解析框架）**：项②复用 `parseYaml`（FR-8）；项①沿用 `check-skill-matrix.mjs` 既有行级解析风格；项④只增加 traceability `reviews.<stage>` 的受控定点编辑函数，不引入 YAML 库或通用序列化器。
- **NFR-9（基线协调）**：tools 仓工作区若存在与本 CR 无关的未提交修改（已知存在 `.qoder/repowiki/` 等删除态文件），提交时只 add 本 CR 文件清单，严禁 `git add -A`。
- **NFR-10（投影事实源）**：`review-annotations/<stage>.yml` 与 `review-loop.yml` 是评审结论和轮次的 canonical 证据，`traceability.yml#reviews.<stage>` 是由 `review-record` 同步生成的可追溯投影；模型不得直接手改三者补齐一致性。

### 5. 验收标准

- **AC-1**（FR-1/FR-3）：在 `agent-skill-matrix.yml` 某 actor 的 `external` 下插入一个仓库内零引用的技能名后运行 `check-skill-matrix.mjs`，退出码非 0 且 stderr 含该技能名与声明它的 actor；移除后恢复通过。
- **AC-2**（FR-2）：只在 `openwiki/` 下出现的技能名**不**计为引用点（仍判红）；只在 `pipeline-templates/*.json` 的 prompt 中出现的技能名**计为**引用点（判绿）。
- **AC-3**（FR-1）：`check-skill-matrix.mjs` 文件头注释的「检查项」清单含第 4 条引用点校验描述。
- **AC-4**（FR-4）：`agent-skill-matrix.yml` 顶层 `external-skills:` 块仍存在，块上方含「纯文档参考，不被解析」的注释；`AGENT-SKILL-MATRIX.md` 中该表述已改为「actor 级 `external`」且不再提 `external-skills` 是合法声明位置；`skills/_index.yml:308-310` 的外部方法论技能名枚举已删除，改为不点名的通用说明。
- **AC-5**（FR-4/FR-22）：CR-2026-024 批次一合入后的真实仓库上运行 `check-skill-matrix.mjs` 通过——即 `brainstorming`×2、`executing-plans`、`subagent-driven-development` 四项声明全部有引用点（B-3 预期终态）。
- **AC-6**（FR-3/FR-5/D-8）：`skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs` 存在；`node --test` 跑通且含 FR-5 列出的全部向量，CRLF/LF 夹具结果一致；无第三方依赖 import。
- **AC-7**（FR-6/FR-10）：前置 TASK 为 `pending` 时执行 `crctl task done` → 退出码非 0、错误码 `DEPENDS_ON_NOT_DONE`、detail 列出该前置 id 与 status，且 `tasks/_index.yml` 内容 sha256 与执行前一致（确认未写入）。
- **AC-8**（FR-6）：前置 TASK 全部 `done` 时执行 `crctl task done` → 正常写入 `status: done` 与 `done-at`，行为与改动前一致。
- **AC-9**（FR-7）：`depends-on` 缺失与 `depends-on: []` 两种形态均放行；`depends-on` 指向不存在的 TASK-ID 时报 `DEPENDS_ON_UNKNOWN`。
- **AC-10**（FR-8/NFR-6/NFR-8）：项②的依赖解析不新增 YAML 提取正则或解析器，直接调用既有 `parseYaml`；构造 A→B→A 与自引用 A→A 两种夹具，均在有限时间内返回且报 `DEPENDS_ON_NOT_DONE`（一跳口径下环上每个成员的直接前置均非 done，不产生死循环）。
- **AC-11**（FR-9）：`skills/shared/crctl/SKILL.md` 用途表含 `task done` 依赖守卫与两个新错误码；`implement-code/SKILL.md` 的拓扑排序表述含「由 `crctl task done` 机械强制」一句。
- **AC-12**（FR-11/FR-12/FR-13）：对含 7 条各约 500 字 blockers 的证据跑 `crctl gate --for <评审通过态>`——`checks[].detail[].actual` 仍为数组、每项字符串长度 ≤ `120 + 后缀长度`；`why` 形如 `期望 blockers 为空，实际 7 条（详见 …/sdd.yml）`，两者均不含任一完整 blocker 原文；不使用输出体积百分比作为验收条件。
- **AC-13**（FR-12/FR-15）：同一证据执行失败的 `crctl advance` 时，`GATE_BLOCKED` message 维持现有摘要行为且不含 blocker 原文；序列化的 gate detail 只包含截断后的数组和条数指针；标量 `equals` 失败快照与改动前一致。
- **AC-14**（FR-14）：改动处注释含「只封单条长度、不封条数」与全量原文来源的说明。
- **AC-15**（FR-15/FR-10）：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿，含项②五类与项③五类新增断言。
- **AC-16**（FR-22）：三件套全绿 + 三个测试文件全部用例通过。
- **AC-17**（FR-23/FR-24）：commit message 含 CR-2026-025 与来源溯源；`grep -r "C:\\\\Users"` 在本 CR 改动中零命中；`ARCHITECTURE.md` §8 按需登记，新增测试文件已登记代码地图与 `dir-graph.yaml`。
- **AC-18**（NFR-5/D-3）：SDD 与实施记录显式声明本 CR 在 CR-2026-024 批次一之后实施；AC-5 的验证在该前提下执行。
- **AC-19**（FR-16/FR-18）：分别以 requirement、tech-design、code payload 执行 `review-record`，对应的 `reviews.requirement`、`reviews.tech-design`、`reviews.code` 投影字段、annotation 路径与 repair-target 均正确；更新一个 stage 时其他 stage、tests 与未知扩展段字节内容保持不变。
- **AC-20**（FR-17）：`review-record --bump-attempt` 成功后 annotation、review-loop 与 traceability 中的时间、attempt、verdict、blocker-count 一致；第二轮记录的 current-attempt 为 2 且 trace attempts 同时保留第 1、2 轮结果。任一前置校验/CAS 注入失败时三文件 sha256 均与执行前一致，临时 payload 保留。
- **AC-21**（FR-18）：traceability 缺失时自动创建最小合法骨架；CR-ID 不匹配、重复 stage 或无法唯一定位时结构化失败且不改任何受控文件，不产生静默空投影。
- **AC-22**（FR-19/FR-20）：requirement block 记录生成后立即运行 `crctl next` 返回 `write-requirement-prd`；实际修改 PRD 内容后返回 `review-requirement`；只在 LF/CRLF 间转换时仍返回 `write-requirement-prd`；旧 annotation 缺少摘要时保持“PRD 存在→review-requirement”的兼容行为。
- **AC-23**（FR-21）：`crctl.test.mjs` 包含 FR-21 全部八类向量并通过，且未引入文件 mtime 判定、历史迁移命令或第三方 YAML 库。

### 6. 成功指标

- `external` 死声明的复发被机械阻断：新增一条零引用 external 声明会在 pre-commit/CI 阶段直接报红，不再依赖人工评审发现（CR-2026-024 是靠人工逐条实测才挖出三条）。
- `external` 权威声明位置收敛为一处：actor 级 `external` 是唯一权威且唯一被程序解析的声明；顶层 `external-skills` 明确为非权威历史参考，不参与校验且无同步要求。
- `depends-on` 从「声明了没人消费」升级为账本级强制：任何**声明了 `depends-on`** 的 TASK，违反依赖顺序执行 `task done` 都被拒写并留下可读的未完成前置清单（`crctl task allocate` 生成的条目不含该字段，按 D-5 视为无依赖，不在此列）；`depends-on` 的四层链条（声明→写入→汇总→校验）终于接上第五层（驱动行为）。
- 门禁输出可读性：真实 blockers 场景下 `gate`/`advance` detail 不再重复完整长文本，仍保留失败条数和 canonical 文件指针；不以跨环境不稳定的体积百分比作为指标。
- 三阶段评审记录由一个 `review-record` 写入点同步形成 annotation、轮次与 traceability 投影；任一正常执行后不再出现 stage 投影落后于 canonical 证据的情况。
- requirement block 后 `crctl next` 能稳定形成“回修→内容变化→重审”的闭环，不把未回修 PRD送去重审，也不被旧 block 永久困在回修节点。
- 四项均有可执行测试兜底，`check-skill-matrix.mjs` 从零测试变为有测试。

### 7. 范围排除

**本 CR 包含**：项①②③④的代码改动、各自测试向量、直接相关的用途表/文档同步；项④明确包含 `review-record` 三阶段投影和 `cmdNext` requirement 回修/重审路由。

**本 CR 不包含**：
- **actor 级 external 引用校验的收紧**（要求引用点必须位于声明该 external 的 actor 自己 owns 的 skill 内）——需新引入 SKILL.md↔owns 归属映射，且会牵出 `product-planning-agent.external.brainstorming` 的合法性判断（D-1、B-4），自成独立议题。
- **`can-call` / `forbidden` 的引用校验**——本 CR 只处理 `external`；`forbidden` 已由 CR-2026-024 明确为声明性边界、无调用级拦截，不在此改变其性质。
- **`lint-prompts` 新增「未注册技能名」规则**——CR-2026-024 评审期确认 R1~R9 无此规则，但那属 prompt 正文治理面，与本 CR 的矩阵声明面是两件事。
- **`cmdNext` 其他状态的路由或文案统一重构**——本 CR 只修 FR-20 定义的 `drafting` requirement 失败证据回修/重审路由；tech-design/code 既有路由及其他状态输出保持不变。
- **`ITEM_MAX` 配置化**（D-7）、**按条数封顶的二级截断**——只封单条长度是本 CR 的显式取舍（FR-15），条数封顶会让 `actual` 不再完整反映失败集合，属另一个取舍。
- **`capabilities` 真闭环 Level C**（CR-2026-024 D-3 已列）、**requirement/tech-design 阶段 suggestions 分流**（CR-2026-024 D-4 已列）——与本 CR 无关，继续留在各自后续项。
- **状态机 / `gates.json` / `rules.json` 本体改动**——本 CR 无此需求（NFR-2）；项④只修改最小 runner 的证据读取与下一节点建议，不新增转换。
- **通用 YAML AST/序列化器、跨进程事务日志或崩溃恢复器**——项④复用既有定点编辑与 `casWriteMulti`，接受 B-18 已声明的极小崩溃窗口。
- **tech-design/code 被评审对象摘要与 stale 路由**——本 CR 的摘要只服务 FR-20 的 requirement `drafting` 缺口；另外两阶段不新增摘要消费逻辑。
- **环检测（依赖成环时的显式 `DEPENDS_ON_CYCLE` 判定）**（D-6）——本 CR 只做一跳直接前置校验，成环 TASK 天然被 `DEPENDS_ON_NOT_DONE` 挡住，不做传递闭包遍历。
- **`external` 引用的有效性校验（被引技能在目标运行时是否真的可用）**——FR-2 采子串匹配，只能证明"仓库文本中提到过"，不能证明"引用在目标运行时可解析"；`test-driven-development` 当前判绿正是靠 `implement-code/SKILL.md`/pipeline prompt 里对未安装技能的引用文本本身（即 §1.1 自陈的失效模式本体），CR-2026-024 删除这两处引用后才归零。该上限本 CR 不解，留给运行时按需自行校验。
- **CR-2026-024 自身的任何改动面**——本 CR 与 CR-2026-024 均改动 `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`（024 改 actor 级 external 存量清理，本 CR 改顶层块注释与声明位置表述），文件面有重叠但改动区域不同、无冲突；存在实施顺序依赖（D-3/NFR-5）。

### 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-08 | v0.1.0 | Ray | 初始草稿（D-2 + D-5 + gate 回显收敛三项合并交付；事实基线 15 条经实跑核对，决策点 D-1~D-9 拍板） |
| 2026-08-08 | v0.2.0 | Ray | 需求评审 attempt-1 回修（4 blocker）：B-3 actor 数订正为 4；D-2 改为保留顶层 `external-skills:` 块（不删，避免与 CR-2026-024 SDD §0 C-5 冲突），FR-4 改为加注释 + 同步收敛 `skills/_index.yml` 技能名枚举；D-6/FR-8/AC-10（环检测）整项撤销，改为一跳直接前置校验天然挡环，FR-6~FR-18 顺延重编号；§7 订正"两 CR 文件面不重叠"为"文件重叠但区域不同"，并补环检测、external 引用有效性两条排除项；§6 成功指标限定为"声明了 depends-on 的 TASK"；FR-10 测试向量补带引号 TASK-ID 形态 |
| 2026-08-09 | v0.3.0 | OldBoy405 | 需求评审 attempt-2 回修（3 blocker + 用户确认扩围）：订正项③事实基线，只修改 `isEmpty` detail 并删除不可复算的体积百分比；明确 actor 级 `external` 为唯一权威/程序解析声明，顶层块仅作非权威参考；项①补 CRLF 规范化和回归夹具；新增项④，以共用 stage 映射同步 requirement/tech-design/code trace 投影，并以 LF 规范化 PRD 摘要修复 `cmdNext` 的 requirement 回修/重审路由。 |

## 编码前质量门禁（v0.27 · CR-2026-026）

## PRD — 开发计划与 TASK 合并评审门禁

### 1. 概述

#### 1.1 问题陈述

`code-implementation` pipeline 当前编码前主链为：

```text
write-dev-plan → write-dev-tasks（status → task-breakdown）
  → push-progress（可跳过）→ human_approval → approve-dev-start → implement-code
```

现有门禁只检查文件存在（`plan.md` 存在、`tasks/` 下至少一个 TASK 文件），没有一个强制 LLM 节点回答以下问题：

1. `plan.md` 是否完整承接已审批 SDD，而不是只满足文件存在。
2. TASK 集合是否完整覆盖 plan 与 SDD，而不是只满足至少有一个 TASK。
3. TASK 的依赖、接口签名、验收条件和涉及文件是否彼此一致、足以直接驱动编码。
4. `write-dev-tasks` 输出的 WARN（估算不一致、接口签名不一致）是否已被处理。

这些问题可能在 `review-code` 被间接发现，但该时点已完成编码，回修目标是 `implement-code`，无法自然修订 `plan.md` 和 TASK。结果是：发现得晚、修复路由不准确、已完成代码可能建立在错误任务拆分上。

**问题边界**：本 CR 补的是「已审批技术设计 → 可执行开发任务」之间的质量门禁，不重新评审 PRD，不替代技术设计评审。

#### 1.2 解决方案摘要

在 `write-dev-tasks` 与开发启动人工审批之间新增一个 `review-dev-plan` LLM 合并评审节点：

- **一次评审**：同时检查 `SDD → plan → TASK` 八类维度，不拆成 plan review + TASK review 两个节点。
- **PASS**：保持 `task-breakdown`，进入现有 push-progress → human_approval → approve-dev-start 流程。
- **BLOCK 双轨**：普通 plan/TASK blocker 回到 `tech-design-reviewed`，按 `write-dev-plan → write-dev-tasks → review-dev-plan` 顺序重放（最多 3 轮）；上游设计疑点回到 `tech-design-review-pending`，复用既有技术设计修订、评审与审批流程。
- **复用既有基础设施**：`review-record`、`review-loop.yml`、`traceability.yml`、`reviewLoop` 回修能力。
- **不新增**：具名状态、审批节点、独立账本类型。仅新增阶段证据 `review-annotations/dev-plan.yml`。
- **门禁升级**：`approve-dev-start` 从「只检查文件存在」升级为校验自动评审 passCondition + evidence digest。

#### 1.3 事实基线（来源：方案文档 §1）

| # | 事实 | 依据 |
|---|---|---|
| B-1 | `write-dev-plan` 读取已审批 `sdd.md` 生成 `plan.md`；`write-dev-tasks` 读取 plan+sdd 生成 TASK 与 `_index.yml`，推进到 `task-breakdown` | 方案 §1.1 |
| B-2 | `task-breakdown` 状态门禁只检查 `plan.md` 存在、`tasks/` 下至少有一个 TASK 文件 | 方案 §1.1 |
| B-3 | `approve-dev-start` 只校验 `plan.md`、`tasks/_index.yml` 等前置产物存在，由人类确认后推进到 `developing` | 方案 §1.1 |
| B-4 | `review-code` 在代码与测试完成后检查「代码 ↔ TASK ↔ SDD」一致性，回修目标是 `implement-code` | 方案 §1.1 |
| B-5 | 现有 reviewLoop 机制（requirement/tech-design/code）已支持 replayNodes、maxAttempts、passCondition、repair target 路由 | 方案 §3.3 |
| B-6 | `review-record` 已有共用 stage 映射（REVIEW_STAGE_FILES / REVIEW_STAGE_LOOPS / REVIEW_STAGE_EXPECT / REVIEW_REPAIR_TARGETS），新增 stage 只需加映射项；traceability 投影能力依赖 CR-2026-025 已落地能力 | 方案 §5.3；CR-2026-025 |
| B-7 | 状态机现有 15 个具名状态 + 注册前 `(new)`；转移 25 条声明（wildcard 展开 47 条）；本 CR 不新增具名状态，新增声明转移数以 SDD/实现期测试固化 | AGENTS.md 纪律 #2 |

#### 1.4 决策点（本 PRD 拍板）

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 评审节点数量 | **一个** `review-dev-plan` 合并评审 | 避免两个节点重复读取同一上下文；方案 §2.2 原则 1 |
| D-2 | 回修入口 | **普通产物 blocker 统一回 `write-dev-plan`**，随后依序重跑 TASK 和评审 | 首版不做动态 repair target 选择，换简单确定的闭环；方案 §2.2 原则 2 |
| D-3 | 状态变更 | **不新增具名状态**；评审在 `task-breakdown` 执行，普通 blocker 回 `tech-design-reviewed`，上游设计疑点回 `tech-design-review-pending` | 最小改造；复用现有技术设计待评审态承接上游疑点 |
| D-4 | 账本模型 | **不新增账本类型**；只新增 `dev-plan.yml` 阶段证据，轮次写既有 `review-loop.yml`，追溯投影到既有 `traceability.yml` | 方案 §2.2 原则 4 |
| D-5 | 人工节点 | **不新增**；沿用现有「确认进入代码开发」人工审批 | 方案 §2.2 原则 5 |
| D-6 | 评审范围 | **以 SDD 为准**，不重新逐条评审 PRD | 方案 §2.2 原则 6 |
| D-7 | 回修粒度 | **TASK-only blocker 也重跑 plan→TASK** | 牺牲少量生成时间换简单确定闭环；方案 §2.2 原则 7 |
| D-8 | 评审循环上限 | **最多 3 轮**，与 requirement/tech-design/code 一致 | 方案 §3.1 |
| D-9 | TASK glob freshness | **首版不做**；不为 TASK 文件新造通用摘要协议 | 完整 subject freshness 是通用问题，应统一覆盖所有 stage；方案 §6.2 |
| D-10 | suggestion 策略 | **strict**：只按当前 CR 已批准范围判断 pass/block，范围外改进进 suggestions | 方案 §4.3 |
| D-11 | 上游设计疑点 | **停止自动回修**；经专用转换回 `tech-design-review-pending`，由人工走现有技术设计修订、重新评审与审批流程 | 不对未变 SDD 重跑 plan/TASK，避免三轮空转；不在本节点擅自修改 SDD |
| D-12 | TASK 正文 freshness | **首版不做**；dev-start evidence digest 覆盖 annotation、plan、task index，不覆盖 `TASK-*.md` 正文 | 遵循 D-9，不为本节点特化通用摘要协议 |
| D-13 | blocker 分流表达 | **复用 `repair-target`**；`write-dev-plan` 表示普通产物 blocker，`write-tech-design` 表示上游设计疑点 | 不新增 blocker-type 字段或新账本模型 |
| D-14 | 上游疑点优先级 | **上游设计疑点优先**；同轮同时出现两类 blocker 时先回技术设计流程 | 上游设计不稳定时修 plan/TASK 会产生无效回修 |
| D-15 | PRD 抽查边界 | **只按 SDD 引用定位抽查**，不得全量复审 PRD | 保持本节点以已审批 SDD 为准，不重开需求评审 |

### 2. 用户故事

- **US-1** 作为开发启动审批人，当 plan/TASK 存在遗漏或矛盾时，`review-dev-plan` 在我审批前就阻断进入编码，而不是等代码写完在 review-code 才发现。
- **US-2** 作为 `dev-agent`（实现者），当我拿到 TASK 集合时，每个 TASK 的目标、输入输出、涉及文件、验收条件都足够明确，可以直接驱动编码，不需要自己重新设计核心方案。
- **US-3** 作为 tools 包维护者，`review-dev-plan` 复用既有 `review-record` 通用路径落盘，不引入新的写账本脚本或模型直写旁路。
- **US-4** 作为 pipeline runtime，`review-dev-plan` 普通 BLOCK 时状态回到 `tech-design-reviewed` 并自动按 plan→TASK→评审顺序重放；上游设计疑点回到 `tech-design-review-pending`，复用既有技术设计修订链路。
- **US-5** 作为评审者，当评审发现 SDD 自相矛盾或无法实施时，问题被报告为「上游设计疑点」并停止开发启动，而不是在本节点擅自改写 SDD。
- **US-6** 作为开发启动审批人，审批后修改 dev-plan annotation、plan 或 TASK index 会触发 `EVIDENCE_DRIFT`，防止已纳入证据摘要的产物被偷改。

### 3. 功能需求

#### 评审节点与 pipeline 集成

- **FR-1（节点位置）**：`code-implementation.pipeline.json` 在 `write-dev-tasks` 后、`push-progress` 前插入 `review-dev-plan` reviewLoop 节点。后续节点顺序后移。
- **FR-2（强制输入）**：`review-dev-plan` 必须读取：`sdd.md`（已审批技术设计）、`plan.md`（交付里程碑）、`tasks/_index.yml`（TASK 集合与拓扑）、全部 `TASK-*.md`（目标/接口/验收）、`review-annotations/sdd.yml`（技术评审已知风险）。默认以 SDD 为准；仅当 SDD 引用 PRD FR/AC 或追溯疑点需要解释时，才可定位抽查对应 `prd.md` 小节，不得全量复审 PRD。
- **FR-3（评审维度）**：评审必须覆盖八类维度：SDD→plan 覆盖、plan→TASK 覆盖、TASK 可执行性、依赖拓扑、接口契约一致性、验收可验证性、范围与极简性、风险与回滚。另含估算一致性检查；估算仅在揭示任务拆分、依赖或验收结构性问题时作为 blocker，普通工时口径差异进入 suggestions。
- **FR-4（评审判定落盘）**：评审判断经 `.crctl/tmp/review-dev-plan.yml` 输入 `crctl review-record --stage dev-plan --bump-attempt`，生成 `review-annotations/dev-plan.yml`，同步更新 `review-loop.yml` 与 `traceability.yml#reviews.dev-plan`；该投影复用 CR-2026-025 的通用 review-record → traceability 能力，不在本 CR 重新实现账本模型。
- **FR-5（PASS 条件与行为）**：PASS 条件为 `verdict=pass && blockers=[]`；通过时保持 `task-breakdown`，允许进入现有开发启动人工审批。
- **FR-6（普通产物 blocker 的回修路由）**：plan/TASK 的 BLOCK 经新状态转换 `task-breakdown → tech-design-reviewed`（trigger: `review-dev-plan:block`），pipeline 按 `write-dev-plan → write-dev-tasks → review-dev-plan` 顺序重放。`review-annotations/dev-plan.yml#repair-target` 记录为 `write-dev-plan`。
- **FR-6a（上游设计疑点）**：发现 SDD 自相矛盾、不可实施或需要改变已审批设计时，评审记录 `upstream-design blocker`，`repair-target: write-tech-design`，并经专用转换 `task-breakdown → tech-design-review-pending`（trigger: `review-dev-plan:upstream-design-blocker`）停止 plan/TASK 自动重放；不得在本节点修改或覆盖 `review-annotations/sdd.yml`。由人工通过既有技术设计修订、重新评审与审批流程处理后，才可重新进入 plan → TASK → review。
- **FR-6b（分流优先级）**：同一轮同时存在 `repair-target: write-tech-design` 与普通 plan/TASK blocker 时，以上游设计疑点优先，进入 FR-6a 路由，不消耗后续普通 dev-plan 自动回修轮次。
- **FR-7（循环上限）**：普通 plan/TASK blocker 的自动评审循环最多 3 轮（`maxAttempts: 3`）；轮次耗尽仍未通过时返回 `LOOP_EXHAUSTED` 并停止，不得进入 human approval。`upstream-design blocker` 只记录本轮审计，不继续消耗普通 dev-plan 自动回修轮次。

#### 回修能力

- **FR-8（回修 prompt 支持）**：`write-dev-plan` 与 `write-dev-tasks` 的 prompt 须接受 `review_feedback`、`self_repair_attempt` 输入，并输出 `fixed-blockers`。回修时只处理评审指出的问题，不扩散 SDD 范围。
- **FR-9（回修禁止空转）**：普通产物 blocker 回修后的 write-dev-plan/write-dev-tasks 必须逐条输出 fixed-blockers；禁止只刷新评审证据而不修改被指出的产物。首版不新增 blocker-to-file diff 对账器，空转由下一轮 review-dev-plan 重新读取实际产物并继续 BLOCK。`upstream-design blocker` 适用 FR-6a，不得进入此自动回修循环。

#### 门禁升级

- **FR-10（dev-start 审批门禁）**：`gates.json#approvalStages.dev-start` 升级为校验：① `review-annotations/dev-plan.yml` 存在；② passCondition（`verdict=pass && blockers=[]`）通过；③ `plan.md`、`tasks/_index.yml` 与至少一个 `TASK-*.md` 仍存在。自动评审不通过时返回 `GATE_BLOCKED`。
- **FR-11（evidence digest）**：人工 dev-start 审批的 evidence digest 覆盖 `dev-plan.yml` annotation、`plan.md` 和 `tasks/_index.yml`。审批后修改这些文件触发既有 `EVIDENCE_DRIFT`；首版不承诺检测 `TASK-*.md` 正文漂移。
- **FR-12（developing 目标态门禁）**：`developing` 目标态门禁同时保留：`plan.md` 存在、`tasks/_index.yml` 存在、`tasks/TASK-*.md` 非空、dev-start passCondition 通过、`approval.yml#development-start` 为合法人工审批记录。全部使用现有 `fileExists`、`globNonEmpty`、`passCondition`、`approval` 门禁类型。

#### 状态机与映射

- **FR-13（状态转换）**：`dir-graph.yaml`（tools 包）新增两条自动评审失败转换：`task-breakdown --review-dev-plan:block--> tech-design-reviewed`、`task-breakdown --review-dev-plan:upstream-design-blocker--> tech-design-review-pending`。不新增具名状态；声明转移数增加 2，wildcard 展开后的精确数量由实现期测试固化。
- **FR-14（crctl 映射扩展）**：`crctl.mjs` 的四个 REVIEW_STAGE_* 映射中加入 `dev-plan`：`REVIEW_STAGE_FILES.dev-plan = dev-plan.yml`、`REVIEW_STAGE_LOOPS.dev-plan = review-dev-plan`、`REVIEW_STAGE_EXPECT.dev-plan = [task-breakdown]`、`REVIEW_REPAIR_TARGETS.dev-plan = write-dev-plan`。同时允许 dev-plan annotation 通过 `repair-target: write-tech-design` 触发上游设计疑点路由；保持通用实现，不新增子命令。

#### Skill 与文档

- **FR-15（新 Skill）**：新建 `skills/develop/review-dev-plan/SKILL.md`，定义输入、八类维度、payload 格式、回修和落盘规则。
- **FR-16（Skill 登记与矩阵）**：`skills/_index.yml` 登记新 Skill；`agent-skill-matrix.yml` 为既有 `dev-agent` 登记 `review-dev-plan` owns，为 `quality-reviewer-agent` 登记 can-call（不新增 actor）。
- **FR-17（文档同步）**：`README.md` / `ARCHITECTURE.md` 更新节点流程、受控评审 stage、状态转换说明与 CR-2026-025 traceability 投影依赖。

#### 收尾

- **FR-18（既有行为不回归）**：requirement、tech-design、write-test-report、code 的既有 reviewLoop 行为不得回归。
- **FR-19（验证关卡）**：`check-skill-matrix.mjs`、`check-agents-contract.mjs`、`lint-prompts.mjs --mode enforce` 全绿；`node --test` 跑通 `crctl.test.mjs` 与 prompt lint tests 全部用例。
- **FR-20（溯源标注）**：commit message 注明来源为 `docs/analysis/开发计划与TASK合并评审门禁方案.md`，含 CR-2026-026 编号。

### 4. 非功能需求

- **NFR-1（最小改造）**：不新增 CR 具名状态，不新增审批 stage，不新增独立账本类型。
- **NFR-2（确定性写入）**：annotation、review-loop 和 traceability 的同轮数据必须共享同一 reviewer、时间、attempt、verdict 与 blocker-count；任一前置校验/CAS 失败不得产生部分写入。
- **NFR-3（行尾纪律）**：所有哈希、逐行解析和定点编辑先规范化 CRLF；结构无法唯一定位时硬失败，不静默降级。
- **NFR-4（兼容性）**：历史 CR 没有 `dev-plan.yml` 时不做批量迁移；只有新流程进入 dev-start approval 时要求新证据。
- **NFR-5（不过度设计）**：首版普通产物 blocker 统一回修 plan→TASK，不实现按 blocker 动态选择 write-dev-plan/write-dev-tasks，不新增专用 LLM 选择暂停节点；上游设计疑点仅复用 `repair-target: write-tech-design` 与现有技术设计流程分流。
- **NFR-6（可审计）**：评审证据记录 reviewer-model 与 suggestion-policy；pipeline 输出 current-attempt、repair-target、repair-instructions 和摘要。
- **NFR-7（零新增第三方依赖）**：全部使用 `node:` 内置模块，测试仅用 `node:test`/`node:assert`。

### 5. 验收标准

- **AC-1**（FR-2/FR-3）：SDD 中存在一个关键模块但 plan 完全未覆盖时，评审 BLOCK，blocker 指明 SDD 章节与缺失计划面。
- **AC-2**（FR-3）：plan 中存在交付项但没有任何 TASK 承接时，评审 BLOCK。
- **AC-3**（FR-3）：TASK 的 `depends-on` 指向不存在任务、形成互锁环或顺序与接口产出相反时，评审 BLOCK。
- **AC-4**（FR-3）：上游 TASK 产出与下游 TASK 消费的函数名、参数或返回类型不一致时，评审 BLOCK。
- **AC-5**（FR-3）：关键 TASK 没有至少两条可执行验收步骤或仍含 TBD/空泛实现说明时，评审 BLOCK；关键 TASK 指 `tasks/_index.yml` 中无下游替代、被其他 TASK 依赖、承接 SDD 核心接口/数据迁移/门禁变更，或失败会阻断本 CR 交付闭环的 TASK。
- **AC-6**（FR-3/D-10）：plan/TASK 擅自加入 SDD 未批准能力时，评审 BLOCK；纯命名和非本 CR 优化进入 suggestions。
- **AC-7**（FR-4/FR-5）：全部维度通过时生成 `dev-plan.yml`，`review-loop.yml#loops.review-dev-plan.current-attempt=1`，`traceability.yml#reviews.dev-plan` 与 annotation 一致。
- **AC-8**（FR-6）：普通 plan/TASK BLOCK 后 status 从 `task-breakdown` 回到 `tech-design-reviewed`，pipeline 依次重跑 plan、TASK、评审；不得直接进入 implement-code。
- **AC-8a**（FR-6a）：SDD 自相矛盾或不可实施时，记录 `upstream-design blocker` 与 `repair-target: write-tech-design`，status 从 `task-breakdown` 回到 `tech-design-review-pending`；未经过人工技术设计修订、重新评审和审批，不得再次进入 plan → TASK → review。
- **AC-8b**（FR-6b/FR-7）：构造同轮同时包含普通 plan/TASK blocker 与 `repair-target: write-tech-design` 的 dev-plan payload 时，路由必须选择 `review-dev-plan:upstream-design-blocker`，status 回 `tech-design-review-pending`，不得触发普通 plan/TASK 自动回修，也不得递增后续普通 dev-plan 回修 attempt。
- **AC-9**（FR-4/NFR-2）：第 2 轮通过时 traceability attempts 同时保留第 1 轮 block 与第 2 轮 pass；三账本时间、轮次、结论一致。
- **AC-10**（FR-10）：评审未通过、证据缺失或 blockers 非空时执行 `crctl approve --stage dev-start`，必须返回 GATE_BLOCKED，且不写合法审批段、不推进 developing。
- **AC-11**（FR-10）：评审通过且 plan/index/TASK 存在时，人工审批行为与现状一致，仍只能由 TTY 或合法签名 grant 完成。
- **AC-11a**（FR-12）：评审通过并存在合法 dev-start 审批后，删除全部 `TASK-*.md` 或篡改 `approval.yml#development-start` 再执行 `advance --to developing`，必须被 developing 目标态门禁拦截，不得推进到 `developing`。
- **AC-12**（FR-11）：审批后修改 dev-plan annotation、plan 或 task index，后续门禁识别 EVIDENCE_DRIFT。
- **AC-12a**（FR-11/D-9）：审批后仅修改 `TASK-*.md` 正文而不修改 annotation、plan 或 task index 时，首版不要求由 dev-start evidence digest 识别漂移。
- **AC-13**（FR-7）：三轮均 BLOCK 时返回 LOOP_EXHAUSTED 并停止，不进入 human approval。
- **AC-14**（FR-18）：requirement、tech-design、write-test-report、code 的既有 review-record、attempt、gate、approve 与 traceability 投影测试全部通过。
- **AC-15**（FR-19）：`check-skill-matrix.mjs`、`check-agents-contract.mjs`、`lint-prompts.mjs --mode enforce` 和相关 Node 测试全绿。
- **AC-15a**（FR-1/FR-13/FR-14/FR-15/FR-16/FR-17/FR-20）：pipeline 模板、状态机转换、crctl stage 映射、Skill 登记、agent-skill-matrix、README/ARCHITECTURE 文档与提交溯源标注全部落地；任一登记缺失或文档引用旧单轨路由时，验收失败。

### 6. 成功指标

- 编码前质量空档被机械阻断：plan/TASK 的遗漏、矛盾或不可执行问题在开发启动审批前即被拦截，不再等到 review-code 阶段才发现。
- 回修路由准确：普通 plan/TASK BLOCK 后回到 `write-dev-plan` 重跑完整链条，上游设计疑点回到既有技术设计修订链条，而不是错误地回到 `implement-code`。
- 复用既有基础设施：不引入新的账本类型、状态或人工节点；`review-record` 通用路径覆盖新 stage。
- 人类保留最终决定权：评审通过后仍需人工确认进入编码；评审只阻断不代行审批。
- 可审计：每轮评审留下 reviewer-model、verdict、blocker-count、时间戳与轮次记录。

### 7. 范围排除

**本 CR 包含**：`review-dev-plan` Skill 新建、pipeline 模板修改、crctl 映射扩展、gates.json 门禁升级、dir-graph.yaml 状态转换、write-dev-plan/write-dev-tasks prompt 回修支持、文档同步、测试向量。

**本 CR 不包含**：
- 不拆成 plan review 与 TASK review 两个节点（D-1）。
- 不新增 `plan-reviewing`、`task-reviewing` 等状态（D-3）。
- 不修改 PRD/SDD 的既有评审与审批责任边界。
- 不在本节点执行代码 diff、lint、test、build（仍属 write-test-report/review-code）。
- 不新增 `review-dev-plan-loop.yml`、`task-review.yml` 等账本（D-4）。
- 不把所有 TASK 内容复制到 annotation 或 traceability。
- 不在本方案中解决所有阶段的被评审对象 freshness；如需解决，应统一覆盖 requirement/tech-design/dev-plan/code（D-9）。
- 不实现普通 plan/TASK blocker 按类型动态选择回修目标（D-7/NFR-5）；仅保留上游设计疑点到 `write-tech-design` 的二分路由。
- 不新增模型选择暂停节点（评审可由生成 plan/TASK 的同一模型执行，首版只要求 reviewer-model 留痕）。

### 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿（基于方案文档 §1-§11 转写；20 条 FR、7 条 NFR、15 条 AC） |
| 2026-08-09 | v0.2.0 | Ray | 修订（grill 拷问硬化）：BLOCK 改双轨路由——普通 plan/TASK blocker 回 `tech-design-reviewed` 自动重放，上游设计疑点回 `tech-design-review-pending` 复用既有技术设计流程（新增 D-11~D-15、FR-6a/6b、FR-13 两条转换、AC-8a，修订 D-2/D-3、§1.2 摘要、US-4、NFR-5，FR-16 明确 dev-agent owns + quality-reviewer-agent can-call）；修复 FR-19/NFR-7 断行 |

## tools 流程优化 Phase 0+1 — 基线事实统一与正确性修复（状态机口径 27/49、approve 原子提交、TASK 归档门禁、archive 原子化、终态查询、review-record 深化）（v0.28 · CR-2026-027）

## PRD — tools 流程优化 Phase 0+1：基线事实统一与正确性修复

### 1. 概述

#### 1.1 问题陈述

CR-2026-026 对 tools 全生命周期实际演练后，操作记录暴露的共性问题不是 LLM 语义能力不足，而是 LLM 同时承担了过多确定性职责（搜索 Skill/仓库路径、解析 worktree/trunk/Git 历史、拼接 Shell 命令、手工生成 frontmatter/索引/账本投影、推进状态、重复核对 crctl 刚写入的证据、根据历史 CR 猜测 schema、临时编写补丁脚本）。`docs/analysis/tools流程步骤优化v2.md`（下称 v2 方案）据此定义了从基线统一到 Merge/Writeback/Archive 的候选演进路线。

**当前必须先解决的基线冲突与真实故障**：

1. 状态机口径冲突：`../tools/dir-graph.yaml` 实测 27 条声明转换（wildcard 展开 49 条），但 workspace `AGENTS.md`、`../tools/ARCHITECTURE.md` 前文仍写 25/47 旧口径；`ARCHITECTURE.md` 内部前后矛盾（§8 维护记录已写 27/49）。
2. `crctl approve` 的 approval 与 status 被拆成不同 Git 提交，可能留下单文件半状态（CR-2026-026 实测）。
3. 归档无 TASK 的 CR 会被 `deliveryIndexComplete` 误判为「无任务」放行归档。
4. CR-2026-026 实测：`inbox-emit` 因中文 JSON Shell 转义失败后，后续归档继续执行，事件永久丢失。
5. `archive-move` 已承诺但遗漏 `_index.yml` 更新（CR-2026-024~026 归档后 `_index.yml` 仍显示 `drafting`）；且 `_backlog.yml` 遗留 CR-2026-024 缺 `- id:` 行的幽灵条目（静默污染 CR-2026-017 条目字段，本 CR 注册期实测确认）。
6. 归档后 `resolveCrState` 强制从 backlog 找 CR，`status/next` 返回 `CR_STATUS_NOT_FOUND`。
7. review Skill 在 `review-record` 成功后重新读取 traceability 核对刚写入的投影；dev-plan 需要 route/repair-target 但命令未返回。
8. `merge-feature-branch` 通过 prose 硬编码 tools 仓特例，违反「所有参与仓来自机器可读声明」（tools 已参与 10 个历史归档 CR，但 workspace `repositories` 只声明 docs 与 multica）。

**问题边界**：本 CR 只做基线统一与正确性修复，不引入 Runner 框架，不实施 Phase 2+ 任何候选路线。

#### 1.2 解决方案摘要

按 v2 方案分两阶段实施：

- **Phase 0 基线统一**：状态机口径全量统一为 27 声明/49 wildcard 展开；确认 crctl 保持单文件；修订 crctl 与 Pipeline 依赖描述；拍板并落地 archive `_index.yml` 全生命周期轻量目录语义；将 tools 声明为 workspace active repository 并删除 merge Skill 隐藏特例；删除旧方案中的 command module 与通用上下文命令描述；建立优化指标基线。**实施首步为 tools 仓一次性 bootstrap（D-12/FR-15）**：tools 声明入 repositories 后从 custom/main 补建 `requirement/CR-2026-027` worktree，全部 `../tools` 改动落在该分支，禁止直写 custom/main。
- **Phase 1 正确性修复**：`crctl approve` 两文件 CAS + 单次提交原子化；archived TASK 完成门禁（禁止隐式 no-task）；archive 事件与 backlog/history/index 同一 CAS 原子移动（收件人复用 owners，普通 `inbox-emit` 空 `--to` 硬失败）；归档残留幽灵条目的版本化迁移清理；终态只读 status/next 查询；review-record 输出 files/attempt/route/repairTarget 并删除 review Skill 的 traceability 二次读取。
- **验证**：按 v2 方案 §6.6 五项最小清单执行，不预跑无关测试族。

#### 1.3 事实基线（来源：v2 方案与质询记录，均已核实）

| # | 事实 | 依据 |
|---|---|---|
| B-1 | `../tools/dir-graph.yaml` 当前 15 个具名状态 + 注册前 `(new)`；27 条声明转换；wildcard 展开后 49 条 | v2 §2.1；本 CR 注册期 grep 复核 |
| B-2 | workspace `AGENTS.md`、`../tools/ARCHITECTURE.md` §3/§5 仍为 25/47 旧口径；ARCHITECTURE §8 已写 27/49（前后矛盾） | v2 §2.1；质询记录 §1.1 |
| B-3 | workspace `CONTEXT.md` 状态机口径已修正为 27/49 并新增 7 个相关术语（CR 阶段文档、specs 基线、CR 目录索引、CR 参与仓、归档事件、CR 终态查询、正常归档与提前终止） | 质询记录 §1.1（已随 CR-2026-027 注册前置提交入库） |
| B-4 | `ARCHITECTURE.md` 规定 crctl.mjs 刻意保持单文件；旧版优化方案提出 `crctl/scripts/commands/*.mjs` | v2 §2.2 |
| B-5 | `ARCHITECTURE.md` 声称 crctl 不依赖 Pipeline，但实现已通过 Pipeline 的 reviewLoop/passCondition 执行 gate | v2 §2.3 |
| B-6 | `cmdArchiveMove` 只原子写 `_backlog.yml` 与 `_history.yml`，未同步 `_index.yml`；cr-archive Skill 声称会同步（承诺未兑现） | 质询记录 §1.6 |
| B-7 | `_index.yml` 保留全部历史 CR 条目，早期归档条目标记 `status: archived`、`archived-at`、`writeback-spec-id`；`cr-query`/`cr-show`/`cr-dashboard` 均以 `_backlog.yml + _history.yml` 为查询事实源，不从 `_index.yml` 读状态；Multica 无读取 `_index.yml` 的运行时代码 | 质询记录 §1.6 |
| B-8 | `resolveCrState` 强制先从 backlog 加载条目，归档后 status/next 均返回 `CR_STATUS_NOT_FOUND` | 质询记录 Q6 |
| B-9 | `cmdApprove` 先写 approval 再调用 `cmdAdvance`；`cmdAdvance` 普通提交只 stage `cr.md`，approval/status 分提交 | 质询记录 Q4 |
| B-10 | `deliveryIndexComplete` 在 task index 缺失或所有 TASK pending 时得到空 doneIds 并放行；状态机证明正常 archived 必经 task-breakdown/developing，developing 已要求 task index + 非空 TASK；20 个现有归档 CR 全部有任务 | 质询记录 Q8 |
| B-11 | `merge-feature-branch` 明文承认 tools 不在 workspace repositories 声明范围，却以 `custom/main` 特例参与；tools 已参与 10 个历史归档 CR | 质询记录 Q3；workspace `dir-graph.yaml` 实测 |
| B-12 | `_backlog.yml` 尾部存在 CR-2026-024 幽灵条目（缺 `- id:` 行，HEAD 即存在）；crctl 自研 YAML 解析器对重复 key 静默覆盖，该条目被解析为 CR-2026-017 的续行字段，覆盖其 title/summary/owners/created/updated；`_history.yml` 中 CR-2026-024 有完整归档条目 | 本 CR 注册期实测 |
| B-13 | `inbox-emit` 当前允许缺失或空 `--to` 写入 notify-log，与 Skill 契约（`to` 必填）不一致；历史 21 条归档记录均有三角色 owners | 质询记录 Q10 |
| B-14 | 四个 review Skill 在 review-record 成功后重新读取 traceability 核对刚写入投影；dev-plan 需要 route/repair-target 但当前命令未返回 | v2 §6.5 |
| B-15 | `../tools/skills/writeback/scripts/lib.mjs` 已提供 LF 规范化、结构化输出、hash/diff、frontmatter 定点处理、参数解析和账本路径保护，有回归测试；engineering-docs 历史 validator 依赖 Ajv/gray-matter/yaml 且 schema 与 CR 阶段 PRD 不兼容 | 质询记录 §1.3/§1.4 |
| B-16 | Multica 尚无真正 Pipeline Runner；`pipeline_node_run` 只是 crctl 事件流投影；typed outputs 与 `.crctl/runs` 协议本轮不定义 | 质询记录 §1.5 |

#### 1.4 决策点（质询记录 Q1~Q10 已拍板，本 PRD 承接为实施约束）

| # | 决策点 | 拍板结果 | 理由 |
|---|---|---|---|
| D-1 | Phase 2~6 承诺强度 | 全部为**候选路线**；本 CR 只承诺 Phase 0/1；PRD Runner 试点需 Phase 0/1 完成后重新确认并另写 Spec | Q1：按证据逐项晋升，不预先批准文件布局/JSON schema/公共 API/retry mode |
| D-2 | archive `_index.yml` 语义 | **全生命周期轻量目录**；归档时由 `archive-move` 与 backlog/history 同一 `casWriteMulti` 更新条目（只写 `status`/`archived-at`/可选 `writeback-spec-id`）；不复制 history 详情、不新增 `history-ref`、不删除条目、不升级为查询事实源 | Q2：现有证据（历史条目保留+已标终态、消费者不读 index）最支持 |
| D-3 | 可写仓来源 | **所有 active repo 参与每个 CR，全部来自 repositories 声明**；tools 加入 workspace repositories（`path: "../tools"`、`trunk: custom/main`、`role: code`）；删除 merge Skill tools 特例；本轮不新增每 CR 仓库选择字段 | Q3：先消除隐藏特例，不建第二套参与模型 |
| D-4 | approve 原子性边界 | **两文件 CAS + 单次 commit**：预检后在内存生成 approval.yml 与目标 status cr.md → casWriteMulti → crctl git add 两文件 → 单次 commit → 成功后发 status outbox；TTY/grant 共用内部 approve-and-advance helper；gate/CAS 失败零写入；commit 失败两文件共同留存不发 outbox；拒绝路径复用现有合法 reject 转换 | Q4：复用现有 CAS，不新增事务框架/WAL |
| D-5 | 归档事件原子性边界 | **archive event 进入 archive-move CAS**：embedded advance 到终态后，archive-move 在内存构造事件（复用 editInboxEmit），与 backlog/history/index 同一 `casWriteMulti`；CAS 成功后发 archive outbox；不新增 `--payload-file`、幂等键或新命令 | Q5：事件与归档要么同生要么同灭 |
| D-6 | 归档 CR 只读查询 | **新增仅供 status/next 的终态只读 resolver**：history `final-status` 为权威；输出 `terminal:true`、`legalNext:[]`、`next:null`；写命令继续用 active resolver；backlog/history 同存同 CR 报 `CR_LOCATION_CONFLICT`；history 重复或缺 final-status 硬失败；cr.md 漂移仅告警；不新增命令与归档字段 | Q6：最小只读契约 |
| D-7 | review-record 返回契约 | 新增 `files[]`、`attempt.{current,max,bumped}`、`route`、`repairTarget`；保留 `file`/`trace` 兼容；files 只列实际写入；删除 review Skill traceability 二次读取；不返回 verified/subject digest/next | Q7：只补真实消费者字段 |
| D-8 | TASK 归档门禁 | **正常归档不允许隐式 no-task**：index 必须存在、tasks 非空、任一非 done → `TASK_STATUS_INCOMPLETE`、全 done 后校验 delivery index；rejected/withdrawn 不走 archived 门禁；archive-move `--final-status` 必须与 cr.md 当前 status 完全一致；不新增 no-task 标志与 task reconcile；历史数据修复用一次性版本化迁移脚本 | Q8：缺文件/空数组不得解释为 no-task |
| D-9 | Phase 0/1 最小修改与验证集合 | 修改核心 = workspace dir-graph/AGENTS、tools ARCHITECTURE、crctl.mjs 与 crctl.test.mjs；只修改确有过时指令的 merge/archive/review Skill 与 feature-writeback pipeline；不改 gates、matrix/index、approve Skill、engineering-docs、writeback scripts 或检查器本身；只运行 diff-check、pipeline JSON parse、crctl tests、lint-prompts enforce 与两项 grep | Q9：改什么测什么，不预跑无关测试族 |
| D-10 | 归档事件收件人 | 取 requirement/development/test owner ID 去重；legacy 缺 owners 回退顶层 owner；最终为空 → CAS 前 `ARCHIVE_RECIPIENTS_MISSING`；普通 `inbox-emit` 缺失/非列表/空 `--to` 一律 `BAD_ARGS`；不新增身份字段 | Q10：复用 owners 模型 |
| D-11 | 幽灵条目清理 | 本 CR 内以**一次性版本化迁移命令**清理 `_backlog.yml` 尾部缺 `- id:` 条目（CR-2026-024 已归档于 `_history.yml`）：扩展既有 `crctl migrate-backlog` 增加幽灵块检测/删除（幂等，`already-clean`），不新增独立脚本目录（ARCHITECTURE §6 否决账本操作脚本库）；修复未来归档行为仍由 D-5 的 archive-move CAS 保证 | B-12 实测 + v2 §6.2 历史数据修复口径；落点拍板 2026-08-09（SDD v0.2.0 方案） |
| D-12 | tools 仓 bootstrap | **注册后一次性补偿**：tools 加入 repositories 声明后，从 custom/main 为本 CR 创建 `requirement/CR-2026-027` worktree，此后全部 `../tools` 改动落在该分支，禁止直写 custom/main；该补偿不等同于每 CR 仓库选择模型，不新增注册字段 | 需求评审 Blocker：本 CR 注册时 tools 未声明，但必须修改 `../tools` 文件（ARCHITECTURE、crctl、merge/archive/review Skill、迁移脚本与测试） |
| D-13 | target-version 口径 | **维持 `tbd` 并声明批准口径**：本 CR 属 tools 正确性修复，不绑定产品发布版本号序列；target-version 在需求审批时确认，不进入产品版本号递增链路 | 需求评审 Suggestion：避免 tbd 无解释 |
| D-14 | post-PASS 设计修订与 next freshness | reviewLoop 的 `maxAttempts=3` 约束单个审查周期内的 block→repair；已 PASS 后因 dev-plan upstream blocker 修订 SDD 时自动开启新 cycle（不新增命令）：保留旧 attempts 审计、`current-cycle+1`、新 cycle 从 attempt=1 开始。`crctl next` 必须检查 SDD subject digest 与较新的 upstream blocker，旧 PASS 不得直接建议审批 | review-dev-plan 上游回退实测：SDD v0.5.0 晚于旧 PASS/审批，next 仍误报 approve-tech-design，且旧 cycle 已 3/3 |

### 2. 用户故事

- **US-1** 作为 tools 包维护者，当我读任何权威文档时，状态机口径（27 声明/49 展开）全库一致，不再需要自己辨别哪个是现状。
- **US-2** 作为 CR 流程执行者，当我在 TTY 或经 `--grant` 审批时，approval 与状态推进落在同一个提交里，任何失败都不会留下「审批已写但状态未动」的半状态。
- **US-3** 作为归档执行者，归档时事件、backlog/history/index 三账本同批原子写入，不会出现「事件已发但未归档」或「已归档但事件丢失」；`_index.yml` 不再停在 `drafting`。
- **US-4** 作为归档执行者，归档已结束的 CR 后仍能查询其 status/next（终态只读），不会得到 `CR_STATUS_NOT_FOUND`。
- **US-5** 作为归档审批方，任何 TASK 未完成的 CR 都无法以 `archived` 结束；「没有 TASK」不再被误读为「无任务可查」。
- **US-6** 作为 review Skill 调用方，`review-record` 一次返回实际写入文件、attempt 与 route/repairTarget，我不再需要重新读取 traceability 核对刚写入的结果。
- **US-7** 作为参与仓消费者，所有可写仓（含 tools）都来自 `dir-graph.yaml#repositories` 机器可读声明，不存在只写在 prose 里的隐藏特例。

### 3. 功能需求

#### Phase 0 — 基线统一

- **FR-1（状态机口径统一）**：状态机事实以 `../tools/dir-graph.yaml` 为准；修正 workspace `AGENTS.md` 与 `../tools/ARCHITECTURE.md` 前文中的 25/47 旧表述为 27 条声明/49 条 wildcard 展开；统一后所有文档、断言、测试注释引用状态机数量时必须写明 declared 或 wildcard-expanded 口径；统一完成前新代码不得硬编码转换数量。
- **FR-2（crctl 单文件边界确认）**：`ARCHITECTURE.md` 明确本轮维持 crctl.mjs 单文件，不创建 `crctl/scripts/commands/` 模块目录；删除旧版优化方案中的 command module 描述；若未来需要模块化必须独立立项并先修改 ARCHITECTURE。
- **FR-3（crctl 与 Pipeline 依赖描述修订）**：`ARCHITECTURE.md` 按以下准确描述修订：crctl 不执行 Skill、不依赖 Skill 自然语言语义；crctl 可读取 dir-graph、gates 与 Pipeline 中的声明式 gate/reviewLoop 配置；Pipeline 不得调用 crctl 之外的账本写入口。
- **FR-4（archive `_index.yml` 生命周期语义落地）**：在 `ARCHITECTURE.md` 与相关文档固化 D-2 语义（全生命周期轻量目录：归档时同批 CAS 更新 `status`/`archived-at`/可选 `writeback-spec-id`；不复制 history 详情、不新增 `history-ref`、不删除条目、不成为查询或状态事实源）；该语义与 §6.3a 行为实现一致。
- **FR-5（tools 声明为参与仓）**：workspace `dir-graph.yaml#repositories` 新增 `{id: tools, path: "../tools", trunk: custom/main, role: code, active: true}`；删除 `merge-feature-branch` Skill 中「tools 不在声明但特殊参与」的 prose 与实现分支；注册、同步、合并、清理只遍历 repositories。
- **FR-6（删除旧方案遗留描述）**：`docs/analysis/tools流程步骤优化v2.md` 中删除旧方案的 command module 目录描述与通用上下文 crctl 命令（`patch`/`run-workflow`/`stage-context`/`registration-check`/`register-preflight`）的描述，确保方案文档与拍板边界一致。
- **FR-7（优化指标基线）**：将 v2 方案 §16.2 的外部调用量目标表（注册 24→8-12、PRD 编写 9→3、implement-code 63→25-35 等）与 §16.1 正确性指标固化为 `ARCHITECTURE.md` 或文档中的基线记录，供 Phase 2+ 候选路线实施前对照；指标是观测值，不得通过删除 gate、测试、补偿或人工审批达成。
- **FR-15（tools worktree bootstrap）**：本 CR 实施的第一项动作：将 tools 加入 workspace `dir-graph.yaml#repositories`（D-3/FR-5）后，从 `../tools` 仓 custom/main 为本 CR 创建同名分支 worktree `requirement/CR-2026-027`（复用 `crctl worktree-path` 路径规则，bucket = `tools`）；fetch 失败按注册期 `STALE_BASE` 降级规则处理并在实施记录标注基线滞后；此后本 CR 对 `../tools` 的全部改动（ARCHITECTURE.md、crctl.mjs、crctl.test.mjs、merge/archive/review Skill、迁移脚本）一律落在该 worktree 分支，禁止直接在 custom/main 提交实施改动；merge/cleanup 阶段 tools 作为 active repo 走正常 merge-feature-branch 与 cr-archive 流程（含 tools 的 merge-commits 记录与 worktree 清理）。该 bootstrap 是注册时序（tools 当时未声明）的一次性补偿，不等同于新增每 CR 仓库选择模型。

#### Phase 1 — 正确性修复

- **FR-8（approve 原子提交）**：`crctl approve` 改为预检（current state/transition/evidence/signature/passCondition/requireFiles）→ 内存生成 approval.yml 与目标 status 的 cr.md → 按候选 approval 复核目标 gate → `casWriteMulti(approval.yml, cr.md)` → `crctl git add` 两文件 → 单次 commit → commit 成功后发送 status outbox → audit 记录最终结果。TTY approve 与 `--grant` 共用内部 approve-and-advance helper；gate/签名/证据预检失败零文件写入；CAS 冲突两文件均不写；commit 失败两文件共同留在工作区并返回结构化恢复信息，不发 status outbox；拒绝路径不写批准段，继续复用现有合法 reject 转换；不新增 crctl 子命令、WAL 或通用事务框架。**受控历史审批迁移（代码评审二轮 b10、三轮回修）**：新增 `crctl approve --resign <reason>`（仅限交互式终端、人类在环无旁路）——gates.json evidence 定义变更（如 dev-start 剔除 task-index）导致既有 `via=crctl-approve` 审批段 digest 漂移报 EVIDENCE_DRIFT 时，按当前定义重算 digest 并只改写该段（保留 approver/approved-at/via/target-status），追加 resign 审计子块与 audit 事件，幂等（digest 已一致则 no-op）；`via=server-approve` 的签名绑定原 digest，本地 `--resign` 必须返回 `RESIGN_SERVER_APPROVAL_UNSUPPORTED`，由服务端按新 digest 重新签发 grant；不新增子命令，不改审批本体字段。
- **FR-9（archived TASK 完成门禁）**：`advance --to archived` 的任务门禁依次校验：① `tasks/_index.yml` 必须存在；② `tasks[]` 必须非空；③ 任一 TASK 非 done → `TASK_STATUS_INCOMPLETE`；④ 全部 done 后校验 `delivery/task/_index.yaml`；⑤ 缺文件、空数组不得被解释为 no-task。`rejected`/`withdrawn` 属提前终止，可在无 TASK/writeback 时进入 history，不走 archived 门禁；`archive-move` 接受当前状态 `archived|rejected|withdrawn`，且 `--final-status` 必须与当前 `cr.md` status 完全一致否则硬失败；不新增永久 `task reconcile` 命令与 no-task 标志。
- **FR-10（归档残留幽灵条目迁移清理）**：扩展既有 `crctl migrate-backlog` 子命令增加幽灵条目清理阶段（不新增独立脚本、不新增子命令）：删除 `_backlog.yml` 尾部缺 `- id:` 行的 CR-2026-024 幽灵条目块；删除依据为 `_history.yml` 中存在 CR-2026-024 完整归档条目（无对应归档时硬失败 `GHOST_ENTRY_ORPHANED`，不静默删除）；运行后 CR-2026-017 条目字段恢复完整；命令幂等（已清理时返回 `already-clean`），再次运行不得重复修改；行为纳入 crctl 测试覆盖（B-12 场景回归）。落点采用 SDD v0.2.0 方案（2026-08-09 拍板）：清理必须经 crctl（CAS + audit），因 ARCHITECTURE §6 否决 `skills/shared/scripts/` 账本操作脚本库。**审计时序（代码评审二轮 b10）**：幽灵清理的 `migrate-backlog-ghost removed:true` 审计事件必须在 casWrite 成功之后记录（先写盘、后审计），CAS_CONFLICT 时 `_backlog.yml` 保持不变且 audit.log 零成功记录。
- **FR-11（archive event 与账本移动原子化）**：`archive-move` 在内存构造 archive event（复用现有 editInboxEmit 逻辑写候选条目，富化 `final-status`/`archive-reason`/`writeback-spec-id`/`archived-at`），与 backlog→history 移动 + index 终态更新经同一 `casWriteMulti` 写入，CAS 成功后发送 archive outbox；任一 event/文件结构错误或 CAS 冲突时事件与三份账本均不写。收件人 `to = unique(owners.requirement.id, owners.development.id, owners.test.id)`；旧条目缺 owners 回退顶层 `owner`；最终为空则 CAS 前返回 `ARCHIVE_RECIPIENTS_MISSING`；不新增 submitter/reviewer 字段。普通 `inbox-emit` 同步修正：`--to` 缺失、解析后非列表或去重后为空均返回 `BAD_ARGS`，不得写入无收件人 notify-log。不新增 `inbox-emit --payload-file`、archive 专用幂等键或新命令。
- **FR-12（archived status 终态只读查询）**：新增仅供 `status`/`next` 使用的终态只读 resolver：active CR 继续从 cr.md/backlog 读取；archived/rejected/withdrawn 从 `_history.yml` 的 `final-status` 读取；输出最小契约含 `cr`/`status`/`terminal:true`/`source`/`legalNext:[]`/`reviewLoops:{}`/`gateBlockers:{}`/`next:null`；`crctl next` 对终态返回 `next:null` 不报错；写命令继续使用现有 active resolver，不允许终态写入；backlog/history 同时存在同一 CR 时 `CR_LOCATION_CONFLICT`；history 重复条目或缺 final-status 硬失败；cr.md 与 history 不一致时以 history 为准并输出 warning；不新增 archive reason/spec-id 等非必要返回字段，不新增 `archive-status` 命令。
- **FR-13（review-record 输出深化）**：`review-record` 保持现有 `file`、`trace` 字段兼容，并增加：`files[]`（只列本次实际写入文件，未 bump 时不得虚列 review-loop.yml）、`attempt.{current,max,bumped}`、`route`（`pass|repair|upstream`）、`repairTarget`（`write-requirement-prd|write-tech-design|write-dev-plan|implement-code|null`）；不返回 `verified`、subject digest、`next`（`next` 仍由 `crctl next` 唯一计算）。删除四个 review Skill 的「重新读取 traceability 核对刚写入结果」步骤，命令成功即表示三账本同批写入完成，调用方按 `files` 组织提交、按 `route` 分流、最后调用 `crctl next`。
- **FR-14（配置文件最小验证清单）**：Phase 0/1 实施完成的验证清单固定为五项：① `git diff --check`；② `JSON.parse(feature-writeback.pipeline.json)`；③ `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`；④ `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`；⑤ grep 核对 tools 隐藏特例与 25/47 旧表述已清零。不修改、不运行 agent-skill matrix 检查族、agents contract 检查族、writeback scripts 测试、engineering-docs 测试及新的 validate-config/schema/Runner；实施实际触及上述权威文件或代码时，按「改了什么测什么」追加对应检查。
- **FR-16（next 路由 freshness 与上游重入修复，CR-2026-026 遗留）**：
  1. `task-breakdown`：读取 canonical `review-annotations/dev-plan.yml`；缺失或 schema 不完整 → `next=review-dev-plan`；PASS（`verdict=pass && blockers=[]`）→ `next=crctl approve --stage dev-start`；BLOCK 时从 annotation 的 `verdict`/`blockers`/顶层 `repair-target` 调用共享 `resolveDevPlanRoute` 确定性重算，repair→`write-dev-plan`、upstream→`write-tech-design`，不得依赖上一条 `review-record` 命令的瞬时返回值；block 且本 cycle 已 `LOOP_EXHAUSTED` → `next=null`、`humanApproval=true` 并输出人工处理原因。
  2. `tech-design-review-pending`：`review-record --stage tech-design` 必须记录 `subject-file=sdd.md` 与 LF 规范化 `subject-sha256`；若当前 SDD digest 与 annotation 不一致，或存在 `reviewed-at` 晚于技术评审记录的 dev-plan upstream blocker，则 `next=review-tech-design`，不得按旧 PASS 建议 approve-tech-design。
  3. post-PASS 设计 revision：`review-record --stage tech-design --bump-attempt` 在“上一技术评审 PASS + 较新 dev-plan upstream blocker + SDD 已修订”时自动开启新 review cycle；`review-loop.yml`/traceability 在原 attempts 上增加 `cycle`，保留历史审计，新 cycle 从 attempt=1 计数。legacy attempt 无 `cycle` 视为 cycle=1；不新增子命令、不手改 review-loop。

### 4. 非功能需求

- **NFR-1（最小改造）**：不新增 CR 具名状态、审批 stage、独立账本类型、crctl 子命令、WAL 或通用事务框架；不创建 `commands/` 模块目录与 `skills/shared/runner/` 公共库。
- **NFR-2（确定性写入）**：approval/status、archive event/三账本的每次写入要么全部发生要么全部不发生；任一前置校验或 CAS 失败不得产生部分写入；commit 失败不得发送对应 outbox 事件。
- **NFR-3（行尾纪律）**：所有哈希、跨行正则、逐行解析与定点编辑先做 CRLF→LF 规范化；结构无法唯一定位时硬失败，禁止静默降级。
- **NFR-4（复用与不复制）**：不复制 `../tools/skills/writeback/scripts/lib.mjs` 已有能力（LF 规范化、结构化输出、hash/diff、frontmatter 定点处理、账本路径保护）；不恢复 engineering-docs MCP/CLI 与历史 Ajv/gray-matter/yaml validator；Phase 2+ 的共享 Runner 库晋升条件（两个真实 Runner + 语义相同重复 + 接口更少更稳 + 不复制 writeback 能力 + 调用方测试）不在本 CR 实施。
- **NFR-5（零新增第三方依赖）**：全部使用 `node:` 内置模块；测试仅用 `node:test`/`node:assert`。
- **NFR-6（兼容性）**：历史 CR 不要求新增证据文件（不批量迁移旧 approval/archive 形态）；rejected/withdrawn 的提前终止路径行为保持；`_index.yml` 不成为新查询事实源。
- **NFR-7（可审计）**：approve 原子路径与 archive-move 原子路径记录 audit 与 outbox 事件；失败路径输出结构化错误码（含恢复指引），不输出「请在终端运行」类手工指引。
- **NFR-8（不过度设计）**：不新增 typed outputs、`.crctl/runs` 协议、scope-change.yml、checkpoint kind 扩展、branch-base-set、register-preflight、registration-check、stage-context；所有 Phase 2+ 机制等待真实案例触发（v2 §12）。

### 5. 验收标准

#### Phase 0

- **AC-1**（FR-1）：按固定范围与判定执行 grep 清零核对：范围 = workspace 根（AGENTS.md、CONTEXT.md、dir-graph.yaml）+ `../tools` 包（ARCHITECTURE.md、AGENTS.md、README.md、skills/、pipeline-templates/），排除 `docs/analysis/` 下明确标注「历史口径/CR-2026-022 后、CR-2026-026 前」的复盘类文档引用；判定 = 模式 `25\s*条声明|25/47|47\s*条` 的命中若上下文为「当前/现状」表述则计未清零，仅作历史注脚的命中不违规；全部状态机数量断言注明 declared/wildcard 口径。
- **AC-2**（FR-2）：`ARCHITECTURE.md` 与 v2 方案文档中不存在 `crctl/scripts/commands/` 或等价模块目录描述；crctl.mjs 仍为单文件。
- **AC-3**（FR-3）：`ARCHITECTURE.md` 的 crctl-Pipeline 依赖描述与实现一致（三句准确描述到位，无「不依赖 Pipeline」旧表述残留）。
- **AC-4**（FR-4/FR-11）：`ARCHITECTURE.md` 与 cr-archive 相关文档的 `_index.yml` 语义描述与实现一致（全生命周期轻量目录、三字段更新、不复制 history、不删除条目）。
- **AC-5**（FR-5）：workspace `dir-graph.yaml#repositories` 含 tools（path/trunk/role/active 四字段齐全）；`merge-feature-branch` Skill 及其实现中不存在 tools 硬编码特例分支；合并/同步路径只遍历 repositories。
- **AC-6**（FR-6）：v2 方案文档中不存在 command module 目录与五条通用上下文命令（patch/run-workflow/stage-context/registration-check/register-preflight）的实现描述。
- **AC-7**（FR-7）：优化指标基线（§16.1/§16.2）以表格形式固化于文档，含「不得通过删除 gate/测试/补偿/人工审批达成」约束。

#### Phase 1

- **AC-8**（FR-8）：四个 stage 的 TTY approve 与 `--grant` 均一次提交（approval.yml 与 cr.md 同 commit），历史「下一阶段补提交 approval」行为消失。
- **AC-9**（FR-8）：gate/签名/证据预检失败时零文件写入；CAS 冲突时 approval.yml 与 cr.md 均不写；commit 失败时两文件共同保留在工作区且不发 status outbox。**AC-9b（代码评审二轮 b10）**：幽灵清理 CAS 冲突时零成功 `migrate-backlog-ghost` 审计记录（审计时序：先 casWrite 成功、后 auditLog）。
- **AC-10**（FR-8）：拒绝路径不写批准段，仍走现有合法 reject 转换（如 `approve-requirement:reject -> write-requirement-prd`）。**AC-10b（代码评审二轮 b10、三轮回修）**：`approve --resign` 非交互式调用一律 `APPROVAL_REQUIRES_HUMAN`（无旁路）；无既有审批段 → `RESIGN_NO_PRIOR_APPROVAL`；`server-approve` → `RESIGN_SERVER_APPROVAL_UNSUPPORTED` 且原段不变；本地审批 digest 已一致 → 幂等 no-op；本地审批真实 TTY 迁移后 gate 复绿，reason/approver 特殊字符保持单一 YAML 标量，且 CAS、审计与受控提交均有运行时证据。
- **AC-11**（FR-9）：构造「task index 存在但全部 pending」的 CR 执行 `advance --to archived`，返回 `TASK_STATUS_INCOMPLETE` 且不归档；构造「task index 缺失」同样被拦截，不得解释为 no-task。
- **AC-12**（FR-9）：TASK 全 done 但 `delivery/task/_index.yaml` 缺失时被拦截；全部就绪后正常归档；rejected/withdrawn 无 TASK 时可进入 history。
- **AC-13**（FR-9）：`archive-move --final-status` 与 cr.md 当前 status 不一致时硬失败。
- **AC-14**（FR-10）：运行 `crctl migrate-backlog` 后 `_backlog.yml` 幽灵条目消失、CR-2026-017 条目完整（title/summary/owners/created/updated 恢复）；再次运行返回 `already-clean` 且文件哈希不变。
- **AC-15**（FR-11）：归档时 inbox 事件与三账本同批写入；CAS 冲突或事件结构错误时事件与三账本均不写；中文 archive reason 不因 Shell 转义丢失；三角色收件人去重、legacy 顶层 owner 回退、空收件人 `ARCHIVE_RECIPIENTS_MISSING`、可选 spec-id、重复归档均按契约处理。
- **AC-16**（FR-11）：普通 `inbox-emit` 在 `--to` 缺失、非列表、去重后为空时返回 `BAD_ARGS`，不写无收件人 notify-log。
- **AC-17**（FR-12）：archived/rejected/withdrawn 三种终态 `crctl status` 返回终态与 `source: history`，`crctl next` 返回 `next:null` 不报错；backlog/history 同存同 CR 报 `CR_LOCATION_CONFLICT`；history 重复或缺 final-status 硬失败；cr.md 漂移输出 warning 且以 history 为准；active CR 查询行为不回归。
- **AC-18**（FR-13）：`review-record` 输出含 `files[]`/`attempt`/`route`/`repairTarget` 且与本次实际写入一致（未 bump 不虚列 review-loop.yml）；四个 review Skill 不再重新读取 traceability 核对刚写入结果；`next` 仍由 `crctl next` 唯一计算。
- **AC-19**（FR-14）：五项最小验证全部通过：① `git diff --check` 无告警；② `JSON.parse(feature-writeback.pipeline.json)` 通过；③ `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿；④ `lint-prompts.mjs --mode enforce` 零发现；⑤ 按 AC-1 的搜索范围与判定方式 grep 确认 tools 隐藏特例与 25/47「现状」表述已清零。
- **AC-22**（FR-15）：实施首步完成后：`../tools` 仓存在 `requirement/CR-2026-027` 分支与对应 worktree（基线 = custom/main HEAD）；`git log` 确认 custom/main 无本 CR 直接提交的实施改动；CR-2026-027 在 tools 的 merge-commits 记录与 docs/multica 同批生成（merge 阶段验收）；归档清理覆盖 tools worktree。
- **AC-23**（FR-16）：
  - `task-breakdown`：无/畸形 `dev-plan.yml` → `review-dev-plan`；PASS → `crctl approve --stage dev-start`；repair BLOCK → `write-dev-plan`；顶层 `repair-target=write-tech-design` → `write-tech-design`；block 且 cycle exhausted → `next:null` + 人工处理，不返回审批。
  - `tech-design-review-pending`：SDD digest 与旧 annotation 不一致，或较新的 dev-plan upstream blocker 存在 → `review-tech-design`；fresh PASS 才返回 `crctl approve --stage tech-design`。
  - 技术评审旧 cycle 已 3/3 且上一轮 PASS 时，post-PASS SDD revision 的首次 `--bump-attempt` 自动生成 cycle=2/attempt=1；旧 cycle attempts 完整保留，后续 cycle 内仍最多 3 次。
- **AC-20**（NFR-1/NFR-4/NFR-5）：不新增第三方依赖与公共 Runner 库；无通用 patch/workflow 实现；crctl.mjs 保持单文件；writeback scripts 未被复制。
- **AC-21**（NFR-6）：历史 CR 查询/归档行为兼容（旧 approval/archive 形态不要求迁移）；`_index.yml` 查询链路不变。

### 6. 成功指标

- **正确性**（§16.1）：状态和账本无旁路；approval 与 status 同一提交；TASK pending 不可回写/归档；archive event 不丢失；archived CR 可查询；所有参与仓来自机器可读声明；候选工具不通过隐藏路径治理当前 CR。
- **效率基线**（§16.2 观测值，不在本 CR 内考核达成）：以 v2 方案表格固化各阶段当前外部调用量（注册 24、PRD 编写 9、implement-code 63 等）与目标值（8-12、3、25-35 等），作为 Phase 2+ 候选路线的对照基线；不得通过删除 gate、测试、补偿或人工审批达成。
- **维护性**：已证明需要 Runner 的语义 Skill 最多 prepare/finalize 两个入口（本 CR 不引入）；无基于历史 CR 的 schema 推断；无会话临时账本脚本；现有 writeback scripts 得到复用。
- **数据健康**：`_backlog.yml` 无幽灵条目；归档 CR 的 `_index.yml` 终态字段与 history 一致。

### 7. 范围排除

**本 CR 包含**：Phase 0 文档/声明修改（workspace AGENTS.md、dir-graph.yaml、CONTEXT.md 复核、v2 方案文档、tools ARCHITECTURE.md、merge-feature-branch SKILL.md 特例删除）；**tools 仓 bootstrap worktree 派生与实施落地（D-12/FR-15/AC-22）**；Phase 1 crctl.mjs 与 crctl.test.mjs 修改（approve 原子化、TASK 门禁、archive-move 原子化、终态 resolver、review-record 输出）；migrate-backlog 扩展与幽灵条目清理（FR-10/D-11）；四个 review Skill 的 traceability 二次读取删除；按 §6.6 的五项最小验证。

**本 CR 不包含**（Phase 2+ 全部候选路线，须分别重新确认并另写 Spec）：
- PRD Runner 垂直试点（prepare/finalize、create/repair 双模式、CR PRD 最小确定性校验、typed outputs）。
- 最小公共能力与 Registration（`skills/shared/runner/lib.mjs`、requirement-register run.mjs、tools root 解析、repo context、checkpoint kind 扩展）。
- 其余 Authoring/Review Runner（requirement review、SDD、tech review、Plan/TASK、dev-plan review）。
- Implement/Test/Code Review Runner（implement prepare/finalize、`crctl test --plan`、test-report Runner、code review Runner、scope-change ledger）。
- Merge/Writeback/Archive Runner（merge run.mjs、writeback run.mjs、traceability prepare/finalize、archive run.mjs、cleanup-report、`merge-metadata --from result.json`）。
- 可选高级机制（control-plane SHA pin、永久 scope-change ledger、永久 task reconcile、writeback plan artifact、crctl 模块化、并行 remote push）。
- 不重新设计 CR 状态机业务流程、不删除 reviewLoop、不跳过人工审批、不引入数据库账本、不引入 YAML 第三方库、不建立通用 Workflow Engine、不自动实施 review suggestions、不一次性重写全部 Skills、不附带拆分 crctl.mjs。

### 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿（基于 v2 方案 §5-§6 与质询记录 Q1~Q10 转写；14 条 FR、8 条 NFR、21 条 AC；幽灵条目清理入范围 D-11/FR-10/AC-14） |
| 2026-08-09 | v0.2.0 | Ray | 修订（需求评审 BLOCK 回修，blocker=FR-5/AC-5 tools 仓引导缺失）：新增 D-12/FR-15/AC-22（tools worktree bootstrap——声明入 repositories 后从 custom/main 补建 requirement/CR-2026-027 分支，禁止直写 custom/main，merge/cleanup 走正常流程）；新增 D-13（target-version 维持 tbd 的批准口径说明）；按 suggestions 固定 AC-1/AC-19 的 grep 搜索范围与判定方式（历史注脚引用不违规）；§1.2/§7 同步 |
| 2026-08-09 | v0.3.0 | Ray | 拍板同步（用户决策 2026-08-09）：FR-10/D-11 落点从 skills/shared/scripts/ 迁移脚本改为 crctl migrate-backlog 扩展（SDD v0.2.0 方案），消除 PRD/SDD 冲突；AC-14 验收语义不变 |
| 2026-08-09 | v0.4.0 | Ray | 修订（review-tech-design 二轮 BLOCK 回修，TD2-BL-1）：AC-14 字面同步为“运行 `crctl migrate-backlog` 后”，清除“迁移脚本”残留（验收语义不变） |
| 2026-08-09 | v0.5.0 | Ray | 范围确认（用户决策 2026-08-09）：纳入 CR-2026-026 遗留缺陷——next task-breakdown 路由缺 dev-plan.yml 检查（实测导致无评审记录时误报 approve dev-start）；新增 FR-16/AC-23，归属 TASK-07 |
| 2026-08-09 | v0.6.0 | Ray | 上游回修（review-dev-plan UPSTREAM BLOCK）：扩展 D-14/FR-16/AC-23，补 task-breakdown route 的 canonical 来源、tech-design SDD freshness、upstream 重入与 post-PASS 新 review cycle；旧 cycle attempts 保留审计，不新增子命令 |
| 2026-08-10 | v0.6.1 | Ray | 代码评审二轮 BLOCK 回修（b10）：FR-8/AC-10b 新增受控历史审批迁移 `approve --resign <reason>`（TTY 人类在环、只重签 digest、保留审批本体、resign 审计子块、幂等）；FR-10/AC-9b 幽灵清理审计时序修正（先 casWrite 成功、后 auditLog，CAS_CONFLICT 零成功记录）；SDD v0.6.1 同步 |
| 2026-08-10 | v0.6.2 | Ray | 代码评审三轮 BLOCK 回修：FR-8/AC-10b 收紧为只迁移 `crctl-approve`；`server-approve` 必须服务端重签；补 YAML 安全标量、真实 TTY 成功路径与真实 CAS_CONFLICT 运行时验收。 |

## 发布联调移交 merge pipeline（v0.2 · CR-2026-029）

## PRD — 发布联调移交 merge pipeline 完成证据（发布类任务不落开发 TASK）

- **版本**：v0.1.0
- **cr-ref**：CR-2026-029
- **状态**：drafting

### 1. 概述

#### 1.1 问题陈述

CR-2026-028 的 TASK-10（发布与联调，4h）被拆为开发期 TASK，但实际执行（双仓 merge、真实 worktree 走查、台账核账）只发生在代码审批之后、`merging` 状态。`crctl task done` 前置态仅 `developing`，导致：

- TASK-10 永远无法通过权威命令登记 `done`（实测 `ILLEGAL_LEDGER_STATE`，当前 merging）；
- 归档门禁（CR-2026-027 FR-9）检查 tasks 全 done 与 delivery 覆盖，TASK-10 残留 pending 会阻塞 writeback 与归档；
- 发布联调的真实完成证据散落在会话输出与 git 历史，没有结构化落盘。

根因：**"发布联调"是 merge pipeline 的职责，不是开发 TASK**。把发布类工作拆进 `developing` 阶段的 TASK，与 `task done` 前置态、归档门禁的语义冲突。

#### 1.2 解决方案摘要

把发布联调从开发 TASK 改为 **merge-feature-branch 的完成证据**：

1. `merge-feature-branch` Skill 在 merge push 成功后新增"发布联调走查"步骤：验证各仓 trunk 的 CR 状态、worktree-path、next，核对 multica CUSTOM.md 台账，把走查结果结构化落盘为 `change-requests/{cr}/merge-verification.md`；
2. `feature-writeback.pipeline.json` 的 merge-feature-branch 节点 prompt 同步该步骤；
3. 明确约定：**发布联调、merge 验证类工作归 merge pipeline，不创建开发 TASK**；
4. 迁移：移除 CR-2026-028 的 TASK-10（tasks/_index.yml 条目 + TASK-10.md），在其变更记录注明移交 merge pipeline（CR-2026-029）。

#### 1.3 事实基线

- `crctl task done` 前置态：`developing`（crctl.mjs `cmdTaskDone` LEGAL 数组）；
- 归档门禁：tasks 空/全 pending/部分 done/delivery 缺失均拦截（CR-2026-027 FR-9）；
- CR-2026-028 当前 `merging`，merge 已完成（tools `870f26d`、multica `c8c96e56a`、knowledge-base `24d39f1`），TASK-10 无法登记 done（实测 `ILLEGAL_LEDGER_STATE`）；
- merge-feature-branch Skill 当前 6 步：预检 → 本地合并 → commit → push → 状态推进 → 摘要（无联调走查证据落盘）。

### 2. 功能需求

- **FR-1（merge pipeline 联调走查）**：`merge-feature-branch/SKILL.md` 在"更新 CR status"步骤后新增"发布联调走查"步骤：① 各仓 trunk 拉取后以主 checkout 与 linked worktree 分别执行 `crctl status`/`worktree-path`/`next`，确认无 `STATUS_DIVERGED`/嵌套路径异常；② 核对 `CUSTOM.md` 台账条目与合并后代码一致；③ 将走查结果（各仓 merge-sha、走查命令与结论、异常与处理）结构化写入 `change-requests/{cr}/merge-verification.md`，提交到 knowledge-base trunk。
- **FR-2（pipeline prompt 同步）**：`feature-writeback.pipeline.json` 的 merge-feature-branch 节点 prompt 增加联调走查与 merge-verification.md 产出描述，与 Skill 一致。
- **FR-3（发布类任务约定）**：merge-feature-branch Skill 明确"发布联调、merge 验证类工作归 merge pipeline，不创建开发 TASK"；`write-dev-tasks` 拆分时不得再产生发布/联调类 TASK。
- **FR-4（迁移 CR-2026-028 TASK-10）**：从 `change-requests/CR-2026-028/tasks/_index.yml` 移除 TASK-10 条目、删除 `tasks/TASK-10.md`，在 CR-2026-028 变更记录（cr.md 或 sdd.md 变更记录）注明"发布联调移交 merge pipeline（CR-2026-029）"；CR-2026-028 的 test-report.md TASK 覆盖矩阵同步。
- **FR-5（验证）**：`crctl.test.mjs` 新增 merge-verification 生成断言（或既有 writeback 测试扩展）；CR-2026-028 在迁移后 tasks 全 done、无 TASK-10，归档门禁通过。

### 3. 验收标准

- **AC-1（FR-1）**：对某 CR 执行 merge-feature-branch 后，knowledge-base trunk 出现 `change-requests/{cr}/merge-verification.md`，含三仓 merge-sha、status/worktree-path/next 走查结论与台账核账结果。
- **AC-2（FR-2）**：pipeline JSON 可解析，merge-feature-branch 节点 prompt 与 Skill 步骤一致（含 merge-verification 产出）。
- **AC-3（FR-3）**：merge-feature-branch Skill 明确发布类工作归 merge pipeline；write-dev-tasks Skill/pipeline 无发布联调类 TASK 拆分指引。
- **AC-4（FR-4）**：CR-2026-028 的 tasks/_index.yml 无 TASK-10、TASK-10.md 已删、变更记录注明移交；其 tasks 状态全 done。
- **AC-5（FR-5）**：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿（含新增用例）；CR-2026-028 归档门禁检查通过。

### 4. 范围排除

- 不改 `crctl task done` 前置态（把 merging 加入 LEGAL）——治标且放宽账本语义，属被否决替代方案；
- 不新增 crctl 子命令、不改归档门禁判定本身；
- 不重跑 CR-2026-028 的 merge（已完成）。

### 5. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-10 | v0.1.0 | Ray | 初稿：发布联调移交 merge pipeline 完成证据 |

## Tools Root 唯一解析与路径统一（CR-2026-028）（v0.29 · CR-2026-028）

## PRD — tools 流程步骤优化 v2：前移优化项

### 1. 概述

#### 1.1 问题陈述

CR-2026-027 已完成 tools 流程优化 Phase 0/1 的基线事实统一与正确性修复，但目标 workspace 如何定位 tools 包仍存在多套隐式规则：当前 `crctl.mjs` 的状态机 loader 会依次尝试 workspace `dir-graph.yaml`、`<workspace>/tools/dir-graph.yaml` 与执行脚本所在 package root；Pipeline loader 会尝试 `<workspace>/tools/pipeline-templates/` 与 package root；gates/default controlled-shell rules 又固定跟随执行脚本所在 checkout。Skill、Pipeline 与 Adapter 中还存在大量 `node tools/skills/...` 或 `$WORKSPACE/tools/...` 当前用法。

在 AI First Platform workspace 中，真实 tools 包位于 sibling `../tools/`，workspace 内同名 `tools/` 是残留空壳。现有行为可能误读空壳目录，或让状态机/Pipeline 与 gates/rules 来自不同 tools checkout。knowledge-base linked worktree 又带来第二个事实：CR 阶段文件应在 worktree 中读写，但 `tools_package_path: "../tools"` 若相对于 worktree checkout 解析会失效。继续依赖 package-root 回退会掩盖配置错误，并使同一项目实际使用哪个 tools 包取决于启动入口。

Registration 侧也存在文档漂移：`crctl cr-init` 已支持一次传入 title、summary、source、target-version 等元数据，但 `requirement-register` 仍描述建档后直接补写受控 frontmatter，Pipeline prompt 还重复描述 cr-init 建档动作。

**问题边界**：本 CR 只修正基础路径与入口契约，复用现有 crctl、cr-init、Adapter 模板和 writeback 脚本；不建设 Runner、installer、自动路径修复器、版本 pin 或跨仓上下文框架。

#### 1.2 解决方案摘要

1. 以 Installation Workspace 的 `dir-graph.yaml#workspace.tools_package_path` 为 Tools Root 唯一事实源；相对路径以 Installation Workspace 为基准，绝对路径直接使用，最终 realpath 归一；配置或身份验证失败统一 `TOOLS_PACKAGE_NOT_FOUND`，无隐式回退。
2. 区分 Operational Workspace（CR 文件实际读写 checkout）与 Installation Workspace（knowledge-base 主 checkout、Tools Root 安装基准）；knowledge-base linked worktree 通过 Git common-dir 找到安装基准，非 knowledge-base worktree 显式复用 `execution_context.knowledge_base_worktree`。
3. 在 `crctl.mjs` 内增加最小、单值惰性 resolver，不拆公共库；state machine、Pipeline、gates、默认 controlled-shell rules 统一从 Tools Root 加载，保留已有显式 `CRCTL_RULES_PATH` 覆盖。
4. 只修 active executable surfaces：active Skill/Pipeline、Adapter/CI 模板与安装说明、当前入口文档；静态配置安装时物化 `{TOOLS_ROOT}`，绝对路径只进入本机 local settings。
5. Registration 直接一次调用现有 `cr-init` 写齐元数据，删除模型二次补写 frontmatter 与 Pipeline 重复描述；cr-init 代码零新增能力。
6. 删除 tools 包自身无人消费的 `target_install_path: "tools/"`；multica 本轮只更新 `CUSTOM.md` 记录现存跨仓消费点，代码暂缓。

#### 1.3 事实基线

| # | 已核实事实 | 依据 |
|---|---|---|
| B-1 | workspace `dir-graph.yaml#workspace.tools_package_path` 已声明 `../tools`，真实 tools 包为 sibling；workspace 内存在同名空壳目录 | workspace `AGENTS.md`、`dir-graph.yaml` |
| B-2 | `loadStateMachine` 当前搜索 workspace graph、`workspace/tools`、`PACKAGE_ROOT`；`loadPipeline` 搜索 `workspace/tools` 与 `PACKAGE_ROOT` | tools `skills/shared/crctl/scripts/crctl.mjs` |
| B-3 | `gates.json` 与默认 controlled-shell rules 当前跟随执行脚本 checkout，可能与状态机/Pipeline 分裂 | crctl 常量 `GATES_PATH`、`RULES_PATH` |
| B-4 | `main()` 在分发实际子命令前 eager `loadGates()`；`help` 在 workspace 解析前返回 | crctl `main()` |
| B-5 | active writeback Skill/Pipeline、crctl Skill 与 Adapter 模板仍存在 `tools/skills/...`、`$WORKSPACE/tools/...` 当前命令 | tools active Skill/Pipeline/Adapter 定向检索 |
| B-6 | `cr-init` 已支持 `--summary`、`--source`、`--target-version` 且 CR-2026-028 注册已一次写齐 | crctl help、cr-init 现有测试与本 CR 注册实录 |
| B-7 | tools `dir-graph.yaml#workspace.target_install_path: "tools/"` 无代码消费，与目标 workspace 的唯一声明冲突 | tools 定向检索 |
| B-8 | multica 已有生成器/跨工具测试猜测 sibling tools 路径；生产 `MULTICA_CONTROLLED_SHELL_RULES` 已使用显式绝对路径 | multica 现有代码与 `CUSTOM.md` |
| B-9 | 现有 crctl 测试为零依赖 CLI 黑盒套件，公共 `makeWorkspace()` 可承接严格配置 | `crctl.test.mjs` |

#### 1.4 质询决策

| # | 决策 | 拍板结果 |
|---|---|---|
| D-1 | 统一对象 | 统一 Tools Root 契约，不强制所有消费者共享运行时代码；当前 resolver 留在 crctl 单文件内 |
| D-2 | 绑定时机 | 动态调用方运行时解析；IDE hooks/CI 安装时物化 |
| D-3 | 缺配置行为 | 硬失败，不保留 package-root 或 workspace/tools 兼容回退 |
| D-4 | 身份标志 | 固定验证 AGENTS.md、dir-graph.yaml、skills/_index.yml、crctl.mjs 四项 |
| D-5 | 修改范围 | active executable surfaces 白名单；历史/生成内容不批量替换 |
| D-6 | multica | 现存消费点登记 CUSTOM“未做”，本轮不改代码，不新增 resolver |
| D-7 | Registration | cr-init 能力已完成，本项只修 Skill/Pipeline 漂移 |
| D-8 | 调用内复用 | 单进程单值惰性缓存，不创建 execution context |
| D-9 | worktree 基准 | Operational/Installation Workspace 分离，Git common-dir 定位安装基准（ADR-0003） |
| D-10 | 路径类型 | 允许相对与绝对路径，realpath 归一；仓库配置推荐相对路径 |
| D-11 | 静态路径变化 | 重新执行安装替换，不建设自动修复器 |
| D-12 | tools 版本 | 只验证包身份，不做 branch/SHA/version pin |
| D-13 | package 配置 | Tools Root 统管 state machine、Pipeline、gates、默认 rules；保留 CRCTL_RULES_PATH |
| D-14 | 自动发现 | 只覆盖 knowledge-base checkout/worktree；其他参与仓显式传 knowledge_base_worktree |
| D-15 | 第二安装声明 | 删除 tools `target_install_path`，不保留默认安装位置字段 |
| D-16 | 静态配置落盘 | 仓库保留 `{TOOLS_ROOT}` 模板；本机绝对路径只进 local settings |
| D-17 | 测试强度 | 扩展现有黑盒套件；不建 resolver/Adapter 独立测试框架 |

#### 1.5 契约优先级与版本口径

`cr.md#summary` 是 2026-08-10 15:06 注册时的快照，早于本 CR 的 grilling 拍板，且当前没有允许修改 summary 的 crctl 专用入口；因此不通过模型直接编辑受控 frontmatter。该快照中的以下三点已被本 PRD D-3/D-4/D-9 与同步修订后的 source 明确取代：

1. “相对 workspace root”改为“相对 Installation Workspace”；
2. 三标志验证增加 `dir-graph.yaml`，固定为四标志；
3. 删除“独立运行时回退 crctl package root”，统一为配置错误硬失败。

需求评审、审批、SDD 与实施以本 PRD 和 `docs/analysis/tools流程步骤优化v2-前移优化项.md` 的质询后契约为准；注册快照只保留审计来源，不作为并行实施口径。

`target-version: tbd` 的批准口径：本 CR 是 tools 包内部契约优化，不进入 AI First Platform 产品版本号递增链路；需求审批确认范围即可，不为此虚构产品版本。

### 2. 用户故事

- **US-1** 作为 tools 流程使用者，我希望每个项目只需在 workspace 目录图声明一次 tools 包位置，即可从主 workspace、knowledge-base CR worktree或其子目录稳定使用同一 tools 包。
- **US-2** 作为 CR 执行者，我希望 workspace 内即使存在空壳 `tools/`，crctl 也不会误读或静默回退，而是使用显式声明或给出明确错误。
- **US-3** 作为 tools 维护者，我希望状态机、Pipeline、gates 与默认 controlled-shell rules 来自同一 Tools Root，避免不同 checkout 配置混用。
- **US-4** 作为 Skill/Pipeline/Adapter 使用者，我希望当前执行指令不假设 tools 固定安装在 workspace 的 `tools/` 子目录。
- **US-5** 作为需求注册执行者，我希望一次 `cr-init` 原子写齐注册元数据，不再由模型第二次编辑受控 frontmatter。
- **US-6** 作为维护者，我希望本次修改只覆盖真实 active surface，并复用现有黑盒测试，不引入尚无消费者的 Runner、installer 或共享路径框架。

### 3. 功能需求

- **FR-1（Tools Root 唯一契约）**：Installation Workspace 的 `dir-graph.yaml#workspace.tools_package_path` 是 Tools Root 唯一声明；相对值以 Installation Workspace 为基准，绝对值直接使用，结果经 realpath 归一。配置缺失、非字符串/空值、路径不存在或身份标志不完整统一返回 `TOOLS_PACKAGE_NOT_FOUND`，detail 必须说明配置值、解析路径或缺失标志；不得尝试 workspace 同名 `tools/`、cwd、调用方 package root 或正在执行的 crctl 所在 checkout。
- **FR-2（workspace 双根语义与 worktree 定位）**：Operational Workspace 负责 CR 阶段文件读写；Installation Workspace 负责 Tools Root 路径基准及 workspace-owned `.rayai-worktrees/` 根。普通 checkout 两者相同；knowledge-base linked worktree 通过 Git common-dir 找主 checkout。`crctl worktree-path` 必须以 Installation Workspace 拼接 `.rayai-worktrees/{bucket}/requirement/{cr}`，从 linked worktree 调用不得返回嵌套的第二个 `.rayai-worktrees`；`push-progress`、`pull-progress`、`resume-from-remote` 继续只消费该命令结果，不自行拼路径。不得改写 worktree graph、创建 symlink/junction或新增 `--tools-root`。tools/multica worktree 必须显式使用 requirement-register 已输出的 `knowledge_base_worktree` 作为 `--workspace`，由其 Git common-dir 得到 Installation Workspace；不得按分支名、CR-ID 或目录扫描猜测。
- **FR-3（四标志身份验证）**：resolver 固定验证 `{toolsRoot}/AGENTS.md`、`dir-graph.yaml`、`skills/_index.yml`、`skills/shared/crctl/scripts/crctl.mjs`；这四项只证明 tools 包身份，不验证 Git branch、commit SHA、版本或全部资源完整性。Pipeline、gates 等目标文件继续由消费者按需校验并沿用现有专用错误码。
- **FR-4（crctl 配置来源收敛）**：在现有 `crctl.mjs` 内实现单值惰性 Tools Root resolver，同一进程只解析一次，不拆公共模块。`loadStateMachine` 只读 `{toolsRoot}/dir-graph.yaml`；`loadPipeline` 只读 `{toolsRoot}/pipeline-templates/`；`loadGates` 只读 `{toolsRoot}/skills/shared/crctl/gates.json`；默认 controlled-shell rules 只读 `{toolsRoot}/skills/shared/controlled-shell/rules.json`。保留显式 `CRCTL_RULES_PATH` 覆盖，不新增其他覆盖入口。`help` 保持无需 workspace；其余子命令沿用现有 eager gates 行为。
- **FR-5（active 执行入口统一）**：只修改 §3.1 的 active surface 白名单；其中实际命令改用 `{TOOLS_ROOT}/skills/...` 逻辑路径并明确来源。动态调用方运行时解析；静态模板安装时物化；所有 Adapter 模板统一字面占位符 `{TOOLS_ROOT}`，删除 `{TOOLS}`/`{WORKSPACE}` 同义占位符。仓库不得提交含本机绝对路径的物化 settings；白名单外历史分析、审查报告、生成 HTML、OpenWiki、inactive/old 内容不做全仓替换。
- **FR-6（Registration 复用 cr-init）**：`requirement-register` 调用现有 `crctl cr-init` 时一次传入 title、owner-requirement、summary、source、target-version；删除建档后直接编辑 `cr.md` frontmatter 的步骤；合并 requirement-authoring Pipeline 中重复的 cr-init 建档描述。三文件原子建档与 bucket/repositories 派生语义保持；worktree 根基准按 FR-2 修正（统一以 Installation Workspace 为根）。不修改 cr-init 实现，不新增 wrapper、register-preflight、registration-check、stage-context 或 Registration Runner。
- **FR-7（删除第二安装位置声明）**：删除 tools `dir-graph.yaml#workspace.target_install_path`，并把同文件“固定挂载到 tools/”的当前描述改为由目标 workspace `tools_package_path` 绑定；不新增替代字段。
- **FR-8（multica 延后项登记）**：本 CR 不修改 multica 代码；`CUSTOM.md#未做` 必须列出现存 sibling tools 猜测点及后续修复方式。生成器后续要求显式 tools root，跨工具测试后续要求显式 `CRCTL_PATH`/rules path；生产 `MULTICA_CONTROLLED_SHELL_RULES` 继续作为安装时物化绝对路径，不新增 multica resolver。
- **FR-9（最小回归验证）**：扩展现有 `crctl.test.mjs`：公共 workspace fixture 显式绑定隔离的最小 tools fixture；表驱动覆盖相对/绝对路径、空壳目录、缺配置、无效路径、四标志缺失；增加一个 Git linked-worktree 黑盒场景并同时验证 Tools Root 与 `worktree-path` 的 Installation Workspace 基准；使用四类 sentinel 配置分别通过 CLI 行为证明 state machine、Pipeline、gates、默认 rules 均来自声明的 Tools Root，并验证 `CRCTL_RULES_PATH` 覆盖。单值惰性缓存以“所有 loader 调用同一 module-scope resolver 且只有一个成功值槽”的代码审查断言验收，不新增 telemetry。复用现有 cr-init metadata 测试；active 文档/模板按 §3.1 精确范围与禁止模式定向检索；不新增 resolver 测试包、mock filesystem、IDE E2E 或跨平台 Adapter matrix。

#### 3.1 active surface 白名单与检索口径

| 类别 | 本 CR 可修改文件 |
|---|---|
| 核心实现与测试 | `dir-graph.yaml`；`skills/shared/crctl/scripts/crctl.mjs`；`skills/shared/crctl/scripts/test/crctl.test.mjs` |
| workspace 当前入口 | knowledge-base 根 `AGENTS.md`（与 tools 包内同名文件区分，属目标 workspace 入口文档） |
| crctl / Registration | `skills/shared/crctl/SKILL.md`；`skills/requirement/requirement-register/SKILL.md`；`pipeline-templates/requirement-authoring.pipeline.json` |
| 生命周期同步 | `skills/sync/push-progress/SKILL.md`；`skills/sync/pull-progress/SKILL.md`；`skills/sync/resume-from-remote/SKILL.md` |
| writeback | `skills/writeback/writeback-prd-sdd/SKILL.md`；`writeback-tasks/SKILL.md`；`writeback-traceability/SKILL.md`；`skills/writeback/scripts/test/writeback.test.mjs`；`pipeline-templates/feature-writeback.pipeline.json` |
| Adapter / CI | `skills/shared/crctl/adapters/**` 的现有文件 |

定向检索在上表范围内要求以下当前命令模式零命中：`node tools/skills/`、`node ../tools/skills/`、`$WORKSPACE/tools/`、`<workspace>/tools/`、`$CLAUDE_PROJECT_DIR/tools/`、`{TOOLS}/tools/`、`{WORKSPACE}/tools/`。其中 `node ../tools/skills/` 主要命中 knowledge-base 根 `AGENTS.md` 的 crctl 调用示例，应改为不绑定安装位置的表达。包内源码使用 `import.meta.url` 定位兄弟文件允许保留；`ARCHITECTURE.md` 历史否决示例、`skills/reviewer-panel.yaml` 自路径注释、`skills/shared/engineering-docs/SKILL.md` 概念引用及历史/生成/inactive 内容明确排除。CI 可以把实际 checkout 目录赋给 `TOOLS_ROOT`，但执行命令不得直接硬编码 `node tools/skills/...`。

### 4. 非功能需求

- **NFR-1（不过度设计）**：不新增 Runner、installer、watcher、repairer、bootstrap launcher、execution context、共享 resolver library、缓存文件或新 crctl 子命令。
- **NFR-2（单一事实源）**：除已有显式 `CRCTL_RULES_PATH` 外，不得出现第二 Tools Root 配置、package-root 兼容回退或 workspace/tools 隐式候选。
- **NFR-3（可移植性）**：仓库中的 workspace 配置推荐相对路径；Adapter 仓库模板保留 `{TOOLS_ROOT}`；不得提交本机绝对路径。Windows 盘符、symlink/junction 由 Node path/realpath 处理，不手写平台分支。
- **NFR-4（兼容业务语义）**：不得修改现有状态机转换、gate/passCondition、审批、CAS、账本、worktree bucket 与 human approval 语义；仅改变 package-owned 配置的定位方式和 prompt 路径表达。
- **NFR-5（零新增依赖）**：实现使用 Node 标准库与现有 YAML 解析能力；测试继续使用 `node:test`、`node:assert` 和现有 Git CLI，不新增 npm 依赖。
- **NFR-6（行尾与失败纪律）**：读取 YAML 后按现有规则兼容 CRLF/LF；解析或结构定位失败必须硬失败，不得以空配置或 package-root fallback 静默继续。
- **NFR-7（可诊断性）**：`TOOLS_PACKAGE_NOT_FOUND` detail 必须足以区分字段缺失、路径不存在与身份标志缺失；成功路径继续通过现有 source path 输出暴露实际加载文件，不新增全局 telemetry。

### 5. 验收标准

- **AC-1（FR-1/FR-3）**：相对 `tools_package_path` 与绝对 `tools_package_path` 均解析到 realpath 后同一目录；四个身份标志齐全时通过。
- **AC-2（FR-1/FR-3）**：字段缺失/空值/非字符串、目标目录不存在、四标志任一缺失均返回 `TOOLS_PACKAGE_NOT_FOUND`，错误 detail 指明具体原因且无其他候选读取。
- **AC-3（FR-1）**：在 workspace 内创建包含同名子路径的空壳 `tools/` 后，crctl 仍只使用声明的 Tools Root；将声明路径破坏后必须失败，不得转读空壳。
- **AC-4（FR-2）**：从 Installation Workspace 根目录及任意子目录调用，解析结果相同；从 knowledge-base linked worktree 根目录及子目录调用，CR 文件来自该 worktree而 Tools Root 相对于主 checkout 解析。对三个 active repo 运行 `worktree-path` 均返回主 checkout 下现有路径，结果不得包含重复的 `.rayai-worktrees/.../.rayai-worktrees`；`push-progress` 的 worktree map 前置校验可据此通过。
- **AC-5（FR-2）**：从 tools/multica worktree 显式传 `--workspace <knowledge_base_worktree>` 可用，并由该 knowledge-base worktree 的 Git common-dir 找到 Installation Workspace；不传时不承诺反推对应 CR，且实现中不存在分支名、CR-ID 或 `.rayai-worktrees` 扫描逻辑。
- **AC-6（FR-4/FR-9）**：隔离 fixture 为四类资源设置可辨识 sentinel：状态机使用仅 fixture 存在的合法转换、Pipeline 使用仅 fixture 存在的 nodeRef/passCondition、gates 使用仅 fixture 要求的证据文件、rules 使用仅 fixture 允许/拒绝的 git shape；分别调用公开 CLI 并断言对应行为，以证明四类资源来自声明的同一 Tools Root。测试不要求新增 source 输出字段；执行脚本来自另一 checkout 时 sentinel 结果不变。
- **AC-7（FR-4）**：设置有效 `CRCTL_RULES_PATH` 时仍使用显式 rules；未设置时使用 Tools Root rules；无新增 gates/rules 覆盖环境变量。
- **AC-8（FR-4）**：代码评审确认 state machine、Pipeline、gates、默认 rules 四个 loader 均调用同一 module-scope resolver，resolver 仅维护一个成功值槽且无 Map/文件缓存/telemetry；一个需要多个 loader 的黑盒命令使用同一 fixture 行为成功。`crctl help` 在无 workspace 时仍成功。
- **AC-9（FR-5）**：§3.1 白名单中的七个禁止模式定向检索零命中（含 `node ../tools/skills/` 与 workspace 根 `AGENTS.md`）；所有 Adapter 模板只使用 `{TOOLS_ROOT}`，安装说明明确其来自 `workspace.tools_package_path`。列明的白名单外允许例外不计失败。
- **AC-10（FR-5/NFR-3）**：版本库 diff 中无新增本机绝对路径；local settings/CI 的物化边界说明清楚，未新增自动安装或修复代码。
- **AC-11（FR-6）**：requirement-register 的一次 cr-init 调用传齐 summary/source/target-version；成功后无模型二次编辑 frontmatter 指令；Pipeline 中 cr-init 三文件建档动作只描述一次。
- **AC-12（FR-6）**：现有 cr-init metadata 黑盒测试通过，`cr.md`、`_backlog.yml`、`_index.yml` 一次建档结果不回归；cr-init 实现无为本 CR 新增的子命令或 wrapper。
- **AC-13（FR-7）**：tools `dir-graph.yaml` 不再含 `target_install_path` 或固定安装到 `tools/` 的当前权威描述；目标 workspace `tools_package_path` 保持唯一安装位置声明。
- **AC-14（FR-8）**：multica 代码 diff 为空；`CUSTOM.md#未做` 准确列出四类现存消费点、显式参数升级路径及 `MULTICA_CONTROLLED_SHELL_RULES` 保留语义。
- **AC-15（FR-9）**：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿，包含路径表驱动、四类 sentinel、`CRCTL_RULES_PATH` 覆盖与 linked-worktree/worktree-path 场景；fixture 不修改真实 tools checkout，且没有新增独立 resolver/Adapter 测试框架。
- **AC-16（NFR-4）**：现有状态机、gate、approve、账本、cr-init、worktree-path 相关回归测试全绿；状态机声明数与转换语义无变化。
- **AC-17（全局）**：执行并通过：① `git diff --check`；② `JSON.parse` 校验 `requirement-authoring.pipeline.json` 与 `feature-writeback.pipeline.json`；③ `node --test skills/shared/crctl/scripts/test/crctl.test.mjs`；④ `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`；⑤ 仅按 §3.1 白名单执行七个禁止模式的 `rg`，零命中。不得以全仓替换历史内容来达成⑤。

### 6. 成功指标

- **路径确定性**：给定同一 Installation Workspace，无论从主 checkout、knowledge-base linked worktree或其子目录调用，Tools Root realpath 唯一且可解释。
- **配置一致性**：一次 crctl 调用中 state machine、Pipeline、gates、默认 rules 不再来自不同 tools checkout。
- **旁路清零**：active executable surfaces 中不存在 workspace/tools 或 package-root 隐式回退；空壳目录无法影响执行。
- **注册复用**：Registration 只调用一次现有 cr-init，受控 frontmatter 无模型补写步骤。
- **维护成本**：不增加第三方依赖、公共 Runner/resolver、installer 或跨平台 Adapter harness；修改集中在现有 loader、prompt、模板和测试入口。

### 7. 范围排除

- PRD/SDD/Plan/TASK/Review/Implement/Test/Merge/Writeback/Archive Runner。
- shared Runner library、typed outputs、`.crctl/runs`、完整 repo/worktree/base context 持久化。
- tools branch/SHA/version pin、compatibility matrix、control-plane SHA pin。
- Adapter 自动 installer、settings 无损合并器、路径 watcher/repairer。
- 从任意参与仓 worktree 自动反推 knowledge-base worktree。
- multica 生成器、跨工具测试与生产代码的本轮路径修复；本轮只登记 CUSTOM 延后项。
- 历史分析、审查报告、生成 HTML、OpenWiki、inactive/old 内容的批量路径替换。
- 新增 `--tools-root`、register-preflight、registration-check、stage-context、Registration Runner 或 cr-init wrapper。
- 修改 CR 状态机、gate、审批、CAS、账本或 worktree 业务语义。
- 为 tools 路径变更提供运行时兼容回退或迁移期双读。

### 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-10 | v0.1.0 | Ray | 初始草稿：承接 `tools流程步骤优化v2-前移优化项.md` 与 grill-with-docs 质询 17 项拍板；9 条 FR、7 条 NFR、17 条 AC |
| 2026-08-10 | v0.2.0 | Ray | 第 1 轮需求评审 BLOCK 回修：声明注册快照优先级与 tbd 口径；将 worktree-path/push-progress 纳入双 workspace 契约；固定 active surface 白名单与六个禁止模式；以四类 sentinel + 代码审查断言替换不可观察的配置来源/缓存验收 |
| 2026-08-10 | v0.3.0 | Ray | 第 2 轮需求评审 BLOCK 回修：workspace 根 `AGENTS.md` 纳入白名单并新增 `node ../tools/skills/` 禁止模式；FR-6 收窄为 bucket/repositories 派生语义保持、worktree 根按 FR-2 修正 |

## tools TCA-001～004 最小优化 — cr-init 三 Owner 注册契约 + owner-set 正式移交 + grant reject 验证回退 + review-dev-plan 精确 trigger / R7 字面量校验（v0.3 · CR-2026-030）

## PRD — tools TCA-001～004 最小优化 — cr-init 三 Owner 注册契约 + owner-set 正式移交 + grant reject 验证回退 + review-dev-plan 精确 trigger / R7 字面量校验

### 1. 概述

#### 1.1 问题陈述

`docs/analysis/tools-text-contract-audit.md` 识别出的 TCA-001～004，在 `../tools@cab3663e224c7198d954b4d25bee5f4a8803a452`（`custom/main`）和 `../multica@c8c96e56a4bae1a2fb84c5700cffec174631ef74`（`main`）核对基线中均成立。现有测试虽全部通过，但关键入口没有兑现 Skill、Pipeline、状态机与平台审批链已经声明的契约：

1. Registration 声明三角色 Owner，实际 `cr-init` 只接收 requirement Owner 并复制到 development/test；Pipeline 还暴露底层忽略的 `cr_id`。
2. 正式移交描述要求更新 `cr.md`、backlog、历史与通知，实际 `owner-set` 只写 backlog；`resume-from-remote` 又附带 Owner 写入，形成第二业务入口。
3. 平台已经生成并投递 Ed25519 v1 grant，但 `reject` 在归属、证据和签名完整验证前即被拒绝，无法执行状态机已有驳回回退。
4. `review-dev-plan` 使用短 trigger `review-dev-plan:block`，而权威状态机要求精确字面量 `review-dev-plan:block -> write-dev-plan`，运行时必然拒绝；现有 R7 又无法静态发现该错误。

这些问题属于现有入口与现有权威契约不一致，不需要增加新编排层、第二审批协议或通用账本框架。继续补文案而不修入口，会让注册 Owner、正式移交、人工驳回和开发计划评审在真实执行中持续漂移。

#### 1.2 目标

本 CR 以最小修改让现有入口兑现既有契约：

1. Registration 一次接收并原子写入三角色 Owner，注册提交成功后才以真实 SHA 产生注册事实。
2. `handover-cr` 成为正式移交唯一业务入口，`owner-set` 成为一致写入、提交和事件投影的受控账本原语。
3. approve/reject 复用现有 v1 签名 grant，reject 完整验证后执行状态机已有回退，并支持紧邻结果状态幂等重放。
4. `review-dev-plan` 独占两个状态命令并使用权威 trigger，Pipeline 仅承担三路路由与既有重放。
5. R7 直接消费权威状态机转移声明，静态拦截可确定的错误 `--to/--trigger` 字面量。

#### 1.3 事实基线

| 编号 | 已核实事实 | 依据 |
|---|---|---|
| B-1 | 基线检查为 `lint-prompts 0 findings`、57 个 active Skill 通过、9 Agent contract 通过、Pipeline JSON 通过、crctl 189/189 测试通过 | 优化方案 §3 |
| B-2 | `cr-init` 当前只接收 `--owner-requirement`，并将同一值复制到三个 Owner | crctl 当前实现与本 CR 注册实录 |
| B-3 | `cmdOwnerSet()` 当前只更新 `_backlog.yml`，未兑现双投影、历史、提交和通知契约 | TCA-002 核对 |
| B-4 | 平台已有 Ed25519 v1 grant、默认落点与 `crctl approve --grant`，缺口仅在 reject 验证和回退 | TCA-003 核对 |
| B-5 | 状态机权威 NORMAL trigger 为 `review-dev-plan:block -> write-dev-plan`，`findTransition()` 精确匹配 | tools `dir-graph.yaml` 与 crctl 当前实现 |
| B-6 | 当前 R7 只检查 `advance` 是否带 `--to/--trigger`，不校验字面量是否存在于状态机 | `lint-prompts.mjs` 当前实现 |
| B-7 | 当前没有 Pipeline Runner 保证平台签名 approve/reject 分派到对应 `approve-*` Skill | 优化方案 §6.1 |
| B-8 | Multica 尚未消费 owners/inbox 注册投影；本 CR 不修改 Multica production code，仅允许扩展既有 Go→crctl 跨接缝测试并同步 `CUSTOM.md` | `CUSTOM-TODO-003/004/005` 边界、`server/internal/governance/approval_crosscheck_test.go` |

#### 1.4 契约优先级与版本口径

本 PRD 以 `docs/analysis/tools-tca-001-004-optimization-plan.md` 的已确认实施边界为需求输入；状态机、门禁、权限和 grant v1 结构仍以 tools 仓权威文件为准。PRD、后续 SDD 或实现不得复制一份状态机、grant 协议或 Git 路径算法作为第二事实源。

`target-version: tbd` 表示该变更尚未绑定产品发布版本，不表示允许省略验收或回写版本。后续人工审批可保持 `tbd`，不得为通过门禁虚构产品版本。

本 PRD 对 source 中“本轮不修改 Multica 源码”的口径作唯一消歧：**Multica production code 零修改，但允许 `server/internal/governance/approval_crosscheck_test.go` 的 test-only diff，并必须同步 `CUSTOM.md` 台账**。除此之外的 Multica 文件均不在修改范围；该口径不代表 owners/inbox 消费、registration reconcile 或 Pipeline Runner 已交付。

### 2. 用户故事

- **US-1** 作为 CR 注册执行者，我希望一次显式提供 requirement、development、test 三个 Owner，使注册结果与 Pipeline 输入一致，即使三者是同一人也没有隐式继承。
- **US-2** 作为后续 Pipeline 节点，我希望只消费原语返回的 Owner、branch、path 和真实提交 SHA，避免模型拼接不存在的执行事实。
- **US-3** 作为 CR 责任移交者，我希望正式移交同时更新权威双投影、唯一责任历史和通知事实，并在远端包含该提交后才宣称完成。
- **US-4** 作为接手远端 CR 的执行者，我希望恢复 worktree 只恢复权威状态，不在恢复过程中隐式改变责任归属。
- **US-5** 作为平台审批人，我希望签名 reject 与 approve 一样经过归属、状态、证据和签名验证，并让合法驳回回到现有回修状态。
- **US-6** 作为 Pipeline 编排者，我希望区分“人工驳回已成功回退”和“技术执行失败”，以便中止当前正向流程而不伪装成系统故障。
- **US-7** 作为开发计划评审执行者，我希望 PASS、NORMAL、UPSTREAM 三路结果稳定对应继续、普通回修和上游设计回退。
- **US-8** 作为 tools 维护者，我希望错误的静态 trigger 在 lint 阶段被发现，且校验直接使用权威状态机声明。

### 3. 功能需求

#### FR-1 三角色原子注册

`crctl cr-init` 必须显式要求 `--owner-requirement`、`--owner-development`、`--owner-test`。缺少任一参数时返回参数错误且对 `cr.md`、`_backlog.yml`、`_index.yml` 零写入；不得保留把 requirement Owner 复制给其他角色的兼容路径。

同一次注册必须生成一个时间戳，并复用于三处当前 Owner 与三条 `reason=initial-assignment` 的 `owner-history`。顶层兼容字段 `owner` 恒等于 `owners.requirement.id`。三文件继续由一次 `casWriteMulti()` 原子写入，CR-ID 分配和并发冲突语义保持不变。

`cr-init` 成功返回必须至少包含 `cr`、`status`、完整三角色 `owners` 与三个文件路径。其成功 audit 可记录完整 Owner 投影和三项初始变化；不得记录尚不存在的 branch、worktree、commit SHA 或 outbox 成功事实。`cr-init` 不产生注册 outbox。

#### FR-2 注册提交、执行上下文与失败边界

`requirement-register` 在 `cr-init` 后必须调用 `crctl git commit --template register --cr <CR-ID>`。只有 commit 成功后，受控 Git 原语才读取真实 HEAD SHA 与 `cr.md` 权威 Owner，并以同一 SHA 尝试产生：

1. `event_kind=status`：`(new) -> drafting`；
2. `event_kind=owners`：完整三角色当前投影与三项 `reason=initial-assignment` 的 `changes[]`。

commit 失败不得产生注册事件；outbox 失败不得回滚已成功 commit，必须返回 `warnings[]` 并记录 `EMIT_FAILED` audit。

`crctl worktree-path` 必须返回 canonical `branch`、`bucket`、`path`。Skill 只能汇总 `cr-init`、register commit 与 `worktree-path` 的真实返回；不得读取 HEAD、拼 branch/path/SHA 或构造事件。全部 push/worktree 步骤成功后才输出 `execution_context`，至少包含 CR-ID、status、owners、branch、registration commit、knowledge-base worktree 与所有参与仓 worktree 映射。

三文件 CAS 成功即永久占用 CR-ID。后续 commit、push 或 worktree 创建失败时返回 `REGISTRATION_INCOMPLETE`，包含 `cr_id`、`failed_step`、`completed_steps`、`commit_sha`、`created_worktrees`、`warnings`；不得输出成功上下文、回收 CR-ID或再次调用 `cr-init`。单仓 fetch 失败可沿用 `STALE_BASE` warning；真正的 worktree 创建失败必须中止。

#### FR-3 Owner 双投影与唯一责任历史

`owner-set <cr_id> --role <requirement|development|test> --id <new-owner> [--note <text>]` 保留命令名，作为本地可信环境中的受控账本原语。执行任何 YAML 写入前，必须通过受控 Git 原语确认整个仓库的 tracked index 与 tracked working tree 均 clean；untracked 文件不阻塞。存在任一预先 staged、预先 unstaged 或二者并存的 tracked 变更时，返回 `OWNER_WORKTREE_DIRTY/changed=false`，分别列出 staged 与 unstaged 路径，并保证 YAML、audit、commit、outbox 零新增；不得自动暂存、提交、丢弃或重分层既有变更。

clean precondition 通过后，必须校验 `cr.md` 与 `_backlog.yml` 的三个当前 Owner 以及顶层兼容 `owner` 一致；任一漂移均返回结构化错误并零写入，不自动修复。

真实变化必须只生成一次时间戳，并复用于两处 `owners.{role}`、requirement 角色的两处顶层 `owner`、`cr.md#owner-history`、backlog 通知事实、audit 和 outbox。`cr.md#owner-history` 是唯一责任历史，只追加一条 `reason=formal-handover` 的 `role/from/to/at` 记录，可选 `note` 仅进入该历史和 inbox 通知事实。`handover-history` 停止新增，仅兼容读取；backlog 不复制责任历史。

候选 `cr.md` 和 `_backlog.yml` 必须由一次 `casWriteMulti()` 写入；backlog 同批追加 `owner-handover` notify-log 与 notify-pending。同值重放仅在双投影一致且整个仓库的 tracked index/working tree clean 时返回 `changed=false`，不得更新时间、历史、通知、audit、commit 或 outbox。

#### FR-4 正式移交唯一入口与恢复只读

`handover-cr` 是正式移交唯一业务入口，固定顺序为 `owner-set -> push-progress`。删除 `skip_push`；只有远端包含 Owner 变更提交才算移交完成。push 失败保留本地正式移交 commit，传播现有结构化错误并由 Pipeline 中止。

`resume-from-remote` 必须删除 `new_owner`、`new_owner_role` 及所有 Owner 写入，只负责恢复 worktree、读取权威状态与调用 `crctl next`。`inbox-emit` 继续服务其他通知场景，不删除。

`owner-set` 不使用 `identity(ws)` 伪造“当前 Owner/admin/force”强授权判断；本 CR 只保证本地可信环境中的受控账本一致性，不宣称提供对抗恶意调用者的平台身份认证。

#### FR-5 Owner 提交、回滚与事件投影

`owner-set` 对 `cr.md` 与 `_backlog.yml` 的真实变化形成一次隔离的正式 commit。CAS 写入后只能暂存这两个受控路径；commit 前必须再次确认 staged 路径集合恰好等于这两个文件且不存在其他 tracked working-tree 变化，否则按本节失败回滚恢复 clean baseline，返回结构化技术错误，不得生成成功 commit。只有 commit 成功才记录成功 audit，并以同一真实 SHA 分别尝试：

1. `event_kind=owners`：完整三角色当前投影与本次一个 `reason=formal-handover` 的 change；
2. `event_kind=inbox`：`event=owner-handover`、收件人与结构化移交事实。

`crctl` 不生成 `subject/body` 等展示文案。outbox 失败只返回 warning 并记录 `EMIT_FAILED`，不回滚 commit、也不阻止后续发布；本地写出 outbox 不等于 Multica 已应用 Owner 或完成通知触达。

若 Git add/commit 或 commit 前隔离校验可观测失败，必须以新内容 hash 为 CAS 前提恢复两个原始快照，撤销本次对这两个路径的暂存，并验证 tracked index 与 tracked working tree 恢复为命令开始时的 clean baseline。成功恢复返回 `OWNER_COMMIT_FAILED/changed=false/rolled_back=true`；恢复 CAS、撤销暂存或 clean-baseline 校验失败返回 `OWNER_COMMIT_ROLLBACK_FAILED` 并列出受影响文件。两种结果都必须中止，禁止进入 `push-progress`；不得通过 reset、checkout 或提交来吞掉并发出现的外部变更。

#### FR-6 签名 grant 双模式与 reject 完整验证

四个 `approve-*` Skill 必须保留双模式：平台非 TTY 使用默认 grant 落点并调用 `crctl approve <cr> --stage <stage> --grant`；本地独立 CLI 无 grant 时继续要求当前 TTY。Pipeline 不拼 grant 路径、不复制 CLI 算法。grant 缺失、签名错误、归属不符、证据漂移或技术投递失败均为技术失败，必须中止且不得模型代签或直接 advance。

`approveWithGrant()` 对 approve/reject 共用以下前置验证：schema v1 与 decision 枚举、`cr_id/stage` 归属、当前状态或合法紧邻结果状态、当前 evidence digest、key 与 Ed25519 signature。reject 不执行 approve 路径的 passCondition，因为 blocker 是合法驳回原因。

验证成功的 reject 必须复用现有四阶段 `REJECT_ROLLBACK` 与权威状态机 trigger，回退成功后返回结构化非零业务结果 `APPROVAL_DECLINED_ROLLED_BACK`，包含 decision、stage、rolledBackTo、trigger、changed。该结果表示人工决定已捕获且回退成功，必须中止当前正向 Pipeline；不得伪装为 `EXEC_FAILED`、`CAS_CONFLICT` 等技术失败，也不得返回 `rerunHint`、下一 Skill 指令或手写 review annotation 文案。

#### FR-7 approve/reject 紧邻结果态幂等

approve 在审批前置态时正常验证并推进；当前状态正好等于该阶段 approve 目标态，且 `approval.yml` 中 `approver/key-id/signature/grant-approved-at/evidence-digest` 与输入完全一致时返回成功 `changed=false`。进入其他状态或持久化字段不一致时返回 `GRANT_STATE_MISMATCH`。

reject 在审批前置态时正常验证并回退；当前状态正好等于该阶段 reject 回退目标态，且 grant 归属、当前 evidence digest 与签名仍有效时再次返回 `APPROVAL_DECLINED_ROLLED_BACK/changed=false`。进入其他状态时返回 `GRANT_STATE_MISMATCH`。

两个幂等分支均不得重复 audit、commit 或 outbox；reject 不新增第二份持久化审批账本，不把未签名 `reject_reason` 写入 Git、Skill 输入或事件。

#### FR-8 开发计划评审三路路由

`review-dev-plan` Skill 是两个状态命令的唯一拥有者，并输出三路结构化结果：

1. **PASS**：仅当 `verdict=pass && blockers=[]`，不推进状态，保持 `task-breakdown`，返回 `route=pass`，Pipeline 继续。
2. **NORMAL**：使用 `--to tech-design-reviewed --trigger "review-dev-plan:block -> write-dev-plan" --expect task-breakdown --embedded`，成功后返回 `route=normal`、`verdict=block` 和 `review_feedback`。Pipeline 仅按现有 `maxAttempts=3` 重放 `write-dev-plan -> write-dev-tasks -> review-dev-plan`，耗尽沿用 `LOOP_EXHAUSTED`，不得进入人工审批。
3. **UPSTREAM**：使用 `--to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker --expect task-breakdown --embedded`，成功回退后返回结构化非零业务结果 `UPSTREAM_DESIGN_BLOCKER`，包含 route、verdict、review feedback 和回退状态。当前 coding Pipeline 必须立即中止，不进入 NORMAL reviewLoop，也不增加 NORMAL attempt。

Pipeline prompt 必须删除上述两个具体 `crctl advance` 命令，只保留 PASS/NORMAL/UPSTREAM 路由、`replayNodes` 和失败中止语义。

#### FR-9 R7 权威 trigger 字面量校验

现有 `lint-prompts.mjs` R7 必须读取 tools `dir-graph.yaml#change-request-track.state_machine.transitions`。输入先规范化 `\r\n -> \n`；跨行或结构解析失败必须硬失败，禁止退化为空 transitions。

对 Skill 中可静态确定的 `crctl advance --to <literal> --trigger <literal>`，R7 必须验证 `(to, trigger)` 至少匹配一条权威转移。包含模板变量的值跳过；不从自然语言或文件位置推断 `from`，运行时完整合法性继续由 `crctl advance` 裁决。不得复制状态机常量或给旧短 trigger 增加兼容别名。

#### FR-10 Skill、Pipeline 与人读契约同步

在不改变节点数量的前提下同步以下当前入口：

- `requirement-register` 使用三 Owner 参数并汇总权威 execution context；`requirement-authoring.pipeline.json` 删除无效 `cr_id` 和命令复制。
- `handover-cr` 收敛为 `owner-set -> push-progress`；`resume-from-remote` 删除 Owner 输入与写入。
- 四个 `approve-*` Skill 区分平台 grant、本地 TTY、业务 reject 与技术失败；相关 Pipeline 只传递决定并在失败时中止。
- `review-dev-plan` 持有两个精确 advance；`code-implementation.pipeline.json` 只保留路由与 replay。
- `README.md`、`AGENTS.md`、`ARCHITECTURE.md` 仅修正失真的当前契约，不新增第二事实源或未交付自动化描述。

##### FR-10.1 精确修改白名单

| 类别 | 本 CR 允许修改的文件 |
|---|---|
| crctl 与测试 | `skills/shared/crctl/scripts/crctl.mjs`；`skills/shared/crctl/SKILL.md`；`skills/shared/crctl/scripts/test/crctl.test.mjs`；`skills/shared/crctl/scripts/lint-prompts.mjs`；`skills/shared/crctl/scripts/test/lint-prompts.test.mjs` |
| Skill | `skills/requirement/requirement-register/SKILL.md`；`skills/sync/handover-cr/SKILL.md`；`skills/sync/resume-from-remote/SKILL.md`；`skills/requirement/approve-requirement/SKILL.md`；`skills/develop/approve-tech-design/SKILL.md`；`skills/develop/approve-dev-start/SKILL.md`；`skills/develop/approve-code/SKILL.md`；`skills/develop/review-dev-plan/SKILL.md` |
| Pipeline | `pipeline-templates/requirement-authoring.pipeline.json`；`pipeline-templates/architecture-design.pipeline.json`；`pipeline-templates/code-implementation.pipeline.json`；`pipeline-templates/resume-cr.pipeline.json` |
| tools 人读契约 | `README.md`；`AGENTS.md`；`ARCHITECTURE.md` |
| Multica test-only | `server/internal/governance/approval_crosscheck_test.go`；`CUSTOM.md` |

Pipeline 节点数量保持不变，不修改 `pipeline-templates/_index.yml#nodes`。本 CR 不修改 CI workflow。Multica 除上述 test-only 文件与台账外零 diff；修改 `approval_crosscheck_test.go` 时必须按 Multica `CLAUDE.md` 使用英文注释，并按当时 `CUSTOM.md` 实际结构登记 CR/TASK 追溯。

### 4. 非功能需求

- **NFR-1（最小设计）**：不新增 `owner-handover`、注册聚合巨型命令、恢复子命令、Pipeline Runner、数据库、WAL、通用 YAML 框架、grant v2、rejection 文件或 crctl 模块拆分。
- **NFR-2（权威来源）**：状态机、门禁、权限、grant v1 和 Git branch/path 算法继续使用现有权威文件或原语；Skill/Pipeline/README 不复制可执行规则。
- **NFR-3（原子与失败安全）**：受控账本继续使用 CAS；正式移交要求 tracked index/worktree clean 并形成只含两份 Owner 账本的隔离 commit；跨行解析失败硬失败；可观测 Git 失败按 FR-5 恢复 clean baseline，禁止静默部分成功或吸收既有变更。
- **NFR-4（安全边界诚实）**：不把本地 `identity(ws)` 或 Owner 字段描述为强认证身份，不宣称 outbox 写出等于平台投影应用或通知触达。
- **NFR-5（兼容性）**：现有 approve 成功路径、本地 TTY 模式、状态机转移、`inbox-emit` 其他调用方、Pipeline 节点数量和既有 CI 入口不得回归。
- **NFR-6（零新增依赖）**：实现复用 Node 标准库、现有 YAML 解析、Ed25519 grant、`casWriteMulti()`、controlled-shell 与 node:test，不新增第三方依赖或测试框架。
- **NFR-7（行尾纪律）**：读取 YAML 或做跨行正则前统一 `\r\n -> \n`，逐行解析使用 `split(/\r?\n/)`；CRLF 与 LF 行为等价，解析不完整时必须失败并报告原因。

### 5. 验收标准

#### 5.1 Registration

- **AC-1（FR-1）**：传入三个不同 Owner 时，`cr.md`、backlog、audit 与返回 JSON 中三角色值一致；顶层 `owner` 仅等于 requirement Owner，三条 initial history 使用同一时间戳。
- **AC-2（FR-1）**：缺任一 Owner 返回参数错误，`cr.md`、backlog、index 与 audit/outbox 均无新增。
- **AC-3（FR-1/FR-2）**：`cr-init` 不发 outbox；register commit 成功后使用真实 HEAD SHA 产生一条 status 与一条 owners 事件，两者 SHA 相同且 owners 事件含三个 change。
- **AC-4（FR-2）**：registration commit 失败不产生事件；outbox 任一写出失败时 commit 仍成功，返回 warning 并存在 `EMIT_FAILED` audit。
- **AC-5（FR-2）**：`worktree-path` 返回 branch/bucket/path；Skill 输出的 execution context 中对应值逐项等于原语返回，Skill/Pipeline 中不存在 branch/path/SHA/event 手工拼接。
- **AC-6（FR-2）**：commit、push 或 worktree 创建失败返回 `REGISTRATION_INCOMPLETE`，不输出成功上下文、不分配第二个 CR-ID，并准确列出完成步骤与已创建 worktree。

#### 5.2 正式移交

- **AC-7（FR-3）**：双投影一致时才允许变更或同值幂等；任一角色或顶层兼容 owner 漂移时零写入并返回结构化错误。
- **AC-8（FR-3）**：真实变化只追加一条 `owner-history`，不追加 `handover-history`；requirement 移交同步两处兼容 `owner`，note 只进入 owner-history 与 inbox 事实。
- **AC-9（FR-3）**：Owner 双投影、owner-history、notify-log、notify-pending、成功 audit 的 `handover-at` 与 owners/inbox outbox payload 的 `handover_at` 均等于 `owner-set` 本次唯一时间戳；事件 envelope 自身投递时间不作相等要求。`cr.md` 与 backlog 由一次 `casWriteMulti()` 提交候选内容。
- **AC-10（FR-3/FR-4）**：同值重放不产生时间、历史、通知、audit、commit 或 outbox，但 `handover-cr` 仍进入 `push-progress` 以发布可能已存在的 commit。
- **AC-11（FR-4）**：`handover-cr` 无 `skip_push`，固定执行 `owner-set -> push-progress`；push 失败保留本地 commit 并明确返回未完成，不能输出移交完成。
- **AC-12（FR-4）**：`resume-from-remote` 的输入、正文和执行路径均无 `new_owner/new_owner_role` 或 Owner 写入；恢复后只读取状态并调用 `crctl next`。
- **AC-13（FR-5）**：commit 成功后以同一真实 SHA 尝试 owners + inbox 两类 outbox；payload 无 `subject/body`，owners payload 含完整三角色投影且仅一个 formal-handover change；两类 payload 的 `handover_at` 与 AC-9 的唯一时间戳一致。
- **AC-14（FR-5）**：outbox 失败不回滚 commit、不阻止发布，并记录 `EMIT_FAILED`；Git add/commit 或 commit 前隔离校验失败时不得写成功 audit 或任何 outbox，成功恢复两个原始快照并撤销本次暂存，验证 tracked index/working tree 回到命令开始时的 clean baseline，返回 `OWNER_COMMIT_FAILED`。
- **AC-15（FR-5）**：注入恢复 CAS 冲突、撤销暂存失败或 clean-baseline 校验失败时返回 `OWNER_COMMIT_ROLLBACK_FAILED` 和受影响文件，且不调用 `push-progress`；并发出现的外部变更不得被 reset、checkout、提交或静默重分层。
- **AC-16（FR-3/FR-5）**：分别构造①仅预先 staged、②仅预先 unstaged、③同一路径或不同路径 staged+unstaged 并存的 tracked 变更，`owner-set` 均返回 `OWNER_WORKTREE_DIRTY/changed=false`，准确分列 staged/unstaged 路径且 YAML、既有 index/worktree 分层、audit、commit、outbox 完全不变；untracked-only fixture 不阻塞。clean fixture 的成功 commit staged diff 只包含 `cr.md` 与 `_backlog.yml`，不得吸收其他路径。

#### 5.3 签名审批

- **AC-17（FR-6）**：四个 stage 的 approve grant 均可正常推进；本地无 grant 调用仍要求 TTY，Pipeline 中无 grant 默认路径或 CLI 拼接。
- **AC-18（FR-6）**：四个 stage 的 reject 仅在 schema、decision、归属、状态、evidence digest、key 和签名全部有效后执行权威回退。
- **AC-19（FR-6）**：伪造签名、跨 CR/stage 挪用、证据漂移、错误状态均零写入且返回对应技术错误；不执行回退。
- **AC-20（FR-6）**：合法 reject 返回 `APPROVAL_DECLINED_ROLLED_BACK`，包含目标状态与权威 trigger，无 `rerunHint`、下一 Skill、未签名 reason 或手写 review annotation。
- **AC-21（FR-7）**：approve 在紧邻目标态且持久化字段完全一致时 `changed=false`；reject 在紧邻回退态且 grant/evidence/signature 仍有效时返回 `APPROVAL_DECLINED_ROLLED_BACK/changed=false`。
- **AC-22（FR-7）**：approve/reject 进入其他状态或 approve 持久化字段不一致时返回 `GRANT_STATE_MISMATCH`；幂等分支不重复 audit、commit 或 outbox。

#### 5.4 开发计划路由与静态检查

- **AC-23（FR-8）**：PASS 仅在 `verdict=pass && blockers=[]` 成立，保持 `task-breakdown` 并继续后续节点。
- **AC-24（FR-8）**：NORMAL 使用完整 trigger 从 `task-breakdown` 回到 `tech-design-reviewed`，只进入现有三节点 replay，最多三轮；短 trigger 在运行时仍被拒绝。
- **AC-25（FR-8）**：UPSTREAM 使用权威 trigger 回到 `tech-design-review-pending`，返回 `UPSTREAM_DESIGN_BLOCKER` 并中止 coding Pipeline，不进入 NORMAL replay 或增加 NORMAL attempt。
- **AC-26（FR-8/FR-10）**：`review-dev-plan` Skill 中存在两个具体 advance；Pipeline 中不存在这两个命令，只存在 route、replayNodes 与 abort 语义；Pipeline 节点数量不变。
- **AC-27（FR-9）**：R7 对完整 NORMAL trigger 通过，对短 trigger 输出 `CONTRADICTS`；校验从当前 `dir-graph.yaml` transitions 读取，不含复制常量或兼容别名。
- **AC-28（FR-9/NFR-7）**：同一 fixture 的 CRLF/LF 输入结果等价；transitions 跨行或结构解析失败时 lint 硬失败，不允许空数组继续。
- **AC-29（FR-9）**：含模板变量的 `--to/--trigger` 被明确跳过；静态 literal 仅校验 `(to, trigger)` 至少命中一条声明，不从自然语言推断 from。

#### 5.5 全量回归

- **AC-30（FR-10）**：FR-10.1 白名单内的 Skill 与人读契约均与本 PRD 一致，不描述 CUSTOM-TODO-001～006 为已交付；Multica production code 零 diff，Multica 只允许 `server/internal/governance/approval_crosscheck_test.go` 与 `CUSTOM.md` 发生 diff，CI workflow 无修改。
- **AC-31（FR-10）**：四个 Pipeline 分别满足：① `requirement-authoring.pipeline.json` 删除 `cr_id` 输入/透传，显式传三 Owner、只消费完整 execution context，审批节点不复制命令或手写 reject；② `architecture-design.pipeline.json` 的审批节点只表达决定传递和技术失败中止；③ `code-implementation.pipeline.json` 的 dev-plan 评审只保留 PASS/NORMAL/UPSTREAM route 与 replay，审批节点不复制 CLI 算法；④ `resume-cr.pipeline.json` 无 `new_owner/new_owner_role` 和 Owner 写入。四个 JSON 节点数量保持，`pipeline-templates/_index.yml#nodes` 不变。
- **AC-32（全局）**：以下命令全部通过：

```bash
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/check-agents-contract.mjs
node --test skills/shared/crctl/scripts/test/*.test.mjs
node --test skills/writeback/scripts/test/*.test.mjs
node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));"
```

审批跨接缝测试只允许扩展 Multica 既有 `server/internal/governance/approval_crosscheck_test.go`，增加 Go 签名 reject grant 被真实 crctl 验签、回退及紧邻状态幂等消费的向量；同步更新 `CUSTOM.md` 台账，不新建集成框架、不修改 Multica production code。

### 6. 成功指标

- **注册契约一致性**：三个不同 Owner 在注册双投影、初始历史、audit、结构化返回和注册事件中无差异；注册事件使用真实提交 SHA。
- **正式移交一致性**：任一成功移交只有一条责任历史、一个只含两份 Owner 账本的隔离 commit 和同 SHA 的 owners/inbox 投影尝试；预存 tracked staged/unstaged 变更一律零副作用拒绝，不存在恢复流程附带 Owner 写入。
- **审批决定可消费**：四阶段合法签名 reject 均能完成权威回退，伪造/挪用/漂移向量全部零写入；重放不重复副作用。
- **开发计划路由可执行**：PASS、NORMAL、UPSTREAM 三路均有黑盒覆盖，NORMAL 完整 trigger 可执行，短 trigger 在 lint 与运行时均被拦截。
- **治理无新增分叉**：无新状态、无第二 grant 协议、无第二 Owner 历史、无 Runner/WAL/数据库/新依赖；Pipeline 节点数与 CI 入口保持不变。

### 7. 范围排除

- 不新增 `owner-handover` 命令、注册聚合巨型命令或恢复子命令。
- 不新增 Pipeline Runner、数据库、WAL、通用 YAML 框架、grant v2 或 rejection 文件。
- 不实现跨进程自动续跑 incomplete registration；保留 `CUSTOM-TODO-006`。
- 不实现可信 `reject_reason` 传输与 Runner 注入；保留 `CUSTOM-TODO-001/002`。
- 不修改 Multica production code，不实现 owners/inbox 消费或 registration reconcile；仅允许修改 `server/internal/governance/approval_crosscheck_test.go` 增加 reject 跨接缝向量并同步 `CUSTOM.md`，保留 `CUSTOM-TODO-003/004/005`。
- 不宣称 outbox 写出等于平台 Owner 投影已应用或通知已触达。
- 不删除仍被其他流程使用的 `inbox-emit`。
- 不修改 CI workflow，不拆分 `crctl.mjs`。
- 不治理 TCA-005 及之后问题，不扩展为 tools 全量文本契约审计。
- 不为 Owner 字段或本地 `identity(ws)` 增加伪造的强授权语义。
- 不解决 `casWriteMulti()` 逐个 rename 之间进程直接崩溃的极端窗口；后续一致性检查必须暴露脏文件。

### 8. 风险与约束

1. `owner-set` 的 Git add/commit 回滚只覆盖可观测失败，无法覆盖进程在账本写入后直接崩溃；本 CR 以一致性检查暴露该状态，不引入 WAL。
2. grant reject 回退依赖当前状态机与 evidence digest；评审或状态已继续推进后，旧 grant 必须拒绝而不是猜测恢复路径。
3. R7 是静态字面量守卫，只能校验可确定的 `(to, trigger)`；模板变量与完整 from 合法性仍由运行时裁决。
4. outbox 是非阻断投影通道；消费者故障时 Git 仍是权威事实，平台需要后续 reconcile 能力。
5. 当前没有 Pipeline Runner，Skill/Pipeline 文档只能收敛契约，不能宣称平台端自动分派已交付。
6. `owner-set` 为保证正式 commit 隔离，要求整个仓库的 tracked index 与 tracked working tree clean；调用者必须先提交、暂存外移或丢弃自己的 tracked 变更，本 CR 不提供自动 stash。

### 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-11 | v0.1.0 | Ray | 初始草稿：承接 TCA-001～004 优化方案，形成 10 条 FR、7 条 NFR、30 条 AC |
| 2026-08-11 | v0.2.0 | Ray | 第 1 轮需求评审 BLOCK 回修：继承 CR title；纳入 source；明确 Multica test-only diff + CUSTOM 台账；固定修改白名单与四 Pipeline 验收；补齐 audit/outbox 时间戳及失败验收，AC 增至 31 条 |
| 2026-08-11 | v0.3.0 | Ray | 第 2 轮需求评审 BLOCK 回修：owner-set 增加 tracked clean precondition、隔离 commit staged-set 校验及 clean-baseline 失败恢复；覆盖 staged/unstaged/并存 fixture，AC 增至 32 条 |

## crctl 执行层职责边界与事务化（v0.4 · CR-2026-031）

## 1. 概述

当前 CR 注册、workspace 创建/恢复/清理、跨仓 merge、merge finalize、writeback 和 archive 的关键 Git、账本与恢复步骤分散在 Pipeline、Skill 和 `crctl.mjs` 中。文本算法重复导致事实源漂移，进程中断后没有统一事务身份，部分远端发布无法可靠续跑，post-merge writeback 还可能落到错误 checkout。

本 CR 将这些执行职责收敛到 crctl：Agent 只路由意图，Pipeline 只编排节点，Skill 只做业务前置和一次深原语调用，版本化脚本只生成确定性 candidate。实现作为一个完整 CR 交付，约 12 个 TASK 在同一 requirement branch 内完成；本 CR 自身使用旧流程完成 merge/writeback/archive，下一 CR 起启用新协议。

## 2. 用户故事

- **US-01 执行平台维护者**：希望所有状态、账本、Git/workspace 和恢复动作由一个可测试入口拥有，以便修复一次即可覆盖所有 Pipeline/Skill 调用。
- **US-02 需求/开发负责人**：希望注册、merge、writeback、archive 重跑时自动识别已完成副作用，以便进程崩溃或单仓失败后继续而不重复分配 CR-ID 或覆盖不属于本事务的资源。
- **US-03 代码审批人**：希望审批绑定明确的 source SHA 和 PRD/SDD/TASK 内容摘要，以便 merge/writeback 不会消费审批后漂移的内容。
- **US-04 平台运营者**：希望 post-merge 写入固定 Transaction Workspace，并能看到 archive cleanup-pending，以便业务终态与运维清理状态分离且可追踪。
- **US-05 工具开发者**：希望事务公共能力保持小而具体，以便在没有真实复杂度证据前不引入通用 saga、插件系统或第三方依赖。

## 3. 功能需求

### FR-01 职责边界与公共入口

crctl 必须独占状态/gate、CAS、账本写入、审计、Git/workspace 事务和恢复；Pipeline/Skill 不得复制这些算法。对外提供幂等深原语 `register`、`merge`、`workspace ensure/inspect/cleanup`、`writeback-apply`、`archive`，并删除已被替代的 `cr-init`、`worktree-path`、`merge-metadata`、`archive-move` 和确认无消费者的冗余命令。不得新增 npm 依赖、数据库、消息队列、分布式锁或通用事务框架。

### FR-02 durable transaction 基础能力

新增最多两个内部模块：`durable-tx.mjs` 和 `workspace-transactions.mjs`。前者提供公共 journal envelope、原子目录锁、recoverable write-set、fsync/rename、fault injection、blob 清理；后者保留 `registerCr`、`ensureWorkspace`、`mergeCr`、`applyWriteback`、`archiveCr` 等具体函数。公共 envelope 必须带 `v/txId/op/cr/phase/graphDigest/inputDigest/sideEffects/commit/lastError`，并按 Git trailer 支持 journal 丢失后的恢复。

### FR-03 注册和 workspace 幂等

`crctl register` 必须以 `registration_key` 幂等：同 key 重跑复用 CR-ID 和 txId，不同 key 可创建相同业务输入的不同 CR；输入摘要变化返回 `REGISTRATION_INPUT_MISMATCH`。注册失败 roll-forward，保留健康资源并只补齐缺失仓。workspace 按 `missing/healthy/branch-only/remote-only/dirty/wrong-branch/path-unregistered` 分类，未知或 dirty 资源不得自动删除。

### FR-04 跨仓 merge 可恢复

`crctl merge` 必须先零副作用 prepare，再按单仓 ref CAS 发布，远端副作用后持久化 intent/observation，并通过 `confirmed|pushable|rebuild|history-rewritten` 分类续跑。merge source 必须读取 signed release snapshot 的 approved SHA。部分发布保持 `code-approved` 并暴露 txId、sideEffects 和 recoverCommand，不自动 revert、reset 或 force。

### FR-05 merge finalize 与 authority handoff

所有参与仓确认后，crctl 在固定 knowledge-base Transaction Workspace 生成一次 finalize commit，原子包含 `cr.md` 状态、完整 merge metadata、机器生成的 `merge-verification.md` 和必要事件。origin 确认后将该 detached workspace 作为 `operational_workspace` 交给 writeback；CR worktree 只读，用户主 checkout 不参与 authority 选择。

### FR-06 release snapshot

`crctl review-record --stage code` 必须从真实已推送 ref/worktree 注入不可由模型 payload 覆盖的 `code.yml#release-subjects`：逐仓 reviewed source SHA，以及 CRLF 规范化、路径排序后的 PRD/SDD/plan/TASK 集合 digest。approve-code 重新核对 ref/HEAD/artifact，一致后原样复制到 signed `approval.yml#code.release-subjects`；漂移返回 `RELEASE_SUBJECT_DRIFT` 且零写入。merge/writeback 只消费 signed snapshot。

### FR-07 writeback candidate/apply

固定 stage 脚本只生成 candidate manifest 和 content-addressed blobs，不直接修改 baseline。`writeback-apply` 只接受 `baseline|tasks|traceability`，校验 signed snapshot、inputDigest、generator SHA、allowlist、before/after/blob hash 和精确 staged set。manifest v1 仅支持受控 create/replace，不支持 delete/rename/chmod/executable bit；origin trunk 在未发布前进时重新生成 candidate，不 rebase/cherry-pick。

### FR-08 archive 与 cleanup

`crctl archive` 是唯一归档入口，自动续跑状态转换、四账本/archive event、commit/lease push 和资源清理。archive commit 经 origin 确认后 `archived` 不回退；cleanup 失败返回 `CR_ARCHIVE_CLEANUP_PENDING`，同一命令只续跑 cleanup。成功 archived 只删除已证明合入 trunk 的 clean worktree/ref；rejected/withdrawn 保留未合并远端 ref，并输出 `preservedRefs`。删除 Skill 的 `cleanup_branch` 开关和模型生成 cleanup report。

### FR-09 安全与路径约束

删除伪造 caller 授权承诺和公开 `--caller`；所有 destructive 操作由 crctl 按 graph containment、realpath、固定 ref/路径和操作前置校验。锁使用本机原子目录 + token/pid/hostname，无 TTL/force unlock；foreign hostname 或无法证明 owner 时保守阻断。Installation Workspace 不承诺跨主机共享锁。

### FR-10 升级边界

新增临时只读 `crctl upgrade-check`，从 origin trunk 和 active repo remote refs 分类 `safe/requiresReapproval/blocksUpgrade`。没有 release snapshot 且已 partial merge/merging/writing-back 的旧 CR 阻止激活新协议；零 publish 的旧 code-approved 可回退 developing 重审。所有新协议 CR 必须有 signed snapshot。协议切换后删除 upgrade-check 及对应测试。

## 4. 非功能需求

- **可靠性**：在 rename、commit、push、finalize、cleanup 任一 fault point 强制退出后，重启必须能 confirmed、continue 或 hard block，不得静默当作成功。
- **幂等性**：重复 register/merge/writeback/archive 不重复 CR-ID、事件、metadata、commit 或 outbox；已确认阶段返回 `changed=false` 或 cleanup continuation。
- **安全性**：所有路径 workspace-relative 且受 containment；manifest 禁止绝对路径、`..`、symlink parent、任意 blob 和未声明文件。
- **可审计性**：事务 commit 带 `AI-First-Op/Tx/CR` trailer；journal 丢失时可结合 remote refs、ancestry、release snapshot 重建；冲突不得猜测。
- **兼容性**：目标账本最低版本为 `cr-backlog/v2`；v1 只返回 `UNSUPPORTED_BACKLOG_SCHEMA`。关键 fault vectors 覆盖 Windows 与 Ubuntu。
- **复杂度边界**：不引入通用 saga/phase engine/handler registry/plugin；只有至少三个真实处理器出现同一非平凡控制逻辑或相同恢复缺陷时，才评估从 `durable-tx.mjs` 提炼最小 runner，并登记 CUSTOM-TODO-008。

## 5. 验收标准

- **AC-01**：静态 contract 检查证明 Agent/Pipeline/Skill 不再拥有 Git、账本、workspace 或恢复算法；所有 active 调用通过指定 crctl 深原语。
- **AC-02**：三仓真实 bare remote 测试覆盖 prepare 冲突、第二仓 push 失败、push 后 kill、finalize stale 和重跑；结果均包含 txId、phase、sideEffects 和 recoverCommand。
- **AC-03**：同 registration key 在 CR-ID 分配、commit、push、任意第 N 个 worktree 失败后重跑，复用原 CR-ID 并只补齐缺失资源；输入变化硬失败。
- **AC-04**：真实 rename 前后 kill + restart 的 write-set 测试证明 after/before/第三值分别 redo、跳过或 `TX_RECOVERY_CONFLICT`，不会误覆盖第三方修改。
- **AC-05**：代码评审记录后、approve 前任一 ref/artifact 漂移返回 `RELEASE_SUBJECT_DRIFT`，approval.yml/cr.md 零写入；审批后的 source/TASK drift按统一回退规则处理，PRD/SDD drift返回 `APPROVED_ARTIFACT_DRIFT`。
- **AC-06**：candidate manifest 对 absolute/`..`/反斜杠/乱序重复 path、symlink、tx 外 blob、hash mismatch、delete/rename/chmod 均 hard fail 且 staged set 为空。
- **AC-07**：writeback candidate 准备后 trunk 前进时，未发布 stage 从新 detached HEAD 重新生成；已发布 commit 从远端历史消失返回 `WRITEBACK_REMOTE_HISTORY_REWRITTEN`。
- **AC-08**：archive commit 发布确认后 cleanup 失败保持 `archived`，返回 `CR_ARCHIVE_CLEANUP_PENDING`；重跑不重复账本/事件；rejected/withdrawn 未合并远端 ref 在 `preservedRefs` 中保留。
- **AC-09**：lock 测试覆盖存活进程、同机崩溃、PID 复用、foreign hostname、token mismatch；无 TTL 和 force unlock。
- **AC-10**：`upgrade-check` 零写入并正确区分 safe/requiresReapproval/blocksUpgrade；协议切换后可删除该临时命令及测试。
- **AC-11**：`lint-prompts --mode enforce`、skill/agent/pipeline contract、crctl tests、writeback tests 和 JSON parse 全部通过；CI 同时覆盖 Ubuntu/Windows 关键事务向量。
- **AC-12**：本 CR 以单一 requirement branch 交付，约 12 个 TASK 即时登记 done；不使用 feature flag、compat wrapper 或双写，本 CR 自身由旧流程完成 merge/writeback/archive。

## 6. 成功指标

- merge、register、writeback、archive 的失败现场均可由机器输出恢复命令和结构化副作用，不再依赖模型读取文本推断。
- active Pipeline/Skill 中 Git/worktree/账本算法复制为零；`crctl.mjs` 删除冗余入口和旧兼容代码后净缩短。
- 重跑成功率以真实 fault-injection matrix 衡量：所有承诺的零副作用、roll-forward、hard-block 场景均有可执行测试。
- post-merge writeback 错误 checkout 和状态/metadata 分裂提交在 contract/integration 测试中为零。

## 7. 范围排除

- 不实现跨多个 remote 的真正原子提交；只实现单仓 ref CAS 和跨仓可恢复 saga。
- 不引入数据库、队列、分布式锁、通用 saga、插件系统、第三个事务模块或新的 YAML 账本。
- 不在本 CR 中实现未来 rejected/withdrawn 远端 ref 删除管理命令。
- 不把 PRD/SDD 内容判断、LLM review、CUSTOM.md 语义判断下沉到 crctl。
- 不自动 reset/stash 用户 checkout，不删除无法证明归属的 worktree/ref。
- 不为 backlog v1 保留永久迁移兼容；旧 workspace 由旧 tools 迁移后再升级。

## crctl TASK 索引初始化与 task-breakdown 门禁闭环（vtbd · CR-2026-037）

## 1. 概述

CR-2026-032 在技术设计审批后生成 Plan/TASK 时暴露流程断点：`write-dev-tasks` 要求生成 `tasks/_index.yml`，但 tools `ARCHITECTURE.md` 将该文件定义为受控账本，禁止 Skill/Agent 手写；当前生产 `crctl task` 只有 developing 阶段的 `done` 子命令，没有首次初始化入口。与此同时，`task-breakdown` gate 只检查 `plan.md` 与 TASK 文件，会在索引缺失时错误放行，而 `review-dev-plan` 和开发启动审批又强制要求索引存在，形成“前一门放行、后一节点必失败”的半完成态。

本 CR 只补一个深原语 `crctl task init`：从 CR worktree 中已经由 `write-dev-tasks` 产生的 `TASK-NN.md` frontmatter 确定性生成/刷新 `_index.yml`，复用现有 YAML 子集解析、CAS、审计和错误出口；同时给 `task-breakdown` gate 增加索引存在性，并让 Skill/Pipeline 调用该原语。Agent 仍只路由，Pipeline 仍只编排，Skill 仍做业务拆解，账本原子写入继续唯一归 crctl。

现有基础设施与本次改造严格分离：不新建事务框架、manifest、账本脚本、YAML 依赖或状态机；不把 Plan/TASK 业务设计判断下沉到 crctl。通用 `crctl validate plan.md/TASK-*.md` 因现有 schema ID（`PLAN-v*`/`TASK-v*`）与实际 CR 文档 ID（`CR-*-plan`/`CR-*-TASK-*`）不一致，明确不在本 CR 顺手接入。

## 2. 用户故事

- **US-01 开发 Agent**：生成 TASK 内容卡后，希望只调用一个 crctl 命令物化受控索引，不手写账本 YAML。
- **US-02 开发计划评审者**：进入 `task-breakdown` 时，希望 Plan、TASK 文件和 `_index.yml` 都已存在，避免下一节点确定性失败。
- **US-03 开发负责人**：开发启动前若 TASK 被评审回修，希望可安全刷新全 pending 索引；一旦已有 done 进度，任何重建都必须拒绝，防止丢账。
- **US-04 tools 维护者**：希望复用既有 parser/CAS/audit/controlled Git，不维护第二套 task 事务、manifest 或生成器协议。
- **US-05 CR-2026-032 交付者**：流程修复合入权威 Tools Root 后，希望用正式命令恢复已提交 Plan/TASK，继续 review-dev-plan，不消费永久例外。

## 3. 功能需求

### FR-01 `crctl task init` 单一入口

新增命令：

```text
crctl task init <CR-ID> --workspace <knowledge-base CR worktree>
```

命令不得接受 TASK 列表、索引 YAML、candidate path、状态或 owner 参数。唯一业务输入是当前 CR 目录中按 `^TASK-\d+.*\.md$` 匹配的 TASK 文件；crctl 读取 frontmatter 后机械生成 `change-requests/{CR-ID}/tasks/_index.yml`。

该命令只负责索引物化，不推进 CR status、不执行人工审批、不提交 Git、不评审 TASK 内容质量。状态推进仍由后续 `crctl advance --to task-breakdown --trigger write-dev-tasks` 完成，提交仍走既有 `crctl git`。

### FR-02 TASK 集合与 frontmatter 硬校验

`task init` 必须在任何写入前完成全量校验：

- 至少一个 TASK 文件，否则 `TASK_SET_EMPTY`；
- 文件名 `TASK-NN.md`、`id={CR-ID}-TASK-NN`、`cr-ref` 与当前 CR 一致；
- `type=TASK`、非空 `title`、`status=pending`、`estimate=<正整数>h`、`depends-on` 为数组；
- TASK ID 和编号唯一；
- 每个依赖都引用本批 TASK，否则复用既有 `DEPENDS_ON_UNKNOWN`；
- 依赖图无环，否则 `TASK_DEPENDENCY_CYCLE`；
- 解析失败或字段不合法统一 `TASK_CARD_INVALID`，detail 必须带文件和字段，不得静默跳过坏卡。

命令不判断任务拆分是否合理、验收条件是否充分、接口契约是否正确；这些继续归 `write-dev-tasks` 和 `review-dev-plan`。

### FR-03 确定性索引投影

索引按 TASK 编号升序生成，固定形态：

```yaml
cr-id: CR-2026-037
tasks:
  - id: CR-2026-037-TASK-01
    title: "..."
    status: pending
    estimate: 4h
    depends-on: []
```

字段只投影 `id/title/status/estimate/depends-on`；不复制正文、slug、plan/sdd ref、文件路径、时间戳或评审结论。字符串使用现有安全标量渲染方式，输出 LF；同一 TASK 集合重复执行必须字节稳定、`changed=false`，不得产生时间漂移。

### FR-04 状态与进度保护

`task init` 仅允许：

- `tech-design-reviewed`：首次生成或 review-dev-plan 普通回修后的刷新；
- `task-breakdown`：开发启动审批前的 TASK 重拆自环刷新。

其他状态返回 `ILLEGAL_LEDGER_STATE`。若现有 `_index.yml` 任一任务已为 `done`、存在 `done-at`，或形状无法证明全部 pending，返回 `TASK_INDEX_HAS_PROGRESS`，原文件不变。不存在索引时 create；索引存在且可刷新时使用读入原始字节 SHA 做 CAS replace。

### FR-05 CAS、审计与幂等

写入必须复用 crctl 既有 `readFileChecked`、CRLF 规范化、`sha256`、`casWrite`/create-only 语义与 `auditLog`，不引入 durable transaction、WAL 或独立版本化账本脚本。

成功返回至少包含：

```json
{
  "op": "task-init",
  "cr": "CR-2026-037",
  "file": ".../tasks/_index.yml",
  "taskCount": 1,
  "totalEstimateHours": 4,
  "changed": true
}
```

失败必须零写入、零审计成功记录；同内容重放返回 `changed=false`。审计记录只含 op、CR、actor、taskCount、changed，不含 TASK 正文。

### FR-06 `task-breakdown` 门禁补齐

`gates.json#statusGates.task-breakdown` 在既有 `plan.md` 与 TASK glob 之外增加：

```text
fileExists change-requests/{cr}/tasks/_index.yml
```

缺索引时 `gate --for task-breakdown` 与 `advance` 必须失败，不得再进入下一节点。状态机与转换数量不变，不新增 gate 类型；索引内容一致性由可信生产入口和随后的 `review-dev-plan` 负责，不在本 CR 新造复杂 gate evaluator。

### FR-07 Skill 与 Pipeline 采用

`write-dev-tasks` 的职责改为：

1. 做业务拆解并写 `TASK-NN.md` 内容文件；
2. 调用 `crctl task init` 生成/刷新 `_index.yml`；
3. 校验 Plan 总估算与命令返回的 `totalEstimateHours`；
4. 调用既有 `crctl advance` 推进 `task-breakdown`；
5. 经 `crctl git` 提交。

Skill 不再指导模型手写 `_index.yml`。`code-implementation.pipeline.json` 节点只描述上述调用顺序、输入传递和失败中止，不复制 frontmatter 校验、DAG、CAS 或 YAML 渲染算法。Agent/matrix 无权限变化，README 不复制命令内部算法；`crctl/SKILL.md` 与 CLI help 只登记接口和失败语义。

### FR-08 Bootstrap 与 CR-2026-032 恢复

由于本 CR 修复的正是索引初始化入口，本 CR 自身在命令合入前没有完全合规的自举路径。允许一次性、显式的人类 bootstrap，仅用于 CR-2026-037 自身的 `_index.yml`：由人类在 Plan/TASK 已完成后审阅精确内容并提交，记录其为 `task init` 上线前的单次治理例外；不得由 Agent 写会话脚本，不得泛化到其他 CR，命令合入后例外立即失效。

CR-2026-032 不使用该例外。修复必须先合入 tools `custom/main`，再从权威 Tools Root 执行 `crctl task init CR-2026-032`、提交索引、推进 `task-breakdown` 并执行 `review-dev-plan`。禁止从 CR-2026-037 候选 worktree 隐藏调用未合入工具治理 CR-2026-032。

### FR-09 范围锁定

本 CR 不实现：

- 通用 `crctl validate plan.md/TASK-*.md`；
- PLAN/TASK engineering-doc schema ID 迁移；
- TASK 正文生成器或 LLM 业务判断；
- 新状态、转换、审批、reviewLoop 或 Agent 权限；
- durable transaction、candidate manifest、独立 task-index 脚本、第三方 YAML 库；
- developing 后的索引重建、done 状态迁移或历史任务兼容器。

## 4. 非功能需求

- **极简性**：实现留在现有 `crctl.mjs` 与 `crctl.test.mjs`，优先复用 parser/CAS/audit；无单实现 interface/factory/plugin。
- **分层**：Agent 只路由；Pipeline 只编排；Skill 做拆解判断；crctl 做机械校验与受控账本写；README 不复制算法。
- **可靠性**：任一 TASK 非法、依赖悬空/成环、状态非法、已有进度或 CAS 冲突时索引零变化。
- **幂等性**：同一 TASK 集合重复 init 字节不变、无新时间戳、`changed=false`。
- **兼容性**：`task done` 现有接口和依赖守卫不变；现有合法 `_index.yml` reader 不需迁移。
- **跨平台性**：LF/CRLF TASK frontmatter 生成同一索引；Windows 路径不得进入索引。
- **性能**：单 CR TASK 数量线性 O(n+e)，不缓存、不并发、不访问网络。
- **可测试性**：使用 Node 标准库与现有 fixture；不新增生产 fault point。

## 5. 验收标准

- **AC-01**：4 张合法 TASK 卡执行 `task init` 后生成按编号排序的 `_index.yml`，字段精确为 FR-03，返回 taskCount=4 与正确总工时。
- **AC-02**：同输入重跑返回 `changed=false`，文件字节、mtime 以外的业务内容和 audit 成功记录数量不漂移。
- **AC-03**：TASK 集合为空、frontmatter 缺失、ID/文件名/CR 不匹配、estimate 非法、depends-on 非数组均在写入前失败并给出文件/字段。
- **AC-04**：悬空依赖返回 `DEPENDS_ON_UNKNOWN`；A→B→A 与 A→A 返回 `TASK_DEPENDENCY_CYCLE`，无索引写入。
- **AC-05**：`tech-design-reviewed` 可首次创建；`task-breakdown` 且全部 pending 可刷新；`developing` 拒绝。
- **AC-06**：现有索引含 done/done-at、未知状态或损坏形状时返回 `TASK_INDEX_HAS_PROGRESS`，原字节不变。
- **AC-07**：并发修改导致 CAS 不匹配时拒绝覆盖；CRLF/LF TASK 集合生成完全相同的 LF 索引。
- **AC-08**：缺 `_index.yml` 时 `gate --for task-breakdown` 和对应 advance 失败；补齐后既有 plan/TASK gate 通过。
- **AC-09**：`write-dev-tasks` 与 Pipeline 不再含“模型直接生成 `_index.yml`”算法，而是调用 `crctl task init`；Pipeline JSON 可解析、节点数不变。
- **AC-10**：现有 `task done`、review-dev-plan、dev-start gate/approval 测试无回归；`lint-prompts --mode enforce`、Skill/Agent contract 和 crctl 测试通过。
- **AC-11**：changed-files 仅落 `crctl.mjs`、`crctl.test.mjs`、`gates.json`、`crctl/SKILL.md`、`write-dev-tasks/SKILL.md`、`code-implementation.pipeline.json`；无需修改 Multica、状态机、README 或版本化脚本。
- **AC-12**：修复合入权威 `custom/main` 后，CR-2026-032 的 4 张已提交 TASK 经正式 `task init` 生成 24h 索引，推进 `task-breakdown` 并可进入 `review-dev-plan`。

## 6. 成功指标

- `tasks/_index.yml` 从首次创建到 done 更新只有 crctl 写入，不再存在 Skill/Agent 直写路径。
- `task-breakdown` 不会在索引缺失时放行。
- TASK 回修在开发前可安全重算，开发进度出现后不可被覆盖。
- CR-2026-032 无需重写 Plan/TASK 即恢复流程。
- 本次净新增只有一个命令和一个既有 gate 条目，不产生第二事务或验证框架。

## 7. 依赖与风险

- **依赖**：现有 `matchFrontmatter`、`parseYaml`、`readFileChecked`、`sha256`、`casWrite`、`auditLog`、`resolveCrState`、`fail/ok`。
- **风险 R-01**：通用 schema 与实际 CR 文档 ID 不一致；本 CR 只验证 task init 所需字段，禁止顺手接 generic validate。
- **风险 R-02**：刷新索引覆盖 done 进度；状态白名单 + progress guard 双重拒绝。
- **风险 R-03**：Pipeline 复制算法后继续漂移；Pipeline 只保留调用顺序，算法唯一在 crctl。
- **风险 R-04**：修复 CR 自举例外被滥用；限定 CR-2026-037、限定单文件首次创建、限定人类执行并在命令合入后失效。
- **风险 R-05**：候选 crctl 被用于治理其他 CR；AC-12 明确要求先合入权威 Tools Root。

## 8. 范围排除

- 不修改 CR-2026-032 的 Archive PRD/SDD/Plan/TASK 内容。
- 不增加 `_index.yml` 的时间戳、hash、schema-version 或 source-file 字段。
- 不让 crctl判断任务标题、正文、验收标准或接口设计是否合理。
- 不修改 `task done` 的 developing-only 与一跳依赖守卫。
- 不把 task init 做成版本化脚本、Pipeline 内联 YAML 或 Agent 工具。
- 不更新 README；CLI help 与 crctl Skill 足以承载命令接口，人读总览无需复制实现细节。

## 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-13 | v0.1.0 | Ray | 初始草稿：单一 task init 深原语、索引门禁、Skill/Pipeline 采用、一次性自举边界与 CR-2026-032 恢复路径 |

## tools Archive 独立小修：cleanup 回显、正常归档 outbox、README 语义（TCA-010 收尾）（vtbd · CR-2026-032）

## 1. 概述

CR-2026-031 已将 archive 主链收敛为 `crctl archive` 单一深原语：四账本通过 recoverable write-set 同批修改，archive commit 经 lease push 发布后再清理 Transaction Workspace、CR worktree 与分支。当前剩余三个相互独立但影响可恢复性和平台实时投影的问题：cleanup 异常已写入 journal 却未返回调用者；正常 `writing-back -> archived` 归档未发出 Multica 已支持的 `archive` outbox；README 仍容易让使用者误以为归档发布和资源清理是同一个全成全败动作。

本 CR 按来源方案交付分组 A（T02）完成 ARC-03、ARC-04、ARC-05。实现复用现有 `archiveCr()`、outbox schema、Multica archive 消费链和幂等键，不新增 archive 命令、事件类型、协议版本或事务层。严格 traceability 结构门禁 ARC-02 明确留给后续 Traceability/feedback CR，在 baseline generator 能生成完整证据前不得提前启用。

## 2. 用户故事

- **US-01 CR 运维者**：当归档事实已发布但 cleanup 异常时，希望命令直接返回错误详情、剩余资源和恢复命令，以便处理现场后续跑，而不是读取内部 journal 猜测原因。
- **US-02 平台使用者**：希望正常归档完成后 Multica 及时收到合法的 `writing-back -> archived` 事件，以便 CR 状态和 feature-writeback pipeline run 不必等待周期 snapshot reconcile 才收敛。
- **US-03 tools 维护者**：希望 archive 返回结构在 complete、cleanup-pending 和幂等重放时保持固定，以便 Skill、Pipeline 和测试只消费一套字段。
- **US-04 流程维护者**：希望 README 清楚区分“终态事实已发布”和“本地资源仍待清理”，以避免使用者因 `cleanup-pending` 手工删除尚未验证安全的资源。
- **US-05 后续 traceability 交付者**：希望本次小修不提前收紧 archive traceability gate，以免当前 generator 尚未产出的 tests/reviews/approval 结构阻断正常归档。

## 3. 功能需求

### FR-01 Archive 返回契约固定化

`crctl archive` 在 `phase=complete`、`phase=cleanup-pending` 以及已完成事务的幂等重放中，必须固定返回以下字段：

- `commit`：已由 origin 确认的真实 archive commit SHA；
- `lastCleanupError`：最近一次 cleanup 异常的结构化错误码；无异常时为 `null`；
- `remaining`：仍未清理且被保守保留的资源列表；无剩余时为空数组；
- `preservedRefs`：按既有规则保留的远端 requirement ref；无保留时为空数组；
- `recoverCommand`：可直接重跑的同一 `crctl archive` 命令。

返回字段必须取自现有 archive journal/事务结果，不建立第二份状态或错误账本。`commit` 必须随远端前进后的 rebuild 更新为最终被 origin 确认的 commit，不得返回已被替代的本地候选 SHA。

### FR-02 Cleanup 异常可见且可续跑

当 cleanup 抛出异常时，`archiveCr()` 必须保留既有语义：archive commit 已发布、CR status 已是终态、命令以业务结果 `phase=cleanup-pending` 返回且不回滚 authority。返回中的 `lastCleanupError` 必须暴露 journal 已记录的错误码；`recoverCommand` 必须可用于同一事务续跑。

当 cleanup 只因 dirty、unknown、未证明已合入等保守条件留下资源，而未抛出异常时，`remaining` 必须表达现场，`lastCleanupError` 为 `null`。调用者必须能区分“有待处理资源”和“cleanup 执行本身异常”两类 pending 原因。

### FR-03 正常归档发送既有 Archive Outbox

仅当 archive 的原始状态为 `writing-back`，且 archive commit 已被 origin 确认后，`cmdArchive()` 必须复用现有 outbox schema 发送一次事件：

- `event_kind=archive`；
- `cr_id=<当前 CR-ID>`；
- `from_status=writing-back`；
- `to_status=archived`；
- `trigger=cr-archive`；
- `commit_sha=<真实、最终、已确认的 archive commit SHA>`；
- `actor` 与 `occurred_at` 继续由现有 crctl identity/time 机制生成。

不得新增 `terminal` 事件、topic、schema v2 或 archive 专用 transport。事件继续使用 Multica 现有 `(cr_id, commit_sha, event_kind)` 幂等键；相同 archive 事务幂等重放不得生成第二个 archive outbox 文件。

### FR-04 Outbox 失败不反转 Git Authority

archive outbox 是可重建投影通道，Git commit 与 `_history.yml` 才是权威事实。outbox 写入失败时：

- 不得回滚、重建或重复发布 archive commit；
- archive 命令仍返回 `phase=complete` 或 `phase=cleanup-pending`；
- 返回 `warnings[]`，其中至少包含 `code=EMIT_FAILED` 与 `event_kind=archive`；
- 后续 snapshot reconcile 继续作为最终兜底。

outbox 发送必须发生在 origin 已确认之后，禁止用未发布或占位 commit SHA 生成 archive 事件。

### FR-05 提前终止状态不得重复发 Archive 事件

当 CR 原始状态为 `rejected` 或 `withdrawn` 时，archive 只执行现有账本搬移和安全 cleanup，不发送 `archive` 或第二个 `status` outbox。对应终态转换已由 `crctl advance` 发出完整 status 事件；归档阶段不得伪造 `writing-back -> archived`，也不得产生重复终态投影。

### FR-06 Multica 既有消费契约验证

Multica 侧只允许增加契约测试和必要的 CUSTOM 台账登记，不修改生产事件协议。测试必须证明现有消费者能够接收 FR-03 的事件，并完成以下行为：

- `archive` 被识别为已知 event kind；
- 以 `writing-back -> archived`、`trigger=cr-archive` 通过既有合法转换校验；
- CR 投影状态更新为 `archived`；
- feature-writeback 的活动 pipeline run 被结束；
- 同一 `(cr_id, commit_sha, event_kind)` 重放保持幂等。

若 Multica 生产代码无需修改，不得为测试方便新增 archive 分支或兼容层。任何 Multica 测试文件改动必须按该仓当时实际 `CUSTOM.md` 结构登记 CR-2026-032/TASK 追溯。

### FR-07 README 语义澄清

`../tools/README.md` 的 feature-writeback/archive 说明必须明确：

1. `archive` 先发布终态权威事实，再尝试安全清理本地和远端资源；
2. `cleanup-pending` 表示 status 已是终态，未完成的仅是资源清理；
3. 处理返回的 `remaining` / `lastCleanupError` 后，只能重跑同一 `recoverCommand`；
4. 不得手工删除 dirty、unknown、未证明已合入或被列入 `preservedRefs` 的资源。

README 只描述上述业务语义，不复制 worktree/ref 分类、ancestry 判断、lease push、journal phase 或 cleanup 算法。

### FR-08 范围与依赖锁定

本 CR 只实现来源方案的 ARC-03、ARC-04、ARC-05 和 T02。ARC-02 严格 traceability gate 必须保持现状：archive 仍只检查当前既有前置，不要求尚未由 baseline generator 生成的 tests/reviews/approval milestone 结构。后续只有在 TRA-03 generator 增强完成并以真实产物通过集成测试后，才能由独立 T10A/Traceability CR 启用严格 gate。

## 4. 非功能需求

- **幂等性**：同一 archive 事务首次成功可产生至多一个 `archive` outbox；幂等重放不得产生新 commit、事件或时间戳漂移。
- **可靠性**：archive authority 一经 origin 确认不得因 cleanup 或 outbox 失败回退；所有 pending 结果必须带真实 commit 与可执行恢复命令。
- **兼容性**：保持现有 `event_kind=archive` schema、Multica consumer、状态机和 `(cr_id, commit_sha, event_kind)` 幂等键；不要求数据库迁移。
- **可观测性**：cleanup 异常通过 `lastCleanupError` 返回，资源保留通过 `remaining/preservedRefs` 返回，投影通道失败通过 `warnings[]` 返回。
- **安全性**：继续遵守 clean 才删、unknown/dirty/未合入则保留的既有 cleanup 规则；本 CR 不放宽任何删除条件。
- **可测试性**：测试必须覆盖真实 archive commit SHA、cleanup fault、dirty pending、outbox 失败、正常归档发送、提前终止不发送和幂等重放。
- **复杂度边界**：复用现有 `emitOutboxEvent()`、archive journal 与事务模块；不新增依赖、通用事件发布器、第二套 archive 状态机或新事务模块。
- **跨平台性**：tools 的 archive/crctl 测试保持 Windows 与 Ubuntu CI 可运行；涉及文本读取继续按仓库规则规范化 CRLF。

## 5. 验收标准

- **AC-01**：正常归档首次执行返回 `phase=complete` 时，同时包含 `commit`、`lastCleanupError=null`、`remaining=[]`、`preservedRefs=[]` 和可执行 `recoverCommand`；返回的 `commit` 等于 origin trunk 中带 `AI-First-Op: archive` trailer 的真实 SHA。
- **AC-02**：注入 `archive-during-cleanup` fault 后，命令返回 `phase=cleanup-pending`、`status=archived`、非空 `lastCleanupError`、真实 `commit` 与 `recoverCommand`；重跑后只续 cleanup，不新增 archive commit。
- **AC-03**：制造 dirty CR worktree 时，命令返回 `cleanup-pending`，对应资源出现在 `remaining`，`lastCleanupError=null` 且现场未被删除；清理 dirty 内容后重跑可完成。
- **AC-04**：正常 `writing-back -> archived` 归档在 origin 确认后产生一个 outbox JSON，字段精确满足 FR-03，`commit_sha` 等于最终 archive commit SHA；同事务重跑 outbox 文件数量不增加。
- **AC-05**：模拟 outbox 写入失败时，origin archive commit 与四账本终态保持已发布，命令结果含 `warnings[{code: EMIT_FAILED, event_kind: archive}]`，且不新增补偿 commit。
- **AC-06**：`rejected` 与 `withdrawn` 归档均不产生 `event_kind=archive` 或第二个终态 status 事件，现有 `preservedRefs` 行为不变。
- **AC-07**：Multica 契约测试使用 FR-03 事件证明 CR 由 `writing-back` 投影为 `archived`，feature-writeback run 被结束；同一幂等键重复上报只处理一次。
- **AC-08**：README 明确“终态发布成功、cleanup 可 pending、处理后重跑同命令”，且未复制 cleanup 分类算法或建议手工删资源。
- **AC-09**：archive 前置仍未启用 ARC-02 严格 traceability 结构校验；仅有当前合法 traceability 文件的既有 fixture 和可归档 CR 不因本次改动被阻断。
- **AC-10**：现有 archive、crctl、Multica governance/daemon 相关测试不通过放宽断言获得绿灯；tools 的 `lint-prompts --mode enforce`、Skill/Agent contract、Pipeline JSON parse 和相关测试全部通过。
- **AC-11**：若 Multica 仅增加契约测试，则其 production code diff 为空；所有 Multica 改动按 `CUSTOM.md` 当前表格登记 CR-2026-032 与对应 TASK。

## 6. 成功指标

- 所有 `cleanup-pending` 结果都能仅凭命令 JSON 判断是资源保留还是 cleanup 异常，并获得同一事务恢复命令。
- 正常归档不再依赖周期 snapshot reconcile 才在 Multica 中显示 `archived`；archive outbox 可直接结束 feature-writeback pipeline run。
- archive/outbox/cleanup 任一失败路径均不产生重复 commit、重复终态事件或 authority 回退。
- README 中不再存在将 archive 发布与 cleanup 描述为单一全成全败动作的表述。
- 当前可归档 CR 的通过率不因尚未交付的严格 traceability schema 而下降。

## 7. 依赖与风险

- **依赖**：tools 当前 `archiveCr()` durable transaction、`emitOutboxEvent()` schema v1、Multica `knownEventKinds/archive -> applyStatus` 消费链、状态机合法转换 `writing-back -> archived`。
- **风险 R-01**：若 outbox 在 cleanup 后才发送，knowledge-base worktree 可能已删除。实现必须从 archive 事务结果和 installation workspace 发事件，不依赖已清理的 CR worktree。
- **风险 R-02**：若只用 `changed=true` 判断是否发事件，cleanup-pending 续跑可能重复发送。实现必须依据原始 archive 状态和持久化发送结果/确定性文件名保证首次发布后至多一次。
- **风险 R-03**：远端前进导致 archive commit rebuild 时，事件必须使用最终 confirmed SHA，否则 Multica 幂等账本会记录无权威对应的旧 SHA。
- **风险 R-04**：commit fallback 当前 archive subject 不匹配既有 `[cr] archive ...` 正则。本 CR 的正确路径是显式 outbox，不以改 commit subject 或依赖 fallback 代替 FR-03。
- **风险 R-05**：Multica 数据库测试在数据库不可达时可能整包 skip。契约测试结果必须确认目标测试真实执行，不得仅凭 `go test` exit 0 判定通过。

## 8. 范围排除

- 不实施 ARC-02，不校验 baseline traceability 当前 CR milestone、tests、reviews、approval 或 merge 的完整结构。
- 不修改 `writeback-traceability.mjs`、feedback、alignment、checkpoint 或 test record 链路。
- 不新增 `terminal`/`feedback` outbox、消息队列、topic、schema 版本、数据库迁移或新消费者。
- 不修改 rejected/withdrawn 的终态转换和既有 status outbox；不为其发送 archive 事件。
- 不改变 archive 四账本内容、commit trailer、lease push、远端 rebuild、clean/dirty/unknown 分类或 ref 保留规则。
- 不把 outbox 失败升级为 archive 失败，不自动回滚、revert 或重新打开 CR。
- 不重构 `crctl.mjs` 为通用事件发布框架，不新增 interface/factory/plugin。

## 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-13 | v0.1.0 | Ray | 初始草稿：冻结 ARC-03/04/05、T02 范围与验收，明确排除 ARC-02 |

## tools Checkpoint 收敛：单一深原语 + latest-checkpoint + 多仓恢复（TCA-011）（vtbd · CR-2026-033）

## 1. 概述

当前 checkpoint 由 `push-progress` Skill 手写完整逐仓 Git 算法（worktree 遍历、`add -A`、diff、commit、push、`rev-parse`、逐仓失败处理），同一算法还被四个 Pipeline prompt 复制；`crctl checkpoint-add` 每次只 CAS 一次并追加单个 repo，没有 batch-id、manifest、journal 或 commit——第 N 仓写失败会留下同一轮的半记录，resume 无法区分"完整 checkpoint"与"半记录"；旧 `checkpoints[]` 无限追加，消费者取首条/末条结论不一；knowledge-base checkpoint 元数据天然"晚一轮"（先 push 分支再改 backlog，本轮元数据不进入刚推送的 remote HEAD），换机恢复只能看到上一轮记录；多仓 push 没有持久化恢复状态，通用"已发布"分类不足以证明 checkpoint freshness。这是 TCA-011 的未解决核心。

本 CR 按《tools-archive-checkpoint-test-traceability-optimization-plan.md》§12 交付分组 B（T03~T05）落地，覆盖 §4.2 CKP-01~07：

- **单一深原语**：新增幂等 `crctl checkpoint`（不新增 `checkpoint status`），`checkpointCr()` 独占全仓 Git、账本与恢复算法；成功/失败输出固定结构化字段（§5.1）。
- **单一当前快照**：`_backlog.yml` 中每 CR 只保留一个整块可原子替换的 `latest-checkpoint`，batch-id 内容寻址（排除 message/actor/时间）；首次成功时同批删除旧 `checkpoints[]` 与顶层 `remote-ref/last-push-*`。
- **敏感文件预检**：`add -A` 前按固定路径规则 + 私钥头内容规则拦截，命中整批零 commit/零 push。
- **多仓可恢复 saga 与 exact-head freshness**：durable journal 增加 `op=checkpoint` 逐仓记录；生成 metadata 前按 remote 与 source SHA 的精确关系分类；KB 用"本轮恢复 HEAD + metadata commit"解决晚一轮，`source-sha` 固定为 metadata commit 的直接父提交。
- **迁移与删除**：push-progress 收缩为一次调用；四条 Pipeline 的 checkpoint 节点只保留输入/跳过/输出/onFail；list-remote-checkpoints 与 resume reader 改读 `latest-checkpoint` 与 exact-head drift；删除 `checkpoint-add`。

**依赖与顺序**：复用 CR-2026-031 交付的 durable-tx/workspace-transactions 基础设施；按总路线图 A→B 顺序，需 CR-2026-032（Archive 小修）先行完成；本 CR 内部按 T03 → T04 → T05 顺序实施，T01（schema/错误码/fault point 红测）先行，每个 TASK 一个可回滚提交。本 CR 实施期自身在 T05 迁移完成前仍使用旧 checkpoint 流程保存进度（与 CR-2026-031 自用旧流程同理）；T05 完成 caller/reader 迁移并删除 checkpoint-add 即完成切换，不安排独立切换步骤。

## 2. 用户故事

- **US-01 换机/协作接续者**：希望在任意一台机器恢复 CR 时，看到与远端完全一致的最新进度（含本轮元数据），不再"晚一轮"。
- **US-02 同步意图发起者**：希望保存进度只有一条命令、一个语义，中断后重跑同一条命令自动续跑补齐，不重复提交、不留半 repo 投影。
- **US-03 Skill/Pipeline 作者**：希望只声明"调用一次 `crctl checkpoint`"，不再复制逐仓 Git 算法与恢复分类。
- **US-04 安全负责人**：希望 `.env`、私钥等敏感文件在任何 `add/commit/push` 之前被整批拦截，且没有绕过开关。
- **US-05 远端只读查询者**：希望远端列表如实标记任一仓的 drift（超前/分叉），不把"仍是祖先"当作 synced。

## 3. 功能需求

### FR-01 单一 checkpoint 深原语与输出契约

`crctl checkpoint <cr_id> [--message <text>] --workspace <ws>` 是唯一 checkpoint 写入入口；正常执行、中断续跑与幂等重放均调用同一命令。输入只含 CR 与人类可读 message；repo/branch/worktree/trunk/remote/batch-id/actor/时间全部内部派生。状态合法性守卫沿用 crctl 现有非终态语义，status 只读 `cr.md`。成功输出固定字段：`op/cr/txId/batchId/phase=complete/repositories[{repo,sourceSha,remoteRef,confirmed}]/metadataCommit/changed/recoverCommand`；失败输出 `txId/phase/sideEffects/recoverCommand`（零副作用错误可省 sideEffects）。不新增 `checkpoint status` 子命令，durable journal 不成为公共查询模型，只读查询继续由 `list-remote-checkpoints` 承担。checkpoint 只在 resolver 确认的当前 CR worktree 与 `requirement/{cr_id}` 分支运行，保留"保存全部未忽略变化"语义：每仓 commit 前纳入 tracked/untracked 的全部未忽略变化；不提供 `--files`、include/exclude glob、staged-only 或 checkpoint ignore 配置。

### FR-02 敏感文件与私钥预检（零副作用）

在 `add -A` 前，crctl 从 Git 状态取得本轮新增/修改的普通文件路径，先按 workspace-relative POSIX 路径执行固定规则，再只对命中文件检查私钥头；命中则在尚未修改 index 时返回 `CHECKPOINT_SENSITIVE_PATH`，整个 checkpoint 零 commit/零 push。固定路径规则：basename `.env`、`.env.*`（明确放行 `.env.example`、`.env.sample`、`.env.template`），basename `id_rsa|id_dsa|id_ecdsa|id_ed25519`，以及任意层级后缀 `.aws/credentials`、`.config/gcloud/application_default_credentials.json`、`.netrc`、`.pypirc`；路径比较按 Git 路径大小写精确语义，不做平台相关模糊匹配。内容规则仅匹配 `-----BEGIN ... PRIVATE KEY-----`。不拦截所有 `*.pem/*.key`，不识别通用 TOKEN/PASSWORD，不做熵扫描，不引入 gitleaks/trufflehog，不提供 `--allow-sensitive` 或例外配置。`.gitignore` 仍是项目特定临时文件与本地配置的第一道边界。

### FR-03 latest-checkpoint 单一当前快照与内容寻址 batch-id

`_backlog.yml` 每 CR 条目只保留一个可原子整块替换的当前快照：

```yaml
latest-checkpoint:
  batch-id: <sha256(cr-id + repository-graph-digest + 按 repo id 排序的 repo/source-sha/remote-ref) 前 16 位>
  repositories:
    - repo: <id>
      source-sha: <本轮内容 commit>
      remote-ref: refs/heads/requirement/<cr>
```

batch-id 是内容寻址标识，只由 cr-id、事务启动时的 repository graph digest、按 repo id 排序后的 `repo/source-sha/remote-ref` 组成，明确排除 message、actor、时间、本地路径与 journal txId；不持久化 `pushed-at/by/summary`（可从 metadata commit 推导）。每次整块替换、不追加，reader 只消费该映射；历史查询走 Git log，事务中间态只读 journal。首次成功执行新命令时，以本轮真实 repo source SHA 生成该映射，并在同一 metadata commit 删除旧 `checkpoints[]`、顶层 `remote-ref`、`last-push-at`、`last-push-by`；不迁移、不归组旧数据，不永久双读、不维护兼容投影，无 `CHECKPOINT_LEGACY_AMBIGUOUS` 迁移分支。

### FR-04 幂等 no-op 快速确认与 KB metadata commit

1. 创建任何 journal/source/metadata commit 前先执行 no-op 快速确认：读取现有 `latest-checkpoint`，fetch 全部参与仓，核对 graph digest、远端 freshness 与本地未忽略变化；全部未变时直接返回现有 checkpoint、`changed=false`，不创建 journal、不更新时间、不 push。
2. 相同 graph 与 source facts 重跑必须 `changed=false`，即使 message 不同也不得产生新 metadata commit；任一 repo source SHA 或参与仓图变化时才形成新 batch-id。
3. 有真实变化时：各 repo 先形成并确认本轮恢复 HEAD，有业务变化的仓创建 source commit、clean 仓沿用当前 HEAD；非 knowledge-base repo 先发布并精确确认 remote HEAD；knowledge-base 在自己的本轮恢复 HEAD 之上生成**只含 checkpoint 账本**的 metadata commit；最后发布 KB metadata commit。
4. `latest-checkpoint.repositories` 中 KB `source-sha` 固定为 metadata commit 的**直接父提交**，表示"本轮 metadata 创建前已确认的 KB 恢复 HEAD"，不要求一定是纯业务内容 commit；避免 commit 内容引用自身 SHA，也避免把上一轮 metadata HEAD 误当作新业务变化导致 `M1 → M2 → M3` 空转。

### FR-05 exact-head freshness 与可恢复 saga

durable journal 增加 `op=checkpoint`，逐仓记录 `prepared → committed-local → pushed → confirmed`，最后记录 `metadata-committed → metadata-pushed → complete`；重跑按 journal 补齐副作用，不做补偿 revert、不改写历史。不修改共享 `classifyRemoteCommit()` 对其他事务的既有语义；checkpoint 在生成 metadata 前使用 exact-head freshness 分类：

- remote == source SHA → confirmed；
- remote 是 source SHA 的祖先 → 本地 source 按当前 remote SHA 做 lease fast-forward publish，push 后必须再确认精确相等；
- source SHA 是 remote 的祖先且不相等 → `CHECKPOINT_REMOTE_ADVANCED`，不写 metadata，提示先走 `pull-progress` 后重新 checkpoint；
- 双方分叉 → `CHECKPOINT_REMOTE_DIVERGED`，不自动 merge、不 force；
- journal 已记录发布但 remote 不再包含 source → `CHECKPOINT_REMOTE_HISTORY_REWRITTEN`。

完整 checkpoint 的可见性点为 KB metadata commit 被 origin confirmed；在此之前其他 repo 的 source commit 只是"已发布资源"，不是完整批次。最终条件：非 KB repo 的 remote HEAD 精确等于 source SHA；KB 的 remote HEAD 精确等于 metadata commit，且记录的 source SHA 为其直接父提交——不得把"任意祖先"解释为当前完整状态。

### FR-06 Pipeline checkpoint 节点收敛

`requirement-authoring.pipeline.json` checkpoint 节点、`architecture-design.pipeline.json` checkpoint 节点、`code-implementation.pipeline.json` 的任务/代码/审批三个 checkpoint 节点、`resume-cr.pipeline.json` 远端比对节点，每个节点只保留输入、是否跳过、输出字段与 onFail：执行 push-progress（`cr_id`、message=阶段摘要），消费输出 `batchId/repositories/phase`，非 complete 按 Skill 失败语义中止。具体 Git 命令、账本字段和恢复分类只存在于 crctl/Skill，Pipeline prompt 不得出现。

### FR-07 push-progress 收缩与 list/resume reader 迁移

- `push-progress` Skill 收缩为一次 `crctl checkpoint {cr_id} [--message ...]` 调用与结果分类；删除手写的 worktree 遍历、`add -A`、diff、commit、push、`rev-parse` 与逐仓失败处理。
- `list-remote-checkpoints` Skill：状态只读 `cr.md`（删除"缺 status 时回退 backlog"的兼容承诺）；checkpoint 只读单个 `latest-checkpoint`；非 KB repo 要求 remote HEAD 与 source SHA 精确相等，KB 要求 remote HEAD 等于 metadata commit 且记录的 source SHA 是其直接父提交；任一仓远端超前或分叉均标记 drift，不把"仍是祖先"当作 synced。
- `resume-from-remote` 只消费 metadata-confirmed 的 `latest-checkpoint` 恢复，不读取旧 `checkpoints[]`。
- README 的 checkpoint 说明更新为"一次保存全部 active repo"的阶段说明与失败语义概览，不复制深原语算法。

### FR-08 旧入口删除与一次性切换

删除 `checkpoint-add` 的 dispatch、help、测试与文案（T05 完成后 `crctl` 不再暴露该命令）。reader 随命令切换一次性改读新字段，不永久双读；如存在过渡兼容代码，必须带删除条件与测试，不允许"先留着以后再说"。旧 checkpoint 历史仍可从 Git 查询。

### FR-09 测试先行与交付结构

- 冻结 `latest-checkpoint` schema、错误码与 fault point 后先写旧实现下失败的测试（T01 红测）；现有 253 个 crctl tests 与 10 个 writeback tests 绿基线不得靠放宽断言"假绿"。
- 实施顺序 T03（checkpoint journal 与 `latest-checkpoint` 整块编辑纯函数，durable-tx/workspace-transactions）→ T04（checkpoint 多仓 publish/recover，crctl 与 checkpoint tests）→ T05（Skill/Pipeline/README 迁移并删 checkpoint-add）；每个 TASK 一个可回滚提交，先测试、再实现、再删旧入口。
- 三 bare remote 测试矩阵覆盖：CR worktree/branch 不匹配与敏感路径命中在任何 `add/commit/push` 前零副作用失败；同一 `latest-checkpoint` 且 graph/remote/local 全未变的重跑在创建 journal 前 `changed=false`；全成功（含 clean repo）；第二仓 push 后 kill/restart；push 响应丢失；remote fast-forward lease publish 并最终精确相等；remote advanced；remote diverged；KB metadata commit/push 失败；同批重放零新 commit；CRLF backlog 与 Windows path。

## 4. 非功能需求

- **可靠性**：任一 rename/commit/push fault 后，要么零 authority 写入，要么返回 txId + 可执行 recoverCommand；重跑自动续跑，不静默当作成功。
- **原子性**：`latest-checkpoint` 整块替换走 recoverable write-set（读入 LF 规范化解析、before hash 按磁盘原字节、任一 schema/第三值/CAS 冲突零写）；敏感命中与 preflight 失败零 commit/零 push。
- **幂等性**：相同 graph 与 source facts 重跑 `changed=false`、零新 commit、零新 journal。
- **安全性**：固定敏感路径与私钥头预检在任何 index 修改前执行；不新增 secret scanner 依赖与绕过开关。
- **可审计性**：KB metadata commit 只含 checkpoint 账本；journal 记录全部副作用；commit trailer 支持 journal 丢失后的恢复判定。
- **兼容性**：关键 fault vectors 覆盖 Windows 与 Ubuntu；CRLF 规范化（解析用 `split(/\r?\n/)`、跨行解析失败硬失败）保证 Windows autocrlf 检出内容可稳定解析。
- **复杂度边界**：不新增 npm 依赖；不建通用 saga/phase runner、checkpoint 历史账本、status API、文件选择器；只有至少三个真实处理器出现同一非平凡重复或同一恢复缺陷需三处修复时，才允许从调用点向既有 `durable-tx.mjs` 提炼最小公共函数。

## 5. 验收标准

- **AC-01（FR-01）**：`crctl checkpoint` 成功输出包含 `op/cr/txId/batchId/phase=complete/repositories[].confirmed=true/metadataCommit/changed/recoverCommand` 全部固定字段；help 无 `checkpoint status` 入口。
- **AC-02（FR-02）**：预置 `.env` / `id_rsa` / 含 `-----BEGIN ... PRIVATE KEY-----` 头的文件后运行 checkpoint，返回 `CHECKPOINT_SENSITIVE_PATH`，三仓 index/commit/push 全部为零；`.env.example` 正常放行。
- **AC-03（FR-03）**：首次新 checkpoint 成功后，`_backlog.yml` 条目不含 `checkpoints[]`/`remote-ref`/`last-push-*`，`latest-checkpoint.batch-id` 等于规定内容寻址值；相同 facts 重跑 batch-id 不变，仅 message 不同也不变；任一 repo source SHA 或 repository graph digest 变化时生成新 batch-id。
- **AC-04（FR-04）**：全仓未变的重跑在创建 journal 前返回 `changed=false`，journal 无新条目；有真实变化时 KB `source-sha` 等于 metadata commit 的直接父提交。
- **AC-05（FR-05）**：fault matrix 覆盖第二仓 push 后 kill/restart（重跑补齐且同批零新 commit）、push 响应丢失、`CHECKPOINT_REMOTE_ADVANCED`（零 metadata 写入）、`CHECKPOINT_REMOTE_DIVERGED`（不 merge/force）、`CHECKPOINT_REMOTE_HISTORY_REWRITTEN`（硬阻断）。
- **AC-06（FR-05）**：lease fast-forward 场景 push 后 remote HEAD 精确等于 source SHA；KB 场景 remote HEAD 等于 metadata commit 且 source SHA 为其直接父提交。
- **AC-07（FR-06）**：静态 contract/lint 检查证明四个 Pipeline 的 checkpoint 节点 prompt 不含任何 Git 命令与账本字段描述。
- **AC-08（FR-07）**：`list-remote-checkpoints` 对超前/分叉仓输出 drift；`cr.md` 缺 status 时不再回退 backlog；resume 只消费 `latest-checkpoint`。
- **AC-09（FR-08）**：T05 完成后 crctl/Skill/Pipeline/README 无 `checkpoint-add` 残留。
- **AC-10（FR-09）**：新增红测在旧实现下按预期红、现有 253+10 绿基线仍绿；Ubuntu/Windows CI 全绿；T03/T04/T05 各为可回滚提交。
- **AC-11（FR-01）**：对每个 active repo 预置 tracked 修改、untracked 未忽略文件与 ignored 文件后执行 checkpoint，成功后的 source commit 包含前两类全部变化且不含 ignored 文件；clean 仓沿用当前 HEAD。

## 6. 成功指标

- 任意时刻只有 metadata-confirmed 的单个 `latest-checkpoint` 被 resume/list 消费；不存在半 repo 投影、"元数据晚一轮"或账本内历史批次数组。
- active Pipeline/Skill 中逐仓 Git 算法复制为零；`crctl.mjs` 因删除 checkpoint-add 与旧兼容代码净缩短。
- 重跑成功率以真实 fault-injection matrix 衡量：所有承诺的零副作用、roll-forward、hard-block 场景均有可执行测试。
- 换机恢复端到端演示：一台机器 checkpoint 后，另一台机器 resume 得到与远端精确一致的最新进度。

## 7. 范围排除

- 不实施总路线图 T06~T16（test 原子记录、traceability/feedback、静态治理收尾属后续交付 CR C/D/E）。
- 不新增 `checkpoint status` 子命令、checkpoint 历史账本数组、文件选择器、include/exclude 配置与 `--allow-sensitive`。
- 不迁移、不归组旧 `checkpoints[]`；不建兼容投影、不永久双读。
- 失败不自动 merge、不 force push、不补偿 revert。
- 不引入数据库、消息队列、分布式锁、2PC、secret scanner 或任何新 npm 依赖；不建通用 saga/phase engine、provider、registry、plugin。
- 不把 durable journal 开放为公共查询模型。

## tools CR 生命周期最小优化 1/5 — Writeback 原子化（vtbd · CR-2026-038）

## 1. 概述

### 1.1 背景

Tools 包已具备 candidate-only generator、`crctl writeback-apply`、durable transaction、状态门禁、跨仓 merge 和 archive 等基础能力，但 writeback 的组合边界仍未闭合：baseline 文件发布与 `merging -> writing-back` 状态推进由两个独立命令完成；manifest 的完整只读校验晚于事务 journal 创建；merge prepare 对全局 `_backlog.yml` 缺少只替换目标 CR 条目的语义合并；candidate 目录仍由 Skill/Pipeline 调用方选择并通过参数向下传递。

这些缺口会造成四类真实风险：

1. baseline 已发布但状态未进入 `writing-back`，后续阶段从 origin 恢复时丢失状态事实。
2. 非法 manifest 已创建 journal，修正输入后因事务输入摘要变化而阻断合法重试。
3. CR 分支中的 `_backlog.yml` 与持续前进的 trunk 发生无业务意义的整文件冲突，或覆盖其他 CR 条目。
4. 调用方掌握 candidate 路径、generator 路径和 manifest 位置，导致深原语边界外泄并产生路径漂移。

本 CR 落实来源规格 FR-01、FR-02、FR-03、FR-10，只修复上述 writeback 原子边界，不重建事务框架、状态机、账本模型或通用 generator 平台。

### 1.2 事实基线

- 权威来源：`docs/analysis/tools-cr-lifecycle-minimal-optimization-spec.md`。
- 来源文档声明的核对基线为 `tools@origin/custom/main`，commit `7b73204464e136b83d4377ba1447a11c2291e6c6`；本次撰写前已通过受控 Git 读取确认该远端引用仍指向此 SHA。
- 当前 CR 的 tools worktree 从本地 `custom/main@c790b7ea778863c4e95b9e94fd01a7840c1691a9` 派生。对该 worktree 的代码检索仍确认：feature-writeback Pipeline 独立调用 baseline `writeback-apply` 与 `advance writing-back`；`writeback-apply` 仍要求 `--candidate`；三个 generator 仍暴露 `--candidate-out`。因此本地提交差异不改变本 CR 的问题结论与范围。
- 状态机、门禁、仓库图和受控写入分别以 Tools `dir-graph.yaml`、`skills/shared/crctl/gates.json`、工作区 `dir-graph.yaml` 和 `skills/shared/crctl/` 当前实现为准，本 PRD 不复制第二套声明。

### 1.3 目标

- baseline 文件、`merging -> writing-back` 状态、提交和远端发布形成一个可恢复的权威事务边界。
- 所有可在零副作用条件下完成的 writeback 校验都发生在 lock/journal 之前。
- merge prepare 只把目标 CR 的 backlog 条目合入最新 trunk，完整保留其他 CR 条目和未知内容。
- candidate 生成位置与固定 generator 选择由 `crctl` 内部拥有，生产调用方不再传递内部路径。
- 所有失败均可使用同一业务命令重试或按结构化错误修复，不需要手改账本、journal 或 baseline。

### 1.4 解决方案摘要

在现有 `crctl writeback-apply` 深原语内完成最小深化：将 baseline 固定状态变更纳入同一 recoverable write-set；把 generator 执行与 manifest 全量预检前移到事务创建之前；在 merge prepare 中复用现有 YAML block matcher 定向替换目标 CR 条目；把 candidate 根目录固定为 operational workspace 内部路径。Pipeline 与 Skill 只保留业务输入、一次深原语调用、结果分类和后续路由。

## 2. 用户故事

- **US-01 回写执行者**：希望执行一次 baseline writeback 后，baseline 内容和 `writing-back` 状态同时成为远端权威事实，以便后续 tasks/traceability 回写不会从旧状态恢复。
- **US-02 故障恢复执行者**：希望非法 manifest 或门禁失败不创建事务中间态，以便修正业务输入后直接重跑同一命令。
- **US-03 并行 CR 维护者**：希望 merge 当前 CR 时保留 trunk 上其他新注册 CR 的条目、顺序、注释和未知字段，以便并行注册不制造冲突或数据丢失。
- **US-04 Skill/Pipeline 作者**：希望只提供 `cr_id`、`stage`、`spec_id` 等业务输入，不需要选择 generator、candidate 目录或 manifest 路径。
- **US-05 审计与运维人员**：希望状态事件和成功审计只引用 origin 已确认的真实 commit SHA，投影发送失败可单独补发且不反转 Git 权威事实。
- **US-06 Tools 维护者**：希望实现复用现有 durable transaction、gate、YAML matcher、Git adapter 和测试 fixture，不引入第二套事务或插件框架。

## 3. 功能需求

### FR-01 Baseline 回写与状态同批发布

1. `writeback-apply --stage baseline` 必须在 candidate、目标矩阵、origin 和状态门禁全部通过后，把以下内容放入同一 recoverable write-set、同一 commit 和同一次 lease push：
   - manifest 声明的 baseline PRD/SDD 与索引文件；
   - operational workspace 中 `change-requests/{CR-ID}/cr.md` 的 `merging -> writing-back` 状态变更及受控更新时间。
2. 状态转换必须继续读取权威状态机和 `gates.json`，不得在 writeback 内复制转换表或另建专用状态机。
3. 仅 `fileExists` gate 可以接收 planned-existing 路径集合；该集合必须精确来自已通过 schema、stage、CR、spec-id、containment、allowlist、before/after hash、generator hash 和目标矩阵校验的 manifest。其他 gate 类型必须只读取当前 authority，不得读取虚拟文件内容。
4. feature-writeback Pipeline 和 `writeback-prd-sdd` Skill 不得再在 baseline writeback 成功后独立调用 `crctl advance --embedded`。
5. 该复合行为只适用于 `stage=baseline` 的固定 `merging -> writing-back` 转换，不得扩展为调用方可指定任意状态或 trigger 的复合接口。
6. 只有 origin 已确认包含真实 write-set commit 后，才允许：
   - 发送一次 status outbox，commit SHA 必须为真实远端已确认 SHA，不得使用 `pending:` 占位；
   - 写入一次 `kind: advance` success audit；
   - 在既有 writeback journal 标记 `outboxEmitted` 与 `auditEmitted`。
7. outbox 或审计发送失败不得回滚已确认的 Git 权威事实；命令返回明确 warning。重放只能补发缺失投影，不得新增 commit、重复 push 或重复已成功投影。
8. 已完成事务的幂等重放必须返回成功与 `changed=false`，并保持远端 commit、状态事件和审计各自唯一。

### FR-02 Writeback 只读预检与零副作用失败

1. 生产入口不得接受调用方提供 candidate manifest、generator 路径或 candidate 输出目录。`crctl` 必须依据固定 stage 和当前 Tools Root 选择唯一版本化 generator 并在内部生成 candidate。
2. 在获取 writeback lock 或创建 durable journal 之前，必须依次完成以下只读/可丢弃步骤：
   - 业务参数、CR 状态与 spec-id 校验；
   - 固定 generator 执行；
   - candidate 文件及 manifest JSON 读取；
   - manifest schema、stage、CR、spec-id、路径 containment、symlink parent、allowlist、文件 hash、before 磁盘锚点、generator hash、input digest 和目标矩阵校验；
   - baseline 状态门禁校验。
3. manifest 必须只读入一次，读入后先执行 `CRLF -> LF` 规范化；事务使用同一份文本及其 digest，不得在预检和持久化阶段二次读取产生 TOCTOU 语义漂移。
4. 任一预检失败必须满足零 authority 副作用：不创建 durable journal，不遗留 lock，不修改目标文件，不产生 commit/push，不发送 outbox 或 success audit。
5. candidate 是 operational workspace 内可丢弃的派生物，不是 authority。修正业务源文件或固定 generator 后重跑同一业务命令，不得因上一次非法输入产生 `TX_INPUT_CONFLICT`。
6. 预检通过后若 origin 在发布前前进，继续沿用现有 stale/rebuild 语义：Transaction Workspace 回到新 origin，重新生成 candidate 后重试；不得 rebase/cherry-pick 未发布 candidate。

### FR-03 `_backlog.yml` 目标 CR 条目语义合并

1. merge prepare 必须以最新 trunk 的完整 `change-requests/_backlog.yml` 为基底。
2. 从已验证的 CR source tree 中提取目标 CR 的完整 backlog 条目，并复用现有 YAML block matcher 在 trunk 文本中定向替换同 ID 的唯一条目。
3. 合并结果必须逐字保留 trunk 中所有其他 CR 条目及其顺序、注释、空行、未知字段和未来兼容字段。
4. 目标 CR source 条目中的 `owners`、`latest-checkpoint` 及其他现有 v2 注册索引字段必须完整保留。
5. CR status 的唯一权威仍为 `change-requests/{CR-ID}/cr.md`。语义合并不得从 `_backlog.yml` 读取、推导、重建或回填 status，也不得为历史残留 status 增加新的兼容分支。
6. trunk 或 source 中目标条目缺失、重复或无法唯一解析时必须在 prepare 阶段硬失败，且零远端发布；不得按行号、模糊字符串或整文件取舍猜测结果。
7. 实现不得引入新的通用 YAML parser 或 YAML patch 框架；必须使用现有 block matcher 并为目标条目替换提炼最小纯函数。

### FR-04 Candidate 内部路径与固定 generator 约定

1. baseline、tasks、traceability 三个生产 writeback stage 的 candidate 必须统一生成到：

   ```text
   {operational_workspace}/.crctl/candidates/{CR-ID}/{stage}
   ```

2. candidate 根目录必须位于 resolver 确认的 operational workspace 内；真实路径解析后不得越界，不得经过 symlink parent 指向外部路径。
3. `.crctl/candidates/` 必须被 Git 忽略，不得出现在 staged set、commit 或远端 authority 中。
4. stage 到固定 generator 的映射是 `crctl` 内部常量。Skill、Pipeline、Agent 和公共 CLI 不得传入或消费 `--candidate-out`、`--candidate`、manifest 路径或 generator 路径。
5. manifest 仍由 `writeback-apply` 执行全矩阵校验；固定目录只解决内部派生物位置，不成为新的信任边界或事实源。
6. candidate 生命周期复用现有 operational workspace/archive 清理，不新增后台清理器、candidate manager、registry 或公共查询 API。

## 4. 非功能需求

- **NFR-01 原子性**：baseline 文件、状态、commit 和 push 必须共享一个 recoverable write-set；任何 commit 前故障均不得留下部分 authority 文件。
- **NFR-02 可恢复性**：write-set、commit、push、outbox、audit 各故障点均须有 fault-injection 测试；Git authority 已确认后的恢复只允许 roll-forward。
- **NFR-03 幂等性**：同一业务输入重复执行不新增 journal、commit、push、outbox 或 audit；已完成事务返回稳定结果。
- **NFR-04 安全性**：所有路径必须 workspace-relative 且经过 containment、allowlist、symlink parent 与 hash 校验；禁止绝对路径、`..` 和调用方指定 generator。
- **NFR-05 兼容性**：LF/CRLF 输入产生一致语义；解析按 `split(/\r?\n/)` 或等价规范化实现，跨行结构匹配失败必须硬失败。新增行为必须在 Ubuntu 和 Windows 上通过。
- **NFR-06 数据保真**：backlog 语义合并除目标 CR 条目外不得改变任何字节；目标条目的未知字段不得丢失。
- **NFR-07 可审计性**：status outbox 与 success audit 必须绑定同一个 origin-confirmed 真实 commit；补发行为有确定性去重键和 journal 标记。
- **NFR-08 性能**：预检只读取一次 manifest 文本；不得为本 CR 引入全仓数据库扫描、后台服务或额外网络往返协议。
- **NFR-09 复杂度边界**：优先复用现有 `performAdvance` 候选逻辑、`runGateChecks`、durable transaction、writeback manifest、YAML block matcher、Git adapter 和测试 fixture；不新增 npm 依赖、通用事务管理器、generator plugin registry、schema registry 或 YAML patch 平台。

## 5. 验收标准

- **AC-01（FR-01）**：baseline writeback 成功后，远端同一个 commit 同时包含 baseline 目标文件和 `cr.md` 的 `writing-back` 状态；紧接着执行 tasks writeback 不会把状态重置为 `merging`。
- **AC-02（FR-01）**：planned-existing 覆盖只对已完整验证 manifest 中的精确路径参与 `fileExists` gate；修改为其他路径或用于其他 gate 类型时门禁拒绝且零写入。
- **AC-03（FR-01）**：在 write-set、commit、push、origin-confirmed 后 outbox、origin-confirmed 后 audit 各 fault point 中断并重跑，最终最多一个权威 commit、一次 status outbox 和一次 success audit；投影失败只返回 warning 并可补发。
- **AC-04（FR-01）**：feature-writeback Pipeline、`writeback-prd-sdd` Skill 与测试中不再存在 baseline 完成后独立 `advance --to writing-back` 的生产调用；任意状态复合参数不可从公共接口传入。
- **AC-05（FR-02）**：非法 JSON、schema、stage、CR、spec-id、containment、symlink parent、allowlist、before/after hash、generator hash、input digest 或目标矩阵任一失败时，journal、lock、目标文件、commit、push、outbox 和 audit 均无新增。
- **AC-06（FR-02）**：先以非法 manifest 触发失败，再修正同一业务源并重跑，能够成功且不会返回由前次非法输入引起的 `TX_INPUT_CONFLICT`。
- **AC-07（FR-02/FR-04）**：公共 CLI、三个 writeback Skill 和 feature-writeback Pipeline 不再接受或传递 `--candidate`、`--candidate-out`、manifest 路径和 generator 路径；stage 只能选择内部固定 generator。
- **AC-08（FR-03）**：参数化测试覆盖目标 CR 位于 backlog 首条、中间、末条，且 trunk 在目标条目前后各新增 CR；结果只替换目标条目，其他条目、顺序、注释、空行和未知字段逐字不变。
- **AC-09（FR-03）**：目标 CR 条目在 trunk/source 缺失或重复时 merge prepare 硬失败，所有 repo 远端 ref 均不前进；测试证明不回退到整份 trunk、整份 source 或行号拼接。
- **AC-10（FR-03）**：目标条目的 `owners`、`latest-checkpoint` 与未知 v2 字段完整保留，且语义合并代码不读写 backlog status。
- **AC-11（FR-04）**：三个 stage 的 candidate 均只出现在 `.crctl/candidates/{CR-ID}/{stage}`，目录受 containment 约束并被 Git 忽略；archive/workspace 清理后不残留需额外后台任务处理的 candidate。
- **AC-12（整体）**：新增回归测试与现有 crctl/writeback 测试在 Ubuntu、Windows 全绿；不得通过删除测试、放宽门禁或弱化现有断言获得通过。

## 6. 成功指标

- baseline writeback 的远端权威提交与 `writing-back` 状态提交数量比固定为 1:1，不再出现独立状态提交或状态丢失。
- 所有 manifest 业务校验失败均满足零 journal、零 authority 写入，修正输入后同命令重试成功。
- backlog 语义合并矩阵对首/中/末条和 trunk 前后新增 CR 场景全部通过，非目标条目字节变化数为 0。
- active Agent/Skill/Pipeline 的 candidate 路径、generator 路径和 baseline 独立 advance 算法副本数量为 0。
- 本 CR 交付不增加 npm 依赖、通用 registry、第二状态机或第二事务框架。

## 7. 依赖、风险与恢复边界

### 7.1 依赖

- 复用 CR-2026-031 已交付的 durable transaction、Transaction Workspace、candidate manifest 和 `writeback-apply`。
- 复用现有状态候选逻辑、`gates.json`、YAML block matcher、repository resolver、Git lease adapter 和 fault-injection fixture。
- 不建立 CR 级 `depends-on` 图；与 CR-2026-039~042 的范围通过来源规格切片隔离，不在本 CR 中复制其交付。

### 7.2 主要风险与控制

- **planned-existing 放宽门禁过宽**：只允许完整验证 manifest 的精确路径进入 `fileExists` 集合，其他 gate 保持现有 authority 读取。
- **origin-confirmed 后投影失败**：Git 事实不回滚，journal 分别记录 outbox/audit 是否发送，重放只补缺项。
- **backlog 文本保真受 Windows 行尾影响**：读入后先规范化解析，before hash 仍锚定磁盘原字节；跨行解析失败硬失败。
- **candidate 内部化造成旧调用方残留**：通过静态 lint/contract 测试扫描所有 active Pipeline、Skill、CLI help 和测试 fixture，不保留长期双入口。
- **本地 worktree 基线高于远端核对基线**：实现期以目标 CR tools worktree 的真实结构为准；若发现论据变化，必须修订本 PRD/SDD 并明确结论是否受影响。

### 7.3 失败与恢复

- 预检失败：零事务副作用；修正业务输入或固定 generator 后重跑同一业务命令。
- origin 在未发布前前进：按现有 stale 语义重置 Transaction Workspace，重生成 candidate 后重试。
- 已 commit 未 push：复用既有 journal 续推，不重建不同 commit。
- origin 已确认、outbox 或 audit 失败：保持成功 Git 事实，返回 warning；同命令重放只补发缺失投影。
- backlog 条目缺失/重复：prepare 阶段硬失败；修复权威账本后重试，禁止手工绕过 merge 或 force push。

## 8. 范围排除

- 不实施来源规格 FR-04~FR-09、FR-11~FR-16；这些分别属于 CR-2026-039~042。
- 不实施 Phase E 跨 CR 端到端验收；该验收在五条生产 CR 全部完成后使用独立最小 CR 执行。
- 不建立通用事务管理器、任意复合状态接口、generator/candidate manager、plugin registry、schema registry、YAML patch 框架或新的 workflow engine。
- 不建立 CR 依赖图、跨 CR 调度器、target repository/source scope 新模型。
- 不修改测试执行、review canonical、CR 时间字段、baseline traceability 证据模型、archive 严格证据门或 Agent/README/CI 职责文本。
- 不允许 force push、force rollback、自动补偿 revert、merge conflict bypass 或手工修改 `_backlog.yml`、`cr.md`、journal。
- 不重写历史 baseline milestone，不批量迁移历史数据，不为历史事实制造伪 commit、伪 digest 或伪事件。

## 9. 追溯矩阵

| 来源规格 | 本 PRD | 主要验收 |
|---|---|---|
| FR-01 Baseline 回写与状态发布 | FR-01 | AC-01~AC-04 |
| FR-02 Writeback 只读预检 | FR-02 | AC-05~AC-07 |
| FR-03 `_backlog.yml` 目标条目语义合并 | FR-03 | AC-08~AC-10 |
| FR-10 Candidate 路径约定 | FR-04 | AC-07、AC-11 |
| 实施 CR 1 完成标准 | FR-01~FR-04、NFR-01~09 | AC-01~AC-12 |

## 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-14 | v0.1.0 | Ray | 根据 Tools CR 生命周期最小优化规格的实施 CR 1 切片创建初始 PRD |

## tools CR 生命周期最小优化 2/5 — 生命周期证据规范化（v0.20.1 · CR-2026-039）

## 1. 概述

《tools-cr-lifecycle-minimal-optimization-spec.md》（下称"规格"）将 tools 包的生命周期治理拆为 5 条实施 CR。本 CR 是第 2 条"生命周期证据规范化"，落实规格 FR-04、FR-05、FR-06、FR-09，解决四类"评审/审批证据与实际受控内容脱节"的真实漏洞：

1. **代码评审 PASS 后、人工审批前无 checkpoint（规格 FR-04 / P0-04）**：`code-implementation.pipeline.json` 现状是 write-test-report → push-progress（node-8）→ review-code（node-9）→ 直接进入 approve-code 人工审批，review-code PASS 与审批之间没有 checkpoint。评审结论只证明"评审时刻"的代码合格；PASS 后未 push 的窗口内，人工审批按 release-subjects 重核远端时可能看到与评审结论不一致的内容。
2. **dev-plan PASS 未绑定被评审正文（规格 FR-05 / P1-01 / TRA-06）**：`crctl review-record` 已为 requirement（prd.md）与 tech-design（sdd.md）写入单文件 `subject-sha256`，但 dev-plan 阶段不写 digest，`crctl next` 对 dev-plan 仅有 upstream-blocker 时间戳逻辑——plan.md 或任一 TASK-*.md 在 PASS 后被修改，旧 PASS 仍可被 approve-dev-start 消费。
3. **cr.md 时间字段双轨（规格 FR-06 / P1-02）**：注册写 `updated`（workspace-transactions.mjs），状态推进的 `crMdStatusText` 只替换**已存在**的 `updated-at` 行——新格式 CR 推进后时间字段实际不刷新，且读侧面对两个语义相同的字段。
4. **review canonical 合同漂移（规格 FR-09 / P1-04）**：`crctl review-record` 实际产出的 canonical 字段是 verdict/blockers/suggestions/dimensions（+ dev-plan block 轨的 repair-target），但三个 CR 生命周期 Pipeline 与多个相关 Skill 引用 canonical annotation 中不存在的 `repair-instructions`、`fixed-blockers`，并存在 `suggestion_policy strict|lenient` 与首轮 suggestion 升格规则——这些文本契约没有实现支撑。

**解法**：全部复用现有深原语，不新建任何账本、schema 或框架——

- 在 code Pipeline review-code PASS 后插入现有 `push-progress`（即一次 `crctl checkpoint` 调用，CR-2026-033 已收敛为单一深原语），phase 非 complete 即中止，不进入人工审批；
- `review-record --stage dev-plan` 复用现有 digest helper 计算 plan.md + 排序 TASK-*.md 的 composite digest，写入现有 `subject-sha256` 字段；`crctl next` 与 approve-dev-start 消费 PASS 前重算；
- cr.md 时间字段 writer 统一写 `updated`，reader 兼容期接受旧 `updated-at`，正常写入时渐进收敛，不批量迁移；
- review canonical 字段收敛为 verdict/blockers/suggestions/dimensions/可选 repair-target，删除 `repair-instructions`、`fixed-blockers`、`suggestion_policy` 的 CR 生命周期文本契约与升格规则。

**依赖与顺序**：复用 CR-2026-031 durable transaction 与 CR-2026-033 checkpoint 深原语（均已合入本规格核对基线 `tools@origin/custom/main` `7b73204`）。CR-2026-038 独占 Writeback 原子化（规格 FR-01/02/03/10），与本 CR 功能边界独立，但两者都会修改 `crctl.mjs` 等共享文件；本 CR 实施时必须基于最新 `custom/main` 集成，不复制或回退 CR-2026-038 的实现。本 CR 实施期自身的进度保存继续使用现有 checkpoint 流程。

本 CR 触及的每个模块必须遵守以下职责边界：Agent 只负责路由、职责判断和选择 Pipeline/Skill；Pipeline 只负责节点顺序、输入传递、reviewLoop、结果分流和失败中止；Skill 只负责业务判断、编排步骤、输入输出与失败语义；crctl 负责状态、门禁、CAS、受控账本写入、审计与原子提交，但不生成 PRD/SDD 业务结论或代替 LLM 评审；版本化脚本只负责确定性文档/证据转换；README 只负责面向人的流程总览、入口、恢复说明与权威链接。所有实现决策按 ponytail 优先级依次选择：复用现有能力 > 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码。

## 2. 用户故事

- **US-01 代码审批人**：希望进入 approve-code 时，远端受控内容就是代码评审 PASS 时的那一份——评审 PASS 后必须先 checkpoint，审批重核不会看到漂移内容。
- **US-02 开发启动审批人 / dev-plan 消费方**：希望 plan.md / TASK 正文在评审 PASS 后被改动时，旧 PASS 自动失效并回到 review-dev-plan，而不是带着过期结论进入开发。
- **US-03 跨会话接续者**：希望 `cr.md` 的时间字段只有一个、语义明确（最近一次受控修改），任何 reader 不因 `updated` / `updated-at` 双轨读错"最后活动时间"。
- **US-04 Tools 维护者**：希望 Agent、Pipeline、Skill、crctl、版本化脚本与 README 各守职责边界，review 输出只有一套 canonical 字段，不再维护不存在的字段、重复算法或第二事实源。

## 3. 功能需求

### FR-01 代码评审 PASS 后、人工审批前强制 checkpoint（规格 FR-04）

- `code-implementation.pipeline.json` 在 review-code 节点返回 verdict=pass、blockers 为空且 test-report.md status=pass 后，必须执行现有 `push-progress`（一次 `crctl checkpoint` 深原语调用），然后才允许进入 approve-code 人工审批节点。
- checkpoint phase 非 complete（含 `CHECKPOINT_SENSITIVE_PATH`、`CHECKPOINT_REMOTE_ADVANCED` 等任一失败分类）时 Pipeline 立即在当前节点中止，不进入人工审批，不带不完整证据前进。
- 回修循环必须完整重放 implement-code → write-test-report → push-progress → review-code，并在再次 PASS 后重新执行本 FR 的 PASS 后 checkpoint；不允许复用上一轮 checkpoint 结论。
- approve-code 继续执行现有 release-subjects 远端重核，门禁不放宽；本 FR 只在审批前补一次受控发布，不改动 approve/reject 语义。
- 不新增 checkpoint 协议、命令或状态；状态机（15 个具名状态 + 注册前 `(new)`；28 条声明、wildcard 展开 50 条转移）不变。

### FR-02 dev-plan composite subject digest（规格 FR-05）

- `crctl review-record --stage dev-plan` 在落盘 annotation 时计算 composite digest，只写入现有 `subject-sha256` 字段（与 requirement/tech-design 同字段）；不新增 `subject-file`、freshness ledger、`input-subjects` 或通用多文件绑定 schema。
- digest 输入固定为 canonical JSON entries：plan.md 作为第一项，随后为全部 TASK-*.md；每项只含按 POSIX 相对路径排序后的 `{ "path": <workspace-relative-path>, "content": <LF-normalized-content> }`，对象键顺序固定为 `path`、`content`，JSON 不含空白，最后以 UTF-8 字节计算 SHA-256。排序、路径、内容和编码均为 digest 输入，禁止使用绝对路径、mtime、`tasks/_index.yml`、文件系统遍历顺序或平台行尾。
- `tasks/_index.yml` 不进入 digest——实现期任务状态会正常变化，不应使旧 PASS 失效；TASK 正文必须进入。
- `crctl next` 与 `approve-dev-start` 在消费 dev-plan PASS 前必须重算 composite digest；与 annotation 记录不一致时判定旧 PASS 失效，路由回 review-dev-plan（`crctl next` 给出重审建议，`approve-dev-start` 硬失败拒绝放行）。
- 历史 annotation 缺少 `subject-sha256`（legacy）时沿用现有"无 digest → 重审"的保守判定，不批量迁移历史数据。
- requirement、tech-design、code 三个阶段的既有绑定格式与消费逻辑保持不变。

### FR-03 cr.md 时间字段统一为 `updated`（规格 FR-06）

- 新注册与所有后续受控状态写入统一使用 `updated`；其语义为 `cr.md` frontmatter 最近一次受控修改时间。
- 受控 writer 收敛为三类：register、状态推进（advance/approve/reject 的 cr.md 状态文本生成）、Owner 正式移交；三者修改 `cr.md` 时均必须刷新 `updated`。
- PRD/SDD/TASK、评审、测试、checkpoint 或其他 CR 产物变化不得触碰 `cr.md#updated`。
- reader 在兼容期接受旧 `updated-at`；任一正常 writer 修改该份 `cr.md` 时，发现旧字段应替换为单一 `updated`，不得同时保留两个字段。
- 不批量迁移历史 CR；只在下一次正常写入时渐进收敛。LF/CRLF 输入必须产生一致结果（读入后 `\r\n → \n` 规范化）。

### FR-04 review canonical 合同收敛（规格 FR-09）

- 所有 review Skill、Pipeline 输出与 annotation 统一使用：`verdict`、`blockers`、`suggestions`、`dimensions`、可选 `repair-target`——与 `crctl review-record` 当前实际产出对齐。
- 本 CR 的清理范围仅覆盖 CR 生命周期的三个 Pipeline（`requirement-authoring`、`architecture-design`、`code-implementation`）及其相关 review/write Skill；`product-planning` 没有 CR 上下文，保留其独立的规划评审合同，不纳入本 CR 的 canonical 迁移。
- `repair-instructions` 不再作为持久化 canonical 字段或 Pipeline/Skill 结构化输出：从上述三个 CR Pipeline 与相关 Skill 中删除；回修所需的具体、可执行说明直接写入 `blockers` 字符串，`review_feedback` 只传递 canonical 字段。
- `fixed-blockers` 不作为独立账本或节点输出义务：下一轮 review 通过 blockers 差异自然体现修复结果；删除 CR 生命周期节点 prompt 中的 fixed-blockers 产出要求。
- blocker 表示本 CR 必须处理的问题；suggestion 表示本 CR 不处理的改进项。
- 删除 `suggestion_policy strict|lenient` 触发参数与"首轮 attempt=1 非阻塞发现升格为 blocker"的规则；dimensions 不再记录 suggestion-policy。
- reviewLoop 回修传递的 review_feedback 只含 canonical 字段（blockers、suggestions、dimensions、repair-target）；各 Skill 的自修复模式按 blockers 定点修复的行为语义不变。
- 不新增错误码注册中心或 payload validator 框架；字段收敛以文本契约修订 + 既有 lint/行为测试保障。

### FR-05 模块职责边界与最小实现（本 CR 约束）

- **Agent**：只做路由、职责判断、Pipeline/Skill 选择；不得保存状态机、执行 Git 算法或直接写受控文件。
- **Pipeline**：只做节点顺序、输入传递、reviewLoop、canonical 结果分流和失败中止；不得复制 checkpoint/digest/CAS/journal/账本算法，不得手写 `_backlog.yml`、annotation、review-loop 或其他受控文件。
- **Skill**：只做业务判断、步骤编排、输入输出与失败语义；不得手写原子账本逻辑、Git 发布算法或重复实现 `crctl`。
- **crctl**：拥有状态、门禁、CAS、受控账本写入、审计与原子提交；`review-record` 只负责 payload 校验、确定性 digest/投影和受控落盘，不生成 PRD/SDD 业务判断、不代替 LLM 评审结论。
- **版本化脚本**：只做 PRD/SDD/TASK/traceability 等确定性转换；不得推进状态或执行人工审批。
- **README**：只做面向人的流程总览、入口、恢复说明与权威链接；不得维护另一份可执行细节、状态机、门禁或深原语算法事实源。
- 新增实现依次按 ponytail 优先级选择：复用现有能力、标准库、原生 Git/文件 API、已有依赖、一行代码、最小新增代码；只有现有深接口无法表达且存在已复现故障时才允许新增代码。
- 本 FR 只约束本 CR 新增或修改的内容；其他实施 CR 负责的历史职责边界清理不在本 CR 中重复实施。

## 4. 非功能需求

- **NFR-01 复用优先**：只复用现有 `crctl checkpoint`、digest helper（sha256 + LF 规范化）、YAML block matcher、CAS 写入与既有测试 fixture；不新增模块、命令或账本。
- **NFR-02 行尾纪律**：所有 digest 计算与 frontmatter 解析先做 `\r\n → \n` 规范化；跨行正则解析失败必须硬失败，禁止静默降级为空结果。
- **NFR-03 跨平台**：全部新行为在 Ubuntu 与 Windows 上通过既有 CI 测试套件。
- **NFR-04 零状态机变更**：本 CR 不增删状态或转移；涉及状态判断的断言以 `../tools/dir-graph.yaml#change-request-track.state_machine` 当前内容为唯一事实源。
- **NFR-05 向后兼容**：legacy 无 digest 的 dev-plan annotation、旧 `updated-at` 字段的存量 CR 均不构成读取错误，按保守路径处理。

## 5. 验收标准

- **AC-01**（FR-01）：review-code PASS 且未执行 PASS 后 checkpoint 时，Pipeline 无法进入 approve-code 人工审批节点；checkpoint phase=complete 后 release-subjects 远端重核通过。
- **AC-02**（FR-01）：PASS 后 checkpoint 失败（phase 非 complete）时 Pipeline 在当前节点中止；按回修循环重放后再次 PASS，重新 checkpoint 成功才可进入审批。
- **AC-03**（FR-02）：PASS 后修改 plan.md、修改任一 TASK-*.md、增删 TASK 文件（路径集合变化）三种操作均使旧 PASS 失效——`crctl next` 建议重审、`approve-dev-start` 硬失败；只修改 `tasks/_index.yml` 不使旧 PASS 失效。
- **AC-04**（FR-02）：composite digest 可由 plan.md + 排序 TASK 集合（相对路径 + LF 内容）独立复算；CRLF 与 LF 工作区检出产生相同 digest；不同 TASK 文件集合不会产生相同 digest。
- **AC-05**（FR-03）：register、状态推进、Owner 正式移交三类写入均刷新 `updated`；PRD/SDD/TASK/评审/测试/checkpoint 等产物变化不触碰 `updated`。
- **AC-06**（FR-03）：legacy `updated-at` 兼容读取正确；writer 在含旧字段的 cr.md 上写入后只剩单一 `updated`（无双字段共存）；CRLF frontmatter 处理一致。
- **AC-07**（FR-04）：三个 CR 生命周期 Pipeline 与其相关 review/write Skill 中不再出现 `repair-instructions`、`fixed-blockers`、`suggestion_policy` 的结构化输入/输出或持久化引用；`product-planning` 及其独立规划评审合同不在此断言范围内。
- **AC-08**（FR-04）：blocker/suggestion 路由正确——block 轨 verdict=block 且 blockers 非空时按 reviewLoop 回修，pass 轨 suggestions 不阻断推进；既有 294/294 crctl 测试基线在修订后保持全绿。
- **AC-09**（FR-05）：本 CR 新增或修改的 Agent、Pipeline、Skill、crctl、版本化脚本和 README 内容分别满足对应职责边界；静态检查不得发现受控文件手写、重复 Git/crctl 算法、Agent 状态机副本或 README 可执行细节副本。
- **AC-10**（全量）：本 CR 自身按规格第 10 节"实施 CR 2"的五步清单完成：code Pipeline 插入 PASS 后 push-progress、composite digest 实现并接入 review-record/next/approve-dev-start、`updated` writer 与旧字段 reader 统一、canonical 字段与 blocker/suggestion 路由收敛。

## 6. 成功指标

- 上线后不再出现"review PASS 后内容漂移仍被人工审批消费"与"plan/TASK 修改后旧 PASS 被 approve-dev-start 沿用"两类事故（此前为规格 P0-04、TRA-06 记录在案的问题）。
- `crctl status/next` 对任一 CR 的时间字段读取不再因 `updated`/`updated-at` 双轨产生歧义；新写入 CR 中双字段共存数为 0。
- 三个 CR 生命周期 Pipeline、相关 Skill 与 canonical annotation 对废弃 review 字段的结构化引用数降为 0；`product-planning` 的独立规划评审合同保持不变。CI 防回潮静态规则本体归实施 CR 5，本 CR 不重复建设。

## 7. 范围排除

- **Writeback 原子化**（规格 FR-01、FR-02、FR-03、FR-10）归 CR-2026-038（实施 CR 1）。
- **结构化测试闭环**（规格 FR-07、FR-08：`crctl test` 结构化 plan、机器区/分析区、shell:false）归实施 CR 3；本 CR 不改动 write-test-report 的测试执行语义与 test-report.md 结构，仅按 FR-04 删除其中对 `repair-instructions`/`fixed-blockers` 的文本引用。
- **归档可信化**（规格 FR-11～FR-13：traceability 最小证据、generator 事实修正、change-impact-analysis/feedback-writeback 退役）归实施 CR 4。
- **职责边界清理**（规格 FR-14～FR-16：Agent/Pipeline/README 收敛、CI workflow 合并、lint 规则扩张）归实施 CR 5；本 CR 只做 review 字段收敛所必需的文本修订，不做整体职责重写。
- 不新增 checkpoint 协议、durable run-id、freshness ledger、subject registry、错误码 registry、schema registry 或通用 traceability 写入接口。
- 不批量迁移历史 CR 的 digest 与时间字段；不重写历史 traceability milestone。
- reviewer-panel 与 `crctl next` 对 requirement/tech-design 的既有 freshness 逻辑不在本 CR 改动范围。

## tools CR 生命周期最小优化 3/5 — 结构化测试闭环（v0.20.2 · CR-2026-040）

## 1. 概述

当前 Tools 包的正式测试证据由 `crctl test`、`write-test-report`、Pipeline 和代码评审共同维护，但入口仍接收 shell 命令字符串，执行与记录分散，且 `test-report.md`、`traceability.yml#tests` 和 review-loop 可能分别更新。这样会产生三类生命周期风险：

1. 测试命令的解析和执行边界依赖 `shell:true` 或字符串拼接，命令参数中的空格、Unicode 和 shell 元字符可能导致误执行或结果不一致。
2. 测试运行已完成但机器证据尚未完整发布时，进程中断、重复重试或单文件写入失败可能留下半套报告，后续代码评审和审批无法判断证据是否完整。
3. `test-report.md` 的机器结果与人工/模型分析混在同一生成路径中，重跑测试时可能覆盖人工分析；反过来，人工分析也可能误改由 `crctl` 生成的 status、commands 或测试账本。

本 CR 落实跨 CR 生命周期规格的实施切片 3，仅覆盖 FR-07、FR-08：将正式验证收敛为一份结构化 `cr-test-plan/v1`，由单一 `crctl test` 深接口以 `shell:false` 执行；在所有命令完成后，以既有 durable transaction 原子发布机器测试证据、`traceability.yml#tests` 和 review-loop attempt；再由 `write-test-report` 只维护 `<!-- crctl:analysis-below -->` 之后的人工分析区。测试失败是可记录的业务结果，测试计划、工作树、执行器或事务失败是技术错误，二者必须分流。

本 CR 不建设测试平台、日志服务、通用 `run/record` 协议、binary write-set、完整工作树 hash、配额系统或新的事务框架。实现必须遵循 ponytail 优先级：复用既有 `crctl`、durable transaction、review-record、controlled Git、Node 标准库和现有测试 fixture；只在现有深接口无法表达且存在真实故障时增加最小代码。

## 2. 用户故事

- **US-01 开发负责人**：希望正式验证只由一份明确的结构化计划驱动，参数按 argv 传递，不因 shell 字符串解析差异执行了错误命令。
- **US-02 测试负责人**：希望测试结果、原始日志、报告机器区、traceability 测试证据和 review-loop 轮次在一次成功发布中保持一致，失败后可按同一入口完整重试。
- **US-03 代码评审者**：希望只读取最终 `test-report.md`、真实日志和结构化 command digest，不需要重新执行 lint/test/build，也不会采信缺少 canonical 证据的报告。
- **US-04 需求/开发 Agent**：希望只负责路由、业务判断和选择 Pipeline/Skill，不保存测试命令表、不维护状态机、不直接写受控账本。
- **US-05 Tools 维护者**：希望在 Ubuntu 和 Windows 上复用 Node 标准库与既有事务设施，区分技术失败和测试失败，不引入第二套执行器、记录器或状态推进实现。
- **US-06 流程接续者**：希望测试重跑、review-loop 回修和 checkpoint 继续遵循现有 CR 状态、评审和审批门禁，任何不完整证据都不能进入代码评审或人工审批。

## 3. 功能需求

### FR-01 结构化测试单一深接口

1. 保留一个公共测试入口：

   ```text
   crctl test <CR-ID> --plan <temporary-plan.json> --workspace <knowledge-base-worktree>
   ```

2. 该入口内部可以有“执行计划”和“发布记录”两个顺序阶段，但不得对调用方公开或要求调用方组合 `test run`、`test record` 两个命令。
3. 调用方不得传入任意 shell 命令字符串、管道、重定向、命令拼接、candidate 路径、状态、review-loop 轮次或 traceability payload。
4. `crctl test` 负责结构化计划校验、测试命令执行、原始日志保存和机器证据原子发布；不负责测试发现、TASK 业务覆盖判断、测试质量评审或 CR 状态推进。
5. 入口必须校验当前 CR 处于合法开发状态，并校验 `cr.md` 中 `owners.test.id` 与 `owners.test.assigned-at` 存在。非法状态或缺少测试负责人时技术失败，canonical 测试证据不变。
6. 入口成功输出至少包含：`op`、`cr`、`attempt`、`status`、`commands`、`test-report`、`traceability`、`review-loop` 和可供 Pipeline 分流的结构化结果。
7. `crctl test` 不新增状态、状态转换、人工审批或独立 test-run ledger。状态推进继续由现有 `crctl advance`，人工审批继续由现有 `crctl approve`。

### FR-02 `cr-test-plan/v1` 输入合同

1. 测试计划 schema 固定为 `cr-test-plan/v1`，最小形态如下：

   ```json
   {
     "schema": "cr-test-plan/v1",
     "commands": [
       {
         "repo": "tools",
         "cwd": ".",
         "executable": "node",
         "args": ["--test", "test/example.test.mjs"],
         "timeoutSeconds": 600
       }
     ]
   }
   ```

2. `commands` 必须为非空数组。每条命令必须包含：
   - `repo`：目标 workspace `dir-graph.yaml#repositories` 中已声明且 active 的 repository id；
   - `cwd`：相对于该 CR worktree 仓根的相对路径，缺省为 `.`；
   - `executable`：非空可执行文件名或路径片段；
   - `args`：字符串数组，允许空数组；
   - `timeoutSeconds`：正整数，并受既有执行超时上限约束。
3. `repo` 必须解析到当前 CR 的对应 worktree。未声明仓库、缺失 worktree、分支不是 `requirement/{CR-ID}` 或解析失败时硬失败。
4. `cwd` 必须规范化后位于对应 CR worktree 内，不接受绝对路径、`..` 穿越、跨仓路径或通过符号链接逃逸 worktree 的路径。
5. 计划和字段解析必须先将 CRLF 规范化为 LF；同一语义的 CRLF/LF 计划必须得到相同 canonical digest。解析失败必须硬失败，禁止静默跳过坏命令或降级为空数组。
6. `crctl` 不从仓库自动发现测试命令。`write-test-report` 根据 TASK 验收条件、仓库原生 lint/test/build 配置和 `implement-code` 输出选择命令，并生成临时结构化 plan；Agent 不保存正式命令表，Pipeline 只传递 CR、worktree 和前序输出。
7. 计划文件是一次调用的临时输入，不作为新的 canonical 产物长期写入 CR；报告机器区记录规范化后的 command 对象和整体 digest，避免重复维护一份 `plan.json` authority。

### FR-03 安全执行与命令结果语义

1. 每条命令必须通过 Node 标准库 `child_process.spawnSync(executable, args, { shell: false, cwd, timeout })` 或等价的 `shell:false` 原生执行路径运行。
2. `executable`、`args`、`cwd` 和 timeout 必须分别传入执行器，不得拼成一条 shell 字符串。命令中的空格、Unicode、引号、`;`、`&&`、`|`、`>` 等字符只能作为参数数据处理，不得获得 shell 语义。
3. 运行阶段不创建 durable journal、不持有受控账本写锁、不修改 `cr.md`、`_backlog.yml`、`traceability.yml` 或 review-loop。运行阶段只收集每条命令的退出码、信号、timeout、stdout/stderr 和执行元数据。
4. 已成功启动的命令返回非零退出码或 timeout，属于**业务失败**：
   - 记录该命令的失败结果和日志；
   - 继续执行计划中的其余命令；
   - 所有命令结束后统一生成 `status: block` 的完整 canonical 证据；
   - 不因一条失败命令跳过其余命令，也不提供 `continueOnError` 等额外分支配置。
5. 计划 schema、repository、worktree/cwd containment、executable 启动或参数校验失败，属于**技术失败**：
   - 立即中止；
   - 不发布新的 canonical test report、traceability tests 或 review-loop attempt；
   - 以结构化错误返回失败原因、文件/字段和可重试动作。
6. 运行阶段发生外部中断或进程无法完成全量计划时，不能把部分结果发布为新的 canonical attempt，不能覆盖上一轮 canonical report；重试必须从完整 plan 重新执行。
7. `implement-code` 可以执行开发期临时检查，但其输出不能替代本 FR 定义的 canonical `crctl test` 记录。`review-code` 不得执行或重新执行 lint/test/build。

### FR-04 机器证据原子发布

1. 所有命令结束且结果已归类后，`crctl test` 必须使用既有 durable transaction 同批发布以下机器事实：
   - `change-requests/{CR-ID}/test-report.md` 的机器区；
   - `change-requests/{CR-ID}/test-evidence/` 下与每条命令对应的原始 stdout/stderr 日志；
   - `change-requests/{CR-ID}/traceability.yml#tests`；
   - `change-requests/{CR-ID}/review-loop.yml` 中 `write-test-report` 的 attempt，以及 traceability 中对应的 review-loop 投影。
2. 正常业务失败也必须完成上述一次性发布，只是 canonical 报告为 `status: block`，并由 Pipeline 回到 `implement-code`；业务失败不是事务错误，不得因为非零退出码回滚或丢弃测试证据。
3. 任一技术校验、文件写入、CAS、事务提交或发布失败时，canonical 测试报告、traceability tests 和 review-loop 必须保持上一轮完整状态；不得留下只更新其中一部分的半完成投影。
4. 原始 stdout/stderr 必须落到现有 `test-evidence/`，报告中的每个 command 只引用对应日志的 workspace-relative 路径，不复制完整日志内容到 traceability。
5. 机器区必须记录每条规范化 command 的完整对象、结果、退出码或 timeout、日志路径，以及整个规范化 command 集合的 LF canonical SHA-256 digest。digest 的输入必须同时包含相对路径和文件内容，避免不同命令集合因简单拼接产生碰撞。
6. 机器区的 `status` 只允许由实际命令结果确定：全部命令退出码为 0 时为 `pass`；任一已启动命令非零或 timeout 时为 `block`。模型、Agent、Pipeline 和 `write-test-report` 不得改写 `status` 或 command 列表。
7. 同一次完整 plan 的记录必须具有稳定的 command 语义；重复执行产生新的合法 attempt 时，必须以新一轮完整结果替换当前 canonical 机器区，而不是把上一轮和本轮命令数组拼接。

### FR-05 `test-report.md` 机器区与人工分析区分界

1. `test-report.md` 使用唯一 marker：

   ```text
   <!-- crctl:analysis-below -->
   ```

2. marker 之前是 `crctl` 独占的机器区，包含 frontmatter、规范化 commands、结果、digest、日志引用和生成来源。`write-test-report`、Agent、Pipeline 和人工不得直接改写该区域。
3. marker 及其之后是人工/模型分析区。`write-test-report` 只拥有该区域，负责根据最新机器结果更新：
   - 测试结果摘要；
   - TASK 验收覆盖矩阵；
   - 新增/修改测试文件；
   - 未覆盖风险与不适用说明；
   - 对失败结果的解释和下一步建议。
4. 重跑测试时，marker 后已有内容必须逐字保留，除非 `write-test-report` 在新的分析写入步骤中基于最新机器结果主动更新；保留机制不能被解释为旧分析自动仍然有效。
5. 报告不存在时，`crctl test` 创建合法机器区并写入唯一 marker，marker 后为空分析区，随后由 `write-test-report` 补充分析。
6. marker 缺失、重复或无法唯一确定机器区/分析区边界时硬失败，要求人工修复后重试；不得猜测第一处、最后一处或通过截断文本降级。
7. marker 与其前后的 CRLF/LF 变化不得改变分界结果。跨行匹配失败必须返回结构化错误，不得静默生成空分析区。
8. `traceability.yml#tests`、`review-loop.yml` 和报告机器区不属于人工分析区，`write-test-report` 不得在分析步骤中直接写入或修改它们。

### FR-06 Skill、Pipeline 与 Agent 采用

1. `write-test-report` Skill 的职责限定为：
   - 校验 CR、测试负责人和前置文档；
   - 根据 TASK 和 implement-code 输出进行业务判断，生成临时结构化 plan；
   - 调用一次 `crctl test`；
   - 读取 crctl 返回的机器结果；
   - 只更新 marker 后分析区；
   - 输出 `status`、blockers、repair-target、attempt 和下一步。
2. `write-test-report` 不得：
   - 手写 `test-report.md` 的 status、commands、generated-by 或机器 digest；
   - 直接写 `traceability.yml#tests` 或 review-loop；
   - 实现 `spawnSync`、shell 安全、事务、CAS、日志归档或账本原子写入算法；
   - 重新执行测试命令来代替 `crctl test`。
3. `code-implementation.pipeline.json` 的测试节点只描述输入传递、一次 Skill 调用、结果分流、`reviewLoop` 和失败中止。测试证据阻塞时按既有 `replayNodes=[implement-code, write-test-report]` 回修，最多 3 次；超过上限停止在当前闭环，不进入 checkpoint、代码评审或人工审批。
4. 代码评审回修的 `reviewLoop` 必须按既有顺序重放：

   ```text
   implement-code -> write-test-report -> push-progress -> review-code
   ```

   评审 PASS 后仍需先完成 checkpoint，checkpoint 未完成不得进入人工审批。
5. `review-code` 只读取真实 diff、TASK/SDD、最终 `test-report.md`、command digest 和原始日志，产出业务评审结论；不得调用 `crctl test`，不得自行补写测试报告或 traceability。
6. Agent 只负责根据职责和当前 `crctl next` 结果选择 coding Pipeline/Skill、传递输入和判断是否需要人工介入；Agent 不保存状态机副本、测试命令表、Git 算法或受控文件写入逻辑。
7. `crctl` 只负责状态、门禁、结构化计划执行、原始日志、机器证据、CAS/durable transaction、review-loop 与审计；不判断 TASK 是否覆盖充分、不判断测试是否“合理”、不生成 LLM 评审结论。
8. 版本化脚本只在本 CR 需要时执行确定性文档转换；本 CR 不增加测试脚本的状态推进、审批或 Git 发布能力。README 只保留人读流程总览和权威入口，不复制本 FR 的执行算法。

### FR-07 测试证据到评审和审批的门禁

1. `write-test-report` 返回 `status=block`、证据缺失、机器区漂移或分析区写入失败时，Pipeline 必须在当前节点中止或进入声明的 reviewLoop 修复，不得进入后续 `push-progress`、`review-code` 或 `human_approval`。
2. `review-code` 通过条件必须同时满足：
   - `review-annotations/code.yml#verdict=pass`；
   - `blockers=[]`；
   - `test-report.md` 的 canonical machine status 为 `pass`；
   - command digest、日志引用和报告机器区可复算且未漂移；
   - analysis 区已存在且对 TASK 覆盖与未覆盖风险作出明确说明。
3. `review-code` 不得因为测试报告缺失、status 非 pass、digest 不一致、日志缺失或分析不完整而降级为 suggestion；这些均必须形成 blocker 并回到 `implement-code -> write-test-report`。
4. 代码评审 PASS 后必须调用现有 `push-progress` 完成 checkpoint；checkpoint 返回的 `phase` 非 `complete` 时中止，不进入人工审批。
5. `approve-code` 继续使用现有 `crctl approve --stage code`，由 `crctl` 校验证据和人工审批，不新增测试审批接口、不把 Pipeline 的 PASS 文本当作审批结论。

### FR-08 幂等、重试和跨平台行为

1. 计划校验、命令执行和事务发布必须支持同一入口重试。事务已完成的重放应复用既有 journal/commit 事实，返回幂等成功，不重复执行已确认的账本发布或产生重复 review-loop attempt。
2. 技术失败必须零 canonical 变化；修正 plan、repository、cwd、executable、marker 或事务冲突后，使用同一 `crctl test` 入口重新执行完整 plan。
3. 业务失败必须生成一份完整的 `block` 证据；修复代码后重新执行完整 plan，不能只执行失败的单条命令、续用部分日志或合并多个 attempt 的结果。
4. 中断运行不得覆盖上一轮 canonical report，不得生成新的 canonical attempt，不得把残留临时日志当作成功证据；重试重新开始并在完整结束后一次性发布。
5. 所有跨行解析、报告 marker 定位、digest 输入和文件读取必须先做 CRLF 到 LF 规范化；输出的 canonical 机器区和 digest 在 Windows/Ubuntu 上一致。
6. 不新增 npm 依赖。优先复用 Node 标准库 `child_process`、`fs`、`path`、`crypto`，以及现有 `crctl` 的解析、hash、CAS、durable transaction、审计和测试 fixture。
7. 不允许 force write、手改 `_backlog.yml`/`cr.md`/`traceability.yml`/`review-loop.yml` 绕过失败，不允许通过增加 `--continueOnError`、`--allow-shell` 或类似开关削弱安全边界。

## 4. 非功能需求

- **安全性**：所有正式测试执行均为 argv + `shell:false`；不接受任意 shell 字符串，不接受绝对路径或跨 worktree cwd，不提供绕过开关。
- **原子性**：机器报告、测试日志引用、traceability tests 和 review-loop attempt 必须在同一既有 durable transaction 中发布；任一技术失败不产生半套 canonical 投影。
- **可恢复性**：测试运行失败与事务技术失败必须返回结构化、可区分的错误/业务结果；重试不需要手工改账本。
- **可审计性**：记录实际规范化 command、结果、digest、日志路径、CR、测试负责人和 attempt；不把完整 stdout/stderr 复制进 traceability。
- **跨平台性**：Windows/Ubuntu 的 CRLF/LF、路径分隔符、参数空格和 Unicode 行为一致；canonical 输出使用 LF。
- **可测试性**：至少覆盖计划 schema、argv 安全、worktree containment、启动失败、非零退出、timeout、中断、事务故障、重复重试、marker 保留/缺失/重复和 command digest 重算。
- **性能**：单 CR 的命令数为 `n` 时，计划校验与证据整理不引入超出命令输出规模的额外持久化模型；不缓存、不并行、不建立测试服务。
- **极简性**：不新增 test runner、test record API、日志平台、schema registry、通用事务层、插件 registry、错误码中心或工作树全量 hash。

## 5. 验收标准

- **AC-01（FR-01/02）**：合法的 `cr-test-plan/v1` 能被 `crctl test` 接受；空 commands、缺 schema、字段类型错误、未知 repo、缺失 worktree、非法 cwd、非正 timeout 和 executable 为空均在写入前失败，返回结构化错误且 canonical 文件零变化。
- **AC-02（FR-02/03）**：包含空格、Unicode、引号、`;`、`&&`、`|`、`>` 等参数的计划按原始 argv 执行，不能触发 shell 解释；测试能证明 `shell:false`，且命令参数没有被拼接为单字符串。
- **AC-03（FR-02/08）**：同一语义的 CRLF 与 LF plan 在 Windows/Ubuntu 上生成相同 command digest；非法跨行/marker 解析硬失败，不产生空 commands 或空分析区。
- **AC-04（FR-03）**：计划中第一条命令返回非零或 timeout 时，剩余命令仍执行；所有命令结束后报告为 `status: block`，每条命令均有退出结果/timeout 和对应原始日志。
- **AC-05（FR-03）**：repository、cwd containment、executable 启动、参数或计划 schema 技术失败时立即中止；上一轮 `test-report.md`、traceability tests 和 review-loop 不变，且不存在新的 canonical attempt。
- **AC-06（FR-04）**：一次成功测试发布同时更新机器报告区、所有命令原始日志引用、`traceability.yml#tests` 和 `review-loop.yml`；任一事务/CAS/fault point 注入失败时，不留下仅更新其中一部分的投影。
- **AC-07（FR-04）**：机器区包含规范化 command 对象、结果、日志路径和可复算的整体 SHA-256 digest；修改 executable、args、cwd、repo 或 command 集合后旧 digest 必然不匹配；不生成第二份 canonical `plan.json`。
- **AC-08（FR-05）**：报告 marker 后已有多行人工分析在测试重跑后逐字保留；marker 缺失或重复时硬失败，报告字节、traceability tests 和 review-loop 均不变化；新报告创建后包含唯一 marker 和空分析区。
- **AC-09（FR-05/06）**：`write-test-report` 只能修改 marker 后分析区；静态 contract 检查证明 Skill 不手写 status/commands/frontmatter、traceability tests、review-loop、spawnSync 或账本 CAS 算法。
- **AC-10（FR-06）**：Pipeline 的测试 evidence reviewLoop 在 block 时按 `[implement-code, write-test-report]` 重放；代码 reviewLoop 按 `[implement-code, write-test-report, push-progress, review-code]` 重放；达到 3 次仍 block 时停止，不进入 human approval。
- **AC-11（FR-06/07）**：`review-code` 不再重新执行 lint/test/build；缺失报告、status 非 pass、digest/日志漂移或分析区不完整均产生 blocker，并回到实现和测试报告节点。
- **AC-12（FR-07）**：测试报告 PASS 后，review-code PASS 仍必须先完成现有 checkpoint；checkpoint `phase != complete` 时不能进入人工审批；`approve-code` 仍只通过现有 `crctl approve --stage code` 推进状态。
- **AC-13（FR-08）**：同一完整 plan 的合法事务重放幂等成功，不重复执行已确认的账本发布，不重复 attempt；修改代码后重试完整 plan 会生成新完整结果，不复用部分日志或只重跑失败命令。
- **AC-14（FR-03/08）**：外部中断发生在命令执行或发布前后时，不覆盖上一轮 canonical report，不发布半套机器证据；恢复只能通过重新执行完整 plan。
- **AC-15（全范围）**：静态检查证明 Agent 不持有状态机/Git/账本算法，Pipeline 不复制 Skill/crctl 完整算法，Skill 不手写受控账本，crctl 不包含业务测试发现或 LLM 评审结论，README 不增加另一份可执行事实源。
- **AC-16（工程质量）**：现有 crctl、review-loop、traceability、checkpoint、code review 和 approval 回归测试保持通过；新增结构化 test、shell:false、原子发布、marker、CRLF、timeout、中断和 fault-injection 测试在 Ubuntu 与 Windows 均通过；不引入新的生产依赖。

## 6. 成功指标

- 正式验证命令全部由 `cr-test-plan/v1` 驱动，生产路径不再接受 shell 命令字符串或 `shell:true`。
- 测试机器证据的唯一发布路径为 `crctl test`；`test-report.md`、`traceability.yml#tests` 和 review-loop 不再存在分散写入造成的半完成状态。
- 测试重跑不会覆盖 marker 后人工分析；marker 异常不会被静默修复或猜测。
- `review-code` 不再重复执行测试命令；测试证据不足时能够通过既有 reviewLoop 回到实现和测试报告节点。
- 所有承诺的技术失败零变化、业务失败可记录、完整重试和事务故障恢复场景均有可执行测试。
- CR-2026-040 的实现不增加第二套测试平台、事务框架、run/record 协议、状态机或账本模型。

## 7. 依赖与风险

- **依赖**：Tools 当前 `crctl` 的 CR/worktree resolver、Node 文件与 hash helper、`spawnSync` 可用能力、durable transaction、CAS、audit、review-loop 和 traceability 投影；`write-test-report`、`review-code` 与 `code-implementation.pipeline.json` 的现有契约。
- **风险 R-01：旧调用契约残留**。当前 Skill/Pipeline 仍可能描述 `--cmd` 字符串或由评审重新执行测试；必须在同一 CR 内同步收敛调用方，并用静态 contract 测试阻止回归。
- **风险 R-02：机器区与分析区边界漂移**。marker 缺失/重复必须硬失败；不得使用宽松正则或“取第一处/最后一处”的兼容逻辑。
- **风险 R-03：测试失败与技术失败混淆**。非零退出和 timeout 必须记录为业务 block；schema、启动器、路径和事务错误必须保持上一轮 canonical 证据不变。
- **风险 R-04：原子发布范围不足**。必须复用既有 durable transaction；不得为 test 单独引入新的 journal、run-id 恢复协议或 binary write-set。
- **风险 R-05：重试重复执行或丢失 attempt**。事务故障测试必须覆盖命令执行完成、部分日志生成、canonical 发布前中断和发布后重放，确认不会出现重复账本或部分 attempt。
- **风险 R-06：跨平台差异**。Windows CRLF、路径和 executable 启动行为可能导致 digest/报告不一致；所有解析和 digest 输入统一先规范化 LF，并加入 Windows 回归矩阵。

## 8. 范围排除

- 不建设日志服务、测试结果数据库、远程测试执行平台、配额系统、测试发现器或通用 binary protocol。
- 不公开拆分 `test run` / `test record`，不新增通用 `run/record` API、公共 test ledger 或独立 test-run 恢复命令。
- 不新增完整工作树 hashing、execution grant、强身份认证、test provider/plugin registry 或 schema registry。
- 不允许 Pipeline、Agent 或 Skill 手写 `test-report.md` 机器区、`traceability.yml#tests`、`review-loop.yml` 或其他受控账本。
- 不让 `crctl` 判断 TASK 验收是否充分、测试命令是否覆盖业务、报告分析是否合理或 LLM 评审是否通过。
- 不让 `review-code` 执行测试；不改变现有 code review、approval、checkpoint 和状态机的业务语义，只补齐测试证据前置条件和回修闭环。
- 不修改 CR-2026-040 之外的生命周期切片：writeback 原子化、证据规范化、归档可信化、职责边界清理和 Phase E 端到端验收均不在本 CR 实施范围。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘在本 CR 的 requirement worktree。

## 9. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-14 | v0.1.0 | Ray | 初始草稿：结构化 test plan、shell:false、机器证据原子发布、marker 分区保护和 review-loop/checkpoint 闭环 |

## 归档可信化（v0.20.3 · CR-2026-041）

## 1. 概述

当前 Tools 包的 CR 生命周期已具备状态机、门禁、CAS、人工审批、durable transaction、跨仓 merge、checkpoint、review-record、candidate-only writeback 和 archive 等深原语。但 `writeback-traceability` 回写的 baseline `traceability.yml` 只记录 `merge-commits` 与 `fr-chain`，**没有兑现 README 和规格中"里程碑含测试、评审、审批与 merge 证据"的承诺**；同时 `crctl archive` 在归档事务产生写入前只校验 tasks done、traceability 落点和 `approval.yml` 存在，**不校验证据是否真实、完整、可复算**，因此一个证据缺失、漂移或状态未通过的 CR 仍可能被归档。此外，`change-impact-analysis` 建立在不存在的 baseline schema（`requirements[].reviews.*.result=stale`）上，`feedback-writeback` 只有 prompt 契约、会直接手写 `traceability.yml`/`tech-notes` 并发送与 canonical 语义冲突的 inbox，二者作为 active 能力存在虚假声明。

本 CR 落实跨 CR 生命周期规格 `docs/analysis/tools-cr-lifecycle-minimal-optimization-spec.md` 的实施切片 4，仅覆盖 FR-11、FR-12、FR-13：

1. **FR-11 最小证据摘要**：`writeback-traceability` generator 为当前 CR 新增 milestone 机械注入测试、评审、审批与 merge 的最小证据摘要；`crctl archive` 复用既有 lock，并在首次发布产生新 journal 或 authority 写入前，以同一确定性校验函数严格校验该证据。
2. **FR-12 事实源修正**：traceability generator 的 trunk 只从 `dir-graph.yaml#repositories` 解析（缺失硬失败，禁止回退 `master`），merge 只从 `change-requests/{CR-ID}/merge-commits.yml` 读取，并清除仍声称来源为 `_backlog.yml` 的注释、变量和错误文案；复用 CR-2026-038 已交付的固定 generator 映射与真实脚本 hash 校验，只补回归确认。
3. **FR-13 退役不支持能力**：删除 `change-impact-analysis` Skill 及其 active 引用，移除 `review-alignment` 对不存在 stale 模型的依赖；退役当前 `feedback-writeback` 的 active 能力声明，保留 `CONTEXT.md` 已敲定的"终态反馈事实"领域模型并按 `CUSTOM.md#CUSTOM-TODO-010` 登记后续建设条件。

本 CR 不建设通用事务管理器、通用 traceability 写入接口、schema registry、错误码注册中心、影响/stale/perspective/change-log 模型、feedback 终态写入链或新的 workflow engine。实现必须遵循 ponytail 优先级：复用既有 `crctl`、durable transaction、review-record、writeback manifest、YAML matcher、Git adapter 和现有测试 fixture；只在现有深接口无法表达且存在真实故障时增加最小代码。

## 2. 目标逻辑架构

本 CR 的全部实现必须遵守以下模块职责边界。该边界是跨 CR 规格 §4 的收敛结果，本 CR 不重复造一套，只按此约束落地。

| 模块 | 应拥有 | 不应拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览、入口、恢复说明和权威链接 | 另一份可执行细节事实源 |

ponytail 优先级（本 CR 各 FR 的取舍依据，自上而下优先）：

1. 复用现有能力（`crctl`、durable transaction、review-record、writeback manifest、YAML matcher、测试 fixture）；
2. Node 标准库（`fs`、`path`、`crypto`、`child_process`）；
3. 原生 Git/文件 API（现有 controlled Git adapter）；
4. 已有依赖；
5. 一行代码；
6. 最小新增代码。

### 2.1 已解决基础设施（只复用，不重做）

| 能力 | 当前状态 | 本 CR 处理 |
|---|---|---|
| durable transaction | 已有锁、journal、write-set、故障恢复和只读 `loadExistingJournal` | 复用；证据校验使用既有 archive lock，不引入新事务层 |
| archive 四账本事务 | 已有 backlog/history/index/cr.md 同批 write-set + commit + lease push + cleanup-pending + outbox | 复用事务与清理；首次发布在新 journal/authority 写入前增加当前 CR milestone 的严格证据门 |
| writeback-apply | 已有 manifest 校验、CAS、commit/push、候选路径、`baseline/tasks/traceability` 固定 generator 映射和真实脚本 hash 校验 | 全量复用；本 CR 只做 FR-12 回归确认，不改生产行为 |
| writeback-traceability generator | 已有 candidate-only、header 累积、milestone 段追加、幂等判据、SELF_CHECK | 复用；仅机械注入 `evidence` 块并修正事实源 |
| review-record / review-annotations | 已产出 `requirement.yml`/`sdd.yml`/`dev-plan.yml`/`code.yml` 四份 annotation | 复用为 review 证据的 canonical 事实源，不改其绑定格式 |
| merge-commits.yml | 已有 `schema: merge-commits/v1`，`repositories[]` 含 repo/base-sha/source-sha/merge-sha | 复用为 merge 证据唯一事实源 |
| approval.yml | 已有人工审批四段（requirement/tech-design/development-start/code） | 复用为审批证据唯一事实源 |
| test-report.md | 已有 `crctl test` 生成的机器区（status/digest/日志引用） | 复用为测试证据唯一事实源 |
| CONTEXT.md 终态反馈事实 | 已敲定 `(CR-ID, spec-id)` 领域模型 | 保留领域语义，退役当前 prompt 契约 |
| CUSTOM.md 台账 | 已有 `CUSTOM-TODO-010` 登记 | 本轮只核对/确认登记，不新增实现 |

### 2.2 本次最小改造

| 改造点 | 性质 | 说明 |
|---|---|---|
| `writeback-traceability.mjs` 注入 `evidence` 块 | 版本化脚本确定性转换 | 只加结构，不改既有段字节保留逻辑 |
| 证据确定性校验纯函数 | 新增最小纯函数 | generator 与 archive gate 复用同一函数 |
| `archiveCr` 写入前证据门 | `crctl` 深模块扩展 | 复用既有 archive lock 与 `loadExistingJournal`；仅首次发布在创建新 journal 前硬失败 |
| trunk resolver 去 `master` 回退 | 事实源修正 | 删除一行 fallback |
| backlog 旧注释/变量/错误文案清理 | 删除 | 只改文案与变量名 |
| 两个退役 Skill 删除 + 引用清理 | 删除 | 不保留 stub |

## 3. 用户故事

- **US-01 归档执行者**：希望在 `crctl archive` 首次发布产生新 journal 或 authority 写入前，就能确认当前 CR 的测试、评审、审批与 merge 证据齐全、状态通过、路径合法且 digest 可复算；证据漂移的 CR 不得进入 archived。
- **US-02 版本化脚本维护者**：希望 `writeback-traceability` 机械从 canonical 文件生成证据摘要，不依赖模型手工誊抄状态或 hash；事实源只有 `merge-commits.yml`、`approval.yml`、`review-annotations/*` 与 `test-report.md`，不再声称来自 `_backlog.yml`。
- **US-03 审计/追溯者**：希望 baseline `traceability.yml` 的每个新 milestone 含最小但可复算的发布证据摘要，既有历史 milestone 逐字节不变、不被迁移或补齐。
- **US-04 能力使用者（Agent/runtime）**：希望 Agent/Skill/Pipeline 只负责路由与业务判断，不维护状态机副本、不手写受控账本、不实现 Git 算法；退役能力不再被 README/Agent/矩阵声称为可执行。
- **US-05 Tools 维护者**：希望在 Ubuntu 和 Windows 上复用既有 durable transaction、manifest 校验和测试 fixture，只为"证据门"增加一个确定性校验函数，不引入第二套事务框架、schema registry 或通用 traceability 接口。

## 4. 功能需求

### FR-01 最小证据摘要结构与机械生成（规格 FR-11）

1. `writeback-traceability` generator 在追加当前 CR 的新 milestone 段时，必须机械注入以下 `evidence` 块（key 名固定，结构最小）：

   ```yaml
   evidence:
     test: { status: pass, path: change-requests/CR-.../test-report.md, sha256: ... }
     reviews:
       requirement: { verdict: pass, path: ..., sha256: ... }
       tech-design: { verdict: pass, path: ..., sha256: ... }
       dev-plan: { verdict: pass, path: ..., sha256: ... }
       code: { verdict: pass, path: ..., sha256: ... }
     approval: { status: approved, path: change-requests/CR-.../approval.yml, sha256: ... }
     merge: { status: merged, path: change-requests/CR-.../merge-commits.yml, sha256: ... }
   ```

2. 证据摘要只记录**状态结论、workspace 相对路径、LF canonical SHA-256 digest**，不复制完整测试报告、annotation 正文、approval grant 明细或 merge commit 明细。
3. generator 必须从下列 canonical 文件读取证据，不允许模型手工誊抄状态或 hash：

   | evidence key | canonical 事实源 | 摘要字段 |
   |---|---|---|
   | `test` | `change-requests/{CR-ID}/test-report.md`（机器区） | `status`、`path`、`sha256` |
   | `reviews.requirement` | `change-requests/{CR-ID}/review-annotations/requirement.yml` | `verdict`、`path`、`sha256` |
   | `reviews.tech-design` | `change-requests/{CR-ID}/review-annotations/sdd.yml` | `verdict`、`path`、`sha256` |
   | `reviews.dev-plan` | `change-requests/{CR-ID}/review-annotations/dev-plan.yml` | `verdict`、`path`、`sha256` |
   | `reviews.code` | `change-requests/{CR-ID}/review-annotations/code.yml` | `verdict`、`path`、`sha256` |
   | `approval` | `change-requests/{CR-ID}/approval.yml`（整份） | `status`、`path`、`sha256` |
   | `merge` | `change-requests/{CR-ID}/merge-commits.yml`（整份） | `status`、`path`、`sha256` |

4. review 证据按四份独立 annotation 分项记录，每项 `verdict: pass`；审批证据只聚合整份 `approval.yml` 为 `status: approved`；merge 证据只聚合整份 `merge-commits.yml` 为 `status: merged`。不复制分阶段 grant 摘要或单仓 commit 明细。
5. digest 输入必须先 CRLF→LF 规范化，并使用既有 `sha256` helper 对整份 canonical 文件计算；同一文件在 Windows/Ubuntu 上必须得到相同 digest。
6. 该 `evidence` 块是 milestone 级结构化证据，与 `fr-chain[].evidence`（每条 FR 的人工注释字符串）互不取代；后者保持既有 opaque 语义不变。

### FR-02 证据与 merge 事实源修正（规格 FR-11 / FR-12）

1. trunk 只从 workspace `dir-graph.yaml#repositories` 的 repositories resolver 获取；目标 repository 缺失时硬失败，禁止回退 `master`、禁止从 `_backlog.yml` 或 merge commit message 猜测 trunk。
2. merge 证据只从 `change-requests/{CR-ID}/merge-commits.yml` 读取；`schema` 必须为 `merge-commits/v1`，`repositories[]` 的 `repo`、`merge-sha` 必须齐全。缺失、重复或字段不齐全硬失败，不猜测、不取 trunk 最新提交。
3. generator 的注释、变量名和错误文案不得继续声称 merge 来源为 `_backlog.yml`；当前代码中"从 `_backlog.yml` 定向提取"的注释、`fromBacklog` 变量名以及"milestone-file 内 merge-commits 与 _backlog.yml 提取结果不一致"的错误文案必须删除或改写为 `merge-commits.yml`。
4. 若 milestone-file 自带 `merge-commits`，与 `merge-commits.yml` 提取结果的一致性校验保持不变（防人工誊抄分叉），但文案与变量名同样不得再引用 `_backlog.yml`。
5. 本需求只修正事实源与文案，不改变 `merge-commits.yml` 的 schema，不新增 YAML parser，不新建 merge 提取路径。

### FR-03 generator 身份既有约束回归（规格 FR-12）

1. CR-2026-038 已交付的 `WRITEBACK_GENERATORS` 固定映射、固定脚本执行和真实脚本 hash 校验是本需求的既有实现；stage 固定为 `baseline`、`tasks`、`traceability`，不得与 generator id 混用。
2. 本 CR 不修改该生产路径，只增加或复用回归测试确认：`writeback-apply` 仍对当前 Tools Root 的固定脚本计算真实 hash，不信任 manifest 自报值；hash 不匹配时拒绝 candidate。
3. 调用方仍不得传入 generator 路径；不得新增 generator plugin registry、候选管理器或新的 generator。
4. 若回归测试发现既有实现缺陷，只做直接修复；不得重写 CR-2026-038 已有映射、执行器或校验流程。

### FR-04 archive 前严格证据门（规格 FR-11）

1. `crctl archive` 继续先获取既有 archive lock；lock 只用于串行化并在失败时释放，不是新的 authority 或事务协议。
2. lock 内先复用只读 `loadExistingJournal` 分流：已 commit/push 或进入 cleanup/complete 的 journal 继续既有恢复，不重复校验证据；无 journal，或已有 journal 但尚无 authority 副作用时，必须在创建/修改 journal及任何 write-set/commit/push/outbox/audit 前校验当前 CR milestone 的 `evidence` 块。
3. archive gate 与 generator 复用**同一确定性证据校验函数**，只检查当前 CR milestone，不建立通用 schema registry 或脚本型 gate。证据校验必须同时覆盖：
   - `test.status == pass`、路径合法、digest 可复算；
   - 四份 review annotation 均存在且 `verdict == pass`、路径合法、digest 可复算；
   - `approval.status == approved`、路径合法、digest 可复算，且从该文件验证 `requirement`、`tech-design`、`development-start`、`code` 四个必需 grant 均存在；
   - `merge.status == merged`、路径合法、digest 可复算，且从该文件验证当前 CR 的合并事实存在。
4. 当前 CR milestone 重复、evidence key 重复、证据路径指向其他 CR，以及证据缺失、状态不通过、路径不合法或 digest 不匹配，均硬失败；失败释放 lock，返回结构化错误并指明缺项，不创建或修改 journal，不产生 authority 写入和审计，可补齐后以同一命令重试。
5. 既有 archive 前置校验（tasks 全 done、`specs/{spec}/traceability.yml` 存在、`approval.yml` 存在）保持不动；本证据门是新增的**追加门**，不替换、不放宽既有门禁。
6. rejected/withdrawn 路径没有 writing-back milestone，不执行该证据门；archive 的 writing-back → archived、cleanup-pending、幂等重放与 outbox 补发语义不变。

### FR-05 历史 milestone opaque 与新 milestone 无 status（规格 FR-11）

1. 既有 milestone 段继续作为 opaque 历史段**逐字节保留**；本 CR 不迁移、不补齐、不重写历史 milestone。
2. 历史 milestone 缺少 `evidence` 字段不构成读取错误；归档门与 generator 只校验当前 CR 的新 milestone。
3. 新 milestone 段**不写 `status`**；不得复制瞬时 `writing-back`、提前写 `archived`、或引入状态机之外的 `released`。CR 状态继续只由 `cr.md` 与 `_history.yml` 表达。
4. generator 的既有幂等判据（specs 侧已含 `- cr: {CR-ID}` 段则 noop）与既有段字节保留自检保持不变。
5. 不建立通用 `traceability-record --kind ...` 接口，不建立 traceability 写入 handler，不新增通用 milestone schema registry。

### FR-06 change-impact-analysis 退役（规格 FR-13）

1. 删除 `skills/review/change-impact-analysis/SKILL.md`，并同步删除其全部 active 引用：
   - `skills/_index.yml` 中 `change-impact-analysis` 条目；
   - `agent-skill-matrix.yml` 中 `quality-reviewer-agent` 的 owns 列表项；
   - `AGENT-SKILL-MATRIX.md`、`agents/quality-reviewer-agent.md`、`agents/_index.yml` 中的声明；
   - `dir-graph.yaml` 中 `skill_context.change-impact-analysis` hint；
   - `README.md`、`docs/QODER-使用指南.md`、`openwiki/architecture/agent-skill-matrix.md` 中的能力声明。
2. 删除 `review-alignment` 对不存在 stale 模型的依赖：移除 AL-07（`traceability.requirements[].reviews.*.result != stale`）及任何引用 `change-impact-analysis` 置位的描述；`review-alignment` 其余 AL-01～AL-06 保留，只读职责不变。
3. 不补建 impact/stale/perspective/change-log 模型，不保留 retired stub、占位 Skill 或兼容分支。
4. 只删除 active 契约；历史报告或架构快照中的事实性提及可以保留，不得为字符串清零改写历史记录。
5. Git 历史承担旧 Skill 的审计与恢复；未来需要 impact 分析时按真实需求注册独立 CR。

### FR-07 feedback-writeback 退役与 CUSTOM-TODO-010 登记（规格 FR-13）

1. 删除 `skills/cr/feedback-writeback/SKILL.md`，并同步删除其全部 active 引用：
   - `skills/_index.yml` 中 `feedback-writeback` 条目；
   - `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md` 中的声明；
   - `README.md`、`docs/QODER-使用指南.md`、`openwiki/architecture/agent-skill-matrix.md` 中的能力声明；
   - `skills/cr/inbox-emit/SKILL.md` 的 event allowlist 中 `feedback-writeback-done` 事件名与触发方描述。
2. 保留 `CONTEXT.md` 中"终态反馈事实"的 canonical 领域语义（`(CR-ID, spec-id)` 唯一标识、`_history.yml` 唯一终态、baseline `feedback[]` 正文与 history 输入摘要）；退役的是当前直接手写 `traceability.yml`/`tech-notes` 并发送与 canonical 语义冲突 inbox 的 prompt 契约。
3. feedback-writeback 的后续建设条件以 Tools `CUSTOM.md#CUSTOM-TODO-010` 为准；本轮不新增占位命令、空字段、兼容分支或新事务接口，不创建占位 Skill 满足 Agent 能力声明。
4. `reviewer-panel` 当前存在且有引用，本 CR 不删除、不退役。
5. 不创建 retired stub；删除后不得残留旧事件名 `feedback-writeback-done` 或对已删除 Skill 的 active 引用；`CUSTOM-TODO-010` 与历史事实性记录不属于 active 引用，必须保留。

### FR-08 职责边界与 ponytail 约束（规格 §4 / §13）

1. 本 CR 的全部改动只落在三类对象上，且不得越界：
   - **版本化脚本**：只增加 `evidence` 块的确定性转换与事实源修正，不做状态推进、审批或 Git 发布。
   - **`crctl`**：只增加 archive 写入前证据门；generator 身份路径保持 CR-2026-038 既有实现，只做回归确认；不做业务设计判断、不生成 LLM 评审结论。
   - **退役清理**：只删除 `change-impact-analysis`、`feedback-writeback` 及 active 引用，不新建替代模型。
2. 证据校验优先扩展现有 helper 模块，不新增独立模块；不建 generator registry、traceability handler、evidence writer factory、archive gate plugin 或通用 YAML patch。
3. 复用既有 durable transaction、review-record、writeback manifest、YAML matcher、Git adapter 与测试 fixture；不为证据门引入新的锁、journal、write-set、run-id 或恢复协议。
4. 所有跨行解析、digest 输入和文件读取先做 CRLF→LF 规范化；解析失败硬失败，禁止静默降级（对齐工程纪律第 1 条）。
5. Agent、Pipeline、Skill、README 在本 CR 只做引用收敛（删除退役能力声明），不复制证据算法、状态机副本或受控文件写入逻辑；其更大范围文本收敛由实施 CR 5（CR-2026-042）承担，本 CR 不越界。

## 5. 非功能需求

- **可信性**：baseline 每个新 milestone 的证据摘要必须可复算；archive 只接受证据齐全且 digest 匹配的 CR。
- **原子性**：archive 证据门在既有 lock 内、新建或修改 journal/write-set 之前执行；证据校验失败释放 lock，不创建或修改 journal，零 authority 写入、零审计事件。
- **可恢复性**：证据缺失/漂移返回结构化错误并指明缺项，补齐后以同一 `crctl archive` 命令重试；不允许手改 `_backlog.yml`/`cr.md`/`approval.yml`/`traceability.yml`/journal 绕过。
- **可审计性**：证据只记录状态结论、相对路径与 digest，不复制完整报告/grant/commit 明细；历史 milestone 逐字节保留。
- **跨平台性**：digest 与解析在 Windows/Ubuntu 上对 CRLF/LF 一致；canonical 输出使用 LF。
- **可测试性**：至少覆盖证据生成、四类证据校验、digest 漂移、路径非法、状态不通过、历史段字节不变、master 回退拒绝、generator hash 拒绝和退役引用零残留。
- **极简性**：不新增 schema registry、错误码中心、通用 traceability 接口、事务框架、数据库或强授权字符串模型；不新增 npm 依赖。

## 6. 验收标准

- **AC-01（FR-01）**：`writeback-traceability` 对新 milestone 注入 `evidence` 块，`test`/`reviews`（四份）/`approval`/`merge` 七项齐全；每项含状态结论、相对路径与 LF canonical digest；不存在完整报告/grant/commit 明细复制。
- **AC-02（FR-01/02）**：证据全部从 canonical 文件机械读取；修改任一 canonical 文件后其 digest 必然不匹配；CRLF 与 LF 版本在 Windows/Ubuntu 得到相同 digest。
- **AC-03（FR-02）**：从 `dir-graph.yaml#repositories` 删除 `tools` 条目后，generator 对含 `tools` 的 CR 硬失败，不回退 `master`；`merge-commits.yml` 缺失/重复/字段不全硬失败。
- **AC-04（FR-02）**：generator 源码、注释与错误文案中不再出现"来源为 `_backlog.yml`"的 merge 声明；`fromBacklog` 变量名与旧错误文案已清除。
- **AC-05（FR-03）**：既有 `baseline/tasks/traceability` 固定映射与真实脚本 hash 回归测试通过；manifest 自报 hash 不匹配时 `writeback-apply` 拒绝 candidate；生产代码无变化，除非测试复现既有缺陷。
- **AC-06（FR-04）**：证据齐全且可复算时 `crctl archive` 正常归档；当前 CR milestone/evidence 重复、路径指向其他 CR、缺任一证据、`verdict`/`status` 非通过、路径非法或 digest 漂移时，在既有 lock 内、新建或修改 journal 前硬失败，不创建/修改 journal，不产生 authority 写入和审计。
- **AC-07（FR-04）**：archive 证据门复用 generator 的确定性校验函数（同一函数、同一判据）；approval 门从 `approval.yml` 验证四个必需 grant，merge 门从 `merge-commits.yml` 验证当前 CR 合并事实；rejected/withdrawn 以及已 commit/push 或进入 cleanup/complete 的恢复不执行 writing-back 证据门，pre-authority journal 仍必须校验。
- **AC-08（FR-05）**：既有历史 milestone 段逐字节不变（含 CR-2026-038/039/040 已写入的 `status: writing-back` 段）；历史段缺 `evidence` 不报错；新 milestone 不含 `status` 字段，不含状态机外状态。
- **AC-09（FR-06）**：`skills/review/change-impact-analysis/SKILL.md` 已删除；`skills/_index.yml`、矩阵、Agent、`dir-graph.yaml` hint、README 与当前使用指南中零 active 引用；`review-alignment` 中 AL-07 与 stale 依赖已移除；历史报告/快照无需字符串清零。
- **AC-10（FR-07）**：`skills/cr/feedback-writeback/SKILL.md` 已删除；索引、矩阵、Agent、README、当前使用指南中零 active 引用；`inbox-emit` allowlist 中 `feedback-writeback-done` 已移除；`CONTEXT.md` 终态反馈事实、`CUSTOM.md#CUSTOM-TODO-010` 与历史记录保留，且未新增占位实现。
- **AC-11（FR-08）**：新增代码只落于版本化脚本（确定性转换）与 `crctl`（证据门）；generator 身份路径只做既有回归确认；不存在新独立模块、registry、handler、factory 或第二事务框架。
- **AC-12（工程质量）**：现有 crctl、writeback、merge、checkpoint、archive、review-record 回归测试保持通过；新增证据生成、证据门、digest、master 回退、历史段字节保留与退役引用测试，以及既有 generator hash 回归测试，在 Ubuntu 与 Windows 均通过；不引入新的生产依赖。

## 7. 成功指标

- baseline `traceability.yml` 的每个新 milestone 均含最小且可复算的 test/reviews/approval/merge 证据摘要；历史 milestone 字节不变。
- 证据缺失、漂移或状态未通过的 CR 无法通过 `crctl archive`；归档证据门与 generator 共用同一确定性校验函数。
- traceability generator 不再存在 `master` 回退、`_backlog.yml` 来源声明或 generator 自报 hash 信任。
- `change-impact-analysis` 与 `feedback-writeback` 在 Skills 索引、矩阵、Agent、README、dir-graph hint 与 inbox allowlist 中零 active 引用；`CONTEXT.md` 终态反馈事实领域模型与 `CUSTOM-TODO-010` 保留。
- CR-2026-041 的实现不增加第二套事务框架、状态机、账本模型、schema registry 或通用 traceability 平台。

## 8. 依赖与风险

- **依赖**：Tools 当前 `crctl` 的 durable transaction、archive 四账本事务、writeback-apply manifest/CAS、review-record、`merge-commits.yml`、`approval.yml`、`test-report.md` 机器区与既有测试 fixture；`writeback-traceability.mjs`、`writeback-prd-sdd.mjs`、`writeback-tasks.mjs` 的既有契约；`CONTEXT.md` 终态反馈事实与 `CUSTOM.md#CUSTOM-TODO-010`。
- **风险 R-01：证据门破坏既有归档路径**。证据门在既有 archive lock 内、任何新 journal/authority 写入前检查当前 CR milestone；仅已 commit/push 或进入 cleanup/complete 的恢复，以及无 writeback milestone 的 rejected/withdrawn 路径跳过，pre-authority journal 仍校验且失败时保持不变。
- **风险 R-02：digest 跨平台漂移**。canonical 文件可能含 CRLF；digest 输入必须先规范化 LF，并在 Windows/Ubuntu 双跑断言一致。
- **风险 R-03：退役清理不彻底或误删历史**。静态扫描必须证明索引、矩阵、Agent、README、dir-graph hint、inbox allowlist 与当前使用指南中零 active 引用，同时允许 `CUSTOM-TODO-010` 与历史报告/快照的事实性提及；禁止保留 retired stub 或旧事件名。
- **风险 R-04：新 milestone 无 status 后归档门定位**。证据门必须按 `- cr: {CR-ID}` 定位 milestone，而非依赖 `status` 字段；历史 `status: writing-back` 段仍按 opaque 保留。
- **风险 R-05：误改既有 generator 路径**。CR-2026-038 已实现固定映射与真实脚本 hash 校验；本 CR 仅回归确认，除非复现缺陷不得改写该路径。
- **风险 R-06：feedback 领域模型误删**。退役的是 prompt 契约，不是 `CONTEXT.md` 领域语义；删除 Skill 时不得连带删除 `CUSTOM-TODO-010` 或领域定义。

## 9. 范围排除

- 不建设通用事务管理器、通用 traceability 写入接口、schema registry、错误码注册中心、测试运行平台或 workflow engine。
- 不建立 impact/stale/perspective/change-log 模型；不实现 feedback 终态写入链、占位命令或兼容分支。
- 不建立通用 `traceability-record --kind ...` 接口、generator plugin registry 或 archive gate plugin。
- 不重写历史 traceability milestone，不为历史数据制造伪 run-id、伪 digest 或伪证据。
- 不复制完整测试报告、review annotation、approval grant 或 merge commit 明细进 baseline。
- 不改变 `reviewer-panel`、`review-alignment` 的既有职责（除移除 stale 依赖外），不删除其他 active Skill。
- 不修改 CR-2026-041 之外的生命周期切片：writeback 原子化、证据规范化、结构化测试闭环、职责边界清理与 Phase E 端到端验收均不在本 CR 实施范围。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘在本 CR 的 requirement worktree。

## 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-15 | v0.1.0 | Ray | 初始草稿：最小证据摘要、事实源修正、generator 身份、archive 证据门、历史段 opaque、双 Skill 退役与职责边界 |
| 2026-08-15 | v0.1.1 | Ray | 按需求评审回修：generator 固定映射/hash 改为复用既有能力；archive 证据门收敛到既有 lock 内、新 journal 前；补重复/跨 CR 路径与 active 引用边界 |

## Workspace 基线新鲜度与 CR Worktree 同步治理（v0.20.4 · CR-2026-043）

## 1. 概述

当前 `crctl workspace inspect/ensure` 能判断 CR worktree 是否存在、已注册、干净且位于正确分支，但不会判断该 worktree 是否已经包含 fetch 后的最新 `origin/{trunk}`。因此，一个分类为 `healthy` 的 worktree 仍可能基于旧 trunk 开始实施，直到代码评审或最终 merge 才暴露冲突，导致测试、评审和审批证据失效并重复执行。

本 CR 增加一项独立的 workspace baseline freshness 能力：

1. 对每个 active repository 比较 CR worktree HEAD 与 fetch 后捕获的 `origin/{trunk}` SHA，返回 `fresh`、`behind-clean`、`diverged` 或 `unknown`。
2. 只对没有 CR 独有提交、没有本地改动的 `behind-clean` worktree 提供显式、可审计的 fast-forward 同步。
3. 在 `implement-code` 前和 `review-code` 前执行 freshness gate；评审前发生安全同步后，复用既有 reviewLoop 重建实现、测试、checkpoint 和评审证据。
4. dirty、diverged、错误分支、路径身份异常或 Git 事实不确定时硬阻断，不覆盖用户工作。

本 CR 不是新事务平台。实现必须复用现有 workspace resolver、基础分类、durable transaction、lock/journal/audit、受控 Git、checkpoint、release-subjects 和 reviewLoop，只做满足上述行为所需的最小改造。

## 2. 目标逻辑架构

### 2.1 Ponytail 优先级

本 CR 的设计和实施必须按以下顺序选择能力，并在首个足够方案处停止：

1. 复用现有能力；
2. Node 标准库；
3. 原生 Git/文件 API；
4. 已有依赖；
5. 一行代码；
6. 最小新增代码。

不得为未来可能出现的同步场景预建通用分支编排、插件、服务或账本。

### 2.2 模块职责边界

| 模块 | 应拥有 | 不应拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

### 2.3 已经解决的基础设施

以下能力已经存在，本 CR 只复用，不得复制或替换：

| 已有能力 | 当前事实 | 本 CR 的复用方式 |
|---|---|---|
| Repository/worktree resolver | `resolveRepositories` 从 `dir-graph.yaml#repositories` 解析 active repo、trunk、worktree root，并按 repo id 稳定排序 | 作为 repository、trunk 和 worktree 路径的唯一来源 |
| Workspace 基础分类 | `classifyRepoWorkspace` 已返回 `healthy`、`dirty`、`wrong-branch`、`missing`、`branch-only`、`remote-only`、`path-unregistered` | freshness 作为第二层关系，不重定义基础分类；`ensureRepoWorkspace` 行为保持不变 |
| 受控 Git | `gitRun/gitMust` 已使用 argv 与 `shell:false`，事务处理器独占 Git 副作用 | 复用 fetch、ancestry 判断和固定形态的 `merge --ff-only` |
| Durable transaction | durable-tx 已有 `workspace` operation、scope lock、journal envelope、故障恢复和只向前写入基础能力 | 同步沿用现有 operation，不增加 WAL、事务协议或补偿框架 |
| Audit 与结构化错误 | crctl 命令层已有统一 audit 和 `TxError` 输出 | 记录同步、阻断、竞态和恢复事实，不新建 workspace ledger |
| Source 发布与重核 | checkpoint、review annotation、approval release-subjects 和 merge 已绑定/重核 source SHA | freshness/sync 不发布远端 requirement branch，不替代最终 source 重核 |
| Pipeline 自修复 | code-implementation 已有测试与代码评审 reviewLoop、`replayNodes` 和失败中止 | 评审前同步后扩展既有重放链，不创建第二套 loop |

### 2.4 本次应复用的最小改造

| 最小改造 | 归属 | 说明 |
|---|---|---|
| Freshness 第二层分类 | `crctl` 现有 workspace transaction 模块 | 基于基础分类和原生 Git ancestry 返回四类关系及 SHA 事实 |
| 两个窄 CLI 入口 | `crctl workspace` | 增加只读业务检查 `freshness` 与显式 fast-forward `sync` |
| 一个窄 Skill | `skills/sync/workspace-freshness` | 根据 crctl 结构化结果决定继续、条件同步、回修或人工处理；不实现 Git/事务算法 |
| 两个 Pipeline gate | `code-implementation` | 分别位于 `implement-code` 前和 `review-code` 前；评审回修复用既有 reviewLoop |
| 最小契约与行为测试 | 现有测试体系 | 覆盖分类、保护、幂等、竞态、恢复和 Pipeline/Skill 边界 |
| 一段人读说明 | README | 说明入口和失败后的人工动作，链接到 Skill/crctl 权威契约 |

本 CR 不新增依赖、数据库、daemon、branch manager、自动 rebase、冲突解决器、远端 requirement 分支发布器、版本化转换脚本或第二套事务框架。

## 3. 用户故事

- **US-01 开发负责人**：希望在开始实施前确认每个参与仓的 CR worktree 已包含最新 trunk；若只是干净落后，希望通过显式安全同步后继续。
- **US-02 代码评审者**：希望评审开始前重新确认 source 基线新鲜；若同步改变了 source，希望实现、测试和 checkpoint 证据先重建，再进入评审。
- **US-03 CR 协作者**：希望 dirty、diverged、错误分支或身份不明的 worktree 被保守阻断，任何自动动作都不能 reset、stash、rebase、覆盖或删除本地工作。
- **US-04 Tools 维护者**：希望 freshness 复用现有 resolver、workspace transaction、受控 Git 和 reviewLoop，不维护第二套状态、Git 或事务实现。
- **US-05 审计者**：希望同步的 before/target/after SHA、结果和失败原因可在现有 journal/audit 中追溯，并能从中断点安全重试。

## 4. 功能需求

### FR-01 分层 freshness 分类

1. Freshness 必须是独立于 `workspaceClassification` 的第二层关系，不修改现有基础分类语义。
2. 仅当 worktree 已注册、当前分支正确、工作区 clean，且 HEAD 与 fetch 后的 trunk SHA 均可确认时，才执行 ancestry 判断：
   - trunk SHA 等于 HEAD，或 trunk 是 HEAD 的祖先：`fresh`；
   - HEAD 是 trunk 的祖先且两者不等：`behind-clean`；
   - 双方互不为祖先：`diverged`；
   - 基础 workspace 不可比较或 Git 事实不完整：`unknown`。
3. `fresh` 必须包含 CR 分支仅 ahead trunk 的正常开发状态；不得要求 HEAD 与 trunk 完全相等。
4. 每仓结构化结果至少包含 repo id、trunk ref/SHA、CR branch/HEAD、worktree path、基础分类、freshness、dirty、`canFastForward` 和阻断原因。
5. 第一版不计算 ahead/behind commit count，不使用时间戳、commit message 或字符串启发式猜测 ancestry。

### FR-02 只读业务检查

1. `crctl workspace freshness <CR-ID>` 必须从目标 workspace 的 repository resolver 读取全部 active repositories 和各自 trunk，不接受调用方传入任意 repo、branch、ref 或 path。
2. 命令必须对每个 active repository fetch `origin`，以本次捕获的 `refs/remotes/origin/{trunk}` SHA 作为比较目标，并按 repo id 稳定输出结果。
3. freshness 检查不得修改 worktree 文件、local/remote requirement branch、CR 状态、审批或业务账本。fetch 更新 remote-tracking refs/FETCH_HEAD 属于明确允许的 Git 元数据变化。
4. repository 声明、fetch、HEAD、trunk 或 ancestry 事实无法确认时必须结构化失败或返回 `unknown`，不得降级为 `fresh`、`healthy` 或空结果。
5. 成功的重复检查不逐次写持久 audit；阻断和技术失败仍按现有审计规则记录。

### FR-03 显式安全同步

1. `crctl workspace sync <CR-ID>` 必须复用 resolver、workspace 基础分类、durable-tx 的 `workspace` operation、scope lock、journal 和 audit。
2. sync 在任何 Git 写入前必须对全部 active repositories 执行一次完整 preflight。任一仓为 dirty、diverged、unknown、wrong-branch、missing、branch-only、remote-only、path-unregistered 或 trunk 不可确认时，全仓零写入并硬失败。
3. 只有 `behind-clean` 仓允许同步；唯一允许的 worktree 写操作是等价于 `git merge --ff-only <captured-trunk-sha>` 的受控 Git 调用。已经 `fresh` 的仓保持 `unchanged`。
4. 调用方不得传入任意 branch、refspec、path、merge strategy、reset、force、stash、rebase 或 push 参数。
5. 每仓执行前必须重核当前分支、clean 状态、HEAD 和 captured trunk SHA；任一事实变化时停止后续写入并返回 expected/actual 事实。
6. 同步后 `afterSha` 必须等于 captured trunk SHA。sync 不 push requirement branch，不修改 CR 状态、审批、review annotation 或业务账本。

### FR-04 幂等、竞态和只向前恢复

1. 同一 CR、同一 before/target 事实重复执行必须幂等；已到达 target SHA 的仓返回 `unchanged/confirmed`，不得生成额外提交。
2. 全仓 preflight 通过后，按 repo id 稳定顺序逐仓 fast-forward，并在每仓完成后持久化既有 journal/audit 事实。
3. 运行期第 N 个仓失败时，停止第 N+1 个及之后的仓；已完成仓保持 fast-forward 结果，不执行 reset、revert 或反向补偿。
4. 中断后重跑同一命令时，已确认完成的仓不重复写，未执行且事实未漂移的仓可继续。
5. trunk、HEAD、branch、dirty 状态、repository graph 或 journal 发生漂移时硬失败，并返回可执行的恢复提示；不得删除 journal、清理用户文件或猜测继续。
6. 单仓 fast-forward 使用原生 Git 原子语义；多仓只承诺稳定顺序、失败停止、逐仓持久化和只向前恢复，不承诺跨仓 ACID 回滚。

### FR-05 生命周期 gate 与 reviewLoop

1. `code-implementation` 必须增加两个 `workspace-freshness` Skill 节点：一个位于 `implement-code` 前，一个位于 `review-code` 前。
2. implement-start gate 的业务路由：
   - 全仓 `fresh`：继续 `implement-code`；
   - 存在 `behind-clean` 且其余仓可比较：显式调用 sync，重核全仓 `fresh` 后继续；
   - 存在 `diverged`、`unknown` 或基础 workspace 阻断：abort，不进入实施。
3. review-start gate 的业务路由：
   - 全仓 `fresh`：继续 `review-code`；
   - 存在 `behind-clean`：显式调用 sync；同步成功后不得直接评审，必须复用代码评审既有 reviewLoop 重放实现、测试、checkpoint、freshness 和 review-code；
   - 存在不可自动同步的结果：abort 并输出人工处理所需事实，不进行无意义的自动重试。
4. 代码评审 reviewLoop 的重放顺序必须包含：`implement-code -> write-test-report -> push-progress -> workspace-freshness(review-start) -> review-code`。
5. 不增加 `write-test-report`、checkpoint 或审批前的额外 freshness gate。`approve-code` 与 merge 继续使用既有 release-subjects/source SHA 重核。
6. Pipeline 只拥有节点顺序、输入传递、reviewLoop 和失败中止；不得出现 Git 命令、ancestry 算法、journal/audit 写入或 Skill 全文复制。

### FR-06 Skill、Agent、crctl 与文档采用

1. 新增一个 active `workspace-freshness` Skill，由 `system-orchestrator` 唯一 owns，`dev-agent` can-call；不新增 Agent。
2. Skill 输入只包含 `cr_id`、workspace 和 gate 场景；Skill 负责调用 freshness、按结构化结果做业务路由，并在允许时调用 sync。
3. Skill 不接受任意 ref/path/branch/strategy，不实现 Git、锁、journal、CAS、状态推进、账本或审计算法。
4. `crctl` 负责确定性 workspace/Git 事实、受控同步、竞态重核、持久恢复与结构化错误；不得判断需求价值、TASK 是否合理或 LLM 评审是否通过。
5. Agent 只根据职责和 `crctl next` 选择 Pipeline/Skill、传递 CR-ID/workspace 并决定是否需要人工介入；不得保存状态机副本或直接写受控文件。
6. 本 CR 不新增版本化脚本。README 只增加命令入口、结果含义、人工处理动作和权威链接，不复制分类算法、恢复状态机或错误实现细节。
7. 新增 Skill 后必须同步 `skills/_index.yml` 与 `agent-skill-matrix.yml`；Pipeline 节点数变化必须同步 `_index.yml`，并通过现有契约检查。

## 5. 非功能需求

- **安全性**：dirty、diverged、错误分支、路径身份异常和事实不确定场景必须零覆盖；禁止 reset、clean、stash、rebase、force、普通 merge 和自动冲突解决。
- **一致性**：repository、trunk、worktree 只由 `dir-graph.yaml` resolver 解析；freshness 与基础 workspace 分类分层，不创建竞争事实源。
- **可恢复性**：同步复用现有 durable transaction、lock/journal 和只向前恢复；多仓部分进度可重放，不做补偿回滚。
- **可审计性**：sync、阻断和竞态记录 CR-ID、repo、branch、before/target/after SHA、分类、结果、actor、时间和 transaction id；不新建 workspace ledger。
- **跨平台性**：Windows 与 Linux 的路径身份、worktree registration、CRLF/LF 和 Git 输出解析行为一致；所有文本先 CRLF 转 LF，逐行解析使用 `\r?\n`，解析失败硬失败。
- **性能**：每个 gate 对每个 active repository 至多执行必要的 fetch、基础分类和 ancestry 检查；不增加 daemon、缓存、后台扫描或 commit count 计算。
- **兼容性**：`ensureRepoWorkspace`、`pull-progress`、checkpoint、release-subjects、状态机和远端 requirement branch 语义保持不变。
- **依赖约束**：不新增生产依赖；优先使用现有 helper、Node 标准库和原生 Git。

## 6. 验收标准

- **AC-01（FR-01）**：HEAD 等于 trunk、以及 CR HEAD 仅 ahead trunk 时，均稳定分类为 `fresh`。
- **AC-02（FR-01/03）**：HEAD 是 trunk 祖先且两者不等时分类为 `behind-clean`；显式 sync 只通过 ff-only 到达 captured trunk SHA，结果为 `fast-forwarded`。
- **AC-03（FR-01/03）**：dirty、wrong-branch、missing、branch-only、remote-only、path-unregistered 复用现有基础分类，freshness 为 `unknown`，sync 全仓零写入。
- **AC-04（FR-01/03）**：CR 分支与 trunk 双方均有独有提交时分类为 `diverged`；sync 不执行 Git 写入，并返回人工处理所需的 repo、path 与 SHA。
- **AC-05（FR-02）**：freshness 对 active repositories 按 id 稳定输出，使用 fetch 后捕获的 `origin/{trunk}` SHA；除 remote-tracking 元数据外，不修改 worktree、requirement branch、状态、审批或账本。
- **AC-06（FR-03/04）**：任一仓在全仓 preflight 阶段阻断时，没有仓发生 fast-forward；preflight 后 trunk、HEAD、branch 或 dirty 事实变化时，停止后续仓并返回 expected/actual。
- **AC-07（FR-04）**：同一输入重跑幂等，不重复提交；多仓第 N 仓中断后重跑保留已完成仓、继续未完成仓，不执行 reset/revert 或删除用户文件。
- **AC-08（FR-05）**：implement-code 前非 fresh worktree 不会直接进入实施；`behind-clean` 经显式 sync 并重核 fresh 后方可继续。
- **AC-09（FR-05）**：实施期间 trunk 前进时，review-code 前 gate 阻止旧 source 进入评审；behind-clean 同步后按既有 reviewLoop 重放实现、测试、checkpoint、freshness 和评审。
- **AC-10（FR-05/06）**：静态契约检查证明 Pipeline 不含 Git/journal 算法，Skill 不含原子账本/Git 算法，Agent 不含状态机/受控写入，README 不复制可执行细节事实源。
- **AC-11（NFR）**：Windows 与 Linux 的 fresh/behind-clean/diverged/unknown、dirty、路径身份、CRLF 和 worktree registration 测试通过；解析失败不会静默返回空结果或 fresh。
- **AC-12（全范围）**：现有 workspace resolver、register/resume/cleanup、checkpoint、test、reviewLoop、approve 和 merge 回归测试保持通过；无新增生产依赖、状态、业务账本、版本化脚本或事务框架。

## 7. 成功指标

- 进入 `implement-code` 和 `review-code` 的 CR worktree 均有可验证的最新 trunk ancestry 事实。
- 可证明安全的 `behind-clean` 场景能够通过显式 ff-only 同步解决；不可证明安全的场景保持零覆盖并给出结构化阻断。
- 因旧 trunk 直到最终 merge 才发现的冲突和由此触发的重复测试、评审、审批显著减少。
- workspace 同步事实全部落在既有 journal/audit，未出现第二套 transaction、ledger、状态机或远端分支发布路径。
- Agent、Pipeline、Skill、crctl、版本化脚本和 README 的职责边界通过静态契约测试持续成立。

## 8. 依赖与风险

- **依赖**：Tools 当前 repository/worktree resolver、`classifyRepoWorkspace`、`gitRun/gitMust`、durable-tx `workspace` operation、audit、checkpoint、release-subjects、`workspace inspect/ensure/cleanup` 和 code-implementation reviewLoop。
- **风险 R-01：把 ahead-only 错判为 stale**。fresh 必须以“trunk 是 CR HEAD 的祖先”为核心判据，正常 CR 独有提交不得被阻断。
- **风险 R-02：同步覆盖本地工作**。只有基础 workspace healthy、clean 且 HEAD 是 trunk 祖先时允许 ff-only；其他场景全仓 preflight 硬失败。
- **风险 R-03：fetch 后事实变化**。sync 必须在锁内 preflight，并在每仓写入前重核 trunk、HEAD、branch 和 dirty 状态；漂移时停止，不使用旧事实继续。
- **风险 R-04：多仓部分完成被误当作失败回滚**。journal 明确记录每仓进度；恢复只向前，不通过 reset/revert 制造补偿风险。
- **风险 R-05：review gate 同步后证据失效**。同步后不得直接进入 review-code，必须重建实现验证、测试报告和 checkpoint，再重新执行 freshness 与评审。
- **风险 R-06：职责扩散**。契约测试必须约束 Pipeline、Skill、Agent 和 README 不复制 crctl 算法，且 `ensureRepoWorkspace`、`pull-progress` 与 checkpoint 不被扩权。
- **风险 R-07：网络不可用**。无法 fetch 或确认 trunk 时返回 `unknown`/结构化失败并阻断；不使用过期 remote-tracking ref 猜测 fresh。

## 9. 范围排除

- 不建设通用分支同步平台、branch manager、daemon、后台扫描、缓存或数据库。
- 不自动 merge、rebase 或解决冲突；不执行 reset、clean、stash、force push、普通 merge 或补偿性 revert。
- 不修改状态机、CR ledger schema、approval、review annotation、release-subjects 或 merge 的既有事实源。
- 不检查、同步或发布远端 `requirement/{CR-ID}` 分支；该职责继续属于 push-progress、pull-progress 和 checkpoint。
- 不修改 `ensureRepoWorkspace` 的 register、resume、inspect 或 cleanup 行为。
- 不计算 ahead/behind commit count，不增加任意 ref/path/strategy 参数。
- 不新增 Agent、版本化转换脚本、feature flag、观察期账本、错误码 registry、插件系统或第二套事务抽象。
- 不增加 write-test-report、checkpoint 或审批前 freshness gate；本次只接入 implement-code 前和 review-code 前两处。
- 不承诺 macOS 全量验收矩阵；第一版覆盖当前 Windows 与 Linux 运行边界。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘在 CR-2026-043 的 knowledge-base requirement worktree。

## 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.1.0 | Ray | 初始草稿：freshness 分层、显式 ff-only 同步、双生命周期 gate、既有 reviewLoop 重放及职责边界 |

## tools CR 生命周期最小优化 5/5 — 职责边界清理（vtbd · CR-2026-042）

## 1. 概述

本 CR 是《tools-cr-lifecycle-minimal-optimization-spec.md》固定拆分的第 5 条实施 CR，只落实规格 FR-14、FR-15、FR-16。当前 Tools 包已经具备 CR 生命周期所需的状态机、门禁、CAS、人工审批、durable transaction、跨仓 merge、checkpoint、review-record、结构化测试、candidate-only writeback 和 archive；问题不是缺少执行基础设施，而是 Agent、Pipeline、Skill、README 与 CI 中仍保留重复、过时或越界的文本契约。

本 CR 通过删除和收缩完成治理，不新增事务框架、状态机、账本模型、通用 Pipeline 解释器或 workflow engine。所有实现决策按以下 ponytail 优先级选择：

1. 复用现有能力；
2. 标准库；
3. 原生 Git/文件 API；
4. 已有依赖；
5. 一行代码；
6. 最小新增代码。

## 2. 目标逻辑架构

| 模块 | 应拥有 | 不应拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览、入口、恢复说明和权威链接 | 另一份可执行细节事实源 |

### 2.1 已解决基础设施（只复用，不重做）

| 能力 | 当前状态 | 本 CR 处理 |
|---|---|---|
| 状态、门禁、CAS 与人工审批 | `crctl status/next/advance/approve` 已有权威实现 | 复用；不改状态机、gates 或审批算法 |
| durable transaction | 已有 lock、journal、write-set、commit/push 与恢复 | 复用；不新增事务层 |
| register / workspace / checkpoint / merge / writeback / archive | 已有单一深原语和结构化恢复语义 | 只删除调用方中的算法副本，不改生产实现 |
| review canonical 合同 | CR-2026-039 已统一为 `verdict`、`blockers`、`suggestions`、`dimensions`、可选 `repair-target` | 只清理残留引用，不重做字段模型 |
| 结构化测试 | CR-2026-040 已由 `crctl test --plan` 负责机器证据，`write-test-report` 负责分析区 | 只收缩重复说明；不新增测试入口 |
| baseline 最小证据与 archive 证据门 | CR-2026-041 已由版本化脚本和 `crctl archive` 承担 | 只收缩重复说明；不改证据结构 |
| Agent/Skill 权限 | `agent-skill-matrix.yml` 已是机器可读事实源 | Agent 文档只引用，不复制权限表 |
| Pipeline 顺序与 reviewLoop | `pipeline-templates/*.pipeline.json` 已是机器可读事实源 | 保留编排；不建立解释器 |
| 治理脚本 | 已有 `lint-prompts.mjs`、`check-skill-matrix.mjs`、`check-agents-contract.mjs` 和测试 fixture | 原地扩展少量确定性规则 |

### 2.2 本次最小改造

| 改造点 | 最小处理 |
|---|---|
| Agent 文档越界 | 删除状态链、backlog 状态推断、Git/账本写入算法；保留定位、路由、职责与权限引用 |
| Pipeline prompt 越界 | 收缩为输入、一次 Skill/命令调用、结构化结果分类、reviewLoop 与失败动作 |
| Skill 越界 | 删除 journal/CAS/Git 深算法副本、手工 commit/push 配方和 CR write Skill 的失效 engineering-docs/MCP/validate-doc 引用 |
| 代码评审模型选择 | 删除 code Pipeline 的 `review_llm` 输入和“选择代码评审 LLM”人工暂停节点；由 Agent/runtime 在进入 Pipeline 前选择 runner |
| README 漂移 | 重写为人读总览、入口、Owner、审批、恢复和权威链接 |
| CI 重复 | 保留 `crctl-ci.yml`，删除重复的 `check-skill-matrix.yml` workflow；检查脚本继续由主 workflow 调用 |
| 防回潮 | 在现有 lint 与测试中增加少量确定性规则；Pipeline 只做 JSON.parse 与固定字段断言 |
| OpenWiki | 修改权威源后由现有 OpenWiki workflow 刷新引用；不手工维护另一套执行合同 |

## 3. 用户故事

- **US-01 Agent 维护者**：希望 Agent 文档只说明“何时路由到哪个 Pipeline/Skill”，不再复制状态机、Git 或受控账本算法。
- **US-02 Pipeline 维护者**：希望节点 prompt 只表达编排和失败路由，深原语内部变化不需要同步修改多份算法文本。
- **US-03 Skill 维护者**：希望 Skill 聚焦业务判断和输入输出，原子写入、提交、发布与恢复统一交给 `crctl`。
- **US-04 CR 执行者**：希望代码评审 runner 在进入 Pipeline 前由 Agent/runtime 选择，不因额外的人工暂停节点中断自动闭环。
- **US-05 Tools 使用者**：希望 README 能快速说明入口、Owner、人工审批与恢复方法，并明确指向权威事实源，而不是复制会漂移的实现细节。
- **US-06 Tools 维护者**：希望单一跨平台 CI 在相关契约变化时运行既有检查，并用小而确定的 lint 阻止越界文本回潮。

## 4. 功能需求

### FR-01 Agent 文档收敛（规格 FR-14）

1. active Agent 文档只保留角色定位、可处理意图、Pipeline/Skill 路由、人工决策边界和对 `agent-skill-matrix.yml` 的引用。
2. Agent 不保存完整或局部状态链，不从 `_backlog.yml` 推断 CR status；CR 当前状态与下一步统一调用 `crctl status/next` 或对应只读 Skill。
3. Agent 不描述 Git worktree、commit、push、merge、CAS、journal、受控账本字段拼接或受控文件落盘算法。
4. Agent 不声称直接写 `cr.md`、`_backlog.yml`、approval、review annotation、review-loop、traceability、specs 或 delivery 账本；写入必须路由到已登记 Skill / `crctl` 深原语。
5. 不在 Agent 文档复制矩阵的完整 owns/can-call/forbidden 清单；唯一权限事实源仍是 `agent-skill-matrix.yml`。
6. 不为追求统一格式新增 Agent 基类、模板引擎或生成器；仅编辑存在越界或过时文本的文档。

### FR-02 Pipeline prompt 收敛与 reviewer 暂停删除（规格 FR-14）

1. active Pipeline 的 Skill 节点 prompt 只保留：业务输入、调用的 Skill/公开命令、结构化结果分类、reviewLoop 输入/输出和失败中止/路由。
2. Pipeline 不展开 journal、CAS、write-set、candidate、manifest、lease、逐仓 Git、账本拼接或恢复算法；调用深原语时只传公开业务参数并消费公开结构化结果。
3. Pipeline 不手写受控文件内容，不要求模型直接编辑 `_backlog.yml`、`cr.md`、approval、review annotation、review-loop、traceability、specs 或 delivery 索引。
4. `code-implementation.pipeline.json` 删除 `review_llm` 输入和“选择代码评审 LLM”`human_approval` 节点；review runner 由 Agent/runtime 在进入 Pipeline 前选择，`review-code` 仍可在评审 `dimensions` 中记录实际 runner/model 作为事实。
5. 删除节点后保持原有 reviewLoop、PASS 后 checkpoint、代码人工审批和失败中止语义；同步 `pipeline-templates/_index.yml#nodes` 的实际节点数。
6. 不修改其他合法人工审批节点，不把 reviewer 选择改造成新 Skill、配置中心、runner registry 或状态字段。
7. Pipeline JSON 结构校验只使用 `JSON.parse` 与固定字段断言；不实现 prompt 语义解释器、通用 workflow runner 或符号执行器。

### FR-03 Skill 职责收敛（规格 FR-14）

1. CR 生命周期 Skill 只保留业务前置、业务判断、一次公开深原语调用、输入输出和失败语义；删除对 journal、CAS、merge、checkpoint、writeback、archive 内部算法的复述。
2. `review-code` 只读取真实 diff 与 canonical 测试证据并形成 LLM 评审结论，不执行或重新执行 lint/test/build；正式测试仍只有 `write-test-report -> crctl test --plan` 一条入口。
3. `write-test-report` 负责选择正式验证范围、生成临时结构化 plan、调用一次 `crctl test --plan` 并更新 marker 后分析区；不得直接写机器区、traceability tests 或 review-loop。
4. 三个生产 writeback Skill 各只调用一次 `crctl writeback-apply` 并解释结构化结果；不暴露或消费 generator、candidate、manifest、journal 或 Git 内部路径。
5. CR write Skill 删除失效的 engineering-docs、MCP、owClient、`_config.yml` 与 validate-doc 依赖声明；文档结构和 frontmatter 以各 Skill 当前明确合同为准。
6. write Skill 不输出手工 `git add/commit/push` 配方；需要提交或发布时调用现有 `crctl` 公开入口。
7. 不删除仍被规划等非 CR 流程真实使用的 `engineering-docs` 或 `validate-doc` Skill；本 CR 只删除 CR write 路径中的失效引用。

### FR-04 README 收敛为人读入口（规格 FR-15）

1. README 只保留：产品定位、概念生命周期、Owner 职责、8 条 active Pipeline/Skill 入口、人工审批方式、checkpoint/merge/archive 的人读区别、恢复命令和权威链接。
2. README 不复制完整状态转移表、节点 prompt、门禁表达式、账本字段、内部算法、完整错误码矩阵、动态测试数量或会漂移的默认值。
3. 状态机只展示概念阶段并链接 `dir-graph.yaml#change-request-track.state_machine`；Pipeline 节点和 reviewLoop 链接 `pipeline-templates/*.pipeline.json`；权限链接 `agent-skill-matrix.yml`。
4. README 用人读语言解释：checkpoint 是进度发布、merge 是多仓发布、operational workspace 是回写期工作区、`cleanup-pending` 表示终态已发布但资源清理未完成。
5. README 不成为执行入口的替代品；具体参数、结果字段和恢复错误以对应 Skill / `crctl` 合同为准。
6. 不在 README 维护 Agent/Skill 的完整权限矩阵、完整节点表或代码实现说明。

### FR-05 静态治理与 CI 收敛（规格 FR-16）

1. `.github/workflows/crctl-ci.yml` 保持唯一主治理 workflow；删除功能重复的 `.github/workflows/check-skill-matrix.yml`，但保留并继续调用 `check-skill-matrix.mjs` 和 `check-agents-contract.mjs`。
2. `crctl-ci.yml` 的 push/pull_request paths 至少覆盖：`README.md`、`AGENT-SKILL-MATRIX.md`、`agent-skill-matrix.yml`、`dir-graph.yaml`、`agents/**`、`skills/**`、`pipeline-templates/**`、`skills/shared/controlled-shell/rules.json` 和 workflow 自身。
3. 主 workflow 在 Ubuntu 与 Windows 上继续执行现有 crctl/writeback 测试、`lint-prompts`、Skill matrix、Agent contract 和 Pipeline JSON 检查。
4. 复用现有 `lint-prompts.mjs` 增加少量确定性规则，至少检测：已废弃公开命令/参数、与权威状态机不一致的字面量 trigger、受控文件手写指令、已退役 Skill 的 active 引用。
5. lint 读取文本后必须统一 CRLF→LF；权威状态机跨行解析失败必须硬失败，不得降级为空规则或静默跳过。
6. 新规则须有最小正/反例测试；不得建立通用 AST、schema registry、错误码 registry、Pipeline 解释器或自然语言语义分类器。
7. OpenWiki 引用更新通过现有 source + workflow 链路完成；`openwiki-update.yml` 不是治理 workflow，不在删除范围。

### FR-06 已解决能力保护与范围边界

1. CR-2026-038～041 已交付的生产行为只做回归保护，不在本 CR 重写或迁移。
2. review canonical 字段以 CR-2026-039 已有实现为准；只删除残留的废弃字段引用，不新增 ledger 或 schema。
3. 不修改 `crctl` 的状态、门禁、CAS、审批、事务、Git、测试、writeback 或 archive 生产算法；若静态治理需要读取权威声明，只通过既有 resolver/helper。
4. 不修改状态机数量、转移、gates、approval grant、reviewLoop 业务语义、traceability evidence 结构或 candidate 路径。
5. 不新增依赖；优先通过删除文本、复用现有检查器和 Node 标准库完成。

## 5. 非功能需求

- **NFR-01 极简性**：净效果以删除重复合同为主；不新增框架、registry、数据库、通用解释器、公共协议或占位能力。
- **NFR-02 单一事实源**：状态、权限、Pipeline、Skill、执行层和 README 的事实源边界与本 PRD第 2 节一致。
- **NFR-03 跨平台**：治理 workflow 与新增测试在 Ubuntu、Windows 上均通过；文本扫描对 LF/CRLF 等价。
- **NFR-04 可验证性**：每项收敛均有确定性扫描、JSON 固定断言或既有行为测试支撑，不依赖“人工看起来更短”。
- **NFR-05 兼容性**：删除重复说明不得改变现有公开命令、合法人工审批、reviewLoop 与深原语结构化结果。
- **NFR-06 可维护性**：README 和 Agent/Pipeline/Skill 通过链接权威文件减少同步面，不复制动态规模数字或实现细节。

## 6. 验收标准

- **AC-01（FR-01）**：active Agent 文档中不存在完整状态链、从 `_backlog.yml` 推断 status 的指令、Git 算法或受控账本手写算法；每个 Agent 仍能从角色、意图和矩阵引用确定合法路由。
- **AC-02（FR-02）**：active Pipeline prompt 中不存在 journal/CAS/write-set/candidate/manifest/lease/逐仓 Git 或受控账本拼接算法；节点仍明确输入、调用、结果分类、reviewLoop 与失败动作。
- **AC-03（FR-02）**：code Pipeline 不再声明 `review_llm` 输入或“选择代码评审 LLM”暂停节点；其节点数与 `_index.yml` 一致，reviewLoop、PASS 后 checkpoint、代码人工审批顺序保持成立。
- **AC-04（FR-03）**：`review-code` 零测试执行入口；`write-test-report` 只调用一次 `crctl test --plan` 并只拥有分析区；三个 writeback Skill 各只有一次公开 `writeback-apply` 调用且不暴露内部路径。
- **AC-05（FR-03）**：CR write Skill 中失效的 engineering-docs/MCP/owClient/`_config.yml`/validate-doc 引用和手工 `git add/commit/push` 配方为零；非 CR 流程仍在真实使用的通用 Skill 保留。
- **AC-06（FR-04）**：README 包含生命周期概念总览、Owner、入口、审批、恢复和权威链接；不含完整状态转移声明、节点 prompt、门禁表达式、内部算法、完整错误矩阵、动态测试数量或默认值副本。
- **AC-07（FR-04）**：README 对 checkpoint、merge、operational workspace、archive 与 cleanup-pending 的说明可由非实现维护者理解，且每项都链接到对应权威合同。
- **AC-08（FR-05）**：仓库只剩 `crctl-ci.yml` 一个主治理 workflow；`check-skill-matrix.yml` 已删除，两个检查脚本仍由主 workflow 调用；`openwiki-update.yml` 保留。
- **AC-09（FR-05）**：主 workflow 的 paths 覆盖 FR-05.2 全部路径，并在 Ubuntu/Windows 执行既有治理与测试套件。
- **AC-10（FR-05）**：新增 lint 正/反例证明废弃命令/参数、非法 trigger、受控文件手写和退役 Skill active 引用会被阻断，合法公开调用与历史事实性记录不误报；LF/CRLF 结果一致。
- **AC-11（FR-05）**：任一 Pipeline JSON 不可解析或缺固定必填字段时检查失败；实现中不存在通用解释器、符号执行或 prompt 语义分析。
- **AC-12（FR-06）**：`crctl` 生产算法、状态机、gates、approval、review canonical schema、test-report 机器区、writeback candidate/evidence/archive 语义无行为改动；相关既有测试全绿。
- **AC-13（全量）**：Agent、Pipeline、Skill、`crctl`、版本化脚本与 README 的实际改动分别落在第 2 节规定的职责内；全仓 active 合同不存在第二套事务框架、状态机、账本模型或 workflow engine。

## 7. 成功指标

- Agent、Pipeline、Skill 与 README 中重复状态机、Git/账本算法和深原语内部步骤的 active 文本引用降为 0。
- code Pipeline 少一个 reviewer 选择人工暂停节点，不影响 reviewLoop、checkpoint 或代码审批。
- 治理 CI 只有一个主 workflow，相关契约改动不会因 paths 漏项跳过检查。
- 新增防回潮仅扩展既有 lint/测试，不增加生产依赖、公共命令或长期接口。
- CR-2026-038～041 已解决的生产能力保持原实现与回归测试，不被本 CR 重新设计。

## 8. 依赖与风险

- **依赖**：CR-2026-038～041 已合入的 writeback、证据、测试与 archive 行为；现有 `agent-skill-matrix.yml`、Pipeline JSON、Skill 合同、`crctl`、lint 和 CI fixture。
- **风险 R-01 过度删除**：文本收缩可能删掉真实业务判断。处理方式是只删除执行层算法副本，保留业务前置、输入输出、结构化错误分类与 reviewLoop。
- **风险 R-02 lint 误报**：历史文档和反例可能包含禁用词。新规则限定 active Agent/Skill/Pipeline/README/CI 范围并沿用局部 `lint-prompts:ignore`，每条规则必须有合法反例测试。
- **风险 R-03 Pipeline 顺序回归**：删除 reviewer 节点会改变 node index。验收以 `node.ref` 和 kind 顺序断言，不依赖旧数组下标；同步 `_index.yml` 节点数。
- **风险 R-04 README 过薄**：删除细节后可能难以上手。必须保留入口、Owner、审批、恢复与四个关键概念的短说明，并链接权威合同。
- **风险 R-05 OpenWiki 漂移**：不手改生成页承载新事实；先改权威源，再由现有 workflow 刷新并检查旧命令/能力引用。

## 9. 范围排除

- 不实现来源规格 FR-01～FR-13；这些属于 CR-2026-038～041，当前只做回归保护。
- 不执行 Phase E 跨 CR 端到端验收；Phase E 是五条实施 CR 完成后的独立验收活动。
- 不改 `crctl` 状态机、门禁、事务、审批、Git、测试、writeback、archive 或账本 schema。
- 不新建通用事务管理器、workflow engine、Pipeline 解释器、runner registry、schema/error-code registry、数据库或权限服务。
- 不删除 `engineering-docs`、`validate-doc`、reviewer-panel 或 OpenWiki workflow；只清理本 CR 范围内失效或重复的 active 引用。
- 不批量改写历史 CR、历史 traceability、历史评审记录或 OpenWiki 历史快照。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘于 CR-2026-042 knowledge-base worktree。

## 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.1.0 | Ray | 初始草稿：职责边界、已解决基础设施、本次最小改造、README/CI/lint 收敛与 reviewer 暂停删除 |

## Tools 本地业务门禁、远端发布与人工审批确认方案（v0.20.5 · CR-2026-044）

## 1. 概述

当前 Tools 的 release snapshot 校验同时回答两个语义不同的问题：本地内容是否仍是被评审的内容，以及该内容是否已发布到远端 requirement ref。现有 `buildReleaseSubjects` 会 fetch 并要求远端 requirement ref 等于本地 HEAD，`verifyReleaseSubjects` 也会把远端 ref 滞后归入 code drift。这使网络不可用、checkpoint 尚未完成或远端 ref 暂时落后时，本地完整有效的评审和审批证据仍可能被拒绝，甚至在 merge 前错误触发 `code-approved -> developing` 回退。

本 CR 建立清晰边界：

1. status、gate、review-record、approve 的业务证据只由当前 Operational Workspace 与各仓本地 CR worktree 决定。
2. checkpoint、resume、workspace freshness/sync、merge、writeback、archive 才读取远端发布事实。
3. 远端 requirement ref 缺失或滞后只表示发布未完成，不表示本地评审证据失效，也不得触发业务状态回退。
4. 只有本地已审批 source、TASK 或受控 artifact 真实漂移时，才沿用既有回修或硬阻断语义。
5. 四个人工审批阶段在共享 TTY 入口统一接受 trim 后、大小写不敏感的 `y|yes`。

本 CR 只调整既有能力之间的职责边界，不建设新框架。

## 2. 目标逻辑架构

### 2.1 Ponytail 优先级

设计和实施必须按以下顺序选择方案，并在首个足够方案处停止：

1. 复用现有能力；
2. Node 标准库；
3. 原生 Git/文件 API；
4. 已有依赖；
5. 一行代码；
6. 最小新增代码。

不得为未来可能出现的发布、审批或 Pipeline 场景预建通用 verifier registry、publication registry、adapter、provider、缓存、daemon、数据库或第二套事务框架。

### 2.2 模块职责边界

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

上述边界必须由现有契约测试或最小增量静态检查持续约束；不得只写在说明文档中。

## 3. 已经解决的基础设施

以下能力已经存在，本 CR 只复用，不复制、不替换：

| 已有能力 | 当前职责 | 本 CR 的复用方式 |
|---|---|---|
| Operational/Installation Workspace 分离 | 解析实际业务工作区与 tools 安装位置 | 继续作为所有 Pipeline 和 Skill 的路径基础 |
| Repository/worktree resolver | 从目标 workspace 的 `dir-graph.yaml#repositories` 解析 active repo、trunk 与 CR worktree | 作为 repo map 和路径的唯一来源 |
| `classifyRepoWorkspace` | 分类 missing、dirty、wrong-branch、path-unregistered、healthy 等本地状态 | release snapshot 构造与重核统一复用；仅 healthy 可继续 |
| 状态机与 gates | `dir-graph.yaml` 和 `gates.json` 声明合法转换与证据门禁 | 状态与转换数量保持不变，不引入 publication 状态 |
| review-record 与 approval | annotation、review-loop、traceability、approval 与 status 的受控写入 | 保留既有证据摘要、原子提交、驳回回退和签名审批 |
| release-subjects v1 | repo reviewed SHA、预期 remote ref 名、受控 artifact digest | schema 不变，只收窄 snapshot 构造和重核的事实来源 |
| checkpoint | source commit、requirement ref 发布、lease、远端确认、metadata 与恢复 | 作为远端 requirement checkpoint 的唯一深原语 |
| workspace freshness/sync | origin trunk 新鲜度分类、ff-only 同步、journal 与 audit | 保留为远端 trunk 预检，不进入本地业务门禁 |
| merge saga | prepare、commit-tree、逐仓 lease publish、rebuild、finalize 与故障恢复 | 只增加首次 prepare 前的全仓 publication preflight |
| writeback/archive | Transaction Workspace、CAS、lease、manifest、远端确认与清理 | 协议和恢复语义保持不变 |
| Durable transaction | lock、journal、recoverable write-set 与只向前恢复 | 不新增 WAL、事务协议或补偿层 |
| 受控 Git 与摘要 | `gitRun/gitMust`、`shell:false`、CRLF 到 LF、SHA-256 | 继续承担 HEAD/ref/ancestry 查询和 artifact 摘要 |
| 现有 bare remote 测试 fixture | 覆盖 crctl、checkpoint、merge、freshness 等行为 | 只扩现有测试文件，不创建新 fixture 框架 |

## 4. 本次应复用的最小改造

| 最小改造 | 归属 | 说明 |
|---|---|---|
| release snapshot 本地化 | 现有 workspace transaction 模块 | `buildReleaseSubjects` 与 `verifyReleaseSubjects` 复用 `classifyRepoWorkspace`，删除 fetch 和远端 ref 相等判定，保持 v1 schema |
| merge publication preflight | 现有 `mergeCr` | 在首次 prepare 前一次性收集所有 active repo 的本地 HEAD、远端 requirement source 与 trunk SHA；全部通过后才进入既有 saga |
| Operational Workspace 连续传递 | 现有 Pipeline 与 `workspace inspect` | Pipeline 只传 `cr_id + operational_workspace`；完整 repo map 仍由 resolver 解析 |
| 阶段终点 checkpoint | 三条现有主 Pipeline | requirement、architecture、code 在审批后 checkpoint 完成才算 Pipeline 完成；失败保持已审批状态并重跑 checkpoint |
| freshness 语义收敛 | 现有 Skill/Pipeline/README | 保持节点位置和同步算法，只明确其是远端 trunk 新鲜度预检，失败不改业务证据 |
| TTY affirmative 扩展 | 共享 `cmdApprove` | 一处判断接受 `y|yes` 并更新 prompt，四个 stage 共用；其他审批语义不变 |
| 最小文档与测试更新 | 现有 Skill、README、ARCHITECTURE、ADR 与测试 | 只同步边界、交接条件、恢复入口和行为回归，不复制实现算法 |

本次新增公共 CLI、状态、账本、snapshot schema、事务模块、版本化转换脚本和第三方依赖的数量必须均为 0。

## 5. 用户故事

- **US-01 需求/开发负责人**：已有 clean committed 本地事实时，希望在网络不可用或远端 requirement ref 滞后时仍能完成 status、gate、review-record 与 approve 的业务判断。
- **US-02 代码评审与审批人**：希望 release snapshot 精确绑定本地被评审 source 和受控 artifact；只有真实本地漂移才使证据失效。
- **US-03 发布执行者**：希望 merge 在生成任何 candidate 前确认所有 active repo 的本地 HEAD 已发布到远端 requirement ref，并在未发布时指向 checkpoint 恢复。
- **US-04 CR 协作者**：希望 Pipeline 连续节点始终使用同一个 Operational Workspace；换 runner、Owner 或机器时通过 checkpoint/resume 显式交接。
- **US-05 人工审批人**：希望四个人工审批在 TTY 中接受常见的 `y/Y/yes/YES`，同时保留非 TTY、grant、resign、驳回回退和证据门禁的安全边界。
- **US-06 Tools 维护者**：希望改造复用既有 resolver、classifier、checkpoint、merge saga、durable transaction 和测试 fixture，不维护第二套发布或事务实现。

## 6. 功能需求

### FR-01 本地业务权威

1. merge 前的 status、gate、review-record、approve 只读取当前 Operational Workspace 与各 active repo 的本地 CR worktree。
2. 上述业务路径不得 fetch、读取 remote-tracking ref 或以 origin 是否存在决定证据有效性。
3. Pipeline 只传递 `cr_id + operational_workspace`；完整 repository/worktree map 由 `resolveRepositories` 在 `crctl` 深原语内部解析。
4. workspace 缺失、路径身份异常或本地事实不可读时 fail closed，不得改从主 checkout、远端 ref 或目录约定猜测。

### FR-02 本地 release snapshot 构造

1. `review-record --stage code` 构造 release-subjects 前，必须对每个 active repo 调用既有 `classifyRepoWorkspace`；只有 `classification=healthy` 才可继续。
2. snapshot 的 `reviewed-source-sha` 来自各仓本地 CR worktree 的 clean committed HEAD。
3. `remote-ref` 字段继续写既有 `refs/heads/requirement/{CR-ID}`，仅表示预期发布分支名，不证明远端存在或已同步。
4. 受控 artifact 继续按路径字典序、CRLF 到 LF 和 SHA-256 规则计算；文件集合与 v1 schema 不变。
5. origin 不存在、网络不可用、远端 requirement ref 缺失或滞后均不得阻止 snapshot 构造。

### FR-03 本地 signed snapshot 重核

1. `verifyReleaseSubjects` 必须校验 snapshot 形状、active repo 集合、本地 workspace healthy、source SHA 与受控 artifact digest。
2. non-KB repo 当前 HEAD 必须精确等于 reviewed SHA。
3. knowledge-base repo 的 reviewed SHA 必须是当前 HEAD 祖先；reviewed SHA 后只允许以下既有 metadata 白名单：`change-requests/{CR-ID}/approval.yml`、`cr.md`、`traceability.yml`、`review-loop.yml`、`change-requests/_backlog.yml` 以及 `change-requests/{CR-ID}/review-annotations/` 前缀。该精确集合保持在现有 verifier 原位，不抽成配置或 registry，不增加新路径。
4. PRD、SDD、plan、TASK 和 `_index.yml` 的集合与 digest 必须保持一致；PRD/SDD 漂移继续使用既有 `APPROVED_ARTIFACT_DRIFT` 分流。
5. verifier 不 fetch、不读取 remote-tracking ref、不返回 `remote-ref-drift`；`ok=false` 只表示本地 workspace、source 或 artifact 失效。

### FR-04 approve-code 只消费本地证据

1. `approveAndAdvance(code)` 继续从 `review-annotations/code.yml` 读取机器注入 snapshot，并调用本地 `verifyReleaseSubjects`。
2. 重核通过后继续把同一 snapshot 写入 `approval.yml#code.release-subjects`，并纳入既有 evidence/approval digest 与原子提交。
3. 真实本地 source、TASK 或 artifact 漂移必须以既有结构化错误零写入拒绝。
4. 网络不可用、origin 缺失或远端 requirement ref 未更新不得阻止代码审批。

### FR-05 merge 全仓 publication preflight

1. 新 merge 事务必须在既有 merge lock 内、首次 prepare 前先完成本地 signed snapshot 重核。
2. 本地 code/TASK 漂移且尚无 trunk publish 时，继续复用唯一的 release-drift 回退；PRD/SDD 漂移继续硬阻断；任一 trunk publish 后的 source 漂移继续 blocked。
3. 本地重核通过后，对全部 active repo fetch origin，在内存中冻结 `{repo, localHead, remoteSourceSha, trunkSha}`。
4. 任一远端 requirement source 缺失时返回 `MERGE_SOURCE_MISSING`；任一 `remoteSourceSha != localHead` 时返回 `RELEASE_REMOTE_NOT_PUSHED`，并提供 repo、head、remote 和 checkpoint recoverCommand。
5. publication lag 失败时 CR 保持 `code-approved`，不得触发 `code-approved -> developing`；`payload.repos` 中不得出现 prepared candidate。
6. 只有全仓 preflight 通过后，才允许使用同一批冻结 SHA 进入现有 prepare/publish/finalize saga。
7. 远端 advanced/diverged/history-rewritten 的细分和恢复继续由 checkpoint 既有算法负责；merge 不复制 ancestry 分类、不自动 checkpoint、不 force。

### FR-06 Operational Workspace 连续性

1. requirement Pipeline 继续使用 register 返回的 knowledge-base worktree 作为 `operational_workspace`。
2. architecture/code Pipeline 入口调用现有 `workspace inspect {cr_id}`，由既有 authority resolver 返回单一 `operationalWorkspace` 字段。
3. 后续连续节点必须原样传递该路径；不得从 `resources[]`、主 checkout、远端 ref 或目录命名重新猜测。
4. `implement-code` 需要多仓路径时，只消费 `workspace inspect/ensure` 的结构化结果，不自行拼接路径。
5. worktree 缺失或 authority 异常时中止，并指向既有 resume 流程；业务 Skill 不自动 fetch/ensure。

### FR-07 阶段终点 checkpoint 合同

1. requirement、architecture、code 三条 Pipeline 均必须在审批后完成 checkpoint，才算该 Pipeline 完成。
2. requirement 的 PRD 草稿 checkpoint 与 code 的 TASK checkpoint继续保持可选；审批后阶段终点 checkpoint 不可跳过。
3. architecture 删除 `auto_push_after_sdd` 输入；code 的审批后 checkpoint 从 `onFail=skip` 改为 `onFail=abort`。
4. checkpoint 失败不得回滚已审批状态，不得要求重新审批；修复远端或 lease 事实后重跑同一 recoverCommand。
5. 跨 runner、Owner 或机器的后继执行必须通过 checkpoint/resume 校验交接；merge publication preflight 作为最终兜底。
6. checkpoint 仍是 Pipeline 完成条件，不进入 approve 原子事务，也不新增 `checkpoint-pending` 状态。

### FR-08 freshness 职责收敛

1. `workspace freshness/sync` 保持现有节点位置、origin trunk fetch、四类结果、ff-only 同步、journal 与 audit 语义。
2. freshness 只作为远端 trunk 新鲜度预检；不得被 status gate、approve 或本地 release verifier 调用。
3. fetch/sync 失败可以中止当前 Pipeline 节点，但不得修改 CR status、approval、review verdict 或 reviewLoop attempt。
4. 本 CR 不移动 freshness 节点，不新增 local-only 模式，不改变同步算法，不自动 merge/rebase。

### FR-09 TTY 人工审批确认

1. 四个审批 stage 共用 `cmdApprove` 的同一判断：`['y', 'yes'].includes(answer.trim().toLowerCase())`。
2. `Y/y/yes/YES/YeS` 及带前后空白的等价输入进入既有批准事务。
3. 空输入、`N/n/no` 和其他文本继续执行既有 reject 权威回退；不得改成无副作用取消。
4. prompt 必须明确“输入 y 或 yes 才会写入 approval.yml [y/N]”。
5. TTY 检查、evidence gate、audit、reject rollback、grant 验签、`--resign` 与 approval/status 原子提交保持不变。
6. 不新增确认 helper、配置、输入字典或依赖。

### FR-10 最小采用与文档边界

1. 只修改实现目标直接涉及的既有 crctl 模块、Pipeline、Skill、测试及人读文档。
2. Skill 只解释 local drift 与 publication lag 的业务分流，不计算 SHA、不复制 Git/事务算法。
3. Pipeline 只声明节点顺序、workspace 传递、checkpoint 完成条件、reviewLoop 与失败中止。
4. README、ARCHITECTURE 和 ADR 只同步事实源边界、交接条件与恢复入口，不复制可执行算法。
5. 不新增 Agent、公共 CLI、状态、账本、snapshot schema、事务层、版本化脚本或第三方依赖。

### FR-11 兼容启用与在途 CR

1. `developing` 及更早状态的 CR 在新版本启用后直接采用新的本地 snapshot 构造与重核规则，不迁移历史账本或 schema。
2. `code-reviewing` 状态的 CR 必须重跑 `review-code`，以当前 healthy committed 本地 source 重新生成 review snapshot 后再审批。
3. `code-approved` 状态的 CR 若既有 signed snapshot 与当前本地 worktree 一致，只需先完成 checkpoint，再进入 merge，不得仅因远端 publication lag 强制重新评审或审批。
4. 已进入 merge 且已有 candidate 或任一 trunk publish 的事务，必须使用启动该事务的 Tools 版本按原 journal 合同完成；不得跨版本重建、清空或改变事务语义。
5. 不批量改写历史 release-subjects v1、approval、review annotation、checkpoint ledger 或 merge journal；启用前只复用现有 `upgrade-check` 做只读兼容检查，不新增 CLI。

## 7. 非功能需求

- **NFR-01 离线确定性**：已有 clean committed source 时，status、gate、review-record 与 approve 的本地业务判定不访问网络。包含 checkpoint/freshness 的完整 Pipeline 不承诺端到端离线。
- **NFR-02 Fail closed**：workspace 非 healthy、HEAD/文件不可读、snapshot 形状非法或仓集合漂移时硬失败，不得降级为空 snapshot、pass 或远端猜测。
- **NFR-03 行尾一致性**：所有 artifact 摘要继续先执行 CRLF 到 LF；逐行解析使用 `split(/\r?\n/)`，跨行解析失败硬失败。
- **NFR-04 状态机稳定**：保持 15 个具名状态 + 注册前 `(new)`、28 条声明转换、wildcard 展开后 50 条的当前口径。
- **NFR-05 Schema 稳定**：release-subjects v1、approval、review annotation、checkpoint ledger 与 durable transaction journal 不迁移。
- **NFR-06 可恢复性**：远端失败只通过既有 checkpoint/merge recoverCommand 向前恢复，不手改账本、不 force ref、不清理 journal。
- **NFR-07 跨平台**：Windows/Linux 继续使用 `spawnSync(..., {shell:false})`、现有路径身份校验和原生 Git argv。
- **NFR-08 最小成本**：不增加缓存、watcher、daemon、数据库、队列、registry、provider、adapter 或生产依赖。

## 8. 验收标准

- **AC-01（FR-01/02）**：origin 不存在或网络不可用时，只要所有本地 CR worktree 为 healthy 且 source 已提交，`review-record --stage code` 能构造 release-subjects v1；调用轨迹中无 fetch 或 remote-tracking ref 读取。
- **AC-02（FR-02）**：任一 active repo 为 dirty、wrong-branch、missing 或 path-unregistered 时，snapshot 零写入失败并返回对应本地 workspace 事实。
- **AC-03（FR-03/04）**：远端 requirement ref 落后本地 HEAD、但本地 snapshot 未漂移时，`approve-code` 能通过本地重核并进入既有批准事务。
- **AC-04（FR-03/04）**：non-KB 本地 HEAD 在 review 后改变时，approve 返回 local source drift，`approval.yml` 与 `cr.md` 零写入。
- **AC-05（FR-03）**：KB reviewed SHA 后，仅修改 `approval.yml`、`cr.md`、`traceability.yml`、`review-loop.yml`、`change-requests/_backlog.yml` 或 `review-annotations/` 前缀时重核通过；逐一增加任一白名单外路径时均返回本地 code drift，且白名单未新增配置或 registry。
- **AC-06（FR-03）**：plan、TASK 或 `_index.yml` 增删/摘要漂移时返回 task drift；LF/CRLF 等价；PRD/SDD 漂移继续返回既有 artifact drift 分类。
- **AC-07（FR-05）**：新 merge 事务中任一 repo 的 remote source 缺失时返回 `MERGE_SOURCE_MISSING`，首次 prepare 前失败，状态保持 `code-approved`，无 candidate。
- **AC-08（FR-05）**：任一 repo 的 remote source 不等于 local HEAD 时返回 `RELEASE_REMOTE_NOT_PUSHED` 和 checkpoint recoverCommand，状态保持 `code-approved`，无 candidate。
- **AC-09（FR-05）**：执行 checkpoint 后重跑 AC-07/08 场景，可以进入既有 prepare/publish/finalize；remote advanced/diverged/history-rewritten 仍由 checkpoint 返回既有分类，merge 不复制 ancestry 算法。
- **AC-10（FR-05）**：本地 code/TASK drift 且零 trunk publish 时仍走唯一 release-drift 回退；PRD/SDD 漂移和已有 trunk publish 后 source drift 保持硬阻断。
- **AC-11（FR-05）**：已有 merge journal 继续按既有 candidate/publish 恢复合同续跑，不清空、不重建已持久化事务事实；新 preflight 不新增 journal 字段。
- **AC-12（FR-06）**：requirement 使用 register 返回的 worktree；architecture/code 从 `workspace inspect.operationalWorkspace` 取得 authority path并在连续节点原样传递，异常时不猜路径、不自动 fetch/ensure。
- **AC-13（FR-07）**：三个 Pipeline 均满足“审批后 checkpoint 且 `onFail=abort`”；失败时已审批状态不回退，重跑 checkpoint 不要求重新审批。
- **AC-14（FR-07）**：architecture 不再声明 `auto_push_after_sdd`；requirement PRD 草稿 checkpoint 和 code TASK checkpoint 仍可选；Pipeline `_index.yml` 节点数同步。
- **AC-15（FR-08）**：freshness fetch/sync 失败不会改变 status、approval、review evidence 或 reviewLoop attempt；现有 fresh/behind-clean/diverged/unknown 与 ff-only 回归保持通过。
- **AC-16（FR-09）**：四个 TTY stage 参数化验证 `Y/y/yes/YES/YeS` 和带空白等价输入进入批准事务。
- **AC-17（FR-09）**：空输入、`N/n/no` 和其他文本继续触发现有 reject 回退；非 TTY 无 grant 仍返回 `APPROVAL_REQUIRES_HUMAN`；grant 与 `--resign` 回归不变。
- **AC-18（FR-10）**：静态契约检查证明 Agent、Pipeline、Skill、crctl、版本化脚本和 README 遵守第 2.2 节职责边界，且 Pipeline/Skill/README 未复制 Git、CAS、journal 或状态机算法。
- **AC-19（FR-10/NFR）**：状态机、gates、release-subjects v1、approval/checkpoint schema、durable transaction 与生产依赖清单无新增类型。
- **AC-20（全范围）**：现有 crctl、checkpoint、merge、writeback、archive、workspace resolver、freshness 与四阶段审批回归全部通过。
- **AC-21（FR-11）**：`developing` 及更早状态无需 schema 迁移即可采用新本地 verifier；`code-reviewing` 必须重跑 code review 生成当前 snapshot。
- **AC-22（FR-11）**：`code-approved` 且本地 snapshot 一致、远端 source 滞后时，checkpoint 后可继续 merge，期间不回退状态、不要求重新 review/approve。
- **AC-23（FR-11）**：已有 candidate 或 trunk publish 的 merge journal 由启动版本按原合同续跑；新版本不重建、清空或迁移该 journal，且启用前 `upgrade-check` 只读。

## 9. 成功指标

- 远端 requirement ref 滞后但本地内容未变导致的 review/approve 失败或状态回退为 0。
- publication lag 的恢复动作 100% 指向 checkpoint/pull/manual，不要求重新 review/approve。
- 本地 source、TASK 和 artifact 漂移仍 100% 被现有审批或 merge 门禁拦截。
- 三个跨 Pipeline 阶段终点均只有 checkpoint complete 才算完成。
- 新增公共 CLI、状态、账本、schema、事务模块、版本化脚本和第三方依赖数量均为 0。
- 四个 TTY stage 对 `Y/y/yes/YES` 的接受率为 100%，其他输入保持既有回退语义。

## 10. 依赖与风险

### 10.1 依赖

- Tools 当前 workspace resolver、`classifyRepoWorkspace`、`buildReleaseSubjects`、`verifyReleaseSubjects`、`checkpointCr`、`mergeCr`、durable transaction、`gitRun/gitMust` 与现有 bare remote fixture。
- 当前 release-subjects v1、approval evidence digest、KB metadata 白名单和 merge journal 恢复合同。
- requirement、architecture、code 三条 Pipeline 以及相关 approve、push-progress、workspace-freshness、merge-feature-branch Skill。

### 10.2 风险

- **R-01 把发布滞后误判为本地漂移**：本地 verifier 不得读取远端；远端精确相等检查只进入 checkpoint/merge 发布边界。
- **R-02 放松本地证据门禁**：snapshot 构造与重核必须先要求 `classifyRepoWorkspace=healthy`，并保留 source/artifact/白名单校验。
- **R-03 merge 产生部分准备事实**：publication preflight 必须覆盖全仓并在首次 prepare 前完成；全部通过后才进入既有 saga。
- **R-04 已启动事务跨版本切换**：已有 candidate/publish 的 merge journal 必须使用启动该事务的 tools 版本按既有合同完成，不在恢复中切换事务语义。
- **R-05 Pipeline workspace 漂移**：同一 Pipeline 连续节点原样传递 authority path；跨 runner/Owner/机器通过 checkpoint/resume 重新建立事实。
- **R-06 文档成为第二事实源**：README/ARCHITECTURE/ADR 只写边界与入口，具体算法和错误分类继续以 crctl、gates、Pipeline JSON 和 Skill 契约为准。
- **R-07 TTY 扩展破坏驳回安全边界**：只修改共享 affirmative 判断与 prompt；false 分支、grant/resign 和非 TTY 路径保持原实现。

## 11. 范围排除

- 不新增 `approval-published`、`checkpoint-pending` 或 remote freshness 状态/账本。
- 不新增 snapshot v2、publication/verifier registry、mode 参数或 context resolver。
- 不把完整 repo map 固化进 Pipeline 或 Agent，不让 Pipeline/Skill 计算 SHA 或 ancestry。
- 不把 checkpoint 合并进 approve 原子事务，不让 merge 自动 checkpoint。
- 不新增 local commit CLI，不拆分 checkpoint 的 commit/push 职责。
- 不移动 freshness 节点，不新增自动 merge/rebase、local-only 模式或新的同步算法。
- 不把 publication error 写入 review annotation、approval 或 traceability，不因网络失败消耗 reviewLoop attempt。
- 不修改 writeback/archive 发布协议，不批量改写历史 CR。
- 不让四个 approve Skill 各自解析 stdin，不新增确认 helper、配置或输入依赖。
- 不借本次改造改变 reject、grant、resign、非 TTY 或 Ed25519 安全边界。
- 不新增 Agent、版本化转换脚本、第三方依赖或第二套事务框架。

## 12. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-16 | v0.2.0 | Ray | 回修 B-01/B-02：冻结 KB metadata 精确白名单；补充 developing/code-reviewing/code-approved/已启动 merge 的兼容启用合同与 AC |
| 2026-08-16 | v0.1.0 | Ray | 初始草稿：本地业务权威、远端 publication preflight、Operational Workspace 连续性、阶段终点 checkpoint 与 TTY `y|yes` |

## Runner Core：architecture-design 自动调度纵切（v0.20.6 · CR-2026-045）

## 1. 概述

当前 tools 已用版本化 Pipeline 声明节点顺序，用 Skill 承载业务步骤，并由 `crctl` 独占状态、门禁、账本、Git、审批和恢复；Multica 也已有 Agent 任务队列、`pipeline_run` / `pipeline_node_run`、CR/review/approval projector、网页审批和签名 grant 投递。但是，一条已审批需求仍需人逐节点判断并启动 `architecture-design`，现有 `crctl next` 只给出确定性下一步，不会在 Multica 中调度 Skill。

本 CR 建设一个有意收窄的 Runner Core，只验证 `architecture-design` 的五节点纵切：

```text
write-tech-design
→ review-tech-design / write-tech-design 回修
→ human_approval
→ approve-tech-design
→ push-progress
```

Core 复用同一 CR Git 权威、同一逻辑 pipeline run、现有 Agent 任务队列、签名审批链和 checkpoint 深原语。它不建设通用工作流引擎，不执行 Git 或账本写入，不解释 LLM 自然语言，不复制 `crctl` 的事务、门禁或 attempt 逻辑。

本 CR 是战略验证：验收通过只证明 architecture 纵切可运行，不自动授权 requirement、code、writeback 或 Runner Main Track。

## 2. 目标逻辑架构

### 2.1 Ponytail 优先级

需求、设计、实现与评审必须按以下顺序选择方案，并在首个足够方案处停止：

1. 复用现有能力。
2. 使用标准库。
3. 使用原生 Git/文件 API。
4. 使用已安装依赖。
5. 一行代码能够解决时不扩张。
6. 最小新增代码。

不得为未来 Pipeline、新节点类型、多机调度或指标分析预建通用抽象。

### 2.2 模块职责

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、`reviewLoop`、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

Runner Core 只拥有运行生命周期、节点调度、任务关联、等待审批、失败中止和幂等续跑。任何业务状态变化仍必须由对应 Skill 调用 `crctl` 产生。

## 3. 已经解决的基础设施

以下能力已经存在，本 CR 必须直接复用：

| 已有能力 | 当前职责 | 本 CR 的复用方式 |
|---|---|---|
| `architecture-design.pipeline.json` | 声明五节点顺序、prompt、失败动作和 reviewLoop | 作为节点顺序和回修合同的唯一来源 |
| `agent-skill-matrix.yml` | 为 active Skill 指定唯一 owner | 机械解析节点执行 Agent；缺失或不唯一时阻断 |
| `crctl status/next/gate/advance` | 状态、下一步、门禁和合法推进 | Runner 观察结果，不复制状态机 |
| `crctl review-record/attempt` | annotation、traceability、review-loop 与 attempt 原子记账 | Runner 不递增、不重置、不推测 attempt |
| `crctl approve --grant` | 验签、证据重核、审批记录和状态推进 | `approve-tech-design` Skill 继续作为唯一消费入口 |
| `crctl checkpoint` | 多仓提交、发布、lease、journal 与恢复 | `push-progress` Skill 继续作为唯一调用入口 |
| `pipeline_run` / `pipeline_node_run` | 运行与节点状态投影 | 复用现有表和同一逻辑 run，不建第二套运行表 |
| governance projector | 从 CR/review/approval 事件投影 run 和节点状态 | 手动路线与自动路线继续共用，不改变 Git 权威 |
| Agent task queue / TaskService | 入队、claim、start、complete、fail 与恢复 | 作为 Skill 节点的唯一执行通道 |
| `cr_id` / `pipeline_node_run_id` 归因列 | 关联任务、CR 和节点 | Runner 入队时写入现有归因，不建关联账本 |
| 网页审批与 `approval_record` | 校验人类身份、签发 Ed25519 grant、幂等批准 | Runner 不签名、不代替人类审批 |
| daemon grant delivery/ACK | 把 grant 投递到 `.crctl/grants/` 并确认 delivered | delivered 后才允许调度 approve Skill |
| CR gate UI | 显示阶段、blocker 和审批动作 | Core 不新增 Runner 控制台 |
| 手动 Skill + `crctl next` | 无 Runner 时的完整人工推进路线 | 作为兼容和回退路径保留 |

## 4. 本次应复用的最小改造

| 最小改造 | 归属 | 需求结果 |
|---|---|---|
| architecture 回放合同显式化 | 现有 Pipeline JSON | `reviewLoop.replayNodes` 明确列出回修和复审顺序，Runner 不根据 prompt 猜测 |
| 当前节点 registry 刷新 | 现有 governance 生成链 | 消除 tools 当前节点 UUID 与 Multica 旧 generated registry 的漂移；Core 只加载 architecture |
| Runner Core 调度器 | 现有 governance/service 边界 | 启动或接管同一 architecture run，逐节点入队、等待和中止 |
| Runner 窄入队路径 | 现有 TaskService/SQL query | 复用任务生命周期，在入队时关联 run/node/CR，不建第二任务系统 |
| 运行恢复元数据 | 现有 run 字段 | 保存启动模板 digest 和最小执行上下文；不建模板数据库 |
| projector/Runner 协作 | 现有 projector | projector 继续投影 Git 事件，Runner 继续调度；二者不得创建平行 run |
| 最小测试与文档 | 现有 governance/task 测试和人读入口 | 验证纵切、block 回修、审批、幂等、恢复和手动兼容 |

允许修改现有表约束或现有 JSON 字段以满足正确性，但必须优先使用 PostgreSQL 原生约束和已有 JSONB；不得新增运行表、幂等表、模板表、消息总线或事务框架。

## 5. 用户故事

- **US-01 路由 Agent**：当用户要求对一个 `requirement-approved` CR 进行架构设计时，希望选择现有 `architecture-design`，由 Runner Core 继续调度，而不是自行判断状态或写文件。
- **US-02 需求/开发负责人**：希望技术设计、自动评审和 block 回修按现有 Pipeline 自动连续执行，直到评审通过或权威 attempt 耗尽。
- **US-03 架构审批人**：希望 Runner 在人工审批前严格暂停；网页批准并投递签名 grant 后才继续。
- **US-04 CR 协作者**：希望服务重启或事件重复投递后继续同一 run，不重复生成 SDD、评审、审批或 checkpoint。
- **US-05 平台维护者**：希望 Core 复用现有表、TaskService、projector、Skill、`crctl` 和 checkpoint，不维护第二套状态机、Git 或事务实现。
- **US-06 手动路线使用者**：希望 Runner 关闭或未接管时，现有 Skill + `crctl next` 路线行为不变。

## 6. 功能需求

### FR-01 支持范围与启动

1. Core 只接受 `pipeline_id=architecture-design`，入口 CR 必须可由现有权威状态判定为 `requirement-approved`。
2. Pipeline 由路由 Agent 选择；Runner 不根据自然语言自行选择 Pipeline 或 Skill。
3. Core 只支持当前五个节点及其 `onFail=abort` 语义，不实现 `skip`、`code_generation`、通用表达式或其他 Pipeline。
4. 输入只包含现有 Pipeline 所需 `cr_id`、可选 `tech_context` 和由服务端确定的 workspace/user 上下文。
5. unsupported pipeline、未知 node kind、未知 Skill、owner 缺失/不唯一或入口状态不合法时零任务入队并 fail closed。

### FR-02 Pipeline 合同与 digest

1. 节点顺序、`ref`、prompt、`onFail`、reviewLoop 和 passCondition 只来自当前 tools Pipeline JSON。
2. `architecture-design.reviewLoop` 必须复用现有 code Pipeline 的机器合同：`replayPolicy=rerun-listed-nodes-in-order`，`replayNodes` 每项都包含 `nodeId`、`ref`、`purpose`，不得引入 refs 字符串数组等第二种 schema。
3. architecture 回放顺序固定为：
   - `{nodeId: 00000000-0000-0000-0016-000000000001, ref: write-tech-design, purpose: repair-sdd}`；
   - `{nodeId: 00000000-0000-0000-0016-000000000002, ref: review-tech-design, purpose: rerun-current-review}`。
4. 不得修改 requirement Pipeline；本 CR 不为其他 Pipeline 补 replayNodes。
5. Multica 使用的节点 ID/metadata 必须从本 CR 基线 tools 重新生成，旧 `0014` architecture UUID 不得继续作为当前合同。
6. run 启动时保存 Pipeline 合同 digest；恢复时当前 registry digest 不一致则阻断并转人工处理。
7. Core 不保存、加载或猜测旧模板版本。

### FR-03 单一逻辑 run

1. 同一 workspace、CR、pipeline 在任一时刻只允许一个非终态逻辑 run。
2. Core 启动时必须复用 projector 已创建的匹配 run；不存在时创建的 run 必须能被后续 projector 事件复用。
3. 两个并发 start，或 start 与 projector 首个 `tech-designing` 事件并发到达时，竞争方必须取得或重新读取同一个非终态 run；失败竞争不得留下第二个 run、首节点 attempt 或有效任务。具体使用 PostgreSQL 约束、事务锁或既有串行化原语由 SDD 决定。
4. Runner 和 projector 可更新同一 run 的各自字段，但不得互相覆盖已完成节点、attempt 历史或终态。
5. run 只保存调度所需 inputs、execution context、digest 和生命周期状态；CR 业务状态仍以 Git 为权威。
6. terminal run 不因迟到或重复事件重新打开。

### FR-04 Skill 节点调度

1. Skill owner 必须由 matrix 的唯一 `owns` 机械解析，Runner 不维护第二份 node-to-agent 映射。
2. Skill 节点通过现有 TaskService 入队，并在创建时关联 `cr_id`、`pipeline_node_run_id`、run/node 和 attempt。
3. 节点 prompt 必须来自固定 registry 合同，只注入声明输入和结构化前序输出；不得拼接未受控自然语言指令。
4. 同一 run/node/attempt 只能有一个有效任务；重复唤醒必须复用或忽略已有任务。
5. task failed、cancelled、超出既有重试策略或 Skill 返回技术失败时，node/run 进入失败终态，不自动跳过。
6. Skill 节点只有在“Agent task 得到该节点定义的成功终态”且“CR 权威后置条件已由现有结构化事件或确定性重读确认”两个条件同时满足时才算成功；task completed 本身不得触发后继节点。
7. 五节点后置条件如下，Runner 只核对结果，不自行补写证据：

| 节点 | task/人类结果 | 必须同时满足的 CR 权威后置条件 |
|---|---|---|
| `write-tech-design` | Agent task 成功 | `sdd.md` 已形成，CR 为 `tech-design-review-pending` |
| `review-tech-design` pass | Agent task 成功 | `review-annotations/sdd.yml` 为 pass、blockers 为空且 subject digest 当前，CR 保持 `tech-design-review-pending` |
| `review-tech-design` block | Agent task 返回结构化 repair 结果 | annotation 为 block、blockers 非空、CR 为 `tech-designing`，再按 replayNodes 回修 |
| `human_approval` | 无 Agent task；等待 grant delivered | pass review 仍当前且 CR 为 `tech-design-review-pending`；不得把网页记录本身当状态推进 |
| `approve-tech-design` approve | Agent task 成功 | `approval.yml#tech-design` 与当前证据一致，CR 为 `tech-design-reviewed` |
| `approve-tech-design` reject | `APPROVAL_DECLINED_ROLLED_BACK` 业务结果 | CR 已权威回退到 `tech-designing`，当前正向 run 中止 |
| `push-progress` | Agent task 成功 | 现有 checkpoint 结果为 `phase=complete` |

8. task 结果与权威后置条件不一致时，Runner 必须停在当前 node 并记录结构化错误；不得重试后继节点、伪造缺失证据或自行推进状态。

### FR-05 reviewLoop

1. `review-tech-design` 的 verdict、blockers 和 attempt 只消费 `crctl review-record` 产生的结构化事件/投影。
2. pass 且 blockers 为空时进入 `human_approval`；block 时只按 `replayNodes` 执行回修和复审。
3. Runner 不递增 attempt；`crctl` 返回 `LOOP_EXHAUSTED` 时 run 失败并保留最后 blocker。
4. 重启或重复 review 事件不得创建相同 attempt 的第二条节点记录或第二个任务。
5. Runner 不解析 blocker 文本决定路由，只把原始结构化 feedback 传给 Pipeline 声明的 repair Skill。

### FR-06 人工审批与 grant

1. 进入 `human_approval` 后 run 为 waiting，且不得提前创建 `approve-tech-design` 或 `push-progress` 任务。
2. 网页审批仍由现有 ApprovalService 校验人类 actor、stage 和 evidence digest，并签发 Ed25519 grant。
3. 只有 daemon 已把对应 grant 投递到 CR workspace 并 ACK 后，Runner 才调度现有 `approve-tech-design` Skill。
4. Runner 不生成、不修改、不验签 grant；`crctl approve --grant` 继续执行全部验证和状态推进。
5. 合法 approve 推进后才允许 checkpoint；合法 reject 按现有 `APPROVAL_DECLINED_ROLLED_BACK` 回退并中止当前正向 run，不执行 checkpoint。
6. grant 缺失、签名错误、归属不符、stage 错误或 evidence 漂移时 fail closed，保留可审计错误。

### FR-07 checkpoint 与完成

1. `approve-tech-design` 完成并由权威 CR 事实确认 `tech-design-reviewed` 后，Runner 才调度 `push-progress`。
2. `push-progress` 必须调用现有 checkpoint 深原语；Runner 不执行 commit、push、lease、journal 或恢复算法。
3. 只有 checkpoint 返回 `phase=complete` 后，architecture run 才可标记 completed。
4. checkpoint 失败时 CR 保持 `tech-design-reviewed`，run 保持可恢复失败/等待状态；重跑同一恢复入口不重新审批。

### FR-08 恢复与幂等

1. 服务启动时只扫描本 workspace 中 Runner Core 管理的非终态 architecture run。
2. 恢复必须根据 run/node/task 记录和当前 CR 结构化事实决定等待、继续或阻断，不凭自然语言输出猜测。
3. task terminal、CR status、review verdict、approval delivered 等重复或乱序通知不得重复调度。
4. 进程在入队前后、task terminal 前后、审批投递前后或 checkpoint 完成前后重启，最终只能形成一个有效节点执行结果。
5. current digest 不匹配、状态与节点不可调和或权威事实缺失时 fail closed，不自动重置 run。

### FR-09 兼容、观测与停用

1. Runner 未启用、未接管或关闭后，手动 Skill + `crctl next` 路线保持可用。
2. 手动路线产生的 CR/review/approval 事件继续由 projector 投影，不要求迁移历史 run。
3. 现有 CR gate UI 继续显示阶段和 blocker；本 CR 不新增 Runner 控制台。
4. 现有 run/node/task 记录必须足以定位当前节点、attempt、等待原因和失败原因。
5. Core 不生成价值评分、组织指标或新的统计账本。

### FR-10 最小采用边界

1. 不新增 Agent、Pipeline、Skill、公共工作流 DSL、运行表、幂等表、模板表、消息总线或第三方依赖。
2. Pipeline 只增加当前 architecture 回放所需机器字段，不复制 Skill 或 `crctl` 算法。
3. Skill 合同只在 Runner 输入/输出确有缺口时最小修订，不新增 Git、账本、attempt 或审批实现。
4. server 只增加纵切所需的固定调度逻辑和现有表/TaskService 接合，不实现通用 DAG/插件/表达式引擎。
5. README 只更新人读入口和停用/恢复说明，不复制 registry、状态机或数据库算法。

### FR-11 E2E hardening scope amendment

1. `crctl review-record` 写入 canonical review annotation 后，review outbox 必须携带同一 stage 的完整 `evidence` snapshot；不得由 Agent、Pipeline、daemon 或 server 重算另一套 digest。
2. daemon/server snapshot reconcile 不得在 active pipeline 期间以 installation-root stale snapshot 覆盖 Runner/live CR projection；active pipeline 结束后仍保留现有 snapshot healing。
3. architecture-design 的 `push-progress` prompt/Skill 不得包含未解析的 workspace 路径占位符；Pipeline 只传递 `cr_id`/message，workspace 复用 daemon 注入和 crctl 既有 resolver。
4. multica 的 issue origin constraint 必须在 migration 完成后保留完整合法集合：`autopilot`、`quick_create`、`lark_chat`、`slack_chat`、`agent_create`、`project_chat`、`project_discussion`、`dingtalk_chat`、`wecom_chat`。
5. 四项 hardening 按 TASK-12 → TASK-13 → TASK-14 → TASK-15 顺序实施；状态、门禁、CAS、审计和受控账本写入仍由既有 `crctl` 负责。

## 7. 非功能需求

- **NFR-01 Fail closed**：合同、owner、workspace、状态、证据、digest 或关联事实缺失/冲突时，零新增后继任务并给出结构化失败。
- **NFR-02 幂等**：重复请求、重复事件和服务重启不得造成重复有效 run、node attempt、Agent task、审批消费或 checkpoint。
- **NFR-03 权威隔离**：Runner 不直接写 CR 受控文件，不执行 Git，不改变 `crctl` 状态机、门禁和事务语义。
- **NFR-04 安全**：人工审批仍要求 TTY 或合法签名 grant；Runner 不持有签名私钥，不提供绕过入口。
- **NFR-05 可恢复**：恢复只向前复用现有记录和深原语 recoverCommand，不清理 journal、不回滚 Git、不猜模板。
- **NFR-06 兼容**：现有手动路线、projector 重放和 CR gate UI 回归通过。
- **NFR-07 跨平台**：涉及路径和进程调用时沿用现有 Windows/Linux 安全路径与 `shell:false` 约束。
- **NFR-08 最小成本**：新增生产依赖、运行表、模板表、消息总线和事务框架数量均为 0。

## 8. 验收标准

- **AC-01（FR-01/02）**：仅 `architecture-design` 可启动；unsupported pipeline、未知节点种类、未知 Skill 或 matrix owner 不唯一时返回结构化错误，且 run/node/task 零新增。
- **AC-02（FR-02）**：tools architecture reviewLoop 复用现有 `replayPolicy=rerun-listed-nodes-in-order` 与 `replayNodes[{nodeId,ref,purpose}]` schema；两项依次为 `…001/write-tech-design/repair-sdd`、`…002/review-tech-design/rerun-current-review`，静态合同测试逐字段通过；requirement Pipeline 节点和 reviewLoop 不变。
- **AC-03（FR-02）**：generated registry 使用当前 `0016` architecture UUID，生成源可追溯到本 CR tools commit；旧 `0014` 不再作为当前节点。
- **AC-04（FR-01/03/04）**：真实 `requirement-approved` CR 启动后，`write-tech-design` 和 `review-tech-design` 各只产生一个有效任务及关联 node run。
- **AC-05（FR-05）**：首次 review 返回 block 时，Runner 只按 `replayNodes` 调度一次 `write-tech-design` 回修和一次 `review-tech-design` 复审，并把 blocker 作为结构化 feedback 传入。
- **AC-06（FR-05）**：连续 block 达到 Pipeline maxAttempts 后，`crctl` 返回 `LOOP_EXHAUSTED`，run 失败、最后 blocker 可见且不进入人工审批。
- **AC-07（FR-05/06）**：复审 pass 后 run 进入 waiting_approval；在 grant delivered ACK 前无 approve/checkpoint 任务。
- **AC-08（FR-06）**：网页 approve → 签名 grant → daemon 投递/ACK → Runner 调度 `approve-tech-design` → Skill 调用 `crctl approve --grant` → CR 进入 `tech-design-reviewed`，链路中 Runner 无签名和受控文件写入。
- **AC-09（FR-06）**：合法 reject 产生权威回退并中止当前正向 run；签名错误、CR/stage/digest 不符时不推进状态、不执行 checkpoint。
- **AC-10（FR-07）**：checkpoint `phase=complete` 后 run 才 completed；checkpoint 故障时保持已审批 CR 状态，重跑恢复入口不重新执行设计、review 或审批。
- **AC-11（FR-08）**：对 task terminal、review、approval delivered 和 CR status 各重复投递至少两次，最终有效 run/node/task 数量及 CR 状态与单次投递相同。
- **AC-12（FR-08）**：在首个 Skill 入队后、review block 后、grant ACK 后和 checkpoint 调用后分别模拟服务重启，均继续同一 run 且无重复有效任务。
- **AC-13（FR-02/08）**：run 启动后替换 registry digest，恢复明确阻断；还原相同 digest 后可继续，不需要多版本模板仓库。
- **AC-14（FR-03/09）**：同一 CR 的手动事件与 Runner 事件由 projector 落入同一非终态 run；无第二套运行表或平行 run。
- **AC-15（FR-09）**：关闭 Runner 后，现有 `write-tech-design` → `review-tech-design` → 人工审批 → `approve-tech-design` → `push-progress` 手动路线回归通过。
- **AC-16（FR-10/NFR）**：静态检查证明 Agent、Pipeline、Skill、`crctl`、版本化脚本和 README 遵守第 2.2 节职责边界。
- **AC-17（FR-10/NFR）**：生产依赖、运行表、模板表、消息总线、通用 DSL/表达式解释器和事务框架新增数量均为 0。
- **AC-18（全范围）**：现有 crctl、TaskService、governance projector、approval grant、daemon delivery、CR gate UI 和手动 architecture Pipeline 相关回归全部通过。
- **AC-19（FR-04）**：对 `write-tech-design`、review pass/block、approve pass/reject 和 `push-progress` 分别注入“task/业务结果已到但对应权威后置条件缺失或陈旧”的场景；Runner 均停在当前 node、无后继任务且不补写任何 CR 证据。补齐真实权威后置条件后，同一 run 只继续一次。
- **AC-20（FR-03）**：分别并发发送两个相同 start，以及并发发送 start 与首个 `tech-designing` projector 事件；每种场景最终只有一个非终态 architecture run、一个首节点 attempt 和一个有效 `write-tech-design` 任务，迟到事件不重开终态 run。

- **AC-21（TASK-12）**：tech-design `review-record` 事件携带 `sdd.yml` evidence，服务端 `cr_sync_event.evidence` 保留该快照；真实 signed-grant crosscheck 不再因 review event 缺 evidence 选用陈旧 requirement evidence。
- **AC-22（TASK-13）**：active architecture pipeline 存在时，stale installation-root snapshot 不得覆盖 operational worktree 已确认的 CR projection；active pipeline 结束后 snapshot healing 与幂等行为保持。
- **AC-23（TASK-14）**：architecture pipeline、generated registry 和 push-progress Skill 不含 `<installation-workspace>` 等未解析路径占位符；daemon pipeline smoke 不执行全盘路径扫描。
- **AC-24（TASK-15）**：完整 migration upgrade 后 issue origin constraint 同时接受九种合法 origin；project Chat/Discussion 容器创建和非法 origin 拒绝均有真实数据库证据。

## 9. 成功指标

- 一条真实 CR 可从 `requirement-approved` 自动运行到 architecture checkpoint complete，期间只在人工审批节点等待人。
- 首次 review block 后自动完成一次回修复审，无人工选择下一 Skill。
- 重复事件和指定重启窗口造成的重复有效任务数为 0。
- Runner 直接执行 Git、直接写受控账本、生成审批签名的次数均为 0。
- 新增运行表、模板表、消息总线、事务框架和生产依赖数量均为 0。
- Core 验收前注册 requirement/code/writeback Runner 扩展 CR 的数量为 0。

## 10. 依赖与风险

### 10.1 依赖

- tools 当前 `architecture-design.pipeline.json`、`agent-skill-matrix.yml`、Skill 合同及 `crctl` 状态/评审/审批/checkpoint 深原语。
- Multica 当前 `pipeline_run` / `pipeline_node_run`、governance projector、Agent task queue、TaskService、ApprovalService、daemon grant delivery 和 CR gate UI。
- workspace 已安装与 Multica registry 来源一致的 tools commit；Runner 启动前能取得当前合同 digest。
- 用于 E2E 的真实 daemon、Agent runtime、Ed25519 审批密钥和可发布 CR worktree。

### 10.2 风险

- **R-01 双写重复 run**：Runner 首节点前创建 run，而 projector 可在状态事件到达时找/建 run；必须保证同一逻辑 run 并发下仍唯一。
- **R-02 task terminal 被误当业务成功**：Agent task 完成不一定等于 Skill 已形成预期 CR 状态和证据；Runner 必须消费结构化权威结果后再继续。
- **R-03 模板漂移**：只存 digest 不保存旧模板，因此漂移时必须阻断，不能用当前模板续跑。
- **R-04 审批时序**：网页记录批准不等于 grant 已投递，更不等于 `crctl approve` 已执行；三者必须分开观察。
- **R-05 projector 回放覆盖 Runner 状态**：投影重放不得重开 terminal run、抹除 attempt 或把已完成节点改回 running。
- **R-06 自动重试扩大副作用**：Runner 不新增独立重试策略；只复用 TaskService 既有行为和 Pipeline/`crctl` 的 attempt 上限。
- **R-07 旧 Multica 本地基线**：本 CR 注册时本地 `main` 落后审计用 `origin/main`；SDD/实现前必须通过既有 freshness/同步流程核实真实基线，不能按旧 worktree 推断现状。
- **R-08 Core 被扩成通用引擎**：未知节点、其他 Pipeline 和未来语义直接拒绝，不在本 CR 增加抽象。
- **R-09 review evidence 漂移**：review outbox 缺 evidence 会让 server 选不到最新 annotation；TASK-12 由 crctl 复用同一 stage evidence，server 不重算。
- **R-10 active pipeline snapshot 竞态**：installation-root snapshot 可能旧于 operational worktree；TASK-13 在已有 ApplySnapshot 入口复用 active pipeline_run guard。
- **R-11 workspace placeholder 误执行**：未解析路径可能诱发 Agent 全盘扫描；TASK-14 删除 pipeline executable prompt 的路径 placeholder，依赖既有 daemon env/crctl resolver。
- **R-12 migration constraint 回归**：259/263 重建约束丢失 project container 值；TASK-15 用向前 repair migration 恢复完整九值集合。

## 11. 范围排除

- 不自动执行 requirement、code、test、writeback 或四主 Pipeline 串联。
- 不修改 requirement Pipeline 的 reviewLoop 或补 CR-ID 逻辑。
- 不实现 `onFail=skip`、`code_generation`、DAG、并行分支、插件或通用 passCondition 解释器。
- 不新增 Pipeline DSL、运行表、幂等表、模板数据库、消息总线、WAL、补偿层或事务框架。
- 不让 Runner/Agent/Skill 直接执行 Git、写受控账本、递增 attempt 或推进状态。
- 不让 Runner 生成、修改、验签或代签审批 grant。
- 不建设 Runner 专用控制台、work-viewer、价值复盘 API、统计表或组织评分。
- 不提供多版本模板恢复；digest 漂移只阻断。
- 不把本 CR 验收自动解释为 Runner Main Track 立项批准。

## 12. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-17 | v0.2.0 | Ray | 回修 B-01～B-03：补五节点双重成功后置条件、并发 run 竞态验收、复用现有 replayNodes 机器 schema |
| 2026-08-18 | v0.3.0 | Ray | E2E hardening scope amendment：新增 TASK-12~15，修复 review evidence、active snapshot projection、workspace placeholder 与 origin constraint migration |

## CR 合并与新注册 Worktree 同步治理优化方案（v0.20.7 · CR-2026-046）

## PRD — CR 合并与新注册 Worktree 同步治理优化方案

### 1. 概述

#### 1.1 问题陈述

在现有 crctl 事务基础设施（远端权威、事务 workspace 生成提交、lease push 发布）上，存在两个独立缺口：

1. **缺口 A（注册基点陈旧）**：`ensureRepoWorkspace` 对 `missing` 分类直接执行 `git branch requirement/{CR-ID} {repo.trunk}`，`{repo.trunk}` 是本地 branch。即使远端 trunk 已前进，新 CR 仍可能从落后的本地 trunk 创建。且首次分类发生在 fetch 之前，本机 remote-tracking ref 过期时，远端已存在的 `origin/requirement/{CR-ID}` 不被识别。
2. **缺口 B（merge 后本地主 checkout 不跟随）**：`crctl merge` 在 detached Transaction Workspace 完成 finalize 后，不移动用户主 checkout（`dir-graph.yaml#repositories[].path`）的本地 trunk。这是正确的发布安全边界，但 clean 的本地 `main` / `custom/main` / `master` 会持续落后。

#### 1.2 解决方案摘要

两处局部修复，不新建任何事务框架：

1. `ensureRepoWorkspace` 在 `missing` 分类下先 `git fetch origin` 并重新分类：有远端 CR 分支则恢复；仍 missing 则从 `origin/{trunk}` 创建本地 CR branch。
2. `crctl merge` 在远端事务完成后，对声明的主 checkout 执行一次私有、非事务化的 best-effort ff-only 同步。

实现选择遵循 ponytail 优先级（复用现有能力 > 标准库 > 原生 Git 命令 > 最小新增代码）：
- 复用 `classifyRepoWorkspace` 二次分类，不新写分类逻辑；
- 复用 CR-2026-043 `workspace sync` 已验证的 `git merge --ff-only <preflight 捕获 SHA>` 模式，不新增合并算法；
- 全程使用 Node 标准库与原生 Git 命令，不新增依赖、不新增文件。

#### 1.3 已解决基础设施（本次直接复用，不重新设计）

| 已有能力 | 权威位置 | 本次处理 |
|---|---|---|
| 参与仓与 trunk 解析 | 工作区 `dir-graph.yaml#repositories` | 直接复用 |
| CR 注册账本 CAS、提交、lease push 与恢复 | `crctl register` + register journal | 保持不变 |
| workspace 七分类与安全补齐 | `classifyRepoWorkspace` / `ensureRepoWorkspace` | 只修正 `missing` 的基点选择 |
| 既有 CR freshness 分类与 ff-only 同步 | `crctl workspace freshness/sync` | 继续服务既有 CR，不扩展职责 |
| 跨仓 merge prepare、journal、lease publish、remote confirmation | `crctl merge` | 保持不变 |
| merge 后唯一业务编辑位置 | detached Transaction Workspace | 保持不变 |
| 状态、门禁、账本、审计与原子提交 | `crctl` | 不新增旁路 |

#### 1.4 模块职责边界

| 模块 | 应该拥有 | 本次不得增加 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 本地 trunk 同步节点、复制 Skill/crctl 算法、手写账本操作 |
| Skill | 业务前置判断、调用步骤、输入输出、失败语义 | Git 分支算法、原子账本逻辑、重复实现 crctl |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、Git 深原语、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性内容转换 | 状态推进、人工审批、本地 trunk 治理 |
| README | 面向人的流程总览 | 另一份可执行步骤或状态事实源 |

两项修改均收敛在 `../tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`。Skill 继续只调用一次深原语，Pipeline 与 README 无需增加可执行细节。

### 2. 用户故事

- **US-1**：作为 CR 注册用户，当我注册新 CR 时，即使本地 trunk 落后于远端，我希望新 CR 分支基于远端最新 trunk，以降低后续 merge 冲突面。
- **US-2**：作为续跑用户，当注册进程在分支创建后中断，我重跑注册时希望挂接同一分支，而不是另建一条平行历史。
- **US-3**：作为远端已存在 CR 分支的用户，当本机 remote-tracking ref 过期时，我重跑注册希望恢复远端分支，而不是基于 trunk 新建。
- **US-4**：作为 merge 完成后的开发用户，当我的本地主 checkout 处于 trunk 分支且 clean 时，我希望它自动 ff-only 到远端最新 trunk，无需手动 `git pull`。
- **US-5**：作为本地有未提交变更或分叉的用户，我希望本地同步静默跳过我的现场，绝不 stash/reset/rebase，且不影响已成功的远端 merge。
- **US-6**：作为 crctl 维护者，我希望本次改动不新增 Pipeline 节点、Skill、账本字段、事务框架或依赖，保持模块职责边界不变。

### 3. 功能需求

#### 注册路径（缺口 A）

- **FR-1**：`ensureRepoWorkspace` 首次分类为 `missing` 时，必须先执行 `git fetch origin`（失败即终止，见 FR-4），然后调用既有 `classifyRepoWorkspace` 重新分类；`healthy` 与 `branch-only` 分类不得触发 fetch。
- **FR-2**：重新分类为 `remote-only` 时，按现有逻辑从 `origin/requirement/{CR-ID}` 恢复（`git branch --track` + worktree 挂接），不基于 trunk 新建平行历史。
- **FR-3**：重新分类仍为 `missing` 时，必须先解析 `refs/remotes/origin/{trunk}` 存在，然后执行 `git branch requirement/{CR-ID} origin/{trunk}`（即 refs/remotes/origin/{trunk} 指向的 SHA）并创建 worktree；禁止再执行 `git branch requirement/{CR-ID} {local-trunk}`。
- **FR-4**：fetch 失败或 `origin/{trunk}` 不可解析时，返回结构化错误 `WORKSPACE_TRUNK_UNAVAILABLE`；不得创建、修改或删除 `requirement/{CR-ID}` branch/worktree，`git fetch origin` 已产生的 `refs/remotes/origin/*` 更新可以保留；禁止静默回退本地 trunk 或离线模式。
- **FR-5**：重新分类为 `dirty` / `wrong-branch` / `path-unregistered` 时，按既有规则硬阻断，不 reset、stash 或删除任何已有资源。
- **FR-6**：register journal 结构保持不变：不新增 `base-sha`、`source`、`action`、`worktree-path` 字段（本地 `requirement/{CR-ID}` ref 已是基点权威事实；`worktrees[]` 已记录逐仓进度）。

#### merge 路径（缺口 B）

- **FR-7**：远端 merge/finalize 确认后，对每个参与仓的 `repo.rootPath`（即 `dir-graph.yaml#repositories[].path` 主 checkout）调用一个私有、非事务化的 local trunk reconciliation helper；不遍历 `git worktree list` 寻找其他 checkout，不处理 CR worktree。
- **FR-8**：helper 每仓按序执行 8 个安全判据，任一不满足即结束该仓，禁止 fallback 到普通 merge/reset/stash：
  1. 读取 `repo.rootPath` 当前 branch；`branch != repo.trunk` → `skipped` / `wrong-branch`；
  2. `git status --porcelain` 非空 → `skipped` / `dirty`；
  3. `git fetch origin` 失败 → `failed` / `fetch-failed`；
  4. `origin/{trunk}` 不可解析 → `failed` / `trunk-unavailable`；
  5. local HEAD == remote HEAD → `unchanged`；
  6. local HEAD 不是 remote HEAD 的祖先 → `skipped` / `diverged`；
  7. `git merge --ff-only <捕获的 remote SHA>` 成功 → `synced`（必须使用步骤 3/4 捕获的 SHA，禁止再次解析移动 ref）；
  8. `git merge --ff-only` 执行失败 → `failed` / `ff-only-failed`。
- **FR-9**：`crctl merge` 成功输出在现有契约上增加 `localTrunkSync: []` 数组；每仓条目四态模型：
  `{ repo, trunk, before, remote, after, status: synced|unchanged|skipped|failed, reason: dirty|wrong-branch|diverged|fetch-failed|trunk-unavailable|ff-only-failed|null }`。
  字段规则固定为：`before` 是进入 helper 时可解析的本地 HEAD，否则为 `null`；`remote` 是 fetch 成功后捕获的 `origin/{trunk}` SHA，否则为 `null`；`after` 是 helper 返回时可解析的本地 HEAD，否则为 `null`。因此 wrong-branch/dirty 在 fetch 前结束时 `remote=null`，fetch-failed 时 `remote=null`，trunk-unavailable 时 `remote=null`，ff-only-failed 时 `remote` 为已捕获 SHA 且 `after` 反映命令失败后的实际 HEAD。
  只表达结果与原因，不扩展为 `skipped-dirty` 等平行状态。
- **FR-10**：远端 merge/finalize 已确认后，无论本地同步结果为 `synced` / `skipped` / `failed`，`crctl merge` 均返回 exit 0、`phase=complete`；本地同步结果不写 merge journal、不写业务账本、不改变 CR status（`merging` / `writing-back` / `archived` 语义不变）、不提供恢复流程（进程中断即不补偿，用户可原生 `git pull --ff-only`）。
- **FR-11**：后续 writeback 仍只使用 detached Transaction Workspace，不依赖本地主 checkout 同步状态。

### 4. 非功能需求

- **NFR-1（安全）**：对已有本地 branch/worktree 与主 checkout 现场零破坏：全程无 `reset`、`stash`、`rebase`、普通 `merge`、强制 checkout 或分支删除。允许的 Git 写入仅包括注册路径中 `fetch` 对 remote-tracking refs 的更新、新建 CR branch/worktree，以及本地同步路径的 `git merge --ff-only <捕获 SHA>`；不得借此引入回滚或补偿事务。
- **NFR-2（幂等）**：branch 创建后、worktree 创建前中断，重跑注册分类为 `branch-only` 并挂接同一分支；branch 创建前中断，重跑重新 fetch 最新远端事实（不冻结旧观察值）。本地同步 helper 重入安全：`unchanged` 分支保证重复执行不产生额外提交。
- **NFR-3（兼容）**：现有 register journal / merge journal / lease publish / finalize / Transaction Workspace / 状态机 / gates 行为不变；`register-tx.test.mjs`、`merge-tx.test.mjs` 既有测试全部继续通过。
- **NFR-4（最小面）**：不新增文件、不新增依赖（仅 Node 标准库 + 原生 Git 命令）、不修改 Agent / Pipeline / Skill / README / 状态机 / gates；实现收敛于 `workspace-transactions.mjs` 与两个测试文件。
- **NFR-5（审计）**：`localTrunkSync` 是本地同步的唯一观察面；不向 `crctl status` / `workspace inspect` / `resume` / 看板扩散新视图。

### 5. 验收标准

- **AC-1（对应 FR-1/3）**：本地 trunk 落后 `origin/{trunk}` 时注册新 CR，CR branch HEAD 等于 fetch 后的远端 trunk SHA。
- **AC-2（对应 FR-2）**：本机初始无 `refs/remotes/origin/requirement/{CR-ID}` 但远端已存在该分支时，fetch 重新分类后恢复远端 CR 分支，不新建历史。
- **AC-3（对应 FR-4）**：fetch 失败或 `origin/{trunk}` 缺失时，返回 `WORKSPACE_TRUNK_UNAVAILABLE`，且不创建、修改或删除 `requirement/{CR-ID}` branch/worktree；测试允许并验证 fetch 已产生的 remote-tracking ref 更新不会被额外回滚，且不得回退到本地 trunk。
- **AC-4（对应 FR-5）**：`healthy`、`branch-only`、`dirty`、`wrong-branch`、`path-unregistered` 现有保护测试继续通过；`healthy`/`branch-only` 不产生 fetch。
- **AC-5（对应 FR-6）**：register journal 结构无新字段，既有 register journal 测试通过。
- **AC-6（对应 FR-8/9）**：表驱动测试覆盖：clean+behind → `synced` 且 HEAD == 捕获 SHA；already current → `unchanged`；dirty / wrong-branch / diverged → `skipped` 且 reason 正确、本地现场字节级不变；fetch-failed / trunk-unavailable / ff-only-failed → `failed` 且 reason 正确。所有结果均断言 `before`、`remote`、`after` 遵循 FR-9 的 SHA/null 规则；failed 场景还必须断言远端 merge 已成功、exit 0、`phase=complete`，且本地主 checkout 现场不被修改。
- **AC-7（对应 FR-10）**：所有 `skipped` / `failed` 场景下，`crctl merge` 返回 exit 0、`phase=complete`，远端 merge 结果不受影响；`localTrunkSync` 输出符合 FR-9 四态契约。
- **AC-8（对应 FR-11/NFR-3）**：现有 merge journal、lease publish、finalize、Transaction Workspace 与重入测试继续通过。

### 6. 成功指标

- 新 CR 初始基点与 fetch 后远端 trunk 不一致的案例数归零（注册路径测试覆盖）。
- merge 完成后 clean 本地主 checkout 落后远端的状态在下次 `crctl merge` 后自动消除（`synced`），不再需要手动干预。
- 既有 CR 注册/merge 测试套件零回归。
- 实现 diff 仅涉及 `workspace-transactions.mjs` 与两个测试文件，无新增文件/依赖。

### 7. 范围排除

1. 不新建第二套事务框架：不增加 WAL、补偿事务、持久化 reconciliation intent、durable journal、intent digest、recoverCommand、跨仓补偿或新的状态机。
2. 不建设分阶段诊断：不扩展 `crctl status`、`workspace inspect`、`resume` 或看板；不扫描、批处理或迁移历史 CR；不把 installation trunk 状态混入 CR workspace authority 视图。
3. 不增加 register journal 字段（`base-sha` / `source` / `action` / `worktree-path`）。
4. 不为本地同步增加事务恢复、失败回滚或状态推进；不因本地同步失败回滚已成功的远端发布。
5. 不单列 `skipped-in-use`、`skipped-missing`、`history-rewritten` 等状态；统一四态 + reason。
6. 不自动 checkout trunk、不遍历其他 worktree、不修改 CR worktree。
7. 不新增 Pipeline 节点、Skill Git 算法、README 可执行细节；既有 CR 不迁移，继续按 `workspace freshness/sync` 显式处理。

## P3 组织智能 CR-A：AI 成熟度看板（E1 快照 / E2 看板 / E3 周报）（v0.21 · CR-2026-047）

## PRD — P3 组织智能 CR-A：AI 成熟度看板

### 1. 概述

#### 问题陈述

管理层需要回答两个问题：「AI 原生转型进行到哪了」与「交付系统有没有变好」。P0–P2 已把每一次任务执行（`task_usage`）、状态推进（`cr_sync_event`）、审批（`approval_record`）、reviewLoop（`pipeline_node_run.attempt`）、点踩（P2 反馈）、越权拦截（P1 §C.5）都落成了结构化行，但缺少一个把这些行聚合为可读视图的读侧。CR-A 交付该看板的第一个可用版本。

#### 解决方案摘要

设计主线：**P3 不新增采集管道，只做已有事件的聚合与呈现**。CR-A 交付三个严格依赖的交付物（E1→E2→E3 一条线）：

- **E1 — 口径配置 + 快照数据管道**：`maturity-config.yaml`（落本仓）+ 配置生成器（照抄 `governance/gen/generate-transitions.mjs` 模式）+ `maturity_snapshot` 快照 rollup 任务（挂 `sys_cron_executions`）。
- **E2 — 看板前端**：趋势 / 排名 / 治理板块，5 维 8 项子指标，无个人榜，观察期（4 周）内无雷达图。
- **E3 — Org Admin Workspace 内置项目 + 周报 Autopilot**：平台自身的一个真实项目产出周报与建议（吃自己的狗粮），报告落盘不经 git，看板直接渲染。

只有 **1 张新表**落库（`maturity_snapshot`），其余全部读时聚合。快照表存在的唯一理由是**历史不可变**：口径（权重/阈值）会随季度改，而「当时那套口径下的分数」必须能重现——这是读时聚合做不到的唯一事情（不是查询性能、不是避免重算，日粒度量级下这两条都不成立）。

#### 范围边界（注册阶段已拍板，本 PRD 原样采纳）

- 目标版本 0.21，开工前置无。
- CR-A 只含 E1/E2/E3；个人榜、资产复用率（第 9 项子指标）、交付效能板块、基线校准写入 config、待我审批端点均属 CR-D，不在本 CR。
- Skill Market（E6）属 CR-B；追溯查询 + 漂移检测（E4/E5）属 CR-C，均不在本 CR。
- 文档 §1.5/§1.6 描述的是目标态个人榜；本 CR 以更新的 §5.1/§5.2 重切表为准：排名仅支持 project，user 榜及其 Owner 开关整体推迟到 CR-D。

#### 依赖与风险

- **既有能力依赖**：`task_usage` + `agent_task_queue.initiator_user_id`、`governance/gate_projection.go`、P1 D7 `activity_log`、`sys_cron_executions`、Team Agent/inbox，以及 `packages/views/dashboard/components/` 现成组件；CR-A 不重建这些能力。
- **CR 间依赖**：CR-A 开工前置无，内部依赖为 E1→E2→E3；CR-B/CR-C 与本 CR 无代码前置，CR-D 反向依赖 CR-A 上线满 4 周及 CR-B。
- **主要风险**：既有事件缺行会直接反映为指标缺失；必须通过快照完整率与治理板块暴露，不得新增采集旁路来掩盖。

### 2. 用户故事

| ID | 角色 | 行为 | 价值 |
|---|---|---|---|
| US-1 | 管理者 | 在一个看板看到组织 AI 采用的整体趋势、项目横向排序 | 判断「AI 原生转型进行到哪了」 |
| US-2 | 管理者 | 看到数量指标（如 Token 强度）与质量护栏（如门禁一次通过率）同屏成对呈现 | 避免「用得多」被误读为「用得好」 |
| US-3 | 管理者 | 每周自动收到一份诊断报告，且在看板上可读 | 不用手动拼数据即可获得趋势解读 |
| US-4 | 团队成员 | 在 Team Agent 里对周报内容追问（如「为什么 EPC 掉了？」） | 获得对话式解读而非只读报告 |
| US-5 | QA / Tech Lead | 在治理板块看到门禁一次通过率、证据漂移、追溯完整率、审批时延、越权尝试次数 | 定位质量与护栏问题 |
| US-6 | 平台管理员 | 口径（权重/阈值）版本化配置，且生成器 `--check` 能校验与 Go 副本无漂移 | 改口径走治理动作而非散落硬编码 |

### 3. 功能需求

#### E1 — 口径配置 + 快照数据管道

- **FR-1** `maturity-config.yaml` 落**本仓**（knowledge-base），承载 5 维 8 项子指标的权重、阈值（`floor`/`target`）与观察期配置；权重与阈值集中于此，不硬编码。
- **FR-2** 配置生成器照抄 multica 已有先例 `governance/gen/generate-transitions.mjs`：读 yaml 声明 → 吐只读 Go 副本（文件头记源 commit SHA）→ 副本提交入库 → `--check` 模式在 CI/pre-commit 重生成并 diff，漂移则非零退出。
- **FR-3** `config_rev` = `maturity-config.yaml` 所在 commit 的 SHA（不手维版本号）。
- **FR-4** 新增 `maturity_snapshot` 表（DDL 见设计 §1.3）：`bucket_date DATE` + `scope TEXT CHECK IN ('org','user','project')` + `scope_id TEXT`（org 固定 `·`）+ `metrics JSONB` + `scores JSONB`（观察期内 `'{}'`）+ `config_rev TEXT` + `created_at TIMESTAMPTZ`，`PRIMARY KEY (bucket_date, scope, scope_id)`。
- **FR-5** 快照 rollup 任务挂 `sys_cron_executions`，每日 00:30 本地时区（`Asia/Shanghai`）跑前一天快照。JobSpec 照抄 `jobs_autopilot.go`：`Cadence: 0` + `PlansForScope`（固定 cron `30 0 * * *` 经现成 `service.NextOccurrencesUTC(expr, "Asia/Shanghai", after, now)` 求解）+ `CatchUpMode: CatchUpEveryPlan` + `MaxPlansPerTick: 7` + `CatchUpWindow: 7×24h` + `Scopes: StaticScopes(global)`。
- **FR-6** 水位线口径照抄 `rollup_task_usage_hourly()` 范本（`pg_try_advisory_xact_lock` + 有界窗口 + 单事务内 upsert 与水位推进同时提交）；水位 = `MAX(bucket_date)`，自带在表里，**不**复用上游 `task_usage_hourly_rollup_state` 状态表。
- **FR-7** 观察期内（§1.2）`scores` 不计算（落 `{}`），`metrics` 照常落库；历史快照不可变，口径变更只影响 `config_rev` 之后的新行，趋势图跨口径处标注断点。
- **FR-8** 一个任务内部遍历 org/user/project 三个 scope 写多行，**不**把 scope 展开成调度器级 Scope。

#### E2 — 看板前端

- **FR-9** 看板顶部：日期区间选择 + Owner mode 标记 + 「每日 00:30 更新前一天数据」。
- **FR-10** 统计条：活跃成员、Token 总消耗、（可选）估算成本——成本列可选，价目表为可编辑 `model-prices.yaml`，不精确、仅供量级参考，UI 明确标注「估算」。
- **FR-11** Token 趋势图按日，可下钻项目/个人/模型。
- **FR-12** 排名区只提供项目排名；CR-A **不实现个人榜、Owner 开关或全员开启通知**，这些能力整体随 CR-D 交付。
- **FR-13** 观察期（4 周）内**不出雷达图**，改用 `dim-segmented` + `usage-trend-card` + `leaderboard` 三件现成组件（`packages/views/dashboard/components/`）。
- **FR-14** 5 维 8 项子指标计算，`score = clamp(100 × (x − floor) / (target − floor))`，归一化到 0–100：
  - AIF：Token 强度（`task_usage` join `agent_task_queue.initiator_user_id` ÷ 活跃成员数，**不走无 user 维的 `task_usage_hourly`**）、AI 渗透率（当期发起 ≥1 个 Agent 任务的成员 / 全体成员）。
  - SII：人均 CR 吞吐（归档 CR 数 / 活跃成员数）。
  - OFI：项目协作规模（`cr.owners` ∪ `comment` ∪ `agent_task_queue`；目标区间计分，低于 2 不加分）、项目活跃率（近 14 天有任务或状态推进的项目 / 全部项目）。
  - EPC：原型直出率（`pipeline_node_run(attempt)` 一次通过，已由 `governance/gate_projection.go` 写入）。
  - ACM：Team Agent 使用深度（经共享队列有 cr_id/issue_id 归属的任务 / 全部任务）、流程完整率（走完 4 条必跑 pipeline 归档的 CR / 归档 CR）。
- **FR-15** 治理板块（不进总分，单独呈现）：门禁一次通过率、`EVIDENCE_DRIFT` 发生次数、追溯完整率、审批时延 P50/P90、越权尝试次数（gitguard FORBIDDEN 拒绝计数）。
- **FR-16** 数量指标必须与质量护栏成对呈现（Token 强度旁永远并排门禁一次通过率）；指标定义页明写每个指标的已知可刷性；此立场写进看板页脚。
- **FR-17** API 面：`GET /api/maturity/overall`、`/token-trend`、`/rankings?scope=project`、`/suggestions[/history]`、`/config`（全员可读）；CR-A 不接受 `rankings?scope=user`，user 榜 API 与开关随 CR-D。
- **FR-18** 看板做成主应用一个 route（复用 `packages/views` 体系），不做独立子域名 iframe。

#### E3 — Org Admin Workspace 内置项目 + 周报 Autopilot

- **FR-19** 内置项目 **Org Admin Workspace**（对应快照里的 `org-admin-avatar` 内置 Agent）。
- **FR-20** 每周 Autopilot：读取最近的 `maturity_snapshot` 序列 + 治理板块异常 → 生成诊断报告落盘 `docs/org-admin/maturity-review-{YYYY-Www}.md`（Org Admin Workspace 项目工作区内的普通目录，**不经 git**）→ 经 inbox 通知 Owner。
- **FR-21** 诊断模板按 AI 净价值「四收益一成本」框架组织：个人效率 / 团队交付 / 知识复利 / 风险收益四节 + 成本一节，每节引用对应板块指标。
- **FR-22** 看板「建议」区直接渲染该目录最新文件；历史 = 目录内历史文件序列（免费获得原产品的 suggestions/history 能力）。
- **FR-23** 建议的生成过程走 Team Agent 消息流，可追问、可继续对话。
- **FR-24** 第 4 周周报内含自算的分位数基线建议（floor ≈ P10、target ≈ P75，**不自动写入 config**，提请人审）。

### 4. 非功能需求

- **NFR-1** 新迁移从 **375** 起；**禁新增 FOREIGN KEY**；每个索引必须 `CREATE INDEX CONCURRENTLY` 且一个迁移文件一条（multica `CLAUDE.md` 硬规则）。
- **NFR-2** 不新建任何事务/队列/outbox 抽象（仓内已有三套：crctl 文件 outbox + `cr_sync_event` 幂等账本、`webhook_delivery` 租约投递、`agent_task_queue` 的 `FOR UPDATE SKIP LOCKED`）。
- **NFR-3** 快照任务用 `CatchUpEveryPlan`（**不用 `CatchUpLatestOnly`**），服务器停 3 天后恢复须补全三天快照，不得永久缺行。
- **NFR-4** 构建 multica 永远不需要 checkout 本仓（生成器模式的关键收益，否则服务器多一个运行时跨仓文件依赖）。
- **NFR-5** 隐私与反 Goodhart：CR-A 不提供个人排名 UI、user 排名 API 或开启开关；Token 消耗是行为数据，不做个人考核依据。个人榜后续若由 CR-D 引入，开启动作必须对全员可见。
- **NFR-6** 日粒度，不做指标实时化。

### 5. 验收标准

| ID | 覆盖 FR | 可执行验收 |
|---|---|---|
| AC-1 | FR-1、FR-3 | 给定包含 5 维 8 项子指标、权重、`floor`、`target` 与观察期的 `maturity-config.yaml`，生成结果中的 `config_rev` 等于该 yaml 所在 commit SHA，仓内无手工版本号。 |
| AC-2 | FR-2 | 声明与只读 Go 副本一致时生成器 `--check` 退出 0；任改一项声明但不重生成时退出非 0；副本文件头包含源 commit SHA。 |
| AC-3 | FR-4 | 在空库执行从 375 起的迁移后，仅新增 `maturity_snapshot` 表；列、CHECK、主键与默认值均符合 FR-4，且无 FK；索引均使用 `CONCURRENTLY` 且一文件一条。 |
| AC-4 | FR-5、FR-8 | 固定时钟跨过 Asia/Shanghai 00:30 后只计划前一天一个 global plan；执行该 plan 后同一任务写出 org/user/project 三类行，调度表不按用户或项目扩增 Scope。 |
| AC-5 | FR-6 | 同一 `bucket_date` 重跑不产生重复行；并发执行只有一个持有 advisory lock；失败回滚时快照与 `MAX(bucket_date)` 同时不前移。 |
| AC-6 | FR-7 | 观察期内连续 3 天均有 `metrics` 且 `scores={}`；改 config 后新行 `config_rev` 变化、旧行摘要不变；跨 revision 查询返回可供 UI 标注的断点。 |
| AC-7 | FR-5、FR-6 | 模拟服务器停 3 天后恢复，一个 tick 补齐缺失 3 个日桶（`CatchUpEveryPlan`）；缺失不超过 7 天时最多计划 7 个桶。 |
| AC-8 | FR-9、FR-10 | 页面首屏同时显示日期区间、Owner mode 标记、更新说明、活跃成员与 Token 总消耗；启用成本列时读取 `model-prices.yaml` 且数值旁显示「估算」。 |
| AC-9 | FR-11 | 给定项目、用户、模型三组夹具，按日趋势汇总分别与源数据一致，切换 project/user/model 下钻不改变日期总量。 |
| AC-10 | FR-12 | 默认页面只显示项目排名；页面与接口均不存在个人排名入口、Owner 开关及开启通知。 |
| AC-11 | FR-13 | 观察期页面不渲染雷达图，仅渲染 `dim-segmented`、趋势与项目横向排序三件式。 |
| AC-12 | FR-14 | 对 8 项子指标各提供至少一组已知输入夹具，原始值逐项符合 FR-14 公式；`x≤floor` 得 0、`x≥target` 得 100、中间值按线性公式计算；总分只使用这 8 项及配置权重。 |
| AC-13 | FR-15 | 治理板块同时返回并展示 5 类指标（门禁一次通过率、`EVIDENCE_DRIFT`、追溯完整率、审批时延 P50/P90、越权尝试次数），且改变任一治理值不改变成熟度总分。 |
| AC-14 | FR-16 | 所有 Token 强度视图均与门禁一次通过率同屏；指标定义页列出 8 项指标的已知可刷性；页脚明确 Token 不作个人考核依据。 |
| AC-15 | FR-17 | `overall`、`token-trend`、`rankings?scope=project`、`suggestions`、`suggestions/history`、`config` 合约测试均通过且 `config` 无需 Owner 权限；`rankings?scope=user` 返回明确不支持，不泄露个人榜数据。 |
| AC-16 | FR-18 | 看板可从主应用 route 直接访问并复用 `packages/views`；构建产物中不存在独立子域名或 iframe 集成。 |
| AC-17 | FR-19 | 初始化组织后存在唯一的 Org Admin Workspace 与对应 `org-admin-avatar` 内置 Agent，重复初始化不产生副本。 |
| AC-18 | FR-20 | 周任务读取最近快照和治理异常后，生成唯一 `docs/org-admin/maturity-review-{YYYY-Www}.md`，文件不进入 git，并向 Owner inbox 产生一条通知。 |
| AC-19 | FR-21 | 生成报告固定含个人效率、团队交付、知识复利、风险收益、成本五节，每节至少引用一个对应板块指标。 |
| AC-20 | FR-22 | 建议区渲染目录中周次最新文件；历史接口按周次返回全部历史文件；空目录返回明确空态而非错误。 |
| AC-21 | FR-23 | 从报告发起追问后进入同一 Team Agent 消息流，连续两轮追问均保留报告上下文并得到回复。 |
| AC-22 | FR-24 | 第 4 周报告基于四周实测分布给出 floor≈P10、target≈P75 的建议值；执行前后 `maturity-config.yaml` 内容与 commit SHA 均不变。 |

### 6. 成功指标

- 首个 4 周观察期内应生成的日快照完整率为 **100%**；7 天窗口内的停机恢复后无永久缺桶。
- 前 4 周周报按计划生成率为 **100%（4/4）**，每份均可在看板读取并从 Team Agent 发起追问。
- 第 4 周周报产出 **1 份**基线建议，包含全部 8 项子指标的 floor≈P10 / target≈P75 建议，且配置零自动写入。
- 治理板块 **5 类指标全部可见**，且治理值变化不会改变成熟度总分。

### 7. 范围排除

本 CR 明确**不做**（含去向）：

- 个人榜及其 `rankings?scope=user`、Owner 开关、全员开启通知（整体随 CR-D；设计 §1.5/§1.6 为目标态描述）。
- 资产复用率（第 9 项子指标，依赖 Skill Market 遥测，随 CR-D）。
- 交付效能板块（E7：Lead Time / Review 负担 / 变更失败率，随 CR-D）。
- 基线校准写入 config（第 4 周只「建议」不「写入」，随 CR-D）。
- 待我审批端点（随 CR-D）。
- 超级个体占比（SII 子指标，随 CR-D）。
- 观察期内雷达图（观察期内用三件式布局替代）。
- Skill Market（E6：可见性/版本/排行/发布门禁/遥测/元数据卡/敏感扫描，随 CR-B）。
- 跨 CR 追溯查询 + 漂移检测（E4 trace event_kind + E5 前缀扫描/drift_finding，随 CR-C）。
- 通用 Pipeline Runner（读侧投影已由 `governance/gate_projection.go` 交付，属 M1/A2）。
- LLM 对齐巡检（`review-alignment` / `change-impact-analysis` 定时化，七跳链路静默风险）。
- 跨组织对标、个人绩效导出/API、指标实时化、Skill 付费/积分机制、bypass 通路层对账（延后 P3+）。

## P3 组织智能 CR-B：内部 Skill Market（E6）（v0.22 · CR-2026-048）

## PRD — P3 组织智能 · 内部 Skill Market

> 依据：`docs/product/P3-组织智能设计.md` §3（内部 Skill Market）、§5.1 CR-B、§5.2 E6、§7（2026-08-19 第二轮评审 23 项决议）；`docs/analysis/P3组织智能-开工前代码核对评审.md`（评审方法与证据链）。
> 本 CR 与 CR-2026-047（CR-A，成熟度看板）**零交集、可真并行**：B 动 `skill` 表与 Market 前端，A 动 `maturity_snapshot` 与看板，无共享表、无共享端点。

### 1. 概述

#### 1.1 问题陈述

个人沉淀的工作方法目前停留在两个地方：一是各自机器上的私有 SKILL.md，二是口口相传。平台已有 `skill` / `skill_file` 表并兼容 Anthropic Agent Skills 标准；当前按 `tools/skills/_index.yml` 的 active 条目核对为 **56 个**内置方法论 Skill（P3 §3.1/§3.3 中的“59”是待回写的陈旧数字，不作为本 CR 验收口径），但**缺三样东西**，导致资产无法在组织内流通：

1. **没有可见性概念**——Skill 要么是某人的，要么是内置的，没有"我发布给团队用"这个动作，因此也没有"发布即授权"的语义边界；
2. **不知道什么被用了**——没有任何地方记录"哪个任务用了哪些 Skill"，于是无法回答"沉淀有没有被扩散"（P3 §1.2 资产复用率的数据源缺失），也无法给出使用量排行；
3. **复用者拿不到使用说明**——`ParseSkillFrontmatter` 只提取 `name` 与 `description` 两个字段，一个 Skill 适用什么场景、依赖什么上下文、能读写哪些目录、失败了怎么办，全靠读正文或问作者。

同时存在一条隐私风险：如果把"发布"做成简单的可见性翻转，作者机器上的 API Key、内网凭据、个人路径会随 SKILL.md 一起进入组织视野。

#### 1.2 解决方案摘要

把个人 Skill 到组织资产的流通面补齐，**增量收敛为三块**：`skill` 表加三列、新增一张 append-only 遥测表、发布路径加一道门禁。四条设计取向：

- **可见性只有两档**（`private` / `org`）——内部平台没有"公开发布"这一档；
- **遥测采集点在服务端任务认领路径**，不新增任何跨进程字段；
- **敏感扫描复用既有 `redact` 包的同一份正则表**，只加一个定位入口与一条新模式；
- **`version` 只是展示字段**，"内容是否变了"一律用既有的内容哈希判定。

#### 1.3 已解决基础设施（本次直接复用，不重新设计）

| 能力 | 现成件 | 本次用法 |
|---|---|---|
| Skill 存储与文件 | `skill` / `skill_file` 表（`server/migrations/008_structured_skills.up.sql`，`UNIQUE(workspace_id,name)` / `UNIQUE(skill_id,path)`） | 只加列，不重建 |
| 内容身份 | `pkg/skillbundle.BuildManifest(skill).Hash`（`handler/daemon.go:3382` 已用它判定包变更） | 一切"内容是否变化"判定的唯一依据 |
| 内置 Skill 标识 | `service/task.go:5840 BuildAgentSkillBundles`，对 `id == ""` 现场合成 `"builtin:" + Name`（`skillbundle.SourceBuiltin`） | 遥测的 `skill_ref` 直接沿用该合成 id |
| 权威 Skill 清单 | `handler/daemon.go:1982-2070`：服务端在任务认领时算出 `[]AgentSkillRefData{ID,Source,Name,Hash,…}` 并发给 daemon（当前未持久化，:3308 那次 marshal 仅用于日志字节数统计） | 遥测采集点，零新增探针 |
| 密钥检测 | `server/pkg/redact`：16 条 patterns（AWS / GitHub PAT 两形制 / OpenAI `sk-` / Slack 两形制 / GitLab / Google / Stripe / JWT / Bearer / PEM / 连接串嵌密码 / 通用 `KEY=VALUE`）+ `Text()` / `InputMap()` | 敏感扫描复用同一份 `patterns` |
| frontmatter 解析 | `internal/skill/frontmatter.go:27 ParseSkillFrontmatter`（CRLF 容错，仅返回 name/description） | 扩展提取范围，不另写解析器 |
| 审计留痕 | `activity_log` + `internal/governance/audit.go` 的封闭 action 白名单模式（`auditActions`，防伪造） | 放行记录沿用该模式加一个 action 值 |
| 权限判定 | `handler/skill.go:406 canManageSkill`（workspace owner/admin 或 creator） | 发布权限在其基础上判定，不另建角色体系 |
| 前端 | `packages/views/skills/`（components / hooks / lib 已在位） | Market 列表与详情页在该域内扩展 |

**明确不重建的三样**：不新建事务/队列/outbox 抽象（仓内已有三套可用机制）；不新建 Skill 内容哈希；不新建密钥正则表。

#### 1.4 模块职责边界

| 层 | 职责 | 不做 |
|---|---|---|
| 迁移（`server/migrations/`，编号从 **380** 起） | 加三列 + 建遥测表 + 索引 | 不加 FK、不加级联 |
| 认领路径（`handler/daemon.go`） | 算出 skillRefs 后写遥测行 | 不改 `TaskCompleteRequest`、不碰 `sanitizeTaskCompleteRequest` |
| 发布路径（`handler/skill*.go`） | 门禁校验 + 敏感扫描 + 可见性翻转 | 不实现"公开发布"档、不为 builtin 写特判分支 |
| `pkg/redact` | 新增 `Findings()` 定位入口 + 第 17 条模式 | 不新增第二份 patterns |
| 前端（`packages/views/skills/`） | 列表 / 排行 / 详情页使用说明卡 / 发布确认框 | 不开新的写通路 |

### 2. 用户故事

- **US-1**（Skill 作者）：作为把某个工作方法打磨成熟的开发者，我希望把私有 Skill 发布给组织，并在发布时清楚看到"这等于授权团队复用我的工作方法"，这样沉淀才有意义而不只是躺在我机器上。
- **US-2**（Skill 作者）：作为发布者，我希望平台在发布前拦住我 SKILL.md 里可能残留的密钥与个人路径，并告诉我第几行命中了什么，这样我不必靠自己逐行检查来保证不泄漏。
- **US-3**（复用者）：作为想用别人 Skill 的工程师，我希望在详情页直接看到它适用什么场景、依赖什么上下文、能读写哪些目录、失败了找谁，这样我不用去问作者或读全文。
- **US-4**（Owner / 管理者）：作为组织 Owner，我希望看到哪些 Skill 真的被使用、被谁使用，这样"沉淀有没有被扩散"是有数据的，而不是靠感觉。
- **US-5**（Owner）：作为处理误报申诉的 Owner，我希望逐条确认放行且每次放行都留痕，这样"拦截是默认、放行是例外"这条边界可审计。

### 3. 功能需求

#### 数据面

- **FR-1**：`skill` 表新增三列：`visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','org'))`、`version TEXT NOT NULL DEFAULT '0.1.0'`、`owner_actor TEXT`。**不得包含 `builtin` 枚举值**——内置 Skill 在 `skill` 表里没有行（`service/task.go:5851`），给不存在的行加枚举值是死代码。
- **FR-2**：新增 `skill_usage_event` 表：`id UUID PRIMARY KEY DEFAULT gen_random_uuid()`、`skill_ref TEXT NOT NULL`、`task_id UUID`、`project_id UUID`、`used_at TIMESTAMPTZ NOT NULL DEFAULT now()`。**`task_id` 与 `skill_ref` 均不得设外键**：仓硬规则禁新增 FK 与级联，且遥测本质是 append-only 审计行，指向已删除 Skill 的历史行应当保留。为支持完成任务过滤与排行聚合，新增 `(task_id)` 与 `(skill_ref, used_at)` 两个索引；每个索引各自放在独立迁移文件中。
- **FR-3**：`skill_ref` 取值两形制——workspace Skill 为其 `skill.id` 的文本形式，内置 Skill 为 `"builtin:" + Name`（沿用 `BuildAgentSkillBundles` 的合成规则，不另定义）。
- **FR-4**：`version` 为**纯展示字段**。任何"内容是否发生变化"的判定必须使用 `skillbundle.BuildManifest(skill).Hash`；**禁止以比较 `version` 值作为内容变更依据**。workspace Skill 的创建、编辑与详情响应可读写/展示该字段；更新版本号本身不触发内容变更判定，也不改变历史遥测事件的 `skill_ref`。

#### 遥测采集

- **FR-5**：在服务端任务认领路径（`handler/daemon.go` 的 `useSkillRefs` 分支，即已算出 `skillRefs` 之后）为每个 ref 写一行 `skill_usage_event`。写入失败不得阻断任务认领（遥测是观测面，不是门禁），失败记日志。允许同一任务多次 claim 产生多行 append-only 事件；任务 claim 路径写入的 `task_id` 必须对应当前任务。
- **FR-6**：**`TaskCompleteRequest` 与 `sanitizeTaskCompleteRequest` 零改动**，禁止新增 `skills_used[]` 或任何等价字段。理由：该 sanitize 函数注释明写漏加字段会重现 GH #7098（NUL 字节 → SQLSTATE 22P05 → 任务永久卡在 `running`）。
- **FR-7**：`used_at` 的语义是"**派发时物化**"而非"完成时使用"，该语义必须写入指标定义页与 `skill_usage_event` 的表注释。所有使用量/复用率排行查询必须 join `agent_task_queue`，显式带 `agent_task_queue.status = 'completed'`，并按 `(task_id, skill_ref)` 去重计数；同一任务重试后最终完成只计一次，重试后最终失败计零。原始事件行仍可用于诊断，不得把原始行数直接当作使用次数。

#### 发布门禁

- **FR-8**：`private → org` 的发布动作触发服务端校验，任一项不通过即拒绝发布并返回结构化错误码与失败原因，不做部分放行；所有校验通过时才原子地完成可见性更新。
- **FR-9**：校验项一——`name` 与 `description` frontmatter 必填；缺失任一字段必须返回对应结构化错误码。
- **FR-10**：校验项二——org 可见的 Skill 必须指定**一个且仅一个非空** `owner_actor`；无 owner 或 owner 值不唯一的发布被拒。这里的“唯一”指每个 Skill 只有一个负责人身份，不要求全组织 owner_actor 全局唯一。
- **FR-11**：校验项三——**资产元数据卡四字段必填**：`applicable-scenarios`（适用什么场景）、`context-dependencies`（依赖什么上下文）、`permission-declaration`（能读写哪些目录）、`failure-handling`（失败后怎么办）。缺任一字段发布被拒，错误指出字段名。
- **FR-12**：校验项四——SKILL.md 通过 `validate-doc` 结构校验（daemon 侧执行）；校验失败不得改变 visibility。
- **FR-13**：`permission-declaration` 中声明了 P1 `rules.json#protectedPaths` 内路径的，发布响应和详情页给出**警告**（不阻断、不改写声明）；警告必须可被验收测试读取。
- **FR-14**：**不得为"builtin 不可编辑"编写任何特判分支**——该性质由"内置 Skill 不入 `skill` 表"天然成立。新增 `is_builtin` 类判断字段或分支视为违反本条。

#### 敏感信息扫描

- **FR-15**：在 `server/pkg/redact` 新增 `Findings(s string) []Finding` 入口，`Finding` 至少含命中模式标识、行号、片段摘要。该函数**必须与 `Text()` 共用同一个 `patterns` 变量**；新增回归测试断言包内只存在一份 patterns 定义，防止日后平行出第二份。
- **FR-16**：在既有 16 条模式上新增第 17 条**个人路径模式**（覆盖 `/Users/<name>`、`C:\Users\<name>`、`/home/<name>` 三形制）。
- **FR-17**：发布校验时对 SKILL.md 正文与该 Skill 的全部 `skill_file` 内容执行扫描；**命中即拦截**，并向作者返回每一处命中的位置（文件 + 行号 + 模式标识）。
- **FR-18**：作者可对某个命中项提交误报申诉；申诉以 `appeal_id = hash(skill_ref, content_hash, file, line, pattern_id)` 绑定当前内容与精确命中项，Owner 才能逐条确认放行，不支持批量一键放行。使用既有 `activity_log` 作为 append-only 状态账本：提交、确认、拒绝均写入封闭 action；同一 `appeal_id` 的重复提交/重复决定幂等；内容哈希变化后旧放行自动失效，不能绕过新内容扫描。每次放行含放行人、时间、Skill、内容哈希与命中项标识，且 action 值须加入 `governance/audit.go` 风格的封闭白名单，防伪造。

#### 前端

- **FR-19**：Market 列表展示作者、版本、使用量排行；workspace Skill 的排行由 `skill_usage_event` 聚合，按已完成任务的 `(task_id, skill_ref)` 去重，内置 Skill 也必须能上榜（其 `skill_ref` 为 `builtin:<name>`）。workspace Skill 展示其 `version`，builtin 展示 tools 包版本/ builtin 标识，不为 builtin 伪造 `skill` 行。
- **FR-20**：详情页把**org 可见 workspace Skill** 的元数据卡四字段渲染为"使用说明卡"；builtin Skill 的元数据卡补齐属于 tools 包基线，不作为本 CR 的发布门禁或新增数据库字段。
- **FR-21**：详情页展示运行时要求标签（该 Skill 需要哪些本机 CLI / 网络 / TTY），从 SKILL.md 既有前置要求按确定性规则半自动提取；无法识别的要求不阻断详情页，显示原文/不生成错误标签。
- **FR-22**：发布确认框明示"发布 = 授权团队复用该工作方法"。
- **FR-23**：带 `source: session-export` 标记的草稿在列表中可筛选；该 marker 从 SKILL.md frontmatter 解析读取，不新增 `skill` 表列，列表筛选与详情显示使用同一解析结果。

### 4. 非功能需求

- **NFR-1（迁移合规）**：新增迁移编号从 **380** 起（CR-2026-047 已占用 375–379）；每个索引必须 `CREATE INDEX CONCURRENTLY`，且**一个迁移文件只含一条索引语句**；up / down 成对。
- **NFR-2（无外键）**：本 CR 不得新增任何 `FOREIGN KEY` / `REFERENCES` / 级联删改；关系与依赖清理在应用层解决。
- **NFR-3（性能）**：遥测写入在任务认领路径上，单任务新增写入量与其 Skill 数同阶（典型 < 10 行），不得引入额外往返或阻塞认领；排行查询走 `skill_ref, used_at` 索引，完成任务过滤走 `task_id` 索引，查询计划不得退化为对遥测表的无约束全表扫描。验收使用固定 fixture 与 `EXPLAIN (FORMAT JSON)` 检查索引条件/扫描范围；不得以小表偶然选择 seq scan 作为唯一证据。
- **NFR-4（安全）**：敏感扫描是发布路径的**默认拦截**而非提示；放行必须留痕。扫描结果中回传给前端的片段摘要不得包含命中的密钥明文。
- **NFR-5（兼容性）**：三列均有默认值，存量 Skill 迁移后自动为 `private` / `0.1.0` / `NULL`，不影响既有 Skill 的使用与 daemon 侧物化；`TaskCompleteRequest` 契约不变，旧版 daemon 无需升级。
- **NFR-6（仓规约）**：multica 仓代码注释一律英文；自研代码带 `// AIFIRST:` 标记（`.sql` 用 `-- AIFIRST:`）；全部改动登记 `../multica/CUSTOM.md`。

### 5. 验收标准

- **AC-1**（对 FR-1/FR-2/NFR-1/NFR-2）：迁移应用后 `skill` 表含三列且 `visibility` 的 CHECK **只有 `private` 与 `org` 两值**；`skill_usage_event` 表存在且 `information_schema` 查不到本 CR 新增的任何外键约束；新增 `(task_id)` 与 `(skill_ref, used_at)` 索引各在独立迁移文件中，所有新增索引语句均为 `CONCURRENTLY`。
- **AC-2**（对 FR-4）：修改一个 Skill 的内容但不改 `version`，系统仍能判定内容已变（`BuildManifest().Hash` 变化）；改 `version` 但不改内容，判定为内容未变；版本更新在列表/详情可见。
- **AC-3**（对 FR-3/FR-5/FR-19）：派发一个使用了 1 个 workspace Skill 与 1 个内置 Skill 的任务，`skill_usage_event` 新增两行，`skill_ref` 分别为该 Skill 的 uuid 文本与 `builtin:<name>`；Market 排行页两者均可见，且显示的 workspace 使用量为 1。
- **AC-4**（对 FR-6）：本 CR 的 diff 中 `TaskCompleteRequest` 结构体与 `sanitizeTaskCompleteRequest` 函数**零改动**（评审以 diff 为证）。
- **AC-5**（对 FR-7）：同一任务对同一 Skill 先后 claim 两次后最终 `completed`，遥测表有两行但使用量只计 1；另一任务反复重试后最终失败，遥测行不计入使用量；所有相关查询都带 `status='completed'`、按 `(task_id, skill_ref)` 去重，表注释含"派发时物化"语义说明。
- **AC-6**（对 FR-8/FR-9）：name 或 description 任一缺失时 org 发布返回对应结构化错误且 visibility 保持 private；四项校验全部通过时才完成一次性 private→org 更新，失败不能部分更新。
- **AC-7**（对 FR-10/FR-11）：未指定唯一 owner_actor，或缺少元数据卡四字段中任意一个的 Skill 执行 org 发布被拒，错误信息指出缺失/非法字段；通过后详情页显示四字段。
- **AC-8**（对 FR-12/FR-13）：validate-doc 失败时 org 发布被拒且 visibility 不变；protectedPaths 命中时发布成功但响应/详情含可读警告，警告不改变 permission-declaration。
- **AC-9**（对 FR-14）：代码中不存在针对 builtin 的可编辑性特判分支；尝试编辑内置 Skill 时因其在 `skill` 表中无对应行而自然失败。
- **AC-10**（对 FR-15/FR-16/FR-17/NFR-4）：含 `ghp_` 形制 token 与含 `C:\Users\<name>` 路径的 SKILL.md 发布均被拦截，且返回结果**指出命中的文件与行号**；返回内容不含密钥明文；`redact` 包内 `patterns` 定义只有一处（回归测试断言通过）。
- **AC-11**（对 FR-18）：作者提交一个命中项申诉后，非 Owner 决定被拒；Owner 对该 `appeal_id` 逐条确认放行后，`activity_log` 出现提交与放行记录（含放行人 / 时间 / Skill / 内容哈希 / 命中项标识）；重复提交/重复决定不产生重复效果；改变 Skill 内容后旧 appeal 不能绕过扫描。
- **AC-12**（对 FR-19/FR-20/FR-21/FR-22）：详情页对 org workspace Skill 渲染四字段使用说明卡、可识别的运行时要求标签与版本；builtin 可进入排行但不生成 skill 行；发布确认框文案含"发布 = 授权"语义。
- **AC-13**（对 FR-23）：带 `source: session-export` 的 SKILL.md 出现在 session-export 筛选结果中，不带该 marker 的不出现；列表和详情使用同一 frontmatter 解析结果且数据库 schema 无新增 source 列。
- **AC-14**（对 NFR-3）：迁移生成 `(task_id)` 与 `(skill_ref, used_at)` 两个索引，分别位于独立迁移文件且 up/down 均使用 `CONCURRENTLY`；固定 fixture 的 `EXPLAIN (FORMAT JSON)` 证明完成任务过滤和排行使用相应索引条件。
- **AC-15**（对 NFR-5）：迁移应用于含存量 Skill 的库后，既有 Skill 全部为 `private`，daemon 侧任务物化行为无变化。
- **AC-16**（对 NFR-6）：`../multica/CUSTOM.md` 已登记本 CR 全部改动；新增 Go / SQL 文件注释为英文并带 `AIFIRST:` 标记。

### 6. 成功指标

上线后按 P3 §1.2 SII 维度与 Market 自身数据观测（口径与观察期规则以 P3 §1.2 为准）：

1. **资产被扩散而非被囤积**——org 可见 Skill 中"被他人发起的任务使用过至少一次"的占比（只发不被用不算数）；
2. **复用者不再靠口口相传**——org 发布的 Skill 100% 具备完整元数据卡（由 FR-11 门禁保证，观测的是它是否造成大量发布失败重试，即门槛是否过高）；
3. **隐私边界有效且不扰民**——敏感扫描的拦截数与其中经申诉放行的比例；放行占比长期偏高说明模式误报率需要调整，而不是把门禁放松；
4. **内置方法论的真实使用分布**——使用量排行覆盖 tools 包 `skills/_index.yml` 当前 `status: active` 的全部 builtin Skill；基线数量在上线时由该索引记录，不把 P3 正文中的旧数字作为固定验收值。

### 7. 范围排除

- **不做"公开发布"档**——内部平台只有 `private` / `org` 两档（P3 §3.2）。
- **不做 Skill 的付费 / 积分机制**——内部资产，流通靠可见性与排行即可（P3 §6）。
- **不做资产复用率指标本身**——该子指标属 CR-D（P3 §1.2 注、§5.1）；本 CR 只交付其数据源 `skill_usage_event`。
- **不做会话导出为 Skill 草稿的生成链路**——该链路在 P2 §7；本 CR 只保证带 `source: session-export` 标记的草稿在 Market 列表可筛（FR-23）。
- **不做 builtin Skill 元数据卡四字段的补齐**——该工作在 tools 包内一次性完成（P3 §3.3），不属本 CR。
- **不改上游 `task_usage*` 系列表**——与本 CR 无关。
- **不新建任何事务 / 队列 / outbox 抽象**——仓内已有 crctl 文件 outbox + `cr_sync_event` 幂等账本、`webhook_delivery` 租约投递、`agent_task_queue` 的 `FOR UPDATE SKIP LOCKED` 三套机制（P3 §6）。

## P3 组织智能 CR-C：跨 CR 追溯与漂移检测（E4 追溯 + E5 漂移）（v0.23 · CR-2026-049）

## PRD — P3 组织智能 CR-C：跨 CR 追溯与漂移检测

### 1. 概述

#### 问题陈述

工程侧有两个问题没有读侧答案：

1. 「这个功能（FR）是谁、经哪个 CR、什么证据落地的」——P0 的 writeback-traceability 已把 `traceability.yml` 落进 git（baseline 权威），但查询只能翻文件；spec 详情页无法从一条 FR 一跳直达落地它的 merge commit、测试证据与评审记录。
2. 「基线和现实漂了没有」——本地执行模式下没人能从平台侧强制所有代码经 CR，绕过 CR 直接提交 trunk（bypass）目前完全不可见，且「从未漂移过」与「从未测过」在看板上无法区分。

#### 解决方案摘要

设计主线不变：**P3 不新增 Agent/LLM 采集管道，只做已有治理事实的聚合与呈现，并新增服务端确定性前缀扫描**。CR-C 交付两个严格依赖的交付物（E4→E5 一条线）：

- **E4 — 跨 CR 追溯查询**：writeback-traceability 完成时，crctl outbox 发出 `trace` 事件。`cr_sync_event.event_kind` 当前没有 CHECK 约束，因此新增 `trace` 本身不需要枚举迁移；事件 payload 使用明确的 canonical JSON envelope，包含 `spec_id` 与完整追溯文档。查询直打 `cr_sync_event`，**不建 `spec_trace` 投影表**（§7 R-10）。spec 详情页 + 全局搜索接入：FR 演进时间线、一跳直达 merge commit / 测试证据 / 评审记录、按人反查经手 spec。
- **E5 — 漂移检测（只做服务端确定性扫描）**：服务端纯 Go 前缀扫描（每小时，`sys_cron`，不走 Agent / 不走 LLM）按 workspace 的 `dir-graph.yaml#repositories` 声明扫各自 trunk 新提交，前缀不在白名单计 `bypass-commit`（warn）、`wip:` 前缀计 `wip-on-trunk`（info）；白名单单一事实源 = 本仓 `dir-graph.yaml#repositories[].commit_prefixes`，经生成器（照抄 `governance/gen/generate-transitions.mjs` 模式）吐 Go 副本。新增 `drift_finding` 表（workspace/repository 维度、明确的 spec 可空语义、幂等唯一索引），drift 数量与解决时延进看板治理板块，finding 流列表页挂治理板块下钻。

为保证现有多 workspace 数据契约，E4 同时补齐 `cr_sync_event` 的 workspace 维度与唯一键：`trace` event_kind 的增加仍然是零 CHECK/枚举迁移，但 ledger 的 tenant-safe key 是本 CR 必须交付的兼容修正。该修正不新增 `spec_trace` 表，也不改变既有事件的业务语义。

持久化面：**1 张新表**（`drift_finding`）+ `cr_sync_event` 的 workspace/key 修正 + 1 个 event_kind（零 CHECK 迁移）+ `dir-graph.yaml` 声明扩展（`commit_prefixes`）。其余全部复用现成机制。

#### 范围边界（注册阶段已拍板，本 PRD 原样采纳）

- 目标版本 0.23，开工前置无；E4→E5 内部一条线。
- CR-C 只含 E4/E5；LLM 对齐巡检与变更影响扫描（`review-alignment` / `change-impact-analysis` 定时化）**推迟**（§7 R-11），本 CR 不做。
- 知识晋升巡检已整节移出 P3 归《Wiki 子系统设计》（§2.3 / R-12），不在本 CR。
- 成熟度看板（E1/E2/E3）属 CR-A（已归档 CR-2026-047）；Skill Market（E6）属 CR-B（已归档 CR-2026-048）；基线校准、交付效能板块、资产复用率、超级个体占比、个人榜、待我审批端点属 CR-D。

#### 依赖与风险

- **既有能力依赖**：P1 crctl outbox 通道与 `cr_sync_event` 表；P0 writeback-traceability；`sys_cron_executions` 调度器；CR-A 已交付的看板治理板块框架；`governance/gen/generate-transitions.mjs` 生成器先例；workspace 的仓库访问配置。
- **CR 间依赖**：开工前置无；E4→E5 一条线。E4 的 trace 查询依赖 P0/P1 的累积追溯与事件投影；E5 的治理展示依赖 CR-A 的治理板块框架，但扫描、finding 数据和下钻列表属于本 CR。
- **主要风险**：
  - 前缀合规 ≠ 通路合规（前缀可手写伪造）；通路层对账明确延后 P3+，本 CR 的 bypass 信号只是「可见性」而非「强制」。
  - 「从未漂移过」与「从未测过」必须可区分——扫描任务失败/未运行必须在治理板块可见，不得与「无 finding」混淆。
  - trunk 历史重写、仓库暂时不可访问或扫描进程中断不得造成游标跳过；失败时保留上一个成功游标并重试。
  - 同一 CR-ID 可能在不同 workspace 重复出现；E4/E5 的事件、finding、查询和唯一键不得跨 workspace 串数据。

### 2. 用户故事

| ID | 角色 | 行为 | 价值 |
|---|---|---|---|
| US-1 | 工程师 | 在 spec 详情页从一条 FR 看到它由哪些 CR 演进而来（时间线），并一跳跳到那次上线的 merge commit 与测试证据 | 回答「这个功能是谁、经哪个 CR、什么证据落地的」 |
| US-2 | 工程师 | 全局搜索按人反查其经手过的 spec，按 spec 反查演进历史 | 追溯审计与知识复用 |
| US-3 | Tech Lead / Owner | 在治理板块看到各仓 trunk 的 bypass 提交数量与 wip-on-trunk 记录，并能区分扫描正常与扫描异常 | 探测影子工程，让绕过可见且不把无数据误读为无漂移 |
| US-4 | QA | 在治理板块下钻到 drift_finding 流列表页，查看并流转 finding 状态（open→acknowledged/resolved/wontfix） | 漂移问题闭环管理 |
| US-5 | 平台管理员 | 在本仓 dir-graph.yaml 维护各仓提交前缀白名单，生成器校验 Go 副本无漂移 | 约定变更走声明而非发版 |

### 3. 功能需求

#### E4 — 跨 CR 追溯查询（trace event_kind + spec 详情页）

- **FR-1** writeback-traceability 成功完成 commit/push 后，crctl outbox 发出版本化的 `event_kind='trace'` 事件。payload 的 canonical JSON 结构固定为：
  ```json
  {
    "spec_id": "ai-first-platform",
    "traceability": {
      "spec-id": "ai-first-platform",
      "cr-ref": "CR-YYYY-NNN",
      "cr-history": [],
      "target-version": "0.23",
      "baseline-since": "0.10",
      "generated-at": "2026-08-20T00:00:00+08:00",
      "milestones": []
    }
  }
  ```
  `traceability` 是 `specs/{spec_id}/traceability.yml` 经 LF 规范化后解析得到的完整语义对象，保留其既有键名（包括 `spec-id`）；顶层 `spec_id` 是供查询/索引使用的稳定别名。payload 不要求保留 YAML 注释或字节顺序。事件的 `cr_id`、`commit_sha`、`occurred_at` 继续使用现有 outbox v1 顶层字段。
- **FR-2** daemon 与 server 的事件 schema/allowlist 必须接受 `trace`；trace 是 ledger-only 事件，不触发 CR 状态转换，不写入 `cr` 状态投影，但成功入账后必须写 `processed_at`，便于重试与健康判断。未知 `trace` 不得因当前 `knownEventKinds` 缺项而被拒收。
- **FR-3** trace 交付采用可恢复的 outbox 语义：writeback journal 记录 `trace-outbox` 的 pending/emitted 事实，并使用由 CR-ID + writeback commit SHA 派生的确定性 dedup 文件名。outbox 暂时不可写时，writeback 主流程仍可完成但必须返回 warning、保留 pending 事实；重跑同一 `writeback-apply --stage traceability` 必须补发，daemon/server 暂时不可用时文件保留并由既有 collector 重试。相同事件最多在 ledger 中落一行。
- **FR-4** 为解决现有多 workspace ledger 的同名 CR 冲突，`cr_sync_event` 增加 `workspace_id`（由 server daemon auth 上下文注入，不信任事件正文），历史行通过 `cr_sync_event.cr_id = cr.cr_id` 回填；回填遇到无法唯一归属的历史行必须硬失败，不得猜测。将唯一键从 `(cr_id, commit_sha, event_kind)` 扩展为 `(workspace_id, cr_id, commit_sha, event_kind)`，并移除旧唯一键；既有 outbox、commit-scan ingestor、review/approval 查询一并按 workspace 写入/读取。`trace` event_kind 本身仍因无 CHECK 约束而不新增枚举迁移。
- **FR-5** 查询直打 `cr_sync_event`，必要时加表达式索引 `(payload->>'spec_id') WHERE event_kind='trace'`；所有查询必须以当前 workspace 过滤，不得依赖 `cr_id` 单独隔离；**不建 `spec_trace` 投影表**（R-10：事件行自带时间戳与完整 payload，二次拆列只多一份会漂的副本）。
- **FR-6** spec 详情页展示该 spec 的 FR 演进时间线：读取 `payload.traceability.milestones[].frs[]`，按 trace 事件时序展示每条 FR 由哪些 CR 演进而来，并标明当前 workspace。
- **FR-7** 一跳直达：从 FR 时间线可跳转到对应 merge commit（commit 页/仓库链接）、测试证据（test-report）与评审记录（approval / review 记录）；链接目标必须使用 traceability evidence 中的路径与 commit SHA，不猜测 trunk 最新提交。
- **FR-8** 全局搜索接入：在当前 workspace 内按 `cr.owners` 反查某人经手过的 spec，按 spec 反查演进历史；搜索结果必须与 spec 详情页使用同一 trace 数据源，禁止跨 workspace 返回同名 CR。

#### E5 — 漂移检测（前缀扫描 + drift_finding）

- **FR-9** 前缀扫描是服务端纯 Go（**不走 Agent、不走 LLM**），注册稳定 job name=`commit_prefix_scan`，每个 workspace 使用一个 scheduler scope（scope_id=workspace_id），每小时按该 workspace `dir-graph.yaml#repositories` 声明的全部仓扫各自 trunk 新提交。服务端必须通过现有仓库访问配置取得每个声明仓的 trunk HEAD 与 commit subject；任一声明仓不可访问时本次 plan 失败，不把缺仓误报为「无 finding」。
- **FR-10** 判定口径：`wip:` 是优先级更高的特许分类，带该前缀的 trunk 提交一律计 `wip-on-trunk`（severity=`info`），不计入 bypass；其余提交前缀不在该仓 `commit_prefixes` 白名单且不属该仓特许格式 → 计 `bypass-commit`（severity=`warn`）。每条 E5 finding 的 `evidence` 必须包含非空 `repository_id`、`trunk`、`commit_sha`、`commit_subject` 与扫描时间。
- **FR-11** 白名单单一事实源 = 本仓 `dir-graph.yaml#repositories[].commit_prefixes`（本 CR 新增字段）；本 CR 首次为 knowledge-base、multica、tools 三个声明仓提交非空初始白名单，并覆盖各仓当前既有合法提交格式。前缀约定不硬编码在 Go。照抄 `governance/gen/generate-transitions.mjs` 生成器模式：读声明 → 吐只读 Go 副本（文件头记源 commit SHA）→ 副本提交入库 → `--check` 模式在 CI/pre-commit 重生成并 diff，漂移则非零退出。
- **FR-12** 新增 `drift_finding` 表，租户与身份契约固定为：`workspace_id UUID NOT NULL`、`repository_id TEXT NOT NULL`、`spec_id TEXT NULL`、`cr_id TEXT NULL`、`kind` CHECK（`alignment-drift`/`impact-stale`/`bypass-commit`/`wip-on-trunk`）、`severity` CHECK（`info`/`warn`/`block`）、`summary TEXT NOT NULL`、`evidence JSONB NOT NULL DEFAULT '{}'`、`status` CHECK（`open`/`acknowledged`/`resolved`/`wontfix`，默认 `open`）、`found_at`、`resolved_at`。本 CR 的 bypass/wip finding 为仓库级记录，`spec_id=NULL`、`cr_id=NULL`；spec 详情不是伪造的 repo finding。未来 alignment/impact finding 才可填写真实 `spec_id`/`cr_id`。
- **FR-13** `drift_finding` 的幂等键为 `CREATE UNIQUE INDEX CONCURRENTLY drift_finding_dedup_idx ON drift_finding (workspace_id, repository_id, kind, COALESCE(spec_id, ''), (evidence->>'commit_sha'))`；E5 事件要求 `evidence.commit_sha` 非空。采用 at-least-once 交付 + 唯一索引去重，不在应用层「先查再插」（R-13）。同一 workspace、仓库、分类和 commit 连续扫描 24 小时仍只一行；不同 workspace 或仓库的同名 commit 不冲突。
- **FR-14** 增量扫描游标持久化在现有 `sys_cron_executions.result.scan_cursors`，按 repository_id 保存上一次**完整成功扫描**的 trunk HEAD SHA。首次成功 plan 只记录当前各仓 HEAD 为 baseline，不对 baseline 之前的存量历史生成 finding；随后每次只扫描 cursor（不含）到本次开始时 HEAD（含）的提交。全部声明仓扫描成功后才原子写入新 cursors；任一仓访问失败、游标不在当前 trunk 历史或进程中断时，不推进受影响 plan 的 cursors，重试必须从上一个成功游标继续，允许重复读取但不得漏扫或产生重复 finding。
- **FR-15** 治理板块使用同一个 `commit_prefix_scan` 的 `sys_cron_executions` 记录作为健康事实源：最新成功 plan 的 `result.scan_cursors` 必须覆盖当前全部声明仓且距当前不超过两个小时桶；无成功记录显示「未初始化」，超过窗口或最新 plan 为 FAILED 显示「扫描异常」。只有健康状态下的零 finding 才显示为「无漂移」，禁止把未运行/失败折叠成零值。健康状态、bypass 数量、wip-on-trunk 数量与解决时延均按当前 workspace 过滤。
- **FR-16** `drift_finding` 流列表页挂在治理板块下作为下钻目的地（§4 质量中心降级形态），支持 status 流转（`open`→`acknowledged`→`resolved`，记录 `resolved_at`；或 `wontfix`），并与治理板块计数使用同一 workspace/repository/finding 查询口径。

### 4. 非功能需求

- **NFR-1** 新增迁移从下一个可用编号 **385** 起（2026-08-20 核实 multica 当前已有 375–379 CR-A maturity/report、380–384 CR-B skill/appeal 迁移，当前最大编号为 384）。`drift_finding` 的 `id` 不得使用 inline `PRIMARY KEY` 生成索引：建表文件只定义 `id UUID NOT NULL DEFAULT gen_random_uuid()`，随后在独立迁移文件中用 `CREATE UNIQUE INDEX CONCURRENTLY` 建 id 索引，再在另一个独立文件用 `PRIMARY KEY USING INDEX`；`drift_finding_dedup_idx` 另占一个只含该索引语句的迁移文件。`cr_sync_event` workspace/key 修正同样不得 inline 新索引；**禁新增 FOREIGN KEY**；每个索引必须 `CREATE INDEX CONCURRENTLY` 且一个迁移文件一条。
- **NFR-2** 不新建任何事务/队列/outbox 抽象（仓内已有 crctl 文件 outbox + `cr_sync_event` 幂等账本、`webhook_delivery` 租约投递、`agent_task_queue` 的 `FOR UPDATE SKIP LOCKED`）。trace 重试复用 writeback journal、现有 outbox collector 和 sys_cron lease。
- **NFR-3** 前缀扫描为确定性纯计算（一次 `git log` 取增量），无 LLM 依赖、无 daemon 依赖，给定 repo HEAD 与白名单时结果可重现。
- **NFR-4** 扫描为旁路检测：只读被扫仓，不得阻塞或修改任何提交；仓库访问失败必须是 FAILED/异常信号，不得静默成功。
- **NFR-5** 所有 trace/finding API、SQL 查询、唯一键和状态变更均 workspace-scoped；不得以 `cr_id`、`spec_id` 或 commit SHA 单独作为跨 workspace 隔离条件。
- **NFR-6** 构建 multica 不需要 checkout 本仓：commit_prefixes 声明经生成器产出 multica 只读 Go 副本；运行时仓库访问使用现有 workspace 仓库配置，不新增跨仓运行时文件依赖。
- **NFR-7** trace outbox 写入失败不阻塞已经完成的 writeback 主流程，但必须保留可恢复 pending 事实；在 outbox/collector 恢复并重跑同一业务命令或自动重试后，不得永久丢失 trace 事件。

### 5. 验收标准

| ID | 覆盖 FR | 可执行验收 |
|---|---|---|
| AC-1 | FR-1、FR-2 | 用一份已生成的 `specs/{spec}/traceability.yml` 触发 trace writeback：事件 `event_kind='trace'` 被 daemon/server 接受，`payload.spec_id` 等于文件 `spec-id`，`payload.traceability` 与 LF 规范化后解析的完整 YAML 语义相等；事件入账后 `processed_at` 非空，且不改变 `cr.status`。 |
| AC-2 | FR-3、NFR-7 | 在 outbox 暂时不可写时，writeback 仍能完成并返回 warning，journal 保留 pending；恢复写入能力后重跑同一 `writeback-apply --stage traceability`，生成确定性 trace outbox 文件并最终入账；重复重跑/重复投递最终只产生一行。 |
| AC-3 | FR-4、NFR-5 | 两个 workspace 使用同名 CR-ID 时，各自产生不同 `workspace_id` 的 trace ledger 行；迁移先为既有行按 `cr` 投影成功回填 workspace_id，再删除旧唯一键并建立 workspace-scoped 唯一键；若存在无法唯一回填的历史行则迁移非零失败；trace 查询只返回当前 workspace，不能读到另一 workspace 的 payload。 |
| AC-4 | FR-5 | 迁移清单中不存在 `spec_trace` 表；`event_kind='trace'` 查询直打 `cr_sync_event`，使用 `payload->>'spec_id'` 过滤；表达式索引如建立则是独立 `CONCURRENTLY` 迁移。 |
| AC-5 | FR-6 | 归档两个以上同 spec CR 后，spec 详情页按 trace 事件时序展示每个 CR 对该 spec 各 FR 的演进，且只显示当前 workspace 的数据。 |
| AC-6 | FR-7 | 从 FR 时间线一跳可到达对应 merge commit、测试证据与评审记录；链接使用 evidence 中的路径/SHA，缺失证据时明确显示缺失，不回退到 trunk 最新提交。 |
| AC-7 | FR-8、NFR-5 | 全局搜索按人反查只返回当前 workspace 内其 owners 经手过的 spec；按 spec 反查返回同一 workspace 的演进历史；构造另一 workspace 同名 CR 后不会混入结果。 |
| AC-8 | FR-9、FR-14 | 注册 `commit_prefix_scan` 后，单 workspace 每小时产生一个 scope=workspace_id 的 plan；缺任一声明仓访问权限时 plan=FAILED，且不产生「无 finding」成功态。首次成功 plan 只建立三仓 HEAD baseline，不为 baseline 前提交生成 finding。 |
| AC-9 | FR-10 | 非白名单前缀提交产生 `bypass-commit`/`warn`；`wip:` 提交产生 `wip-on-trunk`/`info` 且不进入 bypass 计数；每条 evidence 含非空 repository_id、trunk、commit_sha、commit_subject、scanned_at。 |
| AC-10 | FR-11 | `dir-graph.yaml` 为三个声明仓均有非空 `commit_prefixes` 初始声明，覆盖当前已确认的合法提交格式；改一条声明后生成器副本更新，未更新副本时 `--check` 非零；副本头含源 commit SHA。 |
| AC-11 | FR-12、FR-13、NFR-1 | 执行迁移后 `drift_finding` 含 workspace_id/repository_id、可空 spec_id、四类 kind、三类 severity、四类 status 和默认值；bypass/wip 行的 spec_id/cr_id 均为 NULL；无 FK；id 主键及 dedup 索引均按独立 CONCURRENTLY/USING INDEX 迁移落地，dedup key 含 workspace、repository、kind、spec 空值归一化和 evidence.commit_sha。 |
| AC-12 | FR-14 | 给定 cursor=A 与 HEAD=B，扫描只处理 A 之后到 B（含）的提交；首次运行只写 baseline；模拟中途失败后 cursor 仍为 A，重试能处理 A→B 且不漏提交；游标不是当前 trunk ancestor 时 plan=FAILED，不猜测重置。 |
| AC-13 | FR-13 | 同一 workspace/仓库/kind/commit 连扫 24 小时仍只有一行；不同 workspace 或不同仓库即使 commit SHA 相同也分别保留；应用层不做先查再插。 |
| AC-14 | FR-15 | 无成功 plan 显示「未初始化」；最新成功 plan 超过两个小时桶或最新 plan=FAILED 显示「扫描异常」；健康且无 finding 才显示「无漂移」；治理板块显示 bypass 数量、wip-on-trunk 数量与解决时延。 |
| AC-15 | FR-16 | 治理板块可下钻到 drift_finding 列表页；finding status 可流转 open→acknowledged→resolved（记录 resolved_at）或 wontfix，流转后列表、健康状态与板块计数仍按同一 workspace/repository 口径一致。 |

### 6. 成功指标

- 在 outbox 可写、collector/server 恢复且执行同一重试语义后，归档 CR 的 trace 事件最终落库率 **100%**，每个事件只有一条 workspace-scoped ledger 记录。
- 三个声明仓的前缀扫描覆盖率 **100%**：每个 workspace 每小时有成功/失败的明确执行记录，不把缺仓或失败显示成零 finding。
- 首次 baseline 前的历史提交误报数 = **0**；已声明白名单内前缀的误报数 = **0**。
- 同一 workspace/仓库/kind/commit 24 小时重复扫描产生的重复 finding 数 = **0**。
- 跨 workspace 的 trace/finding 数据泄露数 = **0**。

### 7. 范围排除

本 CR 明确**不做**（含去向）：

- LLM 对齐巡检（`review-alignment` 定时化）与变更影响扫描（`change-impact-analysis` 定时化）——七跳链路 + daemon 在线依赖，静默无结果与无漂移不可区分（R-11），待 daemon 在线率有真实数据后再立项；`alignment-drift` / `impact-stale` 只保留表枚举，不由本 CR 产生。
- bypass 通路层对账（controlled-shell 审计行 ↔ trunk 提交交叉核对）——需把本地审计投影到服务端，属新采集，延后 P3+；P3 只做前缀层探测（§2.2 / §6）。
- `spec_trace` 投影表——`cr_sync_event.payload` 已是完整事实，二次拆列只多一份会漂的副本（R-10）。
- 知识晋升巡检（E9 已整节移出 P3，归《Wiki 子系统设计》，R-12）。
- 成熟度看板 E1/E2/E3（CR-A 已归档）、Skill Market E6（CR-B 已归档）、CR-D 全部内容（基线校准写入 config、交付效能板块、资产复用率、超级个体占比、个人榜、待我审批端点）。
- 通用 Pipeline Runner（读侧投影已由 `governance/gate_projection.go` 交付，属 M1/A2）。
- 跨组织对标、个人绩效导出/API、指标实时化、Skill 付费/积分机制（平台级不做项，§6）。

## Pipeline 流程优化 — 职责边界与契约漂移修复（先正确性后职责收敛，P0/P1/P2 单 CR）（v0.24 · CR-2026-050）

## 1. 概述

本 CR 落地 `docs/analysis/pipeline流程优化.md` 对 `../tools/pipeline-templates/` 下 8 条 active Pipeline（architecture-design、requirement-authoring、code-implementation、product-planning、market-to-plan、competitive-radar、feature-writeback、resume-cr）的职责边界与契约漂移审计结论。

问题本质不是缺少基础设施，而是基础设施已经存在（`crctl` 状态/门禁/CAS/审批/事务、`review-record`、`workspace inspect`、`crctl test/task/checkpoint/merge/writeback/archive`、版本化 generator），旧的实现细节仍被复制在 Pipeline prompt 中形成第二份易漂移事实源，并已造成几处**会运行失败或绕过安全边界**的真实契约错误。

审计把问题分三档：

- **P0 / Blocker**：三条 CR Pipeline 的人工审批提示要求直接修改受保护评审账本（`review-annotations/*.yml` 在 `controlled-shell/rules.json#protectedPaths.deny` 中）；product-planning 竞品节点输入缺失；market-to-plan 的 `planning-draft` 缺必填 `context/intent`；competitive-radar 草稿不落盘却要求已落盘 `reportPath` 且 node-5 混调两个 Skill。
- **P1**：approve/review/test/register/freshness 等节点复制了已由 Skill/crctl 承担的关键算法；审批节点遗漏 CR-ID、grant 模式，下一步写死 pipeline 名。
- **P2**：章节清单、文件路径、索引格式、展示字段等非阻断性重复。

实施策略为**同一个 CR 内两阶段**（source §18），不拆分多个 CR。P0/P1/P2 是问题优先级，不等同于实施阶段边界：

1. **阶段一（正确性门）**：完成 FR-01～FR-04 的 P0 修复，并完成 FR-05 四个 approve 节点遗漏 CR-ID、grant 模式与 `crctl next` 的明显契约漂移修复；FR-01～FR-05 对应的契约断言通过后，方可进入阶段二。
2. **阶段二（职责收敛）**：按 `architecture-design → requirement-authoring → code-implementation → resume-cr → feature-writeback → 规划类 Pipeline` 顺序完成 FR-06～FR-13；最终一次性完成本 CR 的评审、验证和回写。

目标职责边界（`§2`）：

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出、失败语义 | 手写原子账本逻辑、重复实现 crctl |
| crctl | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

实现选择继续遵循 ponytail 优先级：复用现有能力 > 标准库 > 原生 Git/文件 API > 已有依赖 > 一行代码 > 最小新增代码。

## 2. 已解决基础设施与保留契约

### 2.1 已解决基础设施（只复用，不重做）

| 能力 | 已有权威实现 | Pipeline 的最小职责 |
|---|---|---|
| 工作区事实解析 | `crctl workspace inspect` | 入口校验 healthy，传递 `operationalWorkspace` 和 `resources` |
| 工作区新鲜度 | `workspace-freshness` Skill + `crctl workspace freshness/sync` | 声明 gate 节点，消费 `continue/synced-continue/replay/manual` |
| CR 注册与 worktree | `requirement-register` + `crctl register` | 传注册业务参数，消费结构化结果 |
| 状态和门禁 | `crctl status/next/gate/advance` | 不复制状态转换算法，不手写 status |
| 评审记录与轮次 | `crctl review-record` / `attempt` | Pipeline 声明机器可读 reviewLoop，Skill 形成评审判断 |
| 人工审批 | `approve-*` Skill + `crctl approve` | 编排 `human_approval → approve-*`，不复制 grant、CAS、回退算法 |
| TASK 索引和任务状态 | `crctl task init/append/done` | 不手写 `tasks/_index.yml` |
| 测试证据 | `write-test-report` + `crctl test` | 编排实现 → 测试报告 → 代码评审 |
| 受控 Git | `controlled-shell` / `crctl git` | 不内联裸 Git 命令序列 |
| checkpoint | `push-progress` + `crctl checkpoint` | 传 `cr_id` 和阶段 message，检查结构化 phase |
| 跨仓合并 | `merge-feature-branch` + `crctl merge` | 传 `cr_id`，消费 merge transaction 结果 |
| 回写转换 | `writeback-*` + `writeback-apply` + 版本化 generator | 传 `cr_id/spec_id/target_version` 等业务输入 |
| 归档和清理 | `cr-archive` + `crctl archive` | 传业务参数，消费 `complete/cleanup-pending` |
| 工程文档骨架和校验 | `engineering-docs`、`validate-doc` | Skill 调用并消费校验结果，不在 Pipeline 复制 schema |

### 2.2 Pipeline 中应保留什么（§17）

每个 `kind=skill` 节点的 prompt 最多保留五项：

1. 调用哪个 Skill；
2. 传入哪些参数；
3. 依赖哪个前序节点的结构化输出；
4. 消费哪些结构化结果；
5. 失败如何 `abort/skip` 或进入 reviewLoop。

Pipeline JSON 继续作为以下机器事实源，**不得搬回 Skill 文本，也不得让 Skill 另写一份 reviewLoop 规则**：

- node 顺序；
- `ref`；
- 输入传递；
- `reviewLoop`；
- `replayNodes`；
- `passCondition`；
- `onFail`；
- timeout；
- human approval 节点。

## 3. 用户故事

- **US-01 Pipeline 维护者**：希望节点 prompt 只表达「调用哪个 Skill、传什么、按什么 reviewLoop 重放、失败去哪」，Skill/crctl 内部变化不需要同步修改多份算法文本。
- **US-02 CR 执行者**：希望人工审批只提交 approve/reject 决定及理由，不再被引导去直接编辑受保护评审账本，避免绕过 CAS 与审计边界。
- **US-03 规划流程使用者**：希望 product-planning / market-to-plan / competitive-radar 按 Skill 声明的必填输入闭环，不因缺 `topic`、`context/intent`、`updates-block/product-snapshot` 而运行失败或无法落盘。
- **US-04 竞品雷达使用者**：希望草稿（confirmed=false）与正式报告（confirmed=true）的顺序闭环可执行，不出现「草稿未落盘却要求 reportPath」的矛盾。
- **US-05 Tools 维护者**：希望审批/评审/测试/freshness 节点把算法交回 Skill 与 `crctl`，下一步统一「以 `crctl next {cr_id}` 为准」，不写死下一条 pipeline 名。
- **US-06 评审者**：希望技术设计新增的术语硬化、REST 契约基线与关键决策记录以收窄后范围进入 Skill 与评审维度，不新增评审节点或独立 ADR 文件。

## 4. 功能需求

### FR-01（P0）三条 CR Pipeline 人工审批不再直接修改受保护评审账本

涉及 `requirement-authoring`（`review-annotations/requirement.yml`）、`architecture-design`（`review-annotations/sdd.yml`）、`code-implementation`（`review-annotations/code.yml`）的 human approval 节点。

1. 删除「在 review-annotations/*.yml 补充 reject_reason」等直接修改受保护账本的指引；`review-annotations/*.yml` 在 `controlled-shell/rules.json#protectedPaths.deny` 中，由 `crctl review-record` / `crctl approve` 独占写入。
2. 改为：人工只提交 `approve/reject` 决定及理由；理由通过 `approve-*` Skill 的 reject 流程记录并回退（需求→`drafting`/重写 PRD、架构→`tech-designing`、代码→`developing`）。
3. 审批证据、CAS、审计和状态回退均由 `crctl approve` 完成；人工决定只进入 `approve-*` 的受控流程。

### FR-02（P0）product-planning 输入契约修复

文件 `product-planning.pipeline.json`。

1. `analyze-user-feedback`、`conduct-market-research`、`analyze-current-product` 至少传 `topic: {{inputs.topic}}`（Skill 必填参数），并保留各自 skip 标志。
2. `write-competitive-report` 补齐 Skill 必填输入：`updates-block`、`product-snapshot`、`confirmed`；明确 Pipeline 如何取得 `fetch-competitor-updates` 输出与 `gather-product-context` 快照，或让现有 Skill 自行调用已存在的上下文能力；不得让一个节点同时「假装拥有」两个 Skill 的输入和业务逻辑。
3. `write-planning-report` 明确传 `prev_outputs`、`review_feedback`、`self_repair_attempt`，使 reviewLoop 回修可可靠消费 blocker；报告章节、文件名与 `_index.yml` 由 Skill 负责。
4. `review-planning-report` 只传报告路径、reviewer、topic、target version、feedback 和 attempt，消费 `approved/blockers/repair-target/current-attempt`；评审维度、annotation 路径、`_index.yml` 状态更新和轮次持久化由 Skill 负责（规划类无 CR 上下文，本地评审记录仍由 Skill 持久化，不引入 `crctl review-loop`）。
5. `write-roadmap` 传 `topic`、`target_version`、`planning_report_path`；删除「同步更新规划报告 `_index.yml` 为 approved」的跨文档写入（该写入不在 `write-roadmap` 契约中，优先删除）。
6. product-planning 的 human approval 只收集结构化 `approve/reject + reason`，删除「在报告末尾补 reject_reason」；驳回中止当前正向链，需修订时按既有 reviewLoop 或正常 Pipeline 重跑，不迁移到 CR `approve-*`/`crctl approve` 机制。

### FR-03（P0）market-to-plan 必填参数与跨文档写入修复

文件 `market-to-plan.pipeline.json`。

1. `planning-draft` 补齐 Skill 必填输入 `context` 与 `intent`；若当前 Pipeline 无法提供产品上下文，先明确复用已有 `gather-product-context`，不得用未声明的「简报」替代 `context`。
2. `extract-market-insight` 的简报调用为 Skill 增加最小显式输入（如 `mode=brief`、`raw_insight_path`），Pipeline 只传这两个业务参数；brief 正文、路径和 index 状态由 Skill 负责，不得在 Pipeline 用 `source` 伪造 Skill 参数。
3. `write-planning-entry` 删除对 `docs/market-insights/_index.yml` 生命周期状态 `published` 的跨文档写入（不在该 Skill 参数与写入契约中，保守默认删除，待真实需求证明再单独设计）。

### FR-04（P0）competitive-radar 草稿/落盘顺序闭环

文件 `competitive-radar.pipeline.json`。

1. node-1 做显式参数映射或统一 Skill 参数名：`competitor_slug → competitor-id/competitor-ids[]`、`since_days → lookback-days`；`slug` 与竞品 ID 不等价时先按现有竞品索引解析，不得让 prompt 自行猜测。
2. node-2 `write-competitive-report` 补齐必填 `updates-block`、`product-snapshot`、`confirmed`；报告固定章节、路径、竞品主文件 updates、reports index 与两阶段落盘规则由 Skill 负责。
3. node-3 `report-to-planning-suggestion` 支持 `reportPath` 与 `reportDraft` 二选一；两者同时存在时优先 `reportPath`。`reportDraft` 最少包含草稿正文、`competitorId`、`reportDate`、来源节点/来源标识；草稿模式只消费输入生成规划建议，不落盘竞品报告，且不得把 node-2 草稿伪装成 `reportPath`。
4. node-5 在人工确认通过后，继续传递 node-2 的 `updates-block`、`product-snapshot` 与 `confirmed=true` 所需结构化上下文，并顺序调用两个已有 Skill：先 `write-competitive-report(confirmed=true)` 落盘正式报告，再 `write-planning-entry(source=node-3.md)` 落盘规划条目；若单个 node 不允许顺序调用多个 Skill，在现有运行时编排能力中显式支持，不新增业务 Skill或事务层，也不在 `write-planning-entry` prompt 中复制报告落盘算法。

### FR-05（阶段一 / P1）审批节点收敛

涉及 `approve-requirement`、`approve-tech-design`、`approve-dev-start`、`approve-code` 四个节点。

1. 删除 `crctl approve --stage ...` 命令细节、TTY 审批路径、`approval.yml`、grant/CAS/状态级联、reject 结果码等由 Skill 与 `crctl approve` 承担的实现。
2. 只保留：读取 execution_context，调用对应 `approve-*`，传入 `cr_id`（完整形态，不得遗漏）与 `approver`（取自 `execution_context.owners.*.id`），消费审批记录、当前状态和结构化结果；失败按 Skill 语义 abort。
3. 下一步统一以 `crctl next {cr_id}` 为准，不得写死下一条 Pipeline/Skill。

### FR-06（P1）评审与测试节点收敛

涉及 `review-requirement`、`review-tech-design`、`review-dev-plan`、`write-test-report`、`review-code` 五个节点。

1. 删除评审业务维度正文、临时 review payload、`crctl review-record` 调用方式、canonical annotation 写入、review-loop/traceability 写入、blocker 回修算法。
2. 保留机器可读 `reviewLoop`、`replayNodes`、`passCondition`、`maxAttempts`，以及对 `verdict/blockers/repair-target/current-attempt` 的消费和路由。
3. `review-tech-design` 把术语硬化、REST 契约基线、关键决策记录要求补回 Skill 评审维度（见 FR-08.4），不新增评审节点。
4. `write-test-report` 删除 `cr-test-plan/v1` schema、executable/args/timeout 白名单、`crctl test` 命令、test-report 机器区与 marker、traceability/review-loop 原子更新、status=block 证据语义；Pipeline 只传 `cr_id`、`source_node`、`tester`、`review_feedback`、`self_repair_attempt`，消费 `status`、`blockers`、报告路径。
5. `review-code` 删除 reviewer runner 选择、diff/log/merge-base 取证命令、test-report/traceability/test-evidence 证据规则、代码评审维度、blocker/suggestions 语义、回修重建算法；Pipeline 只传 CR-ID、workspace、resources、review feedback、attempt，消费 verdict/blockers/test-report.status/repair-target，并保留 `reviewLoop.replayNodes: implement → test-report → checkpoint → freshness → review-code`。

### FR-07（P1）输入、工作区与开发产物节点收敛

1. `write-tech-design` 以 `crctl workspace inspect` 返回的 `operationalWorkspace` 与 `resources[].worktreePath` 为唯一路径事实，删除自拼接 `.rayai-worktrees/{repo.id}/requirement/{cr_id}`、SDD 章节清单、术语/REST/决策业务规则、`crctl advance` 命令、Git 命令与 commit 算法、blocker 逐条修复算法；Skill 输入显式接受 `operational_workspace`、`resources`。
2. knowledge-base 的 `sdd.md` 与代码仓 `ARCHITECTURE.md` 属于同一轮技术设计，但不得声称处于同一 Git commit；只为本 CR 实际涉及且缺失该文档的代码仓起草，各仓在所属 `resources[].worktreePath` 分别提交，最终纳入同一批 checkpoint。
3. architecture-design node-5 `push-progress` 只传 `cr_id` 与阶段 message、消费结构化 `phase`；保留「架构阶段终点」「`phase=complete` 才成功」「checkpoint 失败只重跑同一 checkpoint、不重新审批」语义，删除 checkpoint 命令、workspace resolver、事务恢复和 Git 算法。
4. `requirement-register` 保留输入映射与结构化结果消费，删除完整 `crctl register` 参数序列、registration key 派生示例、绝对路径 execution context 示例、repo worktree 结构；路径值由 Skill/crctl 返回，Pipeline 不自行构造。
5. `write-requirement-prd` 删除 PRD 章节清单、主 workspace 禁写规则、具体落盘路径、blocker 逐条修复；Pipeline 只传 `cr_id`、`source`、review feedback、attempt 和运行时 context。
6. `implement-code` 删除 runtime fallback、PRD/SDD/TASK 读取清单、TASK 依赖/回修根因/验证算法；保留 execution context 与 `resources[].worktreePath` 传递、调用 `implement-code`、消费变更范围/runtime/session/验证结果、reviewLoop 回修输入。
7. `workspace-freshness`（实施前与评审前两个节点）删除 syncable 条件、freshness/sync 调用、continue/synced-continue/replay/manual 路由、逐仓失败处理；Pipeline 只传 `cr_id` 和 gate 名称，消费 route（`continue/synced-continue` 继续、`replay` 按现有 reviewLoop 重放、`manual` abort）。
8. `write-dev-plan` 删除 plan 章节、status 校验和输入文件算法；Pipeline 只传 `cr_id`、`target_version`、`review_feedback`、`self_repair_attempt`、`operational_workspace/resources`，消费结构化 plan 结果。
9. `write-dev-tasks` 删除 TASK 文件格式、接口签名规则、`crctl task init` 命令、estimate 交叉校验和索引失败算法；Pipeline 只传业务输入并消费 TASK 列表、估算与结构化结果。

### FR-08（P1）write-tech-design 三项新增能力收窄（§6）

1. **术语硬化**：仅处理会进入数据模型、状态机或接口契约，且存在一词多义/多词同义/代码别名、边界会影响 FR/AC/角色权限/验收语义的术语；每个被识别的风险术语至少用一个代表性边界场景验证；已有 `CONTEXT.md`/术语表先只读沿用，不新增跨 CR 长期术语资产；纯命名差异以 PRD 业务语义为权威记录 `PRD canonical term → 代码现有别名`，语义冲突不得由技术设计自行裁决（首次状态推进前停止、要求需求负责人澄清）；术语预检位于首次 `crctl advance` 之前，避免留下无 SDD、无评审记录的 `tech-designing` 状态。
2. **HTTP/REST 契约基线**：当 PRD、tech_context 或拟定技术方案表明本 CR 将新增或修改 HTTP API 时条件触发；优先级为目标仓 `ARCHITECTURE.md`/既有 OpenAPI/API 契约 → 现有客户端兼容性 → Skill 默认基线；默认基线可要求资源化 URL、方法语义、状态码语义、统一错误结构、分页策略、偏离说明、禁 HTTP 200 包装所有错误，但不强制复数资源名/kebab-case/固定 `error.code/message/details`/全列表分页/固定 400-422/全部 `201 + Location`；SDD 写接口概要/输入/输出/错误/鉴权与条件性幂等/分页约束，复杂或高风险接口附最小 OpenAPI 片段，不要求完整契约文件。
3. **关键决策记录**：三判据（难以逆转 / 无上下文会疑惑 / 存在真实权衡与替代方案）同时满足才记录；结构为 Decision/Context/Alternatives/Consequences；不伪造替代方案、不新增独立 ADR 文件或审批节点；改仓库级模块边界/依赖方向/硬不变量时按 `ARCHITECTURE.md` 维护规则处理。
4. **评审闭环同步**：`review-tech-design` 扩展现有维度（数据模型完整性：术语唯一且与已审批 PRD 语义一致；接口契约：按接口类型及目标仓既有规范应用条件基线；架构合理性：满足三判据的决策含真实 Alternatives 与 Consequences；多仓架构约束：按 `resources[].worktreePath` 读取相关仓 `ARCHITECTURE.md`），不新增评审节点。

### FR-09（P2）文档章节与落盘路径下沉

从 Pipeline prompt 删除以下由对应 Skill / `engineering-docs` / 版本化脚本负责的内容：

1. PRD/SDD/PLAN/TASK/规划报告固定章节；
2. 文件名和 slug 派生；
3. `_index.yml` 字段和排序规则；
4. review annotation 文件结构；
5. roadmap 幂等追加细节；
6. 竞品报告固定章节。

### FR-10（P2）展示节点收敛

1. `resume-cr` node-3 `cr-show` 删除 Pipeline 自行读取组织 `_backlog.yml`、`cr.md`、PRD/SDD/TASK/test-report/review annotations、最近三次 push-progress、`crctl next`、`crctl status`/`STATUS_DIVERGED` 的字段清单与账本定位规则；改为调用 `cr-show`（`cr-id`、`section: all`）并消费其结构化详情，下一步由 `cr-show` 内部调用 `crctl next` 计算；若「最近三次 checkpoint」是产品必需展示项，补入 `cr-show` Skill 输出契约而非只写在 Pipeline prompt。
2. requirement-authoring、architecture-design、code-implementation 中四个 CR `approve-*` 节点的输出统一消费对应 Skill 结构化结果，不写死下一 Pipeline；本条不适用于无 CR 上下文的规划类 human approval（其语义见 FR-02.6）。

### FR-11（P2）feature-writeback 一行级收敛

删除 node-1 的「校验 cr.md 当前 status=code-approved，否则 abort」预检（该校验已由 `merge-feature-branch` / `crctl merge` 承担）；Pipeline 保留失败中止即可。node-2 至 node-5 维持现状，无需重构。

### FR-12 保留契约与机器事实源边界

1. 每个 `kind=skill` 节点 prompt 收敛后最多保留 §2.2 五要素，不把 Pipeline 机器字段（reviewLoop/replayNodes/passCondition/onFail/timeout）搬回 Skill 文本，也不让 Skill 另写一份 reviewLoop 规则。
2. requirement-authoring 原样保留 `register → PRD → optional checkpoint → review → human approval → approve → checkpoint` 顺序、`auto_push_after_prd` 的 skip/execute 条件分支、reviewLoop 与 execution_context 节点间传递。
3. code-implementation 原样保留 `plan → TASK → review-dev-plan → human approval → developing`，以及 `implement → test-report → checkpoint → freshness → review-code` 顺序；reviewLoop 的 `replayNodes`、`passCondition`、`maxAttempts`、代码评审前已有 test-report、代码审批前经过 checkpoint 和人工审批均不得删改。
4. Pipeline 节点数量保持不变，除非 competitive-radar 的业务闭环无法在现有节点内表达（FR-04.4 的显式运行时编排支持）。
5. 改动 Pipeline 节点数量时同步 `pipeline-templates/_index.yml#nodes`；`node.ref` 必须是 active Skill；`human_approval` 不得替代状态写入。

### FR-13 范围边界与自检

1. 不新增：Pipeline 专用事务层、状态投影、第二套 review-loop 账本、第二套测试证据格式、candidate/manifest/merge/recovery 算法、通用 Runner 框架、事务日志、独立 ADR/跨 CR CONTEXT/术语中心。
2. 不改：状态机、gates、`crctl` 深原语（register/status/next/gate/advance/review-record/approve/test/task/checkpoint/merge/writeback/archive）、审批 grant、reviewLoop 业务语义、traceability evidence 结构。
3. 不把规划类本地 review annotations 强行迁移到 `crctl`；不把 README 扩展成可执行 Pipeline 事实源；不批量改写历史文档 schema。
4. 修改后在 tools 根目录运行：
   - `node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"`
   - `node skills/shared/crctl/scripts/lint-prompts.mjs`
   - `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`
5. 修改 Skill 时还须确定性检查：active ref 与 `skills/_index.yml`/`agent-skill-matrix.yml` 不漂移；写入型 Skill 调用 `validate-doc` 或等价校验；Git/shell 走 `controlled-shell`；CR 上下文摘要统一使用「以 `crctl next {cr_id}` 为准」；不直接写受保护账本；跨行解析/哈希先规范化 CRLF→LF，解析失败硬失败。

### 4.1 Source → FR → AC 追踪

| Source 范围 | 落地 FR | 验收 AC |
|---|---|---|
| §5 architecture-design | FR-01、FR-05～FR-08、FR-12 | AC-01、AC-05～AC-08、AC-12 |
| §6 write-tech-design 三项能力 | FR-08 | AC-08 |
| §7 requirement-authoring | FR-01、FR-05～FR-07、FR-12 | AC-01、AC-05～AC-07、AC-12 |
| §8 code-implementation | FR-01、FR-05～FR-07、FR-09、FR-12 | AC-01、AC-05～AC-07、AC-09、AC-12 |
| §9 product-planning | FR-02、FR-09、FR-12 | AC-02、AC-09、AC-12 |
| §10 market-to-plan | FR-03、FR-09 | AC-03、AC-09 |
| §11 competitive-radar | FR-04、FR-09 | AC-04、AC-09 |
| §12 feature-writeback | FR-11 | AC-11 |
| §13 resume-cr | FR-10 | AC-10 |
| §14～§18 优先级与顺序 | FR-01～FR-12 | AC-01～AC-12、AC-14 |
| §19～§20 排除项与自检 | FR-13 | AC-13 |

## 5. 非功能需求

- **NFR-01 极简性**：净效果以删除重复合同为主；不新增框架、registry、数据库、通用解释器、事务层或 Pipeline 专用脚本。
- **NFR-02 单一事实源**：Pipeline 保留机器编排事实（node/ref/reviewLoop/replayNodes/passCondition/onFail/timeout），业务判断归 Skill，状态/账本/审批/测试证据归 `crctl` 与版本化脚本；职责边界与本 PRD §1 一致。
- **NFR-03 正确性优先**：阶段一 FR-01～FR-05 的输入契约、受保护路径与审批契约断言全部通过后再进入阶段二职责收敛；跨行解析、哈希等代码遵守 CRLF 规范化与「解析失败硬失败」纪律。
- **NFR-04 可验证性**：每项收敛均有确定性断言支撑——Pipeline JSON 可解析、`node.ref` 为 active Skill、必填输入映射存在、受保护账本手写指引为 0、下一步提示统一为 `crctl next`。
- **NFR-05 兼容性**：删除重复说明不得改变现有公开命令、合法人工审批、reviewLoop 与深原语结构化结果；不得改变 8 条 Pipeline 的可达状态与流程闭环。

## 6. 验收标准

- **AC-01（FR-01）**：三条 CR Pipeline 的 human approval 节点不存在任何「编辑/补充 review-annotations/*.yml」指引；人工提示只含 approve/reject 决定及理由，且说明理由经 `approve-*` reject 流程记录、回退与证据由 `crctl approve` 完成。
- **AC-02（FR-02）**：product-planning 的 feedback/market/current-product 节点显式传 `topic`；`write-competitive-report` 具备 `updates-block/product-snapshot/confirmed` 输入映射与 fetch/context 来源；`write-planning-report` 传 prev_outputs/review_feedback/self_repair_attempt；`write-roadmap` 不含规划报告 `_index.yml` 跨文档写入；human approval 只收集结构化 approve/reject+reason，不要求修改报告，reject 中止正向链且不迁移到 CR 审批机制。
- **AC-03（FR-03）**：market-to-plan 的 `planning-draft` 传 `context` 与 `intent`；brief 调用有显式 `mode=brief`/`raw_insight_path` 输入且无 `source` 伪造参数；`write-planning-entry` 不修改 `docs/market-insights/_index.yml`。
- **AC-04（FR-04）**：competitive-radar node-1 存在 slug→competitor-id、since_days→lookback-days 显式映射或统一参数名；node-3 支持 reportPath/reportDraft 二选一且 reportDraft 含草稿正文、competitorId、reportDate、来源标识，草稿模式不落盘、两者同时存在优先 reportPath；node-5 传递 updates-block/product-snapshot/confirmed=true 后顺序调用 write-competitive-report → write-planning-entry，且不在 prompt 复制报告落盘算法。
- **AC-05（FR-05）**：四个 approve 节点不含 `crctl approve` 命令细节/TTY/grant/CAS/状态级联/`approval.yml` 文本；均传完整 `cr_id` 与 `approver`；下一步提示统一为「以 `crctl next {cr_id}` 为准」，不写死下一条 pipeline。
- **AC-06（FR-06）**：review-requirement/review-tech-design/review-dev-plan 不含评审维度正文、临时 payload、`review-record` 调用与 annotation/traceability 写入；write-test-report 不含 test plan schema/白名单/机器区/marker 算法；review-code 不含取证命令/证据规则/回修重建算法；各节点 reviewLoop 机器字段保留且 replayNodes 顺序正确。
- **AC-07（FR-07）**：write-tech-design 以 `workspace inspect` 输出为唯一路径事实且输入含 `operational_workspace`/`resources`；`ARCHITECTURE.md` 与 `sdd.md` 按所属仓分别提交并进入同批 checkpoint；architecture node-5 只传 cr_id/message、消费 phase，保留 phase=complete 与失败只重跑 checkpoint 语义；register 不含完整命令/路径派生；implement 不含 runtime fallback/读取清单/并发算法；freshness 只传 cr_id+gate 并消费 route；write-dev-plan 不含章节/status/输入文件算法；write-dev-tasks 不含格式/接口签名/task init/估算交叉校验/索引失败算法，且能消费 TASK 列表、估算与结构化结果。
- **AC-08（FR-08）**：write-tech-design Skill 术语硬化/HTTP 契约基线/关键决策记录按收窄范围落文（条件触发、仓库约定优先、三判据）；每个风险术语至少有一个覆盖 FR/AC、权限、实体或接口边界的代表性验证场景；review-tech-design 评审维度包含数据模型完整性/接口契约/架构合理性/多仓约束且不新增评审节点。
- **AC-09（FR-09）**：8 条 Pipeline prompt 中不存在 PRD/SDD/PLAN/TASK/规划报告固定章节、文件名 slug 派生、`_index.yml` 字段排序、review annotation 文件结构、roadmap 幂等追加、竞品报告固定章节的重复描述。
- **AC-10（FR-10）**：resume-cr node-3 改为调用 `cr-show` 并消费结构化详情，不含 CR 详情字段/状态映射清单；四个 CR `approve-*` 节点输出不写死下一 Pipeline，规划类审批不被错误迁移到 CR 审批机制。
- **AC-11（FR-11）**：feature-writeback node-1 不含 `status=code-approved` 预检文本；node-2 至 node-5 无改动。
- **AC-12（FR-12）**：每个 kind=skill 节点 prompt 收敛到五要素内；`pipeline-structure.test.mjs` 确定性断言 requirement-authoring 的关键顺序、auto_push skip/execute、execution_context/reviewLoop，以及 code-implementation 的两条关键顺序、test-report/checkpoint/审批前置与 replayNodes；Pipeline 节点数量与 `_index.yml#nodes` 一致（除 FR-04.4 必要的运行时编排支持）；`node.ref` 均为 active Skill。
- **AC-13（FR-13）**：`crctl` 生产算法、状态机、gates、审批 grant、reviewLoop 业务语义、traceability evidence 结构无行为改动；三条明确自检命令全部通过；Skill/index/matrix、validate-doc 等价校验、controlled-shell、crctl next、受保护账本、CRLF 规范化与解析硬失败检查均通过；无新增事务框架/账本/runner registry。
- **AC-14（两阶段顺序）**：实施记录可证明阶段一先完成 FR-01～FR-05，且其契约断言全部通过后才进入阶段二；阶段二按 architecture-design→requirement-authoring→code-implementation→resume-cr→feature-writeback→规划类 Pipeline 顺序执行。

## 7. 成功指标

- 8 条 Pipeline prompt 中受保护账本手写指引、评审/审批/测试/注册/freshness 算法副本降为 0。
- product-planning / market-to-plan / competitive-radar 三类规划流程按 Skill 必填输入契约可闭环，无「缺参导致运行失败」或「草稿未落盘却要求 reportPath」的矛盾。
- 四个 CR `approve-*` 节点下一步提示 100% 统一为「以 `crctl next {cr_id}` 为准」，无写死 pipeline 名；规划类审批保持自身结构化决定语义。
- 本 CR 净效果为删除重复合同，不新增生产依赖、公共命令、事务框架或长期接口。
- 状态机、gates、crctl 深原语保持原实现与回归测试，不被本 CR 重新设计。

## 8. 依赖与风险

- **依赖**：`docs/analysis/pipeline流程优化.md`（审计事实源，§14/15/16 清单）；`../tools/pipeline-templates/*.pipeline.json` 当前内容；对应 Skill 与 `crctl` 现行契约；`agent-skill-matrix.yml` 与 `pipeline-templates/_index.yml`。
- **风险 R-01 过度删除**：文本收缩可能删掉真实业务判断。处理：只删执行层算法副本，保留业务前置、输入输出、结构化结果分类与 reviewLoop；每个节点保留五要素。
- **风险 R-02 契约漂移再犯**：删除时若照抄旧文本会把漂移保留。处理：以 Skill 现行 SKILL.md 与 `crctl` 现行命令为唯一事实源核对，而非以旧 Pipeline prompt 为准。
- **风险 R-03 规划流程闭环破坏**：competitive-radar 草稿/落盘顺序改动可能破坏两阶段落盘。处理：node-3 支持 reportDraft 二选一，node-5 顺序调用两 Skill；若运行时不支持单节点顺序调用，先显式支持再落地，不新增业务 Skill。
- **风险 R-04 Pipeline 顺序回归**：删除/改动节点后 reviewLoop 或 checkpoint 顺序可能受影响。处理：验收以 `node.ref` 与 kind 顺序断言，不依赖旧数组下标；同步 `_index.yml#nodes`。
- **风险 R-05 术语/REST/决策收窄过宽或过窄**：处理：术语硬化仅覆盖进入模型/状态机/接口契约且有歧义/别名/边界风险者；REST 基线条件触发且仓库约定优先；决策记录三判据同时满足才落；评审维度同步但不新增节点。

## 9. 范围排除

- 不修改状态机、gates、`crctl` 深原语、审批 grant、reviewLoop 业务语义、traceability evidence 结构。
- 不新增 Pipeline 专用事务层/状态投影/第二套 review-loop 账本/测试证据格式/candidate-manifest-merge-recovery 算法/通用 Runner 框架。
- 不把规划类本地 review annotations 强行迁移到 `crctl`；不为每个 Pipeline 新建事务日志；不重实现 worktree/merge/checkpoint/archive。
- 不新增独立 ADR、跨 CR CONTEXT、术语中心或术语资产；不把 README 扩展成可执行 Pipeline 事实源。
- 不统一所有历史文档 schema；不批量改写历史 CR、历史 traceability、历史评审记录或 OpenWiki 历史快照。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘于 CR-2026-050 knowledge-base worktree。

## 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-21 | v0.1.1 | Ray | 首轮评审回修：修正两阶段边界，补齐 competitive-radar 草稿契约、跨仓 checkpoint、plan/TASK 收敛、规划审批、风险术语边界场景、流程保留与 Skill 自检 |
| 2026-08-21 | v0.1.0 | Ray | 初始草稿：基于 pipeline流程优化.md 审计落地，P0 正确性 + P1/P2 职责收敛，单 CR 两阶段 |
