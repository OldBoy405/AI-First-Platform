# 准入事务的异常清理：作者记录

## 问题与修复

`decideUnderHeadLock` 原在已获取授权 head 锁、并调用 `AdmissionDecider` 后才安装持有者的 rollback defer。若锁函数或 decider 在此之前 panic / `runtime.Goexit`，且上层未终止进程，已借出的连接和锁可能遗失；这是源码和 pgx 生命周期分析，非真实故障复现。本次将现有的 `handed`/rollback guard 移到 `BeginTx` 成功后、上述调用之前，未改变成功后交接所有权；原有错误分支显式回滚保留。旧快照 raw SHA `39428a0cc2641f83549aa3e90251cf6daece1e5933406156f9692fc22a68e375` 保全于 `source-before/`；新源码 SHA `865821b5ec83c02a198f8ffd9bdbd0a94f7e9daae6ac44ca357f0b7f6280fe9e`。

## 验证及其限制

- `runnerquery_test/admission_cleanup_test.go` 初版 SHA `098978f972ee031d412110798df7d8a128cf153ab86ab9dfbc92f5ac8d164e2b`：源码更改前真实 RED；修复后独立包两项通过。独立审阅指出它会漏掉 ownership 倒置等变异，已将初版逐字节保全于 `source-review/`。
- 增强版测试 SHA `cf50c31196ca2c48247fadc3a631684d7fce3ee76728a68c9ab231a221d3cf57`：检查 BeginTx 错误检查、`!handed`、`context.Background()`、首次 lock/decider 前安装 guard、成功路径的单次交接。独立包两项通过、0 skip；作者在独占复制树中分别对旧源码、取反、提前交接、换 rollback context 运行增强版，四项均真实失败。该测试仍只解析源码，不能证明 panic 释放锁。`go build ./internal/governance` 通过。
- 新 `execution_admission_cleanup_test.go` 编写 panic 时对照 PostgreSQL 55P03 和释放后 UPDATE 一行的探针；初版 SHA `a6b6b540a43b1f7a0d3493bdde4e88c276d1f0affabd6fafafeee00f48e74851` 已保全于 `source-review/`。初版静态独立审阅指出取连接/清理无界及后验错误未区分；最终版 SHA `50df2912530ba2f494afe46f0f8f28f1fc1e070150b797bb001869b56f951a2b` 将探针及自身 rollback 设为有界并区分 55P03 / 其他错误，但依赖的 fixture 清理仍非全链路有界，最终版尚待独立复核。
- `go test -c -o <独占临时目录>/governance.test.exe ./internal/governance` 对最终版退出 0，仅编译，**未执行 TestMain 或该测试**。临时目录只含本次产生的可执行文件；核对后删除该文件及空目录。执行前仍须独立审查和安全隔离 DB 生命周期。
- 尚无真实 DB 的 panic、Goexit、取消、锁释放及并发证据。rollback 使用现有 `context.Background()`，网络卡住的风险未因本次修正消除。成功交接后的事务仍由调用者负责；此改动不构成 RUN-006 验收，也不授权生产接线。
