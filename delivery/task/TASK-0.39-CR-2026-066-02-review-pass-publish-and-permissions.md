---
spec-id: ai-first-platform
version: "0.39"
id: CR-2026-066-TASK-02
type: TASK
cr-ref: CR-2026-066
plan-ref: "change-requests/CR-2026-066/plan.md"
sdd-ref: "change-requests/CR-2026-066/sdd.md"
target-version: 0.39
title: "评审 PASS 发布、clean 前置与权限面：四个 review SKILL 同构改造 + 矩阵/派生表/两份 quality-reviewer Prompt 同步"
slug: review-pass-publish-and-permissions
status: pending
estimate: 24h
depends-on: [CR-2026-066-TASK-01]
created: 2026-09-14T15:25:00+08:00
---

# CR-2026-066-TASK-02 评审 PASS 发布、clean 前置与权限面（G2，FR-1 / FR-2 / FR-3 / FR-8）

## 1. 任务描述

**目标**：把「阶段终点发布」移进四个 review SKILL 的 **PASS 分支**（每阶段恰好一次），在四个 SKILL 的 **Step 1 起始**加只读 clean 前置，在发布后做「发布的 ≡ 评审的」对账，并把评审者的**权限面两侧**（SKILL 文本 ＋ actor 允许面四处载体）同批闭合。

**背景**：发布点原在人工审批 gate 之后的 pipeline 节点（TASK-01 已删除），跨 gate 必须重新唤醒 ⇒ 只能被单独委派（CR-2026-063 实测 3 次）。发布动作**不新增 Skill 参数、不新增落盘文件、不新增状态转换、不新增错误码**：只用既有 `push-progress` 与既有只读 `crctl workspace inspect`。

**输入条件**：TASK-01 已完成（三份 JSON 中 `ref=push-progress` 计数 = 0）；`sdd.md` rev 0.4 已审批（**不得改一字**）；`plan.md` §0.6/§6.1/§8.A 已冻结。

**范围边界**：不改四个 review SKILL 的**参数表 / payload 结构 / 评审维度 / `passCondition` / `reviewLoop` 语义**（`zero_diff`）；不改各阶段既有 `advance` 语义（`review-tech-design` / `review-dev-plan` PASS **不新增** `advance`）；不改 `crctl.mjs` / `rules.json` / `gates.json`；不改 `review-tech-design` 的 Step 2.x 区块（归 CR-P1）与 `review-dev-plan` 的 acceptance-verifiability 面（归 CR-P2）。

## 2. 涉及文件 / 模块

| 文件（相对仓根） | 仓 | 动作 | 说明 |
|---|---|---|---|
| `skills/requirement/review-requirement/SKILL.md` | tools | Step 1 前置 + PASS 发布 + 对账 + 调用时机句 | §3.1/§3.2/§3.3/§3.4 |
| `skills/develop/review-tech-design/SKILL.md` | tools | 同上（PASS **无** `advance`） | §3.1…§3.4 |
| `skills/develop/review-dev-plan/SKILL.md` | tools | 同上（PASS **无** `advance`） | §3.1…§3.4 |
| `skills/develop/review-code/SKILL.md` | tools | 同上（PASS 保留既有 `advance --to code-reviewing`） | §3.1…§3.4 |
| `agent-skill-matrix.yml` | tools | 改 `quality-reviewer-agent` 的 `can-call`/`forbidden` + 块注释（L192-194） | §3.5 |
| `AGENT-SKILL-MATRIX.md` | tools | `## 本 CR 权限变更` 节（L46）追加本 CR 行 | §3.5 |
| `agents/quality-reviewer-agent.md` | tools | 「权限事实源」节（L35-38）给出同一允许面声明 | §3.5 |
| `cr-prompts-revised/quality-reviewer-agent.md` | multica | `## 受限 crctl 权限` 块（L35-46）允许面新增只读 `workspace inspect` | §3.5 |
| `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | tools | **追加** AC-3/AC-4 断言块 | §3.6 |

## 3. 实现要点

### 3.1 Step 1 起始：只读 clean 前置（FR-2，四 SKILL 同构）

```text
pre_check(cr):
  r = crctl workspace inspect {cr}                 # 只读、零写入
  if ∃ resources: classification != 'healthy':     # healthy ⇒ dirty=false（更强前置：worktree 已注册 ∧ HEAD 在 CR 分支）
      报告逐仓 classification/dirty 事实与该仓未提交文件清单
      给出「存在未提交内容，请作者先提交」
      → 不写临时 payload、不 review-record、不 advance、不改 status、不发布
      → 评审者不得对作者工作区做 git add / commit / stash / 清理
```

- **位置钉定**：四个 SKILL 的 **Step 1 起始处**；`review-requirement` 的 Step 1.5 pre-review 门禁顺位不变（仍在其后）。
- **两侧必须同时存在**（B-1）：SKILL 侧的前置 ∧ actor 侧允许面（§3.5）；缺任一侧即 AC-4 红。
- 判据取 `classification`（**不得**写成 `dirty=false` 的等价式——那会漏掉 wrong-branch / path-unregistered 两类不干净工作区）。
- **不新增** crctl 子命令、不新增错误码。

### 3.2 PASS 分支：发布序列（FR-1，四 SKILL 同构、stage 分派不同）

触发顺序**固定**（逐字，SDD §4.1）：

```text
1  落盘：crctl review-record {cr} --stage {stage} [--bump-attempt]      # 既有步骤
2  提交：只提交 review-record 返回的 files[]                              # 既有纪律
3  PASS 既有动作（按 stage 分派、逐字沿用现状）：
     requirement → crctl advance --to requirement-reviewing --trigger review-requirement
     code        → crctl advance --to code-reviewing --trigger review-code --expect developing
     tech-design → 无（保持 tech-design-review-pending）
     dev-plan    → 无（保持 task-breakdown）
4  发布前置：r = crctl workspace inspect {cr}；require ∀ resources: classification == healthy（dirty 即 abort，不发布）
5  发布：push-progress(cr_id={cr}, message="{stage}评审通过")
     require phase == complete                     # changed=false 亦成功
6  对账：verify_release_batch(stage, r)            # §3.3；不等 → CONTRACT_DRIFT 中止
7  报告：透传 phase / batchId / repositories[] / metadataCommit + 对账结论
```

- `message` 四取值逐字：`需求评审通过` / `技术设计评审通过` / `开发计划评审通过` / `代码评审通过`。
- **不得**为 tech-design / dev-plan 新造 `advance`（那会新增状态转换，违反 NFR-4）；SKILL 文本按 stage 各写自己的 PASS 分支，**不共用一个含 `advance` 的模板**。
- **BLOCK 分支不含任何发布调用**（回修中间态不上远端）。
- **失败语义（FR-1 第 5 条）**：发布失败时 verdict 与评审账本保持已落盘结果不变；不重评、不改 verdict、不代作者提交、不回退状态；报告原始错误码与 `recovery`，按 `recovery` 重试**同一个** `push-progress`；发布失败**不阻塞**任何本地门禁。

### 3.3 发布后对账（FR-3，逐阶段判据）

| stage | 对账判据（逐字） |
|---|---|
| requirement | KB 批次 `sourceSha` 内容上的 `prd.md` **LF-only** sha256 ≡ `review-annotations/requirement.yml#subject-sha256` |
| tech-design | 同上（`sdd.md` ≡ `review-annotations/sdd.yml#subject-sha256`） |
| dev-plan | `plan.md` ＋ 全部 `TASK-*.md` 的 composite digest ≡ `review-annotations/dev-plan.yml#subject-sha256`（集合、路径、排序、`path:sha256` 行序逐字一致） |
| code | ① 非 KB 仓：`repositories[].sourceSha` 与 `review-annotations/code.yml#release-subjects[].reviewed-source-sha` **逐仓全等**；② KB 仓：`reviewed-source-sha` 是当前 KB HEAD 的**祖先** 且受控 artifact 逐文件 sha256、文件集合与 `artifacts.digest` 全等 |

- **取证链（KB / 非 KB 分解，SDD §4.3.1）**：非 KB 仓用 `crctl git rev-parse HEAD`（= `sourceSha`）；KB 仓用 `crctl git rev-parse HEAD` = `metadataCommit` ∧ `crctl git rev-parse --verify HEAD^` = KB `sourceSha` ∧ `dirty=false`。
- **禁止**：SHA 关系不成立时用工作区文件复算（等于自证）；**禁止**用 `git show` 取证（`rules.json` 的 `show` 只向 `system-orchestrator` 放行 `review-annotations/*`）。
- 复算先 `\r\n → \n`；解析失败**硬失败报错**（禁止「匹配不到 → 空集 → 静默通过」）。
- 判定不等 → **`CONTRACT_DRIFT` 技术中止**：**不改 verdict、不重评、不回退状态**；报告含期望值/实际值与复算内容来源。

### 3.4 「调用时机 / 用途」的旧 checkpoint 前提句改写（S-13，逐条原文）

| 文件 | 现文（逐字） | 目标口径 |
|---|---|---|
| `review-requirement/SKILL.md` L10 | 「**调用时机**: requirement-authoring pipeline 第 4 节点（push-progress 之后）」 | 删除「（push-progress 之后）」这一 checkpoint 前提；**不改节点序号数字**（`follow_up` 第 4 项） |
| `review-dev-plan/SKILL.md` L9 | 「**调用时机**: code-implementation pipeline 中 write-dev-tasks 之后、push-progress 之前」 | 改为「…write-dev-tasks 之后、开发启动人工审批之前」（去掉 checkpoint 前提） |
| `review-code/SKILL.md` L10 | 「**调用时机**: code-implementation pipeline 第 8 节点（代码编写与统一 checkpoint 后）」 | 删除「（代码编写与统一 checkpoint 后）」；**不改序号数字** |
| `review-code/SKILL.md` L16 | 「在开发者完成编码并推送统一 checkpoint 后，基于…」 | 改为「在开发者完成编码后（评审 PASS 时由本 Skill 发布阶段批次），基于…」口径 |
| `review-tech-design/SKILL.md` | 无 checkpoint 前提句 | 不动 |

- 改写后四个 review SKILL 中 `push-progress 之后` / `push-progress 之前` / `统一 checkpoint 后` **三个 token 零命中**（TASK-02 新增的负向断言，见 §3.6）；**不得**把「发布」写成「checkpoint 节点」口径。

### 3.5 权限面四处载体（FR-8 + B-1，缺一即交付缺陷）

| # | 载体 | 需出现的内容 |
|---|---|---|
| ① | `tools/agent-skill-matrix.yml`：`quality-reviewer-agent` | `forbidden` **移除** `push-progress`（`checkpoint` **保留**）；`can-call` **增加** `push-progress`；块注释（L192-194，位于 `can-call` 之下、`forbidden` 之上）注明 crctl 允许面含**只读** `workspace inspect` |
| ② | `tools/AGENT-SKILL-MATRIX.md`：`## 本 CR 权限变更` 节（L46） | 追加本 CR 行，**行内带 `CR-2026-066`**，约束列写明「新增 can-call `push-progress`；仅在对应 review SKILL 的 PASS 分支内发布一次，不修改业务文件、不推进状态、不改 verdict；crctl 允许面新增只读 `workspace inspect`」 |
| ③a | `tools/agents/quality-reviewer-agent.md`：`## 权限事实源` 节（L35-38） | 给出同一允许面声明（含只读 `workspace inspect`）；**不**新建「受限 crctl 权限块」（tools 侧该块不存在，SDD-CLOSE-04） |
| ③b | `multica/cr-prompts-revised/quality-reviewer-agent.md`：`## 受限 crctl 权限` 块（L35-46） | 穷尽式白名单在允许项（L39-42）**新增只读 `workspace inspect`**；禁止面枚举（L46）**保持含 `checkpoint`**；同时**原位改写 L54**「本 Agent 不负责 push/checkpoint，后续发布由 Pipeline 中对应的同步节点完成」→「评审 PASS 后由本 Agent 发布，经 `push-progress` Skill；不直接调用 `crctl checkpoint`」（该句改写与 TASK-04 的搭车规则同文件，本卡先落权限与发布职责句，TASK-04 追加搭车硬规则时不得回退本卡的改动） |

- 评审者边界（同时写入 SKILL 与 Prompt）：**只发布、不修改业务文件**；发布失败不改 verdict、不重评、不代提交；除各 review SKILL 既有要求的 `advance` 外不承担任何状态推进。
- **部署时序**：平台侧绑定/投影由 owner 在部署窗口执行；本卡只改仓库内文本（部署前 Multica 侧仍是旧白名单，部署窗口须与本卡改动成对生效）。

### 3.6 `pipeline-structure.test.mjs` 追加断言块（AC-3 / AC-4②③④ + S-13）

单条断言内同时校验（缺任一侧即失败）：

```text
A 四个 review SKILL 均含：crctl workspace inspect 前置 ∧ healthy 判据 token ∧ 「请作者先提交」语义；
  均含发布步骤：push-progress ∧ message 四取值之一的阶段式表述 ∧ phase / batchId / repositories / metadataCommit 四消费字段；
  均含对账：CONTRACT_DRIFT ∧ 「不改 verdict」语义；
  均含 BLOCK 分支不含发布的表述。
B tools 三处载体（① 矩阵注释 ∧ ② AGENT-SKILL-MATRIX.md 本 CR 行内含 CR-2026-066 与 workspace inspect ∧ ③a 权限事实源节）
  与 A 的「前置」同一条断言内校验（AC-4② 的 B-1 回归判据）。
C 反向断言：四个 review SKILL 文本不含 crctl checkpoint（发布只经 push-progress Skill）。
D S-13 负向断言：四个 review SKILL 不含 push-progress 之后 / push-progress 之前 / 统一 checkpoint 后。
```

- **TASK-01 已完成**本文件的既有断言改写；本卡只**追加**，不得改动 TASK-01 改写后的既有用例名与断言语义。
- 断言从**文件事实**推导（token 级，不钉死整句）；所有读入先 `\r\n → \n`；跨行/解析失败硬失败。
- 反向断言 C 与 D 是**反向判据**（零命中即绿）：必须**同时**断言 SKILL 文件被成功读出且非空（长度 > 0 且与既有正文长度同量级），禁止「文件读不到 → 零命中 → 静默通过」。

## 4. 验收条件（可执行）

1. **`cmd-02`**：`node --test --test-reporter=dot skills/shared/crctl/scripts/test/pipeline-structure.test.mjs skills/shared/crctl/scripts/test/contract-scan.test.mjs` → **exit 0**（含 A/B/C/D 四条新判据）；`cmd-01` 全量套件 `verdict=pass` / `failures=0`。
2. **`cmd-06`**（`repo=multica`）：`## 受限 crctl 权限` 块含 `workspace inspect` ∧ 禁止面含 `checkpoint` ∧ L54 冲突句零命中 ∧ diff 面恰 4 份 `cr-prompts-revised/*.md` → **exit 0**（变更前实测 exit 1 / 13 failures，其中 4 项与本卡直接相关）。
3. **`cmd-05`** 的 CI 静态五步：`lint-prompts --mode enforce` / `check-skill-matrix` / `check-agents-contract` → `exit 0`（新增文本不得触发 R1/R2/R9/R11/R12 规则：不裸写 `git` 写命令、不手写账本、不在同段出现 3+ 具名状态、不写「下一步」映射、不出现退役字段名）。
4. 负控自检（非证据）：临时删除某一份 SKILL 的 `crctl workspace inspect` 前置句，或在某份 carrier 里删掉 `workspace inspect` → 断言**必须红** → 还原 → `crctl git status --short` 干净（验证「两侧同时存在」的判据活性）。
5. `zero_diff` 自查：四个 SKILL 的参数表 / payload 结构 / 评审维度 / `passCondition` 零 diff；`crctl.mjs` / `rules.json` / `gates.json` 零 diff。

## 5. 完成标志

- 9 个文件就位并随 CR 提交（`[cr]` 前缀消息）；`cmd-02` exit 0、`cmd-06` exit 0、`cmd-05` 静态五步 exit 0；`cmd-01` 全量套件绿（无例外）。
- **B-1 两侧核对表**写入本任务完成记录：SKILL 侧（4 文件 × 前置/发布/对账/BLOCK 四要素） × 载体侧（①②③a③b）逐格打勾，并附 `grep` 命中原句。
- 四份 SKILL 的「调用时机/用途」旧前提句逐字改写对照（§3.4 表）留档；负向 token 三处零命中留 `grep` 证据。
- **任务账本登记**：`crctl task done CR-2026-066 --task CR-2026-066-TASK-02`（即时标 `done` 带 `done-at`）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- TASK-01 的产出：三份 JSON 的终态节点集（`ref=push-progress` 计数 0）——本卡的发布点唯一性前提。
- `skills/sync/push-progress/SKILL.md` 的**既有参数面**（`cr_id` 必填 + `message` 可选）与既有输出字段 `phase` / `changed` / `batchId` / `repositories[]`（`{repo, sourceSha, remoteRef, confirmed}`）/ `metadataCommit`——**不新增参数**（TASK-04 只改该文件的「调用时机」口径，不动参数面）。
- `crctl workspace inspect` 的既有只读输出（`resources[].{repo, classification, dirty, worktreePath, localBranch, remoteBranch}`）与 `crctl review-record` 的既有 `files[]` 返回。
- `review-annotations/{requirement,sdd,dev-plan,code}.yml#subject-sha256` / `#release-subjects[]`（既有事实源，**不新增字段**）。

**产出（下游 TASK 消费方不得缩略）**

- 四个 review SKILL 的 **PASS 发布合同**（§3.2 七步序列 + `message` 四取值 + 四消费字段 + 失败语义）——TASK-04 的口径改写（`push-progress/SKILL.md` / `README.md` / `openwiki` / `dir-graph.yaml`）必须与之同口径，**不得出现第二套说法**。
- `agent-skill-matrix.yml` 的 `quality-reviewer-agent` 终态（`can-call` 含 `push-progress`、`forbidden` 含 `checkpoint` 不含 `push-progress`、注释含只读 `workspace inspect`）——TASK-04 改 `agents/*.md` 的搭车规则时以本终态为准。
- `pipeline-structure.test.mjs` 的 **A/B/C/D 断言块**：TASK-04 在同一文件不再追加（FR-7 的静态文本断言落在 `contract-scan.test.mjs`）。
