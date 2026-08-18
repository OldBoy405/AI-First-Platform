---
spec-id: ai-first-platform
version: "0.20.6"
id: CR-2026-045-TASK-13
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: "active pipeline 期间阻止 stale snapshot 覆盖 projection"
slug: active-pipeline-snapshot-guard
status: pending
estimate: 4h
depends-on:
  - CR-2026-045-TASK-12
created: 2026-08-18T18:39:17+08:00
---

# TASK-13 active pipeline 期间阻止 stale snapshot 覆盖 projection

## 1. 任务描述

修复 daemon snapshot 与 Runner/live CR 事件的竞态：installation-root 的周期性 snapshot 不能在 architecture pipeline 仍 active 时把 operational worktree 已确认的 CR status 覆盖回旧状态。保留 daemon 只负责收集/传输、server governance 负责 projection 的边界。

## 2. 涉及文件 / 模块

- `server/internal/governance/reconcile.go`
- `server/internal/governance/reconcile_test.go`
- `server/internal/daemon/crevents.go`（仅补 source/行为注释或回归测试时修改）

## 3. 实现要点

- 在已有 `ApplySnapshot` projection 入口复用 `pipeline_run` active 状态，active run 的 CR 不接受 root snapshot 的 status 覆盖。
- 不扫描所有 worktree、不在 daemon 复制状态机或 Git ancestor 算法。
- Runner/项目事件仍按现有路径更新 projection；pipeline 完成前 snapshot 只作为背景 reconcile 输入。
- 保留 archived/无 active pipeline CR 的 snapshot healing 行为。

## 4. 验收条件

1. 真实 PostgreSQL fixture：CR projection 已为 `tech-design-reviewed`，active architecture pipeline 存在，stale root snapshot 为旧状态；ApplySnapshot 后 status 不改变。
2. active pipeline 结束后，合法 snapshot 仍能修复真实 drift，且重复 snapshot 幂等。
3. daemon snapshot 现有节流、失败重试、history 传递测试全部通过；governance 全包通过。

## 5. 完成标志

active-run guard 与 stale snapshot 回归测试通过，daemon 仍不直接写 CR/status/Git，治理包和 Linux race 相关测试通过。

## 6. 接口契约

- 消费：TASK-07 Runner `pipeline_run` 生命周期、现有 `ApplySnapshot` 和 daemon snapshot event。
- 产出：`ApplySnapshot` 对 active pipeline CR 的确定性保护，不新增表、消息类型或状态。
