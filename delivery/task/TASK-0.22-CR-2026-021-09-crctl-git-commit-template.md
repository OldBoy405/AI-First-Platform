---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-09
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: crctl git commit --template（S10，既有命令扩展）
slug: crctl-git-commit-template
status: pending
estimate: 3h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-10：给现有 `crctl git commit` 加 `--template <kind>` 分支（`register`/`task-breakdown`/`writeback`/…），按 kind 生成规范 commit message。不是新增顶层子命令，同现有 git commit 白名单前置态。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（`git commit` 分支内加格式化逻辑）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点

1. 模板 kind 从现有各 SKILL 手拼的 commit message 里提炼（`requirement-register:114`/`write-dev-tasks:80`/`writeback-traceability:75`），不臆造新格式，保持与既有 commit 历史风格一致（如 `[cr] {cr_id}: ...`）。
2. 不改变现有 `-m` 直传路径的白名单校验，`--template` 是新增可选分支。

## 验收条件

- `git commit --template register` 生成的 message 符合从既有 3 处提炼的约定格式。

## 完成标志

`node --test crctl.test.mjs` 全绿（含本任务用例）。
