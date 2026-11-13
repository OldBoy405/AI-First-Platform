# S4 整包基线：失败与 skip 的逐项归属

change：`2026-11-12-fork-ci-test-evidence-trust` ｜ 切片 4 ｜ 记录时间 2026-11-12

本文件是归属表 `multica/scripts/aifi45-disposable/test-ownership.json` 的**证据依据**。
纪律：只有带证据的项才可进入 CI 排除或 skip 允许名单；无证据一律不排除、不声明。

## 1. 基线运行事实

- 环境：Windows 10（本机），Go 整包运行，数据库为 runner 自建的一次性 podman Postgres 实例。
- 入口：`run-selection.mjs --selections selections.baseline.json --evidence-dir <本目录>/events`，
  5 个 selection 各用一个独立数据库（provision → `cmd/migrate up` → 一次 `go test -json` → marker 校验后 drop）。
- 容器纪律：运行前后 `podman ps -a` 清单逐字节相同（`podman-before.txt` / `podman-after.txt`，
  去表头后 diff 为空）；`multica-postgres`、`multica-backend` 全程 Exited，卷 `multica-pgdata` 未触碰；
  结束时 `released instance 48d027ce582a remaining=0`。未连接 localhost:5432，未放宽 nonce 门禁。
- 原始流与逐 selection 结论：`events/*.ndjson`、`events/*.json`；分类明细 `events/classification.txt`。

| selection | package | pass | fail | skip |
|---|---|---|---|---|
| baseline-governance | ./internal/governance | 1328 | 48 | 1 |
| baseline-crosslang | ./internal/governance/crosslang_test | 19 | 0 | 0 |
| baseline-cmd-server | ./cmd/server | 659 | 0 | 0 |
| baseline-handler | ./internal/handler | 4507 | 3 | 47 |
| baseline-daemon | ./internal/daemon | 2132 | 24 | 87 |
| **合计** | | **8645** | **75** | **135** |

runner 退出码 1（有失败）。**这不是 CI 环境**：CI 为 ubuntu-latest 且带 Redis（`REDIS_TEST_URL`），
无 `AIFI45_TOOLS_ROOT` / `CRCTL_MJS` / `MULTICA_CONTROLLED_SHELL_RULES`。
因此凡属 Windows-only 或"Redis 缺失"的失败与 skip，都**不得**转化为 CI 排除。

## 2. 失败分类（29 个顶层测试 / 75 个失败帧）

### A 类：状态敏感迁移探针（governance，3 个顶层 / 48 帧）→ 排除，独立入口已验证

| 测试 | 基线证据 | 独立入口结果 |
|---|---|---|
| `TestChannelMigrationAfterUp` | 14 个子测试中 12 个失败：`execution_control_migration_test.go:513: table cr_execution_* starts with N rows; the migration creates structure only` | PASS pass=19 fail=0 skip=0 |
| `TestChannelMigrationAfterDown` | 20 个子测试失败，逐个列出仍然存在的 648 对象（表/主键/索引/触发器） | PASS pass=22 fail=0 skip=0 |
| `TestChannelMigrationAfterReapply` | 12 个子测试失败：`execution_control_migration_test.go:553` 同型"starts with N rows" | PASS pass=15 fail=0 skip=0 |

三者都断言**起始 schema 状态**，整包共用一个数据库时前序测试已写入行，必然失败。
独立入口证据：`independent-entries.txt`（同样前后清单一致、`remaining=0`）。

**超出原设计的新发现**：设计只列了 AfterDown / AfterReapply 两项；`AfterUp` 同样状态敏感
（:513 断言空表），故归属表为 **4 条**而非 3 条。已记入 `pending-adjustments.yaml`。

### B 类：Windows 时钟粒度导致的唯一键冲突（handler，2 个）→ 不排除

- `TestPresenterMemberRemovalLinkage`：`project_presenter_test.go:450: create member user: ERROR: duplicate key value violates unique constraint "user_email_key" (SQLSTATE 23505)`
- `TestSearchIndexChangesScopeToWorkspace`：`search_index_test.go:204: setup: insert into workspace: ... "workspace_slug_key" (SQLSTATE 23505)`

两者的 fixture 用 `time.Now().UnixNano()` 生成"唯一"后缀。本机探针实测：
200000 次连续取值中 **199996 次与前一次完全相同**（Windows 时钟粒度约 100ns~15ms，远粗于纳秒）。
证据与探针源码见 `windows-clock-granularity.md`。

结论：这是**本机平台缺陷，不是常量 id 缺陷**（区别于 EXP-2026-0001）。Linux 上 `UnixNano` 单调递增，
两项预期通过，**不得进入 CI 排除**。本 change 不修改这两个上游测试（超出范围）。

### C 类：本 change 要修的真实缺口（handler，1 个）→ S8 的 RED

- `TestWorkspaceDeletionManifestCoversPublicSchema`：
  `workspace_delete_manifest_test.go:209: workspace deletion manifest drift: unclassified=[cr_execution_activation cr_execution_binding_issue cr_execution_code_source_freeze cr_execution_consumption cr_execution_contract_selection cr_execution_control_command cr_execution_control_fact ...]`
  共 **19 张 `cr_execution_*` 表未分类**。这正是 S8（retain 分类）与 S9（删除实现）的目标，
  基线失败即其 RED 证据，不属于"排除"。

### D 类：跨仓 tools 契约缺口（daemon，6 个）→ 上报，不排除

`TestProposedSnapshotReadShapes`、`TestM26B2TestFactsPayload`、`TestM26B2TestFactsPreserveFailures`、
`TestM26B4ScanEmitsIndependentTestEvent`、`TestM26B4ScanTestOnlyAndReviewOnly`、`TestM26B4CollectorKeepsBothReviewStages`

首个失败信息最直接：
```
crevents_test.go:1004: the snapshot needs 1111...4444:change-requests/CR-2026-002/test-report.md allowed:
FORBIDDEN_SUBCOMMAND: git show: argument shape not allowed by the whitelist
```
其余 5 个是同一根因的下游表现（`stages=map[code:1]`，test 阶段事件缺失）。

根因：这些测试要求 `git show` 放行 `test-report.md`、`trace.tests*`、`--name-only --format=` 三类形状
（AIFI-56 R1），而 pin 住的 tools `skills/shared/controlled-shell/rules.json` 的 `show` 白名单只授予
`review-annotations/*.yml`、`_backlog.yml`、`_history.yml`、`cr.md`。
本机因环境变量 `MULTICA_CONTROLLED_SHELL_RULES` 指向真实 rules.json 而暴露；
`crevents_test.go` 在该变量缺失时回落到**内联 fixture**（其中已含这些形状），所以 CI 目前被掩盖而通过。

**CI 影响（须用户裁定）**：S13 若把 `MULTICA_CONTROLLED_SHELL_RULES` 指向 pin 的 tools rules.json，
这 6 项会在 CI-linux 上真实失败。修法在 tools 仓（放宽 `show` 形状），不在 multica；
本 change 不静默改 tools 白名单、也不把这 6 项排除掉。

### E 类：Windows-only（daemon，16 个）→ 不排除

逐项证据（均来自 `events/baseline-daemon.ndjson` 原始输出）：

| # | 测试 | 观测信息 | 平台根因 |
|---|---|---|---|
| 1-3 | `TestLoadConfig_UsesCodexDesktopAppBundleFallback` / `TestLoadConfig_UsesChatGPTAppBundleCodexPath` / `TestLoadConfig_CodexDesktopFallbackDoesNotOverrideExplicitPath` | `config_test.go:1382/1427/1620: LoadConfig: no agent CLI found: install claude, ...` | fixture 写 `#!/bin/sh` 且无扩展名（`config_test.go:1357` 起），Windows 下不可执行 |
| 4 | `TestRefreshHealedVersion_KeepsHealedPairCurrentAfterInPlaceUpgrade` | `agent_path_selfheal_test.go:347: baseline version = "codex-cli 0.163.0", want 1.0.0` | `writeExecStub`（:41）同为 `#!/bin/sh` 无扩展名；版本探测落到本机真实 codex |
| 5-9 | `TestRunTaskReusesPriorWorkdirForFreshSession` / `TestRunTaskSquadLeaderReusesWorkdirBeforeGCMetaWritten` / `TestRunTaskSquadLeaderDoesNotReuseExternalPriorWorkdir` / `TestRunTaskCancelledWaitingForThePriorWorkdirStopsInsteadOfPreparing` / `TestRunTaskDeclinesReuseWhenTheClaimedDirectoryIsSwappedBeforeUse` | `claude executable not found at "C:\...\claude"` | `newLeaderReuseTestDaemon` 用 `writeTestExecutable` 写 `#!/bin/sh` 脚本为 `claude`（:361 起） |
| 10-12 | `TestListRuntimeLocalSkills_ClaudeEnabledPlugin` / `TestListRuntimeLocalMcpServersClaudeEnabledPlugin` / `TestMergeRuntimeAndAgentMcpConfigClaudeCombinesAndAgentWins` | `supported=true skills=[]` / `servers=[]` / merged 缺 plugin 项 | `writeTestClaudePlugin`（`local_skills_test.go:46`）把 Windows 路径**未转义**拼进 JSON 字符串；实测 `JSON.parse` 报 `Bad control character in string literal`；`claude_plugins.go:53` 吞掉 unmarshal 错误返回 nil |
| 13 | `TestListRuntimeLocalSkills_CodexUsesSharedCODEXHOME` | `local_skills_test.go:692: source_path = "C:/Users/.../skills/debugger"` | 期望 `filepath.Join`（反斜杠），实现返回正斜杠；Linux 下两者一致 |
| 14 | `TestDshPluginPathDirs_FindsBothLayouts/flat` | `dsh_bundle_paths_test.go:268: dirs = [C:\Users\GOBAO\AppData\Roaming\DSH Desktop\runtime-commands\generations\gen-1\bin, ...\bin], want exactly ...` | `dshDesktopAppDataDir(runtime.GOOS, os.Getenv, home)` 在 Windows 读**真实 %APPDATA%**，被本机已安装的 DSH Desktop 污染 |
| 15 | `TestLockReusablePriorEnvRootSurvivesWorkspacesRootSwap` | `leader_workdir_reuse_test.go:1010: move the workspaces root aside: rename ...: The process cannot access the file because it is being used by another process.` | Windows 文件占用语义；POSIX 可 rename 已打开目录 |
| 16 | `TestPruneWorktree_LegacyCacheFallbackSerializesWithCreateWorktree` | `fatal: cannot stat '.../.repos/ws1/c+/Users/GOBAO/.../002.git/hooks/applypatch-msg.sample': Filename too long` | 缓存键把 Windows 绝对路径拼成 `c+/Users/...`，叠加 MAX_PATH 限制 |

第 14 项附带核实：`%APPDATA%\DSH Desktop\runtime-commands\{bin,generations}` 的创建时间为
**2026-09-16 12:34**，早于本次基线（2026-11-12），故该测试**未在本机新建目录**，只是读到了既有安装。

以上 16 项在 CI-linux 上预期通过（POSIX shell、可执行位、正斜杠、无 %APPDATA%、无 MAX_PATH），
**一律不进入 CI 排除**。其中第 10-12 项是上游测试 helper 的真实缺陷（JSON 未转义），
第 14 项是 S3 同类的"开发机路径"问题；两者都超出本 change 范围，见第 5 节上报。

### F 类：未分类（daemon，1 个）→ 不排除，待 CI-linux 观察

- `TestHandleRuntimeGone_DistinctDeletionsWithinCoalesceWindowBothRecover`：
  `runtime_gone_test.go:539: after second distinct deletion: register called 1 times, want 2 (coalesce window must clear on success)`

无平台相关错误信息，断言的是行为（第二次删除必须再次 register）。
两种可能：真实缺陷（成功路径未清 `reregisterNextAttempt`），或 fake register 异步完成与第二次调用之间的竞态。
**现有证据不足以判定**，因此既不归入 Windows-only，也不排除；必须由真实 CI-linux 运行（TC-CBE-005）定性。

### 失败分类小结

| 类 | 顶层数 | 失败帧 | 处置 |
|---|---|---|---|
| A 状态敏感探针 | 3 | 48 | CI 排除 + 独立入口（已 PASS） |
| B Windows 时钟粒度 | 2 | 2 | 不排除 |
| C manifest 缺口 | 1 | 1 | S8/S9 修复（RED） |
| D tools 契约缺口 | 6 | 6 | 上报，不排除 |
| E Windows-only | 16 | 17 | 不排除 |
| F 未分类 | 1 | 1 | 不排除，待 CI 观察 |
| 合计 | 29 | 75 | |

（E 类 17 帧：`TestDshPluginPathDirs_FindsBothLayouts` 有子测试帧 + 顶层帧各 1。）

## 3. skip 分类（135 个 skip 事件 / 129 个顶层）

| 来源 | 事件数 | 理由 | CI-linux 上是否会跑 | 处置 |
|---|---|---|---|---|
| handler | 46 | `REDIS_TEST_URL not set` | **会跑**（CI 提供 Redis） | 不声明 |
| handler | 1 | `set MULTICA_RUN_SKILLS_SH_INTEGRATION=1 to run live GitHub integration test`（`skill_test.go:989`） | 不会（CI 不 opt-in） | **已声明** |
| governance | 1 | `KNOWLEDGE_BASE_REMOTE_URL` / `KNOWLEDGE_BASE_TOKEN` 缺失（`reconcile_live_test.go:21`） | 不会（CI 无知识库凭据） | **已声明** |
| daemon | 86 | 平台守卫，24 种理由（见 `daemon-skip-reasons.txt`） | **会跑** | 不声明 |
| daemon | 1 | `relay helper child only`（`execution_binding_relay_test.go:26`，守卫是 `AIFI45_RELAY_HELPER_MODE` 环境变量，**不是** `runtime.GOOS`） | 不会（父进程才设置） | **已声明** |

daemon 的 86 个平台守卫 skip 已逐条核对守卫条件（`daemon-skip-guards.txt`）。
特别核实：5 条措辞为 "macOS-only" / "runs on Linux/macOS" 的 skip
（`agent_command_names_test.go:16,36`、`agents_probe_dsh_test.go:410,433`、`config_test.go:1489`）
全部位于 `if runtime.GOOS == "windows"` 之内 —— 它们在 Linux 上**会执行**，不是允许名单候选。
`config_test.go:459` 的 `stageFakeAgent` 同样是 GOOS 守卫。

**源码推导（非基线观测）1 项**：`daemon.TestChannelIsolationChild`
（`execution_control_isolation_test.go:116`，`helper process; the parent drives it`）。
该文件是 `//go:build linux`，Windows 基线根本没编译它，所以无法从基线观测；
按源码守卫声明，并在 reason 中明确标注"source-derived, not baseline-observed"。

## 4. 归属表最终内容与 CI 排除

`test-ownership.json`：
- `required-packages`：5 个（与基线 selection 一致），供 S5 的包级下限对账。
- `entries`：**4 条**，全部 `owner=independent`，每条含 package / test / owner / entry / reason。
- `allowed-skips`：**4 条**（3 条基线观测 + 1 条源码推导），每条含 package / test / reason。

`skip-regex` 输出（S5 传给 `go test -skip`）：
```
^(TestChannelIsolation|TestChannelMigrationAfterUp|TestChannelMigrationAfterDown|TestChannelMigrationAfterReapply)$
```

`TestChannelIsolation` 的排除依据是**源码**而非基线：`execution_control_isolation_test.go` 为
`//go:build linux`，`requireIsolationProfile`（:53）在没有获批 profile 时 `t.Fatalf`（不是 skip），
CI 无此 profile，整包运行会失败而非跳过；真实证明属于 WSL `AIFI-ISO` 独立入口（TC-TOR-004）。

**允许名单是下界，不是终态**：它由 Windows 基线 + 源码守卫推导，
CI-linux 的真实 skip 集合必须由 TC-CBE-005（真实 CI 运行）最终确认；
S5 的 `ci-evidence.mjs` 会把名单外的 skip 判为失败，从而把"漏声明"变成可见的红灯，而不是静默放过。

## 5. 超出本 change 范围的上报项（不静默修复、不静默排除）

1. **tools `rules.json` 的 `show` 形状缺口**（D 类 6 项）：需在 tools 仓放宽白名单以匹配 AIFI-56 R1；
   涉及 S13 是否把 `MULTICA_CONTROLLED_SHELL_RULES` 指向 pin 的 tools，须用户裁定。
2. **`writeTestClaudePlugin` 的 JSON 未转义**（E 类 10-12）：上游测试 helper 缺陷，Windows-only。
3. **`TestDshPluginPathDirs_FindsBothLayouts` 读真实 %APPDATA%**（E 类 14）：S3 同类开发机路径问题。
4. **`TestHandleRuntimeGone_...` 未定性**（F 类）：可能是真实缺陷，需 CI-linux 观察。
5. **`run-selection.mjs` 的 `parseArgs` 静默接受未知参数**：S4 的 RED 因此偏弱
   （`--evidence-dir 有值` 用例在实现前即通过）；正向写入路径改由真实基线产出 10 个证据文件证明。
6. **S3 遗留的 5 个 governance 范围外 skip**：已在 S3 记录中列明，未纳入本表。
7. **两个 handler fixture 依赖 `UnixNano` 唯一性**（B 类）：Windows 上不可靠，Linux 正常；
   S9 生成随机唯一键时**不得**沿用 `UnixNano`（本机已证伪）。

## 6. 证据文件索引

| 文件 | 内容 |
|---|---|
| `podman-before.txt` / `podman-after.txt` | 基线运行前后容器清单（去表头后逐字节相同） |
| `baseline-run.txt` | runner 的 5 行 selection 结论 + `remaining=0` |
| `events/*.ndjson` / `events/*.json` | 基线 5 个 selection 的原始 `go test -json` 流与结论；另含独立入口 3 组（`channel-migration-up/down/reapply`） |
| `events/classification.txt` | 逐顶层失败（含前 3 帧原文）与按理由分组的 skip |
| `events/baseline-analysis.txt` | 基线逐包 pass/fail/skip 与失败帧摘要 |
| `mtick003-elapsed.txt` | design 未验证事实 #2：`pass TestMTick003 elapsed=0.06`，无挂住 |
| `red-evidence-dir.tap` / `green-evidence-dir.tap` | `--evidence-dir` 的 RED / GREEN |
| `red-test-ownership.tap` / `green-test-ownership.tap` | 归属表检查器的 RED / GREEN |
| `real-ownership-check.txt` | 真实表 `check`（exit 0，4 entries + 4 allowed skips）与 `skip-regex` |
| `mutation-typo-entry.txt` | 拼错测试名 → exit 1（检查器非空转） |
| `mutation-allowed-skip-pin.txt` | 删掉一条 allowed-skip 声明 → 钉住用例失败；表按 sha256 逐字节还原 |
| `regression-directory.tap` | 目录全量回归 106 tests / 106 pass / 0 fail / 0 skipped |
| `independent-entries.txt` | 3 个状态探针在各自独立入口下 PASS；前后清单一致 |
| `podman-before-entries.txt` / `podman-after-entries.txt` | 独立入口运行的容器纪律 |
| `windows-clock-granularity.md` | UnixNano 探针：199996/200000 连续相同 |
| `daemon-skip-reasons.txt` / `daemon-skip-guards.txt` | 87 个 daemon skip 的 24 种理由与守卫核对 |