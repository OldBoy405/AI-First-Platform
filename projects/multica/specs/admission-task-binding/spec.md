# Spec: admission-task-binding

> Change: 2026-11-11-aifi-45-admission-task-binding | Auto-generated Human View

## Requirements

### Requirement: 准入判定只以调用方指名的锚点 task 及其当前 generation 为输入：回执与可信 effect 必须都属于该 task 与该 CR，不借用 CR 内其他 task、其他 CR 或旧 generation 的消费事实。原因集合不扩充。

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

### Requirement: Runner 按各动作自己的快照给出锚点（授权头、回执、当前 generation 与 effect 由 decider 在头锁内读取）：完成有 own-task 的节点锚定其当前选中任务；派发（含首个节点）、人工门及无 own-task 的完成锚定 run 的 source task。首次派发不要求尚不存在的节点任务先有消费。准入锚点与入队归因取同一个值。

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

### Requirement: 真实 consumption 路由提交后不自行唤醒；只由系统实际的发现路径（ResumeActiveRuns）推进，且重复发现不重复派发。同 task 的合法重放与新 generation 保持 M005 语义。

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
