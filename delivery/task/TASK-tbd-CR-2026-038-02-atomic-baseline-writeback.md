---
spec-id: ai-first-platform
version: "tbd"
id: CR-2026-038-TASK-02
type: TASK
cr-ref: CR-2026-038
plan-ref: CR-2026-038-plan
sdd-ref: CR-2026-038-sdd
title: 实现 baseline 状态同批发布与恢复投影
slug: atomic-baseline-writeback
status: pending
estimate: 14h
depends-on: [CR-2026-038-TASK-01]
owner: Ray
created: "2026-08-14T21:22:00+08:00"
updated: "2026-08-14T21:41:17+08:00"
---

# TASK-02：实现 baseline 状态同批发布与恢复投影

## 1. 任务描述

深化现有 `applyWriteback()`：把 baseline manifest 文件与 `cr.md` 的 `merging -> writing-back` after image 放入同一 recoverable write-set、staged set、commit 和 lease push；origin 确认后再发送 status outbox 与 advance audit，并通过 journal marker 幂等补发。

输入为 TASK-01 的 snapshot、business input digest 和 advance candidate。输出为 TASK-03/TASK-04 可依赖的完整新 `applyWriteback(ctx, options)` 路径；该路径在本 TASK 仅由内部测试 seam 调用，公共 dispatch 与旧生产调用保持不变，直至 TASK-04 同批切换并删除旧路径。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
- `skills/shared/crctl/scripts/lib/durable-tx.mjs`
- `skills/shared/crctl/scripts/test/writeback-tx.test.mjs`
- `skills/shared/crctl/scripts/test/archive-tx.test.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 3. 实现要点

1. journal envelope inputDigest 固定为 `sha256(JSON.stringify({businessInputDigest,manifestDigest}))`；恢复时业务参数或 candidate digest 漂移返回 `TX_INPUT_CONFLICT`。
2. journal 原子创建后以 `journal.createdAt` 作为 `transitionAt`；共享 `crMdStatusText(text,status,{at})` 接受可选时间，不复制 `updated`/`updated-at` 字段分支。
3. 即使 fault 发生在 journal 创建后、statusTransition 保存前，恢复也以同一 `createdAt` 生成完全一致的 after text/hash。
4. baseline write-set 与 staged set 精确等于 manifest files + `change-requests/{cr}/cr.md`；多/少路径返回 `WRITEBACK_STAGED_MISMATCH`。
5. commit/push 沿用现有 exact lease 和 confirmed/pushable/rebuild/history-rewritten 分类；不创建第二状态 commit。
6. origin-confirmed 后调用 `emitStatusEvent` 与 `emitAdvanceAudit`；outbox 名和 audit dedup key 绑定真实 commit，各 marker 成功后 durable save，失败仅 warning。
7. 登记并覆盖 `writeback-after-journal-create`、apply、commit、push、status-outbox、advance-audit fault point；complete replay 返回同 commit、`changed=false`。
8. tasks/traceability 保持现有 commit/status 语义，不调用 baseline callback 或发送状态投影。
9. 新业务输入路径只经内部 seam 验证；不得在本 TASK 提交公共双入口，也不得提前删除现有 candidate dispatch。

## 4. 验收条件

- [ ] happy path 的 origin 单个 commit tree 同时包含 baseline targets 与 `cr.md status=writing-back`，不存在独立状态 commit。
- [ ] journal-created/apply/commit/push 各中断一次后重跑，最终 authority commit 唯一且 after text/hash 稳定。
- [ ] outbox/audit 失败返回 success + warning；修复后重放只补缺项，不新增 commit/push/已成功投影。
- [ ] status outbox 和 `kind: advance` audit 均携带同一 origin-confirmed 40-hex SHA，无 `pending:`。
- [ ] 改变 target-version、milestone-name、brief 或 milestone-file path 恢复旧 journal 时均 `TX_INPUT_CONFLICT`；原参数可成功续跑。
- [ ] baseline 后立即执行 tasks 不把状态重置为 `merging`；tasks/traceability 无状态投影。
- [ ] `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` 与受影响 archive/crctl 定向测试通过。

## 5. 完成标志

内部新路径的 baseline 原子发布和所有恢复 fault matrix 全绿；`applyWriteback()` 返回 phase/commit/status/files/warnings/recoverCommand，且 complete replay 稳定 `changed=false`。现有公共 CLI 回归仍通过，新路径等待 TASK-04 接入。

## 6. 接口契约

**消费 TASK-01**：

```text
canonicalWritebackBusinessInput(options) -> {canonicalJson:string,digest:string}
validateBaselineAdvance({workspace:string,plannedExisting:Set<string>}) -> AdvanceCandidate
preflight snapshot.files -> Array<{path,beforeSha256,afterSha256,blobText}>
```

**产出给 TASK-04**：

```text
applyWriteback(ctx, {
  cr:string, stage:"baseline"|"tasks"|"traceability", specId:string,
  targetVersion:string, milestoneName?:string, brief?:string, milestoneFile?:string,
  workspace:string,
  validateBaselineAdvance:(input)->AdvanceCandidate,
  emitStatusEvent:(event)->string|null,
  emitAdvanceAudit:(event)->boolean
}) -> {phase,changed,commit,status,files,warnings,recoverCommand}
```

三个 callback 仅 baseline 使用；缺失时在 transaction/Git 副作用前失败。TASK-04 必须按此业务接口迁移调用方，不传 candidate/generator/manifest 路径。
