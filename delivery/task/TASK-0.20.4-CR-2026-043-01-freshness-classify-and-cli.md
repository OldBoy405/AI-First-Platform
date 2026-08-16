---
spec-id: ai-first-platform
version: "0.20.4"
id: CR-2026-043-TASK-01
type: TASK
cr-ref: CR-2026-043
plan-ref: "change-requests/CR-2026-043/plan.md"
sdd-ref: "change-requests/CR-2026-043/sdd.md"
title: freshness 只读分类深原语与 freshness CLI
slug: freshness-classify-and-cli
status: pending
estimate: 8h
depends-on: []
created: 2026-08-16T01:00:22+08:00
---

# TASK-01 freshness 只读分类深原语与 freshness CLI

## 1. 任务描述

在 `workspace-transactions.mjs` 新增第二层 freshness 只读分类（复用 `classifyRepoWorkspace` + 原生 ancestry），并在 `crctl.mjs` 的 `cmdWorkspace` 接线只读业务检查子命令 `workspace freshness`，含局部 try/catch 的审计语义。对应 FR-01、FR-02（SDD Phase A）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（新增导出函数）
- `skills/shared/crctl/scripts/crctl.mjs`（cmdWorkspace dispatch、HELP）
- `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs`（新建）

## 3. 实现要点

- `classifyWorkspaceFreshness(ctx, cr)` 按 SDD §4.1：逐仓（ctx.repositories 已按 id 排序）先 `classifyRepoWorkspace`；非 healthy → `freshness='unknown'`（reason=基础分类）；healthy 仓读 HEAD、`status --porcelain` 复核 clean（非空→unknown，reason=`dirty-during-check`）、`fetch origin`、读 `refs/remotes/origin/{trunk}`（失败→该仓 `WORKSPACE_TRUNK_UNAVAILABLE`，整体不可 fresh）。
- ancestry 判定顺序：`headSha==trunkSha` → fresh；`isAncestorOrThrow(trunkSha, headSha)` → fresh（ahead-only）；`isAncestorOrThrow(headSha, trunkSha)` → behind-clean（canFastForward=true）；否则 diverged。
- `isAncestorOrThrow(wtPath, a, b)`：`gitRun(wtPath, ['merge-base','--is-ancestor', a, b])`，status=0→true，status=1→false，其余→抛 `TxError('TX_GIT_FAILED', ..., {repo, args, status, stderr})`。不得把 status>1 当 false。
- 返回 SDD §2.1 `FreshnessResult`：`{ cr, repositories[RepoFreshnessFact], allFresh, syncable }`；`syncable = allFresh ? false : 无阻断项 && 存在 behind-clean`。
- `crctl.mjs`：cmdWorkspace 白名单扩为 `inspect|ensure|cleanup|freshness|sync`；freshness 分支**局部 try/catch**（不经 runTxAsync 后审计）：成功且 allFresh 不写 audit；成功但存在 non-fresh → `auditLog(kind:'workspace-freshness')` 后 `ok(...)`；TxError → 先 audit（含 code/阻断 repo）再 `fail(...)`。freshness/sync 不接受 `--workspace` 以外 flag（多余→BAD_ARGS）。
- 测试（`node --test`）：fresh（HEAD==trunk）、fresh（ahead-only）、behind-clean、diverged、六类非 healthy→unknown、dirty-during-check→unknown、trunk 缺失→WORKSPACE_TRUNK_UNAVAILABLE、merge-base status>1→TX_GIT_FAILED（mock/stub gitRun 或构造坏对象）、多仓稳定排序、Windows 路径身份与 CRLF（复用现有 fixture）。

## 4. 验收条件

1. 四类 freshness 与六类基础分类透传用例全部通过；ahead-only 稳定为 fresh，不误报 behind/diverged。
2. `crctl workspace freshness` 对 allFresh 输出 JSON 且 audit 无新增条目；对 behind-clean 输出 `syncable=true` 且写一条 `workspace-freshness` audit；对 diverged 返回成功的结构化 JSON（`freshness=diverged`、`allFresh=false`、`syncable=false`）并写业务阻断 audit，由上层 Skill 路由 `manual`，不得把正常读取结果转成 TxError。
3. 既有 `workspace-resolver.test.mjs` 与 cmdWorkspace inspect/ensure/cleanup 用例保持通过。

## 5. 完成标志

`node --test skills/shared/crctl/scripts/test/workspace-freshness.test.mjs` 通过 + 既有 crctl 测试全量回归通过 + lint 零新增报错。

## 6. 接口契约

- **消费**：`resolveRepositories`、`classifyRepoWorkspace`、`gitRun/gitMust`、`TxError`、`auditLog`（均为现有导出，不改签名）。
- **产出**：
  - `classifyWorkspaceFreshness(ctx, cr) -> { cr, repositories: RepoFreshnessFact[], allFresh: boolean, syncable: boolean }`（供 TASK-02 preflight 消费）
  - `isAncestorOrThrow(wtPath: string, a: string, b: string) -> boolean`（供 TASK-02 重核消费）
  - CLI `crctl workspace freshness <CR-ID> [--workspace <path>]`（供 TASK-03 Skill 消费）
