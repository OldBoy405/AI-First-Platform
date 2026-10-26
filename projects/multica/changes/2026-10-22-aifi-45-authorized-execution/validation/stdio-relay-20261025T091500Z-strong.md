# AIFI-45 stdio relay — strong 静态复审

## 判定总表

| 项目 | 判定 | 核心依据 |
|---|---|---|
| A：daemon 私有中继整体 | **PARTIAL** | 能启动指定 argv、取 challenge、调 signer、回传所获数据并观察退出；真实 T stdin framing 不匹配，生命周期/reader 清理仍有缺陷。 |
| A1：challenge/envelope 端到端逐字节 | **OPEN（宣称不成立）** | relay→signer 的 challenge RawMessage 保留，但 HTTP json.Marshal 会 compact/HTML escape；envelope 内层 raw token 被保留却套了 T 不接受的外壳。服务器实际签新 payload，不签 challenge JSON bytes。 |
| A2：签发失败时写入 0 字节 | **CLOSED（该分支、静态）** | 签发成功之前没有 stdin.Write；签发返回 error 后只 Close，不进入后面的 Write。返回/回收是否及时是独立未关闭问题。 |
| A3：非零退出只是观察、不证明已绑定 | **CLOSED（观察语义） / OPEN（若称已核验）** | 所有 *exec.ExitError 均允许返回 nil error，包含验证失败、任意 binary 及取消所致退出；并未证明只因 CONSUMPTION_REQUIRED 退出。未发现生产准入消费者。 |
| A4：生命周期/无挂死 | **OPEN** | 未强制 deadline，stdin Write 无独立超时，多个无界 Wait；后续 stdout 不持续消费，WaitDelay 默认 0。 |
| A5：reader 早退无泄漏 | **OPEN** | 扫描结束的 EOF send 不受 ctx 保护；readCtx 也不能自行打断阻塞的 Read。 |
| A6：challenge/stderr 资源封顶 | **PARTIAL** | scanner token/保留 stderr 内容有限；总 stdout budget 漏算换行/空行，stderr 留的是 head 而非 Tail，运行时间/HTTP envelope 无这两个限制。 |
| A7：argv/路径、stderr、challenge 外壳解析 | **PARTIAL** | 无隐式 shell，但 binary/argv/cwd/环境均未建立可信身份；解析不是“唯一键”严格形态，stderr 未净化但当前没日志 sink。 |
| B：签发 client 与服务端 | **PARTIAL** | 四键/URL/合法值/changed 的正常语义对齐；字节承诺不成立，null envelope 等宽松响应未挡，没做 verifier。 |

**确证产品缺陷：F1/P2（真实 T framing 不兼容）、F2/P2（无界等待/停止消费 stdout 的挂死路径）、F3/P2（EOF send goroutine 泄漏）。无确证新增 P0/P1。** 其他字节承诺、解析强度、head/Tail 与空值响应偏差详列，不把它们说成已发生的准入绕过。

## 方法与范围

M：`C:/Users/GOBAO/Downloads/AI/multica`；T：`C:/Users/GOBAO/Downloads/AI/tools`。以下源码路径相对对应根。

只读两份新增产品代码、它们的单测、必要的 Client.postJSON / 服务端编码与解码 / 当前 T stdio 入口和 verifier、指定作者元数据及唯一 wire contract 的相关段落。**未访问 DB；未运行测试、Node、crctl、Podman、vet、编译、生成器或阻塞实验；未修改产品源码/测试；无子代理。** 另一代理 DB 单权保持。报告 wx 独占落盘并回读。

主审 relay.go 为 7,957 bytes / SHA-256 `8c3af9b0fbe5c8de05bedbb0b153af1a9e2b4eee627558aa443a4df442f4ea93`；client.go 为 2,413 / `1be5ce3ba1f35081fa336231afa2aed3f84ff9f35d790d3d8ae9368b0f942aae`。本轮服务端取样 hash 已变，不复核或重签前几轮签发上限/旧锁序结论。配置 strong 身份沿用，actual backend unknown。

## F1/P2 — OPEN：写给真实 T 的 framing 错了，非零退出豁免还会掩盖它

**M** `server/internal/daemon/execution_binding_relay.go:127–150`：写入的是 `{"envelope":<signed.Envelope>}\n`。

**当前 T**：

- `skills/shared/crctl/scripts/lib/execution-binding.mjs:36–46` 的 readProof 读到 EOF、解析整个 stdin JSON，**不取 .envelope**。
- 同文件 `:86–102` 把解析出的整个对象直接交给 verifyExecutionEnvelope，并把验证错误包装成 EXECUTION_BINDING_INVALID/cause_code。
- `lib/execution-authorization.mjs:286–293` 要求 envelope **恰好** key_id/payload_b64/signature 三键。因此只有 envelope 一个键的 wrapper 会在验签之前被拒，底层为 EXECUTION_GRANT_INPUT_INVALID。
- `scripts/crctl.mjs:1584–1594` 直接调用上述函数；只有绑定校验和 source 校验都通过后才到 EXECUTION_CONSUMPTION_REQUIRED。本处 framing 会更早失败，不能把这个非零解释为“绑定已验”。
- 唯一合同 `projects/tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md:86,159` 区分了 **T stdin 单个 envelope** 与 **平台 HTTP 的 {envelope,changed}**。中继不应混淆两层。

这是当前 M/T 源码组合的确定性不兼容判断，**未启动真实 crctl 动态复现**。在正常 T 已发 challenge、服务端已签成功、回管道传输成功的前提下，当前 frame 仍不可能通过该 exactKeys 检查。

relay `:141–150` 把所有 ExitError 视作可观察非零，故这个验证失败仍可得到 nil relay error + 非零 ExitCode，而不是预期的 CONSUMPTION_REQUIRED。这不自动构成产品 fail-open：未发现生产调用点把它当准入。它确实说明“nil error=绑定核验成功”不成立。

单测 `execution_binding_relay_test.go:23–49,90–91,127–131` 的 helper 只是 io.ReadAll、保存收到的 wrapper，再无条件打印 CONSUMPTION_REQUIRED；fixture envelope 甚至不是当前 T 的合法三键/64-byte 签名。该测试能证明写入这些字节，**不能证明真实 T 接受协议**。

## F2/P2 — OPEN：不能从 CommandContext/小 envelope 推出永不挂死

**位置：relay :77–101,117–146,158–173。**

1. **stdin.Write（:130）没有 deadline/cancel-aware writer。** 签名 envelope 没有 relay 本地长度上限，HTTP client 的响应解码也不限体积。就算正常 fixture 很小，管道容量是平台/状态条件，不是接口保证；服务器合法路径字段也能扩大 base64 payload。大于有效缓冲且 child 不读时，Write 可以等待。小于空管道容量的一次写通常可完成，**不能据此说任何 envelope 永不阻塞**。具体 Windows/Linux 缓冲大小与实际 Write 阻塞时序未验证。
2. **即使 Write 成功，child 不退出就会卡 Wait。** :121 的签发失败/EOF 分支、:132 的写错分支都不先 Kill，只 Close 后 Wait；一个忽略 EOF 的 child 也可把失败返回卡住。defer Kill 只在函数能返回/展开时运行，不能解救已经同步等待的同一个 goroutine。
3. **CommandContext 不是自动超时。** background 或未被取消、无 deadline 的 ctx 使它没有必须触发的 Kill。真实 T 有自己的 15 秒 readProof timeout，但 spec.Command 可是任意 child，不能把 T 的实现细节当 daemon 的所有阶段时限。
4. **后续 stdout 可自造相互等待。** readBindingChallenge 返回后没有继续消费 lines；reader 最多再排队一条，之后会在 send 上等 ctx。ctx 直到 relay 返回才 stopReading，而主流程已准备 Wait。child 若继续写足量 stdout，会等管道腾空，父进程会等 child 退出；即使签发成功、stdin 正常读，也存在这个路径。
5. **杀直接 child 不等于清空后代 FD。** cmd.Stderr 为 io.Writer，os/exec 有复制 goroutine；cmd.Wait 会等复制完成。若后代仍持 stderr 写端，缺省 WaitDelay=0 可能等不到 EOF。默认 CommandContext 只 Kill 指定 Process，不证明杀整棵树；继承 stdin 读端的后代也影响 Write 解阻。defer 的“Always reap”是意图，不是所有 FD/树形组合的有界保证。

依据本机只读 Go `src/os/exec/exec.go:262–315,916–977,1065–1085`：默认 Cancel=Process.Kill；WaitDelay=0 可等孤儿进程关 FD；Wait 等进程及 I/O copy；StdinPipe 自动关闭依赖 Wait 观察退出。没有执行这些场景，不把所有具体 OS 调度都当已验证。

**需补的实验（本轮未做）**：可控 child 发 challenge 后不读 stdin/不退出，分别用小 envelope 与大于实测 pipe 容量的 envelope；signer 失败后 child 忽略 EOF；challenge 后持续 stdout；child 退出但后代持 stderr/stdin FD。各在无 deadline 与确定取消/deadline 下观察 Write/Wait 返回、超时、进程树、FD 和 goroutine。不能用测试 helper 自带 60 秒 test timeout 代替产品的时限保证。

## F3/P2 — OPEN：EOF send 可在早退后永久等接收者

**位置：relay :103–105,158–173，尤其 :171。**

普通行 send 有 ctx select；但 scanner 结束后无条件 `lines <- line{err:io.EOF}`，不会响应 stopReading。一个允许的静态交错：

- challenge 先送出并被主 goroutine 消费，readBindingChallenge 返回；
- reader 又把一个后续 stdout 行送进容量为 1 的 channel；
- scanner 随后 EOF，在已满 channel 上发送终止消息；此时没有消费者，且该 send 不看 ctx。

即便进程顺利退出、relay 函数返回并 stopReading，这个 goroutine 也不会退出。这里不是仅猜“有 goroutine 所以可能泄漏”：存在具体不可取消 send 路径。读者还可能阻塞在 scanner.Scan 的底层 Read；cancel 一个普通 context 不会自动中断任意 io.Reader，需所有权正确的 pipe/进程生命周期配合。本轮未做重复调用后的 goroutine/FD 计数实验。

另外 scanner.Err 从未读取：长 token/read error 均被伪装成 EOF，外层 got.err 的一般错误分支实际上收不到 scanner 的真实错误。这仍拒绝签发，但诊断/size 分类不实，不能当 Scanner 已完整报告异常。

## 不变量逐项与其他确证偏差

### “逐字节” — OPEN；签名边界必须区分清楚

- relay `:106–116` 得到的 challenge RawMessage 未主动重建；parse 函数只取内层 object，外层行前后 whitespace/换行本来不在该 RawMessage 中。
- **B client :24–29,55–57 → daemon/client.go:1393–1416** 实际调用 json.Marshal(reqBody)。Go `encoding/json/encode.go:472–486` 会对 Marshaler/RawMessage 的输出执行 appendCompact，且默认 escapeHTML；不仅空白消失，字符串里的 `<`/`>`/`&` 等还可换转义形式。key order 通常保留，不等于 byte-identical。
- `execution_binding_client_test.go:25–30,90–101` 实际断言的是 compact 后 key order，也明确承认 compact；不是宣称的原始字节测试。
- HTTP 返回 envelope 的内层 RawMessage 由 decoder 保留 token，relay append 没重排这个内层对象，但**整段 stdin 不是原 envelope，而是 F1 的 wrapper**。这是两个不同判断，不能相互抵销。
- **服务端实际签的不是 challenge JSON 或外层 envelope 文本。** `governance/execution_binding_issue.go:314–323` 是构造 20 字段 payload→json.Marshal→域分隔签名→base64。T `execution-authorization.mjs:303–307` 验 domain + base64 解出的 payload bytes。challenge 字段语义被映射进 payload；运输包装的 compact/键序变化不自动破坏这个签名。

所以作者报告“服务端按收到 challenge 字节算摘要签名，T 按自身 challenge 字节重算”“重排 envelope 包装会破坏签名”的因果解释均不符合当前代码与 wire contract :159。**逐字节不变量未实现，但也没有因此证实已发生签名破坏/伪造。** 不能为了保留错误说明而给服务端/T 臆造一个 raw-challenge digest 协议。

### 签发失败零写入 — CLOSED；不外推所有错误都零写入

relay `:111–126` 在 signer error 分支只 Close stdin，然后 Wait、返回该签发错误；之前没有 Write。即使 signer 同时返回非空值与 error，该分支也不会使用 envelope。因此中继本身不会先写一段再判断“签发失败”。

当前真实 T `execution-binding.mjs:36–46` 在 EOF/总长度 0 时明确抛 EXECUTION_BINDING_REQUIRED，不把空输入当证明；这与“失败不交证明”一致。任意恶意 binary 可自己声称空输入成功，但那不是 T 的校验语义，也不能成为准入事实。

**Write 失败是另一件事**：:130 的成功签发后写入可能先产生部分字节再报错；不能声称“任何 relay error 都保证 child 从未收到任何字节”。真实 T 对截断/非法 JSON 拒绝；若一个合法证明已完整到达但随后某一步报错，也不能凭本地 error 推断远端从没读过。生命周期 F2 不因零写分支正确而关闭。

### ExitCode/验证状态 — 观察成立，认证不成立

relay `:141–150` 不只接受 CONSUMPTION_REQUIRED；任何 ExitError（包含验证失败、被信号终止、可能的 ctx Kill）都可返回 nil。退出 0 且不验 envelope 的程序同样可返回 result、ExitCode=0；Changed 只是服务器新签/重放，不是 T 验签结果。**代码没有可认证的 Verified/Admitted 证据，ExitCode/Stderr 内容不能替代它。**

定向全 M 搜索 relayExecutionBinding/requestExecutionBinding：relay 除定义只见 unit tests；client 的生产使用者仅 relay，尚未见 handleTask/Agent 准入调用点，亦未见 ExitCode 被这里的产品调用者用于准入。因此没有证实当前实际 fail-open/准入 P1；若未来把 nil error、ExitCode=0 或 stderr 含某串当“绑定已核验/允许启动”，就会错误信任任意 child 输出。

### argv/CR/workspace — PARTIAL，未确认命令注入

- relay `:46–53,77` 直接把 argv 交 exec.CommandContext，**不自动经 shell**；CR/路径中的普通 shell 元字符不会被该 API 自动解释。如果调用方明确选择 sh/cmd/PowerShell 或脚本 eval，则不能靠“用了 exec”排除那个解释器内的注入。
- 不强制 crctl、authorization-bind、--binding-stdio，不校验 executable digest/绝对路径/argv 的 CR 与 spec.CRID 一致性。裸 command name 依 PATH/平台执行规则解析，替换 binary 可以生成自选 challenge 或伪造退出。尚无接受不可信 Command 的生产调用点，故不猜存在实际远程命令注入。
- spec **没有 Workspace 字段**，cmd.Dir/Env 未设置，继承 daemon cwd/环境；workspace 只能由调用者的 argv/真实 T 自行选择。没建立可信工作根/环境隔离，不证明同 UID 防护。CRID 只用于平台 URL；Workspace 不是这个四键 body 的字段。
- B `:45–55` 只挡空 CR，url.PathEscape 处理 URL path segment；服务端仍按 CR 正则/authenticated workspace/task/head 校验，不把它拼成 SQL/本地路径。空白/非法 CR 会被服务器拒绝，不是 client 已验证 canonical CR。真实 T 也有自己的根/grant 检查，但不能把任意 binary 的自报 PID/根替换成 OS 事实。

### stderr 32KiB — 内容 cap 成立，Tail/可信性不成立

relay `:225–240` 的 boundedBuffer **只保存前 32KiB**，后面的写丢弃并返回 len(p),nil。它是内存 bytes.Buffer，不是底层文件/网络：正常 bytes.Buffer.Write 不返回可被吞掉的 I/O error，限额后假报“全部接收”是有意 lossy sink，可持续 drain stderr，不能据此说底层写盘错误被隐藏。

但 StderrTail 是 **head**，不是 tail；决定性的末尾错误可被前面噪声挤掉，stderr 也可能被主动伪造。保存内容有限不代表 CPU/总输出量或进程时长有限，bytes.Buffer/copy goroutine 还有各自固定开销。Wait 后取 String 通常已与 exec stderr copy 同步，本片未见必须成立的数据竞争。

不净化换行/ANSI/控制字符，所以未来不安全地拼接到日志/TUI 会有日志/终端注入风险；当前新增代码没有 logger sink、生产消费者也未见，**未确认已经发生的日志注入路径**。“never logged wholesale”只是注释，不是返回值附带的强制策略。

### 128KiB / parse shape — PARTIAL

- relay `:163,186–193` 限 scanner token，并累计 **len(scanner.Text())**。ScanLines 已剥换行，空行计 0；持续空行不耗 seen budget，即使接收总字节远超 128KiB 也可继续等。故“总 stdout 128KiB”不实，但没有因此发现无界单个 stdout buffer 分配；它主要是时长/CPU、协议资源界限问题。
- T 128KiB 限的是 **stdin proof**（T :36–42），不是 daemon 从 stdout 读到的 challenge；服务端整个 request 又有自己的 64KiB 限额。三者不是同一个方向/同一个预算，不宣称 relay 接受的任意 128KiB challenge 都可由服务端签。
- `parseBindingChallengeLine`（:205–221）用 typed struct json.Unmarshal，**忽略 extra 键**，还允许 JSON struct 的 case folding/重复外层键最终取值；注释“only key”与行为不符。测试 `execution_binding_relay_test.go:192–201` 反而把 extra:2 固定成 accepted。
- strings.Contains 只是廉价启发，不是校验：合法 JSON key 若采用 Unicode escape 而原文不含该字面串可能被漏掉；无关值含该串也会进入下一层。真正保证 object 的是 Unmarshal/RawMessage 首字符检查。若合同要 exact wrapper，应按合同严格拒 extra/重复/大小写别名；不是把 substring 当安全边界。
- 不因此推导服务端接受非法 challenge：inner challenge 会经过服务器的严格键集/UTF8/duplicate 检查，真正认证与签名仍在那里。这不是已确认的绕过 server scope 方式。

## B — PARTIAL：正常四键契约对齐，宽松与“字节”声明需限定

**源码：`execution_binding_client.go:24–29,44–63`；直接 server decoder：`execution_binding_issue.go:337–456,466–480`。**

对齐的部分：

1. struct 恰好 task_id/runtime_id/dispatched_at/challenge，无 omitempty；正常 marshal body 是四键，client URL 是真实绑定 route。服务端 exact 四键，inner exact 12 键；extra/缺键/大小写别名拒绝，不悄悄接受 client 扩字段。
2. 空字符串 CR、len=0 的 challenge 在网络前返回；无效 RawMessage 也会在通用 json.Marshal 时失败。服务端验证 canonical task/runtime UUID、UTC canonical generation、challenge 类型/字段，与当前合法 tuple/T challenge 正常语义对齐。
3. **服务器不要求整份 JSON 的唯一 whitespace/key-order 编码。** ValidateExecutionJSON（execution_authorization.go:446–465）拒 invalid UTF8/重复键/多文档；具体字段有 canonical 约束，整体 body 可以有空格/不同顺序。RawMessage compact 不会仅因此被拒绝。
4. server 正常响应 {envelope,changed}；client Changed 直接取 bool，不取反。true 表示新落行，false 表示旧 envelope 回传；它不是任务准入/消耗/验证状态。此处不重审 head/claim 的 freshness 或上限锁修复。
5. 200 缺 envelope 时 RawMessage len=0，确实报 no envelope；非 2xx 会从 postJSON 返回 requestError，429 不会被默默当成功。**这里调用 postJSON，不是自动 retry/outbox**，不能把以前 terminal 的 429 分类移植成 binding 已有持久重试保证。

仍未覆盖/不对齐的强承诺：

- **null 不等于 len=0**：200 `envelope:null` 会留下 4 字节 RawMessage，当前检查通过；string/array/空对象也无形态/签名校验。实际正常服务端生成三键 envelope，因此这是宽松 client 的确定性行为，不是本轮确认平台会产生 null。T 原本应负责验签；nil client error 不能说一定得到可用证明。
- response 未用 exact field set/重复键/单文档 EOF 检查，Changed 缺失/null 可默认为 false；不能从任意宽松 200 推出可靠 replay 事实。通用 postJSON 接受全部 2xx，响应 Decode 也无尺寸 limit；不是“仅 200 + 有效可信 envelope”严格边界。
- client 没做 UsesDaemonToken 预检；错误凭据由真实 DaemonAuth 拒绝，不因此确认 PAT bypass。mock HTTP 单测的 token 字面值不是认证集成证据。
- Challenge/Envelope 的签名解释及原始字节承诺见前节；合法 schema 不靠字节顺序来保证真实性。

## 作者证据与尚未验证的点

只读 client green2 meta：**7 RUN/7 PASS，6 leaf**；relay-green2 meta（09:39:34.983Z）：**14 RUN/13 PASS/1 SKIP，11 leaf**，exit 0。SKIP 是 helper-only 的入口，本轮未运行；元数据称原库不变/清理是作者记录，不是本评审 DB 确认。

单测是 helper test binary + fake signer、httptest mock endpoint；relay test 验 wrapper 与预先写死的错误串，不调用真实 T verifier，client test不经过真实治理 handler/DaemonAuth。它们不覆盖 F1 的真实协议、不覆盖不读/不退出/继承 FD/reader 早退压力，且明确只验证 compact 后键序，不验证端到端原始字节。

需要动态证据的清单已列于 F2/F3；真实 M→HTTP→当前 crctl 的 stdio 校验及结构化底层 cause 区分也**未验证**。静态切片审阅已完成，不因未跑动态把整体统称 INCOMPLETE；确证静态缺陷仍 OPEN。

**最终：A PARTIAL，B PARTIAL；F1/F2/F3 三项 P2 OPEN；签发失败前零写入 CLOSED（不含终止时限）。没有确证生产准入漏洞或新增 P0/P1。**

**不签消费/准入/activation/隔离域/全局 C1/Gate3；PID/根仍是 daemon 转述，不是本轮 OS 身份证明；旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；消费 closed/off。**

## 发布前文件身份复核

UTC：`2026-10-25T09:48:00.858917+00:00`。四份主文件匹配 relay-green2-source-manifest（09:39:34.999Z）；服务端/T/作者报告匹配本轮读取样本。M/T 标记分别指前述两个仓库根。

| 文件 | bytes | raw SHA-256 |
|---|---:|---|
| M/server/internal/daemon/execution_binding_client.go | 2413 | 1be5ce3ba1f35081fa336231afa2aed3f84ff9f35d790d3d8ae9368b0f942aae |
| M/server/internal/daemon/execution_binding_client_test.go | 7038 | 3447179ba58f907a7f06b24ba7338b26e6a88601106a3d42438f9202e632bd5d |
| M/server/internal/daemon/execution_binding_relay.go | 7957 | 8c3af9b0fbe5c8de05bedbb0b153af1a9e2b4eee627558aa443a4df442f4ea93 |
| M/server/internal/daemon/execution_binding_relay_test.go | 7537 | dcf43db1dc4c1adbc505417797b5853b141db273e9367001cd7d6c4c4fedeed3 |
| M/server/internal/governance/execution_binding_issue.go | 22090 | d961424d2d69b337350175afec36751ae5b48eeb5f642a4e094eaac74e4e6b0d |
| T/skills/shared/crctl/scripts/lib/execution-binding.mjs | 7262 | 8fe71e0f5fc48a524763a63641a43052fff78fc25868017669516297b03ba95d |
| T/skills/shared/crctl/scripts/lib/execution-authorization.mjs | 22367 | 71437e20ddfdf33b74d3490c7129359562443555d1abc0a44886b27f32c34abc |
| T/skills/shared/crctl/scripts/crctl.mjs | 384476 | d064100fc82d07f5ab63d0bd40e824f56cac57699b512f0cd1cf86f1ebca1557 |
| validation/stdio-relay-20261025T091500Z-report.md | 5227 | ee3d2d62eeb6e070ee15d8e7c805b9bd3337ccbb1466467168793d7999309545 |

直接 helper/契约的发布时样本（非作者历史执行 pin）：

- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/daemon/client.go` — 61517 bytes，raw SHA-256 `916edf84ef90c6749d026a9de7ca478d9e6b788360ddf98ce0ccdbfb68eaa01d`。
- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/governance/execution_authorization.go` — 44721 bytes，raw SHA-256 `0c68aca15dd2a57e8a407e5f76a98df264ceec52b31a38433a618cf4ba96a074`。
- `C:/Program Files/Go/src/os/exec/exec.go` — 45089 bytes，raw SHA-256 `3ec96eeef97a375aa5e39663961f8adf3177db9449dacd3c407fd258bc9a2498`。
- `C:/Program Files/Go/src/encoding/json/encode.go` — 40011 bytes，raw SHA-256 `8ff45e82c60c6e29d11fe57ce0c59d79f40ef0d53be28ac36617482a7463b217`。
- `C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md` — 35699 bytes，raw SHA-256 `b39227b95d911063e271c4845ea4f849fb513024e05f026aa1b2aa1540bddb89`。
