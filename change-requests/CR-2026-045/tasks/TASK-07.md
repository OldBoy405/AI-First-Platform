---
id: CR-2026-045-TASK-07
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: Runner Start 与 Reconcile 幂等调度
slug: runner-start-and-reconcile
status: pending
estimate: 12h
depends-on:
  - CR-2026-045-TASK-04
  - CR-2026-045-TASK-05
  - CR-2026-045-TASK-06
created: 2026-08-17T20:39:31+08:00
---

# TASK-07 Runner Start 与 Reconcile 幂等调度

## 1. 任务描述

新增 `internal/governance/runner.go`，实现固定 `architecture-design` 的 Start endpoint 与幂等 `Reconcile(run)`。Reconcile 是唯一调度入口：读取固定生成 registry、现有 run/node/task/CR/review/approval/checkpoint 投影，最多执行一个确定的下一动作；不解析 Agent 文本、blocker 文本或 crctl stderr 决定路由。

## 2. 涉及文件 / 模块

- `server/internal/governance/runner.go`（新增：Start + Reconcile + 错误码 + 后置条件矩阵）
- `server/internal/governance/runner_test.go`（table tests + 竞态集成）
- `server/cmd/server/router.go`（`POST /api/workspaces/{workspaceID}/pipeline-runs` wiring，见 TASK-09 也可合并，本 TASK 定义 handler 签名）

## 3. 实现要点

- Start：只接受 `X-Actor-Source=task_token`；Auth 盖写 `X-Agent-ID/X-Task-ID/X-Workspace-ID`；CR 投影必须 `requirement-approved` 且 `needs_reconcile=false`；source task、executor Agent、CR 同 workspace；executor active、runtime-bound、启用全部 Skill；pipelineOwner=dev-agent 对每节点 `owns|can-call`。INSERT 依赖 partial unique index，冲突后重读同一 run，`changed=false`。
- run 输入 `inputs={cr_id,tech_context}`、`execution_context={runner:architecture-core/v1,template_digest,pipeline_owner,executor_agent_id,source_task_id}`；`started_by` 用 task-token 绑定的 `X-User-ID`。
- Reconcile 步骤固定：① 取唯一非终态 run；② digest 比对，不同则 run failed `TEMPLATE_DIGEST_MISMATCH`；③ `SELECT ... FOR UPDATE` run 并重读投影；④ 按 §5 后置条件矩阵定当前节点；⑤ active task 返回；⑥ terminal 但权威后置未到，`detail.runner.wait_reason=authority_postcondition`；⑦ 双重成功则 mark passed 并创建下一节点；⑧ 最终失败无 retry 则 node/run failed；⑨ 每次最多入队一个 task。
- attempt：初始 write/review attempt=1；block 事件 attempt=N 后 replay repair/review 用 attempt=N+1；`verdict=block && attempt=maxAttempts` 即 `RUNNER_LOOP_EXHAUSTED`，不自增、不解析 stderr。
- detail 多写：Runner 只用 `jsonb_set(...,'{runner}',...)`，不覆盖 verdict/blockers/attempt。

## 4. 验收条件

1. 表测试：happy path、block→repair→pass、canonical attempt=max exhausted、reject、checkpoint 全通过（AC-04~AC-07、AC-10）。
2. 双重后置条件：task terminal 与 CR/review/checkpoint 事件两种顺序均只到一半不前进；subject digest 缺失/陈旧阻断（AC-19）。
3. 竞态：双 start、start-vs-projector 只产生一个非终态 run 与一个首节点 attempt（AC-20）。
4. 恢复：四窗口启动扫描继续同一 run 且无重复有效 task（AC-12）；digest 漂移 fail closed、还原可续（AC-13）。
5. 错误码覆盖 `RUNNER_*`/`TEMPLATE_DIGEST_MISMATCH`/`RUNNER_ATTRIBUTION_INVALID`/`RUNNER_REVIEW_EVIDENCE_INCOMPLETE`/`RUNNER_LOOP_EXHAUSTED`。

## 5. 完成标志

runner.go 落地 + 表测试/竞态/恢复/错误码断言通过 + 无第二套 run 表。

## 6. 接口契约

- 消费：TASK-04 索引、TASK-05 的 `ArchitectureCoreRegistryJSON/Digest`、TASK-06 的 `EnqueuePipelineTask`。
- 产出：`StartArchitecture(ctx, wsID, crID, inputs) (runID, changed, error)` 与 `Reconcile(ctx, wsID, crID) error`；handler `POST /api/workspaces/{workspaceID}/pipeline-runs` 请求体 `{pipeline_id,cr_id,inputs}`；TASK-09 接唤醒与 router，TASK-08 消费入队后的 task context。
