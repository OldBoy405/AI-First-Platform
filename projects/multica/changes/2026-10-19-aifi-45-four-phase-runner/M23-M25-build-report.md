# AIFI-45 M23–M25 — build report

> 只记录实际证据与边界。未 commit/push/deploy、未真实 CR、未清 PG。

## M23 — 合法回修 cycle / 终态拒重开 / 注册接入

### 实现
- `runner_requirement_entry.go::upsertRequirementRun` 在无 active run、准备创建新 run 前，于既有 tx 内读取该 CR 最新 requirement run：
  - 最新为 `completed` 且 `cr.status != drafting`：返回既有 `RUNNER_RESUME_UNSAFE`，拒绝重开；
  - 最新为 `completed` 且 `cr.status == drafting`：允许创建新 run（既有 reject/prd-blocker 回修入口），旧 run 不动；
  - `cancelled`/`failed` 继续走既有 `resumeFailedRequirementRun` 受控恢复，不新增状态。
- 没有新增表/列/状态/扫描服务；没有改 tools/crctl；没有用唯一索引推断 cycle。

### 测试（canonical 名称）
- `TestMHandoff005`：先造一个 completed run（digest `sha256:old-cycle`），CR=drafting，StartRequirement 创建新 run；断言旧 run 仍 completed、digest 不变、新 run 唯一 active、node attempt=1、恰好 1 writer task。
- `TestMHandoff006`（2 subtest）：
  - completed run + CR=requirement-reviewing：Start 拒绝 `RUNNER_RESUME_UNSAFE`，旧 run 仍 completed，无新 active；
  - cancelled run + CR=drafting：Start 拒绝 `RUNNER_RESUME_UNSAFE`，旧 run 仍 cancelled。
- `TestMHandoff007`：CR 已注册、无 active run，连续两次 StartRequirement；同一 run id，active=1、writer task=1、fake spec=1。

### RED / GREEN
- 真实 RED：临时移除 completed guard 后，`TestMHandoff006/completed_cannot_reopen_without_drafting` 语义失败：
  `completed run reopened without legal repair: <nil>`。
- 005/007 在加 guard 前即为合法行为，作为回归锁，不伪称 RED。
- GREEN：3 RUN/3 Test + 2 subtest，7 PASS；相关治理回归 **93 RUN = 71 Test + 22 subtest，93 PASS，0 FAIL/SKIP**；vet/build/diff-check 0。

### 边界
- 005 只验证 completed→drafting 的 requirement 新 cycle；上游 design 复评的 architecture cycle 未在本 slice 新造入口。
- 006 的 completed 判定只看最新 requirement run 与 `cr.status`；若未来出现更旧 failed/cancelled 记录，仍按现有 `resumeFailedRequirementRun` 语义处理。
- 007 只覆盖既有 StartRequirement 重入，不覆盖 Git 注册与平台 DB 跨库原子性（不宣称）。
- 未改 M11 parser/四生成/tools073、M12 UUID guard、M13–15 carrier、events、DDL、CLI。

## 证据
`C:\Users\GOBAO\AppData\Local\Temp\aifi45-m23-m25-evidence\m23\`：
`red.log`、`green.json`、`related.log`、`vet.log`、`build.log`、`diffcheck.log`、`summary.json`。

## M24 — dev-plan/test review 投影

### 实现
- `gate_projection.go` 新增 `extendedReviewGateNodes`：
  - `dev-plan` → code-implementation `review-dev-plan` 节点（UUID …0014，seq 3，skill）；
  - `test` → code-implementation `write-test-report` 节点（UUID …0007，seq 7，skill）。
- `reviewGateNode` 先查既有 `ReviewGateNodes`，再查扩展映射；未知 stage（含 dev-start）仍 no-op。
- `reviewEventPayload` 增加 `repair-target`。
- attempt：仅 `stage=dev-plan && repair-target=write-tech-design` 允许保留 0（upstream 不 bump attempt）；其余 `<1` 仍归一为 1。
- 未复制 design 单 subject 判据；未校验/拒绝 `release-subjects`，也未要求 `subject-sha256`；未恢复 dev-start gate。

### 测试
- `TestM24DevPlanUpstreamBlockProjectsWithoutRoundBump`：dev-plan block + repair-target=write-tech-design + attempt 0 → code review-dev-plan attempt 0 blocked，detail 保留 repair-target；不创建 architecture run。
- `TestM24TestBlockIsNotPassed`：test block → write-test-report blocked，失败详情保留，不投影为 passed。
- `TestM24ReleaseSubjectsDoNotRequireSingleSubject`：code pass 仅带 `release-subjects`、不带 `subject-sha256` → passed，detail 保留 release-subjects。

### RED / GREEN
- RED（临时移除扩展映射）：dev-plan/test 均报 `review node_run row not found ...`；release-subjects 用例旧实现已 passed，是回归锁。
- GREEN：3 RUN/3 Test，6 PASS；相关 gate/review 回归 15 RUN/15 PASS，0 FAIL/SKIP；vet/build/diff-check 0。

### 边界
- `applyReview` 只投影节点状态/detail，不改 CR status；dev-plan upstream 的 `tech-design-review-pending` 转移仍由既有 status 通道负责。
- test 事件只处理 `verdict=block`；`fail` 文本状态未新造映射。
- 不透传 canonical cr-id/review-type/release-subjects 到事件 payload；该项属 M25。

## 证据
`C:\Users\GOBAO\AppData\Local\Temp\aifi45-m23-m25-evidence\m24\`：
`red.log`、`green.json`、`related.log`、`vet.log`、`build.log`、`diffcheck.log`、`summary.json`。

## M25 — review payload canonical carrier

### 实现
- `internal/daemon/crevents.go::reviewAnnotationDoc` 增加 canonical YAML 读取：
  `cr-id`、`review-type`、`repair-target`、`release-subjects`、`review-loop.current-cycle`；
  保留既有 `reviewed-at`/`subject-sha256`/`current-attempt`。
- `buildReviewPayload` 仍只从 `sha:change-requests/{cr}/review-annotations/{file}` 精确读取，不读 working tree。
- 透传：
  - `cr-id`、`review-type`、`repair-target`、`release-subjects`（canonical key 原样）；
  - `cycle`（current-cycle>0 时）；
  - 既有 `stage/verdict/blockers/attempt/reviewer/reviewed_at/subject_sha256` 不变。
- 一致性拒绝：
  - annotation `cr-id` 非空且与 envelope CRID 不一致 → 不产出 payload；
  - `review-type` 与 stage 不匹配（允许 `tech-design`/`sdd`）→ 不产出 payload；
  - 精确 commit 无 annotation → 既有 `git show` 失败路径拒绝。
- 未新增事件类型、未改 schema 名、未覆盖 `detail.runner`。

### 测试
- `TestM25ReviewPayloadRoundTripCanonicalIdentity`：code annotation 带 cr-id/review-type/repair-target/release-subjects/reviewed-at/cycle=2/attempt=3；断言 key 原样透出，既有 subject_sha256 字段仍在。
- `TestM25ReviewPayloadRejectsWrongAttribution`：错误 cr-id、错误 review-type、缺失精确 commit annotation 均拒绝。
- `TestM25DevPlanUpstreamPayloadKeepsM24Facts`：dev-plan block + repair-target=write-tech-design + attempt=0 + cycle=2 经 payload 后仍保留，可直接供 M24 扩展映射消费。

### RED / GREEN
- RED（临时回到 M24 前 payload）：round-trip 缺 canonical identity；错误 CR annotation 被接受；M24 upstream facts 丢失。
- GREEN：3 RUN/3 Test，6 PASS；相关 review payload/commit parse 回归 8 RUN/8 PASS，0 FAIL/SKIP；vet/build/diff-check 0。

### 边界
- M24 联合验证在 payload 层完成；`applyReview` 位于 governance 包且未导出，本 slice 未跨包调用，M24 映射仍由 M24 测试独立覆盖。
- 未修改 tools/crctl、governance、handler、DDL、events、CLI。
- 未在测试中伪造真实 CR 的 `review-annotations/test.yml`；test 阶段仍由 M24 事件投影覆盖。

## 证据
`C:\Users\GOBAO\AppData\Local\Temp\aifi45-m23-m25-evidence\m25\`：
`red.log`、`green.json`、`related.log`、`vet.log`、`build.log`、`diffcheck.log`、`summary.json`。
