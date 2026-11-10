# per-run execution binding endpoint 独立回归与判定

- at: 2026-10-25T10:06Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `stdio-relay-20261025T091500Z-endpoint-independent-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 一条
- 结论: 基线回归通过；A–D 代码判定见下。端点仍不是准入/token 隔离，消费关闭。

## 1. 源码冻结（endpoint green2，7 项）

- 清单: `stdio-relay-20261025T091500Z-endpoint-green2-source-manifest.json`
- 清单 sha256: `857f37c9f60014d9c74775e784f48afa6ab26c0bd0df0640fb0a84f7e3e4074d`
- pre-run pin: `stdio-relay-20261025T091500Z-endpoint-independent-daemon-source-manifest.json`，sha256 `3ea3470cc6eb13d3928a68b5acad829bf477c881c178eb091bb09a65ef14a580`
- 清单只按 `raw_sha256` + `bytes` 记录；7/7 跑前一致，跑后再次一致（无漂移）。

| 文件 | raw sha256 |
|---|---|
| `execution_binding_client.go` | `770c58ed…21ce0` |
| `execution_binding_client_test.go` | `f4e0d68c…04250` |
| `execution_binding_relay.go` | `5af9007b…052d3` |
| `execution_binding_relay_test.go` | `f3188ece…e0a96` |
| `execution_binding_endpoint.go` | `f7cf83f3…238bb` |
| `execution_binding_endpoint_test.go` | `8814ac51…f06c3` |
| `daemon.go` | `50f7fb18…daf13` |

## 2. 回归计数

命令（cwd=`C:/Users/GOBAO/Downloads/AI/multica`）：

`node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(Execution|RequestExecutionBinding|ParseBindingChallengeLine|TerminalReport|SendTerminalTaskReport)' "<V>/stdio-relay-20261025T091500Z-endpoint-independent-daemon" -timeout=280s`

| nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---:|---:|---:|---:|---:|---:|---:|
| `7c227905372fa965` | 0 | 149 | 147 | 0 | 2 | 135 | 2 |

- meta：`error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- before/after 与 `current-bindings-20261025T034807Z-preflight.json` 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog：role `405395` / db `405396`，末尾 `database_present=false`、`role_present=false`。
- migrations 为空（本条未带 migration）。
- SKIP 单列：`TestExecutionBindingRelayHelperProcess`（helper 子进程）、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）；均不计 PASS。

### 关键用例是否真跑

`TestExecutionBindingEndpointEligibility` 的 **5 个子例全部 PASS**（实际事件）：

- `.../no_client`
- `.../task-scoped_(legacy)_daemon`
- `.../daemon_token_but_no_CR`
- `.../daemon_token_and_CR_but_no_generation`
- `.../daemon_token,_CR_and_generation`

## 3. 7/7 hash 前后

| 时点 | 7/7 raw hash 与 endpoint green2 |
|---|---|
| 跑前 pre-run pin | 一致 |
| 跑后复核 | 一致 |
| 最终 | **一致** |

## 4. A–D 独立判定

### A. Eligibility 的 5 个子例与 `mdt_` 判定

- 测试确实有 5 个子例：`execution_binding_endpoint_test.go:139-145`，分别对应
  1. no client（`d.client == nil`）；
  2. `mat_` task-scoped legacy（非 `mdt_`）；
  3. `mdt_` 但无 CR；
  4. `mdt_` + CR 但无代次；
  5. `mdt_` + CR + 代次（want true）。
  实际运行 5/5 PASS（上面名单）。
- `NewClient(...).SetToken("mdt_...")` 后 `UsesDaemonToken()` 为 true，代码依据：
  - `SetToken` 直接写 `c.token` — `client.go:249-251`；
  - `UsesDaemonToken` 返回 `strings.HasPrefix(strings.TrimSpace(c.token), "mdt_")` — `client.go:262-263`。
  因此子例 3–5 的 token 路径成立；`mat_task_scoped` 匹配不到 `mdt_`，为 legacy false。
- 端点创建条件本身在 `execution_binding_endpoint.go:144-165`：client 非 nil、`UsesDaemonToken()`、`PipelineCrID` 非空、`DispatchedAt` 非空。

### B. 端点的“唯一性”

**判定：不是严格的并发唯一；存在同一 run 两个并发 POST 都拿到 envelope 的窗口。**

- nonce 只决定路径：`execution_binding_endpoint.go:70-83`；mux 只在 `/binding/<nonce>` 上注册 — `:87`。
- `serve` 没有 mutex、atomic 或 `sync.Once`；任何到达它的 POST 都会校验 body 并调用 signer — `:103-129`。
- 成功写回后才 `go e.Close()` — `:138`；`Close` 调 `server.Close()`/`listener.Close()` — `:53-58`。
- `http.Server` 并发处理请求；`Close` 停止监听并关闭 idle 连接，但已经进入 handler 的并发请求可以继续。因此在 Close 前的重叠请求可以各自调用 signer 并各自写回 envelope。代码注释 `:23` 的“exactly one accepted request”与实现不完全一致；实际是“best-effort one-shot after first response”，不是并发 CAS/once。

### C. URL nonce 经 env 传给子进程的暴露面

**判定：作为“只注入该 run 的环境/该 run 生命周期的端点”成立；作为同 UID 保密边界不成立。**

- URL 含 128-bit nonce — `execution_binding_endpoint.go:72-83`；通过 `MULTICA_EXECUTION_BINDING_ENDPOINT` 注入 agentEnv — `daemon.go:8750-8752`。
- 同机其他进程能否拿到：
  - Linux：同 UID 通常可读 `/proc/<pid>/environ`（受 hidepid 等限制），能拿到该环境变量；子进程的后代也会继承 env。
  - Windows：没有 `/proc`，同一用户进程需通过进程环境读取/调试等机制，不能一概说“任意同机进程都可读”，但也不是隔离边界。
  - 日志：端点代码不记录 URL；但子进程/其工具可以打印该 env 或 URL，日志是否出现取决于子进程行为。
- 因此如果把“只给本 run”理解为投递范围（env 只注入该 run、端点随 run 结束），成立；如果理解为“同 UID 其他进程无法获取/冒用”，则**夸大**。nonce 是 bearer 能力，端点没有 caller 认证。

### D. `runTask` 里 `defer bindingEndpoint.Close()` 的生效时机

- 注入点与 defer 都在 `runTask` 作用域：`daemon.go:8750-8752`，`defer` 在 `:8751`。
- 成功响应时还有一个更早的 `go e.Close()` — `execution_binding_endpoint.go:138`，所以正常情况下**第一次成功 proof 后立即异步关闭**，不等 agent 子进程结束。
- 若整个 run 没有请求，defer 才在 `runTask` 返回时执行；`runTask` 由 `handleTask` 的 runner 调用（`daemon.go:5917`），其返回发生在 agent 运行结束之后。
- 结论：不是“只在子进程结束后才关”；有成功请求时更早关，defer 是 run 作用域的兜底。

## 5. 边界

- 端点 ≠ 准入：它只签发 binding envelope，不写 receipt、不消费、不激活；消费/准入关闭。
- 未接 T 侧消费，也未把 endpoint/relay 变成完整执行域；不签 activation/隔离域/全局 C1。
- 同 UID 不隔离：端点 nonce 经 env 暴露，relay/管道也不是 containment。
- 旧 claim 锁序仍 INCOMPLETE；业务 TC 0/49，5 major 未关闭。
- 未访问真实 CR、未做真实模型调用、未写原库。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
