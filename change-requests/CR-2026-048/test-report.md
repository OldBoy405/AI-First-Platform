---
cr: CR-2026-048
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-20T17:10:30+08:00"
command-digest: d16543657ef121d22a9f6f5f14fc70cfa492cb1cdeed6cfc7b3299d5cbe85068
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/skill/, "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-01.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./pkg/redact/, "-count=1", -run, "TestFindings|TestPatternsSingleNamedTable"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-02.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./cmd/migrate/, "-count=1", -run, Concurrent]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-03.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/handler/, "-count=1", -run, "TestUpdateSkill|TestAppealFlow|TestGetSkillMarket|TestClaimTaskByRuntimeWritesSkillUsageTelemetry"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-04.log
  - repo: multica
    cwd: server
    executable: go
    args: [build, ./...]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-05.log
  - repo: multica
    cwd: .
    executable: node
    args: [node_modules/typescript/bin/tsc, --noEmit, -p, packages/core/tsconfig.json]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-06.log
  - repo: multica
    cwd: .
    executable: node
    args: [node_modules/typescript/bin/tsc, --noEmit, -p, packages/views/tsconfig.json]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-07.log
---

# 测试报告 · CR-2026-048

<!-- crctl:analysis-below -->
## 测试摘要

7 条验证命令全部 exit 0（详见上方机器区与 `test-evidence/cmd-*.log`）。执行环境：Windows + Go 1.26.4 + 真实 PostgreSQL（`postgres://multica:multica@localhost:5432/multica`，迁移 380–384 已应用并完成一次 down/up 回滚验证，373 的存量 CHECK 冲突与 CR-2026-047 记录一致，与本 CR 无关）。

## TASK 验收覆盖矩阵

| TASK | 验收 | 证据 |
|---|---|---|
| TASK-01 迁移 | AC-1/AC-14/AC-15 | cmd-03（`TestEveryConcurrentUpBuildHasCleanup` 归零）；真实 PG 上 `migrate up` 成功、`down 380` 中 384→380 全部回滚成功（373 拦截为上游存量问题）；无 FK 断言在迁移 SQL 内由仓规约保证 |
| TASK-02 redact | AC-10 | cmd-02：`TestPatternsSingleNamedTable`（16 条、name 唯一非空）+ `TestFindingsLocatesSecretsWithoutLeakingPlaintext`（行号/pattern_id/脱敏 excerpt） |
| TASK-03 frontmatter | AC-7/AC-13 | cmd-01：`TestParseSkillMetadataExtractsCardFields`/`ToleratesBadInput`/`ParseSkillFrontmatterStillCompatible` |
| TASK-04 门禁 | AC-2/AC-9 的纯函数半边 | cmd-01：`TestEvaluatePublish*` 五条 + `TestAppealIDIsDeterministicAndContentSensitive` + `TestProtectedPathPatternsPin` |
| TASK-05 sqlc | AC-5/AC-11/AC-14 | cmd-05 编译通过；`make sqlc` 生成物只含预期文件（models.go/skill.sql.go/skill_market.sql.go/workspace_delete.sql.go） |
| TASK-06 遥测 | AC-3/AC-4 | cmd-04：`TestClaimTaskByRuntimeWritesSkillUsageTelemetry`（真库：claim 写行、workspace 隔离、builtin ref）；`TaskCompleteRequest` 零改动以 diff 为证（本 CR 未触碰该结构） |
| TASK-07 发布/申诉 | AC-2/AC-6/AC-7/AC-8/AC-9/AC-10/AC-11 | cmd-04：发布拦截 422 不部分更新、干净发布成功、org 内容更新重扫、申诉 403/幂等/放行后重发通过、runtime-local 覆盖导入门禁（`overwriteSkillWithFiles` 挂点 + `errSkillPublishGateBlocked`） |
| TASK-08 market | AC-3/AC-5 | cmd-04：`TestGetSkillMarketScopesAndDedupes`（org 过滤、completed 去重、失败任务不计、builtin 上榜） |
| TASK-09 前端 | AC-12/AC-13 | cmd-06/07：core + views typecheck 全过；4 份 locale 的 market 键集合一致（vitest 因本机 Node 24 loader 与 vitest 4 不兼容无法启动，已用等价脚本核验键一致性并在此说明） |
| TASK-10 收口 | AC-16/AC-4 | CUSTOM.md 第 48 行台账已登记；全量 `go test ./...` 失败名单与既有基线一致，无新增回归（见下） |

## 未覆盖与已知基线

- **全量测试基线（既有，非本 CR 引入）**：`pkg/redact` 的 `TestRedactHomeDirectory`（本机域前缀用户名 `DESKTOP-OT18TRG\GOBAO` 使 homeDir 掩码失效，stash 回退后同样失败）、`cmd/multica`/`internal/cli`/`internal/daemon` 等 Windows 环境假设失败、`internal/handler` 的 `TestWorkspaceDeletionManifestCoversPublicSchema`（7 张先前 CR 的表未入 manifest 的既有漂移，本 CR 已把新增的 `skill_usage_event` 登记并实现删除图，漂移清单从 8 项降为 7 项）、`internal/service` 的 builtin_skills CRLF 断言失败——全部与 CUSTOM.md「已知测试失败基线」表一致或为同一类环境假设。
- **未运行**：前端 vitest（vitest 4 在本机 Node v24 启动即报 `ERR_PACKAGE_IMPORT_NOT_DEFINED #module-evaluator`，环境问题而非代码问题）；真实 PG 下的 `TestUpdateSkillSkipsSkillMdFile` 等既有 skill 测试未单独复跑（cmd-04 的 -run 范围已覆盖本 CR 全部新增用例）。
- **观察项**：claim 遥测的插入失败非阻断路径没有注入式测试（fixture 注入成本高于收益，代码路径为 slog.Error + continue，不改变 claim 结果，语义由构造保证）。
