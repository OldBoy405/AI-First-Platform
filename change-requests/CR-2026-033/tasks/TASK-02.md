---
id: CR-2026-033-TASK-02
type: TASK
cr-ref: CR-2026-033
plan-ref: "change-requests/CR-2026-033/plan.md"
sdd-ref: "change-requests/CR-2026-033/sdd.md"
title: durable checkpoint envelope 与 matchEntryBlock 下沉（T03a）
slug: durable-checkpoint-envelope-entry-block
status: pending
estimate: 10h
depends-on:
  - CR-2026-033-TASK-01
created: 2026-08-13T19:06:07+08:00
---

## 任务描述

把 durable-tx 扩展到 checkpoint op（journal envelope/payload keys 校验），并把 crctl 私有 `matchEntryBlock()` 最小下沉到 yaml-subset 供 checkpoint editor 与旧账本命令共享。

## 涉及文件 / 模块

- 修改 `tools/skills/shared/crctl/scripts/lib/durable-tx.mjs`
- 修改 `tools/skills/shared/crctl/scripts/lib/yaml-subset.mjs`
- 修改 `tools/skills/shared/crctl/scripts/crctl.mjs`（task/owner/backlog/inbox editor 改 import）
- 修改 `tools/skills/shared/crctl/scripts/test/durable-tx.test.mjs`（checkpoint envelope 单测）

## 实现要点（引用 SDD §2.3/§3.2）

1. journal payload 校验：`checkpoint.repositories[]` 允许 `repo/remoteRef/baseSha/sourceSha/remoteBefore/phase`；顶层 `batchId/kbSourceSha/metadataCommit` 为 null 或 hex。
2. `inputDigest = sha256(JSON.stringify({cr, graphDigest}))`，只绑定 CR 与 graph；source facts 由各 repo 字段绑定。
3. `matchEntryBlock(text, id)` 导出：返回条目块边界或 null；读入先 CRLF→LF，跨行正则匹配失败硬失败不静默降级（纪律 #1/#4）。
4. crctl 现有调用点改为 import，行为不变（旧测试必须全绿）。

## 验收条件

1. durable-tx 单测覆盖 checkpoint envelope 合法/非法 payload 拒绝路径。
2. `matchEntryBlock` 对 CRLF 输入、EOF 条目、缺失条目返回正确；对重复/畸形条目硬失败。
3. crctl 旧 editor 相关测试全绿（import 下沉无行为变化）。

## 完成标志

两个 lib 修改 + 单测通过；commit 到 tools 仓 `requirement/CR-2026-033`。

## 接口契约

- 消费：TASK-01 的 `OPS.checkpoint`/`PAYLOAD_KEYS.checkpoint`/fault points。
- 产出：`matchEntryBlock(text: string, id: string) -> { start: number, end: number, lines: string[] } | null`（yaml-subset 导出，TASK-03 editor 消费）；durable checkpoint envelope 校验（TASK-04 消费）。
