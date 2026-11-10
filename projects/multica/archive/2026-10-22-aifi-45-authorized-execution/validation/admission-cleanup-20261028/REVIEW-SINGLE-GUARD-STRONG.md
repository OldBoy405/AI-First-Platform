# AIFI-45 admission 单一 guard 清理 — 独立复核与无 DB 复跑（REVIEW-SINGLE-GUARD-STRONG）

> 性质：只读源码语义审查，外加一次独立的无 DB `go test` 复跑。审查期间未修改任何源文件或测试文件；未运行数据库、容器、governance 包的 TestMain 或 CR 操作。
> 本报告不构成执行授权或审批。文中关于 pgx/pgxpool/puddle 的行为都是**对本地模块源码的静态推断**，不证明真实 PostgreSQL、网络或连接池的运行时行为。
> 旧报告保持原样，只代表各自对应的旧快照，不适用于本报告的 SHA：
> - `REVIEW-STRONG.md`（sha256 `44faed9f8d79b076ec062846f2212aa3fe029c2e2f08ec66d5a23ccf46aca0cf`）
> - `REVIEW-TIMEOUT-STRONG.md`（sha256 `3cbcc62c3e7b0a48c66528a6c8f277cd0bf795c7e0f3f5fb8ccf06017f6d4fee`），只对应源码 `d2b6d567…` 与测试 `c8267666…`

## 0. 会话元数据

| 项 | 值 |
|---|---|
| session ID | `01a18576-6db4-7020-aecc-d22b4d27063b`（来自 `PI_SESSION_ID`） |
| 请求模型（环境变量自报） | `PI_PROVIDER=GBClaude`，`PI_MODEL=claude-opus-5-5` |
| 后端 receipt | **未知**：没有可核验的后端调用 receipt 或签名。上面的 provider/model 只是自报，不能作为后端证明 |
| 源码仓库 | `C:/Users/GOBAO/Downloads/AI/multica`，HEAD `81e5293adc758e392a045026cf81ec5cc1bac72d`（工作区有未提交修改；`server/internal/governance/runnerquery_test/` 目录未纳入 git） |
| 依赖版本 | `github.com/jackc/pgx/v5 v5.11.0`（`server/go.mod:18`），`github.com/jackc/puddle/v2 v2.2.2`（`go.mod:61`，indirect） |
| 作者说明（只记录 SHA，内容未审） | `AUTHOR-SINGLE-GUARD.md` sha256 `daff082809ecc4a568ab6570aef70002420d5eba5db56527ba6237ba76fba059` |

## 1. SHA（raw SHA-256，复跑前后一致）

路径都相对于 `C:/Users/GOBAO/Downloads/AI/multica/server/internal/governance/`。

| 角色 | 文件 | SHA-256 |
|---|---|---|
| 当前源码 | `execution_admission_gate.go` | `c0834fc2fc34d4cc3b3fe7cf663ea0a5169b11a37c653f71a823f9c253805680` |
| 当前 AST 测试 | `runnerquery_test/admission_cleanup_test.go` | `7eb49459ac4709eea9f326fba834aff88f99a471a5aa6ce2dae553aebb8150eb` |
| 同包测试（未变、内容未审） | `runnerquery_test/active_query_test.go` | `f535341a576aee2dae1dc0f2be8cd2acccb1e14918590e9476be485cb978afd8` |
| 快照 `source-timeout-final/` | `execution_admission_gate.go` | `d2b6d5678914293a2d4d79c49c856aef8fdc8821fc929913a74638cfb7a4ab6a` |
| 快照 `source-timeout-final/` | `admission_cleanup_test.go` | `c82676665f2177ec4a58599804ad361cc7c52e185e69fa73f58472681ef9f977` |

## 2. diff 范围（相对 `source-timeout-final/`）

- 源码：只删除了两行 `_ = tx.Rollback(ctx)`，分别在 lock 失败分支和 decider 失败分支（快照第 101、113 行），没有其他改动。相对 HEAD 为 12 行新增、12 行删除。
- 测试：只新增一个计数，用 `ast.Inspect` 统计整个函数体内的 `tx.Rollback` 调用，要求恰好 1 次（即只在 guard 中）。

当前 `decideUnderHeadLock` 位于第 84–125 行：
- 第 85–88 行：BeginTx 和错误检查；
- 第 91–99 行：`handed` 与 5 秒 guard（`context.WithTimeout(context.Background(), 5*time.Second)`，`defer cancel()`，`tx.Rollback(cleanupCtx)`）；
- 第 100–105 行：lock；
- 第 106–113 行：decider；
- 第 114–116 行：hook；
- 第 117–122 行：拒绝路径；
- 第 123–124 行：交接。

## 3. 被修复的存活性洞（静态推断）

旧代码在 defer 之前用调用方的 `ctx` 执行显式回滚：
- `ctx` 不是 Background 但没有截止时间时，pgconn 会监听它（`pgconn.go:1218-1228`），但它不会 Done；
- `ctx` 就是 Background 时，pgconn 根本不监听。

两种情况下，网络挂住时回滚都可能无期限阻塞。删除后，所有没交接出去的路径都只走 guard，回滚等待受 5 秒客户端截止时间约束。

## 4. 删除的影响

### 4.1 错误返回值：不变（源码可证）
- lock 返回 `pgx.ErrNoRows` 时，映射为 `AdmissionDecision{Reason: HeadUnavailable}` 和 nil error（第 101–102 行）；
- 其他 lock 错误原样返回（第 104 行）；
- decider 错误原样返回（第 112 行）。

回滚错误以前和现在都被丢弃。`errors.Is` 现在在回滚之前执行，但 `err` 只是一个值，不受回滚影响。

### 4.2 锁释放顺序：已纠正摘要中的过度断言
- Go 的 defer 在 return 表达式求值之后、控制权回到调用方之前执行。所以 guard 在调用方继续执行之前，**完成一次回滚尝试**。
- **只有连接健康、并且 ROLLBACK 在服务端成功执行时**，才能说 `cr`/`approval_record` 上的 FOR SHARE 锁在调用方继续执行之前已经释放。
- **超时、网络分区、连接 busy、连接已关闭**时，guard 只是在 return 之前完成了尝试：客户端标记连接关闭，并把它交给 Destroy。**服务端锁什么时候释放未知**，取决于后端何时感知到 Terminate、FIN/RST 或 CancelRequest，必要时要靠服务端 TCP keepalive 或 `idle_in_transaction_session_timeout`（仓库里没看到全局配置）；中间代理也可能进一步改变行为。
- 拒绝路径之后调用方用另一条池连接写 `waitAdmission`。只有在上一条“健康且成功回滚”的条件下，才能说这一步发生在锁释放之后。

### 4.3 `r.pool` 资源与连接状态（静态推断）
- **连接健康，错误是 PgError 或 ErrNoRows**：guard 用新的 5 秒 ctx 执行 ROLLBACK，成功后连接放回池里复用，和以前一样。在 aborted 状态下 ROLLBACK 也是合法的。
- **调用方 ctx 已取消，但连接仍然健康（行为变化）**：
  - 以前：`Rollback(ctx)` 立即返回 context 已结束，`dbTx.Rollback` 调用 `die()`（`tx.go:225-230`），Release 时 Destroy（`pgxpool/conn.go:32-38`）。
  - 现在：guard 会真的发出 ROLLBACK；成功时服务端明确释放锁，连接可以复用。
- **查询已被取消或超时打断**：连接已经 `asyncClose`，guard 调用 `lock()` 时返回 conn closed（`pgconn.go:829-835`），`die()` 成为空操作，Release 时 Destroy，和以前一样。
- **连接挂住**：5 秒截止时间触发 socket 截止时间（`pgconn/config.go:472-474`、`pgconn.go:3079-3081`），读超时后 `asyncClose`（`pgconn.go:1613-1620`、`770-800`），然后 Release 时 Destroy。
- **池槽与后台析构没有绝对上界**：
  - puddle 的 `Destroy` 是异步的（`puddle pool.go:72-77`），它要等 pgxpool 析构函数返回后才释放信号量（`puddle pool.go:687-695`）；
  - 析构函数最多等待 15 秒的 `CleanupDone`（`pgxpool/pool.go:314-326`）；
  - `asyncClose` 的后台关闭也设了 15 秒截止时间。

  因此推断：调用方的回滚等待大约受 5 秒约束；池槽在 Destroy 之后还可能在后台继续被占用，最多约 15 秒。**但 5 秒和 15 秒都不是绝对上界**：调度延迟、tracer 或 beforeClose 钩子、操作系统 socket 行为、CancelRequest 的拨号路径，都可能让实际时间偏离这个推断。以上没有在真实环境里测量过。

### 4.4 panic 与 Goexit：不变
由 guard 尝试回滚，guard 不 recover，panic 照常向上传播。nil decider 导致的 panic 也一样。三个调用方今天都有 decider 判空，这条路径走不到。

### 4.5 安全性（推断）
门禁事务只做读和 FOR SHARE，从不 COMMIT；失败或超时的连接会被 Destroy，不会复用。所以不会产生未经准入的副作用。残留的服务端锁只会让撤销等待，属于存活性问题。

## 5. 独立无 DB 复跑

- 工作目录：`C:/Users/GOBAO/Downloads/AI/multica/server`
- 命令：`go test -count=1 -json ./internal/governance/runnerquery_test`
- 环境：
  - 用 `env -u` 清除了 `DATABASE_URL` 和所有 `PG*` 变量，运行时核对为 0 个；
  - `GOPROXY=off`，`GOWORK=off`，`GOFLAGS=` 为空；
  - go1.27.1 windows/amd64，MINGW64（Msys），Windows 10.0.19045。
- 输出只保存在 shell 变量里，没有写固定的临时文件。Go 自身的 GOCACHE 和随机临时构建目录不在这条约束内。
- 隔离依据：两个测试文件只导入 `go/ast`、`go/parser`、`go/token`、`regexp`、`strconv`、`testing`，没有导入 governance，所以不会触发 governance 的 TestMain，也不连 DB、不起容器。
- 结果：退出码 0。

| Test | Action | Elapsed |
|---|---|---|
| `TestFindActiveRunTxBindsRequestedPipeline` | pass | 0 |
| `TestAdmissionRollbackGuardPrecedesLockAndDecider` | pass | 0 |
| 包 `.../internal/governance/runnerquery_test` | pass | 0.395 秒 |

统计：run 2，pass 2，fail 0，skip 0。

## 6. 交接之后的持锁副作用路径（尚未审核）

交接之后，tx 和锁归调用方。下面这些路径**本轮没有审核**，而且从表面看都用调用方的 `ctx` 回滚或提交，没有独立的截止时间，**可能存在同类存活性问题**：

- `runner.go:1059-1101`（enqueue）：持锁跨越了 `renderCorePrompt`、`reviewFeedback`、`resolveNodeExecutor`、`checkIndependentReview`，以及走另一条池连接的 `r.tasks.EnqueuePipelineTask`。这个 tx 从不 Commit，结束时执行 `defer tx.Rollback(ctx)`。
- `execution_admission_gate.go` 中的 `markNodeAdmitted`：先 `tx.Exec(ctx, UPDATE pipeline_node_run …)`，再 `tx.Commit(ctx)`，加上 `defer tx.Rollback(ctx)`。
- `execution_admission_gate.go` 中的 `passHumanApprovalNode`：先 `tx.Exec(ctx, stmt …)`，再 `tx.Commit(ctx)`，加上 `defer tx.Rollback(ctx)`。
- 门禁注释里的前提“持锁期间从这里可达的代码不得写 `cr`”（否则会和自己持有的锁形成数据库无法检测的应用层死锁），本轮没有重新核实。
- 这些路径的回滚和提交是否需要有界 ctx，以及持锁期间做外部工作对撤销的影响，都需要单独审核。

## 7. AST 测试盲区

1. 只看源码结构，不执行事务，不证明行为。
2. 写死了语句下标和标识符名（`tx`、`err`、`handed`、`cleanupCtx`、`cancel`）。等价重构也会失败，例如在 BeginTx 之前加 decider 判空、改变量名、把超时改成具名常量。
3. “`tx.Rollback` 恰好 1 次”这个计数只认接收者叫 `tx` 的选择器调用。拦不住的情况包括：`Commit`、通过别名变量调用 `Rollback`、把回滚包进辅助函数、通过方法值间接调用。
4. `BeginTx` 和 `DecideAdmission` 只按方法名匹配，不管接收者；`context`、`time` 只按标识符匹配，没校验 import 路径或别名；没检查 `tx` 是否被遮蔽。
5. 没约束错误返回值的映射（如 `ErrNoRows → HeadUnavailable`），也没约束拒绝路径返回 nil tx。
6. 依赖相对路径 `../execution_admission_gate.go` 和 `go test` 的工作目录。目录未纳入 git，`scripts/test-go.sh` 或 CI 会不会选中它，没有核实。
7. 完全不覆盖第 6 节列出的交接后路径。

## 8. 未验证事项（明确不声称）

- 真实 PostgreSQL 上的锁获取与释放：`pg_locks`、`pg_stat_activity` 中的 `idle in transaction`、`pool.Stat().AcquiredConns()`。
- 服务端锁的释放时机：健康回滚、超时、断连、网络分区、代理场景。
- 5 秒客户端截止时间和约 15 秒后台析构的实测耗时。
- 故障注入：在 decider 或 hook 中注入 panic（外层 recover）、`runtime.Goexit`、nil decider；中途取消 ctx；用代理丢包或暂停 TCP 制造挂起；从独立连接执行 `UPDATE cr … NOWAIT` 观察何时能成功。`r.pool` 是具体类型 `*pgxpool.Pool`，换不了 fake，所以这些都需要真实 DB。
- 依赖 DB 的回归测试（如 `TestAdmissionGateLockBlocksRevocation`、`TestAdmissionWaitingIsNotPersistedAsRunFailure`），本次没有运行。

## 9. 作用域局限

- 只审了 `decideUnderHeadLock` 本身，以及相关的 pgx v5.11.0、puddle v2.2.2 源码片段。
- 工作区 `server/internal/governance/` 下还有其他未提交修改，例如 `execution_control_store_state.go`、`execution_notice.go`、`execution_deployment.go` 和若干测试文件，**均未复核**。
- 没有审查 `AUTHOR-*.md` 的内容和 `active_query_test.go` 的内容。

## 10. 结论

当前源码（`c0834fc2…5805680`）删除两条显式 `Rollback(ctx)` 后，错误返回值不变，所有没交接出去的路径都由 5 秒 guard 统一清理，修掉了调用方 ctx 没有截止时间时显式回滚可能无期限阻塞的问题。

但要注意三点：
- 只有连接健康且 ROLLBACK 成功时，才能说锁在调用方继续执行前已经释放；超时或分区时，guard 只完成了尝试，服务端何时释放锁未知；
- 5 秒和 15 秒都不是池槽或后台析构的绝对上界；
- pgx 相关结论全部来自静态推断。

AST 测试（`7eb49459…150eb`）无 DB 复跑结果为 2 pass、0 skip，只证明源码结构。交接后的持锁路径、真实 DB 行为和故障注入都还没有验证。
