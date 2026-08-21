---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-049-TASK-02
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: tools — writeback trace intent journal 与 complete replay
slug: tools-writeback-trace-intent-replay
status: pending
estimate: 10h
depends-on: [CR-2026-049-TASK-01]
created: 2026-08-20T20:59:46+08:00
---

# TASK-02 — tools：writeback trace intent journal 与 complete replay

## 1. 任务描述

`applyWritebackAtomic`（traceability 阶段）在 commit/push 确认后，先把完整 canonical payload 持久化到 writeback journal（`traceOutbox` intent），再经 `emitTraceEvent` callback 写 outbox；失败返回 warning 并保持 pending。complete journal 重放必须在 `resolveOperationalWorkspace` 之前执行，使 txws 被清理后仍可补发（SDD §1.3，TD-B2）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（applyWritebackAtomic）
- `skills/shared/crctl/scripts/crctl.mjs`（cmdWritebackApply 注入 callback；validateWritebackManifest 接受 v2）
- `skills/writeback/writeback-traceability/SKILL.md`（将 `EMIT_FAILED(event_kind=trace)` 作为 pending 结果输出，不宣称已交付）
- 测试：fault injection（outbox 写失败）、complete replay、txws 已删场景

## 3. 实现要点

- manifest v2 校验：重算 `payloadSha256` 并校验 `payload.spec_id===payload.traceability['spec-id']`；`WRITEBACK_MANIFEST_INVALID` 覆盖 v2 违规。
- journal 字段：`traceOutbox={state:'pending'|'emitted', commit, dedupName, payload, payloadSha256}`；push 确认后、发射前先 `save`。
- 发射：`input.emitTraceEvent({cr, commit, dedupName, payload}) -> string|null`；`dedupName='trace-{cr}-{commit}.json'`；null → warning `EMIT_FAILED(event_kind='trace')`，主流程完成。
- 重放：`loadExistingJournal({op:'writeback', key: cr+'-traceability'})` 在 operational workspace 解析与 candidate 读取之前；`phase==='complete' && state==='pending'` 时仅用 journal intent 补发，成功后置 `emitted` 并返回。

## 4. 验收条件

1. outbox 写失败（mkdir/write fault）→ writeback 完成、返回 warning、journal `state='pending'` 且含完整 payload。
2. 恢复后重跑同一 `writeback-apply --stage traceability` → 补发成功、`state='emitted'`、文件名为 `trace-{cr}-{commit}.json` 确定性命名。
3. 删除 txws/candidate 后重放仍成功（不触碰 operational workspace 解析）。

## 5. 完成标志

`node --test` 全绿；三个验收场景各有独立测试；无 journal 手写账本绕过。

## 6. 接口契约

- 消费：TASK-01 的 manifest v2 `event`（含 `payloadSha256`）。
- 产出：
  - journal `traceOutbox` 结构（供 TASK-03 archive gate 消费）。
  - `input.emitTraceEvent({cr, commit, dedupName, payload}) -> string|null`（由 `cmdWritebackApply` 注入，内部调用 `emitOutboxEvent`，`event_kind:'trace'`）。
