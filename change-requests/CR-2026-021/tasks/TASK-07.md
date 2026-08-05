---
id: CR-2026-021-TASK-07
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: crctl task allocate（S7，TASK-ID CAS 分配）
slug: crctl-task-allocate
status: pending
estimate: 4h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-8：扩展现有 `task` 子命令族，新增 `crctl task allocate <cr> [--slug <s>]`。内部分配 `TASK-{NN}`（同 cr-init 模式：分配即写，不接受调用方传入编号），`slug` 缺失回退 `task-{NN}`。以 `casWrite` 写 `tasks/_index.yml`，唯一并发冲突码 `CAS_CONFLICT`。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（扩展 `task` 命令分支）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点

1. 与 TASK-06 的 cr-init 同一「分配即写」原则：不取显式编号入参，避免重蹈 SDD-BLOCK-001 同类矛盾。
2. `slug` 兜底命名逻辑与 `writeback-tasks.mjs`（CR-2026-020）已有的 slug 处理风格对齐（如有可复用的命名规则，不重复发明）。

## 验收条件

- AC-5（PRD）：并发调用两次，TASK-ID 不重复；slug 缺失时按兜底命名生成；测试用组件级 mismatch-hash 手法（同 TASK-06）。

## 完成标志

`node --test crctl.test.mjs` 全绿（含本任务用例）。
