---
spec-id: ai-first-platform
version: "0.28"
id: CR-2026-055-TASK-01
type: TASK
cr-ref: CR-2026-055
plan-ref: "change-requests/CR-2026-055/plan.md"
sdd-ref: "change-requests/CR-2026-055/sdd.md"
title: "强化技术设计评审合同"
slug: review-tech-design-contract
status: pending
estimate: 8h
depends-on: []
created: 2026-08-30T00:20:00+08:00
---

# 1. 任务描述

更新 `review-tech-design` Skill，使技术设计评审能够消费 Pipeline 提供的真实 workspace/resources，完成 AC 闭环、SDD 既有实现依赖核验、首轮全量 blocker 汇总和回修复核。

# 2. 涉及文件 / 模块

- tools worktree 的 `skills/develop/review-tech-design/SKILL.md`
- SDD §3.1、§4.1 至 §4.4、§4.8

# 3. 实现要点

- 输入合同必须包含必填 `cr_id`、`workspace`、`resources`，以及可选反馈和轮次。
- 评审保留既有 8 个维度；首轮完成全部适用维度后再形成 verdict，不在首个 blocker 处提前结束。
- 对每个 AC 检查设计落点、可观测结果和关键前置条件可达性。
- 只核验 SDD 显式列出的既有实现依赖，并拒绝将正文未列出的事实静默记为 N/A。
- 保留既有临时 payload、`crctl review-record`、reviewLoop 和 route 分流，不新增 payload 字段或运行时层。

# 4. 验收条件

对应 PRD AC-1、AC-2、AC-3。

1. Skill 文档明确列出输入合同、resources 路径约束、AC 闭环和既有依赖识别规则。
2. 文档明确首轮多 blocker 汇总、回修旧 blocker 逐条复核、新 blocker 同轮加入和 maxAttempts=3 不 reset。
3. 文档中的临时 payload、review-record 和 route 分流仍使用既有合同，不引入 runner、adapter 或新账本。

# 5. 完成标志

`review-tech-design/SKILL.md` 与 SDD §3.1、§4.1 至 §4.4、§4.8 一致，prompt lint 无新增问题。

# 6. 接口契约

- 消费：PRD、SDD、Pipeline 的 `workspace`/`resources`/reviewLoop 输入和既有 `crctl review-record` 合同。
- 产出：技术设计评审输入、AC/事实核验和回修规则，供 TASK-06 与 TASK-07 消费。
