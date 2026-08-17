---
id: CR-2026-045-TASK-06
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: CreatePipelineTask sqlc 查询与归因快照
slug: create-pipeline-task-attribution-snapshot
status: pending
estimate: 5h
depends-on: []
created: 2026-08-17T20:39:31+08:00
---

# TASK-06 CreatePipelineTask sqlc 查询与归因快照

## 1. 任务描述

新增唯一 sqlc 查询 `CreatePipelineTask`，从可信 source task 原子复制完整 attribution snapshot 并写入 `cr_id`/`pipeline_node_run_id` 与 context。这是 B01 回修的最小落点——不是通用 enqueue builder，不重新分类 attribution，也不把 logical owner 当用户。补 retry 列清单合同测试锁定既有继承不变。

## 2. 涉及文件 / 模块

- `server/pkg/db/queries/agent.sql`（新增 `CreatePipelineTask`）
- `server/internal/service/task.go`（`EnqueuePipelineTask` 窄入口，复用现有 Agent/runtime readiness 校验）
- sqlc 生成物（`make sqlc` 后提交）
- `server/internal/service/task_attribution_test.go` 或既有 service 测试（新增归因快照断言）

## 3. 实现要点

- source task 是唯一 attribution 来源：必须同一 workspace 且 `source_task.agent_id=executor_agent_id`；从 source 原样复制 `originator_user_id`/`accountable_user_id`/`originator_source`/`delegated_from_task_id`/`rule_version_id`/`trigger_evidence_kind`/`trigger_evidence_ref_id`。
- executor Agent/runtime 从同 workspace active Agent 行重读；`cr_id` 必须存在于同 workspace `cr` 投影；任一 JOIN/guard 不满足则 INSERT 0 行并返回 `RUNNER_ATTRIBUTION_INVALID`。
- context、`cr_id`、`pipeline_node_run_id` 与完整 attribution snapshot 在同一 INSERT 中写入；现有 strict `originator→accountable` CHECK 机械兜底。
- 不新增 retry 分支；只增加合同测试锁定 `CreateRetryTask` 仍原样继承 attribution、`cr_id`、`pipeline_node_run_id`。

## 4. 验收条件

1. source snapshot 全字段复制断言通过；source/Agent/CR 任一跨 workspace 时 INSERT 0 行且返回 `RUNNER_ATTRIBUTION_INVALID`。
2. strict CHECK 通过（originator 非空时 accountable 必等）；retry 列清单合同测试通过。
3. `make sqlc` 生成物与查询一致，`go vet`/`go test ./internal/service/` 通过。

## 5. 完成标志

CreatePipelineTask 查询 + EnqueuePipelineTask 入口落地 + 归因/retry 测试通过 + sqlc 生成物提交。

## 6. 接口契约

- 消费：无上游 TASK。
- 产出：`TaskService.EnqueuePipelineTask(ctx, PipelineTaskSpec) (taskID, error)`，`PipelineTaskSpec` 含 `workspaceID/crID/runID/nodeID/pipelineID/attempt/prompt/sourceTaskID/executorAgentID`；TASK-07 的 Reconcile 调它入队，TASK-08 的 daemon claim 消费其写入的 `context.type=pipeline_node`。
