---
id: CR-2026-060-prd
type: PRD
cr-ref: CR-2026-060
title: CR 全生命周期合同对齐
target-version: "0.33"
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-02T16:46:37+08:00
updated: 2026-09-02T18:30:37+08:00
---

# 1. 概述

## 1.1 问题陈述

AI First 平台已经具备 `crctl` 状态机、门禁、CAS、受控 Git、事务、worktree、评审记录、测试证据、checkpoint、merge、writeback 和 archive 等基础能力，但各阶段的 Pipeline prompt、Skill 合同和消费端仍存在重复描述与字段漂移。重复合同会导致以下问题：

- 注册端、PRD/SDD/PLAN/TASK 生产端与回写消费端对目标版本、目标 spec、工作区和证据的理解不一致；
- Pipeline prompt 复制审批、评审、测试、账本和 Git 算法，修改一个入口时其他入口可能继续使用旧行为；
- writer 与 reviewer 的判断标准不对称，产品决策被延后到技术设计或编码阶段；
- PLAN、TASK、代码、测试报告和代码评审没有稳定地消费同一工作区与同一证据；
- writeback 在 `code-approved` 后仍可能重复做业务判断，或无法同时支持新注册 CR 与历史 legacy CR；
- product-planning、market-to-plan、competitive-radar 和 resume-cr 的输入映射存在已知缺参、草稿状态和展示字段矛盾。

## 1.2 目标

在一个 CR 内完成生命周期合同对齐：让生产端和消费端围绕已有 `crctl` 与版本化脚本共享最小、可验证的字段和职责边界，同时保持现有状态机、事务、审批、评审循环和回写机制不变。

本 CR 的目标版本为 `0.33`。本 CR 在新合同代码合入前已由旧版 register 注册，因此 `CR-2026-060` 本身属于兼容范围内的 legacy registration 形态；实现完成后必须能继续完成本 CR 的 PRD、SDD、PLAN/TASK、编码、测试、评审、回写和归档。

## 1.3 设计原则

1. 复用现有能力，不新建并行状态机、事务层、账本、Runner、协议版本或迁移器。
2. `cr.md` 是 CR 业务事实源；Pipeline 只传递最小运行时上下文；状态、审批、评审、测试证据和受控账本写入继续由 `crctl` 或既有版本化脚本负责。
3. 业务判断留在对应 Skill，确定性转换留在既有 generator，Pipeline 只负责节点顺序、输入传递、reviewLoop 和失败路由。
4. 对历史 CR 兼容读取；对新注册严格写入：新注册必须显式提供并持久化 `target-spec-id`，不得以缺字段代表 legacy。legacy 只表示在本 CR 代码合入前已经存在、且 `cr.md` 与对应 `_backlog.yml` 条目都缺少 `target-spec-id` 的历史 CR；不批量迁移历史产物。
5. 所有跨行解析、哈希和逐行解析先规范化 CRLF 为 LF；解析失败必须报错，不得静默降级为空结果。

## 1.4 主要影响面

| 领域 | 影响内容 |
|---|---|
| 注册与需求期 | `requirement-register`、`requirement-authoring`、PRD writer/reviewer、目标 spec/version 事实 |
| 架构与开发期 | SDD writer/reviewer、PLAN/TASK、workspace context、Coding、测试报告和代码评审 |
| 回写期 | merge、baseline/tasks/traceability generator、archive、legacy/new 双路径 |
| 规划与展示 | product-planning、market-to-plan、competitive-radar、resume-cr |
| 约束与索引 | tools 的 README、AGENTS、Skill/Agent 索引、Pipeline JSON、测试断言 |

源方案中的四个实施组分别对应注册事实、作者与 reviewer 标准、计划到代码证据、回写投影；规划类和展示类契约作为跨组的 Pipeline 输入对齐项一并验收。

# 2. 用户故事

- **US-01 工具维护者**：作为 tools 维护者，我希望 Pipeline prompt 只保留节点编排和结构化输入输出，以便 Skill 或 `crctl` 内部合同变更时不需要同步维护多份算法副本。
- **US-02 CR 执行者**：作为 CR 执行者，我希望注册后能从 `cr.md` 获得唯一的目标版本、目标 spec 和 owner 事实，并能在同一 CR worktree 中连续推进全部阶段。
- **US-03 需求作者与评审者**：作为需求作者或评审者，我希望产品输入、成功结果、权限、失败恢复、兼容范围和验收场景在需求阶段一次闭合，技术设计只补实现机制。
- **US-04 开发计划与测试负责人**：作为开发或测试负责人，我希望 PLAN、TASK、代码、测试报告和代码评审使用同一工作区、同一任务合同和可重算的源码/日志证据。
- **US-05 交付负责人**：作为交付负责人，我希望 `code-approved` 后的 merge、writeback 和 archive 只投影已冻结事实，并且新 CR 与历史 legacy CR 都能完成回写归档。
- **US-06 历史 CR 维护者**：作为历史 CR 维护者，我希望本次合同收敛不强制迁移旧 CR、不改变既有公开命令和状态路径，并能在兼容期继续处理旧字段。

# 3. 功能需求

## FR-01 注册合同与单一目标事实

### 目标

新注册 CR 必须为后续阶段提供足够的目标事实，但不得把 execution context 变成 `cr.md` 的第二副本。

### 要求

1. `requirement-authoring` 注册节点显式传递稳定的 `registration_key`、`title`、`summary`、可选 `source`、`target_version`、必填 `target_spec_id`、三角色 owner，以及可选 `origin`。`source` 只保存为安全 scalar，不在注册事务中解析业务文件路径。Pipeline 的 `target_spec_id` 与 `target_version` 为 required；Skill 与 CLI 同样 required。没有 `target_spec_id` 的新调用不得降级为 legacy。
2. 成功的 new registration 必须在 `cr.md` 与 `_backlog.yml` 同时保存同一个稳定小写 `target-spec-id`；该值匹配 `^[a-z0-9][a-z0-9._-]*$`，不得包含 `/`、`\\`、路径段或 CR/LF。读取时只有两处字段都存在且全等才判定 new mode；只有两处都缺失且 CR 在本次注册前已存在，才判定 legacy。单处存在、值不一致或非法均为 authority drift，硬失败且零写入。
3. `target_version` 在 Pipeline、Skill、CLI 三层均必填，允许真实 `MAJOR.MINOR[.PATCH]` 或 `unassigned`；输入可带 `v/V` 前缀时规范化为不带前缀的值。禁止 `tbd`、`pending`、`none` 等同义值。new mode 的 `unassigned` 只允许 CR 停在 `drafting`，不得进入 `requirement-reviewing`；必须先由 `crctl version-set {cr_id} --to <real-version>` 固化。`CR-2026-060` 的目标版本必须保持为 `0.33`，后续 PRD/SDD/PLAN/TASK 继承 `cr.md`，不得自行改写。
4. 三个 owner 必须分别写入 `id` 与 `assigned-at`；同一注册事务使用一个注册时间，账本、owner history 和 outbox 中对应时间一致。
5. `crctl register` 完成后必须由 register 事务的 workspace resolver 生产唯一公开字段 `operational_workspace`（snake_case，值为真实 knowledge-base CR worktree）；成功 JSON 顶层返回 `cr_id`、`operational_workspace`、`tx_id`、`changed`、注册 commit、`target_spec_id` 和恢复命令等注册结果。`requirement-register` 与 Pipeline 只能逐字透传该字段到 `execution_context.operational_workspace`，不得重新解析、拼接或另行生产路径；不得把长期可复用的 resources 快照作为第二事实源返回给后续节点。
6. 注册成功必须原子完成 knowledge-base 的 `cr.md`、`_backlog.yml`、`_index.yml` 写入、提交/发布和各 active repo 的 `requirement/{cr_id}` worktree ensure，初始状态为 `drafting`。
7. 同 `registration_key` 且包括 target spec/version 在内的规范化输入完全相同的调用必须幂等返回同一 CR；输入漂移必须零写入并返回 `REGISTRATION_INPUT_MISMATCH`。版本非法返回 `REGISTER_VERSION_INVALID`，target spec 缺失/非法分别返回 `REGISTER_TARGET_SPEC_ID_REQUIRED`/`REGISTER_TARGET_SPEC_ID_INVALID`，trunk 不干净返回 `REGISTRATION_TRUNK_DIRTY`，事务或 Git 问题按现有 recoverable 错误返回，不得手工补偿。
8. 注册失败的校验类错误必须在 candidate、journal 和账本写入前返回；事务中断有中间态时只允许重跑同一恢复命令。

## FR-02 PRD/SDD 作者与 reviewer 标准对齐

### 目标

需求阶段关闭产品语义，技术设计阶段关闭实现协议；作者与 reviewer 对同一缺口必须有一致的阶段归属。

### 要求

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

## FR-03 PLAN/TASK、Coding、测试与代码评审对齐

### 目标

让计划、任务、实现和测试消费同一份阶段合同与可归因证据，不扩展动态回修引擎。

### 要求

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

## FR-04 回写成为确定性投影

### 目标

`code-approved` 后只消费冻结事实，确定性生成 baseline、delivery、traceability 并归档，不在回写期重新做上游业务判断。

### 要求

1. `feature-writeback` 保持现有五节点顺序。new mode 从 finalize 后 Transaction Workspace 的 `cr.md`、冻结的 PRD/SDD/PLAN/TASK、test-report 和 merge facts 读取 spec/version 等事实；外部 `spec_id`/`target_version` 可省略，若提供只能校验相等，不能覆盖 authority。new mode 不需要 `milestone_file`，由 traceability generator 从冻结 PLAN/TASK/test-report/merge facts 生成引用链；legacy mode 继续接受显式 spec/version/milestone 输入。
2. merge 继续负责 release-subject drift、跨仓 publication 和合并事务；writeback generator 消费冻结源生成 candidate、manifest 和既有校验结果，不新建事务或重复计算独立 digest。
3. baseline generator 从冻结 PRD/SDD 生成确定性 candidate；相同 CR 内容必须 noop，不同内容按现有 candidate/manifest 冲突语义处理。generator 不重新评估 PRD/SDD 业务质量。
4. TASK generator 在 candidate 前确认本 CR 全部源 TASK 为 done；任一 TASK 未完成必须零写入、零发布，不得只投影已完成子集。delivery 文件和索引中的状态必须与任务账本一致。
5. new mode 的 traceability generator 从 PLAN 交付覆盖表、TASK、test-report 和 merge-commits 生成 `FR → SDD → TASK → repo@mergeSHA → cmd` 引用链；只验证引用存在并投影冻结事实，不重新评价映射质量。legacy mode 继续使用显式 milestone 输入。
6. archive 只在 baseline、tasks、traceability 三段投影 complete，目标引用存在且没有 pending trace event 时成功；不重跑 generator、不手工补文件、不重新评审上游产物。
7. `review-alignment` 改为按需只读诊断：不进入 feature-writeback Pipeline、不推进状态、不写 traceability，不再使用失效的 mtime、backlog merge-commit 或 fingerprint 事实源。
8. 本 CR 及其他 legacy CR 均必须可完成 writeback/archive；不自动迁移历史 CR。

## FR-05 Pipeline、规划与审批输入契约对齐

### 要求

1. 每个 `kind=skill` 节点的 prompt 只保留五类信息：调用哪个 Skill、传入哪些参数、依赖哪个前序结构化输出、消费哪些结果、失败如何 abort/skip/进入 reviewLoop。业务章节、文件命名、账本格式、算法和受控命令细节归属对应 Skill 或 `crctl`。
2. requirement-authoring 的 inputs 中 `registration_key`、`target_spec_id`、`target_version`、三个 owner、title、summary 为注册必填；source 与 origin 按表中 optional 处理。Pipeline 显式把 target spec 传给 requirement-register，并且只透传 register JSON 的 `cr_id + operational_workspace` 到后续节点。new mode 的需求评审固定顺序为：`crctl gate <cr> --for requirement-reviewing --mode pre-review`（仅版本守卫）→ `review-record` → `advance`；版本为 `unassigned` 时前置 guard 必须在任何 canonical 评审写入前失败，review 节点不得绕过 version-set。
3. requirement-authoring 保留 `register → PRD → optional checkpoint → review → human approval → approve → checkpoint` 顺序、`auto_push_after_prd` 分支、reviewLoop 和最小 execution context 传递。architecture-design、code-implementation 和 feature-writeback 的现有节点数量、合法状态顺序、checkpoint 前置和 reviewLoop/replayNodes 均不得被删除或重排。
4. 四个 CR `approve-*` 节点都传完整 `cr_id` 和对应 approver，消费结构化审批结果；不在 Pipeline prompt 中复制 TTY、grant、CAS、approval.yml、状态级联或 reject 回退算法。下一步统一提示为“以 `crctl next {cr_id}` 为准”。人工审批仍只能由人通过 `crctl approve` 完成。
5. product-planning 修复 Skill 必填输入：feedback、market research、current product 至少传 `topic`；竞品报告传 `updates-block`、`product-snapshot`、`confirmed`；规划报告传 `prev_outputs`、`review_feedback`、`self_repair_attempt`；roadmap 传 `topic`、`target_version`、`planning_report_path`，不跨文档修改规划报告索引。规划类 human approval 只收集结构化 `approve/reject + reason`，不迁移到 CR 审批机制。
6. market-to-plan 的 `planning-draft` 传 `context` 与 `intent`；brief 调用显式传 `mode=brief` 与 `raw_insight_path`；不得用 `source` 伪造 Skill 参数或由一个节点复制两个 Skill 的业务逻辑；`write-planning-entry` 不修改 market-insights 索引生命周期状态。
7. competitive-radar 统一 `competitor-id(s)` 与 `lookback-days` 输入；草稿建议支持 `reportPath` 与 `reportDraft` 二选一，同时存在时优先正式路径。`reportDraft` 必须包含草稿正文、competitorId、reportDate 和来源标识，草稿模式不伪装成已落盘报告。正式阶段按既有节点能力顺序调用 `write-competitive-report(confirmed=true)` 再调用 `write-planning-entry`。
8. resume-cr 的展示节点调用 `cr-show(cr-id, section: all)` 并消费其结构化详情；不在 Pipeline 自行复制 CR 详情字段清单。feature-writeback 的 merge 节点不再重复预检 `status=code-approved`，该校验由 merge/crctl 承担。
9. Pipeline `node.ref` 必须是 active Skill，节点数量与对应 `_index.yml` 一致；reviewLoop 的 `maxAttempts`、`replayNodes`、`passCondition` 和 checkpoint 顺序继续作为机器事实源。自动评审有 blocker 时必须回到对应修复节点，不能绕过评审进入人工审批。

## FR-06 兼容、变更组织与验证闭环

1. 实现按四个变更组组织：注册与 authority；PRD/SDD writer-reviewer；PLAN/TASK/Coding/test/review；writeback/archive 与 legacy compatibility。每组只修改必要调用方和测试，writer 与 reviewer、证据生产端与消费端必须成对更新。
2. 阶段一先完成注册/审批/评审输入等正确性合同，契约断言通过后再执行职责收敛；不得通过新增 CR 状态、Pipeline 节点、feature flag、contract-version 或迁移器解决兼容问题。
3. 所有受控写入继续经过既有 `crctl`/版本化脚本；不得直接写 `cr.md` status、`_backlog.yml`、approval、review annotations、review-loop、test-report machine zone 或 traceability 账本。
4. 生产端和消费端的新增字段必须有正向和负向验证：同键输入漂移、版本/spec 不一致、源码/日志漂移、TASK 未完成、非法路径和受保护文件写入均应在副作用发生前失败或按既有业务错误记录。

### 3.1 模式、版本与交付数量的唯一裁决

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

### 3.2 CLI / `crctl` delta 合同矩阵

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

### 3.3 Skill delta 合同矩阵

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

### 3.3.1 审批、规划消费与只读诊断的补充合同

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

### 3.4 四个 TASK 的一一对应与交付约束

来源方案明确要求“一个 CR、四个 TASK”。本 CR 只允许且必须创建以下四个交付 TASK，不能把 Pipeline 节点、checkpoint、merge、writeback、archive 或纯验证命令另建为 TASK：

| TASK | 唯一变更组 | 交付边界 | 最小验收证据 |
|---|---|---|---|
| TASK-1 | 注册与 authority | target-spec/version authority、需求评审前 version gate、register/version-set/writeback CLI 入口及测试 | register/version-set/gate/writeback 的正反 CLI 信封和零副作用断言 |
| TASK-2 | PRD/SDD writer-reviewer | PRD/SDD 输入、作者/reviewer 七维标准、review payload/route 合同 | writer/reviewer 对称性、首轮契约闭包、合法状态路由测试 |
| TASK-3 | PLAN/TASK/Coding/test/review | 两张 PLAN 表、恰四 TASK、workspace/证据/回修合同 | task count/一一对应、cmd-NN、source/log drift 和 review route 测试 |
| TASK-4 | writeback/archive 与 legacy compatibility | new/legacy 解析、三个 writeback stage、archive 投影和兼容测试 | new/legacy 两条端到端夹具、TASK 未完成及外部输入漂移零写入测试 |

`write-dev-tasks` 必须在本 CR 的 plan.md 中为四个变更组各预分配一个 ID，`crctl task init` 后索引中恰有四个 `TASK-*.md` 条目；任何缺失、重复、第五个或跨组 TASK 均返回 `TASK_COUNT_MISMATCH`，不推进到开发启动。每个 TASK 必须在覆盖表中恰出现一次且有唯一 owner；四个 TASK 的完成状态均由 `crctl task done` 登记。

# 4. 非功能需求

- **NFR-01 单一事实源**：业务字段从 `cr.md` 或当前阶段冻结产物读取；Pipeline 只维护机器编排事实；状态、账本、审批、评审、测试、事务和审计继续由既有 `crctl`/generator 维护。
- **NFR-02 原子性与数据安全**：注册、评审记录、任务状态、测试证据和回写事务必须沿用现有 CAS、lease、candidate/journal、受保护路径和 recoverable 语义；任何校验失败不得留下部分账本或发布副作用。
- **NFR-03 可重复性**：同一输入和同一冻结源生成的 candidate、traceability 引用和审计结果应确定性一致；同键同输入注册和同内容回写必须幂等。
- **NFR-04 向后兼容**：不删除现有 `crctl` 命令、合法状态转换、审批 grant、reviewLoop 语义和历史 traceability evidence 结构；新增注册字段为严格必填；缺少 `target-spec-id` 的既有 CR 继续走 legacy mode。writeback 的新 mode 省略外部重复参数是向后兼容的新增分支，不改变 legacy 显式参数行为。
- **NFR-05 可移植性**：仓库、trunk、worktree 和路径均从目标 workspace `dir-graph.yaml` 解析；不引入本机绝对路径、固定仓库名或固定双仓假设。Node 运行时继续满足现有 `>=18` 要求。
- **NFR-06 安全与权限**：路径输入拒绝 CR/LF 和路径穿越；受保护评审账本不接受人工或 Pipeline 直接写入；人工审批不得由 Agent 代签。
- **NFR-07 质量验证**：Pipeline JSON 可解析，active Skill、Agent 索引和权限矩阵无漂移；跨行解析/哈希逻辑统一 CRLF→LF，匹配失败硬失败。

# 5. 验收标准

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

# 6. 成功指标

1. 8 条 active Pipeline 中受保护账本手写指引、审批/评审/测试/注册/freshness 算法副本降为 0。
2. 需求、架构、计划、编码、测试和回写节点对 `cr_id`、operational workspace、target version、任务和证据的生产/消费字段可由结构化断言验证，无缺参导致的运行时失败。
3. 四个 CR approve 节点 100% 传递完整 `cr_id` 与 approver，且下一步提示统一使用 `crctl next`；规划类审批保持结构化 approve/reject 语义。
4. 同一冻结输入的 register/writeback 重跑无重复副作用；new mode 与 legacy mode 均能完成完整生命周期。
5. 测试后源码或日志变化能够在代码评审阶段稳定阻断；TASK 未全部 done 时 writeback 不产生部分交付。
6. 本 CR 的净效果是删除重复合同、补齐缺失字段和确定性消费，不新增并行状态、事务、账本或长期协议资产。

# 7. 依赖、风险与范围排除

## 7.1 依赖与风险

- **依赖**：附件《CR全生命周期合同对齐-需CR实施方案》；目标 workspace `dir-graph.yaml`；tools 的 active Skill/Agent 索引、8 条 Pipeline JSON、`crctl`、gates 和既有测试。
- **R-01 过度删除真实业务判断**：收敛 Pipeline 时只删除算法和固定文档格式，保留业务输入、结构化输出、失败分类与 reviewLoop；writer/reviewer 的七项产品标准必须成对维护。
- **R-02 新旧合同兼容破坏**：本 CR 由旧 register 创建，必须用 `target-spec-id` 是否存在识别 new/legacy mode；不通过迁移历史文件或 CR-ID 特判解决兼容。
- **R-03 证据漂移漏检**：测试报告和 review-code 必须绑定 source revision 与日志事实，并在评审前重算；不依赖共享实例或无法归因的命令输出。
- **R-04 规划流程顺序破坏**：competitive-radar 草稿与正式报告的输入/落盘顺序必须由结构化节点结果传递和测试断言保护，不在 Pipeline 复制报告落盘算法。
- **R-05 跨仓路径误用**：所有开发与评审路径从 `workspace inspect` 读取；各仓文档分别提交，避免把多仓文件误认为同一 commit。

## 7.2 范围排除

- 不修改状态机、审批 grant、reviewLoop 规则或 traceability evidence 结构；仅可在既有 `crctl` gate 机制内增加本 CR 要求的 target-version check，不新增状态。
- 不新增 Pipeline 专用事务层、状态投影、第二套 review-loop 账本、测试证据格式、candidate/manifest/merge/recovery 算法、通用 Runner、独立 ledger、contract-version、迁移器或 feature flag。
- 不新增 Agent、Skill、Pipeline 节点、状态、独立 ADR、跨 CR CONTEXT、术语中心或历史 CR 批量迁移。
- 不把规划类本地评审记录强行迁移到 CR `crctl` 评审机制；不把 README 变成第二份可执行 Pipeline 事实源。
- 不在本 CR 中实现新的产品业务功能、UI、HTTP API 或用户数据模型；本 CR 只对 tools 生命周期合同和既有运行时入口做对齐。
- 不修改 `specs/`、`delivery/` 或主工作区同名 CR 目录；需求文档只落盘于 `change-requests/CR-2026-060/` 的 CR worktree。
- 不要求所有 active repo 无条件产生 commit；只有实际变更或测试的 worktree 需要 clean committed。

## 7.3 实施完成定义

当 AC-01 至 AC-18 全部满足，四组变更已完成评审与测试，CR-2026-060 可在兼容模式下走完回写归档，且没有受控账本漂移时，本 CR 达到实施完成标准。
