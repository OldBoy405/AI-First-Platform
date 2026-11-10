# TC-RUN-006 / TC-RUN-007 源码侧只读分析（STDD strong，第二轮）

> 性质：**只读静态分析快照**，不是验收证据，不是 TC 通过，不改变台账 MISSING、BUILD 状态或 Gate3 NO-GO。
> 未运行任何 DB、容器、`go test` 或生产任务；未修改 multica / tools 源码。
> 作者已开始独立测试，并可能修改 `execution_deployment.go` 等文件；**本报告只覆盖下述旧快照**，之后的改动须重新核对，不得把本报告结论沿用到新快照。

## 0. 快照与适用范围

| 项 | 值 |
|---|---|
| 仓库 | `C:/Users/GOBAO/Downloads/AI/multica`（M 仓） |
| HEAD | `81e5293adc758e392a045026cf81ec5cc1bac72d`（`test(execution): read the queue instead of the fake's own counter`） |
| 读取时刻 | 2026-10-28（UTC），报告写成于 2026-10-28T15:19Z |
| 读取时工作树已脏（另一会话未提交） | `CUSTOM.md`、`scripts/aifi45-db/{README.md,run.mjs,run.test.mjs}`、`server/cmd/server/execution_run_003_test.go`、`server/cmd/server/integration_test.go`、`server/internal/daemon/execution_control_recovery_d8_test.go`、`server/internal/daemon/execution_control_worker_test.go`、`server/internal/governance/{execution_admission_requirement_enqueue_test.go,execution_control_revoked_permit_test.go,execution_control_settlement_test.go,execution_control_store_state.go,execution_control_store_state_test.go,execution_notice.go,execution_notice_test.go,execution_verdict_attestation_test.go}`；未跟踪 `scripts/aifi45-db/instance-{intent-record,lifecycle}{,.test}.mjs` |
| 行号口径 | 读取时工作树。下表文件在读取时与写报告时均**未出现在 dirty 列表**，故行号对应 HEAD blob；脏文件（如 `execution_run_003_test.go`、`integration_test.go`）的行号只代表读取时工作树，可能已漂移 |

本报告引用、读取时为 clean 的文件（HEAD blob 前 12 位）：

| blob | 路径（相对 M 仓） |
|---|---|
| `41dc01f9874e` | `server/internal/governance/execution_admission.go` |
| `d6d1c5bf3465` | `server/internal/governance/execution_admission_gate.go` |
| `9f59b2e96e28` | `server/internal/governance/execution_head_lock.go` |
| `da3933c0b1e3` | `server/internal/governance/execution_consumption.go` |
| `ded6c3273348` | `server/internal/governance/execution_control_policy.go` |
| `416912ec6554` | `server/internal/governance/execution_deployment.go` |
| `22149fa3ef58` | `server/internal/governance/runner.go` |
| `433bdd9f68b9` | `server/internal/governance/runner_code.go` |
| `8be91d390859` | `server/internal/governance/runner_requirement.go` |
| `8b4f1a4bae7b` | `server/internal/governance/four_phase_dispatch_cp_test.go` |
| `61e446b46228` | `server/internal/governance/runner_periodic_resume_test.go` |
| `14349bd7f786` | `server/internal/governance/execution_deployment_retirement_test.go` |
| `686182a5af1a` | `server/internal/daemon/execution_control_worker.go` |
| `6cf501df9477` | `server/cmd/server/router.go` |
| `ad5dc888ba68` | `server/cmd/server/main.go` |
| `b702e05b0f72` | `server/cmd/server/runtime_sweeper.go` |
| `4ada34ae2991` | `server/migrations/644_cr_execution_consumption.up.sql` |
| `77390ad9a424` | `server/migrations/648_cr_execution_control.up.sql` |
| `f328b6f207a2` | `server/pkg/db/queries/agent.sql` |

下文路径均相对 `server/`。

## 1. 测试实际存在与命名

- `TestTC_RUN_006`、`TestTC_RUN_007` **全仓不存在**。`cmd/server` 只有 `execution_run_002_test.go`、`execution_run_003_test.go`、`execution_run_010_test.go`；拟新增的 `authorized_execution_integration_test.go` 不存在。
- 组件级相关测试（均不得登记为整 TC）：
  - `internal/governance/four_phase_dispatch_cp_test.go:181 TestMDispatch001`：code 子测直接调 `runner.ReconcileCode`（:234），code run 由测试直接 INSERT（`runner_code_test.go:13 seedCodeRun`）；使用 `insertingPipelineEnqueuer` 假 enqueuer。
  - `internal/governance/runner_periodic_resume_test.go:70/126/200 TestMTick003/004/005`：直接调 `ResumeActiveRuns`；源码探针（:333）只守 “不引用 `ResumePipelineNodeTask`”。
  - `internal/governance/execution_control_policy_test.go:53 TestChannelPolicyFacts`、`:218 TestChannelPolicyResume`（子测 `signed_resume` :300、`signed_resume_no_revive` :319）：只测函数本体。
  - `internal/governance/execution_deployment_test.go:86 TestChannelPolicyActivation`、`execution_deployment_retirement_test.go`（:222 仅断言 STOP_NEW 后 `new_admission` 等被拒）。
  - `internal/daemon/execution_control_worker_test.go:68 TestChannelWorker`、`:115 TestChannelRecovery`、`execution_control_recovery_d8_test.go:16 TestChannelRecoveryD8`：组件级。
  - `cmd/server/execution_run_003_test.go:46 TestTC_RUN_003`（读取时为脏文件）：:251-252 另建 `NewRunnerWithOptions(... AdmissionDecider: NewAdmissionDecider())`，:302 直接调 `runner.WakeGrant`；**未使用 router 装配的 runner、ACK committed hook 或 periodic sweeper**。
  - `cmd/server/runtime_sweeper_test.go:21,1415` 只测 `runPeriodicSweep`，没有测试经 `runRuntimeSweeper` 调用 resume hook 或 `h.PipelineResume` 接线。
- 无 DB 不可运行：`cmd/server/integration_test.go:46` 与 `internal/governance/crsync_test.go:32` 的 `TestMain` 缺一次性库即 `os.Exit(1)`，两包内任何“纯函数”测试也须隔离库。`internal/daemon/testmain_test.go` 不需 DB。

## 2. TC-RUN-007：不可达（不是只缺证据）

### 已接线
- 启动扫描：`cmd/server/router.go:1617-1646`，`ArchitectureRunnerEnabled()` 为真时，goroutine 调 `ResumeActiveRuns`，并把 `h.PipelineResume` 设为它。
- 周期：`cmd/server/main.go:778` → `runtime_sweeper.go:205`，resume hook 作为最后 stage（:227-237）。
- ACK：`router.go:1631-1632` `SetGrantAckHandler(ValidateGrantAck)` / `SetGrantAckCommittedHandler(WakeGrant)`；`WakeGrant` 在 `runner.go:1709`，先 `Reconcile` 再 `ReconcileRequirement`。
- 入口路由：`router.go:1786` `POST /api/workspaces/{workspaceID}/pipeline-runs`（architecture）、`:1790` `.../pipeline-runs/requirement`。
- 开关：`runner.go:60 ArchitectureRunnerEnabled`，`AIFIRST_ARCHITECTURE_RUNNER` 默认关。

### 断点
- `StartupScan`（`runner.go:1792` 起）只查 `PipelineIDs.ArchitectureDesign`；`StartupScanRequirement`（`runner_requirement.go:737-757`）只查 requirement。
- `Reconcile`/`reconcile`（`runner.go:697-742`）只分派 active writeback run 或 architecture run；`findActiveRun`（:1156-1164）硬编码 ArchitectureDesign。
- `ReconcileCode`（`runner_code.go:28`）**无任何非测试调用方**。
- 生产代码中无人创建 code-implementation 的 runner run：`upsertRunTx`（`runner.go:1113`）的调用点只有 `runner.go:623/685/1146`（Architecture）与 `runner_code.go:308`（Writeback）。`gate_projection.go:166` 创建的是无 runner 标记的投影 run，被 `StartupScan`/`reconcileFromTaskEvent` 的 `execution_context->>'runner'` 条件排除。
- writeback run 只由 code walker 交接创建（`runner_code.go:274 ensureWritebackRun`，调用于 :448），因此 code 阶段与交接 writeback 在真实入口 / 统一 wake / periodic 下都**不可达**。
- daemon 控制 worker：`BeginOwnerTx`（`internal/daemon/execution_control_worker.go:42`）、`ReconcileOwnerTx`（:140）、`NewControlWorker`（:242）、`ApplyTx`（:266）**均无生产调用方**；不存在拉起或重启它们的 supervisor。
- 结论：RUN-007 的 blocker 是 code 阶段发现 / 创建 / 交接入口 + worker supervisor 接线，二者都会改变生产语义，需要设计与授权；不是补隔离 DB 证据即可。

## 3. TC-RUN-006：判定器只有 CR 级 head + 消费，其余语义缺实装 / 缺数据源

### 判定器
- `internal/governance/execution_admission.go:90-180`：只判 head 为 `approve`，以及该 CR 下是否存在任意 consumption → settlement(kind=effect) → verdict → cursor(`last_seq >= v.seq`) 链；join 在 :161-170（`s.request_id = cc.task_id`，过滤只有 `workspace_id, cr_id`）。
- 无额度、撤销 revision、无进展、resume、新准入与收尾的区分；:135-137 `ponytail` 注释自认未钉代次。
- 生产 decider 为 nil：`router.go:253-257` 注明仅测试组合根注入；`NewAdmissionDecider` 无生产调用方；`runner.go:1059`、`:1539` 在 nil 时不门控。
- 即便注入，`ApplyTx` 未接线时生产会对所有 CR 停在 `WAIT_TRUSTED_T_COMMIT`（`execution_admission.go:159` 自注）。
- `execution_admission_gate.go:10-19` 自列未门控：run completion、ensure-writeback 交接、已批准时的 completion 捷径 settlement。

### 原语都无生产调用方
`ConsumeResumeEpochTx`、`AppendRepairExtensionTx`、`StopNewAdmissionsTx`、`CheckDeploymentAccessTx`、`AdmitAndEnqueueTx` 均只在测试中调用；`ApplySensitiveActionTx` 只由 `execution_sensitive_action.go:141` 调用。

### 缺数据源 / 语义缺口
- 额度：仅有追加 `AppendRepairExtensionTx`（`execution_control_policy.go:245`），合计按 `effect_kind=repair AND head_ref=CRID` 求和，不含 workspace；去重按全局 `effect_ref->>'extension_id'`，不按 CR/workspace 限定。`cr_execution_control_settlement`（`migrations/648:170-185`）无 workspace 列；`verdict_id` 无外键，policy 路径把 grant ID 写入该列。**没有修复准入的扣减账本**，“额度刚耗尽”无数据源。
- Resume：`ResumeRequest.RootTerminal`（:321）由调用方提供，:354 直接采信，不从库重算；settlement 的 `verdict_id` 写 `req.GrantID`（:371），不是 T verdict，不满足 “T 已提交 resume receipt”；重放只比 `epoch_key`（:361），不比 `stop_ref`；无 epoch 单调性检查；resume settlement 的 `request_id` 为 SHA1，判定器 join 永不命中，对准入无影响。
- 无进展：governance 中无 no-progress 状态；`no_progress` 仅见于 `internal/daemon/{config.go,daemon.go,poisoned.go}`。
- **疑似缺陷（待作者独立核实）**：`execution_deployment.go:508` 先判 `denyOps`，:511 才判 ACTIVE；`new_admission` 属 `denyOps`，故 ACTIVE 下也返回 `AccessDenied`，`AccessNewAdmission` 只给非 deny/audit 的 op。现有测试未覆盖 ACTIVE + `new_admission`。作者可能已修改该文件，本条仅对 blob `416912ec6554` 成立。
- `CheckDeploymentAccessTx`（:466）读 `cr_execution_policy_activation_head` 不加锁，调用方须自行与 `StopNewAdmissionsTx`（:207，`FOR UPDATE`）串行，否则存在 TOCTOU。

## 4. 代次（generation）、锁与事务约束

- 代次身份：`(task_id, runtime_id, dispatched_at)`，见 `migrations/644:22` 与 `648:207 cr_execution_task_binding_generation_once`。
- `dispatched_at` 可变：`pkg/db/queries/agent.sql:1001 RequeueAgentTaskAfterClaimFailure`（:1009 置 NULL），`:1019 ReclaimStaleDispatchedTaskForRuntime`、`:1064 ReclaimStaleDispatchedTasksForRuntimes`，以及认领时 :903/:1026/:1073 置 `now()`。代次必须在持锁事务内从持久行读取，不能由调用方传入。
- effect → 代次映射未定义：`AdmissionRequest` 只有 WorkspaceID/CRID/Intent。“mark passed” 可对应已完成 task；“enqueue 下一节点” 时新 task 尚不存在，选哪一代消费是设计决定。`cr_execution_task_binding` 无生产写入方。
- 锁：判定在 `cr FOR SHARE` 下（`execution_head_lock.go:34-40`）；consumption 写入同样持 `FOR SHARE`（`execution_consumption.go` 内调用 `lockExecutionAuthorizationHead`）；撤销与 policy 函数持 `cr FOR UPDATE`（`execution_control_policy.go:158/263/342`）。READ COMMITTED 下未提交的消费不可见，判定 fail-closed 为 WAIT。
- 事务：入队经 `TaskService.EnqueuePipelineTask` 自带连接，与判定不同事务（`execution_admission_gate.go:21-35`）；对撤销可线性化但非原子；入队路径不得写 `cr`，否则自锁死锁。
- 因此“把按代计数做成纯函数”**不足以修安全**：数据源（binding 写入、扣减账本）、effect 映射、锁内重读都缺。

## 5. 可独立实施、不改生产语义的切片

1. test-only RED（需隔离库，按 `scripts/aifi45-db/run.mjs`；skip=0）：
   - ACTIVE + `new_admission` 的 `CheckDeploymentAccessTx` 断言（钉住第 3 节疑似缺陷，不在本切片修）。
   - Resume 反例：调用方谎报 `RootTerminal`；同 epoch 不同 `stop_ref`；resume settlement 不改变准入。
   - `AppendRepairExtensionTx` 跨 CR / 跨 workspace 同 `extension_id`。
2. test-only 可达性守护：源码探针断言 `ReconcileCode` 无非测试调用方、`StartupScan` 只覆盖 architecture/requirement，使缺口可见；沿用 `runner_periodic_resume_test.go` 的 `readGovernanceFunc` 方式。不计 TC 通过。
3. `internal/daemon` 中不依赖 DB 的闭集单测：仅限 op 分类 / 输入校验枚举；代次与额度判定不得放入。

## 6. Blockers（按依赖排序）

1. `cmd/server` 带正式迁移的临时实例 provisioner（`ci-disposable-db-followup-20261028.md` 未关闭）。
2. TC-RUN-003 整 TC：decider 生产注入（Gate3 人类决定）、`ControlWorker.ApplyTx` 接线、periodic 与 router ACK 路径实测。
3. 设计决定：effect→代次映射、修复扣减账本、无进展状态与 T resume verdict 绑定、settlement workspace 维度。
4. RUN-007：code run 创建 / 交接入口，`ResumeActiveRuns`/`Reconcile` 覆盖 code 阶段，worker supervisor 与重启编排。
5. 以上满足后才实现 `TestTC_RUN_006`/`TestTC_RUN_007` 并取得隔离库证据。

## 7. 尚未核实的边界

- 未逐行精读 `AdmitAndEnqueueTx`（`execution_channel_admission.go:73`）、`internal/daemon/daemon.go` 任务恢复、`reconcileLocked` 交接分支；可达性结论基于调用方 grep。
- `gate_projection.go:173` 注释提到投影与 Runner 在部分唯一索引上竞争同一 run，对 code 阶段的影响未核实。
- 脏文件（`execution_control_store_state.go`、`execution_run_003_test.go` 等）内容以读取时为准，未固定 hash。
- 未运行任何测试；所有 “无调用方” 结论为静态 grep，未排除反射 / 生成代码间接调用（grep 范围含 `_gen.go`）。
