---
id: CR-2026-050-TASK-09
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: requirement-authoring 收敛（register/PRD/review 节点）+ 关键顺序断言
slug: converge-requirement-authoring
status: pending
estimate: 4h
depends-on: [CR-2026-050-TASK-08]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

阶段二第 2 项：收敛 requirement-authoring 的 register / PRD / review 节点（FR-06.1/FR-07.4/FR-07.5/FR-09），保留 `register → PRD → optional checkpoint → review → human approval → approve → checkpoint` 顺序、`auto_push_after_prd` 分支与 execution_context 传递（FR-12.2），并扩展对应确定性断言。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下均为该仓根相对路径：

- `repo=tools: pipeline-templates/requirement-authoring.pipeline.json`（7 节点；approval 与 approve 节点已在 TASK-01/02 收敛，本 TASK 不得回改）
- `repo=tools: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（FR-12.2 断言扩展）

## 实现要点

1. `requirement-register` 节点：删除完整 `crctl register` 参数序列、registration key 派生示例、绝对路径 execution context 示例、repo worktree 结构；保留输入映射与结构化结果消费；**保留 execution_context 输出（含 owners 字段，SDD §2.4）**。
2. `write-requirement-prd` 节点：删除 PRD 章节清单、主 workspace 禁写规则、具体落盘路径、blocker 逐条修复算法；只传 cr_id/source/review_feedback/self_repair_attempt/运行时 context。
3. `review-requirement` 节点：删除评审维度正文、临时 payload、`review-record` 调用、annotation/traceability 写入（不残留 deny 路径字面量）；保留 reviewLoop 机器字段与五要素。
4. FR-12.2 断言扩展：7 节点顺序（ref 序列）、`auto_push_after_prd` skip/execute 分支存在、execution_context 输出与后续节点消费、reviewLoop 字段集不变。

## 验收条件

1. register 节点无 `crctl register` 命令字面量与绝对路径示例；PRD 节点无章节清单；review 节点无 `review-annotations`/`crctl review-record` 字面量。
2. execution_context 输出（含 owners）与 `auto_push_after_prd` 分支保留。
3. 新增 FR-12.2 断言通过；`pipeline-structure.test.mjs` 全绿；`lint-prompts.mjs` 无新增触发。
4. 节点数仍为 7；`_index.yml#nodes` 无需改动（核对一致）。

## 完成标志

上述 4 条验收全部通过，`git diff` 仅含本 TASK 列出的两个文件。

## 接口契约

- 消费：SDD §3.0 保留项、SDD §2.4 execution_context 字段集、`pipeline-structure.test.mjs` 现有 requirement 断言（:133 auto_push_after_prd 保留）。
- 产出：requirement-authoring 7 节点收敛版 + FR-12.2 断言；execution_context 继续输出 owners 是 requirement-register 自身的既有契约，但 approve 节点不消费 owners，角色解析由 approve-* SKILL 从 cr.md 完成。
