# Spec: execution-wait-visibility

> Change: 2026-11-17-execution-admission-simplification | Auto-generated Human View

## Requirements

### Requirement: 流水线运行的当前进展由 pipeline_run、前沿节点与其最新任务的事实推出；等待原因只在前沿节点无活动任务时采信，残留的旧 runner 标记不得让已入队或已通过的节点显示为等待。

#### Scenario: SC-EWV-001

- **GIVEN** run 状态分别为 completed、failed、cancelled。
- **WHEN** 计算该 run 的进展；failed 分支所需的前沿读取成功。
- **THEN** SHALL state 分别为 completed、failed、cancelled；failed 时 SHALL 带前沿节点 runner.error.code（若有）。

#### Scenario: SC-EWV-002

- **GIVEN** run 为 running；前沿节点的最新任务为 queued、deferred、dispatched、waiting_local_directory 或 running 之一；节点 runner 里残留着旧的 wait_reason=admission。
- **WHEN** 计算该 run 的进展。
- **THEN** SHALL state 为 in_flight，并带 node_id、attempt、task_id、task_status；SHALL NOT 显示为 waiting。

#### Scenario: SC-EWV-003

- **GIVEN** run 为 running；前沿节点无活动任务；runner 为 wait_reason=admission 且 admission 取各种字符串， 包括历史值 WAIT_CONSUMPTION 与 WAIT_TRUSTED_T_COMMIT。
- **WHEN** 计算该 run 的进展。
- **THEN** SHALL state 为 waiting，带 wait_reason 与 admission 的原样字符串（不做枚举校验）；前沿节点已有最新任务时再带 task_status。
- **AND** 其他既有等待原因（projection_stale、review_evidence、authority_postcondition 等）同样原样作为 wait_reason 透传。

#### Scenario: SC-EWV-004

- **GIVEN** run 为 waiting_approval，前沿是未送达审批的人工节点。
- **WHEN** 计算该 run 的进展，且所需前沿读取成功。
- **THEN** SHALL state 为 waiting_human 并带该节点的 node_id。

#### Scenario: SC-EWV-005

- **GIVEN** run 为 running，但没有 status=running 的前沿节点；或前沿节点既无活动任务也无 wait_reason；另有被 projector 直接写 passed 的无任务节点。
- **WHEN** 计算该 run 的进展，且所需的前沿及任务读取成功。
- **THEN** SHALL state 为 idle 且不带等待原因；SHALL NOT 把无任务的 passed 节点或无任务的人工节点判为 waiting。

### Requirement: requirement 的 resume 与 architecture 的 start 回执在 run_id、changed 之外新增 progress；原字段与语义不变；进展读取失败不使已提交的请求失败，也不被呈现为已推进。

#### Scenario: SC-EWV-006

- **GIVEN** 一个因准入等待的 requirement run，以及一个已入队的 run。
- **WHEN** 分别对其调用 resume（requirement）与 start（architecture），且回执的进展读取成功。
- **THEN** SHALL 回执仍含 run_id 与 changed 且语义不变；等待准入的回执 progress.state 为 waiting 并带 admission 原因；已入队的回执 progress.state 为 in_flight 并带 task_id。
- **AND** 缺失 progress 字段的旧调用方行为不变（CLI 的 JSON 输出为原 map 加新字段）。

#### Scenario: SC-EWV-007

- **GIVEN** run 已提交，但进展读取失败，例如数据库错误，或 running、failed 分支实际读取的 runner 详情为数组、标量或字面 null。
- **WHEN** 返回回执。
- **THEN** SHALL 仍返回成功状态与 run_id、changed，省略 progress 并记录日志；SHALL NOT 在回执中声称已推进。

### Requirement: 提供成员级只读的运行进展读面与 CLI 命令；与 Runner 开关同开同关；不新增表、状态或错误码。

#### Scenario: SC-EWV-008

- **GIVEN** Runner 已启用；一个 workspace 内的 run；该 workspace 的成员、非成员，以及绑定另一个 workspace 的任务令牌。
- **WHEN** GET /api/workspaces/{workspaceID}/pipeline-runs/{runID}。
- **THEN** SHALL 对进展读取成功的成员返回 200 与 run_id、pipeline_id、cr_id、status、progress；对非成员返回 404；对绑定其他 workspace 的任务令牌返回 403； run 不属于该 workspace 时返回 404。
- **AND** Runner 未启用时该路由不挂载，与 POST 路由一致。
- **AND** 成员请求的进展读取失败时 SHALL 返回 500 query failed；running、failed 分支实际读取的 runner 详情为数组、标量或字面 null 时属于读取失败。

#### Scenario: SC-EWV-009

- **GIVEN** CLI 对上述路由与 requirement、architecture 的 POST 回执的响应。
- **WHEN** 运行 multica cr pipeline status --run <id>，以及 start、resume 的 table 输出。
- **THEN** SHALL status 使用普通客户端认证读取并输出 STATE 与 REASON；start、resume 的 table 新增这两列；JSON 输出透传完整 map。
- **AND** 已有 start、resume 的请求体、路径与令牌前缀检查不变。

<!-- merged 2026-11-22 from 2026-11-18-defensive-trim-multica: appended REQ-EWV-101/102 and SC-EWV-101–104; original requirements preserved, read conditions corrected -->

### Requirement: 状态与进展使用同一个 run 状态；读取失败按 GET 和已提交 POST 的各自出口处理。

#### Scenario: SC-EWV-101

- **GIVEN** 同工作区的 run 可在首读后由 running 转为 completed，实际读取的前沿 runner 详情也可分别为缺失、对象或非对象。
- **WHEN** 经生产 GET 读取 run 状态与进展。
- **THEN** SHALL 用同一行 status 填顶层并选择进展分支，首读为 running 时不答 progress.state=completed。
- **AND** 缺 runner 键可正常读取；实际读取的 runner 为数组、标量或字面 null 时，running 与 failed 分支均返回 500 query failed。

#### Scenario: SC-EWV-102

- **GIVEN** run 状态是未知值，或是 running 且无 running 前沿。
- **WHEN** 以该状态调用生产进展推导。
- **THEN** SHALL 对未知状态返回错误而非 idle；对无 running 前沿的 running 状态返回 idle。

#### Scenario: SC-EWV-103

- **GIVEN** architecture start 或 requirement resume 已成功提交，回执的进展读取失败。
- **WHEN** 生成 POST 回执。
- **THEN** SHALL 返回成功状态、已提交的 run_id 与 changed，记录读取错误并省略 progress。

### Requirement: 生产进展叶子 GET 与同前缀的启动、恢复 POST 共存。

#### Scenario: SC-EWV-104

- **GIVEN** NewRouterWithOptions 装配生产路由，有真实成员 JWT 和 POST 的真实 mat_ 凭证。
- **WHEN** 切换 Runner 开关查询同一 run，并在开启时用各自正确的请求体对不存在的 CR 发两个 POST。
- **THEN** SHALL 对同一成员 GET 在 Runner 关时返回 404、开时返回 200；开启时两个已认证 POST 均抵达各自 handler 并返回 400 RUNNER_CR_NOT_READY。
