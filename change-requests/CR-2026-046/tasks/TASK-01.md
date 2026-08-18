---
id: CR-2026-046-TASK-01
type: TASK
cr-ref: CR-2026-046
plan-ref: "change-requests/CR-2026-046/plan.md"
sdd-ref: "change-requests/CR-2026-046/sdd.md"
title: ensureRepoWorkspace missing 分支改造（远端基点 + 新错误码）
slug: ensure-workspace-remote-base
status: pending
estimate: 2h
depends-on: []
created: "2026-08-18T20:51:24+08:00"
---

# TASK-01 ensureRepoWorkspace missing 分支改造

## 1. 任务描述

按 SDD §3.1/§4.1 修改 `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 中 `ensureRepoWorkspace(ctx, repo, cr)` 的 `case 'missing'` 分支（现约 L501-524）：

- `git fetch --prune origin`（经 `gitMust`，失败转 `WORKSPACE_TRUNK_UNAVAILABLE`）；
- 复用 `classifyRepoWorkspace` 二次分类；
- `remote-only` → 既有 `--track` + `create('from-remote')`；
- `branch-only` → `create('from-local-branch')`（新增显式分支）；
- 仍 `missing` → 解析 `refs/remotes/origin/{repo.trunk}` 后 `git branch {branch} <trunkRef>` + `create('from-remote-trunk')`，trunk 不可解析转 `WORKSPACE_TRUNK_UNAVAILABLE`；
- 其余重新分类结果 → 既有 `WORKSPACE_ENSURE_BLOCKED` 硬阻断。

删除原 `git branch {branch} {repo.trunk}`（本地 trunk 起点）路径。`healthy`/`branch-only`/`dirty`/`wrong-branch`/`path-unregistered` 首次分类行为零改动、不触发 fetch。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（仅 `ensureRepoWorkspace` 函数体）

## 3. 实现要点

- 全部 Git 副作用经 `gitMust`（模块硬不变量，SDD §1.1）；`fetch` 失败捕获 `TxError` 后重抛 `WORKSPACE_TRUNK_UNAVAILABLE`，携带 `{ repo: repo.id, cause: e.message }`。
- trunk 解析用 `gitRun(rootPath, ['rev-parse', '--verify', '-q', trunkRef])`，status 非 0 或 stdout 为空 → 抛 `WORKSPACE_TRUNK_UNAVAILABLE`，携带 `{ repo: repo.id, ref: trunkRef }`。
- `create(how)` 闭包保持既有实现不动。
- 不引入新依赖、新文件、新账本字段。

## 4. 验收条件

1. `node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` 全绿（既有用例零回归）。
2. 单元级验证（TASK-02 用例）：本地 trunk 落后 origin 时，新建 CR branch HEAD == fetch 后 `refs/remotes/origin/{trunk}` SHA。
3. 单元级验证（TASK-02 用例）：fetch 失败或远端 trunk 缺失时抛 `WORKSPACE_TRUNK_UNAVAILABLE`，且无本地 `requirement/{CR}` branch/worktree。

## 5. 完成标志

- 函数改造完成，diff 仅含 `ensureRepoWorkspace` 函数体；
- TASK-02 测试用例全部通过；
- `git diff --check` 无告警；`node --test skills/shared/crctl/scripts/test/register-tx.test.mjs` 零回归。

## 6. 接口契约

**消费**：既有 `classifyRepoWorkspace(ctx, repo, cr)`（返回 `{ classification, branch, worktreePath, ... }`）、`gitRun`/`gitMust`、`TxError`。

**产出**（行为契约，供 TASK-02 断言）：
- `ensureRepoWorkspace(ctx, repo, cr)` 签名不变；
- 成功返回 `{ ...分类信息, action: 'created:from-remote-trunk' | 'created:from-remote' | 'created:from-local-branch' | 'none' }`；
- 失败抛 `TxError`：`WORKSPACE_TRUNK_UNAVAILABLE`（extra: `{ repo, ref?, cause? }`）、`WORKSPACE_ENSURE_BLOCKED`（extra: 分类投影）。
