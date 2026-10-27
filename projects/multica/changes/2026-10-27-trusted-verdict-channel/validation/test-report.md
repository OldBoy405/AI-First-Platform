# BUILD 测试报告（M003，截至 2026-10-27）

> 唯一证据入口是 `evidence-index.md`；本报告汇总「已验证 / 未验证」，不重复贴跑次。
> 规则：label 只有在**全部冻结必达 leaf** 都是真实非 skip PASS 时才算验证；summary 全绿不算。

## 1. 已验证（checker `verify` 判 OK）

| label | 必达 leaf | 结论 |
|---|---|---|
| `migration-up` | 14 | OK |
| `migration-reapply` | 14 | OK |
| `migration-down` | 14 | OK（另出 7 个 `fn_*` 额外 PASS，不计入必达） |
| `migration-protected` | 2 | OK |
| `store-guards` | 9 | OK（`audit` 已确认 37 个冻结 label 全部有 CP 引用） |
| `foundation-selection` | 5 | OK |

合并跑次：62 pass / 0 fail / 0 skip，leaf_pass=55，`original_unchanged=true`、`owned_resources_cleaned=true`；`migration-down` 单独 22/22（leaf 21）。两个跑次前缀见 `evidence-index.md`。

Node 侧（tools `test/execution-control-{protocol,store}.test.mjs`）：各 2/2 PASS，共 4 个必达 leaf；mutation m1/m2 各自只打红自己的 leaf。**注意**：TAP 产物共用时间戳前缀，跑次顺序不可从产物判定；结论仅依据「文件 sha256 与 green 跑次一致」这一条（由 checker 判，不靠报告文字）。

## 2. 未验证（不得计入 Gate 3 通过项）

| 项 | 状态 |
|---|---|
| `foundation-reservation` | **FAIL**：缺 `fixed_id_conflict_and_rollback`（SC-VC-003）、`root_adoption_terminal_race`、`root_terminal_not_adopted`（SC-VC-004） |
| `foundation-fresh-work` | 未实现（SC-VC-005 主体） |
| `task-tx`（commit 后通知 / rollback 零通知） | 未实现 |
| `protocol` / `store-state` / `policy-*` / `settlement` / `binding` / `reader` / `worker` / `client` / `composition` / `d8-recovery` / `revoked-permit` / `readiness-*` / `merge-*` / `isolation` | 未实现 |
| tools SC-TR-003 并发三请求、rename 前后 kill | 未测（报告未声称） |
| tools SC-TR-001 Go 侧 `cross_language_vectors` | 不存在 |
| P0 隔离证明（两真实受限身份 + 批准 profile） | UNVERIFIED（Windows 无第二受限身份；WSL podman 无批准 profile） |
| `strict-production` profile | UNVERIFIED（待部署授权） |
| Windows 目录 fsync（EPERM/EINVAL 容忍分支） | 待在 Gate 3 披露 |

## 3. mutation 证据（可复现条件）

四个变异都只改 `648_cr_execution_control.up.sql` 的一行，跑 `^TestChannelStoreGuards$`，恢复后校验 sha 与基线 `89f0c3f0…` 一致。

| 变异 | 目标文件 | 替换（原文 → 变异） | 失败 leaf | patch sha256（unified diff，去缩进行） |
|---|---|---|---|---|
| m1 | 648 up | `RAISE EXCEPTION '% is append-only', TG_TABLE_NAME;` → `RETURN OLD;` | `selection_row_immutable`、`reservation_row_immutable` | `96707b44a0daf66f…` |
| m2 | 648 up | `RAISE EXCEPTION 'illegal control command transition …'` → `RAISE NOTICE …` | `command_transition_rejects_skips` | `dd410bdf75bb0842…` |
| m3 | 648 up | `RAISE EXCEPTION 'readiness verdict is write-once';` → `RAISE NOTICE …` | `readiness_verdict_write_once` | `8a7af21b085d289c…` |
| m4 | 648 up | `RAISE EXCEPTION 'deployment head scope is immutable';` → `RAISE NOTICE …` | `deployment_head_scope_immutable` | `5286b3f675d4d181…` |

**缺口**：patch sha256 是按「去掉缩进的行替换 + 手写 unified diff」重建的，不是当时落盘的原始 patch；原始落盘只有失败 leaf、argv、跑次前后源文件 sha256。要彻底满足 long-range-auth §C1，需在下一次变异时由脚本 `diff -u` 落盘。

## 4. 回滚证明（机器判据，不靠文字）

green 跑次写入 `<prefix>.source.json`（10 个源文件 sha256）。一次真实变异后同一前缀判定：

```text
FAIL source server/migrations/648_cr_execution_control.up.sql changed since the run (89f0c3f061c7 -> 43a5651c3e13)
```

恢复后同一前缀回到 `OK store-guards: 9 required leaves passed`，且 up.sql sha 与基线一致。

## 5. 对 AIFI-45 六条 RUN TC 的可重跑性

本报告**不构成回填**。`TC-RUN-001/002/003/006/007/010` 可据此重跑，前置为：

1. 两个源码仓处于本 change 的分支（源码改动**未提交**，重跑前先确认工作树内容与 `<prefix>.source.json` 一致）；
2. 每轮独占 nonce 库（`scripts/aifi45-db/run.mjs`），带 `-migration=` 643–647 up + 648 up（保留库 schema-only 克隆不含 643–647，且已含 642 的列）；
3. 四条 648 专例各自的迁移前置不同：down 需 648 up + down；protected 自身做 down/up，不能与 after-up 同库混跑；
4. `foundation-reservation` 在 SC-VC-003/004 落地前必然 FAIL，重跑时按「未验证」记录，不得按 label 全绿上报。
