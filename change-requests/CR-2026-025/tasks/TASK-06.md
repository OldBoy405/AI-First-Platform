---
id: CR-2026-025-TASK-06
type: TASK
cr-ref: CR-2026-025
plan-ref: "change-requests/CR-2026-025/plan.md"
sdd-ref: "change-requests/CR-2026-025/sdd.md"
title: 文档同步与 Prompt 采纳（用途表 + P-1~P-5）
slug: docs-prompt-adoption
status: pending
estimate: 2h
depends-on: [CR-2026-025-TASK-01, CR-2026-025-TASK-05]
created: "2026-08-09T02:30:00+08:00"
---

## 1. 任务描述

按 FR-9 同步用途表与相关表述，并按 SDD §8 的 P-1~P-5 清单完成 Prompt 采纳（纯 prompt 修改随本 CR 同批提交，不另开 CR）。文案必须引用 TASK-01~05 落地后的最终错误码与命令语义。

## 2. 涉及文件

- 修改：`tools/skills/shared/crctl/SKILL.md`（用途表，P-5）
- 修改：`tools/skills/develop/implement-code/SKILL.md`（P-1）
- 修改：`tools/skills/requirement/review-requirement/SKILL.md`（P-2，Step 4）
- 修改：`tools/skills/develop/review-tech-design/SKILL.md`（P-3，Step 4）
- 修改：`tools/skills/develop/review-code/SKILL.md`（P-4，Step 5，已实测 L103-105）
- 条件修改：`tools/README.md`（若含 `task done` 行为描述则同步，FR-9）

## 3. 实现要点

- P-1：implement-code 拓扑排序表述补一句「依赖顺序由 `crctl task done` 机械强制」。
- P-2~P-4：三个 review Skill 的手工 traceability 投影步骤统一改为「投影由 `crctl review-record` 同步写入，本步骤只做落盘后核对」；保留各自的 status 推进/回退表述不动。
- P-5：crctl 用途表 `task done` 行补依赖守卫与两错误码（`DEPENDS_ON_NOT_DONE`/`DEPENDS_ON_UNKNOWN`，非数组形态 `SCHEMA_INVALID`）；`review-record` 行补三账本投影语义一句。
- FR-9：`skills/shared/crctl/SKILL.md` 用途表同步；`README.md` 实施期先 grep `task done`，有行为描述才改，无则记录"无需改动"。
- 顺手项（SDD §7 已知缺口）：`openwiki/architecture/agent-skill-matrix.md` 的"3 项检查"表述同步为 4 项一句。

## 4. 验收条件

1. AC-11：`skills/shared/crctl/SKILL.md` 用途表含 `task done` 依赖守卫与两个新错误码；`implement-code/SKILL.md` 含「由 `crctl task done` 机械强制」一句。
2. P-2~P-4 三处不再指导模型手写 `traceability.yml#reviews.<stage>` 投影（grep 核对）。
3. `node lint-prompts.mjs --mode enforce` 全绿（无 CONTRADICTS/STALE）。

## 5. 完成标志

AC-11 + grep 核对 + lint enforce 全绿 + `_index.yml` 登记 done。

## 6. 接口契约

- 消费：TASK-01 的两错误码终态、TASK-03 的 review-record 投影语义、TASK-04/05 的检查 4 与声明面终态。
- 产出：提示词终态，供 TASK-07 全量验证复跑 lint enforce。
