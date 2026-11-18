# 执行准入收缩为单一授权头判定，并让等待原因对人可见 — 测试方案与详细案例

> 版本：2026-11-17-execution-admission-simplification
> 创建日期：2026-11-17
> 对应 Phase 2 Spec：`canonical/specs/code/admission-task-binding.yaml`、`authorized-runner.yaml`、`execution-wait-visibility.yaml`（规格 28 个 Scenario，16 个 TC）
> 快照说明：本文“当前状态/待实施”与引用行号为 Gate 2 快照；实施进展以 `tasks.md`、`phase-context.md` 与 `.stdd.yaml.slices_completed` 为准。命令型 CP 断言携带 exit_code + PASS 标签 + fail=0 + skip=0 计数，业务正确性由带 expected 对账的 Go 测试承载（M1 折中，Gate 2 重审）。

## 一、测试策略

### 1.1 测试金字塔

- **判定与 Runner 层（DB 集成，主体）**：准入的全部行为都读写 Postgres（头联结、锁、入队、节点），无法脱离数据库得到有区分度的结果，因此以 `run-selection.mjs` 在**自建一次性 podman 实例**上运行 Go 测试为主；不使用 mock 的判定器代替真实查询。
- **路由 / 装配层**：授权签发（默认契约、可省略字段）与新增 GET 路由经真实 router 与真实认证中间件跑；三种装配情形（无密钥、显式 manifest、半配置）在装配函数层判定。
- **CLI（单元）**：`cmd/multica` 的 status 与 table 输出不需要数据库，用 `go test` 直跑。
- **联调（E2E，仅一条）**：默认契约下 architecture 的 stub 场景，让真实 server、真实 daemon、crctl 与 stub 执行器走完“签发 → head → binding → crctl 检查 → 预消费 → 节点启动”，用于验证 digest 在各环节一致（design.md 最大的未经实机验证点）。不消耗模型请求。
- 提案成功标准第 8 条在此**拆成两项证据**：requirement 形态的 DB 集成用例（TC-RUN-106，覆盖“同形 CR、源任务从未消费、writer → reviewer”）加上述 E2E（TC-RUN-105，覆盖 daemon 链）。**这是对提案措辞的偏离**（驱动现有场景只有 architecture，requirement 流水线不在其范围，新增 requirement 的真实 daemon 场景属于扩大范围），已列入 Gate 2 待确认。

### 1.2 测试原则

- 每个受保护动作对“无头、有效头、叫停、跨范围头、幂等”五类保证各至少一个用例；改写时先建矩阵再改测试，**不按错误码一一对应**。
- 被取代的基线用例（`TestTC_ATB_001–004`、`TC_ATB_005–007` 中依赖消耗的断言）只能删除到有明确的取代条款；混合用例保留全部非准入断言，只改前置数据。
- 现有没有“头指向其他 workspace/CR”的 Runner 准入用例，属于**新增**覆盖，不得靠改写冒充。
- `selection` 必须带 `expected` 名单：所列测试缺一个、零匹配、skip 都不算通过。
- 断言须含能区分对错的观测值（具体状态、计数、字段值），不得只匹配 PASS 标签；命令型 CP 的 PASS 标签只是 run-selection 汇总，每个测试自身须断言具体观测值（拒绝原因字符串、任务与节点行数、HTTP 状态与错误码、`progress.state`）。
- 不改被取代范围之外的断言，不放宽断言换通过；不新增 skip。
- DB 类测试只在一次性实例上跑；**现网 `multica-postgres` 任何时候不连接、不写入**。

### 1.3 已有测试资产（改写或保留；行号以实施前 `rg` 复核为准）

| 测试文件 | 类型 | 本变更处理 |
|----------|------|------------|
| `server/internal/governance/execution_admission_test.go`（`TestAdmissionDeciderWaitsForCommittedConsumption` 等） | DB 集成 | 改写为头判定表（无头/拒绝头/有效头/跨范围头/无效输入） |
| `execution_admission_task_decider_test.go`（`TestTC_ATB_001–004`） | DB 集成 | 删除消耗/effect 部分；004 的无头、拒绝头保留并入头判定表 |
| `execution_admission_task_binding_test.go`（`ATB_005–007`）、`execution_admission_task_discovery_test.go`（`ATB_008–010`） | DB 集成 | 去消耗前置；保留“重复 passed 不改行、approval id、入队归因、重复唤醒不重复派发”；008/009 改成“签发后不自唤醒、发现路径推进” |
| `execution_admission_gate_test.go`、`execution_admission_enqueue_test.go`、`execution_admission_requirement_enqueue_test.go`、`execution_admission_human_gate_test.go` | DB 集成 | “先消费再放行”改为“无头等待、签发头后放行” |
| `execution_consumption_effect_test.go`（`TC_CE_001–004`）、`cmd/server/execution_run_003_test.go`（`TC_RUN_003`） | DB 集成 | 仅删其中的准入断言；链绑定、回滚、跨 CR 隔离、重放不重复写链、伪造签名拒绝保留 |
| `execution_revoke_resume_test.go`（`TC_REC_006`）、`execution_admission_lock_test.go`、`execution_admission_cleanup_test.go`、`execution_admission_failure_branch_test.go`、`admissionguard_test/decider_test.go`、`runnerquery_test/admission_cleanup_test.go` | DB 集成 | 不改（仅为编译去掉 `TaskID` 实参） |
| daemon `execution_preflight_test.go`、`execution_node_preconsume_test.go` | 单元/集成 | 不改（daemon 启动前回执要求，另一条路径） |
| `execution_authorization_test.go`、`execution_authorization_http_test.go`、`execution_authorization_routes_test.go`、`execution_authorization_head_test.go`、`execution_contract_manifest_test.go`、`cmd/server/execution_authorization_head_test.go` | 单元/DB | 保留；其中“未配置→503”的断言按 D3 的三种装配情形重核；manifest 的“空/空返回 nil”不变 |
| `cmd/multica/cmd_cr_pipeline_test.go` | 单元 | 保留；新增 status 与 table 用例 |
| `scripts/aifi45-disposable/selections.json`（与 `selections.baseline.json`）、`scripts/aifi45-real-run/stack.mjs`、`stack.test.mjs`、`run.mjs` | Node | selections 条目与被改名/删除的测试同步；stack 与 run 增加 `--default-contract`（见 design.md 影响面） |

## 二、详细测试案例

### 功能 1：准入只看授权头（admission-task-binding）

#### 案例 1.1 — 四类受保护动作 × 头状态矩阵

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-101 |
| **对应 Spec** | admission-task-binding → SC-ATB-101、102、103、104 |
| **优先级** | P0 |
| **预置条件** | 一次性库；同一 CR 分别处于：无头、有效 approve 头且源/节点任务均无回执与 effect、头已撤销（reject）、头指针指向其他 workspace 或同 workspace 其他 CR 的 approve 记录（这两种**各为独立变体**，分别断言，EXP-2026-0005） |
| **输入** | 对四类受保护动作（置 passed、人工门、普通节点入队、requirement 节点入队）各尝试一次；另直接调判定函数传非法 workspace、非法 CR、未知意图、空事务 |
| **预期结果** | 无头与跨范围头：`HEAD_UNAVAILABLE`，无新任务、节点未 passed、run 未失败，`detail.runner={wait_reason:admission, admission:<原因>}`；有效头：`ADMITTED`，效果完成；撤销头：`HEAD_REJECTED`；非法输入：请求无效错误而非拒绝原因；公开 reconcile 入口把等待转成成功 |
| **当前状态** | ❌ 测试缺（新增；其中“跨范围头”为全新覆盖） |

#### 案例 1.2 — 叫停与入队不交错

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-102 |
| **对应 Spec** | admission-task-binding → SC-ATB-105 |
| **优先级** | P0 |
| **预置条件** | 一次放行判定持有头锁，效果未完成 |
| **输入** | 独立连接发起撤销；判定函数 panic 的变体；撤销后原 Runner、重启 Runner、重复发现 |
| **预期结果** | 撤销被阻塞到效果结束；panic 后锁释放；撤销提交后不再入队，历史不变，并有未撤销正控 |
| **当前状态** | ✅ 已覆盖（`TestAdmissionGateLockBlocksRevocation`、`TestAdmissionDeciderPanicReleasesHeadLock`、`TestTC_REC_006` 并成新 selection） |

#### 案例 1.3 — 签发不自唤醒、发现路径推进、重复发现幂等

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-103 |
| **对应 Spec** | admission-task-binding → SC-ATB-106、107 |
| **优先级** | P0 |
| **预置条件** | run 已注册，CR 无头，首节点因 `HEAD_UNAVAILABLE` 等待；源任务从未消费 |
| **输入** | 经真实授权路由签发（201）→ 检查队列 → 两次 `ResumeActiveRuns`；T1 完成后再两次发现 |
| **预期结果** | 路由提交后发现前无节点任务；首次发现后恰 1 个首节点任务；第二次发现后 `agent_task_queue`、`pipeline_node_run` 计数与首任务 id 不变；T1 完成后首节点 passed 并派发后续，无需源任务回执；再发现无变化 |
| **当前状态** | ❌ 测试缺（由 `ATB_008/009` 改写） |

#### 案例 1.4 — 准入不再依赖 source_task_id，入队归因仍严格

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-104 |
| **对应 Spec** | admission-task-binding → SC-ATB-108 |
| **优先级** | P1 |
| **预置条件** | 有效头；run 的执行上下文缺 `source_task_id`；另一份为格式非法 |
| **输入** | 尝试置 passed、通过人工门；尝试入队 |
| **预期结果** | 置 passed 与人工门放行；入队返回 `RunnerErrAuthorityMismatch` 且无任务；格式非法时入队行为不变 |
| **当前状态** | ❌ 测试缺（新增） |

#### 案例 1.5 — consumption 写入语义不变

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-105 |
| **对应 Spec** | admission-task-binding → SC-ATB-109 |
| **优先级** | P0 |
| **预置条件** | T1 在 generation G1 已消费 |
| **输入** | 同 generation 重放；T1 重新认领为 G2 后再提交 |
| **预期结果** | 重放 200 且 `changed=false`，回执/command/verdict/settlement 行数不变；G2 提交 201，回执 +1，command/verdict/settlement +0；准入结果始终 `ADMITTED` |
| **当前状态** | ✅ 已覆盖（`m005-consumption-effect`，需删去其中的准入断言并加“准入不随消费变化”） |

#### 案例 1.6 — 改写后覆盖矩阵不退化

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-106 |
| **对应 Spec** | admission-task-binding → SC-ATB-110 |
| **优先级** | P1 |
| **预置条件** | 准入相关测试已改写完毕 |
| **输入** | 按下表逐格核对，并统计改写前后各格用例数、被删除用例的取代条款 |
| **预期结果** | 每一格至少一个通过用例；test-report 附前后计数；无新增 skip；见下方矩阵 |
| **当前状态** | ❌ 测试缺（人工核对项，写入 test-report） |

覆盖矩阵（目标，行=受保护动作，列=保证类别，单元格=承担的 TC）：

| 动作 | 无头 | 有效头 | 叫停 | 跨范围头 | 幂等 |
|------|------|--------|------|----------|------|
| 节点置 passed | TC-ATB-101 | TC-ATB-101、103 | TC-ATB-101、102 | TC-ATB-101 | TC-ATB-103 |
| 人工门通过 | TC-ATB-101 | TC-ATB-101、104 | TC-ATB-101、102 | TC-ATB-101 | TC-ATB-103 |
| 普通节点入队 | TC-ATB-101 | TC-ATB-101、103 | TC-ATB-101、102 | TC-ATB-101 | TC-ATB-103 |
| requirement 节点入队 | TC-ATB-101 | TC-ATB-101、106（RUN） | TC-ATB-101、102 | TC-ATB-101 | TC-ATB-103 |

### 功能 2：默认部署可签发授权（authorized-runner）

#### 案例 2.1 — 唤醒只依授权头

| 字段 | 内容 |
|------|------|
| **ID** | TC-RUN-101 |
| **对应 Spec** | authorized-runner → SC-RUN-101 |
| **优先级** | P0 |
| **预置条件** | grant 已送达并 ACK；头有效而无锚点回执；另有无头与撤销头两种 CR |
| **输入** | ACK 回调、周期唤醒各多次 |
| **预期结果** | 有效头推进；无头/撤销头只唤醒核验，不完成业务 gate、不直接派发；重复唤醒不重复派发；伪造签名仍拒绝 |
| **当前状态** | ❌ 测试缺（由 `TestTC_RUN_003` 改写） |

#### 案例 2.2 — 省略字段、显式相等、显式不等

| 字段 | 内容 |
|------|------|
| **ID** | TC-RUN-102 |
| **对应 Spec** | authorized-runner → SC-RUN-102、103、104 |
| **优先级** | P0 |
| **预置条件** | 签名服务存在、无 manifest、owner 已认证、CR 有可解析 project |
| **输入** | 三种请求：省略三字段；三字段显式相等；任一字段取不同值；另含空字符串与未知字段变体 |
| **预期结果** | 省略与相等均 201 且**随后读取 head 为有效**（不得 `EXECUTION_AUTHORIZATION_HEAD_INVALID`），payload、冻结请求、部署契约三者的值一致；不等返回 409 `EXECUTION_CONTRACT_MISMATCH`，无新记录、头不变；空字符串按省略；未知字段仍拒绝；省略请求与重放判定的行为被固定 |
| **当前状态** | ❌ 测试缺（新增） |

#### 案例 2.3 — 三种装配情形

| 字段 | 内容 |
|------|------|
| **ID** | TC-RUN-103 |
| **对应 Spec** | authorized-runner → SC-RUN-105、106 |
| **优先级** | P0 |
| **预置条件** | 无签名密钥无 manifest；显式 manifest 与签名密钥；半配置；manifest 无密钥 |
| **输入** | 启动并探测授权端点与契约 |
| **预期结果** | 无密钥：正常启动、端点 503 `EXECUTION_AUTHORIZATION_DISABLED`；显式 manifest：以其契约为准，默认不生效；半配置、路径非原生绝对路径、sha256 不匹配、超限：仍拒绝启动且不回退默认；manifest 无密钥：仍拒绝启动 |
| **当前状态** | ❌ 测试缺（新增；复用 `execution_contract_manifest_test.go` 既有失败用例） |

#### 案例 2.4 — 签发入口边界不放宽

| 字段 | 内容 |
|------|------|
| **ID** | TC-RUN-104 |
| **对应 Spec** | authorized-runner → SC-RUN-107 |
| **优先级** | P0 |
| **预置条件** | 默认部署；task token、cloud PAT、非 owner/admin 成员、shell issue 缺失的 CR |
| **输入** | 各自提交授权请求；另提交范围与可信范围不一致的请求体 |
| **预期结果** | 403 `EXECUTION_HUMAN_SOURCE_REQUIRED`（task token 与 cloud PAT）；403 `FORBIDDEN_AUTHORIZER`；409 `EXECUTION_SCOPE_UNRESOLVED`；400 `EXECUTION_SCOPE_INVALID`；均无授权记录 |
| **当前状态** | ✅ 已覆盖（既有授权端点测试，需在默认契约下复跑并新增 selection） |

#### 案例 2.5 — 默认契约与 daemon strict 链联调

| 字段 | 内容 |
|------|------|
| **ID** | TC-RUN-105 |
| **对应 Spec** | authorized-runner → SC-RUN-108 |
| **优先级** | P0（第一个实施切片的验收） |
| **预置条件** | 一次性隔离栈；server 不传 manifest 参数；daemon 与 crctl、node 可用；stub 执行器（不消耗模型）；授权头经省略字段的请求签发 |
| **输入** | 运行 architecture-stub 的 default-contract 模式直到首个节点任务启动并完成 |
| **预期结果** | grant 安装、crctl 检查、binding、平台 receipt 全部成功，节点启动完成；任一环节因 digest 不一致被拒时判定失败，**停下复核 D3/D4，不继续堆实现** |
| **当前状态** | ❌ 测试缺（驱动新增 `--default-contract`） |

#### 案例 2.6 — 与 DAYA-5 同形的 requirement 流转

| 字段 | 内容 |
|------|------|
| **ID** | TC-RUN-106 |
| **对应 Spec** | authorized-runner → SC-RUN-109 |
| **优先级** | P0 |
| **预置条件** | requirement run；源任务是从未消费的普通任务；CR 起初无头；头经真实授权路由以默认契约签发 |
| **输入** | 发现路径运行 → writer 任务入队 → 完成并投影 → 再次发现 |
| **预期结果** | writer 任务带 `cr_id` 与 `pipeline_node_run_id` 入队；writer 完成后 review-requirement 任务被派发；全程没有对源任务回执的等待 |
| **当前状态** | ❌ 测试缺（新增；覆盖提案成功标准第 8 条的 requirement 部分） |

### 功能 3：等待原因可见（execution-wait-visibility）

#### 案例 3.1 — 进展推导全状态表

| 字段 | 内容 |
|------|------|
| **ID** | TC-EWV-001 |
| **对应 Spec** | execution-wait-visibility → SC-EWV-001～005 |
| **优先级** | P0 |
| **预置条件** | 逐一构造：completed/failed/cancelled run；running 且前沿有五种活动任务态之一且 runner 残留 `wait_reason=admission`；前沿无活动任务且 `wait_reason=admission` 取 `HEAD_UNAVAILABLE`、`HEAD_REJECTED`、历史 `WAIT_CONSUMPTION`、`WAIT_TRUSTED_T_COMMIT`；其他等待原因（`projection_stale`、`review_evidence`、`authority_postcondition`）；`waiting_approval`；无前沿节点；无任务的 passed 与人工节点 |
| **输入** | 计算进展 |
| **预期结果** | 状态分别为 completed/failed（带 `error.code`）/cancelled、in_flight（带 task_id、task_status，**不是** waiting）、waiting（带原样 wait_reason 与 admission）、waiting_human、idle；无任务的 passed 或人工节点不被判为 waiting |
| **当前状态** | ❌ 测试缺（新增） |

#### 案例 3.2 — 回执兼容

| 字段 | 内容 |
|------|------|
| **ID** | TC-EWV-002 |
| **对应 Spec** | execution-wait-visibility → SC-EWV-006、007 |
| **优先级** | P0 |
| **预置条件** | 因准入等待的 requirement run；已入队的 run；进展读取失败的 run |
| **输入** | 分别调用 requirement resume 与 architecture start |
| **预期结果** | 回执保留 `run_id`、`changed` 且 `changed` 语义不变（新建 true、复用 false、恢复 true）；等待准入时 `progress.state=waiting` 带 admission；已入队时 `progress.state=in_flight` 带 task_id；读取失败时仍成功、省略 `progress` 并记录日志；既有 `TestRequirementResumeIsIdempotent` 等不回归 |
| **当前状态** | ❌ 测试缺（新增） |

#### 案例 3.3 — GET 路由权限

| 字段 | 内容 |
|------|------|
| **ID** | TC-EWV-003 |
| **对应 Spec** | execution-wait-visibility → SC-EWV-008 |
| **优先级** | P0 |
| **预置条件** | Runner 启用；一个 workspace 的 run；成员、非成员、绑定另一 workspace 的任务令牌；另一个 workspace 的 run |
| **输入** | `GET /api/workspaces/{ws}/pipeline-runs/{runID}` |
| **预期结果** | 成员 200 且含 `run_id/pipeline_id/cr_id/status/progress`；非成员 404；跨 workspace 令牌 403；run 不属该 workspace 404；Runner 关闭时路由不存在 |
| **当前状态** | ❌ 测试缺（新增） |

#### 案例 3.4 — CLI status 与 table

| 字段 | 内容 |
|------|------|
| **ID** | TC-EWV-004 |
| **对应 Spec** | execution-wait-visibility → SC-EWV-009 |
| **优先级** | P1 |
| **预置条件** | 测试服务端返回带 `progress` 的 JSON |
| **输入** | `multica cr pipeline status --run <id>`；start、resume 的 table 与 json 输出 |
| **预期结果** | status 用普通客户端认证读取并输出 `STATE`、`REASON`；start、resume 的 table 新增这两列；json 输出为原 map 加新字段；start、resume 的请求体与 `mat_` 前缀检查不变；非任务令牌仍被 resume 拒绝 |
| **当前状态** | ❌ 测试缺（新增；`TestRunCrPipelineResumeTargetsTheRequirementRoute`、`TestRunCrPipelineResumeRefusesNonTaskToken` 保留） |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试（DB 一次性实例） | E2E | 状态 |
|----------|---------|---------------------------|-----|------|
| 准入判定与四类受保护动作 | 判定函数入参校验 | TC-ATB-101～106 | — | 🔴 待实施 |
| 默认契约与可省略字段 | manifest 加载既有测试 | TC-RUN-101～104、106 | TC-RUN-105（stub 场景） | 🔴 待实施 |
| 进展推导与回执 | — | TC-EWV-001、002 | — | 🔴 待实施 |
| GET 路由与 CLI | TC-EWV-004 | TC-EWV-003 | — | 🔴 待实施 |

## 四、回归风险矩阵

| 改动区域 | 风险 | 级别 | 保护 |
|----------|------|------|------|
| `DecideAdmission` 与 `AdmissionRequest` | 误删对叫停、跨范围、幂等的覆盖；放行条件被意外放宽 | 高 | TC-ATB-101、102、103、106；矩阵逐格核对 |
| 头锁与撤销序列化 | 删消耗查询后改变了锁持有区间 | 高 | TC-ATB-102（既有锁用例） |
| 默认契约装配（`router.go`） | 无密钥部署被默认契约弄成启动失败；显式 manifest 被覆盖 | 高 | TC-RUN-103 |
| 请求字段可省略（`execution_authorization.go`） | 填充晚于冻结，head 读取 409；放宽了“显式不等”的拒绝 | 高 | TC-RUN-102（含“签发后读 head 有效”） |
| 默认 digest 与 crctl/daemon 链一致 | 静态推断未经实机，某环节比较失败 | 高 | TC-RUN-105 |
| `markNodeAdmitted`、`passHumanApprovalNode` 去掉 source 任务读取 | 缺 `source_task_id` 的 run 行为变化；入队归因被连带放宽 | 中 | TC-ATB-104 |
| `progressOf` 推导 | `runner` 残留导致误报等待；无任务节点被误判 | 中 | TC-EWV-001 |
| 回执新增字段 | 旧调用方或测试对整体 JSON 的严格比较 | 中 | TC-EWV-002、TC-EWV-004；已确认现有 CLI 对响应是 `map[string]any` 解码 |
| 新 GET 路由 | 越权读取其他 workspace 的 run | 中 | TC-EWV-003 |
| consumption/effect 写入路径 | 被误改 | 中 | TC-ATB-105（既有 m005 用例） |
| `selections.json` 与测试改名 | 选择指向不存在的测试，零匹配失败 | 中 | 改名优先保持函数名；对账规则要求 `expected` 名单完整 |

## 五、建议补充顺序

- **P0-1（第一个切片，决定是否继续）**：TC-RUN-105 的联调——先于大规模改动验证默认契约在 daemon strict 链各环节一致。不一致则停下复核。
- **P0-2**：TC-ATB-101（头判定矩阵）→ TC-ATB-102/103/105 的改写 → TC-RUN-101。
- **P0-3**：TC-RUN-102/103/104、TC-RUN-106。
- **P0-4**：TC-EWV-001/002/003。
- **P1**：TC-ATB-104、TC-EWV-004、TC-ATB-106（矩阵核对写入 test-report）。

## 六、同次执行证据计划

> Locked at Gate 2. Each TC has exactly one check here; a `required` command/pytest check must bind a CP (each command check owns its CP), while `manual` and `not_applicable` checks must not bind a CP (the latter needs a `reason`). Adding it later needs a design-adjustment and re-approval.

```stdd-evidence-plan-v1
{
  "task": "admission-task-binding",
  "tasks": [
    "admission-task-binding",
    "authorized-runner",
    "execution-wait-visibility"
  ],
  "inputs": [
    {"root": "project", "path": "server/internal/governance"},
    {"root": "project", "path": "server/cmd/server"},
    {"root": "project", "path": "server/cmd/multica"},
    {"root": "project", "path": "scripts/aifi45-disposable"},
    {"root": "project", "path": "scripts/aifi45-real-run"}
  ],
  "coverage": {
    "applicability": "not_applicable",
    "reason": "被测对象为 Go 与 Node 脚本，覆盖率采集目前只支持 pytest-cov；项目配置 quality.coverage.enabled=false"
  },
  "checks": [
    {"tc": "TC-ATB-101", "case_id": "head-only-matrix", "requirement": "REQ-ATB-101",
     "scenarios": ["SC-ATB-101", "SC-ATB-102", "SC-ATB-103", "SC-ATB-104"], "cp": "CP-ATB-101", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-102", "case_id": "lock-and-revoke", "requirement": "REQ-ATB-102",
     "scenarios": ["SC-ATB-105"], "cp": "CP-ATB-102", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-103", "case_id": "issue-no-wake-discovery-idempotent", "requirement": "REQ-ATB-102",
     "scenarios": ["SC-ATB-106", "SC-ATB-107"], "cp": "CP-ATB-103", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-104", "case_id": "source-task-optional-for-gates", "requirement": "REQ-ATB-103",
     "scenarios": ["SC-ATB-108"], "cp": "CP-ATB-104", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-105", "case_id": "consumption-write-path-unchanged", "requirement": "REQ-ATB-104",
     "scenarios": ["SC-ATB-109"], "cp": "CP-ATB-105", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-106", "case_id": "coverage-matrix-retained", "requirement": "REQ-ATB-105",
     "scenarios": ["SC-ATB-110"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-RUN-101", "case_id": "ack-wake-head-only", "requirement": "REQ-RUN-101",
     "scenarios": ["SC-RUN-101"], "cp": "CP-RUN-101", "kind": "command", "applicability": "required"},
    {"tc": "TC-RUN-102", "case_id": "default-contract-issue", "requirement": "REQ-RUN-102",
     "scenarios": ["SC-RUN-102", "SC-RUN-103", "SC-RUN-104"], "cp": "CP-RUN-102", "kind": "command", "applicability": "required"},
    {"tc": "TC-RUN-103", "case_id": "default-contract-wiring", "requirement": "REQ-RUN-102",
     "scenarios": ["SC-RUN-105", "SC-RUN-106"], "cp": "CP-RUN-103", "kind": "command", "applicability": "required"},
    {"tc": "TC-RUN-104", "case_id": "authorizer-boundary-unchanged", "requirement": "REQ-RUN-103",
     "scenarios": ["SC-RUN-107"], "cp": "CP-RUN-104", "kind": "command", "applicability": "required"},
    {"tc": "TC-RUN-105", "case_id": "default-contract-daemon-chain-stub", "requirement": "REQ-RUN-104",
     "scenarios": ["SC-RUN-108"], "cp": "CP-RUN-105", "kind": "command", "applicability": "required"},
    {"tc": "TC-RUN-106", "case_id": "daya5-shaped-requirement-flow", "requirement": "REQ-RUN-104",
     "scenarios": ["SC-RUN-109"], "cp": "CP-RUN-106", "kind": "command", "applicability": "required"},
    {"tc": "TC-EWV-001", "case_id": "progress-derivation-table", "requirement": "REQ-EWV-001",
     "scenarios": ["SC-EWV-001", "SC-EWV-002", "SC-EWV-003", "SC-EWV-004", "SC-EWV-005"], "cp": "CP-EWV-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-EWV-002", "case_id": "receipt-compatible-progress", "requirement": "REQ-EWV-002",
     "scenarios": ["SC-EWV-006", "SC-EWV-007"], "cp": "CP-EWV-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-EWV-003", "case_id": "get-run-authz", "requirement": "REQ-EWV-003",
     "scenarios": ["SC-EWV-008"], "cp": "CP-EWV-003", "kind": "command", "applicability": "required"},
    {"tc": "TC-EWV-004", "case_id": "cli-status-and-table", "requirement": "REQ-EWV-003",
     "scenarios": ["SC-EWV-009"], "cp": "CP-EWV-004", "kind": "command", "applicability": "required"}
  ]
}
```
