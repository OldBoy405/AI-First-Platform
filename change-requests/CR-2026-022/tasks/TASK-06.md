---
id: CR-2026-022-TASK-06
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 2.5 — dir-graph 两条 reject 转换 + cmdApprove decline 回退 + approve-* 错误表订正（FR-12）
slug: approve-decline-rollback
status: pending
estimate: 8h
depends-on: [CR-2026-022-TASK-04]
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-12（2.1-H + 评审 B3 修复）：approve 驳回后真正执行状态机回退转换；需求阶段与 dev-start 阶段各补一条 reject 转换（状态机 23→25 条声明，45→47 条展开）；四份 approve-* SKILL 错误表与状态机对齐。

## 涉及文件 / 模块

- `tools/dir-graph.yaml`：`change-request-track.state_machine.transitions` 新增两条：
  - `{ from: requirement-reviewing, to: drafting, trigger: "approve-requirement:reject -> write-requirement-prd" }`（D-1）
  - `{ from: task-breakdown, to: tech-design-reviewed, trigger: "approve-dev-start:reject -> write-dev-plan" }`（B3）
- `skills/shared/crctl/scripts/crctl.mjs`：`cmdApprove` decline 分支（约 :1074-1077）
- `skills/{develop/approve-dev-start,develop/approve-code,develop/approve-tech-design,requirement/approve-requirement}/SKILL.md`：错误处理表
- 口径引用同步：`tools/ARCHITECTURE.md §3`、主仓 AGENTS.md #2、`crctl.test.mjs` 口径断言（如有）

## 实现要点（SDD §2.2/§4.3/D-6）

1. cmdApprove decline 分支改为：
   - 静态映射表 `REJECT_ROLLBACK`（顶部常量）：requirement→drafting、tech-design→tech-designing、dev-start→tech-design-reviewed、code→developing；`approveSkillOf`/`rollbackSkillOf` 同表
   - `findTransition(sm, current, target, trigger)` 查表，无转换 → `fail('APPROVAL_DECLINED', ...)` 维持现状
   - 有转换 → `cmdAdvance({to, trigger, expect: current})` + auditLog `result:'declined-rolled-back'` + `fail('APPROVAL_DECLINED_ROLLED_BACK', '审批未通过，CR 已回退到 {to}，请重跑 {skill}', {rolledBackTo, rerunHint})`（非零退出，D-6）
2. 四份 approve-* 错误表补「审批人回答非 yes」行，与映射表逐一对齐；approve-dev-start 现"重跑 write-dev-plan"的不可达建议改为「CR 回退到 tech-design-reviewed，重新执行 write-dev-plan」
3. approve-requirement「无旁路」表述改为「交互式终端或 Ed25519 签名授权（--grant）二选一，两者都不可绕过审批本身」
4. 口径 25/47 同步更新到 ARCHITECTURE.md §3 与 AGENTS.md #2（若 AGENTS.md 在主仓，注意主仓与 worktree 两处）

## 验收条件

1. 四个 stage 各模拟一次 decline：requirement 回 `drafting`、tech-design 回 `tech-designing`、dev-start 回 `tech-design-reviewed`、code 回 `developing`，均输出 rerunHint
2. decline 后 `crctl status` 显示回退态且 `--grant` 路径不受影响
3. 四份 SKILL 错误表均有对应行；approve-requirement 无"无旁路"字样
4. 口径断言 25/47 全仓一致（grep "23 条声明" 除历史注脚外清零）

## 完成标志

验收 1~4 通过 + crctl.test.mjs 四 stage decline 参数化用例 + 口径断言更新全绿 + 既有 approve 正常路径用例不回归。
