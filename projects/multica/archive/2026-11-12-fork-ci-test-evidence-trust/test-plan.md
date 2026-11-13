# fork CI 与测试证据可信性修复 - 测试方案与详细案例

> 版本：1.0（change `2026-11-12-fork-ci-test-evidence-trust`）
> 创建日期：2026-11-12
> 对应 Phase 2 Spec：`canonical/specs/code|agent/` 下 5 个 capability（ci-backend-environment、test-ownership-and-ci-reconciliation、selection-reconciliation、workspace-delete-execution-tables、ci-credential-and-frontend-typecheck）；设计见 `design.md`。
> 修订 2026-11-13（ADJ-047，Gate 2 以 `--reapprove` 重签）：TC-CBE-005、TC-TOR-004、TC-CCF-003 移交后续 change，证据计划分母 22 → **19**（18 command + 1 manual）。移交原文见 §七 与 `validation/handoff/handoff-to-successor-change.md`；本 change **不**对这 3 项作通过声明。

## 一、测试策略

### 1.1 测试金字塔

- **单元（Node）**：`scripts/aifi45-disposable` 下新增与修改的纯函数/小工具（决策函数、pin、证据对账、归属表、ci-provision、tools-access），全部注入依赖，不起容器，毫秒级。
- **集成（Go + 一次性 Postgres）**：只经 `run-selection.mjs` 自建的 podman 实例，覆盖 nonce 门禁每条件、workspace 删除的真实行为、保留类不变、事务回滚。
- **静态/契约**：`ci.yml`、`ci-paths.json`、governance 测试源码的契约检查（无开发机路径、skip→Fatal、无字面 tools ref）。
- **真实 CI / 独立入口 / 文档**：以 `manual` 记录（推送授权、tools pin、管理员 PAT、WSL root 隔离、验收报告），不用本地命令冒充。其中 3 项（TC-CBE-005、TC-TOR-004、TC-CCF-003）已移交后续 change，见 §七。

### 1.2 测试原则

- 红灯优先：每个新增检查先写 RED 并确认红，再实现。决策类逻辑加**变异验证**（改回旧写法必须变红），结果写入证据。
- 每个拒绝条件单独退化测试（EXP-2026-0005）；多行/流式输入逐行解析、解析失败硬失败（EXP-2026-0003）。
- 真实资源测试的清理覆盖失败路径：一次性实例释放放 `finally`，前后核对容器清单（EXP-2026-0004）。
- 测试数据用随机/唯一键，不用常量 id（EXP-2026-0001）。
- 通过的定义：skip 为 0 且至少一个叶子 PASS；`go test -run` 无匹配不算通过。
- 不为过测试而放宽断言、跳过用例或只改清单。

### 1.3 已有测试资产

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|----------|--------|------|----------|
| `scripts/aifi45-disposable/*.test.mjs` | 42（本地 `node --test` 全过，CI 未运行） | 单元 | instance/provision/selection/run-selection 既有契约 |
| `server/internal/handler/workspace_delete_manifest_test.go` | 分类覆盖（不校验删除行为） | 集成 | schema 表分类覆盖 |
| `server/internal/governance/execution_control_migration_test.go` | TestChannelMigration* 4 项 | 集成 | 648 迁移 up/down/reapply，对初始状态敏感 |
| `server/cmd/server/integration_test.go`、`governance/crsync_test.go` | 各 1 个门禁测试 | 集成 | 仅覆盖 marker 被改一个条件 |
| `scripts/ci-scope.test.mjs`、`scripts/test-go.test.sh` | 既有 | 单元 | scope 判定、test-go 参数 |

## 二、详细测试案例

### 功能：ci-backend-environment

#### 案例 TC-CBE-001 — SC-CBE-001

| 字段 | 内容 |
|------|------|
| **ID** | TC-CBE-001 |
| **对应 Spec** | ci-backend-environment → Requirement REQ-CBE-001 → Scenario SC-CBE-001 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | 给定一个可连接的 Postgres 管理员 URL（本地用注入的假连接）， |
| **输入** | 执行 ci-provision up 再 down，以及 up 未完成时执行 down。 |
| **预期结果** | SHALL 由 up 用既有 createDisposableDatabase 建出符合 TestMain 全部身份检查的库与角色（库名 aifi45_tmp_<nonce>、角色 aifi45_role_<nonce>、库与角色 marker、非超级用户），并把 DATABASE_URL、AIFI45_DISPOSABLE_NONCE 写入环境文件且先对口令发出 ::add-mask::；SHALL 由 down 在 marker 匹配时删除库与角色；marker 不符 SHALL 拒绝删除并非 0 退出。；handle 缺失（up 在写出前失败）时 down SHALL 以 0 退出并说明无资源可清理。；任何日志、stdout/stderr 与 handle 文件 SHALL NOT 含明文口令；GITHUB_ENV 中的 DATABASE_URL 承载 job 级一次性角色口令，写入前 SHALL 先对该口令发出 ::add-mask::，且该口令 SHALL NOT 被复用于任何非一次性资源。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap scripts/aifi45-disposable/ci-provision.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-CBE-002 — SC-CBE-002

| 字段 | 内容 |
|------|------|
| **ID** | TC-CBE-002 |
| **对应 Spec** | ci-backend-environment → Requirement REQ-CBE-001 → Scenario SC-CBE-002 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | cmd/server 与 governance 各自的 verifyDisposableTestDatabase， |
| **输入** | 对 nonce 格式、库名、角色名、session_user 不等于 current_user、库非所有者、库 marker、角色 marker、superuser、createdb、createrole、bypassrls 逐条单独构造失败。 |
| **预期结果** | SHALL 每一条单独退化都被拒绝，且该条件由独立命名的子测试逐条归因；合法的 nonce 库 SHALL 通过。；该测试 SHALL 在 runner 自建一次性库内真实执行，skip 为 0 且至少一个叶子 PASS。；门禁本身 SHALL NOT 被放宽。 |
| **验证方式** | 命令型（本地可执行）：`node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only ci-gate-identity` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-CBE-003 — SC-CBE-003

| 字段 | 内容 |
|------|------|
| **ID** | TC-CBE-003 |
| **对应 Spec** | ci-backend-environment → Requirement REQ-CBE-002 → Scenario SC-CBE-003 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | 仓库存在 .github/aifirst-tools-pin（单行 40 位 hex），ci.yml 的两个消费者从它读取 ref， |
| **输入** | 运行 tools-pin 的 read 与 check：pin 文件合法或非法，检出目录缺少 execution-control-protocol.mjs、control-vectors.json 或 crctl.mjs 之一。 |
| **预期结果** | SHALL read 对非 40 位 hex 或多行文件硬失败；SHALL check 在任一必需文件缺失时非 0 退出并打印 pin 与缺失文件名；全部存在时 SHALL 退出 0；ci.yml 中 SHALL 不再出现 tools 的字面 commit。；对 ci.yml 字面 ref 的检查 SHALL 逐行解析（split(/\r?\n/)），解析失败硬失败。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap scripts/aifi45-disposable/tools-pin.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-CBE-004 — SC-CBE-004

| 字段 | 内容 |
|------|------|
| **ID** | TC-CBE-004 |
| **对应 Spec** | ci-backend-environment → Requirement REQ-CBE-002 → Scenario SC-CBE-004 |
| **优先级** | P1 |
| **置信度** | medium |
| **预置条件** | server/internal/governance 与 crosslang_test 下的 *_test.go， |
| **输入** | 静态契约检查：搜索 C:/Users/ 开发机绝对路径，以及依赖 AIFI45_TOOLS_ROOT 或 CRCTL_MJS 的测试在环境变量缺失时的处理。 |
| **预期结果** | SHALL 源码中不含开发机绝对路径默认值；SHALL 缺失 CRCTL_MJS 或 AIFI45_TOOLS_ROOT 的测试以 Fatal 结束而不是 Skip；契约检查本身 SHALL 能对注入了旧默认路径或 t.Skip 的样例变红。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap scripts/aifi45-disposable/go-test-env-contract.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

> ⏭ **已移交后续 change（ADJ-047，2026-11-13）**：TC-CBE-005 / SC-CBE-005 **不计入**本 change 的计划与覆盖分母。
> 原因：验收对象是真实 CI run，需 multica 推送授权、管理员 PAT 与仓库 secret；本 change 未获提交/推送/部署授权。
> 移交前定义逐字保留于下方 HTML 注释（机器不解析）；取回点 `validation/handoff/handoff-to-successor-change.md` §7.1。

<!-- 移交前定义（原文保留）：
#### 案例 TC-CBE-005 — SC-CBE-005

| 字段 | 内容 |
|------|------|
| **ID** | TC-CBE-005 |
| **对应 Spec** | ci-backend-environment → Requirement REQ-CBE-002 → Scenario SC-CBE-005 |
| **优先级** | P1 |
| **置信度** | low |
| **预置条件** | CI 的 backend-tests 在修复后的 ci.yml 下运行（需推送授权与 tools pin 可用，见 design U1）， |
| **输入** | 查看该 run 的 Test 步骤与 ci-evidence 步骤。 |
| **预期结果** | SHALL cmd/server、governance、crosslang_test、handler 各自有通过的测试且无名单外 skip；若走 U1 路径 β（tools 未推送），SHALL 如实记录 tools 相关测试未验证并使 pin 完整性检查失败，不得 skip 或报绿。；验收报告 SHALL 记录 run id、commit、各 job 结论。 |
| **验证方式** | 人工（manual）：`依赖推送授权与 tools pin 可用；真实 CI run 的结果只能在验收报告中人工确认` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |
-->

### 功能：test-ownership-and-ci-reconciliation

#### 案例 TC-TOR-001 — SC-TOR-001

| 字段 | 内容 |
|------|------|
| **ID** | TC-TOR-001 |
| **对应 Spec** | test-ownership-and-ci-reconciliation → Requirement REQ-TOR-001 → Scenario SC-TOR-001 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | test-ownership.json 列出独立入口承担的测试（package、test、entry、reason）， |
| **输入** | 运行 check：条目对应真实的 func TestX(、拼错的条目、缺 reason 的条目、重复条目。 |
| **预期结果** | SHALL check 对不存在、缺 reason、重复的条目非 0 退出并指名；通过时 SHALL 输出名单与数量；SHALL skip-regex 输出 ^(A|B|…)$ 且名称中的正则元字符被转义。；初始条目 SHALL 含 daemon.TestChannelIsolation 与 governance 的两个状态敏感探针，其余条目 SHALL 由整包基线证据加入。；归属表 SHALL 允许 owner=known-finding 的条目承载经用户裁定不在本 change 内修复的已知失败；该条目 SHALL 指名后继议题与复现命令，SHALL 与其他条目一样被 check 核对真实 func、被 skip-regex 排除、被 ci-evidence 核对排除生效，且 SHALL NOT 被计为覆盖。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap scripts/aifi45-disposable/test-ownership.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-TOR-002 — SC-TOR-002

| 字段 | 内容 |
|------|------|
| **ID** | TC-TOR-002 |
| **对应 Spec** | test-ownership-and-ci-reconciliation → Requirement REQ-TOR-001 → Scenario SC-TOR-002 |
| **优先级** | P1 |
| **置信度** | medium |
| **预置条件** | scripts/test-go.sh 新增 --skip-regex 与 --json-out（上游文件挂钩点）， |
| **输入** | 带与不带这两个参数运行 test-go.test.sh；被测 go 以假命令代替。 |
| **预期结果** | SHALL --skip-regex 原样传给 go test -skip；SHALL --json-out 同时落盘事件流并透传 go test 的退出码（pipefail）；缺参数值 SHALL 拒绝；不带新参数时行为 SHALL 与改前一致。 |
| **验证方式** | 命令型（本地可执行）：`bash scripts/test-go.test.sh` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-TOR-003 — SC-TOR-003

| 字段 | 内容 |
|------|------|
| **ID** | TC-TOR-003 |
| **对应 Spec** | test-ownership-and-ci-reconciliation → Requirement REQ-TOR-001 → Scenario SC-TOR-003 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | ci-evidence 读取 go test -json 事件流及声明（必需包、skip 允许名单、排除名单）， |
| **输入** | 分别喂入：必需包 0 个通过测试、包无事件（TestMain 静默 exit 0）、名单外 skip、排除项出现在事件流、半截 JSON 或缺包级结论、全部合规。 |
| **预期结果** | SHALL 前五种每一种单独非 0 退出并指明包或测试；合规流 SHALL 退出 0；SHALL 逐行解析且解析失败硬失败（不取首行、不静默忽略）；SHALL 打印排除名单与数量。；对 handler TestMain 在库不可达时 exit 0 的情形，SHALL 以必需包 0 通过测试判红。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap scripts/aifi45-disposable/ci-evidence.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

> ⏭ **已移交后续 change（ADJ-047，2026-11-13）**：TC-TOR-004 / SC-TOR-004 **不计入**本 change 的计划与覆盖分母。
> 原因：需要 WSL AIFI-ISO root 隔离环境；用户已裁定保持 UNCOVERED，且不启动 WSL、不以同 uid 对照代替。
> 移交前定义逐字保留于下方 HTML 注释（机器不解析）；取回点 `validation/handoff/handoff-to-successor-change.md` §7.2。

<!-- 移交前定义（原文保留）：
#### 案例 TC-TOR-004 — SC-TOR-004

| 字段 | 内容 |
|------|------|
| **ID** | TC-TOR-004 |
| **对应 Spec** | test-ownership-and-ci-reconciliation → Requirement REQ-TOR-001 → Scenario SC-TOR-004 |
| **优先级** | P1 |
| **置信度** | medium |
| **预置条件** | D1 的独立入口：TestChannelIsolation 经 WSL AIFI-ISO（root 加 AIFI45_ISOLATION_PROFILE），两个状态敏感探针经 run-selection 的 down/reapply 初始状态， |
| **输入** | 本地在授权后真实执行并保存输出。 |
| **预期结果** | SHALL 每项通过数不少于 1、skip 为 0，并把命令、退出码、通过数记入验收报告；任一项不能执行（如 WSL profile 失效）时 SHALL 如实列为未覆盖，不得以同 uid 对照代替。；执行前 SHALL 先向用户说明并征得同意（WSL 启动、podman 实例）。 |
| **验证方式** | 人工（manual）：`需要 WSL root 与一次性 podman 实例，须单独授权；结果由人工在验收报告确认` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |
-->

#### 案例 TC-TOR-005 — SC-TOR-005

| 字段 | 内容 |
|------|------|
| **ID** | TC-TOR-005 |
| **对应 Spec** | test-ownership-and-ci-reconciliation → Requirement REQ-TOR-001 → Scenario SC-TOR-005 |
| **优先级** | P1 |
| **置信度** | medium |
| **预置条件** | change 的验收报告 validation/acceptance-report.md， |
| **输入** | BUILD 结束时检查。 |
| **预期结果** | SHALL 逐项列出实际执行的 CI run 与本地命令、退出码、通过/失败/跳过数、测试范围与未覆盖项；对 skip 大于 0 的包 SHALL 逐个说明；SHALL NOT 出现未执行却标通过的项。 |
| **验证方式** | 人工（manual）：`文档类验收，人工逐项核对` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

### 功能：selection-reconciliation

#### 案例 TC-SEL-001 — SC-SEL-001

| 字段 | 内容 |
|------|------|
| **ID** | TC-SEL-001 |
| **对应 Spec** | selection-reconciliation → Requirement REQ-SEL-001 → Scenario SC-SEL-001 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | 一个配置了非空 expected 数组的 selection，go test -json 流缺少某个预期测试或含多余、重复事件， |
| **输入** | decideSelection 以 verifyGoTestSelection 的真实返回值判定。 |
| **预期结果** | SHALL status 不是 matched 时 ok 为 false，reasons 含该 reason 原文并输出 blocked=<reason>；status 为 matched 且其余判定通过时 SHALL ok 为 true。；单测 SHALL 使用 verifyGoTestSelection 的真实输出而不是手写 {matched, blocked} 形状；把决策函数改回读取 .matched 与 .blocked 的旧写法 SHALL 使该单测变红（变异验证记入证据）。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap scripts/aifi45-disposable/selection-decision.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-SEL-002 — SC-SEL-002

| 字段 | 内容 |
|------|------|
| **ID** | TC-SEL-002 |
| **对应 Spec** | selection-reconciliation → Requirement REQ-SEL-001 → Scenario SC-SEL-002 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | selections.json 中未设置 expected 的 selection（当前全部条目）， |
| **输入** | decideSelection 与 run-selection 运行。 |
| **预期结果** | SHALL 沿用旧判定：test.code 为 0 且 fail 为 0 且 skip 为 0 且 pass 大于 0；PASS 与 FAIL 输出行 SHALL 逐字不变。；run-selection.test.mjs 既有断言 SHALL 全部保持通过且不被改弱。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap scripts/aifi45-disposable/run-selection.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-SEL-003 — SC-SEL-003

| 字段 | 内容 |
|------|------|
| **ID** | TC-SEL-003 |
| **对应 Spec** | selection-reconciliation → Requirement REQ-SEL-001 → Scenario SC-SEL-003 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | selection 的 expected 字段已存在但为空数组、非数组或元素非法， |
| **输入** | decideSelection 判定。 |
| **预期结果** | SHALL ok 为 false 且 reasons 含 EXPECTED_INVALID；SHALL NOT 静默当作未配置。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap --test-name-pattern=EXPECTED_INVALID scripts/aifi45-disposable/selection-decision.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-SEL-004 — SC-SEL-004

| 字段 | 内容 |
|------|------|
| **ID** | TC-SEL-004 |
| **对应 Spec** | selection-reconciliation → Requirement REQ-SEL-001 → Scenario SC-SEL-004 |
| **优先级** | P1 |
| **置信度** | medium |
| **预置条件** | scripts/aifi45-disposable 下的 node 单测与 ci-paths.json 的 scope 映射， |
| **输入** | ci-scope 对「仅改 scripts/aifi45-disposable/**」的变更判定；检查 ci.yml 的 script-checks。 |
| **预期结果** | SHALL 该变更命中 scripts 与 backend scope；script-checks SHALL 含 node --test scripts/aifi45-disposable 的步骤，且 pg 依赖获取失败时步骤失败。；改 run-selection 不触发任何 CI job 的现状 SHALL 不再成立。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap scripts/ci-scope.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

### 功能：workspace-delete-execution-tables

#### 案例 TC-WSD-001 — SC-WSD-001

| 字段 | 内容 |
|------|------|
| **ID** | TC-WSD-001 |
| **对应 Spec** | workspace-delete-execution-tables → Requirement REQ-WSD-001 → Scenario SC-WSD-001 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | 一次性库已迁移到最新，清单新增 retain 分类并按设计逐表登记， |
| **输入** | 运行 TestWorkspaceDeletionManifestCoversPublicSchema 与 retain 分类断言。 |
| **预期结果** | SHALL 公共 schema 中每张表有且仅有一个分类，19 张 cr_execution_* 表分类与设计一致；retain 表 SHALL 有禁 DELETE 触发器且无指向 workspace 的外键；既有规则 SHALL 不变（KEEP 不带 workspace_id，DETACH 与 SETTLE 带 workspace_id）；SHALL 在一次性库真实执行且 skip 为 0。；删去任一登记或回退 retain 断言 SHALL 使测试变红。 |
| **验证方式** | 命令型（本地可执行）：`node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-manifest` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-WSD-002 — SC-WSD-002

| 字段 | 内容 |
|------|------|
| **ID** | TC-WSD-002 |
| **对应 Spec** | workspace-delete-execution-tables → Requirement REQ-WSD-001 → Scenario SC-WSD-002 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | workspace A 与 B 各有 19 张表中每类至少一行， |
| **输入** | 真实 DeleteWorkspace(A)。 |
| **预期结果** | SHALL A 的 cr_execution_notice 与 cr_execution_dispatch_root 行被删除；B 的同表行及 B 的全部其他行 SHALL 不变。；删除步骤 SHALL 在既有事务内（追加到 deleteSteps）。；SHALL 除补 TRUNCATE 守卫的迁移 649 外不新增迁移、不新增触发器例外（不得为 append-only 触发器开任何删除例外）、不改 sqlc 查询；649 SHALL 只加语句级 TRUNCATE 拒绝、复用 cr_execution_binding_issue 与 cr_execution_consumption 各自已有的 append_only 函数，并 SHALL 配套 down 迁移。 |
| **验证方式** | 命令型（本地可执行）：`node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-delete` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-WSD-003 — SC-WSD-003

| 字段 | 内容 |
|------|------|
| **ID** | TC-WSD-003 |
| **对应 Spec** | workspace-delete-execution-tables → Requirement REQ-WSD-001 → Scenario SC-WSD-003 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | 同上，A 有 retain 类与 keep 类行， |
| **输入** | DeleteWorkspace(A) 之后。 |
| **预期结果** | SHALL retain 类 A 行逐字节不变（含 digest 列）；keep 类行 SHALL 不变；对 retain 表的普通 DELETE 与 TRUNCATE SHALL 仍被触发器拒绝。 |
| **验证方式** | 命令型（本地可执行）：`node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-retain` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-WSD-004 — SC-WSD-004

| 字段 | 内容 |
|------|------|
| **ID** | TC-WSD-004 |
| **对应 Spec** | workspace-delete-execution-tables → Requirement REQ-WSD-001 → Scenario SC-WSD-004 |
| **优先级** | P1 |
| **置信度** | medium |
| **预置条件** | 删除事务在追加步骤之后的某一步失败， |
| **输入** | 事务回滚。 |
| **预期结果** | SHALL A 的 notice 与 dispatch_root 行恢复，且 A 的其他行未被半删。 |
| **验证方式** | 命令型（本地可执行）：`node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-atomic` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-WSD-005 — SC-WSD-005

| 字段 | 内容 |
|------|------|
| **ID** | TC-WSD-005 |
| **对应 Spec** | workspace-delete-execution-tables → Requirement REQ-WSD-001 → Scenario SC-WSD-005 |
| **优先级** | P1 |
| **置信度** | medium |
| **预置条件** | workspace A 已删除、其 contract_selection 行按保留策略仍存在（D2「命令禁新建」半句）， |
| **输入** | 经现有创建路径为该 selection 新建 reservation 或 command。 |
| **预期结果** | reservation 半句 SHALL 被拒绝，本 change SHALL 在 CreateReservationTx 内加 workspace 存在性检查使其成立；command 半句经探针实测当前代码放行，按 U3 用户裁定（R5）不在本 change 内修复，SHALL 保持探针断言原样（红灯即为已声明的发现），SHALL 登记为可找回的已知失败并指向后继议题，不得静默放宽断言、不得改触发器、不得把红灯洗成绿灯。；本 change SHALL NOT 实现 command 与 cursor 的收敛转移。；两个半句 SHALL 各自独立成测试函数，使 reservation 半句可独立绿、command 半句可独立红。；command 半句的登记 SHALL 能被 test-ownership check 与归档后的基线规格找回。 |
| **验证方式** | 命令型（本地可执行）：`node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-no-recreate` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

### 功能：ci-credential-and-frontend-typecheck

#### 案例 TC-CCF-001 — SC-CCF-001

| 字段 | 内容 |
|------|------|
| **ID** | TC-CCF-001 |
| **对应 Spec** | ci-credential-and-frontend-typecheck → Requirement REQ-CCF-001 → Scenario SC-CCF-001 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | tools-access 可注入 fetch， |
| **输入** | 分别返回：凭据为空、401、403、404、200、网络异常、其他状态。 |
| **预期结果** | SHALL 映射为 missing、rejected、no-access-or-pin-not-found、ok、inconclusive，非 ok 时非 0 退出；SHALL 任何输出与错误信息不含 token 值；请求头 SHALL 仅在 fetch 调用内使用。 |
| **验证方式** | 命令型（本地可执行）：`node --test --test-reporter=tap scripts/aifi45-disposable/tools-access.test.mjs` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

#### 案例 TC-CCF-002 — SC-CCF-002

| 字段 | 内容 |
|------|------|
| **ID** | TC-CCF-002 |
| **对应 Spec** | ci-credential-and-frontend-typecheck → Requirement REQ-CCF-001 → Scenario SC-CCF-002 |
| **优先级** | P0 |
| **置信度** | high |
| **预置条件** | packages/views 的 use-logout.test.ts 改用 @multica/core 包导入， |
| **输入** | 运行 @multica/views 的 typecheck 与该测试文件。 |
| **预期结果** | SHALL typecheck 0 条 TS6059；use-logout.test.ts SHALL 全部通过；其断言 SHALL 与改前等价（不删除、不放宽）。；若修好 typecheck 后暴露其他前端失败，SHALL 先报告再裁定范围（design U4）。 |
| **验证方式** | 命令型（本地可执行）：`pnpm --filter @multica/views typecheck` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |

> ⏭ **已移交后续 change（ADJ-047，2026-11-13）**：TC-CCF-003 / SC-CCF-003 **不计入**本 change 的计划与覆盖分母。
> 原因：需管理员按最小权限更新 `AIFIRST_TOOLS_READ_TOKEN` 后重跑 transitions-contract-check；本 change 不得读取/创建/轮换凭据，也没有真实 CI job 结论。
> 移交前定义逐字保留于下方 HTML 注释（机器不解析）；取回点 `validation/handoff/handoff-to-successor-change.md` §7.3。

<!-- 移交前定义（原文保留）：
#### 案例 TC-CCF-003 — SC-CCF-003

| 字段 | 内容 |
|------|------|
| **ID** | TC-CCF-003 |
| **对应 Spec** | ci-credential-and-frontend-typecheck → Requirement REQ-CCF-001 → Scenario SC-CCF-003 |
| **优先级** | P2 |
| **置信度** | low |
| **预置条件** | 管理员已按最小权限更新 AIFIRST_TOOLS_READ_TOKEN， |
| **输入** | 重跑 transitions-contract-check。 |
| **预期结果** | SHALL 该 job 通过；管理员未完成更新时 SHALL 如实列为未闭合。；本 change SHALL NOT 读取、创建或轮换凭据。 |
| **验证方式** | 人工（manual）：`依赖管理员动作与 CI 推送，无法由本地命令代替` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED） |
-->

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试 | E2E / 真实 CI | 状态 |
|----------|---------|----------|---------------|------|
| ci-backend-environment | CBE-001/003/004 | CBE-002（一次性库） | CBE-005 ⏭ 已移交（§七） | 🔴 |
| test-ownership-and-ci-reconciliation | TOR-001/002/003 | — | TOR-004 ⏭ 已移交（§七）、TOR-005（报告，manual） | 🔴 |
| selection-reconciliation | SEL-001/002/003/004 | — | CI script-checks 真跑（随推送） | 🔴 |
| workspace-delete-execution-tables | — | WSD-001…005（一次性库） | — | 🔴 |
| ci-credential-and-frontend-typecheck | CCF-001 | CCF-002（tsc/vitest） | CCF-003 ⏭ 已移交（§七） | 🔴 |

## 四、回归风险矩阵

| 风险区域 | 本次改动 | 已有回归保护 | 风险等级 |
|----------|----------|--------------|---------|
| `DeleteWorkspace` 事务 | 追加一步删除 notice/dispatch_root | handler 既有删除测试；WSD-002/003/004 | 🟡 |
| 清单测试语义 | 新增 retain 分类 | 上游分类覆盖测试；WSD-001 | 🟡 |
| run-selection 判定 | 抽决策函数、读正确字段 | run-selection.test.mjs；SEL-001/002/003 | 🟡 |
| test-go.sh | 新增可选参数 | test-go.test.sh；TOR-002 | 🟡 |
| ci.yml / ci-paths.json | 新增 provision/tools/evidence/script-checks 步骤 | ci-scope.test.mjs；真实 CI run（推送后） | 🔴 |
| nonce 门禁 | 仅补测试，不改逻辑 | CBE-002 | 🟢 |
| views 测试导入 | 包导入替换相对导入 | CCF-002、views 全量 vitest | 🟢 |

## 五、建议补充顺序

1. **第一优先（BUILD 先做）**：TC-CBE-001、TC-CBE-002、TC-CBE-003、TC-TOR-001、TC-TOR-003、TC-SEL-001、TC-SEL-002、TC-SEL-003、TC-WSD-001、TC-WSD-002、TC-WSD-003、TC-CCF-001、TC-CCF-002
2. **第二优先**：TC-CBE-004、TC-TOR-002、TC-TOR-005、TC-SEL-004、TC-WSD-004、TC-WSD-005
3. **已移交后续 change**（不计入本 change）：TC-CBE-005、TC-TOR-004、TC-CCF-003，见 §七。

## 六、同次执行证据计划 / Same-Run Evidence Plan

> 本节随 Gate 2 锁定（2026-11-13 以 `--reapprove` 重签，ADJ-047）。**在册 TC 19 个，每个有且仅有一条 check**：18 条 `command` 各绑定独占 CP，1 条 `manual`（TC-TOR-005 验收报告核对）不绑定 CP，由 `stdd agent confirm` 人工确认。已移交的 TC-CBE-005 / TC-TOR-004 / TC-CCF-003 见 §七，**不**在本计划内、不计入分母。
> Locked at Gate 2 (re-signed 2026-11-13 with `--reapprove`). 19 in-scope TCs, each with exactly one check; 3 scenarios handed off per §七 and excluded from this plan.

覆盖率义务：`not_applicable`（Go/Node/CI 配置与前端类型检查，覆盖率采集目前仅支持 pytest-cov）。

```stdd-evidence-plan-v1
{
  "task": "ci-backend-environment",
  "tasks": [
    "ci-backend-environment",
    "test-ownership-and-ci-reconciliation",
    "selection-reconciliation",
    "workspace-delete-execution-tables",
    "ci-credential-and-frontend-typecheck"
  ],
  "inputs": [
    {
      "root": "project",
      "path": "scripts/aifi45-disposable"
    },
    {
      "root": "project",
      "path": "scripts/test-go.sh"
    },
    {
      "root": "project",
      "path": "scripts/test-go.test.sh"
    },
    {
      "root": "project",
      "path": "scripts/ci-scope.mjs"
    },
    {
      "root": "project",
      "path": "scripts/ci-scope.test.mjs"
    },
    {
      "root": "project",
      "path": ".github/workflows/ci.yml"
    },
    {
      "root": "project",
      "path": ".github/ci-paths.json"
    },
    {
      "root": "project",
      "path": "server/internal/governance"
    },
    {
      "root": "project",
      "path": "server/internal/handler"
    },
    {
      "root": "project",
      "path": "server/cmd/server"
    },
    {
      "root": "project",
      "path": "packages/views/auth"
    }
  ],
  "coverage": {
    "applicability": "not_applicable",
    "reason": "被测对象为 Go、Node、CI 配置与前端类型检查，覆盖率采集目前只支持 pytest-cov；项目配置 quality.coverage.enabled=false"
  },
  "checks": [
    {
      "tc": "TC-CBE-001",
      "case_id": "main",
      "requirement": "REQ-CBE-001",
      "scenarios": [
        "SC-CBE-001"
      ],
      "cp": "CP-CBE-001",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-CBE-002",
      "case_id": "main",
      "requirement": "REQ-CBE-001",
      "scenarios": [
        "SC-CBE-002"
      ],
      "cp": "CP-CBE-002",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-CBE-003",
      "case_id": "main",
      "requirement": "REQ-CBE-002",
      "scenarios": [
        "SC-CBE-003"
      ],
      "cp": "CP-CBE-003",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-CBE-004",
      "case_id": "main",
      "requirement": "REQ-CBE-002",
      "scenarios": [
        "SC-CBE-004"
      ],
      "cp": "CP-CBE-004",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-TOR-001",
      "case_id": "main",
      "requirement": "REQ-TOR-001",
      "scenarios": [
        "SC-TOR-001"
      ],
      "cp": "CP-TOR-001",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-TOR-002",
      "case_id": "main",
      "requirement": "REQ-TOR-001",
      "scenarios": [
        "SC-TOR-002"
      ],
      "cp": "CP-TOR-002",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-TOR-003",
      "case_id": "main",
      "requirement": "REQ-TOR-001",
      "scenarios": [
        "SC-TOR-003"
      ],
      "cp": "CP-TOR-003",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-TOR-005",
      "case_id": "main",
      "requirement": "REQ-TOR-001",
      "scenarios": [
        "SC-TOR-005"
      ],
      "kind": "manual",
      "applicability": "required"
    },
    {
      "tc": "TC-SEL-001",
      "case_id": "main",
      "requirement": "REQ-SEL-001",
      "scenarios": [
        "SC-SEL-001"
      ],
      "cp": "CP-SEL-001",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-SEL-002",
      "case_id": "main",
      "requirement": "REQ-SEL-001",
      "scenarios": [
        "SC-SEL-002"
      ],
      "cp": "CP-SEL-002",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-SEL-003",
      "case_id": "main",
      "requirement": "REQ-SEL-001",
      "scenarios": [
        "SC-SEL-003"
      ],
      "cp": "CP-SEL-003",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-SEL-004",
      "case_id": "main",
      "requirement": "REQ-SEL-001",
      "scenarios": [
        "SC-SEL-004"
      ],
      "cp": "CP-SEL-004",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-WSD-001",
      "case_id": "main",
      "requirement": "REQ-WSD-001",
      "scenarios": [
        "SC-WSD-001"
      ],
      "cp": "CP-WSD-001",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-WSD-002",
      "case_id": "main",
      "requirement": "REQ-WSD-001",
      "scenarios": [
        "SC-WSD-002"
      ],
      "cp": "CP-WSD-002",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-WSD-003",
      "case_id": "main",
      "requirement": "REQ-WSD-001",
      "scenarios": [
        "SC-WSD-003"
      ],
      "cp": "CP-WSD-003",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-WSD-004",
      "case_id": "main",
      "requirement": "REQ-WSD-001",
      "scenarios": [
        "SC-WSD-004"
      ],
      "cp": "CP-WSD-004",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-WSD-005",
      "case_id": "main",
      "requirement": "REQ-WSD-001",
      "scenarios": [
        "SC-WSD-005"
      ],
      "cp": "CP-WSD-005",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-CCF-001",
      "case_id": "main",
      "requirement": "REQ-CCF-001",
      "scenarios": [
        "SC-CCF-001"
      ],
      "cp": "CP-CCF-001",
      "kind": "command",
      "applicability": "required"
    },
    {
      "tc": "TC-CCF-002",
      "case_id": "main",
      "requirement": "REQ-CCF-001",
      "scenarios": [
        "SC-CCF-002"
      ],
      "cp": "CP-CCF-002",
      "kind": "command",
      "applicability": "required"
    }
  ]
}
```

Gate 2 前预检 / Preflight: `stdd agent verify <task> --change 2026-11-12-fork-ci-test-evidence-trust --dry-run`

## 七、已移交后续 change 的测试案例（不计入本 change）

2026-11-13 用户裁定执行范围收窄（B 路径，见 ADJ-046 / ADJ-047）：下列 3 个场景的验收对象在本机之外，无法在本 change 内诚实执行或确认，故移交后续 change。**本 change 不对它们作任何通过声明**；其原 TC 定义逐字保留在正文原位置的 HTML 注释中（机器不解析），并完整复制于 `validation/handoff/handoff-to-successor-change.md`。

| TC | Scenario | 移交原因 | 还缺什么 | 取回点 |
|---|---|---|---|---|
| TC-CBE-005 | SC-CBE-005 | 需真实 CI run | multica 提交+推送授权、管理员 PAT、仓库 secret | 移交包 §7.1 |
| TC-TOR-004 | SC-TOR-004 | 需 WSL AIFI-ISO root 隔离 | WSL 启动同意与隔离入口执行 | 移交包 §7.2 |
| TC-CCF-003 | SC-CCF-003 | 需管理员更新 PAT 后重跑 job | `AIFIRST_TOOLS_READ_TOKEN` 更新与真实 job 结论 | 移交包 §7.3 |

后继 change 的入口条件与复现命令见移交包 §3 / §5；**不得**用本 change 的 run id 或本地一次性库结果替代这 3 项的验收。
