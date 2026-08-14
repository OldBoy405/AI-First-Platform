---
spec-id: ai-first-platform
version: "0.21"
id: CR-2026-020-TASK-06
type: TASK
cr-ref: CR-2026-020
plan-ref: "change-requests/CR-2026-020/plan.md"
sdd-ref: "change-requests/CR-2026-020/sdd.md"
title: 三份 writeback SKILL.md 改调 + 事实基线段
slug: writeback-skills-rewrite
status: pending
estimate: 4h
depends-on: [CR-2026-020-TASK-02, CR-2026-020-TASK-03, CR-2026-020-TASK-04]
assignee: ""
created: "2026-08-04T22:21:12+08:00"
---

## 任务描述

把 `writeback-prd-sdd`、`writeback-tasks`、`writeback-traceability` 三份 SKILL.md 从"描述性步骤 + 现写脚本"改为"调用脚本 + 核对 dry-run diff"，并新增"已核实事实基线"段（FR-8）。依赖脚本已落地，因为 SKILL 里要写准确的 CLI 调用方式。

## 涉及文件 / 模块

- `tools/skills/writeback/writeback-prd-sdd/SKILL.md`
- `tools/skills/writeback/writeback-tasks/SKILL.md`
- `tools/skills/writeback/writeback-traceability/SKILL.md`

## 实现要点（引用 SDD FR-6/FR-7/FR-8）

1. **writeback-prd-sdd/SKILL.md**：删除 Step 2（`writeback-backups/` 备份步骤）；Step 3/4 的手工操作描述替换为"调用 `node tools/skills/writeback/scripts/writeback-prd-sdd.mjs --workspace . --cr {cr_id} --spec {spec_id} --version {target_version} [--brief ...] --dry-run` 核对 diff → 无误后去掉 `--dry-run` 实跑"；Step 6 输出摘要删除"备份位置"行。
2. **writeback-tasks/SKILL.md**：Step 2~5 替换为调用 `writeback-tasks.mjs`；保留"格式约定"提示框（真实命名格式）但改为引用脚本内置逻辑而非人工判断。
3. **writeback-traceability/SKILL.md**：Step 3 示例改为脚本生成，删除"与 change-requests 侧保持一致"的一致性校验语义（FR-7）；Step 3 示例里作废的 `TASK-{ver}-{CR-NNN}-01` 命名改为真实格式 `TASK-{version}-{cr_id}-{NN}-{slug}`（FR-8 三处一致化的第 2 处）；新增"`--milestone-file` 由本 Agent 按证据源起草"的说明（fr-chain 等编辑性内容仍需人工/Agent 撰写，脚本只负责结构校验与放置）。
4. 三份 SKILL.md 各自新增"已核实事实基线"段（参照 SDD §0 与 tools/ARCHITECTURE.md 先例格式），固化：里程碑命名惯例、`specs/_index.yml`/`delivery/task/_index.yaml` 字段格式、统一 TASK 命名格式。

## 验收条件

1. `grep -rn "writeback-backups\|metadata.yml" tools/skills/writeback/writeback-prd-sdd/SKILL.md` 无残留。
2. `grep -rn "与.*change-requests.*保持一致\|后者.*权威" tools/skills/writeback/writeback-traceability/SKILL.md` 无残留。
3. `grep -rn "TASK-{ver}-{CR-NNN}" tools/skills/writeback/` 全仓无残留（三处统一，AC-6）。
4. 三份 SKILL.md 均含"已核实事实基线"或等价标题的独立章节。

## 完成标志

三份 SKILL.md 改毕，上述 4 条 grep 验收通过，commit 到 tools 仓。
