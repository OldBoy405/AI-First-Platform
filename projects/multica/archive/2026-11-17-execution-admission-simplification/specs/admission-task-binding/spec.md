# Spec: admission-task-binding

> Change: 2026-11-17-execution-admission-simplification | Auto-generated Human View

## Requirements

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
