---
spec-id: ai-first-platform
version: "0.41"
id: CR-2026-068-TASK-03
type: TASK
cr-ref: CR-2026-068
plan-ref: "change-requests/CR-2026-068/plan.md"
sdd-ref: "change-requests/CR-2026-068/sdd.md"
target-version: 0.41
title: "review-dev-plan 评侧判据同表述收紧：acceptance-verifiability bullet 整体替换为两条 blocker 判据"
slug: review-dev-plan-verifiability
status: pending
estimate: 8h
depends-on: [CR-2026-068-TASK-01]
created: 2026-09-15T23:25:00+08:00
---

# CR-2026-068-TASK-03 review-dev-plan 评侧判据同表述收紧（G3，FR-3 评侧）

## 1. 任务描述

**目标**：在 `skills/develop/review-dev-plan/SKILL.md` 内**原位整体替换** `acceptance-verifiability` bullet（SDD §6.5-E）——在同一既有维度行内补齐两条可判定 blocker 判据（**观测面窄于声称面即 blocker** / **命令形态越受控边界即 blocker**），同表述、同强度对齐 TASK-01 落地的写侧判据（SDD I3）。**不新增维度名、不新增证据账本；八类维度表其余七行与四个增量维度名其余三个零改动。**

**背景**：FR-3 评侧的唯一落点（SDD §6.1）。现行文字只有概括判据（真实责任边界组合证明 AC、拒绝假绿短路）；本卡在该条内追加判据，使「假绿证据」在 dev-plan 阶段被拦截，不留到 implement 阶段。

**输入条件**：同 TASK-01；**依赖 TASK-01 先落地**（评侧判据消费写侧同族措辞；`cmd-03` 两侧 token 各自命中）。

**范围边界（本卡只改 1 个文件）**：`skills/develop/review-dev-plan/SKILL.md`。**逐条不触碰**：其余 4 个交付文件、全部 `zero_diff` 面（含本文件的 Step 1.0 / Step 5 / Step 6 与决策表行 `acceptance-verifiability: pass | block`）。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 锚点 |
|---|---|---|
| `skills/develop/review-dev-plan/SKILL.md` | 改 1 处：L82 `acceptance-verifiability` bullet 整体替换 | 实测：L82 现行文 `- \`acceptance-verifiability\`：核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路。`；L129 决策表行 `acceptance-verifiability: pass | block`（不动）；八类维度表与四个增量维度名（不动） |

**段级零 diff（本卡逐字保留）**：`### Step 1`（含 `0. **只读 clean 前置` 条目）/ `### Step 2` 八类维度表 / 其余三个增量维度 / `### Step 4 — 路由处理` 双轨分支（`dep-7` 面：NORMAL / UPSTREAM + 覆盖矩阵双向唯一映射判据）/ `### 覆盖矩阵与流程控制核验` / Step 5 / Step 6。**不引入** 三 token（`push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`）与 `crctl checkpoint`（`dep-15` S-13 反向断言面，`cmd-02` 真实执行）。

## 3. 实现要点

### 3.1 修订（SDD §6.5-E）：L82 bullet 整体替换为以下**逐字**文本

```text
- `acceptance-verifiability`：核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路；同一判据覆盖证据命令的证明力——**观测面窄于声称面即 blocker**（命令无法观测该表行声称的 AC 结果、`--list` 类命令声称浏览器行为、文件级 `--name-only` 声称符号级不变量、子集测试声称全量），**命令形态越受控边界即 blocker**（涉及 Git 的命令未使用 `rules.json` 已允许的受控入口、命令算法只存在于委派评论而不在证据命令表行），不留到 implement 阶段才暴露。判据落在既有维度内，不新增维度名或证据账本。
```

### 3.2 保持性

- 既有概括句「核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路」**保留在同一条内**（不删除、不另立第二条）。
- 判据落在**既有维度行内**：八类维度表行名与四个增量维度名零新增；决策表行 `acceptance-verifiability: pass | block` 逐字不动。
- 新文字与 TASK-01 写侧判据**同表述同强度**（I3）：观测面 / 四类错配四 token / 受控入口 / 委派评论四处措辞与 §6.5-B B-1 同族。

### 3.3 通用纪律

同 TASK-01 §3.4（行尾 / lint 避让 / 退役字段名 / follow_up 不顺带实现 / 单文件自查）；额外注意本文件是 S-13 反向断言的载体之一，**任何新文字不得含** `crctl checkpoint` 与三个三 token 字面量。

## 4. 验收条件（可执行）

1. **`cmd-03` 的 review 判据清零**：输出中**无** `FAIL review …` 行（11 项正向 token 全命中：两条加粗 blocker 句、四类错配四 token（含受控入口 `rules.json`）、委派评论（`命令算法只存在于委派评论而不在证据命令表行`）、`不留到 implement 阶段才暴露`、`不新增维度名或证据账本`、既有概括句仍在、决策表行仍在）。
2. **`cmd-02` exit 0**：S-13 反向断言（四个 review SKILL 对三 token 与 `crctl checkpoint` 零命中）真实执行仍绿。
3. **`cmd-06` exit 0**（同 TASK-01）。
4. **负控自检**（非证据）：临时把该 bullet 还原为现行概括句 → `cmd-03` 必须出现 `FAIL review missing **观测面窄于声称面即 blocker**` → 再落地 → 工作区干净。
5. **边界自查**：其余 4 个交付文件与全部 `zero_diff` 面的 `git diff --stat` 为空。

## 5. 完成标志

- `skills/develop/review-dev-plan/SKILL.md` 判据行替换就位并随 CR 提交；`cmd-03` review 行清零、`cmd-02` / `cmd-06` exit 0，输出留档。
- 可机械核对事实写入任务完成记录：① 两条加粗 blocker 句在位；② 八类维度表行名集合与决策表行实测未变（`grep -c 'acceptance-verifiability'` 前后对比留档）；③ 三 token 零命中。
- **任务账本登记**：`crctl task done CR-2026-068 --task CR-2026-068-TASK-03`（即时标 `done`，工程纪律 #8）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- `skills/develop/review-dev-plan/SKILL.md` 既有文本：L82 概括句、八类维度表、四个增量维度名、Step 4 双轨路由与覆盖矩阵双向唯一映射判据（`dep-7`）、决策表行。
- TASK-01 产出的写侧判据同族 token（`dep-3` 新 B-1 三子项）——I3 同表述约束的消费来源。
- `change-requests/CR-2026-068/sdd.md#§6.5-E` 与 §4.3（逐字目标文本；冲突时以 SDD 为准）。

**产出（下游 TASK 消费方不得缩略）**

- 评侧两条可判定 blocker 判据（观测面窄 / 形态越界）——`review-dev-plan` 评审执行时的 blocker 判定输入（SDD §7.3：只对评审发生时的 SKILL 版本生效，无追溯效力）。
- 既有维度名集合不变的保持面——TASK-04 收口审计（`cmd-03` review 组 forbid 面）。
