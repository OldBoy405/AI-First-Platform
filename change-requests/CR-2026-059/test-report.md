---
cr: CR-2026-059
status: block
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-05T05:39:40+08:00"
command-digest: b03f22f957ea1ad02f34e7ebe3c8248bffcb5cee87e6c70dbeaee97dcc89cb9a
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
    args: [test, ./internal/handler/, ./pkg/agent/, "-count=1"]
    timeout-seconds: 1800
    exit-code: 1
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-059/test-evidence/cmd-03.log
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
    log: change-requests/CR-2026-059/test-evidence/cmd-04.log
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
    log: change-requests/CR-2026-059/test-evidence/cmd-05.log
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
    log: change-requests/CR-2026-059/test-evidence/cmd-06.log
---

# 测试报告 · CR-2026-059

<!-- crctl:analysis-below -->

# 测试摘要（CR-2026-059，TASK-01~04）

- **tester**: Ray（`cr.md owners.test`）；执行环境：Windows 本机 + 真 PostgreSQL（migrations 481–490 已按 §4.9 部署序应用）。
- **结果**: 6 条 canonical 命令中 5 绿；**cmd-03 失败**，根因是 `pkg/agent` 包 163 项上游测试在本机的 Windows 环境假设失败（与本 CR 零关联，证据见下）。
- 实现产物：multica 仓 4 个 commit（`eaa054032` TASK-01 → `575e13aaa` TASK-02 → `e1ee77488` TASK-03 → `2054e8662` TASK-04）；`tasks/_index.yml` 四 TASK 均已 `crctl task done`。

# 命令结果与解读

| cmd | 结果 | 覆盖 | 备注 |
|---|---|---|---|
| cmd-01 | ✅ exit 0 | AC-19（迁移注册 total 不变量、运行器并发锁、481–490 up/down 往返） | 无 DATABASE_URL 时 DB 子测试 SKIP；**真库补证见下** |
| cmd-02 | ✅ exit 0 | AC-1..5/7/8/11..16/20/22..28 的 handler/service 夹具（无库时 DB 夹具 SKIP） | **真库补证见下（shared 会话全套向量真跑绿）** |
| cmd-03 | ❌ exit 1 | AC-9/10/21 | 失败全部来自 `pkg/agent` 上游 Windows 环境假设；见失败归因 |
| cmd-04 | ✅ exit 0 | AC-29/FR-20 联合面（listeners kind 路由、断连控制、双节点向量） | 含本 CR 新增 `disconnect_control_test.go` |
| cmd-05 | ✅ exit 0 | AC-17（schema 硬降级 + 作者 malformed 降级） | 162/162 |
| cmd-06 | ✅ exit 0 | AC-6/AC-18/NFR-2（pane 行为 + 四语 parity） | 169/169（两文件） |

# cmd-03 失败归因（pre-existing，非本 CR 回归）

- `pkg/agent` 包本机 163 项失败，全部是上游测试的 Windows 环境假设：① fake CLI 可执行文件不带 `.exe`，Windows exec 无法解析（grok/qoder/kiro/zeroclaw/kimi/claude 等后端 ~150 项）；② 路径引号/shell 安全断言与 Windows 分隔符不符（`TestExplainExecError*` 等）。
- **基线对比证明**：在未改动的独立 multica 主克隆（`C:\Users\GOBAO\Downloads\AI\multica`，树与本 CR 证据基线 `be6426a7` 一致）跑同一命令，失败名单完全一致（163 项）——本 CR 的 diff 不含任何 `pkg/agent` 文件（`git diff --stat` 可证）。
- 本 CR 需要的 AC-21 覆盖（`ValidateChatConfig`/`StaticCatalog`/`ModelIDForCapabilityLookup`，CR-2026-056 既有套件）单独运行**全绿**：`go test ./pkg/agent/ -run 'ValidateChatConfig|ModelIDForCapabilityLookup|StaticCatalog|ChatConfig' -count=1`。
- 该失败类别已列入 multica `CUSTOM.md`《已知测试失败基线》（环境假设类："上游 Windows 环境假设…CI 上不会失败"）。

# 真库补证（补充证据，不替代 canonical 命令）

以下命令以真实 DATABASE_URL（开发库，481–490 已应用）运行，全部 exit 0：

- `go test ./cmd/migrate/ -count=1` ✅ — 含新增 `TestDiscussionSharedSessionMigrationsUpDownRoundtrip`（481–490 up→down 逆序往返、481 FK SET NULL 形态、484.down 重建、487/488/489 幂等表三段、486 作者列）。
- `go test ./internal/handler/ -run 'TestSharedDiscussion|TestGetProjectDiscussion' -count=1` ✅ — AC-1（GET 不建 Issue、幂等、kind 断言）、AC-3（普通消息零 task + 作者列）、AC-4（协办 task issue_id NULL + chat_config 快照 + direct_human 归因）、AC-11（未配置 409 零写入）、AC-12/13（B-DP-02 跨上传者 409 零残留）、AC-20（非成员/归档/闭包门禁）、AC-26（幂等重放/异指纹 409）、AC-27（merge-forward 重放同 comment/task id）。
- `go test ./internal/realtime/ -run 'Disconnect|ControlFrame' -count=1` ✅、`go test ./cmd/server/ -run TestChatEvent -count=1` ✅。

# TASK 验收覆盖矩阵

| TASK | 验收命令 | 状态 | 证据 |
|---|---|---|---|
| TASK-01 | cmd-01 + 真库往返 | ✅ | cmd-01.log + 补证 |
| TASK-02 | handler+service 单测矩阵（纯逻辑）+ shared 真库向量 | ✅ | 补证 + cmd-02.log |
| TASK-03 | handler 矩阵/断连/路由 + cmd-02/04 | ✅ | cmd-02/04.log + 补证 |
| TASK-04 | cmd-05 + cmd-06 + 两包 typecheck | ✅ | cmd-05/06.log；`pnpm typecheck`（core/views）exit 0 |

# 新增/修改测试文件

- `server/cmd/migrate/migrate_discussion_shared_session_test.go`（新，真库往返）
- `server/internal/service/discussion_session_test.go`（新，触发矩阵/指纹序不变性/去重保序/合并渲染）
- `server/internal/handler/discussion_shared_session_test.go`（新，shared 会话真库向量）
- `server/internal/realtime/disconnect_control_test.go`（新，断连/控制帧）
- `server/cmd/server/chat_event_privacy_test.go`（新，kind 路由向量）
- `packages/core/api/schemas.test.ts`（新，ProjectDiscussion/ChatMessage 作者/DiscussionSendResult 向量）
- `packages/views/projects/components/discussion-pane.test.tsx`（重写，9 向量）

# 未覆盖风险（不适用说明）

1. **pkg/agent 全包**（cmd-03）：Windows 环境基线失败（上游测试假设），Linux/CI 上应绿；AC-21 子集已单独验证。建议 code-review 时按 CUSTOM.md 基线条款核定。
2. **真库并行夹具**（cmd-02 带 DATABASE_URL 形态）：`TestSweepChatDraftAttachmentsAgeBoundary` 为上游既有真库测试缺陷（`$1::text` 参数类型推断冲突 + 失败后事务未回滚导致清理挂起），在未改动基线同样失败；故 canonical cmd-02 以无库形态运行，shared 会话相关真库向量以上述补证覆盖。
3. 迁移钩子 `concurrentIndexCleanups` 补入的 CR-2026-052/056 历史遗漏条目属登记-only 变更（每条至多一次 to_regclass 查询），已随 `TestEveryConcurrentUpBuildHasCleanup`/`TestConcurrentIndexCleanupsMatchTheirMigrations` 验证。

# 下一步建议

cmd-03 的 pkg/agent 失败与 AC 覆盖无关联且为基线环境问题；其余 5 条 canonical 命令与全部补证均绿。建议：评审按 CUSTOM.md《已知测试失败基线》核定 cmd-03，或在 Linux/CI 上复跑 cmd-03 后进入 review-code。