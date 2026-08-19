---
id: CR-2026-047-TASK-06
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: 快照 rollup 编排（事务、advisory lock、观察期、JSON 校验）
slug: snapshot-rollup-transaction
status: pending
estimate: 12h
depends-on: ["CR-2026-047-TASK-01", "CR-2026-047-TASK-02", "CR-2026-047-TASK-03", "CR-2026-047-TASK-04", "CR-2026-047-TASK-05"]
created: 2026-08-20T01:28:30+08:00
---

# TASK-06 快照 rollup 编排

## 任务描述

把 TASK-04/05 查询、TASK-03 计分、TASK-01 配置编排为 SDD §4.5 的写路径：global handler 遍历 workspace（稳定 ID 序），每 workspace 独立事务 + advisory lock + 水位 no-op，固化为 `maturity_snapshot` 三 scope 行。历史行只插不改。

## 涉及文件 / 模块

- `server/internal/service/maturity_rollup.go`（新建；直接复用 `*pgxpool.Pool` 启动每-workspace事务）
- `server/pkg/db/queries/maturity.sql`（追加：`MaturityWorkspaces`、`MaturitySnapshotMaxBucket`、`MaturitySnapshotInsert`）
- `server/internal/service/maturity_test.go`（rollup 并发/故障用例）

## 实现要点

- sqlc 追加：`MaturityWorkspaces :many`=`SELECT id FROM workspace ORDER BY id`（现有 workspace 表无 active/deleted 状态，故所有存在行都纳入，稳定 UUID 序）；`MaturitySnapshotMaxBucket :one`（`MAX(bucket_date)`，workspace 限定）；`MaturitySnapshotInsert :exec`（`INSERT ... ON CONFLICT (workspace_id,bucket_date,scope,scope_id) DO NOTHING`）。
- 编排签名钉死：`func RollupMaturitySnapshot(ctx context.Context, pool *pgxpool.Pool, planTime time.Time) (int64, error)` → 列 workspace 后逐个调 `RollupMaturityWorkspace`；`func RollupMaturityWorkspace(ctx context.Context, pool *pgxpool.Pool, workspaceID pgtype.UUID, planTime time.Time) (int64, error)`。不新建单实现 DB 抽象；`*pgxpool.Pool` 用于 `Begin(ctx)`，事务内 `qtx:=db.New(tx)`。
- `target = previousLocalDate(planTime, Asia/Shanghai)`（`planTime.In(loc).AddDate(0,0,-1)` 的日期）；时间窗 `[from_utc,to_utc)` 左闭右开。
- 事务内先 `pg_try_advisory_xact_lock(hashtextextended('maturity_snapshot:'||wsID,0))`，拿不到返回 retryable 错误；`MAX(bucket_date)>=target` 则 no-op COMMIT。
- 指标计算：org/project 计算 SDD §4.2 全 8 项与治理 6 字段；user scope 只写 Token/任务趋势类（`token_intensity` 系与 `team_agent_depth` 系），非适用键写 `not_applicable`、`scores={}`。覆盖不足 95% 时 user breakdown/渗透/协作用人数标 `unavailable`（org Token 总量仍 ready）。
- 治理 6 字段恒有键；`traceability_complete_rate` 恒 `value=null,data_status='unavailable',reason='trace_channel_pending_cr_c'`；空分母 `value=null,data_status='empty'`；`approval_latency` 无样本 empty；用 `percentile_cont` 语义在 Go 内按样本排序插值 P50/P90（样本≤2 时线性插值取中值，实施写清）。
- `ValidateSnapshotMetrics(m)`：8 键齐全、governance 6 键齐全、config_rev 匹配 `GeneratedConfigRev()`。
- `observation_active` 用 TASK-03 `ObservationActive`（first_bucket 取该 workspace 最早 org 行，无则用 target 当日）；true 时 `scores={}`，false 时 `BuildScores`。
- 全 workspace 遍历中前序成功、后序失败：任务返回错误（重试时前序水位 no-op 收敛）；不做跨租户大事务。

## 验收条件

1. 同 workspace 双 goroutine 并发同 target：恰好一组 org/user/project 行（唯一键兜底 + advisory lock 不串写）。
2. 故障注入：JSON 校验失败 → 该 workspace 全部行不存在（整事务回滚）；其他 workspace 行已提交。
3. 重跑同 target：行数不变、内容字节不变（历史不可变）；观察期 fixture 写 `scores={}`，calibrated fixture 写满 scores。
4. 覆盖不足 95% fixture：AI 渗透率 `unavailable`、org Token 总量 ready 且 attribution 字段正确。

## 完成标志

rollup 并发/故障/观察期 fixture 全绿；`go vet` 零告警。

## 接口契约

- 消费：TASK-01 `maturity.ConfigV1/GeneratedConfig()/MetricKey...`；TASK-03 四个计分函数；TASK-04/05 全部 `db.Queries.Maturity*`；TASK-02 表结构。
- 产出（供 TASK-07 调度、TASK-08 读侧语义）：
  - `func RollupMaturitySnapshot(ctx context.Context, pool *pgxpool.Pool, planTime time.Time) (int64, error)`
  - `func RollupMaturityWorkspace(ctx context.Context, pool *pgxpool.Pool, workspaceID pgtype.UUID, planTime time.Time) (int64, error)`
  - `func ValidateSnapshotMetrics(m maturity.SnapshotMetricsV1) error`
- 本 TASK 不定义 `DBTX` 或 `MaturityRollupFunc`；scheduler 直接消费上述函数，避免一实现接口/别名漂移。
