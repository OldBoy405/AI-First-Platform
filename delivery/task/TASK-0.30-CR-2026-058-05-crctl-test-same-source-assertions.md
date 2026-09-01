---
spec-id: ai-first-platform
version: "0.30"
id: CR-2026-058-TASK-05
type: TASK
cr-ref: CR-2026-058
plan-ref: "change-requests/CR-2026-058/plan.md"
sdd-ref: "change-requests/CR-2026-058/sdd.md"
target-version: 0.30
title: crctl.test.mjs 同源断言与 AC-4 静态核对
slug: crctl-test-same-source-assertions
status: pending
estimate: 5h
depends-on: [CR-2026-058-TASK-01, CR-2026-058-TASK-02, CR-2026-058-TASK-04]
created: 2026-09-01T16:50:00+08:00
---

## 1. 任务描述

目标：补齐 `crctl.test.mjs` 的 B-SDD-02 同源断言向量（单测层），并完成 AC-4 静态核对（writeback-tx 改写事实 + 既有 AC-14 零观察点保持 + 错误码清单收敛）。本 TASK 是 AC-4 的关键 AC 唯一 owner（证据 cmd-01）。

背景：SDD §6.2 AC-4 要求 `crctl.test.mjs` 含 FR-1 表的正负向量（TASK-01 已落）与 planVersionRefill 语义复核向量（TASK-02 已落）、同源断言向量与 guard source 条件向量；错误码契约按 B-SDD-04 收敛（仅两个新码，同源硬失败复用 `WRITEBACK_STATE_MISMATCH`）。

输入条件：TASK-01（guard 向量）、TASK-02（plan 向量）已在 crctl.test.mjs 落盘且全绿；**TASK-04 已完成**——writeback-tx.test.mjs 改写（UNASSIGNED 期望收敛到 AC-1.2/AC-1.3 冻结负向向量，B-DP-03）是本节 AC-4 静态核对的对象（B-DP-02：本 TASK 依赖 TASK-04）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增同源断言向量 + AC-4 静态断言）

## 3. 实现要点

1. **同源断言向量**（B-SDD-02 单测层，SDD §6.2 AC-3/AC-4 可达性：`resolveRepositories(kb)` + 临时目录直构）：
   - `authority.path !== txws`（或 `source !== 'transaction-workspace'`）时 `planVersionRefill` → `WRITEBACK_STATE_MISMATCH`（复用既有码），extra 保持既有 `{cr, phase}` 形状、authority-mismatch 与两侧路径证据进 message；
   - guard source 条件向量两分支（TASK-01 已落部分，此处补齐边界）：cr-worktree 回退（refill=false）与 txws（refill=true）在 plan 调用侧的行为差异——refill=false 时不调用 `planVersionRefill`（apply 侧由 TASK-03 保证，单测层以 plan 同源断言覆盖）。
2. **AC-4 静态断言——正反语义向量证明（B-DP-03，对象 = TASK-04 改写后的 writeback-tx.test.mjs）**（读文件断言，不引入第二套测试框架）：
   - 正向：文件包含冻结标识 `AC-1.1`/`AC-1.2`/`AC-1.3` 各 ≥1 处（放行向量与两条合法负向向量存在）；
   - 反向：逐 `test(...)` 块结构化核对——含 `WRITEBACK_VERSION_UNASSIGNED` 期望的测试块，其测试名必须含 `AC-1.2` 或 `AC-1.3`（UNASSIGNED 期望只允许存在于两条合法负向向量；「cr.md=unassigned + 真实输入 → UNASSIGNED」旧断言零残留由此可判定）；禁止标识 `AC-1.1-OLD` 零出现；
   - 执行层交叉验证由 cmd-02 的 AC-1.1 放行向量承担（与旧断言同 (fixture,输入) 组合、期望互斥）。
   - 错误码收敛：workspace-transactions.mjs 中新增公开错误码仅 `WRITEBACK_BACKLOG_VERSION_MISMATCH` / `WRITEBACK_BACKLOG_ENTRY_DUPLICATE` 两个；`WRITEBACK_AUTHORITY_DRIFT` 零残留（B-SDD-04）；
   - `guardWritebackVersion` 的 `WRITEBACK_VERSION_UNASSIGNED` 文案与 SDD §4.7 一致（含「仅 cr.md=unassigned 且输入为真实版本时放行并回灌账本」）。

## 4. 验收条件

1. `node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引" skills/shared/crctl/scripts/test/crctl.test.mjs` 通过（exit 0）：新增同源断言与静态断言全绿，既有用例除 BR-1 外不新增失败。
2. 静态核对：本 TASK 新增断言覆盖 AC-4 三项事实（writeback-tx 改写——正反语义向量证明，B-DP-03；错误码收敛；零观察点保持——零观察点在 cmd-02 拒绝路径保持由 TASK-04 断言，此处以 grep 断言 writeback-tx.test.mjs 保留 `snapshotSixPoints` 类调用）。
3. `git diff --name-only` 仅含 `crctl.test.mjs` 一个文件（本 TASK 边界）。

## 5. 完成标志

crctl.test.mjs 全部向量（guard/plan/同源/静态）绿（exit 0）；AC-4 静态核对断言落盘；`_index.yml` 本 TASK 标 done。

## 6. 接口契约

- 消费：TASK-01/02 落盘的 crctl.test.mjs 向量与 `planVersionRefill`/`applyTargetVersionToCrMd`/`editBacklogEntryTargetVersion` 等 export 符号（B-DP-01）；TASK-04 改写后的 `writeback-tx.test.mjs`（正反语义向量静态核对对象，B-DP-02/03）；`resolveRepositories(kb)`。
- 产出（供 TASK-06/TASK-07 消费）：crctl.test.mjs 完整向量集即 cmd-01 证据面；同源断言向量是 B-SDD-02 绑定在单测层的唯一证据；静态断言是 AC-4/AC-5（README 侧由 TASK-06 补）的静态证据。
