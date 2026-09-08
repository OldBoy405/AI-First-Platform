---
cr: CR-2026-061
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-09T00:07:14+08:00"
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

## 测试摘要（cycle 2 / attempt 3，review-code B-CODE-04/05 回修后 canonical 重跑）

**目标（reviewLoop 回修链第 4 段）**：review-code cycle 2 / attempt 1 产出 BLOCK（B-CODE-04 前端附件选择缺失、B-CODE-05 绑定上下文无 fail-closed 校验，评审提交 `9680199`），implement-code 回修后本报告按 plan §6.2 冻结命令表重跑 `crctl test --plan` 生成 canonical 证据。预期与实得一致：机器 `status=pass`、六条命令 exit=0、`skipped` 全 false。command-digest `001d7209…` 与 attempt 2 相同——命令表（§6.2）本轮未变，变化只在各命令的测试源 HEAD 与日志内容。

**执行环境（透明披露）**：
- 计划 = plan.md §6.2 冻结命令表逐条转录至 `.crctl/tmp/test-plan.json`（cmd-NN 与覆盖矩阵「验收证据」列全等）；未在 plan 之外另造命令集。
- 会话环境：`DATABASE_URL` = 主克隆 `.env` dev 库（迁移 505–507 已应用）+ `GOFLAGS=-v`；`pnpm.exe` shim（Go 转发 wrapper）前置 PATH。plan §6.2 口径：cmd-01/02 在 DATABASE_URL 下真库实跑。
- 绑定版本：multica CR 分支回修提交 `f02660ae9`（B-CODE-04：discussion-pane 附件独立选择 + 测试 + CUSTOM.md #81 更新）、tools 回修提交 `bfd3747`（B-CODE-05：promotion-bind fail-closed issue/run 上下文校验 + 测试 + SKILL Step 2.5）；docs 本提交。测试源 HEAD 与日志哈希由 crctl 发布，本报告只消费不重算。

**机器区结果**：

| cmd | exit | 解读 |
|---|---|---|
| cmd-01 | 0 | handler 8 + service 13 = **21/21 PASS、0 FAIL、0 SKIP**（`-v` 逐条可见）；`TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs` 真库 **PASS**（B-CODE-01 回归继续成立）；本轮回修不改 Go 面（B-CODE-04/05 均非服务端 diff） |
| cmd-02 | 0 | **5/5 PASS、0 FAIL、0 SKIP**（§9.2 收敛口径，真库）；7 项上游既有失败不在 `-run` 匹配面内 |
| cmd-03 | 0 | views vitest 全绿：**427 files / 5043 tests passed**（较 attempt 2 的 5040 增 3 项 = discussion-pane 新增 B-CODE-04 附件臂用例：attachment-only、mixed、失败保留重试） |
| cmd-04 | 0 | core vitest 全绿：147 files / 1796 tests passed |
| cmd-05 | 0, **skipped=false** | dot reporter 输出 16 点全过、无 `skipped` 字样；新增 B-CODE-05 错配用例（①c run_id 错配 / ①d issue_id 错配 / ①e 缺 issue_id / ①f 缺位置参数）与既有幂等/失败/普通注册用例全绿 |
| cmd-06 | 0 | lint-prompts enforce 0 findings（SKILL Step 2.5 新增 `BIND_RESPONSE_MISMATCH` 口径无 CONTRADICTS/STALE-REF） |

**结论**：机器 `status=pass`（attempt 3），六条命令全部 exit=0、`skipped=false`；B-CODE-01/02/03 证据面持续闭合，B-CODE-04/05 回修的测试面进入 canonical 证据（cmd-03/cmd-05 日志）。

## TASK 验收覆盖矩阵

| TASK / AC 面 | 证据 | 结果 |
|---|---|---|
| TASK-01 数据层（AC-10 无新表、迁移往返、并发索引清理登记） | cmd-02 | PASS（4/4 迁移口径测试函数真库 PASS） |
| TASK-02 服务内核（AC-1/3/4/5/8、B-CODE-01 回归、错误矩阵零残留、FR-5 结构断言） | cmd-01 | PASS（service 13/13，含 `TestPromoteDiscussionBackfillPreservesHeterogeneousContextRefs` 真库 PASS） |
| TASK-03 HTTP/绑定（AC-2/6/11/13 端点面、context_refs 透出） | cmd-01 | PASS（handler 8/8，含 `TestBindPromotionRun*` 3 项与 AC-13 绑定矩阵） |
| TASK-03/02 AC-13 投影复用（绑定后复用同一 run 不新建） | cmd-02 | PASS（`TestGateProjectionReusesBoundPromotionRun`） |
| TASK-04 前端（AC-9 discussion-pane 消息/附件独立多选、message-only / attachment-only / mixed 三形态、失败保留；AC-7/12 来源入口与四语文案） | cmd-03 | PASS（views vitest 全绿，discussion-pane 14/14 含 3 项新附件臂用例） |
| TASK-04 client schema（AC-7 malformed-response/fallback） | cmd-04 | PASS（core vitest 全绿） |
| TASK-04 tools 消费面（AC-13 tools：定位/绑定/响应上下文 fail-closed 校验/失败语义/普通注册不变） | cmd-05 | PASS（exit=0、`skipped=false`，16 用例全过） |
| TASK-04 prompt 漂移防护 | cmd-06 | PASS（0 findings） |

关键 AC 唯一 owner 行与业务闭环行的证据面与 plan §7 矩阵逐行核对一致，无缺口、无空白通过。

## 新增/修改测试文件（本轮回修，B-CODE-04/05）

- multica `f02660ae9`：`packages/views/projects/components/discussion-pane.test.tsx`（+3 用例：attachment-only 升级、mixed 升级、附件选择失败保留+重试；`Attachment` 夹具 + comment-card `AttachmentList` 轻量 stub）；`discussion-pane.tsx`（`selectedAttachments` 独立选择态、`discussion-attachment-selector` 勾选控件、`attachment_ids` 消费）；`CUSTOM.md` #81 更新。
- tools `bfd3747`：`skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs`（+4 用例：run_id 错配 / issue_id 错配 / 缺 issue_id / 缺位置参数；既有 ①①②③④ 断言同步 issue_id）；`promotion-bind.mjs`（第三位置参数 `issue_id` + `BIND_RESPONSE_MISMATCH` fail-closed 校验）；SKILL Step 2.5/错误处理表同步。
- 前次（attempt 2）报告所述实施期测试文件全部保留（评审对象 docs `755dca2` 之前登记）。

## 未覆盖风险（含「不适用」说明）

1. **7 项上游既有 DB 期失败（governance 5 + migrate 2）不在 cmd-02 收敛面内**——trunk A/B 同症、本 CR 对 4 个相关测试文件零 diff、根因指向 CR-2026-049 遗留测试缺陷（plan §9.2）；排除依据已由 review-dev-plan cycle 2 / attempt 2 独立复核 PASS。按 §9.2 承诺在下次 multica 合法变更时登记 CUSTOM.md 基线。
2. **3 项 `TestLoadAgentSkills_*` 上游既有失败被 cmd-01 `-run` 前缀排除**——非 promotion 面，CUSTOM.md 已登记（2026-09-08 行）。
3. cmd-05 `skipped` 字段：dot reporter 输出不含 `skipped` 字样，机器区恒 false；不存在真实 skip。
4. 本轮回修仅触及前端与 tools 消费面，未改任何 Go 服务端文件（cmd-01/02 测试源相对评审版本变化为零、21/21 与 5/5 口径不变）。
5. 无「不适用」项：§6.2 六条命令全部在本机会话环境实际执行并产出 exit code 与日志。

## 下一步建议

- 提交本报告与 canonical 账本（`test-report.md` / `traceability.yml#tests` / `review-loop.yml` / `test-evidence/cmd-01..06.log` / `_context.md`）→ `crctl checkpoint` 推送（multica/tools 回修提交已各自落盘，本轮随批次一并确认）。
- 委派独立 `quality-reviewer-agent` 执行 `review-code`（cycle 2 / attempt 2，review-record 带 `--bump-attempt`）；评审对象 multica `f02660ae9`、tools `bfd3747`。机器区 `status=pass` + `code.yml` verdict=pass 后停在 `code-reviewing` 人工审批 gate，由 Ray 在交互式终端执行 `crctl approve --stage code`；本报告不代签、不自行推进审批。
