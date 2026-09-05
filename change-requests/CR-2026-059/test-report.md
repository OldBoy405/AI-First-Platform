---
cr: CR-2026-059
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-05T09:40:45+08:00"
command-digest: 73e16bfaef31ed70b9500fda17c2e3f1f17f5f60ae28479c8f36c7aec378d706
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./cmd/migrate/, "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-059/test-evidence/cmd-01.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/handler/, ./internal/service/, "-count=1"]
    timeout-seconds: 1800
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-059/test-evidence/cmd-02.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/handler/, "-count=1"]
    timeout-seconds: 1800
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-059/test-evidence/cmd-03.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./pkg/agent/, -run, "ValidateChatConfig|ModelIDForCapabilityLookup|StaticCatalog|ChatConfig", "-count=1"]
    timeout-seconds: 1800
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-059/test-evidence/cmd-04.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./cmd/server/, ./internal/handler/, ./internal/service/, ./internal/realtime/, "-count=1"]
    timeout-seconds: 1800
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-059/test-evidence/cmd-05.log
  - repo: multica
    cwd: packages/core
    executable: node
    args: [node_modules/vitest/vitest.mjs, run, api/schemas.test.ts]
    timeout-seconds: 1200
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-059/test-evidence/cmd-06.log
  - repo: multica
    cwd: packages/views
    executable: node
    args: [node_modules/vitest/vitest.mjs, run, locales/parity.test.ts, projects/components/discussion-pane.test.tsx]
    timeout-seconds: 1200
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-059/test-evidence/cmd-07.log
---

# 测试报告 · CR-2026-059

<!-- crctl:analysis-below -->

# 测试摘要（CR-2026-059，TASK-01~04）

- **tester**: Ray（`cr.md owners.test`）；执行环境：Windows 本机 + 真 PostgreSQL（migrations 481–490 已按 §4.9 部署序应用）。
- **结果**: **status=pass**——7 条 canonical 命令全部 exit 0（attempt 3/3，write-test-report loop 2→3 已闭环）。
- **本 attempt 的唯一变更**：plan.md §6.2 证据命令表修订（coordinator ① 裁定链，2026-09-05）：
  - cmd-03 由 `./internal/handler/ ./pkg/agent/` 全包收敛为 `./internal/handler/`（AC-9/10 handler 臂，全绿）；
  - AC-21 独立为 cmd-04：`./pkg/agent/ -run 'ValidateChatConfig|ModelIDForCapabilityLookup|StaticCatalog|ChatConfig'`（已单独全绿的子集形态）；
  - 原 cmd-04/05/06 顺延为 cmd-05/06/07；§6.1 交付覆盖表「验收证据」列（FR-19/FR-20 行）、§7 AC 矩阵（AC-6/17/18/21/29 行）、TASK-03/04 卡全部 cmd-NN 下游引用已同步重编号；§6.1 A=B 双向集合断言（TASK id）不受影响。
- 实现产物不变：multica 仓 commits `eaa054032`（TASK-01）→ `575e13aaa`（TASK-02）→ `e1ee77488`（TASK-03）→ `2054e8662`（TASK-04）→ `b4207c321`（幂等键收尾）→ `6027a340b`（③ 裁定台账扩记）；`tasks/_index.yml` 四 TASK 均已 `crctl task done`。

# 命令结果与解读

| cmd | 结果 | 覆盖 | 备注 |
|---|---|---|---|
| cmd-01 | ✅ exit 0 | AC-19（迁移注册 total 不变量、运行器并发锁、481–490 up/down 往返） | 无 DATABASE_URL 时 DB 子测试 SKIP；真库补证见下 |
| cmd-02 | ✅ exit 0 | AC-1..5/7/8/11..16/20/22..28 的 handler/service 夹具 | 真库补证见下（shared 会话全套向量真跑绿） |
| cmd-03 | ✅ exit 0 | AC-9/10 配置 authority 阶梯 handler 臂（非 owner 403 + 不调 `UpdateAgent`、非法配置 PATCH/入队 400） | 2026-09-05 修订：收敛为 `./internal/handler/` 全绿形态 |
| cmd-04 | ✅ exit 0 | AC-21 配置校验单一实现（`-run` 子集） | 2026-09-05 修订：`pkg/agent` 全包不再进入证据命令（归因见下） |
| cmd-05 | ✅ exit 0 | AC-29/FR-20 联合面（listeners kind 路由、断连控制、双节点向量） | 含本 CR 新增 `disconnect_control_test.go` |
| cmd-06 | ✅ exit 0 | AC-17（schema 硬降级 + 作者 malformed 降级） | 162/162 |
| cmd-07 | ✅ exit 0 | AC-6/AC-18/NFR-2（pane 行为 + 四语 parity） | 169/169（两文件） |

# §6.2 修订归因（2026-09-05，① 裁定链）

- attempt-2 时 cmd-03 = `go test ./internal/handler/ ./pkg/agent/ -count=1` 中 `pkg/agent` 全包 163 项失败，全部是上游测试的 Windows 环境假设（fake CLI 可执行文件不带 `.exe`、路径引号/shell 安全断言与 Windows 分隔符不符），与本 CR 零关联：本 CR diff 不含任何 `pkg/agent` 文件；未改动 multica 主克隆（`C:\Users\GOBAO\Downloads\AI\multica`）跑同一命令失败名单逐条一致（A/B 基线对比，2026-09-05）。
- Ray 先前 ③ 裁定（按 CUSTOM.md《已知测试失败基线》条款人工核定不阻塞）已记录于 attempt-2 分析段并扩记台账（multica commit `6027a340b`），但 crctl 机器区无人工豁免字段，canonical 命令 exit 1 使 status=block。
- Ray 2026-09-05 01:24 选定 ①：修订 plan.md §6.2，把 cmd-03 收敛为 AC-21 覆盖子集形态——handler 臂保留全绿（cmd-03），AC-21 以已单独全绿的 `-run` 子集独立为 cmd-04，下游 cmd 引用全部同步重编号。修订后形态先自跑证明 exit 0（`go test ./internal/handler/ -count=1` ✅；`go test ./pkg/agent/ -run 'ValidateChatConfig|ModelIDForCapabilityLookup|StaticCatalog|ChatConfig' -count=1` ✅），再以 `crctl test` 机器区 7 命令全量复跑，全部 exit 0。

# 真库补证（补充证据，不替代 canonical 命令）

以下命令以真实 DATABASE_URL（开发库，481–490 已应用）运行，全部 exit 0：

- `go test ./cmd/migrate/ -count=1` ✅ — 含新增 `TestDiscussionSharedSessionMigrationsUpDownRoundtrip`（481–490 up→down 逆序往返、481 FK SET NULL 形态、484.down 重建、487/488/489 幂等表三段、486 作者列）。
- `go test ./internal/handler/ -run 'TestSharedDiscussion|TestGetProjectDiscussion' -count=1` ✅ — AC-1（GET 不建 Issue、幂等、kind 断言）、AC-3（普通消息零 task + 作者列）、AC-4（协办 task issue_id NULL + chat_config 快照 + direct_human 归因）、AC-11（未配置 409 零写入）、AC-12/13（B-DP-02 跨上传者 409 零残留）、AC-20（非成员/归档/闭包门禁）、AC-26（幂等重放/异指纹 409）、AC-27（merge-forward 重放同 comment/task id）。
- `go test ./internal/realtime/ -run 'Disconnect|ControlFrame' -count=1` ✅、`go test ./cmd/server/ -run TestChatEvent -count=1` ✅。

# TASK 验收覆盖矩阵

| TASK | 验收命令 | 状态 | 证据 |
|---|---|---|---|
| TASK-01 | cmd-01 + 真库往返 | ✅ | cmd-01.log + 补证 |
| TASK-02 | handler+service 单测矩阵（纯逻辑）+ shared 真库向量 + AC-21 子集 | ✅ | 补证 + cmd-02/04.log |
| TASK-03 | handler 矩阵/断连/路由 + cmd-02/05 | ✅ | cmd-02/05.log + 补证 |
| TASK-04 | cmd-06 + cmd-07 + 两包 typecheck | ✅ | cmd-06/07.log；`pnpm typecheck`（core/views）exit 0 |

# 新增/修改测试文件

- `server/cmd/migrate/migrate_discussion_shared_session_test.go`（新，真库往返）
- `server/internal/service/discussion_session_test.go`（新，触发矩阵/指纹序不变性/去重保序/合并渲染）
- `server/internal/handler/discussion_shared_session_test.go`（新，shared 会话真库向量）
- `server/internal/realtime/disconnect_control_test.go`（新，断连/控制帧）
- `server/cmd/server/chat_event_privacy_test.go`（新，kind 路由向量）
- `packages/core/api/schemas.test.ts`（新，ProjectDiscussion/ChatMessage 作者/DiscussionSendResult 向量）
- `packages/views/projects/components/discussion-pane.test.tsx`（重写，9 向量）

# 未覆盖风险（不适用说明）

1. **pkg/agent 全包**（原 cmd-03 形态）：Windows 环境基线失败（上游测试假设），Linux/CI 上应绿。已按 ① 裁定从证据命令表收敛，AC-21 以 `-run` 子集（cmd-04）覆盖；全包失败明细与 A/B 证据已记 CUSTOM.md《已知测试失败基线》（2026-09-05，commit `6027a340b`）。
2. **真库并行夹具**（cmd-02 带 DATABASE_URL 形态）：`TestSweepChatDraftAttachmentsAgeBoundary` 为上游既有真库测试缺陷（`$1::text` 参数类型推断冲突 + 失败后事务未回滚导致清理挂起），在未改动基线同样失败；故 canonical cmd-02 以无库形态运行，shared 会话相关真库向量以上述补证覆盖。
3. 迁移钩子 `concurrentIndexCleanups` 补入的 CR-2026-052/056 历史遗漏条目属登记-only 变更（每条至多一次 to_regclass 查询），已随 `TestEveryConcurrentUpBuildHasCleanup`/`TestConcurrentIndexCleanupsMatchTheirMigrations` 验证。

# 下一步建议

- test-report.status=pass，write-test-report loop 3/3 已闭环。下一步按管线：push-progress（代码与测试证据统一 checkpoint）→ workspace-freshness（review-start）→ review-code 委派全新 quality-reviewer run（本 agent 不自评）；PASS 后停在 approve-code 前 checkpoint。
