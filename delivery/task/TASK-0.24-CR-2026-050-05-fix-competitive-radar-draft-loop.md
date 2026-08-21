---
spec-id: ai-first-platform
version: "0.24"
id: CR-2026-050-TASK-05
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: FR-04 competitive-radar 草稿/落盘顺序闭环 + reportDraft 输入契约
slug: fix-competitive-radar-draft-loop
status: pending
estimate: 5h
depends-on: [CR-2026-050-TASK-01]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

修复 competitive-radar 的参数名漂移、node-2 缺必填输入、node-3「草稿未落盘却要求 reportPath」矛盾与 node-5 混调两 Skill 问题，并为 report-to-planning-suggestion 增加 `reportDraft` 输入契约（SDD §2.1/§4.1/§4.3）。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下均为该仓根相对路径：

- `repo=tools: pipeline-templates/competitive-radar.pipeline.json`（5 节点）
- `repo=tools: skills/competitive/report-to-planning-suggestion/SKILL.md`（输入契约 + 前置条件 + 错误处理表 + 读写清单）

## 实现要点

1. node-1：只做参数名映射 `competitor_slug → competitor-id/competitor-ids[]`、`since_days → lookback-days`；`slug → id` 的索引解析归 `fetch-competitor-updates`（Pipeline 不读竞品索引）。
2. node-2：按 SDD §4.3 顺序调用 `gather-product-context` → `write-competitive-report(updates-block=node-1 输出, product-snapshot, confirmed=false)`，产出草稿正文。
3. node-3：传 `reportDraft`（草稿正文、competitorId、reportDate、来源节点/标识）；SKILL.md 增加 `reportDraft` 可选输入、`reportPath` 优先规则、草稿模式不落盘语义，并同步修订前置条件与错误处理表首行（原「reportPath 不存在即中止」改为 reportPath|reportDraft 二选一）；保留前端按 reportPath 触发的入口契约。
4. node-5：人工确认后顺序调用 `write-competitive-report(confirmed=true, updates-block, product-snapshot)` → `write-planning-entry(source=node-3 输出)`；不在 prompt 复制报告落盘算法。

## 验收条件

1. node-1 无 slug/since_days 直接透传；node-2 含 gather 调用与三必填输入；node-5 含两个 Skill 的顺序调用与 confirmed=true 传递。
2. SKILL.md 的 reportDraft 契约含五字段（body/competitorId/reportDate/sourceNodeId/sourceRef）与「两者同时存在优先 reportPath」。
3. node-3 不再把草稿伪装成 reportPath；草稿模式不落盘表述明确。
4. JSON 可解析；节点数仍为 5；`lint-prompts.mjs` 无新增触发。

## 完成标志

上述 4 条验收全部通过，`git diff` 仅含本 TASK 列出的两个文件。

## 接口契约

- 消费：`write-competitive-report` 两阶段协议（confirmed=false 仅草稿 / true 落盘）、`fetch-competitor-updates` 输出结构、`gather-product-context` 输出。
- 产出：`reportDraft` 最小结构（SDD §2.1 五字段 + reportPath 优先级）；node-1/2/3/5 收敛版 prompt；TASK-13 做 FR-09 下沉时不得回改本 TASK 的闭环流程。
