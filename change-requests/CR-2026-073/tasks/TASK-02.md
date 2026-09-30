---
id: CR-2026-073-TASK-02
type: TASK
cr-ref: CR-2026-073
plan-ref: "change-requests/CR-2026-073/plan.md"
sdd-ref: "change-requests/CR-2026-073/sdd.md"
target-version: 0.46
title: 终态审计根与事前身份绑定
slug: terminal-audit-root-actor
status: pending
estimate: 8h
depends-on: []
created: 2026-09-30T13:05:00+08:00
---

## 任务描述

G2 / FR-4 / AC-4。按 SDD §3.2 统一三个终态 CLI adapter 的审计根与身份，在事务可能清理 authority 前固定 actor；提供 TASK-03 的根/身份契约。

## 涉及文件 / 模块

`tools/skills/shared/crctl/scripts/crctl.mjs` 的 `cmdMerge`、`cmdWritebackApply`、`cmdArchive`、`identity` / `auditLog` / `auditLogOnce` 调用点；`tools/skills/shared/crctl/scripts/test/terminal-audit.test.mjs` 的三入口断言（可与 TASK-03 同一文件分离案例）。不改 durable transaction 算法。

## 实现要点

一次 `resolveRepositories(ws)` 所得 `ctx.installRoot` 是对应 audit 与 advance audit 的根；`authWs` 仅是 merge 事务 authority，不能拿来写持久日志。事务前在合法入口求身份，`identity(ws)` 不可证明时回退 `identity(ctx.installRoot)`；均不可证明要在副作用前报技术错误，禁止写 `unknown`。archive 回调和 writeback outbox 的 actor 使用冻结值，清理后绝不再访问已删 ws 求身份。保留 writeback 原 `advance:{cr}:{commit}` 去重键。

## 验收条件

1. `cmd-04`（plan §6）：定向 `CR073 terminal audit root and actor` 案例，用隔离临时三仓 fixture 从 KB 主 checkout、CR worktree、txws 在各自合法阶段执行对应终态入口，观察 merge/writeback/archive 与 advance audit 位于同一 install-root 且 actor 可证明。
2. 同一 `cmd-04` 核查 archive 清理后不为写审计重建 txws/worktree；身份读取早于事务副作用，未知身份拒绝伪造。该案例仅验证终态审计入口，不宣称全仓测试。

## 完成标志

三个 adapter 内根/身份与回调改动、定向三入口断言落盘，真实运行结果保留；在 developing 内即时用 `crctl task done` 标记 `CR-2026-073-TASK-02`。不可在 TASK-03 尚依赖时单独撤本 TASK。

## 接口契约

- 消费：`resolveRepositories(ws)` 返回 `{ installRoot, ... }`；`identity(ws)` 返回本地配置或 git 用户名（不可证明时旧实现返回 `unknown`）；`auditLog(ws, record)`、`auditLogOnce(ws, record, dedupKey)` 为现有内部签名。
- 产出（供 `CR-2026-073-TASK-03` 消费）：`cmdMerge(ws, positional, flags)`、`cmdArchive(ws, positional, flags)`、`cmdWritebackApply(ws, positional, flags, gates)` 在终态事务前固定 actor、仅以 `ctx.installRoot` 为 `auditLog(ws, record)` / `auditLogOnce(ws, record, dedupKey)` 的 `ws` 参数；调用方 workspace/operational authority/actor 各自独立；outbox callback 使用相同 actor。`auditLogOnce` 的布尔去重结果与原签名不变。
