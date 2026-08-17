---
spec-id: ai-first-platform
version: "0.20.5"
id: CR-2026-044-TASK-01
type: TASK
cr-ref: CR-2026-044
plan-ref: "change-requests/CR-2026-044/plan.md"
sdd-ref: "change-requests/CR-2026-044/sdd.md"
title: 冻结失败向量红测试
slug: freeze-failure-vectors-red-tests
status: pending
estimate: 4h
depends-on: []
created: 2026-08-17T00:02:54+08:00
---

# TASK-01 冻结失败向量红测试

## 1. 任务描述

在既有测试文件中写入表达目标行为的红测试，固化三类失败向量：① local valid + remote stale 时 approve/merge 被误拒；② TTY 输入 `y/Y` 误入 reject 回退；③ merge publication lag 缺 recoverCommand。红测试对基线 `8f530589` 必须失败且失败原因精确（PRD AC-01/AC-03/AC-07/AC-08/AC-16 的先行证据）。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增 3 组红测试）
- `skills/shared/crctl/scripts/test/merge-tx.test.mjs`（新增 2 组红测试）

## 3. 实现要点

- 复用既有 bare remote fixture：`crctl.test.mjs` 现有 approve TTY fixture 与 `merge-tx.test.mjs` 的三仓 fixture。
- 红测试 1（approve 路径）：构造 code-reviewing CR，本地 snapshot 与 worktree 一致，将 origin requirement ref 落后本地 HEAD 一个提交，断言 approve-code 成功进入 code-approved——当前实现返回 remote-ref-drift，故失败。
- 红测试 2（TTY）：以 `y`、`Y`、` yes ` 三种输入参数化调用 approve，断言进入批准事务——当前实现走 reject 回退，故失败。
- 红测试 3（merge）：code-approved CR，某仓远端 requirement ref 缺失/滞后，断言返回 `MERGE_SOURCE_MISSING`/`RELEASE_REMOTE_NOT_PUSHED` 且 `payload.repos` 为空、`recoverCommand` 为 checkpoint 命令——当前实现在逐仓 prepare 内以 `RELEASE_SUBJECT_DRIFT`/`MERGE_SOURCE_MISSING` 不同语义失败，故失败。
- 测试命名带 `CR-2026-044` 前缀，便于后续 TASK 定位转绿集合。

## 4. 验收条件

1. 5 组红测试已入库且对基线代码失败，失败断言信息能指出“当前为 remote 依赖/仅接受 yes/缺 checkpoint recoverCommand”。
2. 除红测试外，既有全量测试不新增失败（`node --test skills/shared/crctl/scripts/test/*.test.mjs` 中仅本 TASK 新增用例红）。
3. 不修改任何生产代码与 Pipeline JSON。

## 5. 完成标志

红测试入库 + 失败原因核对通过 + 其余测试零新增失败。

## 6. 接口契约

- 消费：无上游 TASK。
- 产出：`test('CR-2026-044 approve local-valid+remote-stale ...')`、`test('CR-2026-044 TTY y|yes ...')`、`test('CR-2026-044 merge publication preflight ...')` 等测试名集合；TASK-02 转绿 TTY 组，TASK-03 转绿 approve 本地组，TASK-04 转绿 merge 组。
