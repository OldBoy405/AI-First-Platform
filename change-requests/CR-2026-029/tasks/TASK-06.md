---
id: CR-2026-029-TASK-06
type: TASK
cr-ref: CR-2026-029
plan-ref: "change-requests/CR-2026-029/plan.md"
sdd-ref: "change-requests/CR-2026-029/sdd.md"
title: 全量验证与发布
slug: release-verify
status: pending
estimate: 1h
depends-on: [CR-2026-029-TASK-03, CR-2026-029-TASK-05]
created: "2026-08-10T20:14:00+08:00"
---

# TASK-06 全量验证与发布

## 1. 任务描述

执行全量验证（crctl 套件、writeback 套件、语法检查、三件套、pipeline JSON、七禁止模式定向检索），生成 test-report，按发布顺序 merge tools → knowledge-base。

## 2. 涉及文件

- knowledge-base：`change-requests/CR-2026-029/test-report.md`（crctl test 生成）

## 3. 实现要点

- 验证命令：crctl.test.mjs、writeback.test.mjs、node --check、check-skill-matrix、check-agents-contract、lint-prompts enforce、pipeline JSON parse、git diff --check；
- 发布顺序：tools 先行（新 skill/pipeline 语义生效），knowledge-base 随后（迁移带至 trunk）。

## 4. 验收条件

1. 全部验证命令 pass；
2. 双仓 merge 成功、无冲突；
3. 本 CR 进入 writing-back。

## 5. 接口契约

- **消费**：TASK-03/05 产物。
- **产出**：test-report.md、merge 提交。
