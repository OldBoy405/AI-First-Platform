# AIFI-45 terminal-fence daemon：F1–F4 修复复核（resume1）

## 范围与结论

业务根：`C:/Users/GOBAO/Downloads/AI/multica`。以下简称的 `.go` 文件，除特别说明外均在 `server/internal/daemon/`。

仅复核前报告 `terminal-fence-20261025T060611Z-daemon-strong.md` 的 F1–F4 及修复直接引出的行为。不重复此前全量审计。未访问 DB，未运行测试/编译/vet/生成器，未改产品源码或测试，未调用子代理；未使用或干扰另一个代理的 DB 执行权。这里只读源码、必要 manifest 和新增测试文本，计算哈希并生成报告。

模型声明沿用本轮既有交接：configured strong `OpenAIPersonal/gpt-6.1-sol/high`；actual backend model unknown，未重新核模型。

| 原 finding | 状态 | 简要结论 |
|---|---|---|
| F1 / P1 | **PARTIAL** | 完整 tuple 的 runtime-offline 早退已修；strict 缺 tuple 时仍可能 legacy。 |
| F2 / P1 | **CLOSED** | taskID 最新 claim 缓存及其查询根因已删除，生产 handleTask 每次 stamp 自己的 tuple。 |
| F3 / P2 | **CLOSED** | foreground/replay single-flight 均改 deliveryKey，不同代不再互斥。 |
| F4 / P2 | **CLOSED** | 缓存整体删除，成功重放未 forget 导致的 4096 历史条目耗尽不复存在。 |

**新增确证：N1 / P1，一般 PAT daemon 的无新合同任务被强制升级为 MDT-only terminal 请求，造成 403 回归。新增 P0=0；除 N1 外未新增确证 P1/P2。** F1 的剩余缺口仍归原 F1，不重复计为新 finding。限定静态复核完成，但不能无条件签这组修复通过。

不签完整 terminal 链、生产准入、Gate3、全局 C1、完整 TC/major；不补旧 claim 锁序 INCOMPLETE，也不自动关闭先前 server/Fail finding。

## 1. F1 — PARTIAL

### 已关闭的原触发

- `daemon.go:5742–5748`：handleTask 在查 runtimeIndex 之前调用 `withTerminalClaimOrigin(ctx, task)`。
- `execution_terminal_claim.go:67–75`：T/R/G 三项均非空时，创建包含这次任务原始 tuple 的独立 value context。
- `daemon.go:5756–5768`：runtime-offline 的报告使用该 ctx；`daemon.go:6470–6473` 在持久化前调用 `withContextClaim(parentCtx)`。
- `execution_terminal_claim.go:80–91` 在 taskID 相等且 report 尚未 required 时附 tuple 并置 required=true。

因此来自本次 claim 的完整合法 tuple，在 offline 早退中确实进入 qualified report，不再依赖 prepare 成功或后续缓存命中。时间字符串保持原值，不在 stamp 时截断或重格式化。

### 仍未关闭的输入边界

`execution_terminal_claim.go:68–69`：T、R、G 任一为空就直接返回原 ctx；不根据 `TriggerCommentContent` 判断 strict，也不保存“本应 required 但 tuple 不全”的标记。runtime-offline 分支仍在 strict preflight 之前。

具体静态触发：新的普通 parent context、合法 T/R、`DispatchedAt=""`，trigger 明确声明新执行合同，runtime 不 tracked。stamp 不发生；offline report 只有 taskID；`withContextClaim` 找不到 origin，`terminalClaims():18–23` 接受 required=false 且 report tuple 全空，`persistedTerminalReport` 写 legacy，sender 零 claims 发 legacy /fail。**这是不应允许的 strict→legacy 降级。** RuntimeID 缺失同样不 stamp；不能因为局部 report 的两字段都是空，就证明来源 Task 是 legacy。

若 runtime tracked，严格 claim 回读会因缺失 G 失败，经 `errExecutionTaskClaimUnavailable` 分支返回而不回调；这个保护仍覆盖不到上述 offline 早退。因而不能把 F1 判为完全 CLOSED。

### 畸形但非空，与空值必须区分

T/R/G 均非空但 UUID 非 canonical、G 非法/超微秒时仍 stamp；随后 `execution_terminal_claim.go:25–40` 验证失败，`daemon.go:6472–6473` 在 single-flight、落盘、网络之前直接返回错误。不会捕获错误后再按 legacy 发送。**这属于可接受的 fail-closed**，不要求 stamp 自己先做同一套格式验证。已 required 的报告即使 tuple 为空/畸形也不被 context 修补，仍被该验证拒绝。

### 对交接中服务器事实的使用范围

必要只读回查确认：`server/internal/handler/daemon.go:2730–2735` 在 DB DispatchedAt.Valid 时输出 UTC RFC3339Nano 和 StartClaimSupported。`server/pkg/db/queries/agent.sql:892,1015,1062` 的 claim/dispatch-recovery 设置 dispatched_at；后两处 recovery 限 dispatched、started_at IS NULL。由此可以接受完整 tuple 来自这次 delivery、已启动后无需 taskID cache 追最新代的修复方向。

但“有效值会 canonical 输出”不是客户端已验证“所有 strict 输入都必有值”；本轮没有确证当前正常成功 batch claim 会产出空 G，也不虚构这一动态现象。剩余问题是明确要求复核的缺失/损坏输入、旧响应边界仍允许 strict 降级。建议以明确的 required/contract 状态区分 legacy 和 missing tuple，strict 缺字段应拒绝终态而不是回退。

## 2. F2 — CLOSED，附 context 使用边界

产品搜索未发现 `terminalClaimMu`、`Daemon.terminalClaims`、remember/attach/forget helper 的存储或调用；旧 limit 仅留历史注释，不再有 map/容量执行逻辑。`execution_verifier.go:40–43` 在回读/DaemonID 比对后只说明 context 来源，不 remember。

每次 handleTask 都从传入 Task 的 T/R/G 创建 value context（claim.go:67–75）；batch dispatch 传入 daemon 的 parentCtx，而不是其它任务的 child context（daemon.go:5517–5529）。G1/G2 会持有不同 value，G2 不会改写 G1 的 value，也没有“按 T 借最新 G2”的读取路径。`withContextClaim` 只读该 ctx，不访问 daemon 全局状态。原 F2 根因消除。

### taskID guard 实际保证与不保证的内容

- ctx 中为 T1，report.taskID 为 T2：claim.go:84–86 阻止附 T1 tuple。它不会强制报错，而是原样返回 report；若 report 尚为无 tuple/非 required，之后仍可能 legacy。**防错附不等于证明 T2 可以 legacy**，其 required 判定仍有 F1/N1 所述问题。
- 相同 taskID、不同代：单靠 taskID 判断不能识别误用旧 ctx。生产路径再次进入 handleTask 且三字段完整时，新的 WithValue 会遮蔽旧 value，来源是新 Task；这足以关闭原来的 cache overwrite 触发。
- 若未来调用者绕过每次 stamp，直接用 G1 ctx 给同 T 的 G2 report，helper 无法凭 T 区分；或者以同 T、缺字段 Task 调用 stamp，它原样返回继承 G1 的 ctx。这是 context API 的使用前提/残余 footgun，本轮未找到实际生产复用该 child context 的调用路径，不新增确证 P1/P2，但不能泛称“taskID guard 可阻止任何跨代 ctx 误用”。

### 覆盖语义

`claim.go:81–82` 已 required 的 report 始终优先，不被 ctx 改写，包括 required=true 但格式错误的 report——后者随后 fail closed。未 required 的 report 会从匹配 origin 写入两字段；若调用者先塞入未 required 的半 tuple，该 helper 会覆盖而不是先拒绝。当前产品构造/重放/补偿没有发现依赖这种半 tuple 的路径，未新增确证 finding；建议调用约定保持“显式 tuple 必须同时置 required”。

## 3. F3 — CLOSED；kind 不入 key 未引入新的跨代漏投

- foreground：`daemon.go:6475–6478` 调用 `beginTerminalReportDelivery(report.deliveryKey())`。
- mutex map 的插入、查重、release 全使用相同 deliveryKey（6522–6539）。
- replay：`terminal_report_queue.go:957–961` 也用 item.report.deliveryKey，随后 send。
- `execution_terminal_claim.go:45–49`：generation key=T+NUL+R+NUL+G；G1/G2 不同就不同 key。正常 release 删除的也是各自 key，不释放另一代的 gate。

因此旧 G1 replay 阻塞时，前台 G2 不再在 enqueue 前被错误拦截；两代都能进入独立持久化/发送路径。这是静态结论，未由 reviewer 运行并发实验。

### 同代 complete/fail 竞争：必须明确实际行为

同 T/R/G 的 complete 和 fail **仍共用同一 key**。第二个并发 foreground 在 gate 处返回 already-being-delivered 错误，不进入 enqueue、不被自动等待重提；不是把两个 payload 合并成一条，也不是两者都承诺 durable。磁盘同 key 的不同 payload（含 kind）也通过 record 比对报 conflict（queue:408–421）。

这保留原有“一个 generation 一个终态槽、互斥 first attempt”的语义：旧 taskID gate 及既有文件 key 本来就不含 kind；改成 deliveryKey 只分离不同代，没有额外放开同代 complete/fail 并发。不能为修 F3 把 kind 加入 key 而让互相矛盾的两个终态同时独立重放。

**结论**：原 F3 跨代误判 duplicate/未落盘丢失关闭；同代竞争的第二个回调可能不发送，但它不是新引入的独立合法代次漏投。在“同代所有不同 kind 的结果都必须保留/完成优先于失败”的更强需求下，现有机制不提供该保证，不能宣称全量 exactly-once 或两个结果都 durable。本轮未发现 handleTask 正常分支会同时产生两个相矛盾终态；不据假定新需求新增 P2。

串行不同 payload 的 enqueue 冲突后仍可能按既有 availability fallback 直接发请求；这同样是既有设计，不是此次 deliveryKey 修复新引入，也不在这里扩签为完整仲裁证明。

## 4. F4 — CLOSED；新内存/日志/磁盘风险

不再有全局 taskID claim cache，也没有4096条历史成功记录的占位结构；replay ack、补偿成功后无需 forget。旧 F4 的“已交付仍留 cache→后续永久 cache full”链条消失。

origin 只含三字符串值，不保存 daemon、Task、client 或 HTTP 句柄，也不自行启动 goroutine（claim.go:61–75）。正常 context 生命周期跟随本次 handleTask/已存在的 callback detached timeout；没有新增全局引用容器。foreground gate defer release，replay 正常路径显式 release。没有确证新的跨任务持久内存泄漏；如果上层主动长久保存 context，GC 当然不能回收，但本轮未找到新增的此类保存点。

磁盘不保存 context，只保存报告的三元组/required 对应 v3 字段；原 owner-only/ACL、无 token、结果可能敏感、大小/quota 风险沿用前轮，不重做全量文件系统审计。

**新增可接受风险 R-log，非 P2**：`daemon.go:6477` 现在在 busy 错误中格式化完整 deliveryKey，而不是仅 taskID；该错误被调用点 logger 记录时会包含 runtimeID、dispatchedAt 和 NUL（一般会被格式化/转义）。元数据不等于 secret/token，未确证权限泄漏，但应避免直接输出内部二进制复合 key，使用 taskID/kind 及必要脱敏 generation。不能继续声称本次改动没有新增 generation 日志通路。

## 5. 新增 N1 / P1 — 完整 tuple 被误当作 opt-in：普通 PAT daemon 的终态回调升级为 MDT-only，返回403

### 具体证据与生产调用路径

1. `execution_terminal_claim.go:67–75` **只检查 T/R/G 是否非空**，不检查新合同、是否已通过 claim 回读、终态协议 capability 或当前凭据是否适用。因此普通无新合同、但有有效 dispatched_at 的任务同样会被 stamp。
2. 正常服务器 claim 响应即会提供该代次（handler/daemon.go:2730–2735）；此前原实现只有 strict verified claim 才 remember，普通任务不会因此附 tuple。当前 `TestTerminalReportLegacyTaskStaysLegacy`（generation_test.go:346–364）用的是连 RuntimeID/DispatchedAt 都没有的 Task，不能代表当前服务器返回的普通 legacy-contract 任务。
3. `daemon.go:2240–2254` 的 resolveAuth 从 active profile CLI config 直接加载 token 到 d.client，并不把它换成 MDT。CLI 登录路径 `server/cmd/multica/cmd_auth.go:350–353` 保存 patResp.Token；PAT 本来就是正常 daemon 认证路径。
4. `server/internal/middleware/daemon_auth.go:62–76,197–244` 明确保留 PAT/JWT 向后兼容；PAT 分支把认证来源设置为 `DaemonAuthPathPAT`，不是 daemon_token。`server/cmd/server/router.go:1647–1648,1679–1684` 让 daemon API/claim 经此中间件。
5. 新 ctx 被 report.withContextClaim 附到 body，sender 继续用原 d.client 的 PAT 发 complete/fail。
6. `server/internal/handler/daemon_terminal_claim.go:31–41,49–55`：body 一旦含任一 claim 字段就走 qualified；要求真实 MDT 认证路径及其 workspace/daemon，否则 **403 EXECUTION_DAEMON_BINDING_REQUIRED**。这不是普通 PAT 的过期/网络抖动。

### 触发与影响

有效 `mul_` PAT daemon，普通无新合同任务，T/R/G 全部合法且服务器成功 claim。prepare 走 legacy，无须新 claim 验证；终态报告却因 G 存在被强制附 tuple，在当前服务器被403拒绝。此现象不要求 strict 缺字段、不要求跨代或磁盘损坏，是旧支持路径的静态兼容性回归。

前台重试/重放继续携同 tuple、同 PAT，不能自动恢复。403 会进入原永久拒绝计数并最终 quarantine；complete 的 compensation 也保留该 tuple（queue:888–892），仍可能被相同403拒绝。故任务/结果可能无法正常终结，而原完成仅保留 failed outbox。未运行实际 PAT/DB 负例，不把静态预测写成已观察到的线上事件。

### 建议与不允许的“修法”

required/legacy 应由明确的协议/合同模式决定，而不是单由 timestamp 是否存在决定。普通旧合同要维持既有凭据/协议兼容，或经过明确协商、可用的真实 MDT 路径再升级；strict 即便缺 G 也必须 required→拒绝，不得因 F1 回退 legacy。

不能让服务端把 PAT 当 MDT、不能把 token 前缀当已验证 daemon 绑定、不能对 strict 的403剥 tuple重试，以免以兼容性为名制造真正降级。若业务决定把所有旧任务也切到 MDT-only，必须先有显式迁移/凭据供给，不可由本次局部 stamp 悄然完成。

建议下一独立 actor 负例：正常 claim 输出形态的无合同 T/R/G+真实 PAT，原路径可终态而新路径403；对应 MDT qualified 正常；strict 缺 G 不发 legacy。以上仅建议，本 reviewer 未执行。

## 6. outbox/补偿必要回归：未见本次新增的错文件 ack 或 tuple 降级

- enqueue、list、temp恢复、ack、rejection/quarantine 仍使用 report.deliveryKey 对应 hash 文件名（queue:408,536,574,623,678）；本轮 queue 改动只使 flight caller 也采用同一 key。两代文件与 gate 身份一致。
- reportTerminalTask 创建/ack item 均用已 stamp 的 report.deliveryKey（daemon.go:6503,6514–6518），不会因 ctx 后续变化改名；report 是值，origin 字符串是本次值快照。
- replay 直接使用从磁盘还原的 report，不调用 withContextClaim，因此不借 replay worker/root ctx 改写 generation，旧 legacy 重放仍 legacy。
- quarantine complete→fail 补偿复制 runtimeID/dispatchedAt/required（queue:888–890），直接 send（892），没有被 parent ctx 的另一代覆盖；由原 delivery 调用同步执行，原 gate 仍被持有，不是并发放行同代两种 kind。原完成已移入 failed，补偿不覆盖其文件。
- 这些机制对 N1 的兼容性问题无能为力：它们会正确保留“被误升级后的 tuple”，所以403不会通过重放自动消失。

## 7. 未验证、测试文本与快照

仅静态阅读新增的 offline tuple、legacy-empty、两代并发和磁盘重放测试（execution_terminal_generation_test.go:317–477），没有运行。测试文本未覆盖 strict+空 G 的 offline 负例、正常完整 tuple 的 PAT 无合同路径；两代并发 fixture 使用显式 qualified report，不单独证明所有 context 误用安全。未重新认领任何已有 green 为 reviewer 独立动态证据。

当前六文件与 `terminal-fence-20261025T060611Z-finding-green2-source-manifest.json`（2026-10-25T07:16:29.867Z）匹配。最终创建前再核哈希，附于后表。handler/SQL/auth 仅为本次输入/新兼容性 finding 的必要直连只读，不扩展为重审 server terminal 实现。

本报告通过临时评审文本后以 open('xb')（wx/exclusive create）创建最终目标，读回核验；不覆盖原报告或既有 resume 报告，不改产品树。

### 最终 raw SHA-256 快照

| File | Bytes | SHA-256 | Status |
|---|---:|---|---|
| `server/internal/daemon/execution_terminal_claim.go` | 3638 | `26c0a50d6f75a7f97bc605188f6dae5d67868173be3402d52e3d9ec16b7fba05` | MATCH |
| `server/internal/daemon/execution_verifier.go` | 5580 | `f4796e3f8b9a1186abc1ca46eb08df352a094a034ae31f5bcf209bcdbd5e1161` | MATCH |
| `server/internal/daemon/daemon.go` | 487770 | `98bc22df9158c4daa7f41a95b1caf70223fa1d15f06d324fa0ede67609ff50d7` | MATCH |
| `server/internal/daemon/terminal_report_queue.go` | 37999 | `da15ba13c4a9728613fe64ef75d30e356b0a5450c4676efe3e7b82feb2816f6f` | MATCH |
| `server/internal/daemon/client.go` | 61090 | `b1c9868b1489ac52bca552f7d56e63b23d2f2524f12e00f957fc4b77d6badc55` | MATCH |
| `server/internal/daemon/execution_terminal_generation_test.go` | 15589 | `18b22d8ab66103b74fa97ce0bc24dd02fb34e5517d0fa888ebd09c06bc6abaa3` | MATCH |
| `server/internal/handler/daemon_terminal_claim.go` | 2955 | `164e9304d29c6061975eae0159b8d303be9d35136d141e7cb66e4b3141a365af` | supporting read |
| `server/internal/middleware/daemon_auth.go` | 10978 | `2b1a7f534c6fd637ece96a29c14280b4f8615ba1e2fb5ed2dd5c2297eb275ca0` | supporting read |
| `server/cmd/multica/cmd_auth.go` | 20156 | `39cb1d2b3addc8eef97a380ad85fcb2ed5da0e4acd9d302fe0e0a3be3217129d` | supporting read |
| `server/pkg/db/queries/agent.sql` | 148164 | `6a372e24c77de1233ad3dd2b32b6f151d2bf72658a65d0e32786887b27fd9429` | supporting read |

Creation UTC: 2026-10-25T07:23:27.881050+00:00
