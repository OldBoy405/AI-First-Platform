# 通知 X6：producer、recipient、幂等静态复核

请求 strong 只读会话 `01a186e1-43ce-7020-aecc-d2c4e23868ed`，actual backend unknown。范围：需求/现有分析、multica `execution_notice.go` 与 migration 646，有限 grep；未读 Inbox 实现、完整 crsync、全部 producer、消费端或完整 Composio 实现，未运行 DB/容器/测试，也未证明部署可达性。下列是条件化静态事实，不是生产验收。

- `DeliverNotice` 对调用方 `RecipientID` 仅作 UUID 解析；函数自身不调用 `ResolveNoticeRecipient` 来证明授权者、故障责任或当前 scope。有限 server 代码检索未找到生产调用，不等于证明生产不可达。真实可信 producer 和 recipient 来源、项目与证据绑定仍未定。
- `NoticeDedupeKey` 当前以 CR、cause、证据摘要和 audience 形成 v1 键；DB 唯一索引另含 workspace，不含 project 或实际 recipient。`NoticeEvent` 未提供 project；证据摘要可空。是否满足 canonical 的业务事件身份和收件人变化语义，必须核可信源与兼容迁移。不可仅因静态搜索未见调用就假设无存量或直接改 v2。
- 新通知 notice/inbox 在同一事务，commit 后广播、独立 UPDATE delivered；冲突复用现有行，即便 pending 也不主动重播。恢复流程读取 pending、广播原 inbox ID、更新 delivered：并发恢复可能重复广播，首个失败中止后续处理；消费端幂等与实际恢复调度未证明。不能仅加状态条件或孤立引入 `SKIP LOCKED` 就声称外部投递 exactly-once，广播后崩溃、claim 生命周期与旧数据策略仍需设计。
- 未找到通知与 Composio 的直接关系；任务派发可能先于事务产生外部 session 的既有风险仍是另一条调用链，不可归因到通知或假定其 rollback。生产调用顺序及副作用须由真实入口确认。

**不自动实施评审建议的 v2 键、空证据拒绝、闭集 cause 或收件人选择**：这些会改变兼容、历史重放或用户语义，且可信事实源和 producer 尚未确定。保留本地 fail-closed 输入修复与现有生产接线状态，不将局部 fake/nil-pool/静态检查作为 SC-NTF 或 X6 验收。Gate3 仍 NO-GO。
