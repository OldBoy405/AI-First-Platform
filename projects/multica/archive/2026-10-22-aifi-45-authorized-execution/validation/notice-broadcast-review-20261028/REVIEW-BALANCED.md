# STDD balanced：execution notice broadcast guard 独立复核

## 结论

独立子包的当前实现实测通过：5 个顶层测试、7 个子测试，全部通过，无跳过。静态对照修改前实现与测试 fixture，guard 覆盖的是预期的广播依赖业务路径，而不是编译错误或无效 fixture 导致的失败。**历史 RED 未独立运行或确认**：以下对修改前失败的描述是代码对照推断，不是本次实测 RED 证据，也不能据此宣称完成 RED→GREEN 独立复现。

## 范围与边界

复核对象均位于 `../multica/server/internal/governance/`：

- `execution_notice.go`：投递、恢复及广播依赖 guard。
- `execution_notice_test.go`：原父包集成测试的对应调整，仅静态检查。
- `noticeguard_test/execution_notice_test.go`：新独立子包测试，实测。

仅在 `../multica/server` 工作目录执行：

```text
go test -v -count=1 ./internal/governance/noticeguard_test
```

Go 子进程环境中按名称不区分大小写剔除 `DATABASE_URL` 和所有以 `PG` 开头的变量。未运行父包测试或父包 `TestMain`；未使用数据库、容器或真实通知。内存 `events.Bus` 与测试 loader 仅用于单进程测试。Go 版本为 `go1.27.1 windows/amd64`。

## 实测结果

```text
=== RUN   TestDeliverRejectsMissingBroadcastBeforeDB
--- PASS: TestDeliverRejectsMissingBroadcastBeforeDB (0.00s)
=== RUN   TestRecoveryRejectsMissingBroadcastBeforeDB
--- PASS: TestRecoveryRejectsMissingBroadcastBeforeDB (0.00s)
=== RUN   TestSilentEventsNeedNoBroadcasterOrDB
=== RUN   TestSilentEventsNeedNoBroadcasterOrDB/run-node-started
=== RUN   TestSilentEventsNeedNoBroadcasterOrDB/run-node-ack
=== RUN   TestSilentEventsNeedNoBroadcasterOrDB/run-node-completed
=== RUN   TestSilentEventsNeedNoBroadcasterOrDB/repair-progress
--- PASS: TestSilentEventsNeedNoBroadcasterOrDB (0.00s)
    --- PASS: TestSilentEventsNeedNoBroadcasterOrDB/run-node-started (0.00s)
    --- PASS: TestSilentEventsNeedNoBroadcasterOrDB/run-node-ack (0.00s)
    --- PASS: TestSilentEventsNeedNoBroadcasterOrDB/run-node-completed (0.00s)
    --- PASS: TestSilentEventsNeedNoBroadcasterOrDB/repair-progress (0.00s)
=== RUN   TestBusBroadcasterRejectsMissingDependencies
=== RUN   TestBusBroadcasterRejectsMissingDependencies/nil_bus
=== RUN   TestBusBroadcasterRejectsMissingDependencies/nil_loader
=== RUN   TestBusBroadcasterRejectsMissingDependencies/nil_loaded_item
--- PASS: TestBusBroadcasterRejectsMissingDependencies (0.00s)
    --- PASS: TestBusBroadcasterRejectsMissingDependencies/nil_bus (0.00s)
    --- PASS: TestBusBroadcasterRejectsMissingDependencies/nil_loader (0.00s)
    --- PASS: TestBusBroadcasterRejectsMissingDependencies/nil_loaded_item (0.00s)
=== RUN   TestBusBroadcasterPublishesLoadedItemAndPropagatesError
--- PASS: TestBusBroadcasterPublishesLoadedItemAndPropagatesError (0.00s)
PASS
ok  github.com/multica-ai/multica/server/internal/governance/noticeguard_test  0.890s
```

## 测试与实现检查

- `validEvent()` 提供非静默 kind、必填消息字段及可解析的 workspace/recipient UUID。投递、恢复的 nil broadcast 测试传入 nil pool，要求返回包含 `broadcast` 的错误且不出现 delivered/count；panic 会被测试报告为失败。这使 guard 必须在数据库访问之前命中，而不是因错误 fixture 提前返回其他错误。
- 四种静默事件分别验证在 nil pool、nil broadcaster 下直接返回 silent，且不创建或广播。实现先判静默，再进行消息和 UUID 校验；非静默投递先构造消息、解析 UUID，然后拒绝 nil broadcast，随后才开始事务。恢复先解析 workspace UUID，再拒绝 nil broadcast，随后才查询。
- `BusBroadcaster` 的 nil bus、nil loader、loader 返回 nil item 均被测试要求报错；后两项还断言不发布事件。loader 错误以 `errors.Is` 验证传播且无发布；成功路径验证一次 `inbox:new` 的 workspace、system actor 与载入 item 的 id/title。
- 修改前的静态 diff 显示：投递和恢复没有 nil broadcast 的前置 guard，因此上述 nil pool fixture 会触发 panic；nil bus 原先返回 nil，nil loader 或 nil item 原先使用简化 fallback item。这是针对目标行为的负向信号，但没有实际运行修改前版本，**不能将推断当作已观察 RED**。
- 父包集成测试中三处原本传 nil 的非实时测试改为显式测试专用 noop broadcaster；原本需要验证消息构造错误的 nil broadcaster 调用仍先命中构造错误。父包测试本次未运行。

## 覆盖限制与剩余风险

- 独立子包不验证数据库事务、去重、持久化状态、提交后故障、恢复重播及实际通知端到端；这些不能由本次 GREEN 推断。
- 调用方提供非 nil 的 `BusBroadcaster` 闭包时，nil bus/loader 等内部依赖错误是在闭包执行时发现；投递路径可能已经提交 pending 行，并非所有依赖都在触 DB 前验证。
- 内存 bus 的成功发布不证明有订阅者或外部接收者实际收到消息；测试专用 noop 也会模拟广播成功，不能证明实时通知。
- 本次未对修改前版本做隔离执行、变异测试或复核历史 RED 日志，故不能证明历史 RED 来源或测试对所有回归的敏感度。

## 原始文件 SHA-256

下列是复核时对工作区文件原始字节计算的 SHA-256；实测前后相同。它们不是 Git HEAD 内容哈希，也不是规范化行尾后的哈希。复核期间未修改这三个文件。

| 相对 `../multica/server/internal/governance/` 路径 | 原始 SHA-256 |
|---|---|
| `execution_notice.go` | `821a334fcaedf3fa4d36a946187f121708d445b91ce5b01ecb2fd3b51de71fd2` |
| `execution_notice_test.go` | `8d9a72282cb77f558915b621f62111aec9e8234c77a0a1f4fff87586889faa8f` |
| `noticeguard_test/execution_notice_test.go` | `e90f0f215b9c65e4173b05804f81470487d3eb6966130ce9329970214cb76966` |

复核时前两个文件已处于修改状态，独立子包为未跟踪内容；上述状态并非此次复核产生。静态 diff 的 Git HEAD 为 `81e5293adc758e392a045026cf81ec5cc1bac72d`。
