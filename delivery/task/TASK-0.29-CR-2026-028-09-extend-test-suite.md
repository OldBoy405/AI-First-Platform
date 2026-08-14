---
spec-id: ai-first-platform
version: "0.29"
id: CR-2026-028-TASK-09
type: TASK
cr-ref: CR-2026-028
plan-ref: "change-requests/CR-2026-028/plan.md"
sdd-ref: "change-requests/CR-2026-028/sdd.md"
title: 测试扩展与全量回归（M7）
slug: extend-test-suite
status: pending
estimate: 8h
depends-on:
  - CR-2026-028-TASK-01
  - CR-2026-028-TASK-02
  - CR-2026-028-TASK-03
  - CR-2026-028-TASK-04
  - CR-2026-028-TASK-05
  - CR-2026-028-TASK-06
  - CR-2026-028-TASK-07
  - CR-2026-028-TASK-08
created: "2026-08-10T18:10:38+08:00"
---

# TASK-09 测试扩展与全量回归

## 1. 任务描述

按 FR-9/SDD §4.4 扩展 `crctl.test.mjs`：隔离 fixture、路径表驱动、linked-worktree 黑盒、四类 sentinel、CRCTL_RULES_PATH 覆盖、cr-init metadata 复用用例；全量回归既有用例。

## 2. 涉及文件 / 模块

- tools 包 `skills/shared/crctl/scripts/test/crctl.test.mjs`（主要）
- 如需：tools 包测试 fixture 目录（新增，最小四标志 tools 包）

## 3. 实现要点

- SDD §4.4 全部 8 条：
  1. `makeToolsFixture()`：最小四标志 + dir-graph.yaml（sentinel 转换）+ `pipeline-templates/sentinel.pipeline.json` + `gates.json`（sentinel evidence）+ `controlled-shell/rules.json`（sentinel git shape）；不修改真实 checkout。
  2. `makeWorkspace` 扩展：默认写 dir-graph.yaml 声明 `tools_package_path`（相对值指向 fixture）。
  3. 表驱动：相对/绝对、空壳 `tools/`、缺配置、非字符串、路径不存在、四标志逐一缺失。
  4. linked-worktree 黑盒：临时 git 仓建 worktree，断言 worktree-path 与 Tools Root 均以 InstWS 为根、无嵌套 `.rayai-worktrees`。
  5. 四 sentinel 行为断言（AC-6）：状态机 sentinel 转换 advance 成功、pipeline sentinel nodeRef、gates sentinel evidence、rules sentinel git shape；执行脚本换 checkout 不变。
  6. `CRCTL_RULES_PATH` 覆盖（AC-7）。
  7. cr-init metadata 一次写齐（AC-11/AC-12）。
  8. 代码审查断言（AC-8）：四 loader 同一 resolver、toolsRootCache 仅成功 string、_shellRules 独立、无 Map/文件/telemetry/module-scope 全局。
- 全部 fixture 走临时目录；YAML 解析 CRLF→LF 归一（纪律 #1）。

## 4. 验收条件

1. `node crctl.test.mjs` 全量通过（新增 + 既有用例零回归）。
2. 表驱动失败场景断言 `TOOLS_PACKAGE_NOT_FOUND` 且 exit 1。
3. sentinel 场景在切换执行脚本 checkout 后结果不变。

## 5. 完成标志

全量绿 + 无真实仓库环境污染 + commit 完成。

## 6. 接口契约

- **消费**：TASK-01~08 全部产出签名（deriveInstallRoot/resolveToolsRoot/四 loader/cmdWorktreePath/cr-init 调用形态）。
- **产出**：无新 API；`crctl.test.mjs` 成为 FR-9 验收的执行载体。
