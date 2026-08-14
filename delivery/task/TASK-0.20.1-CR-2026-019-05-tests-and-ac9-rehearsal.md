---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-019-TASK-05
type: TASK
cr-ref: CR-2026-019
plan-ref: "change-requests/CR-2026-019/plan.md"
sdd-ref: "change-requests/CR-2026-019/sdd.md"
title: 测试固化含 AC-9 merge-tree 演练入库
slug: tests-and-ac9-rehearsal
status: pending
estimate: 8h
depends-on: ["CR-2026-019-TASK-02", "CR-2026-019-TASK-03", "CR-2026-019-TASK-04"]
assignee: ""
created: "2026-08-04T17:36:00+08:00"
---

## 任务描述

在 `test/crctl.test.mjs`（node:test，无框架，临时目录 fixture）为三子命令补齐用例，并把当前一次性会话脚本 `_scratch/patch-task10b.mjs` 的 AC-9 merge-tree 零冲突演练固化为常驻测试用例（FR-7）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增用例）
- 删除 / 迁移 `_scratch/patch-task10b.mjs`（其逻辑并入测试）

## 实现要点（参考 SDD §7.2 测试矩阵）

| 用例 | 覆盖 AC | 断言 |
|---|---|---|
| task-done 正常/不存在/已done | AC-1 | status=done+done-at；后两者非零退出且文件无变更 |
| task-done 非法前置态 | AC-5 | fail(ILLEGAL_LEDGER_STATE)，无写 |
| merge-metadata 追加/去重 | AC-2 | merge-commits[] 含 {repo,trunk,sha}；重复 sha 不新增 |
| archive-move 正常 | AC-3 | 条目从 backlog 消失、history 出现带 final-status |
| archive-move history 侧 CAS 冲突 | AC-3 | CAS_CONFLICT 且两文件均无变更 |
| archive-move 非法前置态 | AC-5 | fail，无写 |
| AC-9 merge-tree 零冲突 | AC-7 | 共同祖先注册→分支推 ≥3 次 cr.md→master 注册新 CR→`git merge-tree --write-tree` 对 `_backlog.yml` 冲突数=0、exit 0 |

## 验收条件

1. `node --test test/crctl.test.mjs` 全绿，含上述全部新增用例。
2. AC-9 用例独立可跑（自建临时 git repo fixture），不依赖 `_scratch/` 残留脚本。
3. `_scratch/patch-task10b.mjs` 已删除或明确注明被测试取代。

## 完成标志

新用例全绿 + 既有 32 用例回归全绿（AC-8），`_scratch` 一次性脚本清理完毕。
