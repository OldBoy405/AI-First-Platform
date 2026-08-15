---
id: CR-2026-040-TASK-01
type: TASK
cr-ref: CR-2026-040
plan-ref: "change-requests/CR-2026-040/plan.md"
sdd-ref: "change-requests/CR-2026-040/sdd.md"
title: durable-tx 增加 test op 与 payload 槽位
slug: durable-tx-test-payload
status: pending
estimate: 2h
depends-on: []
created: 2026-08-15T12:00:00+08:00
---

## 任务描述

在既有 `skills/shared/crctl/scripts/lib/durable-tx.mjs` 的 journal envelope、目录锁和 recoverable write-set 模型中增加 `test` 业务 op，使结构化测试的记录阶段能够复用同一事务恢复实现。不引入新的 journal 格式、WAL、saga 或补偿逻辑，不新增 test 专用 fault point。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/durable-tx.mjs`

## 实现要点

- 将 `"test"` 加入 `OPS` 白名单（用于 `acquireLock` 与 `assertEnvelope`）。
- 将 `"test"` 加入 `PAYLOAD_KEYS`，保持 journal 首建时六个 payload 之外新增 `test: null` 槽位。
- 确认 `loadOrCreateJournal` / `saveJournal` / `applyWriteSet` / `recoverWriteSet` 对 `test` op 无需特判。
- 不在 `FAULT_POINTS` 增加 test 专用点：记录阶段复用既有 `tx-apply-between-rename` 与 `tx-apply-before-complete`。
- 遵守行尾纪律：涉及读入内容的哈希/解析统一先 `\r\n → \n` 规范化。

## 验收条件

- `node --test skills/shared/crctl/scripts/test/fault-harness.test.mjs` 现有用例保持通过。
- 在临时 workspace 中手动构造 `op: "test"` 的 journal，确认 `assertEnvelope` 接受、`op` 与 payload 槽位一致；构造 `op: "test"` 但 payload 为空时 `saveJournal` 仍按既有规则拒绝。

## 完成标志

- `OPS`/`PAYLOAD_KEYS` 均含 `test`，`git diff` 仅命中 `durable-tx.mjs`，无新 fault point，既有 fault-harness 全绿。

## 接口契约

- 消费：无上游 TASK。
- 产出：`durable-tx.mjs` 导出契约不变，仅使 `acquireLock({root, scope:"test", op:"test", cr})` 与 `loadOrCreateJournal({op:"test", cr, graphDigest, inputDigest})` 合法；供 TASK-02 的 `testCr` 调用。
