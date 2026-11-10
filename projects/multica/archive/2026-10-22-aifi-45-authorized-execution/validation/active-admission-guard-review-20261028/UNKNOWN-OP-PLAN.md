# ACTIVE unknown-op 默认拒绝实施计划

**目标**：仅封闭 `CheckDeploymentAccessTx` 在 ACTIVE 且未过期时把未知 op 归类为 `NewAdmission` 的消费侧缺口；不更改签名契约、不接通真实生产入口。

**范围**：先核对 `execution_deployment.go` 和 `deploymentaccess_test/execution_deployment_test.go` 当前 SHA 并保全原字节。审全仓 `CheckDeploymentAccessTx` 直接调用者；截至本计划生成时，仅定义与测试直接引用，故不能以此声称真实入口已接通。该函数当前以 denyOps（五个新动作）、auditOps（五个审计动作）、两个明确恢复动作为已知集合。原有 ACTIVE 语义对两个恢复动作返回 NewAdmission；本切片不改变它。

**RED**：通过既有假事务测试，构造 ACTIVE/未过期、STOP、ACTIVE/过期、缺 head 的未知非空 op；均要求 Denied，ACTIVE 原实现必须因实际 `NewAdmission` 与预期不符而 RED，而非编译错误或 mock 设置失败。

**GREEN**：只在 ACTIVE 且未过期分支把 `NewAdmission` 限定为五个已知新动作或两个明确恢复动作；其他 op 拒绝。现有审计动作顺序和行为不变。复跑 deploymentaccess_test；单测使用伪数据库，不触发 governance TestMain，不作真实 DB 验收。

**独立复核/剩余边界**：请求非作者核验全部已知调用与操作集合、变异检测及 SHA；检查未知 activation 状态、空字段/零代次、签名认证、时间、精确恢复与锁竞态均未由此修复，继续 BLOCK；不把该切片记为 RUN TC PASS。
