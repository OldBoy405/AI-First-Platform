---
spec-id: ai-first-platform
version: "0.20.5"
id: CR-2026-044-TASK-03
type: TASK
cr-ref: CR-2026-044
plan-ref: "change-requests/CR-2026-044/plan.md"
sdd-ref: "change-requests/CR-2026-044/sdd.md"
title: release-subjects 本地化与精确 KB 白名单
slug: release-subjects-localize
status: pending
estimate: 6h
depends-on: [CR-2026-044-TASK-01]
created: 2026-08-17T00:02:54+08:00
---

# TASK-03 release-subjects 本地化与精确 KB 白名单

## 1. 任务描述

收窄 `buildReleaseSubjects` 与 `verifyReleaseSubjects` 的事实来源为纯本地：逐仓复用 `classifyRepoWorkspace`，删除 fetch、origin 存在性检查与 remote ref 相等判定；保留 release-subjects v1 schema、artifact 摘要算法与既有 KB metadata 白名单（按 PRD FR-03 冻结的精确集合）。对应 PRD FR-01~FR-04、AC-01~AC-06（SDD §6.1、§6.2）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（`buildReleaseSubjects`、`verifyReleaseSubjects`）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（TASK-01 approve 红测试转绿 + 白名单参数化）

## 3. 实现要点

- `buildReleaseSubjects(ctx, cr)`：逐仓先 `classifyRepoWorkspace(ctx, repo, cr)`，`classification !== 'healthy'` 抛 `RELEASE_WORKSPACE_INVALID`（payload 含 `repo/classification/worktreePath/branch/dirty`）；`reviewedSourceSha` 取本地 HEAD；`remoteRef` 仍渲染 `refs/heads/requirement/{CR-ID}`；删除 `remote get-url`/`fetch`/remote ref 验证；`RELEASE_WORKSPACE_MISSING` 语义并入 classifier 的 `missing`/`branch-only`/`remote-only` 分类失败。
- `verifyReleaseSubjects(ctx, cr, snapshot)`：形状与仓集合校验不变；每仓 healthy 分类；non-KB HEAD 精确等于 reviewed SHA；KB reviewed SHA 必须是当前 HEAD 祖先且区间变更只允许 `approval.yml`、`cr.md`、`traceability.yml`、`review-loop.yml`、`change-requests/_backlog.yml` 与 `review-annotations/` 前缀（保持现有局部 Set + prefix，不抽配置）；artifact 逐文件与 digest 重核不变；删除 remote-ref-drift 分支。
- 返回合同保持 `{ok:true}` / `{ok:false, kind:'code'|'task'|'prd'|'sdd', details}`。
- CRLF→LF 与 `split(/\r?\n/)` 纪律不变；不新增依赖。

## 4. 验收条件

1. origin 不存在或网络不可用时，healthy committed worktree 构造 snapshot 成功；TASK-01 的 approve local-valid+remote-stale 红测试转绿。
2. dirty/wrong-branch/missing/path-unregistered 任一分类时构造与重核均零写入失败，错误 payload 含分类事实。
3. KB 白名单六个成员逐项通过、白名单外路径逐项失败；non-KB HEAD 漂移失败；plan/TASK/_index 摘要漂移返回 `task`，PRD/SDD 漂移返回 `prd`/`sdd`；LF/CRLF 等价。

## 5. 完成标志

`crctl.test.mjs` 全绿 + `buildReleaseSubjects`/`verifyReleaseSubjects` 调用链中无 `fetch` 与 remote-tracking ref 读取。

## 6. 接口契约

- 消费：TASK-01 产出的 approve 红测试集合。
- 产出：`buildReleaseSubjects(ctx, cr): Promise<releaseSubjectsV1>`（签名不变，语义收窄）；`verifyReleaseSubjects(ctx, cr, snapshot): Promise<{ok:boolean, kind?, details?}>`（签名不变，不再返回 `remote-ref-drift`）；TASK-04 以本地 `verifyReleaseSubjects` 作为 merge 共同前置。
