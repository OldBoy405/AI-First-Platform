---
id: CR-2026-041-TASK-07
type: TASK
cr-ref: CR-2026-041
plan-ref: "change-requests/CR-2026-041/plan.md"
sdd-ref: "change-requests/CR-2026-041/sdd.md"
title: 退役 feedback-writeback
slug: retire-feedback-writeback
status: pending
estimate: 3h
depends-on: []
created: 2026-08-15T22:05:40+08:00
---

# TASK-07 退役 feedback-writeback

## 1. 任务描述

删除 `feedback-writeback` Skill（只有 prompt 契约、会直接手写 `traceability.yml`/`tech-notes` 并发送与 canonical 语义冲突的 inbox），并清理 active 引用。保留 `CUSTOM.md#CUSTOM-TODO-010` 与 `CONTEXT.md` 的终态反馈事实模型描述（不新建实现）。对应 FR-07。

## 2. 涉及文件 / 模块

删除：

- `skills/cr/feedback-writeback/SKILL.md`

编辑（清 active 引用）：

- `skills/_index.yml`（`feedback-writeback` 条目）
- `agent-skill-matrix.yml`（system-orchestrator owns 的 `feedback-writeback`）
- `AGENT-SKILL-MATRIX.md`（`system-orchestrator` 行）
- `agents/_index.yml`（若含引用）
- `README.md`（若含 `feedback-writeback` 行）
- `docs/QODER-使用指南.md`（第 763 行「CR 反馈回写」示例）
- `openwiki/architecture/agent-skill-matrix.md`（`system-orchestrator` 行）
- `skills/cr/inbox-emit/SKILL.md`（第 31/38/51 行：`feedback-writeback` 触发方、`feedback-writeback-done` allowlist 项）

保留不改：

- `CUSTOM.md#CUSTOM-TODO-010`（终态反馈事实受控写回的建设条件登记）
- `CONTEXT.md`（终态反馈事实领域模型）

## 3. 实现要点

- 删除只针对 active 能力声明；`docs/二开修改报告_v2.html`、`docs/AI-First-研发协同平台-架构讲解.html` 历史快照保留（PRD FR-07.5）。
- `inbox-emit/SKILL.md` 删除 `feedback-writeback-done` 从触发方列表、allowlist 与 `event` 枚举。
- 不新建替代模型 / 占位 Skill / 空字段。
- 每次编辑后跑 `check-skill-matrix.test.mjs` / `check-agents-contract.test.mjs` / `contract-scan.test.mjs`。

## 4. 验收条件

1. `rg -n "feedback-writeback|feedback-writeback-done"` 在 active 路径（skills/_index.yml、agent-skill-matrix.yml、AGENT-SKILL-MATRIX.md、agents/*、README.md、docs/QODER-使用指南.md、openwiki/architecture/agent-skill-matrix.md、skills/cr/inbox-emit/SKILL.md）零命中。
2. `CUSTOM.md#CUSTOM-TODO-010` 与 `CONTEXT.md` 中终态反馈事实描述保留且未被实现化。

## 5. 完成标志

退役静态扫描测试（TASK-08）通过，且本 CR 全部 contract 测试通过。

## 6. 接口契约

- **消费**：无。
- **产出**：active 能力面收敛（`feedback-writeback` 与 `feedback-writeback-done` 从索引/矩阵/Agent/README/docs/openwiki/inbox allowlist 移除），供 TASK-08 静态扫描验证。
