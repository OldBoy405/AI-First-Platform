# Runner 活跃 run 冲突回查的 pipeline 绑定

## 问题与修正

`upsertRunTx` 在插入冲突时把实际 `pipelineID` 传给 `findActiveRunTx`，但后者之前固定用 `PipelineIDs.ArchitectureDesign` 绑定 `pipeline_id=$3`。`runner_code.go` 的 `ensureWritebackRun` 使用同一个 upsert 创建 feature-writeback run；若出现冲突，旧实现可能错误回查 architecture run，或因找不到而失败。只有满足相应活跃行和冲突条件才会发生，不能从静态代码断言实际已发生。

本次仅将 `findActiveRunTx` 的 SQL 第三个绑定值改为调用方的 `pipelineID`，未增新生产入口，未更改 schema、锁、状态机或授权语义。

## 验证

- 修改前 `runner.go` raw SHA-256 `7dfcbb3c0b2dc5bfb568cb0368c0ab5572d034739f6116e4adc0bdefa35c6854`，逐字节保全在 `source-before/runner.go`。
- 新独立测试包 `server/internal/governance/runnerquery_test/active_query_test.go` raw SHA-256 `f535341a576aee2dae1dc0f2be8cd2acccb1e14918590e9476be485cb978afd8`；通过 Go AST 检查该事务查询的 SQL 谓词及 workspace、CR、pipeline 参数。它只验证源码，不连接数据库，不运行 governance 包的 TestMain。
- **RED**：在上述修改前源码运行 `go test -count=1 -json ./internal/governance/runnerquery_test`，选中 1 项，因 `query argument 4 must be pipelineID` 失败；不是编译错误或无测试。
- **GREEN**：源码改后 raw SHA-256 `faf7085c115e11fbe45da8685a15b37d76b88e6de2bc37d2dc206e1b0c877ed1`；相同命令 1 项 pass、0 fail、0 skip。`go build ./internal/governance` 退出 0。运行时 `GOPROXY=off`、`GOWORK=off` 并清除 DATABASE_URL/PG*。
- 未另存完整原始 stdout/stderr，本文件为作者记录；未做真实 PostgreSQL 冲突、事务锁或并发测试，也未执行真实 CR。

此修复只改变一个回查参数，不证明数据库唯一约束、冲突后行身份、完整交接及恢复链，更不关闭 CP-RUN-007 或授权生产派发。实际 code run 的生产创建入口、统一 wake/扫描与可信授权仍缺失。
