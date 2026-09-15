---
id: CR-2026-068-TASK-01
type: TASK
cr-ref: CR-2026-068
plan-ref: "change-requests/CR-2026-068/plan.md"
sdd-ref: "change-requests/CR-2026-068/sdd.md"
target-version: 0.41
title: "write-dev-plan 写侧三处落点：Step 2a 末追加 upstream 轨四条 + 两张稳定表说明三处原位扩写 + 章节清单第 5 项替换为环境五要素"
slug: write-dev-plan-write-side
status: pending
estimate: 8h
depends-on: []
created: 2026-09-15T23:25:00+08:00
---

# CR-2026-068-TASK-01 write-dev-plan 写侧三处落点（G1，FR-1 / FR-3 写侧 / FR-4 / FR-5 plan 侧）

## 1. 任务描述

**目标**：在 `skills/develop/write-dev-plan/SKILL.md` 内**原位**完成 SDD §6.5-A/B/C 三处落点——Step 2a 段末追加 upstream 轨（加粗小标题 + 四条，**不另起 `###`**）、两张稳定表说明三处扩写（B-1/B-2/B-3）、章节清单第 5 项整体替换为环境五要素。**不新增小节、不重编号 Step、不新增列、章节数保持 7**。

**背景**：FR-1 的 delta 回修语义、FR-3 的观测面判据、FR-4 的回滚闭包判据、FR-5 plan 侧的环境声明全部以本文件为唯一写侧承载（SDD §1.2 / §6.1）。评侧（TASK-03）按 I3「同表述、同强度」消费本卡落地的文本。

**输入条件**：CR status 进入实施期后为 `developing`；`sdd.md` 已审批（sha256(LF) `d2562c30…`，**不得改一字**）；`plan.md` §0.5/§6/§9 已冻结；tools worktree HEAD = `49fa37748d9b2fc7fc58fd53f839e2ed293bde17`（diff 审计基线）。

**范围边界（本卡只改 1 个文件）**：`skills/develop/write-dev-plan/SKILL.md`。**逐条不触碰**：`write-dev-tasks/SKILL.md`（TASK-02）、`review-dev-plan/SKILL.md`（TASK-03）、`implement-code/SKILL.md` 与 `code-implementation.pipeline.json`（TASK-04）、`skills/shared/crctl/scripts/**`（含测试与 `gate-registry.json`）、`write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline`、`pipeline-templates/**` 其余内容、`tools/agents/**`、`agent-skill-matrix.yml`、`dir-graph.yaml`、`ARCHITECTURE.md`（SDD §9 `zero_diff`）。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 锚点（plan §0.5 实测行号，实施期以实时搜索为准） |
|---|---|---|
| `skills/develop/write-dev-plan/SKILL.md` | 改 3 处落点（B 内含 3 个子点）：① Step 2a 段末追加；② `验收证据` / `回滚` bullets 扩写 + 证据命令表 bullets 后追加一句；③ 章节清单第 5 项整体替换 | ① `### Step 2a — 回修模式（CR-2026-026 FR-8/FR-9）` 段末（第 3 条之后、`### Step 3` 之前）；② L76 `验收证据` bullet / L78 `回滚` bullet / L77 证据命令表 bullets 末尾；③ L55 `5. **验收与发布策略** — 发布前 checklist / feature-flag 计划` |

**段级零 diff（本卡逐字保留）**：Step 1 / Step 2 其余章节清单项（1~4、6、7）/ Step 2a 普通轨三条 / Step 3 / Step 4 / 两张稳定表表头与列集 / 证据命令表六项既有形态判据 bullets / frontmatter。**不引入** `crctl checkpoint` 家族反向 token、`git`/`journal` 字面量、退役字段名（`recoverCommand` / `recover_command` / `repair-instructions` / `fixed-blockers` / `suggestion_policy`）。

## 3. 实现要点

### 3.1 修订 ①（SDD §6.5-A）：Step 2a 段末（既有三条之后）追加以下**逐字**文本

```text
**upstream 轨（SDD 重新批准后的增量回修）**：当回修输入来自 `review-dev-plan:upstream-design-blocker` 之后的 SDD 修订与重新批准（人工修订 → 重新评审 → 重新批准 → 按 pipeline 既有 reviewLoop 重放本节点）时：

1. 输入 = **新旧批准 SDD 的变更 delta** 与**同轮未闭合 plan blockers**；不把旧 plan 当作整轮作废。
2. 在**同一份 `plan.md`** 上只重算受影响章节、稳定表行、证据与回滚；未受影响内容逐字保留（重写面与 delta 成正比）。
3. coordinator 只传 subject、delta 与 canonical feedback 引用，**不指定具体行如何修改**。
4. 本轨不修改 review-route 枚举、不把 `repair-target` 改成多值：路由仍由既有 `review-dev-plan` Step 4 UPSTREAM 分支与状态机既有转换承载。
```

**保持性**：普通轨三条逐字保留；加粗小标题形态（**非 `###`**）；`### Step 3 — 落盘并 commit` 标题不动；Step 标题集仍为 `1,2,2a,3,4`。

### 3.2 修订 ②（SDD §6.5-B）：两张稳定表说明三处

**B-1：`验收证据` bullet——既有句逐字保留，其后追加三条子项**（子项缩进对齐既有子项层级）：

```text
   - `验收证据`：稳定标识 `cmd-NN`（两位十进制，与 `crctl test` 机器区 `commands` 1-based 下标及 `test-evidence/cmd-NN.log` 全等）；该命令必须实际覆盖本行所声称的验收面，不得只覆盖其中一部分造成假绿。
     - 观测面 ≥ 声称面：每个 `cmd-NN` 必须能观测该表行声称的 AC 结果；命令的可执行形态（`executable` / `args` / `cwd` / `timeout` 四项）沿用证据命令表 bullets 的既有口径，此处只引用不复述细节，不另立第二套形态判据。
     - 四类典型错配：`--list` 类命令不能证明浏览器行为；文件级 `--name-only` 不能证明符号级不变量；子集测试不能声称全量；涉及 Git 的命令必须使用 `rules.json` 已允许的受控入口（不新开裸面、不改 `rules.json`）。
     - 命令算法唯一事实源 = 证据命令表行；不得通过委派评论补写命令算法。
```

**B-2：`回滚` bullet——既有句逐字保留，其后追加闭包判据**：

```text
   - `回滚`：该 FR 的回滚单元（如 revert 某 TASK commit）；被其它 TASK 消费的共享改动，其回滚单元必须包含受影响下游消费者，并与第 4 章「风险与回滚策略」的逆拓扑顺序一致；单点 revert 会破坏下游时不得声明为单点回滚。
```

**B-3：证据命令表 bullets 之后追加一句（不改既有 bullets）**：

```text
   - 证据命令表的命令行是 `cmd-NN` 的唯一事实源：命令算法只写在表内（`executable` / `args` / `cwd` / `timeout`），不得另行改写或补写。
```

**保持性**：交付覆盖表表头 `| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |` 与证据命令表表头 `| 证据ID | repo | cwd | executable | args | timeout |` **逐字不变**（5 列 / 6 列不增删）；既有概括反假绿句保留，**不另立第二句概括**（AC-3①）。

### 3.3 修订 ③（SDD §6.5-C）：章节清单第 5 项整体替换为以下**逐字**文本

```text
5. **验收与发布策略** — 发布前 checklist / feature-flag 计划；若验收证据依赖常驻服务、浏览器或数据库，本节必须同时写明环境的静态前提与即时验证口径（不新增第八节）：
   - 环境 owner、建立方式、可获得性：责任人与获得途径，不写具体命令；
   - readiness 证据：必须复用**该环境所保障的那一行 FR 的既有 `cmd-NN`**（证据ID 照抄证据命令表，不新增命令行）。两张稳定表「验收证据 ↔ 证据ID」双向唯一映射不得放宽；确实无法复用时，该诉求超出本计划边界，**另立 CR** 修改稳定表合同与对应评审判据，本计划不放宽该映射；
   - 缺失时处置：按既有 `ENVIRONMENT_MISMATCH` 标签中止并报告所需建立动作（该标签的唯一详细事实源是 `implement-code`，此处只引用不复述）。
```

**保持性**：章节数保持 7（不新增第八节）；章节清单第 1~4、6、7 项逐字不动。

### 3.4 通用纪律

- 只改上述 3 处落点；其余行**零改动**（保持 LF 与文件既有行尾；落盘后以归一化读取复核无混合 EOL）。
- 新增文字**不得**触发 `lint-prompts --mode enforce`：不写裸 `git` 命令、不写状态名枚举映射、不写「下一步」的 skill/pipeline 名映射、不指示手写受保护账本（`cmd-06` 机械兜底）。
- 新增文字**不得**含退役字段名与 `…0004` 字面禁令 token（`cmd-02` 的 `contract-scan.test.mjs` / `pipeline-structure.test.mjs` 真实执行面兜底）。
- 不顺带实现 SDD `follow_up` 1~3 项与 CR-P1/P3/R/S 的任何面。
- 落盘后自查：`git status --short`（经 `crctl git status --short`）只显示本卡 1 个文件。

## 4. 验收条件（可执行）

1. **`cmd-03` 的写侧判据清零**（plan §6.2；`repo=tools`，`cwd=.`）：输出中**无** `FAIL write …` 行（upstream 轨 11 项 + B-1/B-2/B-3 判据 + 五要素判据全命中、两条表头逐字在位、普通轨三条逐字在位）。整体 `exit 0` 属 TASK-04 的收口项。
2. **`cmd-02` exit 0**（`pipeline-structure.test.mjs` + `contract-scan.test.mjs`）：本卡改动不触任何字面禁令 ⇒ 中间态不红。
3. **`cmd-06` exit 0**（lint-prompts / skill-matrix / agents-contract / writeback-tests / pipeline JSON 结构）——证明新增文本不触 R1/R2/R7/R9/R12/R13。
4. **负控自检**（非证据、不进 `test-evidence/`）：临时删除 B-2 追加的闭包判据句 → `cmd-03` 必须出现 `FAIL write missing 被其它 TASK 消费的共享改动…` → 还原 → 工作区干净。
5. **边界自查**：其余 4 个交付文件与全部 `zero_diff` 面的 `git diff --stat` 为空。

## 5. 完成标志

- `skills/develop/write-dev-plan/SKILL.md` 三处落点就位并随 CR 提交（`[cr]` 前缀消息）；`cmd-03` 写侧行清零、`cmd-02` / `cmd-06` exit 0，输出留档。
- 三处落点的可机械核对事实写入任务完成记录：① Step 标题集仍 `1,2,2a,3,4` 且 upstream 轨为加粗小标题；② 两条表头逐字在位、`验收证据` bullet 含三条子项；③ 章节清单第 5 项为环境五要素且章节数 7。
- **任务账本登记**：`crctl task done CR-2026-068 --task CR-2026-068-TASK-01`（`tasks/_index.yml` 即时标 `done` 并带 `done-at`，不积压到回写期，工程纪律 #8）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- `skills/develop/write-dev-plan/SKILL.md` 既有文本：Step 2a 普通轨三条（`1. 逐条消费 blockers（每条内含可执行修复说明），修订同一份 \`plan.md\`；只处理评审指出的问题，不扩散 SDD 范围。` / `2. 禁止只刷新评审证据而不修改被指出的产物（空转由下一轮评审重新读取实际产物继续 BLOCK 兜底）。` / `3. 回修期间允许 status=\`tech-design-reviewed\`（普通轨重放态），不因非 task-breakdown abort.`）；两张稳定表表头与既有 bullets；章节清单第 5 项现行文本。
- `change-requests/CR-2026-068/sdd.md#§6.5-A/B/C`（逐字目标文本，实施期唯一来源；本卡正文摘录与之一致，冲突时以 SDD 为准）。

**产出（下游 TASK 消费方不得缩略）**

- 写侧观测面判据的**同族 token 集**（观测面 ≥ 声称面 / 四类典型错配四 token / 受控入口 / 命令算法唯一事实源）——TASK-03 评侧版本必须与同表述同强度（I3），`cmd-03` 两侧各自命中。
- 环境五要素与 readiness 复用既有 `cmd-NN` 判据——TASK-04 的 `…0004` approvalPrompt 文字按 §6.5-G 消费（plan 侧环境声明回 write-dev-plan 的修复路径句）。
- upstream 轨四条——`review-dev-plan` 既有双轨路由（`dep-7`）的写侧合同面；`cmd-03` 逐 token 核验。
