---
spec-id: ai-first-platform
version: "0.21"
id: CR-2026-047-TASK-07
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: scheduler job maturity_snapshot（hook 补偿 + retry 合并）
slug: scheduler-maturity-snapshot-job
status: pending
estimate: 12h
depends-on: ["CR-2026-047-TASK-06"]
created: 2026-08-20T01:29:00+08:00
---

# TASK-07 scheduler job maturity_snapshot

## 任务描述

注册 `Name='maturity_snapshot'` 的每日 00:30 Asia/Shanghai job。因 `PlansForScope` 非 nil 时 `CatchUpMode/CatchUpWindow` 被 scheduler 忽略，补偿必须全部实现在 hook 内（SDD §3.7）。handler 每 plan 只写前一自然日一个 target，不二次扩窗。

## 涉及文件 / 模块

- `server/internal/scheduler/jobs_maturity.go`（新建）
- `server/internal/scheduler/jobs_maturity_test.go`（新建，fixed clock）
- `server/pkg/db/queries/maturity.sql`（追加：`MaturityRetryablePlans`）
- `server/cmd/server/main.go`：在 `TaskUsageHourlyJob(pool)` 与 `AutopilotScheduleDispatchJob(...)` 注册区新增 `schedulerMgr.Register(scheduler.MaturitySnapshotJob(pool))`

## 实现要点

- sqlc：`MaturityRetryablePlans :many` — `SELECT plan_time FROM sys_cron_executions WHERE job_name='maturity_snapshot' AND scope_kind='global' AND scope_id='global' AND status='FAILED' AND attempt<max_attempts AND next_retry_at<=$1 AND plan_time>$2 ORDER BY plan_time ASC LIMIT 7`。
- 构造：`func MaturitySnapshotJob(pool *pgxpool.Pool) JobSpec`，函数内 `queries:=db.New(pool)`。`Name='maturity_snapshot'`、`Cadence:0`、`PlansForScope=maturityPlansForScope(queries)`、`MaxPlansPerTick:7`、`CatchUpMode:CatchUpEveryPlan`、`CatchUpWindow:7*24h`（仅声明意图，注释写明不参与规划）、`Scopes:StaticScopes(ScopeGlobal)`；`RunTimeout/StaleTimeout/HeartbeatInterval/MaxAttempts/RetryBackoff/AllowStaleReentry` 照抄 `AutopilotScheduleDispatchJob`。
- hook 算法：① 查 `MaturityRetryablePlans(now, now-7d)` 得 retrySet（oldest-first，≤7），断言 `latest.RetryEligible(now)` 时 `latest.PlanTime∈retrySet`（测试钉死）；② `after := latest.PlanTime`；无执行记录时 `after := now-24h`（首启只产生最近一个已到期 plan）；有记录时 `after = max(after, now-7d)`；③ `occ := NextOccurrencesUTC('30 0 * * *','Asia/Shanghai',after,now)`；④ retrySet ∪ occ 去重、oldest-first、截 7 返回。不做 latest-only collapse。
- handler：`target=planTime.In(Asia/Shanghai).AddDate(0,0,-1)` 日期；直接调 `service.RollupMaturitySnapshot(ctx,pool,in.PlanTime)`；`RowsAffected` 写回；`Result` 写 `{"bucket_date":"...","workspaces":N}`（小 payload）。不定义 `MaturityRollupFunc` 别名。

## 验收条件

1. fixed clock：首次启动（无任何行）始终返回 `(now-24h,now]` 内最近一个已到期 plan；Asia/Shanghai 00:15 返回前一日 00:30，00:31 返回当日 00:30，均恰好一条。
2. 停机 3 天：返回 3 个 plan，oldest-first；停机 8 天：只返回窗口内最近 7 日 plan，且 `MaxPlansPerTick=7` 截断生效。
3. FAILED 重试：最新 plan FAILED 且 retry-eligible → 原 PlanTime 在返回集中；较老 FAILED + 较新 SUCCESS 并存 → 较老 FAILED 仍在返回集（不被 latest 逻辑搁浅）。
4. handler：plan_time=2026-08-20T00:30+08 → target bucket_date=2026-08-19；同 plan 重跑 rollup no-op 不新增行。
5. 断言测试：`PlansForScope!=nil` 时构造的 JobSpec 不改写 `CatchUpMode/CatchUpWindow` 行为（以 scheduler 单测确认两字段不参与 hook 规划）。

## 完成标志

`go test ./internal/scheduler/ -run Maturity` 全绿；job 在 registry 可见且 `validate()` 通过。

## 接口契约

- 消费（TASK-06）：`service.RollupMaturitySnapshot(ctx context.Context, pool *pgxpool.Pool, planTime time.Time) (int64, error)`；scheduler 既有 `JobSpec/LatestPlanInfo/StaticScopes/ScopeGlobal` 与 `service.NextOccurrencesUTC(cronExpr,timezone string,after,until time.Time) ([]time.Time,error)`。
- 产出（供 TASK-11 集成验证）：
  - `func MaturitySnapshotJob(pool *pgxpool.Pool) JobSpec`
  - `func maturityPlansForScope(queries *db.Queries) func(ctx context.Context, scope Scope, now time.Time, latest LatestPlanInfo) ([]time.Time, error)`
  - `func (q *db.Queries) MaturityRetryablePlans(ctx context.Context, arg db.MaturityRetryablePlansParams) ([]pgtype.Timestamptz, error)`；Params=`Now/WindowStart pgtype.Timestamptz`。
  - 注册调用：`schedulerMgr.Register(scheduler.MaturitySnapshotJob(pool))`（`server/cmd/server/main.go`）。
