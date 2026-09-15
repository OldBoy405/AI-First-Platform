---
spec-id: ai-first-platform
version: "0.40"
id: CR-2026-067-TASK-03
type: TASK
cr-ref: CR-2026-067
plan-ref: "change-requests/CR-2026-067/plan.md"
sdd-ref: "change-requests/CR-2026-067/sdd.md"
target-version: 0.40
title: "断言同步：pipeline-structure.test.mjs 的 CR-2026-055 目标用例两组 term 原位改写为 dep-N 口径"
slug: sync-dep-n-test-terms
status: pending
estimate: 6h
depends-on: [CR-2026-067-TASK-01, CR-2026-067-TASK-02]
created: 2026-09-15T10:05:00+08:00
---

# CR-2026-067-TASK-03 断言同步（G3，FR-6.1）

## 1. 任务描述

**目标**：把 `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 的用例 **`CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确`**（实测 L616）内的**两组 term 原位改写**为 `dep-N` 口径——写侧 8 项 → **9 项**（追加 `dep-N`），评侧 4 项 → **6 项**（原位改写为覆盖「显式小节 + 有序清单 + `dep-N` 引用规则 + `commit SHA` 必填 + 消费口径 + 正文漏列」）。**用例名保持、结构不变、不新增第二个反向用例、顶层用例数保持 36。**

**背景**：FR-6 要求「断言与其同步的是同一份文本」——两份 SKILL 的合同收紧后，若断言仍只覆盖旧形态，会出现「合同变了、断言没变」的静默缺口（PRD §1.1 第 2 条的同一根因）。本卡是 AC-6 的断言面，`gate-registry.json` 的登记值同步（35 → 36）由 TASK-04 承担。

**输入条件**：**TASK-01 与 TASK-02 已完成**（两组新 term 必须已在两份 SKILL 的终态文本中存在，否则本卡的 `cmd-02` 必红——这是本卡 `depends-on` 的实质原因）；tools worktree HEAD = `7094e492…`。

**范围边界（本卡只改 1 个文件）**：`skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 的**该一条用例**。**逐条不触碰**：该文件其余全部用例（含 L656 的 CR-2026-066 断言 A/B/C/D 与 L636 的 `REVIEW_SKILLS` 常量）、`contract-scan.test.mjs`、`suite-gate.mjs`、`gate-registry.json`（TASK-04）、`lint-prompts.mjs`、两份 SKILL（TASK-01/02）、`crctl.mjs` / `scripts/lib/**` / `rules.json` / `gates.json` / `pipeline-templates/**` / `agents/**`。

## 2. 涉及文件 / 模块

| 文件（相对 `tools` 仓根） | 动作 | 锚点（本节点实测，实施期以实时搜索为准） |
|---|---|---|
| `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | 改 2 处（同一用例内的两组 term 数组），用例名与 `assert.ok` / `.replaceAll('\r\n','\n')` 读取形态**逐字保留** | L616 用例起始（`test('CR-2026-055 blocker 修复: …`）；写侧 term 数组（8 项）；评侧 term 数组（4 项） |

**不变量（实测基线）**：本文件 **711 行**、顶层 `^test(` **36 条**、`CR-2026-055` 相关用例 **5 条**（L568 / L585 / L602 / L616 / L627——本卡只改 L616 一条）；`REVIEW_SKILLS` 起于 L636。**不新增测试文件**（`gate-registry.json#manifest.files` 保持 21）。

## 3. 实现要点

### 3.1 目标形态（SDD §6.5-F 逐字；用例名与结构不变）

```javascript
test('CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确', () => {
  const writer = readFileSync(path.join(TOOLS_ROOT, 'skills/develop/write-tech-design/SKILL.md'), 'utf8').replaceAll('\r\n', '\n');
  for (const term of ['### 既有实现依赖与事实', '正文首次出现顺序', 'dep-N', 'repo:', 'relative path:', 'stable symbol/对象:', 'commit SHA:', '依赖结论:', 'sdd.explicit_existing_dependencies']) {
    assert.ok(writer.includes(term), `write-tech-design 合同含 ${term}`);
  }
  const reviewer = readFileSync(path.join(TOOLS_ROOT, 'skills/develop/review-tech-design/SKILL.md'), 'utf8').replaceAll('\r\n', '\n');
  for (const term of ['名为“既有实现依赖与事实”的显式小节', '有序清单', '`dep-N` 引用规则', '`commit SHA` 为必填的 40 位 SHA', 'sdd.explicit_existing_dependencies', '正文同类事实是否漏列']) {
    assert.ok(reviewer.includes(term), `review-tech-design 规则含 ${term}`);
  }
});
```

### 3.2 term 组的覆盖对照（PRD FR-6.1，逐条）

| 侧 | term | 覆盖的合同面（产生方） |
|---|---|---|
| 写侧（9 项） | `### 既有实现依赖与事实` | 小节名（TASK-01 §3.2） |
| | `正文首次出现顺序` | 排序与编号生命周期（TASK-01 §3.1/§3.2） |
| | `dep-N` | `dep-N` 固定结构（TASK-01 §3.2，**本卡新增项**） |
| | `repo:` / `relative path:` / `stable symbol/对象:` / `commit SHA:` / `依赖结论:` | 五字段名（逐字保留） |
| | `sdd.explicit_existing_dependencies` | 消费口径（逐字保留） |
| 评侧（6 项） | `名为“既有实现依赖与事实”的显式小节` | 显式小节（TASK-02 §3.1） |
| | `有序清单` | 有序清单（TASK-02 §3.1） |
| | `dep-N` 引用规则（反引号包裹） | 关系式（**本卡新增项**） |
| | `commit SHA` 为必填的 40 位 SHA（反引号包裹） | SHA 必填（**本卡新增项**，同时是「旧『并可附』零残留」的正向对偶） |
| | `sdd.explicit_existing_dependencies` | 消费口径（逐字保留） |
| | `正文同类事实是否漏列` | 退化面保留（逐字保留） |

### 3.3 纪律

- **只改这两组 term 数组的字面量**；`test(...)` 名、`readFileSync(...).replaceAll('\r\n','\n')` 读取形态、`assert.ok(...)` 硬失败语义**逐字不动**（NFR-5：不得引入「匹配不到 → 静默通过」的降级）。
- **不新增**第二个反向用例、不改动 L656 的 CR-2026-066 断言块与 `REVIEW_SKILLS` 常量；顶层 `^test(` 计数保持 **36**。
- 行尾纪律：本文件为 LF；落盘后 `git diff --stat` 只显示本文件（且改动行数与两组数组规模一致）。
- 落盘后自查：`node --test --test-reporter=dot skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` exit 0。

## 4. 验收条件（可执行）

1. **`cmd-04` 的 term 组两项清零**（plan §6.2；`repo=tools`，`cwd=.`）：输出中**无** `FAIL term 组1 …` / `FAIL term 组2 …` 行（两组 term 与 §3.1 的集合**相等**——既无缺项也无多项，非「子串包含」式抽样）。整体 `exit 0` 还需 TASK-04 的登记值同步，属 TASK-04 的收口项。
2. **`cmd-02` exit 0**（`pipeline-structure.test.mjs` + `contract-scan.test.mjs`）：目标用例在**新** term 组下执行绿（写侧 9 项与评侧 6 项全部命中两份 SKILL 的终态文本）；同批 CR-2026-066 断言 A/B/C/D 与 `contract-scan` 的 `RETIRED_RECOVERY` 零命中保持绿。
3. **顶层用例数不变**：`cmd-04` 打印 `top-level test( = 36`。
4. **负控自检**（非证据、不进 `test-evidence/`）：临时从写侧数组删掉 `'dep-N'` → `cmd-04` 必须出现 `FAIL term 组1 缺[dep-N]` → 还原；再从评侧数组删掉 `` '`commit SHA` 为必填的 40 位 SHA' `` → 必须出现对应的 `FAIL term 组2 缺[…]` → 还原 → 工作区干净。
5. **边界自查**：`gate-registry.json`、两份 SKILL、`agents/**` 的 `git diff --stat` 为空（登记值与 SKILL 由 TASK-04 / TASK-01/02 负责）。

## 5. 完成标志

- 该用例两组 term 改写就位并随 CR 提交（`[cr]` 前缀消息）；`cmd-04` 的两项 term FAIL 清零、`cmd-02` exit 0、顶层计数 36，输出留档。
- **机械证据留档**：目标用例名逐字、两组数组的**逐项**清单（写侧 9 / 评侧 6）与实测计数，证明「不新增第二个反向用例、用例数不减」。
- 未触碰 L656 断言块与 `REVIEW_SKILLS` 常量（`git diff` 的行级证据）。
- **任务账本登记**：`crctl task done CR-2026-067 --task CR-2026-067-TASK-03`（带 `done-at`，即时登记，工程纪律 #8）。

## 6. 接口契约

**消费（上游 TASK 产物，逐字，不得缩略）**

- TASK-01 产出（写侧 9 项 term 的命中前提）：`### 既有实现依赖与事实`、`正文首次出现顺序`、`dep-N`、`repo:`、`relative path:`、`stable symbol/对象:`、`commit SHA:`、`依赖结论:`、`sdd.explicit_existing_dependencies`。
- TASK-02 产出（评侧 6 项 term 的命中前提）：`名为“既有实现依赖与事实”的显式小节`、`有序清单`、`` `dep-N` 引用规则 ``、`` `commit SHA` 为必填的 40 位 SHA ``、`sdd.explicit_existing_dependencies`、`正文同类事实是否漏列`。
- `change-requests/CR-2026-067/sdd.md#§6.5-F`（逐字目标代码块，实施期唯一来源）。
- 既有文件事实：`TOOLS_ROOT` 常量解析（`path.resolve(import.meta.dirname,'..','..','..','..','..')`）、`readFileSync(...).replaceAll('\r\n','\n')` 读取形态、L656 断言块与 `REVIEW_SKILLS`（只读，零改动）。

**产出（下游 TASK / 门禁消费方不得缩略）**

- 目标用例的两组 term 数组终态：写侧 9 项、评侧 6 项（`cmd-04` 以**集合相等**判定，`cmd-02` 以执行绿判定）。
- 顶层用例计数 **36**（`cmd-04` 与 `suite-gate` 的 `manifest.cases` 一致性的比较基准；TASK-04 用它把登记值 35 同步为 36）。
- 「不新增第二个反向用例」的机械事实（顶层计数恒 36 ⇒ TASK-04/`cmd-01` 的登记值与下界判据同时成立）。
