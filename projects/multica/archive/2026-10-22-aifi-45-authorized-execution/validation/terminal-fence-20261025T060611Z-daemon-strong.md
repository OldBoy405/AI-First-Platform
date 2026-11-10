# AIFI-45 terminal-fence — daemon 限定静态评审

## 范围与结论

业务根：`C:/Users/GOBAO/Downloads/AI/multica`。以下代码路径相对此根；主要文件前缀为 `server/internal/daemon/`。

按本轮交接，M native models 于 2026-10-25 **07:03:02Z** 核实 schema1/configured strong 为 **OpenAIPersonal/gpt-6.1-sol/high**；**actual backend model unknown**。本 reviewer 未重新发现模型，不把 configured 当 actual。

仅审 daemon tuple 关联、complete/fail 路径、client 和 outbox v3，以及必要直连 helper。**未访问 DB、未跑测试/编译/vet/生成器、未改源码/测试、未用子代理**；仅只读、哈希及创建评审文本。

**限定静态评审完成，REQUEST_CHANGES：P0=0，P1=2，P2=2。** 并发触发前提逐项列明；未做动态验证不等于静态范围 INCOMPLETE。不签完整 terminal 链、生产准入、Gate3、全局 C1、完整 TC/major；不补旧 claim 锁序 INCOMPLETE，也不凭此关闭先前 server/Fail finding。

## 一、确证 P0/P1/P2

### F1 / P1：runtime-offline 早退可将新合同报告降为 legacy

**路径与行号**：`daemon.go:5748–5773` 的 handleTask 先查 runtimeIndex；不 tracked 时构造只带 taskID/error/reason 的 fail report。它发生在 prepareClaimedPipelineTask 调用之前。`execution_verifier.go:29–46` 只有 strict claim 回读成功且 DaemonID 匹配后才 remember。`execution_terminal_claim.go:74–84` 在 map 无记录时原样返回 report；16–21 接受 required=false、tuple 全空。`daemon.go:6473–6476,6552–6565` 因而允许它进入持久化和 sender；`terminal_report_queue.go:156–190` 写为 v3 claim_mode=legacy，`client.go:693–723` 经零 claims client 分支发无 tuple 的 /fail。

**触发**：新进程/空 map 收到声明新执行合同的 T/R/G，runtime 在 claim 返回与 handleTask 之间被移除。该早退不回读 claim、不拒绝 unfenced callback，而是发送/持久化 legacy fail。若任务后来已被新代领取，请求不再有旧 G 的约束。这里只确证 daemon 降级路径，未做 DB 竞态实验或宣称线上误终止已经发生。

这是新 attach 机制未封住的已知早退类型，不是把有意保留的 legacy API 本身重新当漏洞。`daemon.go:5793–5797` 的 unavailable→不回调保护仅在 prepare-error 分支，覆盖不到这里。

**修复/回归建议（未执行）**：从这次 Task 携带明确 required 状态；strict 无可信 tuple 时不发终态，留给 lease/reclaim，或先完成合法 claim 验证。负例：strict T/R/G、空 map、runtime 不 tracked，HTTP callback=0 且无 legacy outbox；旧合同仍兼容。

### F2 / P1：按 taskID 取最新 cache，可把新代 tuple 附到旧代结果

**证据**：`execution_terminal_claim.go:65–69` 对同 taskID 直接覆盖 claim；74–84 对未 qualified report 仅按 taskID 读取最新值，不比较来源运行。`execution_verifier.go:44–48,69–75` remember 后仍有准备/安装，且最终仍拒绝消费；安装有实际网络等待点（`execution_trust.go:321–337`）。`daemon.go:5798–5800` 的准备失败报告只有 taskID；5956–5965 的 runTask error 和 6395–6405、6434–6449 的 result 报告也没有固化来源 Task tuple。batch dispatch（5498–5535）按 slot 起 goroutine，此处无跨代 taskID 去重；投递锁不保护 prepare/remember 阶段。

**条件静态时序**：同 daemon 的 T/G1 与 T/G2 处理重叠，例如 G1 等待安装时平台已 reclaim 为 G2；G2 回读验证后覆盖 cache。G1 随后因准备/安装/消费拒绝而构造 failure，只带 T；attach 给 **G1 payload** 附 **G2 tuple**。即使服务端 CAS 正确，也只能按请求中的 G2 检查，不能还原 payload 的来源。

重叠在真实调度中的发生率/端到端结果未动态验证；确证的是当前函数组合没有保持 report→origin generation 关联，mutex 无 data race 不能证明代次语义正确。

**forget 的局部正确性及限制**：`execution_terminal_claim.go:89–100` 的 runtimeID+dispatchedAt 相等删除，能防一个**已正确附 G1** 的 stale report 删除 G2。但它不能修复此前已误附 G2 的报告；后者成功后仍可能按相等规则删 G2。

**修复/回归建议（未执行）**：verified tuple/required 必须绑定到单次 execution 的局部上下文或 immutable report；不能报告时按 taskID 重新借最新 tuple。暂停 G1 准备、验证 G2 后恢复 G1，断言 G1 报告仍为 G1 或拒绝，绝不能携 G2；另测 stale qualified G1 的 ack 不删 G2。

### F3 / P2：single-flight 仍按 taskID，旧代 replay 可使新代报告在落盘前丢失

**证据**：foreground 在 `daemon.go:6478–6481` 先 beginTerminalReportDelivery(report.taskID)，竞争失败直接 return，enqueue 到 6487 才发生；6527–6543 的 flight map key 就是 taskID。replay 也按 item.report.taskID 占锁（`terminal_report_queue.go:957–960`），不是 deliveryKey。complete 错误处理仅记录后返回（daemon.go:6407–6415）；其它 fail 调用点同样没有为这个未落盘报告再排队。

**触发**：T/G1 的可发送 pending report 正在 background replay 且 HTTP 阻塞；T/G2 前台报告到达。虽有不同 deliveryKey/文件名，仍因 T 被占用而在落盘前返回。G1 释放不会自动重提 G2 payload。因此 G2 可能既未发送也未持久化；不要求两代 agent 同时运行，旧代只需留下待重放记录。

**修复/回归建议（未执行）**：foreground/replay 都用 deliveryKey 保持同代互斥；若确需 task-level serialization，先可靠持久化不同代报告再等待。阻塞 G1 replay 时提交 G2，确认 G2 durable、最终可发送，ack G1 不删 G2。

### F4 / P2：replay ack/补偿成功不 forget，历史已交付条目可耗尽 4096 cache

**证据**：foreground 成功在 `daemon.go:6514–6523` forget；replay send 成功后 acknowledge 并更新 delivered（`terminal_report_queue.go:961–978`），没有 forget。quarantine 的 fail compensation 成功也只记录日志（892–901）。产品调用搜索中 forget 仅见前述两个 foreground 调用，没有独立回收。上限为 4096（execution_terminal_claim.go:53,65–66）；满时由 verifier:44–45 包 unavailable，daemon.go:5793–5797 退出。

**触发**：同一进程内不同 strict task 的前台发送耗尽重试，后来 replay 成功且磁盘 ack 删除；map 条目继续保留。累计 4096 个这样的不同 taskID 后，即使 pending 已清空，新 task 仍因 cache full 无法继续 strict preparation，直到重启等外部动作。

容量限制本身是可接受的 fail-closed，不是静默 legacy；缺陷是成功交付后遗漏回收。残留记录也增加后续 taskID 复用/合同模式切换时误带旧 tuple 的风险，该模式切换未动态验证，不夸大为已观测越权。

**修复/回归建议（未执行）**：replay send+ack 成功后用 tuple-equality forget；补偿真正成功时清对应代，不因 legacy ack 或未送达 quarantine 删当前代。覆盖 foreground 失败→replay 成功后 map 为空、G1 ack 保留 G2、成功补偿清理及历史交付超过4096不持续占位。

## 二、可接受但有风险／局部正确性

### 1. complete/fail 路径清点

均经 reportTerminalTask：runtime offline（daemon.go:5762，F1）；pipeline prepare error（5798；unavailable 不回调）；runTask error（5956）；local-directory resolve/mode/path/wait cancel（6132,6151,6163,6293）；complete/noncomplete result（6395,6434–6450）。attachPipelineRecovery（6307–6316）只加 recovery，不擦 tuple。中央入口存在不代表来源都 qualified：这些构造通常只带 taskID，依赖 cache，故有 F1/F2。

sender 只在 daemon.go:6552–6565 选择带 variadic claims 的 retry 方法。两个有意直送例外：queue:961 replay 使用磁盘完整 report；queue:892 compensation 在 888–890 显式复制 runtimeID/dispatchedAt/claimRequired，没有看到主动降级。

导出旧 wrapper（client.go:649–650,689–690）仍 legacy；本片 daemon 产品调用未见绕过中央 sender 使用它们，不能因 wrapper 存在就断言生产绕过。usage/progress/cancel-ack 不是本轮两个 endpoint 的签署范围。原 complete 回调失败不会立即 synthetic fail 覆盖原完成。

### 2. deliveryKey、文件、temp、ack、永久拒绝

- execution_terminal_claim.go:30–48：qualified 先验证 canonical T/R UUID、微秒精确时间；key=T+NUL+R+NUL+G，legacy key=T。
- queue:140–143,398–425：文件名为完整 SHA-256 hex，非 raw tuple；同 key 比原 payload，异代正常不共文件。
- list（497–540）、temp recovery（550–618）、ack（620–635）、permanent rejection/failed（659–748）都从 report.deliveryKey 得文件名；未发现按 taskID 删除 generation 文件的产品路径。F3 的 flight gate 是例外。
- temp 验证 JSON/record/tuple 后，要求预期 hash 前缀和 .tmp 后缀；目标冲突保留 temp 报错，不覆盖。ack 校验 filename 与 report key 后只删该文件。
- 永久拒绝只计400/403/语义task-not-found，至少3次且10分钟；401/408/409/429/普通404/5xx 留队（636–656）。stale409可能长期留队，属运维容量风险，不是自动legacy回退。
- 未验证真实 crash、跨进程竞争、Windows rename/ACL、哈希碰撞；单进程 mutex 不是跨进程锁。

### 3. v3、v1/v2、未来版本及 fail-closed

writer（queue:156–190）显式 mode=legacy|generation；generation 保存 tuple。reader（192–247）要求 v3 精确 mode；缺 mode/null/大小写值变体拒绝，generation 缺失/空/null/半 tuple 拒绝。raw decoder（475–494）用完整 UTF-8/重复键/单文档 scanner，并拒绝 version/task_id/claim_mode/runtime_id/dispatched_at 的大小写键别名；scanner 实现在 governance/execution_authorization.go:449–509。

旧 v1/v2 无 claim 值的记录按 legacy 还原。replay 不 attach，直接送还原 report：**重启空 map 保 generation tuple；旧 legacy 重放仍 legacy，不受当前 cache 命中升级**。未来 version 拒绝且保留；list 报错不删，replay:922–926,997–1000 保持周期错误可见。

**建议 R1（非独立安全 P2）**：v1/v2 对 claim 字段实际用 typed string 非空判断，不是 raw presence；显式 null/空字符串会解为空，仍 legacy。v3 legacy 也允许空值 tuple 字段。若要求“出现即拒绝”，应在 fields map 按 presence 拒绝。不能宣称所有字段出现形式都 fail closed；也不把可任意改本机记录的能力夸成新远程越权。

### 4. client 拷贝、redirect、body

execution_terminal_claim.go:102–125 要求恰一合法 claim、可信 URL、非 nil HTTP client，再注入两个 canonical key。业务 body 在 client.go:653–677,693–723 先构建，之后无 tuple 覆盖，无用户 map merge。

copyClient 保留 baseURL/token/identity；拷贝 http.Client 保留 Timeout/Transport/Jar，仅副本 CheckRedirect=ErrUseLastResponse，不改共享策略。NewClient control Timeout=30s（client.go:152–160）；POST helper（1405–1438）发送 Bearer/identity/workspace context header，非2xx（含redirect）作为错误，不 ack。重放使用当前 client 凭据，磁盘不存 token。

**建议 R2**：整份 Client 浅拷贝也复制其中 sync.Mutex/cache（client.go:138–148）。当前 terminal 链不使用这些 mutex，未确证死锁；建议只构造发送字段或显式传 http.Client，避免复制锁及未来共享状态风险。未跑 vet，不宣称其通过/失败。

### 5. 泄漏、1MiB、签名与 manifest

tuple 明文位于 outbox（queue:48–65），不是凭据隔离证明；hash 文件名不等于加密。record 无 auth token；temp 0600+Sync/rename（429–471），目录0700且最末级拒 symlink（380–395）。Windows 仍依赖用户 profile/workspace ACL；未审计所有父目录、quota 或实际权限。

未见新增专门打印 dispatchedAt 的日志；既有 runtimeID/taskID 日志仍在 daemon.go:5760–5761,5781,5822–5833。HTTP错误仍可保留至4096字节 response body（client.go:1431–1433）；未跑敏感日志探针，不宣称日志永不含秘密。

claim SDK 1MiB response 上限仍在 execution_task_claim.go:58–61；outbox ReadFile/terminal output 不是该运输合同，不宣称 outbox 有1MiB上限。本片不改授权签名字节/部署manifest、不生成receipt/activation；对照 wire-contract §3.3–3.5，metadata/claim/fence 都不是准入。既有签名与manifest完整审计不在本轮扩签。

## 三、未验证与既有证据

没有执行上述负例、并发 reclaim、实际 MDT/DB/外部 side-effect、断电重启或4096压力试验。源码条件时序不冒充已运行 exploit。

只读已有 meta：daemon-attach-green2 为7 RUN/7 PASS（6 leaf）；queue-green3 为35 RUN/35 PASS（31 leaf）；independent2-daemon 为116 RUN/115 PASS/1 SKIP（107 leaf）。均为其它 actor 结果，非 reviewer 独立执行。已读 generation 测试覆盖正常sender/缺tuple拒绝/store round-trip/两代文件/verified attach；既有 replay互斥测试主要为 legacy，不能证明跨代 gate/cleanup。没有用测试名字代替路径证据。

此前 Fail replay-scope、Composio 外部活动、Complete server 闭环不重新签；其它actor green或wire文字不由本轮自动关闭旧 finding。

## 四、快照与报告创建

初对 daemon-attach-green2 pin：五文件匹配；queue 当前37992 bytes，与该pin37985不同。后确认 queue-green3 与更新的 independent2-daemon manifest；本报告最终采用后者，以下六文件在创建前再次全部匹配。未把旧pin测试证据硬套 drift。

最终报告由只含本文的临时评审文本经 Python open('xb')（wx/exclusive create）创建，不覆盖已有报告，创建后读回核验；临时文本不在产品源码树。此前两次过长 shell 传输在 Python 解析阶段失败，没有创建目标报告；以最终成功的排他创建回执为准。

Final pin: `terminal-fence-20261025T060611Z-independent2-daemon-source-manifest.json` (2026-10-25T07:05:14.017Z).

| File | Bytes | Raw SHA-256 |
|---|---:|---|
| `server/internal/daemon/execution_terminal_claim.go` | 3991 | `d559b5bee8893bcf159527af55abb3c5290934e1ff23c9cfe76e4fc2afda5e86` |
| `server/internal/daemon/execution_verifier.go` | 5754 | `985ae0533a8665aca1ed92707266bc94cb21b3715bc3dd9520d8e44a3a78cef1` |
| `server/internal/daemon/daemon.go` | 487893 | `308ecb2a97b4ed0fc0ecfd08401fe5db2149a20293b1df0091946595b685339e` |
| `server/internal/daemon/client.go` | 61090 | `b1c9868b1489ac52bca552f7d56e63b23d2f2524f12e00f957fc4b77d6badc55` |
| `server/internal/daemon/terminal_report_queue.go` | 37992 | `a44344f8b713df8ed70efb772414c0451594ec04df16ed9e4b6a9edae4d5de08` |
| `server/internal/daemon/execution_terminal_generation_test.go` | 10331 | `0bf9bfda1e98f641857d3fe3e897e9462d0e0be8135f18e382f20e7933ec3aec` |

Creation UTC: 2026-10-25T07:12:50.406529+00:00
