---
id: CR-2026-020-TASK-08
type: TASK
cr-ref: CR-2026-020
plan-ref: "change-requests/CR-2026-020/plan.md"
sdd-ref: "change-requests/CR-2026-020/sdd.md"
title: knowledge-base：优化方案文档 §4.2 traceability 表述修正
slug: writeback-plan-doc-fix
status: pending
estimate: 1h
depends-on: []
assignee: ""
created: "2026-08-04T22:21:12+08:00"
---

## 任务描述

跨仓小任务，无依赖，可随时插入。`docs/product/writeback-流水线耗时分析与优化方案.md` §4.2 的表格把 `specs/{spec_id}/traceability.yml` 列入"全量重建"一类，与 SDD §8 D3 核实的真实文件形态（989 行跨 CR 累积、含手工注释与历史缺口）不符，需修正为与 SDD 一致的"头部更新 + 段追加"。

## 涉及文件 / 模块

- `docs/product/writeback-流水线耗时分析与优化方案.md`（knowledge-base 仓，非 tools 仓）

## 实现要点（引用 SDD §8 D3）

1. §4.2 表格第一行"`specs/_index.yml` / `delivery/task/_index.yaml` / `specs/{spec_id}/traceability.yml`"的"全量重建"归类，改为拆成两行：
   - `delivery/task/_index.yaml`：全量重建（不变）
   - `specs/_index.yml` / `specs/{spec_id}/traceability.yml`：头部/结构化字段更新 + 追加（引用 SDD §8 D3 与 §0 事实基线，注明"曾在 PRD 阶段误判为可全量重建，架构设计阶段核实真实文件形态后修正"）
2. 该修正是本方案文档自身的事后勘误，不改变 CR-2026-020 已通过评审的 PRD/SDD 结论，只是让"素材文档"与"已定案设计"保持一致，避免未来读者被过时表述误导。

## 验收条件

1. `docs/product/writeback-流水线耗时分析与优化方案.md` §4.2 表格不再把 traceability.yml 与 delivery 索引归为同一类"全量重建"处理。
2. 修正处有一句话注明"据 CR-2026-020 SDD §8 D3 核实修正"，便于溯源。

## 完成标志

文档修正落盘，commit 到 knowledge-base 仓（本 worktree，`change-requests/CR-2026-020/` 之外的 `docs/` 路径改动）。
