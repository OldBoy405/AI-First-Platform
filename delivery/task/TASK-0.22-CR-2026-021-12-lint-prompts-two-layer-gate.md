---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-12
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: 两层机械防线接入 — pre-commit（分阶段 report→enforce）+ CI cr-guard
slug: lint-prompts-two-layer-gate
status: pending
estimate: 4h
depends-on: ["CR-2026-021-TASK-11"]
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-24（SDD §4.4）：`.githooks/pre-commit` 新增 `lint-prompts` 步骤，**本任务只接入 `--mode report`**（M1~M4 期间不阻断，避免拦死本 CR 自身开发期 commit——切到 `--mode enforce` 是 TASK-22 的最后一步，不在本任务范围）；同时接入 CI `cr-guard.template.yml`（归档前 `lint-prompts --mode enforce` 必须 pass）。

**落地 tech-design 评审 suggestion-1（关键，不可默认已解决）**：SDD 只是理论声明「CI 侧兜底」，本任务必须**实测确认** CI 是否真的会调用 `cr-guard.template.yml`——不能仅在文档里写"已接入"就算数。

## 涉及文件 / 模块

- `.githooks/pre-commit`（+1 行，`--mode report`）
- `skills/shared/crctl/adapters/ci/cr-guard.template.yml`（接入 `lint-prompts --mode enforce`）
- 使用方仓库的 CI workflow 配置（若存在，需确认其确实引用了 `cr-guard.template.yml`；若本环境找不到实际 CI workflow 引用该模板，需在完成摘要中**显式标注此为未验证的残余风险**，不得含糊带过）

## 实现要点

1. pre-commit 新增行：`node "$(git rev-parse --show-toplevel)/skills/shared/crctl/scripts/lint-prompts.mjs" --mode report`（不加 `|| exit 1`，report 模式恒 exit 0，天然不阻断）。
2. `cr-guard.template.yml` 加一步 `lint-prompts --mode enforce`，失败即该模板的整体检查失败（阻断归档）。
3. **验证 CI 接线**：搜索仓内/使用方仓库是否有实际引用 `cr-guard.template.yml` 的 CI workflow 文件（如 `.github/workflows/*.yml`）。若找到，确认其执行时机在归档前；若找不到，如实记录"模板已就绪但当前无 CI workflow 消费它"，作为已知限制写入本任务完成摘要与 SDD 风险清单（不是本任务失败，是如实反映现状）。

## 验收条件

- AC-14（PRD）：`.githooks/pre-commit` 新增步骤，M1~M4 期间对存量漂移的 commit 不阻断（report 模式验证）。
- CI cr-guard 接线状态已实测确认并如实记录（接入且生效 / 模板就绪但未被消费，二选一明确结论，不含糊）。

## 完成标志

pre-commit 钩子含 `lint-prompts --mode report` 且不阻断存量漂移 commit；CI cr-guard 接线状态有明确、可核查的结论。
