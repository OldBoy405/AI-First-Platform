---
id: CR-2026-076-TASK-04
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "review-record 写入与隔离提交原子闭环"
slug: crctl-review-record-atomic-write-set
status: pending
estimate: 16h
depends-on: [CR-2026-076-TASK-03]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-03；AC-05／AC-06／AC-07／AC-08；SDD §4.3 + SDD-CLOSE-01）：把 `review-record` 做成「write-set 构造 → 整索引隔离断言 → 仅本次实际文件提交 → 事务收尾 → 含真实 SHA 的 outbox」原子闭环，并使 commit 后崩溃与同操作重投按已提交事实恢复、不重评、不再 bump。

背景与输入条件：`dep-12` 结论原文——评审证据写入、traceability 段落渲染与 index 受控只读查询已存在（`cmdReviewRecord`、`renderReviewsStage`、`upsertReviewsStage`、`queryTrackedChanges`），可在此基础上补齐整索引隔离断言与恢复语义；`dep-13` 提供 `beginLedgerTransaction`／`finishLedgerTransaction`／`abortLedgerTransaction`／`recoverLedgerTransaction`／`applyWriteSet`；`dep-34` 明确事务键 `ledgerTxKey(op, cr, stage = '')`（`crctl.mjs:702`）为模块内私有、不可跨文件导入，「复用该键」只能落在同文件的命令实现上，设计不得假设它由 `durable-tx.mjs` 提供。

明确不做：不引入第二幂等账本（SDD-CLOSE-01）；不新增第二套事务原语；`advance` 保持状态职责，不自动 `add` 整个 CR、不代提交作者代码。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`async function cmdReviewRecord(ws, cr, gates, flags)`（:2200）、`function ledgerTxKey(op, cr, stage = '')`（:702）及其调用点 `beginLedgerCommand`／`recoverLedgerCommand`
- `skills/shared/crctl/scripts/lib/durable-tx.mjs`（`dep-13`，只消费不新增原语）
- `skills/shared/crctl/scripts/test/caller-contract.test.mjs`、`test/fault-harness.test.mjs`、`test/durable-tx.test.mjs`

## 实现要点

1. 执行顺序严格按 SDD §4.3：前置核验 → payload／对象校验 → **实际** write-set 构造 → durable transaction + CAS → **整个 index 的隔离断言**（`git status --porcelain` 输出不得含 write-set 之外的路径，先于 commit 执行）→ 仅本次实际 `files[]` 的隔离提交 → `finishLedgerTransaction` → 发含真实提交 SHA 的 outbox → 成功返回。
2. write-set 明细（不得多、不得少）：`PASS` 无 bump = annotation + traceability；`PASS` 有 bump = 额外纳入 `review-loop.yml`（E2／E3）。
3. 失败分支：非零返回，回滚本次账本写入与**本次暂存影响**（不夹带、不丢弃作者或其他任务的变更），保留原 payload；不发成功事件、不推进下一节点。
4. commit 后崩溃恢复：按已提交事实恢复，**不重新评审、不再 bump**；事件引用真正包含评审账本的 SHA。
5. 幂等与恢复固定：固定原 CR、loop／cycle／attempt、被评审对象、verdict／blockers、payload、bump 意图与本次 write-set；输入或对象被替换不得当作同一次操作的新执行；幂等识别复用既有事务原语与意图摘要（`dep-13`），事务键取自 `ledgerTxKey`（`dep-34`）。
6. 本地提交 ≠ 远端发布：远端仍由 `checkpoint`／`push-progress` 完成（本 TASK 不改 `cmdCheckpoint`，属 TASK-09）。

## 验收条件

1. **AC-05（cmd-04 + cmd-05）**：四种组合（PASS／BLOCK × 有无 bump）各自产生对应的 2 或 3 个账本文件的**隔离**提交，`HEAD` 与 outbox 事件含同一真实 SHA，远端 ref 不变。
2. **AC-06（cmd-05）**：存在不相关暂存或作者变更时非零退出、暂存与本次账本回滚、payload 保留、无成功事件。
3. **AC-07（cmd-05）**：commit 后崩溃或同操作重投返回幂等成功，不产生第二次提交／第二次 attempt；事件指向真实提交。
4. **AC-08（cmd-05）**：恢复期间原对象被替换时非零技术中止，annotation 的 verdict 与 subject 保持原值（不重算后覆盖）。
5. 运行范围以 plan §6.2／§5.5 为唯一事实源：`cmd-04` = `crctl.test.mjs` 单文件；`cmd-05` = `caller-contract.test.mjs` + `fault-harness.test.mjs` + `durable-tx.test.mjs` 三文件，观测 review-record 的调用方契约、故障注入恢复分支与共享事务原语（write-set／CAS／回滚／`ledgerTxKey` 幂等）；**不声称**覆盖 `workspace-transactions.mjs` 的其他命令面。

## 完成标志

- write-set、整索引隔离断言、失败回滚、commit 后恢复与幂等路径均有用例覆盖；`cmd-04`、`cmd-05` 真实执行退出码 0，原样输出落 `test-evidence/cmd-04.log`、`test-evidence/cmd-05.log`；
- 未新增幂等账本、未新增事务原语（结果中给出「复用既有原语」的符号清单）；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-03 口径 + `dep-13`／`dep-34`，不得缩写）：
- 操作根解析：`bindTaskWorkspace` 归一结果（TASK-03 产出）；账本路径 `change-requests/{cr}/review-annotations/{stage}.yml`、`change-requests/{cr}/traceability.yml`、`change-requests/{cr}/review-loop.yml`；
- `import { beginLedgerTransaction, finishLedgerTransaction, abortLedgerTransaction, recoverLedgerTransaction, applyWriteSet } from './lib/durable-tx.mjs'`（`dep-13`）；
- `function ledgerTxKey(op, cr, stage = '')`（`crctl.mjs:702`，同文件私有，只由 `beginLedgerCommand`／`recoverLedgerCommand` 消费）。

产出（供 TASK-05／TASK-08／TASK-09／TASK-17 消费，消费方不得缩写）：
- `async function cmdReviewRecord(ws, cr, gates, flags)`（:2200）：入参 `--stage`／verdict／blockers／`--bump-attempt`（语义不变）；成功回执经 `ok()` 单出口返回，`phase`／`changed` 形状沿用（§3.1 回执形状）；含真实提交 SHA 的 outbox 事件（`event_kind=review` 既有形态）；
- 失败出口：`REVIEW_COMMIT_FAILED` 类既有 code（非零）、`TX_INPUT_CONFLICT`（操作重放输入冲突）、`TX_LEDGER_RECOVERY_REQUIRED`／锁超时既有 code（§3.2 错误码闭包），不新增同义错误码；
- 幂等键：`ledgerTxKey('review-record', cr, stage)` + 意图摘要，二者共同构成同一操作的识别，**不新增第二幂等账本**。
