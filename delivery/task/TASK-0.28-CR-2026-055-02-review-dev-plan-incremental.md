---
spec-id: ai-first-platform
version: "0.28"
id: CR-2026-055-TASK-02
type: TASK
cr-ref: CR-2026-055
plan-ref: "change-requests/CR-2026-055/plan.md"
sdd-ref: "change-requests/CR-2026-055/sdd.md"
title: "明确开发计划增量评审职责"
slug: review-dev-plan-incremental
status: pending
estimate: 8h
depends-on: []
created: 2026-08-30T00:20:00+08:00
---

# 1. 任务描述

更新 `review-dev-plan` Skill，明确 SDD/AC 到 plan/TASK 的翻译增量职责，核验 TASK 新造事实、责任边界、接口契约和验收假绿，并保留普通回修与 UPSTREAM 双轨。

# 2. 涉及文件 / 模块

- tools worktree 的 `skills/develop/review-dev-plan/SKILL.md`
- SDD §3.1、§4.5、§4.8

# 3. 实现要点

- 输入合同必须包含 `cr_id`、`workspace`、`resources`，resources 只能来自 node-1 execution_context。
- 保留八类 plan/TASK 评审维度，但明确 `sdd-to-plan`、`task-executability`、`interface-contracts` 和 `acceptance-verifiability` 的增量边界。
- TASK 新事实不存在或与目标 worktree 不符时形成 blocker，不静默记录 N/A。
- SDD 缺陷或 TASK 新事实反证 SDD 时继续使用 `repair-target=write-tech-design` 的 UPSTREAM 路由。
- 不改变既有 payload、review-record、replayNodes 或状态机转换。

# 4. 验收条件

对应 PRD AC-4、AC-5。

1. Skill 文档明确八类维度和四个增量职责，且不对已审批 SDD 做无差别重复评审。
2. 文档包含 TASK 新事实、责任层、接口/nil 契约、验收组合证明和假绿检查规则。
3. 文档明确普通 blocker 与 UPSTREAM blocker 的 route、触发器和不覆盖 SDD annotation 的约束。

# 5. 完成标志

`review-dev-plan/SKILL.md` 与 SDD §4.5、§4.8 一致，输入资源边界和双轨路由均可被结构测试检查。

# 6. 接口契约

- 消费：已审批 SDD、plan、TASK、node-1 execution_context、reviewLoop feedback 和目标 resources。
- 产出：plan/TASK 增量评审规则与 `repair-target` 路由语义，供 TASK-06、TASK-07 和后续 code-implementation 使用。
