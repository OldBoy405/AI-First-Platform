---
spec-id: ai-first-platform
version: "0.20.1"
id: CR-2026-019-TASK-06
type: TASK
cr-ref: CR-2026-019
plan-ref: "change-requests/CR-2026-019/plan.md"
sdd-ref: "change-requests/CR-2026-019/sdd.md"
title: 同步三份 SKILL.md 改调子命令并禁手写 YAML
slug: sync-skill-docs
status: pending
estimate: 4h
depends-on: ["CR-2026-019-TASK-02", "CR-2026-019-TASK-03", "CR-2026-019-TASK-04"]
assignee: ""
created: "2026-08-04T17:36:00+08:00"
---

## 任务描述

把三份 develop/writeback 期 SKILL.md 中"手工编辑 YAML 账本"的步骤改为调用新子命令，并加明文禁令，闭环 FR-6（根除账本第二写入通道）。依赖三子命令 CLI 契约冻结（入参/错误码），故排在实现之后。

## 涉及文件 / 模块

- `skills/develop/implement-code/SKILL.md` — 任务完成标记改调 `crctl task done`
- `skills/writeback/merge-feature-branch/SKILL.md` — merge commit 记录改调 `crctl merge-metadata`
- `skills/writeback/cr-archive/SKILL.md` — 归档搬移改调 `crctl archive-move`
  （若实际文件名/路径不同，以 `grep` 定位手工编辑账本的 skill 为准）

## 实现要点（参考 SDD §1.2 / FR-6）

- 每处替换：把"手工编辑 `_index.yml`/`_backlog.yml`/`_history.yml`"的指令改为对应 crctl 子命令调用示例（含 `--workspace`）。
- 加一行明文禁令：账本文件禁止手工/会话内脚本编辑，只能经 crctl 子命令（CAS + 审计）。
- 不改这三个 skill 的其它无关措辞（不扩散）。

## 验收条件

1. 三份 SKILL.md 中原"手工编辑 YAML 账本"步骤全部替换为子命令调用。
2. `grep -rn "手工编辑\|手动改" skills/develop skills/writeback --include=SKILL.md` 仅命中"禁止"类措辞，无残留操作指导。

## 完成标志

三份文档更新，grep 校验通过，与冻结的 CLI 契约（TASK-02/03/04）一致。
