---
id: CR-2026-026-TASK-02
type: TASK
cr-ref: CR-2026-026
plan-ref: "change-requests/CR-2026-026/plan.md"
sdd-ref: "change-requests/CR-2026-026/sdd.md"
title: gates.json 门禁升级与状态机两条转换
slug: gates-and-state-machine
status: pending
estimate: 8h
depends-on: ["CR-2026-026-TASK-01"]
created: "2026-08-09T12:55:00+08:00"
---

# TASK-02 — gates.json 门禁升级与状态机两条转换

## 任务描述

升级 `gates.json` 的 dev-start 审批门禁与 developing 目标态门禁，并在 `dir-graph.yaml` 追加两条状态转换（M1 收口）。

输入条件：TASK-01 已交付 dev-plan stage 映射与路由（annotation 顶层 repair-target 可被门禁消费）。

## 涉及文件

- `tools/skills/shared/crctl/gates.json`
- `tools/dir-graph.yaml`

## 实现要点（SDD §3.3/§3.4）

1. `approvalStages.dev-start` 升级（SDD §3.3）：
   - `evidence`: `$default` = `change-requests/{cr}/review-annotations/dev-plan.yml`，另加 `plan`、`task-index` 两键（evidence digest 三键覆盖，FR-11）；
   - `passCondition`: `{ "pipeline": "code-implementation", "nodeRef": "review-dev-plan" }`（运行时读 pipeline JSON 的 reviewLoop.passCondition）；
   - 保留既有 `requireFiles`（plan.md + tasks/_index.yml）。
2. `statusGates.developing` 补全五条件（SDD §3.3）：fileExists plan.md、fileExists tasks/_index.yml、globNonEmpty TASK-*.md（pattern `^TASK-\d+.*\.md$`）、passCondition stage=dev-plan、approval section=development-start。全部使用既有门禁类型，不新增解释器。
3. `reviewLoops` 追加 `"review-dev-plan": { "pipeline": "code-implementation" }`。
4. `dir-graph.yaml` state_machine 追加两条声明（SDD §3.4）：
   - `{ from: task-breakdown, to: tech-design-reviewed, trigger: "review-dev-plan:block -> write-dev-plan" }`
   - `{ from: task-breakdown, to: tech-design-review-pending, trigger: "review-dev-plan:upstream-design-blocker" }`
   - 不新增具名状态；转移口径 25→27 声明 / 47→49 展开（以实现期测试断言为准）。

## 验收条件

1. 评审未通过 / 证据缺失 / blockers 非空时 `crctl approve --stage dev-start` → GATE_BLOCKED 且不写合法审批段（测试向量 ⑥）。
2. task-breakdown 且评审通过后删空 `TASK-*.md`（或篡改 `approval.yml#development-start`）再 `advance --to developing` → 被 developing 目标态门禁拦截（测试向量 ⑦）。
3. 审批后修改 dev-plan.yml / plan.md / tasks/_index.yml → EVIDENCE_DRIFT（测试向量 ⑧）。
4. 状态机断言：两条新转换可 advance（普通轨回 tech-design-reviewed、上游轨回 tech-design-review-pending）；口径 27 声明 / 49 展开。
5. `check-agents-contract.mjs` 对 dir-graph 变更无漂移报警。

## 完成标志

测试向量 ⑥⑦⑧⑨ + 状态机断言全绿；gates.json 不删任何既有条目（只增条件）。

## 接口契约

- 消费：TASK-01 产出的 `review-annotations/dev-plan.yml`（passCondition/evidence digest 读取 verdict/blockers/repair-target）。
- 产出：`gates.json#approvalStages.dev-start` 的 evidence 三键映射与 passCondition 引用（TASK-05 的 pipeline 节点 ref `review-dev-plan` 必须与该 passCondition nodeRef 一致）；dir-graph 两条转换（TASK-03 Skill 文档引用的 trigger 名必须与之一致）。
