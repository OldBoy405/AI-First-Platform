---
id: CR-2026-051-prd
type: PRD
cr-ref: CR-2026-051
title: IM 渠道审批接入 — 飞书审批提醒卡片（通知型 MVP）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-25T18:08:22+08:00
updated: 2026-08-25T19:12:00+08:00
---

# 1. 概述

## 1.1 问题陈述

CR 人工审批当前已有两条正式路径：人类在交互式终端执行 `crctl approve`，或有权限用户在 Web 项目会话中完成签名审批。缺口不在审批执行链路，而在**感知**：CR 进入人工审批门禁后，没有任何主动触达，审批人只能靠轮询 Web 或他人催办才知道有待审批事项，门禁停留时长因此被拉长。

## 1.2 解决方案摘要

只补齐"审批人及时得知有待审批事项"这一段体验：CR **实际进入**四个人工审批门禁时，向该 CR 所属项目 workspace 内已绑定飞书的 owner/admin 发送一次飞书私聊提醒卡片，卡片唯一操作"前往审批"跳回既有 Web 项目会话，审批仍在 Web 侧沿用现有签名、证据校验、漂移检查、grant 与 `crctl` 链路完成。

本 CR 不新增第三套审批执行链路，不新增事务框架、审批协议或多渠道抽象。通知是状态投影之后的**旁路体验**，不参与状态事务。

## 1.3 已解决基础设施（只复用，不重做）

以下为已核实的既有事实源，本 CR 直接复用：

| 能力 | 既有实现（已核实） | 本 CR 处理 |
|---|---|---|
| CR 状态机、门禁、CAS、受控账本、审计、原子提交 | `../tools/skills/shared/crctl` 及 `dir-graph.yaml#change-request-track.state_machine` | 零改动 |
| CR 状态投影与可信转换判定 | `server/internal/governance/crsync.go`（`curStatus == ev.FromStatus && KnownStatuses[ev.ToStatus] && IsLegalTransition(...)` 成立时更新投影并调用 `projectGateTransition`） | 仅在该可信点增发一个专用语义事件 |
| 人工审批执行（签名/证据/漂移/幂等/grant） | `server/internal/governance/approval.go` 与现有 grant 流程 | 零改动；飞书卡片不直接调用审批 |
| CR → 项目 → workspace 关联 | `cr.shell_issue_id → issue.project_id → project.workspace_id`（`shell_issue_id` 可为 NULL，历史 CR 天然落空） | 只读复用 |
| workspace 审批角色口径 | workspace 成员角色为 `owner` / `admin` / `member` 字符串，Web 侧以 `roleAllowed(member.Role, "owner", "admin")` 形式校验 | 复用同一角色口径筛收件人 |
| 飞书用户绑定 | `channel_user_binding`（`workspace_id`、`multica_user_id`、`installation_id`、`channel_type='feishu'`、`channel_user_id` 即 `open_id`；绑定行本身无 revoked 列，成员移除时绑定被清理） | 只读查询，不新增绑定模型 |
| 飞书安装与发送凭据 | `channel_installation`（`workspace_id`、`channel_type`、`status IN ('active','revoked')`、`config` 内含 app 凭据）；撤销安装只把 `status` 翻成 `revoked` 并保留行 | 只读查询；绑定有效性必须连带校验其关联安装为同 workspace、`feishu`、`active`（见 FR-5） |
| 按 `open_id` 发送飞书私聊交互卡片 | `lark` integration 已有 `SendBindingPromptCard`（按 `open_id` 私聊发卡）与 `SendInteractiveCard` / 卡片模板封装 | 增加同类的专用提醒卡片入口 |
| Web 基地址与项目会话路由 | `appURLFromEnv()`（优先 `MULTICA_APP_URL`，回退 `FRONTEND_ORIGIN`，两者皆空则返回空串）与 `/{workspaceSlug}/projects/{projectID}?tab=chat` | 复用生成 CTA 链接 |

职责边界保持不变：Agent 不接管状态机，Skill 不手写账本，`crctl` 不承担通知业务判断，通知模块不承担状态推进。

## 1.4 需求边界（注册摘要已拍板，原样采纳）

仅飞书渠道；best-effort 单次投递；失败只记日志不阻塞状态推进；不新增表 / outbox / 重试 / 多渠道抽象 / 卡片内审批；`tools` 包零改动。以上为注册阶段已确认边界，本 PRD 不重新定义、不扩大。

# 2. 用户故事

- **US-1（审批人 / workspace owner）**：作为 workspace owner，我希望 CR 进入需求 / 架构 / 开发启动 / 代码四个人工审批门禁时，在飞书私聊里立刻收到一张提醒卡片，这样我不必轮询 Web 就能知道该我签了。
- **US-2（审批人 / workspace admin）**：作为已绑定飞书的 admin，我希望卡片上只有"这是哪个 CR、卡在哪个阶段、点哪里去审批"，不希望在 IM 里读 PRD 全文或 diff。
- **US-3（审批人）**：作为审批人，我希望点"前往审批"能直接落到该项目的既有 Web 会话页，审批动作仍在 Web 完成，签名与证据校验一条不少。
- **US-4（非相关成员）**：作为 workspace 里的普通 member 或未绑定飞书的用户，我不希望收到与我无关或我无权处理的审批提醒。
- **US-5（平台运维 / CR 流程 owner）**：作为流程 owner，我希望飞书侧超时、限流、未绑定、无项目等任何异常都只留下可检索的结构化日志，绝不影响 CR 状态推进和其他审批渠道。

# 3. 功能需求

## FR-1 门禁进入语义事件

新增内部事件 `cr:approval-gate-entered`。**仅**在同时满足下列全部条件时发布：

1. 输入来自既有可信 CR 状态事件（走 `crsync` 事件消费路径）；
2. 状态转换合法且投影更新成功（即 `curStatus == ev.FromStatus`、`KnownStatuses[ev.ToStatus]`、`IsLegalTransition(from, to, trigger)` 均成立的那一支）；
3. `ev.FromStatus != ev.ToStatus`（旧状态与新状态不同）；
4. `ev.ToStatus` 属于四个人工审批门禁状态之一：`requirement-reviewing`（需求审批）、`tech-design-review-pending`（架构审批）、`task-breakdown`（开发启动审批）、`code-reviewing`（代码审批）。

事件只携带定位所需最小标识（CR 标识、workspace 标识、CR/issue 关联标识、新状态、事件标识）。项目、workspace、标题、审批人等可变信息由通知侧按现有数据源读取，**不把审批证据复制进事件**。

## FR-2 触发面隔离（不得误触发）

- **不得**以通用 `cr:updated`（`EventCRUpdated`）作为提醒触发源。已核实该事件由 5 处发布，其中包含 `reconcile.go` 与 `gate_projection.go`，把投影维护误当新审批请求会造成重复骚扰。
- 同一状态事件正常重放（投影已处于目标状态、`curStatus != ev.FromStatus`）走非可信分支（仅置 `needs_reconcile`），**不发布**门禁进入事件。
- 状态自环转移（如 `requirement-reviewing → requirement-reviewing`、`task-breakdown → task-breakdown`）因 FR-1 条件 3 被过滤，不重复提醒。
- checkpoint、reconcile、以及不改变状态的普通 CR 更新，均不触发提醒。

## FR-3 收件 workspace 与项目解析（跨 workspace fail-closed）

订阅方按 `cr.shell_issue_id → issue.project_id → project.workspace_id` 解析本次提醒的目标项目与 workspace。解析不到项目（`shell_issue_id` 为 NULL 的历史 CR、异常数据）时**跳过并记录原因**（`project-unresolved`），不新增兜底页面、不新增第二套路由、不影响 CR。

**唯一可信 workspace 锚点**：事件携带的 workspace 标识来自 `crsync` 事件消费入口（由 daemon 凭据解析出的 workspace），是整条解析链的唯一权威锚点。解析过程中读到的任何 `workspace_id` 只能用于比对，不得反过来覆盖或放宽锚点。

**每一跳都必须在同一 workspace 内闭合**（硬约束，缺一不可）：

1. `cr` 行按 `(workspace_id = 锚点, cr_id)` 定位（该二元组即 `cr` 的唯一键）；
2. `issue` 行按 `(id = cr.shell_issue_id, workspace_id = 锚点)` 定位；
3. `project` 行按 `(id = issue.project_id, workspace_id = 锚点)` 定位；
4. 成员集合按 `member.workspace_id = 锚点` 查询（FR-4）；
5. 绑定与安装按 `workspace_id = 锚点` 查询（FR-5）。

任一跳查不到、或读到的 `workspace_id` 与锚点不一致时 **fail-closed**：本次提醒整体跳过并记录结构化跳过日志（原因 `workspace-mismatch`），且**不得**放宽条件重查（不得退化为仅按主键或仅按外键查询）、不得跨 workspace 兜底。跳过不影响 CR 状态推进。

为何外键不够（已核实）：迁移 `124_channel_generalization.up.sql` 头部明示 channel_* 表 NO foreign keys / NO cascades、完整性规则移交应用层；`cr.shell_issue_id` 只是一个 issue 外键，现有 `project_gates.go` 的 `cr JOIN issue ON issue.id = cr.shell_issue_id` 并未比对 `cr.workspace_id = issue.workspace_id`（同文件对 project 则显式比对 workspace，并统一返回 404 不泄露存在性）。因此“外键存在”不能代替 workspace 一致性校验，否则异常关联可能把 CR 标题发到另一个 workspace。

## FR-4 收件人角色筛选

收件人 = 目标 workspace 中角色为 `owner` 或 `admin` 的成员，与 Web 审批链路同一角色口径。`member` 及其他角色不在收件人集合内。workspace 无任何 owner/admin 时按可观测跳过处理。

## FR-5 有效飞书绑定判定、去重与跳过

**“有效飞书绑定”的完整定义**（三条同时成立，缺一即无效）：

1. `channel_user_binding` 存在对应行：`workspace_id = 锚点`、`multica_user_id` = 目标用户、`channel_type = 'feishu'`，取 `channel_user_id` 作为 `open_id`；
2. 该行的 `installation_id` 能解析到 `channel_installation` 行，且该行 `workspace_id = 锚点`、`channel_type = 'feishu'`、**`status = 'active'`**；
3. 该用户仍是该 workspace 的 `owner`/`admin` 成员（由 FR-4 保证）。

条件 2 是必需的硬约束，理由已核实：`channel_installation.status` 由 CHECK 约束限定为 `active` / `revoked`；撤销安装只把 `status` 翻成 `revoked` 并**保留行**以供审计（`server/internal/handler/lark.go#RevokeLarkInstallation`），绑定行不随之删除，且 channel_* 表无外键；同时发送必须取到该安装的凭据（`SendBindingPromptCard` 的 `InstallationID InstallationCredentials` 源自安装 `config`）。只查绑定行会把已撤销安装下的绑定当成有效收件人。

**跳过原因必须可区分**（各自结构化落日志，均不影响 CR）：

| 情形 | 跳过原因 |
|---|---|
| 用户无 `feishu` 绑定行 | `binding-missing` |
| 绑定关联的安装 `status = 'revoked'` | `installation-revoked` |
| 绑定的 `installation_id` 查不到安装行（无外键导致的悬空绑定，orphan） | `installation-missing` |
| 安装行的 `workspace_id` 或 `channel_type` 与锚点不符 | `workspace-mismatch` |

**去重口径**：以 Multica user id 为第一去重键——同一用户在同一 workspace 可能持有多行绑定（`channel_user_binding` 的唯一键是 `(installation_id, channel_user_id)`，多个飞书安装即多行）。每个用户在单次事件内**只发一张卡**，在其有效绑定中取 `bound_at` 最新一条（并列时按绑定 `id` 升序）作为确定性选择；`open_id` 级去重作为第二道保险（同一 `open_id` 单次事件内只发一次）。

**不做**：不校验安装所绑定的 agent 是否仍存在——agent 被硬删的 orphan 安装其 app 凭据仍然有效、出站发送不依赖 WS 连接，为此再造一套有效性定义属超范围。此步全部为只读查询，不新增绑定模型、不新增表、不改绑定流程。

## FR-6 提醒卡片最小内容

卡片内容限定为：

1. 标题：`待人工审批`；
2. CR ID 与 CR 标题；
3. 当前审批阶段；
4. 固定说明：`自动评审已通过，等待人工审批`；
5. 唯一操作：`前往审批`。

卡片内**不含**批准 / 驳回按钮，不含 PRD/SDD 正文、评审证据、diff 或风险清单——这些继续只在 Web 展示。

## FR-7 CTA 落点与基地址

"前往审批"链接 = `appURLFromEnv()` 解析出的基地址 + `/{workspaceSlug}/projects/{projectID}?tab=chat`（既有项目会话路由）。`appURLFromEnv()` 优先 `MULTICA_APP_URL`、回退 `FRONTEND_ORIGIN`；两者皆未配置（返回空串）时**跳过发送并记录原因**（`app-url-missing`），不发送无效链接。

**边界**：基地址非空即按既有拼接口径使用，本 CR **不新增** URL 合法性校验（与 `outcome_replier` 直接拼接 `appURL` 同口径）。把基地址配成非法值属部署配置问题，表现为卡片链接不可达；日志中的 `cr_id` / `stage` / `result=sent` 足以归因，不为此引入校验器或新配置项。

## FR-8 投递语义、非阻塞边界与失败隔离

### FR-8.1 投递必须脱离状态消费路径（可验证的实现边界）

- 事件订阅者在 bus 回调（**同步执行**）内**只允许**做 payload 解析与字段校验，**不得**执行任何数据库查询或飞书 HTTP 调用；收件人解析与发送必须交由独立执行单元（goroutine）异步完成，bus 回调立即返回。
- 异步执行单元**不得**沿用状态消费的请求上下文：状态事件由 HTTP 入口 `HandleCREvents` 以 `r.Context()` 驱动，响应写出后该 ctx 即被取消。异步处理必须使用脱离请求生命周期的上下文（由 background 派生），并带**有界超时**——单个收件人发送 ≤ 10s（与既有 `Patcher.handleEvent` 同口径），单次事件整体处理 ≤ 60s；超时按失败记日志，不重试。
- 异步执行单元必须**自持 panic 恢复并记日志**：`events.Bus.Publish` 的 recover 只覆盖同步 handler，派生 goroutine 内的 panic 会击穿进程，不能依赖 bus 的保护。
- **并发有界**：在飞的提醒处理数须有上限（进程内计数即可，不新增队列表、不新增任务框架）；超过上限时**丢弃本次提醒并记结构化日志**（原因 `overloaded`），与 best-effort 单次投递语义一致——不排队堆积、不重试。
- 单个收件人失败或超时不影响同批其他收件人。

### FR-8.2 失败与跳过必须结构化可观测

- 每个门禁进入事件只触发一次内存态投递处理；每个收件人只尝试一次，不重试。
- 发送成功、失败、跳过三类结果的日志字段口径见 §4.4（含必需字段枚举与 recipient 口径）。
- 跳过原因取值限于：`project-unresolved`、`workspace-mismatch`、`no-approver`（无 owner/admin）、`binding-missing`、`installation-revoked`、`installation-missing`、`app-url-missing`、`feishu-disabled`、`overloaded`。

### FR-8.3 飞书未启用时仍须消费事件并记录跳过

- 审批提醒器的**事件订阅必须无条件注册**，不得放在飞书密钥条件装配块内。已核实 `server/cmd/server/router.go` 仅在 `secretbox.LoadKey("MULTICA_LARK_SECRET_KEY")` 成功时构造并注册 Lark 组件（否则记 `lark integration disabled`）；若订阅随之缺席，“未启用也记录跳过”无从实现。既有 `ChannelRouter`（无飞书也无条件构建）即为同类先例。
- 未启用 / stub 形态下，提醒器仍消费 `cr:approval-gate-entered`，并在**任何数据库查询之前**判定飞书不可用（client 为 nil 或 `IsConfigured() == false`），记录事件级跳过原因 `feishu-disabled` 后返回。
- 该形态下**不得发起任何真实飞书请求**：既有 `stubAPIClient` 的所有方法只记 Warn 并返回 `ErrAPIClientNotConfigured`、不产生 HTTP 流量，可直接作为测试替身。

### FR-8.4 失败隔离与 crash window

- 飞书 API 超时、限流或任何失败**不得**让状态事件消费回滚、不得阻断 CR 状态推进、不得影响 `crctl approve` 与 Web 审批两条既有路径。
- 允许"投影已完成、消息未发出时进程崩溃"或进程退出时在飞提醒丢失；**不得**为消除该 crash window 引入 outbox、通知表、幂等键、补偿扫描或退出前 drain/join。
- 异步处理开始时**不重新校验 CR 当前状态**：事件语义是“曾实际进入该门禁”，审批状态的权威呈现在 Web 侧。极小概率下审批人可能收到刚被处理完的门禁提醒，属可接受噪声，不为此引入二次状态读取、消息撤回或补偿。

## FR-9 发送能力复用边界

在 Lark integration 内新增单一用途的审批提醒器（职责仅为：解析项目/workspace → 取 owner/admin → 查有效飞书绑定 → 去重 → 逐个单次发送 → 记录跳过与失败）。client 侧新增专用方法 `SendApprovalReminderCard` 与其最小参数类型，卡片模板继续封装在 client 内；可把"按 `open_id` 发送交互卡片"的既有逻辑提取为私有 helper，供绑定提示与审批提醒共用。

**不得**：公开任意卡片 JSON 接口、抽象跨渠道 notifier（含 `IMApprovalNotifier` 一类预设接口）、新增卡片 DSL、复制完整飞书 client。提醒器不承担状态推进、审批执行、账本写入或重试调度。

## FR-10 零改动边界守卫

本 CR 代码改动面限定在 multica 仓：`server/internal/governance/crsync.go`（声明并在可信门禁进入点发布事件）、Lark integration 内新增审批提醒器与专用卡片方法、`server/cmd/server/router.go`（注入既有依赖并订阅事件；**订阅注册须在飞书密钥条件装配块之外**，见 FR-8.3）、以及对应测试文件。

明确零改动：`../tools/` 全部模块（Agent / Pipeline / Skill / crctl / 版本化脚本 / README）、数据库 schema 与迁移、CR 账本、`server/internal/governance/approval.go`、Web 审批页面与 API、grant daemon 与 task-token 流程。

## FR-11 启用条件（不新增配置）

不新增审批通知配置项、不新增功能开关、不引入用户级通知偏好。同时满足下列既有条件时自动工作：飞书 integration 已启用且可发消息；目标用户具备 workspace `owner`/`admin` 角色；目标用户存在**有效飞书绑定**（FR-5 三条件）；CR 可解析到项目且全链 workspace 一致（FR-3）；Web 基地址可用。任一条件不满足时按 FR-8.2 跳过并记录可区分原因——包括“飞书未启用”这一条，其可观测性由 FR-8.3 的无条件订阅保证。

# 4. 非功能需求

## 4.1 性能与可用性

- 通知处理不得进入 CR 状态事务的关键路径：状态投影提交与事件发布完成后，通知处理的耗时、阻塞或失败不得延长或回滚状态消费。**可验证边界**：飞书调用被人为阻塞至超时时，`HandleCREvents` 的响应时延与投影结果须与“无提醒器”基线同量级（差值仅为 bus 回调内的解析开销，不含任何 I/O 等待）。
- 该边界只能由订阅者自身保证，因为 `events.Bus.Publish`（`server/internal/events/bus.go`）对订阅者是**同步调用**：即回调内零 I/O + 异步 goroutine + 脱离请求 ctx + 有界超时 + 自持 panic 恢复（FR-8.1）。
- 飞书 API 调用须带上下文超时控制（单收件人 ≤ 10s、单事件 ≤ 60s）；单个收件人发送失败或超时不影响同批其他收件人。
- 在飞的提醒处理并发有上限，过载时按 `overloaded` 丢弃并记日志（FR-8.1）；不引入批量任务框架、队列表或重试调度。
- 单次门禁进入的收件人规模按 workspace owner/admin 数量计（正常为个位数）。

## 4.2 安全与权限

- 提醒仅发送给目标 workspace 的 `owner`/`admin`，且仅发送给已有有效飞书绑定的用户；不得向其他 workspace、`member` 角色或未绑定用户外泄 CR 存在与标题。
- 卡片与日志中不得出现审批证据、签名材料、token 或 diff 内容；卡片不引入任何可绕过 Web 签名审批的操作入口。
- 审批权限判定的唯一权威仍在 Web 审批链路与 `crctl` 门禁：收到卡片不等于获得审批权，点击 CTA 后仍由既有链路重新校验。

## 4.3 兼容性

- 不新增数据库表、不新增 schema migration、不修改既有表结构。
- `shell_issue_id` 为 NULL 的历史 CR、未绑定飞书的 workspace、未启用飞书 integration 的部署，均退化为"不发送 + 记录跳过"，不报错、不影响既有功能。
- 飞书 integration 处于 stub / 未启用形态时不得发起真实请求；该形态下提醒器仍订阅并消费专用事件，只记录 `feishu-disabled` 事件级跳过（FR-8.3），可用 `lark.NewStubAPIClient` 断言零真实请求、零收件人查询。
- 绑定关联安装为 `revoked`、或绑定 `installation_id` 悬空（无外键导致的 orphan）时，退化为“不发送 + 记录可区分跳过原因”，不报错、不影响既有功能。
- 现有绑定提示卡片行为不得因私有 helper 提取而改变（对外行为等价）。

## 4.4 可观测性

发送成功、失败、跳过三类结果均产生结构化日志，字段口径统一，可按 CR 与 stage 检索还原一次门禁的通知结果。

**必需字段枚举**：

| 字段 | 出现于 | 说明 |
|---|---|---|
| `cr_id` | 成功 / 失败 / 跳过 | CR 标识 |
| `stage` | 成功 / 失败 / 跳过 | 审批阶段（事件的新状态） |
| `workspace_id` | 成功 / 失败 / 跳过 | 可信 workspace 锚点（FR-3） |
| `event_id` | 成功 / 失败 / 跳过 | 门禁进入事件标识，用于把一次事件的多条日志串起来 |
| `recipient_user_id` | 成功 / 失败 / 收件人级跳过 | **recipient 的权威口径是 Multica user id** |
| `recipient_open_id` | 成功 / 失败 | 飞书侧定位用（与既有 lark client 日志同口径）；事件级跳过无此字段 |
| `result` | 成功 / 失败 / 跳过 | `sent` / `failed` / `skipped` |
| `reason` | 跳过 | 取值限于 FR-8.2 枚举 |
| `error_class` | 失败 | 错误类别（超时 / 限流 / 未配置 / 其他），不含响应体原文 |

事件级跳过（`project-unresolved`、`workspace-mismatch`、`no-approver`、`app-url-missing`、`feishu-disabled`、`overloaded`）记一条事件级日志；收件人级跳过（`binding-missing`、`installation-revoked`、`installation-missing`）记到收件人粒度。日志中不得出现审批证据、签名材料、token、diff 或飞书响应体原文。

# 5. 验收标准

| AC | 验收内容 | 对应 FR |
|---|---|---|
| AC-1 | CR 实际进入 `requirement-reviewing` / `tech-design-review-pending` / `task-breakdown` / `code-reviewing` 中任一状态时，发布**一次** `cr:approval-gate-entered` 专用语义事件 | FR-1 |
| AC-2 | 通用 `cr:updated`、checkpoint、reconcile、同状态重放与状态自环均**不**发送提醒；订阅方未订阅 `EventCRUpdated` | FR-1、FR-2 |
| AC-3 | 目标项目所在 workspace 的每个“有效飞书绑定 owner/admin”各收到一张飞书私聊卡片；有效性含“绑定关联安装为同 workspace、`feishu`、`active`”；同一用户只收到一张（多绑定取 `bound_at` 最新一条），同一 `open_id` 只收到一张 | FR-3、FR-4、FR-5 |
| AC-4 | 下列四种情形均**不**收到卡片，且各留下可区分跳过原因：非 owner/admin；无 `feishu` 绑定行（`binding-missing`）；绑定关联安装为 `revoked`（`installation-revoked`）；绑定 `installation_id` 悬空 orphan（`installation-missing`） | FR-4、FR-5、FR-8.2 |
| AC-5 | 卡片只包含 FR-6 五项最小内容，且"前往审批"指向 `{appURL}/{workspaceSlug}/projects/{projectID}?tab=chat` 的正确既有会话；基地址不可用时不发送 | FR-6、FR-7 |
| AC-6 | Web 中的批准 / 驳回仍完整走现有签名、证据校验、漂移检查、grant 入队与 `crctl` 推进链路，行为与本 CR 前一致 | FR-9、FR-10 |
| AC-7 | 发送成功 / 失败 / 跳过三类结果的结构化日志满足 §4.4 必需字段枚举（recipient 权威口径为 Multica user id，跳过原因取自 FR-8.2 枚举），且任何失败或跳过下状态事件消费成功、无回滚 | FR-8.2、FR-8.4、FR-11 |
| AC-8 | 未新增数据库表或 migration、未新增投递重试 / outbox / 幂等键、未新增消息 patch 或撤回、未新增多渠道抽象、`../tools/` 零改动；改动文件集合不超出 FR-10 声明范围 | FR-8、FR-9、FR-10 |
| AC-9 | 单元 / 集成测试覆盖：触发条件（四门禁 × 合法转换）、误触发隔离（通用事件 / reconcile / 重放 / 自环）、跨 workspace 负向、安装 revoked/orphan 跳过、多绑定与 `open_id` 去重、CTA 链接生成与基地址缺失、三类日志字段、非阻塞投递、飞书未启用形态 | FR-1～FR-11 |
| AC-10 | 跨 workspace 负向验收：`issue` / `project` / 绑定 / 安装任一层的 `workspace_id` 与事件锚点不一致时**零发送**并记 `workspace-mismatch`；实现的解析查询每一跳都带 workspace 约束（不存在仅按主键或仅按外键的查询路径） | FR-3、FR-5 |
| AC-11 | 飞书客户端被人为阻塞至超时时：状态消费与 `HandleCREvents` 响应不被延迟（与无提醒器基线同量级）、投影结果不变、无回滚，提醒按超时记失败日志；bus 回调内不含数据库或 HTTP 调用（可由测试替身零调用断言） | FR-8.1、§4.1 |
| AC-12 | 未设置 `MULTICA_LARK_SECRET_KEY`（飞书未启用 / stub 形态）时：专用事件仍被消费，记录一条 `feishu-disabled` 事件级跳过日志，且**零真实飞书请求、零收件人查询** | FR-8.3、§4.3 |
| AC-13 | 异步执行单元内的 panic 被自身捕获并记日志、进程不退出；在飞处理数达上限时新事件按 `overloaded` 丢弃并记日志，不排队、不重试 | FR-8.1 |

# 6. 成功指标

| 指标 | 定义 | 目标 |
|---|---|---|
| 提醒触达率 | 进入四门禁且满足 FR-11 启用条件的门禁事件中，至少有一名收件人发送成功的比例 | ≥ 95%（失败均可在日志中归因） |
| 审批等待时长 | 门禁进入 → 人工审批完成的中位时长，与上线前同口径基线对比 | 有可观测下降（作为"跳转 Web 是否构成主要阻力"的判断依据） |
| 误触发率 | 由 checkpoint / reconcile / 重放 / 自环导致的提醒条数 | 0 |
| 流程零阻塞 | 因通知逻辑导致的 CR 状态推进失败、状态事件消费回滚次数 | 0 |
| 跨 workspace 外泄 | 提醒被发送到事件锚点 workspace 之外的条数 | 0 |
| 跳过可归因率 | 未发送的门禁事件中，日志能给出明确跳过原因的比例 | 100% |

# 7. 范围排除

本 CR 明确**不做**（与设计稿 §2.2 一致，实施期不得夹带）：

- 飞书卡片内"批准 / 驳回"按钮及其回调处理；
- 新的 action token、回调签名协议、审批证据打包器；
- 消息状态更新、卡片撤回、审批完成后的卡片 patch；
- 通知 outbox、持久化投递记录、重试队列、幂等键或 exactly-once 保证；
- 新数据库表或 schema migration；
- Slack、钉钉、企业微信等其他渠道接入；
- `IMApprovalNotifier` 一类预设的多渠道 notifier 抽象；
- 用户级通知偏好或新的功能开关；
- 对 Web 审批页 / 审批 handler / `approval.go` / grant daemon / `crctl` / `tools` 的 Pipeline、Skill、README 的任何改造；
- 群聊通知、@提醒、通知摘要 / 聚合 / 免打扰策略；
- 通知队列持久化、进程退出前 drain/join、在飞提醒的补偿重发（见 FR-8.4）；
- URL 合法性校验器（基地址非空即按既有口径拼接，见 FR-7 边界）；
- 异步处理前的 CR 状态二次校验与“审批已完成”消息回收（见 FR-8.4）。

**后续演进条件**：只有当通知型 MVP 的使用数据证明"跳转 Web"确实构成主要审批阻力，且业务愿意承担回调鉴权、身份绑定、token 防重放、漂移证据与结果回写的额外复杂度时，才单独设计飞书卡片内审批。该能力不属于本版本的兼容性承诺。

# 8. 附录：事实核实记录

本 PRD 对 multica 仓既有能力的断言均于 2026-08-25 在 `../multica`（main）核实。初稿据此对设计稿 v0.2 作了两处**事实性澄清**（澄清 1 / 2）；需求评审 attempt 1 回修时又核实并补录澄清 3~7——均不改设计稿范围：

| 断言 | 核实方式与结果 |
|---|---|
| 可信状态转换点存在且可判定 `from != to` | `server/internal/governance/crsync.go` 中 `curStatus == ev.FromStatus && KnownStatuses[ev.ToStatus] && IsLegalTransition(...)` 分支持有 `ev.FromStatus`/`ev.ToStatus` 并调用 `projectGateTransition` |
| 通用 `cr:updated` 不可作触发源 | `EventCRUpdated = "cr:updated"`；`publish` 由 `crsync.go`（3 处）、`gate_projection.go`、`reconcile.go` 共 5 处调用 |
| 四门禁状态名 | 以 `../tools/dir-graph.yaml#change-request-track.state_machine` 当前内容核对：`requirement-reviewing`、`tech-design-review-pending`、`task-breakdown`、`code-reviewing` 均为具名状态 |
| 按 `open_id` 发飞书私聊卡片的能力已存在 | `lark` integration 已有 `SendBindingPromptCard`（`BindingPromptParams.OpenID`）与 `SendInteractiveCard`，卡片模板封装在 client 内 |
| CR → 项目关联 | `cr.shell_issue_id` → `issue.project_id`（`362_aifirst_cr_projection.up.sql` 声明为 nullable，`project_gates.go` 已用同一 join） |
| **澄清 1：绑定"有效性"无 revoked 列** | `channel_user_binding`（`124_channel_generalization.up.sql`）字段为 `workspace_id / multica_user_id / installation_id / channel_type / channel_user_id / config / bound_at`，无 revoked 或 status 列；有效性由行存在 + workspace 成员关系保证（迁移注释明示成员移除时清理绑定）。故 FR-5 以"行存在 + `channel_type='feishu'` + `workspace_id` 匹配"定义有效绑定，且 `channel_type` 取值为 `'feishu'` 而非 `'lark'` |
| **澄清 2：Web 基地址不止 `MULTICA_APP_URL`** | `server/cmd/server/router.go#appURLFromEnv()` 优先 `MULTICA_APP_URL`，回退 `FRONTEND_ORIGIN`，两者皆空返回空串。故 FR-7 的跳过条件是"`appURLFromEnv()` 返回空串"，而非"未设置 `MULTICA_APP_URL`" |
| workspace 审批角色口径 | workspace 成员角色为 `owner`/`admin`/`member` 字符串（`server/internal/handler/workspace.go`），既有 `roleAllowed(member.Role, "owner", "admin")` 用法可复用 |
| **澄清 3：安装有 `status` 列，且撤销保留行** | `channel_installation`（同上迁移）含 `status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked'))`；`server/internal/handler/lark.go#RevokeLarkInstallation` 把 status 翻成 `revoked` 并保留行以供审计（重装再翻回 `active`）。故 FR-5 的有效绑定 = 绑定行 + 关联安装同 workspace/`feishu`/`active` |
| **澄清 4：跨 workspace 一致性不能靠外键** | 迁移 124 头部明示 channel_* 表 NO foreign keys / NO cascades、完整性规则移交应用层；`project_gates.go` 的 `cr JOIN issue ON issue.id = cr.shell_issue_id` 未比对 `cr.workspace_id = issue.workspace_id`（同文件对 project 则显式比对 workspace 并统一返回 404）。故 FR-3 要求每跳带 workspace 约束、fail-closed |
| **澄清 5：Bus 对订阅者是同步调用，且状态消费走请求 ctx** | `server/internal/events/bus.go#Publish` 逐个**同步**调用 handler（recover 仅覆盖同步 handler）；`crsync.go` 在 `applyStatus` 内调 `publish`，而入口 `HandleCREvents` 传入 `r.Context()`。故 FR-8.1 要求回调零 I/O + 派生 goroutine + 脱离请求 ctx + 自持 panic 恢复 |
| **澄清 6：有界超时已有同口径先例** | `server/internal/integrations/lark/outbound.go#Patcher.handleEvent` 用 `context.WithTimeout(context.Background(), 10*time.Second)`，注释明写 bus 投递同步、卡住的 Lark HTTP 调用会卡住整个 publish 调用点 |
| **澄清 7：飞书组件为条件装配，且存在 stub 客户端** | `server/cmd/server/router.go` 仅在 `secretbox.LoadKey("MULTICA_LARK_SECRET_KEY")` 成功时构造 Lark 组件，否则记 `lark integration disabled`；`lark.NewStubAPIClient` 的方法只记 Warn 并返回 `ErrAPIClientNotConfigured`（零 HTTP 流量）；`ChannelRouter` 则为无条件构建先例。故 FR-8.3 要求订阅无条件注册 + stub 形态零真实请求 |
| 每跳 workspace 约束在数据上可实现 | `member`（`001_init.up.sql`）含 `workspace_id` / `user_id` / `role CHECK (role IN ('owner','admin','member'))`；`issue`（`001_init`）、`project`（`034_projects`）、`cr`（`362_aifirst_cr_projection`）三表均有 `workspace_id`；`channel_user_binding` 唯一键为 `(installation_id, channel_user_id)` |

上述澄清均只使 FR / AC 描述与代码事实一致，**不影响**设计稿 §2 范围与 §10 验收结论。

# 9. 修订记录

| 版本 | 时间 | 变更 |
|---|---|---|
| 初稿 | 2026-08-25T18:08:22+08:00 | 首版 11 FR / 5 US / 9 AC |
| 需求评审 attempt 1 回修 | 2026-08-25T19:12:00+08:00 | 按 `review-annotations/requirement.yml`（verdict `block`，4 blocker）定点修复，范围未动（设计稿 §2.1/§2.2 原封不动，FR 数仍为 11，AC 9 → 13）：① blocker-1 → FR-5 重写（有效绑定加“关联安装同 workspace/`feishu`/`active`”，新增 revoked/orphan 可区分跳过原因与每用户去重）+ §1.3 表 + AC-3/AC-4 + §4.3 + 澄清 3；② blocker-2 → FR-3 重写（可信 workspace 锚点 + 每跳硬约束 + fail-closed）+ FR-5 条件 1/2 + AC-10 + 澄清 4；③ blocker-3 → FR-8 拆为 FR-8.1~8.4（回调零 I/O、脱离请求 ctx、有界超时、panic 自持恢复、并发上限与 `overloaded` 丢弃）+ §4.1 可验证边界 + AC-11/AC-13 + 澄清 5/6；④ blocker-4 → FR-8.3（订阅无条件注册、`feishu-disabled` 跳过、stub 零真实请求）+ FR-10/FR-11 装配约束 + AC-12 + 澄清 7；⑤ 评审 suggestions → §4.4 必需字段枚举与 recipient 口径、FR-7 非法基地址边界、FR-8.4 异步前不二次校验状态、FR-5 多绑定去重。 |
