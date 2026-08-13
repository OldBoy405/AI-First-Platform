---
id: CR-2026-033-TASK-05
type: TASK
cr-ref: CR-2026-033
plan-ref: "change-requests/CR-2026-033/plan.md"
sdd-ref: "change-requests/CR-2026-033/sdd.md"
title: Skill/Pipeline 迁移与 checkpoint-add 删除（T05）
slug: checkpoint-migration-and-deletion
status: pending
estimate: 16h
depends-on:
  - CR-2026-033-TASK-04
created: 2026-08-13T19:06:07+08:00
---

## 任务描述

同一可回滚提交内完成 caller/reader 迁移并删除旧入口：4 个 Skill、4 个 Pipeline 文件（6 个节点）、README、skills/_index.yml、ARCHITECTURE.md；删除 `checkpoint-add` dispatch/help/tests/文案。T05 完成即切换，不双读。

## 涉及文件 / 模块

- 修改 `tools/skills/sync/push-progress/SKILL.md`（一次 `crctl checkpoint` 调用）
- 修改 `tools/skills/sync/list-remote-checkpoints/SKILL.md`（`latest-checkpoint` + exact-head drift）
- 修改 `tools/skills/sync/resume-from-remote/SKILL.md`（只消费 metadata-confirmed batch）
- 修改 `tools/skills/sync/pull-progress/SKILL.md`（摘要改 metadata Git 事实；ff-only 不变）
- 修改 `tools/pipeline-templates/requirement-authoring.pipeline.json` / `architecture-design.pipeline.json` / `code-implementation.pipeline.json` / `resume-cr.pipeline.json`（共 6 节点收缩）
- 修改 `tools/README.md`、`tools/skills/_index.yml`、`tools/ARCHITECTURE.md`
- 修改 `tools/skills/shared/crctl/scripts/crctl.mjs`（删除 checkpoint-add 与旧 editor/help/dispatch）
- 修改 `tools/skills/shared/crctl/scripts/test/crctl.test.mjs`（删除旧 checkpoint-add 契约测试，新增 CLI/outbox 契约）

## 实现要点（引用 SDD §8/§10.1.4/§10.2）

1. Pipeline 节点只保留输入、跳过、输出字段与 onFail；prompt 内不得出现 Git 命令或账本字段描述。
2. `ARCHITECTURE.md` 增加 checkpoint 写事务入口点/运行事实/测试入口（随本 CR 实施同步修订，SDD §1.4）。
3. 不修改 `controlled-shell/rules.json#protectedPaths.deny`。
4. 静态扫描证明 active Skill/Pipeline/README/help 无 `checkpoint-add` 残留与旧字段承诺。
5. T05 为单一提交；回滚即整提交 revert。

## 验收条件

1. `rg -n 'checkpoint-add' tools/skills tools/pipeline-templates tools/README.md` 零残留（历史文档/CUSTOM 除外）。
2. Pipeline 静态 contract：6 个节点 prompt 无 `git add/commit/push/checkpoint-add` 与 `checkpoints[]`/`last-push-*` 描述。
3. 全量回归：253+10 基线（含 T04 新增）全绿；Ubuntu/Windows CI 全绿。

## 完成标志

迁移与删除同一提交完成；静态扫描与回归全绿；commit 到 tools 仓 `requirement/CR-2026-033`。

## 接口契约

- 消费：TASK-04 的 `crctl checkpoint` CLI 与固定 JSON 输出。
- 产出：无新代码接口；Skill/Pipeline 调用面收敛为单一 checkpoint 深原语。
