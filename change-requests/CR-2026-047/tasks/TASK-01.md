---
id: CR-2026-047-TASK-01
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: E1 配置声明 schema + 零依赖生成器
slug: maturity-config-schema-generator
status: pending
estimate: 12h
depends-on: []
created: 2026-08-20T01:26:00+08:00
---

# TASK-01 E1 配置声明 schema + 零依赖生成器

## 任务描述

建立 CR-A 全部口径的唯一声明源 `maturity-config.yaml`（knowledge-base 本仓）与零依赖生成器，把声明编译为 multica 内 committed 只读 Go 副本 `server/internal/maturity/config_gen.go`。同时在本 TASK 定义全部纯类型（`server/internal/maturity/schema.go`），供 TASK-03/04/05/06/08 消费。阈值数值以 `docs/product/P3-组织智能设计.md` 附录建议值为准；文档未给值时采用保守初始值并在文件头注释“观察期占位，CR-D 校准”（`calibration_status='observing'` 期间 scores 恒为 `{}`，数值不影响计分）。SDD §2.4。

## 涉及文件 / 模块

- knowledge-base：`maturity-config.yaml`（新建）、可选 `model-prices.yaml`
- multica：`server/internal/maturity/schema.go`（新建，纯类型+校验）、`server/internal/maturity/gen/generate-config.mjs`（新建，零依赖 Node）、`server/internal/maturity/config_gen.go`（生成，勿手改）

## 实现要点

- schema.go 类型（本 TASK 拥有，下游引用）：`MetricKey`（8 常量：`token_intensity`/`ai_penetration`/`cr_throughput_per_capita`/`project_collab_scale`/`project_active_rate`/`prototype_direct_rate`/`team_agent_depth`/`process_completion_rate`）、`DimensionKey`（AIF/SII/OFI/EPC/ACM）、`GovernanceMetricKey`（6 常量）、`DataStatus`（ready/empty/unavailable/not_applicable）、`MetricValue{Value,Numerator,Denominator *float64; Unit string; DataStatus; Reason string; Attribution *Attribution}`、`Attribution{AttributedCount,UnattributedCount int64; Coverage *float64}`、`Headline{ActiveMembers,TotalTokens int64; CostUSD *float64; CostStatus string}`、`SnapshotMetricsV1`、`SnapshotScoresV1`、`ConfigV1`、`MetricConfig{Weight,Floor,Target float64}`、`PriceMap{Models map[string]ModelPrice}`、`ModelPrice{InputUSDPer1M,OutputUSDPer1M,CacheReadUSDPer1M,CacheWriteUSDPer1M float64}`、`ValidateConfig(c ConfigV1) error`。JSON tag 与 SDD §2.2/§2.4 完全一致。
- 生成器硬校验（SDD §2.4）：8 key 齐全且无未知 key；`0<weight<=1`；`sum(weights)=1`（1e-9 容差）；`target>floor`；`observation_weeks=4`；`calibration_status∈{observing,calibrated}`；读取先 `\r\n→\n`；解析不到必填块 hard fail（禁止静默降级为空）；`--check` 重生成后字节 diff 非零退出；`config_rev`=`git -C <source-repo> rev-parse HEAD`，源文件 dirty/untracked 时拒绝。照抄先例 `server/internal/governance/gen/generate-transitions.mjs` 的 CRLF/结构匹配/生成头模式。

## 验收条件

1. `ValidateConfig` 对缺 key、未知 key、权重和≠1、target≤floor、非法 observation_weeks/calibration_status 均返回错误；对合法声明返回 nil。
2. 生成器 fixture：LF 与 CRLF 输入产出字节相同；缺块输入非零退出且 stderr 指明块名；`--check` 在生成产物过期时非零退出、一致时 0；dirty source 拒绝；生成文件头含 40-hex 源 HEAD SHA。
3. `config_gen.go` 内容与声明逐字段一致（`GeneratedConfig()` 断言 8 项 metric 配置齐全）。

## 完成标志

生成器 Node 单测与 `--check` CLI fixture 全绿；`go test ./internal/maturity/` 通过；`config_gen.go` 提交进 multica 且文件头 SHA 与 knowledge-base HEAD 一致。

## 接口契约

- 产出（供 TASK-03/04/05/06/08/10）：
  - `package maturity`（`server/internal/maturity`）
  - `func GeneratedConfig() ConfigV1`
  - `func GeneratedConfigRev() string` // 40-hex
  - `func GeneratedPriceMap() (PriceMap, bool)` // bool=false 表示无 model-prices.yaml
  - 上述 schema.go 全部类型与常量
- 消费：knowledge-base `maturity-config.yaml`、`model-prices.yaml`（同仓文件，非代码接口）。
