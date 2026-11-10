# 通知身份复用 + 三类事实接线（2026-11-09）

> **状态：实现及验证未完成；合同修订待审。** 下述是现有代码的有限事实，不代表 SC-NTF-001～007 已通过、Gate 2 已批准修订或 Gate 3 已完成。2026-11-09 后的独立复核发现下列生产接线与恢复缺口。

## 1. M009 修订方向：不新增列/索引/迁移

**拟议方向**：以既有 `cr_execution_notice (workspace_id, dedupe_key)` 唯一约束承担通知身份，不实施 `design.md §5` 的 `inbox_item.details.execution_notification_key` + partial UNIQUE 方案。原设计仍是已批准合同，修订尚未获批准。

**依据**（读代码得出，不是数据库普查）：

- notice 与 Inbox 1:1，`inbox_item_id` 存在 notice 行上；
- `NoticeDedupeKey` 已包含 CR、cause、evidence digest、audience、规范化接收者；
- `DeliverNoticeTx` 在调用方事务内写 notice + Inbox；提交后 `BroadcastNotice` 标 delivered；
- `RecoverPendingNotices` 按 notice 行恢复，不依赖 Inbox details。

**旧键兼容**：2026-11-09 接线前，仓库内 `DeliverNotice*` 无已知生产调用方；这不是数据库普查，也不能证明不存在旧行。若实际发现旧键数据，保留原数据并单独裁定重放和兼容策略；目前未实现双读、双写或回填。

**未做**：不改 `646_cr_execution_notice`，不加列、不加索引、不加迁移。

## 2. NTF 生产接线

当前代码在以下状态分支尝试写入通知：业务状态先提交，通知在独立事务中写入。**这不是三类真实业务事实均已覆盖的证明**：

| 事实 | 写入点 | cause → audience | 收件人 |
|---|---|---|---|
| `reconcileApproval` 将运行改为 `waiting_approval` | `runner.go#reconcileApproval` | `approval-required` → authorizer | `pipeline_run.started_by`（成员校验失败即不投，尚未证明此人具有授权权力） |
| `failRun` 将运行转为 `failed` | `runner.go#failRun` | 部分环境/绑定错误码 → maintainer；其余 → `run-failed` → authorizer | 同上（maintainer 取 owner/admin）；并非所有失败都代表有界恢复耗尽 |
| 交付完成（`reconcileWriteback`） | `runner_code.go` | `delivered` → authorizer | 同上 |

- 复用 `DeliverNoticeTx`（notice+Inbox 原子）、`BroadcastNotice`（提交后广播并标 delivered）。
- `StartupScan` 在扫描运行前调用 `recoverPendingNotices`：按 workspace 查 `state='pending'`，用 `RecoverPendingNotices` 以**原 Inbox ID** 重投，不新建调度器。
- 通知路径不向业务调用者返回错误；部分失败记 `slog.Warn`，身份查询失败等路径可能直接跳过。它不回滚已提交事实、不重签授权、不重派 writer。
- 失败接线将**错误码的摘要**作为 evidence digest：相同 CR、原因、接收者及错误码会去重，错误码变化会产生新键。这不能证明同码新失败或重要证据变化不被吞掉；审批拒绝等也走 `failRun`，不应据此宣称恢复耗尽。
- 广播后的 `delivered` 更新带 `state='pending'` 谓词；`StartupScan` 即使运行扫描失败也执行通知恢复。
- 消费端未提交改动将真实 `cr_execution_notice` 类型纳入已有 workspace + Inbox ID 幂等路径，保留原 details 标记的兼容行为。标记限于当前 QueryClient，会在清理时移除；本次 claim 专属句柄防止旧异步失败释放新的 claim。它不保证跨会话或实际 OS 投递。

## 3. 证据

先前一次性 PG 命令使用 tmpfs、随机端口/密码及 `go run ./cmd/migrate up`，并在退出时清理其命名容器；命令**未显式关闭容器网络**，现有记录不能证明符合已授权的无外网隔离条件，故以下只记作当时的测试输出，不作为合规隔离环境的验收证据：

```
go test ./internal/governance -run 'TestFailRun|TestUnroutableNotice|TestPendingNotice|TestFailureDigest'
--- PASS: TestFailRunWritesOneDeliveredNotice
--- PASS: TestFailRunKeepsFactsSeparatePerCRAndAudience
--- PASS: TestUnroutableNoticeLeavesTheFailureStanding
--- PASS: TestPendingNoticeIsFinishedOnTheSameInboxID
--- PASS: TestFailureDigestSeparatesChangedCodes
ok  github.com/multica-ai/multica/server/internal/governance
```

同一组测试曾在干净工作树的 `0d0b186f4` 重跑通过；它们没有覆盖后续提交 `0f786836b` 的真实数据库启动恢复。`go build ./...`、`go vet ./internal/governance ./cmd/server` 在 `0f786836b` 干净工作树通过。

五个测试仅覆盖测试直接构造的失败事实、不同 CR、模拟的维护类错误码、不可解析收件人、pending 广播恢复以及错误码变化；**不证明**三类事实的完整生产链、真实根因分流、重要证据变化、数据库并发或写前故障恢复。

原 `server/internal/governance/execution_notice_test.go` 的 `TestTC_NTF_001`～`007` 仍为组件级资产；其中 `TestTC_NTF_007` 的 `before-inbox` 分支断言 notice 和 Inbox 均回滚为零，但没有从已提交的真实业务事实重建通知，也没有重试该分支。测试名称或其他分支的 pending 恢复结果不能替代写前故障验收。原 test-plan 所列 `server/cmd/server/execution_notifications_test.go` 当前未找到，真实入口覆盖仍待补。

消费端未提交改动：早期 `NODE_ENV=test pnpm --filter @multica/core exec vitest run inbox/ws-updaters.test.ts realtime/use-realtime-sync-inbox.test.tsx` 为 48/48；后续会话生命周期候选修复的 realtime、WS、auth、inbox 与 preference 聚焦回归初次为 21 文件／314 例通过；独立复核发现同步清理、刷新续体和清理异常路径竞态后，曾有 13 文件／241 例通过；因后续复核发现目标锁会阻断新会话注销而撤回该机制，撤回后、后续认证代际改动前的其他聚焦回归为 12 文件／229 例通过，`platform/session-cleanup.test.ts` 有 2 例失败、7 例通过，无 skip；当时 core typecheck 和相关改动文件 ESLint 通过，这些旧结果不代表当前工作树。当前补丁不可作为完成或交付证据。测试使用真实服务器载荷形状、真实认证 store 和模拟 socket/通知桥，覆盖同 ID 重投、不同 ID/工作区、超过默认缓存寿命、旧回调迟到及会话切换，不证明真实 OS 通知或跨会话去重。运行时继承 `NODE_ENV=production` 会使 React 测试的 `act` 不可用；以上结果使用测试环境。

## 4. 明确未证明 / 残留

- **通知行写入前故障不恢复**：事实已提交、notice 行未写时，没有 pending 行可供扫描；目前没有事实反查恢复。当前实现仅保证不回滚已提交业务，不满足现行 SC-NTF-007 对写前故障后不丢提醒的要求；不得将此残留视为规格豁免。
- 广播可能重复（崩溃在“广播后、标记前”）。当前未提交的消费端补丁仅证明模拟桥及单一 QueryClient 生命周期内的同 ID 重投处理；显式清理或重启后不保留标记，不承诺第三方物理 exactly-once、实际桌面弹窗或已读。每个不同通知保留一个缓存标记至会话清理，空间随数量增长；这是避免默认 10 分钟 GC 导致会话内重复所需的范围。`claimExecutionNotificationDelivery` 的导出签名改变并移除独立 release 导出，仓内调用方已同步，仓外兼容未验证。
- 独立无网络内存模拟曾观察到：来源偏好读取挂起时注销、清理 QueryClient 并以同一用户重登，即使旧 realtime effect 卸载，已启动的旧 handler 仍可能调用模拟通知桥并在新缓存重建旧标记。用户已同意在现有认证/WebSocket 生命周期处理；未提交候选修复使用同步会话失效、旧 socket 回调拦截、旧 handler 检查，以及认证结束时同步清理和 Inbox 刷新续体检查；两项竞态已有 RED/GREEN 模拟回归，二次独立复核确认正常路径有效，但发现存储或草稿清理抛错会截断认证订阅且跳过 QueryClient 清理；候选修复在失败时仍清 QueryClient、记录异常而不标成功，已有 RED/GREEN 模拟回归；最终独立复核另发现：无 `keys()` 的合法 storage 在失败后，QueryClient 清理会丢失 fallback workspace 清单，后续重试可能错误地返回成功；新增日志可能暴露原始异常内容。日志已改为固定信息；为保留目标而加的生命周期锁会阻断新用户主动注销，已精准撤回。无 `keys()` 的两项恢复测试保留 RED，须先证明跨 session 清理身份／登录恢复边界，不可称会话切片已完成。存储或草稿清理失败时，旧持久化内容或内存草稿仍可能残留；用户已认可将退出、登录与自动恢复、草稿读取纳入同一清理边界；该屏障尚未实现，不能称跨用户隐私已闭合。它不能撤回已交给通知桥的请求，也不证明真实 OS 展示、生产泄漏或跨会话去重。
- 用户认可的退出与恢复边界尚未实现。新增内存 RED：`packages/views/auth/use-logout.test.ts` 在清理异常时未调用退出（1 失败／1 通过）；`packages/core/auth/store.test.ts` 中 token 删除失败仍保留本机身份、旧 `refreshMe` 覆盖同用户新会话（2 失败／10 通过）；`packages/core/api/client.test.ts` 中旧 cookie 请求 401 使新会话失效（1 失败／132 通过）。测试不访问真实网络或证明浏览器 cookie 撤销。随后旧 401 的候选请求代际修复曾使 API 聚焦 172/172 通过；独立复核仍以内存探针复现旧登录迟到成功错误换代、bootstrap 旧 401 触发当前失效、身份替换未换代三项交错缺陷；已另保存 API 7 项和真实 bootstrap 5 项 RED；新的共同认证归属候选曾使这些 RED 转绿，core 定向 223/223、登录页 39/39、Google callback 23/23；再次独立复核确认原三项时序改善，却发现 bootstrap/CLI/Google 争抢、旧 401 干扰新登录和当前登录 401 卡 loading 的三组真实交错。后续 10 项交错 RED 及强化的匿名 refresh 测试在最新改动后转绿；此前定向 core 225/225、views 47/47、web 25/25，三包 typecheck 与定向 ESLint 无错误（provider 2 条 warning）；独立复核确认上述认证交错在限定范围内闭合，另有 54 项内存探针通过。后续 Bearer 防复活改动的定向 API 72/72、renewal 19/19（API 另有 122 项被过滤未执行），新 10 项先 RED 后 GREEN，core typecheck 和定向 ESLint 通过；独立静态复核未发现本切片新增 P1/P2，未重跑测试；不证明 cookie、其他窗口或跨重启失效。实现本机退出屏障后（`platform/storage.ts` 的 `multica_session_barrier`：键缺失或 `clean` 放行，`pending`/未知/损坏/读错阻断；退出先写 `pending` 再删 token；归属不明草稿保留原字节并报 incomplete；Electron 注销只失效会话不强关窗口，issue 发起退出也结束整个 profile 会话），core 全量 180 文件/2552 例、views 全量 506 文件/6372 例、web callback 46 例、desktop coordinator 8 例、notification-gate 21 例通过，0 failed、0 skip；core 与 desktop typecheck 通过。旧 16 条 RED 已按新合同转绿或改为 incomplete 断言。
- 清理屏障剩余边界：屏障写失败时（A′）当前实例阻断并提示，但重启可能由仍有效的 HttpOnly cookie 恢复；本地 peer 同步不构成多窗口停写证明；cookie 远端撤销未获确认。真实浏览器/桌面冷启动、实际持久性未实测。多窗口共享凭据和按 workspace slug 存储的数据，未证明旧 writer 停止前不能重放删除；若新用户已写入同名键，不得凭旧目标自动删除。草稿 rehydrate 和异步搜索索引清理也不能仅以关闭登录页视为结束。用户已确认同 profile 多窗口一起退出、不强关窗口、不自动删除归属不明的草稿；其他窗口可能写入时阻止新会话并提示先保存或备份。具体人工删除范围仍须逐次确认，不假设允许清空整个 profile 或删除其他用户数据。归属未知草稿的 reset/删除已改为保留原字节并报 incomplete；枚举为空或读失败同样不算清理完成。后续曾接入未收口的 session-access 候选，按用户要求已精准撤回；回退后 core typecheck、renewal 19/19 和 scoped diff-check 通过，API 与上述 RED 未重跑，生产清理行为未改变。
- 收件人来源已改为 CR 自身记录的角色 owner：`crsync.applyOwners` 投影 crctl 注册/移交事件里的 `owners.requirement|development|test`（值必须是本 workspace 成员的 `user_id`，非 UUID 值拒绝写入）；授权类通知→requirement、维护类→development；都没有时才退回启动该 run 的任务身份，仍无可用收件人则不发送。Inbox 通知带上 `cr.shell_issue_id`，指向该 CR 的对话，不再依赖“最早 owner/admin”这类猜测。纯投影 run 的 `started_by` 仍是占位最早 owner，因此只作兜底，不作权力证明。
- **真实隔离 PostgreSQL 回执（2026-11-10）**：本地镜像 `pgvector/pgvector:pg17`（ID `366e1863bdee`，`--pull=never`）起一次性容器（唯一名 + `--label aifi45-run` + `--tmpfs /var/lib/postgresql/data` + 仅绑 `127.0.0.1`），跑完仓库正式迁移 `go run ./cmd/migrate up` 至 648 后执行 `go test ./internal/governance -count=1 -v`：**396 PASS / 11 FAIL**。`TestTC_NTF_001～007`、`TestOwnersEventProjectsRoleOwners`、`TestNoticeGoesToTheRecordedRoleOwnerAndItsConversation` 及 `TestFailRun*`、`TestPendingNotice*`、`TestFailureDigest*`、`TestUnroutableNotice*` 全部 PASS。容器已按记录的 ID 删除，`--filter label=aifi45-run` 回读为 0。
- 随后修正了唯一一处规格/代码不一致：维护类通知在无 `development` owner 时不再挑选 workspace owner/admin，而是与授权类一样退回启动该 run 的任务身份（仍做成员校验）；改后在同一一次性容器上重跑通知用例集（`TestFailRun*`、`TestUnroutableNotice*`、`TestPendingNotice*`、`TestFailureDigest*`、`TestTC_NTF_001～007`、owners 与角色 owner 用例）**全 PASS**，容器按 ID 删除、label 回读为 0。
- 该次 11 项失败均与本轮改动无关，原因已取证：`Channel*` 与部分 control 迁移用例要求名为 `aifi45_tmp_<16hex>`/角色 `aifi45_role_<16hex>` 且数据库带 `AIFI45_DISPOSABLE:<nonce>` 注释的非名片库（本容器不满足，探针在 `shobj_description` 处拒绝）；`TestTCAuth010…` 需要 `AIFI45_TOOLS_ROOT` 指向 tools 仓的共享向量夹具；`TestWP4*` 报 `head fixture scope must be unused: rows=2`，属同库跨用例残留。这些不属于 AIFI-45 通知链证据，也不能记作通过。
- **第二次真实验收（2026-11-10，非名片库）**：按探针要求建立 `aifi45_tmp_<16hex>` 库 + `aifi45_role_<16hex>` 非 superuser 角色 + `COMMENT ON DATABASE` 标记 `AIFI45_DISPOSABLE:<nonce>`，并设 `AIFI45_TOOLS_ROOT`，同一容器内新建干净库跑 `go test ./internal/governance -count=1 -v`：**403 PASS / 5 FAIL**。NTF-001～007、owners 投影、角色 owner 路由全部 PASS。5 项失败均非本轮改动：`TestChannelMigrationAfter{Up,Down,Reapply}` 要求「648 up 之前」的空库（本库由 `cmd/migrate up` 已到 648，且同库前序用例已有数据），属旧 runner 按用例另建库的既有前提；`TestWP4OriginalMapping…`/`TestWP4Concurrent…` 报 `Replayed:true` 且 VerdictID 与输入不同，符合同一 request 在前序用例已结算导致返回原映射，属 fixture 隔离问题（改造前首轮同样失败）。
- 说明：在同一定义域重复跑全量会互相污染（第二次得 396/11、第三次 397/11），因此只认「单次、干净库」的结果。
- 隔离局限（如实记录）：容器使用默认网络（`NetworkMode=pasta`），DNS 可解析，**未证明无外网**；仅能证明镜像本地、数据在 tmpfs、端口只绑 127.0.0.1、未挂载任何既有卷、未触碰 `multica-postgres`/`multica-backend`。
- 新增两项 DB 测试已写入（`crsync_test.go` 的 owners 投影与非法 owner 拒绝、`execution_notice_wiring_test.go` 的角色 owner 与对话链接），但本轮**未运行**：它们需要一次性隔离 PostgreSQL，资源操作未获批。`go build ./...`、`go vet ./internal/governance`、涉及文件的 gofmt 通过；这不等于行为已验证。
- 授权投影可能先将 run 置为 `waiting_approval`，使 `reconcileApproval` 的行数门不发通知；现有等待状态未证明与具体待授权请求及其指定接收者绑定。已签授权记录只能证明已发生的授权动作，不能反推待处理请求的授权者。
- 技术故障可能在到达 `failRun` 前被归为通用错误码而路由给业务方。任务失败及重试记录只提供部分事实，尚未形成与同一阻断绑定的恢复终止依据、完整根因、证据、已试路径、具体动作与维护责任人；不能用 `failed` 或错误码替代。
- 当前完成屏障尚未证明约定交付目标与验收已满足，也未证明交付通知收件人；不能将普通节点完成或 starter 等同于约定交付和指定对象。
- `started_by` 经成员校验不等于已证明的业务授权者；不能以审批记录的事后签发人、最近审批人或 workspace owner 推断当前待处理请求的授权者。
- 现有启动/周期扫描能恢复已存在的 pending notice，但尚未证明限定于本 change 的、可重建终态事实的非历史扫描范围。不能扩大为历史回填；事实或身份不能证明时停止，而非猜测或静默宣称完成。
- 真实数据库验收还缺经审计的新独占、无外网入口及完整资源身份和退出/清理证明；不运行旧入口或访问事故库/HOLD。
- 旧键历史行若真实存在，仍需单独裁定；本记录不覆盖数据库普查。

## 5. M008（同日）

`merge-effects.mjs#planRecovery` 的 `intent + at_prev` 已由 `push` 改为 `halt/uncertain`。后续未提交改动中，`unknown + at_prev + settled_no_effect` 即使调用方自报 `noEffectAttested=true` 也返回 `halt/no_effect_unverified`；当前判定没有返回 `PUSH` 或 `RESERVE_NEXT_ATTEMPT` 的分支，`merge-effects.test.mjs` 21/21。该 helper 尚无生产调用方，不能据此宣称实际恢复链已受保护；可信 `no_effect` 的来源、attempt 绑定和旧执行者围栏也未证明。SC-MG-015/016 的条款修订仍在 `wp4-sc-mg-015-016-paired-amendment-20261104.md`，**未获 Gate2 批准**，不声称自动重试可用。

## 6. 本轮委派口径

认证归属和后续 Bearer 切片实现请求 strong 档 `OpenAIPersonal/gpt-6.1-sol:high`；Bearer 切片独立静态复核也请求 strong 档。通知生产者静态核查请求 balanced 档 `OpenAIPersonal/gpt-6.1-terra:xhigh`。前次认证交错最终独立复核沿用既有子代理会话，未重新覆盖模型。上述运行没有可核实的实际后端回执，actual 均记 unknown；档位请求或思考量不作为验收证据。
