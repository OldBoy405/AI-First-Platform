---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-049-TASK-11
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: multica — drift 读/写 API（overview / findings / PATCH CAS）
slug: multica-drift-api
status: pending
estimate: 10h
depends-on: [CR-2026-049-TASK-04, CR-2026-049-TASK-10]
created: 2026-08-20T20:59:46+08:00
---

# TASK-11 — multica：drift 读/写 API（overview / findings / PATCH CAS）

## 1. 任务描述

实现 `GET /api/drift/overview`（六态健康 + 计数 + 解决时延）、`GET /api/drift/findings`（keyset 分页 + 过滤）、`PATCH /api/drift/findings/{id}`（`from_status→to_status` CAS 状态矩阵）。所有端点以 auth workspace 为第一条件，跨 workspace id 恒 404（SDD §3.6/§4.2，TD-B7）。

## 2. 涉及文件 / 模块

- `server/internal/drift/overview.go`（health 判定纯函数）
- `server/internal/drift/finding_repo.go`（keyset 查询 + CAS）
- `server/internal/handler/drift.go` + `server/cmd/server/router.go`
- 测试：health 六态表测、keyset 分页、PATCH 矩阵与并发

## 3. 实现要点

- health：无平台 repo 配置=`not_configured`；有配置无成功=`uninitialized`；最新 plan FAILED=`failed`；最新成功 >2h 或 `config_rev` 不匹配或 cursor 未覆盖全部 repo=`stale`；否则 `ok`；`ok && unresolved=0` → “无漂移”。
- 计数含 `open|acknowledged`；`resolve_latency_ms` 只取 resolved 非空 `resolved_at-found_at` 的 P50/P90，空样本 `null`。
- keyset：排序 `(status_rank, found_at DESC, id DESC)`，rank=open0/acknowledged1/resolved2/wontfix3；cursor=base64url JSON `{rank,found_at,id}`，schema+长度校验。
- PATCH 单 SQL CAS：`WHERE id=$id AND workspace_id=$ws AND status=$from`；零行重读区分 404/409；允许 open→{acknowledged,resolved,wontfix}、acknowledged→{resolved,wontfix}；同状态 200 幂等；进 resolved 写 `resolved_at=now()`，wontfix 保持 NULL。
- 错误 envelope 与 DTO 严格按 SDD §3.6/§3.7。

## 4. 验收条件

1. health 六态判定表测通过（含 config_rev 漂移与 cursor 缺仓）。
2. keyset 分页稳定：新增 finding 不导致重页/漏页；过滤 status/kind/repository_id 正确。
3. PATCH 矩阵：合法流转、同状态幂等、非法流转 409、并发 CAS 仅一个成功、跨 workspace id 404、resolved_at 语义正确。

## 5. 完成标志

`go test ./server/internal/drift/... ./server/internal/handler/...` 全绿。

## 6. 接口契约

- 消费：TASK-04 表与 389 keyset 索引；TASK-10 的 result v1（health 判定输入）。
- 产出：
  - `drift.Overview(ctx, workspaceID) (*OverviewDTO, error)`；`drift.ListFindings(...) (*FindingsPage, error)`；`drift.PatchStatus(...) (*FindingDTO, error)`（错误：ErrNotFound/ErrStateConflict）。
  - 端点 DTO/错误码（供 TASK-12 前端 zod schema 消费）。
