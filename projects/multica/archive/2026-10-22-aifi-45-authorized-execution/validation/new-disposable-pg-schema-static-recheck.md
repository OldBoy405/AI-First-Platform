# 新 disposable PG：schema 与 fixture 静态复核

独立只读调查请求 strong `GBClaude/claude-opus-5-5:high`，actual backend 无回执；审阅者未执行命令，未创建或连接容器/数据库，未读历史事故库、环境或凭据，未运行迁移和测试。协调者另行只读核对相关源码，以 Node 读取 sibling multica 的 migration 文件名并计算清单摘要。结论均限定为调查时未冻结源码的静态事实，不证明新基线可用、旧基线等价或任何具体变更已批准。后续用户已选择 A 方向，原 Gate2 无已核实的 BUILD 中途重开入口；B4 重大偏离及当前状态见 `new-disposable-pg-gate2-draft.md`。

## 本轮输出失误

后续核对迁移器重试源码时，协调者截取函数调用的相邻行，工具输出意外包含源码里的示例默认数据库凭据；未读取实际运行环境、容器或事故库，也未连接数据库。已立即向用户披露，不在本文重复凭据。后续只输出经过敏感字段过滤的源码行，不输出连接字符串及上下文；这不改变现有 HOLD 或测试授权。

## 结果

1. `server/internal/migrations/migrations.go` 从有序 `.up.sql` 文件生成完整 migration ID 集合；`ExtractVersion` 取去掉 `.up.sql`/`.down.sql` 后缀的 **basename**。重复数字前缀不是完整 ID 相同，不能只比数字最大值或账本行数。协调者用 Node `fs.readdirSync` 读取 sibling `multica/server/migrations`，筛选 `.up.sql` 并以 JS 默认字符串顺序排序：当前磁盘 677 个文件，数字前缀不超过 642 的 671 个。文件名以 UTF-8、LF 分隔且末尾附 LF 的清单 SHA-256 为 `d72aed85245e5a3ef2244420385e11658fe946d5ae5f02a08e628a0b97d5d001`；这不是逐文件内容或完整源码快照的摘要，也不是历史库账本事实。
2. 新集群**候选**可使用入库的完整 migration、同快照正式 `cmd/migrate` 与自建 fixture 从空库建立；`cmd/migrate` 的 hooks/conditions、账本和 `taskusagebackfill` 的空历史路径都不能用逐个执行 SQL 代替。静态存在这些文件不证明全链一定成功或与旧 schema-only clone 等价。
3. `server/internal/governance/execution_control_migration_test.go` 的 `TestChannelMigrationAfterUp` 和 `AfterReapply` 检查 648 对象存在/形状，`AfterDown` 检查不存在；Reapply 测试本身不证明此前确实 down。`TestChannelMigrationProtectedData` 在 643–647 业务表自建行并执行 648 down/up，未看到它清理这些行；不得误称插入 `schema_migrations`。`TestExecutionMigrationDownRoundTrip` 的注释以 schema-only clone 为前提，实际逻辑要求 643–647 已 up，测试期间 down/up 这些对象；它只比较旧表 `agent_task_queue`、`cr`、`approval_record` 的行数，未自建旧行 fixture。各调用的实际选择和初态须单独冻结、隔离，不能把冲突默默改成 skip；历史广选择是否包含上述阶段测试尚未确认。
4. `server/internal/handler/workspace_delete_manifest_test.go#TestWorkspaceDeletionManifestCoversPublicSchema` 比对 public schema 的**表**与清单，并检查 workspace_id 分类；它不检查索引或函数。清单静态上没有 `cr_execution_*` 条目；若测试被选中、testPool 可用且 643 表在迁移后仍存在，测试逻辑将报告 unclassified。所知历史 handler 选择锚点之一 `^TestStartClaim` 不选中此测试；test-plan 另要求相关完整包回归，其选择范围尚需核实。尚未运行数据库确认。不得仅为绿测补清单：各表真实删除/保留策略和清理顺序须另审，改测试须遵循适用授权及 `multica/CUSTOM.md` 登记。
5. 642 的 `ADD COLUMN` 和 643–648 的 `CREATE TABLE` 无 `IF NOT EXISTS`。若完整迁移后的库已包含相应对象，重放对应 SQL 预期会报重复对象错误，尚未实测。已查历史调用含 643–648；是否含 642 未确认。原选择与状态必须冻结并重新评审，不能照搬。
6. 正式迁移入口、handler TestMain 及 service 的 `openSharedTestPool` 等路径在缺失 URL 时有默认连接回退；handler 数据库不可达时 TestMain 还可能 exit 0，service 有其他测试级回退路径。governance 当前缺 URL 会失败，但其 TestMain 不足以证明实例归属。入口必须在启动任何迁移和 Go 测试前核验目标身份和 URL，且不能触及旧默认库。
7. 旧 `scripts/aifi45-db/run.mjs` 固定旧实例身份并读原库；参数里的逐文件迁移不自动执行正式 runner 的完整 hooks/conditions。替代实例或入口需按 AIFI-45 的 STDD BUILD B4 重大偏离流程记录并取得具体变更决定，不能仅把 URL 指向新库；原 Gate2 不能伪称重开。
8. 正式 `cmd/migrate` 只有 up/down 方向，不提供选择单个版本的机制；down 按倒序处理已登记的迁移，不能用于只回退 648。直接执行 648 down SQL 不会更新 `schema_migrations`，会使该 nonce DB 的账本与实际对象不一致；按账本核验的迁移完整性检查可能因此误判。是否允许此受控初态或设计经批准的目标版本能力须人类决定，不能静默用于 readiness 验收。

## 保持未决

完整迁移链实际结果与 extension/角色/权限、历史版本集合与新链兼容、测试所需旧行 fixture、共享测试数据隔离、原广选择与多种初态、真实进程树退出和精确清理，均不能由这次静态复核证明。不得连接事故库取证，也不得用 fake-I/O、跳测试、造账本或关闭 readiness 替代这些证明。详见 `new-disposable-pg-gate2-draft.md`；A 方向已选，具体设计、B4 登记、资源与执行计划仍待处理。
