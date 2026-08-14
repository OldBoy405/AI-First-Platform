---
spec-id: ai-first-platform
version: "0.26"
id: CR-2026-025-TASK-05
type: TASK
cr-ref: CR-2026-025
plan-ref: "change-requests/CR-2026-025/plan.md"
sdd-ref: "change-requests/CR-2026-025/sdd.md"
title: 项① 声明面三处修订（顶层块注释 + 声明位置收敛 + 枚举去点名）
slug: external-decl-surface
status: pending
estimate: 2h
depends-on: [CR-2026-025-TASK-04]
created: "2026-08-09T02:30:00+08:00"
---

## 1. 任务描述

落实 FR-4/D-2：顶层 `external-skills:` 块保留不删但标记为纯文档参考，actor 级 `external` 成为唯一被程序解析的权威声明位置（PRD 项①声明面部分）。

## 2. 涉及文件

- 修改：`tools/agent-skill-matrix.yml`（L221 顶层块上方加注释，块内容不动）
- 修改：`tools/AGENT-SKILL-MATRIX.md`（L57 表述收敛）
- 修改：`tools/skills/_index.yml`（L313-317 注释去点名化）

## 3. 实现要点

- `agent-skill-matrix.yml`：`external-skills:` 块上方新增注释「纯文档参考，不被任何程序解析；唯一被 check-skill-matrix 解析的声明位置是 actor 级 external」；块内条目一字不动（D-2：`systematic-debugging` 是 024 SDD §0 C-5 的保留位）。
- `AGENT-SKILL-MATRIX.md`：L57「外部方法论 Skill 只能出现在 `external` 或 `external-skills` 中」改为「只能出现在 actor 级 `external` 中」。
- `skills/_index.yml`：L313-317 逐一点名 6 个外部技能的注释删除具体名称，改写为不点名的通用说明（指向 `agent-skill-matrix.yml` 的 actor 级 `external`），避免随声明增减而过时。
- 改后实跑 `check-skill-matrix.mjs` 确认注释行不干扰解析（顶层块本就不被解析，正则口径 6 空格 vs 2 空格，B-5）。

## 4. 验收条件

1. AC-4 逐条：顶层块仍存在且含「纯文档参考，不被解析」注释；`AGENT-SKILL-MATRIX.md` 不再把 `external-skills` 写成合法声明位置；`skills/_index.yml` 技能名枚举已删、改为不点名说明。
2. `check-skill-matrix.mjs` 与 `check-agents-contract.mjs` 实跑全绿（注释不引入解析副作用）。

## 5. 完成标志

AC-4 对照通过 + 两 checker 全绿 + `_index.yml` 登记 done（本任务为 M3 批次收口）。

## 6. 接口契约

- 消费：TASK-04 的检查 4 已上线（本任务修订的声明面须在其口径下全绿）。
- 产出：三份声明面文件的终态文本，供 TASK-06 文档同步与 TASK-07 全量验证引用。
