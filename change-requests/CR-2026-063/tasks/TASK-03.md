---
id: CR-2026-063-TASK-03
type: TASK
cr-ref: CR-2026-063
plan-ref: "change-requests/CR-2026-063/plan.md"
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
title: "_context.md 活跃合同退役（post-review 白名单删条目 + CR-2026-057 测试原位改为退役合同测试）与活跃引用全量核对"
slug: retire-context-md-active-contract
status: pending
estimate: 8h
depends-on: []
created: 2026-09-11T22:49:24+08:00
---

# CR-2026-063-TASK-03 —— `_context.md` 活跃合同退役与活跃引用全量核对

覆盖 FR：**FR-1③④、FR-2**（SDD §6 FR-1 / FR-2）；变更组 G1；主责仓：`tools`。

## 1. 任务描述

**目标**：把 `_context.md` 从「活跃合同」降为「与任意非白名单文件同等处理」——删除 post-review path drift 白名单中的条目与其注释，并把 CR-2026-057 的「白名单放行」测试**原位**改为「退役合同（拒绝）」测试；同时交付 AC-2 的活跃引用检索证据（计入集合归零 + 排除集合命中清单）。

**背景**：`tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 的 post-review `allowed` 集合当前含 `_context.md` 条目（SDD dep-10），使评审后对它的修改被放行；退役后判定算法不变（SDD §4.4：`unexpected = changedPaths(reviewedSha..HEAD) \ (allowed ∪ review-annotations/ 前缀)`，非空即 `bad('code', { reason:'post-review-path-drift' })`）。

**输入条件**：tools CR worktree；`crctl workspace freshness CR-2026-063`（gate=implement-start）通过；SDD 修订 0.1.4 `e1d44437…` 只读。

## 2. 涉及文件 / 模块

| 文件（相对 tools CR worktree） | 改动性质 |
|---|---|
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | post-review `allowed` 集合：**删除** `_context.md` 条目**与其上方注释**；不新增 `crProcessCachePath()`、不放宽 `classifyRepoWorkspace()` 的 dirty 语义 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | CR-2026-057 的白名单测试**原位改为**退役合同测试（禁止「保留原测试 + 旁边新增反向测试」） |
| （交付证据，落 KB worktree） | AC-2 的检索命令与命中清单（随 test-report 分析段交付；`cmd-03` 提供机械面与清单） |

**不得触碰**（SDD §9 `zero_diff` / `scope_out`）：`lib/durable-tx.mjs`、`crctl.mjs`、`lint-prompts.mjs`、`rules.json`、`yaml-subset.mjs`；历史 CR 目录、历史 `traceability.yml`、归档 delivery 证据。

## 3. 实现要点

1. **删除条目与注释（SDD §6 FR-1③）**：`allowed` 集合中形如 `` `change-requests/${cr}/_context.md` `` 的条目与其上方那行 `_context.md` 说明注释一并删除；集合其余成员、注释风格与函数签名不变。
2. **判定语义不变（SDD §4.4）**：删除后 `_context.md` 与任意其它非白名单文件同等处理——评审后新增或修改 → `post-review-path-drift` 拒绝；**不**新增 `crProcessCachePath()`，**不**放宽 `classifyRepoWorkspace()`。
3. **原位退役测试（SDD §6 FR-1④ / AC-1④）**：把既有「KB 白名单新增 `_context.md` 后继提交 approve-code 通过」用例改写为退役合同断言：① 评审后新增/修改 `_context.md` → `post-review-path-drift` 拒绝（`RELEASE_SUBJECT_DRIFT`）且 `approval.yml` 零写入；② 保留 `_context2.md` 非白名单断言（证明不存在前缀式放宽）。夹具沿用既有 `runCodeReviewAndAdvance` / `makeCodeGrant`。
4. **AC-2 检索证据（SDD §4.5，口径不重新解释、不放宽）**：计入集合 = tools 的 `agents/`、`skills/`、`pipeline-templates/`（排除 `skills/shared/crctl/scripts/test/**`）+ multica 的 `cr-prompts-revised/`，命中数必须为 0；排除集合（`tools/skills/shared/crctl/scripts/test/**`）命中不作归零要求，但**逐条必须读作「拒绝 `_context.md`」语义**，出现任何「放行」正例断言即判不通过。检索命令与命中清单作为交付证据随 test-report 分析段提交（机械面由 `plan.md §6.2 cmd-03` / `cmd-04` 承载，语义判定为人工逐条）。
5. **不得扩大范围**：本 TASK 不改两份 multica 部署副本（`cr-prompts-revised/*`，属 CR-2026-063-TASK-04）；不改 `write-requirement-prd/SKILL.md`（基线红 BR-4 的对象，属 `follow_up`）。

## 4. 验收条件

1. **AC-1③（代码面）**：`workspace-transactions.mjs` 的 post-review `allowed` 集合不再含 `_context.md` 条目，且其上方注释已删；`git diff` 对该文件只显示该删除块。
2. **AC-1④（行为面，机器可判）**：`plan.md §6.2 cmd-01` 中 `crctl.test.mjs` 的退役合同测试通过——评审后新增/修改 `_context.md` ⇒ 返回 `post-review-path-drift`（`RELEASE_SUBJECT_DRIFT`）且 `approval.yml` 零写入；`_context2.md` 仍被拒绝（不存在前缀式放宽）。
3. **AC-2（机械面）**：`plan.md §6.2 cmd-03` 输出 `AC-2 tools accounted-set hits = 0`，并在同一日志里列出排除集合的命中清单（逐条须为拒绝语义）；`plan.md §6.2 cmd-04` 输出 `AC-2 multica accounted-set hits = 0`。
4. **AC-2（人工面）**：把 `cmd-03` 日志中的排除集合清单逐条抄入 test-report 分析段，逐条标注「拒绝语义」判定与证据行。
5. **AC-11（白名单）**：`cmd-03` 的 tools diff 清单只含本 TASK 的 2 个文件与其余 TASK 的白名单文件；`lib/yaml-subset.mjs`、`rules.json`、`gates.json`、`dir-graph.yaml`、`pipeline-templates/**`、`agents/_index.yml` 不出现在清单中。
6. **全量回归**：`plan.md §6.2 cmd-01`（21 个 `*.test.mjs` + 锚定例外模式）exit 0、`skipped=false`。

## 5. 完成标志

- 上述 §4 的 6 条全部实测通过，并留下可复核的命令与输出摘要。
- 本 TASK 触及的文件恰为 §2 的 2 个（tools 侧）；`_context.md` 在计入集合（tools + multica）命中数为 0（multica 侧归零由 CR-2026-063-TASK-04 完成后复核，本 TASK 只对本仓负责并以 `cmd-03` 记录 tools 侧归零）。
- 本 TASK 自行提交：`[cr] CR-2026-063 TASK-03 retire _context.md active contract`（受控 `crctl git` 形态）。
- `crctl task done CR-2026-063-TASK-03 --workspace <KB worktree>` 登记完成。
- **不**改写 `sdd.md` / `prd.md`；**不**修改 TASK-01/02/04 的文件。

## 6. 接口契约

**消费（既有实现，只读复用，SDD dep-10 / dep-12）**

| 符号 | 精确形态与来源 |
|---|---|
| post-review `allowed` 集合 | `workspace-transactions.mjs` L1311–1319（含 L1317–1318 的 `_context.md` 注释与条目）：元素为相对路径字符串；删除后集合其它成员与调用方不变 |
| `bad(code, extra)` → `RELEASE_SUBJECT_DRIFT` / `reason='post-review-path-drift'` | 既有判定出口（SDD §4.4）：`unexpected = changedPaths(reviewedSha..HEAD) \ (allowed ∪ review-annotations/ 前缀)`，非空即拒绝 |
| `classifyRepoWorkspace(ctx, repo, cr)` | 既有（SDD dep-10/§4.4）：本 TASK 不放宽其 dirty 语义 |
| `runCodeReviewAndAdvance` / `makeCodeGrant`（测试夹具） | `crctl.test.mjs` 既有（SDD dep-12）：退役测试的承载夹具 |
| 检索口径 | SDD §4.5（计入/排除集合定义、检索命令、命中清单与判定要求），本 TASK 只执行不重新解释 |

**产出（供下游消费）**

| 产出 | 精确形态 |
|---|---|
| 退役后的 `allowed` 集合 | 同一函数内的路径字符串集合，**不含** `change-requests/${cr}/_context.md`；语义 = SDD §4.4 的「与任意非白名单文件同等处理」 |
| 退役合同测试 | `crctl.test.mjs` 中以 `CR-2026-057` 原始测试名为承载的同一个 `test(...)` 断言块，断言 ① `post-review-path-drift` 拒绝 + `approval.yml` 零写入；② `_context2.md` 仍拒绝 |
| AC-2 证据 | `cmd-03` / `cmd-04` 日志（计入集合命中数 + 排除集合清单）+ test-report 分析段中的逐条语义判定（消费方：CR-2026-063-TASK-04 的收口核对与 `review-code`） |
