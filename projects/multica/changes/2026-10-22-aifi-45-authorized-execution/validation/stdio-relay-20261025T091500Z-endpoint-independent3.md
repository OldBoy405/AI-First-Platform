# per-run binding endpoint green4 终轮独立回归

- at: 2026-10-25T10:21Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `stdio-relay-20261025T091500Z-endpoint-independent3-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 一条
- 结论: 回归通过；「畸形请求不烧名额」新断言实际 PASS；E1 仍未修复，URL 仍是 bearer 能力，不构成隔离。

## 1. 源码冻结（endpoint green4，7 项）

- 清单: `stdio-relay-20261025T091500Z-endpoint-green4-source-manifest.json`
- 清单 sha256: `6f6e795eeed9028ae76f767ce4548b674ce263b148cda8b1314067ab2629bed7`
- pre-run pin: `stdio-relay-20261025T091500Z-endpoint-independent3-daemon-source-manifest.json`，sha256 `1477ac0b5cbe636b7db80f1c41c2f50fe3b1a68e962dc86108398c0ff4e082f8`
- 清单按 `raw_sha256` + `bytes` 记录；7/7 跑前一致，跑后再次一致（无漂移）。
- 相对 green3：`execution_binding_endpoint.go` 与 `execution_binding_endpoint_test.go` 变化，其余 5 项相同。

## 2. 回归计数

命令（cwd=`C:/Users/GOBAO/Downloads/AI/multica`）：

`node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(Execution|RequestExecutionBinding|ParseBindingChallengeLine|TerminalReport|SendTerminalTaskReport)' "<V>/stdio-relay-20261025T091500Z-endpoint-independent3-daemon" -timeout=280s`

| nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---:|---:|---:|---:|---:|---:|---:|
| `284409086c07615b` | 0 | 150 | 148 | 0 | 2 | 136 | 2 |

- meta：`error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- before/after 与 `current-bindings-20261025T034807Z-preflight.json` 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog：role `416754` / db `416755`，末尾 `database_present=false`、`role_present=false`。
- migrations 为空。
- SKIP 单列（不计 PASS）：`TestExecutionBindingRelayHelperProcess`、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）。

## 3. 7/7 hash 前后

| 时点 | 7/7 raw hash 与 endpoint green4 |
|---|---|
| 跑前 pre-run pin | 一致 |
| 跑后复核 | 一致 |
| 最终 | **一致** |

## 4. 新断言：畸形请求不烧名额

- 代码：`CompareAndSwap` 已移到 body 校验之后 — `execution_binding_endpoint.go:125-128`；注释明确 “Claim only after the request is well formed”。
- 用例：`TestExecutionBindingEndpointRefusesWithoutAProof`，其中 “A malformed request must not burn the run's single shot” 在 `execution_binding_endpoint_test.go:196-207`：先发畸形请求，再发合法请求，断言合法请求得到 `200` 且 `signer.calls == 1`。
- 实际运行：该用例 **PASS**（不是 SKIP），Elapsed=0s；同轮 `TestExecutionBindingEndpointSignsOnceUnderConcurrency` 也 PASS（8 并发仍 exactly 1 次签发）。
- 结论：畸形请求不再消耗唯一名额；并发唯一性仍由 CAS 保证。

## 5. E1：仍未修复

- URL 含 nonce — `execution_binding_endpoint.go:72-83`；经 `MULTICA_EXECUTION_BINDING_ENDPOINT` 注入 agentEnv — `daemon.go:8750-8752`。
- 端点无 caller 认证，nonce 即 bearer 能力。同 UID 进程可从子进程环境（Linux 常见 `/proc/<pid>/environ`，受 hidepid 等限制）、子进程继承或日志取得 URL；Windows 无 `/proc`，但同用户仍可通过进程环境/调试或子进程日志暴露。
- 因此 “只给本 run” 只在投递范围/生命周期意义上成立；**不作为同 UID 隔离边界**。E1 未被本轮修复，报告如实记录。

## 6. 边界

- 端点 ≠ 准入；只签发 envelope，不写 receipt、不消费、不激活；消费/准入关闭。
- 未接 T 侧消费；不签 activation/隔离域/全局 C1。
- 同 UID 不隔离：env/nonce 暴露面仍存在。
- 旧 claim 锁序仍 INCOMPLETE；业务 TC 0/49，5 major 未关闭。
- 未访问真实 CR、未做真实模型调用、未写原库。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
