---
cr: CR-2026-048
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-20T18:18:47+08:00"
command-digest: f3a447fae06df36869ce9c94ca5bb4bec3c781b1e16f235d4039684ff59c85b7
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
    args: [test, ./pkg/redact/, "-count=1", -run, "TestFindings|TestPatternsSingleNamedTable|TestTextKeepsMaskedHomeDirAndFindingsHandleCRLF"]
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
    args: [test, ./internal/handler/, "-count=1", -run, "TestUpdateSkill|TestAppeal|TestDecideSkillAppeal|TestGetSkillMarket|TestSkillMarketQueriesUseNewIndexes|TestClaimTaskByRuntimeWritesSkillUsageTelemetry"]
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
    cwd: server
    executable: go
    args: [vet, ./internal/handler/, ./internal/skill/, ./pkg/redact/, ./pkg/db/generated/, ./cmd/migrate/]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-06.log
  - repo: multica
    cwd: packages/views
    executable: node
    args: [../../node_modules/eslint/bin/eslint.js, skills/]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-07.log
  - repo: multica
    cwd: packages/core
    executable: node
    args: [../../node_modules/eslint/bin/eslint.js, api/client.ts, types/agent.ts, types/index.ts]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-08.log
  - repo: multica
    cwd: .
    executable: node
    args: [node_modules/typescript/bin/tsc, --noEmit, -p, packages/core/tsconfig.json]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-09.log
  - repo: multica
    cwd: .
    executable: node
    args: [node_modules/typescript/bin/tsc, --noEmit, -p, packages/views/tsconfig.json]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-10.log
  - repo: multica
    cwd: .
    executable: node
    args: ["--input-type=module", -e, "import assert from 'node:assert/strict'; import fs from 'node:fs'; const locales=['en','ja','ko','zh-Hans']; const keys=locales.map(l=>Object.keys(JSON.parse(fs.readFileSync(`packages/views/locales/${l}/skills.json`,'utf8')).market).sort().join(',')); assert.equal(new Set(keys).size,1,'market locale key sets diverge'); assert.ok(keys[0].includes('applicable_scenarios')&&keys[0].includes('load_failed')&&!keys[0].includes('session_export_hint'),'market keys stale'); const {parseRequirements}=await import('./packages/views/skills/lib/skill-metadata.ts'); assert.deepEqual(parseRequirements('[\"git\",\"node\"]'),['git','node']); assert.deepEqual(parseRequirements('git, node'),['git','node']); assert.deepEqual(parseRequirements(undefined),[]); assert.deepEqual(parseRequirements('[broken'),['[broken']); console.log('locale parity + parseRequirements ok');"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-048/test-evidence/cmd-11.log
---

# 测试报告 · CR-2026-048

<!-- crctl:analysis-below -->
## 测试摘要

11 条验证命令全部 exit 0（详见上方机器区与 `test-evidence/cmd-*.log`）。本轮为代码评审 attempt 1 的回修复测（8 条 blocker），相比上一轮新增：`go vet` 静态检查（cmd-06）、eslint（cmd-07 views/skills、cmd-08 core，修掉 market-page.tsx 两处 `i18next/no-literal-string` 报错）、locale 键一致性 + `parseRequirements` 断言（cmd-11），并把三条新增回归用例并入 cmd-04。执行环境：Windows + Go 1.26.4 + 真实 PostgreSQL（`postgres://multica:multica@localhost:5432/multica`，迁移 380–384 已应用）。

## 本轮回修与证据（对 review-annotations/code.yml attempt 1）

| Blocker | 修复 | 证据 |
|---|---|---|
| 1. AC-12/FR-20/FR-21 详情页四字段卡与运行时标签缺失 | `SkillResponse.metadata` 返回服务端解析的 frontmatter；`SkillMetadataCard`（skill-market-card.tsx）渲染四字段 + 运行时标签，标签解析抽到 `skills/lib/skill-metadata.ts` | cmd-09/10 typecheck；cmd-11 `parseRequirements` 四组断言（JSON 序列/标量列表/缺失/不可解析均不报错）；`skill-metadata.test.ts`（vitest，见下未运行说明） |
| 2. AC-13/FR-23 session-export 开关不过滤 | market 查询取 `content` 解析 `source` 并随 `MarketSkill.source` 返回；前端按 `source === "session-export"` 真过滤（builtin 无 frontmatter，筛选下清空），删除占位提示文案 | cmd-09/10；cmd-11 断言 `session_export_hint` 已从 4 份 locale 移除、新键齐全 |
| 3. AC-14 EXPLAIN 断言缺失 | 新增 `TestSkillMarketQueriesUseNewIndexes`：固定 fixture + `SET LOCAL enable_seqscan = off` + `EXPLAIN (FORMAT JSON)`，逐条断言排行走 `skill_usage_event_scope_idx`、完成过滤走 `skill_usage_event_task_id_idx`、申诉查找走 `skill_appeal_activity_idx` | cmd-04（真库，三个子用例全过） |
| 4. 申诉放行不可撤销 | `GetAppealDecision` 改为取该 appeal_id 最近一条 `approved`/`rejected` 决定，调用方判 action | cmd-04 `TestDecideSkillAppealRejectionRevokesEarlierApproval`（放行后发布 200 → 驳回后发布 422） |
| 5. 触发条件 2 下申诉 id 与门禁 id 不一致 | `SubmitSkillAppeal` 改为直接记账门禁下发的 `appeal_id`（不再用库内旧内容重算哈希），删除 `appealContentHash` | cmd-04 `TestAppealReleasesRescanFindingOnUnsavedContent`（未落库内容的误报可申诉、账本行 appeal_id 与门禁一致、放行后重发 200）。**评审结论修订**：原 blocker 描述为“死锁”，复核后实际影响是**账本断链**（decide 端点本就接受客户端传入的 appeal_id，因此放行仍能生效，但提交记录与决定记录 id 不同，`HasAppealSubmitted` 幂等失效、审计无法关联）；缺陷与修复不变，严重度修订记录于此。 |
| 6. lint 证据缺失 | 测试计划新增 `go vet`（cmd-06）与 eslint（cmd-07/08）；eslint 首跑暴露 market-page.tsx 两处 `i18next/no-literal-string`（`v{version}` 字面量、builtin 徽章硬编码文案），已修 | cmd-06/07/08 exit 0 |
| 7. 前端 vitest 免测理由 | 用 CR-2026-047 同款调用重跑并把失败原样落盘；补隔离探针证明是 Node 24 + pnpm 的 `#module-evaluator` 解析失败（vitest 自身 package.json 已声明该 specifier、目标文件存在），非本 CR 代码问题 | `test-evidence/vitest-startup-failure.log` |
| 8. 迁移 381 缺 COMMENT ON | 381 up 增加 `COMMENT ON TABLE skill_usage_event`（“派发时物化”语义） | sqlc 以真实 PG 解析器读取该注释并写入 `models.go`（见 diff）；见下“未覆盖”对本地库的说明 |

## TASK 验收覆盖矩阵

| TASK | 验收 | 证据 |
|---|---|---|
| TASK-01 迁移 | AC-1/AC-14/AC-15 | cmd-03（`TestEveryConcurrentUpBuildHasCleanup` 归零）；真实 PG 上 `migrate up` 成功、`down` 中 384→380 全部回滚成功（373 拦截为上游存量问题）；**AC-14 的 EXPLAIN 半边由 cmd-04 `TestSkillMarketQueriesUseNewIndexes` 覆盖**；无 FK 断言在迁移 SQL 内由仓规约保证 |
| TASK-02 redact | AC-10 | cmd-02：`TestPatternsSingleNamedTable`（16 条、name 唯一非空）+ `TestFindingsLocatesSecretsWithoutLeakingPlaintext` + 新增 `TestTextKeepsMaskedHomeDirAndFindingsHandleCRLF`（掩码后的 home 路径不被 personal_path 二次改写；CRLF 输入的 excerpt 不带尾随 CR） |
| TASK-03 frontmatter | AC-7/AC-13 | cmd-01：`TestParseSkillMetadataExtractsCardFields`/`ToleratesBadInput`/`ParseSkillFrontmatterStillCompatible` |
| TASK-04 门禁 | AC-2/AC-9 的纯函数半边 | cmd-01：`TestEvaluatePublish*` 五条（含 `Release` 逐条放行与内容变更失效）+ `TestAppealIDIsDeterministicAndContentSensitive` |
| TASK-05 sqlc | AC-5/AC-11/AC-14 | cmd-05/06；`make sqlc` 生成物只含预期文件（models.go/skill.sql.go/skill_market.sql.go/workspace_delete.sql.go） |
| TASK-06 遥测 | AC-3/AC-4 | cmd-04：`TestClaimTaskByRuntimeWritesSkillUsageTelemetry`（真库：claim 写行、workspace 隔离、builtin ref）；`TaskCompleteRequest` 零改动以 diff 为证 |
| TASK-07 发布/申诉 | AC-2/AC-6/AC-7/AC-8/AC-9/AC-10/AC-11 | cmd-04：发布拦截 422 不部分更新、干净发布成功、org 内容更新重扫、申诉 403/幂等/放行后重发通过、驳回撤销放行、未落库内容的申诉链路、runtime-local 覆盖导入门禁 |
| TASK-08 market | AC-3/AC-5 | cmd-04：`TestGetSkillMarketScopesAndDedupes`（org 过滤、completed 去重、失败任务不计、builtin 上榜） |
| TASK-09 前端 | AC-12/AC-13 | cmd-09/10 typecheck 全过；cmd-11 locale 键一致性 + 运行时标签解析断言；四字段卡/`source` 筛选的组件级断言写在 `skill-metadata.test.ts`/既有 vitest 套件，本机未能启动 vitest（见下） |
| TASK-10 收口 | AC-16/AC-4 | CUSTOM.md 第 48 行台账已按本轮新增文件（`internal/handler/skill_publish.go`、`packages/views/skills/lib/skill-metadata.ts`）与放行撤销语义更新；验证命令补 `go vet` |

## 未覆盖与已知基线

- **前端 vitest 未运行**：`node node_modules/vitest/vitest.mjs run skills` 启动即 `ERR_PACKAGE_IMPORT_NOT_DEFINED: #module-evaluator`（Node v24.15.0 + vitest 4.1.0 + pnpm 目录布局），失败输出与隔离探针见 `test-evidence/vitest-startup-failure.log`。降级手段：cmd-09/10 typecheck 覆盖类型面，cmd-11 以 `node --input-type=module` 直跑纯函数与 locale 断言覆盖逻辑面；`skill-metadata.test.ts` 已按仓内 vitest 风格入库，CI 环境可直接执行。组件渲染（四字段卡、findings 面板）仍只有人工核对。
- **迁移 381 的 COMMENT ON 未在本地库重放**：全量 `migrate down` 会在既有 373 CHECK 冲突处中断（上游存量问题，与本 CR 无关），故未重跑整链 down/up；该语句已由 sqlc 的 PG 解析器读入并生成 `models.go` 表注释，全新环境首次 `migrate up` 即生效。
- **全量测试基线（既有，非本 CR 引入）**：`pkg/redact` 的 `TestRedactHomeDirectory`（本机域前缀用户名 `DESKTOP-OT18TRG\GOBAO` 使 homeDir 掩码失效，stash 回退后同样失败）、`cmd/multica`/`internal/cli`/`internal/daemon` 等 Windows 环境假设失败、`internal/handler` 的 `TestWorkspaceDeletionManifestCoversPublicSchema`（7 张先前 CR 的表未入 manifest 的既有漂移）、`internal/service` 的 builtin_skills CRLF 断言失败——全部与 CUSTOM.md「已知测试失败基线」表一致。
- **观察项**：claim 遥测的插入失败非阻断路径没有注入式测试（代码路径为 slog.Error + continue，不改变 claim 结果）；`personal_path` 进入共享 `patterns` 表意味着 `Text()` 全局生效（SDD §4.4 已批准），新增的掩码兼容断言只覆盖 home 目录一种交互。
