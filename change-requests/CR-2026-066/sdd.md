---
id: CR-2026-066-sdd
type: SDD
cr-ref: CR-2026-066
title: CR-P3：评审 PASS 发布与 checkpoint 委派收敛 — 阶段终点发布点前移、审批后 checkpoint 节点退役、归档后本地 trunk 同步 技术设计
target-version: 0.39
status: draft
created: 2026-09-14T11:52:00+08:00
updated: 2026-09-14T12:57:00+08:00
---

# 1. 架构概览

## 1.1 设计目标与不变量

本 CR 的技术设计只做一件事：**把「阶段终点发布」从 pipeline 节点移进评审 Skill 的 PASS 分支，并删掉由此失去存在理由的节点与冗余发布点**；同时让归档自己把本地主 checkout 对齐 origin。设计遵守 PRD §1.3.3 与 NFR-4 的零新增面，落成四条设计不变量：

| # | 设计不变量 | 判据落点 |
|---|---|---|
| I1 | **发布只发生在三个被授权的位置**：① 评审 run 内（FR-1）；② 已排定的下一阶段委派**内**（同一 run）；③ `recovery` 指定的同 run 重跑。除此之外任何位置不得出现 `push-progress`/checkpoint | FR-6 / FR-7 / AC-6 |
| I2 | **全仓 `git add -A` 之前，必须先证明启动工作区是干净的**——发布者（评审者）在跑 `push-progress` 前复核全部 resources `healthy`（`dirty=false`），不干净则不发布、不代提交 | FR-2 / FR-1 第 1 条 / AC-3 |
| I3 | **发布的必须是被评审的**——发布后用只读取证把「发布批次」绑定到「评审对象」；不成立即 `CONTRACT_DRIFT` 技术中止，不改 verdict、不改状态 | FR-3 / AC-3 |
| I4 | **归档是终态事务，其尾部 trunk 同步必须是 best-effort**：只 ff-only、永不破坏本地在途修改、逐仓失败只反映在返回行、不新增错误码、不改退出码 | FR-10 / AC-8 |

分层与依赖方向不变（`ARCHITECTURE.md` §4：Pipeline → Skill → crctl，依赖只朝下）。本 CR 不新增层级、不新增命令面、不新增账本文件。

## 1.2 变更面鸟瞰

三仓、29 个交付文件（tools 25 + multica 4；`sdd.md` 本身是本文档、不计入）。

```text
../tools（25）
  pipeline-templates/  requirement-authoring.pipeline.json      ← 删 2 节点 + 1 输入
                       architecture-design.pipeline.json       ← 删 1 节点
                       code-implementation.pipeline.json       ← 删 4 节点 + 1 输入 + replayNodes 1 项 + 1 句提示
                       _index.yml                              ← nodes 计数与 brief（3 条）
  skills/requirement/review-requirement/SKILL.md               ┐
  skills/develop/review-tech-design/SKILL.md                   │ 四个 review SKILL：
  skills/develop/review-dev-plan/SKILL.md                      │  + Step 1 clean 前置（FR-2）
  skills/develop/review-code/SKILL.md                          ┘  + PASS 分支发布与对账（FR-1/FR-3）
  skills/sync/push-progress/SKILL.md                           ← FR-09 口径重写
  agent-skill-matrix.yml ＋ AGENT-SKILL-MATRIX.md              ← reviewer 权限面（FR-8，三处载体之二）
  agents/dev-agent.md ＋ quality-reviewer-agent.md ＋ delivery-agent.md
                                                               ← 搭车硬规则 + 发布职责（FR-7）
  skills/shared/crctl/scripts/lib/workspace-transactions.mjs   ← archiveCr 返回 localTrunkSync（FR-10）
  skills/cr/cr-archive/SKILL.md                                ← 结果分类/输出块（FR-10.8）
  skills/writeback/merge-feature-branch/SKILL.md               ← publication lag 搭车语义（FR-6）
  README.md ＋ openwiki/pipelines/overview.md ＋ dir-graph.yaml ← FR-09 同一口径
  skills/shared/crctl/scripts/test/pipeline-structure.test.mjs ← AC-1/AC-2/AC-4 断言
  skills/shared/crctl/scripts/test/archive-tx.test.mjs         ← AC-8 用例
  skills/shared/crctl/scripts/test/contract-scan.test.mjs      ← AC-3/AC-4③ ＋ FR-7 静态文本断言
  skills/shared/crctl/scripts/test/crctl.test.mjs              ← 既有断言同步（node 删除连带，见 §6.4）
  skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs      ← 既有断言同步（同上）

../multica（4，部署副本，owner 部署）
  cr-prompts-revised/{quality-reviewer-agent,dev-agent,delivery-agent,cr-coordinator-agent}.md
```

`../multica/cr-prompts-revised/agent-skill-matrix.yml` **不在改动面**（S-7 收口，见 D-6 与 §6.6）；`CUSTOM.md` 不改（#75 已定义该目录是 tools 的部署副本）；不改任何 Go/TS 代码、不改平台 DB、不改 `aifirst/agent-import.mjs`。

## 1.3 依赖方向与分层（不变）

```text
Pipeline（pipeline-templates/*.json）   编排 Skill 调用顺序
   ↓  （本 CR 后：pipeline 不再有「发布节点」这一形态）
Skill（review-* / push-progress / merge / cr-archive）  提示词合约
   ↓
crctl（crctl.mjs + lib/workspace-transactions.mjs）     状态与账本唯一写入执行器
```

三条对本设计的硬约束（来自 `ARCHITECTURE.md` §5 与 §4）：

- **状态单一写者**：评审者发布与归档 trunk 同步都**不得**写 CR status；本 CR 不新增任何状态写入口（评审者的发布动作只经 `push-progress` → `crctl checkpoint`，其状态守卫只检查「非终态」）。
- **账本单一写入通道**：`localTrunkSync` 只出现在 `archiveCr` 的**返回值**中，不落盘、不写 journal、不写账本（`reconcileLocalTrunks` 本身即零账本副作用）。
- **Skill 通用、约束归仓**：`reconcileLocalTrunks` 只处理 `dir-graph.yaml#repositories` 声明的主 checkout，不在 Skill 文本里硬编码任何仓库名或路径。

## 1.4 关键流程

### 1.4.1 阶段终点发布点前移（FR-1/FR-2/FR-3）

```text
阶段 owner run（作者）                    评审 run（quality-reviewer-agent）
  register / write-*  ──┐                 ①FR-2 clean 前置：crctl workspace inspect
  （本地提交，不发布）   │                    └ 任一仓非 healthy → 不评审、不改任何账本
                        │                 ②既有评审动作（维度不变）
                        │                 ③crctl review-record → 提交 files[]
                        │                 ④该阶段既有 PASS advance（有则执行，见 §4.1）
                        │                 ⑤FR-1 发布前置：复查 resources 全 healthy
                        └─────────────────►⑥push-progress（message=<阶段>评审通过）
                                          ⑦FR-3 对账（发布批次 ≡ 评审对象）
                                          ⑧透传 phase/batchId/repositories/metadataCommit
```

人工审批（`crctl approve`）**不在发布路径上**：它是网络无关的本地账本事务（approval.yml + cr.md 同批提交）。审批提交由**下一阶段评审 PASS 的发布**带上远端；code 路径由 `merge` 的 publication preflight 同 run 兜底。

### 1.4.2 搭车与兜底（FR-6）

```text
requirement 审批 ─┐
tech-design 审批 ─┼─► 本地提交（不上远端）─► 下一阶段评审 PASS 的 push-progress 一并带走
dev-start 审批  ──┘
code 审批 ───────► merge 首次 prepare 前 publication preflight：
                    远端 requirement/{cr} 缺失 → MERGE_SOURCE_MISSING
                    远端 requirement/{cr} 滞后 → RELEASE_REMOTE_NOT_PUSHED
                    两者都携 recovery = checkpoint argv（crctl checkpoint {cr} --workspace …）
                    → writeback run 就地执行 recovery 一次 → 同一 run 内重跑 merge
```

### 1.4.3 归档尾部 trunk 同步（FR-10）

```text
crctl archive（终态事务，既有语义不变）
  … 四账本编辑 → commit → lease push → outbox → cleanup …
  └─► reconcileLocalTrunks(ctx)  ← 新增唯一调用点（既有函数、既有分类）
       每仓：symbolic-ref 判分支 → status 判 dirty → fetch --prune → ff-only
       返回行 { repo, trunk, before, remote, after, status, reason }
  └─► archive 返回值新增 localTrunkSync（与 recovery 同级）
```

## 1.5 与 PRD §1.5 五条裁定的承接

| PRD §1.5 | SDD 落点 |
|---|---|
| 第 1 条：FR-10 按实测 **6 个 reason**（含 `failed(trunk-unavailable)`） | §2.3 分类表、§4.6、AC-8② |
| 第 2 条：删除后 `ref=push-progress` 计数为 0（两条判据） | §4.4、AC-1 |
| 第 3 条：评审者走 `push-progress` Skill，`checkpoint` 仍留 `forbidden` | §3.3、D-3、AC-4①③ |
| 第 4 条：§1.1 的 6 次/3 次数字不进入验收面 | 本 SDD 全篇不引用该数字作为判据 |
| 第 5 条：**只读** `workspace inspect` 写入 reviewer 允许面（B-1） | §3.3、§4.2、AC-4②③、SDD-CLOSE-03 |

# 2. 数据模型

## 2.1 无新增实体、字段与账本（NFR-4 落点）

本 CR **不新增** pipeline 节点、评审维度、账本字段、观测指标、crctl 子命令、错误码、Skill 参数、落盘文件。因此第 2 节不定义新实体，只固定「既有结构在本 CR 中的精确形状」——这是实现唯一性的来源。

## 2.2 既有结构引用（只读，逐字沿用）

**(a) checkpoint 批次返回结构**（`push-progress` 的消费面，FR-1 第 3 条）

| 字段 | 形状 | 语义（本 CR 的对账依赖） |
|---|---|---|
| `phase` | `complete` \| 中间态 | 只有 `complete` 可进入对账 |
| `changed` | bool | `false` = 幂等重放（无新 commit），视为成功 |
| `batchId` | string | 批次 ID（写 `_backlog.yml#latest-checkpoint.batch-id`） |
| `repositories[]` | `{repo, sourceSha, remoteRef, confirmed}` | **KB 仓 `sourceSha` = metadata commit 的直接父**；非 KB 仓 `sourceSha` = 该仓 CR worktree HEAD = 远端分支 HEAD |
| `metadataCommit` | string | KB 仓的批次可见点（`_backlog.yml` latest-checkpoint 提交），= 发布后 KB worktree HEAD |

**(b) `localTrunkSync` 行结构**（FR-10.2/3，逐字沿用 merge 既有形状）

```text
{ repo: <dir-graph repository id>, trunk: <trunk 名>, before: <sha|null>, remote: <sha|null>, after: <sha|null>, status: null|unchanged|synced|skipped|failed, reason: null|wrong-branch|dirty|diverged|fetch-failed|trunk-unavailable|ff-only-failed }
```

**(c) `release-subjects`**（code 阶段对账的事实源，既有、不新增字段）

```text
{ version: 1,
  repositories: [{ repo, remote-ref, reviewed-source-sha }],   # = review-record --stage code 时刻各仓 CR worktree HEAD
  artifacts: { algorithm: sha256, canonicalization: crlf-to-lf+path-sort,
               files: [{ path, sha256 }],                       # prd.md/sdd.md/plan.md/tasks/_index.yml/TASK-*.md
               digest: sha256(files.map(f => `${path}:${sha256}`).join('\n')) } }
```

## 2.3 状态与门禁（不新增状态、不新增转换）

- 状态机口径不动（15 具名状态 + 注册前 `(new)`；28 条声明 / wildcard 展开 50 条，CR-2026-027 口径）。
- 本 CR 引用的四个「发布点状态」全部是**既有非终态**（`tech-design-review-pending` / `task-breakdown` / `code-reviewing` / `requirement-reviewing`），`crctl checkpoint` 的状态守卫只拒绝终态（`ILLEGAL_LEDGER_STATE`），故评审 PASS 时发布**不需要新增任何状态或转换**。
- `statusGates` 与 `gates.json` 零改动；`review-code.reviewLoop.replayNodes` 删除一项是本 CR 唯一触碰 `reviewLoop` 语义面的地方（PRD §7 已登记的例外）。

# 3. 接口契约

## 3.1 Skill 契约：四个 review SKILL（调用面与落盘面不变）

| 维度 | 现状 | 本 CR 后 |
|---|---|---|
| 参数 | 各 Skill 既有参数集 | **不变**（不新增参数；发布只用既有 `cr_id` + `message`） |
| 落盘 | `review-annotations/{requirement,sdd,dev-plan,code}.yml` + `review-loop.yml` + `traceability.yml` | **不变** |
| 状态转换 | 各 Skill 既有 `advance`（requirement/code 有，tech-design/dev-plan 无） | **不变**（新增发布步骤**不新增**任何 `advance`） |
| 新增动作 | — | Step 1 起始的只读 `crctl workspace inspect` 前置；PASS 分支内一次 `push-progress` + 一次对账 |

**PASS 发布步骤的合同（四个 SKILL 文本一致，逐字口径）**：

1. 触发顺序固定：`review-record` 成功落盘 → 按 `files[]` 提交（既有纪律）→ 该阶段既有 PASS `advance`（若该 Skill 有）→ 复查发布前工作区干净 → `push-progress`。
2. 发布调用：`push-progress`，`message = <阶段>评审通过`（`需求评审通过` / `技术设计评审通过` / `开发计划评审通过` / `代码评审通过`）。
3. 结果透传：`phase` / `batchId` / `repositories[]` / `metadataCommit` 逐字进入评审报告；`phase=complete ∧ changed=false` 视为成功。
4. BLOCK 分支：**不含**发布调用（回修中间态不上远端）。
5. 失败语义：verdict 与评审账本保持已落盘结果不变；不重评、不改 verdict、不代提交、不回退状态；报告原始错误码与 `recovery`，按 `recovery` 重试**同一个** `push-progress`；发布失败不阻塞任何本地门禁。

## 3.2 crctl CLI 契约：`archive` 返回新增 `localTrunkSync`

| 项 | 契约 |
|---|---|
| 新增字段 | `localTrunkSync`（与 `recovery` 同级），类型 = 上述行数组 |
| 既有字段 | `commit` / `lastCleanupError` / `remaining` / `preservedRefs` / `recovery` / `warnings` **逐字不变** |
| `phase` 分类 | `complete` / `cleanup-pending` **不变**；两个返回路径都带 `localTrunkSync` |
| 退出码 | **不变**（trunk 同步失败不改变退出码） |
| 错误码 | **不新增**（`fetch-failed` / `trunk-unavailable` / `ff-only-failed` 只出现在返回行的 `reason`） |
| 幂等重放 | `changed=false` 的 complete 重放路径同样返回 `localTrunkSync`（按当次实况），不产生新 commit；三个成功返回点（幂等重放早退 / `complete` / `cleanup-pending`）都带该字段 |

确定性四查：**幂等** = 重放按当次实况返回、零新 commit；**权限** = 只读 `git status/symbolic-ref` + best-effort `fetch`/`merge --ff-only`，不写账本、不动别的仓；**错误闭包** = 无新增错误码、退出码不变；**副作用** = 仅 `fetch --prune origin` 与 `merge --ff-only`（受控 `gitMust`，局部捕获）。

## 3.3 权限契约（FR-8 + B-1）

| Actor | 变更 | 约束 |
|---|---|---|
| `quality-reviewer-agent` | `forbidden` 移除 `push-progress`；`can-call` 增加 `push-progress` | 只在对应 review SKILL 的 PASS 分支内发布一次；不修改业务文件、不推进状态、不改 verdict |
| `quality-reviewer-agent` | crctl 允许面新增**只读** `workspace inspect` | 不新增子命令/错误码/写入面；`checkpoint` **仍留在** `forbidden` |

**允许面的四处载体（缺一即交付缺陷）**与断言落点：

| # | 载体文件 | 需出现的内容 | 位置（稳定节名） | 断言落点 |
|---|---|---|---|---|
| ① | `../tools/agent-skill-matrix.yml` | `quality-reviewer-agent` 块注释含只读 `workspace inspect` | 第 192–194 行的块注释（`can-call` 之下、`forbidden` 之上） | 断言 A（tools CI 可执行） |
| ② | `../tools/AGENT-SKILL-MATRIX.md` | 「本 CR 权限变更」节新增一行，**行内带 `CR-2026-066`** | 节名 `## 本 CR 权限变更`（L46），表格追加行（既有行为 L52，属既有 CR，不得混同） | 断言 A |
| ③a | `../tools/agents/quality-reviewer-agent.md` | 「权限事实源」节给出同一允许面声明（含 `workspace inspect`） | 节名 `## 权限事实源`（L35–L38） | 断言 A |
| ③b | `../multica/cr-prompts-revised/quality-reviewer-agent.md` | 「受限 crctl 权限」穷尽式白名单**新增只读 `workspace inspect`**；禁止面枚举保持含 `checkpoint` | 节名 `## 受限 crctl 权限`（L35–L46；允许面条目 L39–L42，禁止面枚举 L46） | 断言 B（交付证据，见 D-5） |

**部署时序**：平台 DB 与 Prompt 投影由 owner 在部署窗口执行；部署前 Multica 侧实际运行的仍是旧白名单（`workspace inspect` 未被列出）。本 CR 的机械断言只约束**仓库内文本**，不约束部署状态；部署动作不在本 CR 范围（PRD §1.3.2）。

## 3.4 错误语义

| 名称 | 归属 | 语义 | 本 CR 是否新增 |
|---|---|---|---|
| `CONTRACT_DRIFT` | **评审侧技术中止**（SKILL 文本定义，不是 crctl 错误码） | FR-3 对账不等：报告「期望值 vs 实际值」两侧原始 SHA 与复算内容来源；**不追加／不改写 annotation、不改 verdict、不回退状态（不改 status）、不重评**——review-record 已按 §4.1 步骤 ① 落盘，本中止发生在步骤 ⑥，只中止后续动作、不改写已落盘结果 | 新增**文本语义**，不新增 crctl 错误码 |
| `CHECKPOINT_SENSITIVE_PATH` / `CHECKPOINT_REMOTE_ADVANCED` / `CHECKPOINT_REMOTE_DIVERGED` / `CHECKPOINT_REMOTE_HISTORY_REWRITTEN` / `TX_*` | crctl 既有 | 评审发布失败时按 `recovery` 重试同一 `push-progress` | 否 |
| `MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` | crctl 既有 | publication lag；`recovery` = checkpoint argv；writeback 同 run 内执行 recovery 一次后重跑 merge | 否（只补 Skill 文本口径） |
| `ARCHIVE_*` | crctl 既有 | 归档前置/状态错误；本 CR 不新增、不改变 | 否 |

## 3.5 前端/HTTP 契约

N/A——本 CR 无 HTTP/REST 接口新增或修改（无 API 定义文件参与 diff）。按 `review-tech-design` 的条件基线（FR-08.2）本维度不适用。

# 4. 关键算法与流程

## 4.1 评审 PASS 发布序列（FR-1，四 SKILL 同构）

```text
publish_after_review_pass(stage):
  1  落盘：crctl review-record {cr} --stage {stage} [--bump-attempt]      # 既有步骤
  2  提交：git 提交 review-record 返回的 files[]                            # 既有纪律（评审者只提交账本文件）
  3  PASS 既有动作（按 stage 分派，逐字沿用现状）：
       requirement → crctl advance --to requirement-reviewing --trigger review-requirement
       code        → crctl advance --to code-reviewing --trigger review-code --expect developing
       tech-design → 无（保持 tech-design-review-pending）
       dev-plan    → 无（保持 task-breakdown）
  4  发布前置（等价于 FR-1 第 1 条的「工作树干净」判据）：
       r = crctl workspace inspect {cr}
       require ∀ resources: classification == healthy   # 零写入只读；dirty 即 abort，不发布
  5  发布：push-progress(cr_id={cr}, message="{stage}评审通过")
       require phase == complete                         # changed=false 亦成功
  6  对账：verify_release_batch(stage, r)                # §4.3；不等 → CONTRACT_DRIFT 中止
  7  报告：透传 phase / batchId / repositories[] / metadataCommit + 对账结论
```

设计要点：

- **步骤 4 复用 FR-2 的同一条只读判据**（`crctl workspace inspect` ⇔ 内部 `git status --porcelain` 的零写入封装），不使用裸 `git status`：这既满足 FR-1 第 1 条的「工作树干净」判据，又保持评审者的能力面不扩张（`workspace inspect` 正是 FR-8 已授权的只读子命令）。
- **步骤 3 的 stage 分派按事实源推导**：tech-design / dev-plan 的 PASS 分支**没有** `advance`（`review-tech-design` PASS 保持 `tech-design-review-pending`；`review-dev-plan` PASS 保持 `task-breakdown`），因此实现**不得**为「顺序」而给这两个 Skill 新造 `advance`（那会新增状态转换，违反 NFR-4）。SKILL 文本按 stage 写各自的 PASS 分支，不共用一个含 `advance` 的模板。
- **步骤 5 失败时步骤 1/2/3 的成果已落盘且不回退**（FR-1 第 5 条）：发布失败不触发第二次评审、不消耗 attempt。

## 4.2 FR-2 评审前置干净检查（四 SKILL Step 1 起始）

```text
pre_check(cr):
  r = crctl workspace inspect {cr}                       # 只读，零写入
  dirty_repos = [x ∈ r.resources : x.classification != "healthy"]     # healthy ⇒ dirty=false（更强前置：还要求 worktree 已注册且 HEAD 在 CR 分支）
  if dirty_repos ≠ ∅:
      报告（含逐仓 classification/dirty 事实与该仓未提交文件清单）
      给出「存在未提交内容，请作者先提交」
      → 不写临时 payload、不 review-record、不 advance、不改 status、不发布
      → 评审者不得对作者工作区做 git add / commit / stash / 清理
  else: 继续既有 Step（review-requirement 的 Step 1.5 pre-review 门禁顺位不变，仍在其后）
```

- 位置钉定：四个 SKILL 的 **Step 1 起始处**（`review-requirement` 的 Step 1.5 是其后的独立步骤，本前置不得插到 Step 1.5 之后）。
- 该前置**不新增** crctl 子命令、不新增错误码；输出复用既有 `workspace inspect` JSON 字段（`resources[].classification` / `dirty` / `worktreePath`）。`classification=healthy` **严格强于** `dirty=false`（`classifyRepoWorkspace` 还要求 worktree 已注册且 HEAD 在 `requirement/{cr}` 分支上，见 §6.3），故判据取 `classification`，不得写成二者等价——写反会漏掉 wrong-branch / path-unregistered 两类不干净工作区。
- **两侧必须同时存在**（B-1）：SKILL 文本含 `crctl workspace inspect` 前置 ∧ 四处载体含该允许面；缺任一侧由 AC-4 断言变红。

## 4.3 FR-3 发布与评审对象对账（`verify_release_batch`）

### 4.3.1 取证链（先把「发布批次」绑定到「当前提交」）

`push-progress` 以 `git add -A` 提交、并以 lease push 到 `refs/heads/requirement/{cr}`，其批次事实由 checkpoint 合同确定。**KB 仓与非 KB 仓的绑定关系不同**（这是本设计的核心技术判断，见 D-4）：

| 仓类别 | checkpoint 保证（契约级） | 取证命令（受控只读） |
|---|---|---|
| **非 KB**（`../tools`、`../multica`） | `repositories[].sourceSha` = 该仓 CR worktree HEAD = 远端分支 HEAD（dirty 时 checkpoint 自己 commit，随后三方相等） | `crctl git rev-parse HEAD --cwd <resources[].worktreePath>` |
| **KB**（`ai-first-platform-docs`） | `repositories[].sourceSha` = **metadata commit 的直接父**（checkpoint 内部断言 `parent !== kbSourceSha → CHECKPOINT_SNAPSHOT_INVALID`）；metadata commit 的 staged set **恰为** `change-requests/_backlog.yml` 一项（否则 `CHECKPOINT_SNAPSHOT_INVALID`）；发布后 KB worktree HEAD = `metadataCommit` | `crctl git rev-parse HEAD` → 必须 = `metadataCommit`；`crctl git rev-parse --verify HEAD^` → 必须 = KB `sourceSha`；两边相等 ∧ `dirty=false` ⇒ KB 工作区中**除 `_backlog.yml` 外**的每个文件与 `sourceSha` 逐字节相同 |

因此：**KB 工作区里的 `prd.md` / `sdd.md` / `plan.md` / `tasks/**` 就是 `sourceSha` 的内容**（它们不是 metadata commit 触碰的唯一路径），可在其上复算哈希；非 KB 仓直接比 HEAD。

**禁止**：在两个 SHA 关系不成立时用工作区文件复算（等于用 `subject-sha256` 自证，对账失去意义）——此时按 `CONTRACT_DRIFT` 中止并报两侧 SHA。`git show` **不得**作为取证手段（`rules.json` 的 `show` 只向 `system-orchestrator` 放行 `review-annotations/*`，shape 不含业务文件）；`rev-parse` / `diff` / `log` 等只读命令可用。

### 4.3.2 逐阶段对账判据

| stage | 评审对象事实（既有） | 对账判据 |
|---|---|---|
| requirement | `review-annotations/requirement.yml#subject-sha256` | KB `sourceSha` 内容上的 `prd.md` **LF-only sha256** 全等 |
| tech-design | `review-annotations/sdd.yml#subject-sha256` | KB `sourceSha` 内容上的 `sdd.md` LF-only sha256 全等 |
| dev-plan | `review-annotations/dev-plan.yml#subject-sha256`（composite） | plan.md + 全部 `TASK-*.md` 的 composite digest 同口径复算全等（集合、路径、排序、`path:sha256` 行序逐字一致） |
| code | `review-annotations/code.yml#release-subjects` | ① 非 KB 仓：`repositories[].sourceSha` 与 `reviewed-source-sha` **逐仓全等**（仓名一一对应）；② KB 仓：`reviewed-source-sha` 是当前 KB HEAD 的祖先 **且** 受控 artifact 逐文件 sha256 与文件集合、`artifacts.digest` 全等（= 既有 `verifyReleaseSubjects` 的 KB 语义：白名单外路径零漂移） |

- KB 仓不适用「逐仓 SHA 全等」的原因（**落点事实**）：code 阶段发布时，KB 仓必然比 `reviewed-source-sha` 多出评审记录/状态提交（`review-annotations/code.yml`、`review-loop.yml`、`traceability.yml`、`cr.md`、`_backlog.yml`），HEAD 前移是**设计使然**；既有 `approve-code`/`merge`/`writeback` 的复核同样是「KB 按受控 artifact + 祖先关系、非 KB 按 HEAD 全等」。SDD 采用同一语义，不新增判据。
- 复算遵循行尾纪律：读入先 `\r\n → \n`；跨行/逐行解析失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」。
- 判定不等 → `CONTRACT_DRIFT` 技术中止：**不改 verdict**、不重评、不回退状态；报告含期望值/实际值与复算内容来源。
- **不新增**账本字段、注解字段、哈希算法（沿用 `subject-sha256` / composite / `release-subjects` 三套既有事实源）。

## 4.4 FR-4 / FR-5 节点退役与连带面

### 4.4.1 删除对象（对象级删除，不是开关）

| pipeline | 删除节点（id 后缀） | 同步删除 |
|---|---|---|
| requirement-authoring | `…0003`（PRD 草稿可选 checkpoint）、`…0007`（审批后强制 checkpoint） | 输入 `auto_push_after_prd` |
| architecture-design | `…0005`（审批后强制 checkpoint） | — |
| code-implementation | `…0003`（TASK 可选 checkpoint）、`…0008`（统一 checkpoint）、`…0012`（审批后强制 checkpoint）、`…0015`（评审后审批前 checkpoint） | 输入 `auto_push_after_task`；`review-code.reviewLoop.replayNodes` 的 `…0008` 项（5→4）；`…0010.approvalPrompt` 的「且评审后 checkpoint `phase=complete`」前提句 |

节点数 requirement **7→5**、architecture **5→4**、code **16→12**；删除后三份 JSON 中 `ref=push-progress` 的节点对象计数 = **0**。不新增替代节点、不重编号其它节点 id（`id` 不回收不复用）、不删 `workspace-freshness`（`…0016`/`…0017`）与 `code_generation` 节点。

### 4.4.2 连带面清单（同一份 diff 内闭合）

1. `pipeline-templates/_index.yml`：三条 `nodes:` 计数改为 5 / 4 / 12；三条 `brief` 不再描述已删节点（新增一句「阶段终点发布发生在评审 PASS 的 review SKILL 内」）。
2. 删除节点的 prompt 中「阶段终点完成条件（CR-2026-044 FR-07）」与 `{{inputs.auto_push_*}}` 字面量随对象一并消失；**其余节点 prompt 不得残留** `auto_push_after_*` / `SKIPPED` 字面量。
3. **`node-N.md` 输出文件名：本 CR 不改名**。判定依据（事实观察）：`node-N.md` 的 N 取**节点 id 末段**而非位置序号——判别性证据是 code `…0016`（位置下标 6）写 `node-16.md`、`…0017`（下标 10）写 `node-17.md`、`…0009`（下标 11）写 `node-9.md`、`…0011`（下标 14）写 `node-11.md`；requirement/architecture 两份因 id 后缀与位置序恰好一致而不具判别力。既然 N 不依赖位置，删除节点**不改变任何既有名字**；`…0014`（review-dev-plan）写 `node-3.md` 属本 CR 之前已存在的命名不一致，登记为 `follow_up`（不扩大本 CR diff）。
4. **悬空引用核查（零命中）**：逐节点扫描 `node-\d+\.md` 后确认**没有任何存活节点读取已删节点的输出文件**——删掉的 `…0007`/`…0008`/`…0012`/`…0015` 与其 requirement 侧对应节点的输出名（`node-7.md`/`node-8.md`/`node-12.md`）只出现在**它们自身**的 prompt 里；`node-3.md` 另出现在 code `…0014` 的 prompt 中，但那是它**自己的输出文件名**（该 prompt 实际读取的是 `node-1.md` 与 `node-2.md` 两个存活节点），不构成引用；`…0009`（review-code）只读 `node-1.md`/`node-9.md`，与 `…0008` 的输出无关。删除 `…0003` 后 `…0014` 成为 `node-3.md` 的唯一写入者（此前的撞名随删除消失）。
5. **`node-N.md` 无任何运行时/生成器解析**：multica `server/internal/governance/**` 对 `node-\d+\.md` 零命中（`grep`），tools 侧唯一相关断言是 `pipeline-structure.test.mjs:229`（architecture 后续节点不得依赖 `node-1.md`）——本 CR 保持满足。
6. **既有测试面的连带改写**：见 §6.4（`pipeline-structure`、`contract-scan`、`crctl`、`checkpoint-tx` 四个文件；不改 `gate-registry.json`，`manifest.cases` 是下界、新增用例不需要改登记面）。

## 4.5 FR-6 搭车（同 run 内兜底，不得单开委派）

- **code 路径**：`merge` 的 publication preflight 语义不变；Skill 文本新增「写回 run 收到 `MERGE_SOURCE_MISSING`/`RELEASE_REMOTE_NOT_PUSHED` 时就地执行 `error.recovery`（结构化 argv，`shell:false`）**一次**，然后在**同一 run 内重跑 merge**；不得转成新委派/新 task」。
- **requirement / tech-design / dev-start 路径**：审批提交由下一阶段评审 PASS 的发布带上远端——这是设计取舍：审批是网络无关的本地账本事务，审批提交在下一阶段评审前只在本地，**换机恢复需重签一次**；交付说明必须明示该取舍。
- **禁止面**（写入四份 Agent 合同与 coordinator 副本）：checkpoint 只允许出现在 §1.1 I1 的三处；「为单个 `push-progress`/checkpoint 单独开 task/委派」次数 = 0（AC-6 观察项 ④）。
- 该硬规则**不新增**委派 lint 规则；由 `contract-scan.test.mjs` 面内一条同风格静态文本断言兜底（tools 三份 Prompt 均含硬规则文本）。
- `delivery-agent` 增量文本必须写明：① `recovery` argv 属于**被授权的同 run 重跑**，不受「不裸调 crctl 原语」约束；② 该例外**不**赋予独立发起 checkpoint 的权力。

## 4.6 FR-10 `archiveCr` 尾部 trunk 同步

### 4.6.1 算法（最小侵入）

```text
archiveCr(ctx, input):
  …（既有事务主体：证据门 → journal → 四账本编辑 → commit → lease push → outbox → cleanup；一行不改）…
  + 局部包装（不导出、不新建模块，紧邻既有 result(...) 定义）：
      const resultWithTrunkSync = (phase, changed, warnings, outbox)
        => result(phase, changed, warnings, outbox, reconcileLocalTrunks(ctx));
  + 三个成功返回点改经该包装：① phase===complete 的幂等重放早退；② 末尾 phase=complete；③ 末尾 phase=cleanup-pending
```

- 调用点时序：**归档 push 与 cleanup 之后**计算（终态已发布，trunk 事实稳定）；幂等重放路径单独计算（不复用上次结果，符合 FR-10.7「按当次实况返回」）。
- 复用既有 `reconcileLocalTrunks(ctx)`：**不新写同步算法、不改其内部判据与分类**（唯一新增的是调用点与返回字段）。
- 返回值：`result()` 结果对象新增 `localTrunkSync` 字段（与 `recovery` 同级），其余字段逐字不变。
- 失败不阻断：`reconcileLocalTrunks` 全程 best-effort（自身已对 `fetch`/`merge --ff-only` 局部捕获、不抛错），因此归档退出码与 `phase` 分类不受影响；逐仓失败只反映在行内 `status/reason`。
- dirty 策略：主 checkout dirty ⇒ `skipped` + `reason=dirty`，**零改动**本地在途修改；报告给出逐条 `reason` 与人类可执行的补救说明（`fetch --prune origin` + `merge --ff-only origin/{trunk}`）。
- 只处理 `dir-graph.yaml#repositories` 的**主 checkout**；永不 `reset`/`clean`/`stash`/强推。

### 4.6.2 返回面与文档同步

- `skills/cr/cr-archive/SKILL.md`：Step 3 结果分类表与「输出」块新增 `localTrunkSync`（含 4 状态 × 6 reason 的分类说明与补救指引）；`recovery` 语义与字段名不变。
- delivery-agent 的最终交付汇报面包含该字段（`localTrunkSync` 行摘要 + 未同步仓的补救说明）。

### 4.6.3 拆分判定（承接 PRD FR-10.9）

**不拆**。见 SDD-CLOSE-01（尺寸判据与结论）。

## 4.7 FR-7 搭车硬规则的文本落点

| 仓 | 文件 | 修订 |
|---|---|---|
| `../tools` | `agents/quality-reviewer-agent.md` | 新增「评审 PASS 后发布」职责（FR-1 的 Skill 动作由本 Agent 执行）+ 搭车规则；「权限事实源」节给出同一允许面声明 |
| `../tools` | `agents/dev-agent.md` | 原位改写「先有代码、测试报告和统一 checkpoint 再由 reviewer 评审」与「checkpoint 未完成不进入后续人工审批」两句为「评审 PASS 即发布」口径 + 搭车规则 |
| `../tools` | `agents/delivery-agent.md` | 新增搭车规则（publication lag 同 run 局部处理；recovery 例外的双向边界） |
| `../multica` | `cr-prompts-revised/{quality-reviewer-agent,dev-agent,delivery-agent,cr-coordinator-agent}.md` | 同步上述文本；`cr-coordinator-agent` 新增「不得为 checkpoint 单开委派」显式禁止 |

硬规则文本（三份 tools Prompt 与四份 multica 副本同句；tools 侧 `agents/` 无 `cr-coordinator-agent.md`，该副本只在 multica，见 §6.3）：

> 跨人工 gate 的第一份委派必须显式携带上一阶段尚未闭合的发布动作（在同一 run 内执行、只回报结果）；禁止为单个 `push-progress` / checkpoint 节点单独开委派。

同批原位改写的事实句（`../multica/cr-prompts-revised/quality-reviewer-agent.md` L54 现有「本 Agent 不负责 push/checkpoint，后续发布由 Pipeline 中对应的同步节点完成」与本 CR FR-1 直接冲突，必须改写为「评审 PASS 后由本 Agent 发布，经 `push-progress` Skill；不直接调用 `crctl checkpoint`」）。

# 5. 技术选型与替代方案

以下六项同时满足决策记录三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代），故记录；其余实现细节不记录。

## D-1 发布点前移到评审 PASS，审批后不设 checkpoint 节点

- **Decision**：阶段终点发布由评审者在 PASS 分支执行（每阶段恰好一次）；审批后无节点，审批提交搭车（下一阶段评审发布 / `merge` publication preflight 同 run 兜底）。
- **Context**：门后节点在 agent 驱动模式下没有强制力（无 runtime 检查、`abort` 只是纸面强度），而跨 gate 必须重新唤醒；冗余发布点使「实现→评审→审批」窗口出现两次 checkpoint。
- **Alternatives**：① 保留门后 checkpoint 并接受单飞委派（被 CR-2026-063/064 的事实否证）；② 引入平台执行层做 approval-continuation（PRD §7 排除：tools 包不只在 Multica 使用，不接受平台耦合）；③ 仅删除冗余节点、保留门后节点（未消除根因）。
- **Consequences**：+ 阶段终点=评审 PASS 的 checkpoint，远端批次与 verdict 同源；− 实现→评审窗口不再有中途恢复点（取舍一）；− 审批提交在下一阶段评审前只在本地，换机需重签一次（取舍二）；回滚边界 = FR-1~FR-3 与 FR-4~FR-5 可分别回退。

## D-2 归档 trunk 同步复用 `reconcileLocalTrunks`，且失败不阻断归档

- **Decision**：`archiveCr` 复用 merge 既有函数与分类，只在返回值新增 `localTrunkSync`；best-effort、永不破坏本地。
- **Context**：归档是 CR 最后一个动作，此后无任何节点对齐主 checkout；而 merge 已经验证过同一函数（唯一既有调用点）。
- **Alternatives**：① 归档前要求主 checkout clean 否则拒绝归档（把可选收益变成硬前置，会让 dirty 主 checkout 卡死终态事务）；② 归档失败即中止（`crctl archive` 已是终态权威发布 + 资源清理两段语义，加硬失败会污染 `phase` 分类）；③ 新写一套 trunk 同步算法（违反零新增与单一算法源）。
- **Consequences**：+ 零新算法、零新错误码、退出码不变；+ dirty 如实报告不静默；− trunk 同步失败不阻断归档（与「只是便利设施」的定性一致，由报告面暴露）。

## D-3 评审者只放开 `push-progress` Skill，不放开 `crctl checkpoint` 原语

- **Decision**：`can-call` 增加 `push-progress`，`checkpoint` 留在 `forbidden`。
- **Context**：`push-progress` 是「一次调用 + 结果解释」的能力面；`crctl checkpoint` 是深原语，包含跨仓 Git 序列与 journal 语义。
- **Alternatives**：① 放开 `checkpoint`（评审者获得跨仓写序列能力，超出「发布自己刚评审的批次」所需）；② 让 `system-orchestrator` 发布（跨 gate 仍需唤醒，回到单飞问题）。
- **Consequences**：发布能力最小化；评审者的能力面仍收敛在「读 + 一次 Skill 调用 + 一次账本落盘 + 既有 advance」。

## D-4 KB 仓的对账判据采用 checkpoint 合同导出关系，而非 `HEAD == sourceSha` 等式

- **Decision**：非 KB 仓用 `HEAD == sourceSha`；KB 仓用 `HEAD == metadataCommit ∧ HEAD^ == sourceSha ∧ dirty=false` 绑定内容，再用 artifact 哈希/digest 与 annotation 全等（§4.3）。
- **Context**：实测 KB 批次中 `repositories[].sourceSha` 是 metadata commit 的**父**（本 CR 自身的批次即为例证：`_backlog.yml#latest-checkpoint` 的 KB `source-sha` = `f9dd6fc3…`，而 `metadataCommit` = `3a553e3b…`、`3a553e3b^ = f9dd6fc3`）；code 阶段 KB 仓必然比 `reviewed-source-sha` 多出评审记录提交，HEAD 全等不可能成立。
- **Alternatives**：① 直接比较 KB `HEAD == sourceSha`（在当前 checkpoint 合同下恒不成立，对账必然假红）；② 复算时用 `git show <sha>:<path>` 取内容（`rules.json` 不放行评审者读业务文件）；③ 新增只读 crctl 子命令返回批次内文件（违反 NFR-4 零新增）。
- **Consequences**：对账判据与既有 `verifyReleaseSubjects`（`approve-code`/`merge`/`writeback` 已在用）同源，实现唯一；代价是评审者需按 §4.3.1 的三步只读取证建立绑定关系（已写明命令）。

## D-5 断言落点分层：tools CI 可执行断言 + multica 交付证据

- **Decision**：AC-4② 的机械判据分两层——**断言 A**（`pipeline-structure.test.mjs`，单一断言内同时校验四处载体中的 tools 三处 + 四个 review SKILL 前置，缺任一侧即失败，随 CI 每轮执行）；**断言 B**（`../multica/cr-prompts-revised/quality-reviewer-agent.md` 的 `## 受限 crctl 权限` 节核对，作为本 CR 的 TASK 完成证据与 `test-report.md` 的 issue evidence，不落为长期 CI 面）。
- **Context**：tools CI（`.github/workflows/crctl-ci.yml`）只 checkout tools 仓，`../multica` 在工作区外、在 CI 中不存在；NFR-6 又明令本 CR 对 multica 只改 Prompt 文档、不写 Go/TS 代码，因此无法在 multica 侧新增测试承载该断言。
- **Alternatives**：① 在 tools 测试里「有 `../multica` 则断言、无则跳过」——静默降级，违反工程纪律 #1（跨行/跨面解析失败必须硬失败）；② 新增跨仓扫描脚本/CI job——扩大扫描面，与 NFR-4/scope_out 冲突；③ 把 multica 副本排除出载体清单——与 PRD FR-8 明确的四处载体冲突。
- **Consequences**：CI 可执行的判据覆盖四处载体中的三处（tools 侧全部）；multica 副本以一次性交付证据覆盖并登记在交付说明，重复执行成本可接受。

## D-6 S-7 第五份权限面副本：**排除**出改动面并写明理由

- **Decision**：`../multica/cr-prompts-revised/agent-skill-matrix.yml`（第 192–194 行 reviewer 块注释与 tools 同名文件逐字相同、同样未含 `workspace inspect`）**不纳入**本 CR 的 multica 改动清单（维持 4 文件），在 SDD 与交付说明中写明排除理由，并登记 `follow_up`。
- **Context**：该副本是 **deployment snapshot**——`CUSTOM.md#75` 定性为「对照快照，公共 Agent Prompt 的唯一事实源为 `tools/agents/`、目录内公共 Prompt 副本不再独立演进、与 tools 分叉时以 tools 为准并人工对齐」；实测无任何代码消费者（`grep -rn "cr-prompts-revised"` 在 `*.ts/*.tsx/*.mjs/*.js/*.go/*.md` 内只命中 `CUSTOM.md`），也不被任何静态校验解析。另一个决定性事实：PRD §1.3.1 第 14 行的注记**已明写**「不改 `cr-prompts-revised/agent-skill-matrix.yml` 部署副本」，属已审批、已冻结范围，SDD 不得反向扩大。
- **Alternatives**：① 纳入（4→5 文件）——与已审批 PRD 明文冲突，且 PRD 哈希已锁（改动即作废本次人工审批）；② 沉默不提——留下 FR-8「不得在同一份合同下留第二种读法」的未说明例外。
- **Consequences**：排除理由进入 SDD/交付说明（可核对）；一致性由 `CUSTOM.md#75` 的「以 tools 为准、人工对齐」机制承担，登记为 `follow_up` 的第一项。

# 6. FR 到技术实现映射

## 6.1 FR 逐条映射（FR-1~FR-11）

| FR | 技术方案条目 | 落点文件 | 可机械核对 |
|---|---|---|---|
| FR-1 | §4.1 发布序列 + §3.1 合同（四 SKILL 同构、stage 分派不同） | 四个 `review-*/SKILL.md` | AC-3；`pipeline-structure.test.mjs` 断言前置换行与发布步骤存在 |
| FR-2 | §4.2 前置算法（位置钉定在 Step 1 起始） | 同上 4 文件 + §3.3 四处载体 | AC-3、AC-4② |
| FR-3 | §4.3 取证链 + 逐阶段判据（含 KB/非 KB 分解） | 同上 4 文件 | AC-3；断言含 `CONTRACT_DRIFT` 与「不改 verdict」 |
| FR-4 | §4.4.1 删除表（requirement `…0007`、architecture `…0005`、code `…0012`） | 3 份 pipeline JSON | AC-1 |
| FR-5 | §4.4.1 删除表 + §4.4.2 连带面 1/2/4 | 3 份 JSON + `_index.yml` + 4 个测试文件 | AC-1、AC-2 |
| FR-6 | §4.5（code 同 run 重跑；审批搭车；禁止面） | `merge-feature-branch/SKILL.md` + 四份 Agent Prompt | AC-6（延期验证点）+ `contract-scan` 文本断言 |
| FR-7 | §4.7 硬规则文本 + delivery 例外双向边界 + 静态文本断言 | 3 份 tools Prompt + 4 份 multica 副本 + `contract-scan.test.mjs` | AC-6、AC-5 |
| FR-8 | §3.3 权限契约（矩阵/can-call/forbidden/四处载体/部署时序） | `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、tools+multica `quality-reviewer-agent.md` | AC-4①~④ |
| FR-9 | §6.5 口径改写清单（四处同口径 + `node-N.md`/replayNodes 例） | `push-progress/SKILL.md`、`README.md`、`openwiki/pipelines/overview.md`、`dir-graph.yaml` | AC-7 |
| FR-10 | §4.6 算法（复用 + 三返回点 + best-effort + 幂等 + 文档面） | `workspace-transactions.mjs`、`cr-archive/SKILL.md`、`delivery-agent.md` | AC-8 |
| FR-11 | §6.7 生成物登记（受影响映射清单 + Runner 保持禁用） | 交付说明（`test-report.md` / CR 交付评论） | AC-9 |

## 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §4.4 删除表（§1.2 三份 JSON） | 三份 JSON 节点数 5/4/12；不存在位于 `human_approval` 之后的 `ref=push-progress` 节点；`ref=push-progress` 计数 = 0；`_index.yml` nodes 与 JSON 一致；被删 id 零出现 | 两条判据都可由 JSON 自身求出（节点序与节点计数），不依赖运行时；删除后「0 个发布节点」与「无门后发布节点」同时成立 |
| AC-2 | §6.4 测试面改动清单 + §4.4.2-4 | `pipeline-structure.test.mjs` 全绿；新断言覆盖 AC-1 两条判据 + 「review SKILL 含发布步骤 + clean 前置」 | 断言从 JSON/`_index.yml`/SKILL 文本事实源推导（NFR-5），不钉死易漂移措辞；`suite-gate` 的 `manifest.cases` 是下界（`SUITE_MANIFEST_CASE_DROP` 只在减少时红），新增用例不需要改登记面 |
| AC-3 | §4.1/§4.2/§4.3（四 SKILL 文本） | 四个 SKILL 均含 clean 前置（`crctl workspace inspect` + `healthy` 判据 + 「请作者先提交」）、PASS 发布（`push-progress` + `message` + 四字段消费）、对账（`CONTRACT_DRIFT`）与失败语义；BLOCK 段落不含发布调用；四个 SKILL 不含 `recoverCommand`/`recover_command` | 文本事实可由文件读出；`RETIRED_RECOVERY` 整树扫描既有、本 CR 不引入旧字段名 |
| AC-4 | §3.3（四处载体 + 断言 A/B） | ① 矩阵 can-call 含 `push-progress`、forbidden 不含且仍含 `checkpoint`；② 断言 A 单条内同时校验 tools 三处载体与四个 SKILL 前置；③ 反向：SKILL 无 `crctl checkpoint`、两份副本权限块含 `workspace inspect`；④ `AGENT-SKILL-MATRIX.md` 本 CR 行；三脚本全绿 | tools 三处载体 + 四个 SKILL 的断言在 CI 内可执行（D-5）；multica 副本以交付证据覆盖（D-5），本 CR 的 TASK 完成标志即含该项；③ 的 tools 侧可直接断言，multica 侧与 ② 同批核对 |
| AC-5 | NFR-1；§6.4 | CI（Ubuntu+Windows）六个步骤全绿；不签例外 | 所有被删除节点牵连的断言都在 §6.4 登记并改写；`lint-prompts --mode enforce` 的风险面在 §7.1 说明（新增文本不得构成状态机副本/裸 git/下一步映射） |
| AC-6 | §4.5 + §6.6（延期验证点登记格式） | 交付说明登记：载体（交付后新注册的小体量演练 CR／次选 CR-P1 首链）、时点、观察项 ①~④、责任 agent、关闭触发条件 | 该演练在本 CR 交付时**不可能**产出证据（需另一个 CR 走完四阶段），故设计为「登记即达成、未登记即 AC-6 未通过」；观察项 ① 的判据（`confirmed=true` + `metadataCommit` 非空 + 对账通过）在本 CR 的四次发布中即可部分自证（本 CR 自身就是载体之一） |
| AC-7 | §6.5 四处口径改写 | 四处均出现「阶段终点完成条件 = 评审 PASS 的 checkpoint（评审者执行、每阶段一次）」与「审批后无 checkpoint 节点 / 搭车」；无「审批后的阶段终点 checkpoint 为强制完成条件」旧句 | 四处均为仓库内文本，可逐字核对；额外把 `openwiki/pipelines/overview.md` 的 replayNodes 例（现含 checkpoint）与 `/coding` mermaid 的两个 checkpoint 节点一并改准，避免同文件内出现第二套事实 |
| AC-8 | §4.6 | `archive-tx.test.mjs`：① 两分支均含 `localTrunkSync`；② 4 状态 × 6 reason 分类正确；③ dirty ⇒ `skipped/dirty` 且本地逐字节未变；④ argv 级命令面白名单：零 `reset/clean/stash/--force/push` 且命令面恰为 7 项（判据见右）；⑤ `changed=false` 重放仍返回且零新 commit；⑥ SKILL 与 delivery 汇报面含该字段 | ④ 的「命令面断言」必须是 **argv 级**，文本级子串判据在 §9 明令零 diff 的函数体上恒假（`rows.push(row)` 含 `push`；git 命令以 argv 数组书写、无字面 `merge --ff-only`），故不采用。实现：抽 `export function reconcileLocalTrunks` 起至下一个顶层 `}` 的函数体文本 → 抽其中全部 `gitRun`/`gitMust` 的第二个实参 argv（实测 7 个调用点）→ 归一化签名（取首 token；argv 含 `--prune`/`--verify`/`--is-ancestor`/`--ff-only` 之一时并入该选项）去重后**恰为** `rev-parse`／`rev-parse --verify`／`symbolic-ref`／`status`／`fetch --prune`／`merge-base --is-ancestor`／`merge --ff-only`（无多无少），且全部 argv 元素不含 `reset`/`clean`/`stash`/`--force`/`push`——子串判据只作用于 argv 元素，**不作用于整段函数体文本**；函数体或 argv 抽取失败、调用点数 ≠ 7 ⇒ **硬失败**（不降级为空串/空集）。该断言与 §9 的函数体零 diff 约束相容（判据落在命令面而非文本），与 ③ 的字节比对互为独立证据 |
| AC-9 | §6.7 | 交付说明登记受影响映射清单（见 §6.7 表）且必有「重启生成前保持 Runner 禁用」或「已重生成」之一 | 映射清单由节点下标直接算出（可复算）；`ArchitectureRunnerEnabled()` 默认 false（`runner.go:56-63`）是既有事实；本 CR 不改 `gate_nodes_gen.go`，故只能走「保持禁用 + 登记」分支 |
| AC-10 | §9 批准范围（scope_in/scope_out/zero_diff） | ① diff 不含平台执行层/Runner/continuation、新节点/维度/账本字段/观测指标、事务层/状态机/错误码改动、`recovery` 字段名改动、`recoverCommand` 复活；② 不含 `onFail:skip` + 输入端开关形式的「审批后/评审后 checkpoint」；③ 在途 CR 唯一（066）、063/064/065 均 archived；④ 与 CR-P1/P2 的面零 diff | ③ 现成（`crctl status` 可查）；④ 由 zero_diff 清单 + 交付前 diff 复核保证；① 的 `recoverCommand` 面由 `contract-scan` 的 `RETIRED_RECOVERY` 整树扫描兜底 |

**反查（§6.2 → §4/§3 正文）**：每条 AC 的落点都能产出所写可观测结果；无「关键前置使目标不可达」的情形——唯一需要额外证成的是 AC-4② 的跨仓可执行性（已由 D-5 把判据拆为可执行层与交付证据层，未把目标过滤掉）与 AC-6 的时点（已由「登记即达成」定义解除不可达）；AC-8④ 的判据已按 argv 级重定义（见该行与 §7.1），与 §9 的函数体零 diff 约束相容，不再存在「文本级判据恒假」的不可达面。正文算法与接口契约均不与 PRD 明文要求冲突：唯一与 PRD 字面表述不同的一处是 FR-3 的 KB 取证等式，已在 §4.3.1/D-4 逐条给出事实与替代论证，且结论与 PRD 的「KB 受控 artifact 哈希与 release snapshot 一致」同向。

## 6.3 既有实现依赖与事实

正文存在但未列入本清单的同类事实引用视为漏列；本清单按仓与依赖面分组、组内按正文首次出现顺序排列（B-2 回修新增项按其正文首现位置插入对应分组）。

1. repo: tools
   relative path: ARCHITECTURE.md
   stable symbol/对象: `## 4. 分层与依赖方向`（L69-82：Pipeline → Skill → crctl「依赖只朝下」的图示与规则）与 `## 5. 硬不变量`（L83 起：不变量 1 状态单一写者、2 账本单一写入通道、4 行尾与硬失败纪律、8 Skill 通用约束归仓）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: §1.1 的「分层与依赖方向不变」与 §1.3 的三条硬约束均取自本文件（实读 L69-95，与声明一致）；I1~I4 四条设计不变量不得与之冲突，本 CR 不新增层级、写入口与账本文件。
2. repo: ai-first-platform-docs
   relative path: change-requests/_backlog.yml
   stable symbol/对象: `change-requests[].latest-checkpoint.{batch-id,repositories[].source-sha,remote-ref}`（批次快照结构）
   commit SHA: 3a553e3bd74e63e9c1d60cf692c7a579c638e996
   依赖结论: FR-3 对账的期望值来源是 checkpoint 返回批次；本文件当前条目实测「KB `source-sha` = `metadataCommit^`」，是本设计 KB 判据（D-4）的直接实证。
3. repo: ai-first-platform-docs
   relative path: change-requests/CR-2026-066/prd.md
   stable symbol/对象: PRD 文档本体（`sha256(LF)` = `9b43bbfafa3be7a82c7e86900b17f64c3e95365347c9ed8588883e8d53aef1db`，349 行 / 61,874 B / 零 CR（行数与 canonical `review-annotations/requirement.yml` 同口径））
   commit SHA: 3a553e3bd74e63e9c1d60cf692c7a579c638e996
   依赖结论: 本 SDD 的全部 FR/AC/§1.4 事实与 §1.5 裁定均以此冻结版本为输入，SDD 不得触碰该文件（改哈希即作废人工审批）。
4. repo: tools
   relative path: pipeline-templates/requirement-authoring.pipeline.json
   stable symbol/对象: `nodes[]`（7 节点：`…0001`/`…0002`/`…0003`/`…0004`/`…0005`/`…0006`/`…0007`）、`inputs[].key`（含 `auto_push_after_prd`）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: FR-4/FR-5 的删除对象（`…0003`/`…0007` 对象 + `auto_push_after_prd`）与 AC-1 的 5 节点终态。
5. repo: tools
   relative path: pipeline-templates/architecture-design.pipeline.json
   stable symbol/对象: `nodes[]`（5 节点，`…0005` 是唯一 push-progress，位于 `…0003` human_approval 之后）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: FR-4 删除 `…0005` ⇒ 4 节点；AC-1 与 FR-11 的 registry digest 变化均源于此。
6. repo: tools
   relative path: pipeline-templates/code-implementation.pipeline.json
   stable symbol/对象: `nodes[]`（16 节点；push-progress 位于下标 3/9/12/15）、`inputs[].key`（含 `auto_push_after_task`）、`nodes[11].reviewLoop.replayNodes`（5 项，第 3 项 `…0008`）、`nodes[13].approvalPrompt`（含「且评审后 checkpoint phase=complete」）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: FR-4/FR-5 的删除面与 §4.4.2 的连带面（输入、replayNodes 5→4、approvalPrompt 前提句）全部落在本文件的这些稳定符号上。
7. repo: tools
   relative path: pipeline-templates/_index.yml
   stable symbol/对象: `pipeline-templates[].nodes`（requirement 7 / architecture 5 / code 16）与三条 `brief`
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: `dir-graph.yaml#pipeline_templates.contract` 第 1 条要求「新增或修改 pipeline JSON 后同步 _index.yml 的 nodes 数量」；`pipeline-structure.test.mjs` 与 `crctl.test.mjs` 都以本文件为一致性事实源。
8. repo: tools
   relative path: skills/shared/crctl/gates.json
   stable symbol/对象: `approvalStages.*`（`to`/`trigger`/`expect`/`approvalSection`/`evidence`/`passCondition`；声明式映射，不复刻规则副本）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: §2.3 与 §9 的「`gates.json` 零改动」声明、SDD-CLOSE-02 第 7 项「门禁只读本地」结论的载体；评审 PASS 发布不新增审批段、不改门禁，故保持零 diff。
9. repo: tools
   relative path: skills/requirement/review-requirement/SKILL.md
   stable symbol/对象: 「调用时机」（L10，`第 4 节点（push-progress 之后）`）、Step 1「前置校验」（L32）、Step 1.5 pre-review 门禁（L37）、PASS 分支（L131 的既有 `advance`）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: FR-2 前置须插在 Step 1 起始（Step 1.5 之前）；FR-1 的发布须接在既有 PASS `advance` 之后；「调用时机」的 checkpoint 前提句需同步。
10. repo: tools
    relative path: skills/develop/review-tech-design/SKILL.md
    stable symbol/对象: Step 1「读取输入」（L38）、Step 4 分流（PASS 保持 `tech-design-review-pending`，无 `advance`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 该 Skill 的 PASS 分支**没有** `advance`，是 §4.1 按 stage 分派的直接依据（不得为该阶段新造 `advance`）。
11. repo: tools
    relative path: skills/develop/review-dev-plan/SKILL.md
    stable symbol/对象: Step 1「前置校验」（L33）、Step 4 路由「PASS 保持 task-breakdown」（L132）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 与 10 同理（PASS 无 `advance`）；其「调用时机」（L9）含「push-progress 之前」的旧前提句，需随 FR-5 改写。
12. repo: tools
    relative path: skills/develop/review-code/SKILL.md
    stable symbol/对象: 「调用时机」（L10 `第 8 节点（代码编写与统一 checkpoint 后）`）、用途句（L16「在开发者完成编码并推送统一 checkpoint 后…」）、Step 5 PASS 分支（L142 的既有 `advance --to code-reviewing`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 该 Skill 的两个「统一 checkpoint 前提句」在 FR-5 删除 `…0008` 后即失真，必须改写；其 PASS `advance` 是 §4.1 步骤 3 的唯一 code 阶段动作。
13. repo: tools
    relative path: skills/sync/push-progress/SKILL.md
    stable symbol/对象: 「调用时机」（L9 的「需求/架构/代码审批后的阶段终点 checkpoint 为强制完成条件」）、参数（`cr_id`/`message`）、Step 2 输出解释（`phase`/`changed`/`batchId`/`repositories[]`/`metadataCommit`）、Step 3 摘要、错误处理表
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-9 与 AC-7 的目标句落在此文件的「调用时机」；FR-1 的发布调用只用既有参数面（不新增参数）。
14. repo: tools
    relative path: skills/writeback/merge-feature-branch/SKILL.md
    stable symbol/对象: Step 3 结果分类表的 publication lag 行（L53：`MERGE_SOURCE_MISSING`/`RELEASE_REMOTE_NOT_PUSHED` → 「状态保持 `code-approved`，不回退；按 `error.recovery`（结构化 argv）先 checkpoint 再重跑 merge」）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-6 的落点文件；§3.4 与 §4.5 的「同一 run 内执行 `recovery` 一次后重跑 merge」以本行的既有语义为前提，本 CR 只补「同 run、不得转成新委派」的口径，不改其分类表结构。
15. repo: tools
    relative path: skills/cr/cr-archive/SKILL.md
    stable symbol/对象: Step 3 结果分类表（L56-84）与「输出」块（`commit`/`lastCleanupError`/`remaining`/`preservedRefs`/`recovery`/`warnings` 逐字透传）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-10.8 的落点文件；§4.6.2 要求其 Step 3 分类表与「输出」块新增 `localTrunkSync`，同时既有字段与分类语义逐字不变（AC-8⑥ 的文本断言面）。
16. repo: tools
    relative path: skills/shared/crctl/scripts/crctl.mjs
    stable symbol/对象: `cmdCheckpoint`（L2367-2393：status 读 KB CR worktree，仅拒绝终态 `ILLEGAL_LEDGER_STATE`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 评审 PASS 时的四个状态（`requirement-reviewing`/`tech-design-review-pending`/`task-breakdown`/`code-reviewing`）均非终态 ⇒ 发布不需要新增状态或转换（NFR-4）。
17. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `checkpointCr` 的 KB 合同（`payload.kbSourceSha` = metadata commit 直接父且受断言 `parent !== payload.kbSourceSha → CHECKPOINT_SNAPSHOT_INVALID`；metadata stage 集合必须恰为 `change-requests/_backlog.yml`，否则 `CHECKPOINT_SNAPSHOT_INVALID`；非 KB 仓 `sourceSha == 本地 HEAD == 远端 HEAD`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §4.3.1 的 KB 取证链与 D-4 的全部依据；也是对账判据能否成立的唯一事实源。
18. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `classifyRepoWorkspace`（L660-688：`localBranch`/`remoteBranch` 用本地 ref，`dirty` 用 `git status --porcelain`，**不 fetch、不 ls-remote**）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-2 前置与 FR-1 步骤 4 是网络无关的只读检查（评审者在离线环境亦可完成前置校验）；`classification=healthy ⇒ dirty=false`（更强前置：还要求 worktree 已注册且 HEAD 在 CR 分支上）判据成立。
19. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `buildReleaseSubjects`（L1216-1252）/`verifyReleaseSubjects`（L1283-1360 区域：非 KB `HEAD == reviewed-source-sha`、KB 祖先关系 + 受控 artifact 逐文件/集合/digest 重核）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §4.3.2 code 阶段判据与该既有复核语义同源（KB 不比 HEAD 全等），避免评审者自造第二套判据。
20. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `reconcileLocalTrunks(ctx)`（L1487-1521：行形状 `{repo,trunk,before,remote,after,status,reason}`；`status ∈ unchanged|synced|skipped|failed`；`reason ∈ wrong-branch|dirty|diverged|fetch-failed|trunk-unavailable|ff-only-failed`；仅 `fetch --prune origin` + `merge --ff-only`；全程局部捕获不抛错）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-10 复用对象；其分类与形状即 `localTrunkSync` 契约，也是 AC-8②③④ 的判据源。
21. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `reconcileLocalTrunks` 在 merge 的既有唯一调用点（L1786）与返回（L1791）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 证明「函数已被生产路径验证」且字段名已被消费；本 CR 只加第二个调用点与返回字段（FR-10.1/2）。
22. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `archiveCr(ctx, input)`（L3498 起）：`result()` 固定返回构造、三个成功返回点（L3597 幂等 complete 早退 / L3757 complete / L3759 cleanup-pending）、既有返回字段 `commit`/`lastCleanupError`/`remaining`/`preservedRefs`/`recovery`/`warnings`
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §4.6.1 的最小侵入点（三返回点 + 局部包装）；既有字段与 `phase` 分类不得改变（AC-8①、§3.2）。
23. repo: tools
    relative path: skills/shared/controlled-shell/rules.json
    stable symbol/对象: `git[]` 白名单（`rev-parse` → `callers:["*"]` 且含 `^--verify \S+$`；`show` → `callers:["system-orchestrator"]` 且只放行 `review-annotations/*`）、`protectedPaths.deny`（账本/审批/评审记录路径）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-3 的取证手段只能用 `rev-parse`（`HEAD`/`--verify HEAD^`）+ 文件只读；`git show` 不可用于业务文件；评审者不得写账本（deny 面不变）。
24. repo: tools
    relative path: agent-skill-matrix.yml
    stable symbol/对象: `quality-reviewer-agent`（L178-208：`can-call` 4 项、块注释 L192-194、`forbidden` 含 `push-progress` 与 `checkpoint`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-8 的改动对象与 AC-4① 的判据；注释扩容是本 CR 三处载体之一。
25. repo: tools
    relative path: AGENT-SKILL-MATRIX.md
    stable symbol/对象: `## 本 CR 权限变更` 节（L46）与既有数据行（L52，`quality-reviewer-agent`/`controlled-shell`，属既有 CR）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: S-8 要求本 CR 行内带 CR 编号以与既有行区分；`check-skill-matrix.mjs` 不校验 can-call/forbidden，故本表是人工可读的补充载体。
26. repo: tools
    relative path: agents/quality-reviewer-agent.md
    stable symbol/对象: `## 权限事实源` 节（L35-38：只声明「权限矩阵：agent-skill-matrix.yml」；文件 42 行、无 crctl 子命令清单）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: S-8③ 的「tools 侧不存在『受限 crctl 权限块』、对应节名是『权限事实源』」的事实源；本 CR 需在该节给出同一允许面声明（载体 ③a）。
27. repo: tools
    relative path: agents/dev-agent.md、agents/delivery-agent.md
    stable symbol/对象: `dev-agent.md` 的评审前置句（「先有代码、测试报告和统一 checkpoint…」「checkpoint 未完成时，不进入后续人工审批」在 tools 侧**实测不存在**——该两句仅存在于 multica 部署副本，tools 侧 dev-agent.md 现文为「委派路由合同（评审）」）；`delivery-agent.md` 的「不裸调 crctl 原语」句
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-7 的 tools 侧增量是**新增**搭车硬规则与发布职责，不是原位改写；原位改写的两个句子落在 multica 副本（见 29）。**PRD §1.4 事实 12 的「multica dev-agent.md L23/L41」与 tools 侧现行文本的差异在此登记为已核实事实。**
28. repo: tools
    relative path: README.md、openwiki/pipelines/overview.md、dir-graph.yaml
    stable symbol/对象: `README.md` L61-75（第 6 节 checkpoint 行 L65）、`openwiki/pipelines/overview.md` L114/L116/L118（三段描述）、L120-140（`/coding` mermaid 的 `D8["checkpoint"]` 与 `D12["checkpoint (mandatory)"]`）、L73（replayNodes 例含 checkpoint）、L172（contract 第 9 条）、`dir-graph.yaml` L178（`pipeline_templates.contract` 第 5 条）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-9/AC-7 的四处口径目标与两处连带（mermaid、replayNodes 例）都落在这些既有行上；`dir-graph.yaml` 第 5 条现文「按顺序列出修复、证据、checkpoint 与当前评审节点」必须改写。
29. repo: multica
    relative path: cr-prompts-revised/quality-reviewer-agent.md
    stable symbol/对象: `## 受限 crctl 权限` 节（L35-46：`仅限评审所需的以下子命令` + 四条允许项 L39-42 + 禁止面枚举 L46 含 `checkpoint`）、L54「本 Agent 不负责 push/checkpoint，后续发布由 Pipeline 中对应的同步节点完成」
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: B-1 事实源（`workspace inspect` 两侧均未出现）；L54 与 FR-1 直接冲突必须原位改写；载体 ③b 的断言 B 落点。
30. repo: multica
    relative path: cr-prompts-revised/dev-agent.md
    stable symbol/对象: L23「代码评审：先有代码、测试报告和统一 checkpoint，再由独立 reviewer 调用 `review-code`」、L41「评审 blocker 未清空、测试报告未 pass 或 checkpoint 未完成时，不进入后续人工审批」
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: FR-7 的两个「原位改写」句子实测在 multica 副本而非 tools 侧；改写为「评审 PASS 即发布」口径。
31. repo: multica
    relative path: cr-prompts-revised/cr-coordinator-agent.md
    stable symbol/对象: L19/L60（`crctl` 仅只读 `status`/`next`，禁止 `advance`/`approve`/`checkpoint` 等写入型子命令）
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: 「门后节点只能被单独委派」的直接原因；FR-7 需在本文件增加「不得为 checkpoint 单开委派」的显式禁止（不改其 crctl 只读边界）。
32. repo: multica
    relative path: CUSTOM.md
    stable symbol/对象: 条目 75（表行，物理行 387）（`cr-prompts-revised/` 定性：公共 Prompt 唯一事实源为 `tools/agents/`、目录内副本不再独立演进、以 tools 为准人工对齐、`cr-coordinator-agent` 不进 tools agent index）
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: D-6（S-7 排除第五份副本）与 D-5（multica 侧不建 CI 断言）的治理依据；本 CR 不改 CUSTOM.md。
33. repo: tools
    relative path: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
    stable symbol/对象: AC-1/AC-2/AC-3 断言（L24-52、L91-99、L114-137）、CR-2026-044 段（L168-213）、CR-2026-050 FR-12.x 段（L304-380）、8 条 pipeline 节点数表（L516-530）、architecture registry 断言（L262-278）、L229（architecture 后续节点不得依赖 `node-1.md`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §6.4 中必须改写的断言清单来源；也是 AC-1/AC-2/AC-4 新断言的落点。
34. repo: tools
    relative path: skills/shared/crctl/scripts/test/contract-scan.test.mjs
    stable symbol/对象: replayNodes 结构快照（L81-98）、`RETIRED_RECOVERY = ['recoverCommand','recover_command']` 整树扫描（L418-425 区域）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: replayNodes 快照含 `push-progress` ⇒ 必须随 FR-5 改写（§6.4）；FR-7 的静态文本断言按「同风格」落在此文件；`RETIRED_RECOVERY` 兜底 AC-3 的零命中判据。
35. repo: tools
    relative path: skills/shared/crctl/scripts/test/crctl.test.mjs、checkpoint-tx.test.mjs
    stable symbol/对象: `crctl.test.mjs` L5036（code pipeline inputs 逐字列表含 `auto_push_after_task`）、L5038（`ids.length === 16`）、L5040（`…0017` 是 `…0009` 的直接前驱；L5039 是 `…0013` 已删除断言）；`checkpoint-tx.test.mjs` L487-495（跨 4 份 pipeline 过滤 `push-progress`/`list-remote-checkpoints` 节点做 prompt 负向断言）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 这两处是 §1.3.1 第 13 行未列出、但会被 FR-4/FR-5 直接证伪的既有断言；`checkpoint-tx` 的 `filter` 形态在删除后集合退化为 1 项（resume-cr 的 `list-remote-checkpoints`），须改为显式枚举以杜绝「过滤为空 → 断言静默失效」。
36. repo: tools
    relative path: skills/shared/crctl/scripts/test/gate-registry.json、suite-gate.mjs
    stable symbol/对象: `manifest.files` / `manifest.cases`（下界语义：`SUITE_MANIFEST_CASE_DROP` 仅在用例数 `<` 基线时红）、`manifest.files` 磁盘集合等式
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 本 CR 只新增用例、不改测试文件集合 ⇒ **不需要**改 `gate-registry.json`（若新增文件则必须同步）。
37. repo: tools
    relative path: .github/workflows/crctl-ci.yml
    stable symbol/对象: 六个步骤（`lint-prompts --mode enforce`、`check-skill-matrix.mjs`、`check-agents-contract.mjs`、pipeline JSON 结构断言、`suite-gate.mjs --run`、writeback 单测）与 `paths` 触发面
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: AC-5 的判据面；其中 `lint-prompts` 的规则面（R1~R13）是本 CR 新增文本必须避让的约束（§7.1）。
38. repo: tools
    relative path: pipeline-templates/emit-registry.mjs
    stable symbol/对象: canonical JSON（`body.pipeline.nodes[].{id,kind,label,ref,prompt,approvalPrompt,onFail,reviewLoop}`）→ `digest = sha256(canonical)`；当前 digest `sha256:5454bfd990f88748fac3351e0abc1d044f14b490cdcef70ac6d627f5959c91cc`
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 删除 architecture `…0005` 必然改变 digest（节点对象进入 canonical JSON）；FR-11 只需登记，不要求本 CR 重生成。
39. repo: multica
    relative path: server/internal/governance/gate_nodes_gen.go、server/internal/governance/runner.go、server/internal/governance/gen/generate-gate-nodes.mjs
    stable symbol/对象: `ApprovalGates`/`ReviewGates` 的 `{PipelineID,NodeID,Seq}` 映射（requirement `…0005`/Seq 5、`…0004`/Seq 4；tech-design `…0003`/Seq 3、`…0002`/Seq 2；dev-start `…0004`/Seq 5；code `…0010`/Seq 14、`…0009`/Seq 12）、`ArchitectureCoreRegistryJSON` 内嵌 registry、`ArchitectureRunnerEnabled()`（`AIFIRST_ARCHITECTURE_RUNNER` 未设 ⇒ false）、生成器 `--check`（对 `../tools` 做比较）
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: §6.7 受影响映射清单的来源；Runner 默认关闭 ⇒ 未重生成期间不影响运行；实测 multica `.github/workflows/*` 对 `gate-nodes`/`gate_nodes`/`governance` **零命中**，故未重生成不会让 multica CI 变红（`--check` 是人工/验证时动作）。
40. repo: multica
    relative path: cr-prompts-revised/agent-skill-matrix.yml
    stable symbol/对象: L192-194 reviewer 块注释（与 tools 同名文件逐字相同、未含 `workspace inspect`）
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: S-7 的事实源；D-6 判定为 deployment snapshot（无代码消费者、无静态解析器，`grep -rn "cr-prompts-revised"` 只命中 `CUSTOM.md`），排除出本 CR 改动面。
41. repo: tools
    relative path: skills/sync/workspace-freshness/SKILL.md
    stable symbol/对象: 「用途」段（L13-15，关键句 L15）：「本 Skill 职责收敛为『远端 trunk 新鲜度预检』…fetch/sync 失败可中止当前 Pipeline 节点，但不改变 CR status、approval、review verdict 或 reviewLoop attempt」
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: SDD-CLOSE-02 第 2 项的证据：其 fetch 只用于感知 behind，本地 ahead 判定不依赖远端内容 ⇒ 与「审批提交只在本地」不冲突；其两个节点（code `…0016`/`…0017`）本 CR 不删。
42. repo: tools
    relative path: skills/shared/crctl/scripts/crctl.mjs
    stable symbol/对象: `approveAndAdvance`（L1095 定义；approval + status 原子提交核心，TTY 与 `--grant` 共用）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: SDD-CLOSE-02 第 3 项的证据：四个 `approve-*` 的输入面 = `approval.yml` + `review-annotations/*` + `gates.json`（code 阶段另经 `verifyReleaseSubjects`，不 fetch、不读 remote-tracking ref）⇒ 审批是网络无关的本地账本事务，支撑 FR-6 的搭车取舍。
43. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `applyWriteback(ctx, input)`（L3182 定义；内部化 `applyWritebackAtomic`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: SDD-CLOSE-02 第 5 项的证据：writeback 只消费 txws 内 approval/release-subjects 与 traceability journal，不做 trunk 相等性校验 ⇒ 不引入远端前置；§9 zero_diff 亦把其签名与 `checkpointCr`/`mergeCr`/`registerCr` 并列。

## 6.4 既有测试面改动清单（连带闭合，逐断言）

| 文件 | 断言/用例 | 处置 |
|---|---|---|
| `pipeline-structure.test.mjs` | L24-30（review-code < checkpoint(…0015) < human_approval） | **删除**（`…0015` 已删）；替换为 AC-1 两条判据断言 |
| 同上 | L32-42（`…0015` onFail=abort/ref=push-progress；`ids.length === 16`） | **改写**：节点数改为事实源推导 12；删除 `…0015` 相关断言 |
| 同上 | L44-52（replayNodes 逐字 5 项） | **改写**：4 项（去掉 `…0008`），仍由 JSON 事实源推导 |
| 同上 | L70-72（`…0008` < `…0017` < `…0009` 的相邻关系） | **改写**：删除 `…0008` 参与的前置，保留 `…0017` < `…0009` |
| 同上 | L114-116、L135-137（`…0010.approvalPrompt` 含「评审后 checkpoint phase=complete」） | **改写为反向断言**：`…0010.approvalPrompt` **不含**该句（FR-5 的同步删除面） |
| 同上 | L168-183（CR-2026-044 AC-13：requirement 7 节点 + approve-requirement 后必有 push-progress + `_index.yml` nodes=7） | **改写**：5 节点；「approve-requirement 之后**不得**有 push-progress」；`_index.yml` nodes=5 |
| 同上 | L186-203（AC-14：architecture `push.length === 1`、5 节点） | **改写**：`push.length === 0`、4 节点；保留「prompt 无 `crctl checkpoint` 字面量」与 `<installation-workspace>` 负向断言（其对象消失后按事实源推导重写） |
| 同上 | L205-213（AC-13 code：审批结果 checkpoint 存在 + TASK checkpoint 可选 + 16 节点） | **改写**：`ref=push-progress` 计数 = 0 + 12 节点 + inputs 不含 `auto_push_after_task` |
| 同上 | L262-278（architecture registry：`nodePermissions.length === 4` + `byRef['push-progress'] === 'system-orchestrator'`） | **改写**：3 个 skill 节点；去掉 push-progress 行；digest 改为「与 `node pipeline-templates/emit-registry.mjs --pipeline architecture-design` 输出一致」或断言格式（不得钉死旧 digest） |
| 同上 | L306-320（FR-12.2：requirement 7 节点顺序 + `auto_push_after_prd` 分支保留） | **改写**：5 节点顺序 `[requirement-register, write-requirement-prd, review-requirement, human_approval, approve-requirement]`；删除草稿 checkpoint 断言 |
| 同上 | L341-375（FR-12.3 L341-363 的 replayNodes 5 项含 `…0008` ＋ FR-12.3b L365-375 的字面量保留断言：`auto_push_after_task`、审批结果 checkpoint） | **改写**：删除 `auto_push_*`/checkpoint label 断言；保留 gate 名与 task done 面 |
| 同上 | L516-530（8 条 pipeline 节点数 7/5/16） | **改写**：5/4/12（其余 5 条不变）；UUID 全局唯一保持不变 |
| 同上 | **新增** | AC-1 两条判据（无门后 push-progress + `ref=push-progress` 计数为 0）；`_index.yml` ≡ JSON（既有 L91-99 已覆盖，保留）；四个 review SKILL 含 clean 前置 token（`crctl workspace inspect` + `healthy`）与发布步骤 token（`push-progress` + 四消费字段）；AC-4② 的单条「四处载体 + 四 SKILL 前置」断言；AC-4③ 反向断言（四 SKILL 不含 `crctl checkpoint`） |
| `contract-scan.test.mjs` | L81-98（code replayNodes ref 快照含 `push-progress`） | **改写**：4 项 ref（去 `push-progress`） |
| 同上 | **新增** | FR-7 静态文本断言：tools 三份 Prompt（`agents/{dev,quality-reviewer,delivery}-agent.md`）均含搭车硬规则文本（token 级：`push-progress` + `单独开委派`/`同 run`，不断言整句） |
| `crctl.test.mjs` | L5036（inputs 逐字含 `auto_push_after_task`）、L5038（16 节点）、L5040（`…0017` 直接前驱 `…0009`；L5039 是 `…0013` 已删除断言） | **改写**：inputs = `['cr_id','target_version']`；节点数按事实源推导；保留 `…0017` 与 `…0009` 相邻关系（删除后仍相邻） |
| `checkpoint-tx.test.mjs` | L487-495（跨 4 份 pipeline 的 `filter(...)` 负向断言） | **改写**：改为显式枚举剩余节点集合（`resume-cr` 的 `list-remote-checkpoints`；`requirement/architecture/code` 三份为空集合）并断言该枚举非空 + 逐条负向断言；**禁止**保留会随删除退化为空集的 `filter` 形态 |
| `archive-tx.test.mjs` | **新增用例**（AC-8 六项；文件与 fixture 既有） | ① 两分支含 `localTrunkSync`；② 分类正确；③ dirty ⇒ `skipped/dirty` + 本地内容逐字节未变；④ 从函数体抽 `gitRun`/`gitMust` 的 argv（7 个调用点）→ 归一化签名集合恰为 `rev-parse`/`rev-parse --verify`/`symbolic-ref`/`status`/`fetch --prune`/`merge-base --is-ancestor`/`merge --ff-only`，且 argv 元素零 `reset/clean/stash/--force/push`（argv 级；抽取失败或调用点数 ≠ 7 硬失败；判据全文见 §6.2 AC-8 行）；⑤ `changed=false` 重放仍返回且零新 commit；⑥ SKILL/delivery 汇报面含字段（文本断言） |
| `gate-registry.json` | `manifest.files` / `manifest.cases` | **不改**（无新增测试文件；`cases` 是下界，新增用例无需登记） |

## 6.5 FR-9 口径改写清单（四处同口径 + 两处连带）

| 文件 | 现文（要点） | 目标口径 |
|---|---|---|
| `skills/sync/push-progress/SKILL.md` L9 | 「PRD 草稿与 TASK checkpoint 仍为可选节点；需求/架构/代码审批后的阶段终点 checkpoint 为强制完成条件」 | 「阶段终点完成条件 = 评审 PASS 的 checkpoint（由评审者执行，每阶段一次）；审批后不再有 checkpoint 节点，未发布的审批提交由下一阶段评审 checkpoint 或 `merge` 的 publication preflight 搭车承担；发布失败保持当前状态、重跑同一 checkpoint，不重新评审/不重新审批」 |
| `README.md` L65 | 「需求/架构/代码三个阶段审批后的阶段终点 checkpoint 是 Pipeline 完成条件…」 | 同上口径（一句话内）；保留 `crctl checkpoint` 的通用（随时可用）语义 |
| `openwiki/pipelines/overview.md` L114/L116/L118 | 「then a **mandatory approval checkpoint**」「mandatory approval checkpoint」 | 改为「then the review PASS publishes the stage batch (mandatory)」口径；`/coding` 段删除「unified checkpoint → code review」中的统一 checkpoint 前置 |
| `openwiki/pipelines/overview.md` L120-140（mermaid） | `D8["checkpoint"]`、`D12["checkpoint (mandatory)"]` | 删除 `D8`/`D12` 两个节点；`D9`（review-code）PASS 分支直接接 `D10`（human_approval） |
| `openwiki/pipelines/overview.md` L73（replayNodes 例）、L172（contract 第 9 条） | 例含 `checkpoint`；第 9 条为「approval-stage terminal checkpoints are mandatory」 | 例改为 `code fix → test report → baseline re-verify → re-review`；第 9 条改为「stage terminal completion = the review-PASS checkpoint（published by the reviewer once per stage）；no post-approval checkpoint nodes」 |
| `dir-graph.yaml` L178（`pipeline_templates.contract` 第 5 条） | 「按顺序列出修复、证据、checkpoint 与当前评审节点」 | 改为「按顺序列出修复、证据、基线重核与当前评审节点」（S-4）；第 1 条（同步 `_index.yml` counts）与 reviewLoop 重放清单约束保持不变 |

## 6.6 AC-6 延期验证点登记格式（交付说明必填块）

TASK/交付说明按下列字段逐项登记（缺任一项即 AC-6 未通过）：

```text
AC-6 延期验证点
  载体       : <本 CR 交付后新注册的小体量演练 CR-ID（首选）| CR-P1 首链（次选）>
  时点       : 载体走完四个阶段的评审发布与审批之后
  观察项 ①   : 每个 review PASS 后远端存在完整批次（repositories[].confirmed=true ∧ metadataCommit 非空 ∧ 对账通过）
  观察项 ②   : 审批动作不产生任何 checkpoint 委派（评审 PASS 之后的 checkpoint 次数 = 0）
  观察项 ③   : 审批未发布时 merge 给出 MERGE_SOURCE_MISSING/RELEASE_REMOTE_NOT_PUSHED + recovery，同 run 执行后可继续（或首次即通过）
  观察项 ④   : 「为单个 push-progress 单独开 task」次数 = 0
  责任 agent : delivery-agent（记录发布批次与 merge 兜底）；cr-coordinator-agent（记录委派计数）
  关闭触发   : 载体归档，或该链路首次走完
```

## 6.7 FR-11 受影响映射清单（交付说明登记用，可复算）

| 生成物 | 受影响项 | 现在 | 删除后 |
|---|---|---|---|
| `gate_nodes_gen.go#ApprovalGates` | requirement | `…0005` / Seq 5 | `…0005` / **Seq 4** |
| `gate_nodes_gen.go#ReviewGates` | requirement | `…0004` / Seq 4 | `…0004` / **Seq 3** |
| `gate_nodes_gen.go#ApprovalGates` | tech-design | `…0003` / Seq 3 | 不变 |
| `gate_nodes_gen.go#ReviewGates` | tech-design | `…0002` / Seq 2 | 不变 |
| `gate_nodes_gen.go#ApprovalGates` | dev-start | `…0004` / Seq 5 | `…0004` / **Seq 4** |
| `gate_nodes_gen.go#ApprovalGates` | code | `…0010` / Seq 14 | `…0010` / **Seq 11** |
| `gate_nodes_gen.go#ReviewGates` | code | `…0009` / Seq 12 | `…0009` / **Seq 10** |
| `gate_nodes_gen.go#ArchitectureCoreRegistryJSON`（含 `digest`） | 整块 | digest `sha256:5454bfd9…c91cc` | 必变（nodes 5→4） |
| `../tools` registry 输出（`emit-registry.mjs`） | digest | 同上 | 必变（同源） |

登记文本必须二选一（AC-9）：**①** 「已重生成」（含重生成后的 `Source:` SHA 与新 digest）；**②** 「未重生成 ⇒ 重新生成前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用」。本 CR 的实际分支 = ②（`runner.go:56-63` 未设 `AIFIRST_ARCHITECTURE_RUNNER` 即 false；`.github/workflows/*` 对 `gate-nodes` 零引用 ⇒ 未重生成不会让任一侧 CI 变红）。重生成归 owner 部署窗口（PRD §1.3.2），登记 `follow_up`。

# 7. 安全与性能考量

## 7.1 行尾纪律与硬失败（工程纪律 #1，NFR-3）

| 面 | 纪律 |
|---|---|
| FR-3 哈希复算 | 读入先 `\r\n → \n`；composite digest 的集合/排序/行序逐字一致；解析失败硬失败，禁止「匹配不到 → 空集 → 静默通过」 |
| AC-8④ 函数体 argv 抽取 | 抽 `export function reconcileLocalTrunks` 起至下一个顶层 `}` 的函数体文本，再抽其中全部 `gitRun`/`gitMust` 的 argv（第二实参）；函数体抽不到、argv 解析不到、或调用点数 ≠ 7 → 抛错（红），不得降级为空串/空集通过；命令面判据只作用于 argv 元素，**不得**对整段函数体文本做子串匹配 |
| FR-5 测试改写 | 断言一律从 JSON/`_index.yml`/SKILL 文本按行解析（`split(/\r?\n/)`），跨行正则失败即红 |
| 新增 SKILL/README 文本 | 必须通过 `lint-prompts --mode enforce`：不得出现裸 `git` 写命令（R2）、不得手写账本（R1）、不得在 Agent/README 同段出现 3+ 具名状态（R12）、不得手写「下一步」映射（R9）、不得出现退役字段名（R11/R10） |

## 7.2 权限与越权面

- 评审者的能力面**只增不改**：`+push-progress`（Skill）与 `+只读 workspace inspect`；`checkpoint` 与全部写入型子命令仍在 `forbidden`。发布不获得「改业务文件」或「改状态」的能力（`advance` 仅限各 review SKILL 既有要求）。
- 评审者不代作者提交：FR-2 前置失败即停；发布前的干净复查（FR-1 步骤 4）把「全仓 `git add -A`」的输入面锁死在「已验证干净」的初始状态。
- 账本写面不变：`protectedPaths.deny` 零改动；评审者仍只提交 `review-record` 返回的 `files[]`；发布只经 `push-progress`（其内部 `_backlog.yml` latest-checkpoint 由 crctl 独占写）。
- `CONTRACT_DRIFT` 是**技术中止**而非裁决：不改 verdict、不重评、不回退状态，避免对账失败被误用为「改判」通道。

## 7.3 best-effort 与「不可破坏本地」

`reconcileLocalTrunks` 的副作用面被两条规则夹住：① 只对 `dir-graph.yaml#repositories` 的**主 checkout** 操作（不碰 CR worktree、不碰他人分支）；② 只 `fetch --prune` + `merge --ff-only`，dirty/wrong-branch/diverged 一律跳过并如实报告。因此归档不会因为本地在途修改而失败，也不会悄悄丢弃本地内容（AC-8③ 用「逐字节未变」把这条钉死）。

## 7.4 性能与观测

- 调用量：本 CR 在每阶段**减少**一次 checkpoint 节点执行（删除 7 个节点、新增 4 次评审内发布，净减少 3 次节点级发布动作），并在归档尾部增加每仓一次 `fetch --prune`（3 仓、best-effort）。不需要新的性能预算或观测指标（NFR-4：不新增观测指标）。
- 网络面：评审前置与对账均只读本地；发布需要网络（与既有 checkpoint 相同）；`merge` 的 publication preflight 仍是 code 路径唯一的远端相等要求。
- 日志/审计：评审者发布经 `push-progress`，其 `crctl checkpoint` 的 audit/outbox 语义不变；归档新增字段不改 audit 行为。

# 8. Prompt 采纳影响

**N/A（本 CR 不触及触发面）。** 依据：本节按 `write-tech-design` 的条件触发判定——只有当 diff 触及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支或 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny` 时才必填。

- `crctl.mjs`：本 CR **不改**该文件。`crctl archive` 的 dispatch 分支（`case 'archive': return cmdArchive(...)`）与 `cmdArchive` 的返回透传（`ok({ op: 'archive', ...result })`）都已存在，新增字段 `localTrunkSync` 随既有 spread 自动透传；无新增子命令、无新增参数、无新增错误码。
- `rules.json`：`git[]` 白名单与 `protectedPaths.deny` **零改动**（FR-3 的取证只用既有 `rev-parse`；不改 guard deny 面）。因此不存在「crctl 新增能力而某 Skill 该采纳未采纳」的漂移面，本节按规则省略为 N/A。

# SDD-CLOSE 关闭项（PRD 显式延后到 SDD 的设计项）

## SDD-CLOSE-01 FR-10 是否需要拆出（PRD FR-10.9）

**结论：不拆，FR-10 留在本 CR。** 判据：① FR-10 的实现面 = `archiveCr` 三个返回点改经一个局部包装 + 返回值新增一个字段 + 一个既有函数的第二次调用，**代码改动 < 20 行**；② 文档面 = `cr-archive/SKILL.md` 一处分类/输出块 + delivery 汇报面一句，与 FR-1~FR-9 的文本修订同批同风格；③ 测试面 = `archive-tx.test.mjs` 六项用例，复用既有 fixture（`makeWritebackFixture`/`makeNewModeArchiveFixture`）不新建夹具；④ 与其余 FR 无耦合（FR-1~FR-9 零依赖 FR-10；FR-10 零依赖别的 FR）。拆出反而要求同步缩减 AC-8 与 §6 指标、并在交付说明登记拆分——成本高于收益。**不触发 PRD FR-10.9 的缩面动作。**（关闭层覆盖：数据生产/存储/响应 schema/消费/兼容降级五层——`localTrunkSync` 由归档事务尾部产生、只出现在 CLI 返回值与文档面、无持久化、消费方为 delivery-agent 汇报、既有字段兼容面不变。）

## SDD-CLOSE-02 PRD §1.4 事实 22 的 8 项「门禁只依赖本地事实」复核

**结论：8 项逐条复核完成，FR-6 的取舍不需要重新评估。** 逐项（证据均在 tools@`5d5a4ada`）：

| # | 检查项 | 结论 | 证据 |
|---|---|---|---|
| 1 | `crctl workspace inspect` | 只读本地 | `classifyRepoWorkspace`（L660-688）只用 `rev-parse --verify refs/heads|refs/remotes/origin`（本地 ref）+ `worktree list --porcelain` + `status --porcelain`；**无 fetch/ls-remote** |
| 2 | `workspace-freshness`（ahead-only=fresh） | 该 Skill 明确定位为「远端 trunk 新鲜度预检」，其 fetch 只用于**感知 behind**；本地 ahead 状态判定不依赖远端内容 ⇒ 与「审批提交只在本地」不冲突 | `workspace-freshness/SKILL.md`「用途」段（L15）；其节点（`…0016`/`…0017`）本 CR 不删 |
| 3 | 四个 `approve-*` → `crctl approve` | 只读本地 | `approveAndAdvance` 的输入面 = `approval.yml` + `review-annotations/*` + `gates.json`；`release-subjects` 复核走 `verifyReleaseSubjects`（注释明写「不 fetch、不读 remote-tracking ref」） |
| 4 | `review-record` | 只读本地 | `buildReleaseSubjects` 注释「CR-2026-044 FR-02：snapshot 只绑定本地事实，不 fetch、不读 remote-tracking ref」；要求 workspace `healthy` |
| 5 | `writeback-apply` | 只读本地 | 消费 txws 内的 approval/release-subjects（`verifyReleaseSubjects`）与 traceability journal，不做 trunk 相等性校验 |
| 6 | `cr-archive` | **部分依赖远端**（如实登记） | 归档本身必须 push 终态 commit；rejected/withdrawn 路径有 `git fetch origin`（L3616 区域）；本 CR **新增**的尾部 `reconcileLocalTrunks` 亦 fetch。**但归档不是 gate**：它不参与「审批能否完成」「评审能否完成」的判定，不改变 FR-6 的取舍 |
| 7 | `gates.json` | 只读本地 | 声明式文件 + `passCondition` 由 pipeline JSON/annotation 求值 |
| 8 | 唯一远端相等要求 = `merge` 的 publication preflight | 成立 | `mergeCr` L1587-1606：`MERGE_SOURCE_MISSING`/`RELEASE_REMOTE_NOT_PUSHED` 是唯一「远端 requirement ref == 本地 HEAD」判定，且携 `recovery`（checkpoint argv） |

⇒ PRD §1.4 事实 22 的残留面（「未逐条重跑」）**关闭**：唯一依赖远端的是归档（非 gate）与 merge 的 publication preflight（已由 FR-6 兜底）。本表引用的 `workspace-freshness/SKILL.md`、`approveAndAdvance`、`applyWriteback` 三项已按 B-2 回修补登 §6.3（末三项）。

## SDD-CLOSE-03 S-7：第五份权限面副本的收口（纳入 vs 排除）

**结论：排除，理由见 D-6**，并按 AC-9/交付说明登记 `follow_up` 第一项。收口证据链（三段，缺一不算关闭）：① 无消费者——`grep -rn "cr-prompts-revised"` 在 `*.ts/*.tsx/*.mjs/*.js/*.go/*.md` 面内只命中 `CUSTOM.md`；② 治理定性——`CUSTOM.md#75`：公共 Prompt 唯一事实源为 `tools/agents/`、目录内副本「不再独立演进」、分叉时「以 tools 为准并人工对齐」；③ 范围已冻结——PRD §1.3.1 第 14 行注记明写「不改 `cr-prompts-revised/agent-skill-matrix.yml` 部署副本」。FR-8 的「不得在同一份合同下留第二种读法」由「四处载体同步 + 断言 A/B」覆盖**运行时有效面**，第五份快照由上述人工对齐机制承担。

## SDD-CLOSE-04 S-8：AC-4②③④ 的可定位落点

**结论：逐项点名完成。**

| 项 | 结论 |
|---|---|
| 承载断言的文件 | AC-4②③ 的 tools 侧断言 → `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（单一新断言内同时校验四处载体中的 tools 三处 + 四个 review SKILL 前置）；FR-7 的静态文本断言 → `skills/shared/crctl/scripts/test/contract-scan.test.mjs`（S-3 指定）；AC-4④ → 同 `pipeline-structure.test.mjs`（读 `AGENT-SKILL-MATRIX.md` 的 `## 本 CR 权限变更` 节并断言本 CR 行含 `CR-2026-066` 与 `workspace inspect`） |
| 副本内小节名 | tools：`## 权限事实源`（**不是**「受限 crctl 权限块」——该块在 tools 侧实测不存在）；multica：`## 受限 crctl 权限`（第 35–46 行，允许项 L39–L42、禁止面枚举 L46） |
| 变更行按 CR 编号区分 | `AGENT-SKILL-MATRIX.md` 的 `## 本 CR 权限变更` 节现存数据行（L52）是既有 CR 的行；本 CR 追加行必须显式带 `CR-2026-066`，断言按该编号定位，不与既有行混同 |

## SDD-CLOSE-05 FR-8 的平台部署时序

**结论：登记完成。** 本 CR 只改仓库内文本（tools 三处载体 + multica 1 份副本的 `## 受限 crctl 权限` 节）；平台把 `push-progress` 绑定给 `quality-reviewer-agent`、Prompt 投影与 `gate_nodes_gen.go` 重生成均为 owner 部署动作（PRD §1.3.2 明写部署不在本 CR 范围）。部署前 Multica 侧运行的仍是**旧白名单**（不含 `workspace inspect`）：因此部署窗口必须与本 CR 的 tools 侧改动**成对生效**，否则 FR-2 前置在平台上仍会被旧合同误判（该风险由部署说明与 `follow_up` 登记，不在本 CR 代码面内消除）。

# 9. 批准范围

## scope_in（当前 CR 必须交付的 FR/AC）

- **FR-1~FR-11 全部**，按 §6.1 的落点表；AC-1~AC-10 全部按 §6.2 的映射验收。
- **文件面（29 个交付文件）**：`../tools` 25 个（§1.2 树；含 PRD §1.3.1 第 13 行两个测试文件，外加被 FR-4/FR-5 直接证伪而必须同批改写的 `crctl.test.mjs`、`checkpoint-tx.test.mjs`，以及 S-3 指定的 `contract-scan.test.mjs`——后三者的改写属「既有断言按新事实同步」（AC-2）与「CI 全绿不得签例外」（NFR-1/AC-5），不新增扫描面、不新增断言维度）；`../multica` 4 个 Prompt 部署副本。
- **KB 仓**：本 SDD（`change-requests/CR-2026-066/sdd.md`）与状态/评审记录；不改 KB 的 `specs/`、`delivery/`、`docs/`。
- 交付说明必须包含：AC-6 延期验证点登记块（§6.6）、FR-11 受影响映射与二选一登记（§6.7）、FR-6 取舍（审批提交在下一阶段评审前只在本地、换机需重签一次）、D-6 的 S-7 排除理由、SDD-CLOSE-05 的部署时序说明、**AC-4②③ 的断言 B 核对结论**（被核文件 `../multica/cr-prompts-revised/quality-reviewer-agent.md` 的 `## 受限 crctl 权限` 节，与命中的 token：允许面 `workspace inspect`、禁止面 `checkpoint`）。

## scope_out（明确排除的路径和能力）

- 不引入平台执行层（Runner / approval-continuation / 平台 API）做 checkpoint；不做「审批后可选 checkpoint」节点（不以 `onFail: skip` + 输入端开关变相恢复）。
- 不新增 pipeline 节点、评审维度、账本字段、观测指标（SLO/计数门禁）、crctl 子命令、错误码、Skill 参数、落盘文件。
- 不改 crctl 事务层、状态机、`reviewLoop` 语义（唯一例外：`review-code.reviewLoop.replayNodes` 删除 `…0008` 一项，5→4）。
- 不改 `merge`/`archive`/`writeback` 的业务算法；不改 `recovery` 合同（一切新文本使用结构化 `recovery`）；不复活 `recoverCommand`/`recover_command`。
- 不改 `../multica/cr-prompts-revised/agent-skill-matrix.yml`（S-7）、`../multica/CUSTOM.md`、`aifirst/**`、任何 Go/TS 代码、平台 DB；不重生成 `gate_nodes_gen.go`；不改 `emit-registry.mjs` 与 registry schema。
- 不新增委派 lint 规则或新扫描面；不在 tools 测试内新增跨仓（`../multica`）条件断言。
- 不触碰 `cr-prompts-revised/` 之外的 multica 目录；不改四个 review SKILL 的 Step 2.x 区块（归 CR-P1）、`quality-reviewer-agent#评审判断`（归 CR-P1）、code pipeline 的 dev-start 提示与 `review-dev-plan` 的 acceptance-verifiability 面（归 CR-P2）。

## zero_diff（明确不得改动的调用点/签名）

| 对象 | 零 diff 约束 |
|---|---|
| `crctl.mjs` | 全文件零 diff（不改 dispatch、不改 `cmdArchive`/`cmdCheckpoint`/`advance`/`gate`/`review-record`） |
| `skills/shared/controlled-shell/rules.json` | 零 diff（`git[]` 白名单与 `protectedPaths.deny` 都不动） |
| `dir-graph.yaml#change-request-track.state_machine` / `skills/shared/crctl/gates.json` | 零 diff（不新增状态、转移、门禁） |
| `checkpointCr` / `mergeCr` / `applyWriteback` / `registerCr` 的函数签名与内部逻辑 | 零 diff（FR-10 只加 `reconcileLocalTrunks` 的第二个调用点与 `archiveCr` 的返回字段） |
| `reconcileLocalTrunks(ctx)` 函数体 | 零 diff（不改判据、不改分类、不改行形状）；AC-8④ 的断言据此为 **argv 级**——函数体含 `rows.push(row)` 与 argv 数组形态的 git 命令，文本级子串判据在本行约束下恒假，不得使用 |
| `archiveCr` 既有返回字段与 `phase` 分类、`crctl archive` 退出码 | 零 diff |
| `recovery` 结构化合同字段名（`executable`/`args`/`cwd`/`requiresTTY`/`promptFor`） | 零 diff |
| `emit-registry.mjs`、`gate_nodes_gen.go`、`gate-registry.json` | 零 diff（只登记契约变化） |
| 四个 review SKILL 的参数表 / payload 结构 / 评审维度 / `passCondition` | 零 diff |
| `agent-skill-matrix.yml` 其它 actor 的 `owns`/`can-call`/`forbidden` | 零 diff（只改 `quality-reviewer-agent` 的 `can-call`/`forbidden` 与块注释） |
| KB `specs/`、`delivery/`、`docs/`（含主 checkout 既有 `docs/analysis/` 未提交变动） | 零 diff |
| `change-requests/CR-2026-066/prd.md` | 零 diff（已审批冻结，`sha256(LF)` = `9b43bbfa…`；改哈希即作废人工审批） |

## follow_up（发现但留给后续 CR / owner 的缺口）

1. **S-7 第五份权限面副本的部署窗口对齐**：`../multica/cr-prompts-revised/agent-skill-matrix.yml` L192-194 仍含旧注释（未含 `workspace inspect`）；按 `CUSTOM.md#75` 的「以 tools 为准人工对齐」机制在下一次部署/rebase 核对时处理（本 CR 不改）。
2. **`node-N.md` 命名不一致**：code `…0014`（review-dev-plan）写 `node-3.md`，与其余节点「`node-N.md` 的 N = 节点 id 末段」的惯例不一致（删除 `…0003` 后它成为 `node-3.md` 的唯一写入者，撞名随之消失）。建议后续 CR 统一为 `node-14.md`。
3. **多个 prompt 的 `node-N.md` 历史错位**（例如 code `…0009` 位于下标 11 却写 `node-9.md`）：本 CR 不改名以避免与 CR-P1/P2 的面重叠，登记待后续统一。
4. **四个 review SKILL 的「调用时机」节点序号**（如 `review-code` 写「第 8 节点」而实际位置为第 12 节点、删除后为第 10 节点）：已属本 CR 之前的历史漂移；本 CR 只改其中的 checkpoint 前提句，序号留给后续 CR（或改为不写死序号的措辞）。
5. **`gate_nodes_gen.go` 与 registry digest 的重生成**（§6.7）：owner 部署窗口执行；在此之前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用。
6. **KB `docs/analysis/done/` 的历史分析文档**（如 `tools-local-worktree-gates-remote-publication-boundary.md` 的「阶段终点 checkpoint 是完成合同」段）仍描述审批后阶段终点 checkpoint：属 CR-2026-044 当时的分析产物（`done/`），本 CR 不改写历史分析；如需标注「已被 CR-2026-066 取代」，另起文档 CR。
7. **CR-2026-065 之后的新口径复核（NFR-5 延伸）**：`assertion-sources.mjs` 尚未提供「函数体文本／argv 抽取」派生化 helper，本 CR 的 AC-8④ 在 `archive-tx.test.mjs` 内就地抽取 argv + 硬失败；若后续再有同类断言，可考虑上移为 `assertion-sources.mjs` 的派生函数（本 CR 不新增该 helper 以避免扩大测试支持面）。
8. **AC-6 演练载体的注册**：本 CR 交付后新注册的小体量演练 CR（首选）或 CR-P1 首链（次选）——由协调者按节奏排定。

---

## 修订记录

- 初稿（2026-09-14）：按 PRD（`a7cbd947`，`sha256(LF)` `9b43bbfa…`）与来源附件起草；基线事实在 tools@`5d5a4ada`、multica@`43848770`、KB worktree@`3a553e3b` 三个 HEAD 上逐条核实（初稿为「既有实现依赖与事实」36 项，B-2 回修后 43 项）。三条对 PRD 的技术性细化落点：① FR-3 的 KB 取证链（D-4，基于 checkpoint 的 `kbSourceSha`/metadata-staged-set 合同）；② FR-1 的发布前置复用 `crctl workspace inspect`（不引入裸 `git status`，保持评审者能力面不扩张）；③ FR-4/FR-5 的连带面（`node-N.md` 判定、`node-3.md` 悬空引用核查、四个测试文件的既有断言改写清单）。SDD-CLOSE-01~05 关闭 PRD 与需求评审转交的 5 项延后事项。
- 回修 0.2（2026-09-14，`review-tech-design` cycle 1 / attempt 1 BLOCK → 按 `repair-target=write-tech-design` 回修）：**B-1** 把 AC-8④ 由「函数体文本级子串断言」重定义为 **argv 级命令面白名单**（§6.2 AC-8 行 ④＋可达性、§6.4 `archive-tx.test.mjs` 行、§7.1、§9 zero_diff 同步）——原判据在 §9 明令零 diff 的函数体上恒假（`rows.push(row)` 含 `push`；git 命令为 argv 数组、无字面 `merge --ff-only`）；**B-2** 在 §6.3 补登 4 项正文同类既有事实（`ARCHITECTURE.md`、`skills/shared/crctl/gates.json`、`merge-feature-branch/SKILL.md`、`cr-archive/SKILL.md`），并按「补进清单」处理 SDD-CLOSE-02 引用的 3 项（`workspace-freshness/SKILL.md`、`approveAndAdvance`、`applyWriteback`），清单 36 → 43 项；同批采纳 S-1~S-6（§4.7 三份 tools Prompt、§3.4 CONTRACT_DRIFT 表述、§6.3 PRD 349 行口径、§9 交付说明补断言 B 结论、三处行号精度、§4.2 `healthy ⇒ dirty=false`）。基线事实仍为 tools@`5d5a4ada`、multica@`43848770`；PRD 零触碰（`sha256(LF)` `9b43bbfa…`）。
