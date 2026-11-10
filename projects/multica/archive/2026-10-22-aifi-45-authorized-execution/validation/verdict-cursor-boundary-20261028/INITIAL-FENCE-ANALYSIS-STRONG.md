# AIFI-45：`ApplyControlCommandTx` 首次插入时 `effective_fence` 的静态分析（只读，Strong）

**状态：未实施、未测试，结论维持 BLOCK。**

本文只回答一个问题：首次插入 command 时，能否要求 `effective_fence == owner_fence`。静态阅读的结论是，这个检查**有可能**放进去，但只能放在首次插入那个分支里，不能放在入口校验处。下面几件事都**没有验证**：

- 换 fence 之后重放已有 command 的行为；
- command 首次签名与 DB 插入之间的先后顺序；
- 实际部署的 schema 和存量数据；
- 全局锁序。

因此本文**不认为恢复兼容已经得到证明**，也**不认为 cursor 绑定的 BLOCK 已经解决**。本文所有内容都是读代码得出的推论，不能当作验证通过。本次没有改代码或旧材料，没有连 DB、没有起容器，也没有跑真实 CR。

## 0. 原始 SHA

| 对象 | 标识 | 说明 |
|---|---|---|
| multica 仓 HEAD | `81e5293adc758e392a045026cf81ec5cc1bac72d` | — |
| `server/internal/governance/execution_control_store_state.go` | sha256 `f437aa2e2a29e26e0744d68d6da226101de6af618043e3a3d14bddafe86d684f`；git blob `8f189502463d99fa7ff6f559e1f19b640f2426ee` | 工作区有**未提交改动**（相对 HEAD 是 +155/−22）。下文行号以这一版工作区为准 |
| `server/migrations/648_cr_execution_control.up.sql` | sha256 `89f0c3f061c73dae188f99ada0accd13ab770e72e7a96130eb70c3c8c07b5b61` | 和 HEAD 一致，与候选方案、各份 review 记录的哈希相同 |
| `projects/multica/archive/2026-10-27-trusted-verdict-channel/design.md` | sha256 `73834bd4bfbbb6b16384387e05ee09a899bbde034170ccf25a33e709c02586f8` | 恢复语义的出处 |
| 本目录 `DESIGN-CANDIDATE-STRONG.md` | sha256 `ab6ca227859194d06bafd7bb313a417cb5fddffbd6c317aa832be31ca6ad8718` | 候选方案 |
| 本目录 `DESIGN-REVIEW-INDEPENDENT-STRONG.md` | sha256 `6778daf8c873dce1c426bc3de4862938dd047d00c3a8693ced18e0b76eb4c857` | 独立 review（反例 2-A） |
| 本目录 `REVIEW-STRONG.md` | sha256 `2a475ca31ba5c07bc646874adaf5de032a06141b0913ec70c7afca841d343e9d` | — |

## 1. 现状（源码与 648）

### 1.1 入参怎么校验

`execution_control_store_state.go`：

- **L152**：`OwnerFence` 和 `EffectiveFence` 只要求大于 0。
- **L115–118**（`verifyControlCommand` 内）：只核对 `in.OwnerFence` 是否等于签名里的 `B.owner_fence`。这个函数在 L158 调用一次，等锁之后在 L199–203 又调用一次。
- **`EffectiveFence` 没有签名**，不和签名比，也不和 cursor 比，在 L204–210 原样写入。这就是独立 review 的反例 2-A：签名里 fence 是 1，传入 effective 是 2，照样能插进去。

### 1.2 重放怎么判定

- **L167–172**：按 `request_id` 查已有行，比对这些字段：`scope`、`lineage_id`、`reservation_id`、`owner_fence`、`seq`、`prev_digest`、`command_bytes`、`envelope`。**`effective_fence` 不在比对范围内。**
- **L175–178**：查到行且字段一致，就直接返回 `Replayed`，不会进入后面的 stop 检查（L184）、open slot 检查（L188–196）和插入（L204）。

### 1.3 调用方

- 非测试代码里**找不到** `ApplyControlCommandTx` 的调用方（静态 grep，只覆盖本仓源码）。
- 非测试代码里写 `effective_fence` 的地方只有两处：本函数的插入（L206/L209），以及 `ApplyControlPolicyEventTx` 的插入（L271–278）。
- 也就是说，本仓源码里**还没有**任何恢复路径会推进 `effective_fence`。

### 1.4 648 的约束

- **L83–84**：两列都是 `BIGINT NOT NULL`。
- **L98**：CHECK 只要求两列都大于 0，**两列之间没有任何约束**。
- 触发器 `cr_execution_command_transition`（定义在 L414–463，挂载在 L599–601，`BEFORE UPDATE`）：
  - L422 把 `owner_fence` 设为不可改；
  - `effective_fence` **不在**不可改清单里；
  - L449–457 的注释写明，终态行可以为恢复修改 `effective_fence`，只有 `verdict_id` 会被拒绝修改；
  - 这个触发器不管 INSERT。
- 推论：在应用层给插入加等值检查，**不需要改 648**，静态上也看不出和 648 冲突。

### 1.5 设计中的恢复语义

archive `design.md` L63–68 是这样描述的：

- 先拿新 fence，把旧 worker 隔离掉；
- `ReconcileOwnerTx` 分情况处理：
  - 链尾相同：恢复原 request；
  - 恰好领先一项：导入原 verdict bytes，再正常结算；
  - 已经结算：返回原 mapping；
  - journal 处于 prepared：在新 fence 下重放原 command；
- 缺失、落后、分叉或多项超前：一律冻结，不推测，不清 slot。

## 2. 可能的实施位置（未实施）

- **放在哪里**：只放在首次插入分支。也就是 L179–181 确认查无此行（`ErrNoRows`）之后、L204 INSERT 之前，可以放在 L196 和 L204 之间，也可以紧跟 L199–203 的二次验签。
- **检查什么**：`in.EffectiveFence != in.OwnerFence` 时，返回 `ErrControlStoreInvalid`。
- **不能放在 L152**：放在那里，会拒掉"行已存在、但传入的 effective 不同"的重放请求，而这类请求现在会返回 `Replayed`。这样就改变了重放合同。
- **这一步不要把 `effective_fence` 加进 L168 的重放比对**：恢复把这一列推进之后，用原始输入发起的重放会变成冲突，同样改变重放合同。

### 静态推论（未验证）

- 设计里允许的恢复，针对的都是已经存在的 command 行：
  - 签名里的 `owner_fence` 不可改，始终是旧值；
  - 这类请求走重放分支（L178），根本到不了插入检查；
  - 把 `effective_fence` 推进到新 fence，是之后对已有行的 UPDATE，648 允许这样改。
- 插入检查只会拦下一种情况：首次插入时传入的 effective 与签名 fence 不同。按设计，"M 侧没有这条 command 行"属于缺失，应当冻结，而不是新插一行。
- 以上只是推论。下面第 3 节的前提有任何一条不成立，这个结论都可能被推翻。

## 3. 未解决的前提（都是这次 BLOCK 的原因）

1. **跨 fence 重放没有验证。** 没有跑测试，确认"行已存在，传入新的 `EffectiveFence`"仍然返回 `Replayed`，并且行内容不变。
2. **command 首次签名和 DB 插入的先后不清楚。** 如果某条路径先签名、先把 command 发给 worker，之后 M 才提交插入，就可能出现"worker 的 journal 处于 prepared，但 M 侧没有这行"。这时在新 fence 下重放会变成首次插入，被这条检查拒掉。目前这条链路没有接线，无法确定是否存在这种时序。
3. **实际部署不清楚。** 各环境是否应用了 648、有没有手工改过、是否已有 command 行，以及已有行的 `effective_fence` 和 `owner_fence` 是什么关系，都不知道。
4. **全局锁序不清楚。** 这条检查只保证 effective 等于**签名里的** fence，**不保证**等于 cursor 的 `owner_fence`。要和 cursor 比，就得在 advisory lineage 锁之内读 cursor，这牵涉到和 settlement、admission、dispatch、`assertFenceTx` 之间的锁序，本次没有核对。
5. **cursor 绑定没有解决。** 独立 review 里的这些项都不在本文范围内，仍然开着：
   - `OpenControlRequestTx` 可以改写 fence；
   - verdict 追加时的 open/fence CAS；
   - `effective_fence` 推进时没有签名、没有单调性约束；
   - 结算后重放的幂等性。
6. **`ApplyControlPolicyEventTx` 没有纳入。** 它的插入（L271–278）对 `effective_fence` 只有 DB 层"大于 0"的约束，本文没有分析。
7. **648 没有单调约束。** 插入之后，`effective_fence` 可以被任意改写，包括往小改。要加 DB 层约束，就得先改规格或新增迁移。
8. **源码有未提交改动。** 行号和 blob 以第 0 节的工作区版本为准，实施前必须重新核对。

## 4. 建议测试（需要 DB，均未运行）

| # | 用例 | 期望 |
|---|---|---|
| T1 | 首次插入，签名 fence=1，`EffectiveFence`=2 | 返回 `ErrControlStoreInvalid`，表里没有这一行 |
| T2 | 首次插入，两个 fence 都是 1 | 返回 `created` |
| T3 | 行已存在，用相同字段重放，但传入 `EffectiveFence` 不同 | 仍然返回 `Replayed`，行内容不变（锁住重放合同） |
| T4 | 回归测试：stop/revoke 顺序、open slot 冲突、签名过期后的二次验签 | 行为不变 |

现有测试夹具里两个 fence 都相等，包括 `internal/governance/execution_control_store_state_test.go`、`execution_control_command_attestation_test.go`、`internal/daemon/execution_control_worker_test.go`、`execution_control_recovery_d8_test.go`。`attestation_test.go` L73 的 `input.OwnerFence++` 预期会先在验签那一步失败。这些预期也都**没有运行确认**。
