---
id: CR-2026-076-TASK-05
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "next 判定优先级与普通 BLOCK 回修"
slug: crctl-next-priority-block-repair
status: pending
estimate: 12h
depends-on: [CR-2026-076-TASK-04]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-04；AC-09；SDD §4.4）：让 `crctl next` 按固定优先级给出下一步，并让普通 BLOCK 的回修按「对象是否变化」分流，避免要求全量重拆或让 `write-dev-plan` 冒用 `write-dev-tasks` 尚未完成的职责。

背景与输入条件：`dep-16` 结论原文——`cmdNext` 已按状态路由并输出 `next`／`humanApproval`／`why`，是 FR-04 判定优先级与 AC-09 的落点；`dep-17` 结论原文——`devPlanFreshness`／`devPlanCompositeDigest`／`detectNewTechDesignCycle` 已具备 plan／TASK 的对象变化与摘要比较能力，可直接复用，**无需新增摘要体系**。

明确不做：不新增摘要体系、不新增 CR 状态、不新增子命令（§3.1 无参数变更，仅新增可选输出字段）；不把「按 CR-ID／cycle 写死的临时例外」留到本轮之后（§8：同步完成后关闭）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`async function cmdNext(ws, cr, gates, flags)`（:3243）、`function devPlanCompositeDigest(ws, cr)`（:2172）、`function devPlanFreshness(ws, cr, annData)`（:2191）、`detectNewTechDesignCycle`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`：定向用例
- 合同文本：`skills/cr/cr-review-record/SKILL.md`（调用说明与「不重评、不再 bump」约束）、`skills/develop/` 下与回修职责边界相关的 Skill 文本（`write-dev-plan` 不得冒用 `write-dev-tasks` 未完成职责的表述）

## 实现要点

1. 判定优先级严格按 SDD §4.4，顺序不可交换：
   ```text
   ① upstream 路线（review-dev-plan:upstream-design-blocker → write-tech-design）
   ② 耗尽等待合法人类继续（LOOP_EXHAUSTED → humanApproval=true，不自动放行）
   ③ 普通 BLOCK 回修
   ```
2. 对象变化判定（复用既有 subject／composite digest，`dep-17`）：
   - 对象已变 **且** 作者已收尾（plan／tasks 实际提交且状态合法）→ 建议独立复评（`review-dev-plan`／`review-code`）；
   - 对象未变 → 继续回修，**不重复拆任务**；
   - 必需产物缺失／摘要不可计算 → 原修复或技术失败；**无旧摘要不推断「已修好」**。
3. 输出面向后兼容：新增可选 `nextReason` 与 `warnings[]`；既有 `next`／`humanApproval`／`why` 字段与类型不变（§3.1）。
4. 职责边界：`write-dev-plan` 不得冒用 `write-dev-tasks` 尚未完成的职责（回修时 TASK 未落定的情形按 ①／③ 原样路由）。
5. 合同文本同步范围限定为「调用说明与回修边界的表述」，不代改 TASK-06／TASK-07 负责的 warning 分流与去 dev-start 文本。

## 验收条件

1. **AC-09（cmd-04）**：单文件 `crctl.test.mjs` 断言——对象已变且收尾完成时 `next` 返回独立复评节点；对象未变时返回回修节点；upstream／耗尽优先返回对应节点或 `humanApproval=true`；三条分支各有正例与反例。
2. **优先级不可交换**：构造同时满足 ① 与 ③ 的输入，断言命中 ①；构造同时满足 ② 与 ③ 的输入，断言命中 ② 且 `humanApproval=true`（不自动放行）。
3. **兼容面**：既有 `next`／`humanApproval`／`why` 字段在全部状态下的取值与改动前逐字一致（回归断言），新增字段缺省不破坏既有消费者。
4. 运行范围＝`crctl.test.mjs` 单文件，**不声称**覆盖 crctl 全部子命令行为；真实执行输出落 `test-evidence/cmd-04.log`，不新增 plan 未列命令。

## 完成标志

- 优先级与对象变化分支均有用例覆盖，`cmd-04` 真实执行退出码 0 并留证；
- `skills/cr/cr-review-record/SKILL.md` 与相应 `skills/develop/*` 合同文本落盘，且与 §4.4 判定口径一致；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-04 产出 + `dep-16`／`dep-17`，不得缩写）：
- `async function cmdReviewRecord(ws, cr, gates, flags)`（:2200）落盘的 `review-annotations/{stage}.yml` 与 `review-loop.yml` 事实（verdict／blockers／attempt 与 bump 事实）；
- `function devPlanCompositeDigest(ws, cr)`（:2172）、`function devPlanFreshness(ws, cr, annData)`（:2191）——对象变化与摘要比较的既有实现，本 TASK 只消费不改签名；
- `skills/shared/crctl/SKILL.md` 的「无新增子命令」声明（TASK-03 产出）。

产出（供 TASK-07／TASK-08／TASK-10／TASK-17 消费，消费方不得缩写）：
- `async function cmdNext(ws, cr, gates, flags)`（:3243）：回执 `{op, phase, cr, status, next, humanApproval, why, nextReason?, warnings?}`；`nextReason` 为可选字符串（①／②／③ 的机器可读原因），`warnings[]` 为 `{code,message,ref?}` 数组（与 TASK-06 同一形状）；
- 路由目标标识符（与 Pipeline 模板逐字一致）：`write-tech-design`（①upstream）、`write-dev-plan`／`write-dev-tasks`（③回修）、`review-dev-plan`／`review-code`（独立复评）；
- 不新增 CR 状态：`humanApproval=true` 表示等待合法人类继续，**不**对应任何新状态。
