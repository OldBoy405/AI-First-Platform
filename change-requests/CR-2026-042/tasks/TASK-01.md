---
id: CR-2026-042-TASK-01
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: Agent 文档收敛
slug: converge-agent-docs
status: pending
estimate: 4h
depends-on: []
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

按 SDD §2.1 收敛 9 个 active Agent 文档：只保留角色定位、意图路由、人工决策边界、权限事实源链接和禁止绕过 Skill/`crctl` 的约束；删除状态链、backlog 状态推断、Git/账本写入算法和完整权限矩阵副本。

重点文件：`agents/requirement-writer.md`、`agents/dev-agent.md`、`agents/quality-reviewer-agent.md`、`agents/delivery-agent.md`；其余 active Agent 仅在存在落盘步骤、重复能力清单或过长交互脚本时做定点删除。

# 2. 涉及文件 / 模块

- `agents/requirement-writer.md`
- `agents/dev-agent.md`
- `agents/quality-reviewer-agent.md`
- `agents/delivery-agent.md`
- `agents/spec-agent.md`、`agents/product-planning-agent.md`、`agents/competitive-analyst-agent.md`、`agents/knowledge-agent.md`、`agents/customer-support-agent.md`（按需）

# 3. 实现要点

- 删除同段出现 3 个及以上 CR 具体状态的状态链/状态表；
- 删除「从 `_backlog.yml` 读 status 决定下一步」的说明；
- 删除 worktree/commit/push/merge/CAS/journal/账本字段写入算法；
- 删除完整 owns/can-call/forbidden 清单，改为指向 `agent-skill-matrix.yml`；
- 保留：角色定位、Pipeline/Skill 路由、人工决策边界、矩阵链接、禁止绕过约束；
- 若 `agents/_index.yml` 的 brief/reference 与实际删改冲突，做定点同步，不扩大改写。

# 4. 验收条件

1. `grep -nE 'drafting|requirement-reviewing|requirement-approved|tech-designing|tech-design-review-pending|tech-design-reviewed|task-breakdown|developing|code-reviewing|code-approved|merging|writing-back|archived' agents/*.md` 在任一文件的同一段落不再出现 ≥3 个不同状态；
2. `grep -nE '_backlog\.yml.*status|status.*_backlog\.yml|从.*_backlog.*判断|读.*_backlog.*状态' agents/*.md` 零命中；
3. `grep -nE 'git (add|commit|push|merge|worktree)|CAS|journal|write-set' agents/*.md` 零命中；
4. `node skills/shared/crctl/scripts/check-agents-contract.mjs` 通过（不变式 1-3）；
5. 每个 Agent 仍包含角色定位、路由、人工边界、矩阵链接、禁止绕过约束五项。

# 5. 完成标志

全部 9 个 Agent 文档通过上述 5 条验收；check-agents-contract.mjs 退出 0。

# 6. 接口契约

- 消费：无上游 TASK 产出（首任务，只读现有 Agent/矩阵事实）。
- 产出：收敛后的 `agents/*.md`（无机器接口）；下游 TASK-04 消费「各 Agent 最终职责与 reviewer 选择边界」文本。
