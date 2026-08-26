---
cr: CR-2026-051
status: block
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-26T15:25:39+08:00"
command-digest: 928d5d893fe1ebe28864f2aaf1fe9130922626c619bcf034c7b52eda24c25eba
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 600
    exit-code: 1
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-051/test-evidence/cmd-01.log
---

# 测试报告 · CR-2026-051

<!-- crctl:analysis-below -->

## 分析段（implement-code 完成证据，写入时间 2026-08-26）

### 1. 机器区 status=block 的定性：tools 仓既有漂移，非本 CR 引入

唯一失败命令是 tools 仓自身的 crctl 测试套件（`node --test skills/shared/crctl/scripts/test/crctl.test.mjs`，见 cmd-01.log）。失败断言为 `crctl.test.mjs:1246` 的两条：

- `assert.match(pipelineText, /crctl task init/)` — 失败；
- `assert.match(pipelineText, /不得手写索引/)` — 失败。

事实链（当场核实）：

- `pipeline-templates/code-implementation.pipeline.json` 当前内容不含上述两串（grep 计数均为 0），nodes 数 = 16（符合 CR-2026-042 口径）；
- 该文件最近一次提交是 tools 仓 `14b4458`（CR-2026-050 code-review attempt 1 repair pipeline contracts and tests）——即 CR-2026-050 的 pipeline 收敛重写删除了 review-code 节点 prompt 里的 `crctl task init` 引用，但 crctl 自测断言未同步；
- **本 CR tools 仓零改动**：worktree `git status --porcelain` 为空、HEAD = origin = `c4b10d50`，本 CR 未在 tools 仓产生任何提交（`git log` 无本 CR 记录）。

结论：该失败与 CR-2026-051 的改动面无关，属 tools 仓既有测试基线漂移，按「已知测试失败基线」口径排除（对应的修复应归 delivery-agent 已另派的 tools 仓 CR，不并入本 CR——见本 CR issue 评论中 `resolveDevPlanRoute` BLOCK freshness 修复的另立 CR 决定）。

### 2. 本 CR 验证证据（全部真库 `--- PASS`，无 `--- SKIP`，C6 口径）

执行环境：`DATABASE_URL` 取真密码（`multica/.env`，48 位随机串）+ `127.0.0.1:5432`（C6 口径①满足：显式真密码；5433 转发容器当前不可用，5432 本机 PostgreSQL 直连认证成功）。

| 命令（cd server） | 结果 | PASS 计数（-v） |
|---|---|---|
| `go build ./...` | 零报告 | — |
| `go vet ./pkg/protocol/ ./internal/governance/ ./internal/integrations/lark/ ./cmd/server/` | 零报告 | — |
| `go test ./pkg/protocol/ -run ApprovalGate -v -count=1` | ok | 3 |
| `go test ./internal/governance/ -run ApprovalGate -v -count=1` | ok | 4 |
| `go test ./internal/integrations/lark/ -run 'ApprovalReminder' -v -count=1` | ok | 21 |
| `go test ./cmd/server/ -run ApprovalReminder -v -count=1` | ok | 4 |
| `go test ./pkg/protocol/ ./internal/governance/ ./internal/integrations/lark/ ./cmd/server/ -count=1` | 全 ok | — |

另有 `go test ./internal/integrations/lark/ -run 'ApprovalReminderCard' -v -count=1`（TASK-04 五类，5 PASS）与绑定提示行为等价回归 `TestHTTPClient_SendBindingPromptCard_*` 原样通过（`http_client_test.go` 零改动）。

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
| AC-11 | 非阻塞（回调零 I/O + 端到端不延迟） | `TestApprovalReminderZeroIOCallback` + `TestApprovalReminderEndToEndLatency`（阻塞替身下端到端时延差 < 50ms） | PASS |
| AC-12 | 飞书未启用形态 | `TestApprovalReminderDependencyIsolation` + `TestApprovalReminderDisabledForm` + `TestApprovalReminderTypedNilGuard` | PASS |
| AC-13 | panic 自恢复 + overloaded 丢弃 | `TestApprovalReminderPanicRecovery` + `TestApprovalReminderOverloadDiscard` | PASS |

BL 回归：BL-1 `TestApprovalReminderBL1HydrationFourStates`（凭据水化四态 + 跨 workspace 安装）；BL-2 `TestApprovalReminderBL2FirstAttemptFails` + `TestApprovalReminderBL2DecryptAndTimeout`（登记先于可失败动作）；BL-3 载荷 shell_issue_id 两态 `TestApprovalGateShellIssueIDTwoStates` + 伪造载荷用例；typed-nil 防护唯一验证点 `TestApprovalReminderTypedNilGuard`。全部 PASS。

### 4. 新增/修改测试文件

- 新：`pkg/protocol/events_approval_gate_test.go`、`internal/governance/crsync_approval_gate_test.go`、`internal/integrations/lark/approval_reminder_card_test.go`、`approval_reminder_test.go`、`cmd/server/approval_reminder_wiring_test.go`（5 个）
- 修改：4 个测试替身各 +1 行空实现（`outbound_test.go`/`outcome_replier_test.go`/`typing_indicator_test.go`/`inbound_enricher_test.go`）

### 5. 与计划的偏差登记（供 review-code 与回写期）

1. **approval_reminder.go 行数 498，超出 SDD §7.3 规则五「预估 < 400 行」预算**：TASK-05 骨架 330 行 + TASK-06 读链约 170 行为完整实现所需（含两条 SQL 上方的 AIFIRST 强制注释与错误分支口径）；仍远低于 800 行提醒线，无新增包级可变状态。若不接受，可拆分文件，但会越出 TASK-06 验收 10 的「本 TASK diff 只含 approval_reminder.go + approval_reminder_test.go」改动面。
2. **回写期两项 PRD revision 待办**（plan.md §0，须由 `writeback-prd-sdd` 以 revision 修订并注明「结论是否受影响：不受影响」）：① PRD FR-10 改动清单加入 `server/pkg/protocol/events.go`（+1 常量 +1 载荷类型）；② PRD §4.4 可观测性表允许事件级 `failed` 无 recipient 字段。

### 6. 下一步建议

- 本 CR 代码与测试证据齐备（4 包全绿、13 AC + 3 BL 全 PASS）；`crctl next` 期望指向代码评审方向。
- tools 仓既有测试漂移（第 1 节）不阻塞本 CR 的 review-code，但应在 delivery-agent 已另派的 tools 仓 CR 中一并修复（`crctl.test.mjs:1243-1247` 断言与 `code-implementation.pipeline.json` 的 `crctl task init`/`不得手写索引` 引用）。
