# X6 向规范收敛方案

> **状态：待强审修订草案，NTF 未就绪；非实现、评审通过、审批、验收或部署承诺。** 本稿依据用户转达的 strong 第二轮反馈修订；[收敛方案 strong 独立报告](ntf-x6-convergence-review-strong-20261028.md)仅审阅 SHA-256 为 `d45ace60bb95eb9b9097783ebe62fa45ccbd9abdc7a9db69ffd853940ca85006` 的旧版，[旧提案 strong 报告](ntf-scope-x6-review-strong-20261028.md)审阅的是旧提案，两份报告原样保留，不冒称任何报告已复核或批准本修订。本文不覆盖原 X6 提案、旧报告或待办 B 旧决议，也不替代现行规范和审批流程；不创建未经批准的 ADJ，不宣称规范改变。源码路径以 sibling `multica` 仓库根目录为基准，作为定位说明而非相对于本 Markdown 的链接。以下仅为静态设计，未实测数据库或事务语义；标为 **hard blocker** 的事项未解决前不得实施上线或宣称规范满足。

**结论：选择 `inbox_item.details` + partial UNIQUE，停止把 `cr_execution_notice` 作为新通知的权威存储。** 646 的部署事实未知，按可能已部署处理：不改写、不删除原迁移及旧表。以下是待评审设计，不是实现、审批或验收结论。

## 1. 冲突及取舍

- 现行 [`design.md` §5](../design.md) 明确要求在既有 Inbox 的 `details` 保存键和投递状态，并用 partial UNIQUE；[canonical REQ-NTF-003](../canonical/specs/code/attention-routing.yaml) 要求复用执行和 Inbox 身份、不新增全局去重账本。
- [X6 提案](ntf-scope-x6-proposal-20261028.md) 延续附表、增加字段和 v2 键；[待办 B 的 X6](backlog-b-disposition-20261026.md) 则记录了“原位改未上线 646”。前者未获批准改变 §5 的存储方案；后者的“未上线”前提现在不能成立。**两者均不能作为重写 646 或继续使用附表的授权。**
- 旧表保留为**历史遗留数据和对账输入**，不接收新通知、不做新路径权威账本。现有 `execution_notice.go` 确实以旧表写入、扫描 pending；切换必须替换写入和恢复路径，而非只改键。

## 2. 新身份和事务

### 2.1 身份

由可信生产者给出稳定事实，编码以下字段：`workspace UUID、project UUID、CR 标识、通知类别/原因、稳定失败事件或 root 身份、规范证据摘要、audience、recipient 类型和 UUID`。

- UUID 先严格解析为 16 字节，拒绝空值和 nil UUID；CR 目前是文本，按其权威合同校验和规范化，**不假设它是 UUID**。枚举闭集；证据摘要带算法和固定长度。
- 使用域分隔版本（如 `execution-notification/v2`）和逐字段类型、长度前缀编码，再 SHA-256；禁止简单分隔符拼接。`details.execution_notification_key = "v2:" + hex`；同时保存可核验的规范身份，冲突回读时逐项比较，不仅比较 hash。
- **新失败不能只靠 cause + evidence 判新旧**：生产者须提供可信、持久的失败发生身份。重放及跨 commit 使用同一身份；真正的新失败即使 cause 和证据相同，也使用不同身份。不能以重试次数、当前时间或日志文本制造新身份；事实不足时停止并告警，而不是猜测。
- **Hard blocker — 可信 scope 来源**：须在真实入口确定 workspace、project、CR、事件及 recipient 的权威来源和校验者，证明 project 属于 workspace、CR 属于该 project，且这些事实对本次事件有效；multi-project 不能通过 CR 名或当前 issue 唯一性猜测。`server/migrations/433_aifirst_cr_projection.up.sql` 的 CR 经 `shell_issue_id` 关联 issue，`server/migrations/585_aifirst_pipeline_runs.up.sql` 的 run 没有直接 project 列；这些结构本身不证明历史或当前业务授权。来源、变更/撤销与检查线性化点未定，不能凭输入参数或当前 membership 填为可信事实。

### 2.2 Inbox 唯一性与恢复

新迁移建立：

```sql
CREATE UNIQUE INDEX CONCURRENTLY <name>
ON inbox_item
  (workspace_id, recipient_type, recipient_id,
   ((details->>'execution_notification_key')))
WHERE details->>'execution_notification_key' IS NOT NULL;
```

写入时要求 key 为非空、符合 v2 格式；上线前检查已有该字段的无效值和重复值，不能静默跳过。冲突处理使用与索引**完全一致的表达式和谓词**：`DO NOTHING` 后读回并校验身份；不可把其他唯一约束冲突当成幂等成功。**每个通知写入/恢复副本启动、重启及加入服务前**都必须检查其连接的目标库中去重唯一索引和 pending 索引：表、唯一性、表达式、谓词与预期一致，`indisvalid` 和就绪状态均满足要求；缺失、INVALID、不匹配或无法核验时该副本的通知写入及恢复失败关闭并告警。不能只依赖迁移一次性检查、索引名称或迁移版本；索引后续丢失/失效的检测与停止合同也须评审并测试。

- **专用 Create 路径（待实现与实测）**：`server/pkg/db/queries/inbox.sql` 的现有 `CreateInboxItem` 是成员/agent 存在性 `INSERT … SELECT`，缺收件人静默 `ErrNoRows`，没有冲突处理；不能把它直接当作已满足 X6 的写入。新增专用 SQL/生成物及服务入口，显式区分收件人/授权失效、真实插入、目标 partial UNIQUE 冲突和其他错误。提议使用明确指定的 **READ COMMITTED** 事务，`INSERT … ON CONFLICT` 指定匹配的索引推断目标并 `DO NOTHING RETURNING`；无返回时以**后续独立 SELECT 语句**按完整唯一目标回读，再校验 workspace、project、CR、事件、evidence、audience、recipient、Inbox 类型和状态。不要在同一语句的 CTE 中假定能看到刚等待提交的冲突行。回读缺失、行被删/身份不符、索引不可用、事务隔离级别不符或其他约束冲突均不冒充成功：中止、有限重试或告警的精确合同须在实施前评审。PG 可见性和竞态结果必须在隔离 DB 验证，不能假称现已成立。
- 旧行检查和新插入之间也有竞态：在旧写者已实际排空且被挡住的前提下，同一事务内用经评审的 workspace+CR 级串行化协议覆盖旧行检查、授权与写入；所有相关新写者必须遵守相同锁顺序。锁粒度、哈希碰撞、超时、事务边界和死锁处理尚需实测，不把 partial UNIQUE 当作旧行检查锁。**Hard blocker：协议或排空证据缺失则不得启用。**
- **事务目标而非既有事实**：同一事务内写 Inbox（`details` 含身份、`execution_delivery.status=pending` 和稳定 Inbox ID）与既有 run/node 通知引用；提交后广播，成功后条件更新为 delivered。业务事实已提交时，通知失败不得回滚业务事实、重签、扣额或重派 writer。`server/migrations/585_aifirst_pipeline_runs.up.sql` 确有 `pipeline_run.execution_context` 和 `pipeline_node_run.detail` JSONB；但**尚未核定**哪一真实字段/路径保存通知引用、所有并发更新是否合并保留、事务是否能由通知入口拥有、run/node 是否可能消失。**Hard blocker：这些事实和失效处置须核实并测证，不得把同事务写入写成现状。**

### 2.3 新 pending 恢复、授权和工作区发现

pending 恢复目标仅扫描身份完整、合法 v2 Inbox，广播同一 ID；广播成功、标记前崩溃允许同 ID 再投，已 delivered 重放不广播，不宣称物理 exactly-once。实现需要为按 workspace、pending 状态和稳定排序/分页设计合适的**独立 CONCURRENTLY pending partial 索引**，经实际查询计划验证；不得假设 §2.2 的去重唯一索引足以支撑恢复扫描。对 malformed v2、缺状态、丢行和错误归属需隔离告警，不能静默跳过。每个并发索引独立文件并登记 cleanup，见 §5。

- **Hard blocker — 抢占及故障恢复**：确定多 worker 竞争、批次上限、公平性、claim 原子性、锁顺序/超时、进程崩溃后的释放与重试、广播成功后标记失败、并发重投及有界退避；覆盖原投递与恢复同时运行。可评估行锁或租约，但本稿不选未经验证的协议、不新增第三种投递状态；在持久状态仍为 pending/delivered 的前提下证明不丢、不创建第二 Inbox，标记仅对同 ID/期望版本生效。
- **Hard blocker — 授权变更**：每次实际广播之前核验该 recipient 对对应 scope 与动作当前仍有资格；须定义与撤权/成员移除竞争的线性化边界、可信授权源、超时和权限故障处理。撤权或无法核验时停止广播、保留未解决事实并告警，不伪造 delivered、不可自动改投其他人；是否取消、重新授权、换收件人及审计处置尚待批准。广播之前检查并不能自行证明跨系统撤权与实际发送原子。
- **Hard blocker — 触发/发现**：现有 `RecoverPendingNotices` 是按单个 workspace 参数扫描，不能据此假定全局工作区发现或调度已接线。明确启动扫描、周期触发、workspace 枚举/分页、创建或删除/权限变化、失败重试和延迟告警的可信入口；对全体目标 workspace 有覆盖证据，停用/未启用时显式报告，不接真实 bus 前不能声称生产恢复可用。

### 2.4 广播 payload、客户端和删除边界

`server/internal/governance/execution_notice.go` 的 `LoadInboxItem` 当前 SELECT/返回值不含 `details`；本次只读工作区中的 `BusBroadcaster` 校验 ID/workspace 后发送 loader 返回值。**该广播依赖及校验属于另一作者的当前未提交改动，不是 X6 改动或已交付证据**，以[强审报告](ntf-x6-convergence-review-strong-20261028.md)所记录的工作区/HEAD 差异为准，实施前须重核。`packages/core/inbox/ws-updaters.ts` 的 `hasExecutionNotificationKey` 依赖 `item.details.execution_notification_key`，缺失就走 legacy 路径。**Hard blocker：新 loader/广播契约须携带并验证非空 v2 key，测试真实 loader → bus → 客户端，不得只用手工 payload；仅暴露客户端需要的字段，完整身份或授权事实不能未经权限审查广播。** 同时校验 workspace、recipient/type 和 payload 的可信边界；Inbox 列表也会下发 `details`，因此持久身份仅存必要 ID/摘要并审查读取权限。

Web/desktop 的同 ID claim 在 `QueryClient` 缓存内，以 workspace+Inbox ID 标识，受缓存回收、刷新/重启、新 session、多个窗口/设备影响；OS tag 也不能证明跨生命周期绝不重复。`apps/mobile/data/realtime/use-inbox-realtime.ts` 的此入口只做列表/未读刷新，不能据此声称所有移动推送已幂等。**Hard blocker：产品须定同 session、刷新/重启、多窗口/多设备及各客户端的可见提醒保证与持久化/失效边界，给正反例和实际覆盖；规范要求的用户可见幂等未证实前不能宣称 SC-NTF-005/007 满足。** 同时验证静音/焦点、显示失败释放 claim、非 execution 旧行行为及 issue 聚合。

`server/migrations/001_init.up.sql` 中 `inbox_item.issue_id` 有 `ON DELETE CASCADE`：若 v2 行关联 issue，issue 删除会删除 Inbox、去重键和 pending，可能令同事件重发或丢待广播。**Hard blocker：必须审定 issue 关联/删除策略和持久身份、删除期间并发、丢行告警及恢复语义；不能仅靠引用或现有唯一索引解决。** 不预设应设 NULL、禁止删除或新增账本，逐方案与现行规范及产品可见性审查后再决定；测试 issue 删除前后、pending/delivered 和重放。

## 3. 旧数据、隔离与可用性

升级前对旧表及相关 Inbox 做只读盘点：按 workspace、CR、状态、Inbox 关联有效性分类；保留原 ID、内容、状态。**不根据当前 issue/project、selection、唯一 project 或当前 membership 回填历史 project。** 旧 hash 也不能反推出原 evidence。

| 旧记录情况 | 处理 |
|---|---|
| 旧 Inbox 同 workspace、类型与 recipient 可核实，但 project 未知 | 保留历史；同 CR、同 recipient 的可能重放进入隔离与对账，不复用旧 ID、不直接认定属于当前 project。 |
| 同 CR，所有相关旧 Inbox 关联可信且 recipient 不同 | 可为已授权的新 recipient 走 v2；不转移旧 Inbox。 |
| Inbox 缺失、跨 workspace、类型/recipient 异常，或旧行集合不完整 | 对受影响范围失败关闭，记录异常；不能仅因找不到匹配就放行。 |
| 旧 pending | **不由新恢复器广播，也不自动标 delivered**；隔离清单、数量、最早年龄和故障率告警。必须证明旧恢复器在广播前不可运行，不能仅靠限制旧状态更新。这里的隔离仅指广播：原 Inbox 行仍可能被用户列表读取，不意味着隐藏或撤回。 |

**Hard blocker — 旧恢复隔离的线性化点**：现有 `RecoverPendingNotices` 是先扫旧 pending、再调用 broadcast、最后 UPDATE；拒绝 UPDATE 时广播已发生，甚至可能重复，绝非隔离。上线前必须枚举所有实例、定时任务和仓外调用者，关闭并排空旧进程与在途广播，验证不可被重启/回滚自动拉起；还须有在**广播前**生效、覆盖旧二进制实际路径的控制及负向证明。拟采用的停机、凭证/网络或发布控制若不能覆盖某调用者，保持功能关闭；不假定旧代码识别新开关或数据库 UPDATE 守卫能拦广播。停止清单、实例版本、权限与零旧广播的观测证据齐全前不得切换。

对账输出旧 notice/Inbox ID、可验证事实、缺失项、证据引用、责任人、处置结果及审计时间；敏感内容按权限控制。只有直接绑定**该旧通知创建时**身份的可信证据，加受权人工审核，才能决定历史归属或后续处置；对账本身不能自动确定 project。未能证明的记录保持未知，提供有时限的运营告警和人工升级，不伪造 delivered。

**NTF 当前未就绪 / NO-GO：** 同 recipient 的未知旧行可能阻断真正的新失败，即使证据已变；该保守规则本身不能满足 SC-NTF-006。旧 pending 被隔离且不能自动广播时，也不能满足现行 SC-NTF-007 对已提交、尚未广播提醒的恢复要求；§5 对旧通知行为不变的要求亦存在未闭合的兼容风险。告警、人工对账或保留 pending 不是需求豁免，也不能代替交付。要解除阻断，须有可信事件发生身份及证据能证明新事件与旧通知不同，或完成经审批的逐项处置并证明满足现行规范；无法证明时继续阻断并告警。不能用“允许重复提醒”或“按当前 project 猜”暗中改变规范。未知旧 pending 的最终处置和 SLA 是上线阻断；本稿不自行创建 ADJ、批准偏离或宣称规范改变，任何规范调整须另走正式流程。

## 4. recipient 授权与上线防混跑

- authorizer 必须来自可信业务授权事实，绑定 workspace/project/CR、具体决策及有效性；在发送和恢复前按合同复核。调用者自报 UUID、当前 membership 或 owner/admin 身份都**不等于业务授权**。维护责任人必须有独立可信的职责依据；同一人可兼任，但维护权限不授予业务决定权。无可信事实、撤销或查询失败时失败关闭并告警。**Hard blocker：尚未确定实际授权事实源、维护职责来源、认证调用链、授权时点和撤权并发合同；本稿不假定现有配置或 grant 一定提供这些事实。**
- 当前 sibling `multica` 仓库的 `server/internal/governance/execution_notice.go` 的 authorizer 解析只检查传入 ID 是成员，不能作为上述授权证明；“最早 owner/admin”也需验证是否真是维护责任人。
- 上线顺序：关闭通知产生与恢复入口 → 枚举并排空所有旧写者/恢复器和在途广播、核对实际镜像及仓外调用者，证明旧恢复在广播前不可运行 → 盘点旧数据 → 加数据库旧表 INSERT 拒绝守卫 → 建各索引并验证 → 部署新代码、逐副本启动检查索引并验证所有实例版本、权限和 workspace 恢复覆盖 → 经审批小范围启用。**不以旧表 UPDATE 守卫作隔离或补充保障**：旧恢复器先广播后更新，拒绝更新会留 pending、导致后续重复广播。任何旧状态变更防护若另有需要，必须先证明旧恢复器不可在广播前运行，并独立审查其副作用。分步 DDL 的停写窗口、锁超时和守卫安装竞态须实测，不能假设迁移器包事务。
- 守卫只能兜住经过旧表的旧代码，**不能证明任意直接写 Inbox、特权账号或未知外部调用者被挡住**；必须清点并限制写权限和接入路径。部署/写者清单不完整则不上线。守卫失败应显式报错及报警，不能静默吞通知。

## 5. 迁移与回退

1. 重新核对实际迁移编号和 schema；新增后续迁移，不碰 646。先做必要的旧路径守卫和数据预检。
2. partial UNIQUE 与 §2.3 的 pending 扫描索引各使用**独立、单语句、非事务**的 `CREATE INDEX CONCURRENTLY` 迁移。按 sibling `multica` 仓库 `server/cmd/migrate/main.go` 对每个 up 版本登记 `concurrentIndexCleanups`；失败构建残留 INVALID 时由 hook 清理后重试。每个通知写入/恢复副本启动时均按 §2.2 校验索引表、唯一性、表达式、谓词、`indisvalid` 与就绪状态，不能只凭 `IF NOT EXISTS` 判成功。down 若并发创建索引，登记 `concurrentDownIndexCleanups`；单独的回退安全检查通过 `preRollbackHooks` 接线，不与 invalid 清理混为一谈。**同一迁移版本在同一方向需要多个 hook 时须显式组合，不能用 map 后写覆盖前写**：up 保留全部必要检查与清理；down 先执行无破坏的 v2 安全拒绝检查，再执行所需 invalid 清理，最后才允许 SQL，任何一步失败即停止。顺序和失败边界须测试，尤其不能让清理先发生而破坏“有 v2 时任何破坏前拒绝”。对每个新索引分别测试。SQL 执行与 `schema_migrations` 记录在迁移器中是两次执行；SQL 成功/记账失败及重试、INVALID/同名异定义都须实测。不能假设多语句文件隐式事务或锁行为已获证明。
3. 回退前停写、停恢复、排空并预检。**存在 v2 Inbox、引用或待恢复状态时，禁止破坏性 down 和重启旧写者**：保留数据与唯一性，采用前向修复。尤其不能先 drop 唯一索引、后发现无法回退。由于 CONCURRENTLY 的 down 需独立非事务执行，拟在 `preRollbackHooks` 为每个可能触及新索引/守卫的回退版本挂统一安全检查，**在首个破坏性 SQL 前**拒绝；逐版本、部分升级和反向顺序都需覆盖，并设计与并发写入间的停写/锁定方案，避免检查后再产生 v2。Hook 只约束经该迁移器的路径，直接 SQL、旧迁移器、特权操作者必须由发布权限和流程限制。检查与实际 drop 之间的原子性不可假定，未证明即 **hard blocker**。不得执行会删旧表的 646 down。
4. 仅在确认无任何 v2 数据/引用且旧 pending 隔离仍有效时，受控执行索引和守卫的逆序回退；验证旧行未变、版本记录正确。回退应用版本不等于允许旧恢复器广播未知 pending。hook 失败、SQL 失败、SQL 成功但版本记录失败及重试均须测证，不能把拒绝写在较晚的 down 文件中。

## 6. RED → GREEN 验收计划

| 层次 | 必测断言 |
|---|---|
| 纯函数 | UUID 等价表示同键、非法/nil 拒绝；各身份字段逐项变化不互吞；长度编码歧义反例；同新失败重放稳定，**相同 cause/evidence 的不同真实失败不同键**；固定 v1 向量不漂移。 |
| 真实隔离 DB 升级 | 在旧 schema 先种 delivered/pending、同/不同 recipient、缺失和跨 workspace Inbox，再升级；逐行比对 ID、状态、内容不变。未知归属阻断、不同 recipient 正控、异常阻断；断言零意外写入、零广播。 |
| 并发与故障 | 真实 READ COMMITTED 两事务 barrier：未提交冲突、提交/回滚后独立语句回读；其他约束、空收件人与身份不符不能误判幂等。旧行检查与 v2 并发串行化；不同 project、recipient、真实失败各自一条。写前、提交后、广播后标记前、claim 后崩溃注入故障；并发恢复/原投递验证同 ID、不丢及 delivered 不重播。 |
| 安全与混版 | 伪造 scope、跨 project/CR、仅成员/维护角色、撤权与发送竞争、权限不可用均不能越权广播；验证真实授权链正控。专设旧恢复先广播后 UPDATE 反例：仅拒 UPDATE 时仍会广播且 pending 会反复重播，不能算隔离；真正切换控制必须证明旧恢复在广播前无法运行、零旧广播且新路径正控可用。 |
| 迁移生命周期 | 真实 runner 非事务建每个索引；中断产生 INVALID，逐项验证 cleanup、重试、定义/谓词及有效性；重复/无效 key 预检阻断。各副本分别在启动、重启、加入服务时对缺失/INVALID/错误定义和不可访问库失败关闭；正确索引正控通过。模拟 SQL 成功但记账失败、部分升级后逐版本 down；同版本多 hook 验证均执行且未覆盖，安全检查先于清理/SQL，任一失败停止；有 v2 时在首个破坏性操作前拒绝且索引/守卫/数据/版本不变；无 v2 up/down/reapply 保留旧行。 |
| 恢复与删除 | 多 workspace 启动/周期扫描、分页、故障和延迟告警；抢占竞争及崩溃释放、撤权/查询失败保留未解决事实，不能标 delivered。issue 删除前后 pending、delivered 及重放验证约定的防丢/防重方案。 |
| 客户端及业务 | 真实 loader → bus payload 包含正确 key，再到各启用客户端；覆盖同 session 重投、刷新/重启、缓存回收、多窗口/设备、静音/焦点、显示失败、旧行及 mobile 适用边界；按已批准保证验证可见提醒，不用缓存内结果冒充跨 session 保证。新失败不被 issue 聚合吞掉；真实通知入口和授权链验证 NTF-005/006/007，而非仅 helper。 |

DB 验收仅在未来经授权的专用隔离实例中，按 sibling `multica` 仓库的 `scripts/aifi45-db/README.md` 和版本化 runner 串行执行：核对 schema 快照及显式迁移列表、nonce/受限角色、原库保全和精确清理；实际选中测试且零 skip，零匹配不算通过。该 runner 的快照及保全能力有文档所列边界，不能扩大表述。

## 剩余阻断

1. 可信 workspace/project/CR、失败发生身份、authorizer/维护责任人来源及撤权时点尚需合同和生产接线；[生产者调查](ntf-producer-gap-20261026.md)记录正文与事实来源缺口。X4 的 runner 固定映射决定不等于映射表已实现。
2. 未知 project 的旧通知和 pending 缺少可证明的归属及经审批处置；同 recipient 新失败与旧 pending 恢复分别阻断 SC-NTF-006 和 SC-NTF-007，NTF 未就绪。旧恢复器必须有广播前不可运行的切换证据，拒绝 UPDATE 不够；不创建未经批准的 ADJ 或宣称规范改变。
3. run/node 实际引用路径和同事务能力、并发锁图、READ COMMITTED 回读及 pending 抢占/撤权/workspace 触发均未证；issue CASCADE 的持久身份和恢复方案未定。
4. loader 真实 payload 缺 key、客户端跨 session/设备提醒边界未闭合；实际部署、写者/恢复器、权限、索引/rollback hook 和有效性均未知。须完成独立强审、隔离 DB 验收及上线批准。

本轮仅修订本文；**未运行测试、未连接 DB 或容器，未修改源码**。本文仍为待强审草案，不表示实施、规范变更或部署。
