---
spec-id: ai-first-platform
version: "0.20.7"
id: CR-2026-046-TASK-01
type: TASK
cr-ref: CR-2026-046
plan-ref: "change-requests/CR-2026-046/plan.md"
sdd-ref: "change-requests/CR-2026-046/sdd.md"
title: 注册路径纵切（远端基点改造 + register 测试）
slug: register-remote-base-vertical
status: pending
estimate: 5h
depends-on: []
created: "2026-08-18T20:51:24+08:00"
---

# TASK-01 注册路径纵切

## 1. 任务描述

按 SDD §3.1/§4.1/§8.1 完成注册路径的实现与测试，形成一个约 1 工作日纵切：

1. 修改 `ensureRepoWorkspace(ctx, repo, cr)` 的 `case 'missing'`：`git fetch --prune origin` → 复用 `classifyRepoWorkspace` 二次分类 → `remote-only` / `branch-only` / `missing` 三路恢复；删除从本地 `repo.trunk` 建 CR branch 的路径。
2. fetch 失败或远端 trunk 不可解析时抛 `WORKSPACE_TRUNK_UNAVAILABLE`，不得创建/修改 CR branch/worktree，不回退本地 trunk。
3. 在 `register-tx.test.mjs` 追加 stale local trunk、远端 CR 分支恢复、fetch 失败、stale trunk ref 被 prune、healthy/branch-only 不 fetch 五组用例；跑完整 register 测试回归。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：仅 `ensureRepoWorkspace` 函数体。
- `tools/skills/shared/crctl/scripts/test/register-tx.test.mjs`：追加必要 import 与测试，不新增 fixture 文件。

## 3. 实现要点

- 所有 Git 副作用经 `gitMust`：`gitMust(rootPath, ['fetch', '--prune', 'origin'])`；失败捕获后重抛 `TxError('WORKSPACE_TRUNK_UNAVAILABLE', ..., { repo: repo.id, cause: e.message })`。
- 二次分类：
  - `remote-only` → 既有 `git branch --track` + `create('from-remote')`；
  - `branch-only` → `create('from-local-branch')`；
  - `missing` → `rev-parse --verify -q refs/remotes/origin/{trunk}` 成功后 `git branch {branch} <trunkRef>` + `create('from-remote-trunk')`；
  - 其余 → `WORKSPACE_ENSURE_BLOCKED`。
- `create(how)` 闭包、register journal、`worktrees[]`、CLI flag 面均不改。
- 测试复用文件内 `makeFixture()` / `git()`；import `resolveRepositories` 与 `ensureRepoWorkspace`。每组用例独立 fixture，finally 清理。
- stale trunk ref 用例：保留本地 `refs/remotes/origin/master`，仅在 bare origin 删除 `refs/heads/master`，验证 `fetch --prune` 清理后错误码与零 CR 资源写入。

## 4. 验收条件

1. stale local trunk 场景：新 `requirement/{CR}` HEAD == fetch 后 origin trunk SHA（PRD AC-1）。
2. 仅远端有 CR 分支时：返回 `action='created:from-remote'`，worktree 分支跟踪 `origin/requirement/{CR}`（PRD AC-2）。
3. fetch 失败和远端 trunk 缺失时：均抛 `WORKSPACE_TRUNK_UNAVAILABLE`，本地 CR branch/worktree 不存在（PRD AC-3）。
4. bogus origin 下 healthy 返回 `action='none'`、branch-only 返回 `created:from-local-branch`，证明二者不 fetch（PRD AC-4）。
5. `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` 全绿，既有七分类/幂等/fault/cleanup 用例零回归；`git diff --check` 通过。

## 5. 完成标志

- 实现与五组新增测试同一 TASK 完成；
- register-tx 全量通过，失败路径有结构化错误断言；
- 未修改 `crctl.mjs`、journal、Pipeline、Skill、README、状态机或 gates；
- 完成后立即执行 `crctl task done CR-2026-046 --task CR-2026-046-TASK-01` 登记进度。

## 6. 接口契约

**消费**：既有 `classifyRepoWorkspace(ctx, repo, cr)`、`gitRun`/`gitMust`、`TxError`、`resolveRepositories(workspacePath)`。

**产出**：
- `ensureRepoWorkspace(ctx, repo, cr)` 签名不变；成功返回含 `action: 'created:from-remote-trunk'|'created:from-remote'|'created:from-local-branch'|'none'`。
- 新失败契约：`TxError.code='WORKSPACE_TRUNK_UNAVAILABLE'`，`extra={ repo, ref?, cause? }`；既有 `WORKSPACE_ENSURE_BLOCKED` 保持。
- 测试证据：`register-tx.test.mjs` 新增用例覆盖 PRD AC-1~4。
