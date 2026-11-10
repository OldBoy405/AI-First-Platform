# AIFI-45 per-run execution binding endpoint — strong 静态复审

## 判定总表

| 切片 | 判定 | 依据与限定 |
|---|---|---|
| loopback、随机路径、给 run 的环境布线 | **CLOSED（机制存在）** | endpoint `:70–87`、daemon `:8750–8752,8889–8900`；不是调用者身份或隔离证明。 |
| “只有这个 run/可信工具子进程能用” | **OPEN** | URL 是 bearer signing capability；没有 UID/PID/run caller 校验，直接进 signer。拿到 URL 的其他进程可用其固定 run 的权限签自选兼容 challenge。 |
| “恰好一次接受/签发” | **OPEN** | `serve :120–138` 签发前没有占用/消费状态；写后异步 Close 不是原子单次闸门。 |
| task/runtime/代次/CR 的固定 selector | **CLOSED（新签发正常路径）** | `ForRun :155–160` 从 Task 值构造 spec；server claim SQL exact T/R/G/CR/W/daemon。不能外推调用进程属于该 run。 |
| endpoint 只接受 challenge 一键 | **PARTIAL** | typed Unmarshal 忽略 extra/外层重复/大小写别名；额外 task/runtime 不会覆盖 spec，但 exact-key 宣称不成立。 |
| 签发拒绝不返回 envelope | **CLOSED（该错误分支）** | `:126–131` 409 + generic error，无 envelope。该分支不 Close，非一次尝试即关闭。 |
| 缺 endpoint 不被 daemon 当已核验 | **CLOSED（所读代码未作此判定） / PARTIAL（可用性与集成）** | nil/warn 后继续，不设 Verified/Admitted；识别出的严格合同仍在早期 preflight 拒绝。现行 T 不读新环境变量。 |
| 单次成功能完整送达 HTTP envelope | **OPEN** | 写响应返回不等于 flush 完；异步 Server.Close 可关闭当前 active connection，存在响应自截断交错。 |
| 测试足以证明拒绝/退役/并发单次 | **PARTIAL** | 正常单次 body 可测；网络错误跳过状态断言，退役重试用无效 body 且不要求真的退役，无并发单次/真实认证/T 验签证据。 |

**确证 finding：E1/P1（受限代签权显式暴露给持 URL 者，可信 run/子进程来源边界不成立）；E2/P2（并发可多次进入签发、失败/写错不消费）；E3/P2（关闭当前响应的自截断竞争）；E4/P2（拒绝/退役测试存在假绿路径）。** E1 是既有同 UID/可信来源未闭合根因在本次产品接线上的具体暴露面，不将它重复算成另一个已验证的“完整消费绕过”。未确认 P0、跨 workspace 任意签名或实际准入/receipt 放行。

## 范围与方法

M 根：`C:/Users/GOBAO/Downloads/AI/multica`；T 根：`C:/Users/GOBAO/Downloads/AI/tools`。除特别说明，M daemon 文件路径相对 `server/internal/daemon/`，T 文件相对 `skills/shared/crctl/scripts/lib/`。

本轮只读新增 endpoint/test、runTask 环境接线与直接资格/严格 preflight、server claim/signature helper、现行 T 相关通道及 Go HTTP 关闭/缓冲语义。**未访问 DB；未执行测试、Node、crctl、Podman、编译、vet、生成器、探针或并发实验；未改产品源码/测试；无子代理。** 另一代理持 DB 单权，未触碰。报告 wx 独占创建并回读。

主 pin：`stdio-relay-20261025T091500Z-endpoint-green2-source-manifest.json`，10:04:42.531Z。endpoint.go 5,450 bytes / `f7cf83f3ff93a7131bbeb1d8b43946683cab43666058b2df6bb9e52fd16238bb`；test 6,594 / `8814ac513bb75170141e6064f8c50a299b81ae1eb02c53142c41790bd3fd06c3`；daemon.go 489,523 / `50f7fb184b1c479a92f06cf7822f6cf0e23e4bed76160afb57babd3d7cbdaf13`，本轮样本匹配。manifest 包含其他 relay 文件不等于本轮重审其修复；不补签前几轮 lifecycle/锁序。配置 strong 身份沿用，actual backend unknown。

## 1. 谁能用 — OPEN / E1 P1

### 明确结论

**这是把平台的“该 run 范围内的绑定代签能力”做成一个可转交 bearer URL，交给 agent run；不是只有 daemon 亲自启动的可信 crctl 子进程能调用的私有端点。** URL 一旦被另一个进程得到，它无需 mdt_、task token 或与该 run 的进程关系即可提交 challenge。

- endpoint **:70–84** 用 crypto/rand 的 16 bytes→32 hex 路径和随机端口，bind `127.0.0.1`；安全随机 128-bit 路径使盲猜不可行，不能写数学上的绝对“不可能”。端口被发现本身也不足以获知 nonce。
- **:87–89,103–124** 只依赖 HTTP 路由/方法/body，未验证 caller UID/PID、发起 run、进程句柄、父子关系或独立认证。endpoint 的 signer 是 daemon 的 d.client，不是调用者的弱 task token。
- daemon **:8750–8752** 显式将完整 URL 写入 agentEnv，**:8889–8900** 将该 env 交给实际 agent backend 配置。这不是以前只有 unit-test 调用的未接零件，已有产品接线。

**在题设“同 UID 对手可读目标进程环境/proc”的威胁模型下，是：任何能读到这个 URL 的同 UID 进程都能获得这份受限代签权，per-run 调用者隔离不成立。** 不需要猜路径；合法 run 自己的 agent 更是被明确授予 URL。MULTICA_ 不能被 custom_env 覆盖即使成立，也只是防改写，不能防读取/转发。

同时精确限定：不是“所有本机进程在不知道 URL 时都无条件有签名权”；OS 的 proc 可读性、MAC/hidepid/Windows ACL 等未在本轮实测。**其他 UID 只要能取得 URL 并连到 loopback，同样没有第二层验证**。也不是泄露平台私钥或变成任意 W/CR/task 的签名器；固定 selector 和服务端校验仍限制 scope。

### 与原私有 stdio 比较

**比原设计意图更弱，明确不是等价替换。** 原意图是 daemon 拿它亲自启动的单个可信控制 child 的 stdout 来取得 challenge；本片接受任意 bearer holder 的普通 HTTP JSON，没证明它出自这个 child、甚至没要求是 crctl。攻击者只需拿 URL 后发普通 HTTP，而非参与那条既定父子 stdio 会话。

但不反向声称旧 stdio 已能防同 UID：旧设计本来也未获得 OS 隔离签字。这里降低/放弃的是来源限定，并新增显式、易转交的受限签名 API，不是从“旧的完美同 UID 隔离”退化。

唯一合同 `projects/tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md:78,80–82` 明确要求不把 Agent 自报 root/identity 当事实、仅转发亲自启动 child 的 challenge、隔离前不得提供任意 nonce 代签能力。当前产品片不满足该来源边界，故列 E1/P1；消费关闭不使“可信签名来源已经实现”的表述成立。

### 环境/proc/日志证据边界

env 注入可静态确认；同 UID 实际读取目标 env/proc、跨 run 偷用和真实 OS ACL **未实验**。新 handler 没 access logger/URL 输出，启动 warn **:163** 只记录 task_id/error，所读接线也未直接打印 URL；未确认已有生产日志泄漏。agent/诊断工具若输出自身环境会把 bearer 持久化，源码没有“返回 URL 自动脱敏”的保证；不能据没找到直接日志 sink 声称全日志都安全。

## 2. 一次性 — OPEN / E2 P2

**位置：endpoint :103–138，Close :53–62。** 没有 mutex/atomic used flag、reservation 或签发前的单次消费判断；Close 在 w.Write 成功后才以 goroutine 启动。

允许的静态交错（未运行）：

1. A、B 持同一 URL，同时对同一路由发两个有效、不同 nonce 的 challenge。
2. 两个 handler 均通过方法/形态校验并进入 **:120** 的 signer。
3. 两个平台请求都可在第一个本地 handler 触发 Close 前完成签发/提交。服务端唯一键只去重同 challenge，不限制同 T/R/G 只能一个不同 challenge。
4. **:138** 关闭监听/连接不能撤销已提交的第二份证明；即使第二个 HTTP client 最终没读全 envelope，也不能据此说只调用/签发了一次。

甚至不必等到“写后 Close goroutine 还没调度”才有窗口：**第一个请求正在等待平台时，第二个就能进入签发。** 异步 Close 既不序列化入口，也不能替代原子单次能力消费。

以下分支连关闭都没有：400/405/413 拒绝；**:126–131** 的 signer error；**:134–135** 的响应写错。最后一种可能已经在平台签过，但 endpoint 仍保留，之后又能请求别的 nonce。因此“answers exactly one challenge / exactly one accepted request”均未成立。把一次性定义成“成功回包一次后尽快停止监听”也仍受并发及后述响应自截断影响。

Close 等待 e.done 只证明 Serve 主循环已返回，不是所有 handler/平台请求都 drain 完，更不能召回签名。无动态并发/close 压测；这不妨碍无单次闸门的静态反例成立。

## 3. task/runtime/代次/CR 绑死 — 有限 CLOSED，不等于调用者绑死

### 正常新签发的 selector 确实不来自 HTTP body

- ForRun **:144–160** 取 Task 值中的 PipelineCrID、ID、RuntimeID、DispatchedAt 构造 spec；闭包接收 spec 值，HTTP body 不能改这些 string 字段。
- serve **:120–124** 固定用该 spec 请求平台；不把 local body 的 task/runtime/CR 作为 selector。
- `server/pkg/db/queries/execution_binding.sql:7–18` 选择 exact task ID，且同时匹配 runtime、dispatched_at、active 状态、CR；agent/runtime workspace 对齐、runtime daemon_id 等于真实认证 daemon。
- `governance/execution_binding_issue.go:120–154` 校验真实 DaemonAuth path、认证 workspace/daemon，并将固定 tuple 交上述查询；**:191–217** 复核 task/CR/project、coordinator 的 workspace/project/daemon 和 head/deployment facts。

**结论：偷到 A endpoint，不能靠 body 把新签发 selector 换成 B 的 task/runtime/generation/CR。** 不等于平台签名权全开放，也未发现跨 workspace 扩权。

但这只固定**被签名声明中的数据库 run**，不验证**提交 challenge 的本地进程属于该 run**。对手可使证明成为“victim A 的 T/R/G + 对手提供的 nonce/PID/roots/operation 等允许字段”。服务端这些 PID/根来自转述，不是 OS 亲子证据。

当前 T `execution-binding.mjs:104–124` 比较自己的 nonce、根、PID、operation、grant scope/head 等，但 **runtime_id/task_id 仅检查 canonical UUID 形态**，没有独立取得当前平台 run 的 tuple 来相等比较。因此同 scope/head/合法安装根等前提满足时，不能用“payload 印着 A 的 task ID”推导“B 控制进程一定拒绝它”。不声称它能把 payload 印成 B，更不声称当前已消费；真实跨 run/真实 T 的利用链本轮未跑。

### replay 不是重新校验所有请求字段的一次新签发

server **:224–229** 的 existing lookup 仍只按 W/CR/grant/challenge；查询见 `execution_binding.sql:20–26`，命中回旧 envelope。故“固定 tuple”严格描述当前 request 的 claim 验证及正常新签 payload，不应扩成“所有 replay 返回 envelope 都与这次 spec 的所有字段相等”。本轮未确认现存异 tuple 的 nonce winner 或可利用猜 nonce 路径；这只是防止将正常新签 selector 的闭合外推过度，不另列 finding。

### “只接受 challenge 一键”实际上不严格

endpoint **:108–116** typed struct Unmarshal 忽略 extra；`{"challenge":{},"task_id":"B"}` 的额外 selector 不被使用，case alias/重复外层 key 也非严格拒绝。于是 body exact-key 宣称是 PARTIAL，不是成立的防线。inner challenge 仍由平台严格校验，未因此确认能覆盖固定 spec 或绕过平台 scope。

## 4. 签发拒绝/重试 — 零 envelope 成立，一次即关不成立

signer error **:126–131** 回 409 `EXECUTION_BINDING_UNAVAILABLE`，没有 envelope；也**没有** go e.Close。400/403/409/429/5xx/网络/超时等平台错误在这里都被折叠成相同 409，不提供原 cause/Retry-After。caller 不能根据这个码可靠区分“应永久拒绝”与“稍后也许可用”。

**如果某个客户端把这个 409 无限重试，endpoint 本身不会因为这些失败而关闭。** 每次形态合法的重试都可再次进 signer，直到 runTask 的 defer Close、某次成功触发 Close 或其他外部关闭。`executionBindingEndpointLinger=5m` 只设在 **IdleTimeout (:94)**：它限制单个 keep-alive 连接 idle，不是 endpoint 5 分钟 TTL，不会自动停止监听，也不限制持续请求次数。ReadHeaderTimeout=5s 也不是读完整 body 或 endpoint 总时长的保证；本轮未做慢 body/连接压力实验。

**不能据此说“当前 T 已无限 HTTP 重试”。** 当前 T 全仓对该 env 名的定向检索未见消费者，已读 `execution-binding.mjs:84–98` 仍是 stdout challenge + stdin proof 的 15s race，没有对这个 URL fetch/重试的路径。新 env 不会自动让 stdio 协议变成 HTTP。真实工具如何使用该端点/回灌裸 envelope 本轮未见产品集成证据；未来 HTTP caller 的 retry 策略也未验证。

所以：服务端拒签不交证明 CLOSED；拒签即一次性消耗 OPEN；“T 当前因此无限重试”不成立为已确认事实。若自定义工具确实循环，服务端会持续提供重试面，但消费/准入并未因此放开。

## E3/P2 — Close 可截断自己刚写的成功响应

**位置：endpoint :133–138,53–58。** w.Write 返回 nil 只表示 ResponseWriter 接受字节，不代表已经完整送达 client；紧接 go e.Close 可在当前 handler 返回/flush 之前关闭它自己的 StateActive connection。

本机只读 Go `C:/Program Files/Go/src/net/http/server.go`：

- **:342,1123,1630–1639** 显示 2KiB response buffer、后续连接 buffer；
- **:1687–1688** Write 可以只是写入 bufio；
- **:1694–1704** handler 完成时 finishRequest 才 flush response 与 conn buffer；
- **:3190–3216** Server.Close 立即关闭 active connections，不只关 listener/idle。

静态交错：短 envelope 全部进入响应 buffer→Write nil→Close goroutine 先关 active socket→handler 完成后 flush 失败；client 可见 EOF/不完整 HTTP，而平台已签发且 endpoint 已退役。大回复也可能只丢末尾，不能用“Write 成功”证明 complete delivery。**本轮未动态复现发生率/平台差异**，但该调度不被任何锁/flush/连接生命周期保障排除。

endpoint 的 Close 注释把 Shutdown 说成等待 idle keep-alive drain，也不准确：标准 Shutdown 会关闭 idle，主要等待 active 请求结束；此处选用 Close 的真实代价就是可打断当前 active 响应。这里仅判定，不提供实现代码。

## 5. 接线与静默无 endpoint — 不证实新准入 fail-open

- endpoint **:145–153** 对 nil daemon/client、UsesDaemonToken=false、空 PipelineCrID/DispatchedAt 返回 nil；网络启动失败 **:161–166** warn 后继续。没有检查 Task.ID/RuntimeID 非空/canonical；不足的 selector 到真实平台会被拒，不是已验证 eligible run。
- UsesDaemonToken 是路由资格前缀分类，不是本机 caller 认证；真实 server 才认证 d.client 的凭据。
- daemon **:8750–8752** nil 时不注入 URL，非 nil 也只是环境变量，不设 proof/Verified/Admitted，不读取 HTTP 签发结果作为任务成功条件；未在本片发现“静默无端点→daemon 误判已核验”的路径。
- 对**当前识别为 strict 的合同**：`execution_verifier.go:23–68` 做 preflight 并最终返回 EXECUTION_CONSUMPTION_REQUIRED；`daemon.go:5799–5821` 在准备失败后 return，早于 runTask。故这条已知 strict 路径不是靠 endpoint nil 继续启动 Agent。未重审所有 malformed/legacy 合同解析，不能签全产品强制准入。
- 对能到 runTask 的其他 eligible run，endpoint 创建失败确实按意图继续，调用工具缺证明将失败/不可用；T 当前并不读取这个 URL，更不应把环境存在当已绑定。新能力属于接线/可用性 PARTIAL，不是认证成功事实。

因此新增片没有证实一个凭“无 URL”放过 strict execution 的准入漏洞；但也没有建立“strict run 一定得到可用证明”的保证，更不能用对端 T 会拒绝来关闭 E1/E2。

## 6. 测试强度 — PARTIAL / E4 P2

### WrongRequests：错路径造法有效，错误吞掉使断言可跳过

`execution_binding_endpoint_test.go:105` 的 Replace 得到 `/binding/deadbeef<nonce>`，确实是与注册的 exact path 不同的有效 URL；不是因为没有多一个 slash 就失效。

问题在 **:106–124** 三个请求都只在 err==nil 时断言 404/405/400。连接失败/意外关服等情况下三个断言全跳过，最后 signer.calls==0 仍成立，测试可以通过。**不是所有运行都完全没有鉴别力，但“没有 HTTP 响应也算成功”的分支无效，不能证明 handler 返回了应有拒绝码或服务当时仍存活。** 严格测试需要确认请求成功到达活服务、再判状态；本轮未改测试。

### ServesOneProof：现有退役断言移除 Close 也能通过

**:52–61** 的后续请求 body 是 `{}`，本就会在形态验证处 400、不触发 signer。若 endpoint 永远不自关，循环可以完整跑满 5 秒后退出，**没有任何断言要求曾发生连接失败/服务退役**，signer.calls 仍等于 1。因此单次正常调用+该循环不证明一次性；静态删除自关的反事实仍满足这些断言，本轮未做 mutation execution。

### 其他证据不足

无两个有效请求同时被阻塞在 signer 的测试，不能证明 E2 关闭；无成功响应 flush/Close 的调度压力证据，不能证明 E3 不存在。Eligibility 的正例甚至未填 task/runtime ID，验证的是弱资格开端口，不是平台接受身份。fake signer/fixture envelope 不做 DaemonAuth/DB/真实 Ed25519/T 期望字段验证；测试能证明裸 body 运输，不证明实际签发/消费链。

## 作者证据、身份与最终结论

只读 `endpoint-green2.meta.json`（10:05:02.593Z）：**24 RUN / 23 PASS / 1 SKIP，20 leaf，exit 0**；filter 包含 endpoint/relay/client/parser。保全原库/清理是作者元数据，本评审未 DB 核验；未读取尚在写入的 independent-daemon 结果并补签。本片静态审阅已完成，不因未跑动态统一标 INCOMPLETE。

**整体 PARTIAL。E1/P1 来源边界 OPEN；E2/P2 一次性 OPEN；E3/P2 成功响应关闭竞争 OPEN；E4/P2 测试假绿 OPEN。** 正常新签 selector 固定、真实平台 task/runtime/代次/CR/W/daemon 校验成立；它们没有约束 HTTP caller 属于那个 run。没有确认跨 workspace 任意签名、receipt/消费/准入被放开；实际环境读取、跨进程偷用、并发双签、响应截断和真实 T HTTP 集成均未动态验证。

**不签消费/准入/activation/隔离域/全局 C1/Gate3；旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭；消费 closed/off。**

## 发布前输入身份

UTC：`2026-10-25T10:14:20.985309+00:00`。三份主文件再次匹配 endpoint-green2 manifest；三份直接签发/验签输入匹配本轮读取样本。没有据 manifest 中其他文件的存在补签旧 relay 修复。

| 文件 | bytes | raw SHA-256 |
|---|---:|---|
| M/server/internal/daemon/execution_binding_endpoint.go | 5450 | f7cf83f3ff93a7131bbeb1d8b43946683cab43666058b2df6bb9e52fd16238bb |
| M/server/internal/daemon/execution_binding_endpoint_test.go | 6594 | 8814ac513bb75170141e6064f8c50a299b81ae1eb02c53142c41790bd3fd06c3 |
| M/server/internal/daemon/daemon.go | 489523 | 50f7fb184b1c479a92f06cf7822f6cf0e23e4bed76160afb57babd3d7cbdaf13 |
| M/server/internal/governance/execution_binding_issue.go | 22090 | d961424d2d69b337350175afec36751ae5b48eeb5f642a4e094eaac74e4e6b0d |
| M/server/pkg/db/queries/execution_binding.sql | 1646 | 2305fc71d51b7c761e5d7c85a2771e04e6b3b30d17c6381aad7bc9863886fd72 |
| T/skills/shared/crctl/scripts/lib/execution-binding.mjs | 7262 | 8fe71e0f5fc48a524763a63641a43052fff78fc25868017669516297b03ba95d |

必要 helper/合同发布时采样（非历史执行 pin）：

- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/daemon/execution_verifier.go` — 5580 bytes；raw SHA-256 `f4796e3f8b9a1186abc1ca46eb08df352a094a034ae31f5bcf209bcdbd5e1161`。
- `C:/Users/GOBAO/Downloads/AI/multica/server/internal/daemon/execution_binding_client.go` — 2652 bytes；raw SHA-256 `770c58eddc28c3a6e0ea9461d423727f0a40bf207ac158be240688a863a21ce0`。
- `C:/Program Files/Go/src/net/http/server.go` — 139414 bytes；raw SHA-256 `8a46dd48f65aba824366170f8f335417af263fc60b7b4e04ef2a4bba4a21253d`。
- `C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md` — 35699 bytes；raw SHA-256 `b39227b95d911063e271c4845ea4f849fb513024e05f026aa1b2aa1540bddb89`。
