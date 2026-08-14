---
spec-id: ai-first-platform
version: "0.28"
id: CR-2026-027-TASK-01
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: bootstrap：tools 入 repositories + tools worktree 派生 + workspace Phase 0 文档统一
slug: bootstrap-tools-worktree-phase0-docs
status: pending
estimate: 6h
depends-on: []
created: "2026-08-09T23:35:00+08:00"
---

# TASK-01 — bootstrap：tools 入 repositories + worktree 派生 + workspace 文档统一

## 任务描述

本 CR 实施第一步（FR-15 硬约束）：将 tools 声明为 workspace 参与仓，从 `custom/main` 补建 `requirement/CR-2026-027` worktree（记录 `bootstrap-base-sha`），并完成 workspace 侧 Phase 0 文档统一（FR-1/FR-6 的 workspace 部分）。worktree 未就位前禁止任何 tools 改动。

## 涉及文件 / 模块

- workspace `dir-graph.yaml`：repositories 新增 `{id: tools, path: "../tools", trunk: custom/main, role: code, active: true}`
- workspace `AGENTS.md`：状态机口径 25/47 → 27/49（工程纪律 #2 段）
- workspace `docs/analysis/tools流程步骤优化v2.md`：删除旧方案 command module（`crctl/scripts/commands/*.mjs`）与五条通用上下文命令（patch/run-workflow/stage-context/registration-check/register-preflight）描述（FR-6）
- `../tools` 仓：新建分支 `requirement/CR-2026-027` worktree（`.rayai-worktrees/tools/requirement/CR-2026-027`）

## 实现要点

- 修改 workspace `dir-graph.yaml` 后，以**主工作区**为 `--workspace` 调用 `crctl worktree-path CR-2026-027 --repo tools`（SDD §1.3 调用根固定，禁止从 CR worktree 以 `--workspace .` 调用）
- `git fetch origin`（tools 仓）后 `git worktree add -b requirement/CR-2026-027 <path> custom/main`；记录 `bootstrap-base-sha` = 派生时 custom/main HEAD（写入本 TASK 完成标志与 AC-22 断言）
- fetch 失败按 `STALE_BASE` 降级：从本地 custom/main 派生并在实施记录标注基线滞后（SDD FR-15）
- workspace 文档修改提交到 knowledge-base 分支 `requirement/CR-2026-027`；tools worktree 创建本身不产生 tools 提交

## 验收条件

1. workspace `dir-graph.yaml#repositories` 含 tools（path/trunk/role/active 四字段齐全）
2. `../tools` 仓存在分支与 worktree `requirement/CR-2026-027`，`git rev-parse custom/main` = `bootstrap-base-sha` 记录值
3. grep workspace `AGENTS.md` 无 25/47「现状」表述（按 AC-1 判定：历史注脚除外）
4. v2 方案文档无 `commands/` 模块目录与五条通用上下文命令描述（按 AC-6 判定）

## 完成标志

workspace 声明与文档修改已提交至 knowledge-base 分支；tools worktree 已派生且 `bootstrap-base-sha` 已记录；AC-5 的 repositories 部分与 AC-22 的 worktree 存在性通过。

## 接口契约

- 消费：无（首个 TASK）
- 产出：tools 仓 worktree 路径 `.rayai-worktrees/tools/requirement/CR-2026-027`（TASK-02~09 的 tools 改动落点）；`bootstrap-base-sha`（TASK-10 的 AC-22 断言输入）
