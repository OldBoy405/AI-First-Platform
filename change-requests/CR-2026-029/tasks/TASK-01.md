---
id: CR-2026-029-TASK-01
type: TASK
cr-ref: CR-2026-029
plan-ref: "change-requests/CR-2026-029/plan.md"
sdd-ref: "change-requests/CR-2026-029/sdd.md"
title: merge-feature-branch 新增发布联调走查步骤
slug: merge-verification-skill
status: pending
estimate: 2h
depends-on: []
created: "2026-08-10T20:14:00+08:00"
---

# TASK-01 merge-feature-branch 新增发布联调走查步骤

## 1. 任务描述

`skills/writeback/merge-feature-branch/SKILL.md` 在"更新 CR status"步骤后新增 Step 6 发布联调走查：各仓 trunk 拉取后以主 checkout 与 linked worktree 执行 `crctl status`/`worktree-path`/`next`，核对 multica CUSTOM.md 台账，把结论写入 `change-requests/{cr}/merge-verification.md` 并提交 knowledge-base trunk。原"输出摘要"顺延为 Step 7。新增发布类任务约定段。

## 2. 涉及文件

- tools：`skills/writeback/merge-feature-branch/SKILL.md`

## 3. 实现要点

- merge-verification.md 契约按 SDD §2.1（frontmatter: cr/verified-at/verified-by/repos[repo/trunk/merge-sha]；正文走查命令与结论、台账核账、异常处理）。
- 主 checkout 的 STATUS_DIVERGED 属预期（worktree 分支与 trunk 快照分离），linked worktree 本身不得有；worktree-path 无嵌套 `.rayai-worktrees`。
- 约定段："发布联调、merge 验证类工作归 merge pipeline，不创建开发 TASK"。

## 4. 验收条件

1. SKILL.md 含 Step 6 联调走查与 merge-verification.md 产出描述；
2. 含发布类任务约定段；
3. 原文 6 步结构保留，仅插入新步骤与顺延编号。

## 5. 接口契约

- **消费**：crctl status/worktree-path/next（只读）、merge-metadata 输出。
- **产出**：merge-verification.md 契约文本。
