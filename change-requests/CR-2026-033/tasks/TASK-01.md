---
id: CR-2026-033-TASK-01
type: TASK
cr-ref: CR-2026-033
plan-ref: "change-requests/CR-2026-033/plan.md"
sdd-ref: "change-requests/CR-2026-033/sdd.md"
title: 契约冻结与红测（T01）
slug: checkpoint-contract-red-tests
status: pending
estimate: 8h
depends-on: []
created: 2026-08-13T19:06:07+08:00
---

## 任务描述

在动实现前冻结 checkpoint 全部公开契约并写入测试：durable journal schema、错误码表、fault points。新增测试在当前旧实现下必须红（预期失败），同时 253 crctl + 10 writeback 现有测试保持绿。本任务只写测试，不提前修改生产契约。

## 涉及文件 / 模块

- 修改 `tools/skills/shared/crctl/scripts/test/durable-tx.test.mjs`（checkpoint envelope 红测）
- 新增 `tools/skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs`（CLI/错误输出红测，T04 继续扩成集成矩阵）
- 修改 `tools/skills/shared/crctl/scripts/test/fault-harness.test.mjs`（5 个新 point 登记红测）

## 实现要点（引用 SDD §2.3/§2.4/§3.5/§10.1.1）

1. 冻结预期：durable-tx 私有 `OPS` 与 `PAYLOAD_KEYS` 数组均应包含字符串 `checkpoint`，journal envelope 应包含 `checkpoint: null`；不得把私有数组虚构成 `OPS.checkpoint`/`PAYLOAD_KEYS.checkpoint` 属性。
2. fault points 预期固定：`checkpoint-after-source-commit` / `checkpoint-after-push` / `checkpoint-after-confirm` / `checkpoint-after-metadata-commit` / `checkpoint-after-metadata-push`。唯一登记源是 TASK-02 将修改的 `durable-tx.mjs#FAULT_POINTS`；crctl 只消费既有 import，不复制列表。
3. 错误码契约固定为 SDD §3.5 唯一集 18 个 code：9 个 `CHECKPOINT_*`，以及 `GRAPH_CHANGED_DURING_TRANSACTION`、`TX_LOCK_HELD`、`TX_INPUT_CONFLICT`、`TX_RECOVERY_CONFLICT`、`TX_WRITESET_INVALID`、`TX_BLOB_MISMATCH`、`TX_GIT_FAILED`、`UNKNOWN_FAULT_POINT`、`FAULT_INJECTED`。
4. 红测断言：journal schema 尚不接受 checkpoint、5 个 fault point 尚未登记、CLI 尚无 checkpoint、错误输出契约尚未实现。
5. 先跑基线确认 253+10 全绿，再加红测；不得放宽任何旧断言，也不得为了让 T01 变绿而提前改生产代码。

## 验收条件

1. `node --test skills/shared/crctl/scripts/test/durable-tx.test.mjs skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs skills/shared/crctl/scripts/test/fault-harness.test.mjs`：新增 checkpoint 契约断言在旧实现下按预期失败。
2. 失败证据分别对应：checkpoint envelope 未支持、5 个 fault point 未登记、checkpoint dispatch/错误输出未实现；不得因测试自身语法/fixture 错误而红。
3. 全量旧基线仍为 crctl 253/253 + writeback 10/10；18-code expected set 与 SDD §3.5 一一对应。

## 完成标志

契约红测落盘并确认因生产能力尚未实现而按预期红；原有基线 253+10 绿；commit 到 tools 仓 `requirement/CR-2026-033`。

## 接口契约

- 产出：测试冻结的 checkpoint envelope（OPS/PAYLOAD_KEYS 数组包含 `checkpoint`）、5 个 fault point 名、18 个错误码 expected set（TASK-02/04 消费）。
- 消费：无（首任务）。
