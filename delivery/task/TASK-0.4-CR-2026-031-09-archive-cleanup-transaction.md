---
spec-id: ai-first-platform
version: "0.4"
id: CR-2026-031-TASK-09
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 实现单一 archive 与 cleanup-pending
slug: archive-cleanup-transaction
status: pending
estimate: 12h
depends-on: [CR-2026-031-TASK-05, CR-2026-031-TASK-07, CR-2026-031-TASK-08]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

实现 `crctl archive` 单一幂等入口，统一状态、四账本、archive event、commit/push 与资源清理；业务终态和运维 cleanup 解耦。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

# 3. 实现要点

- origin confirmed 前允许 rebuild/续推，不提前宣称 archived。
- confirmed 后 status 不回退，journal 转 cleanup-pending。
- 只清理由 graph+journal+ancestry 证明且 clean 的资源。
- rejected/withdrawn 未合并 remote refs 保留并输出 preservedRefs；无 cleanup_branch 参数。

# 4. 验收条件

1. archive commit 发布后每个 cleanup fault 都保持 archived，返回 `CR_ARCHIVE_CLEANUP_PENDING`；重跑不重复账本/event/commit。
2. dirty/unknown workspace 零删除；rejected/withdrawn 未合并 ref 出现在 preservedRefs。
3. 全部清理后 journal complete，重复 archive 返回 changed=false。

# 5. 完成标志

archive 单入口覆盖业务与 cleanup 续跑，模型不生成 cleanup report，任务状态登记 done。

# 6. 接口契约

消费：TASK-05 `ensureWorkspace`、TASK-07 `classifyRemoteCommit`、TASK-08 的 operational workspace/commit 事实。

产出：`archiveCr(ctx:object,input:{cr:string,specId?:string}): Promise<{txId:string,phase:'publishing'|'cleanup-pending'|'complete',status:'archived',changed:boolean,preservedRefs:string[],recoverCommand:string}>`。TASK-10/11 精确消费结果码和字段。
