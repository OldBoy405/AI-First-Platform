---
id: CR-2026-076-TASK-16
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "PRD 交接完整性核对记录"
slug: prd-handover-integrity-check
status: pending
estimate: 8h
depends-on: []
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-SUP-09 本 CR 部分；AC-SUP-10；SDD §4.17）：以机械事实核对需求节点交接完整性——`_backlog.yml#prd-path` 指向**分支内实际存在**的 PRD 文件、PRD 保留 `FR-SUP-01…09` 与 `AC-SUP-01…10` 编号、需求评审 `verdict=pass`，并把原样结果落成核对记录。

背景与输入条件：本 PRD 已实质覆盖 `AC-SUP-01～AC-SUP-10` 并保留原 FR／AC 编号（逐条核对见 SDD §6）；本条在本 CR 的实现形态是 writer 自审 + 独立需求评审的交付检查（已由 `review-annotations/requirement.yml` 落地）。

明确不做：**不**建设语义覆盖检查器、**不**扩大为平台新功能；本命令不产生正确性结论，只记录机械事实（与 AC-SUP-10「不能只检查字符串数量」不冲突——实质覆盖由 `review-annotations/requirement.yml` 独立评审判定）。

## 涉及文件 / 模块

- `change-requests/CR-2026-076/test-evidence/prd-handover-check.md`：**新建**核对记录（原样结论与命令事实）
- 只读输入（不修改）：`change-requests/_backlog.yml`、`change-requests/CR-2026-076/prd.md`、`change-requests/CR-2026-076/review-annotations/requirement.yml`
- 仓库：`ai-first-platform-docs`（knowledge-base CR worktree，`cwd=.`，本 CR 在 KB 侧**无代码变更**）

## 实现要点

1. 核对内容与 `cmd-13` 的行为逐项一致（命令形态唯一事实源 = plan §6.2 cmd-13 行，本 TASK 不得另写第二套命令）：
   - `_backlog.yml` 中 `CR-2026-076` 条目的 `prd-path` 解析 → 该文件在**当前分支内**存在；
   - 存在时打印 `prd-path` 与 `sha256`（按 `\r\n → \n` 归一后计算，遵守行尾纪律）；
   - PRD 中 `FR-SUP-01…FR-SUP-09` 与 `AC-SUP-01…AC-SUP-10` 逐号存在并打印出现次数；
   - `review-annotations/requirement.yml` 含 `verdict: pass`。
2. 核对记录写作要求：只记录上述机械事实（命令、原样输出、`sha256`、逐号出现次数），**不**下「需求已实质覆盖」的结论——该结论的权威来源是独立需求评审判定。
3. 任一项失败 → 非零退出（命令自身），并把失败原因原样落记录；不得静默降级或改判为通过。
4. 状态从 `/cr.md` 读取的口径（TASK-15 同源）不适用于本 TASK；本 TASK 只读 `_backlog.yml` 的 `prd-path` 字段。

## 验收条件

1. **AC-SUP-10（cmd-13）**：需求节点交接完整——PRD 实质覆盖 `AC-SUP-01～10`、保留编号、`prd-path` 指向分支内实际文件；`cmd-13` 真实执行退出码 0。
2. **机械事实可复核**：核对记录内含 `prd-path` 值、PRD 文件 `sha256`、`FR-SUP-01…09` 与 `AC-SUP-01…10` 的逐号出现次数、`verdict: pass` 的原样依据。
3. **不产生正确性结论**：记录中不出现「已实质覆盖」类断言（断言文本不含此类结论句），也不新增任何语义检查器代码。
4. 运行范围以 plan §5.5 为唯一事实源：命令在 KB CR worktree 根目录执行（`repo=ai-first-platform-docs`、`cwd=.`）；**不声称**以字符串计数证明实质覆盖。真实执行输出落 `test-evidence/cmd-13.log`，不新增 plan 未列命令。

## 完成标志

- `change-requests/CR-2026-076/test-evidence/prd-handover-check.md` 落盘且内容为原样机械事实；`cmd-13` 真实执行退出码 0，原样输出落 `test-evidence/cmd-13.log`；
- KB 侧无代码变更（`ai-first-platform-docs` 只新增本 TASK 的记录与证据文件）；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（既有事实，只读）：
- `change-requests/_backlog.yml` 的 `CR-2026-076` 条目字段 `prd-path`；
- `change-requests/CR-2026-076/prd.md`（PRD 正文与编号）；
- `change-requests/CR-2026-076/review-annotations/requirement.yml` 的 `verdict` 字段（需求评审判定，`dep-19` 同源的只读证据面）。

产出（供 TASK-17 的实际发布生效核对与回写期消费，消费方不得缩写）：
- 证据文件（路径为硬契约）：`change-requests/CR-2026-076/test-evidence/prd-handover-check.md` 与 `change-requests/CR-2026-076/test-evidence/cmd-13.log`；
- 交接完整性事实：`prd-path` → 分支内实际文件（存在 + `sha256`）、编号保留（逐号计数）、需求评审 `verdict=pass`；
- 边界契约：本 TASK 不产出正确性结论，也不新增检查器；任何后续「语义覆盖」判定必须走独立评审，不得回填为 TASK 产物。
