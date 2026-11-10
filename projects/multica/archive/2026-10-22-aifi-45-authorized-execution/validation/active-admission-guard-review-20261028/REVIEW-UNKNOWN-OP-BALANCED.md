# AIFI-45 ACTIVE unknown-op 单切片独立审核

## 结论与范围

单切片静态审核及指定 fakeTx 测试通过；**未做独立变异，不能声称新测试已由本审核实证杀死 guard 回退**。这不是生产接线、真实数据库或端到端验收。

与 `source-unknown-op-before/` 比较，源代码仅在未过期 ACTIVE 分支收紧默认行为：5 个已知新增操作和 `complete_unsettled_request`、`bind_existing_mapping` 仍返回 `NewAdmission`；5 个审计操作仍返回 `AuditOnly`；其他非空 op 返回 `Denied`。空 op 返回输入错误。STOP_NEW、过期和缺失 head 分支未被此 diff 改动。静态上操作名按精确字符串匹配；新增测试的未知操作实际只覆盖 `future_operation`，未独立运行其他伪造变体。

全仓搜索 `CheckDeploymentAccessTx` 与 `DeploymentAccessInput`，只发现独立 fakeTx 包及父包数据库测试中的调用，**未找到生产调用者**；因此不能证明服务端路由或 DB 原事实接线已经实现或正确。

## 独立测试

在 `multica/server` 仅执行 `go test -count=1 -json ./internal/governance/deploymentaccess_test`，以环境白名单清除数据库连接变量，设置 `GOPROXY=off`、`GOWORK=off`，并使用 `GOSUMDB=off`、`GOTOOLCHAIN=local`、`GOENV=off` 和 `GOFLAGS=-mod=readonly`。退出码 0：**5 个顶层测试、61 个 leaf 通过、0 skip**。独立包无 `TestMain`；父包存在 `TestMain`，此次没有运行父包测试。测试仅使用 fakeTx，未运行数据库、容器或真实 CR，未修改源码。

测试前后两文件 raw SHA-256 一致：

- `multica/server/internal/governance/execution_deployment.go`：`dc6407f98b07fbd63d7c039a5db497a9540b3dd674206b320b3e31cd92a18e7b`
- `multica/server/internal/governance/deploymentaccess_test/execution_deployment_test.go`：`8dd07c9609f5657d39b45a991cc6ba2d18be8f9bd2167437187b09f2d5d69adf`

对照原始版本 raw SHA-256：

- `source-unknown-op-before/execution_deployment.go`：`f1e719d9388c09eadecc9da17aa21bdafb080265237fabd8b58dc0f50b728811`
- `source-unknown-op-before/execution_deployment_test.go`：`c30f2816bd0f48359941f1993f85273feb481bc2169b6abc688d0b5f68b573f0`

## 未完成与风险

本审核未在临时副本回退 guard，也未验证该回退触发的是期望断言失败而非编译错误。作者另有 overlay 变异报告 `AUTHOR-UNKNOWN-OP-MUTATION.md`；它不是本审核的独立变异结果，也未在此独立复核。

unsigned readiness、zero-value、未知状态、真实 DB 和锁竞态均未审结。未知状态在现有代码中落入非 ACTIVE 分支，不能据此宣称状态闭集已验证。fakeTx 不证明实际事务、并发或生产兼容性。

## 过程身份

- session 自报：`01a185c5-eccb-7020-aecc-d24bc422ce0e`
- 模型自报：`gpt-6.1-terra`；provider：`OpenAIPersonal`
- backend receipt：未知
