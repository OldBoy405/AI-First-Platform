## 新快照限定结论：**F1/F3 的定向修补有依据，但整体仍 BLOCK**

旧报告原 verdict 不变。本轮只做静态阅读、grep 和文件字节 SHA 核对；**没有运行测试、连接数据库或操作真实 CR**。下述运行结果均为作者提供的记录，不是我的亲测。

### 1. 快照核对

按 `validation/lock-recheck-review-20261028/source-manifest.json` 的合并规则：

- base manifest 自身 SHA 一致；
- base＋overrides＋additions 后，**26/26 文件 SHA 一致**；
- 审查结束前再次核对，仍 **26/26 一致、无漂移**；
- 证据所列 643–648 迁移 SHA 与当前 checkout 一致。

这不是完整工作树冻结，也不是提交身份验证。运行记录没有固定全部 Go 源码、依赖及编译环境的 SHA，不能独立证明历史执行恰好使用了当前全部源码。

以下路径均相对 `../multica/`。

## 2. F1：指定的锁等待窗口已修，不等于提交时效保证

**源码：**`server/internal/governance/execution_control_store_state.go`

- command：`:198–203`，完成 lineage 锁及前置查询后，用 `time.Now().UTC()` 再次调用完整 verifier；
- verdict：`:472–477`，取得 cursor 锁、二次 replay 查询及链位置检查后，同样按服务端当前时钟复验；
- 复验失败均发生在本入口 INSERT 之前。没有发现二次验签仅检查签名长度、漏掉主体或误用旧 `in.Now` 的问题。

**测试：**`execution_control_command_attestation_test.go:385–480`

作者用两个真实事务持锁，通过 `pg_blocking_pids` 确认 writer **在 key 有效时已经等待**，跨过到期点才释放锁；随后要求 `ErrControlKeyInvalid`，并在失败事务内检查零目标行。夹具没有插入 stop/open command，也没有推进 cursor，因此不会被这些守卫抢先拒绝。

作者记录：
- `writer-lock-expiry-red-*`：command/verdict 均在“应拒绝却返回 nil”断言失败，不是编译错；
- `writer-lock-expiry-green-*`：33/33、skip 0，含有效签名写入正控。

**限定：**
- 正控不是“同样等待后、key 仍有效的新请求”成对正控；现有正常写入足以排除无条件拒绝，但不能宣称穷尽等待正路径。
- 零行检查未同时断言 cursor 的所有字段不变；当前源码结构支持未更新 cursor，测试本身没有完整覆盖这一点。
- `created_at` 仍使用 `in.Now` 或事务 `now()`（`:210, :486`），**不能作为实际复验时刻证明**。

### 必须保留的时序边界

二次验签后，INSERT 本身仍可能等待唯一索引：

1. T1 在 lineage A 插入 request R，尚未提交；
2. T2 在 lineage B 对 R 完成锁后复验，key 此刻有效；
3. T2 的 INSERT 等待 T1；
4. key 到期后 T1 **回滚**；
5. T2 可以继续首次插入成功。

对应位置 `:204–210, :478–486`。新测试没有覆盖该交错。

这不是本次新增漏洞，也不违背当前已收窄的“指定锁后写前复验”描述；但它说明**连 INSERT 完成时仍有效也不能笼统保证，更不能保证最终 COMMIT 时有效**。当前规格及台账明确保留提交时效限制，这一点没有冒称闭合。

## 3. F3：指定 request 约束映射正确，事务仍必须回滚

**源码：**同文件 `:211–215, :487–491`

映射严格限定：
- command：`23505 + cr_execution_control_command_pkey`
- verdict：`23505 + cr_execution_tool_verdict_request_once`

使用两个 `%w`，保留 `ErrControlStoreConflict` 和原始 `PgError`，没有吞掉其他数据库错误或把失败转成 replay 成功。

**测试：**`execution_control_command_attestation_test.go:288–381`

两条 lineage、不同 cursor/store、相同 request，签名分别合法；观察唯一约束等待后，先提交赢家，再检查业务冲突、回滚输家及唯一赢家归属。这避免了被同 lineage advisory 锁、open-slot 或 cursor 序号检查掩盖。

作者记录：
- `cross-lineage-conflict-red-*`：两子例明确得到预期约束名的原始 23505；
- `cross-lineage-conflict-green-*`：10/10、skip 0，另含精确并发重放正控。

**回滚契约成立，但不是自动恢复事务：**
- SQL 唯一约束失败后，事务已经中止；
- 映射只改变 Go 错误分类，不能继续该事务；
- 测试 `:373–375` 确实回滚。未使用 savepoint，也未证明冲突后事务仍可用，文档没有作此错误声明。
- 测试仅断言 sentinel，没有同时断言 `errors.As` 得到原始约束，也没有显式检查 `25P02`；源码支持保留错误，但这些不是已测覆盖。

**P2／归一化残余：**不能扩展为“所有同 request 并发都统一分类”。例如 verdict 同时复用 request 和 verdict ID，另取不同 lineage/store，数据库可能先报告 verdict **主键**冲突，当前分支不会映射。`648_cr_execution_control.up.sql:119,136–137` 还有其他唯一约束；现有夹具生成不同 verdict ID，排除了这一情况。这是失败关闭的接口一致性边界，不是双写或越权放行证据。

## 4. 附加发现：TestMain 仍有执行安全阻断

### **P1：显式 DATABASE_URL 不证明目标可销毁，检查放测试内部已经太晚**

**位置：**
- `server/cmd/server/integration_test.go:44–64`：只要求 URL 非空、连接成功；
- `:103–104`：setup 首先调用 cleanup；
- `:161–165`：按固定 workspace slug、用户 email 执行 DELETE；
- `:90`：之后才到 `m.Run()`；
- RUN003 仅检查 pool 非 nil（`execution_run_003_test.go:47`），并明确保留 append-only 行（`:528–530`）。

**静态可复现路径：**误把一个可写共享库 URL 显式传入，再选择 RUN003，甚至选择不匹配任何测试的正则，TestMain 仍会先清理、建 fixture。若存在同名数据，会先删除；即使不存在，也会向错误目标写入。不能靠 RUN003 开头补检查来阻止。

这是**测试执行安全阻断**，不是生产授权绕过。它不自动否定已通过外部隔离 harness 的作者运行记录。

### 最窄可行位置与校验

应放在 **TestMain 成功连接之后、`:63–64` 暴露 pool／调用 setup 之前**；拒绝时直接关闭连接并非零退出，不能再 cleanup。无需为此改生产代码。

最小只读门禁应复用 harness 已建立的身份：
1. 从实际连接读取 `current_database()`、当前/会话角色；
2. DB 名、角色名必须分别是 `aifi45_tmp_<nonce>`、`aifi45_role_<同nonce>`；
3. 数据库及角色的 `AIFI45_DISPOSABLE:<nonce>` marker 均匹配，数据库 owner 对应该角色；
4. 拒绝 superuser、createdb、createrole、bypassrls 等权限；
5. 检查失败、缺字段或查询失败均拒绝，不能只认 URL 前缀或 `ALLOW_TEST=1`。

若要绑定“本次运行”而非任意旧临时库，再由 harness 提供期望 nonce／OID，做精确比对。外部 harness 继续负责容器身份、创建与销毁；TestMain 的门禁是防误连，不应冒称能防有权伪造 marker 的操作者。测试内部检查只能作补充。

## 5. 作者证据核对与覆盖上限

已核对：
- `cp-final-cp-run-003[-a…-n]-20261028T082912Z` **15 组**均有精确目标顶层 PASS，meta 为 exit 0、fail/skip 0；
- 对应事件记录均声明隔离身份、原库未变及资源不存在；
- 上述 15 组加四组 RED/GREEN，**19 对保存的 before/after 文件字节相同**。

这支持记录内部一致性，不是我验证了实际数据库状态。15 个 CP 也不是 15 条完整 TC；RUN003 的 consumption/settlement、信任根及 producer 可信前提仍由 fixture 提供。当前文档明确保留这些限制，未见将 CP 通过直接升级为整体验收。

## 6. 保留与未核项

继续保留 **F2（P2，历史 key 到期/撤销后的重放与恢复政策）**，以及 caller-owned trust/scope、完整 B、当前 generation/cursor/fence、producer/ingest、JSONB 原信封字节和摘要互操作等开放边界。

本轮未：
- 动态复现任何交错、验证真实数据库或资源清理；
- 跑 TestMain 安全反例、完整回归或故障注入；
- 完整审全局锁图、所有调用方的回滚处理及生产接线；
- 核验 HEAD、全部依赖或运行时受保护配置。

**最终：可有限接受 F1 指定锁窗口与 F3 指定约束映射的修补；TestMain 误连防护仍为 P1 执行阻断，F2 等继续开放。本次总体 BLOCK，非 Gate3，非整体生产 PASS。**