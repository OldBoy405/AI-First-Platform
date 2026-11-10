# AIFI-45 daemon resume3：N2 guard 与 prepare 前早退清点

## 范围、身份与结论

业务根：`C:/Users/GOBAO/Downloads/AI/multica`。未加前缀的代码文件均位于 `server/internal/daemon/`。

仅审新增 runtime-offline guard/canFenceTerminalReport，以及 handleTask 从入口到第一次调用 prepareClaimedPipelineTask 之间的全部控制流和必要直连 helper。不重审完整 terminal/server/outbox 链。未访问 DB，未运行测试/vet/编译/生成器，未改产品源码或测试，未使用子代理，不使用另一代理的 DB 单执行权。只读、哈希和实际创建本报告。

模型声明沿用既有交接：configured strong `OpenAIPersonal/gpt-6.1-sol/high`；actual backend model unknown，未重新发现模型。

**N2 判定：PARTIAL。** 合法、唯一且受支持的 strict 合同原触发已经关闭：PAT/nil client 或 MDT 缺 RuntimeID/DispatchedAt 的 offline 路径现在不回调；MDT 完整合法 tuple 仍 fenced。**但 strictExecutionContract 返回 error 时保护被跳过，PAT 或 MDT 缺 tuple 仍可发 legacy 终态**，不能按用户要求包含 error 组合的范围判为完全 CLOSED。该剩余问题归并 N2/既有 F1 的 required 判定缺口，保留 P1 风险，不另造重复 finding 编号。

**清点结论：prepare 前正常控制流的早退分支仅此一处 `!tracked`，内部有两个 return；没有第二个 slot、nil-check 或 panic-recovery 终态兜底。** 详细行号/安全性见第二节。没有在此之外确认新的独立 P0/P1/P2。

限定静态复核已完成，不能无条件签这组 fence 边界通过。不签完整 terminal 链、生产准入、Gate3、全局 C1、完整 TC/major，不补旧 claim 锁序 INCOMPLETE。

## 一、N2 的精确判断

### 1. 新代码的实际保护范围

- `daemon.go:5747–5749`：MDT 外形凭据先调用 withTerminalClaimOrigin；早于 runtime 检查。
- `daemon.go:5750–5752,5760`：runtimeIndex 查不到时进入唯一 offline 分支。
- `daemon.go:5767–5770`：只有 `strictErr == nil && strict && !d.canFenceTerminalReport(task)` 才记录错误并直接 return。
- `execution_terminal_claim.go:78–82`：canFenceTerminalReport 仅检查 UsesDaemonToken、RuntimeID/DispatchedAt 非空，是可携带性的粗判，不是身份/格式/当前 claim 的验证。
- `execution_terminal_claim.go:67–75`：实际 stamp 还要求 Task.ID 非空；随后 `withContextClaim:86–97` 按 taskID 匹配附 tuple。
- `daemon.go:5772–5780`：其它 offline 情况走 reportTerminalTask，然后无条件 return。

### 2. 用户指定的组合矩阵

下表针对 runtime 不 tracked、正常新鲜 parent context、有效 taskID。MDT 指 UsesDaemonToken 判为 true 的凭据形态；真实身份/owner 仍需服务器验证，不能把前缀当权限。

| strictExecutionContract 结果 | 凭据/tuple | 实际行为 | 判定 |
|---|---|---|---|
| true,nil | MDT，但 RuntimeID 或 DispatchedAt 为空 | canFence=false，5770直接 return，既不发HTTP也不入legacy outbox。 | **原缺口关闭；有日志的 fail-closed。** |
| true,nil | MDT，T/R/G 完整合法 | origin已stamp，canFence=true，不被新增guard拦住；5772报告附tuple并验证后走qualified发送。 | **保留正确 fenced callback，不误丢。** |
| true,nil | PAT，tuple完整或缺失 | canFence=false，5770 return，不再因PAT兼容而自动降legacy。 | **原N2核心触发关闭。** |
| true,nil | nil client | UsesDaemonToken nil-safe返回false，canFence=false，直接return；不会到nil-client网络发送。 | **safe拒绝。** |
| false,nil | 普通无新合同 | strict为false，不执行“不发回调”的guard，仍到5772。PAT仍legacy；MDT完整tuple仍qualified；MDT缺tuple按既有legacy兼容。 | **未把strict保护误用于正常非strict路径。** |

“完整但畸形”需要单列：canFence 只检查非空，可能为 true；但 stamp 后 `terminalClaims():17–40` 对 canonical task/runtime UUID 和精确微秒时间验证。`daemon.go:6483–6486` 在 enqueue/flight/网络之前执行 persistedTerminalReport 验证，错误即返回；不会剥 tuple 再 legacy。非空空白字符串同样在这里被拒绝。Task.ID为空虽未被canFence检查，但 persistedTerminalReport 会拒绝空taskID；非canonical非空ID会被qualified验证拒绝。因此不能仅凭canFence的名字宣称已验权/验格式，但本轮没有由此确认另一条网络降级。

### 3. strictExecutionContract 自身 error：仍然有洞

这不是假定未知 parser 可能报错。`pipeline_task.go:558–592` 明确有以下实际返回：

- 586：识别到一个非空 contract，但不等于当前 ExecutionPolicyVersion，返回 false,error。
- 590：识别到多于一个 context.execution.contract 声明，返回 false,error。

函数注释（552–557）明确把“声明未知合同”定义为拒绝，而非悄悄当 legacy。当前 offline guard 在 `strictErr != nil` 时整个条件为 false，错误也未被记录/处理，直接走 runtime_offline report；不会进入后面的 prepare 来补救，因为5780已返回。

error 情况必须按凭据/tuple分开看：

| parser返回error时的组合 | 结果 |
|---|---|
| MDT + 完整合法T/R/G | entry已stamp，仍发qualified；generation没有丢失，但合同错误被忽略、日志/失败原因只体现runtime offline。不能把这行说成legacy绕过。 |
| MDT + 缺RuntimeID/DispatchedAt | entry不stamp，错误guard不生效，report无tuple，可能持久化/发送legacy。 |
| PAT + 完整T/R/G | entry不stamp，错误guard不生效，仍可能legacy。 |
| PAT + 缺tuple | 同样legacy；没有因合同声明错误而拒绝。 |

**具体静态反例**：正常PAT client、合法T/R/G、runtimeIndex不含R，trigger带两个可识别的受支持 contract声明，或者一个未知contract声明。parser走586/590；5767因error跳过保护；5772构造taskID-only fail；6484未找到origin，terminalClaims允许required=false且两字段空，于是走legacy。与旧版本相比，受支持唯一strict的PAT例已修，但“声明合同却解析为错误”不能继续借legacy语义终结后来代次。

这是caller的自动降级/代次完整性问题，不是PAT取得新权限，也不是伪造MDT认证。未执行DB竞态或声称线上跨代误终止已发生；静态可达的未fenced回调已足以阻止此边界完全关闭。没有把同一风险按F1/N2重复计数。

**建议（未改源、未执行）**：offline先处理parser error，记录并不发送终态；仅在明确false,nil时保留legacy，在true,nil时要求可fence。若必须对error提交终态，也只能确保qualified格式和认证可用，不能error→legacy。建议下一个持执行权actor补未知contract、重复contract在PAT/MDT缺G下的零HTTP/零legacy-outbox负例。

另一个边界：yaml.Unmarshal错误在parser:569–574被continue，有些malformed YAML最终得到false,nil，并不是上述error返回。本文不声称所有损坏YAML都被strictExecutionContract识别，也不借本轮重审整套合同意图检测；这里的反例只用明确存在的586/590。

## 二、handleTask 在 prepare 之前的全部路径清单

审阅的精确区间：`daemon.go:5742` 函数入口，到 `5801` 第一次 `prepareClaimedPipelineTask(ctx, &task)` 调用。5801调用返回后的错误分支、后续local-directory、runner、slot执行等不计入“prepare之前”，也不能倒过来充当前段保护。

### A. 函数内正常控制流

| 行号 | 操作/分支 | 是否提前结束handleTask | 是否可能发未fenced终态 |
|---|---|---|---|
| 5747–5749 | UsesDaemonToken gate；真则stamp，假则继续 | **否**。helper的return只返回context，不是handleTask return。 | 此处不发送；只是决定后续origin是否存在。 |
| 5750–5752 | Lock、runtimeIndex读取、Unlock | **否**。nil map读本身安全，只得到tracked=false。 | 不发送。 |
| 5760–5770 | !tracked，且parser成功strict，且不可fence | **是，5770**。 | **不发送、不入outbox**。安全拒绝，日志说明留给lease/reclaim；未验证回收最终时效。 |
| 5760、5772–5780 | !tracked且不满足上一行：包括可fence strict、false,nil legacy、parser error | **是，5780**。report错误只在5778记日志，不另有一个return。 | 可fence strict为qualified；正常legacy按兼容处理；**parser error + PAT/MDT缺tuple可能unfenced，见一.3**。 |
| 5782 | tracked=true，取rt.Provider | **否**。没有provider为空时的提前返回。 | 不发送。 |
| 5790–5794 | 建task-scoped logger、phase recorder、context，Mark claimed，defer Mark finished | **否**。 | 只有计时日志；没有终态回调。defer不是recover。 |
| 5795–5798 | 默认agentName；task.Agent非nil才读Name | **否**。Agent为nil只跳过赋值，不return。 | 不发送。 |
| 5801 | 进入prepareClaimedPipelineTask | 到本清点边界。 | 其返回后的回调不能列作另一个prepare前早退。 |

**所以：只有 `!tracked` 这一处正常早退分支，里面两个return（5770/5780），不是只有一个return语句。** 没有其它隐蔽的slot/runtime validation return，也没有在origin gate为false时直接提前结束任务。

### B. nil、slot、取消、panic和helper核查

- handleTask 的task参数为值，不存在 `task == nil` 的handleTask分支。`task.Agent == nil` 已列上，不会终结任务。
- 此区间没有d==nil/logger==nil/context==nil的防御性提前return，也没有ctx.Err()/select取消早退。d.client==nil由UsesDaemonToken处理为false，真正strict且parser成功时新guard会拒绝offline回调；不能把“不检查nil”写成存在一个安全兜底分支。
- `slot` 在5742–5800没有被用于判断或报告，没有“无slot先fail”的本函数路径。
- `task_phase_timing.go:45–56,63–89,94–95` 的constructor/Mark/context helper只创建状态和计时日志。Mark在recorder为nil/重复phase时的return只结束Mark，不结束handleTask；没有complete/fail调用。
- 此函数prepare前没有 `defer recover`、panic→fail转换。daemon包源码检索也未见 `recover(`。唯一已安装的handleTask defer在5794，只Mark finished；无法恢复panic或合成legacy回调。
- 传入无效nil daemon/logger/context、标准库操作或自定义log handler异常可能panic；没有理由把这些异常描述为“安全返回”，但本片也没有panic恢复后发送未fenced终态的代码。未运行panic注入；没有把不受支持的nil对象输入另计为新业务finding。

### C. 直接生产调用者的边界（不是第二个handleTask早退）

必要查看 `daemon.go:5495–5529`：

- 5497–5499：i超出slots或tasks[i]==nil时break，不调用该任务的handleTask；此处不发终态。它是dispatch caller边界，不是handleTask内部nil/slot失败报告。
- 5501–5502取Task值和slot；5516附近启动goroutine，5528调用handleTask(parentCtx,t,slot)。
- goroutine的defer是taskWG.Done、activeTasks计数减一及归还slot/唤醒poller（5517–5527），**没有recover或complete/fail补偿**。普通return触发这些资源清理，不会产生另一个legacy终态。
- 不在本轮证明超量claim/空task的服务端调度契约、panic时的整个进程可用性或slot回收所有异常场景；这里只确认没有遗漏题目关心的prepare前终态发送路径。

## 三、证据与未验证项

只读 `n2-red1.meta.json`：3 RUN/1 PASS/2 FAIL；`n2-green1.meta.json`：84 RUN/84 PASS、78 leaf。这些是其它actor的既有结果，不是reviewer独立运行。

新增源码 `execution_terminal_generation_test.go:536–600` 以hook检查合法strict+PAT离线零回调，普通legacy+PAT对照一回调。它覆盖了N2核心修复，不覆盖本轮指出的parser error矩阵。相关“MDT完整tuple”和缺tuple路径的结论以实际控制流/验证顺序为依据，不宣称reviewer运行了那些组合。

本轮没有访问DB、发真实MDT/PAT请求、运行错误合同负例、panic注入或lease/reclaim验证。不把已有84/84扩成完整terminal链或生产准入证据。

## 四、快照与创建方式

当前六个本片相关文件与 `terminal-fence-20261025T060611Z-n2-green1-source-manifest.json`（2026-10-25T07:32:07.383Z）匹配，创建前再次检查。pipeline_task.go/task_phase_timing.go作为直接helper自行记录raw hash；它们不在该manifest的已列文件中时不冒称pin匹配。仅记录静态身份，不重做这两个文件的全量审计。

最终目标通过临时评审文本以open('xb')（wx/exclusive create）创建并读回核验，不覆盖已有报告或修改产品树。

### Final raw SHA-256 snapshot

Pin: `terminal-fence-20261025T060611Z-n2-green1-source-manifest.json`

| File | Bytes | SHA-256 | Status |
|---|---:|---|---|
| `server/internal/daemon/daemon.go` | 488536 | `782be873397f204d3f2aae76579333707b754527143ed51449e33f232f538859` | MATCH |
| `server/internal/daemon/execution_terminal_claim.go` | 4056 | `dfd5d25d220f6a4922e6e287161cb18602e20c8b9a5b60c34c4616c778e0658e` | MATCH |
| `server/internal/daemon/execution_terminal_generation_test.go` | 19685 | `2ca150e828f1715f2016bca29959a9fea2cc97f5d9402da135b760aedc8438bc` | MATCH |
| `server/internal/daemon/execution_verifier.go` | 5580 | `f4796e3f8b9a1186abc1ca46eb08df352a094a034ae31f5bcf209bcdbd5e1161` | MATCH |
| `server/internal/daemon/client.go` | 61517 | `916edf84ef90c6749d026a9de7ca478d9e6b788360ddf98ce0ccdbfb68eaa01d` | MATCH |
| `server/internal/daemon/terminal_report_queue.go` | 37999 | `da15ba13c4a9728613fe64ef75d30e356b0a5450c4676efe3e7b82feb2816f6f` | MATCH |
| `server/internal/daemon/pipeline_task.go` | 48809 | `8cb7171798f7ee53923658f73751213860bf9caf861f4830f83ad27193e04922` | supporting read |
| `server/internal/daemon/task_phase_timing.go` | 3228 | `3e3eb55c97e5eab0ff6be0434cda3c3fd73efb11141888413fe6048ea1d5c1c5` | supporting read |

Creation UTC: 2026-10-25T07:36:18.219411+00:00
