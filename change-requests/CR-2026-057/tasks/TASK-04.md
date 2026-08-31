---
id: CR-2026-057-TASK-04
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: version-set 子命令（FR-15，同构 owner-set）
slug: version-set-subcommand
status: pending
estimate: 14h
depends-on: [CR-2026-057-TASK-01]
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

新账本写入子命令 `crctl version-set <cr_id> --to <real-version>`（FR-15/AC-15）：`unassigned → 真实版本` 的唯一更正入口，原子同步六类文件、幂等短路、零状态副作用。同构复用 owner-set 的 durable ledger 事务骨架，但恢复时点按 B-SDD-005 定稿（允许状态校验 → 恢复 → tracked-clean → 漂移检查）。**不是**新事务框架、新状态、新 Pipeline（NFR-2）。

输入条件：TASK-01 完成；tools CR worktree。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（dispatch 新 `case 'version-set'`、`cmdVersionSet`、`editTargetVersionLine`、HELP 行）
- `skills/shared/crctl/scripts/test/version-set.test.mjs`（**新主题测试文件**，cmd-04）
- `ARCHITECTURE.md`（§3 代码地图一句增量：登记新写入子命令与同构 owner-set 性质，不抄状态机条款）

## 实现要点

1. §4.4 步骤 1→11 顺序实现：缺 `--to` → `BAD_ARGS`；`normalizeTargetVersion(flags.to, { allowUnassigned: false })` 失败 → `VERSION_SET_INVALID`（零写入）；`resolveCrState` 状态不在允许集 → `VERSION_SET_STATE_INVALID`（**禁止状态在恢复之前短路 → 零恢复**）。
2. 步骤 4：`recoverLedgerCommand(ws, ledgerTxKey('version', cr))` ——允许状态校验后、tracked-clean（步骤 5）与漂移检查（步骤 6）之前（B-SDD-005 时序；owner-set 自身顺序不动，zero_diff）。无残留 no-op；未提交写集幂等回滚到 before 快照；已提交按 head+`AI-First-Tx` trailer 识别并清 journal。键 `version/{cr}` 与其它 op 隔离，外部 dirty 不被恢复。
3. 步骤 6 漂移检查（恢复后事务前状态上）：backlog 条目与每个已存在的 prd/sdd/plan/TASK-* frontmatter 缺 `target-version` 或规范化后 ≠ cr.md 值 → `VERSION_SET_DERIVED_DRIFT`；cr.md 值 ≠ `unassigned` 且 ≠ `to.value` → `VERSION_SET_NOT_UNASSIGNED`；cr.md 与全部已存在产物已等于 `to.value` → 幂等短路 `changed:false` 零 commit。
4. 步骤 7 `editTargetVersionLine(text, version)` 行级纯函数：cr.md 先 `\r\n→\n` 规范化；frontmatter `^target-version:` 行替换；`_backlog.yml` 用 `matchEntryBlock` 条目块行替换；匹配不到 → `LEDGER_PARSE_FAILED` 硬失败（NFR-3，禁止静默返回原文）。
5. 步骤 8-9：`beginLedgerCommand(ws, ledgerTxKey('version', cr), writes, true)`（expectedHash 取调用前 SHA）→ 受控 git add（仅受控路径）→ staged 复核 → commit `"[cr] version-set {cr} {from} -> {to}"` + `AI-First-Tx` trailer → `finishLedgerTransaction` → audit。失败回滚 `abortLedgerTransaction` + unstage + clean 复核（错误码 `VERSION_SET_COMMIT_*` 族镜像 `OWNER_*`）。
6. 不调 `updateCrMdStatus`、不发 status 事件、不写 approval.yml；`owner-history`/`handover-history` 不动。
7. 测试（version-set.test.mjs）：正向 unassigned→`0.30` 全链同步（files 六类全列、from/to/changed:true）；幂等重跑 changed=false 零新 commit；负向 `--to unassigned`/畸形 → `VERSION_SET_INVALID` 零写、`merging` → `VERSION_SET_STATE_INVALID` 零写、cr.md 手改真实版本而 PRD 仍 unassigned → `VERSION_SET_DERIVED_DRIFT` 零写、backlog 缺字段 → DRIFT、允许状态抽样 + 终态拒绝。中断重试闭环（B-SDD-005）：`CRCTL_FAULT_POINT=tx-apply-between-rename`（既有通用注入点，FAULT_POINTS 零新增）中断 → 无注入重跑 → 恰 1 个 version-set commit、六类文件全等于 to.value、重试全程无 `VERSION_SET_WORKTREE_DIRTY`/`VERSION_SET_DERIVED_DRIFT`；`ledger-after-commit` 中断 → 重跑 changed=false。禁止状态零恢复：`merging` 夹具预置 `version/{cr}` 残留 → `VERSION_SET_STATE_INVALID` 且 journal/脏文件原样保留。外部 dirty 不被恢复：无残留但工作区有无关 tracked 变更 → `VERSION_SET_WORKTREE_DIRTY`（键隔离证明）。

## 验收条件

1. 正向全链同步：cr.md、`_backlog.yml`、prd/sdd/plan/全部 TASK-*（已存在的）frontmatter 全等 `to.value`；JSON 含 `op/cr/from/to/changed/files`。
2. 幂等：全链已等于 `--to` → `changed=false`、exit 0、零新 commit。
3. 负向四类错误码各零写入；`merging`/`writing-back`/终态零恢复。
4. 中断重试闭环向量全过（无 WORKTREE_DIRTY/DERIVED_DRIFT 误报；恰 1 commit；幂等确认路径 changed=false）。
5. cmd-04 绿（AC-15 全项 + AC-13 全链同步断言）；ARCHITECTURE.md 仅一句增量。

## 完成标志

cmd-04 全绿；AC-15 逐项核对通过；提交 `[cr] implement CR-2026-057 TASK-04`。

## 接口契约

- 消费：`normalizeTargetVersion(raw, { allowUnassigned: false })`（TASK-01）；既有 `ledgerTxKey` / `recoverLedgerCommand` / `beginLedgerCommand` / `queryTrackedChanges` / `rollbackOwnerWrite` 骨架 / `matchEntryBlock` / `findBlockEnd` / 受控 git（复用不改语义，仅调用时点按 §4.4）。
- 产出：
  - `cmdVersionSet(ws, cr, gates, flags)` 入口；stdout `{ op: "version-set", cr, from, to, changed, files: [<workspace-relative paths>] }`；stderr `{error:{code,message}}`。
  - `editTargetVersionLine(text, version) → string`（行级纯函数；匹配不到抛 `LEDGER_PARSE_FAILED`，不返回原文）。
  - 错误码：`VERSION_SET_INVALID` / `VERSION_SET_NOT_UNASSIGNED` / `VERSION_SET_STATE_INVALID` / `VERSION_SET_DERIVED_DRIFT`（业务四枚）+ 基础设施族 `VERSION_SET_WORKTREE_DIRTY` / `VERSION_SET_COMMIT_FAILED` / `VERSION_SET_COMMIT_ROLLBACK_FAILED`。
- 状态副作用：**不**改变 CR status；不写 approval.yml；不产出新 Pipeline/状态/转换。
