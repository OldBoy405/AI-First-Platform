---
id: CR-2026-033-TASK-04
type: TASK
cr-ref: CR-2026-033
plan-ref: "change-requests/CR-2026-033/plan.md"
sdd-ref: "change-requests/CR-2026-033/sdd.md"
title: checkpointCr 事务与 cmdCheckpoint CLI（T04）
slug: checkpoint-tx-and-cli
status: pending
estimate: 24h
depends-on:
  - CR-2026-033-TASK-03
created: 2026-08-13T19:06:07+08:00
---

## 任务描述

实现唯一 Git/账本事务处理器 `checkpointCr` 与 `crctl checkpoint` CLI（dispatch/help/audit/outbox），交付三 bare remote 集成测试矩阵。旧 push-progress/checkpoint-add 本轮不动。

## 涉及文件 / 模块

- 修改 `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（`checkpointCr`）
- 修改 `tools/skills/shared/crctl/scripts/crctl.mjs`（`cmdCheckpoint`、dispatch、help、audit、outbox）
- 新增 `tools/skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs`（三 bare remote 矩阵）

## 实现要点（引用 SDD §3.1/§3.4/§4/§9.2）

1. preflight（§4.1）：`--workspace=<installation-workspace>` 只经 `resolveRepositories` 派生安装根；显式 cr 定位每仓 worktree、registered/branch 校验；KB `cr.md` status 非终态守卫；fetch 记录 remoteBefore；NUL-safe diff/ls-files 收集变化 path；固定敏感路径 + 私钥头命中全仓零 add/commit/push。
2. no-op（§4.2）：全仓未变 + 重算 batch-id 相等 → `changed=false`、`txId=null`、无 journal/push。
3. source commit（§4.3）：`git add -A` → cached diff → commit；先 durable save sourceSha/sideEffect，再复核 clean。
4. publish（§4.4）：checkpoint-specific exact-head 分类；lease push 后精确确认。
5. metadata（§4.5）：全仓静稳检查 → 固定 `kbSourceSha` → batch snapshot → `applyWriteSet` 应用 `_backlog.yml` after image → 只 stage 该文件 → trailer commit → 复核 direct-parent → lease push → 精确确认 → complete。
6. 恢复（§4.6）：journal phase 重扫/re-source/confirm，无 reset/force/补偿。
7. CLI（§3.1/§3.4）：固定成功/no-op/失败 JSON；outbox `dedup_name=checkpoint-{cr}-{metadataCommit}.json` 仅完整批次一次。

## 验收条件

1. 集成矩阵 15 项全覆盖（SDD §9.2 1～15），含安装根调用、敏感零副作用、source/hook 后变化重扫、部分 push 后新增变化、响应丢失、advanced/diverged/history-rewritten、metadata 故障注入。
2. 成功输出含 `op/cr/txId/batchId/phase=complete/repositories[].confirmed/metadataCommit/changed/recoverCommand`；no-op `txId=null`。
3. 错误 JSON 按 SDD §3.5 表返回 code/phase/sideEffects/recoverCommand。

## 完成标志

`crctl checkpoint` 在测试矩阵下全绿；253+10 基线不回归；commit 到 tools 仓 `requirement/CR-2026-033`。

## 接口契约

- 消费：TASK-03 三个纯函数；TASK-02 的 envelope 与 `matchEntryBlock`；TASK-01 的错误码/fault points。
- 产出：`checkpointCr(ctx, {cr, message, workspace}) -> {cr, txId, phase, batchId, repositories, metadataCommit, changed, sideEffects, recoverCommand}`；CLI `crctl checkpoint <cr_id> [--message <text>] --workspace <installation-workspace>`（TASK-05 消费）。
