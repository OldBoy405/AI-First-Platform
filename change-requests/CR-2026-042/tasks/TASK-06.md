---
id: CR-2026-042-TASK-06
type: TASK
cr-ref: CR-2026-042
plan-ref: "change-requests/CR-2026-042/plan.md"
sdd-ref: "change-requests/CR-2026-042/sdd.md"
title: CI workflow 合并与 Pipeline 固定结构断言
slug: merge-ci-and-pipeline-checks
status: pending
estimate: 8h
depends-on:
  - CR-2026-042-TASK-02
  - CR-2026-042-TASK-05
created: 2026-08-16T15:34:15+08:00
---

# 1. 任务描述

按 SDD §2.5.2/§2.5.3：保留 `crctl-ci.yml` 为唯一主治理 workflow，删除重复的 `check-skill-matrix.yml`；补 Pipeline JSON 固定结构断言；补 paths；在 `crctl.test.mjs` 增加本 CR 静态合同测试向量。

# 2. 涉及文件 / 模块

- `.github/workflows/crctl-ci.yml`
- `.github/workflows/check-skill-matrix.yml`（删除）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`

# 3. 实现要点

- `crctl-ci.yml` 保留 `check-skill-matrix.mjs` 与 `check-agents-contract.mjs` 调用，保留 Ubuntu/Windows matrix 与全部测试；
- push/pull_request paths 增加 `README.md`、`AGENT-SKILL-MATRIX.md`，并明确覆盖 `agent-skill-matrix.yml`、`dir-graph.yaml`、`agents/**`、`skills/**`、`pipeline-templates/**`、`skills/shared/controlled-shell/rules.json`、workflow 自身；
- Pipeline JSON 检查步骤从「仅 JSON.parse」扩展为固定断言：`id`/`triggerCommand`/`inputs[]`/`nodes[]` 存在、node id 唯一、Skill node 有 active `ref`、`reviewLoop.repairNodeId` 与 `replayNodes[].nodeId` 指向现存节点；
- 不解释 prompt、不模拟状态机、不执行 Pipeline；
- `crctl.test.mjs` 追加：code Pipeline 16 节点/无 review_llm/无 `...0013`、`...0017` 后继 `...0009`、`_index.yml` nodes=16、check-skill-matrix.yml 已删、crctl-ci 仍调两个 checker、paths 覆盖、README 必需章节/禁止内容、已知 Skill 越界零命中。

# 4. 验收条件

1. `.github/workflows/check-skill-matrix.yml` 不存在；
2. `crctl-ci.yml` 同时调用 `check-skill-matrix.mjs` 与 `check-agents-contract.mjs`，且 matrix 为 ubuntu+windows；
3. paths 覆盖 PRD FR-05.2 全部路径；
4. Pipeline JSON 固定断言步骤存在于 workflow，且对坏 JSON/重复 node id/悬空 replayNodes 能失败；
5. `node skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿（含新增静态合同向量）。

# 5. 完成标志

单一主治理 workflow 就位、重复 workflow 删除、Pipeline 固定断言与静态合同测试全绿。

# 6. 接口契约

- 消费：TASK-02 的 code Pipeline 16 节点结构；TASK-05 的 `lint-prompts.mjs --mode enforce`。
- 产出：`.github/workflows/crctl-ci.yml`（唯一主治理 workflow）+ `crctl.test.mjs` 静态合同向量；下游 TASK-07 消费做全量验证。
