# X6 通知身份/迁移提案 — STDD strong 独立只读审阅归档（2026-10-28）

> 本文归档对 `ntf-scope-x6-proposal-20261028.md` 的两轮 strong 只读审阅。**旧提案原样保留、未修改**；本文不是批准，也不是实现或测试证据。
> 两轮均**未运行测试、未访问 DB/容器、未发送通知**；除明确标注“已核”外，PostgreSQL 锁/约束语义与迁移器隐式事务行为均为**未在本仓实测的推断**，所列修订均为**建议**，不是已验证结论。
> 首轮**不完整**（见 §2），第二轮补核并**纠正首轮 B1 中 `CHECK … NOT VALID` 的错误建议**（见 §3.3）。

## 1. 审阅对象与实际源 SHA

| 对象 | 值 |
|---|---|
| 被审提案 | `validation/ntf-scope-x6-proposal-20261028.md`（未跟踪文件，sha256 `89e6c18522791e21bb77d566137da6d723ed0e7e709f06b819538845aeb9724a`，本次未改） |
| 平台仓 HEAD | `1a409847af4f049dbbd06ed8e86e6d7267d7496a`；`design.md` 最后提交 `8cc0113e` |
| multica 源仓 | `C:/Users/GOBAO/Downloads/AI/multica`，`main` HEAD `81e5293adc758e392a045026cf81ec5cc1bac72d` |
| `646_cr_execution_notice.up.sql` / `.down.sql` | blob `553b15f0af62e23c7ca7ae1f1b65d759c3d090e5` / `bf378b71c742f3bc6630e61b76f987376d7d5de0`，与 HEAD 一致，最后提交 `5c395581f` |
| `execution_notice.go` | HEAD blob `8d6bcce4c0bce4b1be770896e93998ed9f63152e`；**工作区 blob `22749eafb6d75144bf2f87775f4467538914b4cd`（未提交改动）** |
| `CUSTOM.md` | 工作区 blob `5edf797def9c5b74e47ca5e6bed63d82a1666c23`（未提交改动） |
| 迁移目录 | 最新 `648_cr_execution_control`；649 当前空闲（实施前仍须重核部署清单） |

**非 X6 改动说明**：`execution_notice.go` 工作区差异为另一作者的广播依赖改动（broadcast 为 nil 即报错、`BusBroadcaster` 要求 bus 与 loader 并校验 item `id`/`workspace_id`、恢复使用规范化 `wsID`）。**本审阅不将其视为 X6 改动，也不以其作为 X6 证据。**

## 2. 第一轮（不完整）

### 2.1 完成度声明

首轮在轮次上限内**只读完提案与 `execution_notice.go` 未提交 diff**；**未读** 646 全文、`execution_notice.go` 全文、design §5。首轮依赖这些文件的结论当时标为“基于提案引用的推断”。以下按当时原意归档，其中 B1 的 NOT VALID 建议已在 §3.3 被**纠正作废**。

### 2.2 首轮 blocking（原样意旨）

- **B1 混版锁窗**：只说“迁移加 INSERT 守卫”不够；加列与守卫须同事务并锁表，否则旧二进制可在 DDL 间隙写 v1。首轮写“CHECK 需 `NOT VALID`（否则旧 v1 行令验证失败）”，并要求同时拦截 UPDATE 改 dedupe_key/project/recipient。→ **NOT VALID 部分已于第二轮纠正，见 §3.3。**
- **B2 并发与唯一约束**：v2 “先查旧行再插”非原子；两个 v2 写者可同时判定“无旧行”。建议同事务 advisory lock（workspace+CR）或显式锁 notice/Inbox 行，确定性 barrier 测两种交错。
- **B3 编码/hash/冲突回读**：`v2:` 前缀与“无歧义编码”缺具体规格（长度前缀或 canonical JSON、字段序、版本标签、算法、evidence 规范化）；“核对完整身份”要求 v2 行持久化 evidence 摘要与 audience。
- **B4 workspace/recipient 业务授权**：提案只谈身份，未要求 recipient 当前为 workspace 成员、对 project/CR 有权，未校验 project∈workspace、CR∈project。
- **B5 旧 pending 恢复越权**：`RecoverPendingNotices` 扫描该 workspace 全部 pending 并广播；提案只说“接调度前须隔离”无机制。建议本切片即令恢复只处理 v2 身份完整行，旧 pending 仅报告不广播，测试证明零旧行被广播。
- **B6 down**：v2 存在时拒绝须在 down SQL 显式 `RAISE`；空 v2 时先删守卫后删列，不触 646 旧行；考虑迁移器失败后的版本状态。三态测试。

### 2.3 首轮非阻断风险

- 旧行 project 不可归属：按 CR+recipient 阻断过宽，同 recipient 后续通知可能永久阻断且无解除路径，直接构成 NTF-006 不可用；缺人工对账入口/审批者与阻断可观测性。
- 证据变化：新失败/证据变化也被阻断，是吞通知而非重复，须明确兜底告警责任。
- Inbox 回读：旧行“可验证”依赖 `inbox_item` 当前态，被删/归档须落“不可信→阻断”，不能落“不同 recipient→新建”。
- NTF-006：本提案最多证明 X6 组件，不得宣称满足（与提案自述一致）。

## 3. 第二轮（补核）

### 3.1 已核：design §5 与 646 矛盾，且无生效修订（blocking）

- `design.md` §5（第 74–85 行，尤其 79–81 行）要求：在既有 `inbox_item.details` 写 `execution_notification_key`；按 `(workspace_id, recipient_type, recipient_id, details->>execution_notification_key)` 建 **partial UNIQUE（独立 CONCURRENTLY 迁移）**，Create 路径 ON CONFLICT 返回原记录；投递状态写 `details.execution_delivery.status=pending|delivered`；**不建全局去重账本**；旧通知无该字段行为不变。第 78 行要求键含可信 workspace/project/CR、原因类别、稳定 root cause、规范证据摘要与规范化非空接收者。
- 646 实际：新建独立表 `cr_execution_notice`，唯一索引仅 `(workspace_id, dedupe_key)`，v1 键（`NoticeDedupeKey`）只含 `cr-execution-notice/v1`、CR、cause、evidenceDigest、audience，**无 workspace 规范值以外的 project/recipient**。
- 已查 `pending-adjustments.yaml`（ADJ-AIFI45-M001–M004 及第 12 行）、`canonical/specs/{code,agent}/attention-routing.yaml`（REQ-NTF-003 仍为“不新建全局去重账本”，SC-NTF-005/006 未变）、`specs/attention-routing/spec.md`、`tasks.md`、`test-plan.md`、`slices.md`：**均无批准该偏离的修订**。唯一表述是 `CUSTOM.md #195` 自称“1:1 附表、不是第二账本”——这是实现自述，不是设计修订。
- 结论：提案“扩展 `cr_execution_notice`”是在**未批准的偏离**上加固附表/账本形态。

### 3.2 已核：X6 既有决议与提案方向相反

`validation/backlog-b-disposition-20261026.md:89` 记 X6 为“**改 646 迁移**，原位改未上线的 646”；提案改为“646 一律视为可能已部署、不改，新增 649”。两种取向各有理由，但改变须留决策记录并以**有证据的部署事实**为依据；646 是否已部署至共享/生产实例，本审阅**未核**（禁止访问 DB/容器）。

### 3.3 纠正首轮 B1：`CHECK … NOT VALID` 不可行（PG 语义推断，未实测）

- `NOT VALID` 只跳过对既有行的验证；**此后每次 INSERT 与 UPDATE 产生的新行版本仍须满足 CHECK**。因此若 CHECK 要求 project/recipient 非空，旧 v1 行仅执行 `UPDATE … SET state='delivered'` 也会被拒，**直接打断旧 pending 的标记/恢复**，与提案“旧行状态更新仍允许”矛盾。首轮把 NOT VALID 作为可选方案**是错误的，予以作废**。
- CHECK 也无法区分“迁移前旧行”与“迁移后旧二进制新写的 v1 行”。若要区分，需迁移时回填标记（如新增 `legacy_v1` 后 `UPDATE … SET legacy_v1 = true`），CHECK 写 `legacy_v1 OR v2 完整`；但新写入可自设该标记，**仍需 trigger 拦截**。
- 建议（未验证）trigger 方案：
  - `BEFORE INSERT FOR EACH ROW`：拒绝缺 v2 键或身份不完整行；拒绝 `legacy_v1 = true` 的插入。
  - `BEFORE UPDATE FOR EACH ROW`：仅允许 `state`、`delivered_at` 变化；身份列（workspace_id、cr_id、dedupe_key、inbox_item_id、project_id、recipient_id、摘要/audience）与标记列任何变化均拒绝。
- 锁粒度（PG 语义推断，**未在本仓实测**）：`ALTER TABLE ADD COLUMN` 与 `ADD CONSTRAINT CHECK` 取 ACCESS EXCLUSIVE；`CREATE TRIGGER` 取 SHARE ROW EXCLUSIVE（与 INSERT/UPDATE 互斥）。回填、加列、建 trigger 须在**同一迁移文件/同一隐式事务**内，不可夹 CONCURRENTLY，否则旧写者可在间隙插入；文件开头宜设 `lock_timeout` 以免排队阻塞业务。
- 守卫只能让旧写者**失败关闭**，不能替代“停/排空旧写者”：拿锁前已在途的旧事务会先提交，迁移前后均须核对。

### 3.4 已核：646 全文

- 列：id、workspace_id、cr_id、cause_code、audience（authorizer|maintainer）、dedupe_key、inbox_item_id、state（pending|delivered）、delivered_at、created_at；**无 project/recipient/evidence/details**，**无 FK**（注释称刻意）。
- 索引：`cr_execution_notice_dedupe UNIQUE (workspace_id, dedupe_key)`；`cr_execution_notice_pending (workspace_id, created_at) WHERE state='pending'`。
- down：`DROP INDEX … ; DROP TABLE IF EXISTS cr_execution_notice;` —— **有数据时直接删除数据且无拒绝**。

### 3.5 已核：notice recipient 路径

- `deliverNoticeWith`（`execution_notice.go` 工作区约 239–333 行）对 `ev.RecipientID` 仅 `uuid.Parse`，**不调用 `ResolveNoticeRecipient`**；投递路径不验证成员资格或 project/CR 权限，直接以 `recipient_type='member'` 写 `inbox_item`。
- 冲突时仅按 `(workspace_id, dedupe_key)` 回读 id/inbox_item_id/state，**不比对任何身份字段**。
- v1 键以 `\x00` 拼接字段，无长度前缀；字段含 NUL 即可产生歧义（`BuildNotice` 是否拒 NUL 本审阅未逐行核）。
- `ResolveNoticeRecipient`（约 466–516 行）：authorizer 分支只验证**调用方给定的** authorizerID 是该 workspace 成员，不证明其为该 CR 授权者；maintainer 分支取最早 owner/admin（`ORDER BY created_at, user_id LIMIT 1`），成员变动时接收者会静默变化。
- 结论：当前 recipient 不能直接作为“已授权身份”入键。

### 3.6 已核：迁移器 `server/cmd/migrate/main.go:976–1101`

- 仅用 session advisory lock 串行；**不将单个迁移文件包入显式事务**（注释说明因已有 CONCURRENTLY 迁移）。
- SQL 执行与写 `schema_migrations` 是两次独立 `Exec`，非原子；**无 dirty 状态**；down 若 RAISE 失败，版本记录保留、不删除。
- 推断（**未实测**）：多语句文件经 simple query 由 PG 作为隐式事务执行；SQL 已执行但记录未写时重跑会再执行，故迁移须可重入（IF NOT EXISTS 等）。
- design 要求的 CONCURRENTLY partial UNIQUE 须单语句独立文件，并在 `main.go:118` 附近清单登记 invalid-index cleanup hook；提案未提及。

### 3.7 对各质疑点的补充

- 旧行 project 不可归属 / 证据变化：见 §2.3，保守阻断与 SC-NTF-006 直接冲突。
- 混版绕过/锁窗：见 §3.3；design 路线（details 键 + partial UNIQUE）同样面临旧写者不写 details 键而不触发唯一冲突的问题，任一路线都需要写者侧守卫与停写证据。
- 并发与唯一约束：见 §2.2 B2；design 路线的 partial UNIQUE 含 recipient，但旧行检查仍需同事务锁。
- 旧 pending 恢复：`RecoverPendingNotices` 仍扫描全部 pending，工作区版本只是强制要求 loader，未区分 v1/v2。
- down：646 down 与提案“有 v2 拒绝”须分别处理（见 §3.4、§2.2 B6）。

## 4. 合并 blocking 与最小修订（建议，未验证）

1. **设计决策先行**（新增 ADJ 至 `pending-adjustments.yaml`），二选一：
   (a) 回到 design §5：键与投递状态入 `inbox_item.details`，partial UNIQUE 独立 CONCURRENTLY 迁移，646 表逐步退役；
   (b) 正式批准附表偏离，同步修订 design §5、canonical REQ-NTF-003、CUSTOM，并论证其非“账本”。
   同时撤销或更新 X6 “原位改 646”的旧决议，依据有证据的部署事实。
2. **混版守卫**：采用“回填旧行标记 + INSERT/UPDATE 双 trigger”；写明锁级别、`lock_timeout`、迁移可重入与停写/排空证据。**首轮 NOT VALID 方案作废。**
3. **recipient 授权入投递事务**：成员资格、CR 授权者/维护者归属、project/CR/workspace 归属一致性；配负向测试；固定 maintainer 选择规则并纳入身份比对。
4. **恢复只处理 v2 身份完整行**；旧 pending 仅报告不广播，并有测试证明。
5. **v2 编码规格**：长度前缀或 canonical JSON + 版本标签；冲突回读比对全部身份列（含 evidence 摘要、audience）。
6. **down 三态**：空表 / 仅旧行 / 已有 v2；有 v2 时在 SQL 中 `RAISE` 拒绝。
7. **同 recipient 永久阻断的解除与对账入口及兜底告警责任人**；在此之前不得宣称 NTF-006 满足。

## 5. 未核与限制

- 646 是否已部署于共享/生产实例：未核（禁止 DB/容器）。
- PG 锁级别、NOT VALID 对 UPDATE 的行为、simple query 隐式事务：依 PostgreSQL 语义推断，**未在本仓或隔离实例实测**。
- `BuildNotice` 对 NUL/非法字符的完整处理、仓外调用者：未逐一核。
- 本文所有修订均为建议；未改任何代码、迁移、design、canonical 或旧提案。
