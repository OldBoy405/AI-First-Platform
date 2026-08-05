---
id: CR-2026-021-TASK-08
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: crctl worktree-path + report/cr-metrics（S9/S11，只读聚合）
slug: crctl-worktree-path-report-metrics
status: pending
estimate: 4h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-9/FR-11：两个只读子命令，不涉及 CAS/审计，实现成本低，一起做。
- `worktree-path <cr> --repo <r>`：派生 worktree bucket/path（`role==knowledge-base?"knowledge-base":repo.id` + 固定模板拼接）。
- `report` / `cr-metrics [--period P]`：跨 CR 状态直方图、SLA 阈值比较、周期活动计数聚合。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（2 个只读 dispatch case）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点

1. `worktree-path` 拼接规则从现有 4+ 处 SKILL prose（requirement-register/merge-feature-branch/push-progress/resume-from-remote）里提炼出唯一权威实现，不臆造新规则。
2. `report`/`cr-metrics` 的统计口径需与 `cr-dashboard`/`spec-dashboard` 现有 Step 2 手动统计逻辑对齐（读同一批账本文件，只是从手动变脚本化）。
3. 两者均不写任何文件，无需 CAS。

## 验收条件

- AC-6（PRD 相关部分）：`worktree-path` 给定输入返回确定性路径且不写任何文件（fs 调用 grep 检查）；`report`/`cr-metrics` 输出的统计与手动核对的账本状态一致。

## 完成标志

`node --test crctl.test.mjs` 全绿（含输入→输出映射用例，无需 CAS 用例）。
