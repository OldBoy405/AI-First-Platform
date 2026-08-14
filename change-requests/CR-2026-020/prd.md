---
id: CR-2026-020-prd
type: PRD
cr-ref: CR-2026-020
title: 治理工具链 — writeback 机械步骤固化为入库脚本（三脚本 + SKILL 改调 + 删 writeback-backups + traceability 单一权威）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-04T21:45:00+08:00"
updated: "2026-08-04T21:45:00+08:00"
---

# PRD — writeback 机械步骤固化为入库脚本

## 1. 概述

### 1.1 问题陈述

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

### 1.2 解决方案摘要

把三个节点的机械步骤固化为 `tools/skills/shared/scripts/` 下**版本化的独立脚本**，SKILL.md 改为"调用脚本 + 核对 dry-run diff"，并把已核实事实写进 SKILL 的事实基线段；同时**删除 writeback-backups 步骤**（git commit 即备份与审计）、**收敛双份 traceability.yml 为 specs 侧单一权威文件**。

消除调试循环的关键不是"把补丁脚本写得更稳"，而是**从"增量文本补丁"改为"结构化处理"**，按文件性质分三类（详见 FR-5）：可从其他来源推导的文件全量重建（天然幂等、无锚点）；累积性结构化字段用"解析→改对象→重序列化"（幂等、无文本锚点）；只有真正的累积性正文（PRD/SDD 里程碑节）保留锚点追加，并以行首/字段名结构锚点 + 锚点唯一性硬失败兜底。

**与 CR-2026-019 边界（关键，避免误读为推翻刚定型的决策）**：CR-2026-019 曾**否决**"账本操作脚本入库 `tools/skills/shared/scripts/`"，理由是账本（`_backlog.yml` / `_history.yml` / 各 CR `tasks/_index.yml`）承载状态机、有并发写入语义，第二条脚本通道会绕开 crctl 的 CAS + 审计 + 门禁而长期漂移。**本 CR 的对象不同**：specs/`{PRD,SDD,traceability}`、`specs/_index.yml`、`delivery/task/` 及其 `_index.yaml` 是 git 跟踪的内容文件，无状态机、无并发写语义，**git commit 本身就是它们的 CAS 与审计**；它们当前唯一的写入通道恰恰是"每次会话现写的一次性脚本"（N 条临时通道），固化为版本化脚本是把 N 条收敛为 1 条，方向与账本场景相反。因此本 CR **不做成 crctl 子命令、不接入 casWriteMulti / CAS 审计基础设施**，脚本一律**不触碰**账本文件（`_backlog.yml` / `_history.yml` / `cr.md` / 各 CR `tasks/_index.yml`）——那些仍只走 crctl。

### 1.3 事实基线（已核实，纪律 #4）

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

## 2. 用户故事

- **US-1** 作为执行 writeback 的维护者，我调用一条入库脚本即可完成 PRD/SDD 回写与 `specs/_index.yml` 字段更新，不再会话内现写脚本、不再逐个踩锚点/转义/幂等的坑。
- **US-2** 作为执行 writeback 的维护者，我调用入库脚本完成 tasks 回写，重跑同一 CR 是 noop（幂等），不会产生"首跑成功、重跑失败"的补丁脚本。
- **US-3** 作为执行 writeback 的维护者，traceability 由脚本从证据源全量重建为**唯一**的 specs 侧文件，我不再需要维护两份、也不再有"两份是否一致"的校验负担。
- **US-4** 作为平台维护者，回写脚本版本化、可测试、可复用，且明确不与账本共用 CAS/审计机制——specs/delivery 内容文件的审计由 git 历史承担，账本写入仍只走 crctl 单一通道。
- **US-5** 作为流水线的执行者，我在节点启动时读到 SKILL 里已核实的事实基线（里程碑命名、索引格式、参与仓规则），不再每节点重复现场调研与对照先例。
- **US-6** 作为平台维护者，回写前不再产生 `writeback-backups/` 冗余备份目录，旧版本经 `git log`/`git show`/`git revert` 追溯，CR 目录不再堆积无人查阅的备份文件。

## 3. 功能需求

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

## 4. 非功能需求

- **NFR-1（行尾纪律，纪律 #1）**：脚本对文件读入先 `\r\n → \n` 规范化、解析用 `split(/\r?\n/)`；YAML/跨行解析或（PRD/SDD 追加场景的）锚点匹配失败一律**硬失败报错**，禁止静默降级为空/取一侧。
- **NFR-2（幂等）**：同一 CR 对同一脚本重跑为 noop 并显式输出（已应用则跳过），不产生"首跑成功、重跑失败"，无需补丁脚本。
- **NFR-3（自带 dry-run + 自检，不另写 verify）**：脚本提供 dry-run 模式（打印将产生的 diff 不落盘）与末尾自检断言（回写后校验关键字段），取代 CR-2026-019 中另写、且断言文本自身写错过的一次性 verify 脚本。
- **NFR-4（零新增依赖）**：仅用 Node 标准库与复用的 crctl YAML 工具函数，不加第三方包。
- **NFR-5（与账本机制解耦）**：脚本不触碰 `_backlog.yml` / `_history.yml` / `cr.md` / 各 CR `tasks/_index.yml`（这些仍只走 crctl），不引入 CAS/审计/门禁；仅写 specs/ 与 delivery/ 内容文件。
- **NFR-6（可测试、可回归）**：三个脚本各自留一个可运行自检（最小化，dry-run 断言或独立 test），一次运行验证核心机械逻辑不回归；不引入测试框架/fixture，不搞逐函数套件。

## 5. 验收标准

- **AC-1**（FR-1/FR-5）：对已存在基线的 spec 调用 `writeback-prd-sdd.mjs`，PRD/SDD 新增里程碑节且既有节原样保留、H 下沉一级；`specs/_index.yml` 对应 `features[]` 的 `cr-history[]` 追加本 CR、`current`/`cr-ref`/`updated` 更新；重复运行同一 CR，`cr-history[]` 不产生重复项。
- **AC-2**（FR-2/FR-5）：调用 `writeback-tasks.mjs` 后，done 任务按 `TASK-{version}-{cr_id}-{NN}-{slug}` 落地 `delivery/task/`、frontmatter 含 `spec-id`/`version`、`delivery/task/_index.yaml` 追加对应条目；重跑为 noop（已登记 id 全部跳过，文件与索引无变化）。
- **AC-3**（FR-3/FR-7）：调用 `writeback-traceability.mjs` 后 `specs/{spec_id}/traceability.yml` 由证据源全量重建、tasks 条目命名与 AC-2 一致；`change-requests/{cr_id}/traceability.yml` 未被要求同步，流程无"两份一致性校验"步骤；`merge-commits[]` 缺失时脚本非零退出。
- **AC-4**（FR-4/NFR-5）：`grep` 三脚本实现，均不含 casWriteMulti/审计/门禁调用、不写 `_backlog.yml`/`_history.yml`/`cr.md`/CR `tasks/_index.yml`；脚本不以 crctl 子命令形式注册（`crctl help` 无新增子命令）。
- **AC-5**（FR-6）：回写一个 spec 后 `change-requests/{cr_id}/` 下**不产生** `writeback-backups/` 目录；三份 SKILL.md `grep` 无"备份/metadata.yml/writeback-backups"残留指引。
- **AC-6**（FR-8/FR-9）：三份 writeback SKILL.md 与 `merge-feature-branch` SKILL.md 含"调用脚本 + 核对 dry-run diff""事实基线"段；task 命名在 pipeline 模板、traceability SKILL、writeback-tasks SKILL 三处一致（`grep` 无 `TASK-{ver}-{CR-NNN}` 类作废格式）。
- **AC-7**（NFR-2/NFR-3）：每个脚本 dry-run 输出预期 diff 不落盘；无 dry-run 时落盘后自检断言通过；对同一 CR 连续运行两次，第二次显式输出 noop。
- **AC-8**（NFR-1/NFR-6）：脚本对含 `\r\n` 的输入正确规范化，PRD/SDD 追加锚点命中 0 次或多次时硬失败（非零退出）；三脚本自检一次运行通过。

## 6. 成功指标

- 下一个走完整 writeback 的 CR，流水线总耗时 **≤15 min**（基线 CR-2026-019：~30 min），回写环节**零脚本调试循环**（基线：3 次）。
- 回写期"造工具/调试"时间从约 20 min 降至仅"调用脚本 + 核对 dry-run 输出"。
- 冗余数据清零：新 CR 不产生 `writeback-backups/` 目录；traceability 仅 specs 侧单一权威文件，无"两份一致性"步骤。
- 会话内现写脚本处理 specs/delivery 回写的次数降为 **0**（纪律 #7 适用范围从账本扩展到回写产物，落到工具层）。

## 7. 范围边界

**本 CR 包含**：三个入库脚本 + 三份 writeback SKILL.md 改调与事实基线段 + `merge-feature-branch` SKILL 事实基线段 + 删除 writeback-backups 步骤 + 收敛 traceability 为单一权威 + task 命名三处一致化 + 脚本自检。

**本 CR 不包含**：状态机与账本结构改动；crctl 子命令新增；CAS/审计基础设施接入；`merge-feature-branch` 合并/补偿逻辑改动（仅补其 SKILL 事实基线）；merge/archive 的 git 网络往返耗时优化（~8 min 为流程刚性成本）。
