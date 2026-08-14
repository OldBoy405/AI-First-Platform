---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-022-TASK-09
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 3 — inbox-emit 接口对齐（owner-handover 三处同步 + feedback-writeback/handover-cr 迁 CLI）（FR-15）
slug: inbox-emit-align
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-15（2.1-B）：inbox-emit 通知链接口对齐——真实入参 `cr-id`/`event`（枚举）/`to`（必填列表）/`payload`（可选 JSON）；补 `owner-handover` 事件三处同步；feedback-writeback/handover-cr 迁到 CLI 形态。

## 涉及文件 / 模块

- `skills/cr/inbox-emit/SKILL.md`：① 触发意图列表（L22-32）补 owner-handover（CR 负责人移交）② 输入参数表 event 枚举（L42-47）补 owner-handover，`to` 必填且取值来源写明（CR `owners.*.id` 或 feedback 发起人）③ 下游消费方声明 handover-cr 为 owner-handover 消费方
- `skills/cr/feedback-writeback/SKILL.md`：L98-108 从函数式 `inbox-emit(...)` 迁到 `crctl inbox-emit <cr> --event feedback-writeback-done --to [...] --payload '{outcome, specs-updated, ...}'`；`target/outcome/specs-updated/timestamp` 塞进 payload
- `skills/sync/handover-cr/SKILL.md`：L77-84 迁 CLI 形态 `crctl inbox-emit <cr-id> --event owner-handover --to <new-owner-id> --payload '{"subject":...,"body":...,"from":...}'`

## 实现要点

1. 三处同步缺一不可（只改参数表会造成"枚举齐了但触发场景没声明"的新漂移）
2. 迁移后的命令示例必须与 crctl inbox-emit 真实参数一致（grep crctl.mjs cmdInboxEmit 核实 flags：`--event`/`--to`/`--payload`）

## 验收条件

1. inbox-emit/SKILL.md 三处均含 `owner-handover`
2. feedback-writeback/handover-cr 无函数式 `inbox-emit(` 调用
3. 两处 CLI 示例含必填 `--to`
4. `--event` 取值均在枚举内（R7 落地后自动校验）

## 完成标志

验收 1~4 通过 + lint 复扫零违例（R7 落地后复扫零命中）。
