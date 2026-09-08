---
cr: CR-2026-061
status: block
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-08T22:08:13+08:00"
command-digest: 5f12d71be7c5c25a430e0f29f581d13adab1cf8633fdfaec539b7f858263985c
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [test, -run, "^TestPromotion|^TestPromoteDiscussion|^TestPromoteProjectDiscussion|^TestBindPromotionRun|^TestValidatePromotionRequestShape|^TestParseIssueContextRefs|^TestCanonicalUUIDs|^TestSummarizePromotionContent|^TestBuildPromotionEntry|^TestCreateInTxPromotionRun", ./internal/handler/, ./internal/service/, "-count=1"]
    timeout-seconds: 900
    exit-code: 0
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
    exit-code: 1
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
    args: [--test, "--test-reporter=dot", skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    skipped: false
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

## 测试摘要（cycle 2 / attempt 1，修订版 §6.2 首次 canonical 重跑）

**目标（B-CODE-02/03 修订链）**：按已审批 plan §6.2 修订版重跑 `crctl test --plan`，预期机器 `status=pass`、cmd-05 `skipped=false`。command-digest `5f12d71b…`（cycle 1 的 `0b0c163c…` 因 cmd-01 args 改为 21 项 promotion `-run` 过滤、cmd-05 args 加 `--test-reporter=dot` 而变化，与 §9 修订记录一致）。

**执行环境（透明披露）**：
- 计划 = plan.md §6.2 冻结命令表逐条转录至 `.crctl/tmp/test-plan.json`（cmd-NN 与覆盖矩阵「验收证据」列全等）；未在 plan 之外另造命令集。
- 会话环境：`DATABASE_URL` = 主克隆 `.env` dev 库（迁移 505–507 已应用）+ `GOFLAGS=-v`（逐条 RUN/PASS 可见，不改测试集合/断言/退出码）；`pnpm.exe` shim（Go 转发 wrapper，Windows spawnSync 只解析 .exe）前置 PATH。plan §6.2 口径：cmd-01/02 在 DATABASE_URL 下真库实跑。
- 绑定版本：multica CR 分支 `5aadba5be`（未变）、tools `30b49d2`（未变）、docs 本提交。

**机器区结果**：

| cmd | exit | 解读 |
|---|---|---|
| cmd-01 | 0 | handler 8 + service 13 = **21/21 PASS、0 FAIL、0 SKIP**（`-v` 逐条可见）；`TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs` 真库 **PASS**（B-CODE-01 回归在 canonical 引用日志中执行，B-CODE-02 的 cmd-01 面闭合）；上游既有失败 `TestLoadAgentSkills_*` 被 `-run` 前缀排除（CUSTOM.md 基线） |
| cmd-02 | 1 | governance 5 FAIL + migrate 2 FAIL，全部为上游既有失败（trunk A/B 同症，本 CR 零相关 diff，见下节）；本 CR 相关项全 PASS（`TestGateProjectionReusesBoundPromotionRun`、`TestPromotionMigrationsUpDownRoundtrip`、`TestConcurrentIndexCleanupsMatchTheirMigrations`、`TestEveryConcurrent*`） |
| cmd-03 | 0 | views vitest 全绿 |
| cmd-04 | 0 | core vitest 全绿 |
| cmd-05 | 0, skipped=false | dot reporter 输出仅点号（12 项）、无 `skipped` 字样——B-CODE-03 根因消除，机器区 `skipped=false`（AC-13 tools 消费面 canonical 证据成立） |
| cmd-06 | 0 | lint-prompts enforce 0 findings |

**结论**：机器 `status=block`，唯一原因为 cmd-02；cmd-01/03/04/05/06 全绿，B-CODE-02 的 cmd-01 面与 B-CODE-03 均已闭合。

## cmd-02 失败归因（A/B 已证：上游既有失败，本 CR 零相关 diff）

7 项失败：governance 5 项（`TestAC1_SameRecordTwiceIdempotent`、`TestAC6d_CrossWorkspaceIsolation`、`TestAC5_MergeAndSlotDeferred`、`TestStartArchitectureAdoptsProjectorRunAndDeduplicatesConcurrentStart`、`TestEnqueuePipelineTaskCopiesAttributionAndDeduplicates`）+ migrate 2 项（`TestDiscussionSharedSessionMigrationsUpDownRoundtrip`、`TestCRSyncEventWorkspacePreflightBlocksOrphanAndAmbiguous`）。

- **trunk A/B**：主克隆 trunk（clean main）同环境（同 DATABASE_URL）重跑 `go test ./internal/governance/ ./cmd/migrate/ -count=1` → 上述 7 项全部同症失败（trunk 另有 `TestAC2_FourStagesApproveAndReject` 等额外失败；**本分支失败集 ⊆ trunk 失败集**）→ 非本 CR 引入。
- **zero-diff 核实**：`crctl git diff --name-only eafce66b…`（trunk 基线 vs multica `5aadba5be`）不含 `approval_continuation_test.go`、`runner_integration_test.go`、`migrate_discussion_shared_session_test.go`、`migrate_workspace_seam_test.go` → 本 CR 对失败面零改动。
- **根因示例**：`TestCRSyncEventWorkspacePreflightBlocksOrphanAndAmbiguous` 引用已不存在的 `461_cr_sync_event_workspace_id.up.sql`（该迁移已重编号 475/476；同一测试 happy path 已用新编号，preflight 两处漏改）；`TestDiscussionSharedSessionMigrationsUpDownRoundtrip` 执行 `481_approval_workspace_approve_uniq.up.sql` 时夹具缺 `approval_record` 表。两者均系 AIFIRST（CR-2026-049）遗留测试缺陷，仅在有 DB 时执行（无 DB 时 SKIP——cycle 1 cmd-02 exit=0 即因此）。
- **成因定位**：修订版 §6.2 将「cmd-01/02 在 DATABASE_URL 下真库实跑」写入执行口径，但修订预验仅覆盖 cmd-01（21/21）；cmd-02 整包在真库下首次执行即暴露上述上游既有失败。**已审批 §6.2 在当前执行口径下无法产出机器 `status=pass`（计划层缺陷，与 B-CODE-02/03 同类，位于 cmd-02，未在 review-dev-plan 预验中被发现）**。

## TASK 验收覆盖

- TASK-01..04 的关键 AC 证据面（cmd-01/03/04/05/06）全部通过，含 B-CODE-01 真库回归 PASS、cmd-05 `skipped=false`。
- cmd-02 面的 AC-13（绑定后投影复用同一 run）与 AC-10（迁移与并发索引清理登记）相关测试全部 PASS；7 项失败均不属于任何 AC 验收面。

## 未覆盖风险

1. **cmd-02 上游既有失败（7 项，trunk 同症、本 CR 零 diff）→ 机器区 block**。在 scope 内无法自修复（失败源不在本 CR 批准范围；修 multica 测试文件会移动评审对象 `5aadba5be`，被协调方明令禁止；改冻结 plan 需合法修订链）。合法修复路径：修订 plan §6.2 cmd-02（按 cmd-01 先例以 `-run` 过滤收敛至 AC 相关测试、排除上游既有失败），经既有治理边 `developing → tech-design-reviewed`（`review-code:plan-blocker -> write-dev-plan`，tools `30b49d2` 已含该边）+ review-dev-plan（cycle 2 余 2 轮）+ Ray 重新 `approve --stage dev-start` 后重跑本报告。本报告不代签、不擅自改冻结 plan、不以环境变量绕开命令表（证据完整性不可交易）。
2. cmd-05 skipped 误报已根因消除（dot reporter 无 `skipped` 字样），机器区恒 false。
3. `GOFLAGS=-v`/`DATABASE_URL`/pnpm shim 均为 plan §6.2 明示的会话环境，不属 commands 数组。

## 下一步建议

- `crctl next` = `implement-code`（test-report block 回修路径）；失败集与本 CR 无关，实际回修目标为 plan §6.2 cmd-02 口径——等待协调方与 Ray 按上述合法路径决策。
- 机器区 `status=pass` 前不进入 `review-code` 与人工审批（本报告未委派新 cycle 复评）。