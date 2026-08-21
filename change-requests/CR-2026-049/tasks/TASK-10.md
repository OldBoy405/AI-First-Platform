---
id: CR-2026-049-TASK-10
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: multica — commit_prefix_scan 调度任务与精确增量扫描
slug: multica-commit-prefix-scan-job
status: pending
estimate: 16h
depends-on: [CR-2026-049-TASK-04, CR-2026-049-TASK-09]
created: 2026-08-20T20:59:46+08:00
---

# TASK-10 — multica：commit_prefix_scan 调度任务与精确增量扫描

## 1. 任务描述

注册 `commit_prefix_scan` job（SDD §3.2 参数），实现 scope provider（workspace.repos 含 canonical KB URL 才 eligible）、固定 HEAD=B 到精确 cursor A 的分页遍历、`wip:` 优先分类、finding upsert（`ON CONFLICT DO NOTHING`）、全仓成功才通过 scheduler success result 原子写 `scan_cursors/config_rev/repository_ids`（SDD §3.2/§3.4，TD-B6）。

## 2. 涉及文件 / 模块

- `server/internal/scheduler/jobs_commit_prefix.go`
- `server/internal/service/commit_prefix_scan.go`（ScanRepo/classify 纯函数）
- `server/internal/drift/finding_repo.go`（UpsertFindings/result 编解码）
- `server/cmd/server/main.go`（注册）
- 测试：fake GitHub（100+ 多页、HEAD 前进、cursor missing、429/500）、scheduler job spec 测试

## 3. 实现要点

- `CommitPrefixScanJob(pool, resolver RepositoryBindingResolver, gh CommitSource) JobSpec`：Name=`commit_prefix_scan`、Cadence 1h、CatchUpLatestOnly、Scopes=动态 workspace 枚举、RunTimeout 10m、StaleTimeout 15m、HeartbeatInterval 30s、AllowStaleReentry true、MaxAttempts 3、RetryBackoff 1m/5m/15m。handler 必须以 `in.Scope.ID` 调用 `resolver.ResolveBindings(ctx, workspaceID, decls, workspace.repos, installations)`，禁止注入跨 workspace 共享的静态 `bindings`。
- `ScanRepo(ctx, in ScanRepoInput) (*ScanResult, error)`：`ScanRepoInput{Bound BoundRepo, PrevCursor *string, Heartbeat func(context.Context) error, Source CommitSource}`；先 `Source.Head(ctx, Bound.Token, Bound.Owner, Bound.Repo, Bound.Trunk) -> HeadSHA=B`；无 prevCursor → 只返回 baseline `Cursor=B`；否则从 `Source.Page(ctx, Bound.Token, Bound.Owner, Bound.Repo, Bound.Trunk, B, page, 100)` 分页，精确命中 `PrevCursor=A` 止，分类 `[B..A)`；每页调用 `Heartbeat(ctx)`；空页未命中/100 页未命中/429/403/5xx/timeout/malformed → error，不推进 cursor。
- `classify(subject, prefixes)`：`wip:` 优先 `wip-on-trunk/info`；任一白名单前缀命中为合法；否则 `bypass-commit/warn`。prefixes 只来自 `in.Bound.Prefixes`。
- finding `evidence={repository_id,trunk,commit_sha,commit_subject,scanned_at}`，`spec_id/cr_id=NULL`；`UpsertFindings` 使用 `INSERT ... ON CONFLICT DO NOTHING`。
- handler 成功返回 result v1（config_rev/repository_ids/scan_cursors/finding_count）；任一仓失败 → 返回 error，scheduler 记 FAILED 且不写新 cursor。

## 4. 验收条件

1. fake GitHub 100+ commits 多页：仅 (A,B] 被分类；扫描期间 HEAD 前进不影响本轮集合。
2. cursor 不在历史（非祖先）/429/截断 → plan FAILED 且 cursor 不推进；heartbeat 每页调用可断言。
3. 首次成功只建三仓 baseline、零 finding；24h 重扫同 commit 仅一行；job spec 字段与 SDD §3.2 一致。

## 5. 完成标志

`go test ./server/internal/scheduler/... ./server/internal/service/... ./server/internal/drift/...` 全绿。

## 6. 接口契约

- 消费：TASK-04 的 `drift_finding` dedup 索引；TASK-09 的 `BoundRepo`/`ListCommits`。
- 产出：
  - `CommitPrefixScanJob(pool, resolver RepositoryBindingResolver, gh CommitSource) JobSpec`；`JobNameCommitPrefixScan`。
  - `RepositoryBindingResolver.ResolveBindings(ctx, workspaceID, decls, wsRepos, installations) ([]BoundRepo, error)`；`CommitSource.Head(ctx, token, owner, repo, branch string) (string,error)`、`CommitSource.Page(ctx, token, owner, repo, branch, headSHA string, page, perPage int) ([]CommitMeta,error)`（primitive 参数避免 `ghsnapshot↔drift` import cycle）。
  - `ScanRepo(ctx, in ScanRepoInput) (*ScanResult, error)`；`ScanRepoInput{Bound BoundRepo, PrevCursor *string, Heartbeat func(context.Context) error, Source CommitSource}`；`ScanResult{HeadSHA string, Cursor string, Findings []drift.FindingInput}`。语义固定为从 `HeadSHA=B` 分页到精确 `PrevCursor=A`；未命中/截断/限流不推进 cursor。
  - `drift.UpsertFindings(...) (int64, error)`；result v1 结构（供 TASK-11 health 消费）。
