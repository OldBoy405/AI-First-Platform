# SC-VC-002 / SC-VC-003（部分）证据（TestChannelFoundationReservation）

- 被测：`multica/server/internal/governance/execution_control_reservation.go`
- 测试：`server/internal/governance/execution_control_reservation_test.go`
- 源码 sha256（基线 = 每次 mutation 恢复后）：`c416518a45a7f4f79c860e13554f70739520d87abd91c2d12f45bef49dc2e1d5`
- 运行：`node scripts/aifi45-db/run.mjs ./internal/governance '^TestChannelFoundationReservation$' <prefix> -migration=server/migrations/648_cr_execution_control.up.sql`
- 证据前缀：green `foundation-reservation-green2-*`、m1/m2 `foundation-reservation-{m1,m2}-*`（首次 green 因事务中止失败，见下）

| 运行 | tests/pass/fail/skip | leaf_pass | 失败 leaf | exit |
|---|---|---|---|---|
| green | 3/3/0/0 | 2 | — | 0 |
| m1 去掉「只允许 strict 选择」守卫 | 3/2/1/0 | 1 | `control_reservation_not_runnable` | 1 |
| m2 忽略 23505（冲突当成功） | 3/2/1/0 | 1 | `fixed_id_conflict_and_rollback` | 1 |

三轮均 `original_unchanged:true`、`owned_resources_cleaned:true`、`skip=0`。

## 断言覆盖

- **不可执行**：reservation 行存在；`agent_task_queue` 中该 proposed task id 行数为 0；`cr_execution_control_reservation` 不存在 `task_id/runtime_id/status/dispatched_at/daemon_id` 任一列（结构上不可被 claim 查询匹配）；legacy selection 调 `CreateReservationTx` → `ErrReservationNotStrict`。
- **固定身份**：同 lineage + 同 candidate bytes 二次预留 → `ErrReservationConflict`；同 proposed task id + 异 candidate bytes → `ErrReservationConflict`；外层事务 rollback 后零残留。

## 过程记录（如实）

1. 首次 green 运行 2 fail：Postgres 中 23505 会中止整个事务，第二次「预期冲突」之后所有语句报 `current transaction is aborted`。这是测试写法缺陷，不是实现缺陷。
2. 修法：新增 `expectReservationConflict`，用 **savepoint** 包住每次预期失败（pgx `tx.Begin` 嵌套），断言后回滚 savepoint；重跑 3/3。
3. 该修法有被滥用的风险（savepoint 可能掩盖真实缺陷），已在独立复核任务中列为专问项。

## 未覆盖

- SC-VC-003 的 **同 Tx root+task+settlement 与 commit 后通知**（需 `AdmitDispatchRootTx`/`EnqueuePipelineTaskTx`，未实现）。
- SC-VC-004 的 `root_adoption_terminal_race`（`55P03` 探针，需 dispatch root 接线）。
