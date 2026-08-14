---
id: CR-2026-022-TASK-17
type: TASK
cr-ref: CR-2026-022
plan-ref: "change-requests/CR-2026-022/plan.md"
sdd-ref: "change-requests/CR-2026-022/sdd.md"
title: 批 4 — sync 免责收敛 + bucket 改调 worktree-path + agents constraints 删除 + push-progress 样板抽取（FR-29~31）
slug: sync-converge
status: pending
estimate: 8h
depends-on: [CR-2026-022-TASK-05, CR-2026-022-TASK-15]
assignee: ""
created: "2026-08-06T08:30:00+08:00"
---

## 任务描述

FR-29~31（2.3 冗余批）：sync 四兄弟免责样板收敛、bucket/worktreePath 计算改调 crctl 只读命令、agents 台账 constraints 删除、pipeline push-progress 样板抽取。**前置：TASK-05（FR-11）已把 push-progress 本身修对；TASK-15（批 3.5）护栏已落地。**

## 涉及文件 / 模块

- FR-29：`skills/sync/pull-progress`、`push-progress`、`resume-from-remote`、`handover-cr` 四份 SKILL.md + `skills/shared/controlled-shell/SKILL.md`（收敛目标）
- FR-30：`agents/_index.yml` 各 agent constraints 块
- FR-31：`pipeline-templates/{requirement-authoring, architecture-design, code-implementation}.pipeline.json` 三处 push-progress 节点 prompt

## 实现要点

1. FR-29①：「受控 shell + 禁手工指引 + SHELL_UNAVAILABLE」样板收敛到 `controlled-shell/SKILL.md` 单点引用；**各 skill 必须保留一行「SHELL_UNAVAILABLE 禁止降级为手工指引」摘要**（执行时硬约束，不能依赖跳转）；②bucket/worktreePath 计算三处改调 `crctl worktree-path <cr> --repo <r>`（只读命令已存在，不重复实现）
2. FR-30：删 agents/_index.yml 各 agent `constraints:` prose（与 md「禁止行为」段重复）；机读台账只留 id/path/status/consumers/capabilities
3. FR-31：三处 push-progress 节点 prompt 的「若=false 输出 SKIPPED…经 crctl checkpoint-add 更新 _backlog」样板抽成 push-progress skill 默认说明、节点只传差异参数（引用目标 = 已存在且被复用的同一 skill，风险低）

## 验收条件

1. sync 四文件无整段免责样板重复，均保留 SHELL_UNAVAILABLE 一行摘要
2. sync 文件不再手拼 bucket/worktreePath（grep 无 `bucket =`/`worktreePath =` 拼接逻辑）
3. agents/_index.yml 无 constraints prose 字段
4. 三流水线 push-progress 节点引用 push-progress 默认说明，行为等价（模拟执行一致）
5. lint 引用一致性检查 + 全量复扫零违例

## 完成标志

验收 1~5 通过 + check-skill-matrix.mjs 绿。
