---
id: CR-2026-027-TASK-07
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: status/next 路由修复（终态 resolver + task-breakdown dev-plan 检查）+ inbox-emit 空 to 校验
slug: terminal-resolver-next-route-inbox-emit-guard
status: pending
estimate: 10h
depends-on: ["CR-2026-027-TASK-01", "CR-2026-027-TASK-08"]
created: "2026-08-09T23:35:00+08:00"
---

# TASK-07 — 终态只读查询 + inbox-emit 校验（FR-12/FR-11 收件人面）

## 任务描述

归档后 status/next 不再返回 `CR_STATUS_NOT_FOUND`：新增仅供 status/next 使用的终态只读 resolver；修复 CR-2026-026 遗留的 next task-breakdown 路由缺口（FR-16）；同时修正普通 `inbox-emit` 的空收件人校验（与 Skill 契约对齐）。

## 涉及文件 / 模块

- tools `skills/shared/crctl/scripts/crctl.mjs`（`cmdStatus`/`cmdNext`、`cmdInboxEmit`）
- tools `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点（SDD §3.4/§3.3）

1. 新增 `resolveTerminalCrState(ws, cr)`：仅从 `_history.yml` 读取；输出 `{ status: final-status, terminal: true, source: { history } }`；history 重复条目 → `HISTORY_DUPLICATE_ENTRY` 硬失败；缺 `final-status` → `HISTORY_FINAL_STATUS_MISSING` 硬失败；backlog/history 同存同 CR → `CR_LOCATION_CONFLICT`
2. `cmdStatus`/`cmdNext` 在 active resolver 报 `CR_STATUS_NOT_FOUND` 时 fallback 到终态 resolver：输出 `legalNext: []`、`reviewLoops: {}`、`gateBlockers: {}`、`next: null`（不报错）；cr.md 与 history 不一致时以 history 为准并输出 warning
3. **写命令（advance/approve/checkpoint-add/owner-set/backlog-set/inbox-emit/merge-metadata/review-record 等）不 fallback**，终态写入维持拒绝
4. `cmdNext` 的 task-breakdown 分支（FR-16）：读取 canonical `review-annotations/dev-plan.yml`——缺失/解析失败/缺 verdict 或 blockers → `review-dev-plan`；PASS（verdict=pass 且 blockers=[]）→ `crctl approve --stage dev-start`；BLOCK 时调用 TASK-08 产出的共享 `resolveDevPlanRoute(annotation)`，repair → `write-dev-plan`，顶层 `repair-target=write-tech-design` → `write-tech-design`；block 且当前 cycle exhausted → `next:null`、`humanApproval:true`、why=`LOOP_EXHAUSTED`
5. `cmdNext` 的 tech-design-review-pending 分支（FR-16）：比较 TASK-08 写入的 `sdd.yml#subject-sha256` 与当前 SDD LF digest；较新的 dev-plan upstream blocker 或 digest mismatch → `review-tech-design`；仅 fresh PASS → `crctl approve --stage tech-design`；legacy 无 digest 时有较新 upstream blocker仍必须重审
6. `cmdInboxEmit`：`--to` 缺失、解析后非列表、去重后为空 → `BAD_ARGS`，不写无收件人 notify-log（B-13）

## 验收条件

1. archived/rejected/withdrawn 三种终态 `status` 返回终态与 `source: history`；`next` 返回 `next: null` 不报错（AC-17）
2. backlog/history 同存同 CR → `CR_LOCATION_CONFLICT`；history 重复/缺 final-status → 硬失败
3. cr.md 与 history 不一致 → warning 且以 history 为准；active CR 查询行为不回归
4. 对终态 CR 执行 advance/approve → 维持拒绝（不因 fallback 引入可写性）
5. `inbox-emit` `--to` 缺失/非列表/空 → `BAD_ARGS`，无 notify-log 写入（AC-16）
6. `task-breakdown` 下无/畸形 `dev-plan.yml` → `review-dev-plan`；PASS → `approve dev-start`；repair BLOCK → `write-dev-plan`；upstream BLOCK → `write-tech-design`；exhausted BLOCK → `next:null` + 人工处理（AC-23）
7. `tech-design-review-pending` 下 SDD digest mismatch 或较新 upstream blocker → `review-tech-design`；fresh PASS → `approve tech-design`；legacy annotation 兼容按 SDD §3.4a（AC-23）

## 完成标志

crctl.test.mjs 终态查询 + next 路由/freshness（FR-16）+ inbox-emit 校验用例全绿；既有 status/next/inbox-emit 用例不回归。

## 接口契约

- 消费：TASK-01 产出的 tools worktree；TASK-06 的 archive-move（产生 history 终态条目）；TASK-08 的 `resolveDevPlanRoute`、tech-design subject digest 与 review cycle 字段
- 产出：`resolveTerminalCrState(ws, cr)`（错误码 `HISTORY_DUPLICATE_ENTRY`/`HISTORY_FINAL_STATUS_MISSING`/`CR_LOCATION_CONFLICT`）、`cmdNext` task-breakdown/tech-design freshness 路由（FR-16/AC-23）、`cmdInboxEmit` 空 to 校验；TASK-10 的 AC-16/AC-17/AC-23 验收基于本产出
