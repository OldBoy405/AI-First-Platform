# AIFI-45：准入按任务／generation 绑定消费事实 — 技术设计

## Context

当前 `DecideAdmission` 先要求 CR 的授权头为 `approve`，再按整个 CR 统计 consumption 与可信 effect，最后读取 CR 内最近一条 effect 调用 `VerifyTrustedVerdictEffect`；`AdmissionRequest.TaskID` 目前只是预留字段，不参与判断（`server/internal/governance/execution_admission.go:71-76,121-238`）。因此，同一 CR 中任意任务的 consumption 都可能为另一个动作提供准入依据，而且被计数的回执与被验证的 effect 不必属于同一任务。

M005 已提供本 change 所需的事实载体：

- consumption 回执按 `(workspace_id, cr_id, runtime_id, task_id, dispatched_at)` 唯一（`server/migrations/644_cr_execution_consumption.up.sql:8-22`）。
- 首次回执与 effect 在同一事务提交；重放返回 `200 changed=false`（`server/internal/governance/execution_consumption.go:204-234,242-263`）。
- command、verdict、settlement 都以 task id 为 `request_id`；同一 task 的新 generation 只新增回执，不重新签发 effect（`server/internal/governance/execution_consumption_effect.go:80-89,133-209`）。三张表也都以 `request_id` 保证每 task 一条记录（`server/migrations/648_cr_execution_control.up.sql:78-80,118-137,167-172`）。

Runner 的受保护写入统一经过 `decideUnderHeadLock`。该函数使用 `ReadCommitted`，先锁 `cr` 及当前授权记录，再调用 decider；节点状态写在同一事务提交，任务入队则在其连接上执行，但持续持有 `cr FOR SHARE`，以与撤销线性化（`server/internal/governance/execution_admission_gate.go:21-35,84-125`）。本 change 必须保留以下边界：

1. 不改 schema、迁移、路由、daemon、T/crctl，不改 consumption 路由与 effect 签发规则。
2. 不新增 admission reason；继续使用 `ADMITTED`、`WAIT_CONSUMPTION`、`WAIT_TRUSTED_T_COMMIT`、`HEAD_UNAVAILABLE`、`HEAD_REJECTED`。
3. 授权头、回执、当前 generation 与 effect 均在授权头锁后由 decider 读取；调用方只提供任务标识，不提供准入结论。
4. 不恢复 M005 前驱曾回退的“当前 command 再加前驱 settlement”规则；只使用当前锚点 task 自己的 effect。
5. 不新增 wake。真实发现仍是 `ResumeActiveRuns → StartupScan + StartupScanRequirement`（`server/internal/governance/runner.go:1825-1830`），由启动扫描和 30 秒 sweeper 调用（`server/cmd/server/router.go:1642-1653`、`server/cmd/server/runtime_sweeper.go:27,211-236`）。
6. 真实数据库只使用 supervisor 通过 `scripts/aifi45-disposable` 创建的一次性实例；不接触 `multica-postgres`、`multica-backend`、既有 `aifi45-disposable` 或任何未核实归属的容器和数据库。
7. Go 注释使用英文；按 `CUSTOM.md` 的 M27 现行结构登记，不编造 CR 编号。

拟修改的产品文件仅为：

- `server/internal/governance/execution_admission.go`
- `server/internal/governance/execution_admission_gate.go`
- `server/internal/governance/runner.go`
- `server/internal/governance/runner_requirement.go`

`runner_code.go` 的 code/writeback 路径复用上述共用 gate，无需另建一套判定。测试、一次性库 selections 与 `CUSTOM.md` 按后述清单调整。

## Decisions

### 1. `TaskID` 成为强制锚点，decider 只接受“当前 task 行的当前 generation + 该 task 自己的 effect”

**方案**：

保留现有请求校验和授权头判断，删除按 CR 计数及 `ORDER BY settled_at … LIMIT 1` 的两段查询，按以下顺序实现。

1. 校验 `tx`、`Intent`、`WorkspaceID`、`CRID` 后，必须解析 `TaskID`。空字符串、非 UUID、 nil transaction、未知 intent 均返回 `ErrAdmissionInvalid`。这是调用方错误，不转换成等待原因。
2. 沿用现有 CR/head 查询：
   - CR 不存在：`ErrAdmissionInvalid`；
   - 无授权头：`HEAD_UNAVAILABLE`；
   - 非 `approve`：`HEAD_REJECTED`。
3. 在同一个由 `decideUnderHeadLock` 提供的事务内读取锚点 task 的当前行，并用当前列值匹配回执。SQL 形状如下；`$1=workspace_id`、`$2=cr_id`、`$3=task_id`：

   ```sql
   SELECT t.runtime_id, t.dispatched_at, cc.id IS NOT NULL
   FROM agent_task_queue t
   JOIN agent a
     ON a.id = t.agent_id
    AND a.workspace_id = $1::uuid
   LEFT JOIN cr_execution_consumption cc
     ON cc.workspace_id = $1::uuid
    AND cc.cr_id = $2
    AND cc.task_id = t.id
    AND cc.runtime_id = t.runtime_id
    AND cc.dispatched_at = t.dispatched_at
   WHERE t.id = $3::uuid
   ```

   `JOIN agent` 用于 workspace 隔离，但不要求 `t.cr_id = req.CRID`，因为授权入口 source task 合法地可以有 `cr_id=NULL`；`checkSourceTask` 只拒绝“非空且不同的 CR”（`server/internal/governance/runner.go:1209-1240`）。唯一约束保证匹配的 generation 至多一条回执，因此无需 `ORDER BY` 或 `LIMIT`。

4. 锚点行不存在、所属 workspace 不匹配、`runtime_id` 或 `dispatched_at` 为 NULL、当前 generation 无回执，均返回 `WAIT_CONSUMPTION`。这也覆盖：
   - 只有旧 `dispatched_at` 的回执；
   - `runtime_id` 相同但 generation 不同，或 generation 相同但 runtime 不同；
   - 只有另一个 task 的回执；
   - 同一 task 但只有另一个 CR 的回执。
5. 有当前回执后，只按锚点 task id 读取 effect、verdict、cursor 和 command：

   ```sql
   SELECT v.payload_bytes, cmd.command_bytes, v.store_id, v.lineage_id::text
   FROM cr_execution_control_settlement s
   JOIN cr_execution_tool_verdict v
     ON v.id = s.verdict_id
    AND v.request_id = s.request_id
   JOIN cr_execution_tool_cursor c
     ON c.lineage_id = v.lineage_id
    AND c.store_id = v.store_id
    AND c.epoch = v.epoch
   JOIN cr_execution_control_command cmd
     ON cmd.request_id = s.request_id
   WHERE s.request_id = $3::uuid
     AND s.kind = 'effect'
     AND c.last_seq >= v.seq
   ```

   不再从 `cr_execution_consumption` 横向选择“最近 effect”。`request_id` 的唯一性使该查询至多命中一条任务链。
6. 查询无行，或 `VerifyTrustedVerdictEffect(payload, {"store_id": storeID, "lineage_id": lineageID}, commandBytes)` 失败，返回 `WAIT_TRUSTED_T_COMMIT`。继续保留 `cursor.last_seq >= v.seq`，不比较 verdict digest 与 cursor tail digest，避免后续合法 frame 使既有消费失效。
7. 全部满足后返回 `Allowed=true, ADMITTED`。其他数据库错误继续向上返回，不伪装成等待。

**结果映射表**：

| 条件 | 结果 |
|---|---|
| `TaskID` 空或 malformed | `ErrAdmissionInvalid` |
| 授权头缺失 / 非 approve | `HEAD_UNAVAILABLE` / `HEAD_REJECTED` |
| 锚点 task 行不存在或不在本 workspace | `WAIT_CONSUMPTION` |
| `runtime_id` / `dispatched_at` 为 NULL | `WAIT_CONSUMPTION` |
| 只有旧 generation、他 task、他 CR 回执 | `WAIT_CONSUMPTION` |
| 当前回执存在，但 effect/verdict/cursor/command 不完整 | `WAIT_TRUSTED_T_COMMIT` |
| `VerifyTrustedVerdictEffect` 拒绝 | `WAIT_TRUSTED_T_COMMIT` |
| 当前回执和该 task 的完整可信 effect 均存在 | `ADMITTED` |

**注释同步（C6）**：`execution_admission.go` 中「仍按 CR 计数而非 generation（RUN-006 resume 才命名 generation）」的 ponytail 注释及所有按 CR 描述的说明随本改动改写为按锚点 task 与当前 generation 的现状；同步登记 `CUSTOM.md`，不遗留与实现相反的注释。

**关键关联规则**：当前回执与 effect 通过 **task id** 关联，不要求 `settlement.effect_ref.receipt` 等于当前回执 id。M005 中 effect 指向首次回执；同一 task 新 generation 不重新签发 effect，如果按当前回执 id  join，会错误拒绝合法的新 generation。

**为什么**：

该算法同时关闭三种借用：CR 内他 task、他 CR、同 task 的旧 generation。它还保证被验证的 effect 与回执属于同一 task，而不是 CR 内任意最新记录。

**备选方案及排除原因**：

- 继续 CR 级计数，只额外检查某个 task 有回执：仍可能让回执与 effect 分属不同 task，排除。
- 恢复“当前 command + 前一 seq settlement”的前驱规则：与 M005 回退决定冲突，且不能表达 `seq=1` 的首次消费，排除。
- 以当前 receipt id 连接 `effect_ref`：破坏同 task 新 generation 不重复签发的 M005 合同，排除。
- 新增 `WAIT_GENERATION`、`WAIT_ANCHOR` 等原因：提案明确封闭 reason 集合，且没有必要，排除。

### 2. 调用方按各自快照给出锚点；准入事实在头锁内读取

**方案**：

`decideUnderHeadLock(ctx, workspaceID, crID, taskID)` 的签名与锁序不变（`BeginTx(ReadCommitted) → lockExecutionAuthorizationHead → DecideAdmission`），只要求每个调用方传入非空 `taskID`。不引入锚点解析器，不改锁序，不改 `AdmissionRequest`。

各调用方的锚点来源：

- `markNodeAdmitted`：已有的锁前查询补读 `pipeline_run.execution_context`；节点有当前选中任务（`selectedTask`）则用其 id，否则用 run 的 `source_task_id`。
- `passHumanApprovalNode`：用 run 的 `source_task_id`，不看 human 节点是否意外挂了 task。
- `enqueueNodeFor`、`enqueueRequirementNode`：用调用前已从 `run.ExecutionContext` 解析出的同一个 `sourceTaskID`（`runner.go:1071`、`runner_requirement.go:614`），既作准入锚点，也作 `PipelineTaskSpec.SourceTaskID`。
- 一个小 helper `runSourceTaskID(execCtx []byte) (string, error)` 解析 source，供 `markNodeAdmitted` 与 `passHumanApprovalNode` 使用；字段缺失或不是合法 UUID 时返回 `errCode(RunnerErrAuthorityMismatch, …)`，沿用现有两处入队路径的文案语义（`runner.go:1065-1074`、`runner_requirement.go:609-617`）。
- `decider == nil` 的 legacy 行为不变；`markNode("blocked")` 仍不走 admission（`runner.go:1557-1567`）。

**头锁保护什么、不保护什么**：

头锁串行化的是授权头（撤销）、consumption 回执，以及与回执同事务写入的 effect 链——consumption 路由同样先取该锁（`execution_consumption.go:106`）。decider 在锁内读取这些事实，所以 EXP-2026-0002 要求的“先序列化、再读守卫”对它们成立。

锚点 task id 本身（节点最新任务、run 的 `source_task_id`）是调用方的任务行快照，不受头锁保护：需求重入会经 `recordRequirementRunContext` 覆盖 `source_task_id`（重入持分配锁，reconcile 持 run 锁，二者不互斥），retry 任务的创建也不取头锁。因此“锁后重读锚点”不增加任何保证。一个略旧的快照等价于决策发生在该变更之前，并不授予新权限：放行永远只依据所锚 task 自己的当前回执与自己的 effect。唯一需要保持的不变量是：**准入锚点与入队归因取同一个值**（入队路径用同一个 `sourceTaskID` 变量）。这与既有“入队与 decider 不同事务”的边界同类，作为非原子边界接受并记录；不增加 task 行锁，也不反转既有 `task → runtime → CR head` 锁序（`execution_claim_lock.go:20-27,33-40`）。

**为什么**：

锚点规则集中在共用 gate 与几个调用点，architecture、requirement、code、writeback 不会各自漂移；锁序与现有撤销线性化保持原样。

**备选方案及排除原因**：

- 解析器 + 锁后重读锚点：任务行不受头锁保护，不增加保证，只增加抽象与测试面，排除（Gate 2 修订，ADJ-001）。
- 为“锁等待期间新 retry / source 变化”补锁交错测试：旧快照与“决策先发生”等价，不是可验证的保证；撤销互斥已由既有 `TestAdmissionGateLockBlocksRevocation` 固定，排除（ADJ-003）。
- 所有动作统一锚定 source：会把一次入口消费变成整条 run 的通用授权，违背 Gate 1 已批准的严格完成语义，排除。
- 给 `AdmissionRequest` 增加 run/node/attempt 字段：会把 Runner 解析职责泄漏给通用 decider，排除。
- 新增 task 行锁或全局调度锁：扩大锁面和死锁风险，超出已批准的锁纪律，排除。

### 3. 每个受保护动作的锚点表固定如下

“own-task”始终指该节点当前 `selectedTask`；没有 own-task 时才回退到 run source。人工门与两条派发路径不尝试 own-task。

| Pipeline / 动作 | 受保护调用点 | 锚点 | 理由 |
|---|---|---|---|
| Architecture 节点派发 | `runner.go:774,810,904` → `reconcileSkillTaskFor` → `enqueueNodeFor` 的 gate（`runner.go:1000-1010,1083`） | source | 节点任务尚未创建，要求它先消费会形成循环 |
| Architecture re-review 跳过 writer | `runner.go:769` | own-task；通常无，故 source | 复用/跳过 writer 时不伪造新任务消费 |
| Architecture writer / review / approve passed | `runner.go:806,859,941` | own-task；无则 source | 完成实际节点工作必须有该工作自己的消费证据；投影/跳过例外回退 source |
| Architecture human gate | `runner.go:899` | source | human 节点没有执行任务 |
| Requirement 节点派发 | `runner_requirement.go:157,176,264` → `reconcileRequirementNode` → `enqueueRequirementNode`（`:524-582,682`） | source | 同 architecture，首次及后续派发均不能要求未创建任务的消费 |
| Requirement round-path writer/checkpoint passed | `runner_requirement.go:164` | own-task；无则 source | 按当前实际工作绑定 |
| Requirement review passed | `runner_requirement.go:215` | own-task；无则 source | 已有投影 review evidence 时可无 own-task（`:174-183`），此时用 source |
| Requirement human gate | `runner_requirement.go:250` | source | human 节点无执行任务 |
| Requirement approve passed | `runner_requirement.go:283` | own-task；无则 source | 同上 |
| Code 节点派发 | `runner_code.go:111,118,125,162,172,441,487,494,520,530`，共用 `enqueueNodeFor` | source | 与 architecture 共用同一首次派发规则 |
| Code planReview/finalize/freshness/test/fresh/review/approve passed | `runner_code.go:158,169,179,517,527,556,461` | own-task；无则 source | 完成类动作按节点实际任务绑定 |
| Code human gate | `runner_code.go:437` | source | 无执行任务 |
| Writeback merge/后续节点派发 | `runner_code.go:341,381`，共用 `enqueueNodeFor` | source（从 code run 复制） | 首个 writeback 任务创建前不能要求自身消费 |
| Writeback merge/后续节点 passed | `runner_code.go:376,388` | own-task；无则 source | 与共用完成规则一致 |

`ensureWritebackRun` 本身不是新增受保护动作，沿用现有 gate 注释范围；它只负责 run handoff 和 source 拷贝（`runner_code.go:274-315`）。run completion 也不新增 gate。

**source_task_id 的实际来源与边界**：

| Run kind | source 是否携带 | 证据及结果 |
|---|---|---|
| Architecture `StartArchitecture` | 是 | 由现有 `X-Task-ID` 对应的 task 写入（`runner.go:595-616,1886-1898`） |
| Requirement `StartRequirement` | 是 | 同样由 task-token 身份写入（`runner_requirement_entry.go:82,106-110,325-337`） |
| Architecture re-review | 是，但语义特殊 | 选择最新 code run 中、该 CR 最新 completed task（`runner.go:663-678`）。它不是“最新有回执任务” |
| Code | 测试 fixture 有；生产 projector 没有保证 | 测试 `seedCodeRun` 手工写入（`runner_code_test.go:12-25`）；生产 projector 的 `INSERT pipeline_run` 不写 `execution_context`（`gate_projection.go:139-168`）。不能把测试 source 当成生产能力证明 |
| Writeback | 从 code run 复制 | `runner_code.go:282-294`。缺字段时现有 `COALESCE` 会产生零 UUID；零 UUID 虽能解析，但 decider 查不到锚点 task，最终 `WAIT_CONSUMPTION` |

Architecture re-review 的 source 可能从未消费、只有旧 generation 回执，或没有自己的 effect。此时 `runner.go:769` 的跳过 writer 必须停在 `WAIT_CONSUMPTION` 或 `WAIT_TRUSTED_T_COMMIT`，不能继续找较早的 completed task，也不能借用 CR 内其他 effect。这是严格、可解释的 fail-closed 结果。

**备选方案及排除原因**：

- 每个调用点自行决定“取 CR 内任意/最近任务”：会重新引入借用且各 pipeline 易漂移，排除。
- re-review 改为“最新有可信回执的 completed task”：改变既有 source/attribution 规则并掩盖生产者缺口，排除。
- 人工门也锚定 human 节点任务：human 节点没有执行任务，无可靠锚点，排除。

### 4. 首次派发以 source 打破循环；节点完成后才要求节点自己的消费

**方案与时序**：

1. 授权入口 source task 不是 Runner 创建的。只有触发评论声明 execution contract 的任务才走 daemon strict preflight；该 preflight 在 agent 启动前完成 consumption（`server/internal/daemon/execution_verifier.go:26-48,101-110,184-217`，调用点为 `daemon.go:5808-5811`）。因此典型 source 在调用 `StartArchitecture` / `StartRequirement` 前已经可以持有回执。
2. Runner 创建的节点任务没有触发评论，不走 strict preflight。`CreatePipelineTask` 的插入列不包含 `trigger_comment_id`（`pkg/db/queries/agent.sql:617-699`）。节点 agent 若经 binding endpoint 取得证明，daemon 在 run 结束的 defer 中记录 consumption（`daemon.go:8765-8775`）。
3. 因而：
   - **首次及后续 enqueue**：只要求 source 当前回执和 effect，绝不要求待创建节点任务的回执；
   - **节点 passed**：节点已执行并产生 task 后，才要求该 task 当前 generation 的回执和 effect；
   - **无 own-task 的 passed**：沿用 source；
   - **human gate**：source 已有消费，加上实际 delivered approval 后才可通过。
4. 对每个动作，“最早可 admitted”是：锚点回执与 effect 已在真实路由提交，且该动作原有的业务前置条件已满足，随后发生一次 Reconcile/discovery。路由提交本身不直接执行业务动作。

**为什么**：

首次派发若绑定节点任务，会要求“先消费一个尚不存在的任务”；统一 source 又会削弱完成证据。own/source 分离与现有 daemon 时序一致。

**备选方案及排除原因**：

- 给所有节点任务增加 strict preflight：需要改 daemon/T 和 Runner 任务形态，属于明确 non-goal，排除。
- 节点完成也接受 source：掩盖节点没有取得证明或 deferred consumption 失败的情况，排除。
- 为 consumption 提交后直接调用 Reconcile：新增 wake，扩大 change，且不能代替启动/周期发现验证，排除。

### 5. Retry、review-loop、re-walk 的锚点随当前任务解析，既有唯一性负责不重复派发

**方案**：

- 同一 task 被重新认领：generation 是当前 `(runtime_id, dispatched_at)`。旧回执失效；新回执通过真实路由写入后恢复准入，effect 仍复用该 task 已有链。
- 技术 retry 创建新 task 行，并继承 `parent_task_id/retry_of_task_id`、CR、project 和 `pipeline_node_run_id`（`pkg/db/queries/agent.sql:500-504,569-614`）。新 task 成为 newest 后，完成动作必须以新 task 为锚点；父 task 的 consumption 不能放行子 task。
- review-loop/re-walk 每次重新调用 `markNode(passed)` 时重新解析当前 newest。重复判定是只读的，节点 UPDATE 幂等，不由 admission 创建任务。
- 重复 discovery 不重复派发，继续依赖既有四层机制：
  1. per-run advisory lock（architecture：`runner.go:700-744`；requirement：`runner_requirement.go:28-55`）；
  2. active run 唯一索引（`server/migrations/590_pipeline_run_architecture_active_unique.up.sql:13-15`）；
  3. `(run_id,node_id,attempt)` 唯一（`server/migrations/585_aifirst_pipeline_runs.up.sql:32-49`）；
  4. 每 node-run 至多一个 active task 的部分唯一索引（`server/migrations/591_agent_task_pipeline_node_active_unique.up.sql:14-17`），以及 `CreatePipelineTask` 的 `ON CONFLICT DO NOTHING` 和 winner re-read（`server/internal/service/task.go:402-454`）。
- “已经 passed 的节点后来被人为插入新 retry”不是重新打开节点的授权。walker 按现有状态机处理；本 change 不增加 status regression 或自动取消 retry 的逻辑。

**为什么**：

锚点规则在 retry 下稳定，但具体 task id 不应永久固定。队列状态与唯一索引才是防重复派发的事实源，consumption 不是去重键。

**备选方案及排除原因**：

- 永远使用节点首个 task：retry 子任务可借父任务消费，排除。
- 用 consumption 是否存在来抑制重复 enqueue：合法重复 wake 不是新工作，且会把发现与业务授权混在一起，排除。
- 新 generation 重新签 effect：直接违反 M005，排除。

### 6. 真实验证放在 `governance_test` 复用路由 fixture；内部动作测试留在 `governance`

**方案**：

三个测试文件，各自只承担一种责任：

1. `server/internal/governance/execution_admission_task_decider_test.go`，`package governance`（TC-ATB-001～004，已实现）：decider 的 task/generation/effect 组合。
2. `server/internal/governance/execution_admission_task_binding_test.go`，`package governance`（TC-ATB-005～007）：
   - 四类动作及 no-own-task fallback；
   - retry 子用例，以及 source context 缺失/畸形的错误。
   这些测试必须调用未导出的 `markNode`、`enqueueNodeFor`、`enqueueRequirementNode`、`passHumanApprovalNode`，因此放在内部包。
3. `server/internal/governance/execution_admission_task_discovery_test.go`，`package governance_test`（TC-ATB-008～010）：
   - 复用 `bindingIssueFixture`、`taskClaimHarness`、`ceConsume`、`ceCounts` 等真实路由资产（`execution_binding_issue_test.go:52-192`、`execution_task_claim_project_test.go:31-137`、`execution_consumption_effect_test.go:23-174`）。
   - 使用 `governance.NewRunnerWithOptions` 和真实 `service.TaskService`，调用公开 `StartArchitecture` / `StartRequirement` / `ResumeActiveRuns`，无需为测试导出 Runner 内部函数。

**真实串联 fixture 必须补足的条件**：

`bindingIssueFixture` 已提供真实 generation、授权头、daemon token、binding/consume 路由，但不会自动提供 Runner 可派发条件。测试 helper 必须：

- 给 source task 补 `originator_source`、`originator_user_id`、`accountable_user_id`、trigger evidence，以满足 `CreatePipelineTask` 的归因守卫（`pkg/db/queries/agent.sql:637-656`）；
- 从导出的 architecture/requirement registry JSON 解析 executor 和 skill ref，创建 runtime-bound executor agents 并启用对应 skills；不能用“executor 不存在”制造假的零派发；
- architecture 子例把 CR 置为 `requirement-approved` 后启动，requirement 子例置为 `drafting` 后启动；
- 统计任务时通过 `pipeline_node_run_id JOIN pipeline_node_run AND run_id=<target>`，不能把 source task 本身计入节点任务数；
- 两次 `ResumeActiveRuns` 之外检查 run 状态、wait reason 与任务身份，不能把 nil error 当作已推进的证据（单个 reconcile 错误只被记录日志）。

**架构与 requirement 共用的首次派发阶段（TC-ATB-008）**：

1. 在无 source 回执时调用 `StartArchitecture` 或 `StartRequirement`。run 创建成功，首节点形成 `WAIT_CONSUMPTION`，目标 run 的节点任务为 0。
2. 经真实 binding + consumption 路由为 source 提交，断言 `201 changed=true`。
3. 不调用任何 wake，直接查库：仍无节点任务，证明路由提交不隐式派发。
4. 第一次 `ResumeActiveRuns`：目标 run 恰有 1 个首节点任务，且 node/task 归属正确。
5. 第二次 `ResumeActiveRuns`：任务行数、节点行数及首任务 id 均不变。

**节点自有任务的完成阶段（TC-ATB-009，architecture）**：

1. 首节点任务 T1 已在上一阶段入队；将其按真实 claim 形状置为 running（非 NULL `runtime_id/dispatched_at/started_at`），并把 CR 置为 `tech-design-review-pending`。
2. 把 fixture 的 task 身份切到 T1，在 T1 仍 running 时经真实 binding + consumption 路由提交，断言 `201 changed=true`。这与 daemon“退出时 defer 消费、随后才报告完成”的真实顺序一致；`GetExecutionBindingClaim` 只接受 `dispatched/running/waiting_local_directory`，已 completed 的任务不能再补消费。
3. 将 T1 置为 completed 并运行发现：首节点 passed；review 的派发仍由 source 准入，不要求 review task 预先消费；再次发现不产生新任务或状态变化。

“T1 完成但没有自己的回执则不放行”由 TC-ATB-005 在内部包验证，不在真实路由层构造（该顺序在真实路由下不可达）。

**同 task 重放与新 generation（TC-ATB-010）**：不经 Runner，直接用 `bindingIssueFixture` 的 source task 与 `ceConsume`/`ceCounts`：

1. G1 经真实路由 `201`；同 generation 重放 `200 changed=false`，回执、command、verdict、settlement 行数不变。
2. 把该 task 的 `dispatched_at` 推进到新值（模拟重新认领的数据库效果，task 行仍是合法 claim 形态），重签 binding；提交前以 `DecideAdmission` 判定 `WAIT_CONSUMPTION`（旧回执不放行）。
3. G2 提交 `201`：回执 +1，command/verdict/settlement 均 +0，判定恢复 `ADMITTED`。

**为什么**：

这是 M005 遗留的“真实 consumption → 发现 → 推进”缺口的最小闭环。它证明无 wake、source 首次派发、节点自身消费后推进、重放与新 generation，而不是仅测私有 SQL helper。

**备选方案及排除原因**：

- 在 `cmd/server` 重写一套大 router fixture：无法复用 `bindingIssueFixture`，重复且容易漂移，排除。
- 全部放在内部 `package governance`：无法访问外部测试包的未导出路由 fixture，排除。
- 继续用直接种回执 + `WakeGrant` 代替真实串联：不能证明真实路由、无 wake 和周期发现，排除。
- architecture 与 requirement 都完整跑完整条 pipeline：重复且扩大验证面；首次发现两者表驱动覆盖，节点自身消费只在 architecture 验证即可，排除。
- 先把任务置 completed 再走真实路由补消费：路由按状态拒绝，且与生产顺序相反，排除（ADJ-002）。

### 7. 既有测试只改“哪个 task 被消费”，不削弱断言

**方案**：

按 `DecideAdmission|NewAdmissionDecider|admitTrustedConsumption|admitPlatformConsumption` 与 `cr_execution_consumption` 的 grep 结果，影响清单如下。

| 文件 | 当前假设 / 用法 | 必须调整 |
|---|---|---|
| `server/internal/governance/execution_admission_test.go` | request 无 TaskID；回执使用随机 runtime 和独立 `now()`（`:29-31,176-188`） | 创建带当前 generation 的锚点 task；request 填其 id；helper 从 task 行读取 runtime/dispatched_at。保留全部 head、settlement、verdict、cursor、tail 前进断言，并增加逐条错配反例 |
| `execution_consumption_effect_test.go` | `ceAdmission` 不传 TaskID（`:23-39`） | 传 `f.task.taskID`；TC-CE-004 在新 generation 消费前增加旧回执 `WAIT_CONSUMPTION`，提交后恢复 `ADMITTED`；原有链形状与行数断言不减弱 |
| `execution_admission_gate_test.go` | run 无 source，节点无 own-task；随机 task 消费；重复插入回执（`:113-117`） | 正例使用节点 own-task；另设 no-own-task/source 用例。删除外层 `admitPlatformConsumption` 重复调用，保留节点状态与 wait 断言 |
| `execution_admission_enqueue_test.go` | source UUID 没有 task 行；随机 task 消费；重复插入（`:64-75,150-151`） | 创建真实 source task/generation，消费 source 而不是随机 UUID；增加“他 task 完整消费仍不入队” |
| `execution_admission_requirement_enqueue_test.go` | source task 存在但 `dispatched_at=NULL`；随机 task 消费；重复插入（`:127-136,202-203`） | 给 source 固定非 NULL generation 并消费 source；counting enqueuer 与真实 `TaskService` 的正反断言全部保留 |
| `execution_admission_human_gate_test.go` | run 无 source；随机 task 消费（`:46-55,158-176`） | 创建真实 source 并写入 run context；source 正例和他 task 反例分别覆盖；legacy/no-decider 与 terminal row 断言不变 |
| `execution_admission_lock_test.go` | 以空 TaskID 调用 gate（`:160`） | fixture 提供有效锚点 task，保持无回执的等待结果；继续要求独立连接只以 SQLSTATE `55P03` 证明锁冲突 |
| `execution_admission_cleanup_test.go` | 自定义 panic decider，空 TaskID（`:74`） | 传固定合法 task id；panic 后释放锁的断言不变，不需要真实回执 |
| `execution_admission_failure_branch_test.go` | 自定义 decider 控制特定分支（`:28-45`） | 接口不变；确保 fixture 的 run 带有可用的 source id。不得把拒绝分支改成等待以外的结果 |
| `runnerquery_test/admission_cleanup_test.go` | AST 检查 cleanup/lock/decide 顺序（`:128-170`） | 锁序与结构不变，预期无需改动；仅当结构确有变化时才更新 AST 预期 |
| `admissionguard_test/decider_test.go` | 只验证 nil/typed-nil dependency guard | 无需改语义；接口保持 |
| `server/cmd/server/execution_run_003_test.go` | 随机 `consumptionTask`（`:332-339`），source 无 `dispatched_at`（`:174-178`） | `consumptionTask = sourceTaskID`；source 写入固定非 NULL generation，回执精确复用其 runtime/dispatched_at。五个阶段、伪造 verdict、真实 writer、归因和二次 wake 不重复断言全部保留 |
| `runner_periodic_resume_test.go` | 验证并发/重复 discovery 与 retry 唯一性 | 产品 fixture 不改；复用其 run/task 计数方式支撑 TC-ATB-005/008 |

**其他 grep 命中但不需改变语义的文件**：

- `server/cmd/server/execution_run_002_test.go:78`：仅清理表，无 CR-level admission 断言，不改。
- `server/internal/daemon/execution_control_recovery_d8_test.go:157-204`：验证恢复时保留历史回执，不调用 decider，不改。
- `execution_channel_binding_test.go:52`、`execution_consumption_test.go:41,180-184`、`execution_consumption_adversarial_test.go:302`、`execution_tc_auth_test.go:113`：验证路由/回执计数与 append-only，不改。
- `execution_channel_reader_test.go:176-199`：channel reader fixture，不走 Runner admission，不改。
- `execution_control_migration_test.go:281,596-657`、`execution_migration_roundtrip_test.go:18,33`：schema/迁移保护，不改。
- `execution_consumption_effect_test.go` 的其他链断言：除上述 TaskID 与旧 generation 补充外不改。

特别注意：`execution_admission_gate_test.go`、`execution_admission_enqueue_test.go`、`execution_admission_requirement_enqueue_test.go` 目前都先调用 `admitPlatformConsumption`，随后调用本身已含回执写入的 `admitTrustedConsumption`。新 helper 必须消除这种重复写入，不能靠制造多个 generation 让测试碰巧通过。

**总规则**：fixture diff 只能改变被消费的 task 身份、必要的真实 task/generation 行及新增的错配反例；不得删除队列计数、节点状态、wait reason、验签、归因、链行数或幂等断言，不得新增 skip。

**备选方案及排除原因**：

- 继续保留随机消费 task，再给 decider 增加兼容回退：直接保留被本 change 删除的借用行为，排除。
- 将难改的真实 DB 测试换成 mock decider：会失去 task 行、generation、唯一约束和锁证据，排除。
- 通过减少断言或 skip 维持旧 fixture：掩盖语义收紧造成的真实破坏，排除。

### 8. 明确保留的残余风险与 non-goals

**方案**：以下项目均不通过放宽锚点规则解决，并在交付证据中明确标为未覆盖。

1. **不比较 receipt.grant_digest 与当前 head digest**。decider 只确认当前 head 是 approve，以及回执属于当前 task/generation。授权头被另一个 approve supersede 后，旧回执是否仍可准入沿用现状，不在本 change 扩展；若需按 revision 重新消费，应另立 change。
2. **生产节点任务可能永远没有 consumption**。节点不走 strict preflight，只有实际取得 binding proof 后 daemon defer 才记录；未取证明或记录失败时，节点完成处等待是预期的 fail-closed，不得回退 source。既有 `detail.runner.wait_reason=admission` 与 admission reason 保留。生产者修复属于 daemon/T 的后继 change。
3. **不为 consumption、binding issue、execution ACK 新增 wake**。execution stage 在 ACK continuation/wake 组装中被排除（`server/internal/governance/approval.go:621-628`）；只能依赖 CR 更新、task completed/failed、非 execution ACK 或周期发现。
4. **不补 code run 的生产启动与周期发现**。`ResumeActiveRuns` 只扫描 architecture 和 requirement。code/writeback 共用 gate 获得同一规则，但不做端到端可达性声明。
5. **code/writeback 缺 source 的现存边界不修补**。缺字段的 dispatch 返回 `RUNNER_AUTHORITY_MISMATCH`；writeback 零 UUID 锚点则查无 task 并等待。不得改从 CR 任意任务猜 source。
6. **不回填历史 task/receipt/effect**。缺 task 行、缺 generation 或历史回执无 effect时继续等待。
7. **不扩大锁承诺**。enqueue 与 decider 仍非同一数据库事务；保证仍是现有 head-lock 对撤销的线性化及队列唯一性，不声称覆盖所有恢复、崩溃和并发 generation 形态。
8. **不改变信任根模型**。`VerifyTrustedVerdictEffect` 继续依赖写时验签及不可变 payload 的前提（`execution_verdict_trust.go:4-16,49-80`）；本 change 不新增 manifest provenance、T verdict ingest 或链恢复证明。

**备选方案及排除原因**：

- 用 source 为节点完成兜底、给 consumption 增加 wake、顺便补 code scanner：都会扩大已批准范围并掩盖生产者问题，排除。
- 在本 change 同时比较 grant digest、迁移历史数据：会改变授权 revision 语义并需要迁移/回填设计，排除。

## Architecture

```text
授权入口 source（strict preflight）             Runner 节点任务（非 strict）
 daemon consumeClaimedExecution                 agent 经 binding endpoint 取证明
              │                                          │
              └──────────────┬───────────────────────────┘
                             ▼
        POST /api/daemon/crs/{crID}/execution-authorization/consumption
        HandleDaemonExecutionConsumption
          tx: claim/runtime locks → CR head lock → 重验 binding proof
          INSERT cr_execution_consumption
            key = (workspace, cr, runtime, task, dispatched_at)
             │
             ├─ replay → 200 changed=false，不写 effect
             └─ first receipt → issueConsumptionEffectTx
                  request_id = task id
                  command + verdict + effect settlement
                  同 task 已有 consumption effect → 新 generation 只留回执
                             │
                          COMMIT / 201
                             │
                       不发布 event / wake
                             │
        CR updated / task completed|failed / 非 execution ACK
        boot scan / 30s runtime sweeper
                             │
                             ▼
                  ResumeActiveRuns
                    ├─ StartupScan（architecture）
                    └─ StartupScanRequirement
                             │
                             ▼
               Reconcile / ReconcileRequirement
               per-run advisory lock + 读取实际状态
                             │
          ┌──────────────────┼────────────────────┐
          ▼                  ▼                    ▼
     markNode(passed)   human gate          enqueueNodeFor /
          │             passHumanApprovalNode enqueueRequirementNode
          │                  │                    │
          └──────────────────┴────────────────────┘
                             ▼
              decideUnderHeadLock（ReadCommitted）
                lockExecutionAuthorizationHead
                             │
                TaskID 由调用方按其快照给出
                 own newest task 或 run source
                             │
                DecideAdmission(TaskID mandatory)
                  1. current head = approve
                  2. anchor task 当前行 + 当前 generation receipt
                  3. 按 request_id=TaskID 读取 settlement/verdict/cursor/command
                  4. VerifyTrustedVerdictEffect(payload, scope, commandBytes)
                  5. 形成 ADMITTED 或既有等待原因
                             │
              ┌──────────────┴───────────────┐
              ▼                              ▼
           Allowed                        Refused
              │                              │
     节点 UPDATE 随 tx.Commit          rollback 后写 waitAdmission
     enqueue 在 head lock 持有期间执行   errAdmissionWaiting
              │                              │
              ▼                              ▼
     后续 wake 读取持久化状态          公开 Reconcile 返回 nil，run 保持 active
```

拒绝路径不置 `passed`、不通过人工门、不入队；重复 discovery 仍由现有 advisory lock、node-run 与 active-task 唯一性防止重复副作用。

## Risks / Trade-offs

| 风险 | 影响 | 缓解措施 |
|---|---|---|
| 生产节点任务未取得 proof，永远不产生 consumption | 节点完成处永久等待；这是预期的 fail-closed，不得借 source 放行 | 保留 `wait_reason=admission` 和稳定 reason；architecture/requirement 依赖既有发现。修复 daemon/T 的证据生产另立 change。静态核对：回执唯一产生路径是节点 agent 经 `crctl` 控制操作（如 `advance`，节点 skill 均要求调用）从 `MULTICA_EXECUTION_BINDING_ENDPOINT` 取证明，daemon 在 agent 退出的 defer 中写回执（`daemon.go:8765-8775`）；未经真机验证。**上线前置（用户 2026-11-11 同意）**：部署到会跑真实架构/需求 run 的环境之前，须在真实 daemon + 真实 agent 上跑一条架构 run，确认节点任务的回执出现且节点可推进；未做前不部署。本 change 不授权部署，该条写入 DELIVERY 待办 |
| Architecture re-review 的 source 是该 CR 最新 completed task，可能没有回执或只有旧 generation | 跳过 writer 时不能进入 review | 停在 `WAIT_CONSUMPTION` / `WAIT_TRUSTED_T_COMMIT`；不得改选较早任务或任意 CR 消费 |
| Code run 没有周期发现，生产 projector 也不保证 `source_task_id` | code/writeback 的端到端可达性未证明；缺 source 时可能报错或等待 | 仅让共用 gate 获得同一规则；不补 scanner、不猜 source、不声明 code E2E 覆盖 |
| 锚点 task id（最新节点任务、run 的 source）是调用方快照，并发重入或 retry 可使其略旧 | 以略旧快照上的 task 决策 | 不新增保证：头锁只串行化 head、回执与 effect，这些由 decider 在锁内读取；旧快照等价于决策先于该变更发生，放行仍只依据所锚 task 自己的当前回执与 effect；准入锚点与入队归因取同一个值。作为非原子边界接受 |
| Fixture 继续使用随机 task、NULL generation 或重复回执，造成假绿 | 测试可能再次证明“CR 内任意消费可借用” | 全部改为命名锚点及真实 task 行；删除重复回执写入；只增加错配反例，不削弱原断言 |
| Enqueue 与 decider 不共享数据库事务 | 不能声称业务判定与 INSERT 原子提交 | 保持 head lock 对撤销的线性化；依赖 advisory lock、active-task 唯一索引及 winner re-read |
| 不比较 `receipt.grant_digest` 与当前 head digest | approve 头 supersede 后旧回执是否可复用仍未收紧 | 明确列为本 change 残余边界；revision 级重新消费另立设计 |
| 同 task 新 generation 若误按当前 receipt id 连接 effect | 合法 re-claim 会永久等待 | receipt 与 effect 只按 task id 关联；TC-ATB-010 锁定“回执 +1、链记录 +0” |

## Test strategy

decider 测试在 `execution_admission_task_decider_test.go`（TC-ATB-001～004），内部动作测试使用 `server/internal/governance/execution_admission_task_binding_test.go`（TC-ATB-005～007）；真实路由/发现测试使用 `server/internal/governance/execution_admission_task_discovery_test.go`。每个拒绝条件均为独立命名 subtest，不用一个混合 fixture 同时覆盖多个原因。

| TC / Scenario | 包 / 文件 | 证明内容 | 独立覆盖的拒绝条件或正例 |
|---|---|---|---|
| TC-ATB-001 / SC-ATB-001 | `package governance`，task_decider | 请求与锚点 task 行校验 | 空 `TaskID` → `ErrAdmissionInvalid`；malformed `TaskID` → `ErrAdmissionInvalid`；锚点行缺失 → `WAIT_CONSUMPTION`；锚点在其他 workspace → `WAIT_CONSUMPTION`；`dispatched_at=NULL` → `WAIT_CONSUMPTION` |
| TC-ATB-002 / SC-ATB-002 | 同上 | generation 与 receipt scope | 仅旧 generation 回执 → `WAIT_CONSUMPTION`；仅其他 task 回执 → `WAIT_CONSUMPTION`；仅其他 CR 回执 → `WAIT_CONSUMPTION` |
| TC-ATB-003 / SC-ATB-003 | 同上 | 当前回执存在但可信链不完整 | 无 settlement、无 verdict、cursor 未覆盖、无 command 分别 → `WAIT_TRUSTED_T_COMMIT`；以上不得借用其他 task 的完整链 |
| TC-ATB-004 / SC-ATB-004 | 同上 | `VerifyTrustedVerdictEffect` 与正例 | malformed payload、错误 `effect`、错误 scope、错误 `command_digest` 分别 → `WAIT_TRUSTED_T_COMMIT`；正确 task 当前回执和自身有效 effect → `ADMITTED` |
| TC-ATB-005 / SC-ATB-005 | 同上，task_binding | `markNode` own-task 锚点（含 retry） | 仅 source/其他 task 消费 → 不 passed；节点 own-task 正确消费 → passed。retry 子用例：父 task 消费不得放行 retry 子 task；子 task 自身消费 → passed；重复 `markNode` 无额外状态变化 |
| TC-ATB-006 / SC-ATB-006 | 同上 | no-own-task fallback 与人工门 | 无 own-task 时，其他 task 消费 → 不 passed，正确 source → passed；human gate 对其他 task → 不通过，对正确 source → 通过。附 architecture re-review、requirement 投影 evidence 两个无 own-task 形态 |
| TC-ATB-007 / SC-ATB-007 | 同上 | 两条 dispatch 与首任务无循环 | Architecture：他 task → 不入队，正确 source → 入队；Requirement 同样各一例。source 有效且节点任务尚不存在时即可首次派发，不要求节点预消费 |
| TC-ATB-008 / SC-ATB-008 | `package governance_test`，task_discovery | Architecture 与 requirement 的真实首次发现 | 真实 source route `201` 后、discovery 前节点任务为 0；首次 `ResumeActiveRuns` 后恰 1 个首节点任务；第二次后无新增，且 `agent_task_queue` 与 `pipeline_node_run` 计数及首任务 id 不变 |
| TC-ATB-009 / SC-ATB-009 | 同上，architecture 子例 | 节点自身消费（运行中真实路由）后推进 | T1 running 时经真实 route `201`；T1 completed 后发现 → 首节点 passed，后续节点派发不要求其预消费；再次发现无新增任务或状态变化 |
| TC-ATB-010 / SC-ATB-010 | 同上，不经 Runner，复用 TC-CE-004 helpers | 合法重放与同 task 新 generation | 同 generation 重放 → `200 changed=false`，四类行数不变；仅旧 generation 时 → `WAIT_CONSUMPTION`；新 generation `201` 后 receipt +1，command/verdict/settlement 均 +0，恢复 `ADMITTED` |

`selections.json` 与运行器调整（主会话在草稿基础上修订）：

同次执行证据计划要求每个 TC 独占一个 CP、一个 CP 一条命令。数据库测试必须经 `run-selection.mjs` 才有一次性库，因此每个新 TC 对应 selections.json 里一条独立选择（`atb-001`…`atb-010`，`package` 均为 `./internal/governance`，`run` 为 `^TestTC_ATB_0NN$`），CP 的命令为 `node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only atb-0NN`。这要求 `run-selection.mjs` 新增一个 `--only <name>` 参数：只运行名称精确匹配的一条选择，名称不存在则报错非零退出（防止零匹配被当作通过）；不带该参数的行为不变。该参数有单元测试，写在既有 `run-selection.test.mjs`。

| Selection | 调整 |
|---|---|
| `atb-001`…`atb-010` | 新增，每个 TC 一条，随完整文件的一次真实运行一并回归 |
| `run-admission-support` | 在现有 alternation 中补上本轮直接受影响、原 regex 未包含的 `TestAdmissionGateHoldsNodeUntilConsumptionCommits`、`TestAdmissionGateStopsEnqueueUntilConsumptionCommits`、`TestAdmissionGateLockBlocksRevocation`、`TestAdmissionDeciderPanicReleasesHeadLock`（它们改了 fixture，却不在任何选择里，只有 `go test ./...` 才会跑到） |
| `run-routes` | regex 不变；现有 `TestTC_RUN_003` 覆盖修改后的 source-anchored 回归（CP-RUN-003 以 `--only run-routes` 运行），不得删除该选择 |
| 其余 selections | 名称与 regex 不变，但最终必须执行完整文件，证明无跨 capability 回归；不能仅运行新增选择 |

## 验证与证据说明

1. 先确认 Podman VM 已运行。真实步骤只能由 supervisor 调用 `scripts/aifi45-disposable/run-selection.mjs`，使用本次新建并返回完整 ID 的一次性实例；不得连接外部 admin URL。
2. 严禁操作 `multica-postgres`、`multica-backend`、既有 `aifi45-disposable` 或任何未知容器/旧库。实例必须满足脚本约束：`aifi45-disposable-<nonce>`、`aifi45.disposable=<nonce>`、tmpfs、仅 loopback、带生命周期上限（`scripts/aifi45-disposable/instance.mjs:14-50`）。
3. 从仓库根执行完整选择：
   `node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json`。
   脚本为每个 selection 创建独立数据库并运行迁移，再执行 `go test -count=1 -json`（`run-selection.mjs:107-138`）；本 change 不新增迁移文件，不手工迁移共享库。
4. 保存同一轮的 selections 内容、完整 stdout/stderr 与各组计数。通过标准为：**全部 selection `0 FAIL`、`0 skip`，且每组实际 PASS 数大于 0**。零匹配、编译失败、整包失败均不得记为通过。
5. 核对释放日志包含完整实例 ID 和 `remaining=0`；释放实现会先按完整 ID、名称和 label 验证归属，再删除并回读（`instance.mjs:70-96`）。不得为清理而删除其他容器。
6. 另在 `server/` 执行 `go build ./...` 与 `go vet ./internal/governance ./cmd/server`，并复核 diff：无迁移、无新路由、无 daemon/T 改动。测试报告只记录实际执行结果，不把本计划写成已通过证据。

## 设计期未验证事项（UNVERIFIED / OPEN）

- 设计阶段尚未运行 Go 测试、真实路由、Podman 或一次性数据库；BUILD 实际执行结果及遗留问题见 `test-report.md`。
- 未发现主会话七条事实与源码的直接冲突，但有两个必须保留的边界：
  - Code 测试 fixture 手工携带 `source_task_id`，但生产 projector 创建 run 时不写该字段；不能把 code 测试形状当作生产能力。
- 在检索范围内未找到 code run 的生产启动及周期发现入口；这不是对所有外部部署方式的证明，故 code/writeback 仍明确排除在 E2E 承诺之外。
- 无法仅从服务端代码证明生产中的节点 agent 一定会请求 binding proof；因此节点永久等待是已接受的 fail-closed 风险，而不是已验证的生产发生率。
- 设计阶段，真实 `ResumeActiveRuns` 不重复派发、节点自身消费后推进和 generation 恢复均待上述真实库用例验证；BUILD 结果见 `test-report.md`。撤销互斥（`55P03`）沿用既有锁测试，本 change 不改锁序。

## 修订记录

- 2026-11-11 Gate 2 修订（BUILD 中发现，见 `pending-adjustments.yaml` ADJ-001～003）：
  - 决策 2：删除“锚点解析器 + 锁后重读”，改为调用方快照加 decider 在头锁内读取事实；原因见该节“头锁保护什么、不保护什么”。
  - 决策 6：真实链按可达时序重排（运行中消费、完成后发现）；删除锁交错场景。
  - 场景由 12 个减为 10 个：原 SC-ATB-008（retry）并入 SC-ATB-005，原 SC-ATB-009（锁交错）删除，原 010～012 顺延为 008～010。
