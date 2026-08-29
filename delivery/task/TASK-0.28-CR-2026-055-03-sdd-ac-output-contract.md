---
spec-id: ai-first-platform
version: "0.28"
id: CR-2026-055-TASK-03
type: TASK
cr-ref: CR-2026-055
plan-ref: "change-requests/CR-2026-055/plan.md"
sdd-ref: "change-requests/CR-2026-055/sdd.md"
title: "增加 SDD 的 AC 级输出约束"
slug: sdd-ac-output-contract
status: pending
estimate: 6h
depends-on: [CR-2026-055-TASK-01]
created: 2026-08-30T00:20:00+08:00
---

# 1. 任务描述

更新 `write-tech-design` Skill，使新生成或回修的 SDD 在第 6 节为每个 AC 提供可核对的设计落点、可观测结果和可达性说明，并按既有实现依赖规则附带事实证据。

# 2. 涉及文件 / 模块

- tools worktree 的 `skills/develop/write-tech-design/SKILL.md`
- SDD §3.5、§6、§6.1

# 3. 实现要点

- 每个 AC 必须包含三项固定信息：设计落点、可观测结果、可达性说明。
- 只有依赖既有实现的断言才附 `repo`、commit SHA、relative path、stable symbol、conclusion。
- 无既有实现依赖时明确写 `N/A（本 CR 无既有实现依赖）`；不得用 N/A 掩盖正文中的事实依赖。
- 回修只依据 blocker 和本轮变化定点修订，不无理由重写已确认方案。

# 4. 验收条件

对应 PRD AC-6。

1. Skill 输出合同明确每个 AC 的三项固定信息和既有事实证据要求。
2. 回修输入存在时，文档要求优先修复 blocker 指向位置并保留无关的已确认设计。
3. 文档不新增 SDD 文件、索引、payload 字段或运行时依赖。

# 5. 完成标志

`write-tech-design/SKILL.md` 的输出合同与 SDD §3.5、§6.1 一致，且能被 `lint-prompts` 检查。

# 6. 接口契约

- 消费：PRD AC、既有架构约束、review feedback 和 resources。
- 产出：AC 级 SDD 生成/回修约束，供 TASK-01、TASK-06 和后续 plan/TASK 编写使用。
