---
spec-id: ai-first-platform
version: "0.27"
id: CR-2026-053-TASK-02
type: TASK
cr-ref: CR-2026-053
plan-ref: "change-requests/CR-2026-053/plan.md"
sdd-ref: "change-requests/CR-2026-053/sdd.md"
title: 修改 agents 文件 (评审意图改为委派合同, 含 quality-reviewer-agent.md)
slug: agent-review-intent-delegation
status: pending
estimate: 2h
depends-on: []
created: 2026-08-28T11:20:00+08:00
---

## 任务描述

将三个 agent 文件收敛为「作者委派路由 + 评审唯一 owner」合同（SDD §9 文件清单）：

- `requirement-writer.md`、`dev-agent.md`：评审意图从"直接执行 review Skill"改为"委派路由合同"——读 `crctl next` → 新建 `quality-reviewer-agent` 独立任务（携带来源 Issue/父 task 上下文）→ 只传 CR-ID + workspace + Skill 输入 → 等结构化结果 → 只消费 blocker 回修；
- `quality-reviewer-agent.md`：同步其为四类 review Skill **唯一 owner** 的表述（与 matrix 一致），并补充 FR-A6 独立会话路径（不支持 subagent 时以独立会话身份运行同一 review Skill）；不内嵌绑定 API/SQL/评审维度细节；
- `agents/_index.yml`：只同步实际 capability/reference 变化。

## 涉及文件 / 模块

- `agents/requirement-writer.md`（tools 仓根）
- `agents/dev-agent.md`
- `agents/quality-reviewer-agent.md`
- `agents/_index.yml`

## 实现要点

参考 SDD §6 FR-A3：
- 重写评审意图章节为委派路由合同，不内嵌绑定 API/SQL/评审维度
- quality-reviewer-agent.md 保持既有四类评审路由表，只补 owner 归属与 FR-A6 独立会话说明
- `_index.yml` 只同步 capability 变化

## 验收条件

1. `node skills/shared/crctl/scripts/check-agents-contract.mjs` 零报错（tools 仓 worktree 根执行）
2. `grep -n "quality-reviewer-agent" agents/requirement-writer.md agents/dev-agent.md` 命中委派路由合同
3. `grep -n "review-requirement\|review-tech-design\|review-dev-plan\|review-code" agents/quality-reviewer-agent.md` 命中四类评审路由 + 唯一 owner 表述

## 完成标志

- 四文件修改已 commit
- `check-agents-contract.mjs` 通过

## 接口契约

无接口产出。
