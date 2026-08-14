---
id: CR-2026-039-TASK-04
type: TASK
cr-ref: CR-2026-039
plan-ref: "change-requests/CR-2026-039/plan.md"
sdd-ref: "change-requests/CR-2026-039/sdd.md"
title: code Pipeline PASS 后审批前 checkpoint 节点与 suggestion_policy 删除
slug: post-review-checkpoint-node
status: pending
estimate: 2h
depends-on: [CR-2026-039-TASK-03]
created: 2026-08-15T01:31:31+08:00
---

# 任务描述

在 `code-implementation.pipeline.json` 结构性插入 review-code PASS 后、人工审批前的 checkpoint 节点（现有 `push-progress` Skill，一次 `crctl checkpoint` 调用），并删除该 pipeline 的 `inputs.suggestion_policy` 输入定义。强制性来自节点顺序与 `onFail: abort`，不靠 prompt 告诫。

# 涉及文件 / 模块

- `pipeline-templates/code-implementation.pipeline.json`
- `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（新建，`node --test`）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（若现有 release-subjects 覆盖不足，补充 KB 白名单后继回归）

# 实现要点（SDD §3.2、§3.3）

- 新节点 JSON（逐字契约）：
  ```json
  {
    "id": "00000000-0000-0000-0015-000000000015",
    "kind": "skill",
    "label": "代码评审 PASS 后审批前 checkpoint",
    "ref": "push-progress",
    "prompt": "执行 push-progress：cr_id={{inputs.cr_id}}，message=代码评审通过后审批前 checkpoint。\n\n在节点输出中记录 batchId、repositories、phase；phase 非 complete 时中止，不得进入人工审批。",
    "onFail": "abort",
    "timeoutMinutes": 15
  }
  ```
- 插入位置：`…0009`（review-code）之后、`…0010`（human_approval 代码审查通过）之前；按节点 id 定位，禁止依赖数组行号。
- `…0010` approvalPrompt 追加一句："且评审后 checkpoint phase=complete"。
- `reviewLoop.replayNodes` 不改：重放再次 PASS 后控制权自然落到新节点，重新 checkpoint 由顺序保证。
- 删除 `inputs` 中 `key: suggestion_policy` 定义（FR-04 联动）。

# 验收条件

1. 结构测试：`JSON.parse` 后节点序 review-code(…0009) < push-progress(…0015) < human_approval(…0010) < approve-code(…0011)。
2. 新节点 `onFail === 'abort'`、`ref === 'push-progress'`；节点 id 全局唯一（含 …0015 与既有 14 节点）。
3. review-code 节点 `reviewLoop.replayNodes` 与现状逐字一致（implement-code→write-test-report→push-progress→review-code）。
4. `inputs` 中无 `suggestion_policy`。
5. 执行并保持现有 release-subjects 回归：KB 仅发生 `review-annotations/`、`cr.md`、`traceability.yml`、`review-loop.yml`、`approval.yml`、`_backlog.yml` 等白名单后继变化时 approve-code 仍可通过；KB 非白名单路径、非 KB 仓 HEAD 前移、artifact digest 漂移均拒绝且零写入。若现有测试未覆盖 KB 白名单后继，补入 `skills/shared/crctl/scripts/test/crctl.test.mjs`。

# 完成标志

结构测试全部通过 + 既有全量测试不回归；提交为一个可回滚 commit。

# 接口契约

- 消费：无上游 TASK 产出；pipeline 节点 schema 与既有 push-progress 节点（如 …0008）逐字段同构。
- 产出：修订后的 `pipeline-templates/code-implementation.pipeline.json` + `test/pipeline-structure.test.mjs`（供 TASK-06 回归运行；TASK-05 不依赖本测试文件）。
