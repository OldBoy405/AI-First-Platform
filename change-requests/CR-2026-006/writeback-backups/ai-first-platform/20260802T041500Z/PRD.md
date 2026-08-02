---
id: ai-first-platform-prd
spec-id: ai-first-platform
type: PRD
cr-ref: CR-2026-002
cr-history: [CR-2026-001, CR-2026-002]
title: AI First 研发协同平台
target-version: "0.11"
owner: Ray
owner-role: requirement
status: ga
created: "2026-07-30T21:27:12+08:00"
updated: "2026-07-31T19:35:26+08:00"
version: v0.2.0
refs:
  upstream:
    - docs/product/AI-First平台-PRD.md
    - docs/product/P0-数据模型映射表.md
    - docs/product/P1-crctl接入设计.md
    - docs/product/P2-三模式聊天交互设计.md
    - docs/product/P3-组织智能设计.md
    - docs/product/Wiki子系统设计.md
  downstream: []
fr-list: [M0-FR-1, M0-FR-2, M0-FR-3, M0-FR-4, P1-FR-1, P1-FR-2, P1-FR-3, P1-FR-4, P1-FR-5, P1-FR-6, P1-FR-7]
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

## 基线变更记录

| 日期 | 基线版本 | CR | 说明 |
|------|---------|----|------|
| 2026-07-31 | v0.1.2 | CR-2026-001 | 基线建立：M0 地基 PRD 回写（当时为整文 cp） |
| 2026-07-31 | v0.2.0 | CR-2026-002 | 改为累积式基线：保留 M0 全文并新增 P1 治理核心节；FR/AC 引入里程碑前缀约定；target-version 0.10 → 0.11 |
| 2026-07-31 | v0.2.1 | CR-2026-003 | 缺陷修补附记（§8）：AC-1 embedded 幂等碰撞 + AC-3 归档自愈边界；target-version 0.11 → 0.11.1 |
| 2026-08-01 | v0.3.0 | CR-2026-004 | 新增 P2 D1 里程碑节：Team Agent 共享队列容量上限；target-version 0.11.1 → 0.12 |
| 2026-08-01 | v0.3.1 | CR-2026-005 | 治理工具链补丁附记：delivery/task 回写一致性门禁 + writeback-tasks 原子化；target-version 0.12 → 0.12.1 |
