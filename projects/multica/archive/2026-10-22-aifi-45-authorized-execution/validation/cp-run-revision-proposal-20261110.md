# CP-RUN-004/005/007/008/009 修订方案（待批准，不改 canonical）

> 记录性质：设计偏离与修订记录。**2026-11-10 用户明确批准「这五条按上表改 CP」，已据此改写 canonical 的 CP-RUN-004/005/007/008/009 与 harness 前置；本文件仍不是 Gate 证据，也不改变历史批准。**
> 背景：`canonical/specs/agent/authorized-runner.yaml` 的 CP-RUN-001～010 主项都声明
> `go test ./cmd/server -run ^TestTC_RUN_00N$`，但 `cmd/server` 只存在 `TestTC_RUN_002/003/010`。
> RUN-001 已按路由层补齐（另行实现）；本文件处理其余四条。

## 一、判断标准

一条 CP 存在的意义是：**用一条命令、一组可观察断言，证明某一契约确实成立**。因此：

1. **入口必须与契约所在层一致。** 契约讲的是 HTTP 行为，就在 `cmd/server` 用真实 router 验证；契约讲的是调度/治理行为，硬放到 `cmd/server` 只是转发一层，不增加证据，反而制造“路由已覆盖”的错觉。
2. **不为名字写测试。** 若某 TC 的真实证据在 governance/daemon，就把 CP 改到那里并写明理由与残留，而不是补一个同名空壳。
3. **一条 CP 尽量一个入口。** 只有「同一契约的独立必要条件」才允许补一个 supplement；不为提高覆盖率拆成多条。
4. **改 CP 是规格变更。** AIFI-45 的历史 Gate 2 无指纹、CLI 无法补签，所以本次修订只能以「说明 + 人工批准」落地，不能由实施者直接改 canonical。

### CP-RUN-001（本次核查结论：当前不可整条验证）

按“入口必须与契约所在层一致”的标准，先尝试补真路由测试，核查后停止：

| 契约要求 | 代码事实 |
|---|---|
| 完整原请求与资源选择冻结、签发授权 | `execution_authorization_http.go:209–249` 可通过真实路由验证（201） |
| 自动执行、无重复阶段确认 | `runner.go:868–899`、`:1543` 仍读取独立的 `tech-design` 阶段审批，未复用 execution 授权 |
| 实际任务与 T receipt 匹配 | `execution_admission.go:172–178`：verdict ingest 未接线，`ControlWorker.ApplyTx` 无生产调用方 |

结论：**不新增 `TestTC_RUN_001`**。补 fixture 只会把“注入阶段审批 / 内部写 verdict”当成前置条件，等于用假前置把缺口盖住；只测 201 又会漏掉该 TC 的核心断言。RUN-001 在 M005 接线与跨阶段授权复用落地前，应以 UNVERIFIED 记录，而不是部分通过。

## 二、逐条修订建议

### CP-RUN-004（同 receipt 跨 run 及终态根，有/无显式 adoption 映射）

- 契约性质：dispatch root 的唯一性与 adoption，属治理层；HTTP 层只提供入队触发，无法观察「永久 key 仅一个根」「无映射不推进」。
- 建议入口：`go test ./internal/governance -run '^TestTC_RUN_004$' -count=1 -v`
- 补充（仅当需要证明并发唯一性时，二选一合并进主项，不新增编号）：`TestTC_RUN_004_DispatchRootAdoptionHasOneWinner`、`TestTC_RUN_004_DispatchRootAdoptionHoldsTheRootRowLock` 已作为子断言存在于同一文件，建议**不单独列 CP**，由主项覆盖。
- 残留（须写进 CP 的 note）：主项使用 fake enqueuer，未覆盖真实 TaskService 跨 run 入队。

### CP-RUN-005（Git 准入后 DB 前 / DB 提交后响应前故障）

- 契约性质：故障点恢复与有界子链，属治理层；故障注入点在治理代码，路由层不可见。
- 建议入口：`go test ./internal/governance -run '^TestTC_RUN_005$' -count=1 -v`
- 残留：故障 hook 不能证明真实 Git 与真实 T 扣额；恢复链的「不复活终态根」需以该测试实际断言为准，CP note 不得扩大表述。

### CP-RUN-007（四阶段唯一派发可恢复，不靠手敲命令或直接 walker）

- 契约性质：调度收敛与恢复，属治理层；`cmd/server` 只挂 `/api/daemon/cr-events` 与启动扫描。
- 建议入口（保持一条，取覆盖面更完整的那个）：
  `go test ./internal/governance -run '^TestMDispatch001$' -count=1 -v`
- 说明：`TestRunnerStartupAndEventWakeSourcesConvergeOnReconcile` 覆盖「启动扫描与事件唤醒收敛」，与四阶段派发是不同断言，**不另立 CP**；若人工认为两者都必须计证，则把它作为同一 CP 的 `and` 断言写入 note，而不是第二条命令。
- 残留：现有候选使用 fake enqueuer，未证明真实队列闭环。

### CP-RUN-008（legacy 活任务与未就绪新版本矩阵）

- 契约性质：版本/契约矩阵判定，跨 governance 与 daemon 两侧。
- 建议入口（二选一，不并列计证）：
  - 主项：`go test ./internal/daemon -run '^TestStrictExecutionContract' -count=1 -v`（覆盖 legacy、unsupported、ambiguous 三类判定）
  - 环境与降级联动的补充写入 note：`TestRunnerDigestMismatchIsRecoverableOnSameRun`（governance）
- 残留：缺切换、回退与历史保护的真实矩阵；该 TC 现为**部分覆盖**，CP note 必须如实标注，不得计为整条通过。

### CP-RUN-009（run/node/attempt/cycle/subject/template/policy/receipt/UUID 逐项漂移）

- 契约性质：投影与身份漂移，属治理层。
- 建议入口：`go test ./internal/governance -run '^(TestRequirementReviewRunsOnASeparateAgent|TestRequirementSameAgentForBothRolesIsRefused|TestRequirementDigestDriftKeepsRunResumable)$' -count=1 -v`
- 理由：三条分别覆盖「独立评审 Agent」「同 Agent 兼任被拒」「digest 漂移仍可恢复」，合起来才是该 TC 的必要条件；拆成三条 CP 会虚增分母。
- 残留：逐字段漂移（run/node/attempt/cycle/subject/template/policy/receipt/UUID）未逐项覆盖，CP note 须写明「部分覆盖」。

## 三、四条有限保证（修订后仍必须成立）

1. **入口真实**：每条 CP 指向的函数在冻结源码中真实存在；不存在不得以「同名补壳」充数。
2. **单次可复现**：证据来自该条命令在干净一次性库上的一次运行，事件流完整；零选中、全 skip、包失败都不算通过。
3. **层次诚实**：CP 的 note 必须写明覆盖层与残留；部分覆盖的 TC 不得报告整条通过。
4. **变更留痕**：任何 CP 改动都带理由、替代关系与残留，经人工批准后生效，不改写历史批准。

## 四、执行约定

- 修订只在人工批准后写入 canonical，并重签对应 Gate；本轮不预改。
- 证据一律通过 `scripts/aifi45-disposable/run-selection.mjs` 在每选择一个一次性库上取得，命令与选择文件同时留档。
- 不新增 TC 编号，不改变原有分母；不把组件测试当真实链路。

## 五、落地记录（2026-11-10）

- 已改 `canonical/specs/agent/authorized-runner.yaml`：五条 CP 的 `action` 指向上表入口；每条 `description` 追加「部分覆盖 + 残留」，明确按 meta 前置不得计为整 TC 通过。
- 同时把 harness 前置从已禁用的 `scripts/aifi45-db/run.mjs` 改为 `scripts/aifi45-disposable/run-selection.mjs`（每选择一次性库、nonce 命名 + `AIFI45_DISPOSABLE` 标记），旧入口明确不得运行或改向。24 条 CP 结构保持不变，YAML 解析通过。
- AIFI-45 的 Gate 2 属 `historical/unfingerprinted`，官方 CLI 无法补指纹，因此本次为「记录 + 用户批准」落地，不写 `.stdd.yaml`、不改写历史批准。
- **执行证据（2026-11-10，运行时恢复后补跑）**：本地镜像 `pgvector/pgvector:pg17`（`--pull=never`）、tmpfs、仅绑 127.0.0.1、每个 CP 独立一次性库，`run-selection.mjs` 单次跑完：

  | CP | 结果 |
  |---|---|
  | CP-RUN-004 | PASS 1 |
  | CP-RUN-005 | PASS 1 |
  | CP-RUN-007 | PASS 6 |
  | CP-RUN-008 | PASS 18 |
  | CP-RUN-009 | PASS 3 |

  五条全绿、0 skip；容器按 ID 删除并回读 label 计数为 0。首次跑 CP-RUN-007 时暴露一个真实夹具缺陷：`insertingPipelineEnqueuer` 把 `agent_task_queue.runtime_id` 写成固定常量，只有别的用例恰好播过该 runtime 行时才成立；已改为取执行 Agent 自身的 `runtime_id`（生产语义一致），改后同一干净库通过。
- 说明：本表结果只证明「入口已修正且可在干净库复现」，四条部分覆盖的残留（004/007 的 fake enqueuer、005 未证真实 Git/T 扣额、008 缺切换回退矩阵、009 缺逐字段漂移）仍未消除，故仍不得计为整 TC 通过。
