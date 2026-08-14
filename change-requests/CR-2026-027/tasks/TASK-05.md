---
id: CR-2026-027-TASK-05
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: migrate-backlog 幽灵条目清理阶段 + 主工作区执行一次
slug: migrate-backlog-ghost-entry-cleanup
status: pending
estimate: 4h
depends-on: ["CR-2026-027-TASK-01"]
created: "2026-08-09T23:35:00+08:00"
---

# TASK-05 — migrate-backlog 幽灵条目清理（FR-10/D-11）

## 任务描述

扩展既有 `crctl migrate-backlog` 增加幽灵条目清理阶段（不新增子命令、不新增独立脚本），删除 `_backlog.yml` 尾部 CR-2026-024 缺 `- id:` 行的幽灵块；并在实施期对主工作区执行一次，清理 B-12 残留数据。

## 涉及文件 / 模块

- tools `skills/shared/crctl/scripts/crctl.mjs`（`cmdMigrateBacklog` 增加清理阶段）
- tools `skills/shared/crctl/scripts/test/crctl.test.mjs`
- 主工作区 `change-requests/_backlog.yml`（执行清理后随 CR 提交）

## 实现要点（SDD §3.6/§4.2）

1. 在 `cmdMigrateBacklog` 中新增幽灵块检测阶段：CRLF 归一 → 逐行解析 → 定位「无 `- id:`/`cr-id:` 归属的续行块」（列表项 map 结束后出现 indent ≥ 字段缩进且非 `- ` 开头的第一行起，到 EOF 或下一个 `  - id:` 前）
2. 删除依据：`_history.yml` 中存在同 title 的完整归档条目（`final-status` 存在）；不满足 → `GHOST_ENTRY_ORPHANED` 硬失败，不静默删除
3. 幂等：无幽灵块 → `{ migrated: false, reason: 'already-clean' }`，文件哈希不变
4. 清理后重新 parse 校验：CR-2026-017 条目的 title/summary/owners/created/updated 恢复为归档前形态
5. 实施期执行：tools worktree 提交 crctl 改动后，在主工作区运行一次 `crctl migrate-backlog`（读 `_history.yml` 归属判定），确认 `_backlog.yml` 幽灵块消失，变更随 CR-2026-027 实施提交入库

## 验收条件

1. 幽灵块删除后 `_backlog.yml` 无缺 id 条目；CR-2026-017 条目字段完整（AC-14）
2. 再次运行 → `already-clean` 且文件哈希不变（幂等）
3. history 无对应归档时 → `GHOST_ENTRY_ORPHANED` 且文件不变
4. 主工作区执行后幽灵条目实际消失（B-12 场景回归）

## 完成标志

crctl.test.mjs 幽灵清理三用例全绿（删除/幂等/orphaned）；主工作区 `_backlog.yml` 已清理并提交。

## 接口契约

- 消费：TASK-01 产出的 tools worktree；主工作区 `_history.yml`（归属判定）
- 产出：`cmdMigrateBacklog` 清理阶段（`already-clean`/`GHOST_ENTRY_ORPHANED`）；TASK-10 的 AC-14 验收基于本产出
