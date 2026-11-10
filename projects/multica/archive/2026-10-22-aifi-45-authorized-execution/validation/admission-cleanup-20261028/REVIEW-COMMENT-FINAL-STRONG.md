# AIFI-45 admission 回滚清理 — 注释修订后的终版独立复核（REVIEW-COMMENT-FINAL-STRONG）

> 性质：只读源码比对，外加一次独立的无 DB 构建和 `go test` 复跑。审查期间未修改任何源文件或测试文件；未运行数据库、容器、governance 包的 TestMain 或真实 CR 操作。
> 本报告不构成执行授权、审批或生产验收。
> **旧报告不能直接证明新 SHA 的行为。** 下面三份报告保持原样，只代表各自对应的快照：
> - `REVIEW-STRONG.md`（`44faed9f8d79b076ec062846f2212aa3fe029c2e2f08ec66d5a23ccf46aca0cf`）
> - `REVIEW-TIMEOUT-STRONG.md`（`3cbcc62c3e7b0a48c66528a6c8f277cd0bf795c7e0f3f5fb8ccf06017f6d4fee`），对应源码 `d2b6d567…`
> - `REVIEW-SINGLE-GUARD-STRONG.md`（`6bf735950252795003412c8b015e6ff638632c97bd054d5b9a216372a88dd225`），对应源码 `c0834fc2…`
>
> 本报告对 `b950f20b…` 的结论，来自本轮的直接比对和复跑。至于代码语义，本报告依据本轮证实的“相对 `c0834fc2…` 只有注释变化”，再结合本轮重新确认的源码行，沿用之前对 `c0834fc2…` 的静态语义分析。这是推导出来的，不是旧报告直接证明的。

## 0. 会话元数据与 backend receipt

| 项 | 值 |
|---|---|
| session ID | `01a18576-6db4-7020-aecc-d22b4d27063b`（来自 `PI_SESSION_ID`） |
| 请求模型（环境变量自报） | `PI_PROVIDER=GBClaude`，`PI_MODEL=claude-opus-5-5` |
| 真实 backend receipt | **不可得 / 未知**。本会话里没有任何可核验的后端调用 receipt、签名或响应元数据。上面的 provider/model 只是环境变量自报，不能证明实际是哪个后端模型执行的 |
| 源码仓库 | `C:/Users/GOBAO/Downloads/AI/multica`，HEAD `81e5293adc758e392a045026cf81ec5cc1bac72d`。`execution_admission_gate.go` 是未提交修改（`git status` 显示 ` M`）；`runnerquery_test/` 目录未纳入 git |
| 作者说明（只记录 SHA，内容未审） | `AUTHOR-COMMENT-BOUNDARY.md` `3a137e683eb8a6f8907d77244f44d5d484c1c84a3392d962a94e20078b228a73` |

## 1. SHA（raw SHA-256；当前文件在构建和测试前后一致）

| 角色 | 路径 | SHA-256 |
|---|---|---|
| 当前源码 | `server/internal/governance/execution_admission_gate.go` | `b950f20befd10977d34f531b87bf4d95b89c3e2a43546a733001a8778e16781d` |
| 当前 AST 测试 | `server/internal/governance/runnerquery_test/admission_cleanup_test.go` | `7eb49459ac4709eea9f326fba834aff88f99a471a5aa6ce2dae553aebb8150eb` |
| 同包测试（内容未审） | `server/internal/governance/runnerquery_test/active_query_test.go` | `f535341a576aee2dae1dc0f2be8cd2acccb1e14918590e9476be485cb978afd8` |
| 基线快照 | `source-single-guard/execution_admission_gate.go` | `c0834fc2fc34d4cc3b3fe7cf663ea0a5169b11a37c653f71a823f9c253805680` |
| 基线快照 | `source-single-guard/admission_cleanup_test.go` | `7eb49459ac4709eea9f326fba834aff88f99a471a5aa6ce2dae553aebb8150eb`（与当前测试逐字节相同） |

## 2. 只有注释变化的证据

用 `diff` 比较 `source-single-guard/execution_admission_gate.go`（220 行）和当前文件（219 行），只有两个 hunk：

1. **第 81–83 行替换为第 81–83 行**（函数文档注释）
   - 旧：`A refusal is returned as a nil transaction with the decision, already released — … a refused caller never holds a row lock while it writes its waiting annotation.`
   - 新：`A refusal returns a nil transaction after a rollback attempt, so "tx != nil" and "Allowed" cannot disagree. If cleanup fails or times out, the server may still hold a lock while the caller writes its waiting annotation.`
2. **第 118–120 行替换为第 118–119 行**（拒绝分支的注释）
   - 旧：`Release before returning. … holding this one while acquiring another from the same pool is how a wake with background context waits on itself.`
   - 新：`Attempt rollback before returning. A caller recording why nothing moved needs its own connection; uncertain server-side cleanup can still delay that write.`

逐行核对：
- diff 中共有 11 行改动（`<` 加 `>`），每一行去掉前导空白后都以 `//` 开头。不是 `//` 开头的改动行数为 0。
- 第 76–125 行里没有反引号，所以这些 `//` 行不可能位于原始字符串字面量里，都是真正的 Go 行注释。
- 其余代码行完全一致；行号只在拒绝分支之后整体减 1。

另外，`go build ./internal/governance` 退出码为 0、没有输出，说明当前文件能够编译。

**结论：相对 `c0834fc2…`，只有注释变化，可执行代码没有任何改动。**

新注释的措辞和静态语义一致：只承诺“尝试回滚”，并明确说清理失败或超时时服务端可能仍持锁。它不再声称锁在拒绝时已经释放，纠正了旧注释的过度断言。

## 3. 当前代码的关键行（本轮重新确认）

`decideUnderHeadLock`：
- 第 84 行：函数签名；
- 第 85 行：`r.pool.BeginTx`；
- 第 91 行：`handed := false`；
- 第 93–97 行：`if !handed { cleanupCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second); defer cancel(); _ = tx.Rollback(cleanupCtx) }`；
- 第 100 行：`lockExecutionAuthorizationHead`；
- 第 106 行：`r.decider.DecideAdmission`；
- 第 115 行：hook；
- 第 120 行：拒绝路径 `return nil, decision, nil`；
- 第 122 行：`handed = true`；
- 第 123 行：`return tx, decision, nil`。

函数体内 `tx.Rollback` 只出现在 guard 里。

## 4. 三个层次的结论，必须区分

| 层次 | 结论 | 证据等级 |
|---|---|---|
| **客户端回滚尝试** | 所有没交接出去的路径（lock 或 decider 出错、拒绝、panic、Goexit），都会在控制权回到调用方之前，由 guard 用 5 秒客户端截止时间执行一次 `tx.Rollback` 尝试。成功交接（第 122–123 行）时不尝试。错误返回值和 `ErrNoRows → HeadUnavailable` 的映射，与 `c0834fc2…` 一致 | 源码结构（AST 测试和人工阅读）加上对 pgx v5.11.0 的**静态推断** |
| **服务器锁释放** | **只有**连接健康且 ROLLBACK 在服务端成功执行时，`cr`/`approval_record` 上的 FOR SHARE 锁才会在调用方继续执行之前释放。超时、网络分区、连接 busy 或已关闭时，客户端只是把连接标为关闭并交给 Destroy，**服务端何时释放锁未知**，取决于后端何时感知到断连，或者服务端 keepalive、`idle_in_transaction_session_timeout` 的设置（仓库里没看到全局配置）。5 秒截止时间和约 15 秒的后台析构，都**不是**池槽或后台析构的绝对上界 | **未验证**。只有对 pgx/pgxpool/puddle 源码的静态推断，没有真实 DB 观测 |
| **生产验收** | **未进行，也不声称。** 没有真实 PostgreSQL 测试、故障注入、性能或存活性测量，也没有在生产或预发配置下验证（如连接池参数、代理、服务端超时设置） | 无 |

## 5. 独立无 DB 复跑

- 工作目录：`C:/Users/GOBAO/Downloads/AI/multica/server`
- 环境：
  - 用 `env -u` 清除了 `DATABASE_URL` 和所有 `PG*` 变量，当前 shell 核对为 0 个；
  - `GOPROXY=off`，`GOWORK=off`，`GOFLAGS=` 为空；
  - `go version go1.27.1 windows/amd64`，MINGW64（Msys），Windows 10.0.19045。
- 输出只保存在 shell 变量里，没有写固定的临时文件。Go 自身的 GOCACHE 和随机临时构建目录不在这条约束内。
- 隔离依据：被测包的两个测试文件只导入 `go/ast`、`go/parser`、`go/token`、`regexp`、`strconv`、`testing`，没有导入 governance，所以不会触发 governance 的 TestMain，也不连 DB、不起容器。
- `go build ./internal/governance`：退出码 0，没有输出。只编译，不运行任何测试或 TestMain。
- `go test -count=1 -json ./internal/governance/runnerquery_test`：退出码 0。

| Test | Action | Elapsed |
|---|---|---|
| `TestFindActiveRunTxBindsRequestedPipeline` | pass | 0 |
| `TestAdmissionRollbackGuardPrecedesLockAndDecider` | pass | 0 |
| 包 `github.com/multica-ai/multica/server/internal/governance/runnerquery_test` | pass | 0.429 秒 |

统计：run 2，pass 2，fail 0，skip 0。

## 6. 余留缺口（保留）

**交接之后的持锁副作用路径尚未审核。** 下面三处都用调用方的 `ctx` 回滚或提交，没有独立截止时间，可能存在同类存活性问题：
- `runner.go:1059-1101`（enqueue）：持锁跨越 prompt 渲染、`resolveNodeExecutor`、`checkIndependentReview`，以及走另一条池连接的 `EnqueuePipelineTask`；结束时 `defer tx.Rollback(ctx)`，从不 Commit。
- `markNodeAdmitted`：`tx.Exec` 加 `Commit(ctx)`。
- `passHumanApprovalNode`：`tx.Exec` 加 `Commit(ctx)`。

另外，“持锁期间不得写 `cr`”这个前提没有重新核实。

**AST 测试盲区：**
1. 只看源码结构，不证明行为。
2. 写死了语句下标和标识符名，等价重构也会失败。
3. “`tx.Rollback` 恰好 1 次”拦不住 `Commit`、别名变量、辅助函数或方法值这类间接调用。
4. `BeginTx`、`DecideAdmission`、`context`、`time` 只按名字匹配；没检查 `tx` 是否被遮蔽。
5. 没约束错误返回值的映射，也没约束拒绝路径返回 nil tx。
6. 依赖相对路径和工作目录；目录未纳入 git，CI 或 `scripts/test-go.sh` 会不会选中它没有核实。
7. 不覆盖交接后的路径，也不检查注释内容。注释变化本来就不在测试断言范围内。

**真实 DB 和故障注入未测：**
- `pg_locks`、`pg_stat_activity`、`AcquiredConns`；
- 服务端锁释放时机；
- panic、Goexit、nil decider、取消、TCP 挂起或网络分区；
- 从独立连接执行 `UPDATE cr … NOWAIT`；
- 依赖 DB 的回归测试（`TestAdmissionGateLockBlocksRevocation`、`TestAdmissionWaitingIsNotPersistedAsRunFailure`）。

`r.pool` 是具体类型 `*pgxpool.Pool`，换不了 fake，所以这些只能在真实 DB 上验证。

**作用域：**
- 工作区 governance 目录下还有其他未提交修改，均未复核；
- `AUTHOR-*.md` 和 `active_query_test.go` 的内容未审。

## 7. 结论

当前 `execution_admission_gate.go`（`b950f20b…16781d`）相对 `source-single-guard/`（`c0834fc2…5805680`）**只有注释变化**，可执行代码完全相同，可以编译；新注释与静态语义一致，不再过度断言锁已释放。

无 DB 复跑 2 pass、0 fail、0 skip，只证明源码结构。

客户端回滚尝试的保证来自源码结构加静态推断。服务器锁何时释放未验证。生产验收未进行。真实 backend receipt 不可得。
