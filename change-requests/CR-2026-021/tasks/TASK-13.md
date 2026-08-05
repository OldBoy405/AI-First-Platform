---
id: CR-2026-021-TASK-13
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 1 — D7 merge-commits 3 字段 + approve-* 折叠为 crctl approve
slug: phase1-merge-commits-approve-fold
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-14/FR-15（Phase 1，不依赖新命令，当场会失败，最紧急）：
- D7：`writeback-traceability/SKILL.md:84,107,120`、`feature-writeback.pipeline.json` node-4:67 的 6 字段校验改为 `{repo,trunk,sha}` 必填、`branch` 可选。
- approve-*：`approve-code`/`approve-tech-design`/`approve-dev-start`/`approve-requirement` 删手写 `approval.yml` 段 + 删 `cr-status-set` 步 + 删"回滚 approval.yml"错误处理，改为运行 `crctl approve --stage X`（TTY）。

## 涉及文件 / 模块

- `skills/writeback/writeback-traceability/SKILL.md`
- `pipeline-templates/feature-writeback.pipeline.json`（node-4）
- `skills/develop/approve-code/SKILL.md`、`approve-tech-design/SKILL.md`、`approve-dev-start/SKILL.md`、`skills/requirement/approve-requirement/SKILL.md`

## 实现要点

1. D7 改动不依赖任何新子命令，`merge-commits` 生产者（`merge-feature-branch`，CR-2026-020 FR-8）已产出 3 字段，纯消费侧校验口径修正。
2. approve-* 四个 SKILL 统一改为"运行 `crctl approve --stage X`（TTY），它校验证据+写 approval.yml+级联 advance"，不需要等本轮任何新子命令（`crctl approve` 已存在）。

## 验收条件

- AC-9（PRD，部分）：`writeback-traceability` 对 3 字段 `merge-commits` payload 校验通过；`approve-*` 系列 SKILL.md 不再含手写 `approval.yml` 的 YAML 段。

## 完成标志

4 份 approve-* SKILL + writeback-traceability SKILL + pipeline node-4 均已修订并 grep 确认无残留旧口径。
