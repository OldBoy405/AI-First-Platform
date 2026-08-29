---
spec-id: ai-first-platform
version: "0.28"
id: CR-2026-055-TASK-06
type: TASK
cr-ref: CR-2026-055
plan-ref: "change-requests/CR-2026-055/plan.md"
sdd-ref: "change-requests/CR-2026-055/sdd.md"
title: "传递两条 Pipeline 的 reviewer 资源"
slug: pipeline-reviewer-resources
status: pending
estimate: 6h
depends-on: [CR-2026-055-TASK-02, CR-2026-055-TASK-03, CR-2026-055-TASK-05]
created: 2026-08-30T00:20:00+08:00
---

# 1. 任务描述

更新 architecture-design 和 code-implementation 两条 Pipeline，使对应 reviewer 获得正确的 workspace、resources、review feedback 和 attempt，同时保持节点数量、顺序、reviewLoop、UPSTREAM 和失败语义不变。

# 2. 涉及文件 / 模块

- tools worktree 的 `pipeline-templates/architecture-design.pipeline.json`
- tools worktree 的 `pipeline-templates/code-implementation.pipeline.json`
- SDD §3.2、§4.6

# 3. 实现要点

- architecture-design 的 `review-tech-design` 从同次 `workspace inspect` 原样取得 operationalWorkspace 和 resources。
- code-implementation 的 `review-dev-plan` 从 node-1 `execution_context` 原样取得 operational_workspace 和 resources。
- 两个 reviewer 均接收 `review_feedback` 与 `self_repair_attempt`。
- 不新增节点，不改变既有节点 ID、节点顺序、replayNodes、双轨 route、UPSTREAM 或 maxAttempts=3。

# 4. 验收条件

对应 PRD AC-1、AC-4、AC-7。

1. 结构测试确认 architecture reviewer 含 workspace、resources、feedback、attempt，且 resources 来自 workspace inspect。
2. 结构测试确认 code reviewer 含 execution_context.resources，且不重新发现或拼接路径。
3. Pipeline 节点数量、顺序、reviewLoop、replayNodes 和 maxAttempts=3 与现状一致。

# 5. 完成标志

两个 Pipeline JSON 可解析，结构测试通过，reviewer 资源来源与 SDD §3.2 一致。

# 6. 接口契约

- 消费：TASK-01、TASK-02、TASK-03 的 reviewer 输入合同和现有 Pipeline execution_context。
- 产出：两个 reviewer 节点的 workspace/resources/feedback/attempt 传参，供 TASK-07 结构回归消费。
