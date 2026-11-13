# Spec: selection-reconciliation

> Change: 2026-11-12-fork-ci-test-evidence-trust | Auto-generated Human View

## Requirements

### Requirement: run-selection 的对账失败使 selection 失败；未配置 expected 的既有行为保持不变；node 单测进入 CI。

#### Scenario: SC-SEL-001

- **GIVEN** 一个配置了非空 expected 数组的 selection，go test -json 流缺少某个预期测试或含多余、重复事件，
- **WHEN** decideSelection 以 verifyGoTestSelection 的真实返回值判定。
- **THEN** SHALL status 不是 matched 时 ok 为 false，reasons 含该 reason 原文并输出 blocked=<reason>；status 为 matched 且其余判定通过时 SHALL ok 为 true。
- **AND** 单测 SHALL 使用 verifyGoTestSelection 的真实输出而不是手写 {matched, blocked} 形状；把决策函数改回读取 .matched 与 .blocked 的旧写法 SHALL 使该单测变红（变异验证记入证据）。

#### Scenario: SC-SEL-002

- **GIVEN** selections.json 中未设置 expected 的 selection（当前全部条目），
- **WHEN** decideSelection 与 run-selection 运行。
- **THEN** SHALL 沿用旧判定：test.code 为 0 且 fail 为 0 且 skip 为 0 且 pass 大于 0；PASS 与 FAIL 输出行 SHALL 逐字不变。
- **AND** run-selection.test.mjs 既有断言 SHALL 全部保持通过且不被改弱。

#### Scenario: SC-SEL-003

- **GIVEN** selection 的 expected 字段已存在但为空数组、非数组或元素非法，
- **WHEN** decideSelection 判定。
- **THEN** SHALL ok 为 false 且 reasons 含 EXPECTED_INVALID；SHALL NOT 静默当作未配置。

#### Scenario: SC-SEL-004

- **GIVEN** scripts/aifi45-disposable 下的 node 单测与 ci-paths.json 的 scope 映射，
- **WHEN** ci-scope 对「仅改 scripts/aifi45-disposable/**」的变更判定；检查 ci.yml 的 script-checks。
- **THEN** SHALL 该变更命中 scripts 与 backend scope；script-checks SHALL 含 node --test scripts/aifi45-disposable 的步骤，且 pg 依赖获取失败时步骤失败。
- **AND** 改 run-selection 不触发任何 CI job 的现状 SHALL 不再成立。
