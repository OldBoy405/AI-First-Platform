---
cr: CR-2026-047
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-20T09:04:11+08:00"
command-digest: 2ba50d7e2b16d433412a8846fbd99214ab3c87d59320bee29e3f4a8510ade5f7
commands:
  - repo: multica
    cwd: .
    executable: node
    args: [--test, server/internal/maturity/gen/generate-config.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-047/test-evidence/cmd-01.log
  - repo: multica
    cwd: .
    executable: go
    args: [-C, server, test, ./internal/maturity/, ./internal/migrations/, ./cmd/migrate/, "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-047/test-evidence/cmd-02.log
  - repo: multica
    cwd: .
    executable: go
    args: [-C, server, test, ./internal/service/, -run, "Maturity|TestBuildReportEnvelope|TestEnsureOrgAdminWorkspaceIdempotent|TestPreviousLocalDate|TestDayWindowUTC|TestPercentileCont|TestCostFromTokenRows|TestTaskCoverage|TestNormalizeModel|TestValidateSnapshotMetrics", "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-047/test-evidence/cmd-03.log
  - repo: multica
    cwd: .
    executable: go
    args: [-C, server, test, ./internal/scheduler/, -run, TestMaturity, "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-047/test-evidence/cmd-04.log
  - repo: multica
    cwd: .
    executable: go
    args: [-C, server, test, ./internal/handler/, -run, TestMaturityHandlerGuards, "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-047/test-evidence/cmd-05.log
  - repo: multica
    cwd: packages/core
    executable: node
    args: [node_modules/vitest/vitest.mjs, run, api/maturity-schemas.test.ts, paths]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-047/test-evidence/cmd-06.log
  - repo: multica
    cwd: packages/views
    executable: node
    args: [node_modules/vitest/vitest.mjs, run, dashboard/maturity, layout, search]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-047/test-evidence/cmd-07.log
  - repo: multica
    cwd: .
    executable: go
    args: [-C, server, vet, ./internal/maturity/, ./internal/service/, ./internal/scheduler/, ./internal/handler/, ./cmd/migrate/]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-047/test-evidence/cmd-08.log
---

# 测试报告 · CR-2026-047

<!-- crctl:analysis-below -->

## 测试摘要

代码评审 attempt 1 BLOCK 修复后重新生成 canonical 证据（attempt 3）。8 条机器命令均已启动且 exit-code=0，`status=pass`：

| # | 套件 | 结果 |
|---|---|---|
| 1 | 配置生成器（含 LF/CRLF、dirty guard、漂移与失败硬退出） | ✅ 9/9 |
| 2 | Go maturity/migrations/migrate | ✅ PASS |
| 3 | Go service（真实 PostgreSQL：rollup、latest/daily trend、28 日 baseline、Org Admin dispatch→completion→chat/inbox） | ✅ PASS |
| 4 | Go scheduler（补洞、FAILED retry、fixed-clock） | ✅ PASS |
| 5 | Go handler（六端点边界与隐私守卫） | ✅ PASS |
| 6 | core schema + paths（vitest） | ✅ 82/82 |
| 7 | views maturity/layout/search（vitest） | ✅ 134/134 |
| 8 | go vet 五个包 | ✅ 零告警 |

补充验证：`go build ./...`、core 全量 vitest 132 files / 1550 tests、core/views typecheck、core diagnostics route parity 97 tests均通过。真实 PostgreSQL 的 migration 375–379 逆序回滚及 EXPLAIN 378/379 命中证据继续有效。

## BLOCK 修复验证

- E1：目标 bucket 精确幂等，较新 bucket 成功后旧 FAILED bucket 仍可补洞；AI penetration 按 task initiator 统计且 user scope 组织指标全部 `not_applicable`、`scores={}`。
- E2：latest 使用 `ORDER BY bucket_date DESC LIMIT 1`；model 趋势按 Asia/Shanghai 自然日分桶；provider/model 价格优先于 bare-model fallback；UI 增加日期范围、Owner mode、每日趋势、config revision 断点、Token/质量配对与 8 项可刷性说明。
- E3：真实 PostgreSQL 测试覆盖 Autopilot rule version、项目/复用 chat 绑定、无效 envelope fail-closed、direct envelope 持久化、assistant chat、Owner inbox，以及同 ISO week 第二个 retry task 的 inbox 去重；普通 Org Admin 追问不被误判为报告完成。
- 工程：sqlc 使用 pinned `make sqlc` 重生；rollup 主文件已拆分至 800 行以内；集成挂点与 `CUSTOM.md` 已登记。

## TASK 验收覆盖矩阵

11/11 TASK 已 `crctl task done`；AC-1～AC-22 的逐项可执行映射见同目录 `test-mapping.md`。

## 新增/修改测试文件

- `server/internal/maturity/{schema_test.go,score_test.go}`、`gen/generate-config.test.mjs`
- `server/internal/service/{maturity_rollup_test.go,maturity_rollup_db_test.go,maturity_rollup_crosscheck_test.go,maturity_test.go,maturity_index_explain_test.go,maturity_baseline_db_test.go,org_admin_test.go}`
- `server/internal/scheduler/jobs_maturity_test.go`
- `server/internal/handler/maturity_test.go`
- `packages/core/api/maturity-schemas.test.ts` 与既有 paths/diagnostics parity tests
- `packages/views/dashboard/maturity/maturity-page.test.tsx`

## 未覆盖风险

1. **真实 daemon 文件系统**：server 侧 production dispatch/completion/chat/inbox 已用真实 PostgreSQL贯通；内置 skill 的 temp-file + atomic rename 仍未在实际 daemon + `local_directory` 环境执行，部署验收需补一轮。
2. **全量 views 基线**：补充全量 views 运行有 3 个失败，均位于本 CR merge-base 至 HEAD 未改动的 `project-detail.test.tsx` 与 Windows 路径相关 `rich-content-boundary.test.ts`；CR 范围 targeted suite 18 files / 134 tests 与 typecheck 均通过。
3. **浏览器视觉验收**：date range、Owner mode、趋势与断点已有组件测试，但未进行真实 Web/Desktop 手工视觉与键盘可达性走查。

## 下一步建议

进入 code-review attempt 2；仅在 Standards 与 Spec 双轴均 PASS 且 canonical `review-record` 推进到 `code-reviewing` 后，才交付人工 `approve-code` 指令。
