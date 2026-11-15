# AIFI-45 真实 daemon+agent 授权执行闭环 测试方案与详细案例

> 版本：2026-11-13-aifi-45-real-execution-closure
> 创建日期：2026-11-13
> 对应 Phase 2 Spec：specs/real-execution-closure/spec.md（SC-REC-001～007）、specs/authorized-runner/spec.md（MODIFIED SC-RUN-001/006/007）、specs/workspace-delete-execution-tables/spec.md（MODIFIED SC-WSD-005、ADDED SC-WSD-006）
> 案例与执行矩阵的状态为设计阶段记录；BUILD 实际结果以 test-report.md 为准。
> D1-B、D4-A 已于 2026-11-13 经 Gate 2 确认；2026-11-14 因 BUILD 偏离（ADJ-S7-1/2/3）与 D1.7 信任根注入（ADJ-E4-1）再同步，新增 TC-REC-009、TC-WSD-007，待 Gate 2 重审。

## 一、测试策略

### 1.1 测试金字塔

一组有限、各自职责清晰的检查，不按异常逐类打补丁：

- **组件层（无模型、一次性库）**：TC-REC-001/002/003/009 验证节点证据生产者的四个边界（daemon 启动前消费、server 合同值推导、endpoint 基数、agent 环境的信任根注入）；TC-REC-006 验证撤销后 Runner 不推进；TC-WSD-005/006/007 验证删除边界、并发与消费入口的锁序和模式；TC-REC-008 是全组回归。全部经 `run-selection.mjs --only <名称>` 在自建一次性库上运行。
- **真实层（命令型、需另行授权）**：TC-REC-004 是真实 architecture run A，TC-REC-005 是真实 run B（撤销停止）。一个 CP 对应一次真实运行，脚本结束时打印机器可核对的 `PASS real-run ...` 行，失败打印失败阶段并非零退出，不依赖人工确认（不使用 `stdd agent confirm`，避免重蹈 fork-ci 的 manual-pass 问题）。
- **驱动层（无模型、需 podman）**：TC-REC-007 的 cleanup-smoke 验证驱动在缺配置、setup 失败、超时、阶段失败时的行为。
- 没有 UI 层。

### 1.2 测试原则

- 每个检查只负责一项保证，名称与场景一一对应；一个场景若有多个拒绝条件，用独立命名的 subtest，不用混合 fixture 同时覆盖多个原因（经验库「复制的身份校验只测一个失败条件」）。
- 并发探针按锁状态排序，不用固定 sleep；等待 DB 锁状态须有 deadline。先取序列化锁再读守卫（经验库「ReadCommitted 下先读后写守卫放在序列化锁之前」）。
- 真实资源测试的清理覆盖所有路径，不只覆盖成功路径（经验库）；只按 nonce 与完整 ID 清理，不碰 multica-postgres、multica-backend 或未知资源。
- 真实运行的 CP 只经 `stdd agent verify --cp` 执行，其运行本身即证据运行，不另有预跑。architecture run 合计至多 3 次，第三次仅作止损复跑且需重新取得用户同意；首次真实失败只修节点证据生产者，不继续宣称后续保证。
- 零匹配、skip、名称不存在、阶段 INCONCLUSIVE 都不算通过；已有测试只改被消费的身份与必要 fixture，不删断言、不加 skip；`TestWorkspaceDeletionRefusesNewCommand` 的断言不放宽。

### 1.3 已有测试资产

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|----------|--------|------|----------|
| server/internal/handler/workspace_delete_no_recreate_test.go | 2 | 集成 | reservation 半句（已绿）与 command 半句（已声明红灯，本 change 转绿）；断言不改 |
| server/internal/governance/execution_control_command_attestation_test.go 等 | 33 处 ApplyControlCommandTx 调用点 | 集成 | D4-A 须迁移 fixture：补真实 workspace 归属；不删断言 |
| server/internal/daemon/execution_binding_endpoint_test.go、execution_verifier_test.go | 既有 | 单元/集成 | 单 challenge endpoint 与 strict preflight；本 change 扩展，不削弱既有 source/legacy 断言 |
| server/internal/governance/execution_authorization_revoke_*_test.go | 既有 | 集成 | 撤销 HTTP 直调与互操作；无「撤销→派发/完成」端到端（需新增） |
| scripts/aifi45-disposable/selections.json | 32 个选择 | 脚本 | 一次性库逐选择运行；本 change 新增 rec-001/002/003/009/revoke、handler-wsd-race 与 governance-wsd-lock |

## 二、详细测试案例

### 功能 1：节点证据生产者（REQ-REC-001）

#### 案例 1.1 — TC-REC-001

| 字段 | 内容 |
|------|------|
| **ID** | TC-REC-001 |
| **对应 Spec** | real-execution-closure/spec.md → SC-REC-001（REQ-REC-001） |
| **优先级** | P0 |
| **测试位置** | server/internal/daemon，函数 TestTC_REC_001，经选择 rec-001 在一次性库运行 |
| **预置条件** | 节点任务 claim 带 authorized-execution/v1、空值、未知非空值各一；preflight 依赖项可被置为失败。 |
| **输入** | daemon prepareClaimedPipelineTask 路径，每种情形与每种失败一个独立 subtest。 |
| **预期结果** | authorized：启动 agent 前恰有一条该任务当前 generation 的回执与自身 effect，run 结束不再消费；任一前置失败不启动 agent；未知值拒绝；空值走原路径，行为与改动前一致；同 generation 重放不新增行。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 1.2 — TC-REC-002

| 字段 | 内容 |
|------|------|
| **ID** | TC-REC-002 |
| **对应 Spec** | real-execution-closure/spec.md → SC-REC-002（REQ-REC-001） |
| **优先级** | P0 |
| **测试位置** | server/internal/handler，函数 TestTC_REC_002，经选择 rec-002 在一次性库运行 |
| **预置条件** | 三个 workspace/CR：无初始 approve 记录；有初始记录且 head 为 approve；有初始记录且 head 已撤销。 |
| **输入** | 对每个节点任务调用 pipeline claim 校验与响应生成。 |
| **预期结果** | 空值 / authorized-execution/v1 / authorized-execution/v1；撤销情形不降级；合同值不受 body 或评论影响。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 1.3 — TC-REC-003

| 字段 | 内容 |
|------|------|
| **ID** | TC-REC-003 |
| **对应 Spec** | real-execution-closure/spec.md → SC-REC-003（REQ-REC-001） |
| **优先级** | P0 |
| **测试位置** | server/internal/daemon，函数 TestTC_REC_003，经选择 rec-003 在一次性库运行 |
| **预置条件** | authorized 且已预消费的节点 endpoint；source、legacy、未预消费的节点 endpoint 各一。 |
| **输入** | 依次提交：challenge X、同字节 X、不同 challenge Y、不同 challenge Z。 |
| **预期结果** | authorized 节点：X 通过、X 重放幂等、Y 通过、Z 为 409；其余三种 endpoint：第二个不同 challenge 即 409；任何 proof 通过都不新增 consumption；每个 challenge 的签名/head/manifest/任务校验各有独立拒绝子用例。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 1.4 — TC-REC-009

| 字段 | 内容 |
|------|------|
| **ID** | TC-REC-009 |
| **对应 Spec** | real-execution-closure/spec.md → SC-REC-008（REQ-REC-001） |
| **优先级** | P0 |
| **测试位置** | server/internal/daemon，函数 TestTC_REC_009，经选择 rec-009 在一次性库运行 |
| **预置条件** | 一个 workspace 的 daemon 信任库；两类任务：已预消费的 authorized、合同值为空的 legacy；每类各有 agent custom_env 含同名变量与不含两种变体。 |
| **输入** | 经与 runTask 相同的顺序组装 agent 环境：先 custom_env 层，再 `injectTaskCRWorkspaceEnv`；authorized 的信任库根取自 `prepareClaimedPipelineTask` 对同一 fixture 的预消费结果。 |
| **预期结果** | authorized：环境含 `CRCTL_EXECUTION_TRUST_ROOT`，其值下存在该任务已安装的 grant，custom_env 的同名配置不改变它；legacy：环境不含该变量，包括 custom_env 配置了它的变体；daemon 进程 `os.Getenv` 前后不变；两个任务各自的环境互不影响。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 2：真实 architecture run（REQ-REC-002、REQ-RUN-001、REQ-RUN-003）

#### 案例 2.1 — TC-REC-004

| 字段 | 内容 |
|------|------|
| **ID** | TC-REC-004 |
| **对应 Spec** | real-execution-closure/spec.md → SC-REC-004、SC-REC-005（REQ-REC-002）；authorized-runner/spec.md → SC-RUN-001、SC-RUN-007 |
| **优先级** | P0 |
| **测试位置** | scripts/aifi45-real-run/run.mjs --scenario architecture-main；需要用户逐项授权真实模型（次数、费用、非 Fable 的模型名）、podman、一次性数据库与 backend/daemon |
| **预置条件** | 新 CR 由 fixture 种到 requirement-approved；agent 工作区无预置 grant；run-config.json 已由用户授权写入（模型、次数上限、费用确认）。 |
| **输入** | 真实认证 owner/admin 调授权路由；真实 daemon 安装并消费授权；独立 T 从原字节重提取来源，再改一个来源字段重提取；StartArchitecture 启动；writer、reviewer 由真实 agent 执行；在节点交接处重启 backend/daemon 一次；run 到架构人工门。 |
| **预期结果** | 打印 `PASS real-run source`、`source-tamper-rejected`、`writer-two-advances-one-receipt`、`review-zero-advance-own-effect`、`human-gate`、`restart-dedup`、`cleanup remaining=0`；每行带 run/task/generation/effect 引用，由脚本查询数据库或 CR 文件得出，不凭进程退出码；失败打印失败阶段、节点与原因并非零退出。 |
| **当前状态** | ❌ 测试缺（待实现；运行需另行授权） |

#### 案例 2.2 — TC-REC-005

| 字段 | 内容 |
|------|------|
| **ID** | TC-REC-005 |
| **对应 Spec** | authorized-runner/spec.md → SC-RUN-006（REQ-RUN-002，撤销后不推进分支） |
| **优先级** | P0 |
| **测试位置** | scripts/aifi45-real-run/run.mjs --scenario architecture-revoke；授权同 TC-REC-004，并计入 architecture run 总上限 |
| **预置条件** | 新 CR 重复真实来源、授权、启动；writer 任务经 DB 确认处于 running。 |
| **输入** | 调真实撤销路由使 head 前移；等 writer 任务结束；检查 reviewer 与节点状态；重启 backend/daemon；再次检查。 |
| **预期结果** | 打印 `PASS real-run revoke-stop`、`restart-revoke-stop`、`cleanup remaining=0`；无 reviewer 新任务、节点完成被 HEAD_REJECTED 拒绝、已有历史行未删除、run 不是 completed 或 failed；若撤销提交前该节点已 passed，打印 INCONCLUSIVE 并非零退出，不记 PASS。 |
| **当前状态** | ❌ 测试缺（待实现；运行需另行授权） |

### 功能 3：撤销后不推进（组件层）

#### 案例 3.1 — TC-REC-006

| 字段 | 内容 |
|------|------|
| **ID** | TC-REC-006 |
| **对应 Spec** | authorized-runner/spec.md → SC-RUN-006（REQ-RUN-002） |
| **优先级** | P0 |
| **测试位置** | server/cmd/server 或 server/internal/governance，函数 TestTC_REC_006，经选择 rec-revoke 在一次性库运行 |
| **预置条件** | 经真实授权与撤销路由（临时 chi 挂载真实 handler）建立已撤销的 head；run 有已完成的 writer 节点与待派发的 reviewer 节点。 |
| **输入** | 调 ResumeActiveRuns；再构造新的 Runner 实例（模拟重启）后再调一次；调节点完成。 |
| **预期结果** | 不新增任务行；节点完成返回 HEAD_REJECTED 对应的等待；detail.runner 为 admission/HEAD_REJECTED；历史行字节不变；run 状态不变。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 4：真实运行驱动（REQ-REC-003）

#### 案例 4.1 — TC-REC-007

| 字段 | 内容 |
|------|------|
| **ID** | TC-REC-007 |
| **对应 Spec** | real-execution-closure/spec.md → SC-REC-006（REQ-REC-003） |
| **优先级** | P0 |
| **测试位置** | scripts/aifi45-real-run/run.mjs --scenario cleanup-smoke；需要 podman 授权，不发起模型请求 |
| **预置条件** | 用 dummy 容器代替 backend/daemon；不提供 run-config.json。 |
| **输入** | 依次：无配置启动；传入未知 scenario 或参数；setup 中途失败；运行中超时；注入某阶段失败。 |
| **预期结果** | 打印 `PASS real-run refuse-without-config`（拒绝发生在创建任何资源之前）、`cleanup-setup-failure remaining=0`、`cleanup-timeout remaining=0`、`stop-on-stage-failure`（后续阶段未执行、失败阶段与原因已输出）、`reject-unknown-argument`；空模型与 Fable 被拒。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 5：不回归（REQ-REC-004）

#### 案例 5.1 — TC-REC-008

| 字段 | 内容 |
|------|------|
| **ID** | TC-REC-008 |
| **对应 Spec** | real-execution-closure/spec.md → SC-REC-007（REQ-REC-004） |
| **优先级** | P0 |
| **测试位置** | scripts/aifi45-disposable/run-selection.mjs（不带 --only，运行 selections.json 全组） |
| **预置条件** | 全部代码改动完成；test-ownership.json 中对该探针的已知失败排除已移除。 |
| **输入** | 全组运行。 |
| **预期结果** | 0 FAIL、0 skip、每个选择至少一个叶子 PASS、`remaining=0`；`handler-wsd-no-recreate-command` 为 PASS。 |
| **当前状态** | ❌ 待实现后运行 |

### 功能 6：workspace 删除后的终态安全（REQ-WSD-001）

#### 案例 6.1 — TC-WSD-005

| 字段 | 内容 |
|------|------|
| **ID** | TC-WSD-005 |
| **对应 Spec** | workspace-delete-execution-tables/spec.md → SC-WSD-005（REQ-WSD-001，MODIFIED） |
| **优先级** | P0 |
| **测试位置** | server/internal/handler/workspace_delete_no_recreate_test.go，函数 TestWorkspaceDeletionRefusesNewCommand，经选择 handler-wsd-no-recreate-command 在一次性库运行 |
| **预置条件** | workspace A 已删除，selection 行按保留策略仍在；生产消费路径所用的无 selection lineage 的 command 输入。 |
| **输入** | 调 ApplyControlCommandTx（显式 workspace 归属）新建 command，另取不存在的 workspace id 与空 WorkspaceID 各一；同时保留既有 reservation 半句测试。 |
| **预期结果** | command 被拒；旧断言原样保留；已删除或不存在的 workspace 得到固定的 workspace-gone 错误，空 WorkspaceID 得到 ErrControlStoreInvalid；不使用随机 UUID 填充 30 个旧 fixture 来绕过 guard。 |
| **当前状态** | 🔴 已声明红灯，本 change 转绿 |

#### 案例 6.2 — TC-WSD-006

| 字段 | 内容 |
|------|------|
| **ID** | TC-WSD-006 |
| **对应 Spec** | workspace-delete-execution-tables/spec.md → SC-WSD-006（REQ-WSD-001，ADDED） |
| **优先级** | P0 |
| **测试位置** | server/internal/handler/workspace_delete_concurrent_test.go，函数 TestWorkspaceDeletionWaitsForInFlightWriter 与 TestWorkspaceDeletionRefusesWriterThatWaited（各含 reservation、command 两个子测试），经选择 handler-wsd-race 在一次性库运行 |
| **预置条件** | 不使用生产 hook：交错二用另一事务对删除自己 sweep 的 `cr_execution_notice` 行加锁，暂停真实 DeleteWorkspace，并以 `FOR KEY SHARE NOWAIT` 探针断言暂停时删除确实持有 workspace 锁；reservation 与 command 各一组。 |
| **输入** | 交错一：写入取得 workspace 锁 → 删除请求锁 → 经 pg_blocking_pids/pg_stat_activity 在 deadline 内确认删除被写入阻塞 → 写入提交 → 删除成功。交错二：删除暂停并持有锁 → 写入请求锁 → 确认写入被删除阻塞 → 释放暂停，删除提交 → 写入以 workspace-gone 失败回滚。 |
| **预期结果** | 交错一：写入先于删除完成；交错二：该 workspace 没有任何新的 reservation、command、cursor、verdict、settlement 行；重复 reservation 的既有幂等行为不变；无死锁。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 6.3 — TC-WSD-007

| 字段 | 内容 |
|------|------|
| **ID** | TC-WSD-007 |
| **对应 Spec** | workspace-delete-execution-tables/spec.md → SC-WSD-006（REQ-WSD-001，ADDED） |
| **优先级** | P0 |
| **测试位置** | server/internal/governance，函数 TestExecutionConsumptionHoldsWorkspaceKeyShare，经选择 governance-wsd-lock 在一次性库运行 |
| **预置条件** | 已签发 binding proof 的 authorized 消费请求；用既有的 `ExecutionConsumptionValidationTestHook`（claim 行锁探针已在用）在 handler 已证明 claim、将要写入的时点执行探针。 |
| **输入** | 在该时点用独立连接（短 statement_timeout）分别执行：对 workspace 行 `SELECT … FOR UPDATE`；普通 `UPDATE workspace SET name = name`。 |
| **预期结果** | `FOR UPDATE` 被阻塞（语句超时，且错误确为超时，不是探针自身出错），普通 UPDATE 不被阻塞；消费请求本身返回 201。 |
| **当前状态** | ❌ 测试缺（待实现） |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试 | E2E（真实） | 状态 |
|----------|---------|----------|-------------|------|
| 节点证据生产者 | — | TC-REC-001/002/003/009 | TC-REC-004 | 🔴 |
| 撤销后不推进 | — | TC-REC-006 | TC-REC-005 | 🔴 |
| 真实运行驱动 | — | TC-REC-007（podman，无模型） | — | 🔴 |
| 删除后终态安全 | — | TC-WSD-005/006/007 | — | 🔴 |
| 回归 | — | TC-REC-008 | — | 🔴 |

## 四、回归风险矩阵

| 风险区域 | 本 change 改动 | 已有回归保护 | 风险等级 |
|----------|---------------|-------------|---------|
| 单 challenge endpoint（SC-AUTH-007） | authorized 已预消费节点放宽到 2 | source/legacy endpoint 仍为 1 的子用例；既有 endpoint 测试 | 🔴 |
| legacy 节点任务 | 新增合同值推导 | TC-REC-001 空值子用例；TC-REC-002 (a) | 🟡 |
| M005 一 generation 一回执 | preflight 成为生产者 | TC-REC-001 重放子用例；atb-001～010 | 🟡 |
| 删除事务锁序 | workspace 行 FOR KEY SHARE 加入写入侧 | TC-WSD-006/007；handler-wsd-delete/atomic/retain | 🔴 |
| 授权节点 agent 环境 | 新增 CRCTL_EXECUTION_TRUST_ROOT 注入 | TC-REC-009；rec-001 的 legacy 子用例；首次真实 A（观察 crctl 能否读到信任根） | 🟡 |
| 33 处 command 测试 fixture | 补 workspace 归属 | TC-REC-008 全组 | 🟡 |
| 真实资源泄漏 | 新驱动 | TC-REC-007 | 🟡 |

## 五、建议补充顺序

1. **第一优先**：TC-REC-001/002/003/009（节点证据生产者）；若未通过，不进入真实运行。
2. **第二优先**：TC-REC-007（cleanup smoke，需 podman 授权）→ TC-REC-004（真实 run A，需模型授权）。首次真实失败只修生产者，不动其余。
3. **第三优先**：TC-REC-006 → TC-REC-005（真实 run B）→ TC-WSD-005/006/007 → TC-REC-008 全组回归。

## 六、同次执行证据计划 / Same-Run Evidence Plan

> 本节随 Gate 2 锁定。在册 TC 12 个，每个有且仅有一条 check，均为 `command` 并各绑定独占 CP，没有 `manual`。TC-REC-004/005 的 CP 即真实运行本身，需要 BUILD 前用户单独授权。
> Locked at Gate 2. 12 TCs, each with exactly one command check bound to its own CP; no manual checks.

覆盖率义务：`not_applicable`（Go 与 Node 脚本，覆盖率采集目前只支持 pytest-cov）。

```stdd-evidence-plan-v1
{
  "task": "real-execution-closure",
  "tasks": [
    "real-execution-closure",
    "workspace-delete-execution-tables"
  ],
  "inputs": [
    {"root": "project", "path": "scripts/aifi45-disposable"},
    {"root": "project", "path": "scripts/aifi45-real-run"},
    {"root": "project", "path": "server/internal/governance"},
    {"root": "project", "path": "server/internal/handler"},
    {"root": "project", "path": "server/internal/daemon"},
    {"root": "project", "path": "server/cmd/server"}
  ],
  "coverage": {
    "applicability": "not_applicable",
    "reason": "被测对象为 Go 服务与 Node 脚本，覆盖率采集目前只支持 pytest-cov；项目配置 quality.coverage.enabled=false"
  },
  "checks": [
    {"tc": "TC-REC-001", "case_id": "main", "requirement": "REQ-REC-001", "scenarios": ["SC-REC-001"], "cp": "CP-REC-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-REC-002", "case_id": "main", "requirement": "REQ-REC-001", "scenarios": ["SC-REC-002"], "cp": "CP-REC-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-REC-003", "case_id": "main", "requirement": "REQ-REC-001", "scenarios": ["SC-REC-003"], "cp": "CP-REC-003", "kind": "command", "applicability": "required"},
    {"tc": "TC-REC-004", "case_id": "main", "requirement": "REQ-REC-002", "scenarios": ["SC-REC-004", "SC-REC-005", "SC-RUN-001", "SC-RUN-007"], "cp": "CP-REC-004", "kind": "command", "applicability": "required"},
    {"tc": "TC-REC-005", "case_id": "main", "requirement": "REQ-RUN-002", "scenarios": ["SC-RUN-006"], "cp": "CP-REC-005", "kind": "command", "applicability": "required"},
    {"tc": "TC-REC-006", "case_id": "main", "requirement": "REQ-RUN-002", "scenarios": ["SC-RUN-006"], "cp": "CP-REC-006", "kind": "command", "applicability": "required"},
    {"tc": "TC-REC-007", "case_id": "main", "requirement": "REQ-REC-003", "scenarios": ["SC-REC-006"], "cp": "CP-REC-007", "kind": "command", "applicability": "required"},
    {"tc": "TC-REC-008", "case_id": "main", "requirement": "REQ-REC-004", "scenarios": ["SC-REC-007"], "cp": "CP-REC-008", "kind": "command", "applicability": "required"},
    {"tc": "TC-REC-009", "case_id": "main", "requirement": "REQ-REC-001", "scenarios": ["SC-REC-008"], "cp": "CP-REC-009", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSD-005", "case_id": "main", "requirement": "REQ-WSD-001", "scenarios": ["SC-WSD-005"], "cp": "CP-WSD-005", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSD-006", "case_id": "main", "requirement": "REQ-WSD-001", "scenarios": ["SC-WSD-006"], "cp": "CP-WSD-006", "kind": "command", "applicability": "required"},
    {"tc": "TC-WSD-007", "case_id": "main", "requirement": "REQ-WSD-001", "scenarios": ["SC-WSD-006"], "cp": "CP-WSD-007", "kind": "command", "applicability": "required"}
  ]
}
```
