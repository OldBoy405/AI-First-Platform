---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-019-TASK-02
type: TASK
cr-ref: CR-2026-019
plan-ref: "change-requests/CR-2026-019/plan.md"
sdd-ref: "change-requests/CR-2026-019/sdd.md"
title: 实现 crctl task done 子命令
slug: cmd-task-done
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-04T17:36:00+08:00"
---

## 任务描述

新增 `crctl task done <CR-ID> --task <TASK-ID> [--workspace <dir>]`：将 `tasks/_index.yml` 中该 TASK 的 `status` 由 pending 改为 done 并追加 `done-at` 时间戳。收敛 discipline #8 要求的"任务即时标记完成"，替代会话内手工编辑 YAML。

## 涉及文件 / 模块

- `crctl.mjs`：新增 `editTaskDone(text, taskId)` 纯函数 + `cmdTaskDone(ws, cr, flags)` + dispatch `case 'task'`（:1419 switch）

## 实现要点（参考 SDD §4.1 / §1.3）

- 前置态守卫：`resolveCrState` 读权威状态，须为 `developing`，否则 `fail('ILLEGAL_LEDGER_STATE', 当前态/期望态)`。
- `editTaskDone`：先 `replaceAll('\r\n','\n')`；块锚定正则抽取 `- id: <taskId>` 到下一 `- id:` 或 EOF；块内 `status:` 行用 replace 回调**一次产出两行**（同缩进 `status: done` + `done-at`）；`hit` 标志为 false → `fail('TASK_INDEX_SHAPE')`（匹配不到硬失败，纪律 #1）。
- 错误码：`TASK_NOT_FOUND`（块抽不到）/ `TASK_ALREADY_DONE`（已 done）/ `ILLEGAL_LEDGER_STATE`。
- 写入走 `casWrite`（expectedHash = 读入时全文 sha256）；写后 `auditLog(op:'task-done', before/after 摘要)`。**不改 CR status、不发 status 事件**（纪律 #5）。

## 验收条件

1. 对 pending 的 TASK 执行 → `_index.yml` 该块 `status: done` 且新增 `done-at`，退出 0。
2. TASK-ID 不存在 → `TASK_NOT_FOUND` 非零退出，`_index.yml` 无变化。
3. 已 done 的 TASK 再执行 → `TASK_ALREADY_DONE` 非零退出，文件无变化。

## 完成标志

子命令可用，TASK-05 对应用例（正常/不存在/已done/非法前置态）通过，lint 零报错。
