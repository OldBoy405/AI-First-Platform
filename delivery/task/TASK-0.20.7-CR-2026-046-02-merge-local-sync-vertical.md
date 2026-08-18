---
spec-id: ai-first-platform
version: "0.20.7"
id: CR-2026-046-TASK-02
type: TASK
cr-ref: CR-2026-046
plan-ref: "change-requests/CR-2026-046/plan.md"
sdd-ref: "change-requests/CR-2026-046/sdd.md"
title: merge 路径纵切（本地 trunk 同步 + 测试 + 全量回归）
slug: merge-local-sync-vertical
status: pending
estimate: 7h
depends-on: ["CR-2026-046-TASK-01"]
created: "2026-08-18T20:51:24+08:00"
---

# TASK-02 merge 路径纵切与发布验证

## 1. 任务描述

按 SDD §3.2/§4.2/§4.3/§8.2 完成 merge 路径实现、测试和最终全量回归，形成一个约 1 工作日纵切：

1. 在 `workspace-transactions.mjs` 新增模块内导出 `reconcileLocalTrunks(ctx)`，按 8 判据逐仓生成 `LocalTrunkSyncRow`；有副作用的 fetch/merge 均经 `gitMust` 并局部捕获，helper 不抛错。
2. 在 `mergeCr` 的 `save('complete')` 后、return 前调用 helper，新增返回字段 `localTrunkSync`；不改 `crctl.mjs`、journal、merge status 或业务状态。
3. 在 `merge-tx.test.mjs` 追加 happy path 三仓断言、6 场景表驱动测试、`local-sync-ff-only-failed` faultPoint 集成测试。
4. 在 TASK-01 完成后执行全部 crctl 测试与发布 checklist，承接 Plan M2 的最终发布验证。

## 2. 涉及文件 / 模块

- `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：新增 `reconcileLocalTrunks`，`mergeCr` 返回处最小接线。
- `tools/skills/shared/crctl/scripts/test/merge-tx.test.mjs`：追加用例与必要 import。
- 复用 `tools/skills/shared/crctl/scripts/test/merge-fixture.mjs` 已导出的 `makeFixture`/`git`/`runCrctl`，零改动。

## 3. 实现要点

- `LocalTrunkSyncRow` 精确字段：`{ repo, trunk, before, remote, after, status, reason }`；status/reason/SHA-null 规则按 SDD §2.2 表。
- 判据顺序固定：wrong-branch → dirty → fetch-failed → trunk-unavailable → unchanged → diverged → synced / ff-only-failed。
- 只读判定用 `gitRun`；`git fetch --prune origin`、`git merge --ff-only <captured SHA>` 用 `gitMust` + 局部 try/catch；禁止重新解析已捕获 remote SHA。
- ff-only try/catch 内调用 `faultPoint('local-sync-ff-only-failed', { repo: repo.id })`，仅测试环境变量匹配时生效。
- helper 位于 merge 锁内但不写 journal/audit；失败条目不影响其他仓、远端结果、`phase=complete` 或 exit 0。
- 测试：
  - happy path 在既有三仓用例追加 `localTrunkSync` 逐行断言；
  - 表驱动场景：wrong-branch、dirty、diverged、fetch-failed、trunk-unavailable（远端删 trunk、本地留 stale tracking ref）、unchanged；
  - faultPoint 完整 merge：三仓可均 `failed/ff-only-failed`，至少断言 kb 行及远端 merge 成功。

## 4. 验收条件

1. clean+behind 三仓均 `synced`，主 checkout HEAD == 捕获 remote SHA；already-current 为 `unchanged`（PRD AC-6）。
2. wrong-branch / dirty / diverged 为 `skipped` 且现场不变；fetch-failed / trunk-unavailable / ff-only-failed 为 `failed`，before/remote/after 符合 SDD §2.2（PRD AC-6）。
3. faultPoint 场景 `runCrctl` exit 0、`phase='complete'`，远端 trunk 已包含 merge commit，本地失败不回滚远端（PRD AC-7）。
4. `node --test skills/shared/crctl/scripts/test/merge-tx.test.mjs` 全绿，既有 journal/lease/finalize/rebuild/history-rewrite 用例零回归（PRD AC-8）。
5. TASK-01 已 done 后执行 `node --test skills/shared/crctl/scripts/test/*.test.mjs` 全绿；`git diff --check` 通过；`crctl.mjs`/Pipeline/Skill/README/状态机/gates 零 diff。

## 5. 完成标志

- helper、mergeCr 接线与全部新增测试同一 TASK 完成；
- merge-tx 与全量 crctl 测试通过，发布 checklist 五项全部核对；
- 无新增文件、依赖、事务、账本字段或恢复流程；
- 完成后立即执行 `crctl task done CR-2026-046 --task CR-2026-046-TASK-02` 登记进度。

## 6. 接口契约

**消费**：
- 既有 `ctx.repositories[]: { id, trunk, rootPath }[]`、`gitRun`/`gitMust`/`faultPoint`。
- TASK-01 完成状态与 register-tx 绿色证据（仅作为最终全量回归前置，无代码接口依赖）。

**产出**：
- `export function reconcileLocalTrunks(ctx): LocalTrunkSyncRow[]`。
- `LocalTrunkSyncRow = { repo:string, trunk:string, before:string|null, remote:string|null, after:string|null, status:'synced'|'unchanged'|'skipped'|'failed', reason:'dirty'|'wrong-branch'|'diverged'|'fetch-failed'|'trunk-unavailable'|'ff-only-failed'|null }`。
- `mergeCr(ctx, input)` complete 返回对象新增 `localTrunkSync: LocalTrunkSyncRow[]`；其余字段与 `mergeStatus` 契约不变。
- 故障注入点名：`local-sync-ff-only-failed`。
- 测试证据：`merge-tx.test.mjs` 覆盖 PRD AC-6~8，完整 test glob 覆盖全量回归。
