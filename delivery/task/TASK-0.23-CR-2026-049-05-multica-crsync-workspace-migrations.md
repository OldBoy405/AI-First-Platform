---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-049-TASK-05
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: multica — cr_sync_event workspace 迁移 390-397 与全 seam 切换
slug: multica-crsync-workspace-migrations
status: pending
estimate: 16h
depends-on: []
created: 2026-08-20T20:59:46+08:00
---

# TASK-05 — multica：`cr_sync_event` workspace 迁移 390–397 与全 seam 切换

## 1. 任务描述

为 `cr_sync_event` 增加 `workspace_id`（daemon auth 注入，不信任 body），确定性回填（多归属/孤儿 preflight 硬失败），按 new-index-before-old-drop 顺序迁移 390–397，并同步切换全部受影响 seam：ingest ON CONFLICT/processed、in-process mutex、runner checkpoint join、maturity.sql 七处 join、approval latestEvidence/幂等索引（SDD §2.2/§2.4/§2.5，TD-B4）。

## 2. 涉及文件 / 模块

- `server/migrations/390~397_*.up/down.sql`（含 390 preflight + 396/397 approval 幂等索引切换）
- `server/internal/governance/crsync.go`、`approval.go`、`runner.go`
- `server/pkg/db/queries/maturity.sql`（+ sqlc 重新生成）
- 测试：迁移 PG 测试、crsync/approval/runner 测试 fixture、静态 contract grep 测试

## 3. 实现要点

- 390：preflight（`count(DISTINCT workspace_id)<>1` 的 `cr_id` 集合为空）→ 标量子查询回填 → 零 NULL 断言 → `SET NOT NULL`。
- 391/392/393：新 workspace unique、trace spec 表达式索引、workspace unprocessed 索引（均 CONCURRENTLY）先建；394/395 再删旧 unique/unprocessed；396/397 approval 幂等索引同序。
- 代码切换：`lockKey(workspaceID, crID)`；`INSERT ... ON CONFLICT (workspace_id, cr_id, commit_sha, event_kind)`；processed UPDATE 带 workspace；`latestEvidence` 直接 `cse.workspace_id=$1`；maturity 全部 `e.workspace_id=cr.workspace_id`；approval conflict/idempotent select 带 workspace。
- 静态 contract 测试：禁止出现不带 workspace 的 `cr_sync_event` conflict/join。

## 4. 验收条件

1. 单 workspace 数据迁移成功且全行非 NULL；构造孤儿行与同名多归属行 → 390 非零失败。
2. 两个 workspace 同名 CR：事件各自入账，`latestEvidence`/approval 不串数据。
3. 迁移往返（up/down）干净；grep contract 测试全绿。

## 5. 完成标志

`go test ./server/internal/governance/... ./server/cmd/migrate/...` 全绿；sqlc 生成无漂移。

## 6. 接口契约

- 消费：无上游 TASK（与 TASK-04 并行）。
- 产出：
  - `cr_sync_event` 唯一键 `(workspace_id, cr_id, commit_sha, event_kind)`、trace 表达式索引、workspace unprocessed 索引（供 TASK-06/07）。
  - `SyncService.lockKey(workspaceID, crID)`；带 workspace 的 ingest/processed/latestEvidence/join 语义（供 TASK-06）。
