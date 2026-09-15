---
id: CR-2026-067-plan
type: PLAN
cr-ref: CR-2026-067
sdd-ref: "change-requests/CR-2026-067/sdd.md"
target-version: 0.40
status: draft
created: 2026-09-15T10:05:00+08:00
updated: 2026-09-15T10:05:00+08:00
---

# CR-2026-067 开发计划（CR-P1：评审输入结构与回修闭合 — SDD 既有实现事实的 `dep-N` 唯一表达、评侧同口径核验、状态链整体重证与批准范围四字段自洽）

**权威输入（人工审批绑定，本计划不修改其一个字节）**

| 输入 | 绑定 | 摘要证据 |
|---|---|---|
| `change-requests/CR-2026-067/sdd.md`（832 行 / 81,916 B / LF-only，唯一权威） | `review-annotations/sdd.yml#subject-sha256`（cycle 1 / attempt 2，`verdict=pass`、`blockers=[]`）+ `approval.yml#tech-design`（`via: crctl-approve`、`2026-09-15T09:20:01+08:00`、approver `OldBoy405`、`evidence-digest 99dda63a…`、`target-status: tech-design-reviewed`） | sha256(LF) = `551f5a39fea79b858920ac723dc6e1fb779f775baac39fa0a58a86fc6eaad2fe`（本节点按 worktree 实际文件复算，与 `review-annotations/sdd.yml#subject-sha256` 逐字节相等） |
| `change-requests/CR-2026-067/prd.md`（285 行 / 51,864 B / LF-only） | 需求人工审批冻结 | sha256(LF) = `efde31fd0ce727ee58c733de6f97b464b95e069dcdfc615c71488113cbeb0fea`（SDD §6.3 第 30 项登记值；本计划只按 SDD 引用定位抽查，**不全量复审 PRD**） |
| `cr.md#target-version` | 注册期继承 | `0.40`（禁止 tbd / 自行改写，CR-2026-057 FR-13） |

- **硬边界一（不得触碰）**：`sdd.md` 已被 `review-annotations/sdd.yml#subject-sha256` 与 `approval.yml#tech-design#evidence-digest` **双重绑定**——改它一个字节即同时作废本轮评审与人工审批（`APPROVED_ARTIFACT_DRIFT`）。本计划与 `tasks/**` 只**重述**已审批的实施契约，不新增 SDD 正文修改；`prd.md` 同样零触碰（含 S-1 的「七条」措辞与 S-2 的计数偏差，见 §8）。
- **硬边界二（范围）**：交付面 = SDD §1.2 / §9 的 **4 个文件**（全部在 `../tools`）；`zero_diff` 面（§9）逐条不得改动；`follow_up` 6 项不得顺带实现（§8.C）。
- **本计划的 replay 身份**：本条 run = `code-implementation` **node-1/node-2**（`write-dev-plan` → `write-dev-tasks`）；`review-dev-plan` 由**独立 quality-reviewer-agent run** 执行（不在作者会话内自评），`reviewLoop.maxAttempts=3`、`repairRef=write-dev-plan`、`replayNodes=[write-dev-plan, write-dev-tasks, review-dev-plan]`。
- **上一阶段发布收口已在本节点首位完成**（§0.2）：tech-design 人工审批提交已随一次 `crctl checkpoint` 发布。

---

## 0. 基线与工作区事实（本节点实测，落笔即读，未轮询）

### 0.1 入口状态与门禁（crctl 权威值）

| 项 | 实测 |
|---|---|
| `crctl status CR-2026-067 --workspace <KB worktree>` | `status=tech-design-reviewed`；`source.backlogSha256=c956359c20a7`（收口后 §0.2 批次刷新）；`legalNext` = `task-breakdown`(`write-dev-tasks`) / `rejected` / `withdrawn` |
| `crctl next CR-2026-067` | **`write-dev-plan`**（`humanApproval=false`，why「技术设计已审批，编写开发计划」） |
| `gateBlockers.task-breakdown` | `["文件不存在","文件不存在","目录缺失或无匹配文件"]`（= `plan.md` / `tasks/_index.yml` / `tasks/TASK-*.md` 尚未生成，符合本节点开工前预期） |
| `approval.yml#tech-design`（只读核对） | `approver: OldBoy405`、`approved-at 2026-09-15T09:20:01+08:00`、`via: crctl-approve`、`evidence-digest 99dda63a…`、`target-status: tech-design-reviewed`（提交 `64457f14`） |
| `review-loop.yml` | `review-requirement` cycle 1 / attempt 1；`review-tech-design` **cycle 1 / attempt 2**（attempt 1 = BLOCK 1 blocker，已闭合） |
| `workspace inspect CR-2026-067` | 三仓 `classification=healthy`、`dirty=false`、`localBranch/remoteBranch=true`；`operationalWorkspace` 非空 |

### 0.2 上一阶段发布收口（本节点首位执行，已发布）

```text
node <TOOLS>/skills/shared/crctl/scripts/crctl.mjs checkpoint CR-2026-067 \
  --message 技术设计已审批（上一阶段发布收口） --workspace <KB worktree>
⇒ phase=complete、changed=true、batchId=91c65d76b5d09013、txId=d3a1d0aae5e0466088579717095be881
⇒ metadataCommit=58b426a7792a6d9987788c11b20436c62663557c
⇒ repositories[]（三仓 confirmed=true）：KB 64457f14749f2bf000957e2bb714f7c8642e7216 / multica 5c1880f2125e73733b1a5bfc7501db310ab7f584 / tools 7094e492822594b971699924478ba27ccf612c42
⇒ sideEffects：KB push + KB metadata commit + KB push（metadata）
```

⇒ 技术设计人工审批写入的 `approval.yml#tech-design` 与 `tech-design-reviewed` 状态提交（`64457f14`）现已上远端，`_backlog.yml#latest-checkpoint` 由 batch `4e1ed31ef30ea1f5`（KB `e936434e`）前移为本批次；上一阶段未闭合的发布动作**已闭合**，本节点不再重复发布。

### 0.3 三仓 worktree（路径 authority = `resources[].worktreePath` 原样值，不拼接、不回退主工作区）

| repo | worktreePath | 分支 | HEAD（本节点实测） | 本 CR 角色 |
|---|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-067` | `requirement/CR-2026-067` | `58b426a7…`（§0.2 checkpoint metadata commit） | 承载 prd/sdd/plan/tasks/test-report/证据；零代码 |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-067` | `requirement/CR-2026-067` | `5c1880f2125e73733b1a5bfc7501db310ab7f584` | **零 diff**（SDD §9 `zero_diff`：不改部署副本与 Go/TS 代码） |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-067` | `requirement/CR-2026-067` | `7094e492822594b971699924478ba27ccf612c42`（= SDD §6.3 全部 tools 条目的 `commit SHA` 登记值；**diff 审计基线**） | 4 个交付文件（实现主面） |

### 0.4 测试面基线实测（本节点未改任何文件，全部为「变更前事实」，win32 / node v24.15.0）

| 项 | 实测值（本条 run） |
|---|---|
| **全量套件** `node skills/shared/crctl/scripts/test/suite-gate.mjs --run` | **`verdict=pass` / `exit_code=0` / `duration_ms=866590`（866.6 s）/ `files_executed=21` / `cases_executed=597` / `failures=0` / `skipped_file_level=0` / `converged=true` / pool=15（availableParallelism=16）/ `registry_sha256=f8d983a04656d1fae05588af9daa14b128872bc124e5bcddfd155088b53bd5bf` / `exceptions_count=0`** |
| 目标文件 | `pipeline-structure.test.mjs` 实跑 **exit 0 / 0.7 s / 74 个点号**（该文件 36 条顶层用例 + `contract-scan.test.mjs` 38 条）；本文件 **711 行**、顶层 `^test(` **36 条**、`CR-2026-055` 相关用例 **5 条**（L568 / L585 / L602 / L616 / L627）、`REVIEW_SKILLS` 常量起于 **L636** |
| `gate-registry.json` | `schema=crctl-suite-gate/v1`；`manifest.files` = **21**；`manifest.cases` 共 **21** 键（合计 578）；**`manifest.cases["pipeline-structure.test.mjs"] = 35`** 而该文件实测顶层用例 **36**（登记值落后 1，SDD D-5 的同步对象）；`exceptions = []` |
| 基线结论 | **本 CR 的起点是全绿**：NFR-1 的「保持绿」是对既有绿的保持；FR-6 的登记值同步（35 → 36）与 `suite-gate` 的**下界判据**（`f.cases < base` 才红）不冲突——变更前后均为 `36 ≥ 登记值` |

### 0.5 关键锚点（实施定位线索；行号为本节点在同一 HEAD 上实测，实施期以实时搜索为准）

| 文件 | 既有对象（本节点实测事实） | 本 CR 处置 |
|---|---|---|
| `skills/develop/write-tech-design/SKILL.md`（162 行） | L113 Step 2.6 既有实现证据段（五要素必填清单含 `commit SHA`、待核实依赖、`N/A` 可用条件）；L115 标题 `### 既有实现依赖与事实`；L117 首句；L119–L125 固定结构块（`1. repo:` 编号列表形态，实测 `grep -c '1. repo:'` = **1**）；L127 消费口径句（`sdd.explicit_existing_dependencies` + 「交叉检查」）；L129 回修模式句（唯一一句）；L131 SDD-CLOSE 义务段；L88–L90 Step 2 章节 9「批准范围」；L48 Step 1 提交口径句（实测 `crctl checkpoint` = **1**，本 CR 不删） | TASK-01：§6.5-A（L113 整段替换）、§6.5-B（L117 句 + 固定结构块 + 结构块后句）、§6.5-C（L129 原位扩写）、§6.5-D（L90 末原位追加） |
| `skills/develop/review-tech-design/SKILL.md`（176 行） | L58 Step 2 引用块「批准范围前置（CR-2026-057 FR-5/AC-5）」；L71 `### Step 2.1`；L87 依赖核验段（显式小节名 / 有序清单 / 四要素 + 旧「**并可附** `commit SHA`」，实测 `grep -c '并可附'` = **1**）；L89 核验手段段（`crctl git rev-parse HEAD` / 不执行 lint-build-test / `正文存在但未列入依赖清单的同类事实引用形成 blocker`）；L93 Step 2.2 首轮全量句（逐字）；L95–L104 Step 2.3 分级边界与五个固定前缀；节标题编号集实测 = `1,2,2.1,2.2,2.3,3,4,5,6`（「Step 1.0」的机械载体 = `### Step 1` 段内 `0. **只读 clean 前置` 条目，全文无字面 `Step 1.0`）；四反向 token 实测各 **0**、`crctl checkpoint` 实测 **0** | TASK-02：§6.5-E1（L87 / L89 两段原位替换）、§6.5-E2（L58 引用块末原位追加） |
| `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（711 行） | **L616** 目标用例 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确`：写侧 8 项 term / 评侧 4 项 term（两组 `for (const term of [...])`）；用例名与结构保持 | TASK-03：§6.5-F（两组 term 原位改写，写侧 9 项 / 评侧 6 项；不新增第二个反向用例） |
| `skills/shared/crctl/scripts/test/gate-registry.json` | L38 `"pipeline-structure.test.mjs": 35`；`exceptions: []`（L243） | TASK-04：§6.5-G（35 → 36；`exceptions` 不动） |
| `agents/quality-reviewer-agent.md` | `##` 小节实测 **7 个**，`## 评审判断` 不存在 | 零 diff（TASK-02/04 的保持性核对面，`cmd-03` / `cmd-05` 机械核对） |

### 0.6 附带项事实复核（S-2 / S-3，本节点只读复算，不改 `sdd.md` / `prd.md`）

| 附带项 | 本节点复算（命令 + 实测值） | 结论 |
|---|---|---|
| **S-2**（PRD §1.4 事实 16 写「CR-2026-055 相关 4 条」） | `grep -c "test('CR-2026-055"` → **5**（L568 / L585 / L602 / L616 / L627） | PRD 计数与实测不符；SDD 未继承该计数（§6.3 第 11/12 项只引 L616 与顶层总数 36）⇒ **本 CR 不受影响**，按实测 5 条理解；`prd.md` 冻结，不在本 CR 修 |
| **S-3**（SDD §6.3 第 27 项括注「七个评审维度」） | `skills/requirement/review-requirement/SKILL.md#Step 2` 维度表实测 **5 行**（结构完整性 / FR 可测试性 / 范围合理性 / 与规划对齐 / 依赖识别）＋ **3 条**条件契约闭包（HTTP API / crctl-CLI / Skill 契约） | 括注措辞与库内实状不符；该括注不承担本 CR 的判据（第 27 项的实际作用是「零 diff 点名对象 + `REVIEW_SKILLS` 载体」）⇒ **不影响设计唯一性与验收可达性**；已由评审登记为后续文档类 CR 面，本 CR 不改 |

两处均属**文本措辞**类缺口，落在 SDD `follow_up` 第 1 / 第 6 项与「归后续文档类 CR」的口径内（§8.A / §8.C）。

---

## 1. 交付里程碑

| # | 阶段 | 内容 | 产出 | 估算 | 状态 |
|---|---|---|---|---|---|
| M1 | 需求与架构（已完成） | 注册 → PRD → 评审 → 人工审批 → SDD → 评审 BLOCK/回修/复评 PASS → 人工架构审批 → 发布收口 | `prd.md`、`sdd.md`（832 行）、`approval.yml#tech-design`、批次 `91c65d76…` | — | **done** |
| M2 | 开发计划与拆分（本节点） | `write-dev-plan` → `write-dev-tasks` → 独立 `review-dev-plan` | `plan.md`、`tasks/TASK-01..04.md`、`tasks/_index.yml`、`status=task-breakdown` | 本条 run | **本条 run（评审由独立 reviewer run 执行）** |
| M3 | 实现 | TASK-01 → TASK-02 → TASK-03 → TASK-04（依赖序，见 §2） | tools **4 个文件**的 diff；4 个 TASK 在 `tasks/_index.yml` 标 `done` | **28 h（≈ 3.5 人天）** | pending |
| M4 | 测试 | `write-test-report`（`crctl test --plan`，6 条证据命令） | `test-report.md` ＋ `test-evidence/cmd-01…06.log` | 见 §5.4 预算 | pending |
| M5 | 代码评审与审批 | 独立 `review-code` → 人工 `approve-code` | `review-annotations/code.yml`、`approval.yml#code` | — | pending |
| M6 | 交付回写 | `delivery-agent` 的 `merge-feature-branch` → `feature-writeback` → `cr-archive` | merge 提交、`delivery/task/**`、`specs/ai-first-platform` 基线 | — | pending |

**估算口径**：四张 TASK 卡 frontmatter 的 `estimate` 之和 = **28 h**（8 + 8 + 6 + 6）；与 `crctl task init CR-2026-067 --count-hint 4` 返回的 `totalEstimateHours` 必须相等（不等时按 `write-dev-tasks` Step 4 输出 WARN，不静默覆盖）。

---

## 2. 任务依赖图

```text
TASK-01（write-tech-design 写侧四处原位修订；FR-1 / FR-4 / FR-5 写侧）
   │  改：skills/develop/write-tech-design/SKILL.md（L113 / L117–L127 / L129 / L90 末）
   │
   ├──────────────► TASK-03（L616 目标用例两组 term 改写；FR-6.1）
   │                  │  改：skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
   │                  │  （新 term 组断言 `dep-N` 固定结构与评侧引用规则 ⇒ 依赖 TASK-01/02 的文本先落地）
   │                  ▼
TASK-02（review-tech-design 评侧两处原位修订；FR-2 / FR-3 / FR-5 评侧）
   │  改：skills/develop/review-tech-design/SKILL.md（L87 / L89 / L58 末）
   │                  │
   │                  └──────────────► TASK-04（登记值同步 + 交付面/零 diff 收口；FR-6.2 / FR-7）
   │                                    改：skills/shared/crctl/scripts/test/gate-registry.json（35 → 36）
   │                                    核：diff 面恰 4 文件、zero_diff 面零改动、CI 静态面与全量套件绿
   ▼
（TASK-01 与 TASK-02 互不共用文件，可并行；二者均无 depends-on）
```

- **依赖序固定为 `{TASK-01 ∥ TASK-02} → TASK-03 → TASK-04`**：`pipeline-structure.test.mjs` 的两组 term 断言**消费**两份 SKILL 的终态文本（`dep-N` 固定结构 / `\`dep-N\` 引用规则` / `\`commit SHA\` 为必填的 40 位 SHA`），故 TASK-03 必须晚于 TASK-01/02；TASK-04 的零 diff 审计对象是**全部改动的终态 diff**，故晚于前三者。**不存在两个 TASK 并发改同一文件**。
- **无环、无悬空**：`depends-on` 只引用本 CR 的 canonical id（§9 表）；TASK-04 的依赖闭包由 TASK-03 传递覆盖，但仍逐条显式声明（审计面需要三者终态齐备）。
- **中间态不红**：TASK-01 / TASK-02 单独落地后，L616 目标用例的**旧** term 组仍全部命中（写侧 8 项与评侧 4 项在目标文本中被逐字保留），全量套件保持绿；TASK-03 落地后新 term 组亦命中（TASK-01/02 已先落地）。**FR-1~FR-5 与 FR-6 同批交付**（NFR-7），半套状态不进入交付。
- **回滚单元**（§4.0）与依赖图逆序一致。

---

## 3. 资源与分工

| 角色 | 责任 | 本 CR 范围 |
|---|---|---|
| `owners.development` = **Ray** | 技术设计、实现 4 个 TASK、开发相关审批 | tools 4 个文件全部 diff |
| `owners.test` = **Ray** | `write-test-report` 的真实证据（6 条证据命令、`sourceRevision` 绑定） | `test-report.md`、`test-evidence/cmd-01…06.log` |
| `owners.requirement` = **Ray** | 已闭合（PRD 冻结） | 零动作 |
| 独立评审方 | `review-tech-design` / `review-dev-plan` / `review-code` 一律由**新建 quality-reviewer-agent task** 执行 | 作者不自评 |

- tools worktree 为单写者（`requirement/CR-2026-067` 分支，`classification=healthy` / `dirty=false`）；**不与其他 CR 并发**（§9 AC-9②：在途仅本 CR，CR-2026-063/064/065/066 均 `archived`）。
- 实施期不启停任何数据库 / 消息队列 / 共享服务；本 CR 只改文本与一个既有数值，不部署平台 Prompt、不改 `../multica`。

---

## 4. 风险与回滚策略

### 4.0 回滚单元（逆拓扑组合，唯一事实）

| 单元 | 覆盖 | 回滚方式 | 语义 |
|---|---|---|---|
| **RU1** | TASK-01 全部（`write-tech-design/SKILL.md` 四处原位修订） | revert TASK-01 的提交 | 写侧合同回退（FR-1 / FR-4 / FR-5 写侧）；与 RU2 合批时须同批复原（FR-5 的两侧判据逐字相同） |
| **RU2** | TASK-02 全部（`review-tech-design/SKILL.md` 两处原位修订） | revert TASK-02 的提交 | 评侧合同回退（FR-2 / FR-3 / FR-5 评侧）；与 RU1 的 FR-5 半边**必须同批** |
| **RU3** | TASK-03 全部（`pipeline-structure.test.mjs` 两组 term） | revert TASK-03 的提交 | 断言面回退；**必须与 RU1/RU2 同批**（term 组断言新 `dep-N` 文本，单独回退会红） |
| **RU4** | TASK-04 全部（`gate-registry.json` 数值 + 收口审计的记录面） | revert TASK-04 的提交 | 登记值回退（35）；与 RU3 同批即回到变更前全绿态 |

**回滚边界（NFR-7）**：四条 FR 面**同批交付、同批回退**——本 CR 的 diff 只有 4 个文件且互为断言依赖（`cmd-04` 的 term 组 / 登记值与 `cmd-03` 的 SKILL 文本判据互锁），任一单独回退都会使 `cmd-01` 或 `cmd-04` 变红。回退即整批 revert 四个文件的提交，不产生「半套合同」。

### 4.1 风险表

| # | 风险 | 影响 | 缓解（本计划的机器判据 / 纪律） |
|---|---|---|---|
| R-1 | 写侧固定结构块**只加 `dep-N` 首行、未退役旧 `1. repo:` 前缀** | AC-1① 假绿（两套形态并存，违反 NFR-3） | `cmd-03` 的 `forbid('write',['1. repo:'])` 反向断言（实测基线 1 处残留 ⇒ 变更后必须 0）＋ `cmd-02` 的写侧 term 断言 |
| R-2 | 评侧只改五要素句、漏改「并可附」强制性 | AC-2④ 红（同一合同两种强度） | `cmd-03` 的 `forbid('review',['并可附'])`（实测基线 1 处）＋ `cmd-02` 的评侧 6 项 term（含 `` `commit SHA` 为必填的 40 位 SHA ``） |
| R-3 | 两侧四字段自洽判据**表述漂移**（同判据不同措辞） | AC-5① 不可机械核对 | `cmd-03` 以 `①`…`④` 首尾标记**切段后逐字节比较**两侧文本，非「看见关键词即通过」 |
| R-4 | 改写时误删 Step 2.2 首轮全量句 / Step 2.3 分级边界 / AC 闭环伪码（放宽既有门禁） | AC-9③ 红、CR-2026-066 断言失效 | `cmd-03` 的逐字 token 断言（首轮全量句、`no_design_landing(ac)` 等四项伪码、五个固定前缀、分级边界句）＋ `cmd-01` 全量套件（含 CR-2026-066 断言 A/B/C/D） |
| R-5 | 新增文字引入四个反向 token（`crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`）或删除 `write-tech-design` 现存 `crctl checkpoint` 句 | AC-2⑦ / AC-8② 红 | `cmd-05`：四 review SKILL 四 token 零命中 ＋ 写侧 `crctl checkpoint` 计数恒 **1**（实测基线，只校验不改） |
| R-6 | 交付面越界（多改文件：`crctl.mjs` / `rules.json` / `gates.json` / `pipeline-templates/**` / 矩阵 / `agents/**` / 三个 review-requirement 等 zero_diff 面） | AC-7① ② 红、违反批准范围 | `cmd-05` 的 **diff 白名单双向相等**（恰 4 文件；零 diff 前缀表逐条否定）＋ `cmd-06` 的 CI 静态面 |
| R-7 | 新增文本触发 `lint-prompts --mode enforce`（R1 手写 deny 面 / R2 裸 git / R7 advance 参数形态 / R9「下一步」映射副本 / R12 状态机副本 / R13 backlog 状态推断） | CI 红（NFR-1） | `cmd-06` 的 `lint-prompts --mode enforce` 本机等价面；TASK-01/02 的实现要点写明避让约束（新增文本不写裸 git 命令、不写状态名枚举、不写「下一步」映射） |
| R-8 | `manifest.cases` 与实测顶层用例数再次漂移（改错文件 / 改错键 / 顺手加用例） | AC-6②③ 红 | `cmd-04` 直接比较 `manifest.cases["pipeline-structure.test.mjs"]` 与实测顶层 `^test(` 计数（当前 35 vs 36 ⇒ 变更后必须 36 = 36）；并断言不新增第二个反向用例（计数恒 36） |
| R-9 | 证据命令超 `write-test-report` 节点预算（20 min / 1200 s） | 测试节点失败 | §5.4 预算：实测 866.6 s（cmd-01）＋ 其余 ≤ 6 s，合计 ≤ 873 s（余量 ≥ 327 s）；最贵的 cmd-01 排第一 |
| R-10 | 违反行尾纪律（跨行断言/解析静默降级、CRLF 假红假绿） | 假绿 / 假红 | 四个审计命令全部先 `\r\n → \n` 归一读入；解析/读取失败**硬失败**（`length < 3000` 即红、`arrs.length !== 2` 即红、`crctl git diff` 非零即红）——工程纪律 #1 |
| R-11 | 实施期发现 SDD 不可实施 | 阻断 | 出口 = 状态机既有边 `review-dev-plan:upstream-design-blocker`（`task-breakdown → tech-design-review-pending`）；**不得就地放宽** SDD 或 `zero_diff` |

---

## 5. 验收与发布策略

### 5.1 发布前 checklist（全部机器可判或逐行可核）

1. `crctl status CR-2026-067` = `developing`；`tasks/_index.yml` 四张卡全部 `done`（带 `done-at`，即时登记不积压，工程纪律 #8）。
2. tools diff **恰为** SDD §9 `scope_in` 的 4 个文件（双向相等）：`cmd-05` 输出 `tools diff paths = 4`，无「越界路径」与「缺少应改文件」。
3. `zero_diff` 面无改动：`crctl.mjs` / `rules.json` / `gates.json` / `suite-gate.mjs` / `contract-scan.test.mjs` / `lint-prompts.mjs` / `pipeline-templates/**` / `agent-skill-matrix.yml` / `AGENT-SKILL-MATRIX.md` / `agents/**` / `dir-graph.yaml` / `ARCHITECTURE.md` / 三个 `write-dev-*` SKILL / `review-requirement` / `review-code`（`cmd-05`）。
4. `cmd-01` 全量套件 `verdict=pass` / `failures=0` / `files_executed=21` / `skipped_file_level=0` / `cases_executed=597`；`cmd-02` exit 0；`cmd-03` / `cmd-04` / `cmd-05` 在变更后 **failures = 0**；`cmd-06` exit 0。
5. `cmd-04` 的 `top-level test( = 36` 与 `manifest.cases = 36` **同批一致**，`exceptions` 为空数组（**不签任何新例外**）。
6. `cmd-03` 的两侧①~④**逐字节相同**（`cut(W) === cut(V)`）且四项判据齐备。
7. `sourceRevision` 绑定：6 条证据命令均为 `repo=tools`，与 tools worktree HEAD 一致（由 `crctl test` 发布，本计划不重算）。

### 5.2 发布与观测

- **本 CR 自身的发布点**：`review-dev-plan` PASS 之后的 `push-progress`（`message=开发计划与任务`）由该评审 run 的 PASS 分支执行（每次评审 PASS 一次；BLOCK 分支不发布）。本节点自身**不再发布**（上一阶段发布收口已在 §0.2 闭合；本节点的 `plan.md` / `tasks/**` / 状态提交由评审 PASS 的 checkpoint 搭车发布）。
- **交付后观测**：本 CR 不新增观测指标 / SLO / 计数门禁（NFR-2）；`本轮新增：` 仍只承担 blocker 文本分类（FR-3.3）。
- **`dep-N` 新形态的生效时点**：本 CR 的提交合并后，其后写 SDD 的 CR 适用新口径（SDD D-6 / §7.3 的时序差）；本 CR 自身的 SDD 按实施前形态，**无追溯效力**。

### 5.3 例外治理与零例外口径

- `suite-gate` 的 `exceptions` 是本 CR 唯一例外登记处；交付态必须为**显式空数组**（`cmd-01` 的 `exceptions_count=0` + `cmd-04` 的 `exceptions` 断言双向保证）。
- 失败向量一律就地修（不回改被断言文件、不降级为下界、不新增用例掩盖）；跨行解析/读取失败**硬失败**（工程纪律 #1）。

### 5.4 预算（证据命令集）

`write-test-report` 节点 `timeoutMinutes=20`（1200 s，实测 `pipeline-templates/code-implementation.pipeline.json#00000000-0000-0000-0015-000000000007`）。预算表（本节点实测，按 §6.2 顺序执行）：

| 证据ID | 预算（本节点实测） | 依据 |
|---|---|---|
| cmd-01 | **866.6 s**（`duration_ms=866590`） | §0.4 基线实跑（21 文件 / 597 用例 / pool=15，win32 / node v24.15.0） |
| cmd-02 | ≤ 5 s（实测 **0.7 s**） | §0.4 目标文件实跑 |
| cmd-03 | ≤ 5 s（实测 **0.2 s**） | §6.3 干跑 |
| cmd-04 | ≤ 5 s（实测 **0.2 s**） | §6.3 干跑 |
| cmd-05 | ≤ 5 s（实测 **0.2 s**） | §6.3 干跑 |
| cmd-06 | ≤ 10 s（实测 **1.6 s**） | §6.3 干跑（CI 静态四步 + pipeline JSON 结构断言） |
| **合计** | **≤ 897 s**（实测 ≈ **869.5 s**；< 1200 s，余量 ≥ 303 s） | — |

**顺序策略**：cmd-01（最贵且是回归主证据）排第一——它同时覆盖 AC-6④、AC-8 与 NFR-1；其余五条都在秒级，任一条红都不影响 cmd-01 的日志已落盘。

**估算总工时 = 28 h**（= 四张 TASK 卡 `estimate` 之和 = §9 预分配之和；与 `crctl task init --count-hint 4` 的 `totalEstimateHours` 交叉校验）。

---

## 6. 两张稳定表（契约必填节，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 既有实现事实唯一表达（AC-1①~⑥） | §2.2 条目形状 ＋ §4.1 分配算法 ＋ §6.5-A（Step 2.6 证据段）/ §6.5-B（`### 既有实现依赖与事实` 固定结构 + 消费口径句） | CR-2026-067-TASK-01 | cmd-03（AC-1 六项文本判据：`dep-N` 固定结构 / 只引用不重述 / 40 位 SHA 必填 / 待核实依赖前提资格 / `N/A` 条件 / 编号生命周期；旧 `1. repo:` 零残留）、cmd-02（写侧 9 项 term 执行面） | RU1 |
| FR-2 评侧 `dep-N` 核验与两侧同口径（AC-2①~⑦） | §4.2 核验算法 ＋ §6.5-E1（Step 2.1 两段：五要素 + 引用关系式 + SHA 必填 + 诚实边界） | CR-2026-067-TASK-02 | cmd-03（AC-2①~⑦ 文本判据：五要素 / 引用必须已定义 / 未承载事实成 blocker / SHA 必填且「并可附」零残留 / 扫描边界与 Prompt 合同 / Step 编号集 / 四反向 token）、cmd-02（评侧 6 项 term 执行面） | RU2 |
| FR-3 首轮全量检查保持原样（AC-3①~③） | §4.6 保持性清单 ＋ §6.4 零改动核对清单 | CR-2026-067-TASK-02 | cmd-03（Step 2.2 首轮全量句逐字存在 ＋ `quality-reviewer-agent.md` `##` 小节数 = 7 且无 `## 评审判断`）、cmd-05（`agents/**` 零 diff） | RU2 |
| FR-4 状态链整体重证（AC-4①~④） | §4.3 ＋ §6.5-C（回修句原位扩写为一句群） | CR-2026-067-TASK-01 | cmd-03（四项判据 token：整体重证四维 / 不得只修一格 / 同一标识符唯一裁决 / 不扩散） | RU1 |
| FR-5 批准范围四字段自洽（AC-5①~③） | §4.4 ＋ §6.5-D（写侧章节 9 末追加）/ §6.5-E2（评侧批准范围前置块末追加） | CR-2026-067-TASK-01（关联 CR-2026-067-TASK-02：评侧同判据半边） | cmd-03（两侧 `①`~`④` 切段后**逐字节相同** ＋ 写侧「不新增第五个字段」尾句 ＋ 评侧「任一一型命中 → blocker / upstream-design-blocker」尾句） | RU1（写侧半）∪ RU2（评侧半） |
| FR-6 测试断言与门禁基线同步（AC-6①~⑤） | §4.5 ＋ §6.5-F（L616 两组 term）/ §6.5-G（`manifest.cases` 35 → 36） | CR-2026-067-TASK-03（关联 CR-2026-067-TASK-04：登记值半边） | cmd-04（term 组集合相等 ＋ 顶层用例数 36 ＋ 登记值一致 ＋ `exceptions` 空 ＋ 退役字段名零命中）、cmd-02（目标用例执行面）、cmd-01（`suite-gate --run` 全绿 / `exceptions_count=0`） | RU3 ∪ RU4 |
| FR-7 边界与零新增（AC-7①~③、AC-9①~③） | §1.2 变更面 ＋ §9 `scope_in` / `scope_out` / `zero_diff` ＋ §4.6 保持性约束 | CR-2026-067-TASK-04（关联 CR-2026-067-TASK-01/02/03：各自文件级的零改动半边） | cmd-05（diff 白名单双向相等 ＋ zero_diff 前缀表 ＋ 写侧 `crctl checkpoint` 计数 = 1 ＋ 四 review SKILL 反向 token 零命中）、cmd-06（CI 静态面：lint-prompts / skill matrix / agents contract / pipeline JSON 结构） | RU1∪RU2∪RU3∪RU4 |

**表注（防假绿）**

① 「验收证据」列按「主责命令在前」列出覆盖本行验收面的 `cmd-NN`；每个 `cmd-NN` 与 §6.2 证据命令表的 `证据ID`、`crctl test` 机器区 `commands` 1-based 下标、`test-evidence/cmd-NN.log` 三者全等（CR-2026-057 FR-16）。**7 个 in-scope FR 各出现一次**；四张 TASK 全部在表中出现（主责 TASK 唯一，关联 TASK 不改变主责），与 `tasks/_index.yml#id` 双向一致。
② `cmd-01`（全量套件）与 `cmd-02`（目标文件定点）**不是假绿**：`cmd-02` 直接执行 L616 目标用例（含改写后的两组 term，任一项缺失即 `assert.ok` 红），`cmd-01` 覆盖「无回归 + CR-2026-066 既有断言 A/B/C/D + `exceptions` 为空」；两者互补而非互相替代。
③ **文本判据的存在性不由命令退出码单独承担**：`cmd-03` / `cmd-04` / `cmd-05` 在同一个 `-e` 脚本内**先断言读取非空**（`length < 3000` 即红、`arrs.length !== 2` 即红、`crctl git diff` 退出码非零即红），再逐 token 判定并逐条打印 `FAIL`；不存在「匹配不到 → 空集 → 静默通过」的降级路径（NFR-5 / 工程纪律 #1）。
④ **两侧「同表述」的机械判据是逐字节比较**，不是关键词命中：`cmd-03` 以 `① \`scope_in\` 与 \`zero_diff\` 不得对同一对象同时要求` 与 `④ \`follow_up\` 不得承载当前 AC 的必要条件` 为切段标记，取两侧切片后要求 `cw === cv`（AC-5① 可 diff 核对）。
⑤ **证据命令与 SDD 的关系**：`cmd-01` = CI 步骤 `crctl full test suite` 逐字；`cmd-06` = CI 其余五步（lint-prompts / skill matrix / agents contract / pipeline JSON 结构 / writeback 单测）的**本机等价面**（Windows 侧；Ubuntu 侧由外部 CI 承担，**不属本轮 run 拥有、不等待**）；`cmd-02`…`cmd-05` 是本计划自有的只读审计命令（**不新增测试文件、不新增 CI step**——`gate-registry.json` 的 `manifest.files` 保持 21 已双向保证文件集合不变）。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["skills/shared/crctl/scripts/test/suite-gate.mjs","--run"]` | 1080 |
| cmd-02 | tools | . | node | `["--test","--test-reporter=dot","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs","skills/shared/crctl/scripts/test/contract-scan.test.mjs"]` | 300 |
| cmd-03 | tools | . | node | ["-e", "const fs=require('fs'),P=require('path');const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL,BT=String.fromCharCode(96);const read=p=>fs.readFileSync(P.join(R,p),'utf8').split(CR).join(NL);const bad=[];const W=read('skills/develop/write-tech-design/SKILL.md'),V=read('skills/develop/review-tech-design/SKILL.md');const need=(label,t,toks)=>{if(t.length<3000){bad.push(label+' 读空或过短 length='+t.length);}for(const k of toks){if(t.indexOf(k)<0){bad.push(label+' 缺 '+k);}}};const forbid=(label,t,toks)=>{for(const k of toks){if(t.indexOf(k)>=0){bad.push(label+' 残留 '+k);}}};need('write',W,['### 既有实现依赖与事实','dep-1','  repo:','  relative path:','  stable symbol/对象:','  commit SHA: <40-character SHA>','  依赖结论:','编号按正文首次出现顺序分配、只增不改','编号不复用','实现事实只在该表定义一次','SDD 正文只能写','不得在正文重新陈述','为必填的 40 位 SHA','待核实依赖','不得继续作为方案前提','只有本节与正文均无既有实现依赖时','不得用 N/A 掩盖正文中的事实依赖','必须重证该状态链的完整输入维度、分支、可见动作与对应 AC','不得只修被点名的那一格','同一标识符、锚点或 testid 在全文只能有一个裁决','未受该根因影响的已确认方案不得重写','不新增第五个字段、不新增独立 ledger 文件、不新增状态、不新增评审维度名']);forbid('write',W,['1. repo:']);need('review',V,['名为“既有实现依赖与事实”的显式小节','按正文首次依赖出现顺序维护有序清单','五要素','正文出现的 '+BT+'dep-N'+BT+' 必须在表中已定义','未通过 '+BT+'dep-N'+BT+' 引用承载','为必填的 40 位 SHA','不由 reviewer 扫描全仓库','不做全仓库无界扫描','Prompt 合同','不宣称对自由文本事实的机械识别','不新增 crctl 校验面、lint 规则或 annotation dimension','有序清单','正文同类事实是否漏列','首轮必须完成全部适用维度后再统一生成 verdict，不得在首个 blocker 处提前结束；合并同根因问题、拆分不同根因问题，同一轮 blockers 同时包含独立根因','no_design_landing(ac)','landing_conflicts_with_prd(ac)','prerequisite_filters_required_target(ac)','不得仅因缺少里程碑、TASK owner、任务拆分、工时、完成标志','已解决：','部分解决：','未解决：','本轮新增：','范围外：','任一一型命中','upstream-design-blocker']);forbid('review',V,['并可附','crctl checkpoint','push-progress 之前','push-progress 之后','统一 checkpoint 后']);const A='① '+BT+'scope_in'+BT+' 与 '+BT+'zero_diff'+BT+' 不得对同一对象同时要求',B='④ '+BT+'follow_up'+BT+' 不得承载当前 AC 的必要条件',C2='② 外部治理规则强制修改时',C3='③ 不得用 '+BT+'scope_out'+BT+' 隐藏当前交付必须发生的治理修改';const cut=t=>{const i=t.indexOf(A),j=t.indexOf(B);return i<0?null:(j<0?null:t.slice(i,j+B.length));};const cw=cut(W),cv=cut(V);if(!cw){bad.push('写侧四字段自洽判据段未取到');}else if(!cv){bad.push('评侧四字段自洽判据段未取到');}else if(cw!==cv){bad.push('两侧四字段自洽判据非逐字相同');}else{if(cw.indexOf(C2)<0){bad.push('自洽判据段缺 '+C2);}if(cw.indexOf(C3)<0){bad.push('自洽判据段缺 '+C3);}}const steps=t=>t.split(NL).filter(l=>l.indexOf('### Step ')===0).map(l=>{const s=l.slice(9),k=s.indexOf(' — ');return k<0?s.trim():s.slice(0,k).trim();}).join(',');const ew=steps(W),ev=steps(V);if(ew!=='1,2,2.5,2.6,3,4,5'){bad.push('write Step 编号集变化 '+ew);}if(ev!=='1,2,2.1,2.2,2.3,3,4,5,6'){bad.push('review Step 编号集变化 '+ev);}if(V.indexOf('0. **只读 clean 前置')<0){bad.push('review 缺 Step 1 的只读 clean 前置条目');}const q=read('agents/quality-reviewer-agent.md');const qs=q.split(NL).filter(l=>l.indexOf('## ')===0).length;if(qs!==7){bad.push('quality-reviewer-agent ## 小节数='+qs);}if(q.indexOf('## 评审判断')>=0){bad.push('quality-reviewer-agent 出现 评审判断 小节');}if(bad.length){console.log('audit-skill failures = '+bad.length);for(const x of bad){console.log('FAIL '+x);}process.exit(1);}console.log('audit-skill failures = 0');"] | 300 |
| cmd-04 | tools | . | node | ["-e", "const fs=require('fs'),P=require('path');const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL,SQ=String.fromCharCode(39),BT=String.fromCharCode(96);const read=p=>fs.readFileSync(P.join(R,p),'utf8').split(CR).join(NL);const bad=[];const T=read('skills/shared/crctl/scripts/test/pipeline-structure.test.mjs');if(T.length<3000){bad.push('pipeline-structure.test.mjs 读空');}const CASE='CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确';const i=T.indexOf('test('+SQ+CASE);if(i<0){bad.push('目标用例缺失 '+CASE);}else{const j=T.indexOf('test(',i+5);const body=T.slice(i,j<0?T.length:j);const arrs=[];let p=0;while(true){const a=body.indexOf('for (const term of [',p);if(a<0){break;}const b=body.indexOf('])',a);if(b<0){arrs.push(null);break;}const inner=body.slice(a+20,b);const items=[];for(const piece of inner.split(',')){const x=piece.trim();if(x.length>1&&x.charAt(0)===SQ&&x.charAt(x.length-1)===SQ){items.push(x.slice(1,-1));}}arrs.push(items);p=b+2;}if(arrs.length!==2){bad.push('目标用例 term 组数='+arrs.length+'（期望 2）');}else{const wantW=['### 既有实现依赖与事实','正文首次出现顺序','dep-N','repo:','relative path:','stable symbol/对象:','commit SHA:','依赖结论:','sdd.explicit_existing_dependencies'];const wantV=['名为“既有实现依赖与事实”的显式小节','有序清单',BT+'dep-N'+BT+' 引用规则',BT+'commit SHA'+BT+' 为必填的 40 位 SHA','sdd.explicit_existing_dependencies','正文同类事实是否漏列'];for(const pair of [[0,wantW],[1,wantV]]){const got=arrs[pair[0]],want=pair[1];const miss=want.filter(x=>got.indexOf(x)<0),extra=got.filter(x=>want.indexOf(x)<0);if(miss.length+extra.length>0){bad.push('term 组'+(pair[0]+1)+' 缺['+miss.join(',')+'] 多['+extra.join(',')+']');}}}}const n=T.split(NL).filter(l=>l.indexOf('test(')===0).length;if(n!==36){bad.push('顶层 test( 计数='+n+'（基线 36）');}const g=JSON.parse(read('skills/shared/crctl/scripts/test/gate-registry.json'));const gc=g.manifest&&g.manifest.cases?g.manifest.cases['pipeline-structure.test.mjs']:undefined;if(gc!==n){bad.push('manifest.cases='+gc+' 与顶层用例数 '+n+' 不一致');}if(!Array.isArray(g.exceptions)){bad.push('exceptions 非数组');}else if(g.exceptions.length!==0){bad.push('exceptions 非空数组');}for(const f of ['skills/develop/write-tech-design/SKILL.md','skills/develop/review-tech-design/SKILL.md','skills/shared/crctl/scripts/test/pipeline-structure.test.mjs','skills/shared/crctl/scripts/test/gate-registry.json']){const t=read(f);for(const k of ['recoverCommand','recover_command']){if(t.indexOf(k)>=0){bad.push(f+' 命中退役字段名 '+k);}}}if(bad.length){console.log('audit-test failures = '+bad.length);for(const x of bad){console.log('FAIL '+x);}process.exit(1);}console.log('audit-test failures = 0; top-level test( = '+n+'; manifest.cases = '+gc);"] | 300 |
| cmd-05 | tools | . | node | ["-e", "const cp=require('child_process'),fs=require('fs'),P=require('path');const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL;const read=p=>fs.readFileSync(P.join(R,p),'utf8').split(CR).join(NL);const bad=[];const base='7094e492822594b971699924478ba27ccf612c42';const CRCTL=P.join(R,'skills/shared/crctl/scripts/crctl.mjs');const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only',base,'--cwd',R],{encoding:'utf8',shell:false});if(r.status!==0){bad.push('crctl git diff 失败 status='+r.status);}else{const parts=String(r.stdout).split(NL);const bi=parts.findIndex(l=>l.trim()==='{');const changed=parts.slice(0,bi<0?parts.length:bi).map(s=>s.trim()).filter(Boolean);console.log('tools diff paths = '+changed.length);for(const f of changed){console.log('  '+f);}const WL=['skills/develop/write-tech-design/SKILL.md','skills/develop/review-tech-design/SKILL.md','skills/shared/crctl/scripts/test/pipeline-structure.test.mjs','skills/shared/crctl/scripts/test/gate-registry.json'];const ZERO=['skills/shared/crctl/scripts/crctl.mjs','skills/shared/controlled-shell/rules.json','skills/shared/crctl/gates.json','skills/shared/crctl/scripts/test/suite-gate.mjs','skills/shared/crctl/scripts/test/contract-scan.test.mjs','skills/shared/crctl/scripts/lint-prompts.mjs','pipeline-templates/','agent-skill-matrix.yml','AGENT-SKILL-MATRIX.md','agents/','dir-graph.yaml','ARCHITECTURE.md','skills/develop/write-dev-plan/SKILL.md','skills/develop/write-dev-tasks/SKILL.md','skills/develop/review-dev-plan/SKILL.md','skills/requirement/review-requirement/SKILL.md','skills/develop/review-code/SKILL.md'];for(const f of changed){if(WL.indexOf(f)<0){bad.push('越界路径 '+f);}for(const z of ZERO){if(f.indexOf(z)===0){bad.push('zero_diff 面被改动 '+f);}}}for(const f of WL){if(changed.indexOf(f)<0){bad.push('缺少应改文件 '+f);}}}const W=read('skills/develop/write-tech-design/SKILL.md');const cnt=(t,k)=>t.split(k).length-1;if(cnt(W,'crctl checkpoint')!==1){bad.push('write-tech-design crctl checkpoint 计数='+cnt(W,'crctl checkpoint')+'（应为 1，不删该句）');}for(const f of ['skills/requirement/review-requirement/SKILL.md','skills/develop/review-tech-design/SKILL.md','skills/develop/review-dev-plan/SKILL.md','skills/develop/review-code/SKILL.md']){const t=read(f);if(t.length<3000){bad.push(f+' 读空');}for(const k of ['crctl checkpoint','push-progress 之前','push-progress 之后','统一 checkpoint 后']){if(t.indexOf(k)>=0){bad.push(f+' 命中 '+k);}}}if(bad.length){console.log('audit-diff failures = '+bad.length);for(const x of bad){console.log('FAIL '+x);}process.exit(1);}console.log('audit-diff failures = 0');"] | 300 |
| cmd-06 | tools | . | node | ["-e", "const cp=require('child_process'),fs=require('fs'),P=require('path');const R=process.cwd(),NL=String.fromCharCode(10);const read=p=>fs.readFileSync(P.join(R,p),'utf8').split(String.fromCharCode(13)+NL).join(NL);const bad=[];const run=(label,args)=>{const r=cp.spawnSync(process.execPath,args,{cwd:R,encoding:'utf8',shell:false});const s=String(r.stdout==null?'':r.stdout),e=String(r.stderr==null?'':r.stderr);console.log('['+label+'] exit='+r.status);if(r.status!==0){bad.push(label+' exit='+r.status);console.log(s.slice(-800));console.log(e.slice(-800));}};run('lint-prompts',['skills/shared/crctl/scripts/lint-prompts.mjs','--mode','enforce']);run('skill-matrix',['skills/shared/crctl/scripts/check-skill-matrix.mjs']);run('agents-contract',['skills/shared/crctl/scripts/check-agents-contract.mjs']);const wb=fs.readdirSync(P.join(R,'skills/writeback/scripts/test')).filter(f=>f.endsWith('.test.mjs')).map(f=>'skills/writeback/scripts/test/'+f);if(wb.length<1){bad.push('writeback 测试文件未枚举到（硬失败）');}run('writeback-tests',['--test','--test-reporter=dot'].concat(wb));const active=new Set();let cur=null;for(const l of read('skills/_index.yml').split(NL)){const t2=l.trim();if(t2.indexOf('- id:')===0){cur=t2.slice(5).trim();continue;}if(cur!==null&&t2==='status: active'){active.add(cur);}}const pf=fs.readdirSync(P.join(R,'pipeline-templates')).filter(f=>f.endsWith('.pipeline.json'));if(pf.length<1){bad.push('pipeline 模板未枚举到（硬失败）');}for(const f of pf){const d=JSON.parse(read('pipeline-templates/'+f));if(!(d.id&&d.triggerCommand&&Array.isArray(d.inputs)&&Array.isArray(d.nodes))){bad.push(f+' 缺基础字段');}const ids=d.nodes.map(n=>n.id);if(new Set(ids).size!==ids.length){bad.push(f+' 重复 node id');}for(const n of d.nodes){if(n.kind==='skill'&&!n.ref){bad.push(f+' skill 节点缺 ref');}if(n.kind==='skill'&&n.ref&&!active.has(n.ref)){bad.push(f+' inactive ref '+n.ref);}const rl=n.reviewLoop;if(rl){if(rl.repairNodeId&&ids.indexOf(rl.repairNodeId)<0){bad.push(f+' 悬空 repairNodeId');}const rp=rl.replayNodes?rl.replayNodes:[];for(const x of rp){if(ids.indexOf(x.nodeId)<0){bad.push(f+' 悬空 replayNodes');}}}}}console.log('pipeline structure checked = '+pf.length+' active skills = '+active.size);if(bad.length){console.log('audit-ci failures = '+bad.length);for(const x of bad){console.log('FAIL '+x);}process.exit(1);}console.log('audit-ci failures = 0');"] | 300 |

> **转录纪律**：`cmd-03`…`cmd-06` 的 args 是**单个 `-e` 参数**（数组第二个元素），`write-test-report` 逐字转录本表 cell（`JSON.stringify` 往返逐字相同即可）；四个脚本**不含**双引号 / 反斜杠 / 换行 / 竖线（需要换行常量的地方用 `String.fromCharCode(10)`／`String.fromCharCode(13)` 构造；单引号用 `String.fromCharCode(39)` 构造；路径一律正斜杠），因此不存在转义歧义。

#### 6.2.1 `cmd-03` 说明（AUDIT-SKILL，只读）

覆盖四类判据：**(a) 写侧合同**（`### 既有实现依赖与事实` 小节 + `dep-N` 固定结构（`dep-1` 首行 + 五字段缩进两格 + `commit SHA: <40-character SHA>`）+ 只引用不重述 + 编号生命周期 + 待核实依赖前提资格 + `N/A` 可用条件；并**反向断言**旧 `1. repo:` 零残留）；**(b) 写侧回修四判据与批准范围写侧尾句**；**(c) 评侧合同**（显式小节名 + 有序清单 + 五要素 + 「正文出现的 `dep-N` 必须在表中已定义」+ 「未通过 `dep-N` 引用承载」+ SHA 必填 + 扫描边界 + Prompt 合同 + 不新增 crctl 校验面/lint/annotation dimension + Step 2.2 首轮全量句 + AC 闭环伪码 + 五个固定前缀 + 分级边界 + 评侧批准范围尾句；并**反向断言**「并可附」与四个反向 token 零命中）；**(d) 两侧①~④逐字节相同**、**Step 编号集**（写侧 `1,2,2.5,2.6,3,4,5`；评侧 `1,2,2.1,2.2,2.3,3,4,5,6` + Step 1 的 `0. **只读 clean 前置` 条目）、`agents/quality-reviewer-agent.md` 的 `##` 小节数 = 7。

#### 6.2.2 `cmd-04` 说明（AUDIT-TEST，只读）

覆盖五类判据：**(a)** L616 目标用例存在（用例名逐字）；**(b)** 该用例的两组 term **集合相等**（写侧 9 项 / 评侧 6 项，缺项与多项分别报出）；**(c)** 顶层 `^test(` 计数 = 36（不减少、不新增第二个反向用例）；**(d)** `gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]` 与该计数一致 且 `exceptions` 为显式空数组；**(e)** 4 个交付文件内 `recoverCommand` / `recover_command` 零命中（`RETIRED_RECOVERY` 退役字段名的定点面）。

#### 6.2.3 `cmd-05` 说明（AUDIT-DIFF，只读）

覆盖四类判据：**(a)** tools diff 面（相对基线 `7094e492…`）**恰为 4 个文件**（白名单双向相等）；**(b)** `zero_diff` 前缀表（`crctl.mjs` / `rules.json` / `gates.json` / `suite-gate.mjs` / `contract-scan.test.mjs` / `lint-prompts.mjs` / `pipeline-templates/` / `agent-skill-matrix.yml` / `AGENT-SKILL-MATRIX.md` / `agents/` / `dir-graph.yaml` / `ARCHITECTURE.md` / 三个 `write-dev-*` SKILL / `review-requirement` / `review-code`）**无命中**；**(c)** 写侧 `crctl checkpoint` 计数恒 1（不删该句）；**(d)** 四个 review SKILL 的 `crctl checkpoint` 与三个旧 checkpoint 前提句 token 零命中。

#### 6.2.4 `cmd-06` 说明（AUDIT-CI，只读）

覆盖 CI 五步的本机等价面：**(a)** `lint-prompts.mjs --mode enforce`；**(b)** `check-skill-matrix.mjs`；**(c)** `check-agents-contract.mjs`；**(d)** `skills/writeback/scripts/test/*.test.mjs`（枚举后整批跑）；**(e)** pipeline JSON 结构断言（重复 node id / skill 节点 `ref` 存在且在 `skills/_index.yml` 为 active / `reviewLoop.repairNodeId` 与 `replayNodes[]` 无悬空 / `id` / `triggerCommand` / `inputs[]` / `nodes[]` 齐备）。**不新增 CI 面**，只作 `NFR-1` 与 AC-7 的本机证据。

### 6.3 干跑/可达性记录（本条 run 按同一语义实跑，未改任何文件）

干跑语义 = `spawnSync(executable, args, { cwd: <repo worktree>/<cwd>, shell:false })`；下表均为**变更前基线**实测（本条 run，win32 / node v24.15.0）。

| 证据ID | 可达性 | 本条 run 实测 | 结论（变更前 / 变更后预期） |
|---|---|---|---|
| cmd-01 | 可达 | **exit 0 / 866.6 s / 21 文件 / 597 用例 / failures=0 / skipped_file_level=0 / exceptions_count=0 / verdict=pass** | 变更前全绿；变更后须仍 `verdict=pass` / `failures=0`（登记值 35 → 36 是下界，不改变判据语义） |
| cmd-02 | 可达 | **exit 0 / 0.7 s / 74 点号**（目标文件两条文件级实跑） | 变更前绿（旧 term 组）；变更后须在新 term 组下仍绿（TASK-01/02 先落地） |
| cmd-03 | 可达 | **exit 1 / 25 failures**（写侧缺 13 项含 `dep-1` / 五字段缩进 / 编号生命周期 / 整体重证四判据 / 写侧尾句，且残留 `1. repo:`；评侧缺 9 项含 `五要素` / 引用关系式 / SHA 必填 / Prompt 合同 / 评侧尾句，且残留 `并可附`；两侧①~④段未取到） | 实施前基线；**25 项逐条对应 TASK-01/02 的交付物**（无一项落在零 diff 面），故该命令是有效鉴别器而非恒真式 |
| cmd-04 | 可达 | **exit 1 / 3 failures**（term 组 1 缺 `dep-N`；term 组 2 缺 `` `dep-N` 引用规则 `` 与 `` `commit SHA` 为必填的 40 位 SHA ``；`manifest.cases=35` 与顶层用例数 36 不一致） | 实施前基线；3 项分别对应 TASK-03（2 项）与 TASK-04（1 项） |
| cmd-05 | 可达 | **exit 1 / 4 failures**（`tools diff paths = 0` ⇒ 4 项「缺少应改文件」） | 实施前基线；实施后须 `tools diff paths = 4` 且 failures = 0 |
| cmd-06 | 可达 | **exit 0**（`lint-prompts` / `skill-matrix` / `agents-contract` / `writeback-tests` 各 exit 0；`pipeline structure checked = 8` / `active skills = 56`；1.6 s） | 变更前与变更后均须 exit 0（本 CR 不新增静态面） |

- 六个命令均为**只读**：不写账本、不写登记面、不新增文件（`gate-registry.json` 的 `manifest.files` 恒 21、`manifest.cases` 只改一个既有数值）。
- 干跑后 `git status --short`（tools worktree）为**空**（零残留）。

---

## 7. AC/业务闭环覆盖矩阵（契约必填节，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 写侧 `dep-N` 固定结构与六项判据 | §6.5-A ＋ §6.5-B ＋ §2.2 ＋ §4.1 | CR-2026-067-TASK-01 | cmd-03；cmd-02 |
| AC-2 评侧五要素 / 引用关系式 / SHA 必填 / 诚实边界 / Step 编号 / 反向 token | §6.5-E1 ＋ §4.2 ＋ §1.4.2 | CR-2026-067-TASK-02 | cmd-03；cmd-02 |
| AC-3 首轮全量句与 Agent Prompt 零改动 | §4.6 ＋ §6.4 | CR-2026-067-TASK-02 | cmd-03（逐字句 + 7 小节）；cmd-05（`agents/**` 零 diff） |
| AC-4 回修整体重证四判据 | §6.5-C ＋ §4.3 | CR-2026-067-TASK-01 | cmd-03 |
| AC-5 两侧四字段自洽判据同表述 + 冲突在 SDD 阶段成 blocker + 无第五字段 | §6.5-D ＋ §6.5-E2 ＋ §4.4 | CR-2026-067-TASK-01（关联 CR-2026-067-TASK-02） | cmd-03（切段逐字节相同 + 两侧尾句） |
| AC-6 目标用例两组 term / 用例数不减 / 登记值一致 / `suite-gate --run` 全绿零例外 / `RETIRED_RECOVERY` 零命中 | §6.5-F ＋ §6.5-G ＋ §4.5 | CR-2026-067-TASK-03（关联 CR-2026-067-TASK-04） | cmd-04；cmd-02；cmd-01 |
| AC-7 交付 diff 恰 4 文件 + 零新增 + `zero_diff` 文件零改动 | §1.2 ＋ §9 | CR-2026-067-TASK-04（关联 CR-2026-067-TASK-01/02/03） | cmd-05；cmd-06 |
| AC-8 CR-2026-066 既有断言全绿且未放宽 | §4.6 ＋ §6.4 | CR-2026-067-TASK-04（关联 CR-2026-067-TASK-02：四个 review SKILL 反向 token 面） | cmd-01（断言 A/B/C/D 随套件执行）；cmd-05（反向 token 与零 diff） |
| AC-9 与 CR-P2 面零 diff / 串行 / 只收紧不放宽 | §9 ＋ §6.4 ＋ §9 `zero_diff` | CR-2026-067-TASK-04 | cmd-05（`write-dev-*` / `review-dev-plan` / `code-implementation.pipeline.json` 零 diff）；cmd-03（Step 2.1 伪码 / Step 2.3 分级边界与前缀保留） |
| 业务闭环：同一条事实在两侧只有一个强度（`commit SHA` 必填） | §7.3 ＋ §6.5-A/E1 | CR-2026-067-TASK-01（写侧半）＋ CR-2026-067-TASK-02（评侧半） | cmd-03（两侧「为必填的 40 位 SHA」+ 评侧「并可附」零残留）；cmd-04（评侧 term 命中） |
| 业务闭环：正文引用必须已定义（关系式而非集合比较） | §4.2 ＋ §6.5-E1 | CR-2026-067-TASK-02 | cmd-03 |
| 业务闭环：判据唯一事实源（不在 Agent Prompt 造第二份） | §4.6 ＋ FR-3.2 | CR-2026-067-TASK-02 | cmd-03（7 小节 / 无 `## 评审判断`）；cmd-05（`agents/**` 零 diff） |
| 业务闭环：断言与其同步的是同一份文本（测试无假绿） | §4.5 ＋ NFR-5 | CR-2026-067-TASK-03 | cmd-04（term 集合相等，非子串包含式抽样）；cmd-02 |
| 业务闭环：只收紧不放宽（既有门禁判据逐字保留） | §6.4 ＋ AC-9③ | CR-2026-067-TASK-04 | cmd-03（逐字 token）；cmd-01（CR-2026-066 断言全绿） |

> **关键 AC 唯一 owner 说明（机械可判）**
> - **AC-1 / AC-4 / AC-5（写侧半）唯一 owner = TASK-01**（`write-tech-design` 文本的实际产生层；证据 cmd-03、cmd-02）。
> - **AC-2 / AC-3 / AC-5（评侧半）唯一 owner = TASK-02**（`review-tech-design` 文本的实际产生层；证据 cmd-03、cmd-02、cmd-05）。
> - **AC-6 唯一 owner = TASK-03**（`pipeline-structure.test.mjs` 的 term 组实际产生层；登记值半边由 TASK-04 承担并在 §6.1 记为关联）。
> - **AC-7 / AC-8 / AC-9 唯一 owner = TASK-04**（交付面与零 diff 收口的实际责任层；证据 cmd-05、cmd-06、cmd-01）。
> - 四张 TASK 均在矩阵中出现，与 `tasks/_index.yml#id` 集双向一致；业务闭环行不与关键 AC 行争用同一证据语义。
> - **无阻断**：全部 AC 的验收证据在实施后**可达**（§6.3 干跑记录；本 CR 不依赖未来证据，无「延期验证点」）。

---

## 8. 附带项与残余项收口对照

### A. 协调者转交的 2 条 non-blocking 附带项（本轮逐条处置）

| # | 附带项 | 处置 | 落点 |
|---|---|---|---|
| **S-2**（`review-tech-design` attempt 1/3 的 `范围外` suggestion：PRD §1.4 事实 16 的「CR-2026-055 相关 4 条」与实测 5 条不符） | **按实际事实理解 + 保留理由**：本节点复算 `grep -c "test('CR-2026-055"` = **5**（L568 / L585 / L602 / L616 / L627），本计划全部按 5 条理解；SDD 未继承该计数（§6.3 第 11/12 项只引 L616 与顶层总数 36），设计唯一性与验收可达性不受影响。**不改 `prd.md`**（已随需求审批冻结，改哈希即作废 `approval.yml#requirement`）；该处属需求文本、超出本 CR 设计范围，已登记为 SDD `follow_up` 第 6 项 | 本表；`tasks/TASK-03.md` §3（term 断言只锁 1 条目标用例，不锁 5 条计数） |
| **S-3**（`review-tech-design` attempt 2/3 的新发现 `范围外` suggestion：SDD §6.3 第 27 项括注「七个评审维度」与库内实状不符） | **按实际事实理解 + 保留理由**：本节点复算 `skills/requirement/review-requirement/SKILL.md#Step 2` 维度表 = **5 行**（结构完整性 / FR 可测试性 / 范围合理性 / 与规划对齐 / 依赖识别）＋ **3 条**条件契约闭包（HTTP API / crctl-CLI / Skill 契约）。该括注**不承担本 CR 的判据**（第 27 项的实际作用 = 零 diff 点名对象 + `REVIEW_SKILLS` 载体）；措辞本体属 `review-tech-design` L73 / `write-tech-design` L131 的既有同族表述，**两处均不在本 CR 修订目标与 §9 零 diff 面内**，本 CR **不改**；建议随 S-1 / S-2 一并校正语料措辞（归后续文档类 CR） | 本表；本计划不引用该括注作为判据 |

### B. `zero_diff` 复核清单（四张 TASK 卡逐条声明不触碰，`cmd-05` / `cmd-06` 机械兜底）

- **文件级零 diff**（不在改动集合）：`skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/lib/**`、`skills/shared/crctl/gates.json`、`skills/shared/controlled-shell/rules.json`、`skills/shared/crctl/scripts/test/suite-gate.mjs`、`skills/shared/crctl/scripts/test/contract-scan.test.mjs`、`skills/shared/crctl/scripts/lint-prompts.mjs`、`skills/shared/crctl/scripts/check-*.mjs`、`pipeline-templates/**`、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`agents/**`、`dir-graph.yaml`、`ARCHITECTURE.md`、`skills/develop/{write-dev-plan,write-dev-tasks,review-dev-plan}/SKILL.md`、`skills/requirement/review-requirement/SKILL.md`、`skills/develop/review-code/SKILL.md`、`change-requests/CR-2026-067/prd.md`、KB 的 `specs/`+`delivery/`+`docs/`、`../multica/**`。
- **段级零 diff**（文件在改动集合内，下列对象逐字保留）：`write-tech-design` 的 Step 1 / Step 2.5 / Step 3 / Step 4 / Step 5 与 Step 1 第 2 条的 `crctl checkpoint` 句、Step 2.6 的 AC 映射合同 / AC 反查闭环 / SDD-CLOSE 义务段、章节 9 的既有存在性判据与只读语义；`review-tech-design` 的 Step 1（含 `0. 只读 clean 前置`）/ Step 2.2 / Step 2.3 / Step 3 / Step 4 / Step 5 / Step 6；`pipeline-structure.test.mjs` 除 L616 外的全部用例（含 L656 的 CR-2026-066 断言 A/B/C/D 与 L636 的 `REVIEW_SKILLS` 常量）。
- **无独立条目但零改动义务不变**：`advance` / `gate` / `review-record` / `checkpoint` 命令面（其零改动由 `crctl.mjs` 全文件零 diff 覆盖）。

### C. 本条 run 不处置（仅登记，防误作漏做）

- SDD `follow_up` 1~6 项：PRD「七条」措辞（S-1）、`dep-N` 历史分析文档同步、`manifest.cases` 下界语义的严格化、评侧 SHA 必填对新写 SDD 的生效时点、回修重证质量的观测面、PRD §1.4 事实 16 计数（S-2）——**一律不得顺带实现**（本 CR 只做 §9 `scope_in` 的 4 个文件）。
- **CR-P2 面**（`write-dev-plan` / `write-dev-tasks` / `review-dev-plan`、TASK 依赖闭包、证据命令证明力、环境责任与 readiness、`code-implementation.pipeline.json` 的 dev-start 提示）：**零 diff**（AC-9①）。
- CR-P3 / CR-R / CR-S 的面（评审 clean 前置与 PASS 发布、结构化 `recovery`、`suite-gate` 判据语义）：**零 diff**。

---

## 9. TASK 拆分预分配（`write-dev-tasks` 的输入，共 4 个，组映射 1:1）

| 变更组 | 覆盖 FR | TASK id | 仓 | 粒度 | 依赖 | 估算 |
|---|---|---|---|---|---|---|
| G1 写侧四处原位修订（`write-tech-design/SKILL.md`：§6.5-A/B/C/D） | FR-1、FR-4、FR-5（写侧半） | CR-2026-067-TASK-01 | tools | 1 天 | — | 8h |
| G2 评侧两处原位修订（`review-tech-design/SKILL.md`：§6.5-E1/E2） | FR-2、FR-3、FR-5（评侧半） | CR-2026-067-TASK-02 | tools | 1 天 | — | 8h |
| G3 断言同步（`pipeline-structure.test.mjs` L616 两组 term） | FR-6.1 | CR-2026-067-TASK-03 | tools | 1 天 | CR-2026-067-TASK-01、CR-2026-067-TASK-02 | 6h |
| G4 登记值同步 + 交付面/零 diff 收口（`gate-registry.json` 35 → 36） | FR-6.2、FR-7 | CR-2026-067-TASK-04 | tools | 1 天 | CR-2026-067-TASK-01、CR-2026-067-TASK-02、CR-2026-067-TASK-03 | 6h |

- `task_count_hint = 4`（= 上表组数 = `tasks/_index.yml` 的 TASK 数 = §6.1/§7 出现的 canonical id 集）；`crctl task init CR-2026-067 --count-hint 4` 返回值 `totalEstimateHours` 期望 = **28h**。
- 三步断言（CR-2026-060 AC-08）：① **组映射 preflight**（Skill 内零 crctl 调用：恰 4 张卡、id = `CR-2026-067-TASK-01..04` 连续无重号、与上表一致；失败则删除草稿并 abort `TASK_COUNT_MISMATCH`）；② `crctl task init CR-2026-067 --count-hint 4`（写入前可数校验，失败零写入）；③ **init 后防并发复核**（以返回 `taskCount == 4` 为准，重跑组映射 preflight；不一致则保留现场、修正文件集后重跑同一命令，复核通过前不得 `advance --to task-breakdown`）。
- **TASK 卡的权威进度字段是 `tasks/_index.yml`**：卡片 frontmatter 的 `status` 一律 `pending`（`renderTaskIndex` 的渲染口径），真实状态只以账本为准（`crctl task done` 登记，带 `done-at`）。
- 四张卡的完成边界全部落在 `developing` 内可被 `crctl task done` 登记的事件（实现已落盘 + 证据命令绿 + 账本登记），**无 `merge` / `writeback` / `archive` / `code-reviewing` / `code-approved` 前置**（流程控制 TASK 禁止，CR-2026-057 FR-10）。
- 命名约定：`TASK-NN.md`（两位补零）；`slug` 英文 kebab-case ≤ 40 字符；`estimate` 形如 `Nh`（`^[1-9]\d*h$`）；`depends-on` 只引 canonical id 且无环（由 `loadTaskCards` 硬校验）。

---

## 10. 本计划不得越界（`zero_diff` 与本 CR 边界，逐条生效）

1. 不改 `sdd.md` / `prd.md` 一个字节（评审与审批双重绑定）。
2. 不改 `crctl.mjs`、`scripts/lib/**`、`rules.json`、`gates.json`、`suite-gate.mjs`、`contract-scan.test.mjs`、`lint-prompts.mjs`、`check-*.mjs`。
3. 不改 `pipeline-templates/**`（含 `_index.yml` 的 nodes 计数与 dev-start 提示）、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`agents/**`、`dir-graph.yaml`、`ARCHITECTURE.md`。
4. 不新增任何文件（含测试文件与 CI step）；`gate-registry.json#manifest.files` 保持 21；不新增 annotation dimension / 账本字段 / 评审指标 / Skill 参数 / crctl 子命令·flag·错误码。
5. 不重编号任何 Step；不新增小节层级；不放宽既有 blocker 判据（只收紧）。
6. 不删除 `write-tech-design` 现存的 `crctl checkpoint` 句；不引入四个反向 token；不引入 `recoverCommand` / `recover_command`。
7. `../multica` 零 diff（不改部署副本、不写 Go/TS、不改 `CUSTOM.md`）。
8. 不部署平台 Prompt、不重生成任何平台生成物、不启停任何共享服务。

---

## 11. 修订记录

- 初稿（2026-09-15，`code-implementation` node-1，本条 run）：按已审批 SDD（832 行 / 81,916 B / LF-only / sha256(LF) `551f5a39…`）与冻结 PRD（285 行 / sha256(LF) `efde31fd…`）起草；**上一阶段发布收口在本节点首位执行完成**（batch `91c65d76b5d09013` / metadataCommit `58b426a7…`）；测试面基线在本节点实测（全量套件 `verdict=pass` / 866.6 s / 21 文件 / 597 用例 / 0 failures；`manifest.cases["pipeline-structure.test.mjs"]=35` vs 实测 36）；四组 TASK 预分配（8/8/6/6 h = 28 h）；6 条证据命令（`cmd-01`~`cmd-06`，其中 4 条审计命令在本节点干跑并留下变更前基线：25 / 3 / 4 failures 与 exit 0）；协调者转交的 S-2 / S-3 逐条处置（§8.A）。
