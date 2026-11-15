# multica backend-tests 在 CI 变绿 测试方案与详细案例

> 版本：2026-11-15-multica-backend-tests-green
> 创建日期：2026-11-15
> 对应 Phase 2 Spec：`canonical/specs/code/` 下 `ci-admin-test-ownership.yaml`、`governance-runner-run-lock.yaml`、`backend-tests-ownership.yaml`

## 一、测试策略

### 1.1 测试金字塔

- 单元：管理员流对账的 6 个 node 用例（TC-CAO-001）。
- 集成（真实 PostgreSQL，受限一次性角色）：`run-selection.mjs --only` 的 5 个 selection（TC-RRL-001/002、TC-BTO-001/003，外加 TC-BTO-002 的归属表检查是纯 node）。它们是本 change 的主证据，因为缺陷只在「受限角色、小池、并行共享库」下出现。
- 人工 / 真实 CI：管理员步骤的接线（TC-CAO-002）、等锁点替换评审（TC-RRL-003）、claim 用例定性（TC-BTO-004）、真实 CI 结果（TC-BTO-005）、`CUSTOM.md` 登记（TC-BTO-006）。

### 1.2 测试原则

- 每个检查只对应一条保证；不为同一缺陷在多个层重复检查。
- 先 RED 再 GREEN：每个检查在改前必须是已知失败（或因被测对象不存在而失败），改后通过。TC-RRL-001 的改前失败样本已有实测（池 4 挂起，2026-11-15）；TC-BTO-001 改前已实测在受限角色下失败；TC-CAO-001 的坏样本本身就是红样本。
- 对账逻辑先用已知好样本和已知坏样本自测，再接入 CI。
- 断言须含能区分对错的观测值（具体计数、被拒绝的具体测试名），不得只匹配 PASS 标签；selection 检查同时断言 `skip=0`。 / Assertions must carry observable values that distinguish right from wrong.
- selection 检查由 `run-selection.mjs` 自建并按 nonce 释放一次性实例，不连接共享库、不使用管理员 DSN。
- 人工检查如实标注为人工；依赖真实 CI 的结论只由真实 CI 给出，不声称本地已证明。

### 1.3 已有测试资产

| 测试文件 | 用例数 | 类型 | 覆盖范围 |
|----------|--------|------|----------|
| `scripts/aifi45-disposable/ci-evidence.test.mjs` | 既有若干 | 单元 | 共享流对账的 4 条规则；本 change 在同文件追加管理员流用例 |
| `server/internal/governance/runner_periodic_resume_test.go::TestMTick003` | 1 | 集成 | 并发唤醒下只派发 1 个任务；原样保留，池上限改为 4 |
| `server/internal/governance/*_test.go::TestExecutionMigrationDownRoundTrip` | 1 | 集成 | down 脚本往返；仅改归属，不改用例 |
| `server/cmd/migrate/migrate_issue_properties_bigm_index_test.go` | 1 | 集成 | bigm 索引；改读 `pg_stats` |
| `scripts/aifi45-disposable/test-ownership.test.mjs` | 既有 | 单元 | 归属表结构校验；本 change 不改其用例 |

## 二、详细测试案例

### 功能 1：管理员流对账（ci-admin-test-ownership）

#### 案例 1.1 — 好样本通过、五类坏样本失败

| 字段 | 内容 |
|------|------|
| **ID** | TC-CAO-001 |
| **对应 Spec** | ci-admin-test-ownership → REQ-CAO-001、SC-CAO-001 |
| **优先级** | P0 |
| **预置条件** | 无外部依赖；`reconcileAdminStream` 纯函数 |
| **输入** | 6 个用例（标题均含 `TCCAO001`）：好样本（三个 ci-admin 测试各一条顶层 pass、包级 pass、以换行结尾）；坏样本 5 类：其中一个 skip、其中一个缺失、其中一个 fail、流不以换行结尾、同一测试两条顶层 pass |
| **预期结果** | 好样本 `ok: true` 且 problems 为空；每个坏样本 `ok: false`，problems 点名具体的包与测试名（流不完整时指出流不完整）；`node --test` 输出 `pass 6 fail 0` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED：`reconcileAdminStream` 不存在） |

#### 案例 1.2 — 管理员步骤在可建库的 PG 上跑通并通过对账

| 字段 | 内容 |
|------|------|
| **ID** | TC-CAO-002 |
| **对应 Spec** | ci-admin-test-ownership → REQ-CAO-002、SC-CAO-002 |
| **优先级** | P0 |
| **预置条件** | 本地 podman 管理员 PG（`pgvector/pgvector:pg17`，可建库）；`DATABASE_URL` 指向它 |
| **输入** | ci.yml 新步骤里的 `go test -json -run '^(三个名字)$' ./cmd/backfill_codex_usage_cache ./internal/taskusagebackfill > <流文件>`，再运行管理员流对账 |
| **预期结果** | 3 个测试各一条 pass，对账通过，进程退出码 0；真实 CI 该步骤与对账均为绿（TC-BTO-005 一并登记）。人工检查：需要真实服务容器，本地结果不替代 CI |
| **当前状态** | ❌ 测试缺（人工，BUILD 后执行） |

### 功能 2：运行锁（governance-runner-run-lock）

#### 案例 2.1 — 池上限 4 下并发唤醒不挂起

| 字段 | 内容 |
|------|------|
| **ID** | TC-RRL-001 |
| **对应 Spec** | governance-runner-run-lock → REQ-RRL-001、SC-RRL-001 |
| **优先级** | P0 |
| **预置条件** | 一次性迁移库；`TestMain` 的池上限为 4；selection `governance-mtick003` |
| **输入** | `run-selection.mjs --only governance-mtick003` |
| **预期结果** | 退出码 0；输出含 `PASS governance-mtick003 ` 与 `skip=0`。改前同条件（池 4）挂起超时是现成红样本（2026-11-15 实测，7 个 goroutine 卡在 `Acquire`） |
| **当前状态** | ❌ 测试缺（selection 缺；BUILD 先加池 4 与 selection 做 RED，再改 `withRunLock`） |

#### 案例 2.2 — `withRunLock` 的互斥、释放、取消

| 字段 | 内容 |
|------|------|
| **ID** | TC-RRL-002 |
| **对应 Spec** | governance-runner-run-lock → REQ-RRL-002、SC-RRL-002 |
| **优先级** | P0 |
| **预置条件** | 一次性迁移库；selection `governance-run-lock` |
| **输入** | 两个 Go 用例：`TestWithRunLockSerialisesSameRun`（两个 goroutine 同 run id，`fn` 内计数器检测并发进入，随后第三次调用无需等待）；`TestWithRunLockCancelReleasesWaiter`（持锁 `fn` 未返回，另一调用等锁后取消 → 返回 `ctx.Err()`，池中已获取连接数不超过 1；持锁者返回后下一次调用立即获锁） |
| **预期结果** | 退出码 0，两个用例各一条 pass，`skip=0` |
| **当前状态** | ❌ 测试缺（BUILD 先写 RED：`withRunLock` 不存在） |

#### 案例 2.3 — 三处等锁点替换

| 字段 | 内容 |
|------|------|
| **ID** | TC-RRL-003 |
| **对应 Spec** | governance-runner-run-lock → REQ-RRL-003、SC-RRL-003 |
| **优先级** | P1 |
| **预置条件** | 改后的 4 个 Go 文件 |
| **输入** | 人工评审 diff，并全文搜索 `pg_advisory_lock(` |
| **预期结果** | `runner.go`、`runner_code.go`、`runner_requirement.go` 不再含阻塞式 `pg_advisory_lock(`，三处都调用 `withRunLock`；`runner_requirement_entry.go` 无改动。人工检查，搜索输出写入 test-report |
| **当前状态** | ❌ 测试缺（人工，BUILD 后执行） |

### 功能 3：测试归属与 claim 定性（backend-tests-ownership）

#### 案例 3.1 — bigm 用例在受限角色通过

| 字段 | 内容 |
|------|------|
| **ID** | TC-BTO-001 |
| **对应 Spec** | backend-tests-ownership → REQ-BTO-001、SC-BTO-001 |
| **优先级** | P0 |
| **预置条件** | selection `bigm-restricted-role`（受限一次性角色，已迁移） |
| **输入** | `run-selection.mjs --only bigm-restricted-role` |
| **预期结果** | 退出码 0；输出含 `PASS bigm-restricted-role ` 与 `skip=0`。改前同条件失败（`pg_statistic` 权限，2026-11-15 实测）是现成红样本 |
| **当前状态** | ❌ 测试缺（selection 缺；BUILD 先加 selection 做 RED，再改 `pg_stats`） |

#### 案例 3.2 — 归属表登记 4 个测试并被排除

| 字段 | 内容 |
|------|------|
| **ID** | TC-BTO-002 |
| **对应 Spec** | backend-tests-ownership → REQ-BTO-002、SC-BTO-002 |
| **优先级** | P0 |
| **预置条件** | 改后的 `test-ownership.json` |
| **输入** | `test-ownership.mjs check` 与 `test-ownership.mjs skip-regex` |
| **预期结果** | `check` 退出 0，输出 `test ownership OK: 8 entry(ies)`（原 4 + 新 4）；skip 正则含 `TestExecuteBackfillUpdatesOnlyEligibleCodexRowsAndRebuildsRollup`、`TestHook_DirectV034Upgrade`、`TestHook_FreshDatabaseStampsWatermarkOnly`、`TestExecutionMigrationDownRoundTrip`；原 4 个 independent 条目与 allowed-skips 仍在 |
| **当前状态** | ❌ 测试缺（改前条目数为 4，断言 8 因此为 RED） |

#### 案例 3.3 — `DownRoundTrip` 经 selection 单独通过

| 字段 | 内容 |
|------|------|
| **ID** | TC-BTO-003 |
| **对应 Spec** | backend-tests-ownership → REQ-BTO-002、SC-BTO-003 |
| **优先级** | P0 |
| **预置条件** | 既有 selection `governance-migration-roundtrip` |
| **输入** | `run-selection.mjs --only governance-migration-roundtrip` |
| **预期结果** | 退出码 0；输出含 `PASS governance-migration-roundtrip ` 与 `skip=0`。注意：该用例改为 independent 后 CI 不再运行它，证据只来自本检查，test-report 须如实写明 |
| **当前状态** | ⚠️ 部分覆盖（selection 已存在，改前即可通过；登记由 TC-BTO-002 保证） |

#### 案例 3.4 — claim deadline 用例定性

| 字段 | 内容 |
|------|------|
| **ID** | TC-BTO-004 |
| **对应 Spec** | backend-tests-ownership → REQ-BTO-003、SC-BTO-004 |
| **优先级** | P1 |
| **预置条件** | C1–C4 已落地；`--cpus=2` 的 Go 容器、一次性库；优先 `-race` |
| **输入** | 对 `TestClaimTasksByRuntime_PartialSuccessFitsClientDeadlines` 重复运行至少 20 次 |
| **预期结果** | `design-adjustments.md` 记录次数、失败次数、失败错误全文、是否带 `-race`，并写出结论（复现并修复，或无法复现及依据）。人工检查，由 balanced 子代理执行、主会话验收 |
| **当前状态** | ❌ 测试缺（人工，BUILD 后执行） |

#### 案例 3.5 — 真实 CI

| 字段 | 内容 |
|------|------|
| **ID** | TC-BTO-005 |
| **对应 Spec** | backend-tests-ownership → REQ-BTO-004、SC-BTO-005 |
| **优先级** | P0 |
| **预置条件** | 本 change 的提交已推送（另行取得用户授权）；CI 对该提交跑完 backend-tests |
| **输入** | 对比该 run 的失败集合与 run 43687569973 的 8 例 |
| **预期结果** | 原 7 例（4 个权限、`DownRoundTrip`、`TestMTick003` 超时、`DeleteWorkspace`）不再出现；claim 用例按 TC-BTO-004 结论处理；run id 记入 test-report。管理员步骤及其对账（TC-CAO-002）在该 run 里为绿。人工检查，只由真实 CI 给出 |
| **当前状态** | ⏭️ N/A（2026-11-15 用户同意）：GitHub Actions 账单/额度阻塞，run 43727687773 未启动；替代证据见 test-report §8（第一轮真实 CI run 43725057558 + 本地 CI-equivalent） |

#### 案例 3.6 — `CUSTOM.md` 登记

| 字段 | 内容 |
|------|------|
| **ID** | TC-BTO-006 |
| **对应 Spec** | backend-tests-ownership → REQ-BTO-004、SC-BTO-006 |
| **优先级** | P1 |
| **预置条件** | 改后的 `CUSTOM.md` |
| **输入** | 人工检查登记行与换行（逐字节统计 `\r\n` 与裸 `\n`） |
| **预期结果** | 登记行列出本 change 触达的 multica 定制；文件 CRLF，无裸 LF |
| **当前状态** | ❌ 测试缺（人工，BUILD 后执行） |

## 三、测试执行矩阵

| 功能模块 | 单元测试 | 集成测试 | E2E / 真实 CI | 状态 |
|----------|---------|----------|---------------|------|
| 管理员流对账 | TC-CAO-001 | TC-CAO-002（人工） | TC-BTO-005 | 🔴 待 BUILD |
| 运行锁 | — | TC-RRL-001、TC-RRL-002 | TC-BTO-005 | 🔴 待 BUILD |
| 测试归属与 claim | TC-BTO-002 | TC-BTO-001、TC-BTO-003 | TC-BTO-004、TC-BTO-005 | 🔴 待 BUILD |

## 四、回归风险矩阵

| 风险区域 | 本次改动 | 已有回归保护 | 风险等级 |
|---------|---------|-------------|---------|
| Runner 并发唤醒、锁语义 | `withRunLock` 取代三处阻塞式 `pg_advisory_lock` | `TestMTick003` @池 4、`TestWithRunLock*`、governance 全包 @池 4 | 🔴 |
| CI 对账漏判 SKIP | 新增管理员流对账 | TC-CAO-001 的 5 类坏样本；共享流既有 4 条规则 | 🟡 |
| 池固定为 4 暴露其他测试 | `TestMain` 池 4 | BUILD 阶段 governance 全包 @4 跑一遍并逐个定性 | 🟡 |
| `DownRoundTrip` 退出共享 run | 登记 independent | TC-BTO-003 | 🟡 |

## 五、建议补充顺序

1. **第一优先**：TC-BTO-001、TC-CAO-001、TC-BTO-002（各自独立，最便宜）。
2. **第二优先**：TC-RRL-001、TC-RRL-002（生产路径，先 RED 再改）。
3. **第三优先**：TC-CAO-002、TC-RRL-003、TC-BTO-006；之后 TC-BTO-004（子代理）；最后 TC-BTO-005（推送后）。

## 六、同次执行证据计划

```stdd-evidence-plan-v1
{
  "task": "backend-tests-ownership",
  "tasks": [
    "backend-tests-ownership",
    "ci-admin-test-ownership",
    "governance-runner-run-lock"
  ],
  "inputs": [
    {"root": "project", "path": "scripts/aifi45-disposable"},
    {"root": "project", "path": ".github/workflows/ci.yml"},
    {"root": "project", "path": "server/internal/governance"},
    {"root": "project", "path": "server/cmd/migrate"},
    {"root": "project", "path": "server/cmd/backfill_codex_usage_cache"},
    {"root": "project", "path": "server/internal/taskusagebackfill"},
    {"root": "project", "path": "CUSTOM.md"}
  ],
  "coverage": {
    "applicability": "not_applicable",
    "reason": "被测对象为 Go、Node 与 CI 配置，覆盖率采集目前只支持 pytest-cov；项目配置 quality.coverage.enabled=false"
  },
  "checks": [
    {"tc": "TC-CAO-001", "case_id": "admin-stream-good-and-bad", "requirement": "REQ-CAO-001",
     "scenarios": ["SC-CAO-001"], "cp": "CP-CAO-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-CAO-002", "case_id": "admin-step-on-admin-pg", "requirement": "REQ-CAO-002",
     "scenarios": ["SC-CAO-002"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-RRL-001", "case_id": "mtick003-pool4", "requirement": "REQ-RRL-001",
     "scenarios": ["SC-RRL-001"], "cp": "CP-RRL-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-RRL-002", "case_id": "withrunlock-mutex-release-cancel", "requirement": "REQ-RRL-002",
     "scenarios": ["SC-RRL-002"], "cp": "CP-RRL-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-RRL-003", "case_id": "lock-sites-replaced", "requirement": "REQ-RRL-003",
     "scenarios": ["SC-RRL-003"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-BTO-001", "case_id": "bigm-restricted-role", "requirement": "REQ-BTO-001",
     "scenarios": ["SC-BTO-001"], "cp": "CP-BTO-001", "kind": "command", "applicability": "required"},
    {"tc": "TC-BTO-002", "case_id": "ownership-table-check", "requirement": "REQ-BTO-002",
     "scenarios": ["SC-BTO-002"], "cp": "CP-BTO-002", "kind": "command", "applicability": "required"},
    {"tc": "TC-BTO-003", "case_id": "roundtrip-selection", "requirement": "REQ-BTO-002",
     "scenarios": ["SC-BTO-003"], "cp": "CP-BTO-003", "kind": "command", "applicability": "required"},
    {"tc": "TC-BTO-004", "case_id": "claim-deadline-characterisation", "requirement": "REQ-BTO-003",
     "scenarios": ["SC-BTO-004"], "kind": "manual", "applicability": "required"},
    {"tc": "TC-BTO-005", "case_id": "real-ci", "requirement": "REQ-BTO-004",
     "scenarios": ["SC-BTO-005"], "kind": "manual", "applicability": "not_applicable",
     "reason": "GitHub Actions 账单/额度阻塞（2026-11-15，run 43727687773 未启动）；替代证据：第一轮真实 CI run 43725057558 除已修复的 reservation 用例外全绿，本地 CI-equivalent 中四个关键用例与两种对账通过。用户 2026-11-15 同意以此收口。"},
    {"tc": "TC-BTO-006", "case_id": "custom-ledger", "requirement": "REQ-BTO-004",
     "scenarios": ["SC-BTO-006"], "kind": "manual", "applicability": "required"}
  ]
}
```
