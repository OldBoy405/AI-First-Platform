# Spec: workspace-delete-execution-tables

> Change: 2026-11-12-fork-ci-test-evidence-trust（最新修订并入 2026-11-13-aifi-45-real-execution-closure） | Auto-generated Human View

## Requirements

> 修订 2026-11-15（change 2026-11-13-aifi-45-real-execution-closure）：SC-WSD-005 取代「command 半句保持红灯」的条款，SC-WSD-006 新增删除与写入并发的交错保证及 workspace 行锁强度。

### Requirement: 19 张 cr_execution_* 表按 D2 策略登记并有行为测试；删除路径只删 notice 与 dispatch_root，保留类保持不变；不得仅改清单。

#### Scenario: SC-WSD-001

- **GIVEN** 一次性库已迁移到最新，清单新增 retain 分类并按设计逐表登记，
- **WHEN** 运行 TestWorkspaceDeletionManifestCoversPublicSchema 与 retain 分类断言。
- **THEN** SHALL 公共 schema 中每张表有且仅有一个分类，19 张 cr_execution_* 表分类与设计一致；retain 表 SHALL 有禁 DELETE 触发器且无指向 workspace 的外键；既有规则 SHALL 不变（KEEP 不带 workspace_id，DETACH 与 SETTLE 带 workspace_id）；SHALL 在一次性库真实执行且 skip 为 0。
- **AND** 删去任一登记或回退 retain 断言 SHALL 使测试变红。

#### Scenario: SC-WSD-002

- **GIVEN** workspace A 与 B 各有 19 张表中每类至少一行，
- **WHEN** 真实 DeleteWorkspace(A)。
- **THEN** SHALL A 的 cr_execution_notice 与 cr_execution_dispatch_root 行被删除；B 的同表行及 B 的全部其他行 SHALL 不变。
- **AND** 删除步骤 SHALL 在既有事务内（追加到 deleteSteps）。
- **AND** SHALL 除补 TRUNCATE 守卫的迁移 649 外不新增迁移、不新增触发器例外（不得为 append-only 触发器开任何删除例外）、不改 sqlc 查询；649 SHALL 只加语句级 TRUNCATE 拒绝、复用 cr_execution_binding_issue 与 cr_execution_consumption 各自已有的 append_only 函数，并 SHALL 配套 down 迁移。

#### Scenario: SC-WSD-003

- **GIVEN** 同上，A 有 retain 类与 keep 类行，
- **WHEN** DeleteWorkspace(A) 之后。
- **THEN** SHALL retain 类 A 行逐字节不变（含 digest 列）；keep 类行 SHALL 不变；对 retain 表的普通 DELETE 与 TRUNCATE SHALL 仍被触发器拒绝。

#### Scenario: SC-WSD-004

- **GIVEN** 删除事务在追加步骤之后的某一步失败，
- **WHEN** 事务回滚。
- **THEN** SHALL A 的 notice 与 dispatch_root 行恢复，且 A 的其他行未被半删。

#### Scenario: SC-WSD-005

- **GIVEN** workspace A 已删除，其 contract_selection 行按保留策略仍存在；生产消费路径使用的是由 workspace 与 CR 派生、没有 selection 行的 lineage。
- **WHEN** 经现有创建路径为该 workspace 新建 reservation，或经 ApplyControlCommandTx（包含生产消费入口）新建 command。
- **THEN** SHALL 两半句都被拒绝；command 半句由已声明的红灯转为满足，TestWorkspaceDeletionRefusesNewCommand 的断言 SHALL NOT 放宽、改名或删除。
- **AND** ApplyControlCommandTx 的 workspace 归属 SHALL 由调用方的已认证 workspace 提供，SHALL NOT 由 ReservationID 反推（生产中它是消费回执 id）；不改命令签名与 schema。
- **AND** SHALL NOT 实现 command 与 cursor 的收敛转移，不删除保留的历史行。
- **AND** reservation 半句与 command 半句仍各自独立成测试函数。
- **AND** ApplyControlCommandTx 收到已删除或不存在的 workspace id SHALL 以 ErrReservationWorkspaceGone 拒绝；未提供 WorkspaceID SHALL 以 ErrControlStoreInvalid 拒绝。
- **AND** 本场景取代原 SC-WSD-005 中「command 半句保持红灯、登记为已知失败」的条款；红灯登记的取回点保留在归档中，不改写。

#### Scenario: SC-WSD-006

- **GIVEN** reservation 或 command 的写入与同一 workspace 的删除并发。
- **WHEN** 分别取两种交错：写入先取得 workspace 锁，删除先取得 workspace 锁。
- **THEN** SHALL 删除之后不留下新的 reservation、command、cursor、verdict、settlement 行：写入先到则删除等待写入提交，删除先到则写入得到 no-row 并回滚。
- **AND** 加锁顺序固定为 workspace → claim → head → lineage → cursor，不出现反序死锁。
- **AND** 探针不用固定 sleep 决定先后，等待 DB 锁状态须有 deadline；重复 reservation 的既有幂等行为不变。
- **AND** 保留证据与消费回执契约不变；不新增外键、级联或后台补偿。
- **AND** 写入侧对 workspace 行只取 FOR KEY SHARE：对该行的 FOR UPDATE（删除）SHALL 被阻塞，普通 UPDATE（如 issue_counter 递增）SHALL NOT 被阻塞。
- **AND** 生产消费入口 SHALL 在 claim 与 head 加锁之前持有该锁；该顺序由生产 handler 保证并被独立测试，不只由 store 函数保证。
