---
id: CR-2026-075-cmd-records
type: EVIDENCE
cr-ref: CR-2026-075
source-task: CR-2026-075-TASK-10
target-version: 0.48
updated: 2026-10-06T04:53:15.085Z
---

# CR-2026-075 证据命令执行记录（`cmd-01`～`cmd-11`）

命令形态的唯一事实源是 `plan.md` §6.2 证据命令表：下表 `repo`/`cwd`/`executable`/`args`/`timeout` 五列在本轮**逐字取自该表**（执行器由表行解析后直接 `spawnSync(executable, args, { shell:false, cwd })`，未改写、未合并、未替换、未新增参数），逐条原始输出见同目录 `cmd-NN.txt`。

记录口径（CR-2026-073 FR-6/FR-8）：每条写明**真实运行范围**；范围小于全仓的命令**不得**被读作「全量通过」；本轮未使用 `go test ./...`、`make test` 等全仓命令，也未新增 plan 未列的命令行。

| 证据ID | repo | cwd | executable | timeout(s) | exit | 耗时(ms) | 真实运行范围 | 本轮结果摘要 |
|---|---|---|---|---|---|---|---|---|
| `cmd-01` | tools | `.` | `node` | 900 | ✅ 0 | 144250 | 单文件 `skills/shared/crctl/scripts/test/crctl.test.mjs`（tools 仓；**非 tools 仓全量**） | `node --test` 单文件：tests 247 / pass 247 / fail 0（✔ 247） |
| `cmd-02` | tools | `.` | `node` | 600 | ✅ 0 | 7074 | 单文件 `planning-entry.test.mjs`（tools 仓；非全仓） | tests 10 / pass 10 / fail 0 |
| `cmd-03` | tools | `.` | `node` | 600 | ✅ 0 | 10146 | 单文件 `competitive-report.test.mjs`（tools 仓；非全仓） | tests 15 / pass 15 / fail 0 |
| `cmd-04` | tools | `.` | `node` | 600 | ✅ 0 | 783 | 单文件 `durable-tx.test.mjs`（tools 仓；非全仓） | tests 16 / pass 16 / fail 0 |
| `cmd-05` | tools | `.` | `node` | 300 | ✅ 0 | 2386 | 六个单文件合并运行：`caller-contract` / `contract-scan` / `check-skill-matrix` / `check-agents-contract` / `lint-prompts` / `pipeline-structure`（tools 仓；非该目录全量、非全仓） | 六文件合并：tests 125 / pass 125 / fail 0 |
| `cmd-06` | tools | `skills/shared/engineering-docs/scripts` | `node` | 600 | ✅ 0 | 1200 | `skills/shared/engineering-docs/scripts` 目录下 vitest **定向文件集**（`src/__tests__/{generators,validators}.test.ts`；**非该 TS 包全量、非 tools 仓全量**） | vitest 定向文件集：Test Files 2 passed (2) / Tests 21 passed (21)（generators 12 + validators 9） |
| `cmd-07` | multica | `server` | `go` | 900 | ✅ 0 | 2077 | multica `./internal/daemon/` **单包 + 定向 `-run` 名集**（非包内全量、非 `go test ./...`） | go test 单包定向名集：顶层 `--- PASS:` 18 行 / 子测试 `    --- PASS:` 24 行；`ok` 包级通过 |
| `cmd-08` | multica | `.` | `node` | 300 | ✅ 0 | 105 | multica `cr-prompts-revised/test/delegation-contract.test.mjs` 单文件（非 multica 仓全量） | `node --test` 单文件：tests 19 / pass 19 / fail 0 |
| `cmd-09` | multica | `.` | `node` | 300 | ✅ 0 | 120 | multica CR worktree 内只读内联脚本（平台只读查询 + 仓库副本比对；零写入） | deployment-copy 4 行（LF sha256）+ imported-skill 14 行 + agent-in-sync 4 行 + 末行 `cmd-09 ok` |
| `cmd-10` | tools | `.` | `node` | 600 | ✅ 0 | 728 | tools CR worktree 内只读内联脚本（平台只读查询 + 仓库目标比对；零写入） | skill-in-sync 14 行 + agent-in-sync 2 行 + out-of-scope-drift 1 行（R8 单列）+ 末行 `cmd-10 ok` |
| `cmd-11` | tools | `.` | `node` | 3600 | ❌ 1 | 562360 | tools `skills/shared/crctl/scripts/test/` **测试文件集合**（磁盘集合 ≡ `gate-registry.json#manifest.files`，逐文件子进程；**非多仓全量**） | **verdict=block**：files_executed 28 / cases_executed 693 / failures 4；check_failed=SUITE_FAILURES_UNREGISTERED |

原始输出文件：`cmd-01.txt`、`cmd-02.txt`、`cmd-03.txt`、`cmd-04.txt`、`cmd-05.txt`、`cmd-06.txt`、`cmd-07.txt`、`cmd-08.txt`、`cmd-09.txt`、`cmd-10.txt`、`cmd-11.txt`。

## `cmd-07` `-v` `--- PASS` 摘要与 `-run` 名集分支命中

`-run` 名集（plan §6.2 原样，10 个 alternative；TASK-10 卡正文表述为「九个名集」，命令仍按表行原样执行，本行只记事实差异）：

```text

Test(InjectTaskCRWorkspaceEnv|DaemonEnvBuildHasNoConfigFirstRootFallback|PreparePipelineTaskHydratesMachineLocalPaths|ConfigurePipelineGitEnvironment|ConfigureTaskGitEnvironment|InstallPipelineCrctlLauncher|InstallCrctlLauncher|ResolveTaskWorkspaceBinding|ParseExecutionContext|TaskWorkspaceBinding)
```

| 名集分支 | 顶层 `--- PASS:` 命中 |
|---|---|
| `TestInjectTaskCRWorkspaceEnv` | 9 |
| `TestDaemonEnvBuildHasNoConfigFirstRootFallback` | 1 |
| `TestPreparePipelineTaskHydratesMachineLocalPaths` | 1 |
| `TestConfigurePipelineGitEnvironment` | 1 |
| `TestConfigureTaskGitEnvironment` | 1 |
| `TestInstallPipelineCrctlLauncher` | 1 |
| `TestInstallCrctlLauncher` | 1 |
| `TestResolveTaskWorkspaceBinding` | 1 |
| `TestParseExecutionContext` | 1 |
| `TestTaskWorkspaceBinding` | 1 |

顶层 PASS 行合计 18；包级结果行 `ok  github.com/multica-ai/multica/server/internal/daemon`。

## `cmd-09` 比对结果（部署副本收敛 / 取用路径台账 / 线上 instructions）

```text
deployment-copy requirement-writer sha256=9cdae83a96bf030bf34c9b251a8e90526923df332fba69236c88257e73007f08
deployment-copy dev-agent sha256=4137bc575ee9ab05d27f2c3013f61182e2188252468c5a6a766b9c402f225218
deployment-copy quality-reviewer-agent sha256=daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c
deployment-copy cr-coordinator-agent sha256=b383a2f294cef4a6c0ec6f03a2249affb8ed9735a959db16590436474acab1f3
imported-skill crctl AI-First-tools@main/skills/shared/crctl
imported-skill validate-doc AI-First-tools@main/skills/shared/validate-doc
imported-skill engineering-docs AI-First-tools@main/skills/shared/engineering-docs
imported-skill cr-review-record AI-First-tools@main/skills/cr/cr-review-record
imported-skill review-code AI-First-tools@main/skills/develop/review-code
imported-skill review-dev-plan AI-First-tools@main/skills/develop/review-dev-plan
imported-skill review-tech-design AI-First-tools@main/skills/develop/review-tech-design
imported-skill write-dev-tasks AI-First-tools@main/skills/develop/write-dev-tasks
imported-skill write-tech-design AI-First-tools@main/skills/develop/write-tech-design
imported-skill review-requirement AI-First-tools@main/skills/requirement/review-requirement
imported-skill write-planning-entry AI-First-tools@main/skills/planning/write-planning-entry
imported-skill planning-draft AI-First-tools@main/skills/planning/planning-draft
imported-skill write-competitive-report AI-First-tools@main/skills/competitive/write-competitive-report
imported-skill requirement-register AI-First-tools@main/skills/requirement/requirement-register
agent-in-sync requirement-writer sha256=9cdae83a96bf030bf34c9b251a8e90526923df332fba69236c88257e73007f08
agent-in-sync dev-agent sha256=4137bc575ee9ab05d27f2c3013f61182e2188252468c5a6a766b9c402f225218
agent-in-sync quality-reviewer-agent sha256=daf87cb1b9046e3b1b576187d131ba5b1f120c650a6616cd76b4037a6a19b15c
agent-in-sync cr-coordinator-agent sha256=b383a2f294cef4a6c0ec6f03a2249affb8ed9735a959db16590436474acab1f3
cmd-09 ok: 部署副本收敛与 imported Skills 取用路径零漂移；四份 CR Agent 线上 instructions 与部署副本逐字一致（LF）
```

## `cmd-11` 逐文件顶层用例数与 `gate-registry.json#manifest` 核对

聚合门禁范围：tools `skills/shared/crctl/scripts/test/` 测试文件集合（磁盘集合 ≡ `manifest.files`，28 个文件、693 用例；**不表述为多仓全量**）。registry sha256 = `f0eaaa944d1a658b4b4c9657289635aa92f9d9a6914c40133ae3234ee10c5db2`，`exceptions` 项数 = 0。

| 文件 | 本轮顶层用例数 | state | exit | manifest 基线 | 基线核对 | 失败项数 |
|---|---|---|---|---|---|---|
| `archive-tx.test.mjs` | 30 | ok | 0 | 24 | ≥ 24 ✅ | 0 |
| `caller-contract.test.mjs` | 15 | ok | 0 | 13 | ≥ 13 ✅ | 0 |
| `check-agents-contract.test.mjs` | 1 | ok | 0 | 1 | ≥ 1 ✅ | 0 |
| `check-skill-matrix.test.mjs` | 8 | ok | 0 | 8 | ≥ 8 ✅ | 0 |
| `checkpoint-tx.test.mjs` | 23 | ok | 0 | 23 | ≥ 23 ✅ | 0 |
| `competitive-report.test.mjs` | 15 | ok | 0 | 15 | ≥ 15 ✅ | 0 |
| `contract-scan.test.mjs` | 26 | ok | 0 | 17 | ≥ 17 ✅ | 0 |
| `crctl-summary.test.mjs` | 8 | failed | 1 | 8 | ≥ 8 ✅ | 4 |
| `crctl.test.mjs` | 247 | ok | 0 | 237 | ≥ 237 ✅ | 0 |
| `durable-tx.test.mjs` | 16 | ok | 0 | 10 | ≥ 10 ✅ | 0 |
| `fault-harness.test.mjs` | 8 | ok | 0 | 8 | ≥ 8 ✅ | 0 |
| `guard-protected-paths.test.mjs` | 5 | ok | 0 | 5 | ≥ 5 ✅ | 0 |
| `lint-prompts.test.mjs` | 39 | ok | 0 | 39 | ≥ 39 ✅ | 0 |
| `merge-tx.test.mjs` | 17 | ok | 0 | 17 | ≥ 17 ✅ | 0 |
| `pipeline-structure.test.mjs` | 36 | ok | 0 | 36 | ≥ 36 ✅ | 0 |
| `planning-entry.test.mjs` | 10 | ok | 0 | 10 | ≥ 10 ✅ | 0 |
| `register-tx.test.mjs` | 30 | ok | 0 | 30 | ≥ 30 ✅ | 0 |
| `skill-scope.test.mjs` | 3 | ok | 0 | 3 | ≥ 3 ✅ | 0 |
| `terminal-audit.test.mjs` | 3 | ok | 0 | 3 | ≥ 3 ✅ | 0 |
| `test-cr.test.mjs` | 30 | ok | 0 | 27 | ≥ 27 ✅ | 0 |
| `trace-outbox.test.mjs` | 12 | ok | 0 | 12 | ≥ 12 ✅ | 0 |
| `trace-semantic.test.mjs` | 5 | ok | 0 | 5 | ≥ 5 ✅ | 0 |
| `upgrade-check.test.mjs` | 2 | ok | 0 | 2 | ≥ 2 ✅ | 0 |
| `version-set.test.mjs` | 12 | ok | 0 | 12 | ≥ 12 ✅ | 0 |
| `workspace-freshness.test.mjs` | 32 | ok | 0 | 32 | ≥ 32 ✅ | 0 |
| `workspace-resolver.test.mjs` | 7 | ok | 0 | 7 | ≥ 7 ✅ | 0 |
| `writeback-tx.test.mjs` | 36 | ok | 0 | 36 | ≥ 36 ✅ | 0 |
| `yaml-subset.test.mjs` | 17 | ok | 0 | 17 | ≥ 17 ✅ | 0 |

摘要行（原样）：

```text
suite-gate: command=node --test --test-reporter=tap <28 files> (pool=15, availableParallelism=16)
suite-gate: observer=tap-per-file duration_ms=562314 converged=true exit_code=1
suite-gate: files_executed=28 cases_executed=693 skipped_file_level=0
suite-gate: failures=4 [summary-03 逐命令：--detail 输出与金样本三层等价（① 字段集合 ② 稳定值 ③ 易变形态） | summary-04 注册命令默认面 = compact summary（为 --detail 面的真子集且严格更少字段） | summary-05 未注册命令收到 --detail 与未收到 --detail 均与现状等价（D-9 代价项） | summary-06 --detail 是布尔开关，不消费后随 token（位置参数不被吃掉）]
suite-gate: registry_sha256=f0eaaa944d1a658b4b4c9657289635aa92f9d9a6914c40133ae3234ee10c5db2 exceptions_count=0
suite-gate: check_failed=SUITE_FAILURES_UNREGISTERED detail=未登记失败：summary-03 逐命令：--detail 输出与金样本三层等价（① 字段集合 ② 稳定值 ③ 易变形态）、summary-04 注册命令默认面 = compact summary（为 --detail 面的真子集且严格更少字段）、summary-05 未注册命令收到 --detail 与未收到 --detail 均与现状等价（D-9 代价项）、summary-06 --detail 是布尔开关，不消费后随 token（位置参数不被吃掉）
suite-gate: verdict=block
```

**本轮红项（如实记录，不在 TASK-10 内修实现）**：`SUITE_FAILURES_UNREGISTERED` = `crctl-summary.test.mjs` 的 4 例（`summary-03`～`summary-06`，`SyntaxError: Unexpected end of JSON input`）。该 4 例在**基线 `061a12f` 同机同样红**（本 TASK 用 `git archive 061a12f skills/shared/crctl` 抽出基线副本独立复跑复现，8 例中 pass 4 / fail 4，与本轮 HEAD 完全同集）；根因是绑定守卫与夹具根冲突（`crctl-summary.test.mjs` 用 `os.tmpdir()` 造夹具并以 `--workspace <tmp>` 驱动 CLI，而本轮任务环境已注入 `CRCTL_OPERATIONAL_WORKSPACE` → 显式异根被 `WORKSPACE_CONTEXT_MISMATCH` 拒绝、stdout 为空）。判据与边界见 `uncovered-risks.md` 的 R15。

## FR-04 段① / 段② 逐条可见性核对（`cmd-01` / `cmd-05`）

口径（TASK-10 卡）：不以用例总数绿替代逐条可见性核对——下表的「断言位置」是断言在测试文件中的落点，「本轮结果」是该用例在本轮 `cmd-01`/`cmd-05` 原始输出中的行状态。

| 面 | 子项 | 断言位置（tools CR worktree） | 本轮结果 |
|---|---|---|---|
| 段① | M1 真缺参归一成功且全程无错误码 | `crctl.test.mjs:509` | ✔ 见原始输出 |
| 段① | M2 绑定下空串/纯空白/裸旗标不归一并报 `WORKSPACE_REQUIRED`、stdout 无成功回执 | `crctl.test.mjs:662` | ✔ 见原始输出 |
| 段① | 同根（含尾分隔符与 `\\?\` 别名）一次成功、归一与显式同根逐字同结果 | `crctl.test.mjs:673` | ✔ 见原始输出 |
| 段① | M4 显式异根 `WORKSPACE_CONTEXT_MISMATCH` + 零业务写入 + 重放仍零写入 | `crctl.test.mjs:689` | ✔ 见原始输出 |
| 段① | M3/无绑定声明缺根同码（`WORKSPACE_REQUIRED`） | `crctl.test.mjs:560` | ✔ 见原始输出 |
| 段① | `BAD_ARGS` 与空串/裸旗标不进本地纠正集合 | `crctl.test.mjs:627` | ✔ 见原始输出 |
| 段② | 五项前置 + 同 run 恰一次 + 只改一个参数 + 机器侧零改动 + 审计保留 | `caller-contract.test.mjs:534` | ✔ 见原始输出 |
| 段② | 六条「明确不构成授权来源」负面清单逐条且恰为六条 | `caller-contract.test.mjs:562` | ✔ 见原始输出 |

**边界（不得误读）**：段①/段② 的可见性核对只证明 FR-04 的**机器语义面与调用方静态合同面**；FR-04 **段③**（实际受控调用方节点的节点日志/回放）不由 `cmd-*` 断言，其取证载体 = `test-evidence/caller-replay/`（TASK-08 生产）+ `write-test-report` 机器区 + `review-code` 逐条人工核对。`cmd-01`/`cmd-05` 全绿**不得**被读作段③已验证。

## `test-evidence/caller-replay/` 归档核对（本 TASK 只核对不生产）

归档为 `CR-2026-075-TASK-08` 生产（`records.json#producedBy`：task / skill / agent / at），本 TASK **只核对不生产、不改写**。

| 文件 | 存在 | 字节 | sha256（LF 归一） |
|---|---|---|---|
| `caller-replay/records.json` | 是 | 4762 | `973ec72aa09fed366fa1248e29c88d30eaad9f1a67290a6e5607533693a672d0` |
| `caller-replay/A.node-record.json` | 是 | 133696 | `ad3b9973fbd3f80aaba4ad7955fb8af79d5ddfcef2eefc9ef02e317eff635fdf` |
| `caller-replay/B.node-record.json` | 是 | 131293 | `10f0e3ddc205298363d6e6b0a1b284fac5eb72207c535b9b5faac1c2931aafa7` |

records.json：schema=`cr-2026-075/caller-replay/v1`，cr=`CR-2026-075`，producedBy.task=`CR-2026-075-TASK-08`，producedBy.at=`2026-10-06T01:51:06.465Z`；逐调用字段记录在 `{A,B}.node-record.json` 的 `calls[]`。

| 核对字段（TASK-10 卡列举） | A.node-record.json | B.node-record.json |
|---|---|---|
| 调用次数 `calls.length` | 2 | 2 |
| 两次调用 `argv` | ① `status CR-2026-075 --workspace ` ② `status CR-2026-075 --workspace C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-075` | ① `status CR-2026-075 --workspace    ` ② `status CR-2026-075 --workspace C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-075` |
| 两次 `exitCode` | 1, 0 | 1, 1 |
| 两次 `errorCode` | WORKSPACE_REQUIRED,  | WORKSPACE_REQUIRED, WORKSPACE_CONTEXT_MISMATCH |
| stderr 单一 JSON（两次） | true, false | true, true |
| 两次逐次绑定三值 `calls[].bindingTripleUsed` | ① MULTICA_TASK_ID / CRCTL_OPERATIONAL_WORKSPACE / CRCTL_TASK_AUDIT_ROOT ② 与 ① 全等（`bindingNotOverwritten=true`） | ① MULTICA_TASK_ID / CRCTL_OPERATIONAL_WORKSPACE / CRCTL_TASK_AUDIT_ROOT ② 与 ① 全等（`bindingNotOverwritten=true`） |
| stdout 含成功回执（两次） | false, true | false, false |
| 纠正次数 `correctionCount` | 1（`仅把 --workspace 换成同一绑定根的已确认显式根（本 run = CRCTL_OPERATIONAL_WORKSPACE）`） | 1（`仅把 --workspace 换成同一绑定根的已确认显式根（本 run = CRCTL_OPERATIONAL_WORKSPACE）`） |
| 有无第三次调用 `thirdCallOccurred` | false | false |
| 有无恢复委派 `recoveryDelegation` | false | false |
| 有无版本扫描 `versionScan` | false | false |
| 零业务写入证明 `zeroWriteProof` | `before.gitStatus.porcelain` + 前后 journal 集合比对（`before`/`after`/`delta`） | 同上结构 |
| 停止自动纠正 `stoppedAutoCorrection` | `纠正后一次成功，无需再次纠正（无第三次调用）` | `true` |

**核对结论**：三条归档文件存在，TASK-10 卡列举的字段在归档内**逐项可检索且取值自洽**（A 变体：WORKSPACE_REQUIRED → 同 run 仅换 `--workspace` 一次成功、纠正 1 次、无第三次调用；B 变体：补成异根 → WORKSPACE_CONTEXT_MISMATCH、stdout 无成功回执、绑定未被覆盖、停止自动纠正）。本 TASK 未重跑、未改写该归档（`git status` 归档文件零改动）。
