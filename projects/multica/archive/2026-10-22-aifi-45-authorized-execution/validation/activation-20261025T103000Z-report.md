# 不可删 activation（增量 9）

## 先立语义，再写代码

`tasks.md` 5 处点名「不可删 activation」，但 `design.md`/`slices.md`/`test-plan.md` 与 tools 侧 wire-contract **都没定义它**。凭空造一张叫 activation 的表，等于用实现冒充设计。所以先落 `activation-semantics.md`，把语义从已有事实（签发/消费/撤销）**推导**出来，并明确标注"该语义是本次推导，Gate 前需确认"：

- activation = **平台声明「这个 run 代次在当前 head 上满足了准入前置」**；
- 推论 1：**必须有 receipt 才能激活**（否则 activation 成为绕过消费的第二条准入旁路）；
- 推论 2：**不可删 ≠ 可撤销**——停下只能产生新事实（撤销 head），不能抹掉"曾经激活过"；
- 推论 3：**一代次一条**（与 receipt 同粒度）。

## 实现

**迁移 `645_cr_execution_activation.{up,down}.sql`**

- 表 `cr_execution_activation`，唯一键 `(workspace, cr, runtime, task, dispatched_at)`；
- `consumption_id` 指向授权它的 receipt（应用层校验，无 FK）；
- 触发器拒 **UPDATE / DELETE / TRUNCATE**（`BEFORE UPDATE OR DELETE` 行级 + `BEFORE TRUNCATE` 语句级）——"不可删"必须挡住能直连 DB 的写者，不能只挡应用。

**`POST /api/daemon/crs/{crID}/execution-authorization/activation`**（仅 daemon token）

- body 同签发 exact 4 键；同事务复核 claim / head（撤销・scope・policy・template・source）/ coordinator / daemon / challenge；
- **head 校验先于幂等分支**：撤销后即使已有 receipt 也拒绝激活；
- 查 receipt：无 → 409 `EXECUTION_CONSUMPTION_REQUIRED_FOR_ACTIVATION`；challenge 与 receipt 不一致 → 409 `EXECUTION_ACTIVATION_CONFLICT`；
- 插入 `ON CONFLICT DO NOTHING`：新写 **201 `changed=true`**；重放 **200 `changed=false`** 且返回同一 activation id；异 challenge/异 head_digest → 409；
- **没有 DELETE 路由**（测试断言 405/404）。

## 证据（含一次假绿被发现）

| 轮次 | 内容 | 结果 |
|---|---|---|
| `green1` | 首版实现 | 5/5 PASS（5 leaf）——但仍无 RED |
| `red1` | 迁移探针写坏（只注释掉 `CREATE TRIGGER` 那行，留下 `BEFORE TRUNCATE` 悬挂） | **invalid**：migration 语法错，不计 RED |
| `red2` | 去掉整段 TRUNCATE 触发器 + 去掉 receipt 要求 | 只有 1 FAIL（receipt），TRUNCATE 用例仍绿 |
| — | **发现假绿**：`TRUNCATE` 那条把 `$1` 传给了没有占位符的语句，pgx 报的是**参数个数错误**，不是触发器拒绝 | 修测试：三条语句各自独立执行 |
| `red3` | 同样两个探针 | **2 FAIL**：`activate without a receipt = 500`、`TRUNCATE succeeded but the activation fact must be immutable` → 两条都有鉴别力 |
| `green2` | 还原后 | **5 RUN / 5 PASS（5 leaf）**，643+644+645 三条迁移均记录，原库无漂移 |

## 覆盖的不变量

1. `no receipt, no activation` → 409 且 0 行；
2. 消费后可激活 → 201、UUID、1 行，且 `consumption_id` **等于**那张 receipt；
3. 同代次重放 → 200、同 id、仍 1 行；
4. 同代次换一份**也已签发**的证明 → 409 `EXECUTION_ACTIVATION_CONFLICT`、0 行；
5. 撤销 head 后激活 → 409（head 拒绝）且 0 行；
6. `UPDATE`/`DELETE`/`TRUNCATE` 全部报错，行数仍 1；`DELETE` 路由 405/404。

## 边界（不得外推）

- **仍未准入**：没有任何消费者读 activation，T 仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出，daemon 也未调用本端点。**activation 记录 ≠ 已准入**。
- 语义是本次推导，**未**经 Gate 确认；若最终设计不同（例如 activation 需要绑 daemon 心跳/隔离域），本表结构要随之调整。
- 不签隔离执行域、全局 C1；不解除 `EXECUTION_CONSUMPTION_REQUIRED`。

## 终轮独立回归（唯一认领）

| 项 | 值 |
|---|---|
| governance `^TestExecution(Activation\|Consumption)`（643+644+645） | **17 / 17 / 0 / 0（15 leaf）** |
| handler `^TestStartClaim` | 13 / 13 / 0 / 0（10 leaf） |
| daemon `Test.*Execution` | 153 / 151 / 0 / 2（138 leaf，SKIP=helper、Windows symlink） |
| activation 5 用例 + consumption 6 子例 | **全部实际 PASS 非 SKIP** |
| 原库 | 137 表 / 6228 行 / 82 审批，三条均一致 |
| 安全 | `error=null`、`original_unchanged`、`owned_resources_cleaned`、`sessions=0`、`locks=0` |
| 18/18 hash | 前后一致（`…-freeze-manifest.json`，已去重） |
| catalog | gov 504234/504235、handler 507137/507138、daemon 509976/509977，末尾均不存在 |

迁移 645 sha `62e836e9…ad344`。

独立面另确认两件结构性事实：

- **head 校验确实先于** receipt / 幂等分支（`execution_activation.go`:86 head 读取 → :97-99 校验 → :104/:123 payload+challenge → :133-152 receipt → :167+ 幂等）；
- `BEFORE TRUNCATE` 触发器**不会**阻断 `DROP TABLE`，down 迁移先删 trigger 再删表，**可回滚**。
