# 设计调整记录（BUILD 阶段）

> 本文件只记录实现与受审文档（design.md / canonical specs / test-plan.md）的偏离。
> **2026-11-14 文档同步轮**：ADJ-S7-1/2/3 与 ADJ-S3-1、ADJ-E4-1 已同步写入 design.md、canonical specs、test-plan.md、slices.md、tasks.md（见各条「同步位置」）。
> **Gate 2 已于 2026-11-14T02:46:19 由用户重审确认**（`--reapprove`，证据原文「确认 Gate 2」；AI 解读为：接受 G2-7、接受 D1.7 边界、采纳「不算 Gate 1 新增接受风险、不重审 Gate 1」的判断，已向用户声明）。Gate 1 未重审。重审时 `specs/real-execution-closure/spec.md` 与 `specs/workspace-delete-execution-tables/spec.md` 由 stdd 的 `_generate_spec` 重新渲染（旧文件经比对与改动前 canonical 的渲染逐字节一致，非手写）。
> 记录不等于批准：S9 实现、S4–S6 真实运行仍各需单独授权或前置条件，见 tasks.md。

## 已知：`stdd validate` 的 TC/Scenario 粗略计数不满足（未处理，非本轮引入）

- `stdd validate` 要求 TC 个数不少于 `specs/*/spec.md` 的 Scenario 个数。Gate 2 渲染出 `spec.md` 后，原始状态即为 10 个 TC 对 12 个 Scenario（差 2）；本轮同步后为 12 对 13（差 1）。此前「通过」只是因为 Gate 2 之前 `spec.md` 不存在。
- 原因是 TC-REC-004 一次真实运行同时覆盖 SC-REC-004/005 与 SC-RUN-001/007，TC-REC-005/006 同覆盖 SC-RUN-006，TC-WSD-006/007 同覆盖 SC-WSD-006；这是证据计划「每 TC 一条 check、各绑独占 CP」的有意映射，不是漏测。
- 未为凑数新增 TC，也未改 test-plan（改了会使刚确认的 Gate 2 再次 stale）。`validate` 是只读结构检查，未接入 Gate 与 phase 推进。**不得声称 `stdd validate` 通过。** 如用户要求消除，需拆分 TC 或新增 TC 并再次重审 Gate 2。

## ADJ-S7-1 workspace 锁模式：`FOR KEY SHARE`，而非 `FOR SHARE`（需重审 Gate 2）（已于 2026-11-14T02:46:19 重审通过）

- **设计原文**：design.md D4-A 第 2–4 点与 :128、:192、:240（同步前位置，现行行号已变），test-plan.md :199（同步前位置，现行行号已变），slices.md 第 7 行（同步前位置，现行行号已变），均写 `FOR SHARE`。
- **实现**：`governance.lockWorkspaceKeyShare` 执行 `SELECT id::text FROM workspace WHERE id=$1::uuid FOR KEY SHARE`，三处取锁点：`ApplyControlCommandTx`、`CreateReservationTx`、`HandleDaemonExecutionConsumption`（先于 claim/head 锁）。
- **理由（事实）**：
  - 删除侧的 `LockWorkspaceForDelete` 是 `FOR UPDATE`，与 `FOR KEY SHARE`、`FOR SHARE` 都互斥，删除/写入的互斥保证两者相同。
  - 区别在普通 UPDATE：`FOR SHARE` 与 `UPDATE workspace SET issue_counter = ...`（`FOR NO KEY UPDATE`）冲突，`FOR KEY SHARE` 不冲突。用 `FOR SHARE` 则每次授权节点消费期间，该 workspace 的创建 issue 会被阻塞到消费事务结束。
  - 既有先例：`LockWorkspaceForChatSessionCreate`（`workspace.sql:82`）对同一删除锁使用 `FOR KEY SHARE`。
- **证据**：把模式改成 `FOR SHARE` 后 `governance-wsd-lock` 变红（"an ordinary UPDATE of the workspace row was blocked"）；改回后绿。
- **对保证的影响**：SC-WSD-005/006 的两条保证不变；只是不额外阻塞无关写入。

## ADJ-S7-2 并发探针不引入生产测试 hook（需重审 Gate 2）（已于 2026-11-14T02:46:19 重审通过）

- **设计原文**：design.md D4-A 并发探针写"默认 nil 的测试 hook 报告锁已持有并阻塞到测试释放"。
- **实现**：`handler/workspace_delete_concurrent_test.go` 不改任何生产代码。
  - 交错一：测试事务先取 workspace 锁并写入，真实 `DeleteWorkspace` 请求锁时被 `pg_blocking_pids` 确认阻塞（SQL 含 `FROM workspace`、`FOR UPDATE`），再提交写入，删除成功，写入结果恰好一份。
  - 交错二：用另一事务对该 workspace 的 `cr_execution_notice` 行 `FOR UPDATE`，把真实 `DeleteWorkspace` 暂停在它自己的 sweep（它取得 workspace 锁之后），用 `FOR KEY SHARE NOWAIT` 探针确认删除确实持有 workspace 锁（前提断言），再启动 writer，确认它被删除事务阻塞；释放暂停，删除提交，writer 以 `ErrReservationWorkspaceGone` 失败，该 writer 的行数为 0，A 的 19 张表对照保持。
- **理由**：不在生产路径加只为测试存在的 hook；暂停点用生产自己的 sweep 行锁，行为更真实。
- **"无 sleep"的口径**：不用 sleep 决定顺序。等待循环里有 5ms 轮询间隔，但顺序由 `pg_blocking_pids` 观察到的锁等待确定，超过 8s deadline 则失败。
- **证据**：把 `ApplyControlCommandTx` 的取锁删掉 → command 的两种交错变红、reservation 的仍绿（pass=2 fail=4）；再同时删掉 `CreateReservationTx` 的取锁 → 6 个全红。已逐字节还原。

## ADJ-S7-3 新增一个选择 `governance-wsd-lock`（需重审 Gate 2，test-plan 增行）（已于 2026-11-14T02:46:19 重审通过）

- **新增**：`governance.TestExecutionConsumptionHoldsWorkspaceKeyShare`，选择名 `governance-wsd-lock`（`selections.json`）。
- **理由**：`handler-wsd-race` 的两个 writer 覆盖 `ApplyControlCommandTx` 与 `CreateReservationTx`，但生产里唯一调用 `ApplyControlCommandTx` 的是 `HandleDaemonExecutionConsumption`。锁序"workspace 先于 claim/head"是在该 handler 里保证的，只测 store 函数不能防止 handler 里的锁被删掉或移到 claim 之后。该测试在 handler 已证明 claim、将要写入的时点，用独立连接断言：对 workspace 行的 `FOR UPDATE` 被阻塞（删除互斥），普通 `UPDATE` 不被阻塞（模式不过强）。
- **证据**：删掉 handler 里的取锁 → 红（"a FOR UPDATE on the workspace row was not blocked"）；改成 `FOR SHARE` → 红；还原后绿。

## ADJ-S7-4 TC-WSD-005 的"缺 workspace"用例落点

- test-plan 的 TC-WSD-005 要求"缺 workspace 的 `ErrReservationWorkspaceGone` 用例"。落在 `TestWorkspaceDeletionRefusesNewCommand` 内，作为新增子测试（CP-WSD-005 选择 `handler-wsd-no-recreate-command` 不变）：
  - `command_for_unknown_workspace`：从未存在的 workspace id → `ErrReservationWorkspaceGone`。
  - `command_without_workspace`：`WorkspaceID` 为空 → `ErrControlStoreInvalid`。
  - 已删 workspace 子测试原只 `t.Logf` 拒绝原因，现与 reservation 半边一致钉住 `ErrReservationWorkspaceGone`（原 `err == nil` 的 Fatal 断言保持不变，只增不减）。
- 文件头与函数注释里"仍红 / known finding / ADJ-017"的陈述已过时，已改为"已转绿"，"不得放宽断言"保留。
- **理由**：这样 CP-WSD-005 的选择名与命令不变，不触碰 Gate 2 已确认的 CP 映射；用例落在同一函数里，也让"缺 workspace"与"已删 workspace"共享同一套 fixture 与正向对照。
- **证据**：两个子测试经 `handler-wsd-no-recreate-command`（5/5）在一次性 PG 通过；`ApplyControlCommandTx` 去掉 workspace 取锁的变异使 command 两个交错用例变红（见 phase-context 的 S7 变异记录）。**未单独验证**：该变异是否也使 `command_for_unknown_workspace` 变红（未知 workspace 可能同时被外键拒绝），故这两个子测试的独立性靠它们断言不同的错误身份（`ErrReservationWorkspaceGone` 与 `ErrControlStoreInvalid`），不靠变异证明。

## 已核对的事实（非偏离）

- `HandleDaemonExecutionConsumption` 对 workspace 缺失返回 409 `EXECUTION_BINDING_SCOPE_MISMATCH`，其余取锁错误返回 500。这是新增的拒绝路径，沿用该 handler 对"claim 行不存在"的同类答复；design 未逐字规定状态码。
- 生产里 `ApplyControlCommandTx` 只有一个调用者（`execution_consumption_effect.go:155`，在上述 handler 内），`CreateReservationTx` 当前没有生产调用者，所以 handler 内先取 workspace 锁即固定了锁序 workspace → claim → head → lineage → cursor。
- 回归：governance 整包失败集合与 HEAD 相同（48 个既有失败，均为 `TestChannelMigration*` 的环境前提，与 `test-ownership.json` 已登记的 independent 项一致）。`TestTC_ATB_009` 在 HEAD 上单独跑也会失败（`binding issue = 400, want 200`），在工作树上时过时不过，**未定位根因**，不归因于本变更。

## S8 待办（本切片刻意未做）

- `test-ownership.json` 的 `TestWorkspaceDeletionRefusesNewCommand` known-finding 条目现已与事实不符，须移除；`test-ownership.test.mjs:199-221` 的 TC-TOR-001 断言"已提交的 known-finding 仍在"，须随之改为不再依赖该条目（机制本身的夹具测试保留）。这改的是 fork-ci 变更的测试，S8 里单独处理并说明。

## ADJ-S3-1 design 里的内存标记名与实现不一致（需重审 Gate 2，文字性）（已于 2026-11-14T02:46:19 重审通过）

- **设计原文**：design.md D1 第 2 条写「标记 `executionConsumptionRecorded`」。
- **实现**：字段名为 `Task.ExecutionPreconsumed`（`json:"-"`，仅内存，不进 wire），另有 `Task.PipelineExecutionContract`（claim 合同值，进 wire）。语义不变：只有预消费拿到平台持久化回执后才设置，不替代回执。
- **同步位置**：design.md D1 第 2 条。受审字节变了就算 stale，工具不判断「勘误」，所以与其他条目一并重审。

## ADJ-E4-1 授权节点的信任根注入：daemon 经环境变量 `CRCTL_EXECUTION_TRUST_ROOT` 交付（新增设计，需重审 Gate 2）（已于 2026-11-14T02:46:19 重审通过）

- **起因**：design 的未验证项与 tasks 3.3（E4 结论）：节点 agent 的 `crctl advance` 读不到 daemon 信任库里的 grant。crctl 只认 `--trust-root`，无环境变量也无默认根；节点 skill 的 advance 不带该 flag；daemon 只给 agent 注入 `MULTICA_EXECUTION_BINDING_ENDPOINT`。用户裁定走成对 tools change（选项 A，未采用放宽信任边界的 B）。
- **tools 侧**（独立 Gate，各自确认，互不代签）：change `2026-11-13-aifi-45-node-trust-root` 已完成 Phase 1–3，Gate 1/2/3 均已确认（**2026-11-14T23:06:22 后更新：并入 B2/B4 使 Gate 1/2/3 先后 stale，Gate 1/2 已重签 current，Gate 3 仍 stale，待用户在 S4/S5 取证后重签；本条为 ADJ-E4-1 当时的记录**）；变量 `CRCTL_EXECUTION_TRUST_ROOT`，八个命令生效，与 `--trust-root` 同值通过、异值 `EXECUTION_TRUST_ROOT_INVALID`。**仍未提交，也未进入 DELIVER。** tools 的实现未做真实 daemon 注入与真实节点运行。
- **本变更新增的设计**（design.md D1 第 7 条；L2 表新增 agent 环境变量行；风险表 4 行；canonical SC-REC-008；TC-REC-009、CP-REC-009；slices.md S9；tasks.md §9）：
  - 值 = `store.Root`，即 daemon 自己调用 crctl 时传的 `--trust-root` 实参（`daemon/execution_verifier.go` 的 `prepareClaimedPipelineTask` 与 `consumeClaimedExecution` 里传给 crctl 的 `--trust-root` 实参）。tools 侧逐字比较，不归一。
  - 仅对「已绑定且 `ExecutionPreconsumed`」的任务，在 `injectTaskCRWorkspaceEnv` 内、与 `CRCTL_OPERATIONAL_WORKSPACE` 同条件发布；函数开头先 `delete`（含 custom_env 带入的同名变量）。不写 daemon 进程环境。载体 `Task.ExecutionTrustRoot`（`json:"-"`）。
  - 发布顺序先 tools 后 daemon；daemon 无条件注入，不探测 crctl 能力、不加握手；错位时 advance 失败关闭、节点不推进。
- **只定位、不授权**：agent 今天本来就能给 crctl 传任意 `--trust-root`；本地准入成功不等于平台授权，权威仍是平台侧该任务当前 generation 的预消费回执。注入不新增 agent 能力，也不提供隔离。
- **关于 Gate 1 的判断（AI 的判断，请用户裁定）**：
  - **判断**：只重审 Gate 2，不重审 Gate 1。理由：proposal 与 canonical proposal 里没有「agent 不得知晓信任库路径」之类的安全不变量或已接受风险条款（已检索信任根、信任库、不变量、接受风险）；业务承诺与成功标准不变；Gate 1 固定约束预设了「需改 tools 时开成对 change」，已按其办理；注入不新增 agent 能力。
  - **反面（须诚实写出）**：`execution_trust.go` 称信任库为 daemon-only install root，并要求它在 agent 工作树之外。注入把路径告知 agent，这句话的含义变了——安装与写入者仍只有 daemon，但 agent 现在拿到路径。若用户认为这属于新增接受风险，则按修订矩阵须 Gate 1+2 一并重审并重跑旧证据。实现时校正该注释。agent 与 daemon 同一 OS 用户时，目录本来就可被 agent 读写（0700 只挡不同用户），注入没有改变这一点。
- **未验证**：agent 与 daemon 是否同一 OS 用户；provider 沙箱是否允许 agent 读该目录；旧 crctl 的错位行为是读码推导。真实节点运行（S5）才会暴露这些，读不到按止损点处理（只修 S1–S3/S9 的生产链，不回退 `.crctl`、不暗中改 tools）。
- **对 S4–S6 的影响**：不改变它们的授权需求；仍需用户单独授权 podman、backend/daemon、非 Fable 模型名、次数与费用。

## 同步轮新增与变更清单（供 Gate 2 重审时对照）

- **design.md**：头部同步说明；D1 方案标题与第 2 条（标记名）；**新增 D1 第 7 条**；D4 方案标题；`FOR SHARE`→`FOR KEY SHARE`（D4 正文、L2 表、风险表、序列图、G2 表各处）+ 新增「锁模式」段；并发探针段整段重写（不加 hook，新增 `governance-wsd-lock`）；L2 表新增 agent 环境变量行与 3 处锁模式措辞；序列图加 `ExecutionPreconsumed`/信任根注入；D5 两处说明；风险表改写「agent 看不到 grant」行并新增 3 行，替换「测试 hook」行；未验证项两条；Gate 2 决策表新增 **G2-7、G2-8**；两处「推荐」口径改为已确认口径。
- **canonical code specs**：real-execution-closure 新增 SC-REC-008，描述两处改为已确认口径；workspace-delete-execution-tables 新增三条 `and`（workspace-gone/invalid 错误、锁模式、消费入口锁序），描述改为已确认口径。
- **canonical agent specs**：real-execution-closure 新增 CP-REC-009，前置条件加 009；workspace-delete-execution-tables 新增 CP-WSD-007。
- **test-plan.md**：新增 TC-REC-009、TC-WSD-007；TC-WSD-005/006 的输入、预置条件、预期、测试位置改为实现口径（旧断言原样保留不变）；执行矩阵、回归风险矩阵、补充顺序；证据计划块 10→12 个 TC，新增 2 条 check（各绑独占 CP）。
- **slices.md / tasks.md**：新增 S9 与 §9；S7 的锁模式与探针描述；tasks 3.3 注明已裁定走成对 tools change。
- **不变**：proposal、Gate 1 已确认的范围与 Q1–Q6；SC-REC-001..007、SC-RUN-*、SC-WSD-005/006 的 `then` 主句；TestWorkspaceDeletionRefusesNewCommand 的旧断言；4 个真实 CP（CP-REC-004/005/007 及它们的授权前提）。

## ADJ-S4-1 驱动的实现分层与两处细化（不改受审文档，仅记录）

- **文件**：`scripts/aifi45-real-run/{config,lifecycle,smoke,run}.mjs` 与 `real-run.test.mjs`（hermetic，假 podman，42 个用例）。`run.mjs` 导出 `main(argv, io)`，CLI 入口只在直接执行时运行。
- **配置字段**按 design 接口表：`model`、`max_runs`（1..3）、`cost_ack`；`model` 空/空白/非字符串或含 `fable`（不区分大小写）、`max_runs` 缺失/越界/非整数、`cost_ack` 缺失/空白、配置不可读/不可解析，均在创建任何资源前以 `REFUSED real-run ...` 非零退出。`cleanup-smoke` 不接受 `--config`。
- **清理是同步的**（podman 调用用 `spawnSync`），所以同一个 `releaseAll` 既能在 `SIGINT`/`SIGTERM`/未捕获异常里用，也能在 `exit` 事件里用；释放失败的资源留在登记册里，下一次调用重试，`remaining` 只数「未被证明已消失」的对象。容器删除前以完整 ID + 名称 + nonce label 三者证明归属；创建后返回的 ID 不可用时，由按 label 的读回兜底发现。
- **架构场景未实现前**：`architecture-main`/`architecture-revoke` 在配置校验通过后输出 `INCONCLUSIVE real-run stage=setup reason=SCENARIO_NOT_IMPLEMENTED` 并非零退出，绝不打印 PASS。
- **dummy 容器**用本机已有的 `alpine:3.21`（`--pull=never`），不碰任何 `multica-*`。
- **验证**：8 个变异（去归属证明、失败后继续、去 label 读回、deadline 改为每阶段、去 SIGTERM 处理、失败释放不重试、放行 Fable、放宽 max_runs 上限）均使测试变红并已还原；真实 cleanup-smoke 6 行 PASS。**未验证**：SIGKILL 路径（只靠容器 `--timeout` 与 label 读回兜底，设计已承认）；整进程树被外层 supervisor 终止的情形。

## ADJ-S5-0 真实运行用固定来源的 crctl 副本（用户 2026-11-14 同意，S5 实现，不改受审文档）

- **事实**：daemon 的 crctl 位于「受控 shell 规则文件旁」（`daemon/pipeline_task.go` 的 `resolvePipelineCrctl`）。真实运行若指向 tools 工作树，会跑到含他人未提交 M008 改动的 crctl，证据说不清验证了什么。
- **做法**：S5 的驱动在工作树之外建临时副本，内容为 tools 的 `HEAD` 加本 tools change 的 `crctl.mjs` 改动（只按路径取这一个文件，不读、不依赖他人的未提交文件），把规则路径指向副本，并在输出里打印 crctl 的 sha256。不动 tools 工作树，不需要提交。
- **与 CI 的 pin 机制无关**：`tools-pin.mjs` 固定的是已提交的 revision，不适用于未提交的改动。

## ADJ-S6-1 撤销后不推进：无需生产改动，测试一次即绿（不改受审文档，仅记录）

- tasks 6.2 预设「仅在证明缺既有 gate 时才补最小修复」。`TestTC_REC_006`（`rec-revoke`）首次运行即通过，说明既有 admission gate（`execution_admission.go` 的 head 判定、`markNode` 的 passed 门）已满足 SC-RUN-006 的组件层部分，**未改生产代码**。
- 一次就绿的测试不能直接当证据：同序列含「未撤销」对照子测试（会推进），并做了 4 个变异（去 head 拒绝判定、去 `markNode` 的 admission 门、重启后 Runner 无 decider、不发撤销请求），均变红；连跑 3 次稳定。
- **未覆盖**：派发入口 `decideUnderHeadLock`（`governance/runner.go` 的派发入口，函数定义在 `governance/execution_admission_gate.go`）对「writer 已 passed、撤销后才派发 reviewer」的独立拒绝；既有 `TestAdmissionGateLockBlocksRevocation` 只覆盖该入口的持锁。要覆盖须构造「passed 但未派发」的中间态，超出本 change 的有限保证，记为未验证项，不声称覆盖。

## ADJ-S8-1 test-ownership 台账随 S7 转绿调整（不改受审文档，仅记录）

- S7 让 `TestWorkspaceDeletionRefusesNewCommand` 转绿后，`test-ownership.json` 里它的 `known-finding` 条目已不符事实，已移除；`test-ownership.test.mjs` 的 `TC-TOR-001 the committed known-finding stays declared...` 依赖该条目存在，改为 `TC-TOR-001 the committed table declares no known-finding now that the command probe is fixed`（findings 为空、`check` 退出 0、`skip-regex` 不含该探针；约 197–200 行的期望字符串同步去掉该名）。用合成条目验证 known-finding 机制的测试一字未改。
- 这两个文件属于已交付的 fork-ci change（`2026-11-12-fork-ci-test-evidence-trust`）的产物；本 change 只改了「该条目是否存在」这一事实依赖，不改它的机制与其他断言。变异检查：恢复条目后新测试与「台账起始条目」测试变红。
- `CUSTOM.md` 的 #327 行按「只增不改」末尾追加「已由 #335 修复」，原文不动。

## ADJ-C1-1 C1 评审（strong 档只读）发现与处置（不改受审文档，仅记录）

C1 对 S1/S2/S3/S7/S9 的未提交生产代码做了只读评审：BLOCKER 0，MAJOR 2，MINOR 3，NIT 2。主会话逐条核实后处置如下。

**已修（均先证明缺陷或让测试能区分）**

- **MAJOR-1 授权节点的 strict 在 CR root 准备阶段丢失**。`prepareClaimedPipelineTask` 的外层因 `PipelineExecutionContract` 判为 strict，但 `preparePipelineTask` 只从（节点任务为空的）触发评论推导 strict，于是不做 `viewsForTaskProject`：多项目同名 CR 会报 `found 2`，只有 foreign root 时会把它带入后续 preflight。**同一类问题的三处判据**（外层、root 准备、`daemon.go` 两处终态上报 fencing 判定）各自推导 strict，修在共同边界：新增 `taskExecutionStrict(task)` 作为唯一推导，三处都调用它。新增 `TestTaskExecutionStrictReadsBothSources`（6 例）与 `TestExecutionRootBindingRequiresTrustedProject` 的子测试「authorized node task is scoped to its own project too」；把 `preparePipelineTask` 改回旧推导后该子测试变红，已还原。
- **MAJOR-2 Windows 下 custom_env 可用大小写变体注入或覆盖信任根**。子进程环境在 Windows 上大小写不敏感，而 map 转环境切片的顺序不定，注入器只删除精确大写键。改为按 `strings.EqualFold` 清除，再发布精确大写键。新增子测试「a case variant of the name is no way around the clearing」（授权与未预消费两种任务）；改回精确键 `delete` 后该子测试变红，已还原。
  - **不修的同类项**：`CRCTL_WORKSPACE`、`CRCTL_OPERATIONAL_WORKSPACE`、`CRCTL_TASK_AUDIT_ROOT`、`CRCTL_TRIGGER_*` 的清除同样只匹配精确键，是 CR-2026-072/076 的既有行为，不在本变更的保证范围内，也未被本变更放大。另行提醒，不在此处顺手改。
- **MINOR-3 锁序测试不能证明 workspace 先于 claim/head**。既有 hook 在所有锁都取完之后才运行，反序也能通过（本轮在反序变异下确认：既有测试仍绿）。新增 `TestExecutionConsumptionTakesWorkspaceBeforeClaimRows`：测试连接持有 task 行 `FOR UPDATE`，让 handler 撞上它，轮询 `workspace ... FOR UPDATE` 探针，被阻塞即说明 handler 在等 task 行时已持有 workspace。把 workspace 锁移到 claim 锁之后，新测试变红（既有测试仍绿），已还原。归入 `governance-wsd-lock` 选择（现 2 个测试）。
- **NIT-1 陈旧的 single-shot/exactly-one 注释**（`execution_binding_endpoint.go`、`daemon.go`）与「预消费授权节点最多 2 个不同 challenge、同字节可重放」不符，已改。**NIT-2 `issueConsumptionEffectTx` 前置条件注释**漏了 workspace 锁，已补成 workspace → claim → head。

**未采纳 / 记录**

- **MINOR-1 发布条件没有检查 `ExecutionPreconsumed`**：不采纳。`ExecutionTrustRoot` 只在 `prepareClaimedPipelineTask` 里与 `ExecutionPreconsumed` 同一处赋值（`nodeAuthorized` 为真时），两者不可能不一致；S9 的变异 M2 已证明同时判两个条件是重复判据，`TestTC_REC_009` 的「未预消费不发布」子测试覆盖该保证。保持单一判据。
- **MINOR-2 `CreateReservationTx` 未重读 current head（design D4.4 文字写「重读 selection/current head」）**：如实记为偏差，不补实现。`ReservationRequest` 不携带任何 head 信息、reservation 行也不依赖 head，当前无生产调用方（`CreateReservationTx` 仅测试使用）；在无调用方、无合同的前提下构造「head 重读」只会凭空增加一个判据。实际落实的是 D4.4 中与 SC-WSD-006 直接相关的部分：先锁 workspace、锁后再读 selection、再插入（`TestWorkspaceDeletionRefusesNewCommand` 与 `handler-wsd-race` 覆盖）。若将来有生产调用方需要 head 准入，应随该调用方的 change 一并设计。待文档同步轮把 D4.4 的「/current head」措辞勘误，当前受审文档保持原文。

## ADJ-C1-2 `TestTC_ATB_009` 的非确定性失败找到根因（测试夹具，不改受审文档，仅记录）

- **现象**：全组回归里 `rec-revoke` 在 S6 当天连跑 3 次绿，随后一次全组红，报 `binding issue = 400, want 200: EXECUTION_BINDING_REQUEST_INVALID`（`governance/execution_revoke_resume_test.go` 的 `TestTC_REC_006`（`revoked_head` 子测试里 writer 消费前的 binding issue））。此前 `TestTC_ATB_009` 的非确定性失败（HEAD 隔离运行也失败）一直未定位根因。
- **根因**：`decodeExecutionBindingRequest` 要求 `dispatched_at` 等于 Go 的 `RFC3339Nano` 规范拼写（`execution_binding_issue.go:436`，会去掉末尾的 0）。测试用 `to_char(dispatched_at, '...SS.US"Z"')` 取 `dispatched_at=now()` 的值，`US` 永远输出 6 位小数；微秒位以 0 结尾（约十分之一）时，同一时刻是两种拼写，被拒为 400。生产不受影响：daemon 的 `dispatched_at` 来自 claim JSON，已经是 Go 规范拼写。
- **确认方式**（不是推断）：把两个用例的 `dispatched_at=now()` 临时固定为 `2026-11-14 00:00:00.123450+00`，两个都稳定红，报错与现象逐字相同（atb-009：`execution_admission_task_discovery_test.go` 的 binding issue 断言；rec-revoke：`TestTC_REC_006` 同一处断言）；加上规范化后两个都绿；还原 `now()` 后 `rec-revoke` 与 `atb-009` 各 20 次共 40 次全绿。`TestTC_ATB_010`、`TestTC_CE_004` 的 `dispatched_at` 来自固定夹具值 `+1s`，小数 `123456` 不以 0 结尾，不暴露。
- **修复**（共同边界一处）：`execution_revoke_resume_test.go` 新增 `canonicalGeneration(t, raw)`（解析后以 `RFC3339Nano` 重写），S6 用例与 `TestTC_ATB_009` 的赋值点各调用一次。`TestTC_ATB_009` 是前一个 change 的测试文件，只改这一行赋值，不改任何断言。
- **未做**：没有去改生产解码器（它是对的，拒绝非规范拼写是它的合同），也没有给其余 `to_char` 用点加 helper（它们的输入固定、不暴露）。

## ADJ-C1-3 C1 的 test_config（balanced）与 docs_skills（economy）评审及处置（不改受审文档，仅记录）

两路评审均只读。test_config：BLOCKER 0，MAJOR 3，MINOR 6，NIT 2；docs_skills：BLOCKER 0，MAJOR 1，其余 MINOR/NIT 共约 18 项。逐条核实后处置如下。

**test_config 已修（均有红绿或变异证明）**

- **MAJOR-1 `workspace_delete_concurrent_test.go` 的探针与暂停事务取自 `testPool`**：pgxpool 默认 `MaxConns = max(4, NumCPU)`，交错二同时占用 rollup 单例、暂停事务、写入事务和被测删除各一条连接，第五次探针查询在 4 核 runner 上拿不到连接。本机 16 核，所以一直没暴露。**复现**：临时把 handler 测试池 `MaxConns` 钉成 4，旧测试红（`no backend became blocked ... within 8s`）；**修复**：暂停事务、写入事务与观测探针改用 `pgx.Connect` 的独立连接（`wsdConn`），池里只剩 rollup 单例与被测删除；池 4 下转绿，正常池 5 次连跑全绿；`handler_test.go` 的临时改动已逐字节还原。
- **MAJOR-2 `TestTC_REC_002` 两侧都经同一个 `AgentTaskResponse`**，把 JSON 键改名不会变红，而键名正是 server 与 daemon 唯一的耦合点：键一旦不一致，所有授权节点静默退回 legacy，TC-REC-001/002/003/009 全绿。**修复**：每个用例把 claim 响应 `json.Marshal` 后解到 `daemon.Task` 再断言（该包已有先例 `issue_trigger_preview_test.go`）。**变异**：把 daemon 侧标签改名，`TestTC_REC_002` 的两个"授权"子测试（initial approval、revoked authorization）及其父测试变红（`pass=3 fail=3`），其余三个 legacy 子测试仍绿，已还原。
- **MINOR-5 TC-REC-006 缺 test-plan 写的"调节点完成"步骤**：序列里加入 `Reconcile`（task-completed 事件所调的节点完成入口），在原 Runner 与重启后的 Runner 上各调一次，夹在 discovery 之间；未撤销的对照仍会推进。6 次连跑全绿。
- **MINOR-4 real-run 测试的 60 ms 时间余量**：阶段 250 ms、预算 375 ms，两侧各 125 ms 余量；「每阶段新预算」变异仍红，已还原。
- **MINOR-6 `the same generation consumed twice stays one receipt` 名不副实**：它只断言 daemon 对 `changed=false` 的重放仍放行，不数回执行。改名为 `a replayed generation answered changed=false still admits`，并注明「重放不新增行」是 server 属性，由 `m005-consumption-effect` 承担。
- **MINOR-7 8 秒轮询窗口落在被测删除 10 秒 `lock_timeout` 内**：交错用例改用 `setWorkspaceDeleteLockTimeoutForTest` 把删除自身的锁等待放宽到 60 秒，窗口不再受慢 runner（CI 带 `--race`）影响。
- **MINOR-8 `lockWorkspaceKeyShare` 注释"每个 execution-control 写入者都先取"不实**：`ApplyControlPolicyEventTx`（撤销/停止）不取，也无生产调用方（全仓只有测试调用）。注释改为"三个运营写入者先取"，并写明策略事件当前无生产调用方、无 workspace 入参，将来的调用方需自行决定是否允许对已删 workspace 写停止事件。**不加实现**：没有调用方也没有合同。

**test_config 记录、不修**

- **MAJOR-3 CI 不执行 `scripts/aifi45-real-run/*.test.mjs`，且驱动不在任何 change-scope**：属实，且是先前已识别并留给用户裁定的项（`ci.yml:1076` 只跑 `scripts/aifi45-disposable/*.test.mjs`）。改 CI 属于改 `ci.yml` 与 `ci-paths.json`，须用户确认，已列入收尾待决项，不自行改。
- **MINOR-9 `handler-wsd-race` 不含"重复 reservation 的既有幂等行为不变"**：属实，这条由 `channel-protocol` 选择里的 `TestChannelFoundationReservation` 承担（全组回归 CP-REC-008 含它）。`handler-wsd-race` 属于 handler 包，该测试在 governance 包，同一选择无法跨包；要并入须改 CP 映射即改 test-plan（Gate 2 重审）。不为凑一个映射去改受审文档，如实记为"该子句由 `channel-protocol` 选择承担"。
- **NIT-10 `installCleanup` 每次安装 5 个监听且不摘除，会触发 MaxListenersExceededWarning**：不采纳。监听数是每个事件名一个，冒烟安装 3 个 registry 即每个事件 3 个监听，远低于默认上限 10；驱动是进程级生命周期，不需要摘除；"恰好一次"由登记册而非监听数承担。
- **NIT-11 `signer.calls` 在 HTTP handler 协程写、在测试协程读，无同步**：不采纳。`syscall.Read/Write` 在 race 构建里对全局 `ioSync` 做 Acquire/ReleaseMerge（`syscall/syscall_unix.go`、`internal/poll/fd_windows.go`），handler 先写计数、后写响应，测试协程读完响应才读计数，这条经 socket 的先后会被竞态检测器视为同步。既有 `execution_binding_endpoint_test.go`、`execution_binding_endpoint_interop_test.go` 对同一个共享 fake（`fakeBindingSigner.calls int`）同模式读取，改类型会改动既有测试文件。依据是读 Go 源码，本机无 gcc，未能本地跑 `-race`，属未验证。

**docs_skills 已修**

- **MAJOR-1 CUSTOM.md #334 行 7 个单元格**：上一轮追加"合并注意"文字时落在行尾的 `|` 之后，多出一个单元格（且行尾丢了 `|`）；已并回第 6 列并补回行尾 `|`，四行均为 6 列。同时，"改动"列的编号 ①②③④⑥⑦ 跳号，已改为 ①–⑥。
- **MINOR**：`governance-wsd-lock 1/1` 已过期（CUSTOM.md、`phase-context.md`、`.stdd.yaml`）改为 2/2；Gate 2 已重审但 tasks.md 与 ADJ 标题仍写"待/需重审"，已补"已于 2026-11-14T02:46:19 重审通过"（`design.md`、`test-plan.md` 头部是 Gate 2 指纹，**刻意不改**，已在 `phase-context.md` 记明）；`phase-context.md` 的"`stdd validate` 通过"与事实矛盾，已改；`phase-context.md` 缺 S6 记录，已补，并写明 S6 切片整体未完成所以不入 `slices_completed`；两处新 `// AIFIRST:` 标记缺 change id（`handler/agent.go`、`execution_revoke_resume_test.go`），已统一；`tasks.md` 选择名 `revoke` 应为 `rec-revoke`，已改。
- **NIT**：`design-adjustments.md` 与 `tasks.md` 中的 `file:line` 漂移引用（`runner.go:1082`、`execution_verifier.go:116,216`、`execution_revoke_resume_test.go:122`、`pipeline_task.go:904`、以及同步前的 design/test-plan/slices 行号）改为符号引用或注明"同步前位置"（balanced 子代理执行，我核对结果）；CUSTOM.md 索引行补 `pipeline_task.go` 与 `.gitignore`；#335 位置列补 `cmd/server/execution_run_003_test.go` 与 `execution_admission_task_discovery_test.go`；phase-context 的 27/28 口径差异已说明；ADJ-S7-4 补"理由/证据"；`tasks.md` 补 C1 修复与 S5 `crctl-stage` 两条。
- **不修**：`.stdd.yaml` 的 `traceability: 0/0/0` 是 stdd 新建 change 时写入的模板默认值（`stdd/cli/commands/new.py`），构建阶段不维护，也没有读取它做判定的逻辑，故不填；ADJ-S5-0、ADJ-S6-1、ADJ-S8-1 没有"证据"小标题但各自含"验证/未覆盖/未做"，不为对齐格式改写。

## ADJ-A0-1 — 无模型替身运行(architecture-stub)发现两处生产缺口(2026-11-14,已裁定:B1+B2 同一次修订,B2 选 tools 补字段;文档已同步,待 Gate 2 重审,尚未改任何生产代码)

- **来源**:`node scripts/aifi45-real-run/run.mjs --scenario architecture-stub`(真实 podman 整栈、真实 backend/daemon、替身 pi,零模型费用)。栈、domain seed、CR 工作区、真实授权路由(HTTP 201)、source 任务入队均 PASS,随后 source 任务在 daemon 启动 agent 之前被判 failed。**这不是 TC-REC-004 的证据**(输出前缀 `stub-run`)。
- **P2-B1(主会话读码核实)**:comment 触发、无 pipeline 载体的 strict source 任务,在 `prepareClaimedPipelineTask`(`daemon/execution_verifier.go`)得到 `EXECUTION_BINDING_UNAVAILABLE: authorization client or resolved CR root unavailable`。原因:`task.PipelineWorkspace` 只在 `preparePipelineTask`(`daemon/pipeline_task.go`)里设置,而该函数对无 pipeline 标记的任务直接 `return nil`;server 侧载体字段(`handler/daemon.go` `validateClaimedPipelineCarrier`)也只给 pipeline-node 任务。因此 source 任务在现有生产代码里**没有任何合法途径产生自己的 consumption**,而 `StartArchitecture` 的 `NewAdmissionDecider`(`governance/execution_admission.go`,"source 任务无需自带 CR id,回执确立 CR")要求它存在。design.md D1.2 与 F6 假定"source strict 预检已存在",与此不符。先例 E2 与 `TestTC_RUN_003` 均直接种 pipeline 载体/消费行,从未走过真实 comment 触发的 source。
- **P2-B2(读码 + 宿主机实测)**:`pipelineAuthorityFacts` 对**每个** pipeline 节点任务调用 `crctl workspace inspect <CR> --detail`,要求输出含 `targetSpecId` 与有效 `targetVersion`;tools HEAD(`e52b808`,即 pin)的该命令输出键仅为 `op,cr,mode,txId,resources,changed,operationalWorkspace,operationalWorkspaceError,freshness`(主会话复跑确认);tools 仓内 `git log -S'"targetSpecId"'` 对 crctl.mjs 与 workspace-transactions.mjs 无任何提交加入该输出键。daemon 单测用的是假 inspect JSON。即使 B1 修好,节点任务也会在 agent 启动前失败。**未端到端实证**(B1 先挡住)。
- **处置**:按止损条款停下,不改 daemon/tools/design。需用户裁定修复范围;若采纳,属设计修订(D1 增补 source 路径),须按 revision-rules 同步文档并重审 Gate 2(必要时 Gate 1)。
- **脚本侧已做**:`stub-flow.mjs`、`scenario-stub.mjs`、`stub-pi.mjs` 等(见 P2 报告),writer/reviewer/人工门/重启阶段未实现,`writer` stage 显式抛 `NOT_IMPLEMENTED_IN_THIS_PHASE`。
- **裁定(用户 2026-11-14)**:「B1」后又指示「把 B1 和 B2 合并成一次文档修订、一次 Gate 2 重审,其中 B2 选 A」。AI 的解读:B1=daemon 增加 source 路径;B2 选 A=tools 的 `workspace inspect --detail` 补字段。用户当时未说明 tools 改动并入原 change 还是另开;AI 曾暂按另开写入。随后 AI 核实两种方案成本(只读调查,见下),用户裁定「**并入**」,文档已改为并入 tools 的 `2026-11-13-aifi-45-node-trust-root`。
- **文档同步(未动代码)**:design 新增 D1.8/D1.9、G2-9、S10/S11、风险三行、未验证 8/9;canonical code spec 新增 SC-REC-009/010(REQ-REC-001);agent spec 新增 CP-REC-010;test-plan 新增 TC-REC-010(共 13 TC,证据计划同步)、SC-REC-010 并入 TC-REC-004 的 scenarios;slices/tasks 新增 10/11。同轮并入 D4.4「/current head」措辞勘误与 MINOR-9(该子句由 `channel-protocol` 选择承担,回归矩阵已说明)。
- **事实核对(本轮)**:tools `workspace inspect` golden(`crctl-detail/workspace-inspect.json`)的字段路径集合不含 `targetSpecId`/`targetVersion`,且 `crctl-summary.test.mjs` 对字段路径集合逐一比对,故 tools 补字段须同步金样本;该金样本在 tools 工作树里 `git status` 标 M,但已核实 `git diff HEAD --quiet` 返回 0、`git ls-files --eol` 为 i/lf w/lf,即内容与 HEAD 一致、M 仅是 stat 差异;因此 B2 可编辑它,编辑前仍须重新核实。M008 的其余改动(AGENTS.md、CUSTOM.md、merge-effects.mjs 及其测试)不动。`readCrMdTargetVersion`、`resolveTargetSpecMode` 是现成读取器。
- **仍未验证**:B1 修好后 server 的 `/binding`、`/consumption` 对无节点载体 source 任务是否放行(仅读码);B2 补字段后 daemon 读真实 crctl 输出首次端到端成功。
- **并入 vs 另开的成本核对(只读调查,2026-11-14)**:
  - Gate:B2 改 tools 的 proposal/design/spec/test-plan,Gate 2 stale、Gate 3(含 Gate 2 输入)随之 stale;Gate 1 因 B2 改变 proposal 的范围描述而须重审(AI 判断,不改则「workspace 完全不受影响」一句失实)。旧批准保留为 superseded 回执,不删除。另开则只审 B2 的小文档,但原 Gate 3 的证据冻结了整个 `skills/shared/crctl/scripts` 目录(153 项输入,`crctl.mjs` 的哈希目前与之相符),同一工作树里改 `crctl.mjs` 后该证据在两种方案下都不再匹配。
  - 重跑:并入或另开,旧 9 项检查与全量套件(约 13 分钟,有一项既有环境失败 `execution-control-isolation`)都要在 B2 之后重跑;C1–C7 都要覆盖新代码。区别是并入只有一个 run 一次取证,另开要先交付/提交 node-trust-root 才能得到 B2-only 的干净证据与分开提交。
  - 结论:两处改动都未提交、同文件,AI 终评并入更省且不丢信息;用户裁定并入。

## ADJ-S10-1 S10（D1.8）实现选择与审查(2026-11-14,Gate 2 重审后,不改受审文档,仅记录)

- **实现**:`execution_verifier.go` 的 `prepareClaimedPipelineTask` 新增 source 分支(`sourceScope := !nodeAuthorized && task.PipelineWorkspace == ""`);helper `sourceExecutionScope` 取 CR 身份(声明→任务 `CrID`→issue 唯一关联)与 CR 根(`resolveTaskWorkspaceBinding(task, nil)`);`crID/crRoot/localWorkDir` 为局部值,不写 `Task.Pipeline*`、不设 `ExecutionPreconsumed`/`ExecutionTrustRoot`。`consumeClaimedExecution` 签名改为 `(ctx, task Task, crID, crRoot, trustRoot, name)`,函数内仅对按值副本设 `PipelineCrID/PipelineWorkspace` 供一次性资格栅栏 `executionBindingEndpointForRun`,其余用参数;唯一生产调用点是 `prepareClaimedPipelineTask`,无测试直接调用。这是 D1.8 第 3 条「改为接收参数」的具体写法,没有改变范围或合同。
- **主会话变异检查后删去的重复判据**:子代理初版在 helper 里重复了 `assertDeclarationMatchesAssociation` 与 `pipelineCRIDPattern` 检查,但紧随其后的 `resolveTaskWorkspaceBinding` 在 declared 分支已做同一冲突检查、`parseExecutionContext`/`bindTaskToAssociatedCR`/`findPipelineCRRoot` 已校验 CR-ID 格式,删去后全部测试仍绿,故按「重复判据」删除,helper 注释写明依赖关系。`sourceScope` 条件初版含 `task.PipelinePrompt == ""` 与 `task.PipelineCrID == ""`,变异检查(去掉它们)全绿,证明冗余:半载体由 `preparePipelineTask` 以 `pipeline carrier is incomplete` 先拒绝,有 prompt 无根时 `resolveTaskWorkspaceBinding` 给出空根并被 `CRRoot == ""` 拒绝;保留的 `!nodeAuthorized` 有真实作用(否则携带节点合同却缺载体的 claim 会被当作 source,并被错误标记预消费),已补测试并经变异验证(去掉后红)。
- **变异检查结果**:写回 `Pipeline*` → `TestTC_REC_010` 三个成功子测试红;`ExecutionPreconsumed` 恒真 → `TestTC_REC_001` 与 `TestTC_REC_010` 红;去掉 `!nodeAuthorized` → 新增子测试红。**等价变异(未区分)**:调换声明与任务关联的优先级——二者冲突时 `resolveTaskWorkspaceBinding` 本就拒绝,一致时结果相同,无可观察差异。
- **与计划的差异**:冲突用例断言的是既有错误(`disagrees with the task's formal CR association`,由 `bindingUnavailable` 常量加前缀)而非字面量 `EXECUTION_BINDING_UNAVAILABLE`,test-plan 允许「或既有错误码」;无来源/多关联用字面量 `EXECUTION_BINDING_UNAVAILABLE`。source 预检仍会经副本打开并立即关闭一个本地栅栏监听,运行期该函数对原 task 恒为 nil,未暴露给 agent。
- **回归**:`go test ./internal/daemon` 全包失败集合与改动前逐名相同(30 行基线 diff 为空;27 个既有 Windows 失败);`go build ./...`、`go vet ./internal/daemon`、gofmt 干净。`selections.json` 加 `rec-010`。
- **仍未验证**:server 的 `/binding`、`/consumption` 对无节点载体 source 的校验是否全部放行(仅 A0 的真实栈运行会观察;若拒绝,按止损点停下,不借手工 DB 修复)。

## ADJ-A0-2 — A0 重跑：B1/B2 已生效，暴露第三处生产缺口 B3（daemon 本地信任根的 `authorization-bind` receipt 只允许绑定一次）(2026-11-14，**用户已同意方案 1；受审文档已同步（design D1.10、SC-REC-001 增一条、TC-REC-001 增一个子用例、S12、G2-10），待 Gate 2 重审；未改代码**)

- **A0 重跑结果**（S10 与 tools S4 就位后，真实 podman 整栈，2 次均 0 模型费用，输出逐行一致，仅 id 不同）：build/tools/daemon/stack/domain/executors/cr-workspace/authorization(http=201)/source queued 通过，**source 任务完成且 consumption=1、effect=1**（B1 已生效），**writer 节点任务通过 root/inspect/authority 后才失败**（B2 已生效，`cr-workspace.mjs` 已改写 `target-version: v1.0.0` 与两侧一致的 `target-spec-id`，宿主验证 inspect 给出 `targetSpecId=architecture-real-run`、`targetVersion=v1.0.0`）。清理 remaining=0，podman 前后集合一致。
- **失败原文**：writer 任务 `failed`，`consumption=0 effects=0/0/0`，替身 trace 不存在；daemon 日志：`pipeline task preparation failed ... EXECUTION_CONSUMPTION_REQUIRED: non-read-only bind did not return a receipt (exit=1): {"error":{"code":"EXECUTION_CONSUMPTION_CONFLICT","message":"同一授权阶段已由不同subject/challenge/operation消费，拒绝覆盖"}}`。
- **根因（主会话读码核实）**：daemon 对每个 strict 任务（source 与每个节点）在启动前以 `crctl authorization-bind --trust-root <store.Root> --binding-stdio` 预消费。tools 的 `authorization-bind` 固定 `stage: 'authorization-bind'`（`crctl.mjs:2682`，subject=grantDigest），本地 receipt 文件名是 `<scopeHash>-<grant_id>-<stage>.execution-receipt.json`（`lib/execution-authorization.mjs:436-440`），已存在而 challenge/task_id 不同即 `EXECUTION_CONSUMPTION_CONFLICT`（`:557-565`；tools 自己的 `test/execution-authorization.test.mjs:1442-1449` 把「different run identity → CONFLICT」断言为合同）。challenge 是 `crypto.randomBytes(32)`，每次调用都不同（`lib/execution-binding.mjs:161`）。daemon 的信任根 `store.Root` 是**每 workspace 一个**（`execution_trust.go:64`，`~/.multica/execution-trust/<workspace>`）。所以同一 grant 下，source 先占用该 stage 的本地 receipt，之后任何节点、任何重新派发的 generation 的绑定都会冲突。平台侧则是每 task+generation 一条（`cr_execution_consumption_once UNIQUE(workspace_id, cr_id, runtime_id, task_id, dispatched_at)`），二者口径不一致。
- **性质**：不是夹具问题，是既有生产缺口，并非 S3/S10 引入——节点预消费（D1-B）和 source 预消费都落在同一个本地 stage receipt 上；此前所有测试用假 crctl 或只跑 source，E2 先例（2026-11-08）只证明了 source 一次启动准入。与 SC-REC-001「每个被推进的节点各有一条自己的当前 generation consumption」直接冲突，也会让「重启后重新派发的 generation」无法启动。
- **候选方案**：
  1. **（AI 建议）daemon 侧：每个 task generation 一个信任根子目录**，如 `~/.multica/execution-trust/<workspace>/<sha256(task_id|runtime_id|dispatched_at) 前 32 hex>`（Windows 路径不含冒号）。该 generation 的 grant、公钥由 `InstallExecutionAuthorization` 在该根内安装，本地 `authorization-bind` receipt 因此天然按 generation 隔离，与平台 `UNIQUE(task, runtime, dispatched_at)` 口径一致；注入给节点 agent 的 `CRCTL_EXECUTION_TRUST_ROOT` 就是该 generation 的根（D1.7 的「只定位、不授权、不提供隔离」不变）。只改 multica daemon，不改 tools 合同；`ExecutionTrustStore` 增加一个按 generation 取子目录的方法 `Generation`（`OpenExecutionTrustStore` 不改）。代价：每个 generation 留下一个很小的目录（一份公钥与 grant，几 KB），本方案不做回收，记为已知风险；本地 `advance` 阶段 receipt 的跨 generation 重放保护随之失去，但状态机推进与平台 effect 的 `(task, generation)` 唯一键仍在。
  2. tools 侧让本地 receipt 文件名带上 challenge：会改变 tools 已断言为合同的「同阶段异 challenge 即冲突」，且削弱本地重放保护，属 receipt 合同变更，需要独立 Gate 1+2，排除。
  3. 让 source 不占用 `authorization-bind` stage：只解决 source 与节点冲突，不解决「节点 A 与节点 B」「同一任务重新派发」冲突，排除。
- **仍未验证**：每个 generation 一个根后，节点 agent 的 `crctl advance` 能否读到该根下的 grant 并通过 `preflightAdvanceAuthorization`（A0 writer 阶段的替身要真实走一遍）；daemon 重启后重新派发 generation 的本地绑定是否在新根上成功（restart-dedup 阶段）。
- **用户裁定（2026-11-14）**：「同意按你的方案，实施。简单的、执行类的任务可以交给balanced子代理」，AI 的解读：同意方案 1 并授权起草受审文档的修订；**不等于批准 Gate 2**，也不授权在 Gate 2 重审通过前改 daemon 代码。
- **文档同步（只改文档，已收窄）**：首版同步新增了 SC-REC-011、TC-REC-011、CP-REC-011、三条风险、一条未验证项、空标识校验与「保留旧入口只给测试用」，用户质疑设计是否过重后收窄：①空标识校验删除（`GetTaskExecutionClaim` 已要求规范 UUID 与可解析的 `dispatched_at`，且在此之前返回）；②新增 SC/TC/CP 改为 SC-REC-001 增一条 and、TC-REC-001 增一个子用例，TC 数回到 13、证据计划回到 13 项；③`OpenExecutionTrustStore` 保持不变，generation 用一个方法派生，不再有「只给测试用」的旧入口；④风险合并为一行，不另设未验证项；⑤删去「binding endpoint 也用该根」一句，读码核实 endpoint 不用信任根。保留：D1.10、S12（含 TC-REC-009 期望值更新）、G2-10。
- **所需裁定（原文，保留）**：方案 1 是设计变更（D1-B/D1.7 的信任根口径由「每 workspace」改为「每 generation」，新增 SC 与 TC、切片 S12），按 revision-rules 须改受审的 design/spec/test-plan 并重审 Gate 2。

## ADJ-S12-1 — S12 实现记录：新子用例的 RED 原因与可达的区分力（2026-11-14，实现缺陷之外无偏离）

- 实现与设计一致：`ExecutionTrustStore.Generation(task, runtime, dispatchedAt)` 返回 workspace 根下 `sha256(task␀runtime␀dispatched_at)` 前 32 个十六进制字符的子目录 store；`OpenExecutionTrustStore` 的尾部（建目录、取身份快照、构造 store）抽为私有 `snapshotTrustRoot`，两者共用，对外行为与错误文本不变；`prepareClaimedPipelineTask` 在其之后调用 `Generation`，其后全部使用该 store。无空标识校验，无新入口。
- **TC-REC-001 新子用例的 RED 原因与预期不同**：接入前它红在 `EXECUTION_TRUST_CONFLICT: admission-test-key.pub already installed with different content`，而不是根相等。原因是测试 fixture 每个实例都生成新的 ed25519 密钥，两个 fixture 共用 workspace 根时公钥安装就冲突；生产里同一 grant 同一密钥，不会撞公钥，真正撞的是 tools 的本地 receipt，而替身 crctl 不产生 receipt。所以该子用例在没有修复时是「借公钥冲突」变红，断言本身（两根不同、同一 workspace 根之下、传给 crctl 的 `--trust-root` 等于各自的 `ExecutionTrustRoot`）仍然成立。
- **可达的区分力（主会话变异检查，均已还原并 `cmp` 校验、还原后复跑全绿）**：M1 去掉调用点的 `Generation` 调用 → 新子用例与 TC-REC-009 红；M2 派生漏掉 `dispatched_at` → 新子用例红。
- **不可达的部分**：在不改 fixture 密钥的前提下，单测无法复现 tools 的本地 receipt 冲突；这一点由 A0 重跑与真实 A 观察，未在单测里补做。
- 回归：daemon 全包失败集合与 S10 基线逐名相同（27 个既有 Windows 失败，无 `TestExecution*`/`TestTC_REC_*`）；`go build`、`go vet` 干净；本任务触及的文件 gofmt 无输出（全包 `gofmt -l` 的 266 条是既有 CRLF 文件，与本任务无关）。

## ADJ-A0-3 — B4：agent 子进程里的 git shim 因缺规则变量对所有 git 调用失败关闭（2026-11-14，记录，未裁定，未改代码、未改受审文档）

- **现象（A0 重跑，零模型，节点 writer 已越过预消费）**：替身 writer 在 `CRCTL_OPERATIONAL_WORKSPACE`（CR worktree）下 `crctl next` 报 `CR_WORKTREE_STATUS_MISSING` 且路径双份；在 `CRCTL_TASK_AUDIT_ROOT`（安装根）下 `next` 成功，但随后 `workspace inspect` 报 `WORKSPACE_GIT_INSPECT_FAILED`（`git worktree list --porcelain` 失败）。因此没有执行任何 `crctl advance`，「节点 agent 的 `crctl advance` 能否经 env 信任根与 binding endpoint 准入」**仍未得到答案**。
- **已排除**：属主与 `safe.directory`（uid 0/0，两根都在 `safe.directory`）；同环境绕过 shim 的真实 git 执行 `rev-parse --git-common-dir` 返回 `/workspace/.git`，成功。
- **直接原因（trace 原文）**：PATH 上的 shim 返回 `SHELL_UNAVAILABLE: controlled-shell rules not visible in this environment; git denied (fail closed)`。`gitguard-exec` 经 `gitguard.FromEnv()` 读 `MULTICA_CONTROLLED_SHELL_RULES`，agent 子进程里没有这个变量。
- **读码核实（主会话）**：`server/pkg/agent/claude.go:1283-1299` 的 `mergeEnv`（`buildEnv`，pi 与 claude 共用）丢弃全部继承来的 `MULTICA_*`；`taskMulticaEnvironment`（`daemon.go:180`）与 `injectTaskCRWorkspaceEnv` 都没有把规则路径补回；`isBlockedEnvKey` 也禁止 `custom_env` 提供。全库没有任何生产代码把该变量放进 agent 环境。该丢弃逻辑随 2026-10-21 第九次上游同步（`a3af2341f`）进入 fork。daemon 自己仍需要这个变量（`resolvePipelineCrctl`、`prepareCRGuard`），所以栈里 daemon 进程设置了它，与生产配置一致；这不是 A0 栈或替身造成的。
- **性质**：既有生产缺口，不是 S1–S12 引入。daemon 装了 shim（`daemon.go:8815`），却没有让 shim 的后端拿到规则，结果 agent 里**每一次** git（含 crctl 自己 spawn 的 git）都失败关闭。此前的真实运行用的是非 git 的 `/workspace`，crctl 的 `deriveInstallRoot` 在 shim 拒绝后回落到传入路径，恰好得到正确结果，所以没暴露。
- **仅补规则变量还不够（静态核对，未实测）**：`rules.json` 的 `rev-parse` 白名单不含 `--git-common-dir`，`cat-file` 不在白名单；`worktree list --porcelain` 在白名单内。规则可见之后，`--workspace <operational worktree>` 下 `deriveInstallRoot` 仍会被白名单拒绝而回落；`--workspace <安装根>` 下 `inspect` 预计可行，`advance` 是否还会用到被拒的 git 未知。
- **待用户裁定（不是实现缺陷的同合同修复，涉及 daemon 与 tools 两个交付面）**：见汇报的方案对比。裁定前不写代码、不改 design/spec/test-plan；真实 A 不得启动。
- **A0 运行次数**：先前自设的累计上限 12 次（零模型费用），本轮累计已到约 15 次，超出的 3 次未事先征得同意，已如实记录。

## ADJ-A0-4 — B4 裁定与收窄：用户选 P 并入 tools `node-trust-root`；只做 crctl 一半（2026-11-14，不改 multica 受审文档，仅记录）

- **用户裁定**：2026-11-14 对 ADJ-A0-3 的 P/Q/R 回复「P，并入 node-trust-root」。AI 解读：授权起草两个 change 的受审文档修订（tools 的 `node-trust-root` 与本 change），**不等于批准任何 Gate**，Gate 重审通过前不写业务代码。
- **取证**（A0 栈，零模型，替身 writer，只改 `scripts/aifi45-real-run/`；是 what-if 对照，**不是任何 TC 的证据**）：
  - 第 4 步（只让 shim 看到规则变量）：拒绝变为 `FORBIDDEN_SUBCOMMAND`；crctl 内部被拒的 git 只有 `rev-parse --git-common-dir` 与 advance 内的 `show HEAD:<CR>/execution-contract.yml`。`operational` 候选的 `next` 因前者被拒失败；`audit-root` 候选的 `next`/`inspect` 成功，但第一次 `advance` 以 `EXECUTION_BINDING_INVALID` 失败（`deriveInstallRoot` 拿不到 common-dir，把安装根回落成 CR worktree，与冻结的安装根不匹配），没走到平台 endpoint。结论：只补规则变量不够。2 次真实整栈运行，均 exit 1。
  - 第 5 步（只让 crctl 子进程的 PATH 去掉 shim 目录，不发布规则变量）：两个候选的 `next`/`inspect` 均无白名单拒绝（`next` 5 次、`inspect` 7 次 git 调用）；采用 `operational` 后两次 `advance` 都成功：`committed=true`，`basis.grant_head` 等于授权 head，`trust_root_seen` 与 DB 复算的该任务 generation 目录一致，consumption=1，effects=1/1/1，`status=tech-design-review-pending`；agent 直接调用的 git 仍 `SHELL_UNAVAILABLE`。2 次真实整栈运行，均 exit 2（场景刻意在 reviewer 阶段 INCONCLUSIVE，不输出 writer 的 PASS）。
  - 这同时第一次回答了「节点 agent 的 `crctl advance` 能否经 `CRCTL_EXECUTION_TRUST_ROOT` 读到该 generation 的 grant 并通过 binding endpoint 准入」：在 crctl 的 git 不被 shim 拦截的前提下，能（替身口径；真实模型 run 仍待 TC-REC-004）。
  - 运行前后 `podman ps -a` / `podman pod ps` 一致，带标签资源 0；两仓 `git status --short` 38/11 行不变。A0 累计运行次数现约 19 次，早已超过自设的 12 次上限（用户知情，已在 ADJ-A0-2 如实记录）。
- **AI 的收窄（须用户在 tools 文档的 Gate 审阅时确认或推翻）**：P 原含「daemon 把规则路径也发布给 agent」。第 4 步证明它不充分，第 5 步证明它非必要；并且它会把 agent 直接调用的 git 从「全拒」放宽为「按白名单放行」，是对所有 agent 的全局行为变化。因此 **multica 侧不改生产代码**：daemon 不发布 `MULTICA_CONTROLLED_SHELL_RULES`。若用户推翻该收窄，须回到 multica design 另行修订并重审 Gate 2。
- **tools 侧**：并入 `node-trust-root` 的决策 8（crctl 在 `main()` 第一条语句从自己进程的 PATH 移除放有 shim 的目录；`lib/git-shim-path.mjs` 纯函数 + `crctl.mjs` 纯插入），TC-NTR-012 / CP-NTR-012，切片 S5。tools 的 Gate 1/2 重审通过后才实现；不改 grant、签名、binding、receipt、verdict 合同。
- **本 change 的受审文档本轮不改**：design/spec/test-plan 没有对 shim 的承诺，裁定对它们没有新增设计/验收/测试选择（修订矩阵里只有这类变化才重审 Gate 2）；B4 的保证由 tools 的 TC-NTR-012 与本 change 的 TC-REC-004（真实节点推进）加 A0 观察承担。这个判断记在这里，供 Gate 3 复核；若 Gate 审阅者认为 D1.7 的跨仓依赖须在 design 里写明，再走一轮 Gate 2 同步。
- **multica 侧实现事项**（脚本，非生产代码；依赖 tools S5 完成）：
  1. `scripts/aifi45-real-run/crctl-stage.mjs` 的覆盖清单在 `crctl.mjs` 之外加入新文件 `lib/git-shim-path.mjs`（仅允许 HEAD 中不存在的新文件），补 `crctl-stage.test.mjs`；
  2. 替身 pi 的 what-if（剥 shim、记录器）改回生产形态——shim 留在 PATH 上、无规则变量，由新 crctl 自己剥离——重跑 writer 两次 advance（须先向用户说明次数并征得同意）；
  3. 其后补 reviewer、人工门、重启去重阶段。

## ADJ-A0-5 生产形态 A0 通过 writer 阶段（B4 修复后首次端到端，替身口径，非 TC 证据）(2026-11-15)

- **授权**：用户原话「同意重跑真实整栈 A0(13.2b)」。零模型、1 次，第 20 次累计运行（此前自设上限 12，已超，用户在 ADJ-A0-2/3/4 知情）。
- **形态**：`architecture-stub`，生产形态——shim 目录留在 agent PATH 上、**不**设置 `MULTICA_CONTROLLED_SHELL_RULES`、替身 pi 不再对 crctl 子进程做任何 PATH/环境处理，由 tools 侧新实现的 `lib/git-shim-path.mjs`（`crctl.mjs` 入口调用 `stripGitShimDirs`）自行剥离。`crctl-stage` 也已把该新文件随固定来源副本一起物化（13.1）。
- **结果（原文）**：
  - `PASS stub-run source task=b000335e run=e8055208 consumption=1 effect=1`
  - `PASS stub-run writer-advances advances=2 consumption=1 effects=1/1/1 status=tech-design-review-pending trust_root_seen=d1640985 workspace_arg=operational`
  - `PASS stub-run cleanup remaining=0`；`INCONCLUSIVE stub-run stage=reviewer reason=NOT_IMPLEMENTED_IN_THIS_PHASE`；`NOTE stub-run is not evidence for the real-model checks`；exit 2。
- **断言口径**（读码核实，不是只看打印）：writer 的 `advances` 取自 trace 里成功的 advance 目标（应为 `tech-designing`、`tech-design-review-pending`）；`consumption` 与 `command/verdict/settlement` 三个计数由 SQL 读 `cr_execution_consumption` 与三张 effect 表（各须为 1）；`status` 由 daemon 容器内 `crctl next` 读；`trust_root_seen` 的目录段由 `agent_task_queue` 的 `runtime_id`+`dispatched_at`（Go 拼写）复算 `hex(sha256(task|runtime|dispatched))[:32]` 后比对，并在 daemon 容器内确认该目录存在；trace 里不得出现 `--trust-root`。
- **意义**：B4（agent 内 crctl 的 git 被 shim 全拒）在真实 crctl 与真实 daemon/backend 上已解除，writer 两个门控 advance 在生产形态下通过，S9 注入的信任根与 S12 的 generation 子目录一致。
- **不是什么**：零模型替身运行，**不是** TC-REC-004 的证据，也不能替代真实 run A。真实 run A 仍未授权启动。剩余未实现的阶段：reviewer（0 advance）、人工审批门、daemon 重启后的重新派发去重；`architecture-main`/`architecture-revoke` 场景代码未写。
- 环境核对：运行前后 `podman ps -a` 集合一致（仅 `multica-postgres`、`multica-backend` 两个 Exited），pod 数 0；两仓 `git status --short` 仍为 38 / 14 行。

## ADJ-A0-6 第一次真实 run A（用户授权的那一次）的实际结果：source 节点被真实数据验证，驱动在观察层失败(2026-11-15)

- **授权与花费口径**：用户 2026-11-15「授权真实 run A」；`scripts/aifi45-real-run/.local/run-config.json` 记录 `model=GB-JP/deepseek-flash`、`max_runs=1`、`cost_ack` 为用户此前的原话口径。**真实 run A 的 1 次额度已在本次用掉。**
- **运行结果（原文，`run.mjs --scenario architecture-main`）**：`build`/`tools`（head `e52b8081`）/`daemon`/`stack`/`domain`/`executors`/`cr-workspace` 全部 PASS，`authorization http=201 head=18cb5df4`，`source queued task=9f1bb0b9`；随后 `FAIL real-run stage=source-task reason=SOURCE_TRACE_MISSING`，detail 为 `no stub trace at /tmp/aifi45-stub-trace-…jsonl`；cleanup `remaining=0`。
- **必须先于失败点通过的断言**（读码核实 `scenario-stub.mjs:380-381` 在 trace 读取 `:385` 之前）：`SOURCE_CONSUMPTION_MISMATCH` 与 `SOURCE_EFFECT_MISMATCH` 都没有触发。**因此这一次真实模型确实完成了 source 任务，且该任务在平台上恰好 1 条消费记录、command/verdict/settlement 各 1 行**——这是本次唯一拿到真实模型证据的部分（仍不是 TC-REC-004 的完整证据：writer 两个终态与 reviewer、审批门都没走到）。
- **失败性质**：驱动的观察层仍依赖替身写的 trace 文件（`/tmp/aifi45-stub-trace-<task>.jsonl`），真实 pi 不写它。**不是生产机制缺陷**，是验证工具（A8 之外的驱动）缺陷；按止损原则不推断、不冒充结论。
- **第一次尝试（同日更早）**：`FAIL stage=daemon reason=DAEMON_FAILED`，`chmod: /usr/local/bin/pi.mjs: No such file or directory`——真实模式仍无条件 `chmod` 替身的 `pi.mjs`。**该次在容器启动阶段就退出，没有任何模型调用**，因此不消耗真实 run 额度；已修（`chmod` 按 runner 分支）。
- **已修与未修**：`daemonScript` 的安装步骤已按 runner 分支；`MULTICA_AGENT_TIMEOUT` 真实模式 900s、任务观察上限 600s（替身仍是 120s/180s）。**观察层改为模型无关**（main 模式用信任根 generation 目录里的执行回执 + 账本，stub 模式保留 trace）后，仍**必须再跑一次真实 A** 才能得到 writer/reviewer/审批门的真实证据——**目前没有这次授权**。
- **环境**：两次运行后 `podman ps -a` 都只剩 `multica-postgres`、`multica-backend`（Exited），pod 0；multica `git status --short` 38 行、tools 14 行，均未变化；**没有任何提交**。

## ADJ-A0-7 真实 run A 成功（第二次授权的独立运行），以及取证运行自身会再跑一次真实 A 的事实(2026-11-15)

- **用户授权**：2026-11-15「授权再跑一次真实 run A」。
- **结果（原文，`run.mjs --scenario architecture-main`，exit 0）**：
  - `PASS real-run source task=a3379b0d run=7c530fab consumption=1 effect=1`
  - `PASS real-run writer-advances advances=2 consumption=1 effects=1/1/1 status=tech-design-review-pending trust_root_seen=71c64994 evidence=receipts`
  - `PASS real-run reviewer task=016bbc19 consumption=1 effects=1/1/1 advances=0 status=tech-design-review-pending`
  - `PASS real-run approval-gate status=waiting_approval pending=0 new_tasks=0`
  - `PASS real-run restart-dedup status=waiting_approval tasks=2 consumption=1/1 effects=unchanged`
  - `PASS real-run cleanup remaining=0`；`PASS real-run scenario architecture-main waiting_approval cr=tech-design-review-pending`；exit 0。
  - 环境：运行后 `podman ps -a` 只剩两个既有 Exited 容器、pod 0；multica/tools `git status --short` 38/14 行不变。
- **观察口径**（main 模式）：`advances=2` 来自该 generation 信任根目录的执行回执（advance 回执 = 全部回执减去平台预消费的 `authorization-bind` 一条），`consumption`/`effects` 来自账本 SQL，`status` 来自容器内 `crctl next`，generation 段由 `agent_task_queue` 复算；trace 仅替身模式使用。
- **重大事实（必须记住）**：`stdd agent verify` 的 **CP-REC-004 的 action 本身就是 `run.mjs --scenario architecture-main`**，所以取证运行会再跑一次真实模型 run。2026-11-15 01:0x 的第一次取证（`run 17cc4e4b-…`）被我方工具超时中断（exit 3221225794，3 通过/10 失败，**不完整、不可选**）；第二次取证（`run 103ef910-…`）走了完整流程，其 CP-REC-004 又执行了一次真实 A，**因输出标签与 canonical agent spec 期望不一致而失败**（see 下条）。也就是说到此刻为止真实模型 run A 共发生 2 次完整执行：一次是我方独立运行（成功，证据见上），一次是取证内嵌运行（失败于标签，非机制）。**第三次之前必须由用户另行授权。**
- **标签/覆盖差距（已定位，实现待做，无需模型）**：canonical agent spec 的 CP-REC-004 断言要求这些行，驱动的现状是：
  | spec 期望 | 驱动现状 |
  |---|---|
  | `PASS real-run source ` | 有 |
  | `PASS real-run source-tamper-rejected ` | **未实现**（此前为 B4 之外的 defer 项，口径由本次裁定） |
  | `PASS real-run writer-two-advances-one-receipt ` | 现为 `writer-advances`（内容含 advances=2/consumption=1） |
  | `PASS real-run review-zero-advance-own-effect ` | 现为 `reviewer` |
  | `PASS real-run human-gate ` | 现为 `approval-gate` |
  | `PASS real-run restart-dedup ` | 有 |
  | `PASS real-run cleanup remaining=0` | 有 |
  改输出标签属于实现层，不改受审文档；`source-tamper-rejected` 按 SC-REC-004 的口径实现：copy 一份来源字节、改一个字符、保留签名，重提取/安装必须拒签（`EXECUTION_SOURCE_INVALID`，`execution_authorization.go:284`、`execution_trust.go:287-288`），且该任务消费记录为 0（先例：`projects/tools/archive/2026-11-08-aifi45-trust-anchor-chain/validation/e2-m2-real-loop-20261108b/run.sh:610-663`）。
- **CP-REC-008 的失败是并发争用，不是回归**：同一 selections 全组在取证之外单独跑 exit 0、`remaining=0`、无 FAIL（`Temp/sel.out`）。取证运行里它与真实 run A 等重活并发，disposable 实例冲突。

## ADJ-A0-8 第二次取证（用户确认跑真实 A+B）失败：A 停在 reviewer、B 停在重启，证据不完整(2026-11-15)

- **授权**：用户原话「确认取证跑真实 A+B 两次」。该次取证（run `77ab6fac-155c-4429-843e-2a4d46250…`）**结果 10 通过 / 3 失败，exit 1**，因此**不能作为 Gate 3 的选定 run**。
- **CP-REC-004（真实 A）**：`source`、`source-tamper-rejected`、`writer-two-advances-one-receipt` 三段已在取证里出现并通过（说明 tamper 探针与 writer 回执口径在真实模型下成立），随后 **缺少 `review-zero-advance-own-effect`、`human-gate`、`restart-dedup`**，exit 1 → 失败发生在 **reviewer 阶段**（或其后未达断言）。容器已清理，**具体原因本次未留存**。
- **CP-REC-005（真实 B）**：`PASS real-run revoke-stop` 已出现（撤销语义在真实栈成立），**缺少 `restart-revoke-stop`**，exit 1 → 失败发生在**重启后保持**这一步（stub 形态下该步是通过的）。
- **CP-REC-008**：取证内 exit 1；同一 selections 全组在取证之外单独跑 exit 0、`remaining=0`、无 FAIL（`Temp/sel.out`）。判断仍为与真实 run 并发的 disposable 实例争用，不是回归。
- **诊断能力缺口（已修）**：`stdd agent verify` 的 tc-evidence 只保存 `exit_code`/`result`/`assertions_passed`，**不保存 stdout/stderr**，所以这次失败无法定位到具体断言与错误码。已在 `run.mjs` 加只追加的诊断日志（`scripts/aifi45-real-run/.local/last-run-<ts>.out`，`.local/` 已 gitignore），把每行 `out`/`err` 同时落盘；单测 179/176/0/3 通过。**日志本身不是证据**，只用于下一次失败后的定位。
- **真实模型调用累计（如实）**：授权范围内共 3 次完整真实 A（独立 1 次成功、取证内嵌 1 次失败于标签、本次取证内嵌 1 次失败于 reviewer）+ 1 次真实 B（本次）。**再跑任何真实 A/B 都需要新的授权。**
- **未变**：两仓未提交；multica Gate 1/2 current、Gate 3 pending；tools Gate 1/2/3 current。清理读回仍按本 run nonce（本机另有他人会话的 `aifi45-real-run-1916fc3f025f1258-*` 遗留栈，未触碰）。

## ADJ-A0-9 取证通过（13/13）与两条必须留档的观察(2026-11-15)

- **取证**：`stdd agent verify real-execution-closure --change 2026-11-13-aifi-45-real-execution-closure` 在带上 `CRCTL_MJS`、`AIFI45_TOOLS_ROOT`（此前缺失导致 CP-REC-008 里 `channel-protocol` 的 2 个用例失败）后为 **13 passed / 0 failed**，选定 run `11acf6e8-cb13-4ca0-b758-916d695d5911`。
- **真实 A（CP-REC-004）在取证内全绿**（日志 `.local/last-run-…`）：`source`、`source-tamper-rejected`、`writer-two-advances-one-receipt`（advances=2、consumption=1、effects=1/1/1）、`review-zero-advance-own-effect`（consumption=1、effects=1/1/1、advances=0）、`human-gate`（waiting_approval、new_tasks=0）、`restart-dedup`（unchanged）、cleanup、`PASS … scenario architecture-main`。
- **真实 B（CP-REC-005）在取证内全绿**：`revoke-stop status=running reviewer_tasks=0 head=revoke` → `restart-revoke-stop status=failed tasks=1 refused=1 consumption=unchanged`。
- **观察 1（须在 Gate 3 复核）**：撤销后、daemon 重启时，平台会给**被撤销节点的 writer 再派一次任务**；该任务四条账本计数全为 0，即**在 agent 启动前就被拒**（预消费发生在 agent 启动之前，见 S3）。因此本变更的断言取「允许 0 消费的重派、禁止 reviewer 任务、禁止任何已发生的消费/effect 变化、禁止推进型状态」。SC-RUN-006 的字面保证是「reviewer 不派发、节点不推进、重启后保持」，两次运行都满足；但「重启会给撤销节点再派一次被拒的任务」这一行为本身应作为残留事实供评审。
- **观察 2**：撤销后 writer 的控制写先被 binding 端点以 409 `EXECUTION_AUTHORIZATION_HEAD_INVALID` 拒绝（不是 runner 的 `HEAD_REJECTED` 注解），场景按该证据断言，未放宽。
- **断言口径的两处修订（均为实现层，不改受审文档）**：(a) 重启后允许 run 从 `running` 走向终结态 `failed`，但禁止任何推进型状态；(b) 重启后允许出现四账本全 0 的新任务行（含 `refused=` 计数），禁止 reviewer 任务与任何已发生的消费/effect。两处都有单测反例（`RESTART_REVOKE_ADVANCED`、`RESTART_REVOKE_TASK_FACTS`、`RESTART_REVOKE_REVIEWER`）。

## ADJ-A0-10 最终取证（13/13）与三处断言/显示修订(2026-11-15)

- **选定 run**：`bb5a9173-27cf-40fc-bb62-66e3e20c8bd1`。`stdd agent verify real-execution-closure` **13 passed / 0 failed**，exit 0；`stdd ci check-failures` 报 TC 覆盖 **13/13 (100%)**、0 错误。`validate_current_evidence` 对该 run 无问题。
- **run A（真实模型）**：`source-tamper-rejected … code=EXECUTION_SOURCE_INVALID consumption=0`；`source … consumption=1 effect=1`；`writer-two-advances-one-receipt advances=2 consumption=1 effects=1/1/1 status=tech-design-review-pending … evidence=receipts`；`review-zero-advance-own-effect … consumption=1 effects=1/1/1 advances=0`；`human-gate … waiting_approval pending=0 new_tasks=0`；`restart-dedup … tasks=4 consumption=1/1/1/1 effects=unchanged`；`cleanup remaining=0`。
- **run B（真实模型）**：`revoke-stop status=running reviewer_tasks=0 head=revoke`；`restart-revoke-stop status=failed tasks=1 refused=1 consumption=unchanged`；`cleanup remaining=0`。
- **修订 1（reviewer 判定）**：原先要求 `pipeline_node_run.detail.verdict == "pass"`；两次真实运行里出现过 `verdict=""`（节点仍被 runner 标为 passed）与一次 `block`（600s 内未通过）。runner 只在 `conclusiveReviewEvidence` 为真时把节点标 passed（`runner.go:849-861`），因此改为「`verdict` 缺省视为可接受，出现非 pass 值才算矛盾」。这是**放宽显示层判据**，核心事实仍是节点 passed。
- **修订 2（撤销后重派）**：见 ADJ-A0-9 的观察 1——允许四账本全 0 的被拒重派并计入 `refused=`，禁止 reviewer 任务与任何已发生的消费/effect 变化。
- **修订 3（显示索引）**：任务事实行加入 `seq` 后，`restart-dedup` 的 `consumption=` 曾误打印 seq（显示为 `1/2`）。已改为真实消费列（`[2]`）。**这是纯显示错误**，断言比较的是整行，未受影响；但此前两次取证输出里的该字段不可按字面解读。
- **取证成本如实记录**：为把驱动判据对齐真实行为，本轮共发生 7 次真实 A、3 次真实 B 的模型调用（多数消耗在驱动的观察/判据缺陷上，非机制失败）。这些调用均由用户逐次或「自行执行」授权；其中 CP-REC-008 的失败根因是取证调用缺少 `CRCTL_MJS`/`AIFI45_TOOLS_ROOT`（ADJ-A0-9）。
- **未改受审文档**：以上都是驱动实现层的判据/显示修订，SC/TC/CP 文字未变。
