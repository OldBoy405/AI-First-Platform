# AIFI-45 M20–M22 — projection stale guard 与事务/协调批次

> 状态：**M20 已完成作者侧 RED→GREEN；M21a/M21b/M22 未实施，停在事务重构前。** 未勾任务、未 commit/push/deploy、未真实 CR、未清 PG。

## M20 — projection stale 不推进

- `runner_requirement.go::reconcileRequirementNode`：writer/checkpoint（`refWriteRequirementPRD`、`refPushProgress`）task completed 后，先读 `cr.needs_reconcile`。为 TRUE 时写 `runner.wait_reason=projection_stale`，返回等待，不 `markNode passed`、不派下一节点；FALSE 时保持原 handoff 语义。
- 未新增状态/账本/字段/业务判据；未给 writer 造证据；未复制 crctl 规则。review/approval 既有 evidence、conclusive、approval_record、closing status 门未改。
- 新增 `TestM20RequirementStaleProjectionWaits`：完成 writer task 后 `needs_reconcile=true`，重入不新增 checkpoint task、writer 不 passed、detail 为 `projection_stale`；清 flag 后恢复原 handoff。
- RED：临时移除 stale guard，实际 `completed writer with stale projection advanced to another node: 1 -> 2`。
- GREEN：同测试 exit 0；相关治理回归 83 RUN = 63 Test + 20 subtest，83 PASS，0 FAIL/SKIP。
- `go vet ./internal/governance` 0、`go build ./...` 0、`git diff --check` 0。

## M21a / M21b / M22 — 未实施
- 未改 `recordRequirementRunContext`/`restoreRequirementRunTx` 调用结构，未给 `upsertRun`/`upsertRequirementRun` 加 tx 参数，未把下游创建/接管与 context/上游完成放入同一 pgx.Tx，未做提交前独立连接不可见/提交后可见、逐写点回滚、重入单下游。
- 未改 commit/解锁后 Reconcile 路径，未新增 Bus 延迟缝或 commit 后崩溃重建用例。
- 原因：本回合剩余预算不足以保证同一 Tx 内不逃逸 `r.pool`、不破坏既有 StartArchitecture/StartRequirement 恢复与并发正例；不提交半套事务改动。

## 边界
- M20 只检查 `cr.needs_reconcile` 这一既有投影新鲜度事实，不判断 PRD/版本等业务内容；writer/checkpoint 的 canonical 职责仍归 crctl/投影。
- M21/M22 CP 未闭环；等后续同 writer/DB 继续。PG33551 保留。

## 证据
`C:\Users\GOBAO\AppData\Local\Temp\aifi45-m20-m22-evidence\`：
`m20-red.log`、`m20-green.json`、`m20-green-stderr.log`、`related.log`、`vet.log`、`build.log`、`diffcheck.log`、`summary.json`。

## M21a — requirement persist seam（已完成）

- `runner_requirement_entry.go`：`StartRequirement` 拆为
  - `startRequirementPersist`：现有校验 + `upsertRequirementRun`（run/node/context/inputs、digest/source/started_by 合并语义）后直接返回，不 Reconcile；
  - `coordinateRequirementStart`：只调用 `ReconcileRequirement`；
  - 公开 `StartRequirement` 先 persist 再 coordinate，行为等价。
- 未改 `recordRequirementRunContext`/`restoreRequirementRunTx` 语义，未新增 writer/表/状态。
- 新增 `TestM21aPersistSeamDoesNotDispatch`：persist 后 fake task count 0，context 的 digest/source/started_by 保留；coordinate 后才派 writer。
- GREEN：1 RUN/1 Test，2 PASS；相关治理回归 84 RUN = 64 Test + 20 subtest，84 PASS，0 FAIL/SKIP；vet/build/diff-check 0。
- 该段是内部 seam 重构，没有可独立观察的旧行为 RED（旧公开入口总是先持久化再立即协调）；用“persist-only 不派 task”的 seam 行为锁定。

## M21b / M22 — 未实施（明确阻塞）
- 未给 `upsertRun`/`upsertRequirementRun` 加 tx 参数，未把校验/接管/context/上游完成/下游创建放入同一 pgx.Tx；requirement recovery callback 仍自带事务且 `continueRequirementRun` 自 Begin，强改会同时影响 M20 已验证的恢复语义与既有 392 case。
- 未改 commit+释放锁/连接后 Reconcile、未加 Bus 递归/崩溃重建用例。
- 不在本回合提交半套事务层；M21b/M22 CP 仍未完成。

## M21b — tx 路径（部分完成，未达“所有校验/查询同 tx”）

- `runner.go`：新增 `upsertRunTx`/`findActiveRunTx`；`upsertRun` 改为自 Begin/Commit 包装；`StartArchitecture` 在 Begin 后调用 `upsertRunTx`，提交后释放连接再 `Reconcile`。
- `runner_requirement_entry.go`：`upsertRequirementRun` 在分配锁连接上 Begin 一个 tx，活动 run 的 `recordRequirementRunContext`、新 run INSERT、context/inputs 均走该 tx；提交后显式解锁/Release，再返回。
- `runner_requirement_resume.go`：失败 run 的 `restoreRequirementRunTx` 改用调用方 tx；`resumeLateReviewDelivery` 接受调用方 tx 并去掉内层 Begin/Commit；`continueRequirementRun` 不再在恢复回调内调用，改为 commit+释放后 `queueRequirementContinuation` 单独短事务派 retry child。
- 新增 `TestM21bUpsertRunTxVisibilityAndRollback`：同 tx 重入同一 run；独立连接提交前不可见；回滚后不存在；提交后可见且只有 1 个下游 run。
- GREEN：1 RUN/1 Test，2 PASS；相关治理回归 **86 RUN = 66 Test + 20 subtest，86 PASS，0 FAIL/SKIP**；vet/build/diff-check 0。
- 未完成边界（必须由 Main 知悉）：
  - `StartArchitecture` 的 CR/source 预检仍在 tx 外；`upsertRequirementRun` 的 handover/recovery 读取（`latestRequirementRun`、walk/evidence 等）仍走 `r.pool`，只有写点在 tx；
  - 因此“校验/查询 → 下创建/接管 → context → 上游完成”尚未做到全程同一 tx，也还没有“tx 内出现 r.pool 即失败”的注入断言；
  - 未做逐写点失败回滚矩阵（仅覆盖 upsertRun 回滚与可见性）。
- M22 未开始：commit+释放锁/连接后 Reconcile 仅 architecture 路径已满足；requirement 的 Bus 递归/锁序反例、commit 后崩溃重建用例尚未写。

## M22 — commit 后协调 / Bus 同步递归 / 崩溃重建

- 未改 `internal/events`：现有 `Publish` 同步调用保持不变；未新增 goroutine/队列/延迟发布。
- 顺序确认：architecture 已是 Begin→upsertRunTx→Commit→释放连接→Reconcile；requirement 的 `startRequirementPersist` 在分配锁连接上 commit 并显式 unlock/Release 后才返回，`StartRequirement` 随后才 coordinate/Reconcile。
- 新增测试 seam `Runner.afterCommit`（仅测试注入，生产 nil；无 env/flag），位于 commit/释放之后、协调之前。
- 新增 `TestM22BusWakeAfterCommitDispatchesOnce`：真实 `events.Bus` + `WireRequirementEvents`，commit 前 0 task；发布 CRUpdated 后恰好 1 writer；再同步 re-publish 一次仍恰好 1，用真实 run/task 行数断言。
- 新增 `TestM22CommitCrashRebuildStartupScanRequirement`：commit 后、协调前注入 panic 丢弃内存；新 Runner 走原 `StartupScanRequirement`，断言 active run=1、writer task=1、run 仍 running、digest 完整。
- RED：临时把 `afterCommit` 移到分配/commit 之前，崩溃重建测试实际失败 `read the current run: no rows in result set`。
- GREEN：M22 2 RUN/2 Test，4 PASS；相关治理回归 **88 RUN = 68 Test + 20 subtest，88 PASS，0 FAIL/SKIP**；vet/build/diff-check 0。
- 已知残留边界：M21b 记录的 tx 外只读预检/handover 查询不变，留 M23 TOCTOU；未新增 StartupScan 服务，复用既有扫描。
