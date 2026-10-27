# strong 复核 BLOCK 修复记录（2026-10-27）

复核结论：`BLOCK`（B1 + M1–M12 + m1）。本文件记录每条的处置与证据，全部结论只依据实跑输出。

## 处置表

| 编号 | 结论 | 处置 | 证据 |
|---|---|---|---|
| B1 | 有效 | selection/reservation 行级 `BEFORE UPDATE OR DELETE` 拒绝 + 语句级 `BEFORE TRUNCATE` 拒绝 | `store-guards/selection_row_immutable`、`reservation_row_immutable` |
| M1 | 有效 | 命令状态机（created→issued→result_ready→settled_*\|uncertain）、终态出不去、身份/签名字段恒冻结、admission 边界 issued 后冻结、verdict_id 终态、禁止 DELETE | `command_transition_rejects_skips`、`command_signed_fields_frozen` |
| M2 | 有效 | 7 张保活/演化表补语句级 TRUNCATE guard（行级触发器对 TRUNCATE 不触发） | `retained_tables_reject_truncate` |
| M3 | 有效 | deployment head `scope` 不可改、revision 单调、RETIRED 终态、禁止 DELETE | `deployment_head_scope_immutable` |
| M4 | 有效 | freeze 身份/批准字段冻结；supersede/revoke 只能 NULL→值、幂等、且须晚于 approved_at | `freeze_stamp_cannot_be_cleared` |
| M5 | 有效 | `origin-registration` 强制非空 origin（CHECK）+ `(scope,origin_id)` 部分唯一 | `origin_registration_requires_origin` |
| M6 | 有效 | legacy 裁决改用 `deployment_head.legacy_catalog_ref` 钉住的目录，删除 `created_at DESC LIMIT 1` | `legacy_catalog_must_be_pinned` |
| M7 | 有效 | 持久 legacy 行不再恒拒：仍要求目录证明，通过则返回 legacy 且保留自身身份 | `legacy_persistent_row_requires_proof` |
| M8 | 有效 | 预约在同一 Tx 回读 selection 行，校验 mode/lineage/scope；伪造结构体失效 | `reservation_selection_reverified` |
| M9 | 有效 | `ResolveSelectionTx` 先取 `pg_advisory_xact_lock(hashtextextended(...))`，关闭缺行→插目录竞态 | `unknown_selection_rejected`（同 Tx 语义）+ 代码 |
| M10 | 有效 | readiness 请求字段冻结、observation slots 只追加（`@>` 旧值）、verdict/digest 写一次、禁止 DELETE | `readiness_verdict_write_once` |
| M11 | 有效 | 清单由「名字存在」升级为「语义正确」：约束按 contype、索引按谓词、触发器按事件集合；reapply 全量复核 | `migration-up/down/reapply` |
| M12 | 有效 | 破坏性探针前置 DB 身份闸门（库名/角色 nonce 正则、非 superuser、库注释 `AIFI45_DISPOSABLE:<nonce>`）；down 前先向 648 表写入真实行 | `TestChannelMigrationProtectedData` |
| m1 | 有效 | `contractDigestOf` 解码 hex，要求 64 位小写 hex / 32 字节 | 代码 + `strict_field_deleted_binding_mismatch` |

## 实跑结果（同一批最终源码哈希）

| 套件 | 结果 |
|---|---|
| `TestChannelMigrationAfterUp` | 15/15 pass，leaf 14 |
| `TestChannelMigrationAfterDown` | 22/22 pass，leaf 21 |
| `TestChannelMigrationAfterReapply` | 15/15 pass，leaf 14 |
| `TestChannelMigrationProtectedData` | 4/4 pass，leaf 3 |
| `TestChannelStoreGuards` | 10/10 pass，leaf 9 |
| `TestChannelFoundationSelection` | 6/6 pass，leaf 5 |
| `TestChannelFoundationReservation` | 4/4 pass，leaf 3 |
| 合并回归（6 个套件一次跑） | 54/54 pass，leaf 48，skip=0，`original_unchanged=true`，`owned_resources_cleaned=true` |

变异证据（每次只改 648 up.sql 一行，跑完恢复并校验 sha）：

| 变异 | 被打红 leaf |
|---|---|
| m1 append-only 函数改为 `RETURN OLD` | `selection_row_immutable`、`reservation_row_immutable` |
| m2 状态机非法转移改 `RAISE NOTICE` | `command_transition_rejects_skips` |
| m3 readiness 写一次改 `RAISE NOTICE` | `readiness_verdict_write_once` |
| m4 head scope 冻结改 `RAISE NOTICE` | `deployment_head_scope_immutable` |

恢复后 `648_cr_execution_control.up.sql` sha256 = `89f0c3f061c73dae188f99ada0accd13ab770e72e7a96130eb70c3c8c07b5b61`（与基线一致）。

## 仍未关闭（诚实披露）

- `foundation-reservation` 声明 5 条 leaf，其中 `fixed_id_conflict_and_rollback`（SC-VC-003）、`root_adoption_terminal_race`、`root_terminal_not_adopted`（SC-VC-004）**未实现**，该 label 目前必然 unverified；`TestChannelFoundationReservation` 现有 4/4 只覆盖 SC-VC-002 与 M8 反例。
- SC-VC-003、SC-VC-010–013 的真实事务/签名/撤销实现证据仍缺（本次修的是这些表**允许**什么，不是端点**做到**什么）。
- P0 隔离证明仍 UNVERIFIED（Windows 无两个真实受限身份，方案 C 无批准 profile）。
- Windows 目录 fsync 的 EPERM/EINVAL 容忍分支仍待在 Gate 3 披露。
