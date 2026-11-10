# Go 测试入口空包保护：作者验证

## 范围

`scripts/test-go.sh` 的 regular 选择在 `go list ./...` 成功但过滤 agent 后为空时，旧代码将无包参数调用 `go test`，可能测试 server 当前目录。修复是在调用原有 guard 前报告空包并退出非零；不改 agent-only、race、普通非空包的选择及 guard。

`scripts/test-go.test.sh` 的 fake Go 增加空列表、仅 agent 和 list 失败场景，断言非零且没有 `go test` 调用；list 失败还断言原 77 状态。既有默认双分支、两种顺序、usage 校验继续执行。脚本使用自建临时目录并在 EXIT 删除；fake Go 不运行真实测试、数据库或容器。

## 实际观察

在 multica 根执行 `bash scripts/test-go.test.sh`：

1. 旧源码 + 新测试：exit 1，诊断 `empty: expected failure without running go test, got status 0`，实际旧版调用了 fake `go test`。失败是行为断言，不是构建或环境故障。
2. 最小修复后：exit 0，输出 `test-go.test.sh: PASS`，包括全部新增及既有断言。

输出为工具中观察到的内容，未另存原始日志。此切片不实现临时 PostgreSQL、正式迁移或 CI provisioning，也不解除 TestMain 的数据库身份门禁。

## Raw SHA-256

| 文件 / 快照 | SHA-256 |
|---|---|
| 修复前 `scripts/test-go.sh` | `83bc2f78fc95ff617328e525674f114e9e9b0cb3aab035cf67d1d4e0ca0581ea` |
| 修复后 `scripts/test-go.sh` | `6ea063a5b5eed74897468a35a404919a80f4a83b494208359f726a5e8f2b90c8` |
| RED 与 GREEN `scripts/test-go.test.sh` | `d87cc33f1e5f0c4c536c54601b7faabd2c7f25fdfaab8d47708e6044e3bcc082` |
