---
id: CR-2026-063-TASK-01
type: TASK
cr-ref: CR-2026-063
plan-ref: "change-requests/CR-2026-063/plan.md"
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
title: gate --mode pre-review 错配可操作化（contractDrift + recoverCommand + crIdForRecover）与 R7 配对 lint
slug: gate-pre-review-contract-drift-and-r7-pairing-lint
status: pending
estimate: 12h
depends-on: []
created: 2026-09-11T19:30:00+08:00
---

## 1. 任务描述

在 tools CR worktree（`resources[].worktreePath`，HEAD = 基线 `ebdd6290f1523ffb682609b7ad6ab83e7d30245e` + 本 CR 既有提交）实现两条**原位修订**：

1. **FR-7**：`crctl gate <CR-ID> --mode pre-review` 与 `--for` 不匹配时，保留 `BAD_ARGS` 与零写入，错误体 extra 补入 `contractDrift: true` 与固定形态 `recoverCommand`；`--for requirement-reviewing` 的正常检查序列与输出**完全不变**。
2. **FR-8**：`lint-prompts.mjs` 既有 R7 内新增一个区配子判据（同行 `\bgate\b` + `--mode pre-review` ⇒ 必须同行 `--for requirement-reviewing`），**不新增规则编号**，不改 lint 退出语义与豁免机制。

输入：已审批 SDD §3.1 / §3.1.1 / §3.4-A / §4.1 / §4.3 / §6 FR-7 / FR-8 / §6.1 AC-7 / AC-8 / §9（`scope_in`/`zero_diff`）+ dep-1 / dep-6 / dep-15 / dep-16 / dep-21；已审批 PRD 修订 0.1.1 FR-7 / FR-8 与 AC-7 / AC-8；plan.md §6.2（cmd-01 / cmd-02 / cmd-04）与 §7。

本 TASK **不**改 `sdd.md`、**不**改 `prd.md`、**不**改 `pipeline-templates/**` / `rules.json` / `gates.json` / `dir-graph.yaml`（SDD §9 `zero_diff`）。

## 2. 涉及文件 / 模块

修改（PRD §1.3.1 第 8、9 行）：

- `tools` `skills/shared/crctl/scripts/crctl.mjs`：`cmdGate()` 的 `--mode pre-review` 错配分支（基线 L957–960）+ **文件内新增 helper `crIdForRecover`**（SDD §4.1.1；`zero_diff` 已显式豁免该 helper）。
- `tools` `skills/shared/crctl/scripts/lint-prompts.mjs`：R7 段落内的逐行循环（基线 L249–284）新增子判据。
- `tools` `skills/shared/crctl/scripts/test/crctl.test.mjs`：新增 FR-7 向量（错配错误体 + 零写入 + 既有路径不变）。
- `tools` `skills/shared/crctl/scripts/test/lint-prompts.test.mjs`：新增 R7 配对向量（正/负）与既有 R7 向量不回归。

不得改动：`crctl.mjs` 中 `cmdReviewLoopReset` 与 `cmdGate` + `crIdForRecover` 之外的段落（尤其 `approve` / `owner-set` / `version-set` / `review-record` 调用点）；`lint-prompts.mjs` 的其它规则与规则清单注释（仍 R1~R13，**无 R14**）。

## 3. 实现要点（逐字对齐 SDD）

### 3.1 FR-7：`recoverCommand` 取值算法（SDD §4.1.1，确定性、无自由输入）

```text
输入：cr（cmdGate 的位置参数）
1. crId = /^CR-\d{4}-\d{3,}$/.test(String(cr)) ? String(cr) : '<CR-ID>'
2. recoverCommand = `crctl workspace inspect ${crId}`
```

- helper 形态：`crIdForRecover(cr) -> string`，返回第 1 步结果；**一处定义、两处调用**（FR-7 与 FR-9 共用，见 TASK-02 的消费声明），不得在本 TASK 之外再复制该正则。
- 占位符 `'<CR-ID>'` 为字面量；`requireCr()`（dep-6）只判非空、不判语法，语法判定由本 helper 承担。

### 3.2 FR-7：`cmdGate` 判定树（SDD §4.1.2）

```text
if (!flags.for) → fail(BAD_ARGS, 'gate 需要 --for <target-status>')            [不变]
if (flags.mode === 'pre-review'):
    if (flags.for !== 'requirement-reviewing'):
        fail('BAD_ARGS',
             '--mode pre-review 仅支持 --for requirement-reviewing；该调用与版本化 Skill/Pipeline 的声明不一致
              （contractDrift=true），请复核权威 Skill/Pipeline 中该 stage 的门禁入口，勿继续按当前参数重试',
             { contractDrift: true,
               recoverCommand: 'crctl workspace inspect ' + crIdForRecover(cr) })
    else:
        runPreReviewGateChecks(...)   [既有序列，行为与输出不变]
else:
    runGateChecks(...)                [不变]
```

- 错误体落在 `error` 内（`fail()` 的 extra 展开，dep-1）：`{error:{code:'BAD_ARGS',message:…,contractDrift:true,recoverCommand:'…'}}`，stderr JSON、退出码 1、**零写入**（两条 fail 分支均在任何写路径之前）。
- `contractDrift` **恒为 `true` 的固定常量**：不携带区分信息、不是漂移类型分类器，调用方不得据此反推（SDD §3.1.1 / SDD-CLOSE-01）。

### 3.3 FR-8：R7 配对子判据（SDD §4.3）

在既有 R7 段落的逐行循环（`for (let li = 0; li < lines.length; li++)`）**内**、既有 `advance` / `backlog-set` / `commit --template` 三个子判据**之后**新增：

```text
hasGate    = /\bgate\b/.test(l)
hasMode    = l.includes('--mode pre-review')
hasForPair = l.includes('--for requirement-reviewing')
if (hasGate && hasMode && !hasForPair):
    findings.push({ rule:'R7', level:'CONTRADICTS', file: ctx.file, line: para.startLine + li,
                    why: 'gate --mode pre-review 必须同时声明 --for requirement-reviewing' })
```

- 行级判定（与既有 R7 四类子判据同族）；`\b` 视 `-` 为非词字符，不命中 `gateway`/`delegate`。
- 不改既有四类子判据的判据与命中文本；不新增规则编号；沿用既有 `isIgnored` ±1 行豁免与 `--mode report`（exit 0）/ `--mode enforce`（`LINT_DRIFT` exit 1）退出语义。
- 文本纪律：本 TASK 改动的 SKILL/文档文本不得出现 ≥3 具名状态、不得把 `_backlog.yml` 与状态判断写进同一段（dep-15 R12/R13）。

### 3.4 测试

- `crctl.test.mjs`：新增用例（≥2 条）——① `crctl gate CR-X --for tech-design-review-pending --mode pre-review` → exit 1、`error.code==='BAD_ARGS'`、`error.contractDrift===true`、`error.recoverCommand==='crctl workspace inspect CR-X'`（用非规范 CR 位置参数时回退 `'<CR-ID>'`）、执行前后 workspace 文件哈希集合零变化；② `--for requirement-reviewing --mode pre-review` 既有路径的返回与已审批前一致。
- `lint-prompts.test.mjs`：新增向量 A（缺 `--for requirement-reviewing` → R7 finding）与向量 B（两者同现 → 无 finding）；既有 R7 向量（advance 形态、`backlog-set` 白名单、`--template` subject）结果不变；无新增规则编号。
- 行尾纪律（AGENTS.md #1）：测试内对该文件文本做逐行判定前统一 `\r\n → \n`；解析/读取失败硬失败。

## 4. 验收条件

1. **cmd-01**（`node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt|TASK-06 ⑤|已知 Skill 越界文本零命中" skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/durable-tx.test.mjs`，cwd = tools worktree）：全绿，含本 TASK 新增的 FR-7 向量；其 3 条 skip 为 plan §5.3 登记的基线红（BR-1/BR-3/BR-4）。
2. **cmd-02**（`node --test --test-reporter=dot skills/shared/crctl/scripts/test/lint-prompts.test.mjs`）：全绿，含 R7 配对向量与既有 R7 向量。
3. **cmd-04**（`node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce`，cwd = tools worktree）：exit 0，零 finding（真实仓库零误报 —— 扫描面内 `--mode pre-review` 仅 `skills/requirement/review-requirement/SKILL.md:42` 一行且已同含 `--for requirement-reviewing`，dep-21）。
4. 人工/评审可核对：`crctl git diff --unified=3 ebdd6290f1523ffb682609b7ad6ab83e7d30245e -- skills/shared/crctl/scripts/crctl.mjs`（白名单形态 `^--unified=\d+ .+$`）的全部 hunk 仅落在 `cmdGate` + `crIdForRecover`（不涉 `cmdReviewLoopReset` 与四个 tx 调用点）。

## 5. 完成标志

- 上述 4 条验收全部通过；本 TASK 的提交落盘 tools CR 分支（独立 commit，`[cr] ` 前缀消息），文件面仅 §2 列出的 4 个文件。
- 任务账本：本 TASK 在 `tasks/_index.yml` 标 `done`（`crctl task done CR-2026-063 --task CR-2026-063-TASK-01`，仅 `developing` 下可登记）。
- 本 TASK 完成边界为 `developing` 内可被 `crctl task done` 登记的事件（实现落盘 + cmd-01/cmd-02/cmd-04 全绿 + 账本登记），**不含** merge / writeback / archive / code-reviewing / code-approved（流程控制 TASK 禁止）。
- 不登记 multica 侧台账（本 TASK 不碰 multica 仓）；`zero_diff` 文件零改动。

## 6. 接口契约

**消费**（既有实现，签名与 SDD dep-1/dep-6/dep-15 一致，逐字对齐目标仓实际形态）：

- `fail(code, message, extra)`（`crctl.mjs:43–47`）：写 stderr `{error:{code,message,...extra}}` 后 `process.exit(1)`；**extra 展开落在 `error` 内**（FR-7 两个新字段因此落在 `error.contractDrift` / `error.recoverCommand`）。
- `cmdGate(ws, cr, gates, flags)`（`crctl.mjs:957–960` 为 `--mode pre-review` 分支）：`flags.for`（string）、`flags.mode`（`'pre-review'`），其余分支 `runGateChecks(ws, cr, status, gates, opts)` 形态不变。
- `requireCr(cr)`（`crctl.mjs:3531`）：只判非空、不判 CR-ID 语法。
- `lint-prompts.mjs` 的段落切分 `splitMarkdown` / 文件遍历 `walkFiles` / 豁免 `isIgnored` / 退出语义（`L14` 规则清单 R1~R13 无 R14）：本 TASK 不改其形态，只在 R7 的逐行循环内新增子判据。
- 测试夹具：`crctl.test.mjs` 的 `runCrctl` / `makeWorkspace` / `writeCrEntry`（既有），`lint-prompts.test.mjs` 的 `makeFixture` / `runLint` / `MINI_DIR_GRAPH`（dep-16）。

**产出**（本 TASK 暴露给下游/消费方的精确签名）：

- `crIdForRecover(cr) -> string`：`crctl.mjs` 文件作用域函数；对 `String(cr)` 匹配 `^CR-\d{4}-\d{3,}$` 时返回 `String(cr)`，否则返回字面量 `'<CR-ID>'`。**TASK-02 消费**（在其 `recoverCommand` 拼装处调用，不再复制正则）。
- `cmdGate` 错配分支的错误体契约（可观测）：`{error:{code:'BAD_ARGS', message:<固定文案>, contractDrift:true, recoverCommand:'crctl workspace inspect ' + crIdForRecover(cr)}}`，stderr、exit 1、零写入、可任意重放。
- R7 finding 形状：`{rule:'R7', level:'CONTRADICTS', file, line, why}`（`why` 文案见 §3.3），触发条件 = 同行 `\bgate\b` 且 `--mode pre-review` 且缺 `--for requirement-reviewing`。
