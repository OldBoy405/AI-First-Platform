# 生产组合注入准入决策器（2026-11-09）

## 改了什么

`server/cmd/server/main.go`：`RouterOptions` 增加 `AdmissionDecider: governance.NewAdmissionDecider()`；`router.go` 在 `AIFIRST_ARCHITECTURE_RUNNER` 开启时要求非空决策器（缺失或 typed-nil 则 `os.Exit(1)`）。

修改前 `RouterOptions` 的注释把“生产注入”留给 Gate3，main 当时未注入；本次把注入与启动门一起落地，使 runner 启用时不会再静默走 legacy 路径。

## 证据

先前使用一次性 PG（tmpfs、随机端口/密码、仓库自身 `go run ./cmd/migrate up`，容器用后清理）。临时脚本未显式关闭容器网络，因此现有记录不能证明满足授权中的无外网隔离；以下仅为测试输出，不能作为符合该条件的验收证据。见 [执行偏差记录](../notice-execution-deviation-20261109.md)：

```
go test ./internal/governance -run 'TestAdmission' -count=1 -v
--- PASS: TestAdmissionDeciderPanicReleasesHeadLock
--- PASS: TestAdmissionGateStopsEnqueueUntilConsumptionCommits
--- PASS: TestAdmissionWaitingIsNotPersistedAsRunFailure
--- PASS: TestAdmissionGateHoldsNodeUntilConsumptionCommits
--- PASS: TestAdmissionWaitingIsNotAFailure
--- PASS: TestAdmissionGateLockBlocksRevocation (2 sub-cases)
--- PASS: TestAdmissionDeciderWaitsForCommittedConsumption
ok  github.com/multica-ai/multica/server/internal/governance  2.245s
```

`TestAdmissionDeciderWaitsForCommittedConsumption` 覆盖完整阶梯：无 head → `HEAD_UNAVAILABLE`；reject head → `HEAD_REJECTED`；approve 无消费 → `WAIT_CONSUMPTION`；有消费无 settlement/verdict → `WAIT_TRUSTED_T_COMMIT`；verdict 未上链 → `WAIT_TRUSTED_T_COMMIT`；链覆盖 → `ADMITTED`；链尾前进后仍 `ADMITTED`（后续帧不撤回）。

`setup.txt` 记录容器名/端口与 migrate 结果；`admission-test.log` 是原始 TAP 输出。

## 边界（不声称）

- 这是**决策器层**的真实 DB 证据，不是生产链路端到端：`ControlWorker.ApplyTx`（verdict 写入 + cursor 推进）仍无生产调用方，`cr_execution_tool_verdict` / `cr_execution_tool_cursor` 在生产不会产生行，因此生产上不会到达 `ADMITTED`，只会落在拒绝/等待态（`HEAD_UNAVAILABLE` / `HEAD_REJECTED` / `WAIT_CONSUMPTION` / `WAIT_TRUSTED_T_COMMIT`）。
- 决策器的 `s.request_id = cc.task_id` 假设在生产写入方（`ApplySensitiveActionTx` 用 SHA1 收据作 request_id）下不成立；该身份收敛与 ingest 一并归入载体 `2026-10-29-trusted-verdict-outcome-binding`。
- `cmd/server` 集成测试需 `scripts/aifi45-db/run.mjs` 注入的一次性身份，本次未运行，也不据此声称通过。
