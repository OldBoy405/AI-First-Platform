# stdio-relay 增量 3：per-run 单次签发端点 + runTask 接线

> 前两个增量：daemon 能拿到签名（客户端）、daemon 能给**自己 spawn 的子进程**交付（中继）。这个增量解决"run 自己的工具链怎么要证明"——并第一次真正接进 `runTask`。

## 做了什么

`multica/server/internal/daemon/execution_binding_endpoint.go`

- `startExecutionBindingEndpoint(signer, spec)`：在 `127.0.0.1:0` 上开一个**每 run 一个**的端点，路径含 128-bit 随机 nonce；POST `{"challenge":{…}}` → 返回**裸 envelope**。
- 用 `atomic.Bool.CompareAndSwap` 先"占用"再签发：并发第二个请求得 409 `EXECUTION_BINDING_ALREADY_CLAIMED`，**签发只发生一次**。
- 签发失败回 409 `EXECUTION_BINDING_UNAVAILABLE`，**不带任何 proof 形状的字段**。
- 请求体上限 128KiB；只接受 `challenge` 为非空对象；GET 405、错路径 404。
- 端点寿命 = run 寿命（`runTask` 的 `defer Close()`），**不再**在应答后自关。
- `claimed` 从“一次性布尔”改为“**一次性 challenge**”：同 challenge 重放放行（服务端幂等，同 envelope），不同 challenge 409——这样 T 15s 超时后能用同一串 challenge 重试，不会把该 run 的唯一名额烧掉。

`multica/server/internal/daemon/daemon.go`（唯一接线点）

```go
agentEnv := taskMulticaEnvironment(...)
if bindingEndpoint := d.executionBindingEndpointForRun(task); bindingEndpoint != nil {
    defer bindingEndpoint.Close()
    agentEnv[ExecutionBindingEndpointEnv] = bindingEndpoint.URL()
}
```

准入条件（`executionBindingEndpointForRun`）：daemon 持 `mdt_` 令牌 **且** `task.PipelineCrID != ""` **且** `task.DispatchedAt != ""`。任一不满足 → 返回 nil、**不注入任何变量**；启动失败只 warn，run 继续（消费仍关闭，拒绝是 T 自己的事）。

## 这一片被 strong 抓到 1 项 P1 + 3 项 P2（全部如实处理，不是都修掉了）

| 编号 | 问题 | 处置 |
|---|---|---|
| **E1 / P1** | 端点 URL 是一条**可转交的受限代签能力**：拿到 URL 的进程不需要 `mdt_`、也不需要属于这个 run。同 UID 可读子进程环境（Linux `/proc/<pid>/environ`；Windows 也可经调试/继承/日志），所以**它不隔离 run，比"私有 stdio 只给单个 child"弱**。 | **未修，如实记录。** 这是同 UID 威胁模型的直接后果，没有廉价修法；真正的边界是容器。对外**不得**声称"只有本 run 能拿到"。同时确认能力面有限：task/runtime/代次/CR 在服务端被绑死，端点签不出别 run 的证明，也拿不到平台私钥、不是任意任务签名权。 |
| **E2 / P2** | 一次性不原子：`serve` 无 CAS/Once，两个有效并发请求都能进入签发。 | **已修**（`claimed.CompareAndSwap`），并加 `TestExecutionBindingEndpointSignsOnceUnderConcurrency`（8 并发，断言恰好 1 个 200、signer 恰好 1 次）。 |
| **E3 / P2** | 成功后 `go e.Close()` 可能在响应 flush 前切断连接（自截断）。 | **已修**：删掉自关；靠 `claimed` 防重放，靠 run 结束关端点。 |
| **E4 / P2** | 测试假绿：错路径断言在"请求出错"时被跳过；退役断言用 `{}` 重试且不要求真退役。 | **已修**：所有请求错误一律 `t.Fatalf`；重放断言改为"第二个 POST 必须 409 且 signer 只 1 次"。 |
| 措辞 | strong 指出"只接受 challenge 一个键"不成立（typed Unmarshal 忽略多余键）。 | 已从描述中删掉该说法。 |

## 证据

| 轮次 | 内容 | 结果 |
|---|---|---|
| `endpoint-green1` | 端点初版（自关 + 无 CAS） | 4RUN/4PASS（4 leaf），但 `RejectsWrongRequests` 耗时 5.00s（`Shutdown` 等 keep-alive） |
| `endpoint-green2` | 7 项冻结清单（含 `daemon.go` 接线）+ `Close` 改立即关 | 24RUN/23PASS/1SKIP（20 leaf） |
| `endpoint-green3` | **CAS 一次性 + 删除自关 + 测试去假绿** | **25RUN/24PASS/1SKIP（21 leaf）**，原库无漂移 |

SKIP 只有 helper 子进程 guard（中继测试用）。

## 增量 5：跨语言 HTTP 互通（strong/独立都点名的空缺）

`multica/server/internal/daemon/execution_binding_endpoint_interop_test.go`：Go 测试里 spawn **真 node**，import **tools 仓的真实** `fetchExecutionBindingOverHTTP` 打**真 Go 端点**：

- `proof_is_delivered`：T 拿到裸 envelope（断言无 `envelope` 外层、`schema`/`key_id` 正确、challenge 是 T 自己的字节）；
- `refusal_reaches_T_as_unavailable`：端点拒签（409）→ T 报 `EXECUTION_BINDING_UNAVAILABLE`，**拿不到任何 proof 形状的东西**。

依赖 `AIFI45_TOOLS_ROOT` 与 `node`；缺失则 Skip（不伪装通过）。

**证据**：`interop-http-green1` 3 RUN / 0 PASS（Windows ESM 需 `file://` URL，路径直传失败，**不计**）；`interop-http-green2` **3/3 PASS（2 leaf）**；**RED 探针**（端点改回包外壳）→ **3 FAIL**，说明该互通测试确实卡住了“裸 envelope”这个契约。

## 明确没做 / 不得外推

- **没有** T 侧消费（**已由增量 4 补上**，见 `projects/tools/changes/…/validation/execution-endpoint-consumer-20261025T093000Z-report.md`：`crctl` 现在按 `MULTICA_EXECUTION_BINDING_ENDPOINT` 走 HTTP 取证明，验完仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出；本段保留作历史）。
- **不是准入**：端点只签；不写 receipt、不改 CR 事实、不解除 `EXECUTION_CONSUMPTION_REQUIRED`。
- **不是隔离**：同 UID 可读环境拿到 URL（E1）。
- 一个 run 目前只发一次证明；需要第二次（重试）要重新起 run 或后续改成按代次签发——已知限制，未做。
- 未签 activation、隔离执行域、全局 C1；旧 claim 锁序 INCOMPLETE；业务 TC 0/49；5 major 未关闭。

## 终轮独立回归（endpoint-green4，唯一认领）

| 项 | 值 |
|---|---|
| RUN/PASS/FAIL/SKIP | **150 / 148 / 0 / 2** |
| PASS leaf / SKIP leaf | **136 / 2** |
| 原库 | 137 表 / 6228 行 / 82 审批，前后一致 |
| 安全 | `error=null`、`original_unchanged`、`owned_resources_cleaned`、`sessions=0`、`locks=0` |
| 7/7 hash | 跑前跑后一致（`…-endpoint-green4-source-manifest.json`） |
| catalog | role 416754 / db 416755，末尾不存在 |

非作者复判：**B（并发唯一性）CLOSED**（`CompareAndSwap` 在签发前，8 并发恰好 1 个 200、signer 1 次）；**D（关闭时机）CLOSED**（成功不再自关，唯一关闭点是 `runTask` 的 defer）。

作者在本轮前还修了一个非作者发现的小缺陷：CAS 原本在 body 校验**之前**，畸形请求会烧掉该 run 的唯一名额；已移到校验之后，并加断言“畸形请求后仍能成功一次”（`…_test.go:196-207`，实际 PASS）。

**冻结链**：endpoint-green1 → green2 → green3 → **green4（已认领）**；前三轮作废为历史。

## 终轮独立回归（endpoint-green7，唯一认领）

| 项 | 值 |
|---|---|
| RUN/PASS/FAIL/SKIP | **153 / 151 / 0 / 2** |
| PASS leaf / SKIP leaf | **138 / 2** |
| 互通用例 | `proof_is_delivered` PASS 0.09s、`refusal_reaches_T_as_unavailable` PASS 0.08s（**均非 SKIP**） |
| 原库 | 137 表 / 6228 行 / 82 审批，前后一致 |
| 安全 | `error=null`、`original_unchanged`、`owned_resources_cleaned`、`sessions=0`、`locks=0` |
| 8/8 hash | 跑前跑后一致（`…-endpoint-green7-source-manifest.json`） |

**冻结链**：green1 → green2 → green3 → green4 → green5（幂等重放，23/25，用例未同步）→ green6 → **green7（已认领）**。前六轮均作废为历史。
