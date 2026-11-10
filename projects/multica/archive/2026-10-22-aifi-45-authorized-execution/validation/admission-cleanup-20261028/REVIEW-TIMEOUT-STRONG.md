# AIFI-45 admission 回滚超时修复 — 最终源码语义复核与无 DB 复跑（REVIEW-TIMEOUT-STRONG）

> 性质：只读源码语义审查，外加一次独立的无 DB `go test` 复跑。审查期间未修改任何源文件或测试文件；未运行数据库、容器、governance 包的 TestMain 或 CR 操作。
> 本报告不构成执行授权或审批，也不证明真实的锁释放或服务端行为（见 §6）。
> 旧报告 `REVIEW-STRONG.md`（sha256 `44faed9f8d79b076ec062846f2212aa3fe029c2e2f08ec66d5a23ccf46aca0cf`）以及其他早期结论，只对应当时审查的旧快照（`source-before/`、`source-review/`、`source-timeout-review/`），不适用于本报告所列的最终 SHA。

## 0. 会话元数据

| 项 | 值 |
|---|---|
| session ID | `01a18576-6db4-7020-aecc-d22b4d27063b`（来自 `PI_SESSION_ID`） |
| 请求模型（环境变量自报） | `PI_PROVIDER=GBClaude`，`PI_MODEL=claude-opus-5-5` |
| 后端 receipt | **未知**：没有可核验的后端调用 receipt 或签名。上面的 provider/model 只是环境变量自报，不能作为后端证明 |
| 源码仓库 | `C:/Users/GOBAO/Downloads/AI/multica`，HEAD `81e5293adc758e392a045026cf81ec5cc1bac72d`（工作区有未提交修改；`runnerquery_test/` 目录未纳入 git） |
| pgx 版本 | `server/go.mod:18`：`github.com/jackc/pgx/v5 v5.11.0`，语义依据来自本地模块缓存中的源码 |

## 1. 被审对象 SHA（raw SHA-256，按文件字节计算，复跑前后一致）

路径都相对于 `C:/Users/GOBAO/Downloads/AI/multica/server/internal/governance/`。

| 角色 | 文件 | SHA-256 |
|---|---|---|
| 最终源码 | `execution_admission_gate.go` | `d2b6d5678914293a2d4d79c49c856aef8fdc8821fc929913a74638cfb7a4ab6a` |
| 最终 AST 测试 | `runnerquery_test/admission_cleanup_test.go` | `c82676665f2177ec4a58599804ad361cc7c52e185e69fa73f58472681ef9f977` |
| 同包另一测试（未审、未变） | `runnerquery_test/active_query_test.go` | `f535341a576aee2dae1dc0f2be8cd2acccb1e14918590e9476be485cb978afd8` |

对照快照（路径相对于本目录）：

| 快照 | 文件 | SHA-256 |
|---|---|---|
| `source-before/`（等于 HEAD 中的版本） | `execution_admission_gate.go` | `39428a0cc2641f83549aa3e90251cf6daece1e5933406156f9692fc22a68e375` |
| `source-timeout-review/` | `execution_admission_gate.go` | `865821b5ec83c02a198f8ffd9bdbd0a94f7e9daae6ac44ca357f0b7f6280fe9e` |
| `source-timeout-review/` | `admission_cleanup_test.go` | `cf50c31196ca2c48247fadc3a631684d7fce3ee76728a68c9ab231a221d3cf57` |

## 2. diff 范围

- 相对 `source-timeout-review/`，最终源码只改了两处：新增 import `"time"`（第 44 行）；guard 内部改为第 94–97 行，内容是一行注释、`cleanupCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)`、`defer cancel()`、`_ = tx.Rollback(cleanupCtx)`。
- 相对 HEAD（`git diff --stat`）：12 行新增、10 行删除，只包含 guard 前移和有界清理这两处改动。
- 相对 `source-timeout-review/`，测试只改了 guard 内部的断言：从“单条语句 `tx.Rollback(context.Background())`”改为上面三条语句的精确结构，并要求超时是 `5*time.Second`。

## 3. 最终源码语义（`decideUnderHeadLock`，第 84–127 行）

- **guard 位置**：guard 在 BeginTx 错误检查（第 86–88 行）之后，在 `lockExecutionAuthorizationHead`（第 100 行）和 `r.decider.DecideAdmission`（第 107 行）之前。lock、decider 或 hook 中发生 panic 或 `runtime.Goexit`，或者 decider 为 nil 导致 panic，都会触发回滚。guard 不 recover，panic 会照常向上传播。
- **交接**：`handed = true` 只在第 125 行设置一次，紧接着就是 `return tx, decision, nil`。成功交接时 guard 整体跳过，不会创建 timer，也不会回滚。pgx 的 Tx 不绑定 ctx（ctx 按调用逐次传入），所以 cancel `cleanupCtx` 影响不到已交出的 tx。三个调用方都只在 tx 非 nil 时才安装自己的回滚：`runner.go:1063`、`markNodeAdmitted`、`passHumanApprovalNode`。
- **拒绝路径**（第 123 行）：由 guard 回滚，返回值不变。
- **显式错误路径**（第 101、113 行）：仍然用调用方的 `ctx` 回滚。guard 里的第二次回滚返回 `ErrTxClosed`（`tx.go:221-222`）；`pgxpool.Tx.c` 已经是 nil，不会重复 Release（`pgxpool/tx.go:37-44`）。
- **取消**：调用方 ctx 被取消时，显式回滚会失败，`dbTx` 调用 `die()`（`tx.go:225-230`），Release 时 Destroy 连接（`pgxpool/conn.go:32-38`）。guard 只是空操作。
- **5 秒超时**：默认的 context 处理方式是给 socket 设截止时间（`pgconn/config.go:472-474`、`pgconn.go:3079-3081`）。截止时间到后读操作超时，触发 `asyncClose`（`pgconn.go:1613-1620`、`770-800`），后台在最多约 15 秒内关闭 socket。接着 `dbTx` 被标为 closed（`die()` 发现连接已关闭会直接返回），pool 在 Release 时 Destroy 这条连接，不会复用。如果出事时连接处于 busy，`lock()` 直接返回 conn busy（`pgconn.go:829-833`），同样走 die 加 Destroy。
- **局限（第 94 行注释准确）**：客户端截止时间只限制本 goroutine 的回滚等待和池槽占用，**不保证服务端及时释放锁**。服务端要等后端感知到 Terminate、FIN/RST 或 CancelRequest，才会中止事务、释放 `cr`/`approval_record` 上的 FOR SHARE 锁。网络分区或中间代理会让这个时间没有上界，只能靠服务端 TCP keepalive 或 `idle_in_transaction_session_timeout`（仓库里没看到全局配置）。
- **安全性**：门禁事务只做读和 FOR SHARE，从不发 COMMIT；超时或失败的连接会被 Destroy，不会复用。所以不会产生未经准入的副作用。残留的锁只会让撤销等待，属于存活性问题，不是安全问题。

以上 pgx 行为来自对源码的阅读和推断，没有在真实网络或 DB 上观测过。

## 4. 独立无 DB 复跑

- 工作目录：`C:/Users/GOBAO/Downloads/AI/multica/server`
- 命令：`go test -count=1 -json ./internal/governance/runnerquery_test`
- 环境：
  - 用 `env -u` 清除了 `DATABASE_URL` 和所有 `PG*` 变量，复跑后核对当前环境中没有匹配的变量；
  - `GOPROXY=off`，`GOWORK=off`，`GOFLAGS=` 为空；
  - `go version go1.27.1 windows/amd64`，MINGW64（Msys）shell，Windows 10.0.19045。
- 输出只保存在 shell 变量里，没有写固定的临时文件。Go 自身的 GOCACHE 和随机临时构建目录不在这条约束内。
- 隔离依据：这个包的两个测试文件只导入 `go/ast`、`go/parser`、`go/token`、`regexp`、`strconv`、`testing`，没有导入 governance，所以不会触发 governance 的 TestMain，也不连 DB。
- 结果：退出码 0。

| Test | Action | Elapsed |
|---|---|---|
| `TestAdmissionRollbackGuardPrecedesLockAndDecider` | pass | 0 |
| `TestFindActiveRunTxBindsRequestedPipeline` | pass | 0 |
| 包 `.../internal/governance/runnerquery_test` | pass | 0.4 秒 |

统计：run 2，pass 2，fail 0，skip 0。

## 5. AST 测试：已覆盖与脆性

已覆盖：
- 函数体第 0 条语句是 `tx, err := …BeginTx(…)`，第 1 条是 `if err != nil { return nil, _, err }`；
- 第 2 条是 `handed := false`，第 3 条是 `defer func(){ if !handed { cleanupCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second); defer cancel(); _ = tx.Rollback(cleanupCtx) } }()`；
- guard 位于第一次 lock 调用和第一次 `DecideAdmission` 调用之前；
- `handed` 恰好被赋值两次，倒数第二条是 `handed = true`，最后一条是 `return tx, _, nil`。

脆性与缺口（保留）：
1. **只看源码结构**：不执行事务，不证明行为。测试第 25 行自己也写明了这一点。
2. **太脆**：写死了语句下标和标识符名（`tx`、`err`、`handed`、`cleanupCtx`、`cancel`）。等价重构也会让它失败，例如在 BeginTx 之前加一个 decider 判空、改变量名、把超时改成具名常量。
3. **匹配仍有宽松处**：
   - `BeginTx` 和 `DecideAdmission` 只按方法名匹配，不管接收者；
   - `context`、`time` 只按标识符匹配，没校验 import 的路径或别名；
   - 没检查 `tx` 是否被遮蔽（shadowing）。
4. **未约束显式错误路径的回滚和调用方 ctx**：有 guard 兜底，影响很小。
5. **依赖运行环境**：测试用相对路径 `../execution_admission_gate.go`，依赖 `go test` 把工作目录设在包目录。`scripts/test-go.sh` 会不会选中这个未纳入 git 的目录，没有核实。

## 6. 未验证事项（明确不声称）

- 真实 PostgreSQL 上的锁获取与释放：`pg_locks`、`pg_stat_activity` 中的 `idle in transaction`、`pool.Stat().AcquiredConns()` 是否回到 0。
- 服务端锁的释放时机：超时、断连、网络分区或代理场景下，后端什么时候中止事务。
- 故障注入：在 decider 或 hook 中注入 panic（外层 recover）、`runtime.Goexit`、nil decider、中途取消 ctx，以及用代理丢包或暂停 TCP 来验证 5 秒超时后连接被 Destroy、从独立连接执行 `UPDATE cr … NOWAIT` 能成功并影响 1 行。`r.pool` 是具体类型 `*pgxpool.Pool`，换不了 fake，所以这些都需要真实 DB。
- 依赖 DB 的回归测试，例如 `TestAdmissionGateLockBlocksRevocation`、`TestAdmissionWaitingIsNotPersistedAsRunFailure`，本次没有运行。

## 7. 作用域局限

- 只审了 `execution_admission_gate.go` 中的 `decideUnderHeadLock` 及其三个调用方的事务所有权，另外读了 pgx v5.11.0 中的相关源码。
- 工作区 `server/internal/governance/` 下还有其他未提交修改，例如 `execution_control_store_state.go`、`execution_notice.go`、`execution_deployment.go` 和若干测试文件，**均未复核**。
- `active_query_test.go` 只是作为同包测试被执行，内容没有审查。
- 没有审查 `AUTHOR-EXECUTION.md`、`AUTHOR-TIMEOUT.md` 的内容。

## 8. 结论

最终源码（`d2b6d567…a4ab6a`）的事务所有权语义正确：guard 在 BeginTx 成功后立即安装，覆盖 panic、Goexit、拒绝和错误路径，不影响成功交接；5 秒有界清理和 pgx 5.11 的 die/Destroy 路径相容。局限在于它只限制客户端，不保证服务端及时释放锁。AST 测试（`c8267666…f9f977`）在本环境无 DB 复跑结果为 2 pass、0 skip，但它只证明源码结构，不能替代真实 DB 和故障注入证据。
