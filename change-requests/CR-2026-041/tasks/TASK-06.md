---
id: CR-2026-041-TASK-06
type: TASK
cr-ref: CR-2026-041
plan-ref: "change-requests/CR-2026-041/plan.md"
sdd-ref: "change-requests/CR-2026-041/sdd.md"
title: 退役 change-impact-analysis
slug: retire-change-impact-analysis
status: pending
estimate: 3h
depends-on: []
created: 2026-08-15T22:05:40+08:00
---

# TASK-06 退役 change-impact-analysis

## 1. 任务描述

删除 `change-impact-analysis` Skill 及其全部 active 引用（建立在不存在 baseline schema `requirements[].reviews.*.result=stale` 上的虚假能力声明）。对应 FR-06。

## 2. 涉及文件 / 模块

删除：

- `skills/review/change-impact-analysis/SKILL.md`

编辑（清 active 引用）：

- `skills/_index.yml`（`change-impact-analysis` 条目）
- `agent-skill-matrix.yml`（quality-reviewer owns 的 `change-impact-analysis`）
- `AGENT-SKILL-MATRIX.md`（`quality-reviewer-agent` 行）
- `agents/quality-reviewer-agent.md`（「变更影响分析」行与 owns 列表）
- `agents/_index.yml`（description、supported、path 引用）
- `dir-graph.yaml#skill_context.change-impact-analysis`
- `README.md`（第 552 行「影响分析」行）
- `docs/QODER-使用指南.md`（第 753 行「变更影响分析」示例）
- `openwiki/architecture/agent-skill-matrix.md`（`quality-reviewer-agent` 行）
- `skills/review/review-alignment/SKILL.md`（第 60 行 AL-07 与第 112 行「与其他 Skill 关系」中的 change-impact 行）

## 3. 实现要点

- 删除只针对 active 引用；`docs/二开修改报告_v2.html`、`docs/AI-First-研发协同平台-架构讲解.html` 属历史报告/快照，保留不改（PRD FR-06.4）。
- `review-alignment` 删 AL-07 后，其验收条件不再依赖不存在的 stale 模型。
- 每次删除/编辑后跑 `check-skill-matrix.test.mjs` / `check-agents-contract.test.mjs` / `contract-scan.test.mjs` 验证索引一致。

## 4. 验收条件

1. `rg -n "change-impact-analysis"` 在 active 路径（skills/_index.yml、agent-skill-matrix.yml、AGENT-SKILL-MATRIX.md、agents/*、README.md、docs/QODER-使用指南.md、openwiki/architecture/agent-skill-matrix.md、dir-graph.yaml）零命中。
2. `change-impact-analysis` Skill 目录已删除；`check-skill-matrix` / `check-agents-contract` / `contract-scan` 通过。

## 5. 完成标志

退役静态扫描测试（TASK-08）通过，且本 CR 全部 contract 测试通过。

## 6. 接口契约

- **消费**：无。
- **产出**：active 能力面收敛（`change-impact-analysis` 从索引/矩阵/Agent/README/docs/dir-graph 移除），供 TASK-08 静态扫描验证。
