---
id: CR-2026-049-TASK-07
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: multica — trace 读 API（spec 时间线 / spec-search）
slug: multica-trace-read-api
status: pending
estimate: 12h
depends-on: [CR-2026-049-TASK-06]
created: 2026-08-20T20:59:46+08:00
---

# TASK-07 — multica：trace 读 API（spec 时间线 / spec-search）

## 1. 任务描述

新增 governance trace 读服务与两个端点：`GET /api/cr/specs/{spec_id}/trace` 返回 FR 演进时间线（最新有效完整 snapshot 投影、`(cr,milestone)` 去重、事件赋时、baseline-imported 历史不丢）；`GET /api/cr/spec-search` 按 owner/spec 反查。owner 是 crctl free-text identity（精确匹配），不宣称等同 Multica user UUID（SDD §3.5，TD-B7）。

## 2. 涉及文件 / 模块

- `server/internal/governance/trace.go`（读服务 + 纯函数投影）
- `server/internal/handler/trace.go`（端点 + DTO + 错误 envelope）
- `server/cmd/server/router.go`（workspace 区挂载）
- 测试：投影/去重/赋时纯函数、handler 隔离、跨 workspace

## 3. 实现要点

- 查询经 `cr_sync_event` trace 表达式索引（TASK-05），按 `(occurred_at,id)` 升序；取最新有效完整 snapshot 的 `milestones` 为展示集合。
- 投影规则：事件 `cr_id→(occurred_at,id)` 映射回 milestone；无独立事件的历史条目标记 `source='baseline-imported'` 排在事件条目前；同 key 语义 hash 不同 → `trace_snapshot_conflict`；`frs` 与 `fr-chain` 统一为响应字段 `frs`。
- malformed 历史行：该 event `state='malformed', error_code='trace_payload_invalid'`，不泄漏 raw payload。
- evidence 缺失：`null/missing` 显式返回，不回退 trunk HEAD。
- spec-search：`q` 转义 ILIKE（spec_id/owner id）；owner 对 `jsonb_each(cr.owners).value->>'id'` 大小写不敏感精确匹配；keyset cursor（spec_id 字典序）；limit 1..100。
- 错误 envelope：`{"error","message","request_id"}`；成员校验用 `workspaceMember`。

## 4. 验收条件

1. 首个完整 snapshot 导入历史 milestones（含 CR-2026-001~048），后续事件赋时去重，稳定排序。
2. owner 精确匹配、spec q 过滤、跨 workspace 同名 CR 不泄漏。
3. malformed 行不泄漏 raw payload；evidence 缺失显示 missing；响应通过 Zod/JSON schema 断言。

## 5. 完成标志

`go test ./server/internal/governance/... ./server/internal/handler/...` 全绿。

## 6. 接口契约

- 消费：TASK-06 的 ledger 行与 payload envelope；TASK-05 的 trace 表达式索引。
- 产出：
  - `TraceService.SpecTimeline(ctx, workspaceID, specID string) (*SpecTimeline, error)`（DTO 按 SDD §3.5）。
  - `TraceService.SpecSearch(ctx, workspaceID, q, owner string, limit int, cursor *string) (*SpecSearchPage, error)`。
  - 端点 DTO（供 TASK-12 前端 zod schema 消费）。
