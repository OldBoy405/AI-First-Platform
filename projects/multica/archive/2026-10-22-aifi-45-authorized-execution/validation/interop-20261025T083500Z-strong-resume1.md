# AIFI-45 interop strong resume1 — 仅复核 I1

## 判定

**I1：CLOSED（限定静态输入隔离根因）。** 负例不再向新 Node 回送旧 Node 的 challenge/PID；现在使用负例自己的 child challenge 取真实 HTTP envelope，只改 canonical task_id 并保留原 signature，再送回同一 child。在当前 fixture/key 文件稳定、服务响应满足已审合同、所读 T 实现不变的正常路径上，输入有意破坏的只有“原签名与修改后 payload bytes 的对应关系”。原先即使删验签也会因旧 challenge 被拒的替代路径已移除。

**“只能因签名失败”不能无条件扩大为任何非零退出都已被测试证明是签名错误。** T 验签之前确有 envelope/base64/key 等检查和文件 I/O；本次构造保持它们合法，但测试末尾仍只断言 err != nil，没有精确核 error/cause_code。随机运行环境失败仍可能被误当负例成功；建议保留结构化错误断言作为健壮性增强，不因此重开本轮已经修复的旧 challenge/PID 混用 I1。

只复核负例构造及 T 的相关检查顺序，没有重开 fixture/生产链全量。**未访问 DB，未运行测试/Node/vet/编译/生成器，未改源码或测试，未使用子代理。** 本报告 wx 独占创建并回读验证。

M 根：`C:/Users/GOBAO/Downloads/AI/multica`；下文 M 文件相对此根。T 根：`C:/Users/GOBAO/Downloads/AI/tools`，下文 T 文件位于 `skills/shared/crctl/scripts/lib/`。

主 pin：`interop-20261025T083500Z-green1-source-manifest.json`，时间 `2026-10-25T08:38:34.794Z`，当前 `server/internal/governance/execution_binding_issue_test.go` 为 36,112 bytes，raw SHA-256 `5a2b7b536ef40313bca3577156009a005adcd6802e436ec4d3ca5aeb2de34ec6`，匹配该 pin。T 两模块与上轮所读身份一致；不冒充 green1 记录了执行时 T 的完整 pin。模型配置背景沿用，actual backend unknown。

## 1. 同一 child 的 challenge→HTTP→变更→回填闭环

- `execution_binding_issue_test.go:862–923`：每次 runChild 启动 Node，读取其 stdout 的 binding_challenge，将该 map 传入 proof callback，callback 的返回值写入该 cmd 的 stdin、关闭 stdin，再等待该 cmd。
- 新负例 `:957–964` 自己定义 callback，body.challenge 就是本次 callback 参数；T/R/G 来自 fixture 的正确 run，不再读 positiveEnvelope，也不忽略新 challenge。
- `:965–980` marshal body 后调用真实 `f.post(t,raw,f.h.token)`，要求 HTTP 200，并从 response.Envelope 解出 envelope；没有生成另一份 binding signature。
- `:981–988` 解出当前 response 的 payload；`:992` 仅给已有 task_id 键赋 `uuid.NewString()`，为 canonical 小写 UUID。其余字段保留，键集合不因替换已有键改变。
- `:993–1002` 重新 marshal payload、StdEncoding base64 编码并写回 PayloadB64，然后 marshal 原 envelope；KeyID 与 Signature 没有赋新值。map 重编码可能改变 raw payload 键序，这也使原签名不再覆盖新 bytes，但不是新增字段或新的语义拒绝原因。
- `:1004–1005` 对该次 runChild 断言非零退出；正例在 `:926–954` 独立运行，不再充当负例的旧 envelope 储存源。

所以 T 收到的新 payload 仍携该 child 的 nonce、roots、PID/PPID、operation 和其 grant/head/deployment 值；没有上轮 C_old≠C_new 的固定拒绝路径。

## 2. T 的实际顺序与本次输入如何保持前置合法

相关真实源码：T `execution-binding.mjs:86–124`，以及它调用的 `execution-authorization.mjs:286–309`。不能把这些前置检查省略为“第一个动作就是 crypto.verify”。

| 检查顺序 / 位置 | 能在 crypto.verify 前失败吗 | 本次构造是否有意破坏 |
|---|---|---|
| binding readProof / Promise.race（binding `:86–98`） | 是：运输 JSON、大小、EOF、15 秒 timeout | 没有。回送 json.Marshal 的 envelope，正常关闭 stdin；不是故意坏 JSON/空输入。运行超时仍是环境边界。 |
| schema 白名单（authorization `:286–289`） | 是 | 没有。高层函数固定传 execution-binding/v1（binding `:100`），不是从被篡改字段选 schema。 |
| envelope exact 三键 + key_id 类型/格式（authorization `:290–293`） | 是 | 没有。仍 marshal 同一个 ExecutionGrantEnvelope，仅修改 PayloadB64；其定义 exact KeyID/PayloadB64/Signature 三字段，未加删 envelope 键。 |
| payload_b64 与 signature 的规范 base64（authorization `:294–295`） | 是 | 没有。新 payload 用 base64.StdEncoding.EncodeToString；signature 字符串来自真实 HTTP response，未改。 |
| 解出 signature 长度为 64 bytes（authorization `:296`） | 是 | 没有。原服务 Ed25519 signature 完整保留，不截断、不替换为空值。 |
| keys 文件存在/containment/size、PEM 解析、Ed25519 key type（authorization `:297–302`） | 是 | 没有。key_id、公钥文件、安装根均未改；child 在出 challenge 前已由 readExecutionGrant 读取同一 fixture 的服务公钥验 initial grant。文件稳定这一前提仍不能替代 error 分类。 |
| domain + raw bytes 后 crypto.verify（authorization `:303–306`） | **本次有意失败点** | 原 signature 对应原 payload；task_id/重编码后的 payload bytes 已不同，验证应失败。 |
| payload JSON 解析（authorization `:307`）与 binding expected/20 键/身份形状（binding `:104–124`） | **都在验签之后** | 新 payload 仍合法 JSON/20 键，其余 expected 值不变；task_id 是 canonical UUID，不会因形状被拒。 |

若 crypto.verify 返回 false，authorization 抛 `EXECUTION_GRANT_SIGNATURE_INVALID`；binding `:100–102` 再包装为 `EXECUTION_BINDING_INVALID`，extra.cause_code 为原错误码。因此只看外层 binding 错误码仍不足以区分 base64/key/signature，应检查 cause_code。

## 3. task_id 修改是否会触发另外一个字段拒绝？

**在所读 T 合同下不会。** `execution-binding.mjs:104–113` 的 expected 没有固定 task_id/runtime_id 值；`:114–121` 将它们列为 identities，仅要求字符串与 canonical UUID regex，而非等于 fixture 的原 task。

因此新的 canonical task_id 仍通过该形状条件；20 键不变、daemon_id/root/nonce/PID/head 等都来自同一 child 对应 response，并未被 mutation 改动。如果仅去掉签名比较而保留其他解析/字段校验，这个经过同 child HTTP 构造的负例在正常前提下应能被接受，从而使本负例测试失败——这正是上轮缺失的隔离性。

这不等于服务端会接受自报的另一个 task_id：服务端 HTTP 已先按原正确 run 验证并签发，篡改发生在 response 之后，服务端没有对篡改版本重新签名。也不改变 T 只校 UUID 形状的既有信任上限；不在本轮扩成生产任务/进程身份评审。

## 4. 剩余断言上限与证据

- 最后仍是 `if _,err := runChild(...); err == nil { Fatal }`（`:1004–1005`），没有解析 child stderr/cause_code。源码注释 `:989–991` 的“only possible rejection reason”宜理解为**在受控合法 fixture 下唯一刻意制造的合同失败**，不是说 OS/文件 I/O/超时等不可能失败。
- 推荐 Node catch 输出结构化 code/extra.cause_code，并断言 cause_code 精确为 EXECUTION_GRANT_SIGNATURE_INVALID，同时保留正常 exit/异常退出分类。此建议不要求本轮改源码；不会为了未跑新测试而将已修输入混用根因标成 PARTIAL。
- 只读核验 `green1.meta.json` 和 stdout.jsonl，统计 **3 RUN / 3 PASS / 0 FAIL / 0 SKIP，2 leaf**，匹配作者摘要及当前测试 pin。作者记录原库 unchanged/released、临时资源 cleaned；本评审没有访问 DB 或独立执行这些事实。
- 该记录没有保存被断言的签名错误 cause，也没有“移除验签后负例变红”的 mutation 执行；本轮只是静态分析该反事实，不冒充已经运行过 mutation。
- 本轮未确认新的独立 P0/P1/P2。未重评上轮其他健壮性、安装模式、root provenance 或生产链边界。

**限定结论：I1 的跨 child 旧 challenge/PID 替代拒绝根因 CLOSED；本次 mutation 保持验签前结构/编码/长度/key 条件合法，正常路径下刻意制造的失败只有签名不再匹配；任意非零退出的精确 cause 仍未被测试断言。不签消费/准入/activation/隔离域/全局 C1/进程身份；旧 claim 锁序 INCOMPLETE；TC 0/49；5 major 未关闭；消费 closed/off。**

## 附：发布前身份核对

时间：`2026-10-25T08:41:42.073519+00:00`。M 测试 raw pin 再匹配；T 两模块再匹配本轮读取样本，不代表 green1 记录了它们的运行时身份。

- M `server/internal/governance/execution_binding_issue_test.go` — 36112 bytes，SHA-256 `5a2b7b536ef40313bca3577156009a005adcd6802e436ec4d3ca5aeb2de34ec6`。
- T `skills/shared/crctl/scripts/lib/execution-binding.mjs` — 7262 bytes，SHA-256 `8fe71e0f5fc48a524763a63641a43052fff78fc25868017669516297b03ba95d`。
- T `skills/shared/crctl/scripts/lib/execution-authorization.mjs` — 22367 bytes，SHA-256 `71437e20ddfdf33b74d3490c7129359562443555d1abc0a44886b27f32c34abc`。

Go envelope exact 三字段定义补充行号：`server/internal/governance/execution_authorization.go:165–169`（KeyID/PayloadB64/Signature；无其他字段）。该 helper 发布时取样 44721 bytes，SHA-256 `0c68aca15dd2a57e8a407e5f76a98df264ceec52b31a38433a618cf4ba96a074`，不扩成 green1 已测 pin。
