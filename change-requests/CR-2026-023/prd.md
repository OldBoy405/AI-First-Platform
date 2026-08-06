---
id: CR-2026-023-prd
type: PRD
cr-ref: CR-2026-023
title: 治理工具链 — 代码评审 LLM 选择暂停节点 + R9 护栏（CR 上下文下一步收敛 crctl next）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-06T23:40:00+08:00"
updated: "2026-08-06T23:40:00+08:00"
---

# PRD — 代码评审 LLM 选择暂停节点 + R9 护栏（两份分析方案合一落地）

## 1. 概述

### 1.1 问题陈述

本 CR 合并两份分析文档（`docs/analysis/code-review-llm-selection-plan-2026-08-06.md` 与 `docs/analysis/review-skip-drift-and-r9-guard-2026-08-06.md`）揭示的两个 tools 包治理缺口：

- **问题 A（评审模型不可干预）**：code-implementation pipeline（`/coding`，12 节点）在节点 8（push-progress 统一 checkpoint）推送完成后**直接进入节点 9（review-code）自动评审**，中间没有任何暂停点。执行者无法决定由哪个 LLM/runner 执行评审；`pipeline inputs` 只能触发时预选，`code_generation` 的 runtime 选择机制又仅适用于节点 6 不适用 skill 节点——"评审前停下来让我选择"的诉求没有任何合法承载。
- **问题 B（需求期跳评审提示链漂移）**：观测到 CR 在写完 PRD 后有时未执行 `review-requirement` 就"进入下一环节"。逐层核查证实机器门禁 fail-closed 无旁路（`crctl advance` 进评审态有 GATE_BLOCKED 门禁、`crctl approve` 三重硬检查、passCondition 解析无 fail-open 路径）——**漂移发生在提示链层**：需求期各 skill 输出摘要手写「下一步」副本（D1 主因 `write-requirement-prd` 给出"review-requirement 或 push-progress"等价分叉、D2 `push-progress` 无下一步指引、D3 `requirement-writer` 映射表无前置条件、D4 reviewLoop 耗尽无机器停止、D5 未收敛到 `crctl next` 权威推荐）。全库 grep 证实 develop/writeback 域存在完全同构的手写副本共 **17 处**，漂移风险一致（跳过 review-tech-design / review-code 直接审批等）。

两个问题同属 tools 包 prompt/pipeline 模板治理，合并为一个 CR 落地以获得统一的评审记录与回写基线。

### 1.2 解决方案摘要

**块 A —— 代码评审 LLM 选择暂停节点**：在节点 8 与节点 9 之间插入 `human_approval` 节点「选择代码评审 LLM」（id `0015-000000000013`），作为声明式模板中唯一合法暂停机制的暂停确认点；新增可选触发输入 `review_llm`（熟手触发 `/coding` 时一次选定，暂停节点快速确认；留空则现场三选一：会话默认模型 / 外部 CLI runner / 其他指定模型）；review-code prompt 头部承接选择结果并在 dimensions 记录 reviewer-model 留痕；repair 循环 replayNodes 不加入选择节点（一次选择、全程复用）。

**块 B —— R9 护栏 + 存量清零**：`lint-prompts` 新增 R9 规则——CR 上下文域（`skills/(requirement|develop|writeback|sync|cr)/`，cr-show 豁免）skill 的「下一步」提示必须收敛到 `crctl next {cr_id}`，禁止手写 skill/pipeline 名映射副本，级别 CONTRADICTS（enforce 阻断）；判据源直读 `skills/_index.yml` 提取全部 skill id（对齐 R7/R8 直读模式，新增 skill 自动覆盖零维护副本）；17 处存量手写副本改写为统一形态（分支语义保留、权威指针收敛）；配套 push-progress 引导链闭环、requirement-writer 前置注记、AGENTS.md 编辑规则条目。

**范围口径（本 CR 的既定决策）**：两份分析文档 §流程决策 均写有「不开 CR，直接提交 tools 仓」；**按用户决策，本次改走 CR 流程**——两块改动全部在本 CR 内落地，tools 仓改动经 CR worktree 流程追踪、合入 `custom/main`。原文档的流程决策不再执行。

### 1.3 方案遗留决策点（本 PRD 拍板）

两份分析文档中的开放项，本 PRD 直接给出决定，SDD/实施期不得再次悬置：

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 附件1 §6.1 建议 `review_llm` 输入可按 YAGNI 缓上 | **本 CR 即实现**该输入 | 节点 approvalPrompt 含「若触发参数 review_llm 已指定，请按该模型执行」分支，不加输入则该分支成为死文本；输入改动成本极小（一个 inputs 数组条目），缓上反而留下"暂停节点无快速确认路径"的半成品形态 |
| D-2 | 附件1 §6.1 建议 reviewer-model 措辞改"留痕（自报）" | **采纳**：reviewer-model 记录在 review-code dimensions 内，由执行评审的 Agent 自报，不改 crctl `review-record` 契约（canonical 文件 `reviewer` 字段仍由 crctl 注入 `identity(ws)`） | 机器可读的评审模型审计（按模型统计 blocker 率）需要扩 `--reviewer-model` 旗标 + gates/digest 联动，属独立 CR 级改动，列入范围排除 |
| D-3 | 附件2 §4.6 AGENTS.md「修改 Skill」规则条目标注"可选" | **实现**：tools 仓 AGENTS.md 追加第 7 条（CR 上下文 skill「下一步」一律写「以 crctl next 为准」） | 只有机器护栏（R9）没有文字规范，新增 skill 的作者无从知晓约定；条目一行，成本可忽略 |
| D-4 | 附件2 §4.3 统一改写形态的 `{修复节点}` 占位 | 落地时 `{修复节点}` 必须是占位文本或语义方向（PASS/BLOCK 走向），**不得写字面 skill id**，否则新形态自身命中 R9（附件2 §6.4③ 自触发风险） | 已在附件2 实测确认，固化为验收项 |

### 1.4 事实基线（已核实，纪律 #4）

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

## 2. 用户故事

- **US-1** 作为代码评审的发起者，代码与测试证据推送统一 checkpoint 后，流水线在评审前暂停并询问我用哪个模型执行评审，我可以选当前会话默认模型、外部 CLI runner 或其他指定模型。
- **US-2** 作为熟手执行者，我触发 `/coding` 时在 `review_llm` 输入框一次选定评审模型，暂停节点快速确认即过，不必每轮现场选择。
- **US-3** 作为审计评审证据的维护者，`review-annotations/code.yml` 的 dimensions 里能看到 reviewer-model 留痕，知道这份评审判断由哪个模型产出。
- **US-4** 作为审批人，我在评审模型选择节点驳回时本轮评审即中止（abort），不会出现"无选择进入评审"的状态。
- **US-5** 作为执行需求/开发/回写期 skill 的 Agent，我读到的「下一步」指引一律指向 `crctl next {cr_id}` 权威推荐，不再有"执行 X 或 Y"的等价分叉把我引向跳过评审的路径。
- **US-6** 作为治理工具链维护者，任何人日后在 CR 上下文域 SKILL.md 手写「下一步：执行 xxx-skill」都会被 lint-prompts R9 以 CONTRADICTS 阻断，17 处存量清零后不再复燃。
- **US-7** 作为 requirement-writer 的对话方，我说"批准需求"时映射表先检查评审 verdict=pass 且 blockers=[]，不再被直连 approve-requirement 后遭拒、又被降级翻译成"那先讨论架构"。
- **US-8** 作为推完 checkpoint 的 Agent，push-progress 输出摘要明确告诉我下一步以 `crctl next` 为准，引导链不再在推送后断裂。

## 3. 功能需求

### 块 A —— 代码评审 LLM 选择暂停节点（附件1 §二）

- **FR-1（新增触发输入 `review_llm`）**：`pipeline-templates/code-implementation.pipeline.json` 的 `inputs` 数组追加 `{ key: review_llm, label: 代码评审 LLM, type: text, required: false }`，placeholder/description 写明"留空则在评审前暂停由人工选择"（D-1 决策：本 CR 即实现）。
- **FR-2（插入 human_approval 节点「选择代码评审 LLM」）**：在节点 8（`0015-000000000008` push-progress）之后、节点 9（`0015-000000000009` review-code）之前插入 `{ id: 00000000-0000-0000-0015-000000000013, kind: human_approval, label: 选择代码评审 LLM, onFail: abort, timeoutMinutes: 4320 }`；`approvalPrompt` 覆盖三分支：① 触发参数 `review_llm` 已指定 → 按该模型执行并快速确认；② 留空 → 暂停询问三选一（当前会话默认模型 / 外部 CLI runner 按代码执行设置列出 / 其他指定模型）；③ 驳回 → 中止本轮评审。该节点**不写 CR 状态**（AGENTS.md 合规）。
- **FR-3（review-code prompt 头部承接选择）**：节点 9 prompt 最前面追加一段：执行评审前确认上一节点选定的评审 LLM（`{{inputs.review_llm}}` 或人工审批环节的用户选择），按该模型/runner 执行本评审，并在 `.crctl/tmp/review-code.yml` 的 dimensions 中记录 reviewer-model 留痕（自报，D-2 决策）；其余取证与落盘要求不变（评审判断写临时 payload，经 `crctl review-record --stage code --bump-attempt` 落盘 canonical），不改 crctl 契约。
- **FR-4（replayNodes 不加入选择节点）**：review-code 的 `reviewLoop.replayNodes` 保持现状（`implement-code → write-test-report → push-progress → review-code`），**不加入 0013**——原则"一次选择、全程复用"，避免每轮自修复重复询问；确需换模型重审时由人工在节点 10（代码审查通过）驳回后重走。write-test-report 的 reviewLoop（006→007）不受影响。
- **FR-5（台账同步）**：`pipeline-templates/_index.yml` 该条 `nodes: 12 → 13`，brief 补「选择代码评审 LLM（人工确认）」环节描述。
- **FR-6（README 同步）**：tools 仓 `README.md` 代码编写期节点表在「推送代码+文档统一 checkpoint」与「代码评审」两行之间插入新节点行（输入/行为/状态写入=无/是否可跳过=否）。

### 块 B —— R9 护栏 + 存量清零（附件2 §四/§六）

- **FR-7（R9 规则实现）**：`skills/shared/crctl/scripts/lint-prompts.mjs`——① `loadJudgements()` 直读 `skills/_index.yml` 提取全部 skill id 入判据集（读入 `\r\n → \n` 规范化，纪律 #1）；② `runRules()` 在 R8 块后追加 R9 块：scope `^skills/(requirement|develop|writeback|sync|cr)/` 且非 cr-show，命中条件 = 行含「下一步」且不含 `crctl next` 且含任一 skill id 或 pipeline 名模式（`requirement-authoring|architecture-design|code-implementation|feature-writeback|resume-cr|writeback|coding|architecture` + `pipeline`），级别 **CONTRADICTS**（enforce 阻断）；③ `<!-- lint-prompts:ignore -->` ±1 行豁免自动适用；④ 文件头注释规则清单追加 R9。
- **FR-8（17 处存量副本清零）**：按附件2 §4.2 表逐行改写为 §4.3 统一形态「下一步 : 以 `crctl next {cr_id}` 为准（PASS→等待人工审批；BLOCK→pipeline 自动回 {修复节点} 修复重审）」——分支语义保留、权威指针收敛；`{修复节点}` 必须是占位文本或语义方向，不得写字面 skill id（D-4 决策）。涉及 17 个 SKILL.md（requirement 4 + develop 9 + writeback 4）。
- **FR-9（push-progress 引导链闭环）**：`skills/sync/push-progress/SKILL.md` 输出摘要 `last-push-at` 行后追加「下一步 : 以 `crctl next {cr_id}` 为准」（R9 scope 内 sync 域，闭环 D2 断链）。
- **FR-10（requirement-writer 前置注记）**：`agents/requirement-writer.md` Skill 映射表「批准需求 / 推进状态 → approve-requirement」行加前置注记——仅当 `review-annotations/requirement.yml` verdict=pass 且 blockers=[] 时映射生效（D3 修复）。
- **FR-11（AGENTS.md 编辑规则条目）**：tools 仓 `AGENTS.md`「编辑规则 → 修改 Skill」追加第 7 条：CR 上下文 skill（requirement/develop/writeback/sync/cr 域）输出摘要「下一步」一律写「以 `crctl next {cr_id}` 为准」，不得手写 skill/pipeline 名映射副本（lint-prompts R9 强制）（D-3 决策）。
- **FR-12（测试向量）**：`skills/shared/crctl/scripts/test/lint-prompts.test.mjs` 按既有 R7/R8 fixture 模式追加：① 正向——CR 上下文域（fixture 路径必须落在 `skills/requirement/…`）手写 skill 副本命中 R9 CONTRADICTS，`crctl next` 形态不报；② 反向——域外（`skills/planning/…`）「下一步」不受约束；③ pipeline 名模式捕获（approve-code「下一步：writeback pipeline」类）。

### 收尾 —— 台账同步与验收

- **FR-13（同批 commit 纪律 + 自检）**：R9 规则 + 测试向量 + 17 处存量清零必须在**同一 commit**（否则 enforce 钩子阻断自身）；自检顺序：① 规则上线前 `--mode report` 确认存量命中恰为附件2 §4.2 表所列 17 处（不多不少）；② 测试向量全绿；③ 清零后 `--mode enforce` 归零；④ pipeline JSON 解析自检；⑤ pre-commit 三件套（`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce`）全绿。
- **FR-14（溯源标注）**：commit message 与代码注释延续「漂移治理」编号风格（R9 条目与 `docs/prompt-audit-report-2026-08-05.md` G5 项呼应），注明需求来源为本 CR 两份分析文档；全部改动不引入本机绝对路径（可移植性）。

## 4. 非功能需求

- **NFR-1（同批原子性）**：FR-13 的同批 commit 纪律是硬约束——R9 enforce 级别意味着规则上线与存量清零拆成两个 commit 会让前一个 commit 的 pre-commit 钩子自阻断。
- **NFR-2（零新增第三方依赖）**：lint-prompts.mjs 与测试向量只用 Node 标准库与既有工具函数；pipeline JSON 改动只增节点/输入/prompt 文本。
- **NFR-3（行尾纪律，纪律 #1）**：R9 读 `skills/_index.yml` 先 `\r\n → \n` 规范化；跨行解析失败硬失败，禁止静默降级（T04 教训）。
- **NFR-4（可移植性）**：approvalPrompt 中外部 CLI runner 枚举"按代码执行设置列出"，由目标运行时提供，tools 包不硬编码模型名；全部改动不含本机绝对路径。
- **NFR-5（human_approval 合规边界）**：新插入节点只做暂停确认与选择记录，不写 CR 状态、不替代 `crctl advance`（AGENTS.md 约束）；选择结果通过会话上下文传给下一节点，不新增 pipeline JSON 层变量机制。
- **NFR-6（基线协调）**：实施期对 `code-implementation.pipeline.json` 的改动必须叠加在 tools 仓工作区现有未提交修改（`auto_push_after_task` default false 等 3 处，属用户另行变更）之上，提交时按变更归属拆分 commit，不得把他人变更混入本 CR 提交、也不得覆盖丢失（见 §1.4 事实基线末行）。
- **NFR-7（流程决策留痕）**：两份附件文档原「不开 CR，直接提交 tools 仓」的流程决策已被用户决策覆盖，本 PRD §1.2 已记录；实施期 commit message 注明 CR-2026-023 溯源。

## 5. 验收标准

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

## 6. 成功指标

- 全库 `lint-prompts --mode enforce` R9 命中数在本 CR 完成后收敛为 0，且后续新增手写副本在 pre-commit 即被阻断（复燃率 0）。
- 代码评审暂停选择节点在 `/coding` 全量触发路径可用：留空现场选择与 `review_llm` 预选两条路径均可走通；repair 循环零重复询问。
- 每份代码评审证据（`review-annotations/code.yml`）dimensions 含 reviewer-model 留痕，评审模型可追溯率 100%。
- 需求期"写完 PRD 未评审就到下一步"的提示链漂移不复现：需求期四份 SKILL.md + push-progress 的「下一步」全部指向 `crctl next` 权威推荐。

## 7. 范围排除

**本 CR 包含**：附件1 §二 完整方案（2.1~2.6 四步改动 + 两项同步）+ 附件2 §四/§六 全部落地项（R9 规则 + 17 处清零 + push-progress 闭环 + requirement-writer 注记 + AGENTS.md 条目 + 测试向量），以及收尾自检与端到端验收。

**本 CR 不包含**：
- `crctl.mjs`、`gates.json`、`rules.json` 本体改动（附件1 §五 明确不在范围；reviewer 字段仍由 crctl 注入 `identity(ws)` 不改契约）。
- `agent-skill-matrix.yml`、`skills/_index.yml` 增删（未新增/删除 skill 无需变更）。
- 其他 7 条 pipeline 模板、develop/ 域 skill 文档的无关修订。
- 机器可读的评审模型审计（`crctl review-record --reviewer-model` 旗标 + gates.json/digest 联动——附件1 §八.3 明确属独立 CR 级改动）。
- D4 的运行时层缺口（reviewLoop maxAttempts 耗尽后 pipeline 运行时行为）——不在 tools 包管辖范围，需向平台运行时方确认耗尽语义；tools 侧以 `crctl approve` 证据门兜底（附件2 §七.1）。
- tools 仓现有 3 个未提交 pipeline JSON 修改（`auto_push_after_task` default、`source` required）——属用户另行变更，本 CR 仅按其基线叠加、不代为提交（NFR-6）。
- spec/ 域 R9 白名单扩展评估（附件2 §七.2，后续按需）。
