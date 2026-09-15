---
id: CR-2026-068-plan
type: PLAN
cr-ref: CR-2026-068
sdd-ref: "change-requests/CR-2026-068/sdd.md"
target-version: 0.41
status: draft
created: 2026-09-15T23:10:00+08:00
updated: 2026-09-15T23:58:00+08:00
---

# CR-2026-068 开发计划（CR-P2：plan/TASK 返工成本与执行前提）

**权威输入（人工审批绑定，本计划不修改其一个字节）**

| 输入 | 绑定 | 摘要证据 |
|---|---|---|
| `change-requests/CR-2026-068/sdd.md`（949 行 / LF，唯一权威） | `review-annotations/sdd.yml#subject-sha256`（cycle 1 / attempt 2，`verdict=pass`、`blockers=[]`）+ `approval.yml#tech-design`（`via: crctl-approve`、`2026-09-15T22:00:30+08:00`、approver Ray、`evidence-digest 12bc5318…`、`target-status: tech-design-reviewed`，提交 `6edaaf3d`） | sha256(LF) = `d2562c30145326f949d3376481a8ced48157934b7addbc684d89f8b6e69979f3`（本节点按 worktree 实际文件复算，与 `review-annotations/sdd.yml#subject-sha256` 全等） |
| `change-requests/CR-2026-068/prd.md`（冻结，零触碰） | 需求人工审批冻结 | sha256(LF) = `5cb67f17d6d6e0e8076712873b186b3286734045ba11cf5cd57ad114d42f2596`；本计划只按 SDD 引用定位，不全量复审 PRD |
| `cr.md#target-version` | 注册期继承 | `0.41`（禁止 tbd / 自行改写，CR-2026-057 FR-13） |

- **硬边界一（不得触碰）**：`sdd.md` 已被 `review-annotations/sdd.yml#subject-sha256` 与 `approval.yml#tech-design#evidence-digest` 双重绑定——改它一个字节即同时作废本轮评审与人工审批。本计划与 `tasks/**` 只重述已审批的实施契约；`prd.md` 同样零触碰。
- **硬边界二（范围）**：交付面 = SDD §1.2 / §9 `scope_in` 的 **5 个文件、7 处落点**（全部在 tools worktree）；`zero_diff` 面（§9）逐条不得改动；`follow_up` 3 项不得顺带实现（§10）。
- **本计划的 replay 身份**：本条 run = `code-implementation` node-1/node-2（`write-dev-plan` → `write-dev-tasks`）；`review-dev-plan` 由独立 quality-reviewer-agent run 执行（作者不自评），`reviewLoop.maxAttempts=3`、`repairRef=write-dev-plan`、replayNodes=[repair-plan, regenerate-tasks, rerun-current-review]。
- **上一阶段发布收口已在本节点首位完成**（§0.2）：技术设计人工审批提交已随一次 `crctl checkpoint` 发布。

---

## 0. 基线与工作区事实（本节点实测，落笔即读，未轮询）

### 0.1 入口状态与门禁（crctl 权威值）

| 项 | 实测 |
|---|---|
| `crctl status CR-2026-068 --workspace <KB worktree>` | `status=tech-design-reviewed`；`legalNext` = `task-breakdown`(`write-dev-tasks`) / `rejected` / `withdrawn`；`reviewLoops.review-requirement=1/3`、`review-tech-design=2/3`、`review-dev-plan=1/3`（`review-dev-plan` attempt 1 = BLOCK，回修入口见 §11「回修 1/3」） |
| `gateBlockers.task-breakdown` | `["文件不存在","文件不存在","目录缺失或无匹配文件"]`（= `plan.md` / `tasks/_index.yml` / `tasks/TASK-*.md` 尚未生成，符合本节点开工前预期） |
| `approval.yml#tech-design`（只读核对） | approver Ray、`2026-09-15T22:00:30+08:00`、`via: crctl-approve`、`evidence-digest 12bc5318…`、`target-status: tech-design-reviewed`（提交 `6edaaf3d`） |
| `review-loop.yml` | `review-requirement` cycle 1 / attempt 1；`review-tech-design` cycle 1 / attempt 2（attempt 1 = BLOCK 1 blocker `dep-23` 归属，已闭合） |
| `workspace inspect CR-2026-068` | 三仓 `classification=healthy`、`dirty=false`；`operationalWorkspace` 非空 |

### 0.2 上一阶段发布收口（本节点首位执行，已发布）

```text
node <TOOLS>/skills/shared/crctl/scripts/crctl.mjs checkpoint CR-2026-068 \
  --message 技术设计已审批（上一阶段发布收口） --workspace <KB worktree>
⇒ phase=complete、changed=true、batchId=56fda17d5aa4c9b3、metadataCommit=516c0d2595027846f92b5c93264150a5db3827a7
⇒ repositories[]（三仓 confirmed=true）：KB 6edaaf3d6b41f65c8396e0730d3ba2ac661e8ed8 / multica d4a49e2b9ca7d83368737cd57d6a697d3bd042b4 / tools 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
⇒ sideEffects：KB push + KB metadata commit + KB push（metadata）
```

⇒ 技术设计人工审批写入的 `approval.yml#tech-design` 与 `tech-design-reviewed` 状态提交（`6edaaf3d`）现已上远端（`origin/requirement/CR-2026-068` 前移），multica / tools 两仓与远端一致。上一阶段未闭合的发布动作**已闭合**，本节点不再重复发布。

### 0.3 三仓 worktree（路径 authority = `resources[].worktreePath` 原样值，不拼接、不回退主工作区）

| repo | worktreePath | 分支 | HEAD（本节点实测） | 本 CR 角色 |
|---|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-068` | `requirement/CR-2026-068` | `516c0d25…`（§0.2 checkpoint metadata commit） | 承载 prd/sdd/plan/tasks/test-report/证据；零代码 |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-068` | `requirement/CR-2026-068` | `d4a49e2b9ca7d83368737cd57d6a697d3bd042b4` | **零 diff**（SDD §9 `zero_diff`：不改部署副本与 Go/TS 代码、不改 CUSTOM.md） |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-068` | `requirement/CR-2026-068` | `49fa37748d9b2fc7fc58fd53f839e2ed293bde17`（= SDD §6.3 全部 tools 条目的 `commit SHA` 登记值；**diff 审计基线**） | 5 个交付文件（实现主面） |

### 0.4 测试面基线实测（本节点未改任何文件，全部为「变更前事实」，win32 / node v24.15.0）

| 项 | 实测值（本条 run） |
|---|---|
| **目标文件定点** `node --test --test-reporter=dot pipeline-structure.test.mjs contract-scan.test.mjs` | **exit 0 / 0.7 s / 74 点号**（两文件全绿，含 `dep-15` 的 CR-2026-043 / CR-2026-050 / S-13 / 节点数断言与 `dep-18` 的退役字段扫描） |
| `gate-registry.json` | `manifest.cases["pipeline-structure.test.mjs"] = 36`、`exceptions: []`（CR-2026-067 已同步；本 CR 预期零测试改动，登记值不动） |
| 基线结论 | 本 CR 起点是全绿；FR-1~FR-6 的交付全部为文本原位修订，无任何断言需要同步（SDD §6.4 逐条论证） |

### 0.5 关键锚点（实施定位线索；行号为回修 1/3 在 tools worktree HEAD `49fa37748d9b` 上复核实测，实施期以实时搜索为准）

| 文件 | 既有对象（本节点实测事实） | 本 CR 处置 |
|---|---|---|
| `skills/develop/write-dev-plan/SKILL.md` | `### Step 2a — 回修模式（CR-2026-026 FR-8/FR-9）` 段落（L86 起；普通轨三条，无 upstream 轨文字）；两张稳定表说明：`验收证据` bullet（L68 概括反假绿句）、`回滚` bullet（L69「该 FR 的回滚单元（如 revert 某 TASK commit）」）、证据命令表区块（L73~L79，其两条 bullets 在 L76~L77 六项形态判据）；章节清单第 5 项「**验收与发布策略** — 发布前 checklist / feature-flag 计划」（L57） | TASK-01：§6.5-A（Step 2a 末追加）＋ §6.5-B（B-1/B-2 原位扩写、B-3 追加）＋ §6.5-C（第 5 项整体替换） |
| `skills/develop/write-dev-tasks/SKILL.md` | `### Step 2a` 第 1 条（现行「**重新生成** TASK 卡……不保留已被评审判废/删除的旧 TASK」）；第 2、3 条；`### Step 3 — 生成 TASK 文件`；`### Step 4 — TASK 数量三步断言与索引初始化`（`dep-6`：三步断言 + `crctl task init --count-hint` + `TASK_COUNT_MISMATCH` + 「`tasks/_index.yml` 是受控账本，禁止 Agent/Skill 手写」） | TASK-02：§6.5-D（第 1 条整体替换；第 2、3 条逐字保留；`重新生成` 零残留） |
| `skills/develop/review-dev-plan/SKILL.md` | L82 `acceptance-verifiability` bullet（现行只有概括判据）；L129 决策表行 `acceptance-verifiability: pass | block` | TASK-03：§6.5-E（L82 整体替换；决策表行与八类维度表不动） |
| `skills/develop/implement-code/SKILL.md` | L102 `## 环境验证与 ENVIRONMENT_MISMATCH`（唯一详细事实源声明 + 六条既有 bullets：一次环境检查 / 最多一次重跑 / timeout 与测试入口 / 标签不写 crctl 面 / 临时隔离实例例外 / 受控建立归因） | TASK-04：§6.5-F（节末追加两条 bullets；既有六条逐字保留） |
| `pipeline-templates/code-implementation.pipeline.json` | 节点 `…0004`（id `00000000-0000-0000-0015-000000000004`、kind=human_approval、label「确认进入代码开发」、onFail=abort、timeoutMinutes=4320）的 `approvalPrompt` 现行值含「❌ 暂缓：补充任务拆分意见，重新执行 write-dev-tasks 后再确认」；`…0014.reviewLoop`（repairRef=write-dev-plan、replayNodes 三项、maxAttempts=3） | TASK-04：§6.5-G（`approvalPrompt` 值替换；节点对象其余字段与节点集零变化） |

---

## 1. 交付里程碑

| # | 阶段 | 内容 | 产出 | 估算 | 状态 |
|---|---|---|---|---|---|
| M1 | 需求与架构（已完成） | 注册 → PRD → 评审 → 人工审批 → SDD → 回修复评 PASS → 人工架构审批 → 发布收口（§0.2） | `prd.md`、`sdd.md`（949 行）、`approval.yml#tech-design`、批次 `56fda17d…` | — | **done** |
| M2 | 开发计划与拆分（本节点） | `write-dev-plan` → `write-dev-tasks` → 独立 `review-dev-plan` | `plan.md`、`tasks/TASK-01..04.md`、`tasks/_index.yml`、`status=task-breakdown` | 本条 run | **本条 run（评审由独立 reviewer run 执行）** |
| M3 | 实现 | TASK-01 → TASK-02 → TASK-03 → TASK-04（依赖序，见 §2） | tools **5 个文件、7 处落点**的 diff；4 个 TASK 在 `tasks/_index.yml` 即时标 `done`（工程纪律 #8，不积压到回写期） | **30 h（≈ 3.75 人天）** | pending |
| M4 | 测试 | `write-test-report`（`crctl test --plan`，6 条证据命令） | `test-report.md` ＋ `test-evidence/cmd-01…06.log` | 见 §5.4 预算 | pending |
| M5 | 代码评审与审批 | 独立 `review-code` → 人工 `approve-code` | `review-annotations/code.yml`、`approval.yml#code` | — | pending |
| M6 | 交付回写 | `delivery-agent` 的 merge / writeback / archive | merge 提交、`delivery/task/**`、`specs/ai-first-platform` 基线 | — | pending |

**估算口径**：四张 TASK 卡 frontmatter 的 `estimate` 之和 = **30 h**（8 + 8 + 8 + 6）；与 `crctl task init CR-2026-068 --count-hint 4` 返回的 `totalEstimateHours` 必须相等（不等时按 `write-dev-tasks` Step 4 输出 WARN，不静默覆盖）。

---

## 2. 任务依赖图

```text
TASK-01（write-dev-plan 写侧三处落点：Step 2a upstream 轨 + 两张稳定表三处扩写 + 章节 5 环境五要素；FR-1 / FR-3 写侧 / FR-4 / FR-5 plan 侧）
   │  改：skills/develop/write-dev-plan/SKILL.md（Step 2a 段末 L86~L92 后 / L68 / L69 / 证据命令表 bullets 后 / L57）
   │
   ├──────────────► TASK-03（review-dev-plan 评侧判据同表述收紧；FR-3 评侧）
   │                  │  改：skills/develop/review-dev-plan/SKILL.md（L82 一条）
   │                  │  （评侧两条 blocker 判据消费写侧 §6.5-B 的同表述 ⇒ 依赖 TASK-01 先落地）
   │                  ▼
TASK-02（write-dev-tasks Step 2a 第 1 条 delta 重算改写；FR-2）
   │  改：skills/develop/write-dev-tasks/SKILL.md（Step 2a 第 1 条）
   │                  │
   │                  └──────────────► TASK-04（implement 侧 + dev-start 提示 + 交付面/零 diff 收口；FR-5 其余两侧 / FR-6）
   │                                    改：skills/develop/implement-code/SKILL.md（环境节末两条）＋
   │                                       pipeline-templates/code-implementation.pipeline.json（…0004 approvalPrompt 值）
   │                                    核：diff 面恰 5 文件、zero_diff 面零改动、静态面与目标测试绿
   ▼
（TASK-01 与 TASK-02 互不共用文件，可并行；二者均无 depends-on）
```

- **依赖序固定为 `{TASK-01 ∥ TASK-02} → TASK-03 → TASK-04`**：TASK-03 的评侧判据按 SDD I3「同表述、同强度」消费 TASK-01 落地的写侧文本（观测面/四类错配/受控入口三组措辞必须两侧逐字同族），故晚于 TASK-01；TASK-04 的零 diff 审计对象是**全部改动的终态 diff**（cmd-05 白名单双向相等），且 §6.5-G 的 `❌` 分支文字引用 TASK-01/TASK-02 落地的修复路径语义，故晚于前三者。**不存在两个 TASK 并发改同一文件**。
- **无环、无悬空**：`depends-on` 只引用本 CR 的 canonical id（§9 表）；TASK-04 的依赖闭包由 TASK-03 传递覆盖，但仍逐条显式声明（审计面需要三者终态齐备）。
- **中间态不红**：TASK-01/02/03/04 均为纯文本修订且零测试改动（SDD §6.4），每个 TASK 单独落地后 `dep-15`/`dep-17`/`dep-18` 既有断言仍绿（新文字不写 `\bgit\b`/`\bjournal\b`/三 token/退役字段名/「重新生成」）；TASK-03 评侧收紧不触碰任何测试断言面。**FR-1~FR-6 同批交付**，半套状态不进入交付。
- **回滚单元**（§4.0）与依赖图逆序一致。

---

## 3. 资源与分工

| 角色 | 责任 | 本 CR 范围 |
|---|---|---|
| `owners.development` = **Ray** | 技术设计、实现 4 个 TASK、开发相关审批 | tools 5 个文件全部 diff |
| `owners.test` = **Ray** | `write-test-report` 的真实证据（6 条证据命令、`sourceRevision` 绑定） | `test-report.md`、`test-evidence/cmd-01…06.log` |
| `owners.requirement` = **Ray** | 已闭合（PRD 冻结） | 零动作 |
| 独立评审方 | `review-tech-design`（已完成）/ `review-dev-plan` / `review-code` 一律由**新建 quality-reviewer-agent task** 执行 | 作者不自评 |

- tools worktree 为单写者（`requirement/CR-2026-068` 分支，`classification=healthy` / `dirty=false`）；**不与其他 CR 并发**（SDD AC-9②：在途仅本 CR，CR-2026-063~067 均 `archived`）。
- 实施期不启停任何数据库 / 消息队列 / 共享服务；本 CR 只改文本与一个 JSON 字符串值，不部署平台 Prompt、不改 `../multica`。

---

## 4. 风险与回滚策略

### 4.0 回滚单元（逆拓扑组合，唯一事实）

| 单元 | 覆盖 | 回滚方式 | 语义 |
|---|---|---|---|
| **RU1** | TASK-01 全部（`write-dev-plan/SKILL.md` 三处落点） | revert TASK-01 的提交 | 写侧合同回退（FR-1 / FR-3 写侧 / FR-4 / FR-5 plan 侧）；与 RU3 合批时须同批复原（FR-3 两侧判据同表述，单独回退一侧会使口径不对称） |
| **RU2** | TASK-02 全部（`write-dev-tasks/SKILL.md` 第 1 条） | revert TASK-02 的提交 | TASK delta 合同回退（FR-2）；独立可回退（不改任何断言面） |
| **RU3** | TASK-03 全部（`review-dev-plan/SKILL.md` 一条） | revert TASK-03 的提交 | 评侧合同回退（FR-3 评侧）；与 RU1 的写侧判据**必须同批**（I3 同表述约束） |
| **RU4** | TASK-04 全部（`implement-code/SKILL.md` 两条 bullets + `…0004` approvalPrompt 值 + 收口审计的记录面） | revert TASK-04 的提交 | 环境责任三侧的 implement/dev-start 半边回退（FR-5）；与 RU1 合批即回到变更前全绿态 |

**回滚边界**：本 CR diff 只有 5 个文件且 FR-3 的两侧判据互为同族表述、`…0004` 提示文字引用写侧落点语义，任一单独回退都可能造成「半套合同」；回退即按受影响下游消费者的依赖闭包组合 revert（本表 RU 组合），不产生半套状态。回滚执行顺序 = 本表逆序（先 RU4，后 RU1）——与第 4 章「风险与回滚策略」的逆拓扑要求一致（本 CR 自身的 plan.md 也按 I4 承载该判据）。

### 4.1 风险表

| # | 风险 | 影响 | 缓解（本计划的机器判据 / 纪律） |
|---|---|---|---|
| R-1 | upstream 轨写成独立 `###` 小节或重编号 Step（违反 D-1 / C1 保持性） | AC-1 假绿、`dep-3` Step 编号集破坏 | `cmd-03` 断言 Step 标题集仍为 `1,2,2a,3,4` 且 upstream 轨为加粗小标题形态（`**upstream 轨`）＋ 普通轨三条逐字存在（need 集含三条原文） |
| R-2 | 两张稳定表被加列/删列/表头改动，或 `验收证据 ↔ 证据ID` 双向唯一映射被放宽（C2/C3 保持性） | AC-3⑤ / AC-6 红 | `cmd-03` 断言两条表头行逐字存在（`| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |`、`| 证据ID | repo | cwd | executable | args | timeout |`）＋ 判据只落在既有 bullet 内（`证据ID 照抄证据命令表，不新增命令行`、`另立 CR` 出口句） |
| R-3 | `…0004` approvalPrompt 写入 `git`/`journal`/`review-annotations`/`reject_reason` 或丢两分支（`dep-15` 字面禁令） | `pipeline-structure.test.mjs` CR-2026-043 / CR-2026-050 用例红（CI 红） | `cmd-03` forbid 四 token ＋ need `✅ 通过` / `❌ 暂缓`；`cmd-02` 定点重跑该测试文件（真实断言执行面，非仅文本检索） |
| R-4 | `…0014.reviewLoop` / 节点集 / 其余 prompt 被顺手改动（`dep-8` 零改动面） | AC-7③ 红、replayNodes 语义漂移 | `cmd-05` diff 白名单双向相等（恰 5 文件）＋ `cmd-06` pipeline 结构断言（无悬空 repairNodeId / replayNodes / 重复 node id / inactive ref）＋ `cmd-03` 断言节点数 12 与 `…0004` 其余字段（kind/label/onFail/timeoutMinutes）不变 |
| R-5 | write-dev-tasks 出现第二套回修规则或残留「重新生成」（违反 I2 / C4） | AC-2①~④ 红、`dep-17` CR-2026-037 断言面语义漂移 | `cmd-03` forbid `重新生成`（同文件全文零命中）＋ need 第 2、3 条逐字保留 ＋ need `执行 plan→TASK delta 重算` / `下游依赖闭包` / `crctl task init` 只刷新索引语义句 |
| R-6 | 评侧判据与写侧不同表述/不同强度（违反 I3），或新增维度名/证据账本（C5 保持性） | AC-3 假绿、八类维度表面破坏 | `cmd-03` 评侧 need 两条加粗 blocker 句与四类错配逐字 token（与写侧同族措辞）＋ forbid `acceptance-verifiability` 行以外的新维度（决策表行 `acceptance-verifiability: pass | block` 逐字保留） |
| R-7 | implement 环境节既有六条 bullets 被改写，或 readiness 成为第二套验证语义（C6 / D-3） | AC-5③ 红、`ENVIRONMENT_MISMATCH` 单一事实源漂移 | `cmd-03` need 既有「一次环境检查」「最多一次重跑」「唯一详细事实源」三条逐字存在 ＋ need 新 bullets 含「一次环境检查」执行内容定位句与「环境无关 TASK 不被提前阻断」 |
| R-8 | 交付面越界（多改 `crctl.mjs` / `rules.json` / `gate-registry.json` / `pipeline-templates/**` 其他文件 / `agents/**` / 矩阵 / `dir-graph.yaml` / `ARCHITECTURE.md` 等 zero_diff 面） | AC-7① ② 红、违反批准范围 | `cmd-05` 的 **diff 白名单双向相等**（恰 5 文件；零 diff 前缀表逐条否定）＋ `cmd-06` 的 lint/matrix/agents-contract 静态面 |
| R-9 | 新增文字触发 `lint-prompts --mode enforce`（R1 手写 deny 面 / R2 裸 git / R7 crctl 参数形态 / R9「下一步」映射 / R12 状态机副本 / R13 backlog 状态推断） | CI 红（`dep-19`） | `cmd-06` 的 `lint-prompts --mode enforce` 本机等价面；TASK 实现要点写明避让约束（不写裸 git 命令、不写状态名枚举映射、不指示手写受保护账本） |
| R-10 | 新增文字引入退役字段名（`repair-instructions` / `fixed-blockers` / `suggestion_policy` / `recoverCommand` / `recover_command`，`dep-18`） | contract-scan 红 | `cmd-02` 定点执行 `contract-scan.test.mjs`（38 用例真实扫描面）＋ 新文字不使用这些字面量 |
| R-11 | 证据命令超 `write-test-report` 节点预算（20 min / 1200 s） | 测试节点失败 | §5.4 预算：实测基线 cmd-01 866.6 s ＋ 其余秒级，合计 ≈ 870 s（余量 ≥ 330 s）；最贵的 cmd-01 排第一 |
| R-12 | 违反行尾纪律（跨行断言/解析静默降级、CRLF 假红假绿；`dep-5` 不变量 4、SDD-CLOSE-05） | 假绿 / 假红 | 四条审计命令全部先 `\r\n → \n` 归一读入；读取失败**硬失败**（`length < 3000`/`< 500` 即红、JSON 解析异常即红、`crctl git diff` 非零即红）——工程纪律 #1；审计脚本含双引号的 token 一律以 `String.fromCharCode(96)` 等构造，避免转义歧义 |
| R-13 | 实施期发现 SDD 不可实施 | 阻断 | 出口 = 状态机既有边 `review-dev-plan:upstream-design-blocker`（`task-breakdown → tech-design-review-pending`）与 `review-dev-plan:block -> write-dev-plan`；**不得就地放宽** SDD 或 `zero_diff` |

---

## 5. 验收与发布策略

### 5.0 环境静态前提与即时 readiness（SDD §6.5-C 承载的自反声明；本 CR 无常驻环境依赖）

- **环境 owner / 建立方式 / 可获得性**：本 CR 的全部证据命令只依赖本机 `node`（v24.15.0，已安装）与三仓 worktree（`crctl workspace inspect` 实测 `classification=healthy`）；无数据库、消息队列、浏览器或常驻服务依赖。owner = `owners.development` = Ray；建立方式 = 既有 Multica 工作区 + crctl worktree 派生（已建立）；可获得性 = 本机即时可用（§0.4 基线实跑已证明）。
- **readiness 证据（复用既有 `cmd-NN`，不新增命令行）**：本计划的环境就绪由 `cmd-02`（两份目标测试文件实跑，exit 0）与 `cmd-06`（静态面，exit 0）承载——它们同时是 AC 验收证据，**未为 readiness 另立任何命令**，两张稳定表双向唯一映射未放宽；本 CR 不触发「无法复用 → 另立 CR」出口。
- **缺失时处置**：若实施期 `node` 或 worktree 不可用，按既有 `ENVIRONMENT_MISMATCH` 标签中止并报告所需建立动作（唯一详细事实源 = `implement-code`，此处只引用不复述）；dev-start 审批只确认上述静态前提，不要求任何服务在线。

### 5.1 发布前 checklist（全部机器可判或逐行可核）

1. `crctl status CR-2026-068` = `developing`；`tasks/_index.yml` 四张卡全部 `done`（带 `done-at`，即时登记不积压，工程纪律 #8）。
2. tools diff **恰为** SDD §9 `scope_in` 的 5 个文件（双向相等）：`cmd-05` 输出 `tools diff paths = 5`，无「越界路径」与「缺少应改文件」。
3. `zero_diff` 面无改动：`skills/shared/crctl/scripts/**`（含 `gate-registry.json`）、`write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline`、`pipeline-templates/_index.yml` 与 `…0004` 以外的全部 pipeline 内容、`tools/agents/**`、`agent-skill-matrix.yml`、`dir-graph.yaml`、`ARCHITECTURE.md`（`cmd-05`）。
4. `cmd-02`（目标测试文件定点）exit 0 / 74 点号；`cmd-03` / `cmd-04` / `cmd-05` 在变更后 **failures = 0**；`cmd-06` exit 0；`cmd-01` 全量套件 `verdict=pass` / `failures=0` / `exceptions_count=0`。
5. `cmd-03` 断言：普通轨三条逐字保留、Step 标题集 `1,2,2a,3,4`、两张表头逐字存在、`重新生成` 与四 token / 退役字段名零命中、既有六条环境 bullets 三点逐字保留。
6. `…0004` approvalPrompt 含静态前提确认与 `✅ 通过` / `❌ 暂缓` 两分支；节点 id/kind/label/onFail/timeoutMinutes 与节点数 12 不变（`cmd-03` + `cmd-04`）。
7. `sourceRevision` 绑定：6 条证据命令均为 `repo=tools`，与 tools worktree HEAD 一致（由 `crctl test` 发布，本计划不重算）。

### 5.2 发布与观测

- **本 CR 自身的发布点**：`review-dev-plan` PASS 之后的 `push-progress`（`crctl checkpoint`）由该评审 run 的 PASS 分支执行（每次评审 PASS 一次；BLOCK 分支不发布）。本节点自身**不再发布**（上一阶段发布收口已在 §0.2 闭合；本节点的 `plan.md` / `tasks/**` / 状态提交由评审 PASS 的 checkpoint 搭车发布）。
- **交付后观测**：本 CR 不新增观测指标 / SLO / 计数门禁（SDD §2.1）；成功指标（未受影响内容改写数 = 0、readiness 复用比例 = 100%、新增结构件 = 0）为实施后可统计的既有事实，不落成新账本字段。
- **判据生效时点**：`review-dev-plan` 评审判据收紧只对评审发生时的 SKILL 版本生效，对既有已归档 CR 无追溯效力（SDD §7.3）。

### 5.3 例外治理与零例外口径

- `suite-gate` 的 `exceptions` 保持**显式空数组**（本 CR 预期零测试改动，不签任何新例外，SDD §6.6）。
- 失败向量一律就地修（不回改被断言文件、不降级为下界、不新增用例掩盖）；跨行解析/读取失败**硬失败**（工程纪律 #1）。

### 5.4 预算（证据命令集）

`write-test-report` 节点 `timeoutMinutes=20`（1200 s，pipeline `…0007`）。预算表（本节点实测，按 §6.2 顺序执行）：

| 证据ID | 预算（本节点实测） | 依据 |
|---|---|---|
| cmd-01 | **866.6 s**（CR-2026-067 同款命令基线实测 `duration_ms=866590`） | §0.4 同款基线（21 文件 / 597 用例 / pool=15，win32 / node v24.15.0） |
| cmd-02 | ≤ 5 s（实测 **0.7 s**） | §0.4 目标文件实跑 |
| cmd-03 | ≤ 5 s（实测 **0.04 s**） | §6.3 干跑（回修 1/3 复跑） |
| cmd-04 | ≤ 5 s（实测 **0.04 s**） | §6.3 干跑（回修 1/3 复跑） |
| cmd-05 | ≤ 5 s（实测 **0.13 s**） | §6.3 干跑（回修 1/3 复跑） |
| cmd-06 | ≤ 10 s（实测 **1.5 s**） | §6.3 干跑（回修 1/3 复跑） |
| **合计** | **≤ 897 s**（预期 ≈ **869.0 s**；< 1200 s，余量 ≥ 300 s） | — |

**顺序策略**：cmd-01（最贵且是回归主证据）排第一——它同时覆盖 AC-7 / AC-8 的回归面与 NFR-1；其余五条都在秒级，任一条红都不影响 cmd-01 的日志已落盘。

**估算总工时 = 30 h**（= 四张 TASK 卡 `estimate` 之和 = §9 预分配之和；与 `crctl task init --count-hint 4` 的 `totalEstimateHours` 交叉校验）。

---

## 6. 两张稳定表（契约必填节，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 upstream 后 plan 增量回修（AC-1①~⑤） | §1.4.1 ＋ §4.1 算法 ＋ §6.5-A（Step 2a 末 upstream 轨四条；普通轨三条逐字保留、Step 编号不重编） | CR-2026-068-TASK-01 | cmd-03（upstream 轨四条文本判据：delta 输入 / 只重算受影响面 / 未受影响逐字保留 / coordinator 只传引用不指定行 / 路由面不变；普通轨三条与 Step 标题集 `1,2,2a,3,4` 保持）、cmd-02（`dep-15`/`dep-17` 既有断言执行面） | RU1 |
| FR-2 TASK 及依赖闭包 delta 重算（AC-2①~⑤） | §1.4.2 ＋ §4.2 算法 ＋ §6.5-D（Step 2a 第 1 条整体替换；第 2、3 条逐字保留；`crctl task init` 只刷新索引；`重新生成` 零残留） | CR-2026-068-TASK-02 | cmd-03（delta 重算 + 依赖闭包同步 + 未受影响保留 + 索引只刷新 + 无第二套规则 + 第 2/3 条保留）、cmd-02（`dep-17` CR-2026-037 两条 match / 一条 doesNotMatch 真实执行面）、cmd-01（全量回归） | RU2 |
| FR-3 证据命令可执行性与证明力（AC-3①~⑤） | §1.4.3 ＋ §4.3 判据算法 ＋ §6.5-B（写侧六项：观测面 ≥ 声称面 / 四类错配 / 命令算法唯一事实源；既有概括句保留）＋ §6.5-E（评侧两条 blocker 判据，同表述同强度） | CR-2026-068-TASK-01（关联 CR-2026-068-TASK-03：评侧同判据半边） | cmd-03（写侧六项 + 评侧两条加粗 blocker 句 + 表头逐字保持 + 既有概括句保留）、cmd-02（两测试文件真实执行） | RU1 ∪ RU3 |
| FR-4 回滚单元是依赖闭包（AC-4①~④） | §1.4.4 ＋ §4.4 算法 ＋ §6.5-B B-2（`回滚` bullet 三项闭包判据原位扩写；列集不变） | CR-2026-068-TASK-01 | cmd-03（`回滚` bullet 含下游消费者闭包 / 逆拓扑一致 / 单点回滚禁令三项） | RU1 |
| FR-5 环境责任与即时 readiness（AC-5①~③、AC-6①~③） | §1.4.5 ＋ §4.5 三侧流程 ＋ §6.5-C（plan 章节 5 五要素）/ §6.5-F（implement 两条 bullets）/ §6.5-G（`…0004` approvalPrompt 值） | CR-2026-068-TASK-04（关联 CR-2026-068-TASK-01：plan 侧五要素半边） | cmd-03（五要素 + readiness 复用既有 `cmd-NN` + `ENVIRONMENT_MISMATCH` 只引用不复述 + 既有六条 bullets 保留 + 四 token 零命中 + 两分支保留）、cmd-04（节点对象字段与节点集不变）、cmd-02（CR-2026-043/050 真实执行面） | RU4 ∪ RU1 |
| FR-6 边界与零新增（AC-7①~④、AC-8①~④、AC-9①~③） | §1.4.6 ＋ §4.6 零 diff 面 ＋ §6.4 改动/零改动清单 ＋ §9 `scope_in`/`zero_diff` | CR-2026-068-TASK-04（关联 CR-2026-068-TASK-01/02/03：各自文件级的零改动半边） | cmd-05（diff 白名单双向相等恰 5 文件 + zero_diff 前缀表零命中）、cmd-06（lint-prompts / skill-matrix / agents-contract / writeback-tests / pipeline 结构断言）、cmd-01（全量套件绿 + `exceptions_count=0`） | RU4∪RU1∪RU2∪RU3 |

**表注（防假绿）**

① 「验收证据」列按「主责命令在前」列出覆盖本行验收面的 `cmd-NN`；每个 `cmd-NN` 与 §6.2 证据命令表的 `证据ID`、`crctl test` 机器区 `commands` 1-based 下标、`test-evidence/cmd-NN.log` 三者全等（CR-2026-057 FR-16）。**6 个 in-scope FR 各出现一次**；四张 TASK 全部在表中出现（主责 TASK 唯一，关联 TASK 不改变主责），与 `tasks/_index.yml#id` 双向一致。
② `cmd-01`（全量套件）与 `cmd-02`（目标文件定点）**不是假绿**：本 CR 新增文字的保持性约束（字面禁令、三步断言、受治理账本句、CR-2026-037/043/050/S-13 断言）恰好落在 `cmd-02` 的两份真实测试文件内，任一禁令被新文字命中即 `assert` 红；`cmd-01` 覆盖「无回归 + `exceptions` 显式空」。两者互补而非互相替代。
③ **文本判据的存在性不由命令退出码单独承担**：`cmd-03` / `cmd-04` / `cmd-05` 在同一 `-e` 脚本内**先断言读取非空**（四份 SKILL 与 pipeline 模板 `length < 3000` 即红、`…0004.approvalPrompt` `length < 80` 即红、JSON 解析异常即红、`crctl git diff` 退出码非零即红），再逐 token 判定并逐条打印 `FAIL`；不存在「匹配不到 → 空集 → 静默通过」的降级路径（NFR-5 / 工程纪律 #1）。
④ **证据命令与 SDD 的关系**：`cmd-01` = 既有 CI 步骤 `suite-gate --run` 逐字（本 CR 零测试改动，登记值 36 不动）；`cmd-06` = CI 其余步骤的本机等价面（Windows 侧；Ubuntu 侧由外部 CI 承担，**不属本轮 run 拥有、不等待**）；`cmd-02`~`cmd-05` 是本计划自有的只读审计命令（**不新增测试文件、不新增 CI step**——`gate-registry.json` 的 `manifest.files` 保持 21 已双向保证文件集合不变）。
⑤ **FR-3 主责为 TASK-01（写侧）、关联 TASK-03（评侧）**：评侧文件的实际产生层是 TASK-03，AC-3 的评侧半边在 §7 矩阵行单独记 TASK-03 owner，不与交付覆盖表的主责语义冲突。
⑥ **表内 `args` 是字面值、可直接转录**：四条审计命令的 `-e` 脚本以字面文本写在表内（书写约束见 §6.2.5），`write-test-report` 的 `cr-test-plan/v1` 与实施期收口均逐字转录本表 cell；**不存在「实现期平面化」步骤，也不依赖任何临时脚本文件**（命令算法只在表内定义一次）。脚本语义见 §6.2.1~§6.2.4，四条命令的变更前实跑基线见 §6.3。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["skills/shared/crctl/scripts/test/suite-gate.mjs","--run"]` | 1080 |
| cmd-02 | tools | . | node | `["--test","--test-reporter=dot","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs","skills/shared/crctl/scripts/test/contract-scan.test.mjs"]` | 300 |
| cmd-03 | tools | . | node | ["-e","const fs=require('fs'),P=require('path');const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL,BT=String.fromCharCode(96),PIPE=String.fromCharCode(124);const read=p=>fs.readFileSync(P.join(R,p),'utf8').split(CR).join(NL);const bad=[];const W=read('skills/develop/write-dev-plan/SKILL.md'),T=read('skills/develop/write-dev-tasks/SKILL.md'),V=read('skills/develop/review-dev-plan/SKILL.md'),I=read('skills/develop/implement-code/SKILL.md');const four=[['write',W],['tasks',T],['review',V],['implement',I]];for(const pr of four){if(pr[1].length<3000){bad.push('FAIL '+pr[0]+' 读空或过短 length='+pr[1].length);}}const need=(label,t,toks)=>{for(const k of toks){if(t.indexOf(k)<0){bad.push('FAIL '+label+' missing '+k);}}};const forbid=(label,t,toks)=>{for(const k of toks){if(t.indexOf(k)>=0){bad.push('FAIL '+label+' residual '+k);}}};need('write',W,['**upstream 轨（SDD 重新批准后的增量回修）**','**新旧批准 SDD 的变更 delta**','同轮未闭合 plan blockers','只重算受影响章节、稳定表行、证据与回滚','未受影响内容逐字保留','coordinator 只传 subject、delta 与 canonical feedback 引用','不指定具体行如何修改','不把旧 plan 当作整轮作废','review-dev-plan:upstream-design-blocker','本轨不修改 review-route 枚举','不把 '+BT+'repair-target'+BT+' 改成多值','1. 逐条消费 blockers（每条内含可执行修复说明），修订同一份 '+BT+'plan.md'+BT+'；只处理评审指出的问题，不扩散 SDD 范围。','2. 禁止只刷新评审证据而不修改被指出的产物（空转由下一轮评审重新读取实际产物继续 BLOCK 兜底）。','3. 回修期间允许 status='+BT+'tech-design-reviewed'+BT+'（普通轨重放态），不因非 task-breakdown abort。','观测面 ≥ 声称面：每个 '+BT+'cmd-NN'+BT+' 必须能观测该表行声称的 AC 结果','不另立第二套形态判据','四类典型错配：'+BT+'--list'+BT+' 类命令不能证明浏览器行为；文件级 '+BT+'--name-only'+BT+' 不能证明符号级不变量；子集测试不能声称全量；涉及 Git 的命令必须使用 '+BT+'rules.json'+BT+' 已允许的受控入口','命令算法唯一事实源 = 证据命令表行；不得通过委派评论补写命令算法。','被其它 TASK 消费的共享改动，其回滚单元必须包含受影响下游消费者','与第 4 章「风险与回滚策略」的逆拓扑顺序一致','单点 revert 会破坏下游时不得声明为单点回滚。','证据命令表的命令行是 '+BT+'cmd-NN'+BT+' 的唯一事实源：命令算法只写在表内（'+BT+'executable'+BT+' / '+BT+'args'+BT+' / '+BT+'cwd'+BT+' / '+BT+'timeout'+BT+'），不得另行改写或补写。','若验收证据依赖常驻服务、浏览器或数据库','环境 owner、建立方式、可获得性：责任人与获得途径，不写具体命令；','readiness 证据：必须复用','证据ID 照抄证据命令表，不新增命令行','双向唯一映射不得放宽','另立 CR','缺失时处置：','唯一详细事实源是 '+BT+'implement-code'+BT+'，此处只引用不复述','不新增第八节','该命令必须实际覆盖本行所声称的验收面，不得只覆盖其中一部分造成假绿']);const steps=t=>t.split(NL).filter(l=>l.indexOf('### Step ')===0).map(l=>{const s=l.slice(9),k=s.indexOf(' — ');if(k<0){return s.trim();}return s.slice(0,k).trim();}).join(',');const ew=steps(W);if(ew!=='1,2,2a,3,4'){bad.push('FAIL write step-set = '+ew);}const headLine=(t,key)=>t.split(NL).find(l=>l.indexOf(key)>=0);const cntP=s=>s.split(PIPE).length-1;const h1=headLine(W,'FR/关键AC'),h2=headLine(W,PIPE+' 证据ID '+PIPE);if(h1){if(cntP(h1)!==6){bad.push('FAIL write coverage-table header pipe-count = '+cntP(h1));}if(h1.indexOf('SDD交付项')<0){bad.push('FAIL write coverage-table header 缺 SDD交付项');}if(h1.indexOf('主责/关联TASK')<0){bad.push('FAIL write coverage-table header 缺 主责/关联TASK');}if(h1.indexOf('验收证据')<0){bad.push('FAIL write coverage-table header 缺 验收证据');}if(h1.indexOf('回滚')<0){bad.push('FAIL write coverage-table header 缺 回滚');}}else{bad.push('FAIL write coverage-table header 未取到');}if(h2){if(cntP(h2)!==7){bad.push('FAIL write evidence-table header pipe-count = '+cntP(h2));}if(h2.indexOf('repo')<0){bad.push('FAIL write evidence-table header 缺 repo');}if(h2.indexOf('cwd')<0){bad.push('FAIL write evidence-table header 缺 cwd');}if(h2.indexOf('executable')<0){bad.push('FAIL write evidence-table header 缺 executable');}if(h2.indexOf('args')<0){bad.push('FAIL write evidence-table header 缺 args');}if(h2.indexOf('timeout')<0){bad.push('FAIL write evidence-table header 缺 timeout');}}else{bad.push('FAIL write evidence-table header 未取到');}need('tasks',T,['执行 plan→TASK delta 重算','直接受影响 TASK','下游依赖闭包','未受影响 TASK 保留','只用于刷新','同步更新受影响 TASK 的输入、输出、接口（接口契约节的消费/产出签名）、命令、'+BT+'depends-on'+BT+'、完成标志与回滚','2. 禁止只刷新评审证据而不修改被指出的产物。','3. 回修期间允许 status='+BT+'tech-design-reviewed'+BT+'（普通轨重放态）。','crctl task init','禁止 Agent/Skill 手写']);forbid('tasks',T,['重新生成']);need('review',V,['**观测面窄于声称面即 blocker**','**命令形态越受控边界即 blocker**',BT+'--list'+BT+' 类命令声称浏览器行为','文件级 '+BT+'--name-only'+BT+' 声称符号级不变量','子集测试声称全量','涉及 Git 的命令未使用 '+BT+'rules.json'+BT+' 已允许的受控入口','命令算法只存在于委派评论而不在证据命令表行','不留到 implement 阶段才暴露','不新增维度名或证据账本','核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路']);const dec=V.split(NL).find(l=>{if(l.indexOf('acceptance-verifiability:')<0){return false;}if(l.indexOf('block')<0){return false;}return true;});if(dec){if(dec.indexOf('pass')<0){bad.push('FAIL review decision-row 缺 pass');}if(cntP(dec)!==1){bad.push('FAIL review decision-row pipe-count = '+cntP(dec));}}else{bad.push('FAIL review decision-row 未取到');}need('implement',I,['即时 readiness：在**第一个依赖环境的 TASK 前**执行 plan 指定的 readiness '+BT+'cmd-NN'+BT+'；该命令是既有「一次环境检查」在环境依赖 TASK 上的执行内容','失败时按既有 '+BT+'ENVIRONMENT_MISMATCH'+BT+' 中止并报告所需建立动作','环境无关 TASK 不被提前阻断','readiness 未通过只阻断依赖该环境的 TASK','一次环境检查：任务开始时只做一次有界前提检查','最多一次重跑','唯一详细事实源']);const D=JSON.parse(read('pipeline-templates/code-implementation.pipeline.json'));if(D.nodes.length!==12){bad.push('FAIL pipeline 节点数 = '+D.nodes.length);}const N4=D.nodes.find(n=>n.id==='00000000-0000-0000-0015-000000000004');if(!N4){bad.push('FAIL pipeline 缺 …0004 节点');}else{if(N4.kind!=='human_approval'){bad.push('FAIL pipeline …0004 kind = '+N4.kind);}if(N4.label!=='确认进入代码开发'){bad.push('FAIL pipeline …0004 label = '+N4.label);}if(N4.onFail!=='abort'){bad.push('FAIL pipeline …0004 onFail = '+N4.onFail);}if(N4.timeoutMinutes!==4320){bad.push('FAIL pipeline …0004 timeoutMinutes = '+N4.timeoutMinutes);}const ap=N4.approvalPrompt?N4.approvalPrompt:'';if(ap.length<80){bad.push('FAIL pipeline …0004 approvalPrompt 读空或过短 length='+ap.length);}need('pipeline',ap,['TASK 拆分已完成','环境静态前提（只确认静态事实，不要求审批时所有服务在线）','环境 owner 已明确、建立方式已写明、可获得性已声明','动态健康状态由 implement-code 在第一个依赖环境的 TASK 前用 plan 指定的 readiness 证据即时验证','审批不为其背书','按缺口所属产物回到对应写作节点','✅ 通过','❌ 暂缓']);forbid('pipeline',ap,['重新执行 write-dev-tasks 后再确认','review-annotations','reject_reason']);}if(bad.length){console.log('audit-skill failures = '+bad.length);for(const x of bad){console.log(x);}process.exit(1);}console.log('audit-skill failures = 0');"] | 300 |
| cmd-04 | tools | . | node | ["-e","const fs=require('fs'),P=require('path');const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL,WCH='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz';const read=p=>fs.readFileSync(P.join(R,p),'utf8').split(CR).join(NL);const bad=[];const raw=read('pipeline-templates/code-implementation.pipeline.json');if(raw.length<3000){bad.push('FAIL pipeline 模板读空或过短 length='+raw.length);}const D=JSON.parse(raw);const ids=D.nodes.map(n=>n.id);if(D.nodes.length!==12){bad.push('FAIL pipeline 节点数 = '+D.nodes.length);}const uniq=new Set(ids);if(uniq.size!==ids.length){bad.push('FAIL pipeline 重复 node id');}const N4=D.nodes.find(n=>n.id==='00000000-0000-0000-0015-000000000004');if(!N4){bad.push('FAIL pipeline 缺 …0004 节点');}else{if(N4.kind!=='human_approval'){bad.push('FAIL pipeline …0004 kind = '+N4.kind);}if(N4.label!=='确认进入代码开发'){bad.push('FAIL pipeline …0004 label = '+N4.label);}if(N4.onFail!=='abort'){bad.push('FAIL pipeline …0004 onFail = '+N4.onFail);}if(N4.timeoutMinutes!==4320){bad.push('FAIL pipeline …0004 timeoutMinutes = '+N4.timeoutMinutes);}const ap=N4.approvalPrompt?N4.approvalPrompt:'';if(ap.length<80){bad.push('FAIL pipeline …0004 approvalPrompt 读空或过短 length='+ap.length);}for(const k of ['环境静态前提（只确认静态事实，不要求审批时所有服务在线）','环境 owner 已明确、建立方式已写明、可获得性已声明','动态健康状态由 implement-code 在第一个依赖环境的 TASK 前用 plan 指定的 readiness 证据即时验证','审批不为其背书']){if(ap.indexOf(k)<0){bad.push('FAIL pipeline …0004 approvalPrompt missing '+k);}}for(const k of ['重新执行 write-dev-tasks 后再确认','review-annotations','reject_reason']){if(ap.indexOf(k)>=0){bad.push('FAIL pipeline …0004 approvalPrompt residual '+k);}}}const N14=D.nodes.find(n=>n.reviewLoop);if(!N14){bad.push('FAIL pipeline 缺 reviewLoop 节点');}else{const rl=N14.reviewLoop;if(rl.repairRef!=='write-dev-plan'){bad.push('FAIL pipeline reviewLoop.repairRef = '+rl.repairRef);}if(rl.feedbackInput!=='review_feedback'){bad.push('FAIL pipeline reviewLoop.feedbackInput = '+rl.feedbackInput);}if(rl.attemptInput!=='self_repair_attempt'){bad.push('FAIL pipeline reviewLoop.attemptInput = '+rl.attemptInput);}if(rl.replayPolicy!=='rerun-listed-nodes-in-order'){bad.push('FAIL pipeline reviewLoop.replayPolicy = '+rl.replayPolicy);}if(rl.maxAttempts!==3){bad.push('FAIL pipeline reviewLoop.maxAttempts = '+rl.maxAttempts);}if(rl.onBlock!=='route-to-repair-node'){bad.push('FAIL pipeline reviewLoop.onBlock = '+rl.onBlock);}const wantP=['repair-plan','regenerate-tasks','rerun-current-review'],wantR=['write-dev-plan','write-dev-tasks','review-dev-plan'],wantI=['00000000-0000-0000-0015-000000000001','00000000-0000-0000-0015-000000000002','00000000-0000-0000-0015-000000000014'];const rp=rl.replayNodes?rl.replayNodes:[];if(rp.length!==3){bad.push('FAIL pipeline replayNodes 数 = '+rp.length);}else{for(let i=0;i<3;i=i+1){if(rp[i].purpose!==wantP[i]){bad.push('FAIL pipeline replayNodes['+i+'].purpose = '+rp[i].purpose);}if(rp[i].ref!==wantR[i]){bad.push('FAIL pipeline replayNodes['+i+'].ref = '+rp[i].ref);}if(rp[i].nodeId!==wantI[i]){bad.push('FAIL pipeline replayNodes['+i+'].nodeId = '+rp[i].nodeId);}if(ids.indexOf(rp[i].nodeId)<0){bad.push('FAIL pipeline replayNodes['+i+'] 悬空');}}}const pc=rl.passCondition?rl.passCondition:{};const al=pc.allOf?pc.allOf:[];if(al.length!==2){bad.push('FAIL pipeline passCondition.allOf 数 = '+al.length);}else{if(al[0].path!=='verdict'){bad.push('FAIL pipeline passCondition[0].path = '+al[0].path);}if(al[0].equals!=='pass'){bad.push('FAIL pipeline passCondition[0].equals = '+al[0].equals);}if(al[1].path!=='blockers'){bad.push('FAIL pipeline passCondition[1].path = '+al[1].path);}if(al[1].isEmpty!==true){bad.push('FAIL pipeline passCondition[1].isEmpty = '+al[1].isEmpty);}}}const hasWord=(t,w)=>{let i=0;for(;;){const k=t.indexOf(w,i);if(k<0){return false;}const a=k>0?t.charCodeAt(k-1):32,b=k+w.length<t.length?t.charCodeAt(k+w.length):32;if(WCH.indexOf(String.fromCharCode(a))<0&&WCH.indexOf(String.fromCharCode(b))<0){return true;}i=k+1;}};for(const n of D.nodes){for(const f of ['prompt','approvalPrompt']){const s=n[f];if(typeof s!=='string'){continue;}const low=s.toLowerCase();if(hasWord(low,'git')){bad.push('FAIL pipeline '+n.id+' '+f+' 命中 git');}if(hasWord(low,'journal')){bad.push('FAIL pipeline '+n.id+' '+f+' 命中 journal');}if(s.indexOf('review-annotations')>=0){bad.push('FAIL pipeline '+n.id+' '+f+' 命中 review-annotations');}if(s.indexOf('reject_reason')>=0){bad.push('FAIL pipeline '+n.id+' '+f+' 命中 reject_reason');}}}if(bad.length){console.log('audit-pipeline failures = '+bad.length);for(const x of bad){console.log(x);}process.exit(1);}console.log('audit-pipeline failures = 0');"] | 300 |
| cmd-05 | tools | . | node | ["-e","const cp=require('child_process'),fs=require('fs'),P=require('path');const R=process.cwd(),NL=String.fromCharCode(10),CR=String.fromCharCode(13)+NL;const read=p=>fs.readFileSync(P.join(R,p),'utf8').split(CR).join(NL);const bad=[];const base='49fa37748d9b2fc7fc58fd53f839e2ed293bde17';const WL=['skills/develop/write-dev-plan/SKILL.md','skills/develop/write-dev-tasks/SKILL.md','skills/develop/review-dev-plan/SKILL.md','skills/develop/implement-code/SKILL.md','pipeline-templates/code-implementation.pipeline.json'];const ZERO=['skills/shared/crctl/scripts/','skills/develop/write-tech-design/','skills/develop/review-tech-design/','skills/develop/review-code/','skills/develop/write-test-report/','skills/develop/coding-discipline/','pipeline-templates/','agents/','agent-skill-matrix.yml','AGENT-SKILL-MATRIX.md','dir-graph.yaml','ARCHITECTURE.md'];const CRCTL=P.join(R,'skills/shared/crctl/scripts/crctl.mjs');const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only',base,'--cwd',R],{encoding:'utf8',shell:false});if(r.status!==0){bad.push('FAIL diff crctl git diff status='+r.status);console.log(String(r.stderr?r.stderr:'').slice(-400));}else{const parts=String(r.stdout).split(NL);const bi=parts.findIndex(l=>l.trim()==='{');const changed=parts.slice(0,bi<0?parts.length:bi).map(s=>s.trim()).filter(Boolean);console.log('tools diff paths = '+changed.length);for(const f of changed){console.log('  '+f);}for(const f of changed){const inWL=WL.indexOf(f)>=0;if(!inWL){bad.push('FAIL diff 越界路径 '+f);}for(const z of ZERO){if(f.indexOf(z)===0){if(!inWL){bad.push('FAIL diff zero_diff 面被改动 '+f);}}}}for(const f of WL){if(changed.indexOf(f)<0){bad.push('FAIL diff 缺少应改文件 '+f);}const t=read(f);if(t.length<3000){bad.push('FAIL diff '+f+' 读空或过短 length='+t.length);}}}if(bad.length){console.log('audit-diff failures = '+bad.length);for(const x of bad){console.log(x);}process.exit(1);}console.log('audit-diff failures = 0');"] | 300 |
| cmd-06 | tools | . | node | ["-e","const cp=require('child_process'),fs=require('fs'),P=require('path');const R=process.cwd(),NL=String.fromCharCode(10);const read=p=>fs.readFileSync(P.join(R,p),'utf8').split(String.fromCharCode(13)+NL).join(NL);const bad=[];const run=(label,args)=>{const r=cp.spawnSync(process.execPath,args,{cwd:R,encoding:'utf8',shell:false});const s=String(r.stdout==null?'':r.stdout),e=String(r.stderr==null?'':r.stderr);console.log('['+label+'] exit='+r.status);if(r.status!==0){bad.push('FAIL '+label+' exit='+r.status);console.log(s.slice(-800));console.log(e.slice(-800));}};run('lint-prompts',['skills/shared/crctl/scripts/lint-prompts.mjs','--mode','enforce']);run('skill-matrix',['skills/shared/crctl/scripts/check-skill-matrix.mjs']);run('agents-contract',['skills/shared/crctl/scripts/check-agents-contract.mjs']);const wbDir=P.join(R,'skills/writeback/scripts/test');if(!fs.existsSync(wbDir)){bad.push('FAIL writeback 测试目录缺失（硬失败）');}else{const wb=fs.readdirSync(wbDir).filter(f=>f.endsWith('.test.mjs')).map(f=>'skills/writeback/scripts/test/'+f);if(wb.length<1){bad.push('FAIL writeback 测试文件未枚举到（硬失败）');}run('writeback-tests',['--test','--test-reporter=dot'].concat(wb));}const active=new Set();let cur=null;for(const l of read('skills/_index.yml').split(NL)){const t2=l.trim();if(t2.indexOf('- id:')===0){cur=t2.slice(5).trim();continue;}if(cur!==null&&t2==='status: active'){active.add(cur);}}const pfDir=P.join(R,'pipeline-templates');const pf=fs.readdirSync(pfDir).filter(f=>f.endsWith('.pipeline.json'));if(pf.length<1){bad.push('FAIL pipeline 模板未枚举到（硬失败）');}for(const f of pf){const raw=read('pipeline-templates/'+f);if(raw.length<500){bad.push('FAIL '+f+' 读空或过短 length='+raw.length);continue;}const d=JSON.parse(raw);if(!(d.id&&d.triggerCommand&&Array.isArray(d.inputs)&&Array.isArray(d.nodes))){bad.push('FAIL '+f+' 缺基础字段');}const ids=d.nodes.map(n=>n.id);if(new Set(ids).size!==ids.length){bad.push('FAIL '+f+' 重复 node id');}for(const n of d.nodes){if(n.kind==='skill'&&!n.ref){bad.push('FAIL '+f+' skill 节点缺 ref');}if(n.kind==='skill'&&n.ref&&!active.has(n.ref)){bad.push('FAIL '+f+' inactive ref '+n.ref);}const rl=n.reviewLoop;if(rl){if(rl.repairNodeId&&ids.indexOf(rl.repairNodeId)<0){bad.push('FAIL '+f+' 悬空 repairNodeId');}const rp=rl.replayNodes?rl.replayNodes:[];for(const x of rp){if(ids.indexOf(x.nodeId)<0){bad.push('FAIL '+f+' 悬空 replayNodes');}}}}}console.log('pipeline structure checked = '+pf.length+' active skills = '+active.size);if(bad.length){console.log('audit-ci failures = '+bad.length);for(const x of bad){console.log(x);}process.exit(1);}console.log('audit-ci failures = 0');"] | 300 |

#### 6.2.1 `cmd-03` 说明（AUDIT-SKILL，只读）

读取四份目标 SKILL 全文（CRLF 归一后，`length < 3000` 即红）＋ pipeline JSON；逐条打印 `FAIL <组> missing|residual <token>`（组 = `write` / `tasks` / `review` / `implement` / `pipeline`）＋末行 `audit-skill failures = N`（N=0 → exit 0）。**(a) write-dev-plan 写侧**：普通轨三条逐字保留；upstream 轨 11 token（`**upstream 轨（SDD 重新批准后的增量回修）**`、`**新旧批准 SDD 的变更 delta**`、`同轮未闭合 plan blockers`、`只重算受影响章节、稳定表行、证据与回滚`、`未受影响内容逐字保留`、`coordinator 只传 subject、delta 与 canonical feedback 引用`、`不指定具体行如何修改`、`不把旧 plan 当作整轮作废`、`review-dev-plan:upstream-design-blocker`、`本轨不修改 review-route 枚举`、`不把 \`repair-target\` 改成多值`）；Step 标题集仍为 `1,2,2a,3,4`；B-1 四 token（`观测面 ≥ 声称面：每个 \`cmd-NN\` 必须能观测该表行声称的 AC 结果`、四类典型错配整句（含 `--list` / 文件级 `--name-only` / 子集测试 / 受控入口 `rules.json` 四 token）、`不另立第二套形态判据`、`命令算法唯一事实源 = 证据命令表行；不得通过委派评论补写命令算法。`）；B-2 三项闭包判据；B-3 唯一事实源句；C 五要素 9 token（`若验收证据依赖常驻服务、浏览器或数据库`、`环境 owner、建立方式、可获得性：责任人与获得途径，不写具体命令；`、`readiness 证据：必须复用`、`证据ID 照抄证据命令表，不新增命令行`、`双向唯一映射不得放宽`、`另立 CR`、`缺失时处置：`、`唯一详细事实源是 \`implement-code\`，此处只引用不复述`、`不新增第八节`）；既有概括反假绿句保留；**反向断言**两张表头逐字存在（列集不变的机械载体：交付覆盖表该行 6 竖线且 5 列名齐备、证据命令表该行 7 竖线且 5 列名齐备）。**(b) write-dev-tasks**：need（`执行 plan→TASK delta 重算`、`直接受影响 TASK`、`下游依赖闭包`、`未受影响 TASK 保留`、`只用于刷新`、`同步更新受影响 TASK 的输入、输出、接口（接口契约节的消费/产出签名）、命令、\`depends-on\`、完成标志与回滚`、第 2/3 条原文、`crctl task init`、`禁止 Agent/Skill 手写`）；forbid（`重新生成`）。**(c) review-dev-plan**：need 10 token（两条加粗 blocker 句、四类错配四 token、`命令算法只存在于委派评论而不在证据命令表行`、`不留到 implement 阶段才暴露`、`不新增维度名或证据账本`、既有概括句）＋ 决策表行断言（含 `acceptance-verifiability:` 的行恰 1 竖线且含 `pass` 与 `block`）。**(d) implement-code**：need 7 token（两条新 bullets 四 token ＋ 既有「一次环境检查」「最多一次重跑」「唯一详细事实源」逐字保留）。**(e) pipeline**：`…0004.approvalPrompt` need 8 token（`TASK 拆分已完成`、静态前提确认句、owner/建立方式/可获得性句、动态健康由 implement-code 即时验证句、`审批不为其背书`、按缺口所属产物回写作节点句、`✅ 通过`、`❌ 暂缓`）；forbid（`重新执行 write-dev-tasks 后再确认`、`review-annotations`、`reject_reason`）；节点对象其余字段（kind=human_approval / label / onFail=abort / timeoutMinutes=4320）与节点数 12 不变。

#### 6.2.2 `cmd-04` 说明（AUDIT-PIPELINE，只读）

读取 pipeline 模板全文（CRLF 归一后，`length < 3000` 即红；JSON 解析异常即红）；逐条打印 `FAIL pipeline …` ＋末行 `audit-pipeline failures = N`。**(a)** `…0004` 节点对象其余字段不变（kind=human_approval / label「确认进入代码开发」/ onFail=abort / timeoutMinutes=4320），`approvalPrompt` 非空（`length < 80` 即红）且含 4 项静态前提 token（静态前提确认句、owner/建立方式/可获得性句、动态健康由 implement-code 即时验证句、`审批不为其背书`）、无 3 项残留 token（`重新执行 write-dev-tasks 后再确认`、`review-annotations`、`reject_reason`）；**(b)** 节点数 = 12、无重复 id、`…0014.reviewLoop` 逐项保持（repairRef=write-dev-plan；feedbackInput / attemptInput / replayPolicy；replayNodes 三项 `nodeId` + `ref` + `purpose` 逐字且目标节点存在；maxAttempts=3；passCondition.allOf 两项（verdict=pass / blockers isEmpty）；onBlock=route-to-repair-node）（`dep-8` 零改动面的机械载体）；**(c)** 全部节点 `prompt` 与 `approvalPrompt` 对 `git` / `journal` 词边界（大小写不敏感，等价 `\bgit\b` / `\bjournal\b`）与 `review-annotations` / `reject_reason` 复扫（`dep-15` 同款判据的本机冗余面，非替代 cmd-02）。

#### 6.2.3 `cmd-05` 说明（AUDIT-DIFF，只读）

以 `crctl git diff --name-only <基线> --cwd <tools worktree>` 取 diff 面（命令非零退出即红；先打印 `tools diff paths = N` 与原样路径清单）。**(a)** diff 面（相对基线 `49fa37748d9b2fc7fc58fd53f839e2ed293bde17`）**恰为 5 个文件**（白名单双向相等：4 个 SKILL + `code-implementation.pipeline.json`）——白名单外任一路径 = `越界路径` 红、白名单内缺任一文件 = `缺少应改文件` 红；**(b)** `zero_diff` 前缀表（`skills/shared/crctl/scripts/`、`write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline`、`pipeline-templates/`（白名单内该文件除外——由 (a) 的精确路径相等保证 `_index.yml` 与其余内容零改动）、`agents/`、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`dir-graph.yaml`、`ARCHITECTURE.md`）**无命中**；五个白名单文件均须可读（`length < 3000` 即红）。末行 `audit-diff failures = N`。

#### 6.2.4 `cmd-06` 说明（AUDIT-CI，只读）

CI 步骤的本机等价面（逐步 `spawnSync(node, args, { shell:false })`，每步打印 `[label] exit=N`；任一步非零即红并截取末 800 字符输出）：**(a)** `lint-prompts.mjs --mode enforce`；**(b)** `check-skill-matrix.mjs`；**(c)** `check-agents-contract.mjs`；**(d)** `skills/writeback/scripts/test/*.test.mjs`（枚举后整批跑；目录缺失或零命中 = 硬失败）；**(e)** pipeline JSON 结构断言（`id` / `triggerCommand` / `inputs[]` / `nodes[]` 齐备、重复 node id、skill 节点 `ref` 存在且在 `skills/_index.yml` 为 active、`reviewLoop.repairNodeId` 与 `replayNodes[]` 无悬空；模板枚举零命中 = 硬失败），并打印 `pipeline structure checked = N active skills = M`。**不新增 CI 面**，只作 NFR-1 与 AC-7 的本机证据；末行 `audit-ci failures = N`。

#### 6.2.5 转录纪律（cmd-03…cmd-06）

四条审计命令的 args 是**单个 `-e` 参数**（数组第二个元素），**字面值就是 §6.2 表内 cell**——本节只是书写约束说明，**不存在第二个生成步骤**：TASK-04 收口与 `write-test-report` 的 `cr-test-plan/v1` 一律**逐字转录**本表 cell（`JSON.parse` → `JSON.stringify` 往返与原 cell 逐字相同即可），不得在 plan 之外另行生成、改写或补写命令算法（证据命令表是 FR-3 判据域的唯一事实源，命令算法只写在本表内）。

四个脚本已按以下约束书写（可直接由本表字面值复核）：**不含**双引号 / 反斜杠 / 裸换行 / 竖线——换行常量用 `String.fromCharCode(10)`、CRLF 用 `String.fromCharCode(13)`、反引号用 `String.fromCharCode(96)`、竖线比较用 `String.fromCharCode(124)` 构造；单引号在 JSON 字符串内无需转义，可直接使用。四条命令已在本节点按 `spawnSync(executable, args, { shell:false })` 同语义实跑并留下变更前基线（§6.3：`cmd-03` = 54 failures / `cmd-04` = 5 failures / `cmd-05` = 5 failures / `cmd-06` exit 0）；实施期收口后须复跑至 `cmd-03` / `cmd-04` / `cmd-05` failures = 0、`cmd-06` exit 0（与 §6.3「变更后预期」列一致），再进入 `write-test-report` 的正式证据执行。

### 6.3 干跑/可达性记录（按 §6.2 表内字面命令实跑；只读，未改任何文件）

干跑语义 = `spawnSync(executable, args, { cwd: <repo worktree>/<cwd>, shell:false })`；下表为**变更前基线**实测（本节点，win32 / node v24.15.0；**回修 1/3 按 §6.2 表内字面 args 复跑**，下述数字即复跑实测）：

| 证据ID | 可达性 | 本条 run 实测 | 结论（变更前 / 变更后预期） |
|---|---|---|---|
| cmd-01 | 可达 | **exit 0 / 866.6 s / 21 文件 / 597 用例 / failures=0 / exceptions_count=0 / verdict=pass**（CR-2026-067 同款命令基线） | 变更前全绿；变更后须仍 `verdict=pass` / `failures=0`（本 CR 零测试改动，登记值 36 不动） |
| cmd-02 | 可达 | **exit 0 / 0.7 s / 74 点号**（目标文件两条文件级实跑） | 变更前与变更后均须 exit 0（新文字不触禁令） |
| cmd-03 | 可达 | **exit 1 / 54 failures**（`write` 组 28 项：upstream 轨 11 + B-1 四 token + B-2 三项 + B-3 一句 + C 五要素 9；`tasks` 组 7 项：delta 重算 6 token + 残留 `重新生成`；`review` 组 9 项：两条 blocker 句 + 四类错配四 token + 委派评论 + `不留到 implement 阶段才暴露` + `不新增维度名或证据账本`；`implement` 组 4 项：两条新 bullets 四 token；`pipeline` 组 6 项：静态前提 5 token + 残留旧 `❌` 分支——各项逐条对应 TASK-01/02/03/04 的交付物，无一项落在零 diff 面） | 实施前基线；实施后须 failures = 0 |
| cmd-04 | 可达 | **exit 1 / 5 failures**（`…0004.approvalPrompt` 缺新静态前提内容 4 项 + 残留旧 `❌` 分支 1 项；节点字段 / 节点数 / `…0014.reviewLoop` / 全节点禁词复扫均零失败） | 实施前基线；实施后须 failures = 0 |
| cmd-05 | 可达 | **exit 1 / 5 failures**（`tools diff paths = 0` ⇒ 5 项「缺少应改文件」） | 实施前基线；实施后须 `tools diff paths = 5` 且 failures = 0 |
| cmd-06 | 可达 | **exit 0 / 1.5 s**（`lint-prompts` / `skill-matrix` / `agents-contract` / `writeback-tests` 各 exit 0；`pipeline structure checked = 8` / `active skills = 56`） | 变更前与变更后均须 exit 0（本 CR 不新增静态面） |

- 六个命令均为**只读**：不写账本、不写登记面、不新增文件；干跑后 tools worktree `git status --porcelain` 为空（零残留）。

---

## 7. AC/业务闭环覆盖矩阵（契约必填节，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 upstream 轨四条 + 普通轨三条保留 + Step 编号不变 | §6.5-A ＋ §4.1 ＋ §1.4.1 | CR-2026-068-TASK-01 | cmd-03；cmd-02 |
| AC-2 delta 重算 + 闭包同步 + 未受影响保留 + 索引只刷新 + 无第二套规则 | §6.5-D ＋ §4.2 ＋ §1.4.2 | CR-2026-068-TASK-02 | cmd-03；cmd-02（`dep-17` 断言真实执行）；cmd-01 |
| AC-3 写侧六项判据 + 既有概括句保留 + 评侧两条 blocker 判据同表述 + 维度名/表头不变 | §6.5-B ＋ §6.5-E ＋ §4.3 | CR-2026-068-TASK-03（关联 CR-2026-068-TASK-01：写侧半边） | cmd-03（两侧 token）；cmd-02 |
| AC-4 `回滚` bullet 三项闭包判据、列集不变 | §6.5-B B-2 ＋ §4.4 | CR-2026-068-TASK-01 | cmd-03 |
| AC-5 plan 五要素（章节数 7 不新增节）+ dev-start 静态前提/两分支/零残留 + implement 两条 bullets/既有六条保留 | §6.5-C ＋ §6.5-F ＋ §6.5-G ＋ §4.5 | CR-2026-068-TASK-04（关联 CR-2026-068-TASK-01：plan 侧五要素半边） | cmd-03；cmd-02 |
| AC-6 双向唯一映射不放宽 + 无「另立 cmd-NN」形态 + 无法复用指向另立 CR | §6.5-C ④ ＋ §4.5 readinessMap ＋ §9 `follow_up` 1 | CR-2026-068-TASK-01（关联 CR-2026-068-TASK-04：plan 侧消费） | cmd-03（`证据ID 照抄证据命令表，不新增命令行` + `另立 CR` 出口句） |
| AC-7 交付 diff 恰 5 文件 + 零新增 + `zero_diff` 文件零改动 | §1.2 ＋ §4.6 ＋ §9 | CR-2026-068-TASK-04（关联 CR-2026-068-TASK-01/02/03） | cmd-05；cmd-06；cmd-01（`exceptions_count=0`） |
| AC-8 CR-2026-066 / 067 面零 diff（四 review SKILL Step 1.0/5/6、`write-tech-design`/`review-tech-design`、登记值 36） | §4.6 ④ ＋ §6.4 | CR-2026-068-TASK-04 | cmd-05（白名单否定面）；cmd-02（S-13 / CR-2026-055 用例真实执行）；cmd-01 |
| AC-9 在途仅本 CR、串行、零测试改动保持全绿 | §9 `scope_out` ＋ §6.4 ＋ §6.6 | CR-2026-068-TASK-04 | cmd-05（`gate-registry.json` 零 diff ⇒ 登记值不动）；cmd-01 |
| 业务闭环：同一条判据在写侧与评侧只有一个强度（观测面/四类错配/受控入口） | §4.3 ＋ §6.5-B/E | CR-2026-068-TASK-01（写侧半）＋ CR-2026-068-TASK-03（评侧半） | cmd-03（两侧同族 token 各自命中）；cmd-02 |
| 业务闭环：delta 重写面与 SDD delta 成正比（不整轮作废、不漏修下游） | §4.1/§4.2 ＋ §6.5-A/D | CR-2026-068-TASK-01（plan 半）＋ CR-2026-068-TASK-02（TASK 半） | cmd-03（`不把旧 plan 当作整轮作废` + 闭包同步 + 未受影响保留） |
| 业务闭环：环境静态前提人工确认与动态 readiness 执行分离（审批不背书动态健康） | §4.5 ＋ §6.5-G/F | CR-2026-068-TASK-04 | cmd-03（`审批不为其背书` + `环境无关 TASK 不被提前阻断`） |
| 业务闭环：readiness 不产生第二套验证语义（复用既有 `cmd-NN`） | §4.5 ＋ D-3 ＋ §6.5-C ④ | CR-2026-068-TASK-01 | cmd-03（照抄证据命令表 + 不新增命令行） |

> **关键 AC 唯一 owner 说明（机械可判）**
> - **AC-1 / AC-4 / AC-6 唯一 owner = TASK-01**（`write-dev-plan` 文本的实际产生层）。
> - **AC-3 唯一 owner = TASK-03**（`review-dev-plan` 判据行的实际产生层；写侧半边由 TASK-01 承担，§6.1 FR-3 行以 TASK-01 为主责、TASK-03 为关联）。
> - **AC-2 唯一 owner = TASK-02**（`write-dev-tasks` 第 1 条的实际产生层）。
> - **AC-5 / AC-7 / AC-8 / AC-9 唯一 owner = TASK-04**（AC-5 的三侧承载中 implement / dev-start 两边半与收口责任层在 TASK-04，plan 侧五要素半边为关联 TASK-01——与本矩阵 AC-5 行、§6.1 FR-5 行同口径；AC-7/AC-8/AC-9 = 交付面与零 diff 收口的实际责任层）。
> - 四张 TASK 均在矩阵中出现，与 `tasks/_index.yml#id` 集双向一致；业务闭环行不与关键 AC 行争用同一证据语义。
> - **无阻断**：全部 AC 的验收证据在实施后**可达**（§6.3 干跑记录；本 CR 不依赖未来证据，无「延期验证点」）。

---

## 8. 附带项与残余项收口对照

### A. 协调者转交的附带项（本轮逐条处置）

| # | 附带项 | 处置 | 落点 |
|---|---|---|---|
| 需求期 canonical suggestion（PRD §1.4 事实 21 的「cmp 逐字节 / 33,478 B」只在 EOL 归一后成立） | **已处理（继承 SDD 承接）**：SDD §1.5 / §6.7 / §7.1 已按「内容一致（EOL 归一后）」理解且未在任何目标文本写入 `cmp`/字节数口径；本计划四条审计命令全部先 `\r\n → \n` 归一（工程纪律 #1），`cmd-03` 不以字节数或 `cmp` 判定一致。**不改 `prd.md`**（冻结）；该处属需求文本、SDD `follow_up` 第 2 项，不在本 CR 修 | §4.1 R-12；§6.2.5 |
| 技术设计评审遗留 | 无遗留非阻塞项：上轮 1 条 blocker（`dep-23` 归属）与 5 条 suggestion 已全部闭环（canonical `review-annotations/sdd.yml`，attempt 2/3 pass） | 本表 |

### B. `zero_diff` 复核清单（四张 TASK 卡逐条声明不触碰，`cmd-05` / `cmd-06` 机械兜底）

- **文件级零 diff**（不在改动集合）：`skills/shared/crctl/scripts/**`（含全部测试与 `gate-registry.json`）、`skills/develop/write-tech-design/SKILL.md`、`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-code/SKILL.md`、`skills/develop/write-test-report/SKILL.md`、`skills/develop/coding-discipline/SKILL.md`、`pipeline-templates/` 内 `code-implementation.pipeline.json#…0004.approvalPrompt` 以外的全部内容（含 `_index.yml` 计数 5/4/12）、`tools/agents/**`、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`dir-graph.yaml`、`ARCHITECTURE.md`、`change-requests/CR-2026-068/prd.md`、KB 的 `specs/`+`delivery/`+`docs/`、`../multica/**`。
- **段级零 diff**（文件在改动集合内，下列对象逐字保留）：`write-dev-plan` 的 Step 1/2/3/4、TOC 编号、两张稳定表表头、既有概括反假绿句、章节 1~4 与 6~7 清单项；`write-dev-tasks` 的 Step 1/2/3/4 结构、Step 2a 第 2/3 条、`dep-6` 三步断言与受控账本句、TASK 卡结构；`review-dev-plan` 的八类维度表其余七行、四个增量维度名其余三个、Step 1.0/Step 5/Step 6、决策表行；`implement-code` 的环境节既有六条 bullets 与唯一事实源声明、其余全部章节；pipeline 的节点集/顺序/`…0014.reviewLoop`/其余全部节点 prompt 与 approvalPrompt。
- **无独立条目但零改动义务不变**：`advance` / `gate` / `review-record` / `checkpoint` 命令面（其零改动由 `crctl.mjs` 全文件零 diff 覆盖）。

### C. 本条 run 不处置（仅登记，防误作漏做）

- SDD `follow_up` 1~3 项：readiness 无法复用 `cmd-NN` 时的稳定表合同修改、需求文本 EOL 表述的后续 revision、观测面判据的机械化校验——**一律不得顺带实现**（本 CR 只做 §9 `scope_in` 的 5 个文件）。
- CR-P1（CR-2026-067）面、CR-P3 / CR-R / CR-S 的面：**零 diff**（本 CR 与 067 交付面互斥，SDD AC-8）。

---

## 9. TASK 拆分预分配（`write-dev-tasks` 的输入，共 4 个，组映射 1:1）

| 变更组 | 覆盖 FR | TASK id | 仓 | 粒度 | 依赖 | 估算 |
|---|---|---|---|---|---|---|
| G1 write-dev-plan 写侧三处落点（§6.5-A/B/C；FR-1、FR-3 写侧、FR-4、FR-5 plan 侧） | FR-1、FR-3（写）、FR-4、FR-5（plan） | CR-2026-068-TASK-01 | tools | 1 天 | — | 8h |
| G2 write-dev-tasks Step 2a 第 1 条 delta 重算改写（§6.5-D） | FR-2 | CR-2026-068-TASK-02 | tools | 1 天 | — | 8h |
| G3 review-dev-plan 评侧判据收紧（§6.5-E） | FR-3（评侧） | CR-2026-068-TASK-03 | tools | 1 天 | CR-2026-068-TASK-01 | 8h |
| G4 implement 侧两条 bullets + `…0004` approvalPrompt 值替换 + 交付面/零 diff 收口（§6.5-F/G） | FR-5（implement/dev-start）、FR-6 | CR-2026-068-TASK-04 | tools | 1 天 | CR-2026-068-TASK-01、CR-2026-068-TASK-02、CR-2026-068-TASK-03 | 6h |

- `task_count_hint = 4`（= 上表组数 = `tasks/_index.yml` 的 TASK 数 = §6.1/§7 出现的 canonical id 集）；`crctl task init CR-2026-068 --count-hint 4` 返回值 `totalEstimateHours` 期望 = **30h**。
- 三步断言（CR-2026-060 AC-08）：① **组映射 preflight**（Skill 内零 crctl 调用：恰 4 张卡、id = `CR-2026-068-TASK-01..04` 连续无重号、与上表一致；失败则删除草稿并 abort `TASK_COUNT_MISMATCH`）；② `crctl task init CR-2026-068 --count-hint 4`（写入前可数校验，失败零写入）；③ **init 后防并发复核**（以返回 `taskCount == 4` 为准，重跑组映射 preflight；不一致则保留现场、修正文件集后重跑同一命令，复核通过前不得 `advance --to task-breakdown`）。
- **TASK 卡的权威进度字段是 `tasks/_index.yml`**：卡片 frontmatter 的 `status` 一律 `pending`（`renderTaskIndex` 的渲染口径），真实状态只以账本为准（`crctl task done` 登记，带 `done-at`）。
- 四张卡的完成边界全部落在 `developing` 内可被 `crctl task done` 登记的事件（实现已落盘 + 证据命令绿 + 账本登记），**无 `merge` / `writeback` / `archive` / `code-reviewing` / `code-approved` 前置**（流程控制 TASK 禁止，CR-2026-057 FR-10）。
- 命名约定：`TASK-NN.md`（两位补零）；`slug` 英文 kebab-case ≤ 40 字符；`estimate` 形如 `Nh`（`^[1-9]\d*h$`）；`depends-on` 只引 canonical id 且无环（由 `loadTaskCards` 硬校验）。

---

## 10. 本计划不得越界（`zero_diff` 与本 CR 边界，逐条生效）

1. 不改 `sdd.md` / `prd.md` 一个字节（评审与审批双重绑定）。
2. 不改 `skills/shared/crctl/scripts/**` 任何文件（含 `crctl.mjs`、`lib/**`、测试、`gate-registry.json`）、`rules.json`、`gates.json`。
3. 不改 `pipeline-templates/**` 中 `…0004.approvalPrompt` 值以外的全部内容（含 `_index.yml` 计数与其余节点字段）、`agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、`agents/**`、`dir-graph.yaml`、`ARCHITECTURE.md`。
4. 不新增任何文件（含测试文件与 CI step）；`gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]` 保持 36、`exceptions` 保持 `[]`；不新增账本字段 / 评审维度名 / crctl 子命令·flag·错误码 / Skill 参数 / lint 规则。
5. 不重编号任何 Step；不新增小节层级（upstream 轨为加粗小标题非 `###`）；plan.md 章节数保持 7。
6. 不引入 `\bgit\b` / `\bjournal\b` / 三 token（`push-progress 之前`/`push-progress 之后`/`统一 checkpoint 后`）/ `review-annotations` / `reject_reason` / 退役字段名（`recoverCommand` 等）；不删 `write-tech-design` 现存 `crctl checkpoint` 句（该文件本就零 diff）。
7. `../multica` 零 diff（不改部署副本、不写 Go/TS、不改 `CUSTOM.md`）。
8. 不部署平台 Prompt、不重生成任何平台生成物、不启停任何共享服务。

---

## 11. 修订记录

- 初稿（2026-09-15，`code-implementation` node-1，本条 run）：按已审批 SDD（949 行 / sha256(LF) `d2562c30…`，与 `review-annotations/sdd.yml#subject-sha256` 全等）与冻结 PRD（sha256(LF) `5cb67f17…`）起草；**上一阶段发布收口在本节点首位执行完成**（batch `56fda17d5aa4c9b3` / metadataCommit `516c0d25…`，KB `6edaaf3d` 已推远端）；测试面基线在本节点实测（目标文件定点 exit 0 / 0.7 s / 74 点号；`manifest.cases=36`、`exceptions=[]`）；四组 TASK 预分配（8/8/8/6 h = 30 h）；6 条证据命令（`cmd-01`~`cmd-06`，其中 4 条审计命令在本节点干跑并留下变更前基线：64 / 5 / 5 failures 与 exit 0×3）；环境静态前提按 §6.5-C 自反声明（无常驻环境依赖，readiness 复用 `cmd-02`/`cmd-06`，不新增命令行）。
- 回修 1/3（2026-09-15，`review-dev-plan` cycle 1 attempt 1 = BLOCK，repair-target `write-dev-plan`）：① **定点修复 blocker（证据命令表 args 非可执行 argv）**——§6.2 证据命令表 `cmd-03`~`cmd-06` 的 `args` 列由「待实现期平面化」占位描述改为**字面 `-e` 脚本**（与 CR-2026-066/067 同款形态：无裸双引号 / 反斜杠 / 换行 / 竖线，换行/CRLF/反引号/竖线全部以 `String.fromCharCode(...)` 构造），并已按 `spawnSync(executable, args, {shell:false})` 同语义实跑复测：`cmd-03` = 54 failures、`cmd-04` = 5 failures、`cmd-05` = 5 failures（`tools diff paths = 0`）、`cmd-06` exit 0；表内 cell 经 `JSON.parse` / `JSON.stringify` 往返逐字复核（往返 = 表内 cell 逐字相同，竖线零出现）。§6.2.5 转录纪律改为「表内 cell 即字面值、逐字转录，无第二生成步骤、不依赖任何临时脚本文件」；§6.2 表注 ③ 同步为实现口径并新增 ⑥；§6.2.1~§6.2.4 判据描述与实现逐 token 对齐（含读空硬失败阈值）；§6.3 干跑记录更新为复跑实测（54 / 5 / 5 / exit 0，cmd-03 按 `write`/`tasks`/`review`/`implement`/`pipeline` 五组列出）；§5.4 预算行同步为复跑实测耗时。② 采纳本轮两条 `范围外` suggestion：§7「关键 AC 唯一 owner 说明」与 §6.1 / §7 表行口径统一（AC-5 → 主责 TASK-04、关联 TASK-01；AC-3 不再声称 TASK-01 在 §6.1 记为关联）；§0.5 / §2 / TASK-01 §2 的 `write-dev-plan/SKILL.md` 锚点行号按 tools@`49fa3774` 复核实测对齐（章节清单第 5 项 L57、`验收证据` bullet L68、`回滚` bullet L69、证据命令表区块 L73~L79）。③ §0.1 补充 `review-dev-plan=1/3` 回修轮状态。除上述定点修订外，`sdd.md` / `prd.md` 零触碰；交付面（5 文件 / 7 处落点）、四张 TASK 组映射（4 卡 / 30 h / 依赖序 `{TASK-01 ∥ TASK-02} → TASK-03 → TASK-04`）与 §6.1/§7 的证据映射未变。
