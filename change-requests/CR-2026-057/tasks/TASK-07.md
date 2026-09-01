---
id: CR-2026-057-TASK-07
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: review-dev-plan 与 review-code 契约修订（FR-7/FR-9/FR-11/FR-16 评审侧）
slug: review-dev-plan-code-contract
status: pending
estimate: 8h
depends-on: []
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

修订 `review-dev-plan` / `review-code` / `implement-code` 三个 SKILL（FR-1～FR-4 前缀与闭合规则同 TASK-06；本 TASK 另含 FR-7 批准范围前置路由、FR-9 唯一 TASK owner、FR-11 流程控制核验、FR-16 评审侧 skip 语义与「未执行」摘要），以及 `implement-code` 一句越界撤回。只改文本契约，不改状态机 / repair-target 枚举 / review-record schema。

输入条件：tools CR worktree；纯文档修订，可与 M3 并行。

## 涉及文件 / 模块

- `skills/develop/review-dev-plan/SKILL.md`
- `skills/develop/review-code/SKILL.md`
- `skills/develop/implement-code/SKILL.md`

## 实现要点

1. **FR-1～FR-4**：契约域闭合清单、首轮全量、分级、FR-3 前缀表 + 机械核对规则、逐条复核，与 TASK-06 同口径；review-dev-plan / review-code 按科目选用闭合项，缺适用项写 N/A 及原因。
2. **FR-7 批准范围前置核对**：两个 SKILL 在其余维度之前先核对 SDD「批准范围」。路由表（plan §6.3/PRD FR-7）：
   - review-dev-plan：plan/TASK 把批准范围译错、SDD 本身仍正确 → blocker，repair-target=`write-dev-plan`（既有 `review-dev-plan:block -> write-dev-plan`）；批准范围/SDD 设计本身需改 → repair-target=`write-tech-design`（既有 upstream：`review-dev-plan:upstream-design-blocker`）；不得发明第三值。
   - review-code：实际 diff 触碰 `scope_out`、把 `follow_up` 做成当前交付、或改动 `zero_diff` 调用点 → blocker，repair-target=`implement-code`（既有 `REVIEW_REPAIR_TARGETS.code`）；禁止写 `write-tech-design`/`write-dev-plan`；implementer 必须撤回越界 diff。
3. **FR-9**：review-dev-plan 将「关键 AC 无唯一 TASK owner」判为 blocker；覆盖矩阵缺失、关键 AC 证据列非 `cmd-NN` 亦为 blocker。不向 crctl/gates.json 新增静态检查。
4. **FR-11**：review-dev-plan 核验 FR-10（交付 TASK 不得以 merge/writeback/archive 为完成前置）；`deliveryIndexComplete` 与 `crctl task done` 合法状态零改动表述。
5. **FR-16 评审侧（review-code）**：只读机器区 `skipped`/`exit-code`/`timed-out` 与覆盖矩阵 `cmd-NN`，不得自行解析各测试框架输出。关键测试 `skipped:true` → 摘要必须明确「未执行/未测」，不得把单纯 exit 0 叙述成该 AC 已验证；若该命令是某关键 AC 的唯一验收证据 → 必须 blocker（repair-target=`implement-code`），不得仅凭机器区 `status=pass` 进入代码审批；环境不满足（`ENVIRONMENT_MISMATCH`）保持既有技术中止约定，不写成代码 blocker；环境不满足可作为未覆盖风险记录，不等价于关键验收完成。
6. **implement-code**：补一句——code 评审 blocker 若涉范围越界（scope_out/zero_diff/follow_up），implementer 必须撤回越界 diff，不得在实现期扩大范围。
7. 文本约束（R8）：新文本不含 contract-scan 四串；不破坏既有静态断言原文（实施前跑 contract-scan/lint-prompts 确认基线面）。

## 验收条件

1. 两个 review SKILL 均含批准范围前置核对与各自路由表行（repair-target 枚举值仅既有三值）。
2. review-dev-plan 含 FR-9 唯一 owner blocker 规则与 FR-11 核验规则；review-code 含 FR-16 只读机器区规则、`skipped:true` 摘要措辞与唯一证据 blocker 规则。
3. AC-1～AC-4 四节点矩阵中 review-dev-plan / review-code 两行的夹具语义与 SKILL 文本一致（review-code 回修夹具含 repair-target 必须 `implement-code`）。
4. contract-scan 零命中（AC-4）；lint-prompts 通过；`REVIEW_REPAIR_TARGETS` 常量零改动（zero_diff 4）。

## 完成标志

contract-scan 与 lint-prompts 零命中；路由表/矩阵逐项核对通过；提交 `[cr] implement CR-2026-057 TASK-07`。

## 接口契约

- 消费：既有 `review-record` payload（`verdict`/`blockers`/`dimensions`/`suggestions`）、既有 repair-target 枚举（`write-dev-plan`/`write-tech-design`/`implement-code`）、机器区 `skipped` 字段（TASK-05 产出）与 plan 覆盖矩阵 `cmd-NN`。
- 产出：三 SKILL 文本契约；不产出新 CLI、新状态、新转换、新 repair-target 枚举值。
- 本 CR 自身 review-dev-plan / review-code 轮即按本契约执行（AC-6/7/9/10/16 评审行为侧证据载体）。
