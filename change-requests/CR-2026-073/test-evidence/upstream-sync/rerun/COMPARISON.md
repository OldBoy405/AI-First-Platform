# CR-2026-073 B-C2 上游同步证据重跑与逐项对照

本文件由 `rerun/failure-sets/` 与各自原始 `02-test-go.log` 机器生成（脚本 `scripts/gen-evidence.mjs`），所有数字可回到原始日志逐行核对。

## 1. 本轮运行

在三个已记录的提交上重跑同一套全量带库 Go 套件（`scripts/test-go.sh`，无 `--race`），每组条件三个提交各跑一次，共 6 次 + 1 次定向复核：

| 条件 | 提交 | 树 HEAD | DB | TMPDIR | 套件 exit | 失败项 | 原始日志 |
|---|---|---|---|---|---|---|---|
| cond-a-tasktmp | merged | `820bb5a11` | `cr073_merged` | `继承任务环境: multica-task-2074477066` | 1 | 176 | `cond-a-tasktmp/merged/02-test-go.log` (1268037 B, sha256 `5d59a1f011619a64330d1b5a913fa95ebbfc3d7e9d79d1f4ad6a5691eebac6c6`) |
| cond-a-tasktmp | premerge | `95da7c9d7` | `cr073_premerge` | `继承任务环境: multica-task-2074477066` | 1 | 148 | `cond-a-tasktmp/premerge/02-test-go.log` (1175868 B, sha256 `616f5ef6c6106379b1f70977ad2762a05f5c1d101121b201554b280ba11e79ec`) |
| cond-a-tasktmp | upstream | `4736a85d4` | `cr073_upstream` | `继承任务环境: multica-task-2074477066` | 1 | 178 | `cond-a-tasktmp/upstream/02-test-go.log` (1251049 B, sha256 `b0d960fb1f243659f93b138d6b96e63459ab4330167c26e63c25e5318c4a7f32`) |
| cond-b-shorttmp | merged | `820bb5a11` | `cr073_shorttmp_merged_` | `C:/rt/cond-b-shorttmp-merged` | 1 | 135 | `cond-b-shorttmp/merged/02-test-go.log` (1202989 B, sha256 `9aec9851364d7c36f2f7ef6eb9035e94bdbaaa71979ec3c89a639d887adf1aca`) |
| cond-b-shorttmp | premerge | `95da7c9d7` | `cr073_shorttmp_premerge_` | `C:/rt/cond-b-shorttmp-premerge` | 1 | 115 | `cond-b-shorttmp/premerge/02-test-go.log` (1109291 B, sha256 `8a50fd195bda61353df89de99ac7c9f44cea51efe443130237189e4dd9c5552b`) |
| cond-b-shorttmp | upstream | `4736a85d4` | `cr073_shorttmp_upstream_` | `C:/rt/cond-b-shorttmp-upstream` | 1 | 137 | `cond-b-shorttmp/upstream/02-test-go.log` (1188445 B, sha256 `8e37e46d2dc8e4796df717ee66941b77ae8c2051cc504bc6b504394d0e234716`) |

另有 `cond-b-shorttmp/premerge/03-targeted-merged-only-tests.log`：对「仅在 merged 失败」的 25 项在合并前树做定向复跑。

## 2. 条件一致性与已登记的偏离

- 三个提交、同一台 Windows 机器、同一 Go 工具链（`go version go1.26.4 windows/amd64`）、同一脚本与同一次调用形态（`cd server && go run ./cmd/migrate up`；`bash scripts/test-go.sh`，**无** `--race`——本机无 gcc）；`core.autocrlf=true`。
- 每个提交使用**新建空库**（`cr073_cond-a-tasktmp_*` / `cr073_cond-b-shorttmp_*`，见各 `00-db-setup.log`）并先跑各自提交的迁移。记录中的第七次同步用的是 `multica_go_test` / `multica_go_test_ab`（后者本机已不存在）：**绝对条数受共享测试库累计状态影响**，故本报告以「同批三树的逐项差集」为主要判据，并在 §3 与已记录基线逐包对照。
- 每次运行使用**全新的 GOCACHE**（`grep -c '(cached)'` = 0，见各 `00-meta.txt`），保证每个包真实执行、不复用任何早先尝试的结果。
- **运行中途被中止的尝试**（首个 wrong-password 尝试 + 一次缓存未清空的重跑）连同说明保存在 `_preflight-aborted-attempt/`，不计入本节数字。
- **行尾归一化**（唯一对工作树的改动）：合并前两个提交按 `text=auto` 检出 `scripts/agent-cli-command-names.txt` 为 CRLF，守卫脚本会以 `invalid agent CLI command name ...: agy` 直接退出 2（即记录的 Windows 陷阱）。对这两个树把该文件归一为 LF——内容证明与原文去 `\r` 后 sha256 全等，`git status` 干净、`git diff --ignore-cr-at-eol` 退出码 0，见各 `00-lineendings-normalization.txt`。
- **两个条件集**：`cond-a-tasktmp` 用本任务继承的临时根（`C:\Users\GOBAO\AppData\Local\Temp\multica-task-2074477066`），`cond-b-shorttmp` 把 TMPDIR/TEMP 指到短根 `C:/rt/...`。两集三树内部条件完全一致；两集之差即 Windows 长路径类环境噪声（见 §5）。
- **未执行 `./pkg/agent/...` 半程**：`scripts/test-go.sh` 为 `set -eu`，regular 半程已失败即退出——记录中的第七次同步同构（因此 `pkg/agent` 不在本证据面内，也不以它声称全绿）。

## 3. 失败条数与已记录基线（CUSTOM.md《已知测试失败基线》第七次同步行）对照

### cond-a-tasktmp（任务临时根）

| 包 | merged | premerge | upstream | 已记录基线（merged / premerge） |
|---|---|---|---|
| `cmd/migrate` | 1 | 0 | 1 | 1 |
| `cmd/multica` | 25 | 2 | 25 | 25 |
| `internal/cli` | 6 | 6 | 6 | 6 |
| `internal/daemon` | 65 | 65 | 67 | 61 |
| `internal/daemon/execenv` | 10 | 14 | 10 | 11 |
| `internal/daemon/repocache` | 55 | 46 | 55 | 22 |
| `internal/handler` | 2 | 2 | 2 | 2 |
| `internal/integrations/lark` | 0 | 1 | 0 | — |
| `internal/integrations/wecom` | 6 | 6 | 6 | 6 |
| `internal/maintenance` | 1 | 1 | 1 | 1 |
| `internal/service` | 4 | 4 | 4 | 4 |
| `internal/storage` | 1 | 1 | 1 | 1 |
| **合计** | 176 | 148 | 178 | 140 / 114 |


### cond-b-shorttmp（短临时根）

| 包 | merged | premerge | upstream | 已记录基线（merged / premerge） |
|---|---|---|---|
| `cmd/migrate` | 1 | 0 | 1 | 1 |
| `cmd/multica` | 25 | 2 | 25 | 25 |
| `internal/cli` | 6 | 6 | 6 | 6 |
| `internal/daemon` | 61 | 61 | 62 | 61 |
| `internal/daemon/execenv` | 10 | 14 | 10 | 11 |
| `internal/daemon/repocache` | 18 | 18 | 19 | 22 |
| `internal/handler` | 2 | 2 | 2 | 2 |
| `internal/integrations/lark` | 0 | 0 | 0 | — |
| `internal/integrations/wecom` | 6 | 6 | 6 | 6 |
| `internal/maintenance` | 1 | 1 | 1 | 1 |
| `internal/service` | 4 | 4 | 4 | 4 |
| `internal/storage` | 1 | 1 | 1 | 1 |
| **合计** | 135 | 115 | 137 | 140 / 114 |


- **包集合与已记录基线一致**（cond-b 的 premerge 少一个包：其唯一失败项 `cmd/migrate :: TestAgentTaskHistoryIndexMigrationAndPagePlans` 在合并前树**不存在**该用例，见 §4.1），逐包分布量级一致：cond-b 下 merged `internal/daemon`=61（记录 61）、`cmd/multica`=25（记录 25）、`cmd/migrate`=1（记录 1）、`internal/storage`=1（记录 1）。
- 与记录值 140/114 的差额，来源可逐条核对：① 本次为**空库**起步，记录那次在累计状态的共享测试库上跑（`internal/daemon/repocache`、`internal/daemon/execenv` 两组本身即状态敏感）；② 本次 `internal/daemon/execenv` 的 4 项 Hermes 用例在 premerge 树取到了本任务的 `MULTICA_TASK_CONFIG_ROOT`（失败消息里可见 `...\multica-config\hermes-state\...`），在 merged/upstream 树通过；③ `cmd/multica` 若干用例在 premerge 树**挂起**（见 §4）而非失败。

> 结论：与已记录基线**同名同包同量级**，不存在「多出一类新失败」的情况；差异全部落在记录中已标注为「环境类 / 共享测试库状态敏感」的组里。

## 4. 逐项失败名单对照（同批三树）

### 4.1 cond-b-shorttmp：merged − premerge = 25 项（仅合并结果树失败）

| # | 失败项 | 合并前树是否存在该用例 | 纯上游树是否同样失败 | 归类 |
|---|---|---|---|---|
| 1 | `cmd/migrate :: TestAgentTaskHistoryIndexMigrationAndPagePlans` | 否 | 是 | 同步新增用例（合并前树无此用例） |
| 2 | `cmd/multica :: TestDaemonLifecycleRefusesForeignDaemon` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 3 | `cmd/multica :: TestDaemonLogSourcePathResolvesPerProfile` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 4 | `cmd/multica :: TestDaemonRefusesDaemonWithUnreadableIdentity` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 5 | `cmd/multica :: TestDaemonRestartUnauthenticatedFailsBeforeStopping` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 6 | `cmd/multica :: TestDaemonStatusKnownProfileStillReportsStopped` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 7 | `cmd/multica :: TestDaemonStatusNestedProfileStillProbes` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 8 | `cmd/multica :: TestDaemonStatusReportsPortConflictInsteadOfClaimingItsOwn` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 9 | `cmd/multica :: TestDaemonStatusShowsWhoManagesTheDaemon` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 10 | `cmd/multica :: TestDaemonStatusUnknownProfile` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 11 | `cmd/multica :: TestDaemonStopAcceptsDaemonWithoutProfileField` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 12 | `cmd/multica :: TestEnumerateDiskUsageRoots` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 13 | `cmd/multica :: TestEnumerateDiskUsageRootsUsesAndDeduplicatesProfileConfig` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 14 | `cmd/multica :: TestFileWithinWorkingDirWindowsPaths` | 否 | 是 | 同步新增用例（合并前树无此用例） |
| 15 | `cmd/multica :: TestGuardLocalPathLinksOnlyFiresInAgentContext` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 16 | `cmd/multica :: TestPrintDiskUsageOtherRootsHintFiresWhenCurrentRootNonEmpty` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 17 | `cmd/multica :: TestPrintDiskUsageOtherRootsHintSuggestsProfilesWithTasks` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 18 | `cmd/multica :: TestRequireKnownProfile` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 19 | `cmd/multica :: TestResolveDiskUsageRootTaskContext` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 20 | `cmd/multica :: TestRunDaemonDiskUsageAllProfilesUsesPerProfileToken` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 21 | `cmd/multica :: TestRunDaemonDiskUsageJSONSurvivesServerFailure` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 22 | `cmd/multica :: TestRunDaemonLogsMissingFileNamesProfilePath` | 是 | 是 | 合并前树该包挂起被包超时中止 → 未观察到（非「通过」） |
| 23 | `cmd/multica :: TestRunRuntimeProfileSetAndUnsetPath` | 是 | 是 | 其余 |
| 24 | `cmd/multica :: TestRunRuntimeProfileSetPathPreservesExistingConfig` | 是 | 是 | 其余 |
| 25 | `internal/daemon/repocache :: TestCheckoutIdentityMigratesExistingWorktree` | 否 | 是 | 同步新增用例（合并前树无此用例） |

其中 `cmd/multica` 23 项、`cmd/migrate` 1 项、`internal/daemon/repocache` 1 项；23 项 `cmd/multica` 项在纯上游树**同样失败**（`merged − upstream` = 0 项），即这些失败随上游代码而来、不是本 fork 引入。

### 4.2 cond-b-shorttmp：premerge − merged = 5 项（仅合并前树失败，已记录基线曾记为 0）

| # | 失败项 | 原始失败首条消息 |
|---|---|---|
| 1 | `internal/daemon/execenv :: TestHermesMemoryStorePathLayout` | hermes_memory_test.go:63: store path = "C:\\Users\\GOBAO\\multica_workspaces_desktop-localhost-8080\\ai-first-f33387fe2294\\aifi-38-763a6c575196\\multica-config\\hermes-state\\11111111-2222-3333-4444-555555555555\\resear |
| 2 | `internal/daemon/execenv :: TestHermesSessionStorePathLayout` | hermes_sessions_test.go:27: store path = "C:\\Users\\GOBAO\\multica_workspaces_desktop-localhost-8080\\ai-first-f33387fe2294\\aifi-38-763a6c575196\\multica-config\\hermes-sessions\\11111111-2222-3333-4444-555555555555\\r |
| 3 | `internal/daemon/execenv :: TestPruneHermesMemoryStores` | hermes_memory_test.go:578: removed = 0, want 1 |
| 4 | `internal/daemon/execenv :: TestPruneHermesSessionStores` | hermes_sessions_test.go:293: removed = 0, want 1 ~ 2026/09/30 16:18:14 WARN execenv: hermes source home has no config.yaml; this task runs without a configured provider unless the environment supplies one source_home=C:\rt\cond-b-shorttmp-premerge\TestPrepareHermesHomeLi ~ 2026/09/30 16:18:14 WARN execenv: hermes session store not mounted; conversation history stays task-local store=C:\rt\cond-b-shorttmp-premerge\TestPrepareHermesHomeLinkFailureKeepsTaskLocalDB240182319\002\issue-1 error=" |
| 5 | `internal/daemon/repocache :: TestCreateWorktreeRemovesCoAuthoredByHookWhenDisabled` | cache_test.go:2030: CreateWorktree (disabled) failed: create worktree: git worktree add: Preparing worktree (new branch 'agent/test-agent/000000000000-1790756305') ~ fatal: cannot lock ref 'refs/heads/agent/test-agent/000000000000-1790756305': Unable to create 'C:/rt/cond-b-shorttmp-premerge/TestCreateWorktreeRemovesCoAuthoredByHookWhenDisabled1169041222/002/ws-1/c+/rt/cond-b-shorttm ~ 2026/09/30 16:18:26 INFO repo cache: cloning url=C:\rt\cond-b-shorttmp-premerge\TestFreshMigrationCarriesUnpushedBranchsame_task1600511510\001 path=C:\rt\cond-b-shorttmp-premerge\TestFreshMigrationCarriesUnpushedBranchsa |

### 4.3 cond-b-shorttmp：upstream − merged = 2 项（仅纯上游树失败；与记录中「2 项纯上游树时序/临时目录」同量级）

| # | 失败项 | 原始失败首条消息 |
|---|---|---|
| 1 | `internal/daemon :: TestLockReusablePriorEnvRootRejectsIdentitySwap` | leader_workdir_reuse_test.go:955: accepted reuse after the validated directory was replaced at the same path (would use C:\rt\cond-b-shorttmp-upstream\TestLockReusablePriorEnvRootRejectsIdentitySwap3005971344\001\ws-lead |
| 2 | `internal/daemon/repocache :: TestCreateWorktreeRemovesCoAuthoredByHookWhenDisabled` | cache_test.go:2030: CreateWorktree (disabled) failed: create worktree: git worktree add: Preparing worktree (new branch 'agent/test-agent/000000000000-1790756977') ~ fatal: cannot lock ref 'refs/heads/agent/test-agent/000000000000-1790756977': Unable to create 'C:/rt/cond-b-shorttmp-upstream/TestCreateWorktreeRemovesCoAuthoredByHookWhenDisabled3067922850/002/ws-1/c+/rt/cond-b-shorttm ~ 2026/09/30 16:29:37 INFO repo cache: cloning url=C:\rt\cond-b-shorttmp-upstream\TestCreateWorktreeFetchesDespiteAgentBranchOnRemote631453092\001 path=C:\rt\cond-b-shorttmp-upstream\TestCreateWorktreeFetchesDespiteAgentBr |

### 4.4 cond-b-shorttmp：merged − upstream = 0 项

**合并结果树相对纯上游树没有任何额外失败项**——fork 侧定制在本次同步结果中没有引入上游不存在的失败。

### 4.5 cond-a-tasktmp 的同口径差集（长临时根环境）

| 差集 | 项数 |
|---|---|
| merged − premerge | 33 |
| merged − upstream | 0 |
| premerge − upstream | 5 |
| upstream − merged | 2 |
| premerge − merged | 5 |

### 4.6 超时与包中止

| 条件/树 | 中止的包 | 挂起用例 | 记录 |
|---|---|---|---|
| cond-a-tasktmp/premerge | `cmd/multica`（600.107s） | `TestRunDaemonDiskUsageJSONSurvivesServerFailure`（9m53s） | `cond-a-tasktmp/premerge/02-test-go.log` |
| cond-b-shorttmp/premerge | `cmd/multica`（600.113s） | `TestRunDaemonDiskUsageJSONSurvivesServerFailure`（9m50s） | `cond-b-shorttmp/premerge/02-test-go.log` |
| cond-b-shorttmp/premerge 定向复跑（`-timeout 300s`） | `cmd/multica`（300.108s） | `TestRunDaemonDiskUsageAllProfilesUsesPerProfileToken`（5m0s） | `cond-b-shorttmp/premerge/03-targeted-merged-only-tests.log` |

因此合并前树的 `cmd/multica` 失败清单**不完整**（仅记录到中止前已打印的项）；在 merged 与 upstream 树上这些用例会快速失败而不是挂起。

## 5. 环境噪声的量化（两个条件集之差）

| 树 | cond-a 失败项 | cond-b 失败项 | 差 | 差额所在包 |
|---|---|---|---|---|
| merged | 176 | 135 | 41 | internal/daemon、internal/daemon/repocache |
| premerge | 148 | 115 | 33 | internal/daemon、internal/daemon/repocache、internal/integrations/lark |
| upstream | 178 | 137 | 41 | internal/daemon、internal/daemon/repocache |

差集项在原始日志中的失败消息形如 `git clone --bare: fatal: cannot stat 'C:/Users/GOBAO/AppData/Local/Temp/multica-task-2074477066/...'`、`cannot create leading directories of ...`——临时根过长触发的 Windows 路径类失败，仅出现在任务临时根条件下；把临时根缩短为 `C:/rt/...` 后消失。两组三树各自内部条件一致，互为对照。

## 6. 结论（对应 plan §5 上游场景取证要求）

1. **全量原始日志**：三提交 × 两条件共 6 份未截断 stdout/stderr（字节数与 sha256 见各 `00-meta.txt`），含命令、cwd、提交 SHA、起止时间、exit code；合并前/纯上游基线为**同批同条件**实测，不是摘要推断。
2. **逐项失败对照**：与 `CUSTOM.md#已知测试失败基线` 第七次同步行逐包对照（§3），与三树同批差集逐项对照（§4）；已知失败**没有**被改成绿或以子集替代全量。
3. **fork 归因**：`merged − upstream = 0`；仅在纯上游树出现的 2 项与仅在合并前树出现的 5 项均为时序/临时目录/任务环境类（§4.2、§4.3、§4.6），同类项在两棵 pre-merge 树各自复现。
4. **未闭合面（不得据此声称全绿）**：`./pkg/agent/...` 半程未执行（与记录同构）；合并前树 `cmd/multica` 清单因包超时中止而不完整；绝对条数与记录值存在空库/累计库差异（§2、§3）。

## 7. 复现

```bash
# 前置：multica 仓三个提交的干净 worktree；postgres 容器 multica-postgres
bash scripts/run_one.sh cond-b-shorttmp merged     # 生成 rerun/cond-b-shorttmp/merged/*
bash scripts/run_one.sh cond-b-shorttmp premerge
bash scripts/run_one.sh cond-b-shorttmp upstream
bash scripts/targeted_premerge.sh                  # 25 项定向复核
node scripts/gen-evidence.mjs                      # 重新生成本文件与 failure-sets/
```

脚本随证据一并存放于 `rerun/scripts/`。
