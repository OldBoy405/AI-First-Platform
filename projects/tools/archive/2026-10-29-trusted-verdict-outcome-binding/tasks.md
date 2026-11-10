# 2026-10-29-trusted-verdict-outcome-binding — tools（T 生产侧）任务清单

> 切片依据 [design](design.md)（S1）与 [M design](../../../multica/changes/2026-10-29-trusted-verdict-outcome-binding/design.md)（G1/C2/K1/K2）。只做 v2 verdict 签发面与共享向量，不动其他 5 个 operation。

## 1. trusted-merge-gate / v2 签发（P0）

- [x] 1.1 `OPERATIONS` 中 verdict 的 schema 改为 `execution-control-verdict/v2`；domain 仍为 `execution-verdict/v1`（domain 是 purpose 级，不随版本改）
- [x] 1.2 `verifyControlEnvelope` 增加 **仅 verdict** 的 payload 闭集校验：`schema/purpose/domain/scope/frame/request_id/epoch/sequence/previous_verdict_digest/result/effect/command_digest` 恰好齐全，多一个或少一个都拒绝；`effect ∈ {effect,no_effect}`；`command_digest` 为 64 位小写 hex
- [x] 1.3 导出 `verdictPayloadV2({scope, frame, requestId, epoch, sequence, previousVerdictDigest, result, effect, commandDigest})`，签发端与向量生成共用同一处构造，避免两处各拼一份
- [x] 1.4 `test/fixtures/control-vectors.json` 中 verdict 用例改为 v2（重算 `payload_b64`/`payload_sha256`/`digest`/`signature_b64`），其余 4 个用例与 `keys` 不动

## 2. 测试与验证（P0）

- [x] 2.1 TC-VT-004 → v1 schema、未知 effect、缺 `command_digest`、多余字段分别拒绝
- [x] 2.2 TC-VT-007 → v2 正例签名→验签往返，且与向量文件逐字节一致
- [x] 2.3 `node --test` 相关测试全绿
