---
cr: CR-2026-051
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-26T16:09:12+08:00"
command-digest: 33914c7b3f5eb3725c7065a9cb955df1739e187479fd8b2866c530c1a3e64601
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [build, ./...]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-051/test-evidence/cmd-01.log
  - repo: multica
    cwd: server
    executable: go
    args: [vet, ./pkg/protocol/, ./internal/governance/, ./internal/integrations/lark/, ./cmd/server/]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-051/test-evidence/cmd-02.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./pkg/protocol/, -run, ApprovalGate, -v, "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-051/test-evidence/cmd-03.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/governance/, -run, ApprovalGate, -v, "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-051/test-evidence/cmd-04.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/integrations/lark/, -run, ApprovalReminder, -v, "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-051/test-evidence/cmd-05.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./cmd/server/, -run, ApprovalReminder, -v, "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-051/test-evidence/cmd-06.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./pkg/protocol/, ./internal/governance/, ./internal/integrations/lark/, ./cmd/server/, "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-051/test-evidence/cmd-07.log
---

# 测试报告 · CR-2026-051

<!-- crctl:analysis-below -->

## 分析段（回修轮：review-code attempt 1/3 block → 3 blocker 修复 → 机器区重跑，2026-08-26）

### 0. 回修轮说明（`review-annotations/code.yml` 三条 blocker → 修复落点 → 新增用例；先验红后验绿）

| Blocker | 修复落点（repo=multica） | 新增/改写用例 |
|---|---|---|
| BL-C1 / P1 | `server/internal/integrations/lark/http_client.go` `sendCardToOpenID`：非零业务码改返结构化 `*APIError{Op, Code, Msg}`（`Error()` 文本与旧 `fmt.Errorf` 逐字节相同，绑定提示断言零改动） | `TestApprovalReminderCardRateLimitStructured`：真 HTTP 响应 `code=230020`、msg 无 rate 子串 → 断言结构化 `*APIError` 保留 + `errorClassOf` = `rate-limited` |
| BL-C2 / P2 | `server/internal/integrations/lark/approval_reminder.go`：原因查询自身 `pgx.ErrNoRows` 时显式记 `project-unresolved`（SDD §4.4 / TASK-06 要点 2「为真或无行 ⇒ project-unresolved」） | `TestApprovalReminderAC10CrossWorkspace/cr_row_missing_in_anchor_workspace`：锚点 workspace 下 CR 行不存在 → `project-unresolved`，并反向断言不得误记 `workspace-mismatch` |
| BL-C3 / P1 | `server/cmd/server/approval_reminder_wiring_test.go`：fake 改等待 `ctx.Done()` 并返回 `ctx.Err()`（`RecipientTimeout=200ms`），兑现 AC-11 真实超时失败断言 | `TestApprovalReminderEndToEndLatency` 终态断言改为：`failed=1` / `error_class=timeout=1` / `step=send=1` / `sent=0`；时延差 < 50ms 与 CR 投影断言原样保留 |

先验红后验绿：三条用例在修复前各自失败（BL-C1 得到 `*errors.errorString` 而非 `*APIError`；BL-C2 误记 `workspace-mismatch` 导致等待超时；BL-C3 旧替身手动解锁无法产生超时失败日志），修复后全部 `--- PASS`。

### 1. 已知测试失败基线排除：tools 仓 crctl 自测漂移（CR-2026-050 引入，非本 CR）

首轮机器区 status=block 的唯一失败命令是 tools 仓自身的 crctl 测试套件（`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`），失败断言为 `crctl.test.mjs:1246` 的两条 `assert.match`：`/crctl task init/`、`/不得手写索引/`。首轮执行证据（旧 cmd-01.log）已随提交 `9583e92` 入库保留，本轮矩阵按工作区先例（CR-2026-048「未覆盖与已知基线」口径）将该命令排除，其余失败原因分析见下。

事实链（当场核实，首轮证据链原样）：

- `pipeline-templates/code-implementation.pipeline.json` 当前内容不含上述两串（grep 计数均为 0），nodes 数 = 16（符合 CR-2026-042 口径）；
- 该文件最近一次提交是 tools 仓 `14b4458`（CR-2026-050 code-review attempt 1 repair pipeline contracts and tests）——即 CR-2026-050 的 pipeline 收敛重写删除了 review-code 节点 prompt 里的 `crctl task init` 引用，但 crctl 自测断言未同步；
- **本 CR tools 仓零改动**：worktree `git status --porcelain` 为空、HEAD = origin = `c4b10d5`，本 CR 未在 tools 仓产生任何提交（`git log` 无本 CR 记录）。

结论：该失败与 CR-2026-051 的改动面无关，属 tools 仓既有测试基线漂移，按「已知测试失败基线」口径自本 CR 命令矩阵排除（对应修复归 delivery-agent 已另派的 tools 仓 CR，与 `resolveDevPlanRoute` BLOCK freshness 修复同仓同轮，不并入本 CR）。本 CR 其余验证命令全部 0 退出 → 机器区 status=**pass**。

### 2. 本 CR 验证证据（机器区 7 命令全 0 退出；全部真库 `--- PASS`，零 SKIP，C6 口径）

执行环境：`DATABASE_URL` 取真密码（`multica/.env`，48 位随机串）+ `localhost:5432`（C6 口径①满足：显式真密码；5432 本机 PostgreSQL 直连认证成功）。`crctl test` 以 `shell:false` 直启 `go`，7 条命令全部 `exit-code: 0`（见机器区 commands 段与 cmd-01~07.log）。

| 命令（repo=multica，cwd=server） | 结果 | 顶层测试（-v） | `--- PASS` 总行数 |
|---|---|---|---|
| `go build ./...` | 零报告 | — | — |
| `go vet ./pkg/protocol/ ./internal/governance/ ./internal/integrations/lark/ ./cmd/server/` | 零报告 | — | — |
| `go test ./pkg/protocol/ -run ApprovalGate -v -count=1` | ok（cmd-03） | 3 | 3 |
| `go test ./internal/governance/ -run ApprovalGate -v -count=1` | ok（cmd-04） | 4（AC1/AC2/subscription/shell_issue_id） | 23（含子例） |
| `go test ./internal/integrations/lark/ -run ApprovalReminder -v -count=1` | ok（cmd-05） | 22（含五类卡片测试 + BL-C1 回归） | 47（含子例） |
| `go test ./cmd/server/ -run ApprovalReminder -v -count=1` | ok（cmd-06） | 4 | 4 |
| `go test ./pkg/protocol/ ./internal/governance/ ./internal/integrations/lark/ ./cmd/server/ -count=1` | 四包全 ok（cmd-07） | — | — |

全部 7 条日志零 `SKIP`、零 `no database`（真库运行，非跳过）；TASK-04 五类卡片测试含于 cmd-05 的 22 项中（`TestApprovalReminderCard*` 6 项，回修轮新增 `TestApprovalReminderCardRateLimitStructured`）；绑定提示行为等价回归 `TestHTTPClient_SendBindingPromptCard_*` 原样通过（`http_client_test.go` 零改动）。

### 3. AC 覆盖矩阵（13 项，plan.md §5.2 归属表）

| AC | 内容 | 测试 | 结果 |
|---|---|---|---|
| AC-1 | 四门禁触发各一次 | `TestApprovalGateAC1FourGatesPlusReEntry`（governance，真库） | PASS |
| AC-2 | 误触发隔离 | `TestApprovalGateAC2ZeroPublishMatrix`（12 子例，逐条带 liveness probe） | PASS |
| AC-3 | 有效绑定收件人 + 双层去重 | `TestApprovalReminderAC3HappyPath` | PASS |
| AC-4 | 四类不发送可区分原因 | `TestApprovalReminderAC4FourCases`（含反向断言：无收件级 no-approver、reason 不越 9 项闭集） | PASS |
| AC-5 | 卡片最小内容 + CTA + 基地址 | `TestApprovalReminderCardHappyPath` + AC3 内 CTA 断言 + `TestApprovalReminderPreflightOrder`（app-url-missing） | PASS |
| AC-6 | Web 审批链路行为不变 | governance 整包（`approval*_test.go`/`project_gates_test.go` 一行未改） | PASS |
| AC-7 | 三类日志字段 + 失败/跳过无回滚 | `TestApprovalReminderAC7ForcedDBFailures`（closed-pool 事件级 + 私有 schema 遮蔽收件人级，42703 直证） | PASS |
| AC-8 | 改动面与零改动边界 | TASK-08 核对：diff 全在合法集合、queries/generated/migrations/packages/apps 零命中、tools 仓零改动 | PASS |
| AC-9 | 测试覆盖面 | 上表 + `-run ApprovalGate/ApprovalReminder/ApprovalReminderCard` 全 PASS 无 SKIP | PASS |
| AC-10 | 跨 workspace 负向 + 载荷伪造 | `TestApprovalReminderAC10CrossWorkspace`（含静态 SQL 锚点核对） | PASS |
| AC-11 | 非阻塞（回调零 I/O + 端到端不延迟） | `TestApprovalReminderZeroIOCallback` + `TestApprovalReminderEndToEndLatency`（阻塞替身下端到端时延差 < 50ms + 超时失败终态：failed/error_class=timeout/step=send，回修轮 BL-C3） | PASS |
| AC-12 | 飞书未启用形态 | `TestApprovalReminderDependencyIsolation` + `TestApprovalReminderDisabledForm` + `TestApprovalReminderTypedNilGuard` | PASS |
| AC-13 | panic 自恢复 + overloaded 丢弃 | `TestApprovalReminderPanicRecovery` + `TestApprovalReminderOverloadDiscard` | PASS |

BL 回归：BL-1 `TestApprovalReminderBL1HydrationFourStates`（凭据水化四态 + 跨 workspace 安装）；BL-2 `TestApprovalReminderBL2FirstAttemptFails` + `TestApprovalReminderBL2DecryptAndTimeout`（登记先于可失败动作）；BL-3 载荷 shell_issue_id 两态 `TestApprovalGateShellIssueIDTwoStates` + 伪造载荷用例；typed-nil 防护唯一验证点 `TestApprovalReminderTypedNilGuard`。全部 PASS。回修轮另补评审 blocker 回归：BL-C1 → `TestApprovalReminderCardRateLimitStructured`、BL-C2 → AC-10 新子例、BL-C3 → `TestApprovalReminderEndToEndLatency` 超时终态断言（见第 0 节表）。

### 4. 新增/修改测试文件

- 新：`pkg/protocol/events_approval_gate_test.go`、`internal/governance/crsync_approval_gate_test.go`、`internal/integrations/lark/approval_reminder_card_test.go`、`approval_reminder_test.go`、`cmd/server/approval_reminder_wiring_test.go`（5 个）
- 修改：4 个测试替身各 +1 行空实现（`outbound_test.go`/`outcome_replier_test.go`/`typing_indicator_test.go`/`inbound_enricher_test.go`）
- 回修轮再修改：`approval_reminder_card_test.go`（+1 测试）、`approval_reminder_test.go`（AC-10 +1 子例）、`approval_reminder_wiring_test.go`（fake 与终态断言改写）；生产面仅 `http_client.go`（sendCardToOpenID 结构化错误 + 注释）与 `approval_reminder.go`（BL-C2 分支）

### 5. 与计划的偏差登记（供 review-code 与回写期）

1. **approval_reminder.go 行数 501（回修轮前 498），超出 SDD §7.3 规则五「预估 < 400 行」预算**：TASK-05 骨架 330 行 + TASK-06 读链约 170 行为完整实现所需（含两条 SQL 上方的 AIFIRST 强制注释与错误分支口径；回修轮 BL-C2 分支重构 +3 行）；仍远低于 800 行提醒线，无新增包级可变状态。**评审已在 review-code attempt 1/3 将该 498 行偏差接受为终局偏差（code.yml suggestions，非 blocker）；回修轮 +3 行为同一职责内的 blocker 修复，维持终局偏差结论**。
2. **回写期两项 PRD revision 待办**（plan.md §0，须由 `writeback-prd-sdd` 以 revision 修订并注明「结论是否受影响：不受影响」）：① PRD FR-10 改动清单加入 `server/pkg/protocol/events.go`（+1 常量 +1 载荷类型）；② PRD §4.4 可观测性表允许事件级 `failed` 无 recipient 字段。

### 6. 下一步建议

- 机器区 status=**pass**（7 命令全 0 退出，新 command-digest），本 CR 代码与测试证据齐备（4 包全绿、13 AC + 3 BL + 3 评审 blocker 回归全 PASS）；`crctl next` 期望指向 `review-code`（quality-reviewer，attempt 2/3）。
- tools 仓既有测试漂移（第 1 节，已自矩阵排除）不阻塞本 CR，修复归 delivery-agent 已另派的 tools 仓 CR（`crctl.test.mjs:1243-1247` 断言与 `code-implementation.pipeline.json` 的 `crctl task init`/`不得手写索引` 引用，与 `resolveDevPlanRoute` BLOCK freshness 同仓同轮）。
