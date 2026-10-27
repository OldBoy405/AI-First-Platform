# SC-TR-001 / SC-TR-002 证据（execution-control-protocol）

- 被测文件：`tools/skills/shared/crctl/scripts/lib/execution-control-protocol.mjs`
- 测试文件：`test/execution-control-protocol.test.mjs`（loader `runnode green protocol ./test/execution-control-protocol.test.mjs`）
- 源码 sha256（基线 = 恢复后）：`3c785ee4b2b4ac41134549e6f6cfbc931de71cba3941ca5e11cd26f5b3929f41`
- 原始 TAP：`protocol-mutations-20261027T160015Z.{green,m1,m2}.tap`

| 运行 | 命令 | exit | tests/pass/fail/skip | 结果 |
|---|---|---|---|---|
| green | `node --test --test-reporter=tap test/execution-control-protocol.test.mjs` | 0 | 2/2/0/0 | 两 leaf 全绿 |
| m1 | 同上，删去 `verifyControlEnvelope` 里 purpose/domain/scope 三段绑定检查 | 1 | 2/1/1/0 | `not ok 1 - verify purpose/domain/scope`（`Missing expected exception: purpose 错用`）；`ok 2` 不受影响 |
| m2 | 同上，删去 key-purpose 检查 | 1 | 2/1/1/0 | `not ok 2 - exact keys 与 key-purpose`（`Missing expected exception: attestation 签 resume`）；`ok 1` 不受影响 |

两次 mutation 各自只打红自己的 leaf（互为对照），恢复后 sha256 与基线一致，再跑 green 通过。

## 覆盖到的断言

`verify purpose/domain/scope`：合法 envelope 通过且 digest = sha256(payload bytes)；purpose/domain/scope 任一错用 → `EXECUTION_CONTROL_BINDING_MISMATCH`；payload 缺 scope（已签名）→ 同上；schema 错域 → 同上；payload 被改写但签名不动 → `EXECUTION_CONTROL_SIGNATURE_INVALID`；base64 非法字符/缺失 → `EXECUTION_CONTROL_INPUT_INVALID`。

`exact keys 与 key-purpose`：envelope 多字段 → INPUT_INVALID；attestation 签 `resume` / human 签 `command` → `EXECUTION_CONTROL_KEY_PURPOSE_INVALID`；未登记 key_id → KEY_INVALID；manifest 重复 key_id / key 条目多字段 / 相对路径 → TRUST_MANIFEST_INVALID；key 文件 sha256 与 pin 不符、key 位于 agent 可写根、非 Ed25519 公钥 → KEY_INVALID。

## 未覆盖（须后续叶补）

跨语言向量（与 Go 侧同一原字节互验，属 `TestChannelProtocol/cross_language_vectors`）、store 的 `ApplyOnce`/冻结帧链（SC-TR-003/004）尚未实现。
