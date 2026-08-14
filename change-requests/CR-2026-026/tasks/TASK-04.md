---
id: CR-2026-026-TASK-04
type: TASK
cr-ref: CR-2026-026
plan-ref: "change-requests/CR-2026-026/plan.md"
sdd-ref: "change-requests/CR-2026-026/sdd.md"
title: write-dev-plan / write-dev-tasks 回修支持与 approve-dev-start 表述
slug: repair-support-prompts
status: pending
estimate: 4h
depends-on: ["CR-2026-026-TASK-02"]
created: "2026-08-09T12:55:00+08:00"
---

# TASK-04 — write-dev-plan / write-dev-tasks 回修支持与 approve-dev-start 表述

## 任务描述

为 `write-dev-plan` 与 `write-dev-tasks` 增加 reviewLoop 回修契约（FR-8/FR-9），并同步 `approve-dev-start` 的门禁表述（SDD §8 采纳清单）。

输入条件：TASK-02 已落地（回修后重入 tech-design-reviewed 的状态转换可用）。

## 涉及文件

- `tools/skills/develop/write-dev-plan/SKILL.md`
- `tools/skills/develop/write-dev-tasks/SKILL.md`
- `tools/skills/develop/approve-dev-start/SKILL.md`

## 实现要点（SDD §8 采纳清单 + FR-8/FR-9）

1. `write-dev-plan/SKILL.md`：新增可选参数 `review_feedback` / `self_repair_attempt`；回修模式——逐条消费 blockers 与 repair-instructions 修订同一 plan.md，输出 `fixed-blockers`；只修评审指出问题，不扩散 SDD 范围；回修期间允许 status=tech-design-reviewed（普通轨重放态）。
2. `write-dev-tasks/SKILL.md`：同上新增回修参数与 fixed-blockers 输出；回修时**重新生成** TASK 与 `_index.yml`，不保留已被删除的旧 TASK；允许 status=tech-design-reviewed 重入。
3. `approve-dev-start/SKILL.md`：审批前置表述补充——dev-start 审批前须存在 `review-annotations/dev-plan.yml` 且 passCondition（verdict=pass && blockers=[]）通过；evidence digest 覆盖 dev-plan.yml/plan.md/tasks/_index.yml 三键；TASK 正文漂移不在 digest 承诺范围（FR-11/AC-12a）。
4. 禁止引入账本手工编辑步骤（不变量 2）。

## 验收条件

1. 三个 SKILL.md 通过 `lint-prompts.mjs --mode enforce`。
2. write-dev-plan/write-dev-tasks 含 review_feedback/self_repair_attempt 参数与 fixed-blockers 输出要求；write-dev-tasks 含「回修时重新生成，不保留已删旧 TASK」表述。
3. approve-dev-start 含 dev-plan.yml 存在 + passCondition + evidence digest 三键说明。
4. `grep -rn "手工编辑\|手动改"` 三个文件命中为 0 或仅「禁止」措辞。

## 完成标志

lint-prompts 全绿；三文件契约表述与 SDD §8 一致；无账本旁路。

## 接口契约

- 消费：TASK-02 的 `review-dev-plan:block` 转换（回修后重入 tech-design-reviewed）；TASK-01 的 annotation 顶层 repair-target（approve-dev-start 说明的 passCondition 判据）。
- 产出：`fixed-blockers` 输出约定（TASK-05 的 reviewLoop replayNodes 中 write-dev-plan/write-dev-tasks 节点的回修语义）；approve-dev-start 的 evidence digest 三键表述（TASK-07 测试向量 ⑧ 的文档依据）。
