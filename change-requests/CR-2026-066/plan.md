---
id: CR-2026-066-plan
type: PLAN
cr-ref: CR-2026-066
sdd-ref: "change-requests/CR-2026-066/sdd.md"
target-version: 0.39
status: draft
created: 2026-09-14T15:05:00+08:00
updated: 2026-09-14T15:05:00+08:00
---

# CR-2026-066 开发计划（CR-P3：评审 PASS 发布与 checkpoint 委派收敛 — 阶段终点发布点前移、审批后 checkpoint 节点退役、归档后本地 trunk 同步）

**权威输入（人工审批绑定，本计划不修改其一个字节）**

| 输入 | 绑定 | 摘要证据 |
|---|---|---|
| `change-requests/CR-2026-066/sdd.md`（rev 0.4，唯一权威） | `review-annotations/sdd.yml#subject-sha256`（cycle 2 / attempt 1，`verdict=pass`、`blockers=[]`）+ `approval.yml#tech-design`（`via: crctl-approve`、`2026-09-14T14:13:53+08:00`、approver `OldBoy405`、`evidence-digest ef97f12e…`、`target-status: tech-design-reviewed`） | **112,204 B / `\r` 计数 0（纯 LF）**；sha256(LF) = `78846c1bc7f17662bb8566ea71eb0ccaa11f1deec103abf3e4d42a8b649aa410`（与 `review-annotations/sdd.yml#subject-sha256` 逐字节相等，本条 run 按 worktree 实际文件复算） |
| `change-requests/CR-2026-066/prd.md` | 需求人工审批 evidence-digest（SDD §1.4 事实 3） | sha256(LF) = `9b43bbfafa3be7a82c7e86900b17f64c3e95365347c9ed8588883e8d53aef1db`（SDD 头部与 `review-annotations/requirement.yml` 同口径登记值；本计划只按 SDD 引用定位抽查，**不全量复审 PRD**，D-15） |
| `cr.md#target-version` | 注册期继承 | `0.39`（禁止 tbd / 自行改写，CR-2026-057 FR-13） |

- **硬边界一（不得触碰）**：`sdd.md` 已被 `review-annotations/sdd.yml#subject-sha256` 与 `approval.yml#tech-design#evidence-digest` **双重绑定**——改它一个字节即同时作废本轮评审与人工审批（`APPROVED_ARTIFACT_DRIFT`）。本计划与 `tasks/**` 只**重述**已审批的实施契约，不新增 SDD 正文修改；`prd.md` 同样零触碰。
- **硬边界二（范围）**：交付面 = SDD §1.2 的 **29 个文件**（tools 25 + multica 4）；`zero_diff` 面（§9）逐条不得改动；`follow_up` 8 项不得顺带实现（§8）。
- **本计划的 replay 身份**：本条 run = `code-implementation` **node-1/node-2**（`write-dev-plan` → `write-dev-tasks`）；`review-dev-plan` 由**独立 quality-reviewer-agent run** 执行（不在作者会话内自评），`reviewLoop.maxAttempts=3`、`repair-target=write-dev-plan`。
- **架构阶段收尾已在本节点首位完成**（§0.2）：架构终点 checkpoint 已发布，SDD＋评审＋审批整批已上远端。

---

## 0. 基线与工作区事实（本节点实测，落笔即读，未轮询）

### 0.1 入口状态与门禁（crctl 权威值）

| 项 | 实测 |
|---|---|
| `crctl status CR-2026-066` | `tech-design-reviewed`（`d5339ab9`，node-1 入口值）；`legalNext` = `task-breakdown`(`write-dev-tasks`) / `rejected` / `withdrawn` |
| `crctl next CR-2026-066` | **`write-dev-plan`**（`humanApproval=false`，why「技术设计已审批，编写开发计划」） |
| `gate --for tech-design-reviewed` | `pass=true`（`verdict=pass` ∧ `blockers` 空 ∧ `approval.yml#tech-design` 在册）——架构审批是唯一缺口，已补上 |
| `approval.yml#tech-design` | approver `OldBoy405`、`approved-at 2026-09-14T14:13:53+08:00`、`via: crctl-approve`、`evidence-digest ef97f12e…`、`target-status: tech-design-reviewed` |
| `review-loop.yml` | `review-requirement` cycle 1 / attempt 2；`review-tech-design` **cycle 2 / attempt 1**（cycle 1 三条 attempts 全保留） |
| `workspace inspect` | 三仓 `classification=healthy`、`dirty=false`、`localBranch/remoteBranch=true`；`operationalWorkspace` 非空 |

### 0.2 架构阶段终点 checkpoint（本节点首位执行，已发布）

```text
crctl checkpoint CR-2026-066 --message 架构设计已审批
⇒ phase=complete、changed=true、batchId=a6c98051920971b1、txId=f98839539c6d4edebfe234b1da3254c3
⇒ metadataCommit=e97c4edaceb9aa3f76681c36d0196515c25f6531
⇒ repositories[]（三仓 confirmed=true）：KB d5339ab9… / multica 43848770… / tools 5d5a4ada…
⇒ sideEffects：KB push + KB metadata commit + KB push（metadata）
```

⇒ 远端 `refs/heads/requirement/CR-2026-066` 现已含 SDD rev 0.4 ＋ 两轮评审记录 ＋ 人工审批提交整批（架构阶段终点完成条件满足，`push-progress` 节点语义结束；失败时的重跑口径 = 同一 checkpoint，不重新审批）。

### 0.3 三仓 worktree（路径 authority = `resources[].worktreePath` 原样值，不拼接、不回退主工作区）

| repo | worktreePath | 分支 | HEAD（本节点实测） | 本 CR 角色 |
|---|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-066` | `requirement/CR-2026-066` | `e97c4eda…`（checkpoint metadata commit） | 承载 prd/sdd/plan/tasks/test-report/证据；零代码 |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-066` | `requirement/CR-2026-066` | `43848770bff13465de8ed9a0e28ecc7371716514` | 4 份 Prompt 部署副本（**仅文档**，不写 Go/TS） |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-066` | `requirement/CR-2026-066` | `5d5a4ada96b882eb2c640e34bb72857a7073b668`（= 注册基线 = SDD §6.3 全部 `commit SHA` 登记值；**diff 审计基线**） | 25 个交付文件（实现主面） |

### 0.4 测试面基线实测（本节点未改任何文件，全部为「变更前事实」）

| 项 | 实测值（本条 run） |
|---|---|
| **全量套件** `node skills/shared/crctl/scripts/test/suite-gate.mjs --run` | **`verdict=pass` / `exit_code=0` / `duration_ms=785565`（786 s）/ `files_executed=21` / `cases_executed=588` / `failures=0` / `skipped_file_level=0` / `converged=true` / pool=15（availableParallelism=16）/ node v24.15.0（win32）/ `registry_sha256=f8d983a04656d1fae05588af9daa14b128872bc124e5bcddfd155088b53bd5bf` / `exceptions_count=0`** |
| CI 静态面 | `lint-prompts.mjs --mode enforce` = exit 0 / 0 findings（<1 s）；`check-skill-matrix.mjs` = exit 0（56 active skill / 8 actor，<1 s）；`check-agents-contract.mjs` = exit 0（9 agent，1 s）；`node --test skills/writeback/scripts/test/*.test.mjs` = exit 0（1 s） |
| 单文件耗时 | `pipeline-structure.test.mjs` ≈ 1 s；`contract-scan.test.mjs` ≈ 1 s；`checkpoint-tx.test.mjs` **≈ 194 s**（23 用例）；`crctl.test.mjs` 用例数 224（体量最大，见 §6.1 表注③）；`archive-tx.test.mjs` 用例数 24（CR-2026-065 实测整文件 > 150 s） |
| `gate-registry.json` | `schema=crctl-suite-gate/v1`；`manifest.files` = 21；`manifest.cases` 合计 **578**（`archive-tx` 24、`checkpoint-tx` 23、`contract-scan` 17、`crctl` 224、`pipeline-structure` 35）；`exceptions=[]`（显式空数组） |
| **基线结论** | **本 CR 的起点是全绿**（NFR-1 的「保持绿」是对既有绿的保持，不是转绿）；FR-5 的连带改写必须让上述断言在**新事实**下重新绿，且不得签任何例外（AC-5） |

### 0.5 关键断言锚点（实施定位线索；行号以实施期实时搜索为准，SDD §6.4 登记清单为准）

| 文件 | 既有断言/用例（逐字名或位置） | 本 CR 处置 |
|---|---|---|
| `pipeline-structure.test.mjs` | `AC-1: 节点序 review-code(…0009) < checkpoint(…0015) < human_approval(…0010) < approve-code(…0011)`；`AC-2: checkpoint 节点 onFail=abort、ref=push-progress；节点 id 全局唯一（CR-2026-042 后 16 节点）`；`AC-3: review-code reviewLoop.replayNodes 为 5 项，含 workspace-freshness(…0017) 重核（CR-2026-043）`；`CR-2026-044 AC-13/14: requirement-authoring 审批后强制 checkpoint（7 节点），草稿 checkpoint 仍可选`；`CR-2026-044 AC-14: architecture-design 删除 auto_push_after_sdd，审批后 checkpoint abort，5 节点不变`；`CR-2026-044 AC-13: code-implementation 审批后 checkpoint abort、TASK checkpoint 仍可选、16 节点不变`；`CR-2026-045 AC-03: emit-registry 输出 canonical registry 且 digest 稳定`；`CR-2026-050 AC-12: 8 条 Pipeline 节点数与 UUID 全局唯一保持不变` | 按 SDD §6.4 逐条改写/删除/新增（TASK-01、TASK-02） |
| `crctl.test.mjs` | `CR-2026-042 静态合同：code Pipeline 16 节点、无 review_llm、无 …0013、后继与 replayNodes`（L5036 `inputs` 含 `auto_push_after_task`、L5038 `ids.length === 16`、L5040 `…0017` 直接前驱 `…0009`） | 改写（TASK-01）；**L5040 的相邻关系在删除后仍成立**，保留 |
| `checkpoint-tx.test.mjs` | **L487 起、`filter(...)` 在 L491、整条 test 止于 L506**（`checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints[]`）；L495-506 是 review-alignment 事实源断言 | **只改 L491 的 `filter` 形态 → 显式枚举**，L495-506 逐字保留（S-14；TASK-01） |
| `contract-scan.test.mjs` | replayNodes 结构快照（L81-98，含 `push-progress`）；`RETIRED_RECOVERY = ['recoverCommand','recover_command']` 整树扫描（L418-425 区域） | 快照改 4 项（TASK-01）；新增 FR-7 静态文本断言（TASK-04） |
| `archive-tx.test.mjs` | 既有 fixture `makeWritebackFixture`（L17）、`makeNewModeArchiveFixture`（L86）；文件 783 行 | 新增 AC-8 六项用例（TASK-03），**复用既有 fixture、不新建夹具** |
| 四个 review SKILL | `review-requirement` L10「第 4 节点（push-progress 之后）」；`review-dev-plan` L9「write-dev-tasks 之后、push-progress 之前」；`review-code` L10「第 8 节点（代码编写与统一 checkpoint 后）」＋ L16「在开发者完成编码并推送统一 checkpoint 后…」 | 三处旧前提句改写（S-13；TASK-02） |

### 0.6 附带项事实源（S-12/S-13/S-14 与 multica 落点）

- `review-annotations/sdd.yml#suggestions` 的第 4/5/6 条即 S-12/S-13/S-14（全文见 canonical 记录；处置见本计划 §8）。
- multica `cr-prompts-revised/quality-reviewer-agent.md`：`## 受限 crctl 权限` 节（L35 起）为**穷尽式白名单**，四条允许项 L39-42 **不含** `workspace inspect`，禁止面枚举含 `checkpoint`；另有 L54「本 Agent 不负责 push/checkpoint，后续发布由 Pipeline 中对应的同步节点完成」（与 FR-1 直接冲突，必须原位改写）。
- multica `cr-prompts-revised/dev-agent.md` L23「代码评审：先有代码、测试报告和统一 checkpoint，再由独立 reviewer 调用 `review-code`」、L41「评审 blocker 未清空、测试报告未 pass 或 checkpoint 未完成时，不进入后续人工审批」（FR-7 的两个原位改写句）。
- multica `cr-prompts-revised/delivery-agent.md` L27「本 Agent 只传业务输入、消费结构化结果和解释错误，不裸调 crctl 原语、不跨节点补跳」（recovery 例外要在本句上开洞）；`## 汇报与完成标准` 节为归档终态汇报面（L44 原文只有「归档返回 `complete` 或 Skill 明确的完成态」，全文件 `cleanup-pending` / `localTrunkSync` **零命中**）。
- multica `cr-prompts-revised/cr-coordinator-agent.md` L19/L60：`crctl` 仅只读 `status`/`next`，禁止 `advance`/`approve`/`checkpoint` 等写入型子命令（门后节点只能被单独委派的直接原因；本 CR 增加「不得为 checkpoint 单开委派」显式禁止）。
- 四份 multica 副本当前**不含**「已部署」类部署声称（本节点实测 `grep` 零命中）⇒ 交付不得引入部署声称（AC-9/D-6 边界）。

---

## 1. 交付里程碑

| # | 阶段 | 内容 | 产出 | 估算 | 状态 |
|---|---|---|---|---|---|
| M1 | 需求与架构（已完成） | 注册 → PRD → 评审 → 人工审批 → SDD → 两轮 cycle 评审 → 人工架构审批 → 架构终点 checkpoint | `prd.md`、`sdd.md`（rev 0.4）、`approval.yml#tech-design`、批次 `a6c98051…` | — | **done** |
| M2 | 开发计划与拆分（本节点） | `write-dev-plan` → `write-dev-tasks` → 独立 `review-dev-plan` | `plan.md`、`tasks/TASK-01..04.md`、`tasks/_index.yml`、`status=task-breakdown` | 本条 run | **本条 run（评审由独立 reviewer run 执行）** |
| M3 | 实现 | TASK-01 → TASK-02 → TASK-03 → TASK-04（依赖序，见 §2） | tools 25 文件 ＋ multica 4 文件的 diff；4 个 TASK 在 `tasks/_index.yml` 标 `done` | **88 h（≈ 11 人天）** | pending |
| M4 | 测试 | `write-test-report`（`crctl test --plan`，7 条证据命令） | `test-report.md` ＋ `test-evidence/cmd-01…07.log` | 见 §5.4 预算 | pending |
| M5 | 代码评审与审批 | 独立 `review-code` → 人工 `approve-code` | `review-annotations/code.yml`、`approval.yml#code` | — | pending |
| M6 | 交付说明与登记 | 交付说明必填块（§10）：AC-6 延期验证点、FR-11 映射与二选一登记、D-6 排除理由、部署时序、断言 B 结论 | 交付评论/`test-report.md` 分析段 | — | pending |

**估算口径**：四张 TASK 卡 frontmatter 的 `estimate` 之和 = **88 h**（24 + 24 + 16 + 24）；与 `crctl task init CR-2026-066 --count-hint 4` 返回的 `totalEstimateHours` 必须相等（不等时按 `write-dev-tasks` Step 4 输出 WARN，不静默覆盖）。

---

## 2. 任务依赖图

```text
TASK-01（pipeline 节点退役与测试面连带闭合；FR-4/FR-5）
   │  改：3 份 pipeline JSON、_index.yml、四个既有测试文件
   ├──────────────────────────────► TASK-02（评审 PASS 发布、clean 前置与权限面；FR-1/FR-2/FR-3/FR-8）
   │                                  改：四个 review SKILL、矩阵、派生表、两份 quality-reviewer Prompt、
   │                                      并在 pipeline-structure.test.mjs 追加断言块
   │                                       │
   │                                       │（同文件串行：TASK-01 先改既有断言，TASK-02 再追加新断言）
   │                                       ▼
TASK-03（归档尾部 trunk 同步；FR-10）  TASK-04（口径改写、搭车硬规则与登记收口；FR-6/FR-7/FR-9/FR-11）
   │  改：workspace-transactions.mjs       改：push-progress SKILL、merge SKILL、README、openwiki、
   │      cr-archive SKILL、archive-tx           dir-graph、三份 tools Agent Prompt、三份 multica 副本、
   │                                            contract-scan.test.mjs 追加静态断言
   └──────────────────────────────────────────►  │
                                                 ▼
                                    （TASK-04 依赖 TASK-01/02/03：它消费前三个 TASK 的最终文本与实现事实）
```

- **依赖序固定为 `TASK-01 → TASK-02 → {TASK-03 并行} → TASK-04`**：`pipeline-structure.test.mjs` 由 TASK-01（改写既有断言）与 TASK-02（追加 AC-3/AC-4 断言）**共用**；`contract-scan.test.mjs` 由 TASK-01（replayNodes 快照）与 TASK-04（FR-7 静态断言）**共用**；Agent Prompt 三件中 `agents/quality-reviewer-agent.md` 由 TASK-02（权限事实源节）与 TASK-04（搭车规则/发布职责句）**共用**，multica 的 `quality-reviewer-agent.md` 同理。共享文件的写入者一律按上表串行，**不存在两个 TASK 并发改同一文件**。
- **无环、无悬空**：`depends-on` 只引用本 CR 的 canonical id（§9 表）；TASK-03 的 `depends-on: []` 表示它只依赖 `tools@5d5a4ada` 基线与 TASK-01/02 无关（归档面与 pipeline 面零耦合，SDD-CLOSE-01 判据④）。
- **回滚单元**（§4.0）与依赖图逆序一致：RU4 ⊂ RU1∪RU2∪RU3。

---

## 3. 资源与分工

| 角色 | 责任 | 本 CR 范围 |
|---|---|---|
| `owners.development` = **Ray** | 技术设计、实现 4 个 TASK、开发相关审批 | tools 25 文件 ＋ multica 4 文件全部 diff |
| `owners.test` = **Ray** | `write-test-report` 的真实证据（7 条证据命令、`sourceRevision` 绑定） | `test-report.md`、`test-evidence/cmd-01…07.log` |
| `owners.requirement` = **Ray** | 已闭合（PRD 冻结） | 零动作 |
| 独立评审方 | `review-tech-design` / `review-dev-plan` / `review-code` 一律由**新建 quality-reviewer-agent task** 执行 | 作者不自评 |

- 三条 worktree 均为单写者（`requirement/CR-2026-066` 分支）；**不与其他 CR 并发**（AC-10③：在途仅本 CR，063/064/065 均 `archived`）。
- 实施期不启停任何数据库/消息队列/共享服务；本 CR 不部署平台 Prompt、不重生成 `gate_nodes_gen.go`、不启用 Runner（§10）。

---

## 4. 风险与回滚策略

### 4.0 回滚单元（逆拓扑组合，唯一事实）

| 单元 | 覆盖 | 回滚方式 | 语义 |
|---|---|---|---|
| **RU1** | TASK-01 全部（3 份 pipeline JSON、`_index.yml`、`pipeline-structure`/`crctl`/`checkpoint-tx`/`contract-scan` 的连带改写） | revert TASK-01 的提交 | 节点退役与测试面原子回退（FR-4/FR-5 互为补充，**不可只回一半**：节点删了而断言没回会红） |
| **RU2** | TASK-02 全部（四个 review SKILL、矩阵、派生表、两份 quality-reviewer Prompt、pipeline-structure 的 AC-3/AC-4 断言） | revert TASK-02 的提交 | 发布点回退到「审批后节点」（须同时具备 RU1 的节点，故 RU2 回滚必须与 RU1 同批复原） |
| **RU3** | TASK-03 全部（`archiveCr` 局部包装与 `localTrunkSync`、`cr-archive/SKILL.md`、`archive-tx.test.mjs`） | revert TASK-03 的提交 | **完全独立**（SDD-CLOSE-01 判据④），不影响其它 FR |
| **RU4** | TASK-04 全部（口径四处、搭车硬规则与四份 Prompt 副本、`contract-scan` 静态断言、交付登记块） | revert TASK-04 的提交 | 纯文本与登记面回退；不影响实现唯一性 |

**回滚边界（SDD §9 承接）**：FR-1~FR-3（评审发布）与 FR-4~FR-5（节点退役）互为补充但**可分别按 RU 组合回退**；FR-10 完全独立（RU3）；FR-9/FR-11 只改文本与登记，回退即还原。**实现→评审窗口不再有中途恢复点**（取舍一）与**审批提交在下一阶段评审前只在本地、换机需重签一次**（取舍二）是设计取舍，回滚不改变它们。

### 4.1 风险表

| # | 风险 | 影响 | 缓解（本计划的机器判据/纪律） |
|---|---|---|---|
| R-1 | 删节点后**遗留悬空引用**（`node-N.md` 读取已删节点输出、`replayNodes` 指向已删 id） | CI 红 / 运行时错 | SDD §4.4.2-4 的零命中核查已实测；`cmd-05` 的 pipeline JSON 结构断言逐节点校验 `repairNodeId`/`replayNodes` 目标存在；`cmd-01` 全套件 |
| R-2 | 测试面改写**漏改一条**既有断言（§6.4 共 14 处） | CI 红（AC-5 不得签例外） | `cmd-01` 全量套件 + `cmd-03` 定点用例；TASK-01 的完成标志要求 §6.4 逐行核对表 |
| R-3 | `checkpoint-tx` 的 `filter` 形态改写成**会随删除退化为空集**的形式 | 负向断言静默失效（假绿） | TASK-01 明确：改为**显式枚举**剩余节点集合并断言该枚举非空；`cmd-03` 定点跑该用例 |
| R-4 | 归档三返回点只改了一半（`cleanup-pending` 分支漏 `localTrunkSync`） | AC-8① 红 | `archive-tx` 六项用例逐个覆盖三个成功返回点（`cmd-04`） |
| R-5 | `reconcileLocalTrunks` 函数体被顺带改动（违反 `zero_diff`） | 违反批准范围，AC-10① 红 | `cmd-05` 的 hunk 级禁改 token 断言（`function reconcileLocalTrunks` / 其它 `function …`）＋ `cmd-01` 的 AC-8④ argv 断言 |
| R-6 | 权限面**只改 SKILL 不改允许面**（B-1 的旧形态） | 同一合同两种读法 | `cmd-02`（tools 三处载体 + 四 SKILL 前置**同一条**断言）＋ `cmd-06`（multica 副本白名单）＋ `cmd-05`（`check-skill-matrix`/`lint-prompts`） |
| R-7 | 新增文本触发 `lint-prompts --mode enforce`（裸 git 写命令 R2 / 手写状态映射 R9 / 退役字段名 R11-R10） | CI 红 | `cmd-05` 的 CI 静态五步逐条实跑；TASK 卡写明避让约束（§7.1） |
| R-8 | 证据命令超 `write-test-report` 节点预算（20 min） | 测试节点失败 | §5.4 预算：实测 786 s（cmd-01）＋ 其余 ≤ 180 s，合计 ≤ 966 s < 1200 s；命令顺序把最贵的 cmd-01 排第一。**已知环境抖动**：本节点四次运行中有一次 `writeback` 子进程崩溃（§6.3），处置为按同一命令重跑（只读、幂等），不改预算口径 |
| R-9 | 平台生成物（`gate_nodes_gen.go` Seq / registry digest）被无声忽略 | 部署漂移 | AC-9 登记块（`cmd-07` 机械核对「未重生成 ⇒ Runner 保持禁用」分支存在）；部署由 owner 在部署窗口执行（本 CR 不重生成） |
| R-10 | multica 侧改动越界（写了 Go/TS 或第 5 个文件） | 违反 NFR-6 / SDD-CLOSE-03 | `cmd-06` 的 multica diff 白名单（恰 4 份 `cr-prompts-revised/*.md`） |
| R-11 | 实施期发现 SDD 不可实施 | 阻断 | 出口 = 状态机既有边 `review-dev-plan:upstream-design-blocker`（`task-breakdown → tech-design-review-pending`）；**不得就地放宽** SDD 或 `zero_diff` |

---

## 5. 验收与发布策略

### 5.1 发布前 checklist（全部机器可判或逐行可核）

1. `crctl status CR-2026-066` = `developing`，`tasks/_index.yml` 四张卡全部 `done`（带 `done-at`）。
2. tools diff **恰为** SDD §1.2 的 25 个文件（双向相等）；multica diff **恰为** 4 个 Prompt 副本（`cmd-05` / `cmd-06`）。
3. `cmd-01` 全量套件 `verdict=pass` / `failures=0` / `files_executed=21` / `skipped_file_level=0` / **`cases_executed ≥ 594`**（588 基线 + 6 条 AC-8 用例）；`cmd-02`/`cmd-03`/`cmd-04` 各自 exit 0，且 `cmd-04` 与 `cmd-05` 的 AC-8 存在性数值（命中用例数 ≥ 6）同批一致。
4. `cmd-05` 的 CI 静态五步全绿 + `zero_diff` 文件不在改动集合（`crctl.mjs`、`rules.json`、`gates.json`、`gate-registry.json`、`emit-registry.mjs`、`yaml-subset.mjs`、`durable-tx.mjs`、`ARCHITECTURE.md`）。
5. `cmd-06`/`cmd-07` 的跨仓与登记面审计 exit 0（含「无部署声称」反向断言）。
6. `sourceRevision` 绑定：`cmd-01…04` 的 `repo=tools`、`cmd-06` 的 `repo=multica`、`cmd-07` 的 `repo=ai-first-platform-docs`，与各自 worktree HEAD 一致（由 `crctl test` 发布，本计划不重算）。
7. **不得签任何新例外**（AC-5）：`suite-gate` 的 `exceptions` 保持显式空数组；`gate-registry.json` 零 diff。

### 5.2 发布与观测

- **本 CR 自身的发布点**（不依赖 FR-1 的落地）：`review-dev-plan` PASS 之后的 `push-progress`（`message=计划与任务`）由 dev-agent 执行；代码阶段的发布按现状由 `code-implementation` 的既有 checkpoint 节点承担（本 CR 落地前它们仍存在）。
- **交付后观测**（AC-6 延期验证点，本 CR 交付时**不可能**产出证据 ⇒ 登记即达成）：见 §10 的登记块；关闭触发 = 载体归档或该链路首次走完。
- 不新增观测指标 / SLO / 计数门禁（NFR-4）。

### 5.3 例外治理与零例外口径

- `suite-gate` 的 `exceptions` 是本 CR 唯一例外登记处；交付态必须为**显式空数组**（`cmd-01` 的 `exceptions_count=0` + `cmd-05` 的 registry 零 diff 双向保证）。
- 失败向量一律就地修（不回改被断言文件、不降级为下界）；跨行解析失败**硬失败**（工程纪律 #1）。

### 5.4 预算（证据命令集）

`write-test-report` 节点 `timeoutMinutes=20`（1200 s）。预算表（实测/估算，按 §6.2 顺序执行）：

| 证据ID | 预算（实测或估算） | 依据 |
|---|---|---|
| cmd-01 | **786 s**（实测，`duration_ms=785565`） | §0.4 基线实测，全量 21 文件 / 588 用例 / pool=15 |
| cmd-02 | ≈ 2 s（实测 1 s + 1 s） | §0.4 单文件耗时 |
| cmd-03 | < 5 s（实测 0 s + 0 s，定点用例为纯静态断言） | 本条 run 实测 |
| cmd-04 | ≤ 120 s（估算：既有 24 用例 > 150 s 摊到 6 条新增用例） | §0.4 + SDD §6.4 |
| cmd-05 | ≤ 60 s（估算：静态五步实测 < 1 s×4 + writeback 1 s + diff 读取） | §0.4 |
| cmd-06 | ≤ 10 s（估算：4 文件读取 + 一次 diff） | 结构同上 |
| cmd-07 | ≤ 10 s（估算：1 文件读取 + 一次 diff） | 结构同上 |
| **合计** | **≤ 966 s**（< 1200 s，余量 ≥ 234 s） | — |

**顺序策略**：cmd-01（最贵）排第一——它同时是 AC-5 与 FR-4/FR-5 回归的主证据；其余六条都在秒级，任一条红都不影响 cmd-01 的日志已落盘。

---

## 6. 两张稳定表（契约必填节，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 评审 PASS 发布（AC-3） | §4.1 发布序列（步骤 3 按 stage 分派）＋ §3.1 四 SKILL 合同（PASS 分支一次 `push-progress`，`message=<阶段>评审通过`，四字段透传，BLOCK 不发布） | CR-2026-066-TASK-02（关联 CR-2026-066-TASK-01） | cmd-02（四 SKILL 发布 token 断言）、cmd-01（全套件不回归） | RU2（须与 RU1 同批） |
| FR-2 评审前置干净检查（AC-3、AC-4） | §4.2 前置算法（Step 1 起始、`crctl workspace inspect`、`classification=healthy`、不代提交）＋ §3.3 四处载体 | CR-2026-066-TASK-02 | cmd-02（断言 A：tools 三处载体 + 四 SKILL 前置同一断言）、cmd-06（断言 B：multica 副本）、cmd-05（`check-skill-matrix`/`lint-prompts` 绿） | RU2 |
| FR-3 发布与评审对象对账（AC-3） | §4.3 取证链（KB/非 KB 分解）＋逐阶段判据（`subject-sha256` / composite / `release-subjects`）＋ `CONTRACT_DRIFT` 失败语义（不改 verdict） | CR-2026-066-TASK-02 | cmd-02（`CONTRACT_DRIFT` 与「不改 verdict」token 断言）、cmd-04（`RETIRED_RECOVERY` 零命中） | RU2 |
| FR-4 审批后 checkpoint 节点退役（AC-1） | §4.4.1 删除表（`…0007`/`…0005`/`…0012` 对象级删除，不重编号、不新增替代节点） | CR-2026-066-TASK-01 | cmd-02（节点数 5/4/12 + 无门后 push-progress + 被删 id 零出现）、cmd-03（连带既有断言） | RU1 |
| FR-5 冗余 checkpoint 节点退役与连带面（AC-1、AC-2） | §4.4.1（`…0003`×2、`…0008`、`…0015` ＋ 输入 `auto_push_*`）＋ §4.4.2 连带面 1-6（`_index.yml`、replayNodes 5→4、`approvalPrompt` 前提句、四个测试文件） | CR-2026-066-TASK-01 | cmd-02（`ref=push-progress` 计数 0 + `_index.yml` ≡ JSON + 12 节点 + inputs）、cmd-03（`CR-2026-042 静态合同` / `checkpoint T05 contract` 定点） | RU1 |
| FR-6 审批后发布由搭车承担（AC-6） | §4.5（code 路径同 run 内执行 `recovery` 一次后重跑 merge；审批搭车；禁止单开委派） | CR-2026-066-TASK-04 | cmd-02（`contract-scan` 的 FR-7 静态文本断言）、cmd-06（四副本硬规则） | RU4 |
| FR-7 搭车规则写入 Agent 委派合同（AC-6） | §4.7 落点表（tools 三份 Prompt ＋ multica 四份副本）＋ §4.5 的 delivery 双向边界（recovery 例外不赋予独立发起 checkpoint 的权力） | CR-2026-066-TASK-04（关联 CR-2026-066-TASK-02：`quality-reviewer-agent` 的发布职责句与权限块同文件） | cmd-02（tools 三份 Prompt 均含硬规则 token）、cmd-06（四副本硬规则 + delivery `同 run`） | RU4 |
| FR-8 评审者的发布职责与权限（AC-4） | §3.3 权限契约（`forbidden` 去 `push-progress`、`can-call` 加 `push-progress`、只读 `workspace inspect` 入允许面、`checkpoint` 仍在 `forbidden`） | CR-2026-066-TASK-02 | cmd-02（`can-call`/`forbidden` 断言 + 派生表本 CR 行）、cmd-06（副本白名单）、cmd-05（三脚本绿） | RU2 |
| FR-9 FR-07 口径重写（AC-7） | §6.5 四处同口径 ＋ 两处连带（`/coding` mermaid 的 `D8`/`D12` 删除、replayNodes 例） | CR-2026-066-TASK-04 | cmd-05（四处口径正/负 token 断言 + `dir-graph` contract 第 5 条改写） | RU4 |
| FR-10 归档后本地各仓与 origin 一致（AC-8） | §4.6 算法（三个成功返回点改经局部包装、`localTrunkSync` 与 `recovery` 同级、best-effort、幂等按当次实况） | CR-2026-066-TASK-03（关联 CR-2026-066-TASK-04：delivery 汇报面） | cmd-04（AC-8 用例）、cmd-01（全套件 + argv 面断言）、cmd-06（delivery 汇报面的 multica 半） | RU3 |
| FR-11 平台生成物登记（AC-9） | §6.7 受影响映射清单（`gate_nodes_gen.go` 的 `NodeID`/`Seq` ＋ registry digest）＋二选一登记 | CR-2026-066-TASK-04 | cmd-07（登记块含 `AIFIRST_ARCHITECTURE_RUNNER` 与 `未重生成` 分支） | RU4 |

**表注（防假绿）**

① 「验收证据」列按「主责命令在前」列出覆盖本行验收面的 `cmd-NN`；每个 `cmd-NN` 与 §6.2 证据命令表的 `证据ID`、`crctl test` 机器区 `commands` 1-based 下标、`test-evidence/cmd-NN.log` 三者全等（CR-2026-057 FR-16）。
② 11 个 in-scope FR **各出现一次**，主责 TASK 唯一（关联 TASK 不改变主责）；四张 TASK 全部在表中出现，与 `tasks/_index.yml#id` 双向一致。
③ `crctl.test.mjs`（224 用例）与 `checkpoint-tx.test.mjs`（≈ 194 s）**不整文件进证据集**：它们的本 CR 相关断言由 `cmd-03` 的 `--test-name-pattern` 定点取证（`CR-2026-042 静态合同`、`checkpoint T05 contract` 等纯静态用例，实测 < 5 s），文件级"不改坏"由 `cmd-01` 全量套件兜底（`files_executed=21` / `failures=0`）。**这不是假绿**：定点命令确实覆盖本行声称的验收面（新事实下的断言），全量命令覆盖「无回归」。
④ `cmd-03` 的 `--test-name-pattern` 必须**命中至少一条用例**：`crctl.test.mjs` 的 `CR-2026-042 静态合同…` 与 `checkpoint-tx.test.mjs` 的 `checkpoint T05 contract…` 是**既有用例名**，TASK-01 改写时**保留原名**（仅改断言体）；若改名，则本行证据失效即红（TASK-01 完成标志含此项）。
⑤ **`cmd-04` 的假绿口子由两道判据闭合**：① **用例名约定**（TASK-03 的 AC-8 六项用例名必须以 `CR-2026-066 AC-8` 起始）+ `cmd-05` 的**源码级存在性守卫**（`CR-2026-066 AC-8` token ≥ 6、`test(` 计数 ≥ 30）；② `cmd-04` 非零退出即红。**本条 run 实测：缺用例时 `--test-name-pattern` 空跑 exit 0（无摘要）** ⇒ 单靠 `cmd-04` 的退出码**不构成存在性证据**，必须与 `cmd-05` 的守卫同批判读；`test-report.md` 分析段与 TASK-03 完成标志须逐字记录两组数值（命中用例数与会话计数）。
⑥ **证据命令与 SDD 的关系**：`cmd-01`＝CI 步骤 `crctl full test suite` 逐字；`cmd-05` 的静态五步＝CI 步骤 lint-prompts / skill matrix / agents contract / pipeline JSON structure / writeback unit tests 的本机等价面（Windows 侧；Ubuntu 侧由外部 CI 承担，**不属本轮 run 拥有的工作，不等待其完成**）；`cmd-02`…`cmd-04` 是 `node --test` 定点形态；`cmd-05`…`cmd-07` 是本计划自有的只读审计命令（不新增 CI 面、不新增测试文件——`gate-registry.json` 零 diff 已双向保证文件集合不变）。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["skills/shared/crctl/scripts/test/suite-gate.mjs","--run"]` | 1080 |
| cmd-02 | tools | . | node | `["--test","--test-reporter=dot","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs","skills/shared/crctl/scripts/test/contract-scan.test.mjs"]` | 300 |
| cmd-03 | tools | . | node | `["--test","--test-reporter=dot","--test-name-pattern","CR-2026-042 静态合同","--test-name-pattern","checkpoint T05 contract","--test-name-pattern","CR-2026-044 AC-13","--test-name-pattern","CR-2026-044 AC-14","--test-name-pattern","CR-2026-050 AC-12","skills/shared/crctl/scripts/test/crctl.test.mjs","skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs"]` | 300 |
| cmd-04 | tools | . | node | `["--test","--test-reporter=dot","--test-name-pattern","CR-2026-066","skills/shared/crctl/scripts/test/archive-tx.test.mjs"]` | 600 |
| cmd-05 | tools | . | node | `["-e","const cp=require('child_process'),fs=require('fs'),path=require('path'); const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL; const read=p=>fs.readFileSync(path.join(R,p),'utf8').split(CR).join(NL); const bad=[]; const run=(label,args)=>{const r=cp.spawnSync(process.execPath,args,{cwd:R,encoding:'utf8',shell:false});const s=String(r.stdout==null?'':r.stdout),e=String(r.stderr==null?'':r.stderr);console.log('['+label+'] exit='+r.status);if(r.status!==0){bad.push(label+' exit='+r.status);console.log(s.slice(-500));console.log(e.slice(-500));}}; run('lint-prompts',['skills/shared/crctl/scripts/lint-prompts.mjs','--mode','enforce']); run('skill-matrix',['skills/shared/crctl/scripts/check-skill-matrix.mjs']); run('agents-contract',['skills/shared/crctl/scripts/check-agents-contract.mjs']); const wbt=fs.readdirSync(path.join(R,'skills/writeback/scripts/test')).filter(f=>f.endsWith('.test.mjs')).map(f=>'skills/writeback/scripts/test/'+f); run('writeback-tests',['--test','--test-reporter=dot'].concat(wbt)); const active=new Set();let cur=null; for(const l of read('skills/_index.yml').split(NL)){const t=l.trim();if(t.indexOf('- id: ')===0){cur=t.slice(6).trim();continue;}if(cur!==null&&t==='status: active'){active.add(cur);}} const pf=fs.readdirSync(path.join(R,'pipeline-templates')).filter(f=>f.endsWith('.pipeline.json')); for(const f of pf){const d=JSON.parse(read('pipeline-templates/'+f));const dn=d.nodes===undefined?[]:d.nodes;const ids=dn.map(n=>n.id);if(new Set(ids).size!==ids.length){bad.push(f+' 重复 node id');}for(const n of dn){if(n.kind==='skill'&&!n.ref){bad.push(f+' skill 节点缺 ref');}if(n.kind==='skill'&&n.ref&&!active.has(n.ref)){bad.push(f+' inactive ref '+n.ref);}const rl=n.reviewLoop;if(rl){if(rl.repairNodeId&&ids.indexOf(rl.repairNodeId)<0){bad.push(f+' 悬空 repairNodeId');}const rp=rl.replayNodes===undefined?[]:rl.replayNodes;for(const x of rp){if(ids.indexOf(x.nodeId)<0){bad.push(f+' 悬空 replayNode '+x.nodeId);}}}}} console.log('pipeline structure checked = '+pf.length+' active skills = '+active.size); const base='5d5a4ada96b882eb2c640e34bb72857a7073b668'; const WL=['pipeline-templates/requirement-authoring.pipeline.json','pipeline-templates/architecture-design.pipeline.json','pipeline-templates/code-implementation.pipeline.json','pipeline-templates/_index.yml','skills/requirement/review-requirement/SKILL.md','skills/develop/review-tech-design/SKILL.md','skills/develop/review-dev-plan/SKILL.md','skills/develop/review-code/SKILL.md','skills/sync/push-progress/SKILL.md','agent-skill-matrix.yml','AGENT-SKILL-MATRIX.md','agents/dev-agent.md','agents/quality-reviewer-agent.md','agents/delivery-agent.md','skills/shared/crctl/scripts/lib/workspace-transactions.mjs','skills/cr/cr-archive/SKILL.md','skills/writeback/merge-feature-branch/SKILL.md','README.md','openwiki/pipelines/overview.md','dir-graph.yaml','skills/shared/crctl/scripts/test/pipeline-structure.test.mjs','skills/shared/crctl/scripts/test/archive-tx.test.mjs','skills/shared/crctl/scripts/test/contract-scan.test.mjs','skills/shared/crctl/scripts/test/crctl.test.mjs','skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs']; const ZERO=['skills/shared/crctl/scripts/crctl.mjs','skills/shared/controlled-shell/rules.json','skills/shared/crctl/gates.json','skills/shared/crctl/scripts/test/gate-registry.json','pipeline-templates/emit-registry.mjs','skills/shared/crctl/scripts/lib/yaml-subset.mjs','skills/shared/crctl/scripts/lib/durable-tx.mjs','ARCHITECTURE.md','AGENTS.md']; const CRCTL=path.join(R,'skills/shared/crctl/scripts/crctl.mjs'); const r0=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only',base,'--cwd',R],{encoding:'utf8'}); if(r0.status!==0){bad.push('crctl git diff 失败');}else{const parts=String(r0.stdout).split(NL);const bi=parts.findIndex(l=>l.trim()==='{');const changed=parts.slice(0,bi<0?parts.length:bi).map(s=>s.trim()).filter(Boolean);console.log('tools diff paths = '+changed.length);changed.forEach(f=>console.log('  '+f));for(const f of changed){if(WL.indexOf(f)<0){bad.push('越界路径 '+f);}}for(const f of WL){if(changed.indexOf(f)<0){bad.push('缺少应改文件 '+f);}}for(const f of ZERO){if(changed.indexOf(f)>=0){bad.push('zero_diff 面被改动 '+f);}}} const hunk=(p,tokens)=>{const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--unified=0',base,'--',p,'--cwd',R],{encoding:'utf8'});if(r.status!==0){bad.push('diff 失败 '+p);return;}const lines=String(r.stdout).split(NL).filter(l=>{const c=l.charAt(0);if(c==='+'){return l.indexOf('+++')!==0;}if(c==='-'){return l.indexOf('---')!==0;}return false;});for(const l of lines){for(const t of tokens){if(l.indexOf(t)>=0){bad.push(p+' 改动命中禁改 token '+t);}}}}; hunk('dir-graph.yaml',['state_machine:','wildcards:','transitions:','namedStates']); hunk('skills/shared/crctl/scripts/lib/workspace-transactions.mjs',['function checkpointCr','function mergeCr','function applyWriteback','function registerCr','function reconcileLocalTrunks','function buildRecovery']); const at=read('skills/shared/crctl/scripts/test/archive-tx.test.mjs'); const ac8=at.split('CR-2026-066 AC-8').length-1; const tn=at.split('test(').length-1; console.log('archive-tx AC-8 tokens = '+ac8+' test( count = '+tn); if(ac8<6){bad.push('archive-tx 未登记 6 条 AC-8 用例名（CR-2026-066 AC-8，实得 '+ac8+'）');} if(tn<30){bad.push('archive-tx test( 调用数 = '+tn+'（基线 24 + 新增 6）');} const pp=read('skills/sync/push-progress/SKILL.md'); if(pp.indexOf('评审 PASS')<0){bad.push('push-progress SKILL 缺 [评审 PASS] 口径');} if(pp.indexOf('搭车')<0){bad.push('push-progress SKILL 缺 [搭车] 口径');} if(pp.indexOf('审批后的阶段终点 checkpoint 为强制完成条件')>=0){bad.push('push-progress SKILL 保留旧句');} const rd=read('README.md'); if(rd.indexOf('评审 PASS')<0){bad.push('README 缺 [评审 PASS] 口径');} if(rd.indexOf('阶段终点 checkpoint 是 Pipeline 完成条件')>=0){bad.push('README 保留旧句');} const ow=read('openwiki/pipelines/overview.md'); if(ow.indexOf('review PASS')<0){bad.push('openwiki 缺 [review PASS] 口径');} for(const t of ['mandatory approval checkpoint','mandatory checkpoint','checkpoints are mandatory','checkpoint (mandatory)','D8[','D12[','checkpoint →']){if(ow.indexOf(t)>=0){bad.push('openwiki 保留旧词法 '+t);}} const dg=read('dir-graph.yaml'); if(dg.indexOf('修复、证据、checkpoint 与当前评审节点')>=0){bad.push('dir-graph contract 第 5 条保留旧词法');} if(dg.indexOf('基线重核')<0){bad.push('dir-graph contract 第 5 条未改准');} if(bad.length>0){console.log('tools-close-audit failures = '+bad.length);bad.forEach(x=>console.log('FAIL '+x));process.exit(1);} console.log('tools-close-audit failures = 0');"]` | 600 |
| cmd-06 | multica | . | node | `["-e","const cp=require('child_process'),fs=require('fs'),path=require('path'); const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL; const read=p=>fs.readFileSync(path.join(R,p),'utf8').split(CR).join(NL); const bad=[],D='cr-prompts-revised/',F=['quality-reviewer-agent.md','dev-agent.md','delivery-agent.md','cr-coordinator-agent.md']; const full={};for(const n of F){full[n]=read(D+n);} const qa=full['quality-reviewer-agent.md']; const b0=qa.indexOf('## 受限 crctl 权限'),e0=qa.indexOf('## ',b0+3); if(b0<0){bad.push('quality-reviewer-agent 缺 [受限 crctl 权限] 节');} const blk=b0<0?'':qa.slice(b0,e0<0?qa.length:e0); if(blk.indexOf('workspace inspect')<0){bad.push('受限 crctl 权限块未列入只读 workspace inspect');} if(blk.indexOf('checkpoint')<0){bad.push('受限 crctl 权限块禁止面未保留 checkpoint');} if(qa.indexOf('本 Agent 不负责 push/checkpoint')>=0){bad.push('quality-reviewer-agent 保留旧句 [本 Agent 不负责 push/checkpoint]');} if(full['dev-agent.md'].indexOf('统一 checkpoint')>=0){bad.push('dev-agent 保留 [统一 checkpoint] 旧前提句');} if(full['dev-agent.md'].indexOf('checkpoint 未完成时')>=0){bad.push('dev-agent 保留 [checkpoint 未完成时] 旧前提句');} const da=full['delivery-agent.md']; if(da.indexOf('recovery')<0){bad.push('delivery-agent 未登记结构化 recovery 例外');} if(da.indexOf('同 run')<0){bad.push('delivery-agent 缺 [同 run] 搭车口径');}if(da.indexOf('localTrunkSync')<0){bad.push('delivery-agent 汇报面缺 [localTrunkSync]');} for(const n of F){const t=full[n];if(t.indexOf('单独开委派')<0){bad.push(D+n+' 缺搭车硬规则 [单独开委派]');}if(t.indexOf('已部署')>=0){bad.push(D+n+' 出现部署声称');}} const CRCTL='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-066/skills/shared/crctl/scripts/crctl.mjs'; const r0=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','43848770bff13465de8ed9a0e28ecc7371716514','--cwd',R],{encoding:'utf8'}); if(r0.status!==0){bad.push('crctl git diff 失败');}else{const parts=String(r0.stdout).split(NL);const bi=parts.findIndex(l=>l.trim()==='{');const changed=parts.slice(0,bi<0?parts.length:bi).map(s=>s.trim()).filter(Boolean);console.log('multica diff paths = '+changed.length);changed.forEach(f=>console.log('  '+f));for(const f of changed){if(f.indexOf(D)!==0){bad.push('multica 越界路径 '+f);continue;}if(F.indexOf(f.slice(D.length))<0){bad.push('multica 越界路径 '+f);}}for(const n of F){if(changed.indexOf(D+n)<0){bad.push('multica 缺少应改文件 '+D+n);}}} if(bad.length>0){console.log('multica-audit failures = '+bad.length);bad.forEach(x=>console.log('FAIL '+x));process.exit(1);} console.log('multica-audit failures = 0');"]` | 300 |
| cmd-07 | ai-first-platform-docs | . | node | `["-e","const cp=require('child_process'),fs=require('fs'),path=require('path'); const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL; const read=p=>fs.readFileSync(path.join(R,p),'utf8').split(CR).join(NL); const bad=[],CRD='change-requests/CR-2026-066/'; const plan=read(CRD+'plan.md').split(NL).filter(l=>l.indexOf('const cp=require(')<0).join(NL); for(const t of ['AC-6 延期验证点','载体','时点','观察项 ①','观察项 ②','观察项 ③','观察项 ④','责任 agent','关闭触发','AIFIRST_ARCHITECTURE_RUNNER','未重生成','D-6','cr-prompts-revised/agent-skill-matrix.yml','部署窗口','受限 crctl 权限','workspace inspect']){if(plan.indexOf(t)<0){bad.push('plan.md 交付说明必填块缺 token '+t);}} if(plan.indexOf('已重生成')>=0){bad.push('plan.md 不得声称已重生成（本 CR 走 [未重生成 + Runner 保持禁用] 分支）');} if(plan.indexOf('平台已部署')>=0){bad.push('plan.md 出现平台部署声称');} const CRCTL='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-066/skills/shared/crctl/scripts/crctl.mjs'; const r0=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','9a64fc4fac97e328a2dee0bff1711cc4f2a4c367','--cwd',R],{encoding:'utf8'}); if(r0.status!==0){bad.push('crctl git diff 失败');}else{const parts=String(r0.stdout).split(NL);const bi=parts.findIndex(l=>l.trim()==='{');const changed=parts.slice(0,bi<0?parts.length:bi).map(s=>s.trim()).filter(Boolean);console.log('KB diff paths = '+changed.length);changed.forEach(f=>console.log('  '+f));for(const f of changed){if(f.indexOf(CRD)!==0&&f!=='change-requests/_backlog.yml'){bad.push('KB 越界路径 '+f);}}} if(bad.length>0){console.log('kb-audit failures = '+bad.length);bad.forEach(x=>console.log('FAIL '+x));process.exit(1);} console.log('kb-audit failures = 0');"]` | 120 |

> **转录纪律**：`cmd-05`/`cmd-06`/`cmd-07` 的 `-e` 脚本是**单参数**，`write-test-report` 逐字转录 §6.2.1…§6.2.3 的源码块（`args` 数组的第二个元素），不得重排、不得改写引号。三个脚本均**不含**双引号 / 反斜杠 / 换行 / `|`（需要换行常量处用 `String.fromCharCode(10)` 构造；路径一律正斜杠），因此 `JSON.stringify` 往返逐字相同。

#### 6.2.1 `cmd-05` 说明（AUDIT-TOOLS，只读审计，不新增 CI 面）

覆盖六类判据：**(a) CI 静态五步**（`lint-prompts --mode enforce` / `check-skill-matrix` / `check-agents-contract` / pipeline JSON 结构断言（重复 id、skill `ref` 存在且在 `skills/_index.yml` 为 active、`reviewLoop.repairNodeId` 与 `replayNodes[]` 无悬空）/ `skills/writeback/scripts/test/*.test.mjs`）；**(b) tools diff 白名单双向相等**（恰为 SDD §1.2 的 25 个文件）；**(c) `zero_diff` 文件不在改动集合**；**(d) hunk 级禁改 token**（`dir-graph.yaml` 的 state_machine 段、`workspace-transactions.mjs` 的 6 个函数声明）；**(e) FR-9 口径四处的正/负 token**；**(f) AC-8 用例存在性守卫**（`archive-tx.test.mjs` 内 `CR-2026-066 AC-8` token ≥ 6 且 `test(` 调用数 ≥ 30）——与 `cmd-04` 的「执行面」互补，闭合 `cmd-04` 空跑即绿的假绿口子（见表注⑤）。

#### 6.2.2 `cmd-06` 说明（AUDIT-MULTICA，断言 B 的一次性交付证据）

覆盖五类判据：**(a)** `## 受限 crctl 权限` 块含只读 `workspace inspect` 且禁止面仍含 `checkpoint`（B-1 的 multica 侧）；**(b)** 三份旧前提句零命中（L54 冲突句、`dev-agent` 的两句）；**(c)** 四份副本均含搭车硬规则 token `单独开委派`，`delivery-agent` 含 `recovery`、`同 run` 与 `localTrunkSync`（AC-8⑥ 的 delivery 半）；**(d)** multica diff 面**恰为** 4 份 `cr-prompts-revised/*.md`；**(e)** 副本不出现部署声称。该命令**不落长期 CI 面**（D-5：multica 在工作区外、tools CI 不可见），只作 TASK-02/TASK-04 的完成证据与 `test-report.md` 的 issue evidence。

#### 6.2.3 `cmd-07` 说明（AUDIT-KB，交付登记面）

覆盖三类判据：**(a)** `plan.md` 的交付说明必填块（AC-6 六字段、FR-11 的 `AIFIRST_ARCHITECTURE_RUNNER` 与「未重生成」分支、D-6 的第五份副本排除理由、部署窗口成对生效、断言 B 结论的两个 token）；**(b)** 不得出现「重生成已完成」或平台侧部署声称（负向）；**(c)** KB diff 面 ⊆ `change-requests/CR-2026-066/**` ∪ `change-requests/_backlog.yml`。

**自证防护**：脚本先按 token `const cp=require(` **剔除三维度审计命令所在行**，只扫描 `plan.md` 的非证据命令面——否则脚本自身文本会把正向 token 全部「自证」、把负向 token 全部「自触发」（本条 run 实测到后者，见 §6.3）。

### 6.3 干跑/可达性记录（本条 run 按同一语义实跑，未改任何文件）

干跑语义 = `spawnSync(executable, args, { cwd: <repo worktree>/<cwd>, shell:false })`；下表均为**变更前基线**实测（本条 run，win32 / node v24.15.0）。

| 证据ID | 可达性 | 本条 run 实测 | 结论（变更前 / 变更后预期） |
|---|---|---|---|
| cmd-01 | 可达 | **exit 0 / 786 s / 21 文件 / 588 用例 / failures=0 / skipped_file_level=0** | 变更前全绿；变更后须 `failures=0` 且 **`cases_executed ≥ 594`**（588 + 6 条 AC-8 用例） |
| cmd-02 | 可达 | **exit 0**（pipeline-structure 1 s ＋ contract-scan 1 s） | 变更前绿（旧事实）；变更后须在新断言下仍绿（TASK-01/02 落地后） |
| cmd-03 | 可达 | **exit 0**（定点命中的两条纯静态用例 < 1 s） | 变更前绿；变更后须仍绿（用例名保留、断言体改新事实） |
| cmd-04 | **实施后可达** | **未跑**：`CR-2026-066` 前缀用例尚不存在；实测**空跑即绿**（exit 0、无摘要）⇒ 单靠它构成假绿 | TASK-03 完成后首次干跑 = cmd-04 本体；用例存在性由 `cmd-05` 的 token 计数守卫兜底（表注⑤） |
| cmd-05 | 可达 | **exit 1 / 42 failures**（CI 静态四步 exit 0、`pipeline structure checked = 8`、`tools diff paths = 0`、`archive-tx AC-8 tokens = 0 / test( count = 28`；25 项「缺少应改文件」＋ 15 项口径/文本未改 ＋ 2 项 AC-8 守卫） | 实施前基线；失败向量逐条对应 TASK 交付物（25 文件 + 口径四处 + AC-8 用例名） |
| cmd-06 | 可达 | **exit 1 / 14 failures**（权限块未含 `workspace inspect`、L54 冲突句、`dev-agent` 两句旧前提、四副本缺搭车硬规则、`delivery-agent` 缺 `localTrunkSync`、4 份应改文件缺失） | 实施前基线 |
| cmd-07 | 可达 | **exit 0**（登记块已在 §10 落盘 ⇒ AC-6 按「登记即达成」定义在交付时即可判定）；**失败向量已实测**：首版负向判据命中 2 项（禁止声称），修正表述后归零 | 变更后须继续 exit 0（负向判据活性已证） |

- 七条命令均为只读：不写账本、不写登记面、不新增测试文件（`gate-registry.json` 零 diff 双向保证文件集合不变）。
- **`cmd-05` 的一次环境抖动（如实登记）**：本条 run 四次运行中有一次 `writeback-tests` 子进程 exit 1 崩溃（`node:test` 的 async_hooks 栈、无断言失败），其余三次 exit 0（含手工单跑两次）。判定为环境抖动而非本 CR 的判据面；处置 = 按同一命令重跑（只读、幂等），不改判据、不降级。

---

## 7. AC/业务闭环覆盖矩阵（契约必填节，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 节点数 5/4/12；无门后 `push-progress`；`ref=push-progress` 计数 = 0；`_index.yml` ≡ JSON；被删 id 零出现 | §4.4.1 ＋ §6.2 AC-1 | CR-2026-066-TASK-01 | cmd-02；cmd-03 |
| AC-2 既有断言按新事实同步且全绿；新增断言覆盖两条判据与「review SKILL 含发布步骤 + clean 前置」 | §6.4 ＋ §4.4.2-4 ＋ NFR-5 | CR-2026-066-TASK-01 | cmd-02；cmd-03；cmd-01（全套件不回归） |
| AC-3 四个 review SKILL 均含 clean 前置 + PASS 发布 + 对账 + 失败语义；BLOCK 不含发布；四 SKILL 不含退役字段名 | §4.1/§4.2/§4.3 ＋ §6.4 新增行 | CR-2026-066-TASK-02 | cmd-02（含 `RETIRED_RECOVERY` 由 `contract-scan` 承载） |
| AC-4 ①矩阵 can-call/forbidden；②权限面闭合（三处载体 + 四 SKILL 前置同一条断言）；③反向（四 SKILL 不含 `crctl checkpoint` / 两份副本含 `workspace inspect`）；④本 CR 行 + 三脚本绿 | §3.3 ＋ §6.2 AC-4 ＋ B-1 回归判据 | CR-2026-066-TASK-02 | cmd-02（断言 A）；cmd-06（断言 B）；cmd-05（三脚本绿） |
| AC-5 CI 六步骤全绿、不签例外 | §6.4 ＋ NFR-1 ＋ `.github/workflows/crctl-ci.yml` | CR-2026-066-TASK-04（关联 CR-2026-066-TASK-01/02/03） | cmd-01（suite-gate 步骤 + 全量套件）；cmd-05（其余五步本机等价面） |
| AC-6 延期验证点登记块（载体/时点/观察项①~④/责任 agent/关闭触发） | §6.6 ＋ PRD AC-6 | CR-2026-066-TASK-04 | cmd-07 |
| AC-7 四处口径一致、旧句零命中 | §6.5 | CR-2026-066-TASK-04 | cmd-05 |
| AC-8 六项用例（三返回点含字段 / 分类 / dirty 逐字节未变 / argv 白名单 / 幂等重放 / 文档面） | §4.6 ＋ §6.2 AC-8 | CR-2026-066-TASK-03（关联 CR-2026-066-TASK-04：delivery 汇报面） | cmd-04；cmd-01（argv 面随套件执行）；cmd-06（delivery 汇报面的 multica 半） |
| AC-9 交付说明登记 `NodeID`/`Seq` 与 digest 需重生成 **或**「未重生成 ⇒ Runner 保持禁用」 | §6.7 ＋ FR-11 | CR-2026-066-TASK-04 | cmd-07 |
| AC-10 ①scope_out 可检查（无平台执行层/新节点维度账本字段、无事务层与状态机改动、无 `recoverCommand` 复活）；②不做「审批后可选 checkpoint」；③串行（在途唯一）；④与 CR-P1/P2 面零 diff | §9 `scope_out`/`zero_diff` ＋ §7 | CR-2026-066-TASK-04 | cmd-05（tools diff/zero_diff + hunk 级禁改 token）；cmd-06（multica diff）；cmd-07（KB diff）；cmd-04（`RETIRED_RECOVERY` 零命中） |
| 业务闭环：发布的必须是被评审的（对账即发布，无静默通过） | §4.3 ＋ §3.4 `CONTRACT_DRIFT` | CR-2026-066-TASK-02 | cmd-02 |
| 业务闭环：「零发布节点」与「无门后发布节点」同时成立（两条判据由 JSON 自身求出） | §4.4 ＋ §6.2 AC-1 可达性说明 | CR-2026-066-TASK-01 | cmd-02 |
| 业务闭环：归档 best-effort 且永不破坏本地在途修改（dirty ⇒ `skipped` 且逐字节未变） | §4.6 ＋ §7.3 | CR-2026-066-TASK-03 | cmd-04 |
| 业务闭环：交付登记面不静默（AC-6/AC-9/D-6/部署时序/断言 B 结论） | §6.6/§6.7 ＋ SDD-CLOSE-03/05 ＋ §9 `scope_in` 交付说明要求 | CR-2026-066-TASK-04 | cmd-07 |

> **关键 AC 唯一 owner 说明（机械可判）**
> - **AC-1 / AC-2 唯一 owner = TASK-01**（节点退役与测试面连带的实际产生层；证据 cmd-02、cmd-03，回归面 cmd-01）。
> - **AC-3 / AC-4 唯一 owner = TASK-02**（四 SKILL 文本与四处权限载体的实际产生层；证据 cmd-02、cmd-06、cmd-05）。
> - **AC-8 唯一 owner = TASK-03**（`archiveCr` 返回面与 `archive-tx` 用例的实际产生层；证据 cmd-04）。
> - **AC-5 / AC-6 / AC-7 / AC-9 / AC-10 唯一 owner = TASK-04**（口径改写、搭车规则、diff/zero_diff 与交付登记的实际产生层；证据 cmd-01、cmd-05、cmd-07）。
> - 四张 TASK 均在矩阵中出现，与 `tasks/_index.yml#id` 集双向一致；业务闭环行不与关键 AC 行争用同一证据语义。
> - **无阻断**：全部 AC 的验收证据在实施后**可达**（§6.3 干跑记录；AC-6 按「登记即达成」定义，不需要未来证据）。

---

## 8. 附带项与残余项收口对照

### A. 协调者转交的 3 条 non-blocking 附带项（本轮逐条处置）

| # | 附带项（`review-annotations/sdd.yml#suggestions`） | 处置 | 落点 |
|---|---|---|---|
| **S-13** | 三份 review SKILL 的旧 checkpoint 前提句（`review-requirement` L10 / `review-dev-plan` L9 / `review-code` L10、L16）在 FR-5 删除 `…0003`/`…0008` 后必须改写；§6.5 的清单与 AC-3/AC-7 文本判据未覆盖 | **已处理（显式列入交付项 + 新增负向 token 断言）**：① TASK-02 的「涉及文件/实现要点」逐条列出这三份 SKILL 的旧句原文与目标口径；② `pipeline-structure.test.mjs` 的 AC-3 断言块追加**负向 token 断言**（四个 review SKILL 文本不含 `push-progress 之后` / `push-progress 之前` / `统一 checkpoint 后`），与既有「含 clean 前置/发布 token」正向断言同一条；③ `cmd-05` 只做正向口径核对（不重复负向面）。**不改 `sdd.md`**（审批冻结）。 | `tasks/TASK-02.md`；`cmd-02` |
| **S-14** | §6.4 `checkpoint-tx` 行的断言区间应写准：整条 test 起于 L487、`filter` 在 L491、止于 L506；L495-506 是 review-alignment 事实源断言，须保留 | **已处理**：TASK-01 写明三个精确锚点（L487 用例起点 / L491 `filter` 形态 / L506 用例终点），并明写「**只改 L491 的 `filter` 形态 → 显式枚举**，L495-506 逐字保留」；`cmd-03` 定点跑该用例名（`checkpoint T05 contract`）验证改写后仍绿。**禁止**按窄范围（L487-495）截断用例。 | `tasks/TASK-01.md`；`cmd-03` |
| **S-12** | §6.3 节首收录判据③「§9 `zero_diff` 点名对象」与清单内容不一致（`advance`/`gate`/`review-record` 与 `registerCr` 无独立条目） | **保留理由（一句话）**：判据③ 在本 CR 的操作口径按「**设计成立依赖**的零改动载体」解释（与评审者 `verdict=pass` 的判定同口径）——上述四个命令面对象**不要求**入册，其**零改动义务**仍逐字按 §9 `zero_diff` 表执行，并由 `cmd-05` 的 zero_diff 文件集合断言 + hunk 级禁改 token 断言 + `cmd-01` 全套件机械兜底；**收窄或补登判据③ 的唯一合法落点是 §6.3 正文，而该文件已被审批冻结（改一字即触发 `APPROVED_ARTIFACT_DRIFT`），故本轮不做**。 | 本计划 §8；`cmd-05` |

### B. SDD 评审已完成闭合项（不在本轮动作面）

- `已解决：B-2`（§6.3 漏列项，含 `cmdArchive` ＋ 两个候选）、`已解决：S-11`（第 35 项括注精度）、`已解决：S-7`~`S-10`（历史闭合项）：均已在 SDD rev 0.4 落地并随 `subject-sha256 78846c1b…` 冻结，**本计划不复述、不改写**。

### C. `zero_diff` 复核清单（TASK 卡须逐条声明不触碰，`cmd-05` 机械兜底）

**零 diff 文件**（不在改动集合）：`skills/shared/crctl/scripts/crctl.mjs`（全文件）、`skills/shared/controlled-shell/rules.json`、`skills/shared/crctl/gates.json`、`skills/shared/crctl/scripts/test/gate-registry.json`、`pipeline-templates/emit-registry.mjs`、`skills/shared/crctl/scripts/lib/yaml-subset.mjs`、`skills/shared/crctl/scripts/lib/durable-tx.mjs`、`ARCHITECTURE.md`、`AGENTS.md`、`change-requests/CR-2026-066/prd.md`、KB 的 `specs/`+`delivery/`+`docs/`、multica 的 `cr-prompts-revised/agent-skill-matrix.yml` + `CUSTOM.md` + `aifirst/**` + 任何 Go/TS 代码。

**段/函数级零 diff**（文件在改动集合内，但下列对象零 diff，由 hunk 级禁改 token 兜底）：`dir-graph.yaml#change-request-track.state_machine`（含 `state_machine:`/`wildcards:`/`transitions:`/`namedStates`）；`checkpointCr` / `mergeCr` / `applyWriteback` / `registerCr` / `reconcileLocalTrunks` / `buildRecovery` 的函数体与签名；`archiveCr` 既有返回字段与 `phase` 分类；`recovery` 结构化合同字段名。

**无独立条目但零改动义务不变**：`advance` / `gate` / `review-record` 命令面（S-12 保留理由，见上 A 表）。

### D. 本条 run 不处置（仅登记，防误作漏做）

- `follow_up` 8 项（SDD §9）：S-7 第五份副本部署对齐、`node-N.md` 命名不一致、`node-N.md` 历史错位、review SKILL 的「调用时机」节点序号、`gate_nodes_gen.go` 与 registry digest 重生成、KB `docs/analysis/done/` 历史分析文档、`assertion-sources.mjs` 派生 helper 上移、AC-6 演练载体注册 —— **一律不得顺带实现**（FR-1 的「调用时机」句改写只改 checkpoint 前提句，**不改节点序号数字**）。
- CR-P1 / CR-P2 的面（`review-tech-design` Step 2.x、`quality-reviewer-agent#评审判断`、code pipeline dev-start 提示、`review-dev-plan` 的 acceptance-verifiability 面）：**零 diff**。

---

## 9. TASK 拆分预分配（`write-dev-tasks` 的输入，共 4 个，组映射 1:1）

| 变更组 | 覆盖 FR | TASK id | 仓 | 粒度 | 依赖 | 估算 |
|---|---|---|---|---|---|---|
| G1 节点退役与测试面连带闭合 | FR-4、FR-5 | CR-2026-066-TASK-01 | tools | 3 天 | — | 24h |
| G2 评审 PASS 发布、clean 前置与权限面 | FR-1、FR-2、FR-3、FR-8 | CR-2026-066-TASK-02 | tools + multica | 3 天 | CR-2026-066-TASK-01 | 24h |
| G3 归档尾部 trunk 同步 | FR-10 | CR-2026-066-TASK-03 | tools | 2 天 | — | 16h |
| G4 口径改写、搭车硬规则与登记收口 | FR-6、FR-7、FR-9、FR-11 | CR-2026-066-TASK-04 | tools + multica | 3 天 | CR-2026-066-TASK-01、CR-2026-066-TASK-02、CR-2026-066-TASK-03 | 24h |

- `task_count_hint = 4`（= 上表组数 = `tasks/_index.yml` 的 TASK 数 = §6.1/§7 出现的 canonical id 集）；`crctl task init` 返回值 `totalEstimateHours` 期望 = **88h**。
- 三步断言（CR-2026-060 AC-08）：① 组映射 preflight（恰 4 张卡、`CR-2026-066-TASK-01..04` 连续无重号、与上表一致）；② `crctl task init CR-2026-066 --count-hint 4`（写入前可数校验，失败 `TASK_COUNT_MISMATCH` 零写入）；③ init 后复核磁盘文件集与组映射（防并发增删）。
- **TASK 卡的权威进度字段是 `tasks/_index.yml`**：卡片 frontmatter 的 `status` 一律 `pending`（`renderTaskIndex` 的渲染口径），真实状态只以账本为准（`crctl task done` 登记，带 `done-at`）。
- 四张卡的完成边界全部落在 `developing` 内可被 `crctl task done` 登记的事件（实现已落盘 + 证据命令绿 + 账本登记），**无 `merge` / `writeback` / `archive` / `code-reviewing` / `code-approved` 前置**（流程控制 TASK 禁止，CR-2026-057 FR-10）。
- 命名约定：TASK-03 新增的 `test(...)` 名必须以 `CR-2026-066` 起始（`cmd-04` 的定点模式依赖）；TASK-01 改写既有断言时**保留用例名**（`cmd-03` 的定点模式依赖）。

---

## 10. 交付说明必填块（`cmd-07` 机械核对；TASK-04 落盘、交付评论/`test-report.md` 逐字转录）

**AC-6 延期验证点**

```text
AC-6 延期验证点
  载体       : 本 CR 交付后新注册的小体量演练 CR（首选，由协调者/owner 指定）；次选 = CR-P1 的首次阶段评审 PASS 链
  时点       : 载体走完四个阶段的评审发布与审批之后
  观察项 ①   : 每个 review PASS 后远端存在完整批次（repositories[].confirmed=true ∧ metadataCommit 非空 ∧ 对账通过）
  观察项 ②   : 审批动作不产生任何 checkpoint 委派（评审 PASS 之后的 checkpoint 次数 = 0）
  观察项 ③   : 审批未发布时 merge 给出 MERGE_SOURCE_MISSING/RELEASE_REMOTE_NOT_PUSHED + recovery，同 run 执行后可继续（或首次即通过）
  观察项 ④   : 「为单个 push-progress 单独开 task」次数 = 0
  责任 agent : delivery-agent（记录发布批次与 merge 兜底）；cr-coordinator-agent（记录委派计数）
  关闭触发   : 载体归档，或该链路首次走完
```

**FR-11 平台生成物登记（二选一，本 CR 的实际分支 = ②）**

- 受影响映射（可复算，SDD §6.7）：`gate_nodes_gen.go#ApprovalGates` requirement `…0005` Seq 5 → **Seq 4**；`#ReviewGates` requirement `…0004` Seq 4 → **Seq 3**；`#ApprovalGates` dev-start `…0004` Seq 5 → **Seq 4**；`#ApprovalGates` code `…0010` Seq 14 → **Seq 11**；`#ReviewGates` code `…0009` Seq 12 → **Seq 10**；tech-design 两项不变；`#ArchitectureCoreRegistryJSON` 整块 digest 必变（nodes 5→4，当前 `sha256:5454bfd9…c91cc`）。
- **登记文本 = ②：未重生成 ⇒ 重新生成前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用**（`runner.go:56-63` 未设即 false；multica `.github/workflows/*` 对 `gate-nodes`/`governance` 零引用 ⇒ 未重生成不会让任一侧 CI 变红）。重新生成由 owner 在**部署窗口**执行，不属本 CR 范围。

**D-6：第五份权限面副本的排除理由（S-7）**

- `cr-prompts-revised/agent-skill-matrix.yml` L192-194 仍含旧块注释（未含 `workspace inspect`）；按 `CUSTOM.md#75` 的「公共 Prompt 唯一事实源为 `tools/agents/`、目录内副本不再独立演进、分叉时以 tools 为准人工对齐」在下一次部署/rebase 核对时处理（本 CR 不改，登记为 `follow_up` 第一项）。

**SDD-CLOSE-05：部署时序（成对生效）**

- 本 CR 只改仓库内文本；平台把 `push-progress` 绑定给 `quality-reviewer-agent`、Prompt 投影与生成物重生成均为 owner 的**部署窗口**动作。部署前 Multica 侧运行的仍是旧白名单（不含只读 `workspace inspect`）⇒ 部署窗口必须与 tools 侧改动**成对生效**，否则 FR-2 前置会被旧合同误判。本 CR 的机械断言只约束仓库内文本，**不约束部署状态，也不构成平台侧的部署声称**。

**AC-4②③ 的断言 B 核对结论**

- 被核文件：`../multica/cr-prompts-revised/quality-reviewer-agent.md` 的 **`## 受限 crctl 权限`** 节（穷尽式白名单）。命中的 token：允许面 **只读 `workspace inspect`**；禁止面仍含 **`checkpoint`**。核对方式 = `cmd-06`（`repo=multica` 的一次性交付证据，不落长期 CI 面）。

---

## 11. 本计划不得越界（`zero_diff` 与本 CR 边界，逐条生效）

1. 不改 `sdd.md` / `prd.md` 一个字节（审批与评审双重绑定）。
2. 不改 `crctl.mjs`、`rules.json`、`gates.json`、`gate-registry.json`、`emit-registry.mjs`、`yaml-subset.mjs`、`durable-tx.mjs`、`ARCHITECTURE.md`。
3. 不改事务层/状态机/错误码/`reviewLoop` 语义（唯一例外：`review-code.reviewLoop.replayNodes` 删 `…0008` 一项）；不复活 `recoverCommand`/`recover_command`。
4. 不新增 pipeline 节点、评审维度、账本字段、观测指标、crctl 子命令、错误码、Skill 参数、落盘文件；**不新增测试文件**（`gate-registry.json` 的 `manifest.files` 保持 21）。
5. 不做「审批后可选 checkpoint」节点（不以 `onFail: skip` + 输入端开关变相恢复）；不重编号其它节点 id。
6. `../multica` 只改 4 份 `cr-prompts-revised/*.md`，不写 Go/TS、不改 `CUSTOM.md`、不改 `aifirst/**`、不改 `cr-prompts-revised/agent-skill-matrix.yml`。
7. 不新增委派 lint 规则、不新增跨仓（`../multica`）CI 条件断言（D-5：multica 侧以一次性交付证据覆盖）。
8. 不部署平台 Prompt、不重生成 `gate_nodes_gen.go`、不启用 Runner。

---

## 12. 修订记录

- 初稿（2026-09-14，`code-implementation` node-1）：按已审批 SDD rev 0.4（`sha256(LF) 78846c1b…`）与 PRD（`9b43bbfa…`）起草；架构阶段终点 checkpoint 已在本节点首位发布（`batchId a6c98051920971b1`）；测试面基线在本节点实测（全量套件 `verdict=pass` / 786 s / 588 用例 / 0 failures；CI 静态五步全绿）；四组 TASK 预分配（24/24/16/24 h = 88 h）；7 条证据命令（`cmd-01`~`cmd-07`）；协调者转交的 S-12/S-13/S-14 逐条处置（§8.A）。
