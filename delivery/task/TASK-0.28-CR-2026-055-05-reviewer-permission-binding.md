---
spec-id: ai-first-platform
version: "0.28"
id: CR-2026-055-TASK-05
type: TASK
cr-ref: CR-2026-055
plan-ref: "change-requests/CR-2026-055/plan.md"
sdd-ref: "change-requests/CR-2026-055/sdd.md"
title: "绑定 reviewer 最小权限"
slug: reviewer-permission-binding
status: pending
estimate: 5h
depends-on: [CR-2026-055-TASK-04]
created: 2026-08-30T00:20:00+08:00
---

# 1. 任务描述

更新 tools 的 `agent-skill-matrix.yml`，使 `quality-reviewer-agent` 能调用既有 `controlled-shell`，同时保持其没有审批、状态推进和账本写入权限。

# 2. 涉及文件 / 模块

- tools worktree 的 `agent-skill-matrix.yml`
- SDD §1.2、§3.3、§7.1

# 3. 实现要点

- 仅在 `quality-reviewer-agent.can-call` 增加 `controlled-shell`。
- 不修改 `owns`、`forbidden`、其他 actor、Skill 索引或 rules.json。
- 与 TASK-04 的文档授权语义保持一致。

# 4. 验收条件

对应 PRD AC-8、AC-11。

1. `check-skill-matrix.mjs` 通过，active Skill 的 owns 归属无漂移。
2. reviewer 权限含 `controlled-shell`，但不含 approve、crctl、push-progress 或其他写入 Skill。
3. git diff 仅包含批准的权限矩阵文件。

# 5. 完成标志

权限矩阵检查通过，且 reviewer 的权限边界与 controlled-shell 文档一致。

# 6. 接口契约

- 消费：TASK-04 的只读取证合同和现有 agent-skill-matrix 结构。
- 产出：`quality-reviewer-agent -> controlled-shell` 的 can-call 关系，供 TASK-07 权限回归检查消费。
