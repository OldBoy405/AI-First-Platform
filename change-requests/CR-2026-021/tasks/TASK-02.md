---
id: CR-2026-021-TASK-02
type: TASK
cr-ref: CR-2026-021
plan-ref: "change-requests/CR-2026-021/plan.md"
sdd-ref: "change-requests/CR-2026-021/sdd.md"
title: crctl review-record（S1，判断/写入分离）
slug: crctl-review-record
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-05T11:50:00+08:00"
---

## 任务描述

FR-1（SDD §4.1/§2.2）：新增 `crctl review-record <cr> --stage <requirement|tech-design|code> --from <payload.yml> [--bump-attempt]`。schema 校验非受控临时 payload 后，按 stage→文件名显式映射（`tech-design`→`sdd.yml` 非同名，是最容易写错的地方）写入 canonical `review-annotations/{file}.yml`（CAS+审计），成功后删除临时 payload。

## 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（新 dispatch case + `.crctl/tmp/review-{stage}.yml` 消费逻辑）
- `.gitignore`（补 `.crctl/tmp/`）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（新增用例）

## 实现要点

1. payload schema 校验：`verdict∈{pass,block}`、`blockers` 为列表、`dimensions` 齐全，失败 `SCHEMA_INVALID` 非零退出不写。
2. stage→文件名映射硬编码显式表：`requirement→requirement.yml`、`tech-design→sdd.yml`、`code→code.yml`；未知 stage → `STAGE_UNKNOWN`。
3. `reviewer=identity(ws)`、`reviewed-at=nowIso()` 由 crctl 生成，不接受 payload 或 CLI 覆盖。
4. `casWrite` 写 canonical 文件；`--bump-attempt` 时级联既有 attempt 记账逻辑（复用现有实现，不重写）。
5. 成功后删除 `.crctl/tmp/review-{stage}.yml`，避免残留误提交或跨 CR 串味。
6. CRLF 归一：读 payload 前 `replaceAll('\r\n','\n')`。

## 验收条件

- AC-1（PRD）：对 `tech-design` stage 调用，生成文件是 `review-annotations/sdd.yml`（非 `tech-design.yml`）；`verdict` 非法值时非零退出且不写入；成功后临时 payload 被删除。
- 前置态非法测试（`crctl.test.mjs` 既有模式，§0）：`status===1` + 结构化 `error.code` + 目标文件 `after===before`（写入前）。
- `--bump-attempt` 级联行为与既有 `attempt` 命令一致，无重复实现。

## 完成标志

`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿（含本任务新增用例）；`.gitignore` 已补 `.crctl/tmp/`。
