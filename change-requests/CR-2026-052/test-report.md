---
cr: CR-2026-052
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-27T15:46:23+08:00"
command-digest: d99fbfeb4448e1c1586ae851879c6e8bf7a7af8c658b6819814b25c6ea996e54
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [build, ./...]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-052/test-evidence/cmd-01.log
  - repo: multica
    cwd: server
    executable: go
    args: [vet, ./internal/governance/..., ./internal/service/..., ./cmd/...]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-052/test-evidence/cmd-02.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/governance/..., ./internal/daemon, -run, "TestAC|TestGrantDeliveryQueue|TestBuildPrompt_ApprovalContinuation_MergedHandoff|TestBuildPrompt_HandoffNote", -v, "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-052/test-evidence/cmd-03.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, "--test-name-pattern=CR-2026-052|EVIDENCE_DRIFT", skills/shared/crctl/scripts/test/crctl.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-052/test-evidence/cmd-04.log
---

# 测试报告 · CR-2026-052

<!-- crctl:analysis-below -->
## 测试摘要

本轮（review-code cycle 1 / attempt 2）修复两条 blocker 后重新取证，**status=pass**，4 条命令全部 exit=0、无 skip、无 FAIL：

| 命令 | 结果 |
|------|------|
| cmd-01 `go build ./...`（multica/server） | exit=0 |
| cmd-02 `go vet ./internal/governance/... ./internal/service/... ./cmd/...` | exit=0 |
| cmd-03 `go test ./internal/governance/... ./internal/daemon -run "TestAC\|TestGrantDeliveryQueue\|TestBuildPrompt..." -v -count=1` | exit=0，11 条 `--- PASS`，**0 条 skip**（真实连库执行） |
| cmd-04 `node --test --test-name-pattern=CR-2026-052\|EVIDENCE_DRIFT crctl.test.mjs`（tools） | exit=0，13 pass / 0 fail |

## 关键修复（相对上轮 block 证据 53b8122）

1. **Blocker 1（approval.sql 前向引用）**：`CreateApprovalContinuationTask` 的 `JOIN squad s ON ... s.leader_id = a.id` 原先引用未 JOIN 的 `agent a`（SQLSTATE 42P01）。已重排为 `agent a` 先于 `squad s` JOIN（对齐 `agent.sql` 既有 `CreatePipelineTask` 写法），并 `make sqlc` 重生成 `approval.sql.go`。落 commit `dc2179510`。
2. **顺带修复的 SQL bug**：`AppendApprovalContinuationEvidence` 引用不存在的 `agent_task_queue.updated_at` 列（真库实跑时 SQLSTATE 42703）——已移除该列，重新 sqlc 生成。此 bug 正是上轮「静默跳过」没暴露出来的运行期硬错误。
3. **测试夹具修复**（`approval_continuation_test.go`）：
   - `wsUUID(ws, 0x51/0x52/0x53)` 写入了非十六进制字节（'Q'/'R'/'S'）→ `::uuid` cast 失败；改用 `'a'/'b'/'c'`。
   - seed issue 未分配 `number`（默认 0）→ 违反 `uq_issue_workspace_number`；改为 `(SELECT COALESCE(MAX(number),0)+1 ...)` 分配唯一号。
   - `TestAC9` 三个子测试共用同一 `cr_id`/`stage`/`evidence_digest` → 撞 `approval_record_approve_ws_uniq` 唯一索引；拆分为 9a/9b/9c 各自独立 crID。

## 测试环境与执行方式

- **数据库**：真实 PostgreSQL `localhost:5432`，凭据取自 `multica/.env`（哈希口令）。因共享 `multica` 库存在历史迁移漂移（`schema_migrations` 仅 445 条、磁盘上 504 条 up 迁移，缺 95 条含 404/432 `conversation_starters` 重命名，导致 `GetAgentForUpdate` 的 `SELECT *` 报 `column conversation_starters does not exist`），本轮在**专用库 `multica_cr052`** 上全量跑通 504 条迁移后实跑 `TestAC*`（`DATABASE_URL` 指向该库）。共享 `multica` 库的漂移是环境问题，非本 CR 代码缺陷，详见未覆盖风险。
- `-v -count=1` 保证每条子测试的真实执行证据落盘于 `test-evidence/cmd-03.log`（含 11 条 `--- PASS` 明细，无 `Skipping`）。

## 验收覆盖矩阵（AC-1~AC-12）

| AC | 覆盖测试 | 结果 |
|----|---------|------|
| AC-1 | TestAC1_SameRecordTwiceIdempotent | PASS |
| AC-2 | TestAC2_FourStagesApproveAndReject | PASS |
| AC-5 | TestAC5_MergeAndSlotDeferred | PASS |
| AC-6 | TestAC6_FailClosedReasons（含 no_shell_issue / no_leader） | PASS |
| AC-6d | TestAC6d_CrossWorkspaceIsolation | PASS |
| AC-7 | TestAC7_HistoricalDeliveredNoTask | PASS |
| AC-8 | TestAC8_RunnerOffContinuationStillEnqueues | PASS |
| AC-9a~d | TestAC9_DoubleHookContract（3 子测试） | PASS |
| AC-10 | TestGrantDeliveryQueue（deliverGrants + ACK 双钩） | PASS |
| AC-11/AC-12 | tools `crctl.test.mjs`（CR-2026-052 AC-11 / AC-12①②） | 13 pass |

> AC-3（入队失败→delivered_at NULL+5xx）由 AC-9a 的预提交 error 路径与 AC-6 fail-closed 路径共同覆盖；AC-4（15s 重投递）依赖 daemon deliverGrants fake 时序，由 `TestGrantDeliveryQueue` 的 pending/ack 断言覆盖。AC-9d（committed error→log/2xx）由 9c 子测试覆盖。

## 新增/修改测试文件

- `server/internal/governance/approval_continuation_test.go`：seed 夹具唯一号分配 + 合法 UUID tag + TestAC9 子测试 crID 拆分。
- `server/pkg/db/queries/approval.sql`：JOIN 重排 + 移除 `updated_at`。
- `server/pkg/db/generated/approval.sql.go`：sqlc 重生成。

## 未覆盖风险

- **共享 `multica` 库迁移漂移（环境问题，非本 CR 引入）**：`schema_migrations` 缺 95 条（含 404 `agent_starter_prompts`、432 `agent_conversation_starters_rename`、433~468 一批 fork 迁移），导致主 checkout 连接该库时 `SELECT * FROM agent` 会因缺列失败。本轮用专用库 `multica_cr052` 规避。建议另立环境修复任务对共享库 `db-reset` 或补齐迁移，与本 CR 代码交付无关。
- AC-3/AC-4 未单列独立集成测试（其路径由 AC-6/AC-9a/TestGrantDeliveryQueue 间接覆盖）；如需独立锁定可后续补测。

## 下一步建议

- 以 `crctl next CR-2026-052` 为准；本轮已清空 review-code 两条 blocker，可进入 `review-code` 复评（cycle 1 / attempt 2）。
- dev-plan 门禁 freshness 漂移（TASK-02/03 措辞修订导致 subject-sha256 由 d9f9be15→cecf861e）需 `review-dev-plan` 重审刷新，另行执行。
