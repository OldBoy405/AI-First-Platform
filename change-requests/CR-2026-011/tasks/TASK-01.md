---
id: CR-2026-011-TASK-01
type: TASK
cr-ref: CR-2026-011
plan-ref: "change-requests/CR-2026-011/plan.md"
sdd-ref: "change-requests/CR-2026-011/sdd.md"
title: migration 161：pipeline 两表 + agent_task_queue B4 两列 + retry 克隆清单
slug: migration-pipeline-tables
status: done
estimate: 4h
depends-on: []
assignee: ""
created: "2026-08-02T12:40:00+08:00"
---

## 任务描述
落地 SDD §3：唯一 DB 迁移（编号 161），建 `pipeline_run` / `pipeline_node_run` 两表 +
`agent_task_queue` 增 `cr_id` / `pipeline_node_run_id` 两列。全 CR 唯一硬前置。

## 涉及文件
- `server/migrations/161_aifirst_pipeline_runs.up.sql`（+down，对称回滚）：
  ① pipeline_run（P0 §3.4 原样：pipeline_id/cr_id/issue_id/status 5 值 CHECK/inputs/
  execution_context/started_by）；② pipeline_node_run（P0 §3.4 + **增补 `detail JSONB
  NOT NULL DEFAULT '{}'`** 存 review 明细；UNIQUE(run_id,node_id,attempt)）；
  ③ ALTER agent_task_queue 两列 + `atq_cr_id_idx` 部分索引（P0 §2.2 原样，
  pipeline_node_run_id 带 `ON DELETE SET NULL`）
- `server/pkg/db/queries/agent.sql`（:239）：`CreateRetryTask` 的 INSERT…SELECT 显式列清单
  **补 cr_id / pipeline_node_run_id 两列**（不补则重试任务静默丢归因）+ `make sqlc`
- `CUSTOM.md`：登记 161 fork 迁移（沿 158 条目模式，即认领编号）

## 实现要点
- 编号 161：migrations_lint_test.go 强制 >148 且唯一；与并行 CR 撞号时合并序重号。
- **claim 谓词（agent.sql:350-388）不改**：新列不参与 NOT EXISTS 串行化与"四 FK 全空"
  互斥类判定——本期两列由回调后置写入，claim 时恒 NULL（SDD §3 声明）。
- down 迁移先 DROP 列（依赖 FK）再 DROP 表，顺序验证。
- 单测：migration up/down 往返；存量任务两列 NULL；retry 克隆保留 cr_id（造一条带 cr_id 的
  失败任务→触发重试→SELECT 断言）；`pipeline_node_run` 删除行后队列行 SET NULL 生效。
