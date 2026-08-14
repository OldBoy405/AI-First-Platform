---
id: CR-2026-028-TASK-05
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: crctl/Sync/Writeback Skill 与 pipeline 路径统一（M4a）
slug: unify-skill-pipeline-paths
status: pending
estimate: 4h
depends-on: [CR-2026-028-TASK-04]
created: "2026-08-10T18:10:38+08:00"
---

# TASK-05 crctl/Sync/Writeback Skill 与 pipeline 路径统一

## 1. 任务描述

按 FR-5 白名单将动态调用方（Agent/Skill）提示词中的 crctl 路径表达从 `tools/skills/...` 改为 `{TOOLS_ROOT}/skills/...`（运行时由 Agent 解析），保证七禁止模式零命中。

## 2. 涉及文件 / 模块（tools 包）

- `skills/shared/crctl/SKILL.md`
- `skills/sync/push-progress/SKILL.md`、`skills/sync/pull-progress/SKILL.md`、`skills/sync/resume-from-remote/SKILL.md`
- `skills/writeback/writeback-prd-sdd/SKILL.md`、`skills/writeback/writeback-tasks/SKILL.md`、`skills/writeback/writeback-traceability/SKILL.md`
- `skills/writeback/scripts/test/writeback.test.mjs`（注释中运行命令）
- `pipeline-templates/feature-writeback.pipeline.json`

## 3. 实现要点

- SDD §8 清单逐项：`node tools/skills/...` → `{TOOLS_ROOT}/skills/...` 表达。
- sync 三 Skill 的 `crctl worktree-path` 消费不改（TASK-04 后行为自动一致）。
- writeback 三 Skill 的命令路径与 `feature-writeback.pipeline.json` 的 `tools/skills/writeback/scripts/*.mjs` 同步替换。
- 变更后运行验证：grep 全部 active 文件，`node tools/skills/`、`node ../tools/skills/`、`$WORKSPACE/tools/`、`<workspace>/tools/`、`$CLAUDE_PROJECT_DIR/tools/`、`{TOOLS}/tools/`、`{WORKSPACE}/tools/` 零命中（FR-5 判据）。

## 4. 验收条件

1. 白名单文件内七禁止模式 grep 零命中；`{TOOLS_ROOT}` 出现于所有动态调用命令。
2. 逐文件人工走查：语义等价（仅路径表达变更，无命令/参数变更）。
3. `writeback.test.mjs` 注释命令与正文一致。

## 5. 完成标志

grep 零命中 + 走查无命令语义变化 + commit 完成。

## 6. 接口契约

- **消费**：TASK-04 产出的 worktree-path 语义（sync 三 Skill 行为基准）。
- **产出**：无新 API；全部为提示词/模板字面量变更，契约面为 FR-5 白名单文件清单本身。
