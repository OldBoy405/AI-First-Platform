# 精确恢复空 identity 对比计划

strong 审核发现：origin 或 digest 的两个字符串均为空时，现有等值比较会通过；这不是可证明的精确 pin。按用户确认的默认拒绝原则，仅在 STOP_NEW/过期恢复候选中，对空的 persisted origin 或 persisted digest 拒绝，再执行原有相等检查。单侧空对另一侧非空已由现有不等比较拒绝；此变更不修改 ACTIVE 路径、签名契约或 DB。

先保全上一轮已复核源码/测试。fakeTx 通过 STOP_NEW 和过期 ACTIVE 两组分别测试两侧 origin 全空、两侧 digest 全空，并保留既有非空相等正控；应先以 ExactRecovery vs Denied 的真实 RED 复现，再修复 GREEN 并做定向变异。只检查形状，不以非空相等冒充 DB 或签名验证。`RequestID` 尚未从 DB 回查；不在此切片引入仅非空检查而令已有 DB 负例因无关条件假绿。`in.Now` 可被调用方传入、STOP/activation 与锁竞态仍未修，不接生产、不计算 RUN。
