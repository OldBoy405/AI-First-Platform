---
id: CR-2026-027-TASK-04
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: archived TASK 完成门禁五步判定（deliveryIndexComplete 修复）
slug: archived-task-gate-five-steps
status: pending
estimate: 6h
depends-on: ["CR-2026-027-TASK-01"]
created: "2026-08-09T23:35:00+08:00"
---

# TASK-04 — archived TASK 完成门禁（FR-9）

## 任务描述

修复 `deliveryIndexComplete` 在 task index 缺失或所有 TASK pending 时得到空 doneIds 并放行的问题：正常归档不允许隐式 no-task，缺文件/空数组不得被解释为无任务。

## 涉及文件 / 模块

- tools `skills/shared/crctl/scripts/crctl.mjs`（`deliveryIndexComplete` checker 实现 + `cmdAdvance` 对 archived 目标态的校验路径）
- tools `skills/shared/crctl/scripts/test/crctl.test.mjs`
- **不改** `gates.json`（D-9：archived 门禁声明已含 deliveryIndexComplete，缺口在执行层）

## 实现要点（SDD §4.1）

1. `deliveryIndexComplete` 改为五步判定：① `tasks/_index.yml` 不存在 → `TASK_INDEX_MISSING`；② `tasks[]` 空数组 → `TASK_LIST_EMPTY`（不得解释为 no-task）；③ 任一 TASK status ≠ done → `TASK_STATUS_INCOMPLETE`（列出未完成 TASK-ID）；④ 全部 done 后 `delivery/task/_index.yaml` 缺失或空 → `DELIVERY_INDEX_MISSING`；⑤ 全部通过放行
2. `rejected`/`withdrawn` 终态不适用 archived 门禁（提前终止语义，D-8）；`archive-move` 的 `--final-status` 与 cr.md 当前 status 一致性校验在 TASK-06 落地
3. 不新增 no-task 标志与永久 `task reconcile` 命令
4. 行尾纪律：读取 `_index.yml` 先 CRLF→LF 归一，解析用 `split(/\r?\n/)`

## 验收条件

1. 「task index 存在但全部 pending」→ `advance --to archived` 返回 `TASK_STATUS_INCOMPLETE` 且不归档
2. 「task index 缺失」→ `TASK_INDEX_MISSING` 拦截
3. 「tasks 空数组」→ `TASK_LIST_EMPTY` 拦截
4. 「全部 done 但 delivery/task/_index.yaml 缺失」→ `DELIVERY_INDEX_MISSING` 拦截
5. 全部就绪 → 正常放行归档；rejected/withdrawn 无 TASK 可进入 history（AC-11/AC-12）

## 完成标志

crctl.test.mjs 五类失败 + 放行用例全绿；既有 archived 路径用例不回归；gates.json 无改动（git diff 校验）。

## 接口契约

- 消费：TASK-01 产出的 tools worktree
- 产出：五步判定的 `deliveryIndexComplete`（失败码 `TASK_INDEX_MISSING`/`TASK_LIST_EMPTY`/`TASK_STATUS_INCOMPLETE`/`DELIVERY_INDEX_MISSING`）；TASK-06 的 archive-move 三终态接受与 TASK-10 回归基于本产出
