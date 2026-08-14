---
spec-id: ai-first-platform
version: "0.23"
id: CR-2026-022-TASK-10
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 3 — merge-feature-branch HEAD 一致性校验 + write-competitive-report 写入目标/两阶段确认（FR-16/17）
slug: merge-head-check
status: pending
estimate: 5h
depends-on: []
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-16（2.1-J）：merge-feature-branch 补本地/远端 HEAD 一致性校验（防合并"缺最后一次提交"的远端分支）。FR-17（2.1-K）：write-competitive-report 写入目标订正 + 两阶段确认协议挪到 human_approval 之后。

## 涉及文件 / 模块

- `skills/writeback/merge-feature-branch/SKILL.md`：Step1.4 增补 HEAD 比对
- `pipeline-templates/competitive-radar.pipeline.json`：节点 2 prompt 写入目标改为 `docs/competitive/reports/_index.yml`；节点 2 显式传 `confirmed=false`；真正落盘挪到 human_approval 通过后
- `skills/competitive/write-competitive-report/SKILL.md`：核对读写清单与确认参数传递（与节点 2 对齐）

## 实现要点

1. FR-16：Step1.4 增加 `git rev-parse HEAD` vs `git rev-parse origin/requirement/{cr_id}` 比对，不一致 → 提示先跑 push-progress 补跑，不进入合并
2. FR-17：节点 2 prompt 目标路径 `docs/competitive/_index.yml` → `docs/competitive/reports/_index.yml`（竞品注册表 vs 报告索引是两个文件）；`confirmed` 参数默认 `false`（先出草稿），human_approval 通过后再 confirmed=true 落盘

## 验收条件

1. merge-feature-branch Step1.4 含 HEAD 比对步骤与拦截语义
2. competitive-radar 节点 2 写入目标为 `reports/_index.yml` 且含 `confirmed=false` 传参
3. human_approval 通过前无 `docs/competitive/reports/*.md` 落盘（模拟驳回验证）
4. write-competitive-report SKILL 读写清单与节点 2 目标一致

## 完成标志

验收 1~4 通过 + lint 复扫零违例。
