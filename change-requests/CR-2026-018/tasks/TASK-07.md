---
id: CR-2026-018-TASK-07
type: TASK
cr-ref: CR-2026-018
plan-ref: "change-requests/CR-2026-018/plan.md"
sdd-ref: "change-requests/CR-2026-018/sdd.md"
title: dir-graph.yaml 状态机 scope 字段更新（FR-7）
slug: dir-graph-scope-update
status: pending
estimate: 2h
depends-on: ["CR-2026-018-TASK-02"]
assignee: ""
created: "2026-08-04T17:00:00+08:00"
---

## 1. 任务描述

将 `tools/dir-graph.yaml` 的 `change-request-track.state_machine.scope` 字段从 `"目标 workspace/change-requests/_backlog.yml"` 改为 `"目标 workspace/change-requests/{CR-ID}/cr.md"`，反映状态权威载体的变化（FR-7）。核实 `gates.json` 无 backlog 路径引用（SDD §6 已核实，本任务不改 gates.json，仅做二次确认）。

## 2. 涉及文件 / 模块

- `tools/dir-graph.yaml`（:210 附近）

## 3. 实现要点

- 只改 `scope` 字段的文字描述，不改 `transitions[]`/`wildcards` 等状态机语义本身（NFR-1，零变更）。
- 二次确认 `tools/skills/shared/crctl/gates.json` 是否有隐藏的 backlog 路径引用；若发现遗漏，本任务顺带修正并在完成标志中注明。

## 4. 验收条件

- `dir-graph.yaml` 的 scope 字段更新后，`crctl status` 输出的 `source.stateMachine` 字段无变化（该字段指向 dir-graph.yaml 文件路径本身，不是 scope 文字内容）。
- 状态机转移表（23 条声明/45 条展开）逐行 diff 确认零变更。

## 5. 完成标志

scope 字段更新完成；状态机转移表零变更已核实；gates.json 二次确认无遗漏引用（或已一并修正）。
