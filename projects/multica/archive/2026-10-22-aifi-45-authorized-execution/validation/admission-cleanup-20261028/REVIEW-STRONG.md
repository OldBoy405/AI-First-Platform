# AIFI-45 admission 回滚与测试 — 只读静态复核归档（REVIEW-STRONG）

> 性质：**仅静态源码审查**。审查期间未执行任何数据库、容器、`go test`、CR 操作，未修改任何源文件。
> 本报告**不声称**任何测试已运行或通过，**不构成**执行授权或审批。

## 0. 审查会话元数据

| 项 | 值 |
|---|---|
| session ID | `01a18580-f785-7020-aecc-d232b5aab89c`（来自 `PI_SESSION_ID`） |
| 模型（环境变量自报） | `PI_PROVIDER=GBClaude`，`PI_MODEL=claude-opus-5-5` |
| 模型后端 receipt | **未知**——没有可核验的后端调用 receipt 或签名；上面的 provider/model 只是环境变量自报，不能作为后端证明 |
| 源码仓库 | `C:/Users/GOBAO/Downloads/AI/multica`，HEAD `81e5293adc758e392a045026cf81ec5cc1bac72d`（工作区有未提交修改） |
| 审查轮次 | 第 1 轮：旧 DB 测试；第 2 轮：最终 DB 测试和增强 AST 测试 |

## 1. 被审对象 SHA（raw SHA-256，按文件字节计算）

路径都相对于 `server/internal/governance/`。

| 类别 | 文件 | SHA-256 | 备注 |
|---|---|---|---|
| 生产源码（修复后，工作区） | `execution_admission_gate.go` | `865821b5ec83c02a198f8ffd9bdbd0a94f7e9daae6ac44ca357f0b7f6280fe9e` | 回滚 defer 移到加锁和 decider **之前** |
| 生产源码（旧实现，HEAD blob） | `git show HEAD:…/execution_admission_gate.go` | `39428a0cc2641f83549aa3e90251cf6daece1e5933406156f9692fc22a68e375` | 由 `git show` 输出计算；defer 位于 decider **之后** |
| 生产源码（依赖） | `execution_head_lock.go` | `f86d5551bb668cf3e726146c4bd62669f038ec327df19a61b34b61b5cd936426` | 对 `cr` 行和 `approval_record` 行加 `FOR SHARE` |
| 旧 DB 测试（第 1 轮） | `execution_admission_cleanup_test.go` | `a6b6b540a43b1f7a0d3493bdde4e88c276d1f0affabd6fafafeee00f48e74851` | 已被替换，当前工作区中不存在 |
| 最终 DB 测试（第 2 轮） | `execution_admission_cleanup_test.go` | `50df2912530ba2f494afe46f0f8f28f1fc1e070150b797bb001869b56f951a2b` | 当前工作区版本 |
| 增强 AST 测试（第 2 轮） | `runnerquery_test/admission_cleanup_test.go` | `cf50c31196ca2c48247fadc3a631684d7fce3ee76728a68c9ab231a221d3cf57` | 只做源码级检查 |
| 共享 fixture / helper | `execution_admission_lock_test.go` | `a10ec099ae603f4d9ff6e02acd61e6966fc41587f0b0975dbd0a8970ba0a1d1e` | `newAdmissionLockFixture`、`lockNotAvailable`、`probeFromAnotherConnection` |
| 共享 TestMain | `crsync_test.go` | `cdc344a7849fc6f67ff44e74260d70d5afde6bb822488af1156c76ba423b3f58` | 要求 `DATABASE_URL`；持 advisory lease；结束时清理 |

## 2. 第 1 轮：旧 DB 测试（a6b6b540…）静态结论

- **旧实现能否先报 55P03**：能。新旧两版都在调用 decider 之前加 `FOR SHARE`，另一连接上的 `UPDATE` 带 300ms `lock_timeout`，会因 FOR SHARE 与 NO KEY UPDATE 冲突而报 55P03。
- **旧实现的 RED**：泄漏的事务还持锁，panic 后的 UPDATE 等 300ms 后报错，测试 Fatalf。
  - **缺口**：只判断 `err != nil`，不区分 55P03 和其他错误，需要人工从日志确认。
- **清理顺序**：函数内 defer 先执行；之后 `t.Cleanup` 后进先出，先回滚 `decider.tx`，再删 fixture，删除不会被泄漏的锁卡住。
- **preserved DB**：测试只用 `testPool`（`DATABASE_URL`），是否误用 preserved DB 完全取决于外部注入。
- **新实现**：panic 时 defer 回滚事务，之后 UPDATE 成功并要求更新 1 行作为正控。
- **当时的无界点**：
  - 探针 `Acquire` 用 `context.Background()`；
  - decider 内调用 `t.Fatalf` 会触发 Goexit；
  - cleanup 里的 Rollback、`SET DEFAULT`、fixture DELETE 都不设超时。

## 3. 第 2 轮：最终 DB 测试（50df2912…）静态结论

### 3.1 第 1 轮缺口的处理情况
| 缺口 | 最终版处理 | 结论 |
|---|---|---|
| 后验错误不分类 | 55P03 报 "still blocked"；其他错误报 "inconclusive"；没有错误但行数≠1 时报行数错误 | 已解决，RED 有专门文案 |
| 探针 `Acquire` 无界 | `Acquire`、`SET`、`UPDATE` 共用 3s 上下文，另设 300ms `lock_timeout` | 已解决 |
| decider 内 `t.Fatalf` / Goexit | decider 不再持有 `t`，错误写进 `probeErr`，经 `lockNotAvailable` 判定后失败 | 已解决 |
| cleanup Rollback 无界 | 限时 3s；超时会导致 pgx 关闭连接，服务端在断开时释放锁 | 已解决 |
| 恢复 `lock_timeout` 失败后污染连接池 | 恢复失败时先在 3s 内关闭底层连接再 `Release`，连接池会丢弃它 | 已解决 |

### 3.2 旧实现与新实现的预期路径（静态推断，非运行结果）
- **旧实现（HEAD blob 39428a0c…）**：
  - panic 前的探针报 55P03；
  - 泄漏的事务继续持锁，后验 UPDATE 报 55P03，在 "still blocked" 处 Fatalf；
  - 清理先回滚泄漏的事务，再删 fixture；
  - 只占 2 个连接，pgxpool 默认 MaxConns ≥ 4。
- **新实现（865821b5…）**：
  - panic 往上传的过程中 defer 先回滚，测试的 `recover` 拿到 panic；
  - 之后 UPDATE 成功，并要求 `RowsAffected()==1`（唯一 `crID`），作为正控。

### 3.3 仍然存在的无界点（保留）
1. **共享 fixture**：`newAdmissionLockFixture` 和 `testUserID` 的 INSERT/UPDATE 都用 `context.Background()`。`UPDATE workspace … issue_counter` 和 user/member upsert 可能被其他会话的行锁卡住；advisory lease 只能约束走同一 TestMain 的进程。
2. **fixture 清理**：4 条 DELETE 不设超时，也没有 `lock_timeout`。如果限时 Rollback 失败，同时服务端迟迟没发现连接断开，就可能一直等。
3. **生产代码里的回滚**：`decideUnderHeadLock` 以 `context.Background()` 被调用，`BeginTx`、`FOR SHARE` 加锁，以及 defer 里的 `tx.Rollback(context.Background())` 都没有上限。新实现中如果这次 Rollback 卡住，panic 传不出来，只能靠 `go test -timeout` 兜底。AST 测试还**强制**使用这种 Background 写法。
4. **本文件之外**：TestMain 结束时的 `cleanup`，以及 lock 测试里 `probeFromAnotherConnection` 的 `Acquire`，仍然不设上限。

### 3.4 证据缺口和覆盖限制（保留）
- 只验证了 `cr` 行锁的释放；`approval_record` 行的 `FOR SHARE` 释放是"同一事务回滚"的推断，测试没有探针。
- 没有断言 `decider.tx` 已关闭（例如第二次 Rollback 应返回 `ErrTxClosed`）。
- 动态上只覆盖 decider 里的 **panic**。以下情况都没有用数据库验证：
  - Goexit；
  - `ExecutionAdmissionTestHook` 里的 panic；
  - `lockExecutionAuthorizationHead` 期间的 panic；
  - 事务交出后（`handed=true`）调用方再 panic。
- 如果 `recover` 拿到的不是预期值，测试会重新 panic，整个测试二进制崩溃（cleanup 先跑，但其他测试结果会丢失）。
- 正控 UPDATE 会真的把 `head_id` 置为 NULL 并提交；没有检查 `cr` 表上的触发器或约束。

## 4. 增强 AST 测试（cf50c31…）的能力边界

**能证明（仅限 `decideUnderHeadLock` 的源码结构）**：
- 前几条语句依次为：`BeginTx`，立即检查 `err != nil` 并返回 nil 事务，`handed := false`，然后是 `defer func(){ if !handed { _ = tx.Rollback(context.Background()) } }()`。
- 这个 defer 写在第一次调用 `lockExecutionAuthorizationHead` 和 `DecideAdmission` 之前。
- `handed` 只被赋值 2 次，`handed = true` 是倒数第二条语句，最后一条是 `return tx, …, nil`。
- 不依赖数据库，`runnerquery_test` 包里没有 TestMain。

**源级局限（保留）**：
- 不证明运行时事务真的回滚、锁真的释放（测试注释自己写明了）。
- 按名字匹配，不做类型和作用域分析，因此查不出：
  - `tx` 被重新声明遮蔽；
  - `context` 是别名导入；
  - `DecideAdmission` 是别的同名方法；
  - 通过 `p := &handed` 间接修改；
  - 只比较代码位置，不做控制流分析。
- 不检查拒绝路径是否返回 nil 事务、测试钩子的位置、Rollback 是否有上限；它反而把不设上限的 `context.Background()` 固定了下来。
- 依赖固定语句下标和相对路径 `../execution_admission_gate.go`，重构时容易误报失败。

## 5. 执行先决条件（不是授权）

如果有权限的人以后决定执行，静态上建议满足：
1. 通过 `scripts/aifi45-db/run.mjs` 注入**一次性** `DATABASE_URL`（这个脚本本次没有审查）。不得指向 preserved 或共享库：TestMain 会删除 `governance-tests` 工作区下的所有 `cr`，以及 `cr_id LIKE 'CR-9%'` 的行。
2. 设置 `go test -timeout`，兜住 §3.3 的无界路径。
3. 需要的证据：
   - 旧实现 RED 必须是 "post-panic update still blocked with SQLSTATE 55P03"；
   - 新实现 GREEN 必须是 1 行正控；
   - "inconclusive" 或行数≠1 都**不能**算作证据。
4. 可选加固：
   - 给 fixture 和清理加上下文超时与 `lock_timeout`；
   - 补 Goexit 或测试钩子 panic 的数据库探针；
   - 补 `approval_record` 行锁释放的探针。

## 6. 声明

- 本报告**没有**运行任何数据库、容器、测试或 CR，§2–§4 都是静态推断，不是实际结果。
- 本报告**不是**执行授权或审批。
- 模型后端 receipt **未知**。
- 归档时只新建了本文件，没有修改任何源码或测试文件。
