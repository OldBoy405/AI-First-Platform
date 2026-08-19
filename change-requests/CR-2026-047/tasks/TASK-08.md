---
id: CR-2026-047-TASK-08
type: TASK
cr-ref: CR-2026-047
plan-ref: "change-requests/CR-2026-047/plan.md"
sdd-ref: "change-requests/CR-2026-047/sdd.md"
title: 读 API 六个端点 + 受保护路由 + core schema/client
slug: maturity-read-api
status: pending
estimate: 16h
depends-on: ["CR-2026-047-TASK-01", "CR-2026-047-TASK-02", "CR-2026-047-TASK-06"]
created: 2026-08-20T01:29:30+08:00
---

# TASK-08 读 API + 路由 + core schema/client

## 任务描述

实现 SDD §3 全部端点：`GET /api/maturity/overall|token-trend|rankings|suggestions|suggestions/history|config`。全部读已存 snapshot/envelope，禁止重算历史分数；注册进 router 的 Auth+RequireWorkspaceMember 组。前端可消费的 zod schema 与 client 方法同步落地。

## 涉及文件 / 模块

- `server/internal/maturity/api.go`（新建：响应类型，含 `MaturityReport`）
- `server/internal/service/maturity.go`（新建：读服务）
- `server/internal/handler/maturity.go`（新建：参数校验/响应编码）
- `server/cmd/server/router.go`（注册 6 条路由，位置靠近既有 `/api/dashboard` 受保护组，禁止进 public `/api/config` 区）
- `server/pkg/db/queries/maturity.sql`（追加：`GetMaturitySnapshot`、`ListMaturitySnapshots`、`MaturityReportHistory`、`MaturityReportLatest`）
- `packages/core/api/schemas.ts`（追加 zod）、`packages/core` client（追加 6 个方法、query keys 含 workspaceId）

## 实现要点

- sqlc 读：`GetMaturitySnapshot(wsID, bucket_date, scope, scope_id)`；`ListMaturitySnapshots(wsID, scope, scope_id, from, to, limit)`（378 索引）；`MaturityReportHistory(projectID, schema, cursor, limit)`（379 索引 keyset `project_id,completed_at DESC,id DESC`）；`MaturityReportLatest(projectID, schema)`。
- 服务签名：
  - `func (s *MaturityService) Overall(ctx, wsID string, date *string) (*maturity.MaturityOverallResponse, error)`
  - `func (s *MaturityService) TokenTrend(ctx, wsID string, req maturity.TokenTrendQuery) (*maturity.TokenTrendResponse, error)`
  - `func (s *MaturityService) Rankings(ctx, wsID string, date *string, metric string, limit int, cursor *string) (*maturity.ProjectRankingsResponse, error)`
  - `func (s *MaturityService) Suggestions(ctx, wsID string) (*maturity.SuggestionResponse, error)`
  - `func (s *MaturityService) SuggestionHistory(ctx, wsID string, limit int, cursor *string) (*maturity.SuggestionHistoryResponse, error)`
  - `func (s *MaturityService) Config(ctx, wsID string) (*maturity.MaturityConfigResponse, error)`
- `maturity.MaturityReport` 字段与 §3.5 完全一致（report_key/week/generated_at/relative_path/markdown/content_sha256/source_task_id/chat_session_id/config_revs）。
- 错误语义：401/403 由中间件；`invalid_query`（日期/范围/维度）、`unsupported_scope`（rankings 非 project）、`unsupported_user_dimension`（trend user 非 self）均 400 + `ApiError{error,message,request_id}`；空数据 200 + 结构化 empty。`metric=total` 且 scores 空 → item `value=null,data_status='unavailable'`。观察期 `total_score=null`、dimension.score=null。user snapshot 行不暴露 score。history 同 `report_key` 取 completed_at 最新且 SHA 有效一条。
- model 维度走 TASK-04 `MaturityModelCostRows`：`cost_status` 计算 = 全 authoritative / mixed（部分 authoritative 其余已覆盖价目）/ estimated（无 authoritative 但全可估）/ unavailable（存在未知模型 uncosted Token）。
- zod：6 响应 schema + 枚举 fallback（未知枚举值不炸 `parseWithFallback`）；client 方法命名 `getMaturityOverall/getMaturityTokenTrend/getMaturityRankings/getMaturitySuggestions/getMaturitySuggestionHistory/getMaturityConfig`。

## 验收条件

1. handler/service 测试：401 无凭证、403 非成员、rankings `scope=user` 400、trend `dimension=user&dimension_id=<他人>` 400、`dimension_id=self` 200 且响应不含他人 user id、invalid range 400。
2. 观察期 fixture：overall `total_score=null` 且 dimensions 全 null、raw 正常；empty workspace 200 empty。
3. history：同 report_key 两条取最新；cursor 翻页不重不漏；`EXPLAIN` 命中 379。
4. zod malformed fixtures：缺字段/错误枚举/新增字段均不抛异常。

## 完成标志

service/handler/core 三侧测试全绿；router 单测断言 6 路由在受保护组（middleware 链含 workspace member 校验）。

## 接口契约

- 消费：TASK-01 `GeneratedConfig()/GeneratedConfigRev()/GeneratedPriceMap()`；TASK-02 表结构；TASK-04 `MaturityModelCostRows`；TASK-06 rollup 写语义（不调用其函数）。
- 产出（供 TASK-09 前端、TASK-10 周报）：
  - `maturity` 包：`MaturityOverallResponse`、`TokenTrendQuery/TokenTrendResponse`、`ProjectRankingsResponse`、`SuggestionResponse/SuggestionHistoryResponse`、`MaturityConfigResponse`、`MaturityReport`、`ApiError`、`Observation`
  - `*MaturityService` 六个方法（签名见上）
  - `packages/core`：6 个 zod schema + 6 个 client 方法
