# cmd-03 证据补齐与同环境改前基线对照（TASK-02）

> 用途：补齐 TASK-02 的 `cmd-03` 证据缺口（短根日志、8 项失败明细、同环境改前基线对照），供 `write-test-report`／`review-code` 消费。
> 授权依据：Ray 2026-10-10T10:44:30（`01a1256a-1287-742e-87fc-18b2d8eb8c97`）「先补短根日志、8项失败明细及同环境改前基线对照；本 CR 相关验证通过后，可将确认的既有平台失败单独记录，不顺带扩大 repocache 修复范围，不将全量失败报告为通过」。
> 本文件与三份日志同属 `cmd-03` 的证据面，不新增 plan §6.2 未列的命令；`run` 定向日志是同一命令的失败明细派生物。

## 一、命令与环境（四份证据同一环境）

| 证据文件 | 命令 | 工作副本 HEAD | `TMP`／`TEMP` |
|---|---|---|---|
| `cmd-03.log` | `go test ./internal/daemon/repocache/ -count=1 -v` | 默认临时根（本 runtime 多层嵌套路径） | 未设置 |
| `cmd-03-short-root.log` | 同上 | `e5f0fc089`（TASK-01＋TASK-02 已落盘） | `C:\ctmp` |
| `cmd-03-baseline.log` | 同上 | `a2046ce34`（本 CR 在 multica 仓的 merge-base／改前基线） | `C:\ctmp` |
| `cmd-03-short-root-failures.log` | `go test ./internal/daemon/repocache/ -count=1 -v -run '^(8 个失败名集)$'` | `e5f0fc089` | `C:\ctmp` |

执行目录一律为对应工作副本的 `server/`；`go version go1.27.1 windows/amd64`。

## 二、同环境改前基线对照（结论：8 项失败改前即存在）

| 观测面 | 改前基线 `a2046ce34` | 改后 `e5f0fc089` | 判读 |
|---|---|---|---|
| 默认临时根（`cmd-03.log`） | 未采集 | 顶层 FAIL **55** | 失败数随临时根长度膨胀 → 噪声面 |
| 短临时根 `C:\ctmp` 顶层 FAIL 数 | **8** | **8** | 一致 |
| 短临时根 `--- PASS:` 数 | **78** | **78** | 一致 |
| 短临时根失败名集 | 见第三节 8 项 | **逐名一致** | 集合相等 |
| 退出码 | `exit=1` | `exit=1` | 一致（不报告为通过） |
| 身份相关用例（9 个） | 全部 `PASS` | 全部 `PASS` | 见第四节 |
| `go list -deps ./internal/daemon/repocache/` 命中 `internal/daemon` | — | **0** | 该包不依赖本 TASK 改动的包 |

短根失败名集在改前改后逐名一致，且 `repocache` 包不导入 `internal/daemon`（`go list -deps` 零命中），因此 8 项失败**与本 CR 的 `GIT_CONFIG_GLOBAL`／身份写入点改动无因果关系**。

## 三、8 项失败明细（逐项，取自 `cmd-03-short-root-failures.log` 定向运行）

| # | 用例 | 失败断言（原样摘要） | 根因归类 |
|---|---|---|---|
| 1 | `TestCreateWorktreeFromPartialCacheHasFileContents` | `partial_clone_test.go:177: create workspace cache dir: mkdir C:\ctmp\...\002\ws-1\file+C:: The filename, directory name, or volume label syntax is incorrect.` | A：`file+<盘符:>` 形 cache 目录在 Windows 不可创建 |
| 2 | `TestReusedIsolatedCheckoutRepairsPromisorConfig` | `partial_clone_test.go:141: create workspace cache dir: mkdir ...\ws-1\file+C:: ...` | A |
| 3 | `TestCreateIsolatedCheckoutFromPartialCacheHasFileContents` | `partial_clone_test.go:104: create workspace cache dir: mkdir ...\ws-1\file+C:: ...` | A |
| 4 | `TestIsPartialClone` | `partial_clone_test.go:198: sync failed: git clone --bare: fatal: could not create leading directories of 'C:\ctmp\...\ws-1\file+C:\ctmp\...\001.git': exit status 128` | A |
| 5 | `TestReconcileCoAuthoredByHooksUpgradesReleasedHookInPlace` | `cache_test.go:2625: hook was not upgraded to read the state file.` | B：Unix `prepare-commit-msg` 钩子升级语义 |
| 6 | `TestReconcileCoAuthoredByHooksMigratesReleasedHook` | `cache_test.go:2599: expected the previous release's hook to be removed at ...\hooks\prepare-commit-msg, stat err=<nil>`／`cache_test.go:2602: upgraded host still adds the trailer after the toggle was turned off.` | B |
| 7 | `TestCreateWorktreeDoesNotExcludeReasonixProjectConfig` | `cache_test.go:1289: checkout "C:\\ctmp\\...\\003\\ctmp\\...\\001" is not a child of the work dir "C:\\ctmp\\...\\003"` | C：路径父子关系断言（Windows 盘符重复拼接） |
| 8 | `TestFreshCheckoutDiscardsLocalWork` | `existing_checkout_test.go:307: tracked.txt = "base\r\n", want the uncommitted edit discarded` | D：CRLF 行尾断言（Windows autocrlf） |

归类口径：A＝4 项、B＝2 项、C＝1 项、D＝1 项，共 8 项。四类均为该包测试对平台的假设不成立（Windows 目录名合法性／Unix 钩子语义／路径拼接／行尾），与 `GIT_CONFIG_GLOBAL`、`[include]` 身份叠加、`safe.directory` 三段配置无交集。

默认临时根下 55 项的膨胀面同样来自上述平台假设被长路径叠加放大（`file+C:` 与盘符重复拼接对路径长度敏感），不是新增失败类别。

## 四、本 CR 相关验证（短临时根，改后）

- 身份／配置环境面 9 个用例全绿：`TestCheckoutIdentityIgnoresSharedCache`、`TestCheckoutIdentityConcurrentTasksAndOverrides`、`TestCheckoutIdentityMigratesExistingWorktree`、`TestCheckoutIdentityUserConfigAndCoauthor`、`TestCheckoutIdentityWithoutUserFailsClosed`、`TestIsolatedCheckoutPreservesIntentionalIdentity`、`TestCheckoutIdentityConfigLockFailureIsRetryable`、`TestCheckoutIdentityRejectsForeignWorktree`、`TestCheckoutIdentityEnabledWithSharedConfigLocked`。
- 短临时根下改前基线同样全绿，即该子集与本次改动前后行为一致（无回归）。
- TASK-02 的 `cmd-02` 定向证据（`cmd-02.log`，`exit=0`）已覆盖叠加式三段配置与「身份缺失在账本写入前失败关闭」。

## 五、结论

1. `cmd-03` **不报告为通过**：改后仍 `exit=1`，8 项失败按 Ray 的裁定**单独记录**为既有平台失败（本 CR 不修复、不顺带扩大 repocache 范围）。
2. 8 项失败在**同环境改前基线**上逐名复现，且该包不依赖本 CR 改动的包 → 与本 CR 无因果。
3. 本 CR 相关验证（身份／配置环境子集）在短临时根下全绿，改前改后一致。
