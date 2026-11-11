# AIFI-45 准入按任务／generation 绑定 测试方案与详细案例

> 版本：2026-11-11-aifi-45-admission-task-binding
> 创建日期：2026-11-11
> 对应 Phase 2 Spec：specs/admission-task-binding/spec.md（SC-ATB-001～010）、specs/authorized-runner/spec.md（MODIFIED SC-RUN-003）
> 案例与执行矩阵的状态为设计阶段记录；BUILD 实际结果和返修进展以 test-report.md 为准。

## 一、测试策略

### 1.1 测试金字塔

偏集成、偏真实库：准入判定、Runner 受保护动作、真实 consumption 路由与真实发现路径的行为都依赖 task 行、generation、唯一约束、授权头锁和队列唯一索引，用 mock 会丢失这些证据。分三层：（1）decider 单层（TC-ATB-001～004，包内直接调用）；（2）Runner 动作层（TC-ATB-005～007，包内，真实库，计数 enqueuer 与真实 TaskService 各取所需）；（3）真实链层（TC-ATB-008～010，`governance_test`，复用 bindingIssueFixture 的真实路由与真实 TaskService，经 `ResumeActiveRuns` 发现）。没有 UI/E2E 层。

### 1.2 测试原则

- 每个拒绝条件一个独立命名 subtest，不用混合 fixture 同时覆盖多个原因（EXP-2026-0005）；每个场景既有「借用被拒」又有「正确 task 放行」。
- 先取序列化锁再读守卫的约束沿用既有锁测试（独立连接探针只接受 SQLSTATE 55P03，EXP-2026-0002）；本 change 不改锁序，不新增锁交错用例。
- 既有测试只改被消费的 task 身份、必要的真实 task/generation 行与新增反例；不删队列计数、节点状态、wait reason、验签、归因、链行数或幂等断言，不加 skip。
- 数据库测试只在 supervisor 自建的一次性实例上运行；绝不触碰 multica-postgres、multica-backend、aifi45-disposable 或任何未知资源。
- 零匹配、skip、名称不存在都不算通过。

### 1.3 已有测试资产（本 change 要修改 fixture 的）

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|----------|--------|------|----------|
| server/internal/governance/execution_admission_test.go | 既有 | 集成 | decider 的 head/回执/settlement/verdict/cursor；改为命名锚点 task |
| server/internal/governance/execution_consumption_effect_test.go（TC-CE-001～004） | 4 | 集成 | 真实 consumption 路由与 effect 链；`ceAdmission` 传锚点，TC-CE-004 增补旧回执 WAIT_CONSUMPTION |
| server/internal/governance/execution_admission_{gate,enqueue,requirement_enqueue,human_gate}_test.go | 既有 | 集成 | 四类受保护动作的等待/放行；随机 task 消费改为 own-task 或 source，删除重复回执写入 |
| server/internal/governance/execution_admission_{lock,cleanup,failure_branch}_test.go | 既有 | 集成 | 锁与清理测试补合法 task id；failure_branch 复用的 run fixture 已带 source id，无需修改 |
| server/cmd/server/execution_run_003_test.go（TC-RUN-003） | 1 | 集成 | 五阶段 wake 与写入口；consumptionTask 改为 source 并固定其 generation |
| server/internal/governance/runner_periodic_resume_test.go | 既有 | 集成 | 重复发现与 retry 唯一性；不改，供 TC-ATB-008 复用计数方式 |

细目与不改的文件见 design.md 决策 7。

## 二、详细测试案例


### 功能 1：准入判定锚点（REQ-ATB-001）

#### 案例 1.1 — TC-ATB-001

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-001 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-001（REQ-ATB-001） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_decider_test.go，函数 TestTC_ATB_001，经选择 atb-001 在一次性库运行 |
| **预置条件** | TaskID 为空（或畸形）；锚点行缺失、属他 workspace、dispatched_at 或 runtime_id 为 NULL；CR 内另有他 task 的完整链。 |
| **输入** | 直接调用 DecideAdmission（事务内），每种情形一个独立 subtest。 |
| **预期结果** | 空/畸形 → ErrAdmissionInvalid；其余三种 → WAIT_CONSUMPTION；他 task 的完整链不改变结果。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 1.2 — TC-ATB-002

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-002 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-002（REQ-ATB-001） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_decider_test.go，函数 TestTC_ATB_002，经选择 atb-002 在一次性库运行 |
| **预置条件** | T1 已认领；CR 内的消费事实只有：他 task T0 的回执+effect / T1 旧 generation 的回执（T1 已重新认领）/ 他 CR 名下对 T1 的回执。 |
| **输入** | 以 T1 为锚点调用 DecideAdmission，三种情形各一个 subtest。 |
| **预期结果** | 每种 → WAIT_CONSUMPTION，不放行。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 1.3 — TC-ATB-003

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-003 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-003（REQ-ATB-001） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_decider_test.go，函数 TestTC_ATB_003，经选择 atb-003 在一次性库运行 |
| **预置条件** | T1 当前回执在；T1 自己缺 settlement / verdict / cursor 覆盖 / command 之一；T0 具备完整链。 |
| **输入** | 以 T1 为锚点调用 DecideAdmission，四种缺失各一个 subtest。 |
| **预期结果** | 每种 → WAIT_TRUSTED_T_COMMIT，不借 T0 的链。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 1.4 — TC-ATB-004

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-004 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-004（REQ-ATB-001） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_decider_test.go，函数 TestTC_ATB_004，经选择 atb-004 在一次性库运行 |
| **预置条件** | T1 当前回执 + 自己的完整可信 effect 链，head 为 approve；变体：payload 畸形、effect 字段错、scope 不符、command_digest 不符；head 缺失、非 approve。 |
| **输入** | 以 T1 为锚点调用 DecideAdmission。 |
| **预期结果** | 完整链 → ADMITTED；四种破坏各 → WAIT_TRUSTED_T_COMMIT；head 缺失 → HEAD_UNAVAILABLE，非 approve → HEAD_REJECTED；无新增原因。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 2：Runner 按动作解析锚点（REQ-ATB-002）

#### 案例 2.1 — TC-ATB-005

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-005 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-005（REQ-ATB-002） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_binding_test.go，函数 TestTC_ATB_005，经选择 atb-005 在一次性库运行 |
| **预置条件** | 节点 N 有 own-task T_N 且已完成；source S 已有完整消费，T_N 没有（架构与需求各一例）；另含 retry 子用例：T_N 已消费并完成后产生更新的子任务 T_N2。 |
| **输入** | Runner 尝试 markNode(passed)。 |
| **预期结果** | 仅 S/他 task 消费 → 不 passed、节点状态不变、有 admission 等待标注；T_N 当前 generation 回执与其 effect 提交后 → passed；retry 子用例：T_N 的消费不放行 T_N2，T_N2 自己消费后 passed，重复调用无额外状态变化。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 2.2 — TC-ATB-006

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-006 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-006（REQ-ATB-002） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_binding_test.go，函数 TestTC_ATB_006，经选择 atb-006 在一次性库运行 |
| **预置条件** | 无 own-task 的节点（架构复审跳过 writer、需求 review 取投影证据）与人工门节点；S 的消费缺失 / 完整，另有他 task 完整消费。 |
| **输入** | Runner 尝试 markNode(passed) 或 passHumanApprovalNode。 |
| **预期结果** | S 缺 → 不放行；他 task 完整 → 不放行；S 完整 → 放行。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 2.3 — TC-ATB-007

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-007 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-007（REQ-ATB-002） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_binding_test.go，函数 TestTC_ATB_007，经选择 atb-007 在一次性库运行 |
| **预置条件** | 架构与需求 run 刚注册，首节点任务不存在；S 的消费缺失 / 完整，另有他 task 完整消费。 |
| **输入** | Runner 评估首次派发（计数 enqueuer 与真实 TaskService 各一）。 |
| **预期结果** | S 完整才入队；S 缺或仅他 task → 不入队，node 标 wait_reason=admission，run 不失败；不要求节点任务预消费。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 3：真实路由与发现路径（REQ-ATB-003）

#### 案例 3.1 — TC-ATB-008

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-008 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-008（REQ-ATB-003） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_discovery_test.go，函数 TestTC_ATB_008，经选择 atb-008 在一次性库运行 |
| **预置条件** | 架构与需求 run 已注册并因 S 无消费而等待；S 的 consumption 经 bindingIssueFixture.routes 的真实路由首次提交。 |
| **输入** | 路由 201 后检查队列；依次两次 ResumeActiveRuns。 |
| **预期结果** | 路由提交后、发现前节点任务为 0；第一次发现后恰 1 个首节点任务；第二次后 agent_task_queue、pipeline_node_run 计数与首任务 id 不变。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 3.2 — TC-ATB-009

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-009 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-009（REQ-ATB-003） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_discovery_test.go，函数 TestTC_ATB_009，经选择 atb-009 在一次性库运行 |
| **预置条件** | 架构 run 的首节点任务 T1 仍在运行；source S 已消费，T1 无自己的回执。 |
| **输入** | T1 运行中经真实路由消费；T1 置 completed 后发现；再发现一次。 |
| **预期结果** | 发现后首节点 passed 并派发后续节点，后续节点派发不要求其预消费；再次发现无新增任务或状态变化。（“T1 无回执不放行”由 TC-ATB-005 验证；已完成任务不能再经真实路由补消费。） |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 3.3 — TC-ATB-010

| 字段 | 内容 |
|------|------|
| **ID** | TC-ATB-010 |
| **对应 Spec** | admission-task-binding/spec.md → SC-ATB-010（REQ-ATB-003） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance/execution_admission_task_discovery_test.go，函数 TestTC_ATB_010，经选择 atb-010 在一次性库运行 |
| **预置条件** | bindingIssueFixture 的 source task 已在 G1 消费（不经 Runner）；复用 TC-CE-004 的 helper。 |
| **输入** | 同 generation 重放；重新认领为 G2 后提交。 |
| **预期结果** | 重放 200 changed=false，四类行数不变；G2 提交前 WAIT_CONSUMPTION；提交 201 后回执 +1、command/verdict/settlement +0、ADMITTED。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 4：SC-RUN-003 回归（authorized-runner，MODIFIED）

#### 案例 4.1 — TC-RUN-003

| 字段 | 内容 |
|------|------|
| **ID** | TC-RUN-003 |
| **对应 Spec** | authorized-runner/spec.md → SC-RUN-003 |
| **优先级** | P0 |
| **测试位置** | server/cmd/server/execution_run_003_test.go，经选择 run-routes 在一次性库运行 |
| **预置条件** | 既有五阶段 fixture；consumptionTask 改为 run 的 source task，source 写入固定非 NULL generation，回执精确复用其 runtime/dispatched_at。 |
| **输入** | 既有输入不变。 |
| **预期结果** | 既有全部断言保留（伪造 verdict 被拒、真实 writer、归因、二次 wake 不重复派发）；锚点 task 的 effect 提交前只 wake 不推进。 |
| **当前状态** | ✅ 已覆盖（需改 fixture） |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试（真实库） | E2E（真实路由 + 发现） | 状态 |
|---|---|---|---|---|
| 准入锚点（REQ-ATB-001） | — | TC-ATB-001～004 | — | 🔴 |
| Runner 动作锚点（REQ-ATB-002） | — | TC-ATB-005～007 | — | 🔴 |
| 真实链（REQ-ATB-003） | — | — | TC-ATB-008～010 | 🔴 |
| SC-RUN-003 回归 | — | TC-RUN-003 | — | 🟡 |
| `--only` 运行器参数 | run-selection.test.mjs（新增用例） | 经所有 CP 间接覆盖 | — | 🔴 |

## 四、回归风险矩阵

| 风险区域 | 本 change 改动 | 已有回归保护 | 风险等级 |
|---|---|---|---|
| 所有受保护动作的准入放行条件（收紧） | 调用方按各自快照给出锚点，共用 gate 在头锁内调用 decider | 完整 selections.json 一次真实运行（0 FAIL、0 skip）；TC-CE-001～004、TC-RUN-002/003/010 | 🔴 |
| 既有 fixture 的随机 task 消费与重复写回执 | 改为命名锚点、去重 | 逐文件 diff 评审：不得删除断言 | 🟡 |
| 生产节点任务无 consumption 时的等待 | 完成处 fail-closed，不借 source | 既有 wait_reason=admission 标注；TC-ATB-005 | 🟡 |
| code/writeback 路径 | 共用 gate 的同一规则，不补发现与启动 | 仅 gate 层测试（TC-ATB-005～007 的架构/需求形态）；不声明 code 端到端 | 🟡 |
| run-selection.mjs | 新增 --only | run-selection.test.mjs；不带 --only 的路径不变 | 🟢 |
| fork CI | 不改 | 已登记另立 change | 🟢 |
| 本机其他容器与卷 | 无意触碰 | 实例前后容器与卷集合比较；只按完整 ID 释放 | 🟡 |

## 五、建议补充顺序

1. **第一优先**（切片 1）：TC-ATB-001～007 和既有 P0 回归 TC-RUN-003；新增用例计划 RED 先行，TC-RUN-003 随调用方迁移调整 fixture 并验证。实际执行及偏差见 test-report.md 第三节。
2. **第二优先**（准入改完立即做）：TC-ATB-008、009、010，以及其余既有 fixture 的调整。
3. **第三优先**：`--only` 的单元测试，随运行器改动一并完成。

## 六、同次执行证据计划

证据 run 不依赖 tools 仓库；执行前须启动 Podman 虚拟机并保证执行期间独占，比较容器与卷集合期间不得有其他容器或卷被创建或删除。调用方生成 run id，将同一值传给 `stdd agent verify admission-task-binding --change <change> --run <id>` 和 `stdd ci check-failures <change> --run <id>`，两者之间不得再跑其他 `agent verify`。每个 CP 经 `run-selection.mjs --only` 各自创建并释放一个一次性实例。Node 命令的输出为 ASCII；失败输出中的非 ASCII 字节若无法按执行器的系统 locale 解码（中文 Windows 为 cp936），执行器会崩溃，这是响亮失败，不会变成通过。`inputs` 不含 change 目录或其产物；项目输入的冻结范围为被测对象及入口在测试前直接执行的数据与命令（含迁移入口与 SQL），不含 Go 编译期传递依赖，也不含属环境的 Podman 与镜像。被测对象为 Go 测试，覆盖率采集目前只支持 pytest-cov，项目配置 `quality.coverage.enabled=false`，因此覆盖率不适用。


```stdd-evidence-plan-v1
{
  "task": "admission-task-binding",
  "tasks": ["admission-task-binding", "authorized-runner"],
  "inputs": [{"root": "project", "path": "scripts/aifi45-disposable"}, {"root": "project", "path": "server/internal/governance"}, {"root": "project", "path": "server/cmd/server"}, {"root": "project", "path": "server/cmd/migrate"}, {"root": "project", "path": "server/internal/migrations"}, {"root": "project", "path": "server/migrations"}],
  "coverage": {"applicability": "not_applicable", "reason": "被测对象为 Go 测试，覆盖率采集目前只支持 pytest-cov；项目配置 quality.coverage.enabled=false"},
  "checks": [
    {"tc": "TC-ATB-001", "cp": "CP-ATB-001", "requirement": "REQ-ATB-001", "scenarios": ["SC-ATB-001"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-002", "cp": "CP-ATB-002", "requirement": "REQ-ATB-001", "scenarios": ["SC-ATB-002"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-003", "cp": "CP-ATB-003", "requirement": "REQ-ATB-001", "scenarios": ["SC-ATB-003"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-004", "cp": "CP-ATB-004", "requirement": "REQ-ATB-001", "scenarios": ["SC-ATB-004"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-005", "cp": "CP-ATB-005", "requirement": "REQ-ATB-002", "scenarios": ["SC-ATB-005"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-006", "cp": "CP-ATB-006", "requirement": "REQ-ATB-002", "scenarios": ["SC-ATB-006"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-007", "cp": "CP-ATB-007", "requirement": "REQ-ATB-002", "scenarios": ["SC-ATB-007"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-008", "cp": "CP-ATB-008", "requirement": "REQ-ATB-003", "scenarios": ["SC-ATB-008"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-009", "cp": "CP-ATB-009", "requirement": "REQ-ATB-003", "scenarios": ["SC-ATB-009"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-ATB-010", "cp": "CP-ATB-010", "requirement": "REQ-ATB-003", "scenarios": ["SC-ATB-010"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-RUN-003", "cp": "CP-RUN-003", "requirement": "REQ-RUN-001", "scenarios": ["SC-RUN-003"], "case_id": "main", "kind": "command", "applicability": "required"}
  ]
}
```
