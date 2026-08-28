---
id: CR-2026-053-TASK-03
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 修改 pipeline 节点 prompt (review-* 节点)
slug: pipeline-review-prompt-update
status: pending
estimate: 2h
depends-on: []
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

修改三个 Pipeline 的四个 review 节点 prompt：
- `requirement-authoring.pipeline.json` → review-requirement 节点
- `architecture-design.pipeline.json` → review-tech-design 节点
- `code-implementation.pipeline.json` → review-dev-plan + review-code 节点

Prompt 变更内容：
- 明确"新建独立 reviewer task/run"
- 每轮 reviewLoop 重新委派
- 技术失败 `onFail=abort`
- 业务 block 走既有 reviewLoop
- 不内嵌绑定 API/SQL/评审维度

## 涉及文件 / 模块

- `../tools/pipeline-templates/requirement-authoring.pipeline.json`
- `../tools/pipeline-templates/architecture-design.pipeline.json`
- `../tools/pipeline-templates/code-implementation.pipeline.json`

## 实现要点

参考 SDD §6 FR-A4 和 §1.3 目标闭环：
- schema/节点顺序/reviewLoop/onFail 不变
- 仅改 prompt 描述
- 验证 `lint-prompts.mjs` 通过

## 验收条件

1. 四个 review 节点 prompt 明确新建独立 reviewer
2. `lint-prompts.mjs` 零报错
3. Pipeline schema 未变化

## 完成标志

- 三个 pipeline JSON 修改已 commit

## 接口契约

无接口产出。
