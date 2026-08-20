---
id: CR-2026-049-TASK-09
type: TASK
cr-ref: CR-2026-049
plan-ref: "change-requests/CR-2026-049/plan.md"
sdd-ref: "change-requests/CR-2026-049/sdd.md"
title: multica — repo binding resolver 与 ghsnapshot 扩展
slug: multica-repo-binding-ghsnapshot
status: pending
estimate: 10h
depends-on: [CR-2026-049-TASK-08]
created: 2026-08-20T20:59:46+08:00
---

# TASK-09 — multica：repo binding resolver 与 ghsnapshot 扩展

## 1. 任务描述

实现每 workspace 仓库访问绑定：generated declaration 的 canonical URL 必须逐一出现在 `workspace.repos`（现有持久化契约只有 URL/description，trunk 只取 generated declaration）；从 workspace 的 `github_installation` 中解析对 owner/repo 有 Contents:Read 的唯一 installation；复用 `ghsnapshot.Client` 的 App JWT/installation token 缓存，扩展 `ResolveRepositoryAccess` 与 `ListCommits`（SDD §3.3/§3.4，TD-B5）。

## 2. 涉及文件 / 模块

- `server/internal/integrations/ghsnapshot/client.go`（扩展访问解析与 commits 读取）
- `server/internal/drift/binding.go`（resolver 纯逻辑 + 错误码）
- 测试：fake GitHub server（token mint、repo access、SSH canonicalize、多 installation）

## 3. 实现要点

- `ResolveRepositoryAccess(ctx, installationIDs []int64, owner, repo string) (installationID int64, err error)`：对每个 installation mint token 后检查 Contents:Read；零个 → `repository_access_missing`，多个 → `repository_access_ambiguous`。
- `ListCommits(ctx, token, owner, repo, branch string, opts ListCommitsOptions) ([]CommitMeta, error)`：`GET /repos/{owner}/{repo}/commits?sha=<url.Values 编码>&per_page=&page=`；`CommitMeta{SHA, Subject}`；subject 取 message LF 规范化首行；403/429/5xx、timeout、malformed JSON 均结构化错误（不含 token/header）。
- `drift.ResolveBindings(ctx, workspaceID, decls, wsRepos []RepoData, installations []GitHubInstallation) ([]BoundRepo, error)`：URL 规范化（SSH→HTTPS owner/repo）后精确相等；三仓全部成功才返回；`BoundRepo{RepoID, Owner, Repo, Trunk string, Prefixes []string, Token string}`。`Prefixes` 必须从对应 `RepoPrefixDecl` 原样绑定，禁止扫描任务重新读取静态配置。
- token 纪律：内存缓存，不落日志/result/错误。

## 4. 验收条件

1. fake GitHub：单 installation 绑定成功；零/双 installation 分别报 missing/ambiguous。
2. SSH URL canonicalize 后匹配；非 GitHub provider → `repository_provider_unsupported`。
3. 测试断言 error/result 不含 token；token 复用（缓存）可测。

## 5. 完成标志

`go test ./server/internal/integrations/ghsnapshot/... ./server/internal/drift/...` 全绿。

## 6. 接口契约

- 消费：TASK-08 的 `RepoPrefixDecl`/`GeneratedPrefixes`。
- 产出：
  - `ghsnapshot.ResolveRepositoryAccess(...) (int64, error)`、`ghsnapshot.ListCommits(...) ([]CommitMeta, error)`、`CommitMeta{SHA, Subject}`。
  - `drift.ResolveBindings(...) ([]BoundRepo, error)`、`BoundRepo{RepoID, Owner, Repo, Trunk string, Prefixes []string, Token string}`（供 TASK-10 扫描消费）。
