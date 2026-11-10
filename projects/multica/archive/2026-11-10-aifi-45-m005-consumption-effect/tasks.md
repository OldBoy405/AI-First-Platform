# AIFI-45 M005 consumption-effect — 任务清单

## 1. 切片 S1：首次 consumption 签发 effect（P0）

- [x] 1.1 RED：TC-CE-001、TC-CE-002 写入 `execution_consumption_effect_test.go`，确认因缺少 effect 而失败
- [x] 1.2 GREEN：新增 `execution_consumption_effect.go`（`issueConsumptionEffectTx`），在 handler 的 `INSERT … RETURNING` 成功路径、commit 前调用
- [x] 1.3 REFACTOR + 修 `execution_admission.go` 陈旧注释

## 2. 切片 S2：链连续、跨 CR、重放与新 generation（P0，依赖 1）

- [x] 2.1 RED：TC-CE-003、TC-CE-004
- [x] 2.2 GREEN：补全 lineage 锁后守卫、cursor 取下一格、两个固定 keyID（如 S1 已满足则记录为「RED 未失败」并说明）

## 3. 测试与验证

- [x] 3.1 `scripts/aifi45-disposable/selections.json` 增加 `m005-consumption-effect`
- [x] 3.2 整组一次性库回归（含 TC-RUN-003 所在选择）
- [x] 3.3 `go build ./...`、`go vet`（governance、cmd/server）
- [x] 3.4 CUSTOM.md 登记；test-report.md
