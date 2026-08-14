---
spec-id: ai-first-platform
version: "0.24"
id: CR-2026-023-TASK-04
type: TASK
cr-ref: CR-2026-023
plan-ref: "change-requests/CR-2026-023/plan.md"
sdd-ref: "change-requests/CR-2026-023/sdd.md"
title: 块 A — code-implementation pipeline 插入「选择代码评审 LLM」节点（FR-1/2/3/4）
slug: pipeline-review-llm-node
status: pending
estimate: 5h
depends-on: [CR-2026-023-TASK-03]
assignee: ""
created: "2026-08-07T00:40:00+08:00"
---

## 任务描述

在 `code-implementation.pipeline.json` 落地块 A 四处改动：新增 `review_llm` 输入（FR-1）、插入 0013 human_approval 节点（FR-2）、review-code prompt 头部追加段（FR-3）、验证 replayNodes 不含 0013（FR-4）。**依赖**：depends-on 指向 TASK-03（commit 1 收口）——commit 1 = TASK-01+02+03 原子批，commit 2（本任务）必须在 commit 1 整体落地后执行，故依赖连到 commit 1 的收口任务而非仅 TASK-01，保证图语义与「commit 1 先于 commit 2」约束一致。**前置**：与用户确认 tools 仓 3 处未提交 pipeline JSON 修改的归属（本文件含 `auto_push_after_task` default 改动，同文件不同 hunk，按 hunk 拆分 add，SDD §4.3 基线协调）。

## 涉及文件 / 模块

- `pipeline-templates/code-implementation.pipeline.json`

## 实现要点（SDD §2.1/§2.2/§3.1/§3.2/§4.2）

1. `inputs[]` 追加 `review_llm`（type text、required false、placeholder/description 见 SDD §2.1）。
2. `nodes[]` 在 `nodes[8]`（0008 push-progress）与 `nodes[9]`（0009 review-code）之间插入 0013 节点（SDD §2.2 定稿 JSON：kind human_approval、onFail abort、timeoutMinutes 4320、approvalPrompt 用 SDD §3.1 三分支文案）。插入后 `nodes[9..12]` 整体后移一位，UUID 不变。
3. review-code（0009）节点 `prompt` 字段**最前面**拼接 SDD §3.2 追加段，其余文本零改动。
4. `reviewLoop.replayNodes` **零改动**——显式 nodeId 引用，0013 天然不在重放列表（SDD §4.2）。

## 验收条件

1. `node -e "JSON.parse(require('fs').readFileSync('pipeline-templates/code-implementation.pipeline.json','utf8'))"` 解析通过；`nodes.length === 13`。
2. 数组顺序上 0013（human_approval）位于 0008 与 0009 之间；`inputs` 含 `review_llm`；review-code prompt 首段含 reviewer-model 留痕要求。
3. review-code `reviewLoop.replayNodes` 恰为 4 项（implement-code/write-test-report/push-progress/review-code），不含 0013；write-test-report reviewLoop 未变。
4. 提交只含本 CR hunk，不混入用户 3 处未提交修改（git diff 核对）。

## 完成标志

块 A pipeline 改动落地 + JSON 自检通过 + replayNodes 验证；commit 2 提交（commit 1 块 B 之后）。
