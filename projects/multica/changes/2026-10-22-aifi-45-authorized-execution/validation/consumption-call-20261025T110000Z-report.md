# ① 消费调用单开关（默认关）+ ③ 清 tools 旧账

## ① 消费调用：一个开关，默认关

**问题**：服务端已经有消费端点，但 daemon **从来不调用**它；要等 Gate 翻转时再临时接线，等于把决策点藏进一次大改动里。

**做法**：把"是否把交付当成消费"收敛成**一个字段 + 一个调用点**。

- `Client.requestExecutionConsumption`：body **恰好四键**（task_id/runtime_id/dispatched_at/challenge）、解析 `receipt`/`changed`、空 CR ID 与空 challenge **不发网络请求**、200 但无 receipt 判错（不产生"空收据"）。
- `Daemon.recordConsumptionAfterDelivery`：**默认 false**，且生产代码里**没有任何地方**把它设为 true（独立面 `git grep` 核实）——所以今天行为与之前完全一致。
- `executionBindingEndpoint.DeliveredChallenge()`：只有在**响应写成功之后**才记录本次交付的 challenge；写失败 ⇒ 视为"run 没拿到证明"。
- `daemon.go`：在 run 结束的 `defer` 里，若 `DeliveredChallenge()` 非空**且**开关开 ⇒ 调消费端点；失败只 `warn`，**不失败任务**（消费是记录，不是准入门槛）。

**为什么是"交付"而不是"使用"**：daemon 观察不到 T 内部是否真的用了证明——T 验完就按设计以 `EXECUTION_CONSUMPTION_REQUIRED` 退出。所以这个开关的语义必须在开启时被**明确接受为"拿到即消费"**，这正是 Gate 要拍的那件事。默认关、且注释里写明，是为了不让它悄悄变成事实。

**证据**（`consumption-call-…-green2`）：**8 RUN / 8 PASS（7 leaf）**

| 用例 | 断言 |
|---|---|
| `TestRequestExecutionConsumptionClient` | 路径/方法正确、body 键集合恰为四键 |
| `…ClientRefusals/*` | 409 两种码、200 无 receipt、空 CR 不发请求 |
| `TestRecordDeliveredConsumptionSwitchIsOffByDefault` | **开关关 ⇒ 0 次请求、返回空**；开 ⇒ 1 次且拿到 receipt；无 CR/无 challenge ⇒ 不请求 |
| `TestEndpointReportsOnlyWhatItDelivered` | 未响应时 `DeliveredChallenge()` 为空；响应后等于该 challenge |

**RED 探针**（忽略开关 + 不记录 delivered）→ **2 FAIL**（`switch off = (...Receipt:"1111…")`、`delivered = , want …`），两条都有鉴别力。

## ③ tools 旧账：按语义注入，而不是按调用计数

**失败**：`CR-2026-030 TASK-01：owner-set 恢复失败 → OWNER_COMMIT_ROLLBACK_FAILED（AC-15）` 报 `INTERNAL_ERROR`，栈在 `durable-tx.mjs:266 saveJournal`。

**根因**：该用例用"第 11 次 `fs.renameSync` 失败"来模拟回滚失败。产品后来在 apply 之前多了一次 journal rename，于是第 11 次落在 **saveJournal**，根本不是回滚恢复点 → 抛的是通用内部错误。这是**测试与实现细节耦合**，不是产品缺陷。

**修法**：把注入从"全局第 N 次"改成"**写入 `cr.md` 的第 2 次**"——第 1 次是 apply，第 2 次就是回滚把原文放回去。判断只用 `String(b).includes('CR-T1') && String(b).endsWith('cr.md')`，不依赖分隔符，也不再被无关 rename 数量影响。

**结果**（作者跑）：

| 范围 | 结果 |
|---|---|
| `crctl.test.mjs` | **299 / 299** |
| tools 全量 `scripts/test/*.test.mjs` | **1058 tests / 1057 pass / 0 fail / 1 skip** |

失败从 1 变 0，且**没有放宽任何断言**（错误码仍是 `OWNER_COMMIT_ROLLBACK_FAILED`、仍要求 `affected` 数组）。

## 边界

- 开关默认关 ⇒ **今天仍然没有任何消费调用**；T 仍以 `EXECUTION_CONSUMPTION_REQUIRED` 退出。
- activation 记录、收据、开关都**不等于准入**；不签 activation 语义、隔离执行域、全局 C1。
- 旧账清理只动测试注入方式，产品代码零改动（`git status` 里 `crctl.test.mjs` 是唯一 tools 变更）。

## 终轮独立回归（唯一认领）

| # | 命令 | RUN/PASS/FAIL/SKIP | PASS leaf |
|---|---|---|---|
| 1 | governance `^TestExecution(Activation\|Consumption)`（643+644+645） | **17 / 17 / 0 / 0** | 15 |
| 2 | handler `^TestStartClaim` | 13 / 13 / 0 / 0 | 10 |
| 3 | daemon（含 RequestExecution / RecordDelivered） | **160 / 158 / 0 / 2** | 144 |

- 三条 `error=null`、`original_unchanged`、`owned_resources_cleaned`、`sessions=0`、`locks=0`；原库 **137 表/6228 行/82 审批** 均一致；**20/20 hash 零漂移**。
- 独立面只读核实：`recordConsumptionAfterDelivery` **只**在 `execution_consumption_client_test.go:141` 被赋 true，**生产代码零赋值**；`DeliveredChallenge` 记录点在 `execution_binding_endpoint.go:155 → :161`（写响应之后）。
- 独立面复跑 tools 旧账单文件：**299 / 299 / 0 fail / 0 skip**，`CR-2026-030 … AC-15` **PASS**（790ms）。

（作者另跑 tools 全量为 1058 / 1057 pass / 0 fail / 1 skip；两者不混算。）
