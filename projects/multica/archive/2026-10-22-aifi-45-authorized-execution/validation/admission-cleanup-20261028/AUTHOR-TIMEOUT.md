# 准入事务异常清理超时：作者记录

在前一轮 guard 前移后，强审指出 `Rollback(context.Background())` 在网络挂起时可能无界阻塞。经只读核对 pgx v5.11 的事务和连接池失败路径，本轮把未交接事务的 rollback 改为独立 `context.WithTimeout(context.Background(), 5*time.Second)`，并在 guard 内 defer cancel；成功交接路径不创建计时器。前一轮源码 `865821b5ec83c02a198f8ffd9bdbd0a94f7e9daae6ac44ca357f0b7f6280fe9e` 和测试 `cf50c31196ca2c48247fadc3a631684d7fce3ee76728a68c9ab231a221d3cf57` 原样保存在 `source-timeout-review/`，旧审阅保持不变。

**边界**：5 秒是传给客户端 rollback 的 context deadline，不证明 5 秒内服务器锁释放、远程后端终止或网络断开已被服务器感知；代理、网络分区和服务端 keepalive 可能延迟释放。此修复未在真实数据库或网络故障下注入验证。

增强 AST 测试先在无界回滚源码上真实失败，随后修改源码；独立源码测试包 2/2 通过，governance 包 `go test -c` 只编译成功，没有运行 TestMain 或数据库测试。针对超时值、漏 defer cancel、反转 handed 条件的 3 项变异仅在自建独占复制树运行，均使源码测试失败；临时文件逐一移除，空目录删除。测试只解析源码，不能证明运行时 rollback 或锁释放。

最终源码 raw SHA `d2b6d5678914293a2d4d79c49c856aef8fdc8821fc929913a74638cfb7a4ab6a`；AST 测试 SHA `c82676665f2177ec4a58599804ad361cc7c52e185e69fa73f58472681ef9f977`；尚未执行的 DB panic 探针 SHA `50df2912530ba2f494afe46f0f8f28f1fc1e070150b797bb001869b56f951a2b`。RUN-006 和 Gate3 状态不因此改变。
