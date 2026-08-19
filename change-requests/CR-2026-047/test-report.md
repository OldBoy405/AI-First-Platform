---
cr: CR-2026-047
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-20T04:39:35+08:00"
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

ponytail 模式实现（2026-08-20）。8 条机器命令全绿（exit-code 全 0），`status=pass`：

| # | 套件 | 结果 |
|---|---|---|
| 1 | 配置生成器（node --test，9 用例） | ✅ 9/9 |
| 2 | Go maturity/migrations/migrate（真实 PG） | ✅ ok |
| 3 | Go service（rollup 集成 + 读路径 + envelope + Org Admin 幂等 + 纯函数，真实 PG） | ✅ ok |
| 4 | Go scheduler（hook 补偿 fixed-clock，真实 PG） | ✅ 5/5 |
| 5 | Go handler（六端点 400 守卫） | ✅ 6/6 |
| 6 | core zod malformed + paths 一致性（vitest） | ✅ 82/82 |
| 7 | views maturity/layout/search（vitest） | ✅ 133/133 |
| 8 | go vet 五个包 | ✅ 零告警 |

另：真实 PostgreSQL 迁移 375–379 up/down/up 已执行（379→375 逆序回滚成功；`down` 全程在 373 因上游存量 CHECK 冲突中止，与本 CR 无关，见 test-mapping.md R-1）；EXPLAIN 命中 378/379 由 `TestMaturityIndexesServeTheirQueries` 钉死。

## TASK 验收覆盖矩阵

11/11 TASK 已 `crctl task done`；AC-1~AC-22 → 测试用例逐条映射见 `test-mapping.md`（本文件同目录）。

## 新增/修改测试文件

- `server/internal/maturity/schema_test.go`、`score_test.go`
- `server/internal/maturity/gen/generate-config.test.mjs`
- `server/internal/service/maturity_rollup_test.go`、`maturity_rollup_db_test.go`、`maturity_rollup_crosscheck_test.go`、`maturity_test.go`、`maturity_index_explain_test.go`、`org_admin_test.go`
- `server/internal/scheduler/jobs_maturity_test.go`
- `server/internal/handler/maturity_test.go`
- `packages/core/api/maturity-schemas.test.ts`
- `packages/views/dashboard/maturity/maturity-page.test.tsx`

## 未覆盖风险

1. **daemon 全链路（AC-18 后半）**：文件落盘 + inbox 通知 + 同周去重需真实 daemon + local_directory 绑定环境，本会话未跑；写侧（envelope/SHA/report_key 幂等）已全覆盖。
2. **基线端到端（AC-22 后半）**：28 个连续 org bucket 的端到端建议 fixture 未实现（需 28 天数据）；SQL 分位数语义已钉死，观察期结束后由首份真实周报验证。
3. **前端三件式复用偏差**：sibling 组件与 usage 领域类型耦合，maturity 页改为同构自实现（CUSTOM.md #46 记录）；若后续 CR 把三组件重构为通用原语，可回切复用。
4. **实现期新增 2 个未列名的 sqlc 查询**：`MaturityTaskDepthRows`、`MaturitySnapshotFirstBucket`（TASK-06 卡文字本身要求的能力依赖）。

## 下一步建议

按用户指令跳过代码评审（review-code）；下一步为人工 `approve-code`（需先将状态推进到 `code-reviewing`，请用户按 `crctl next` 权威建议操作）。
