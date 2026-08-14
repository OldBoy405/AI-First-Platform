---
id: CR-2026-028-TASK-06
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: Adapter/requirement 入口与仓库 AGENTS.md 路径统一（M4b）
slug: unify-adapter-agents-paths
status: pending
estimate: 4h
depends-on: [CR-2026-028-TASK-04]
created: "2026-08-10T18:10:38+08:00"
---

# TASK-06 Adapter/requirement 入口与仓库 AGENTS.md 路径统一

## 1. 任务描述

按 FR-5 白名单将静态安装物化方（IDE hooks/CI）与 requirement 入口的路径表达统一为 `{TOOLS_ROOT}` 字面量；knowledge-base 根 `AGENTS.md` 改为不绑定安装位置的口径表达。

## 2. 涉及文件 / 模块

- tools 包 `skills/shared/crctl/adapters/**`（claude-code、qoder、cursor、codex、ci 全部模板与 hooks）
- tools 包 `skills/requirement/requirement-register/SKILL.md`（路径部分，元数据部分归 TASK-07）
- tools 包 `pipeline-templates/requirement-authoring.pipeline.json`（路径部分）
- knowledge-base 根 `AGENTS.md`（crctl 调用示例）

## 3. 实现要点

- SDD §8：Adapter 模板统一字面 `{TOOLS_ROOT}/skills/...`，安装说明注明来源 `workspace.tools_package_path`；七个禁止模式（`$CLAUDE_PROJECT_DIR/tools/`、`{TOOLS}/tools/`、`{WORKSPACE}/tools/` 等）零命中。
- hooks 启动即需路径（安装时物化一次，D-2/D-16）：模板保持占位符，不提交本机绝对路径（NFR-3）。
- knowledge-base 根 `AGENTS.md`：`node ../tools/skills/shared/crctl/scripts/crctl.mjs` 示例改为“经 Tools Root 解析的 crctl”口径表达（本仓库与 tools 包同名 AGENTS.md 区分处理，只改根 AGENTS.md）。
- requirement-register/requirement-authoring 中与路径无关的元数据部分（cr-init 一次传齐）由 TASK-07 处理，本 TASK 不触碰。

## 4. 验收条件

1. `skills/shared/crctl/adapters/**` 全量 grep：七禁止模式零命中；`{TOOLS_ROOT}` 统一。
2. knowledge-base 根 `AGENTS.md` 无 `../tools/...` 相对安装路径表达；`docs/` 下历史文档不在此列（只改 active 入口）。
3. requirement 两文件路径部分与 TASK-07 元数据改动无冲突（diff 不重叠）。

## 5. 完成标志

grep 零命中 + 根 AGENTS.md 口径更新 + commit 完成。

## 6. 接口契约

- **消费**：TASK-04 产出的 InstWS/worktree-path 语义。
- **产出**：无新 API；Adapter 模板字面量 `{TOOLS_ROOT}/skills/...` 作为安装物化契约；知识库 AGENTS.md 入口口径。
