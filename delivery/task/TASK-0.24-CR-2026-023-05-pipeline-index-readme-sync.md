---
spec-id: ai-first-platform
version: "0.24"
id: CR-2026-023-TASK-05
type: TASK
cr-ref: CR-2026-023
plan-ref: "change-requests/CR-2026-023/plan.md"
sdd-ref: "change-requests/CR-2026-023/sdd.md"
title: 块 A — _index.yml nodes 12→13 + README 节点表/mermaid 同步（FR-5/6）
slug: pipeline-index-readme-sync
status: pending
estimate: 3h
depends-on: [CR-2026-023-TASK-04]
assignee: ""
created: "2026-08-07T00:40:00+08:00"
---

## 任务描述

同步块 A 节点数变更到台账与文档：`pipeline-templates/_index.yml` 的 code-implementation-v1 条目 nodes 12→13 + brief 补环节（FR-5）；tools 仓 `README.md` 代码编写期节点表插行 + mermaid 流程图 D8→新节点→D9 中转（FR-6）。nodes 计数以 TASK-04 实际结果为准。

## 涉及文件 / 模块

- `pipeline-templates/_index.yml`（code-implementation-v1 条目，L52 附近）
- tools 仓 `README.md`（代码编写期节点表 L453 附近 + mermaid 图 L425-426）

## 实现要点（SDD §4.2 第 5 步）

1. `_index.yml`：`nodes: 12 → 13`；brief 补「选择代码评审 LLM（人工确认）」环节描述。
2. README 节点表：在「推送代码+文档统一 checkpoint」行（L453）之后插入新节点行（输入=统一 checkpoint 结果 + 触发参数 review_llm / 行为=暂停等待人工选择模型 / 状态写入=无 / 可跳过=否）。
3. README mermaid：`D8 --> D9`（L425-426 直连）改为经新节点中转（D8 → 新节点 → D9）；节点总数描述 12→13 同步。

## 验收条件

1. `_index.yml` 该条 `nodes: 13` 且 brief 含选择节点描述；与 TASK-04 的 pipeline 实际节点数一致。
2. README 节点表新行位于正确位置且列齐（输入/行为/无状态写入/不可跳过）；mermaid 图 D8 与 D9 之间经新节点中转，无直连残留。

## 完成标志

台账 + README 双同步完成，节点数口径一致（13）；与 TASK-04 同 commit 2 提交。
