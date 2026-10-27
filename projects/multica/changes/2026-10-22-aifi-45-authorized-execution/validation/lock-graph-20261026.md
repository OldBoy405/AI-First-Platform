# 执行链锁图（2026-10-26 起，B2 → B3 → G5 → G1）

> 目的：在加锁之前先确定顺序，避免"修一个 TOCTOU 换来一个死锁"。本文记录只读核实结果与已实施顺序；没做的部分明确标出，不写"无死锁"。

## 1. 变更史

| 阶段 | 顺序 | 出处 |
|---|---|---|
| CR 绑定（既有） | **task FOR UPDATE → issue → project → cr** | `internal/service/task.go::BindCurrentTaskToCR` |
| 消费（B2 前） | head → 无 task 锁 | `execution_consumption.go` |
| 签发/激活（B2 前） | head → 不碰 task 行 | `execution_binding_issue.go`、`execution_activation.go` |
| 消费（B2） | task SHARE → head | `execution_consumption.go` |
| **三个写端点（G1，当前）** | **task SHARE → runtime SHARE → head** | `execution_claim_lock.go::lockExecutionClaimRows` |
| 终态（B3） | 只做 task 的 CAS UPDATE，判定在 CAS 之后同一事务内 | `pkg/db/queries/agent.sql`、`service/terminal_claim.go` |
| dispatch root（G5） | **root FOR UPDATE → generation CAS + terminal 谓词 + RETURNING generation** | `execution_dispatch_root.go` |

B2 前的冲突（记录在案，勿再犯）：消费持 CR 后若再拿 task，与绑定的 task→CR 成环；因此 head 必须是最后一段，task 必须先拿。

## 2. 当前顺序（三个写端点共用）

`lockExecutionClaimRows(task, runtime)` → `lockExecutionAuthorizationHead(cr, approval_record)`

- **为什么还要 runtime**：`GetExecutionBindingClaim` 的判定依据是 `agent_task_queue` **和** `agent_runtime`——任务必须仍是该 runtime 的 active generation，runtime 必须仍属已认证 daemon。只锁 task 时，"runtime 换 daemon"可以在 claim 读与写入之间提交，证明/收据/激活照样落库。
- **为什么 FOR SHARE 不是 FOR UPDATE**：这三个端点从不改这两行；要排除的写者（取消/重领任务、runtime 归属变更）都取 FOR UPDATE。共享锁还允许同一 run 的并发请求并行，FOR UPDATE 会无意义地串行化。
- **runtime 位置**：claim 查询是 task `JOIN` runtime，故 runtime 紧随 task；head 最后。

## 3. 已验证（动态）

| 断言 | 证据 |
|---|---|
| 三个端点都持 task 锁（另一个连接改该任务行被 `55P03` 挡住） | `TestExecutionClaimRowLock{Binding,Consumption,Activation}`，300ms 探针，`todo-a-20261026/g1-green-20261027T043903Z`（3/3，leaf_pass 3，skip 0） |
| 三个端点都持 runtime 锁 | 同上 |
| **修前确实是缺的**：签发/激活连 task 锁都没有；消费有 task 锁但没有 runtime 锁 | `g1-red-20261027T043722Z`（3 run / 3 fail / 0 skip）：binding→task 未挡，consumption→**runtime** 未挡（task 已挡，说明探针能分辨），activation→task 未挡 |
| 两把锁各自 load-bearing（非冗余） | `g1-mutations-20261027T043944Z`：`m1-no-runtime-lock` 3 fail、`m2-no-task-lock` 3 fail，各自命中所缺那把 |
| **锁强度 load-bearing**（不只是"有锁"） | `m3-runtime-key-share`（`FOR KEY SHARE`）3 fail：弱锁挡不住非键列更新，正是归属变更这一向量 |
| 无回归 | `g1-full-governance-20261027T044122Z`：957 run / 955 pass / 1 fail / 1 skip，leaf_pass 864（基线 861+3）。fail=`TestTC_NTF_003`、skip=`TestReconcileLiveGitHub`，均为既有（`g5-full-governance-env` 954/952/1/1） |

## 4. 只读核实的相邻路径（静态，未动态取证）

| 路径 | 取锁情况 | 与 task→runtime 的关系 |
|---|---|---|
| claim/reclaim：`ReclaimStaleDispatchedTaskForRuntime(s)`、`ExpireStaleQueuedTasks`、`FailExpiredRuntimeReconnectRetries` | 只锁 **task**（`FOR UPDATE [OF t]`），`agent_runtime` 仅被 JOIN 读 | 同向（task 先），不反向取 runtime 锁 |
| supplement：`StartAgentTaskWithSupplement`、`CreateTaskSupplement`、`BindCommentTaskSupplement` | 同上，`FOR UPDATE OF t` | 同向 |
| runtime 单点：`LockAgentRuntime`、`LockAgentRuntimeForAccessChange`、`LockRuntimesForMerge`、`ListAgentRuntimeIDsByProfile` | 只锁 runtime | 单资源，不涉 task |
| `daemon.go:2167` | runtime FOR UPDATE → `GetAgentForUpdate`（agent 行） | runtime→agent；与我们的 task→runtime 不构成二资源环 |
| **workspace teardown** `handler/workspace.go::lockWorkspaceTaskOwners` | workspace → agents → issues → **runtimes**（集合式 FOR UPDATE），稍后才删 task | **反向对（runtime 早于 task）**：该路径自己在注释里写明与"task 行然后 owner"的并发更新可能死锁，且以自身 `lock_timeout` 视为可重试 503 |

## 5. G5：dispatch root

`AdmitDispatchRoot` 先按 `cr_execution_dispatch_root` 行 `FOR UPDATE`（含 `adoption_digest`），再以 `terminal_at IS NULL` + 期望 generation + `adoption_digest` 谓词执行 UPDATE 并 `RETURNING generation`；0 行即回读 `terminal_at` 区分 `ErrDispatchRootTerminal` 与 `ErrDispatchAdoptionRejected`。撤销/CR 锁路径不反向取 root 锁。

证据：`TestTC_RUN_004_DispatchRootAdoptionHoldsTheRootRowLock/{terminal,adopt}`（`55P03` 探针）、`TestTC_RUN_004_DispatchRootAdoptionHasOneWinner`；`g5-green`/`green2` 6/6。变异：去 `FOR UPDATE` RED；同时去掉 Go 层摘要检查与 SQL 谓词 RED；单独去 CAS（`m2b`）、单独去 Go 检查（`m3`）、单独去 SQL 谓词（`m4`）为 **GREEN → 冗余防线，不宣称各有独立测试**。

## 6. 未验证 / 已知代价（不得当成已证）

1. **没有动态证伪"执行链无死锁"**。三个端点与 bind/reclaim/teardown 只做到顺序一致（必要条件）；仍需一条并发用例（同任务同时 bind 与 consume，断言无 `40P01`）才能声称。
2. **workspace teardown 的反向对是已知代价**，靠它自己的 `lock_timeout` + 可重试 503 兜底；本文不声称这对已消除。
3. **runtime 心跳会被延迟**：心跳更新 `agent_runtime.last_seen_at` 需等这三个端点的事务结束。事务内无网络、无重活，代价是毫秒级；如需进一步隔离，应改为"只锁心跳不写的列"这类结构改造，属后续优化。
4. **终态路径**仍不加锁（B3 的 CAS 后判定），未纳入本轮探针。
5. G1 只覆盖"任务/runtime 归属"这一层；可信 current-head、撤销、受保护 store 归 M003（G6），不得据此标 PRESENT。
