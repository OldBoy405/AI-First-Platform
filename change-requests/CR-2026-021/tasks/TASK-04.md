---
id: CR-2026-021-TASK-04
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: crctl checkpoint-add / owner-set / backlog-set（S3/S4/S5，白名单字段写子命令）
slug: crctl-checkpoint-owner-backlog-set
status: pending
estimate: 6h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-3/FR-4/FR-5：三个结构同构的 `_backlog` 字段级白名单写子命令，一起实现测试模式共用。
- `checkpoint-add <cr> --repo <r> --sha <sha> [--remote-ref <ref>]`：追加 `checkpoints[]` + 更新 `remote-ref`/`last-push-at`(crctl 生成)/`last-push-by`(identity)。
- `owner-set <cr> --role <requirement|development|test> --id <id>`：写 `owners.{role}.id` + `assigned-at`(crctl 生成)。
- `backlog-set <cr> --field <prd-path|sdd-path> --value <v>`：白名单标量，硬拒 `status`/`updated-at`/`owners`/`merge-commits`。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（3 个新 dispatch case）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点

1. 三者均用 `casWrite` 保护单文件（`_backlog.yml`）字段级更新，复用 `matchEntryBlock` 定位 CR 条目。
2. `backlog-set` 的白名单硬编码为**白名单**而非黑名单：只列 `prd-path`/`sdd-path`，其余一律拒（`FIELD_NOT_ALLOWED`），为未来静态字段留扩展位但不预先开放。
3. `owner-set --id` 是业务数据（被指派人身份），由调用方传入，与「操作者身份必须 crctl 生成」原则不冲突（区分清楚，避免和 `--by` 类混淆）。

## 验收条件

- AC-3（PRD）：三命令分别正确更新对应字段；`backlog-set --field status` 硬拒（非零退出，`FIELD_NOT_ALLOWED`，提示改用 `advance`）。
- 前置态非法（如 CR 不存在）走既有 `ILLEGAL_LEDGER_STATE`/等价码 + 文件零变更快照对比。

## 完成标志

`node --test crctl.test.mjs` 全绿（含 3 命令新增用例，各覆盖正常/前置态非法/CAS 冲突）。
