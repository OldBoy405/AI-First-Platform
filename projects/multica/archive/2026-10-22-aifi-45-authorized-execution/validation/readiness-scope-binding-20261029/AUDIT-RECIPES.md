# Audit scope 测试矩阵及变异

- 最终三文件 raw 字节快照位于 `source-audit-final/`。在 `readinessScopeTx` 中模拟 readiness 的 scope 筛选，分别覆盖 `checkpoint_ingest`、`verdict_ingest`、`original_bytes_query`、`no_effect_settlement`、`resume_intent`，与 ACTIVE、过期 ACTIVE、带 verdict_ref 的 STOP_NEW 交叉；每种同 scope 为正控、异 scope 断言 `ErrDeploymentNotReady` 且零写。该 STOP_NEW 带引用为合成输入：schema 列可空且无 mode/ref 联动约束，但未核真实历史数据。
- `AUDIT-RED.json` 以 Go overlay 在唯一拥有的临时目录将 readiness 查询 `WHERE request_id = $1::uuid AND scope = $2 FOR UPDATE`, `requestID, scope` 改为按 request ID 查询，其他源码不动；30 leaf 中 15 同 scope 通过、15 异 scope 命中语义断言，0 skip。变异文件 raw SHA 为 `f37f244df37dd80505514560ac41ff3b35fee21c03238f43420e9c66f1d67aeb`，文件未存档，配方及此前源快照可重现；隔离目录已按所有权和字节校验清理。
- `AUDIT-GREEN.json` 是作者对最终 live 源的完整无 DB fake-Tx 子包结果：9 顶层、152 leaf 通过、0 skip。只保存派生事件计数，不保存原始 stdout/stderr。该结果不证明真实 PG predicate、锁、签名、历史兼容性或生产入口。
