## 结论

**通过，限于验签到首次查询的探针范围。** 不是仅编译通过：指定测试包实际运行并显示全部子测试 PASS。

- 两帧由真实 Node protocol signer 使用临时 Ed25519 密钥生成；scope 为指定 `store_id`/`lineage_id`。第二帧前驱是第一帧原始 payload 的 SHA-256。
- 两帧分别调用真实 `AppendVerdictFrameTx`，均命中假 `pgx.Tx` 的首次 replay 查询 sentinel，且断言**恰好一次查询**，可防止 query 0 假绿。
- 旧 scope、重标前驱/request/sequence/epoch、翻转签名均断言 `ErrControlStoreInvalid` 且查询数为零；签名负例还断言嵌套的 `ErrControlSignatureInvalid`。旧 scope 的两帧先独立验签成功，再被 writer 拒绝。

**限制：** sentinel 在首查处中断；未验证 cursor 连续性、实际插入、事务提交、数据库并发或生产信任根/接线。未运行数据库、容器或其他测试；未改文件。测试时已清除 `DATABASE_URL`/`PG*`。

## 原始文件 SHA-256

| 文件 | SHA-256 |
|---|---|
| `server/internal/governance/crosslang_test/writer_scope_test.go` | `5a0864eedbc492c74d19b67cb13a26461d061504fecf99af8aaea4ebe20cf1b5` |
| `server/internal/governance/crosslang_test/interop_test.go` | `bcec35e7f885ca209e03d3ccc0000cc73dae95d44e467be28e8a7aeb2317bed4` |
| `server/internal/governance/execution_control_store_state.go`（实际 writer） | `f437aa2e2a29e26e0744d68d6da226101de6af618043e3a3d14bddafe86d684f` |
| `server/internal/governance/execution_control_protocol.go` | `f808f2e4d2b112467707f9f2a2aa45db4adb98988ec8b330b26b1d5758ef2641` |
| `tools/skills/shared/crctl/scripts/lib/execution-control-protocol.mjs` | `0079ec97a6feb7d511e25d6f73f4f1550ace21aec25e49d5bad21333326f19ce` |
