# Spec: workspace-delete-execution-tables

> Change: 2026-11-12-fork-ci-test-evidence-trust | Auto-generated Human View

## Requirements

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

- **GIVEN** workspace A 已删除、其 contract_selection 行按保留策略仍存在（D2「命令禁新建」半句），
- **WHEN** 经现有创建路径为该 selection 新建 reservation 或 command。
- **THEN** reservation 半句 SHALL 被拒绝，本 change SHALL 在 CreateReservationTx 内加 workspace 存在性检查使其成立；command 半句经探针实测当前代码放行，按 U3 用户裁定（R5）不在本 change 内修复，SHALL 保持探针断言原样（红灯即为已声明的发现），SHALL 登记为可找回的已知失败并指向后继议题，不得静默放宽断言、不得改触发器、不得把红灯洗成绿灯。
- **AND** 本 change SHALL NOT 实现 command 与 cursor 的收敛转移。
- **AND** 两个半句 SHALL 各自独立成测试函数，使 reservation 半句可独立绿、command 半句可独立红。
- **AND** command 半句的登记 SHALL 能被 test-ownership check 与归档后的基线规格找回。
