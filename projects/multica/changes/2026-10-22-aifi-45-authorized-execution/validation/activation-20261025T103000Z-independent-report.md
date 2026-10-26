# 不可删 activation 独立回归报告

- at: 2026-10-25T12:28Z
- 角色: 本轮唯一 DB 执行者（非作者）
- 代码仓/cwd: `C:/Users/GOBAO/Downloads/AI/multica`
- 证据仓: `.../validation/`
- 前缀: `activation-20261025T103000Z-independent-`
- DB 访问: 仅版本化 `scripts/aifi45-db/run.mjs` 三条串行
- 结论: 三条均完成且门禁通过；5 个 activation 用例与 6 个 consumption 用例全部实际 PASS；18/18 前后一致。

## 1. 源码冻结

- 权威 freeze: `activation-20261025T103000Z-freeze-manifest.json`，18 项，sha256 `253e8803ea6da4e73cbabd2fc60ec1162e00c422a7660e42024631674187458a`
- 三条 pre-run pin 均 18/18 匹配；跑后复核仍 18/18（无漂移）:
  - governance `a48a94dc9b66f6725143c066cd02da45014e922a0e5f9ca776f0c1160c3c83b8`
  - handler `3a5409bf40e87cf178347603223db4acdce8b2abd2eef7dd51cb7f009ddc4c0c`
  - daemon `667108c7287619ac097142ea2e3959e23b1b28be2607c2ac0c99b41ccd0344b6`

## 2. 回归计数

| # | 命令 | nonce | exit | RUN | PASS | FAIL | SKIP | PASS leaf | SKIP leaf |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | governance `^TestExecution(Activation\|Consumption)`（643+644+645） | `e4091a8304bd980f` | 0 | 17 | 17 | 0 | 0 | 15 | 0 |
| 2 | handler `^TestStartClaim` | `8d0468b764e50e70` | 0 | 13 | 13 | 0 | 0 | 10 | 0 |
| 3 | daemon `^Test(...)` | `5566f4dc192c343b` | 0 | 153 | 151 | 0 | 2 | 138 | 2 |

- 三条 meta：`test.exit=0`、`error=null`、`original_unchanged=true`、`owned_resources_cleaned=true`、`sessions=0`、`locks=0`。
- 每条 before/after 与 `current-bindings-20261025T034807Z-preflight.json` 完全一致：**137 表 / 6228 行 / 82 审批**。
- catalog 精确不存在：
  - governance role `504234` / db `504235`
  - handler role `507137` / db `507138`
  - daemon role `509976` / db `509977`
- SKIP 单列（不计 PASS）：daemon `TestExecutionBindingRelayHelperProcess`、`TestExecutionTrustRefusesLinkedRootInsideWorkspace`（Windows symlink）；governance 无 SKIP。

## 3. 激活/消费用例

5 个 activation 用例全部实际 PASS（非 SKIP）：

- `TestExecutionActivationRequiresReceipt`
- `TestExecutionActivationAfterConsumption`
- `TestExecutionActivationRefusesAnotherProof`
- `TestExecutionActivationRefusesRevokedHead`
- `TestExecutionActivationIsImmutable`

6 个 `TestExecutionConsumptionReceipt/*` 子例全部 PASS（含 `a_second_challenge_for_one_generation_is_refused`）。

governance `test.migrations` 记录三条：

- 643 `495ec3c0…cfcbbe`
- 644 `d07d5282…2e3b`
- 645 `62e836e9f6822e32518e7e96defe1a622edb435da705ad001f09b263e96ad344`

## 4. 只读判定

### (a) head 校验先于 receipt/幂等分支

**是。** `execution_activation.go`：

- 先 `GetExecutionAuthorizationHead`（`:86`），再 `validateExecutionAuthorizationHead`（`:97-99`）；
- 之后才 `decodeExecutionBindingHeadPayload`（`:104`）与 challenge/scope 校验（`:123`）；
- receipt 检查在 `:133-152`；
- `ON CONFLICT ... DO NOTHING` 的幂等/重放分支在 `:167` 之后。

因此 revoked/re-scoped head 会在 receipt 与已存在 activation 的幂等返回之前拒绝；这与注释 `:97-98` 一致。

### (b) TRUNCATE 触发器是否会在 DROP TABLE 时误伤 / down 是否可行

**不会误伤；down 可行。** `645_cr_execution_activation.up.sql` 的 TRUNCATE 触发器是 `BEFORE TRUNCATE ... FOR EACH STATEMENT`（`:42-44`）；`DROP TABLE` 不是 TRUNCATE，不会触发表触发器。
`645_cr_execution_activation.down.sql` 先 `DROP TRIGGER`（no_truncate、no_mutation，`:2-3`），再 `DROP FUNCTION`（`:4`）、`DROP INDEX`（`:5`），最后 `DROP TABLE`（`:6`）。触发器已在表删除前移除，down 顺序自洽且可行。

## 5. 边界

activation 记录 ≠ 准入；T 仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出；语义为文档推导、待 Gate 确认；不签隔离域或全局 C1。消费仍关闭；旧 claim 锁序 INCOMPLETE；业务 TC 0/49，5 major 未关闭。

## DB 权

**DB 单执行权已释放，无运行中测试；无遗留 owned 临时数据库/role。**
