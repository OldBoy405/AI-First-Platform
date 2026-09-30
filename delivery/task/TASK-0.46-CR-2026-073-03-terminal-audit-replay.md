---
spec-id: ai-first-platform
version: "0.46"
id: CR-2026-073-TASK-03
type: TASK
cr-ref: CR-2026-073
plan-ref: "change-requests/CR-2026-073/plan.md"
sdd-ref: "change-requests/CR-2026-073/sdd.md"
target-version: 0.46
title: 终态事件去重与清理重放回归
slug: terminal-audit-replay
status: pending
estimate: 10h
depends-on: [CR-2026-073-TASK-02]
created: 2026-09-30T13:05:00+08:00
---

## 任务描述

G3 / FR-5 / AC-5，兼顾 AC-4 的清理观察。消费 TASK-02 根与 actor 契约，在现有终态 adapter 内仅对同一业务事件重放去重；为合法入口/清理/去重留下可重复的隔离回归，不伪造旧历史。

## 涉及文件 / 模块

`tools/skills/shared/crctl/scripts/crctl.mjs` 的 `cmdMerge`、`cmdWritebackApply`、`cmdArchive` 业务审计调用与现有 `auditLogOnce`；`tools/skills/shared/crctl/scripts/test/terminal-audit.test.mjs`，复用 `merge-fixture.mjs`、`writeback-tx.test.mjs`、`archive-tx.test.mjs` 的临时仓方法。共享测试文件与 TASK-02 协调，不重写其测试。

## 实现要点

保持 `advance:{cr}:{commit}` 去重键；成功业务事件采用稳定的 txId/stage/phase 标识，release-drift 与成功分离，不把不同事务/阶段合并。事务已完成重放不增加相同 kind/event；被删除入口不可用于重放，应从存活的 install-root 重放。临时 fixture 断言清理不重建、不动旧审计行；journal/merge 算法不变。

## 验收条件

1. `cmd-05`（plan §6）：只跑 `CR073 terminal audit replay and cleanup`，对可重放的 writeback/archive 与 merge 合法路径验证同一业务事件不重复、不同阶段/事务不误合并。
2. 同一 `cmd-05` 验证清理后 worktree/txws 不复活、actor 保持 TASK-02 产出的身份，旧历史不被倒填；merge 若状态已禁止重入，则原状态机拒绝且无额外成功审计。测试范围仅临时三仓 fixture，不声称全仓。

## 完成标志

去重与定向回归落盘，保留真实运行结果；在 developing 内即时用 `crctl task done` 标记 `CR-2026-073-TASK-03`，不等待归档。若需回滚先撤本 TASK 再撤 TASK-02。

## 接口契约

- 消费 TASK-02 的完整内部契约：`cmdMerge(ws, positional, flags)`、`cmdArchive(ws, positional, flags)`、`cmdWritebackApply(ws, positional, flags, gates)` 事务前固定 actor，使用 `resolveRepositories(ws).installRoot` 作为 `auditLog(ws, record)` / `auditLogOnce(ws, record, dedupKey)` 的 `ws` 参数；outbox callback 使用该 actor；`auditLogOnce` 返回布尔值。
- 产出：原三个 adapter 对外签名与返回保持不变；同一 `{op}:{cr}:{txId}:{stage|phase}` 稳定业务事件经 `auditLogOnce(ws, record, dedupKey)` 至多追加一次，按真实 journal 稳定标识落实；不同阶段/事务及 release-drift 不得合并为同一 key。只 append、不迁移旧 JSONL。
