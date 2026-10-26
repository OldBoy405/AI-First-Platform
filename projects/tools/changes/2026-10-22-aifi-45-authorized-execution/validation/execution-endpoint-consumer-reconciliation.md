# T 侧消费 + 端点幂等：对独立审阅意见的逐条核对

> 独立代理（`obs_24f689b2ee…`）的完整报告未被写入磁盘（它到回合上限、无法调用 write）。它在回复里给了三条结论；本条只核对事实，不改它已说过的话。

## 1. 它的"致命 wire mismatch"结论 **不成立**（已核实）

它主张：服务端返回 `{"envelope":…,"changed":…}`，而 T 拒绝剥壳 ⇒ HTTP 路径必然失败。

**错在对端认错了**：T 的 HTTP 分支连的是 **daemon 的 per-run 端点**，不是服务端签发端点。链条是：

```
T  ──POST {"challenge":…}-->  daemon 端点 (execution_binding_endpoint.go)
                                  │  调 Client.requestExecutionBinding
                                  ▼
                             服务端 POST …/binding  →  {"envelope":…,"changed":…}
                                  │  daemon 客户端解析 json:"envelope" → signed.Envelope
                                  ▼
T  <── 裸 envelope ───────────  daemon 端点 w.Write(append(signed.Envelope,'\n'))
```

依据：
- `multica/server/internal/daemon/execution_binding_client.go`：响应结构体字段 `Envelope json.RawMessage \`json:"envelope"\`` —— 外壳由 **daemon** 拆，不需要 T 拆；
- `multica/server/internal/daemon/execution_binding_endpoint.go`：`w.Write(append(signed.Envelope,'\n'))` —— 端点发的是 **裸证明文档**；
- `TestExecutionBindingEndpointServesOneProof` 断言「响应体 == 裸 envelope」，且 `TestExecutionBindingEnvelopeInteropWithToolsVerifier` 早已证明 T 接受裸 envelope。

所以"HTTP 分支 100% 不可用"是**误判**；但它的底层直觉（"这条链上同时存在带外壳和不带外壳两种 JSON"）是对的，也正因如此，T 侧 `does not unwrap` 断言才有意义。

## 2. 它的超时窗口结论 **成立**，已修

它指出：T 15s 超时先放弃、daemon 端点整体 30s，唯一名额在签发前被占 ⇒ 同 run 重试永远 409。这是真实的可用性缺陷。

**修法**（`endpoint-green5`/`green6`）：端点从"一次性布尔"改成"一次性**challenge**"：

- 首个 well-formed challenge 占用名额；
- **同一 challenge 的重放放行**（服务端对同 challenge 是幂等重放，返回同一 envelope），所以 T 超时后可以安全重试；
- **不同 challenge 一律 409**，乱换 challenge 不能拿到第二份证明。

并发测试同步修正为「8 个**不同** challenge 并发 → 恰好 1 个 200、signer 只 1 次」，并新增「同 challenge 重放 → 200 且体相同」「不同 challenge → 409」。

**T 侧收尾（同轮完成）**：`fetchExecutionBindingOverHTTP` 现在最多两次尝试、两次携带**同一串 challenge 字节**（不会重新生成 nonce），且**只对 5xx/网络失败重试**，4xx 一律终态。新增两个用例把这两件事钉住（`a timed-out attempt is retried with the same challenge`、`a 5xx is retried but a 4xx is not`），RED 探针（重试时重新生成 nonce）可使其失败。

## 3. 它的测试强度意见 **部分成立**

- `does not unwrap a wrapped response` 有鉴别力（RED 探针把剥壳加回去后该用例失败）；
- 但 `posts only the challenge` 的"单键"是 T 约束自己，daemon 端点用 typed `json.Unmarshal` 会忽略多余键 —— 这条已在文档里改成"T 只发单键"，不再宣称"端点只接受单键"；
- 它指出**缺一条"env → HTTP 传输选择"的端到端断言**：确实缺。当前只有单元级的 `fetchExecutionBindingOverHTTP` 测试 + daemon 侧端点测试，**没有**一条"真 crctl + 真 daemon 端点"的互通测试。列为待办（下一步：把 `TestExecutionBindingEnvelopeInteropWithToolsVerifier` 扩成端点模式）。

## 4. 它没覆盖而必须记住的

- 端点替换 + **改写公钥**（同 UID 已实证可行）组合起来才能伪造；只改 env 只能 DoS 或用旧 envelope（`expected.challenge` 绑新 nonce，应被拒）。根因是既有公钥可替换，不是本改动新增。
- 消费仍关闭，T 验完仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出。

## 证据（本片最终）

| 轮次 | 内容 | 结果 |
|---|---|---|
| tools `execution-binding-endpoint.test.mjs` | 6 用例 | 6/6 PASS；RED 探针（多键 + 剥壳）→ 4 pass / 2 fail |
| tools 既有 `execution-authorization.test.mjs` | 真实 T 验签矩阵 | 160/160 PASS |
| multica `endpoint-green5` | 幂等重放改动 | 23/25（1 FAIL：并发用例仍用同一 challenge，属测试未同步） |
| multica `endpoint-green6` | 并发用例改不同 challenge | **25 RUN / 24 PASS / 0 FAIL / 1 SKIP（21 leaf）** |

工作区既有 1 个**与本片无关**的失败（`crctl.test.mjs` owner-set 恢复，HEAD 干净 worktree 299/299 通过、stash 掉本片两个文件后仍失败），必须在 C1–C7 全量门禁前解决。
