---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-15
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 1 — D3 test-report frontmatter 交 crctl test 生成
slug: phase1-test-report-frontmatter
status: pending
estimate: 2h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-17：`write-test-report/SKILL.md:51-84` 的 frontmatter（status/commands 按真实退出码）交既有 `crctl test --cmd` 生成，模型只写 `<!-- crctl:analysis-below -->` 以下分析段。不依赖任何新命令（`crctl test` 已存在）。

## 涉及文件 / 模块

- `skills/develop/write-test-report/SKILL.md`

## 实现要点

删除手写 frontmatter 的描述性步骤，改为"先跑 `crctl test --cmd ...` 生成 frontmatter，再补分析段"。

## 验收条件

- AC-9（PRD，部分）：`write-test-report` 不再手写 frontmatter。

## 完成标志

SKILL.md 修订完成并 grep 确认无手写 `status:`/`commands:` 的指引残留。
