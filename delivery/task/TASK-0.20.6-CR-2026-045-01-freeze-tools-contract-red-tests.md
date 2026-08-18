---
spec-id: ai-first-platform
version: "0.20.6"
id: CR-2026-045-TASK-01
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: tools 合同红测试冻结
slug: freeze-tools-contract-red-tests
status: pending
estimate: 4h
depends-on: []
created: 2026-08-17T20:39:31+08:00
---

# TASK-01 tools 合同红测试冻结

## 1. 任务描述

在 tools worktree 既有测试文件中写入表达目标行为的红测试，冻结三类合同：① architecture-design reviewLoop 复用既有 `replayPolicy=rerun-listed-nodes-in-order` + `replayNodes[{nodeId,ref,purpose}]` schema；② `emit-registry.mjs` 输出 canonical registry（schema / pipelineOwner / nodePermissions / digest）；③ `crctl review-record` 的 review outbox payload 含 `attempt`/`blockers`/`reviewed_at`/`subject_sha256`。红测试对基线 `462c3e9` 必须失败且失败原因精确（AC-02/AC-03/AC-06 的先行证据）。

## 2. 涉及文件 / 模块

- `pipeline-templates/architecture-design.pipeline.json`（只读，作为被测合同）
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（追加 architecture reviewLoop 与 registry 合同红测试）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（追加 review outbox 断言组）

## 3. 实现要点

- 红测试 1（reviewLoop）：在既有 `pipeline-structure.test.mjs` 读取 `architecture-design.pipeline.json`，断言 `review-tech-design.reviewLoop.replayNodes` 恰为 `[{nodeId:"...0016...001",ref:"write-tech-design",purpose:"repair-sdd"},{nodeId:"...0016...002",ref:"review-tech-design",purpose:"rerun-current-review"}]` 且 `replayPolicy` 为 `rerun-listed-nodes-in-order`；requirement Pipeline 的节点与 reviewLoop 逐字段不变。当前 architecture Pipeline 无该 reviewLoop，故失败。
- 红测试 2（registry）：在同一 `pipeline-structure.test.mjs` 调用待新增的 `pipeline-templates/emit-registry.mjs --pipeline architecture-design`，断言输出含 `schema=ai-first.pipeline-registry/architecture-core-v1`、`pipelineOwner=dev-agent`、每个节点 `owner` 唯一且 pipelineOwner 有 `owns|can-call`、`digest` 为 canonical SHA-256；`--check` 模式比较节点/prompt/permissions/replayLoop/digest。当前脚本不存在，故失败。
- 红测试 3（outbox）：在 bare fixture 上执行真实 `review-record --stage tech-design --bump-attempt`，断言生成的事件 payload 含 `attempt`、`blockers`、`reviewed_at`、`subject_sha256` 且 `subject_sha256` 等于 SDD LF 规范化 digest。当前 payload 缺这些字段，故失败。
- 测试命名带 `CR-2026-045` 前缀，便于后续 TASK 定位转绿集合。

## 4. 验收条件

1. 三组红测试已入库且对基线 `462c3e9` 失败，失败断言能指出「缺 reviewLoop / 无 emit-registry / outbox 缺 attempt/blockers/subject」。
2. 除红测试外，tools 既有全量测试不新增失败。
3. 不修改任何生产代码、Pipeline JSON 或 crctl.mjs 正文。

## 5. 完成标志

三组红测试入库 + 失败原因核对通过 + 其余测试零新增失败。

## 6. 接口契约

- 消费：无上游 TASK。
- 产出：`CR-2026-045 architecture reviewLoop schema`、`CR-2026-045 registry contract`、`CR-2026-045 review outbox payload` 三组测试名集合；TASK-02 转绿 reviewLoop/registry，TASK-03 转绿 outbox。
