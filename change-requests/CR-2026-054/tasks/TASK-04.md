---
id: CR-2026-054-TASK-04
type: TASK
cr-ref: CR-2026-054
plan-ref: "change-requests/CR-2026-054/plan.md"
sdd-ref: "change-requests/CR-2026-054/sdd.md"
title: "收敛 Agent 执行边界文档"
slug: agent-execution-boundaries
status: pending
estimate: 6h
depends-on: []
created: 2026-08-29T18:15:00+08:00
---

# 1. 任务描述

同步平台文档中的 Agent、Skill 和 README 职责，使环境前提不足时使用 `ENVIRONMENT_MISMATCH` 并由既有 Pipeline 中止；不复制 Pipeline、crctl、状态机或账本算法。

# 2. 涉及文件 / 模块

- `tools` worktree 的 `agents/dev-agent.md`
- `tools` worktree 的 `skills/develop/implement-code/SKILL.md`
- `tools` worktree 的 `skills/develop/review-code/SKILL.md`
- `tools` worktree 的 `README.md`

# 3. 实现要点

- Agent 只保留路由、职责判断和 Skill 委派；技术中止后报告所需平台/人工动作并结束，不等待或轮询下游任务。
- implement-code 只做一次环境检查，任务范围内可修正时最多重跑一次；遵守测试计划 timeout，使用既有测试入口，不创建脱离验证步骤继续存活的后台进程；超出权限时返回 `ENVIRONMENT_MISMATCH`。
- review-code 不采信无法可信关联当前变更的共享实例输出；环境不匹配不生成代码 blocker。
- README 只写人读原则和链接，具体判定仍以 Skill、Pipeline 和 crctl 为准。

# 4. 验收条件

对应 PRD 验收标准：AC-3、AC-4。

1. 文档 diff 只修改 SDD 约定的职责边界，未新增 Pipeline 节点、状态、gate、权限矩阵字段或账本操作。
2. 负向场景能明确区分 `ENVIRONMENT_MISMATCH`、可归因代码失败和共享实例不可采信三种语义。
3. implement-code 文档明确要求遵守既有测试计划 timeout、使用既有测试入口和清理后台进程；dev-agent 文档明确要求技术中止后报告平台/人工动作并结束。
4. 文档内引用的既有命令、Skill 和 Pipeline 名称均能在 tools worktree 中定位。

# 5. 完成标志

四个文档完成审查，职责和失败语义无重复事实源，diff 检查通过。

# 6. 接口契约

- 消费：TASK-04 使用 SDD §3.3 和现有 `code-implementation` Pipeline 的失败语义。
- 产出：Agent/Skill/README 文档契约，供后续 review-code 和 test-report 审查；不产生运行时代码接口。
