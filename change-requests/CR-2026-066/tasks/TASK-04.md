---
id: CR-2026-066-TASK-04
type: TASK
cr-ref: CR-2026-066
plan-ref: "change-requests/CR-2026-066/plan.md"
sdd-ref: "change-requests/CR-2026-066/sdd.md"
target-version: 0.39
title: "口径改写、搭车硬规则与登记收口：四处同口径 + 四份 Prompt 副本 + FR-7 静态断言 + 交付登记块"
slug: checkpoint-wording-and-hitchhike-rules
status: pending
estimate: 24h
depends-on: [CR-2026-066-TASK-01, CR-2026-066-TASK-02, CR-2026-066-TASK-03]
created: 2026-09-14T15:25:00+08:00
---

# CR-2026-066-TASK-04 口径改写、搭车硬规则与登记收口（G4，FR-6 / FR-7 / FR-9 / FR-11）

## 1. 任务描述

**目标**：把「阶段终点完成条件 = 评审 PASS 的 checkpoint」在新事实下**四处同口径**（`push-progress` SKILL / `README.md` / `openwiki/pipelines/overview.md` / `dir-graph.yaml#pipeline_templates.contract`），把「审批后发布由搭车承担、禁止为 checkpoint 单开委派」写入 `merge` SKILL 与七份 Agent Prompt（tools 三份 ＋ multica 四份），补一条 FR-7 静态文本断言，并在交付说明登记 AC-6 / FR-11 / D-6 / 部署时序 / 断言 B 五块。

**背景**：TASK-01 删掉 7 个 checkpoint 节点、TASK-02 把发布移进评审 PASS。本卡负责**消除第二套说法**：文档/口径/委派合同面若残留「审批后阶段终点 checkpoint 为强制完成条件」或「为 checkpoint 单独委派」，实现期与部署期会按两套事实执行（FR-9 / FR-6 的直接动机）。

**输入条件**：TASK-01/02/03 已完成（三份 JSON 中 `ref=push-progress` 计数 0；四个 review SKILL 的发布合同与权限面就位；`archiveCr` 返回 `localTrunkSync` 已落地）；`sdd.md` rev 0.4 已审批（**不得改一字**）。

**范围边界**：不新增委派 lint 规则、不新增扫描面、不新增跨仓 CI 断言（D-5：multica 侧以一次性交付证据覆盖）；不改 `review-tech-design` Step 2.x、`quality-reviewer-agent#评审判断`、code pipeline 的 dev-start 提示、`review-dev-plan` 的 acceptance-verifiability 面（CR-P1/P2 面，零 diff）；不改 `cr-prompts-revised/agent-skill-matrix.yml`、`CUSTOM.md`、`aifirst/**` 或任何 Go/TS 代码（D-6）。

## 2. 涉及文件 / 模块

| 文件（相对仓根） | 仓 | 动作 | 说明 |
|---|---|---|---|
| `skills/sync/push-progress/SKILL.md` | tools | 改「调用时机」口径（L9） | §3.1 |
| `README.md` | tools | 改第 6 节 checkpoint 行（L65） | §3.1 |
| `openwiki/pipelines/overview.md` | tools | 三段流水线描述（L114/116/118）＋ `/coding` mermaid（删 `D8`/`D12`）＋ replayNodes 例（L73）＋ contract 第 9 条（L172） | §3.1 |
| `dir-graph.yaml` | tools | 改 `pipeline_templates.contract` 第 5 条 | §3.1（`state_machine` 段零 diff） |
| `skills/writeback/merge-feature-branch/SKILL.md` | tools | publication lag 行补「同 run 内搭车、不得转成新委派」 | §3.2 |
| `agents/quality-reviewer-agent.md` | tools | 新增「评审 PASS 后发布」职责 + 搭车硬规则（**在 TASK-02 的权限事实源节之外**） | §3.2/§3.3 |
| `agents/dev-agent.md` | tools | 搭车硬规则 + 「评审 PASS 即发布」口径 | §3.2/§3.3 |
| `agents/delivery-agent.md` | tools | 搭车硬规则 + recovery 例外双向边界 + 归档汇报面含 `localTrunkSync` | §3.2/§3.3 |
| `cr-prompts-revised/{quality-reviewer-agent,dev-agent,delivery-agent,cr-coordinator-agent}.md` | multica | 四份部署副本同步同一硬规则（coordinator 含显式禁止） | §3.3 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | tools | **追加** FR-7 静态文本断言（在 TASK-01 改好的 replayNodes 快照之外） | §3.4 |

## 3. 实现要点

### 3.1 FR-9 四处同口径（＋两处连带）

**目标口径（四处同一句意，逐条可核）**：

> **阶段终点完成条件 = 评审 PASS 的 checkpoint**（由评审者执行，每阶段一次）；审批后不再有 checkpoint 节点，未发布的审批提交由下一阶段评审 checkpoint 或 `merge` 的 publication preflight 搭车承担；发布失败保持当前状态、重跑同一 checkpoint，**不重新评审 / 不重新审批**。

| 文件 | 现文（逐字） | 目标 |
|---|---|---|
| `push-progress/SKILL.md` L9 | 「PRD 草稿与 TASK checkpoint 仍为可选节点；需求/架构/代码审批后的阶段终点 checkpoint 为强制完成条件」 | 上述口径；**保留** `crctl checkpoint` 的通用（随时可用）语义与既有参数面（`cr_id` / `message`） |
| `README.md` L65 | 「…需求/架构/代码三个阶段审批后的阶段终点 checkpoint 是 Pipeline 完成条件，不可跳过，失败保持已审批状态、重跑同一 checkpoint 不重新审批（CR-2026-044）」 | 同口径（一句话内）；`checkpoint` 行的「随时可用」语义保留 |
| `openwiki/pipelines/overview.md` L114/116/118 | 「then a **mandatory approval checkpoint**」/「a **mandatory checkpoint**」/「unified checkpoint → code review」 | 改为「then the review PASS publishes the stage batch (mandatory)」口径；`/coding` 段删除「统一 checkpoint」前置 |
| `openwiki/pipelines/overview.md` L120-140（mermaid） | `D8["checkpoint"]`、`D12["checkpoint (mandatory)"]` | **删除 `D8`/`D12` 两个节点**；`D9`（review-code）PASS 分支直接接 `D10`（human_approval）；不得留下悬空箭头 |
| `openwiki/pipelines/overview.md` L73 | replayNodes 例「code fix → test report → checkpoint → re-review」 | 改为「code fix → test report → baseline re-verify → re-review」 |
| `openwiki/pipelines/overview.md` L172（contract 第 9 条） | 「Requirement/architecture/code approval-stage terminal checkpoints are mandatory (CR-2026-044)…」 | 改为「stage terminal completion = the review-PASS checkpoint（published by the reviewer once per stage）；no post-approval checkpoint nodes」 |
| `dir-graph.yaml` L178（`pipeline_templates.contract` 第 5 条） | 「按顺序列出修复、证据、checkpoint 与当前评审节点」 | 改为「按顺序列出修复、证据、**基线重核**与当前评审节点」（S-4）；第 1 条（同步 `_index.yml` 计数）与 reviewLoop 重放清单约束**保持不变**；`change-request-track.state_machine` 段**零 diff** |

### 3.2 FR-6 搭车语义（同 run 内兜底，禁止新委派）

- `skills/writeback/merge-feature-branch/SKILL.md` 的 publication lag 行（L53）：**分类表结构不动**，补一句——写回 run 收到 `MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` 时，按 `error.recovery`（结构化 argv，`shell:false`）**就地执行一次**，然后**在同一 run 内重跑 merge**；不得转成新委派/新 task。`recovery` 字段名与语义不变。
- `agents/delivery-agent.md` 增量必须写明**双向边界**：① `recovery` argv 属于**被授权的同 run 重跑**，不受「不裸调 crctl 原语」约束；② 该例外**不**赋予独立发起 checkpoint 的权力。
- 归档终态汇报面（FR-10.8）：`agents/delivery-agent.md` 与 `../multica/cr-prompts-revised/delivery-agent.md` 的汇报项含 `localTrunkSync`（行摘要 + 未同步仓的补救说明）——`cmd-06` 对 multica 副本机械核对该 token。

### 3.3 FR-7 搭车硬规则（七份 Prompt 同句）

**硬规则文本（tools 三份 ＋ multica 四份同句）**：

> 跨人工 gate 的第一份委派必须显式携带上一阶段尚未闭合的发布动作（在同一 run 内执行、只回报结果）；**禁止为单个 `push-progress` / checkpoint 节点单独开委派**。

| 文件 | 增量 |
|---|---|
| `tools/agents/quality-reviewer-agent.md` | 新增「评审 PASS 后发布」职责（§3.1 的发布动作由本 Agent 执行）+ 硬规则；**不改** `## 权限事实源` 节（TASK-02 的落点） |
| `tools/agents/dev-agent.md` | 硬规则 + 改写评审前置口径（tools 侧现文为「委派路由合同（评审）」；`quality-reviewer-agent` 的发布职责句只落 reviewer Prompt） |
| `tools/agents/delivery-agent.md` | 硬规则 + §3.2 的双向边界 + 归档汇报面 |
| `multica/cr-prompts-revised/quality-reviewer-agent.md` | 硬规则（在 TASK-02 的权限块与 L54 改写之外追加，**不得回退 TASK-02 的改动**） |
| `multica/cr-prompts-revised/dev-agent.md` | 硬规则 + **原位改写 L23**「代码评审：先有代码、测试报告和统一 checkpoint，再由独立 reviewer 调用 `review-code`」与 **L41**「评审 blocker 未清空、测试报告未 pass 或 checkpoint 未完成时，不进入后续人工审批」→「评审 PASS 即发布」口径 |
| `multica/cr-prompts-revised/delivery-agent.md` | 硬规则 + §3.2 双向边界 + 归档汇报面含 `localTrunkSync` |
| `multica/cr-prompts-revised/cr-coordinator-agent.md` | 硬规则 + 「不得为 checkpoint 单开委派」的**显式禁止**（不改其 crctl 只读边界） |

- 语言纪律：tools 文档用中文；multica 侧改动限于 Prompt 文档（中文），**不写 Go/TS**（NFR-6）。
- 文本必须通过 `lint-prompts --mode enforce`：不裸写 `git` 写命令、不手写账本、同段不出现 3+ 具名状态、不写「下一步」映射、不出现退役字段名（`recoverCommand`/`recover_command`）。
- **不得**留下「已部署/已生效」类声称（`cmd-06` 反向断言）。

### 3.4 `contract-scan.test.mjs` 的 FR-7 静态文本断言（在 TASK-01 的快照之外）

```text
tools 三份 Prompt（agents/dev-agent.md / agents/quality-reviewer-agent.md / agents/delivery-agent.md）
均含硬规则 token：push-progress ∧ 单独开委派（或 同 run）；token 级，不断言整句；
三份文件必须被成功读出且非空（防空集合静默通过）。
```

- 断言风格与既有 `contract-scan` 同款（文本 token 检索，非逐行结构快照）；`RETIRED_RECOVERY` 整树扫描段**不动**。
- 不新增扫描面、不新增 lint 规则。

### 3.5 交付登记块（AC-6 / FR-11 / D-6 / 部署时序 / 断言 B，逐字转录 `plan.md` §10）

- 五块内容**逐字**从 `change-requests/CR-2026-066/plan.md` §10 转录到交付评论与 `test-report.md` 的分析段（`plan.md` 的 §10 是 canonical 落点，`cmd-07` 按它机械核对）。
- 不得改写为「平台已生效」口径；FR-11 登记走**未重生成 ⇒ `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用**分支。

## 4. 验收条件（可执行）

1. **`cmd-05`**（`repo=tools`）：四处口径正/负 token 全部通过（`push-progress` SKILL 与 README 含「评审 PASS」且旧句零命中；openwiki 含 `review PASS` 且 `mandatory approval checkpoint`/`mandatory checkpoint`/`checkpoints are mandatory`/`checkpoint (mandatory)`/`D8[`/`D12[`/`checkpoint →` 零命中；dir-graph contract 第 5 条含「基线重核」且旧词法零命中）→ **exit 0**（变更前实测 exit 1 / 42 failures）。
2. **`cmd-02`**：`pipeline-structure.test.mjs` + `contract-scan.test.mjs` → **exit 0**（含 FR-7 静态文本断言）；`cmd-06`（`repo=multica`）→ **exit 0**（四副本硬规则、coordinator 禁止、dev-agent 两句旧前提零命中、delivery 含 `recovery`/`同 run`/`localTrunkSync`、diff 面恰 4 文件）。
3. **`cmd-07`**（`repo=ai-first-platform-docs`）：交付说明必填块 token 齐备（AC-6 六字段 / `AIFIRST_ARCHITECTURE_RUNNER` + 「未重生成」/ `D-6` + `cr-prompts-revised/agent-skill-matrix.yml` / 部署窗口 / 断言 B 的 `受限 crctl 权限` + `workspace inspect`）且负向判据零命中 → **exit 0**。
4. **`cmd-01`** 全量套件 `verdict=pass` / `failures=0`（口径改写文本不得触发 lint-prompts 规则面）；`cmd-05` 的 CI 静态五步 `exit 0`。
5. 负控自检（非证据）：临时删掉某份 Prompt 的硬规则句 → `cmd-02` 的 FR-7 断言或 `cmd-06` **必须红** → 还原 → `crctl git status --short` 干净。
6. `zero_diff` 自查：`dir-graph.yaml` 的 `state_machine` 段、CR-P1/P2 面文件零 diff（`cmd-05` 的 hunk 级 token 检查）。

## 5. 完成标志

- 11 个文件就位并随 CR 提交（`[cr]` 前缀消息）；`cmd-05`/`cmd-06`/`cmd-07`/`cmd-02` exit 0；`cmd-01` 全量套件绿（无例外）。
- **四处同口径对照表**（现文 → 目标文 → `grep` 证据）与**七份 Prompt 硬规则落点表**（文件 → 行 → token）写入本任务完成记录。
- 交付说明必填块五块随交付评论发布，并在完成记录中登记发布位置（Issue 评论 id / `test-report.md` 分析段）。
- **任务账本登记**：`crctl task done CR-2026-066 --task CR-2026-066-TASK-04`（即时标 `done` 带 `done-at`）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- TASK-02 的产出：四个 review SKILL 的 PASS 发布合同（§3.2 的七步序列、`message` 四取值、四消费字段）与 `quality-reviewer-agent` 的权限终态 —— 本卡的口径改写必须与之**同口径**，不得自造第二套说法；`multica/cr-prompts-revised/quality-reviewer-agent.md` 的权限块由 TASK-02 落盘，本卡只追加硬规则。
- TASK-01 的产出：`ref=push-progress` 节点数 0 —— 本卡口径改写的**事实前提**（若仍有节点，口径句即失真）。
- TASK-03 的产出：`localTrunkSync` 字段名与 4 状态 × 6 reason 分类 —— 本卡的 delivery 汇报面句必须引用同名同分类。
- `recovery` 结构化合同字段名 `executable`/`args`/`cwd`/`requiresTTY`/`promptFor`（**零 diff**，只消费）。
- `merge-feature-branch/SKILL.md` L53 的既有 publication lag 分类行（结构不动，只补语义）。

**产出（下游节点消费方不得缩略）**

- 四处同口径的**唯一说法**（`push-progress` SKILL / README / openwiki / dir-graph contract）——`review-code` 与交付说明按它核对「无第二套事实」。
- 七份 Prompt 的**硬规则同句** —— `cmd-02`（tools 三份）与 `cmd-06`（multica 四份）的判据面。
- `plan.md` §10 的交付说明必填块（AC-6 / FR-11 / D-6 / 部署时序 / 断言 B）——`test-report.md` 与交付评论逐字转录的来源。
