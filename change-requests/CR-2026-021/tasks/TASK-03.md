---
id: CR-2026-021-TASK-03
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: crctl review-note（S2，supplemental-reviews 追加）
slug: crctl-review-note
status: pending
estimate: 3h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-2：新增 `crctl review-note <cr> [--stage <s>] --note <text>`，向 `approval.yml` 的 `supplemental-reviews[]` 追加一条记录（CAS+审计）。操作者身份由 `identity(ws)` 生成，**不接受 `--by` 参数**（不变量 7：不得触碰 `approval.yml#requirement/#tech-design/#dev-start/#code` 四段审批本体）。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（新 dispatch case）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点

1. 只写 `supplemental-reviews[]` 数组追加，不得修改 `approval.yml` 的 `#requirement`/`#tech-design`/`#dev-start`/`#code` 四个审批段（grep 静态核查）。
2. `casWrite` 保护；`--by` 参数若传入应报错拒绝（校验 CLI 层面拒绝，不是静默忽略）。

## 验收条件

- AC-2（PRD）：调用后 `supplemental-reviews[]` 追加一条含 crctl 生成身份的记录；传入 `--by` 报错拒绝。
- grep `crctl.mjs` 本命令实现，确认无对四段审批本体的写路径（合 SDD §7 安全边界）。

## 完成标志

`node --test crctl.test.mjs` 全绿（含本任务用例）。
