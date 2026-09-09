---
id: CR-2026-060-prd
type: PRD
cr-ref: CR-2026-060
title: CR 全生命周期合同对齐
target-version: "0.33"
owner: Ray
owner-role: requirement
status: ga
created: 2026-09-02T16:46:37+08:00
updated: 2026-09-02T18:30:37+08:00
spec-id: ai-first-platform
version: v0.33
cr-history: "[CR-2026-060]"
---

## CR 全生命周期合同对齐（v0.33 · CR-2026-060）

## 1. 概述

### 1.1 问题陈述

AI First 平台已经具备 `crctl` 状态机、门禁、CAS、受控 Git、事务、worktree、评审记录、测试证据、checkpoint、merge、writeback 和 archive 等基础能力，但各阶段的 Pipeline prompt、Skill 合同和消费端仍存在重复描述与字段漂移。重复合同会导致以下问题：

- 注册端、PRD/SDD/PLAN/TASK 生产端与回写消费端对目标版本、目标 spec、工作区和证据的理解不一致；
- Pipeline prompt 复制审批、评审、测试、账本和 Git 算法，修改一个入口时其他入口可能继续使用旧行为；
- writer 与 reviewer 的判断标准不对称，产品决策被延后到技术设计或编码阶段；
- PLAN、TASK、代码、测试报告和代码评审没有稳定地消费同一工作区与同一证据；
- writeback 在 `code-approved` 后仍可能重复做业务判断，或无法同时支持新注册 CR 与历史 legacy CR；
- product-planning、market-to-plan、competitive-radar 和 resume-cr 的输入映射存在已知缺参、草稿状态和展示字段矛盾。

### 1.2 目标

在一个 CR 内完成生命周期合同对齐：让生产端和消费端围绕已有 `crctl` 与版本化脚本共享最小、可验证的字段和职责边界，同时保持现有状态机、事务、审批、评审循环和回写机制不变。

本 CR 的目标版本为 `0.33`。本 CR 在新合同代码合入前已由旧版 register 注册，因此 `CR-2026-060` 本身属于兼容范围内的 legacy registration 形态；实现完成后必须能继续完成本 CR 的 PRD、SDD、PLAN/TASK、编码、测试、评审、回写和归档。

### 1.3 设计原则

1. 复用现有能力，不新建并行状态机、事务层、账本、Runner、协议版本或迁移器。
2. `cr.md` 是 CR 业务事实源；Pipeline 只传递最小运行时上下文；状态、审批、评审、测试证据和受控账本写入继续由 `crctl` 或既有版本化脚本负责。
3. 业务判断留在对应 Skill，确定性转换留在既有 generator，Pipeline 只负责节点顺序、输入传递、reviewLoop 和失败路由。
4. 对历史 CR 兼容读取；对新注册严格写入：新注册必须显式提供并持久化 `target-spec-id`，不得以缺字段代表 legacy。legacy 只表示在本 CR 代码合入前已经存在、且 `cr.md` 与对应 `_backlog.yml` 条目都缺少 `target-spec-id` 的历史 CR；不批量迁移历史产物。
5. 所有跨行解析、哈希和逐行解析先规范化 CRLF 为 LF；解析失败必须报错，不得静默降级为空结果。

### 1.4 主要影响面

| 领域 | 影响内容 |
|---|---|
| 注册与需求期 | `requirement-register`、`requirement-authoring`、PRD writer/reviewer、目标 spec/version 事实 |
| 架构与开发期 | SDD writer/reviewer、PLAN/TASK、workspace context、Coding、测试报告和代码评审 |
| 回写期 | merge、baseline/tasks/traceability generator、archive、legacy/new 双路径 |
| 规划与展示 | product-planning、market-to-plan、competitive-radar、resume-cr |
| 约束与索引 | tools 的 README、AGENTS、Skill/Agent 索引、Pipeline JSON、测试断言 |

源方案中的四个实施组分别对应注册事实、作者与 reviewer 标准、计划到代码证据、回写投影；规划类和展示类契约作为跨组的 Pipeline 输入对齐项一并验收。

## 2. 用户故事

- **US-01 工具维护者**：作为 tools 维护者，我希望 Pipeline prompt 只保留节点编排和结构化输入输出，以便 Skill 或 `crctl` 内部合同变更时不需要同步维护多份算法副本。
- **US-02 CR 执行者**：作为 CR 执行者，我希望注册后能从 `cr.md` 获得唯一的目标版本、目标 spec 和 owner 事实，并能在同一 CR worktree 中连续推进全部阶段。
- **US-03 需求作者与评审者**：作为需求作者或评审者，我希望产品输入、成功结果、权限、失败恢复、兼容范围和验收场景在需求阶段一次闭合，技术设计只补实现机制。
- **US-04 开发计划与测试负责人**：作为开发或测试负责人，我希望 PLAN、TASK、代码、测试报告和代码评审使用同一工作区、同一任务合同和可重算的源码/日志证据。
- **US-05 交付负责人**：作为交付负责人，我希望 `code-approved` 后的 merge、writeback 和 archive 只投影已冻结事实，并且新 CR 与历史 legacy CR 都能完成回写归档。
- **US-06 历史 CR 维护者**：作为历史 CR 维护者，我希望本次合同收敛不强制迁移旧 CR、不改变既有公开命令和状态路径，并能在兼容期继续处理旧字段。

## 3. 功能需求

### FR-01 注册合同与单一目标事实

#### 目标

新注册 CR 必须为后续阶段提供足够的目标事实，但不得把 execution context 变成 `cr.md` 的第二副本。

#### 要求

1. `requirement-authoring` 注册节点显式传递稳定的 `registration_key`、`title`、`summary`、可选 `source`、`target_version`、必填 `target_spec_id`、三角色 owner，以及可选 `origin`。`source` 只保存为安全 scalar，不在注册事务中解析业务文件路径。Pipeline 的 `target_spec_id` 与 `target_version` 为 required；Skill 与 CLI 同样 required。没有 `target_spec_id` 的新调用不得降级为 legacy。
2. 成功的 new registration 必须在 `cr.md` 与 `_backlog.yml` 同时保存同一个稳定小写 `target-spec-id`；该值匹配 `^[a-z0-9][a-z0-9._-]*$`，不得包含 `/`、`\\`、路径段或 CR/LF。读取时只有两处字段都存在且全等才判定 new mode；只有两处都缺失且 CR 在本次注册前已存在，才判定 legacy。单处存在、值不一致或非法均为 authority drift，硬失败且零写入。
3. `target_version` 在 Pipeline、Skill、CLI 三层均必填，允许真实 `MAJOR.MINOR[.PATCH]` 或 `unassigned`；输入可带 `v/V` 前缀时规范化为不带前缀的值。禁止 `tbd`、`pending`、`none` 等同义值。new mode 的 `unassigned` 只允许 CR 停在 `drafting`，不得进入 `requirement-reviewing`；必须先由 `crctl version-set {cr_id} --to <real-version>` 固化。`CR-2026-060` 的目标版本必须保持为 `0.33`，后续 PRD/SDD/PLAN/TASK 继承 `cr.md`，不得自行改写。
4. 三个 owner 必须分别写入 `id` 与 `assigned-at`；同一注册事务使用一个注册时间，账本、owner history 和 outbox 中对应时间一致。
5. `crctl register` 完成后必须由 register 事务的 workspace resolver 生产唯一公开字段 `operational_workspace`（snake_case，值为真实 knowledge-base CR worktree）；成功 JSON 顶层返回 `cr_id`、`operational_workspace`、`tx_id`、`changed`、注册 commit、`target_spec_id` 和恢复命令等注册结果。`requirement-register` 与 Pipeline 只能逐字透传该字段到 `execution_context.operational_workspace`，不得重新解析、拼接或另行生产路径；不得把长期可复用的 resources 快照作为第二事实源返回给后续节点。
6. 注册成功必须原子完成 knowledge-base 的 `cr.md`、`_backlog.yml`、`_index.yml` 写入、提交/发布和各 active repo 的 `requirement/{cr_id}` worktree ensure，初始状态为 `drafting`。
7. 同 `registration_key` 且包括 target spec/version 在内的规范化输入完全相同的调用必须幂等返回同一 CR；输入漂移必须零写入并返回 `REGISTRATION_INPUT_MISMATCH`。版本非法返回 `REGISTER_VERSION_INVALID`，target spec 缺失/非法分别返回 `REGISTER_TARGET_SPEC_ID_REQUIRED`/`REGISTER_TARGET_SPEC_ID_INVALID`，trunk 不干净返回 `REGISTRATION_TRUNK_DIRTY`，事务或 Git 问题按现有 recoverable 错误返回，不得手工补偿。
8. 注册失败的校验类错误必须在 candidate、journal 和账本写入前返回；事务中断有中间态时只允许重跑同一恢复命令。

### FR-02 PRD/SDD 作者与 reviewer 标准对齐

#### 目标

需求阶段关闭产品语义，技术设计阶段关闭实现协议；作者与 reviewer 对同一缺口必须有一致的阶段归属。

#### 要求

1. PRD writer 从 `cr.md` 读取 title、summary、source、target-version 和需求 owner；source 若指向文件，必须在 writer 阶段校验路径 containment 与存在性。PRD 不得从 Pipeline 传入的重复字段覆盖 `cr.md`。
2. PRD writer 与 requirement reviewer 共同检查以下七个产品维度：调用场景、业务输入、成功结果、权限与可见性、失败与恢复、兼容范围、场景化验收。安全、权限、数据损失、重复副作用、兼容性以及产品二选一不得延后。
3. 当改动涉及 HTTP API、`crctl`/CLI 或 Skill 可调用契约时，首轮评审必须一次闭合适用的契约域：
   - HTTP API：endpoint、request、response、error、权限、幂等、状态和验收观察点；
   - `crctl`/CLI：命令与 flags、输入约束、JSON/stdout、错误码、调用者约束、幂等、状态副作用和验收观察点；
   - Skill：必填参数、落盘路径、允许的状态转换、失败码及与 `crctl` 的唯一写入边界。
   不适用项必须显式记为 `N/A` 并说明原因。
4. 只有产品结果已经唯一、而 wire schema、精确错误结构、分页、锁、事务或幂等载体尚未决定时，才允许将其列为条件性 `SDD-CLOSE-*` 技术延后项。SDD 必须逐项关闭已有延后项；若 SDD 需要改变已批准的产品结果，必须回到需求阶段澄清。
5. `write-tech-design` 仅在影响数据模型、状态机或接口契约且存在歧义、别名或边界风险时硬化术语；每个风险术语至少用一个代表性边界场景验证，并优先沿用已有 `CONTEXT.md` 或仓库术语。语义冲突不得由 SDD 自行裁决。
6. 当 PRD 或技术上下文表明改动 HTTP API 时，SDD 按目标仓既有 `ARCHITECTURE.md`、OpenAPI 或 API 约定优先，补充资源 URL、方法语义、状态码、错误结构、分页、兼容性与条件性幂等约束；复杂或高风险接口提供最小 OpenAPI 片段，不强制新建完整契约文件。
7. 仅当决策难以逆转、无上下文会造成疑惑、且存在真实权衡与替代方案三个条件同时满足时，在 SDD 中记录 `Decision / Context / Alternatives / Consequences`；不新建独立 ADR 或跨 CR 术语资产。
8. review-requirement 与 review-tech-design 的 canonical 评审记录、轮次、traceability 投影和状态推进继续通过现有 Skill/`crctl` 完成；作者不得直接写受保护评审账本。

### FR-03 PLAN/TASK、Coding、测试与代码评审对齐

#### 目标

让计划、任务、实现和测试消费同一份阶段合同与可归因证据，不扩展动态回修引擎。

#### 要求

1. 架构、计划、实现和评审节点使用 `crctl workspace inspect` 返回的 `operationalWorkspace` 与 `resources[].worktreePath` 作为路径事实，不拼接固定的 `.rayai-worktrees` 路径或固定仓库名。knowledge-base 的 `sdd.md` 与各代码仓 `ARCHITECTURE.md` 分别在所属 worktree 修改和提交，再由 checkpoint 汇总。
2. PLAN 只保留两张稳定表：
   - 交付覆盖表：`FR/关键 AC | SDD 交付项 | 主责/关联 TASK | 验收证据 | 回滚（适用时）`；
   - 证据命令表：`证据 ID | repo | cwd | executable | args | timeout`。
   每个 in-scope FR 必须在交付覆盖表出现一次；验证命令单独编号，供测试报告稳定引用。
3. TASK 使用 PLAN 预分配的 ID，核验范围、依赖、接口和验收证据；`tasks/_index.yml` 的初始化、追加和 done 状态只通过 `crctl task init/append/done`，不得直接写账本。普通 dev-plan blocker 按既有 plan→tasks→review 路由，TASK-only 问题不得制造新的动态分支。
4. `implement-code` 只将 SDD、PLAN、TASK、目标仓规范和 `resources[].worktreePath` 作为实现依据，不把 PRD 作为并列实现合同。只有有变更或测试的 worktree 才需要 clean committed，其他 active repo 不得产生意外 diff。
5. `write-test-report` 必须执行 PLAN 证据命令目录的 canonical 门禁，并发布与当前代码关联的 `sourceRevision`、日志哈希和测试命令结果到既有 test-report/traceability 结构。业务测试失败按既有 `status=block` 证据语义记录；技术错误沿用现有非零退出语义。
6. `review-code` 对当前代码 HEAD、测试报告和日志重算既有证据；源码、日志或命令事实漂移必须阻断。review 输出固定包含 `verdict`、`blockers`、`suggestions`、`dimensions`、`repair-target`，不新增 aggregate evidence digest 或平行错误码族。
7. 代码评审不得重新执行测试；纯证据问题仍按 implement-code→test-report→review 回修，implement-code 在无代码变更时明确 no-op。实现、测试、评审和 checkpoint 使用同一 CR workspace。

### FR-04 回写成为确定性投影

#### 目标

`code-approved` 后只消费冻结事实，确定性生成 baseline、delivery、traceability 并归档，不在回写期重新做上游业务判断。

#### 要求

1. `feature-writeback` 保持现有五节点顺序。new mode 从 finalize 后 Transaction Workspace 的 `cr.md`、冻结的 PRD/SDD/PLAN/TASK、test-report 和 merge facts 读取 spec/version 等事实；外部 `spec_id`/`target_version` 可省略，若提供只能校验相等，不能覆盖 authority。new mode 不需要 `milestone_file`，由 traceability generator 从冻结 PLAN/TASK/test-report/merge facts 生成引用链；legacy mode 继续接受显式 spec/version/milestone 输入。
2. merge 继续负责 release-subject drift、跨仓 publication 和合并事务；writeback generator 消费冻结源生成 candidate、manifest 和既有校验结果，不新建事务或重复计算独立 digest。
3. baseline generator 从冻结 PRD/SDD 生成确定性 candidate；相同 CR 内容必须 noop，不同内容按现有 candidate/manifest 冲突语义处理。generator 不重新评估 PRD/SDD 业务质量。
4. TASK generator 在 candidate 前确认本 CR 全部源 TASK 为 done；任一 TASK 未完成必须零写入、零发布，不得只投影已完成子集。delivery 文件和索引中的状态必须与任务账本一致。
5. new mode 的 traceability generator 从 PLAN 交付覆盖表、TASK、test-report 和 merge-commits 生成 `FR → SDD → TASK → repo@mergeSHA → cmd` 引用链；只验证引用存在并投影冻结事实，不重新评价映射质量。legacy mode 继续使用显式 milestone 输入。
6. archive 只在 baseline、tasks、traceability 三段投影 complete，目标引用存在且没有 pending trace event 时成功；不重跑 generator、不手工补文件、不重新评审上游产物。
7. `review-alignment` 改为按需只读诊断：不进入 feature-writeback Pipeline、不推进状态、不写 traceability，不再使用失效的 mtime、backlog merge-commit 或 fingerprint 事实源。
8. 本 CR 及其他 legacy CR 均必须可完成 writeback/archive；不自动迁移历史 CR。

### FR-05 Pipeline、规划与审批输入契约对齐

#### 要求

1. 每个 `kind=skill` 节点的 prompt 只保留五类信息：调用哪个 Skill、传入哪些参数、依赖哪个前序结构化输出、消费哪些结果、失败如何 abort/skip/进入 reviewLoop。业务章节、文件命名、账本格式、算法和受控命令细节归属对应 Skill 或 `crctl`。
2. requirement-authoring 的 inputs 中 `registration_key`、`target_spec_id`、`target_version`、三个 owner、title、summary 为注册必填；source 与 origin 按表中 optional 处理。Pipeline 显式把 target spec 传给 requirement-register，并且只透传 register JSON 的 `cr_id + operational_workspace` 到后续节点。new mode 的需求评审固定顺序为：`crctl gate <cr> --for requirement-reviewing --mode pre-review`（仅版本守卫）→ `review-record` → `advance`；版本为 `unassigned` 时前置 guard 必须在任何 canonical 评审写入前失败，review 节点不得绕过 version-set。
3. requirement-authoring 保留 `register → PRD → optional checkpoint → review → human approval → approve → checkpoint` 顺序、`auto_push_after_prd` 分支、reviewLoop 和最小 execution context 传递。architecture-design、code-implementation 和 feature-writeback 的现有节点数量、合法状态顺序、checkpoint 前置和 reviewLoop/replayNodes 均不得被删除或重排。
4. 四个 CR `approve-*` 节点都传完整 `cr_id` 和对应 approver，消费结构化审批结果；不在 Pipeline prompt 中复制 TTY、grant、CAS、approval.yml、状态级联或 reject 回退算法。下一步统一提示为“以 `crctl next {cr_id}` 为准”。人工审批仍只能由人通过 `crctl approve` 完成。
5. product-planning 修复 Skill 必填输入：feedback、market research、current product 至少传 `topic`；竞品报告传 `updates-block`、`product-snapshot`、`confirmed`；规划报告传 `prev_outputs`、`review_feedback`、`self_repair_attempt`；roadmap 传 `topic`、`target_version`、`planning_report_path`，不跨文档修改规划报告索引。规划类 human approval 只收集结构化 `approve/reject + reason`，不迁移到 CR 审批机制。
6. market-to-plan 的 `planning-draft` 传 `context` 与 `intent`；brief 调用显式传 `mode=brief` 与 `raw_insight_path`；不得用 `source` 伪造 Skill 参数或由一个节点复制两个 Skill 的业务逻辑；`write-planning-entry` 不修改 market-insights 索引生命周期状态。
7. competitive-radar 统一 `competitor-id(s)` 与 `lookback-days` 输入；草稿建议支持 `reportPath` 与 `reportDraft` 二选一，同时存在时优先正式路径。`reportDraft` 必须包含草稿正文、competitorId、reportDate 和来源标识，草稿模式不伪装成已落盘报告。正式阶段按既有节点能力顺序调用 `write-competitive-report(confirmed=true)` 再调用 `write-planning-entry`。
8. resume-cr 的展示节点调用 `cr-show(cr-id, section: all)` 并消费其结构化详情；不在 Pipeline 自行复制 CR 详情字段清单。feature-writeback 的 merge 节点不再重复预检 `status=code-approved`，该校验由 merge/crctl 承担。
9. Pipeline `node.ref` 必须是 active Skill，节点数量与对应 `_index.yml` 一致；reviewLoop 的 `maxAttempts`、`replayNodes`、`passCondition` 和 checkpoint 顺序继续作为机器事实源。自动评审有 blocker 时必须回到对应修复节点，不能绕过评审进入人工审批。

### FR-06 兼容、变更组织与验证闭环

1. 实现按四个变更组组织：注册与 authority；PRD/SDD writer-reviewer；PLAN/TASK/Coding/test/review；writeback/archive 与 legacy compatibility。每组只修改必要调用方和测试，writer 与 reviewer、证据生产端与消费端必须成对更新。
2. 阶段一先完成注册/审批/评审输入等正确性合同，契约断言通过后再执行职责收敛；不得通过新增 CR 状态、Pipeline 节点、feature flag、contract-version 或迁移器解决兼容问题。
3. 所有受控写入继续经过既有 `crctl`/版本化脚本；不得直接写 `cr.md` status、`_backlog.yml`、approval、review annotations、review-loop、test-report machine zone 或 traceability 账本。
4. 生产端和消费端的新增字段必须有正向和负向验证：同键输入漂移、版本/spec 不一致、源码/日志漂移、TASK 未完成、非法路径和受保护文件写入均应在副作用发生前失败或按既有业务错误记录。

#### 3.1 模式、版本与交付数量的唯一裁决

本节是本 CR 实施和评审使用的唯一模式裁决，不允许 Pipeline、Skill、CLI 各自推断：

| 判据/约束 | new mode | legacy mode |
|---|---|---|
| 模式判定 | 成功的 `crctl register` 必须有 `target-spec-id`；读取时 `cr.md` 与 `_backlog.yml` 均有该字段且值一致 | 仅对本 CR 代码合入前已经存在、且两处均缺少 `target-spec-id` 的历史 CR 生效；不因本次调用缺参而进入 legacy |
| 注册入口 | `target_spec_id` 在 Pipeline input、`requirement-register` 参数、`crctl register --target-spec-id` 均必填；值为小写稳定 ID，禁止路径字符 | 不提供新的 legacy 注册入口；历史 CR 只读兼容 |
| 目标版本 | 注册三层均必填，允许真实 `MAJOR.MINOR[.PATCH]` 或 `unassigned`；`unassigned` 只能停在 `drafting` | 沿用历史 `cr.md`/backlog 值和旧消费方式，不批量补写 |
| 需求评审前版本门禁 | `crctl gate <cr> --for requirement-reviewing --mode pre-review` 只校验 mode/authority/真实版本，禁止检查 requirement passCondition；成功后才允许 `review-record`，PASS record 后由 `advance` 执行完整状态门禁 | 不因缺 `target-spec-id` 新增该 pre-review guard；仍受既有版本格式校验 |
| writeback authority | `spec_id`、`target_version` 从 finalize 后 Transaction Workspace 的 `cr.md` 读取；调用方若重复传值只作相等校验；不需要 milestone 输入 | `spec_id`、`target_version` 显式必填；traceability 的 `milestone_file` 显式必填 |
| 交付任务数 | 本 CR 恰好四个 TASK，且 TASK-1/2/3/4 与四个变更组一一对应；Pipeline 节点、验证命令和提交数量不计为 TASK | N/A |

若 new mode 只存在一处 `target-spec-id`、两处值不一致或值非法，按 `TARGET_SPEC_AUTHORITY_DRIFT` 硬失败并零写入，不猜模式。该判定不以 CR-ID 特判、不新增 `contract-version`、feature flag、迁移器或状态。

#### 3.2 CLI / `crctl` delta 合同矩阵

HTTP API：`N/A：本 CR 不新增或修改 HTTP endpoint、request、response、error 或 HTTP 权限契约`。本 CR 的可调用面只有 CLI 与 Skill；下表冻结受影响公共命令的调用者、输入、输出和副作用。所有命令均使用 `--workspace <path>`（未显式传入时沿用现有 cwd 探测）；成功 JSON 只写 stdout，失败以 exit 1 在 stderr 输出 `{error:{code,message,...}}`，失败不得输出成功对象。错误码沿用现有同名码；新增码只能按本表实现。

| 命令与调用者 | flags 与输入约束 | 成功 stdout JSON | 失败码与零副作用观察点 |
|---|---|---|---|
| `crctl register`；调用者=`requirement-register` | `--registration-key <k> --title <t> --owner-requirement <id> --owner-development <id> --owner-test <id> --target-version <real\|unassigned> --target-spec-id <id>`；可选 `--summary <s> --source <scalar> --origin <CR-ID> --year <Y> --workspace <ws>`。target-spec-id 匹配 `^[a-z0-9][a-z0-9._-]*$`；单行 scalar 拒绝 CR/LF；source 注册期不解析路径 | `{op:"register",cr_id,target_spec_id,operational_workspace,tx_id,phase:"complete",changed,target_version,side_effects,recover_command,outbox,warnings}`；`target_spec_id` 是账本 `target-spec-id` 的唯一 JSON 映射；`operational_workspace` 只能由 register 的 workspace resolver 生产，`requirement-register` 只将其原样放入 `execution_context.operational_workspace`；side_effects 明列三账本、commit/push、各 active repo worktree | 语法/未知 flag/其他基础必填缺失=`BAD_ARGS`；**缺失或空的 `--target-spec-id` 优先且唯一返回 `REGISTER_TARGET_SPEC_ID_REQUIRED`，不返回 `BAD_ARGS`**；非法=`REGISTER_TARGET_SPEC_ID_INVALID`；版本=`REGISTER_VERSION_INVALID`；漂移=`REGISTRATION_INPUT_MISMATCH`；脏 trunk=`REGISTRATION_TRUNK_DIRTY`。校验在 lock/journal/账本前完成；同键同输入 `changed=false`，无新 commit/outbox/worktree |
| `crctl gate <cr> --for requirement-reviewing --mode pre-review`；调用者=`review-requirement`、Pipeline 预检 | 只读且只用于 review-record 前；`--mode pre-review` 只读取 new/legacy mode 判据与 `cr.md.target-version`，**不得读取 PRD、requirement annotation 或 requirement review passCondition**；无 mode 的既有 gate 仍是完整目标状态门禁，只能在 review-record 后由 `advance` 等状态路径消费 | `{cr,for:"requirement-reviewing",mode:"pre-review",pass,checks:[{type,ok,why,...}]}` | new mode 且版本=`unassigned` 返回 exit 1，stderr 唯一错误信封为 `{error:{code:"GATE_BLOCKED",...}}`，check code 固定为 `TARGET_VERSION_UNASSIGNED`；new mode 的 target-spec authority 输入若缺失、非法、不一致，check code 分别固定为 `TARGET_SPEC_AUTHORITY_MISSING`、`TARGET_SPEC_AUTHORITY_INVALID`、`TARGET_SPEC_AUTHORITY_DRIFT`；legacy mode 两处均缺失时按 3.1 判定，不触发 target-spec 检查；target-version 缺失、非法、未固化的 check code 分别固定为 `TARGET_VERSION_MISSING`、`TARGET_VERSION_INVALID`、`TARGET_VERSION_UNASSIGNED`。上述每一类 guard 失败均使用同一外层 `GATE_BLOCKED`，不得改用其他外层错误码。guard 失败时不得产生临时 review payload、annotation、review-loop、traceability、status、outbox、journal 或 commit；真实版本在尚无 PASS annotation 时必须 `pass=true` |
| `crctl advance <cr> --to requirement-reviewing --trigger review-requirement`；调用者=`review-requirement` | `--workspace <wt>`；可带 `--expect drafting`；不得由 Pipeline 自行写 status | 成功 `{advanced:true,cr,from:"drafting",to:"requirement-reviewing",trigger,files:["change-requests/{cr}/cr.md"],commit}` | new mode `unassigned` 在写 `cr.md` 前返回 `GATE_BLOCKED`（含 `TARGET_VERSION_UNASSIGNED`）；状态/评审不变，无 status outbox、attempt 或 commit |
| `crctl version-set <cr> --to <real-version>`；调用者=`requirement-register`/`write-requirement-prd` 的编排或用户 | `--to` 只接受真实版本，禁止 `unassigned`、同义词和畸形版本；只允许 `unassigned → real`；校验 cr.md、backlog 及已存在 PRD/SDD/PLAN/TASK 版本一致性 | 首次从 `unassigned` 转为真实版本成功 stdout `{op:"version-set",cr_id,from:"unassigned",to,changed:true,files,commit}`；当前已是同一真实版本且所有派生产物一致时幂等 stdout `{op:"version-set",cr_id,from,to,changed:false,files:[]}`，其中 `from` 与 `to` 均为该同一真实版本且不产生新 commit | 错误优先级固定为：缺 `--to`=`BAD_ARGS` → 值非法=`VERSION_SET_INVALID` → 非法 CR 状态=`VERSION_SET_STATE_INVALID` → tracked dirty=`VERSION_SET_WORKTREE_DIRTY` → authority/派生产物漂移=`VERSION_SET_DERIVED_DRIFT` → 若 `cr.md` 当前为 `unassigned` 则执行变更；若规范化后目标已是当前真实版本且所有派生产物一致则 `changed=false` 幂等；若当前已是其他真实版本则=`VERSION_SET_NOT_UNASSIGNED`。提交失败=`VERSION_SET_COMMIT_FAILED`/`VERSION_SET_COMMIT_ROLLBACK_FAILED`。失败无 ledger/write-set/commit/status/outbox；成功只改 cr.md、backlog 和已存在派生产物的 target-version，不改 status |
| `crctl writeback-apply <cr> --stage baseline|tasks|traceability`；调用者=三个 writeback Skill | new：`--spec-id`、`--target-version` 可省略，省略即从 txws authority 读取；若提供必须与 authority 全等；`milestone-name/brief/milestone-file` 为 N/A，传入即 `BAD_ARGS`。legacy：spec/version 必填，traceability 还须 workspace-relative POSIX `--milestone-file`；baseline 可选 milestone-name/brief，tasks 不接受 milestone 参数。三 stage 均拒绝 candidate/generator/manifest 路径 | `{op:"writeback-apply",cr,stage,phase:"complete",changed,mode,specId,targetVersion,status,commit,files,warnings,recover_command}`；相同冻结输入重复返回 `changed:false` | 参数形态=`BAD_ARGS`；new authority 缺失/不一致=`WRITEBACK_SPEC_REQUIRED`/`WRITEBACK_SPEC_MISMATCH`；版本缺失/非法/不一致/`unassigned`=`WRITEBACK_VERSION_INVALID`/`WRITEBACK_VERSION_MISMATCH`/`WRITEBACK_VERSION_UNASSIGNED`；旧 `WRITEBACK_MANIFEST_*`、`WRITEBACK_STATE_MISMATCH`、`MERGE_COMMITS_MISSING` 等按既有语义。版本、mode、path、source 读取和 manifest preflight 均在 candidate/journal 前完成；失败无 candidate/journal/账本/commit/push |
| `crctl archive <cr> [--spec-id <id>]`；调用者=`cr-archive` | new 可省 spec-id，从已完成 writeback authority 读取；legacy writing-back 必须显式 spec-id；rejected/withdrawn 沿用可选语义 | `{op:"archive",cr,phase,status,changed,commit,lastCleanupError,remaining,preservedRefs,recover_command,warnings}` | `ARCHIVE_SPEC_REQUIRED`、`ARCHIVE_TRACEABILITY_MISSING`、`ARCHIVE_TASKS_PENDING`、`ARCHIVE_TRACE_PENDING` 等既有码；不因 archive 重新选择 spec/version，不重放 generator；authority 发布前失败无 archive commit/cleanup |

`N/A` 表示该 mode 不存在该输入，不是由调用者猜默认值。`recover_command` 只由 `crctl` 生成，事务中间态只重跑该命令；模型、Pipeline 和 Skill 不拼接 recovery/Git/ledger 算法。

本表冻结跨载体字段名，禁止生产端和消费端自行别名：CLI flag=`--target-spec-id`；`cr.md`/`_backlog.yml` 账本键=`target-spec-id`；register 成功 JSON 键=`target_spec_id`；Pipeline execution context 键=`operational_workspace`（不使用 `operationalWorkspace` 或其他别名）；register 结构化 CR 标识统一为 `cr_id`。register 的所有公开 JSON 键（包括 `tx_id`、`target_version`、`side_effects`、`recover_command`）必须使用 snake_case；旧版返回别名只可作为迁移期非消费兼容字段，后续节点不得读取任何旧版别名。`operational_workspace` 的唯一生产者是 register 的 workspace resolver；后续节点只能消费 register 返回的原值。

#### 3.3 Skill delta 合同矩阵

所有写入型 Skill 必须把判断或业务源写入非受控临时位置，再调用既有 `crctl`/版本化脚本；不得直接写 status、backlog、review annotation、review-loop、test machine zone、traceability 或 task index。下表的“状态”是允许读取/推进的状态，不代表 Skill 可自行改状态。

| Skill | required / optional 参数 | 结构化输出与落盘 | 合法状态/失败路由 | 唯一写入边界 |
|---|---|---|---|---|
| `requirement-register` | required=`title,registration_key,requirement_owner,dev_owner,test_owner,target_version,target_spec_id`；optional=`summary,source,origin,year` | 返回 register JSON；`cr.md`、`_backlog.yml`、`_index.yml` 和 worktree ensure 由 register 落盘；不解析 source 路径 | 注册前置 `(new)`，成功=`drafting`；校验失败 abort；中断只重跑 recover_command | 只调用一次 `crctl register`，不写账本/Git |
| `write-requirement-prd` | required=`cr_id`；optional=`source,review_feedback,self_repair_attempt`；runtime context 只读 | 输出 PRD 摘要和 `change-requests/{cr_id}/prd.md`；title/summary/source/target-version/owner 从 cr.md 读取 | 只在 `drafting`；review feedback 回修后仍 drafting；缺文件/版本未固化按 `PRD_*` abort | 只写 PRD 正文/frontmatter和经 `crctl backlog-set` 的 prd-path，不写 status |
| `review-requirement` | required=`cr_id`；optional=`reviewer,self_repair_attempt,review_feedback` | **固定顺序**：先运行 `gate --for requirement-reviewing --mode pre-review`，通过后才写临时 `.crctl/tmp/review-requirement.yml`；随后 `review-record` 产生 canonical=`review-annotations/requirement.yml`，并由 crctl 投影 review-loop/traceability | `drafting`/兼容重审；pre-review guard pass → review-record；record=pass 后才 `advance` 消费完整 passCondition 并到 `requirement-reviewing`；guard block 时 route=`version-set` 且不记录评审，record=block 时 route=`write-requirement-prd`；`SCHEMA_INVALID`/`GATE_BLOCKED` abort | 判断由 Skill 产出，annotation/attempt/trace/status 仅经 `crctl review-record`/`advance` |
| `write-tech-design` / `review-tech-design` | writer required=`cr_id,operational_workspace,resources`；tech_context/review feedback/attempt optional；reviewer required 同前两路径 | writer=`sdd.md`；reviewer 临时 payload→`review-annotations/sdd.yml`、review-loop、traceability | writer 读取 `requirement-approved`；review 在 `tech-design-review-pending`；block 回 `tech-designing`，pass 保持评审待审批路径；缺资源为技术 abort | writer 只写 SDD；reviewer 只经 `crctl review-record` 和合法 advance |
| `write-dev-plan` / `write-dev-tasks` / `review-dev-plan` | plan required=`cr_id`，target_version optional且不得覆盖 cr.md；tasks required=`cr_id`，`task_count_hint` optional但本 CR 固定为 4；review required=`cr_id,workspace,resources`，feedback/attempt optional | plan=`plan.md`；tasks=`tasks/TASK-*.md` 后调用 `crctl task init`；review payload→`review-annotations/dev-plan.yml` | plan 读取已审批 SDD；tasks 进入 `task-breakdown`；本 CR 实际 TASK 数不是 4 或非一一对应即 `TASK_COUNT_MISMATCH` abort；review block 按既有 `write-dev-plan`/upstream 路由，pass 才可审批开发启动 | task index 只经 `crctl task init/append/done`；review 只经 `crctl review-record`/`advance` |
| `implement-code` / `write-test-report` / `review-code` | implement required=`cr_id,operational_workspace,resources`；runtime/feedback/attempt optional；test required=`cr_id`，source_node/tester/feedback/attempt optional；review required=`cr_id,workspace,resources`，reviewer/focus/feedback/attempt optional | code 写目标 repo worktree；test 通过 `crctl test --plan` 生成 `test-report.md` machine zone、`test-evidence/cmd-NN.log`、trace tests/review-loop；review payload→`review-annotations/code.yml` | implement 只在 `developing`；test 只在 `developing`；test block 回 implement；review block 回 implement，pass 才到 `code-reviewing` | code 只写 resources 指定 codeRoot；test machine/trace/review annotation/status 只经 crctl；review 不重跑测试 |
| `merge-feature-branch` | required=`cr_id`；workspace 由目标 workspace resolver 得到，不作为业务替代事实 | `crctl merge` 返回 `operational_workspace`、tx_id、phase、merge-commits/verification | 只消费 `code-approved`；release drift 按既有回退，事务中断重跑同命令 | merge/Git/status/merge facts 只经 `crctl merge` |
| `writeback-prd-sdd` / `writeback-tasks` / `writeback-traceability` | 三者 required=`cr_id`；new 的 spec/version optional且只能重复校验；legacy spec/version required；trace legacy 另 required=`milestone_file`，new 为 N/A；baseline 的 milestone-name/brief 仅 legacy optional | 各 Skill 只输出一次 `crctl writeback-apply` 的结构化结果；baseline→`specs/{spec}/PRD.md,SDD.md`，tasks→`delivery/task/*,_index.yaml`，trace→`specs/{spec}/traceability.yml` | merge 后 `writing-back`；任一业务源/引用/版本失败 abort；中断只重跑同一 writeback 命令；不引入 review 路由 | generator/candidate/manifest/journal/commit/push 和 status 只经 `crctl writeback-apply` |
| `cr-archive` | required=`cr_id`；new writing-back 的 spec_id optional，legacy writing-back required；终止态沿用 optional | 输出 archive JSON；四账本和 cleanup 由 `crctl archive` 完成 | `writing-back` 完整投影后=`archived`；pending 只续跑 recover_command；不重新评审 | 只调用一次 `crctl archive`，不手工清理或写账本 |

#### 3.3.1 审批、规划消费与只读诊断的补充合同

本表覆盖 FR-05 明确修改的剩余消费面。`N/A` 只表示本 CR 对该 Skill 的**内部参数或持久化格式没有 delta**，不表示 Pipeline 可省略参数；参数定义仍以所指 `SKILL.md` 为准。规划类 Pipeline 的 human approval 只消费结构化 `approve|reject + reason`，不写 CR status、approval、review-loop 或 traceability，也不调用 `crctl approve`。

| Skill / 适用映射 | required / optional 参数 | 结构化输出与落盘 | 状态 / 失败路由 | `crctl` 边界 |
|---|---|---|---|---|
| `approve-requirement` | required=`cr_id`；optional=`approver,notes`，缺 approver 取 `owners.requirement.id` | 只消费并返回 `crctl approve --stage requirement` 的结构化审批结果；approval.yml#requirement 仅由 crctl 写入 | 仅 `requirement-reviewing`；PASS 到 `requirement-approved`；reject 回 `drafting` 并中止正向链；无 grant 的非 TTY=`APPROVAL_REQUIRES_HUMAN`，证据不通过=`GATE_BLOCKED` | Skill/Pipeline 不写 approval/status/reject；仅 crctl 的签名 grant 或交互人类审批可写 |
| `approve-tech-design` | required=`cr_id`；optional=`approver,notes`，缺 approver 取 `owners.development.id` | 只消费并返回 `crctl approve --stage tech-design` 结果；approval.yml#tech-design 仅由 crctl 写入 | 仅 `tech-design-review-pending`；PASS 到 `tech-design-reviewed`；reject 回 `tech-designing`；证据/签名/状态失败 abort | 同上；Pipeline 只传完整 cr_id 与 approver，不复制 TTY/grant/CAS/回退算法 |
| `approve-dev-start` | required=`cr_id`；optional=`approver`，缺 approver 取 `owners.development.id`；`notes=N/A`（既有 Skill 无此入参） | 只消费并返回 `crctl approve --stage dev-start` 结果；approval.yml#development-start 仅由 crctl 写入 | 仅 `task-breakdown`；PASS 到 `developing`；reject 回 `tech-design-reviewed`；plan/tasks/dev-plan passCondition 不满足=`GATE_BLOCKED`，技术校验失败 abort | 同上；任务账本不因审批由 Pipeline 或 Skill 写入 |
| `approve-code` | required=`cr_id`；optional=`approver,notes`，缺 approver 取 `owners.development.id` | 只消费并返回 `crctl approve --stage code` 结果；approval.yml#code 仅由 crctl 写入 | 仅 `code-reviewing`；PASS 到 `code-approved`；reject 回 `developing`；review 证据不通过=`GATE_BLOCKED`，技术失败 abort | 同上；可选 suggestion 转 planning 记录不阻塞审批，且不进入 writeback |
| product-planning：`analyze-user-feedback`、`conduct-market-research`、`analyze-current-product`、`write-planning-report`、`review-planning-report`、`write-roadmap` | 三个基础分析入口均 required=`topic`；报告 required=`topic`，optional=`target_version,prev_outputs,review_feedback,self_repair_attempt`；评审/roadmap 按既有 `SKILL.md` 参数 | 分析输出 node 结构化结果；报告落盘 `docs/product-planning/...`；review 输出 `approved/blockers/...`；roadmap 落盘既有 roadmap。除 Pipeline 映射外，其他内部格式=N/A | 无 CR 状态；skip 仅产出 `SKIPPED`；报告/评审失败 abort 或按既有 reviewLoop 回报告 writer；人类 reject 中止本规划正向链 | `crctl=N/A`：规划产物不使用 CR 受控账本；不得把规划审批改接 `crctl approve` |
| market-to-plan：`extract-market-insight`、`planning-draft`、`write-planning-entry` | extract 首次 required=`insight_source`，brief required=`mode:brief,raw_insight_path`；planning-draft required=`context,intent`，target_version=N/A（非既有参数）；entry 按既有 `source,title,target_version,owner` | extract 落盘 raw/brief 既有洞察文档；planning-draft 仅输出草稿、不落盘；entry 落盘规划条目，且不改 market-insights 索引生命周期 | 无 CR 状态；任一 required 输入/源文档不成立 abort；人类 reject 中止本链 | `crctl=N/A`；不得用 `source` 冒充 planning-draft 参数或手写账本 |
| competitive-radar：`fetch-competitor-updates`、`write-competitive-report`、`report-to-planning-suggestion`、`write-planning-entry` | fetch 接收统一 `competitor-id(s),lookback-days`；report required=`updates-block,product-snapshot,confirmed`；suggestion 的 `reportPath` 与 `reportDraft` 二选一，双传优先 reportPath；entry 按既有参数 | `confirmed=false` 输出未落盘 `reportDraft{body,competitorId,reportDate,sourceNodeId,sourceRef}`；`confirmed=true` 落盘正式报告；suggestion 只输出草稿；entry 落盘规划条目 | 无 CR 状态；草稿字段不完整、双输入皆缺、报告路径越界或上游失败 abort；人类 reject 中止本链 | `crctl=N/A`；不得把草稿伪装为正式报告，或把该审批迁移为 CR approval |
| resume-cr：`list-remote-checkpoints`、`resume-from-remote`、`cr-show` | 三者 required=`cr_id`；`cr-show` optional=`section`，resume 仅接受既有 workspace 上下文 | checkpoint 输出 batch/resources 分类；resume 输出 resources/owners/next；cr-show 输出 section=all 的结构化详情与 `crctl next` 结果；均不直接落盘业务事实 | 无自主状态推进；缺 checkpoint、workspace ensure 或 show 失败 abort，保留现场；下一步只由 crctl next 给出 | list/resume 只调用既有 `crctl workspace` 原语；cr-show 只读并调用 `crctl next`，不得重建 status 映射 |
| `review-alignment` | required=`cr_id`；optional=`spec_id,strict`；不存在 Pipeline 入参映射改动时 Skill 参数 delta=`N/A`，仍引用既有参数表 | 输出 `{skill,cr_id,spec_id,current-status,result,drifts,summary}`；**不落盘**，不追加 traceability/drift 或 summary.stale | 任意状态按需调用；结果为 `pass|drift-detected`，只供调用者诊断，不阻断审批、merge、writeback 或 archive | 严格只读；不调用 advance/review-record/approve，不写状态、annotation、review-loop、traceability、账本或 Git；不得读取 mtime、backlog merge-commit 或 fingerprint 作为事实 |

上述 Skill 输出的 `下一步` 均只写“以 `crctl next {cr_id}` 为准”，不复制 status→节点映射表。

#### 3.4 四个 TASK 的一一对应与交付约束

来源方案明确要求“一个 CR、四个 TASK”。本 CR 只允许且必须创建以下四个交付 TASK，不能把 Pipeline 节点、checkpoint、merge、writeback、archive 或纯验证命令另建为 TASK：

| TASK | 唯一变更组 | 交付边界 | 最小验收证据 |
|---|---|---|---|
| TASK-1 | 注册与 authority | target-spec/version authority、需求评审前 version gate、register/version-set/writeback CLI 入口及测试 | register/version-set/gate/writeback 的正反 CLI 信封和零副作用断言 |
| TASK-2 | PRD/SDD writer-reviewer | PRD/SDD 输入、作者/reviewer 七维标准、review payload/route 合同 | writer/reviewer 对称性、首轮契约闭包、合法状态路由测试 |
| TASK-3 | PLAN/TASK/Coding/test/review | 两张 PLAN 表、恰四 TASK、workspace/证据/回修合同 | task count/一一对应、cmd-NN、source/log drift 和 review route 测试 |
| TASK-4 | writeback/archive 与 legacy compatibility | new/legacy 解析、三个 writeback stage、archive 投影和兼容测试 | new/legacy 两条端到端夹具、TASK 未完成及外部输入漂移零写入测试 |

`write-dev-tasks` 必须在本 CR 的 plan.md 中为四个变更组各预分配一个 ID，`crctl task init` 后索引中恰有四个 `TASK-*.md` 条目；任何缺失、重复、第五个或跨组 TASK 均返回 `TASK_COUNT_MISMATCH`，不推进到开发启动。每个 TASK 必须在覆盖表中恰出现一次且有唯一 owner；四个 TASK 的完成状态均由 `crctl task done` 登记。

## 4. 非功能需求

- **NFR-01 单一事实源**：业务字段从 `cr.md` 或当前阶段冻结产物读取；Pipeline 只维护机器编排事实；状态、账本、审批、评审、测试、事务和审计继续由既有 `crctl`/generator 维护。
- **NFR-02 原子性与数据安全**：注册、评审记录、任务状态、测试证据和回写事务必须沿用现有 CAS、lease、candidate/journal、受保护路径和 recoverable 语义；任何校验失败不得留下部分账本或发布副作用。
- **NFR-03 可重复性**：同一输入和同一冻结源生成的 candidate、traceability 引用和审计结果应确定性一致；同键同输入注册和同内容回写必须幂等。
- **NFR-04 向后兼容**：不删除现有 `crctl` 命令、合法状态转换、审批 grant、reviewLoop 语义和历史 traceability evidence 结构；新增注册字段为严格必填；缺少 `target-spec-id` 的既有 CR 继续走 legacy mode。writeback 的新 mode 省略外部重复参数是向后兼容的新增分支，不改变 legacy 显式参数行为。
- **NFR-05 可移植性**：仓库、trunk、worktree 和路径均从目标 workspace `dir-graph.yaml` 解析；不引入本机绝对路径、固定仓库名或固定双仓假设。Node 运行时继续满足现有 `>=18` 要求。
- **NFR-06 安全与权限**：路径输入拒绝 CR/LF 和路径穿越；受保护评审账本不接受人工或 Pipeline 直接写入；人工审批不得由 Agent 代签。
- **NFR-07 质量验证**：Pipeline JSON 可解析，active Skill、Agent 索引和权限矩阵无漂移；跨行解析/哈希逻辑统一 CRLF→LF，匹配失败硬失败。

## 5. 验收标准

- **AC-01（FR-01）注册三层必填与幂等**：`requirement-authoring` input、`requirement-register` Skill 参数和 `crctl register` CLI 均拒绝缺失 `target_spec_id`；成功注册的 `cr.md` 与 `_backlog.yml` 均有相同 `target-spec-id`。同 registration key 同规范化输入重跑返回同一 `CR-ID`、`changed=false` 且不重复 commit/outbox/worktree；同 key 任一字段漂移返回 `REGISTRATION_INPUT_MISMATCH` 且 zero write；成功包含三账本、注册 commit、push 和全部 active repo worktree ensure 结果。
- **AC-02（FR-01）模式与目标事实**：`target-spec-id` 只接受稳定小写无路径字符串；两处字段缺一、非法或不一致时返回 `TARGET_SPEC_AUTHORITY_DRIFT` 且不写入。`CR-2026-060` 因注册时没有该字段明确标记为 legacy，不能被本 CR 实施自动补字段；new CR 的 `target-spec-id`、目标版本和三角色 owner 在 cr.md、backlog 与结构化消费结果中保持一致。
- **AC-03（FR-01/FR-05）版本门禁与评审顺序**：注册 `target_version` 三层必填；`unassigned` 的 new CR 可写 PRD 并只停在 `drafting`。`review-requirement` 必须先运行 `crctl gate <cr> --for requirement-reviewing --mode pre-review`：真实版本且尚无 PASS annotation 时 guard 返回 pass，随后才允许 `review-record`；new mode 的 `unassigned` 返回外层 `GATE_BLOCKED`、check code `TARGET_VERSION_UNASSIGNED`、exit 1，且临时 payload、cr.md、review annotation、review-loop、traceability、outbox、journal、commit 全部不变。PASS record 后由 `advance --to requirement-reviewing --trigger review-requirement` 运行完整 passCondition；不得在 review-record 前调用无 mode 的完整 gate。先执行 `crctl version-set <cr> --to <real-version>` 成功后，guard 才可继续。`version-set` 缺 `--to`/非法值/非法状态/dirty/authority drift 的错误优先级按 3.2 矩阵；version-set 首次从 `unassigned` 到真实版本时返回 `from:"unassigned"`、`to` 为请求真实版本、`changed=true`；当前真实版本与目标相同且派生产物一致时返回 `from` 与 `to` 均为该同一真实版本、`changed=false`、`files:[]` 且无新 commit；当前为其他真实版本时返回 `VERSION_SET_NOT_UNASSIGNED`；失败不产生 ledger/commit/status 副作用。注册结果同时包含 JSON `cr_id`、JSON `target_spec_id`、唯一生产的 `operational_workspace`、`tx_id`、`changed`、`commit`/`side_effects`/`recover_command`；后续 execution context 只能原样消费该字段，不拼接路径或持有 resources authority。
- **AC-04（FR-02）PRD authority**：PRD 的 title、summary、source、target-version 和 owner 来自 `cr.md`；source 路径的 containment/existence 在 writer 阶段校验；PRD 具备概述、用户故事、功能需求、非功能需求、验收标准、成功指标和范围排除七类章节。
- **AC-05（FR-02）作者/reviewer 对称**：PRD writer 与 requirement reviewer 对七项产品维度使用同一标准；涉及 HTTP、CLI 或 Skill 契约时首轮一次列出全部适用闭包项，不把权限、数据安全、幂等、兼容和产品结果缺口留作 suggestion。
- **AC-06（FR-02）技术闭合**：write-tech-design/review-tech-design 对已有 `SDD-CLOSE-*` 逐项关闭；风险术语有边界场景；HTTP 条件基线遵循目标仓规范；满足三判据的决策含 Alternatives 与 Consequences；SDD 不私自改变已批准产品结果。
- **AC-07（FR-03）工作区与计划**：plan、tasks、implement、test-report、review-code 使用 `workspace inspect` 的 operational workspace/resources；PLAN 恰有交付覆盖表和证据命令表；每个 in-scope FR 只出现一次且每条验证命令有稳定证据 ID。
- **AC-08（FR-03/FR-06）任务账本与数量**：本 CR 的 `plan.md` 明确且仅明确四个变更组的**恰好四个 TASK**；`write-dev-tasks` 传入本 CR 的 `task_count_hint=4` 并在生成/`crctl task init` 前后断言实际条目数恰为 4、四个 TASK 与四组一一对应。缺失、重复、第五个、跨组或流程控制 TASK 返回 `TASK_COUNT_MISMATCH`，不推进到开发启动；每个 TASK 的依赖、done 状态仍只能由 `crctl task init/append/done` 维护。
- **AC-09（FR-03）代码证据**：test-report 发布的 source revision、日志哈希和命令与当前实现对应；源码、日志或命令事实发生漂移时 review-code 返回 block；review-code 输出包含 `verdict/blockers/suggestions/dimensions/repair-target`，不新增 aggregate evidence digest。
- **AC-10（FR-03/FR-05）回修与审批顺序**：代码 review 的 evidence-only 回修仍经过 implement-code→test-report→checkpoint→freshness→review-code；所有自动评审 blocker 清空前不可进入 human approval；四个 CR approve 节点传完整 cr_id/approver，人工审批不由 Agent 代签，下一步均以 `crctl next` 为准。
- **AC-11（FR-04）new/legacy writeback 输入合同**：new mode 的 baseline/tasks/traceability 调用可不传 spec/version，三者均从 finalize 后 txws 的 cr.md 读取；显式重复值不一致在 candidate/journal 前返回 `WRITEBACK_SPEC_MISMATCH` 或 `WRITEBACK_VERSION_MISMATCH`，且 zero write；new traceability 传 milestone 参数返回 `BAD_ARGS`/N/A，不读取外部里程碑。legacy mode 的 spec/version 必填，traceability 的 milestone-file 必填，本 CR 作为 legacy registration 仍可完成 writeback/archive。
- **AC-12（FR-04）确定性投影**：相同冻结 PRD/SDD 内容重复生成 baseline 为 noop；任一 TASK 未 done 时 tasks writeback 零写入且不发布 done 子集；new traceability 可生成 `FR→SDD→TASK→repo@mergeSHA→cmd` 引用链。
- **AC-13（FR-04）归档边界**：archive 仅在 baseline/tasks/traceability 三段 complete、目标引用存在且无 pending trace event 时成功；writeback 不重新做业务评审；review-alignment 不在 Pipeline、不推进状态、不写 traceability。
- **AC-14（FR-05）规划输入闭环**：product-planning 的必填 topic/上下文/报告输入、market-to-plan 的 context/intent/brief 输入、competitive-radar 的草稿二选一和正式两步落盘均可由对应 Skill 契约消费；规划类审批不改用 CR approve 机制；resume-cr 展示使用 cr-show 结构化结果。
- **AC-15（FR-05）机器事实不漂移**：8 条 active Pipeline 的 JSON 可解析，节点数量与 `_index.yml` 一致，所有 node.ref 为 active Skill；requirement、architecture、coding、writeback 的现有顺序、reviewLoop、replayNodes、passCondition 和 checkpoint 前置均保留；Pipeline prompt 不再复制章节、账本、审批、测试、Git 或 generator 算法。
- **AC-16（FR-06/NFR）回归与边界**：以下检查通过：
  - `lint-prompts.mjs`、`check-skill-matrix.mjs`、`check-agents-contract.mjs`、`pipeline-structure.test.mjs`；
  - 注册、版本、测试、writeback、trace semantic、trace outbox、archive 相关现有测试；
  - register 缺 target spec、target spec 非法、单处字段/字段不一致、同键漂移、非法版本的负向测试；
  - new `unassigned` 的 gate/advance 拒绝和 `version-set` 正向/幂等/漂移/失败零副作用测试；
  - new writeback 省略或重复 spec/version、重复值漂移、legacy 缺参数、非法 milestone/path、candidate 前 zero-write 测试；
  - 源码/日志漂移、TASK 未完成和受保护文件写入的负向测试。
  所有失败均不得以手工修改受控账本或跳过 review/approval 代替修复；不适用的 HTTP API 契约在评审矩阵中显式标记 `N/A：本 CR 不新增或修改 HTTP API`。
- **AC-17（FR-06）交付组织**：四组变更完成并合入后，CR worktree 不遗留本 CR 未提交改动；`tasks/_index.yml` 恰有四个 TASK，四个 TASK 全部 `done`；未参与变更的 active repo 不产生意外 diff；不新增状态、Pipeline、事务框架、ledger、Runner、contract-version、feature flag 或历史迁移器。
- **AC-18（FR-04/FR-05）遗漏 Skill 与只读边界**：四个 `approve-*` 均按 3.3.1 的 required/optional、approval 段、合法成功/驳回状态、`GATE_BLOCKED`/技术 abort 路由和 crctl 独占写入执行；product-planning、market-to-plan、competitive-radar、resume-cr 的消费 Skill 均按矩阵传入必填/可选字段，输出和落盘不漂移，规划审批不改接 CR approve。`review-alignment` 的任意状态调用只返回结构化诊断，验证其不在 feature-writeback Pipeline、不调用 crctl 写命令、不写 traceability/status/annotation/review-loop/Git，且不读取 mtime、backlog merge-commit 或 fingerprint。

## 6. 成功指标

1. 8 条 active Pipeline 中受保护账本手写指引、审批/评审/测试/注册/freshness 算法副本降为 0。
2. 需求、架构、计划、编码、测试和回写节点对 `cr_id`、operational workspace、target version、任务和证据的生产/消费字段可由结构化断言验证，无缺参导致的运行时失败。
3. 四个 CR approve 节点 100% 传递完整 `cr_id` 与 approver，且下一步提示统一使用 `crctl next`；规划类审批保持结构化 approve/reject 语义。
4. 同一冻结输入的 register/writeback 重跑无重复副作用；new mode 与 legacy mode 均能完成完整生命周期。
5. 测试后源码或日志变化能够在代码评审阶段稳定阻断；TASK 未全部 done 时 writeback 不产生部分交付。
6. 本 CR 的净效果是删除重复合同、补齐缺失字段和确定性消费，不新增并行状态、事务、账本或长期协议资产。

## 7. 依赖、风险与范围排除

### 7.1 依赖与风险

- **依赖**：附件《CR全生命周期合同对齐-需CR实施方案》；目标 workspace `dir-graph.yaml`；tools 的 active Skill/Agent 索引、8 条 Pipeline JSON、`crctl`、gates 和既有测试。
- **R-01 过度删除真实业务判断**：收敛 Pipeline 时只删除算法和固定文档格式，保留业务输入、结构化输出、失败分类与 reviewLoop；writer/reviewer 的七项产品标准必须成对维护。
- **R-02 新旧合同兼容破坏**：本 CR 由旧 register 创建，必须用 `target-spec-id` 是否存在识别 new/legacy mode；不通过迁移历史文件或 CR-ID 特判解决兼容。
- **R-03 证据漂移漏检**：测试报告和 review-code 必须绑定 source revision 与日志事实，并在评审前重算；不依赖共享实例或无法归因的命令输出。
- **R-04 规划流程顺序破坏**：competitive-radar 草稿与正式报告的输入/落盘顺序必须由结构化节点结果传递和测试断言保护，不在 Pipeline 复制报告落盘算法。
- **R-05 跨仓路径误用**：所有开发与评审路径从 `workspace inspect` 读取；各仓文档分别提交，避免把多仓文件误认为同一 commit。

### 7.2 范围排除

- 不修改状态机、审批 grant、reviewLoop 规则或 traceability evidence 结构；仅可在既有 `crctl` gate 机制内增加本 CR 要求的 target-version check，不新增状态。
- 不新增 Pipeline 专用事务层、状态投影、第二套 review-loop 账本、测试证据格式、candidate/manifest/merge/recovery 算法、通用 Runner、独立 ledger、contract-version、迁移器或 feature flag。
- 不新增 Agent、Skill、Pipeline 节点、状态、独立 ADR、跨 CR CONTEXT、术语中心或历史 CR 批量迁移。
- 不把规划类本地评审记录强行迁移到 CR `crctl` 评审机制；不把 README 变成第二份可执行 Pipeline 事实源。
- 不在本 CR 中实现新的产品业务功能、UI、HTTP API 或用户数据模型；本 CR 只对 tools 生命周期合同和既有运行时入口做对齐。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；需求文档只落盘于 `change-requests/CR-2026-060/` 的 CR worktree。
- 不要求所有 active repo 无条件产生 commit；只有实际变更或测试的 worktree 需要 clean committed。

### 7.3 实施完成定义

当 AC-01 至 AC-18 全部满足，四组变更已完成评审与测试，CR-2026-060 可在兼容模式下走完回写归档，且没有受控账本漂移时，本 CR 达到实施完成标准。

## Discussion 无 Issue 共享会话（v0.32 · CR-2026-059）

## 1. 概述

### 1.1 问题陈述

项目 Discussion 目前仍把普通沟通、附件和 Coordinator 协办挂在隐藏 `project_discussion` Issue 的 comment 流上，与来源文档（`docs/product/Multica聊天会话级配置与Discussion方案.md`，CR-B 段）描述的目标承载不一致：

- `GET /api/projects/{id}/discussion` 打开面板就会 `EnsureProjectDiscussionIssue`，空面板也会留下一个工作容器。
- 普通文字、附件、绑定 Coordinator、@mention 协办都写 comment；协办任务挂在该 Issue 上，而不是无 Issue 的 chat task。
- 前端 `DiscussionPane` 用 Issue timeline 渲染消息，并把 `issue_id` 当作会话身份；发送走 comment API。
- `PATCH /api/chat/sessions/{sessionId}/config` 只对 Private Ask 生效且按 `creator_id` 门禁；Discussion 没有会话级模型 / Thinking Mode。
- `chat_session` 没有 `kind`，`agent_id` 非空，且 `(project_id, creator_id)` 的 active 唯一索引把「项目内任意 active session」都算进去——直接插入项目级 shared session 会与同一创建者的 Private Ask 撞车。

以上事实已在来源文档 §14 记录，并在本 CR 落笔前按当前 `../multica` 的 CR-2026-059 requirement worktree（已同步至 multica main）复核（见 §1.4）。本 CR 不处理 Discussion → 工作 Issue/CR 的显式升级，也不改 Team Agent 配置与发送内核。

### 1.2 解决方案摘要

把新 Discussion 从隐藏 Issue/comment 换成项目级 shared `chat_session` / `chat_message`：

```text
Discussion:
  chat_session(kind=project_shared)
    -> chat_message
    -> 可选 Coordinator chat task（issue_id 为空）
    -> 打开 / 发送 / 附件 / 协办均不创建工作 Issue
    -> 旧 project_discussion Issue 只读，新消息不双写
```

本 CR（来源文档 CR-B，注册摘要已拍板）交付一个可独立验收的闭环：

1. `chat_session.kind` 区分 `private` 与 `project_shared`；每个项目最多一个 active shared session。
2. Discussion GET 只创建或读取 shared session，不得创建 `project_discussion` Issue。
3. 项目成员（= 当前 workspace 成员，口径见 FR-25）读写 shared session；`creator_id` 只作审计，不作 ACL。
4. Discussion 会话级模型 / Thinking Mode 复用 CR-2026-056 的解析、校验和任务快照，不得第二套实现。
5. 普通消息只写 `chat_message`，不创建 Agent task、不创建 Issue。
6. 明确 @mention Coordinator 或分析/总结请求才创建无 Issue 的 chat task；回复写回同一 shared session。
7. 发送前附件复用 CR-2026-056 未绑定草稿契约；发送成功绑定到 session / message（协办时也绑 task）。
8. 旧 `project_discussion` Issue 保留只读回放；新消息不双写。

### 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

将新 Discussion 从隐藏 Issue/comment 改为项目级 shared `chat_session`/`chat_message`，支持单一 Coordinator 协办，打开/发送/附件/协办均不自动创建工作 Issue。不含多 Agent 参与者表、Discussion 升级、历史全量迁移，以及 Team Agent 配置与发送链路。依赖已归档 CR-2026-056（来源文档 CR-A）的会话配置解析、任务快照和未绑定附件校验。

目标仓库为 sibling `../multica/`。knowledge-base 承载本 PRD 与来源文档；`../tools/` 无实施改动。

`target-version` 继承 `cr.md` 的 `0.32`（`crctl version-set` 已从 `unassigned` 更正），本文件不得改写该字段。

### 1.4 当前代码事实（落笔前核实）

基线：CR-2026-056 已合入 multica main 并已归档（KB `_history.yml` `final-status: archived`）；本 CR 的 requirement worktree 已于 2026-09-03 同步至 multica main `3759afb68bb76576bf5ec3efe82560cdea8fe132`（迁移最大编号仍为 **480**）。复核命令在 `../multica` 的 CR-2026-059 requirement worktree。

| 结论 | 证据 |
|---|---|
| Discussion GET 懒创建隐藏 Issue | `server/internal/handler/project_chat.go` `GetProjectDiscussion`（L224）调用 `EnsureProjectDiscussionIssue`（L250） |
| 容器创建集中在服务层 | `server/internal/service/project_chat.go` `EnsureProjectDiscussionIssue`（L55）；sqlc `GetProjectDiscussionIssue` |
| GET 响应只有 `issue_id` + `coordinator_agent_id` | `ProjectDiscussionResponse`（`handler/project_chat.go` L215）；前端 schema `packages/core/api/schemas.ts` `ProjectDiscussion`（L1400） |
| 前端按 Issue timeline 渲染 | `packages/views/projects/components/discussion-pane.tsx` |
| Coordinator 绑定已存在 | `project.settings.discussion_coordinator_agent_id`（`service/discussion_coordinator.go` L22 `ProjectSettingDiscussionCoordinatorID`） |
| Coordinator 激活走 comment mention | `comment.go` `handleDiscussionContainerMentionTrigger`（L2664）；任务挂在 Discussion Issue |
| Coordinator 转投 Team Agent 走 Issue comment | `service/discussion_coordinator.go` `RouteDiscussionToTeamAgent`（L103）；`MergeForwardDiscussion` 入参为 `comments []db.Comment`（`service/project_chat.go` L176） |
| `chat_session` 无 `kind` | `033_chat.up.sql` 及后续迁移未增加该列 |
| `chat_session.agent_id` 非空 + FK（CASCADE） | `033_chat.up.sql` L7 `agent_id UUID NOT NULL REFERENCES agent(id) ON DELETE CASCADE`；内联 FK，PostgreSQL 自动命名约束 `chat_session_agent_id_fkey`；同文件 `agent_task_queue.chat_session_id` 已是 `ON DELETE SET NULL`（既有先例） |
| Private Ask active 唯一索引不区分 kind | `436_chat_session_project.up.sql` `chat_session_project_creator_active_unique`（`(project_id, creator_id)`，谓词仅 `project_id IS NOT NULL AND status='active'`） |
| CR-A 配置列已在 `chat_session` | `478_chat_session_chat_config_columns.up.sql`：`base_model` / `base_thinking_level` / `model_override` / `thinking_level_override` |
| 通用配置 PATCH 仅 Private Ask + creator-only | `handler/chat.go` `PatchChatSessionConfig`（L858）：非创建者 403，无 `project_id` 404 |
| chat task 已支持 `chat_session_id` 且 `issue_id` 可空 | `033_chat.up.sql`；`CreateChatTask`（`pkg/db/queries/chat.sql` L1107） |
| 附件已支持未绑定及 session/message/task | `029_attachment` / `083_attachment_chat_columns` / `164_attachment_task_id` 迁移；CR-2026-056 上传者门与 168h sweeper（`service/chat_draft_attachment_cleanup.go`） |
| 当前最大迁移编号 **480** | `server/migrations/480_issue_project_chat_session_origin_uidx.up.sql` |
| 解析/快照/目录校验已落地 | `service/chat_config.go` `ResolveChatConfig`（L50）/ `ValidateResolvedChatConfig`（L88）/ `LoadChatCatalogForConfig`（L125）；`mergeChatConfigContext` |
| Idempotency-Key 基础设施已存在 | `server/pkg/publicapi/v1/foundation.go` `HeaderIdempotencyKey`、`MaxIdempotencyBytes = 255` |
| 错误体与发送错误映射已存在 | `handler.go` `writeErrorCode`（L549）；`handler/project_chat.go` `writeProjectChatSendError`（L589） |
| 同步后 trunk 新增内容不涉及 Discussion 代码路径 | multica main 相对本 CR 原基线（`217b281c`）新增：merge CR-2026-060: multica、`cr-prompts-revised/` Agent 提示词包、服务端 pipeline registry 再生成（`gate_nodes_gen.go`/`transitions_gen.go`） |

### 1.5 修订记录

- **2026-09-03（选项 A 裁决，AIFI-16）**：成员口径定点修订——「项目成员 := 当前 workspace 成员」。依据：来源文档的 8 处成员表述（7 处直写「项目成员」+ 1 处 project/workspace 并写）均为 ACL 表述、无独立成员建模；multica 成员唯一模型是 workspace 级 `member`（无项目级成员表）；KB 延期清单第 10 项已把「项目级成员模型」列为未来引入项。本次修订把 FR-25 负向契约中「同 workspace 非本项目成员」空类改写为「非本 workspace 成员」，把「已被移出项目」改写为「已被移出 workspace（member 行删除，挂接平台已有 revoke-member 事务与退订机制）」，并同步 FR-4/FR-9/FR-10/FR-17/FR-20、Discussion 与 merge-forward HTTP 契约权限行、AC-20/AC-28/AC-29、成功指标与范围排除的措辞，保证可测性。其余需求不变。

## 2. 用户故事

- **US-1 项目成员**：作为项目成员，我希望打开 Discussion 时不会悄悄创建一个隐藏 Issue，从而普通沟通不再污染工作项列表。
- **US-2 项目成员**：作为项目成员，我希望在 Discussion 里发文字和附件，其他成员立刻能看见，而这些消息不会创建 Agent task 或工作 Issue。
- **US-3 项目 owner/admin**：作为项目管理员，我希望 Discussion 的模型和 Thinking Mode 属于这条共享会话，改配置不影响 Agent 管理页，也不影响 Private Ask 或其他项目。
- **US-4 协办请求者**：作为具备 Agent 调用权限的成员，我希望只有明确 @mention Coordinator 或发起分析/总结时才启动 Agent，并且任务挂在会话上、没有 Issue。
- **US-5 协办观察者**：作为项目成员，我希望 Coordinator 的回复出现在同一条 Discussion 时间线里，而不是另开一个工作 Issue。
- **US-6 附件上传者**：作为附件上传者，我希望发送前的草稿只有我能看见；发送成功后才和消息一起对项目成员可见，失败时仍可重试。
- **US-7 历史读者**：作为项目成员，我希望仍能只读回放旧 Discussion Issue 里的历史消息，同时新消息只进入 shared session、不双写。
- **US-8 Private Ask 用户**：作为 Private Ask 用户，我希望 Discussion 的共享可见性不会放宽我的 creator-only 会话。

## 3. 功能需求

### FR-1 打开 Discussion 不得创建工作 Issue

`GET /api/projects/{projectId}/discussion` 可以创建或读取该项目的 active `project_shared` session，但不得调用 `EnsureProjectDiscussionIssue`，也不得以任何其他路径创建 `origin_type='project_discussion'` 的 Issue，或任何其他工作 Issue。未配置 Coordinator 时仍必须能打开纯人类会话。来源 FR-13、FR-14、§7.2、AC-16。

### FR-2 Discussion 使用 `chat_session.kind = project_shared`

为 `chat_session` 增加 `kind`：`private` | `project_shared`。已有行（1:1 聊天与 Private Ask）默认 `private`。新 Discussion 只使用 `project_shared`。不得复制一套 Discussion 消息表。来源 §5.3、FR-14。

### FR-3 每个项目最多一个 active shared session

第一阶段每个 `(workspace_id, project_id)` 最多一个 `kind=project_shared` 且 `status=active` 的 session。由部分唯一索引 + 服务层项目级并发锁共同保证。并发 GET 必须收敛到同一 `session_id`。来源 FR-17。

### FR-4 `creator_id` 不作 shared session ACL

shared session 仍写入 `creator_id`（首次打开者，审计用）。项目成员（= 当前 workspace 成员，口径见 FR-25）读取、发送、订阅实时事件不得因 `caller != creator_id` 被拒绝。不得用 `creator_id` 过滤 shared session 消息列表。非 workspace 成员 / 已被移出 workspace / 仅持有 UUID 的拒绝规则见 FR-25，不得用「项目成员可读写」一句话代替负向契约。来源 FR-17、§9、AC-21。

### FR-5 Private Ask 与 1:1 的 creator-only 不得被放宽

`kind=private`（含 Private Ask 与无 `project_id` 的 1:1）继续走现有 creator-only 门禁。`PatchChatSessionConfig`、`SendChatMessage`、`GetChatSession`、实时事件不得因为新增 `project_shared` 分支，让非创建者读到或改到 Private Ask。来源 AC-21、§7.2、§9。

### FR-6 必须改写 Private Ask active 唯一索引谓词

现有 `chat_session_project_creator_active_unique`（`436_chat_session_project.up.sql`）在 `project_id IS NOT NULL AND status = 'active'` 上唯一，**不区分 kind**。本 CR 必须把它收窄为仅覆盖 `kind = 'private'`（或等价「非 project_shared」），否则插入 Discussion shared session 会与同一 `creator_id` 的 Private Ask 冲突。另增 `(workspace_id, project_id)` 上 `kind='project_shared' AND status='active'` 的部分唯一索引。索引均 `CREATE [UNIQUE] INDEX CONCURRENTLY`，一文件一条语句。来源 §5.3；本条是落笔前核实出的实施约束，来源文档未单列但属于 FR-3/FR-5 可落地前提。

### FR-7 `agent_id` 对 shared session 可空

shared session 在未绑定 Coordinator 时 `agent_id` 必须允许 NULL，以支持纯人类 Discussion。绑定 Coordinator 后可写入该 Agent id；解绑后回到 NULL，session 行不删。不得对无 Coordinator 的 GET/发送要求 Agent。现有 `INNER JOIN agent` 的 Private Ask / 1:1 查询不得被 NULL `agent_id` 带崩，也不得把无 Coordinator 的 shared session 从 Discussion 查询里滤掉。`agent_id` 是项目设置的**投影**，不是第二套绑定入口；权威源、同步、重绑与失效见 FR-26。列级 NOT NULL 与既有 CASCADE FK 的改动由 481 迁移落地（FR-21）：Coordinator Agent 被 hard-delete 时 session/message 行必须保留（不得级联删除）、`agent_id` 由 FK 置 NULL（AC-31/AC-32 验收）。来源 §5.3、FR-4。

### FR-8 Discussion 配置属于共享 session，owner/admin 可改

第一阶段由项目 owner/admin 修改模型和 Thinking Mode；必须服务端强制，仅隐藏前端控件不足够。没有 Coordinator 时仍可保存配置（基础快照在创建时写入：有 Coordinator 则取其当时默认值；无 Coordinator 则 `base_*` 允许空，有效值按 CR-2026-056 优先级回退到 runtime 默认，source 不得标成 `agent_default`）。来源 FR-4、FR-5、FR-6、§9。

### FR-9 配置 PATCH 按 kind 分流，复用 CR-A 解析与校验

`PATCH /api/chat/sessions/{sessionId}/config`：

- `kind=private`：保持 CR-2026-056 行为（creator-only；无 `project_id` 的 1:1 仍 404）。
- `kind=project_shared`：当前 workspace 成员（项目成员口径见 FR-25）可 GET 配置；PATCH 仅 owner/admin。非 owner/admin PATCH 返回 403 `forbidden_chat_config`。

有效值解析、三态 PATCH（省略 / `null` 或空串清除 override / 非空设置 override）、目录与 runtime 校验必须调用 CR-2026-056 已落地的 `ResolveChatConfig` / `ValidateResolvedChatConfig` / `LoadChatCatalogForConfig`，禁止第二套快照逻辑。无 Coordinator（`agent_id` 为空）时不得走「创建者 Agent」路径，也不得调用 `UpdateAgent`。来源 FR-26、FR-28、§6、§7.2；依赖 CR-2026-056。

### FR-10 普通 Discussion 消息只写 chat_message

当前 workspace 成员发送普通文字或附件消息：只创建 `chat_message`（`role=user`），不创建 Agent task，不创建 Issue，不写 comment。来源 FR-15、AC-17、AC-18、§8.2。

### FR-11 明确请求才创建无 Issue 的 chat task

仅在以下情况创建 chat task：

1. 消息明确 `@mention` **当前可路由 Coordinator**（FR-26 的解析结果）；或
2. 用户点击分析 / 总结（或等价的显式协办操作，`coordinator_request=analyze|summarize`）。

`coordinator_request` 与正文 @mention 不得双建 task：`analyze`/`summarize` 优先于 mention 推导；`mention` 与正文 @mention 只建一个 task。@mention 其它 Agent 不当作协办，走 FR-10。

任务必须：`chat_session_id` = 该 shared session；`issue_id` 为空；`agent_id` = 入队当时可路由 Coordinator；入队前写入 `context.chat_config` 快照（合并保留已有字段，禁止整对象覆盖）。设置未绑定 → 409 `discussion_coordinator_not_configured`；已绑定但 Agent 删除/归档/不在本 workspace → 409 `discussion_coordinator_unavailable`；两者都不创建 task 与 Issue。不具备 Agent 调用权限的成员发起协办被 403（现有 invocation 拒绝，不新造枚举）。来源 FR-16、FR-26、AC-19、§8.2、§9。

### FR-12 Coordinator 回复写回同一 shared session

Coordinator（及由其触发的助手消息）写入同一 `project_shared` session 的 `chat_message`（`role=assistant`），不得创建工作 Issue，不得把新回复写到旧 `project_discussion` Issue。执行、重试、重新 claim 只读该任务的 `chat_config` 快照。来源 FR-16、FR-27、AC-20。

### FR-13 现有 Coordinator 转投与 merge-forward 的 Discussion 侧适配

CR-2026-012 的两条既有能力必须在新承载上继续可触发，但**不得改写** CR-2026-056 的 Team Agent 发送事务：

1. Coordinator 把工作转投到 Team Agent（`RouteDiscussionToTeamAgent` / DD-5）：触发源从 Discussion Issue comment 改为 shared session 消息；之后调用既有 Team Agent 发送内核。
2. 成员多选 Discussion 消息 merge-forward（`POST /api/projects/{id}/chat/merge-forward`）：入参从仅 `comment_ids` 扩展为 shared session 的 `message_ids`。完整 HTTP 八项见「merge-forward HTTP 契约」与 FR-23 / FR-24。

明确不修 CR-2026-056 台账中的 KG-1（转投无 `chat_config` 快照）和 KG-2（换绑后转投仍写旧 Issue）。来源 cr.md「不含 Team Agent 配置与发送链路」；兼容既有 Discussion UI，避免新承载把协办/转投打成死链。

### FR-14 发送前附件是上传者草稿

复用 CR-2026-056 未绑定附件契约：发送前五类绑定字段全空；只有上传者可访问、下载、删除和重试绑定；不得出现在项目公共附件列表、Team Agent timeline、Discussion 消息流或团队 WebSocket。不得另建草稿表。来源 FR-18、FR-19；依赖 CR-2026-056。

### FR-15 发送成功原子绑定，失败保留草稿

Discussion 发送成功时，附件必须在同一发送事务中绑定到 `chat_session` 和 `chat_message`；若本条触发了协办 task，也绑定 `task_id`。事务失败不得留下半成品消息/task/Issue；未绑定附件保留供重试。发送失败不得删除草稿。TTL sweeper 继续用 CR-2026-056 的 168h 周期，本 CR 不改谓词。来源 FR-20 Discussion 分支、FR-21、§8.2。

### FR-16 旧 project_discussion Issue 只读、不双写、不补建

已存在的 `origin_type='project_discussion'` Issue 保留，可供只读回放。切换后：

- 新消息只进入 `project_shared` session。
- 不得把新消息再写进该 Issue（不双写）。
- 不得删除旧 Issue。
- GET Discussion **不得**为「还没有历史容器」的项目补建该 Issue。

GET 响应可带可空 `legacy_issue_id`（已有历史容器则为 UUID，否则 JSON `null`），供只读回放；该字段出现不得被前端当成可写 session 身份。来源 AC-22、§11.1。

### FR-17 GET/PATCH/发送携带 session 身份并防漂移

Discussion 的配置 PATCH 与发送必须针对 GET 返回的 `session_id`。服务端确认该 session 属于当前 workspace/project、`kind=project_shared`。精确状态不得「404/409 二选一」，映射固定为：

| 条件 | 状态 | error-code |
|---|---|---|
| session 不存在、跨 workspace、跨项目、`kind≠project_shared`、调用者不是当前 workspace 成员（项目成员口径见 FR-25） | 404 | `chat_session_not_found` |
| 调用者是当前 workspace 成员，但 `status≠active`（已归档/关闭）且操作为 PATCH 或 POST | 409 | `chat_session_closed_or_changed` |
| 同上，但操作为消息列表 GET | 200 | （只读；不创建新 session） |

不得静默另开 session，不得落到 Private Ask 行上。来源 §7.2、§7.3。

### FR-18 可区分错误与前端回滚

至少保持并覆盖 Discussion 路径（状态与 code 一一对应，禁止只写 2xx / 4xx）：

```text
400 invalid_model_or_thinking_level
400 invalid_discussion_message
400 invalid_message_selection
400 invalid_merge_forward_selection
400 invalid_cursor
400 idempotency_key_required
403 forbidden_chat_config
403 forbidden_project_discussion
404 chat_session_not_found
409 chat_session_closed_or_changed
409 discussion_coordinator_not_configured
409 discussion_coordinator_unavailable
409 attachment_already_bound
409 idempotency_key_reused
```

legacy `comment_ids` 路径继续使用既有 400 `invalid_comment_selection`（本 CR 不改该 code）。前端根据错误回滚配置控件或保留草稿，不静默丢失输入和附件。来源 §7.3。

### FR-19 前端 DiscussionPane 改走 shared session

`DiscussionPane` 必须以 `session_id` 为会话身份：拉消息、发送、附件、配置控件、实时更新都走 shared session API，不再把 GET 的 `issue_id` 当作可写容器。硬降级规则对齐 CR-2026-056：`session_id` 缺失 / 空 / 非 UUID 时只读并重试 GET，禁止拿空 id 去 PATCH/发送。只读历史通过 `legacy_issue_id` 渲染旧 Issue timeline，且明确不可在该流发送。Model / Thinking 控件调用会话配置接口，不调用 `UpdateAgent`。来源 FR-29 中与功能接入相关的部分（不重做 composer 视觉，视觉属 CR-D）。

### FR-20 实时事件对当前 workspace 成员可见

shared session 的新消息、协办 task 事件必须广播给**当前** workspace 成员（项目成员口径见 FR-25），不得沿用 Private Ask 的 per-creator 投递。Private Ask 事件投递保持 per-user。成员被移出 workspace 后的退订 / 不广播见 FR-25。来源 §9、AC-21。

### FR-21 迁移、sqlc 与定制台账

新迁移从下一个可用编号 **481** 起。禁止新增 FOREIGN KEY / REFERENCES / 级联删除或更新。**唯一允许的既有 FK 生命周期改动**（这是「转换既有约束」，不是新增 FK）：

**481 迁移：`agent_id` 改可空 + 既有 FK `ON DELETE CASCADE` → `ON DELETE SET NULL`**（落地 FR-7 / FR-26 的 Coordinator hard-delete 保留语义；取评审推荐方案——保留 DB 级引用完整性，不采用「删除 FK + 纯应用层校验」）：

- `up`（同一迁移文件按序执行）：
  ```sql
  ALTER TABLE chat_session ALTER COLUMN agent_id DROP NOT NULL;
  ALTER TABLE chat_session DROP CONSTRAINT chat_session_agent_id_fkey;
  ALTER TABLE chat_session ADD CONSTRAINT chat_session_agent_id_fkey
      FOREIGN KEY (agent_id) REFERENCES agent(id) ON DELETE SET NULL;
  ```
  约束名沿用 PostgreSQL 对 `033_chat.up.sql:7` 内联 FK 的自动命名（该文件未显式命名）；引用列与被引用列不变。`ADD CONSTRAINT` 不自动建索引，与基线一致（基线该列亦无独立索引），本 CR 不新增该列索引。
- `down`：反向恢复——`DROP CONSTRAINT chat_session_agent_id_fkey` → 重建为 `... ON DELETE CASCADE` → `ALTER COLUMN agent_id SET NOT NULL`。最后一步在存在 NULL `agent_id` 行时会失败，属**数据依赖回滚**：注释必须写明「先清理 NULL 行再回滚」，禁止静默吞掉或伪造成功。
- 除此之外不新增任何 FK；`chat_message.chat_session_id`、`chat_session.workspace_id/creator_id` 的既有 CASCADE 不属本 CR 范围，不动。

每个新增索引必须 `CREATE [UNIQUE] INDEX CONCURRENTLY` 且一个迁移文件一条语句。本 CR 在 multica 仓落地的新文件、挂钩点和迁移必须登记 `CUSTOM.md`（编号顺延）。代码注释一律英文。

### FR-22 Discussion 四主 endpoint HTTP 八项闭合

`GET /discussion`、`PATCH .../config`、`GET .../messages`（及同语义的 `.../messages/page`）、`POST .../messages` 必须按下方「Discussion HTTP 契约」闭合：endpoint、request、response、精确状态/error-code、权限、幂等、状态副作用、验收观察点。禁止成功只写「2xx」，禁止错误只写「404 或 409」。

### FR-23 merge-forward 入参扩展必须闭合修改契约

`POST /api/projects/{id}/chat/merge-forward` 新增 `message_ids` 后，必须按下方「merge-forward HTTP 契约」闭合互斥、空/重复/顺序/跨 session、权限、响应、错误、成功状态、幂等与副作用。legacy `comment_ids` 行为与 error-code 保持 CR-2026-012（400 `invalid_comment_selection`）。不得改 `sendProjectChatCore`。

### FR-24 有副作用的 Discussion 入口必须可安全重试

`POST .../messages`（`kind=project_shared`）与带 `message_ids` 的 merge-forward 必须接受 `Idempotency-Key`（现有头，`server/pkg/publicapi/v1/foundation.go`，最长 255 字节）。缺头 400 `idempotency_key_required`。同一调用者 + 同一 session/project + 同一 key：指纹相同则重放首次成功响应（201，同一 `message_id`/`task_id` 或 merge-forward 的 `comment_id`/`task_id`），不新建 message/task，已绑定附件不得退化成 409 `attachment_already_bound`；指纹不同则 409 `idempotency_key_reused` 且零写入。并发同一 key 必须收敛到一次提交。记录至少保留 24h。Private Ask `POST .../messages` 与 legacy `comment_ids` merge-forward **不**新要求该头。

### FR-25 shared session 安全负向契约

授权以**请求当时**的 workspace 成员资格为准，不看 `creator_id`，不看历史上是否开过面板。

**成员口径（选项 A 裁决，AIFI-16）**：项目成员 := 当前 workspace 成员。来源文档的 8 处成员表述（7 处直写「项目成员」+ 1 处 project/workspace 并写）均为 ACL 表述、无独立成员建模；multica 成员唯一模型是 workspace 级 `member`（`034_projects.up.sql` 仅 `lead_id`，无项目级成员表）；KB 延期清单 `docs/product/部分/CR后续工作汇总-优先级清单.md` 第 10 项已把「项目级成员模型」列为未来引入项，本 CR 不引入。因此「同 workspace 非本项目成员」是空类（能访问本项目的 workspace 成员即项目成员），负向契约按下表以 workspace 成员资格表述。

| 调用者 | 项目路径 `GET /discussion` | session 路径（消息 GET/POST、PATCH config） | 已发送附件下载 | 实时 |
|---|---|---|---|---|
| 当前 workspace 成员（= 项目成员） | 按主契约 | 按主契约 | 允许 | 订阅并接收 |
| 非本 workspace 成员 | 403 `forbidden_project_discussion` | 404 `chat_session_not_found` | 404（不确认附件存在） | 拒绝订阅；不广播 |
| 已被移出 workspace 的旧成员 | 同上 403 | 同上 404 | 同上 404 | 移出事务中退订；之后不广播 |
| 仅持有 session/message/attachment UUID、无当前 workspace 成员资格 | 无项目路径则不适用 | 404 `chat_session_not_found` | 404 | 拒绝订阅；不广播 |

「已被移出 workspace」= workspace `member` 行删除，挂接平台已有 revoke-member 事务（`revokeAndRemoveMember`，`server/internal/handler/workspace_revoke.go`）与既有退订机制（AC-29）。未绑定草稿仍仅上传者可访问（FR-14）。Private Ask 维持 creator-only。不得因持有 UUID 而从 shared 分支漏读。

### FR-26 Coordinator 唯一权威源与生命周期

**写权威**：`project.settings.discussion_coordinator_agent_id`（既有项目 settings PATCH，本 CR 不另造绑定 URL）。非法 UUID / 非本 workspace Agent 保持现有 400。

**投影**：active `project_shared` session 的 `agent_id` 必须在项目锁下与写权威对齐，禁止长期分叉。

| 事件 | settings | session.agent_id | `base_*` | 已入队 task |
|---|---|---|---|---|
| 首次 GET 尚无 session | 不变 | 创建时写入当时 settings（可空） | 有可路由 Coordinator 则取其当时默认；否则允许空（FR-8） | 无 |
| 首次绑定（空 → Agent） | 写入 UUID | 同一事务投影 | **补写**当时 Agent 默认（仅当 `base_*` 仍空） | 不变 |
| 替换（Agent A → B） | 写入 B | 投影为 B | **不**重取快照 | 保持旧 `agent_id` 与 `chat_config` |
| 解绑（UUID → 空） | 清除 key | 投影为 NULL | 不变 | 保持旧绑定直到终态 |
| Agent 归档 / 不在 workspace | settings 保留原 UUID，GET 仍回该值；**不**自动清 settings | 投影为 NULL（不可路由） | 不变 | 保持旧绑定直到终态 |
| Agent hard-delete（`agent` 行删除） | settings 保留原 UUID，GET 仍回该值（settings 是 project 级数据，不随 agent 行删除） | **DB 级 FK `ON DELETE SET NULL` 置 NULL**（481 迁移）；session/message 行**保留**（不级联删除） | 不变 | 保持旧绑定直到终态；历史消息与回放完整可读 |

**读规则**（GET / @mention / 新 task 路由，任一入口不得混读）：

1. 可路由 Coordinator = settings UUID，且该 Agent 在本 workspace 存在且未归档。
2. GET `coordinator_agent_id` = settings 原值（未配置则空串）；即使 Agent 已失效也回原 UUID，供 UI 展示坏绑定。
3. @mention 校验与新 task 路由只使用「可路由 Coordinator」。失效时新协办 409 `discussion_coordinator_unavailable`。
4. 竞态：settings PATCH 与 GET/发送必须抢同一项目锁；锁内先写 settings 再投影 `agent_id`，或 GET 发现分叉则先修复再返回。并发 GET 仍收敛到 FR-3 的同一 `session_id`。
5. Agent hard-delete 不得级联删除 `chat_session` / `chat_message`：481 迁移把 FK 改为 `ON DELETE SET NULL` 后，删除 agent 行只把 session.`agent_id` 置 NULL，session/message 行与历史回放完整保留，事务与回放验收见 AC-32。

### Discussion HTTP 契约（可执行，覆盖 FR-1 / FR-8 / FR-9 / FR-10 / FR-11 / FR-17 / FR-22 / FR-24 / FR-25）

一期保留项目路径；`PATCH /config` 与 `GET|POST .../messages` 已存在，按 `kind` 分流，不另造平行 URL。

```text
GET    /api/projects/{projectId}/discussion
PATCH  /api/chat/sessions/{sessionId}/config
GET    /api/chat/sessions/{sessionId}/messages
GET    /api/chat/sessions/{sessionId}/messages/page
POST   /api/chat/sessions/{sessionId}/messages
```

公共错误体：`{ "code": "<error-code>", "error": "<message>" }`（与现有 `writeErrorCode` 一致）。未登录走现有 401，本表不重复。

#### GET `/api/projects/{projectId}/discussion`

| 项 | 契约 |
|---|---|
| request | 无 body。`projectId` 为 UUID。 |
| 权限 | 当前 workspace 成员（= 项目成员，口径见 FR-25）。非本 workspace 成员 / 已被移出 workspace：403 `forbidden_project_discussion`。项目不在本 workspace：404（现有 `project not found`，无 code）。 |
| 成功 | **200**。创建或读取该项目唯一 active `project_shared` session；不得创建 Issue。 |
| 幂等 | 不要求 `Idempotency-Key`。并发 GET 在项目锁下收敛到同一 `session_id`（FR-3）。若仅有已归档 shared session，本 GET **新建**一条 active session，不自动解档。 |
| 副作用 | 可能插入一行 `chat_session`；禁止插入 `project_discussion` Issue。 |

成功体：

```json
{
  "session_id": "<uuid>",
  "issue_id": null,
  "legacy_issue_id": "<uuid>|null",
  "coordinator_agent_id": "<uuid-or-empty>",
  "model": "<id-or-empty>",
  "thinking_level": "<level-or-empty>",
  "model_source": "override|session_default|runtime_default",
  "thinking_level_source": "override|session_default|runtime_default"
}
```

- `issue_id` 必须为 JSON `null`。
- `legacy_issue_id` 仅回放；无历史则为 `null`；本 GET 不得插入该 Issue。
- `coordinator_agent_id` 按 FR-26 回 settings 原值；未配置时为空字符串，不得伪造 UUID。
- 不得返回 `agent_default`。

#### PATCH `/api/chat/sessions/{sessionId}/config`（`kind=project_shared`）

| 项 | 契约 |
|---|---|
| request | 无 `session_id` 字段（id 在 path）。body 三态与 CR-2026-056 FR-6 全等：`model` / `thinking_level` 省略=保持，`null` 或 `""`=清 override，非空=设 override。 |
| 权限 | 当前项目 owner/admin。当前 workspace 成员但非 owner/admin：403 `forbidden_chat_config`。非 workspace 成员 / 跨项目 / 错误 kind：404 `chat_session_not_found`（FR-17）。 |
| 成功 | **200**。响应配置字段与 GET Discussion 相同（含 `session_id`；`issue_id` 仍为 null）。 |
| 错误 | 400 `invalid_model_or_thinking_level`；409 `chat_session_closed_or_changed`（成员看到已归档 session）。非法 JSON：400（现有 `invalid request body`）。 |
| 幂等 | 不要求 `Idempotency-Key`；末次提交获胜。不创建 session。 |
| 副作用 | 只改该 session 的 override；不调用 `UpdateAgent`；不影响已入队 task。 |

`kind=private` 保持 CR-2026-056：creator-only；无 `project_id` 的 1:1 仍 404。

#### GET 消息列表（`kind=project_shared`）

Discussion **禁止**对 shared session 返回无分页裸数组。`GET .../messages` 与已有 `GET .../messages/page` 对 `kind=project_shared` **同语义**，响应必须是分页对象，不得是 `ChatMessageResponse[]`。`kind=private` 的 `GET .../messages` 仍为现有裸数组，本 CR 不改。

| 项 | 契约 |
|---|---|
| request | query：`limit` 可选，默认 50，范围 1–100；`before_created_at`（RFC3339Nano）与 `before_id`（UUID）必须成对出现或成对省略。非法 limit/缺一半 cursor：400 `invalid_cursor`。无 body。 |
| 排序 | SQL 先取更新窗口，序列化前反转为页内时间正序（与现有 `ListChatMessagesPage` 全等）。 |
| 权限 | 当前 workspace 成员。非 workspace 成员 / 错误 kind / 跨项目：404 `chat_session_not_found`。已归档 shared session：**200** 只读。 |
| 成功 | **200**。 |
| 幂等 | 只读，无 `Idempotency-Key`。 |
| 副作用 | 无。不得混入 Private Ask 消息。 |

成功体（沿用现有 `ChatMessagesPageResponse`）：

```json
{
  "messages": [
    {
      "id": "<uuid>",
      "chat_session_id": "<uuid>",
      "role": "user|assistant",
      "content": "<string>",
      "task_id": "<uuid>|null",
      "created_at": "<rfc3339>",
      "attachments": []
    }
  ],
  "limit": 50,
  "has_more": false,
  "next_cursor": { "created_at": "<rfc3339nano>", "id": "<uuid>" }
}
```

`has_more=false` 时省略 `next_cursor`。`messages` 可为空数组。

#### POST `/api/chat/sessions/{sessionId}/messages`（`kind=project_shared`）

请求头：`Idempotency-Key` 必填（FR-24）。请求体：

```json
{
  "content": "这段讨论请看附件",
  "attachment_ids": ["<uuid>"],
  "coordinator_request": "none|mention|analyze|summarize"
}
```

输入约束（违反一律 400 `invalid_discussion_message`，零写入）：

- `content` 去首尾空白后为空 **且** `attachment_ids` 缺省或长度为 0：拒绝（至少一项）。
- `attachment_ids` 含重复 UUID：拒绝（不静默去重）。
- `attachment_ids` 元素非 UUID：400（现有 `parseUUIDSliceOrBadRequest`）。
- `coordinator_request` 缺省视为 `none`；其它非法枚举：拒绝。
- `content` 可为空字符串，只要有合法附件。

| 项 | 契约 |
|---|---|
| 权限 | 当前 workspace 成员可发普通消息。协办另需 Agent 调用权限，否则 403（现有 invocation）。非 workspace 成员：404 `chat_session_not_found`。 |
| 成功 | **201 Created**（禁止 200/204/空 body）。 |
| 错误 | FR-17 归档 409 `chat_session_closed_or_changed`；FR-11 两个 409 coordinator code；已绑定附件 409 `attachment_already_bound`（仅当**非**幂等重放）；配置 400 `invalid_model_or_thinking_level`；缺幂等头 400 `idempotency_key_required`；指纹冲突 409 `idempotency_key_reused`。 |
| 幂等 | FR-24。指纹 = trim(`content`) + 稳定排序后的 `attachment_ids` + `coordinator_request`（重复 ID 在校验阶段已 400，进不了指纹）。重放 201 且同一 `message_id`/`task_id`。 |
| 副作用 | 普通消息：一条 `chat_message`（`role=user`），无 task、无 Issue。协办：同一事务再加一条 `issue_id` 为空的 chat task。附件在同一事务绑定。失败零残留。 |

成功体：

```json
{
  "session_id": "<uuid>",
  "message_id": "<uuid>",
  "issue_id": null,
  "task_id": null
}
```

`session_id` 等于 path。普通消息 `task_id` 为 JSON `null`；协办成功为非空 UUID。`issue_id` 恒为 `null`。失败不返回半成品 id。

### merge-forward HTTP 契约（覆盖 FR-13 / FR-23 / FR-24）

`POST /api/projects/{id}/chat/merge-forward`

请求体：

```json
{
  "comment_ids": ["<uuid>"],
  "message_ids": ["<uuid>"],
  "register_cr": false
}
```

互斥与输入：

| 条件 | 状态 | error-code |
|---|---|---|
| `comment_ids` 与 `message_ids` 均非空 | 400 | `invalid_merge_forward_selection` |
| 仅 `comment_ids`（含 `{}` / 空数组 / 省略 `message_ids`，与今日行为一致） | 沿用 CR-2026-012 | `invalid_comment_selection`（空、>50、非本项目 Discussion comment） |
| `message_ids` 键存在且为空数组，且无非空 `comment_ids` | 400 | `invalid_message_selection` |
| `message_ids` 非空：长度 >50；任一 id 非本项目 `kind=project_shared` 的 **同一** session；跨 session；Private Ask / 他项目 / 普通 Issue | 400 | `invalid_message_selection` |
| `message_ids` 含非 UUID | 400 | 现有 generic bad request |
| `message_ids` 重复 | 按首次出现顺序静默去重（与现有 comment 去重一致），去重后仍须 ≥1 且 ≤50 | — |

`register_cr` 缺省 `false`；`true` 时仍只向 Team Agent 合并文本追加 instruction block，零 CR 账本写入。

| 项 | 契约 |
|---|---|
| 权限 | 当前 workspace 成员（= 项目成员）且具备既有 Team Agent 发送权限（含 presenter 规则）。非 workspace 成员：403 `forbidden_project_discussion`。项目不存在：404 `project not found`。 |
| 成功 | **201**。体为既有 `SendProjectChatMessageResponse`：`session_id`、`issue_id`、`comment_id`、`task_id`（Team Agent 侧，均非空 UUID）。 |
| 错误 | 内核错误沿用 `writeProjectChatSendError`（403 `presenter_required`、409 `team_agent_not_configured`、429 `project_queue_full`、502 `enqueue_failed` 等）。`message_ids` 路径缺 `Idempotency-Key`：400 `idempotency_key_required`；指纹冲突：409 `idempotency_key_reused`。 |
| 幂等 | **仅** `message_ids` 路径要求 `Idempotency-Key`（FR-24）。指纹 = 去重后顺序保留的 `message_ids` + `register_cr`。重放 201 且同一 `comment_id`/`task_id`。legacy `comment_ids` 不新要求该头。 |
| 副作用 | 调用既有 merge-forward 内核：Team Agent 侧一条合并 comment + 一条 task。Discussion 源 `chat_message` / 旧 comment **不**移动、不删除、不双写回 Discussion。无 Team Agent 容器时由内核按既有规则 ensure（本 CR 不改）。 |

### legacy 响应安全降级（覆盖 NFR-8）

Discussion GET 用独立 zod schema，不要把 `session_id` 做成可写的空默认后继续操作。硬降级 / 软默认对齐 CR-2026-056「legacy 响应安全降级」：缺 `session_id` 则只读；合法 `session_id` 但缺配置字段时可写并重试。`issue_id` 出现非 null 不得被当成可写容器（本 CR 的可写身份只有 `session_id`）。

## 4. 非功能需求

- **NFR-1 双端一致**：web 与 desktop 共享 `packages/views` 行为一致；mobile 不在本 CR 范围。
- **NFR-2 四语文案**：新增 UI 文案提供 en/ja/ko/zh-Hans；`packages/views/locales/parity.test.ts` 对新增 key 全绿。
- **NFR-3 复用优先**：复用 `chat_session` / `chat_message`、CR-2026-056 配置解析与附件草稿、已有 chat task（可无 Issue）。不给 `agent_task_queue` 增加模型/Thinking 专用列，不复制 Discussion 消息表，不新增 `discussion_participant`。
- **NFR-4 并发与事务**：GET 创建 shared session 必须在项目锁下幂等；发送事务失败零残留；配置修改与 Coordinator 重绑只影响尚未入队的协办任务；同一 `Idempotency-Key` 并发必须收敛到一次提交。
- **NFR-5 安全**：未绑定附件下载必须校验上传者；shared session 的成员门禁、配置写权限、已发送附件下载与实时订阅必须服务端强制（FR-25）；不得用 session/message/attachment UUID 猜测读取。
- **NFR-6 兼容**：旧 `project_discussion` 只读；Private Ask / 1:1 / Team Agent 路径除本 CR 明确的索引谓词与 kind 分流外不得改变行为。
- **NFR-7 零 Team Agent 内核回归**：不修改 `sendProjectChatCore` 的配置写入、容器绑定和附件绑定语义；转投/merge-forward 只改 Discussion 侧入参适配。KG-1/KG-2 保持已知缺口。
- **NFR-8 API 兼容**：Discussion GET/发送响应必须经 `parseWithFallback` + zod schema，缺失 `session_id` 不得白屏、不得伪造 UUID。
- **NFR-9 依赖**：必须使用已归档 CR-2026-056 的会话配置解析、任务快照和未绑定附件校验；禁止平行实现。

## 5. 验收标准

| ID | 覆盖 FR | 可执行验收 |
|---|---|---|
| AC-1 | FR-1、FR-16 | 打开 Discussion 面板不创建 `project_discussion` 或其他工作 Issue；`GET` 的 `issue_id` 为 null；无历史容器时 `legacy_issue_id` 为 null 且数据库无新 `origin_type='project_discussion'` 行。 |
| AC-2 | FR-1、FR-10、FR-11 | 发送普通文字、上传附件、绑定/解绑 Coordinator、请求协办后，均不新增工作 Issue。 |
| AC-3 | FR-10、FR-11 | 普通 Discussion 消息不创建 Agent task；`POST .../messages` 成功体 `task_id` 为 null。 |
| AC-4 | FR-11、FR-17 | 明确 @mention Coordinator 或 `coordinator_request=analyze\|summarize` 后，task 的 `chat_session_id` 等于请求 session，`issue_id` 为空；`context.chat_config` 已写入。 |
| AC-5 | FR-12 | Agent 回复作为 `chat_message` 出现在同一 `session_id`；该 session 无对应工作 Issue。 |
| AC-6 | FR-4、FR-5、FR-20 | 项目成员 A 发送的 shared 消息对成员 B 可见；用户 B 的 Private Ask 对 A 仍不可见；Private Ask 非创建者调用配置 PATCH 仍 403。 |
| AC-7 | FR-16 | 旧 `project_discussion` Issue 的历史 comment 可只读回放；其后的新 Discussion 消息不出现在该 Issue 的 comment 流中。 |
| AC-8 | FR-3、FR-6 | 并发打开同一项目 Discussion 只产生一行 active `project_shared` session；同一用户在该项目的 Private Ask active session 仍可独立存在（索引谓词收窄后不再冲突）。 |
| AC-9 | FR-8、FR-9 | 非 owner/admin PATCH shared session 配置返回 403 `forbidden_chat_config`；owner/admin PATCH 不调用 `UpdateAgent`，`agent.model` / `agent.thinking_level` 不变。 |
| AC-10 | FR-9、FR-18 | 不支持的 model / Thinking Mode：PATCH 与协办入队返回 400 `invalid_model_or_thinking_level`；已入队 task 的 `chat_config` 不变。命令：`go test ./server/internal/handler/ ./server/pkg/agent/ -count=1`。 |
| AC-11 | FR-11 | 未绑定 Coordinator 时协办请求不创建 task 与 Issue，返回 409 `discussion_coordinator_not_configured`。 |
| AC-12 | FR-14 | 发送前未绑定附件只有上传者可见；其他项目成员下载/列表/消息流均不可见。 |
| AC-13 | FR-15 | 发送成功后附件绑定 `chat_session_id` 与 `chat_message_id`（协办时还有 `task_id`）并对项目成员可见；发送失败时五类绑定仍为空且可重试。 |
| AC-14 | FR-7 | 无 Coordinator 时 GET/普通发送成功；`agent_id` 为空；绑定 Coordinator 后协办可用，解绑后 `agent_id` 回到空且历史消息仍可读。 |
| AC-15 | FR-13、FR-23 | merge-forward 仅 `message_ids` 且消息均属本项目同一 shared session 时，201 且 Team Agent 侧一条合并 comment+task；Discussion 源消息不被移动或删除。仅 `comment_ids` 的旧 Issue 路径与 400 `invalid_comment_selection` 保持原行为。 |
| AC-16 | FR-13 | Coordinator 转投 Team Agent 仍可触发既有发送内核；本 CR diff 不修改 `sendProjectChatCore` 的容器绑定与 `chat_config` 写入语义。KG-1/KG-2 不得被本 CR 的验收当成新缺陷。 |
| AC-17 | FR-19、NFR-8 | `packages/core/api/schemas.test.ts`：Discussion GET 缺/空/非 UUID `session_id` → 硬降级只读；合法 `session_id` 且 `issue_id` 为 null 时可发送。前端不得用 `legacy_issue_id` 调用发送。 |
| AC-18 | FR-19、NFR-2 | DiscussionPane 在有 `session_id` 时不再依赖可写 `issue_id`；新增文案 en/ja/ko/zh-Hans 对称，`parity.test.ts` 全绿。 |
| AC-19 | FR-21、FR-6 | 从 481 起的迁移：无**新增** FK；481 up 使 `agent_id` 可空并把既有约束 `chat_session_agent_id_fkey` 由 `ON DELETE CASCADE` 改为 `ON DELETE SET NULL`（`pg_get_constraintdef` 验证定义）；481 down 恢复 CASCADE + `SET NOT NULL`（迁移 up/down 往返测试全绿）；新增索引均为 `CONCURRENTLY` 且一文件一条；Private Ask 唯一索引谓词已排除 `project_shared`；`CUSTOM.md` 已按当时结构登记本 CR 条目。 |
| AC-20 | FR-17、FR-18 | 当前 workspace 成员对已归档 shared session 的 PATCH/发送返回 409 `chat_session_closed_or_changed`；错误 kind / 跨项目 / 非 workspace 成员的 session 路径返回 404 `chat_session_not_found`；不得写入其他项目或其他 kind 的 session。消息列表对已归档 shared session 仍 200。 |
| AC-21 | FR-9、NFR-9 | 配置解析与协办入队的 catalog / waitable / blocked 判定复用 CR-2026-056 单一实现（`ResolveChatConfig` / `LoadChatCatalogForConfig`）；测试不得再复制第二套规则表。 |
| AC-22 | NFR-6、NFR-7 | Team Agent GET 仍不创建 Issue；Private Ask creator-only 夹具全绿；`go test ./server/internal/handler/ ./server/internal/service/ -count=1` 不新增与 Discussion 无关的失败。 |
| AC-23 | FR-22 | `GET .../messages`（shared）无 cursor 时 200 且 body 为分页对象（含 `messages`/`limit`/`has_more`），不是裸数组；`limit=0` 或只给 `before_id` 返回 400 `invalid_cursor`。页内 `created_at` 非递减。 |
| AC-24 | FR-22 | `POST .../messages`：空 content 且无附件、或 `attachment_ids` 含重复 UUID、或非法 `coordinator_request` → 400 `invalid_discussion_message` 且无新 message/task。仅附件、content 为空 → 201 且 `task_id` 为 null。成功状态码为 201。 |
| AC-25 | FR-23 | merge-forward 同时给非空 `comment_ids` 与 `message_ids` → 400 `invalid_merge_forward_selection` 且 Team Agent 侧无新 comment/task。`message_ids` 含他项目 / Private Ask / 另一 session 的 id → 400 `invalid_message_selection`。重复 `message_ids` 只产生一条合并 comment。 |
| AC-26 | FR-24 | Discussion `POST .../messages` 缺 `Idempotency-Key` → 400 `idempotency_key_required` 零写入。同一 key+同一指纹重试（含响应丢失后重放）→ 两次都 201 且 `message_id`/`task_id` 相同，附件不返回 409 `attachment_already_bound`，DB 仍一条 message。同一 key 不同 content → 409 `idempotency_key_reused` 零写入。并发同一 key 只提交一次。 |
| AC-27 | FR-24、FR-23 | `message_ids` merge-forward 缺 `Idempotency-Key` → 400 `idempotency_key_required`。同一 key 重放 → 201 且同一 `comment_id`/`task_id`，Team Agent 侧不新增第二对 comment/task。legacy `comment_ids` 不带该头仍可 201。 |
| AC-28 | FR-25 | 非本 workspace 成员：`GET /discussion` 403 `forbidden_project_discussion`；持有 `session_id` 的消息 GET/POST 与 PATCH → 404 `chat_session_not_found`；已发送附件下载 404 且无文件字节。已被移出 workspace 的旧成员（member 行删除，挂接平台已有 revoke-member 事务）即时失去上述能力。 |
| AC-29 | FR-25、FR-20 | 非 workspace 成员 / 已被移出 workspace 的成员订阅 shared session 实时通道被拒绝；移出 workspace 后服务端退订（挂接平台已有 revoke-member 事务与退订机制），后续 shared 消息/task 事件不再投递给该用户。成员 B 仍能收到。夹具：handler 或 realtime 测试，命令 `go test ./server/internal/handler/ ./server/internal/service/ -count=1`。 |
| AC-30 | FR-26 | 首次绑定 Coordinator：settings 与 active session.`agent_id` 同 UUID；若 `base_*` 为空则被补写为该 Agent 当时默认。替换为另一 Agent：session.`agent_id` 更新，`base_*` 不变；已入队 task 的 `agent_id` 与 `chat_config` 不变。解绑：session.`agent_id` 为空，历史消息仍可读。 |
| AC-31 | FR-26、FR-11 | Coordinator Agent 归档后：GET `coordinator_agent_id` 仍为原 UUID；新的 @mention/analyze 返回 409 `discussion_coordinator_unavailable` 且不建 task；settings 不被 GET 清掉。Agent hard-delete 后的完整验收见 AC-32。并发 settings PATCH 与 GET 后 session.`agent_id` 与 settings 一致。 |
| AC-32 | FR-7、FR-21、FR-26 | Coordinator Agent 行 hard-delete 后：`chat_session` 行与历史 `chat_message` 行**全部保留**（FK 置 NULL 不级联删除）；session.`agent_id` 为 NULL（投影置 NULL）；GET `/discussion` 的 `coordinator_agent_id` 仍返回 settings 原 UUID；消息列表 GET 仍 200 且可完整回放删除前的历史；新 @mention/analyze 409 `discussion_coordinator_unavailable` 零写入。删除事务只移除 agent 行并把 session.`agent_id` 置 NULL，不留半成品、不触碰消息与设置。 |

来源文档完成标志要求 AC-16 至 AC-22 全部满足；上表 AC-1 至 AC-7 对应来源这七条，AC-8 至 AC-22 覆盖同一闭环中必须可测、但来源完成标志未逐条编号的规则（索引撞车、可空 agent、错误码、前端降级、依赖复用）；AC-23 至 AC-31 覆盖此前评审轮次 B-HTTP-1/B-HTTP-2/B-IDEMP-1/B-ACL-1/B-COORD-1 关闭的契约闭合，重生成后全部保留；AC-32 覆盖 cycle 1 第 3/3 轮 blocker B-COORD-2 的 hard-delete FK 生命周期与回放验收。

## 6. 成功指标

- 打开 Discussion、发送普通消息、上传附件、请求 Coordinator 产生新工作 Issue（含 `project_discussion`）的次数为 **0**。
- 普通 Discussion 消息创建 Agent task 的比例为 **0**。
- 明确协办任务 **100%** 满足 `chat_session_id` 非空且 `issue_id` 为空。
- 同一项目 active `project_shared` session 数 = **1**，且与 Private Ask active session 可并存。
- 发送前未绑定附件被非上传者读取的次数为 **0**。
- 非当前 workspace 成员成功读取 shared 消息、已发送附件或实时事件的次数为 **0**。
- Private Ask 非创建者成功读取或 PATCH 的次数为 **0**。

## 7. 范围排除

以下内容明确不做，归属后续 CR 或明确非目标：

- 多个长期 Discussion Agent 和 `discussion_participant` 表（来源 CR-B 不包含；AC-29）。
- Discussion 到工作 Issue 或 CR 的显式升级（来源 CR-C；来源 AC-23 至 AC-27）。
- 历史 `project_discussion` 全量迁移到 `chat_message`。
- Team Agent 的配置和发送内核（来源 CR-A 已交付；本 CR 只做 Discussion 侧转投入参适配）。
- CR-2026-056 KG-1 / KG-2。
- 发送框整体视觉重构、对齐普通非项目聊天 composer（来源 CR-D）。
- 多个 active Team Agent 主题或完整 thread 列表。
- 给 `agent_task_queue` 增加模型和 Thinking Mode 专用列。
- 把 `/compact` 作为普通用户消息发送。
- 在 Multica 服务端复制 CR 状态机或直接写 knowledge-base 的 `_backlog.yml`。
- 自定义 promotion 表；复制一套独立 Discussion 消息表。
- mobile 端。
- 项目级成员模型（per-project member 子系统）。KB 延期清单第 10 项已列为未来引入项；本 CR 成员口径为「项目成员 := 当前 workspace 成员」（FR-25），项目级成员模型另行 CR。
- `../tools/` 仓改动。

## Discussion 显式升级（v0.34 · CR-2026-061）

## 1. 概述

### 1.1 问题陈述

CR-2026-059（CR-B）已把 Discussion 改为项目级 shared `chat_session` / `chat_message`，打开、发送、附件、Coordinator 协办均不再创建隐藏 Issue。但 Discussion 目前没有任何「把讨论内容变成正式工作」的出口：

- 没有「转为工作 Issue」端点或前端入口；用户要把讨论内容落成工作项只能手工开 Issue 并手工复制内容。
- 即使将来人工复制，目标 Issue 与来源 session / 消息 / 附件之间没有任何引用关系，无法回溯。
- 没有幂等保障：同一批消息被两次升级会创建两个重复 Issue；网络重试语义未定义。
- 「升级为 CR」路径不存在：来源文档 §10.2 要求升级只准备来源上下文并进入现有 `requirement-register`，Multica 不得写 CR 账本——目前该边界没有代码约束，也没有触发入口。
- `issue.context_refs`（`001_init.up.sql`：`JSONB NOT NULL DEFAULT '[]'`）在响应中已读出（`handler/issue.go`），但全仓没有结构化写入路径，前端 schema 也未暴露。

以上事实已在来源文档 §10 / §14 记录，并在本 CR 落笔前按 multica trunk `78e14082`（CR-2026-059 与 CR-2026-045/053 的 Runner、pipeline 投影均已合入，含 AIFI-21/AIFI-22 与 upstream 主线）复核（见 §1.4）。本 CR 只做 Discussion → 工作 Issue 的显式升级与来源追溯，不改 CR-B 已交付的 Discussion 会话内核，不自动升级，不迁移历史。

### 1.2 解决方案摘要

在 Discussion 上增加唯一的显式升级出口：

```text
Discussion shared session
  -> 用户选择消息和附件
  -> 显式点击「转为工作 Issue」
  -> 创建正式 Issue + 写入来源引用（issue.context_refs）
  -> 重复升级 / 重试返回同一个目标 Issue
  -> 原 Discussion 消息与附件保持原归属，不移动、不删除、不复制

「升级为 CR」（A 口径，Ray 已拍板）
  -> 先得到目标 Issue + 来源上下文
  -> 同事务预建一条 requirement-authoring pipeline run（cr_id=NULL、issue_id=目标 Issue，
     携带注册意图与来源上下文；不创建 agent_task_queue 行）
  -> knowledge-base 的 requirement-register 注册时按 issue_id/pipeline_id 定位并复用该 run
  -> CR 注册与状态机仍由 knowledge-base 完成
  -> Multica 不写 CR 账本、不复制状态机
```

本 CR（来源文档 CR-C，注册摘要已拍板）交付一个可独立验收的闭环：

1. 只有用户显式执行升级操作才创建正式工作 Issue；打开、发送、附件、协办均不得创建（FR-22）。
2. 升级请求携带所选消息与附件，服务端校验它们同属当前项目 active shared session。
3. 创建正式 Issue，并把规范化来源集合写入 `issue.context_refs`；原消息与附件归属不变（FR-23）。
4. 以「规范化来源集合 + 项目级并发锁 + 幂等记录」保证同一来源集合只产生一个工作 Issue；重试返回已创建的目标 Issue（FR-24）。
5. 工作 Issue 可回溯来源 session、消息与附件。
6. 「升级为 CR」只准备来源上下文并预建一条 `requirement-authoring` pipeline run（`cr_id=NULL`），knowledge-base 注册时按 `issue_id`/`pipeline_id` 定位并复用该 run（FR-10 配套点）；Multica 不写 `_backlog.yml` 等 CR 账本（FR-25 / AC-27）。
7. 一期不新增 `discussion_promotion` 表，除非实现验证表明现有 `context_refs` 与并发锁无法满足幂等与审计（来源文档 §10.1）。

### 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

提供 Discussion 到正式工作 Issue 的显式升级出口：用户选择消息和附件并显式执行「转为工作 Issue」后创建正式 Issue，保存来源 session/消息/附件引用，原消息与附件保持原归属；以规范化来源集合与项目级并发锁保证重复升级不产生重复 Issue，重试返回既有目标 Issue。「升级为 CR」只准备来源上下文并预建一条 `requirement-authoring` pipeline run（`cr_id=NULL`，A 口径），knowledge-base 注册时按 `issue_id`/`pipeline_id` 定位并复用该 run；Multica 不写 CR 账本。

不含自动升级、原消息/附件移动删除或静默复制、Discussion 多主题与多 Agent 参与者模型、新增 `discussion_promotion` 表（除非验证表明现有引用与锁不足）。依赖已归档 CR-2026-059 的 shared Discussion session、消息与附件来源，以及现有 Issue 创建能力和 knowledge-base 的 `requirement-register` 流程。

目标仓库为 sibling `../multica/`。knowledge-base 承载本 PRD 与来源文档；`../tools/` 除 FR-10 配套点（requirement-register 消费预建 run 的注册流程协同）外无实施改动；本 CR 回退转换（`requirement-approved -> drafting`，trigger `write-tech-design:prd-blocker -> write-requirement-prd`）已作为治理变更落地 tools trunk（`49c46dd`，AIFI-17 拍板）。

`target-version` 继承 `cr.md` 的 `0.34`（注册阶段已确定），本文件不得改写该字段。`target-spec-id` 为 `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

### 1.4 当前代码事实（落笔前核实）

基线：multica trunk `78e14082845f7fb19f33a356169349b07042c04b`（= origin/main；含 CR-2026-059 Discussion shared session、CR-2026-045/053 Runner 与 pipeline 投影、AIFI-21/AIFI-22 及 upstream 主线；本 CR 的 multica requirement worktree 已同步至该 SHA）。tools trunk `49c46dd`（含 AIFI-17 拍板的 `requirement-approved -> drafting` 回退转换）。以下结论均在该 SHA 上核实。

| 结论 | 证据 |
|---|---|
| Discussion 已是 shared session，不再懒创建隐藏 Issue | `handler/project_chat.go` `GetProjectDiscussion`（L233）；服务层注释「EnsureProjectDiscussionIssue is no longer called from this path」（L231） |
| `chat_session.kind` 已交付 | `server/migrations/496_chat_session_kind.up.sql`：`ADD COLUMN kind TEXT NOT NULL DEFAULT 'private'`（CR-2026-059 TASK-01） |
| Discussion 消息为 `chat_message`，附件可绑 session/message/task | `033_chat.up.sql`（`chat_message` 表）；`083_attachment_chat_columns.up.sql`；`164_attachment_task_id.up.sql` |
| `issue.context_refs` 存在但无写入路径 | `001_init.up.sql` L67：`context_refs JSONB NOT NULL DEFAULT '[]'`；`handler/issue.go`（L877/L968 读出）；`pkg/db/queries/issue.sql` 无 context_refs 写入语句；前端 `packages/core/api/schemas.ts` 无对应字段 |
| Idempotency-Key 基础设施已存在 | `server/pkg/publicapi/v1/foundation.go` L4/L6：`HeaderIdempotencyKey = "Idempotency-Key"`、`MaxIdempotencyBytes = 255`；CR-B 幂等表 `501-504_chat_idempotency*`（scope 枚举 `discussion_message`/`merge_forward_messages`，含 `response_status`/`response_body` 回放能力） |
| 项目级 advisory lock 先例已存在 | `service/project_chat.go` `ensureContainerIssueLocked` 经 `qtx.LockIssueDuplicateKey(ctx, lockKey)`（L110-111），锁键 `prefix|workspace|project`；`projectChatSessionAdvisoryKey(workspaceID, projectID)`（L452） |
| 旧 `project_discussion` Issue 保留只读 | `service/project_chat.go` `EnsureProjectDiscussionIssue`（L58）仍在，仅供历史容器路径；新路径不调用（L231） |
| 前端 Discussion 面板已走 shared session | `packages/views/projects/components/discussion-pane.tsx`（CR-B 交付，携带 `session_id` 渲染分页消息） |
| pipeline task 创建三守卫（A 口径据此改道） | db `CreatePipelineTask`（`server/pkg/db/queries/agent.sql` L629）：① `JOIN cr` 要求同 workspace 的 CR 行已存在；② 来源 task 行须 `originator_source`/`originator_user_id` 非空且 `issue_id IS NOT NULL`；③ 执行者 agent 须同 workspace active 且 `runtime_id` 非空。任一守卫失败插入 0 行。服务层入口已演进为 `EnqueuePipelineTask`（`server/internal/service/task.go` L399）。promotion 是成员 HTTP 端点：无 source task、CR 尚未注册 → 该查询必然 0 行，v0.2 的「复用 CreatePipelineTask」不可用，v0.3 按 A 口径改道 |
| Multica 无 requirement-authoring orchestrator | `server/internal/governance/runner.go` `HandleStartArchitecture`（L845）仅接受 `pipeline_id=architecture-design`，其它 pipeline_id 返回 `RUNNER_UNSUPPORTED_PIPELINE`（L31） |
| `pipeline_run`/`pipeline_node_run` 唯一写路径是状态事件投影 | 无 sqlc INSERT 查询（全仓 grep 零命中，仅 `maturity.sql` 读取）；写路径为 `server/internal/governance/gate_projection.go` 内联 SQL：`findOrCreateRun`（L125，按 `(workspace_id, cr_id, pipeline_id)` 查非终态 run，无则新建）、`upsertNodeRunning`（L175）、`markNodePassed`（L199）、`applyReview`（L279）。由 crctl 状态事件驱动（`crsync.go` L451/L466 `projectGateTransition`，仅真实状态变更触发）；requirement-authoring 的 run 在 CR 进入 `requirement-reviewing`/`requirement-approved` 时才由投影创建（`pipelineForStatus`，L27） |
| `pipeline_run` 表结构支持预建 run（A 口径） | `451_aifirst_pipeline_runs.up.sql`：`cr_id TEXT` 可 NULL（规划类 pipeline 无 CR）、`issue_id UUID`（`ON DELETE SET NULL`）、`inputs`/`execution_context` JSONB、`started_by UUID NOT NULL`；`pipeline_node_run` 含 `UNIQUE (run_id, node_id, attempt)`、`kind CHECK ('skill','human_approval','code_generation')` |
| pipeline run/task 唯一性 guard 先例 | `456_pipeline_run_architecture_active_unique.up.sql`：`(workspace_id, pipeline_id, cr_id)` 部分唯一索引（`cr_id IS NOT NULL` 且 status active——run 绑定 CR 后防重复的 DB 保障）；`457_agent_task_pipeline_node_active_unique.up.sql`：`agent_task_queue(pipeline_node_run_id)` 部分唯一索引（active 状态仅一条） |
| 节点 id 由 pipeline 模板确定 | `server/internal/governance/gate_nodes_gen.go`（自 tools pipeline-templates 生成）：requirement-authoring 已注册（review skill 节点 seq4、human_approval seq5）；首节点 `requirement-register` skill 节点 id `00000000-0000-0000-0011-000000000001`（seq 1） |
| task 绑定先例 | `handler/cr_bind.go` `HandleBindCurrentTask`（`POST /api/crs/{crID}/bind-current-task`）——A 配套点 run 绑定通道的同族先例 |
| `chat_idempotency` 幂等键作用域 | `502_chat_idempotency_scope_key_unique.up.sql`：唯一键 `(workspace_id, user_id, scope_type, scope_id, key)`；`501_chat_idempotency.up.sql`：`scope_type` CHECK 仅 `('discussion_message','merge_forward_messages')`——本 CR 新增 `discussion_promotion` scope 需扩展该 CHECK（迁移号 ≥ 505） |
| 固定错误体 `{code, error}` 与 502 先例 | `handler/handler.go` `writeErrorCode`（L578，固定 code+error 字段）；`handler/project_chat.go` `writeProjectChatSendError`（L612）默认分支：事务已整体回滚后统一 502 `enqueue_failed`（L638） |
| CR-B 项目路径成员门禁口径 | `handler/project_chat.go` `GetProjectDiscussion`（L233）成员门禁（SDD §3.1/FR-25）：项目路径（project 存在性已确认）非成员返回 **403** `forbidden_project_discussion`；**404 `chat_session_not_found` 只用于 session 级失败**（不存在/跨项目/归档） |
| 当前最大迁移编号 | **504**（`504_idx_chat_idempotency_created.up.sql`） |
| CR 注册与状态机在 knowledge-base，不在 Multica | KB `dir-graph.yaml#repositories`；`../tools/` 的 `requirement-register` Skill 经 `crctl register` 深原语写 `change-requests/`；Multica 无该账本写入路径 |

### 1.5 修订记录

- 初稿（2026-09-07）：按来源文档 CR-C 段与注册摘要起草，代码事实在 multica trunk `b5bf30ca` 核实。
- v0.2（2026-09-07）：按 review-requirement 第 1 轮 BLOCK（B-API-01~04）定点修复：①按分支拆分默认/`upgrade_to_cr=true` 条件副作用，明确 pipeline task 输入/响应、同事务边界、失败 502 零残留与唯一 task 语义（FR-10、契约、AC-8）；②定义 canonical fingerprint 算法、key 作用域与输入限制，确定 key 冲突优先于来源查重的确定性规则（FR-6/FR-7、契约、AC-5）；③权限判定固定为四步顺序，成员缺失唯一 403、session 级失败唯一 404，AC-6 与之一致（FR-8）；④补齐逐类错误闭包表（状态/固定 code/错误体/零写入范围/客户端动作）（FR-3/FR-13、契约、AC-2/AC-11）。
- v0.3（2026-09-08）：按 Ray 拍板的 A 口径（write-tech-design 预检发现 FR-10 在 multica `78e14082` 上无法机械满足）定点修订：①FR-10/HTTP 契约「副作用」「成功响应」「幂等与查重优先级」「错误闭包」/AC-8 改为预建 `requirement-authoring` pipeline run（`cr_id=NULL`、`issue_id=目标`、`started_by=调用者`，`inputs`/`execution_context` 携带注册意图与来源上下文）+ 首节点 `pipeline_node_run`，不创建 `agent_task_queue`；响应以 `run_id`（pipeline_run.id）替代 v0.2 的 task id 字段；失败语义改为 502 `pipeline_run_create_failed`（其它事务失败 500 `internal_error`），均整体回滚零残留；②补齐 A 配套点消费契约（knowledge-base 注册按 `issue_id`/`pipeline_id` 定位并绑定复用预建 run，绑定失败=注册技术失败，同一 promotion 至多一条 run，新增 AC-13）；③§1.4 基线刷新至 multica `78e14082`（迁移号整体 +14：`chat_session_kind` 496、`chat_idempotency` 501–504、最新 504 → promotion scope CHECK ≥ 505；`CreatePipelineTask` 服务层入口演进为 `EnqueuePipelineTask`（task.go L399）+ db 三守卫（agent.sql L629）；`writeErrorCode` 实际位于 handler.go L578；pipeline run 写路径=gate_projection.go 状态事件投影、无 sqlc INSERT；唯一性 guard 451/456/457）。

## 2. 用户故事

- **US-1 讨论参与者**：作为项目成员，我希望选中讨论里的一段消息和附件后点「转为工作 Issue」，就能得到一个可执行的工作项，而不是手工复制粘贴。
- **US-2 讨论参与者**：作为项目成员，我希望升级后的 Issue 上能看到它来自哪次讨论、哪些消息、哪些附件，审计时有据可查。
- **US-3 讨论参与者**：作为项目成员，我希望重复点击升级或网络重试不会产生一堆重复 Issue，返回的始终是同一个目标 Issue。
- **US-4 原消息读者**：作为项目成员，我希望升级动作不搬走、不删掉、不复制我在 Discussion 里的消息和附件，它们还留在原处。
- **US-5 项目 owner/admin**：作为项目负责人，我希望「升级为 CR」走现有 requirement 流程，Multica 服务端不会越过边界直接去改知识库的 CR 账本。
- **US-6 未授权成员**：作为没有 Issue 创建权限的成员，我希望能看到讨论，但升级入口对我关闭或返回明确错误，不会悄悄越权创建。

## 3. 功能需求

### FR-1 只有显式升级才创建工作 Issue

打开 Discussion、发送普通消息、上传附件、请求 Coordinator 协办、读取消息列表，均不得创建任何工作 Issue（含 `origin_type='project_discussion'` 的历史容器）。唯一创建正式工作 Issue 的路径是用户显式执行「转为工作 Issue」。来源 FR-22、AC-23。

### FR-2 升级入口契约

新增 `POST /api/projects/{projectId}/discussion/promote`。完整 HTTP 契约见下节「Discussion promotion HTTP 契约」。创建正式 Issue 使用现有 Issue 创建能力，禁止为升级另建一套 Issue 写入路径。

### FR-3 来源选择校验

请求体 `message_ids` 与 `attachment_ids` 必须满足：均为 UUID 字符串数组（元素非 UUID 或类型非字符串数组即拒绝）；至少一个 message 或一个 attachment（两数组同时为空即拒绝）；无重复 UUID；全部消息属于当前项目唯一的 active `project_shared` session（即 Discussion GET 返回的 `session_id`）；全部附件已绑定到该 session 的 `chat_message`（发送成功后的附件，不是未绑定草稿）。以上任一失败返回 400 `invalid_promotion_selection`，零写入。`session_id` 缺失/非 UUID 返回 400 `invalid_promotion_selection`；`title` 非字符串或超 200 字符返回 400 `invalid_promotion_title`；`description` 非字符串或超 10,000 字符返回 400 `invalid_promotion_description`。来源 §10.1。错误码、错误体与客户端动作的完整映射见 HTTP 契约「错误闭包」表。

### FR-4 创建 Issue 并写入来源引用

校验通过后创建正式 Issue，并把规范化来源集合写入 `issue.context_refs`（JSONB 数组，条目至少含 `session_id`、`message_ids[]`、`attachment_ids[]`、`promoted_by`、`promoted_at`）。`message_ids`/`attachment_ids` 为排序去重后的 UUID 列表。`upgrade_to_cr=true` 且 pipeline run 创建成功后，条目额外回写 `pipeline_run_id`（同一事务，FR-10）。目标 Issue 的标题、描述可由用户提供；未提供时服务端生成默认值（标题含项目名与升级时间，描述含来源消息摘要）。来源 FR-23、AC-26。

### FR-5 原 Discussion 消息与附件保持原归属

升级不得移动、删除、复制或改绑原 `chat_message` 与附件；附件仍绑定原 `chat_session_id`/`chat_message_id`；Discussion 消息流与附件列表不因升级发生变化。来源 FR-23、AC-24。

### FR-6 幂等：同一来源集合只产生一个工作 Issue

以规范化来源集合作为查重键：`session_id`（小写 UUID 规范形式）+ 排序去重后的 `message_ids` + 排序去重后的 `attachment_ids`。服务端在项目级并发锁下先查后建：已存在以该来源集合升级的目标 Issue 时直接返回它（`created=false`），不创建新 Issue、不覆盖既有 Issue 的 `title`/`description`（这两个字段只在首次创建时生效，不参与指纹与查重）。并发同源升级必须收敛到同一目标 Issue。来源 FR-24、AC-25。

**判定优先级（确定性规则）**：在项目级并发锁内，同 key 指纹冲突检查（FR-7，409）先于来源查重命中（本 FR，返回既有 Issue）；两者都不命中才创建。组合规则（含 `upgrade_to_cr`）见 HTTP 契约「幂等与查重优先级」表。

### FR-7 幂等键：canonical fingerprint 与重放语义

**指纹算法（canonical fingerprint）**：对请求做规范化后取 SHA-256：`projectId`、`session_id` 统一为小写 UUID 字符串；`message_ids`/`attachment_ids` 排序去重；`upgrade_to_cr` 规范为布尔值（缺省 false）。按固定键序 JSON 序列化后计算：

```text
fingerprint = SHA256(hex) of canonical JSON:
{"projectId":"<小写>","session_id":"<小写>","message_ids":[排序去重小写],"attachment_ids":[排序去重小写],"upgrade_to_cr":true|false}
```

`title`/`description` **不参与指纹**：同一来源集合不同标题/描述不构成指纹差异，也不构成查重差异（见 FR-6），标题/描述只在首次创建时生效。

**key 作用域**：`Idempotency-Key` 的作用域为 `(workspace_id, user_id, scope_type='discussion_promotion', scope_id=project_id, key)`，复用 CR-B `chat_idempotency` 表（新增 `discussion_promotion` scope，需扩展 scope CHECK 约束，迁移号 ≥ 505）。同一 key 在不同项目、不同调用者之间互不影响。

**key 输入限制**：必填、非空、≤ 255 字节（`pkg/publicapi/v1/foundation.go` `MaxIdempotencyBytes`）。缺失返回 400 `idempotency_key_required`；空串/纯空白/超 255 字节返回 400 `invalid_idempotency_key`。

**重放语义**：同 key + 同指纹重放（含响应丢失后重试）→ 201 且回放首次响应（`created=false`，`upgrade_to_cr=true` 时回放首次返回的 `run_id`，不新建 run）；同 key + 不同指纹 → 409 `idempotency_key_reused`，零写入（优先级先于 FR-6 查重）。同源不同 key 的重试经 FR-6 的查重返回同一目标 Issue；若先普通升级（`upgrade_to_cr=false`）后以新 key 再发 `upgrade_to_cr=true`，返回同一目标 Issue 并只补建一次 pipeline run（FR-10）。

### FR-8 权限边界（固定判定顺序）

权限相关判定按下列固定顺序执行，每一步失败即返回、零写入，前面步骤不依赖后面步骤的结果（因此同输入只产生唯一响应）：

1. **项目解析**：`projectId` 非 UUID → 400 `invalid_project_id`；UUID 合法但 workspace 内无此项目 → 404 `project_not_found`。
2. **成员门禁**：非 workspace 成员 / 已被移出 workspace → 403 `forbidden_promotion`（项目路径口径：project 存在性已在第 1 步确认，与 CR-B `GetProjectDiscussion` 成员门禁 403 保持一致；不向非成员透露 session 存在性）。
3. **Issue 创建权限**：workspace 成员但不具备现有 Issue 创建权限（沿用现有 Issue 权限口径，不新造权限模型）→ 403 `forbidden_promotion`。
4. **session 解析**：session 不存在 / 不属于本 project / `kind` 非 `project_shared` / 已归档或非 active → 404 `chat_session_not_found`（口径与 CR-B session 路径一致；仅 session 级失败用 404）。

以上 1–4 步全部零写入。发起升级不要求 Coordinator 或 Agent 配置；纯人类 Discussion 同样可升级（FR-11）。

### FR-9 工作 Issue 可回溯来源

目标 Issue 详情与 API 响应可读到来源 `session_id`、消息与附件引用（经 `context_refs` 解析），前端在 Issue 详情页展示「来自 Discussion 升级」的来源入口，可跳转回 Discussion 定位消息。来源 AC-26。

### FR-10 升级为 CR：预建 pipeline run，不写 CR 账本（A 口径）

「升级为 CR」复用 FR-2 的 promotion 得到目标 Issue 与来源上下文，随后在 Multica 侧预建一条 `requirement-authoring` pipeline run 作为注册意图的 run 事实（A 口径；v0.2 的「复用 `CreatePipelineTask` 创建 pipeline task」在 multica trunk `78e14082` 上被 db 三守卫机械拒绝：cr 行 JOIN 要求 CR 已存在、来源 task 要求 `originator_source`/`issue_id` 非空、执行者 agent 要求 active+runtime 绑定——promotion 是成员 HTTP 端点，无 source task 且 CR 尚未注册，见 §1.4）。CR 注册（`crctl register` / `requirement-register`）与状态机仍在 knowledge-base 由 requirement 流程完成。Multica 服务端代码不得读写 knowledge-base `_backlog.yml` / `_history.yml` / `cr.md`，不得复制 CR 状态机与门禁。来源 FR-25、AC-27。

**条件副作用与事务边界（`upgrade_to_cr=true` 分支）**：

- 预建 run 行（`pipeline_run` + 首节点 `pipeline_node_run`）与目标 Issue、`context_refs`、幂等记录在**同一 DB 事务**内写入；事件通知（`issue:created` 等）在**事务提交后**按现有事件模式发出，提交前不得泄漏。
- `pipeline_run` 行：`pipeline_id='requirement-authoring'`、`cr_id=NULL`、`issue_id=目标 Issue`、`status='running'`、`started_by=调用者`（满足 `started_by NOT NULL` 约束）；`inputs` 携带来源上下文（`session_id`、排序去重的 `message_ids`/`attachment_ids`、`promoted_by`/`promoted_at`），`execution_context` 携带机器可读的注册意图标记（含 `intent: discussion-promotion`；字段形状由 SDD 定，必须机器可读且幂等可重放）。
- 首节点 `pipeline_node_run`：requirement-authoring 模板第 1 节点（`requirement-register` skill 节点，`node_id=00000000-0000-0000-0011-000000000001`、`kind='skill'`、`seq=1`、`attempt=1`、`status='running'`）。
- **不创建 `agent_task_queue` 行**：本端点没有 source task，`CreatePipelineTask` 的执行者解析与 attribution 语义不适用；run 的后续节点状态仍由 knowledge-base 注册后的 crctl 状态事件投影驱动（沿用现有投影路径，§1.4）。
- run 创建失败（含 run/首节点写入失败、执行上下文校验失败、DB 失败）→ **整个事务回滚** → 502 `pipeline_run_create_failed`，**零残留**（无 Issue、无 `context_refs`、无幂等记录、无 run 行）；客户端动作：以同一 key 整体重试（FR-7 幂等安全）。锁/死锁/连接失败等其它事务失败 → 500 `internal_error`，同样整体回滚零残留（见错误闭包表）。
- **唯一的 run 语义**：每个目标 Issue 至多创建一条 `requirement-authoring` pipeline run。同 key 同指纹重放回放首次返回的 `run_id`；同源不同 key 的请求在锁内查重命中后：既有 `context_refs` 条目已含 `pipeline_run_id` → 直接返回该值；未含（先普通升级后升级为 CR）→ 在同一事务内补建一次并回写 `pipeline_run_id`。并发同源升级为 CR 在项目级锁下串行化，第二个请求只会拿到已存在的 run，不建第二条。
- promotion 的 HTTP 响应额外携带 `run_id`；CR 注册结果不在本端点返回（异步由 requirement 流程产出），Multica 不轮询也不写 CR 账本。

**A 配套点：预建 run 的消费契约（knowledge-base 侧识别与复用，可评审）**：

- **识别键**：`{workspace_id, pipeline_id='requirement-authoring', issue_id=目标 Issue, cr_id IS NULL, status='running'}`。promotion 响应与目标 Issue 的 `context_refs` 条目均携带 `pipeline_run_id`，供注册侧定位。
- **传播**：用户从升级结果进入现有 requirement 注册入口时，注册上下文携带 promotion 的 `issue_id` 与 `run_id`（由升级响应与目标 Issue `context_refs` 读取；`requirement-register` 的 promotion 上下文为可选输入，缺失时按普通注册处理）。
- **绑定（复用）**：`requirement-register` 注册产生 CR-ID 后，经 Multica 服务端受控绑定通道（与 `bind-current-task` 同族的 run 绑定端点，端点与鉴权由 SDD 设计）将该预建 run 的 `cr_id` 由 NULL 更新为新 CR-ID。绑定必须幂等，且仅允许 `cr_id IS NULL` 的 promotion 预建 run 被绑定一次（已绑定的 run 拒绝二次绑定）。绑定完成后，Multica 现有 cr 状态事件投影（`gate_projection.findOrCreateRun` 按 `cr_id` 命中同一 `status='running'` run）复用该 run，不新建；`456` 部分唯一索引同时保证绑定后不会出现第二条 active run。
- **失败语义**：绑定失败（run 不存在/已被消费/服务不可达）→ `requirement-register` 按技术失败停止并报错，可经 `registration_key` 幂等重试；绑定完成前该 CR 不得推进到 `requirement-reviewing`。任何情况下同一 promotion 至多存在一条 `requirement-authoring` run（`cr_id` 为 NULL 或绑定后的 CR-ID，始终同一行）。
- **普通注册**（无 promotion 上下文）不定位不绑定，走现有投影路径（进入 `requirement-reviewing` 时由投影新建 run），行为与现状一致。
- **未消费的预建 run**：用户升级为 CR 后从未发起注册时，run 保持 `cr_id=NULL`、`status='running'` 原状，不影响任何现有路径；其过期与清理策略不在本 CR（见范围排除）。

### FR-11 前端交互

`discussion-pane.tsx` 提供多选消息与附件的交互，以及「转为工作 Issue」「升级为 CR」两个显式操作入口（样式复用现有 Discussion 面板与 Issue 创建弹层，不新造组件体系）。升级成功后展示目标 Issue 链接并保留 Discussion 内容不变；失败时保留选择状态并展示错误，可重试。未配置 Coordinator、纯人类 Discussion 同样可用升级入口。

### FR-12 不新增 `discussion_promotion` 表（默认）

一期默认复用 `issue.context_refs` + 项目级并发锁 + 幂等记录实现 FR-6/FR-7 的查重与审计。仅当实现验证（可复现的并发/查询测试）表明现有机制无法可靠满足「同源唯一」与「审计可查」时，才允许引入最小 `discussion_promotion` 表，且必须在 SDD 中附验证证据说明为何 context_refs 不足。来源文档 §10.1。

### FR-13 可区分错误与零残留

升级请求失败（校验失败、权限失败、key 冲突、并发/锁/数据库/事务失败、pipeline run 创建失败）不得留下半成品 Issue、半写 `context_refs`、半绑定附件或孤立幂等记录。错误体固定为 `{ "code", "error" }`（复用 CR-B `writeErrorCode` 形状），逐类错误的 HTTP 状态、固定 code、零写入范围与客户端动作见 HTTP 契约「错误闭包」表；前端按该表可区分并给出正确恢复动作（保留选择 / 换 key / 原 key 直接重试）。500 `internal_error` 与 502 `pipeline_run_create_failed` 均为可安全重试错误（幂等语义保证重试不产生重复 Issue 或重复 pipeline run）。

### Discussion promotion HTTP 契约（可执行，覆盖 FR-2 / FR-3 / FR-4 / FR-6 / FR-7 / FR-8 / FR-10 / FR-13）

```text
POST /api/projects/{projectId}/discussion/promote
```

#### 请求

| 字段 | 类型 | 约束 |
|---|---|---|
| `projectId`（path） | UUID | 非 UUID → 400 `invalid_project_id`；合法但 workspace 无此项目 → 404 `project_not_found` |
| `Idempotency-Key`（header） | string | 必填、非空、≤ 255 字节；缺失 → 400 `idempotency_key_required`；空/纯空白/超长 → 400 `invalid_idempotency_key` |
| `session_id` | UUID | 必填；缺失/非 UUID → 400 `invalid_promotion_selection` |
| `message_ids` | UUID 字符串数组 | 可空；元素非 UUID 字符串或类型非数组 → 400 `invalid_promotion_selection` |
| `attachment_ids` | UUID 字符串数组 | 可空；元素非 UUID 字符串或类型非数组 → 400 `invalid_promotion_selection` |
| `title` | string | 可选；非字符串或超 200 字符 → 400 `invalid_promotion_title` |
| `description` | string | 可选；非字符串或超 10,000 字符 → 400 `invalid_promotion_description` |
| `upgrade_to_cr` | bool | 可选，默认 false；类型错误 → 400 `invalid_request_body` |

`message_ids` 与 `attachment_ids` 不得同时为空、不得含重复 UUID（均 400 `invalid_promotion_selection`）。非法 JSON / 请求体无法解析 → 400 `invalid_request_body`。所有 400/403/404/409 均零写入。

#### canonical fingerprint（FR-7）

```text
fingerprint = SHA256(hex) of canonical JSON（固定键序）:
{"projectId":"<小写 UUID>","session_id":"<小写 UUID>","message_ids":[排序去重的小写 UUID],"attachment_ids":[排序去重的小写 UUID],"upgrade_to_cr":<true|false>}
```

`title`/`description` 不参与指纹（只影响首次创建，见 FR-6）。key 作用域：`(workspace_id, user_id, scope_type='discussion_promotion', scope_id=project_id, key)`。

#### 判定顺序（固定，所有校验零写入，仅最终创建步骤落盘）

1. 请求形态校验（400 类：request 表 + FR-3 形状项）。
2. project 解析（400 `invalid_project_id` / 404 `project_not_found`）。
3. 成员门禁（403 `forbidden_promotion`）。
4. Issue 创建权限（403 `forbidden_promotion`）。
5. session 解析（404 `chat_session_not_found`：不存在 / 跨项目 / 非 `project_shared` / 已归档或非 active）。
6. 来源选择校验（FR-3：400 `invalid_promotion_selection`）。
7. 获取项目级 advisory lock（`prefix|workspace|project`，先例 `projectChatSessionAdvisoryKey`）；锁内：
   1. key 冲突检查（FR-7）：同 key 同指纹 → 回放首次响应（201，`created=false`）；同 key 不同指纹 → 409 `idempotency_key_reused`（**优先级先于查重**）。
   2. 来源查重（FR-6）：同源命中 → 返回既有 Issue（`created=false`）；`upgrade_to_cr=true` 时按 FR-10 补建/复用唯一的 pipeline run。
   3. 均未命中 → 创建 Issue + `context_refs` + 幂等记录（`upgrade_to_cr=true` 另含预建 run 行：`pipeline_run` + 首节点 `pipeline_node_run`，无 `agent_task_queue`），同一事务提交。

#### 成功响应（201）

```json
{
  "issue_id": "<UUID>",
  "issue_number": 123,
  "session_id": "<UUID>",
  "source_refs": { "session_id": "<UUID>", "message_ids": ["<UUID>"], "attachment_ids": ["<UUID>"] },
  "created": true,
  "upgrade_to_cr": false,
  "run_id": null
}
```

- `created=false`：重放或查重命中。重放回放的响应与首次一致（`issue_id`/`source_refs`/`run_id` 同首次），但 `created` 恒为 false（表示本次请求未新建）。
- `upgrade_to_cr=true` 且 pipeline run 已创建/已存在时，`run_id` 为 run UUID，否则为 null（FR-10）。

#### 副作用（按分支拆分，FR-10）

| 分支 | 副作用 | 禁止 |
|---|---|---|
| 默认（`upgrade_to_cr=false`） | 同一事务内：新增 Issue 行 + 写入 `context_refs` + 幂等记录 | 不得创建 comment / task；不得修改 `chat_message`、`attachment`、`chat_session` 行 |
| `upgrade_to_cr=true`（A 口径） | 默认分支全部副作用 + 每个目标 Issue 至多一条 `requirement-authoring` 预建 pipeline run（`pipeline_run`（`cr_id=NULL`、`issue_id=目标`、`started_by=调用者`、`inputs`/`execution_context` 携带注册意图与来源上下文）+ 首节点 `pipeline_node_run` 同事务写入；**不创建 `agent_task_queue` 行**；事件通知在提交后发出） | 同上；不得写 knowledge-base CR 账本；run 创建失败 → 事务整体回滚 → 502 `pipeline_run_create_failed` 零残留 |

#### 幂等与查重优先级（确定性规则）

| 场景 | 结果 |
|---|---|
| 同 key + 同指纹重放 | 201 回放首次响应（`created=false`）；`upgrade_to_cr=true` 回放首次 `run_id`，不新建 run |
| 同 key + 不同指纹（含先普通升级后同 key 再 `upgrade_to_cr=true`；指纹含 `upgrade_to_cr`，必不同） | 409 `idempotency_key_reused`，零写入 |
| 同源不同 key，串行/并发 | 201 返回既有 Issue（`created=false`）；`title`/`description` 不覆盖首次值 |
| 同源不同 key，先普通升级、后 `upgrade_to_cr=true` | 返回同一 Issue；锁内查重命中且 `context_refs` 无 `pipeline_run_id` → 同一事务补建一次 run 并回写；已有 → 返回既有值。**至多一条 pipeline run** |
| 同源不同 key 并发 `upgrade_to_cr=true` | 项目级锁串行化：第二个请求拿到的 `run_id` 与第一个相同 |

#### 错误闭包（逐类：状态 / 固定 code / 错误体 / 零写入范围 / 客户端动作）

错误体统一 `{ "code": "<固定 code>", "error": "<人读文案>" }`。

| 场景 | HTTP | code | 零写入范围 | 客户端动作 |
|---|---|---|---|---|
| 非法 JSON / 请求体无法解析 / `upgrade_to_cr` 类型错误 | 400 | `invalid_request_body` | 全部 | 保留选择，修正后重试 |
| `projectId` 非 UUID | 400 | `invalid_project_id` | 全部 | 停止（调用方 bug） |
| project 不存在 | 404 | `project_not_found` | 全部 | 停止 |
| `session_id` 缺失/非 UUID、数组元素非法、两数组同空、含重复 UUID | 400 | `invalid_promotion_selection` | 全部 | 保留选择，修正后重试 |
| `title` 非字符串/超 200 字符 | 400 | `invalid_promotion_title` | 全部 | 保留选择，修正标题后重试 |
| `description` 非字符串/超 10,000 字符 | 400 | `invalid_promotion_description` | 全部 | 保留选择，修正后重试 |
| `Idempotency-Key` 缺失 | 400 | `idempotency_key_required` | 全部 | 带 key 重试 |
| `Idempotency-Key` 空/纯空白/超 255 字节 | 400 | `invalid_idempotency_key` | 全部 | 换合法 key 重试 |
| 非 workspace 成员 / 已被移出 | 403 | `forbidden_promotion` | 全部 | 展示无权限，不重试 |
| 成员但无 Issue 创建权限 | 403 | `forbidden_promotion` | 全部 | 展示无权限，不重试 |
| session 不存在 / 跨项目 / 非 `project_shared` / 已归档 | 404 | `chat_session_not_found` | 全部 | 刷新 Discussion 后重选 |
| 消息不属于该 session / 附件未绑定该 session 消息（含草稿附件） | 400 | `invalid_promotion_selection` | 全部 | 保留选择，移除非法项后重试 |
| 同 key 不同指纹 | 409 | `idempotency_key_reused` | 全部 | 换新 key 重发（同源由查重收敛） |
| 锁/数据库/事务失败（死锁、超时、连接失败等） | 500 | `internal_error` | 全部（事务回滚） | 原 key 直接重试（幂等安全） |
| `upgrade_to_cr=true` 且预建 pipeline run 创建失败（run/首节点写入、执行上下文校验失败） | 502 | `pipeline_run_create_failed` | 全部（事务回滚） | 原 key 直接重试（幂等安全，不会产生重复 Issue/run） |
| 其它未预期内部错误 | 500 | `internal_error` | 全部 | 原 key 直接重试 |

状态码总集：201（创建/幂等命中）；400/403/404/409/500/502 如上表；**200 不用于本端点**。

#### 验收观察点

- DB：目标 Issue 行 + `context_refs` 含规范化来源集合；Discussion 消息/附件行数与绑定字段升级前后全等。
- 同一来源集合两次升级 Issue 行数只增 1；`chat_idempotency` 存在 `scope_type='discussion_promotion'` 记录且指纹为 canonical fingerprint。
- `upgrade_to_cr=true`：同一目标 Issue 对应的 `requirement-authoring` `pipeline_run` 至多 1 条（`cr_id` 绑定前后同一行）；`agent_task_queue` 无新增行；重放与查重命中均返回相同 `run_id`。
- 错误注入夹具：任一类失败后 Issue 表、`context_refs`、`chat_idempotency`、`pipeline_run`/`pipeline_node_run` 均零残留。

## 4. 非功能需求

- **NFR-1 双端一致**：web 与 desktop 共享 `packages/views` 行为一致；mobile 不在本 CR 范围。
- **NFR-2 四语文案**：新增 UI 文案提供 en/ja/ko/zh-Hans；`packages/views/locales/parity.test.ts` 对新增 key 全绿。
- **NFR-3 复用优先**：复用 `issue.context_refs`、CR-B 的幂等记录模式与 advisory lock 先例、现有 Issue 创建能力与 `pipeline_run`/`pipeline_node_run` 表及投影语义；`upgrade_to_cr` 分支直接写预建 run 行（新增 sqlc INSERT 查询，SDD 落地），不复用 `EnqueuePipelineTask`（三守卫对无 source task 的 promotion 不可用，见 §1.4）；不复制 Discussion 消息表，不新造 Issue 写入路径，默认不新增 `discussion_promotion` 表（FR-12）。
- **NFR-4 并发与事务**：同源并发升级在项目级锁（`prefix|workspace|project`）下收敛到一次创建；升级事务失败零残留（FR-13）；幂等记录、Issue 创建、`context_refs` 与 `upgrade_to_cr=true` 的预建 run 行（`pipeline_run` + 首节点 `pipeline_node_run`，无 `agent_task_queue`）**同一事务提交**，提交后广播 `issue:created` 等现有事件，提交前不得泄漏；事件广播失败不回滚已提交数据。
- **NFR-5 安全**：权限校验服务端强制；不得凭 `session_id` 猜测跨项目读取或升级；`context_refs` 只写入可信来源集合，不接受任意 JSON 注入（由服务端生成，前端不能直接提交任意 `context_refs` 内容）。
- **NFR-6 兼容**：旧 `project_discussion` Issue 仍只读回放；CR-B 的 Discussion GET/发送/协办行为除本 CR 明确新增的 promotion 入口外不得改变；Private Ask / Team Agent 路径不受影响。
- **NFR-7 依赖**：必须使用已归档 CR-2026-059 的 shared session、消息与附件来源事实；「升级为 CR」必须走现有 `requirement-authoring` 流程入口，禁止平行实现；promotion 预建 run 是该升级意图唯一的 run 事实，knowledge-base 注册必须按 FR-10 配套点定位并复用，禁止平行新建第二条 run。

## 5. 验收标准

| ID | 覆盖 FR | 可执行验收 |
|---|---|---|
| AC-1 | FR-1 | 打开 Discussion、发送普通消息、上传附件、请求 Coordinator 后，Issue 表均无新增工作 Issue；只有 promotion 端点成功时才新增。命令：`go test ./server/internal/handler/ ./server/internal/service/ -count=1`。 |
| AC-2 | FR-2、FR-3 | 只选消息、只选附件、消息+附件混合，均 201 且目标 Issue 创建；空选择、含重复 UUID、含未绑定草稿附件、含他项目/Private Ask/另一 session 消息 → 400 `invalid_promotion_selection` 零写入；非法 JSON → 400 `invalid_request_body`；`projectId` 非 UUID → 400 `invalid_project_id`；`session_id` 非 UUID → 400 `invalid_promotion_selection`；`title` 超 200 字符 → 400 `invalid_promotion_title`；`description` 超 10,000 字符 → 400 `invalid_promotion_description`，均零写入。 |
| AC-3 | FR-4 | 目标 Issue 的 `context_refs` 含 `session_id`、排序去重的 `message_ids[]`/`attachment_ids[]`、`promoted_by`/`promoted_at`；未提供 title 时服务端生成默认标题与描述摘要。 |
| AC-4 | FR-5 | 升级前后 `chat_message` 行数、内容、`attachment` 绑定字段（`chat_session_id`/`chat_message_id`）全等；Discussion 消息流与附件列表渲染不变。 |
| AC-5 | FR-6、FR-7 | 同一来源集合串行升级两次：第二次不创建新 Issue，返回与第一次相同的 `issue_id`；同 key+同指纹重放返回同一 Issue 且 `created=false`；同 key 不同指纹 → 409 `idempotency_key_reused` 零写入；同 key 先普通升级（`upgrade_to_cr=false`）后同 key 再发 `upgrade_to_cr=true` → 409 `idempotency_key_reused`（指纹含 `upgrade_to_cr`，必不同）；换新 key 重发 `upgrade_to_cr=true` → 返回同一 Issue 且至多补建一条 pipeline run（`run_id` 与首次/既有值一致）；缺 `Idempotency-Key` → 400 `idempotency_key_required`；空 key/超 255 字节 → 400 `invalid_idempotency_key`。并发同源升级只产生一个 Issue（handler/service 测试夹具）。 |
| AC-6 | FR-8 | 固定判定顺序，同输入唯一响应：非 workspace 成员 / 已被移出 workspace 升级 → 403 `forbidden_promotion`（唯一，不泄漏 session 存在性）；无 Issue 创建权限成员 → 403 `forbidden_promotion`；session 不存在/跨项目/非 `project_shared`/已归档 → 404 `chat_session_not_found`；project 不存在 → 404 `project_not_found`；以上均零写入。 |
| AC-7 | FR-9 | 目标 Issue API 响应可解析出来源 `session_id` 与消息/附件引用；前端 Issue 详情展示「来自 Discussion」来源入口，点击可跳回 Discussion。 |
| AC-8 | FR-10 | `upgrade_to_cr=true`：promotion 成功后同一事务写入预建 `requirement-authoring` pipeline run（`pipeline_run`：`cr_id=NULL`、`issue_id=目标 Issue`、`started_by=调用者`、`inputs`/`execution_context` 携带注册意图与来源上下文 + 首节点 `pipeline_node_run`），不创建 `agent_task_queue` 行，响应返回 `run_id`；同一目标 Issue 至多一条 run（同 key 重放返回同一 `run_id`；同源不同 key 第二次升级为 CR 不新建，至多补建一次并回写 `context_refs.pipeline_run_id`）；run 创建失败注入夹具 → 502 `pipeline_run_create_failed` 且 Issue/`context_refs`/幂等记录/run 行零残留，原 key 重试成功且不产生重复；Multica 代码库无对 knowledge-base `_backlog.yml` / `cr.md` 的写入调用（grep 验证零命中）；后续 CR 注册仍在 knowledge-base 经 `crctl register` 完成。 |
| AC-9 | FR-11 | DiscussionPane 可选择消息与附件并触发两个升级入口；未配置 Coordinator 的纯人类 Discussion 同样可升级；升级成功后目标 Issue 链接可见、Discussion 内容不变；失败时选择保留并可重试。 |
| AC-10 | FR-12 | 一期交付不新增 `discussion_promotion` 表（`server/migrations/` 无该命名迁移）；若 SDD 附验证证据证明 `context_refs` 不足，则该证据与 reviewer 裁决记录在案后方可引入。 |
| AC-11 | FR-13、NFR-4 | 逐类失败夹具（400/403/404/409/500/502 各代表项）下，失败不留下半成品 Issue / 半写 `context_refs` / 孤立幂等记录 / 孤立 pipeline run 与 node_run 行；错误体含固定 `code`（断言「错误闭包」表逐条映射，code 与状态一一对应）；500/502 后以原 key 重试成功且 Issue 数/pipeline run 数不增加；前端按错误类型保留选择或提示重试。 |
| AC-13 | FR-10 | promotion 来源的 CR 注册（knowledge-base 侧消费，跨仓验收）：`requirement-register` 按 `issue_id` + `pipeline_id='requirement-authoring'` 定位 `cr_id IS NULL`、`status='running'` 的预建 run 并绑定新 CR-ID（同一行被复用、不新建第二条 run；绑定幂等、仅允许绑定一次）；绑定后 CR 进入 `requirement-reviewing` 时 Multica 状态事件投影复用同一 run（`pipeline_run` 行数不增）；绑定失败 → 注册按技术失败停止、`registration_key` 幂等重试安全；普通注册（无 promotion 上下文）不定位不绑定、行为不变。以 tools 侧注册集成测试 + multica 侧 run 投影断言为准。 |
| AC-12 | NFR-2、NFR-6 | 新增文案 en/ja/ko/zh-Hans 对称，`parity.test.ts` 全绿；旧 `project_discussion` Issue 只读回放不回归；CR-B Discussion GET/发送测试全绿。 |

来源文档完成标志要求 AC-23 至 AC-27 全部满足；上表 AC-1 对应来源 AC-23（只有显式升级才创建工作 Issue），AC-4 对应 AC-24（原消息附件不被移动或删除），AC-5 对应 AC-25（重复升级不产生重复 Issue），AC-3/AC-7 对应 AC-26（工作 Issue 可回溯来源 session/消息/附件），AC-8/AC-13 对应 AC-27（升级 CR 继续经过 requirement-register，Multica 不直接写 CR 账本；注册复用 promotion 预建 run）。AC-2/AC-6/AC-9/AC-10/AC-11/AC-12 覆盖同一闭环中必须可测、但来源完成标志未逐条编号的规则（来源选择校验、权限、前端交互、不新增 promotion 表、零残留与兼容性）。

## 6. 成功指标

- 打开 Discussion、发送、附件、协办产生的正式工作 Issue 数为 **0**；升级产生的 Issue **100%** 来自显式升级操作。
- 同一来源集合升级产生的目标 Issue 数 = **1**。
- 同一目标 Issue 对应的 `requirement-authoring` pipeline run 数 ≤ **1**（重放 / 查重命中 / 并发不产生第二条 run）。
- 原 Discussion 消息与附件被升级动作移动、删除或改绑的次数为 **0**。
- 目标 Issue 可回溯来源（`context_refs` 完整含 session/消息/附件）的比例为 **100%**。
- 升级失败留下半成品（孤立 Issue / 半写引用 / 孤立幂等记录）的次数为 **0**。
- Multica 服务端对 knowledge-base CR 账本的写入调用次数为 **0**。
- 未授权成员成功创建升级 Issue 的次数为 **0**。

## 7. 范围排除

以下内容明确不做，归属后续 CR 或明确非目标：

- 自动把 Discussion 消息升级为 Issue（任何定时/事件驱动升级）。
- 移动、删除或静默复制原 Discussion 消息与附件（FR-5 的反面）。
- 在 Multica 内实现 CR 注册、CR 状态机或 `_backlog.yml` 写入（来源 FR-25、AC-27）。
- 历史 `project_discussion` Issue 的 comment 升级（旧容器只读回放；升级只面向 shared session 消息）。
- Discussion 多主题、多 Agent 参与者模型与 `discussion_participant` 表。
- 新增 `discussion_promotion` 表（默认不做，仅 FR-12 的验证证据路径例外）。
- 给 `agent_task_queue` 增加模型/Thinking Mode 专用列；复制一套独立 Discussion 消息表。
- Team Agent / Private Ask 的发送、配置内核改动。
- 发送框整体视觉重构、对齐普通非项目聊天 composer（来源 CR-D）。
- mobile 端。
- `../tools/` 仓改动（除 FR-10 配套点：requirement-register 消费预建 run 的注册流程协同外）。
- 未消费的 promotion 预建 run 的过期与清理策略（用户升级后未发起注册时 run 保持 `cr_id=NULL`、`status='running'` 原状，不影响任何现有路径）。
- 把 `/compact` 作为普通用户消息发送。
