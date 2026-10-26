# stdio relay green3 独立回归与鉴别力实验报告

- at: 2026-10-25T09:54Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `stdio-relay-20261025T091500Z-independent2-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs`，逐条串行
- 结论: 基线回归通过；判定 1 和 3 被现有测试抓到；判定 2（临时 hung-child 测试）揭示 relay 在自设 30s 内返回但 **err=nil**。relay 仍未接入 `handleTask`，不构成隔离；消费/准入关闭。

## 0. 源码冻结（green3，4 项）

- 清单: `stdio-relay-20261025T091500Z-relay-green3-source-manifest.json`
- 清单 sha256: `8ffe496cf3d5fcff20937f9c244e348c5a73a600d3e07c70ef77feeb59072822`
- **该 green3 清单只有 `raw_sha256` + `bytes`，没有 `lf_sha256` 字段**；4/4 核验按清单实际字段做 raw sha256 + 字节数，均一致。
- pre-run manifest: `stdio-relay-20261025T091500Z-independent2-daemon-source-manifest.json`，sha256 `c65a189c379a64288d8126682504b801e64ce01b88fdcecaa33d7c59fc12c4d7`，4/4 匹配。
- 4 项最终 raw hash:
  - `execution_binding_client.go` `770c58eddc28c3a6e0ea9461d423727f0a40bf207ac158be240688a863a21ce0`
  - `execution_binding_client_test.go` `f4e0d68c424943f2da0dca888d1a2e0208ababae6b43fe5ec6afaf7179704250`
  - `execution_binding_relay.go` `bc5cc094b9625fd90ee57556ebaff60a0eaf57c3da6e2d67fbf9534737b52a68`
  - `execution_binding_relay_test.go` `d79466053f181f6f478743619d02bba7f26b1c8f81e18a6d79b54c2eaed5b953`

## 1. 基线回归

命令（cwd=`C:/Users/GOBAO/Downloads/AI/multica`）：

`node scripts/aifi45-db/run.mjs ./internal/daemon '^Test(Execution|RequestExecutionBinding|ParseBindingChallengeLine|TerminalReport|SendTerminalTaskReport)' "<V>/stdio-relay-20261025T091500Z-independent2-daemon" -timeout=280s`

| nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | 结果 |
|---|---:|---:|---:|---:|---:|---:|---|
| `4f868aac5839eaf4` | 0 | 139 | 137 | 0 | 2 | 126 | 通过 |

- meta: `error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- before/after 与 `current-bindings-20261025T034807Z-preflight.json` rows 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog: role `377002` / db `377003`，末尾 `database_present=false`、`role_present=false`。
- SKIP（不计 PASS）：`TestExecutionBindingRelayHelperProcess`（仅 helper 子进程）、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）。helper 只 SKIP，未当 PASS。
- 跑后 4/4 hash 仍与 green3 一致。

## 2. 三个鉴别力判定

### 判定 1：签发失败分支 `return result, err` → `return result, nil`

- 实际改动位置：`execution_binding_relay.go` signer error 分支（`result.StderrTail = stderr.String()` 后一行）。
- 实测：RUN 139 / PASS 136 / FAIL 1 / SKIP 2，PASS leaf 125，runner exit 1。
- **被抓到**：失败测试 `TestExecutionBindingRelayFailsClosedWhenSigningFails`。
- meta 仍 `original_unchanged=true`、`owned_resources_cleaned=true`、sessions/locks=0；catalog 精确不存在（role 379841 / db 379842）。
- 已还原；还原后 4/4 raw hash 与 green3 一致。

### 判定 2：子进程写 challenge 后既不读 stdin 也不退出

- 临时测试：`server/internal/daemon/zz_relay_hang_investigation_test.go`（用 test binary 自重启 helper；helper 写出 challenge 后 sleep，不读 stdin、不退出）。
- 实测（`go test ./internal/daemon -run '^TestRelayHungChildTimeout$' -count=1 -timeout=60s -v`）：
  - elapsed: **30.0031106s**（≤40s，符合自设 30s 超时）
  - result: `ExitCode=1`，Challenge/Envelope 有值，StderrTail 空
  - **err = nil**
  - 临时测试因此 FAIL（断言 err != nil 不成立），`TEMP_TEST_EXIT=1`
- 结论：relay 会在自设超时内结束并杀掉子进程，但把超时杀进程产生的 `*ExitError` 当普通孩子退出吞掉，**没有返回 error**。这是 baseline 产品代码的实际行为，不是测试环境挂死。
- 临时测试文件已删除（`TEMP_EXISTS=false`）；删除后 4/4 hash 与 green3 一致。

### 判定 3：裸 envelope → `{"envelope":…}` 外壳

- 有效 mutation：`stdio-relay-...-independent2-mut3d-wrapper`，把回写改为 `{"envelope":<envelope>}` + 换行。
- 实测：RUN 139 / PASS 136 / FAIL 1 / SKIP 2，PASS leaf 125，runner exit 1。
- **被抓到**：`TestExecutionBindingRelayDeliversEnvelopeToThisRun` 失败，错误文本显示 child 收到的正是 `{"envelope":…}`，不是裸 proof。
- meta 仍 `original_unchanged=true`、`owned_resources_cleaned=true`、sessions/locks=0；catalog 精确不存在（role 391197 / db 391198）。
- 已还原；最终 4/4 raw hash 与 green3 一致。

**过程噪声（不作为判定结果）**：wrapper mutation 先有两次 anchor 未命中（未改文件，跑成基线）和一次插入换行导致编译失败（0 RUN）；这三次不是有效 mutation 证据。有效结果只取 `mut3d-wrapper`。所有尝试均清理临时库/role，未写原库。

## 3. 每步后的 4/4 hash

| 步骤 | 4/4 raw hash 与 green3 | 说明 |
|---|---|---|
| 跑前 | 一致 | pre-run manifest 已 wx 落盘 |
| 基线后 | 一致 | 4/4 匹配 |
| 判定 1 还原后 | 一致 | `execution_binding_relay.go` `bc5cc094…52a68` |
| 判定 2 临时测试删除后 | 一致 | 未改 4 项源文件；helper 文件已删 |
| 判定 3 还原后 | 一致 | `bc5cc094…52a68` |
| 最终 | **一致** | `FINAL_4OF4=true` |

- `git status --porcelain --` 显示这 4 个文件在实验前后都是 `??`（未跟踪）；因此 `git diff --stat` 为空是正常的，**不能用它证明内容一致**。内容一致性以上述 raw sha256 + bytes 为准。
- 未改其他产品/测试文件；临时测试已删。

## 4. 边界与事实

- **relay 尚未接入 `handleTask`**：非测试代码中对 `relayExecutionBinding` 的引用只有定义本身，没有调用者；本片不能当作任务执行路径已使用中继。
- relay 的 stdio 是 daemon 与单个孩子的私有管道，但**不是隔离**：同 UID 进程仍可读同 UID 管道；不构成隔离执行域。
- 签发/验证仍不等于消费；准入/activation/隔离域/全局 C1 均未签。
- 旧 claim 锁序仍 INCOMPLETE；完整业务 TC 仍 **0/49**，5 major 未关闭，消费关闭。
- 未访问真实 CR、未做真实模型调用、未写原库。
- 请求配置 requested `Gobao/deepseek-flash/max`（configured schema1），actual unknown。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
