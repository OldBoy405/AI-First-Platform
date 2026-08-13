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

1. `OPS` 与 `PAYLOAD_KEYS` 私有数组各加入字符串 `checkpoint`；journal envelope 加入 `checkpoint: null`。durable-tx 只做 generic 校验：op 在 OPS、至多一个 payload 非 null、非 null payload key 与 op 相同；不得读取或特判 checkpoint 内部 repo/SHA/ref/phase 字段。
2. `FAULT_POINTS` 唯一数组加入 TASK-01 冻结的 5 个 checkpoint point；`crctl.mjs` 继续使用既有 import，不新建第二份列表。
3. 将现有 `matchEntryBlock(text, id)` 原样下沉并导出，保持返回 `{start,end,text,indent}|null`、首个精确 id 命中与缺失返回 null 的行为；输入由调用方先 CRLF→LF。crctl 现有调用点改 import，旧测试必须全绿。

## 验收条件

1. durable-tx 单测只覆盖 generic checkpoint op/payload slot：合法 op-payload 对应、多个 payload、payload 与 op 不一致；不得加入 repo/SHA/ref/phase 业务 fixture。TASK-01 的 generic envelope/fault point 红测转绿，checkpoint CLI 红测留给 TASK-04。
2. `matchEntryBlock` 对 LF 输入、EOF 条目、缺失条目保持现有返回；输出精确为 `{start,end,text,indent}|null`，现有 editor 行为不变。
3. crctl 旧 editor 相关测试全绿；源码仅存在 durable-tx 一份 `FAULT_POINTS` 数组；durable-tx 无 `checkpoint.repositories` 或 checkpoint phase 特判。

## 完成标志

两个 lib 修改 + 单测通过；commit 到 tools 仓 `requirement/CR-2026-033`。

## 接口契约

- 消费：TASK-01 冻结的 checkpoint envelope/fault point expected set。
- 产出：`matchEntryBlock(text: string, id: string) -> { start: number, end: number, text: string, indent: number } | null`（yaml-subset 导出，TASK-03 editor 消费）；generic checkpoint envelope slot 与唯一 `FAULT_POINTS` 登记（TASK-04 消费）。
