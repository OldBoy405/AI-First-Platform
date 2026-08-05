---
id: CR-2026-022-TASK-04
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 2.5 — git commit --template 补显式 --cr 旗标（FR-10）
slug: template-explicit-cr
status: pending
estimate: 3h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-10（2.1-F）：`resolveTemplateCr` 补显式 `--cr <cr-id>` 旗标，调用方直传已知值、跳过「分支探测 → subject 正则」反向解析；原路径保留为兜底。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`：`resolveTemplateCr`（约 :1953-1961）+ `applyCommitTemplate`/`cmdGit` 旗标解析
- `skills/requirement/requirement-register/SKILL.md` Step 4：commit 调用改为带 `--cr {cr-init 返回值}`（与 TASK-03 同文件协同）

## 实现要点（SDD §3.1）

1. `--cr` 提供时：校验格式 `^CR-\d{4}-\d{3}$`（不合 BAD_ARGS）+ `_backlog` 条目存在性（不在则 fail），直用，不调 `resolveTemplateCr`
2. `--cr` 缺省：走原分支探测 → subject 正则兜底 → fail 路径，存量调用零破坏
3. requirement-register Step 4 示例改为 `crctl git commit --template register --cr {cr_id} -m "..."`（cr_id 为 Step 2 cr-init 返回值）

## 验收条件

1. master 分支（非 requirement/CR-*）`git commit --template register --cr CR-2026-999 -m "..."` 直传成功、不触发反向解析
2. 非法格式 `--cr abc` 被 BAD_ARGS 拒绝；不存在 CR 被拒绝
3. 不带 --cr 在 requirement/CR-* 分支上原逻辑可用
4. requirement-register SKILL 示例含 `--cr`

## 完成标志

验收 1~4 通过 + crctl.test.mjs 新增用例全绿 + 既有 commit --template 用例不回归。
