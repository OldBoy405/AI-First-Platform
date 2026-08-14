---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-019-TASK-04
type: TASK
cr-ref: CR-2026-019
plan-ref: "change-requests/CR-2026-019/plan.md"
sdd-ref: "change-requests/CR-2026-019/sdd.md"
title: 实现 crctl archive-move 子命令
slug: cmd-archive-move
status: pending
estimate: 6h
depends-on: ["CR-2026-019-TASK-01"]
assignee: ""
created: "2026-08-04T17:36:00+08:00"
---

## 任务描述

新增 `crctl archive-move <CR-ID> --final-status <status> [--archive-reason <s>] [--spec-id <id>] [--workspace <dir>]`：原子地从 `_backlog.yml` 删除该 CR 条目并向 `_history.yml` 追加富化条目。替代 cr-archive 期手工在两文件间搬移。

## 涉及文件 / 模块

- `crctl.mjs`：新增 `cmdArchiveMove(ws, cr, flags)` + dispatch `case 'archive-move'`，写入用 TASK-01 的 `casWriteMulti`

## 实现要点（参考 SDD §4.3）

- 前置态守卫：status === `archived`（advance 已把状态推到 archived 后才调用本命令）。
- 读 `_backlog.yml`(text_b,hash_b) + `_history.yml`(text_h,hash_h)。
- 从 backlog 抽 `- id: {cr}` 块，抽不到 → `ENTRY_NOT_IN_BACKLOG`；history 已含 {cr} → `ENTRY_ALREADY_IN_HISTORY`（防重复归档）。
- newBacklog = 删该块；newHistory = `history[]` 追加富化块（原块缩进下沉一级 + `final-status/archive-reason/writeback-spec-id/archived-at`）。
- `casWriteMulti([{backlog,hash_b,newBacklog},{history,hash_h,newHistory}])`；写后 `auditLog(op:'archive-move')`。不改 status。
- 残余崩溃窗口为已接受天花板（SDD §4.3），不加 WAL。

## 验收条件

1. 正常执行 → CR 条目从 backlog 消失、在 history 出现且带 `final-status`，退出 0。
2. history 侧 CAS 冲突（写前被改） → `CAS_CONFLICT` 且**两文件均无变更**。
3. 非 archived 前置态 → `ILLEGAL_LEDGER_STATE`，两文件无变更。

## 完成标志

子命令可用，依赖 TASK-01 已合入；TASK-05 对应用例（正常/CAS 冲突/非法前置态）通过，lint 零报错。
