# AIFI-45 一次性库实例生命周期与测试守卫边界 — 测试方案与详细案例

> 版本：1.0（standard 模式）
> 创建日期：2026-11-11
> 对应 Phase 2 Spec：`canonical/specs/code/disposable-test-instance.yaml`、`canonical/specs/code/test-wrapper-path-guard.yaml`（Human View 在 Gate 2 生成）

## 一、测试策略

### 1.1 测试金字塔

- **单元（多数）：** 实例信封、释放归属判定、`--admin-url` 拒绝、guard 与 `test-go.test.sh` 的 TMPDIR 行为。全部用假的 `podman` 调用或假命令，不依赖 podman、数据库、网络。
- **集成（少数，真实 podman）：** 一次完整生命周期（创建、真实 provision、释放、读回为零）和一次强杀后 TTL 自毁。显式运行 `instance.real.mjs`；文件名不含 `.test.`，默认通配不执行，需要本机已有 `docker.io/pgvector/pgvector:pg17`。
- **真实入口运行：** TC-DTI-007 的证据经入口运行 `selections.identity.json` 的两个单测试选择。另以完整 `selections.json` 的 13 个选择作 C2 回归，调用方需导出 `AIFI45_TOOLS_ROOT`，结果单独记录于 test-report，不属冻结证据。不另造 E2E 框架。

### 1.2 测试原则

- 每个 Scenario 至少一个 TC；每个 TC 在修复前能暴露问题（RED 先行）。guard 的 RED 用私有目录内以绝对路径调用的假命令加标记文件，`test-go.test.sh` 自身的拒绝只在修复后验证。
- 真实步骤不存在 skip 状态；必须显式运行真实测试文件并通过，未执行不能当作 PASS。
- 不碰任何非本次创建的容器、卷、库。真实测试只在运行前后比较容器与卷集合，并只删除按完整 ID 创建的实例。
- 不调用真实 Go、agent CLI。TMPDIR 的复现条件只在测试自建的私有临时目录内。

### 1.3 已有测试资产

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|---|---|---|---|
| `scripts/aifi45-disposable/provision.test.mjs` | 5（本次已复跑） | 单元 | 库级 nonce 库、角色、标记、drop 前回读。本 change 不改 |
| `scripts/aifi45-disposable/selection.test.mjs` | 已有 | 单元 | 选择清单与 NDJSON 对账。本 change 不改 |
| `server/cmd/server/integration_test.go` | 已有 | 集成 | `verifyDisposableTestDatabase` 与错 nonce 拒绝，C2 的口径参照 |
| `scripts/test-go.test.sh` | 已有（约 10 个 `test-go.sh` 场景） | 单元 | 参数与 guard 路由；新增 TMPDIR 用例 |

## 二、详细测试案例

### 功能 1：入口只使用自建实例（REQ-DTI-001）

#### 案例 1.1 — 创建参数的固定信封

| 字段 | 内容 |
|---|---|
| **ID** | TC-DTI-001 |
| **对应 Spec** | disposable-test-instance → SC-DTI-001 |
| **优先级** | P0 |
| **预置条件** | nonce 为 16 位十六进制，上限 T 秒。 |
| **输入** | `buildRunArgs({nonce, ttlSeconds})`；另外用 T=3601、0、-1、1.5 各调用一次。 |
| **预期结果** | 数组含 `--pull=never`、`--rm`、`--timeout=T`、`-p 127.0.0.1::5432`、`--tmpfs /var/lib/postgresql/data`、`--name aifi45-disposable-<nonce>`、`--label aifi45.disposable=<nonce>`、镜像 `docker.io/pgvector/pgvector:pg17`；不含 `-v`、`--volume`、`--mount`、`--privileged`、`--network host`、`--publish-all`，也不含密码；T 超过 3600 或非正整数时抛错。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 1.2 — `--admin-url` 被拒绝

| 字段 | 内容 |
|---|---|
| **ID** | TC-DTI-002 |
| **对应 Spec** | disposable-test-instance → SC-DTI-002 |
| **优先级** | P0 |
| **预置条件** | 一个合法的选择清单文件；两个子用例均以空 PATH 运行入口，环境变量子用例将 `AIFI45_ADMIN_URL` 设为无效地址。 |
| **输入** | 一个子用例传入 `--admin-url postgres://x`；另一个不传该参数而设置 `AIFI45_ADMIN_URL`。 |
| **预期结果** | `--admin-url` 在创建任何实例前被拒绝：退出码非零，stderr 含明确的 external admin 拒绝信息且不含 podman。环境变量不再被读取：入口继续尝试启动 podman，空 PATH 使 spawn ENOENT 出现在 stderr；退出码非零，stderr 不含外部连接拒绝信息但含 podman。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 2：释放核对归属（REQ-DTI-002）

#### 案例 2.1 — 归属匹配时按 ID 释放

| 字段 | 内容 |
|---|---|
| **ID** | TC-DTI-003 |
| **对应 Spec** | disposable-test-instance → SC-DTI-003 |
| **优先级** | P0 |
| **预置条件** | 假 `run`：按 ID 查询返回名称 `aifi45-disposable-N`、标签 `aifi45.disposable=N,other=x`；`rm` 之后两个读回都返回空。 |
| **输入** | `releaseInstance({id: ID, nonce: N})`。 |
| **预期结果** | 记录到的调用依次为：按 ID 查询、`rm -f -v <ID>`、按 ID 读回、按标签读回；返回 `remaining: 0`。另一个子用例：`rm` 后按标签读回仍有 ID，抛错。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 2.2 — 归属不匹配时不删除

| 字段 | 内容 |
|---|---|
| **ID** | TC-DTI-004 |
| **对应 Spec** | disposable-test-instance → SC-DTI-004 |
| **优先级** | P0 |
| **预置条件** | 假 `run` 分别返回：名称不同；标签不含该键；标签仅子串相同（如 `aifi45.disposable=N-x`）；按 ID 查不到。 |
| **输入** | `releaseInstance({id: ID, nonce: N})`。 |
| **预期结果** | 四种情形都抛错，且调用记录里没有任何 `rm`。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 3：生命周期上限（REQ-DTI-003）

#### 案例 3.1 — 强杀入口后实例自毁（真实 podman）

| 字段 | 内容 |
|---|---|
| **ID** | TC-DTI-005 |
| **对应 Spec** | disposable-test-instance → SC-DTI-005 |
| **优先级** | P0 |
| **预置条件** | 本机有镜像；以显式文件名运行 `instance.real.mjs`（不含 `.test.`，默认通配不执行）。记录运行前的容器与卷集合。 |
| **输入** | 子进程调用 `startInstance({ttlSeconds: 15})` 后打印容器 ID 并停住；父进程强杀该子进程（不释放），然后每秒按 ID 读回。 |
| **预期结果** | 在 15 秒加宽限（30 秒）内读回为零；结束后容器与卷集合等于运行前集合。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 4：入口释放实例（REQ-DTI-004）

#### 案例 4.1 — 一个通过、一个失败的选择后释放（真实 podman）

| 字段 | 内容 |
|---|---|
| **ID** | TC-DTI-006 |
| **对应 Spec** | disposable-test-instance → SC-DTI-006 |
| **优先级** | P0 |
| **预置条件** | 本机有镜像；以显式文件名运行 `instance.real.mjs`（不含 `.test.`，默认通配不执行）；测试临时目录里的选择清单含一个会通过的选择（真实 governance 测试）和一个匹配零测试的选择；记录运行前的容器与卷集合。 |
| **输入** | 子进程运行 `run-selection.mjs --selections <临时清单>`。 |
| **预期结果** | 退出码非零；输出含 `PASS <通过的选择>` 与 `FAIL <失败的选择>`；含释放证据行（容器 ID 前 12 位、remaining=0）；按标签与按 ID 读回为零；其他容器与卷集合与运行前相同。 |
| **当前状态** | ❌ 测试缺（待实现） |

### 功能 5：governance 核验一次性库身份（REQ-DTI-005）

#### 案例 5.1 — 错误 nonce 在写 fixture 前被拒绝

| 字段 | 内容 |
|---|---|
| **ID** | TC-DTI-007 |
| **对应 Spec** | disposable-test-instance → SC-DTI-007 |
| **优先级** | P0 |
| **预置条件** | 证据经入口运行 `selections.identity.json` 的两个各自只含一个测试的选择；governance TestMain 已用正确 nonce 通过，父测试读取 fixture workspace 的 `updated_at`。 |
| **输入** | `governance-nonce-gate` 的父测试以错误 nonce 重新执行测试二进制（`-test.run=^$`）；`governance-identity-check` 核验错误 nonce 与库标记不匹配时的拒绝。 |
| **预期结果** | 子进程 15 秒内非零退出，输出含 `governance integration test disposable identity mismatch`；父测试再读 `updated_at` 不变；身份核验拒绝错误 nonce 与不匹配的库标记。两个单测试选择均 PASS，零匹配即失败。13 个选择的完整入口运行是 C2 回归，调用方需导出 `AIFI45_TOOLS_ROOT`，结果单独记录于 test-report，不在冻结证据范围内。 |
| **当前状态** | ❌ 测试缺（待实现）；RED 通过临时把核验调用注释掉，确认该测试会失败后再恢复。 |

### 功能 6：测试包装脚本拒绝含 `:` 的 TMPDIR（REQ-TWG-001）

#### 案例 6.1 — guard 拒绝，假命令不被执行

| 字段 | 内容 |
|---|---|
| **ID** | TC-TWG-001 |
| **对应 Spec** | test-wrapper-path-guard → SC-TWG-001 |
| **优先级** | P0 |
| **预置条件** | 私有临时目录内创建含 `:` 的子目录作 TMPDIR；绝对路径假命令，执行时写标记文件。 |
| **输入** | `TMPDIR=<含冒号目录> bash go-test-with-agent-cli-guard.sh -- <假命令>`。 |
| **预期结果** | 退出码非零，stderr 含该原因，标记文件不存在。修复前同一用例：标记存在、退出码 0，用例失败（RED）。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 6.2 — `test-go.test.sh` 在 mktemp 前拒绝

| 字段 | 内容 |
|---|---|
| **ID** | TC-TWG-002 |
| **对应 Spec** | test-wrapper-path-guard → SC-TWG-002 |
| **优先级** | P1 |
| **预置条件** | `TMPDIR` 为不存在的含 `:` 路径。 |
| **输入** | 在 `test-go.test.sh` 内以该 TMPDIR 子进程重新运行 `bash "$0"`。 |
| **预期结果** | 子进程退出码为 2，stderr 含该原因。只在修复后验证；修复前 `mktemp` 会先因目录不存在失败，不会走到 PATH 改写。 |
| **当前状态** | ❌ 测试缺（待实现） |

#### 案例 6.3 — 空 TMPDIR 回退 `/tmp`

| 字段 | 内容 |
|---|---|
| **ID** | TC-TWG-003 |
| **对应 Spec** | test-wrapper-path-guard → SC-TWG-003 |
| **优先级** | P1 |
| **预置条件** | `TMPDIR` 为空；假命令写标记并以固定码（如 7）退出。 |
| **输入** | `TMPDIR= bash go-test-with-agent-cli-guard.sh -- <假命令>`。 |
| **预期结果** | 标记存在，退出码为 7；`test-go.test.sh` 既有用例仍全部通过。 |
| **当前状态** | ❌ 测试缺（待实现） |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试（真实 podman） | E2E（入口运行） | 状态 |
|---|---|---|---|---|
| 实例信封（REQ-DTI-001） | TC-DTI-001、TC-DTI-002 | 由 TC-DTI-006 间接覆盖 | — | 🔴 |
| 释放归属（REQ-DTI-002） | TC-DTI-003、TC-DTI-004 | TC-DTI-006 | — | 🔴 |
| 生命周期上限（REQ-DTI-003） | — | TC-DTI-005 | — | 🔴 |
| 入口释放（REQ-DTI-004） | — | TC-DTI-006 | 完整入口运行一次（C2 回归） | 🔴 |
| governance 身份（REQ-DTI-005） | — | — | TC-DTI-007（经入口） | 🔴 |
| TMPDIR 拒绝（REQ-TWG-001） | TC-TWG-001、TC-TWG-002、TC-TWG-003 | — | — | 🔴 |

## 四、回归风险矩阵

| 风险区域 | 改动 | 已有回归保护 | 风险等级 |
|---|---|---|---|
| `run-selection.mjs` 的既有逐选择流程 | 取得 `adminUrl` 的方式改变；前后包 `startInstance`/`releaseInstance` | 完整 `selections.json` 一次真实运行（AIFI-45 11 选择、M005 12 选择，加新增 1 个） | 🟡 |
| governance TestMain | 新增身份核验 | 同上；`execution_control_migration_test.go` 已有的检查 | 🟡 |
| `provision.mjs` / `selection.mjs` | 不改 | `provision.test.mjs`（5）、`selection.test.mjs` | 🟢 |
| guard 与 `test-go.sh` 的正常路径 | mktemp 前加一个 case 判断 | `test-go.test.sh` 既有场景；TC-TWG-003 | 🟢 |
| 本机其他容器（`multica-postgres`、`multica-backend`） | 无意触碰 | 真实测试前后集合比较；释放只按完整 ID 且核对归属 | 🟡 |
| fork CI | 不改，governance 在无 nonce 环境会更早失败 | 已登记，另立 change | 🟢 |

## 五、建议补充顺序

1. **第一优先**（实现前必补，RED 先行）：TC-DTI-001、TC-DTI-003、TC-DTI-004、TC-TWG-001、TC-DTI-007。
2. **第二优先**（实现后立刻做真实验证）：TC-DTI-005（强杀 TTL，先于其他真实步骤验证方案可行）、TC-DTI-006、TC-DTI-002。
3. **第三优先**（同批完成）：TC-TWG-002、TC-TWG-003。

## 六、同次执行证据计划

证据 run 不依赖 tools 仓库；执行前须启动 Podman 虚拟机并保证执行期间独占，比较容器与卷集合期间不得有其他容器或卷被创建或删除。调用方生成 run id，将同一值传给 `stdd agent verify disposable-test-instance --change <change> --run <id>` 和 `stdd ci check-failures <change> --run <id>`，两者之间不得再跑其他 `agent verify`。Node 测试命令使用 TAP reporter，使成功输出为 ASCII；失败输出中的非 ASCII 字节若无法按执行器的系统 locale 解码（中文 Windows 为 cp936），执行器会崩溃，这是响亮失败，不会变成通过。`inputs` 不含 change 目录或其产物。项目输入的冻结范围为 TC 的被测对象及入口在测试前直接执行的数据与命令（含迁移入口与 SQL）；不含 Go 编译期传递依赖，也不含属环境的 Podman 与镜像。被测对象为 Node 脚本、shell 脚本与 Go 测试，覆盖率采集目前只支持 pytest-cov，项目配置 `quality.coverage.enabled=false`，因此覆盖率不适用。

```stdd-evidence-plan-v1
{
  "task": "disposable-test-instance",
  "tasks": ["disposable-test-instance", "test-wrapper-path-guard"],
  "inputs": [
    {"root": "project", "path": "scripts/aifi45-disposable"},
    {"root": "project", "path": "scripts/go-test-with-agent-cli-guard.sh"},
    {"root": "project", "path": "scripts/test-go.test.sh"},
    {"root": "project", "path": "scripts/test-go.sh"},
    {"root": "project", "path": "scripts/agent-cli-command-names.txt"},
    {"root": "project", "path": "server/internal/governance"},
    {"root": "project", "path": "server/cmd/migrate"},
    {"root": "project", "path": "server/internal/migrations"},
    {"root": "project", "path": "server/migrations"}
  ],
  "coverage": {"applicability": "not_applicable", "reason": "被测对象为 Node 脚本、shell 脚本与 Go 测试，覆盖率采集目前只支持 pytest-cov；项目配置 quality.coverage.enabled=false"},
  "checks": [
    {"tc": "TC-DTI-001", "cp": "CP-DTI-001", "requirement": "REQ-DTI-001", "scenarios": ["SC-DTI-001"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-DTI-002", "cp": "CP-DTI-002", "requirement": "REQ-DTI-001", "scenarios": ["SC-DTI-002"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-DTI-003", "cp": "CP-DTI-003", "requirement": "REQ-DTI-002", "scenarios": ["SC-DTI-003"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-DTI-004", "cp": "CP-DTI-004", "requirement": "REQ-DTI-002", "scenarios": ["SC-DTI-004"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-DTI-005", "cp": "CP-DTI-005", "requirement": "REQ-DTI-003", "scenarios": ["SC-DTI-005"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-DTI-006", "cp": "CP-DTI-006", "requirement": "REQ-DTI-004", "scenarios": ["SC-DTI-006"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-DTI-007", "cp": "CP-DTI-007", "requirement": "REQ-DTI-005", "scenarios": ["SC-DTI-007"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-TWG-001", "cp": "CP-TWG-001", "requirement": "REQ-TWG-001", "scenarios": ["SC-TWG-001"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-TWG-002", "cp": "CP-TWG-002", "requirement": "REQ-TWG-001", "scenarios": ["SC-TWG-002"], "case_id": "main", "kind": "command", "applicability": "required"},
    {"tc": "TC-TWG-003", "cp": "CP-TWG-003", "requirement": "REQ-TWG-001", "scenarios": ["SC-TWG-003"], "case_id": "main", "kind": "command", "applicability": "required"}
  ]
}
```
