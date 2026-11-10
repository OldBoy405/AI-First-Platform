# AIFI-45 最新组合快照独立复跑

## 对象与环境

在 `multica/server` 对指定源码和独立测试包进行复跑；Go `go1.27.1 windows/amd64`。以环境白名单清除数据库连接环境变量，设置 `GOPROXY=off`、`GOWORK=off`，另设 `GOSUMDB=off`、`GOTOOLCHAIN=local`、`GOTELEMETRY=off`、`GOENV=off` 和 `GOFLAGS=-mod=readonly`。只执行 `./internal/governance/deploymentaccess_test`，该独立包无 `TestMain`；没有运行父包测试或其 `TestMain`。测试使用 fakeTx；未运行数据库、容器或真实 CR，未修改真实源码。

前后 raw SHA-256 均与目标相同：

- `server/internal/governance/execution_deployment.go`：`449216c3469c48cdc7bb33fd9e138bd632bfabf0c95815f891fb00bab446178a`
- `server/internal/governance/deploymentaccess_test/execution_deployment_test.go`：`2a5bcd5fae7d965a74a96263940c30aa32d36775882fbacdd7ac1cbfbd9a0de5`

## 基线

`go test -count=1 -json ./internal/governance/deploymentaccess_test` 退出 0，包通过：**7 顶层、75 leaf 全部通过、0 skip**；stderr 为空。顶层按无 `/` 的 run 事件统计，leaf 按无后代 run 事件统计。JSON 输出只在独占临时目录解析，未留存原始日志。

如实记录执行过程：第一次基线测试自身也退出 0，结果同为 7/75/0；但自写汇总校验误将数字 leaf 当作数组读取，导致脚本误报基线失败并跳过当次变异。修正汇总校验后完整复跑基线及以下变异，结果如上。

## 独立 overlay 变异

分别在独占临时目录生成源码副本与 `go test -overlay` 映射，每个副本只替换一个 guard，运行目标 fakeTx 子测试；完成后删除本次临时目录。均观察到目标子测试开始、失败和明确断言，包退出 1、stderr 为空，**不是编译失败**。

1. **缺失 IssuedAt**：将 `in.IssuedAt.IsZero() || (!expiresAt.IsZero() && in.IssuedAt.After(expiresAt))` 回退为仅在非零时检查过期。`TestRecoveryRejectsMissingOrInvalidIdentityFacts/stop_new/missing_issued_at` 断言失败：`CheckDeploymentAccessTx(complete_unsettled_request) = ExactRecovery, want Denied`。
2. **generation 零值**：将 `in.PersistedGeneration <= 0 || in.Generation <= 0 || in.PersistedGeneration != in.Generation` 回退为仅在两者均非零且不相等时拒绝。`TestRecoveryRejectsMissingOrInvalidIdentityFacts/stop_new/missing_generation` 出现相同的 `ExactRecovery, want Denied` 断言失败。

以上各只验证了一个 STOP_NEW 子案例及相应变异，不代表穷举所有状态或零值组合。

## 边界

这些结果仅证明该快照上指定 fakeTx 测试通过、两个定向回退可被对应断言检测；不代表安全闭环，也不验证 unsigned readiness、生产接线、真实数据库、锁与并发竞态。未就其他切片作完整安全审计。

过程身份自报：session `01a185c5-eccb-7020-aecc-d24bc422ce0e`；模型 `gpt-6.1-terra`，provider `OpenAIPersonal`；backend receipt 未知。
