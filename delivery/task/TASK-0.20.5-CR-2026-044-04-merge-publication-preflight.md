---
spec-id: ai-first-platform
version: "0.20.5"
id: CR-2026-044-TASK-04
type: TASK
cr-ref: CR-2026-044
plan-ref: "change-requests/CR-2026-044/plan.md"
sdd-ref: "change-requests/CR-2026-044/sdd.md"
title: merge 全仓 publication preflight 与双 recoverCommand
slug: merge-publication-preflight
status: pending
estimate: 8h
depends-on: [CR-2026-044-TASK-01, CR-2026-044-TASK-03]
created: 2026-08-17T00:02:54+08:00
---

# TASK-04 merge 全仓 publication preflight 与双 recoverCommand

## 1. 任务描述

在 `mergeCr` 内把本地 signed snapshot 重核提升为所有调用的共同前置，并在新事务（`payload.repos.length === 0`）首次 prepare 前增加全仓 publication preflight：内存冻结 `publicationFacts`，全部通过后才进入既有 prepare/publish/finalize saga；publication lag 错误返回 checkpoint recoverCommand，状态保持 `code-approved`。对应 PRD FR-05、AC-07~AC-11、AC-23（SDD §6.3）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（`mergeCr`）
- `skills/shared/crctl/scripts/test/merge-tx.test.mjs`（TASK-01 merge 红测试转绿 + journal 恢复测试）

## 3. 实现要点

- 共同前置：读 `approval.yml#code.release-subjects` 后调用 TASK-03 的纯本地 `verifyReleaseSubjects`；PRD/SDD → `APPROVED_ARTIFACT_DRIFT`；code/TASK 且 `payload.repos` 无 pushed 仓 → 返回 `phase:'release-drift'`；任一 pushed 仓 → `RELEASE_SUBJECT_DRIFT` blocked。此段置于现有 `payload.repos` 分支判断之前，对空与非空 journal 均生效。
- preflight 仅当 `payload.repos.length === 0`：逐仓 fetch origin，读本地 CR worktree HEAD、`refs/remotes/origin/requirement/{CR-ID}`、`refs/remotes/origin/{trunk}`；构造局部 `publicationFacts=[{repo, localHead, remoteSourceSha, trunkSha}]`（不写 journal）。
- source 缺失抛 `MERGE_SOURCE_MISSING`（`repo/ref/recoverCommand`），`remoteSourceSha !== localHead` 抛 `RELEASE_REMOTE_NOT_PUSHED`（`repo/head/remote/recoverCommand`）；两者的 `recoverCommand` 固定为 `crctl checkpoint {cr} --workspace {JSON.stringify(ctx.installRoot)}`，顶层 `recoverCommand` 仍为 merge 命令只用于 saga 技术失败。
- 全仓通过后逐仓首次 prepare：`sourceSha=remoteSourceSha`、`baseSha=trunkSha`，其余 prepare/commit-tree 逻辑不动；后续恢复、rebuild（使用 `rec.sourceSha` 冻结 source）、publish、finalize、lease 与 journal 合同全部不变。
- 不新增 journal 字段、不自动 checkpoint、不复制 ancestry 分类。

## 4. 验收条件

1. TASK-01 的 merge 红测试转绿：source 缺失/滞后均在首次 prepare 前失败，`payload.repos=[]`、无 candidate、状态 `code-approved`、错误 payload 的 recoverCommand 精确等于 checkpoint 命令。
2. checkpoint 补齐后重跑 merge 能进入 prepare/publish/finalize 正常完成。
3. 已有 prepared journal 续跑前执行共同 verifier：零 publish drift 走 release-drift，已有 publish drift 保持 blocked；trunk rebuild 使用冻结 `sourceSha`，不采纳移动 ref。
4. 本地 code/TASK drift 零 publish 仍触发唯一 `code-approved -> developing` 回退；PRD/SDD drift 硬阻断。

## 5. 完成标志

`merge-tx.test.mjs` 全绿 + `mergeCr` diff 仅新增共同前置段与 preflight 段，既有 saga 行为回归不变。

## 6. 接口契约

- 消费：TASK-03 产出的纯本地 `verifyReleaseSubjects(ctx, cr, snapshot)`。
- 产出：`mergeCr(ctx, input)` 公开签名不变；新增错误码语义 `MERGE_SOURCE_MISSING`/`RELEASE_REMOTE_NOT_PUSHED`（payload 含 checkpoint recoverCommand）；TASK-05 的 merge Skill 文本据此解释 publication lag。
