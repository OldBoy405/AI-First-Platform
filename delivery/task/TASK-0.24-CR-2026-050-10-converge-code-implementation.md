---
spec-id: ai-first-platform
version: "0.24"
id: CR-2026-050-TASK-10
type: TASK
cr-ref: CR-2026-050
plan-ref: "change-requests/CR-2026-050/plan.md"
sdd-ref: "change-requests/CR-2026-050/sdd.md"
title: code-implementation 收敛 + write-dev-plan 前缀 + 顺序/replayNodes 断言
slug: converge-code-implementation
status: pending
estimate: 6h
depends-on: [CR-2026-050-TASK-09]
created: 2026-08-21T11:57:27+08:00
---

## 任务描述

阶段二第 3 项：收敛 code-implementation 的 review-dev-plan / write-test-report / review-code / implement / freshness / write-dev-plan / write-dev-tasks 节点（FR-06.4/06.5、FR-07.6～07.9、FR-09），保留两条关键顺序与 §3.0/DD-4 保留字面量，并对齐 write-dev-plan SKILL.md 提交前缀。

## 涉及文件 / 模块

仓根只允许取 `execution_context.resources[]` 中 `repo=tools` 的 `worktreePath`；以下均为该仓根相对路径：

- `repo=tools: pipeline-templates/code-implementation.pipeline.json`（16 节点；approval 与 approve 节点已在 TASK-01/02 收敛，不得回改）
- `repo=tools: skills/develop/write-dev-plan/SKILL.md`（DD-7 提交前缀 `[cr] `）
- `repo=tools: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（FR-12.3 断言扩展 + 保留字面量核对）

## 实现要点

1. `review-dev-plan`：删除八维评审维度、双轨 advance 与 `--embedded` 细节；保留 reviewLoop 机器字段与 upstream 结果触发 abort 的路由。
2. `write-test-report`：删除 `cr-test-plan/v1` schema、白名单、`crctl test` 命令、机器区/marker/traceability 原子更新；只传 cr_id/source_node/tester/review_feedback/self_repair_attempt，消费 status/blockers/报告路径。
3. `review-code`：删除 runner 选择、取证命令、证据规则、评审维度、回修重建算法；只传输入并消费 verdict/blockers/test-report.status/repair-target；`replayNodes: implement → test-report → checkpoint → freshness → review-code` 原样保留。
4. `implement-code`：删除 runtime fallback、读取清单、并发算法；保留 `execution_context.resources[].worktreePath` 传递（测试 :185-188 保留）。
5. `workspace-freshness` 两节点：删除 syncable/freshness/sync 调用与路由算法；只传 cr_id+gate 名，消费 route；**保留 `implement-start`/`review-start` gate 名（:73-74）**。
6. `write-dev-plan`/`write-dev-tasks` 节点：只传契约输入（SDD §3.2），消费 plan/TASK 结构化结果；删除章节/status 校验/输入文件算法/接口签名规则/task init/估算交叉校验/索引失败算法。
7. 保留字面量（DD-4）：终点 checkpoint「审批结果」label（:157）、`auto_push_after_task`（:160）、checkpoint prompt 的 cr_id 引用（:38/:65）。
8. FR-12.3 断言扩展：`plan → TASK → review-dev-plan → human approval → developing` 与 `implement → test-report → checkpoint → freshness → review-code` 两条顺序、replayNodes 5 项、16 节点不变。

## 验收条件

1. 各节点收敛后无 `crctl test`/`crctl review-record`/`crctl task init`/diff/log 命令字面量与 deny 路径字面量；负向断言通过。
2. `:73-74`、`:157`、`:160`、`:38`/`:65` 保留字面量逐字核对通过；两条关键顺序断言通过。
3. write-dev-plan SKILL.md 无 `feat(` 前缀（改为 `[cr] `）。
4. `pipeline-structure.test.mjs` 全绿；`lint-prompts.mjs` 无新增触发；节点数仍为 16。

## 完成标志

上述 4 条验收全部通过，`git diff` 仅含本 TASK 列出的三个文件。

## 接口契约

- 消费：SDD §3.0 保留项、DD-4 处置清单、`write-test-report`/`review-code`/`workspace-freshness` 现行 SKILL 契约。
- 产出：code-implementation 16 节点收敛版 + FR-12.3 断言；reviewLoop replayNodes 是后续 checkpoint/freshness 回修链的唯一事实，不得漂移。
