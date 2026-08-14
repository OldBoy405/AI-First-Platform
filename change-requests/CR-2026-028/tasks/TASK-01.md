---
id: CR-2026-028-TASK-01
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: 修复 worktree-path 嵌套路径 bug（M1 前置）
slug: fix-worktree-path-nested-bug
status: pending
estimate: 4h
depends-on: []
created: "2026-08-10T18:10:38+08:00"
---

# TASK-01 修复 worktree-path 嵌套路径 bug

## 1. 任务描述

修复 `crctl worktree-path` 从 knowledge-base linked worktree 调用时返回嵌套路径 `<worktree>/.rayai-worktrees/{bucket}/requirement/{cr}`（第二层 `.rayai-worktrees` 拼接在 worktree 内部，路径不存在）的问题。这是 FR-2 的依赖项，也是 M2/M3 联调的前置。

## 2. 涉及文件 / 模块

- tools 包 `skills/shared/crctl/scripts/crctl.mjs`：`cmdWorktreePath`
- tools 包 `skills/shared/crctl/scripts/test/crctl.test.mjs`：linked-worktree 回归用例

## 3. 实现要点

- 参考 SDD §3.3：`cmdWorktreePath` 的根基准改为 Installation Workspace（`deriveInstallRoot` 产物），worktree 内调用不再拼出第二个 `.rayai-worktrees`。
- 本 TASK 允许先行引入最简 `deriveInstallRoot`（非 git 回退 OpWS），供 M2 正式落地；SDD §4.1 算法。

## 4. 验收条件

1. 临时 git 仓建 linked worktree，从 worktree 内调用 `crctl worktree-path`，输出为 `<主checkout>/.rayai-worktrees/{bucket}/requirement/{cr}`，路径 `fs.existsSync` 语义正确（目录可创建/可寻址），无嵌套 `.rayai-worktrees`。
2. 主 checkout（非 worktree）调用输出与既有行为一致（路径不变）。
3. `crctl.test.mjs` 新增用例通过；既有用例全量通过（无回归）。

## 5. 完成标志

linked-worktree 用例绿 + 既有套件全绿 + 本 TASK commit 完成。

## 6. 接口契约

- **消费**：无上游 TASK。
- **产出**：
  - `deriveInstallRoot(opWs: string): string` — 最简版（SDD §4.1）；`cmdWorktreePath(opWs, cr, repo): string` 消费。
  - `cmdWorktreePath(opWs: string, cr: string, repo: {id: string, role: string}): string` — 返回 `<installRoot>/.rayai-worktrees/{bucket}/requirement/{cr}`；bucket 语义不变（knowledge-base 角色用 `knowledge-base`，其余用 repo.id）。
  - 下游 TASK-04 正式接管该签名（本 TASK 仅修正根基准，不改签名）。
