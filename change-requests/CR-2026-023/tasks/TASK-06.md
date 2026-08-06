---
id: CR-2026-023-TASK-06
type: TASK
cr-ref: CR-2026-023
plan-ref: "change-requests/CR-2026-023/plan.md"
sdd-ref: "change-requests/CR-2026-023/sdd.md"
title: 收尾 — 五步自检 + pre-commit 三件套 + 溯源标注 + 端到端验收（FR-13/14 + AC-11）
slug: final-selfcheck-e2e
status: pending
estimate: 4h
depends-on: [CR-2026-023-TASK-01, CR-2026-023-TASK-02, CR-2026-023-TASK-03, CR-2026-023-TASK-04, CR-2026-023-TASK-05]
assignee: ""
created: "2026-08-07T00:40:00+08:00"
---

## 任务描述

收尾验收：执行 FR-13 五步自检与 pre-commit 三件套，确认 commit 1（块 B 原子）与 commit 2（块 A）的提交编排与溯源标注（FR-14），并跑 AC-11 端到端两场景。

## 涉及文件 / 模块

- 无新增文件改动（纯验证 + 提交编排核对）

## 实现要点（SDD §4.3 + PRD FR-13/14 + AC-10/11）

1. **五步自检**（FR-13）：① 规则上线前 `--mode report` 命中恰为 17；② 测试向量全绿；③ 清零后 `--mode enforce` 归零；④ pipeline JSON 解析自检；⑤ pre-commit 三件套（`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce`）全绿。
2. **提交编排核对**：commit 1 = R9 + 测试 + 17 处清零 + 3 处配套（原子）；commit 2 = pipeline + _index.yml + README；两 commit 无相互依赖、可独立 revert。
3. **溯源标注**（FR-14）：commit message 延续漂移治理编号（R9 条目呼应 prompt-audit-report G5）+ 注明 CR-2026-023 来源；全部改动无本机绝对路径。
4. **端到端**（AC-11）：场景 A 模拟 /coding 走到节点 8 后暂停选择模型、repair 循环不重复询问；场景 B 对新写 PRD 的在途 CR 验证 `crctl next` 推荐 review-requirement 且提示链无等价分叉。

## 验收条件

1. 五步自检 + 三件套全绿；`lint-prompts --mode enforce` 全库 R9 归零。
2. AC-1~AC-11 逐条对照 PRD 勾验通过；commit message 含漂移治理编号与 CR 溯源。

## 完成标志

全部自检绿 + 端到端两场景通过 + AC 全勾验；本 CR 开发期任务完成，进入 review-code。
