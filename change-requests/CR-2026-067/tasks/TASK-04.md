---
id: CR-2026-067-TASK-04
type: TASK
cr-ref: CR-2026-067
plan-ref: "change-requests/CR-2026-067/plan.md"
sdd-ref: "change-requests/CR-2026-067/sdd.md"
target-version: 0.40
title: "登记值同步与交付面收口：gate-registry 的 manifest.cases 35→36 + diff/zero_diff/全量套件三面收口"
slug: registry-sync-and-delivery-close
status: pending
estimate: 6h
depends-on: [CR-2026-067-TASK-01, CR-2026-067-TASK-02, CR-2026-067-TASK-03]
created: 2026-09-15T10:05:00+08:00
---

# CR-2026-067-TASK-04 登记值同步与交付面收口（G4，FR-6.2 / FR-7）

## 1. 任务描述

**目标**：① 把 `skills/shared/crctl/scripts/test/gate-registry.json` 的 `manifest.cases["pipeline-structure.test.mjs"]` 由 **35 同步为 36**（与实测顶层用例数一致，SDD D-5 / §6.5-G）；② 在**全部改动终态**上完成本 CR 的交付面收口——diff 面恰 4 文件、`zero_diff` 面零命中、全量套件与 CI 静态面全绿、`exceptions` 保持空。**不签任何新例外、不改 `suite-gate.mjs` 的判据语义。**

**背景**：`suite-gate` 的用例数判据是**下限**（`f.cases < base` 才红），因此登记值落后 1 不触发红灯——但登记值与实际不一致本身就是事实缺口（PRD §1.5 第 2 条裁定为「同步口径」）。本卡同时承担 FR-7（边界与零新增）与 AC-7/AC-8/AC-9 的收口责任：**只有全部终态齐备后**，diff 审计与零 diff 审计才有意义（`depends-on` 的实质原因）。

**输入条件**：TASK-01 / TASK-02 / TASK-03 全部完成并提交；tools worktree HEAD 的 diff 基线 = `7094e492822594b971699924478ba27ccf612c42`；`sdd.md` / `prd.md` 零触碰。

**范围边界（本卡只改 1 个文件 + 只读收口）**：`skills/shared/crctl/scripts/test/gate-registry.json` 的一个数值。收口动作全部**只读**（执行既有命令、读 diff、留档计数）。**逐条不触碰**：`crctl.mjs` / `scripts/lib/**` / `rules.json` / `gates.json` / `suite-gate.mjs` / `contract-scan.test.mjs` / `lint-prompts.mjs` / `check-*.mjs` / `pipeline-templates/**` / `agent-skill-matrix.yml` / `AGENT-SKILL-MATRIX.md` / `agents/**` / `dir-graph.yaml` / `ARCHITECTURE.md` / 三个 `write-dev-*` SKILL / `review-requirement` / `review-code` / `../multica/**`。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 锚点（本节点实测） |
|---|---|---|
| `skills/shared/crctl/scripts/test/gate-registry.json` | 改 1 个数值 | L38 `"pipeline-structure.test.mjs": 35` → `36`；`exceptions: []`（L243）**不动**；`schema` / `manifest.files`（21）/ 其余 20 个 `manifest.cases` 键**不动** |
| （只读收口对象）4 个交付文件 + 全仓 diff | 审计 | `cmd-03` / `cmd-04` / `cmd-05` / `cmd-06` / `cmd-01`（plan §6.2） |

## 3. 实现要点

### 3.1 登记值同步（SDD §6.5-G）

1. 先取实测顶层用例数：`node -e` 或 `grep -c "^test(" skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` → 必须为 **36**（TASK-03 的完成标志已保证）；登记值 = 该实测值（**不猜测、不手抄计划里的数字**）。
2. 只改 `manifest.cases` 中该文件对应的**一个**数值；不改键名、不改其他文件的登记值、不改 `manifest.files`、不动 `exceptions`。
3. 保持 JSON 既有格式（缩进 / 行尾 / 尾随换行）；落盘后 `node -e "JSON.parse(require('fs').readFileSync(...))"` 可解析。

### 3.2 交付面收口（在**全部终态**上执行，全部只读）

| 面 | 判据 | 命令 |
|---|---|---|
| diff 面 | tools diff（相对 `7094e492…`）**恰为 4 个文件**：`skills/develop/write-tech-design/SKILL.md`、`skills/develop/review-tech-design/SKILL.md`、`skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`、`skills/shared/crctl/scripts/test/gate-registry.json` | `cmd-05` |
| `zero_diff` 面 | `crctl.mjs` / `rules.json` / `gates.json` / `suite-gate.mjs` / `contract-scan.test.mjs` / `lint-prompts.mjs` / `pipeline-templates/` / `agent-skill-matrix.yml` / `AGENT-SKILL-MATRIX.md` / `agents/` / `dir-graph.yaml` / `ARCHITECTURE.md` / `write-dev-*` 三个 SKILL / `review-requirement` / `review-code` 均**零命中** | `cmd-05` |
| 保持性面 | 写侧 `crctl checkpoint` 计数 = **1**（不删该句）；四个 review SKILL 的 `crctl checkpoint` 与三个旧前提句 token = **0** | `cmd-05` |
| 合同面 | `cmd-03` 整命令 exit 0（写侧 + 评侧 + 两侧①~④逐字节相同 + Step 编号集 + `quality-reviewer-agent` 7 小节） | `cmd-03` |
| 断言面 | `cmd-04` 整命令 exit 0（term 集合相等 + 顶层 36 + 登记值一致 + `exceptions` 空 + 退役字段名零命中） | `cmd-04` |
| 门禁面 | `cmd-01` 全量套件 `verdict=pass` / `failures=0` / `files_executed=21` / `skipped_file_level=0` / `cases_executed=597` / `exceptions_count=0` | `cmd-01` |
| CI 静态面 | `cmd-06` exit 0 | `cmd-06` |

### 3.3 纪律

- **不签例外**：`exceptions` 必须为显式空数组；任何红色必须就地修复（回 TASK-01/02/03），**不得**改断言、降级为下界、或改 `suite-gate.mjs`。
- 收口结论必须**逐条留档**（命令 → 退出码/计数 → 结论），不得写「已全部通过」而不带原始输出。
- 发现 diff 面多出文件或 `zero_diff` 面被改动 → **停止**，回到对应 TASK 修复后重跑本卡收口（不得就地放宽）。
- 实施期若发现 SDD 不可实施 → 出口 = 状态机既有边 `review-dev-plan:upstream-design-blocker`，**不得**自行扩大或缩小批准范围。

## 4. 验收条件（可执行）

1. **`cmd-04` exit 0**：`audit-test failures = 0`；输出含 `top-level test( = 36` 与 `manifest.cases = 36`（两者一致）。
2. **`cmd-05` exit 0**：`tools diff paths = 4`（恰 4 文件，无越界与缺失）、`audit-diff failures = 0`。
3. **`cmd-03` exit 0**：`audit-skill failures = 0`（含两侧①~④逐字节相同与 Step 编号集）。
4. **`cmd-01`**：`verdict=pass` / `exit_code=0` / `failures=0` / `exceptions_count=0` / `files_executed=21`（全量套件在本 CR 的终态下保持全绿、零例外）。
5. **`cmd-06` exit 0**（CI 静态面本机等价）。
6. **负控自检**（非证据、不进 `test-evidence/`）：临时把登记值改回 `35` → `cmd-04` 必须出现 `manifest.cases=35 与顶层用例数 36 不一致` → 还原 → 工作区干净；再临时改动一个 `zero_diff` 文件（如 `skills/shared/crctl/gates.json` 加一个空行）→ `cmd-05` 必须出现 `zero_diff 面被改动` → 还原（**必须还原干净**）。
7. **`exceptions` 零例外**：`gate-registry.json#exceptions` = `[]`（`cmd-04` 与 `cmd-01` 双向保证）。

## 5. 完成标志

- `gate-registry.json` 的登记值 = 实测顶层用例数（36）并随 CR 提交（`[cr]` 前缀消息）。
- 六条命令的**原始输出留档**（`cmd-01`~`cmd-06` 的退出码与关键计数），并逐条给出结论；`cmd-01…06` 的 `cmd-NN` 与 `test-evidence/cmd-NN.log` 的对应关系与 plan §6.2 全等（由 `write-test-report` 发布，本卡只留档）。
- **交付面三方一致**：diff 面恰 4 文件 ∧ `zero_diff` 面 0 命中 ∧ 全量套件 0 failures / 0 exceptions。
- 负控自检两项（登记值回退 / zero_diff 面篡改）均按预期判红并已还原（工作区干净）。
- **任务账本登记**：`crctl task done CR-2026-067 --task CR-2026-067-TASK-04`（带 `done-at`，即时登记，工程纪律 #8）；四张卡全部 `done` 后方可进入 `write-test-report` 节点。

## 6. 接口契约

**消费（上游 TASK 产物，逐字，不得缩略）**

- TASK-03 产出：`pipeline-structure.test.mjs` 顶层用例计数 **36**（登记值的比较基准）与两组 term 数组终态。
- TASK-01 / TASK-02 产出：两份 SKILL 的终态文本（`cmd-03` 的判据面与 `cmd-05` 的 `zero_diff` / 反向 token 面的比较基准）。
- `change-requests/CR-2026-067/sdd.md#§6.5-G`、`#§9 scope_in/zero_diff`（逐字目标与边界，实施期唯一来源）。
- `gate-registry.json` 既有结构：`schema`（`crctl-suite-gate/v1`）、`manifest.files`（21 条）、`manifest.cases`（21 键）、`exceptions`（`[]`）、`stateMachine`。

**产出（下游节点 / 门禁消费方不得缩略）**

- `manifest.cases["pipeline-structure.test.mjs"] = 36`（`suite-gate --run` 的下界基线与 `cmd-04` 的一致性判据同时消费）。
- 收口证据集（`cmd-01` / `cmd-03` / `cmd-04` / `cmd-05` / `cmd-06` 的退出码与计数）——供 `write-test-report`（`repo=tools` 的 6 条命令）与 `review-code` 消费；**本卡不发布 `test-report.md`**（该文件由 `crctl test` 独占写）。
- `exceptions = []` 的零例外事实（AC-6④）。
- 「diff 面恰 4 文件」的机械事实（AC-7①，`cmd-05` 的 `tools diff paths = 4`）。
