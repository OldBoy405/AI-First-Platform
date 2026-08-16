---
id: CR-2026-042-TASK-02
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: Pipeline prompt 收敛与 code Pipeline reviewer 暂停删除
slug: converge-pipeline-prompts
status: pending
estimate: 4h
depends-on: []
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

按 SDD §2.2 收缩 8 个 active Pipeline 的越界 prompt，并删除 `code-implementation.pipeline.json` 的 reviewer 选择暂停。

code Pipeline 结构变更：删除 input `review_llm`、删除 human approval node `00000000-0000-0000-0015-000000000013`；节点 `...0017` 后直接进入 `...0009`；`review-code` prompt 改为由 runtime 决定 runner 并在 `dimensions.reviewer-model` 自报留痕；同步 `pipeline-templates/_index.yml` nodes 17→16。

# 2. 涉及文件 / 模块

- `pipeline-templates/code-implementation.pipeline.json`
- `pipeline-templates/*.pipeline.json`（其余 7 个，收缩越界 prompt）
- `pipeline-templates/_index.yml`

# 3. 实现要点

- 每个 Skill 节点 prompt 只保留：输入、调用的 Skill/公开命令、结构化结果分类、reviewLoop、失败动作；
- 删除 journal/write-set/CAS/candidate/manifest/lease/逐仓 Git/账本拼接算法副本；
- 删除直接写受控文件的指令；
- 保留节点的 `id`/`kind`/`ref`/`reviewLoop`/`onFail`/`timeoutMinutes`（除 `...0013` 删除）；
- `review-code` 的 `replayNodes` 保持现状（implement-code → write-test-report → checkpoint → workspace-freshness → review-code），不依赖 `...0013`；
- 需求/架构/开发启动/代码四个人工审批节点全部保留。

# 4. 验收条件

1. 全部 `pipeline-templates/*.pipeline.json` 经 `JSON.parse` 成功；
2. `code-implementation` 的 `inputs` 恰为 `[cr_id, target_version, auto_push_after_task]`，无 `review_llm`；
3. node `00000000-0000-0000-0015-000000000013` 不存在，节点总数为 16；
4. 节点 `...0017` 的直接后继是 `...0009`；
5. `review-code` 的 `reviewLoop.replayNodes` 五个 nodeId 均指向现存节点且顺序不变；
6. `pipeline-templates/_index.yml` 中 code-implementation `nodes: 16`；
7. 全部 prompt 中 `journal|write-set|candidate|manifest|lease|逐仓` 的可执行算法复述零命中（保留公开命令调用与结果分类）。

# 5. 完成标志

code Pipeline 16 节点、无 `review_llm`、无 `...0013`；全部 Pipeline JSON 可解析且越界 prompt 收缩完成。

# 6. 接口契约

- 消费：无上游 TASK 产出；只读 SDD §2.2 与当前 Pipeline JSON。
- 产出：code Pipeline `inputs: [cr_id, target_version, auto_push_after_task]`、`nodes: 16`、无 `...0013`；下游 TASK-04 消费「reviewer 由 runtime 选择」的最终描述，TASK-06 消费「16 节点结构」做固定断言。
