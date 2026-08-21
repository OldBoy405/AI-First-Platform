---
id: CR-2026-050-prd
type: PRD
cr-ref: CR-2026-050
title: Pipeline 流程优化 — 职责边界与契约漂移修复（先正确性后职责收敛，P0/P1/P2 单 CR）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-21T10:11:57+08:00
updated: 2026-08-21T10:32:27+08:00
---

# 1. 概述

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

# 2. 已解决基础设施与保留契约

## 2.1 已解决基础设施（只复用，不重做）

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

## 2.2 Pipeline 中应保留什么（§17）

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

# 3. 用户故事

- **US-01 Pipeline 维护者**：希望节点 prompt 只表达「调用哪个 Skill、传什么、按什么 reviewLoop 重放、失败去哪」，Skill/crctl 内部变化不需要同步修改多份算法文本。
- **US-02 CR 执行者**：希望人工审批只提交 approve/reject 决定及理由，不再被引导去直接编辑受保护评审账本，避免绕过 CAS 与审计边界。
- **US-03 规划流程使用者**：希望 product-planning / market-to-plan / competitive-radar 按 Skill 声明的必填输入闭环，不因缺 `topic`、`context/intent`、`updates-block/product-snapshot` 而运行失败或无法落盘。
- **US-04 竞品雷达使用者**：希望草稿（confirmed=false）与正式报告（confirmed=true）的顺序闭环可执行，不出现「草稿未落盘却要求 reportPath」的矛盾。
- **US-05 Tools 维护者**：希望审批/评审/测试/freshness 节点把算法交回 Skill 与 `crctl`，下一步统一「以 `crctl next {cr_id}` 为准」，不写死下一条 pipeline 名。
- **US-06 评审者**：希望技术设计新增的术语硬化、REST 契约基线与关键决策记录以收窄后范围进入 Skill 与评审维度，不新增评审节点或独立 ADR 文件。

# 4. 功能需求

## FR-01（P0）三条 CR Pipeline 人工审批不再直接修改受保护评审账本

涉及 `requirement-authoring`（`review-annotations/requirement.yml`）、`architecture-design`（`review-annotations/sdd.yml`）、`code-implementation`（`review-annotations/code.yml`）的 human approval 节点。

1. 删除「在 review-annotations/*.yml 补充 reject_reason」等直接修改受保护账本的指引；`review-annotations/*.yml` 在 `controlled-shell/rules.json#protectedPaths.deny` 中，由 `crctl review-record` / `crctl approve` 独占写入。
2. 改为：人工只提交 `approve/reject` 决定及理由；理由通过 `approve-*` Skill 的 reject 流程记录并回退（需求→`drafting`/重写 PRD、架构→`tech-designing`、代码→`developing`）。
3. 审批证据、CAS、审计和状态回退均由 `crctl approve` 完成；人工决定只进入 `approve-*` 的受控流程。

## FR-02（P0）product-planning 输入契约修复

文件 `product-planning.pipeline.json`。

1. `analyze-user-feedback`、`conduct-market-research`、`analyze-current-product` 至少传 `topic: {{inputs.topic}}`（Skill 必填参数），并保留各自 skip 标志。
2. `write-competitive-report` 补齐 Skill 必填输入：`updates-block`、`product-snapshot`、`confirmed`；明确 Pipeline 如何取得 `fetch-competitor-updates` 输出与 `gather-product-context` 快照，或让现有 Skill 自行调用已存在的上下文能力；不得让一个节点同时「假装拥有」两个 Skill 的输入和业务逻辑。
3. `write-planning-report` 明确传 `prev_outputs`、`review_feedback`、`self_repair_attempt`，使 reviewLoop 回修可可靠消费 blocker；报告章节、文件名与 `_index.yml` 由 Skill 负责。
4. `review-planning-report` 只传报告路径、reviewer、topic、target version、feedback 和 attempt，消费 `approved/blockers/repair-target/current-attempt`；评审维度、annotation 路径、`_index.yml` 状态更新和轮次持久化由 Skill 负责（规划类无 CR 上下文，本地评审记录仍由 Skill 持久化，不引入 `crctl review-loop`）。
5. `write-roadmap` 传 `topic`、`target_version`、`planning_report_path`；删除「同步更新规划报告 `_index.yml` 为 approved」的跨文档写入（该写入不在 `write-roadmap` 契约中，优先删除）。
6. product-planning 的 human approval 只收集结构化 `approve/reject + reason`，删除「在报告末尾补 reject_reason」；驳回中止当前正向链，需修订时按既有 reviewLoop 或正常 Pipeline 重跑，不迁移到 CR `approve-*`/`crctl approve` 机制。

## FR-03（P0）market-to-plan 必填参数与跨文档写入修复

文件 `market-to-plan.pipeline.json`。

1. `planning-draft` 补齐 Skill 必填输入 `context` 与 `intent`；若当前 Pipeline 无法提供产品上下文，先明确复用已有 `gather-product-context`，不得用未声明的「简报」替代 `context`。
2. `extract-market-insight` 的简报调用为 Skill 增加最小显式输入（如 `mode=brief`、`raw_insight_path`），Pipeline 只传这两个业务参数；brief 正文、路径和 index 状态由 Skill 负责，不得在 Pipeline 用 `source` 伪造 Skill 参数。
3. `write-planning-entry` 删除对 `docs/market-insights/_index.yml` 生命周期状态 `published` 的跨文档写入（不在该 Skill 参数与写入契约中，保守默认删除，待真实需求证明再单独设计）。

## FR-04（P0）competitive-radar 草稿/落盘顺序闭环

文件 `competitive-radar.pipeline.json`。

1. node-1 做显式参数映射或统一 Skill 参数名：`competitor_slug → competitor-id/competitor-ids[]`、`since_days → lookback-days`；`slug` 与竞品 ID 不等价时先按现有竞品索引解析，不得让 prompt 自行猜测。
2. node-2 `write-competitive-report` 补齐必填 `updates-block`、`product-snapshot`、`confirmed`；报告固定章节、路径、竞品主文件 updates、reports index 与两阶段落盘规则由 Skill 负责。
3. node-3 `report-to-planning-suggestion` 支持 `reportPath` 与 `reportDraft` 二选一；两者同时存在时优先 `reportPath`。`reportDraft` 最少包含草稿正文、`competitorId`、`reportDate`、来源节点/来源标识；草稿模式只消费输入生成规划建议，不落盘竞品报告，且不得把 node-2 草稿伪装成 `reportPath`。
4. node-5 在人工确认通过后，继续传递 node-2 的 `updates-block`、`product-snapshot` 与 `confirmed=true` 所需结构化上下文，并顺序调用两个已有 Skill：先 `write-competitive-report(confirmed=true)` 落盘正式报告，再 `write-planning-entry(source=node-3.md)` 落盘规划条目；若单个 node 不允许顺序调用多个 Skill，在现有运行时编排能力中显式支持，不新增业务 Skill或事务层，也不在 `write-planning-entry` prompt 中复制报告落盘算法。

## FR-05（阶段一 / P1）审批节点收敛

涉及 `approve-requirement`、`approve-tech-design`、`approve-dev-start`、`approve-code` 四个节点。

1. 删除 `crctl approve --stage ...` 命令细节、TTY 审批路径、`approval.yml`、grant/CAS/状态级联、reject 结果码等由 Skill 与 `crctl approve` 承担的实现。
2. 只保留：读取 execution_context，调用对应 `approve-*`，传入 `cr_id`（完整形态，不得遗漏）与 `approver`（取自 `execution_context.owners.*.id`），消费审批记录、当前状态和结构化结果；失败按 Skill 语义 abort。
3. 下一步统一以 `crctl next {cr_id}` 为准，不得写死下一条 Pipeline/Skill。

## FR-06（P1）评审与测试节点收敛

涉及 `review-requirement`、`review-tech-design`、`review-dev-plan`、`write-test-report`、`review-code` 五个节点。

1. 删除评审业务维度正文、临时 review payload、`crctl review-record` 调用方式、canonical annotation 写入、review-loop/traceability 写入、blocker 回修算法。
2. 保留机器可读 `reviewLoop`、`replayNodes`、`passCondition`、`maxAttempts`，以及对 `verdict/blockers/repair-target/current-attempt` 的消费和路由。
3. `review-tech-design` 把术语硬化、REST 契约基线、关键决策记录要求补回 Skill 评审维度（见 FR-08.4），不新增评审节点。
4. `write-test-report` 删除 `cr-test-plan/v1` schema、executable/args/timeout 白名单、`crctl test` 命令、test-report 机器区与 marker、traceability/review-loop 原子更新、status=block 证据语义；Pipeline 只传 `cr_id`、`source_node`、`tester`、`review_feedback`、`self_repair_attempt`，消费 `status`、`blockers`、报告路径。
5. `review-code` 删除 reviewer runner 选择、diff/log/merge-base 取证命令、test-report/traceability/test-evidence 证据规则、代码评审维度、blocker/suggestions 语义、回修重建算法；Pipeline 只传 CR-ID、workspace、resources、review feedback、attempt，消费 verdict/blockers/test-report.status/repair-target，并保留 `reviewLoop.replayNodes: implement → test-report → checkpoint → freshness → review-code`。

## FR-07（P1）输入、工作区与开发产物节点收敛

1. `write-tech-design` 以 `crctl workspace inspect` 返回的 `operationalWorkspace` 与 `resources[].worktreePath` 为唯一路径事实，删除自拼接 `.rayai-worktrees/{repo.id}/requirement/{cr_id}`、SDD 章节清单、术语/REST/决策业务规则、`crctl advance` 命令、Git 命令与 commit 算法、blocker 逐条修复算法；Skill 输入显式接受 `operational_workspace`、`resources`。
2. knowledge-base 的 `sdd.md` 与代码仓 `ARCHITECTURE.md` 属于同一轮技术设计，但不得声称处于同一 Git commit；只为本 CR 实际涉及且缺失该文档的代码仓起草，各仓在所属 `resources[].worktreePath` 分别提交，最终纳入同一批 checkpoint。
3. architecture-design node-5 `push-progress` 只传 `cr_id` 与阶段 message、消费结构化 `phase`；保留「架构阶段终点」「`phase=complete` 才成功」「checkpoint 失败只重跑同一 checkpoint、不重新审批」语义，删除 checkpoint 命令、workspace resolver、事务恢复和 Git 算法。
4. `requirement-register` 保留输入映射与结构化结果消费，删除完整 `crctl register` 参数序列、registration key 派生示例、绝对路径 execution context 示例、repo worktree 结构；路径值由 Skill/crctl 返回，Pipeline 不自行构造。
5. `write-requirement-prd` 删除 PRD 章节清单、主 workspace 禁写规则、具体落盘路径、blocker 逐条修复；Pipeline 只传 `cr_id`、`source`、review feedback、attempt 和运行时 context。
6. `implement-code` 删除 runtime fallback、PRD/SDD/TASK 读取清单、TASK 依赖/回修根因/验证算法；保留 execution context 与 `resources[].worktreePath` 传递、调用 `implement-code`、消费变更范围/runtime/session/验证结果、reviewLoop 回修输入。
7. `workspace-freshness`（实施前与评审前两个节点）删除 syncable 条件、freshness/sync 调用、continue/synced-continue/replay/manual 路由、逐仓失败处理；Pipeline 只传 `cr_id` 和 gate 名称，消费 route（`continue/synced-continue` 继续、`replay` 按现有 reviewLoop 重放、`manual` abort）。
8. `write-dev-plan` 删除 plan 章节、status 校验和输入文件算法；Pipeline 只传 `cr_id`、`target_version`、`review_feedback`、`self_repair_attempt`、`operational_workspace/resources`，消费结构化 plan 结果。
9. `write-dev-tasks` 删除 TASK 文件格式、接口签名规则、`crctl task init` 命令、estimate 交叉校验和索引失败算法；Pipeline 只传业务输入并消费 TASK 列表、估算与结构化结果。

## FR-08（P1）write-tech-design 三项新增能力收窄（§6）

1. **术语硬化**：仅处理会进入数据模型、状态机或接口契约，且存在一词多义/多词同义/代码别名、边界会影响 FR/AC/角色权限/验收语义的术语；每个被识别的风险术语至少用一个代表性边界场景验证；已有 `CONTEXT.md`/术语表先只读沿用，不新增跨 CR 长期术语资产；纯命名差异以 PRD 业务语义为权威记录 `PRD canonical term → 代码现有别名`，语义冲突不得由技术设计自行裁决（首次状态推进前停止、要求需求负责人澄清）；术语预检位于首次 `crctl advance` 之前，避免留下无 SDD、无评审记录的 `tech-designing` 状态。
2. **HTTP/REST 契约基线**：当 PRD、tech_context 或拟定技术方案表明本 CR 将新增或修改 HTTP API 时条件触发；优先级为目标仓 `ARCHITECTURE.md`/既有 OpenAPI/API 契约 → 现有客户端兼容性 → Skill 默认基线；默认基线可要求资源化 URL、方法语义、状态码语义、统一错误结构、分页策略、偏离说明、禁 HTTP 200 包装所有错误，但不强制复数资源名/kebab-case/固定 `error.code/message/details`/全列表分页/固定 400-422/全部 `201 + Location`；SDD 写接口概要/输入/输出/错误/鉴权与条件性幂等/分页约束，复杂或高风险接口附最小 OpenAPI 片段，不要求完整契约文件。
3. **关键决策记录**：三判据（难以逆转 / 无上下文会疑惑 / 存在真实权衡与替代方案）同时满足才记录；结构为 Decision/Context/Alternatives/Consequences；不伪造替代方案、不新增独立 ADR 文件或审批节点；改仓库级模块边界/依赖方向/硬不变量时按 `ARCHITECTURE.md` 维护规则处理。
4. **评审闭环同步**：`review-tech-design` 扩展现有维度（数据模型完整性：术语唯一且与已审批 PRD 语义一致；接口契约：按接口类型及目标仓既有规范应用条件基线；架构合理性：满足三判据的决策含真实 Alternatives 与 Consequences；多仓架构约束：按 `resources[].worktreePath` 读取相关仓 `ARCHITECTURE.md`），不新增评审节点。

## FR-09（P2）文档章节与落盘路径下沉

从 Pipeline prompt 删除以下由对应 Skill / `engineering-docs` / 版本化脚本负责的内容：

1. PRD/SDD/PLAN/TASK/规划报告固定章节；
2. 文件名和 slug 派生；
3. `_index.yml` 字段和排序规则；
4. review annotation 文件结构；
5. roadmap 幂等追加细节；
6. 竞品报告固定章节。

## FR-10（P2）展示节点收敛

1. `resume-cr` node-3 `cr-show` 删除 Pipeline 自行读取组织 `_backlog.yml`、`cr.md`、PRD/SDD/TASK/test-report/review annotations、最近三次 push-progress、`crctl next`、`crctl status`/`STATUS_DIVERGED` 的字段清单与账本定位规则；改为调用 `cr-show`（`cr-id`、`section: all`）并消费其结构化详情，下一步由 `cr-show` 内部调用 `crctl next` 计算；若「最近三次 checkpoint」是产品必需展示项，补入 `cr-show` Skill 输出契约而非只写在 Pipeline prompt。
2. requirement-authoring、architecture-design、code-implementation 中四个 CR `approve-*` 节点的输出统一消费对应 Skill 结构化结果，不写死下一 Pipeline；本条不适用于无 CR 上下文的规划类 human approval（其语义见 FR-02.6）。

## FR-11（P2）feature-writeback 一行级收敛

删除 node-1 的「校验 cr.md 当前 status=code-approved，否则 abort」预检（该校验已由 `merge-feature-branch` / `crctl merge` 承担）；Pipeline 保留失败中止即可。node-2 至 node-5 维持现状，无需重构。

## FR-12 保留契约与机器事实源边界

1. 每个 `kind=skill` 节点 prompt 收敛后最多保留 §2.2 五要素，不把 Pipeline 机器字段（reviewLoop/replayNodes/passCondition/onFail/timeout）搬回 Skill 文本，也不让 Skill 另写一份 reviewLoop 规则。
2. requirement-authoring 原样保留 `register → PRD → optional checkpoint → review → human approval → approve → checkpoint` 顺序、`auto_push_after_prd` 的 skip/execute 条件分支、reviewLoop 与 execution_context 节点间传递。
3. code-implementation 原样保留 `plan → TASK → review-dev-plan → human approval → developing`，以及 `implement → test-report → checkpoint → freshness → review-code` 顺序；reviewLoop 的 `replayNodes`、`passCondition`、`maxAttempts`、代码评审前已有 test-report、代码审批前经过 checkpoint 和人工审批均不得删改。
4. Pipeline 节点数量保持不变，除非 competitive-radar 的业务闭环无法在现有节点内表达（FR-04.4 的显式运行时编排支持）。
5. 改动 Pipeline 节点数量时同步 `pipeline-templates/_index.yml#nodes`；`node.ref` 必须是 active Skill；`human_approval` 不得替代状态写入。

## FR-13 范围边界与自检

1. 不新增：Pipeline 专用事务层、状态投影、第二套 review-loop 账本、第二套测试证据格式、candidate/manifest/merge/recovery 算法、通用 Runner 框架、事务日志、独立 ADR/跨 CR CONTEXT/术语中心。
2. 不改：状态机、gates、`crctl` 深原语（register/status/next/gate/advance/review-record/approve/test/task/checkpoint/merge/writeback/archive）、审批 grant、reviewLoop 业务语义、traceability evidence 结构。
3. 不把规划类本地 review annotations 强行迁移到 `crctl`；不把 README 扩展成可执行 Pipeline 事实源；不批量改写历史文档 schema。
4. 修改后在 tools 根目录运行：
   - `node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"`
   - `node skills/shared/crctl/scripts/lint-prompts.mjs`
   - `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`
5. 修改 Skill 时还须确定性检查：active ref 与 `skills/_index.yml`/`agent-skill-matrix.yml` 不漂移；写入型 Skill 调用 `validate-doc` 或等价校验；Git/shell 走 `controlled-shell`；CR 上下文摘要统一使用「以 `crctl next {cr_id}` 为准」；不直接写受保护账本；跨行解析/哈希先规范化 CRLF→LF，解析失败硬失败。

## 4.1 Source → FR → AC 追踪

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

# 5. 非功能需求

- **NFR-01 极简性**：净效果以删除重复合同为主；不新增框架、registry、数据库、通用解释器、事务层或 Pipeline 专用脚本。
- **NFR-02 单一事实源**：Pipeline 保留机器编排事实（node/ref/reviewLoop/replayNodes/passCondition/onFail/timeout），业务判断归 Skill，状态/账本/审批/测试证据归 `crctl` 与版本化脚本；职责边界与本 PRD §1 一致。
- **NFR-03 正确性优先**：阶段一 FR-01～FR-05 的输入契约、受保护路径与审批契约断言全部通过后再进入阶段二职责收敛；跨行解析、哈希等代码遵守 CRLF 规范化与「解析失败硬失败」纪律。
- **NFR-04 可验证性**：每项收敛均有确定性断言支撑——Pipeline JSON 可解析、`node.ref` 为 active Skill、必填输入映射存在、受保护账本手写指引为 0、下一步提示统一为 `crctl next`。
- **NFR-05 兼容性**：删除重复说明不得改变现有公开命令、合法人工审批、reviewLoop 与深原语结构化结果；不得改变 8 条 Pipeline 的可达状态与流程闭环。

# 6. 验收标准

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

# 7. 成功指标

- 8 条 Pipeline prompt 中受保护账本手写指引、评审/审批/测试/注册/freshness 算法副本降为 0。
- product-planning / market-to-plan / competitive-radar 三类规划流程按 Skill 必填输入契约可闭环，无「缺参导致运行失败」或「草稿未落盘却要求 reportPath」的矛盾。
- 四个 CR `approve-*` 节点下一步提示 100% 统一为「以 `crctl next {cr_id}` 为准」，无写死 pipeline 名；规划类审批保持自身结构化决定语义。
- 本 CR 净效果为删除重复合同，不新增生产依赖、公共命令、事务框架或长期接口。
- 状态机、gates、crctl 深原语保持原实现与回归测试，不被本 CR 重新设计。

# 8. 依赖与风险

- **依赖**：`docs/analysis/pipeline流程优化.md`（审计事实源，§14/15/16 清单）；`../tools/pipeline-templates/*.pipeline.json` 当前内容；对应 Skill 与 `crctl` 现行契约；`agent-skill-matrix.yml` 与 `pipeline-templates/_index.yml`。
- **风险 R-01 过度删除**：文本收缩可能删掉真实业务判断。处理：只删执行层算法副本，保留业务前置、输入输出、结构化结果分类与 reviewLoop；每个节点保留五要素。
- **风险 R-02 契约漂移再犯**：删除时若照抄旧文本会把漂移保留。处理：以 Skill 现行 SKILL.md 与 `crctl` 现行命令为唯一事实源核对，而非以旧 Pipeline prompt 为准。
- **风险 R-03 规划流程闭环破坏**：competitive-radar 草稿/落盘顺序改动可能破坏两阶段落盘。处理：node-3 支持 reportDraft 二选一，node-5 顺序调用两 Skill；若运行时不支持单节点顺序调用，先显式支持再落地，不新增业务 Skill。
- **风险 R-04 Pipeline 顺序回归**：删除/改动节点后 reviewLoop 或 checkpoint 顺序可能受影响。处理：验收以 `node.ref` 与 kind 顺序断言，不依赖旧数组下标；同步 `_index.yml#nodes`。
- **风险 R-05 术语/REST/决策收窄过宽或过窄**：处理：术语硬化仅覆盖进入模型/状态机/接口契约且有歧义/别名/边界风险者；REST 基线条件触发且仓库约定优先；决策记录三判据同时满足才落；评审维度同步但不新增节点。

# 9. 范围排除

- 不修改状态机、gates、`crctl` 深原语、审批 grant、reviewLoop 业务语义、traceability evidence 结构。
- 不新增 Pipeline 专用事务层/状态投影/第二套 review-loop 账本/测试证据格式/candidate-manifest-merge-recovery 算法/通用 Runner 框架。
- 不把规划类本地 review annotations 强行迁移到 `crctl`；不为每个 Pipeline 新建事务日志；不重实现 worktree/merge/checkpoint/archive。
- 不新增独立 ADR、跨 CR CONTEXT、术语中心或术语资产；不把 README 扩展成可执行 Pipeline 事实源。
- 不统一所有历史文档 schema；不批量改写历史 CR、历史 traceability、历史评审记录或 OpenWiki 历史快照。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；本 PRD 只落盘于 CR-2026-050 knowledge-base worktree。

# 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-21 | v0.1.1 | Ray | 首轮评审回修：修正两阶段边界，补齐 competitive-radar 草稿契约、跨仓 checkpoint、plan/TASK 收敛、规划审批、风险术语边界场景、流程保留与 Skill 自检 |
| 2026-08-21 | v0.1.0 | Ray | 初始草稿：基于 pipeline流程优化.md 审计落地，P0 正确性 + P1/P2 职责收敛，单 CR 两阶段 |
