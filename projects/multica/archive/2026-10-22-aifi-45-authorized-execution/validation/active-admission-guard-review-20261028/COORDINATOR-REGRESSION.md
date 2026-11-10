# 协调会话局部回归

`multica/server` 下清除 `DATABASE_URL`、`PG*` 和 Windows Job probe 环境，设置 `GOPROXY=off`：

- `go vet ./internal/governance ./internal/governance/deploymentaccess_test`：exit 0。
- `go build ./...`：exit 0；未执行测试。
- `go test -json -count=1 ./internal/governance/deploymentaccess_test ./internal/governance/crosslang_test ./internal/governance/noticeguard_test`：exit 0，三个包均 PASS。按 Go JSON 中带 Test 字段的 `pass/fail/skip` 事件计数：
  - deploymentaccess：顶层 3/0/0，子测试事件 55/0/0。
  - crosslang：顶层 2/0/0，子测试事件 14/0/0；包含子测试分组事件，不应与仅计叶子的历史统计相加。
  - noticeguard：顶层 6/0/0，子测试事件 16/0/0。

均为无 DB 子包；不证明真实数据库、生产接线或实际通知送达。未运行 `cmd/server` 或 governance 父包的 TestMain，未接触容器。
