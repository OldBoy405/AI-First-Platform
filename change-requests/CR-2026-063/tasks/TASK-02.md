---
id: CR-2026-063-TASK-02
type: TASK
cr-ref: CR-2026-063
plan-ref: "change-requests/CR-2026-063/plan.md"
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
title: review-loop reset 原子提交（单文件 ledger 事务 + add/commit + 失败回滚）与 durable-tx write-set 前置条件放宽
slug: review-loop-reset-atomic-commit
status: pending
estimate: 16h
depends-on: [CR-2026-063-TASK-01]
created: 2026-09-11T19:30:00+08:00
---

## 1. 任务描述

在 tools CR worktree 把 `crctl review-loop reset` 从「`fs.writeFileSync` 直写、不提交、不 CAS、不回滚」改造为**一次可恢复的 ledger 事务提交**（FR-9），并因此放宽 `lib/durable-tx.mjs` 的 ledger write-set 前置条件（`writes.length < 2` → `< 1`，FR-9 第 3 条），同时新增/迁移测试用例覆盖成功路径、崩溃窗口与单文件 write-set。

输入：已审批 SDD §3.2（命令契约）、§3.3（前置条件）、§4.2.1（时序）、§4.2.2（崩溃/失败窗口真值表）、§5.1 D-1 / §5.2 D-2、§6 FR-9、§6.1 AC-9、§7.1（安全控制点）、§9（`scope_in`/`zero_diff`）+ dep-2 / dep-3 / dep-4 / dep-5 / dep-7 / dep-8 / dep-9 / dep-11 / dep-13 / dep-14；已审批 PRD 修订 0.1.1 FR-9（含第 3 条的择一结论与两条否决替代）与 AC-9①–⑥；plan.md §4.1 R-03、§5.3、§6.2（cmd-01 / cmd-05）、§7、§8（U-1/U-2/U-3）。

本 TASK **不**改 `sdd.md`、**不**改 `prd.md`、**不**新写事务框架（FR-9 第 7 条）、**不**把 reset 并入 checkpoint、**不**放宽 controlled-shell 全局规则、**不**改 `rules.json` / `gates.json` / `dir-graph.yaml`。

> **上游设计修订项（不属本 TASK 的自由度，plan §8.2）**：
>
> - **U-1（S-1）**：SDD §3.2 / §3.5 / §5.2 D-2 声明了 `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`，但 §4.2.1 步骤 13 未给其产生路径（`abort`/`syncLedgerIndex` 经 `runTxAsync` 抛出会转成 `TX_*` 码）。契约/算法择一属 `write-tech-design` 职责。**本 TASK 不自行择一、不实现任一变体**；若上游轨未先行闭环（SDD 未修订 + 未重新评审/审批），本 TASK 在该分支上**不可执行**（停在 `task-breakdown`，由 `review-dev-plan` 判定 `repair-target=write-tech-design`）。
> - **U-2（S-2）**：SDD §4.2.1 步骤 12 未写明「commit 前断言 staged 恰等于 write-set」。本 TASK 按 **FR-9 第 4 条**（commit 只包含 `review-loop.yml`）实现该前置断言（镜像 `owner-set` L2541–2543 / `version-set` L2832–2833），SDD 侧明文落点归 U-2。
> - **U-3（S-3）**：SDD dep-14 现写「既有断言基线必须继续通过」，与「该用例用非 git 夹具 `makeWorkspace()`、改造后必走 commit 失败分支」冲突。本 TASK **迁移夹具**（`makeGitWorkspace()`，断言不变）是 in-scope 测试文件内的必要实现；SDD dep-14/AC-9⑤ 口径改写归 U-3。

## 2. 涉及文件 / 模块

修改（PRD §1.3.1 第 10、11 行）：

- `tools` `skills/shared/crctl/scripts/crctl.mjs`：`cmdReviewLoopReset`（基线 L1821–1848）→ 改 `async`，替换写入与返回段（读参、TTY 检查、耗尽检查、审计字段、输出字段集**不变**）。
- `tools` `skills/shared/crctl/scripts/lib/durable-tx.mjs`：`beginLedgerTransaction` 的 ledger write-set 前置条件一处数值（基线 L487，`writes.length < 2` → `< 1`）。**仅此一处**：不改导出面、journal/manifest 结构、`recover`/`abort`/`finish` 语义、`FAULT_POINTS` 表（SDD §9 `zero_diff`）。
- `tools` `skills/shared/crctl/scripts/test/crctl.test.mjs`：新增成功路径/W1/W2/W3/三条既有拒绝/恢复串断言；**迁移**既有成功路径用例（`L3430–3452`，耗尽态 `cycle+1`）到 `makeGitWorkspace()`，断言不变；`runCrctlWrapped`（L43–56）增加可选 env 形参（向后兼容的测试侧改动，dep-14）。
- `tools` `skills/shared/crctl/scripts/test/durable-tx.test.mjs`：新增 write-set 规模向量（`writes.length === 1` 接受并完成 prepare/apply/finish；空 write-set 仍 `TX_WRITESET_INVALID`）。

不得改动：`crctl.mjs` 中 `cmdReviewLoopReset` 之外的段落（尤其 `cmdGate` + `crIdForRecover` 属 TASK-01）；`review-record` / `approve` / `owner-set` / `version-set` 调用点；dispatcher 的 `case 'review-loop'`（保持 `return cmdReviewLoopReset(...)`，`async main()` 与 `main().catch` 已能接管 Promise，dep-6）。

## 3. 实现要点（逐字对齐 SDD）

### 3.1 `cmdReviewLoopReset` 时序（SDD §4.2.1）

```text
async function cmdReviewLoopReset(ws, cr, gates, flags):
  1  非 TTY → fail('NOT_TTY')                                        [不变，在一切写入之前]
  2  --loop 缺失 → fail('BAD_ARGS')                                   [不变]
  3  --reason 缺失/空白 → fail('BAD_ARGS')                            [不变]
  4  await recoverLedgerCommand(ws, ledgerTxKey('reset', cr, loopRef))
        # 本事务键下的残留幂等回滚/确认；必须先于任何状态判断
  5  state = readAttempts(ws, cr, loopRef, gates)                     [既有]
  6  !state.exhausted → fail('LOOP_NOT_EXHAUSTED', …, {current, max})  [不变]
  7  p = attemptsFilePath(ws, cr); raw = readFileChecked(p)
     expectedHash = raw == null ? null : sha256(raw)
        # 与事务内部 readHash 同源（未归一原文 utf8 sha256）；文件不存在传 null（新建文件），不前造错误分支
  8  由 state.data 组装 all.loops[loopRef] = { current-cycle: fromCycle+1, current-attempt: 0,
                                              attempts: [...(prev.attempts||[])] }
     newText = renderLoopText(all.loops)                              # LF-only（dep-11）
  9  rel = path.relative(ws, p).split(path.sep).join('/')
  10 ledgerTx = await beginLedgerCommand(ws, key, [{ path: p, expectedHash, newText }], true /* commitRequired */)
  11 addR = controlledGit(ws, 'add', ['-A', '--', rel], ws, 'crctl-review-loop-reset')
  12 commitMsg = `[cr] review-loop reset ${cr} ${loopRef} cycle ${fromCycle} -> ${nextCycle}\n\nAI-First-Tx: ${ledgerTx.txId}`
     commitR = addR.ok ? controlledGit(ws, 'commit', ['-m', commitMsg], ws, 'crctl-review-loop-reset') : addR
  13 if (!commitR.ok):
         rolled = await runTxAsync(abortLedgerTransaction(ledgerTx))
         if (rolled.paths.length) await runTxAsync(syncLedgerIndex(ws, rolled.paths, 'crctl-review-loop-reset'))
         auditLog(ws, { kind:'review-loop-reset', cr, loop:loopRef, fromCycle, toCycle:nextCycle,
                        reason, by: identity(ws), result:'commit-failed' })
         fail('REVIEW_LOOP_RESET_COMMIT_FAILED', '…已按 journal 还原并撤销暂存', {
              changed:false, rolled_back:true,
              recoverCommand: `crctl review-loop reset ${crIdForRecover(cr)} --loop ${loopRef} --reason <reason>` })
  14 else:
         await injectLedgerFault('ledger-after-commit')
         await runTxAsync(finishLedgerTransaction(ledgerTx))
         auditLog(ws, { kind:'review-loop-reset', cr, loop:loopRef, fromCycle, toCycle:nextCycle,
                        reason, by: identity(ws) })
         ok({ op:'review-loop-reset', cr, loop:loopRef, 'current-cycle':nextCycle,
              'current-attempt':0, file:p, reason })          # 字段集与改造前一致
```

- **步骤 12 的前置断言（U-2 / FR-9 第 4 条）**：commit 前断言（a）无其它 unstaged 变更、（b）staged 恰等于 write-set（本 TASK 即 `review-loop.yml` 一条）。镜像 `owner-set`（L2541–2543）/`version-set`（L2832–2833）的既有形态；命中不满足时走步骤 13 的失败分支（`REVIEW_LOOP_RESET_COMMIT_FAILED`，`changed:false`、`rolled_back:true`），不留 dirty 中间态。
- `recoverCommand` 的 `--reason` 位置一律占位符 `<reason>`，用户文本永不拼接（NFR-3）；`<CR-ID>` 回退由 TASK-01 的 helper 承担。
- 受控 git 形态：`add -A -- <rel>`、`commit -m "[cr] …"`（多行 trailer 依赖既有 `flags=s` 白名单）；不新增 git 形态、不改 `rules.json`。

### 3.2 崩溃/失败窗口真值表（SDD §4.2.2，AC-9① ②）

| 窗口 | 注入方式（既有机制） | 中断时盘上状态 | 同命令下次行为 |
|---|---|---|---|
| W1 apply 完成、complete 前 | `CRCTL_FAULT_POINT=tx-apply-before-complete`（dep-9） | 文件=新内容；journal=`prepared/written`；HEAD 未变 | 步骤 4 判定未提交 → 按 journal 还原 → 干净执行一次（只递增一次 cycle） |
| W2 add/commit 失败（进程内） | `.githooks/pre-commit` `exit 1` + `core.hooksPath`（dep-13 先例） | 文件=新内容且已暂存；HEAD 未变 | 步骤 13 立即还原文件 + 恢复 index；exit 1 并写审计（`result: commit-failed`） |
| W3 commit 成功、complete 前 | `CRCTL_FAULT_POINT=ledger-after-commit`（dep-9） | 文件=新内容且已提交（HEAD 含 `AI-First-Tx: <txId>`）；journal 未清理 | 步骤 4 用 trailer 判定「已提交」→ 只清 journal，**不重复递增**；随后按当前状态返回 `LOOP_NOT_EXHAUSTED` |

### 3.3 `lib/durable-tx.mjs` 前置条件（SDD §3.3，D-1）

- `beginLedgerTransaction` 的 `writes.length < 2` → `writes.length < 1`（仍以 `TX_WRITESET_INVALID` 拒绝空 write-set）。
- 空 write-set 另有 `applyWriteSet` 的 `entries.length === 0` 独立拒绝（dep-8，L311）——**不变**。
- 单条目与多条目的 prepare/apply/rollback 路径同构（逐条 CAS、逐条 before 快照），4 个既有调用点全部 ≥2 文件 → 零行为差异（AC-9⑥ 的可验断言覆盖）。

### 3.4 测试（AC-9①–⑥ 的载体）

- 成功路径：committed（提交只含该文件、消息含 `[cr] ` 与 tx trailer）、`git status --porcelain` 为空、`current-cycle` +1、`current-attempt=0`、`attempts[]` 历史条目保留。
- W1/W2/W3：按 §3.2 真值表；W2 断言「失败返回 + 文件/index 回到执行前 + tracked clean + HEAD 不变 + 审计已写」；W1 断言「下次同命令按 journal 还原后干净执行一次」；W3 断言「已提交事实保留、不重复递增」。
- 恢复串：失败与成功结果中的 `recoverCommand` 均不含 `--reason` 的用户文本（含含空格/引号的 reason）。
- 三条既有拒绝不变：非 TTY → `NOT_TTY`；缺 `--loop`/`--reason` → `BAD_ARGS`；未耗尽 → `LOOP_NOT_EXHAUSTED`。
- `durable-tx.test.mjs`：`writes.length === 1` 被接受并完成 prepare/apply/finish；空 write-set 仍 `TX_WRITESET_INVALID`；既有 9 个用例不回归。
- 夹具迁移：`crctl.test.mjs:3430–3452` 改用 `makeGitWorkspace()`（L3688），**断言不变**；`runCrctlWrapped` 增加可选 env 形参以注入 W1/W3 fault point。
- 行尾纪律（AGENTS.md #1）：测试内对文件读取/哈希前统一 `\r\n → \n`；解析失败硬失败，禁止静默降级。

## 4. 验收条件

1. **cmd-01**（`node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt|TASK-06 ⑤|已知 Skill 越界文本零命中" skills/shared/crctl/scripts/test/crctl.test.mjs skills/shared/crctl/scripts/test/durable-tx.test.mjs`，cwd = tools worktree）：全绿，含本 TASK 的成功路径/W1/W2/W3/单文件 write-set 向量与迁移后的既有用例。
2. **cmd-05**（`node --test --test-reporter=dot --test-skip-pattern "checkpoint T05 contract|TASK-01 RED-7" skills/shared/crctl/scripts/test/{version-set,writeback-tx,register-tx,checkpoint-tx,merge-tx,archive-tx}.test.mjs`）：全绿 —— 既有 4 个 ledger 调用点（`approve`/`owner-set`/`version-set`/`review-record`）事务测试与事务消费者族零行为差异；其 2 条 skip 为 plan §5.3 登记的基线红（BR-2/BR-5）。
3. **implement 期目录级全量回归**（不纳入 `crctl test` 计划，见 plan §5.4）：`node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt|TASK-06 ⑤|已知 Skill 越界文本零命中|checkpoint T05 contract|TASK-01 RED-7" skills/shared/crctl/scripts/test/`（cwd = tools worktree）→ 失败集 ⊆ plan §5.3 登记的 5 条基线红、**无新增红**（基线实测 858 s，exit 1，含且仅含该 5 条）。
4. 人工/评审可核对：`crctl git diff --unified=3 ebdd6290f1523ffb682609b7ad6ab83e7d30245e -- skills/shared/crctl/scripts/lib/durable-tx.mjs` 的全部 hunk 仅落在 `writes.length` 比较数值一处；`crctl.mjs` 的 hunk 仅落在 `cmdReviewLoopReset`。

## 5. 完成标志

- 上述 4 条验收全部通过；本 TASK 的提交落盘 tools CR 分支（独立 commit，`[cr] ` 前缀消息），文件面仅 §2 列出的 4 个文件。
- **U-1 前置**：若 SDD 未按 U-1 修订并重新评审/审批，步骤 13 的回滚失败分支不可实现 → 本 TASK 不标 done，停在 `task-breakdown` 报 `review-dev-plan`（`repair-target=write-tech-design`）。
- 任务账本：`crctl task done CR-2026-063 --task CR-2026-063-TASK-02`（仅 `developing` 下可登记）。
- 本 TASK 完成边界为 `developing` 内可被 `crctl task done` 登记的事件（实现落盘 + cmd-01/cmd-05 + 目录级回归无新增红 + 账本登记），**不含** merge / writeback / archive / code-reviewing / code-approved。
- 不登记 multica 侧台账（本 TASK 不碰 multica 仓）；`zero_diff` 文件零改动（`rules.json`、`gates.json`、`dir-graph.yaml`、`FAULT_POINTS` 表、`durable-tx.mjs` 其它内容）。

## 6. 接口契约

**消费**：

- `crIdForRecover(cr) -> string`（**CR-2026-063-TASK-01 产出**，`crctl.mjs` 文件作用域）：匹配 `^CR-\d{4}-\d{3,}$` 时返回 `String(cr)`，否则返回字面量 `'<CR-ID>'`。本 TASK 在步骤 13 的 `recoverCommand` 中调用，**不得复制该正则**。
- `readAttempts(ws, cr, loopRef, gates) -> {current, max, attempts, cycle, cycleAttempts, exhausted, data}`（dep-7）：只回流状态投影，**不返回原文或哈希**（PRD FR-9 第 2 条 / SDD-CLOSE-03）。
- `attemptsFilePath(ws, cr) -> string`、`readFileChecked(p) -> string|null`、`sha256(text) -> string`（dep-7 / dep-3）：`expectedHash` 由 `readFileChecked` 原文 + `sha256` 取得（先例 dep-4，`crctl.mjs` L2183/L2193）；文件不存在时 `expectedHash = null`。
- `renderLoopText(loops) -> string`（dep-11，L3791–3804，LF-only + 尾换行）。
- `ledgerTxKey('reset', cr, loopRef) -> string`、`recoverLedgerCommand(ws, key) -> Promise`、`beginLedgerCommand(ws, key, writes, commitRequired) -> Promise<ledgerTx>`、`abortLedgerTransaction(tx) -> Promise<{paths:[…]}>`、`syncLedgerIndex(ws, paths, caller) -> Promise`、`finishLedgerTransaction(tx) -> Promise`（dep-3 / dep-8，L672–705、`durable-tx.mjs` L514/L519）：写入 `writes = [{ path, expectedHash, newText }]`，CAS 由事务按 `expectedHash` 自行校验（不经过 `casWrite`）。
- `controlledGit(ws, sub, args, cwd, caller) -> {ok, exit, stdout, stderr, code?}`（dep-3，L412）：`add -A -- <rel>`（白名单 `^-A -- .+$`）与 `commit -m "[cr] …"`（`flags=s`）均在既有白名单内（dep-17）。
- `injectLedgerFault('ledger-after-commit')`（dep-9；W1 用 `CRCTL_FAULT_POINT=tx-apply-before-complete`）、`auditLog(ws, entry)`、`identity(ws)`（dep-7）。
- 测试夹具：`makeGitWorkspace()`（`crctl.test.mjs:3688`）、`.githooks/pre-commit exit 1` + `core.hooksPath` 先例（dep-13，L3958 起 / L4224 起）、`runCrctlInTty` / `runCrctlWrapped`（dep-14，L43–56）、`durable-tx.test.mjs` 既有 9 用例（dep-8）。

**产出**：

- `async function cmdReviewLoopReset(ws, cr, gates, flags)`：dispatcher 形态不变（`return cmdReviewLoopReset(...)`），Promise 由既有 `async main()` / `main().catch(...)` 接管。
- 成功返回（字段集与改造前**完全一致**）：`{op:'review-loop-reset', cr, loop, 'current-cycle':nextCycle, 'current-attempt':0, file, reason}`，exit 0；副作用 = `review-loop.yml` 已提交（提交只含该文件、消息含 `[cr] ` 与 `AI-First-Tx: <txId>`）+ 审计一条。
- 失败返回（commit 失败）：exit 1，`error.code = 'REVIEW_LOOP_RESET_COMMIT_FAILED'`，extra `{changed:false, rolled_back:true, recoverCommand:'crctl review-loop reset <CR-ID> --loop <loopRef> --reason <reason>'}`；文件与 index 回到执行前；审计 `result:'commit-failed'`。
- `lib/durable-tx.mjs` 的行为面变更（唯一）：`beginLedgerTransaction` 接受 `writes.length === 1`，仍以 `TX_WRITESET_INVALID` 拒绝 `writes.length === 0`；导出面与 journal/manifest 结构不变。
