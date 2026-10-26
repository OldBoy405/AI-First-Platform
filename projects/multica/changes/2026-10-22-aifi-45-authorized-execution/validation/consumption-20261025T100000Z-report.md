# 执行消费收据（增量 7）：把"签过"变成"花掉了"

## 为什么需要它

前几片打通了：签发 → 交付（私有 stdio / per-run 端点）→ T 侧验签 → 跨语言互通。缺的一环是**消费**：平台无法知道某份证明是否真的被某个 run 用过、用了哪一次。没有这一步，`EXECUTION_CONSUMPTION_REQUIRED` 永远解不开。

## 做了什么

**迁移 `644_cr_execution_consumption.{up,down}.sql`**

- append-only 收据表，唯一键 `(workspace_id, cr_id, runtime_id, task_id, dispatched_at)`——**一个 run 代次一张收据**；
- 触发器拒 `UPDATE`/`DELETE`；无 FK/级联；`challenge`/`grant_digest`/`head_digest` 均 64 字符约束。

**`POST /api/daemon/crs/{crID}/execution-authorization/consumption`**

- 与签发**相同的 exact 4 键 body**、相同的 daemon-only 认证；
- 同一个 RR 事务里复核：claim（runtime+代次+active+`cr_id`=URL CR+认证 workspace+daemon）、head（复用 `validateExecutionAuthorizationHead`：撤销/scope/policy/template/source）、coordinator/daemon/scope；
- **必须存在对应签发记录**（`(workspace, cr, grant_digest, challenge)`），否则 409 `EXECUTION_BINDING_NOT_ISSUED`——没签过的 challenge 不可能拿到收据；
- 插入用 `ON CONFLICT DO NOTHING`：新写 → **201 `changed=true`**；同代次重放 → **回滚后重读** → **200 `changed=false` 且返回同一 receipt**。

## 证据

| 轮次 | 内容 | 结果 |
|---|---|---|
| `consumption-…-green1` | 首版实现 | **6 RUN / 6 PASS（5 leaf）**，两条迁移均记录 sha256 |
| `consumption-…-red1` | 删掉“必须存在签发记录”检查 | **3 FAIL**（`no_proof_means_no_receipt`、`a_proof_for_another_challenge_cannot_be_consumed`、父用例）→ 该检查确有鉴别力 |
| `consumption-…-green2` | 还原后 | **6 RUN / 6 PASS（5 leaf）**，原库 137 表/6228 行/82 审批无漂移 |

覆盖的子例：

1. `a_verified_proof_is_consumed_once` —— 首消费 201、`changed=true`、receipt 是 UUID、行数 1；**重放 200、`changed=false`、同一 receipt、行数仍 1**；
2. `no_proof_means_no_receipt` —— 未签发 → 409 `EXECUTION_BINDING_NOT_ISSUED`、行数 0；
3. `a_proof_for_another_challenge_cannot_be_consumed` —— 签了 A 却拿 B 来消费 → 409、行数 0；
4. `only_the_daemon_token_may_consume` —— 空 token 与用户 session token 均被拒（401/403），行数 0；
5. `the_receipt_table_refuses_mutation` —— 直接 `UPDATE`/`DELETE` 收据表均报错（验的是迁移触发器，不是应用层）。

## 对抗与并发（增量 8，只加测试不改逻辑）

`execution_consumption_adversarial_test.go`：

| 用例 | 钉住的不变量 |
|---|---|
| `a_revoked_head_cannot_be_consumed` | 签发后撤销 → 消费 **409**，**0 张收据** |
| `another_generation_cannot_consume_this_proof` | 同 task/challenge、异 `dispatched_at` → 409，0 张收据 |
| `a_consumed_proof_cannot_be_reconsumed_after_revoke` | 先消费 201，撤销后再消费 → **409 且 body 含 `EXECUTION_AUTHORIZATION_HEAD`**（头校验先于幂等分支），行数仍 1 |
| `TestExecutionConsumptionIsRaceFree` | 8 个 goroutine 同代次并发 → **恰好 1 个 201、7 个 200、同一 receipt、表里 1 行** |

证据：`adversarial2` **12 RUN / 12 PASS（10 leaf）**，643+644 均记录；
**RED 探针**（删 `ON CONFLICT DO NOTHING`）→ **4 FAIL**（race 用例 7×500 + 两个幂等用例 500），说明并发唯一性真的靠那条子句。

## 明确没做

- **没有**把 `EXECUTION_CONSUMPTION_REQUIRED` 去掉：T 侧仍以它收尾，daemon 也**还没有**调用这个端点。收据只是"可被写入的证据"，不是准入开关。
- **没有**收据 → 准入的判定逻辑（那属于 activation 决策，且需要 Gate）。
- 未签 activation、隔离执行域、全局 C1。

## 两轮自纠 + 一次被独立面拦下

1. **收据按 run 代次唯一、不含 challenge**：同一代次先后用两个都已签发的 challenge 消费时，第二个会被当成重放并返回**第一张** receipt——这等于告诉调用方“你的 challenge 已被消费”。已改为：冲突后读出已存 receipt 并**比对 challenge**，不一致则 **409 `EXECUTION_CONSUMPTION_CONFLICT`**；新增子例 `a_second_challenge_for_one_generation_is_refused`。
2. **Rollback-then-read 的竞态**：原实现冲突后 `tx.Rollback()` 再用池连接重读，可能读到并发事务尚未提交前就 `ErrNoRows`。已改为 **READ COMMITTED**（这张表靠约束保证唯一，各校验都是时点事实），冲突后的读在**同一事务**内完成，无需回滚。
3. **`head_digest` 列重复**：代码里根本没有独立的 head digest（`head.GrantDigest` 就是它），原迁移多存一列同名值容易误导。已从迁移与 INSERT 中删除。
4. **被独立面拦下的一次**：我一边让独立代理跑基线、一边改源码，它检出 `execution_consumption_test.go` / `644_*.up.sql` hash 漂移并 **STOP**（`FINAL_13OF13=false`），拒绝把 hybrid 工作区当成冻结证据——这是正确行为，记在本报告里作为流程教训：**冻结期间不得改源码**。
5. **一次自己的回退事故**：strong 复审代理在被要求“还原 mutation”时，把我已改好的 `execution_consumption.go` 恢复成了**旧版**，导致随后一次运行出现 4 个 500（INSERT 仍带 `head_digest`，而迁移已删该列）。定位后重写并全绿。教训：**多代理共享一个工作区时，restore 必须限定到它自己改的 hunk**。

## 终轮独立回归（final2，唯一认领）

| 项 | 值 |
|---|---|
| governance `^Test`（643+644） | **911 RUN / 910 PASS / 0 FAIL / 1 SKIP（823 leaf）** |
| handler `^TestStartClaim` | 13 / 13 / 0 / 0（10 leaf） |
| daemon `Test.*Execution` | 153 / 151 / 0 / 2（138 leaf） |
| 消费 6 子例 | **全部实际 PASS，非 SKIP** |
| 原库 | 137 表 / 6228 行 / 82 审批，三条均前后一致 |
| 安全 | `error=null`、`original_unchanged`、`owned_resources_cleaned`、`sessions=0`、`locks=0` |
| 13/13 hash | 跑前跑后一致（`…-final2-freeze-manifest.json`） |
| catalog | gov 463512/463513、handler 466892/466893、daemon 469731/469732，末尾均不存在 |

迁移记录：643 `495ec3c0…cfcbbe`、644 `d07d5282…2e3b`。

## 终轮独立回归（final3，唯一认领）

| 项 | 值 |
|---|---|
| governance `^TestExecutionConsumption`（643+644） | **12 / 12 / 0 / 0（10 leaf）** |
| handler `^TestStartClaim` | 13 / 13 / 0 / 0（10 leaf） |
| daemon `Test.*Execution` | 153 / 151 / 0 / 2（138 leaf） |
| 四个对抗/并发用例 | **全部实际 PASS 非 SKIP** |
| 原库 | 137 表 / 6228 行 / 82 审批，三条均一致 |
| 安全 | `error=null`、`original_unchanged`、`owned_resources_cleaned`、`sessions=0`、`locks=0` |
| 14/14 hash | 跑前跑后一致（`…-final3-freeze-manifest.json`） |
| catalog | gov 481217/481218、handler 484098/484099、daemon 486937/486938，末尾均不存在 |

**冻结链**：final1（用例未同步，4×500）→ final2 → **final3（已认领）**；更早已作废的 green1/2/3 一律不认。
