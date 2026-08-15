---
id: CR-2026-043-TASK-04
type: TASK
cr-ref: CR-2026-043
plan-ref: "change-requests/CR-2026-043/plan.md"
sdd-ref: "change-requests/CR-2026-043/sdd.md"
title: code-implementation 双 gate 与 reviewLoop 重放及契约测试
slug: pipeline-freshness-gates
status: pending
estimate: 6h
depends-on: [CR-2026-043-TASK-03]
created: 2026-08-16T01:00:22+08:00
---

# TASK-04 code-implementation 双 gate 与 reviewLoop 重放及契约测试

## 1. 任务描述

在 `code-implementation.pipeline.json` 插入两个 `workspace-freshness` gate 节点（implement-code 前、review-code 前），扩展 review-code 节点 `reviewLoop.replayNodes` 为 5 项，同步 `pipeline-templates/_index.yml` 节点数，并新增契约测试。对应 FR-05、FR-06（SDD Phase C 第二部分）。

## 2. 涉及文件 / 模块

- `pipeline-templates/code-implementation.pipeline.json`
- `pipeline-templates/_index.yml`
- `skills/shared/crctl/scripts/test/`（契约测试，并入现有 contract/pipeline 测试文件或新增最小文件）

## 3. 实现要点

- 节点 `00000000-0000-0000-0015-000000000016`：kind=skill，ref=workspace-freshness，label=「Workspace freshness（实施前）」，位置在 approve-dev-start(...005) 之后、implement-code(...006) 之前；prompt 传入 `cr_id`、`gate=implement-start`；`route=manual` 时 abort，不进入 implement-code；onFail=abort。
- 节点 `00000000-0000-0000-0015-000000000017`：同 ref，label=「Workspace freshness（评审前）」，位置在统一 checkpoint push-progress(...008) 之后、「选择代码评审 LLM」human_approval(...013) 之前；`gate=review-start`；`route=replay` 时按 reviewLoop 回修，`manual` 时 abort；onFail=abort。
- review-code 节点(...009) `reviewLoop.replayNodes` 扩为 5 项，顺序：implement-code(...006) → write-test-report(...007) → push-progress(...008) → workspace-freshness(...017, purpose: `re-verify-baseline`) → review-code(...009)。write-test-report 节点(...007) 自身 replayNodes 不动。
- 节点 prompt 只描述输入传递、一次 Skill 调用与按 route 分流；不复制 Skill 步骤全文，不出现 git/journal 字样。
- `pipeline-templates/_index.yml`：code-implementation-v1 `nodes: 13 → 15`。
- 契约测试断言：JSON 可解析；两节点 ref=workspace-freshness 且位置正确（...016 在 ...005 与 ...006 之间、...017 在 ...008 与 ...013 之间）；review-code replayNodes 恰为 5 项且含 ...017；`_index.yml` nodes==JSON nodes 数组长度==15；所有 node.ref 在 `skills/_index.yml` active；pipeline prompt 全文无 `git `/journal 字样；`gates.json` 与状态机文件未被本 CR 修改（diff 断言）。

## 4. 验收条件

1. `node -e` pipeline JSON 解析通过；`pipeline-templates/_index.yml` nodes=15 与实际一致。
2. 契约测试全部通过，包含节点位置、replayNodes 顺序、active ref、prompt 无违禁字样四类断言。
3. 既有 pipeline 契约/lint 检查保持通过；write-test-report 与 dev-plan reviewLoop 未被改动。

## 5. 完成标志

契约测试通过 + tools 仓既有自检命令（pipeline JSON 可解析）通过 + lint 零新增报错。

## 6. 接口契约

- **消费**：TASK-03 产出的 Skill ref `workspace-freshness` 与其输出契约 `{ route, facts, blockers }`。
- **产出**：
  - pipeline 节点 `00000000-0000-0000-0015-000000000016`、`00000000-0000-0000-0015-000000000017`（供运行时编排消费）
  - review-code reviewLoop.replayNodes 5 项声明（供 TASK-05 集成测试消费）
