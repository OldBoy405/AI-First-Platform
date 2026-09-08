---
cr: CR-2026-061
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-08T23:18:42+08:00"
command-digest: 001d7209487ddae986880bacdcfa413e869d45084eac1a4f7d10569bf27db382
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
    args: [test, -run, "^TestGateProjectionReusesBoundPromotionRun|^TestPromotionMigrationsUpDownRoundtrip|^TestConcurrentIndexCleanupsMatchTheirMigrations|^TestEveryConcurrent", ./internal/governance/, ./cmd/migrate/, "-count=1"]
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

## 测试摘要（cycle 2 / attempt 2，§6.2 cmd-02 收敛修订后 canonical 重跑）

**目标（§9.2 修订链第 3 段）**：plan §6.2 cmd-02 收敛修订（`-run` 过滤至 AC-13/AC-10 相关 5 项测试函数，排除 7 项上游既有 DB 期失败）已经 review-dev-plan cycle 2 / attempt 2 PASS（评审提交 `78aedee`）并获 Ray 重批 dev-start；本报告按修订版 §6.2 重跑 `crctl test --plan`。预期与实得一致：机器 `status=pass`、cmd-05 `skipped=false`。command-digest `001d7209…`（相对 attempt 1 的 `5f12d71b…`，唯一变化 = cmd-02 args 收敛，与 §9.2 修订记录一致）。

**执行环境（透明披露）**：
- 计划 = plan.md §6.2 冻结命令表逐条转录至 `.crctl/tmp/test-plan.json`（cmd-NN 与覆盖矩阵「验收证据」列全等）；未在 plan 之外另造命令集。
- 会话环境：`DATABASE_URL` = 主克隆 `.env` dev 库（迁移 505–507 已应用）+ `GOFLAGS=-v`（逐条 RUN/PASS 可见，不改测试集合/断言/退出码）；`pnpm.exe` shim（Go 转发 wrapper，Windows spawnSync 只解析 .exe）前置 PATH。plan §6.2 口径：cmd-01/02 在 DATABASE_URL 下真库实跑。
- 绑定版本：multica CR 分支 `5aadba5be`（未变）、tools `30b49d2`（未变）、docs 本提交。测试源 HEAD 与日志哈希由 crctl 发布（sourceRevision / logSha256），本报告只消费不重算。

**机器区结果**：

| cmd | exit | 解读 |
|---|---|---|
| cmd-01 | 0 | handler 8 + service 13 = **21/21 PASS、0 FAIL、0 SKIP**（`-v` 逐条可见）；`TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs` 真库 **PASS**（B-CODE-01 回归在 canonical 引用日志中执行，B-CODE-02 的 cmd-01 面闭合）；上游既有失败 `TestLoadAgentSkills_*` 被 `-run` 前缀排除（CUSTOM.md 基线） |
| cmd-02 | 0 | **5/5 PASS、0 FAIL、0 SKIP**（收敛口径，真库）：governance `TestGateProjectionReusesBoundPromotionRun` + migrate `TestPromotionMigrationsUpDownRoundtrip` / `TestConcurrentIndexCleanupsMatchTheirMigrations` / `TestEveryConcurrentUpBuildHasCleanup` / `TestEveryConcurrentDownBuildHasCleanup`；7 项上游既有失败不在 `-run` 匹配面内（§9.2 归因） |
| cmd-03 | 0 | views vitest 全绿：427 files / 5040 tests passed |
| cmd-04 | 0 | core vitest 全绿：147 files / 1796 tests passed |
| cmd-05 | 0, **skipped=false** | dot reporter 输出仅点号、无 `skipped` 字样——B-CODE-03 根因消除，机器区 `skipped=false`（AC-13 tools 消费面 canonical 证据成立） |
| cmd-06 | 0 | lint-prompts enforce 0 findings |

**结论**：机器 `status=pass`（attempt 2），六条命令全部 exit=0；B-CODE-01/02/03 三类证据面全部闭合。

## TASK 验收覆盖矩阵

| TASK / AC 面 | 证据 | 结果 |
|---|---|---|
| TASK-01 数据层（AC-10 无新表、迁移往返、并发索引清理登记） | cmd-02 | PASS（4/4 迁移口径测试函数真库 PASS） |
| TASK-02 服务内核（AC-1/3/4/5/8、B-CODE-01 回归、错误矩阵零残留、FR-5 结构断言） | cmd-01 | PASS（service 13/13，含 `TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs` 真库 PASS） |
| TASK-03 HTTP/绑定（AC-2/6/11/13 端点面、context_refs 透出） | cmd-01 | PASS（handler 8/8，含 `TestBindPromotionRun*` 3 项与 AC-13 绑定矩阵） |
| TASK-03/02 AC-13 投影复用（绑定后复用同一 run 不新建） | cmd-02 | PASS（`TestGateProjectionReusesBoundPromotionRun`） |
| TASK-04 前端（AC-7/9/12 discussion-pane、Issue 详情来源入口、四语文案） | cmd-03 | PASS（views vitest 全绿） |
| TASK-04 client schema（AC-7 malformed-response/fallback） | cmd-04 | PASS（core vitest 全绿） |
| TASK-04 tools 消费面（AC-13 tools：定位/绑定/失败语义/普通注册不变） | cmd-05 | PASS（exit=0、`skipped=false`） |
| TASK-04 prompt 漂移防护 | cmd-06 | PASS（0 findings） |

关键 AC 唯一 owner 行与业务闭环行的证据面与 plan §7 矩阵逐行核对一致，无缺口、无空白通过。

## 新增/修改测试文件（本 CR，multica `5aadba5be`）

- 实施期已登记于 plan §6.1/§6.2 与 TASK 卡；本次重跑未改动任何测试文件（评审对象 `5aadba5be` 保持，cmd 日志的 sourceRevision 一致）。
- 本报告唯一实质变化为证据面：cmd-02 args 收敛（§9.2），命令表已冻结于 plan §6.2。

## 未覆盖风险（含「不适用」说明）

1. **7 项上游既有 DB 期失败（governance 5 + migrate 2）不在 cmd-02 收敛面内**——trunk `eafce66b` A/B 同症、本 CR 相对 trunk 对 4 个相关测试文件零 diff、根因指向 CR-2026-049 遗留测试缺陷（详见 plan §9.2）。它们不属于本 CR 任何 AC 验收面，排除依据已由 review-dev-plan cycle 2 / attempt 2 独立复核 PASS。按 §9.2 承诺，将在下次 multica 合法变更时登记 CUSTOM.md《已知测试失败基线》；该登记不影响本 CR 验收。
2. **3 项 `TestLoadAgentSkills_*` 上游既有失败被 cmd-01 `-run` 前缀排除**——同上，非 promotion 面，CUSTOM.md 已登记（2026-09-08 行）。
3. cmd-05 `skipped` 字段：dot reporter 输出不含 `skipped` 字样，冻结模式表不再误命中，机器区恒 false；不存在真实 skip。
4. `GOFLAGS=-v`/`DATABASE_URL`/pnpm shim 均为 plan §6.2 明示的会话环境变量，不属 commands 数组，不违反 cr-test-plan/v1 schema。
5. 无「不适用」项：§6.2 六条命令全部在本机会话环境实际执行并产出 exit code 与日志。

## 下一步建议

- 提交本报告与 canonical 账本（`test-report.md` / `traceability.yml#tests` / `review-loop.yml` / `test-evidence/cmd-01..06.log` / `_context.md`）→ `crctl checkpoint` 推送（multica/tools 零改动，评审对象保持）。
- 委派独立 `quality-reviewer-agent` 执行新 cycle `review-code`（cycle 2 / attempt 1，canonical `review-code` 当前 cycle 2 / attempt 0）。机器区 `status=pass` + `code.yml` verdict=pass 后停在 `code-reviewing` 人工审批 gate，由 Ray 在交互式终端执行 `crctl approve --stage code`；本报告不代签、不自行推进审批。
