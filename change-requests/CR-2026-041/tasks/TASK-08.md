---
id: CR-2026-041-TASK-08
type: TASK
cr-ref: CR-2026-041
plan-ref: "change-requests/CR-2026-041/plan.md"
sdd-ref: "change-requests/CR-2026-041/sdd.md"
title: 测试与回归
slug: tests-and-regression
status: pending
estimate: 5h
depends-on:
  - CR-2026-041-TASK-01
  - CR-2026-041-TASK-02
  - CR-2026-041-TASK-03
  - CR-2026-041-TASK-04
  - CR-2026-041-TASK-05
  - CR-2026-041-TASK-06
  - CR-2026-041-TASK-07
created: 2026-08-15T22:05:40+08:00
---

# TASK-08 测试与回归

## 1. 任务描述

补齐本 CR 的测试覆盖（SDD §8）与 FR-03 回归确认：generator/validator 单测、archive gate 单测、退役静态扫描，并跑全量回归。不新增测试框架，沿用既有 `node --test` / 现有 fixture 约定。

## 2. 涉及文件 / 模块

- `skills/writeback/scripts/test/writeback.test.mjs`（新增/扩展 generator + validator 用例）
- `skills/shared/crctl/scripts/test/archive-tx.test.mjs`（扩展证据门 + 分流用例）
- `skills/shared/crctl/scripts/test/contract-scan.test.mjs`（或新增退役静态扫描用例）
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`（FR-03 回归：`WRITEBACK_GENERATORS` 与 `actualGeneratorSha` 保持通过）

## 3. 实现要点

- generator/validator 用例：
  - 证据七项齐全、固定 path map 精确、digest 可复算、CRLF/LF 同 digest、新 milestone 无 status、历史段字节不变、SELF_CHECK。
  - `--validate-evidence` 模式：正常 JSON `ok`；缺失/重复/同 CR 内错误 path/跨 CR 路径/digest 漂移/verdict 非 pass/approval 缺 grant/merge 缺事实 → 结构化 error + 非零退出。
- archive gate 用例：
  - 证据齐全归档成功；证据缺失/漂移/路径互换/状态未通过归档失败且零 journal/authority 写入。
  - pre-authority 分流：无 journal 校验；pre-authority journal 校验且失败不改 journal；已 commit/push 与 cleanup/complete 恢复跳过；rejected/withdrawn 跳过。
- FR-03 回归：不改生产；确认 `WRITEBACK_GENERATORS` 映射（`baseline/tasks/traceability`）与 `actualGeneratorSha` 比对既有用例继续通过。
- 退役静态扫描：active 路径零 `change-impact-analysis` / `feedback-writeback` / `feedback-writeback-done` 引用，且 `CUSTOM.md#CUSTOM-TODO-010` 保留。
- 跨平台：Ubuntu/Windows 全量通过，不引入新生产依赖。

## 4. 验收条件

1. 本 CR 相关测试（writeback.test.mjs、archive-tx.test.mjs、contract-scan 退役扫描）全部通过。
2. 既有全量测试（含 writeback-tx.test.mjs 的 FR-03 回归）不回归，双平台通过。

## 5. 完成标志

`node --test`（Tools 仓全量）通过，Ubuntu/Windows 各跑一次；`git status` 无意外生成物。

## 6. 接口契约

- **消费**：TASK-01~07 全部产出（`readEvidenceInputs`、`validateMilestoneEvidence`、`--validate-evidence`、`runFixedEvidenceValidator`、退役收敛后的索引/矩阵）。
- **产出**：测试用例与回归证明，供 code-review / merge 阶段依据。
