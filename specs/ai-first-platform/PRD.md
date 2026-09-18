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

## Team Agent 和 Private Ask 发送框 UI 优化（v0.35 · CR-2026-062）

## 1. 概述

### 1.1 问题陈述

Team Agent（`packages/views/projects/components/project-team-agent-chat.tsx`）与 Private Ask（`packages/views/projects/components/project-private-ask.tsx`）的发送框当前与普通非项目聊天（`packages/views/chat/components/chat-input.tsx` 的 `ChatInput`/`ChatInputCore`）存在两套互不一致的 composer 视觉体系：

- 两侧 composer 包装均为 `shrink-0 border-t px-4 py-3` 固定 padding，不采用 `chat-column.ts` 的 `CHAT_GUTTER`/`CHAT_COLUMN` 容器感知对齐，发送框边缘与消息列边缘在宽面板中不对齐。
- Model Picker / Thinking Mode 以 `*-model-row` 独立一行放在 composer 上方（`mb-1.5 flex items-center gap-1.5 text-xs text-muted-foreground`），而不是普通聊天底部的 `leftAdornment` 工具栏槽位，形成与普通聊天不同的控件层次。
- 输入 surface 的边框、背景、focus-within 状态、圆角与内部滚动等细节与普通非项目聊天不一致，用户在两类聊天间切换时会感到两套输入体验。

来源文档 `docs/product/Multica聊天会话级配置与Discussion方案.md` §12 CR-D 要求：**在不改变业务语义的前提下，将项目聊天发送框的布局和视觉体验对齐普通非项目聊天**。以上现状与 CR-D 目标不符。

### 1.2 解决方案摘要

按来源文档 CR-D 的布局基准重构两侧项目聊天 composer 的视觉层次：

```text
composer wrapper
  -> container-aware gutter（CHAT_GUTTER，复用 chat-column.ts）
  -> centered, width-capped input surface（CHAT_COLUMN）
       -> optional top metadata / attachment area（pending-message / 队列 / presenter 提示保留）
       -> scrollable editor area（长文本内部滚动）
       -> bottom-left add menu + session config controls（leftAdornment 或等价底部工具栏控件）
       -> bottom-right send / stop action
```

具体规则（来源文档 §12 CR-D）：

1. 复用普通聊天的 `CHAT_GUTTER`/`CHAT_COLUMN`，让消息列和发送框边缘对齐；项目窄面板使用容器宽度，不依赖浏览器 viewport 断点。
2. 复用单一输入 surface：边框、背景、focus-within 状态、圆角和内部滚动保持一致。
3. 输入区、附件预览、底部工具栏分层，长文本在输入区内部滚动，不能把发送按钮顶出面板。
4. 左下角复用普通聊天的附件/添加入口，并将 Model Picker、Thinking Mode 作为 `leftAdornment` 或等价底部工具栏控件接入；控件不再单独占据发送框上方的一整行，除非窄屏布局确实需要换行。
5. 右下角复用普通聊天的发送/停止按钮和 loading、上传中、运行中状态。
6. Team Agent 和 Private Ask 继续使用各自的 draft adapter、项目草稿隔离和 pending-message 模式，不接入普通聊天的全局 session store。
7. 配置控件使用已有的 Model Picker/Thinking Picker；控件操作仍调用会话配置接口（`PATCH /chat/config`，CR-2026-056 交付），不得改变 Agent 配置。
8. 保留可访问名称、tooltip、键盘发送、附件上传中禁发、失败可重试和运行中停止。

本 CR 是纯前端体验 CR（来源文档 CR-D）：不新增 API、数据库字段、任务快照或数据模型，不改变 draft/attachment/send/stop/retry 业务行为。

### 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

在不改变业务语义的前提下，将 Team Agent 与 Private Ask 项目聊天发送框的布局和视觉体验对齐普通非项目聊天：复用 CHAT_GUTTER/CHAT_COLUMN 对齐与单一输入 surface，Model Picker/Thinking Mode 控件作为底部工具栏控件接入（仍调用会话配置接口、不改 Agent 配置），附件预览/上传中/发送中/停止/失败/空态视觉一致，Web 与 Desktop 共享组件适配；不新增 API、数据库字段、任务快照或数据模型，不改变 draft/attachment/send/stop/retry 业务行为。

**包含范围**（来源文档 §12 CR-D）：

- Team Agent 和 Private Ask composer 的结构、间距、边框、背景、焦点和响应式布局。
- Model/Thinking 控件在底部工具栏中的排列和窄屏换行。
- 附件预览、上传中、发送中、停止、失败和空态视觉一致性。
- Web 和 Desktop 共享组件的适配。
- 对应组件测试和必要的 Playwright 截图/交互验证。

**不包含范围**：

- 新增 API、数据库字段或任务快照逻辑。
- 修改 Team Agent、Private Ask、Discussion 的权限和发送事务。
- 改造普通非项目聊天的现有视觉基线。
- 引入新的 UI 组件库或新的状态管理方式。
- 修改普通聊天 `ChatInput` 的既有业务语义；如需改共享组件，只做保证项目聊天兼容所需的最小调整。
- Discussion UI 变化不得混入本 CR。

**依赖**：依赖 CR-A（CR-2026-056「会话级配置与 Team Agent 闭环」，已归档并回写 specs 基线）提供会话配置控件所需的服务端字段和功能接口（`PATCH /chat/config`）；不依赖 CR-B（CR-2026-059）/CR-C（CR-2026-061）的 Discussion 产出。

**目标仓库**：代码实施在 sibling `../multica/`（`packages/views` 共享组件）；knowledge-base 承载本 PRD 与来源文档；`../tools/` 无实施改动。

`target-version` 继承 `cr.md` 的 `0.35`（注册阶段由 AIFI-18 指定），本文件不得改写该字段。`target-spec-id` 为 `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

**契约说明**：本 CR 不定义新的用户可调用契约（无新增 HTTP API、CLI 或 Skill 契约），PRD 契约确定性四查（幂等/权限/错误闭包/副作用）不适用（N/A）；现有 `PATCH /chat/config` 契约仅作为消费方引用先例，其确定性语义由 CR-2026-056 定义，本 CR 不改变。

### 1.4 当前代码事实（落笔前核实）

基线：multica requirement worktree HEAD `117fc6be657f91d43df5892b52782a18329c7aed`（register 时 ensure 的 requirement/CR-2026-062 worktree，已含 CR-A/CR-B/CR-C 合入产物）。以下结论均在该 SHA 上核实：

| 结论 | 证据 |
|---|---|
| `CHAT_GUTTER`/`CHAT_COLUMN` 定义与容器感知语义 | `packages/views/chat/components/chat-column.ts`：`CHAT_GUTTER = "px-5 @2xl:px-8 @4xl:px-12"`、`CHAT_COLUMN = "mx-auto w-full max-w-4xl"`；文件头注释明确「gutter scales with the CONTAINER, never the viewport」「gutter OUTSIDE the cap」的嵌套顺序语义 |
| 普通聊天 composer 结构（对齐基准） | `packages/views/chat/components/chat-input.tsx` `ChatInput`（L625-770）：wrapper 应用 `CHAT_GUTTER`；surface 应用 `CHAT_COLUMN` + `rounded-lg border border-surface-border bg-surface … focus-within:border-brand focus-within:ring-2`（L659-660）；编辑器区 `flex-1 min-h-0 overflow-y-auto px-3 py-2`（L703）；左下 `absolute bottom-1.5 left-1.5` 为 `ChatAddMenu` + `leftAdornment`（L737-752）；右下 `absolute bottom-1 right-1.5` 为 `SubmitButton`（loading/uploading/running/stop/tooltip，L753-770） |
| `ChatInputCore` 支持 `leftAdornment` 且不接触全局 store | `chat-input.tsx` L829 `interface ChatInputCoreProps extends ChatInputProps`（`leftAdornment?: ReactNode` 定义于 ChatInputProps L123）；`ChatInputCore` 渲染含 `leftAdornment` 底部工具栏（L1127-1136）；L856 注释「this component never touches useChatStore」（由 chat-input.test.tsx 钉住的结构事实） |
| Team Agent 当前 composer 与配置行 | `project-team-agent-chat.tsx`：wrapper `shrink-0 border-t px-4 py-3`（L864）；`project-chat-model-row` 独立行位于 composer 上方（L914-963，`mb-1.5 flex items-center gap-1.5 text-xs text-muted-foreground`），含 `ModelPicker`（L936）与 `ThinkingPicker`（L955）；`ChatInputCore` 使用点（L968，draftAdapter/onSend/onUploadFile/isRunning/mentionItemTypes） |
| Team Agent 会话配置路径与权限门禁 | `project-team-agent-chat.tsx` L686-692 注释：有效模型/思考级别在 active session 上，经 `PATCH /chat/config` 持久化，`api.updateAgent` 不得从聊天路径调用；L920-923：owner/admin 可编辑（`canConfigure`），普通成员显示只读徽标 `project-chat-model-readonly`（L924-933） |
| Private Ask 当前 composer 与配置行 | `project-private-ask.tsx`：wrapper `shrink-0 border-t px-4 py-3`（L392）；`private-ask-model-row` 独立行位于 composer 上方（L401-432），含 `ModelPicker`（L410）与 `ThinkingPicker`（L424），注释明确 creator-only session config（L401-403）；`ChatInputCore` 使用点（L436，draftAdapter/onSend/onUploadFile/onStop/isRunning/disabled=running） |
| `PATCH /chat/config` 已交付（CR-A） | `server/cmd/server/router.go` L2078、`server/internal/handler/project_chat.go` L87 |
| 上传中禁发/发送/停止/失败重试位于 `ChatInputCore` | `chat-input.tsx` L870 `pendingUploads` 显式计数；L1140 `SubmitButton disabled` 含 `pendingUploads > 0`；L1142-1143 `running`/`onStop`；L1144-1147 send/stop tooltip（含快捷键格式化） |
| CR-A 已归档并回写基线 | kb `change-requests/_index.yml`：CR-2026-056「会话级配置与 Team Agent 闭环」status=archived，writeback-spec-id=ai-first-platform；`specs/ai-first-platform/PRD.md`、`SDD.md` 含会话配置内容 |
| 来源文档已入库 | kb `docs/product/Multica聊天会话级配置与Discussion方案.md`：§12 CR-D（FR-29~33、包含/不包含范围、完成标志）、§13「发送框 UI」（AC-30~35） |

### 1.5 修订记录

- 初稿（2026-09-09）：按来源文档 CR-D 段与注册摘要起草，代码事实在 multica requirement worktree HEAD `117fc6be` 核实。

## 2. 用户故事

- **US-1 Team Agent 用户（项目 owner/admin）**：作为项目负责人，我希望 Team Agent 发送框和普通聊天长得一样、模型和思考模式在底部工具栏随手可调，而不是一眼看出两套输入框。
- **US-2 Team Agent 普通成员**：作为项目普通成员，我希望 UI 调整后模型/思考模式仍以只读形式展示，我无法通过 UI 越权修改会话配置（权限仍在服务端强制）。
- **US-3 Private Ask 用户**：作为使用 Private Ask 的项目成员，我希望模型/思考模式调整只影响我自己的会话，UI 重构后这个隔离不因布局变化而改变。
- **US-4 窄面板用户**：作为在窄项目面板或小浮窗里聊天的用户，我希望发送框不横向溢出，输入区、附件预览、配置控件和发送/停止按钮互不遮挡。
- **US-5 键盘/无障碍用户**：作为依赖键盘和屏幕阅读器的用户，我希望发送框保留可访问名称、tooltip、键盘发送（Mod+Enter）和运行中停止能力。
- **US-6 既有用户**：作为已经习惯 Team Agent/Private Ask 的用户，我希望草稿、附件、发送、停止、失败重试行为和以前完全一致，这次升级只是视觉和布局变化。

## 3. 功能需求

### FR-1 发送框布局对齐普通非项目聊天（来源 FR-29）

Team Agent 和 Private Ask 的发送框采用与普通非项目聊天一致的 composer 布局语言：container-aware gutter（`CHAT_GUTTER`）→ centered width-capped input surface（`CHAT_COLUMN`），消息列与发送框边缘对齐；项目窄面板使用容器宽度，不依赖浏览器 viewport 断点。不另建一套并行 composer 视觉体系。实现复用 `chat-column.ts` 的既有定义与容器语义（先例见 §1.4），不复制第二份常量。

### FR-2 单一输入 surface（来源 FR-29、FR-30）

两侧项目聊天发送框复用 `ChatInputCore` 的单一输入 surface：边框、背景、focus-within 状态、圆角和内部滚动与普通非项目聊天保持一致；输入区、附件预览、底部工具栏分层，长文本在输入区内部滚动，不能把发送按钮顶出面板。UI 优化必须保留现有 `ChatInputCore`、draft adapter、草稿附件、上传状态、发送中、停止和失败重试行为。

### FR-3 配置控件作为底部工具栏控件（来源 FR-31）

Model Picker 和 Thinking Mode 控件作为发送框底部工具栏的一部分呈现（`leftAdornment` 或等价底部工具栏 slot，先例见 §1.4）；不再单独占据发送框上方的一整行，除非窄屏布局确实需要换行（换行时保持工具栏整体换行，不挤压输入区）。

控件操作仍调用会话配置接口（`PATCH /chat/config`，CR-2026-056 交付），**不得改变 Agent 配置**：不得从聊天路径调用 `api.updateAgent`，`agent.model`/`agent.thinking_level` 不被聊天操作修改。权限门禁保持不变：Team Agent 中 owner/admin 可编辑、普通成员只读徽标；Private Ask 中 creator-only 会话配置语义不变；runtime 不可用时保持现有 guide 提示行为。

### FR-4 窄屏与双端不溢出、不遮挡（来源 FR-32）

发送框在窄项目聊天面板、桌面端和 Web 端保持内容不横向溢出；输入区、附件状态（预览/上传中）、配置控件和发送/停止按钮不得互相遮挡。窄屏下配置控件在工具栏内换行或折叠，不允许挤压输入区导致其不可用。

### FR-5 视觉状态一致性（来源 FR-30、AC-33）

附件预览、上传中（禁发）、发送中、停止、失败重试、空态等视觉状态与普通非项目聊天保持一致；右下角复用普通聊天的发送/停止按钮及 loading、上传中、运行中状态。Team Agent 和 Private Ask 继续使用各自的 draft adapter、项目草稿隔离和 pending-message 模式，不接入普通聊天的全局 session store（`ChatInputCore` 自身不接触 `useChatStore` 的结构事实保持不变，见 §1.4）。

### FR-6 可访问性保持（来源 AC-35）

可访问名称、tooltip 与键盘发送（Mod+Enter，运行中可停止）行为保持可用；布局调整不得移除或破坏现有控件语义（配置控件仍可通过键盘聚焦与操作）。

### FR-7 不新增数据与业务语义（来源 FR-33、AC-34）

本 CR 不新增会话、任务、附件或 Discussion 数据模型；不新增 API、数据库字段、任务快照逻辑；不改变 draft、attachment、send、stop、retry 的业务行为；不修改 Team Agent、Private Ask、Discussion 的权限和发送事务。业务语义由已归档功能 CR（CR-A/CR-B/CR-C）提供，本 CR 只做视觉与布局。

### FR-8 共享组件适配与测试（来源完成标志）

Web 与 Desktop 共享组件适配（两平台共用 `packages/views` 实现，不做平台分支视觉）；交付对应组件测试与必要的 Playwright 截图/交互验证（含窄面板回归）；并输出与普通非项目聊天布局的差异说明，仅记录必要差异（完成标志）。

## 4. 非功能需求

- **NFR-1 双端一致**：Web 与 Desktop 共享 `packages/views` 组件，行为与视觉一致；mobile 不在本 CR 范围。
- **NFR-2 无障碍**：控件保留可访问名称与 tooltip；键盘发送/停止可用；布局调整不降低焦点可见性与对比度。
- **NFR-3 文案**：优先复用现有控件与文案 key，不为此 UI 调整新增文案；若实现确实需要新 key，须 en/ja/ko/zh-Hans 四语对称且 `packages/views/locales/parity.test.ts` 全绿。
- **NFR-4 性能与依赖**：不引入新 UI 组件库、不引入新状态管理；配置控件状态仍由现有会话配置数据源驱动，不为布局调整新增重复请求。
- **NFR-5 兼容**：不改造普通非项目聊天的现有视觉基线；对共享组件的任何修改只做保证项目聊天兼容所需的最小调整；普通聊天、Team Agent、Private Ask、Discussion 的既有测试不回归。

## 5. 验收标准

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-1 | 来源 AC-30 | Team Agent 和 Private Ask 发送框均复用普通非项目聊天的 composer 布局语言（`CHAT_GUTTER`/`CHAT_COLUMN`），不出现两套互不一致的输入框结构。组件测试断言两处 composer 应用与 `chat-column.ts` 相同的 gutter/column 规则；Playwright 截图对比宽面板下发送框边缘与消息列边缘对齐。 |
| AC-2 | FR-2 | 来源 AC-30 | 单一输入 surface：边框、背景、focus-within、圆角、内部滚动与普通非项目聊天一致；组件测试/截图对照 `chat-input.tsx` 的 surface 结构与状态样式，长文本在输入区内部滚动且发送按钮不被顶出面板。 |
| AC-3 | FR-4 | 来源 AC-31 | 发送框在窄项目面板（含 360px 浮窗场景）中不发生横向溢出；输入区、附件预览、配置控件和发送/停止按钮不重叠。Playwright 窄面板回归 + 截图断言通过。 |
| AC-4 | FR-3 | 来源 AC-32 | Model Picker 和 Thinking Mode 位于底部工具栏或其窄屏换行布局中；功能调用目标仍是会话配置接口：操作后 `agent.model`/`agent.thinking_level` 不变（沿用 CR-2026-056 AC-1/AC-2 口径），会话配置经 `PATCH /chat/config` 持久化生效；普通成员仍为只读徽标，Private Ask 仍 creator-only。 |
| AC-5 | FR-5 | 来源 AC-33 | 普通聊天已有的附件上传、上传中禁发、发送中、停止、失败重试和草稿保留行为不回归：既有 chat-input/项目聊天测试全绿，且新增/更新项目聊天发送框组件测试覆盖上述每个状态。 |
| AC-6 | FR-5、FR-7 | 来源 AC-34 | Team Agent 和 Private Ask 的 draft adapter、项目隔离和 pending-message 状态不因 UI 调整而改用全局聊天 store：代码评审确认两处仍注入各自 draftAdapter，pending-message 渲染行为不变（现有 `project-chat-pending-message`/`private-ask-pending-message` 语义保持）。 |
| AC-7 | FR-6、FR-8 | 来源 AC-35 | Web/Desktop 共享视图通过组件测试和窄面板回归检查；可访问名称、tooltip 和键盘发送行为可用（组件测试/可访问性断言，含运行中停止）。 |
| AC-8 | FR-7、FR-8 | 来源 FR-33、完成标志 | 交付 diff 中无新增 API 路由、无新增 `server/migrations/` 迁移、无任务快照逻辑或数据模型变更；普通非项目聊天视觉基线不变化（截图基线对比）；差异说明文档记录必要差异，且每项差异有明确理由。 |

来源完成标志要求 FR-29 至 FR-33 和 AC-30 至 AC-35 全部满足：AC-1/AC-2 对应来源 AC-30（composer 布局语言复用、单一输入 surface），AC-3 对应 AC-31（窄面板不溢出不重叠），AC-4 对应 AC-32（配置控件入底部工具栏、调用目标仍为会话配置接口），AC-5 对应 AC-33（附件/上传/发送/停止/失败/草稿行为不回归），AC-6 对应 AC-34（draft adapter、项目隔离、pending-message 不用全局 store），AC-7 对应 AC-35（组件测试、窄面板回归、可访问名称/tooltip/键盘发送）。FR-1~FR-8 分别覆盖来源 FR-29~FR-33 及来源「完成标志」的差异说明与测试交付要求。

## 6. 成功指标

- Team Agent 与 Private Ask 发送框与普通非项目聊天 composer 之间的非必要布局差异数 = 0（必要差异以差异说明文档为准，均有明确理由）。
- 窄面板（360px 浮窗/窄项目面板）横向溢出与控件遮挡缺陷数 = 0。
- UI 调整导致的 draft/attachment/send/stop/retry 行为回归数 = 0。
- 因 UI 调整新增的 API / 数据库迁移 / 数据模型 = 0。
- 普通非项目聊天视觉基线变化 = 0。
- 发送框对齐与视觉一致性截图验收通过率 = 100%。

## 7. 范围排除

以下内容明确不做，归属后续 CR 或明确非目标：

- 新增 API、数据库字段或任务快照逻辑（来源 FR-33）。
- 修改 Team Agent、Private Ask、Discussion 的权限和发送事务。
- 改造普通非项目聊天的现有视觉基线。
- 引入新的 UI 组件库或新的状态管理方式。
- 修改普通聊天 `ChatInput` 的既有业务语义；如需改共享组件，只做保证项目聊天兼容所需的最小调整。
- Discussion UI 变化混入本 CR（Discussion 视觉改造不属于 CR-D，来源文档「CR 顺序和边界」）。
- 会话配置服务端字段与功能接口本身（由 CR-2026-056 提供，本 CR 只消费）。
- mobile 端。
- 对 Team Agent / Private Ask 的队列、presenter、附件上传管线等业务逻辑的任何行为改动。

## CR-P0 流程正确性止血 — `_context.md` 合同退役、Prompt 源/overlay 归位、委派合同收紧、crctl 原子性与错误可操作化（v0.36 · CR-2026-063）

## 1. 概述

### 1.1 问题陈述

CR-2026-062（AIFI-18 全链路执行）暴露出一组**流程正确性**缺陷：它们不改变任何业务能力，但会让后续每一个 CR 的委派、评审、恢复与账本写入持续走偏。需求来源是 Issue AIFI-24 附件《AIFI-18_SDD到planTASK_原位修订方案.md》§3「CR-P0：流程正确性止血」，共 7 组原位修订：

1. **第三事实副本 `_context.md` 仍然活跃**：删除决策（来源 §1.2）已拍板，但盘上仍有 4 处活跃合同——Multica 侧两份旧 Prompt 副本要求维护/读取它，tools 侧的 post-review 白名单放行它，CR-2026-057 引入的测试把「放行」钉成了合同。缓存与 canonical 事实（`cr.md`、`review-loop.yml`、`traceability.yml`、评审记录）并存时，评审与门禁会读到过期导航数据。
2. **Prompt 事实源定位不清**：`multica/cr-prompts-revised/` 既登记为「快照」，又混放 Multica 专属 coordinator 与四个公共 Agent 的副本，且已与 `tools/agents/` 分叉（§1.4 事实 4）。owner 部署时无法判断该复制什么。
3. **委派合同复制流程步骤**：Multica coordinator overlay（`cr-prompts-revised/cr-coordinator-agent.md`）与公共 `tools/agents/dev-agent.md` 的委派段没有明确「只传事实与 canonical 引用」，执行侧凭评论重建 Skill/Pipeline 步骤，错误被复述成新的执行算法。
4. **错配错误不可操作**：`crctl gate --mode pre-review` 在 stage 不匹配时只回 `BAD_ARGS`（`crctl.mjs:960`），调用方看不到当前 stage 的正确下一步，也无法区分「我传错了」与「版本化 Skill/Pipeline 与 crctl 已经漂移」。
5. **`review-loop reset` 留下已写未提交中间态**：`crctl.mjs:1821` 的 `cmdReviewLoopReset` 直接 `fs.writeFileSync`（L1844）后返回，**不提交、不回滚、无 CAS**；一旦 add/commit 环节失败，CR worktree 会停在一个 dirty 的账本上，后续门禁与 post-review 漂移检查都会误判。
6. **`review-record` payload 的 YAML 子集边界没有写明**：blocker/suggestion 值若写成多行引号标量或折叠块，解析结果与作者意图不一致，而调用方没有明文约束可依。

本 CR 只做「止血」：**原位修订既有文件、既有函数、既有 Skill 段落与既有测试**，不新增流程、不新增观测指标、不换实现方案。

### 1.2 解决方案摘要

按来源文档 §3 的 7 组原位修订逐条落地（每组都锚定「仓 + 文件」，见 §1.3 与 §3 各 FR）：

1. **`_context.md` 合同退役**（§3.1）：Multica 侧两份旧 Prompt 副本各原位替换/删除 `_context.md` 段（`cr-prompts-revised/dev-agent.md`、`quality-reviewer-agent.md`）；tools 侧从 post-review 白名单中删除该条目（`workspace-transactions.mjs` `allowed` 集合）；把 CR-2026-057 的既有测试**原位改成退役合同测试**（`crctl.test.mjs`），不在旁边新增反向补丁测试。不新增 `crProcessCachePath()`，不放宽 `classifyRepoWorkspace()` 的 dirty 语义——删除后 `_context.md` 与其它非白名单文件同等处理。
2. **全量核对**（§3.1.5）：活跃 `agents/`、`skills/`、`pipeline-templates/` 的 `_context.md` **活跃合同引用**归零（口径说明见 §1.5，需人工审批一并确认）；历史 CR、历史 traceability、归档 delivery 证据不改。
3. **Prompt 源 / overlay 归位**（§3.2.1）：原位重写 `multica/CUSTOM.md` 的 **#75 行职责单元格**——公共 Agent Prompt 唯一事实源为 `tools/agents/`；`cr-prompts-revised/cr-coordinator-agent.md` 是 Multica 专属 overlay；目录内公共 Prompt 副本不再独立演进，owner 部署时以 tools 同名文件覆盖平台公共 Agent；DB 是部署投影；`cr-coordinator-agent` 不进入 tools agent index。不新增登记行、不追加第二份事实源说明。
4. **不改动的矩阵与索引**（§3.2.2）：`tools/agents/_index.yml` 不新增 coordinator；`tools/agent-skill-matrix.yml` 保留既有 `cr-coordinator-agent` system actor 声明；`multica/cr-prompts-revised/agent-skill-matrix.yml` 不作为公共矩阵独立演进。
5. **Multica coordinator overlay 三处原位替换**（§3.3）：`cr-prompts-revised/cr-coordinator-agent.md` 的 `## 委派与评论`、`## 评审闭环`、`## 失败与输出` 三节按 §3.3.1/§3.3.2/§3.3.3 给定文本原位替换；保留 `职责`、`事实源与读取`、`路由`、`平台层权限` 与只读约束，不整文件推倒重写。
6. **公共 dev-agent 委派合同**（§3.4）：`tools/agents/dev-agent.md` 的 `## 委派路由合同（评审）` 原位收紧为「每轮新 reviewer task/run、标准节点走 Pipeline Runner、只传 Skill 已声明的结构化输入与 canonical 引用、不复述 Skill 步骤/门禁命令/advance 参数/blocker 修法」，并要求对来自版本化 Skill/Pipeline 的错误命令**同时报告 `CONTRACT_DRIFT`**（不以成功掩盖合同错误）。
7. **crctl 错误可操作化与原子性**（§3.5/§3.6/§3.7）：`gate --mode pre-review` 错配保留 `BAD_ARGS` 与零写入，同时给出 stage 专属安全恢复方向与 `contractDrift`；`lint-prompts.mjs` 的 R7 规则内加入配对检查；`review-loop reset` 改为复用既有 ledger 事务助手的一次原子提交；`crctl/SKILL.md` 的 `review-record` 行与各 review Skill 的 payload 示例注释补写 YAML 子集边界。

### 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

删除 `_context.md` 全部活跃合同（Prompt、post-review 白名单、既有测试原位退役）；公共 Agent Prompt 事实源归位 `tools/agents/`、coordinator 保留 Multica overlay；收紧 coordinator 与 dev 委派合同（只传事实与 canonical 引用、冲突报 `CONTRACT_DRIFT`）；`gate --mode pre-review` 错配补 stage 专属恢复方向与 `contractDrift`；`review-loop reset` 改原子提交；补清 `review-record` payload 的 YAML 子集边界。不新增 SLO/M1–M8/P50-P90/计数门禁，不新增 R14 委派 lint，不换 YAML 解析器，不改平台 DB 与 `aifirst/agent-import.mjs`。

#### 1.3.1 scope_in 边界（原文前缀，评审核对用）

> `multica/cr-prompts-revised/*` 只是平台部署副本，公共 Agent 正式改动落 `tools/agents/*`，multica 仓只改 coordinator overlay 与 `CUSTOM.md#75`，平台 DB 与 `aifirst/agent-import.mjs` 由 owner 部署。

**该前缀句的限定**（防止前缀句被当作 multica 文件清单直接核对）：前缀句是**公共 Prompt 事实源归位口径**——公共 Agent 的正式改动不落 multica 部署副本；它不排除 FR-1 的两份部署副本退役编辑（下表第 1、2 行）。加上这两处，本 CR 对 `../multica` 的改动共 **4 个文件**：`cr-prompts-revised/{dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md` + `CUSTOM.md`（与 AC-11 的四文件口径一致）。

逐条落到「哪个仓的哪个文件」：

| # | 仓 | 文件 | 原位修订 |
|---|---|---|---|
| 1 | `../multica` | `cr-prompts-revised/dev-agent.md`（`## 环境与代码边界` 末段，基线 L47） | 用 canonical resume 口径替换整段 `_context.md` 规则，不在段后追加说明 |
| 2 | `../multica` | `cr-prompts-revised/quality-reviewer-agent.md`（`## 入口识别与证据` 首段，基线 L19） | 删除 `_context.md` 引用，改为读 `dir-graph.yaml`、`crctl status/next` 返回、当前 CR canonical 产物与 Skill 指定证据 |
| 3 | `../multica` | `cr-prompts-revised/cr-coordinator-agent.md`（`## 委派与评论` L38、`## 评审闭环` L45、`## 失败与输出` L63） | 三节原位替换（§3.3.1/3.3.2/3.3.3 文本） |
| 4 | `../tools` | `agents/dev-agent.md`（`## 委派路由合同（评审）`，基线 L31） | 原位收紧委派合同，加 `CONTRACT_DRIFT` 报告义务 |
| 5 | `../multica` | `CUSTOM.md`（#75 行，基线 L387） | 原位重写同一表格行的职责单元格；不新增行 |
| 6 | `../tools` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（post-review `allowed` 集合，基线 L1311–1319） | 删除 `_context.md` 条目与其注释 |
| 7 | `../tools` | `skills/shared/crctl/scripts/test/crctl.test.mjs`（CR-2026-057 白名单测试，基线 L4554） | 原位改为退役合同测试，保留 `_context2.md` 反例 |
| 8 | `../tools` | `skills/shared/crctl/scripts/crctl.mjs`（`cmdGate` 的 `--mode pre-review` 分支，基线 L959–960） | 错配返回 stage 专属恢复方向 + `contractDrift` + 固定字符串 `recoverCommand` |
| 9 | `../tools` | `skills/shared/crctl/scripts/lint-prompts.mjs`（R7，基线 L249–284） | 内加入 `gate --mode pre-review` ↔ `--for requirement-reviewing` 配对检查 |
| 10 | `../tools` | `skills/shared/crctl/scripts/crctl.mjs`（`cmdReviewLoopReset`，基线 L1821–1848） | 改 async，复用 ledger 事务助手做一次原子提交，失败回滚 |
| 11 | `../tools` | `skills/shared/crctl/scripts/lib/durable-tx.mjs`（`beginLedgerTransaction` 的 ledger write-set 前置条件，基线 L487） | 仅把 `writes.length < 2` 原位放宽为 `< 1`（FR-9 第 3 条：接受单文件 write-set、仍拒空 write-set）；不新增导出、不改 journal/manifest 结构与 recover/abort/finish 语义 |
| 12 | `../tools` | `skills/shared/crctl/SKILL.md`（`review-record` 行，基线 L34） | 原位补写 YAML 子集边界说明 |
| 13 | `../tools` | `skills/{requirement/review-requirement,develop/review-tech-design,develop/review-dev-plan,develop/review-code}/SKILL.md` | 既有 payload 示例注释原位补写单行标量约束 |
| 14 | `../tools` | 上述 8/9/10/11 四个脚本的既有测试（`scripts/test/**`） | 追加/修订覆盖新增行为的测试并有反向用例 |

#### 1.3.2 目标仓库与版本

- 代码实施在 `../tools/`（crctl 脚本、`lib/durable-tx.mjs`、lint、公共 Agent Prompt、SKILL.md）与 `../multica/`（coordinator overlay、两份部署副本、`CUSTOM.md`）。
- knowledge-base 承载本 PRD 与来源文档；本 CR 不改 KB 的 `specs/`、`delivery/`、`docs/`。
- **部署不在本 CR 范围内**（来源 §1.1、§3.3）：平台 DB 的 Prompt 投影与 `multica/aifirst/agent-import.mjs` 不改，由 owner 在各 CR 落地后用 `multica agent update` 或平台等价受控入口部署。原因：该 importer **只创建不存在的 Agent，遇到同名 Agent 会 `skip`**，不能用于更新已有 Prompt。
- `target-version` 继承 `cr.md` 的 `0.36`（注册阶段由 Ray 指定），本文件不得改写该字段。`target-spec-id` 为 `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

#### 1.3.3 契约说明（确定性四查适用面）

本 CR 定义了两处**用户可调用的 CLI 可观察契约**变更，四查（幂等 / 权限 / 错误闭包 / 副作用）落点为 FR-7、FR-9 与 AC-7、AC-9：

- `crctl gate --mode pre-review` 的错配错误体（FR-7）；
- `crctl review-loop reset` 的原子性与失败回退（FR-9）。

其余 FR 为文档/Prompt/测试侧的原位修订（FR-1~FR-6、FR-10），不定义新的用户可调用契约；其验收以「文本合同 + 测试/检索证据」形式给出。本 CR **不新增**任何 API、子命令、账本字段或账本条目；FR-7 的 `contractDrift` 与补入的 `recoverCommand` 是**既有错误体的字段补充**（沿用既有 crctl 事务错误体 / 事务返回的同名字段命名，见 §1.4 事实 7、16），不构成新的契约面。

### 1.4 当前事实（落笔前核实）

基线（requirement worktree，register 时 ensure）：

| 仓 | worktree HEAD |
|---|---|
| `ai-first-platform-docs`（本 KB） | `00b596f9c2263fecf38c3fc616bcb1c22916bae8` |
| `../multica` | `5fde81c1f463e7031663ef8111ee0b7ce39aac3c` |
| `../tools` | `ebdd6290f1523ffb682609b7ad6ab83e7d30245e` |

以下结论均在上述 SHA 上核实（路径相对各自 worktree 根）：

| # | 结论 | 证据 |
|---|---|---|
| 1 | 需求源两处拷贝在 CRLF→LF 归一后逐字节一致 | Issue AIFI-24 附件《AIFI-18_SDD到planTASK_原位修订方案.md》与主 checkout `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md`（24585 B，SHA256 `b774e41d…`）归一后 `equal=true`；该文件当前在主 checkout 为 untracked，在 CR worktree 分支上不存在（`cr.md source` 记的是 Issue `AIFI-24`，不是路径） |
| 2 | `_context.md` 的 tools 侧活跃引用共 6 处，全部落在两个文件 | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` L1317–1318（条目 + 注释）；`skills/shared/crctl/scripts/test/crctl.test.mjs` L4554（测试名 `CR-2026-057: KB 白名单新增 _context.md…`）、L4560、L4561、L4565。`agents/`、`pipeline-templates/` 与其余 `skills/**` 命中 0 |
| 3 | `_context.md` 的 multica 侧引用共 2 处 | `cr-prompts-revised/dev-agent.md:47`（`## 环境与代码边界` 末段，L43 起）、`cr-prompts-revised/quality-reviewer-agent.md:19`（`## 入口识别与证据` 首段，L17 起） |
| 4 | Multica 副本已与 tools 公共 Prompt 分叉 | 同一检索在 `tools/agents/**` 命中 0——公共 dev/reviewer Prompt 已不含 `_context.md` 规则，Multica 仍保留旧口径 |
| 5 | `CUSTOM.md` #75 行在位且正处于「快照」定性 | `CUSTOM.md:387`：`| 75 | \`cr-prompts-revised/\`（\`agent-skill-matrix.yml\` + 5 个 Agent prompt md） | …快照…与 tools 仓实际生效 prompt 分叉时以 tools 仓为准并人工对齐 |`；该表表头为 `| # | 位置 | 改动 | 原因 / 追溯 | 日期 | 合并注意 |` |
| 6 | coordinator overlay 章节结构 | `cr-prompts-revised/cr-coordinator-agent.md`：L11 `## 职责`、L15 `## 事实源与读取`、L24 `## 路由`、L38 `## 委派与评论`、L45 `## 评审闭环`、L55 `## 平台层权限`、L63 `## 失败与输出`；目录构成 = `agent-skill-matrix.yml` + 5 个 prompt md |
| 7 | pre-review 错配当前只有裸 `BAD_ARGS` | `crctl.mjs` L957–960：`cmdGate` 内 `if (flags.mode === 'pre-review') { if (flags.for !== 'requirement-reviewing') fail('BAD_ARGS', '--mode pre-review 仅支持 --for requirement-reviewing'); … }`；`fail()`（L43–47）输出 `{error:{code,message,...extra}}` 到 stderr 并 `exit 1`，当前 extra **为空**（`gate` 错误体上不存在 `recoverCommand`；该字段名当前只出现在 `register`/`checkpoint`/`merge`/`writeback`/`archive` 的事务返回与 `TxError` extra，如 `workspace-transactions.mjs:777`/`:1074`/`:1514`/`:1945`/`:2882`/`:3460`） |
| 8 | `review-loop reset` 当前直写不提交 | `crctl.mjs` L1821 `function cmdReviewLoopReset(ws, cr, gates, flags)`（同步）；L1844 `fs.writeFileSync(p, renderLoopText(all.loops), 'utf8')` 后 L1845 `auditLog`、L1846 `ok(...)`；无 CAS、无事务、无 commit |
| 9 | reset 的既有语义与人类在环硬检查 | `crctl.mjs` L1822–1824 非 TTY → `NOT_TTY` 无旁路；L1826–1828 `--loop`/`--reason` 缺失 → `BAD_ARGS`；L1829–1832 未耗尽 → `LOOP_NOT_EXHAUSTED`；效果 = `current-cycle+1`、`current-attempt=0`、`attempts[]` 历史保留；`review-loop.yml` 由 crctl 独占（L844 `attemptsFilePath`、`renderLoopText` import L30） |
| 10 | 可复用的事务与提交助手、ledger write-set 前置条件、index 回滚机制族 | `crctl.mjs`：`casWrite` L672、`ledgerTxKey` L678、`syncLedgerIndex` L682、`recoverLedgerCommand` L691、`beginLedgerCommand` L705、`controlledGit` L412；`lib/durable-tx.mjs`：`abortLedgerTransaction` L514、`finishLedgerTransaction` L519。先例：`review-record` 用 `writes[{path,expectedHash,newText}] → beginLedgerCommand → finishLedgerTransaction`（`crctl.mjs` L2177–2195），`expectedHash` 由 `readFileChecked` 取原文 + `sha256`（L2183）。**前置条件缺口**：`beginLedgerTransaction` 拒 `writes.length < 2`（`lib/durable-tx.mjs:487`，`TX_WRITESET_INVALID`），既有 4 个调用点全部 ≥2 文件（`approve` L1130 = approval.yml+cr.md、`owner-set` L2535 = cr.md+_backlog.yml、`version-set` L2828 = cr.md+_backlog.yml+derived、`review-record` L2177–2195 = annotation+traceability，+bump 时再加 review-loop），**无单文件先例**，且当前无测试守卫该 ≥2 规则（`durable-tx.test.mjs` 只测 write-set entry 校验与 journal 形状）；空 write-set 另有 `applyWriteSet` 的 `entries.length === 0` 独立拒绝（`lib/durable-tx.mjs:311`）。**index 回滚机制族**：`syncLedgerIndex`（L682，以 `git add -A -- <relpath>` 使 index 与回滚后内容一致）用于 `approve` 提交失败路径（L1141，caller `crctl-approve`）与崩溃恢复路径（L697，caller `crctl-ledger-recovery`）；同族 `rollbackVersionWrite`（L2725：abort + 撤销暂存 + clean baseline 复核）、`rollbackOwnerWrite`（L2471） |
| 11 | 版本化 Prompt 的 R7 规则在位 | `lint-prompts.mjs` L14 规则清单注释列 R1~R9；R7 实现 L249–284（advance `--to`/`--trigger` 形态、全角/伪旗标、`backlog-set --field` 白名单、`commit --template` subject 含 CR）；当前**无** `gate --mode pre-review` 与 `--for requirement-reviewing` 的配对检查 |
| 12 | `review-record` 契约行与四份 payload 示例在位 | `skills/shared/crctl/SKILL.md:34` 为 `review-record` 行；`skills/requirement/review-requirement/SKILL.md:105–111`、`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/develop/review-code/SKILL.md` 各有 YAML payload 示例（`verdict`/`blockers`/`dimensions`/`suggestions`）；四处均无「必须单行标量」的边界说明 |
| 13 | YAML 子集解析器的既有边界 | `skills/shared/crctl/scripts/lib/yaml-subset.mjs:1–5` 头注释：支持块映射、块序列、flow 映射/序列、引号字符串、注释、`\|` 与 `>`（保守处理为拼接文本）；不支持锚点、别名、tag、多文档 |
| 14 | coordinator 的矩阵声明与 tools index 现状 | `agent-skill-matrix.yml:25–29` `actors.cr-coordinator-agent`（`kind: system`、`mode: leader`）；`agents/_index.yml` 共 9 个 agent，无 coordinator |
| 15 | 公共 dev-agent 委派段在位 | `agents/dev-agent.md:31` `## 委派路由合同（评审）` |
| 16 | CR-R 的先决约束 | 本 CR 未完成 CR-R（`recoverCommand` → 结构化 `recovery` 的原子迁移，需求见 `docs/analysis/crctl_recoverCommand结构化恢复合同_原子迁移方案.md`，独立 CR），故 FR-7/FR-9 的兼容字段 `recoverCommand` 只能是无用户输入的固定字符串。该字段在 `gate` 错误体上**当前不存在**（事实 7：extra 为空），本 CR 沿用既有 crctl 事务错误体 / 事务返回的同名命名，在 FR-7、FR-9 两处错误体上**补入**（是「补入」，不是「保留既有字段」） |

### 1.5 §3.1.5 的口径（对来源文档的解释，须在人工审批时一并确认）

来源 §3.1.5 字面要求：活跃 `agents/`、`skills/`、`pipeline-templates/` 搜索 `_context.md` **结果为 0**。但 §3.1.4 同时要求把 CR-2026-057 的既有测试**原位改成退役合同测试**并保留 `_context2.md` 反例——退役测试里必然仍出现 `_context.md` 字面量（作为「必须被拒绝的对象」）。两条要求不可能同时字面成立。

**本 PRD 采用的解释（不静默缩小 AC）**：

> 目标是「**活跃合同引用**为 0」；`scripts/test/**` 内的**负向断言字符串**不计入。

精确检索口径（AC-2 按其执行）：

- 范围：`../tools` 的 `agents/`、`skills/`、`pipeline-templates/` 三棵子树的全文件（`.md`/`.mjs`/`.js`/`.yml`/`.yaml`/`.json`/`.ts`）。
- 计入：任何**要求创建/读取/维护/放行** `_context.md` 的文本（合同语句、白名单条目、注释性说明）。
- 排除：`skills/shared/crctl/scripts/test/**` 下作为**必须被拒绝的对象**出现的字面量（退役测试名、断言字符串、测试夹具注释）。
- 判定：计入集合为空；排除集合在 `scripts/test/**` 内的出现次数不作归零要求，但必须全部是负向断言语义（正例放行断言一律不允许残留）。

`../multica` 侧同口径适用（两份部署副本归零，无测试例外）。

### 1.6 修订记录

- 初稿（2026-09-11）：按来源文档 §3 与注册摘要（`cr.md` summary）起草；三仓事实在 §1.4 所列三个 worktree HEAD 上逐条核实。§1.5 为对来源 §3.1.5 的口径解释，需人工审批确认。
- 修订 0.1.1（2026-09-11，第 1 轮需求评审回修）：关闭 **B-1**——FR-9 显式择定单文件 write-set 路径（原位放宽 `lib/durable-tx.mjs:487` 的 `writes.length < 2` 为 `< 1`，理由与两条未采用替代写在 FR-9 第 3 条），并在 FR-9 第 5 条与 AC-9② 补齐 index 回滚的既有机制口径、AC-9⑥ 给出该放宽的可验断言；同步 §1.4 事实 10（助手清单 + write-set 前置条件 + index 回滚族）、事实 7 与事实 16（`gate` 错误体 extra 为空，`recoverCommand` 是「补入」不是「保留」）；§1.3.1 的 scope_in 表新增 `lib/durable-tx.mjs` 一行并顺延后续行号，§1.3.2/NFR-1 同步该文件面。同时收口：S-1（§1.3.1 前缀句限定，multica 仓共 4 个文件）、S-2（§1.3.3 的「不新增」限定为账本字段/子命令/API）、S-3（四查落点改为 FR-7、FR-9 与 AC-7、AC-9）、S-4（FR-9 第 2 条 expected hash 改引 `review-record` 先例；`readAttempts` 不返回原文/哈希）。

## 2. 用户故事

- **US-1 后续 CR 的执行 Agent**：作为按 Pipeline 节点干活的 Agent，我希望恢复/返工时只读 canonical 事实（`crctl status/next`、`cr.md`、`review-loop.yml`、评审记录），不再被要求维护或读取 `_context.md` 这类会过期的第三副本，这样我不会基于缓存做出与门禁不一致的判断。
- **US-2 平台 owner（部署者）**：作为把 Prompt 部署进 Multica 的 owner，我希望一眼看清「公共 Prompt 的唯一事实源是 `tools/agents/`，只有 coordinator 是 Multica 专属 overlay」，这样我不会把分叉的旧副本当成规范复制上平台。
- **US-3 需求/开发 Agent 的委派接收方**：作为被委派的 Agent，我希望收到的是 CR-ID、节点/Skill 名、`crctl status/next` 结果、workspace/resources 原样值、canonical 引用与责任 Agent，而不是别人复述出来的 Skill 步骤，这样我不会照着二手算法执行。
- **US-4 自动化调用方（Skill/Pipeline/脚本）**：作为调用 `crctl gate --mode pre-review` 的一方，我希望 stage 传错时拿到「当前 stage 的正确安全恢复方向」与「是否与版本化合同漂移」的信号，而不是一条无法区分责任的 `BAD_ARGS`。
- **US-5 交互式终端前的人（人类在环）**：作为唯一被允许执行 `review-loop reset` 的人，我希望这次重置要么整体生效（文件已提交、工作区干净），要么整体无效（文件与 index 回滚、报错并留审计），这样我不会把 CR 留在一个已写未提交的中间态。
- **US-6 写评审 payload 的 reviewer**：作为写 `review-requirement.yml`/`sdd.yml` 等 payload 的 reviewer，我希望明确知道 `blockers`/`suggestions` 只能写单行标量，这样我的评审内容不会因解析口径而与落盘结果不一致。
- **US-7 评审者（CR 自身）**：作为本 CR 的 reviewer，我希望能逐条核对「哪个仓的哪个文件被原位改了」，使得这次止血不引入第二套流程或新的观测负担。

## 3. 功能需求

### FR-1 `_context.md` 活跃合同退役（来源 §3.1.1–§3.1.4）

四条原位修订，逐条落到「仓 + 文件」，**不追加新章节、不复制第二套流程**：

1. `../multica` `cr-prompts-revised/dev-agent.md`：把 `## 环境与代码边界` 末段（基线 L47）中「`change-requests/{CR-ID}/_context.md` 是允许维护的工作流导航缓存：每次本 Agent run 收尾时…刷新或创建…随 CR 一起提交」整段**替换**为 canonical resume 口径——受控账本/`review-annotations`/`review-loop`/`traceability`/`specs/` 不得手工修改，写入必须经专用 Skill/crctl；恢复或返工直接读 `crctl status {cr_id}`、`crctl next {cr_id}`、`cr.md`、`review-loop.yml` 与 canonical review annotations；**不得创建或读取 `_context.md` 等上下文副本，也不得让缓存替代状态、评审证据或门禁**。不得以「保留旧段 + 段后追加说明」的方式落地。
2. `../multica` `cr-prompts-revised/quality-reviewer-agent.md`：`## 入口识别与证据` 首段（基线 L19）删除 `_context.md` 引用，改为「评审前读取目标 workspace `dir-graph.yaml`、`crctl status/next` 返回、当前 CR canonical 产物和该 Skill 指定的证据；canonical 事实优先于缓存、评论和执行方自报」。目的：避免 owner 后续把旧缓存合同复制上平台。
3. `../tools` `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：post-review path drift 的 `allowed` 集合（基线 L1311–1319）**删除** `change-requests/${cr}/_context.md` 条目及其上方注释（L1317–1318）。**不新增** `crProcessCachePath()`，**不放宽** `classifyRepoWorkspace()` 的 dirty 语义。删除后：评审后新增或修改 `_context.md` 与其它非白名单文件同等处理（`post-review-path-drift` 拒绝）。
4. `../tools` `skills/shared/crctl/scripts/test/crctl.test.mjs`：把 CR-2026-057 的既有测试（基线 L4554 起，名含 `_context.md` 白名单放行）**原位改成退役合同测试**，断言语义变为「`_context.md` 不再属于 post-review allowed paths；评审后新增或修改该文件必须按普通 unexpected path 拒绝」，并**保留 `_context2.md` 非白名单断言**，证明不存在前缀式放宽。禁止「保留原测试 + 旁边新增反向测试」。

### FR-2 活跃引用全量核对（来源 §3.1.5）

在 CR-P0 的变更范围内，对 `../tools` 的活跃 `agents/`、`skills/`、`pipeline-templates/` 与 `../multica` 的 `cr-prompts-revised/` 执行 `_context.md` 检索：**活跃合同引用为 0**，判定口径与排除项按 §1.5 执行。历史 CR 目录、历史 `traceability.yml`、归档 delivery 证据**不改**（不批量迁移、不重写历史）。

### FR-3 Prompt 事实源归位：`CUSTOM.md` #75 原位重写（来源 §3.2.1）

`../multica` `CUSTOM.md` 的 **#75 行职责单元格**（基线 L387）原位重写，明确：

- 公共 Agent Prompt（requirement/dev/reviewer/delivery 等）的**唯一事实源是 `tools/agents/`**；
- `cr-prompts-revised/cr-coordinator-agent.md` 是 **Multica 专属 overlay**；
- 目录中的公共 Prompt 副本**不再独立演进**，owner 部署时以 tools 同名文件覆盖平台公共 Agent；
- **DB 是部署投影，不是事实源**（禁止把 DB/UI 临时编辑反向当规范）；
- `cr-coordinator-agent` **不进入 tools agent index**。

约束：**不新增登记行**、不在 `CUSTOM.md` 后追加第二份事实源说明、不改变该表其它行；`:387` 所在表结构与列语义不变（`位置`/`改动`/`原因 / 追溯`/`日期`/`合并注意`）。

### FR-4 矩阵与索引不改动（来源 §3.2.2）

以下三处**保持现状**，本 CR 不得改动（作为反向验收对象）：

- `../tools` `agents/_index.yml`：**不新增** `cr-coordinator-agent`（基线 9 个 agent）；
- `../tools` `agent-skill-matrix.yml`：**保留**既有 `cr-coordinator-agent` system actor 权限声明（基线 L25–29）；该声明是平台 actor 的公共权限边界，不因 prompt 文件不在 tools 而另造第二份；
- `../multica` `cr-prompts-revised/agent-skill-matrix.yml`：不作为公共矩阵独立演进（本 CR 不改）。

### FR-5 Multica coordinator overlay 三处原位替换（来源 §3.3）

目标文件 `../multica` `cr-prompts-revised/cr-coordinator-agent.md`。**保留**当前正确的 `## 职责`、`## 事实源与读取`、`## 路由`、`## 平台层权限` 与只读约束（不得整文件推倒重写），**原位替换**以下三处：

1. `## 委派与评论`（基线 L38）：标准 Pipeline 节点只通过平台已有 Runner 启动目标 Agent；Runner 提供的固定 PipelinePrompt、canonical feedback、attempt、source task 与 executor 是该次委派的权威输入，本 Agent 不在评论中复制它们的执行算法。计划外人工委派只传以下事实：CR-ID、当前 Pipeline 节点或 Skill 名、`crctl status/next` 的当前返回、权威 workspace/resources **原样值**、canonical feedback 路径或对象引用、当前责任 Agent；**不得**复述 Skill/Pipeline 步骤，不得内联状态推进或 Git 命令，不得把 blocker 正文改写成新的执行步骤，不得声明未来节点已经满足。`mention://agent/<id>` 是立即创建/唤醒目标 task/run 的工作委派而非抄送；串行交接的一条评论只 mention 一个当前目标，下一节点或复评者只作纯文本说明；每次触发后记录一次 squad activity。
2. `## 评审闭环`（基线 L45）：保留既有 BLOCK / Suggestions / alignment 责任边界，原位改写**标准评审入口**——标准 Pipeline 评审由 Pipeline Runner 按 registry 节点启动新的 `quality-reviewer-agent` task/run，协调者不得用评论重建 review Skill 的步骤；评审 BLOCK 按 `review-record` 返回的 `repair-target` 与 Pipeline `reviewLoop` 处理；协调者只在 repair target 无效、最大轮次耗尽、权限/事实冲突、技术失败或人工 gate 时介入。
3. `## 失败与输出`（基线 L63）：在既有失败 bullet 内**原位扩写**——当评论、Agent Prompt 与当前 Skill/Pipeline 事实发生冲突时，停止该次手工委派，报告 `CONTRACT_DRIFT` 与冲突两侧，不自行选择一套步骤继续；来自 crctl 的恢复信息只逐字段转发，不改写为协调者自己的 Git/状态序列。

约束：本修改是 **Prompt 合同缓解**，不宣称平台已新增运行时委派校验；owner 将该文件复制到平台后才生效（部署不在本 CR 范围）。

### FR-6 公共 dev-agent 委派合同（来源 §3.4）

`../tools` `agents/dev-agent.md` 的 `## 委派路由合同（评审）`（基线 L31）原位修改为：

- 每轮评审使用**新的** reviewer task/run；
- 标准节点走 Pipeline Runner；
- 仅传 review Skill 已声明的结构化输入和 canonical 引用；
- **不**在委派评论中复述 Skill 步骤、门禁命令、advance 参数或 blocker 修法；
- 若 Agent 临时生成的**只读**命令出现零写入 `BAD_ARGS`，可按 crctl 明示的恢复方向恢复一次；
- 若错误命令来自**版本化 Skill/Pipeline**，当前 run 可按安全恢复完成，但**必须同时报告 `CONTRACT_DRIFT`**，不得以成功掩盖合同错误。

约束：**不新增** R14 委派 lint（来源 §1.3/§3.4：无法检查真实运行期评论的规则不引入）。

### FR-7 `gate --mode pre-review` 错配可操作化（来源 §3.5.1）

目标：`../tools` `skills/shared/crctl/scripts/crctl.mjs` 的 `cmdGate()` 中 `--mode pre-review` 分支（基线 L959–960）。行为合同：

- **保留** `BAD_ARGS` 错误码与**零写入**（进程退出码非 0，stderr JSON 形如 `{error:{code:'BAD_ARGS', …}}`）；
- 明确 `--mode pre-review` 仅支持 `--for requirement-reviewing`；
- 对其它 stage 返回**stage 专属安全恢复方向**：固定为 `crctl workspace inspect <cr_id>` 形态（`<cr_id>` 取自被调用的 CR，不含任何用户自由输入）；
- 返回布尔 `contractDrift: true`，提示调用方检查权威 Skill/Pipeline；该字段在本 CR 中**恒为 `true`**，不携带区分信息，只是「须复核权威 Skill/Pipeline」的固定提示，调用方不得据此反推漂移类型（该定位的说明归 SDD）；
- **补入**兼容字段 `recoverCommand`：沿用既有 crctl 事务错误体 / 事务返回的同名命名（`register`/`checkpoint`/`merge`/`writeback`/`archive`，见 §1.4 事实 7、16），在本错误体上新增该字段，值**只能是无用户输入的固定字符串**（本 CR 未完成 CR-R，结构化 `recovery` 不在范围）；
- `--for requirement-reviewing` 的既有 pre-review 检查序列行为**不变**（既有门禁测试全绿）。

### FR-8 版本化 Prompt 的配对 lint（来源 §3.5.2）

`../tools` `skills/shared/crctl/scripts/lint-prompts.mjs` 的 R7 规则内（基线 L249–284）**原位加入配对检查**：文本中出现 `gate --mode pre-review` 时，必须同时出现 `--for requirement-reviewing`，否则产生 `R7` 级 finding。

约束：该规则只防**版本化 Prompt 漂移**；**不**用于声称真实运行期评论已被机械限制；不新增规则编号（不新增 R14 之类的委派 lint），不改变既有 R7 判据（advance 参数形态、`backlog-set --field` 白名单、`commit --template` subject）。

### FR-9 `review-loop reset` 原子提交（来源 §3.6）

目标：`../tools` `skills/shared/crctl/scripts/crctl.mjs#cmdReviewLoopReset`（基线 L1821）。行为合同：

1. 函数改为 `async`；dispatcher 保持 `return cmdReviewLoopReset(...)`，由既有 `async main()` 接管（不改调用形态）。
2. 读取 attempts 状态时取得**目标文件 expected hash**：以 `readFileChecked` 取 `review-loop.yml` 原文 + `sha256` 作为 `expectedHash`（先例 `review-record`，`crctl.mjs` L2183、L2193）。`readAttempts` 只返回状态投影（`current`/`max`/`attempts`/`cycle`/`cycleAttempts`/`exhausted`/`data`），**不返回原文或哈希**，不承担 CAS 取值；事务路径的 CAS 由 ledger 事务按 `expectedHash` 自行校验，不经过 `casWrite`。
3. 复用既有助手完成一次事务写：命令入口先 `recoverLedgerCommand(ws, ledgerTxKey('reset', cr, loopRef))`（本事务键下的残留幂等回滚/确认，外部 dirty 不受影响，口径同 `approve`/`version-set`），随后 `beginLedgerCommand` → `controlledGit` add/commit → `abortLedgerTransaction`/`finishLedgerTransaction`（先例见 §1.4 事实 10）。
   - **write-set 构成（本 CR 择一结论）**：`reset` 的 write-set **只有 `review-loop.yml` 一个文件**（`auditLog` 走 `.crctl/` 审计域，不进 git 事务）。
   - **单文件路径的落地方式**：把 `lib/durable-tx.mjs:487` 的 ledger 前置条件 `writes.length < 2` **原位放宽为 `writes.length < 1`**——仍拒绝空 write-set，但接受单文件 write-set。
   - **理由**：该前置条件的作用只是「拒绝空 write-set」（空集另有 `applyWriteSet` 的 `entries.length === 0` 独立拒绝，`lib/durable-tx.mjs:311`），`>= 2` 的数值来自既有 4 个调用点的形态、不是可回滚性的必要条件——单条目与多条目的 prepare/apply/rollback 路径完全同构（逐条 CAS 校验、逐条 before 快照回滚）；既有 4 个调用点（`approve`/`owner-set`/`version-set`/`review-record`）全部传 ≥2 文件，故该放宽对它们**零行为差异**。
   - **不采用的替代**：(b) 在 write-set 中塞入一个内容不变的第二个文件——会让第 4 条「commit 只包含 `review-loop.yml`」与 FR-11 的零无关改动口径变成假象；(c) 绕开 `beginLedgerCommand` 自建写入路径——被第 7 条禁止，且 `casWrite` 单文件直写不提供崩溃可恢复与 index 回滚，无法满足 AC-9②。
   - 该放宽是本 FR 对 `lib/durable-tx.mjs` 在**行为面**的唯一改动：不新增导出、不改 journal/manifest 结构、不改 `recover`/`abort`/`finish` 语义。
4. commit **只包含 `review-loop.yml`**（`controlledGit add` 只 stage 该路径），提交消息保留 `[cr]` 前缀并带 transaction id（`AI-First-Tx: <txId>` trailer；事务按 `commitRequired=true` 记账，供崩溃后「已提交 / 未提交」判定，口径同 `approve`）。
5. add/commit 失败时按 §1.4 事实 10 的既有机制族回滚，**不得留下 dirty 中间态**：`abortLedgerTransaction(tx)` 按 journal 把 `review-loop.yml` 还原为执行前内容，随后 `syncLedgerIndex(ws, rolled.paths, 'crctl-review-loop-reset')`（`git add -A -- <relpath>`）使 index 与该文件回滚后的内容一致——执行前 tracked-clean 时即回到执行前状态（先例：`approve` 失败路径 `crctl.mjs` L1141、`version-set` 的 `rollbackVersionWrite` L2725、`owner-set` 的 `rollbackOwnerWrite` L2471）；之后写审计并返回失败。
6. 在 CR-R 之前，失败结果可继续返回兼容 `recoverCommand`（沿用既有 crctl 事务错误体的同一命名，在本错误体上**补入**），但**不得把用户输入的 `reason` 拼入字符串**（TTY 重试时重新输入 reason）。
7. **不**新写事务框架 / primitive（仅复用既有 ledger 事务助手 + 上述前置条件数值放宽），**不**把 reset 并入 checkpoint，**不**放宽 controlled-shell 全局规则。
8. 既有语义不变：非 TTY → `NOT_TTY`（无旁路参数/环境变量）；缺 `--loop`/`--reason` → `BAD_ARGS`；未耗尽 → `LOOP_NOT_EXHAUSTED`；成功效果 = `current-cycle+1`、`current-attempt=0`、`attempts[]` 历史保留；`review-loop.yml` 仍由 crctl 独占。

### FR-10 `review-record` payload 的 YAML 子集边界（来源 §3.7）

两处**原位补写**（只说明既有事实，**不换解析器**）：

- `../tools` `skills/shared/crctl/SKILL.md` 的既有 `review-record` 行（基线 L34）：写明 payload 中 `blockers` / `suggestions` 等值必须使用 **YAML 子集支持的单行标量**；不得使用多行引号标量或折叠块；说明依据是既有 `lib/yaml-subset.mjs` 的解析边界（块标量 `|`/`>` 仅保守拼接为文本，锚点/别名/tag/多文档不支持）。
- 各 review Skill 的既有 payload 示例注释（`requirement/review-requirement`、`develop/review-tech-design`、`develop/review-dev-plan`、`develop/review-code`）：在示例处补同一约束，**不新增字段、不新增维度、不改示例结构**。

约束：本 FR 是**文档侧**说明；`lib/yaml-subset.mjs` 行为与实现零改动。

### FR-11 零新增与不修改边界

本 CR 的交付 diff 必须体现下列「不改动」事实（来源 §1.3/§1.4/§7）：

- 不新增 SLO、M1–M8 指标、P50/P90、连续 N 个 CR 统计、为复盘计数新增的账本字段或 Prompt 要求、「评审轮数必须降到某个数」的门禁；
- 不新增 R14 委派 lint；
- 不换 YAML 解析器、不放宽其解析边界；
- 不改平台 DB，不改 `../multica` `aifirst/agent-import.mjs`；
- 不新增 Pipeline 节点、不新增评审维度、不新增委派平台 API、不新增 context 生成器/`crProcessCachePath()`、不为 context commit 放宽 `rules.json`、不让 README 复制可执行步骤事实源；
- 不改 CR 状态机/`gates.json`/状态推进路径。

## 4. 非功能需求

- **NFR-1 兼容性（最重要）**：`../tools` 全量既有测试（crctl、ledger/durable-tx、prompt lint、pipeline structure、contract-scan 等）保持通过；`crctl` 既有子命令的**成功路径输出与退出码不变**（本 CR 只改一份错配错误体、一个内部写入路径及其复用的 ledger write-set 前置条件一处数值，不改任何成功输出契约）。
- **NFR-2 幂等与可重入**：`review-loop reset` 的写入以目标文件 expected hash 为前提；同一次重试不产生第二个 cycle（失败回滚后重跑必须等价于一次干净执行）；`gate --mode pre-review` 保持零写入，可任意重放。
- **NFR-3 确定性（无自由输入进入恢复字符串）**：所有人类可读的恢复方向/`recoverCommand` 字符串**不含**用户输入（`reason` 等），防止把用户文本拼进可被复制的命令。
- **NFR-4 行尾纪律**：所有对仓库文件的哈希、跨行正则、逐行解析相关代码与测试在读写前做 `\r\n → \n` 归一；解析失败**硬失败报错**，禁止静默降级（工作区纪律 #1，本 CR 触及 crctl 脚本与测试，直接适用）。
- **NFR-5 审计与可追溯**：`reset` 保持既有 `auditLog` 记录（`kind: review-loop-reset`，含 `fromCycle`/`toCycle`/`reason`/`by`）；事务提交带 transaction id；失败路径同样落审计。Prompt/文档侧修改不新增运行时埋点。
- **NFR-6 语言与措辞**：`../multica` 仓文档按其 `CLAUDE.md` 规则以中文书写既有内容为准，本 CR 只改写既有中文段落；`../tools` 侧文档/CR 产物用中文，代码注释按既有文件语言。
- **NFR-7 无部署副作用**：本 CR 不触发平台 Agent DB 更新；`multica agent update` 等部署动作由 owner 在 CR 落地后执行。

## 5. 验收标准

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-1 | §3.1.1–§3.1.4 | 四处原位修订全部落地：①`cr-prompts-revised/dev-agent.md` 的 `## 环境与代码边界` 段内不再出现 `_context.md` 且含 canonical resume 口径（`crctl status`/`crctl next`/`cr.md`/`review-loop.yml`/canonical annotations）；②`cr-prompts-revised/quality-reviewer-agent.md` 的 `## 入口识别与证据` 首段不再出现 `_context.md`；③`workspace-transactions.mjs` 的 `allowed` 集合不含 `_context.md` 条目（且无 `crProcessCachePath`、`classifyRepoWorkspace` 零 diff）；④`crctl.test.mjs` 中原 CR-2026-057 测试已原位改为退役语义，新语义断言「`_context.md` 评审后变更 → `post-review-path-drift` 拒绝」，且保留 `_context2.md` 非白名单断言。同一测试文件中不存在「旧放行断言 + 新拒绝断言」并存的重复测试。 |
| AC-2 | FR-2、FR-1 | §3.1.5（口径见 §1.5） | 按 §1.5 口径检索：计入集合（要求创建/读取/维护/放行 `_context.md` 的文本）在 `../tools` 的 `agents/`、`skills/`、`pipeline-templates/` 与 `../multica` 的 `cr-prompts-revised/` 中为 **0**；排除集合（`skills/shared/crctl/scripts/test/**` 的负向断言字面量）出现处均为拒绝语义断言，无正例放行残留。检索命令与命中清单作为交付证据（含 `--include`/排除路径与行尾归一处理）。 |
| AC-3 | FR-3 | §3.2.1 | `CUSTOM.md` 的 **#75 行职责单元格**同时包含五要素：`tools/agents/` 为公共唯一事实源、coordinator 为 Multica 专属 overlay、目录内公共副本不再独立演进（owner 以 tools 覆盖平台公共 Agent）、DB 是部署投影、coordinator 不进 tools agent index；表格行数与其它行文字零 diff（除该单元格）。 |
| AC-4 | FR-4 | §3.2.2 | `git diff` 显示 `tools/agents/_index.yml`、`tools/agent-skill-matrix.yml`、`multica/cr-prompts-revised/agent-skill-matrix.yml` **零改动**；`agents/_index.yml` 仍为 9 个 agent，`agent-skill-matrix.yml` 的 `cr-coordinator-agent`（`kind: system`/`mode: leader`）声明保留。 |
| AC-5 | FR-5 | §3.3 | `cr-coordinator-agent.md` 的 `## 委派与评论`、`## 评审闭环`、`## 失败与输出` 三节内容与 §3.3.1/§3.3.2/§3.3.3 合同逐条对应（含「只传事实与 canonical 引用」「一条评论只 mention 一个当前目标」「标准评审由 Runner 启动新 reviewer task/run」「`CONTRACT_DRIFT` 停手报告」）；`## 职责`/`## 事实源与读取`/`## 路由`/`## 平台层权限` 四节与文件 frontmatter 保持原样；文件内不出现 Skill/Pipeline 步骤复述或 Git/状态推进命令。 |
| AC-6 | FR-6 | §3.4 | `agents/dev-agent.md` 的 `## 委派路由合同（评审）` 含六条要求（新 task/run、Runner、只传声明输入与 canonical 引用、不复述步骤/门禁/advance/修法、只读 `BAD_ARGS` 可恢复一次、版本化来源错误须同时报 `CONTRACT_DRIFT`）；`lint-prompts.mjs` 中不存在 R14 或等价委派 lint 规则。 |
| AC-7 | FR-7 | §3.5.1 | `crctl gate --mode pre-review --for <非 requirement-reviewing 的 stage>` 在真实 workspace 上：退出码非 0；stderr JSON 的 `error.code === 'BAD_ARGS'`；`error.contractDrift === true`；错误体含形如 `crctl workspace inspect <cr_id>` 的恢复方向；`error.recoverCommand` 存在且为固定字符串、不含任何用户输入；执行前后 worktree 文件哈希集合零变化（零写入）。`--for requirement-reviewing` 的既有 pre-review 检查行为与既有测试结果不变。 |
| AC-8 | FR-8 | §3.5.2 | lint 单元向量：文本含 `gate --mode pre-review` 而缺 `--for requirement-reviewing` → 产生 R7 finding；两者同时出现 → 不产生；既有 R7 向量（advance 形态、`backlog-set` 白名单、`--template` subject）结果不变；无新增规则编号。 |
| AC-9 | FR-9 | §3.6 | ①reset 成功路径：`review-loop.yml` 的变更**已被提交**（提交只包含该文件、消息含 `[cr]` 前缀与 transaction id），`git status --porcelain` 为空；②add/commit 故障注入（既有 fault 机制）→ 命令失败返回，`review-loop.yml` 按 journal 还原、index 经 `syncLedgerIndex`（`git add -A --`）回到与执行前一致的状态（无 dirty 残留），审计已写；③失败或成功结果中的 `recoverCommand` 均不含 `--reason` 的用户文本；④非 TTY → `NOT_TTY`、未耗尽 → `LOOP_NOT_EXHAUSTED`、缺参 → `BAD_ARGS` 三条既有行为不变；⑤成功后 `current-cycle` 递增 1、`current-attempt=0`、`attempts[]` 历史条目保留；⑥单文件 write-set 路径成立：`beginLedgerTransaction` 接受 `writes.length === 1` 并完成 prepare/apply/finish，空 write-set 仍抛 `TX_WRITESET_INVALID`，既有 4 个调用点（`approve`/`owner-set`/`version-set`/`review-record`）的既有事务测试全绿。 |
| AC-10 | FR-10 | §3.7 | `crctl/SKILL.md` 的 `review-record` 行与四份 review Skill 的 payload 示例处均出现「单行标量」边界说明（含「不得使用多行引号标量或折叠块」）；`lib/yaml-subset.mjs` 零 diff；payload 示例结构（字段名与层级）不变、未新增字段。 |
| AC-11 | FR-11 | §1.3/§1.4/§7 | 交付 diff 中：无新增 SLO/M1–M8/P50–P90/计数门禁/账本字段/评审维度/Pipeline 节点；无 `crProcessCachePath`；`rules.json` 零 diff；`multica/aifirst/agent-import.mjs` 零 diff；`../multica` 平台侧除 §1.3.1 列出的 4 个文件外无其它改动。 |
| AC-12 | 全部 | §3.8 | `../tools` 全量既有测试通过（crctl、ledger/durable-tx、prompt lint、pipeline structure、contract-scan 及本 CR 新增/修订的用例），且 `../multica` 侧被改文件不引入语法/结构破损（Markdown 表格结构、frontmatter 完整）。 |

来源 §3.8 验收清单与上表映射：活跃 Agent/Skill/Pipeline 不再引用 `_context.md` → AC-1/AC-2；post-review 白名单不再包含 `_context.md` → AC-1③；旧 CR-2026-057 测试已原位改为退役测试 → AC-1④；tools 不新增 coordinator prompt → AC-4；coordinator overlay 不含手写 Skill/Pipeline 步骤 → AC-5；`gate --mode pre-review` 错配由既有 lint 抓住 → AC-8；reset 成功后工作区 clean、add/commit 故障时文件与 index 回滚 → AC-9；recover 字符串不包含用户 reason → AC-9③；全量既有测试通过 → AC-12。

## 6. 成功指标

- 活跃 `_context.md` **合同引用**数 = 0（按 §1.5 口径，含 `../multica` 侧）。
- post-review 白名单中 `_context.md` 条目数 = 0。
- `gate --mode pre-review` 错配时返回「stage 专属恢复方向 + `contractDrift`」的比例 = 100%（无裸 `BAD_ARGS`）。
- `review-loop reset` 成功后的 dirty 中间态数 = 0；add/commit 故障场景的「文件/index 回滚 + 审计落盘」成功率 = 100%。
- 恢复类字符串包含用户输入（`reason`）的处数 = 0。
- 本 CR 新增的观测指标 / 计数门禁 / Pipeline 节点 / 评审维度 / 账本字段数 = 0。
- 既有测试回归数 = 0。

## 7. 范围排除

以下内容明确不做：

**来源文档层面的排除项**

- 新增 SLO、M1–M8 指标、P50/P90、连续 N 个 CR 统计、「评审轮数降到某个数」的门禁，以及为复盘计数新增的账本字段或 Prompt 要求（来源 §1.4）。
- 新增 R14 委派 lint（来源 §1.3/§3.4：无法检查真实运行期评论）。
- 更换 YAML 解析器或放宽其解析边界（来源 §3.7）——本 CR 只补写既有边界说明。
- 历史 CR 目录的 `_context.md`、历史 `traceability.yml`、归档 delivery 证据的批量迁移或重写（来源 §1.2）。
- 平台 DB 的 Prompt 更新与 `../multica` `aifirst/agent-import.mjs` 的改造（来源 §1.1：importer 只创建不更新；部署由 owner 在 CR 落地后执行）。
- coordinator 进入 `tools/agents/_index.yml`；新增平台委派 schema；新事务框架；新 context 生成器；新 Pipeline 节点；新评审维度或观测指标；为 context commit 放宽 `rules.json`；README 复制可执行步骤事实源（来源 §7）。

**CR 边界（独立 CR，不得并入本 CR）**

- **CR-R：结构化恢复合同原子迁移**（全局 `recoverCommand` → `recovery`，生产者/消费者同 CR 迁移，无双写期）——需求文档已存在（`docs/analysis/crctl_recoverCommand结构化恢复合同_原子迁移方案.md`），独立评审、审批与回滚。本 CR 的 `reset` 兼容止血在 CR-R 落地后由其原位替换。
- **CR-P1：评审输入结构与回修闭合**（来源 §5）。
- **CR-P2：plan/TASK 返工成本与执行前提**（来源 §6）。
- 来源 §2 明确：四个 CR 分别评审、审批、回滚，**不得合并为一个发布单元**。

**本次明确不碰的既有资产**

- CR 状态机、`gates/`、`reviewLoop`/`replayNodes`/`maxAttempts` 语义、CAS 与 durable ledger transaction 框架、controlled-shell 与 `rules.json`、`ENVIRONMENT_MISMATCH`、Pipeline Runner 结构化节点输入、版本化 `cmd-NN` 与 test evidence（来源 §7「继续复用、不再造」）。
- KB 的 `specs/`、`delivery/`、`docs/`（本 CR 不改知识库文档；主 checkout 中 `docs/analysis/` 的既有未提交变动属 Ray 的文档归位操作，不在本 CR 范围）。

## CR-S：测试基线与门禁可信化 — 断言去硬编码、4 条基线漂移转绿、CI 全量步骤成为真门禁（v0.38 · CR-2026-065）

### 1. 概述

#### 1.1 问题陈述

tools 仓的全量测试在基线上就是红的：固定 `tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289` 上，不带例外跑全部 21 个 `*.test.mjs`，失败恰为 5 条（BR-1…BR-5）。这 5 条不是本 CR 造的，也不是某一个 CR 造的，而是被 5 次各自合理的变更累积出来的：

| # | 测试（基线行号） | 断言什么 | 引入变更 |
|---|---|---|---|
| BR-1 | `crctl.test.mjs:1337` `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引` | `code-implementation.pipeline.json` **文本**含 `crctl task init`、含「不得手写索引」 | `14b4458`（CR-2026-050 只改 pipeline、未同步测试） |
| BR-2 | `checkpoint-tx.test.mjs:480` `checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints[]` | `skills/review/review-alignment/SKILL.md` **文本**含 `latest-checkpoint` | `fc2b142`（CR-2026-060 TASK-04 把 reader 事实源改为 `cr.md` + `_backlog.yml` 条目信息） |
| BR-3 | `crctl.test.mjs:4777` `TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）` | `tools/dir-graph.yaml` **状态机条目数**恰 28、wildcard 展开恰 50 | `bef1f4d` + `2e4442d`（CR-2026-061）、`49c46dd`（AIFI-17）各 +1 行，均未碰测试 |
| BR-4 | `crctl.test.mjs:4989` `CR-2026-042 静态合同：已知 Skill 越界文本零命中` | `write-requirement-prd/SKILL.md` **文本**写「七个章节**和**未替换占位符」 | `fc797ed`（AIFI-22 把「和」改成「、」） |
| BR-5 | `archive-tx.test.mjs:373` `TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖` | 预存**同名但内容不同**的 outbox 文件时，archive 返回 `warnings: []` | 冻向量构造问题（非产品缺陷，见 FR-8/FR-9） |

由此产生的问题不是「5 条测试要修」，而是四件事同时不成立：

1. **验收不可达**：任何在 SDD/计划里写「全量测试全绿」的 CR 都不可达，只能每个 CR 再签一次例外授权——CR-2026-060、CR-2026-063、CR-2026-064 已各付过一次；而 CR-2026-063 SDD §6.4 的授权明示「只覆盖本 CR 的验收口径」，**不跨 CR 继承**，所以这份代价会无限重复。
2. **门禁没有约束力**：`.github/workflows/crctl-ci.yml:111` 的 `crctl full test suite` 步骤正是这条不带例外的全量命令，它在基线上就是红的。一条本来就红的 CI 步骤不构成门禁——于是「漂移在引入它的 CR 内当场变红」这件事在 CI 上直接不成立，漂移只能攒到被别的手段发现（本轮就是攒到第 5 次变更才暴露）。
3. **漂移的根因是断言类型，不是某条测试写错了**：BR-1…BR-4 的共同形态是**把会随合理变更而变的事实钉成快照**——pipeline 文本措辞、reader 的事实源、状态机条目数、Skill 文本的连接词。这类断言给出的失败信号无法区分「事实变了」与「产品坏了」，真红线会被假红淹没。
4. **BR-5 的冻结向量没有覆盖真实崩溃窗口**：产品按「同名文件 + **内容相等**才算已发送」去重（共享函数 `emitOutboxEvent`：`crctl.mjs:293` 起，register / archive / status / audit / trace 共用；CR-2026-052 TASK-08 的 drift-audit 语义在此之上排除 `payload.detected_at`），而 RED-7 预写的是**同名但内容不同**的文件，于是它测的是一个从未发生过的场景，并把「必须可见的冲突信号」当成了失败。

本 CR 是 CR-2026-064（CR-R，结构化恢复合同原子迁移）的**前置**：先把这类债从根上清掉，再回到 CR-2026-064。后者原地冻结在 `tech-design-review-pending`，不在本 CR 范围内。

#### 1.2 解决方案摘要

四件事，一个 CR：

1. **断言去硬编码**：计数类断言从事实源自身推导；文本类断言只查语义，不钉措辞与标点；同时**必须保留拒绝产品错误的能力**——推导不得宽到「等于当前行数」这种等价重述（FR-1、FR-2、FR-3），并由 SDD 逐条分清「可推导的事实」与「必须钉死的目标值」。
2. **4 条断言漂移转绿**（BR-1…BR-4）：把断言对齐到各自事实源的**当前事实**——指令的真实载体（`write-dev-tasks` SKILL）、reader 的当前事实源（`cr.md` + 条目信息）、状态机的推导口径、Skill 文本的语义要素；不是改产品去迎合旧断言。
3. **BR-5 按「构造改对」处理**：保留产品「内容相等才算已发送」语义（不改产品语义、不整条作废），把 r2 的构造改成**预写与本次事件内容一致的文件**（真实崩溃窗口，原断言全部保留），并新增「同名但内容不同」的显式用例（要求可见信号 + journal 保持 pending + 后续可补发），同时把「哪些字段参与比较、哪些易变字段必须排除」从 `crctl.mjs` 注释里的口头约定钉成**可机器检查的契约**。
4. **CI 可信化 + 例外治理**：让 `.github/workflows/crctl-ci.yml` 的全量测试步骤成为真门禁（退出码 0 当且仅当失败集合为空，21 个文件全部被真实执行，不得靠 skip/删/改名/放宽达成绿），定掉 `--test-concurrency=2` 的收敛问题（含可复现证据），并给残余例外一个**单一登记处 + owner + 到期**，到期未清即红。

「绿」的约束力必须由本 CR 自证：对每一类被覆盖的断言做一次**负控注入**（真实漂移 → 全量测试在本 CR 内变红 → 还原恢复绿），负控证据随交付物留存（FR-13）。

#### 1.3 需求来源与事实源

- 需求来源：Multica issue `AIFI-26`（`CR-S：测试基线与门禁可信化（CI 全量绿 + 漂移当场红）`，本 CR 的 `source`），其中范围与边界由 owner（`Ray`）在 `AIFI-25` 线程裁决：范围只做包 A、一个 CR、BR-5 按「构造改对」实施、不含包 B（SDD 评审合同）、不含 CR-2026-064 的迁移本身。
- 事实源：`tools` 仓自身——`tools/dir-graph.yaml`（状态机唯一事实源）、`pipeline-templates/*.pipeline.json`、各 `SKILL.md`、`skills/shared/crctl/scripts/**`、`.github/workflows/crctl-ci.yml`。
- 计数口径（口径必须写明，禁止混用）：状态机 = **15 个具名状态 + 注册前 `(new)`**；转移 = **声明条数**与 **wildcard 展开条数**两个口径——CR-2026-031 时点是 28 / 50，CR-2026-061 与 AIFI-17 各 +1 条后为 **31 声明**；本 CR 一律以 `tools/dir-graph.yaml` 当前内容为准。
- 本 PRD 只写到「行为 + 验收标准 + 引用先例」这一层；确定性实现算法（推导函数怎么写、清单放在哪个文件、负控怎么落地）归开发期 SDD。

**本轮第一手实测（本 PRD 作者，`tools@dddd0ad6`，CR worktree，clean）**：

| 项 | 实测事实 | 命令/方式 |
|---|---|---|
| BR-1 | `code-implementation.pipeline.json` 对 `crctl task init` **零命中**（该指令的载体是 `skills/develop/write-dev-tasks/SKILL.md`）；pipeline 节点数 16 | 逐文本搜索 = 0 命中 |
| BR-2 | `skills/review/review-alignment/SKILL.md` 对 `checkpoint` **零命中** | 逐文本搜索 = 0 命中 |
| BR-3 | `dir-graph.yaml` 声明转移 = **31**（断言 28），`from: any-active` = 2 | 逐行计数 |
| BR-4 | `write-requirement-prd/SKILL.md` 现为「七个章节**、**未替换占位符」；5 个禁用词（`engineering-docs` / `MCP` / `owClient` / `_config.yml` / `validate-doc`）**全零命中** | 逐词计数 = 0 |
| BR-5 | `emitOutboxEvent` 对同名文件按「逐字段内容相等（排除 `payload.detected_at`）」判定，不等则抛 `OUTBOX_DEDUP_CONFLICT` → 调用方记 `EMIT_FAILED` | `crctl.mjs:293` 起逐行读 |
| 5 条红 | 按测试名过滤单跑 5 条：**exit 1 / 22.7 s / 失败恰 5 条**（匹配到的用例 0 通过、0 其它失败） | `node --test --test-name-pattern='…' crctl.test.mjs checkpoint-tx.test.mjs archive-tx.test.mjs` |
| CI | `.github/workflows/crctl-ci.yml:111` = `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs`（无例外）；`:115` = writeback 单文件 | 逐行读 |
| 文件集 | `skills/shared/crctl/scripts/test/*.test.mjs` = **21 个** | 目录计数 |

诚实口径：**全量（21 个文件）的「exit 1 / 894.8 s / 失败恰 5 条」是既有实测**（AIFI-25 的作者与 reviewer 各独立跑过一次），本 PRD 作者本轮未重跑全集，只做了上表的名字过滤单跑与逐条代码/事实源核对；实现阶段必须以自己的实测替换该数字。

---

### 2. 用户故事

- **US-1（CR 作者 / 实现者）**：作为要写「全量测试通过」这条 AC 的人，我希望这条命令在基线上就是绿的，这样我不需要为每个 CR 再签一次例外授权，也不需要在计划里解释「为什么绿不了」。
- **US-2（评审者 / 测试负责人）**：作为评审与验收的人，我希望一条红色断言意味着「某条事实与事实源不一致」，而不是「某个文本的连接词换了」；我希望失败信息能直接指向被断言的事实源，这样我不必先花一轮判断是产品坏了还是断言过期了。
- **US-3（tools 维护者）**：作为改事实源的人（状态机加一条转换、Skill 文本重写、reader 换事实源），我希望我改完事实源后**在同一个 CR 内**就看到测试变红并被迫同步断言，而不是让漂移静默地积累 5 次变更。
- **US-4（owner / 治理视角）**：作为对例外负责的人，我希望任何拿不到绿的例外都在**同一处**登记着 owner 和到期日，到期没清就直接红——而不是像现在这样散落在各 CR 的 SDD 授权记录里、且明示不跨 CR 继承。
- **US-5（BR-5 的场景）**：作为维护 outbox 发射链路的人，我希望冻结的失败向量覆盖**真实发生过的崩溃窗口**（文件已写、journal 未标记），并在「同名但内容不同」时给出可见信号而不是静默去重，这样这条链路的行为契约是可检查的、不是靠注释约定的。

---

### 3. 功能需求

> 以下 FR 描述**可观察行为与交付边界**。推导算法、清单文件形态、负控落地方式归 SDD。
> 基线行号仅用于定位，**禁止依赖行号做盲改**；实施定位一律以实时搜索结果为准。

#### FR-1 计数类断言从事实源自身推导

计数类断言（状态机声明条数、wildcard 展开条数、pipeline 节点数、测试文件数等）**不得把数字写死在测试里**，必须从唯一事实源（`tools/dir-graph.yaml`、`pipeline-templates/*.pipeline.json`、目录自身）解析后推导。

推导规则必须由事实源自身的结构定义（例如 wildcard 展开数 = 声明条数 − wildcard 条数 + `any-active` 目标集合大小 × wildcard 条数），**不得引入与事实源等价的第二套硬编码**。

#### FR-2 文本类断言只查语义

文本类断言（`pipeline-templates/*.json`、`SKILL.md`、`README`、`AGENTS.md` 等）**不得把措辞、标点、连接词、缩进、行宽钉死**，必须断言语义要素：必须存在的指令名与结构性字段、必须不出现的禁用词、必须保留的校验步骤语义、必须承担的职责边界。

等价改写（同义连接词、标点、语序、换行）不得使其变红；语义变化（删除被断言的事实、把指令挪到不承担该职责的载体、加入越界或禁用内容）必须使其变红。

#### FR-3 去硬编码的反风险：推导不得宽到接受产品错误

「从事实源推导」不等于「无约束」。SDD 必须逐条分清两类事实并给出归类清单：

1. **可推导的事实**：计数、集合成员、展开规则、跨文件投影关系——由推导得到，硬编码其快照即为缺陷。
2. **必须钉死的目标值**：具名状态集合、每条转换的稳定标识（`from → to` + trigger）、gate 与 pipeline 的结构不变量、断言所依赖的受控清单——必须**显式登记**，不得由推导自动接受。

硬性底线：**推导不得退化为等价重述**（例：把「声明条数 = 28」改成「声明条数 = 当前文件行数」「断言 = 自己读到的条数」这类恒真式，等于不检查）。判据是 FR-13 的负控：向事实源注入任意一次真实漂移，断言必须变红。

#### FR-4 BR-1 同步：指令断言对齐到真实载体

`code-implementation.pipeline.json` 不再承担「`crctl task init` / 不得手写索引」的指令文本（该指令由 `skills/develop/write-dev-tasks/SKILL.md` 承担）。断言必须改为**在承担该职责的载体上**断言该指令存在，并保留对 pipeline 的语义约束（pipeline 只编排 Skill、不得指导 Agent 直写 `tasks/_index.yml`）。

该测试从红转绿，且当 `write-dev-tasks` 的相关指令消失、或 pipeline 出现「直写索引」的指导文本时，仍必须变红。

#### FR-5 BR-2 同步：reader 事实源断言对齐到当前事实源

CR-2026-060 TASK-04 起，alignment reader 的事实源是 `cr.md` + `_backlog.yml` 条目信息，`latest-checkpoint` 不再是它的事实源。断言必须改为对**当前事实源**断言（reader 的进展信息来自条目字段），并保留「不读旧 `checkpoints[]`」的既有零命中语义断言。

**不得**为了转绿而在 `SKILL.md` 里补写 `latest-checkpoint` 字样——那是把测试对齐到已废弃的事实源，属于 FR-13 意义上的假绿。

#### FR-6 BR-3 同步：状态机口径断言改为推导 + 显式登记

状态机口径断言必须：

1. 声明条数与 wildcard 展开条数**从 `dir-graph.yaml` 推导**（FR-1）；
2. 同时保留**必须钉死的目标值**断言：具名状态集合（15 个具名 + 注册前 `(new)`）、每条声明转换的稳定标识集合（`from` / `to` / trigger）显式登记；
3. 结构不变量由推导断言：每条声明的 `from` / `to` 必须属于具名状态集合（或合法的 wildcard 语义），wildcard 展开规则自洽。

新增、删除或改名任一状态或转换，必须在**引入该变更的 CR 内**使该测试变红，除非该 CR 显式更新登记的目标值——这正是「漂移当场红」在状态机面的可控形态。

#### FR-7 BR-4 同步：Skill 文本断言只查语义

`write-requirement-prd/SKILL.md` 的「落盘后重新读取并校验」断言必须改为**语义要素**断言（该校验步骤存在、且校验 frontmatter 必填字段 / 七个章节 / 未替换占位符这三类对象），**不得钉死**「和」「、」等连接词与标点。既有语义约束全部保留：5 个禁用词（`engineering-docs` / `MCP` / `owClient` / `_config.yml` / `validate-doc`）零命中、不得调用不支持 PRD 的 `validate`、不得输出手工 commit 配方。

该测试从红转绿，且当被断言的校验步骤语义被删除、或上述禁用词出现时必须变红。

#### FR-8 BR-5：保留产品「内容相等才算已发送」语义

不改产品语义：共享函数 `emitOutboxEvent`（register / archive / status / audit / trace 共用）保持——

1. 目标文件名存在且**逐字段内容相等** → 视为已发送，返回该文件名，不覆盖、不新增；
2. 文件名存在但**内容不同** → `OUTBOX_DEDUP_CONFLICT`，调用方记 `EMIT_FAILED`，不得静默去重、不得覆盖既有文件；
3. CR-2026-052 TASK-08 建立的「drift-audit 排除易变字段 `payload.detected_at`」语义**不动**，其既有测试不得回归。

不得把「同名即视为已发送」作为转绿手段，不得整条作废 RED-7。

#### FR-9 BR-5：冻结向量按「构造改对」修正并补齐真实冲突用例

1. RED-7 的 r2 构造改为**预写与本次事件内容一致的文件**（= 真实的「文件已写、journal 未标记」崩溃窗口）；
2. **原断言全部保留**：`warnings: []`、`outbox = archive-<cr>-<head>.json`、既有文件不被覆盖、origin commit 数不变、重放不再生成事件；
3. **新增显式用例**覆盖「同名但内容不同」→ 必须有**可见信号**（`EMIT_FAILED` / `OUTBOX_DEDUP_CONFLICT` 至少其一出现在结果或 audit 中）、journal 保持 pending、后续补发可成功且零新 commit。

#### FR-10 去重比较字段契约可检查

把「哪些字段参与比较、哪些易变字段必须排除」从 `crctl.mjs` 注释里的口头约定，钉成**可机器检查的契约**：

1. 参与比较的字段集合与必须排除的易变字段集合必须显式声明，且能由测试断言；
2. 契约必须**单一事实源**，不得同时存在两份（注释一份、代码一份）；
3. 契约不得放宽为「自动排除所有时间类字段」：新增一个未登记的易变字段，必须使契约检查变红。

契约的落点（导出常量 / 受控清单 / 测试内声明）归 SDD。

#### FR-11 CI 全量测试步骤成为真门禁

`.github/workflows/crctl-ci.yml` 的 `crctl full test suite` 步骤必须成为真门禁：

1. 步骤退出码 0 **当且仅当**全量失败集合为空（有例外时见 FR-14）；
2. **21 个 `*.test.mjs` 全部被真实执行**：不得整文件跳过、不得让文件级 skip 静默通过、不得靠删测试 / 改测试名 / 放宽或删除断言达成绿；
3. 「绿」必须有约束力：任何使既有断言面失效的变更（状态机增删转换、pipeline / Skill 文本语义变化、去重比较字段的易变面变化）都必须在引入它的 CR 内使该步骤变红；
4. 本 CR 必须以 FR-13 的负控实验证明第 3 条，而不是只声称。

#### FR-12 `--test-concurrency=2` 的收敛决定

对本机实测到的「30+ 分钟不收敛（父进程空闲、子进程停滞）」必须给出结论与证据：

1. 保留该参数 → 给出它在 CI 环境下可收敛、可复现的证据；
2. 或按实测改写（去掉该参数 / 调整并发度 / 其它可复现方案）→ 给出改写前后的对比数据；
3. 决定必须同时落在 CI 配置与文档/测试说明的**同一口径**上，不得一半在 CI、一半在别处；
4. 证据必须可复现（命令 + 耗时 + 是否停滞的观察），不得只写结论。

#### FR-13 漂移当场红的负控证据

「绿有约束力」必须由本 CR 自证，且证据可重放：

1. 对每一类被覆盖的断言（状态机口径、pipeline/Skill 文本语义、去重比较字段契约）各注入一次**真实漂移**（例如：向 `dir-graph.yaml` 加一条转换；向某个 `SKILL.md` 注入一个禁用词或删除被断言的校验步骤语义；给事件新增一个未登记的易变字段）；
2. 每次注入后，全量测试必须在**本 CR 内**变红；还原后恢复绿；
3. 负控必须是可重放的测试或命令，不得以人工观察作为证据；
4. 注入物不得留在交付分支（不得为了证明而永久保留失败用例或放宽断言）。

#### FR-14 例外治理：单一登记处 + owner + 到期，到期未清即红

若本 CR 结束时仍存在例外（未能转绿的失败用例、被跳过的用例、已知不收敛的配置），必须：

1. **单一登记处**：所有例外登记在同一处（单一清单文件或单一 CI 步骤内），不得散落多处，也不得只存在于某个 CR 的 SDD 授权记录里；
2. 每条例外至少含：稳定标识（测试名或断言标识）、原因、**owner**、**到期**（日期或可判定的条件）；
3. **到期未清即红**：到期已过而例外仍在 → 门禁失败，不得静默续期；
4. **不得自证绿**：例外清单只能经受控写入变更，测试代码不得写入或自动续期例外；例外标识与实际失败集合不匹配时门禁红；
5. 无例外时该面必须**显式声明为空**，不得以「文件不存在」充当空。

例外是过渡手段：本 CR 的目标是例外集合为空（FR-11 的「失败集合为空」）；第 1…5 条是为「届时仍有例外」准备的兜底治理，不是把例外合法化。

#### FR-15 范围与产品语义的最小改写

1. BR-1…BR-4 只改测试；
2. BR-5 只改测试构造，以及为 FR-10 所需的最小产品面（把去重比较字段契约从注释变为可检查声明）——不得改变 `emitOutboxEvent` 的去重语义；
3. 不改状态机、错误码、事务语义、`reviewLoop` / archive / merge / checkpoint / writeback 的业务算法；
4. 不改 `write-tech-design` / `review-tech-design` 的 SDD 评审合同（包 B，owner 已明确不做）；
5. 不含 CR-2026-064 的恢复合同迁移本身；
6. 不新增测试框架、不引入新的第三方依赖（含 YAML 解析依赖）。

#### FR-16 零回归与覆盖不降级

转绿不得以牺牲覆盖换取：4 条漂移对应的断言在转绿后必须**仍能在其事实源变化时变红**（由 FR-13 负控证明）；21 个文件的既有通过集合之外不得出现新的红、不得出现新的 skip。

#### FR-17 契约面声明与确定性四查

本 CR **不新增、不修改用户可调用契约**：不新增 crctl 子命令或 flag、不新增 HTTP 端点、不改 Skill 参数契约、不新增受治理账本的写路径（断言只读，见 4.2）。

唯一具有契约性质的内部面是 FR-14 的**例外登记面**（人 / CI 之间的约定），其确定性按四查给出（实现落点归 SDD）：

- **幂等**：同一稳定标识重复登记不产生重复条目；同一例外在同一到期日内重复检查结论一致（不得因检查次数改变门禁结果）。
- **权限与写入边界**：例外清单只能经受控写入变更；测试代码与产品代码不得写入或自动续期；变更必须可审计（谁、何时、为什么）。
- **错误闭包**：缺失稳定标识 / 缺失原因 / 缺失 owner / 缺失到期 / 到期已过仍存在 / 例外标识与真实失败集合不匹配 → 门禁失败 + 明确错误消息 + 零写入（不得静默通过、不得静默改写清单）。
- **副作用**：登记只影响门禁结论，不改变测试执行本身；不得以登记替代执行（登记了「已跳过」的用例仍必须由 CI 真实报告其状态）。

若 SDD 在实现中决定新增任何对外可调用入口（新命令 / flag / 契约字段），必须在本 CR 内按上述四查同批补齐，不得留作后续。

---

### 4. 非功能需求

#### 4.1 性能

- 全量测试耗时不得因本 CR 显著恶化；交付物必须给出基线与本次实测的同口径对比（基线数字：`tools@dddd0ad6` 上不带例外 = exit 1 / 894.8 s / 失败恰 5 条，为既有实测）。
- 推导类断言只读本地文件，不得引入网络、子进程风暴或额外的全仓扫描；不得把「推导」实现为对每个断言都重新遍历仓库。
- 若 FR-12 改写并发参数，必须给出 CI 上的耗时证据。

#### 4.2 安全

- **例外登记不得成为自证绿通道**：测试与产品代码均不得写入/续期例外清单（FR-14.4）。
- **断言不得被弱化为恒真**：任何「推导」都必须保留拒绝产品错误的能力（FR-3），由负控证明。
- **不改写入边界**：本 CR 不新增对 `_backlog.yml` / `cr.md` / `approval.yml` 等受治理文件的写入路径；断言只读。

#### 4.3 兼容性

- **行尾规范**：任何读文件做哈希、跨行正则或逐行解析的断言，必须先做 `\r\n → \n` 规范化；解析用 `split(/\r?\n/)`；跨行正则解析失败必须硬失败报错，禁止静默降级（既有工程纪律）。
- **双环境一致**：同一断言在 Windows 本机（CR worktree，autocrlf 检出）与 CI（bash）下必须得到一致结论；不得依赖 shell 特有行为。
- **Node 版本**：断言与命令必须在 CI 使用的 Node 版本与本机 Node（实测 `v24.15.0`）下均可运行，不得依赖两者的行为差异。
- **历史证据不改写**：不改写历史 CR 的产物与归档证据；本 CR 只对齐当前活跃事实源。
- **不与 CR-2026-064 耦合**：本 CR 的交付不依赖、也不改变 `recoverCommand` / `recover_command` 现状（该迁移仍冻结在 AIFI-25）。

---

### 5. 验收标准

> 本 CR 只有同时满足以下全部条件才算完成。每条 AC 都必须能在固定 commit 上用命令复核。

- **AC-01（FR-11）CI 全量步骤真门禁**：`crctl full test suite` 步骤使用最终口径命令（参数以 FR-12 决定为准）执行 `skills/shared/crctl/scripts/test/*.test.mjs` 时 **exit 0**，失败集合为空；执行到的测试总数 > 0 且文件级 skip 数为 0（21 个文件全部被真实执行）；同一命令在同一 commit 上可复现。
- **AC-02（FR-1、FR-2）断言去硬编码审计**：交付内含「断言 → 事实源」映射，覆盖 BR-1…BR-4 所在的断言类别（计数类、文本类、跨文件投影类）；表中每条断言的事实源可由命令取得，且该断言的取值随事实源变化而变化（以负控为证）。
- **AC-03（FR-3）可推导事实 vs 必须钉死目标值的分界**：交付内含逐条归类清单；「必须钉死」的目标值（具名状态集合、转换稳定标识集合、受控清单）显式登记；推导项中不存在与事实源等价的第二套硬编码（「等于文件行数」类恒真式被显式排除）。
- **AC-04（FR-4）BR-1 转绿**：该测试通过；断言对象是指令的真实载体；对 pipeline 的「只编排 Skill、不指导直写 `tasks/_index.yml`」语义断言保留。
- **AC-05（FR-5）BR-2 转绿**：该测试通过；且 `review-alignment/SKILL.md` 未新增 `latest-checkpoint` 字样（除非 reader 的事实源确实回到该字段，且该回退本身有独立依据）。
- **AC-06（FR-6）BR-3 转绿**：状态机口径测试通过；声明数与展开数由 `dir-graph.yaml` 推导；具名状态与转换稳定标识显式登记；负控：向 `dir-graph.yaml` 增加一条转换 → 该测试变红（证据留存）。
- **AC-07（FR-2、FR-7）BR-4 转绿**：`CR-2026-042 静态合同…` 测试通过；5 个禁用词仍零命中；负控：向 `write-requirement-prd/SKILL.md` 注入一个禁用词或删除被断言的校验步骤语义 → 该测试变红（证据留存）。
- **AC-08（FR-8、FR-9）BR-5 修正且语义未变**：RED-7 用例通过且其构造为「预写与本次事件内容一致的文件」（真实崩溃窗口），原断言（`warnings: []`、`outbox = archive-<cr>-<head>.json`、不覆盖、origin commit 数不变）全部保留；「同名但内容不同」新用例通过并断言可见信号（`EMIT_FAILED` / `OUTBOX_DEDUP_CONFLICT`）、journal 保持 pending、后续补发成功；CR-2026-052 TASK-08 的 `detected_at` 语义测试不回归。
- **AC-09（FR-10）去重比较契约可检查**：存在单一事实源的声明（参与比较字段 + 必须排除的易变字段），并有测试对其断言；负控：给事件新增一个未登记的易变字段 → 契约检查变红（证据留存）。
- **AC-10（FR-12）并发参数决定**：交付内给出决定与可复现证据（命令、耗时、是否停滞）；CI 配置与文档口径一致，无「一半在 CI、一半在别处」。
- **AC-11（FR-13）漂移当场红负控**：状态机、文本语义、去重契约三类断言各完成一次注入 → 全量测试变红 → 还原后恢复绿；命令与关键输出留存；注入物不在交付分支中。
- **AC-12（FR-14）例外治理**：若存在例外 → 单一登记处且每条含 owner + 到期；构造一条到期例外 → 门禁红；例外清单的变更不来自测试代码；无例外 → 显式声明为空（非「文件不存在」）。
- **AC-13（FR-15）范围与语义边界**：变更集审计显示 diff 只落在 tests / CI 配置 / 去重契约所需的最小产品面；BR-1…BR-4 的产品面零 diff；无新增依赖或测试框架；不含包 B 与 CR-2026-064 迁移面。
- **AC-14（FR-16）零回归与耗时对比**：全量 21 个文件通过集合中无新增红、无新增 skip；给出与基线（894.8 s）同口径的耗时对比。
- **AC-15（FR-17）契约面与四查**：交付内声明本 CR 不新增用户可调用契约；例外登记面按四查给出幂等 / 权限与写入边界 / 错误闭包 / 副作用的确定结论；若实现新增了对外入口，则四查已同批补齐。

---

### 6. 成功指标

> 本节只列**一次性可核查的发布期事实**与一个有界观察窗口，不引入运行期 SLO 或统计平台改造。

| 指标 | 判定方式 | 目标 |
|---|---|---|
| 基线转绿 | 全量命令退出码 + 失败集合 | exit 0、失败集合为空、21 个文件全部执行 |
| 断言不再依赖硬编码快照 | 断言→事实源映射 + 负控实验 | 覆盖 BR-1…BR-4 全部断言类别，每类负控可变红 |
| 漂移当场红 | 三类负控注入 | 注入即红、还原即绿，证据可重放 |
| 例外有主有期 | 例外登记处内容检查 | 例外集合为空，或每条含 owner + 到期且到期即红 |
| 重复成本消除 | 归档后最近 3 个 CR 的 SDD/计划文本检查 | 不再出现「全量绿不可达 → 需新例外授权」的记录 |
| CI 步骤连续可信 | 观察窗口内该步骤的 CI 结论 | 连续绿；期间任何事实源漂移由引入它的 CR 承担变红 |

---

### 7. 范围排除

1. **不含包 B**：不改 `write-tech-design` / `review-tech-design` 的 SDD 评审合同（例如要求 SDD 携带 AC 命令的实跑证据）——owner 已明确不做（会把 plan/TASK 的工作提前到 SDD 期并造成重做），若将来要做另立 CR。
2. **不含 CR-2026-064 的恢复合同迁移本身**：该 CR 原地冻结在 `tech-design-review-pending`，本 CR 完成后再回到它。
3. **不改 5 条红的根因对象本身**：pipeline 文本、状态机条目、`write-requirement-prd` 文本、alignment reader 合同、archive outbox 链路的**业务语义**均不在本 CR 内变更；本 CR 只让断言与事实源一致（BR-5 按 owner 裁定只改测试构造 + 契约声明）。
4. **不改 CI 之外的交付/发布流程**：不含 push-progress、merge、archive、writeback 的算法与门禁语义。
5. **不含 multica 仓测试面**：本 CR 只针对 tools 仓的测试与 CI 配置。
6. **不新增测试框架 / 第三方依赖**：复用既有 Node 测试运行器与既有断言方式。
7. **不以降低断言强度换绿**：不得删除用例、整条作废（BR-5 只改构造）、把断言改为恒真、靠 skip 少红。
8. **不改写历史证据**：历史 CR 产物、归档 traceability/delivery 证据保持原样。
9. **不做平台 Prompt 部署**：tools 侧的 Skill/Agent 文本变化若涉及平台部署，由 owner 另行执行，本 CR 不声称平台侧已生效。

## CR-R：结构化恢复合同原子迁移 — `recoverCommand`/`recover_command` 全量退役为结构化 `recovery`（v0.37 · CR-2026-064）

### 1. 概述

#### 1.1 问题陈述

crctl 的多个事务在失败或可恢复中间态中，把「恢复动作」以 shell 命令字符串形式返回：

```json
{ "recoverCommand": "crctl review-loop reset CR-2026-062 --loop review-tech-design --reason \"...\"" }
```

部分 CLI 路径还同时投影 `recoverCommand` 与 `recover_command` 两个同义字段。

该合同把三种互不相同的责任混在一个字符串里：**机器执行入口**、**参数值与参数边界**、**人类显示文本**。由此产生四类缺陷：

1. **shell 语义可被输入改变**：用户输入（如 reset `--reason`）、workspace 路径、branch/ref 经字符串拼接后进入命令，`"`、`;`、`$()`、反引号、换行都可能改变执行语义；
2. **跨 shell 不可移植**：bash、PowerShell、cmd 的引号与转义规则不同，同一字符串在不同终端语义不同；
3. **显示文本被当执行合同**：Agent 可能直接执行本应只用于展示的字符串；两个同义字段还形成重复投影，消费方无从判断哪个是事实源；
4. **测试不具证明力**：现有测试用 `result.recoverCommand.includes('...')` 只能证明字符串片段存在，无法证明 argv 边界正确。

本 CR 注册时由 `crctl register` 返回的结果本身即同时包含 `recoverCommand` 与 `recover_command` 两个字段，是该缺陷仍在生产路径上的现存实例。

#### 1.2 解决方案摘要

把恢复动作从「命令字符串」改为**唯一的结构化数据字段 `recovery`**（`executable` + `args[]` + 可选 `cwd` + `requiresTTY` + `promptFor[]`），执行方一律以非 shell 的 argv 方式调用；需要人重新输入的值不进入 `args[]`，只经 `promptFor[]` 声明。

本 CR 是**单发布原子迁移**：在同一个 CR 内完成全部已知生产者与全部活跃消费者的切换，并在同一个 CR 内删除 `recoverCommand` / `recover_command`，复用既有 contract-scan 防止退役字段回流。不设双写兼容期、不留 deprecated alias、不生成 migration shim、不拆第二个删除 CR。

前提事实：当前不存在仓外机器消费者；活跃生产者与消费者可在同一 tools 发布中同步切换。因此整体原子切换比长期兼容层成本更低、可靠性更高。

#### 1.3 需求来源与事实源

- 需求来源文档：`crctl_recoverCommand结构化恢复合同_原子迁移方案.md`（AIFI-25 议题附件），其 §3 定义目标合同、§4 定义盘上影响面、§6 定义安全测试向量、§7 定义交付边界、§8 定义验收条件。
- 边界来源：`AIFI-18_SDD到planTASK_原位修订方案.md` §2——四个 CR（CR-P0 / CR-R / CR-P1 / CR-P2）分别评审、审批、回滚，**不得合并为一个发布单元**；CR-P0 已作为 CR-2026-063 归档；CR-R 只负责 recovery 合同迁移。
- 本 PRD 只写到「行为 + 验收标准 + 引用先例」这一层。确定性算法的实现细节（构造器是否提取、逐文件改法、错误消息文案、契约扫描实现方式）归开发期 SDD。

---

### 2. 用户故事

- **US-1（执行方 / Agent）**：作为收到 crctl 可恢复结果的 Agent 或脚本，我希望恢复动作是结构化 argv 数据而不是命令字符串，这样我可以直接用 `spawn`/`execFile` 类接口按参数边界执行，不必自己判断当前 shell 的转义规则，也不会把展示文本误当执行合同。

- **US-2（CR owner / 人类操作者）**：作为在终端处理失败事务的人，我希望需要我重新确认的值（如 reset 的 reason）被明确声明为「执行时向人索取」，而不是把上一轮的旧值回显在一条可复制命令里，这样我不会无意中复用一个已经不成立的理由。

- **US-3（crctl 维护者）**：作为维护 crctl 事务层的开发者，我希望恢复合同只有一个字段名、一套语义，这样我新增或修改一个可恢复场景时不需要同时维护两个投影，也不需要判断哪个字段是权威的。

- **US-4（评审者 / 测试者）**：作为评审与测试的人，我希望恢复合同的测试断言的是确定的 `executable` 与逐元素 `args[]`，而不是字符串包含，这样测试能真正证明参数边界正确，而不是证明某个片段出现过。

- **US-5（安全视角）**：作为关心注入面的人，我希望用户可控输入（reason、路径、ref）永远不会被拼接进一条会被 shell 解释的字符串，这样含 `"`、`;`、换行、`$()`、反引号的输入不再具备改变执行语义的能力。

---

### 3. 功能需求

> 以下 FR 描述**可观察行为与交付边界**。具体实现算法（是否提取公共构造器、逐文件改写顺序、扫描器实现）归 SDD。
> 实施定位一律以 `rg "recoverCommand|recover_command"` 的实时搜索结果为准；来源文档中的行号仅为参考，**禁止依赖行号做盲改**。

#### FR-1 唯一恢复合同字段 `recovery`

crctl 所有可恢复结果必须以唯一字段 `recovery` 表达恢复动作，字段语义如下：

| 字段 | 类型 | 规则 |
|---|---|---|
| `executable` | 非空 string | 实际可执行入口（如 `crctl`、`node`）；不得包含参数或 shell 运算符 |
| `args` | string[] | 每个元素是一个完整 argv；不得把多个参数拼成单个元素 |
| `cwd` | 绝对路径 string 或省略 | 仅当恢复动作必须位于特定 workspace 时返回；不得依赖调用方猜测 |
| `requiresTTY` | boolean | 是否必须在可信交互终端执行 |
| `promptFor` | string[] | 执行时需重新向人获取的逻辑值（如 `reason`）；这些值不得预先拼入 `args` |

`recovery` 是恢复动作的**唯一机器执行事实源**。

#### FR-2 argv 边界与参数完整性

1. CR-ID、workspace、branch/ref、路径等每个参数各自占据独立的 `args[]` 元素；
2. `args[]` 的顺序与目标 CLI 的参数顺序一致；
3. 含空格的路径不依赖任何额外引号即可正确传递；
4. 结果中不得返回等价的 shell string 作为「备用执行入口」。

#### FR-3 `executable` 安全约束

`executable` 不得包含：空格分隔的参数、管道 `|`、重定向 `>` `<`、分隔符 `;`、连接符 `&&`、命令替换 `$()` 或反引号、任何 shell 展开。使用 `node` 作为入口时，脚本路径必须是 `args[0]`，不得并入 `executable` 字符串。

#### FR-4 `promptFor[]` 人工输入行为

对必须由人确认的值（如 `review-loop reset` 的 reason）：

1. 该值**不出现在** `args[]` 中，也不出现在任何 shell string 中；
2. 通过 `promptFor: ["reason"]` 声明，并按需置 `requiresTTY: true`；
3. 执行方必须在可信 TTY 中重新向人获取该值，并按目标 CLI 既有交互入口传入；
4. 执行方**不得**从旧错误消息、评论或日志中提取该值后自动复用；
5. 非 TTY 环境下执行方停止并报告所需的人类动作。

本 CR 不引入新的交互协议；`promptFor` 只是把既有的人工输入要求结构化声明出来。

#### FR-5 全部已知生产者迁移

`tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 中全部可恢复场景原位改为返回 `recovery`，至少覆盖：**register、workspace sync、merge、publication lag → checkpoint、checkpoint、writeback traceability、writeback apply、archive、test**。

每个生产者迁移时：保留原错误码与恢复时机；把命令 token 拆成独立 args；workspace / ref / path / reason 不进入模板字符串；需特定 workspace 时写入 `cwd`；**在同一位置删除旧字段，而不是并排双写**。

#### FR-6 CLI 投影迁移

`tools/skills/shared/crctl/scripts/crctl.mjs` 原位完成：接收并透传 `recovery`；删除 `recoverCommand` 与 `recover_command` 两个字段的 projection（含双投影位置）；`review-loop reset`（CR-P0 中新增的安全兼容恢复结果）直接返回结构化 `recovery`；CLI 层不得重新拼接 shell string。

#### FR-7 全部活跃 Skill / Agent 消费者迁移

至少原位修改：`tools/skills/shared/crctl/SKILL.md`、`tools/skills/writeback/merge-feature-branch/SKILL.md`、`tools/skills/sync/push-progress/SKILL.md`、`tools/skills/cr/cr-archive/SKILL.md`、`multica/cr-prompts-revised/delivery-agent.md`，以及实施时搜索发现的其它活跃 Agent / Skill / Pipeline 引用。

修改规则：把「执行 `recoverCommand`」改为读取 `recovery.executable` / `recovery.args[]` / `cwd` / `requiresTTY` / `promptFor[]`；Agent 不自行转义或补写参数；缺少必需字段时报告合同错误，不猜测恢复命令。`multica/` overlay 文件只提供 owner 可复制版本，本 CR 不更新平台 DB。

#### FR-8 文档迁移且不产生第二套合同

原位修改 `tools/README.md` 与 `tools/openwiki/operations/crctl-transactions.md` 的事实源或其既有生成输入。若 openwiki 文件由生成流程维护，则修改其权威输入后重新生成；**不得同时手工维护第二套合同描述**。

#### FR-9 测试改为结构断言

至少原位迁移：`archive-tx.test.mjs`、`checkpoint-tx.test.mjs`、`merge-tx.test.mjs`、`register-tx.test.mjs`、`workspace-freshness.test.mjs`、`writeback-tx.test.mjs`，以及 `crctl.test.mjs` 中的 reset 恢复合同测试。

原有 `result.recoverCommand.includes('...')` 形式的字符串断言改为结构断言，例如：

```js
assert.equal(result.recovery.executable, 'crctl');
assert.deepEqual(result.recovery.args, [/* exact argv */]);
assert.equal(result.recovery.requiresTTY, false);
assert.deepEqual(result.recovery.promptFor, []);
```

涉及临时路径时断言数组元素与顺序，**不对完整 JSON 做脆弱快照**。

#### FR-10 旧字段同 CR 删除，不留兼容路径

在本 CR 内删除：全部生产者的 `recoverCommand`；全部生产者的 `recover_command`；`crctl.mjs` 的兼容 projection；测试中的字符串断言；活跃 Skill / Agent / Pipeline 中的旧消费说明；README 中的旧合同示例。

不得保留 deprecated alias、不得生成 migration shim、不得新增「若无 `recovery` 则读取 `recoverCommand`」形式的 fallback。

#### FR-11 contract-scan 退役保护

复用**既有**静态合同扫描机制，把 `recoverCommand` 与 `recover_command` 两个名称加入退役字段禁止清单。

- 扫描范围：活跃源码、活跃 Skill、活跃 Agent、Pipeline、活跃测试。
- 允许排除：历史 CR、历史 traceability、归档 delivery 证据、changelog/migration 文档、contract-scan 自身的禁止名单。
- **不得**把「全仓零命中」作为唯一实现，因为历史证据合法地包含旧字段。

#### FR-12 安全测试向量

每类生产者至少覆盖与其输入相关的边界（不要求每函数全排列）：

1. **参数边界**：CR-ID、workspace、branch/ref 处于独立 `args[]` 元素；含空格路径无需额外引号；参数顺序与 CLI 合同完全一致。
2. **用户输入**：reason 至少覆盖 `normal reason`、含双引号值、含分号值、含换行值、`$(substitution)`、反引号表达式；预期 reset 的 `args[]` 不包含 reason，`promptFor` 包含 `reason`，JSON 序列化后仍是数据、不形成 shell command。
3. **executable 安全**：按 FR-3 断言。
4. **合同缺失**：消费方在「无 `executable`」「`args` 非数组」「`requiresTTY=true` 但环境无 TTY」「`promptFor` 非空却无允许的人类输入入口」四种情况下必须停止并报告合同错误，且**不得自动回退旧字段**（旧字段在本 CR 已删除）。

#### FR-13 既有语义零改变

本次修改不得改变：既有错误码、exit code、transaction id、route、files、rollback 信息的原义；reviewLoop、archive、merge、checkpoint、writeback 的业务算法；状态机转换与门禁语义。

#### FR-14 实施前有界盘点

进入编码前执行一次有界搜索（排除 `node_modules`、`.git`），范围至少覆盖 `tools/` 与 `multica/cr-prompts-revised/`，把结果按 **producer / code consumer / Prompt-Skill consumer / active test / active docs / historical evidence（排除）** 六类归档到本 CR 的实施计划。该盘点只用于确保本次原子迁移不漏调用方，**不得转化为持续观测机制**。

#### FR-15 整体回滚

本迁移是单发布原子切换，回滚必须整体进行：

1. 若本 CR 在合并前失败，回滚整个 CR；
2. 不保留「部分生产者新合同、部分消费者旧合同」的分支状态；
3. 不通过临时恢复 `recoverCommand` 让半迁移版本发布；
4. 已发布版本若必须回退，回退到上一完整 tools 版本，而不是在当前版本双写。

#### FR-16 回写与平台部署边界

本 CR 包含正常 writeback 所需的 `specs/` 与 `delivery/` 更新。tools 发布后，由 owner 更新引用恢复合同的 Multica 平台 Prompt；**本 CR 不得声称平台 DB 已部署**。

#### FR-17 合同确定性（幂等 / 判定顺序 / 错误闭包 / 副作用）

`recovery` 是 crctl 对外的可调用契约的一部分，其确定性规则如下（实现算法归 SDD）：

**幂等**：`recovery` 是同一失败态的确定性投影。指纹参与字段集合固定为 `executable` + `args[]` 有序序列 + `cwd`（省略时视为不参与）+ `requiresTTY` + `promptFor[]` 有序序列；同一 CR、同一事务、同一失败态重复求值必须产出逐元素相等的结果，不得含时间戳、随机数、进程 id 或环境相关的可变成分。重复消费 `recovery` 不改变其值，也不改变原事务的幂等结论——恢复语义仍由原有事务重跑规则决定。

**判定顺序（消费方校验）**：消费方必须按固定顺序判定并以**首个**不满足项作为唯一结论，禁止「A 或 B」式并列——
1. `executable` 存在且为非空 string 且满足 FR-3；
2. `args` 为数组且每个元素为 string；
3. `cwd` 若存在则为绝对路径；
4. `requiresTTY` 为 true 时当前环境必须具备可信 TTY；
5. `promptFor` 非空时必须存在允许的人类输入入口。

**错误闭包**：上述每一类不满足都必须闭合为「停止执行 + 报告合同错误 + 零执行副作用 + 明确的人类/调用方动作」，至少覆盖：合同字段缺失或类型错误、`executable` 违反安全约束、TTY 要求不满足、`promptFor` 无输入入口。四类均不得自动回退旧字段、不得猜测恢复命令、不得降级为字符串执行。

**副作用**：`recovery` 本身是纯数据，求值与返回**零副作用**（不执行命令、不渲染字符串、不写文件）。生产者返回 `recovery` 不得改变其原有的写入范围、事务边界与回滚语义（见 FR-13）。人类界面若需显示命令，只能从 `recovery` 渲染；**显示结果不得反向作为执行输入**。消费方一律使用非 shell 的 argv 执行方式，禁止 `shell: true` 与 `Invoke-Expression`。

---

### 4. 非功能需求

#### 4.1 性能

- `recovery` 为纯数据结构，不引入命令执行、字符串解析或额外 I/O，对既有事务路径的开销增量可忽略；
- 本 CR 不新增常驻进程、不新增扫描调度；FR-11 的退役扫描复用既有静态扫描机制，不新增独立流水线阶段。

#### 4.2 安全

- **注入面闭合**：用户可控输入（reason、路径、ref）不再进入任何会被 shell 解释的字符串；含 `"`、`;`、换行、`$()`、反引号的输入在 JSON 序列化后仍为数据；
- **执行方式约束**：全部代码消费者使用 argv 边界的执行接口，禁止 `shell: true` 与 `Invoke-Expression`；
- **人在环保持**：`requiresTTY` / `promptFor[]` 只结构化声明既有的人工确认要求，不削弱任何既有人工门禁，也不新增绕过路径。

#### 4.3 兼容性

- **无外部机器消费者前提**：当前不存在仓外机器消费者，活跃生产者与消费者在同一 tools 发布中同步切换；
- **无兼容层**：不提供双写、deprecated alias、migration shim 或 fallback 读取路径；
- **历史证据不改写**：不改写历史 CR、历史 traceability、归档 delivery 证据；旧字段允许继续存在于这些历史材料中；
- **CR 独立性**：本 CR 与 CR-P0 / CR-P1 / CR-P2 分别评审、审批、回滚，不得合并为一个发布单元。

---

### 5. 验收标准

> 对应来源文档 §8「验收条件」。本 CR 只有同时满足以下全部条件才算完成。

- **AC-01（对应 FR-1、FR-2）**：所有可恢复结果使用 `recovery`，字段语义与 FR-1 表格一致；`args[]` 保持逐参数边界且顺序与目标 CLI 一致；结果中不存在等价 shell string 备用入口。
- **AC-02（对应 FR-5、FR-6）**：register、workspace、merge、checkpoint、writeback、archive、test、reset 八类恢复路径的测试全部通过，且其恢复结果均为结构化 `recovery`。
- **AC-03（对应 FR-4、FR-12.2）**：用户提供的 reason 不出现在 reset 的 `args[]` 中，也不出现在任何 shell string 中；`promptFor` 包含 `reason`；六类恶意/特殊 reason 输入在序列化后仍为数据。
- **AC-04（对应 FR-17 副作用段）**：所有代码消费者使用 argv 边界执行，代码中不存在 `shell: true` 或 `Invoke-Expression` 用于执行恢复动作。
- **AC-05（对应 FR-7、FR-8、FR-9、FR-10）**：活跃源代码、活跃 Skill、活跃 Agent、Pipeline、README 与活跃测试均不再消费 `recoverCommand` / `recover_command`；不存在 deprecated alias、migration shim 或旧字段 fallback。
- **AC-06（对应 FR-11）**：`recoverCommand` / `recover_command` 仅允许出现在历史证据、迁移文档与退役禁止名单中；contract-scan 在活跃范围命中旧字段时失败，且对允许排除范围不误报。
- **AC-07（对应 FR-13）**：既有 crctl、ledger transaction、workspace freshness、merge、writeback、archive 全量测试通过。
- **AC-08（对应 FR-13）**：修改未改变错误码、状态转换、transaction id、rollback 或 files 语义（以既有测试与逐项核对为证）。
- **AC-09（对应 FR-16）**：tools 发布后由 owner 更新引用恢复合同的 Multica 平台 Prompt；本 CR 的交付物与结论中不出现「平台 DB 已部署」的声称。
- **AC-10（对应 FR-3、FR-12.3）**：`executable` 不含空格分隔参数与任何 shell 运算符；以 `node` 为入口时脚本路径位于 `args[0]`。
- **AC-11（对应 FR-12.4、FR-17 判定顺序/错误闭包）**：四类合同缺失场景下消费方均停止并报告合同错误，零执行副作用，且不回退旧字段；判定按固定顺序给出唯一结论。
- **AC-12（对应 FR-14）**：实施计划中存在一次有界盘点结果，并按 producer / code consumer / Prompt-Skill consumer / active test / active docs / historical evidence 六类归档；未因此新增任何持续观测机制。
- **AC-13（对应 FR-15）**：交付分支不存在「部分生产者新合同、部分消费者旧合同」的中间状态；回滚方案为整体回滚。
- **AC-14（对应 FR-16）**：正常 writeback 所需的 `specs/` 与 `delivery/` 更新已包含在本 CR 内。

---

### 6. 成功指标

> 来源文档 §2.2 明确不新增使用量、失败率、SLO 或迁移统计。因此本节只列**一次性可核查的发布期事实**，不引入运行期观测或计数门禁。

| 指标 | 判定方式 | 目标 |
|---|---|---|
| 恢复合同单一性 | 活跃范围内恢复结果字段名清点 | 仅 `recovery` 一个，旧字段 0 处活跃引用 |
| 注入面闭合 | FR-12.2 的六类 reason 向量测试 | 全部通过，reason 不进 `args[]` / 不进 shell string |
| 语义零漂移 | 既有 crctl / ledger / freshness / merge / writeback / archive 全量测试 | 全绿，无错误码或状态转换变更 |
| 退役保护有效性 | contract-scan 正反用例 | 活跃范围命中即失败；历史证据与禁止名单自身不误报 |
| 迁移完整性 | FR-14 有界盘点六类归档 | 无「已知调用方未迁移」遗留项 |
| 原子性 | 交付分支状态核对 | 无半迁移中间态；回滚方案为整体回滚 |

---

### 7. 范围排除

本 CR **明确不做**以下内容（来源文档 §2.2 与 §7.2）：

1. 不新增通用命令执行框架；
2. 不新增 shell parser、quoting library 或跨 shell renderer；
3. 不改变 reviewLoop、archive、merge、checkpoint、writeback 的业务算法；
4. 不增加兼容层、双写期或 deprecation 周期；
5. 不改写历史 CR、历史 traceability 或归档 delivery 证据；
6. 不更新 Multica DB（平台 Prompt 部署由 owner 另行执行）；
7. 不新增使用量、失败率、SLO 或迁移统计；
8. 不包含 AIFI-18 的 SDD review 规则；
9. 不包含 `_context.md` 删除（属已归档的 CR-P0 / CR-2026-063）；
10. 不包含 plan/TASK 增量回修（属 CR-P2）；
11. 不调整 Pipeline 节点；
12. 不改造 Multica API 或 importer（含 `aifirst/agent-import.mjs`）；
13. 不拆出第二个「删除旧字段」的 CR；
14. 不与 CR-P1 / CR-P2 合并为同一发布单元。

## CR-P3：评审 PASS 发布与 checkpoint 委派收敛 — 阶段终点发布点前移、审批后 checkpoint 节点退役、归档后本地 trunk 同步（v0.39 · CR-2026-066）

## 1. 概述

### 1.1 问题陈述

需求来源是 Issue AIFI-27 附件《CR-P3：评审 PASS 发布与 checkpoint 委派收敛方案》（19,297 B，附件 id `01a09dc1-7230-7618-8137-9c0b8adbe1b8`）§1–§2。CR-2026-063（AIFI-24）全生命周期的实测暴露出一组**发布点位置**问题：

1. **阶段终点 checkpoint 位于人工审批 gate 之后**（requirement `…0007`、architecture `…0005`、code `…0012`）。agent 驱动模式下，阶段 owner 的那次 run 在 gate 之前就已结束；要执行门后节点**必须新开一次唤醒**，而 `agent-skill-matrix.yml` 明令 `cr-coordinator-agent` 不可执行 `push-progress`，于是这一步只能被单独委派出去。CR-2026-063 的 6 次 checkpoint 里有 3 次是这种「只做这一步」的单独委派（来源 §1.1）。
2. **冗余发布点**：requirement `…0003`（PRD 草稿）、code `…0003`（设计/任务）、`…0008`（代码+文档统一 checkpoint）、`…0015`（评审 PASS 后、审批前）都是为「让远端有批次」而存在的额外节点。其中 `…0008`/`…0015` 还使「实现→评审→审批」窗口内出现两次 checkpoint，而这些节点在 agent 驱动模式下同样没有强制力（无 runtime 检查「跑没跑」，`abort` 只是纸面强度）。
3. **评审对象与发布对象之间没有强制对账**：评审者按 worktree 文件出 verdict，发布由**另一个**节点在之后执行；「审的不是发的」这一窗口只靠流程纪律约束，没有机械判据。
4. **归档后本地主 checkout 与 origin 不一致**：`reconcileLocalTrunks(ctx)` 目前只被 merge 调用；归档是 CR 的最后一个动作，此后没有任何节点把各仓主 checkout ff-only 对齐 origin，只能靠 owner 手工执行。

**根因结论（来源 §1.2，本 PRD 采纳）**：门后有没有节点，唤醒都得发生；消除单飞要靠**「发布点位置 + 搭车规则」**，不是靠节点存在与否。因此本 CR 的两条主杠杆是：把阶段终点发布点前移到**评审 PASS**（由评审者执行，每阶段恰好一次），并把审批后的发布交给**搭车**（下一阶段评审 checkpoint / `merge` 的 publication preflight）。

### 1.2 解决方案摘要

按来源 §3「目标节奏」逐条落地（每组都锚定「仓 + 文件」，见 §1.3.1 与 §3 各 FR）：

1. **评审 PASS 发布**（FR-1）：`review-requirement` / `review-tech-design` / `review-dev-plan` / `review-code` 四个 SKILL 在 PASS 分支新增发布步骤——`review-record`（及该阶段既有 `advance`）完成、工作树干净之后调用既有 `push-progress`（`message = <阶段>评审通过`），消费 `phase` / `batchId` / `repositories[]` / `metadataCommit` 并在评审报告透传；BLOCK 分支不发布。
2. **评审前置干净检查**（FR-2）：四个 review SKILL 的 Step 1 新增 `crctl workspace inspect <CR>` 全部 resources `classification=healthy`（`dirty=false`）前置（该前置是**只读**既有子命令，其授权由 FR-8 同步写入评审者允许面，见 §1.5 第 5 条）；不满足则**不评审**、报告「存在未提交内容，请作者先提交」，评审者不得代提交。理由：`push-progress` 是 `git add -A` 全仓提交，评审者发布前必须确保不会把作者未提交内容一并发布。
3. **发布与评审对象对账**（FR-3）：评审者发布后必须校验「发布的就是评审的」——requirement / tech-design 用注解 `subject-sha256`（PRD / SDD 文件）在 KB 发布批次的 `sourceSha` 上复算 LF-only sha256；dev-plan 用 plan.md + 全部 `TASK-*.md` 的 composite digest；code 用 `review-annotations/code.yml#release-subjects[].reviewed-source-sha` 与 `repositories[].sourceSha` 逐仓比对。不等即 `CONTRACT_DRIFT` 技术中止（**不改 verdict**），报原始差异。
4. **审批后与冗余 checkpoint 节点退役**（FR-4 / FR-5）：删除 requirement `…0007` / `…0003`＋输入 `auto_push_after_prd`、architecture `…0005`、code `…0012` / `…0003`＋输入 `auto_push_after_task` / `…0008` / `…0015`＋审批提示前提句，并从 `review-code.reviewLoop.replayNodes` 删掉 `…0008` 一项；节点数 requirement 7→5、architecture 5→4、code 16→12，`_index.yml` 计数与 `pipeline-structure.test.mjs` 断言同步。
5. **审批后发布由搭车承担**（FR-6 / FR-7）：code 路径由 `merge` 的 publication preflight（`MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` + 结构化 `recovery`）在**同一 writeback run 内**硬兜底；requirement / tech-design / dev-start 的审批提交由下一阶段评审 PASS checkpoint 带回；**任何情况下不得为 checkpoint 单开 task/委派**——该硬规则写入 coordinator / dev / delivery / reviewer 四份 Agent 合同（tools 公共 Prompt 为唯一事实源，multica 侧同步部署副本）。
6. **评审者的发布职责与权限**（FR-8）：`agent-skill-matrix.yml` 的 `quality-reviewer-agent` 从 `forbidden` 移除 `push-progress`、在 `can-call` 增加 `push-progress`（`checkpoint` 仍留在 `forbidden`——评审者只用 `push-progress` Skill，不用 `crctl checkpoint` 原语），`AGENT-SKILL-MATRIX.md` 的「本 CR 权限变更」节同步；并把 FR-2 强制前置所需的**只读** `workspace inspect` 写入该 actor 的 crctl 允许面（三处载体同步：矩阵注释、`AGENT-SKILL-MATRIX.md` 变更行、tools 与 multica 两份 `quality-reviewer-agent` 的受限 crctl 权限块——B-1 闭合）。
7. **FR-07 口径重写 + 归档后 trunk 同步 + 平台伴随项**（FR-9 / FR-10 / FR-11）：`push-progress/SKILL.md`、`README.md`、`openwiki/pipelines/overview.md`、`dir-graph.yaml#pipeline_templates.contract` 同步为「阶段终点完成条件 = 评审 PASS 的 checkpoint」；`archiveCr` 复用既有 `reconcileLocalTrunks(ctx)` 并在返回结构新增 `localTrunkSync`；节点集变化对平台生成物（`emit-registry.mjs` digest、`gate_nodes_gen.go` 的 `NodeID/Seq`）的影响只**登记契约变化**，重生成由 owner 在部署窗口执行。

### 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

评审 PASS 时由评审 agent 发布阶段产物（需求 / 技术设计 / plan-TASK / code 各一次，含发布对账与评审前置 clean 检查）；退役全部「审批后 checkpoint」节点与冗余 checkpoint 节点（requirement 7→5、architecture 5→4、code 16→12）；未发布的审批提交由下一阶段评审 checkpoint 或 `merge` 的 publication preflight 搭车承担、任何情况下禁止单开 checkpoint 委派；归档后复用 `reconcileLocalTrunks` 把各仓主 checkout ff-only 对齐 origin（archive 返回新增 `localTrunkSync`）。不引入平台执行层、不新增 pipeline 节点 / 评审维度 / 账本字段 / 观测指标、不改 crctl 事务层与 `recovery` 合同、不复活 `recoverCommand`。

#### 1.3.1 scope_in 边界（原文前缀，评审核对用）

> 本 CR 只改 tools 仓的 pipeline JSON / 四个 review SKILL / `push-progress` SKILL / 权限矩阵 / 既有测试，以及 multica 仓的四份 Agent Prompt 部署副本（公共 Prompt 的正式改动仍落 `tools/agents/*`）；平台 DB 与生成物重生成由 owner 在部署窗口执行。

逐条落到「哪个仓的哪个文件」（基线行号见 §1.4）：

| # | 仓 | 文件 | 修订类型 |
|---|---|---|---|
| 1 | `../tools` | `pipeline-templates/requirement-authoring.pipeline.json` | 删节点 `…0003`、`…0007` 与输入 `auto_push_after_prd` |
| 2 | `../tools` | `pipeline-templates/architecture-design.pipeline.json` | 删节点 `…0005` |
| 3 | `../tools` | `pipeline-templates/code-implementation.pipeline.json` | 删节点 `…0003`、`…0008`、`…0015`、`…0012`、输入 `auto_push_after_task`、`review-code.reviewLoop.replayNodes` 的 push-progress 项、code `human_approval` 提示的「评审后 checkpoint `phase=complete`」前提句 |
| 4 | `../tools` | `pipeline-templates/_index.yml` | `nodes` 计数 5 / 4 / 12 与 brief 同步 |
| 5 | `../tools` | `skills/{requirement/review-requirement,develop/review-tech-design,develop/review-dev-plan,develop/review-code}/SKILL.md` | Step 1 前置 clean 检查；PASS 分支新增 `push-progress`；发布对账；失败语义；「调用时机 / 用途」里的 checkpoint 前提句同步 |
| 6 | `../tools` | `skills/sync/push-progress/SKILL.md` | FR-07 口径重写（评审 PASS 强制、审批后无节点、搭车） |
| 7 | `../tools` | `agent-skill-matrix.yml` + `AGENT-SKILL-MATRIX.md` | reviewer 去 `forbidden: push-progress`、加 `can-call: push-progress`；crctl 允许面注释与「本 CR 权限变更」行**新增只读 `workspace inspect`**（FR-2 前置的授权来源，B-1），注释与派生表同步 |
| 8 | `../tools` | `agents/{dev-agent,quality-reviewer-agent,delivery-agent}.md` | 搭车硬规则 + 评审者发布职责（公共 Prompt 唯一事实源）；`quality-reviewer-agent.md` 的受限 crctl 允许面显式含只读 `workspace inspect`、`checkpoint` 仍在禁止面 |
| 9 | `../tools` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | `archiveCr` 末尾调用 `reconcileLocalTrunks(ctx)`，返回增加 `localTrunkSync` |
| 10 | `../tools` | `skills/cr/cr-archive/SKILL.md` | 结果分类表 / 输出块新增 `localTrunkSync`（`recovery` 语义不变） |
| 11 | `../tools` | `skills/writeback/merge-feature-branch/SKILL.md` | publication lag 行补「同 run 内搭车、不单独委派」语义（`recovery` 字段名不变） |
| 12 | `../tools` | `README.md`、`openwiki/pipelines/overview.md`、`dir-graph.yaml`（`pipeline_templates.contract`） | FR-07 与新节奏口径 |
| 13 | `../tools` | `skills/shared/crctl/scripts/test/{pipeline-structure,archive-tx}.test.mjs` | 断言重写 + 新增（见 AC-1 / AC-2 / AC-3 / AC-8） |
| 14 | `../multica` | `cr-prompts-revised/{cr-coordinator-agent,dev-agent,delivery-agent,quality-reviewer-agent}.md` | 搭车硬规则 + 评审者发布职责（部署副本，owner 部署）；`quality-reviewer-agent.md` 的「受限 crctl 权限」穷尽式白名单**新增只读 `workspace inspect`**，其禁止面枚举（含 `checkpoint`）不变 |

**`../multica` 改动共 4 个文件**（上表最后一行）；不改 `CUSTOM.md`（#75 已定义该目录是 tools 的部署副本，本 CR 不重写该行）、不改 `agent-skill-matrix.yml` 部署副本、不改平台 DB 与 `aifirst/agent-import.mjs`。

#### 1.3.2 目标仓库与版本

- 代码实施在 `../tools/`（pipeline JSON、SKILL.md、Agent Prompt、权限矩阵、crctl lib 与测试）与 `../multica/`（四份 Prompt 部署副本）。
- knowledge-base 承载本 PRD 与来源附件；本 CR 不改 KB 的 `specs/`、`delivery/`、`docs/`。
- `target-version` 继承 `cr.md` 的 `0.39`（注册阶段由 owner 指定，`crctl version-set` 之外无改写入口）；`target-spec-id` = `ai-first-platform`，由注册事务写入双账本，本文件不得改写。
- **部署不在本 CR 范围内**：平台 DB 的 Prompt 投影、`gate_nodes_gen.go` / registry digest 重生成由 owner 执行（FR-11 只登记契约变化）。

#### 1.3.3 契约说明（确定性四查适用面）

本 CR 有两处**用户可调用契约**的变更，四查（幂等 / 权限 / 错误闭包 / 副作用）落点为 FR-1（Skill 契约）、FR-10（crctl CLI 契约）与 AC-1、AC-8：

- **Skill 契约**（FR-1、FR-2、FR-3）：四个 review SKILL 的调用面与落盘面**不变**——不新增 Skill 参数、不新增落盘文件、不新增状态转换、不新增错误码；新增的只有「PASS 分支内的一次 `push-progress` 调用 + 一次对账 + 前置 `workspace inspect` 只读检查」。该前置是 crctl **既有只读子命令**（不新增命令、不新增错误码），其授权由 FR-8 的 actor 允许面变更承载：`crctl workspace inspect` 必须在 SKILL 文本与 actor 允许面**两侧同时**存在，由 AC-3 与 AC-4 联合断言（B-1）。
- **crctl CLI 契约**（FR-10）：`crctl archive` 的返回结构**新增** `localTrunkSync` 字段；既有字段（`commit`、`lastCleanupError`、`remaining`、`preservedRefs`、`recovery`、`warnings`）与退出码语义不变，不新增错误码。

其余 FR 是 Prompt / 文档 / 矩阵 / 测试侧的原位修订（FR-4~FR-9、FR-11），不定义新的用户可调用契约；其验收以「文本合同 + 检索/测试证据」形式给出（AC-2~AC-7、AC-9、AC-10）。

### 1.4 当前事实（落笔前核实）

基线（`crctl register` 时 ensure 的 requirement worktree HEAD）：

| 仓 | worktree HEAD |
|---|---|
| `ai-first-platform-docs`（本 KB） | `9a64fc4fac97e328a2dee0bff1711cc4f2a4c367`（register 提交） |
| `../multica` | `43848770bff13465de8ed9a0e28ecc7371716514` |
| `../tools` | `5d5a4ada96b882eb2c640e34bb72857a7073b668`（= tools `main`） |

以下结论均在上述 SHA 上核实（路径相对各自仓根）：

| # | 结论 | 证据 |
|---|---|---|
| 1 | 三份 pipeline 当前节点数为 requirement **7** / architecture **5** / code **16**；审批后存在 push-progress 节点 | `requirement-authoring.pipeline.json`：`…0003`（推送 PRD 草稿到远端，`onFail=skip`）、`…0007`（推送需求审批结果 checkpoint，`onFail=abort`），`human_approval` 为 `…0005`（列表下标 4，即第 5 位）；`architecture-design.pipeline.json`：`…0005` 是唯一 push-progress，位于 `human_approval` `…0003`（下标 2）之后；`code-implementation.pipeline.json`：push-progress 4 个（下标 3、9、12、15），`human_approval` 在下标 4、13，故 `…0012`（下标 15）在最后一次审批之后 |
| 2 | 待删输入字段当前存在且被节点 prompt 引用 | requirement inputs 含 `auto_push_after_prd`（节点 `…0003` prompt 写 `{{inputs.auto_push_after_prd}}=false 则 SKIPPED`）；code inputs 含 `auto_push_after_task` |
| 3 | `review-code.reviewLoop.replayNodes` 当前 **5** 项，第 3 项即待删的 push-progress | `code-implementation.pipeline.json`：`[implement-code, write-test-report, push-progress(…0008, publish-repaired-code-and-evidence-checkpoint), workspace-freshness(…0017), review-code]` |
| 4 | code `human_approval` 提示当前含「评审后 checkpoint」前提句 | `…0010` 的 `approvalPrompt`：「…`test-report.md` 须满足 status=pass 后才可进入本节点；当前应为 `code-reviewing`，且**评审后 checkpoint phase=complete**」 |
| 5 | `_index.yml` 的 nodes 计数与 JSON 一致，且 brief 写明两类 checkpoint | `pipeline-templates/_index.yml`：requirement `nodes: 7  # CR-2026-044：审批后新增强制终点 checkpoint`；architecture `5`；code `16  # CR-2026-042 …17 -> 16` |
| 6 | `pipeline-structure.test.mjs` 把现状钉成了断言 | 同文件：AC-1 断言 `review-code(…0009) < checkpoint(…0015) < human_approval(…0010) < approve-code(…0011)`；AC-2 断言 `ids.length === 16`；AC-3 断言 `replayNodes` 逐字等于 5 项；另有「`_index.yml` nodes 与实际 JSON 一致」与「`…0010` approvalPrompt 含 `评审后 checkpoint phase=complete`」断言；CR-2026-044 段断言 requirement 7 节点 / architecture 5 节点 |
| 7 | 四个 review SKILL 当前均无发布步骤、无 clean 前置 | 全文件检索 `push-progress` 仅命中「调用时机」句：`review-requirement`「第 4 节点（push-progress 之后）」、`review-dev-plan`「write-dev-tasks 之后、push-progress 之前」、`review-code`「第 8 节点（代码编写与统一 checkpoint 后）」；四个 SKILL 均无 `crctl workspace inspect` 的 dirty/healthy 前置 |
| 8 | `review-code` 的「用途」把统一 checkpoint 写成前提 | `review-code/SKILL.md` L16：「在开发者完成编码并推送统一 checkpoint 后…」；另 L38 提醒「不要用已推送的 `origin/requirement/{cr_id}...HEAD` 作为唯一 diff range」 |
| 9 | `push-progress` Skill 契约面 | 参数 `cr_id`（必填）+ `message`（可选）；返回消费 `phase` / `changed` / `batchId` / `repositories[]`（每仓 `sourceSha`+`confirmed`）/ `metadataCommit`；错误分流 `CHECKPOINT_SENSITIVE_PATH`、`CHECKPOINT_REMOTE_ADVANCED`、`CHECKPOINT_REMOTE_DIVERGED`、`CHECKPOINT_REMOTE_HISTORY_REWRITTEN`、`TX_*`、终态 `ILLEGAL_LEDGER_STATE`；幂等重放返回 `changed=false` |
| 10 | reviewer 在矩阵里的当前归属 | `agent-skill-matrix.yml` 的 `quality-reviewer-agent`：`can-call = [review-planning-report, cr-show, controlled-shell, crctl]`，`forbidden` 含 `push-progress` 与 `checkpoint`（均在列）；注释声明 crctl 仅允许 `status`/`next`/对应 review 的 `gate`/`review-record`/`advance` |
| 11 | `AGENT-SKILL-MATRIX.md` 的派生面 | L20「主责矩阵」（owns）、L46「本 CR 权限变更」节（`| Actor | 新增 can-call | 约束 |` 表，当前一行 `quality-reviewer-agent` / `controlled-shell`）、L54「设计缺口」；`check-skill-matrix.mjs` 机械校验的是三份 `owns` 声明（can-call / forbidden **不在**其校验面） |
| 12 | Agent 合同当前把「checkpoint 完成」写成评审/审批前提 | multica `cr-prompts-revised/dev-agent.md` L23「先有代码、测试报告和统一 checkpoint，再由独立 reviewer 调用 `review-code`」、L41「checkpoint 未完成时，不进入后续人工审批」；`cr-prompts-revised/quality-reviewer-agent.md` L54「本 Agent 不负责 push/checkpoint，后续发布由 Pipeline 中对应的同步节点完成」（**与本 CR FR-1 直接冲突，必须原位改写**）、L46 的 crctl 禁止清单含 `checkpoint`；同文件 L35–L46 的「受限 crctl 权限」块是**穷尽式白名单**——L37 明写「仅限评审所需的以下子命令」后只列 `status`／`next`、`gate`、`review-record`、`advance`（L39–L42），L46 按写入型子命令枚举禁止面，`workspace inspect` **两侧均未出现**（FR-2 与之冲突，B-1 的事实源；本 PRD 按 §1.5 第 5 条把它写入允许面）；tools 侧 `agents/quality-reviewer-agent.md`（42 行）通篇无该清单，只声明「权限矩阵：`agent-skill-matrix.yml`」为事实源 |
| 13 | `agent-skill-matrix.yml` 禁止 coordinator 发布 | multica `cr-prompts-revised/cr-coordinator-agent.md` L19/L60：`crctl` 仅只读 `status`/`next`，禁止 `advance`/`approve`/`checkpoint` 等写入型子命令——这是「门后节点只能被单独委派」的直接原因（来源 §1.2） |
| 14 | `reconcileLocalTrunks` 的现有归属、形状与分类 | `lib/workspace-transactions.mjs:1487` 定义，**唯一调用点** `:1786`（merge 路径），merge 返回 `localTrunkSync`（`:1791`）；行形状 `{repo, trunk, before, remote, after, status, reason}`；分类 `status ∈ {unchanged, synced, skipped, failed}`，`reason ∈ {wrong-branch, dirty, diverged, fetch-failed, **trunk-unavailable**, ff-only-failed}`（来源文档只列了 5 个 reason，漏 `trunk-unavailable`，见 §1.5）；副作用仅 `fetch --prune origin` 与 `merge --ff-only`，全程 best-effort、不抛错、不写 journal/账本 |
| 15 | `archiveCr` 现有返回字段 | `archiveCr(ctx, input)`（`:3498`）：`commit` / `lastCleanupError` / `remaining` / `preservedRefs` / `recovery` / `warnings`；`cr-archive/SKILL.md` Step 3 逐字透传这些字段；`archive-tx.test.mjs` 已有「固定返回 commit/lastCleanupError/recovery/warnings」与「complete 幂等重放 changed=false」用例 |
| 16 | publication preflight 的既有语义与字段名 | `skills/writeback/merge-feature-branch/SKILL.md:53`：`MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` = publication lag，状态保持 `code-approved` 不回退，「按 `error.recovery`（结构化 argv）先 checkpoint 再重跑 merge」——FR-6 只补「同 run 内、不单独委派」的显式口径，**不改** `recovery` 合同与字段名（CR-2026-064 已定） |
| 17 | 平台生成物是 tools 合同的派生物 | `pipeline-templates/emit-registry.mjs` 从 tools 权威合同生成 architecture-design Core registry（schema `ai-first.pipeline-registry/architecture-core-v1`）；`../multica` `server/internal/governance/gate_nodes_gen.go` 为生成文件（header 记 `Source: tools@7a747981…`），按 gate 映射 `NodeID`+`Seq`（当前 requirement `…0005`/Seq 5、tech-design `…0003`/Seq 3、dev-start `…0004`/Seq 5、code `…0010`/Seq 14；review 节点 requirement `…0004`/Seq 4、tech-design `…0002`/Seq 2、code `…0009`/Seq 12），由 `server/internal/governance/gen/generate-gate-nodes.mjs` 的 `--check` 守护；Runner 默认关闭（`runner.go` `ArchitectureRunnerEnabled()` 未设 `AIFIRST_ARCHITECTURE_RUNNER` 时返回 false） |
| 18 | CI 已是真门禁（不得签例外） | `.github/workflows/crctl-ci.yml`（Ubuntu + Windows）：`lint-prompts --mode enforce`、`check-skill-matrix.mjs`、`check-agents-contract.mjs`、pipeline JSON 结构断言、`suite-gate.mjs --run`、writeback 单测 |
| 19 | `recoverCommand` / `recover_command` 的退役名单在测试里 | `test/contract-scan.test.mjs:418` `RETIRED_RECOVERY = ['recoverCommand', 'recover_command']`，全树扫描 |
| 20 | 来源 §1.1 的 6 次 checkpoint 台账只有最后一次可核 | KB `change-requests/_history.yml` 的 `CR-2026-063.latest-checkpoint.batch-id = 7dfd04f27a18486c`，与来源表第 6 行一致；前 5 次 batchId 属来源记载，本 PRD 未逐条复核（**不影响根因结论**：门后节点在 agent 驱动模式下必须新开唤醒） |
| 21 | 串行约束当前成立 | `crctl status` 对 CR-2026-063/064/065 均为 `archived`；`change-requests/` 最大编号 065（无撞号）、注册前 `_backlog.yml` 为空；本次注册 `crctl register` 返回 `changed=true`、txId 事务化落三账本与三仓 worktree |
| 22 | 来源 §3「gate 阻塞性结论」的锚点与未重核面 | 来源 §3 声称已逐条核对「下一阶段入口 `crctl workspace inspect`、`workspace-freshness`（ahead-only=fresh）、四个 `approve-*`、`review-record`、`writeback-apply`、`cr-archive`、`gates.json` 全部只依赖本地事实，唯一远端相等要求是 `merge` 的 publication preflight」。本 PRD 独立核实的锚点是 tools `ARCHITECTURE.md` 的 CR-2026-044 段（「release-subjects 构造/重核只读本地 healthy committed worktree（不 fetch、不读 remote-tracking ref），status/gate/review/approve 不受网络影响；发布完整性由 checkpoint 与 merge 首次 prepare 前的全仓 publication preflight 承担（publication lag 保持 `code-approved` 并指向 checkpoint）」）与 §1.4 事实 16 的 publication lag 语义。**未逐条重跑**来源 §3 的 8 项门禁核对：若 SDD/实现期发现某门禁依赖远端事实，FR-6 的取舍需重新评估（不影响 FR-1~FR-5、FR-7 的成立） |

### 1.5 对来源文档的事实更正与需人工确认的口径

1. **FR-10 的分类清单不完整（本 PRD 以代码事实为准）**：来源 §4 FR-10 写 `skipped(wrong-branch|dirty|diverged)` 与 `failed(fetch-failed|ff-only-failed)`；实测 `reconcileLocalTrunks` 还有 `failed(trunk-unavailable)`（`rev-parse --verify origin/<trunk>` 失败时），且行形状含 `trunk` 字段。本 PRD 的 FR-10 与 AC-8 按**实测 6 个 reason** 写；该项**不改变**来源的方案取向（复用既有函数、只加调用点与返回字段）。
2. **删除后不再有 push-progress 节点（来源未写明的口径补充）**：FR-4 删 3 个、FR-5 删 4 个之后，requirement 剩 5 节点、architecture 剩 4 节点、code 剩 12 节点，**三份 JSON 中不再存在任何 `ref=push-progress` 的节点对象**——发布一律由 review SKILL 内的 `push-progress` 调用承担，pipeline 里不再有「发布节点」这一形态。AC-1 据此采用两条判据：「不存在任何位于 `human_approval` 之后的 push-progress 节点」**且**「`nodes[].ref=push-progress` 计数为 0」——只写前者不足以表达删除后「零发布节点」的更强事实，只写后者不足以表达「不得在审批后再新增发布节点」。
3. **Skill 契约的发布动作不在 `crctl` 子命令面**：评审者的发布调用的是 **`push-progress` Skill**（其内部调用 `crctl checkpoint`），不是让评审者直接执行 `crctl checkpoint`。因此 FR-8 只把 `push-progress` 移出 `forbidden`、把 `checkpoint` **留在** `forbidden`；`cr-prompts-revised/quality-reviewer-agent.md:46` 的 crctl 禁止清单**不改**。此项需在人工审批时一并确认。
4. **§1.1 的事实面限定**：6 次 checkpoint / 3 次单独委派的具体数字来自来源文档记载（见 §1.4 事实 20），本 CR 的目标与验收不依赖这些数字，只依赖「门后节点必须重新唤醒」这一机制性结论。
5. **评审前置 `workspace inspect` 的授权面（本 PRD 收口裁定，需人工一并确认）**：来源 FR-2 把只读 `crctl workspace inspect` 写成四个 review SKILL 的强制前置，但该 actor 的 crctl 允许面（矩阵注释与 multica 部署副本的穷尽式白名单）不含它（§1.4 事实 12）——同一份合同下会得到两种互斥读法：「违反自己的穷尽式权限合同去执行前置」或「跳过前置而违反 FR-2」。本 PRD 采用评审建议的**方案 (a)**：在 FR-8 明确把**只读** `workspace inspect` 加入该 actor 的 crctl 允许面，并把三处载体（`agent-skill-matrix.yml` 注释、`AGENT-SKILL-MATRIX.md` 变更行、tools 与 multica 两份 `quality-reviewer-agent.md` 的受限 crctl 权限块）同步列入 §1.3.1 第 7、8、14 行；`checkpoint` 仍在禁止面（发布只经 `push-progress` Skill，不放开 crctl 原语）。该授权**不新增** crctl 子命令、不新增错误码、不引入任何写入面，落地由 AC-4 的权限面闭合判据机械复核。

### 1.6 修订记录

- 修订 0.2（2026-09-14，cycle1 attempt1 BLOCK 回修）：闭合 **B-1**——FR-2 的强制前置 `crctl workspace inspect` 与 `quality-reviewer-agent` 的穷尽式权限合同互相矛盾；按评审给出的**方案 (a)** 把**只读** `workspace inspect` 写入该 actor 的 crctl 允许面：§1.3.1 第 7、8、14 行登记三处载体（矩阵注释 / `AGENT-SKILL-MATRIX.md` 变更行 / tools 与 multica 两份 `quality-reviewer-agent.md` 的受限 crctl 权限块），FR-8 新增载体同步条目，§1.5 新增第 5 条授权面裁定，§1.4 事实 12 补登穷尽式白名单证据，AC-4 增加权限面闭合判据（两侧同时断言 + 反向断言 `crctl checkpoint` 不出现在 review SKILL）。同轮一并承接 6 条 suggestions：S-1（AC-6 载体/时点/延期验证点）、S-2（FR-3 只读取证手段，明示 `git show` 不可用）、S-3（FR-7 增加既有测试面静态文本断言）、S-4（`dir-graph.yaml` contract 第 5 条改显式枚举）、S-5（delivery-agent 的 `recovery` argv 例外）、S-6（§1.4 新增事实 22 与 §7 承接 §8 取舍/回滚边界）。
- 初稿（2026-09-14）：按来源附件 §1–§9 与注册摘要（`cr.md` summary）起草；基线事实在 §1.4 三个 worktree HEAD 上逐条核实。FR 编号与来源 §4 的 FR-1~FR-11 一一对应（不重编号）；AC-1~AC-9 对应来源 §5；**AC-10 为本 PRD 新增**，用于把来源 §2.2 的 scope_out 与 §7 的「不与其他 CR 并发」写成可检查约束（来源文档没有对应 AC）。§1.5 记录三处对来源文档的事实更正与一处口径解释，需在人工审批时一并确认。

## 2. 用户故事

- **US-1 阶段 owner（dev-agent / requirement-writer）**：作为按 Pipeline 节点的 Agent，我希望评审 PASS 后远端就有一个「产物 + verdict + 状态」的完整批次，这样我的 run 在人工 gate 前结束后不必再被唤醒去补一次发布。
- **US-2 评审者（quality-reviewer-agent）**：作为出 verdict 的评审者，我希望发布的就是我刚评审的那份内容（前置 `healthy` 检查 + 发布后对账），这样我不会把自己的署名绑定到没看过的内容上，也不会替作者提交未完成的工作。
- **US-3 CR 协调者**：作为只读 `crctl status/next` 与路由的协调者，我希望「审批后发布」有一条明确的搭车路径（下一阶段评审 checkpoint 或 `merge` 的 publication preflight），这样我不会被逼着为单个 `push-progress` 单开一次委派。
- **US-4 换机 / 接手的协作者**：作为中途接手的人，我希望每个阶段结束时远端都存在完整批次（`repositories[].confirmed=true`、`metadataCommit` 非空），这样我能按 checkpoint 续接而不依赖本地未发布状态。
- **US-5 部署 owner**：作为把 Prompt 部署进平台的人，我希望「阶段终点完成条件」在 `README`、`openwiki`、`push-progress` SKILL 与 `dir-graph.yaml` 里是**同一句口径**，这样我不会按两套说法部署。
- **US-6 走完归档的 delivery-agent / owner 机器**：作为归档的执行者，我希望 `crctl archive` 的返回直接告诉我每个仓的主 checkout 是否已与 origin 对齐（`unchanged` / `synced` / `skipped` + `reason`），这样我不必手工逐仓 `fetch` + `merge --ff-only`，也不会让本地停在旧 trunk 上。
- **US-7 维护 tools 的开发者**：作为改 pipeline JSON 的人，我希望节点退役与 `_index.yml` 计数、`pipeline-structure.test.mjs` 断言、平台生成物登记在同一份 diff 内闭合，这样 CI 不会在中间态变红，也不会出现「JSON 删了、平台 `Seq` 没重生成」的静默漂移。
- **US-8 本 CR 的 reviewer**：作为本 CR 的评审者，我希望能逐条核对「哪个仓的哪个文件被原位改了、哪条断言变了」，使得这次收敛不引入第二套发布流程或新的观测负担。

## 3. 功能需求

### FR-1 评审 PASS 发布（4 个 review SKILL）〔来源 §4 FR-1〕

`review-requirement` / `review-tech-design` / `review-dev-plan` / `review-code` 四个 SKILL 在 PASS 分支新增一个发布步骤，合同如下：

1. **触发条件（顺序固定）**：该阶段 `review-record` 成功落盘 → 该阶段既有 `advance` 完成（`review-tech-design` / `review-dev-plan` / `review-code` 的既有 `advance` 语义不变；`review-requirement` 为既有 `advance --to requirement-reviewing --trigger review-requirement`）→ `git status --porcelain` 干净 → 才执行发布。
2. **发布调用**：调用既有 `push-progress` Skill，`message` = `<阶段>评审通过`（如 `需求评审通过` / `技术设计评审通过` / `开发计划评审通过` / `代码评审通过`）；**不新增 Skill 参数**（只用既有 `cr_id` + `message`），不新增落盘文件。
3. **结果透传**：消费并**逐字**透传 `phase` / `batchId` / `repositories[]` / `metadataCommit` 到评审报告；`phase=complete` 且 `changed=false`（no-op）视为成功。
4. **BLOCK 分支不发布**：`verdict=block` 时不调用 `push-progress`（回修中间态不上远端）。
5. **失败语义（不改 verdict、不重评）**：发布失败（含 `CHECKPOINT_SENSITIVE_PATH` / `CHECKPOINT_REMOTE_*` / `TX_*`）时——verdict 与评审账本**保持已落盘结果不变**，不重评、不改 verdict、不代作者提交、不回退状态；报告原始错误码与 `recovery`，按 `recovery` 重试**同一个** `push-progress`（不产生第二次评审）；发布失败**不阻塞**任何本地门禁。
6. **幂等与副作用**：重复发布以 `crctl checkpoint` 既有幂等语义为准（同内容重放 `changed=false`）；发布只经 `push-progress`/`crctl` 写 `_backlog.yml` 的 checkpoint 字段，评审者不得直接编辑任何账本。
7. **不改的部分**：四个 review SKILL 的评审维度、`verdict`/`blockers`/`suggestions` 结构、payload YAML 子集边界、`reviewLoop` 语义与状态转换全部不变。

### FR-2 评审前置干净检查〔来源 §4 FR-2〕

四个 review SKILL 的 **Step 1 前置校验内**（既有 Step 1.5 pre-review gate **之前**，两者都是零写入，故相对顺序不构成副作用面；钉定该位置是为了可机械核对）新增：

- 执行只读的 `crctl workspace inspect <cr_id>`，要求**全部** resources 满足 `classification=healthy`（等价 `dirty=false`）。
- 不满足时：**不进入评审**——不写临时 payload、不调用 `review-record`、不 `advance`、不改 status、不发布；报告须含**逐仓的 dirty 事实与该仓未提交文件清单**，并给出「存在未提交内容，请作者先提交」的明确指示。
- **不得**由评审者 `git add` / `commit` / `stash` / 清除作者未提交内容。
- 该检查**不新增 crctl 子命令、不新增错误码**（复用 `workspace inspect` 既有只读输出）。
- **授权来源（B-1 闭合）**：该前置由 FR-8 的允许面变更授权——`workspace inspect` 是 crctl 既有只读子命令，写入 `quality-reviewer-agent` 的 crctl 允许面后，SKILL 侧的前置与 actor 侧的权限合同指向同一件事。**不得只改 SKILL 而不改允许面**：两侧必须同时存在（缺任一侧即 CI 变红，判据见 AC-3 与 AC-4）；该前置不产生任何写入，也不改变 FR-1 的发布顺序。

### FR-3 发布与评审对象对账〔来源 §4 FR-3〕

评审者在发布成功后必须校验「发布的就是评审的」，逐阶段口径：

| 阶段 | 评审对象事实 | 对账判据 |
|---|---|---|
| requirement / tech-design | annotation `subject-sha256`（`prd.md` / `sdd.md`） | 在 KB 发布批次的 `sourceSha`（= checkpoint 返回的 KB 仓 `repositories[].sourceSha`）所对应的该文件内容上复算 **LF-only** sha256，必须与 annotation 全等 |
| dev-plan | annotation `subject-sha256`（`plan.md` + 全部 `TASK-*.md` 的 composite digest） | 同口径复算 composite digest，必须全等 |
| code | `review-annotations/code.yml#release-subjects[].reviewed-source-sha` | 与 checkpoint 返回的 `repositories[].sourceSha` **逐仓**相等（仓名与 SHA 一一对应）；KB 受控 artifact 哈希与 release snapshot 一致 |

- **取证手段（只读、不新增能力面）**：复算前必须先把发布批次绑定到当前提交——取该仓 `crctl git rev-parse HEAD`（controlled-shell 白名单 `rev-parse`，`callers=*`）与 checkpoint 返回的 `repositories[].sourceSha` 比较；两者**相等**且 FR-2 的 `dirty=false` 成立时，「当前提交 = 发布内容 = 工作区内容」成立（`push-progress` 以 `git add -A` 提交），据此按 LF-only 复算 sha256 才有效。**禁止**在两者不相等时用工作区文件复算（那等于用 `subject-sha256` 自证，对账失去意义，尤其对 dev-plan 的 composite digest 与 code 的逐仓比对）：此时按 `CONTRACT_DRIFT` 技术中止并报告两侧 SHA。`git show` **不得**作为取证手段（`rules.json` 的 `show` 只向 `system-orchestrator` 放行 `review-annotations/*` 路径，shape 不含业务文件；`git diff`/`log`/`rev-parse` 等只读命令可用）。
- 判定不等 → `CONTRACT_DRIFT` **技术中止**：**不改 verdict**、不重评、不回退状态；报告须含「期望值 vs 实际值」两侧原始 SHA 与复算所用内容来源。
- 复算必须遵循行尾纪律（读入先 `\r\n → \n` 归一；跨行/逐行解析失败**硬失败报错**，禁止静默降级）。
- **不新增**账本字段、不新增注解字段、不新增哈希算法或口径（沿用既有 `subject-sha256` / composite / `release-subjects` 三套既有事实源）。

### FR-4 审批后 checkpoint 节点全部退役〔来源 §4 FR-4〕

从 pipeline JSON 中**删除节点对象**（不是改 `onFail`、不是加开关）：

| pipeline | 删除节点 | 删除输入 |
|---|---|---|
| requirement-authoring | `00000000-0000-0000-0011-000000000007`（推送需求审批结果 checkpoint） | — |
| architecture-design | `00000000-0000-0000-0016-000000000005`（推送架构设计到远端） | — |
| code-implementation | `00000000-0000-0000-0015-000000000012`（推送代码审批结果到远端） | — |

约束：不新增替代节点；不把删除实现为「保留节点 + `onFail: skip` + 默认关闭的开关」（来源 §1.3 已排除该方案：门后节点在 agent 驱动模式下没有强制力，`abort` 只是纸面强度）；不重编号其它节点的 `id`（`id` 是稳定 UUID，删除后不回收、不复用）。

### FR-5 冗余 checkpoint 节点退役〔来源 §4 FR-5〕

| pipeline | 删除节点 | 同步删除 | 理由 |
|---|---|---|---|
| requirement-authoring | `…0011-000000000003`（推送 PRD 草稿到远端） | 输入 `auto_push_after_prd` | 被 FR-1 的 PRD 评审发布覆盖 |
| code-implementation | `…0015-000000000003`（推送设计/任务到远端） | 输入 `auto_push_after_task` | 被 `review-dev-plan` PASS 发布覆盖 |
| code-implementation | `…0015-000000000008`（推送代码+文档统一 checkpoint） | `review-code.reviewLoop.replayNodes` 中的该项（5→4） | 被 `review-code` PASS 发布覆盖（同一批提交 + verdict） |
| code-implementation | `…0015-000000000015`（代码评审 PASS 后审批前 checkpoint） | code `human_approval`（`…0010`）`approvalPrompt` 中「评审后 checkpoint `phase=complete`」前提句 | 评审 PASS 已发布；审批不再以 checkpoint 为前置 |

同步要求（同一份 diff 内闭合，来源 §4 FR-5 与 `dir-graph.yaml#pipeline_templates.contract` 第 1 条）：

- 节点数 requirement **7→5**、architecture **5→4**、code **16→12**；`pipeline-templates/_index.yml` 的 `nodes:` 与 brief 同步（brief 不再描述已删节点）。
- 删除后三份 JSON 中**不再存在任何 `ref=push-progress` 的节点对象**（发布只发生在 review SKILL 内，见 FR-1）。
- 不删 `workspace-freshness` 节点（`…0016` / `…0017`）、不删 `code_generation` 节点、不改 `human_approval` 与 `approve-*` 的既有配对关系。

### FR-6 审批后发布由搭车承担（不得单开委派）〔来源 §4 FR-6〕

- **code 路径**：`merge` 的 publication preflight 语义**不变**；新增明确要求——writeback run 收到 `MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` 时，按 `error.recovery`（`executable` + `args[]` + `cwd`，`shell:false`）**就地执行一次**该命令，然后**在同一 writeback run 内重跑 merge**；不得把它转成一次新的委派或新 task。
- **requirement / tech-design / dev-start 路径**：审批提交由**下一阶段的评审 PASS checkpoint** 带上远端（无需任何额外动作）——这是设计取舍：审批是**网络无关的本地账本事务**，审批提交在下一阶段评审前只在本地，**换机恢复需重签一次**；该取舍必须写入 PRD/SDD 的事实节并在交付说明中明示。
- **禁止面**：不得为 checkpoint 单独创建 task/委派。checkpoint 只允许出现在三处：① 评审 run 内（FR-1）；② 已排定的下一阶段委派**内**（同一 run）；③ `recovery` 指定的**同 run** 内重跑。
- 反向验收：实施期与演练期观察到的「为单个 `push-progress`/checkpoint 单独开 task」次数 = 0（AC-6）。

### FR-7 搭车规则写入 Agent 委派合同〔来源 §4 FR-7〕

在 **tools 公共 Agent Prompt**（唯一事实源）与 **multica 部署副本**中增加同一句硬规则：

> 跨人工 gate 的第一份委派必须显式携带上一阶段尚未闭合的发布动作（在同一 run 内执行、只回报结果）；**禁止为单个 `push-progress` / checkpoint 节点单独开委派**。

落点（`../tools` 为正式改动，`../multica` 为部署副本，owner 复制上平台）：

| 仓 | 文件 | 修订 |
|---|---|---|
| `../tools` | `agents/quality-reviewer-agent.md` | 新增「评审 PASS 后发布」职责（FR-1 的 Skill 侧动作由本 Agent 执行）+ 搭车规则 |
| `../tools` | `agents/dev-agent.md` | 原位改写「先有代码、测试报告和统一 checkpoint 再由 reviewer 评审」与「checkpoint 未完成不进入审批」两句（改为「评审 PASS 即发布」口径）+ 搭车规则 |
| `../tools` | `agents/delivery-agent.md` | 新增搭车规则（merge/writeback 路径的 publication lag 局部处理） |
| `../multica` | `cr-prompts-revised/{quality-reviewer-agent,dev-agent,delivery-agent,cr-coordinator-agent}.md` | 同步上述文本（coordinator 增加「不得为 checkpoint 单开委派」的显式禁止） |

`delivery-agent` 的增量文本必须写明两件事：① `merge` 的 publication lag 返回的结构化 `recovery` argv 属于**被授权的同 run 重跑**，不受「不裸调 crctl 原语」约束；② 该例外**不**赋予独立发起 checkpoint 的权力（不得把 recovery 变成一次单独委派）。

约束：**不新增**委派 lint 规则（与 CR-2026-063 的既有结论一致：无法机械检查真实运行期评论的规则不引入）；该硬规则的落地以一条**同风格静态文本断言**兜底——在既有 `contract-scan.test.mjs` 面内断言 tools 侧三份 Prompt（`agents/{dev,quality-reviewer,delivery}-agent.md`）均含该硬规则文本（不新增 lint 规则、不新增扫描面）；本 FR 是 **Prompt 合同**，不宣称平台已新增运行时委派校验；平台 DB 部署由 owner 执行。

### FR-8 评审者的发布职责与权限〔来源 §4 FR-8〕

- `agent-skill-matrix.yml` 的 `quality-reviewer-agent`：`forbidden` **移除** `push-progress`；`can-call` **增加** `push-progress`。`checkpoint` **保留**在 `forbidden`（FR-8 只放开 Skill，不放开 crctl 原语；见 §1.5 第 3 条）。
- 该 actor 的 crctl 允许子命令注释同步为：`status` / `next` / **只读 `workspace inspect`**（FR-2 的 Step 1 强制前置，B-1 闭合）/ 对应 review 的 `gate` / `review-record` / `advance`；**不新增** `checkpoint`，也不放行其它写入型子命令。
- **允许面的载体同步（三处，缺一即交付缺陷）**：① `agent-skill-matrix.yml` 的 `quality-reviewer-agent` 块注释；② `AGENT-SKILL-MATRIX.md`「本 CR 权限变更」节的本 CR 行（约束列写明 `workspace inspect` 为只读前置）；③ `../tools/agents/quality-reviewer-agent.md` 与 `../multica/cr-prompts-revised/quality-reviewer-agent.md` 的受限 crctl 权限块——multica 副本的穷尽式白名单必须把只读 `workspace inspect` 列入允许项（其禁止面枚举保持含 `checkpoint` 不变），tools 副本的「权限事实源」节必须给出同一允许面声明，不得在同一份合同下留第二种读法。
- `AGENT-SKILL-MATRIX.md` 的「本 CR 权限变更」节追加本 CR 一行（`quality-reviewer-agent` / 新增 can-call `push-progress` / 约束：仅在对应 review SKILL 的 PASS 分支内发布一次，不修改业务文件、不推进状态、不改 verdict）。
- 评审者边界（写进 Prompt 与 SKILL）：**只发布、不修改**业务文件；发布失败**不改 verdict**、不重评、不代提交；评审者不承担任何状态推进（`advance` 例外仅为各 review SKILL 既有要求）。
- 平台侧把 `push-progress` 绑定给 `quality-reviewer-agent` 属 **owner 部署动作**（本 CR 交付后的部署项，不在代码范围内）；更新后的 `quality-reviewer-agent` 部署副本（含放宽后的只读 crctl 允许面）必须在同一部署窗口同步生效——在部署前，Multica 侧实际运行的副本仍是旧白名单（FR-2 与 AC-4 的机械断言只约束仓库内文本，部署时序由 owner 把握）。

### FR-9 FR-07 口径重写〔来源 §4 FR-9〕

`skills/sync/push-progress/SKILL.md`（现有 L9 的「调用时机」句）、`README.md`（第 6 节 checkpoint 行）、`openwiki/pipelines/overview.md`（`/requirement`、`/architecture`、`/coding` 三段与「不变量」清单）、`dir-graph.yaml#pipeline_templates.contract`（涉及 checkpoint / replayNodes 的条目）同步为同一口径：

> **阶段终点完成条件 = 评审 PASS 的 checkpoint**（由评审者执行，每阶段一次）；审批后不再有 checkpoint 节点，未发布的审批提交由下一阶段评审 checkpoint 或 `merge` 的 publication preflight 搭车承担；发布失败保持当前状态、重跑同一 checkpoint，**不重新评审 / 不重新审批**。

约束：不新增文档体系（新不变量写成既有文档内的一句话）；`openwiki/operations/` 与 `openwiki/pipelines/overview.md` 之间不产生第二套口径；`dir-graph.yaml` 的 `pipeline_templates.contract` 仍必须表达「新增或修改 pipeline JSON 后同步 `_index.yml` 计数」与 reviewLoop 重放清单两条既有约束；其中第 5 条（现文「按顺序列出修复、证据、checkpoint 与当前评审节点」）必须**改写为显式枚举**——评审 PASS 发布发生在当前评审节点**内部**、不再是独立 replay 节点（且 architecture 与删除后的 code `replayNodes` 均不含 checkpoint 项），故该条须写为「按顺序列出修复、证据、基线重核与当前评审节点」（或等价地显式写明「评审 PASS 发布不再是 replay 节点」），不得保留会把实现期读成「`replayNodes` 里应有一个 checkpoint 项」的旧词法。

### FR-10 归档后本地各仓与 origin 一致〔来源 §4 FR-10〕

1. **复用既有函数**：`archiveCr` 事务完成后调用既有 `reconcileLocalTrunks(ctx)`（不新写同步算法、不改该函数内部判据与分类）。
2. **返回结构新增字段**：`archiveCr` 返回值新增 `localTrunkSync`，与既有 `recovery` 同级并存（`recovery` 语义与字段名不变）；行形状沿用 merge 既有形状 `{repo, trunk, before, remote, after, status, reason}`。
3. **分类语义**（以实测为准，见 §1.5 第 1 条）：`status ∈ {unchanged, synced, skipped, failed}`；`reason ∈ {wrong-branch, dirty, diverged, fetch-failed, trunk-unavailable, ff-only-failed}`（`status=unchanged|synced` 时 `reason=null`）。
4. **只做 ff-only，永不破坏本地**：只处理 `dir-graph.yaml#repositories` 声明的**主 checkout**；**永不** `reset` / `clean` / `stash` / 强推 / 改动本地在途修改。
5. **dirty 策略**：主 checkout dirty 时**仍然跳过并如实报告**（`skipped` + `reason=dirty`），不改动本地在途修改；报告给出逐条 `reason` 与**人类可执行的补救说明**（不要求本 CR 自动处理）。
6. **失败不阻断归档**：该步骤是 best-effort，逐仓失败只反映在返回行；**不新增**错误码、不改变 `crctl archive` 的退出码语义、不改变既有 `phase=complete` / `phase=cleanup-pending` 分类、不写 journal/账本。
7. **幂等**：归档幂等重放（`changed=false`、`remaining=[]` 重跑）时 `localTrunkSync` 仍按当次实况返回，不产生新 commit、不产生第二次清理。
8. **文档同步**：`skills/cr/cr-archive/SKILL.md` 的结果分类表与输出块新增 `localTrunkSync` 字段与分类说明；delivery-agent 的最终汇报面包含该字段。
9. **可拆出**：若 SDD 阶段判定 CR 尺寸过大，FR-10 可被 owner 拆为后续 CR；拆出时必须同步缩减 AC-8、`archive-tx.test.mjs` 的新增用例与 §6 对应指标，并在本 CR 交付说明中显式登记。

### FR-11 平台生成物同步（伴随项，非平台执行层）〔来源 §4 FR-11〕

节点集变化后，两份**派生物**都会变：

- `../tools` `pipeline-templates/emit-registry.mjs` 生成的 architecture-design Core registry digest；
- `../multica` `server/internal/governance/gate_nodes_gen.go` 的 `NodeID` / `Seq` 映射（生成文件，`--check` 守护）——删除节点会改变该文件中 `Seq`（gate 与 review 节点的序位）等值。

本 FR 只要求**登记契约变化**，不要求在本 CR 内改 multica 生成物：

1. 交付说明中显式登记「生成物需重新生成」及其触发原因（节点集变化）；
2. 若**未**重新生成，必须显式声明「重新生成前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用」（该开关当前默认 false，见 §1.4 事实 17）；
3. **不允许静默**：本 CR 不得只改 tools 而让平台侧生成物在无人知晓的情况下失效；重生成由 owner 在部署窗口执行（不引入平台执行层、不新增 pipeline-平台耦合）。

## 4. 非功能需求

- **NFR-1 兼容性（最重要）**：`../tools` 全量既有测试与 CI（第 18 项事实所列 6 个步骤）保持绿；`crctl` 既有子命令的成功路径输出与退出码**不变**（唯一例外是 `archive` 返回**新增** `localTrunkSync`，既有字段与分类不变）。本 CR **不得签任何新例外**（CR-2026-065 已把全量测试变为真门禁）。
- **NFR-2 幂等与可重入**：`push-progress` 重放 `changed=false`；`review-record` 重放不消耗新 attempt；`archive` 重放不产生新 commit；评审发布失败按 `recovery` 重试**同一** checkpoint，不触发第二次评审。
- **NFR-3 行尾纪律（工作区纪律 #1）**：本 CR 触及哈希复算（FR-3 的 `subject-sha256` / composite）与跨行文本断言（FR-5 的测试改写），读写前必须 `\r\n → \n` 归一；解析失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」的降级。
- **NFR-4 零新增**：不新增 pipeline 节点、评审维度、账本字段、观测指标（SLO / 计数门禁）、crctl 子命令、错误码、Skill 参数、落盘文件；`emit-registry.mjs` 与 `gate_nodes_gen.go` 的**生成逻辑与 schema** 不改。
- **NFR-5 确定性（测试断言去硬编码，CR-2026-065 口径）**：`pipeline-structure.test.mjs` 的改写必须**从事实源推导**（读 JSON 实际节点集 / `_index.yml` 计数），不得钉死措辞与标点，也不得把新断言写成「等于当前行数」式恒真式。
- **NFR-6 语言纪律**：`../tools` 文档与 CR 产物用中文，代码注释按既有文件语言；`../multica` 代码注释一律英文（其 `CLAUDE.md` 硬规则）——本 CR 对 multica 的改动限于 Prompt 文档（中文），不写 Go/TS 代码。
- **NFR-7 无部署副作用**：本 CR 不触发平台 Agent DB 更新、不改 `aifirst/agent-import.mjs`、不启用 Runner；Prompt 部署与生成物重生成由 owner 执行。

## 5. 验收标准

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-4、FR-5 | §5 AC-1 | 三份 pipeline JSON 节点数 = **5 / 4 / 12**；**不存在任何位于 `human_approval` 之后的 `push-progress` 节点**（静态断言，按 JSON 节点序求值）；**且**三份 JSON 中 `ref=push-progress` 的节点对象计数 = **0**；`_index.yml` 的 `nodes:` 与 JSON 实际节点数一致；被删节点 id 不出现在任何 JSON 中。 |
| AC-2 | FR-5、NFR-5 | §5 AC-2 | `pipeline-structure.test.mjs` 的既有断言按新事实同步（「16 节点」「`review-code` < checkpoint < `human_approval`」「replayNodes 5 项」「`…0010` 含 `评审后 checkpoint phase=complete`」等改为事实源推导），全套断言全绿；新增断言覆盖 AC-1 两条判据与「review SKILL 含发布步骤 + clean 前置」。断言不得钉死易漂移措辞（NFR-5）。 |
| AC-3 | FR-1、FR-2、FR-3 | §5 AC-3 | 四个 review SKILL **均含**：评审前置 `healthy` 检查（`crctl workspace inspect` + `dirty=false` 判据 + 「请作者先提交」语义）、PASS 后 `push-progress` 调用（`message = <阶段>评审通过`、消费 `phase`/`batchId`/`repositories[]`/`metadataCommit`）、发布对账（三阶段各自判据）、失败语义（不改 verdict / 不重评 / 不代提交 / 按 `recovery` 重试同一 checkpoint）；BLOCK 分支**不含**发布调用；四个 SKILL 均**不含** `recoverCommand` / `recover_command`（`contract-scan.test.mjs` 的 `RETIRED_RECOVERY` 全树零命中）。 |
| AC-4 | FR-2、FR-8 | §5 AC-4 ＋ B-1 回归判据 | ① 矩阵：`quality-reviewer-agent` 的 `can-call` 含 `push-progress`、`forbidden` 不含 `push-progress` 且仍含 `checkpoint`；② **权限面闭合（B-1 回归判据，机械复核）**：只读 `workspace inspect` 在**三处载体**（矩阵注释、`AGENT-SKILL-MATRIX.md` 变更行、multica 部署副本的受限 crctl 权限块）均被列入该 actor 的允许面，**且**四个 review SKILL 均含该前置调用——两侧在同一条断言内同时校验，缺任一侧即失败；③ 反向：四个 review SKILL 文本不含 `crctl checkpoint`（发布只经 `push-progress` Skill），tools 与 multica 两份 `quality-reviewer-agent.md` 的受限 crctl 权限块均含 `workspace inspect`（旧白名单不得原样保留）；④ `AGENT-SKILL-MATRIX.md` 的「本 CR 权限变更」节登记本 CR 一行；`check-skill-matrix.mjs` / `check-agents-contract.mjs` / `lint-prompts.mjs --mode enforce` 全绿。 |
| AC-5 | 全部 | §5 AC-5 | CI（`crctl-ci.yml`，Ubuntu + Windows）全量绿：lint-prompts、skill matrix、agents contract、pipeline JSON 结构断言、`suite-gate.mjs --run`、writeback 单测——**不得签任何新例外**。 |
| AC-6 | FR-1、FR-6、FR-7 | §5 AC-6（＋本 PRD 定义载体与时点） | **交付时可判定**：受控端到端演练的**载体与时点已写死**——载体 = 本 CR 交付后新注册的一个小体量演练 CR（首选，owner 指定；次选 CR-P1 的首次阶段评审 PASS 链），时点 = 该载体走完四个阶段的评审发布与审批后；观察项 ① 每个 review PASS 后远端存在完整批次（`repositories[].confirmed=true`、`metadataCommit` 非空、对账通过）；② 审批动作**不产生**任何 checkpoint 委派（评审 PASS 之后的 checkpoint 次数 = 0）；③ 审批未发布时 `merge` 给出 `MERGE_SOURCE_MISSING`/`RELEASE_REMOTE_NOT_PUSHED` + `recovery`，同 run 内执行后可继续（或首次即通过）；④ 「为单个 `push-progress` 单独开 task」次数 = 0。**该演练在本 CR 交付时无法产出证据**，故本 CR 交付说明必须把 AC-6 登记为**延期验证点**：写明载体（CR-ID 或候选集）、观察项 ①~④、责任 agent（delivery-agent 记录发布批次与 `merge` 兜底、cr-coordinator-agent 记录委派计数）与关闭触发条件（载体归档或该链路首次走完）；未登记即 AC-6 未通过。 |
| AC-7 | FR-9 | §5 AC-7 | `README.md`、`openwiki/pipelines/overview.md`、`dir-graph.yaml#pipeline_templates.contract`、`push-progress/SKILL.md` 四处口径一致：阶段终点完成条件 = 评审 PASS 的 checkpoint（评审者执行、每阶段一次）、审批后无 checkpoint 节点、未发布审批提交由搭车承担；四处均不再出现「审批后的阶段终点 checkpoint 为强制完成条件」的旧句。 |
| AC-8 | FR-10 | §5 AC-8 | `archive-tx.test.mjs`：① `archiveCr` 返回含 `localTrunkSync`（`phase=complete` 与 `cleanup-pending` 两分支均含）；② 分类正确：`unchanged` / `synced` / `skipped(wrong-branch|dirty|diverged)` / `failed(fetch-failed|trunk-unavailable|ff-only-failed)`；③ **dirty 跳过用例**：主 checkout dirty → `skipped`+`reason=dirty`、本地内容逐字节未变；④ 全流程不出现 `reset`/`clean`/`stash`/强推（命令面断言）；⑤ 归档幂等重放（`changed=false`）时 `localTrunkSync` 仍返回、不产生新 commit；⑥ `cr-archive/SKILL.md` 与 delivery-agent 汇报面含该字段与分类说明。 |
| AC-9 | FR-11 | §5 AC-9 | 本 CR 交付说明中登记：`gate_nodes_gen.go` 的 `NodeID`/`Seq` 与 registry digest 因节点集变化需重新生成（给出触发原因与受影响映射清单），**或**声明「重新生成前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用」；两种表述**必有其一**，不得静默。 |
| AC-10 | 全部（边界与串行） | §2.2、§7（本 PRD 新增） | ① **scope_out 可检查**：交付 diff 中不含平台执行层 / Runner / continuation 相关实现文件，不含新 pipeline 节点、新评审维度、新账本字段、新观测指标（SLO / 计数门禁），不含 `crctl` 事务层 / 状态机 / 错误码 / `reviewLoop` 语义改动（`review-code.reviewLoop.replayNodes` 删除一项为唯一例外），不含 `recovery` 合同字段名改动、不含 `recoverCommand`/`recover_command` 复活（`contract-scan` 零命中）；② **不做审批后可选 checkpoint 节点**：diff 中不存在以 `onFail: skip` + 输入端开关形式恢复「审批后/评审后 checkpoint」的节点；③ **串行（不与其他 CR 并发）**：实施与交付期间 `change-requests/_backlog.yml` 的在途条目**只有本 CR**，CR-2026-063/064/065 的 `crctl status` 均为 `archived`，且本 CR-ID 为 `CR-2026-066`（紧随 064/065 之后、不早于 CR-P1 / CR-P2）；④ 与 CR-P1 / CR-P2 的面不重叠：`review-tech-design` 的 Step 2.x 区块与 `quality-reviewer-agent#评审判断`、code pipeline 的 dev-start 提示、`review-dev-plan` 的 acceptance-verifiability 面均零 diff（P1 / P2 按新基线写）。 |

来源 §5 的 AC-1~AC-9 与上表一一对应（未新增也未合并判据）；AC-10 是「把 §2.2 scope_out 与 §7 串行约束写成可检查约束」的落地判据。

## 6. 成功指标

- 每个阶段的**评审 PASS 后**远端存在完整批次的比例 = 100%（`repositories[].confirmed=true` 且 `metadataCommit` 非空）。
- **审批后**产生的 checkpoint 次数 = 0；「为单个 `push-progress`/checkpoint 单独开 task/委派」次数 = 0。
- AC-6 的延期验证点（载体、观察项、责任 agent、关闭触发条件）在本 CR 交付说明中登记 = 100%；未登记则「审批后 checkpoint 委派次数 = 0」无证据可交。
- 三份 pipeline JSON 中 `ref=push-progress` 的节点数 = 0；审批后 push-progress 节点数 = 0。
- 评审发布的对账通过率 = 100%（不等即 `CONTRACT_DRIFT`，无静默通过）。
- `archiveCr` 返回 `localTrunkSync` 的比例 = 100%；归档后各仓主 checkout 与 origin trunk 不一致且未被如实报告（静默 dirty/diverged）的次数 = 0。
- 本 CR 新增的观测指标 / 计数门禁 / pipeline 节点 / 评审维度 / 账本字段 / crctl 子命令数 = 0。
- 既有测试回归数 = 0；CI 新增例外数 = 0。

## 7. 范围排除

**来源 §2.2 scope_out（逐条不做，判据见 AC-10）**

- 不引入**平台执行层**（Runner / approval-continuation / 平台 API）做 checkpoint——tools 工具包不只在 Multica 使用，不接受平台耦合（来源 §2.2 与 §1.3 已排除的替代方案）。
- 不新增 pipeline 节点、不新增评审维度、不新增账本字段、不新增观测指标（SLO / 计数门禁）。
- 不改 crctl 事务层、状态机、错误码、`reviewLoop` 语义（唯一例外：`review-code.reviewLoop.replayNodes` 删除 `push-progress …0008` 一项，5→4）。
- 不改 `merge` / `archive` / `writeback` 的业务算法；不改 `recovery` 合同（CR-2026-064 已定，本 CR 一切新文本使用结构化 `recovery`，禁止复活旧字段名 `recoverCommand` / `recover_command`）。
- 不复活 `recoverCommand` / `recover_command`（`contract-scan` 退役名单整树扫描零命中）。
- 平台 DB / `aifirst/agent-import.mjs` / Prompt 部署 / 生成物重生成由 owner 另行执行。
- **不做「审批后可选 checkpoint」节点**：不保留被删节点、也不以 `onFail: skip` + 默认关闭的输入端开关形式变相恢复（来源 §1.3 的排除理由：门后节点无强制力；如需恢复必须另起 CR）。

**来源 §7 的顺序与并发约束（可检查形式见 AC-10③）**

- 顺序：CR-P0(063) → CR-R(064) → CR-S(065) → **本 CR(066)** → CR-P1 → CR-P2；本 CR **不得早于** CR-P1 / CR-P2 执行。
- **不与其他 CR 并发**（tools 单写者）：任一 CR 失败只回滚本 CR。

**与 CR-P1 / CR-P2 的面不重叠（不得顺手改）**

- `review-tech-design` 的 Step 2.x 区块与 `quality-reviewer-agent#评审判断` 归 CR-P1；code pipeline 的 dev-start 提示、`review-dev-plan` 的 acceptance-verifiability 面归 CR-P2。
- 本 CR 不往 dev-start 提示加任何 checkpoint 前提，也不重编号 `review-tech-design` 的 Step 2.1/2.2/2.3。

**来源 §8 的取舍与回滚边界（本 CR 承接，需人工一并确认）**

- 取舍一：实现→评审窗口**不再有中途恢复点**（统一 checkpoint `…0008` 删除后）；如需恢复该节点必须另起 CR（本 CR 不做，见上「不做『审批后可选 checkpoint』节点」）。
- 取舍二：审批提交在下一阶段评审前**只在本地**（换机恢复需重签一次），code 路径由 `merge` 的 publication preflight 在同 run 内硬兜底；该取舍已在 §1.3.3 与 FR-6 写明。
- 回滚边界：FR-1~FR-3（review 发布）与 FR-4~FR-5（节点退役）互为补充但**可分别回退**；FR-10（trunk 同步）**完全独立**；FR-9 与 FR-11 只改文本与登记，回退即还原。

**本次明确不碰的既有资产**

- KB 的 `specs/`、`delivery/`、`docs/`（主 checkout 中 `docs/analysis/` 的既有未提交变动属 owner 的文档归位操作，不在本 CR 范围）。
- CR 状态机、`gates.json`、`rules.json`（controlled-shell 白名单）、CAS 与 durable ledger transaction 框架、`ENVIRONMENT_MISMATCH`、版本化 `cmd-NN` 与 test evidence。
- `../multica` 的 `CUSTOM.md`、`cr-prompts-revised/agent-skill-matrix.yml`、`aifirst/**` 与任何 Go/TS 代码。

## CR-P1：评审输入结构与回修闭合（v0.40 · CR-2026-067）

## 1. 概述

### 1.1 问题陈述

需求来源是 Issue AIFI-29 附件《AIFI-18_SDD到planTASK_原位修订方案.md》（33,478 B，附件 id `01a0a23f-47e4-7663-ab33-b749cc4ff22c`）第 5 节「CR-P1：评审输入结构与回修闭合」（KB 内同文路径 `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md`）。该节钉出三类**结构性**问题，它们都不是「评审不认真」，而是**合同本身让漂移不可判定**：

1. **既有实现事实被定义两次、且没有稳定标识**：`write-tech-design` 的 Step 2.6 既有实现证据段要求「必须逐项附证据」，紧随其后的 `### 既有实现依赖与事实` 小节又维护一份编号清单；SDD 正文可以、也事实上被允许**重新陈述**「当前代码已经如何工作」。正文与依赖表因此是两份可漂移的事实副本，而每条事实只有**位置序号**（`1.` `2.` `3.`）作为身份——正文增删一条即整体漂移，评审无法用一个稳定 key 交叉核对「正文这条断言对应表里哪条」。
2. **两侧强制性不一致、判据不可判定**：写侧 `commit SHA` 是**必填**（Step 2.6「必须逐项附证据：`repo`、`commit SHA`、`relative path`、`stable symbol/对象`、`conclusion`」），评审侧却写作「每项固定包含 `repo`、`relative path`、`stable symbol/对象` 和"依赖结论"，**并可附** `commit SHA`」（§1.4 事实 4）——同一份合同对同一条事实给出两种强度，作者按写侧写、评审按评侧放宽，闭合无从机械判定。同时评侧判据是「正文同类事实**是否漏列**」这一**集合比较**，缺一条可判定的关系式（「正文引用的 `dep-N` 必须已定义」）。
3. **回修只修被点名的一格，批准范围四字段缺自洽判据**：`write-tech-design` 现有唯一一句回修约束是「回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案」（§1.4 事实 2），没有任何「状态链必须整体重证」的要求——AIFI-18 实测中 stop handler、running、空 ID 顺序、失败回流被**拆成多轮**修补，正是该形态（来源 §5.3）。与之并列，`批准范围` 四字段（`scope_in`/`scope_out`/`zero_diff`/`follow_up`）只有「章节与字段必须存在、空字段须写 `无`/`N/A`」的存在性判据，没有自洽判据：`scope_in` 与 `zero_diff` 可能对同一对象同时要求「改」与「不改」、外部治理强制修改可能被藏进 `scope_out`、当前 AC 的必要条件可能被塞进 `follow_up`——这些冲突到 dev-plan 阶段才由 upstream 轨触发，返工代价被推迟放大（来源 §5.4）。

**根因结论（来源 §5，本 PRD 采纳）**：三项的共同根因是**事实与判据都缺一个可判定的承载体**——事实缺稳定标识（`dep-N`）、判据缺两侧同口径的关系式（引用必须已定义 + `commit SHA` 两侧共同必填）、回修与范围缺「什么算闭合」的判据（状态链整体重证 + 范围四字段自洽）。因此本 CR 的三条杠杆全部是**原位把既有 Step 2.x 判据与 SDD 写作合同收紧**，不新增任何结构性载体。

### 1.2 解决方案摘要

按来源 §5.1–§5.5 逐条落地（每组都锚定「仓 + 文件 + 既有段落」，见 §1.3.1 与 §3 各 FR）：

1. **既有实现事实唯一表达**（FR-1）：`write-tech-design` 的 `### 既有实现依赖与事实` 小节原位改为 `dep-N` 固定结构（`repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论` 五字段，`commit SHA` 为必填 40 位 SHA）；实现事实**只在该表定义一次**，SDD 正文只能写「设计依赖 `dep-N`」、不得重述「当前代码已经如何工作」；无法绑定字段的引用按待核实依赖列出且不得继续作为方案前提；`N/A` 仅在正文与依赖表均无既有实现依赖时可用。
2. **评审侧同口径收口**（FR-2）：`review-tech-design` 的 **Step 2.1** 原位修订——reviewer 核验依赖表五要素；**正文只能引用存在的 `dep-N`**；正文出现未通过 `dep-N` 引用承载的当前实现事实 → blocker；把「**并可附** `commit SHA`」改为与写侧同口径的**必填**。修订只在既有 Step 2.1 内进行，**不重编号任何 Step**（Step 1.0 clean 前置与 Step 5/6 PASS 发布已由 CR-2026-066 占用）。
3. **首轮全量检查保持原样**（FR-3）：`review-tech-design#Step 2.2` 的既有「首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束」句**零改动**，只在验收时核对仍存在；**不**在 `tools/agents/quality-reviewer-agent.md` 新建小节或复制第二份判据（来源 §5.2 已删除「`#评审判断` 小节」这一不存在的锚点）。
4. **状态链整体重证**（FR-4）：`write-tech-design` 的既有回修模式句**原位扩写**——blocker 触及状态判定、活动性、事件顺序、空值或失败回流时，必须重证该状态链的完整输入维度、分支、可见动作与对应 AC；不得只修被点名的一格；同一标识符/锚点/testid 全文只有一个裁决；未受该根因影响的已确认方案不得重写（「整体重证」与「不扩散」两个方向同时约束）。
5. **批准范围四字段自洽**（FR-5）：`write-tech-design` 的「批准范围」四字段说明与 `review-tech-design` 的「批准范围前置」段**两侧原位加入同一组判据**——`scope_in` 与 `zero_diff` 不得对同一对象自相矛盾；外部治理规则强制修改时必须在 SDD 阶段纳入 `scope_in`、修订 `zero_diff` 或给出已有合法出口；不得用 `scope_out` 隐藏必须发生的治理修改；`follow_up` 不得承载当前 AC 的必要条件。评侧发现冲突**必须在 SDD 阶段形成 blocker**，不留到 dev-plan 再触发 upstream。
6. **同 CR 测试断言与门禁基线同步**（FR-6）：`pipeline-structure.test.mjs` 的 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确` 用例内的两组 term **原位改写**为 `dep-N` 口径（不另写第二个反向用例、用例数不减少），`gate-registry.json#manifest.cases` 与实际顶层用例数同步，`suite-gate --run` 全量绿且**不签任何新例外**。

### 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

收紧 SDD 既有实现事实的表达与评审闭合：写侧把既有实现事实收敛为带稳定 `dep-N` 的唯一依赖表（`commit SHA` 必填），正文只引用不重述；reviewer 侧 `commit SHA` 同为必填并核验 `dep-N` 引用；状态链类 blocker 必须整体重证、批准范围四字段判据在写手与评审两侧一致。同 CR 原位同步 `pipeline-structure.test.mjs` 的 CR-2026-055 依赖清单用例与 `gate-registry.json` 用例数，不新增 annotation dimension、账本字段、评审指标或 Pipeline 节点。

#### 1.3.1 scope_in 边界（原文前缀，评审核对用）

> CR-P1 只原位改 review SKILL 既有 Step 2.x 与 SDD/plan 写作合同，不重编号、不碰 crctl 事务层、不新增 annotation dimension / 账本字段 / 评审指标 / Pipeline 节点；`dep-N` 为写侧与评审侧统一语义，`commit SHA` 两侧同为必填。

（该句来自来源 §2 的 CR-P1 边界段；其中「plan 写作合同」的落地归 CR-P2（来源 §6 CR-P2 / `write-dev-plan`、`write-dev-tasks`、`review-dev-plan`），本 CR 的写作合同面 = **SDD 写作合同**，见 FR-7 第 5 条。）

逐条落到「哪个仓的哪个文件、改哪一段」（基线行号与证据见 §1.4）：

| # | 仓 | 文件 | 修订类型（原位） |
|---|---|---|---|
| 1 | `../tools` | `skills/develop/write-tech-design/SKILL.md` | Step 2.6 既有实现证据段的依赖形态改 `dep-N` + 正文只引用；`### 既有实现依赖与事实` 小节固定结构改 `dep-N`；回修模式句扩写状态链整体重证；Step 2 第 9 节「批准范围」加四字段自洽判据 |
| 2 | `../tools` | `skills/develop/review-tech-design/SKILL.md` | Step 2.1 existing dependency 核验段：五要素核验 + 正文只能引用存在的 `dep-N` + 未承载事实成 blocker + `commit SHA` 由「并可附」改必填；Step 2「批准范围前置」段加同一组自洽判据 |
| 3 | `../tools` | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确` 用例内两组 term 原位改写为 `dep-N` 口径（不新增反向用例） |
| 4 | `../tools` | `skills/shared/crctl/scripts/test/gate-registry.json` | `manifest.cases["pipeline-structure.test.mjs"]` 与实际顶层用例数同步（条件性，见 FR-6 第 2 条与 §1.5 第 2 条） |

**本 CR 明确零 diff 的面**（评审核对清单）：四个 review SKILL 中除 `review-tech-design` 外的三个；`tools/agents/quality-reviewer-agent.md`；`skills/develop/review-tech-design/SKILL.md` 的 Step 1.0 / Step 2.2 / Step 2.3 / Step 3 / Step 4 / Step 5 / Step 6；`write-tech-design/SKILL.md` 的 Step 1 / Step 2.5 / Step 3 / Step 4 / Step 5；`skills/shared/crctl/scripts/{crctl.mjs,lib/**}`；`pipeline-templates/**`；`agent-skill-matrix.yml`；`skills/develop/{write-dev-plan,write-dev-tasks,review-dev-plan}/SKILL.md`。

#### 1.3.2 目标仓库与版本

- 代码实施在 `../tools/`（两个 develop SKILL + 既有测试与门禁登记）。
- knowledge-base 承载本 PRD 与来源文档；本 CR 不改 KB 的 `specs/`、`delivery/`、`docs/`。
- `../multica/` 本 CR **零 diff**（本 CR 不改任何 Agent Prompt 部署副本、不改 Go/TS 代码）。
- `target-version` 继承 `cr.md` 的 `0.40`（注册阶段确定，`crctl version-set` 之外无改写入口）；`target-spec-id` = `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

#### 1.3.3 契约说明（确定性四查适用面）

本 CR **不新增、不修改任何用户可调用契约**，四查（幂等 / 权限 / 错误闭包 / 副作用）对本 CR **N/A**，理由逐条：

- **无 HTTP API**：本 CR 不改任何 endpoint / request / response。
- **无 CLI（crctl）契约变更**：`skills/shared/crctl/scripts/**` 除既有测试文件外零 diff——不新增/删除子命令与 flag，不改任何 JSON 输出形状、退出码、错误码、调用者约束（不碰事务层，见 FR-7）。
- **无 Skill 契约变更**：`write-tech-design` / `review-tech-design` 的**必填参数、落盘路径、允许的状态转换、失败码、与 `crctl` 的唯一写入边界全部不变**（§1.4 事实 18）。本 CR 改的是两份 SKILL **正文内的 Prompt 判据**：依赖表的表达形态（`dep-N`）、正文引用规则、回修判据、批准范围自洽判据、以及一处强制性口径（`commit SHA` 由评侧可选改必填）。这些是**评审与写作合同**，不是调用契约；它们的验收以「文本合同 + 既有测试断言」形式给出（AC-1~AC-9）。
- **唯一强度变化的说明**：评侧 `commit SHA` 由「并可附」改为必填，会让原本可通过的 SDD 在**新口径**下成为 blocker。该变化不改变任何 crctl 状态转换或错误码，只改变 `review-tech-design` 的 blocker 判定输入；对既有已归档 CR 无追溯效力（评审判据只对评审发生时的 SKILL 版本生效）。

### 1.4 当前事实（落笔前核实）

基线（`crctl register` ensure 的 requirement worktree HEAD）：

| 仓 | worktree HEAD |
|---|---|
| `ai-first-platform-docs`（本 KB） | `0a3253403a2d377a5329db5bb9269fe00e239f17`（register 提交） |
| `../multica` | `5c1880f2125e73733b1a5bfc7501db310ab7f584` |
| `../tools` | `7094e492822594b971699924478ba27ccf612c42`（= tools `main`） |

以下结论均在上述 SHA 上核实（路径相对各自仓根）：

| # | 结论 | 证据 |
|---|---|---|
| 1 | 写侧既有实现证据段与依赖小节现状：五要素（含 `commit SHA`）必填、固定结构为**编号列表** `1. repo: …`、排序约束「正文首次出现顺序」、消费口径句 `sdd.explicit_existing_dependencies` | `skills/develop/write-tech-design/SKILL.md` Step 2.6（「必须逐项附证据：`repo`、`commit SHA`、`relative path`、`stable symbol/对象`、`conclusion`」）与紧邻的 `### 既有实现依赖与事实` 小节（```text 1. repo: … relative path: … stable symbol/对象: … commit SHA: <40-character SHA> 依赖结论: … ```） |
| 2 | 写侧当前唯一的回修约束句是「回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案。」，**无**状态链整体重证要求 | 同文件，`### 既有实现依赖与事实` 小节末（该句位于 SDD-CLOSE 关闭义务段之前） |
| 3 | 写侧「批准范围」现状只要求**存在性与字段完整性**（四字段承载且仅承载四字段；空字段写 `无`/`N/A` 加理由；`approve-tech-design` 后只读；冲突只能经 `review-dev-plan` 双轨回上游）——**无** `scope_in`/`zero_diff` 自洽判据、无「治理强制修改不得藏进 `scope_out`」、无「`follow_up` 不得承载当前 AC 必要条件」 | 同文件 Step 2 章节 9「批准范围（契约必填章节，CR-2026-057 FR-5/FR-6）」全段 |
| 4 | 评侧 `commit SHA` 为**可选**（与写侧必填不一致） | `skills/develop/review-tech-design/SKILL.md` Step 2.1：「每项固定包含 `repo`、`relative path`、`stable symbol/对象` 和"依赖结论"，**并可附** `commit SHA`」 |
| 5 | 评侧已有「不扫描全仓 / 不猜测未写出的依赖」边界与「正文同类事实是否漏列」交叉检查；判据是集合比较，**无**「正文引用的 `dep-N` 必须已定义」这一关系式 | 同文件 Step 2.1 后段（「`sdd.explicit_existing_dependencies` 仅指该清单，不由 reviewer 扫描全仓库或临时猜测；reviewer 还必须交叉检查正文同类事实是否漏列。」） |
| 6 | 首轮全量句**已在库**（CR-2026-055 引入），逐字为「首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束；合并同根因问题、拆分不同根因问题，同一轮 blockers 同时包含独立根因。」 | 同文件 Step 2.2 首句 |
| 7 | 评侧「批准范围前置」现状只核对**章节与四字段存在**（缺即 blocker，`本轮新增：`），**无**自洽判据、**无**「冲突必须在 SDD 阶段形成 blocker、不留到 dev-plan upstream」的要求 | 同文件 Step 2 引用块「**批准范围前置（CR-2026-057 FR-5/AC-5）**」 |
| 8 | `quality-reviewer-agent.md` 现有 **7** 个 `##` 小节：角色定位 / 意图与路由 / 独立会话路径（FR-A6）/ 人工决策边界 / 权限事实源 / 发布职责与搭车硬规则（CR-2026-066 FR-1 / FR-7）/ 约束；`## 评审判断` 小节**不存在**，`评审判断` 一词仅出现在 `## 意图与路由` 的一句内 | `tools/agents/quality-reviewer-agent.md`：`grep -n '^##'` 输出 7 行；L24「评审判断写临时 payload，canonical 落盘由 `crctl review-record` 独占」 |
| 9 | 目标用例逐字断言两组 term：写侧 8 项 `['### 既有实现依赖与事实', '正文首次出现顺序', 'repo:', 'relative path:', 'stable symbol/对象:', 'commit SHA:', '依赖结论:', 'sdd.explicit_existing_dependencies']`；评侧 4 项 `['名为"既有实现依赖与事实"的显式小节', '有序清单', 'sdd.explicit_existing_dependencies', '正文同类事实是否漏列']` | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` L616 用例 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确` |
| 10 | CR-2026-066 的反向断言只覆盖**四个 review SKILL**（`REVIEW_SKILLS` 常量 L636–641），`write-tech-design` **不在**其中；C 段断言不含 `crctl checkpoint`，D 段断言不含 `push-progress 之后` / `push-progress 之前` / `统一 checkpoint 后` | 同文件 L656 用例（断言 A/B/C/D）与 L636 `REVIEW_SKILLS` 定义 |
| 11 | `write-tech-design/SKILL.md` 现存 **1** 处 `crctl checkpoint`（Step 1 提交口径句「架构审批后由同一批 checkpoint（`crctl checkpoint`）纳入」）；四个 review SKILL 均为 **0** 处 | `grep -c 'crctl checkpoint'`：write-tech-design = 1，四个 review SKILL = 0 且各自四 token 均为 0 |
| 12 | `gate-registry.json#manifest.cases["pipeline-structure.test.mjs"] = 35`，`exceptions: []`；同文件实测**顶层用例 = 36**（TAP `1..36`、`# tests 36`、`# pass 36`、`# fail 0`） | `test/gate-registry.json` 与 `node --test --test-reporter=tap pipeline-structure.test.mjs` 实测输出 |
| 13 | `suite-gate` 的用例数判据是**下限**：`if (f.cases < base) trigger('SUITE_MANIFEST_CASE_DROP')`；`manifest.cases` 只校验「缺基线 / 非正整数」，**不校验实际值大于基线** | `test/suite-gate.mjs` L448–453 与 L123–126 |
| 14 | CI 已是真门禁（Ubuntu + Windows 各跑一遍）：`lint-prompts.mjs --mode enforce` → `check-skill-matrix.mjs` → `check-agents-contract.mjs` → pipeline JSON 结构断言（全模板）→ `suite-gate.mjs --run` → writeback 单测 | `.github/workflows/crctl-ci.yml` 六个 step |
| 15 | `recoverCommand` / `recover_command` 在退役名单里，整树扫描命中即红 | `test/contract-scan.test.mjs` L418 `RETIRED_RECOVERY = ['recoverCommand', 'recover_command']` |
| 16 | 目标用例位置与形态：`pipeline-structure.test.mjs` 顶层用例 `^test(` 共 36 条，其中 CR-2026-055 相关 4 条（L568 / L585 / L602 / L616）、CR-2026-066 相关 1 条（L656）；本 CR 目标用例 = **1 条**，原位改写不改变条数 | 同文件 `grep -c '^test('` = 36 |
| 17 | 评侧 Step 编号现状：Step 1（含 **1.0** clean 前置）、Step 2（含批准范围前置）、Step 2.1、Step 2.2、Step 2.3、Step 3、Step 4、**Step 5**（PASS 发布与对账）、**Step 6**（输出摘要）——Step 5/6 与 Step 1.0 由 CR-2026-066 占用 | `skills/develop/review-tech-design/SKILL.md` 节标题逐条读取 |
| 18 | 两份 SKILL 的参数表、落盘路径、状态转换与写入边界本 CR 不变 | `write-tech-design` 参数 = `cr_id`/`tech_context`/`operational_workspace`/`resources`/`review_feedback`/`self_repair_attempt`，落盘 `change-requests/{cr_id}/sdd.md`，推进 `requirement-approved→tech-designing→tech-design-review-pending`；`review-tech-design` 参数 = `cr_id`/`workspace`/`resources`/`reviewer`/`review_feedback`/`self_repair_attempt`，canonical 落盘 `review-annotations/sdd.yml` + review-loop + traceability（`crctl review-record` 独占） |
| 19 | 串行约束当前成立：CR-2026-063/064/065/066 的 `crctl status` 均为 `archived`；注册前 `change-requests/_backlog.yml` 无在途条目；本次 `crctl register` 返回 `cr_id = CR-2026-067`、`phase = complete`、`targetVersion 0.40`、commit `0a3253403a2d377a5329db5bb9269fe00e239f17`，同一命令幂等重放返回 `changed = false` | `crctl status change-requests/_index.yml` 尾部与 register 两次调用的 JSON 输出 |

### 1.5 对来源文档的事实更正与需人工确认的口径

1. **写侧 `commit SHA` 已经是必填，本 CR 的收口点在评侧（来源 §5.1.1 的措辞会让人以为两侧都要「改成必填」）**：来源 §5.1.1 写「`commit SHA` 在 `dep-N` 中为**必填**，与评审侧口径一致（见 5.1.2）」。实测写侧 Step 2.6 已是「必须逐项附证据：`repo`、`commit SHA`…」，固定结构也已是 `commit SHA: <40-character SHA>`（§1.4 事实 1）；真正不一致的是**评侧**的「并可附 `commit SHA`」（§1.4 事实 4）。本 PRD 的 FR-1/FR-2 按「写侧保持必填并换 `dep-N` 表达、评侧由可选改必填」落笔，两侧终态同为必填——**不改变**来源的目标（两侧同口径），只更正「哪一侧需要收紧」。需人工一并确认。
2. **门禁基线值与实测值的落差（本 PRD 收口裁定，需人工一并确认）**：`gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]` 登记值 **35**，而该文件实测顶层用例 **36**（§1.4 事实 12、13、16）。`suite-gate` 的判据是 `cases < 登记值` 即红，因此**多出 1 条用例不会触发红灯**——这 1 个用例（CR-2026-066 的 L656 断言）是在 CR-S 登记基线之后追加的。来源 §5.1.1 只要求「保持用例数不减；若用例数发生变化，同 CR 刷新 `manifest.cases`」，而 §5.5 的验收写「`gate-registry.json#manifest.cases` 已同步」。本 PRD 采用**同步口径**：FR-6 第 2 条要求实施后该条目与实际顶层用例数一致（本 CR 原位改写预期不改变用例数，**不新增**用例，故若实施后仍为 36 而登记值仍为 35，则把登记值同步为 36；`suite-gate.mjs` 的判据语义与之无关，**不改**）。该项不改变来源的方案取向。
3. **来源 §5.2 的删除锚点已由本 PRD 独立复核**：`quality-reviewer-agent.md#评审判断` 小节**确实不存在**（§1.4 事实 8），来源「删除原方案中的错误锚点」结论成立；本 CR 因此**零改动**该 Agent Prompt，判据唯一事实源 = `review-tech-design/SKILL.md`。
4. **`dep-N` 的稳定性口径（来源未写明，本 PRD 钉定，需人工一并确认）**：来源只写「每条事实获得稳定 `dep-N`」，未写编号生命周期。本 CR 钉为：**按正文首次出现顺序分配、只增不改、正文增删条目不重编号**（删除的条目留空洞，不复用编号）。若不钉，`dep-N` 只是把「序号漂移」换成另一个编号面，与「稳定标识」的意图相反；同时保留既有「按正文首次出现顺序」的排序约束，使编号顺序与正文顺序一致，评审可按序核对。
5. **反向 token 约束的适用面（避免误删既有文本）**：来源 §2/§5.1.2 要求「四个 review SKILL 的新增文字不得出现 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`」。实测这四个 token 在四个 review SKILL 中**已经全为 0**（§1.4 事实 11），该约束对本 CR 是**保持性**约束（新增文字不得重新引入）；而 `write-tech-design/SKILL.md` 现存 1 处 `crctl checkpoint`（提交口径句），它**不在** CR-2026-066 的 `REVIEW_SKILLS` 反向断言面内（§1.4 事实 10），且删除它属于独立的发布口径变更、不在来源 §5 授权面内——本 CR **不删该句**，只保证**本 CR 新增文字**不引入该 token 家族。
6. **评侧 Step 2.3 的「分级」边界对本 CR 的约束**：`review-tech-design` Step 2.3 已明确「不得仅因缺少里程碑、TASK owner、任务拆分、工时、完成标志、`cmd-NN`、cwd/timeout、具体测试文件或完整执行命令而形成 blocker——这些是 PLAN/TASK 粒度」。FR-5 新增的范围自洽判据**不得**把该边界扩大为「范围字段写得不够详细即 blocker」：判据只针对**四字段之间的自相矛盾与必需条件错位**（可判定），不针对详尽程度。
7. **来源 §5.5 的三条验收在语义上重叠**（「两侧 `commit SHA` 同为必填」「正文不再重复定义既有实现事实」「`pipeline-structure.test.mjs` 已原位同步」），本 PRD 把它们拆到 FR-1/FR-2（行为）与 FR-6（证据面）两组 AC，避免同一条不变量在两个 AC 里各自表述成不同强度。

### 1.6 修订记录

- 初稿（2026-09-15）：按来源附件 §5（含 §5.1–§5.5）与注册摘要（`cr.md` summary）起草；基线事实在 §1.4 三个 worktree HEAD 上逐条核实。FR 编号与来源 §5 的小节一一对应（§5.1.1→FR-1、§5.1.2→FR-2、§5.2→FR-3、§5.3→FR-4、§5.4→FR-5、§5.1.1 末段＋§5.5→FR-6、§2 边界→FR-7）；AC-1~AC-8 对应来源 §5.5（未合并判据，只按行为面/证据面分组），**AC-9 为本 PRD 新增**，把来源 §2 的 CR-P1 边界与 §8 的串行约束写成可检查约束。§1.5 记录两处对来源文档的确认（第 1、5 条）、一处删除锚点的复核（第 3 条）与三处本 PRD 钉定的口径（第 2、4、6 条），需在人工审批时一并确认。

## 2. 用户故事

- **US-1 SDD 写手（`write-tech-design` / dev-agent）**：作为写 SDD 的人，我希望既有实现事实**只在一处定义**、每条有稳定 `dep-N`，这样正文只需写「设计依赖 `dep-N`」，回修时不会出现「正文改了、表没改」的第二份事实副本。
- **US-2 SDD 评审者（`review-tech-design` / quality-reviewer-agent）**：作为核对依赖的人，我希望能用一个**稳定 key**（`dep-N`）逐条核对，且两侧对 `commit SHA` 的强制性一致（都必填），这样我不会因为「评侧允许省略 SHA」而把一个写侧严格要求的事实放过去。
- **US-3 提 blocker 的评审者**：作为发现状态链问题的人，我希望回修被要求**整体重证该状态链**（不是只补被点名的那一格），这样同根因问题不会在 stop handler / running / 空 ID / 失败回流之间被拆成多轮修补。
- **US-4 人工审批者（Ray）**：作为批准 SDD 的人，我希望 `批准范围` 四字段在**写侧与评侧使用同一组判据**，`scope_in` 与 `zero_diff` 不会自相矛盾、治理强制修改不会被藏进 `scope_out`、当前 AC 的必要条件不会塞进 `follow_up`，这样我看到的批准范围是自洽的，而不是把冲突推迟到 dev-plan 才暴露。
- **US-5 CR 协调者**：作为路由回修的人，我希望回修与审批范围的问题在 **SDD 阶段**就被评审判据拦下，这样不会出现「dev-plan 阶段才触发 upstream 轨、整轮 plan/TASK 作废」的返工。
- **US-6 维护 tools 的开发者**：作为改 SKILL 的人，我希望既有断言在同一份 diff 内原位同步、`gate-registry.json` 的基线与实际一致、不签任何新例外，这样 CI 不会在中间态变红，也不会留下「测试删了一条没人发现」的静默缺口。
- **US-7 本 CR 的 reviewer**：作为本 CR 的评审者，我希望逐条核对「哪个仓的哪个文件的哪一段被原位改了、哪条断言变了、哪些面必须零 diff」，使得这次收紧不引入第二套判据、不重编号 Step、不新增任何观测负担。

## 3. 功能需求

### FR-1 既有实现事实的唯一表达（`write-tech-design`）〔来源 §5.1.1〕

修订面 = `skills/develop/write-tech-design/SKILL.md` 的 **Step 2.6 既有实现证据段**与紧随其后的 **`### 既有实现依赖与事实` 小节**，两处均**原位修订**（不新增小节、不重排 Step 编号、不改 Step 2.6 的 AC 映射合同）：

1. **覆盖面不缩小**：保留既有的「涉及既有实现（现有仓库、文件路径、稳定符号、配置键、接口/协议、数据库结构、模块行为、调用顺序或责任边界，且是方案成立前置条件）的断言，必须逐项附证据」与五要素清单（`repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论`）；本 CR 不缩小该覆盖面，也不改「核验必须覆盖正文所声称的实际行为，不以『文件或符号存在』代替行为成立」。
2. **稳定标识 `dep-N`**：每条既有实现事实获得稳定标识 `dep-N`（N 为正整数）；编号按**正文首次出现顺序**分配，**只增不改**——正文增删条目不重编号，被删除的条目留下空洞、编号不复用（本 PRD 钉定，见 §1.5 第 4 条）。
3. **固定结构原位改为**（原 `1. repo: …` 编号列表形态退役；小节名 `### 既有实现依赖与事实` 与五个字段名保持不变）：

   ```text
   dep-1
     repo: <repository id>
     relative path: <path from repository root>
     stable symbol/对象: <symbol, key, interface, module, behavior, or responsibility>
     commit SHA: <40-character SHA>
     依赖结论: <verified current behavior required by this design>
   ```

4. **实现事实只在该表中定义一次**：SDD 正文**只能**写「设计依赖 `dep-N`」，**不得**在正文重新陈述「当前代码已经如何工作」。这是与 FR-2 第 2~3 条成对的同一条不变量（写侧要求 + 评侧判据），不得只落一侧。
5. **`commit SHA` 必填**：该字段为**必填的 40 位 SHA**（写侧现状已是必填，本 CR 保留并明确 `dep-N` 语境下的必填性），与评侧 FR-2 第 4 条同口径。
6. **待核实依赖**：无法绑定事实字段（`repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论`）的引用按**待核实依赖**列出，且**不得继续作为方案前提**（既有语义保留并强化为「前提资格」约束）。
7. **N/A 的可用条件**：`N/A（本 CR 无既有实现依赖）` **只有在正文与依赖表均无**既有实现依赖时才可用（既有语义保留）。
8. **不改的部分**：Step 2.6 的 AC 逐项映射合同（设计落点 / 可观测结果 / 可达性说明）、AC 反查正文的闭环要求、`sdd.explicit_existing_dependencies` 的消费口径、SDD-CLOSE 关闭义务（CR-2026-060 AC-06）全部不变。

### FR-2 评审侧 `dep-N` 核验与两侧同口径（`review-tech-design`）〔来源 §5.1.2〕

修订面 = `skills/develop/review-tech-design/SKILL.md` 的 **Step 2.1（AC 闭环与既有实现依赖核验）**内的 existing dependency 核验段，**原位修订**：

1. **五要素核验**：reviewer 核验依赖表中每项的 `repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论`；取证手段与边界不变——按 `resources` 匹配 `repo`、以受控只读 `crctl git rev-parse HEAD` 取 SHA、核验文件与稳定符号，**不执行** lint/build/test，**不做**全仓库无界扫描，**不猜测**作者未写出的依赖。
2. **正文只能引用存在的 `dep-N`**：正文出现的 `dep-N` 引用必须在依赖表中已定义；引用未定义的编号 = 事实引用无承载，形成 blocker。
3. **未承载的当前实现事实 → blocker**：正文出现**未通过 `dep-N` 引用承载**的当前实现事实时形成 blocker（既有判据「正文存在但未列入依赖清单的同类事实引用形成 blocker」的强化表达：判据从「同类事实是否漏列」的集合比较，升级为「是否由 `dep-N` 引用承载」的关系式）。
4. **`commit SHA` 由可选改为必填**：现基线写作「每项固定包含 `repo`、`relative path`、`stable symbol/对象` 和"依赖结论"，**并可附** `commit SHA`」；本 CR 原位改为与写侧同口径（必填 40 位 SHA；缺失或 SHA 与 `resources` 取证结果不符 → blocker）。旧「并可附」措辞**零残留**。
5. **修订只在 Step 2.1 内**：**不重编号任何 Step**（Step 1.0 clean 前置与 Step 5/6 PASS 发布已由 CR-2026-066 占用，§1.4 事实 17）；本 CR 在 `review-tech-design` 中的新增文字**不得出现** `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（CR-2026-066 反向断言零命中；该约束对本 CR 是保持性约束，见 §1.5 第 5 条）。
6. **诚实边界（明确写出）**：本规则是 **Prompt 合同**，**不宣称** NLP 机械识别全部自由文本事实——「正文事实是否漏列/是否被 `dep-N` 承载」的判定仍是评审判断，不是机械门禁；因此**不得**为它新增 crctl 校验面、lint 规则或 annotation dimension（FR-7）。
7. **不改的部分**：Step 2.1 的 AC 闭环判定伪码（缺少设计落点 / 设计结论与 PRD 契约冲突 / 结果不可观察 / 关键前置条件使 AC 不可达）、「先区分 PRD 的现有实现基线描述与目标契约」要求、Step 2.2 首轮全量句、Step 2.3 分级与前缀、Step 3~Step 6 全部不变。

### FR-3 首轮全量检查保持原样（零改动核对）〔来源 §5.2〕

1. `review-tech-design/SKILL.md#Step 2.2` 的既有句「首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束；合并同根因问题、拆分不同根因问题，同一轮 blockers 同时包含独立根因」**逐字保持**（CR-2026-055 引入，§1.4 事实 6）；本 CR 对该句**不做任何修改**，只在验收时核对仍存在（AC-3）。重复写入等于造第二份事实源，违反本方案的原位原则。
2. **不新建 Agent Prompt 小节、不复制第二份判据**：`tools/agents/quality-reviewer-agent.md` **零 diff**——不新增小节（`## 评审判断` 小节不存在，§1.5 第 3 条）、不把首轮全量判据复制进 Agent Prompt；该判据的唯一事实源是 `review-tech-design/SKILL.md`。
3. **来源原方案的三项不做**：不为「首轮漏检」写账本计数；不用 `本轮新增：` 统计流程质量；不对评审轮数作数字承诺。`本轮新增：` 仍只承担 blocker 文本分类（CR-2026-057 FR-3），不承担观测指标。

### FR-4 状态链整体重证（`write-tech-design` 回修模式原位扩写）〔来源 §5.3〕

修订面 = `write-tech-design/SKILL.md` 的现有句「回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案。」——在该句**原位扩写**（不新增小节、不改 Step 编号、不改 `reviewLoop` 与 `maxAttempts`）：

1. blocker 若触及**状态判定、活动性、事件顺序、空值或失败回流**，必须**重证该状态链的完整输入维度、分支、可见动作与对应 AC**；
2. **不得只修被点名的那一格**；
3. **同一标识符、锚点或 testid 在全文只能有一个裁决**；
4. **未受该根因影响的已确认方案不得重写**（保留既有「不无理由重写已确认方案」的约束）。

扩写后该段必须**同时**表达「整体重证」与「不扩散」两个方向：前者防止只修一格，后者防止借重证之名重写无关设计。该修订直接覆盖 AIFI-18 中 stop handler、running、空 ID 顺序和失败回流被拆成多轮修补的问题形态。本 FR **不新增** blocker 计数、轮数门禁或观测指标。

### FR-5 批准范围四字段自洽（写手与 reviewer 两侧同判据）〔来源 §5.4〕

**写手侧**（修订面 = `write-tech-design/SKILL.md` Step 2 第 9 节「批准范围」的四字段说明，**原位加入**）：

1. `scope_in` 与 `zero_diff` 不得对**同一对象**同时要求「修改」与「不修改」；
2. 外部治理规则强制修改时，必须在 **SDD 阶段**把该对象纳入 `scope_in`、修订 `zero_diff`、或给出**已有**的合法出口；
3. 不得用 `scope_out` 隐藏当前交付**必须发生**的治理修改；
4. `follow_up` 不得承载当前 AC 的**必要条件**。

**reviewer 侧**（修订面 = `review-tech-design/SKILL.md` Step 2 的「批准范围前置」段，**原位加入相同判据**）：四字段自洽判据与写侧**逐条一致**（同一表述、同一四字段名）；发现以下任一情形 → **必须在 SDD 阶段形成 blocker**：`scope_in` 与 `zero_diff` 对同一对象自相矛盾；治理强制修改被藏进 `scope_out`；当前 AC 的必要条件被放进 `follow_up`。**不得**把这些留到 dev-plan 再由 `review-dev-plan` 的 `upstream-design-blocker` 轨触发。

约束：不新增第五个字段、不新增独立 ledger 文件、不新增状态、不新增评审维度名（FR-5 的判据属于既有「批准范围前置」与「PRD↔SDD 对齐」面，不另造维度）；判据只针对四字段之间的**自相矛盾与必需条件错位**，不针对详尽程度（§1.5 第 6 条）。

### FR-6 同 CR 测试断言与门禁基线同步〔来源 §5.1.1 末段、§5.5〕

1. **目标用例原位改写**：`skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 的用例 **`CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确`**（§1.4 事实 9）：
   - 该用例内**两组 term 原位改写**为 `dep-N` 口径：写侧 term 组覆盖「小节名 + `dep-N` 固定结构 + 五字段名」（现为 8 项，含 `### 既有实现依赖与事实` / `正文首次出现顺序` / 四字段名 + `依赖结论:` / `sdd.explicit_existing_dependencies`）；评侧 term 组覆盖「显式小节 + 有序清单 + `dep-N` 引用规则 + `commit SHA` 必填 + `sdd.explicit_existing_dependencies` + 正文漏列」。
   - **不另写第二个反向用例**；用例名保持（便于定位）；该文件的**顶层用例数不得减少**（当前 36 条，§1.4 事实 16）。
2. **`manifest.cases` 同步**：实施后 `skills/shared/crctl/scripts/test/gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]` 必须与 `pipeline-structure.test.mjs` 的**实际顶层用例数一致**（当前登记 35 / 实测 36，§1.5 第 2 条；本 CR 原位改写预期不改变用例数，若实施后仍为 36 而登记值仍为 35，则同 CR 把登记值同步为 36）。
3. **门禁全绿且零例外**：`suite-gate --run` 全量绿；`gate-registry.json#exceptions` 保持**空**（**不得签任何新例外**，CR-S 后全量测试是真门禁）。
4. **不改门禁机制**：不改 `suite-gate.mjs` 的判据语义（`cases < 登记值` 即红）、不新增门禁脚本、不新增 CI step、不新增 lint 规则。
5. **回归面**：CI 六个 step（lint-prompts enforce / skill matrix / agents contract / pipeline JSON 结构断言 / suite-gate --run / writeback 单测，§1.4 事实 14）全绿；`contract-scan` 的 `RETIRED_RECOVERY` 整树零命中（§1.4 事实 15）。

### FR-7 边界与零新增〔来源 §2、§5.5〕

1. **只原位改既有 Step 2.x 判据与 SDD 写作合同**：与 CR-2026-066 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账、Step 6 摘要**零 diff**（不重写、不放宽、不新增反向 token 命中）。
2. **不重编号 Step**：`review-tech-design` 的 Step 1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6 与 `write-tech-design` 的 Step 1 / 2 / 2.5 / 2.6 / 3 / 4 / 5 全部保持编号不变。
3. **不碰 crctl 事务层**：`skills/shared/crctl/scripts/crctl.mjs`、`scripts/lib/**`、`gates.json`、状态机声明、`rules.json` 零 diff；不新增/删除子命令、flag、错误码。
4. **不新增 annotation dimension / 账本字段 / 评审指标 / Pipeline 节点**：不改 `pipeline-templates/**`、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、traceability / review-loop / backlog 的字段集；不新增观测指标（SLO / 计数门禁 / 评审轮数承诺）。
5. **面不重叠（与 CR-P2 的边界）**：plan/TASK 写作合同（`skills/develop/write-dev-plan/SKILL.md`、`write-dev-tasks/SKILL.md`、`review-dev-plan/SKILL.md`）、upstream 增量回修、TASK 依赖闭包、证据命令证明力、环境责任与 readiness、`code-implementation.pipeline.json` 的 dev-start 提示全部归 CR-P2（来源 §6），本 CR **零 diff**。
6. **不复活旧字段名**：不引入 `recoverCommand` / `recover_command`（`contract-scan` 退役名单整树零命中）；结构化 `recovery` 合同（CR-2026-064）不变。
7. **不新增 Skill 契约面**：两份 SKILL 的参数表、落盘路径、允许的状态转换、失败码、与 `crctl` 的唯一写入边界不变（§1.3.3）。

## 4. 非功能需求

- **NFR-1 兼容性与门禁（最重要）**：`../tools` 全量既有测试与 CI（§1.4 事实 14 的六个 step，Ubuntu + Windows）保持绿；本 CR **不得签任何新例外**，`gate-registry.json#exceptions` 保持空。两份 SKILL 的状态转换、参数、落盘路径与错误码**零变化**。
- **NFR-2 零新增**：不新增 Pipeline 节点、评审维度名、账本字段、观测指标、crctl 子命令 / flag / 错误码、Skill 参数、落盘文件、lint 规则、CI step。
- **NFR-3 原位与单一事实源**：所有修订发生在**既有段落内部**；不得出现「新旧两套判据并存」的形态（尤其：`dep-N` 表与旧编号列表不得同时作为判据；批准范围自洽判据不得在写侧与评侧各自表述成不同强度；首轮全量判据不得在 SKILL 之外再存一份）。
- **NFR-4 判据可机械核对**：新增/改写的判据必须能被既有文本断言覆盖（AC-1~AC-6）；**不得**把不可判定表述（如「足够详细」「合理范围」）写成判据；同时不得把评审判断降级为「只要字面出现某词即通过」——判定责任仍在 reviewer（FR-2 第 6 条）。
- **NFR-5 行尾纪律（工作区纪律 #1）**：本 CR 触及跨行文本断言与 `\r\n` 归一化的测试读取（`readFileSync(...).replaceAll('\r\n','\n')`），读写前必须归一；断言/解析失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」。测试文件与 SKILL 文件必须保持 LF 检出内容一致（`gate-registry` 与 `suite-gate` 均按 LF 读取）。
- **NFR-6 语言纪律**：`../tools` 文档与 SKILL 正文用中文，代码与测试断言内注释按既有文件语言；本 CR 对 `../multica` 零 diff，不涉及英文注释规则。
- **NFR-7 可回退**：FR-1~FR-5 是 Prompt 判据的原位改动，FR-6 是同一 CR 内的断言同步——两者必须同批交付（否则 CI 红）；回退即同批还原，不产生半套合同。

## 5. 验收标准

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-1 | §5.5（写侧） | `write-tech-design/SKILL.md`：① `### 既有实现依赖与事实` 小节存在且采用 `dep-N` 固定结构（`dep-N` + `repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论` 五字段齐全）；② 正文规则含「只写设计依赖 `dep-N`、不得重述当前代码行为」与「实现事实只在该表定义一次」；③ `commit SHA` 为必填 40 位 SHA；④ 无法绑定字段的引用列入待核实依赖且不得作为方案前提；⑤ `N/A` 仅在正文与依赖表均无依赖时可用；⑥ 编号稳定口径（按正文首次出现顺序分配、只增不改）已写明。 |
| AC-2 | FR-2 | §5.5（评侧） | `review-tech-design/SKILL.md#Step 2.1`：① 含五要素核验；② 含「正文只能引用存在的 `dep-N`」；③ 含「正文出现未通过 `dep-N` 引用承载的当前实现事实 → blocker」；④ `commit SHA` **必填**，且「并可附 `commit SHA`」措辞零残留；⑤ 保留「不扫描全仓 / 不猜测未写出的依赖」边界并写明「Prompt 合同、不宣称 NLP 机械识别」；⑥ Step 编号未变（Step 1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6 全部存在）；⑦ 本 CR 新增文字不含 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`。 |
| AC-3 | FR-3 | §5.5（零改动核对） | ① `review-tech-design/SKILL.md#Step 2.2` 的首轮全量句**逐字**存在（「首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束；合并同根因问题、拆分不同根因问题」）；② `tools/agents/quality-reviewer-agent.md` 相对基线**零 diff**（`##` 小节集合仍为 7 个、无新增小节、无判据副本）；③ 交付物中不存在「首轮漏检」账本计数、「`本轮新增：` 作为流程质量统计」、「评审轮数数字承诺」。 |
| AC-4 | FR-4 | §5.5（状态链） | `write-tech-design/SKILL.md` 回修模式段含四项判据：① 状态判定 / 活动性 / 事件顺序 / 空值 / 失败回流类 blocker → 重证该状态链的完整输入维度、分支、可见动作与对应 AC；② 不得只修被点名的一格；③ 同一标识符 / 锚点 / testid 全文只有一个裁决；④ 未受该根因影响的已确认方案不得重写。 |
| AC-5 | FR-5 | §5.5（范围自洽） | ① **两侧**（`write-tech-design` 批准范围四字段说明 + `review-tech-design` 批准范围前置段）均含四条同判据（`scope_in`↔`zero_diff` 不得对同一对象自相矛盾；治理强制修改必须纳入 `scope_in` / 修订 `zero_diff` / 给出已有出口；不得用 `scope_out` 隐藏必须发生的治理修改；`follow_up` 不得承载当前 AC 必要条件），且表述与字段名一致；② 评侧要求冲突在 **SDD 阶段**形成 blocker、不留到 dev-plan upstream；③ 无第五字段、无新账本文件、无新评审维度名、无新状态。 |
| AC-6 | FR-6 | §5.1.1 末段、§5.5 | ① `pipeline-structure.test.mjs` 的 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确` 用例仍在，且其写侧/评侧 term 组已原位改写为 `dep-N` 口径（写侧覆盖小节名 + `dep-N` 固定结构 + 五字段；评侧覆盖显式小节 + 有序清单 + `dep-N` 引用规则 + `commit SHA` 必填）；② 该文件**顶层用例数不减少**（基线 36），**无**第二个反向用例；③ `gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]` 与该文件实际顶层用例数一致；④ `suite-gate.mjs --run` 全量绿、`gate-registry.json#exceptions` 为空数组（未签新例外）；⑤ `contract-scan` 的 `RETIRED_RECOVERY` 整树零命中。 |
| AC-7 | FR-7 | §5.5（零新增） | ① 交付 diff 只含 §1.3.1 表内文件（`write-tech-design/SKILL.md`、`review-tech-design/SKILL.md`、`pipeline-structure.test.mjs`，以及条件性的 `gate-registry.json`）；② `skills/shared/crctl/scripts/{crctl.mjs,lib/**}`、`gates.json`、`pipeline-templates/**`、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`tools/agents/**`、`../multica/**` 零 diff；③ 无新 annotation dimension / 账本字段 / 评审指标 / Pipeline 节点 / crctl 子命令 / flag / 错误码 / Skill 参数 / 落盘文件。 |
| AC-8 | FR-1、FR-2、FR-4、FR-7 | §5.5（CR-P3 面零 diff） | CR-2026-066 的既有断言在实施后**仍全绿且未被放宽**：四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账四要素（`phase` / `batchId` / `repositories[]` / `metadataCommit`）逐字保留；四 SKILL 不含 `crctl checkpoint`、不含 `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`；四个 review SKILL 的 PASS 分支断言与权限面断言（`REVIEW_SKILLS` 四处载体）零改动。 |
| AC-9 | 全部（边界与串行） | §2、§8（**本 PRD 新增**） | ① **与 CR-P2 面零 diff**：`write-dev-plan` / `write-dev-tasks` / `review-dev-plan` 的 SKILL 与 `code-implementation.pipeline.json` 的 dev-start 提示在交付 diff 中不存在；② **不与其他 CR 并发**：实施与交付期间 `change-requests/_backlog.yml` 的在途条目只有本 CR，CR-2026-063/064/065/066 的 `crctl status` 均为 `archived`；③ **本 CR 只收紧判据、不放宽任何既有门禁**：`review-tech-design` 中不存在被删除或弱化的既有 blocker 判据（Step 2.1 的 AC 闭环伪码、Step 2.3 的分级边界与固定前缀句全部保留）。 |

来源 §5.5 的七条验收与上表一一对应（AC-1~AC-8 未合并判据，只按「行为面 / 证据面 / 零 diff 面」分组排列）；AC-9 是「把 §2 的 CR-P1 边界与 §8 的串行约束写成可检查约束」的落地判据（来源文档没有对应 AC）。

## 6. 成功指标

- SDD 正文重复定义既有实现事实的比例 = 0（正文只出现「设计依赖 `dep-N`」）。
- 正文引用未定义 `dep-N` 的比例 = 0；依赖表五字段（含 40 位 `commit SHA`）完整率 = 100%。
- 两侧 `commit SHA` 强制性一致率 = 100%（写侧必填 = 评侧必填）；评侧因 SHA 缺失而漏判的次数 = 0。
- 状态链类 blocker（状态判定 / 活动性 / 事件顺序 / 空值 / 失败回流）在**一轮**内完成整体重证的比例 = 100%；同根因被拆成多轮修补的次数 = 0。
- 批准范围四字段冲突在 **SDD 阶段**被评审判据拦下的比例 = 100%；因范围冲突触发 `review-dev-plan` 的 `upstream-design-blocker` 的次数 = 0。
- 本 CR 新增的 annotation dimension / 账本字段 / 观测指标 / Pipeline 节点 / crctl 子命令 / flag / 错误码 / Skill 参数 = 0。
- `pipeline-structure.test.mjs` 的顶层用例数（基线 36）= 不减少；`gate-registry.json#manifest.cases` 与该数不一致的条目数 = 0；`gate-registry.json#exceptions` 长度 = 0。
- 既有测试回归数 = 0；CI 新增例外数 = 0；CR-2026-066 的既有断言（clean 前置 / PASS 发布 / 对账 / 权限面）失败数 = 0。

## 7. 范围排除

**来源 §2 的 CR-P1 边界（逐条不做，判据见 AC-7 / AC-9）**

- **不重编号 Step**：`review-tech-design` 的 Step 1.0 / Step 5 / Step 6 与其余既有 Step 号一律保留（CR-2026-066 已占用；本 CR 只在既有 Step 2.1 与 Step 2 的既有段落内原位扩写）。
- **不碰 crctl 事务层**：不改 `crctl.mjs`、`scripts/lib/**`、状态机、`gates.json`、`rules.json`、`review-loop` / `traceability` / `_backlog` 字段集；不新增子命令、flag、错误码。
- **不新增结构承载**：不新增 annotation dimension、账本字段、评审指标（SLO / 计数门禁）、Pipeline 节点、Skill 参数、落盘文件、lint 规则、CI step。
- **不新增观测负担**：不为「首轮漏检」写账本计数；不用 `本轮新增：` 统计流程质量；不对评审轮数作数字承诺。
- **不在 Agent Prompt 造第二份判据**：`tools/agents/quality-reviewer-agent.md` 零 diff；不新建小节、不复制首轮全量判据、不把 `dep-N` 规则写进 Agent Prompt（唯一事实源 = review SKILL）。

**来源 §5 明确交出本 CR 的面**

- plan/TASK 写作合同（`write-dev-plan` / `write-dev-tasks` 的回修与 `crctl task init` 口径）、TASK 依赖闭包重算、证据命令可执行性与证明力、环境责任与即时 readiness、dev-start 提示改写 → **CR-P2**（来源 §6/§6.7）。
- 发布点前移与 checkpoint 委派收敛、四个 review SKILL 的 Step 1.0 clean 前置与 Step 5/6 PASS 发布/对账 → **CR-P3**（CR-2026-066，已归档）。
- 结构化 `recovery` 迁移与 `recoverCommand` 退役 → **CR-R**（CR-2026-064，已归档）；本 CR 不复活旧字段名。
- 测试基线去硬编码与 `suite-gate` 真门禁 → **CR-S**（CR-2026-065，已归档）；本 CR 不签例外、不改 `suite-gate.mjs` 语义。
- `review-requirement` / `review-dev-plan` / `review-code` 三个 review SKILL、`write-dev-*` 全部 SKILL、`skills/requirement/**` → 本 CR 零 diff。

**本次明确不碰的既有资产**

- 本 CR **不要求** reviewer 做全仓扫描、不要求作者猜测未写出的依赖、不宣称对自由文本事实的机械识别——「正文事实是否被 `dep-N` 承载」仍是评审判断。
- 本 CR **不删** `write-tech-design/SKILL.md` Step 1 现存的 `crctl checkpoint` 提交口径句（删除它属独立的发布口径变更，不在来源 §5 授权面内，见 §1.5 第 5 条）。
- CR 状态机、`gates.json`、`rules.json`（controlled-shell 白名单）、CAS 与 durable ledger transaction 框架、`ENVIRONMENT_MISMATCH`、版本化 `cmd-NN` 与 test evidence、`reviewLoop` / `replayNodes` / `maxAttempts`。
- KB 的 `specs/`、`delivery/`；`../multica` 的 `CUSTOM.md`、`cr-prompts-revised/**`、`aifirst/**` 与任何 Go/TS 代码。

**顺序与并发约束（可检查形式见 AC-9）**

- 顺序：CR-P0(063) → CR-R(064) → CR-S(065) → CR-P3(066) → **本 CR(067)** → CR-P2；本 CR 不得早于 CR-P3 执行，也不与 CR-P2 并发（tools 单写者）。
- 任一 CR 失败只回滚本 CR；不得为了保持后续 CR 而保留半套新旧合同。

## CR-P2：plan/TASK 返工成本与执行前提（v0.41 · CR-2026-068）

## 1. 概述

### 1.1 问题陈述

需求来源是 Issue AIFI-31 附件《AIFI-18_SDD到planTASK_原位修订方案.md》（33,478 B，附件 id `01a0a47b-3088-760a-b307-bcf076426c31`）第 6 节「CR-P2：plan/TASK 返工成本与执行前提」（含 §6.1–§6.7 与边界段落；KB 内同文路径 `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md`，与附件逐字节一致，已 cmp 核实，见 §1.4 事实 21）。基线：tools main 已合并 CR-2026-063(CR-P0) / 064(CR-R) / 065(CR-S) / 066(CR-P3) / 067(CR-P1)，全部 `archived`。该节钉出四类问题，全部是**合同缺可判定承载体**，不是「执行不认真」：

1. **upstream 返工把增量当整轮**：`write-dev-plan/SKILL.md#Step 2a` 回修模式只定义普通轨（逐条消费 review-dev-plan canonical blockers）；upstream SDD 重新批准后（`review-dev-plan:upstream-design-blocker` → 人工修订 → 重新评审与审批 → pipeline 重放 `write-dev-plan→write-dev-tasks→review-dev-plan`），没有任何文字定义「以新旧批准 SDD 的变更 delta 为输入的增量回修」——coordinator 只能把现有 plan/TASK 当作整轮作废并全量重建（来源 §6.1「原文问题」）。这是 AIFI-18 实测中返工成本被放大的第一形态。
2. **TASK 层现行文字与增量语义直接矛盾**：`write-dev-tasks/SKILL.md#Step 2a` 现写作「逐条消费 blockers，**重新生成** TASK 卡并调用 `crctl task init` 刷新 `_index.yml`；不保留已被评审判废/删除的旧 TASK」（§1.4 事实 6）——即使 plan 只做 delta 修订，TASK 层仍被要求全量重建；同时「只修 plan、让旧 TASK 留给下一轮评审发现」的形态也无人禁止（来源 §6.2「必须原位改写的相反现行文字」）。
3. **证据命令的观测面缺可判据**：`write-dev-plan` 两张稳定表说明只有一条概括性反假绿句（「该命令必须实际覆盖本行所声称的验收面，不得只覆盖其中一部分造成假绿」，§1.4 事实 4），没有可判定口径——`--list` 不能证明浏览器行为、文件级 `--name-only` 不能证明符号级不变量、子集测试不能声称全量、涉 Git 命令应走受控入口；`review-dev-plan` 的 `acceptance-verifiability` 增量维度只写「核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路」（§1.4 事实 9），「观测面窄于声称面」「命令形态越受控边界」均无 blocker 判定——假绿命令与越界命令被留到 implement 阶段才暴露（来源 §6.3）。
4. **环境前提缺位、动态健康被写成人工长期事实**：plan 的「验收与发布策略」章节说明只有「发布前 checklist / feature-flag 计划」（§1.4 事实 2），没有环境 owner、建立方式、可获得性、readiness 证据与缺失处置；dev-start 人工审批提示（`code-implementation.pipeline.json` 节点 `…0004`）只确认任务拆分完成（§1.4 事实 12）；`implement-code` 环境节写「任务开始时只做一次有界前提检查」（§1.4 事实 18），没有「在第一个依赖环境的 TASK 前执行 plan 指定的 readiness `cmd-NN`」的即时性约束。结果：环境缺位要么在 implement 深处才以 `ENVIRONMENT_MISMATCH` 暴露，要么被错误地要求在人工审批时全部在线——把动态健康状态写成人工长期事实（来源 §6.5）。

**根因结论（来源 §6 与 §7，本 PRD 采纳）**：四项的共同根因是 plan/TASK 写作合同缺三个可判定承载体——**delta 语义**（upstream 增量回修 + TASK 依赖闭包重算）、**观测面判据**（证据命令证明力）、**环境前提的静态声明 + 即时验证**（plan 声明 / dev-start 静态确认 / implement 即时 readiness）。crctl 状态机、reviewLoop、两张稳定表双向唯一映射、`ENVIRONMENT_MISMATCH`、结构化 `recovery`、`suite-gate` 真门禁等基础设施全部已就位（来源 §7「继续复用、不再造」）。因此本 CR 的全部杠杆是**原位改四份 Skill 的既有段落 + 一处 pipeline 人工审批提示文本**，零新增结构承载（§6.6/§6.7）。

### 1.2 解决方案摘要

按来源 §6.1–§6.5 逐条落地（每组锚定「仓 + 文件 + 既有段落」，见 §1.3.1 与 §3 各 FR）：

1. **upstream 后 plan 增量回修**（FR-1）：`write-dev-plan/SKILL.md#Step 2a` 原位扩写——普通轨语义保留；新增 upstream 轨：upstream SDD 重新批准后，以**新旧批准 SDD 的变更 delta** 与**同轮未闭合 plan blockers** 为输入，在**同一份 plan** 上只重算受影响章节、稳定表行、证据与回滚，未受影响内容保留；coordinator 只传 subject / delta / canonical feedback 引用，不指定具体行如何修改。不改 review-route 枚举、不把 repair-target 改成多值。
2. **TASK 及依赖闭包重算**（FR-2）：`write-dev-tasks/SKILL.md#Step 2a` 的「重新生成」段**在该段内原位改写**为 delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留，`crctl task init` 只用于刷新 `_index.yml` 索引；节点层零改动（12 节点、`…0001→…0002` 顺序、replayNodes 条目全保持；`purpose: regenerate-tasks` 是标签，其 delta 重算语义只在 SKILL 正文内明确）。
3. **证据命令的可执行性与证明力**（FR-3）：`write-dev-plan` 两张稳定表说明原位加入观测面判据（每个 `cmd-NN` 必须能观测该表行声称的 AC 结果；`--list` 不能证明浏览器行为；文件级 `--name-only` 不能证明符号级不变量；子集测试不能声称全量；涉 Git 命令用 `rules.json` 已允许的受控入口；不再通过委派评论补写命令算法）；`review-dev-plan` 既有 `acceptance-verifiability` 维度原位加入同一判据：观测面窄于声称面即 blocker、命令形态越受控边界即 blocker。
4. **回滚单元是依赖闭包**（FR-4）：`write-dev-plan` 交付覆盖表既有 `回滚` bullet 原位明确：被其它 TASK 消费的共享改动，其回滚单元必须包含受影响下游消费者并与风险节逆拓扑顺序一致；单点 revert 会破坏下游时不得声明为单点回滚。
5. **环境责任与即时 readiness**（FR-5，三侧）：plan 侧在既有「验收与发布策略」章节项（不新增第八节）原位扩写——证据依赖常驻服务/浏览器/数据库时必须写明环境 owner、建立方式、可获得性、readiness 证据（**必须复用该环境所保障的那一行 FR 的既有 `cmd-NN`**，不破坏两张稳定表双向唯一映射；确实无法复用时另立 CR，本 CR 不放宽该映射）与缺失时 `ENVIRONMENT_MISMATCH` 处置引用；dev-start 侧把 `code-implementation.pipeline.json` 节点 `…0004` 既有 approvalPrompt 原位改为只确认 owner、建立方式和可获得性（静态前提），不要求审批时所有服务在线；implement 侧在 `implement-code/SKILL.md` 既有环境节原位加入：在第一个依赖环境的 TASK 前执行 plan 指定的 readiness `cmd-NN`，失败按既有 `ENVIRONMENT_MISMATCH` 中止并报告建立动作，环境无关 TASK 不被提前阻断。
6. **零新增边界**（FR-6）：不新增 Pipeline 环境节点（节点数保持 5/4/12）、不改 review-route 枚举与 replayNodes、不改 upstream attempts 账本（来源 §6.6：不把 upstream block 追加到 `attempts[]`、不新增 review-events、不改 traceability schema、不做聚合指标）、不新增账本字段/评审维度/观测指标；`suite-gate --run` 全量绿、`gate-registry.json#manifest.cases` 与实际一致、零新例外。

### 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

降低 upstream 返工成本并提前声明执行前提：upstream SDD 重新批准后 write-dev-plan 以新旧 SDD delta 与同轮未闭合 plan blockers 为输入，在同一份 plan 上只重算受影响章节、稳定表行、证据与回滚（未受影响内容保留）；write-dev-tasks 的『重新生成』原位改写为 delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留；证据命令必须可执行且观测面覆盖 AC 声称面；回滚单元必须包含受影响下游依赖闭包；plan 侧声明环境 owner、建立方式、可获得性与 readiness（复用既有 cmd-NN，不破坏两张稳定表双向唯一映射），dev-start 只确认静态前提，implement 侧在首个环境依赖 TASK 前执行即时 readiness。不新增 Pipeline 环境节点（节点数保持 5/4/12）、不改 review-route 枚举与 replayNodes、不改 upstream attempts 账本、不新增账本字段、评审维度或观测指标。

#### 1.3.1 scope_in 边界（原文前缀，评审核对用）

> CR-P2 只动 Step 2.x 评审判据与 plan/TASK 写作合同：upstream 增量回修、TASK 依赖闭包重算、证据证明力、环境责任与即时 preflight；明确不负责新 Pipeline 环境节点、动态环境人工门禁、评审观测指标。

（该边界来自来源 §2 的 CR-P2 行与 §6 边界段落；与已归档 CR 的块级不重叠约束见 FR-6 与 AC-8。）

逐条落到「哪个仓的哪个文件、改哪一段」（基线行号与证据见 §1.4）：

| # | 仓 | 文件 | 修订类型（原位） |
|---|---|---|---|
| 1 | `../tools` | `skills/develop/write-dev-plan/SKILL.md` | Step 2a 原位扩写 upstream delta 回修轨；两张稳定表说明加观测面判据；交付覆盖表 `回滚` bullet 加依赖闭包判据；「验收与发布策略」章节项（plan.md 第 5 章说明）加环境责任声明五要素（不新增第八节） |
| 2 | `../tools` | `skills/develop/write-dev-tasks/SKILL.md` | Step 2a 第 1 条的「重新生成」段原位改写为 delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留（`crctl task init` 只用于刷新索引） |
| 3 | `../tools` | `skills/develop/review-dev-plan/SKILL.md` | 既有 `acceptance-verifiability` 增量维度原位加入观测面 / 受控边界 blocker 判据 |
| 4 | `../tools` | `pipeline-templates/code-implementation.pipeline.json` | 节点 `…0004`（确认进入代码开发）approvalPrompt 原位改写：加环境静态前提确认（owner / 建立方式 / 可获得性），保留结构化决定，不含 `git` / `journal` / `review-annotations` / `reject_reason` |
| 5 | `../tools` | `skills/develop/implement-code/SKILL.md` | 既有「环境验证与 ENVIRONMENT_MISMATCH」节原位加入：首个环境依赖 TASK 前执行 plan 指定 readiness `cmd-NN`、失败按既有标签中止、环境无关 TASK 不提前阻断 |

**本 CR 明确零 diff 的面**（评审核对清单）：`skills/shared/crctl/scripts/**`（含全部测试与 `gate-registry.json`——本 CR 预期零测试改动，见 §1.5 第 2 条）；`skills/develop/{write-tech-design,review-tech-design,review-code,write-test-report,coding-discipline}/SKILL.md`；`pipeline-templates/**` 中除 `…0004` approvalPrompt 文本外的全部内容（节点集、节点数、reviewLoop、其余 prompt）；`tools/agents/**`；`agent-skill-matrix.yml`；`../multica/**`（零 diff）；KB 的 `specs/`、`delivery/`、`docs/`（`docs/analysis/` 来源文档只读）。

#### 1.3.2 目标仓库与版本

- 代码实施在 `../tools/`（四份 Skill 正文 + 一份 pipeline JSON 的 approvalPrompt 文本）。
- knowledge-base 承载本 PRD 与评审产物；本 CR 不改 KB 的 `specs/`、`delivery/`、`docs/`。
- `../multica/` 本 CR 零 diff（不改任何 Agent Prompt 部署副本、不改 Go/TS 代码）。
- `target-version` 继承 `cr.md` 的 `0.41`（注册阶段人工确定「版本在当前基础上顺延」，现行最新 CR-2026-067 = `0.40`；`crctl version-set` 之外无改写入口）；`target-spec-id` = `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

#### 1.3.3 契约说明（确定性四查适用面）

本 CR **不新增、不修改任何用户可调用契约**，四查（幂等 / 权限 / 错误闭包 / 副作用）对本 CR **N/A**，理由逐条：

- **无 HTTP API**：本 CR 不改任何 endpoint / request / response。
- **无 crctl CLI 契约变更**：`skills/shared/crctl/scripts/**` 零 diff——不新增/删除子命令与 flag，不改任何 JSON 输出形状、退出码、错误码、调用者约束。
- **无 Skill 契约变更**：五份目标文件涉及的 Skill（write-dev-plan / write-dev-tasks / review-dev-plan / implement-code）的**必填参数、落盘路径、允许的状态转换、失败码、与 `crctl` 的唯一写入边界全部不变**（§1.4 事实 6–10、18）。本 CR 改的是 SKILL **正文内的 Prompt 判据**与 pipeline **人工审批提示文本**：回修的 delta 语义、依赖闭包重算、观测面判据、回滚单元判据、环境责任声明、dev-start 静态确认内容、implement 侧 readiness 即时性。这些是**写作与评审判据**，不是调用契约；它们的验收以「文本合同 + 既有测试断言仍绿」形式给出（AC-1~AC-9）。
- **唯一语义强度变化**：`review-dev-plan` 的 `acceptance-verifiability` 判据收紧（观测面窄于声称面 → blocker；命令形态越受控边界 → blocker），会让原本可通过的 plan 在**新口径**下形成 blocker。该变化不改变任何 crctl 状态转换或错误码，只改变 `review-dev-plan` 的 blocker 判定输入；对既有已归档 CR 无追溯效力（评审判据只对评审发生时的 SKILL 版本生效）。

### 1.4 当前事实（落笔前核实）

基线（`crctl register` ensure 的 requirement worktree HEAD）：

| 仓 | worktree HEAD |
|---|---|
| `ai-first-platform-docs`（本 KB） | `f05e71d7abf696379c8454ac8e34d82267e4e56d`（register 提交 = KB trunk HEAD） |
| `../tools` | `49fa37748d9b2fc7fc58fd53f839e2ed293bde17`（= tools `main`） |
| `../multica` | `d4a49e2b9`（requirement/CR-2026-068 分支基线） |

以下结论均在上述 SHA 上核实（路径相对各自仓根）：

| # | 结论 | 证据 |
|---|---|---|
| 1 | `write-dev-plan/SKILL.md` 现共 Step 1 / Step 2 / **Step 2a** / Step 3 / Step 4 五个编号节；Step 2a「回修模式（CR-2026-026 FR-8/FR-9）」只有普通轨三条：① 逐条消费 blockers、只处理评审指出的问题不扩散 SDD 范围；② 禁止只刷新评审证据而不修改被指出的产物；③ 回修期间允许 status=`tech-design-reviewed`。**无**任何 upstream delta 回修文字 | `skills/develop/write-dev-plan/SKILL.md` L86–93（TOC 与正文实读） |
| 2 | Step 2 的 plan.md 章节列表共 **7 章**：交付里程碑 / 任务依赖图 / 资源与分工 / 风险与回滚策略 / **验收与发布策略**（现说明仅「发布前 checklist / feature-flag 计划」）/ 两张稳定表（CR-2026-060 AC-07）/ AC 业务闭环覆盖矩阵（CR-2026-057 FR-8）。**无**环境 owner / 建立方式 / 可获得性 / readiness / `ENVIRONMENT_MISMATCH` 处置文字，**无第八节** | 同文件 L57–66 |
| 3 | 交付覆盖表（稳定表 1/2）5 列固定（`FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`）；`回滚` bullet 现文「该 FR 的回滚单元（如 revert 某 TASK commit）」——**无**依赖闭包 / 下游消费者 / 逆拓扑判据 | 同文件 L67–85 |
| 4 | 交付覆盖表 `验收证据` bullet 已有概括性反假绿句「该命令必须实际覆盖本行所声称的验收面，不得只覆盖其中一部分造成假绿」；证据命令表（稳定表 2/2）bullets：`证据ID`=`cmd-NN`（两位十进制）、`args` 为 JSON token 数组、`executable` 直接可 spawn、`cwd` 相对路径、`timeout` 秒。**无** `--list`≠浏览器 / `--name-only`≠符号不变量 / 子集≠全量 / Git 受控入口 / 命令算法不经委派评论的可判定口径 | 同文件 L73–91 |
| 5 | `write-dev-tasks/SKILL.md` 现共 Step 1 / Step 2 / **Step 2a** / Step 3 / Step 4 / Step 5 / Step 6 编号节 + 注意事项；Step 2a 第 1 条逐字为「逐条消费 blockers（每条内含可执行修复说明），**重新生成** TASK 卡并调用 `crctl task init` 刷新 `_index.yml`；不保留已被评审判废/删除的旧 TASK」——与 delta 语义直接矛盾（来源 §6.2 点名的相反现行文字） | `skills/develop/write-dev-tasks/SKILL.md` L46–53 |
| 6 | `write-dev-tasks/SKILL.md` L115「`tasks/_index.yml` 是受控账本，禁止 Agent/Skill 手写」与 `crctl task init` 指引并存（crctl.test.mjs CR-2026-037 用例两条 match 断言的载体）；TASK 卡结构 = frontmatter（id / type / cr-ref / plan-ref / sdd-ref / target-version / title / slug / status / estimate / **depends-on** / created）+ 正文 6 节（任务描述 / 涉及文件 / 实现要点 / 验收条件 / 完成标志 / 接口契约——消费/产出签名逐字对齐 SDD） | 同文件 L54–93、L115；`skills/shared/crctl/scripts/test/crctl.test.mjs` L1338–1349 |
| 7 | `review-dev-plan/SKILL.md` 的 `acceptance-verifiability` 增量维度（「增量职责与事实核验（CR-2026-055）」节四个增量维度之一）现文「核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路」——**无**「观测面窄于声称面即 blocker」「命令形态越受控边界即 blocker」判据 | `skills/develop/review-dev-plan/SKILL.md` L75–85 |
| 8 | `review-dev-plan` Step 2「八类维度评审」表含「验收可验证性」行（每个 TASK ≥2 条可执行验收步骤，总体覆盖 SDD 验收面）；该表与四个增量维度名均为既有枚举，本 CR 不新增维度名 | 同文件 L53–93 |
| 9 | `review-dev-plan` Step 4 双轨：**NORMAL**（repair-target=write-dev-plan 缺省 → `advance tech-design-reviewed`，pipeline 按 write-dev-plan → write-dev-tasks → review-dev-plan 重放 ≤3 轮）；**UPSTREAM**（repair-target=write-tech-design → `advance tech-design-review-pending`，停止自动重放，输出 `UPSTREAM_DESIGN_BLOCKER`，由人工走既有技术设计修订、重新评审与审批流程）——upstream 后的重放入口与顺序已存在，缺的是增量回修的写作合同 | 同文件 L141–148 |
| 10 | `code-implementation.pipeline.json` 共 **12 节点**；顺序 `…0001 write-dev-plan → …0002 write-dev-tasks → …0014 review-dev-plan → …0004 human_approval（确认进入代码开发）→ …0005 approve-dev-start → …`；`…0014 reviewLoop`：maxAttempts=3、replayNodes = [write-dev-plan(`repair-plan`), write-dev-tasks(`regenerate-tasks`), review-dev-plan(`rerun-current-review`)]——「两个 authoring 节点 + 复审」已含 | `pipeline-templates/code-implementation.pipeline.json` 实读（node 遍历 + reviewLoop JSON） |
| 11 | `…0004`（完整 id `00000000-0000-0000-0015-000000000004`，human_approval「确认进入代码开发」）approvalPrompt 现文只确认任务拆分完成：「✅ 通过：勾选此 Todo，下一节点 approve-dev-start 会记录确认并推进到 developing / ❌ 暂缓：补充任务拆分意见，重新执行 write-dev-tasks 后再确认」——**无**任何环境内容、无 `git` / `journal` / `review-annotations` / `reject_reason` | 同文件实读 |
| 12 | `pipeline-templates/_index.yml`：`code-implementation-v1 nodes: 12`（注释「CR-2026-066：删除 4 个 checkpoint 节点与 auto_push_after_task（16 -> 12）」）、`requirement-authoring-v1 nodes: 5`、`architecture-design-v1 nodes: 4` | `_index.yml` L53–58 与 `pipeline-structure.test.mjs` AC-1（L35） |
| 13 | `pipeline-structure.test.mjs` 现有约束：CR-2026-043 用例断言**全部 12 节点的 prompt+approvalPrompt 无 `git` / `journal` 字样**；human_approval 判据（requirement `…0005` / architecture `…0003` / code `…0010`）无 `review-annotations` 路径、无 `reject_reason` 引导、保留 approve/reject 结构化决定；AC-1 断言节点数 5/4/12 ≡ `_index.yml`；`…0014 < …0004 < …0005` 顺序断言 | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` L35、L113–125、L160–171、L385–386 |
| 14 | `crctl.test.mjs` CR-2026-037 用例：`write-dev-tasks/SKILL.md` 必含 `/crctl task init/` 与 `/禁止 Agent\/Skill 手写/`、**不得含** `/重新生成.*TASK 与 \`_index\.yml\`/`（doesNotMatch 型）；pipeline 节点 prompt 对受治理账本写指令零命中；pipeline 节点数 ≡ `_index.yml` 登记值。另有 CR-2026-029 用例：write-dev-tasks 与 code-implementation pipeline 不得含「发布…联调 / 联调…TASK / 发布类任务拆分」 | `skills/shared/crctl/scripts/test/crctl.test.mjs` L1338–1358、L3918–3925 |
| 15 | `gate-registry.json`：`manifest.cases["pipeline-structure.test.mjs"] = 36` = 该文件实际顶层用例数 36（`grep -c '^test('` 实测）；`exceptions: []`；`suite-gate` 判据为 `cases < 登记值` 即红 | `test/gate-registry.json` 实读 + 实测 |
| 16 | `contract-scan.test.mjs` AC-1 扫描面 = 3 个 pipeline JSON + 11 个 SKILL.md（含本 CR 4 个目标 SKILL 与 code-implementation pipeline）对废弃 canonical 字段零命中；`RETIRED_RECOVERY`（`recoverCommand` / `recover_command`）整树零命中 | `skills/shared/crctl/scripts/test/contract-scan.test.mjs` L30–52、L418 |
| 17 | `implement-code/SKILL.md`「环境验证与 ENVIRONMENT_MISMATCH」节（该 Skill 是有界验证与 `ENVIRONMENT_MISMATCH` 的**唯一详细事实源**，其余文档只链接不复述）现有 bullets：一次环境检查（任务开始时只做一次有界前提检查，不反复探测）/ 最多一次重跑 / 遵守测试计划 timeout 与既有测试入口、不创建脱离验证步骤存活的后台进程 / `ENVIRONMENT_MISMATCH` 稳定技术失败标签（不写 crctl 状态、gate、账本、评审 blocker、测试证据 schema；由既有 Pipeline `onFail=abort` 中止）/ 临时隔离实例例外 / 受控建立时归因于当前变更的失败按普通代码失败。**无** readiness `cmd-NN` 即时性文字、无「环境无关 TASK 不被提前阻断」判据 | `skills/develop/implement-code/SKILL.md` L102–111 |
| 18 | `review-dev-plan/SKILL.md` 的 `push-progress` 命中 2 处，均在 Step 5「PASS 发布与对账」（CR-2026-066 合法发布面）；`crctl checkpoint` 命中 0 处；Step 1.0 只读 clean 前置（CR-2026-066 FR-2）与 Step 5/6 已被 CR-2026-066 占用，Step 编号不得重编 | `grep` 实测 + SKILL.md TOC（L33–177） |
| 19 | 串行约束当前成立：CR-2026-063 / 064 / 065 / 066 / 067 的 `crctl status` 均为 `archived`（067 = terminal，`next` = null）；`change-requests/_backlog.yml` 在途条目仅 CR-2026-068；本次 `crctl register` 返回 `cr_id = CR-2026-068`、`phase = complete`、`targetVersion = 0.41`、commit `f05e71d7`，三仓 worktree 已 ensure | `crctl status CR-2026-067`、`_backlog.yml`、register JSON 输出 |
| 20 | KB 内来源文档 `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md`（33,478 B）与 Issue AIFI-31 附件**逐字节一致**（`cmp` 通过）；来源 §6.2 所引「12 节点、`…0001→…0002` 顺序、replayNodes 含两个 authoring 节点」与盘上事实相符（事实 10） | `cmp` 实测 + §6.2 逐条核对 |
| 21 | 来源 §6.5 所引约束「节点 prompt/approvalPrompt 不得出现 `git` / `journal` 字样」确为现行测试断言（事实 13 CR-2026-043 用例，覆盖全部 12 节点含 `…0004`）；「两张稳定表双向唯一映射（CR-2026-060 AC-07）」确为 `review-dev-plan` 覆盖矩阵节既有机械核对判据 | `pipeline-structure.test.mjs` L113–125 + `review-dev-plan/SKILL.md` L86–92 |

### 1.5 对来源文档的事实更正与需人工确认的口径

1. **FR-3 写侧不是从零新增反假绿句**：交付覆盖表 `验收证据` bullet 已有概括性反假绿句（§1.4 事实 4）。本 CR 的加入是**具体化可判定口径**（观测面公式与四类典型错配 + 受控入口 + 命令算法唯一事实源），与来源 §6.3「原位加入」一致；既有概括句保留，不在旁边另立第二句概括。
2. **本 CR 预期零测试改动（与 CR-2026-067 的用例同步义务不同）**：改动面唯一触及的既有字样断言是 crctl.test.mjs CR-2026-037 用例的 **doesNotMatch** 型 `/重新生成.*TASK 与 \`_index\.yml\`/`（§1.4 事实 14）——「重新生成」措辞删除后该断言天然仍绿；`…0004` approvalPrompt 现文本无任何既有 match 型断言（§1.4 事实 13 的 git/journal 断言是保持性反向断言）。`gate-registry.json#manifest.cases = 36` 已与实际一致（CR-2026-067 已同步），本 CR 不新增用例、预期 36 保持；若实施中用例数意外变化，同 CR 同步登记值，不签任何例外。
3. **`…0004` approvalPrompt 的「原位改为」落点**：现文本不含任何环境内容（§1.4 事实 11），来源 §6.5 dev-start 侧的「原位改为只确认 owner、建立方式和可获得性」= 在既有任务拆分确认文本上**扩写环境静态前提**（保留拆分完成确认的语境），不是删除拆分确认；现文本决定形态是「✅ 通过 / ❌ 暂缓」两分支，重写保留两分支结构化决定（approve/reject 结构化决定的现行载体形态）。需人工一并确认。
4. **`ENVIRONMENT_MISMATCH` 的单一事实源纪律**：`implement-code/SKILL.md` 是该标签的唯一详细事实源（「其余文档只链接不复述」，§1.4 事实 17）。write-dev-plan 侧 FR-5 的新文字只**引用**标签名与处置入口，不得复述其完整语义（避免第二份事实源）；implement-code 侧新文字加在同一节内，与既有 bullets 同节共生、不改写它们。
5. **「一次环境检查」与 readiness `cmd-NN` 的关系钉定（来源未写明，本 PRD 钉定）**：「在第一个依赖环境的 TASK 前执行 plan 指定的 readiness `cmd-NN`」是既有「任务开始时只做一次有界前提检查」在环境依赖 TASK 上的**具体化执行内容**，不是新的反复探测；仍受「最多一次重跑」、测试计划 timeout 与受控入口约束。「环境无关 TASK 不被提前阻断」是新增的隔离判据。需人工一并确认。
6. **readiness 无法复用既有 `cmd-NN` 时**：来源已钉「确实无法复用时，该诉求超出本 CR 边界，另立 CR 修改稳定表合同与对应评审判据，本 CR 不放宽该映射」；本 PRD 落为 FR-5 第 4 条硬边界 + AC-6 第 2/3 项。评审按「不存在『为 readiness 单独申请新 `cmd-NN`』的形态文字」核对。
7. **`purpose: regenerate-tasks` 标签语义钉定**：标签文本不改（撞 CR-2026-066 的节点数与 `_index.yml` 断言面即 AC-7 fail）；其「delta 重算」语义只在 `write-dev-tasks/SKILL.md` 正文内明确（FR-2 第 2 条）。来源 §6.2 已写明，本 PRD 落为可检查约束。

### 1.6 修订记录

- 初稿（2026-09-15）：按来源附件 §6（含 §6.1–§6.7 与边界段落）与注册摘要（`cr.md` summary）起草；基线事实在 §1.4 三个 worktree HEAD 上逐条核实。FR 编号与来源 §6 小节一一对应（§6.1→FR-1、§6.2→FR-2、§6.3→FR-3、§6.4→FR-4、§6.5→FR-5、§2+§6.6+§6.7→FR-6）；AC-1~AC-8 对应来源 §6.7 十条验收（按行为面 / 证据面 / 零 diff 面分组，未合并判据），**AC-9 为本 PRD 新增**，把来源 §2 的 CR-P2 边界与 §8 的串行约束写成可检查约束。§1.5 记录三处需人工一并确认的钉定（第 3、5 条）、三处本 PRD 钉定（第 4、6、7 条）与两处事实核对（第 1、2 条）。

## 2. 用户故事

- **US-1 dev-plan 写手（`write-dev-plan` / dev-agent）**：作为写 plan 的人，我希望 upstream SDD 重新批准后在**同一份 plan** 上只重算受影响章节、稳定表行、证据与回滚，这样未受影响的已确认内容不被无理由重写，返工成本与 delta 成正比而不是与全文成正比。
- **US-2 dev-tasks 写手（`write-dev-tasks` / dev-agent）**：作为拆 TASK 的人，我希望回修语义是 delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留，这样受影响闭包的输入/输出/接口/命令/depends-on/完成标志/回滚被同步更新、不残留旧口径，而不是每轮全量重建 TASK 卡。
- **US-3 CR 协调者（coordinator）**：作为路由 upstream 回修的人，我希望只传 subject、delta、canonical feedback 引用而不指定具体行如何修改，这样我不会把增量回修升级成整轮作废的委派。
- **US-4 dev-plan 评审者（`review-dev-plan` / quality-reviewer-agent）**：作为核对证据命令的人，我希望「观测面窄于声称面」「命令形态越受控边界」是可判定的 blocker 判据，这样假绿命令与越界命令在 dev-plan 阶段就被拦下，不会漏到 implement 阶段才暴露。
- **US-5 人工审批者（Ray）**：作为批准进入代码开发的人，我希望 dev-start 审批只确认环境 owner、建立方式和可获得性这类**静态前提**，不用在审批时逐个确认服务在线，这样动态健康状态不会被写成人工长期事实、也不会被审批卡错误背书。
- **US-6 implement 执行者（`implement-code` / dev-agent）**：作为写代码的人，我希望在第一个依赖环境的 TASK 前执行 plan 指定的 readiness `cmd-NN`，失败按既有 `ENVIRONMENT_MISMATCH` 中止并报告建立动作，这样环境缺位在正确的位置、以正确的标签暴露，环境无关 TASK 不被提前阻断。
- **US-7 本 CR 的 reviewer**：作为本 CR 的评审者，我希望逐条核对「哪个仓的哪个文件、哪一段被原位改了、哪些面必须零 diff」，确认没有两套并存的回修规则、没有新的环境验证事实源、没有新节点 / 新账本字段 / 新观测指标。

## 3. 功能需求

### FR-1 upstream 后 plan 增量回修（`write-dev-plan`）〔来源 §6.1〕

修订面 = `skills/develop/write-dev-plan/SKILL.md` 的 **Step 2a「回修模式（CR-2026-026 FR-8/FR-9）」**——在该节内**原位扩写**（不新增小节、不重编号、保留出处标注）：

1. **普通轨语义逐字保留**：既有三条（逐条消费 blockers 只处理评审指出的问题不扩散 SDD 范围 / 禁止只刷新评审证据而不修改被指出的产物 / 回修期间允许 status=`tech-design-reviewed`）不动（§1.4 事实 1）。
2. **新增 upstream 轨判据（同在 Step 2a 内）**：
   - upstream SDD 重新批准后（`review-dev-plan:upstream-design-blocker` → 人工修订 → 重新评审与审批 → pipeline 按 replayNodes 重放，§1.4 事实 9/10），`write-dev-plan` 以**新旧批准 SDD 的变更 delta** 与**同轮未闭合 plan blockers** 为输入；
   - 在**同一份 plan** 上只重算受影响章节、稳定表行、证据与回滚；
   - 未受影响内容保留；
   - coordinator 只传 subject、delta、canonical feedback 引用，**不指定具体行如何修改**（委派合同遵守 CR-2026-063 已落地的公共 dev-agent 委派合同文字，不重述、不改写）。
3. **不改路由面**：不修改 review-route 枚举、不把 `repair-target` 改成多值；upstream 轨由既有 `review-dev-plan` Step 4 UPSTREAM 分支与状态机既有转换承载，本 CR 零状态机改动（FR-6）。

### FR-2 TASK 及依赖闭包重算（`write-dev-tasks`）〔来源 §6.2〕

修订面 = `skills/develop/write-dev-tasks/SKILL.md` 的 **Step 2a 第 1 条**——**在该段内原位改写**，不得在别处另写一段增量规则与它并存：

1. 现「逐条消费 blockers（每条内含可执行修复说明），**重新生成** TASK 卡并调用 `crctl task init` 刷新 `_index.yml`；不保留已被评审判废/删除的旧 TASK」改写为：
   - `write-dev-plan` 完成 SDD→plan delta 后，`write-dev-tasks` 必须继续执行 plan→TASK delta（`…0001 → …0002` 节点顺序承载，§1.4 事实 10）；
   - 重算**直接受影响 TASK 及其下游依赖闭包**（普通轨 blockers 指向的 TASK 与 upstream delta 波及的 TASK 都是「直接受影响」的来源）；
   - 同步更新受影响 TASK 的输入、输出、接口（接口契约节的消费/产出签名）、命令、`depends-on`、完成标志和回滚；
   - 未受影响 TASK 保留；
   - **`crctl task init` 只用于刷新 `_index.yml` 索引**（受控账本唯一初始化入口，既不手写也不承担重算语义；既有「禁止 Agent/Skill 手写」句保持，§1.4 事实 6）；
   - 禁止只修 plan、让旧 TASK 留给下一轮评审发现。
2. **节点层零改动**：`code-implementation.pipeline.json` 节点集（12）、`…0001 write-dev-plan → …0002 write-dev-tasks` 顺序、`…0014 reviewLoop.replayNodes` 条目全部保持；`purpose: regenerate-tasks` 是标签，本 CR 只在 `write-dev-tasks/SKILL.md` 正文内明确其语义为 delta 重算，**不改节点集、不改节点数（保持 5/4/12）、不改 replayNodes 条目**（以免撞 CR-2026-066 的节点数与 `_index.yml` 断言，§1.5 第 7 条）。
3. **文件内单一回修规则**：delta 重算规则与全量重建规则不得并存（「重新生成」措辞零残留；AC-2 第 3 项）；既有 doesNotMatch 断言（crctl.test.mjs CR-2026-037）删除措辞后天然仍绿（§1.5 第 2 条）。
4. Step 2a 第 2、3 条（禁空转 / 允许 `tech-design-reviewed` 重放态）保留。

### FR-3 证据命令的可执行性与证明力（写侧 + 评侧）〔来源 §6.3〕

**写侧**（`skills/develop/write-dev-plan/SKILL.md` 两张稳定表说明，原位加入；既有概括反假绿句保留，§1.5 第 1 条）：

1. 每个 `cmd-NN` 必须能观测该表行声称的 AC 结果（**观测面 ≥ 声称面**）；
2. `--list` 类命令不能证明浏览器行为；
3. 文件级 `--name-only` 不能证明符号级不变量；
4. 子集测试不能声称全量；
5. 涉及 Git 的命令必须使用 `rules.json` 已允许的受控入口（不新开裸 git 面、不改 `rules.json`）；
6. 不再通过委派评论补写命令算法（命令算法唯一事实源 = 证据命令表行）。
- 两条稳定表的表头 / 列集 / 「验收证据 ↔ 证据ID」双向唯一映射合同不变（CR-2026-060 AC-07 面，FR-6 第 3 条）。

**评侧**（`skills/develop/review-dev-plan/SKILL.md` 既有 `acceptance-verifiability` 增量维度，原位加入同一判据）：

7. **观测面窄于声称面即 blocker**；
8. **命令形态越受控边界即 blocker**，不留到 implement 阶段才暴露。
- 修订只在该维度段内原位扩写：**不重编 Step 号**（Step 1.0 clean 前置与 Step 5/6 PASS 发布已由 CR-2026-066 占用，§1.4 事实 18）；本 CR 在 `review-dev-plan` 中的新增文字**不得出现** `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（CR-2026-066 反向断言零命中，保持性约束）；**不新增新的评审维度名或证据账本**（判据落在既有 `acceptance-verifiability` 维度内，八类维度表与四个增量维度名不变，§1.4 事实 8）。

### FR-4 回滚单元是依赖闭包（`write-dev-plan` 交付覆盖表）〔来源 §6.4〕

修订面 = `write-dev-plan/SKILL.md` 交付覆盖表既有 `回滚` bullet（现文「该 FR 的回滚单元（如 revert 某 TASK commit）」，§1.4 事实 3）——原位明确：

1. 被其它 TASK 消费的**共享改动**，其回滚单元必须**包含受影响下游消费者**；
2. 并与风险节（plan.md 第 4 章「风险与回滚策略」）中的**逆拓扑顺序一致**；
3. 单点 revert 会破坏下游时**不得声明为单点回滚**。

不改交付覆盖表列集（仍为固定 5 列，§1.4 事实 3）。

### FR-5 环境责任与即时 readiness（plan / dev-start / implement 三侧）〔来源 §6.5〕

**plan 侧**（`write-dev-plan/SKILL.md` 既有「验收与发布策略」章节项 = plan.md 第 5 章说明，**不新增第八节**，原位扩写）——若证据依赖常驻服务、浏览器或数据库，plan 必须在该节写明：

1. **环境 owner**；
2. **建立方式**；
3. **可获得性**；
4. **readiness 证据**：必须复用**该环境所保障的那一行 FR 的既有 `cmd-NN`**，不得为 readiness 单独申请新 `cmd-NN`（理由：两张稳定表「验收证据 ↔ 证据ID」双向唯一映射（CR-2026-060 AC-07，`review-dev-plan` 覆盖矩阵节机械核对）不允许存在不被交付覆盖表引用的命令行——进证据命令表而不被引用即 blocker，不进表则不是合法 `cmd-NN`（无 executable/args/timeout 与 `crctl test` 机器区下标）。确实无法复用时，该诉求超出本 CR 边界，**另立 CR** 修改稳定表合同与对应评审判据，**本 CR 不放宽该映射**，§1.5 第 6 条）；
5. **缺失时的 `ENVIRONMENT_MISMATCH` 处置**（只引用既有标签与处置入口，不复述其完整语义——`implement-code` 是该标签唯一详细事实源，§1.5 第 4 条）。

**dev-start 侧**（`code-implementation.pipeline.json` 节点 `00000000-0000-0000-0015-000000000004` 既有 approvalPrompt，原位改写）：

6. 改为**只确认 owner、建立方式和可获得性**（静态前提）；不要求审批时所有服务在线，**不把动态健康状态写成人工长期事实**；
7. 改写文本满足现行 `pipeline-structure.test.mjs` 断言：节点 prompt/approvalPrompt **不得出现 `git` / `journal` 字样**（因此环境建立方式只写责任人与获得途径，不写命令）；**保留 approve/reject 结构化决定**（既有「✅ 通过 / ❌ 暂缓」两分支形态，§1.5 第 3 条）；**不得残留 `review-annotations` 路径与 `reject_reason` 引导**；
8. 节点对象其余字段（id / kind / label / onFail / timeoutMinutes）与节点集零变化（§1.4 事实 11）。

**implement 侧**（`skills/develop/implement-code/SKILL.md` 既有「环境验证与 ENVIRONMENT_MISMATCH」节，原位加入）：

9. 在**第一个依赖环境的 TASK 前**执行 plan 指定的 readiness `cmd-NN`（该命令属于既有「一次环境检查」有界前提检查的执行内容，不是反复探测，§1.5 第 5 条）；
10. 失败则按既有 `ENVIRONMENT_MISMATCH` 中止并报告建立动作（标签语义、不写 crctl 状态 / gate / 账本 / 评审 blocker / 测试证据 schema、`onFail=abort` 等既有边界全部不变，§1.4 事实 17）；
11. **环境无关 TASK 不被提前阻断**；
12. 不新增环境 Pipeline 节点、不让 coordinator 启停共享服务；「一次环境检查 / 最多一次重跑 / 临时隔离实例例外 / 受控建立归因」等既有 bullets 原样保留（同节共生，不改写）。

### FR-6 边界与零新增〔来源 §2、§6.6、§6.7〕

1. **不修改 upstream attempts 账本**（来源 §6.6）：不把 upstream block 追加到 `attempts[]`（该设计会产生 attempt 0 或重复 `(cycle,attempt)`、混淆「评审事件」与「预算 attempt」）、不新增 review-events、不改 traceability schema、不做聚合指标；既有 canonical annotation 与 audit 保留 upstream 事实。
2. **不新增 Pipeline 环境节点**：节点数保持 5/4/12（`_index.yml` 计数一致）；不改 replayNodes 条目、不改 review-route 枚举、不把 repair-target 改成多值。
3. **不新增账本字段 / 评审维度 / 观测指标 / crctl 子命令 / flag / 错误码 / Skill 参数 / 落盘文件 / lint 规则 / CI step**；`skills/shared/crctl/scripts/**`（含 gate-registry.json 与全部测试）预期零 diff（§1.5 第 2 条）。
4. **面不重叠（与已归档 CR 的块级边界，来源 §2）**：四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账、Step 6 摘要零 diff（CR-2026-066 面）；`write-tech-design` / `review-tech-design` 的 dep-N 与 SDD 写作合同零 diff（CR-2026-067 面）；`review-code` / `write-test-report` / `coding-discipline` 零 diff；本 CR 新增文字不得出现 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`。
5. **不复活旧字段名**：不引入 `recoverCommand` / `recover_command`（`contract-scan` 退役名单整树零命中，§1.4 事实 16）。
6. **测试与门禁**：`suite-gate --run` 全量绿、`gate-registry.json#manifest.cases` 与实际顶层用例数一致（当前 36/36）、`exceptions` 保持空（**不签任何新例外**，CR-S 后全量测试是真门禁）；本 CR 预期不新增测试用例（改动面无 match 型既有断言，§1.4 事实 14/15、§1.5 第 2 条）。

## 4. 非功能需求

- **NFR-1 兼容性与门禁（最重要）**：`../tools` 全量既有测试与 CI（lint-prompts enforce / skill matrix / agents contract / pipeline JSON 结构断言 / suite-gate --run / writeback 单测，Ubuntu + Windows）保持绿；本 CR **不得签任何新例外**，`gate-registry.json#exceptions` 保持空。
- **NFR-2 零新增**：同 FR-6 第 2/3 条（无新节点 / 维度名 / 账本字段 / 观测指标 / 子命令 / flag / 错误码 / Skill 参数 / 落盘文件 / lint 规则 / CI step）。
- **NFR-3 原位与单一事实源**：所有修订发生在**既有段落内部**；不得出现「新旧两套规则并存」的形态——尤其：`write-dev-tasks` 的 delta 重算规则不得与全量重建规则并存；`ENVIRONMENT_MISMATCH` 唯一详细事实源仍是 `implement-code`（write-dev-plan 侧只引用不复述）；plan 侧环境声明不得另造第二套验证语义。
- **NFR-4 判据可机械核对**：新增/改写的判据必须能被既有文本断言或 AC 的逐字核对覆盖（AC-1~AC-8）；**不得**把不可判定表述（如「足够详细」「合理覆盖」）写成判据。
- **NFR-5 行尾纪律**：触及跨行文本断言与 `\r\n` 归一化读取的测试面（contract-scan / pipeline-structure / crctl.test 的 `readTextNormalized` / `replaceAll('\r\n','\n')`），读写前必须归一；断言/解析失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」。SKILL 与 JSON 文件保持 LF 检出内容一致。
- **NFR-6 语言纪律**：`../tools` SKILL 正文用中文；本 CR 对 `../multica` 零 diff。
- **NFR-7 可回退**：全部为 Prompt 判据与提示文本的原位改动，**同批交付、同批还原**，不产生半套合同（尤其 `write-dev-plan` 的 upstream delta 轨与 `write-dev-tasks` 的 delta 重算语义必须同批落地——一侧单独存在即规则矛盾）。

## 5. 验收标准

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-1 | §6.7 | `write-dev-plan/SKILL.md#Step 2a`：① 普通轨三条既有语义逐字保留；② 含 upstream 轨判据——以新旧批准 SDD 变更 delta + 同轮未闭合 plan blockers 为输入、同一份 plan 上只重算受影响章节/稳定表行/证据/回滚、未受影响内容保留；③ 含「coordinator 只传 subject/delta/canonical feedback 引用、不指定具体行如何修改」；④ review-route 枚举与 repair-target 单值语义未被修改；⑤ 未新增 Step、未重编号。 |
| AC-2 | FR-2 | §6.7 | `write-dev-tasks/SKILL.md#Step 2a`：① 「重新生成」措辞零残留，该段表达 delta 重算 + 下游依赖闭包同步 + 同步更新输入/输出/接口/命令/depends-on/完成标志/回滚 + 未受影响 TASK 保留；② 「`crctl task init` 只用于刷新 `_index.yml` 索引」语义已写明；③ 文件内不存在两套并存的回修规则；④ 既有「`tasks/_index.yml` 是受控账本，禁止 Agent/Skill 手写」句仍在且 crctl.test.mjs CR-2026-037 用例仍绿（match 与 doesNotMatch 断言两侧）；⑤ 节点集 / 节点数 / replayNodes / `purpose: regenerate-tasks` 标签文本未被改动。 |
| AC-3 | FR-3 | §6.7 | ① `write-dev-plan` 两张稳定表说明含六项观测面判据（观测面 ≥ 声称面、`--list`≠浏览器行为、`--name-only`≠符号级不变量、子集≠全量、Git 用 `rules.json` 受控入口、命令算法不经委派评论补写），既有概括反假绿句保留且未另立第二句；② `review-dev-plan` `acceptance-verifiability` 维度含「观测面窄于声称面即 blocker」与「命令形态越受控边界即 blocker」；③ 八类维度表与四个增量维度名未变、无新证据账本；④ `review-dev-plan` 本 CR 新增文字不含 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`；⑤ 两张稳定表表头/列集/双向唯一映射合同未变。 |
| AC-4 | FR-4 | §6.7 | `write-dev-plan` 交付覆盖表 `回滚` bullet：① 共享改动的回滚单元必须包含受影响下游消费者；② 与风险节逆拓扑顺序一致；③ 单点 revert 会破坏下游时不得声明为单点回滚；④ 表列集未变（固定 5 列）。 |
| AC-5 | FR-5 | §6.7 | ① `write-dev-plan`「验收与发布策略」章节项含环境五要素（owner / 建立方式 / 可获得性 / readiness 复用既有 `cmd-NN` / 缺失时 `ENVIRONMENT_MISMATCH` 处置引用），plan.md 章节未新增第八节；② `code-implementation.pipeline.json` `…0004` approvalPrompt 只确认 owner/建立方式/可获得性等静态前提、不要求审批时服务在线、不含 `git`/`journal` 字样、保留 ✅/❌ 两分支结构化决定、无 `review-annotations`/`reject_reason` 残留，节点对象其余字段与节点集零变化；③ `implement-code` 环境节含「首个环境依赖 TASK 前执行 plan 指定 readiness `cmd-NN`」「失败按既有 `ENVIRONMENT_MISMATCH` 中止并报告建立动作」「环境无关 TASK 不被提前阻断」，且该节既有 bullets（一次检查/一次重跑/timeout/标签不写账本/临时隔离例外/受控归因）未改写。 |
| AC-6 | FR-5 | §6.7（映射不破坏） | ① readiness 证据复用既有 `cmd-NN`：两张稳定表「验收证据 ↔ 证据ID」双向唯一映射未被放宽或修改（`review-dev-plan` 覆盖矩阵节机械核对判据原样保留）；② 不存在「为 readiness 单独申请新 `cmd-NN`」的形态文字；③ 无法复用场景的文字指向「另立 CR」，本 CR 内无任何放宽。 |
| AC-7 | FR-6 | §6.7（零新增） | ① 交付 diff 只含 §1.3.1 表内 5 个文件；② `skills/shared/crctl/scripts/**`（含全部测试与 `gate-registry.json`）、`write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline`、pipeline 节点集与 reviewLoop、`tools/agents/**`、`agent-skill-matrix.yml`、`../multica/**`、KB `specs/`/`delivery/`/`docs/` 零 diff；③ 节点数保持 5/4/12 且 `_index.yml` 计数一致；④ upstream attempts 账本 / traceability schema / 账本字段 / 评审维度 / 观测指标 / crctl 子命令 / flag / 错误码零新增。 |
| AC-8 | FR-1~FR-6 | §6.7 + §2（CR-2026-066/067 面零 diff） | ① 四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账四要素（`phase` / `batchId` / `repositories[]` / `metadataCommit`）逐字保留；② 四 SKILL 不含 `crctl checkpoint`、不含 `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`；③ CR-2026-067 的 dep-N 面（`write-tech-design` / `review-tech-design`）零 diff；④ `pipeline-structure.test.mjs` 的 CR-2026-043（git/journal 零命中）、CR-2026-037（账本写指令零命中 + `task init` 断言）、AC-1（5/4/12）与 `crctl.test.mjs` CR-2026-029（无发布联调拆分指引）全部仍绿。 |
| AC-9 | 全部（边界与串行） | §2、§8（**本 PRD 新增**） | ① **串行约束**：实施与交付期间 `change-requests/_backlog.yml` 在途条目只有本 CR，CR-2026-063/064/065/066/067 的 `crctl status` 均为 `archived`；② **顺序**：CR-P0(063) → CR-R(064) → CR-S(065) → CR-P3(066) → CR-P1(067) → **本 CR(068)**，不与任何 CR 并发（tools 单写者）；③ `suite-gate --run` 全量绿、`gate-registry.json#manifest.cases` 与实际顶层用例数一致（36）、`exceptions` 为空数组（未签任何新例外）。 |

来源 §6.7 的十条验收与上表一一对应（AC-1~AC-8 按行为面 / 证据面 / 零 diff 面分组，未合并判据）；AC-9 是「把来源 §2 的 CR-P2 边界与 §8 的串行约束写成可检查约束」的落地判据（来源文档没有对应 AC）。

## 6. 成功指标

- upstream 重放后 plan 的重写面与 delta 成正比：未受影响章节 / 稳定表行 / 证据 / 回滚的改写数 = 0。
- upstream 重放后未受影响 TASK 的重建数 = 0；受影响依赖闭包内残留旧接口 / 命令 / `depends-on` 数 = 0。
- 「只修 plan、旧 TASK 留给下一轮评审发现」形态的发生数 = 0（由 AC-2 判据约束）。
- 观测面窄于声称面 / 命令形态越受控边界的 blocker 在 **dev-plan 阶段**拦截率 = 100%；漏到 implement 阶段才暴露数 = 0。
- readiness 复用既有 `cmd-NN` 的比例 = 100%；两张稳定表双向唯一映射被放宽次数 = 0。
- dev-start 审批要求动态服务在线 / 把动态健康写成人工长期事实的文字 = 0。
- 环境依赖 TASK 执行前即时 readiness 执行率 = 100%；环境无关 TASK 被提前阻断次数 = 0。
- 本 CR 新增的 Pipeline 节点 / 账本字段 / 评审维度 / 观测指标 / crctl 子命令 / flag / 错误码 / Skill 参数 / 落盘文件 = 0；测试用例数变化 = 0（36 保持）；`gate-registry.json#exceptions` 长度 = 0。
- 既有测试回归数 = 0；CI 新增例外数 = 0；CR-2026-066 / CR-2026-067 的既有断言失败数 = 0。

## 7. 范围排除

**来源 §2 的 CR-P2 边界（逐条不做，判据见 AC-7 / AC-9）**

- **不新增 Pipeline 环境节点**：节点集 / 节点数（5/4/12）/ replayNodes 全保持；`purpose: regenerate-tasks` 标签文本不改。
- **不做动态环境人工门禁**：dev-start 不要求审批时服务在线；不让 coordinator 启停共享服务。
- **不新增评审观测指标**：无 SLO / 轮数承诺 / 计数门禁 / 聚合指标。

**来源 §6.6 明确不做（upstream attempts 账本零改动）**

- 不把 upstream block 追加到 `attempts[]`、不新增 review-events、不改 traceability schema、不做聚合指标；既有 canonical annotation 与 audit 保留 upstream 事实。

**来源 §6.5 明确交出的面**

- readiness 无法复用既有 `cmd-NN`、需要独立 readiness 命令行 → 修改两张稳定表双向唯一映射合同与对应评审判据，**另立 CR**，本 CR 不放宽映射。
- 不修改 `review-route` 枚举、不把 `repair-target` 改成多值（FR-1 第 3 条）。

**与已归档 CR 的面不重叠（块级零 diff，判据见 AC-8）**

- CR-2026-066 面：四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账、Step 6、节点集与权限矩阵。
- CR-2026-067 面：`write-tech-design` / `review-tech-design` 的 dep-N 表达、`commit SHA` 双侧必填、状态链整体重证、批准范围四字段自洽。
- CR-2026-065（CR-S）面：`suite-gate` 判据语义、`gate-registry.json` 登记机制——本 CR 不签任何新例外。
- CR-2026-064（CR-R）面：结构化 `recovery` 合同；不复活 `recoverCommand` / `recover_command`。

**本次明确不碰的既有资产**

- crctl 状态机、gate、CAS、durable ledger transaction、`reviewLoop` / `replayNodes` / `maxAttempts`、controlled-shell 与 `rules.json`、`ENVIRONMENT_MISMATCH` 标签语义（唯一详细事实源在 `implement-code`）、版本化 `cmd-NN` 与 test evidence、两张稳定表合同（CR-2026-060 AC-07）、`skills/shared/crctl/scripts/**` 全部测试与 `gate-registry.json`。
- `../multica/` 的 `CUSTOM.md`、`cr-prompts-revised/**`、`aifirst/**` 与任何 Go/TS 代码；平台 DB；KB 的 `specs/`、`delivery/`、`docs/`（`docs/analysis/` 来源文档只读）。
- `tools/agents/**`（不在来源 §6 修订面内，Agent Prompt 零 diff）。

**顺序与并发约束（可检查形式见 AC-9）**

- 顺序：CR-P0(063) → CR-R(064) → CR-S(065) → CR-P3(066) → CR-P1(067) → **本 CR(068)**；本 CR 不得早于 CR-P1 执行（来源 §8 实施顺序第 6 条：CR-P2 最后落地），不与任何 CR 并发（tools 单写者）。
- 任一 CR 失败只回滚本 CR；不得为了保持后续 CR 而保留半套新旧合同（来源 §8）。

## CR 流程降本提效首期：FR-8 成本基线 + FR-1 OutputGuard + FR-2 crctl 输出瘦身（v0.42 · CR-2026-069）

## 1. 概述

### 1.1 问题陈述

需求来源是 Issue **AIFI-32** 附件《CR需求来源_CR流程降本提效_收敛版.md》（26,406 B，附件 id `01a0ae08-91e4-76af-a810-798d812b6c2f`）。该文件是原始来源《CR需求来源_CR流程降本提效.md》（22,327 B，2026-09-16）经 grilling 决策（Q1～Q36）收敛后的版本；两份文件已按来源 §15 的「注册时保留原始附件与本收敛版，原始附件作为需求演进证据」一并登记在本 CR 的 `change-requests/CR-2026-069/sources/` 下（见 §1.4 事实 15）。**本 PRD 的一切范围判定以收敛版为唯一权威**，原始版只作演进证据，其 §8 九项 FR 不构成九项交付合同（来源 Q1、Q35）。

问题本身（来源 §4 基线 + 原始版 §1、§8）：CR 流程的单位成本由工具结果 token 主导，而工具结果在进入模型上下文前**完全不受治理**。原始版实测口径（2026-08-18～2026-09-16，672 个会话文件 / 643 个带工具结果的会话）：工具结果合计约 **49.7M tokens**（o200k 编码），其中搜索类约 10.97M、目录列举约 2.32M、文件打印约 5.98M；带 CR-ID 的会话覆盖 36 个 CR，约 **17 会话/CR**（中位数 8、P75 12、P90 56、最大 124）；crctl 自身命令输出约 1.24M，占执行类输出约 53%（来源 §4，本 PRD 原样采纳为需求动因，不重复其统计过程，见 §1.4 事实 12）。

来源给出的根因结论（原始版 §4 R-1/R-2/R-3/R-4 + 收敛版 §6.1）有三条直接决定本 CR 的形状：

1. **治理点位置错**：只有把护栏放在「工具结果进入**下一轮模型上下文**之前」才降低成本；只改 Multica daemon 的 transcript/preview 已经太晚——`server/internal/daemon/tool_output_preview.go` 源码注释自己写明 `It does not limit the full output consumed by the agent`（§1.4 事实 8）。因此该文件本 CR **零 diff**（AC-12）。
2. **靠 Prompt 约束不稳定**：来源 R-2 判定「靠提示词约束行为跨模型不可靠」，§11 明确「不把检索纪律仅写入 Skill/Prompt 作为主要手段」。因此本 CR 的实现面是**代码层无状态规则求值**，不是 Prompt 治理（FR-1）。
3. **收益必须可证伪**：原始版 R-4 判定成本口径未与真实账单对齐。因此**先测基线、后改代码、再复测**被钉为第一期第一位（FR-8），并把它设成后续扩项的硬门槛（§5.6 / AC-17）。

同时，来源 §3 钉死了「已解决的基础设施本 CR 直接复用」：crctl 的状态机 / 门禁 / CAS / `durable-tx.mjs` / `workspace-transactions.mjs` / `gates.json` / `pipeline-templates` / writeback 版本化脚本 / CI 合同校验全部已存在（§1.4 事实 1–5）。因此本 CR 的全部杠杆是**在呈现层与工具结果层做减法**，零新增治理结构。

### 1.2 解决方案摘要

按来源 §1「首期仅实施三项」逐条落地，编号沿用来源 FR 编号（FR-3～FR-7、FR-9 编号保留、不占用，见 §7）：

1. **FR-8 离线成本与质量度量**（来源 §5）：新增一个只读度量脚本（来源建议落位 `AI-First-tools/skills/shared/metrics/scripts/cr-cost.mjs`，该目录当前不存在，§1.4 事实 6），在本 CR 内只执行两次——改造前基线 + 672 会话 policy 离线回放、部署后 14 天窗口复测。它不推进 CR、不参与门禁、不写状态与账本；机器结果只有一份 JSON，人读摘要由同一脚本即时渲染；报告作为 CI artifact 或 Issue 附件保存。
2. **FR-1 通用 OutputGuard**（来源 §6）：无状态 Core（规则求值 + 确定性裁剪 + 提示 + 覆盖度结果）+ 五个 Runtime 薄 Adapter（只做 Provider hook 输入/输出映射）。seam 在 `Runtime 原生工具调用 → Adapter → Core → 裁剪后的模型可见结果`。首期只治理实测高消耗命令族（`grep`/`rg`/`find`/`Get-ChildItem`/`cat`/`Get-Content`），不写 shell parser；`policy.json` 是阈值唯一事实源，阈值由 FR-8 基线产出而不是拍脑袋。裁剪结果一律标 `complete=false`、保留 `toolName`/`toolCallId`/`isError`/`exitCode` 与结果结构、被丢弃正文不落盘；`complete=false` 不是充分门禁证据；逃生阀是一次性首行注释且不绕过任何安全控制；缺 Adapter 或 policy 损坏时显式 fail-open 并标 `coverage=unavailable`。Core/Policy/五 Adapter 随同一 Tools Release 原子发布，按 Pi → Claude → CodeBuddy → Qoder → Codex(partial) 顺序启用。
3. **FR-2 crctl 输出瘦身**（来源 §7）：只给「基线识别出的、覆盖 ≥80% crctl 输出 token 的最小命令集合」增加独立 summary projector；默认输出 compact summary JSON，完整字段经统一 `--detail` 获取。当前 `crctl.mjs` 的成功输出由统一 `ok()` 全量缩进打印（§1.4 事实 7），本 CR 改的是**呈现层**，禁止在全局 `ok()` 粗暴删所有命令字段；退出码、错误码、字段语义与状态、门禁、审批、CAS、事务、Git 行为逐一不变（AC-11）。

三项合起来构成一个可证伪闭环：**FR-8 定义「省了多少、有没有变差」的唯一口径 → FR-1 与 FR-2 是唯一被允许的两个降本手段 → FR-8 的复测结果是 FR-3～FR-7、FR-9 能否重新立项的唯一前置**。

### 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

> CR 流程降本提效首期：在不改变 CR 阶段、门禁、审批、Git、账本与事务语义的前提下，只实施三项。FR-8 离线建立成本基线与历史回放（读取既有 session 工具结果与 Provider usage，对 672 个历史 Pi session 离线回放 OutputGuard policy，部署后固定 14 天窗口复测；只在改造前与部署后各执行一次，不进 Pipeline 节点、不参与门禁、不写状态与账本，目标桶 tokens/CR 需下降至少 20% 且三项质量护栏全部不恶化才允许重新立项评估候选 FR）。FR-1 无状态 OutputGuard Core 加五个 Runtime 薄 Adapter（在工具结果进入下一轮模型上下文之前治理无界检索、递归列举与全文读取；policy/capabilities/conformance 为唯一事实源；裁剪结果必须标记 complete=false 并保留 toolName、toolCallId、isError、exitCode 与结果结构，被丢弃正文不落盘、不进 transcript；complete=false 结果不得作为充分门禁证据；一次性首行注释逃生阀只影响当前调用、原因必填、不绕过安全控制；Adapter 或 policy 缺失损坏时显式 fail-open 并标 coverage=unavailable；按 Pi 到 Claude 到 CodeBuddy 到 Qoder 到 Codex(partial) 顺序启用；Core、Policy、五个 Adapter 随同一 Tools Release 原子发布升级）。FR-2 只对基线识别出的、覆盖至少 80% crctl 输出 token 的最小命令集增加 summary projector（默认输出 compact summary，完整字段经 --detail 获取，不新增 --output json、--verbose、--pretty 平行开关，不在全局 ok() 粗暴删字段；退出码、错误码、字段语义与状态、门禁、审批、CAS、事务、Git 行为逐一不变）。范围为一个 CR、十个 TASK，复用既有跨仓 checkpoint、事务与受控 Git，每个 Adapter 独立提交可单独回滚；明确零改动 AI-First-multica 的 tool_output_preview.go，不新建事务协调器、WAL、CAS 层或 Git 提交框架，不拆分或重构 workspace-transactions.mjs，不复制 passCondition、状态映射或 reviewLoop 算法，不实现完整 Bash/PowerShell parser，不调用 LLM 做输出摘要，不新增状态、门禁、审批或 CR 生命周期节点，不新增账本、数据库、仪表盘、sidecar 日志或远程动态开关。FR-3 至 FR-7 与 FR-9 保留为候选 Backlog，不属于本 CR 验收范围，不得借本 CR 扩大范围。

#### 1.3.1 scope_in 边界（原文前缀，评审核对用）

> 在不改变 CR 阶段、门禁、审批、Git、账本与事务语义的前提下，首期仅实施：1. **FR-8**：离线建立成本基线、历史回放与部署后复测；2. **FR-1**：通过无状态 OutputGuard Core 与 Runtime Adapter，在工具结果进入模型上下文前治理无界检索、全文读取和超量输出；3. **FR-2**：仅对贡献主要输出量的 crctl 命令做 compact summary，完整结果通过 `--detail` 获取。FR-3～FR-7、FR-9 保留为候选 Backlog，不属于本 CR 验收范围。

（来源 §1 逐字。Issue 标题写作「FR-0/1/2」，与来源 §1 不符，**以来源 §1 的 FR-8 + FR-1 + FR-2 为准**——本 PRD 不存在「FR-0」，Issue 标题只是人工录入笔误，见 §1.5 第 1 条。）

三项的**共同硬边界**（来源 §2 依赖方向 + §3.1「本 CR 禁止」清单 + Q2）：

- 依赖方向固定为 `Agent → Pipeline → Skill → crctl`、`Runtime Adapter → OutputGuard Core → policy.json`、`离线度量脚本 → 既有 session/provider usage（只读）`；不得出现反向或第二通道。
- 对本次**新增/修改**的面是硬约束；存量 Prompt 重复不扩散、不顺带全仓重构（Q2、§11）。
- 新增产物一律是**非权威投影**（Q3）：度量 JSON、trailer、覆盖度声明都不进 CR 权威账本、不进门禁 passCondition 输入。

#### 1.3.2 目标仓库与版本

| 仓 | 本 CR 的落地面 | 明确不碰的面 |
|---|---|---|
| `../tools`（`ai-first.tools` 方法论包） | OutputGuard 新增目录（来源 §6.2 建议位 `output-guard/`：`core.mjs` + `policy.json` + `capabilities.json` + `conformance.json` + 五个 Adapter）、FR-8 度量脚本（建议位 `skills/shared/metrics/scripts/cr-cost.mjs`）、FR-2 的 crctl summary projector 与 `--detail`、README 导航段、合同测试 | `skills/shared/crctl/scripts/lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`（不新建第二套事务、不拆分重构）、`skills/shared/crctl/gates.json`、`dir-graph.yaml#state_machine`、`pipeline-templates/*.pipeline.json`（节点数保持 5/4/12）、`agent-skill-matrix.yml`、既有阶段/门禁/审批/事务语义 |
| `../multica` | 仅 Runtime 启动接线 / Adapter 挂载与部署（来源 §8 TASK-09：只部署挂载，不复制 policy、不改 preview） | `server/internal/daemon/tool_output_preview.go`（**零 diff**，AC-12）、`server/internal/governance/runner.go` 的固定 `architecture-design` 切片、Provider 事件归一化语义 |
| knowledge-base（本仓） | 本 PRD 与后续评审/审批产物；`change-requests/CR-2026-069/sources/` 两份需求来源证据 | `specs/`、`delivery/`、`docs/`（只读）、受控账本（一律经 crctl） |

- `target-version` 继承 `cr.md` 的 **`0.42`**（注册阶段人工确定「版本在现有版本上延续」：现行最高 `specs/_index.yml#current = 0.41` = CR-2026-068 的 target-version，§1.4 事实 13）；本文件不改写该值，唯一更正入口是 `crctl version-set`。
- `target-spec-id` = **`ai-first-platform`**，由注册事务双写入 `cr.md` 与 `_backlog.yml`（全等），本文件不得改写。
- 实施拆分为**一个 CR、十个 TASK**（来源 §8 / Q23）：TASK-01 基线 → TASK-02 Core/policy/capabilities/conformance → TASK-03～07 五 Adapter（可并行准备，启用顺序受 §6.11 约束）→ TASK-08 FR-2 → TASK-09 Multica 接线 → TASK-10 部署后复测。该拆分是**范围合同**（十项全部交付、不得并项或漏项），具体的文件级步骤与依赖矩阵归开发期 plan/TASK，不在需求期重排。

#### 1.3.3 契约说明（确定性四查适用面）

本 CR **新增两类用户可调用契约**，四查适用面如下（可观察行为，实现算法归 SDD）：

- **适用：OutputGuard 的调用前判定 + 调用后裁剪决策**（FR-1）——它是每次工具调用都会命中的新契约面，四查逐条落在 FR-1 第 6～9 项（幂等求值、固定判定顺序与唯一终态 action、错误码闭包、零写入与零残留副作用）。
- **适用：`crctl <命令> --detail`**（FR-2）——它是新增 flag 与默认输出形状变更，四查落在 FR-2 第 3～6 项（幂等、无权限分支、错误面不变、纯呈现零副作用）。
- **不适用：FR-8**——它是只读离线脚本，不定义任何用户可调用的请求/响应契约（无 HTTP API、无 crctl 子命令、无状态写入），验收以「可复现筛选规则 + 固定 JSON 字段集 + 口径合同」形式给出（AC-17/AC-18）。
- **不适用：本 CR 不改任何既有 HTTP endpoint / request / response、不改 crctl 既有子命令集与错误码语义**（AC-11、AC-1）。`skills/shared/crctl/scripts/crctl.mjs` 被改的只有成功输出投影层，不改状态转换、门禁、审批、CAS、事务与 Git 行为。

### 1.4 当前事实（落笔前核实）

基线（`crctl register` ensure 的 requirement worktree，注册 commit `b87f7648090b74060a155697c54f979f9b16ea84`）：

| 仓 | 基线 |
|---|---|
| `ai-first-platform-docs`（本 KB） | worktree HEAD = trunk HEAD = `b87f7648`（register 提交，trunk `master`，注册前 `change-requests/` clean） |
| `../tools` | `82e43dc53d51f69a799904c786900ea78e57ca12`（= tools `main`） |
| `../multica` | `947386318d52ecdb026a017f76220cde2ef7b94e`（`requirement/CR-2026-069` 分支基线，= multica `main`） |

以下结论均在上述 SHA / 当前盘面上实读核实（路径相对各自仓根）：

| # | 结论 | 证据 |
|---|---|---|
| 1 | `skills/shared/crctl/scripts/lib/` 现有 `durable-tx.mjs`（锁、journal envelope、recoverable write-set、CAS、恢复、`nowIso`/`FAULT_POINTS` 唯一实现）与 `workspace-transactions.mjs`（仓库/worktree、候选 manifest 校验、受控 Git、原子提交）+ `outbox-contract.mjs` + `yaml-subset.mjs`——**两套既有事务/账本基础设施齐备，本 CR 只能复用** | `ls lib/`；`crctl.mjs` L55 注释「nowIso 与 FAULT_POINTS 自 TASK-04 起 re-import 自 lib/durable-tx.mjs（唯一实现）」 |
| 2 | `ARCHITECTURE.md` 的「分层与依赖方向」节已把「另一套独立 WAL/事务框架」列为禁区，理由是「跨文件与跨仓写入统一复用 `durable-tx.mjs` …… 再造第二套会分裂恢复语义」——来源 §3.1 的禁止项与仓内既有硬不变量一致，不是本 CR 新立规矩 | `tools/ARCHITECTURE.md` L69、L101 |
| 3 | `skills/shared/crctl/gates.json` 存在且是运行时适配映射（证据路径 / 审批段 / passCondition 引用），状态机事实源是 `dir-graph.yaml#change-request-track.state_machine`；`requirement-reviewing` 门禁 = `fileExists prd.md` + `passCondition(stage=requirement)` | `gates.json` 实读（`approvalStages.requirement`、`statusGates."requirement-reviewing"`） |
| 4 | `pipeline-templates/` 现有 8 个 pipeline JSON；`requirement-authoring` 为 5 节点（register → write-requirement-prd → review-requirement(reviewLoop maxAttempts=3, passCondition `verdict=pass` ∧ `blockers` 空) → human_approval → approve-requirement）——本 CR 不改节点集与 reviewLoop | `ls pipeline-templates/` + `cat requirement-authoring.pipeline.json` |
| 5 | `skills/writeback/scripts/` 现有 `writeback-prd-sdd.mjs` / `writeback-tasks.mjs` / `writeback-traceability.mjs` + `lib.mjs` + `test/`；`.github/workflows/crctl-ci.yml` 存在；测试面 `skills/shared/crctl/scripts/test/` 现有 **21** 个 `*.test.mjs`，`gate-registry.json#manifest.cases` 按文件登记基线用例数（21 项、合计 579），判据是 **`实际顶层用例数 < 登记基线` 即 `SUITE_MANIFEST_CASE_DROP` 红**（棘轮只挡回退，不挡新增）；`exceptions` 当前为空数组 | `ls` 实读 + `gate-registry.json` + `suite-gate.mjs` L448–454 |
| 6 | `output-guard/` 与 `skills/shared/metrics/` 两个来源建议目录**当前均不存在**（本 CR 新增面）；`skills/shared/crctl/adapters/` 现有 `ci` / `claude-code` / `codex` / `cursor` / `qoder` 五个**crctl 守卫**适配器模板（职责是裸 git deny、受控路径写入 deny/ask、SessionStart 注入权威指针），**无 codebuddy**，且**无任何输出裁剪能力** | `ls -d tools/output-guard tools/skills/shared/metrics` → No such file；`ls adapters/`；`adapters/claude-code/README.md` 表 |
| 7 | `crctl.mjs` 的成功输出面是单一 `ok(obj)`，实现为 `JSON.stringify(obj, null, 2)` 全量缩进打印；全仓 `crctl.mjs` 中 **`--detail` / `--verbose` / `--pretty` / `--output` 零命中**，`ok(` 调用点 36 处，`fail(` 247 处。来源 §7.1「尚无 `--detail`、`--verbose` 或必要的 `--output json` 模式」成立 | `crctl.mjs` L51–53 + grep 实测 |
| 8 | `../multica/server/internal/daemon/tool_output_preview.go` L10 注释逐字为 `previews. It does not limit the full output consumed by the agent.`；该文件只限制上传/展示预览。`server/internal/governance/runner.go` 是固定 `architecture-design` 切片的 Reconcile 实现；`server/pkg/agent/` 现有 claude / codebuddy / codex / cursor / qoder 等各 Runtime 归一化实现（`SupportedTypes` 白名单在 `agent.go` L350） | 三文件实读、grep |
| 9 | Pi 侧 seam 的合同存在：`@earendil-works/pi-coding-agent` 文档的事件流为 `tool_call (can block)` → `tool_result (can modify)`；`tool_call` 返回 `{ block: true, reason?, terminate? }` 控制阻断，`tool_result` handler「chain like middleware」 | `docs/extensions.md` L304–306、L778–796、L842–848 |
| 10 | 会话数据位置与规模（当前盘面复核）：`~/.multica/pi-sessions` 共 1032 个文件（其中 `*.jsonl` 604 个）、`~/.pi/agent/sessions` 共 104 个文件；按来源区间 `2026-08-18`～`2026-09-16` 过滤 `*.jsonl` 得 584 + 89 = **673** 个 | `find … -name '*.jsonl' -newermt 2026-08-18 ! -newermt 2026-09-17` |
| 11 | FR-2 的调用方现状：`gate-registry.json` 与各 SKILL/pipeline 文本以 `crctl <子命令>` 原样调用（无 `--detail`），故「现有机器调用方若依赖完整字段则显式补 `--detail`」是一个**必须扫描并更新既有真实调用方**的交付项，不是可选优化 | grep 实测（现零 `--detail`） |
| 12 | 来源 §4 的 49.7M / 17 会话每 CR / 各桶 token 数字**未被本 PRD 复算**（复算正是 TASK-01 的交付物）；本 PRD 只采纳其数量级作为需求动因，并把「可复现的筛选规则 + 重跑即得同一结果」写成 FR-8 的验收，不把任何具体数字写成既成事实（除 §1.4 事实 10 的复核数外）。样本文件数的口径差异见 §1.5 第 3 条 | 来源 §4 + 本表事实 10 |
| 13 | 版本事实：`specs/_index.yml` 唯一 feature `ai-first-platform` 的 `current: "0.41"`、`cr-ref: CR-2026-068`；`change-requests/_history.yml` 中已归档 CR 的最大 `target-version` = 0.41；注册前 `change-requests/_backlog.yml` 无任何在途条目（schema `cr-backlog/v2`，文件为空条目集）。本次 `crctl register` 返回 `cr_id = CR-2026-069`、`targetVersion = 0.42`、`targetSpecId = ai-first-platform`、commit `b87f7648`、三仓 worktree 已 ensure、`operational_workspace` 指向 `.rayai-worktrees/knowledge-base/requirement/CR-2026-069` | `specs/_index.yml`、`_history.yml`、`_backlog.yml`、register JSON 输出 |
| 14 | tools 包规模计数口径复核：`skills/*/SKILL.md` 共 **56** 份、`agents/` 共 **9** 份 Agent 定义（另 `_index.yml`）、`pipeline-templates/` 共 **8** 份 pipeline——与 KB `AGENTS.md` 声明的「9 Agent / 56 Skill / 8 Pipeline」一致；来源 §3.1 引用该包时不存在计数漂移 | `find skills -name SKILL.md | wc -l`、`ls agents`、`ls pipeline-templates/*.json` |
| 15 | 来源证据文件已入 CR 目录：`change-requests/CR-2026-069/sources/CR需求来源_CR流程降本提效_收敛版.md`（26,406 B）与 `…/CR需求来源_CR流程降本提效.md`（22,327 B，原始版）。登记时工作区副本与 Issue 附件 `cmp` 逐字节一致（两者均 LF），且 checkpoint 后 **git blob 尺寸仍为 26,406 / 22,327 B**（存储为 LF，未被改写）。注意：本 KB 仓 `core.autocrlf=true` 且无 `.gitattributes`，**任何新检出会得到 CRLF 工作区文件**，故后续任何核对必须按 EOL 归一比较，不得把「与附件逐字节一致」写成无条件事实（§1.4 事实 16） | `cmp` 实测、`git cat-file -s HEAD:<路径>` = 26406 / 22327、`git config --get core.autocrlf` = true、`ls .gitattributes` → 不存在 |
| 16 | 行尾纪律先例：已归档 CR-2026-068 的 requirement 评审 `suggestions` 第 1 条正是「KB 内来源文档与 Issue 附件逐字节一致（cmp 通过）」在字节层不成立（检出 CRLF/34036B vs 附件 LF/33478B），并建议改写为「EOL 归一后一致」。本 PRD 自初稿即按该口径表述，不再重复同一断言错误 | `change-requests/CR-2026-068/review-annotations/requirement.yml#suggestions` |

### 1.5 对来源文档的事实更正与需人工确认的口径

1. **Issue 标题与来源 §1 不一致，取来源 §1**：标题「CR 流程降本提效：FR-0/1/2」中的 FR-0 不存在；收敛版 §1 与 Q4/Q35 钉定首期 = **FR-8 + FR-1 + FR-2**。注册输入由协调者按来源 §1 复核后下发（`target-version 0.42`、`target-spec-id ai-first-platform`、三角色 owner = Ray），本 PRD 与 cr.md summary 一致，不改写标题含义。
2. **FR 编号保留空洞是刻意的**：本 PRD 的功能需求只有 FR-1、FR-2、FR-8 三条；FR-3～FR-7、FR-9 是来源 §12 的候选 Backlog **编号占位**，不是遗漏。评审时若发现「缺 6 条 FR」，判据应为「是否把候选 Backlog 借本 CR 带入」而不是「编号是否连续」。
3. **样本文件数 672 vs 复核 673**：来源记 672 个会话文件；本次按 `*.jsonl` + 来源区间复核得 673（§1.4 事实 10）。差 1 属窗口边界与文件类型口径，不影响任何结论。**本 PRD 不把 672 写成硬事实**：FR-8 的验收是「筛选规则以命令形式可复现 + 重跑得到同一集合」，回放样本数由脚本自身输出，不得把常量 672 写进代码或门禁（AC-17）。
4. **§6.3 的 Runtime 能力矩阵不由本 PRD 复述为事实**：Claude / CodeBuddy / Qoder 的 `PreToolUse` + `PostToolUse.updatedToolOutput`、Codex 的 `Managed PreToolUse` + `block/feedback` 路径与 hosted `WebSearch` 绕过，来自来源引用的外部文档（§6.3 参考依据）。需求期只钉合同：**能力分级必须由 `capabilities.json` 声明、由 `conformance.json` 逐 Adapter 验证、uncovered 路径必须显式标记而不宣称生效**（AC-4、AC-8）。若实施期发现某 Runtime 实际不具备 full 能力，唯一合法动作是把 `capabilities.json` 降为 partial/unavailable（不得伪装 full），并据此调整 §6.11 启用顺序。
5. **需人工一并确认：逃生阀标记不合法时的行为（来源未写明，本 PRD 钉定）**——来源 §6.6 只规定 `reason` 必填、单行、限制长度，未规定缺失/畸形时的处置。本 PRD 钉为：**该标记视为不存在，调用按普通路径处理（不拒绝工具调用本身），不新增 action 取值、不新增提示文本；若随后被裁剪，仍按 §6.7 输出 `action=truncate` trailer**，模型因此可见「本次未获得完整结果」。不引入第二套错误码，不引入授权文件（保持 Q18 无状态）。
6. **需人工一并确认：`--detail` 与 summary 的字段等价定义**——来源 §7.3 写「`--detail` 的业务字段与旧完整输出等价」。本 PRD 钉为：**`--detail` 的输出必须等于改造前该命令的完整 JSON（同字段集、同语义、同嵌套形状），差异只允许出现在「默认输出被投影为 compact summary」这一侧**；合同测试按「逐字段集合比对」而非「字节比对」验收，以免行尾与缩进噪声产生假失败（AC-10、AC-21）。
7. **需人工一并确认：新增合同测试的棘轮登记同步义务**——FR-2 要求「既有测试全绿，并增加 summary/detail 合同测试」（来源 §7.3）。本 KB 的 `gate-registry.json#manifest.cases` 是**下限棘轮**：`实际用例数 < 登记基线` 即 `SUITE_MANIFEST_CASE_DROP` 红，故**新增用例不登记也不会立即变红，但会永久留在回归保护之外**（§1.4 事实 5）。本 PRD 因此要求新增用例在同一 CR 内把该文件的登记值同步为实际值（先例：CR-2026-067 同步 `pipeline-structure.test.mjs` 的 36），且**不得签任何新例外**，`exceptions` 保持空数组。落地判据 AC-21。
8. **OutputGuard Adapter 与 crctl 既有 IDE 适配器的关系（本 PRD 钉定，避免第二份事实源）**：`skills/shared/crctl/adapters/` 现有模板治理的是「裸 git / 受控路径写入 / SessionStart 注入」，与 FR-1 的「工具结果裁剪」是**两套不同职责**，不得合并成一个配置文件，也不得把 `policy.json` 复制进 crctl adapter 目录。目录归属、hook 是否与既有 `settings.template.json` 共用安装入口归 SDD；硬边界是**policy 单一事实源、随同一 Tools Release 原子发布**（AC-3、AC-20）。CodeBuddy 当前无任何既有适配器，属纯新增（§1.4 事实 6）。
9. **来源 §6.10 的「Tools Plugin 携带 Skills 与 hooks」在 tools 仓当前无载体**：仓内不存在 `.claude-plugin/plugin.json` 或等价 plugin 清单；现有 Claude 安装方式是「把 `settings.template.json` 的 hooks 段合并进目标 workspace 的 `.claude/settings.json`」并**在安装时物化为 tools 包绝对路径**（模板里是占位符，安装动作负责替换）。本 PRD 因此只钉合同（显式安装一次、三级 scope、启动只检查不修复、不得复制 policy），把「是否引入 plugin 打包形态」交给 SDD 依据该先例决定；不得为「Plugin」新建安装框架或远程开关（AC-20、§7）。

### 1.6 修订记录

- **初稿（2026-09-17）**：按来源收敛版 §1～§15 与注册摘要（`cr.md` summary）起草；§1.4 的 16 项事实在三仓基线 SHA / 当前盘面上逐条实读核实。FR 编号沿用来源编号（FR-1=来源 §6、FR-2=来源 §7、FR-8=来源 §5）；AC-1～AC-16 与来源 §9.1 的十六条合并前硬验收**一一对应、不合并判据**；**AC-17～AC-21 为本 PRD 新增**，覆盖来源正文有要求但 §9.1 未列成验收的五个面（FR-8 输出/口径/执行次数合同、FR-1 发布与启用合同、FR-2 调用方同步与用例登记合同）。§1.5 记录三处需人工一并确认的钉定（第 5、6、7 条）、四处本 PRD 钉定（第 3、4、8、9 条）与一处范围更正（第 1、2 条）。

---

## 2. 用户故事

- **US-1 CR 流程的操作者（任意 Runtime 下的 Agent 使用者）**：作为让 Agent 反复检索与读文件的人，我希望无界搜索、递归列举和整文件打印在**结果进入模型上下文之前**就被收窄成「唯一文件列表 / 连续行窗口 + 下一次 offset」，这样我不再为同一份噪音付两轮 token，而且模型永远知道自己是拿到了完整结果还是切片。
- **US-2 需要全量证据的 Agent**：作为确实要看完整生成文件的执行者，我希望有一条一次性的、必须写明原因的逃生阀（首行 `# output-guard: full reason=…`），这样取证不会被护栏卡住，而逃生阀也不会变成绕过安全控制的永久后门。
- **US-3 crctl 的调用方（Skill / 脚本 / 评审者）**：作为调 `crctl status/next/validate/checkpoint` 的人，我希望默认看到的是 compact summary、需要完整字段时显式加 `--detail`，这样高频命令不再为缩进和全量投影付费，而退出码与错误码和我原来依赖的字段一个都不变。
- **US-4 Reviewer / gate 消费者（quality-reviewer-agent）**：作为做最终判断的人，我希望 `complete=false` 的切片结果**明确不可作为充分门禁证据**，系统要求我继续按 offset/limit 取证或走逃生阀，这样裁剪不会把「取证不足」伪装成「已核对」。
- **US-5 运行环境的安装者（Ray / 企业部署者）**：作为把 Tools 装进各 Runtime 的人，我希望缺失或损坏时系统**显式 fail-open 并告诉我 coverage=unavailable**，只报告、不静默安装或修复，这样我永远不会以为护栏在生效而实际没有。
- **US-6 成本决策者（Ray）**：作为决定要不要继续投入 FR-3～FR-7、FR-9 的人，我希望有一份和真实账单对齐、按归一化指标（tokens/CR、会话数/CR）表达的 before/after 对照，以及「目标桶下降 ≥20% 且三项质量护栏全部不恶化」的机械门槛，这样扩项与否不再靠感觉，也不会用 token 下降换返工增加。
- **US-7 本 CR 的评审者**：作为核对本 CR 的人，我希望逐条确认「CR 阶段 / 门禁 / 审批 / Git / 账本 / 事务六类语义零改动」与 `tool_output_preview.go` 零 diff 成立，确认没有第二套事务框架、没有复制 policy、没有把候选 Backlog 偷偷做进当前 TASK。

---

## 3. 功能需求

> 编号沿用来源 FR 编号；FR-3～FR-7、FR-9 是候选 Backlog 占位，本 CR 不定义（§7）。每条 FR 的行为后括注来源小节。

### FR-8 离线成本与质量度量〔来源 §5〕

**定位**：只回答三个问题——FR-1/FR-2 是否真的降低单位 CR 成本、是否以取证不足/缺陷后移/返工增加换取 token 下降、是否值得继续启动候选 FR（来源 §5.1）。它**不推进 CR、不参与门禁、不写状态、不写账本**（§5.1、Q11）。

1. **实现位置与执行次数**：新增只读度量脚本（建议 `AI-First-tools/skills/shared/metrics/scripts/cr-cost.mjs`）；本 CR 内**只执行两次**——改造前（历史日志生成 `baseline.json` + 对历史 session 离线回放 OutputGuard policy）与部署后（14 天窗口生成 `after-fr1-fr2.json` 与前后差异摘要）。不新增 Pipeline 节点、Skill 步骤、Agent 收尾动作、定时任务、数据库或仪表盘；部署后报告**不是代码合并门禁**（§5.2、Q11、Q25）。
2. **输入（全部只读复用）**：既有 session 工具调用与结果、既有 CR-ID / task / run / session 标识、Provider usage 的 `input` / `cachedInput`|`cacheRead` / `cacheWrite` / `output`、既有 Pipeline 与评审数据（门禁一次通过、reviewLoop、评审发现缺陷）、Runtime 启动能力记录与 OutputGuard trailer。不新增采集面（§5.3、Q17）。
3. **输出（单份机器事实）**：机器结果只保留一份 JSON，字段集固定为来源 §5.4：`window` / `sampleCRs` / `coverage{runtime→full|partial|unavailable}` / `providerUsage{input,cachedInput,cacheWrite,output}` / `toolResultTokens` / `k` / `metrics{tokensPerCR,sessionsPerCR,searchTokenRatio,fullReadRatio,bootstrapTokensPerSession}` / `guardrails{firstPassGateRate,reviewLoopsPerCR,reviewDefectsPerCR}`。人读摘要由**同一脚本即时渲染**，不维护第二份事实；报告作为 CI artifact 或 Multica 附件保存，**不进入权威账本**（§5.4、Q32）。
4. **k 与金额口径**：`k = Provider 实际计费金额 ÷ 同区间工具结果 token`；`预计节省金额 = k × 节省的工具结果 token`。用两个完整 CR（一个接近会话数中位数、一个高会话数样本）；必须保留原始 usage 维度与价格来源；**取不到实际计费金额时只报告 token 放大系数，不得宣称真实金额节省**；首期只对 Pi 出成本结论，其它 Runtime 只报覆盖度与裁剪量，**不外推 Pi 的 k**（§5.5、Q8、Q26）。
5. **观察窗口与扩项门槛**：部署后固定 14 天；只统计 `coverage=full` 且带 CR-ID 的完整 Pi CR；样本不足输出 `insufficient-sample`，**不延长当前 CR、不编造结论**；目标桶（搜索/列举/打印 + crctl）`tokens/CR` 至少下降 **20%**，且 X-5 三项质量护栏（门禁一次通过率、reviewLoop/CR、评审阶段发现缺陷数）**全部不恶化**；只有满足该条件才允许重新立项评估 FR-3～FR-9（§5.6、Q28、Q34）。
6. **可复现性**：样本筛选规则（目录、文件类型、时间窗、CR-ID 归属）必须作为脚本输出的一部分可复现，且重跑得到同一集合；比较只用归一化指标，不比较绝对总量（来源 §4 末 + §1.4 事实 12）。

### FR-1 通用 OutputGuard（无状态 Core + Runtime 薄 Adapter）〔来源 §6〕

**定位**：唯一 seam 是「工具结果进入下一轮模型上下文之前」（§6.1）：`Runtime 原生工具调用 → Runtime Adapter(Pre/Post hook) → OutputGuard Core → 裁剪后的模型可见结果 → Runtime/Multica transcript`。**只修改 Multica daemon 的 transcript/preview 不满足本需求**（§1.4 事实 8）。

1. **职责切分**：`core.mjs` = 纯函数、无状态规则求值与确定性裁剪；`policy.json` = 阈值/命令族/裁剪/提示规则的**唯一事实源**；`capabilities.json` = 各 Runtime 的 full/partial/unavailable 声明；`conformance.json` = 跨 Adapter 共用测试向量；**Adapter 只做 Provider hook 输入输出映射**，不复制 policy、不做业务判断、不独立版本演进（§6.2、Q9、Q32、§2 表）。
2. **首期命令族（可判定范围）**：只治理实测高消耗命令 `grep`/`rg`、`find`、`Get-ChildItem`、`cat`、`Get-Content`。不实现完整 Bash/PowerShell 解析器：能确定违规 → 执行前拒绝或施加上限；无法确定 → 允许执行但结果仍受统一输出封顶；不解析任意管道、重定向、脚本嵌套；后续扩族只能依据 FR-8 数据（§6.4、Q16）。
3. **阈值来源**：任何阈值都不写进 PRD、Prompt、Skill 或代码常量，一律由 TASK-01 基线产出后写入 `policy.json`（§6.4 末、Q5）。
4. **裁剪策略（确定性、非语义）**：搜索/列举 → 唯一文件列表 + 总命中数 + 可执行的缩小范围写法；文件读取 → 连续行窗口 + 原始行号 + 提示下一次 `offset/limit`；普通 shell → 保留头尾 + 中间显示省略量。**不调用 LLM 摘要、不做语义压缩**（§6.5、Q19）。
5. **门禁证据不变量（硬）**：每个被裁剪结果必须显式标 `complete=false`，不得伪装完整；只允许改结果正文，必须保留 `toolName`、`toolCallId`、`isError`、`exitCode` 与 Runtime 要求的结果结构；某条 Runtime 路径无法安全保持上述字段/结构 → **不得裁剪**并把该路径标 `coverage=unavailable`；被丢弃正文不得进入下一轮模型上下文；`complete=false` 的结果**不是充分门禁证据**，Reviewer/gate/审批不得据此作最终判断，作最终判断前必须继续按 `offset/limit` 切片取证或走逃生阀取完整结果（§6.5.1，落地 AC-15、AC-16）。
6. **幂等（确定性四查之「幂等」）**：Core 是纯函数，决策指纹 = `(policyVersion, 命中规则标识, toolName, 规范化后的调用参数, 原始结果正文)` 的固定组合；同一指纹 + 同一 policy 版本必须产生**逐字相同**的模型可见结果与 trailer。跨调用零状态：不创建授权文件、nonce、永久开关或「下一次调用」状态；重复调用同一命令得到同构结果（§6.2、§6.6、Q18）。
7. **权限与判定顺序（确定性四查之「权限」）**：固定顺序、每个决定只有一个终态，无并列——
   ① Runtime 自身工具执行权限与既有安全控制（crctl controlled-shell 白名单 `skills/shared/controlled-shell/rules.json`、protected paths、审批、账本写入控制）**先于 OutputGuard**，OutputGuard 既不评估也不放宽，逃生阀同样不能绕过它们；
   ② 解析首行逃生阀标记：合法（`# output-guard: full reason=<单行、限长>`）→ 本调用 `action=passthrough` 并跳过封顶；不合法 → **视为不存在该标记**（§1.5 第 5 条），不拒绝调用、不新增 action 取值；
   ③ 调用前可判违规 → `action=block`（拒绝并给替代写法）或 `action=rewrite`（施加上限后执行）；
   ④ 结果侧 → 按第 4/5 项裁剪得到 `action=truncate`，或字段不可保持 → 不裁剪并标该路径 unavailable；
   ⑤ 以上均未命中 → 不追加任何文本（§6.7）。
   终态取值集合固定为 `{block, rewrite, truncate, passthrough, unavailable}`，`unavailable` 只由第 8 项的降级面产生。
8. **错误闭包（确定性四查之「错误闭包」）**：唯一降级码为 `OUTPUT_GUARD_UNAVAILABLE runtime=<runtime> reason=<ADAPTER_MISSING|DISABLED|BUNDLE_INVALID|POLICY_INVALID>`（reason 枚举闭包，四值，不新增）。任一命中时：原工具调用继续、结果不修改（**显式 fail-open**）；FR-8 标 `coverage=unavailable`；该会话不进入完整覆盖效果样本；不静默假装生效；不让 Agent 退化为 Prompt 自觉；**不影响 crctl / Git / 账本 / 审批的 fail-closed 行为**。错误路径零文件写入、零状态变更、无补偿事务（§6.9、Q20）。
9. **副作用面（确定性四查之「副作用」）**：OutputGuard 唯一可见副作用是「模型可见结果正文 + 一行 trailer」与「Runtime 启动日志一行 `output-guard runtime=… coverage=… policy=v1`」。被丢弃正文只在 Adapter 内存短暂存在，裁剪后立即丢弃；下一轮上下文、session、Multica transcript 与日志只接收裁剪结果；度量只记原始/保留 token 数不存正文；使用逃生阀时完整输出按正常工具结果进入会话。不新增 JSONL、sidecar、数据库或 CR 台账（§6.7、§6.8、Q31）。
10. **发布与安装**：Core + `policy.json` + `capabilities.json` + `conformance.json` + 五个 Adapter 属**同一个 Tools Release**，原子发布、原子升级；Adapter 从同一 Release 的**相对路径**读取 policy，不复制到其他目录独立维护；不提供单独 Adapter 升级命令；`policyVersion` 只表示格式版本，不建多版本兼容/迁移框架；运行中的会话用启动时版本、新会话用新版；启动检查**只报告缺失/损坏并给出明确修复命令，不静默安装或修复**；独立使用 Tools 时 Adapter 由用户/管理员在启用 Tools 时显式安装一次，不在 CR 过程中安装；scope 分级 Project（首期试点）/ User（开发者机器全项目）/ Managed（企业统一部署）（§6.10、Q15、Q21、Q33）。
11. **上线与启用顺序**：不建长期 shadow mode，上线前用历史 Pi session 离线回放 policy 并抽检误伤；实现五个 Adapter，启用顺序固定 `Pi → Claude → CodeBuddy → Qoder → Codex(partial)`，前一个 Runtime 完成 conformance、真实冒烟与降级验证后才启用下一个；这是部署顺序，**不新增 CR 状态或 Pipeline 节点**（§6.11、Q22、Q24）。
12. **回滚粒度**：单 Runtime Adapter 误伤 → 只禁用该 Adapter（新会话生效），其它 Runtime 保持启用；Core/Policy 共性错误 → 整体回退 Tools Release；阈值过严 → 改 `policy.json` 并随完整 Release 发布；**不建远程动态开关，安装配置就是启用开关**（§10、Q29）。

### FR-2 crctl 输出瘦身（仅呈现层）〔来源 §7〕

1. **选择规则**：先由 FR-8 基线按命令聚合 crctl 输出 token，选出**覆盖 ≥80% crctl 输出 token 的最小命令集合**；只为该集合增加**独立的 summary projector**，默认输出 compact summary JSON，`--detail` 返回原完整字段。禁止在全局 `ok()` 中粗暴删除所有命令字段（§7.1、§7.2、Q30）。
2. **开关面收敛**：不新增无意义的 `--output json`、`--verbose`、`--pretty` 平行开关（现状该四个 flag 零存在，§1.4 事实 7）；既有机器调用方若依赖完整字段，**显式补 `--detail`**（§7.2 第 6/7 条）。
3. **幂等与无权限分支**：`--detail` 是纯呈现层开关——不参与任何状态判定、门禁、审批或 CAS 判定，不加权限分支，不改退出码；同一命令在相同仓库状态下重复调用，`--detail` 输出恒等。
4. **错误闭包**：所有错误路径（247 个 `fail(` 出口）保持既有错误码、错误体与非零退出，**不进入 summary 投影**；未知/新增错误码禁止借本 CR 引入。
5. **不变量（来源 §7.3）**：命令退出码不变；错误码、字段语义和失败信息不变；状态、门禁、审批、CAS、事务和 Git 行为不变；`--detail` 业务字段与旧完整输出等价（等价定义见 §1.5 第 6 条）；既有测试全绿并增加 summary/detail 合同测试。
6. **同 CR 义务**：新增 summary/detail 合同测试后，其所属测试文件的 `gate-registry.json#manifest.cases` 登记基线必须在同一 CR 内同步为实际用例数（棘轮只挡回退，不登记即等于新合同无回归保护），且不签任何新例外（§1.5 第 7 条、AC-21）。
7. **不做**：不优化 crctl 运行时小文件读取、不治理历史上从未读取的大文件、不建 crctl 字段/错误码事实页与 CI 新鲜度（那是候选 FR-9，§7）。

### 关于「FR-0」的不存在声明

来源与本 CR 均无 FR-0；Issue 标题中的「FR-0/1/2」按 §1.5 第 1 条更正为「FR-8 + FR-1 + FR-2」。评审若需范围核对，以 §1.3.1 原文前缀为准。

---

## 4. 非功能需求

- **NFR-1 语义零改动（最重要，来源 §1 / §3.1 / AC-1）**：CR 阶段、门禁（passCondition）、审批、Git/worktree、账本 schema 与事务语义**全部不变**。不新建事务协调器 / WAL / CAS 层 / Git 提交框架；不拆分或重构 `workspace-transactions.mjs`；`durable-tx.mjs` 无第二套实现；不在 Skill、Adapter 或度量脚本中手写账本；不复制 passCondition、状态映射或 reviewLoop 算法（判据 AC-1、AC-2）。
- **NFR-2 单一事实源**：`policy.json` 是 OutputGuard 阈值唯一事实源；`capabilities.json` 是 Runtime 能力唯一事实源；`conformance.json` 是跨 Adapter 合同唯一事实源；FR-8 机器 JSON 是成本事实唯一机器源；README 只提供总览与权威入口链接，**不复制 policy、hook 细节或完整能力矩阵**（AC-3、AC-13、Q32）。
- **NFR-3 确定性与可复现**：Core 纯函数（同输入同输出）；不调用 LLM 摘要、不做语义压缩；FR-8 样本筛选规则可复现、重跑同集合；度量比较只用归一化指标（AC-3、AC-17）。
- **NFR-4 隐私**：被裁剪正文只在内存短暂存在，裁剪后立即丢弃；不落盘、不进 transcript、不进新增日志；度量只记 token 数不记正文（AC-7）。
- **NFR-5 可观测但不建台账**：唯一观测面是拒绝/裁剪时的一行稳定 trailer 与启动时一行能力记录；不新增 JSONL、sidecar、数据库、仪表盘或 CR 台账；FR-8 全部从既有 session 与启动记录派生（AC-7、AC-17）。
- **NFR-6 降级诚实性**：缺 Adapter / 禁用 / bundle 损坏 / policy 解析失败一律**显式** fail-open 并标 `coverage=unavailable`；不得伪装 full、不得静默安装或修复、不得让 Agent 退化为 Prompt 自觉；同时不得削弱 crctl/Git/账本/审批的 fail-closed（AC-8、AC-4）。
- **NFR-7 兼容性与 CI**：`../tools` 全量既有测试与 CI（`lint-prompts` enforce、skill matrix、agents contract、pipeline 结构断言、`suite-gate --run`、writeback 单测）保持绿；`gate-registry.json#exceptions` 保持空数组；新增用例的登记基线同 CR 同步（AC-11、AC-21）。
- **NFR-8 语言与行尾纪律**：tools 与 KB 文档产物用中文，multica 仓代码注释一律英文；任何对仓库文件做哈希/跨行正则/逐行解析的度量与测试代码，读入后必须先 `\r\n → \n` 归一、解析用 `split(/\r?\n/)`、匹配失败硬报错（禁止「匹配不到→空集→静默通过」）；来源证据文件的「与附件一致」断言一律写成 EOL 归一后一致（§1.4 事实 15、16）。
- **NFR-9 可回滚性**：五个 Adapter 各自独立提交、可单独禁用回滚；Core/Policy 共性错误回退整个 Tools Release；无远程开关、无补偿流程（AC-14、§10）。

---

## 5. 验收标准

> AC-1～AC-16 与来源 §9.1「合并前硬验收」一一对应（编号沿用，便于追溯）；AC-17～AC-21 为本 PRD 新增（覆盖来源正文有要求但 §9.1 未列成验收的面），逐条标注。

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-1/FR-2/FR-8（边界） | §9.1 AC-1 | 逐项核对零改动：CR 状态机（`dir-graph.yaml#state_machine` 状态数与转换集不变）、各 pipeline `reviewLoop.passCondition`、四类审批（requirement/tech-design/dev-start/code）、账本 schema（`cr.md` frontmatter / `_backlog.yml` / `traceability.yml` / `tasks/_index.yml`）、Git/worktree 与事务行为。交付 diff 中上述文件（除 `crctl.mjs` 的成功输出投影层）零变化。 |
| AC-2 | FR-1/FR-2（不造轮子） | §9.1 AC-2 | `lib/durable-tx.mjs`、`lib/workspace-transactions.mjs` 零 diff 或仅**消费式引用**（不新增实现、不拆分）；全 diff 中不出现第二套锁/journal/write-set/CAS/提交框架；Skill、Adapter、度量脚本中无手写账本代码；无复制的 passCondition/状态映射/reviewLoop 算法。 |
| AC-3 | FR-1 | §9.1 AC-3 | Core 对同一输入（§FR-1 第 6 项指纹）产生逐字相同结果（合同测试断言）；`policy.json`/`capabilities.json`/`conformance.json` 是阈值/能力/合同的唯一读取源——全 diff 中无第二份阈值副本、无硬编码阈值常量、PRD/Prompt/Skill 内不出现具体阈值。 |
| AC-4 | FR-1 | §9.1 AC-4 | Pi、Claude、CodeBuddy、Qoder 四个 Adapter 通过 `conformance.json` 的 full 向量；Codex 按其 partial capability manifest 逐条验证支持项、uncovered 路径（含 hosted `WebSearch` 等特殊路径）被显式标记为不生效。测试输出可区分 full/partial/unavailable，无「宣称 full 但向量缺失」。 |
| AC-5 | FR-1 | §9.1 AC-5 | 无界搜索、递归列举、全文读取被拒绝或收窄时，模型可见结果中**必须包含可执行的缩小范围替代写法**（搜索/列举→唯一文件列表+命中数+写法；读取→下一次 `offset/limit` 具体值），逐命令族测试断言替代写法存在且格式合法。 |
| AC-6 | FR-1 | §9.1 AC-6 | 逃生阀只影响当前调用（无跨调用状态、无授权文件/nonce/永久开关）；`reason` 必填单行限长；不合法标记按「视为不存在」处理（§1.5 第 5 条）；**逃生阀不能绕过** Git 白名单、protected paths、审批、账本写入控制（四类各一条负向测试）。 |
| AC-7 | FR-1 | §9.1 AC-7 | 被裁剪的原始正文不出现在：下一轮模型上下文、session 文件、Multica transcript、任何新增日志（sentinel 端到端验证，见 AC-15）；不产生任何新增 sidecar/JSONL/DB 落盘。 |
| AC-8 | FR-1 | §9.1 AC-8 | 无 Adapter / Adapter 禁用 / bundle 损坏 / policy 解析失败四场景均显式 fail-open（原调用继续、结果不改），输出 `OUTPUT_GUARD_UNAVAILABLE` 且 `reason` 落在四值枚举内；FR-8 侧该会话标 `coverage=unavailable` 并排除出完整覆盖样本；无静默安装/修复副作用。 |
| AC-9 | FR-1/FR-8 | §9.1 AC-9 | 历史 session 离线回放完成并产出 `baseline.json`（含可复现筛选规则与实际样本数）；合法调用抽检**零误伤**（抽样清单与判定入证据）。 |
| AC-10 | FR-2 | §9.1 AC-10 | 默认输出为 compact summary，且被投影的命令集恰为基线选出的最小集合（覆盖 ≥80% crctl 输出 token，命令清单来自 TASK-01 输出）；同一命令加 `--detail` 的字段集合与改造前完整输出**逐字段等价**（合同测试按字段集合比对，§1.5 第 6 条）。 |
| AC-11 | FR-2 | §9.1 AC-11 | 逐命令比对：退出码不变；错误码与错误体不变（`fail(` 出口零语义变更）；状态推进、门禁、审批、CAS、事务、Git 行为不变；`../tools` 既有测试全绿。 |
| AC-12 | FR-1（seam 边界） | §9.1 AC-12 | `AI-First-multica/server/internal/daemon/tool_output_preview.go` **零 diff**（以 `git diff` 对该路径断言为空）。 |
| AC-13 | FR-1/FR-2 | §9.1 AC-13 | README 只有流程总览与权威入口链接，**不复制** policy 内容、hook 细节或完整能力矩阵；出现任一复制即 fail。 |
| AC-14 | FR-1 | §9.1 AC-14 | 每个已启用 Runtime 至少一次真实冒烟，覆盖四类行为：拒绝、裁剪、逃生、损坏降级；冒烟记录作为交付证据（不作为成本结论依据）。 |
| AC-15 | FR-1 | §9.1 AC-15 | 在待丢弃区域放置唯一 sentinel，端到端验证该 sentinel **未进入**模型可见 `tool_result`，同时 `toolName`、`toolCallId`、`isError`、`exitCode` 与结果结构全部保留；任一字段丢失即该路径不得裁剪并标 unavailable。 |
| AC-16 | FR-1 | §9.1 AC-16 | 以 `complete=false` 结果尝试完成 Reviewer/gate/审批判断时，系统必须要求继续切片取证或使用逃生阀取完整结果，**不得接受为充分门禁证据**（至少一条端到端用例证明该拦截存在）。 |
| AC-17 | FR-8（**本 PRD 新增**） | §5.2/§5.4/§5.6 | ① FR-8 在合并前与部署后各恰好执行一次，全 diff 中不出现新 Pipeline 节点 / Skill 步骤 / 定时任务 / 仪表盘 / 数据库；② 机器结果只有一份 JSON 且字段集 ≡ §5.4 列表，人读摘要由同一脚本渲染（无第二份产物文件）；③ 样本数由脚本输出，代码与门禁中不出现 672 等硬编码样本常量；④ 报告以 CI artifact 或 Issue 附件形式存在，CR 权威账本（四账本）零变化；⑤ 14 天窗口、`insufficient-sample` 分支与「目标桶 ≥20% ∧ 三护栏不恶化」判定为脚本内可测函数，样本不足时输出 `insufficient-sample` 且不产出成本结论。 |
| AC-18 | FR-8（**本 PRD 新增**） | §5.5 / Q8、Q26 | ① `k` 的输出必须同时给出实际计费金额来源与同区间工具结果 token 分母；② 缺金额时输出中 `k` 为空/标记不可得且**不出现任何金额节省宣称**；③ 非 Pi Runtime 报告只含覆盖度与裁剪量，无外推成本；④ 原始 usage 四维（input/cachedInput/cacheWrite/output）维度值保留可核。 |
| AC-19 | FR-1（发布，**本 PRD 新增**） | §6.10 / Q15、Q21、Q33 | ① Core+三份 JSON+五 Adapter 在同一 Release 单元内交付，Adapter 以相对路径读同一 Release 的 policy（无复制目录）；② 不存在单独 Adapter 升级命令与多版本兼容/迁移框架；③ 启动检查只输出缺失/损坏与修复命令，无自动安装/改写用户配置行为（负向测试）；④ 安装 scope 三级可区分。 |
| AC-20 | FR-1（启用顺序，**本 PRD 新增**） | §6.11 / Q22、Q24 | ① 启用顺序记录可核对：每个 Runtime 的启用都以「该 Runtime conformance 通过 + 真实冒烟通过 + 降级验证通过」为前置，前一项未过则后一项不得启用；② 该顺序不引入任何 CR 状态或 Pipeline 节点（AC-1 联测）；③ 不建长期 shadow mode，误伤检查由历史 session 回放承担。 |
| AC-21 | FR-2（调用方与测试棘轮同步，**本 PRD 新增**） | §7.2 第 7 条 / §1.5 第 7 条 | ① 扫描到的全部真实既有 `crctl` 调用方（Skill 文本、pipeline prompt、脚本、测试）在同一 CR 内更新：需要完整字段者显式带 `--detail`，无因字段缺失而失败的调用方；② 新增 summary/detail 合同测试所属文件的 `gate-registry.json#manifest.cases` 登记基线已同步为实际顶层用例数（同步前后 `suite-gate --run` 均绿，且新增用例数不落在登记面之外）；③ `exceptions` 保持空数组，未签任何新例外。 |

---

## 6. 成功指标

**成本主指标（归一化，来源 §5.6）**

- 目标桶（搜索 / 列举 / 打印 + crctl 命令输出）`tokens/CR` 相对 `baseline.json` 下降 **≥ 20%**（14 天窗口、只计 `coverage=full` 且带 CR-ID 的完整 Pi CR）。
- `sessionsPerCR` 不高于基线；`searchTokenRatio`、`fullReadRatio` 下降；`bootstrapTokensPerSession` 不因此项改造而上升。
- 折算口径：`预计节省金额 = k × 节省的工具结果 token`；k 不可得时只报 token，不报金额（AC-18）。

**质量护栏（X-5，三项必须全部不恶化）**

- `firstPassGateRate`（门禁一次通过率）不下降；
- `reviewLoopsPerCR` 不上升；
- `reviewDefectsPerCR`（评审阶段发现缺陷数）不下降。

任一恶化 → 按来源 §10 回滚对应措施（单 Adapter 禁用 / 整体回退 Release），不新增补偿流程。

**取证完整性护栏（不得被 token 下降换掉）**

- 因 `complete=false` 被当作充分门禁证据而通过的判断次数 = 0（AC-16）；
- sentinel 泄漏到模型可见 `tool_result` 的次数 = 0（AC-15）；
- 合法调用被误伤次数 = 0（AC-9）；
- 降级被静默（无 `coverage=unavailable` 记录）的会话数 = 0（AC-8）。

**治理面零退化指标**

- 状态机状态数与转换数变化 = 0；Pipeline 节点数保持 5/4/12；
- 新增账本字段 / 数据库表 / 仪表盘 / sidecar 日志 / 远程开关 / 事务框架 = 0；
- `gate-registry.json#exceptions` 长度 = 0；既有测试回归失败数 = 0；
- `tool_output_preview.go` diff 行数 = 0；`durable-tx.mjs` / `workspace-transactions.mjs` 新增实现行数 = 0。

**扩项决策输出**

- 只有目标桶 ≥20% 且三护栏全不恶化，才立项评估 FR-3～FR-7、FR-9；否则以 `after-fr1-fr2.json`（或 `insufficient-sample`）作为不再投入的书面依据。

---

## 7. 范围排除

**候选 Backlog（来源 §12 / Q35：编号保留，本 CR 不实施、不得借本 CR 扩大范围）**

- **FR-3** SKILL.md 核心/附录分层（延后；不得在当前 TASK 顺手实施）；
- **FR-4** CUSTOM/AGENTS/README/architecture 指引分层；
- **FR-5** Pipeline/gates/注册面定位摘要页（不得复制 passCondition）；
- **FR-6** 跨会话交接卡（如实施须保持非权威投影）；
- **FR-7** PRD/SDD 稳定锚点与任务相关节（涉及受控写路径，须另行确认）；
- **FR-9** crctl 字段/错误码/命令面事实页及 CI 新鲜度（如实施须复用现有生成/digest 机制）。
- 以上六项的唯一启动前置是 §5.6 / AC-17 的收益门槛，门槛未过即不重新立项。

**架构与非目标（来源 §11 逐条）**

- 不实现 Agent / Pipeline / Skill / crctl 的架构重构；不把固定 `architecture-design` Runner（`governance/runner.go`）泛化为通用工作流引擎；
- 不修复所有存量 Prompt 重复，只要求本次不新增越界；不把检索纪律仅写入 Skill/Prompt 作为主要手段；
- 不新增状态、门禁、审批或 CR 生命周期节点；不新增账本、数据库、仪表盘、sidecar 日志、WAL、CAS 或事务框架；不建测试与夹具族索引；
- 不修改 Multica daemon preview；不实现完整 Bash/PowerShell parser；不调用 LLM 做输出摘要；
- 不自动安装 Provider、不重试失败工具调用、不修复 Runtime；不要求所有 Runtime 具有相同能力；
- 不优化 crctl 运行时小文件读取；不拆分 `workspace-transactions.mjs`；不治理历史上从未读取的大文件；不通过合并相邻会话解决 bootstrap；
- 不建长期 shadow mode；不建远程动态开关（安装配置即启用开关）；不建 policy 多版本兼容/迁移矩阵。

**明确不并入的既有资产（判据 AC-1 / AC-2 / AC-12）**

- crctl 状态机、`gates.json`、CAS/durable 事务、`reviewLoop`/`replayNodes`/`maxAttempts`、controlled-shell `rules.json`、writeback 版本化脚本与 digest/manifest 校验、`skills/shared/crctl/scripts/test/**` 既有断言语义；
- `skills/shared/crctl/adapters/**` 既有 crctl 守卫适配器与 OutputGuard 适配器**不得合并为同一配置事实源**（§1.5 第 8 条）；
- `../multica` 的 `tool_output_preview.go`（零 diff）、`governance/runner.go` 切片语义、Provider 事件归一化行为；
- KB 的 `specs/`、`delivery/`、`docs/`（含只读的历史分析文档）与受控账本的手工编辑。

## Agent Skill 路由与 Pi bash 默认超时：评审无限阻塞最小治理（v0.43 · CR-2026-070）

## 1. 概述

### 1.1 问题陈述

需求来源是 Issue **AIFI-33** 附件《CR需求来源_Agent_Skill路由与Pi工具默认超时_收敛版.md》（17,049 B，附件 id `01a0b04e-58a0-75e8-b98a-bda8970e573f`），已登记在 `change-requests/CR-2026-070/sources/`。AIFI-33 只有收敛版一份附件，无原始演进版本。**本 PRD 的一切范围判定以该收敛版为唯一权威**（来源 §1、§11）。

事故事实（来源 §2.1～§2.2，均发生在 AIFI-32 / CR-2026-069 期间）：

| 项目 | 第一次 | 第二次 |
|---|---|---|
| 节点 | `review-requirement` | `review-dev-plan` 复评 |
| 触发行为 | 猜测 `~/.multica/skills` 失败后执行根目录搜索 | 全局 `~/.pi/agent/skills` 未找到 workspace Skill 后执行根目录搜索 |
| 命令 | `find / -maxdepth 6 -type d -name "review-requirement" ... \| head -20` | `find / -name "SKILL.md" -path "*review-dev-plan*" ... \| head -20` |
| CPU | 约 1110 秒 | 约 1350 秒 |
| 阻塞时长 | 约 18 分 38 秒 | 约 22 分 38 秒 |
| 恢复方式 | 人工终止精确子进程 PID，同一 Agent run 恢复 | 同上 |

共同根因链（来源 §2.3）：Runtime 已注入并原生发现 Skill → Agent 没有直接使用已发现 Skill → 用 Shell 猜路径 → 猜测失败后执行 `find /` → bash 调用未显式传 timeout、Pi 当前无默认 timeout → 工具调用无限等待，Agent 无法进入下一轮。两次均发生在读取 Issue 上下文后、首次加载当前 `review-*` Skill 的阶段，**属可重复路径，不是偶发故障**。

不属于本需求的问题（来源 §2.4）：另一次 dev-agent「疑似卡住」经核实是 `suite-gate` 正常执行（显式 `timeout: 1200`，同一命令两次耗时约 876/878 秒，命令自行正常返回），属长命令进度展示，不在本 CR 范围。

### 1.2 解决方案摘要

以最小改造消除同类无限阻塞，只做两件事，其余全部复用既有能力：

1. **FR-1**：在 Multica 单一的共享 Skills brief 中增加一条 Provider-neutral 的 Agent 行为约束——已列出的 Skill 是权威入口，选定后直接使用 Runtime 原生发现结果；预期 Skill 不可用时立即技术中止，不猜路径、不做文件系统兜底搜索。
2. **FR-2**：在 Pi 内置 bash 的**现有** timeout 解析点补一个 300 秒默认值，未显式传 timeout 时生效，显式值继续覆盖默认值；复用既有 `setTimeout`、AbortSignal、错误返回与跨平台 `killProcessTree()`。

明确不新建第二套系统（来源 §3 各节结论）：不新增 Skill Locator / manifest / 全局注册表 / 路径索引；不新增 Shell Guard、lexer 或 parser，不改 OutputGuard 行为；不新增状态、错误码、账本字段、metrics、数据库、sidecar、事务框架；Pipeline、四类 `review-*` Skill、crctl、版本化转换脚本与审批合同零业务改造；不修改、不重开已归档的 CR-2026-069。

### 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

#### 1.3.1 scope_in 边界（原文前缀，评审核对用）

逐条标注**逐字出处**（评审核对用；本版按需求评审 S-5 回修改正第 1～2 条的出处）：

- 「在 Multica 单一共享 Skills brief 中要求 Agent 直接使用 Runtime 原生发现的 Skill、缺失时技术中止」（cr.md summary 逐字；同义展开见来源 §5）
- 「在 Pi 内置 bash 的现有 timeout 解析点增加 300 秒默认值」（cr.md summary 逐字；同义展开见来源 §6）
- 「不得通过 Shell 或文件系统递归搜索 `SKILL.md`」与「未显式传入 timeout 的 Agent bash 调用使用 300 秒默认值」（来源 §1 首项、次项逐字；初稿第 1～2 条把这两句当作 cr.md summary 原文，属出处标错，本版改正）
- 「不新增 Skill Locator、Shell Guard/parser、错误码、metrics、数据库、sidecar、Pipeline 节点、账本或事务框架，不修改已归档 CR-2026-069 的 OutputGuard 合同」（cr.md summary）
- 「本需求不重新打开已归档的 CR-2026-069，作为独立后续 CR 注册」（来源 §1 末段）
- 「不关联其他CR、版本延续、负责人都是Ray」（AIFI-33 Issue 正文）

#### 1.3.2 目标仓库与版本

| 项 | 值 | 依据 |
|---|---|---|
| target-version | `0.43` | 版本延续：`specs/_index.yml` current = `0.42`、cr-ref = CR-2026-069（已归档），CR 序列最新为 CR-2026-069，下一个未占用版本为 0.43 |
| target-spec-id | `ai-first-platform` | 与 CR-2026-060～069 同一 spec 的后续演进 |
| origin | 空 | 本 CR 是独立后续 CR，不是修复某个已归档 CR 的缺陷（来源 §1 明示「不重新打开 CR-2026-069」） |
| 关联 CR | 无 | Issue 正文明示「不关联其他CR」 |
| FR-1 落点仓 | `multica`（`../multica`，dir-graph repositories 已声明为参与仓） | 唯一写入点在 `runtime_config_sections.go` 的共享 Skills brief |
| FR-2 落点仓 | Pi 包 `@earendil-works/pi-coding-agent` 的**版本化源码**（具体仓与发布路线 = 需求期待定项，见本节下方三条候选） | 不在本 workspace `dir-graph.yaml#repositories` 声明的三仓内，且本团队当前**没有**该包的既有发布路径（§1.4 事实 9）；本机已安装版本 0.85.1 只作现状证据，不是交付目标（§1.4 事实 5、FR-2 交付边界） |

FR-2 的落点仓不在 CR 参与仓集合是本需求的既有事实，不是本 PRD 新造的依赖：**不得**以「改不动」为理由退化成 patch 本机 `dist`（来源 §6.2 明令禁止），**也不得**在需求期私自修改 `dir-graph.yaml` 扩充参与仓。

**交付路线是需求期显式待定项（需求评审 B-1 回修）**：初稿此处写「开发计划阶段按实际 Pi 源码仓位置与**既有依赖发布路径**完成最小拆分」，预设了 Pi 已存在一条既有发布路径；本轮核实该前提不成立（§1.4 事实 9）。本版改为把三条候选路线连同各自所需权限与证据列出，由开发计划（`write-dev-plan`）选定并在 SDD 中写明「选定路线 + 被升级版本的产出方 + 升级动作时点」；需求期不替开发计划拍板，也不承诺任何一条路线。

| 候选路线 | 需要的权限（当前状态） | 需要的证据 | 对交付 diff 的影响 |
|---|---|---|---|
| R-A 自建 fork，并由本团队可控位置发布 | 本团队侧的 Git 建仓/推送权；一个本团队有发布权的 npm scope 或私有 registry 凭据（本机 `npm whoami` 实测 `ENEEDAUTH`，即当前无 registry 登录） | fork 仓 URL + 提交 SHA + 发布产物版本号与发布记录 | Pi 侧改动落在 fork 的版本化源码与测试，可完整纳入 CR 交付 diff |
| R-B 向第三方上游 `earendil-works/pi`（源码克隆地址 `pi-mono`，见 §1.4 事实 9）提 PR，等上游发版后升级 | 上游接受该 PR 并发版，时点不受本团队控制 | 上游 PR/commit 链接 + 上游发布的版本号 + 运行环境升级到该版本的安装记录 | 本 CR 只能交付 PR 侧源码改动；AC-5～AC-8 的运行环境侧验证要等上游发版后才可执行 |
| R-C 版本化源码本地构建后覆盖本机安装 | 一份 Pi 源码检出（当前 `C:\Users\GOBAO\Downloads\AI` 下不存在，须先按 R-A/R-B 建立）＋本机全局安装权限（现装位置 `D:\tools\npm-global\`） | 源码仓 URL/SHA + 构建命令与产物 + 安装方式说明 | 改动仍须**先**落在版本化源码与测试；构建与安装属运行环境动作，不进交付 diff |

三条路线共用的边界（不随路线选择变化）：

1. **不得**以直接编辑已安装包的 `dist` 文件作为改动载体或交付内容（来源 §6.2）。R-C 与「patch dist」的区分只有一条：改动是否**先**出现在版本化源码及其测试里。
2. Multica Runtime 的升级动作（替换 PATH 上的 `pi` 可执行文件）**一律发生在 CR 合并之后**，属运行环境维护，不是 CR 交付 diff 的一部分；本 CR 内不修改 Multica 侧任何依赖声明——该仓对本包本就无依赖声明可改（§1.4 事实 9）。
3. AC-12 的判据与路线选择解耦（路线无关的 diff 判据，见 §5）。
4. 若届时需要把 Pi 源码仓纳入 CR worktree 集合，作为架构期决策提出，不在本 PRD 内预先承诺改 `dir-graph.yaml`。

#### 1.3.3 契约说明（确定性四查适用面）

本 CR 不新增 HTTP API、不新增 CLI 命令与 flag、不新增 Skill 契约，只改一条 Agent 行为约束（FR-1）与一个既有工具调用的默认值（FR-2）。FR-2 定义了 Agent 可调用的工具行为合同，四查按「行为 + 验收 + 引用先例」这一层给出，实现细节归 SDD：

| 查项 | FR-1 | FR-2 |
|---|---|---|
| 幂等 | N/A（无请求指纹；brief 文本为一次性注入） | 同一 `timeout` 输入必得同一解析结果；未传与传 `300` 解析结果等价，其余显式值不等价于默认值 |
| 权限判定顺序 | N/A（无权限分支） | 固定顺序见 FR-2「判定顺序」：非法值 → 超上限 → 合法显式值 → 未传取默认 |
| 错误闭包 | 见 FR-3 失败语义：技术中止 + 不写状态/账本，复用现有运行时/技术中止错误，不新增 `SKILL_NOT_FOUND` | 见 FR-2 超时结果：复用现有 `Command timed out after N seconds`，不新增 `TOOL_TIMEOUT` 类平行错误结构 |
| 副作用与事务边界 | 零 CR 状态、零门禁、零审批、零账本写入 | 只清理本次工具调用的进程树；不产生 CR 侧副作用；无新增持久资源 |

### 1.4 当前事实（落笔前核实）

以下断言均在写入前用命令核实，核实口径为「仓库内存在 / 位置与签名」，不含实现算法评价：

1. **Multica 已完成 Runtime 原生 Skill 注入**：`writeSkillFiles()` 存在于 `server/internal/daemon/execenv/context.go:939`；`context.go:140` 的注释确定 Pi 位置为 `{workDir}/.pi/skills/{name}/SKILL.md`（native discovery）。附属文件写入、slug 冲突、sidecar manifest 记录与清理、保留用户自有 Skill 均由该既有函数承担（来源 §3.1）。
2. **共享 Skills brief 的唯一生成点存在**：`writeSkills` 定义于 `server/internal/daemon/execenv/runtime_config_sections.go:833`，输出 `## Skills` 段（只列 Skill 名称），由同文件 `:1058` 在 brief 组装时调用；其函数注释明示「Names only, deliberately」，理由正是避免形成第二事实源（实测约 3,100 tokens/次、占整份 brief 40%）。该函数与「等价的单一公共 Agent contract」二者之一是 FR-1 的落点。
3. **未发现既有等价且单一的公共 Agent 行为 contract 承载该规则**（本版按 S-1 改为可复现口径）：在 `server/internal/daemon/execenv/` 内按字面短语 `native skill discovery` 复核，非测试代码只命中 `openclaw_config.go:669` 一处注释（原文 `the user loses native skill discovery on that one agent`），其余命中全部位于 `execenv_test.go`；逐 provider 的 Skill 位置注释集中在 `runtime_config.go:158-181`（`InjectRuntimeConfig` 的函数注释，逐 provider 行在 `:161-181`），措辞是 `discovers its environment through its native mechanism` 与 `skills discovered natively from ...`，**不含** `native skill discovery` 这个字面短语（初稿把两者混为一次 grep 命中，字面复核会得到不同命中集，故改正）。两处命中同为说明性注释而非规则正文，**结论不受影响**：来源 §5.2「单一写入点、不得并存两份完整语义」在当时代码中仍是**新约束**而不是既有约束的复述。
4. **OutputGuard 已具备调用前与结果侧治理**（CR-2026-069 归档产物）：`tools/output-guard/` 目录当前含 `core.mjs`、`policy.json`、`capabilities.json`、`conformance.json`、`adapters/`、`test/`（`ls` 核实）。来源 §3.2 断言 `core.mjs` 把含 `|`、`;`、`&&`、`||` 的复合命令判为 indeterminate 并 passthrough，两次事故命令均属该类——**本 CR 不改该合同**，其不变性由 AC-9 的 conformance 复跑取证。
5. **Pi 内置 bash 的唯一缺口确认**（现状证据取自本机已安装 `@earendil-works/pi-coding-agent` 0.85.1 的 `dist/core/tools/bash.js`，读取方式=按行 grep，不作为交付物）：`resolveTimeoutMs(timeout)` 在 `timeout === undefined` 时返回 undefined（`:14-24`）；输入 schema 描述为 `"Timeout in seconds (optional, no default timeout)"`（`:28`）；超时错误文本为 `` `Command timed out after ${timeoutSecs} seconds` ``（`:257`）；非法值错误 `Invalid timeout: must be a finite number of seconds`（`:18`；本版按 S-2 改正行号——初稿写第 19 行，第 19 行是右花括号。判据以 `resolveTimeoutMs` 内的非法值分支为准，dist 行号随版本漂移）；超上限错误 `Invalid timeout: maximum is ${MAX_TIMEOUT_SECONDS} seconds`（`:22`）。与来源 §3.3「现有唯一缺口是 timeout 为 optional，未传入时没有默认值」一致，即本 FR 只需补默认值。
6. **`killProcessTree()` 与 AbortSignal 已存在**：`dist/core/tools/` 内含 `killProcessTree`（Windows 走受信任 `System32/taskkill.exe /F /T /PID`，POSIX 走进程组 `SIGKILL` 并在失败时回退单 PID，来源 §3.3），且 `:71-76` 已有 `setTimeout` + `timeoutHandle` 清理路径。**不另写 cleanup。**
7. **版本与 CR 序列事实**：主 checkout `specs/_index.yml` → `current: "0.42"`、`cr-ref: CR-2026-069`；`change-requests/` 下目录最新为 `CR-2026-069`（`status: archived`），无本需求既有条目，故注册分配 `CR-2026-070`、target-version `0.43`。
8. **三仓 worktree 已 ensure**：`crctl workspace inspect CR-2026-070` → `ai-first-platform-docs`、`multica`、`tools` 均在 `requirement/CR-2026-070` 分支。
9. **Pi 包是第三方上游产物，本团队当前不存在它的发布路径**（需求评审 B-1 回修新增，三处证据）：
   - **归属上游**：`{npm root -g}\@earendil-works\pi-coding-agent\package.json`（实测 `version 0.85.1`，`where pi` → `D:\tools\npm-global\pi.cmd`）声明 `repository = {type: git, url: git+https://github.com/earendil-works/pi.git, directory: packages/coding-agent}`、`author = Mario Zechner`、`license = MIT`；随包发布的 `docs/development.md` 第 8 行给出的源码克隆地址是 `git clone https://github.com/earendil-works/pi-mono`，同文件 `## Forking / Rebranding` 一节把「改名发布」定义为**使用者自行**改 `package.json` 的 `piConfig.name` / `configDir` / `bin`。即：该 npm scope 归第三方作者，本团队无发布权；本机 `npm whoami` 实测 `ENEEDAUTH`（无任何 registry 登录），当前也不存在可用的发布凭据。
   - **Multica 不 pin 也不 vendor**：`grep -rn "pi-coding-agent"`（multica worktree，排除 `node_modules`／`.git`）零命中；`grep -rn "earendil"` 只命中 `apps/docs/content/docs/install-agent-runtime{,.zh,.ja,.ko}.mdx:34`，该处把 `Pi coding agent` 列为操作者自行安装的 agent CLI（安装链接指向 `https://github.com/earendil-works/pi`）。运行期由 daemon 按 `server/pkg/agent/pi.go:202-212` 的 `exec.LookPath(execName)` 解析 PATH 上的 `pi`，且 `server/pkg/agent/version.go:13-23` 的 `MinVersions` 不含 `pi` 条目（无最低版本门禁，Multica 不感知 Pi 版本）。**故来源 §6.2「按现有依赖升级流程让 Multica Runtime 使用新版本」在 Pi 侧没有对应的既有机制**——可执行文件由操作者替换，不存在「依赖升级提交」。
   - **无本团队 fork 与指针登记**：`dir-graph.yaml#repositories` 只声明 `ai-first-platform-docs`／`multica`／`tools` 三仓；`docs/references/` 只有 `multica.md`、`openwiki.md`、`tools.md` 三个指针；`C:\Users\GOBAO\Downloads\AI` 下无 pi 源码检出（核实口径：该层目录清单无 pi 命名录，且其中有顶层 `package.json` 的目录逐个核 name，无 `@earendil-works` 包）；`../multica/CUSTOM.md`（552 行）无 pi fork 登记——按 `earendil|coding-agent`  grep 零命中，含 `pi` 字样的三处（`:32`、`:184`、`:499`）分别是非 CR 的 pi session 排障、上游同步后的 `pkg/agent` pi 测试记录与 OutputGuard 不为 pi 新开 hooks 写点的说明，均非 fork 登记（该台账只登记 multica 相对其上游的定制）。

### 1.5 需求期不下结论的实现细节（归开发期 SDD）

- FR-1 规则正文的最终措辞与落点选择（改 `writeSkills` 输出，还是改等价的公共 Agent contract 并让 `writeSkills` 只引用单一来源）——来源 §5.2 已给出「二者不得并存两份完整语义」的裁决边界。
- FR-2 中「默认值」与内部 `timeout:` 错误传递的具体接线方式（现有实现把**调用方传入值**回传进错误文本，默认值生效时错误文本必须报告实际生效秒数）。
- Pi 侧交付路线（§1.3.2 三条候选 R-A／R-B／R-C 中选哪一条）、被升级 Pi 版本的实际产出方与版本号、切换运行环境 PATH 上 `pi` 可执行文件的具体记录。升级动作本身按本版口径固定为「发生在 CR 合并之后」，不属交付 diff（§1.3.2 共用边界 2、AC-12）。

### 1.6 修订记录

| 版本 | 时间 | 内容 |
|---|---|---|
| 0.1 | 2026-09-18 | 初稿：按收敛版来源 §5～§12 落 FR-1/FR-2 与 12 条 AC；核实来源 §3 的四项复用能力断言（事实 1～6）与版本序列（事实 7） |
| 0.2 | 2026-09-18 | 需求评审 attempt 1 回修（repair-target=write-requirement-prd）。**B-1**：新增 §1.4 事实 9（Pi 属第三方上游产物＋Multica 不 pin 不 vendor＋本团队无 fork 与发布路径，三处证据），§1.3.2 把「既有依赖发布路径」改为显式待定项并列出 R-A/R-B/R-C 三条候选路线及各自所需权限与证据、三条共用边界，FR-2 交付边界与 §5 AC-12 收敛为路线无关的可判定口径（含产出方与升级时点）。**S-1** 事实 3 改为可复现口径（注明结论不受影响）；**S-2** 事实 5 非法值行号 19→18 并改以分支为判据；**S-3** NFR-1 与 §7 第 13 条补隐式长调用面的处置口径（明确排除在本 CR 之外）；**S-4** FR-2 实现边界与 AC-5 补 schema 说明文案一致性核对点；**S-5** §1.3.1 第 1～2 条出处改正为 cr.md summary／来源 §1 的实际逐字句。FR-1／FR-2 行为合同、scope_in、target-version 与 owner 均未改动。 |

---

## 2. 用户故事

- **US-1** 作为 CR 流程负责人，我希望 `review-*` 节点不再因 Agent 全盘搜文件而无限阻塞，以便 CR 按 Pipeline 节奏进入人工审批，而不是靠人工识别并终止子进程才能继续。
- **US-2** 作为质量评审 Agent（`quality-reviewer-agent`），我希望任务列出的 Skill 就是我选择 Skill 的权威入口、并由 Runtime 原生发现，以便不需要猜测任何 Runtime 私有目录就能加载评审合同。
- **US-3** 作为执行长命令的 Agent，我希望忘记传 timeout 时平台仍给一次有界等待与干净的进程树清理，以便错误以现有工具错误形式回到我的下一轮，而不是永久挂死。
- **US-4** 作为跑长测试的 dev-agent，我希望显式声明的 `timeout: 1200` 原样生效，以便 `suite-gate` 类正常长任务不被 300 秒默认值误伤。
- **US-5** 作为运行环境维护者，我希望预期 Skill 不可用时节点立即技术中止并给出缺失能力事实，以便不会产出一份基于猜路径的伪评审结论或脏账本。
- **US-6** 作为方法论包维护者，我希望 timeout 的 owner 只有一处、Skill 路由规则只有一处，以便后续排障不需要在多层之间比对哪套计时器或哪份 Prompt 副本生效。

---

## 3. 功能需求

### FR-1 Agent 直接使用 Runtime 已发现的 Skill〔来源 §5〕

**行为合同**（Agent 侧可观察行为，全部可测试）：

1. 当前任务 brief 列出的 Skill 名称是 Agent 选择 Skill 的**权威入口**；
2. 选定 Skill 后，通过 Runtime 的原生发现结果使用它，先于任何仓库探索；
3. 禁止的兜底形式（枚举）：用 Shell 或文件系统递归搜索 `SKILL.md`（含 `find`、`Get-ChildItem` 等等价命令族）、按猜测访问 `~/.multica/skills`、`~/.pi/agent/skills` 或其他 Runtime 私有目录；
4. 预期 Skill 未被 Runtime 发现时：Agent **停止当前节点**，按现有技术中止路径报告 Skill 名、当前 Runtime 与任务；不生成业务 verdict；不调用 `crctl review-record`、`advance` 或任何状态写入；不新增 `SKILL_NOT_FOUND` 等平行错误体系。

**唯一写入点**：规则只写入 Multica 单一共享 Skills brief（`writeSkills` 生成段），或——若现有 Runtime 已提供等价且单一的公共 Agent contract——修改该 contract 并保持 `writeSkills` 只引用该单一来源。**两种落点不得同时持有完整语义**，且不得复制到 `review-requirement` / `review-tech-design` / `review-dev-plan` / `review-code`、各 Agent 独立 Prompt、README、Pipeline JSON。

**约束**（不可违反项）：不把 Pi 路径硬编码为跨 Runtime 通用合同；不在 Agent Prompt 复制所有 Provider 的 Skill 路径表；不新增 Skill 文件索引、缓存、Locator、manifest 或全局注册表；不把路径发现下沉到 review Skill；不改变 Skill 名称、frontmatter 或现有注入目录。

### FR-2 Pi 内置 bash 未显式传 timeout 时默认 300 秒〔来源 §6〕

**唯一解析规则**：

```text
调用显式传 timeout → 使用显式值
调用未传 timeout   → 使用 300 秒默认值
```

默认值固定为 300 秒；本期不引入配置文件、环境变量或远程开关（来源 §6.1）。

**判定顺序（固定，消除并列歧义）**：

1. 显式值非有限数或 ≤ 0 → 现有 `Invalid timeout: must be a finite number of seconds`；
2. 显式值换算后超既有上限 → 现有 `Invalid timeout: maximum is <MAX_TIMEOUT_SECONDS> seconds`；
3. 合法显式值 → 使用该值（含 `timeout: 1200`），不被默认值覆盖；
4. 未传 → 300 秒。
5. 传 `0`、负数、`NaN`、`Infinity` 归入第 1 档，行为与现状一致（零写入、不启动进程）。

**超时结果**（顺序确定）：

1. 复用现有 `killProcessTree(child.pid)` 清理**该工具调用**的进程树（父进程及其后代）；
2. 返回现有错误文本 `Command timed out after <实际生效秒数> seconds`（默认值生效时为 `Command timed out after 300 seconds`）；
3. Agent 按当前 Skill/节点的既有失败语义处理；
4. 无任何 CR 状态、门禁、审批或账本副作用；
5. 不新增 `TOOL_TIMEOUT`、`TOOL_TIMEOUT_CLEANUP_FAILED` 等平行错误结构。

**实现边界**：只修改 Pi 内置 bash 的现有 timeout 解析点及对应 schema/说明（默认值落地后该说明文案必须同步为与 300 秒默认值一致的措辞，不得继续声明「no default timeout」；核对点见 AC-5）；复用现有 `setTimeout`、AbortSignal、timeout 错误与显式 timeout 上限校验；不增加依赖；不新增 Runtime Executor；不在 Multica、OutputGuard、Agent、Skill 或 Pipeline 再设置第二套计时器。

**交付边界**（需求评审 B-1 回修后收敛为路线无关的可判定口径）：Pi 侧改动**必须**先落在版本化源码及其测试（R-A/R-B/R-C 任一路线均适用，路线选择见 §1.3.2），经该仓既有构建与测试产出可安装产物；**不得**以直接修改已安装包的 `dist` 作为改动载体或交付（来源 §6.2）——区别只在改动是否**先**出现在版本化源码里。来源 §6.2 末句「按现有依赖升级流程让 Multica Runtime 使用新版本」在 Pi 侧无对应既有机制（事实 9），本 PRD 把它改写为：升级动作（替换运行环境 PATH 上的 `pi` 可执行文件）发生在 **CR 合并之后**，由路线对应的产出方（R-A/R-C 为本团队构建产物、R-B 为上游发布）提供版本，属运行环境维护，不进 CR 交付 diff；路线选定与该版本的产出方归开发计划与架构期决策（§1.3.2、§1.5），需求期不拍板。

### FR-3 既有能力的复用合同（跨 FR 约束）〔来源 §3、§4〕

本 CR 的第三项需求是对「不建第二套系统」的可验收约束，因为它是两个改动单元共同的边界：

| 面 | 必须复用 | 本 CR 禁止 |
|---|---|---|
| Skill 发现与注入 | Multica 既有 `writeSkillFiles()` 与 Runtime 原生发现 | 新增 Skill Locator / manifest / 注册表 / 路径映射 / 索引缓存 |
| 命令与输出治理 | 已归档 CR-2026-069 的 OutputGuard `core.mjs` + `policy.json` + `capabilities.json` + `adapters/pi` | 新增第二 Guard、扩展 Shell 解析、修改复合命令 passthrough 合同 |
| 计时与清理 | Pi 既有 `setTimeout` / AbortSignal / timeout 错误 / `killProcessTree()` | 第二套计时器、自写进程清理 |
| CR 流程 | Pipeline 既有节点顺序、`reviewLoop`、工具失败中止；crctl 既有状态、门禁、CAS、账本、审计 | 新增 Pipeline 节点、状态、错误码、账本字段、sidecar、metrics、事务框架 |
| 工具错误的归类 | Runtime 执行错误 → 既有工具错误 → 既有失败语义 | 把 timeout 记账为 CR 业务状态或写入受控账本 |

---

## 4. 非功能需求

- **NFR-1 兼容性**：显式传 timeout 的调用行为逐字不变（含 `timeout: 1200` 的长测试路径）；AbortSignal 提前取消、非法值与超上限校验、现有错误文本语义无回归。**隐式长调用的处置口径**（需求评审 S-3）：来源 §10 把「300 秒误伤长任务」的控制写成两半——前半「现有显式 timeout 覆盖」由 NFR-1 与 AC-7 承担；后半「长测试、build、migration 必须显式声明」是面向调用方的运行约定，**本 CR 不逐条排查也不代改现存隐式长调用面**（如共享 brief 自身要求的 `gh pr checks --watch` 类前台阻塞调用与 dev-agent 的 suite／build 路径），排除口径见 §7 第 13 条；默认值生效后如出现误伤，按 §6 回滚粒度处理并另立需求。
- **NFR-2 回归面收敛**：OutputGuard `core.mjs`、`policy.json`、`capabilities.json` 与 compound-shell passthrough 合同不因本需求改变；Pipeline、四类 `review-*` Skill、crctl、状态机、受控账本、版本化转换脚本与审批合同零业务 diff。
- **NFR-3 跨平台清理正确性**：timeout 后的进程树清理走既有实现（Windows `System32/taskkill.exe /F /T /PID`，POSIX 进程组 `SIGKILL` + 失败回退单 PID），Multica daemon 进程不受影响。
- **NFR-4 阻塞上界**：未显式传 timeout 的 bash 调用最长寿命从「无界」变为 ≤300 秒；不新增可观测性字段、metrics 或 UI。
- **NFR-5 零新增基础设施**：不新增依赖、数据库、sidecar、错误码、状态或事务框架。
- **NFR-6 单一事实源**：Skill 路由规则在一处生效；timeout 默认值的 owner 只有 Pi built-in bash 一处；README 若需说明只给总览与权威链接，不复制 timeout 或 Skill 路由细节。
- **NFR-7 平台中立**：FR-1 规则文本不得假设 Pi 专有目录为跨 Runtime 合同，也不得枚举各 Provider 路径表。

---

## 5. 验收标准

AC 编号沿用来源 §7 以保持可追溯；映射列是本 PRD 追加的取证口径。

| AC | 验收内容 | 对应 FR |
|---|---|---|
| AC-1 | Multica 共享 Skills brief 只增加一处 Provider-neutral 行为规则，未在各 `review-*` Skill 或 Agent Prompt 复制（对 FR-1 禁止复制面做 diff 核对，命中处必须为零） | FR-1 |
| AC-2 | 重放第一次 `review-requirement` 触发场景：Agent 直接使用 Runtime 已发现的 Skill，session 不出现查找 `SKILL.md` 的 Shell 调用 | FR-1 |
| AC-3 | 重放第二次 `review-dev-plan` 复评场景：Agent 直接使用 Runtime 已发现的 Skill，session 不出现根目录或 HOME 递归检索 | FR-1 |
| AC-4 | 预期 Skill 不可用时节点技术中止：不执行文件系统兜底搜索、不生成 verdict、不写 crctl 状态或账本（构造 Skill 缺失场景后核对 cr.md/账本零变化） | FR-1 |
| AC-5 | Pi bash 未显式传 timeout 时使用 300 秒默认值；核对点含该工具的 schema 说明文案与默认值一致（不再声明 `optional, no default timeout`）（S-4） | FR-2 |
| AC-6 | timeout 到期后复用现有 `killProcessTree()`，父进程及其后代被清理；Multica daemon 不受影响（daemon PID 与状态前后一致） | FR-2 |
| AC-7 | 显式 `timeout: 1200` 原样生效、不被默认值覆盖；dev-agent 长测试行为无回归 | FR-2 |
| AC-8 | AbortSignal、非法 timeout（非有限数 / ≤0）、显式 timeout 上限与现有错误文本行为无回归 | FR-2 |
| AC-9 | OutputGuard 全部 conformance 测试通过；`core.mjs`、`policy.json`、`capabilities.json` 与 compound-shell passthrough 合同不因本需求改变 | FR-3 |
| AC-10 | Pipeline、四类 `review-*` Skill、crctl、状态机、受控账本、版本化转换脚本与审批合同无业务 diff | FR-3 |
| AC-11 | 未新增依赖、数据库、sidecar、metrics、错误码、状态或事务框架 | FR-3 |
| AC-12 | 路线无关的可判定口径（B-1 回修）：本 CR 交付 diff 中 **Pi 侧改动只出现在版本化源码与其测试文件内**；已安装包 `dist`（`@earendil-works/pi-coding-agent` 的安装目录）不出现在任何交付 diff 中。取证 = 逐份交付 diff 列文件路径清单并核对归属；**不要求**验证运行环境已升到新版本（被升级版本的产出方与升级时点已在 §1.3.2 与 FR-2 交付边界写明） | FR-2 |

补充判定口径：

- AC-2 / AC-3 的行为验证必须用真实 smoke run 留证（来源 §8.1）；Prompt 静态断言只证明规则存在，不能替代真实行为验证。
- AC-5～AC-8 的 timeout 验证在测试环境缩短等待时间，但必须走与 300 秒默认值相同的解析与 cleanup 路径（来源 §8.2）；**验收测试中不得真实等待 300 秒、不得执行 `find /`**。
- AC-9～AC-11 以复跑既有测试与 diff 面为观察点，不要求新增测试基础设施。
- AC-12 的取证只看**交付 diff 的文件集合**（版本化源码与测试 vs 已安装 `dist`），不要求验证「Runtime 已升级到新版本」；后者发生在合并后，属运行环境维护（§1.3.2 共用边界 2）。本次收敛只改判据口径，**AC 编号、FR 归属与来源 §7 的对应关系不变**（B-1 回修注记）。若开发计划选定 R-B（向第三方上游提 PR），则本 CR 的 Pi 侧交付只到 PR 的源码 diff 为止，AC-2／AC-3 不受影响，AC-5～AC-8 的运行环境侧验证需等上游发版后重跑（§1.3.2 路线表）。

---

## 6. 成功指标

| 指标 | 上线前基线 | 目标 | 观察方式 |
|---|---|---|---|
| 两次历史评审场景回放中的 `SKILL.md` 搜索调用次数 | 2 次 CR 各 1 次，均无界阻塞 | 0 | 回放 session 工具调用记录 |
| 未显式传 timeout 的 bash 调用最长寿命 | 无界（实测阻塞 18 分 38 秒 / 22 分 38 秒） | ≤ 300 秒 | AC-5 与 fixture 计时 |
| 同类无限阻塞所需的人工终止次数 | 每事故 1 次（合计 2 次） | 0 | 后续 CR 流程记录 |
| 显式长任务（`timeout: 1200`）正常返回率 | 现状正常 | 无回归 | `suite-gate` 冒烟 |
| timeout 后遗留子进程数 | 未度量（此前无默认 timeout 触发路径） | 0 | AC-6 |
| 交付 diff 涉及的改动单元数 | — | 恰为 2（Multica 规则 + Pi 默认 timeout 及其回归测试） | diff 核对 |

发布顺序与回滚沿用来源 §9 的**递次序**（不新增 CR 状态或 Pipeline 节点）：先发布 Multica 共享 Agent 行为规则 → 用质量评审 Agent 重放两次历史场景 → 产出含 bash 默认 timeout 的 Pi 版本（路线相关：R-A/R-C 本团队构建、R-B 等上游发版）→ 在 **CR 合并之后**替换运行环境 PATH 上的 `pi` 可执行文件（Multica 无依赖升级提交可走，事实 9）→ 验证默认与显式两条路径。回滚粒度到「单一共享规则」与「Pi 版本/固定默认值」两处，OutputGuard、crctl、Pipeline 与账本因本 CR 零改动不参与回滚。

---

## 7. 范围排除

以下明确不做（来源 §1「明确不实施」、§2.4、§3 各节结论、§4「不应做」列）：

1. Task 当前工具 / 持续时间 UI；
2. 新运行态字段、数据库、sidecar 或 metrics；
3. 新 Skill Locator、Skill manifest 或全局注册表；
4. 新 Dangerous Command Guard、Shell lexer 或 Shell parser；
5. 新进程树、事务、账本、状态机或错误码框架；
6. 修改 CR-2026-069、OutputGuard 算法或现有 Pipeline；
7. 把 dev-agent「正常长测试」当阻塞问题处理的可观测性改造（以显式 timeout、进程活动与最终返回为判断依据）；
8. timeout 默认值的配置化（配置文件 / 环境变量 / 远程开关）——只有实际数据证明固定值不适用时才另立需求；
9. 在 Multica、OutputGuard、Agent、Skill 或 Pipeline 侧设置第二套计时器；
10. 直接 patch 本机已安装 Pi 包 `dist` 作为交付；
11. 需求期预先拆更多 TASK（按来源 §11：开发计划依实际 Pi 源码仓与发布路线完成最小拆分；因 §1.4 事实 9 已证实无「既有依赖发布路径」，拆分时一并选定 §1.3.2 的 R-A／R-B／R-C）；
12. 把 `docs/product/`、`docs/analysis/` 既有平台级文档搬入本 CR 产物，或为本 CR 改动 `dir-graph.yaml` 的状态机 / gates 声明（状态机与 gates 唯一事实源在 tools 包，本仓库不复刻）。
13. 逐条排查或代改现存**隐式 timeout 长调用面**（未显式传 `timeout` 的长命令路径，如 Multica 共享 brief 自身要求的 `gh pr checks --watch` 类前台阻塞调用与 dev-agent 的 suite／build 路径）；该风险由来源 §10 的后半句「必须显式声明」承担，属调用方运行约定，不属本 CR 改动单元（口径见 NFR-1）。
14. 为本 CR 新建 npm scope、私有 registry 或 Pi fork 仓库（路线选择与所需权限归开发计划，§1.3.2）；也不包含向上游提 PR 的**结果保障**（R-B 下上游是否接受与何时发版不由本 CR 控制，本 CR 只交付 PR 侧的源码 diff）。
