---
id: CR-2026-026-TASK-05
type: TASK
cr-ref: CR-2026-026
plan-ref: "change-requests/CR-2026-026/plan.md"
sdd-ref: "change-requests/CR-2026-026/sdd.md"
title: pipeline 插入 review-dev-plan 节点与 Skill 登记
slug: pipeline-node-and-registry
status: pending
estimate: 8h
depends-on: ["CR-2026-026-TASK-03", "CR-2026-026-TASK-04"]
created: "2026-08-09T12:55:00+08:00"
---

# TASK-05 — pipeline 插入 review-dev-plan 节点与 Skill 登记

## 任务描述

在 `code-implementation.pipeline.json` 中 write-dev-tasks 后、push-progress 前插入 review-dev-plan reviewLoop 节点（FR-1），并完成 `skills/_index.yml` 与 `agent-skill-matrix.yml` 登记（FR-16）。

输入条件：TASK-03（Skill 存在）与 TASK-04（回修契约）完成。

## 涉及文件

- `tools/pipeline-templates/code-implementation.pipeline.json`
- `tools/skills/_index.yml`
- `tools/agent-skill-matrix.yml`

## 实现要点（SDD §3.5 + FR-1/FR-16）

1. **节点插入**：node-2（write-dev-tasks）之后、node-3（push-progress）之前插入 `kind: skill, ref: review-dev-plan` 节点；UUID 按仓库规则分配（00000000-0000-0000-0015-000000000099 为示意值，须替换为不冲突的真实 UUID）；后续节点顺序后移。
2. **reviewLoop 配置**（SDD §3.5）：`repairRef: write-dev-plan`；`replayPolicy: rerun-listed-nodes-in-order`；replayNodes 三项（write-dev-plan repair-plan / write-dev-tasks regenerate-tasks / review-dev-plan rerun-current-review）；`maxAttempts: 3`；passCondition allOf（verdict=pass + blockers isEmpty）；`onBlock: route-to-repair-node`。
3. **节点 prompt**：强制输入清单（FR-2）、八类维度（FR-3）、payload 经 `.crctl/tmp/review-dev-plan.yml` 输入 `crctl review-record --stage dev-plan --bump-attempt` 落盘；路由处理（SDD §3.5 onBlock 二分契约）——normal 先 `advance --to tech-design-reviewed --trigger review-dev-plan:block`（embedded）再按 replayNodes 重放；upstream 执行 `advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker`（embedded）后输出 upstream-design-blocker 并 abort（onFail: abort）。
4. **登记**：`skills/_index.yml` 登记 `review-dev-plan`（develop 组，节点数/摘要同步更新）；`agent-skill-matrix.yml` 为 `dev-agent` 登记 owns、为 `quality-reviewer-agent` 登记 can-call（不新增 actor）。
5. pipeline JSON 的 `updatedAt` 与 `_index.yml` 节点数一致性（dir-graph L174 契约：改 pipeline JSON 必须同步 _index.yml nodes 数量）。

## 验收条件

1. `node -e "JSON.parse(require('fs').readFileSync('pipeline-templates/code-implementation.pipeline.json'))"` 解析通过（合法 JSON、UUID 不重复）。
2. `check-skill-matrix.mjs` 通过：review-dev-plan 恰一个 owns（dev-agent）；quality-reviewer-agent can-call 合法。
3. `check-agents-contract.mjs` 通过；`lint-prompts.mjs --mode enforce` 通过（节点 prompt 无 CONTRADICTS/STALE）。
4. pipeline-templates/_index.yml 的 nodes 数量与 pipeline JSON 实际节点数一致。
5. 节点 ref `review-dev-plan` 与 TASK-02 的 gates.json passCondition nodeRef 一致。

## 完成标志

三件套检查全绿；pipeline JSON 合法且节点顺序正确（write-dev-tasks → review-dev-plan → push-progress）；矩阵登记无漂移。

## 接口契约

- 消费：TASK-03 的 Skill（节点 ref）；TASK-04 的 fixed-blockers 输出（replayNodes 回修语义）；TASK-01 的 review-record --stage dev-plan。
- 产出：`review-dev-plan` 节点的 reviewLoop passCondition（TASK-02 的 gates.json passCondition 运行时读取对象）；pipeline 结构变化（TASK-06 的 README/ARCHITECTURE 文档依据）。
