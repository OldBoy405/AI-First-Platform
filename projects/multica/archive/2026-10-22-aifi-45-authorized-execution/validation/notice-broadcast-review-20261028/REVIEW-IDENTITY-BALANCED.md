# STDD balanced：notice identity guard 第二轮独立复跑

## 结论与执行边界

作者后续修订的独立子包实测通过：**6 个顶层测试、16 个子测试全部通过，无跳过**。本轮仅在 `../multica/server` 工作目录运行：

```text
go test -v -count=1 ./internal/governance/noticeguard_test
```

Go 子进程环境中按名称不区分大小写移除所有以 `DB`、`DATABASE`、`PG` 或 `POSTGRES` 开头的变量。未运行父包测试或父包 `TestMain`，未操作数据库、容器或真实通知。此次复跑只读源码和测试，不修改它们。

## 实测输出

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
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity/empty_map
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity/missing_id
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity/wrong_id
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity/non-string_id
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity/different_id_case
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity/missing_workspace
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity/wrong_workspace
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity/non-string_workspace
=== RUN   TestBusBroadcasterRejectsMismatchedItemIdentity/different_workspace_case
--- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity (0.00s)
    --- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity/empty_map (0.00s)
    --- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity/missing_id (0.00s)
    --- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity/wrong_id (0.00s)
    --- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity/non-string_id (0.00s)
    --- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity/different_id_case (0.00s)
    --- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity/missing_workspace (0.00s)
    --- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity/wrong_workspace (0.00s)
    --- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity/non-string_workspace (0.00s)
    --- PASS: TestBusBroadcasterRejectsMismatchedItemIdentity/different_workspace_case (0.00s)
=== RUN   TestBusBroadcasterPublishesLoadedItemAndPropagatesError
--- PASS: TestBusBroadcasterPublishesLoadedItemAndPropagatesError (0.00s)
PASS
ok  github.com/multica-ai/multica/server/internal/governance/noticeguard_test  0.870s
```

## 检查结果

- 身份负例共 9 个：空 map，以及 item ID 和 workspace ID 分别缺失、错误、非字符串、大小写不同。每个负例要求返回非 nil 错误，且监听到的 `inbox:new` 数量为零。
- 正例验证 loader 接收预期 workspace 和 item ID；匹配 item 发布一次，事件类型、workspace、system actor 和 payload 中的 id、workspace_id、title 均符合预期。loader 返回的 sentinel 错误通过 `errors.Is` 验证传播，且未监听到 `inbox:new`。
- 静默事件、投递与恢复的 nil broadcaster，以及 nil bus、nil loader、nil loaded item guard 均包含在本次通过的测试中。投递和恢复的 nil broadcaster 测试使用 nil pool，要求在 DB 访问前返回错误而非 panic。
- 测试使用的是**真实的进程内同步 `events.Bus`** 和测试 loader，并非 fake bus。零事件断言只订阅 `inbox:new`；不能将其描述为对所有事件类型的零事件断言。
- 静态实现检查：`BusBroadcaster` 在发布前要求载入的 `id` 和 `workspace_id` 是字符串，且分别与入参按字符串精确相等。该比较本身不验证 UUID 格式；大小写不同会被拒绝。

## 所审文件原始 SHA-256

以下为相对 `../multica/server/internal/governance/` 的文件原始字节 SHA-256；复跑前后相同。不是 Git HEAD 哈希，也未做行尾规范化。

| 文件 | 原始 SHA-256 |
|---|---|
| `execution_notice.go` | `3c523681b010b4c70f4ba96122d57851f21801c5bef4e9ea9b9c7727f819085f` |
| `execution_notice_test.go` | `8d9a72282cb77f558915b621f62111aec9e8234c77a0a1f4fff87586889faa8f` |
| `noticeguard_test/execution_notice_test.go` | `184f920c7277e1684d8c2a29c139bff8eb6e5bb990b435e8874c5d990cd49def` |

## 覆盖限制

- 本轮无法验证数据库事务、持久化状态及恢复路径中的 workspace 规范化；未运行父包的数据库集成测试。
- 本轮不能证明实际通知送达或存在真实订阅者，也不能以进程内 bus 的发布成功替代端到端送达证据。
- 身份负例只断言非 nil 错误，不逐项验证错误内容；所测范围不覆盖所有可能的输入，例如两侧相同的空字符串或其他非 UUID 字符串。
- 未运行修改前版本或变异测试；本轮 GREEN 不是独立实测 RED 的证据。
