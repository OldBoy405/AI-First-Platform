---
cr: CR-2026-045
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-17T22:57:24+08:00"
command-digest: 1326f653aa26665948c32813c65f941c2cb1794fc3d3fda55c48e2ce50343042
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
    args: [test, ./internal/daemon, -run, "Test(ParseCRCommitMessageReviewContract|BuildReviewPayload|FindPipelineCRRootCardinality|PreparePipelineTaskHydratesMachineLocalPaths|PipelinePromptDoesNotEnterIssueWorkflow)", "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-05.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/handler, -run, TestHydratePipelineContext, "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-06.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/service, -run, "Test(ResolveTaskWorkspaceIDPipelineCarrier|NotifyTaskAvailableAllowsDisabledEmptyClaimCache)", "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-07.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./pkg/gitguard, "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-08.log
  - repo: multica
    cwd: server
    executable: go
    args: [build, ./...]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-09.log
  - repo: multica
    cwd: server
    executable: go
    args: [vet, ./internal/governance, ./internal/service, ./internal/daemon, ./internal/handler, ./pkg/gitguard]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-10.log
---

# 测试报告 · CR-2026-045

<!-- crctl:analysis-below -->

## 1. 测试摘要

本报告为代码评审 attempt 1 Block 回修后的第 3 次结构化测试执行。10 条机器命令全部 exit 0，command digest 为 `1326f653aa26665948c32813c65f941c2cb1794fc3d3fda55c48e2ce50343042`。

- tools：`pipeline-structure` 16/16、`contract-scan` 7/7、`crctl` 全量 190/190。
- multica：真实 PostgreSQL（Podman `multica-postgres`，已应用 migration 265/266）上的 `internal/governance` 全包通过；Runner 表测试覆盖并发 start、projector adoption、并发 enqueue、终态后 retry、归因复制、happy path、block→repair、三轮耗尽、signed reject、checkpoint、StartupScan 和事件唤醒。
- daemon/handler/service：pipeline carrier、CR root、LocalWorkDir seam、hydration、workspace resolution、exact-commit review parity 定向测试通过。
- 静态验证：`go build ./...`、相关包 `go vet`、`pkg/gitguard` 全绿。

## 2. 验证命令与结果解读

| 证据 | 结果 | 说明 |
|---|---|---|
| `cmd-01` pipeline-structure | 16/16 | 五节点/replay/registry/digest；`git show` 仅放行 40 位 SHA + canonical review annotation 路径 |
| `cmd-02` contract-scan | 7/7 | Pipeline 结构快照与退役字段扫描 |
| `cmd-03` crctl 全量 | 190/190 | review attempt 写入 canonical annotation；outbox 字段 parity |
| `cmd-04` governance 全包 | PASS | 真 PG；partial unique、归因、Runner 分支、grant ACK、projector JSONB merge 均执行，非 TestMain skip |
| `cmd-05` daemon 定向 | PASS | commit-scan 从历史 commit 读取正确 attempt；workspace/LocalWorkDir/prompt carrier |
| `cmd-06` handler 定向 | PASS | pipeline context 正常透传；坏 CR/UUID/attempt fail closed |
| `cmd-07` service 定向 | PASS | pipeline task workspace 解析；disabled EmptyClaim cache 回归 |
| `cmd-08` gitguard | PASS | controlled-shell 新 `show` 规则可由 Go RE2 正确加载 |
| `cmd-09` build | PASS | `go build ./...` |
| `cmd-10` vet | PASS | governance/service/daemon/handler/gitguard |

## 3. TASK 验收覆盖矩阵

| TASK | 回修后证据 | 状态 |
|---|---|---|
| TASK-01～03 tools 合同/outbox | cmd-01～03；16+7+190 全绿 | covered |
| TASK-04 并发唯一性 | `TestStartArchitectureAdoptsProjectorRunAndDeduplicatesConcurrentStart`、`TestEnqueuePipelineTaskCopiesAttributionAndDeduplicates`（双 enqueue + terminal retry） | covered（真 PG） |
| TASK-05 registry/digest | `TestParseCoreRegistryFixedContract`、emitter `--check` | covered |
| TASK-06 归因复制 | source snapshot 字段复制、workspace resolution、无归因 source 拒绝 | covered（真 PG） |
| TASK-07 固定 Runner | happy、authority wait、repair replay、loop exhausted、signed reject、checkpoint | covered（真 PG） |
| TASK-08 daemon carrier | CR root cardinality/path traversal、workspace inspect seam、LocalWorkDir、hydration、普通 prompt 隔离 | covered |
| TASK-09 唤醒/恢复/feature off | StartupScan、task terminal、CR projection、grant ACK callback、default-off flag | covered（进程内 + 真 PG） |
| TASK-10 review parity | exact-commit attempt 1/2、blocker/subject/reviewed_at parity | covered |
| TASK-11 集成与台账 | governance 纵切表测试 + CUSTOM #29～#34 | covered；真 Agent E2E 见限制 |

## 4. Blocker 修复对应关系

1. Runner 已按固定五节点实现双重成功判定、review replay、human approval、reject 和 checkpoint authority。
2. Start 增加 task-token/path 归属、CR/Agent/Skill/input/registry/prompt 校验；active run 幂等并由 partial unique 兜底。
3. projector loser 重读、terminal guard、review 顶层 merge 并保留 `detail.runner`；pipeline task active loser 重读。
4. daemon 在 claim 后执行 machine-local CR root + `crctl workspace inspect`，校验 healthy/realpath，并复用 LocalWorkDir/path mutex/`CRCTL_WORKSPACE`。
5. grant ACK 唤醒 Runner；`AIFIRST_ARCHITECTURE_RUNNER` 默认关闭时不挂路由、不订阅、不扫描。
6. commit-scan 不再读最新工作树：使用受 controlled-shell 约束的 `git show {sha}:path`，历史轮次与 outbox 同源字段 parity。
7. 新增 PostgreSQL Runner 集成测试、carrier/hydration/handler/service 测试，并重跑结构化报告。

## 5. 仍未执行或环境限制

1. **未执行真实 daemon + 外部 Agent CLI + 网页签名审批的整链 E2E**：当前证据在真实 PG 上驱动 canonical CR/review/approval/checkpoint 表、事件总线和 enqueue 边界，但没有启动真实 Agent 模型执行五个 Skill。部署前仍应在预发布环境补一次 signed grant 真机 E2E。
2. **未执行 Go race detector**：本机 `CGO_ENABLED=0`，启用后 Windows Go 无可用原生 C compiler；`go test -race` 因工具链前置条件失败。并发数据库断言已普通模式执行通过，但 race detector 证据不存在。
3. **multica `internal/daemon` 全包在本 Windows 主机存在既有环境失败**：用户级 skill 污染、Windows symlink privilege、Agent CLI 路径等与本 CR 无关。报告只将本 CR 改动对应的 daemon tests 纳入 PASS，未把全包失败描述为通过。
4. `inspectPipelineWorkspace` 的真实 subprocess 成功路径需 healthy CR worktree；回修工作树本身为 dirty，当前通过注入 seam 验证参数、返回路径和 LocalWorkDir 接线，并通过真实 `crctl workspace inspect` 契约的 tools 测试约束结构。

## 6. 结论

自动化与真实 PostgreSQL 证据已补齐首轮代码评审要求的可本地验证部分；报告状态 `pass` 仅代表上述 10 条命令。真 Agent/signed-grant 预发布 E2E 与 race detector 仍是明确的发布前验证项，不冒充已完成。
