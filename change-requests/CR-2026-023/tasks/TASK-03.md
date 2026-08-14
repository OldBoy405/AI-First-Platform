---
id: CR-2026-023-TASK-03
type: TASK
cr-ref: CR-2026-023
plan-ref: "change-requests/CR-2026-023/plan.md"
sdd-ref: "change-requests/CR-2026-023/sdd.md"
title: 块 B — 17 处存量清零 + push-progress 闭环 + requirement-writer 注记 + AGENTS.md 条目（FR-8/9/10/11）
slug: r9-backlog-zeroing
status: pending
estimate: 6h
depends-on: [CR-2026-023-TASK-01]
assignee: ""
created: "2026-08-07T00:40:00+08:00"
---

## 任务描述

把 CR 上下文域 17 处手写「下一步」副本改写为统一形态（FR-8），并配套 push-progress 引导链闭环（FR-9）、requirement-writer 前置注记（FR-10）、tools AGENTS.md 编辑规则第 7 条（FR-11）。行号以**内容锚点**定位（纪律 #4，行号可能已漂移）。

## 涉及文件 / 模块（17 处 SKILL.md + 3 处配套）

**17 处存量清零**（附件2 §4.2 表，行号为参考锚点）：
- requirement（4）：`requirement-register/SKILL.md`、`write-requirement-prd/SKILL.md`、`review-requirement/SKILL.md`、`approve-requirement/SKILL.md`
- develop（9）：`write-tech-design`、`review-tech-design`、`approve-tech-design`、`write-dev-plan`、`write-dev-tasks`、`approve-dev-start`、`write-test-report`、`review-code`、`approve-code`
- writeback（4）：`merge-feature-branch`、`writeback-prd-sdd`、`writeback-tasks`、`writeback-traceability`

**配套 3 处**：
- `skills/sync/push-progress/SKILL.md`（输出摘要 `last-push-at` 行后补「下一步 : 以 `crctl next {cr_id}` 为准」，FR-9）
- `agents/requirement-writer.md`（映射表 approve-requirement 行加前置注记：仅当 verdict=pass 且 blockers=[]，FR-10）
- tools 仓 `AGENTS.md`（「编辑规则 → 修改 Skill」追加第 7 条，FR-11）

## 实现要点（SDD §3.3 统一改写形态）

- 有 PASS/BLOCK 分支语义的（review-* / write-test-report）：`下一步 : 以 crctl next {cr_id} 为准（PASS→等待人工审批；BLOCK→pipeline 自动回对应修复节点重审）`
- 纯顺序流转的（register/prd/approve-* 链）：`下一步 : 以 crctl next {cr_id} 为准`
- **括号内不得写任何字面 skill id**（D-4 防自触发；"对应修复节点"是语义方向占位）
- 保留原分支语义，只收敛权威指针

## 验收条件

1. 改写前 `--mode report` 命中恰为 17 处（对照附件2 §4.2 表，不多不少）；改写后 `--mode enforce` 全库 R9 归零。
2. 逐行 diff 核对分支语义保留；grep 证实改写后行不含字面 skill id（不自触发 R9）。
3. push-progress 摘要、requirement-writer 注记、AGENTS.md 第 7 条三处配套落地且与 R9 scope 五域枚举一致。

## 完成标志

17 处清零 + 3 处配套完成，`--mode enforce` 归零；与 TASK-01/02 同 commit 1 提交（NFR-1 原子）。
