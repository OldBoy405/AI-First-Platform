---
id: CR-2026-027-TASK-08
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: review-record 输出深化 + 四个 review Skill 删除 traceability 二次读取
slug: review-record-output-deepen
status: pending
estimate: 8h
depends-on: ["CR-2026-027-TASK-01"]
created: "2026-08-09T23:35:00+08:00"
---

# TASK-08 — review-record 输出深化（FR-13）

## 任务描述

`review-record` 返回对象增加真实消费者字段（files/attempt/route/repairTarget），并删除四个 review Skill 的「重新读取 traceability 核对刚写入结果」步骤。

## 涉及文件 / 模块

- tools `skills/shared/crctl/scripts/crctl.mjs`（`cmdReviewRecord` 返回对象）
- tools `skills/shared/crctl/scripts/test/crctl.test.mjs`
- tools `skills/requirement/review-requirement/SKILL.md`、`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/develop/review-code/SKILL.md`

## 实现要点（SDD §3.5）

1. `cmdReviewRecord` 保持 `file`、`trace` 兼容，返回对象新增：
   - `files[]`：只列本次实际写入（annotation + traceability；bumped 时才含 review-loop.yml）
   - `attempt.{current,max,bumped}`：从 review-loop 当前轮次读取（bumped = 本轮是否递增）
   - `route`/`repairTarget`：按 stage 判定真值表——任意 stage pass → `route: 'pass'`、`repairTarget: null`；非 dev-plan block → `repair` + `REVIEW_REPAIR_TARGETS[stage]`；dev-plan block 默认 → `repair` + `write-dev-plan`；dev-plan block 且顶层 `repair-target=write-tech-design`（resolveDevPlanRoute 既有判定）→ `upstream` + `write-tech-design`
   - 不返回 `verified`、subject digest、`next`
2. 四个 review Skill：删除「review-record 成功后重新读取 traceability 核对投影」步骤，改为：按返回 `files` 组织提交、按 `route` 分流（repair/upstream 路由到对应回修）、最后调用 `crctl next`

## 验收条件

1. `review-record` 输出含 `files[]`/`attempt`/`route`/`repairTarget` 且与本次实际写入一致（未 bump 不虚列 review-loop.yml）（AC-18）
2. pass 时 `route: 'pass'` 且 `repairTarget: null`；非 dev-plan block → `repair`；dev-plan 显式上游疑点 → `upstream`（TD-BL-2 真值表）
3. 四个 review Skill 无「重新读取 traceability」步骤（grep 校验）
4. `next` 仍由 `crctl next` 唯一计算（命令不返回 next）

## 完成标志

crctl.test.mjs route 真值表用例全绿；四 Skill 修改后 `lint-prompts.mjs --mode enforce` 零发现（M6 复核）。

## 接口契约

- 消费：TASK-01 产出的 tools worktree；TASK-07 的终态 resolver 无耦合（active 路径）
- 产出：`cmdReviewRecord` 扩展输出（`files`/`attempt`/`route`/`repairTarget`）；四个 review Skill 修订；TASK-10 的 AC-18 与 lint 复核基于本产出
