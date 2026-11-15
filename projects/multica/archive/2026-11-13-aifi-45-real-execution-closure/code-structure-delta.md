# Code Structure Delta — 2026-11-13-aifi-45-real-execution-closure
> 生成时间: 2026-11-15T04:12:51.925043 | Git commit: 8eac1460e
> 置信度: 0.70 (AI-generated — 以源代码为准)

## 变更文件

- `scripts/aifi45-disposable/test-ownership.test.mjs`
- `scripts/aifi45-real-run/config.mjs`
- `scripts/aifi45-real-run/cr-workspace.mjs`
- `scripts/aifi45-real-run/cr-workspace.test.mjs`
- `scripts/aifi45-real-run/crctl-stage.mjs`
- `scripts/aifi45-real-run/crctl-stage.test.mjs`
- `scripts/aifi45-real-run/lifecycle.mjs`
- `scripts/aifi45-real-run/real-run.test.mjs`
- `scripts/aifi45-real-run/run.mjs`
- `scripts/aifi45-real-run/scenario-main.mjs`
- `scripts/aifi45-real-run/scenario-revoke.mjs`
- `scripts/aifi45-real-run/scenario-stub.mjs`
- `scripts/aifi45-real-run/smoke.mjs`
- `scripts/aifi45-real-run/stack.mjs`
- `scripts/aifi45-real-run/stack.test.mjs`
- `scripts/aifi45-real-run/stub-flow.mjs`
- `scripts/aifi45-real-run/stub-flow.test.mjs`
- `scripts/aifi45-real-run/stub-pi.mjs`
- `scripts/ci-scope.test.mjs`
- `server/cmd/server/execution_run_003_test.go`
- `server/internal/daemon/daemon.go`
- `server/internal/daemon/execution_binding_endpoint.go`
- `server/internal/daemon/execution_binding_endpoint_rec_test.go`
- `server/internal/daemon/execution_consumption_client.go`
- `server/internal/daemon/execution_control_recovery_d8_test.go`
- `server/internal/daemon/execution_control_worker_test.go`
- `server/internal/daemon/execution_node_preconsume_test.go`
- `server/internal/daemon/execution_node_trust_root_test.go`
- `server/internal/daemon/execution_preflight_test.go`
- `server/internal/daemon/execution_root_binding_test.go`
- `server/internal/daemon/execution_source_preconsume_test.go`
- `server/internal/daemon/execution_trust.go`
- `server/internal/daemon/execution_verifier.go`
- `server/internal/daemon/pipeline_task.go`
- `server/internal/daemon/types.go`
- `server/internal/governance/execution_admission_task_discovery_test.go`
- `server/internal/governance/execution_consumption.go`
- `server/internal/governance/execution_consumption_effect.go`
- `server/internal/governance/execution_control_reservation.go`
- `server/internal/governance/execution_control_store_state.go`
- `server/internal/governance/execution_control_store_state_test.go`
- `server/internal/governance/execution_revoke_resume_test.go`
- `server/internal/governance/execution_workspace_lock_test.go`
- `server/internal/handler/agent.go`
- `server/internal/handler/daemon.go`
- `server/internal/handler/pipeline_execution_contract_test.go`
- `server/internal/handler/workspace_delete_concurrent_test.go`
- `server/internal/handler/workspace_delete_no_recreate_test.go`