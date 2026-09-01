---
id: CR-2026-058-TASK-03
type: TASK
cr-ref: CR-2026-058
plan-ref: "change-requests/CR-2026-058/plan.md"
sdd-ref: "change-requests/CR-2026-058/sdd.md"
target-version: 0.30
title: applyWritebackAtomic 回灌集成（authority 快照绑定 / payload 冻结 / entries 合成 / 恢复协议）
slug: apply-writeback-atomic-refill
status: pending
estimate: 14h
depends-on: [CR-2026-058-TASK-01, CR-2026-058-TASK-02]
created: 2026-09-01T16:50:00+08:00
---

## 1. 任务描述

目标：在既有 `applyWritebackAtomic`（workspace-transactions.mjs）上做 SDD §4.4 的最小插入：authority 快照绑定（第 5.5 步）、回灌计划调用（第 7 步）、journal payload `versionRefill` 冻结持久化（第 11 步）、entries 合成（第 13 步）、baseline cr.md 单条目合成（§4.5）、恢复协议五现场（第 9 步）。**不改变** `crctl.mjs` dispatch、`durable-tx.mjs`（`applyWriteSet`/`recoverWriteSet`/`FAULT_POINTS` 零改动）、`yaml-subset.mjs`、generator 脚本与既有信封形态（SDD §9 zero_diff）。

背景：FR-2 要求回灌与 stage 业务文件、baseline status 变迁同一次 write-set / 同一次 commit；cr.md 全局恰好一条 write-set 记录；B-SDD-01 要求 `payload.versionRefill` 落盘即冻结、恢复按 manifest/phase 向前恢复。

输入条件：TASK-01（`versionGuard.authority/refill/value`）、TASK-02（`planVersionRefill` 产物）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（改动：`applyWritebackAtomic` 插入点 + baseline 合成分支）

## 3. 实现要点

按 SDD §4.4 步骤编号实现：

1. **第 5.5 步 authority 快照绑定**：`resolveOperationalWorkspace`（第 4 步，既有）返回 opWs 后立即校验 `versionGuard.authority.source === 'transaction-workspace' && versionGuard.authority.path === opWs.path`；不一致 → throw `WRITEBACK_STATE_MISMATCH`（**复用既有码**，extra 保持既有 `{cr, phase}` 形状，guardSource/guardPath/opPath 证据进 message——不新增公开错误码，B-SDD-04）。该检查先于 business/candidate/journal/lock，失败零写入。
2. **第 7 步回灌计划**：`if (versionGuard.refill) refillPlan = planVersionRefill({ txws: opWs.path, authority: versionGuard.authority, cr, stage, version: versionGuard.value })`；在 candidate 生成（`prepareWritebackCandidate`）与 journal 创建之前，FR-2.1 时序成立。
3. **第 9 步恢复协议（B-SDD-01 冻结）**：found 分支（journal 已存在）若 payload 已含 `versionRefill` → **保留首次 payload，禁止重算/覆写**（第 7 步重算的 plan 仅作纯读 fail-fast、不落入 payload）。按既有 write-set manifest/phase 区分现场：
   - a) manifest 缺失（`writeback-after-journal-create` 中断，文件未动）→ entries 从 payload 持久化条目重建，`applyWriteSet` 首轮落盘；
   - b) manifest state=`prepared`（rename 间部分 apply，可能 backlog 已 after、cr.md 仍 unassigned）→ `recoverWriteSet` 按 manifest 补齐；entries 从 payload 重建（与 manifest 同路径同哈希），`applyWriteSet` 全 skip；两账本路径保留在 entries/git add/files 内（不因重算把 backlog 条目降为 null）；
   - c) manifest state=`complete`（已全量落盘、commit 前）→ entries 从 payload 重建，`applyWriteSet` 全 skip，补 `git add`+commit；
   - d) 本轮 `versionGuard.refill === false` → 校验 `payload.versionRefill.inputVersion === versionGuard.value`，不一致 → `TX_INPUT_CONFLICT`（既有码，硬阻断）；entries 只用 payload 持久化条目，不回算 after；
   - e) 防御：guard 仍 `refill=true` 但 payload 无 `versionRefill`（部署前旧守卫的在途 journal）→ `TX_INPUT_CONFLICT` 硬阻断、零写入、人工处置。
4. **第 11 步 payload 持久化**：`created=true` 时（`loadOrCreateJournal`）写入 `payload.versionRefill = { inputVersion, crMd: RefillEntry|null, backlog: RefillEntry|null }`（含 path/beforeSha256/afterSha256/afterText 全文），随既有 `save('start')` 落盘，不新增 phase；`created=false` 不触碰（冻结）。
5. **第 13 步 entries 合成**：既有 `snapshot.files` + `statusTransition` 之后追加：`payload.versionRefill?.backlog` → entry（path/beforeSha256/afterSha256/content=afterText）；`payload.versionRefill?.crMd` → entry（tasks/traceability 侧）。**只依赖 payload，不依赖瞬时 refillPlan**（B-SDD-01）。
6. **§4.5 baseline cr.md 单条目合成**：`statusTransition` 构建处改两分支——回灌分支（`payload.versionRefill` 存在且本块未被持久化跳过）：底本 = `refillPlan.crMdBase.text`（plan 语义复核文本，B-SDD-02 绑定），`crMdStatusText(..., 'writing-back', {at})` 后 `applyTargetVersionToCrMd(afterText, payload.versionRefill.inputVersion)`，`beforeSha256 = refillPlan.crMdBase.sha256`；非回灌分支与今日行为完全一致（`advanceCandidate.beforeText/beforeSha256`）。`advanceCandidate` 回调仍被执行（gate 检查副作用保留，`validateBaselineAdvance` 零改动）。`crMdStatusText` 返回 null 时既有 `WRITEBACK_STATUS_INVALID` 硬失败保留。
7. **cr.md 全局恰好一条 write-set 记录**：baseline = `statusTransition` 条目（afterText 已含版本行），`payload.versionRefill.crMd=null`；tasks/traceability = `payload.versionRefill.crMd` 条目（`statusTransition=null`）。二者互斥。
8. **故障边界（FR-2.2，零新增 fault-point）**：`writeback-after-apply` → 第 13–14 步之间天然含两账本 + 业务文件 after 映像；`writeback-after-commit` → `payload.committed=true` 短路 commit 段只 push+complete；`writeback-after-push` → `pushed=true` 短路 push 段只补投影与 `save('complete')`。**无**「先滚回 unassigned」代码路径。

## 4. 验收条件

1. 静态核对：SDD §4.4 步骤 1–14 的插入点（第 5.5/7/9/11/13 步 + §4.5）在代码中逐项存在且语义一致（对照 SDD 原文逐条比对）。
2. zero_diff 面零改动：`git diff --name-only` 仅含 `workspace-transactions.mjs`；`durable-tx.mjs` / `yaml-subset.mjs` / `crctl.mjs`（dispatch/flag 面/`fail()`/`ok()`/`runTxAsync`）/ `FAULT_POINTS` 登记表 / `statusTransition` 既有字段 / `verifyReleaseSubjects` 白名单零改动。
3. `node --test --test-reporter=dot skills/shared/crctl/scripts/test/writeback-tx.test.mjs` 通过（exit 0）：既有 14 用例（含 AC-14 观察点）不被集成改动破坏。
4. `node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引" skills/shared/crctl/scripts/test/crctl.test.mjs` 通过（exit 0）：既有用例不新增失败。
5. 代码审阅：payload `versionRefill` 只写一次（`created=true` 时）；found 分支无任何覆写路径；entries 合成只读 payload。

## 5. 完成标志

插入点清单与 zero_diff 核对通过；writeback-tx.test.mjs 既有用例与 crctl.test.mjs 既有用例全绿；`_index.yml` 本 TASK 标 done。

## 6. 接口契约

- 消费：TASK-01 `guardWritebackVersion` 返回值（`authority/refill/value`）；TASK-02 `planVersionRefill` 返回值与 `RefillEntry` 形状；既有 `applyWriteSet` / `recoverWriteSet` / `faultPoint` / `loadOrCreateJournal` / `saveJournal` / `resolveOperationalWorkspace` / `resolveWritebackCandidate` / `readPreparedCandidate`（`blobText`）/ `crMdStatusText` / `advanceCandidate`（`beforeText`/`beforeSha256`）。
- 产出（供 TASK-04 消费）：journal payload 新字段 `writeback.versionRefill = { inputVersion, crMd: RefillEntry|null, backlog: RefillEntry|null }`（落盘即冻结）；回灌分支 CLI 成功信封 `phase="complete"`、`changed=true`、`files` 含 `change-requests/{CR-ID}/cr.md` 与 `change-requests/_backlog.yml`（经既有 `payload.files` 投影，FR-6.1）；失败信封保持既有 `fail(code, message, extra)` 扁平形状（FR-6.2）。
