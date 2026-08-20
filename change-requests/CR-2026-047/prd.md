---
id: CR-2026-047-prd
type: PRD
cr-ref: CR-2026-047
title: P3 组织智能 CR-A：AI 成熟度看板（E1 快照 + E2 看板 + E3 周报）
target-version: 0.21
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-20T00:19:52+08:00
updated: 2026-08-20T00:29:19+08:00
---

# PRD — P3 组织智能 CR-A：AI 成熟度看板

## 1. 概述

### 问题陈述

管理层需要回答两个问题：「AI 原生转型进行到哪了」与「交付系统有没有变好」。P0–P2 已把每一次任务执行（`task_usage`）、状态推进（`cr_sync_event`）、审批（`approval_record`）、reviewLoop（`pipeline_node_run.attempt`）、点踩（P2 反馈）、越权拦截（P1 §C.5）都落成了结构化行，但缺少一个把这些行聚合为可读视图的读侧。CR-A 交付该看板的第一个可用版本。

### 解决方案摘要

设计主线：**P3 不新增采集管道，只做已有事件的聚合与呈现**。CR-A 交付三个严格依赖的交付物（E1→E2→E3 一条线）：

- **E1 — 口径配置 + 快照数据管道**：`maturity-config.yaml`（落本仓）+ 配置生成器（照抄 `governance/gen/generate-transitions.mjs` 模式）+ `maturity_snapshot` 快照 rollup 任务（挂 `sys_cron_executions`）。
- **E2 — 看板前端**：趋势 / 排名 / 治理板块，5 维 8 项子指标，无个人榜，观察期（4 周）内无雷达图。
- **E3 — Org Admin Workspace 内置项目 + 周报 Autopilot**：平台自身的一个真实项目产出周报与建议（吃自己的狗粮），报告落盘不经 git，看板直接渲染。

只有 **1 张新表**落库（`maturity_snapshot`），其余全部读时聚合。快照表存在的唯一理由是**历史不可变**：口径（权重/阈值）会随季度改，而「当时那套口径下的分数」必须能重现——这是读时聚合做不到的唯一事情（不是查询性能、不是避免重算，日粒度量级下这两条都不成立）。

### 范围边界（注册阶段已拍板，本 PRD 原样采纳）

- 目标版本 0.21，开工前置无。
- CR-A 只含 E1/E2/E3；个人榜、资产复用率（第 9 项子指标）、交付效能板块、基线校准写入 config、待我审批端点均属 CR-D，不在本 CR。
- Skill Market（E6）属 CR-B；追溯查询 + 漂移检测（E4/E5）属 CR-C，均不在本 CR。
- 文档 §1.5/§1.6 描述的是目标态个人榜；本 CR 以更新的 §5.1/§5.2 重切表为准：排名仅支持 project，user 榜及其 Owner 开关整体推迟到 CR-D。

### 依赖与风险

- **既有能力依赖**：`task_usage` + `agent_task_queue.initiator_user_id`、`governance/gate_projection.go`、P1 D7 `activity_log`、`sys_cron_executions`、Team Agent/inbox，以及 `packages/views/dashboard/components/` 现成组件；CR-A 不重建这些能力。
- **CR 间依赖**：CR-A 开工前置无，内部依赖为 E1→E2→E3；CR-B/CR-C 与本 CR 无代码前置，CR-D 反向依赖 CR-A 上线满 4 周及 CR-B。
- **主要风险**：既有事件缺行会直接反映为指标缺失；必须通过快照完整率与治理板块暴露，不得新增采集旁路来掩盖。

## 2. 用户故事

| ID | 角色 | 行为 | 价值 |
|---|---|---|---|
| US-1 | 管理者 | 在一个看板看到组织 AI 采用的整体趋势、项目横向排序 | 判断「AI 原生转型进行到哪了」 |
| US-2 | 管理者 | 看到数量指标（如 Token 强度）与质量护栏（如门禁一次通过率）同屏成对呈现 | 避免「用得多」被误读为「用得好」 |
| US-3 | 管理者 | 每周自动收到一份诊断报告，且在看板上可读 | 不用手动拼数据即可获得趋势解读 |
| US-4 | 团队成员 | 在 Team Agent 里对周报内容追问（如「为什么 EPC 掉了？」） | 获得对话式解读而非只读报告 |
| US-5 | QA / Tech Lead | 在治理板块看到门禁一次通过率、证据漂移、追溯完整率、审批时延、越权尝试次数 | 定位质量与护栏问题 |
| US-6 | 平台管理员 | 口径（权重/阈值）版本化配置，且生成器 `--check` 能校验与 Go 副本无漂移 | 改口径走治理动作而非散落硬编码 |

## 3. 功能需求

### E1 — 口径配置 + 快照数据管道

- **FR-1** `maturity-config.yaml` 落**本仓**（knowledge-base），承载 5 维 8 项子指标的权重、阈值（`floor`/`target`）与观察期配置；权重与阈值集中于此，不硬编码。
- **FR-2** 配置生成器照抄 multica 已有先例 `governance/gen/generate-transitions.mjs`：读 yaml 声明 → 吐只读 Go 副本（文件头记源 commit SHA）→ 副本提交入库 → `--check` 模式在 CI/pre-commit 重生成并 diff，漂移则非零退出。
- **FR-3** `config_rev` = `maturity-config.yaml` 所在 commit 的 SHA（不手维版本号）。
- **FR-4** 新增 `maturity_snapshot` 表（DDL 见设计 §1.3）：`bucket_date DATE` + `scope TEXT CHECK IN ('org','user','project')` + `scope_id TEXT`（org 固定 `·`）+ `metrics JSONB` + `scores JSONB`（观察期内 `'{}'`）+ `config_rev TEXT` + `created_at TIMESTAMPTZ`，`PRIMARY KEY (bucket_date, scope, scope_id)`。
- **FR-5** 快照 rollup 任务挂 `sys_cron_executions`，每日 00:30 本地时区（`Asia/Shanghai`）跑前一天快照。JobSpec 照抄 `jobs_autopilot.go`：`Cadence: 0` + `PlansForScope`（固定 cron `30 0 * * *` 经现成 `service.NextOccurrencesUTC(expr, "Asia/Shanghai", after, now)` 求解）+ `CatchUpMode: CatchUpEveryPlan` + `MaxPlansPerTick: 7` + `CatchUpWindow: 7×24h` + `Scopes: StaticScopes(global)`。
- **FR-6** 水位线口径照抄 `rollup_task_usage_hourly()` 范本（`pg_try_advisory_xact_lock` + 有界窗口 + 单事务内 upsert 与水位推进同时提交）；水位 = `MAX(bucket_date)`，自带在表里，**不**复用上游 `task_usage_hourly_rollup_state` 状态表。
- **FR-7** 观察期内（§1.2）`scores` 不计算（落 `{}`），`metrics` 照常落库；历史快照不可变，口径变更只影响 `config_rev` 之后的新行，趋势图跨口径处标注断点。
- **FR-8** 一个任务内部遍历 org/user/project 三个 scope 写多行，**不**把 scope 展开成调度器级 Scope。

### E2 — 看板前端

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

### E3 — Org Admin Workspace 内置项目 + 周报 Autopilot

- **FR-19** 内置项目 **Org Admin Workspace**（对应快照里的 `org-admin-avatar` 内置 Agent）。
- **FR-20** 每周 Autopilot：读取最近的 `maturity_snapshot` 序列 + 治理板块异常 → 生成诊断报告落盘 `docs/org-admin/maturity-review-{YYYY-Www}.md`（Org Admin Workspace 项目工作区内的普通目录，**不经 git**）→ 经 inbox 通知 Owner。
- **FR-21** 诊断模板按 AI 净价值「四收益一成本」框架组织：个人效率 / 团队交付 / 知识复利 / 风险收益四节 + 成本一节，每节引用对应板块指标。
- **FR-22** 看板「建议」区直接渲染该目录最新文件；历史 = 目录内历史文件序列（免费获得原产品的 suggestions/history 能力）。
- **FR-23** 建议的生成过程走 Team Agent 消息流，可追问、可继续对话。
- **FR-24** 第 4 周周报内含自算的分位数基线建议（floor ≈ P10、target ≈ P75，**不自动写入 config**，提请人审）。

## 4. 非功能需求

- **NFR-1** 新迁移从 **375** 起；**禁新增 FOREIGN KEY**；每个索引必须 `CREATE INDEX CONCURRENTLY` 且一个迁移文件一条（multica `CLAUDE.md` 硬规则）。
- **NFR-2** 不新建任何事务/队列/outbox 抽象（仓内已有三套：crctl 文件 outbox + `cr_sync_event` 幂等账本、`webhook_delivery` 租约投递、`agent_task_queue` 的 `FOR UPDATE SKIP LOCKED`）。
- **NFR-3** 快照任务用 `CatchUpEveryPlan`（**不用 `CatchUpLatestOnly`**），服务器停 3 天后恢复须补全三天快照，不得永久缺行。
- **NFR-4** 构建 multica 永远不需要 checkout 本仓（生成器模式的关键收益，否则服务器多一个运行时跨仓文件依赖）。
- **NFR-5** 隐私与反 Goodhart：CR-A 不提供个人排名 UI、user 排名 API 或开启开关；Token 消耗是行为数据，不做个人考核依据。个人榜后续若由 CR-D 引入，开启动作必须对全员可见。
- **NFR-6** 日粒度，不做指标实时化。

## 5. 验收标准

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

## 6. 成功指标

- 首个 4 周观察期内应生成的日快照完整率为 **100%**；7 天窗口内的停机恢复后无永久缺桶。
- 前 4 周周报按计划生成率为 **100%（4/4）**，每份均可在看板读取并从 Team Agent 发起追问。
- 第 4 周周报产出 **1 份**基线建议，包含全部 8 项子指标的 floor≈P10 / target≈P75 建议，且配置零自动写入。
- 治理板块 **5 类指标全部可见**，且治理值变化不会改变成熟度总分。

## 7. 范围排除

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
