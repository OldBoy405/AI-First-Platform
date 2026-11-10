# AIFI-45 双帧动态信封互操作：限定结果

源仓 `multica/server/internal/governance/crosslang_test/interop_test.go` 是独立 Go 测试子包，不运行 governance 包带数据库副作用的 `TestMain`。测试动态调用 tools 侧真实 Node signer/verifier，使用运行时生成的测试 Ed25519 密钥，生成两帧 verdict；Go 侧以实际 `VerifyControlEnvelope` 验证同一信封和原 payload 字节。第二帧签名 payload 中前驱值等于第一帧 payload 的 SHA-256，且分别检查域分离签名 digest 与裸 payload digest；两侧对签名篡改均拒绝。

作者及独立 balanced 复核分别在 `DATABASE_URL` 和 `PG*` 清空后执行 `go test -v -count=1 ./internal/governance/crosslang_test`，均为 1 个顶层测试及 4 个子测试 PASS、skip 0；独立审查及快照 SHA 见 `REVIEW-BALANCED.md` 和 `REVIEW-RECEIPTS.json`。没有真实密钥、数据库或容器操作。

后续 `writer_scope_test.go` 用真实 Node signer 的两帧调用真实 Go `AppendVerdictFrameTx`：正例在假事务首个查询处以 sentinel 中断，错误 scope、request/epoch/sequence/前驱和签名均在查询前拒绝。balanced 独立复跑与限定复核见 `REVIEW-WRITER-BALANCED.md`；这仍不是数据库写入测试。

这些只证明动态信封验签、正向前驱字段及 writer 验签前置互操作：通用验签器不校验链连续性；尚无真实数据库 cursor 与链尾状态下拒绝错误前驱、Node store digest 与 writer 入链、真实事务/cursor、可信 B 和真实 producer→ingest 的证据。**TC-RUN-003 仍 MISSING，44/49，Gate3 NO-GO。**
