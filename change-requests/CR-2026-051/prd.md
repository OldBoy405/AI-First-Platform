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
updated: 2026-08-25T18:08:22+08:00
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
| 飞书用户绑定 | `channel_user_binding`（`workspace_id`、`multica_user_id`、`channel_type='feishu'`、`channel_user_id` 即 `open_id`；表无 revoked 列，有效性由行存在 + 成员关系保证，成员移除时绑定被清理） | 只读查询，不新增绑定模型 |
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

## FR-3 收件 workspace 与项目解析

订阅方按 `cr.shell_issue_id → issue.project_id → project.workspace_id` 解析本次提醒的目标项目与 workspace。解析不到项目（`shell_issue_id` 为 NULL 的历史 CR、异常数据）时**跳过并记录原因**，不新增兜底页面、不新增第二套路由、不影响 CR。

## FR-4 收件人角色筛选

收件人 = 目标 workspace 中角色为 `owner` 或 `admin` 的成员，与 Web 审批链路同一角色口径。`member` 及其他角色不在收件人集合内。workspace 无任何 owner/admin 时按可观测跳过处理。

## FR-5 飞书绑定筛选与去重

对 FR-4 得到的用户集合，查询 `channel_user_binding` 中 `workspace_id` 匹配、`channel_type = 'feishu'` 的绑定行，取 `channel_user_id` 作为 `open_id`；无绑定行的用户直接跳过。发送前对 `open_id` **去重**，同一 `open_id` 单次事件内只发一次。此步为只读查询，不新增绑定模型、不新增表、不改绑定流程。

## FR-6 提醒卡片最小内容

卡片内容限定为：

1. 标题：`待人工审批`；
2. CR ID 与 CR 标题；
3. 当前审批阶段；
4. 固定说明：`自动评审已通过，等待人工审批`；
5. 唯一操作：`前往审批`。

卡片内**不含**批准 / 驳回按钮，不含 PRD/SDD 正文、评审证据、diff 或风险清单——这些继续只在 Web 展示。

## FR-7 CTA 落点与基地址

"前往审批"链接 = `appURLFromEnv()` 解析出的基地址 + `/{workspaceSlug}/projects/{projectID}?tab=chat`（既有项目会话路由）。`appURLFromEnv()` 优先 `MULTICA_APP_URL`、回退 `FRONTEND_ORIGIN`；两者皆未配置（返回空串）时**跳过发送并记录原因**，不发送无效链接。

## FR-8 投递语义与失败隔离

- 每个门禁进入事件只触发一次内存态投递处理；每个收件人只尝试一次，不重试。
- 发送失败时记录结构化日志，字段至少包含：CR ID、审批阶段（新状态）、workspace 标识、收件人标识、错误类别。
- 跳过场景（无项目、无基地址、无 owner/admin、无有效飞书绑定、飞书 integration 未启用）同样产生可观测的结构化跳过日志与原因。
- 飞书 API 超时、限流或任何失败**不得**让状态事件消费回滚、不得阻断 CR 状态推进、不得影响 `crctl approve` 与 Web 审批两条既有路径。
- 允许"投影已完成、消息未发出时进程崩溃"导致该次提醒丢失；**不得**为消除该 crash window 引入 outbox、通知表、幂等键或补偿扫描。

## FR-9 发送能力复用边界

在 Lark integration 内新增单一用途的审批提醒器（职责仅为：解析项目/workspace → 取 owner/admin → 查有效飞书绑定 → 去重 → 逐个单次发送 → 记录跳过与失败）。client 侧新增专用方法 `SendApprovalReminderCard` 与其最小参数类型，卡片模板继续封装在 client 内；可把"按 `open_id` 发送交互卡片"的既有逻辑提取为私有 helper，供绑定提示与审批提醒共用。

**不得**：公开任意卡片 JSON 接口、抽象跨渠道 notifier（含 `IMApprovalNotifier` 一类预设接口）、新增卡片 DSL、复制完整飞书 client。提醒器不承担状态推进、审批执行、账本写入或重试调度。

## FR-10 零改动边界守卫

本 CR 代码改动面限定在 multica 仓：`server/internal/governance/crsync.go`（声明并在可信门禁进入点发布事件）、Lark integration 内新增审批提醒器与专用卡片方法、`server/cmd/server/router.go`（注入既有依赖并订阅事件）、以及对应测试文件。

明确零改动：`../tools/` 全部模块（Agent / Pipeline / Skill / crctl / 版本化脚本 / README）、数据库 schema 与迁移、CR 账本、`server/internal/governance/approval.go`、Web 审批页面与 API、grant daemon 与 task-token 流程。

## FR-11 启用条件（不新增配置）

不新增审批通知配置项、不新增功能开关、不引入用户级通知偏好。同时满足下列既有条件时自动工作：飞书 integration 已启用且可发消息；目标用户具备 workspace `owner`/`admin` 角色；目标用户存在有效飞书绑定；CR 可解析到项目；Web 基地址可用。任一条件不满足时按 FR-8 跳过并记录原因。

# 4. 非功能需求

## 4.1 性能与可用性

- 通知处理不得进入 CR 状态事务的关键路径：状态投影提交与事件发布完成后，通知处理的耗时、阻塞或失败不得延长或回滚状态消费。
- 飞书 API 调用须带上下文超时控制，单个收件人发送失败不影响同批其他收件人。
- 单次门禁进入的收件人规模按 workspace owner/admin 数量计（正常为个位数），不引入批量任务框架。

## 4.2 安全与权限

- 提醒仅发送给目标 workspace 的 `owner`/`admin`，且仅发送给已有有效飞书绑定的用户；不得向其他 workspace、`member` 角色或未绑定用户外泄 CR 存在与标题。
- 卡片与日志中不得出现审批证据、签名材料、token 或 diff 内容；卡片不引入任何可绕过 Web 签名审批的操作入口。
- 审批权限判定的唯一权威仍在 Web 审批链路与 `crctl` 门禁：收到卡片不等于获得审批权，点击 CTA 后仍由既有链路重新校验。

## 4.3 兼容性

- 不新增数据库表、不新增 schema migration、不修改既有表结构。
- `shell_issue_id` 为 NULL 的历史 CR、未绑定飞书的 workspace、未启用飞书 integration 的部署，均退化为"不发送 + 记录跳过"，不报错、不影响既有功能。
- 飞书 integration 处于 stub / 未启用形态时不得发起真实请求。
- 现有绑定提示卡片行为不得因私有 helper 提取而改变（对外行为等价）。

## 4.4 可观测性

发送成功、失败、跳过三类结果均产生结构化日志，字段口径统一（CR、stage、workspace、recipient、结果或错误类别），可按 CR 与 stage 检索还原一次门禁的通知结果。

# 5. 验收标准

| AC | 验收内容 | 对应 FR |
|---|---|---|
| AC-1 | CR 实际进入 `requirement-reviewing` / `tech-design-review-pending` / `task-breakdown` / `code-reviewing` 中任一状态时，发布**一次** `cr:approval-gate-entered` 专用语义事件 | FR-1 |
| AC-2 | 通用 `cr:updated`、checkpoint、reconcile、同状态重放与状态自环均**不**发送提醒；订阅方未订阅 `EventCRUpdated` | FR-1、FR-2 |
| AC-3 | 目标项目所在 workspace 的每个"已绑定飞书的 owner/admin"各收到一张飞书私聊卡片；同一 `open_id` 只收到一张 | FR-3、FR-4、FR-5 |
| AC-4 | 非 owner/admin 用户、无有效飞书绑定的 owner/admin 均**不**收到卡片 | FR-4、FR-5 |
| AC-5 | 卡片只包含 FR-6 五项最小内容，且"前往审批"指向 `{appURL}/{workspaceSlug}/projects/{projectID}?tab=chat` 的正确既有会话；基地址不可用时不发送 | FR-6、FR-7 |
| AC-6 | Web 中的批准 / 驳回仍完整走现有签名、证据校验、漂移检查、grant 入队与 `crctl` 推进链路，行为与本 CR 前一致 | FR-9、FR-10 |
| AC-7 | 飞书发送失败，或缺少项目 / 基地址 / 收件人 / 绑定时，均有含 CR、stage、workspace、recipient、错误或跳过原因的结构化日志，且 CR 状态推进不受影响（状态事件消费成功、无回滚） | FR-8、FR-11 |
| AC-8 | 未新增数据库表或 migration、未新增投递重试 / outbox / 幂等键、未新增消息 patch 或撤回、未新增多渠道抽象、`../tools/` 零改动；改动文件集合不超出 FR-10 声明范围 | FR-8、FR-9、FR-10 |
| AC-9 | 单元 / 集成测试覆盖：触发条件（四门禁 × 合法转换）、误触发隔离（通用事件 / reconcile / 重放 / 自环）、收件人筛选与去重、CTA 链接生成、失败与跳过隔离 | FR-1～FR-8 |

# 6. 成功指标

| 指标 | 定义 | 目标 |
|---|---|---|
| 提醒触达率 | 进入四门禁且满足 FR-11 启用条件的门禁事件中，至少有一名收件人发送成功的比例 | ≥ 95%（失败均可在日志中归因） |
| 审批等待时长 | 门禁进入 → 人工审批完成的中位时长，与上线前同口径基线对比 | 有可观测下降（作为"跳转 Web 是否构成主要阻力"的判断依据） |
| 误触发率 | 由 checkpoint / reconcile / 重放 / 自环导致的提醒条数 | 0 |
| 流程零阻塞 | 因通知逻辑导致的 CR 状态推进失败、状态事件消费回滚次数 | 0 |
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
- 群聊通知、@提醒、通知摘要 / 聚合 / 免打扰策略。

**后续演进条件**：只有当通知型 MVP 的使用数据证明"跳转 Web"确实构成主要审批阻力，且业务愿意承担回调鉴权、身份绑定、token 防重放、漂移证据与结果回写的额外复杂度时，才单独设计飞书卡片内审批。该能力不属于本版本的兼容性承诺。

# 8. 附录：事实核实记录

本 PRD 对 multica 仓既有能力的断言均于 2026-08-25 在 `../multica`（main）核实，并据核实结果对设计稿 v0.2 作两处**事实性澄清**（不改范围）：

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

两处澄清仅使 FR 描述与代码事实一致，**不影响**设计稿 §2 范围与 §10 验收结论。
