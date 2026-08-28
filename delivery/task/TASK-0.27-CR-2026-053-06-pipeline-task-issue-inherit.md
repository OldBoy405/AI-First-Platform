---
spec-id: ai-first-platform
version: "0.27"
id: CR-2026-053-TASK-06
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 修改 CreatePipelineTask SQL 继承 issue_id/project_id
slug: pipeline-task-issue-inherit
status: pending
estimate: 2h
depends-on: []
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

修改 `server/pkg/db/queries/agent.sql` 中 `CreatePipelineTask`：
- INSERT 列追加 `issue_id` 和 `project_id`
- 值在 SQL 内从来源 task 行 `s.issue_id`/`s.project_id` 直接拷贝
- 追加守卫 `s.issue_id IS NOT NULL`
- 运行 `make sqlc` 重新生成

## 涉及文件 / 模块

- `server/pkg/db/queries/agent.sql`
- `server/pkg/db/generated/` (make sqlc 生成物)

## 实现要点

参考 SDD §2.3 和 §4.4 路径 1:
- SQL 内从来源 task 行 `SELECT s.issue_id, s.project_id`
- `s.issue_id IS NOT NULL` 守卫：来源 task 无 issue_id 时 INSERT 0 行
- `PipelineTaskSpec` 不新增任何 Issue/Project 字段
- 原子拒绝机制：`pgx.ErrNoRows` → `GetActivePipelineTask` 复查 → `ErrRunnerAttributionInvalid`

## 验收条件

1. `make sqlc` 成功生成 CreatePipelineTask 生成物
2. `go test ./server/pkg/db/... -run TestCreatePipelineTaskIssueInherit` 通过（负向：来源 task `issue_id IS NULL` 时返回 `ErrNoRows` 且无新增行；正向：新行 `issue_id`/`project_id` 与来源行相等）
3. AC-B10 覆盖测试通过

## 完成标志

- agent.sql 修改已 commit
- sqlc 生成物更新已 commit
- 单元测试通过

## 接口契约

**消费**:
- 来源 task 的 `issue_id`/`project_id`

**产出**:
- 新 pipeline task 行含 `issue_id`/`project_id` 继承
