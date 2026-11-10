# 生产 runner 准入组合：缺失 decider 的防护计划（待安全复核）

**目标**：用户已授权 AIFI-45 默认拒绝生产入口接线。完成真实可信判定前，禁止唯一已发现的生产 runner 组装点在没有准入 decider 时运行旧的 nil → 放行路径。此切片不是完整接线、不是部署授权。

**现状**：`cmd/server/main.go` 调用 `NewRouterWithOptions` 未设置 `AdmissionDecider`；`router.go` 启用 `AIFIRST_ARCHITECTURE_RUNNER` 时将 nil 透传 `NewRunnerWithOptions`，runner 多处据此跳过门禁。`NewAdmissionDecider` 仍按 CR 而非 task generation 查询可信记录，不能直接当作已经安全的生产接线；可信 writer 的生产驱动未闭合。

**候选最小切片**：strong 只读设计审认为该防护方向可行但须先盘点 feature flag 测试、记录启用时无法启动的可用性变化；其未复核四条旧路径，不能作为最终代码审查。全 `server/` Go 测试源扫描仅发现 `internal/governance/runner_contract_test.go` 显式设置该变量，未发现 cmd/server 测试显式设置；外部环境仍可能影响测试和部署。
1. 保留 `NewRunner`/`NewRunnerWithOptions` 的历史测试基线；在唯一的 router 生产组装入口，开启 runner 时对配置缺失的 decider（包括接口中 typed-nil）拒绝启动，不启动任何 runner 事件、路由或扫描。既有 runner 关闭模式保持不变。只承诺防止该生产组合点无 decider，不冒称其他构造方式、未门控 effect 或任何非 nil 实现已经可信。
2. 将 decider 非空判定置于 governance 的最小 helper，通过外部 no-TestMain 包覆盖普通 nil、typed nil 和可用实现。对 router 用独立源码 AST 检查校验失败分支的先后与退出；AST 只证明结构，不能代替真实启动行为。先真实 RED，再最小 GREEN；不得运行父包 TestMain 或数据库。
3. 独立安全和测试审查，登记 multica CUSTOM，校验既有 integration tests 尚未运行；安全风险和可用性改变明确列示。main 目前不注入 decider，因此已启用 runner 的生产配置若部署该代码会拒绝启动；本轮不部署、不承诺本切片已可安全上线。

**后续**：以受锁可信证据绑定具体 effect/代次，接通可信 verdict ingress 与受保护 writer，解决 cursor/fence、readiness、停止准入及事务竞态，再依据跨仓合同接真实 decider 并用已批准的隔离 DB 各自验收 RUN。不可用该局部拒启动、组件测试或静态检查声称生产安全、RUN PRESENT 或 Gate3 PASS。
