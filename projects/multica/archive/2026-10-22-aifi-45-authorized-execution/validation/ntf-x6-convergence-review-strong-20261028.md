# X6 向规范收敛方案 — STDD strong 独立只读审阅归档（2026-10-28）

> 本文归档对 `validation/ntf-x6-canonical-convergence-20261028.md` 的 strong 只读审阅原文。**审阅只针对 sha256 `d45ace60bb95eb9b9097783ebe62fa45ccbd9abdc7a9db69ffd853940ca85006` 版本**；作者可能已开始修订，**本文不默认复核任何新版**，新版须另行审阅。归档时（写入本文前）重算该文件 sha256 仍为上值，但不据此推断后续内容。
> 审阅期间**未改文件、未运行测试、未访问 DB/容器、未发送通知**。凡涉及 PostgreSQL 行为（隔离级别回读可见性、ON CONFLICT 对 INVALID 索引的推断、REVOKE 与 owner、锁语义）的判断，均为**依 PG 语义的推断，未实测**；标“已核”者为静态读源确认。所列修订均为**建议**，不是验证结论。

## 1. 审阅对象与源 SHA

| 对象 | 值 |
|---|---|
| 被审文档 | `validation/ntf-x6-canonical-convergence-20261028.md`，sha256 `d45ace60bb95eb9b9097783ebe62fa45ccbd9abdc7a9db69ffd853940ca85006`（87 行） |
| multica 源仓 | `C:/Users/GOBAO/Downloads/AI/multica`，`main` HEAD `81e5293adc758e392a045026cf81ec5cc1bac72d` |
| `server/internal/governance/execution_notice.go` | 工作区 blob `22749eafb6d75144bf2f87775f4467538914b4cd`（与前轮相同；HEAD blob `8d6bcce4c0bce4b1be770896e93998ed9f63152e`） |
| `packages/` | 审阅时无未提交改动 |

**非 X6 改动**：`execution_notice.go` 工作区差异为另一作者的广播依赖改动（broadcast/loader 必需、item id/workspace 校验），不视为 X6，也不作为 X6 证据。

## 2. design §5 符合度

- **符合**：选择 `inbox_item.details` 承载身份；partial UNIQUE 列为 `(workspace_id, recipient_type, recipient_id, details->>'execution_notification_key')`，独立 CONCURRENTLY 迁移；`execution_delivery` 置于 details；停止把 `cr_execution_notice` 作为新路径权威存储。已核：服务端当前无任何代码写 `execution_notification_key`/`execution_delivery`（仅客户端读取及前端测试夹具使用），建索引前无历史重复风险。
- **缺口**：§5 要求“同一事务持久化运行通知引用与 Inbox 记录”，文档只说“既有 run/node 通知引用”，未指明目标表/列。已核可用的 JSONB 有 `pipeline_run.execution_context`、`pipeline_node_run.detail`（`585_aifirst_pipeline_runs.up.sql`），但授权执行是否落在 pipeline_run 未核。该点未定，§5 的同事务引用无法验证。

## 3. Blocking（六项）

### B1 广播载荷缺 details，客户端把每次重投当新提醒（已核）

- 客户端 `packages/core/inbox/ws-updaters.ts:40-56` 仅凭 `item.details.execution_notification_key` 识别新策略行；缺该字段即按旧行“总是 claim”并弹横幅。
- 服务端广播载荷由 `LoadInboxItem`（`execution_notice.go` 约 422–458 行）构造，SELECT **不含 details**。因此至少一次重播、pending 恢复每次都会弹横幅，违反 §5“消费者按 Inbox ID 幂等、不新增主动提醒”。
- 客户端“已弹”标记作用域为当前 QueryClient 缓存；客户端重建（刷新/重启）后恢复重投会再次弹出。文档需明确接受或给出非缓存方案。
- 最小修订：广播载荷必须携带 details 中的 key（loader 回读并校验）；端到端测试“同 Inbox ID 重投两次仅一次横幅”；写明客户端重建后的行为。
- 注：广播在 commit 之后、客户端收到 `inbox:new` 后重拉列表，“inbox 提交前不通知”语义成立。

### B2 旧恢复器不能靠“受控更新”隔离（顺序已核，后果为推断）

- 旧 `RecoverPendingNotices` 先广播、后 UPDATE（约 366–375 行）。文档“旧状态更新通道也必须受控”若以守卫拒绝 UPDATE，广播已经发生，行仍为 pending，下一轮再次广播，形成**无限重播**。
- 旧 `DeliverNotice` 先 INSERT 旧表（约 271 行）后 INSERT Inbox（约 304 行），因此旧表 INSERT 守卫对旧投递有效。
- 最小修订：删除 UPDATE 守卫表述；改为让旧代码**在广播前失败**——例如新迁移重命名旧表或撤销应用角色对旧表的 SELECT（应用角色是否为表 owner 未核，若是则 REVOKE 无效），或以二进制/副本清点作为上线硬前提。

### B3 新默认恢复路径不完整

文档已正确要求只处理合法 v2、恢复前复核授权、旧 pending 不交给新恢复器，但缺：

- (a) pending 位于 `details->'execution_delivery'->>'status'`，无对应 partial 索引，`inbox_item` 为热表时恢复扫描将全表扫；
- (b) 多副本抢占（`FOR UPDATE SKIP LOCKED` 或租约）及崩溃释放——文档仅写“需明确”；
- (c) 授权撤销/复核失败的 pending 去向：§5 状态仅 `pending|delivered`，新增终态需 ADJ，否则永驻 pending、每轮重试/告警；
- (d) 每个 workspace 由谁调度恢复。

### B4 先筛后 insert 的语义漏洞

- 已核：现有 `CreateInboxItem`（`pkg/db/queries/inbox.sql` 约 92–106 行）以 `WHERE EXISTS member` 静默跳过（返回 ErrNoRows）。若复用或仿写并加 `ON CONFLICT DO NOTHING`，“成员不存在”与“已存在”无法区分；必须使用专用查询，回读不到即失败关闭，不得当作幂等成功。
- 推断：冲突后回读依赖 READ COMMITTED（每语句新快照）；REPEATABLE READ 下可能看不到冲突行，文档须固定隔离级别。
- 推断：ON CONFLICT 推断不选用 INVALID 索引，缺有效索引时直接报错；除上线顺序外，新代码应在启动时检查 `indisvalid` 并失败关闭。
- “同 CR 同 recipient 旧行”检查只有在旧表 INSERT 守卫已生效、旧集合被冻结时才无需加锁；须写明此前提及守卫生效前禁止混跑。

### B5 CONCURRENTLY 索引的 invalid 清理与 down 机制未写对（迁移器已核）

- up：须登记 `server/cmd/migrate/main.go` 的 `concurrentIndexCleanups`（约 142 行；注释称映射“total”，并有测试逐项对照迁移文件）。
- down：down 为单语句、非事务的 `DROP INDEX CONCURRENTLY`，SQL 文件中不能放拒绝检查；“存在 v2 拒绝回退”必须实现为挂在**索引迁移版本**上的 `preRollbackHooks`，以便在删索引之前拒绝。文档“登记对应 down hook”混淆了 invalid 清理与拒绝回退。
- 未核：多迁移文件在 down 方向的执行顺序。

### B6 project/CR 与 recipient 的可信来源未指名

- project/CR 候选（已核 schema）：433 投影 `UNIQUE(workspace_id, cr_id)`，但 project 经当前 shell issue 间接得到（可变的当前态）；648 `cr_execution_contract_selection` 有 `UNIQUE(workspace_id, project_id, cr_id)`、注释“never updated”，可经 lineage 绑定。文档只写“可信生产者给出”，未定来源，也未说明无 selection 的 CR 如何处理（即无法发 v2，影响可用性）。
- recipient：文档正确指出 `ResolveNoticeRecipient` 与 `CreateInboxItem` 仅校验成员；但授权者事实来源与维护责任配置在仓内均不存在，失败关闭意味着 NTF-002/003/004 当前不可用。须在实施前指名具体来源。

## 4. 非阻断但须写明

- 已核 FK：`inbox_item.issue_id` 为 `ON DELETE CASCADE`。新通知若挂 issue，issue 删除会连带删除去重身份与待恢复记录，重放将产生新提醒；建议 `issue_id` 置空或明确接受。
- 已核：`ListInboxItems` 返回 `i.details`，身份字段会下发客户端，只宜存摘要与必要 ID。
- 旧 pending 的“隔离”仅指不广播，其 Inbox 行仍出现在用户列表中，应写明。
- 可信失败发生身份缺来源，且同 recipient 旧行阻断，SC-NTF-006 仍不能宣称满足（文档已自认，结论正确）。

## 5. 最小修订清单（建议）

1. 广播载荷携带 details key，并有端到端单次横幅测试；写明客户端重建行为。
2. 删除“旧状态更新受控”；改为广播前隔离旧恢复器（重命名/撤销 SELECT，或二进制清点作硬前提）。
3. 新恢复器：pending partial 索引、SKIP LOCKED/租约、撤销终态（需 ADJ）、调度归属。
4. 专用 insert + 冲突回读查询，固定 READ COMMITTED，启动检查 `indisvalid`；写明旧行检查依赖守卫冻结。
5. 登记 `concurrentIndexCleanups`；以索引迁移版本上的 `preRollbackHook` 实现“有 v2 拒绝回退”。
6. 指名 project/CR 来源（建议 648 selection 经 lineage 绑定）、授权者/维护者来源，以及 run/node 通知引用的目标表/列。

## 6. 未核与限制

- PG 隔离级别回读可见性、ON CONFLICT 对 INVALID 索引的行为、REVOKE 对 owner 的效果、锁语义：推断，未实测。
- 应用 DB 角色是否为旧表 owner、迁移 down 文件顺序、授权执行是否使用 pipeline_run：未核。
- 646 是否已部署于共享/生产实例：未核（禁止访问 DB/容器）。
- 本文不改任何源码、迁移、design、canonical、被审文档或此前提案/审阅文件。
