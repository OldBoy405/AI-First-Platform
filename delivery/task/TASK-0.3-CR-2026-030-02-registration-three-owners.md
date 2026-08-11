---
spec-id: ai-first-platform
version: "0.3"
id: CR-2026-030-TASK-02
type: TASK
cr-ref: CR-2026-030
plan-ref: "change-requests/CR-2026-030/plan.md"
sdd-ref: "change-requests/CR-2026-030/sdd.md"
title: 实现三 Owner Registration 与真实提交事件
slug: registration-three-owners
status: pending
estimate: 8h
depends-on: [CR-2026-030-TASK-01]
created: "2026-08-11T02:34:00+08:00"
---

# TASK-02 实现三 Owner Registration 与真实提交事件

## 1. 任务描述

落实 SDD §3.1～§3.4、§4.1～§4.3：`cr-init` 显式接收三角色 Owner，以一次时间戳写入三账本候选；注册 commit 成功后才使用真实 HEAD SHA 产生 status 与 owners 事件；`worktree-path` 返回 canonical branch。失败输出完整 `REGISTRATION_INCOMPLETE`，不分配第二个 CR-ID。

## 2. 涉及文件 / 模块

- tools：`skills/shared/crctl/scripts/crctl.mjs`
- tools：`skills/shared/crctl/scripts/test/crctl.test.mjs`

## 3. 实现要点

- `cmdCrInit(ws, gates, flags)` 要求 `requirement-owner`、`development-owner`、`test-owner`，缺任一参数零写入。
- `cr.md`、`_backlog.yml`、`_index.yml` 继续经 `casWriteMulti()`；兼容顶层 `owner` 只等于 requirement Owner。
- `cr-init` 自身不发 outbox；register commit 成功后调用既有事件 helper，status/owners 共用 `controlledGit(... rev-parse HEAD)` 的真实 SHA。
- `cmdWorktreePath()` 返回 `{op, cr, repo, bucket, branch, path}`，branch 来自 canonical 规则。
- commit 失败不读 HEAD、不发事件；逐项 outbox 失败记录 warning 与 `EMIT_FAILED`，不反转 commit。

## 4. 验收条件

1. 三个不同 Owner 在 cr.md/backlog/audit/JSON 与三条 initial history 中逐项一致且共用一次时间戳。
2. 缺任一 Owner 时三账本、audit、outbox 均不变；CAS conflict 不产生部分注册。
3. registration commit 后 status/owners 事件 SHA 等于真实 HEAD；commit 失败零事件，outbox 失败保留 commit 并返回 warning。
4. `worktree-path` 的 branch/bucket/path 与权威规则一致。

## 5. 完成标志

TASK-01 中 AC-1～AC-6 对应测试转绿，既有测试通过，`tasks/_index.yml` 中 TASK-02 标记 `done`。

## 6. 接口契约

- **消费**：`casWriteMulti(writes)`；`controlledGit(ws, sub, args, cwd, caller)`；`emitOutboxEvent(ws, ev)`。
- **产出**：`cr-init --requirement-owner <id> --development-owner <id> --test-owner <id>`；`worktree-path` JSON 新增 `branch: string`；register execution context 包含真实 `commit_sha` 与三 Owner 投影。
