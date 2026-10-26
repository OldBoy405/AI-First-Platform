# consumption 独立回归 — STOP：运行后源码漂移，最终 13/13 不成立

- at: 2026-10-25T12:07Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `consumption-20261025T100000Z-independent-`
- **结论: 基线三条在冻结状态通过；但 mutation 前/后源码发生外部漂移，最终 13/13 不一致。按“漂移立即 STOP”，本轮不能给出最终 13/13 认证，也不把 mutation 结果算作对 13 项冻结的有效证据。**

## 1. 冻结状态与漂移

- 指定 freeze: `consumption-20261025T100000Z-freeze-manifest.json`，13 项，sha256 `97d49d62715689b74d76f581daa8225c3755aa90ca7a8c83a5d7859179ef7d9f`
- 三条基线命令的 pre-run manifest 均 13/13 匹配；三条在冻结状态完成回归。
- **运行中外部漂移**：
  - `server/internal/governance/execution_consumption_test.go` mtime `2026-10-25 20:06:48 +0800`，实际 `93458d1f…dbd843`（6963 B）；指定 freeze 期望 `65228172…77bc5a`（5889 B）。
  - `server/migrations/644_cr_execution_consumption.up.sql` mtime `2026-10-25 20:06:37 +0800`，实际 `d07d5282…2e3b`（1675 B）；指定 freeze 期望 `58b09775…d91e9ff`（1796 B）。
- 这两个文件的新 hash 恰好匹配 `consumption-20261025T100000Z-green3-source-manifest.json`；该 green3 还期望 `execution_consumption.go` 为 `5b8df76d…bce8c1`（8789 B），但当前该文件是 `5cad80f2…a6c46e`（9171 B，指定旧 freeze 的版本）。
- 因此当前工作区是 **hybrid**：`execution_consumption.go` 为旧 freeze，测试/迁移为 green3；既不是指定 13 项 freeze，也不是完整 green3。
- **最终 13/13 = false**。本轮没有对这两个外部变更做还原/覆盖；只在 mutation 中备份并还原了 `execution_consumption.go`，其最终 hash 回到旧 freeze（`5cad80f2…a6c46e`），但这不修复测试/迁移漂移。

## 2. 基线回归计数（均在漂移前、冻结 13/13 状态下）

| 命令 | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| governance `^Test`（643+644） | `a13f67ff1a7e5662` | 0 | 910 | 909 | 0 | 1 | 822 | 1 |
| handler `^TestStartClaim`（643+644） | `f8c0456b3d2b3220` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| daemon `^Test(...)`（643+644） | `d494fc8e519e5d5b` | 0 | 153 | 151 | 0 | 2 | 138 | 2 |

- 三条 meta 均 `error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- 每条 before/after 与 `current-bindings-20261025T034807Z-preflight.json` 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog 精确不存在：
  - governance role `445264` / db `445265`
  - handler role `448643` / db `448644`
  - daemon role `451513` / db `451514`
- governance 的 `TestExecutionConsumptionReceipt` 5 子例全部实际 PASS（非 SKIP）：
  - `a_verified_proof_is_consumed_once`
  - `no_proof_means_no_receipt`
  - `a_proof_for_another_challenge_cannot_be_consumed`
  - `only_the_daemon_token_may_consume`
  - `the_receipt_table_refuses_mutation`
- 三条 `test.migrations` 均记录 643 与 644：
  - 643 `495ec3c0…cfcbbe`
  - 644 `58b09775…d91e9ff`（这是漂移前的 644；漂移后的 644 未再作为冻结证据）
- SKIP：
  - governance `TestReconcileLiveGitHub`（env 未配置）
  - daemon `TestExecutionBindingRelayHelperProcess`（helper）、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）

## 3. Mutation：删除“必须存在签发记录”检查

- 删除 `execution_consumption.go` 中 `var issued ...` / `EXECUTION_BINDING_NOT_ISSUED` 检查块。
- 重跑 governance（前缀 `...-independent-mut-no-issued-check`）：RUN 910 / PASS 906 / FAIL 3 / SKIP 1，PASS leaf 820，runner exit 1。
- 失败测试：
  - `TestExecutionConsumptionReceipt/no_proof_means_no_receipt`
  - `TestExecutionConsumptionReceipt/a_proof_for_another_challenge_cannot_be_consumed`
  - `TestExecutionConsumptionReceipt`（父）
- 但该 mutation 在漂移后的测试/迁移上运行（已非指定 13 freeze），因此**只能说明该测试会抓；不能作为 13 项冻结的正式 mutation 结论**。
- 恢复 `execution_consumption.go` 后其 hash 回到 `5cad80f2…a6c46e`；但最终 13/13 仍因测试/迁移漂移为 false。
- mutation 证据：nonce `8394892a91f84ac1`，role `454383` / db `454384`；`original_unchanged=true`、`cleaned=true`、catalog 不存在。

## 4. 处置

- 按“任何漂移立即 STOP”：不再跑后续 DB 命令，不手工覆盖外部测试/迁移，不把 hybrid 工作区认证为任一冻结。
- 需要作者/主会话确认以哪份 freeze 为准，并重新提供完整一致源码后再复跑最终证据。
- 本轮不签 final 13/13，不签 receipt 消费链完成。

## 5. 边界

- receipt ≠ 准入；T 侧仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出；消费仍关闭。
- 不签 activation、隔离域或全局 C1。
- 旧 claim 锁序 INCOMPLETE；业务 TC 0/49，5 major 未关闭。
- 未访问真实 CR、未做真实模型调用、未写原库。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
