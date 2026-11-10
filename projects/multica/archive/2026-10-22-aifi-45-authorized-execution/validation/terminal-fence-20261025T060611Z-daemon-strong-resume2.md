# AIFI-45 daemon resume2：N1 与 HTTP client/vet 修复复核

## 范围和结果

业务根：`C:/Users/GOBAO/Downloads/AI/multica`。以下未加前缀的 Go 文件位于 `server/internal/daemon/`。

只复核 N1 credential gate、terminalClaimHTTPClient 的 vet 修复及题目指定的 strict preflight/认证/重试直连行为。不重读全量，不重新签前轮 F2–F4、server terminal、outbox 全链。**未访问 DB、未跑测试/vet/编译/生成器、未改源或测试、未使用子代理**；没有使用另一个代理持有的 DB 执行权。仅只读、哈希和创建报告。

模型声明沿用既有交接：configured strong `OpenAIPersonal/gpt-6.1-sol/high`，actual backend model unknown，未重新做模型发现。

| 本轮修复 | 判定 | 限定结论 |
|---|---|---|
| N1：普通 PAT/nil-client 被误升级为 qualified | **CLOSED** | 新鲜生产 parent context 下，非 strict 的普通任务不再仅因有 G 就在 PAT/nil-client 下被附 tuple；完整合法 MDT tuple 仍附。 |
| vet：复制含 mutex 的整个 Client | **CLOSED** | 已改为只复制 http.Client；直接调用相同 retry helper，未发现此重构新增 P0/P1/P2。 |

**不能因此签全部修复通过**：组合检查确认 **N2 / P1：PAT+strict+runtime-offline 即使完整 tuple 仍降 legacy**，详见第四节。它是本轮 credential gate 扩出的回归变体，与旧 F1 共享“缺少 required 状态”根因，不把同一根因重复累计两项风险。原 F1 的 MDT+缺 G+offline 也仍未关闭。除此之外，未新增确证 P0/P1/P2。

限定静态复核完成。不签完整 terminal 链、生产准入、Gate3、全局 C1、完整 TC/major，不补旧 claim 锁序 INCOMPLETE。

## 一、N1 修复：CLOSED，但不是“前缀证明身份”

### 正常输入路径

- `client.go:258–264`：UsesDaemonToken 对 nil receiver 安全，实际是 `c != nil && strings.HasPrefix(strings.TrimSpace(c.token), "mdt_")`。
- `daemon.go:5747–5749`：仅该方法为 true 时调用 withTerminalClaimOrigin；此 gate 在 runtimeIndex 检查和 offline 早退之前。
- `execution_terminal_claim.go:67–75,80–91`：完整 T/R/G 被保存在本次 run ctx，随后在 matching taskID 的未 required report 上附加。已 required 的报告不被覆盖或降级。
- `daemon.go:6474–6477`：在持久化、flight、网络之前 stamp/验证；`execution_terminal_claim.go:17–40` 拒绝 required 的无效 tuple，没有错误后剥 tuple 重试的分支。

因此普通无新合同的 PAT 任务不再因正常 claim 响应带 dispatched_at 被强制送入 MDT-only terminal 分支。正常已配置的 MDT daemon、完整合法 T/R/G 仍为 qualified；gate 并未把这一正常情况降级。该条件不是新授权证据，实际身份仍由服务器判定。

PAT/空 token/nil client 的 UsesDaemonToken 为 false；无上游 origin、无显式 qualified report 时保留 legacy。这里不表示无 token 请求能通过服务器认证，也不表示显式 required 的 report 会因当前凭据为 PAT 而被剥 tuple。既有 generation outbox 和补偿的 tuple 不经过这个 gate 擦除。

### 前缀、伪造和空白

`server/internal/middleware/daemon_auth.go:107–160`：服务器从实际 Authorization 去掉精确 `Bearer ` 后按原始 token 的 mdt_ 前缀选择 MDT 分支，再对完整 token 做 hash/cache/DB daemon-token lookup，只有查到真实身份后才设置 DaemonAuthPathDaemonToken/workspace/daemon。PAT 分支（200–244）设置 DaemonAuthPathPAT；不能仅靠客户端布尔值设置这条身份路径。

| token 形态 | 客户端分类 | 服务端含义 |
|---|---|---|
| 空、空白、nil Client | false | 没有因此获得认证；正常请求仍可能401。 |
| 正常 mul_ PAT、mcn_、JWT | false | 不当 MDT；原有中间件认证路径保持自己的标签。 |
| 合法 mdt_ token | true | 仍须真实 token 验证和 scope 检查。 |
| 只有 mdt_ 或随意伪造 mdt_… | true | 只是 wire 分类提示；token lookup 失败会401，不能伪造 daemon identity。 |
| 把 PAT 文本改成 mdt_ 前缀 | true | 服务器走 MDT lookup，不会因为 PAT 表有某个 token 就回退认证成 MDT；不是权限绕过。 |
| MDT_ 大写 | false | 服务器也区分大小写，不会当成合法 mdt_。 |
| mdt_ token 前后带空白 | TrimSpace 后可能 true | 客户端发送并未相应 TrimSpace，不能声称与服务器原始 token 判定完全相等。 |

空白的具体说明：`client.go:1429–1431` 仍把原 c.token 拼入 Authorization；middleware 不为 token 再做 TrimSpace。尤其前导空白可能导致服务端不进 MDT 分支/认证失败；尾部空白还可能受 HTTP 层 OWS 处理影响，未运行运输实验。**分类和认证不是同一套规范化**，可能出现 false-positive 分类后401，但未见把无效 token 变成有效 legacy 认证的绕过。建议在 credential 导入处统一验证/规范化，或明确要求 token 无首尾空白；本轮不把配置损坏导致认证失败新增为安全 P2。

`server/internal/handler/daemon_terminal_claim.go:31–55` 对含 claim 字段的请求继续要求真实 DaemonAuthPathDaemonToken 和匹配认证 workspace/非空 daemon；PAT/JWT/cloud PAT 均不满足。客户端判定和服务端约束在正常合法 token 形态上相容，但 UsesDaemonToken 的名字不能被理解为已经完成服务器认证。

### nil-client 测试的准确边界

generation_test.go:378–402 的 nil-client case 安装了 terminalReportSend hook；`daemon.go:6556–6557` 在 hook 分支返回，所以它证明 nil-safe gate 和 local legacy report，不证明 nil Client 能真实联网。真实网络路径仍需要有效 d.client/http.Client：`execution_terminal_claim.go:95–96` 的零 claims 分支读取 c.client。旧实现实际网络 nil Client 同样不能工作，非本次新增 finding，也不能把该测试泛称为“任何 nil-client 终态都不 panic”。

## 二、strict preflight 组合：有日志的 fail-closed，不是所有早退都安全

`execution_verifier.go:24–43` 的 strict 分支未改变：必须实际 GetTaskExecutionClaim、验证响应，并将 claim.DaemonID 与本机 cfg.DaemonID 比对。nil client、SDK错误、DaemonID mismatch 都以 errExecutionTaskClaimUnavailable 拒绝。`daemon.go:5792–5798` 先记录 pipeline preparation failed，再对 unavailable 直接返回，不发送终态、不启动 agent。

`execution_task_claim.go:24–34` 在 GET 前解析 expected tuple；G 为空/非法会直接返回 sentinel。HTTP非200同样包装 sentinel（52–56）。`server/internal/handler/daemon_execution_claim.go:19–26` 要求真实 MDT，PAT 即使是合法用户凭据也无法取得该 strict claim。

| 输入组合 | 当前路径与结论 |
|---|---|
| MDT + strict + tracked + G 缺失 | 不 stamp；SDK 在本地拒绝缺 G，记录失败后返回，无 legacy terminal、无 agent。是可接受的 fail-closed。 |
| MDT + strict + tracked + 完整 tuple，但 claim/DID 不匹配 | 记录失败后返回，不因已有 ctx tuple 就绕过 preflight，也不发 terminal。 |
| MDT + strict + offline + 完整合法 tuple | 在早退前 stamp，qualified fail；最终接受与否由服务器 fence 决定。 |
| MDT + strict + offline + G 缺失 | stamp 返回原 ctx；offline 在 preflight 前发 legacy。**旧 F1 残留，非本轮新增修复成功。** |
| PAT + strict + tracked + 完整 tuple | gate 不 stamp；strict SDK 实际 GET 被服务器拒绝，包装 unavailable 并记录后返回，不发 legacy，不启动 agent。 |
| nil client + strict + tracked | verifier 显式拒绝，记录后返回；不启动 agent、不发 terminal。 |
| PAT + strict + offline + 完整 tuple | 在 preflight 前进入 legacy fail，构成本轮 N2。 |

tracked 的缺 G/非 MDT strict 路径会留下平台 task 等待 lease/reclaim，而不是强行回调终结；这是故意拒绝无可信 claim 的动作。有 error 日志，不能叫静默成功或无日志失联。这里只核控制流，**没有验证 sweeper/reclaim 一定按时完成**，也不把 log 等同于完备运维恢复。不得因此把 offline 行为也一并称为 fail-closed。

## 三、vet 修复：CLOSED，重试/超时/统计与 client 隔离未发现回归

### 复制范围和 body

`execution_terminal_claim.go:94–118` 现在返回 *http.Client：零 claims 返回原 control client；qualified 时验证数量、tuple、可信 URL、非 nil HTTP client，再注入两键，并只复制 `*c.client` 设置副本 CheckRedirect=ErrUseLastResponse。没有再复制含 workspaceMu/issueGCBatchMu 的整个 daemon Client。

`client.go:681–685,727–731` 两个 terminal 方法分别使用返回的 HTTP client 调 `c.postJSONViaWithRetry(..., body, nil, schedule, nil)`。业务 body 仍在注入之前构造，没有其后覆盖两个 tuple key；新返回值没有遗失 baseURL/token/identity，因为这些字段仍从原 c 的 POST helper 构造。

### 与原 retry helper 的等价性

`client.go:1360–1361` 的 postJSONWithRetry 本来就仅转调 `postJSONViaWithRetry(ctx, c.client, path, reqBody, respBody, schedule, nil)`。新调用是同一 helper，唯一区别是可选 no-redirect HTTP client 显式传入。

- retry loop（1367–1391）仍最多 len(schedule)+1 次，检查父 ctx、返回 lastErr、仅 isTransientError 时重试，sleep 仍响应 ctx 取消。
- 错误分类（1328–1342）仍区分5xx/408/429/运输错误与永久4xx/响应格式错误；requestError 构造及非2xx判定仍在1439–1442，没有因重构吞掉403/409或把redirect当成功。
- Timeout/Transport/Jar 等由 http.Client 值副本保留。默认 control client 仍30s（155）；terminal report detached 6分钟外层 ctx 仍在 daemon.go:251,6501。没有误换 bundleClient 的无固定超时模式。
- TransferStats 的 nil receiver 方法在 client.go:415–427 明确安全；stats=nil 时 observeResponseStarted 无操作，wrap 返回原 reader。terminal 旧 wrapper 也传 nil，故没有新增 nil-stats panic，也没有改变原本不存在的 terminal 统计承诺。
- `ResolveSkillBundle`（455–464）继续传 c.bundleClient 和 &stats；helper 本身没有为 terminal 改写，也没有把 bundleClient/共享 client 的 CheckRedirect 或 Timeout 全局修改。技能下载仍保留原来的按 ctx 限时和 high-water stats。

### redirect 范围和小语义边界

qualified 的 CheckRedirect 只设在局部 http.Client 副本，原 c.client 不变；Transport/Jar 指针共享属于原 client 运输/连接复用语义，不因设置副本字段而改变其它调用的 redirect 回调。legacy 仍使用原 client，保留旧策略。

旧整份 Client 副本会在构造时快照 token/identity；新 helper 每次尝试都从原 c 构造 headers。因此若凭据在一次 retry schedule 中被外部更新，后续尝试可能使用更新后的 token，而不是旧 snapshot。不能在这个极端条件下宣称逐字节完全相同；但同一 report tuple/body 不会随凭据更新被抹除，服务器仍会验证身份/scope。未见新的降级/越权路径。本轮未做并发 credential 更新/data-race 测试，不扩大为全 Client 线程安全结论。

## 四、新确证 N2 / P1：credential-only gate 对 PAT strict 的 offline 早退自动降 legacy

### 与旧 F1、N1 的关系

原 N1 是“普通 legacy-contract PAT 任务因完整 G 被误升级成 MDT-only 并403”，该具体回归已 CLOSED。修它需要保留旧合同兼容，但不能把“不能用 MDT”当作“strict 可以走 legacy”。旧 F1 只要缺 tuple就仍有降级；本轮 gate 使 **PAT strict 即使有完整 tuple也不 stamp**，新增了这一完整输入的触发变体。

这里以 N2 标识本轮新增 gate 行为便于追踪；它与原 F1 的 required/legacy 判定根因归并处理，不重复累计成两项独立权限风险。

### 具体触发与行号

1. d.client 是正常 mul_ PAT；Task 的 T/R/G 全部合法且非空，TriggerCommentContent 声明新 strict 合同。
2. runtime 在 claim 返回与 handleTask 之间不再 tracked。
3. `daemon.go:5747–5749` UsesDaemonToken=false，不设置 origin。
4. `daemon.go:5760–5773` offline 分支构造 taskID-only fail 并 return。strict 检查在5792，根本未执行。
5. `daemon.go:6474–6477` report.withContextClaim 在新鲜 parent ctx 找不到 origin；`execution_terminal_claim.go:18–23` 接受非 required 空 tuple；于是 legacy 持久化/发送。
6. 服务端 `handler/daemon_terminal_claim.go:40–41` 无 claim intent 即走 legacy，不会触发 MDT-only 拒绝。此处未实际访问 DB 或执行 PAT 请求，确证的是完整静态自动降级路径；不声称已观察到线上跨代终止。

### 影响和建议

stale strict delivery 的自动 callback 丢失 generation fence，可能影响后来领取的同 task。PAT 原本就有 legacy 访问能力，所以**不是凭 token 前缀提升权限或新认证绕过**；问题是声明 strict 的生产 caller 不应自动用兼容接口替它作无 fence 终结。

建议在早退前区分两种独立事实：是否 strict/required，以及是否有能安全报告的 tuple/MDT。无新合同的 PAT 保留 legacy；strict 若无可用 MDT/tuple 应记录拒绝且不回调，留给 lease/reclaim。不要对 strict 的403或不支持凭据采用剥 tuple重试；也不要放宽服务端把 PAT 当 MDT。

建议独立 actor 回归（本 reviewer 未执行）：真实 PAT+strict+完整T/R/G+offline 断言无终态HTTP且无legacy outbox；PAT普通合同同形输入仍legacy；MDT完整tuple offline仍qualified；MDT strict空G offline也应不降legacy。

## 五、已有证据、未验证与落盘

- 只读 n1-red1.meta.json：3 RUN/1 PASS/2 FAIL；n1-green2.meta.json：41 RUN/41 PASS、37 leaf。是其它 actor 已执行结果，不是 reviewer 自己跑测试。
- 新三例源码（generation_test.go:317–402）使用 terminalReportSend hook；PAT fixture 文本为 pat_literal_test_only、MDT fixture 为 mdt_literal_test_only，并非真实服务器已验证的身份。可证明本机 gate/report 行为，不能据此签真实 MDT/PAT 认证链，也未覆盖 strict+offline 的 N2。
- final2-vet.json 可见 assignment copies lock value 报错；final2-vet2.json 在2026-10-25T07:26:08.474Z记 exit0、空 stdout/stderr。命令范围沿用作者交接；该简短 JSON 本身没有 argv，不冒充 reviewer 独立执行整组 vet。
- 未运行 prefix/空白运输、真实PAT/MDT、retry/redirect/超时、credential并发更新或DB/reclaim测试；源代码判断与上述其它actor证据分开陈述。
- final2-freeze-manifest（07:25:30）早于 vet 修复，不能用作当前三个变更文件的无漂移声明。最终采用较新的 n1-green2-source-manifest（07:26:12.468Z）；本次读时六个相关文件均匹配，创建前再校验，表附后。

最终报告由临时评审文本以 Python open('xb')（wx/exclusive create）创建，读回核验；不覆盖既有报告，临时文本不在产品树。

### Final raw SHA-256 snapshot

Pin: `terminal-fence-20261025T060611Z-n1-green2-source-manifest.json`

| File | Bytes | SHA-256 | Status |
|---|---:|---|---|
| `server/internal/daemon/client.go` | 61517 | `916edf84ef90c6749d026a9de7ca478d9e6b788360ddf98ce0ccdbfb68eaa01d` | MATCH |
| `server/internal/daemon/daemon.go` | 487956 | `0191e9d1831bf38aa2aeb04dd96946bdba90dcc718d3453cb2827eb2edecb13b` | MATCH |
| `server/internal/daemon/execution_terminal_claim.go` | 3750 | `85f22e7449fb5b2e7acdeba466bd286d8c07bcbabff551ba9729bc10f0bd5e33` | MATCH |
| `server/internal/daemon/execution_verifier.go` | 5580 | `f4796e3f8b9a1186abc1ca46eb08df352a094a034ae31f5bcf209bcdbd5e1161` | MATCH |
| `server/internal/daemon/terminal_report_queue.go` | 37999 | `da15ba13c4a9728613fe64ef75d30e356b0a5450c4676efe3e7b82feb2816f6f` | MATCH |
| `server/internal/daemon/execution_terminal_generation_test.go` | 17575 | `347f5b86d2bac484eb506edde5c03e27fcdb7b3ec3d9efa38e38abbac35521a4` | MATCH |
| `server/internal/daemon/execution_task_claim.go` | 3527 | `ad8de9adb8c443ab64522e3a568e5bd46d267fdbbb97d9316a2bc2f2a55d7452` | supporting read |
| `server/internal/middleware/daemon_auth.go` | 10978 | `2b1a7f534c6fd637ece96a29c14280b4f8615ba1e2fb5ed2dd5c2297eb275ca0` | supporting read |
| `server/internal/handler/daemon_execution_claim.go` | 4253 | `7164b743495d61ca4c6e3273ba0d0c03ba3bbed65724fcd9a2ea3797b9a08282` | supporting read |
| `server/internal/handler/daemon_terminal_claim.go` | 2955 | `164e9304d29c6061975eae0159b8d303be9d35136d141e7cb66e4b3141a365af` | supporting read |

Creation UTC: 2026-10-25T07:30:29.696946+00:00
