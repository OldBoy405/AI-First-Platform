---
spec-id: ai-first-platform
version: "0.27"
id: CR-2026-053-TASK-03
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 修改 pipeline 节点 prompt (review-* 节点, 含 FR-A6 无 subagent 路径)
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
- 明确"新建独立 reviewer task/run"，不得恢复作者会话执行评审
- 每轮 reviewLoop 重新委派
- 技术失败 `onFail=abort`
- 业务 block 走既有 reviewLoop
- **FR-A6**：不支持 subagent 的运行时，停在当前 review 节点 + 提示用户另开独立会话以 `quality-reviewer-agent` 身份运行同一 review Skill，不退化为作者自评
- 不内嵌绑定 API/SQL/评审维度

## 涉及文件 / 模块

- `pipeline-templates/requirement-authoring.pipeline.json`（tools 仓根）
- `pipeline-templates/architecture-design.pipeline.json`
- `pipeline-templates/code-implementation.pipeline.json`

## 实现要点

参考 SDD §6 FR-A4/FR-A5/FR-A6 和 §1.3 目标闭环：
- schema/节点顺序/reviewLoop/onFail 不变，仅改 prompt 描述
- FR-A5：一次独立评审入口只执行一轮，回修循环仍归 Pipeline 持有
- 验证 `lint-prompts.mjs` 通过

## 验收条件

1. `node skills/shared/crctl/scripts/lint-prompts.mjs` 零报错（tools 仓 worktree 根执行）
2. `grep -c '"reviewLoop"' pipeline-templates/{requirement-authoring,architecture-design,code-implementation}.pipeline.json` 节点结构未变化
3. 四个 review 节点 prompt 文本含"新建独立 reviewer task/run"与"无 subagent 时另开独立会话"

## 完成标志

- 三个 pipeline JSON 修改已 commit

## 接口契约

无接口产出。
