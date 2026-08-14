---
id: CR-2026-022-TASK-11
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 3 — architecture-design pipeline UUID 0016 迁移含 repairNodeId + seed 幂等（FR-18）
slug: uuid-0016-migrate
status: pending
estimate: 4h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-18（2.1-C）：`architecture-design.pipeline.json` 5 节点 UUID 前缀 `0014-*` 与 `resume-cr.pipeline.json` 撞号，破坏 seed 幂等。全部 5 个节点统一迁到未占用前缀 `0016-*`，同步 `repairNodeId` 自引用。

## 涉及文件 / 模块

- `pipeline-templates/architecture-design.pipeline.json`：节点 id `...0014-000000000001/002/003` 与 resume-cr 同前缀撞号（L36/45/51/74/82/91 附近）

## 实现要点

1. 全部 5 个节点（不只撞号的 3 个）迁到 `0016-*`——零散只改撞号会破坏「一条 pipeline 一个 UUID 前缀」约定（已占用：0002/0003/0010/0011/0013/0014/0015）
2. 必须同步 L51 附近 `repairNodeId: "...0014-000000000001"`（node-1 自引用，onBlock: route-to-repair-node 路由目标）→ `0016-...0001`
3. 改后：JSON 解析自检 + seed 幂等验证（同 seed 两次生成节点集合一致）
4. 报告 2.1-C 已占用前缀表同步标记 0016（TASK-19 收尾项，此处先改 JSON）

## 验收条件

1. architecture-design 全部节点 id 前缀为 `0016-`
2. `repairNodeId` 指向新 node-1 id
3. 两条流水线 JSON 解析通过；seed 幂等（重复 seed 不产生重复节点）
4. 与 resume-cr 无任何撞号前缀

## 完成标志

验收 1~4 通过。
