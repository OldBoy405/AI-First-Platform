---
spec-id: ai-first-platform
version: "0.4"
id: CR-2026-031-TASK-07
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 实现可恢复跨仓 merge 与 finalize
slug: recoverable-cross-repo-merge
status: pending
estimate: 20h
depends-on: [CR-2026-031-TASK-05, CR-2026-031-TASK-06]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

实现 `crctl merge/status`：无副作用 prepare、Git commit-tree candidate、逐仓 lease publish、远端事实 reconcile 和单一 knowledge-base finalize。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

# 3. 实现要点

- 只消费 approval release-subjects，不使用当前 branch 猜 source。
- `classifyRemoteCommit` 仅返回 confirmed/pushable/rebuild/history-rewritten。
- prepare 使用临时 index/tree 与 `commit-tree`，不 checkout/move 本地 trunk。
- 所有仓 confirmed 后，finalize 同一 commit 写 status、完整 metadata、verification/event；返回 operational_workspace。
- 部分发布保持 code-approved，不自动 revert/reset/force。

# 4. 验收条件

1. 三 bare remote 覆盖 prepare conflict、第二仓失败、响应丢失、remote stale、finalize stale、history rewrite；重跑不重复已 confirmed push。
2. 部分发布输出 txId/phase/sideEffects/recoverCommand，CR status 仍为 code-approved。
3. finalize commit 同时包含完整事实且 origin confirmed 后 authority 切换到 Transaction Workspace。

# 5. 完成标志

merge 单入口可从所有承诺 fault point roll-forward 或 hard block，无公开 metadata 补写，任务状态登记 done。

# 6. 接口契约

消费：TASK-05 workspace/journal、TASK-06 `verifyReleaseSubjects`。

产出：`classifyRemoteCommit({remoteSha:string,expectedBase:string,commitSha:string,commitIsRemoteAncestor:boolean,journalSaysPublished:boolean}): 'confirmed'|'pushable'|'rebuild'|'history-rewritten'`；`mergeCr(ctx:object,input:{cr:string}): Promise<{txId:string,phase:string,changed:boolean,sideEffects:object[],recoverCommand:string,operationalWorkspace?:string}>`。TASK-08/09/11 精确消费。
