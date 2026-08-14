---
id: CR-2026-031-TASK-03
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 实现 repository resolver 与 authority containment
slug: repository-authority-resolver
status: pending
estimate: 10h
depends-on: [CR-2026-031-TASK-01]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

实现唯一 repository resolver、canonical workspace 路径和 phase authority 判定，替代写死 repo id/bucket 与 `--workspace .` 推断。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

# 3. 实现要点

- 只读 workspace `dir-graph.yaml#repositories`，验证 active repo 的 id/path/trunk/role。
- bucket 从声明和 knowledge-base role 解析；禁止写死 `ai-first-platform-docs`。
- canonical/realpath containment 拒 absolute、`..`、symlink escape、未注册路径。
- authority 在 merge finalize 前指 CR worktree，finalize 后指 detached Transaction Workspace。

# 4. 验收条件

1. repo rename、inactive/missing trunk、未知 repo、symlink escape 均返回精确结构化错误。
2. 三仓 fixture 返回稳定、排序后的 repo map、graphDigest、branch 和 canonical path。
3. post-finalize authority 不返回主 checkout 或旧 CR worktree。

# 5. 完成标志

resolver 成为 register/workspace/merge/writeback/archive 唯一仓库和路径入口，任务状态登记 done。

# 6. 接口契约

消费：TASK-01 `runCrctl(...)`。

产出：`resolveRepositories(workspace: string): { repositories: Array<{id:string,role:string,path:string,trunk:string,bucket:string,worktreePath:string,branch:string}>, graphDigest:string, knowledgeBaseRepoId:string }`；`resolveOperationalWorkspace(ctx: object, cr: string): { phase:string, path:string, source:'cr-worktree'|'transaction-workspace' }`。TASK-05/07/08/09 精确消费。
