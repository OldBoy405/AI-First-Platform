# 全量门禁报告（gate）

- at: 2026-10-25T13:41Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `gate-20261025T113000Z-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs`；服务包被 runner 拒绝，未绕过。

## 结论：FAIL / NO-GO

实际运行三包中两包出现失败（handler 3、daemon 33），service 全量因 runner 包白名单拒绝而未执行；DB/原库完整性门禁均通过，源码 20/20 前后未漂移。工具全量 1058/1057/0/1 通过（1 个 Windows symlink SKIP）。

## 1. 冻结核验

- multica freeze：`gate-20261025T113000Z-freeze-manifest.json`，20 项，sha256 `93ca4614bce1451da46267c4e614b8efff893a8340844e6617f726ebaa8a3e80`；三条实际运行包前后均 20/20。
- tools freeze：`gate-20261025T113000Z-tools-manifest.json`，4 项，sha256 `d8b4b366daf579adad345b62feae6727c6ce414962c5eb069e03acc3e50f2266`；tools 跑前/跑后 4/4。
- 最终 multica 20/20：`true`；tools 4/4：`true`。
- 关键产品变化已核对：`server/internal/daemon/daemon.go:852` `d.recordConsumptionAfterDelivery = true`（消费记录开启；准入未开启）。

## 2. 四包计数

| # | 包 | 状态 | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | 20/20 前/后 |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 1 | `./internal/governance` `^Test` + 643/644/645 | 完成 | `a1512737f2742698` | 0 | 921 | 920 | 0 | 1 | 832 | true/true |
| 2 | `./internal/handler` `^Test` | **FAIL** | `36b37989563a5e78` | 1 | 4557 | 4507 | 3 | 47 | 4130 | true/true |
| 3 | `./internal/daemon` `^Test` | **FAIL** | `91b77605c8d15378` | 1 | 2155 | 2024 | 33 | 98 | 1865 | true/true |
| 4 | `./internal/service` `^Test` | **未执行** | — | — | — | — | — | — | — | pre true / post n/a |

- service 拒绝原因：`scripts/aifi45-db/run.mjs:64` 的 approved-package 白名单只有 `./internal/governance`、`./internal/handler`、`./internal/daemon`、`./cmd/server`、`./pkg/protocol`，不含 `./internal/service`；runner 在创建 DB/journal 前退出。未修改 runner、未绕过、未生成 `.meta.json`。
- 实际运行三条均未触发 timeout：governance 正常返回，handler 113s、daemon 40s；均在 runner 300s 子进程上限内。service 未进入运行阶段。

## 3. 原库一致性 / DB 门禁

| 包 | rows | tables | sum(count) | approvals | before=after | before=preflight | release | 遗留 OID | catalog absence |
|---|---:|---:|---:|---:|---|---|---|---|---|
| governance | 219 | 137 | 6228 | 82 | true | true | sessions=0, locks=0 | 532761/532762 | true |
| handler | 219 | 137 | 6228 | 82 | true | true | sessions=0, locks=0 | 536168/536169 | true |
| daemon | 219 | 137 | 6228 | 82 | true | true | sessions=0, locks=0 | 539127/539128 | true |
| service | — | — | — | — | n/a | n/a | 未创建 | — | n/a |

- 三个实际运行包的 `original_unchanged=true`、`owned_resources_cleaned=true`、`error=null`；handler/daemon 虽测试失败，但原库仍逐字节一致，before/after 均等于 preflight（137 表 / 6228 行 / 82 审批）。
- 三条 runner 均在结束后验证 role/database 不存在；无遗留 owned 临时库/role。

## 4. 失败清单与归因

### 4.1 handler（3）

- `TestRollupTaskUsageHourlyIdempotentAndWatermark`：`dashboard_test.go:750` `no rows in result set`，查询 `task_usage_hourly_rollup_state WHERE id=1`。
- `TestRollupTaskUsageHourlyCapsWindowAtOneDay`：`dashboard_test.go:1285` 同一 rollup state 无行。
- `TestTaskSupplementClaimStartReplay`：`task_supplement_test.go:78` 期望 200，实际 409 `task claim is stale or task is no longer startable`。

### 4.2 daemon（33）

- `TestRefreshHealedVersion_KeepsHealedPairCurrentAfterInPlaceUpgrade`
- `TestLoadConfig_UsesCodexDesktopAppBundleFallback`
- `TestLoadConfig_UsesChatGPTAppBundleCodexPath`
- `TestLoadConfig_CodexDesktopFallbackDoesNotOverrideExplicitPath`
- `TestM26B2TestFactsPayload`
- `TestM26B2TestFactsPreserveFailures`
- `TestM26B4ScanEmitsIndependentTestEvent`
- `TestM26B4ScanTestOnlyAndReviewOnly`
- `TestM26B4CollectorKeepsBothReviewStages`
- `TestDshPluginPathDirs_FindsBothLayouts/flat`
- `TestDshPluginPathDirs_FindsBothLayouts`
- `TestLockReusablePriorEnvRootSurvivesWorkspacesRootSwap`
- `TestRunTaskDeclinesReuseWhenTheClaimedDirectoryIsSwappedBeforeUse`
- `TestListRuntimeLocalSkills_ClaudeEnabledPlugin`
- `TestListRuntimeLocalSkills_FollowsSymlinkedSkillDirs`
- `TestListRuntimeLocalSkills_CodexUsesSharedCODEXHOME`
- `TestListRuntimeLocalSkills_PerRootVisitedAllowsCrossRootSymlinkAlias`
- `TestHandleRuntimeGone_DistinctDeletionsWithinCoalesceWindowBothRecover`
- `TestListRuntimeLocalMcpServersClaudeEnabledPlugin`
- `TestMergeRuntimeAndAgentMcpConfigClaudeCombinesAndAgentWins`
- `TestShouldReusePriorWorkdirSquadLeaderRejectsSymlinkEscape`
- `TestRepoCheckoutReturnsRetryableBusyToCapableClient`
- `TestRepoCheckoutForwardsFresh`
- `TestRepoCheckoutForwardsIsolatedMode`
- `TestRepoCheckoutUsesTaskScopedProjectRefByDefault`
- `TestRepoCheckoutExplicitRefOverridesProjectDefault`
- `TestRepoCheckoutRejectsUnresolvableWorkdirWithTheReason`
- `TestRepoCheckoutRejectsAnotherTaskWorkdir`
- `TestRunTaskReusesPriorWorkdirForFreshSession`
- `TestRunTaskSquadLeaderReusesWorkdirBeforeGCMetaWritten`
- `TestRunTaskSquadLeaderDoesNotReuseExternalPriorWorkdir`
- `TestPruneWorktree_LegacyCacheFallbackSerializesWithCreateWorktree`
- `TestRunTaskCancelledWaitingForThePriorWorkdirStopsInsteadOfPreparing`

### 4.3 归因区分

- **未发现由本变更引入的失败证据**：冻结的消费客户端/投递记录用例在 daemon 全量中均 PASS，包括 `TestRequestExecutionConsumptionClient`、其 4 个 refusal 子例、`TestRecordDeliveredConsumptionSwitch`；`recordConsumptionAfterDelivery` 的开启没有导致消费路径失败。
- handler 失败点位于 dashboard rollup state 与 task supplement claim replay，不经过 `daemon.New()`/消费调用路径；handler 包也不在冻结 20 项内。daemon 失败点集中在 agent CLI/桌面 bundle、DSH/profile、Windows symlink/文件占用、Git 长路径、RepoCheckout/RunTask 夹具、crevents 阶段分类和 runtime-gone coalesce，均为既有环境/夹具/顺序状态类，不是消费记录开关路径。
- 因未做“变更前同环境全量基线”复跑，不能把上述全部严格证明为历史既有；故按“非本变更路径的既有/环境/夹具失败”记录，不修复、不折算 PASS。

## 5. SKIP 逐条

### governance（1）

- `TestReconcileLiveGitHub`

### handler（47）

- `TestRequireDaemonWorkspaceAccess_CacheHit`
- `TestRequireDaemonWorkspaceAccess_CacheMissBackfills`
- `TestMembershipCache_InvalidatedOnDeleteMember`
- `TestMembershipCache_InvalidatedOnUpdateMember`
- `TestMembershipCache_InvalidatedOnLeaveWorkspace`
- `TestMembershipCache_InvalidatedOnDeleteWorkspace`
- `TestRedisLivenessStore_TouchAndIsAlive`
- `TestRedisLivenessStore_TTLExpiry`
- `TestRedisLivenessStore_Forget`
- `TestRedisLivenessStore_BatchEmptyInput`
- `TestRedisLocalSkillListStore_CreateGetComplete`
- `TestRedisLocalSkillListStore_CreateWithoutMultiPermission`
- `TestRedisLocalSkillListStore_PopPendingAcrossInstances`
- `TestRedisLocalSkillListStore_PopPendingConcurrent`
- `TestRedisLocalSkillListStore_PendingTimeout`
- `TestRedisLocalSkillImportStore_PreservesCreatorID`
- `TestRedisLocalSkillImportStore_CreateWithoutMultiPermission`
- `TestRedisLocalSkillImportStore_CompletePreservesFiles`
- `TestRedisLocalSkillImportStore_PreservesConflict`
- `TestRedisLocalSkillImportStore_PopPendingAcrossInstances`
- `TestRedisLocalSkillListStore_PerRuntimeIsolation`
- `TestRedisLocalSkillListStore_PopPendingAtomicClaim`
- `TestRedisLocalSkillImportStore_PopPendingBatch`
- `TestRedisModelCatalogCache_RoundTrip`
- `TestRedisModelCatalogCache_SkipsUncacheableResults`
- `TestRedisModelCatalogCache_InvalidateAndExpiry`
- `TestRedisModelCatalogCache_DropsUndecodableSnapshot`
- `TestRedisModelListStore_CreateGetComplete`
- `TestRedisModelListStore_CreateWithoutMultiPermission`
- `TestRedisModelListStore_PopPendingAcrossInstances`
- `TestRedisModelListStore_PopPendingConcurrent`
- `TestRedisModelListStore_PendingTimeout`
- `TestRedisModelListStore_RunningTimeout`
- `TestRedisModelListStore_HasPending`
- `TestRedisUpdateStore_CreateGetComplete`
- `TestRedisUpdateStore_CreateWithoutMultiPermission`
- `TestRedisUpdateStore_PopPendingAcrossInstances`
- `TestRedisUpdateStore_ReportAndPollAcrossInstances`
- `TestRedisUpdateStore_FailAcrossInstances`
- `TestRedisUpdateStore_RejectsConcurrentActive`
- `TestRedisUpdateStore_RunningTimeoutClearsActive`
- `TestRedisUpdateStore_PopPendingConcurrent`
- `TestFetchFromSkillsSh_AnthropicPptxIntegration`
- `TestRedisWebhookRateLimiter_RejectsAboveLimit`
- `TestRedisWebhookIPRateLimiter_HasSeparateBudgetFromTokenLimiter`
- `TestRedisSlidingWindowRateLimiter_SeparatesInvitationNamespaces`
- `TestRedisSlidingWindowRateLimiter_PreservesWebhookFailOpenAndExposesErrors`

### daemon（98）

- `TestResolveAgentEntry_SelfHealsAfterInPlaceUpgrade`
- `TestResolveAgentEntry_RejectsBelowMinVersionAfterUpgrade`
- `TestResolveAgentEntry_ReturnsVersionPairedWithCachedPath`
- `TestResolveAgentEntry_HealedPathWinsOverReappearingPinnedPath`
- `TestResolveAgentEntry_UninstalledLeavesEntryUnchanged`
- `TestProbeDshMulticaProfile`
- `TestProbeBuiltinRuntime_DshFailureWithProfileInstalledIsNotCondemned`
- `TestProbeAgentCLIsDiscoversDshWithoutMulticaProfile`
- `TestProbeBuiltinRuntime_DshWithoutMulticaProfile`
- `TestProbeAgentCLIsUsesDshDesktopAppBundleFallback`
- `TestProbeAgentCLIsIgnoresNonExecutableDshBundle`
- `TestProbeBuiltinRuntime_DshThatCannotRunIsNotAProfileVerdict`
- `TestProbeAgentCLIs_DiscoversPiAndOmpSeparately`
- `TestRegisterRuntimes_PiAndOmpBothReachTheServer`
- `TestResolveAgentExecutablePath_PreservesDispatchShimName`
- `TestResolveAgentExecutablePath_CanonicalizesOrdinaryVersionTarget`
- `TestLoadConfig_CompletedTaskTTLDefaultsDisabledOnSelfHostAndReadsEnv`
- `TestLoadConfig_WSClaimPollIntervalPrecedence`
- `TestLoadConfig_CompletedTaskTTLDefaultsBoundedOnOfficialCloud`
- `TestResolveAgentsViaLoginShell_ResolvesViaInteractiveShell`
- `TestLoadConfig_DiscoversQwenCode`
- `TestLoadConfig_SkipsMulticaHooksShadowingAgentBinaries`
- `TestLoadConfig_SkipsMulticaHooksFromLoginShellFallback`
- `TestLoadConfig_AutoUpdateDefault_SelfHostOff`
- `TestLoadConfig_CodexHandshakeTimeout`
- `TestLoadConfig_CodexTurnInterruptTimeout`
- `TestLoadConfig_CodexFirstTurnNoProgressTimeout`
- `TestLoadConfig_CodexFirstTurnTimeoutEqualToSemanticWarns`
- `TestLoadConfig_ToolWatchdogDefaultsToIdleWatchdog`
- `TestLoadConfig_CodexSemanticInactivityDerivesFromWatchdog`
- `TestLoadConfig_OpenCodeIdleWatchdog`
- `TestLoadConfig_AutoUpdateDefault_CloudOn`
- `TestLoadConfig_AutoUpdateEnv_ForcesOnForSelfHost`
- `TestLoadConfig_AutoUpdateEnv_ForcesOffForCloud`
- `TestLoadConfig_AutoUpdate_NoFlagWinsOverCloudDefault`
- `TestLoadConfig_AutoReload_DefaultsOnEvenForSelfHost`
- `TestLoadConfig_AutoReload_NotGatedOnAutoUpdateEnv`
- `TestLoadConfig_AutoReload_OffSwitches/env_false`
- `TestLoadConfig_AutoReload_OffSwitches/env_0`
- `TestLoadConfig_AutoReload_OffSwitches/env_off`
- `TestLoadConfig_AutoReload_OffSwitches/flag_or_config_file`
- `TestLoadConfig_AutoReload_OffSwitches/flag_beats_a_truthy_env`
- `TestResolveAgentsViaLoginShell_StripsAliasShadowing`
- `TestResolveAgentsViaLoginShell_HardTimeoutOnBackgroundedStdout`
- `TestLoadConfig_SkipsLoginShellWhenLookPathSucceeds`
- `TestProbeAgentCLIsIgnoresNonExecutableCodexBundle`
- `TestLoadConfig_AppliesBackendOverridesFromConfigFile`
- `TestLoadConfig_BackendOverrides_BackwardCompat_NoConfigFile`
- `TestLoadConfig_BackendOverrides_MalformedConfigFileNonFatal`
- `TestCursorSupplementHookCommandRequiresInstallableHooks`
- `TestHermesPreparedSessionReachability`
- `TestExecuteAndDrain_PiTurnErrorOutranksIdleWatchdogCancellation`
- `TestExecuteAndDrain_PiWithoutTurnErrorKeepsIdleWatchdogResult`
- `TestExecuteAndDrain_PiTurnErrorOutranksUpstreamCancellation`
- `TestExecuteAndDrain_PiWithoutTurnErrorKeepsUpstreamCancellation`
- `TestProvisionDshMulticaProfile_UnconfiguredIsANoOp`
- `TestProvisionDshMulticaProfile_InstallsTheFirstWorkingCandidate`
- `TestProvisionDshMulticaProfile_ForwardsTheSpecVerbatim`
- `TestProvisionDshMulticaProfile_ReportsEveryCandidateFailure`
- `TestProvisionDshMulticaProfile_ExitZeroWithoutAProfileIsAFailedCandidate`
- `TestProvisionDshMulticaProfile_FailedInstallLeavesTheProfileDirectory`
- `TestProvisionDshMulticaProfile_PreservesPreexistingProfileOnFailure`
- `TestProvisionDshMulticaProfile_FailedInstallKeepsNonSkeletonProfiles`
- `TestStartDshProfileProvision_RunsAtMostOnce`
- `TestStartDshProfileProvision_KicksDiscoveryWhenTheInstallFinishes`
- `TestStartDshProfileProvision_SuccessWithoutAProfileWithdrawsTheWait`
- `TestProvisionDshMulticaProfile_CancellationKillsTheWholeTree`
- `TestExecutionBindingRelayHelperProcess`
- `TestExecutionTrustRefusesLinkedRootInsideWorkspace`
- `TestPruneWorktreePreemptionCleansLocksBeforeTaskStarts`
- `TestLockReusablePriorEnvRootSurvivesRetargetAfterValidation`
- `TestValidateLocalPath`
- `TestHandleModelList_CustomOmpCompatibilityTarget`
- `TestResolveTaskModelSelectionKeepsLiveOnlyCodexOverridesOnFallback`
- `TestMuseDetectedThroughLoginShell`
- `TestOpenCodeV2RefusesSynthesizedMCPWithoutAgentConfig`
- `TestDetectBuiltinRuntimes_DoesNotRetryWhenSelfHealBurnsTheWindow`
- `TestDetectBuiltinRuntimes_SelfHealRejectionIsABelowMinimumVerdict`
- `TestTaskTempDirSurvivesGCWhileTheRunHoldsIt`
- `TestRunTaskPreservesProviderCostWithoutTokens`
- `TestRunTask_InjectsPrivateTaskTempDir`
- `TestRunTask_TaskTempBaseOverride`
- `TestRunTask_TaskTempBaseInvalidFailsStartup`
- `TestAgentCLIGuardDetectsSwallowedFailure`
- `TestCleanTaskArtifacts_ManagedPathDoesNotFollowSymlinks/leaf`
- `TestCleanTaskArtifacts_ManagedPathDoesNotFollowSymlinks/parent`
- `TestCleanTaskArtifacts_DoesNotFollowSymlinks`
- `TestExecuteAndDrain_CodexInactivityReportsMCPToolResultTranscript`
- `TestManagedArtifact_DirectRemovalDoesNotFollowLinks/leaf`
- `TestManagedArtifact_DirectRemovalDoesNotFollowLinks/parent`
- `TestManagedArtifact_DirectRemovalMatchesTreeWalk/leaf_symlink`
- `TestCleanTaskArtifacts_UsesLiteralTrackedPaths/:(top)fixture`
- `TestCleanTaskArtifacts_UsesLiteralTrackedPaths/:(exclude)fixture`
- `TestManagedArtifact_DirectRemovalMatchesTreeWalk/parent_symlink`
- `TestScanDiskUsage_DoesNotFollowSymlinks`
- `TestAgentCLIGuardFailsClosedWhenSetupFails`
- `TestLockReusablePriorEnvRootNeverWritesOutsideWorkspacesRoot/symlink_inside_the_root_pointing_outside_it`
- `TestCleanTaskArtifacts_UsesLiteralTrackedPaths/star*fixture`

### service
- 未执行，无 SKIP 记录。

## 6. tools 全量（不占 DB）

命令：`cd C:/Users/GOBAO/Downloads/AI/tools && node --test --test-reporter=spec skills/shared/crctl/scripts/test/*.test.mjs`

| tests | pass | fail | skipped | duration |
|---:|---:|---:|---:|---:|
| 1058 | 1057 | 0 | 1 | 957.7s |

- 唯一 SKIP：`EXEC-12 受控文件自身为 symlink：拒绝写入`，原因 `当前环境无法创建 symlink: EPERM`（不计 PASS）。
- 无失败用例；tools manifest 4/4 跑前/跑后一致。

## 7. 明确未测项

- `./internal/service` 全量：runner 包白名单拒绝，未执行、未创建 DB；不能用其他包或直接 `go test` 冒充。
- coverage：runner 不支持 `-cover`，本轮未采集任何覆盖率。
- 未修复 handler/daemon 失败；未重跑变更前全量基线。
- 未签 activation 语义、隔离域、全局 C1；未做 Gate3/commit/push/release。

## 8. 边界

消费记录开关已开，但准入仍关闭；T 仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出。activation 记录不等于准入；语义推导待 Gate 确认。旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 个 major 未关闭。

## DB 权

**DB 单执行权已释放；无运行中测试；无遗留 owned 临时数据库/role。**
