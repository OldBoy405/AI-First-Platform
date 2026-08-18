---
id: CR-2026-046-TASK-03
type: TASK
cr-ref: CR-2026-046
plan-ref: "change-requests/CR-2026-046/plan.md"
sdd-ref: "change-requests/CR-2026-046/sdd.md"
title: reconcileLocalTrunks helper 实现与 mergeCr 接线
slug: reconcile-local-trunks-helper
status: pending
estimate: 3h
depends-on: []
created: "2026-08-18T20:51:24+08:00"
---

# TASK-03 reconcileLocalTrunks helper 实现与 mergeCr 接线

## 1. 任务描述

按 SDD §3.2/§4.2/§4.3 在 `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 新增模块内 helper `reconcileLocalTrunks(ctx)`（导出供测试），并在 `mergeCr` 的 `save('complete')` 之后、return 之前调用，把结果写入返回对象的 `localTrunkSync` 字段。

helper 逐 `ctx.repositories` 执行 8 判据（SDD §4.2 伪代码逐条落位）：

1. wrong-branch → `skipped`/`wrong-branch`；
2. dirty → `skipped`/`dirty`；
3. `git fetch --prune origin`（经 `gitMust`，局部 try/catch）失败 → `failed`/`fetch-failed`；
4. `refs/remotes/origin/{trunk}` 不可解析 → `failed`/`trunk-unavailable`；
5. 已一致 → `unchanged`；
6. 非祖先 → `skipped`/`diverged`；
7. `git merge --ff-only <捕获 SHA>`（经 `gitMust`，try/catch 内含 `faultPoint('local-sync-ff-only-failed', { repo })`）成功 → `synced`；
8. ff-only 失败 → `failed`/`ff-only-failed`。

helper **绝不抛出**；行结果字段按 SDD §2.2 表取值。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：新增 `reconcileLocalTrunks` + `mergeCr` 返回处两行接线。
- 不改 `crctl.mjs`（`ok({ op:'merge', ...result })` 自动透传）、不改 `mergeStatus` 只读快照。

## 3. 实现要点

- 只读判定用 `gitRun`；两条 Git 副作用命令（fetch --prune、merge --ff-only）用 `gitMust` + 局部 try/catch（模块硬不变量：Git 副作用只经 gitMust）。
- `remote` 字段是判据 3/4 捕获的 SHA，判据 7 禁止重新解析移动 ref（直接使用捕获 SHA）。
- `faultPoint` 从 `./durable-tx.mjs` 既有 import（文件顶部已 import，无需新增）。
- helper 同步执行（无 await），位于 merge 目录锁内（`finally` 释放锁之前）。
- 失败条目不写 journal/audit；任何条目都不改变 `phase=complete` / exit 0 语义。

## 4. 验收条件

1. 单元级验证（TASK-04 表驱动）：wrong-branch / dirty / diverged / fetch-failed / trunk-unavailable / unchanged / synced 各状态 reason 与 before/remote/after 取值符合 SDD §2.2。
2. 集成验证（TASK-04）：happy path merge 后三仓主 checkout ff-only 到 origin master，输出 `localTrunkSync` 三行 `synced`。
3. `node --test skills/shared/crctl/scripts/test/merge-tx.test.mjs` 既有用例零回归。

## 5. 完成标志

- `reconcileLocalTrunks(ctx)` 与 `mergeCr` 接线完成，diff 不含 `crctl.mjs`；
- TASK-04 全部用例通过；既有 merge 用例零回归；
- `git diff --check` 无告警。

## 6. 接口契约

**消费**：`gitRun`/`gitMust`/`TxError`/`faultPoint`（durable-tx）、`ctx.repositories[]`（`{ id, trunk, rootPath }`）。

**产出**（供 TASK-04 断言）：
- `export function reconcileLocalTrunks(ctx): LocalTrunkSyncRow[]`
- `LocalTrunkSyncRow = { repo: string, trunk: string, before: string|null, remote: string|null, after: string|null, status: 'synced'|'unchanged'|'skipped'|'failed', reason: 'dirty'|'wrong-branch'|'diverged'|'fetch-failed'|'trunk-unavailable'|'ff-only-failed'|null }`
- `mergeCr(ctx, input)` 返回对象新增字段 `localTrunkSync: LocalTrunkSyncRow[]`（与 `phase:'complete'` 同对象）。
- 故障注入点名：`local-sync-ff-only-failed`（`CRCTL_FAULT_POINT` 匹配时抛 `FAULT_INJECTED`）。
