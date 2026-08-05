---
id: CR-2026-021-TASK-18
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 3 — cr-review-record/handover-cr/push-progress/write-requirement-prd/inbox-emit 改调 S2/S4/S3/S5/inbox-emit
slug: phase3-sync-skills-migrate
status: pending
estimate: 5h
depends-on: ["CR-2026-021-TASK-03", "CR-2026-021-TASK-04", "CR-2026-021-TASK-05"]
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

P3-03/P3-04/P3-05/P3-06/P3-07（SDD §6.1）：五处小型账本写入迁移，结构相似（各改一个字段/一个命令），一起做。
- `cr-review-record:53-54` 写 approval.yml supplemental-reviews → `crctl review-note`（S2）；reject/withdraw 走 `advance`；**重新定位该 skill = 补充意见记录 + 状态推进转发**。
- `handover-cr:66-68` / `resume-from-remote:86` 手改 owners → `crctl owner-set`（S4）。
- `push-progress:63-77` 手写 remote-ref/last-push/checkpoints → `crctl checkpoint-add`（S3）。
- `write-requirement-prd:87-89` 手改 prd-path → `crctl backlog-set --field prd-path`（S5）。
- `inbox-emit` SKILL 手写 notify-log → `crctl inbox-emit`。

## 涉及文件 / 模块

- `skills/cr/cr-review-record/SKILL.md`
- `skills/cr/handover-cr/SKILL.md`、`skills/sync/resume-from-remote/SKILL.md`
- `skills/sync/push-progress/SKILL.md`
- `skills/requirement/write-requirement-prd/SKILL.md`
- `skills/cr/inbox-emit/SKILL.md`

## 实现要点

`cr-review-record` 的重新定位是本任务里唯一需要"改结构"而非单纯替换调用的一处，需要重写其用途描述段，明确它不再是"写文件的技能"而是"记录补充意见 + 转发状态推进"。

## 验收条件

- AC-11（PRD，部分）：五份 SKILL.md 均已改调对应新子命令，`grep` 确认不再手写受控文件。

## 完成标志

五份 SKILL.md 修订完成并各自 grep 校验通过。
