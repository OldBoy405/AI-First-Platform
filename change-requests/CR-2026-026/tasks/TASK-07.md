---
id: CR-2026-026-TASK-07
type: TASK
cr-ref: CR-2026-026
plan-ref: "change-requests/CR-2026-026/plan.md"
sdd-ref: "change-requests/CR-2026-026/sdd.md"
title: crctl 测试向量与全量回归
slug: test-vectors-and-regression
status: pending
estimate: 4h
depends-on: ["CR-2026-026-TASK-06"]
created: "2026-08-09T12:55:00+08:00"
---

# TASK-07 — crctl 测试向量与全量回归

## 任务描述

在 `crctl.test.mjs` 追加 SDD §9 的十类向量，并执行全量回归（FR-19/AC-15/AC-15a）。

输入条件：TASK-01~06 全部落地（被测对象存在）。

## 涉及文件

- `tools/skills/shared/crctl/scripts/test/crctl.test.mjs`（追加向量）

## 实现要点（SDD §9 测试设计）

追加向量（沿用 `node --test` + `spawnSync` 黑盒 + `mkdtempSync` 临时目录夹具，零第三方依赖）：
1. **①映射与落盘**：`review-record --stage dev-plan` 在 task-breakdown 落盘 annotation/review-loop/traceability 三账本。
2. **②repair-target schema**：缺省→write-dev-plan；显式 write-tech-design→upstream；非法值→SCHEMA_INVALID 且三账本 sha256 不变。
3. **③UPSTREAM bump 跳过**：payload repair-target=write-tech-design → review-loop current-attempt 不变、attempts 不追加（AC-8b）。
4. **④NORMAL/PASS bump**：普通 block 与 pass 均 attempt+1、attempts 追加。
5. **⑤并存优先**：同轮普通 blocker + repair-target=write-tech-design → 路由 upstream、普通项进 suggestions 摘要。
6. **⑥dev-start GATE_BLOCKED**：无 dev-plan.yml / passCondition 不过 → `crctl approve --stage dev-start` 返回 GATE_BLOCKED、不写合法审批段。
7. **⑦developing 目标态**：删空 TASK-*.md 或篡改 approval.yml#development-start 后 advance --to developing → 门禁拦截（AC-11a）。
8. **⑧EVIDENCE_DRIFT**：审批后修改 dev-plan.yml/plan.md/tasks/_index.yml → 重算 digest 不一致（AC-12）。
9. **⑨LOOP_EXHAUSTED**：三轮 BLOCK → 停止、不进入 human approval（AC-13）。
10. **⑩四 stage 回归**：requirement/tech-design/write-test-report/code 既有 review-record/attempt/gate/approve/traceability 投影测试全部通过（AC-14）。
11. 状态机断言：两条新转换可 advance；口径 27 声明 / 49 展开。

## 验收条件

1. `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全部用例通过（含既有回归 + 新增十一类）。
2. `check-skill-matrix.mjs`、`check-agents-contract.mjs`、`lint-prompts.mjs --mode enforce` 全绿（AC-15/AC-15a）。
3. 测试不含本机绝对路径；无第三方 import。

## 完成标志

全量测试与三件套检查全绿；CR 验收清单（plan.md §5）逐项勾选完成。

## 接口契约

- 消费：TASK-01 的 resolveDevPlanRoute/bump 分支；TASK-02 的 gates/状态机；TASK-03/04/05 的 Skill/pipeline/登记（lint/check 对象）；TASK-06 的文档。
- 产出：回归证据（write-test-report 的输入；CR 验收 checklist 完成依据）。
