# stdio relay green4 终轮独立回归报告

- at: 2026-10-25T09:59Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `stdio-relay-20261025T091500Z-independent3-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 一条
- 结论: green4 基线回归通过；`TestExecutionBindingRelayStopsWhenTheChildNeverFinishes` 实际 PASS（非 SKIP），耗时 0.5s。relay 仍未接入 `handleTask`，不构成隔离；消费/准入关闭。

## 0. 源码冻结（green4，4 项）

- 清单: `stdio-relay-20261025T091500Z-relay-green4-source-manifest.json`
- 清单 sha256: `f549ce4f9bbeef40df0d793bf714c51fea1a99500eb907951490718a3f2b2ae6`
- pre-run pin: `stdio-relay-20261025T091500Z-independent3-daemon-source-manifest.json`，sha256 `ffadf2d70c46c1cdb934ea32547c527310ca27481eb2ff2d0ca93439303536b0`
- 清单只按 `raw_sha256` + `bytes` 记录；4/4 跑前一致，跑后再次一致（无漂移）。

| 文件 | 跑前/跑后 raw sha256 | 结果 |
|---|---|---|
| `execution_binding_client.go` | `770c58eddc28c3a6e0ea9461d423727f0a40bf207ac158be240688a863a21ce0` | 一致 |
| `execution_binding_client_test.go` | `f4e0d68c424943f2da0dca888d1a2e0208ababae6b43fe5ec6afaf7179704250` | 一致 |
| `execution_binding_relay.go` | `5af9007be619c8673cbeb46dc0859aec40c319de8fab0e2af3e48a8cb5d052d3` | 一致 |
| `execution_binding_relay_test.go` | `f3188ece9a2cc70cdcdde18cb3d8c33e61ed49dd2e5a1d97c56e43e3e1ce0a96` | 一致 |

## 1. 回归计数

命令（cwd=`C:/Users/GOBAO/Downloads/AI/multica`）：

`node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(Execution|RequestExecutionBinding|ParseBindingChallengeLine|TerminalReport|SendTerminalTaskReport)' "<V>/stdio-relay-20261025T091500Z-independent3-daemon" -timeout=280s`

| nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---:|---:|---:|---:|---:|---:|---:|
| `581e7dd5a3244440` | 0 | 140 | 138 | 0 | 2 | 127 | 2 |

- meta: `error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`、`output_redacted=false`。
- before/after 与 `current-bindings-20261025T034807Z-preflight.json` rows 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog: role `396875` / db `396876`，末尾 `database_present=false`、`role_present=false`。
- 迁移记录为空（本条命令未带 migration）。

### SKIP 单列（不计 PASS）

| SKIP | 性质 |
|---|---|
| `TestExecutionBindingRelayHelperProcess` | helper 子进程专用，非测试本体 |
| `TestExecutionTrustRefusesLinkedRootInsideWorkspace` | Windows symlink 权限 |

## 2. 4/4 hash 前后

| 时点 | 4/4 raw hash 与 green4 清单 |
|---|---|
| 跑前 pre-run pin | 一致 |
| 跑后复核 | 一致 |
| 最终 | **一致** |

未修改任何源文件；无临时测试文件残留。

## 3. 关键用例是否真跑

| 用例 | 实际动作 | 耗时 | 是否 SKIP |
|---|---|---|---:|
| `TestExecutionBindingRelayStopsWhenTheChildNeverFinishes` | `pass` | **0.5s** | 否 |

- 该用例在 `*.stdout.jsonl` 中有唯一 PASS 事件，`Elapsed=0.5s`；不是 SKIP，也不是父级代替子级。
- green3 轮发现的“超时杀子进程但 `err=nil`”行为，由作者修复；本轮该用例真实通过。

## 4. 边界

- relay **尚未接入 `handleTask`**：非测试代码没有对 `relayExecutionBinding` 的调用者；本片不能当作任务执行路径已使用中继。
- relay 的 stdio 是 daemon 与单个子进程的私有管道，但**不是隔离**：同 UID 进程仍可读同 UID 管道；不构成隔离执行域。
- 消费/准入关闭；不签 activation、隔离域或全局 C1。
- 旧 claim 锁序仍 INCOMPLETE；完整业务 TC 仍 **0/49**，5 major 未关闭。
- 未访问真实 CR、未做真实模型调用、未写原库。
- 请求配置 requested `Gobao/deepseek-flash/max`（configured schema1），actual unknown。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
