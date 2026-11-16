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
<!-- merged 2026-11-16 from 2026-11-16-multica-execution-evidence-closure: appended SC-MEC-001/002; original requirements preserved -->

### Requirement: 三个恢复入口仅在锁后活动 run 的 ID 等于已取锁 ID 时推进；对象消失或切换时本次无效果返回。

#### Scenario: SC-MEC-001

- **GIVEN** 一次性迁移库；architecture/requirement/code 三个入口各有合法 A；独占 Runner 池上限 4；控制连接持 A 锁，恢复调用已完成锁前查询并进入取锁路径
- **WHEN** 分别保持 A 不变、使 A 终态且创建同归属合法 B、使 A 终态且无后继；changed 情形另持 B 锁再释放 A，随后另一次恢复并释放 B
- **THEN** SHALL unchanged 推进 A；changed 的第一次恢复返回且 B 的节点/任务/状态不变，第二次恢复等待 B 锁后推进 B 恰好一次；no-active 无效果返回
- **AND** 三种入口均走原生产恢复函数、原 digest/admission 与假 enqueuer；不加生产 hook，不以替身身份判定函数代替
- **AND** B created_at 使用明确顺序；architecture 至少三次、requirement/code 至少两次 Runner 独占池新增获取证明交错已达取锁边界，全部等待有 deadline
- **AND** 换目标不增加业务 attempt、不将 B 标为 failed；下一次既有唤醒负责恢复，不承诺同次立即推进
- **AND** 非 ErrNoRows 的查询错误与 digest 错误继续传播；writeback 和 requirement 创建锁不被扩大修改

### Requirement: 保持现有同 run 串行、释放、取消、等待不占连接，以及池 4 并发唤醒只派发一次的保证。

#### Scenario: SC-MEC-002

- **GIVEN** 同一次 governance-run-lock selection 包含两个原锁测试、TestReconcileRunIdentity 与 TestMTick003，带 race，governance TestMain 的池上限为 4
- **WHEN** 经既有 run-selection 执行与精确对账
- **THEN** SHALL 四个顶层测试完整通过，pass=4/fail=0/skip=0；同 run 回调最多一个并发进入、取消返回 ctx.Err、等待不占用持锁者需要的连接、释放后可再次进入
- **AND** TestMTick003 派发任务数和 run 任务数恰好为 1，首节点 attempt 为 1；不改既有断言
- **AND** 新身份测试内部用普通表循环，不产生名单外子测试事件；runner 本轮只执行这一个 selection，不重复运行原 governance-mtick003 入口
