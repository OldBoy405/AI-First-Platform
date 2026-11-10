# 【候选方案｜未评审｜未实测｜BLOCK】verdict / cursor / command 的 fail-closed 最小生产链

**状态：BLOCK。** 本文只是候选方案，没有经过评审，也没有任何运行验证：没跑测试，没连 DB 或容器，没改源码。不能拿它当实施依据，也不能当验收证据。第 7 节列出的 8 个未闭合项，以及第 6 节的待查假设，必须先逐项解决，之后才能进入 RED。这些问题有的需要改规格，有的需要独立核查部署状态。

- 关联报告：同目录的 `REVIEW-STRONG.md`（原始 SHA-256 `2a475ca31ba5c07bc646874adaf5de032a06141b0913ec70c7afca841d343e9d`），本文不修改它。
- 依据的源码是 multica 工作区，HEAD 为 `81e5293adc758e392a045026cf81ec5cc1bac72d`，工作区不干净。行号都对应下表各文件此刻的原始字节。

| 文件（相对 `multica/server`） | 原始 SHA-256（已用 `sha256sum` 独立复验） |
|---|---|
| `internal/governance/execution_control_store_state.go` | `f437aa2e2a29e26e0744d68d6da226101de6af618043e3a3d14bddafe86d684f` |
| `internal/daemon/execution_control_worker.go` | `23d65168cad81433af10f64f9084fab0d57745b690c82c47679e8317a53cfd3b` |
| `migrations/648_cr_execution_control.up.sql` | `89f0c3f061c73dae188f99ada0accd13ab770e72e7a96130eb70c3c8c07b5b61` |

- 规格依据（没有算哈希）：
  - 平台仓 `projects/multica/archive/2026-10-27-trusted-verdict-channel/design.md` §3、§4、§5；
  - 同目录 `canonical/specs/code/verdict-channel.yaml` 中的 SC-VC-011、SC-VC-012。

---

## 1. 方案依据的源码事实

1. **command 签了哪些字段。** `verifyControlCommand`（store L74–130）要求签名里的 `request_id`、`expected_seq`、`previous_verdict_digest`、`B.lineage_id`、`B.owner_fence`（L115–118）、`B.candidate.reservation_id` 与写入列逐一相等。代码只核对了 lineage，**没有看到它核对 store_id 或 epoch**。
2. **verdict 签了哪些字段。** `verifyVerdictSubject`（store L380–399）只绑定 `request_id`、`epoch`、`sequence`、`previous_verdict_digest`。store 和 lineage 只通过 AttestationScope 绑定（L355）。**fence 没有被签名。**
3. **command 表哪些列不可改。** 触发器 `cr_execution_command_transition`（migration L414–463，挂在 L600–601）把 `owner_fence`、`seq`、`prev_digest`、`command_bytes`、`envelope` 等字段设为不可改。`effective_fence` **不在**不可改清单里，也没有单调性约束。
4. **cursor 表没有约束。** `cr_execution_tool_cursor`（migration L147–164）上没有触发器；`open_request_id` 没有外键也没有 CHECK；fence 不保证单调。
5. **各写路径当前的锁行为：**
   - `ApplyControlCommandTx`（L148–219）：验签 → advisory lineage 锁（`lockControlLineage` L132–146，要求 read committed）→ 写 command，不锁 cursor。
   - `ApplyControlPolicyEventTx`（L249–282）：只加 advisory 锁。
   - `TransitionControlCommandTx`（L285–317）：只有 UPDATE 带来的隐式行锁。
   - `BeginOwnerTx`（worker L42–94）和 `ReconcileOwnerTx`（L140 起）：只锁 cursor。
   - `ControlWorker.ApplyTx`（L266–290）：锁 cursor → Append 时再锁一次 → 写 verdict → 把 open 清成 NULL（store L493–497）。
6. **规格里的要求：**
   - SC-VC-011：要求 `EnsureRequestTx` 锁 cursor，并拒绝并行的第二条 command；fence 只能由 `BeginOwnerTx` 递增。**代码里没有 `EnsureRequestTx`。**
   - design §3：ingest ACK 不释放 slot，只有结算事务提交才释放。
   - design §3 的固定锁序：deployment head → policy activation head → CR → referenced head → 业务行 → cursor/command → dispatch root/task。
   - design §4：「journal prepared → 新 fence 下重放原 command」。

## 2. 候选锁序（与现有全局锁序是否兼容：**尚未证明**）

候选方案在 control 写路径内部使用以下顺序：

`lockControlLineage`（advisory）→ cursor `FOR UPDATE` → command 行 `FOR UPDATE` → 插入 verdict → 对 cursor 做 CAS UPDATE

**本文不声称这个顺序与 design §3 的全局锁序或现有调用方兼容。** 原因有三：

- design §3 没有给 advisory lineage 锁规定位置。它算「CR」锁还是「业务行」锁，没有定义。
- §3 里写的「cursor/command」也没有规定两者谁先谁后。
- 结算（`execution_control_settlement.go`）、准入（admission / `AdmitAndEnqueueTx`）和 dispatch root 的加锁路径**本轮都没有读**。它们可能在 advisory 锁之前就持有 cursor 或 command 行锁，也可能反过来。

所以这个锁序只是待验证的假设。要先独立梳理所有持有 advisory、cursor、command、dispatch 锁的路径，并补上死锁验证，才能定下来（见未闭合项 4、8）。

## 3. 候选生产链

### 3.1 启动

1. 事务 1：调用 `BeginOwnerTx`，fence 加 1，提交。旧 owner 被隔离。
2. 事务 2：在新 fence 下调用 `ReconcileOwnerTx`。只有返回 `ready` 才开始服务。
3. 在恢复判定里新增一项：cursor 的 `open_request_id` 必须和本 lineage 的开放 command 一致（两边都空，或都指向同一个 request）。不一致就冻结，原因记为 `open_mismatch`；不自动修复，也不清空 slot。

### 3.2 打开 request：新增 `EnsureRequestTx`，名字取自 SC-VC-011

在同一个事务内依次执行：

1. 加 advisory 锁，再锁 cursor。要求 `owner_fence` 等于本 worker 的 fence，且 `frozen_reason IS NULL`。
2. 判断是否重放：
   - command 已存在且逐字段相同，并且 `open_request_id` 就是它 → 返回已存储的记录，不做任何写入；
   - 已存在但有任何字段不同 → CONFLICT。
3. 把 command 签名和 cursor 交叉核对：签名的 `B.owner_fence` 等于 cursor 的 `owner_fence`；`expected_seq` 等于 `last_seq + 1`；`previous_verdict_digest` 等于 `last_digest`。
4. 复用 `ApplyControlCommandTx` 的插入逻辑。advisory 锁在同一 session 内可以重入。
5. 用 CAS 写入 open：`... WHERE open_request_id IS NULL AND owner_fence = $f`，并要求 `RowsAffected == 1`。

`OpenControlRequestTx` 改为**只校验 fence，不再写 fence**：去掉 `SET owner_fence`，在 WHERE 里加上 `owner_fence = $fence`。这样只有 `BeginOwnerTx` 能改 fence。

### 3.3 追加 verdict（替换现有的 `ApplyTx` 和导出的 Append）

1. 保留现有的验签和 subject 绑定（L354–399）。
2. 加 advisory 锁，再锁 cursor，读出 `last_seq`、`last_digest`、`owner_fence`、`open_request_id`、`frozen_reason`。要求：fence 一致；没有冻结；`open_request_id` 等于 `in.RequestID`。
3. 对该 command 行加 `FOR UPDATE`。要求：lineage 一致；state 为 `issued`（这个状态值待定，见未闭合项 3）；`seq` 等于 `in.Seq`；`prev_digest` 等于 `in.PrevDigest`；`effective_fence` 等于 cursor 的 `owner_fence`。
4. 插入 verdict，然后在同一个事务里推进 command 状态（推进到哪个状态待定）。
5. 对 cursor 做 CAS UPDATE：`WHERE owner_fence = $f AND open_request_id = $req AND last_seq = $seq - 1`，`RowsAffected` 必须等于 1。**这一步不清 `open_request_id`。**
6. 由结算事务提交时用 CAS 清空 open，条件是 `open_request_id = $req AND owner_fence = $f`（是否这样做，见未闭合项 2）。
7. `AppendVerdictFrameTx` 改为包内私有，或者改成必须带 fence 的入口，堵住直接调用绕过 fence 的路径。

### 3.4 重放与恢复原 bytes

- **完全相同的重放：** 在锁内返回已存储的记录，不写入。这一步不核对 fence，因为它不改变任何状态。这个取舍需要评审确认。
- **journal 恢复：** 不重新签名，也不重新算摘要，只重发**原始已签名的 bytes**。必须先经过 Reconcile。凡是无法确定的情况一律冻结，不推测“该 command 未被消费”。
- **新 fence 下重放原 command：** 签名里的 `B.owner_fence` 保持旧值（不可改）。在锁内把 `effective_fence` 用 CAS 从旧值推进到当前 fence。这样做的可信度受第 4 节约束。

### 3.5 错误处理

- 任何错误都回滚整个事务，不存在部分写入。
- 错误映射到现有的封闭错误集：
  - fence 不符 → `ErrWorkerFenceRejected` / `T_VERDICT_FENCED`；
  - open 或 command 绑定不符 → `ErrControlStoreConflict` / `BINDING_MISMATCH`；
  - seq 或 prev 不符 → `SEQUENCE_GAP`；
  - lineage 已冻结 → `RECOVERY_REQUIRED`；
  - 事务隔离级别不符 → INVALID；
  - 未知错误一律拒绝。
- CAS 的 `RowsAffected` 不等于 1 时，按 CONFLICT 回滚。

### 3.6 升级与部署兼容：独立检查之前一律冻结

- 静态 `git grep` 显示，非 test 代码里没有调用 `ApplyTx` 或 `OpenControlRequestTx` 的地方。**但这只覆盖本仓源码，不代表任何实际部署的状态。** 是否已有环境应用了 migration 648，是否已经存在 cursor、command、verdict 行，这些都**不知道**。
- 所以**不能**由“没有生产调用方”推出“不需要迁移或数据处理”。在独立检查目标部署之前，按以下方式处理：
  1. 本链首次接入时，每个已存在的 cursor 都必须先经过一次显式的独立核对：`open_request_id`、开放的 command、`effective_fence` 与 `owner_fence` 的关系、verdict 链尾。任何不一致或无法判定的，**一律冻结**，不自动补齐，不清空 slot，不推测。
  2. 核对结果和冻结记录要留证，比如写入 `frozen_reason` / `reconcile_proof`（这两列已存在于 migration L157–158，具体格式待定）。
  3. 只有拿到部署检查证据后，才能决定是否需要数据迁移，或第二个迁移。
- 现有测试需要改写：直接调用 `ApplyTx` / Append 而不先 open 的用例，以及 `cursor_single_open`（test L167–177，固定 fence=2）。

## 4. 签名绑定的条件：旧 fence 与恢复用的 `effective_fence`

| 待证明的事实 | 签名是否直接绑定 | 间接绑定的条件 | 无法由签名证明的部分 |
|---|---|---|---|
| command 在哪个 owner 下签发 | **直接绑定**：`B.owner_fence`（store L115–118） | — | 这只是签发时那一刻的 fence，不代表当前 owner |
| verdict 属于哪个 request、链上哪个位置 | **直接绑定**：`request_id`/`epoch`/`sequence`/`previous_verdict_digest` | — | — |
| verdict 是在哪个 fence 下产生的 | **不绑定** | 下面四条**同时**成立时，才能间接推出“verdict 所指的 request 是在签名的 `B.owner_fence` 下发出的，并在当前 fence 下有效”：<br>(a) verdict 的 `request_id` 在同一事务、同一把锁下查到 command 行；<br>(b) 这行 command 的 bytes 插入时已经验过签（L159、L198–202）；<br>(c) 触发器保证签名字段之后不可改（migration L414–428）；<br>(d) seq 和 prev 都与 command 一致 | 不能证明 verdict 签名方知道或认可当前 fence |
| 恢复时 `effective_fence` 推进到新 fence | **不绑定**，列本身也没有签名 | 只能二选一：<br>① **纯服务端状态绑定**：在 cursor 锁内用 CAS 把它从旧值推进到当前 `owner_fence`，并有 DB 单调约束兜底（第 5 节）。可信度完全依赖 DB 和服务端代码，不来自签名。<br>② **新签名产物绑定**：design §4 提到“worker 接受新 fence 后才返回 signed checkpoint”，protocol 里也有 checkpoint 域（CUSTOM.md #221）。**前提是** checkpoint 的 payload 同时签了 lineage、store、epoch、**新 fence**、open 的 `request_id`、原 command 的 digest，并在同一事务里核验。**checkpoint 的 payload 字段本轮没有核实。** | 如果方案 ② 的字段不满足，`effective_fence` 只能做到服务端可信 |
| 原 command 能否在新 fence 下重新签名 | — | 不能。重签会违反“恢复原 bytes”和签名字段不可改的要求，而且会产生一个新 request | — |

**结论：** 旧 fence 是直接签名绑定的；恢复用的 `effective_fence` 在现有协议下**最多只能做到服务端状态绑定**。要做到签名绑定，必须先证实或新增一个签了上述字段的 checkpoint，而这一步可能需要改协议规格。

## 5. 必须新增的 DB 约束与测试

**DB 约束。** 规格规定 648 是唯一迁移、不加新 FK；新增第二个迁移或改 648，都需要先改规格（CUSTOM.md #220 ③）。

1. cursor 触发器需要保证：
   - `owner_fence` 只增不减；
   - scope、lineage、store、epoch 不可改；
   - `last_seq` 每次只能 +0 或 +1，+1 时 digest 必须一起变；
   - `open_request_id` 只允许 NULL→X 或 X→NULL。
2. command 的 `effective_fence` 必须 ≥ `owner_fence`，且只增不减。
3. 可选：插入 verdict 时由触发器做软引用校验，要求对应 command 存在，且 lineage、seq 一致。

**不需要 DB 的对抗测试**（放在外部测试包，用假 tx 或纯函数）：

- 把“cursor 行 + command 行 + 输入”的比对抽成纯函数，逐一覆盖负例：request 不同、`effective_fence` 与 cursor fence 不同、seq 不同、prev 不同、state 不对、lineage 已冻结、open 为 NULL。
- 用一个记录 SQL 顺序的假 `pgx.Tx`，断言加锁顺序，并断言 UPDATE 的 WHERE 里带着 fence 和 open 条件。**这只能证明候选顺序被实现了，不能证明它与全局锁序兼容。**
- command 签名里的 fence 与 cursor 不一致时被拒（在验签层面）。

**只能用 DB 验收的项目：**

- `FOR UPDATE`、CAS 和 read committed 的真实语义；
- 接管与追加并发；
- 跨 settlement、admission、dispatch 路径不发生死锁；
- 触发器生效；
- `open_once` 部分唯一索引（migration L108–110）与 cursor open 的交互；
- 提交后重放；
- 恢复时推进 `effective_fence`；
- 第 3.6 节的部署核对与冻结。

## 6. 待查假设（尚未核实）

- **DB schema：** 本文假设实际部署的 schema 就是工作区 migration 648 的原始字节（SHA-256 `89f0c3f0…5b61`）。各部署是否真的应用了 648、有没有手工变更，不知道。
- **开放的 command：** 本文假设一个 lineage 只对应一个 store 和 epoch 的 cursor，并假设 `open_once` 的“开放状态”集合（created、issued、result_ready、uncertain）就等同于 cursor 上的 open。这两点都**没有经过规格确认**。
- **调用方：** “无生产调用方”只基于对非 test Go 文件的 `git grep`，不覆盖反射调用、其他仓库或已部署的二进制。`BeginOwnerTx` 的调用方没有 grep。

## 7. 未闭合项（全部解决之前保持 BLOCK）

1. **command 没有签 store_id 和 epoch。** 只核对了 lineage，`B` 里有没有 store 字段没核实。如果一个 lineage 下有多个 store 或 epoch，command 对应哪一行 cursor 就有歧义。
2. **slot 什么时候释放。** 规格写的是“ACK 不释放，结算事务提交时释放”，而代码在追加 verdict 时就清空了 open。本文按 fail-closed 改为在结算时释放，但 cursor 的 open 是否就等于规格说的 slot，需要规范确认。
3. **verdict 到达时 command 的状态。** 应该是 `issued` 还是 `result_ready`？状态推进是否应该和追加 verdict 放在同一个事务里？都没有定义。
4. **settlement、admission、dispatch 的锁序没读过。** 候选锁序可能与它们冲突，**不能宣称兼容**。
5. **DB 约束需要先改规格**（新增第二个迁移，或改 648）。
6. **`BeginOwnerTx` 的生产调用方没查。** Reconcile 里“新 fence 下重放、推进 `effective_fence`”的逻辑目前没有实现；第 4 节方案 ② 依赖的 checkpoint 字段也没核实。
7. **Manifest / AttestationScope 的可信来源**目前仍由调用方传入，见 `control-channel-hardening-20261028.md` L7。
8. **design §3 的“cursor/command”没有规定先后。** “cursor 先、command 后”以及 advisory 锁放在最前，都是本文自己的设计选择，规格里没有依据。
