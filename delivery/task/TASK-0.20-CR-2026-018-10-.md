---
id: CR-2026-018-TASK-10
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: 端到端 merge-tree 零冲突演练（AC-9，核心目标验收）
slug: end-to-end-merge-tree-verification
status: pending
estimate: 6h
depends-on: ["CR-2026-018-TASK-02", "CR-2026-018-TASK-08"]
assignee: ""
created: "2026-08-04T17:15:00+08:00"
---

## 1. 任务描述

实现 SDD §4.5，这是本 CR 的核心目标验收：构造一个 fixture workspace，演练"CR 分支上推进 ≥3 次状态 + master 侧并行注册另一 CR"的场景，对 `_backlog.yml` 执行 `git merge-tree --write-tree` dry-run，断言零冲突。这是复盘 CR-2026-012 中"9 个状态提交全撞同一文件"问题的直接反证。

## 2. 涉及文件 / 模块

- 临时 fixture git 仓库（测试用，不入库主仓）
- 可选：若发现有价值固化为长期回归，追加到 `crctl.test.mjs` 集成测试段

## 3. 实现要点

- 演练步骤：初始化 fixture 仓 → 建 CR-X 分支，用改造后的 crctl 推进 3 次状态（每次只应改 `change-requests/CR-X/cr.md`）→ 切回 master，注册 CR-Y（写 `_backlog.yml` 新条目，注册字段变更）→ `git merge-tree --write-tree master CR-X分支` → 断言输出不含 `_backlog.yml` 冲突标记。
- 对照组：若时间允许，可额外跑一次"改造前"版本（或手工模拟双写场景）对比冲突数，用于交付摘要中的量化对比（复盘基线：CR-2026-012 为 9 个提交全冲突）。

## 4. 验收条件

- AC-9：fixture 演练中 `merge-tree --write-tree` dry-run 对 `_backlog.yml` 零冲突。
- 演练脚本或步骤记录可复现（供后续 CR 参考或固化为回归用例）。

## 5. 完成标志

端到端演练通过，零冲突断言成立；演练过程/脚本已记录，可供 code-review 阶段复现验证。
