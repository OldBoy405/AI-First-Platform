# Slice 8 验证记录 — workspace 删除清单的 19 张执行控制表分类

- change：`2026-11-12-fork-ci-test-evidence-trust`
- 切片：8（P0，依赖 #4）
- 覆盖：TC-WSD-001 / SC-WSD-001 / **CP-WSD-001**（canonical `specs/agent/workspace-delete-execution-tables.yaml`）
- 日期：2026-11-12
- 结论：**本切片验证通过**。CP-WSD-001 的两条断言（`exit_code 0`、`stdout_contains 'PASS handler-wsd-manifest '`）均由 runner 自建的一次性 podman 实例真跑满足；4/4 变异 DETECTED；整包回归无本切片可归因的回归。
- 边界：`retain` 只是**清单分类**，删除实现属 S9。本切片未写任何 DELETE 业务代码、未新增迁移、未给 append-only 触发器开删除例外、未改 sqlc。

---

## 1. 产出物

| 文件 | 性质 | 说明 |
|---|---|---|
| `server/internal/handler/workspace_delete_manifest_test.go` | **上游文件**（MUL-5562，CUSTOM.md #87） | 只追加两处并标 `// AIFIRST:`：第 5 种归属常量 `workspaceDeleteRetain`；表尾 19 条 `cr_execution_*` 登记。**既有测试体一行未改** |
| `server/internal/handler/workspace_delete_retention_test.go` | **fork 独有**（新，`// AIFIRST:` 英文头） | 分类与 catalog 对账：触发器 + 指向 workspace 的外键 |
| `scripts/aifi45-disposable/selections.json` | fork 目录（M30 已登记） | 追加 `handler-wsd-manifest` |
| `CUSTOM.md` | 台账 | #87 补登（严格追加）+ 新行 #324；M31 → 8 行 #317–#324 |

 sha256（本切片结束时）：

- manifest `e71ecfb152ba71081523946e153489ff4f9bc4e2374d4de28ffb87d7e8e28a99`
- retention `f477838debfe3a4eb4a03278232c12d799a26c50a2b732cdd91135208d0267b1`

### 1.1 上游 diff 口径（如实说明，不是纯字节追加）

```
git diff --numstat    → 38 插入 / 10 删除
git diff -w --numstat → 28 插入 /  0 删除
```

那 10 行「删除」全部是 **gofmt 对齐空格重排**：新键 `cr_execution_policy_activation_event` 比既有键长，gofmt 把 #87 登记的那 10 张 fork 表（`approval_record`、`chat_idempotency`、`cr`、`cr_sync_event`、`drift_finding`、`maturity_snapshot`、`pipeline_node_run`、`pipeline_run`、`project_chat_session`、`project_presenter_grant`）的值列重新对齐。忽略空白后**零删除行**，动作值仍为 `workspaceDelete`。语义上是纯追加，字节上不是——两者都记下来，不含糊成「只追加」。

`gofmt -l` 无输出；`go vet ./internal/handler` exit 0。

---

## 2. 前置事实核实（tasks 8.1）

逐张读迁移 `643`–`648`（静态）+ 由新测试在真库上对账（运行时）：

- **19 张** `cr_execution_*` 表。
- **7 张**声明 `workspace_id`：`binding_issue`、`consumption`、`activation`、`notice`、`dispatch_root`、`contract_selection`、`code_source_freeze`；其余 **12 张没有**。
- **没有任何一张 `REFERENCES workspace`**。648 头部明确写了继承 643–647 的约定：*no FK or cascade (relationships are verified by the application on every use)*。→ 删 workspace 行**不会**级联清空这些表，`delete` 类必须显式 DELETE。
- **16 张**带拒绝 DELETE 的触发器；`notice`、`dispatch_root`、`tool_cursor` **没有**。

### 2.1 决策 7 的逐表分类（2 delete / 11 retain / 6 keep）

| 表 | 动作 | workspace_id | BEFORE DELETE 行触发器 | 依据 |
|---|---|---|---|---|
| `cr_execution_notice` | delete | 有 | 无 | 运营态通知，随 workspace 清除；无触发器无外键，须显式 DELETE |
| `cr_execution_dispatch_root` | delete | 有 | 无 | 运营态派发根，同上 |
| `cr_execution_activation` | retain | 有 | 有 | 审计证据，触发器继续拒绝 DELETE |
| `cr_execution_binding_issue` | retain | 有 | 有 | 同上 |
| `cr_execution_code_source_freeze` | retain | 有 | 有 | 同上 |
| `cr_execution_consumption` | retain | 有 | 有 | 同上 |
| `cr_execution_contract_selection` | retain | 有 | 有 | 选定合同，不可降级/不可删 |
| `cr_execution_control_command` | retain | 无 | 有 | 648 头部：command 行**不得为已删 workspace 重建**，走收敛而非丢弃；本切片不实现收敛转换 |
| `cr_execution_control_fact` | retain | 无 | 有 | 审计事实 |
| `cr_execution_control_reservation` | retain | 无 | 有 | 审计预留 |
| `cr_execution_control_settlement` | retain | 无 | 有 | 结算证据 |
| `cr_execution_task_binding` | retain | 无 | 有 | 绑定证据 |
| `cr_execution_tool_verdict` | retain | 无 | 有 | T 判定证据 |
| `cr_execution_deployment_head` | keep | 无 | 有 | 全局部署 head，非 workspace 作用域 |
| `cr_execution_deployment_snapshot` | keep | 无 | 有 | 全局部署快照 |
| `cr_execution_policy_activation_event` | keep | 无 | 有 | 全局策略事件 |
| `cr_execution_policy_activation_head` | keep | 无 | 有 | 全局策略 head |
| `cr_execution_policy_readiness` | keep | 无 | 有 | 全局就绪请求 |
| `cr_execution_tool_cursor` | keep | 无 | 无 | 全局工具游标 |

`keep` 的既有规则（不带 `workspace_id`）与 `retain` 不冲突：11 张 `retain` 里 **5 张**带 `workspace_id`（`activation`、`binding_issue`、`code_source_freeze`、`consumption`、`contract_selection`；另 2 张带 `workspace_id` 的是 `delete` 类的 `notice`、`dispatch_root`）。既有测试体只对 KEEP / DETACH / SETTLE 三类断言 `workspace_id` 的有无，未对 retain 施加该规则，故 GREEN 成立。**既有断言未改弱**。

上表的 `workspace_id` 与外键两列已用脚本逐张从 `CREATE TABLE … );` 区块复核：7 张有 `workspace_id`、12 张没有、**19 张全部 `REFERENCES workspace` 计数为 0**。触发器列由新测试在真库上按 `pg_trigger.tgtype` 位判定（GREEN 即其证据）。

---

## 3. RED / GREEN（CP-WSD-001）

selection 名 **`handler-wsd-manifest`** 取自锁定的 canonical CP-WSD-001。design 决策 8 写的是 `handler-workspace-deletion`，与 canonical 冲突 → **canonical 优先**，已记 ADJ-012，并据此确定 S9/S10 必须用 `handler-wsd-delete` / `-retain` / `-atomic` / `-no-recreate`。

 RED 用**真实改前状态**取证：保留 `retain` 常量、移除 19 条登记（因此是**断言级**红灯，不是编译级）。

```
RED  exit=1  FAIL handler-wsd-manifest pass=0 fail=2 skip=0
  workspace_delete_manifest_test.go:211: unclassified=[19 张全部点名] missing=[]
  workspace_delete_retention_test.go:158: cr_execution_activation is classified "" in the manifest, decision 7 says "retain"
  ...（逐表）
  released instance 4d25e39238f4 remaining=0
  manifest restored=true sha256=e71ecfb1…

GREEN exit=0 PASS handler-wsd-manifest pass=2 fail=0 skip=0
  released instance 292534b3ebff remaining=0
```

两条断言逐条核对：`exit_code 0` ✓；stdout 含 `PASS handler-wsd-manifest ` ✓。**skip=0**，无静默跳过。

证据：`red/handler-wsd-manifest.{json,ndjson}`、`green/handler-wsd-manifest.{json,ndjson}`、`red-green-run.txt`。

---

## 4. 变异验证 4/4 DETECTED

在**同一个自建一次性实例**（`fb10525d9426`，库 `aifi45_tmp_394e2d7c8fd202bd`）上逐条中和，每条要求真跑变红：

| # | 中和方式 | 结果 | 红灯报文 |
|---|---|---|---|
| 1 | 删一条 manifest 登记（`cr_execution_notice`） | **DETECTED** exit=1 | `unclassified=[cr_execution_notice]` |
| 2 | 把一条 `retain` 回退成 `keep`（`binding_issue`） | **DETECTED** exit=1 | `is classified "keep" … decision 7 says "retain"` |
| 3 | **真库**删掉 retain 表的 BEFORE DELETE 触发器 | **DETECTED** exit=1 | `retained table cr_execution_binding_issue has no BEFORE DELETE row trigger; its rows are no longer protected` |
| 4 | **真库**加一个指向 workspace 的外键（`ADD CONSTRAINT … NOT VALID`） | **DETECTED** exit=1 | `references workspace via [aifi45_probe_workspace_fk]; deleting the workspace would cascade into it` |

- baseline exit=0 fail=0；**还原后** exit=0 fail=0。
- 触发器用 `pg_get_triggerdef(oid)` **逐字节还原**，`trigger restored=true`；探针外键 `probe constraint removed=true`。
- manifest sha256 前后一致 `e71ecfb1…`（两条文本变异均按原字节还原）。
- 3、4 是**真实 schema 退化**，不是只改测试期望——证明 catalog 断言有牙。

证据：`mutation-manifest-and-catalog.txt`、`mutations/{manifest-entry-removed,classification-reverted,retain-trigger-dropped,retain-fk-added}.ndjson`。

---

## 5. 回归

### 5.1 node 目录全量

`node --test "scripts/aifi45-disposable/*.test.mjs"` → **154 PASS / 0 fail / 0 skip**（与 S6/S7 一致，本切片未改 node 代码）。
证据：`regression-directory.tap`。（Windows Node 24 必须用 glob 形式，目录形式会 `MODULE_NOT_FOUND`。）

### 5.2 handler 整包（一次性实例真跑）

`--only baseline-handler`，注入 `CRCTL_MJS` / `AIFI45_TOOLS_ROOT`（与 S4 基线同条件）：

| | pass | fail | skip |
|---|---|---|---|
| S4 基线 | 4507 | 3 | 47 |
| S8 回归 | 4506 | 5 | 47 |

**按测试名逐条对账**（`regression-handler-failing-diff.txt`）：

- 基线失败集合：`TestPresenterMemberRemovalLinkage`、`TestSearchIndexChangesScopeToWorkspace`、`TestWorkspaceDeletionManifestCoversPublicSchema`
- S8 失败集合：`TestPresenterIllegalTransitions`（+ 2 个子测试）、`TestPresenterTransferFlow`、`TestSearchIndexChangesScopeToWorkspace`

定性：

1. **本切片修好了** `TestWorkspaceDeletionManifestCoversPublicSchema`（基线红 → 现绿），这正是 S8 的目标。
2. `TestSearchIndexChangesScopeToWorkspace` **同名同因**，基线就红，属 S4 归属表已定性的范围外项，本切片未触碰。
3. presenter 家族失败数变化 = **既有 Windows 时钟粒度 flake**，见 5.3。
4. skip 集合数量不变（47）。

pass 4507→4506 的算术核对：manifest 由红转绿 +1、`MemberRemovalLinkage` 本次侥幸通过 +1、presenter 新增 3 个受害测试 −3 → 净 −1。**不是丢了覆盖**。

### 5.3 presenter flake 的逐测试 A/B（不笼统归因上游）

`createPresenterTestMember`（`project_presenter_test.go:18`）用 `time.Now().UnixNano()` 拼 email：
`presenter-<role>-<UnixNano>@multica.ai`。Windows 时钟粒度粗，同一 tick 内两次调用产生**相同 email** → `user_email_key` 23505。

**A/B 设计**：用 `-run '^TestPresenter'` 单独跑，**本切片新增的测试不在该 run 内**，因此若仍失败即与本切片无关。在一次性库上**连跑两次**：

| | pass | fail | skip | 受害测试 |
|---|---|---|---|---|
| run1 | 11 | 3 | 0 | `IllegalTransitions/approve_while_a_presenter_is_already_active`（:395）+ `MemberRemovalLinkage`（:450） |
| run2 | 11 | 3 | 0 | `IllegalTransitions/non-presenter_cannot_transfer`（:317）+ `MemberRemovalLinkage`（:451） |

三次观察（S4 基线、S8 整包、两次单独跑）报文**完全同型**，且**受害子测试在两次之间移动** → 非确定性、与本切片改动无因果关系。S4 基线自身就带同一报文（`MemberRemovalLinkage:450`），S4 当时已定性为「Windows 时钟粒度，非常量 id 缺陷」。

**处置：属范围外，未擅自修改上游测试**。**ADJ-006 已登记同一根因并已有裁定**（「两个上游测试本 change 不改」「Linux 上预期通过，不得进入 CI 排除」），本切片不新开条目，只把这次 A/B 证据补进 ADJ-006，仍 `resolved: false` 待用户裁定。
注意：CI 跑 ubuntu-latest，时钟粒度细，**可能**不复现——但这只是推断，**未验证**，须由 TC-CBE-005（真实 CI run）确认，不报绿。

证据：`probe-presenter/probe-runs.txt`、`probe-presenter/run{1,2}/probe-presenter-flake.{json,ndjson}`。

---

## 6. 容器与安全边界

- 本切片全部数据库动作只经 `run-selection.mjs` **自建的一次性 podman 实例**；每次运行结束都打印 `released instance … remaining=0`（RED `4d25e39238f4`、GREEN `292534b3ebff`、变异 `fb10525d9426`、整包 `914e5ac1721f`、探针 `a6e2f613acd4` / `0438a11152a7`）。
- 探针运行前后 `podman ps -a --format '{{.Names}} {{.Status}} {{.Image}}' | sort` **逐字节相同**（`containers-compare.txt` 为 0 字节）；全部运行结束后复查，仍只有 `multica-postgres`、`multica-backend` 两个既有旧容器且均 `Exited (0)`。
- **未连 localhost:5432**、**未操作旧 `multica-postgres` 容器**、未触碰 `multica-pgdata` 卷、**未放宽 nonce 门禁**、**未读取或打印任何凭据**。
- 变异 3/4 对 schema 的改动全部在一次性库内，且已还原/删除；未新增迁移文件。

---

## 7. 未验证 / 范围外 / 待裁定

**未验证（不得报通过）**：

1. CP-WSD-002～005 对应的 `handler-wsd-delete` / `handler-wsd-retain` / `handler-wsd-atomic` / `handler-wsd-no-recreate` **四条 selection 尚不存在**，属 S9/S10。
2. **删除实现本身未写**：`retain` 分类不产生任何运行时删除行为；`DeleteWorkspaceExecutionRows` 与 `deleteSteps` 挂钩属 S9。
3. `cr_execution_control_command` 的**收敛转换未实现**（648 头部要求「不得为已删 workspace 重建」），本切片只把它归为 retain；禁新建探针属 S10（**U3 停下上报点**）。
4. 未在 ubuntu-latest 上跑过本 selection；presenter flake 在 CI-linux 是否复现**未知**。
5. `make test` 未执行（U5 排除）；未执行真实 CI run（TC-CBE-005）。
6. 整包回归的 47 个 skip **未逐个重新定性**，沿用 S4 归属表；`allowed-skips` 仍只是下界。

**范围外发现（已上报，未擅自扩围）**：

- **ADJ-006（既有，本次补证）**：`createPresenterTestMember` 的 `UnixNano` email 后缀在 Windows 上非确定性撞唯一键，污染 handler 整包回归信号；受害测试会在运行之间移动。既有裁定为「本 change 不改这两个上游测试、不得进入 CI 排除」，本次 A/B 证据已补入该条，仍待用户裁定是否扩围修复。
- `TestSearchIndexChangesScopeToWorkspace` 基线即红，S4 已定性，本切片未处理。

---

## 8. 证据文件清单

```
red/handler-wsd-manifest.{json,ndjson}          RED 真跑（exit 1，19 张未分类）
green/handler-wsd-manifest.{json,ndjson}        GREEN 真跑（exit 0，2 pass 0 skip）
red-green-run.txt                               RED/GREEN 控制台原文 + 还原核对
mutation-manifest-and-catalog.txt               4/4 变异汇总 + sha256 前后一致
mutations/manifest-entry-removed.ndjson         变异 1
mutations/classification-reverted.ndjson        变异 2
mutations/retain-trigger-dropped.ndjson         变异 3（真库删触发器）
mutations/retain-fk-added.ndjson                变异 4（真库加外键）
regression-directory.tap                        node 目录全量 154 PASS
regression-handler/baseline-handler.{json,ndjson}  handler 整包真跑（4.7 MB 原始流）
regression-handler-failing-diff.txt             与 S4 基线按测试名对账
probe-presenter/probe-runs.txt                  presenter 单独跑两次控制台原文
probe-presenter/run{1,2}/probe-presenter-flake.{json,ndjson}
probe-presenter/containers-{before,after,compare}.txt  容器清单比对（compare 为 0 字节）
```