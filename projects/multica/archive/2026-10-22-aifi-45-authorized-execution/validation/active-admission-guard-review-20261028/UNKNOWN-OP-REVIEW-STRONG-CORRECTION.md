# 更正：UNKNOWN-OP-REVIEW-STRONG.md 中关于"未知 mode"的表述

- 被更正的报告：同目录 `UNKNOWN-OP-REVIEW-STRONG.md`，原始 SHA-256 `27a9f963f1170d5ddaa3f06d59d017713e9410c560593b0d93715bbb6cd7962f`。原文**不修改、不覆盖**，本文只做补充更正。
- 方式：只读静态复核。没有改代码，没有跑测试，没有连 DB 或容器，没有操作 CR。
- 依据的源码：multica `server/internal/governance/execution_deployment.go`，本次复验 SHA-256 为 `dc6407f98b07fbd63d7c039a5db497a9540b3dd674206b320b3e31cd92a18e7b`，与原报告相同。另读了 `server/migrations/648_cr_execution_control.up.sql` L335–349，SHA-256 为 `89f0c3f061c73dae188f99ada0accd13ab770e72e7a96130eb70c3c8c07b5b61`。

## 1. 原文的具体错误

- **报告 §3 第 3 项最后一句：** "mode 不是 `ACTIVE`/`STOP_NEW` 的未知值（L30–31 只定义了这两个）会走非 ACTIVE 分支，未知 op 同样被拒。这一点没有测试覆盖。"
  - 这句话只对"未知 op"成立，但写在"其他状态是否保持"一项下，**读起来像是未知 mode 整体被安全拒绝。这不对。** 它漏掉了一个实质事实：在未知 mode 下，已知的恢复 op 可以拿到 `ExactRecovery`，审计 op 拿到 `AuditOnly`。
- **我回传给协调方的结论：** "不认识的 mode 值会走非 ACTIVE 分支、结果也是拒绝"。这句话**直接错了**，它把"未知 op 被拒"泛化成了"未知 mode 被拒"。

## 2. 按代码独立复核（L466–544）

- `mode` 来自 activation event 行（L493–495），代码**不校验它是否属于 `ACTIVE`/`STOP_NEW`**。
- 只要 `mode != ActivationModeActive`，不管过没过期，都会越过 L508 进入 STOP/过期共用的恢复分支。这时：
  1. L517：op 在 denyOps 里 → `Denied`。
  2. L521：op 在 auditOps 里 → `AuditOnly`。
  3. L525：`AdmissionSeq <= 0` 或 `> cutoff` → `Denied`。`cutoff` 取自 head 的 `last_issued_admission_seq`（L474）。
  4. L528：`IssuedAt`、`expiresAt` 都非零且 IssuedAt 晚于 expiresAt → `Denied`。
     - 两者任一为零，这一项就被跳过。
     - 当 `verdict_ref` 为 NULL 时（L503–505），`expiresAt` 保持零值，这一项必然跳过。
  5. L532：op 是 `complete_unsettled_request` 或 `bind_existing_mapping` 时：
     - `PersistedOriginRef == OriginRef` 且 `PersistedDigest == Digest`；
     - Generation 两边都非零且不相等时才拒；任一为 0 都放行；
     - 两条都满足 → **`AccessExactRecovery`**。
  6. 其他 op → `Denied`。
- **结论：** 未知 mode 在代码层面被**当作 STOP_NEW 处理**。只要满足 1–5 的条件，两个恢复 op 就会返回 `ExactRecovery`，而不是拒绝。你指出的问题成立。

## 3. 假设与可达性

- 本地 migration 648 L347 有 `CHECK (mode IN ('ACTIVE', 'STOP_NEW'))`。在 schema 与这份文件字节一致的数据库里，正常写入走不到未知 mode。
- 但下面三点**没有核实**：
  1. 实际部署是否应用了 648，有没有手工改过约束；
  2. 有没有绕过约束的写入；
  3. 是否存在会伪造 mode 的假事务或其他 `pgx.Tx` 实现。
- 所以准确的说法是：**函数本身对未知 mode 不 fail-closed，只是靠 DB 的 CHECK 兜底。**
- 函数目前没有生产调用方（见原报告 §3 第 4 项），现在不存在从外部可利用的路径。
- 恢复字段（AdmissionSeq、IssuedAt、Persisted*、Generation）仍由调用方传入，零值放行这条与原报告 §3 第 5 项一致。

## 4. 影响

- 未知 mode 下会返回 `ExactRecovery`，这是一个**改前就有的行为**。本次 unknown-op 改动只碰了 L512–515 的 ACTIVE 分支，没有引入它，也没有修复它。
- 在 DB CHECK 失效或被绕过、并且以后接上生产调用方的前提下，它会让"不明状态"的 activation 允许精确恢复，而不是冻结。是否应当在函数内显式拒绝未知 mode，属于设计决策，**本文不给定论**，列为剩余 BLOCK 项。
- 原报告 §3 第 3 项"其他状态是否保持不变：通过"中，"STOP_NEW、过期、缺 head 三条路径没有改动"这部分仍然成立。只有关于未知 mode 的那句需要按本文更正。

## 5. 现状未测

- 现有 fake 测试只构造了 `ACTIVE`、`STOP_NEW` 和缺 head 三种情况，**没有任何未知 mode 用例**，正例反例都没有。本次也没有运行测试。
- 如果要补，建议用例如下（只是提议，未实施）：
  - mode 为 `PAUSED`、`verdict_ref` 为 NULL、op 为 `complete_unsettled_request`、字段全部相等。
    - 记录当前实际返回 `ExactRecovery`，作为现状固定。
    - 如果决定改为 fail-closed，这个用例就是 RED，期望 `Denied`。
  - 同样的设置，换成 `future_operation`，期望 `Denied`。
  - 同样的设置，换成 `new_admission`，期望 `Denied`。

## 6. 局部 unknown-op 结论是否受影响

**不受影响。** 原报告对本切片的"限定 PASS"仍然成立，理由如下：

- 改动只在 ACTIVE 且未过期的分支里，把未知 op 从 `NewAdmission` 改成 `Denied`。
- 在任何 mode 下，**未知 op** 都会落到 L541–542 的 `default: Denied`，或者在缺 head 时落到 L485。
- 本次更正涉及的是**已知恢复 op 在未知 mode 下**的行为。这个行为改前就存在，不在本切片范围内。

RUN-006 仍为 MISSING，Gate3 不受影响。剩余 BLOCK 新增一项："函数内未知 mode 未显式拒绝，只依赖 DB CHECK；没有测试覆盖"。
