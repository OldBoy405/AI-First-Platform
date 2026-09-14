---
id: CR-2026-066-prd
type: PRD
cr-ref: CR-2026-066
title: CR-P3：评审 PASS 发布与 checkpoint 委派收敛 — 阶段终点发布点前移、审批后 checkpoint 节点退役、归档后本地 trunk 同步
target-version: 0.39
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-14T10:47:00+08:00
updated: 2026-09-14T11:22:00+08:00
---

# 1. 概述

## 1.1 问题陈述

需求来源是 Issue AIFI-27 附件《CR-P3：评审 PASS 发布与 checkpoint 委派收敛方案》（19,297 B，附件 id `01a09dc1-7230-7618-8137-9c0b8adbe1b8`）§1–§2。CR-2026-063（AIFI-24）全生命周期的实测暴露出一组**发布点位置**问题：

1. **阶段终点 checkpoint 位于人工审批 gate 之后**（requirement `…0007`、architecture `…0005`、code `…0012`）。agent 驱动模式下，阶段 owner 的那次 run 在 gate 之前就已结束；要执行门后节点**必须新开一次唤醒**，而 `agent-skill-matrix.yml` 明令 `cr-coordinator-agent` 不可执行 `push-progress`，于是这一步只能被单独委派出去。CR-2026-063 的 6 次 checkpoint 里有 3 次是这种「只做这一步」的单独委派（来源 §1.1）。
2. **冗余发布点**：requirement `…0003`（PRD 草稿）、code `…0003`（设计/任务）、`…0008`（代码+文档统一 checkpoint）、`…0015`（评审 PASS 后、审批前）都是为「让远端有批次」而存在的额外节点。其中 `…0008`/`…0015` 还使「实现→评审→审批」窗口内出现两次 checkpoint，而这些节点在 agent 驱动模式下同样没有强制力（无 runtime 检查「跑没跑」，`abort` 只是纸面强度）。
3. **评审对象与发布对象之间没有强制对账**：评审者按 worktree 文件出 verdict，发布由**另一个**节点在之后执行；「审的不是发的」这一窗口只靠流程纪律约束，没有机械判据。
4. **归档后本地主 checkout 与 origin 不一致**：`reconcileLocalTrunks(ctx)` 目前只被 merge 调用；归档是 CR 的最后一个动作，此后没有任何节点把各仓主 checkout ff-only 对齐 origin，只能靠 owner 手工执行。

**根因结论（来源 §1.2，本 PRD 采纳）**：门后有没有节点，唤醒都得发生；消除单飞要靠**「发布点位置 + 搭车规则」**，不是靠节点存在与否。因此本 CR 的两条主杠杆是：把阶段终点发布点前移到**评审 PASS**（由评审者执行，每阶段恰好一次），并把审批后的发布交给**搭车**（下一阶段评审 checkpoint / `merge` 的 publication preflight）。

## 1.2 解决方案摘要

按来源 §3「目标节奏」逐条落地（每组都锚定「仓 + 文件」，见 §1.3.1 与 §3 各 FR）：

1. **评审 PASS 发布**（FR-1）：`review-requirement` / `review-tech-design` / `review-dev-plan` / `review-code` 四个 SKILL 在 PASS 分支新增发布步骤——`review-record`（及该阶段既有 `advance`）完成、工作树干净之后调用既有 `push-progress`（`message = <阶段>评审通过`），消费 `phase` / `batchId` / `repositories[]` / `metadataCommit` 并在评审报告透传；BLOCK 分支不发布。
2. **评审前置干净检查**（FR-2）：四个 review SKILL 的 Step 1 新增 `crctl workspace inspect <CR>` 全部 resources `classification=healthy`（`dirty=false`）前置（该前置是**只读**既有子命令，其授权由 FR-8 同步写入评审者允许面，见 §1.5 第 5 条）；不满足则**不评审**、报告「存在未提交内容，请作者先提交」，评审者不得代提交。理由：`push-progress` 是 `git add -A` 全仓提交，评审者发布前必须确保不会把作者未提交内容一并发布。
3. **发布与评审对象对账**（FR-3）：评审者发布后必须校验「发布的就是评审的」——requirement / tech-design 用注解 `subject-sha256`（PRD / SDD 文件）在 KB 发布批次的 `sourceSha` 上复算 LF-only sha256；dev-plan 用 plan.md + 全部 `TASK-*.md` 的 composite digest；code 用 `review-annotations/code.yml#release-subjects[].reviewed-source-sha` 与 `repositories[].sourceSha` 逐仓比对。不等即 `CONTRACT_DRIFT` 技术中止（**不改 verdict**），报原始差异。
4. **审批后与冗余 checkpoint 节点退役**（FR-4 / FR-5）：删除 requirement `…0007` / `…0003`＋输入 `auto_push_after_prd`、architecture `…0005`、code `…0012` / `…0003`＋输入 `auto_push_after_task` / `…0008` / `…0015`＋审批提示前提句，并从 `review-code.reviewLoop.replayNodes` 删掉 `…0008` 一项；节点数 requirement 7→5、architecture 5→4、code 16→12，`_index.yml` 计数与 `pipeline-structure.test.mjs` 断言同步。
5. **审批后发布由搭车承担**（FR-6 / FR-7）：code 路径由 `merge` 的 publication preflight（`MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` + 结构化 `recovery`）在**同一 writeback run 内**硬兜底；requirement / tech-design / dev-start 的审批提交由下一阶段评审 PASS checkpoint 带回；**任何情况下不得为 checkpoint 单开 task/委派**——该硬规则写入 coordinator / dev / delivery / reviewer 四份 Agent 合同（tools 公共 Prompt 为唯一事实源，multica 侧同步部署副本）。
6. **评审者的发布职责与权限**（FR-8）：`agent-skill-matrix.yml` 的 `quality-reviewer-agent` 从 `forbidden` 移除 `push-progress`、在 `can-call` 增加 `push-progress`（`checkpoint` 仍留在 `forbidden`——评审者只用 `push-progress` Skill，不用 `crctl checkpoint` 原语），`AGENT-SKILL-MATRIX.md` 的「本 CR 权限变更」节同步；并把 FR-2 强制前置所需的**只读** `workspace inspect` 写入该 actor 的 crctl 允许面（三处载体同步：矩阵注释、`AGENT-SKILL-MATRIX.md` 变更行、tools 与 multica 两份 `quality-reviewer-agent` 的受限 crctl 权限块——B-1 闭合）。
7. **FR-07 口径重写 + 归档后 trunk 同步 + 平台伴随项**（FR-9 / FR-10 / FR-11）：`push-progress/SKILL.md`、`README.md`、`openwiki/pipelines/overview.md`、`dir-graph.yaml#pipeline_templates.contract` 同步为「阶段终点完成条件 = 评审 PASS 的 checkpoint」；`archiveCr` 复用既有 `reconcileLocalTrunks(ctx)` 并在返回结构新增 `localTrunkSync`；节点集变化对平台生成物（`emit-registry.mjs` digest、`gate_nodes_gen.go` 的 `NodeID/Seq`）的影响只**登记契约变化**，重生成由 owner 在部署窗口执行。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

评审 PASS 时由评审 agent 发布阶段产物（需求 / 技术设计 / plan-TASK / code 各一次，含发布对账与评审前置 clean 检查）；退役全部「审批后 checkpoint」节点与冗余 checkpoint 节点（requirement 7→5、architecture 5→4、code 16→12）；未发布的审批提交由下一阶段评审 checkpoint 或 `merge` 的 publication preflight 搭车承担、任何情况下禁止单开 checkpoint 委派；归档后复用 `reconcileLocalTrunks` 把各仓主 checkout ff-only 对齐 origin（archive 返回新增 `localTrunkSync`）。不引入平台执行层、不新增 pipeline 节点 / 评审维度 / 账本字段 / 观测指标、不改 crctl 事务层与 `recovery` 合同、不复活 `recoverCommand`。

### 1.3.1 scope_in 边界（原文前缀，评审核对用）

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

### 1.3.2 目标仓库与版本

- 代码实施在 `../tools/`（pipeline JSON、SKILL.md、Agent Prompt、权限矩阵、crctl lib 与测试）与 `../multica/`（四份 Prompt 部署副本）。
- knowledge-base 承载本 PRD 与来源附件；本 CR 不改 KB 的 `specs/`、`delivery/`、`docs/`。
- `target-version` 继承 `cr.md` 的 `0.39`（注册阶段由 owner 指定，`crctl version-set` 之外无改写入口）；`target-spec-id` = `ai-first-platform`，由注册事务写入双账本，本文件不得改写。
- **部署不在本 CR 范围内**：平台 DB 的 Prompt 投影、`gate_nodes_gen.go` / registry digest 重生成由 owner 执行（FR-11 只登记契约变化）。

### 1.3.3 契约说明（确定性四查适用面）

本 CR 有两处**用户可调用契约**的变更，四查（幂等 / 权限 / 错误闭包 / 副作用）落点为 FR-1（Skill 契约）、FR-10（crctl CLI 契约）与 AC-1、AC-8：

- **Skill 契约**（FR-1、FR-2、FR-3）：四个 review SKILL 的调用面与落盘面**不变**——不新增 Skill 参数、不新增落盘文件、不新增状态转换、不新增错误码；新增的只有「PASS 分支内的一次 `push-progress` 调用 + 一次对账 + 前置 `workspace inspect` 只读检查」。该前置是 crctl **既有只读子命令**（不新增命令、不新增错误码），其授权由 FR-8 的 actor 允许面变更承载：`crctl workspace inspect` 必须在 SKILL 文本与 actor 允许面**两侧同时**存在，由 AC-3 与 AC-4 联合断言（B-1）。
- **crctl CLI 契约**（FR-10）：`crctl archive` 的返回结构**新增** `localTrunkSync` 字段；既有字段（`commit`、`lastCleanupError`、`remaining`、`preservedRefs`、`recovery`、`warnings`）与退出码语义不变，不新增错误码。

其余 FR 是 Prompt / 文档 / 矩阵 / 测试侧的原位修订（FR-4~FR-9、FR-11），不定义新的用户可调用契约；其验收以「文本合同 + 检索/测试证据」形式给出（AC-2~AC-7、AC-9、AC-10）。

## 1.4 当前事实（落笔前核实）

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

## 1.5 对来源文档的事实更正与需人工确认的口径

1. **FR-10 的分类清单不完整（本 PRD 以代码事实为准）**：来源 §4 FR-10 写 `skipped(wrong-branch|dirty|diverged)` 与 `failed(fetch-failed|ff-only-failed)`；实测 `reconcileLocalTrunks` 还有 `failed(trunk-unavailable)`（`rev-parse --verify origin/<trunk>` 失败时），且行形状含 `trunk` 字段。本 PRD 的 FR-10 与 AC-8 按**实测 6 个 reason** 写；该项**不改变**来源的方案取向（复用既有函数、只加调用点与返回字段）。
2. **删除后不再有 push-progress 节点（来源未写明的口径补充）**：FR-4 删 3 个、FR-5 删 4 个之后，requirement 剩 5 节点、architecture 剩 4 节点、code 剩 12 节点，**三份 JSON 中不再存在任何 `ref=push-progress` 的节点对象**——发布一律由 review SKILL 内的 `push-progress` 调用承担，pipeline 里不再有「发布节点」这一形态。AC-1 据此采用两条判据：「不存在任何位于 `human_approval` 之后的 push-progress 节点」**且**「`nodes[].ref=push-progress` 计数为 0」——只写前者不足以表达删除后「零发布节点」的更强事实，只写后者不足以表达「不得在审批后再新增发布节点」。
3. **Skill 契约的发布动作不在 `crctl` 子命令面**：评审者的发布调用的是 **`push-progress` Skill**（其内部调用 `crctl checkpoint`），不是让评审者直接执行 `crctl checkpoint`。因此 FR-8 只把 `push-progress` 移出 `forbidden`、把 `checkpoint` **留在** `forbidden`；`cr-prompts-revised/quality-reviewer-agent.md:46` 的 crctl 禁止清单**不改**。此项需在人工审批时一并确认。
4. **§1.1 的事实面限定**：6 次 checkpoint / 3 次单独委派的具体数字来自来源文档记载（见 §1.4 事实 20），本 CR 的目标与验收不依赖这些数字，只依赖「门后节点必须重新唤醒」这一机制性结论。
5. **评审前置 `workspace inspect` 的授权面（本 PRD 收口裁定，需人工一并确认）**：来源 FR-2 把只读 `crctl workspace inspect` 写成四个 review SKILL 的强制前置，但该 actor 的 crctl 允许面（矩阵注释与 multica 部署副本的穷尽式白名单）不含它（§1.4 事实 12）——同一份合同下会得到两种互斥读法：「违反自己的穷尽式权限合同去执行前置」或「跳过前置而违反 FR-2」。本 PRD 采用评审建议的**方案 (a)**：在 FR-8 明确把**只读** `workspace inspect` 加入该 actor 的 crctl 允许面，并把三处载体（`agent-skill-matrix.yml` 注释、`AGENT-SKILL-MATRIX.md` 变更行、tools 与 multica 两份 `quality-reviewer-agent.md` 的受限 crctl 权限块）同步列入 §1.3.1 第 7、8、14 行；`checkpoint` 仍在禁止面（发布只经 `push-progress` Skill，不放开 crctl 原语）。该授权**不新增** crctl 子命令、不新增错误码、不引入任何写入面，落地由 AC-4 的权限面闭合判据机械复核。

## 1.6 修订记录

- 修订 0.2（2026-09-14，cycle1 attempt1 BLOCK 回修）：闭合 **B-1**——FR-2 的强制前置 `crctl workspace inspect` 与 `quality-reviewer-agent` 的穷尽式权限合同互相矛盾；按评审给出的**方案 (a)** 把**只读** `workspace inspect` 写入该 actor 的 crctl 允许面：§1.3.1 第 7、8、14 行登记三处载体（矩阵注释 / `AGENT-SKILL-MATRIX.md` 变更行 / tools 与 multica 两份 `quality-reviewer-agent.md` 的受限 crctl 权限块），FR-8 新增载体同步条目，§1.5 新增第 5 条授权面裁定，§1.4 事实 12 补登穷尽式白名单证据，AC-4 增加权限面闭合判据（两侧同时断言 + 反向断言 `crctl checkpoint` 不出现在 review SKILL）。同轮一并承接 6 条 suggestions：S-1（AC-6 载体/时点/延期验证点）、S-2（FR-3 只读取证手段，明示 `git show` 不可用）、S-3（FR-7 增加既有测试面静态文本断言）、S-4（`dir-graph.yaml` contract 第 5 条改显式枚举）、S-5（delivery-agent 的 `recovery` argv 例外）、S-6（§1.4 新增事实 22 与 §7 承接 §8 取舍/回滚边界）。
- 初稿（2026-09-14）：按来源附件 §1–§9 与注册摘要（`cr.md` summary）起草；基线事实在 §1.4 三个 worktree HEAD 上逐条核实。FR 编号与来源 §4 的 FR-1~FR-11 一一对应（不重编号）；AC-1~AC-9 对应来源 §5；**AC-10 为本 PRD 新增**，用于把来源 §2.2 的 scope_out 与 §7 的「不与其他 CR 并发」写成可检查约束（来源文档没有对应 AC）。§1.5 记录三处对来源文档的事实更正与一处口径解释，需在人工审批时一并确认。

# 2. 用户故事

- **US-1 阶段 owner（dev-agent / requirement-writer）**：作为按 Pipeline 节点的 Agent，我希望评审 PASS 后远端就有一个「产物 + verdict + 状态」的完整批次，这样我的 run 在人工 gate 前结束后不必再被唤醒去补一次发布。
- **US-2 评审者（quality-reviewer-agent）**：作为出 verdict 的评审者，我希望发布的就是我刚评审的那份内容（前置 `healthy` 检查 + 发布后对账），这样我不会把自己的署名绑定到没看过的内容上，也不会替作者提交未完成的工作。
- **US-3 CR 协调者**：作为只读 `crctl status/next` 与路由的协调者，我希望「审批后发布」有一条明确的搭车路径（下一阶段评审 checkpoint 或 `merge` 的 publication preflight），这样我不会被逼着为单个 `push-progress` 单开一次委派。
- **US-4 换机 / 接手的协作者**：作为中途接手的人，我希望每个阶段结束时远端都存在完整批次（`repositories[].confirmed=true`、`metadataCommit` 非空），这样我能按 checkpoint 续接而不依赖本地未发布状态。
- **US-5 部署 owner**：作为把 Prompt 部署进平台的人，我希望「阶段终点完成条件」在 `README`、`openwiki`、`push-progress` SKILL 与 `dir-graph.yaml` 里是**同一句口径**，这样我不会按两套说法部署。
- **US-6 走完归档的 delivery-agent / owner 机器**：作为归档的执行者，我希望 `crctl archive` 的返回直接告诉我每个仓的主 checkout 是否已与 origin 对齐（`unchanged` / `synced` / `skipped` + `reason`），这样我不必手工逐仓 `fetch` + `merge --ff-only`，也不会让本地停在旧 trunk 上。
- **US-7 维护 tools 的开发者**：作为改 pipeline JSON 的人，我希望节点退役与 `_index.yml` 计数、`pipeline-structure.test.mjs` 断言、平台生成物登记在同一份 diff 内闭合，这样 CI 不会在中间态变红，也不会出现「JSON 删了、平台 `Seq` 没重生成」的静默漂移。
- **US-8 本 CR 的 reviewer**：作为本 CR 的评审者，我希望能逐条核对「哪个仓的哪个文件被原位改了、哪条断言变了」，使得这次收敛不引入第二套发布流程或新的观测负担。

# 3. 功能需求

## FR-1 评审 PASS 发布（4 个 review SKILL）〔来源 §4 FR-1〕

`review-requirement` / `review-tech-design` / `review-dev-plan` / `review-code` 四个 SKILL 在 PASS 分支新增一个发布步骤，合同如下：

1. **触发条件（顺序固定）**：该阶段 `review-record` 成功落盘 → 该阶段既有 `advance` 完成（`review-tech-design` / `review-dev-plan` / `review-code` 的既有 `advance` 语义不变；`review-requirement` 为既有 `advance --to requirement-reviewing --trigger review-requirement`）→ `git status --porcelain` 干净 → 才执行发布。
2. **发布调用**：调用既有 `push-progress` Skill，`message` = `<阶段>评审通过`（如 `需求评审通过` / `技术设计评审通过` / `开发计划评审通过` / `代码评审通过`）；**不新增 Skill 参数**（只用既有 `cr_id` + `message`），不新增落盘文件。
3. **结果透传**：消费并**逐字**透传 `phase` / `batchId` / `repositories[]` / `metadataCommit` 到评审报告；`phase=complete` 且 `changed=false`（no-op）视为成功。
4. **BLOCK 分支不发布**：`verdict=block` 时不调用 `push-progress`（回修中间态不上远端）。
5. **失败语义（不改 verdict、不重评）**：发布失败（含 `CHECKPOINT_SENSITIVE_PATH` / `CHECKPOINT_REMOTE_*` / `TX_*`）时——verdict 与评审账本**保持已落盘结果不变**，不重评、不改 verdict、不代作者提交、不回退状态；报告原始错误码与 `recovery`，按 `recovery` 重试**同一个** `push-progress`（不产生第二次评审）；发布失败**不阻塞**任何本地门禁。
6. **幂等与副作用**：重复发布以 `crctl checkpoint` 既有幂等语义为准（同内容重放 `changed=false`）；发布只经 `push-progress`/`crctl` 写 `_backlog.yml` 的 checkpoint 字段，评审者不得直接编辑任何账本。
7. **不改的部分**：四个 review SKILL 的评审维度、`verdict`/`blockers`/`suggestions` 结构、payload YAML 子集边界、`reviewLoop` 语义与状态转换全部不变。

## FR-2 评审前置干净检查〔来源 §4 FR-2〕

四个 review SKILL 的 **Step 1 前置校验内**（既有 Step 1.5 pre-review gate **之前**，两者都是零写入，故相对顺序不构成副作用面；钉定该位置是为了可机械核对）新增：

- 执行只读的 `crctl workspace inspect <cr_id>`，要求**全部** resources 满足 `classification=healthy`（等价 `dirty=false`）。
- 不满足时：**不进入评审**——不写临时 payload、不调用 `review-record`、不 `advance`、不改 status、不发布；报告须含**逐仓的 dirty 事实与该仓未提交文件清单**，并给出「存在未提交内容，请作者先提交」的明确指示。
- **不得**由评审者 `git add` / `commit` / `stash` / 清除作者未提交内容。
- 该检查**不新增 crctl 子命令、不新增错误码**（复用 `workspace inspect` 既有只读输出）。
- **授权来源（B-1 闭合）**：该前置由 FR-8 的允许面变更授权——`workspace inspect` 是 crctl 既有只读子命令，写入 `quality-reviewer-agent` 的 crctl 允许面后，SKILL 侧的前置与 actor 侧的权限合同指向同一件事。**不得只改 SKILL 而不改允许面**：两侧必须同时存在（缺任一侧即 CI 变红，判据见 AC-3 与 AC-4）；该前置不产生任何写入，也不改变 FR-1 的发布顺序。

## FR-3 发布与评审对象对账〔来源 §4 FR-3〕

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

## FR-4 审批后 checkpoint 节点全部退役〔来源 §4 FR-4〕

从 pipeline JSON 中**删除节点对象**（不是改 `onFail`、不是加开关）：

| pipeline | 删除节点 | 删除输入 |
|---|---|---|
| requirement-authoring | `00000000-0000-0000-0011-000000000007`（推送需求审批结果 checkpoint） | — |
| architecture-design | `00000000-0000-0000-0016-000000000005`（推送架构设计到远端） | — |
| code-implementation | `00000000-0000-0000-0015-000000000012`（推送代码审批结果到远端） | — |

约束：不新增替代节点；不把删除实现为「保留节点 + `onFail: skip` + 默认关闭的开关」（来源 §1.3 已排除该方案：门后节点在 agent 驱动模式下没有强制力，`abort` 只是纸面强度）；不重编号其它节点的 `id`（`id` 是稳定 UUID，删除后不回收、不复用）。

## FR-5 冗余 checkpoint 节点退役〔来源 §4 FR-5〕

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

## FR-6 审批后发布由搭车承担（不得单开委派）〔来源 §4 FR-6〕

- **code 路径**：`merge` 的 publication preflight 语义**不变**；新增明确要求——writeback run 收到 `MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` 时，按 `error.recovery`（`executable` + `args[]` + `cwd`，`shell:false`）**就地执行一次**该命令，然后**在同一 writeback run 内重跑 merge**；不得把它转成一次新的委派或新 task。
- **requirement / tech-design / dev-start 路径**：审批提交由**下一阶段的评审 PASS checkpoint** 带上远端（无需任何额外动作）——这是设计取舍：审批是**网络无关的本地账本事务**，审批提交在下一阶段评审前只在本地，**换机恢复需重签一次**；该取舍必须写入 PRD/SDD 的事实节并在交付说明中明示。
- **禁止面**：不得为 checkpoint 单独创建 task/委派。checkpoint 只允许出现在三处：① 评审 run 内（FR-1）；② 已排定的下一阶段委派**内**（同一 run）；③ `recovery` 指定的**同 run** 内重跑。
- 反向验收：实施期与演练期观察到的「为单个 `push-progress`/checkpoint 单独开 task」次数 = 0（AC-6）。

## FR-7 搭车规则写入 Agent 委派合同〔来源 §4 FR-7〕

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

## FR-8 评审者的发布职责与权限〔来源 §4 FR-8〕

- `agent-skill-matrix.yml` 的 `quality-reviewer-agent`：`forbidden` **移除** `push-progress`；`can-call` **增加** `push-progress`。`checkpoint` **保留**在 `forbidden`（FR-8 只放开 Skill，不放开 crctl 原语；见 §1.5 第 3 条）。
- 该 actor 的 crctl 允许子命令注释同步为：`status` / `next` / **只读 `workspace inspect`**（FR-2 的 Step 1 强制前置，B-1 闭合）/ 对应 review 的 `gate` / `review-record` / `advance`；**不新增** `checkpoint`，也不放行其它写入型子命令。
- **允许面的载体同步（三处，缺一即交付缺陷）**：① `agent-skill-matrix.yml` 的 `quality-reviewer-agent` 块注释；② `AGENT-SKILL-MATRIX.md`「本 CR 权限变更」节的本 CR 行（约束列写明 `workspace inspect` 为只读前置）；③ `../tools/agents/quality-reviewer-agent.md` 与 `../multica/cr-prompts-revised/quality-reviewer-agent.md` 的受限 crctl 权限块——multica 副本的穷尽式白名单必须把只读 `workspace inspect` 列入允许项（其禁止面枚举保持含 `checkpoint` 不变），tools 副本的「权限事实源」节必须给出同一允许面声明，不得在同一份合同下留第二种读法。
- `AGENT-SKILL-MATRIX.md` 的「本 CR 权限变更」节追加本 CR 一行（`quality-reviewer-agent` / 新增 can-call `push-progress` / 约束：仅在对应 review SKILL 的 PASS 分支内发布一次，不修改业务文件、不推进状态、不改 verdict）。
- 评审者边界（写进 Prompt 与 SKILL）：**只发布、不修改**业务文件；发布失败**不改 verdict**、不重评、不代提交；评审者不承担任何状态推进（`advance` 例外仅为各 review SKILL 既有要求）。
- 平台侧把 `push-progress` 绑定给 `quality-reviewer-agent` 属 **owner 部署动作**（本 CR 交付后的部署项，不在代码范围内）；更新后的 `quality-reviewer-agent` 部署副本（含放宽后的只读 crctl 允许面）必须在同一部署窗口同步生效——在部署前，Multica 侧实际运行的副本仍是旧白名单（FR-2 与 AC-4 的机械断言只约束仓库内文本，部署时序由 owner 把握）。

## FR-9 FR-07 口径重写〔来源 §4 FR-9〕

`skills/sync/push-progress/SKILL.md`（现有 L9 的「调用时机」句）、`README.md`（第 6 节 checkpoint 行）、`openwiki/pipelines/overview.md`（`/requirement`、`/architecture`、`/coding` 三段与「不变量」清单）、`dir-graph.yaml#pipeline_templates.contract`（涉及 checkpoint / replayNodes 的条目）同步为同一口径：

> **阶段终点完成条件 = 评审 PASS 的 checkpoint**（由评审者执行，每阶段一次）；审批后不再有 checkpoint 节点，未发布的审批提交由下一阶段评审 checkpoint 或 `merge` 的 publication preflight 搭车承担；发布失败保持当前状态、重跑同一 checkpoint，**不重新评审 / 不重新审批**。

约束：不新增文档体系（新不变量写成既有文档内的一句话）；`openwiki/operations/` 与 `openwiki/pipelines/overview.md` 之间不产生第二套口径；`dir-graph.yaml` 的 `pipeline_templates.contract` 仍必须表达「新增或修改 pipeline JSON 后同步 `_index.yml` 计数」与 reviewLoop 重放清单两条既有约束；其中第 5 条（现文「按顺序列出修复、证据、checkpoint 与当前评审节点」）必须**改写为显式枚举**——评审 PASS 发布发生在当前评审节点**内部**、不再是独立 replay 节点（且 architecture 与删除后的 code `replayNodes` 均不含 checkpoint 项），故该条须写为「按顺序列出修复、证据、基线重核与当前评审节点」（或等价地显式写明「评审 PASS 发布不再是 replay 节点」），不得保留会把实现期读成「`replayNodes` 里应有一个 checkpoint 项」的旧词法。

## FR-10 归档后本地各仓与 origin 一致〔来源 §4 FR-10〕

1. **复用既有函数**：`archiveCr` 事务完成后调用既有 `reconcileLocalTrunks(ctx)`（不新写同步算法、不改该函数内部判据与分类）。
2. **返回结构新增字段**：`archiveCr` 返回值新增 `localTrunkSync`，与既有 `recovery` 同级并存（`recovery` 语义与字段名不变）；行形状沿用 merge 既有形状 `{repo, trunk, before, remote, after, status, reason}`。
3. **分类语义**（以实测为准，见 §1.5 第 1 条）：`status ∈ {unchanged, synced, skipped, failed}`；`reason ∈ {wrong-branch, dirty, diverged, fetch-failed, trunk-unavailable, ff-only-failed}`（`status=unchanged|synced` 时 `reason=null`）。
4. **只做 ff-only，永不破坏本地**：只处理 `dir-graph.yaml#repositories` 声明的**主 checkout**；**永不** `reset` / `clean` / `stash` / 强推 / 改动本地在途修改。
5. **dirty 策略**：主 checkout dirty 时**仍然跳过并如实报告**（`skipped` + `reason=dirty`），不改动本地在途修改；报告给出逐条 `reason` 与**人类可执行的补救说明**（不要求本 CR 自动处理）。
6. **失败不阻断归档**：该步骤是 best-effort，逐仓失败只反映在返回行；**不新增**错误码、不改变 `crctl archive` 的退出码语义、不改变既有 `phase=complete` / `phase=cleanup-pending` 分类、不写 journal/账本。
7. **幂等**：归档幂等重放（`changed=false`、`remaining=[]` 重跑）时 `localTrunkSync` 仍按当次实况返回，不产生新 commit、不产生第二次清理。
8. **文档同步**：`skills/cr/cr-archive/SKILL.md` 的结果分类表与输出块新增 `localTrunkSync` 字段与分类说明；delivery-agent 的最终汇报面包含该字段。
9. **可拆出**：若 SDD 阶段判定 CR 尺寸过大，FR-10 可被 owner 拆为后续 CR；拆出时必须同步缩减 AC-8、`archive-tx.test.mjs` 的新增用例与 §6 对应指标，并在本 CR 交付说明中显式登记。

## FR-11 平台生成物同步（伴随项，非平台执行层）〔来源 §4 FR-11〕

节点集变化后，两份**派生物**都会变：

- `../tools` `pipeline-templates/emit-registry.mjs` 生成的 architecture-design Core registry digest；
- `../multica` `server/internal/governance/gate_nodes_gen.go` 的 `NodeID` / `Seq` 映射（生成文件，`--check` 守护）——删除节点会改变该文件中 `Seq`（gate 与 review 节点的序位）等值。

本 FR 只要求**登记契约变化**，不要求在本 CR 内改 multica 生成物：

1. 交付说明中显式登记「生成物需重新生成」及其触发原因（节点集变化）；
2. 若**未**重新生成，必须显式声明「重新生成前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用」（该开关当前默认 false，见 §1.4 事实 17）；
3. **不允许静默**：本 CR 不得只改 tools 而让平台侧生成物在无人知晓的情况下失效；重生成由 owner 在部署窗口执行（不引入平台执行层、不新增 pipeline-平台耦合）。

# 4. 非功能需求

- **NFR-1 兼容性（最重要）**：`../tools` 全量既有测试与 CI（第 18 项事实所列 6 个步骤）保持绿；`crctl` 既有子命令的成功路径输出与退出码**不变**（唯一例外是 `archive` 返回**新增** `localTrunkSync`，既有字段与分类不变）。本 CR **不得签任何新例外**（CR-2026-065 已把全量测试变为真门禁）。
- **NFR-2 幂等与可重入**：`push-progress` 重放 `changed=false`；`review-record` 重放不消耗新 attempt；`archive` 重放不产生新 commit；评审发布失败按 `recovery` 重试**同一** checkpoint，不触发第二次评审。
- **NFR-3 行尾纪律（工作区纪律 #1）**：本 CR 触及哈希复算（FR-3 的 `subject-sha256` / composite）与跨行文本断言（FR-5 的测试改写），读写前必须 `\r\n → \n` 归一；解析失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」的降级。
- **NFR-4 零新增**：不新增 pipeline 节点、评审维度、账本字段、观测指标（SLO / 计数门禁）、crctl 子命令、错误码、Skill 参数、落盘文件；`emit-registry.mjs` 与 `gate_nodes_gen.go` 的**生成逻辑与 schema** 不改。
- **NFR-5 确定性（测试断言去硬编码，CR-2026-065 口径）**：`pipeline-structure.test.mjs` 的改写必须**从事实源推导**（读 JSON 实际节点集 / `_index.yml` 计数），不得钉死措辞与标点，也不得把新断言写成「等于当前行数」式恒真式。
- **NFR-6 语言纪律**：`../tools` 文档与 CR 产物用中文，代码注释按既有文件语言；`../multica` 代码注释一律英文（其 `CLAUDE.md` 硬规则）——本 CR 对 multica 的改动限于 Prompt 文档（中文），不写 Go/TS 代码。
- **NFR-7 无部署副作用**：本 CR 不触发平台 Agent DB 更新、不改 `aifirst/agent-import.mjs`、不启用 Runner；Prompt 部署与生成物重生成由 owner 执行。

# 5. 验收标准

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

# 6. 成功指标

- 每个阶段的**评审 PASS 后**远端存在完整批次的比例 = 100%（`repositories[].confirmed=true` 且 `metadataCommit` 非空）。
- **审批后**产生的 checkpoint 次数 = 0；「为单个 `push-progress`/checkpoint 单独开 task/委派」次数 = 0。
- AC-6 的延期验证点（载体、观察项、责任 agent、关闭触发条件）在本 CR 交付说明中登记 = 100%；未登记则「审批后 checkpoint 委派次数 = 0」无证据可交。
- 三份 pipeline JSON 中 `ref=push-progress` 的节点数 = 0；审批后 push-progress 节点数 = 0。
- 评审发布的对账通过率 = 100%（不等即 `CONTRACT_DRIFT`，无静默通过）。
- `archiveCr` 返回 `localTrunkSync` 的比例 = 100%；归档后各仓主 checkout 与 origin trunk 不一致且未被如实报告（静默 dirty/diverged）的次数 = 0。
- 本 CR 新增的观测指标 / 计数门禁 / pipeline 节点 / 评审维度 / 账本字段 / crctl 子命令数 = 0。
- 既有测试回归数 = 0；CI 新增例外数 = 0。

# 7. 范围排除

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
