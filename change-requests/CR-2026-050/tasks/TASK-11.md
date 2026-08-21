---
id: CR-2026-050-TASK-11
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: resume-cr 展示节点收敛 + cr-show 输出契约补最近三次 checkpoint
slug: converge-resume-cr-cr-show
status: pending
estimate: 2h
depends-on: [CR-2026-050-TASK-06]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

阶段二第 4 项：把 resume-cr node-3 的 CR 详情字段/状态映射清单收回 cr-show Skill（FR-10.1），并把「最近三次 checkpoint」写入 cr-show 输出契约（SDD DD-5）。

## 涉及文件 / 模块

- `tools/pipeline-templates/resume-cr.pipeline.json`（node-3）
- `tools/skills/cr/cr-show/SKILL.md`（输出契约）

## 实现要点

1. node-3：删除自行读取组织 `_backlog.yml`/`cr.md`/PRD/SDD/TASK/test-report/review annotations/最近三次 push-progress/`crctl next`/`crctl status` 的字段清单与账本定位规则；改为调用 `cr-show`（`cr-id`、`section: all`）并消费其结构化详情，下一步由 cr-show 内部调用 `crctl next` 计算。
2. cr-show SKILL.md：输出契约增加「最近三次 checkpoint」展示项（batchId/时间/phase），保留现有 `section` 参数语义；cr-show 已内部调用 `crctl next`，无需重复声明。
3. FR-09：node-3 不残留章节/路径/索引描述。

## 验收条件

1. node-3 prompt 无 `_backlog.yml`/`review-annotations`/`crctl status` 字面量，含 `cr-show`（cr-id + section=all）。
2. cr-show SKILL.md 输出契约含最近三次 checkpoint 项。
3. JSON 可解析；节点数不变；`lint-prompts.mjs` 无新增触发。

## 完成标志

上述 3 条验收全部通过，`git diff` 仅含本 TASK 列出的两个文件。

## 接口契约

- 消费：cr-show SKILL.md 现行输出契约（section 参数、内部 crctl next）。
- 产出：resume-cr node-3 收敛版 + cr-show 输出契约扩展（最近三次 checkpoint）。
