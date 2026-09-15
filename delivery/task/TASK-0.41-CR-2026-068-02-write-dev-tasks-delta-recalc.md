---
spec-id: ai-first-platform
version: "0.41"
id: CR-2026-068-TASK-02
type: TASK
cr-ref: CR-2026-068
plan-ref: "change-requests/CR-2026-068/plan.md"
sdd-ref: "change-requests/CR-2026-068/sdd.md"
target-version: 0.41
title: "write-dev-tasks Step 2a 第 1 条整体替换：delta 重算 + 下游依赖闭包同步 + 未受影响 TASK 保留 + 索引只刷新"
slug: write-dev-tasks-delta-recalc
status: pending
estimate: 8h
depends-on: []
created: 2026-09-15T23:25:00+08:00
---

# CR-2026-068-TASK-02 write-dev-tasks Step 2a 第 1 条整体替换（G2，FR-2）

## 1. 任务描述

**目标**：在 `skills/develop/write-dev-tasks/SKILL.md` 内**原位整体替换** Step 2a 第 1 条（SDD §6.5-D）——把现行「**重新生成** TASK 卡……不保留已被评审判废/删除的旧 TASK」的整轮重建语义，改为「plan→TASK delta 重算 + 直接受影响 TASK 及其下游依赖闭包同步 + 未受影响 TASK 保留 + `crctl task init` 只刷新索引」。**第 2、3 条逐字保留，条目数仍为 3；文件内不得出现第二套回修规则（I2）。**

**背景**：FR-2 的唯一改写面（SDD §6.1）。现行文字与 delta 语义直接矛盾（`重新生成` + `不保留旧 TASK`）；`dep-17` 的 CR-2026-037 用例 doesNotMatch 断言要求 `重新生成.*TASK 与 \`_index\.yml\`` 组合零命中，删词后天然仍绿。

**输入条件**：同 TASK-01（`sdd.md` 冻结 `d2562c30…`；tools HEAD = `49fa3774…` diff 审计基线）。

**范围边界（本卡只改 1 个文件）**：`skills/develop/write-dev-tasks/SKILL.md`。**逐条不触碰**：其余 4 个交付文件（TASK-01/03/04）、全部 `zero_diff` 面（同 TASK-01 边界清单）。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 锚点 |
|---|---|---|
| `skills/develop/write-dev-tasks/SKILL.md` | 改 1 处：`### Step 2a — 回修模式（CR-2026-026 FR-8/FR-9）` 第 1 条整体替换 | 实测：`### Step 2a` L46；第 1 条现行文（「逐条消费 blockers……**重新生成** TASK 卡并调用 `crctl task init` 刷新 `_index.yml`；不保留已被评审判废/删除的旧 TASK。」）；第 2 条（「禁止只刷新评审证据而不修改被指出的产物。」）、第 3 条（「回修期间允许 status=`tech-design-reviewed`（普通轨重放态）。」）逐字保留；`### Step 3 — 生成 TASK 文件` 不动 |

**段级零 diff（本卡逐字保留）**：Step 1 / Step 2 / Step 2a 第 2、3 条 / Step 3（TASK frontmatter 与正文 6 节结构）/ `### Step 4 — TASK 数量三步断言与索引初始化`（三步断言 + `crctl task init --count-hint` + `TASK_COUNT_MISMATCH` + 「`tasks/_index.yml` 是受控账本，禁止 Agent/Skill 手写」句，`dep-6` 面逐字保留）/ Step 5 / Step 6 / 注意事项。

## 3. 实现要点

### 3.1 修订（SDD §6.5-D）：Step 2a 第 1 条整体替换为以下**逐字**文本

```text
1. 逐条消费 blockers（每条内含可执行修复说明），并执行 plan→TASK delta 重算：`write-dev-plan` 完成 SDD→plan delta 后继续同步 plan→TASK；重算**直接受影响 TASK**（普通轨 blockers 指向的 TASK 与 SDD→plan delta 波及的 TASK 都是「直接受影响」的来源）及其**下游依赖闭包**（`depends-on` 可达的传递闭包），同步更新受影响 TASK 的输入、输出、接口（接口契约节的消费/产出签名）、命令、`depends-on`、完成标志与回滚；未受影响 TASK 保留；`crctl task init` 只用于刷新 `_index.yml` 索引，不承担重算语义（被评审判废/删除的 TASK 从文件集移除后由索引刷新反映）。
```

### 3.2 保持项（逐字）

- 第 2 条：`2. 禁止只刷新评审证据而不修改被指出的产物。`
- 第 3 条：`3. 回修期间允许 status=`tech-design-reviewed`（普通轨重放态）。`
- `dep-6` 面：`禁止 Agent/Skill 手写` 句与 `crctl task init` 调用形态（`cmd-03` need / `dep-17` 两条 match 断言载体）。
- `purpose: regenerate-tasks` 标签文本与 `replayNodes` 条目在 pipeline JSON 内**零改动**（不在本卡文件）。

### 3.3 通用纪律

- `重新生成` 措辞在本文件内**零残留**（同文件全文检索；`cmd-03` forbid 兜底）。
- 文件内**不得出现第二套回修规则**（I2）：delta 语义只写在第 1 条内部，不新增第 4 条、不在别处另写一段。
- 其余纪律同 TASK-01 §3.4（行尾 / lint 避让 / 退役字段名 / follow_up 不顺带实现 / 单文件自查）。

## 4. 验收条件（可执行）

1. **`cmd-03` 的 tasks 判据清零**：输出中**无** `FAIL tasks …` 行（6 项正向 token 全命中：`执行 plan→TASK delta 重算` / `直接受影响 TASK` / `下游依赖闭包` / 同步更新六面句 / `未受影响 TASK 保留` / `只用于刷新`；`重新生成` 零残留）。
2. **`cmd-02` exit 0**：`dep-17` CR-2026-037 用例真实执行——两条 match（`crctl task init` / `禁止 Agent/Skill 手写`）仍命中、doesNotMatch（`重新生成.*TASK 与 \`_index\.yml\``）仍零命中。
3. **`cmd-06` exit 0**（同 TASK-01）。
4. **负控自检**（非证据）：临时把第 1 条改回含 `重新生成` 的原文 → `cmd-03` 必须出现 `FAIL tasks residual 重新生成` → 还原 → 工作区干净。
5. **边界自查**：其余 4 个交付文件与全部 `zero_diff` 面的 `git diff --stat` 为空。

## 5. 完成标志

- `skills/develop/write-dev-tasks/SKILL.md` 第 1 条替换就位并随 CR 提交；`cmd-03` tasks 行清零、`cmd-02` / `cmd-06` exit 0，输出留档。
- 可机械核对事实写入任务完成记录：① `grep -c '重新生成'` = **0**；② 第 2、3 条逐字在位；③ `crctl task init` 与受控账本句在位（`dep-6` 面）。
- **任务账本登记**：`crctl task done CR-2026-068 --task CR-2026-068-TASK-02`（即时标 `done`，工程纪律 #8）。

## 6. 接口契约

**消费（上游/既有，逐字）**

- `skills/develop/write-dev-tasks/SKILL.md` 既有文本：Step 2a 第 1 条现行文（整轮重建语义）、第 2/3 条、Step 4 三步断言与受控账本句、Step 3 TASK 卡六节结构。
- `change-requests/CR-2026-068/sdd.md#§6.5-D` 与 §1.4.2（逐字目标文本与 delta 算法；冲突时以 SDD 为准）。
- TASK-01 产出的 plan→plan delta 语义（`dep-3` 新 upstream 轨）——本卡第 1 条的「`write-dev-plan` 完成 SDD→plan delta 后继续同步 plan→TASK」承接句。

**产出（下游 TASK 消费方不得缩略）**

- TASK delta 重算合同（直接受影响判定 + 传递闭包 + 六面同步 + 未受影响保留 + 索引只刷新）——TASK-04 收口审计（`cmd-03` tasks 组）与 `review-dev-plan` 依赖拓扑维度的消费面。
- 文件内单一回修规则的不变量（I2）——`cmd-03` forbid `重新生成` 的机械载体。
