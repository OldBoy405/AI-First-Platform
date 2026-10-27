# AIFI-45 M30–M34 — build report

## M30a — authority spec/version + merge rebind

### 实现
- `pipeline_task.go` 在 carrier 校验、`findPipelineCRRoot`、健康/路径 inspect 后，新增 `pipelineAuthorityFacts`：
  - 通过既有 `crctl workspace inspect <cr> --workspace <root> --detail` 读取 authority；
  - 解析 `targetSpecId`/`target-spec-id`、`targetVersion`/`target-version`；
  - spec 缺失 → `TARGET_SPEC_AUTHORITY_DRIFT`；
  - version 缺失/`unassigned` → `WRITEBACK_VERSION_UNASSIGNED`；
  - version 非法 → `WRITEBACK_VERSION_INVALID`；
  - 任一失败在绑定前返回，不写 `PipelineWorkspace`/`PipelineLocalWorkDir`。
- 新 task 的根仍完全由本次 `workspace inspect` 的 `operationalWorkspace` 决定；merge 后 authority 返回新根时，新 task 绑定新根；旧 task 字段不被触碰。
- 未新增表/状态/endpoint，未改运行中 env。

### 测试
- `TestM30AAuthorityFactsReject`：spec 缺失/version unassigned/version invalid 三 subtest，均拒绝且 task 未绑定。
- `TestM30AMergeRebindNewRoot`：两次 prepare 的 inspect 分别返回旧/新 operational；第一个 task 保持旧根，第二个绑定新根。
- 既有 `TestPreparePipelineTaskHydratesMachineLocalPaths`、`TestInspectPipelineWorkspaceDetailContract`、`TestFindPipelineCRRootCardinality` 通过。
- RED：临时让 authority 校验返回 nil，三个 authority code 用例实际 `err=<nil>`。
- GREEN：M30A 3 RUN/3 Test + 5 subtest，8 PASS；相关 daemon 10 PASS，0 FAIL/SKIP；vet/build/diff-check 0。

### 边界
- Task carrier 没有显式 spec/version 字段，本段只校验 authority 自身 spec/version 存在与格式；显式声明一致性未实现。
- merge 换根直接消费 `workspace inspect operationalWorkspace`；未在 daemon 另写 journal/txws 解析器，也未按目录名猜根。
- `TestInjectTaskCRWorkspaceEnvPipelineTask` 在本机因既有“无 original global Git config”环境失败，与本次改动无关；未改该测试/skip。

## M30b — 未实施（阻塞：无真实 merge phase 投递通道）

- 现有授权文件范围内没有 merge 机器结果载体：
  - `crOutboxEvent` 的 merge envelope 只有 event kind/CR，没有 `phase`/`advanced.to`；
  - `pipeline_node_run.detail` 目前由 daemon 的任务收尾写入，但 `internal/daemon` 不在本段授权修改范围；
  - 直接读 task completed/exit0 作为 merge 成功会违反 M30b 第 1/2 条。
- 因此本段未写消费者，避免造合成 merge phase、把 exit0 当 complete、或新增未授权字段/表/状态。
- 最小需求（需 Main 授权改 `internal/daemon` 的 pipeline 结果投递）：在 merge 任务完成后把 `phase`、`advanced.to`、`APPROVED_ARTIFACT_DRIFT`/`RELEASE_SUBJECT_DRIFT` 原样写入该 node 的 detail（或既有 envelope payload），然后 governance 才能按真实 facts 分流。
- 本段未改源码/DB，未提交；`TestMDelivery001/003` 未写。

## M30b handler 侧 — merge facts 落 node detail

### 实现
- `CompleteTask` 在 `CompleteTaskWithTransition` 成功后，若 `task.PipelineNodeRunID` 有效，调用 `recordPipelineMergeFacts`。
- `pipelineMergeDetail(output)` 只解析严格 JSON 白名单：
  - `phase`；
  - `advanced`（或 `advanced.to`）；
  - 递归识别 `code`/`error_code`/`errorCode` 中的 `APPROVED_ARTIFACT_DRIFT`、`RELEASE_SUBJECT_DRIFT`。
  - 非 JSON → `{"unavailable":"not_json"}`；缺 phase → `{"unavailable":"missing_phase"}`；绝不推断 complete。
- 写 `pipeline_node_run.detail` 的专用子键 `pipeline_merge`，`jsonb_set` 合并，不覆盖 `detail.runner`/review 字段。
- 非 pipeline 任务不调用；缺失 output 只标记 unavailable，不改变完成语义。

### 测试
- `TestM30BPipelineMergeDetail` 6 subtest：complete、release-drift+advanced.to=developing、两种 drift code、非 JSON、缺 phase。
- RED：临时让解析器无条件返回 `phase=complete`，6 个子测试全部失败（非 JSON/缺 phase 被误判成功）。
- GREEN：1 RUN/1 Test + 6 subtest，7 PASS；`go vet ./internal/handler`、`go build ./...`、`diff --check` 0。
- handler 测试使用 33551 DB，TestMain 正常进入、不 DBskip。

### 边界
- 仅完成 handler 侧落盘与纯解析测试；未新增完整 HTTP 持久化集成测试（现有 handler 测试夹具成本高）。
- governance 侧 M30b 消费、`TestMDelivery001/003` 尚未开始。

## M30b governance 步骤 1+2 — writeback run + merge dispatch

### 实现
- `runner_code.go` 新增 `findActiveWritebackRun` / `ensureWritebackRun`：
  - 在 approve-code 完成且 `code-approved` 后调用；
  - 复用 active writeback run；否则同 tx 调 `upsertRunTx(..., FeatureWriteback)`；
  - execution_context 写 runner schema、`WritebackCoreRegistryDigest`、pipeline_owner=delivery-agent、source_task_id/executor_agent_id（来自 code run）。
- 新增 `dispatchWritebackMerge`：
  - 解析 Writeback registry，按 `Pipeline.Nodes[0]` 定位 merge 节点（不硬编码 UUID）；
  - `reconcileSkillTaskFor(..., FeatureWriteback, writeback registry)` 派发 merge seq1；
  - human/approval 不派 Agent/task 的既有语义不变。
- `reconcileCodeApproval` 在 approve-code passed 后先建立 writeback + 派 merge，再完成 code run；保持原 code/approval 收尾兼容。
- 未实现 seq2–5、`detail.pipeline_merge` 分流、release-drift/drift 阻断。

### 测试
- `TestMDev001` 扩展断言：
  - writeback run 存在、pipeline=feature-writeback、digest=`WritebackCoreRegistryDigest`、active 唯一；
  - merge 节点恰好 1 条 task；
  - 连续两次 Reconcile 不产生第二个 writeback run/merge task。
- RED：临时移除 ensure/dispatch 调用，实测 `no rows in result set`（无 writeback run）。
- GREEN：MDev001 2 PASS；相关治理 7 RUN = 4 Test + 3 subtest，7 PASS，0 FAIL/SKIP；vet/build/diff-check 0。

### 未完成
- 步骤 3：读 `detail.pipeline_merge` 的 complete/release-drift/drift/unavailable 分流。
- 步骤 4：`TestMDelivery001/003` 完整交付链测试。

## M30b governance 步骤 3+4 — pipeline_merge 分流 / MDelivery

### 实现
- `reconcileWriteback`：
  - merge task 完成后读取 `pipeline_node_run.detail.pipeline_merge`；
  - `phase=complete` → mark merge passed，按 Writeback registry seq2–5 逐个 `reconcileSkillTaskFor`（FeatureWriteback + writeback registry），全部完成后 writeback run completed；
  - `phase=release-drift` → mark merge blocked、停止，不重派 merge、不推进 seq2；
  - `errors` 含 drift 码 → blocked + waitEvidence 保 detail；
  - `unavailable`/缺 phase/未知 phase → waitEvidence，不推进；
  - merge task completed 本身不作为成功依据。
- `Reconcile` 先检查 active writeback run，存在则进入 `reconcileWriteback`。
- 未新增状态/表/CLI/引擎。

### 测试
- `TestMDelivery001`：code-approved → writeback merge complete → seq2–5 推进；断言 writeback run completed、5 nodes/5 tasks、digest 保真。
- `TestMDelivery003` 4 subtest：
  - release-drift+advanced.to=developing：merge 不重试、seq2 不派任务、节点不 passed、detail 保真；
  - APPROVED_ARTIFACT_DRIFT / RELEASE_SUBJECT_DRIFT：阻断且 detail 保真；
  - unavailable：不推进、不报成功。
- RED：强制把任何 phase 当 complete，release-drift 实际推进（`writeback advanced after release_drift`）。
- GREEN：MDelivery 2 RUN/2 Test + 4 subtest，6 PASS；相关治理 89 RUN = 66 Test + 23 subtest，89 PASS，0 FAIL/SKIP；vet/build/diff-check 0。

### 边界
- release-drift 测试只断言 writeback 停止/merge 不重试；未在同一测试中驱动 `code-approved -> developing` 状态转换并创建新 code run。
- drift/unavailable 负例使用测试注入的 `pipeline_merge` detail，handler 侧真实落盘已单独验收。

## M31 — archive 安装根 / cleanup 后重入

### 实现
- `preparePipelineTask` 在 carrier/registry/digest 校验后识别 `contract.Ref == "cr-archive"`：
  - 不再要求 `change-requests/<cr>/cr.md` 存在；
  - 不再走 workspace inspect/authority 预检；
  - 通过 `findPipelineArchiveRoot` 在配置的 CRWorkspaceRoots 中找唯一 `.crctl/outbox` 安装根，唯一匹配才绑定；
  - `PipelineWorkspace` / `PipelineLocalWorkDir` 均绑定安装根。
- 非 archive 节点行为完全不变；authority 缺失/漂移仍拒绝。
- 未改运行中 env，未恢复已删 txws，未新增状态/表。

### 测试
- `TestMDelivery005`：临时安装根只有 `.crctl/outbox` + `audit.log`，无 CR worktree；archive 节点 prepare 成功并绑定安装根，audit/outbox 仍可读；authority inspect 被显式禁止调用。
- 缺失安装根时 archive prepare 失败（`PIPELINE_CRCTL_UNAVAILABLE`）。
- RED：禁用 archive 分支后，prepare 仍按普通节点找 CR root，实际 `expected exactly one CR root ... found 0`。
- GREEN：MDelivery005 2 PASS；相关 daemon 11 RUN = 6 Test + 5 subtest，11 PASS；vet/build/diff-check 0。

### 边界
- 安装根选择使用配置 CRWorkspaceRoots 上的 `.crctl/outbox` 唯一性，未在 daemon 内重写 tools 的 `deriveInstallRoot` git common-dir 算法。
- 未执行真实 archive/清理；仅临时夹具根。
- M32 settle 结果参与终态未开始。

## M32 — settle 结果参与终态汇合

### 实现
- `settleCREventsForTask` 改为返回 error；`runTask` 在终态报告前接收：
  - settle 失败（outbox/HTTP/cursor/applyAck）→ 不再用 `completed` 上报；
  - 复用既有 fail 通道，`status=blocked`、`failure_reason=CR_EVENTS_SETTLE_FAILED`；
  - 原业务输出（含 `cleanup-pending`）保留在 comment，错误信息同时保留，不重派清理/重归档；
  - 不新增状态/表/事件类型。
- `applyAck` 改为返回 error：
  - acked 文件删除失败 → 返回；
  - server rejected 事件 → 返回（仍保留 3 次 quarantine 与计数）；
  - 继续处理其余 accepted/rejected，返回首个错误。
- `collectRoot` 在每批 applyAck 失败时返回，cursor 不推进的既有语义不变。
- 非 CR 绑定/无 collector 任务仍直接 nil。

### 测试
- `TestMDelivery006` 5 subtest：
  - cleanup-pending + settle 失败 → 不报 completed、reason 可诊断、业务文字保留；
  - 非 CR 任务不受影响；
  - applyAck rejection → error；
  - applyAck 删除失败（非空目录作为 wedged acked 文件）→ error；
  - settle 成功 + cleanup-pending → 业务结果保持 completed。
- 既有 `TestPartialAcceptDeletesOnlyAckedFiles` / `TestPoisonedFileQuarantinedAfterThreeRejections` 的断言由“忽略 rejection”改为“rejection 必须以 error 暴露”，仍保留删除/隔离断言（增强，非削弱）。
- RED：让 `settleFailedResult` 保持 completed，实际失败 `settle failure still reported success`。
- GREEN：MDelivery006 1 RUN + 5 subtest，6 PASS；相关 daemon 13 RUN = 8 Test + 5 subtest，13 PASS，0 FAIL；vet/build/diff-check 0。

### 边界
- 通过纯 helper `settleFailedResult` 与 collector/applyAck 单测验证，未在完整 `runTask` 网络回调链路中端到端断言 UI 最终状态。
- 未操作真实安装根；未 commit/push/deploy/真实 CR/清 PG。

## M34 — run ownership / archived 乱序 / 收尾汇合（TC-MDELIVERY-007）

### 实现（仅 `gate_projection.go`、`runner_code.go`、新增 `gate_projection_m34_test.go`）
- `gate_projection.go::completeRun` 增加 ownership 谓词
  `COALESCE(execution_context->>'runner','') = ''`：投影只完成**自己创建**的 run
  （无 runner 标记，语义不变）；带 `execution_context.runner` 的 run 归对应
  pipeline Runner 所有（`requirement-core/v1` → requirement-authoring；
  `architecture-core/v1` 为 architecture/code/writeback 共用标记），只能由 Runner
  在自身事实汇合后关闭。archived / 跨阶段事件不再抢关 Runner run。
- `gate_projection.go::projectGateTransitionErr` 增加终态护栏：投影前读当前
  `cr.status`；CR 已 `archived` 而事件不是 archived 时，直接
  `flagProjectionReconcile`（只置 `needs_reconcile=TRUE` + `updated_at`），
  不 completeRun、不 findOrCreateRun、不回退状态、不写节点。诊断信息沿用既有
  不可变 `cr_sync_event`（from/to/trigger/payload）与 `needs_reconcile`，
  **未新增列/状态**（`cr` 表无 detail 列，未改 DDL）。
- `runner_code.go::deliveryFactsConverged` 为交付 run 的收尾闸：仅当
  (a) CR 投影存在且 `needs_reconcile=FALSE`（settle/交付投影事实已落地）、
  (b) `cr.status` 非 rejected/withdrawn、
  (c) 本 run 所有 `pipeline_node_run.status='passed'`（任务事实，而非单一状态）
  三者同时成立才返回 ""；否则返回稳定 reason。`reconcileWriteback` 在关闭自身
  run 前调用它，未汇合时向 archive 节点写既有
  `detail.runner.wait_reason=delivery_facts:<reason>` 并保持 run 打开，下一次
  Reconcile 重判。**未新增状态/表/列/引擎/CLI**。
- 说明：未把“`cr.status == 'archived'`”做成唯一硬门。既有
  `TestMDelivery001` 夹具在 `cr.status=code-approved` 下驱动 writeback 全部节点
  完成并断言 run completed；若硬性要求 archived 会破坏该既有断言。按“优先最小
  调整实现”改为多事实闸（投影新鲜度 + 节点事实 + 终态否定态），archived 落地时
  作为投影事实的一员参与，未删弱/跳过任何既有断言。

### 测试（`gate_projection_m34_test.go::TestMDelivery007`，6 subtest）
- `archived_completes_only_projection_owned_run`：requirement/architecture/code/
  writeback 四条 Runner 自有 run + archived 事件 → 全部保持 running；
- `cross_stage_archived_does_not_steal_runner_runs`：直接
  `projectGateTransitionErr(code-approved → archived)` → 四条 Runner run 不变；
- `projection_owned_run_completes_normally`：无 runner 标记的投影 run 正常
  completed；
- `late_writingback_after_archived_is_flagged_not_reopened`：CR 已 archived 后
  迟到 `merging → writing-back`（先直接投影、再走 ingest）→ 0 条新 run、
  status 仍 archived、`needs_reconcile=true`、ledger payload 保留 from/to 诊断；
- `duplicate_out_of_order_events_are_idempotent`：同一 ledger key 重复 + 另一
  sha 重复 → run 数 0、status 不变、ledger 恰 2 行；
- `runner_close_waits_for_fact_convergence`：未完成节点 →
  `node_facts_pending`；全 passed → ""；`needs_reconcile` → `projection_dirty`；
  rejected → `terminal_negative`。

### RED（实现前，stub `deliveryFactsConverged` 恒返回 ""）
`.../m34/red.log`，native exit=1，1 Test + 6 subtest，4 subtest FAIL：
- `archived closed a run owned by another pipeline (feature-writeback): got completed want running`
- `archived closed a run owned by another pipeline (code-implementation): got completed want running`
- `projector opened a run after archived: 1`
- `pending node facts must hold the run open: reason="" err=<nil>`
（`projection_owned_run_completes_normally` / 幂等子例在旧代码下本就通过，作为回归守卫。）

### GREEN
`.../m34/green.json`：`go test -count=1 -v -run '^(TestMDelivery007|TestGateProjectionPipelineHandoff)$'`
native exit=0，2 RUN / 2 Test + 6 subtest 全 PASS（1.73s）。
`.../m34/regression.json`：`-run '^(TestReconcile|TestGateProjection|TestApplyReview|TestMDelivery)'`
exit=0，21 RUN 全 PASS；追加 `^TestMDev` exit=0。`go vet ./internal/governance` exit=0。
DB=127.0.0.1:33551（白名单 env，`GOENV=off GOTOOLCHAIN=local GOPROXY=off -mod=readonly`）。

### 边界
- 未改 `internal/daemon`、`internal/handler`、tools、DDL/events/`transitions_gen.go`、
  M11–M33 语义；未改既有测试断言（仅新增测试文件）。
- `cancelActiveRuns`（rejected/withdrawn）未加 ownership 谓词：CP/TC 只要求
  archived 与跨阶段不抢关，且既有 `TestGateProjectionRejectedCancelsActiveRun`
  依赖现语义；留作后续如需再收紧。
- 迟到事件的“诊断 detail”受限于 `cr` 无 detail 列且禁止新列，实际落在既有
  `needs_reconcile` + 不可变 `cr_sync_event` payload；Runner 侧诊断落在既有
  `pipeline_node_run.detail.runner.wait_reason`。
- 未 commit/push/deploy；未做真实 CR/归档；未清 PG。完整整包回归留 Main。

## M33 — 终态队列结构化 recovery / 重启校验

### 实现
- 终态记录 version 1 → 2；新增 `recovery`：
  - `executable/args/cwd/requires_tty/prompt_for` 对齐 tools `buildRecovery`；
  - 身份：`workspace_id/cr_id/pipeline_id/node_id/attempt/daemon_id/root`；
  - `argv_digest` 摘要。
  - v1 记录仍可读取（无 recovery）；>2 未知版本继续拒绝并保留。
- `buildTerminalRecovery` 由 `governance.CompiledPipelineNodeFor` 校验真实节点合同后生成，argv 为
  `node <abs crctl.mjs> workspace inspect <CR>`，cwd 为绑定 root；不执行、不读磁盘 argv 作为授权。
- `attachPipelineRecovery` 接入 pipeline prepare 失败与 runTask 主失败报告。
- `validateTerminalRecovery` 重放前：
  - daemon id 精确匹配；
  - root 必须绝对、cwd=root、位于当前配置 roots 内；
  - 节点合同重新解析成功；
  - 用当前 `MULTICA_CRCTL_PATH` 重建 argv，逐项比对 executable/args/cwd/requiresTTY/promptFor；
  - 自摘要与重建摘要都校验；任一失败 → 拒绝、保留文件、Error 日志。
- `replayPendingTerminalReports` 对带 recovery 的记录不再直接 HTTP 重放：校验通过后记录
  “no controlled recovery entry is available; record retained”，不执行、不删除、不伪报 settle。
- 无 recovery 的旧记录仍走原 HTTP 重报/ack 路径。

### 测试
- `TestMRecovery003`：结构化 recovery 落盘 → 新 Daemon 重开队列 → recovery 仍在 → 重放 sends=0、pending=1、文件保留（不伪报 settle）。
- `TestMRecovery004`：
  - 合法 descriptor 通过；
  - argv 篡改（重算摘要）拒绝；
  - daemon 身份篡改拒绝；
  - root 越界篡改拒绝；
  - 未知版本拒绝且文件保留；
  - 仅文字记录仍正常 HTTP 重报。
- RED：跳过 recovery 分支后，记录以 HTTP-only 重放，`pending=0 delivered=1 sends=1`。
- GREEN：MRecovery003/004 2 PASS；相关 daemon 39 RUN = 20 Test + 19 subtest，39 PASS，0 FAIL；vet/build/diff-check 0。

### 边界 / 待接入
- daemon 层当前没有受控 recovery 执行入口；校验通过的 recovery 记录只保留并报错，不执行。
- 未新增执行器/补偿文件，未改 tools；若需真正恢复，需要 Main 指定既有受控入口（当前层缺少该入口）。
- workspace_id 无当前配置对照源，仅做非空/摘要绑定；daemon/root/节点合同与 argv 已强校验。
