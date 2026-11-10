# 精确恢复零值 fail-closed 计划

用户已授权 AIFI-45 消费侧按默认拒绝修复零值绕过，不改已归档签名契约。仅加强 `CheckDeploymentAccessTx` 的 STOP_NEW/过期恢复候选：`IssuedAt` 必须非零，`PersistedGeneration` 与 `Generation` 必须均为正数且相等；缺失证据拒绝。migration 648 对 deployment head generation 有正数 CHECK；本检查不改变 schema。ACTIVE 未过期、已知恢复 op 的既有 NewAdmission 映射不在本切片。

先保全 unknown-mode 修复后的原字节快照。fakeTx 表驱动覆盖 STOP_NEW、ACTIVE/过期；分别将 `IssuedAt`、persisted/current generation 置零或负数，以及两个 generation 均为零，必须返回 Denied；保留原非零相等恢复为正控。旧实现应因 ExactRecovery 而在目标断言处真实 RED，最小更改后重跑全子包 0 skip。

**边界**：入参仍由调用方提供，`RequestID` 目前未用于回查；非零并相等不是权威事实，不证明签名、截止时间绑定、current deployment generation 或 head/STOP 竞态安全；禁止据此接生产、计算 RUN TC 或解除 BLOCK。
