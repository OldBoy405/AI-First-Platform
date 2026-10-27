# 执行链锁图（2026-10-26，B2）

> 目的：在加锁之前先确定顺序，避免"修一个 TOCTOU 换来一个死锁"。本文只记录只读核实结果与已实施顺序；未做的部分明确标出。

## 1. 现状与冲突

| 路径 | 取锁顺序 | 出处 |
|---|---|---|
| CR 绑定 | **task FOR UPDATE → issue → project → cr** | `internal/service/task.go::BindCurrentTaskToCR`（`LockAgentTaskForCrBind` 等） |
| 消费（改前） | **CR head（cr 行 + approval_record SHARE）→ 无 task 锁** | `execution_consumption.go` 调 `lockExecutionAuthorizationHead` |
| 签发 | head → …（不碰 task 行） | `execution_binding_issue.go:160` |
| 激活 | head → …（不碰 task 行） | `execution_activation.go:82` |
| 终态 | 只做 task 的 CAS UPDATE（设计上不加锁） | `pkg/db/queries/agent.sql:817 GetAgentTaskForTerminalClaim` 注释 |

冲突：消费持 CR 后若再拿 task，与 CR 绑定的 task→CR 成环。这不是理论问题——评审判定它是 B2 的 blocker，直接加 `FOR SHARE` 会引入死锁。

## 2. 已实施的顺序

统一为 **task 行 → CR head（cr + approval_record）→ 新表**：

- `execution_consumption.go`：在 `lockExecutionAuthorizationHead` **之前**先 `SELECT id FROM agent_task_queue WHERE id=$1 FOR SHARE`；行不存在即 409 `EXECUTION_BINDING_SCOPE_MISMATCH`。
- 理由有二：与 CR 绑定的 task→cr 一致；并让"读 claim 之后、写收据之前"的终态更新被挡住（评审的 claim TOCTOU）。

## 3. 已验证

| 断言 | 证据 |
|---|---|
| 消费进行中，另一连接改该任务终态会被 `55P03` 挡住 | `TestExecutionConsumptionRefusesMovedAuthority/the_task_row_is_locked_before_the_head`，`lock_timeout=300ms` 探针；未加锁时该探针返回 `<nil>`（RED） |
| 收紧后同代重放/撤销/竞争不回归 | 同套 8/8，0 skip；TC-AUTH-009 仍绿 |

## 4. 未验证（不得当成已证）

1. **CR 绑定与消费的并发死锁未被动态证伪**。顺序一致是必要条件，不是充分条件；需要一条并发用例（同任务同时 bind 与 consume，断言无 `40P01`）才能声称"无死锁"。
2. ~~终态路径没有加锁~~ **已由 B3 处理（2026-10-26）**：终态仍走 CAS，但判定放在 CAS **之后**、同一事务内——CAS 已持该行写锁，未提交的消费（`FOR SHARE`）会挡住它，提交后新快照才读到，因此不需要把终态改成 `FOR UPDATE`。证据见 `tc-coverage` 增量 24。
3. **claim/reclaim 路径**（`execution_task_claim.go`）未纳入本轮锁图核实。

## 5. 结论

B2 的"直接加锁会成环"已按 task→CR 顺序解决，并用锁探针证实了 task 锁真实存在且生效。B3 因此**解除了锁序障碍**，但它自己仍需改终态路径；在 4.1 与 4.2 补上之前，不得写"执行链无死锁"或"终态 fence 已闭合"。
