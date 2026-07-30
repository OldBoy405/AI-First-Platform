---
id: CR-2026-001-TASK-05
type: TASK
cr-ref: CR-2026-001
plan-ref: "change-requests/CR-2026-001/plan.md"
sdd-ref: "change-requests/CR-2026-001/sdd.md"
title: tools-consistency-ci — agents.contract 四不变式接入 fork 仓库 CI
status: done
estimate: 6h
depends-on: []
assignee: ""
created: "2026-07-30T22:43:34+08:00"
---

# TASK-05 tools-consistency-ci — agents.contract 四不变式接入 fork 仓库 CI

## 任务描述

对应 FR-4 / SDD 组件 `tools-consistency-ci`。与 TASK-01~04 无依赖，可并行。在 tools 仓库现有 `check-skill-matrix.mjs`（已覆盖 owns 唯一性/active 校验）基础上，补齐 `dir-graph.yaml#agents.contract` 四条不变式的校验并接入 CI。

## 涉及文件 / 模块

- 现有：`tools/skills/shared/crctl/scripts/check-skill-matrix.mjs`、`tools/.github/workflows/check-skill-matrix.yml`、`tools/.githooks/pre-commit`
- 扩展点：四不变式中现有脚本未覆盖的部分——① Agent 先有 `.md` 再登记 `_index.yml`（双向存在性）；② Agent references 的 Skill 必须 active；③ Agent 正文/references 的 active Skill 同步到 matrix 的 owns/can-call、禁止项在 forbidden；④ 属行为约束，CI 不可静态校验，在校验脚本注释中说明由 crctl 门禁承担

## 实现要点

- 扩展现有脚本或同目录新增 `check-agents-contract.mjs`，沿用零依赖、行级状态机解析的既有风格（注意 CRLF 教训：用 `split('\n')` 逐行，不用 indexOf 切块）
- CI workflow 的 `paths` 触发条件补上 `agents/**`
- 验证方式照搬 PRD AC-4：故意制造不一致 → CI 红 → 修复 → 绿

## 验收条件

1. 故意让某 Agent 引用一个 inactive/未登记 Skill，CI（或本地 pre-commit）报错并指明具体 Agent 与 Skill
2. 恢复后校验通过，输出四不变式的覆盖情况（含第④条"由运行时承担"的显式说明）

## 完成标志

两条验收全过，脚本与 workflow 变更提交进 tools 仓库。

## 完成记录（2026-07-30）

- 交付物：`tools/skills/shared/crctl/scripts/check-agents-contract.mjs`（新增，零依赖，逐行状态机解析）；`.github/workflows/check-skill-matrix.yml` 补 `agents/**` 触发路径 + 新校验步骤；`.githooks/pre-commit` 串联两个校验器；README 同步。tools 仓库 commit `033a4a3`。
- 验收 1（红）：向 `agents/_index.yml` 注入 `fake/not-a-real-skill` 引用 → 校验失败 exit 1，报错精确到 agent 与 skill 名（3 处命中）。
- 验收 2（绿）：恢复后校验通过，输出含不变式 4"由 crctl 运行时承担"的显式说明；提交 `033a4a3` 时 pre-commit 钩子实际触发并通过。
