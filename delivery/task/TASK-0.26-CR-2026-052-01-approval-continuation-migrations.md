---
spec-id: ai-first-platform
version: "0.26"
id: CR-2026-052-TASK-01
type: TASK
cr-ref: CR-2026-052
plan-ref: "change-requests/CR-2026-052/plan.md"
sdd-ref: "change-requests/CR-2026-052/sdd.md"
title: "迁移 469/470/471：approval_continuation 唯一约束与 workspace carrier"
slug: approval-continuation-migrations
status: pending
estimate: 4h
depends-on: []
created: 2026-08-27T10:44:32+08:00
---

# TASK-01：迁移 469/470/471

## 1. 任务描述

新增三条数据库迁移（up/down 各一，遵循仓库惯例：单语句、`CONCURRENTLY`、编号顺延、down 幂等），为续跑任务提供幂等与 workspace-qualified 排队约束的数据层。对应 SDD §2.2（469）、§2.3（470/471），闭合 TD-BL-10 的 workspace authority 数据层。

## 2. 涉及文件 / 模块

- 新建 `server/migrations/469_approval_continuation_record_active_unique.up.sql`
- 新建 `server/migrations/469_approval_continuation_record_active_unique.down.sql`
- 新建 `server/migrations/470_approval_continuation_workspace_scope.up.sql`
- 新建 `server/migrations/470_approval_continuation_workspace_scope.down.sql`
- 新建 `server/migrations/471_approval_continuation_workspace_cr_pending_unique.up.sql`
- 新建 `server/migrations/471_approval_continuation_workspace_cr_pending_unique.down.sql`

## 3. 实现要点（SDD §2.2/§2.3）

**469（FR-4，record-id 五态幂等）**：
```sql
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_approval_continuation_record_active
    ON agent_task_queue (trigger_evidence_ref_id)
    WHERE trigger_evidence_kind = 'approval_continuation'
      AND status IN ('queued','deferred','dispatched','waiting_local_directory','running');
```
down：`DROP INDEX CONCURRENTLY IF EXISTS idx_approval_continuation_record_active;`

**470（TD-BL-10，nullable workspace carrier + CHECK）**：
```sql
ALTER TABLE agent_task_queue
  ADD COLUMN approval_workspace_id UUID,
  ADD CONSTRAINT agent_task_queue_approval_workspace_ck
  CHECK (trigger_evidence_kind IS DISTINCT FROM 'approval_continuation'
         OR approval_workspace_id IS NOT NULL);
```
down：同一 `ALTER TABLE` 先 `DROP CONSTRAINT agent_task_queue_approval_workspace_ck`，再 `DROP COLUMN approval_workspace_id`。nullable 列不触发表重写，无长锁。

**471（FR-6/TD-BL-10，(workspace,cr) queued/deferred 唯一）**：
```sql
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_approval_continuation_workspace_cr_pending
    ON agent_task_queue (approval_workspace_id, cr_id)
    WHERE trigger_evidence_kind = 'approval_continuation'
      AND status IN ('queued','deferred');
```
down：`DROP INDEX CONCURRENTLY IF EXISTS idx_approval_continuation_workspace_cr_pending;`

注意：470 列添加必须在 469/471 索引之前应用（471 依赖该列存在）。编号 469<470<471 顺延即满足顺序。

## 4. 验收条件

1. `make sqlc && (cd server && go build ./...)` 通过；迁移可被 embed 并在空库顺序 apply 无报错。
2. 手工或测试 apply 全部 up，再逆序 apply 全部 down，幂等无残留：`\d agent_task_queue` 不含 `approval_workspace_id` 与两条新索引；469/471 索引名在 `pg_indexes` 查询存在/消失符合预期。
3. 470 CHECK 生效：向 `approval_continuation` 行写 NULL `approval_workspace_id` 被拒；普通任务行 `approval_workspace_id` NULL 通过。

## 5. 完成标志

三条 up/down 迁移落盘；`go build ./...` 通过；up/down 幂等验证通过；与既有迁移 257/284/433/443/467 编号无冲突。

## 6. 接口契约

- **消费**：无前置 TASK。
- **产出**：`agent_task_queue.approval_workspace_id` 列（nullable，仅 continuation 必填）、`idx_approval_continuation_record_active`（469）、`idx_approval_continuation_workspace_cr_pending`（471）。下游 TASK-02 的 sqlc 查询引用本列与索引约束。
