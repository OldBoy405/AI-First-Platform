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
