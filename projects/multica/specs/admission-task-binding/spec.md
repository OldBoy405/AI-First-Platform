# Spec: admission-task-binding

> Change: 2026-11-11-aifi-45-admission-task-binding（最新修订并入 2026-11-17-execution-admission-simplification） | Auto-generated Human View

## Requirements

> 修订 2026-11-18（change 2026-11-17-execution-admission-simplification）：准入判定改为只读 CR 当前执行授权头，本文件下方各节保留原文作为历史基线，其准入触发条件按下列对应关系取代或修订——SC-ATB-001～004（锚点 task 与 generation 的回执/effect 准入）→ 由 SC-ATB-101～104 取代；SC-ATB-005～007（按动作取锚点 task）→ 由 SC-ATB-101、SC-ATB-102、SC-ATB-108 取代；SC-ATB-008～009（路由提交后不自唤醒、发现路径推进、重复发现不重复派发）→ 语义改由 SC-ATB-106、SC-ATB-107 承接；SC-ATB-010（同 generation 重放与新 generation）→ 保留写入语义，删去「准入随之 WAIT_CONSUMPTION/ADMITTED」；consumption/effect 写入路径本身未改（SC-ATB-109）。下文 SC-ATB-004 要求「完整 effect 链才 ADMITTED」已不再成立，以 SC-ATB-102 为准。

### Requirement: 准入判定只以调用方指名的锚点 task 及其当前 generation 为输入 （原文；准入触发条件已由 SC-ATB-101～104 取代）：回执与可信 effect 必须都属于该 task 与该 CR，不借用 CR 内其他 task、其他 CR 或旧 generation 的消费事实。原因集合不扩充。

#### Scenario: SC-ATB-001

- **GIVEN** 准入请求的 TaskID 为空、不是 UUID，或指向不存在、属于其他 workspace、尚无当前 generation（runtime_id 或 dispatched_at 为 NULL）的 task；该 CR 内另有一个 task 已具备完整回执与可信 effect。
- **WHEN** DecideAdmission 被调用。
- **THEN** SHALL 对空和畸形 TaskID 返回 ErrAdmissionInvalid（调用方错误，不是等待原因）；对其余三种情形返回 WAIT_CONSUMPTION，且均不放行。
- **AND** 另一个 task 的完整链不改变上述任一结果。

#### Scenario: SC-ATB-002

- **GIVEN** 锚点 task T1 已认领（当前 generation G1）；CR 内的消费事实只有以下之一：他 task T0 的回执与 effect；T1 旧 generation 的回执（T1 随后被重新认领）；其他 CR 名下对 T1 的回执。
- **WHEN** 以 T1 为锚点调用 DecideAdmission。
- **THEN** SHALL 对每种情形分别返回 WAIT_CONSUMPTION，不放行。

#### Scenario: SC-ATB-003

- **GIVEN** T1 的当前 generation 回执已存在，但 T1 自己缺少 effect 结算、verdict、覆盖其 seq 的 cursor 或 command 之一；T0 具备完整链。
- **WHEN** 以 T1 为锚点调用 DecideAdmission。
- **THEN** SHALL 对每种缺失分别返回 WAIT_TRUSTED_T_COMMIT，不借用 T0 的链。

#### Scenario: SC-ATB-004

- **GIVEN** T1 的当前 generation 回执与它自己的完整可信 effect 链都存在，授权头为 approve。
- **WHEN** 以 T1 为锚点调用 DecideAdmission。
- **THEN** SHALL 返回 ADMITTED。
- **AND** 同样的链若 verdict 载荷畸形、effect 字段不是 effect、签名 scope 与其 store/lineage 不符或 command_digest 与 command 字节不符，SHALL 返回 WAIT_TRUSTED_T_COMMIT。
- **AND** 授权头缺失仍为 HEAD_UNAVAILABLE，非 approve 仍为 HEAD_REJECTED；不新增任何原因。

### Requirement: Runner 按各动作自己的快照给出锚点 （原文；按动作取锚点已由 SC-ATB-101、102、108 取代）（授权头、回执、当前 generation 与 effect 由 decider 在头锁内读取）：完成有 own-task 的节点锚定其当前选中任务；派发（含首个节点）、人工门及无 own-task 的完成锚定 run 的 source task。首次派发不要求尚不存在的节点任务先有消费。准入锚点与入队归因取同一个值。

#### Scenario: SC-ATB-005

- **GIVEN** 节点 N 有自己的任务 T_N 且已完成；run 的 source task S 已有完整回执与 effect，T_N 没有。
- **WHEN** Runner 尝试把 N 标为 passed。
- **THEN** SHALL 不放行并保持节点原状态；T_N 当前 generation 的回执与它自己的 effect 提交后才放行。
- **AND** 他 task 或 source 的消费不得放行该节点。
- **AND** 重试：T_N 已消费并完成后产生更新的子任务 T_N2（继承父任务关系）时，以 T_N2 为锚点；T_N 的消费不放行，T_N2 自己消费后才放行，重复调用不产生额外状态变化。

#### Scenario: SC-ATB-006

- **GIVEN** 节点没有自己的任务（架构复审跳过 writer、需求 review 取投影证据）或是人工门节点；S 的消费状态分别为缺失与完整，另有他 task 的完整消费。
- **WHEN** Runner 尝试把该节点标为 passed 或通过人工门。
- **THEN** SHALL 仅当 S 当前 generation 的回执与 S 自己的 effect 完整时放行；他 task 的消费不放行。

#### Scenario: SC-ATB-007

- **GIVEN** 架构或需求 run 刚注册，首个节点任务尚不存在；S 的回执与 effect 分别缺失与完整，另有他 task 的完整消费。
- **WHEN** Runner 评估是否派发首个节点任务。
- **THEN** SHALL 仅在 S 的消费完整时派发；SHALL 不要求尚不存在的节点任务先有消费；他 task 的消费不放行派发。
- **AND** S 缺回执时只等待（node 的 wait_reason 为 admission），不创建任务也不使 run 失败。

### Requirement: 真实 consumption 路由提交后不自行唤醒 （原文；发现与幂等语义改由 SC-ATB-106、107 承接）；只由系统实际的发现路径（ResumeActiveRuns）推进，且重复发现不重复派发。同 task 的合法重放与新 generation 保持 M005 语义。

#### Scenario: SC-ATB-008

- **GIVEN** 架构（及需求）run 已注册，首个节点因 S 尚无消费而等待；S 的 consumption 经真实路由首次提交（201）。
- **WHEN** 路由提交之后、发现之前检查队列；随后先后执行两次 ResumeActiveRuns。
- **THEN** SHALL 在路由提交后、发现前没有节点任务；第一次发现后恰有一个首节点任务；第二次发现后 agent_task_queue 与 pipeline_node_run 的计数及首任务 id 都不变。

#### Scenario: SC-ATB-009

- **GIVEN** 首节点任务 T1 仍在运行（尚未完成）；其所属 run 的 source S 已消费，T1 尚无自己的回执。
- **WHEN** T1 在运行期间经真实 binding 与 consumption 路由首次消费（201）；随后 T1 完成，发现路径运行，并再运行一次。
- **THEN** SHALL 首节点在发现后 passed 并派发后续节点，且后续节点的派发不要求其任务预先消费；再次发现不产生新任务或状态变化。
- **AND** T1 完成但没有自己的回执时不放行，由 SC-ATB-005 验证；已完成的任务不能再经真实路由补消费，故不在本场景构造该顺序。

#### Scenario: SC-ATB-010

- **GIVEN** T1 已在 generation G1 消费。
- **WHEN** 同一 generation 重放提交；T1 被重新认领为 G2 后再提交。
- **THEN** SHALL 对同 generation 重放返回 200 且 changed=false，回执、command、verdict、settlement 行数均不变；G2 提交前准入为 WAIT_CONSUMPTION，提交后（201）回执 +1、command/verdict/settlement 均 +0，准入恢复为 ADMITTED。

### Requirement: Runner 对四类受保护动作（节点置 passed、人工门通过、普通节点入队、requirement 节点入队）的准入判定只以 CR 当前执行授权头为输入： 头存在、decision 为 approve、且与 workspace 和 CR 同属一个范围才放行；不再读取源任务或节点任务的 consumption 回执与 effect/verdict 链。

#### Scenario: SC-ATB-101

- **GIVEN** CR 没有执行授权头（头指针为 NULL）。
- **WHEN** Runner 对四类受保护动作各自尝试一次。
- **THEN** SHALL 对每一类都返回 HEAD_UNAVAILABLE 且不放行：不创建任务、不把节点置 passed、不通过人工门、不使 run 失败； 被拒节点的 detail.runner 为 wait_reason=admission 且 admission=HEAD_UNAVAILABLE。
- **AND** 公开的 reconcile 入口把该等待转成成功唤醒，而不是错误。

#### Scenario: SC-ATB-102

- **GIVEN** CR 的当前头是同 workspace、同 CR 的 approve 记录；run 的源任务和节点任务都没有任何 consumption 回执，也没有 effect、command、verdict、settlement。
- **WHEN** Runner 对四类受保护动作各自尝试一次。
- **THEN** SHALL 对每一类都返回 ADMITTED 并完成该动作的效果（入队、置 passed 或通过人工门）。
- **AND** 判定函数的请求只携带 workspace、CR 与意图，不再携带任何任务标识。

#### Scenario: SC-ATB-103

- **GIVEN** CR 的头已被撤销：指针指向 decision=reject 的记录。
- **WHEN** Runner 对四类受保护动作各自尝试一次。
- **THEN** SHALL 对每一类都返回 HEAD_REJECTED 且不放行，已完成的历史节点与任务不变。

#### Scenario: SC-ATB-104

- **GIVEN** CR 的头指针指向另一个 workspace 的 approve 记录，或同 workspace 内另一个 CR 的 approve 记录。
- **WHEN** Runner 对四类受保护动作各自尝试一次。
- **THEN** SHALL 按无头处理并返回 HEAD_UNAVAILABLE，不借用该记录的决定，不放行。
- **AND** 无效输入（非法 workspace 或 CR 标识、未知意图、空事务）仍返回请求无效错误，而不是拒绝原因。

### Requirement: 叫停与入队不交错；授权头签发本身不唤醒 Runner，由系统实际的发现路径（ResumeActiveRuns）推进；重复发现不重复派发。

#### Scenario: SC-ATB-105

- **GIVEN** 一次放行判定正持有 CR 的头锁，尚未完成其效果。
- **WHEN** 另一个独立连接发起撤销。
- **THEN** SHALL 使撤销等待到该效果结束；撤销提交之后的任何判定读到 HEAD_REJECTED 并不再入队；判定函数 panic 时锁被释放。
- **AND** 该保证是“线性化于撤销”，不是同一事务内的原子步骤；文档和注释不得写成原子。

#### Scenario: SC-ATB-106

- **GIVEN** requirement（及 architecture）run 已注册，CR 无头，首个节点因 HEAD_UNAVAILABLE 等待。
- **WHEN** 经真实授权路由首次签发头（201）；在路由提交之后、发现之前检查队列；随后先后执行两次 ResumeActiveRuns。
- **THEN** SHALL 在路由提交后、发现前没有节点任务；第一次发现后恰有一个首节点任务；第二次发现后 agent_task_queue 与 pipeline_node_run 的计数及首任务 id 都不变。

#### Scenario: SC-ATB-107

- **GIVEN** CR 有有效头；run 的源任务从未消费；首节点任务 T1 已完成。
- **WHEN** 发现路径运行，并再运行一次。
- **THEN** SHALL 首节点 passed 并派发后续节点，后续节点的派发不要求源任务或 T1 有消耗回执；再次发现不产生新任务或状态变化。

### Requirement: 准入不再读取 run 的 source_task_id；入队路径读取它只用于来源归因，其严格校验保持。

#### Scenario: SC-ATB-108

- **GIVEN** CR 有有效头；run 的执行上下文缺少 source_task_id。
- **WHEN** Runner 尝试把节点置 passed 或通过人工门；另行尝试入队。
- **THEN** SHALL 对置 passed 与人工门放行而不返回 AUTHORITY_MISMATCH；对入队仍返回 RunnerErrAuthorityMismatch 且不创建任务。
- **AND** run 的执行上下文里 source_task_id 存在但格式非法时，入队路径行为不变。

### Requirement: 摘除准入对 consumption/effect 的读取不改变这些链的写入语义：consumption 路由的重放与新 generation 行数规则保持。

#### Scenario: SC-ATB-109

- **GIVEN** 任务 T1 已在 generation G1 消费。
- **WHEN** 同一 generation 重放提交；T1 被重新认领为 G2 后再提交。
- **THEN** SHALL 对同 generation 重放返回 200 且 changed=false，回执、command、verdict、settlement 行数均不变； G2 提交（201）后回执 +1，command、verdict、settlement 均 +0。
- **AND** 同一时间 CR 的准入结果保持 ADMITTED，不随消费状态变化。

### Requirement: 测试改写后覆盖不退化：每类受保护动作对“无头、有效头、叫停、跨范围头、幂等”五类保证各至少保留一个用例。

#### Scenario: SC-ATB-110

- **GIVEN** 既有准入测试已按新语义改写、删减或新增。
- **WHEN** 按“受保护动作 × 五类保证”的矩阵逐格核对改写后的测试。
- **THEN** SHALL 每一格至少对应一个通过的用例，矩阵与改写前后各格用例数写入 test-report；任何被删除的用例都能指向被取代的基线条款。
- **AND** 没有因本变更新增的 skip，也没有靠放宽断言换来的通过。
