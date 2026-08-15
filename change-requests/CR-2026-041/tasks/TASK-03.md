---
id: CR-2026-041-TASK-03
type: TASK
cr-ref: CR-2026-041
plan-ref: "change-requests/CR-2026-041/plan.md"
sdd-ref: "change-requests/CR-2026-041/sdd.md"
title: generator 事实源修正
slug: generator-fact-source-fix
status: pending
estimate: 2h
depends-on:
  - CR-2026-041-TASK-01
created: 2026-08-15T22:05:40+08:00
---

# TASK-03 generator 事实源修正

## 1. 任务描述

修正 `writeback-traceability.mjs` 的事实源：trunk 提取删除 `|| 'master'` 回退（缺失硬失败 `TRUNK_UNKNOWN`）；清除仍声称 merge 来源为 `_backlog.yml` 的头注释、变量名与错误文案，统一为 `merge-commits.yml`。对应 FR-02。

## 2. 涉及文件 / 模块

- `skills/writeback/scripts/writeback-traceability.mjs`（唯一改动文件）

## 3. 实现要点

- `trunkOf(repo)`：返回 `null` 时不再回退 `master`，改为 `fail('TRUNK_UNKNOWN', ...)`（当前在 `for (const mc of mergeCommits)` 循环里 `mc.trunk = trunkOf(mc.repo) || 'master'`）。
- 头注释中「从 change-requests/_backlog.yml 定向提取」改为「从 change-requests/{cr}/merge-commits.yml 定向提取」。
- 变量重命名：`fromBacklog` → `fromMergeCommits`（若存在）；`STRUCTURE_MISMATCH` 文案「与 _backlog.yml 提取结果不一致」改为「与 merge-commits.yml 提取结果不一致」。
- `MERGE_COMMITS_MISSING` 相关错误文案保持指向 `merge-commits.yml`（已正确），只清残留 `_backlog.yml` 字样。
- 不改变读取行为：`merge-commits.yml` 已是事实源（TASK-08 起），本任务只做文案/变量/回退收敛，不新增永久迁移兼容。

## 4. 验收条件

1. `rg -n "_backlog|master" writeback-traceability.mjs` 仅剩历史注释说明且无 `|| 'master'` 回退；`fromBacklog` 变量已不存在。
2. 构造 dir-graph 缺 trunk 条目的 fixture，generator 以 `TRUNK_UNKNOWN` 硬失败（不静默写 master）。

## 5. 完成标志

`node writeback.test.mjs`（trunk 硬失败 + 文案扫描用例）通过。

## 6. 接口契约

- **消费**：`lib.mjs` 的 `readFile`/`fail`；TASK-01 的 trunk 提取上下文。
- **产出**：`trunkOf(repo) -> string | fail('TRUNK_UNKNOWN')`（无 `master` 回退）。
