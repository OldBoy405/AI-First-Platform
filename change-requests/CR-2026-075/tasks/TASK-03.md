---
id: CR-2026-075-TASK-03
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: 共享恢复原语锁内比对与取样
slug: durable-tx-locked-expect-and-sample
status: pending
estimate: 8h
depends-on: []
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

扩展共享恢复原语 `lib/durable-tx.mjs#recoverLedgerTransaction`：新增可选 `expect`（锁内期望比对）与可选 `sampleCommitState`（锁内 Git 完成事实取样），并把既有唯一调用点 `recoverLedgerCommand` 接线到新语义（FR-12；SDD §4.5.4 第 2 步、SDD-CLOSE-04、§5.3）。**既有 helper 保持 `recoverLedgerCommand(ws, key)` 两参与无 `expect` 的兼容语义**：本 TASK 只把它的锁外预读（`currentHead`/`headMessage`）换成锁内取样（SDD §9 `zero_diff` 第④类唯一批准的既有 helper 改动），五个既有调用者（`crctl.mjs:1201/1871/2093/2594/2852`）保持两参、零改动；业务摘要/txId 比对（`expect`）只由新增 `recoverBusinessLedgerCommand`（TASK-04 落地、TASK-05 复用）消费。两个新入参缺省时行为与现状逐字一致；取样失败固定为保守失败。本 TASK 是 TASK-04/05 的上游生产者（`expect` 与 `sampleCommitState` 的消费者）：按本 TASK 自身验收（原语 + 缺省兼容）完成后即由 `crctl task done --task CR-2026-075-TASK-03` 即时登记，**不把 TASK-04/05 或任何下游的完成状态作为本 TASK done 的前置**（`guardDependsOn` 只要求直接前置 done，禁止隐性完成门循环）；跨消费者联合向量由 TASK-04/05 在真实业务入口用例内验证、TASK-10 复跑核对。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/durable-tx.mjs` — `recoverLedgerTransaction` 签名与锁内判定顺序；模块头不变量（不理解业务 phase/Git/状态机、零标准库以外依赖）保持。
- `skills/shared/crctl/scripts/crctl.mjs` — 仅 `recoverLedgerCommand(ws, key)`（`crctl.mjs:707`）接线。
- `skills/shared/crctl/scripts/test/durable-tx.test.mjs` — 原语侧向量（B17-a/B17-b、B18-b/B18-c/B18-d）与缺省兼容回归。

## 实现要点

- 签名扩为 `recoverLedgerTransaction({ root, key, currentHead, headMessage, expect, sampleCommitState })`；`expect`、`sampleCommitState` 均可选。缺省（均不传）时保持既有判据路径（`currentHead`/`headMessage`），`phase=complete`、第三值、CAS 与锁语义分支、错误码集合零新增、零改动。
- 判定全部在取得 `ledger-<key>` 锁之后、同一 `latestLedger` 现场对象上完成（`dep-35`），顺序不得调换（SDD §4.5.4 第 2.b 步）：
  1. `expect.inputDigest` 与现场 journal 的 `inputDigest` 不一致（含 journal 缺该字段）→ `TX_INPUT_CONFLICT`（零写入、旧 journal 与已写文件原样保留）。
  2. `expect.txId` 与现场 journal `txId` 不一致 → `TX_LEDGER_RECOVERY_REQUIRED`（零写入、保守失败、不改旧现场）。
  3. 无 journal → `{recovered:false, paths:[]}`（他人已收敛或从未存在，视为无在途）。
  4. `payload.phase === 'complete'` → committed（删该 tx 目录、零文件改动）。
  5. `payload.commitRequired` 为真 → 先做第 2.c 步锁内取样，再判 committed；取样失败即保守失败，不进入回滚。
  6. 其余 → rolledBack（既有 write-set 语义把本意图未收敛写入还原为 before）。
  7. 第三值 → 既有 `TX_RECOVERY_CONFLICT` 原样抛出，不改文件。
- 第 2.c 步锁内取样（`dep-33` 形态，均经 `controlledGit`；与第 2.b 步同一临界区、同一 journal 现场）：原语在该步 `await sampleCommitState({ targetRoot: payload.targetRoot, headBefore: payload.headBefore })`，回调在原语持锁期间执行、原语 await 其返回后再释放锁；原语自身保持 Git 无关（取样只在此一处发生）。
  - 取样器返回 `{ headSha, messages }`：`headSha = git rev-parse HEAD`（`payload.targetRoot` 项目根）；`headBefore` 为 40 位十六进制且 ≠ `headSha` 时取 `git log --reverse --format=%B <headBefore>..<headSha>`，否则取 `git log --format=%B -1`（限制为 `headSha` 单条）。
  - 取样失败或形态被拒（git 非零、`headSha` 非 40 位十六进制、`messages` 非数组）→ `TX_GIT_FAILED` 硬失败：零写入、journal 与已写文件原样保留、不进入任何回滚；**禁止**回退到锁外预读的 HEAD/消息，禁止降级为单条。
  - `committed = commitRequired && headSha !== payload.headBefore && messages 任一条含 AI-First-Tx: <该 journal 的 txId>`。
- `recoverLedgerCommand(ws, key)` 接线（**签名与参数个数不变，保持两参、无 `expect`**）：
  - 只把锁外预读的 `currentHead`/`headMessage` 入参换成 `sampleCommitState`（按上条形态实现，HEAD/消息形态被拒即抛 `TX_GIT_FAILED`）；`currentHead`/`headMessage` 不再作为判据入参传给原语。
  - 不构造、不传 `expect`：既有 CR 账本 journal 的恢复走原语缺省（无 `expect`）比对语义，与现状逐字一致；因此不因缺 `inputDigest` 来源而落入 `TX_INPUT_CONFLICT`，也不要求改任何既有调用者。
  - 既有 `gitHeadSha(ws)` 只保留用于 `recovered.rolledBack && recovered.paths.length && head` 后的 `syncLedgerIndex` 触发条件（非判据）；`syncLedgerIndex` 行为保留。
- 同一份契约由 TASK-04/05 的两个业务入口同传取样器；两个调用点不得各写一套取样实现。

## 验收条件

1. 在 tools CR worktree 根执行证据命令 `cmd-04`（plan §6.2 原样：repo=tools、cwd=`.`、executable=`node`、args=`["--test","skills/shared/crctl/scripts/test/durable-tx.test.mjs"]`、timeout=600）：全绿。真实运行范围 = 单文件 `durable-tx.test.mjs`（既有故障注入组织，不新建框架）；**不声称覆盖 `lib/` 全部模块**。新增覆盖：
   - B17-a（B-03 异意图在途）：同 key 事务中断在 written 之后、commit 之前 + 另一正文/策略的请求 → 第二个请求经锁内摘要比对得 `TX_INPUT_CONFLICT` 非零、零业务写入，旧 journal 与已写文件保持原样；随后同意图请求按原事务收敛（`rolledBack` → 补成 `changed=true`）。
   - B17-b（B-03 交错替换）：注入交错时序（请求 A 完成只读预读后，由测试路径收敛旧 journal 并以同身份异意图事务替换现场，再让 A 进入恢复）→ A 必须 `TX_INPUT_CONFLICT` 非零、零业务写入，且替换现场后新事务的 journal 与已写文件逐字保持（A 未回滚他人现场）；同摘要、异 txId 的变体 → `TX_LEDGER_RECOVERY_REQUIRED` 非零、零写入。
   - B18-b（B-07 提交落地、finish 前中断）：`ledger-after-commit` 故障注入 + 同 payload 重跑 + 随后合法覆盖 → 重跑先经原语收敛旧 journal（该 key 下 journal 目录消失、业务文件零改动），返回 exit=0 / `changed=false` / `commit` = 携带本意图 trailer 的提交（可为非 HEAD）；随后合法覆盖不再撞 `TX_LEDGER_RECOVERY_REQUIRED`。
   - B18-c（B-09 锁外快照与锁内现场分叉）：请求 R 先完成只读预读并固定 `expect={inputDigest,txId}`（提交前快照）；写入者 W 完成带 `AI-First-Tx: <txId>` 的提交 C 后在 `finishLedgerTransaction` 前中断（`ledger-after-commit`），锁经 `_setPidProbe`/ESRCH 呈现为陈旧锁；R 再以同一 expect 进入恢复 → 锁内现取 `headSha=C` 与含 trailer 的消息集 → committed：exit=0 / `changed=false` / `commit=C`（可为非 HEAD）、C 与已提交文件逐字保留（未还原为 before）、该 key 下 journal 目录消失；取样回调内以同 key 调 `beginLedgerTransaction` 必抛 `TX_LOCK_HELD`（证明取样持锁）；把预读快照固定为提交前 HEAD/空消息时结论不变（判据不消费锁外快照）。
   - B18-d（B-09 取样失败保守失败）：同 B18-c 现场但锁内取样不可用（`git rev-parse` 非零 / HEAD 形态被拒 / 取样器抛 `TX_GIT_FAILED`）→ 非零 `TX_GIT_FAILED`、stdout 无成功回执、零业务写入：已提交文件与 HEAD 原样、journal 未删除也未回滚；git 恢复可用后同一请求重跑得 committed（exit=0 / `changed=false` / `commit=C`、journal 消失）。
   - 既有调用兼容回归（FR-12）：以既有两参流程创建的 journal（不传 `expect`、与现状同形的写入/中断现场）在 `recoverLedgerCommand` 默认路径下收敛结果与现状逐字一致（不出现 `TX_INPUT_CONFLICT`、不要求 `inputDigest` 期望值）；并以 `cmd-01` 复跑（`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`，timeout=900，cwd=tools CR worktree 根）证明五个既有两参调用点所属子命令的恢复兼容。
2. 缺省兼容负测：不传 `expect`/`sampleCommitState` 时既有 `currentHead`/`headMessage` 判据路径行为逐字不变；既有 `recoverLedgerCommand(ws, key)` 两参调用（五个既有调用者路径）在默认路径下恢复行为与现状逐字一致；`phase=complete`、第三值、CAS、锁分支与错误码集合零新增。
3. 新增用例不得绕过 `controlledGit` 直接 `spawnSync('git', …)` 取证（含测试内的对方提交注入）；tools 测试读入后先 `\r\n → \n` 规范化，跨行匹配失败硬失败（工程纪律 #1）。
4. 文件集检查经受控入口（argv 固定），cwd = tools CR worktree 根；`<operational-workspace>` 取 `crctl workspace inspect CR-2026-075` 的 `operationalWorkspace` 原样值：

   `node skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <tools-worktree> --workspace <operational-workspace>`

   断言输出仅含本 TASK 声明的三个文件。status 仅证明文件集。

## 完成标志

- `cmd-04` 全绿且 B17-a/B17-b、B18-b/B18-c/B18-d 与既有调用兼容回归断言逐条可见。
- `durable-tx.mjs` 模块头不变量保持（业务 phase/Git/状态机零感知、零标准库以外依赖）；`recoverLedgerTransaction` 在全仓仍只有 `recoverLedgerCommand` 一个调用点（新增业务 helper `recoverBusinessLedgerCommand` 属 TASK-04 改动面，本 TASK 不落地），且该调用点是本 TASK 唯一改动的既有调用点；`recoverLedgerCommand` 保持两参、不传 `expect`，五个既有调用者零改动。
- 完成登记不受下游完成状态影响：`cmd-04` 全绿且缺省兼容回归通过（本 TASK 自身验收达成）即用 `crctl task done --task CR-2026-075-TASK-03` 即时登记，不等待 TASK-04/05 完成。
- 产物已落盘并提交，commit 自含其新增测试；不夹带 TASK-04/05 的业务入口改动（R9 顺序编辑：`crctl.mjs` 由 TASK-01/03/04/06 共享，本 TASK 只改 `recoverLedgerCommand` 一处）。

## 接口契约

**消费**（逐字对齐 SDD 与目标仓现状）：

- `acquireLock({ root, scope: 'ledger-<key>', op: 'ledger' })`（`durable-tx.mjs:127`）：独占 mkdir、无重入、无 TTL；同一 key 一把锁（取样与判定同处该临界区）。
- `latestLedger(root, key)`（`durable-tx.mjs:411`）：锁内重读最新 journal 的唯一来源。
- `rollbackLedgerPayload(payload, txDir)`（`durable-tx.mjs:429`）：既有 write-set 回滚与第三值判据。
- `loadExistingJournal({ root, op, cr, key, inputDigest, createAfterComplete })`（`durable-tx.mjs:212`）：只读预读；**既有 `recoverLedgerCommand` 接线不再使用它构造 `expect`**（`expect` 的构造属 TASK-04 的 `recoverBusinessLedgerCommand`）。
- `hasLedgerTransaction({ root, key })`（`durable-tx.mjs:458`）。
- `gitHeadSha(ws, cwd)`（`crctl.mjs:366`）、`controlledGit(ws, sub, args, cwd, caller, options)`（`crctl.mjs:399`）、`syncLedgerIndex(ws, paths, caller)`（`crctl.mjs:698`）、`deriveInstallRoot(opWs)`。
- Git 形态限制（`skills/shared/controlled-shell/rules.json`，本 CR 不改白名单）：`git.log.shapes` = `^--oneline .+$` / `^--format=%B -1$` / `^--reverse --format=\S+ \S+$`；`git.rev-parse.shapes` 含 `^HEAD$`、`^--verify \S+$`、`^--verify -q \S+$` 等。

**产出**：

```text
recoverLedgerTransaction({ root, key, currentHead, headMessage, expect, sampleCommitState })
  → { recovered: boolean, committed?: true, rolledBack?: true, paths: string[] }

expect?: { inputDigest: string, txId: string | null }
sampleCommitState?: (ctx: { targetRoot: string, headBefore: string })
  => Promise<{ headSha: string, messages: string[] }> | { headSha: string, messages: string[] }
```

- 错误码：只新增三个**既有**码的使用点——`TX_INPUT_CONFLICT`（锁内摘要不符）、`TX_LEDGER_RECOVERY_REQUIRED`（锁内 txId 不符）、`TX_GIT_FAILED`（取样失败/形态被拒）；不新增错误码。
- 既有 helper 签名不变：`recoverLedgerCommand(ws, key)`（零参数增删、不传 `expect`；只把判据取值来源换成锁内取样，`syncLedgerIndex` 触发条件保留）。
- 下游消费者：TASK-04 的新增 `recoverBusinessLedgerCommand`（TASK-05 复用）引用同一份签名与取样器形态，必须同传 `expect` 与 `sampleCommitState`，不得另立第二套取样或比对实现；既有 `recoverLedgerCommand(ws, key)` 只传 `sampleCommitState`、保持两参无 `expect` 的兼容语义。生产者完成即登记 done，不等待下游完成；跨消费者联合向量（共享 `_index.yml` 的 B18-a 类向量）由 TASK-04/05 各自用例验证、TASK-10 复跑核对。
