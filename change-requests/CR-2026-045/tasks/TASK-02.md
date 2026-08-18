---
id: CR-2026-045-TASK-02
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: architecture reviewLoop 与 emit-registry 生成器
slug: architecture-reviewloop-and-emit-registry
status: pending
estimate: 6h
depends-on:
  - CR-2026-045-TASK-01
created: 2026-08-17T20:39:31+08:00
---

# TASK-02 architecture reviewLoop 与 emit-registry 生成器

## 1. 任务描述

在 tools 侧落地两处合同：① 给 `architecture-design.pipeline.json` 的 `review-tech-design` 增加既有 `replayLoop` schema（`replayPolicy=rerun-listed-nodes-in-order` + `replayNodes[{nodeId,ref,purpose}]`），并让 review/approve/push-progress 节点 prompt 改为每节点独立 `crctl workspace inspect`，不依赖本地 node-N 文件；② 新增 `pipeline-templates/emit-registry.mjs`，用 tools 既有 `yaml-subset.mjs` 读 matrix/index，输出 canonical registry JSON。转绿 TASK-01 的 reviewLoop 与 registry 两组红测试。

## 2. 涉及文件 / 模块

- `pipeline-templates/architecture-design.pipeline.json`（加 reviewLoop，保留 5 节点与 `onFail=abort`）
- `pipeline-templates/emit-registry.mjs`（新增）
- `pipeline-templates/emit-registry.test.mjs`（转绿红测试）

## 3. 实现要点

- reviewLoop 的 `replayNodes` 使用当前 `0016` 节点 UUID（`00000000-0000-0000-0016-000000000001` / `...0002`），`ref` 与 `purpose` 依次为 `write-tech-design/repair-sdd`、`review-tech-design/rerun-current-review`；不改 requirement Pipeline。
- `emit-registry.mjs` 只做确定性转换与硬校验：CRLF→LF、Pipeline active、Skill active、每个 Skill 恰一个 owner、pipeline owner 对每个 Skill 有 `owns|can-call`；输出 `{schema,pipeline,pipelineOwner,nodePermissions,digest}`。
- prompt 渲染只允许 `{{inputs.cr_id}}` 与 `{{inputs.tech_context}}` 两个字面 token，用 `String.replaceAll`；`tech_context` 作为有长度上限数据块附加；生成后仍有 `{{`/`}}` 即硬失败，不实现表达式解释器。
- 失败非零退出，不输出空 registry；`--check` 模式比较节点/prompt/permissions/replayLoop/digest。

## 4. 验收条件

1. TASK-01 的 reviewLoop 与 registry 两组红测试转绿。
2. `emit-registry.mjs --pipeline architecture-design` 输出 schema/owner/can-call 校验通过，残留 `{{` 时非零退出且不落盘空文件。
3. requirement Pipeline 的节点与 reviewLoop 逐字段不变（合同测试锁定）。

## 5. 完成标志

reviewLoop 合同与 emit-registry 生成器落地 + 两组红测试转绿 + requirement Pipeline 不变。

## 6. 接口契约

- 消费：TASK-01 产出的 reviewLoop/registry 测试名。
- 产出：`emit-registry.mjs --pipeline architecture-design` 输出的 `{schema,pipeline,pipelineOwner,nodePermissions,digest}`（schema=`ai-first.pipeline-registry/architecture-core-v1`，pipelineOwner=`dev-agent`）；TASK-05 消费该输出嵌入生成物，TASK-07 消费 digest 与 nodePermissions。
