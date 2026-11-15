# Spec: ci-admin-test-ownership

> Change: 2026-11-15-multica-backend-tests-green | Auto-generated Human View

## Requirements

### Requirement: 对账能区分「声明为 ci-admin 的测试通过了」与「没跑或被跳过」：管理员步骤的 `go test -json` 事件流里， 每个 `owner: ci-admin` 的测试必须有且仅有一条顶层 `pass`；`skip`、`fail`、缺失、流不完整都使该步骤对账失败。

#### Scenario: SC-CAO-001

- **GIVEN** 一份好样本事件流：三个 ci-admin 测试各有一条顶层 pass，各包有包级 pass 结论，以换行结尾； 表里这三个条目为 `owner: ci-admin`，另有不相干的 independent 条目； 以及在好样本上分别构造的五个坏样本：其中一个测试 skip；其中一个测试缺失；其中一个测试 fail；流不以换行结尾；同一测试两条顶层 pass
- **WHEN** 对好样本与每个坏样本分别执行管理员流对账
- **THEN** SHALL 好样本对账通过（ok 为 true、problems 为空），每个坏样本都对账失败且 problems 指出具体的包与测试名（流不完整时指出流不完整）
- **AND** 不相干的 independent 条目不被要求出现在该流里
- **AND** 同一测试出现两条顶层 pass 时失败（要求「恰好一条」，不是「至少一条」）

#### Scenario: SC-CAO-002

- **GIVEN** 管理员 PostgreSQL（可建库）与已迁移或空的 `multica` 库；`DATABASE_URL` 指向它
- **WHEN** 运行 ci.yml 里该步骤的 `go test -json -run '^(…)$' ./cmd/backfill_codex_usage_cache ./internal/taskusagebackfill`，再对其输出执行管理员流对账
- **THEN** SHALL 3 个测试各一条 pass，对账通过，进程退出码为 0
- **AND** 真实 CI 中该步骤与对账均为绿（登记于交付 test-report）
