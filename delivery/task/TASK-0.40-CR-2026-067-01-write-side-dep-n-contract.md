---
spec-id: ai-first-platform
version: "0.40"
id: CR-2026-067-TASK-01
type: TASK
cr-ref: CR-2026-067
plan-ref: "change-requests/CR-2026-067/plan.md"
sdd-ref: "change-requests/CR-2026-067/sdd.md"
target-version: 0.40
title: "写侧四处原位修订：Step 2.6 证据段与依赖小节改 dep-N 固定结构 + 回修句整体重证扩写 + 批准范围四字段自洽判据追加"
slug: write-side-dep-n-contract
status: pending
estimate: 8h
depends-on: []
created: 2026-09-15T10:05:00+08:00
---

# CR-2026-067-TASK-01 写侧四处原位修订（G1，FR-1 / FR-4 / FR-5 写侧）

## 1. 任务描述

**目标**：在 `skills/develop/write-tech-design/SKILL.md` 内**原位**完成 SDD §6.5-A/B/C/D 四处修订——既有实现事实收敛为带稳定标识 `dep-N` 的**唯一**依赖表（旧 `1. repo:` 编号列表形态退役）、回修句原位扩写为「整体重证 + 不扩散」双方向判据、章节 9「批准范围」末追加四字段自洽判据。**不新增小节、不重编号 Step、不新增结构件**。

**背景**：三项结构性问题的共同根因是「事实与判据缺一个可判定的承载体」（PRD §1.1）。写侧是 `dep-N` 形态的唯一产生点：正文只写「设计依赖 `dep-N`」、事实只在该表定义一次；评侧（TASK-02）只是同一合同的关系式核验方。

**输入条件**：CR status 进入实施期后为 `developing`；`sdd.md` 已审批（sha256(LF) `551f5a39…`，**不得改一字**）；`plan.md` §0.5/§6/§9 已冻结；tools worktree HEAD = `7094e492822594b971699924478ba27ccf612c42`（diff 审计基线）。

**范围边界（本卡只改 1 个文件）**：`skills/develop/write-tech-design/SKILL.md`。**逐条不触碰**：`review-tech-design/SKILL.md`（TASK-02）、两个测试文件与登记文件（TASK-03/04）、`crctl.mjs` / `scripts/lib/**` / `rules.json` / `gates.json` / `pipeline-templates/**` / `agent-skill-matrix.yml` / `AGENT-SKILL-MATRIX.md` / `agents/**` / `dir-graph.yaml` / `ARCHITECTURE.md` / 三个 `write-dev-*` SKILL / `review-requirement` / `review-code`（SDD §9 `zero_diff`）。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 锚点（本节点实测行号，实施期以实时搜索为准） |
|---|---|---|
| `skills/develop/write-tech-design/SKILL.md` | 改 4 处（原位替换 / 原位扩写 / 原位追加），**无新增小节** | ① L113 Step 2.6 既有实现证据段；② L115 标题下的 L117 首句 + L119–L125 固定结构块 + L127 结构块后句；③ L129 回修模式句；④ L88–L90 章节 9「批准范围」段末 |

**段级零 diff（本卡逐字保留）**：Step 1（含 L48 的 `crctl checkpoint` 提交口径句，实测计数 1，**不删**）、Step 2 的章节 1–8、Step 2.5、Step 2.6 的 AC 逐项映射合同与 AC 反查闭环、章节 9 的既有存在性判据与「`approve-tech-design` 后只读 / 双轨回上游」句、L131 SDD-CLOSE 关闭义务段、Step 3 / 4 / 5。**不引入** `crctl checkpoint` 家族反向 token（`push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`）与 `recoverCommand` / `recover_command`。

## 3. 实现要点

### 3.1 修订 ①（SDD §6.5-A）：L113 整段替换为以下**逐字**目标文本

```text
涉及既有实现（现有仓库、文件路径、稳定符号、配置键、接口/协议、数据库结构、模块行为、调用顺序或责任边界，且是方案成立前置条件）的断言，必须逐项附证据：`repo`、`commit SHA`、`relative path`、`stable symbol/对象`、`conclusion`；每条事实在 `### 既有实现依赖与事实` 表中获得稳定标识 `dep-N`（N 为正整数），其中 `commit SHA` 为必填的 40 位 SHA，编号按正文首次出现顺序分配、只增不改（正文增删条目不重编号，被删除的条目留下空洞、编号不复用）；实现事实只在该表定义一次，SDD 正文只能写「设计依赖 `dep-N`」，不得在正文重新陈述「当前代码已经如何工作」。无法绑定这些字段的引用按待核实依赖列出，不得归入 N/A。无既有实现依赖时才明确写 `N/A（本 CR 无既有实现依赖）`，不得用 N/A 掩盖正文中的事实依赖。核验必须覆盖正文所声称的实际行为，不以「文件或符号存在」代替行为成立。正文中的「现有、既有、复用、无需新增」等断言若在当前资源 HEAD 上不成立，必须改为新增能力设计或列入待核实依赖，不得继续作为方案前提。
```

相对原文的**唯一**新增内容：`dep-N` 稳定标识句（含「`commit SHA` 为必填的 40 位 SHA」与编号生命周期）＋「事实只在该表定义一次 / 正文只能写设计依赖 `dep-N`」句。既有五要素清单、「核验必须覆盖正文所声称的实际行为」、「现有/既有/复用/无需新增 的前提资格」逐字保留（**覆盖面不缩小**）。

### 3.2 修订 ②（SDD §6.5-B）：`### 既有实现依赖与事实` 小节三处

**L117 句 → 替换为**：

```text
当方案依赖既有实现时，必须在本节按正文首次出现顺序列出每项依赖，每项以稳定标识 `dep-N`（N 为正整数）开头，使用以下固定结构：
```

**固定结构块（`1. repo: …` 编号列表形态）→ 整块替换为**（注意：字段行**缩进两格**；`dep-1` 独立首行；旧 `1. repo:` 前缀**零残留**）：

```text
dep-1
  repo: <repository id>
  relative path: <path from repository root>
  stable symbol/对象: <symbol, key, interface, module, behavior, or responsibility>
  commit SHA: <40-character SHA>
  依赖结论: <verified current behavior required by this design>
```

**结构块后一句 → 替换为**：

```text
`review-tech-design` 只将本节的有序清单作为 `sdd.explicit_existing_dependencies`，并按 `dep-N` 引用关系核验正文：正文出现的 `dep-N` 必须已在本节定义；正文出现未被 `dep-N` 引用承载的当前实现事实是事实引用无承载。无法绑定字段的引用必须列入待核实依赖；只有本节与正文均无既有实现依赖时，才写 `N/A（本 CR 无既有实现依赖）`。
```

**不变量**：小节名 `### 既有实现依赖与事实` 与五个字段名（`repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论`）**逐字不变**；排序约束「正文首次出现顺序」保留；`sdd.explicit_existing_dependencies` 的消费口径语义不变（仍指有序清单）。

### 3.3 修订 ③（SDD §6.5-C）：L129 回修句原位扩写为以下**一句群**（替换原「回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案。」）

```text
回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案。blocker 触及状态判定、活动性、事件顺序、空值或失败回流时，必须重证该状态链的完整输入维度、分支、可见动作与对应 AC，不得只修被点名的那一格；同一标识符、锚点或 testid 在全文只能有一个裁决；未受该根因影响的已确认方案不得重写——「整体重证」与「不扩散」两个方向同时约束，前者防止只修一格，后者防止借重证之名重写无关设计。
```

（四项判据落在**同一句群**内：整体重证四维 / 不得只修一格 / 同一标识符唯一裁决 / 不扩散。**不新增** blocker 计数、轮数门禁或观测指标。）

### 3.4 修订 ④（SDD §6.5-D）：章节 9「批准范围」段末**原位追加**以下**逐字**文本

追加位置 = 既有段落末尾（`代码阶段发现实际 diff 越界时只回 `implement-code`。` 之后），**同一段落内**延续，不新增列表项、不新增小节：

```text
四字段自洽判据（与 `review-tech-design` 的「批准范围前置」逐条同表述；判据只针对四字段之间的自相矛盾与必需条件错位，不针对详尽程度）：① `scope_in` 与 `zero_diff` 不得对同一对象同时要求「修改」与「不修改」；② 外部治理规则强制修改时，必须在 SDD 阶段把该对象纳入 `scope_in`、修订 `zero_diff`、或给出已有的合法出口；③ 不得用 `scope_out` 隐藏当前交付必须发生的治理修改；④ `follow_up` 不得承载当前 AC 的必要条件。不新增第五个字段、不新增独立 ledger 文件、不新增状态、不新增评审维度名。
```

**跨 TASK 契约（AC-5①）**：`①`…`④` 四条判据的**同一表述**必须与 TASK-02 在 `review-tech-design` 中追加的版本**逐字节相同**（`cmd-03` 以 `① \`scope_in\` 与 \`zero_diff\` 不得对同一对象同时要求` 与 `④ \`follow_up\` 不得承载当前 AC 的必要条件` 为切段标记做逐字节比较）；两侧的**引导句与尾句**按角色不同（本卡为「与 `review-tech-design` 的『批准范围前置』」+「不新增第五个字段…」）。

### 3.5 通用纪律

- 只改上述 4 处；其余行**零改动**（含文件末尾换行形态：保持 LF 与文件既有行尾）。
- 新增文字**不得**触发 `lint-prompts --mode enforce`：不写裸 `git` 命令、不写状态名枚举（同段 3 个以上具名状态）、不写「下一步」的 skill/pipeline 名映射、不手写 guard-deny 文件指示（`cmd-06` 机械兜底）。
- 不顺带实现 SDD `follow_up` 1~6 项与 CR-P2/P3/R/S 的任何面。
- 落盘后自查：`git status --short`（经 `crctl git status --short`）只显示本卡 1 个文件。

## 4. 验收条件（可执行）

1. **`cmd-03` 的写侧判据清零**（plan §6.2；`repo=tools`，`cwd=.`）：输出中**无** `FAIL write …` 行（写侧 22 项正向 token 全命中、旧 `1. repo:` 零残留、四面修订齐备）。该命令是写侧 + 评侧 + 两侧比较的**聚合**判据，本卡只对写侧行负责；整体 `exit 0` 属 TASK-04 的收口项。
2. **`cmd-06` exit 0**（CI 静态面本机等价：`lint-prompts --mode enforce` / `check-skill-matrix` / `check-agents-contract` / `writeback-tests` / pipeline JSON 结构）——证明新增文本不触发 R1/R2/R7/R9/R12/R13。
3. **`cmd-02` exit 0**（`pipeline-structure.test.mjs` + `contract-scan.test.mjs`）：本卡的改动**不打破** L616 目标用例的**旧** term 组（写侧 8 项、评侧 4 项在目标文本中被逐字保留）与 CR-2026-066 断言 A/B/C/D ⇒ 中间态不红。
4. **负控自检**（非证据、不进 `test-evidence/`）：临时把固定结构块首行改回 `1. repo: <repository id>` → `cmd-03` 必须出现 `FAIL write 残留 1. repo:` → 还原 → 工作区干净。
5. **边界自查**：`review-tech-design/SKILL.md`、两个测试文件与登记文件、`agents/**`、`pipeline-templates/**` 的 `git diff --stat` 为空。

## 5. 完成标志

- `skills/develop/write-tech-design/SKILL.md` 四处修订就位并随 CR 提交（`[cr]` 前缀消息）；`cmd-03` 写侧行清零、`cmd-06` exit 0、`cmd-02` exit 0，三者输出留档。
- **`dep-N` 形态的四项可机械核对事实**写入任务完成记录：① `dep-1` 独立首行 + 五字段缩进两格；② `grep -c '1. repo:'` = **0**；③ `commit SHA: <40-character SHA>` 行在位；④ 编号生命周期句（「只增不改 … 编号不复用」）在位。
- 修订 ③/④ 的**四项判据**与**四条自洽判据**逐条留档（判据 → 落点行 → 原文摘录）。
- `crctl checkpoint` 在本文档内的计数仍为 **1**（不删该句，`cmd-05` 兜底）。
- **任务账本登记**：`crctl task done CR-2026-067 --task CR-2026-067-TASK-01`（`tasks/_index.yml` 即时标 `done` 并带 `done-at`，不积压到回写期，工程纪律 #8）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- `skills/develop/write-tech-design/SKILL.md` 既有文本：L113 证据段（五要素清单含 `commit SHA`、待核实依赖、`N/A` 条件、「核验必须覆盖正文所声称的实际行为」、「现有/既有/复用/无需新增」前提资格句）；L115 小节标题 `### 既有实现依赖与事实`；L117 首句；L119–L125 固定结构块（`1. repo: <repository id>` / `   relative path: …` / `   stable symbol/对象: …` / `   commit SHA: <40-character SHA>` / `   依赖结论: …`）；L127 消费口径句（含 `sdd.explicit_existing_dependencies`）；L129 回修句；L88–L90 章节 9 全段（四字段承载 + 空字段写 `无`/`N/A` + `approve-tech-design` 后只读 + `review-dev-plan` 双轨）。
- `change-requests/CR-2026-067/sdd.md#§6.5-A/B/C/D`（逐字目标文本，实施期唯一来源；本卡正文摘录与之一致，冲突时以 SDD 为准）。

**产出（下游 TASK 消费方不得缩略）**

- 写侧合同的**四条可判定不变量**（TASK-03 的写侧 term 断言逐字依赖）：`dep-N` 固定结构（含 `dep-1` / 五字段名 / `commit SHA: <40-character SHA>`）、「事实只在该表定义一次 + 正文只能写设计依赖 `dep-N`」、「`commit SHA` 为必填的 40 位 SHA」、「编号按正文首次出现顺序分配、只增不改 / 编号不复用」。
- 写侧**批准范围四字段自洽判据**的 `①`…`④` 文本块（TASK-02 的评侧版本必须与其逐字节相同；`cmd-03` 直接比较）。
- 写侧**回修四判据**句群（`cmd-03` 逐 token 核验）。
- 上述产物同时是 TASK-03 的写侧 9 项 term 数组的**唯一来源**：`['### 既有实现依赖与事实','正文首次出现顺序','dep-N','repo:','relative path:','stable symbol/对象:','commit SHA:','依赖结论:','sdd.explicit_existing_dependencies']`。
