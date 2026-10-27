# SC-VC-001 证据（TestChannelFoundationSelection）

- 被测：`multica/server/internal/governance/execution_contract_selection.go`
- 测试：`server/internal/governance/execution_contract_selection_test.go`
- 源码 sha256（基线 = 每次 mutation 恢复后）：`565a562cc48136ceeb788416c4ec271188ec50fc41a86b58fd65f947b66685ec`
- 运行方式：`node scripts/aifi45-db/run.mjs ./internal/governance '^TestChannelFoundationSelection$' <prefix> -migration=server/migrations/648_cr_execution_control.up.sql`（每轮独占 nonce 库）
- 证据前缀：green `foundation-selection-green-20261027T160826Z`、m1/m2 `foundation-selection-{m1,m2}-20261027T160919Z`、m3 `foundation-selection-m3-*`

| 运行 | tests/pass/fail/skip | leaf_pass | 失败 leaf | exit |
|---|---|---|---|---|
| green | 4/4/0/0 | 3 | — | 0 |
| m1 去掉 strict 投影绑定检查 | 4/3/1/0 | 2 | `strict_field_deleted_binding_mismatch` | 1 |
| m2 缺 selection 时回落 legacy | 4/3/1/0 | 2 | `unknown_selection_rejected` | 1 |
| m3 目录条目只比 CR 不比 classification | 4/3/1/0 | 2 | `legacy_requires_catalog_proof` | 1 |

四轮均 `original_unchanged:true`、`owned_resources_cleaned:true`、`skip=0`；每次恢复后 sha256 与基线一致，green 复跑通过。

## 断言覆盖

- **strict 不可降级**：投影为 nil / `Present:false` / 空 digest / 不同 digest 四种情况全部 `T_VERDICT_BINDING_MISMATCH`；匹配时才返回 strict。删字段不落 legacy、不落 unknown。
- **Unknown 拒绝**：无 selection 且无目录 → `EXECUTION_SELECTION_UNKNOWN`；目录存在但未列该 CR → 仍 Unknown（证明是 per-CR 而非 per-scope）。
- **legacy 只由目录证明**：目录条目 `status=legacy` 才返回 legacy 且带 `provenance_digest`；`status=unknown` 不算；目录 payload 不可解析不算；同 scope 下未列 CR 仍 Unknown。

## 过程记录（如实）

1. 首次 m3 注入写成 `if true {`，导致 `entry` 未使用 → **编译失败**，按纪律不算 RED，该次证据已删除重做。
2. 重做时发现 m3 同时打红 leaf 2：原因是 leaf 2 里含「目录 status 非 legacy」用例。已把该用例移到 leaf 3（`legacy_requires_catalog_proof` 的语义本就更贴），随后 m3 只打红 leaf 3。
3. m1/m2 在测试重排后各重跑一次，确保证据与当前测试文件一致。

## 未覆盖

reservation / dispatch root（SC-VC-002..004）、`55P03` 探针与 FreshWork（SC-VC-005）尚未实现。
