---
spec-id: ai-first-platform
version: "0.4"
id: CR-2026-031-TASK-05
type: TASK
cr-ref: CR-2026-031
plan-ref: "change-requests/CR-2026-031/plan.md"
sdd-ref: "change-requests/CR-2026-031/sdd.md"
title: 实现幂等 register 与 workspace 生命周期
slug: register-workspace-transactions
status: pending
estimate: 16h
depends-on: [CR-2026-031-TASK-02, CR-2026-031-TASK-03, CR-2026-031-TASK-04]
created: 2026-08-11T17:36:00+08:00
---

# 1. 任务描述

实现 `crctl register` 与 `workspace inspect/ensure/cleanup`，以 registration key 和 journal 在 CR-ID 分配、commit/push、任意仓 workspace 失败后 roll-forward。

# 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

# 3. 实现要点

- registration key 只保存 SHA-256；同 key/同 inputDigest 复用，不同输入 hard fail。
- 三账本通过 recoverable write-set；registration commit 加固定 trailer并 lease push。
- workspace 分类固定为 missing/healthy/branch-only/remote-only/dirty/wrong-branch/path-unregistered。
- ensure 只补齐可证明资源；cleanup 不删除 dirty/unknown/未合并 ref。

# 4. 验收条件

1. 每个 fault point 重跑复用同 CR-ID/txId，不重复账本/commit/worktree；输入变化返回 `REGISTRATION_INPUT_MISMATCH`。
2. 第一仓成功、第二仓失败后只补第二仓；dirty/wrong branch/path-unregistered 零删除。
3. graph 零副作用变化可重建，有副作用变化返回 `GRAPH_CHANGED_DURING_TRANSACTION`。

# 5. 完成标志

register/workspace 四个 CLI 输出结构化 phase/sideEffects/recoverCommand，集成测试通过，任务状态登记 done。

# 6. 接口契约

消费：TASK-02 `assertSupportedBacklogSchema`、TASK-03 `resolveRepositories`、TASK-04 durable APIs。

产出：`registerCr(ctx: object,input: {registrationKey:string,title:string,summary?:string,source?:string,targetVersion?:string,owners:{requirement:string,development:string,test:string}}): Promise<{cr:string,txId:string,phase:string,changed:boolean,sideEffects:object[],recoverCommand:string}>`；`ensureWorkspace(ctx,input:{cr:string,mode:'inspect'|'resume'|'partial'|'archived'}): Promise<{txId:string,resources:object[],changed:boolean}>`。TASK-07/09 使用 workspace/journal 事实。
