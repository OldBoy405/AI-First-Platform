---
spec-id: ai-first-platform
version: "0.21"
id: CR-2026-020-TASK-07
type: TASK
cr-ref: CR-2026-020
plan-ref: "change-requests/CR-2026-020/plan.md"
sdd-ref: "change-requests/CR-2026-020/sdd.md"
title: merge-feature-branch 事实基线 + pipeline prompt 修订 + ARCHITECTURE.md §3/§6 修订
slug: merge-branch-facts-and-arch-doc
status: pending
estimate: 3h
depends-on: []
assignee: ""
created: "2026-08-04T22:21:12+08:00"
---

## 任务描述

不依赖脚本实现，可与 TASK-01~06 并行：补 `merge-feature-branch` SKILL 的参与仓事实基线（FR-9），修订 `feature-writeback.pipeline.json` 三个节点的 prompt 使其与新脚本调用方式和 FR-6/FR-7 一致，并按 `tools/ARCHITECTURE.md` §8 维护规则修订该文档（SDD §1.2 末段）。

## 涉及文件 / 模块

- `tools/skills/develop/merge-feature-branch/SKILL.md`（新增事实基线段，不改合并/补偿逻辑）
- `tools/pipeline-templates/feature-writeback.pipeline.json`（node-2/node-3/node-4 的 prompt 字段）
- `tools/ARCHITECTURE.md`（§3 代码地图、§6 否决表）

## 实现要点（引用 SDD FR-9、§1.2、§9）

1. **merge-feature-branch SKILL**：新增"已核实事实基线"段，固化：tools 仓（`phase0-tools`，`dir-graph.yaml` 自声明）参与合并且 trunk=`custom/main`（非 `main`，已核实：`git branch` 显示 `* custom/main`）；无提交的分支自动跳过合并与 merge-commits 记录；合并前需补齐开发期未 push 的 `origin/requirement/{cr_id}`。仅补事实，不改现有合并/补偿步骤描述。
2. **pipeline node-2**（`writeback-prd-sdd` 节点 prompt）：删除"备份到 writeback-backups/**"指引，改为"调用脚本 + 核对 dry-run diff"表述，与 TASK-06 改后的 SKILL.md 保持一致。
3. **pipeline node-3**（`writeback-tasks` 节点 prompt）：命名格式改为 `TASK-{target_version}-{cr_id}-{NN}-{slug}`（当前模板是作废的 `TASK-{target_version}-{NNN}-{NN}-*`，FR-8 三处一致化的第 1 处）。
4. **pipeline node-4**（`writeback-traceability` 节点 prompt）：删除"与 change-requests/{cr_id}/traceability.yml 保持一致（本条为权威版本）"表述，改为"specs 侧为唯一权威文件，change-requests 侧为开发期工作稿，归档后不要求同步"（FR-7）。
5. **ARCHITECTURE.md §3**：代码地图新增 `skills/writeback/scripts/` 条目，注明职责与"不触碰账本文件"的边界。
6. **ARCHITECTURE.md §6**：否决表"独立账本操作脚本库"条目补充范围澄清——否决对象是**账本写入**脚本库；specs/delivery 内容文件回写脚本落点收窄为 `skills/writeback/scripts/`（不是 `skills/shared/scripts/`），防止后续 CR 误以为该否决记录已被推翻而把账本脚本也堆进 `skills/writeback/scripts/`。

## 验收条件

1. `grep -n "trunk=custom/main\|custom/main" tools/skills/develop/merge-feature-branch/SKILL.md` 命中。
2. `grep -n "writeback-backups" tools/pipeline-templates/feature-writeback.pipeline.json` 无残留；`grep -n "TASK-{{inputs.target_version}}-{NNN}-{NN}" tools/pipeline-templates/feature-writeback.pipeline.json` 无残留（已改新格式）。
3. `grep -n "保持一致.*权威版本\|后者为权威" tools/pipeline-templates/feature-writeback.pipeline.json` 无残留。
4. `tools/ARCHITECTURE.md` §3 含 `skills/writeback/scripts/` 条目；§6 否决表该行含 CR-2026-020 范围澄清备注。

## 完成标志

4 类文件改毕，上述 4 条 grep/人工核对通过，commit 到 tools 仓（可与 TASK-01~06 的 commit 分开或合并，视实现时便利）。
