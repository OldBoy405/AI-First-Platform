---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-019-TASK-03
type: TASK
cr-ref: CR-2026-019
plan-ref: "change-requests/CR-2026-019/plan.md"
sdd-ref: "change-requests/CR-2026-019/sdd.md"
title: 实现 crctl merge-metadata 子命令
slug: cmd-merge-metadata
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-04T17:36:00+08:00"
---

## 任务描述

新增 `crctl merge-metadata <CR-ID> --repo <r> --trunk <t> --sha <sha> [--workspace <dir>]`：向 `_backlog.yml` 对应条目的 `merge-commits[]` 幂等追加结构化条目 `{repo, trunk, sha}`。替代回写期手工编辑 backlog。

## 涉及文件 / 模块

- `crctl.mjs`：新增 `editMergeMetadata(...)` 纯函数 + `cmdMergeMetadata(ws, cr, flags)` + dispatch `case 'merge-metadata'`

## 实现要点（参考 SDD §4.2 / §0 修订）

- **入参结构化**：`merge-commits[]` 是 `{repo,trunk,sha}` 条目（非裸 sha，SDD §0 已核实修订 PRD FR-2），故取 `--repo/--trunk/--sha` 三参。
- 前置态守卫：status ∈ {`merging`, `writing-back`}，否则 `ILLEGAL_LEDGER_STATE`。
- `loadBacklogEntry(ws, cr)` → `{entry, text, hash}`；若 `entry.merge-commits` 已含相同 sha → 幂等 `ok(MERGE_COMMIT_DUP)` noop 返回。
- 定位条目 `merge-commits:` 块（无则在条目内创建该键），块尾按缩进插入三行；`casWrite(backlogPath, hash, newText)`。
- 去重键 = sha；保序追加（不排序，保留合并时间序）。写后 `auditLog`。不改 status。

## 验收条件

1. 新 sha 追加 → 条目 `merge-commits[]` 出现 `{repo,trunk,sha}` 三字段，退出 0。
2. 重复 sha 再执行 → 幂等，`merge-commits[]` 条目数不增，退出 0（或专用幂等码）。
3. 非法前置态调用 → `ILLEGAL_LEDGER_STATE`，backlog 无变化。

## 完成标志

子命令可用，TASK-05 对应用例（追加/去重）通过，lint 零报错。
