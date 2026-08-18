---
spec-id: ai-first-platform
version: "0.20.6"
id: CR-2026-045-TASK-14
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: "push-progress workspace contract 去除未解析占位符"
slug: push-progress-workspace-contract
status: pending
estimate: 2h
depends-on:
  - CR-2026-045-TASK-13
created: 2026-08-18T18:39:17+08:00
---

# TASK-14 push-progress workspace contract 去除未解析占位符

## 1. 任务描述

修复 architecture-design 的 push-progress prompt 和 Skill 示例，禁止 Agent 把 `<installation-workspace>` 当作真实路径或通过 `find /` 猜路径。复用 daemon 已注入的 `CRCTL_WORKSPACE`，由 `crctl checkpoint` 自身使用现有 repository/worktree resolver。

## 2. 涉及文件 / 模块

- `pipeline-templates/architecture-design.pipeline.json`
- `skills/sync/push-progress/SKILL.md`
- `server/internal/governance/gate_nodes_gen.go`（通过既有生成器刷新）
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`
- `server/internal/daemon/pipeline_task_test.go`（必要时补环境契约测试）

## 3. 实现要点

- Pipeline 只传递 `cr_id` 和 message，不内联未定义 workspace placeholder。
- pipeline/daemon 场景调用 `crctl checkpoint {cr_id} --message {message}`；standalone Skill 场景保留显式 workspace 的人读说明，但不要求 Agent 猜值。
- 重新生成 registry，确保 tools source 与 Multica compiled registry 一致。
- 增加静态检查，architecture executable prompt 不得包含 `<installation-workspace>` 等未解析路径 token。

## 4. 验收条件

1. architecture pipeline source、generated registry、push-progress Skill 均无未解析 workspace placeholder。
2. pipeline structure/registry tests 通过；既有 daemon environment tests 证明 `CRCTL_WORKSPACE`/`CRCTL_OPERATIONAL_WORKSPACE` 注入仍存在。
3. pipeline checkpoint 命令不触发全盘 `find`，真实 disposable smoke 或等价受控命令验证通过。

## 5. 完成标志

模板、生成物、Skill 和静态测试一致，daemon pipeline targeted tests 与 tools 全包通过。

## 6. 接口契约

- 消费：TASK-08 daemon pipeline environment、TASK-05 registry generator、现有 `push-progress`/`crctl checkpoint`。
- 产出：无路径猜测的 architecture push-progress prompt 和一致 generated registry。
