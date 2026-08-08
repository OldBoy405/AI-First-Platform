---
id: CR-2026-024-TASK-03
type: TASK
cr-ref: CR-2026-024
plan-ref: "change-requests/CR-2026-024/plan.md"
sdd-ref: "change-requests/CR-2026-024/sdd.md"
title: 端到端验证与回写准备（跨批次全量回归 + lenient 演练整合 + feature-writeback 前置核对）
slug: e2e-verification-writeback
status: pending
estimate: 4h
depends-on: [CR-2026-024-TASK-02]
created: "2026-08-08T22:00:00+08:00"
---

# TASK-03 端到端验证与回写准备

## 1. 任务描述
在批次一/二分别提交并各自三件套通过后，执行跨批次端到端整合验证，确认默认路径零回归、lenient 增量路径行为正确，并为 feature-writeback 做好落点核对。本 TASK 不产生 tools 仓代码改动，是验证与回写前置动作。

## 2. 涉及文件 / 模块（tools 仓 + 本 CR worktree）
- tools 仓三件套脚本（check-skill-matrix / check-agents-contract / lint-prompts）
- 任一在途/历史真实 CR（回归样本）
- `change-requests/CR-2026-024/`（回写落点核对）

## 3. 实现要点（对应 plan §5 验收 checklist）
1. **跨批次全量三件套**：批次一/二合并后再跑一遍三件套，确认无跨批次交互引入的漂移。
2. **strict 默认路径回归**：真实 CR 走 code-implementation，crctl next/status/gate 无越级；评审行为与改动前一致（非阻塞发现进 suggestions、verdict 判据不变）。
3. **lenient 增量路径演练**：显式 suggestion_policy=lenient 触发，验证升格判据（不扩 diff/有明确改法/纯实现层）+ 轮次闸（仅 attempt=1 升格，第 2 轮起 suggestions）+ dimensions.suggestion-policy canonical 留痕 + approve-code suggestions 承接（record-idea 可选落 docs/ideas/）。
4. **溯源与边界核对（FR-24/NFR-10）**：全改动无本机绝对路径；两 commit message 注明方案 v2.6 + CR-2026-024；确认未混入 tools 仓删除态外部文件（.qoder/repowiki 等）。
5. **回写前置核对**：确认 specs/delivery 累积落点策略（AGENTS.md #6，按里程碑分节、禁 cp 覆盖）。

## 4. 验收条件
- 跨批次三件套全绿。
- strict 路径真实 CR 回归零越级、零行为漂移。
- lenient 路径四项（升格判据/轮次闸/canonical 留痕/suggestions 承接）全部生效。
- 溯源与基线隔离核对通过。

## 5. 完成标志
端到端验证全绿 + 回写落点核对完成；任务状态在 `_index.yml` 标记 done；CR 具备进入 feature-writeback 条件。
