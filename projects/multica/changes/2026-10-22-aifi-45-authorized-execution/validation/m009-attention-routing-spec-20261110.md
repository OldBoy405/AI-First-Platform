# M009 attention-routing 待批准规格（2026-11-10 自 trusted-verdict-outcome-binding 移回）

> **来源与处置**：本文件原为 `projects/multica/changes/2026-10-29-trusted-verdict-outcome-binding/specs/attention-routing/spec.md`，及该 change design 的「AIFI-45 本轮承接增量 §2 M009 通知身份」「§3 M009 静态代码核对」两节。用户 2026-11-10 采纳收窄建议：M009 与可信裁决绑定无共同保证、代码或验收，移回 AIFI-45 处理，按原 TC-NTF-001～007 验收。以下正文原样保留，**仍是待批准文本**；移回不构成批准、实施授权或验收结论。下一步：在 AIFI-45 或独立小 change 中评审，并修正 `ResolveNoticeRecipient` 维护类回退偏差、补证 SC-NTF-007 写前重建。

---

## Spec: attention-routing — AIFI-45 M009 承接增量

> **待批准文本。** 用户已口头确认复用 notice 唯一身份及 CR 角色 owner 路由方向，本轮承接到现有载体，不表示合同生效、实施完成或验收通过。AIFI-45 原 SC-NTF-001～007、design §5 及历史草案保留；本页列出拟议修订，不回写或覆盖原文件。
>
> 来源：`projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/m009-notice-identity-amendment-draft-20261109.md`；同目录 `notification-convergence-plan-20261109.md`「四项验收保证」第 2、3 项；本轮用户补充的 CR owner／run 启动身份／会话链接规则。早期草案中「责任来源尚未确定、不从 owner/starter 猜测」是历史调查结论；本增量明确通知收件路由来源，但不以收到通知推导业务授权。静态源码核对及尚存偏差见 本文件末尾附录（原 design 承接增量 §3）。

## Requirements

### Requirement: 三类必要通知依据真实事实产生，普通进度保持安静，内容能回到 CR 对话。

**现有机制不足：** 节点状态或固定快照不能证明待决授权、恢复耗尽或约定交付，裸 Inbox 消息也不能让接收者定位并处理原 CR 对话。

#### Scenario: SC-NTF-001（原要求保留）

- **GIVEN** 正常节点完成、ACK、status/next 变化或额度内有进展的常规修复。
- **WHEN** Runner 记录进度。
- **THEN** SHALL 不创建机械主动通知，只保留可查询运行记录和必要证据引用。

#### Scenario: SC-NTF-002（M009 事实与会话承接）

- **GIVEN** 有可追溯的真实事实证明当前需要补授权／业务判断、有界恢复后需责任人处置的阻断，或已完成约定交付。
- **WHEN** 按下面的身份与角色路由创建必要通知。
- **THEN** SHALL 仅包含结论、必要错误、canonical 证据链接及明确所需动作，不复制整份 JSON／报告；无业务授权问题不要求人回复「继续」。
- **AND** Inbox 的 `issue_id` SHALL 取同一可信 workspace/CR 的 `cr.shell_issue_id`，指向该 CR 对话，而非另建会话或指向其他 issue。若原 CR 尚无 shell issue，不伪造 ID，也不宣称已具备会话链接；其缺失不改变原通知身份或制造第二条提醒。
- **AND** 路由成功不是事实证明；普通节点 completed 不自动等于约定交付，技术错误码也不单独证明恢复已耗尽或根因真实。

### Requirement: 收件人取 crctl 投影的 CR 角色 owner，无可用 owner 才退回该 run 的任务启动身份，仍无则不发送。

**现有机制不足：** workspace 的 owner/admin 身份、显示名或 `member.id` 都不是当前 CR 的角色责任来源，单凭启动者是成员也不能证明其具备业务授权。

角色事实链为 crctl 注册／交接记录的 `owners.requirement|development|test` → owners outbox → `crsync.applyOwners` → 同 workspace/CR 的 `cr.owners`。每个角色 owner 的 `id` 必须表示本 workspace 成员的 `user_id`（UUID），不是显示名、Agent ID、`member.id` 或任意 UUID；投影保留角色归属，消费时按 workspace 成员资格核验。`test` 一并投影保留，但不另造第四类通知或将它自动替代 requirement/development。

#### Scenario: SC-NTF-003（M009 维护路由承接）

- **GIVEN** 凭据、部署、环境或绑定故障，适用有界恢复已耗尽或无法安全恢复。
- **WHEN** 确定维护类通知接收者。
- **THEN** SHALL 优先取该 CR 的 `owners.development.id`，并验证为本 workspace 成员的 `user_id`；有可用 development owner 时，不被 starter 或 workspace owner/admin 替换。
- **AND** 只有没有可用 development owner 时，才退回启动该 run 的任务身份（现有 `pipeline_run.started_by` 所记录并可验证的成员 `user_id`）；仍无可路由身份则不发送，不自行挑选 workspace owner/admin，也不广播给业务方。
- **AND** 通知带已试路径和具体维护动作，不把命令搬运或技术排查交给业务方；维护身份不因此得到业务授权。

#### Scenario: SC-NTF-004（M009 授权路由承接）

- **GIVEN** 授权／范围／验收／追加额度或无进展阻断需要业务判断，维护者与授权者可能同人或异人。
- **WHEN** 按根因确定授权类通知接收者。
- **THEN** SHALL 优先取该 CR 的 `owners.requirement.id`，并验证为本 workspace 成员的 `user_id`；仅无可用 requirement owner 才退回该 run 的任务启动身份，仍无则不发送。
- **AND** 无可用 owner 包括角色缺失、空值、ID 无效或不属于本 workspace；读取／验证出错时停止发送，不把故障当成 owner 缺失后随意改投。有效 CR owner 存在时不得以启动者覆盖。
- **AND** 通知明确剩余阻断和所需判断；此规则只确定提醒收件人，不签发 grant、不扩大 owner／starter 的权限，实际决定仍经原有身份、权限与审批入口。约定交付类通知沿现有非维护受众路由取 requirement owner／同样回退，不隐含交付验收已由该人确认。

### Requirement: 复用 cr_execution_notice 既有唯一键和 Inbox 身份，重放不扰民，重要变化不互吞。

**现有机制不足：** `cr_sync_event` 的 commit/event-kind 去重不能跨新 commit 识别同一未变化事实，Inbox 的 CreateIfEligible 或读侧 issue 聚合也不提供发送侧并发唯一性。

#### Scenario: SC-NTF-005（M009 通知身份拟议修订）

- **GIVEN** 同一稳定原因／事件、重要证据摘要、非空受众和规范化接收者的事实被重复投递、跨 run/commit 重放或并发处理。
- **WHEN** 持久化通知或重启恢复。
- **THEN** SHALL 复用 `cr_execution_notice` 作为通知持久身份，以既有 `(workspace_id, dedupe_key)` 唯一约束并发去重；notice 与对应 Inbox 记录在同一事务内持久化，冲突返回原 notice 和原 Inbox ID，不创建第二条内部通知。
- **AND** 规范身份继续覆盖可信 workspace、project、CR、稳定原因／事件、重要证据摘要、非空受众及规范化接收者；接收者以规范 UUID 表达，等价写法不得成为不同身份。run ID、commit、重放时间和错误码本身不得替代未证明的业务事件身份。
- **AND** 不新增 `inbox_item.details.execution_notification_key`、partial UNIQUE 索引或相关迁移；不新增数据库表、列、索引、第二通知账、全局事件平台、调度器或历史回填。既有 notice 唯一约束是复用对象，不是本次新增索引。
- **AND** `pending`／`delivered` 状态和稳定 Inbox ID 保存在既有 notice；已 delivered 的相同事件不作为新通知重播，pending 恢复按原 Inbox ID 重投，消费者按 workspace + Inbox ID 幂等展示。

#### Scenario: SC-NTF-006（原保证保留，M009 路由身份承接）

- **GIVEN** 已通知后出现新失败、重要证据变化、接收者变化或约定交付完成，或不同 CR 恰有同名原因。
- **WHEN** 新事实进入同一通知入口。
- **THEN** SHALL 为必要变化生成不同的规范事件身份并发送必要通知，不被旧 root cause、旧接收者或 issue 聚合吞掉；不同 CR 不互吞，同一事实不因换 run/commit 产生新提醒。
- **AND** CR owner 或回退身份改变造成实际接收者变化时，使用规范化新接收者参与身份计算；不改写旧 notice、旧 Inbox 或其 delivered 状态。

### Requirement: 写 notice 前及广播／标记前故障均沿原身份恢复，不重做业务效果。

**现有机制不足：** pending 扫描只能恢复已经提交的 notice，业务先提交而 notice 尚未写入时没有 pending 行，不能靠该扫描或一条风险记录保证不丢提醒。

#### Scenario: SC-NTF-007（原保证保留，M009 持久身份承接）

- **GIVEN** 业务事实已提交，随后写 notice／Inbox 前、notice 事务中、提交后广播前，或广播后标记前发生故障。
- **WHEN** 沿既有业务事实与通知身份有界恢复。
- **THEN** SHALL 不回滚已提交业务事实、不重签授权、不重复扣额或派发 writer；从可追溯且可靠保留的既有持久业务事实重建尚未写入的通知意图，沿原规范身份恢复，不丢提交后提醒。
- **AND** notice 与 Inbox 任一持久化失败时事务整体回滚；后续按原身份重建，不能以「尚无 pending 行」降低恢复要求。具体事实生产者、持久位置和逐事件重建能力须证明，不能用可覆盖单槽快照或日志代替。
- **AND** 已提交 pending 用原 Inbox ID 恢复；广播后标记前中断允许同 ID 再投，消费者须幂等展示。内部唯一记录不等于广播、客户端展示或第三方物理 exactly-once。
- **AND** 若发现旧键记录，保留数据并单独裁定兼容／重放，不推断历史为空，不擅自回填、双写或迁移。

## 沿用验收与生效边界

来源为 AIFI-45 原 `TC-NTF-001～007`，仍按原分母与既有编号验收：001 保持安静；002 覆盖真实事实及 CR 对话链接；003/004 覆盖三角色投影、跨 workspace/无效 ID 拒绝、owner 优先、无 owner 才回退及仍无不发；005/006 覆盖规范身份、并发、跨 run/commit 与接收者／证据变化；007 覆盖写前、事务、广播／标记故障和消费端同 ID 幂等。不增加 TC 编号，不将静态代码或局部测试引用计为已通过。

本页区分待审合同和当前实现：唯一键、CR owner 优先、会话链接已有源码接线；维护类无 owner 的回退、可信 project／事件证据和写前恢复仍有具体差距，详见 design。本轮不改代码、schema、迁移、Gate 或历史合同，不以把方向纳入 specs 宣称通知能力已闭合。

---

## 附：原 design 承接增量 §2–§3（原样）

### 2. M009 通知身份与 CR 角色责任来源

完整拟议文本见 本文件上文，沿用 SC-NTF-001～007。来源为 [M009 身份草案](m009-notice-identity-amendment-draft-20261109.md)四项替换方向，加上本轮用户补充的角色 owner／run 启动身份／CR 对话事实；早期草案对责任来源未知的判断保留作历史，不再用来否定已经存在的 CR 角色投影。

- **身份与并发**：复用 `cr_execution_notice (workspace_id, dedupe_key)` 既有唯一约束；notice/Inbox 同事务持久化，冲突返回原 notice／Inbox ID。规范身份继续覆盖可信 workspace/project/CR、稳定原因／事件、重要证据、非空受众和规范接收者；跨 run/commit 重放不变，重要变化不互吞。原因是 commit 级 cr_sync 去重与读侧聚合都不能保证发送侧的同事实唯一性。
- **不再采用旧候选存储位置**：原 AIFI-45 design §5 的 Inbox details 键、partial UNIQUE 及相应迁移保留为历史；本轮待审方案明确不新增这些字段、索引或迁移，也不另建通知账、调度器或回填。原因是既有 notice 已能持久标识内部通知，无需再造一套身份。
- **角色事实链**：crctl 注册／交接的 `owners.requirement|development|test` 经 owners outbox 由 `crsync.applyOwners` 投影到 `cr.owners`；角色对象的 `id` 必须是本 workspace 成员的 `user_id`，不是 `member.id`、显示名或 Agent ID。授权类→requirement，维护类→development；现有非维护交付受众沿 requirement 路由，test 仅保留投影、不新增受众。原因是 workspace 管理角色不是该 CR 的责任归属。
- **回退与权限边界**：有可用 CR owner 就优先使用；只有无可用 owner 才退回启动该 run 的任务身份（`pipeline_run.started_by` 的有效成员 user_id），仍无则不发送；读取出错停止发送，不任选 workspace owner/admin。owner/starter 只确定提醒对象，不因此获业务授权。原因是成员身份或收到通知本身不能替代原审批与权限校验。
- **会话与投递**：Inbox `issue_id` 取同 workspace/CR 的 `cr.shell_issue_id`，无 shell issue 时不伪造链接；pending/delivered 和稳定 Inbox ID 保存在 notice，提交后广播，pending 按原 ID 恢复，消费者按 workspace+Inbox ID 幂等。原因是裸消息不能定位原对话，而广播与标记无法物理 exactly-once。
- **保留写前恢复保证**：业务提交后通知失败不回滚业务、不重签／扣额／派 writer；即使 notice 尚未写入，也须从可靠既有持久事实逐事件重建原身份，不能以无 pending 行豁免 SC-NTF-007。原因是 pending 扫描不覆盖 notice 写入之前的故障。

### 3. M009 静态代码核对：已接入与偏差分开记

以下路径均相对 `../multica/`，仅为本轮只读源码事实，不是测试或生产验收：

| 位置 | 当前可核事实及与待审文本的关系 |
|---|---|
| `server/internal/governance/crsync.go#applyOwners` | 已接 owners 事件，投影 requirement/development/test 的角色对象并检查 `id` 的 UUID 形状；这里本身不查询成员表。接收资格由下游按 workspace/user_id 再核，不能把形状检查写成已证明成员资格 |
| `server/internal/governance/execution_notice.go#noticeOwnerRole/#ResolveNoticeOwner` | 已映射维护→development、非维护→requirement；按 `member(workspace_id,user_id)` 校验 owner，缺失／无效／非成员返回无可用 owner；不是取 `member.id` |
| `server/internal/governance/execution_notice_wiring.go#notifyFact/#runNoticeIdentity` | 已先查 CR owner，查不到才进入回退；run 身份来自 `pipeline_run.started_by`，查询错误时停止通知 |
| `server/internal/governance/execution_notice.go#ResolveNoticeRecipient` | **具体偏差**：授权类回退会验证传入 starter 的成员身份；维护类却忽略 starter，按创建顺序挑 workspace owner/admin。因此「维护类无 CR owner→starter→仍无不发」尚不能宣称与当前源码一致；本轮只写规定与差距，不改代码，也不把旧分支纳为合同例外 |
| `server/internal/governance/execution_notice.go#DeliverNoticeTx`、`server/migrations/646_cr_execution_notice.up.sql` | 已用 `(workspace_id,dedupe_key)` 冲突取原 notice/Inbox，notice 与 Inbox 同事务；Inbox `issue_id` 已取 `cr.shell_issue_id`，没有依赖新 details 键或新 partial UNIQUE 的必要 |
| `server/internal/governance/execution_notice.go#NoticeDedupeKey`、`runner.go#failRun` | 当前 key 含 CR/cause/证据摘要/audience/规范 recipient，workspace 由唯一约束覆盖；尚未证明可信 project 覆盖。失败接线对错误码求摘要，不能据此声称同码新失败／重要证据变化已不互吞 |
| `server/internal/governance/execution_notice_wiring.go#notifyFact/#recoverPendingNotices` | 业务事实与 notice 事务分离，恢复扫描仅覆盖已有 pending；notice 写前故障的逐事件重建仍未证明。保留 SC-NTF-007，不把缺口降为可接受的不丢通知保证 |

`execution_notice_wiring_test.go#TestNoticeGoesToTheRecordedRoleOwnerAndItsConversation` 已有 development owner 优先与会话链接的测试源码，但不覆盖无 owner 的维护回退；本轮未执行，不能据测试存在宣称其通过或全链完成。
