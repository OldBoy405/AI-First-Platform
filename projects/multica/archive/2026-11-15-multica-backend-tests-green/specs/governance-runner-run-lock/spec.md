# Spec: governance-runner-run-lock

> Change: 2026-11-15-multica-backend-tests-green | Auto-generated Human View

## Requirements

### Requirement: 同一个 run 的并发唤醒（周期扫描、启动扫描、事件唤醒）在连接池上限为 4 时全部完成， 并且只派发 1 个任务；等待锁的唤醒不占用池连接。

#### Scenario: SC-RRL-001

- **GIVEN** 一次性迁移库；governance 测试包的连接池上限为 4；一个活动 run； 6 个 `ResumeActiveRuns`、1 个 `Reconcile`、1 个事件唤醒并发发起（既有 `TestMTick003`）
- **WHEN** 运行 `TestMTick003`
- **THEN** SHALL 在超时内完成（不挂起）
- **AND** 派发的任务数恰好为 1，run 持有的任务数为 1
- **AND** 第一个节点仍在第 1 次尝试

### Requirement: `withRunLock` 保持原先的锁语义：同一 run 的 `fn` 严格串行，锁在 `fn` 结束后释放，等待中被取消的调用返回取消错误 且不留下锁或连接。

#### Scenario: SC-RRL-002

- **GIVEN** 一次性迁移库；同一个 run id；两个 goroutine 调用 `withRunLock`，`fn` 内用计数器检测并发进入； 另有一个持锁且未返回的 `fn`，以及一个在等锁、随后 ctx 被取消的调用
- **WHEN** 两个调用并发执行并随后同一 run id 再调用一次；以及在持锁期间取消等锁调用的 ctx
- **THEN** SHALL 任意时刻最多 1 个 `fn` 在执行，第一次调用返回后锁被释放使第三次调用无需等待即可进入；被取消的等锁调用返回 `ctx.Err()`
- **AND** 取消返回后，池里已获取的连接数不超过持锁者占用的那 1 条
- **AND** 持锁者返回后，同一 run id 的下一次调用可立即获得锁

### Requirement: 三处同类的等锁点（`Reconcile`、`reconcileCode`、`reconcileRequirement`）都使用 `withRunLock`； `upsertRequirementRun` 的等锁点保持不变（其临界区已在锁连接上）。

#### Scenario: SC-RRL-003

- **GIVEN** 改后的 `runner.go`、`runner_code.go`、`runner_requirement.go`、`runner_requirement_entry.go`
- **WHEN** 人工评审 diff 与全文搜索 `pg_advisory_lock(`
- **THEN** SHALL 前三个文件不再包含阻塞式 `pg_advisory_lock(`，三处都调用 `withRunLock`；`runner_requirement_entry.go` 仍使用原等锁点且无改动
