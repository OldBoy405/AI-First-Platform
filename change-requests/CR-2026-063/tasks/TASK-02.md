---
id: CR-2026-063-TASK-02
type: TASK
cr-ref: CR-2026-063
plan-ref: "change-requests/CR-2026-063/plan.md"
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
title: "review-loop reset 原子提交（单文件 ledger 事务 + 提交隔离 + 失败回滚）与 durable-tx write-set 前置条件放宽"
slug: review-loop-reset-atomic-commit
status: pending
estimate: 16h
depends-on: [CR-2026-063-TASK-01]
created: 2026-09-11T22:49:24+08:00
---

# CR-2026-063-TASK-02 —— `review-loop reset` 原子提交与 write-set 前置条件放宽

覆盖 FR：**FR-9**（SDD §6 FR-9）；变更组 G3；主责仓：`tools`。

## 1. 任务描述

**目标**：把 `crctl review-loop reset` 的写入路径从「`fs.writeFileSync` 直写、无 CAS、无提交」改为「复用既有 ledger 事务助手做一次单文件 write-set 的原子提交」，并让两条失败路径（提交失败 / 恢复未完成）各有唯一产生点、各自落审计、对外只暴露 op-scoped 错误码。

**背景**：改造前 `cmdReviewLoopReset` 同步直写 `review-loop.yml`（SDD dep-2），失败后可能留下 dirty 中间态且无审计——这是本 CR（流程正确性止血）的核心目标之一。既有 4 个 ledger 事务调用点全部 ≥2 文件，`beginLedgerTransaction` 的前置条件 `writes.length < 2`（SDD dep-8）会拒绝单文件 write-set，故须原位放宽为 `< 1`（SDD §3.3 / D-1）。

**输入条件**：`CR-2026-063-TASK-01` 已完成（`crIdForRecover` 可用）；`crctl workspace freshness CR-2026-063`（gate=implement-start）通过；SDD 修订 0.1.4 `e1d44437…` 只读。

## 2. 涉及文件 / 模块

| 文件（相对 tools CR worktree） | 改动性质 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs` | `cmdReviewLoopReset` 改 `async` 并按 SDD §4.2.1 步骤 1–14 重写写入与返回段；dispatcher（`case 'review-loop'`）**不改** |
| `skills/shared/crctl/scripts/lib/durable-tx.mjs` | **仅**把 ledger write-set 前置条件的比较数值 `writes.length < 2` 原位放宽为 `< 1`；导出面、journal/manifest 结构、`recover`/`abort`/`finish` 语义、`FAULT_POINTS` 表零改动 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 新增成功路径/W1/W2/W2b/W2c 用例；既有成功路径用例夹具迁移（见 §3.7） |
| `skills/shared/crctl/scripts/test/durable-tx.test.mjs` | 新增单文件 write-set 被接受、空 write-set 仍 `TX_WRITESET_INVALID` 的用例 |

**不得触碰**（SDD §9 `zero_diff`）：`lib/workspace-transactions.mjs`、`lint-prompts.mjs`、`rules.json`、`crctl.mjs` 中 `cmdReviewLoopReset` 之外的段落（含 `cmdGate` / `review-record` / `approve` / `owner-set` / `version-set` 调用点）。本 TASK 消费 TASK-01 的 `crIdForRecover`，**不得**复制第二份正则。

## 3. 实现要点

1. **成功路径（SDD §4.2.1 步骤 1–14，逐条）**：TTY 硬检查 → `--loop`/`--reason` 校验 → `recoverLedgerCommand(ws, ledgerTxKey('reset', cr, loopRef))` 残留恢复 → `readAttempts` 耗尽判定 → 取 `expectedHash`（`readFileChecked` 原文 + `sha256`；文件不存在传 `null`）→ 组装 `current-cycle = fromCycle + 1`、`current-attempt = 0`、保留 `attempts[]` → `renderLoopText`（LF-only）→ `beginLedgerCommand(ws, key, [{ path, expectedHash, newText }], true)`（单文件 write-set，CAS 由事务按 `expectedHash` 自校验）→ `controlledGit(ws, 'add', ['-A', '--', rel], …)`。
2. **步骤 12 提交隔离前置（FR-9 第 4 条的唯一保证手段）**：`iso = queryTrackedChanges(ws, { audit:false })`；`isolated = addR.ok && iso.ok && iso.unstaged.length === 0 && JSON.stringify(iso.staged) === JSON.stringify([rel])`。`isolated=false` ⇒ **不执行 commit**，直接进入步骤 13（外来 staged 变更永不被夹带、也不被本命令改写）。
3. **步骤 13 恢复链（本地 try/catch，**禁止**经 `runTxAsync` 包装）**：`rolled = await abortLedgerTransaction(ledgerTx)` → `if (rolled.paths.length) syncLedgerIndex(ws, rolled.paths, 'crctl-review-loop-reset')` → `clean = queryTrackedChanges(ws, { audit:true })` 并复核 `staged`/`unstaged` 均为空；任一步失败由本地 `catch` 收敛为 `fail('REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED', …, { affected: [rel] })`，**审计先于 fail**（`kind='review-loop-reset'`、`result='commit-failed'`）。**不得**让 `TX_JOURNAL_INVALID` / `TX_RECOVERY_CONFLICT` / `TX_GIT_FAILED` 作为对外退出码出现。
4. **提交失败路径**：`isolated === false` 或 `git commit` 命令失败 ⇒ 回滚后可恢复到干净基线时 `fail('REVIEW_LOOP_RESET_COMMIT_FAILED', …, { changed:false, rolled_back:true, recoverCommand: 'crctl review-loop reset ' + crIdForRecover(cr) + ' --loop ' + loopRef + ' --reason <reason>' })`；提交消息 `[cr] review-loop reset <CR-ID> <loopRef> cycle <from> -> <to>` + 空行 + `AI-First-Tx: <txId>` trailer。
5. **成功收尾**：`await injectLedgerFault('ledger-after-commit')` → `await runTxAsync(finishLedgerTransaction(ledgerTx))` → `auditLog(…无 result 字段…)` → `ok({ op:'review-loop-reset', cr, loop:loopRef, 'current-cycle':nextCycle, 'current-attempt':0, file:p, reason })`（字段集与改造前一致，**不含** `recoverCommand`）。
6. **`durable-tx.mjs` 一处放宽**：只改 `writes.length < 2` → `writes.length < 1`；空 write-set 仍被该前置条件与 `applyWriteSet` 的 `entries.length === 0` 双重拒绝。
7. **既有成功路径用例夹具迁移（SDD dep-14，本 TASK 必须做）**：`crctl.test.mjs` 中 `CR-2026-049：review-loop reset 耗尽态开启下一 cycle，保留 attempts 历史` 当前使用非 git 夹具 `makeWorkspace()`（无 `git init`），改造后步骤 11–12 的 `git add`/`git commit` 必然失败 ⇒ 改用 `makeGitWorkspace()`（必要时补一次基线 commit 以建立 HEAD），**断言与断言语义逐字不变**（仍断言 `status==0`、`current-cycle==2`、`current-attempt==0`、`attempts` 历史 3 条）。属 PRD §1.3.1 第 14 行「既有测试修订」面，不是对 `reset` 契约的放宽。
8. **同型既有用例**：`CR-2026-049：review-loop reset 非交互式调用拒绝（人类在环，无旁路）` 的三条既有拒绝（`NOT_TTY` / 缺 `--loop`/`--reason` 的 `BAD_ARGS` / `LOOP_NOT_EXHAUSTED`）行为与输出**不变**。

## 4. 验收条件

1. **成功路径（AC-9①/⑤）**：reset 成功后 `review-loop.yml` 变更**已被提交**且提交只含该文件（消息含 `[cr] ` 前缀与 `AI-First-Tx: <txId>` trailer）；`git status --porcelain` 为空；`current-cycle` 递增 1、`current-attempt=0`、`attempts[]` 历史条目保留；成功输出字段集与改造前一致且**不含** `recoverCommand`。
2. **W1 窗口（AC-9②）**：`CRCTL_FAULT_POINT=tx-apply-before-complete` 中断后，同命令下次执行按 journal 还原到执行前，再干净执行一次（cycle 只递增一次）。
3. **W2 窗口（AC-9②）**：`.githooks/pre-commit` `exit 1` + `core.hooksPath`（既有先例）使 commit 失败 ⇒ 返回 `REVIEW_LOOP_RESET_COMMIT_FAILED`（`changed:false`、`rolled_back:true`、`recoverCommand` 存在）、文件与 index 回到执行前、tracked clean、HEAD 不变、审计已写（`result='commit-failed'`）。
4. **W2b 窗口（AC-9②，本轮新增）**：同一 git 夹具在 reset 前 `git add` 一个无关文件 ⇒ 步骤 12 判 `isolated=false`、**不 commit**、无夹带；回滚后 clean 复核因无关 staged 仍在而失败 ⇒ `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`（`affected:[<relpath>]`）+ 审计；无关 staged 变更保持原样。
5. **W2c 窗口（AC-9②，本轮新增）**：`.githooks/pre-commit` 先把 `review-loop.yml` 写成第三值再 `exit 1` ⇒ `abortLedgerTransaction` 抛 `TX_RECOVERY_CONFLICT` ⇒ 本地 `catch` 映射为 `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`（`affected:[<relpath>]`）+ 审计 + exit 1；**断言 stderr 不作为对外错误码出现 `TX_RECOVERY_CONFLICT`**（恢复链不经 `runTxAsync` 的可验向量）。
6. **恢复串断言面（AC-9③）**：只对**失败结果**断言；两个向量分开——规范 CR-ID（`CR-2026-063`）内插、非规范输入回退 `<CR-ID>`；`--reason` 位置恒为占位符 `<reason>`，任何用户文本都不进恢复串。
7. **既有行为不变（AC-9④）**：三条既有拒绝（`NOT_TTY` / 缺参 `BAD_ARGS` / `LOOP_NOT_EXHAUSTED`）行为与输出不变。
8. **单文件 write-set（AC-9⑥）**：`durable-tx.test.mjs` 断言 `writes.length === 1` 被接受、空 write-set 仍 `TX_WRITESET_INVALID`；既有 4 个 ledger 调用点（`approve`/`owner-set`/`version-set`/`review-record`）的事务测试全绿。
9. **全量回归**：`plan.md §6.2 cmd-01`（21 个 `*.test.mjs` + 锚定例外模式）exit 0、`skipped=false`；`plan.md §6.2 cmd-05` 的 diff 清单只含本 TASK 的 4 个文件与 TASK-01 的 4 个文件（实施顺序完成后）。

## 5. 完成标志

- 上述 §4 的 9 条全部实测通过，并留下可复核的命令与输出摘要（命令、cwd、exit、关键断言行；W1/W2/W2b/W2c 各自注明注入方式与断言结果）。
- `crctl git diff --name-only` 相对基线 `ebdd6290f1523ffb682609b7ad6ab83e7d30245e` 中，本 TASK 触及的文件恰为 §2 的 4 个；`lib/durable-tx.mjs` 的 diff 除那一处比较数值外为空。
- 本 TASK 自行提交：`[cr] CR-2026-063 TASK-02 review-loop reset atomic commit`（受控 `crctl git` 形态）。
- `crctl task done CR-2026-063-TASK-02 --workspace <KB worktree>` 登记完成。
- **不**改写 `sdd.md` / `prd.md`；**不**修改 TASK-01/03/04 的文件。

## 6. 接口契约

**消费（CR-2026-063-TASK-01 产出 + 既有实现）**

| 符号 | 精确形态与来源 |
|---|---|
| `crIdForRecover(cr)` | CR-2026-063-TASK-01 产出：`(cr) => /^CR-\d{4}-\d{3,}$/.test(String(cr)) ? String(cr) : '<CR-ID>'`（SDD §4.1.1）。本 TASK 的两条失败 `recoverCommand` 均以它内插，**不得**自带第二份正则 |
| `beginLedgerCommand(ws, key, writes, commitRequired)` | 既有（SDD dep-3）：`writes = [{ path, expectedHash, newText }]`；本 TASK 传**单元素**数组 + `commitRequired = true` |
| `abortLedgerTransaction(tx)` / `finishLedgerTransaction(tx)` | 既有（SDD dep-8）：前者按 journal 的 `beforeText` 还原并返回 `{ paths }`，可抛 `TX_JOURNAL_INVALID` / `TX_RECOVERY_CONFLICT` |
| `syncLedgerIndex(ws, paths, tag)` | 既有（SDD dep-3/dep-26）：`git add -A -- <relpath>` 使 index 与还原后内容一致；失败抛 `TX_GIT_FAILED` |
| `queryTrackedChanges(ws, { audit })` | 既有（SDD dep-7）：返回 `{ ok, staged, unstaged }`；`staged = git diff --name-only --cached`、`unstaged = git diff --name-only -- .` |
| `readAttempts(ws, cr, loopRef, gates)` / `attemptsFilePath` / `readFileChecked` / `sha256` / `renderLoopText` / `auditLog` / `identity` / `injectLedgerFault` | 既有（SDD dep-3/dep-7/dep-9/dep-11）：状态读取、原文读取与哈希、LF-only 渲染、审计与身份、崩溃窗口注入 |
| `ledgerTxKey('reset', cr, loopRef)` | 既有（SDD dep-3）：本 CR 首次使用该 ledger 事务键 |

**产出（对外契约，逐字对齐 SDD §3.2 / §4.2）**

| 维度 | 精确形态 |
|---|---|
| 函数 | `async function cmdReviewLoopReset(ws, cr, gates, flags): Promise<void>`；dispatcher `case 'review-loop'` 仍为 `return cmdReviewLoopReset(...)`（调用形态不变） |
| 成功输出 | `{ op: 'review-loop-reset', cr, loop: loopRef, 'current-cycle': nextCycle, 'current-attempt': 0, file: p, reason }`（不含 `recoverCommand`） |
| 失败输出①（提交失败） | exit 1，`error.code = 'REVIEW_LOOP_RESET_COMMIT_FAILED'`，extra `{ changed:false, rolled_back:true, recoverCommand }`；两个产生点：步骤 12 隔离断言不成立 / `git commit` 命令失败 |
| 失败输出②（回滚未完成） | exit 1，`error.code = 'REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED'`，extra `{ affected: [rel] }`（不带 `recoverCommand`）；唯一产生点 = 步骤 13 的 `catch` |
| 对外错误闭包 | `NOT_TTY` / `BAD_ARGS` / `UNKNOWN_LOOP` / `LOOP_NOT_EXHAUSTED` / `CAS_CONFLICT`（事务内抖动）/ 上述两个 `REVIEW_LOOP_RESET_*`；恢复链内部 `TX_*` **不得**外泄 |
| 审计 | 成功与失败两条路径都 `auditLog(ws, { kind:'review-loop-reset', cr, loop: loopRef, fromCycle, toCycle, reason, by: identity(ws), … })`；失败路径额外 `result:'commit-failed'` |
| `lib/durable-tx.mjs` | ledger write-set 前置条件 `writes.length < 1`（原 `< 2`）；其余零改动 |
