# per-run binding endpoint interop 终轮独立回归

- at: 2026-10-25T11:54Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `stdio-relay-20261025T091500Z-endpoint-independent4-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 一条
- 结论: 回归通过；真 T 侧 node 传输互通用例实际 PASS（非 SKIP）；端点仍不认证调用方，消费关闭。

## 1. 源码冻结（endpoint green7，8 项）

- 清单: `stdio-relay-20261025T091500Z-endpoint-green7-source-manifest.json`
- 清单 sha256: `6e28cc0161a6fc88e2d349025c7915a6846df22e6561333cc72ae53fb163edf2`
- pre-run pin: `stdio-relay-20261025T091500Z-endpoint-independent4-daemon-source-manifest.json`，sha256 `ce05614c94a0b84066a8b38992fa5e0c4ba25897accedfaeefd4fef65f1967ee`
- 清单按 `raw_sha256` + `bytes` 记录；8/8 跑前一致，跑后再次一致（无漂移）。

## 2. 回归计数

命令（cwd=`C:/Users/GOBAO/Downloads/AI/multica`，设置 `AIFI45_TOOLS_ROOT=C:/Users/GOBAO/Downloads/AI/tools`）：

`node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(Execution|RequestExecutionBinding|ParseBindingChallengeLine|TerminalReport|SendTerminalTaskReport)' "<V>/stdio-relay-20261025T091500Z-endpoint-independent4-daemon" -timeout=280s`

| nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---:|---:|---:|---:|---:|---:|---:|
| `20efda39608773ac` | 0 | 153 | 151 | 0 | 2 | 138 | 2 |

- meta：`error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- before/after 与 `current-bindings-20261025T034807Z-preflight.json` 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog：role `433800` / db `433801`，末尾 `database_present=false`、`role_present=false`。
- migrations 为空。
- SKIP 单列（不计 PASS）：`TestExecutionBindingRelayHelperProcess`（helper 子进程）、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）。

## 3. 8/8 hash 前后

| 时点 | 8/8 raw hash 与 endpoint green7 |
|---|---|
| 跑前 pre-run pin | 一致 |
| 跑后复核 | 一致 |
| 最终 | **一致** |

## 4. 真 T 侧传输互通用例

环境变量已设置，未触发 `AIFI45_TOOLS_ROOT not set` / tools transport missing / node missing 的 SKIP 分支。

| 子用例 | 实际动作 | 耗时 |
|---|---|---:|
| `TestExecutionBindingEndpointInteropWithToolsTransport/proof_is_delivered` | `pass`（非 SKIP） | **0.09s** |
| `TestExecutionBindingEndpointInteropWithToolsTransport/refusal_reaches_T_as_unavailable` | `pass`（非 SKIP） | **0.08s** |

父用例 `TestExecutionBindingEndpointInteropWithToolsTransport` 也为 `pass`（Elapsed 0.18s）；两个子例均未 Skip。

## 5. 边界

端点不认证调用方（nonce 为 bearer 能力，同 UID 环境暴露面仍在）；消费仍关闭，未接 T 侧消费；不签 activation/隔离域/全局 C1。旧 claim 锁序 INCOMPLETE；业务 TC 0/49，5 major 未关闭。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
