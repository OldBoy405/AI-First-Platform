---
spec-id: ai-first-platform
version: "0.40"
id: CR-2026-067-TASK-02
type: TASK
cr-ref: CR-2026-067
plan-ref: "change-requests/CR-2026-067/plan.md"
sdd-ref: "change-requests/CR-2026-067/sdd.md"
target-version: 0.40
title: "评侧两处原位修订：Step 2.1 两段改 dep-N 关系式核验与 commit SHA 必填 + 批准范围前置块追加同判据"
slug: review-side-dep-n-relations
status: pending
estimate: 8h
depends-on: []
created: 2026-09-15T10:05:00+08:00
---

# CR-2026-067-TASK-02 评侧两处原位修订（G2，FR-2 / FR-3 / FR-5 评侧）

## 1. 任务描述

**目标**：在 `skills/develop/review-tech-design/SKILL.md` 内**原位**完成 SDD §6.5-E1/E2 两处修订——Step 2.1 的两段改为「五要素核验 + `dep-N` 引用关系式 + `commit SHA` 必填（旧「并可附」零残留）+ 诚实边界」，Step 2「批准范围前置」引用块末追加与写侧逐字相同的四字段自洽判据。**不重编号任何 Step、不新增小节**。

**背景**：同一份合同此前对同一条事实给出两种强度（写侧必填 / 评侧「并可附」），且评侧判据是「是否漏列」的集合比较、缺一条可判定的关系式（PRD §1.1 第 2 条）。本卡把评侧收紧到与写侧同口径——这是本 CR **唯一**的强度变化（SDD §7.3），且只对评审发生时的 SKILL 版本生效，无追溯效力。

**输入条件**：CR status 进入实施期后为 `developing`；`sdd.md` 已审批（sha256(LF) `551f5a39…`，**不得改一字**）；tools worktree HEAD = `7094e492…`。

**范围边界（本卡只改 1 个文件）**：`skills/develop/review-tech-design/SKILL.md`。**逐条不触碰**：`write-tech-design/SKILL.md`（TASK-01）、两个测试文件与登记文件（TASK-03/04）、`crctl.mjs` / `scripts/lib/**` / `rules.json` / `gates.json` / `pipeline-templates/**` / `agent-skill-matrix.yml` / `AGENT-SKILL-MATRIX.md` / **`agents/**`（`quality-reviewer-agent.md` 零 diff，实测 `##` 小节 = 7）** / `dir-graph.yaml` / `ARCHITECTURE.md` / `review-requirement` / `review-dev-plan` / `review-code`（SDD §9 `zero_diff`）。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 锚点（本节点实测行号，实施期以实时搜索为准） |
|---|---|---|
| `skills/develop/review-tech-design/SKILL.md` | 改 3 处（两段原位替换 + 引用块末原位追加），**无新增小节、无 Step 重编号** | ① L87 Step 2.1 依赖核验段（旧「**并可附** `commit SHA`」在此段，实测 `grep -c '并可附'` = 1）；② L89 Step 2.1 核验手段段；③ L58 Step 2 引用块「**批准范围前置（CR-2026-057 FR-5/AC-5）**」末 |

**段级零 diff（本卡逐字保留）**：Step 1（含 `0. 只读 clean 前置` 条目与 `crctl workspace inspect` / `classification` 判据）、Step 2 的维度表与其余引用块、Step 2.1 的 SDD-CLOSE 义务核验段与 AC 闭环判定伪码（`no_design_landing(ac)` 四项）、Step 2.2 首轮全量句（逐字）、Step 2.3 分级边界与五个固定前缀、Step 3 / 4 / 5（PASS 发布与对账四要素）/ Step 6。**不引入** `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（实测当前各 0，本卡为**保持性**约束）；**不引入** `recoverCommand` / `recover_command`。

## 3. 实现要点

### 3.1 修订 ①（SDD §6.5-E1 前半）：L87 段**整段替换**为以下逐字目标文本

```text
SDD 的既有实现依赖必须来自名为“既有实现依赖与事实”的显式小节。该小节按正文首次依赖出现顺序维护有序清单，每项以稳定标识 `dep-N`（N 为正整数）开头，固定包含 `repo`、`relative path`、`stable symbol/对象`、`commit SHA` 和“依赖结论”五要素，其中 `commit SHA` 为必填的 40 位 SHA（缺失或与取证结果不符形成 blocker）。`sdd.explicit_existing_dependencies` 仅指该清单，不由 reviewer 扫描全仓库或临时猜测；reviewer 还必须核验 `dep-N` 引用规则：正文出现的 `dep-N` 必须在表中已定义，判据从「正文同类事实是否漏列」的集合比较升级为「正文引用是否由 `dep-N` 承载」的关系式——正文出现未通过 `dep-N` 引用承载的当前实现事实形成 blocker。本规则是 Prompt 合同，不宣称对自由文本事实的机械识别——判定仍属评审判断，不新增 crctl 校验面、lint 规则或 annotation dimension。
```

要点：① 五要素核验（`commit SHA` **必填 40 位**；缺失或与取证不符 → blocker）；② 关系式「正文出现的 `dep-N` 必须在表中已定义」；③ 未承载事实 → blocker（由「集合比较」**显式升级**为「引用关系式」，旧表述作为退化面在新文本中保留）；④ **旧「并可附 `commit SHA`」措辞零残留**；⑤ 诚实边界（Prompt 合同、不宣称 NLP 机械识别、不新增 crctl 校验面 / lint 规则 / annotation dimension）。

### 3.2 修订 ②（SDD §6.5-E1 后半）：L89 段**整段替换**为以下逐字目标文本

```text
只核验 SDD 明确写入且设计成立依赖的既有实现事实，不做全仓库无界扫描：对每项依赖按 `resources` 找到匹配 `repo`，用受控只读取证 `crctl git rev-parse HEAD` 取 commit SHA，并核验文件/稳定符号；事实缺失或行为不符形成业务 blocker（附 repo/SHA/path/symbol/conclusion 证据），资源缺失或不可读为技术失败且不写临时 payload。SDD 正文出现未被 `dep-N` 引用承载的当前实现事实形成 blocker；只有正文与依赖清单均无依赖时才记录 `N/A（本 CR 无既有实现依赖）`。行号只作辅助，不作唯一证据；评审不执行 lint/build/test。
```

要点：仅核心句改写（`dep-N` 关系式 + `N/A` 条件），**取证手段与边界逐字保留**（`crctl git rev-parse HEAD` 受控只读取证 / 资源缺失为技术失败 / 不写临时 payload / 行号只作辅助 / 不执行 lint·build·test / 不做全仓库无界扫描）。

### 3.3 修订 ③（SDD §6.5-E2）：L58 「批准范围前置」引用块**末原位追加**以下逐字文本

以 `> ` 前缀**延续同一引用块**（不新增引用块、不新增小节、不新增维度名）：

```text
四字段自洽判据（与 `write-tech-design` 章节 9 逐条同表述；判据只针对四字段之间的自相矛盾与必需条件错位，不针对详尽程度）：① `scope_in` 与 `zero_diff` 不得对同一对象同时要求「修改」与「不修改」；② 外部治理规则强制修改时，必须在 SDD 阶段把该对象纳入 `scope_in`、修订 `zero_diff`、或给出已有的合法出口；③ 不得用 `scope_out` 隐藏当前交付必须发生的治理修改；④ `follow_up` 不得承载当前 AC 的必要条件。任一一型命中 → blocker（`本轮新增：`），必须在 SDD 阶段形成，不得留到 dev-plan 再由 `review-dev-plan` 的 `upstream-design-blocker` 轨触发。
```

**跨 TASK 契约（AC-5①）**：`①`…`④` 四条判据的**同一表述**必须与 TASK-01 在写侧章节 9 中追加的版本**逐字节相同**；两侧**引导句与尾句**按角色不同（本卡为「与 `write-tech-design` 章节 9」+「任一一型命中 → blocker … `upstream-design-blocker` 轨触发」）。既有引用块内容（存在性判据、缺即 blocker、`本轮新增：` 前缀）**逐字保留**，本卡只做追加。

### 3.4 通用纪律

- 只改上述 3 处；Step 标题文本与编号集**逐一保持**（实测 `1,2,2.1,2.2,2.3,3,4,5,6`；「Step 1.0」的机械载体 = Step 1 段内 `0. **只读 clean 前置` 条目，其文本零改动）。
- 新增文字**不得**触发 `lint-prompts --mode enforce`（同 §3.4 约束）；**不把** Step 2.3 的分级边界扩大为「范围字段写得不够详细即 blocker」（判据只针对四字段之间的自相矛盾与必需条件错位）。
- 落盘后自查：`git status --short` 只显示本卡 1 个文件。

## 4. 验收条件（可执行）

1. **`cmd-03` 的评侧判据清零**（plan §6.2；`repo=tools`，`cwd=.`）：输出中**无** `FAIL review …` 行（评侧 25 项正向 token 全命中、`并可附` 零残留、四个反向 token 零命中），且**无** `FAIL 两侧…` 行（①~④ 与写侧逐字节相同——需 TASK-01 亦已完成）。整体 `exit 0` 属 TASK-04 的收口项。
2. **`cmd-06` exit 0**（CI 静态面本机等价，证明新增文本不触发 lint 规则）。
3. **`cmd-02` exit 0**：本卡改动**不打破**旧评侧 4 项 term（`名为“既有实现依赖与事实”的显式小节` / `有序清单` / `sdd.explicit_existing_dependencies` / `正文同类事实是否漏列`）与 CR-2026-066 断言 A/C/D（四个 review SKILL 不含 `crctl checkpoint` 与三个旧前提句）⇒ 中间态不红。
4. **负控自检**（非证据、不进 `test-evidence/`）：临时把 L87 的「为必填的 40 位 SHA（缺失或与取证结果不符形成 blocker）」改回旧措辞（可选 `commit SHA`）→ `cmd-03` 必须出现 `FAIL review 缺 为必填的 40 位 SHA` 与 `FAIL review 残留 并可附` → 还原 → 工作区干净。
5. **边界自查**：`write-tech-design/SKILL.md`、`agents/**`、两个测试文件与登记文件的 `git diff --stat` 为空；`grep -c '^## ' agents/quality-reviewer-agent.md` = 7。

## 5. 完成标志

- `skills/develop/review-tech-design/SKILL.md` 三处修订就位并随 CR 提交（`[cr]` 前缀消息）；`cmd-03` 评侧行与两侧比较行清零（在 TASK-01 亦完成的前提下）、`cmd-06` exit 0、`cmd-02` exit 0，三者输出留档。
- **六项可机械核对事实**写入任务完成记录：① `五要素` 核验句在位；② 「正文出现的 `dep-N` 必须在表中已定义」在位；③ 「未通过 `dep-N` 引用承载 … blocker」在位；④ `grep -c '并可附'` = **0**；⑤ 扫描边界与 Prompt 合同句在位；⑥ Step 编号集与四反向 token 计数（0/0/0/0）逐条留档。
- **不重编号任何 Step**、不新增小节、不复制判据进 `agents/**`（唯一事实源 = review SKILL）。
- **任务账本登记**：`crctl task done CR-2026-067 --task CR-2026-067-TASK-02`（带 `done-at`，即时登记，工程纪律 #8）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- `skills/develop/review-tech-design/SKILL.md` 既有文本：L58 引用块（`> **批准范围前置（CR-2026-057 FR-5/AC-5）**：其余维度之前，先核对 SDD「批准范围」固定章节——必须存在且承载四字段 … 缺章节或缺字段 → blocker（`本轮新增：`），本轮仍继续完成其余维度后统一生成 verdict。`）；L87 依赖核验段（四要素 + **并可附** `commit SHA` + `sdd.explicit_existing_dependencies` 边界 + 「交叉检查正文同类事实是否漏列」）；L89 核验手段段（`crctl git rev-parse HEAD` / 业务 blocker / 技术失败 / `N/A` 句 / `行号只作辅助` / `评审不执行 lint/build/test`）。
- `change-requests/CR-2026-067/sdd.md#§6.5-E1/E2`（逐字目标文本，实施期唯一来源；本卡正文摘录与之一致，冲突时以 SDD 为准）。
- TASK-01 产出的写侧 `①`…`④` 文本块（**逐字节**作为本卡评侧版本的比对基准；两卡任一漂移即 `cmd-03` 红）。

**产出（下游 TASK 消费方不得缩略）**

- 评侧合同的**三条关系式**（TASK-03 的评侧 term 断言逐字依赖）：显式小节 + 有序清单、`` `dep-N` 引用规则 ``（引用必须已定义）、`` `commit SHA` 为必填的 40 位 SHA ``（缺失或与取证不符 → blocker）、`正文同类事实是否漏列`（退化面保留）。
- 评侧**批准范围四字段自洽判据**的 `①`…`④` 文本块 + 尾句（「任一一型命中 → blocker」「不留到 dev-plan 的 `upstream-design-blocker` 轨」）。
- 上述产物同时是 TASK-03 的评侧 6 项 term 数组的**唯一来源**（逐字六项）：

  ```text
  名为“既有实现依赖与事实”的显式小节
  有序清单
  `dep-N` 引用规则
  `commit SHA` 为必填的 40 位 SHA
  sdd.explicit_existing_dependencies
  正文同类事实是否漏列
  ```
- **零 diff 承诺**（TASK-04 的 `cmd-05` 依赖）：`agents/quality-reviewer-agent.md` 与 Step 2.2 / 2.3 / 1.0 承载面逐字未改。
