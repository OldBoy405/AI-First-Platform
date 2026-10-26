# AIFI-45 旧 StartTask claim 非作者 strong 静态复核

## 结论与权限

**INCOMPLETE；不签 PASS。当前没有确证的本片新增安全 finding。** 下述已检路径已有具体锁序结论，但第 5 节的符号尚未补完，不把这些边界包装为全链无死锁证明。

- 同一旧 claim reviewer 的续审，不新增 reviewer。requested / 用户提供的有效配置：`OpenAIPersonal/gpt-6.1-sol/high`；actual 无回执，`unknown`。
- 只读取文件；未执行命令、测试、SQL、DB 连接、容器、网络或子进程；未修改源码。DB 执行权仍归独立 balanced；原事故现场 HOLD 未触碰。
- 唯一写入是用户明确要求的本报告，不是源码、CR 状态、Gate 或审批记录。创建前精确查找确认目标不存在；宿主 write 工具不暴露原子 `wx` / O_EXCL 选项，因此不声明原子排他创建保证。
- 不签 Gate3、整个 C1 或 49TC；不使用 runner PASS、新隔离库恢复或 metadata/SDK 新测试替代旧 claim 证据。

## 1. 本片输入和当前源码绑定

代码路径以下均相对 multica 仓根（工作区 repositories 指向的 sibling `../multica`），证据路径相对本报告目录。

已读 `current-bindings-20261025T034807Z-claim-lock-facts.md` 全文；其 digest 在用户提供的宿主验证及当前 manifest 中同为 `42f0e5665d36d9b6d526211c5f5d55a878e179fdbc9214f9589c8c6fe03872a1`。本 reviewer 未执行哈希重算。

已读当前 `current-bindings-20261025T034807Z-source-manifest.json` 全文。它自述为 post author GREEN、pre independent regression，**不是追溯性的 pre-run manifest**。当前源码按函数重新读取：

- `server/internal/handler/daemon.go:4531-4619` 的完整 `StartTask`，含尾部 attribution / capability response。
- `server/internal/service/task.go:4634-4699` 的 `StartTaskForClaim` 和 post-commit `taskStarted`。
- 不因 daemon.go 整文件 raw hash 随已说明的新 metadata 路径改变而报告“未说明漂移”；没有用 HEAD 全 diff 界定本片，也没有据旧主工作区 cr.md 判断 CR 状态。
- service/task.go 精确符号查询只见 `StartTaskForClaim` 定义；handler/daemon.go 精确查询只见 `:4577` 调用。此为已查询两文件的调用者结果，不虚构仓库全局引用索引。

## 2. 认证、新 claim 与兼容性：已确认事实

1. `server/internal/middleware/daemon_auth.go:115-153`：mdt identity 来自 token hash 查询或认证缓存，服务端写入 workspace / daemon context。`X-Daemon-ID`、请求体 daemon_id / workspace_id 不是本函数的新 claim 授权来源。
2. `server/internal/handler/daemon.go:57-84,127-166,4535,4580`：先从数据库 task 的服务端 workspace 解析结果执行 mdt workspace 相等或用户 membership 门禁；传入 service 的 workspace 是该解析结果，不是直接转发请求 header/body。
3. `server/internal/service/task.go:8222-8281`：解析 issue、chat、autopilot，以及持久化 quick-create / pipeline context。context 分支依赖既有可信 task 创建合同，不等同于证明完整 claim 或 project admission。
4. `server/internal/handler/daemon.go:4563-4580`：runtime UUID 与 PostgreSQL 微秒精度 generation 先校验；mdt workspace 非空而 daemon identity 空时返回 403。
5. `server/internal/service/task.go:4650-4659`：runtime 加锁后核验 workspace 和非空 daemon identity，随后才锁 task claim。因此外 daemon 的精确 runtime/generation 在首次 start 与 replay 前都受检查；不是只检查第一次 start。
6. `server/pkg/db/queries/agent.sql:1196-1202`：锁定 task 必须同时匹配 id、runtime_id、dispatched_at，且状态为 dispatched / waiting_local_directory / running。拒绝映射见 `handler/daemon.go:4582-4593`，非 legacy 的 stale/归属失败返回 409。
7. `server/internal/middleware/daemon_auth.go:168-279`：PAT / cloud PAT / JWT 仍提供认证后的用户 identity；非 legacy service 空 daemon 参数有意保留用户兼容路径，workspace membership 门禁未被本片替换。这里只作静态兼容结论，没有新增真实 PAT 回归执行证据。

## 3. 锁序与 FK：已补出的具体结论

### 3.1 Start、supplement、replay

`service/task.go:4650-4674`：runtime FOR UPDATE → exact task FOR UPDATE → 首次 start 的 capability/state mutation → commit；仅 commit 后调用 taskStarted / agent 状态协调。replay 不重复 mutation 或 taskStarted。

**真实 start SQL 在 `server/pkg/db/queries/supplement.sql:1-32`，不是 agent.sql。** candidate JOIN runtime 但明确 `FOR UPDATE OF t`，只锁 task；capability INSERT 后更新同 task 的 status / started_at / wait_reason / lease。没有写 task.runtime_id，也没有从这个 JOIN 获得 runtime/agent 行锁。capability 表在所读 schema 中未见 runtime FK 或附加 trigger。

### 3.2 ClaimTask 与两个 runtime 外层

- `service/task.go:3880-4032`，`agent.sql:854-931,1843-1846`：agent FOR UPDATE → 候选 task FOR UPDATE SKIP LOCKED → status / dispatch time / lease 更新；project 分支再取 advisory `claim-project|<id>`、只读复核，冲突时 CAS requeue 同 task。
- **ClaimAgentTask 的 runtime_id 是 WHERE fence，不是 SET 目标。这里不会因“更新了 runtime_id”而新增 runtime FK KEY SHARE。** service 的 claim 事务未调用 runtime 行锁。
- `service/task.go:4060-4189` 的 `ClaimTaskForRuntime` 没有包住下游 claim 的外层数据库事务：promotion / reclaim 各自查询，然后逐 agent 调用 claimTask。
- `service/task.go:4345-4537` 的 `ClaimTasksForRuntimes` 同样是 promotion、batch reclaim、候选读取、逐 agent 独立 claim；不在持有多个 runtime 行锁的外层事务中调用 claimTask。
- `agent.sql:994-1084`：singular / batch reclaim 只刷新 dispatched_at 与 lease，task selector 为 SKIP LOCKED；runtime JOIN 为读取。`agent.sql:2430-2463,2529-2566` promotion 只 SET status，不写 runtime_id。
- `agent.sql:976-992`、`service/task.go:4000,4303-4307`：requeue 是 id/runtime/generation CAS，写 status / timestamp / lease / receipt 字段，不写 runtime_id。

**对此已检组合，所担心的“claim 已拿 task，再因 runtime_id UPDATE 的 FK KEY SHARE 等新 Start 的 runtime FOR UPDATE”不成立。** 不能仅因 query 中出现 runtime_id 列名推定存在这个锁环。旧轮未定位的 `ClaimAgentTaskByRuntime` 不能继续当作一个已证实的 SQL 符号；本轮已按真实 `ClaimTaskForRuntime` / `ClaimTasksForRuntimes` 调用链审查。

### 3.3 Runtime access-change / teardown

- `handler/runtime.go:1101-1178`、`queries/runtime.sql:368-399`：access-change 先 runtime FOR NO KEY UPDATE → non-owner agents NOWAIT → chat sessions NOWAIT → tasks FOR UPDATE，再改 visibility / cancellation / settlement / unbind。新 Start 与该路径在**同一 runtime**的首锁已互斥，不会一个先持 task、另一个先持 runtime 后相互等锁。
- `service/runtime_teardown.go:73-179` 已读到尾部：runtime FOR UPDATE → bound user agents → cancellation / terminal settlement → drain check → user unbind / pause → task history detach → system dependency cleanup / chat locking / system-agent deletion。
- `handler/runtime.go:1389-1411,1592-1630` 的删除调用者先锁 runtime。`handler/runtime_profile.go:519-540,567` 和 `queries/runtime_profile.sql:168-177` 先按 id 锁全部 profile runtime，再进入 agent / teardown。
- `queries/runtime.sql:434-445` 真实 detach 是 terminal task 的 `runtime_id = NULL`，不是改指另一个 runtime；不会为 NULL 目标申请新的 parent FK KEY SHARE。同 runtime teardown 与新 Start 的 runtime 首锁一致。
- `SettleTerminalTaskState` 的 Go 包装和 `PrepareRuntimeAccessCancellation` 已读，详见第 5 节尚缺的底层 SQL；因此这里不扩张成跨 runtime、全部 dependent-row 路径的无死锁证明。

### 3.4 真实 schema 的 FK 与 trigger 尾部

仅从 `disposable-db-20261024T162608Z-balanced3-governance.schema.sql` 读取，没有连接数据库：

- `:8094-8098`：真实 `agent_task_queue_runtime_id_fkey` 为 runtime 引用、ON DELETE CASCADE。
- `:4241`：active_requires_runtime 是 NOT VALID CHECK `(runtime_id IS NOT NULL) OR (completed_at IS NOT NULL)`；不把它称为额外行锁。
- `:7899`、`:382-459`：dirty trigger 仅 DELETE 或 UPDATE OF runtime_id, issue_id 触发，函数 UPDATE/DELETE 全分支和尾部已读完；只从 usage / agent / issue 读取并 upsert hourly dirty key，没有 runtime 行锁。dirty 表所见约束是 `:5312-5313` unique key，未见 runtime FK/该表 trigger。**新 Start / claim / reclaim / requeue 的上述 SET 列不会触发这个 dirty trigger。** teardown 的 detach 会触发它，不能据此反称 start 会触发。
- `:311-325,7906`：terminal MCP overlay trigger 只改 NEW 字段，不锁 runtime。
- `:285-305,7857`：状态更新另有 capture_task_wakeup；它调用的 `capture_issue_wakeup` 全文 `:200-250` 会 upsert wakeup receipt，因此没有把“没有 runtime FK 更新”误说成“没有其他锁”。
- 为检查 receipt → enqueue → runtime 反向链，已读 ordinary dispatcher `service/issue_wakeup.go:978-1043,1159,1327` 与 system dispatcher 相关调用点 `issue_wakeup_system.go:414,494,657`。两者在 receipt 锁前调用 `lock_task_owner_rows`；真实函数 `schema:642-718` 会先取得包含 runtime 的 KEY SHARE。ordinary 路径还核验 candidate runtime 未变。因此这些已检 enqueue 路径不是“先 receipt、后首次申请同 runtime KEY SHARE”的反例。其他管理/注册路径未据此自动背书。

## 4. 旧证据与 fixture：核验层级

已读取三个旧 meta（未复跑）：

| 证据 | 记录的结果 | 本 reviewer 的含义 |
| --- | --- | --- |
| claim-build-20261024T153817Z-red1.meta.json | exit 1；run 1 / pass 0 / fail 1 | 已查对应 stdout 失败行：foreign daemon exact claim 得到 status=200；不是构建失败替代 RED |
| claim-build-20261024T153817Z-green2.meta.json | exit 0；3/3、skip 0 | 历史测试事件计数，不说成三个独立安全场景或当前数据库验收 |
| claim-build-20261024T153817Z-handler-green.meta.json | exit 0；13/13、skip 0 | 历史 TestStartClaim 事件记录，不是本轮执行 |

已读 `handler/daemon_start_claim_test.go` 全文：stale generation、wrong runtime、first start/replay、reclaimed generation、concurrent replay、真实 cancellation row-wait、精度及 legacy 兼容场景。已读 `governance/execution_start_claim_test.go` 的测试主体至结尾：真实 DaemonAuth/token、empty identity 403、foreign start/replay 拒绝，以及观察 PG blocker 后改归属的测试设计；fixture 自建 user/member 已见。这里只核源码与旧 meta，不把测试源码当作执行结果。

`handler/handler_test.go:44-45,108-199`：每进程 UUID email/slug；setup 单事务 commit 后返回实际 IDs；cleanup 按已创建 workspace/user IDs 删除，没有按共享 email/slug 预清历史。这是 harness 防串扰修正，**不是事故原库已恢复、完整隔离已证明或可以继续在原库执行的授权**。

## 5. 仍缺的具体符号 / 判断边界

以下不是确证 finding，也不笼统写“未穷尽全仓”：

1. **agent rebind 的完整事务调用者**：尚未逐段读取 `Handler.UpdateAgent` 和 Builder runtime rebind 调用者如何取得 `LockAgentRuntimeForAccessChange`，再执行 `UpdateAgent` / `RebindAgentBuilderRuntime`。已见 SQL 会写 agent.runtime_id，但还未完整校验调用者是否可能在已有 task/dependent-row 锁后等待 runtime；不能凭注释代替调用者锁序。
2. **teardown / revocation dependent-row SQL 尾部**：Go 已跟到 `SettleTerminalTaskState` → `SettleTerminalTaskSupplements` / `SettleDelegatedFailureRecoveriesForTask`，以及 system cleanup 的 `LockChatSessionsBySystemRuntimeAgents`；这些底层 SQL 的完整锁对象、与其真实写入调用者的反序尚未补齐。尤其跨 runtime 遗留 task 被 `CancelAgentTasksByRuntimeOrAgent` 扫到时，不能仅靠同 runtime 首锁排除全部三方锁环。
3. **wakeup 管理/注册与 receipt 的反向链**：ordinary/system dispatch 的 early runtime fence 已确认；尚未完整审完 `IssueWakeupService` 管理/注册事务（例如持 receipt 后是否进一步写 agent/runtime/task owner 引用）。`capture_issue_wakeup` 的 receipt upsert 已识别，未把这条未审尾部静默消掉。
4. **真实 PAT 新 claim 回归**：源码门禁兼容已核，没有本 reviewer 执行的真实 PAT + generation-aware start/replay 测试。旧 handler suite 不能冒充这一项。

如主会话继续补审，应优先给上述调用者 / SQL 的有界片段；无需再跟 metadata 新 API/SDK 或全仓历史。本报告在此落盘，不等待穷尽后才留下记录。

## 6. 明确保留的合同缺口

legacy 无 generation 的入口仍存在且可走旧兼容分支，**本片没有关闭防降级**；完整 project / resource / admission / 每 repo / 完整 claim、隔离与授权消费证明仍未实现或未证明，按已公开 major 边界保留。本次不是 receipt 签发、不开放消费，也不是对 signed head 或新资源 API 的审查。后续任何 scoped 静态通过都不得改写这些边界。
