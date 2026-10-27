# 证据索引（M003，以本文件为唯一入口）

旧前缀（`foundation-*`、`migration-*`、`*-mutations-*`）产生于 648/selection/reservation 重写之前，**不再可认证当前树**，只保留作历史。当前权威证据前缀：

```text
ac-proto-20261027T165916Z        # TestChannelProtocol（SC-VC-006/007/008，含跨语言向量）
z-combined-20261027T165412Z      # 合并跑次（6 个 Go 套件，含 SC-VC-003/004）
v-tasktx-20261027T165049Z        # TestChannelTaskTx（commit/rollback 边界）
q-down-20261027T163826Z          # migration-down（需 648 up + down，不能与 after-up 同库混跑）
```

（`p-final-*`、`n-green-*`、`y-combined-*` 为同代码演进途中的前序跑次，已被 `z-combined-*` 取代；源码摘要随每次改动重录。）

## 当前跑次

| 项 | 值 |
|---|---|
| 测试 | `^TestChannel(MigrationAfterUp|MigrationAfterReapply|MigrationProtectedData|StoreGuards|FoundationSelection|FoundationReservation)$` |
| 结果 | 65 pass / 0 fail / 0 skip，leaf_pass=58（down 另计 22/22 leaf 21；task-tx 3/3 leaf 2） |
| `original_unchanged` / `owned_resources_cleaned` | true / true |
| 源码摘要 | `*.source.json`：合并跑次 10 个文件（648 up/down、两个实现、四个测试、checker），down 跑次 5 个 |
| 迁移前置 | 643–647 up + 648 up（保留库 schema-only 克隆不含 643–647，且已含 642 列） |

## 名单校验（此前缺失的消费者）

```bash
node multica/scripts/aifi45-verify/channel-evidence.mjs verify <label> <prefix> --expectations <expectations.json>
```

结果：

| label | 结论 |
|---|---|
| migration-up / migration-reapply | OK（14 必达 leaf 全 PASS） |
| migration-protected | OK（2） |
| store-guards | OK（9） |
| foundation-selection | OK（5） |
| foundation-reservation | OK（5）：含 SC-VC-003 同 Tx/固定 ID 与 SC-VC-004 55P03 探针 |
| task-tx | OK（2）：commit 后通知一次、rollback 零持久零通知 |
| protocol | OK（3）：purpose/domain/scope 绑定、跨语言同字节同签名、exact keys |

checker 自测 9/9（`node --test scripts/aifi45-verify/channel-evidence.test.mjs`），含反例：summary 全绿但必达 leaf 缺失、改名、SKIP、仅父测试 PASS、重复 leaf、源摘要漂移、CLI 入口失效。

## 变异回滚的机器证据

mutant run（m2 状态机）exit=1；**同一时刻**用 checker 校验 green 前缀 → `FAIL source server/migrations/648_cr_execution_control.up.sql changed since the run (89f0c3f061c7 -> 43a5651c3e13)`；恢复后 sha 与基线一致 → 同一前缀校验回到 `OK`。即「已回滚」不再依赖报告里的文字声明。

## 命名注意

`migration-up-*.schema.sql` 是**原始库**的 schema 快照（不含任何 `cr_execution_*`），不是 648 应用后的目标 schema；`original-before/after.json` 才是跑次前后状态。

## 旧报告的计数口径

旧的 `selection-*`、`reservation-*`、`protocol-*`、`store-*` 报告表里的 pass/fail 与 `meta.json` 字段口径不一致（green 行含父测试、RED 行剔除父测试失败），且其「恢复后 sha 一致」无产物支撑。以 `*.meta.json` 的 `test.counts` 与本索引为准。
