# multica 执行恢复与证据闭环 - 测试方案

> Change：2026-11-16-multica-execution-evidence-closure
> 创建日期：2026-11-16
> 对应 SPEC：governance-runner-run-lock、selection-reconciliation、ci-backend-environment 三份 Canonical code spec；agent task 与 change ID 相同。
> 修订（2026-11-16）：两组命令检查与真实库交错已执行通过；真实 CI（TC-MEC-003）因平台账单/额度阻塞，经用户明确裁定本轮延期为 not_applicable（接受风险），权威 CI 验证仍未完成；台账人工核对（TC-MEC-004）待确认。本修订改变受审承诺，须重审 Gate 1+2。

## 一、测试策略

### 1.1 测试金字塔

不设测试比例指标。本轮用两组命令检查和一次台账核对承担已验证的有限保证；真实 CI 核对（TC-MEC-003）经用户裁定延期，作为接受风险显式记录，权威检出与规则加载仍未验证。数据库组证明真实恢复入口的身份与副作用；离线组证明事件边界、精确选择及静态接线；台账检查只证明追溯与测量，不冒充功能保证。真实 CI 仍是权威目标合同，额度恢复后另行验证，不以本地/离线结果冒充。

### 1.2 测试原则

- 复用既有测试文件、run-selection 和 CI，不新增执行框架，不逐调用者或异常再建独立命令。
- 新回归先 RED 后 GREEN；原来已正确的串行、取消和拒绝场景不要求人为制造 RED。
- 断言含目标 ID、节点/任务变化、派发次数、池占用、matched/blocked 与失败原因等具体观测值；PASS 名称只证明测试执行，不能独自证明正确性。
- 四个顶层 Go 测试在同一个一次性库 selection 中执行并按完整 package/test/leaf 对账。新增测试用普通表循环，不产生未列入 expected 的子测试。
- 命令 action 由平台默认 shell 执行；环境通过 Node spawnSync 的 env 注入，不写 VAR=1 前缀，不新增包装脚本。
- 不连共享库、不跑真实 agent、不自行安装依赖或操作未知容器；资源释放覆盖失败路径，等待有总 deadline。
- 复用同次 STDD run 与同次 CI 原始证据，不为各条断言反复执行整组。输入改变后另建 run；manual 不由命令结果代签。
- 真实 CI 是权威目标合同；本轮因账单/额度阻塞（run 43752944966 runner_id=0、六测试 skipped）经用户明确裁定延期，TC-MEC-003 记为 not_applicable（接受风险）并如实保留未验证与阻塞原因，不冒充通过、不继承旧归档 N/A、不绕过平台；非用户裁定的自动 N/A 仍禁止，额度恢复后另行验证。

### 1.3 已有测试资产

| 测试文件/入口 | 本次复用范围 | 类型 | 补充范围 |
|---|---|---|---|
| runner_run_lock_test.go | 两个既有顶层锁测试 | 真实库 | 一个 TestReconcileRunIdentity，串行覆盖三入口×三情形 |
| runner_periodic_resume_test.go | TestMTick003 | 真实库 | 纳入同一精确 selection，不另跑重复组 |
| runner_integration/requirement/code_test.go | 合法 registry/context 与假 enqueuer 夹具 | 真实库设施 | 独立 Runner 池和控制连接，不改变生产接口 |
| selection.test.mjs、selection-decision.test.mjs | 既有合法/拒绝/秘密不回显案例 | 离线 | 一个事件与缺测表驱动矩阵 |
| tools-pin.test.mjs、scripts/ci-scope.test.mjs | 必需文件列表、缺文件与 job 顺序断言 | 离线 | 第四规则文件及一个 CI wiring 测试 |
| daemon/crevents_test.go | 六个快照/事件事实测试 | 真实 CI | 不改测试兜底，核对真实规则日志 |
| CUSTOM.md | 既有明细与索引 | 人工 | 当前 change 追溯、前三数实测、第四数未决 |

## 二、详细测试案例

### TC-MEC-001 - 锁身份与恢复保证

| 字段 | 内容 |
|---|---|
| **ID** | TC-MEC-001 |
| 对应 Spec | REQ-MEC-001/002；SC-MEC-001/002 |
| 优先级 | P0 |
| 预置条件 | 既有一次性 PostgreSQL 与合法夹具；独占 Runner 池 MaxConns=4，控制连接不计入该池；A 锁由控制连接持有 |
| 输入 | CP-MEC-001 对 governance-run-lock 执行 -race -count=1；四个顶层测试为 TestWithRunLockSerialisesSameRun、TestWithRunLockCancelReleasesWaiter、TestReconcileRunIdentity、TestMTick003 |
| 身份交错 | 三个入口分别运行 unchanged/changed/no-active。architecture 等池 AcquireCount 至少新增3次，requirement/code 至少2次；确认锁前查询已完成后才改变目标。changed 将 A 终结、创建时间顺序明确的 B，持 B 锁再释放 A |
| 预期结果 | unchanged 仅推进 A；no-active 无效果；changed 的第一次恢复返回且 B 节点/任务/状态不变。下一次恢复等待 B 锁，释放后推进一次，再唤醒不重复派发；不得在 A 锁下执行 B。原查询/digest 错误传播语义不变 |
| 额外断言 | 既有串行 overlaps=0/calls=2、取消等待者释放且后续可取锁；池4恢复派发=1、首 attempt=1；完整 expected 对账 matched，pass=4/fail=0/skip=0 |
| 当前状态 | 两个锁测试与 TestMTick003 已有；身份矩阵、expected 扩充待 BUILD；本次未执行 |

### TC-MEC-002 - 事件边界、精确名单与接线矩阵

| 字段 | 内容 |
|---|---|
| **ID** | TC-MEC-002 |
| 对应 Spec | REQ-MEC-003/004/005；SC-MEC-003/004/005 |
| 优先级 | P0 |
| 预置条件 | Node 与四个既有测试文件；无数据库、网络或真实 agent |
| 输入 | CP-MEC-002 一次运行 selection、selection-decision、tools-pin 与 ci-scope 四个测试文件；新增 TC-MEC-002 event matrix 和 TC-MEC-002 CI wiring |
| 事件预期 | 旧六字段合法流与 OutputType 合法 output 流 matched；其值仅为空串/frame/error/error-continue。错误值、类型、上下文或未知键 EVENT_INVALID；合法 FailedBuild 只随 fail，仍 blocked。skip/fail/截断及原拒绝案例不变，不回显秘密 |
| 名单预期 | governance-run-lock 恰有四项完整 import package/test/leaf=true，run 完整锚定。删掉任一测试的全部事件、保留其他测试 pass 和进程 exit0，仍 SELECTION_MISMATCH，decideSelection.ok=false；完整流 matched/ok=true。无 expected 的既有语义和原 selection 引用不改 |
| 接线预期 | pin 固定 7a0a2ab57f3f5e2c583c3523bc69d67e7be115c1；REQUIRED_FILES 包含规则文件，缺第四文件与缺其他必需文件均在共同入口失败；backend env 为 github.workspace 下 .aifirst-tools 的 rules.json；同一 pin checkout 与完整性检查早于 Test，原 DB/admin/always teardown 断言保留 |
| 额外断言 | 测试内核对具体结果与配置；命令 exit0、fail0、skipped0 且两个新测试名称出现。字符串检查不是实际 CI 成功的替代证据 |
| 当前状态 | 既有测试已存在；元数据、精确名单和接线增量待 BUILD；本次未执行 |

### TC-MEC-003 - 同一次真实 CI 的权威运行证据

| 字段 | 内容 |
|---|---|
| **ID** | TC-MEC-003 |
| 对应 Spec | REQ-MEC-006；SC-MEC-006 |
| 优先级 | P0（本轮经用户裁定延期，接受风险） |
| 预置条件 | 最终业务提交与独立的提交/push/CI 授权；实际平台账单、凭据和 workflow 可运行。Gate 不替代这些授权。本轮账单/额度未恢复，前置不满足 |
| 输入 | 核对一个对应最终业务 SHA 的真实 CI run，保留 run URL、head SHA、tools pin、job/step 结论和原始事件；复用同一次运行，不逐项再启动整组 |
| 预期结果 | backend-tests 及 Test、共享对账、admin 步实际执行成功；两个生成合同仅 --check 并成功。六个既有测试均真实 pass，且 TestProposedSnapshotReadShapes 输出 checking the snapshot read shapes against the real rules.json |
| 固定六测试 | TestM26B2TestFactsPayload；TestM26B2TestFactsPreserveFailures；TestM26B4CollectorKeepsBothReviewStages；TestM26B4ScanEmitsIndependentTestEvent；TestM26B4ScanTestOnlyAndReviewOnly；TestProposedSnapshotReadShapes |
| 禁止替代 | 本地通过、fixture 回落、跳过、旧提交的绿灯、源码字符串或旧归档 N/A 均不满足。生成物漂移则停止报告，不扩大范围重生成 |
| 当前状态 | 本轮延期：not_applicable（接受风险），权威 CI 验证仍未完成。实际 run 43752944966 因账单 runner_id=0、六测试 skipped，未启动有效执行；不推断通过、不制造运行回执。额度恢复后另行验证，届时仍须满足上述全部预期与禁止替代 |

### TC-MEC-004 - 当前定制台账与有限测量

| 字段 | 内容 |
|---|---|
| **ID** | TC-MEC-004 |
| 对应 Spec | REQ-MEC-007；SC-MEC-007 |
| 优先级 | P1，交付前完成，不作为延期交付授权 |
| 预置条件 | 实际业务差异与当时 CUSTOM 表结构；当前真实 change/task 标识 |
| 输入 | 一次人工核对 CUSTOM 明细、模块/CR 索引与改动文件；记录实际 tree/HEAD、时间及三个测量值 |
| 预期结果 | 当前状态不冒称 CI 通过；稳定编号、CRLF 和历史原记录保留；前三数仅统计 git 跟踪的 server/packages 下 .go/.ts/.tsx/.sql/.mjs：union 标记文件数、union 匹配行数、AIFIRST 匹配行数，union 为 AIFIRST 或 CR-2026-[0-9]{3}，一行多次只计一次 |
| 边界 | 不为改变测量成员而 staging；不混入未跟踪文件；不要求数字只能上涨，下降说明真实原因。第四数明确未决/本次未测，不填旧314冒充当前结果 |
| 当前状态 | required manual，待 BUILD 后实际核对；本次未执行 |

## 三、测试执行矩阵

| 功能 | 离线命令 | 真实库命令 | 真实 CI | 人工台账 |
|---|---|---|---|---|
| 三入口身份、串行/取消/池4 | 不替代 | TC-MEC-001 | 复用已有 backend 路径 | 不替代 |
| 有限元数据、完整选择 | TC-MEC-002 | TC-MEC-001 同次对账 | TC-MEC-003 本轮延期（未验证） | 不替代 |
| pin、规则及 job 接线 | TC-MEC-002 | 沿用已核实环境 | TC-MEC-003 本轮延期（接受风险） | 不替代 |
| 定制追溯与前三数 | 不新增框架 | 不涉及 | 只提供当前事实 | TC-MEC-004 |

## 四、回归风险矩阵

| 风险区域 | 本次改动 | 回归保护 | 风险等级 |
|---|---|---|---|
| 锁后换目标、延迟一次唤醒 | 三入口身份比较 | 确定性交错、B 持锁正向对照、已有锁/恢复测试 | 高 |
| 协议兼容误放行缺测 | 两项已知可选元数据与四项 expected | 原状态机拒绝测试、缺完整测试仍失败 | 高 |
| 规则 fixture 回落、合同漂移 | 单一 pin、共同必需文件、规则 env | 离线接线本轮已验证；实际 CI 加载延期未验证（接受风险）；--check 失败停止 | 高 |
| 追溯与测量误报 | 当前 CUSTOM 记录与前三数 | 一次人工核对；第四数明确未决 | 中 |
| 运行资源与环境 | 不新增依赖/资源机制 | 既有一次性库身份、deadline、失败清理 | 中 |

## 五、建议补充顺序

1. P0：实现并检查 TC-MEC-001/002 增量；已有正确测试与新回归在同次组中验证（本轮已通过）。
2. P0（本轮延期）：TC-MEC-003 真实 CI 因账单/额度阻塞经用户裁定延期，记为 not_applicable 接受风险并如实保留未验证；额度恢复后另行核对，不以本地/离线结果宣布权威闭环。
3. P1：按实际实现完成 TC-MEC-004 台账核对，交付前确认。产品代码（守卫、selection、pin、接线、CUSTOM）本轮交付；延期的仅是权威真实 CI 验证这一证据项，不是把产品功能拆成后续未交付特性。不新增 P2。

## 六、同次执行证据计划

本节随 Gate 2 锁定（本轮修订后须重审）。四个 TC 各一条 check：两个 required command 分别独占一个 CP；TC-MEC-004 为 required manual，不绑定 CP，由用户通过 stdd agent confirm 记录实际确认；TC-MEC-003 本轮经用户裁定延期为 not_applicable（接受风险），声明原因、不绑定 CP、不执行、不继承任何结果，权威 CI 验证仍未完成。不得用命令输出替代人工确认，也不得晚补计划后继续沿用旧 Gate。

Go/Node 不属于当前 STDD 的 pytest-cov 采集范围，因此不声明代码覆盖率保证。inputs 仅列业务源码、测试及受审业务文档，不包含 change 目录或证据产物。DB 命令失败不得退出0或伪造 PASS；离线矩阵必须调用真实解析/决策并断言具体结果。

```stdd-evidence-plan-v1
{
  "task": "2026-11-16-multica-execution-evidence-closure",
  "inputs": [
    {"root": "project", "path": "server/internal/governance/runner.go"},
    {"root": "project", "path": "server/internal/governance/runner_code.go"},
    {"root": "project", "path": "server/internal/governance/runner_requirement.go"},
    {"root": "project", "path": "server/internal/governance/runner_run_lock.go"},
    {"root": "project", "path": "server/internal/governance/runner_run_lock_test.go"},
    {"root": "project", "path": "server/internal/governance/runner_periodic_resume_test.go"},
    {"root": "project", "path": "server/internal/governance/crsync_test.go"},
    {"root": "project", "path": "server/internal/governance/runner_integration_test.go"},
    {"root": "project", "path": "server/internal/governance/runner_requirement_test.go"},
    {"root": "project", "path": "server/internal/governance/runner_code_test.go"},
    {"root": "project", "path": "server/internal/daemon/crevents_test.go"},
    {"root": "project", "path": "server/go.mod"},
    {"root": "project", "path": "scripts/aifi45-disposable/selection.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/selection.test.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/selection-decision.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/selection-decision.test.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/selections.json"},
    {"root": "project", "path": "scripts/aifi45-disposable/tools-pin.mjs"},
    {"root": "project", "path": "scripts/aifi45-disposable/tools-pin.test.mjs"},
    {"root": "project", "path": "scripts/ci-scope.test.mjs"},
    {"root": "project", "path": ".github/aifirst-tools-pin"},
    {"root": "project", "path": ".github/workflows/ci.yml"},
    {"root": "project", "path": "CUSTOM.md"}
  ],
  "coverage": {
    "applicability": "not_applicable",
    "reason": "Go/Node被测栈，当前STDD覆盖率采集仅支持pytest-cov；不声明代码覆盖率保证"
  },
  "checks": [
    {
      "tc": "TC-MEC-001",
      "case_id": "run-lock-identity",
      "requirement": "REQ-MEC-001",
      "scenarios": ["SC-MEC-001", "SC-MEC-002"],
      "cp": "CP-MEC-001",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-MEC-002",
      "case_id": "event-and-wiring-matrix",
      "requirement": "REQ-MEC-003",
      "scenarios": ["SC-MEC-003", "SC-MEC-004", "SC-MEC-005"],
      "cp": "CP-MEC-002",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-MEC-003",
      "case_id": "real-ci-authority",
      "requirement": "REQ-MEC-006",
      "scenarios": ["SC-MEC-006"],
      "kind": "manual",
      "applicability": "not_applicable",
      "reason": "真实 CI 受平台账单/额度阻塞（run 43752944966 runner_id=0、六测试 skipped，未启动有效执行），经用户明确裁定本轮延期该必需证据；权威 CI 验证仍未完成，作为接受风险显式记录，不冒充通过、不继承旧归档 N/A，额度恢复后另行验证"
    },
    {
      "tc": "TC-MEC-004",
      "case_id": "custom-trace",
      "requirement": "REQ-MEC-007",
      "scenarios": ["SC-MEC-007"],
      "kind": "manual",
      "applicability": "required"
    }
  ]
}
```

Gate 2 前仅预检：`stdd agent verify 2026-11-16-multica-execution-evidence-closure --change 2026-11-16-multica-execution-evidence-closure --dry-run`。本计划不授权执行 CP、提交、push 或触发 CI。
