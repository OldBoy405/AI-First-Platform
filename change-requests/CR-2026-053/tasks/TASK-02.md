---
id: CR-2026-053-TASK-02
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 修改 agents 文件 (评审意图改为委派合同)
slug: agent-review-intent-delegation
status: pending
estimate: 2h
depends-on: []
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

将 `requirement-writer.md` 和 `dev-agent.md` 的评审意图从"直接执行 review Skill"改为"委派路由合同"：
- 读 `crctl next` 判断下一步
- 新建 `quality-reviewer-agent` 独立任务（携带来源 Issue/父 task）
- 只传 CR-ID + workspace + Skill 输入
- 等结构化结果
- 只消费 blocker 回修

同时更新 `agents/_index.yml` 同步 capability 变化。

## 涉及文件 / 模块

- `../tools/agents/requirement-writer.md`
- `../tools/agents/dev-agent.md`
- `../tools/agents/_index.yml`

## 实现要点

参考 SDD §6 FR-A3:
- 重写评审意图章节，描述委派路由合同
- 不内嵌绑定 API/SQL/评审维度细节
- `_index.yml` 只同步实际 capability 变化

## 验收条件

1. `requirement-writer.md` 评审意图描述为委派路由
2. `dev-agent.md` 评审意图描述为委派路由
3. `_index.yml` capability 与 matrix 一致

## 完成标志

- 三文件修改已 commit
- `check-agents-contract.mjs` 通过

## 接口契约

无接口产出。
