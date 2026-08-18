---
id: CR-2026-046-TASK-04
type: TASK
cr-ref: CR-2026-046
plan-ref: "change-requests/CR-2026-046/plan.md"
sdd-ref: "change-requests/CR-2026-046/sdd.md"
title: merge 路径测试（happy path 断言 + 表驱动 + faultPoint 注入）
slug: merge-local-sync-tests
status: pending
estimate: 4h
depends-on: ["CR-2026-046-TASK-03"]
created: "2026-08-18T20:51:24+08:00"
---

# TASK-04 merge 路径测试

## 1. 任务描述

按 SDD §8.2 在 `tools/skills/shared/crctl/scripts/test/merge-tx.test.mjs` 追加测试：

1. **happy path 追加断言**：既有三仓 happy path 测试中追加 `r.json.localTrunkSync` 断言——三仓 `status=synced`、`before`=fixture 初始 HEAD、`remote`=origin master SHA、`after`=remote；主 checkout `rev-parse master` == origin master（PRD AC-6/7）。
2. **表驱动单元测试**：直接调 `reconcileLocalTrunks(ctx)`，复用 `merge-fixture.mjs` 已导出的 `makeFixture()` bare 三仓。场景：wrong-branch（checkout 其他分支）、dirty（未提交文件）、diverged（本地前进且 origin 也前进）、fetch-failed（bogus url）、trunk-unavailable（远端删 master、本地保留 stale tracking ref，验证 `--prune` 清理）、unchanged（已同步）→ 断言 status/reason/before/remote/after 按 SDD §2.2 表取值（PRD AC-6）。
3. **ff-only-failed 集成**：以 `CRCTL_FAULT_POINT=local-sync-ff-only-failed` 跑完整 merge → exit 0、`phase=complete`、kb 行 `failed/ff-only-failed`、远端 master 已含 merge commit（PRD AC-6/7）。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/test/merge-tx.test.mjs`（追加用例 + import `reconcileLocalTrunks`/`resolveRepositories`）
- 复用 `tools/skills/shared/crctl/scripts/test/merge-fixture.mjs`（已导出 `makeFixture`/`git`/`runCrctl`，零改动）

## 3. 实现要点

- `ctx` 构造：`const ctx = resolveRepositories(kb)`（fixture 的 kb 有 dir-graph.yaml）。
- 表驱动用例逐场景构造后断言整行字段；每场景独立 fixture 或干净还原（新 fixture 成本低，直接每场景新 `makeFixture()`）。
- trunk-unavailable：`git(bare, ['update-ref', '-d', 'refs/heads/master'])` 后保留本地 stale `refs/remotes/origin/master`，调 helper 断言 `failed`/`trunk-unavailable` 且 `remote=null`。
- diverged：本地 master 前进一个 commit；origin 用 clone 也前进（各自分叉）。
- faultPoint 集成：`runCrctl(['merge', cr, '--workspace', kb], { cwd: kb, env: { CRCTL_FAULT_POINT: 'local-sync-ff-only-failed' } })`；注意 faultPoint 在 helper 对每仓触发，三行均为 `failed/ff-only-failed`（或断言 kb 行即可，其余仓同为该状态）。
- 断言远端成功：bare master 含 `merge ${cr}: kb` commit；`r.json.phase === 'complete'`、`r.status === 0`。

## 4. 验收条件

1. 新增三组用例全绿：`node --test skills/shared/crctl/scripts/test/merge-tx.test.mjs`。
2. 表驱动覆盖 6 场景，每行 status/reason/before/remote/after 与 SDD §2.2 表逐字段一致。
3. faultPoint 集成证明 exit 0 + `phase=complete` + 远端已 merge（远端成功不受本地失败影响，PRD AC-7）。
4. 既有 merge journal/lease/finalize/重入/history-rewrite 用例零回归。

## 5. 完成标志

- 三组用例落盘且全绿；既有用例零回归；
- `git diff --check` 干净；
- 新增用例覆盖 PRD AC-6/7，`localTrunkSync` 输出契约有逐字段断言。

## 6. 接口契约

**消费**（来自 TASK-03）：
- `reconcileLocalTrunks(ctx): LocalTrunkSyncRow[]`（字段定义见 TASK-03 §6）；
- `mergeCr` 返回对象字段 `localTrunkSync`；
- 故障注入点名 `local-sync-ff-only-failed`。

**产出**：无代码接口（纯测试）；产出测试证据供 M3 回归与 review-code 引用。
