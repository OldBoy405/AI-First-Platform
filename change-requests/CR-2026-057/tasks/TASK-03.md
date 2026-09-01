---
id: CR-2026-057-TASK-03
type: TASK
cr-ref: CR-2026-057
plan-ref: "change-requests/CR-2026-057/plan.md"
sdd-ref: "change-requests/CR-2026-057/sdd.md"
target-version: unassigned
title: writeback-apply 版本守卫（FR-14）
slug: writeback-version-guard
status: pending
estimate: 10h
depends-on: [CR-2026-057-TASK-01]
created: 2026-08-31T22:00:00+08:00
---

## 任务描述

`crctl writeback-apply` 入口版本守卫（FR-14/AC-14）：在 `resolveOperationalWorkspace`、traceability replay 分支、`prepareWritebackCandidate`、`loadOrCreateJournal` **之前**执行守卫，版本错误优先于 `WRITEBACK_STATE_MISMATCH`；失败路径零 candidate/journal/authority 痕迹。含 B-SDD-001（守卫不依赖 authority resolver）、B-SDD-002（规范化值回灌）、B-SDD-003（缺 flag 与空串区分）。

输入条件：TASK-01 完成；tools CR worktree。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（新 `guardWritebackVersion`、`applyWritebackAtomic` 顶部插入 + 回灌）
- `skills/shared/crctl/scripts/crctl.mjs`（`cmdWritebackApply` 必填判定改 flag 存在性）
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`（断言适配 + 守卫向量，cmd-03）
- `skills/shared/crctl/scripts/test/merge-fixture.mjs`（`makeCodeApprovedFixture` cr.md 补 `target-version: 0.2`）

## 实现要点

1. 守卫内部（§4.3 第 1 步）：`b = normalizeTargetVersion(input.targetVersion)` → `raw = readCrMdTargetVersion(crWorktreePath(ctx, cr), cr)` → `a = normalizeTargetVersion(raw)` → 按 §2.2 状态模型映射三错误码；**不调用** `resolveOperationalWorkspace`（B-SDD-001）。cr.md 侧缺失/无 frontmatter/缺字段 → 规范化失败 → `WRITEBACK_VERSION_INVALID`。
2. 第 1.5 步回灌：守卫通过后 `input.targetVersion = guard.value`，后续 `canonicalWritebackBusinessInput`、businessInputDigest、manifest、generator `--version` 全部消费规范化串（B-SDD-002）；既有 `startsWith('v')` 剥离保持为防御性 no-op。
3. `cmdWritebackApply`：`!('target-version' in flags)` → `BAD_ARGS`（缺 flag）；显式 `--target-version ""` 放行进守卫 → `WRITEBACK_VERSION_INVALID`（B-SDD-003）。
4. `writeback-tx.test.mjs` 既有「`targetVersion:'0.3'` 重试 → `TX_INPUT_CONFLICT`」断言改为 `WRITEBACK_VERSION_MISMATCH`（新守卫先行命中）；三 stage × {MISMATCH、UNASSIGNED、INVALID} 各断言 §3.2 六项禁止观察点（目标文件哈希、candidates 目录、journal、lock、authority/status、commit/push）；同参重试同码无增量；`status=drafting` 夹具证明版本错误优先（AC-14.6）；显式空串 vs 缺 flag 区分断言；`v0.2`/`V0.2` 输入下 businessInputDigest/manifest `targetVersion` 为 `0.2`。
5. `merge-fixture.mjs` `makeCodeApprovedFixture` cr.md 模板补 `target-version: 0.2`（否则既有 merge 链夹具被守卫判 INVALID，AC-18 红）。

## 验收条件

1. 三 stage × 三错误码向量全过；每次失败后六项禁止观察点字节级成立。
2. 同参重试错误码相同且无增量痕迹；改用合法真实版本且与 cr.md 一致后进入既有 candidate/journal 事务。
3. `status=drafting` 夹具下错误码为 `WRITEBACK_VERSION_*` 而非 `WRITEBACK_STATE_MISMATCH`。
4. 缺 flag → `BAD_ARGS`；显式空串 → `WRITEBACK_VERSION_INVALID`；规范化回灌断言通过。
5. cmd-03 绿（AC-14 全项）；merge-fixture 适配后既有用例不新增失败。

## 完成标志

cmd-03 全绿；AC-14 逐项核对通过；提交 `[cr] implement CR-2026-057 TASK-03`。

## 接口契约

- 消费：`normalizeTargetVersion(raw, { allowUnassigned: true })`、`readCrMdTargetVersion(workspacePath, crId)`（TASK-01）；`crWorktreePath(ctx, cr)`（既有）；`canonicalWritebackBusinessInput` / `prepareWritebackCandidate` / `loadOrCreateJournal`（既有，语义不变）。
- 产出（lib 内新函数，供 `applyWritebackAtomic` 调用）：
  - `guardWritebackVersion(ctx, cr, inputTargetRaw) → { ok: true, value: string }`；失败 `throw TxError(code)`，code ∈ {`WRITEBACK_VERSION_INVALID`, `WRITEBACK_VERSION_UNASSIGNED`, `WRITEBACK_VERSION_MISMATCH`}。
- `applyWritebackAtomic(ctx, input)` 行为变化仅限：入口先守卫后回灌；守卫失败时 replay 分支 / `resolveOperationalWorkspace` / prepare / journal 均未执行。
