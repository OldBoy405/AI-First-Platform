---
id: CR-2026-049-TASK-06
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: multica — trace 事件入账（schema/事务/processed）
slug: multica-trace-ingest-transaction
status: pending
estimate: 10h
depends-on: [CR-2026-049-TASK-04, CR-2026-049-TASK-05]
created: 2026-08-20T20:59:46+08:00
---

# TASK-06 — multica：trace 事件入账（schema / 事务 / processed）

## 1. 任务描述

`crsync.go` 接受 `trace` 事件：`knownEventKinds` 增加 trace；payload 按 canonical envelope 校验（spec_id、traceability 对象、milestones、`cr_id` 恰一段）；入账使用事务内 insert-or-load + `FOR UPDATE` + processed 标记，只有 committed processed 行才 ack；payload 上限 2 MiB。trace 是 ledger-only，不触发 `cr.status` 转换（SDD §3.1，TD-B3）。

## 2. 涉及文件 / 模块

- `server/internal/governance/crsync.go`（trace 校验与事务分支）
- `server/internal/governance/crsync_test.go`（fault injection、幂等、坏 payload）
- daemon 事件 schema fixture

## 3. 实现要点

- `validateTracePayload(payload json.RawMessage) error`：`spec_id` 非空、`traceability` 为对象、`milestones` 数组、payload 中 `- cr: {cr_id}` 恰一段；违规 rejected code `BAD_TRACE_PAYLOAD`。
- `MaxTracePayloadBytes = 2<<20`；超限 `TRACE_PAYLOAD_TOO_LARGE`，文件保留（rejected，不删除）。
- `ingestTraceTx`：BEGIN → INSERT `ON CONFLICT DO NOTHING` → `SELECT ... FOR UPDATE` → 已 processed 且 `payload = incoming::jsonb` 语义相等 → commit 幂等；payload 不同 → `EVENT_IDEMPOTENCY_CONFLICT` rollback/reject；未 processed → schema 校验 + `processed_at=now()` → commit；`apply()` 不新增 trace 状态分支（default 即无状态转换）。
- `HandleCREvents` 仅在事务 commit 后把文件加入 Accepted。

## 4. 验收条件

1. 合法 trace：accepted、`processed_at` 非空、`cr.status` 不变。
2. fault injection 在 INSERT 后/processed 前中断：重投最终一行且 processed；同 key 不同 payload → rejected 且文件保留。
3. 坏 payload / 2MiB+ → rejected（对应错误码），daemon 不删文件。

## 5. 完成标志

`go test ./server/internal/governance/...` 全绿；三个验收场景独立测试。

## 6. 接口契约

- 消费：TASK-05 的 workspace conflict target 与 lockKey。
- 产出：
  - `validateTracePayload(payload json.RawMessage) error`；`ingestTraceTx(ctx, workspaceID, ev) error`；`MaxTracePayloadBytes`。
  - ledger 行：`(workspace_id, cr_id, commit_sha, 'trace', payload)` + `processed_at`（供 TASK-07 读服务）。
