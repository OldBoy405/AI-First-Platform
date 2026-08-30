---
id: CR-2026-056-TASK-01
type: TASK
cr-ref: CR-2026-056
plan-ref: "change-requests/CR-2026-056/plan.md"
sdd-ref: "change-requests/CR-2026-056/sdd.md"
title: M0 基线核对与实现准备
slug: m0-baseline-inspect
status: pending
estimate: 4h
depends-on: []
created: 2026-08-30T20:45:00+08:00
---

## 任务描述

确认两个资源 worktree 可用、基线与工具链就绪，把路径/基线/验证命令固化为后续 TASK 的消费事实。对应 plan.md M0（0.5 人天）。

输入条件：CR 已 `tech-design-reviewed`；multica CR worktree 已存在于 `.rayai-worktrees/multica/requirement/CR-2026-056`，knowledge-base CR worktree 已存在于 `.rayai-worktrees/knowledge-base/requirement/CR-2026-056`。

## 涉及文件 / 模块

- 无代码改动（只读核对）。核对产物记录在本 TASK 的验收输出与后续提交信息中。

## 实现要点

1. 对两资源执行 `crctl workspace inspect`，确认均 healthy；路径以输出为准，不得实施期重拼（plan §2）。
2. multica CR worktree 执行 `crctl git rev-parse HEAD`，必须等于 SDD §9 声明基线 `8746add879cbd1c78e573c2a4a1776e16158c00c`。
3. 核实 `server/migrations/` 最大编号为 `471_approval_continuation_workspace_cr_pending_unique.up.sql`（SDD §9 #8），确定本 CR 迁移从 472 起。
4. 验证 `make sqlc` 可运行（仓根）；Go 模块在 `server/go.mod`（仓根无 `go.mod`），三组入口在 `server/` 目录执行：`cd server && go test ./internal/handler/ ./pkg/agent/ ./internal/service/ -count=1`，基线上全绿；前端测试命令（`packages/core/api/schemas.test.ts`、locales parity、team-agent / private-ask 组件测）入口可用。
5. 若 HEAD 漂移 / diverged / 资源异常：按 `workspace-freshness` gate 路由（continue / synced-continue / replay / manual）处理，不自动合并，必要时暂停上报。

## 验收条件

1. `crctl git rev-parse HEAD`（multica CR worktree）输出 `8746add879cbd1c78e573c2a4a1776e16158c00c`。
2. 迁移目录最大编号 471；`make sqlc` 运行成功；`cd server && go test ./internal/handler/ ./pkg/agent/ ./internal/service/ -count=1` 基线绿（输出留档）。
3. 两资源 inspect 均 healthy，路径与 plan §2 资源列表一致。

## 完成标志

上述三项核验输出全部留档（提交信息或会话记录），后续 TASK-02~TASK-11 直接消费，不再重复探测。

## 接口契约

- 消费：无（首个 TASK）。
- 产出（事实，非代码）：两资源权威路径、multica 基线 SHA `8746add...`、最大迁移号 471、验证命令清单（Go 命令一律 `cd server && ...`：`cd server && go build ./...`、`cd server && go test ./internal/handler/ ./pkg/agent/ ./internal/service/ -count=1`）——供 TASK-02（迁移编号起点）、TASK-03（make sqlc）、TASK-11（测试命令）消费，各 TASK 不得另行拼 Go 命令。
