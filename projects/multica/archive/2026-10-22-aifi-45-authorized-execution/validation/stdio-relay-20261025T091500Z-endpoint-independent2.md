# per-run binding endpoint green3 独立回归与 B/D 复判

- at: 2026-10-25T10:19Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `stdio-relay-20261025T091500Z-endpoint-independent2-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 一条
- 结论: 回归通过；B（并发唯一性）与 D（关闭时机）均已 CLOSED；E1（URL 是 bearer 能力、同 UID 可读 env）**未修复**，仍是明确的非隔离边界。

## 1. 源码冻结（endpoint green3，7 项）

- 清单: `stdio-relay-20261025T091500Z-endpoint-green3-source-manifest.json`
- 清单 sha256: `bcdb6643a28dba0ae232c5d6d5f8d58f839814adb6f2202b01133f95c3a953c6`
- pre-run pin: `stdio-relay-20261025T091500Z-endpoint-independent2-daemon-source-manifest.json`，sha256 `9753a7258a09b0f80583031a74ba152f0478690731254e7dcc4b6093d2846015`
- 清单按 `raw_sha256` + `bytes` 记录；7/7 跑前一致，跑后再次一致（无漂移）。
- green2 作废；本轮只以 green3 为准。

## 2. 回归计数

命令（cwd=`C:/Users/GOBAO/Downloads/AI/multica`）：

`node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(Execution|RequestExecutionBinding|ParseBindingChallengeLine|TerminalReport|SendTerminalTaskReport)' "<V>/stdio-relay-20261025T091500Z-endpoint-independent2-daemon" -timeout=280s`

| nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---:|---:|---:|---:|---:|---:|---:|
| `69a42311e77f4449` | 0 | 150 | 148 | 0 | 2 | 136 | 2 |

- meta：`error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- before/after 与 `current-bindings-20261025T034807Z-preflight.json` 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog：role `411073` / db `411074`，末尾 `database_present=false`、`role_present=false`。
- migrations 为空。
- SKIP 单列（不计 PASS）：`TestExecutionBindingRelayHelperProcess`（helper 子进程）、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）。

### 关键用例是否真跑

| 用例 | 实际动作 | Elapsed | 是否 SKIP |
|---|---|---:|---|
| `TestExecutionBindingEndpointSignsOnceUnderConcurrency` | `pass` | **0s** | 否 |
| `TestExecutionBindingEndpointEligibility` 5 子例 | 全部 `pass` | — | 否 |

Eligibility 5 子例：`no_client`、`task-scoped_(legacy)_daemon`、`daemon_token_but_no_CR`、`daemon_token_and_CR_but_no_generation`、`daemon_token,_CR_and_generation`。

## 3. 7/7 hash 前后

| 时点 | 7/7 raw hash 与 endpoint green3 |
|---|---|
| 跑前 pre-run pin | 一致 |
| 跑后复核 | 一致 |
| 最终 | **一致** |

## 4. B / D 复判

### B. 并发唯一性：CLOSED

- `execution_binding_endpoint.go:49` 增加 `claimed atomic.Bool`。
- `serve` 在任何 body 读取/签名前执行 `e.claimed.CompareAndSwap(false, true)` — `:108-119`；第二个请求直接得 `409` + `{"error":"EXECUTION_BINDING_ALREADY_CLAIMED"}` — `:115-119`。
- 测试 `TestExecutionBindingEndpointSignsOnceUnderConcurrency`（test 文件 `:71-110`）并发 8 个 POST，断言 exactly 1 个 `200`、`fakeBindingSigner.calls == 1`；本轮实际 PASS。
- 因此上一轮“重叠请求可各自签一份”的窗口已关闭。
- 附带事实：CAS 在 body 校验之前；若首个请求 body 非法，唯一名额会被消耗。这不影响并发唯一性结论，但“第一个请求失败后还能重试”并不成立。

### D. 关闭时机：CLOSED

- 成功响应后已**删除** `go e.Close()`；`serve` 末尾只保留 “No self-close here” 注释（`:145-148`）。
- 非测试代码中唯一 `bindingEndpoint.Close()` 是 `runTask` 的 `defer` — `daemon.go:8750-8752`；`runTask` 返回时才关闭。
- 因此成功响应不再被“答后自关”截断；端点随 run 生命周期结束（有成功请求时也不提前自关）。
- `Close` 仍是立即关闭监听/服务器（endpoint.go:58-66），不会等待 keep-alive；但在本路径上只由 runTask 的 defer 触发。

## 5. E1：未修复，仍如实记录

- URL 含 nonce：`execution_binding_endpoint.go:72-83`；通过 `MULTICA_EXECUTION_BINDING_ENDPOINT` 注入该 run 的 agentEnv：`daemon.go:8750-8752`。
- 端点没有 caller 认证，nonce 就是 bearer 能力。同机同 UID 进程可从子进程环境（Linux 常见为 `/proc/<pid>/environ`，受 hidepid 等限制）或子进程继承/日志取得 URL；Windows 没有 `/proc`，但同一用户仍可通过进程环境/调试或子进程日志暴露。
- 所以“只给本 run”若指投递范围（只注入本 run、端点随 run 结束）成立；若指“同 UID 其他进程无法获取/冒用”则不成立。**E1 未被本轮修复，而是被如实记录为限制**。

## 6. 边界

- 端点 ≠ 准入；只签发 envelope，不写 receipt、不消费、不激活。消费/准入仍关闭。
- 未接 T 侧消费；不签 activation/隔离域/全局 C1。
- 同 UID 不隔离：env/nonce 暴露面仍存在，relay/管道也不是 containment。
- 旧 claim 锁序仍 INCOMPLETE；业务 TC 0/49，5 major 未关闭。
- 未访问真实 CR、未做真实模型调用、未写原库。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
