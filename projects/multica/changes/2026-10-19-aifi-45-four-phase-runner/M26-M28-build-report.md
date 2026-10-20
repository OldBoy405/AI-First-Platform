# AIFI-45 M26–M28 — build report

> 只记录实际跑过的证据。未 commit/push/deploy、未真实 CR、未清 PG。

## M26 Stage A — code walker seq1→5 / version wait

### 实现
- `enqueueNode` / `reconcileSkillTask` 参数化：
  - 新增 `enqueueNodeFor(..., pipelineID, injectFeedback, registry)` 与 `reconcileSkillTaskFor(...)`；
  - architecture 旧入口保持原行为（ArchitectureDesign + tech-design feedback）；
  - code 使用 `CodeImplementation` 与 code registry；
  - `checkIndependentReview`/executor 解析改为使用传入 registry，不再硬编码 architecture。
- 新增 `runner_code.go`：
  - `ReconcileCode`：按 code run 的 run 锁 + `CodeCoreRegistryDigest` 校验推进；
  - `reconcileCodeLocked` 完成 seq1→5：
    - `write-dev-plan` → `write-dev-tasks` → `review-dev-plan`（loop1）；
    - BLOCK 标记 blocked 并重放下一 attempt 的 seq1→3，`attempt` 用既有 `(run,node,attempt)`；
    - PASS 后 `write-dev-tasks:finalize` → `workspace-freshness(implement-start)`；
  - `target_version` 缺失/`unassigned`/非法（`v?x.y.z` 语义）时，writer 前置等待：创建 seq1 node row，写 `runner.wait_reason=version_unassigned`，不派 task、不消耗重试。
- 未改 architecture walker、未恢复 dev-start gate、未新增表/列/状态/服务/CLI。

### 测试
- `TestMDev007`（3 subtest）：missing / unassigned / invalid → 0 task，plan node `wait_reason=version_unassigned`。
- `TestMDevPlanLoopA`：真实 code run，plan→tasks→plan review 三次派发；review BLOCK 后重放 plan attempt 2，断言 attempt-2 task 恰好 1 条。
- RED：临时让 code walker 直接返回，MDev007 无等待 row、loop 计划任务 0 条。
- GREEN：2 RUN/2 Test + 3 subtest，7 PASS；相关治理回归 **98 RUN = 73 Test + 25 subtest，98 PASS，0 FAIL/SKIP**；vet/build/diff-check 0。

### Stage A 边界
- seq4 finalize/seq5 freshness 的推进代码已写，但未用独立主链测试覆盖其成功路径。
- loop1 只验证 BLOCK→attempt2 重放；attempt 边界/三次上限未覆盖。
- testCr 权威读取、seq6→11、MDev004/MDev001 均未开始（Stage B/C）。
- 未改 `internal/daemon/crevents.go`；本段无需 test facts。

## 证据
`C:\Users\GOBAO\AppData\Local\Temp\aifi45-m26-m28-evidence\m26a\`：
`red.log`、`green.json`、`related.log`、`vet.log`、`build.log`、`diffcheck.log`、`summary.json`。

## M26 Stage B — seq6→11 / test fact gate（部分完成，未达验收）

### 已实现
- `runner_code.go` 增加 seq6→11：
  - `implement-code`(6) → `write-test-report`(7) → `workspace-freshness(review-start)`(8) → `review-code`(9) → `human_approval`(10) → `approve-code`(11)；
  - test loop BLOCK 重放 `6→7`；code review BLOCK 重放 `6→7→8→9`；
  - attempt 按 `(run,node,attempt)`；三个 loop 独立 maxAttempts；
  - human_approval 不派 Agent/task，复用 approval_record delivered 语义；approve-code 完成后 run completed。
- test fact gate（Runner 侧）：
  - `codeTestFacts` 从 test node detail 读取 `status/sourceRevision/commands`；
  - `validCodeTestFacts` 要求 `status=pass`、命令非空、每条 `commandDigest` 非空、`exitCode=0`、`timedOut=false`；run 有 `commit_sha` 时 revision 必须一致；
  - 缺失/不合法 → `waitEvidence(test_facts)` 或 loop BLOCK，不 PASS。

### 测试
- `TestMDevTestFactsGate`：正例 + `status=fail`/无命令/exit≠0/timedOut/revision 不匹配全部拒绝。
- 既有 `TestMDev007`、`TestMDevPlanLoopA` 继续 GREEN。
- GREEN：3 RUN/3 Test + 8 subtest，11 PASS；相关治理回归 **104 RUN = 74 Test + 30 subtest，104 PASS，0 FAIL/SKIP**；vet/build/diff-check 0。

### 明确未完成（不能算 Stage B 完成）
- `internal/daemon/crevents.go` 的精确 sha test-report/trace.tests 读取与事件透出**未实现**；Runner 当前只能消费 test node detail，生产 daemon 尚未投递该事实。
- `TestMDev004` 三类 BLOCK 各自完整 replay seq 未写；仅计划 loop 有 Stage A 测试，test/code loop 无真实 RED→GREEN。
- `TestMDev001` 属 Stage C，未开始。
- finalize/freshness 成功路径、三次上限仍未单测。

## M26 Stage B2 — crevents test facts production

### 路径确认
- 现有 fixture 确认 test report 路径为 `change-requests/{cr}/test-report.md`（frontmatter `status`）。
- trace 读取按精确 sha 依次尝试 `trace.tests` / `.yml` / `.yaml` / `.json`；未找到 tools checkout 的其他路径，未读取 working tree。

### 实现
- `crevents.go` 新增 `buildTestFactsPayload(root, sha, crID)`：
  - 精确 `sha:change-requests/{cr}/test-report.md` 读取 frontmatter status；
  - 精确 sha 读取 trace，解析 `commands`（兼容 `tests`）逐项 `name/commandDigest/exitCode/sourceRevision/timedOut`；
  - 缺失 report/trace/commands、commandDigest 为空、trace `cr-id`/`commit-sha`/sourceRevision 不匹配 → 不产出；
  - 输出既有 payload 风格：`test-status` + `commands`；`exitCode!=0`/`timedOut=true` 原样保留。
- `buildReviewPayload` 在 stage=code 且同一 commit 有 test facts 时合并 `test-status`/`commands`，不改 review canonical 字段；review annotation 行为不变。
- 未新增事件类型/schema，未写 test.yml，未改 `detail.runner`。

### 测试
- 正常：test facts status/命令字段完整；同一 commit 的 code review payload 同时保留 `stage/verdict/cr-id` 与 `test-status`。
- report 缺失 → false；trace cr-id/commit-sha 不匹配 → false。
- `status=block`、`exitCode=2`、`timedOut=true` 原样返回。
- RED：临时让 `buildTestFactsPayload` 直接 false → 正常用例与失败原样用例失败。
- GREEN：3 RUN/3 Test，6 PASS；相关 daemon review/payload 回归 **11 RUN/11 PASS，0 FAIL/SKIP**；vet/build/diff-check 0。

### 边界
- 仍无 stage=test 的独立事件生产者；test facts 目前随 stage=code review payload 透出，Runner 侧读取 test node detail 的链路仍需后续衔接。
- 未改 tools、governance、handler、events、DDL。

## M26 Stage B3 — test facts independent payload / detail-only projection

### 实现
- `crevents.go::buildTestFactsPayload` 输出改为独立 payload：
  - `stage=test`
  - `test-status` + `commands`
  - **无 verdict**
- 撤销 stage=code review payload 合并 test facts；同一 commit 的 review annotation 与 test facts 各自独立。
- `gate_projection.go::applyReview`：`verdict==""` 的 facts-only payload：
  - 仍按 stage 映射找到 node/run；
  - 只写 detail，节点状态保持 `pending`（不 passed/blocked、不 completed、不 bump attempt）；
  - 不创建/触碰 review-code 节点。
- `runner_code.go::codeTestFacts` 的 status key 对齐为 `test-status`；commands 字段保持不变。
- 未新增事件类型/状态/表。

### 测试
- daemon：独立 test payload 有 `stage=test`、无 verdict；同 commit code review payload 不含 test-status；report 缺失/CR/commit 不匹配仍拒绝；失败/timedOut 原样保留。
- governance：`TestM26B3FactsOnlyDetailDoesNotPass` 发布 facts-only test payload 后，write-test-report 节点不是 passed/blocked，detail 保留 facts，review-code 行数为 0。
- RED：daemon 去掉 stage=test → 独立 payload 用例失败；governance 关闭 facts-only 分支 → 节点被写成 passed。
- GREEN：daemon 3 RUN/3 Test，6 PASS；governance 1 RUN/1 Test，2 PASS；相关 daemon 11 PASS、governance 8 PASS；vet/build/diff-check 0。

### 边界
- 仍未新增 `stage=test` 的事件生产者/commit 触发；当前实现保证独立 payload 与 applyReview 语义正确，但 crevents 的 scan 入口何时产出该 payload 仍需后续接线（若现有 producer 已直接投递 review 事件则为即插即用）。
- `TestMDev004`、`TestMDev001` 仍未做。

### B3 修正记录
- 复核发现 `runner_code.go` 的 status JSON tag 仍为 `status`，与 daemon 独立 payload 的 `test-status` 不一致；已改为 `test-status`，并重跑 `TestMDevTestFactsGate` GREEN。

## M26 Stage B4 — commit-scan 实际产出 stage=test

### 实现
- `scanCommitsSinceCursor` 每个 commit：
  - 既有 `parseCRCommitMessage` 仍先产出 review/status 等事件；
  - 额外调用 `testFactEventsForCommit`：
    - 若同 commit 有 review 事件，使用其 CRID；
    - 否则用 `git show --name-only --format= <sha>` 从 `change-requests/{cr}/test-report.md` 派生 CRID；
    - 调 `buildTestFactsPayload`，成功则追加独立 `EventKind=review`、`stage=test`、无 verdict 的事件；
    - 读取/匹配失败只跳过 test 事件，不影响 review，也不让 scan 失败。
- 去重：`mergeCREvents` 的 review key 增加 payload stage；同 CR+commit+stage 仍去重，code 与 test 可同时保留。未新增事件类型/表/状态。

### 测试
- 同 commit 同时有 review annotation + test facts：scan 产出 code + test 两个事件。
- test-only commit（无 review 消息）经文件存在产出 stage=test；只有 review 时无 test 事件。
- test facts CRID 不匹配：test 跳过，review 仍产出。
- collector 合并后仍保留 code + test 两个 stage。
- RED：临时让 `testFactEventsForCommit` 返回 nil → test-only/同 commit 用例失败。
- GREEN：4 RUN/4 Test，8 PASS；相关 daemon 16 RUN/16 PASS，0 FAIL/SKIP；vet/build/diff-check 0。

### 边界
- 未改 tools/governance/handler/events/DDL；scan 仍只读精确 sha。

## M26 Stage C — loops replay / main chain / exhaustion

### 测试
- `TestMDev004`（3 subtest）：
  - plan BLOCK → 重放 `1→2→3`，plan attempt2 task 恰好 1，tasks attempt2 为 0；
  - test BLOCK → 重放 `6→7`，implement attempt2 task 恰好 1；
  - review-code BLOCK → 重放 `6→7→8→9`，implement attempt2、freshness/review attempt1 各 1。
- `TestMDev001`：
  - 真实 code run seq1→approve-code；6 个 loop/finalize/freshness 任务 + 2 个 freshness + test/implement 等共 **10** 个 Agent task；
  - human_approval 节点不派 task；approve 前 run `waiting_approval`；
  - delivered code approval + `code-approved` 后 approve-code 完成，run `completed`。
- `TestMDev001MissingTestFactsWaits`：test task completed 但无 facts → test node `wait_reason=review_evidence`、`error.code=test_facts`，freshness 未派发，run 未 completed。
- 3 次上限：`TestMDev004PlanLoopExhaustion` / `TestMDev004TestLoopExhaustion` / `TestMDev004CodeLoopExhaustion`；第 3 次 BLOCK 返回 `RUNNER_LOOP_EXHAUSTED`，run failed。
- 修复：`codeTestFacts` 对空 detail 返回缺失，而不是把 `{}` 当成完整但非法的 facts 继续重试。

### RED / GREEN
- RED：移除空 facts 判定后，`TestMDev001MissingTestFactsWaits` 实际 `wait_reason="" code="" status="running"`（未进入等待）。
- GREEN：targeted 12 RUN = 9 Test + 3 subtest，12 PASS；相关治理 **116 RUN = 83 Test + 33 subtest，116 PASS，0 FAIL/SKIP**；vet/build/diff-check 0。

### 边界
- 未改 daemon/tools/DDL/events；未新增状态。
- 主链使用真实 DB run/task/approval 行与真实 test facts 结构；test facts 由测试注入节点 detail，未重新跑 daemon 事件链（B4 已独立验证 scan 产出）。

### C 段补充
- `TestMDev001` 的 test facts 改为通过真实 `stage=test` payload 经 `applyReview` 投影到 `write-test-report` detail，再由 Runner 消费；未再直接写 detail。
- 重跑 `TestMDev001` GREEN。

## M27 — upstream repair-target 路由（第 1 点完成，第 2 点未做）

### 实现
- `runner_code.go` 的 plan review BLOCK 分支读取节点 detail 顶层 `repair-target`（不解析 blockers/attempt）。
- `repair-target=write-tech-design`：
  - 标记 plan review 节点 `blocked`（保留原 detail）；
  - 写 `runner.wait_reason=review_evidence`、`error.code=upstream_repair`；
  - 返回停止，不重放 `1→2→3`、不进入 seq4+，run 保持非 failed/completed。
- 普通 BLOCK 仍按原 loop 重放。

### 测试
- `TestMDev005`：upstream BLOCK 后 plan/tasks attempt2 均为 0；review 节点 blocked 且 detail 保留 `write-tech-design`；run 未 failed/completed；finalize seq4 未创建。
- RED：临时关闭 upstream 分支，实际 `upstream block was treated as ordinary replay`。
- GREEN：MDev005 1 RUN/1 Test，2 PASS；相关治理 117 RUN = 84 Test + 33 subtest，117 PASS，0 FAIL/SKIP；vet/build/diff-check 0。

### 未完成（第 2 点）
- 未实现 status=`tech-design-review-pending` 时由既有 WireEvents/Reconcile 启动/续接 architecture 复评 run；`StartArchitecture` 仍只接受 requirement-approved，projection 创建的 architecture run 也缺少 Runner context/digest。
- `TestMDev006` 未写。继续需要改 `runner.go` 的受控启动/接管入口，并明确从 review 节点开始而非重写 PRD；这不是当前第 1 点能独立完成的部分。

## M27 第 2 点 — tech-design-review-pending 受控接管

### 实现
- `Reconcile` 无 active architecture run 时，调用 `ensureArchitectureRereviewRun`（仅 CR status=`tech-design-review-pending`）：
  - 从该 CR 最近 code run 的 completed source task 取 source task/agent/started_by；
  - 用既有 `upsertRunTx` 写入 architecture run，execution_context 含 runner schema、template_digest、pipeline_owner、source_task_id，并带 `architecture_rereview:true`；
  - 若已有投影创建的无 context run，也由 `upsertRunTx` 补齐。
- `reconcileLocked` 对 `architecture_rereview`：
  - attempt1 跳过 write-tech-design task，直接 mark passed；
  - 从 review-tech-design 节点开始派发；
  - review BLOCK 后允许进入 attempt2 的 writer 修订（既有 loop 语义）。
- `StartArchitecture` 原语义未改；未新增 endpoint/CLI/状态。

### 测试
- `TestMDev006`：删除 projection architecture run 后，在 `tech-design-review-pending` 下 Reconcile：
  - 创建 architecture run，digest 正确；
  - write-tech-design task=0，review-tech-design task=1；
  - review BLOCK + repair-target 后，writer attempt2 task=1。
- RED：关闭受控入口后，无 run 创建（`no rows in result set`）。
- GREEN：MDev006 2 PASS；相关治理 **118 RUN = 85 Test + 33 subtest，118 PASS，0 FAIL/SKIP**；vet/build/diff-check 0。

### 未完成
- `TestMDev006` 未覆盖 review PASS→approval→approve、随后 code 阶段恢复、无重复 active run 的尾部；当前只验证受控创建/首派 review/BLOCK→writer。
- 未跑完整 architecture 全包；留 Main。

## M27 尾部 — approval / code resume / digest

### 测试补全（并入 `TestMDev006`）
- review attempt2 PASS → human approval 节点无 Agent task，architecture run `waiting_approval`。
- delivered tech-design approval + `tech-design-reviewed` → approve-code 节点完成 → architecture run `completed`。
- 收尾后 architecture run `execution_context.template_digest` 仍等于 registry digest。
- code 阶段 `ReconcileCode` 复用原 code run：
  - 已 passed 的 plan 节点 task 数仍为 1，不重复派发；
  - tasks 节点 attempt 仍为 1，不串用 attempt 2；
  - active code run 行数为 1。
- 重新接入 code 阶段前补 code skills，避免把夹具缺 skill 误判成恢复失败。

### GREEN
- `TestMDev006` 1 RUN/1 Test，2 PASS。
- 相关治理 **118 RUN = 85 Test + 33 subtest，118 PASS，0 FAIL/SKIP**；vet/build/diff-check 0。

### 边界
- 尾段本身没有单独捕获 RED；受控入口 RED 已在 m27b 记录。尾段是在既有 approval/reconcile 逻辑上补断言，未新增第二套审批逻辑。
- 未改 runner.go 的 rerun 分支：实际 PASS 后已按 registry 节点/seq 正常进入 approval。

## M28 — APPROVAL_DECLINED_ROLLED_BACK

### 实现
- `runner.go` 新增 `approvalStageForNode` + `approvalRejectRolledBack`：
  - approve-tech-design → stage `tech-design` / rolled back `tech-designing`；
  - approve-code → `code` / `developing`；
  - approve-requirement → `requirement` / `drafting`；
  - 仅当最新 delivered decision=reject 且 CR 已处于对应回退态时判定为业务拒绝。
- `reconcileSkillTask` 的 `failed/cancelled` 分支先做该判定：
  - 命中返回既有 `RUNNER_APPROVAL_REJECTED`，不落 `RUNNER_TASK_FAILED`、不 failRun、不重试；
  - 未命中保持原技术失败语义。
- architecture `reconcileApproval` 不再把已识别的 ApprovalRejected 覆盖成 TaskFailed。
- 未新增状态/错误码/表；requirement 侧经同一 `reconcileSkillTask` 分支复用。

### 测试
- `TestMHandoff008`：
  - delivered tech-design reject + CR 回退到 tech-designing + approve task failed；
  - Reconcile 返回 `RUNNER_APPROVAL_REJECTED`；
  - 不派新 task、不 bump attempt；
  - run status / node detail / template digest 前后完全不变；
  - 连续两次 Reconcile 幂等，不重复处理。
- RED：关闭拒绝优先判定后实际 `RUNNER_TASK_FAILED: run failed`。
- GREEN：MHandoff008 2 PASS；相关治理 **119 RUN = 86 Test + 33 subtest，119 PASS，0 FAIL/SKIP**；vet/build/diff-check 0；既有 signed-reject 测试仍 PASS。

### 边界
- MHandoff008 使用 architecture approve 任务覆盖共享路径；未单独新增 requirement 专用 reject test，但 requirement/approve-requirement 走同一 `reconcileSkillTask` 判定。
