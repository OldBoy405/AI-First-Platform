---
spec-id: ai-first-platform
version: "0.27"
id: CR-2026-053-TASK-10
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 集成测试与验收（含 emit-registry.mjs 验证）
slug: integration-test
status: pending
estimate: 4h
depends-on: [CR-2026-053-TASK-01, CR-2026-053-TASK-02, CR-2026-053-TASK-03, CR-2026-053-TASK-04, CR-2026-053-TASK-05, CR-2026-053-TASK-06, CR-2026-053-TASK-07, CR-2026-053-TASK-08, CR-2026-053-TASK-09, CR-2026-053-TASK-11]
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

端到端集成测试，验证完整闭环：
1. tools 仓结构测试与契约校验全绿（FR-A7/AC-A3，含 `emit-registry.mjs --verify`）
2. review Skill 绑定前置步骤与 Multica 绑定接口联调
3. 前端审批卡可见性联动（AC-C1~C6）
4. 存量 CR-2026-051/052 修复验收（AC-D1~D6）
5. 人工审批流程闭环验证（`crctl approve`）

## 涉及文件 / 模块

- 测试文件（按既有测试惯例），不改生产代码（除非修复回归）

## 实现要点

验收清单（按 SDD AC 系列全覆盖）：
- AC-A1~A8: tools 仓改造验收（check-skill-matrix / check-agents-contract / lint-prompts / emit-registry --verify）
- AC-B1~B11: 绑定接口测试覆盖
- AC-C1~C6: 审批卡可见性测试覆盖
- AC-D1~D6: 存量 CR 修复验收

## 验收条件

1. （tools 仓 worktree 根）`node skills/shared/crctl/scripts/check-skill-matrix.mjs && node skills/shared/crctl/scripts/check-agents-contract.mjs && node skills/shared/crctl/scripts/lint-prompts.mjs` 零报错
2. （tools 仓 worktree 根）`node pipeline-templates/emit-registry.mjs --verify` 通过
3. （multica 仓根）`go test ./server/internal/service/... ./server/pkg/db/...` 通过（AC-B1~B11）
4. （multica 仓根）`pnpm exec turbo test --filter='@multica/views'` 通过（AC-C1~C6）
5. E2E：`cr.shell_issue_id` 分别等于 CR-2026-051/052 的 FR-B8 来源 Issue UUID（AC-D1/D2）

## 完成标志

- 测试文件已 commit，全部测试通过
- 四类 review Skill 各跑一轮独立 reviewer，验证 reviewer 与作者为两个独立 task/run

## 接口契约

无接口产出。
