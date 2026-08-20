---
id: CR-2026-049-TASK-04
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: multica — drift_finding 迁移 385-389
slug: multica-drift-finding-migrations
status: pending
estimate: 8h
depends-on: []
created: 2026-08-20T20:59:46+08:00
---

# TASK-04 — multica：drift_finding 迁移 385–389

## 1. 任务描述

新增 `drift_finding` 表与索引迁移（SDD §2.1/§2.3）：表文件无 inline PK/FK/index；id 唯一索引与 `USING INDEX` 主键分文件；dedup 与 keyset 索引独立 `CONCURRENTLY`；E5 finding 的 evidence 完整性由 DB CHECK 兜底。所有并发索引在 `cmd/migrate` invalid-index cleanup registry 登记。

## 2. 涉及文件 / 模块

- `server/migrations/385_drift_finding.up/down.sql`
- `server/migrations/386_drift_finding_id_uidx.up/down.sql`
- `server/migrations/387_drift_finding_primary_key.up/down.sql`
- `server/migrations/388_drift_finding_dedup_idx.up/down.sql`
- `server/migrations/389_drift_finding_keyset.up/down.sql`
- `server/cmd/migrate` concurrent-index cleanup registry 及对应 registry 测试

## 3. 实现要点

- 列/CHECK 严格按 SDD §2.1（kind/severity/status 枚举、E5 evidence 必填 CHECK、默认值、无 FK）。
- 388 dedup：`(workspace_id, repository_id, kind, COALESCE(spec_id,''), (evidence->>'commit_sha'))`；389 keyset：`(workspace_id, status, found_at DESC, id DESC)`。
- down 顺序逆序；每文件仅一条索引语句（`USING INDEX` 文件除外）。

## 4. 验收条件

1. PG 迁移测试：up 后 `\d drift_finding` 结构/CHECK/索引齐全，down 往返干净。
2. registry 测试通过：386/388/389 均有 cleanup hook 且无孤儿登记。
3. `EXPLAIN` keyset 查询（workspace+status+found_at desc）走 389 索引。

## 5. 完成标志

`go test ./server/cmd/migrate/...` 与迁移集成测试全绿。

## 6. 接口契约

- 消费：无上游 TASK。
- 产出：
  - `drift_finding` 表结构与 dedup/keyset 索引，供 TASK-10/TASK-11 使用（INSERT `ON CONFLICT DO NOTHING`、keyset 分页）。
