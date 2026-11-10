# Go 测试入口包安全：独立复审与复跑

## 范围和结论

复审 `../multica/scripts/test-go.sh` 的空 regular 包保护及其 fake 测试，结论是：最终快照的静态逻辑符合此切片目标，指定 fake 测试复跑通过；这不是对真实 Go 测试或 CI 的端到端验证。两轮都只允许运行 `bash scripts/test-go.test.sh` 作为测试，不运行真实 Go 测试、数据库或容器；另用 `sha256sum` 和 `git status --short` 做只读检查。测试与 guard 使用临时目录并通过 EXIT trap 清理。未改动 multica 源文件或既有报告；此前工作树脏改保留。

静态审阅确认：测试在 PATH 前放置自建 fake `go`，处理 `list`、`test`，其他子命令报错；guard 再将自身 sentinel 目录置于 PATH 前，但命令名单不含 `go`，故其调用仍解析到 fake。测试本身不启动真实 Go、DB 或容器。

## 两轮快照与实际复跑

均在 multica 根执行 `bash scripts/test-go.test.sh`，工具输出均为 `test-go.test.sh: PASS`（成功退出）；观察未另存原始运行日志。两轮分别在运行前后执行 `sha256sum scripts/test-go.sh scripts/test-go.test.sh` 和 `git status --short`：各轮两个 raw SHA 均前后一致，工作树状态输出也前后一致。

| 快照 | `scripts/test-go.sh` raw SHA-256 | `scripts/test-go.test.sh` raw SHA-256 |
|---|---|---|
| 第一轮，旧测试 | `6ea063a5b5eed74897468a35a404919a80f4a83b494208359f726a5e8f2b90c8` | `d87cc33f1e5f0c4c536c54601b7faabd2c7f25fdfaab8d47708e6044e3bcc082` |
| 第二轮，最终测试 | `6ea063a5b5eed74897468a35a404919a80f4a83b494208359f726a5e8f2b90c8` | `67d51ae935eae61980a91bb7e40da35f2fc33cd1d131f4d26d970de16a285214` |

第一轮 fake 只记录 `go test`，因此当时不能从日志证明 usage 和 agent-only 未调用 `go list`。第二轮对最终快照单独复审、复跑；新增独立 list 日志及相关断言，不能将这些新增覆盖追溯到第一轮。

## 最终快照观察

- `go list ./...` 成功但为空、或过滤 agent 后为空，脚本在 guard 和测试调用之前输出 `no regular Go packages found` 并非零退出；`go list` 失败的状态经赋值和 `set -e` 传播。测试在 `--only regular` 下验证这三种情况没有 fake `go test` 调用，失败注入状态为 77，并对前两种检查诊断。
- `--only agent` 静态上跳过 list 和空 regular 保护。最终测试对 `--only agent --race`、`--race --only agent` 检查 list 日志为空，并检查预期的限并发 agent 测试调用；regular 也检查两种选项顺序。
- 默认 `--race` 静态上先通过 guard 测试过滤后的 regular 包，再通过 guard 以 `-p 2 -parallel 2` 测试 agent；fake 测试检查两次调用的参数和顺序。guard 保留被测命令失败状态，发现 sentinel marker 时报告并失败，这是静态观察。
- 三个 usage 错误检查状态 2、usage 输出，以及 fake test 日志和合法 list 日志均为空。

## 未覆盖故障和边界

- fake 只在验证 `list ./...` 参数后记录 list；非法参数的 list 和其他 Go 子命令不入日志，故日志本身不能严格证明“任何 go 调用均未发生”。regular 成功和空包用例也未断言 list 日志次数或内容。
- 空包及 list 失败注入只在 `--only regular` 下测试；默认双路径遇到这些失败时不会继续执行 agent，是由脚本控制流静态判断，而非对应动态用例。agent-only 未在 list 故障模式下额外注入测试。
- list 失败测试断言 77，但未单独断言注入的错误文本；没有注入 fake `go test` 失败或 guard sentinel marker，故命令失败和 marker 的可见性未动态验证。也未验证真实 Go 的包枚举、真实测试或 DB 行为。
- 此切片不解决 disposable CI、临时数据库或 CI provisioning，也不解除已有数据库身份门禁。
