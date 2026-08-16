---
spec-id: ai-first-platform
version: "0.20.4"
id: CR-2026-043-TASK-02
type: TASK
cr-ref: CR-2026-043
plan-ref: "change-requests/CR-2026-043/plan.md"
sdd-ref: "change-requests/CR-2026-043/sdd.md"
title: sync 显式 ff-only 同步事务与 sync CLI
slug: sync-ffonly-transaction
status: pending
estimate: 10h
depends-on: [CR-2026-043-TASK-01]
created: 2026-08-16T01:00:22+08:00
---

# TASK-02 sync 显式 ff-only 同步事务与 sync CLI

## 1. 任务描述

在 `workspace-transactions.mjs` 新增 `syncWorkspaceToTrunk` 深原语：复用 durable-tx 的 workspace operation（lock/journal），实现全仓 preflight、intent 绑定、逐仓重核、唯一 `merge --ff-only` 写操作与只向前恢复；在 `durable-tx.mjs` 登记 2 个故障点；在 `crctl.mjs` 接线 `workspace sync` 子命令（局部 catch、失败前审计）。对应 FR-03、FR-04（SDD Phase B）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（新增 sync 事务）
- `skills/shared/crctl/scripts/lib/durable-tx.mjs`（FAULT_POINTS 追加 2 条）
- `skills/shared/crctl/scripts/crctl.mjs`（cmdWorkspace sync 分支、HELP）
- `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs`（事务用例）

## 3. 实现要点

- 事务骨架按 SDD §4.2：`acquireLock({ root, scope: 'workspace-sync-'+cr, op:'workspace' })` → `loadExistingJournal({op:'workspace', cr})` 分流。
  - 非 complete journal：校验 graphDigest 未漂移；只用 payload.repos 的原始 beforeSha/targetTrunkSha；已到 targetSha→confirmed，仍在 beforeSha→pending，其余→`WORKSPACE_FRESHNESS_CHANGED`。
  - 无在途 journal：锁内全仓 preflight（调用 TASK-01 `classifyWorkspaceFreshness`）；allFresh→`{changed:false, txId:null}` 直接返回（零 journal）；任一阻断→抛对应 TxError（零 journal）；syncable→生成 `intentDigest=sha256(canonicalJson({graphDigest, cr, repos:[{repo,beforeSha,targetTrunkSha}]}))`（repos 按 id 排序）。
  - latest complete 且 `complete.inputDigest==intentDigest` 但当前又 syncable → `WORKSPACE_FRESHNESS_CHANGED`（外部回退保护）；否则 `loadOrCreateJournal({op:'workspace', cr, graphDigest, inputDigest:intentDigest, createAfterComplete:true})`，写 payload 并 save('preflight')，`faultPoint('ws-sync-after-preflight')`。
- 逐仓（repo id 顺序，跳过 confirmed/fast-forwarded）：重核 branch、`status --porcelain` 为空、HEAD==beforeSha、重新 fetch 后 origin/{trunk} SHA==targetTrunkSha；任一漂移→`WORKSPACE_FRESHNESS_CHANGED`（停止后续仓）。唯一写操作 `gitMust(wt, ['merge','--ff-only', targetSha])`；`afterSha=rev-parse HEAD`，`afterSha!=targetSha`→`WORKSPACE_SYNC_CONFLICT`；save('syncing')，`faultPoint('ws-sync-after-repo')`。
- 结束 save('complete')，返回 SDD §2.2 `SyncResult`（含 recoverCommand=同一 sync 命令）。不得 reset/revert/删除 journal。
- `crctl.mjs` sync 分支：局部 try/catch；成功/no-op 先 `auditLog(kind:'workspace-sync', {cr, txId, phase, changed, repos[...]})` 再 `ok(...)`；TxError 先写失败 audit（含 e.extra）再 `fail(...)`。
- 测试：ff-only 成功且 afterSha==target；全 fresh no-op 零 journal；dirty/diverged/unknown 零写入；preflight 阻断零 journal；`ws-sync-after-repo` 故障注入后续跑只用原始 intent；latest complete 后 trunk 再前进创建新事务（createAfterComplete）；外部回退到旧 beforeSha→WORKSPACE_FRESHNESS_CHANGED；trunk/HEAD/branch/dirty 竞态漂移→硬失败；并发锁→TX_LOCK_HELD；重跑幂等不重复提交；sync 成功与失败均在 fail/ok 前写 audit。

## 4. 验收条件

1. behind-clean 单仓与多仓 sync 成功：每仓 afterSha==captured trunk SHA，journal phase=complete，audit 含 before/target/after。
2. 任一阻断场景（dirty/diverged/unknown/基础分类/trunk 不可确认）零 worktree 写入且零 journal 创建；部分完成后故障注入重跑只向前、不重复 fast-forward、不执行 reset/revert。
3. `crctl workspace sync` 技术失败（如锁竞争、Git 错误）退出非零且失败 audit 已写入；既有 durable-tx 测试与 FAULT_POINTS 入口校验保持通过。

## 5. 完成标志

`node --test` 下 workspace-freshness 事务用例全部通过 + 既有 crctl/durable-tx 全量回归通过 + lint 零新增报错。

## 6. 接口契约

- **消费**：TASK-01 的 `classifyWorkspaceFreshness(ctx, cr)`、`isAncestorOrThrow(wtPath, a, b)`；既有 `acquireLock`、`loadExistingJournal`、`loadOrCreateJournal`、`saveJournal`、`faultPoint`、`gitRun/gitMust`、`sha256`。
- **产出**：
  - `syncWorkspaceToTrunk(ctx, { cr }) -> Promise<{ cr, txId: string|null, phase:'complete', changed: boolean, repositories: RepoSyncRecord[], recoverCommand: string }>`
  - FAULT_POINTS 新增 `'ws-sync-after-preflight'`、`'ws-sync-after-repo'`
  - CLI `crctl workspace sync <CR-ID> [--workspace <path>]`（供 TASK-03 Skill 消费）
