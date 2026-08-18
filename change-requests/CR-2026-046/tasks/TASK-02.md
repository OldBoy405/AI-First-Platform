---
id: CR-2026-046-TASK-02
type: TASK
cr-ref: CR-2026-046
plan-ref: "change-requests/CR-2026-046/plan.md"
sdd-ref: "change-requests/CR-2026-046/sdd.md"
title: register 路径单元测试（stale trunk / 远端恢复 / 不可用）
slug: register-workspace-remote-tests
status: pending
estimate: 3h
depends-on: ["CR-2026-046-TASK-01"]
created: "2026-08-18T20:51:24+08:00"
---

# TASK-02 register 路径单元测试

## 1. 任务描述

按 SDD §8.1 在 `tools/skills/shared/crctl/scripts/test/register-tx.test.mjs` 追加单元测试，直接 import lib 函数（先例：`merge-tx.test.mjs` 已 import `prepareMergeTree`/`replaceBacklogEntry`）：

1. stale local trunk：origin master 推进后本地落后，`ensureRepoWorkspace`（missing）建 CR branch，HEAD == 新 origin master SHA（PRD AC-1）。
2. 远端 CR 分支恢复：仅远端有 `requirement/{CR}`、本地无任何 ref → action `created:from-remote`，tracking 正确（PRD AC-2）。
3. fetch 失败：`git remote set-url origin <bogus>` → 抛 `WORKSPACE_TRUNK_UNAVAILABLE`，无本地 branch/worktree（PRD AC-3）。
4. trunk 缺失且本地存在 stale tracking ref：保留本地 `refs/remotes/origin/master`，仅在 bare origin `update-ref -d refs/heads/master` → `fetch --prune` 清理 stale ref 后抛 `WORKSPACE_TRUNK_UNAVAILABLE`（PRD AC-3）。
5. healthy/branch-only 不 fetch：bogus url 下 `healthy` 返回 `none`、`branch-only` 返回 `from-local-branch` 不抛错（PRD AC-4）。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/test/register-tx.test.mjs`（仅追加用例与必要 import）

## 3. 实现要点

- 复用文件内既有 `makeFixture()`（三 bare origin）+ `git()` helper，不新建 fixture 文件。
- 单元测试需要 `ctx`：`import { resolveRepositories, ensureRepoWorkspace } from '../lib/workspace-transactions.mjs';`，`const ctx = resolveRepositories(kb)`（fixture 已有 dir-graph.yaml）。
- stale trunk 场景：clone origin 到临时目录 → commit → push 推进 origin master → 本地 kb fetch 前仍是旧 ref → 调用 ensure 后比对 `git(kb, ['rev-parse', `requirement/${cr}`])` 与 bare 的 master SHA。
- 远端 CR 分支场景：先在 origin 用 clone 推 `requirement/{cr}` 分支，本地删掉任何同分支 ref/worktree 后调用 ensure。
- trunk 缺失场景：先 `git(bare, ['update-ref', '-d', 'refs/heads/master'])`，保留本地 `refs/remotes/origin/master` 后调用 ensure，断言抛错码。
- 断言 TxError：用 `assert.throws(fn, (e) => e.code === 'WORKSPACE_TRUNK_UNAVAILABLE')`（先例：既有 `assert.throws(..., (e) => e.code === ...)` 模式）。

## 4. 验收条件

1. 新增 5 组用例全绿：`node --test skills/shared/crctl/scripts/test/register-tx.test.mjs`。
2. 每组用例的失败分支断言本地 `git branch --list requirement/{cr}` 为空且 `worktree list` 不含该 CR worktree。
3. 既有全部 register 用例零回归（七分类/幂等/fault/cleanup 等）。

## 5. 完成标志

- 5 组用例落盘且全绿；既有用例零回归；
- `git diff --check` 干净；
- 新增用例覆盖 PRD AC-1/2/3/4。

## 6. 接口契约

**消费**（来自 TASK-01）：
- `ensureRepoWorkspace(ctx, repo, cr)`：成功返回含 `action`；失败抛 `TxError`，code ∈ { `WORKSPACE_TRUNK_UNAVAILABLE`, `WORKSPACE_ENSURE_BLOCKED` }。
- `resolveRepositories(workspacePath)`：返回 `{ repositories: [{ id, trunk, rootPath, worktreePath }], ... }`。
- `classifyRepoWorkspace(ctx, repo, cr)`：返回 `{ classification: 'healthy'|'branch-only'|'remote-only'|'missing'|'dirty'|'wrong-branch'|'path-unregistered', ... }`。

**产出**：无代码接口（纯测试）；产出测试证据供 M3 回归与 review-code 引用。
