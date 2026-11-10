# 准入错误路径的单一回滚 guard（作者记录）

`AUTHOR-TIMEOUT.md` 中的回滚超时只覆盖 defer：两条普通错误分支仍先调用 `Rollback(ctx)`，若调用方 context 无 deadline 且连接异常，该调用可能阻塞、使 defer 无法开始。先在 `source-timeout-final/` 原样保全上轮已审源码与测试。增强源码 AST 测试要求该函数只能有 guard 内唯一一次 `tx.Rollback`，在旧源码上真实 RED：找到 3 处。删除两处冗余的显式 rollback 后，该 guard 在返回前统一接管所有未交接路径。

无 DB 的 `runnerquery_test` 两项 2/2、0 skip；生产包 `go build` 和 governance 测试二进制编译均成功，DB 探针未执行。构建二进制仅放独占目录，删除本次文件并核空删除目录。客户端 deadline 不保证服务端锁释放；退出前实际完成回滚和异常网络行为未受这些测试证明。

新源码 raw SHA `c0834fc2fc34d4cc3b3fe7cf663ea0a5169b11a37c653f71a823f9c253805680`；AST 测试 SHA `7eb49459ac4709eea9f326fba834aff88f99a471a5aa6ce2dae553aebb8150eb`。之前强审和测试仅覆盖前一 SHA，最终快照须重新独立复核，RUN-006 仍 MISSING。
