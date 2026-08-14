---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-022-TASK-12
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 3 — market-insights 索引统一 schema + 迁移脚本 + 节点 5 终态订正（FR-19）
slug: market-insights-schema
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-19（2.1-D + 流水线走查）：三个写入方统一 `docs/market-insights/_index.yml` 目标 schema；`market-to-plan.pipeline.json` 节点 5 终态 `planned` → `published`。

## 涉及文件 / 模块

- `skills/planning/conduct-market-research/SKILL.md`：L57/71 `entries:` → `insights:`；type `MARKET-INSIGHT` → `MARKET_INSIGHT`；status 保持 `published`（终态）；补 `file:` 字段
- `skills/planning/extract-market-insight/SKILL.md`：确认已符合目标 schema（`insights:`/`MARKET_INSIGHT`/`raw`），补「单一事实源」声明
- `skills/planning/write-insight-brief/SKILL.md`：status 写入 `briefed`（该文件批 4 评估下线，TASK-18；本任务先对齐再下线）
- `pipeline-templates/market-to-plan.pipeline.json`：节点 5（L76）`planned` → `published`，执行方明确 write-planning-entry
- 迁移脚本：`skills/writeback/scripts/migrate-market-insights.mjs`（SDD D-7 落点）+ 测试 fixture（若 `docs/market-insights/_index.yml` 存在旧字段名历史数据才需执行迁移）

## 实现要点

1. 三份 SKILL.md **同一 commit 原子提交**（判据 2：多 skill 共用数据契约）
2. 索引头补「单一事实源」声明（防第四个写入者再漂移）
3. 迁移脚本入库版本化（遵守纪律 #7，会话内不现写）；fixture 覆盖旧字段 → 新字段转换
4. 节点 5 终态改为 `published` 且写进 write-planning-entry 的步骤描述（不只存在于 pipeline prompt）

## 验收条件

1. 三写入方按统一 schema 读写互不破坏（模拟三写方各写一次）
2. 索引头含单一事实源声明
3. market-to-plan 节点 5 终态为 `published`
4. 三份 SKILL.md 在同一个 commit（git log 验证）
5. 迁移脚本 fixture 测试通过（若执行迁移，diff 记录在 PR 描述）

## 完成标志

验收 1~5 通过 + 迁移脚本测试绿。
