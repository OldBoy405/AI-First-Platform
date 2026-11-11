> **口径说明（2026-11-10 手工补注）**：`stdd structure delta` 取的是整个工作树 diff，因此下表还包含与本次无关的在途 AIFI-45 改动，并且可能漏掉新增文件。本 change 实际触及的 multica 文件如下：

> - `server/internal/governance/execution_control_protocol.go`
> - `server/internal/governance/execution_verdict_trust.go`
> - `server/internal/governance/execution_verdict_trust_test.go`
> - `server/internal/governance/execution_admission.go`
> - `server/internal/governance/execution_control_store_state.go`
> - `server/internal/governance/execution_control_protocol_test.go`
> - `server/internal/governance/execution_control_operation_domain_test.go`
> - `server/internal/governance/execution_verdict_attestation_test.go`
> - `server/internal/governance/crosslang_test/interop_test.go`
> - `server/internal/governance/crosslang_test/shared_vectors_test.go`
> - `server/internal/daemon/execution_control_worker_test.go`
> - `server/internal/daemon/execution_control_recovery_d8_test.go`
> - `server/cmd/server/execution_run_003_test.go`
> - `CUSTOM.md`

> 以源代码为准；下表仅作参考。

# Code Structure Delta — 2026-10-29-trusted-verdict-outcome-binding
> 生成时间: 2026-11-10T15:54:30.569789 | Git commit: 0f786836b
> 置信度: 0.70 (AI-generated — 以源代码为准)

## 变更文件

- `apps/desktop/src/main/auth-session-coordinator.test.ts`
- `apps/desktop/src/main/auth-session-coordinator.ts`
- `apps/desktop/src/main/index.ts`
- `apps/desktop/src/main/notification-gate.test.ts`
- `apps/desktop/src/main/notification-gate.ts`
- `apps/web/app/auth/callback/page-session.test.tsx`
- `apps/web/app/auth/callback/page.test.tsx`
- `apps/web/app/auth/callback/page.tsx`
- `packages/core/api/client.test.ts`
- `packages/core/api/client.ts`
- `packages/core/api/index.ts`
- `packages/core/api/request-session.ts`
- `packages/core/api/ws-client.test.ts`
- `packages/core/api/ws-client.ts`
- `packages/core/auth/store.test.ts`
- `packages/core/auth/store.ts`
- `packages/core/inbox/ws-updaters.test.ts`
- `packages/core/inbox/ws-updaters.ts`
- `packages/core/onboarding/store.test.ts`
- `packages/core/onboarding/store.ts`
- `packages/core/platform/auth-initializer.test.tsx`
- `packages/core/platform/auth-initializer.tsx`
- `packages/core/platform/core-provider.tsx`
- `packages/core/platform/session-cleanup.test.ts`
- `packages/core/platform/session-cleanup.ts`
- `packages/core/platform/session-renewal.test.ts`
- `packages/core/platform/session-renewal.ts`
- `packages/core/platform/storage.ts`
- `packages/core/realtime/auth-session.ts`
- `packages/core/realtime/provider-session.test.tsx`
- `packages/core/realtime/provider.tsx`
- `packages/core/realtime/use-realtime-sync-inbox.test.tsx`
- `packages/core/realtime/use-realtime-sync-invitations.test.tsx`
- `packages/core/realtime/use-realtime-sync.ts`
- `packages/views/auth/login-page-session.test.tsx`
- `packages/views/auth/login-page.test.tsx`
- `packages/views/auth/login-page.tsx`
- `packages/views/auth/use-logout.test.ts`
- `packages/views/auth/use-logout.ts`
- `scripts/aifi45-db/instance-intent-record.mjs`
- `scripts/aifi45-db/instance-intent-record.test.mjs`
- `scripts/aifi45-db/instance-intent-snapshot.test.mjs`
- `scripts/aifi45-db/instance-lifecycle.mjs`
- `scripts/aifi45-db/instance-lifecycle.test.mjs`
- `scripts/aifi45-db/instance-ownership.mjs`
- `scripts/aifi45-db/instance-ownership.test.mjs`
- `scripts/aifi45-db/run.mjs`
- `scripts/aifi45-db/run.test.mjs`
- `scripts/aifi45-db/supervisor-buffer-brand.test.mjs`
- `scripts/aifi45-db/supervisor-collector.mjs`
- `scripts/aifi45-db/supervisor-collector.test.mjs`
- `scripts/aifi45-db/supervisor-erase.test.mjs`
- `scripts/aifi45-db/supervisor-protocol.mjs`
- `scripts/aifi45-db/supervisor-protocol.test.mjs`
- `scripts/aifi45-disposable/provision.mjs`
- `scripts/aifi45-disposable/provision.test.mjs`
- `scripts/aifi45-disposable/run-selection.mjs`
- `scripts/aifi45-disposable/selection.mjs`
- `scripts/aifi45-disposable/selection.test.mjs`
- `scripts/test-go.sh`
- `scripts/test-go.test.sh`
- `server/cmd/server/execution_run_003_test.go`
- `server/cmd/server/integration_test.go`
- `server/internal/daemon/crevents.go`
- `server/internal/daemon/crevents_test.go`
- `server/internal/daemon/daemon.go`
- `server/internal/daemon/execution_control_recovery_d8_test.go`
- `server/internal/daemon/execution_control_worker.go`
- `server/internal/daemon/execution_control_worker_replay_memory_test.go`
- `server/internal/daemon/execution_control_worker_test.go`
- `server/internal/daemon/health_test.go`
- `server/internal/governance/authorizationscope/sufficiency.go`
- `server/internal/governance/authorizationscope/sufficiency_test.go`
- `server/internal/governance/crosslang_test/interop_test.go`
- `server/internal/governance/crosslang_test/shared_vectors_test.go`
- `server/internal/governance/crosslang_test/writer_scope_test.go`
- `server/internal/governance/crsync.go`
- `server/internal/governance/crsync_test.go`
- `server/internal/governance/deploymentaccess_test/execution_deployment_test.go`
- `server/internal/governance/deploymentaccess_test/readiness_scope_test.go`
- `server/internal/governance/dev_phase_cp_test.go`
- `server/internal/governance/execution_admission.go`
- `server/internal/governance/execution_authorization.go`
- `server/internal/governance/execution_authorization_routes.go`
- `server/internal/governance/execution_authorization_test.go`
- `server/internal/governance/execution_channel_reader.go`
- `server/internal/governance/execution_control_command_attestation_test.go`
- `server/internal/governance/execution_control_operation_domain_test.go`
- `server/internal/governance/execution_control_policy.go`
- `server/internal/governance/execution_control_policy_test.go`
- `server/internal/governance/execution_control_protocol.go`
- `server/internal/governance/execution_control_protocol_test.go`
- `server/internal/governance/execution_control_revoked_permit_test.go`
- `server/internal/governance/execution_control_settlement.go`
- `server/internal/governance/execution_control_settlement_test.go`
- `server/internal/governance/execution_control_store_state.go`
- `server/internal/governance/execution_control_store_state_test.go`
- `server/internal/governance/execution_deployment.go`
- `server/internal/governance/execution_merge_effect.go`
- `server/internal/governance/execution_merge_effect_test.go`
- `server/internal/governance/execution_notice.go`
- `server/internal/governance/execution_notice_wiring.go`
- `server/internal/governance/execution_notice_wiring_test.go`
- `server/internal/governance/execution_original_mapping.go`
- `server/internal/governance/execution_sensitive_action.go`
- `server/internal/governance/execution_verdict_attestation_test.go`
- `server/internal/governance/execution_verdict_trust.go`
- `server/internal/governance/execution_verdict_trust_test.go`
- `server/internal/governance/execution_wp4_slices_db_test.go`
- `server/internal/governance/noticeguard_test/execution_notice_test.go`
- `server/internal/governance/runner.go`
- `server/internal/governance/runner_integration_test.go`
- `server/internal/governance/runnerquery_test/active_query_test.go`
- `server/internal/governance/runnerquery_test/admission_cleanup_test.go`
- `server/internal/governance/runnerquery_test/router_admission_test.go`
- `server/internal/governance/settlementguard_test/settlement_test.go`
- `server/internal/governance/supervisorjob_test/job_windows_test.go`