---
cr: CR-2026-061
status: block
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-08T19:29:13+08:00"
command-digest: 0b0c163cde293483c73b275c10dc4c98235cb425e13c7776e0ba76bfe2ac6a95
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/handler/, ./internal/service/, "-count=1"]
    timeout-seconds: 900
    exit-code: 1
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-061/test-evidence/cmd-01.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/governance/, ./cmd/migrate/, "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-061/test-evidence/cmd-02.log
  - repo: multica
    cwd: packages/views
    executable: pnpm
    args: [test]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-061/test-evidence/cmd-03.log
  - repo: multica
    cwd: packages/core
    executable: pnpm
    args: [test]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-061/test-evidence/cmd-04.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: true
    log: change-requests/CR-2026-061/test-evidence/cmd-05.log
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/lint-prompts.mjs, --mode, enforce]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
    log: change-requests/CR-2026-061/test-evidence/cmd-06.log
---

# 测试报告 · CR-2026-061

<!-- crctl:analysis-below -->
## 测试摘要（canonical 重跑 attempt 3，绑定 multica HEAD `5aadba5be`）

**本轮目的（B-CODE-02 回修）**：canonical `test-report.md` 与 `test-evidence/cmd-NN.log` 经 write-test-report / `crctl test --plan` 在**当前修复版本**上重新生成——multica CR 分支 HEAD `5aadba5be`（含 B-CODE-01 修复与新回归测试）、tools `6fbc5c82`、docs CR 分支（本轮提交前 HEAD `a0e676f`）。上一轮修复前 canonical 报告（generated-at `2026-09-08T17:22:33+08:00`）已被本次机器区整体替换；`traceability.yml#tests` 与 `review-loop.yml#write-test-report`（attempt 3）由 crctl 原子更新。

**执行环境（透明披露）**：

- 计划 = plan.md §6.2 冻结命令表（`.crctl/tmp/test-plan.json`），命令集逐条全等 → **command-digest 与上一轮相同**（`0b0c163c…`，plan 未改）；`cmd-NN` 1-based 下标与覆盖矩阵证据列全等。
- `GOFLAGS=-v`：crctl 以 `spawnSync(shell:false)` 继承执行环境，`-v` 使 go test 逐条输出 `=== RUN / --- PASS / --- SKIP / --- FAIL` 行，让**每条测试**（含 DB 依赖 SKIP 与新回归测试）在 canonical cmd-NN 日志中逐条可见。该环境变量不改变测试集合、断言或退出码，仅提高日志可核验性；plan args 未动。
- PATH 前置 `C:\temp\pnpm-shim\pnpm.exe`（Windows spawnSync 不能解析 npm-global 的 .cmd shim，同 attempt 1 记录）。
- **未置 DATABASE_URL**（plan 冻结口径无 env；全包 + DB 组合运行会触发上游既有超时，见「未覆盖风险」#3）。DB 依赖测试按 C6 口径在 canonical 日志中呈现 SKIP，真实执行证据见下节。

**机器区结果**：

| cmd | 结果 | 解读 |
|---|---|---|
| cmd-01 | exit=1 | handler 全绿；service 仅 3 项上游既有 `TestLoadAgentSkills_*` 失败（`scan: 13 destinations for 10 columns`）。日志逐条可见：PASS 225 / FAIL 3 / SKIP 226（DB 依赖测试）。**新回归测试已进入 canonical 日志**：`=== RUN   TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs` + `--- SKIP: … (0.00s)`（DB 依赖）。 |
| cmd-02 | exit=0 | governance + migrate 全绿（0 FAIL）；DB 依赖测试 SKIP 逐条可见（迁移登记断言 `TestEveryConcurrentUpBuildHasCleanup`/`TestConcurrentIndexCleanupsMatchTheirMigrations` 等全 PASS）。 |
| cmd-03 | exit=0 | views：427 文件 / 5040 测试全过。 |
| cmd-04 | exit=0 | core：147 文件 / 1796 测试全过。 |
| cmd-05 | exit=0（skipped=true 误命中） | node --test：tests 12 / pass 12 / fail 0。机器区 skipped=true 为冻结模式表 `\bSKIPPED\b` 误命中 spec reporter 恒打印的 `ℹ skipped 0` 摘要行（非真实 skip）；dot reporter 复核 12 点全绿（输出 `............`）。 |
| cmd-06 | exit=0 | lint-prompts enforce：0 findings。 |

## B-CODE-01 回归的真实 DB 执行证据（当前 HEAD，本轮重新执行）

canonical cmd-01 按 plan 冻结口径不置 DATABASE_URL（原因见「未覆盖风险」#3），新回归测试在 canonical 日志中呈现为 SKIP；其**真实执行**以以下本轮在 `5aadba5be` 上重跑的专项证据证明（dev 库 DATABASE_URL，均 `-v` 确认 PASS 非 SKIP）：

| 命令（cd server） | 结果 |
|---|---|
| `go test ./internal/service/ -run 'TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs' -v -count=1` | **PASS**（B-CODE-01 新回归） |
| `go test ./internal/service/ -run 'Promotion|PromoteDiscussion' -v -count=1` | 12/12 PASS（含新回归 + CreateAndReplay/DedupeHitAndUpgradeBackfill/ForbiddenAndZeroWrites/CreateInTxPromotionRunFailureZeroResidue/PromotionSourcesNeverWriteChatTables 等） |
| `go test ./internal/handler/ -run 'Promotion|PromoteDiscussion|BindPromotionRun' -v -count=1` | 5/5 PASS（endpoint/错误矩阵/双冲突/非 promotion 形状 404 等） |
| `go test ./internal/governance/ -run 'TestGateProjectionReusesBoundPromotionRun' -v -count=1` | PASS |
| `go test ./cmd/migrate/ -run 'TestPromotionMigrationsUpDownRoundtrip' -v -count=1` | PASS（505/506/507 up/down 往返） |

## A/B 与治理（新证据上重新完成，B-CODE-02 条件）

- 绑定版本：multica CR 分支 `5aadba5be`（cmd-01/02/03/04 sourceRevision）、tools `6fbc5c82`（cmd-05/06）；`crctl workspace freshness` allFresh（trunk：multica `eafce66b` / tools `49c46dd`）。
- **A/B 重验（当前版本）**：trunk `eafce66b`（主克隆，clean）同命令 `go test ./internal/handler/ ./internal/service/ -count=1` → 3 项 `TestLoadAgentSkills_*` 失败名单与错误逐条一致（`scan: 13 destinations for 10 columns`：skill 表 13 列 vs 夹具 10 列，上游 fixture 陈旧）。本 CR 零 diff 相关文件（`task_agent_skills_test.go` 非本 CR 改动）。
- 附注：trunk 主克隆另有 5 项 builtin-skills 模板类失败（`TestBuiltinSkillsConformToTemplate`/`TestBuiltinSkillsFrontmatterIsStrictYAML`/`TestLegacyRedirectsFollowTheDaemonsBrief`/`TestPlatformSkillDescriptionNamesEveryDomain`），**本 CR 分支全部通过**——本 CR 失败集 ⊆ trunk 失败集，主克隆多出的失败属其本地技能文件状态，不影响归因。
- **治理口径**：command-digest 与上一轮一致（plan 冻结）；机器区 block 失败集与 Ray ① 人工裁定集完全一致（同一 3 项、同一 root cause、无新增失败类别）；CUSTOM.md《已知测试失败基线》登记保持权威。裁定前提未变，按 ① 口径在新 generated-at / sourceRevision 证据上重新完成。

## TASK 验收覆盖矩阵

| TASK | 验收条件 | 证据 |
|---|---|---|
| TASK-01 数据层 | 迁移 505/506/507 + promotion.sql 查询 + migrate 登记 | cmd-02（登记断言 PASS；DB 面 SKIP 可见）+ DB 专项 `TestPromotionMigrationsUpDownRoundtrip` PASS |
| TASK-02 服务内核 | createInTx 唯一写入路径/幂等四分支/查重补建/零残留；**B-CODE-01 元素级合并语义** | cmd-01（纯函数组与零写结构测试 PASS；DB 面 SKIP 可见）+ DB 专项 12/12 PASS（含 `TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs`） |
| TASK-03 HTTP/绑定/CLI | promotion 端点错误闭包/context_refs 暴露/bind 端点/CLI/投影复用 | cmd-01（handler 全绿）+ DB 专项 handler 5/5 PASS + governance 投影 PASS |
| TASK-04 前端+tools | cmd-03/04/05/06 | cmd-03 5040 / cmd-04 1796 / cmd-05 12/12（skipped 误命中）/ cmd-06 0 findings |

## 新增/修改测试文件

同 B-CODE-01 修复轮：`server/internal/service/promotion_test.go` 新增 `TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs`（真实 DB 异构三元素回归：matched extra/nested 字段保留、legacy jsonb 全等、另一 promotion 条目不污染）；其余测试文件清单不变。

## 未覆盖风险

1. **cmd-01 机器区 block（唯一来源）**：3 项 `TestLoadAgentSkills_*` 上游既有 fixture 陈旧失败。A/B 已在当前版本重验（见上）、CUSTOM.md 基线已登记、Ray ① 已人工核定（root cause 未变）。自修复在批准范围外（改上游测试文件属 scope_out，CR-2026-057 FR-7 禁止）。
2. **cmd-05 机器区 `skipped=true` 为冻结模式表误命中**：`ℹ skipped 0` 摘要行命中 `\bSKIPPED\b`，非真实 skip；dot reporter 12/12 全绿。根治需 plan §6.2 cmd-05 加 `--test-reporter=dot`（plan 冻结，需经 review-dev-plan 合法修订，本轮未动）。
3. **DB 全包组合运行不可行（上游既有；canonical 不置 DB 的原因）**：`DATABASE_URL` 置位时 service 全包在无关并行测试（chat_config 组）处 `panic: test timed out after 10m0s`（attempt 2 实测，已由 attempt 3 无 DB 运行覆盖）；trunk 同命令同症类别。canonical cmd-01/02 因此保持 plan 冻结口径（无 DB），DB 面由专项证据覆盖。attempt 2 DB 置位暴露的 5 项 DB 测试失败——governance `TestStartArchitectureAdoptsProjectorRunAndDeduplicatesConcurrentStart`/`TestEnqueuePipelineTaskCopiesAttributionAndDeduplicates`（`RUNNER_ATTRIBUTION_INVALID`）、migrate `TestDiscussionSharedSessionMigrationsUpDownRoundtrip`（dev 库 `approval_record` 缺失）、`TestCRSyncEventWorkspacePreflightBlocksOrphanAndAmbiguous`（迁移文件 461 缺失）——**已 A/B 确认 trunk 全同**，非本 CR 回归。
4. **环境 shim**：pnpm.exe PATH shim（同 attempt 1）；`GOFLAGS=-v` 仅提高日志逐条可见性（见测试摘要，不改测试集合/断言/退出码）。

## 下一步建议

机器区 status=block 归因仍为同一上游既有失败集（Ray ① 已裁定；A/B 与基线登记已在新证据上重新完成），按 B-CODE-02 修复方向可进入 review-code attempt 3/3。若评审仍要求本 CR 自查面机器全 pass，唯一路径是经 review-dev-plan 修订 plan §6.2（② 路径），本轮未启动。

