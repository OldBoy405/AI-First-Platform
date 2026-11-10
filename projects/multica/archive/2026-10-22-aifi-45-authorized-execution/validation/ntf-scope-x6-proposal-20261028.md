# X6 通知去重范围 — 待强审设计提案（2026-10-28）

> 以下为当时只读调查与方案的原样归档，是**待强审的设计提案，不是已实现或批准**。旧格式守卫涉及可用性及部署防混跑，旧行保守阻断和迁移 down 均有权衡；不得据此声称 NTF-006 已满足。下文“本次仅静态分析”指归档前的调查快照。

## 范围与当前事实

本方案只解决 **X6 身份和兼容**，不接 Runner、恢复调度或真实广播，也不宣布 NTF 生产可用。

- 当前 `server/internal/governance/execution_notice.go:69–81,130–135` 没有 project 字段；v1 键只含 CR、cause、evidence、audience，recipient 不在键中。
- 仓内直接调用者：`BuildNotice` 由 `DeliverNotice` 和 `execution_notice_test.go` 调用；`DeliverNotice`、`RecoverPendingNotices`、`ResolveNoticeRecipient` 的外部调用目前仅在该测试文件。`NoticeDedupeKey` 只有 `BuildNotice` 调用。**仓外调用者及实际部署情况未知**。
- `646_cr_execution_notice.up.sql:10–29` 的旧行不保存 project、recipient 或 evidence 原文。recipient 可能从同 workspace、同 ID 的 `inbox_item` 读取；**无法仅凭旧 hash 反推出 evidence 或历史 project**。
- `433_aifirst_cr_projection.up.sql:13–26` 的 CR 通过 shell issue 间接关联 project；`execution_authorization_revoke.go:204–211` 查询的是**当前** issue/project，不能证明旧通知创建时的 project。`648_cr_execution_control.up.sql:29–45` 的 selection 也不能单凭同 CR 证明旧 notice 属于某个 selection。

## 最小迁移与兼容方案

### 1. 扩展，不改 646

新增后续编号迁移，暂称 `server/migrations/649_cr_execution_notice_scope.{up,down}.sql`；实施前重新核编号和部署清单。**无论本地历史说什么，646 一律视为可能已部署，不原位改写。**

- 在原表追加 nullable `project_id`、`recipient_id`，必要时追加 v2 证据摘要；旧行保持 NULL，原 notice ID、Inbox ID、键和状态不改。不新增 FK/cascade。
- 保留 `(workspace_id,dedupe_key)` 唯一索引。v2 键使用与旧 64 位十六进制值不相交的 `v2:` 前缀，散列版本化、无歧义编码的 `(workspace, project, CR, cause, evidence, audience, recipient)`；UUID 先解析为规范值，拒绝缺失及非法值。冲突回读时核对保存的身份，不能仅凭 hash 返回另一条记录。
- 保留旧 `NoticeDedupeKey` 的 v1 行为作为兼容计算；新增明确命名的 v2 函数，避免静默改变已有导出函数语义。`NoticeEvent`、`BuildNotice`、`DeliverNotice` 和直接测试调用者同步适配；静默事件仍不写 Inbox。

### 2. 旧行保守归属

**不做自动 project 回填，也不按当前 shell issue、唯一 project 或最近 selection 猜测。**

对新事件，先按 workspace + CR 检查旧行，并核对应 Inbox 的 workspace、类型和 recipient：

| 旧行情况 | v2 行为 |
|---|---|
| 同 CR、同 recipient，历史 project 未证明 | **阻断并报告待人工/可信证据对账**；不复用旧 ID，也不新发。即使新 evidence 不同也暂阻断，因为旧行没有可验证的 evidence 原文。 |
| 同 CR，旧 Inbox 可验证且 recipient 不同 | 可为新 recipient 创建 v2；不修改或转移旧 Inbox。 |
| Inbox 缺失、跨 workspace、类型/recipient 不可信 | 阻断该 CR 的新投递并报告异常，不猜归属。 |
| 未来取得能**直接关联该 notice 创建时身份**的可信证据 | 另行审阅对账机制，再决定是否建立可追溯的归属；当前切片不自动认领。 |

这有明确的可用性代价：旧 project 未知时，同 recipient 的新失败/新证据可能暂被阻断，**不能宣称已满足 NTF-006**。旧 pending 保留原状态与 ID；现有恢复函数会扫描旧 pending，后续接调度前必须隔离或审查旧行，不能自动把不明归属广播出去。

### 3. 防混跑与回退

仅加字段不够：旧二进制仍会写 v1，可能与 v2 并存并重复提醒。建议迁移增加 **只针对 INSERT 的数据库守卫**：新插入必须具备 v2 键及完整 project/recipient；旧行的状态更新仍允许。这样迁移后旧写者**明确失败关闭**，不是兼容混跑。上线前仍须停/排空旧写者并核实；迁移本身不启用通知。

回退不能简单删列：已有 v2 行后会丢身份，旧写者也无法正确去重。`down` 应在存在 v2 行时明确拒绝、保留数据；恢复采用前向修复。无 v2 行时的受控回退另测。测试需考虑 `execution_control_migration_test.go:625` 现有旧格式直接插入夹具：它应在升级前种入，不能为了让测试通过放宽守卫。

## RED → GREEN 测试计划

建议新增 `server/internal/governance/execution_notice_scope_test.go`，在现有 `execution_notice_test.go` 调整直接调用与 fixture；迁移测试单独覆盖旧 schema 升级，不复用会删除 643–647 表的整组往返测试。

1. **纯函数 RED**：相同输入稳定；仅改 project 或 recipient 键不同；不同 workspace/CR/evidence/audience 不互吞；UUID 等价表示一致；缺值、歧义编码被拒。固定 v1 向量证明旧算法未漂移。
2. **真实隔离库 RED**：先按旧 646 种 delivered、pending、不同 recipient、缺失/跨 workspace Inbox 行，再应用新迁移。断言原 ID、状态、内容不变；同 recipient 未知 project 阻断，不同 recipient 可新建；坏关联阻断。测试须验证**无广播及零意外新增行**。
3. **并发与混版**：相同 v2 并发只有一个 Inbox；不同 recipient/project 各一条；模拟旧写者在迁移后的 INSERT 被拒，旧 pending 状态更新仍可执行。用确定性 barrier 验证，而非仅计最终行数。
4. **生命周期**：空 v2 时 up/down/reapply 保留旧行；有 v2 时 down 被拒且所有数据不变。验证新旧键冲突、丢响应重试和冲突回读的完整身份。
5. **回归**：已有 NTF 组件测试适配后复跑；故障注入只用记录器，不接真实 bus。上述结果只证明 X6 组件，不证明生产接线或完整业务 TC。

## 执行权限

用户已授权专用可丢弃实例；**不需重新索取泛泛授权**。未来实际执行仍须通过 `scripts/aifi45-db/README.md` 和 `run.mjs` 的现行身份、nonce 受限角色、串行、原库保全及精确清理门禁；原库 HOLD 不解除。迁移列表须根据实际 schema 快照显式核对，零选中或 skip 不算通过。

本次仅静态分析：**未改代码、未运行测试、DB 或容器，未发送通知**。
