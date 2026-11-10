# 未知 activation mode 默认拒绝计划

本地代码对任何非 ACTIVE mode 进入 STOP/过期恢复分支；具备相等字段的已知恢复 op 因而可能得到 ExactRecovery，审阅报告误写为拒绝，已要求新 correction 保留原报告。migration 648 的 CHECK 当前仅允许 ACTIVE/STOP_NEW，正常受约束 DB 中 unknown mode 不应出现；本切片是对损坏、fakeTx 和未来扩展的纵深防御，不把该反例冒称已在真实 DB 出现。

- 先保存上一轮已审源码/测试 raw 快照。添加 fakeTx 测试：mode 为未知字符串时，已知恢复、审计和新操作全部 Denied；回退源码实际 RED，须是恢复/审计错误分类而非 mock 错误。
- 在读到 event mode 后、readiness 和恢复分支之前，明确只接受 ACTIVE/STOP_NEW；其余返回 Denied。保留缺 head、有效 ACTIVE/STOP_NEW 行为，单元 GREEN 并独立复核。
- 不改 schema、签名、存储、入口或既有 RUN 结论；绝不把此变更解释为恢复身份、签名、锁或 DB 并发已安全。
