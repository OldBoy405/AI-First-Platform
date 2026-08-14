---
spec-id: ai-first-platform
version: "0.22"
id: CR-2026-021-TASK-17
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: Phase 3 — review-* 三个评审 SKILL + write-test-report 改调 S1/attempt
slug: phase3-review-skills-migrate
status: pending
estimate: 4h
depends-on: ["CR-2026-021-TASK-02"]
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

P3-01/P3-02（SDD §6.1）：`review-code`/`review-tech-design`/`review-requirement` 从直接 Write `review-annotations/{stage}.yml` + 手写 review-loop，改为 `crctl review-record --stage X --from <payload> --bump-attempt`；`write-test-report` 手写 review-loop 进 traceability 改为 `crctl attempt`（既有命令）。

## 涉及文件 / 模块

- `skills/develop/review-code/SKILL.md`、`review-tech-design/SKILL.md`
- `skills/requirement/review-requirement/SKILL.md`
- `skills/develop/write-test-report/SKILL.md`

## 实现要点

三份 review-* SKILL 改为"agent 先把判断写入 `.crctl/tmp/review-{stage}.yml`，再调 `crctl review-record`"，注意各自 stage 参数正确（`review-tech-design` 用 `--stage tech-design`，产出 `sdd.yml`）。

## 验收条件

- AC-11（PRD，部分）：三份 review-* SKILL 与 write-test-report 不再含手写受控文件的指引，`grep` 确认。

## 完成标志

四份 SKILL.md 修订完成，且实测跑一次 review-record 调用链路（在临时 workspace）验证 stage 映射正确。
