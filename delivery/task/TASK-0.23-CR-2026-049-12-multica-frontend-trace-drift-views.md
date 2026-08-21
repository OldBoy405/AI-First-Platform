---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-049-TASK-12
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: multica — 前端：core schemas / spec trace / search / drift 面
slug: multica-frontend-trace-drift-views
status: pending
estimate: 16h
depends-on: [CR-2026-049-TASK-07, CR-2026-049-TASK-11]
created: 2026-08-20T20:59:46+08:00
---

# TASK-12 — multica 前端：core schemas / spec trace / search / drift 面

## 1. 任务描述

`packages/core` 新增四个响应 Zod schema + client 方法（全部 `parseWithFallback`，未知 enum 显示 `unknown` fallback）；`packages/views` 新增 spec 详情页（FR 时间线 + 一跳直达）、全局搜索 Specs 分组、maturity 治理卡 drift 摘要与 finding 流列表页（状态流转）。web/desktop 共享页面（SDD §3.5/§3.7）。

## 2. 涉及文件 / 模块

- `packages/core/api/schemas.ts`、`packages/core/api/client.ts`
- `packages/views/governance/spec-trace/`（时间线页，路由 `/{slug}/governance/specs/{specId}`）
- `packages/views/search/search-command.tsx`（Specs 分组，`searchSpecs` 并行调用）
- `packages/views/dashboard/maturity/maturity-page.tsx`（drift 卡）
- `packages/views/dashboard/drift/`（finding 列表 + PATCH）
- 测试：malformed response、unknown enum、baseline-imported 渲染、缺失 evidence、跨平台共用

## 3. 实现要点

- schemas：`SpecTraceResponseSchema`、`SpecSearchResponseSchema`、`DriftOverviewSchema`、`DriftFindingsSchema`；enum 加 `unknown` fallback 变换；malformed 返回安全空 envelope 并上报 endpoint tag。
- client：`getSpecTrace(specId)`、`searchSpecs({q,owner,limit,cursor})`、`getDriftOverview()`、`listDriftFindings(filter,cursor)`、`patchDriftFinding(id,{from_status,to_status})`。
- 时间线渲染：`baseline-imported` 历史在事件条目之前；事件按 `(occurred_at,id)` 排序；`trace_snapshot_conflict` 显示冲突标记；evidence 缺失显示 missing，不回退 trunk HEAD；一跳直达仅用 `{repo,trunk,sha}` 构造 GitHub commit 链接。
- drift 卡：健康六态文案 + 计数 + 解决时延；`uninitialized/failed/stale` 明确区分于“无漂移”；列表页 keyset 无限滚动 + PATCH 状态按钮（终态禁用）。

## 4. 验收条件

1. malformed response 测试：不 crash、空 envelope；未知 `scan_health/kind/status` 显示 unknown。
2. 时间线渲染测试：历史导入 + 事件排序 + 缺失 evidence + 冲突标记。
3. 搜索 Specs 分组导航到 spec 详情；drift 卡/列表与 `/api/drift/*` 口径一致；web/desktop 共用组件测试通过。

## 5. 完成标志

`eslint` + `vitest`（core/views）全绿；`parseWithFallback` 覆盖四个 schema。

## 6. 接口契约

- 消费：TASK-07 的 `SpecTimeline`/`SpecSearchPage` DTO；TASK-11 的 `OverviewDTO`/`FindingsPage`/`FindingDTO` 与错误码。
- 产出：
  - 四个 Zod schema + 五个 client 方法（签名见 §3）；views 路由/分组/列表组件（供 TASK-13 E2E 消费）。
