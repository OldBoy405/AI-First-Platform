---
id: CR-2026-053-TASK-01
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 修改 agent-skill-matrix.yml (owner 归属调整)
slug: matrix-owner-reassign
status: pending
estimate: 1h
depends-on: []
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

将四个 CR 评审 Skill 的唯一 `owns` 从作者型 Agent 收敛到 `quality-reviewer-agent`：
- 从 `requirement-writer.owns` 删除 `review-requirement`
- 从 `dev-agent.owns` 删除 `review-tech-design`、`review-dev-plan`、`review-code`
- 四个 Skill 加入 `quality-reviewer-agent.owns`
- 两作者 Agent 保留 `can-call` 能力

同时同步更新 `AGENT-SKILL-MATRIX.md` 说明文档。

## 涉及文件 / 模块

- `agent-skill-matrix.yml`（tools 仓根）
- `AGENT-SKILL-MATRIX.md`（tools 仓根）

## 实现要点

参考 SDD §6 FR-A1:
- 修改 YAML 中各 agent 的 `owns` 列表
- 验证修改后 `check-skill-matrix.mjs` 通过
- 确认每个 active Skill 唯一 owns

## 验收条件

1. `node skills/shared/crctl/scripts/check-skill-matrix.mjs` 零报错（tools 仓 worktree 根执行）
2. `node pipeline-templates/emit-registry.mjs --verify` 通过（registry 一致性）
3. 四个 review Skill 唯一 owner 为 `quality-reviewer-agent`，`requirement-writer`/`dev-agent` 保留 `can-call`

## 完成标志

- agent-skill-matrix.yml 修改已 commit
- AGENT-SKILL-MATRIX.md 同步更新已 commit
- `check-skill-matrix.mjs` 通过

## 接口契约

无接口产出。
