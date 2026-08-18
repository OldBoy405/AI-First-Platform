---
cr: CR-2026-045
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-18T02:59:10+08:00"
command-digest: 61856524520506c71779e5c80dea7ec982d1ab1ae35c045925f5f5e335a4daf7
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/pipeline-structure.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/contract-scan.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-03.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/governance, "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-04.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/daemon, -run, "Test(ConfigurePipelineGitEnvironment|InstallPipelineCrctlLauncher|FindPipelineCRRootCardinality|PreparePipelineTaskHydratesMachineLocalPaths|PipelinePromptDoesNotEnterIssueWorkflow)", "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-05.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/daemon/execenv, -run, TestPrepareLocalPipelineSkipsWorkspaceSidecars, "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-06.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/handler, -run, TestHydratePipelineContext, "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-07.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/service, -run, "Test(ResolveTaskWorkspaceIDPipelineCarrier|NotifyTaskAvailableAllowsDisabledEmptyClaimCache)", "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-08.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./pkg/gitguard, "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-09.log
  - repo: multica
    cwd: server
    executable: go
    args: [build, ./...]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-10.log
  - repo: multica
    cwd: server
    executable: go
    args: [vet, ./internal/governance, ./internal/service, ./internal/daemon, ./internal/handler, ./pkg/gitguard]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-11.log
---

# 测试报告 · CR-2026-045

<!-- crctl:analysis-below -->

## 1. 测试摘要

本报告为代码评审 attempt 2 Block 回修后的第 4 次结构化测试执行。11 条机器命令全部 exit 0，command digest 为 `61856524520506c71779e5c80dea7ec982d1ab1ae35c045925f5f5e335a4daf7`；`crctl test` canonical status 为 `pass`、测试轮次为 `2`。

- tools：`pipeline-structure` 16/16、`contract-scan` 7/7、`crctl` 全量 193/193。
- multica：真实 PostgreSQL（Podman `multica-postgres`，migration 265/266）上的 `internal/governance` 全包通过；B08 覆盖 digest drift→同一 active run 恢复，B09 覆盖 checkpoint failure→单节点 successor retry；并发 start/enqueue、review replay、三轮耗尽、signed reject、StartupScan、grant ACK 仍通过。
- Linux race：VMware Ubuntu 22.04 guest 使用 `golang:1.26.4-bookworm`（GCC 12.2、`CGO_ENABLED=1`）和隔离 PostgreSQL 16，`internal/governance` race 全包 PASS，daemon 5 项定向 race PASS；证据为 `go-race-governance.log`（SHA-256 `20fcde1c05b47182459ca4eb2dc033eb437350870f46b7b8459ee2c59409c011`）与 `go-race-daemon.log`（SHA-256 `e0c15139acb289b21423591f2b80e3efc63e6ccd339a816c771bf15a64f47bda`）。
- daemon：pipeline crctl launcher、Git trust config、operational workspace authority、pipeline sidecar opt-out 定向测试通过；handler/service/gitguard、build、vet 全部通过。
- cross-tool approval test：默认结构化计划不依赖外部 CRCTL_PATH，因此未将可选跨工具子测试冒充机器区命令；显式 CRCTL_PATH 运行时 requirement/tech-design/dev-start/code 四 stage 全部通过，code stage 的 machine-injected `release-subjects` fixture（真实 KB worktree + 受控 artifact 重核）已补齐。

## 2. 验证命令与结果解读

| 证据 | 结果 | 说明 |
|---|---|---|
| `cmd-01`/`cmd-02` | PASS | pipeline structure 16/16、contract scan 7/7；五节点/replay/registry/digest 与退役字段扫描通过 |
| `cmd-03` | 193/193 | crctl 黑盒全量；包含 operational-workspace authority、Git inspection hard failure、outbox parity |
| `cmd-04` | PASS | governance 真 PG；B08/B09 与既有 Runner 并发/归因/replay/grant/StartupScan 覆盖 |
| `cmd-05`/`cmd-06` | PASS | daemon pipeline launcher/Git trust/path 与 execenv sidecar opt-out |
| `cmd-07`/`cmd-08` | PASS | handler pipeline context、service carrier/workspace resolution |
| `cmd-09` | PASS | controlled-shell/gitguard |
| `cmd-10` | PASS | `go build ./...` |
| `cmd-11` | PASS | governance/service/daemon/handler/gitguard `go vet` |
| `go-race-governance.log` | PASS | Linux/amd64、Go 1.26.4、GCC 12.2、真实 PostgreSQL；Runner/B08/B09 并发路径无 race |
| `go-race-daemon.log` | PASS | Linux/amd64；pipeline launcher/Git environment/CR root/hydration/prompt 5 项无 race |

## 3. TASK 验收覆盖矩阵

| TASK | 回修后证据 | 状态 |
|---|---|---|
| TASK-01～03 tools 合同/outbox | cmd-01～03；16+7+190 全绿 | covered |
| TASK-04 并发唯一性 | `TestStartArchitectureAdoptsProjectorRunAndDeduplicatesConcurrentStart`、`TestEnqueuePipelineTaskCopiesAttributionAndDeduplicates`（双 enqueue + terminal retry），并由 Linux race detector 覆盖 | covered（真 PG + race） |
| TASK-05 registry/digest | `TestParseCoreRegistryFixedContract`、emitter `--check` | covered |
| TASK-06 归因复制 | source snapshot 字段复制、workspace resolution、无归因 source 拒绝 | covered（真 PG） |
| TASK-07 固定 Runner | happy、authority wait、repair replay、loop exhausted、signed reject、checkpoint | covered（真 PG） |
| TASK-08 daemon carrier | CR root cardinality/path traversal、workspace inspect seam、LocalWorkDir、hydration、普通 prompt 隔离 | covered |
| TASK-09 唤醒/恢复/feature off | StartupScan、task terminal、CR projection、grant ACK callback、default-off flag | covered（进程内 + 真 PG） |
| TASK-10 review parity | exact-commit attempt 1/2、blocker/subject/reviewed_at parity | covered |
| TASK-11 集成与台账 | governance/daemon 纵切测试 + CUSTOM #35～#36；真实 server+daemon+Codex 已执行并闭环完整人工 signed-grant 五节点 E2E（disposable CR-2026-956，见 §7）；cross-tool 四 stage approve/reject/release-subjects 深原语全绿 | covered |

## 4. Blocker 修复对应关系

1. Runner 已按固定五节点实现双重成功判定、review replay、human approval、reject 和 checkpoint authority。
2. Start 增加 task-token/path 归属、CR/Agent/Skill/input/registry/prompt 校验；active run 幂等并由 partial unique 兜底。
3. projector loser 重读、terminal guard、review 顶层 merge 并保留 `detail.runner`；pipeline task active loser 重读。
4. daemon 在 claim 后执行 machine-local CR root + `crctl workspace inspect`，校验 healthy/realpath，并复用 LocalWorkDir/path mutex/`CRCTL_WORKSPACE`。
5. grant ACK 唤醒 Runner；`AIFIRST_ARCHITECTURE_RUNNER` 默认关闭时不挂路由、不订阅、不扫描。
6. commit-scan 不再读最新工作树：使用受 controlled-shell 约束的 `git show {sha}:path`，历史轮次与 outbox 同源字段 parity。
7. 新增 PostgreSQL Runner 集成测试、carrier/hydration/handler/service 测试，并重跑结构化报告。

## 5. 仍未执行或环境限制

1. **完整真实五节点 E2E 已闭合**：真实 server（`localhost:18080`）、daemon、Codex Agent、Skill 与 Ed25519 signed grant 在 disposable CR `CR-2026-956` 上端到端跑通。五节点最终态：write-tech-design passed、review-tech-design blocked→repair→passed、human_approval passed（真实网页人工点击 Approve，grant digest=`482e59249c8b3e0ccaea2574bb4beee0e6ebbe8b7b7e373df63bee34a1c4400b`，key_id=`cr045-e2e`）、approve-tech-design passed（`crctl approve --grant` → `tech-design-reviewed`）、push-progress passed（`crctl checkpoint` batchId=`ceb13d1afacac5cd`，三仓推送 confirmed）；`pipeline_run.status=completed`，`needs_reconcile=false`。负向路径同时真实触发：workspace dirty 前置拦截（`PIPELINE_CRCTL_UNAVAILABLE: workspace resource is dirty`）与 stale grant → `EVIDENCE_DRIFT`（零写入 abort）。完整证据见 §7。
2. **Windows race 环境限制已由 Linux 证据替代**：Windows 主机仍缺少 CGO C compiler，但 VMware Ubuntu 22.04 上的 Linux/amd64 race 已通过；governance 使用真实 PostgreSQL，daemon 使用本 CR 5 项定向范围。cross-tool `TestGrantCrossVerifiesWithCrctl` 因 race 容器未注入完整 tools/Node seam 而按既有测试约定 SKIP，其独立 fixture 状态见第 4 项。
3. **multica `internal/daemon` 全包在本 Windows 主机存在既有环境失败**：用户级 skill 污染、Windows symlink privilege、Agent CLI 路径等与本 CR 无关；报告只将本 CR 改动对应的 daemon tests 纳入 PASS，未把全包失败描述为通过。
4. **可选跨工具 code approval fixture 已闭合**：`TestGrantCrossVerifiesWithCrctlCodeStage` 新增，在真实 KB repo + linked worktree + machine-injected `review-annotations/code.yml#release-subjects` 上重核受控 artifact（PRD/SDD/plan/tasks 的 CRLF→LF sha256 + 集合 digest + 逐仓 source 事实），approve 与 reject 及紧邻重放全绿；结构化测试计划仍不将该可选 seam 计入 PASS（需显式 CRCTL_PATH）。

## 6. 结论

自动化、真实 PostgreSQL 与 Linux race 证据已闭合 B08/B09 及 daemon authority 修复；真实 server/daemon/Codex/signed-grant 五节点 E2E（含 reject/stale-grant/workspace-dirty 负向路径）与 feature-off 手动路线、四 stage cross-tool 深原语（含 code release-subjects）现已全部闭合，B10 证据链完整。结构化测试报告 `status: pass` 仍只代表机器区 11 条 canonical 命令，真实 E2E 与 cross-tool seam 证据在 §7 单独列证。

## 7. 真实五节点 E2E 与 cross-tool seam 证据（B10）

### 7.1 真实 server/daemon/Codex/signed-grant 五节点 E2E

- disposable CR：`CR-2026-956`（run `b0c9fd5a-d072-4765-b1fd-42df470055db`），与正式 `CR-2026-045` 严格隔离；完整证据见 `test-evidence/B10-e2e-evidence-CR-2026-956.md`（本仓库持久副本）。
- 后端：`http://localhost:18080`（真实 server）；前端：`http://localhost:3000`（Next rewrite 代理，避免 CORS）。
- 五节点最终态：write-tech-design `passed`（attempt 1/2）；review-tech-design `blocked`(1) → `passed`(2)；human_approval `passed`（真实网页人工点击 Approve）；approve-tech-design `passed`；push-progress `passed`。
- 有效 grant：stage=tech-design、decision=approve、evidence_digest=`482e59249c8b3e0ccaea2574bb4beee0e6ebbe8b7b7e373df63bee34a1c4400b`（sdd.yml）、key_id=`cr045-e2e`、Ed25519 signature 验签通过；daemon `delivered_at` 已写。
- 终态：`pipeline_run.status=completed`、`cr.status=tech-design-reviewed`、`needs_reconcile=false`、`crctl next → write-dev-plan`。
- checkpoint：`crctl checkpoint` batchId=`ceb13d1afacac5cd`、metadataCommit=`197927fe7d32080d84581eef7ed7e4ef87d22336`、三仓（ai-first-platform-docs/multica/tools）推送 confirmed。
- 负向路径真实触发：① workspace dirty 前置拦截（`PIPELINE_CRCTL_UNAVAILABLE: workspace resource is dirty`，零写入）；② stale grant → `EVIDENCE_DRIFT`（grant 以 requirement.yml 摘要签发，`crctl approve --grant` 验出与 sdd.yml 摘要不符，零写入 abort）。

### 7.2 feature-off 手动路线（AC-15）

- `TestArchitectureRunnerFeatureFlag`：`AIFIRST_ARCHITECTURE_RUNNER` 默认 off；`1/true/yes/on` 才启用。
- router.go：feature off 时不 `NewRunner`/不 `WireEvents`/不 `SetGrantAckHandler`/不挂 `POST /api/workspaces/{workspaceID}/pipeline-runs` 路由，手动 Skill + crctl 路线原样保留。
- 手动路线深原语（`crctl approve`/`reject`/`checkpoint`）由 cross-tool seam 与 tools 机器区 193/193 覆盖。

### 7.3 cross-tool seam（真实 crctl 深原语 + 签名 grant）

- `TestGrantCrossVerifiesWithCrctl`：requirement/tech-design/dev-start 三 stage 的 approve/reject 与紧邻重放（真实 `crctl.mjs` 子进程 + Go 签名 grant）全绿。
- `TestGrantCrossVerifiesWithCrctlCodeStage`（新增）：code stage 在真实 KB repo + linked worktree + machine-injected `review-annotations/code.yml#release-subjects` 上重核受控 artifact（PRD/SDD/plan/tasks CRLF→LF sha256 + 集合 digest + 逐仓 source 事实 + KB reviewed-source-sha 祖先约束），approve/reject 及紧邻重放全绿。

### 7.4 E2E 期间发现并已记录的非 Runner Core 问题（供 follow-up）

1. multica 迁移回归：migration 259/263 重建 `issue_origin_type_check` 时丢失 `project_chat`/`project_discussion`，导致项目聊天容器 issue 创建 500；已在 E2E 数据库恢复完整约束。
2. `crctl review-record` 的 outbox 事件不带 evidence 字段，导致 tech-design 评审证据（sdd.yml）未同步到服务端 `cr_sync_event`，审批 grant 以陈旧 requirement 证据签发（本次 E2E 触发 stale grant 的根因）。
3. daemon crevents 快照扫描主工作区（master 快照）覆盖了 worktree 的 `tech-design-reviewed` 投影（投影漂移）。
4. push-progress prompt 的 `<installation-workspace>` 占位符未解析，Agent 退化为全盘 `find /` 挂起。

