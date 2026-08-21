---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-049-TASK-03
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: tools — archive trace pending 前置门
slug: tools-archive-trace-pending-gate
status: pending
estimate: 8h
depends-on: [CR-2026-049-TASK-02]
created: 2026-08-20T20:59:46+08:00
---

# TASK-03 — tools：archive trace pending 前置门

## 1. 任务描述

`archiveCr` 在创建 archive journal、写 authority commit、清理任何 worktree **之前**读取 writeback traceability journal：`emitted` 放行；`pending` 调用 `replayTraceEvent` 补发，成功持久化后放行；仍失败抛 `ARCHIVE_TRACE_PENDING` 零写入并保留现场。journal 缺失/意图不完整抛 `ARCHIVE_TRACE_FACT_MISSING`（SDD §1.3，TD-B2）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（archiveCr 前置段）
- `skills/shared/crctl/scripts/crctl.mjs`（cmdArchive 注入 replayTraceEvent）
- `skills/cr/cr-archive/SKILL.md`（行为契约文案，非 prompt 面变更）

## 3. 实现要点

- 前置位置：`loadOrCreateJournal(op:'archive')` 之前、任何 `git add/commit/push` 与 `archiveCleanup` 之前。
- 读取 `writeback/{cr}-traceability` journal；`traceOutbox.state==='pending'` → `input.replayTraceEvent({cr, intent})`（内部 `emitOutboxEvent`，复用 TASK-02 的 `dedupName`）；成功 → 更新原 journal `state='emitted'`。
- 失败分支：`throw new TxError('ARCHIVE_TRACE_PENDING', ..., {cr, txId})`；不删除任何资源。
- Skill 文案：`ARCHIVE_TRACE_PENDING` 只提示重跑同一 archive，禁止跳门/手工清 journal。

## 4. 验收条件

1. pending + outbox 不可写 → archive 拒绝，无 commit/push、无 cleanup，工作区现场保留。
2. pending + outbox 恢复 → 重跑 archive 成功，journal `state='emitted'`，无重复事件文件。
3. `emitted` → 直接通过，不重复发射；journal 缺失 → `ARCHIVE_TRACE_FACT_MISSING` 非零。

## 5. 完成标志

`node --test` 全绿；三个验收场景独立测试；archive 成功路径行为不回归。

## 6. 接口契约

- 消费：TASK-02 的 `traceOutbox` journal 结构与 `dedupName`。
- 产出：
  - `input.replayTraceEvent({cr, intent}) -> string|null`（cmdArchive 注入）。
  - 错误码 `ARCHIVE_TRACE_PENDING` / `ARCHIVE_TRACE_FACT_MISSING`（供 TASK-13 集成与 Skill 契约消费）。
