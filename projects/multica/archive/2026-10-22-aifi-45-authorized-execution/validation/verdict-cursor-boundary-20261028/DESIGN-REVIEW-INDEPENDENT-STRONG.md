# AIFI-45：对 DESIGN-CANDIDATE-STRONG.md 的独立只读复核（Strong）

**总判定：BLOCK。** 下面 8 项里，7 项判为 BLOCK，1 项有条件 PASS（fail-closed）。

## 0. 范围、方式与限制

- 方式：只读静态复核。没有改动任何文件（候选原文和之前的报告都没动），没有连接 DB 或容器，没有跑测试，也没有发起真实 CR。下面所有反例都是**静态推导**，没有实际运行复现过。
- 被审对象：同目录 `DESIGN-CANDIDATE-STRONG.md`。原始 SHA-256 已用 `sha256sum` 复验：
  `ab6ca227859194d06bafd7bb313a417cb5fddffbd6c317aa832be31ca6ad8718`，与委托要求一致。
- 同目录 `REVIEW-STRONG.md` 复核时测得原始 SHA-256 为 `2a475ca31ba5c07bc646874adaf5de032a06141b0913ec70c7afca841d343e9d`，与候选文中引用的值一致。本文没有修改它。
- multica 仓 HEAD：`81e5293adc758e392a045026cf81ec5cc1bac72d`，工作区不干净。下表行号都按工作区文件的原始字节计算：

| 文件（相对 `multica/server`） | 原始 SHA-256（本次 `sha256sum` 复验） | 本次是否通读 |
|---|---|---|
| `internal/governance/execution_control_store_state.go`（下称 store） | `f437aa2e2a29e26e0744d68d6da226101de6af618043e3a3d14bddafe86d684f` | 全文通读 |
| `internal/daemon/execution_control_worker.go`（下称 worker） | `23d65168cad81433af10f64f9084fab0d57745b690c82c47679e8317a53cfd3b` | 全文通读 |
| `migrations/648_cr_execution_control.up.sql` | `89f0c3f061c73dae188f99ada0accd13ab770e72e7a96130eb70c3c8c07b5b61` | **只核了哈希，没读正文** |

### 0.1 本次没读的材料，以及由此带来的条件

由于轮次限制，下面这些材料**都没有读**。凡是结论依赖它们的地方，都标成「待核」，不能算已经核实：

1. **migration 648 正文**。cursor 表的列，比如 `frozen_reason`、`reconcile_proof` 是否存在；command 触发器是否允许改 `effective_fence`；`open_once` 索引的定义。这些都只来自候选和 `REVIEW-STRONG.md` 的转述。
2. **`execution_control_settlement.go`**。结算路径实际锁哪些行、按什么顺序锁，都不知道。
3. **admission / `AdmitAndEnqueueTx` / dispatch root 路径**。它们的锁序不知道。
4. **规格和计划文档**。包括 `archive/2026-10-27-trusted-verdict-channel/design.md` §3–§5、`canonical/specs/code/verdict-channel.yaml`（SC-VC-011/012）、`design.md`、`tasks.md`、`test-plan.md`。其中规格条文只来自候选的转述。
5. **全仓 grep 没做**。调用方相关结论，要么来自已读的两个文件，要么引用 `REVIEW-STRONG.md` §2.5（那是非 test Go 文件的 `git grep`），本次没有重跑。`BeginOwnerTx` 的生产调用方没有查。

### 0.2 「当前代码已存在的缺陷」与「候选方案引入的假设风险」要分开看

下面每条反例都标了属于哪一类：

- **【当前】**：在已读的两份源码里，现在就成立。
- **【候选】**：只有按候选方案实现以后才会出现。比如第 1 项的死锁，在当前已接线的代码里**不存在**：现在的 Append 不锁 command 行，`TransitionControlCommandTx` 也不碰 cursor。它是候选锁序和候选结算步骤组合起来才会出现的**假设风险**。

---

## 1. 汇总

| # | 项 | 判定 | 性质 |
|---|---|---|---|
| 1 | 锁序死锁 | **BLOCK** | 【候选】假设风险；settlement/admission 的锁序待核 |
| 2 | request/seq/fence 是否由原始签名字节绑定 | **BLOCK** | 【当前】`EffectiveFence` 无校验 +【候选】校验条件可以被绕过 |
| 3 | 恢复时的新 fence 与旧命令 | **BLOCK** | 【当前】Reconcile 没有恢复入口 +【候选】只靠服务端状态授权 |
| 4 | 事务内 command/cursor 的状态 | **BLOCK** | 【候选】状态机断链 |
| 5 | 签名前后的有效期与锁竞争 | **BLOCK** | 【候选】复验点不在最后一把锁之后 |
| 6 | exact replay | **BLOCK** | 【候选】结算后重放不再幂等；另有一处【当前】的次要问题 |
| 7 | 上线时已有的状态 | **有条件 PASS（fail-closed）** | 可用性风险；列是否存在待核 |
| 8 | 生产入口缺失 | **BLOCK** | 【当前】没有接线 |

---

## 2. 逐项复核

### 2.1 锁序死锁：BLOCK【候选假设风险，不是当前已接线的死锁】

已读代码里的事实：

- `ApplyControlCommandTx`（store L148 起）：验签（L158），然后拿 advisory 锁（`lockControlLineage`，L132），然后写 command。**不锁 cursor。**
- `TransitionControlCommandTx`（store L285 起）：只有 UPDATE command 时带来的行锁。**不碰 cursor。**
- `BeginOwnerTx`（worker L42，L54）和 `ReconcileOwnerTx`（worker L140，L152）：只做 cursor `FOR UPDATE`，**不拿 advisory 锁**。
- `ApplyTx`（worker L266）：先 `assertFenceTx` 锁 cursor（L250–255、L267），再调 `AppendVerdictFrameTx`（L280）；后者在 store L450 对同一行再锁一次。**不锁 command，也不拿 advisory 锁。**

所以在已读范围内，当前没有交叉锁序。候选方案会引入下面两种组合：

**反例 1-A：command→cursor 与 cursor→command 交叉【候选】**
- 事务 S 是候选 §3.3 第 6 步的结算：先用 `TransitionControlCommandTx` 去 UPDATE 请求 R 的 command 行，拿到 R 的行锁；然后 CAS UPDATE cursor 清 open，等待 cursor 行锁。
- 事务 A 是候选 §3.3 第 2–3 步的 Append：先 advisory 锁，再 cursor `FOR UPDATE` 并拿到 cursor 锁；然后对 R 的 command 行 `FOR UPDATE`，等待 S。
- 结果：S 等 A，A 等 S，PostgreSQL 报 deadlock，并回滚其中一方。如果 S 改为先拿 advisory 锁，那 A 和 S 在 advisory 锁上就串行了，这个反例不再成立。可是候选没有规定结算路径要拿 advisory 锁，而 settlement 的实际加锁代码**没读（待核）**。

**反例 1-B：cursor→advisory 与 advisory→cursor 交叉【候选】**
- 如果候选的 Append 继续沿用 `ApplyTx` 前置的 `assertFenceTx`（先锁 cursor，worker L267），再在 Append 里调 `lockControlLineage`，锁序就是 cursor→advisory。
- 同一 lineage 上的 `EnsureRequestTx`（候选 §3.2 第 1 步）是 advisory→cursor。
- 两者并发，就构成交叉等待。候选 §3.3 写的是「替换现有 ApplyTx」，但没有明确要去掉前置的 cursor 锁。

**1-C：** `BeginOwnerTx` 和 `ReconcileOwnerTx` 不拿 advisory 锁，只锁 cursor。它们单独存在不会和 advisory→cursor 路径交叉，但只要在同一事务里再去拿 advisory 锁或 command 锁，就有风险。候选没有分析这一点。

候选在 §2 和 §7 第 4、8 项里也自认没有证明。在 settlement/admission/dispatch 的锁序核清之前，**不能定锁序**。

### 2.2 request/seq/fence 是否由原始签名字节绑定：BLOCK

已读代码里的事实：

- command 签名的绑定在 `verifyControlCommand`（store L74 起）：`request_id`、`expected_seq`、`previous_verdict_digest`、`B.lineage_id`、`B.owner_fence`（L115）、`B.candidate.reservation_id`。**不绑定 store_id 和 epoch。** AttestationScope 只检查 lineage（L75）。
- verdict 签名的绑定在 `verifyVerdictSubject`（store L380 起）：`request_id`、`epoch`、`sequence`、`previous_verdict_digest`。**不含 fence。** store/lineage 只靠调用方传入的 AttestationScope 约束（L355）。
- verdict 和 command 之间唯一的关联是 `request_id`。

**反例 2-A（主反例）：插入时 `effective_fence` 可以被任意指定【当前缺陷 + 候选校验被绕过】**
- 当前代码：`ApplyControlCommandTx` 对 `EffectiveFence` 只检查 `> 0`（L152），然后原样插入（L205–210）。它不和签名的 `B.owner_fence` 比，也不和 cursor 比。重放比对的字段（L166–172）里也**没有** `effective_fence`。
- 候选在 §3.2 第 3 步只要求签名的 `B.owner_fence == cursor.owner_fence`，**没有**要求插入时 `effective_fence == owner_fence`。
- 构造步骤：
  1. cursor 的 fence 为 1。调用方提交一条签名 `B.owner_fence=1` 的合法 command，同时传 `EffectiveFence=2`。签名校验通过，插入成功。
  2. 调用 `BeginOwnerTx` 接管：fence 加 1，变成 2（worker L42 起）。
  3. 新 owner 追加 verdict。候选 §3.3 第 3 步检查 `effective_fence(=2) == cursor.owner_fence(=2)`，**通过**。
- 结果：旧 owner 签发的命令不经过 Reconcile，也不经过 CAS 推进，直接在新 fence 下被认可。fence 隔离对这条命令失效。
- 修复条件：插入时强制 `effective_fence = owner_fence = cursor.owner_fence`；把 `effective_fence` 纳入重放比对；DB 层的单调约束要等 648 正文核清（待核）。

**2-B：多 epoch 下 command 绑到哪一行 cursor 有歧义【当前】**
- `BeginOwnerTx` 用 `ORDER BY epoch DESC LIMIT 1`（worker L42–54），说明同一 lineage/store 可以有多个 epoch。
- command 不签 store/epoch，所以它绑定到哪一行 cursor，只能由服务端决定。
- seq/prev 的 CAS 会限制可落的位置，但仍然是服务端状态决定，不是签名决定。候选 §7 第 1 项也承认这一点。

### 2.3 恢复时的新 fence 与旧命令：BLOCK

已读代码里的事实：`ReconcileOwnerTx`（worker L140 起）

- `journal.Seq > lastSeq` 时直接冻结，原因记为 `journal_ahead`（L185–187）。
- 只有 verdict 已经提交、而且就是链尾时，才返回 `Replayed`（约 L190–202）。
- **整个函数不读 command 表，也不读 `open_request_id`。**

**反例 3-A：恢复入口不存在【当前】**
- 场景：worker 已经备好 journal，seq = lastSeq + 1，verdict 还没提交，然后崩溃。重启后先 `BeginOwnerTx`，再 `ReconcileOwnerTx`。
- 实际结果：L185 判为 `journal_ahead`，冻结。
- 候选 §3.4 说「journal 恢复…必须先经过 Reconcile」「新 fence 下重放原 command」，但按当前代码这条路**根本走不到**。候选又没有给出修改 Reconcile 的具体规则。
- 后果：这是 fail-closed，不会损坏数据；但 design §4 的恢复语义没有实现。实现者如果自己放开 `journal_ahead`，就会落入反例 3-B。

**反例 3-B：只靠服务端状态授权【候选】**
- 候选 §3.4 在锁内用 CAS 把 `effective_fence` 从旧值推进到当前 fence。这一列没有签名。
- 只要某段服务端代码持有事务并执行这次 CAS，旧 owner 签发的命令就在新 fence 下生效，**没有任何签名方重新认可过**。
- 候选 §4 也承认只能做到服务端可信。要做到签名绑定，需要一个 checkpoint，同时签 lineage、store、epoch、新 fence、open 的 request_id 和原 command 的 digest；protocol 里这个 checkpoint 的字段**没有核实（待核）**。
- 在规格明确接受「服务端可信」或者签名 checkpoint 落地之前，判 BLOCK。

### 2.4 事务内 command/cursor 的状态：BLOCK【候选】

已读代码里的事实：

- 新 command 插入时的状态是 `created`（store L210）。
- `TransitionControlCommandTx` 允许 `created→issued`、`issued→result_ready` 等转换（L285 起）。
- `open_once` 相关的开放状态有 4 个：created、issued、result_ready、uncertain（L45）。`ApplyControlCommandTx` 按这 4 个状态计数（约 L188–197）。这个计数和 cursor 的 `open_request_id` 是两套独立的 slot。

**反例 4-A：状态机断链【候选】**
- 候选 `EnsureRequestTx` 插入的是 `created`。候选 Append（§3.3 第 3 步）要求 `state = issued`。
- 候选整条链里**没有任何一步做 created→issued**。按字面实现，每次 Append 都会被拒；要么就是实现者自行猜一个转换的位置和事务。候选 §7 第 3 项也自认未定义。

**反例 4-B：两套 slot 可能不一致【候选，部分待核】**
- 候选让 Append 不清 open，改由结算清（§3.3 第 5–6 步）。但结算代码没读，结算是否会同时让 command 状态离开开放集、并清掉 cursor open，没有保证。
- 如果结算只推进了 command 状态而没有清 open，下一次 `EnsureRequestTx` 的 CAS（要求 `open_request_id IS NULL`）就会永久失败。fail-closed，但 lineage 卡死。
- 反过来，如果只清了 open 而 command 还在开放集，就会撞上 `ApplyControlCommandTx` 的计数冲突。

### 2.5 签名前后的有效期与锁竞争：BLOCK【候选】

已读代码里的事实：

- command：先用调用方的 Now 验签（L158），拿 advisory 锁之后再用服务器时钟复验（L199–203），然后插入。这个位置是对的。
- verdict：先用调用方的 Now 验签（L411）；拿 cursor 锁（L450）之后，用服务器时钟复验（L473–476），然后插入。按当前只有一把锁的情况，位置也是对的。

**反例 5-A：复验之后还有一把锁要等【候选】**
- 候选 Append 的锁序是 advisory → cursor → command `FOR UPDATE`。候选只说「保留现有验签」，复验点仍在 cursor 锁之后、command 锁之前。
- 构造步骤：
  1. 签名密钥在 T 时刻过期。
  2. Append 在 T-1 时刻拿到 cursor 锁，复验通过。
  3. 对 command 行 `FOR UPDATE` 时，被持有该行锁的结算事务阻塞，一直等到 T+5。
  4. 拿到锁后直接插入。
- 结果：用过期密钥签的 verdict 入链。
- 修复条件：服务器时钟复验必须放在**最后一把锁之后**、第一次写入之前。

### 2.6 exact replay：BLOCK【候选】

**反例 6-A：结算后再发同一条 command，不再幂等【候选】**
- 候选 §3.2 第 2 步规定：只有 command 已存在、逐字段相同，**并且 `open_request_id` 仍然是它**，才返回已存储的记录。
- 构造步骤：
  1. request R 打开，追加 verdict，结算按候选 §3.3 第 6 步清空 open。
  2. 客户端因为超时，原样重发 R。
- 实际结果：第 2 步不满足（open 为 NULL），落到第 3 步；`expected_seq ≠ last_seq+1`，返回 SEQUENCE_GAP 或 CONFLICT，而不是幂等返回。
- 后果：客户端可能把错误理解成「没执行」，于是重新签发一个新 request，导致同一个意图被重复执行。
- 对照：当前的 `ApplyControlCommandTx` 在 open 检查之前就做了重放判定（L178），没有这个问题。

**次要问题 6-B：verdict 重放查找在锁之前，用的是调用方时钟【当前，次要】**
- `AppendVerdictFrameTx` 先用 `in.Now` 验签（L411），然后在锁之前做重放查找（L442）。
- 如果调用方传入一个过去的 Now，用已过期密钥签的帧仍能通过验签，并作为「已存在」返回成功。
- 这一步不写数据，所以不是数据损坏；但调用方可能把它当作 ACK。
- 候选 §3.4 的「完全相同的重放不核对 fence」会把这个行为延续到已被隔离的旧 owner。需要评审确认可以接受。

### 2.7 上线时已有的状态：有条件 PASS（fail-closed）

- 已读代码中，生产路径从来不写 cursor 的 `open_request_id`。只有 `OpenControlRequestTx` 会写（L504 起），而据 `REVIEW-STRONG.md` §2.5，它只在测试里被调用。
- 所以已部署环境里，只要存在处于开放状态的 command 行，cursor open 必然为 NULL，就会被候选 §3.1 第 3 步判为 `open_mismatch`，**全部冻结**。
- 这不会损坏数据，也不会让授权失效，但会导致大面积不可用。候选 §3.6 自己没有夸大，结论保持「需要部署检查」。
- 待核：
  - `frozen_reason` / `reconcile_proof` 这两列是否真的存在（候选引用 648 L157–158，648 正文未读）；
  - 当前已读代码中**没有任何地方写这两列**，冻结记录由谁写、什么格式，都未定义。
- 条件：拿到部署状态的检查证据之前，不能把这一项升级为 PASS。

### 2.8 生产入口缺失：BLOCK【当前】

- `EnsureRequestTx`：在已读的两份文件里不存在，与候选的说法一致；全仓没有 grep。
- `ApplyTx` 和 `OpenControlRequestTx` 没有非 test 调用方。这一条引自 `REVIEW-STRONG.md` §2.5，本次没有重跑。
- `BeginOwnerTx` 的生产调用方没有查。
- **【当前】`OpenControlRequestTx` 会改写 fence**（L504 起）：它执行 `SET owner_fence = $5`，WHERE 里只有 `open_request_id IS NULL`。任何调用方都能把 fence 设成任意值，包括比原来更小，从而让已被隔离的旧 worker 重新通过 `assertFenceTx`。候选 §3.2 打算修掉这一点，但目前还没修。
- **【当前】`ApplyControlPolicyEventTx` 完全不验签**（L249 起）：revoke/stop 的 envelope 是服务端自己构造的。这个方向是 fail-closed 的（只会挡住后续命令），但不在签名覆盖范围内，不属于候选方案处理的范围。

---

## 3. 进入 RED 之前的最低前置条件

1. 插入 command 时强制 `effective_fence = owner_fence = cursor.owner_fence`，并把 `effective_fence` 纳入重放比对（对应 2.2）。
2. 读完 settlement、admission 和 dispatch root 的加锁路径以后，定一个全局锁序，统一 advisory、cursor、command 三者的顺序，并规定结算路径也要拿 advisory 锁（对应 2.1）。
3. 把服务器时钟复验放在最后一把锁之后（对应 2.5）。
4. 规定 created→issued 由谁、在哪个事务里推进，并规定 Append 和结算各自让 command 进入什么状态（对应 2.4）。
5. command 的 exact replay 不依赖 open 状态（对应 2.6）。
6. 恢复路径二选一：要么修改 Reconcile 的 `journal_ahead` 行为并实现签名 checkpoint，要么在规格里明确「旧命令一律冻结，不在新 fence 下重放」（对应 2.3）。
7. 补读 migration 648 正文和规格文档，核实 0.1 节列出的待核项（对应 2.4、2.7）。
8. 对目标部署做独立检查，确认 648 是否已应用、有没有已存在的数据（对应 2.7）。

## 4. 剩余风险

- 2.1、2.4、2.7 的部分结论依赖没读的 648 正文、settlement、admission 代码和规格文档。补读以后，判定可能收紧或放宽。
- 所有反例都是静态推导，没有在 DB 上复现。
- 行号对应上表 SHA 的工作区文件。文件一旦改动，行号就会失效。
