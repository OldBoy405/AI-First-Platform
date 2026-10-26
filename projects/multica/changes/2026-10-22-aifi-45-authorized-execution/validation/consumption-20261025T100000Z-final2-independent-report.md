# consumption final2 独立回归报告

- at: 2026-10-25T12:13Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `consumption-20261025T100000Z-final2-independent-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 三条串行；未手工 SQL/psql
- 结论: 三条均完成且门禁通过；`TestExecutionConsumptionReceipt` 6 子例全部实际 PASS；13/13 前后一致。

## 1. 源码冻结

- 权威 freeze: `consumption-20261025T100000Z-final2-freeze-manifest.json`，13 项，sha256 `52ef4ccb076f4ffc03b69ea89993c372a7fa086e63f52682dbad034caeae728a`
- 三条 pre-run pin 均 13/13 匹配；跑后复核仍 13/13（无漂移）:
  - governance `e1734e4b18f3dbd474901738b6e343df728c86345dd72c37f7f30790d3fbed43`
  - handler `80b06a19e08086f875a37a0143cfecf8682b33eb6ecb64b00b67d3d44222e482`
  - daemon `e328c05a5d624a7653074c84921ea9c8ce61e8183434fadc3f5174c42ee54daa`
- green2/green3 清单未作为本轮依据。

## 2. 回归计数

| # | 命令 | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | governance `^Test`（643+644） | `ed2b243a91f03e64` | 0 | 911 | 910 | 0 | 1 | 823 | 1 |
| 2 | handler `^TestStartClaim` | `23713e655d9c0d27` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | daemon `^Test(...)` | `af58ab0c46e30788` | 0 | 153 | 151 | 0 | 2 | 138 | 2 |

- 三条 meta：`test.exit=0`、`error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- 每条 before/after 与 `current-bindings-20261025T034807Z-preflight.json` 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog 精确不存在：
  - governance role `463512` / db `463513`
  - handler role `466892` / db `466893`
  - daemon role `469731` / db `469732`

### SKIP 单列（不计 PASS）

- governance `TestReconcileLiveGitHub`（env 未配置）。
- daemon `TestExecutionBindingRelayHelperProcess`（helper 子进程）、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）。

## 3. 消费回执 6 子例

`TestExecutionConsumptionReceipt` 的 6 个子例全部实际 PASS（非 SKIP）：

1. `a_verified_proof_is_consumed_once`
2. `no_proof_means_no_receipt`
3. `a_proof_for_another_challenge_cannot_be_consumed`
4. `only_the_daemon_token_may_consume`
5. `a_second_challenge_for_one_generation_is_refused`
6. `the_receipt_table_refuses_mutation`

governance `test.migrations` 记录两条：

- `server/migrations/643_cr_execution_binding_issue.up.sql` — `495ec3c0ee54d1a29b3ad376a2f7d0cbd5844960c9035685a7821fb612cfcbbe`
- `server/migrations/644_cr_execution_consumption.up.sql` — `d07d528240d4c5cfa74609e4029d7117badfb70360bd436912548726acf2e3bb`

## 4. 13/13 前后

| 时点 | 13/13 raw hash 与 final2 freeze |
|---|---|
| 三条跑前 | 一致 |
| 三条跑后 | 一致 |
| 最终 | **一致** |

未修改任何源码/测试/迁移；无 mutation，无临时文件。

## 5. 边界

- receipt ≠ 准入：写入回执不写 activation，不放行消费。
- T 侧仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出；消费仍关闭。
- 不签 activation、隔离域或全局 C1；旧 claim 锁序 INCOMPLETE；业务 TC 0/49，5 major 未关闭。
- 未访问真实 CR、未做真实模型调用、未写原库。
- 请求配置 requested `Gobao/deepseek-flash/max`（configured schema1），actual unknown。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
