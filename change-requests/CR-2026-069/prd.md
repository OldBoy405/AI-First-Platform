---
id: CR-2026-069-prd
type: PRD
cr-ref: CR-2026-069
title: CR 流程降本提效首期：FR-8 成本基线 + FR-1 OutputGuard + FR-2 crctl 输出瘦身
target-version: 0.42
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-17T14:41:46+08:00
updated: 2026-09-17T14:41:46+08:00
---

# 1. 概述

## 1.1 问题陈述

需求来源是 Issue **AIFI-32** 附件《CR需求来源_CR流程降本提效_收敛版.md》（26,406 B，附件 id `01a0ae08-91e4-76af-a810-798d812b6c2f`）。该文件是原始来源《CR需求来源_CR流程降本提效.md》（22,327 B，2026-09-16）经 grilling 决策（Q1～Q36）收敛后的版本；两份文件已按来源 §15 的「注册时保留原始附件与本收敛版，原始附件作为需求演进证据」一并登记在本 CR 的 `change-requests/CR-2026-069/sources/` 下（见 §1.4 事实 15）。**本 PRD 的一切范围判定以收敛版为唯一权威**，原始版只作演进证据，其 §8 九项 FR 不构成九项交付合同（来源 Q1、Q35）。

问题本身（来源 §4 基线 + 原始版 §1、§8）：CR 流程的单位成本由工具结果 token 主导，而工具结果在进入模型上下文前**完全不受治理**。原始版实测口径（2026-08-18～2026-09-16，672 个会话文件 / 643 个带工具结果的会话）：工具结果合计约 **49.7M tokens**（o200k 编码），其中搜索类约 10.97M、目录列举约 2.32M、文件打印约 5.98M；带 CR-ID 的会话覆盖 36 个 CR，约 **17 会话/CR**（中位数 8、P75 12、P90 56、最大 124）；crctl 自身命令输出约 1.24M，占执行类输出约 53%（来源 §4，本 PRD 原样采纳为需求动因，不重复其统计过程，见 §1.4 事实 12）。

来源给出的根因结论（原始版 §4 R-1/R-2/R-3/R-4 + 收敛版 §6.1）有三条直接决定本 CR 的形状：

1. **治理点位置错**：只有把护栏放在「工具结果进入**下一轮模型上下文**之前」才降低成本；只改 Multica daemon 的 transcript/preview 已经太晚——`server/internal/daemon/tool_output_preview.go` 源码注释自己写明 `It does not limit the full output consumed by the agent`（§1.4 事实 8）。因此该文件本 CR **零 diff**（AC-12）。
2. **靠 Prompt 约束不稳定**：来源 R-2 判定「靠提示词约束行为跨模型不可靠」，§11 明确「不把检索纪律仅写入 Skill/Prompt 作为主要手段」。因此本 CR 的实现面是**代码层无状态规则求值**，不是 Prompt 治理（FR-1）。
3. **收益必须可证伪**：原始版 R-4 判定成本口径未与真实账单对齐。因此**先测基线、后改代码、再复测**被钉为第一期第一位（FR-8），并把它设成后续扩项的硬门槛（§5.6 / AC-17）。

同时，来源 §3 钉死了「已解决的基础设施本 CR 直接复用」：crctl 的状态机 / 门禁 / CAS / `durable-tx.mjs` / `workspace-transactions.mjs` / `gates.json` / `pipeline-templates` / writeback 版本化脚本 / CI 合同校验全部已存在（§1.4 事实 1–5）。因此本 CR 的全部杠杆是**在呈现层与工具结果层做减法**，零新增治理结构。

## 1.2 解决方案摘要

按来源 §1「首期仅实施三项」逐条落地，编号沿用来源 FR 编号（FR-3～FR-7、FR-9 编号保留、不占用，见 §7）：

1. **FR-8 离线成本与质量度量**（来源 §5）：新增一个只读度量脚本（来源建议落位 `AI-First-tools/skills/shared/metrics/scripts/cr-cost.mjs`，该目录当前不存在，§1.4 事实 6），在本 CR 内只执行两次——改造前基线 + 672 会话 policy 离线回放、部署后 14 天窗口复测。它不推进 CR、不参与门禁、不写状态与账本；机器结果只有一份 JSON，人读摘要由同一脚本即时渲染；报告作为 CI artifact 或 Issue 附件保存。
2. **FR-1 通用 OutputGuard**（来源 §6）：无状态 Core（规则求值 + 确定性裁剪 + 提示 + 覆盖度结果）+ 五个 Runtime 薄 Adapter（只做 Provider hook 输入/输出映射）。seam 在 `Runtime 原生工具调用 → Adapter → Core → 裁剪后的模型可见结果`。首期只治理实测高消耗命令族（`grep`/`rg`/`find`/`Get-ChildItem`/`cat`/`Get-Content`），不写 shell parser；`policy.json` 是阈值唯一事实源，阈值由 FR-8 基线产出而不是拍脑袋。裁剪结果一律标 `complete=false`、保留 `toolName`/`toolCallId`/`isError`/`exitCode` 与结果结构、被丢弃正文不落盘；`complete=false` 不是充分门禁证据；逃生阀是一次性首行注释且不绕过任何安全控制；缺 Adapter 或 policy 损坏时显式 fail-open 并标 `coverage=unavailable`。Core/Policy/五 Adapter 随同一 Tools Release 原子发布，按 Pi → Claude → CodeBuddy → Qoder → Codex(partial) 顺序启用。
3. **FR-2 crctl 输出瘦身**（来源 §7）：只给「基线识别出的、覆盖 ≥80% crctl 输出 token 的最小命令集合」增加独立 summary projector；默认输出 compact summary JSON，完整字段经统一 `--detail` 获取。当前 `crctl.mjs` 的成功输出由统一 `ok()` 全量缩进打印（§1.4 事实 7），本 CR 改的是**呈现层**，禁止在全局 `ok()` 粗暴删所有命令字段；退出码、错误码、字段语义与状态、门禁、审批、CAS、事务、Git 行为逐一不变（AC-11）。

三项合起来构成一个可证伪闭环：**FR-8 定义「省了多少、有没有变差」的唯一口径 → FR-1 与 FR-2 是唯一被允许的两个降本手段 → FR-8 的复测结果是 FR-3～FR-7、FR-9 能否重新立项的唯一前置**。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

> CR 流程降本提效首期：在不改变 CR 阶段、门禁、审批、Git、账本与事务语义的前提下，只实施三项。FR-8 离线建立成本基线与历史回放（读取既有 session 工具结果与 Provider usage，对 672 个历史 Pi session 离线回放 OutputGuard policy，部署后固定 14 天窗口复测；只在改造前与部署后各执行一次，不进 Pipeline 节点、不参与门禁、不写状态与账本，目标桶 tokens/CR 需下降至少 20% 且三项质量护栏全部不恶化才允许重新立项评估候选 FR）。FR-1 无状态 OutputGuard Core 加五个 Runtime 薄 Adapter（在工具结果进入下一轮模型上下文之前治理无界检索、递归列举与全文读取；policy/capabilities/conformance 为唯一事实源；裁剪结果必须标记 complete=false 并保留 toolName、toolCallId、isError、exitCode 与结果结构，被丢弃正文不落盘、不进 transcript；complete=false 结果不得作为充分门禁证据；一次性首行注释逃生阀只影响当前调用、原因必填、不绕过安全控制；Adapter 或 policy 缺失损坏时显式 fail-open 并标 coverage=unavailable；按 Pi 到 Claude 到 CodeBuddy 到 Qoder 到 Codex(partial) 顺序启用；Core、Policy、五个 Adapter 随同一 Tools Release 原子发布升级）。FR-2 只对基线识别出的、覆盖至少 80% crctl 输出 token 的最小命令集增加 summary projector（默认输出 compact summary，完整字段经 --detail 获取，不新增 --output json、--verbose、--pretty 平行开关，不在全局 ok() 粗暴删字段；退出码、错误码、字段语义与状态、门禁、审批、CAS、事务、Git 行为逐一不变）。范围为一个 CR、十个 TASK，复用既有跨仓 checkpoint、事务与受控 Git，每个 Adapter 独立提交可单独回滚；明确零改动 AI-First-multica 的 tool_output_preview.go，不新建事务协调器、WAL、CAS 层或 Git 提交框架，不拆分或重构 workspace-transactions.mjs，不复制 passCondition、状态映射或 reviewLoop 算法，不实现完整 Bash/PowerShell parser，不调用 LLM 做输出摘要，不新增状态、门禁、审批或 CR 生命周期节点，不新增账本、数据库、仪表盘、sidecar 日志或远程动态开关。FR-3 至 FR-7 与 FR-9 保留为候选 Backlog，不属于本 CR 验收范围，不得借本 CR 扩大范围。

### 1.3.1 scope_in 边界（原文前缀，评审核对用）

> 在不改变 CR 阶段、门禁、审批、Git、账本与事务语义的前提下，首期仅实施：1. **FR-8**：离线建立成本基线、历史回放与部署后复测；2. **FR-1**：通过无状态 OutputGuard Core 与 Runtime Adapter，在工具结果进入模型上下文前治理无界检索、全文读取和超量输出；3. **FR-2**：仅对贡献主要输出量的 crctl 命令做 compact summary，完整结果通过 `--detail` 获取。FR-3～FR-7、FR-9 保留为候选 Backlog，不属于本 CR 验收范围。

（来源 §1 逐字。Issue 标题写作「FR-0/1/2」，与来源 §1 不符，**以来源 §1 的 FR-8 + FR-1 + FR-2 为准**——本 PRD 不存在「FR-0」，Issue 标题只是人工录入笔误，见 §1.5 第 1 条。）

三项的**共同硬边界**（来源 §2 依赖方向 + §3.1「本 CR 禁止」清单 + Q2）：

- 依赖方向固定为 `Agent → Pipeline → Skill → crctl`、`Runtime Adapter → OutputGuard Core → policy.json`、`离线度量脚本 → 既有 session/provider usage（只读）`；不得出现反向或第二通道。
- 对本次**新增/修改**的面是硬约束；存量 Prompt 重复不扩散、不顺带全仓重构（Q2、§11）。
- 新增产物一律是**非权威投影**（Q3）：度量 JSON、trailer、覆盖度声明都不进 CR 权威账本、不进门禁 passCondition 输入。

### 1.3.2 目标仓库与版本

| 仓 | 本 CR 的落地面 | 明确不碰的面 |
|---|---|---|
| `../tools`（`ai-first.tools` 方法论包） | OutputGuard 新增目录（来源 §6.2 建议位 `output-guard/`：`core.mjs` + `policy.json` + `capabilities.json` + `conformance.json` + 五个 Adapter）、FR-8 度量脚本（建议位 `skills/shared/metrics/scripts/cr-cost.mjs`）、FR-2 的 crctl summary projector 与 `--detail`、README 导航段、合同测试 | `skills/shared/crctl/scripts/lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`（不新建第二套事务、不拆分重构）、`skills/shared/crctl/gates.json`、`dir-graph.yaml#state_machine`、`pipeline-templates/*.pipeline.json`（节点数保持 5/4/12）、`agent-skill-matrix.yml`、既有阶段/门禁/审批/事务语义 |
| `../multica` | 仅 Runtime 启动接线 / Adapter 挂载与部署（来源 §8 TASK-09：只部署挂载，不复制 policy、不改 preview） | `server/internal/daemon/tool_output_preview.go`（**零 diff**，AC-12）、`server/internal/governance/runner.go` 的固定 `architecture-design` 切片、Provider 事件归一化语义 |
| knowledge-base（本仓） | 本 PRD 与后续评审/审批产物；`change-requests/CR-2026-069/sources/` 两份需求来源证据 | `specs/`、`delivery/`、`docs/`（只读）、受控账本（一律经 crctl） |

- `target-version` 继承 `cr.md` 的 **`0.42`**（注册阶段人工确定「版本在现有版本上延续」：现行最高 `specs/_index.yml#current = 0.41` = CR-2026-068 的 target-version，§1.4 事实 13）；本文件不改写该值，唯一更正入口是 `crctl version-set`。
- `target-spec-id` = **`ai-first-platform`**，由注册事务双写入 `cr.md` 与 `_backlog.yml`（全等），本文件不得改写。
- 实施拆分为**一个 CR、十个 TASK**（来源 §8 / Q23）：TASK-01 基线 → TASK-02 Core/policy/capabilities/conformance → TASK-03～07 五 Adapter（可并行准备，启用顺序受 §6.11 约束）→ TASK-08 FR-2 → TASK-09 Multica 接线 → TASK-10 部署后复测。该拆分是**范围合同**（十项全部交付、不得并项或漏项），具体的文件级步骤与依赖矩阵归开发期 plan/TASK，不在需求期重排。

### 1.3.3 契约说明（确定性四查适用面）

本 CR **新增两类用户可调用契约**，四查适用面如下（可观察行为，实现算法归 SDD）：

- **适用：OutputGuard 的调用前判定 + 调用后裁剪决策**（FR-1）——它是每次工具调用都会命中的新契约面，四查逐条落在 FR-1 第 6～9 项（幂等求值、固定判定顺序与唯一终态 action、错误码闭包、零写入与零残留副作用）。
- **适用：`crctl <命令> --detail`**（FR-2）——它是新增 flag 与默认输出形状变更，四查落在 FR-2 第 3～6 项（幂等、无权限分支、错误面不变、纯呈现零副作用）。
- **不适用：FR-8**——它是只读离线脚本，不定义任何用户可调用的请求/响应契约（无 HTTP API、无 crctl 子命令、无状态写入），验收以「可复现筛选规则 + 固定 JSON 字段集 + 口径合同」形式给出（AC-17/AC-18）。
- **不适用：本 CR 不改任何既有 HTTP endpoint / request / response、不改 crctl 既有子命令集与错误码语义**（AC-11、AC-1）。`skills/shared/crctl/scripts/crctl.mjs` 被改的只有成功输出投影层，不改状态转换、门禁、审批、CAS、事务与 Git 行为。

## 1.4 当前事实（落笔前核实）

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
| 15 | 来源证据文件已入 CR 目录：`change-requests/CR-2026-069/sources/CR需求来源_CR流程降本提效_收敛版.md`（26,406 B，与 Issue 附件 `cmp` **逐字节一致**，两者均为 LF）与 `…/CR需求来源_CR流程降本提效.md`（22,327 B，与原始 task workdir 同尺寸副本一致）。注意：本 KB 仓 `core.autocrlf=true` 且无 `.gitattributes`，这两份文件**入库后检出为 CRLF**，任何「与附件逐字节一致」的断言在检出面上不成立，必须写成「EOL 归一后一致」（§1.4 事实 16） | `cmp` 实测、`git config --get core.autocrlf` = true、`ls .gitattributes` → 不存在 |
| 16 | 行尾纪律先例：已归档 CR-2026-068 的 requirement 评审 `suggestions` 第 1 条正是「KB 内来源文档与 Issue 附件逐字节一致（cmp 通过）」在字节层不成立（检出 CRLF/34036B vs 附件 LF/33478B），并建议改写为「EOL 归一后一致」。本 PRD 自初稿即按该口径表述，不再重复同一断言错误 | `change-requests/CR-2026-068/review-annotations/requirement.yml#suggestions` |

## 1.5 对来源文档的事实更正与需人工确认的口径

1. **Issue 标题与来源 §1 不一致，取来源 §1**：标题「CR 流程降本提效：FR-0/1/2」中的 FR-0 不存在；收敛版 §1 与 Q4/Q35 钉定首期 = **FR-8 + FR-1 + FR-2**。注册输入由协调者按来源 §1 复核后下发（`target-version 0.42`、`target-spec-id ai-first-platform`、三角色 owner = Ray），本 PRD 与 cr.md summary 一致，不改写标题含义。
2. **FR 编号保留空洞是刻意的**：本 PRD 的功能需求只有 FR-1、FR-2、FR-8 三条；FR-3～FR-7、FR-9 是来源 §12 的候选 Backlog **编号占位**，不是遗漏。评审时若发现「缺 6 条 FR」，判据应为「是否把候选 Backlog 借本 CR 带入」而不是「编号是否连续」。
3. **样本文件数 672 vs 复核 673**：来源记 672 个会话文件；本次按 `*.jsonl` + 来源区间复核得 673（§1.4 事实 10）。差 1 属窗口边界与文件类型口径，不影响任何结论。**本 PRD 不把 672 写成硬事实**：FR-8 的验收是「筛选规则以命令形式可复现 + 重跑得到同一集合」，回放样本数由脚本自身输出，不得把常量 672 写进代码或门禁（AC-17）。
4. **§6.3 的 Runtime 能力矩阵不由本 PRD 复述为事实**：Claude / CodeBuddy / Qoder 的 `PreToolUse` + `PostToolUse.updatedToolOutput`、Codex 的 `Managed PreToolUse` + `block/feedback` 路径与 hosted `WebSearch` 绕过，来自来源引用的外部文档（§6.3 参考依据）。需求期只钉合同：**能力分级必须由 `capabilities.json` 声明、由 `conformance.json` 逐 Adapter 验证、uncovered 路径必须显式标记而不宣称生效**（AC-4、AC-8）。若实施期发现某 Runtime 实际不具备 full 能力，唯一合法动作是把 `capabilities.json` 降为 partial/unavailable（不得伪装 full），并据此调整 §6.11 启用顺序。
5. **需人工一并确认：逃生阀标记不合法时的行为（来源未写明，本 PRD 钉定）**——来源 §6.6 只规定 `reason` 必填、单行、限制长度，未规定缺失/畸形时的处置。本 PRD 钉为：**该标记视为不存在，调用按普通路径处理（不拒绝工具调用本身），不新增 action 取值、不新增提示文本；若随后被裁剪，仍按 §6.7 输出 `action=truncate` trailer**，模型因此可见「本次未获得完整结果」。不引入第二套错误码，不引入授权文件（保持 Q18 无状态）。
6. **需人工一并确认：`--detail` 与 summary 的字段等价定义**——来源 §7.3 写「`--detail` 的业务字段与旧完整输出等价」。本 PRD 钉为：**`--detail` 的输出必须等于改造前该命令的完整 JSON（同字段集、同语义、同嵌套形状），差异只允许出现在「默认输出被投影为 compact summary」这一侧**；合同测试按「逐字段集合比对」而非「字节比对」验收，以免行尾与缩进噪声产生假失败（AC-10、AC-21）。
7. **需人工一并确认：新增合同测试的棘轮登记同步义务**——FR-2 要求「既有测试全绿，并增加 summary/detail 合同测试」（来源 §7.3）。本 KB 的 `gate-registry.json#manifest.cases` 是**下限棘轮**：`实际用例数 < 登记基线` 即 `SUITE_MANIFEST_CASE_DROP` 红，故**新增用例不登记也不会立即变红，但会永久留在回归保护之外**（§1.4 事实 5）。本 PRD 因此要求新增用例在同一 CR 内把该文件的登记值同步为实际值（先例：CR-2026-067 同步 `pipeline-structure.test.mjs` 的 36），且**不得签任何新例外**，`exceptions` 保持空数组。落地判据 AC-21。
8. **OutputGuard Adapter 与 crctl 既有 IDE 适配器的关系（本 PRD 钉定，避免第二份事实源）**：`skills/shared/crctl/adapters/` 现有模板治理的是「裸 git / 受控路径写入 / SessionStart 注入」，与 FR-1 的「工具结果裁剪」是**两套不同职责**，不得合并成一个配置文件，也不得把 `policy.json` 复制进 crctl adapter 目录。目录归属、hook 是否与既有 `settings.template.json` 共用安装入口归 SDD；硬边界是**policy 单一事实源、随同一 Tools Release 原子发布**（AC-3、AC-20）。CodeBuddy 当前无任何既有适配器，属纯新增（§1.4 事实 6）。
9. **来源 §6.10 的「Tools Plugin 携带 Skills 与 hooks」在 tools 仓当前无载体**：仓内不存在 `.claude-plugin/plugin.json` 或等价 plugin 清单；现有 Claude 安装方式是「把 `settings.template.json` 的 hooks 段合并进目标 workspace 的 `.claude/settings.json`」并**在安装时物化为 tools 包绝对路径**（模板里是占位符，安装动作负责替换）。本 PRD 因此只钉合同（显式安装一次、三级 scope、启动只检查不修复、不得复制 policy），把「是否引入 plugin 打包形态」交给 SDD 依据该先例决定；不得为「Plugin」新建安装框架或远程开关（AC-20、§7）。

## 1.6 修订记录

- **初稿（2026-09-17）**：按来源收敛版 §1～§15 与注册摘要（`cr.md` summary）起草；§1.4 的 16 项事实在三仓基线 SHA / 当前盘面上逐条实读核实。FR 编号沿用来源编号（FR-1=来源 §6、FR-2=来源 §7、FR-8=来源 §5）；AC-1～AC-16 与来源 §9.1 的十六条合并前硬验收**一一对应、不合并判据**；**AC-17～AC-21 为本 PRD 新增**，覆盖来源正文有要求但 §9.1 未列成验收的五个面（FR-8 输出/口径/执行次数合同、FR-1 发布与启用合同、FR-2 调用方同步与用例登记合同）。§1.5 记录三处需人工一并确认的钉定（第 5、6、7 条）、四处本 PRD 钉定（第 3、4、8、9 条）与一处范围更正（第 1、2 条）。

---

# 2. 用户故事

- **US-1 CR 流程的操作者（任意 Runtime 下的 Agent 使用者）**：作为让 Agent 反复检索与读文件的人，我希望无界搜索、递归列举和整文件打印在**结果进入模型上下文之前**就被收窄成「唯一文件列表 / 连续行窗口 + 下一次 offset」，这样我不再为同一份噪音付两轮 token，而且模型永远知道自己是拿到了完整结果还是切片。
- **US-2 需要全量证据的 Agent**：作为确实要看完整生成文件的执行者，我希望有一条一次性的、必须写明原因的逃生阀（首行 `# output-guard: full reason=…`），这样取证不会被护栏卡住，而逃生阀也不会变成绕过安全控制的永久后门。
- **US-3 crctl 的调用方（Skill / 脚本 / 评审者）**：作为调 `crctl status/next/validate/checkpoint` 的人，我希望默认看到的是 compact summary、需要完整字段时显式加 `--detail`，这样高频命令不再为缩进和全量投影付费，而退出码与错误码和我原来依赖的字段一个都不变。
- **US-4 Reviewer / gate 消费者（quality-reviewer-agent）**：作为做最终判断的人，我希望 `complete=false` 的切片结果**明确不可作为充分门禁证据**，系统要求我继续按 offset/limit 取证或走逃生阀，这样裁剪不会把「取证不足」伪装成「已核对」。
- **US-5 运行环境的安装者（Ray / 企业部署者）**：作为把 Tools 装进各 Runtime 的人，我希望缺失或损坏时系统**显式 fail-open 并告诉我 coverage=unavailable**，只报告、不静默安装或修复，这样我永远不会以为护栏在生效而实际没有。
- **US-6 成本决策者（Ray）**：作为决定要不要继续投入 FR-3～FR-7、FR-9 的人，我希望有一份和真实账单对齐、按归一化指标（tokens/CR、会话数/CR）表达的 before/after 对照，以及「目标桶下降 ≥20% 且三项质量护栏全部不恶化」的机械门槛，这样扩项与否不再靠感觉，也不会用 token 下降换返工增加。
- **US-7 本 CR 的评审者**：作为核对本 CR 的人，我希望逐条确认「CR 阶段 / 门禁 / 审批 / Git / 账本 / 事务六类语义零改动」与 `tool_output_preview.go` 零 diff 成立，确认没有第二套事务框架、没有复制 policy、没有把候选 Backlog 偷偷做进当前 TASK。

---

# 3. 功能需求

> 编号沿用来源 FR 编号；FR-3～FR-7、FR-9 是候选 Backlog 占位，本 CR 不定义（§7）。每条 FR 的行为后括注来源小节。

## FR-8 离线成本与质量度量〔来源 §5〕

**定位**：只回答三个问题——FR-1/FR-2 是否真的降低单位 CR 成本、是否以取证不足/缺陷后移/返工增加换取 token 下降、是否值得继续启动候选 FR（来源 §5.1）。它**不推进 CR、不参与门禁、不写状态、不写账本**（§5.1、Q11）。

1. **实现位置与执行次数**：新增只读度量脚本（建议 `AI-First-tools/skills/shared/metrics/scripts/cr-cost.mjs`）；本 CR 内**只执行两次**——改造前（历史日志生成 `baseline.json` + 对历史 session 离线回放 OutputGuard policy）与部署后（14 天窗口生成 `after-fr1-fr2.json` 与前后差异摘要）。不新增 Pipeline 节点、Skill 步骤、Agent 收尾动作、定时任务、数据库或仪表盘；部署后报告**不是代码合并门禁**（§5.2、Q11、Q25）。
2. **输入（全部只读复用）**：既有 session 工具调用与结果、既有 CR-ID / task / run / session 标识、Provider usage 的 `input` / `cachedInput`|`cacheRead` / `cacheWrite` / `output`、既有 Pipeline 与评审数据（门禁一次通过、reviewLoop、评审发现缺陷）、Runtime 启动能力记录与 OutputGuard trailer。不新增采集面（§5.3、Q17）。
3. **输出（单份机器事实）**：机器结果只保留一份 JSON，字段集固定为来源 §5.4：`window` / `sampleCRs` / `coverage{runtime→full|partial|unavailable}` / `providerUsage{input,cachedInput,cacheWrite,output}` / `toolResultTokens` / `k` / `metrics{tokensPerCR,sessionsPerCR,searchTokenRatio,fullReadRatio,bootstrapTokensPerSession}` / `guardrails{firstPassGateRate,reviewLoopsPerCR,reviewDefectsPerCR}`。人读摘要由**同一脚本即时渲染**，不维护第二份事实；报告作为 CI artifact 或 Multica 附件保存，**不进入权威账本**（§5.4、Q32）。
4. **k 与金额口径**：`k = Provider 实际计费金额 ÷ 同区间工具结果 token`；`预计节省金额 = k × 节省的工具结果 token`。用两个完整 CR（一个接近会话数中位数、一个高会话数样本）；必须保留原始 usage 维度与价格来源；**取不到实际计费金额时只报告 token 放大系数，不得宣称真实金额节省**；首期只对 Pi 出成本结论，其它 Runtime 只报覆盖度与裁剪量，**不外推 Pi 的 k**（§5.5、Q8、Q26）。
5. **观察窗口与扩项门槛**：部署后固定 14 天；只统计 `coverage=full` 且带 CR-ID 的完整 Pi CR；样本不足输出 `insufficient-sample`，**不延长当前 CR、不编造结论**；目标桶（搜索/列举/打印 + crctl）`tokens/CR` 至少下降 **20%**，且 X-5 三项质量护栏（门禁一次通过率、reviewLoop/CR、评审阶段发现缺陷数）**全部不恶化**；只有满足该条件才允许重新立项评估 FR-3～FR-9（§5.6、Q28、Q34）。
6. **可复现性**：样本筛选规则（目录、文件类型、时间窗、CR-ID 归属）必须作为脚本输出的一部分可复现，且重跑得到同一集合；比较只用归一化指标，不比较绝对总量（来源 §4 末 + §1.4 事实 12）。

## FR-1 通用 OutputGuard（无状态 Core + Runtime 薄 Adapter）〔来源 §6〕

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

## FR-2 crctl 输出瘦身（仅呈现层）〔来源 §7〕

1. **选择规则**：先由 FR-8 基线按命令聚合 crctl 输出 token，选出**覆盖 ≥80% crctl 输出 token 的最小命令集合**；只为该集合增加**独立的 summary projector**，默认输出 compact summary JSON，`--detail` 返回原完整字段。禁止在全局 `ok()` 中粗暴删除所有命令字段（§7.1、§7.2、Q30）。
2. **开关面收敛**：不新增无意义的 `--output json`、`--verbose`、`--pretty` 平行开关（现状该四个 flag 零存在，§1.4 事实 7）；既有机器调用方若依赖完整字段，**显式补 `--detail`**（§7.2 第 6/7 条）。
3. **幂等与无权限分支**：`--detail` 是纯呈现层开关——不参与任何状态判定、门禁、审批或 CAS 判定，不加权限分支，不改退出码；同一命令在相同仓库状态下重复调用，`--detail` 输出恒等。
4. **错误闭包**：所有错误路径（247 个 `fail(` 出口）保持既有错误码、错误体与非零退出，**不进入 summary 投影**；未知/新增错误码禁止借本 CR 引入。
5. **不变量（来源 §7.3）**：命令退出码不变；错误码、字段语义和失败信息不变；状态、门禁、审批、CAS、事务和 Git 行为不变；`--detail` 业务字段与旧完整输出等价（等价定义见 §1.5 第 6 条）；既有测试全绿并增加 summary/detail 合同测试。
6. **同 CR 义务**：新增 summary/detail 合同测试后，其所属测试文件的 `gate-registry.json#manifest.cases` 登记基线必须在同一 CR 内同步为实际用例数（棘轮只挡回退，不登记即等于新合同无回归保护），且不签任何新例外（§1.5 第 7 条、AC-21）。
7. **不做**：不优化 crctl 运行时小文件读取、不治理历史上从未读取的大文件、不建 crctl 字段/错误码事实页与 CI 新鲜度（那是候选 FR-9，§7）。

## 关于「FR-0」的不存在声明

来源与本 CR 均无 FR-0；Issue 标题中的「FR-0/1/2」按 §1.5 第 1 条更正为「FR-8 + FR-1 + FR-2」。评审若需范围核对，以 §1.3.1 原文前缀为准。

---

# 4. 非功能需求

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

# 5. 验收标准

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

# 6. 成功指标

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

# 7. 范围排除

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
