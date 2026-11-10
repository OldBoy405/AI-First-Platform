# consumption-call 单开关 独立回归报告

- at: 2026-10-25T13:03Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `consumption-call-20261025T110000Z-independent-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 三条串行
- 结论: 三条均通过；20/20 前后一致；消费调用开关默认关，无生产代码设为 true；tools 旧账单文件 299/299，AC-15 PASS。

## 1. 源码冻结

- 权威 freeze: `consumption-call-20261025T110000Z-freeze-manifest.json`，20 项，sha256 `be319f10fb87eb3902520c3a14453338f5a4a1022b632fc7372ee73dd6ea3d85`
- 三条 pre-run pin 均 20/20 匹配；跑后复核仍 20/20（无漂移）:
  - governance `67a336a95f271931e94bd679971e4f59f3eacdce529dbc7bc39b6f6ad06f9901`
  - handler `9c43c2f35c4f2c5b89385d128be34fb02a9d5a9084e6bfd2687736c40f9e8fe4`
  - daemon `c018ac9b8e221c1aaebc4421aa306c93be9130697fcef411bae683b42d59a560`

## 2. 回归计数

| # | 命令 | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | governance `^TestExecution(Activation\|Consumption)`（643+644+645） | `938426310aea432e` | 0 | 17 | 17 | 0 | 0 | 15 | 0 |
| 2 | handler `^TestStartClaim` | `304b9c4eb3544cfb` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | daemon `^Test(...RequestExecution\|RecordDelivered...)` | `cd26263e192773f6` | 0 | 160 | 158 | 0 | 2 | 144 | 2 |

- 三条 meta：`test.exit=0`、`error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- 每条 before/after 与 `current-bindings-20261025T034807Z-preflight.json` 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog 精确不存在：
  - governance role `521335` / db `521336`
  - handler role `524238` / db `524239`
  - daemon role `527080` / db `527081`
- governance migrations 三条均记录：643 `495ec3c0…cfcbbe`、644 `d07d5282…2e3b`、645 `62e836e9…ad344`。
- SKIP 单列（不计 PASS）：daemon `TestExecutionBindingRelayHelperProcess`、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）。

### 新增消费调用测试

daemon 实际 PASS（非 SKIP）：

- `TestRequestExecutionConsumptionClient`
- `TestRequestExecutionConsumptionClientRefusals/no_receipt_for_this_generation`
- `.../already_consumed_by_another_proof`
- `.../200_without_a_receipt`
- `.../empty_cr_id_never_reaches_the_network`
- `TestRecordDeliveredConsumptionSwitchIsOffByDefault`

## 3. 20/20 前后

| 时点 | 20/20 raw hash 与 freeze |
|---|---|
| 三条跑前 | 一致 |
| 三条跑后 | 一致 |
| 最终 | **一致** |

未修改任何源码/测试/迁移。

## 4. 开关只读核

- `recordConsumptionAfterDelivery` 只在测试中设为 true：
  - `server/internal/daemon/execution_consumption_client_test.go:141` `&Daemon{client: client, recordConsumptionAfterDelivery: true}`
- 生产代码只有字段声明与读取/早退，没有赋值为 true：
  - 字段与注释 `daemon.go:765-768`
  - 早退判断 `execution_consumption_client.go:59`
- 因此默认关 ⇒ `recordDeliveredConsumption` 完全不动，不会发消费请求。

### DeliveredChallenge 记录点

- `execution_binding_endpoint.go:155` 先 `w.Write(...)`；若写失败直接 return（不给 delivered 赋值）。
- 写成功后 `:161` 才 `e.delivered = append(...)`。
- `DeliveredChallenge` 在 `:167-175` 返回拷贝。
- 结论：只在写响应成功后记录，符合“投递后”语义。

## 5. tools 旧账复跑（独立，未改代码）

命令：`cd C:/Users/GOBAO/Downloads/AI/tools && node --test --test-reporter=spec skills/shared/crctl/scripts/test/crctl.test.mjs`

| 指标 | 实际 |
|---|---:|
| tests | 299 |
| pass | 299 |
| fail | 0 |
| skipped | 0 |
| duration | 325.6s |

- `CR-2026-030 TASK-01：owner-set 恢复失败 → OWNER_COMMIT_ROLLBACK_FAILED 并列出受影响文件（AC-15）` **PASS**（790ms）。
- 说明：这是该单文件 299 项的结果，不是 tools 全仓 1058 项的复跑。

## 6. 边界

- 开关关 ⇒ 仍无消费调用；当前默认关。
- T 仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出；消费仍关闭。
- 不签 activation 语义（推导待 Gate 确认）、隔离域或全局 C1。
- 旧 claim 锁序 INCOMPLETE；业务 TC 0/49，5 major 未关闭。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
