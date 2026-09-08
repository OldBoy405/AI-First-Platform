---
cr: CR-2026-061
status: block
tester: Ray
generated-by: crctl-test
generated-at: "2026-09-08T17:22:33+08:00"
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
## 测试摘要

TASK-01～TASK-04 全部 `done`（`crctl task done` 记账，`tasks/_index.yml` 四行 done），
developing 内完成标志逐项满足。`crctl test` 机器区 6 条证据命令全量执行：

- **cmd-01**（go test ./internal/handler/ ./internal/service/）exit=1：仅 3 项**上游既有 fixture 陈旧**测试失败（`TestLoadAgentSkills_*`），与 CR 改动无关（A/B 证据见 §3）。
- **cmd-02**（go test ./internal/governance/ ./cmd/migrate/）exit=0 ✓
- **cmd-03**（pnpm test packages/views）exit=0 ✓（427 文件 / 5040 测试）
- **cmd-04**（pnpm test packages/core）exit=0 ✓（147 文件 / 1796 测试）
- **cmd-05**（node --test promotion-bind.test.mjs）exit=0，12/12 断言全过；机器区 `skipped=true` 是冻结模式表误命中（`ℹ skipped 0` 摘要行命中 `\bSKIPPED\b`），非真实 skip，证据见 §3.3。
- **cmd-06**（lint-prompts --mode enforce）exit=0 ✓（0 findings）

机器区 `status=block` 的唯一来源是 cmd-01 的 3 项上游既有失败（详见 §3.1），
**本 CR 全部自有测试面（cmd-02/03/04/05/06 + 真库 promotion 专项）全绿**。

## 验证命令与结果解读

| 命令 | 结果 | 解读 |
|---|---|---|
| cmd-01 | exit=1 | handler 包全绿；service 包仅 3 项 `TestLoadAgentSkills_*` 失败：`scan: 13 destinations for 10 columns`——`skill` 表现为 13 列（CR-2026-048 visibility/version/owner_actor 与上游演进），`task_agent_skills_test.go` 的 `skillRow` 夹具仍造 10 列。未改动 trunk `eafce66b`（main clone，worktree clean）同命令 A/B 失败名单逐条一致；本 CR 零 diff 该文件。已登记 CUSTOM.md《已知测试失败基线》。 |
| cmd-02 | exit=0 | governance + migrate 全绿（含 505/506/507 登记断言 `TestEveryConcurrentUpBuildHasCleanup`/`TestConcurrentIndexCleanupsMatchTheirMigrations`）。 |
| cmd-03 | exit=0 | discussion-pane 多选/两入口/成功链接/失败保留选择（AC-9）、issue-detail 来源入口（AC-7 前端面）、locales parity（AC-12）全绿。 |
| cmd-04 | exit=0 | client.promotion.test.ts（Idempotency-Key 强制 + 请求形状 + malformed fallback）与 schemas.promotion.test.ts（PromotionResultSchema/IssueSchema.context_refs 旧后端回退）全绿。 |
| cmd-05 | exit=0（机器区 skipped=true，误命中） | 12/12 断言全过：① 绑定命令参数 `{cr_id} --run-id {run_id}`；①b 幂等重放 changed=false；② 404/409/401/500 六码技术失败停止 + registration_key 重试指引；②b multica 缺失 MULTICA_UNAVAILABLE；③ 无 promotion 上下文按普通注册；④ SKILL.md 硬不变量。 |
| cmd-06 | exit=0 | lint-prompts 0 findings（SKILL.md 新增内容无 crctl 命令面漂移）。 |

**真库专项证据（DATABASE_URL 置位，非 plan 命令面，补充证据）**：

```text
cd server && DATABASE_URL=… go test ./cmd/migrate/ -run TestPromotionMigrationsUpDownRoundtrip -v -count=1   → PASS（505/506/507 up/down 往返）
cd server && DATABASE_URL=… go test ./internal/governance/ -run TestGateProjectionReusesBoundPromotionRun -v -count=1 → PASS（绑定后投影按 cr_id 复用同一行）
cd server && DATABASE_URL=… go test ./internal/service/ -run 'TestPromoteDiscussion|TestCreateInTxPromotionRunFailureZeroResidue|TestPromotionSourcesNeverWriteChatTables' -v -count=1 → 5/5 PASS（创建+重放 created=false/查重补建/非成员零写/run 失败零残留/chat_* 零写）
cd server && DATABASE_URL=… go test ./internal/handler/ -run 'TestPromoteProjectDiscussion|TestBindPromotionRun' -v -count=1 → 6/6 PASS（201+run_id/错误矩阵/非成员 403/绑定幂等/双冲突/非 promotion 形状 404）
```

> 开发期真库验证曾暴露两处实现缺陷并已修复（red→green）：① `InsertPipelineRun` 未写预生成 `id` 导致首节点 FK 23503（补 `@id` 参数 + sqlc 重生）；② 幂等重放未强制 `created=false`（PRD FR-7，存储体保留首次 `created=true`）。另有测试夹具修复：promotion handler fixture 的 `agent_id` 传空串改 `NULL`；零残留断言按 fixture project 收窄（表级计数会被其它测试污染）。修复 commit `50898d205`（`[cr] CR-2026-061 fix: …`）。

## TASK 验收覆盖矩阵

| TASK | 验收条件 | 证据 |
|---|---|---|
| TASK-01 数据层 | 迁移 505/506/507 + promotion.sql 10 查询 + migrate 登记；505 CHECK 三值、506 部分唯一、507 GIN | cmd-02（登记断言）+ 真库 `TestPromotionMigrationsUpDownRoundtrip` PASS；`TestEveryConcurrentUpBuildHasCleanup`/`DownBuild` PASS |
| TASK-02 服务内核 | createInTx 唯一写入路径；指纹/查重/幂等四分支；默认标题描述；预建 run；零残留 | cmd-01（service 包除 3 项基线外全绿，含 `TestPromotionDigestsFixedVectors` 等纯函数组）+ 真库 `TestPromoteDiscussionCreateAndReplay`/`DedupeHitAndUpgradeBackfill`/`ForbiddenAndZeroWrites`/`CreateInTxPromotionRunFailureZeroResidue`/`PromotionSourcesNeverWriteChatTables` 全 PASS |
| TASK-03 HTTP/绑定/CLI | promotion 端点错误闭包；context_refs 暴露；bind 端点 task-token/幂等/409；CLI；投影复用同一行 | cmd-01（handler 包全绿）+ 真库 `TestPromoteProjectDiscussion*`/`TestBindPromotionRun*` 6/6 PASS + governance 投影 PASS |
| TASK-04 前端+tools | cmd-03/04/05/06 先行跑通 + typecheck | cmd-03（5040）/cmd-04（1796）/cmd-05（12/12，skipped 为误命中）/cmd-06（0 findings）；core+views `pnpm typecheck` 零报错 ✓ |

## 新增/修改测试文件

multica：`server/cmd/migrate/migrate_promotion_test.go`（新，TASK-01）、`server/internal/service/promotion_test.go`（新，TASK-02）、`server/internal/handler/promotion_test.go`（新，TASK-03）、`server/cmd/multica/cmd_cr_test.go`（新，TASK-03）、`server/internal/governance/promotion_projection_test.go`（新，TASK-03）、`packages/core/api/client.promotion.test.ts`+`schemas.promotion.test.ts`（新，TASK-04）、`packages/views/projects/components/discussion-pane.test.tsx`（+2 用例 + NavigationProvider 夹具）、`packages/views/issues/components/issue-detail.test.tsx`（+2 用例）。
tools：`skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs`（新，12 断言）。

## 未覆盖风险

1. **cmd-01 机器区失败（block 唯一来源）**：3 项 `TestLoadAgentSkills_*` 为上游 fixture 陈旧（skill 表 13 列 vs 夹具 10 列），trunk `eafce66b` A/B 复现一致，本 CR 零 diff 相关文件；已登记 CUSTOM.md 基线（2026-09-08 行）。**自修复在批准范围外**（改上游测试文件属 scope_out，CR-2026-057 FR-7 禁止），需人工裁定处置口径（CR-2026-059 先例：A/B 证据 + 人工核定不计入回归）。
2. **cmd-05 机器区 `skipped=true` 为冻结模式表误命中**：node 24 spec reporter 恒打印 `ℹ skipped 0` 摘要行，命中 `/\bSKIPPED\b/i`。cmd-05.log 实测 12/12 pass、fail=0、无真实 skip；另以 `--test-reporter=dot` 复核（12 点全过，exit 0）。根治建议：plan §6.2 cmd-05 args 追加 `--test-reporter=dot`（写回 plan 需经 review-dev-plan 合法修订，plan 现为已审批冻结态，本 CR 未擅自改动）。
3. **DB 依赖测试面**：plan 的 cmd-01/02 未置 `DATABASE_URL`，handler/governance/migrate 的 DB 测试整体 SKIP（C6 口径）。本报告已用 dev 库 DATABASE_URL 补跑 promotion 专项全绿（见上）；dev 库曾因 `schema_migrations` 旧号登记导致 `migrate up` 撞 451，已按 CUSTOM.md 第 3 条一次性修复（快照 `schema_migrations_bak_cr2026061`，54 行 +14），随后应用 505–507（已记入 CUSTOM.md）。
4. **环境 shim**：crctl 以 `spawnSync(shell:false)` 执行命令，npm-global 的 `pnpm` 是 .cmd shim 无法被解析，本次在 PATH 前置 go 编译的本地 `pnpm.exe` 转发 shim（C:\temp\pnpm-shim，非仓库产物）使 cmd-03/04 可执行；同机复现照此处理。
5. **组合运行顺序缺陷（与 CR 无关）**：`DATABASE_URL` 置位且组合运行时 `internal/handler` 的 4 项 deferred-fallback 测试互踩夹具失败，单独运行各自全绿；CR worktree 与 trunk 表现一致（已登记 CUSTOM.md 基线）。

## 下一步建议

按 write-test-report 契约，机器区 `status=block` 时 pipeline 应把失败命令回传 implement-code 自修复；
但本 block 的 3 项失败经 A/B 证明为上游既有、修复超出批准范围，自修复不可行也不合规。
处置选项二选一（请 cr-coordinator-agent / Ray 裁定）：
1. 按 CR-2026-059 先例人工核定（A/B 证据 + CUSTOM.md 基线已登记），随后进入独立 review-code；
2. 以 review-dev-plan 修订 plan §6.2（cmd-01 收窄面排除已知失败 / cmd-05 加 `--test-reporter=dot`），修订后重跑 `crctl test` 取 pass。
在裁定前不推进 `code-reviewing`、不消耗 review-code attempt。
