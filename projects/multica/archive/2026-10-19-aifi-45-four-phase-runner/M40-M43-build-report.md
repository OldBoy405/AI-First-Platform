# AIFI-45 M40–M43 — build report

## M40 — taskfailure 混合/禁止类/安全暂态分类（TC-MRECOVERY-006）

### 实现
- `pkg/taskfailure/classify.go`：在既有 auth/quota 规则之后、capacity/server/network/timeout/process 规则之前新增 4b 守卫 `hasForbiddenFailureWitness`。命中 crctl 事务码（`TX_GIT_FAILED`/`TX_RECOVERY_CONFLICT`/`TX_INPUT_CONFLICT`/`TX_LEDGER_RECOVERY_REQUIRED`/`TX_JOURNAL_INVALID`）、permission/isolation 拒绝、signature/approval/evidence 冲突（含 `APPROVED_ARTIFACT_DRIFT`/`RELEASE_SUBJECT_DRIFT`）时落既有 `agent_error.unknown`（非重试、可 resume）。未新增分类常量/开关/白名单表，导出签名不变，仅改判定优先级。
- 混合类不整体进重试白名单（canonical M-SC-RECOVERY-006）；只有 `provider_network` 等既有可证明暂态子类保持可重试。

### 测试
- `pkg/taskfailure/classify_test.go::TestMRecovery006`（15 子例）+ 测试内 `mRecovery006Retryable` 镜像 `service.retryableReasons`，同时断言具体 Reason 与重试决定。
- RED：219 RUN（29 父 + 190 子），pass 210 / fail 9（parent + 8 子例），实际报 `mixed TX_GIT_FAILED … i/o timeout → provider_network`、`signature … deadline exceeded → provider_network` 等。
- GREEN：219 RUN 全 PASS，exit 0；`go vet ./pkg/taskfailure` exit 0。
- 证据：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-m40-m43-evidence/m40/`（red.log / green.json / vet.log / summary.txt）。

### 边界
- 禁止类落 `agent_error.unknown` 而非新增专用 reason（不允许新增常量）；auth 401/quota 402 仍保留更具体标签。
- 未 commit/push；未改 service/handler/governance/daemon。

## M41a — 待补报/技术中断、预算退避、技术 attempt 与业务 loop 分离

### 实现（最小）
- `internal/service/task.go::MaybeRetryFailedTask` 在 `retryEligible` 之后、overlay/事务之前新增既有查询 `HasRetryTaskForParent` 守卫：一个 failed parent 至多一个非取消 retry child，重复 sweep tick 直接 no-op。
  - 原因：deferred child（`fire_at` 未到）不在 queued/dispatched，`hasRunnableSuccessor` 看不见；`CreateRetryTask` 的 ON CONFLICT 只让 queued 槽，没有该守卫时每次 tick 会再造一次技术 attempt；pipeline 节点任务还会撞 `idx_agent_task_queue_pipeline_node_active`（23505），使 sweep 直接报错。
  - 复用既有列/查询，未新增预算、状态、表、列、引擎、CLI；未改 `retryAttemptCeiling`/`retryDelayForAttempt` 常量。

### 测试（扩展 `internal/service/retry_deferred_test.go`）
- `TestMRecovery002`：技术中断（runtime_offline）→ deferred child（fire_at 有效、attempt=parent+1、max_attempts 不变、继承 pipeline_node_run_id、错误/failure_reason 保留）；第二次 `MaybeRetryFailedTask` 必须 nil 且 child 数=1；业务 BLOCK（agent_blocked）不产生 retry；M40 非重试分类（TX/process 混合 → `agent_error.unknown`）直接终态。
- `TestMRecovery005`：`retryDelayForAttempt` 对 runtime_offline/provider_network/runtime_recovery 在 attempt 1..4 单调不倒退；`retryAttemptCeiling` 仅保留既有 provider_network→3 例外，`max<=1` 与其它 reason 不抬预算；attempt=2/max=2（runtime_recovery）耗尽即停、终态；provider_network attempt=3/max=3 不再重试；技术重试只把子任务 `attempt` 变 2，`pipeline_node_run.attempt` 保持 1；业务 BLOCK 不消耗技术 attempt。

### RED / GREEN
- RED `.../m41a/red.log`：native exit=1，RUN 8（2 父 + 6 子），pass 6 / fail 2；实际失败 `second recovery pass = child:false err:ERROR: duplicate key value violates unique constraint "idx_agent_task_queue_pipeline_node_active" (SQLSTATE 23505), want nil/nil`。
- GREEN `.../m41a/green.json`：exit=0，RUN 8 全 PASS。
- 回归 `.../m41a/regression.log`：11 个既有+新增 retry 测试 exit=0（2.101s）；`go vet ./internal/service` exit 0。

### 边界
- 修复只针对 sweeper 重复建 child；`FailTaskWithTransition` 的事务内首建路径未改（重放由 `FailAgentTask` 终态保护）。
- 未接 tick/未挂 `ResumePipelineNodeTask`（人工加预算入口，M42 范围）；未改治理层 child 跟随（M41b）。
- 未 commit/push/deploy/真实 CR/清 PG；完整整包留 Main。

## M41b — failed parent 判定顺序（TC-MRECOVERY-001/007）

### 实现（`internal/governance/runner.go`、`runner_requirement.go`）
- `reconcileSkillTaskFor` 的 `failed/cancelled` 分支改为四步判定顺序（不再直接 failRun）：
  1. 已投递的业务拒绝且 CR 已回退 → `RUNNER_APPROVAL_REJECTED`（既有 `approvalRejectRolledBack`）；
  2. 本轮已有 conclusive canonical review verdict（`detail` 中 `conclusiveReviewEvidence`，M28 late-delivery 形态）→ 返回 complete，由走查按业务 verdict 路由；
  3. 同一 `pipeline_node_run` 上已有 queued/deferred/dispatched/waiting/running 的 retry child（新 helper `nodeTaskInFlight`）→ 等待该 child，不 failRun、不再建 child；
  4. 以上都不成立才 `failRun(RUNNER_TASK_FAILED)`。
- `reconcileRequirementNode` 的 `requirementNodeStopped` 分支采用同一顺序（新增 helper `conclusiveReviewResult` 复用同一 `reviewEvidence` + `conclusiveReviewEvidence` 定义）。
- 未改 `resume`/`adopt`/known-execution UUID 守卫、状态/表/列/事件/DDL；未 bump `pipeline_node_run.attempt`。

### 测试（新增 `runner_recovery_m41b_test.go`）
- `TestMRecovery001`：架构与 requirement 两入口各一例——failed parent + deferred child → run 保持 running、无新 task、node attempt 仍 1；child 完成后按业务 verdict 推进（block → repair 派发）。
- `TestMRecovery007`：迟到 review verdict 优先于 task 失败（不落 RUNNER_TASK_FAILED）；签名 reject 仍返回 `RUNNER_APPROVAL_REJECTED`；completed/cancelled run 不因迟到 failed task 回退/复活/建 child；无 child/证据的失败仍终态且 attempt 不变。

### RED / GREEN
- RED（基线判定顺序，`.../m41b/red.log`）：native exit=1，RUN 8（2 父 + 6 子），pass 6 / fail 2（parent + 子例）—— `late_review_record_beats_task_failure: reconcile must follow the delivered verdict, got RUNNER_TASK_FAILED: run failed`。
  - 说明：`TestMRecovery001` 在基线已通过（`selectedTask` newest-first 让 child 自然胜出），保留为回归守卫；`nodeTaskInFlight` 是顺序无关的显式保证。
- GREEN（`.../m41b/green.json`）：exit=0，RUN 8 全 PASS。
- 回归 `regression.log`：MHandoff008/失败writer/resume/late-delivery/block 路由共 7 测试 exit=0（2.306s）；`go vet` exit=0。

### 边界
- `nodeTaskInFlight` 未把 cancelled child 视为在飞；未取消/接管既有 child（等待其结局）。
- 迟到 verdict 在 failed 任务上同时尊重 pass/block（业务记录权威），未新增“failed 任务可重启业务轮次”的语义。
- 未 commit/push；完整整包留 Main。

## M-PRE.5 B-SWEEP — 隔离实测（M42/M43 取值依据）

### 方法
- 临时 `cmd/server/zz_bsweep_measure_test.go`（package main，测后删除，生产文件零改动）直接调用真实未导出的 `runPeriodicSweep` 与 6 个 sweep 阶段函数；tick 间隔只在探针内参数化，真实 `sweepInterval=30s` 单独跑 2 tick。
- DB 127.0.0.1:33551，白名单 env，`GOENV=off GOTOOLCHAIN=local GOPROXY=off -mod=readonly`；夹具独立 workspace/runtime/agent，测后清理。
- 证据：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-m40-m43-evidence/b-sweep/`（raw.json / summary.md / commands.txt / run.log）。

### 四组数字
1. 节拍（11 间隔）：100ms 探针 → 99.478/99.965/100.365ms（min/median/max，抖动 ±0.44ms≈0.4%）；callback 250ms 时实际间隔被拉成 250.05–250.77ms（单飞、丢 tick）；真实 30s 间隔 29999.883ms。30s 是触发节拍，不是回调超时。
2. 批量：N=1/10/100 各 20 次均 `processed=N`；1200 条（2×600）按生产上限 500 分 3 tick 清空（500/500/200）。
3. 回调耗时（完整 6 阶段）：N=1 p50 7.5ms / p95 15.6 / max 22.2；N=10 20.2/21.4/23.4；N=100 190.1/215.5/267.4；真实 30s 默认 N=100 loaded 212.1ms、idle 9.5ms。
4. 公平/续扫：2 workspace×600 交错 → tick1 258/242，tick2 250/250，tick3 92/108；total 1200、failed 600/600、retry children 0，无丢失/重复。排序为 `created_at ASC LIMIT 500`，无 per-workspace 配额：单一 workspace 占满老积压时按 tick 偏斜但不永久饿死。

### M42/M43 建议取值
- 批大小：保持 500（500 行 tick≈0.88s，远低于 30s；不新增/不抬现有上限）。
- 单次回调超时：10s per-tick（≥5s 下限），对实测最慢 0.88s 约 11× 余量；idle 9.5ms。
- 续扫：依赖既有状态幂等（queued→failed）下一 tick 继续，无需新游标/账本；公平性维持 FIFO，如需租户公平另评估配额（本段未改代码）。

### 边界
- `sweepInterval` 为 const，无法在不改生产代码下注入：节拍分布用同一 `runPeriodicSweep` 探针间隔测量，真实默认单独采样。
- 探针逐行复刻 `runRuntimeSweeper` 的 6 阶段闭包体；runtime GC / delegated recovery 属独立循环，不在 30s tick 内。
- 未新增 flag、未改默认值/迁移/表；临时探针已删除；未 commit/push。
