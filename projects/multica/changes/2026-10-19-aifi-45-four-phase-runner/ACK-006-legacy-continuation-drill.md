# AIFI-45 收尾：旧 approval-continuation 存量处置演练（M-CP-ACK-006）

> **状态：未执行。** 本文档只描述**有序处置流程**，不操作任何真实 task 或审批。
> canonical `M-CP-ACK-006` 的断言本身就是「真实旧续接处置未执行」；在旧 running
> 未确认退出之前，禁止模拟恢复正常调度。历史审批仍可兼容读取。

## 1. 为什么要处置

AIFI-45 把审批 ack 改回**纯送达**（M50）：`HandleGrantsAck` 不再解析续接目标、
不再入队续接任务，也不再因单个 CR 解析失败而整批回滚。恢复持久执行改由
`Runner.ResumeActiveRuns` 在 30s sweeper 周期里按 pipeline 完成（M42/M43）。

因此 `EnqueueApprovalContinuation` / `resolveContinuationTarget` /
`NotifyContinuationTaskEnqueued` 这套**旧续接机器已无生产调用方**，但代码与
历史数据行仍在。存量行如果继续被消费，会出现「同一节点既被 Runner 派发、又被
旧续接派发」的双派发。

## 2. 存量长什么样（识别口径）

旧续接任务行的唯一识别特征是 `agent_task_queue.context`：

```json
{
  "type": "approval_continuation",
  "schema": "ai-first.approval-continuation/v1",
  "approvals": [
    {"cr_id": "...", "stage": "requirement|tech-design|dev-start|code",
     "decision": "approve|reject", "approval_record_id": "..."}
  ]
}
```

对应写入方是 `internal/service/approval_continuation.go::EnqueueApprovalContinuation`
（`CreateApprovalContinuationTask`，`status='queued'`，`fire_at IS NULL`）。

**只读盘点 SQL**（在目标库执行，先看不要改）：

```sql
-- 总量与状态分布
SELECT status, count(*) FROM agent_task_queue
WHERE context->>'type' = 'approval_continuation'
GROUP BY 1 ORDER BY 2 DESC;

-- 按阶段/决定分布
SELECT a.value->>'stage' AS stage, a.value->>'decision' AS decision, count(*)
FROM agent_task_queue t, jsonb_array_elements(t.context->'approvals') a
WHERE t.context->>'type' = 'approval_continuation'
GROUP BY 1,2 ORDER BY 3 DESC;

-- 关联的 CR 与审批记录（判断是否已被 Runner 接管）
SELECT t.cr_id, t.status, t.created_at, r.stage, r.decision, r.delivered_at
FROM agent_task_queue t
LEFT JOIN approval_record r ON r.id::text = (t.context->'approvals'->0->>'approval_record_id')
WHERE t.context->>'type' = 'approval_continuation'
ORDER BY t.created_at;
```

判定口径：

- `status='queued'` 且**没有**对应 `pipeline_node_run` 的 CR → 纯存量，可收尾。
- `status='queued'` 且该 CR **已有** Runner 活跃 run → **高危双派发源**，优先收尾。
- `status='running'` → **停止**，进入第 3 步前置检查，不得强行终止。
- `status IN ('completed','cancelled','failed')` → 历史行，只读留档，不收尾。

## 3. 前置检查（不满足则整体中止）

1. **确认无旧 running**：第 2 步盘点中 `status='running'` 的行数必须为 0。
   非 0 时**禁止**进入收尾——先等其自然终态，或由人类在 TTY 逐个处理。
2. **确认 Runner 已接管**：对每个涉及 CR，`crctl status {cr_id} --workspace <ws>`
   给出的阶段与 `pipeline_run` 的活跃 run 一致；不一致的 CR 单独列出、暂不收尾。
3. **确认审批事实不动**：`approval_record` 是权威事实，收尾只动
   `agent_task_queue`，绝不改审批/评审事实。
4. **留痕**：收尾前后各跑一次第 2 步盘点 SQL，输出存档。

## 4. 有序收尾（人工在 TTY 执行，逐步确认）

按「高危 → 纯存量」顺序，一次一个 CR，不要批量：

1. 对该 CR 先取权威事实：`crctl status {cr_id}` 与 `crctl next {cr_id}`。
2. 若 `next` 已指向 Runner 阶段（即 Runner 会派发），把该 CR 的
   `approval_continuation` 行置为 `cancelled`，并记录 `approval_record_id`。
3. 若 `next` 未指向任何阶段（CR 已终态），同样置 `cancelled`。
4. 每个 CR 收尾后复核一次：该 CR 的 `pipeline_node_run` 是否出现**重复**节点行
   （同 `node_id` 同 `attempt` 出现两条即双派发证据），出现则回滚该步并上报。
5. 全部完成后，确认 sweeper 的 `ResumeActiveRuns` 仍能正常发现活跃 run
   （`go test ./internal/governance -run '^TestMTick003$'` 应通过）。

## 5. 收尾之后（代码侧，可另行排期）

存量处置完，旧续接机器即可删除，属于**减法定制**：

- `internal/service/approval_continuation.go`（`EnqueueApprovalContinuation`、
  `NotifyContinuationTaskEnqueued` 及 `ApprovalContinuationSpec`）
- `internal/governance/approval.go` 的 `approvalContinuationEnqueuer` 接口成员、
  `continuationTarget` 与 `resolveContinuationTarget`
- 对应 sqlc 查询（`CreateApprovalContinuationTask` /
  `GetApprovalContinuationTaskByRecord` 等）与既有 `TestAC*` 断言

删除前须在 `CUSTOM.md` 登记（当前为 `#150`，注明"存量已收尾后摘除"），
并重跑 `go test ./internal/governance ./internal/service`。

## 6. 本次实测（2026-10-20，隔离测试库）

在 AIFI-45 自建隔离测试库 `aifi45_test` 上只读盘点：

```
context->>'type' = 'approval_continuation'  →  0 行
context->>'type' = 'pipeline_node'          →  0 行
其余 agent_task_queue                       →  6022 行，全部 completed 且无 context type
```

即**测试库无任何旧续接存量**，本地无可演练对象；真实存量只可能存在于生产库，
须由人类按第 2–4 步执行。
