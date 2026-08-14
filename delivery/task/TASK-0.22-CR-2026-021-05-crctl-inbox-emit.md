---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-05
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: crctl inbox-emit（_backlog notify-log 事件追加）
slug: crctl-inbox-emit
status: pending
estimate: 3h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-6：`crctl inbox-emit <cr> --event <...>` 专命令，追加 `_backlog` 的 `notify-log`/`notify-pending`。不复用 `backlog-set`（事件追加语义比标量 set 重）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`
- `skills/cr/inbox-emit/SKILL.md`（本任务只做 crctl 侧；SKILL 改调在 TASK-18）

## 实现要点

1. `casWrite` 追加 `notify-log[]`，时间戳 crctl 生成。
2. 事件 payload 结构与既有 `notify-pending` 消费逻辑对齐（若下游已有读取约定，不臆造新结构）。

## 验收条件

- `_backlog` 对应 CR 条目的 `notify-log[]` 正确追加；CAS 冲突场景（并发追加）不产生半状态。

## 完成标志

`node --test crctl.test.mjs` 全绿（含本任务用例）。
