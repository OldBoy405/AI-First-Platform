# AIFI-45 empty origin/digest 独立复跑

## 对象及基线

在 `multica/server` 执行 `go test -count=1 -json ./internal/governance/deploymentaccess_test`，Go `go1.27.1 windows/amd64`。使用环境白名单清除数据库连接变量，设置 `GOPROXY=off`、`GOWORK=off`，另设 `GOSUMDB=off`、`GOTOOLCHAIN=local`、`GOTELEMETRY=off`、`GOENV=off` 和 `GOFLAGS=-mod=readonly`。只运行独立 fakeTx 包；该包无 `TestMain`，未运行父包测试。

基线退出码 0，包通过：**7 个顶层、79 个 leaf 全部通过、0 skip**；stderr 为空。顶层按不含 `/` 的 run 事件统计，leaf 按没有后代 run 事件统计。原始 JSON 仅在临时目录解析，未留存。

测试前后 raw SHA-256 均与指定快照一致：

- `server/internal/governance/execution_deployment.go`：`0d9773985591f63035c7bc706d9e406e1a929f2bed990235b5d0d287cea96e0a`
- `server/internal/governance/deploymentaccess_test/execution_deployment_test.go`：`e556f9b8e532669cfbec72fb34b364d991842cb3d2aadb15d2a459d75d758032`

## 两个独立 overlay 变异

以 `mktemp -d` 创建本次执行独占的临时目录；分别生成仅删除单个空值守卫的源码副本及 `go test -overlay` 映射，不修改真实源码。每个变异针对 STOP_NEW 和过期 ACTIVE 各运行一个现有 fakeTx 子测试。下列四个子测试均实际启动并以 `CheckDeploymentAccessTx(complete_unsettled_request) = ExactRecovery, want Denied` 断言失败；两次变异测试均退出 1、stderr 为空，不是编译失败。

1. 删除 `in.PersistedOriginRef == ""` 守卫：
   - `TestRecoveryRejectsMissingOrInvalidIdentityFacts/stop_new/both_origins_empty`
   - `TestRecoveryRejectsMissingOrInvalidIdentityFacts/active_expired/both_origins_empty`
2. 删除 `in.PersistedDigest == ""` 守卫：
   - `TestRecoveryRejectsMissingOrInvalidIdentityFacts/stop_new/both_digests_empty`
   - `TestRecoveryRejectsMissingOrInvalidIdentityFacts/active_expired/both_digests_empty`

只删除本次独占目录内已知生成文件；随后确认目录为空、执行 `rmdir`，并确认目录已不存在。真实源码和测试文件的测试后 hash 如上。

## 边界与过程身份

未运行真实 DB、容器或真实 CR；未修改源码。上述 fakeTx 和定向变异不证明真实数据库行为、并发锁或生产安全。

环境自报 session ID `01a185c5-eccb-7020-aecc-d24bc422ce0e`，模型 `gpt-6.1-terra`，provider `OpenAIPersonal`；后端 session receipt 和 backend receipt 未知，不能独立证明后端身份。
