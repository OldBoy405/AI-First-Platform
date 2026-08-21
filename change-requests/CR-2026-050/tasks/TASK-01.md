---
id: CR-2026-050-TASK-01
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: FR-01 三条 CR Pipeline 人工审批提示修复（受保护账本指引删除）
slug: fix-human-approval-protected-path-prompts
status: pending
estimate: 3h
depends-on: []
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

删除 requirement-authoring / architecture-design / code-implementation 三条 pipeline 的 human approval 提示中「在 review-annotations/*.yml 补充 reject_reason」等直接修改受保护账本的指引，改为结构化 approve/reject 决定 + approve-* reject 流程。这是 P0 安全修复，也是阶段一 gate 的第 1 项。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下均为该仓根相对路径，禁止从 knowledge-base 拼接 `tools/`：

- `repo=tools: pipeline-templates/requirement-authoring.pipeline.json`（human_approval 节点 `…0011-…0005`，字段 `approvalPrompt`）
- `repo=tools: pipeline-templates/architecture-design.pipeline.json`（human_approval 节点 `…0016-…0003`，字段 `approvalPrompt`；**无 `prompt` 字段，不撞 :178/:179 断言**）
- `repo=tools: pipeline-templates/code-implementation.pipeline.json`（代码审批节点 `…0015-…0010`；**不动** `…0004` 开工确认）
- `repo=tools: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（新增负向断言）

## 实现要点

1. 三条 approvalPrompt 改为：人工只提交 `approve/reject` 决定及理由；驳回理由经 `approve-*` reject 流程记录并回退（需求→重写 PRD、架构→tech-designing、代码→developing）；审批证据/CAS/审计/回退由 `crctl approve` 完成。
2. 删除全部 `review-annotations/*.yml` 路径字面量与「补充 reject_reason」指引（注意 SDD §3.1 lint R1：不得残留 deny 路径字面量）。
3. code `…0010` 保留「评审后 checkpoint phase=complete」前提句（SDD §3.0 / 测试 :114-117）。
4. 新增负向断言：三条 JSON 的 approvalPrompt 均不含 `review-annotations` 字面量、不含「补充 reject_reason」。

## 验收条件

1. `grep -n "review-annotations\|reject_reason"` 在三条 JSON 的 human approval 节点返回 0 命中。
2. `…0010` approvalPrompt 仍含 checkpoint `phase=complete` 前提；`…0004` 节点文本零改动。
3. 新增负向断言通过：`node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`。
4. `node skills/shared/crctl/scripts/lint-prompts.mjs` 无新增 R1 触发。

## 完成标志

上述 4 条验收全部通过，且 `git diff` 仅含本 TASK 列出的三处 approvalPrompt 与测试断言改动。

## 接口契约

- 消费：SDD §3.1 反模式清单、SDD §3.0 保留项（`…0010` checkpoint 前提句）。
- 产出：三条 JSON 的 human approval 节点收敛版文本（后续 TASK-09/TASK-10 在同一文件上继续收敛其他节点，不得回改本 TASK 的 approvalPrompt）。
