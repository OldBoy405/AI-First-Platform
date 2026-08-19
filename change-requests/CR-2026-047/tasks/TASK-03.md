---
id: CR-2026-047-TASK-03
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: 计分纯函数与观察期判定
slug: scoring-pure-functions
status: pending
estimate: 8h
depends-on: ["CR-2026-047-TASK-01"]
created: 2026-08-20T01:27:00+08:00
---

# TASK-03 计分纯函数与观察期判定

## 任务描述

实现 SDD §4.4 的计分公式与观察期判定，纯函数、不访问 DB，table-driven 测试钉死边界。观察期/未校准时 `scores={}`；本模块不含任何 DB/SQL。

## 涉及文件 / 模块

- `server/internal/maturity/score.go`（新建）
- `server/internal/maturity/score_test.go`（新建）

## 实现要点

- `MetricScore(x float64, c MetricConfig) float64`：`clamp(100*(x-c.Floor)/(c.Target-c.Floor), 0, 100)`；`x` 为 NaN 时返回 0。
- `DimensionScores(m map[MetricKey]MetricValue, cfg ConfigV1) (map[DimensionKey]float64, error)`：每维 `Σ(score*weight)/Σ(weight)`（只计该维 metric 中 `data_status` 为 ready 且 Value 非 nil 的项；该维全部非 ready 时该维分数为 0，不报错）。
- `TotalScore(m map[MetricKey]MetricValue, cfg ConfigV1) (float64, error)`：全局 `Σ(score*weight)`，权重和=1 已由 `ValidateConfig` 保证；缺 metric key 返回错误。
- `BuildScores(m map[MetricKey]MetricValue, cfg ConfigV1) (SnapshotScoresV1, error)`：产出 `{Schema:"ai-first.maturity-scores/v1", MetricScores, DimensionScores, TotalScore}`；所有 key 齐全（8+5+1），任一 0..100。
- `ObservationActive(firstBucket time.Time, now time.Time, cfg ConfigV1) bool`：`now.Sub(firstBucket) < 28*24h || cfg.CalibrationStatus != "calibrated"`；调用方在 true 时写 `scores={}`、不调用 BuildScores。

## 验收条件

1. table 测试：floor=0/target=10/x=5→50；x<floor→0；x>target→100；x 恰在 floor/target 边界；浮点 1e-9 边界不越界。
2. 维度加权：两 metric 权重 0.5/0.5 分数 20/80→50；权重 0.8/0.2→32；一项 `data_status='unavailable'` 时仅以 ready 项归一。
3. `BuildScores` 缺任一 MetricKey 返回错误；正常输入 8+5+1 键齐全且区间 0..100。
4. `ObservationActive`：第 27 天+observing=true；第 28 天+calibrated=false；第 28 天+observing=true。

## 完成标志

`go test ./internal/maturity/ -run Score` 全绿；无 lint 报错。

## 接口契约

- 消费（TASK-01）：`maturity.ConfigV1`、`MetricConfig`、`MetricKey`、`DimensionKey`、`MetricValue`、`SnapshotScoresV1`。
- 产出（供 TASK-06）：
  - `func MetricScore(x float64, c maturity.MetricConfig) float64`
  - `func DimensionScores(m map[maturity.MetricKey]maturity.MetricValue, cfg maturity.ConfigV1) (map[maturity.DimensionKey]float64, error)`
  - `func TotalScore(m map[maturity.MetricKey]maturity.MetricValue, cfg maturity.ConfigV1) (float64, error)`
  - `func BuildScores(m map[maturity.MetricKey]maturity.MetricValue, cfg maturity.ConfigV1) (maturity.SnapshotScoresV1, error)`
  - `func ObservationActive(firstBucket time.Time, now time.Time, cfg maturity.ConfigV1) bool`
