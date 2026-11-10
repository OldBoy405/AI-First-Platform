# AIFI-45 RUN-003：`AppendVerdictFrameTx` 中 cursor / open_request_id / owner_fence 的关联审查（只读，Strong）

- 方式：只读静态审查。没有修改代码，没有连 DB 或容器，没有运行任何测试。
- 结论：**部分确认，其余 BLOCK**。
  - 库 API 层面确实有缺口：verdict 帧不核对 cursor 当前打开的 request，写入后无条件清掉 `open_request_id`；直接调用 `AppendVerdictFrameTx` 可以绕过 fence。
  - 这个缺口**没有接到生产路径**，也**没有实际运行复现**。
  - 修复方案里，涉及 open 契约、fence 字段和 command 行锁序的部分仍然 BLOCK。

## 0. 被审对象与版本

- multica 仓 HEAD：`81e5293adc758e392a045026cf81ec5cc1bac72d`。工作区不干净；store 文件有未提交修改，下面的行号都按**工作区文件**计。
- 平台仓 HEAD（审查开始时）：`1a409847af4f049dbbd06ed8e86e6d7267d7496a`。

文件指纹分两列。两列不是同一种东西：

- **原始 SHA-256**：对工作区文件原始字节直接计算的 SHA-256，用 `sha256sum` 得出。本会话**已独立复验**，与协调会话测得的值逐一相同。
- **Git blob SHA-1**：`git hash-object` 的输出，40 位，是对 `blob <len>\0` 前缀加内容做的 SHA-1。它**不是**原始文件哈希。上一轮报告把它误称为 “raw SHA”，在此更正。

| 文件（相对 `multica/server`） | 原始 SHA-256（已独立复验） | Git blob SHA-1 | 与 HEAD 比较 |
|---|---|---|---|
| `internal/governance/execution_control_store_state.go` | `f437aa2e2a29e26e0744d68d6da226101de6af618043e3a3d14bddafe86d684f` | `8f189502463d99fa7ff6f559e1f19b640f2426ee` | 有未提交修改 |
| `internal/daemon/execution_control_worker.go` | `23d65168cad81433af10f64f9084fab0d57745b690c82c47679e8317a53cfd3b` | `686182a5af1aea02bdb54334310c908376a2f907` | 无差异 |
| `migrations/648_cr_execution_control.up.sql` | `89f0c3f061c73dae188f99ada0accd13ab770e72e7a96130eb70c3c8c07b5b61` | `77390ad9a424464acb119bfc0bb0ee36d6c11180` | 无差异 |
| `internal/governance/execution_control_protocol.go` | `f808f2e4d2b112467707f9f2a2aa45db4adb98988ec8b330b26b1d5758ef2641` | `8db1da6e238bca5761cf083dced2e3a5a0a0ee7a` | 无差异 |

## 1. 第一轮（初步，当时结论为 BLOCK）

第一轮只看了 store 的结构和 grep 结果，发现三点：

- L449–450 只读 `last_seq` 和 `last_digest`，加了 `FOR UPDATE`。
- L495 无条件写入 `open_request_id = NULL`。
- `OpenControlRequestTx`（L504–509）唯一的条件是 `open_request_id IS NULL`，fence 可以被设成任意值，包括比原来更小的值。

当时 schema、migration 和 worker 都还没读，所以判定 BLOCK。下面几个说法当时只是**转述**已有评审，没有用源码核实：

- `REVIEW-CONTROL-CHAIN-STRONG.md` L60：`assertFenceTx` 会核 fence；
- `REVIEW-BRIEF.md` L42：这条路径没有生产调用方。

这两点在第二轮已按源码复核，见 §2.5。

## 2. 第二轮（源码核对）

### 2.1 签名覆盖了哪些字段（store L320–399，protocol L34）

- `VerdictFrameInput`（L320–338）包含这些字段：VerdictID、Scope、LineageID、RequestID、StoreID、Epoch、Seq、PrevDigest、PayloadBytes、Envelope、CommitRef、ReceiptRef、Now、Manifest、AttestationScope。**其中没有 fence 字段。**
- `verifyVerdictAttestation`（L354–371）依次检查四件事：
  1. `AttestationScope` 里的 store_id 和 lineage_id 与本帧相同；
  2. 用 `VerdictDomain = "execution-verdict/v1"`（protocol L34）验签；
  3. 入链的 payload 与被签名的字节逐字节相同；
  4. 调用 `verifyVerdictSubject`。
- `verifyVerdictSubject`（L380–399）要求签名 payload 里的 `request_id`、`epoch`、`sequence`、`previous_verdict_digest` 与入链帧一致。
- **结论**：
  - request 已经被签名绑定，帧的位置（epoch、seq、prev）也被签名绑定。
  - **`owner_fence` 和 `open_request_id` 不在签名里**；protocol.go 中没有出现 fence 字段。

### 2.2 `AppendVerdictFrameTx`（store L404–501）

- L405–413：检查必填字段，然后验签。
- L415–445：按 `request_id` 做重放查找。完全相同的帧按幂等返回；有差异的帧返回 `ErrControlStoreConflict`。这一步不看 fence，也不看 open 状态。
- L447–454：对 cursor 行加 `FOR UPDATE`，**只读取 `last_seq` 和 `last_digest`**。
- L469–474：检查 seq 连续，并检查 prev 是否等于链尾。
- L476–482：用服务器时钟重新验签。
- L483–491：INSERT verdict。
- L493–497：执行 `UPDATE cr_execution_tool_cursor SET last_seq, last_digest, open_request_id = NULL`。WHERE 只有主键，**不比较 `open_request_id`，不比较 `owner_fence`，也不检查 `RowsAffected`**。
- 整个函数**既不读也不锁 `cr_execution_control_command`**，因此不会核对以下任何一点：该 request 是否存在、是否属于本 lineage、状态是否为 issued 或 result_ready、它的 owner/effective fence 是多少。

### 2.3 `ControlWorker.ApplyTx` 与 `assertFenceTx`（worker L250–290）

- `assertFenceTx`（L250–263）在**调用方传入的同一个 tx 中**，对 `(lineage_id, store_id, epoch)` 对应的 cursor 行执行 `SELECT owner_fence … FOR UPDATE`，然后要求它等于 `w.fence.Fence`。
- `ApplyTx`（L266–290）先调 `assertFenceTx`，再用 worker 自己 fence 里的值覆盖 `in` 的 LineageID、StoreID、Epoch（L273–275），然后调用 `AppendVerdictFrameTx`。
  - Append 在 L449 会对同一行再加一次锁。这是同一事务内的重复加锁，顺序一致，不会自己死锁。
  - 字段覆盖发生在 Append 验签**之前**。epoch 已被签名绑定，所以覆盖后的值如果与签名不一致，会被拒绝。
  - `AttestationScope` 仍然由调用方传入，要求与 fence 的 store 和 lineage 一致，否则在 L355 被拒。
- `ApplyTx` **同样不核对 `open_request_id == in.RequestID`**。
- `AppendVerdictFrameTx` 是导出函数，直接调用即可完全绕过 fence 检查，没有任何机制阻止。

### 2.4 migrations/648 中的约束

- `cr_execution_control_command`（L78–106）：
  - `request_id` 是主键；
  - `owner_fence > 0` 且 `effective_fence > 0`；
  - `UNIQUE(lineage_id, seq)`。
- 部分唯一索引 `cr_execution_control_command_open_once`（L108–110）：同一 lineage 下处于 created、issued、result_ready、uncertain 状态的 command 最多一条。
- `cr_execution_tool_verdict`（L118–137）：
  - `UNIQUE(request_id)`，`UNIQUE(store_id, epoch, seq)`；
  - **`request_id` 没有外键指向 command 表**；
  - L556–561 的触发器禁止 UPDATE、DELETE、TRUNCATE。
- `cr_execution_tool_cursor`（L147–164）：
  - 主键是 `(lineage_id, store_id, epoch)`，CHECK 只有 `owner_fence > 0` 这一项和另外两项格式约束；
  - **`open_request_id` 没有外键也没有 CHECK，cursor 表上也没有触发器**；
  - 数据库层不保证 fence 单调递增。

### 2.5 生产是否接线（已用 `git grep` 核对非 test 的 Go 文件）

- `AppendVerdictFrameTx` 唯一的调用方是 `ControlWorker.ApplyTx`（worker L280）。
- `ApplyTx` 在非 test 代码里**没有调用方**。
- `OpenControlRequestTx` 只在 `execution_control_store_state_test.go` L170 和 L177 被调用。
- 结论：**没有生产调用方**。生产代码从来没有打开过 `open_request_id`，所以目前没有可以从外部利用的路径。

## 3. 攻击能否真实发生

**在库 API 层面可以静态构造，但没有运行复现。** 构造方式：

1. 调用 `OpenControlRequestTx(reqA, F)`。
2. 用 manifest 里的合法密钥签一份 reqB 的 verdict。它的 scope 是 `{store_id, lineage_id}`，`sequence = last_seq + 1`，`previous_verdict_digest` 等于链尾。
3. 直接调用 `AppendVerdictFrameTx`，或经 `ApplyTx` 并且 fence 正确。

预期结果：这一帧会被接受，reqA 的 open 状态被静默清掉。

能否达到这一步受以下条件限制：

- **需要可信签名方签出这样一帧。** 签名已经绑定了 request 和帧的位置，所以拿已有的签名帧不能改投到别的位置，也不能伪造签名。只有在签名方与 cursor 对“当前打开的是哪个 request”认识不一致时，才会出现这样的帧。这是**纵深防御缺失**，不是签名被绕过。
- **fence 只在直接调用 Append 时会被绕过。** 走 `ApplyTx` 时，旧 fence 会在 L259 被拒。
- 现有验收里有没有“open 的 request 与帧的 request 不匹配”的用例：**没有核查**。

## 4. 最小 RED/GREEN 方案（未实施）

- **RED**：写一个 DB 集成测试。governance 包的 `TestMain` 要求设置 `DATABASE_URL`，本次没有运行。
  1. Open reqA，fence 为 F；
  2. 对一份合法签名的 reqB 帧调用 `AppendVerdictFrameTx`；
  3. 期望返回 `ErrControlStoreInvalid`，且 cursor 的 `last_seq`、`last_digest` 不变，`open_request_id` 仍为 reqA，verdict 表中没有 reqB 的行。
- **GREEN（不改 API 的部分）**：
  - L449 同时读出 `open_request_id`，要求它非空并等于 `in.RequestID`；
  - L495 的 WHERE 加上 `AND open_request_id = $6::uuid`，并断言 `RowsAffected() == 1`。

## 5. BLOCK / 尚未完成的事项

1. **open 契约。** 生产代码里没有人调用 `OpenControlRequestTx`。如果强制要求 open 匹配，`ApplyTx` 和现有的 Append 测试很可能都要先 Open 一次。需要先在规范里定下谁在什么时候打开 request，才能落地上面的 GREEN。
2. **fence 由谁核对。** 要让 Append 自己核 fence，需要在 `VerdictFrameInput` 里加 fence 字段，或者把 Append 改成非导出函数。fence 不在签名里，只能在事务内做比较。这是 API 决策，本次不做猜测。
3. **command 行与锁序（尚未核完）。** 要在事务内核对 command 行（存在、属于本 lineage、状态、fence），必须先确定它与 `lockControlLineage`（store L132）和 `ApplyControlCommandTx`（store L148）之间的锁顺序。本次**没有读这两段**，所以不给方案。
4. **fence 单调性。** 是否在 `OpenControlRequestTx` 里加 `owner_fence <= $5` 来防止 fence 回退，属于设计决策，需要另外确认。
5. **没有运行任何测试，也没有连 DB。** 第 3 节的复现只是静态推论。

## 6. 前提假设

- 行号按上面列出的原始 SHA-256 对应的工作区文件计算；文件一旦改动，行号就会失效。
- “没有生产调用方”的结论只基于对非 `_test.go` 的 Go 文件做 `git grep`，不覆盖反射调用或仓库以外的调用方。
- manifest 和 AttestationScope 本身可信与否（它们来自调用参数）不在本次范围内，见 `control-channel-hardening-20261028.md` L7。
