---
spec-id: ai-first-platform
version: "0.4"
id: CR-2026-031-TASK-08
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 实现 Transaction Workspace 与 candidate writeback
slug: transaction-workspace-writeback
status: pending
estimate: 18h
depends-on: [CR-2026-031-TASK-03, CR-2026-031-TASK-04, CR-2026-031-TASK-06, CR-2026-031-TASK-07]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

将三个 writeback generator 收敛为 candidate-only，并实现 `crctl writeback-apply` 在 Transaction Workspace 校验、应用、精确 stage、commit 和 lease publish。

# 2. 涉及文件 / 模块

- `skills/writeback/scripts/writeback-prd-sdd.mjs`
- `skills/writeback/scripts/writeback-tasks.mjs`
- `skills/writeback/scripts/writeback-traceability.mjs`
- `skills/writeback/scripts/lib.mjs`
- `skills/writeback/scripts/test/writeback.test.mjs`
- `skills/shared/crctl/scripts/{crctl.mjs,lib/workspace-transactions.mjs}`

# 3. 实现要点

- manifest v1 固定 schema/排序/allowlist，仅 create/replace。
- inputDigest 覆盖 signed snapshot、stage/spec/version、before hashes、generator SHA。
- 拒绝 path traversal、symlink、tx 外 blob、hash mismatch、delete/rename/chmod。
- origin 前进且未发布时从新 detached base 重生成，不 rebase/cherry-pick。

# 4. 验收条件

1. 全部恶意 manifest/path/blob/hash case hard fail，baseline 和 staged set 保持空。
2. 应用成功后 staged set 与 manifest paths 精确相等，commit 带固定 trailer。
3. candidate 后 trunk 前进执行 rebuild；已发布历史丢失返回 `WRITEBACK_REMOTE_HISTORY_REWRITTEN`。

# 5. 完成标志

脚本不再直接写 baseline/Git/状态，三个 stage 通过集成测试，任务状态登记 done。

# 6. 接口契约

消费：TASK-03 `resolveOperationalWorkspace`、TASK-04 `applyWriteSet`、TASK-06 `verifyReleaseSubjects`、TASK-07 `classifyRemoteCommit`。

产出：generator CLI 输出 `{candidateDir:string,manifestPath:string,inputDigest:string}`；`applyWriteback(ctx:object,input:{cr:string,stage:'baseline'|'tasks'|'traceability',candidate:string,specId:string}): Promise<{txId:string,phase:string,changed:boolean,commit?:string,recoverCommand:string}>`。TASK-09/10 精确消费。
