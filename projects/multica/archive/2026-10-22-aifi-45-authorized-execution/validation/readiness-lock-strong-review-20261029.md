# readiness R/H/AH 锁序 strong 静态复审

请求 `GBClaude/claude-opus-5-5:high` 的独立会话 `01a186bf-a59b-7020-aecc-d2b542623dfd` 完成；actual backend 回执 unknown。仅静态源码/文档分析，未执行 PostgreSQL、测试或容器，**未复现死锁**，未评估所有跨模块及事务外层锁。源码当前 raw SHA：`execution_deployment.go` `7b9078db96c6a54b9cb87c040bedfb7b346d8c1a4a77b772367fa94063e3268a`；`execution_policy_readiness.go` `079410205927ed5a5fcf8fb82c78d78463cb75c93efce43e84da6189e9589ed9`；迁移 648 `89f0c3f061c73dae188f99ada0accd13ab770e72e7a96130eb70c3c8c07b5b61`。这些 SHA 由主会话在评审后计算，不冒称评审前后独立核验。

令 R=readiness row，H=deployment head，AH=activation head。按 `execution_deployment.go` 静态读取：

| 路径 | 本函数内顺序 |
|---|---|
| ActivatePolicyTx | R UPDATE → H UPDATE → 重放检查 → AH UPDATE |
| IssueAdmissionTx | AH UPDATE → R UPDATE |
| FinalizeLegacyRetirementTx | H UPDATE → R UPDATE |
| CheckDeploymentAccessTx | AH 非锁定读 → R UPDATE |
| StopNewAdmissionsTx | AH UPDATE |

潜在环 1：Activate 持 R 等 H；Finalize 持 H 等同一 R。需要同 scope、使用同一个 request、Finalize 通过状态/revision/generation 检查；该 request 的 action 后续仍可能令 Finalize 正常拒绝。潜在环 2：A1 持 R 等 H，A2 持同 scope H 等 AH(T2)，Issue 持 AH(T2) 等 R；需要 Issue 的 active verdict_ref 指向该 R、A2 使用另一 R′ 等条件。A1 可以是 T2 的重放：重放检查在 H 之后，因此不必假定跨 target 复用。均只是条件化静态推论，不代表运行证据。

候选将 R 的读取锁从 `FOR UPDATE` 改为 `FOR SHARE`：评审认为两个环的 R 读者等待边可因共享兼容而消失，且共享行锁仍应与实际 readiness UPDATE/`FOR UPDATE` 写者冲突。但必须用真实受控 PostgreSQL 证明锁强度、全局顺序、事务隔离及调用前后锁集合；不能据此宣称不存在其他死锁。不能改成更弱 `FOR KEY SHARE` 并假定可阻止非键更新。迁移中的不可变约束和单次写入需和实际 schema 一起复核；不把本候选当成签名、权威时间、target 绑定或撤销语义的证明。

`CheckDeploymentAccessTx` 对 AH 非锁定读的并发停新 TOCTOU 与 R 锁问题不同；仅靠换 R 锁不能解决。按非测试 Go 的有限字面搜索，主要函数未找到生产直接调用；这不排除间接/其他语言/部署路径。`daemon/execution_launch_snapshot.go`、`execution_contract_selection.go` 与外层事务锁仍需深入，当前不是完整全局图。

## 下一步而非授权

先核全局写者与合同约束，补可验证的隔离 PostgreSQL 测试设计。行锁探针须 `lock_timeout=300ms`、精确 SQLSTATE `55P03`、分离 fixture 与释放后正控；死锁复现如单独使用 `40P01`，须可控排程与安全清理，不能替代行锁探针。版本化 runner 必须提供原库未变与本次资源清理回执，未经允许不得碰历史冻结库。合同是否允许 verdict 跨 target/唯一消费、权威事实及停新一致性分别决定。现阶段不修改锁，也不把 mock、静态推论或建议当作 Gate 证据。
