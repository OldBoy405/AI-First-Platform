# AIFI-45 stdio relay — strong resume1（仅三项 P2 修复）

## 三项结论

| 上轮 finding | 判定 | 本轮行号依据及限定 |
|---|---|---|
| P2-1 / F1：T stdin framing 不匹配 | **CLOSED（静态协议形态）** | `execution_binding_relay.go:145–155` 写裸 envelope + LF；T `execution-binding.mjs:36–46,86–102` 解析整个 stdin，`execution-authorization.mjs:290–306` 接三键 envelope。旧多包一层的根因消除。未运行真实 T 验签互通，不签全链。 |
| P2-2 / F2：无界 Write/Wait/进程回收 | **PARTIAL** | relay `:86–103` 补无 deadline 时 30s ctx 及 WaitDelay=5s，覆盖常见直接 child 挂住、Wait 内 stderr pipe 不 EOF；但直接 StdinPipe.Write 的特定继承句柄组合仍不保证被 WaitDelay 解阻，见下文 Go 实现分支。不能签任何情况下 30s/35s 必返。 |
| P2-3 / F3：reader EOF send 泄漏 | **CLOSED（原不可取消 send 根因）** | relay `:119–120,183–195`：普通行及 EOF send 均可响应派生 ctx；满 channel/调用者早退后不会再因这个 EOF send 永久停住。底层 Read 的关闭仍属于 P2-2 的进程/FD 生命周期边界，非“任意 io.Reader 仅取消 ctx 就能中断”。 |

**无确证新增 P0/P1，无新增独立 P2。P2-2 是上轮同一生命周期 finding 的残余，不重复计数。**

**明确更正字节问题：HTTP compact/等价转义不导致当前协议的签名失败，不是第四项真实签名/互通缺陷。** 上轮把“端到端逐字节：OPEN”作为表格项，易被读成验签障碍；本轮收窄并更正为“字面原样传输承诺不成立，但这种运输格式变化本身不是功能或签名缺陷”。上轮正文已经指出服务器不签 challenge 原文；不能同时让 OPEN 摘要继续暗示相反因果。F1 的旧 wrapper 则是真实形态错误，现已独立修复。

## 方法与范围

M 根：`C:/Users/GOBAO/Downloads/AI/multica`；T 根：`C:/Users/GOBAO/Downloads/AI/tools`。M 源码路径默认在 `server/internal/daemon/`，T 库路径默认在 `skills/shared/crctl/scripts/lib/`。仅三项 P2、用户指定的 null/head 附加变更，以及回答四问所必需的服务端/T/Go helper。

**未访问 DB；未执行测试、Node、crctl、Podman、编译、vet、生成器或阻塞实验；未修改产品源码/测试；未用子代理。** 另一代理 DB 单权保持。仅静态读取、hash/解析作者文件，报告 wx 独占创建并回读。

主 pin：`stdio-relay-20261025T091500Z-relay-green3-source-manifest.json`，09:49:25.138Z。最终回读 relay 8,985 bytes / raw SHA-256 `bc5cc094b9625fd90ee57556ebaff60a0eaf57c3da6e2d67fbf9534737b52a68`；client 2,652 / `770c58eddc28c3a6e0ea9461d423727f0a40bf207ac158be240688a863a21ce0`。采样中曾见 relay 同长度的 `76f7db9b06d538ac3d51fceb1236904e9bec40331701b153225cf24aef9e938e`；随后重新读取与 raw/LF hash 均回到 green3 的 bc5c…，不猜中间态来源/内容。本结论以最终样本及发布前复核为准，不把混合身份当动态证据。configured strong 身份沿用，actual backend unknown。

## P2-1 CLOSED：裸 envelope + 换行与当前 T 解析相容

- relay **:148** 直接写 `signed.Envelope` 加一个 LF，不再有 `{"envelope":...}` 的 stdin 外壳；随后 **:156** Close 使 T 能读到 EOF。
- `execution_binding_relay_test.go:125–134` 既比较完整 received 与裸 envelope+LF，又显式拒 `{"envelope":` 前缀。此测试仍是记录字节的 test-binary helper，不是 T crypto verifier，但对原 framing 根因有静态鉴别力。
- T **execution-binding.mjs:36–46** 聚合 stdin，空输入拒绝，整段交 parseExecutionJSON；**:100–102** 将整个解析结果当 envelope 送 verifier。
- T **execution-authorization.mjs:48–55,64–74** 用 fatal UTF-8 decode 和 JSON.parse，并进行 token walk。JSON 语法允许文档末尾 LF；token walk 的 `\s` 不把这个换行当数据 token，不会增加 key。
- T **:290–307** 验 envelope 三键及 base64 解出的 payload，不把 envelope 文本末尾 LF 拼入签名输入。

所以 **有效裸 envelope 外部追加 LF 是安全运输 whitespace**，不会改变 payload 或签名。还须满足 T 的 128KiB 总 stdin cap（execution-binding.mjs:39–41），该 cap 包括 LF；不能把“换行安全”说成任意超长文档也接受。本轮未跑实际 T 正/负验签，故仅关闭原 framing 源码根因。

## P2-2 PARTIAL：30s/5s 的有效范围与残余

### 已修好的常见路径

relay **:86–89** 仅在 caller ctx **没有 deadline** 时创建 30s context；不是固定等待 30s，也不是 `min(caller deadline, now+30s)`。若 caller 已有较长 deadline，就沿用较长的；已有更短 deadline 也沿用。**:92** 将该 ctx 给 CommandContext，**:103** 设置 WaitDelay=5s。

对一个没有持管道后代的普通 child：超过有效 ctx 截止会触发默认 Process.Kill；已进入 Wait 的调用能回收，readCtx 的 send 也可被取消。原先 background 下 child 永不退出而父进程永久 Wait 的常见反例因此得到实质缓解。新增 30s 是 deadline，不是人为睡眠。

### 问 1：父 ctx 未取消、child 正常 exit，WaitDelay 是否无影响？

**只能在 pipes/copy 正常及时结束时回答“无影响”，不能无条件确认。**

依据本机只读 Go `C:/Program Files/Go/src/os/exec/exec.go`：

- **:935–970** Wait 先等 Process，再处理 ctx/copy，最后 close parentIOPipes；
- **:981–1007** 若 copying goroutine 已完成会立即返回，甚至不创建 timer。因此普通 child 退出并关闭流，不会故意再等 5s，更不会等满 30s。
- **:1005–1018** 即使父 ctx 尚未取消，只要 Wait 已观察 child 退出而 I/O copy 仍未完成，也会启动 WaitDelay；5s 后关管道并返回 ErrWaitDelay。

所以对“主 child 正常 exit=0，但孙进程持 stderr 写端”的情况，行为**刻意改变**：原本可能永久等 EOF，现在可在 WaitDelay 后关闭受管 pipe，返回 ErrWaitDelay；relay **:159–163** 会把非 ExitError 的 Wait 错误作为 relay error。若 child 本来非零，Go Wait **:964–967** 保留既有 ExitError 优先级，copy 的 ErrWaitDelay 未必成为最终错误，relay 仍可能按既有观察语义返回非零 ExitCode、nil relay error。此处不能把 nil 解释为验证成功。

**对已进入 Wait、stderr copy 因孙进程继承而不 EOF 的典型情况，WaitDelay 确实有用。** 它不杀整棵树，只关闭/结束父进程自己的相应 I/O 等待。孙进程本身是否存活/回收，本轮未验证。

### 仍不能签“覆盖所有继承 pipe 的 Write”

关键是 relay **:148 的 stdin.Write 在 Wait 之前，并非 os/exec 管理的 stdin-copy goroutine**。StdinPipe 的返回端由调用者直接写（Go exec.go **:1071–1085**）；本 relay 因 Stderr 是 boundedBuffer 才有库内 io.Copy（**:591–615**）。WaitDelay 不等于对每个调用者的直接 Write 设置 deadline。

本机可读 Go 实现给出一个仍需验证的残余分支（不是本轮实际运行）：

1. child 发 challenge 后不读 stdin；spawn 后代保留 stdin 读端但把 stderr 重定向/关闭，自己等待。父 relay 写大于有效 pipe 缓冲的合法对象 envelope，在 **:148** 等待，尚未调用 Wait。
2. 30s ctx 到期，CommandContext 默认 Kill 直接 child；后代仍持 stdin 读端且不读，故不能只靠直接 child 退出保证 Write 解阻。此时 stderr-copy 可以已经 EOF。
3. Go `watchCtx` **:837–842** 的 timer 不能交给尚未调用的 Wait；到期后执行 **:860–889**。若 `c.goroutineErr` 已就绪，走 **:862–868**，**不会**执行只有 default 分支 **:878** 才做的 closeDescriptors(parentIOPipes)。最后向 Wait 的结果通道发送，而 Wait 仍未被调用。
4. 直接 stdin writer 可继续等后代，因而不能从这两个常量证明必在 30s+5s 内返回。特别不能把文档中的“关闭 I/O pipes”概述理解为任何情况下都主动关闭所有用户手写端。

这是已读 Go 版本的静态路径分析，**具体可复现的 OS 句柄继承/pipe 容量、实际编译运行的 Go 版本、超时精度与错误返回未验证**。因此只给 P2-2 PARTIAL，不伪称已复现永挂，也不因补了两个 timer 就签全部关闭。不同 Go 实现/版本的细节须用目标环境核对。

此外 ctx 是合作式取消：已审 Client 的 HTTP 使用 NewRequestWithContext（client.go **:1423–1436**），可遵从截止；不能据此保证任意自定义 signer 都会返回。停止消费后续 stdout 的结构仍在，但对普通直接 child，deadline 可在之后终止它；这不是证明它现在不会短时卡住。

**所需实验，均未执行**：不读/不退出的 child；大于实测 pipe 容量的 envelope；child 退出但后代只保留 stdin、stderr 已 EOF；后代只保留 stderr；持续 stdout 后等待。分别验证有/无 caller deadline、正常 child exit=0/非零、DeadlineExceeded/ErrWaitDelay/broken-pipe 的返回与优先级，并观察进程树/FD/goroutine。当前 helper 正常收完 stdin 的 GREEN 不代替这些实验。

## 问 2：T 的 15s 与 relay 的 30s，不是固定串行等待

T **execution-binding.mjs:84–98** 发 challenge 后启动 readProof/15s race；到时 destroy stdin 并拒绝。relay 的 30s（无 caller deadline 时）在启动 child **之前**就开始，覆盖另一个起点/阶段；不是“先等 T 15s，再额外等 30s”。

分情况：

- **relay 已在 Wait，T 于自身 15s 后实际退出、stderr/其他管道正常关闭**：Wait 立即按退出状态返回，不会等 relay 30s 截止，不额外固定等 5s。
- **relay 尚在同步 signer HTTP**：child 退出不自动 cancel 这个 HTTP ctx。即使 T 在约 15s 已退出，relay 仍可等 HTTP 完成/有效 ctx 到期，所以调用者确实可能等待超过 T 的 15s；无 caller deadline 的通常上限来自整个 relay 的 30s ctx，但不含上述未关闭 I/O 残余与必要 cleanup。不是“子进程退出就自动瞬间结束签发”。
- **HTTP 在 T 退出后才成功**：无继承读端时后续 Write 通常是 EPIPE/Windows broken pipe；具体结果依时序，未实测。relay **:148–154** 会返回 `write envelope` 包装错误，并记录 child 的 ExitCode/StderrHead；它不会自动把该错误转换成 T 的 EXECUTION_BINDING_UNAVAILABLE 或 EXECUTION_CONSUMPTION_REQUIRED。若仍有 reader，Write 也可能成功，随后只观察到 child 非零退出。
- **HTTP 自己失败/截止**：**:132–141** 保留签发错误作为返回值；其间即使 child 也已退出，错误优先级仍是签发分支，而非自动改成 child 原因。

因此**确有超过 15s 的占用可能，也有 transport error 与 T 业务拒绝不是同一分类的情形**。这是需要区分的观察语义，不证明准入放行或新独立 P0/P1。上层不得把 nil relay error、某个 ExitCode 或任一 stderr 字串当验证/准入信号；本片没有为这种用法签字。动态调度、业务调度器卡顿效果、错误优先级的运行记录未验证。

## P2-3 CLOSED：原 EOF send 的不可取消路径已消除

relay **:119–120** 的 readCtx 派生自有效 relay ctx，函数返回 defer stopReading；父 deadline 到期也向它传播。普通行 send **:183–187** 与 EOF send **:191–195** 都有 ctx.Done 分支。

上轮具体交错“challenge 返回→一条额外行占满 channel→EOF send 永远等消费者”现在在 ctx 取消时可以退出。若 channel 与取消同时 ready，select 即使选 send，也完成一次发送后结束 goroutine，不会再落入无条件永久 send。因此该原根因静态 CLOSED；不因尚未跑 goroutine 压测就写 PARTIAL。

仍不声称 context 会打断任意 io.Reader 的 Read。scanner.Scan 的 I/O 需要对应 pipe 生命周期结束；前述 P2-2 保留了该生命周期边界，不将 EOF-send 的修复外推成所有 FD/树形组合无泄漏。本轮没有做重复调用后的 goroutine/FD 动态计数。

## 问 4：准确的签名字节边界与前次更正

### 哪一段字节会变？

1. **child stdout → relay 提取出的 challenge RawMessage → signer 入参**：未重建 challenge object；只取内层 token，不包括 stdout 外壳/行分隔。
2. **Client → HTTP request body**：`execution_binding_client.go:26–30,56–58` 经过通用 `client.go:1413–1420` 的 json.Marshal；Go `encoding/json/encode.go:472–486` 对 RawMessage 做 appendCompact，并按 escapeHTML 处理等价转义。因而原本无意义空白可能消失，字符串中的 `<`/`>`/`&` 可变成转义编码。不能宣称这一步 byte-identical；但对合法输入这些变化保持字段值。
3. **服务端新建 signed payload**：不是把 HTTP 原文签下去，见下一节。
4. **HTTP response 的 envelope 运输包装 → client → child stdin**：client **:60–65** TrimSpace 只去对象外部 whitespace，relay **:148** 追加外部 LF，不重建 payload_b64 的内容。外层 envelope 的空白/键序也不是签名输入；其 exact key/value/schema 仍须满足 verifier。

### 服务端签的到底是什么？不是“challenge 原文”或“整个 challenge 的摘要”

`server/internal/governance/execution_binding_issue.go`：

- **:265–274** 明确新建 executionBindingPayload。schema/key/作用域/资源来自服务端事实，runtime/task 来自已核 run；根、PID、operation/tools 等使用已解析并校验/转述的 challenge 字段。
- **:269 的 Challenge: challenge.Challenge** 是 T 产生的 64hex **nonce 字段值**，不是 `SHA256(raw challenge JSON)`，也不是整个 challenge 原文。
- **:271 的 HeadDigest: head.GrantDigest** 是授权 grant 的 digest，不是挑战 JSON 的摘要；其他 policy/template/tools digest 也各有自己的含义。
- **:314–323** 对这个自建结构 json.Marshal 得到 raw payload，然后构造 payload_b64 并签 `executionBindingSignedBytes(raw)`。
- **:100–101** 签名输入严格是 `execution-binding/v1\0 || raw_payload_bytes`。

T **execution-authorization.mjs:294–307** base64 解 payload，验该域和原 payload bytes；**execution-binding.mjs:104–124** 再比较 nonce/根/PID/operation/head/部署事实等字段。

### 变了之后谁会失败？

- **HTTP challenge 只 compact/等价转义/重排同值字段**：没有一方仅因这种运输编码变化验签失败。服务器消费字段，T 不重算 raw-challenge JSON 摘要；它比较自己的 nonce 等字段与已验签 payload。
- **签名完成后改 payload_b64 解出的 payload bytes，即使只是改 payload 内部空格**：T 的 crypto.verify 会失败；这才是必须逐字节保存的加密边界。
- **只重排外层 envelope 三键、改变其无意义 whitespace/等价 JSON 转义**：只要 decoded key/value 与严格形态不变，不改变签名输入，不因此失败。重复键/非法 UTF-8/多文档等仍可被严格 parser 拒绝，不能推成“任何 JSON 改动都安全”。
- **改变 challenge 的语义值**：可能被服务器拒绝；若服务器对新值确实签了新 payload，签名本身仍可有效，但原 child 会在 expected-field 比较处拒绝。这与“格式变化使密码学验签失败”是不同原因。

**更正结论**：前次 OPEN 只适用于字面“所有运输 bytes 不变”的不准确承诺。若把它视为当前实现的实际验签缺陷，我明确撤回这种解读；它不构成第四项 P2，也不阻碍本轮 P2-1 关闭。源注释仍有“sign exactly those bytes / signature covers raw envelope”的宽泛说法，宜按上述真实边界理解；本轮不改源码。

## 附加变更限定确认

- **client :60–65** 的对象形态检查会拒 missing/空、null、string、array、number 等非对象 envelope，原 null 漏挡已修；但空对象仍过，尚不等于三键/密码学验证。这个薄 client 仍由真实 T 做 verifier，本轮不重开 response 其他严格性。
- **relay :245–263** 注释确实称保存 stderr head，符合实现；字段名仍叫 StderrTail，不能据名字假定最后 32KiB。它不成为可信业务 cause/日志安全策略，本轮无新独立 finding。
- 原签发失败零写入仍在 **:127–141** 成立；Write 错误可有已写部分字节，不扩大成所有 error 都零字节。

## 作者证据、未验证与最终边界

只读 `relay-green3.meta.json`（09:49:20.208Z）：**14 RUN / 13 PASS / 1 SKIP，11 leaf，exit 0**；原库保全/资源清理由作者记录，本评审未操作/验证 DB。主单测仍是 helper test binary + fake signer、mock HTTP；本轮新增裸 frame 与 null 断言，不是实际 T 验签、WaitDelay 继承 FD 或 goroutine 压力的证据。

**P2-1 CLOSED；P2-2 PARTIAL；P2-3 CLOSED 原 send 根因。** 裸 envelope/LF 源码协议对齐；普通退出不额外等 30s，正常 EOF 不固定延迟 5s；但 WaitDelay 对正常 child exit 后遗留 stderr 的等待会改变行为，对“直接 Write、后代只持 stdin、stderr copy 已完成”的范围不能签全覆盖。相应目标环境实验、实际 Go 构建身份、动态错误分类与任务调度影响**未验证**。不因没有动态运行把已完成的静态复核统称 INCOMPLETE。

**不签消费/准入/activation/隔离域/全局 C1/Gate3；旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；消费 closed/off。**

## 发布前身份复核

UTC：`2026-10-25T09:56:45.304948+00:00`。四份主文件最终全部匹配 green3 manifest（含 relay bc5c…）；服务端/T 匹配本轮读取样本。M/T 为前述根。

| 文件 | bytes | raw SHA-256 |
|---|---:|---|
| M/server/internal/daemon/execution_binding_client.go | 2652 | 770c58eddc28c3a6e0ea9461d423727f0a40bf207ac158be240688a863a21ce0 |
| M/server/internal/daemon/execution_binding_client_test.go | 7062 | f4e0d68c424943f2da0dca888d1a2e0208ababae6b43fe5ec6afaf7179704250 |
| M/server/internal/daemon/execution_binding_relay.go | 8985 | bc5cc094b9625fd90ee57556ebaff60a0eaf57c3da6e2d67fbf9534737b52a68 |
| M/server/internal/daemon/execution_binding_relay_test.go | 7871 | d79466053f181f6f478743619d02bba7f26b1c8f81e18a6d79b54c2eaed5b953 |
| M/server/internal/governance/execution_binding_issue.go | 22090 | d961424d2d69b337350175afec36751ae5b48eeb5f642a4e094eaac74e4e6b0d |
| T/skills/shared/crctl/scripts/lib/execution-binding.mjs | 7262 | 8fe71e0f5fc48a524763a63641a43052fff78fc25868017669516297b03ba95d |
| T/skills/shared/crctl/scripts/lib/execution-authorization.mjs | 22367 | 71437e20ddfdf33b74d3490c7129359562443555d1abc0a44886b27f32c34abc |

直接 helper 发布时采样（非真实执行 Go/平台身份 attestation）：

- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/daemon/client.go`：61517 bytes，raw SHA-256 `916edf84ef90c6749d026a9de7ca478d9e6b788360ddf98ce0ccdbfb68eaa01d`。
- `C:/Program Files/Go/src/os/exec/exec.go`：45089 bytes，raw SHA-256 `3ec96eeef97a375aa5e39663961f8adf3177db9449dacd3c407fd258bc9a2498`。
- `C:/Program Files/Go/src/encoding/json/encode.go`：40011 bytes，raw SHA-256 `8ff45e82c60c6e29d11fe57ce0c59d79f40ef0d53be28ac36617482a7463b217`。
