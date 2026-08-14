---
id: CR-2026-028-TASK-04
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: worktree-path 双根落地与多仓 workspace 场景（M3）
slug: worktree-path-dual-root
status: pending
estimate: 8h
depends-on: [CR-2026-028-TASK-01, CR-2026-028-TASK-02, CR-2026-028-TASK-03]
created: "2026-08-10T18:10:38+08:00"
---

# TASK-04 worktree-path 双根落地与多仓 workspace 场景

## 1. 任务描述

将 `cmdWorktreePath` 正式切换为以 Installation Workspace（InstWS）为根拼接 `.rayai-worktrees/{bucket}/requirement/{cr}`；验证 tools/multica worktree 显式 `--workspace <knowledge_base_worktree>` 场景下 InstWS 派生正确（SDD §4.1 实测证据）。FR-2 核心落地。

## 2. 涉及文件 / 模块

- tools 包 `skills/shared/crctl/scripts/crctl.mjs`：`cmdWorktreePath` 改根基准；`push-progress`/`pull-progress`/`resume-from-remote` 消费点核对
- tools 包 `skills/shared/crctl/scripts/test/crctl.test.mjs`：linked-worktree + 多仓场景用例

## 3. 实现要点

- SDD §3.3：`cmdWorktreePath(opWs, cr, repo)` → `join(deriveInstallRoot(opWs), '.rayai-worktrees', bucket, 'requirement', cr)`。
- 三个 sync Skill 只消费 `worktree-path` 命令返回值，不自行拼接（FR-2）。
- multica worktree 的 common-dir 指向 multica 自身 `.git`——tools/multica 场景必须以 `--workspace <knowledge_base_worktree>` 传入，由其派生 InstWS，绝不使用 cwd 的 common-dir（SDD §4.1 实测）。
- 不需要新增 `--tools-root`；help 仍不解析 workspace。

## 4. 验收条件

1. 黑盒：从 knowledge-base linked worktree 调用 `crctl worktree-path`，输出 InstWS 基准路径、无嵌套 `.rayai-worktrees`（与 TASK-01 回归用例叠加）。
2. 多仓：`--workspace <knowledge_base_worktree>` 场景下 tools/multica worktree 路径以主 checkout 为根，与既有 `.rayai-worktrees/{bucket}/requirement/CR-2026-028` 布局一致。
3. `push-progress`/`pull-progress`/`resume-from-remote` 在 linked-worktree 场景可正常消费 `worktree-path` 输出（不自行拼接出错误路径）。

## 5. 完成标志

三类场景用例绿 + sync 三 Skill 消费路径正确 + commit 完成。

## 6. 接口契约

- **消费**：TASK-02 产出正式版 `deriveInstallRoot(opWs)`；TASK-03 产出 loader 签名。
- **产出**：
  - `cmdWorktreePath(opWs: string, cr: string, repo: {id: string, role: string}): string`（正式版，根=InstWS）
  - `push-progress`/`pull-progress`/`resume-from-remote` 继续只消费 `worktree-path` stdout（接口不变，行为修正）
  - 下游 TASK-05/06 在提示词中依赖此路径语义。
