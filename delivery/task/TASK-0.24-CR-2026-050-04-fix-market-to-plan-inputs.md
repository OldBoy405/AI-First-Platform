---
spec-id: ai-first-platform
version: "0.24"
id: CR-2026-050-TASK-04
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: FR-03 market-to-plan 必填参数修复 + extract-market-insight 简报模式
slug: fix-market-to-plan-inputs
status: pending
estimate: 4h
depends-on: [CR-2026-050-TASK-01]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

修复 market-to-plan 的 `planning-draft` 缺必填 `context/intent`、brief 调用契约缺失、跨文档写入越界三处问题；并为 extract-market-insight 增加 `mode=brief`/`raw_insight_path` 显式输入（SDD §2.2）。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下均为该仓根相对路径：

- `repo=tools: pipeline-templates/market-to-plan.pipeline.json`（5 节点）
- `repo=tools: skills/planning/extract-market-insight/SKILL.md`（参数表 + Step 3.5 触发条件 + 失败码）

## 实现要点

1. node-3 `planning-draft`：按 SDD §4.3 顺序调用 `gather-product-context` → `planning-draft(context=快照, intent=从简报提炼的一句话意图, target_version)`；不再用未声明的「简报」替代 `context`。
2. node-2（extract-market-insight 第二次调用）：显式传 `mode: brief`、`raw_insight_path`；删除 `source` 伪造参数。
3. node-5 `write-planning-entry`：删除对 `docs/market-insights/_index.yml` 生命周期状态 `published` 的跨文档写入（SDD DD-8 已确认该生命周期终态暂缺写者，属已知后果）。
4. SKILL.md：参数表增加 `mode`（默认 insight）与 `raw_insight_path`（mode=brief 时必填）；Step 3.5「简报附加区块」触发条件改为由 `mode=brief` 驱动；`mode=brief` 且路径缺失/不可读时按 `INSIGHT_SOURCE_EMPTY` 同族错误码硬失败，不静默降级为 insight 模式。

## 验收条件

1. node-3 含 gather-product-context 调用与 `context`/`intent` 映射；node-2 含 `mode=brief`/`raw_insight_path` 且无 `source` 伪造参数。
2. node-5 无 `docs/market-insights/_index.yml` 写入表述。
3. SKILL.md 参数表含两个新输入及默认值/必填语义；Step 3.5 由 `mode` 驱动；失败码语义明确。
4. JSON 可解析；节点数仍为 5；`lint-prompts.mjs` 无新增触发。

## 完成标志

上述 4 条验收全部通过，`git diff` 仅含本 TASK 列出的两个文件。

## 接口契约

- 消费：`planning-draft` 必填 `context`（gather-product-context 输出）/`intent`（SDD §2.3）；extract-market-insight 现有错误码风格。
- 产出：SKILL 新输入契约 `mode: insight|brief`（默认 insight）、`raw_insight_path`（brief 必填）；node-2/3/5 收敛版 prompt；TASK-13 做 FR-09 下沉时不得回改本 TASK 的输入契约。
