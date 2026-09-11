---
id: CR-2026-063-TASK-01
type: TASK
cr-ref: CR-2026-063
plan-ref: "change-requests/CR-2026-063/plan.md"
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
title: "gate --mode pre-review 错配可操作化（contractDrift + recoverCommand + crIdForRecover）与 R7 配对 lint"
slug: gate-pre-review-drift-and-r7-pairing
status: pending
estimate: 12h
depends-on: []
created: 2026-09-11T22:49:24+08:00
---

# CR-2026-063-TASK-01 —— `gate --mode pre-review` 错配可操作化与 R7 配对 lint

覆盖 FR：**FR-7、FR-8**（SDD §6 FR-7 / FR-6 FR-8）；变更组 G2；主责仓：`tools`。

## 1. 任务描述

**目标**：让 `crctl gate <CR-ID> --mode pre-review` 与非 `requirement-reviewing` 的 `--for` 组合时，除既有的 `BAD_ARGS` + 零写入之外，额外给出 ① `contractDrift: true` 固定提示与 ② 固定形态恢复方向 `recoverCommand`；并让版本化 Prompt 侧出现「`gate` + `--mode pre-review` 却未声明 `--for requirement-reviewing`」时被既有 R7 规则判为 `CONTRADICTS`。

**背景**：现状 `cmdGate` 的错配分支只 `fail('BAD_ARGS', ...)`（SDD dep-1），调用方拿不到「该调用与版本化 Skill/Pipeline 声明不一致」的信号，也拿不到可复制的恢复方向；`lint-prompts.mjs` 的 R7 只有 `advance` / `backlog-set` / `commit --template` 三类行级子判据（SDD dep-15）。

**输入条件**：tools CR worktree（`resources[].worktreePath`，分支 `requirement/CR-2026-063`）；`crctl workspace freshness CR-2026-063`（gate=implement-start）通过；SDD 修订 0.1.4 `e1d44437…`（审批绑定 `c05a6c02…`）与 PRD `9247c107…` 只读。

## 2. 涉及文件 / 模块

| 文件（相对 tools CR worktree） | 改动性质 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | `cmdGate()` 的 `--mode pre-review` 分支补 extra 字段；新增文件内 helper `crIdForRecover`（一处定义，FR-7/FR-9 共用） |
| `skills/shared/crctl/scripts/lint-prompts.mjs` | R7 既有逐行循环内新增一个子判据；不新增规则编号、不改既有三类子判据、不改退出语义与豁免机制 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 新增 AC-7 两向量用例（规范 / 非规范 CR-ID）+ 零写入断言 |
| `skills/shared/crctl/scripts/test/lint-prompts.test.mjs` | 新增 R7 配对正/负向量；既有三类 R7 向量保持不变 |

**不得触碰**（SDD §9 `zero_diff`）：`skills/shared/controlled-shell/rules.json`、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`、`skills/shared/crctl/scripts/test/` 以外的任何非白名单文件；`crctl.mjs` 中 `cmdGate` 与 `crIdForRecover` 之外的段落。

## 3. 实现要点

1. **`crIdForRecover` helper（SDD §4.1.1，逐字）**：模块作用域，输入 `cr`（`cmdGate`/`cmdReviewLoopReset` 的位置参数）：
   ```text
   crIdForRecover(cr) = /^CR-\d{4}-\d{3,}$/.test(String(cr)) ? String(cr) : '<CR-ID>'
   ```
   只允许一份定义、两处调用；不得在 `cmdReviewLoopReset` 里复制第二份正则。占位符形态与既有 `crctl test` 的 `recoverCommand`（`<plan>`/`<worktree>`，SDD dep-11）同族；CR-ID 语法校验形态与既有 `archive`（SDD dep-27）一致。
2. **`cmdGate` 错配分支（SDD §4.1.2 判定树）**：`flags.mode === 'pre-review'` 且 `flags.for !== 'requirement-reviewing'` 时，`fail('BAD_ARGS', <SDD §3.1 的 message 原文>, { contractDrift: true, recoverCommand: 'crctl workspace inspect ' + crIdForRecover(cr) })`。分支仍在任何写路径之前（`cmdGate` 全程无写路径，零写入由结构保证）。`--for requirement-reviewing` 的正常检查序列与输出**完全不变**。
3. **`contractDrift` 语义（SDD §3.1.1）**：恒为 `true` 的固定常量，只表示「该调用与版本化 Skill/Pipeline 声明不一致，须复核权威 Skill/Pipeline」；**不是**漂移类型分类器，调用方不得据此反推漂移侧。
4. **R7 子判据（SDD §4.3，位置：既有 `advance` / `backlog-set` / `commit --template` 三个子判据之后，仍在 `for (let li = 0; li < lines.length; li++)` 内）**：
   ```text
   hasGate    = /\bgate\b/.test(l)
   hasMode    = l.includes('--mode pre-review')
   hasForPair = l.includes('--for requirement-reviewing')
   if (hasGate && hasMode && !hasForPair):
       findings.push({ rule:'R7', level:'CONTRADICTS', file: ctx.file, line: para.startLine + li,
                       why: 'gate --mode pre-review 必须同时声明 --for requirement-reviewing' })
   ```
   用 `\bgate\b` 而非字面 `gate --mode pre-review`（真实形态是 `crctl gate <CR-ID> --for <stage> --mode pre-review`，`gate` 与 `--mode` 不相邻）；豁免沿用既有 `<!-- lint-prompts:ignore -->` ±1 行；不新增规则编号（不得出现 `R14`）。

## 4. 验收条件

1. **AC-7 向量①（规范 CR-ID 内插）**：`crctl.test.mjs` 中断言以真实 CR-ID（如 `CR-2026-063`）调用 `crctl gate CR-2026-063 --for tech-design-review-pending --mode pre-review` 时，stderr JSON 满足 `error.code === 'BAD_ARGS'`、`error.contractDrift === true`、`error.recoverCommand === 'crctl workspace inspect CR-2026-063'`，进程退出码非 0。
2. **AC-7 向量②（非规范位置参数回退）**：同一断言面，把位置参数换成非规范形态（如 `CR-X`），断言 `error.recoverCommand === 'crctl workspace inspect <CR-ID>'`（**不内插**），其余字段同上。
3. **AC-7 零写入**：执行前后对该 tools worktree 的文件哈希集合（或等价的可观测集合）无变化；`failure` 后无任何账本/工作区写入痕迹。
4. **AC-7 既有路径不变**：`crctl gate --for requirement-reviewing --mode pre-review` 的既有检查序列与输出不变（既有用例保持通过）。
5. **AC-8 正/负向量**：`lint-prompts.test.mjs` 中，向量 A（某行含 `gate` 与 `--mode pre-review` 且**不含** `--for requirement-reviewing`）产生 `rule === 'R7'` 且 `level === 'CONTRADICTS'` 的 finding；向量 B（两者同现）不产生 finding；既有三类 R7 向量结果不变；`findings` 中不出现 `R14`。
6. **真实仓库零误报**：`plan.md §6.2 cmd-02`（`lint-prompts.mjs --mode enforce`）在实施后仍为 `0 findings`。
7. **全量回归**：`plan.md §6.2 cmd-01`（21 个 `*.test.mjs` + 锚定例外模式）exit 0、`skipped=false`（本 TASK 的两个测试文件在该命令内被真实执行）。

## 5. 完成标志

- 上述 §4 的 7 条全部实测通过，并留下可复核的命令与输出摘要（命令、cwd、exit、关键断言行）。
- 改动文件集合恰为 §2 的 4 个文件（`crctl git diff --name-only` 相对基线 `ebdd6290f1523ffb682609b7ad6ab83e7d30245e` 逐条在白名单内）。
- 本 TASK 产生的文件（含新增用例）由本 TASK 自行提交：`[cr] CR-2026-063 TASK-01 gate pre-review drift + R7 pairing`（受控 `crctl git` 形态，`[cr] ` 前缀）。
- `crctl task done CR-2026-063-TASK-01 --workspace <KB worktree>` 登记完成（纪律 #8：做完一个标一个，不积压到回写期）。
- **不**在本 TASK 内改写 `sdd.md` / `prd.md`；**不**修改 TASK-02/03/04 的文件。

## 6. 接口契约

**产出（供下游 TASK 消费，逐字对齐 SDD）**

| 符号 | 精确形态（SDD 落点） |
|---|---|
| `crIdForRecover(cr)` | 模块作用域函数，`(cr) => /^CR-\d{4}-\d{3,}$/.test(String(cr)) ? String(cr) : '<CR-ID>'`；返回值为恢复串中的 CR-ID 片段（SDD §4.1.1）。**消费方：CR-2026-063-TASK-02 的 `cmdReviewLoopReset` 失败分支** |
| gate 错配错误体 | stderr JSON `{ error: { code: 'BAD_ARGS', message: <SDD §3.1 message 原文>, contractDrift: true, recoverCommand: 'crctl workspace inspect ' + crIdForRecover(cr) } }`，进程退出码 1，零写入（SDD §3.1 / §4.1.2） |
| R7 finding | `{ rule: 'R7', level: 'CONTRADICTS', file, line, why: 'gate --mode pre-review 必须同时声明 --for requirement-reviewing' }`（SDD §3.4-A / §4.3） |

**消费（上游既有实现，只读复用，SDD dep-1 / dep-6 / dep-15 / dep-27）**

- `fail(code, message, extra)`（`crctl.mjs` L43–47）：只写 stderr 后 `process.exit(1)`——零写入的结构性来源。
- `cmdGate(ws, cr, gates, flags)`（同文件，`--mode pre-review` 分支 L957–960）。
- `lint-prompts.mjs` 的 R7 段落（L249–284：`l.includes(...)` 四类行级子判据）、`splitMarkdown`（L185–200）、`isIgnored`（±1 行）、report/enforce 退出语义（L340–360）。
- `/^CR-\d{4}-\d{3,}$/` 的既有校验形态（`archive` L3513、`version-set` L2741；`workspace-transactions.mjs` L36 `CR_DIR_RE`）。
