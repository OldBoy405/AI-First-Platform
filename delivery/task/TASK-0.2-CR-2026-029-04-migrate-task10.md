---
spec-id: ai-first-platform
version: "0.2"
id: CR-2026-029-TASK-04
type: TASK
cr-ref: CR-2026-029
plan-ref: "change-requests/CR-2026-029/plan.md"
sdd-ref: "change-requests/CR-2026-029/sdd.md"
title: 迁移移除 CR-2026-028 TASK-10
slug: migrate-task10
status: pending
estimate: 2h
depends-on: []
created: "2026-08-10T20:14:00+08:00"
---

# TASK-04 迁移移除 CR-2026-028 TASK-10

## 1. 任务描述

在 knowledge-base 仓（CR-2026-029 分支内）迁移 CR-2026-028：从 `change-requests/CR-2026-028/tasks/_index.yml` 定点移除 TASK-10 条目块，删除 `tasks/TASK-10.md`，删除后校验其余 9 个任务 id 集合不变。

## 2. 涉及文件

- knowledge-base：`change-requests/CR-2026-028/tasks/_index.yml`、`change-requests/CR-2026-028/tasks/TASK-10.md`

## 3. 实现要点

- 定点编辑按 SDD §4.1：CRLF 归一 → 锚定 `  - id: CR-2026-028-TASK-10` 起始行 → 块结束=下一个 `  - id:` 或文件尾 → 删除 → 校验 id 集合（TASK-01..09 保留、TASK-10 消失）→ CAS 复核写回。
- 解析/删除失败必须硬失败，禁止静默降级（纪律 #1）。
- 不触碰 CR-2026-028 的 approval.yml、review-annotations、traceability 与已 merge 代码。

## 4. 验收条件

1. _index.yml 无 TASK-10、含 TASK-01..09 且字段完整；
2. TASK-10.md 已删除；
3. 其余任务块逐字节保留（diff 仅含 TASK-10 块删除）。

## 5. 接口契约

- **消费**：CR-2026-028 既有任务索引。
- **产出**：迁移后的索引与文件系统状态。
