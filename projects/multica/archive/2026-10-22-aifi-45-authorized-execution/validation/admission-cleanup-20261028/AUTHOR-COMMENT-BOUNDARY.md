# 准入回滚注释边界（作者记录）

强审指出：rollback 尝试先于调用方继续，不代表远端服务器一定已释放锁。将 `execution_admission_gate.go` 先前关于拒绝路径「已释放」「caller 不持锁」的注释改为：返回前尝试 rollback，但失败或超时时服务器可能仍持锁，后续等待说明写入可能被延迟。无可执行代码修改；旧 SHA `c0834fc2fc34d4cc3b3fe7cf663ea0a5169b11a37c653f71a823f9c253805680` 在 `source-single-guard/` 完整保全。

新源码 raw SHA `b950f20befd10977d34f531b87bf4d95b89c3e2a43546a733001a8778e16781d`；AST 测试 SHA 未变 `7eb49459ac4709eea9f326fba834aff88f99a471a5aa6ce2dae553aebb8150eb`。作者无 DB 重跑源码测试 2/2、0 skip，`go build ./internal/governance` 成功；Go parser 不读取注释再格式化的两个源码结果字节相同。旧独立审阅只覆盖旧 SHA，注释与源码 diff 仍待复核，不证明真实数据库行为。
