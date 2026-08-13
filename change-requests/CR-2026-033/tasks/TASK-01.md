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

在动实现前冻结 checkpoint 全部公开契约并写入测试：durable journal schema、错误码表、fault points。新增测试在当前旧实现下必须红（预期失败），同时 253 crctl + 10 writeback 现有测试保持绿。

## 涉及文件 / 模块

- 修改 `tools/skills/shared/crctl/scripts/lib/durable-tx.mjs`（仅登记 op/payload keys 与 fault point 常量，不含业务逻辑）
- 新增 `tools/skills/shared/crctl/scripts/test/checkpoint-contract.test.mjs`（红测）
- 修改 `tools/skills/shared/crctl/scripts/crctl.mjs`（仅 FAULT_POINTS 注册 5 个 checkpoint point，供 `UNKNOWN_FAULT_POINT` 校验）
- 修改 `tools/skills/shared/crctl/scripts/test/fault-harness.test.mjs`（登记清单断言）

## 实现要点（引用 SDD §2.3/§2.4/§3.5/§10.1.1）

1. `OPS` 增加 `checkpoint`，`PAYLOAD_KEYS` 增加 `checkpoint`；envelope 增加 `checkpoint: null`。
2. fault points 固定：`checkpoint-after-source-commit` / `checkpoint-after-push` / `checkpoint-after-confirm` / `checkpoint-after-metadata-commit` / `checkpoint-after-metadata-push`。
3. 错误码契约固定为 SDD §3.5 全表 19 个 code，其中 checkpoint 新增 9 个（`CHECKPOINT_*`），其余复用既有 `TX_*`/`GRAPH_CHANGED_DURING_TRANSACTION`/`UNKNOWN_FAULT_POINT`/`FAULT_INJECTED`。
4. 红测断言：journal schema 非法输入被拒、每个已登记 fault point 可命中、每个错误码的 zero-sideEffect/recoverCommand 语义有枚举断言。
5. 先跑基线确认 253+10 全绿，再加红测；不得放宽任何旧断言。

## 验收条件

1. `node --test skills/shared/crctl/scripts/test/*.test.mjs`：新增契约测试红（旧实现下失败），旧 253 项仍绿。
2. `CRCTL_FAULT_POINT=checkpoint-after-push` 等 5 个值在 CLI 层被识别为已登记（不再 `UNKNOWN_FAULT_POINT`）。
3. 错误码表断言与 SDD §3.5 一一对应，无遗漏、无多出。

## 完成标志

契约测试落盘并确认在旧实现下按预期红；基线 253+10 绿；commit 到 tools 仓 `requirement/CR-2026-033`。

## 接口契约

- 产出：`OPS.checkpoint`、`PAYLOAD_KEYS.checkpoint`、5 个 fault point 名、19 个错误码清单（TASK-02/03/04 消费）。
- 消费：无（首任务）。
