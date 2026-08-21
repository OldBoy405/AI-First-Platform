---
id: CR-2026-050-TASK-13
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: 规划类 Pipeline FR-09 下沉 + write-roadmap 提交前缀对齐
slug: planning-pipelines-responsibility-sink
status: pending
estimate: 3h
depends-on: [CR-2026-050-TASK-12]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

阶段二第 6 项：在 product-planning / market-to-plan / competitive-radar 三条 JSON 上完成 FR-09 章节/路径/索引下沉（不改变 TASK-03/04/05 已落的输入契约与闭环流程），并对齐 write-roadmap SKILL.md 提交前缀。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下均为该仓根相对路径：

- `repo=tools: pipeline-templates/product-planning.pipeline.json`
- `repo=tools: pipeline-templates/market-to-plan.pipeline.json`
- `repo=tools: pipeline-templates/competitive-radar.pipeline.json`
- `repo=tools: skills/planning/write-roadmap/SKILL.md`（DD-7：`[planning] ` → `[cr] `）

## 实现要点

1. 三条 JSON 删除以下由对应 Skill 负责的描述：规划报告/竞品报告固定章节清单、文件名与 slug 派生、`_index.yml` 字段与排序规则、review annotation 文件结构、roadmap 幂等追加细节、两阶段落盘规则细节。
2. 不得改动：TASK-03 的 topic/skip/顺序调用链、TASK-04 的 context/intent/mode、TASK-05 的 reportDraft/confirmed 闭环与 skip 分支。
3. write-roadmap SKILL.md 的 Commit 指引改为 `[cr] update roadmap ...`（白名单内）。

## 验收条件

1. 三条 JSON 的 prompt 无固定章节枚举、slug 派生、`_index.yml` 字段/排序、annotation 文件结构描述；负向断言（TASK-14 汇总）先行 grep 验证。
2. TASK-03/04/05 的输入映射与闭环表述逐条仍在（diff 仅删不增）。
3. write-roadmap 无 `[planning] ` 前缀。
4. JSON 可解析；节点数不变（8/5/5）；`lint-prompts.mjs` 无新增触发。

## 完成标志

上述 4 条验收全部通过，`git diff` 仅含本 TASK 列出的四个文件。

## 接口契约

- 消费：TASK-03/04/05 的收敛版 prompt（本 TASK 只在既有文本上做删除，不重写输入契约）。
- 产出：三条规划 Pipeline 的 FR-09 下沉版；write-roadmap 前缀对齐。
