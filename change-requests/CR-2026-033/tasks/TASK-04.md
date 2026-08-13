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
- 修改/扩展 `tools/skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs`（TASK-01 红测扩展为三 bare remote 矩阵）

## 实现要点（引用 SDD §3.1/§3.4/§4/§9.2）

1. journal 业务 payload（workspace-transactions 所有）：计算 `inputDigest = sha256(JSON.stringify({cr, graphDigest}))`；创建/恢复时校验 checkpoint object、repositories 非空且 repo 唯一、`repo/remoteRef/baseSha/sourceSha/remoteBefore/phase`、`batchId/kbSourceSha/metadataCommit` 的类型/格式与 phase 枚举；加载后的业务 payload 与恢复事实不一致时用 SDD §3.5 已冻结的 `TX_RECOVERY_CONFLICT` 硬失败。不得把这些规则下沉 durable-tx。
2. preflight（§4.1）：`--workspace=<installation-workspace>` 只经 `resolveRepositories` 派生安装根；显式 cr 定位每仓 worktree、registered/branch 校验；KB `cr.md` status 非终态守卫；fetch 记录 remoteBefore；NUL-safe diff/ls-files 收集变化 path；固定敏感路径 + 私钥头命中全仓零 add/commit/push。
3. no-op（§4.2）：全仓未变 + 重算 batch-id 相等 → `changed=false`、`txId=null`、无 journal/push。
4. source commit（§4.3）：`git add -A` → cached diff → commit；先 durable save sourceSha/sideEffect，再复核 clean。
5. publish（§4.4）：checkpoint-specific exact-head 分类；lease push 后精确确认。
6. metadata（§4.5）：全仓静稳检查 → 固定 `kbSourceSha` → batch snapshot → `applyWriteSet` 应用 `_backlog.yml` after image → 只 stage 该文件 → trailer commit → 复核 direct-parent → lease push → 精确确认 → complete。
7. 恢复（§4.6）：先验证加载的业务 payload，再按 journal phase 重扫/re-source/confirm，无 reset/force/补偿。
8. CLI（§3.1/§3.4）：固定成功/no-op/失败 JSON；outbox `dedup_name=checkpoint-{cr}-{metadataCommit}.json` 仅完整批次一次。

## 验收条件

1. 集成矩阵 15 项全覆盖（SDD §9.2 1～15），并在 `checkpoint-tx.test.mjs` 增加业务 payload 合法/恢复冲突 fixture（重复 repo、非法 SHA/ref/phase、字段缺失 → `TX_RECOVERY_CONFLICT`）；确认 durable-tx.test 不含这些业务 fixture。
2. 安装根调用、敏感零副作用、source/hook 后变化重扫、部分 push 后新增变化、响应丢失、advanced/diverged/history-rewritten、metadata 故障注入均通过。
3. 成功输出含 `op/cr/txId/batchId/phase=complete/repositories[].confirmed/metadataCommit/changed/recoverCommand`；no-op `txId=null`。
4. 错误 JSON 按 SDD §3.5 表返回 code/phase/sideEffects/recoverCommand；加载后的 checkpoint 业务 payload 与恢复事实不一致沿用 `TX_RECOVERY_CONFLICT`。

## 完成标志

`crctl checkpoint` 在测试矩阵下全绿；253+10 基线不回归；commit 到 tools 仓 `requirement/CR-2026-033`。

## 接口契约

- 消费：TASK-03 三个纯函数；TASK-02 的 generic envelope slot、唯一 FAULT_POINTS 登记与 `matchEntryBlock`；TASK-01 的 18-code/fault point 测试 expected set。
- 产出：`checkpointCr(ctx, {cr, message, workspace}) -> {cr, txId, phase, batchId, repositories, metadataCommit, changed, sideEffects, recoverCommand}`；workspace-transactions 内部 checkpoint payload validator；CLI `crctl checkpoint <cr_id> [--message <text>] --workspace <installation-workspace>`（TASK-05 消费）。
