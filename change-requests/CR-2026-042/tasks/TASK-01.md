---
id: CR-2026-042-TASK-01
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: 收敛 Agent 与 Pipeline 调用合同
slug: converge-agent-pipeline-contracts
status: pending
estimate: 8h
depends-on: []
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

收敛 9 个 active Agent 和 8 个 active Pipeline 的调用方合同。Agent 只保留职责判断、路由、人工边界与权限事实源；Pipeline 只保留节点顺序、输入传递、reviewLoop 和失败中止。删除 code Pipeline 的 `review_llm` input 与 reviewer 选择节点 `00000000-0000-0000-0015-000000000013`。

# 2. 涉及文件 / 模块

- `agents/*.md`（9 个 active Agent，重点为 requirement-writer/dev-agent/quality-reviewer-agent/delivery-agent）
- `agents/_index.yml`（仅在 brief/reference 冲突时定点同步）
- `pipeline-templates/*.pipeline.json`（8 个 active Pipeline）
- `pipeline-templates/_index.yml`

# 3. 实现要点

- Agent 删除状态链、`_backlog.yml` status 推断、Git/账本/CAS/journal 算法、完整权限矩阵副本；保留角色、路由、人工决策边界、矩阵链接和禁止绕过 Skill/`crctl` 的约束；
- Pipeline prompt 删除 journal/write-set/candidate/manifest/lease/逐仓 Git/账本拼接算法，只保留公开 Skill/命令 interface 与结构化结果分类；
- code Pipeline 删除 `review_llm` 与 `...0013`，`...0017` 后直接进入 `...0009`；runtime 选择 reviewer，`review-code` 通过 `dimensions.reviewer-model` 留痕；
- 保持 review-code 的 replayNodes 顺序及需求/架构/开发启动/代码四个人工审批节点。

# 4. 验收条件

1. Agent 同一段不含 3 个及以上权威具名状态，且 `_backlog.yml` + status/状态判断组合零命中；
2. Agent 无 worktree/commit/push/merge/CAS/journal/账本写入算法，`check-agents-contract.mjs` 通过；
3. 全部 Pipeline JSON 可解析，Skill node `ref` 指向 active Skill，reviewLoop 引用无悬空；
4. code Pipeline `inputs` 恰为 `[cr_id, target_version, auto_push_after_task]`，节点总数 16，无 `review_llm` 与 `...0013`；
5. `...0017` 的直接后继为 `...0009`，review-code 五个 replayNodes 均存在且顺序不变；
6. `pipeline-templates/_index.yml` 中 code-implementation `nodes: 16`。

# 5. 完成标志

上述 6 条通过；改动作为一个 tools 仓 TASK commit；随后通过 `crctl task done CR-2026-042 CR-2026-042-TASK-01` 即时登记完成。

# 6. 接口契约

- 消费：现有 `agent-skill-matrix.yml`、`dir-graph.yaml` 状态机、Pipeline JSON 与 SDD §2.1/§2.2。
- 产出：code Pipeline 合同 `{ inputs: [cr_id,target_version,auto_push_after_task], nodeCount: 16, reviewerSelection: runtime }`；TASK-02 消费 reviewer/runtime 文本合同，TASK-03 消费 16 节点结构做固定断言。
