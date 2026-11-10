# test-go 重复选项切片：独立复核记录

本记录仅汇总本会话的两轮独立只读代码复核和 fake-Go 复跑；不是作者测试记录，也不代表 CI 临时数据库能力已完成。两轮测试的 SHA 不同，不得混为同一快照。以下 SHA-256 均为原始文件字节，未做行尾归一化。

## 复核对象与对照

| 对象 | raw SHA-256 |
|---|---|
| `multica/scripts/test-go.sh`，两轮源码 | `b009954bc50ac182de9137782195766db46950cca5dfadf20fae17af77c4f543` |
| `multica/scripts/test-go.test.sh`，第一轮旧测试 | `8a2229d9eed881de3407d085b8c8b5f6867d4ec126fd0da405aefeda66612d29` |
| `multica/scripts/test-go.test.sh`，第二轮最终测试 | `47ad3429a9850c379419d7c9f09c0b8e883ac26f3647bc2d32e5719c24a2b67e` |
| 本目录 `source-before/test-go.sh` | `6ea063a5b5eed74897468a35a404919a80f4a83b494208359f726a5e8f2b90c8` |
| 本目录 `source-before/test-go.test.sh` | `67d51ae935eae61980a91bb7e40da35f2fc33cd1d131f4d26d970de16a285214` |

相对 `source-before/test-go.sh`，最终源码在解析第二个 `--only` 时打印 usage 并退出 2，发生在任何 `go list` 或测试调用之前；前版会用后一个值覆盖前一个值。最终源码未改变默认双套件、`--race`、单次 `--only` 的路由或 guard 接线。

## 第一轮：旧测试 `8a2229…`

- 测前、测后最终源码 SHA 均为 `b009954b…`，旧测试 SHA 均为 `8a2229d9…`；上述两份 `source-before` 文件的 raw SHA 测前、测后也未变化。
- 运行 `bash scripts/test-go.test.sh`，测试创建 fake Go；后备 PATH 限定为 `/usr/bin`，运行前确认该 PATH 找不到 Go。输出 `test-go.test.sh: PASS`，退出码 **0**。
- 此版本测试 default、`--race`、带 `--race` 的单次 `--only` 两种顺序，以及四组重复参数。重复参数检查退出 2、usage、fake `go list` 与 `go test` 零调用。
- 独占 `TMPDIR=/tmp/aifi45-test-go-review.WuxxSI26h7`：测试后检查根目录为空，随后以 `rmdir` 删除。测试和 guard 的 EXIT trap 自行清理各自创建的子目录。
- 当时发现的测试盲区：成功 regular 路径没有核对 `go list` 精确次数；没有证明测试调用经 guard；单 `--only` 不带 `--race` 未单独覆盖。

## 第二轮：最终测试 `47ad3429…`

- 测前、测后源码 raw SHA 均为 `b009954bc50ac182de9137782195766db46950cca5dfadf20fae17af77c4f543`；最终测试均为 `47ad3429a9850c379419d7c9f09c0b8e883ac26f3647bc2d32e5719c24a2b67e`。执行所依赖的 guard 和命令名文件测前后也未变化：分别为 `f657e450f0d9c914d49fc2bc60e21f6ec91337e916d4e397312b7caef1d78a0a` 和 `79177235ee107d5ebaa32a0143389de3e60cb48139d9b6e39280d565e365cd6a`。
- 再次仅运行 `bash scripts/test-go.test.sh`，后备 PATH 为 `/usr/bin` 且事先确认找不到 Go；输出 `test-go.test.sh: PASS`，退出码 **0**。本轮在外层预设 `MULTICA_AGENT_CLI_GUARD_MARKER=external-canary`；测试脚本开始时 unset 该变量，fake `go test` 要求接收非空 marker。
- 成功路径比较完整 fake `go list` 日志：default、regular 及其 race 路径预期一次 `list ./...`，agent-only 预期零次；新增不带 `--race` 的 regular 和 agent 单选用例。重复参数断言保留。根据源码，两个真实测试分支均通过 `go-test-with-agent-cli-guard.sh` 调用 fake Go。
- 独占 `TMPDIR=/tmp/aifi45-test-go-review.EJRlUCfTU8`：测试后检查根目录为空，随后以 `rmdir` 删除。测试和 guard 的 EXIT trap 自行清理各自创建的子目录。

## 判定与限制

该重复选项切片在上述两个快照上分别通过独立 fake-Go 复跑；第二轮弥补了第一轮指出的三项覆盖缺口。输出仅为脚本汇总 PASS，逐项行为依据测试源码中的断言及成功退出分析，非逐项独立日志。

- 本会话**没有实测前版 RED，也没有执行源码或测试变异**；前版会接受重复参数、预计被新增断言捕获，是静态分析，不替作者声称已实测。
- marker 非空只是接线哨兵，不能证明 guard 的完整性或防止代码自行伪造 marker；本次未注入 fake `go test` 失败，未验证 sentinel 被调用时的失败处理。失败模式的 `go list` 次数也未逐例断言。
- 未运行真实 Go、DB、容器或真实 CR；没有验证真实包、CI 全路径、临时数据库 provisioner 或 TestMain 身份门禁。两轮均未修改源码或其他报告；本归档只新建本文件。fake 测试通过不解除既有 CI 临时数据库和 supervisor BLOCK。
