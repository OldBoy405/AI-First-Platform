---
id: CR-2026-053-TASK-11
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 存量 CR-2026-051/052 修复
slug: existing-cr-fix
status: pending
estimate: 2h
depends-on: [CR-2026-053-TASK-05]
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

存量 CR-2026-051 和 CR-2026-052 走同一受控 task + 绑定接口修复：
- 使用 `bind-current-task-to-cr` 接口
- 禁用直接 SQL 修改

## 涉及文件 / 模块

- CR-2026-051 和 CR-2026-052 的 worktree

## 实现要点

参考 SDD §6 FR-B8:
- 按 AC-D1~D6 验收清单执行
- 验证绑定成功后 CR→Issue 投影正确

## 验收条件

1. CR-2026-051 绑定成功
2. CR-2026-052 绑定成功
3. AC-D1~D6 覆盖测试通过

## 完成标志

- 两个 CR 均通过验收清单

## 接口契约

**消费**:
- `POST /api/crs/{cr_id}/bind-current-task` 接口（由 CR-2026-053-TASK-05 实现）
