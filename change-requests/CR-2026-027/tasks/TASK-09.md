---
id: CR-2026-027-TASK-09
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: Skill 同步（merge-feature-branch 特例删除 + cr-archive 契约）+ ARCHITECTURE §8 登记
slug: skill-sync-merge-archive
status: pending
estimate: 4h
depends-on:
  - "CR-2026-027-TASK-01"
  - "CR-2026-027-TASK-02"
  - "CR-2026-027-TASK-03"
  - "CR-2026-027-TASK-04"
  - "CR-2026-027-TASK-05"
  - "CR-2026-027-TASK-06"
  - "CR-2026-027-TASK-07"
  - "CR-2026-027-TASK-08"
created: "2026-08-09T23:35:00+08:00"
---

# TASK-09 — Skill 同步 + §8 登记（FR-5/FR-4 的 prompt 面）

## 任务描述

删除 `merge-feature-branch` 的 tools 隐藏特例（FR-5）、同步 `cr-archive` 的三账本 CAS 契约（FR-4/FR-11），并在 ARCHITECTURE.md §8 登记本 CR 维护记录。

## 涉及文件 / 模块

- tools `skills/writeback/merge-feature-branch/SKILL.md`（删除 tools 特例 prose 与实现分支）
- tools `skills/cr/cr-archive/SKILL.md`（对齐 FR-11 契约）
- tools `ARCHITECTURE.md`（§8 维护记录登记本 CR）

## 实现要点

1. `merge-feature-branch/SKILL.md`：删除「tools 不在声明但以 `custom/main` 特例参与」的 prose 与实现分支；合并/同步/清理只遍历 `dir-graph.yaml#repositories`（FR-5/AC-5）
2. `cr-archive/SKILL.md`：归档事件与三账本同批 CAS 的契约描述（不再描述独立 inbox-emit 发归档事件）；`--final-status` 必须等于 cr.md 当前终态；收件人复用 owners（FR-11/AC-15）；`_index.yml` 生命周期语义描述与实现一致（FR-4/AC-4）
3. `ARCHITECTURE.md` §8：登记本 CR（Phase 0 口径统一 + Phase 1 approve/TASK/archive/migrate/终态 resolver/review-record/next freshness 与 review cycle 改造；合 §4/§5 全部不变量）

## 验收条件

1. grep `merge-feature-branch/SKILL.md` 无 tools 硬编码特例（AC-5）
2. `cr-archive/SKILL.md` 无独立 inbox-emit 归档事件描述；`_index.yml` 语义与 §3.2 实现一致（AC-4）
3. `ARCHITECTURE.md` §8 含 CR-2026-027 登记条目

## 完成标志

三个文件提交至 tools worktree；`lint-prompts.mjs --mode enforce` 零发现（改 prompt 后必跑）；AC-4/AC-5 的 Skill 部分通过。

## 接口契约

- 消费：TASK-01 的 tools worktree；TASK-02 的 ARCHITECTURE 基线修订；TASK-03~08 的完整 Phase 1 最终行为（含 archive/review/next freshness），确保 §8 在全部代码落地后登记
- 产出：修订后的两个 SKILL.md + ARCHITECTURE §8 登记；TASK-10 的 grep/lint 复核基于本产出
