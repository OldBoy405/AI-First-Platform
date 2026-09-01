---
id: CR-2026-058-TASK-01
type: TASK
cr-ref: CR-2026-058
plan-ref: "change-requests/CR-2026-058/plan.md"
sdd-ref: "change-requests/CR-2026-058/sdd.md"
target-version: 0.30
title: 窄只读路径解析器与 guardWritebackVersion 判定表重写（FR-1/FR-3）
slug: resolve-writeback-authority-guard
status: pending
estimate: 10h
depends-on: []
created: 2026-09-01T16:50:00+08:00
---

## 1. 任务描述

目标：实现 SDD §4.1 新增窄只读解析器 `resolveWritebackAuthorityPath`，并按 SDD §2.1/§4.2 重写 `guardWritebackVersion` 判定表（FR-1/FR-3）。守卫必须让版本错误优先于 `WRITEBACK_STATE_MISMATCH`，因此**禁止**在守卫内调用会抛 STATE/OPERATIONAL_WORKSPACE 错误的完整 `resolveOperationalWorkspace`。

背景：CR-2026-057 把守卫做成「任一侧 unassigned → 拒绝」，导致已 merge 且账本为 `unassigned` 的 CR 无法 writeback（AIFI-15 死锁）；且守卫经 `crWorktreePath` 读版本，与 writeback authority（txws）分裂。本 TASK 修正读取位置与判定语义。

输入条件：tools worktree 基线 HEAD=`2bb66294db30b116e0d53aea48990611017c75d6`；`workspace-transactions.mjs` 既有 `normalizeTargetVersion` / `readCrMdTargetVersion` / `crWorktreePath` / `txWorkspacePath` / `readCrMdStatus` / `mergeStatus` / `POST_FINALIZE_STATUSES` 可用（SDD §6.3 证据 1）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（改动：新增 `resolveWritebackAuthorityPath` export；重写 `guardWritebackVersion`，**调用签名 `(ctx, cr, inputTargetRaw)` 不变**，返回值扩展）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增 guard 单测向量）

## 3. 实现要点

1. `resolveWritebackAuthorityPath(ctx, cr)`（SDD §4.1）：
   - 返回 `{ path, source }`，`source ∈ {'transaction-workspace', 'cr-worktree'}`；**永不抛** STATE/OPERATIONAL_WORKSPACE 类错误，任何证据不足回退 `{ path: crWorktree, source: 'cr-worktree' }`。
   - 先读 `crWorktreePath(ctx, cr)` 的 cr.md status：∈ `POST_FINALIZE_STATUSES`（merging/writing-back/archived）且 txws 存在且其 cr.md status 也在该集合 → `{ path: txws, source: 'transaction-workspace' }`。
   - status 非 null 时再查 `mergeStatus`（**包 try/catch**，journal 损坏按 `{phase:'none'}` 无证据处理）：`phase==='complete'` 且 `operationalWorkspace` 的 cr.md status ∈ POST_FINALIZE_STATUSES → 返回该路径 + `'transaction-workspace'`。
   - 与 `resolveOperationalWorkspace` 的差异（SDD §4.1 差异表）：不抛错、仅版本比较路径定位、merge journal try/catch。真正的 authority 断言仍由既有 `resolveOperationalWorkspace` 承担。
2. `guardWritebackVersion(ctx, cr, inputTargetRaw)`（SDD §4.2）：
   - `b = normalizeTargetVersion(inputTargetRaw)`；`auth = resolveWritebackAuthorityPath(ctx, cr)`；`a` = `auth.path` 上 `readCrMdTargetVersion` 的规范化值（先 `\r\n→\n`）。
   - 判定表六行：`!a.ok || !b.ok` → `WRITEBACK_VERSION_INVALID`（extra 既有 `cr`/`input`/`inputReason`/`crMdReason`）；`a=unassigned && b=真实 && auth.source==='transaction-workspace'` → 放行 `{ok:true, value:b.value, refill:true, authority:auth}`；`a=unassigned && b=真实 && source==='cr-worktree'` → 放行 `{ok:true, value:b.value, refill:false, authority:auth}`（回灌禁用，后续落 STATE_MISMATCH）；`a=unassigned || b=unassigned` → `WRITEBACK_VERSION_UNASSIGNED`；`a.value !== b.value` → `WRITEBACK_VERSION_MISMATCH`（extra 既有）；全等 → `{ok:true, value:a.value, refill:false, authority:auth}`。
   - `WRITEBACK_VERSION_UNASSIGNED` 文案按 SDD §4.7 改写：`writeback 版本守卫：两侧或输入侧为 unassigned 一律拒绝（cr.md=${a}，输入=${b}）；仅 cr.md=unassigned 且输入为真实版本时放行并回灌账本`。
   - 纯判定 + 一次只读文件读取；无 journal/candidate/lock 痕迹（守卫在 `loadExistingJournal`/`prepareWritebackCandidate`/`acquireLock` 之前执行，SDD §4.4 步骤 1）。
3. crctl.test.mjs 新增 guard 向量（import 模式与既有 `normalizeTargetVersion` 测试一致，SDD §6.2 AC-4 可达性：`resolveRepositories(kb)` 构造 ctx）：
   - FR-1 判定表六行各至少一条（merged 夹具或临时目录直构 cr.md）；
   - authority 快照形状：放行时返回 `{path, source}` 且 source 正确；
   - source 条件两分支：txws 回灌（refill=true）与 cr-worktree 回退（refill=false）；
   - UNASSIGNED 新文案断言（区分两侧/输入侧 unassigned 与已放行）。

## 4. 验收条件

1. `node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引" skills/shared/crctl/scripts/test/crctl.test.mjs` 通过（exit 0）：新增 guard 向量全绿，既有用例除 BR-1 外不新增失败。
2. `guardWritebackVersion` 调用签名 `(ctx, cr, inputTargetRaw)` 不变，返回值含 `{ok, value, refill, authority:{path, source}}`；`WRITEBACK_VERSION_UNASSIGNED` 文案与 SDD §4.7 一致（静态核对）。
3. 代码审阅：`resolveWritebackAuthorityPath` 无任何 throw STATE/OPERATIONAL_WORKSPACE 类错误的路径；`mergeStatus` 调用有 try/catch。
4. `git diff --name-only` 仅含 `workspace-transactions.mjs` 与 `crctl.test.mjs` 两个文件（本 TASK 边界）。

## 5. 完成标志

crctl.test.mjs 新增 guard 向量全部通过（exit 0）；`WRITEBACK_VERSION_UNASSIGNED` 文案已改写；代码 review 自检通过；`_index.yml` 本 TASK 标 done。

## 6. 接口契约

- 消费（本 TASK 使用）：`normalizeTargetVersion(raw)` → `{ok, value}|{ok:false, reason}`；`readCrMdTargetVersion(path, cr)` → `{ok, raw}`；`crWorktreePath(ctx, cr)` / `txWorkspacePath(ctx, cr)` → 路径字符串；`readCrMdStatus(path, cr)` → status 或 null；`mergeStatus(ctx, cr)` → `{phase, operationalWorkspace}`（可能抛，须 try/catch）；`POST_FINALIZE_STATUSES` 常量。
- 产出（本 TASK 暴露给下游）：
  - `resolveWritebackAuthorityPath(ctx, cr)` → `{path: string, source: 'transaction-workspace'|'cr-worktree'}`（export；永不抛 STATE/OPERATIONAL 错误）；
  - `guardWritebackVersion(ctx, cr, inputTargetRaw)` → `{ok: true, value: string, refill: boolean, authority: {path, source}}` 或 throw `WRITEBACK_VERSION_INVALID|UNASSIGNED|MISMATCH`（extra 保持既有形状）。
  - 下游消费方：TASK-02（`planVersionRefill` 的 `authority` 入参语义）、TASK-03（`versionGuard.authority/refill/value`）。
