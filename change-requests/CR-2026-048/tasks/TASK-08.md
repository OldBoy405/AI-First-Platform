---
id: CR-2026-048-TASK-08
type: TASK
cr-ref: CR-2026-048
plan-ref: "change-requests/CR-2026-048/plan.md"
sdd-ref: "change-requests/CR-2026-048/sdd.md"
title: Market 读端点 GET /api/skills/market
slug: market-read-endpoint
status: pending
estimate: 6h
depends-on: [CR-2026-048-TASK-05]
created: 2026-08-20T14:32:57+08:00
---

# TASK-08 Market 读端点

## 任务描述

新增 `GET /api/skills/market`，一次返回当前 workspace 的 org Skill + builtin 排行。SDD §3.3、§4.3。

## 涉及文件 / 模块

- `server/internal/handler/skill_market.go`（新建）
- `server/cmd/server/router.go`（改：挂载 `/api/skills/market`）
- `server/internal/handler/skill_market_test.go`（新建）

## 实现要点

- `SkillMarketResponse{ Workspace []MarketSkill; Builtin []MarketBuiltin }`，`MarketSkill{ID, Name, Description, Version, OwnerActor string; UsageCount int64}`，`MarketBuiltin{Name, Description string; UsageCount int64}`。
- workspace 部分：`ListOrgSkillSummariesByWorkspace`（TASK-05，已含 visibility='org' 过滤）+ `MarketSkillUsage` 按 `skill.id::text` 反查 usage_count（未命中的 Skill usage=0）。
- builtin 部分：`TaskService.BuiltinSkills()`（既有）列 Name/Description + `MarketSkillUsage` 中 `skill_ref='builtin:<name>'` 的 usage_count。
- 工作区身份只取认证上下文（`h.resolveWorkspaceID(r)`），请求体无任何 workspace 参数；鉴权 `requireWorkspaceRole(..., "member")`。

## 验收条件

1. （AC-3/AC-5）同一 workspace 内 1 个 org Skill 被 2 次 claim（同一任务）后最终 completed → usage_count=1；1 个 private Skill 不出现在结果。
2. （AC-3）builtin 列表含 `builtin:<name>` 的使用量；另一个 workspace 的 usage 不混入（fixture 造两 workspace 数据断言隔离）。
3. 非成员 → 403。

## 完成标志

`go test ./internal/handler/ -run SkillMarket -v` 通过（隔离/去重/鉴权三条）。

## 接口契约

- 消费：`db.ListOrgSkillSummariesByWorkspace`/`MarketSkillUsage`（TASK-05）、`TaskService.BuiltinSkills()`（既有）。
- 产出：`GET /api/skills/market` → `{workspace:[{id,name,description,version,owner_actor,usage_count}], builtin:[{name,description,usage_count}]}`——供 TASK-09 前端消费。
