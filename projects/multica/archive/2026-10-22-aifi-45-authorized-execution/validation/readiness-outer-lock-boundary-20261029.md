# readiness 外层事务与真实 effect：有限静态扩展

只读会话 `01a1870a-538d-7020-aecc-d2f00ffd6903`；actual backend unknown。未执行 DB、测试、容器或网络，未证明生产部署的实际调用。以下路径相对 `../multica/server/`。

- 五个部署函数（Activate/Issue/Stop/Check/Finalize）的有限非测试 Go 字面调用搜索未找到直接生产调用；不排除间接、其他语言或其他部署版本。测试在一个事务组合 Activate→Issue→Stop（`internal/governance/execution_deployment_retirement_test.go:144–170`），所以独立函数锁序不是完整外层事务锁集。
- `internal/daemon/execution_launch_snapshot.go:40–73,92–110` 先非锁定读，提交阶段对 deployment head `FOR UPDATE` 比 generation 并返回 snapshot/digest；仅发现测试调用，**未证明锁覆盖真实执行或锁释放后的 effect**。
- Check 对 activation head 非锁定读（`internal/governance/execution_deployment.go:467–510`），Stop 锁同 head 并写 STOP_NEW/cutoff（`:208–248`），Issue 持锁核 ACTIVE 并写序号（`:262–301`）。未找到生产组合调用，不能假设 Check 后真实 effect 在同一同步域再次经过 Issue。
- readiness 读取不验证签名/action/generation；Activate 三个 digest 仅在入参非空时比较（`:70–90,124–143`）；Finalize 的 workset 摘要只看非空，并未在本函数与裁决或持久 workset 对比（`:377–425`）。可信上游及合同需另审；这些均非已证生产利用。Issue 的首个 head 查询会吞掉数据库错误分类，故业务错误不等于 SQLSTATE。
- 旧报告的 R→H/H→R 和 R→H→AH/AH→R 是**条件化静态候选**。Finalize 和 Activate 所需 action 不同：有锁等待不代表两个动作均可成功；不声称已复现死锁，也不自行采用 FOR SHARE。

## 未执行的隔离验证前提

仅在获准的版本化 runner、全新隔离 DB/fixture、单编排者和明确所有权下执行。原历史库维持 HOLD。逐个 R/H/AH 在事务屏障后以 `lock_timeout=300ms` 对同一行执行真实冲突写，要求精确 SQLSTATE `55P03`；持锁结束后同 fixture 同写操作须成功，另有不冲突正控。`40P01` 实验须单独授权和可控排程，不能替代行锁正控。Check→Stop→effect 是独立验证：若真实 effect 接线或可信事实源未就绪，应标 BLOCK/unknown。每次受限资源和原库不变、owned cleanup 需有回执；任何身份、错误或清理不确定即停止。不能据此宣称签名、授权来源或完整 Gate 已验证。
