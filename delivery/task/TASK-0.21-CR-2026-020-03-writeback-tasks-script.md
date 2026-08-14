---
spec-id: ai-first-platform
version: "0.21"
id: CR-2026-020-TASK-03
type: TASK
cr-ref: CR-2026-020
plan-ref: "change-requests/CR-2026-020/plan.md"
sdd-ref: "change-requests/CR-2026-020/sdd.md"
title: writeback-tasks.mjs 入库脚本
slug: writeback-tasks-script
status: pending
estimate: 5h
depends-on: [CR-2026-020-TASK-01]
assignee: ""
created: "2026-08-04T22:21:12+08:00"
---

## 任务描述

实现 TASK 回写脚本：拷贝 done 任务到 `delivery/task/` + frontmatter 注入 + 全量重建 `delivery/task/_index.yaml`（SDD §4.2、FR-2）。**幂等判据以 SDD 评审 attempt 1 修复后的版本为准**：扫描 `delivery/task/*.md` frontmatter 的 id 集合，不看目标文件名是否存在。

## 涉及文件 / 模块

- 新建 `tools/skills/writeback/scripts/writeback-tasks.mjs`
- 依赖 TASK-01 的 `lib.mjs`
- 读写对象：`delivery/task/*.md`（写，新增）、`delivery/task/_index.yaml`（写，全量重建）；`change-requests/{cr}/tasks/_index.yml`（只读，账本文件，禁止写）

## 实现要点（引用 SDD §4.2、§2.2、§8 修复记录）

1. CLI 契约：`--workspace --cr --spec --version [--dry-run]`。
2. 幂等判据（**SDD-BLOCK-001 修复后**）：先扫描现有 `delivery/task/*.md` 收集已交付 id 集合；读 CR `tasks/_index.yml`（只读）筛 `status=done`；其 `id` 已在已交付集合中 → 跳过，不看文件名。
3. 命名：`TASK-{version}-{cr_id}-{NN}-{slug}`（`slug` 取源任务 frontmatter，缺失回退 `task-{NN}`）。
4. 拷贝时在 frontmatter 闭合 `---` 前插入 `spec-id`/`version` 两行。
5. `delivery/task/_index.yaml` **全量重建**：扫描全部 `delivery/task/*.md` frontmatter 投影七字段（id/file/title/status/cr-ref/target-version/estimate）；顺序 = 既有 id 原序 + 新增按 id 排序追加（SDD §2.2，控制 diff 面）。
6. 自检：回读断言新增 id 均恰 1 条、字段齐全、全文件无 `\r`。

## 验收条件

1. 构造 2 个 done 任务（1 个已有 slug、1 个无 slug）：回写后文件名分别符合 `TASK-{version}-{cr}-{NN}-{slug}` 与 `TASK-{version}-{cr}-{NN}-task-{NN}`。
2. 幂等专项验证 SDD-BLOCK-001 场景：任务首次回写后，源任务 frontmatter 补充/修改 `slug` 字段再重跑——不得产生第二份交付文件（判据是 id 集合而非文件名）。
3. `delivery/task/_index.yaml` 全量重建后，既有条目（用真实 `delivery/task/_index.yaml` 的前 N 条模拟）顺序不变，新增条目按 id 排在后面。
4. 同一 CR 重复执行：noop，文件无变化。

## 完成标志

脚本落盘，上述 4 条验收手工跑通（临时目录测试），commit 到 tools 仓。
