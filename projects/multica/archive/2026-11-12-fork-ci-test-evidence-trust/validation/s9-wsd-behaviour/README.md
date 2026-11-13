# Slice 9 — workspace 删除路径的执行控制表行为验证

STDD change：`2026-11-12-fork-ci-test-evidence-trust`
能力：`workspace-delete-execution-tables` / REQ-WSD-001 / SC-WSD-002、SC-WSD-003、SC-WSD-004
TC：TC-WSD-002、TC-WSD-003、TC-WSD-004　CP：CP-WSD-002、CP-WSD-003、CP-WSD-004
执行时间：2026-11-12（本机 Windows，Node v24.22.1，Go 工具链见 `go vet`）

> **结论先说（2026-11-12T23:01+08:00 更新）**：SC-WSD-002、SC-WSD-003、SC-WSD-004 **全部通过**，CP-WSD-002/003/004 均 exit 0，**Slice 9 已标记 done**（`slices_completed['9']`：tc_coverage 3/3、new_tests 25）。
>
> **过程如实保留**：首轮验证时 SC-WSD-003 **部分通过**——逐字节保留与 11 张 retain 表的普通 DELETE 拒绝全部通过，但 **TRUNCATE 拒绝有 2 张表失败**（`cr_execution_binding_issue`、`cr_execution_consumption`），根因是既有迁移 643/644 缺语句级守卫，不是本切片改动造成。当时 CP-WSD-003 exit 1、Slice 9 **未**标记 done，记 ADJ-014（major）停下待裁定，**未自行选边**。用户裁定「补迁移修缺口（修订 SC-WSD-002）」后，按 STDD revision 流程修订 canonical 并重签 Gate 2，再新增迁移 **649** 修复，复验全绿。§7 保留发现当时的完整记录，§11 记录裁定与修复。

---

## 1. 产出物与改动面

| 文件 | 性质 | 改动 |
|---|---|---|
| `server/internal/governance/workspace_delete_execution.go` | **fork 独有**（新，`// AIFIRST:` 英文头） | 新增 `DeleteWorkspaceExecutionRows(ctx, tx pgx.Tx, workspaceID string) error`，两条参数化 `DELETE … WHERE workspace_id = $1::uuid` |
| `server/internal/handler/workspace.go` | **上游文件挂钩点** | 净增 **11 行 / 0 删除**：1 行带 `// AIFIRST:` 的 governance import + 10 行 `deleteSteps` 新步骤 |
| `server/internal/handler/workspace_delete_execution_test.go` | **fork 独有**（新，`// AIFIRST:` 英文头） | 3 个顶层测试 + 22 个子测试，19 张表 × 2 个 workspace 的夹具 |
| `scripts/aifi45-disposable/selections.json` | fork 目录（M30 已登记） | 追加 `handler-wsd-delete` / `handler-wsd-retain` / `handler-wsd-atomic` 三条，名字取自锁定的 canonical CP-WSD-002/003/004；裁定后另追加 `governance-migration-roundtrip`（ADJ-016，见 §11） |
| `server/migrations/649_cr_execution_truncate_guard.{up,down}.sql` | **fork 独有**（新，裁定后追加） | 两条 `BEFORE TRUNCATE … FOR EACH STATEMENT` 守卫 + 配套 down，见 §11 |
| `server/internal/governance/execution_migration_roundtrip_test.go` | **fork 独有**（改，CUSTOM.md #204） | 把 649 纳入 down/up 循环与触发器清单，净增 7 行 / 删 3 行，见 §11 |

**SC-WSD-002 的三条禁止项逐条核实**（`git status --porcelain` 为空即未改）：

- 不新增迁移：**首轮**为 `server/migrations/` 无改动；用户裁定后按修订版 SC-WSD-002 **只新增 649**（补 TRUNCATE 守卫 + 配套 down），643/644/645/648 及其余迁移**逐字节未动**
- 不新增触发器例外：**始终成立**——649 只加拒绝型语句级守卫，未为任何表开删除/更新例外（D2 的实质 concern 未被触碰）
- 不改 sqlc 查询：`server/pkg/db/`（含 `queries/`、generated）无改动

`gofmt -l` 对三个 Go 文件无输出；`go vet ./internal/governance ./internal/handler` exit 0。

### 1.1 步骤位置（ADJ-013）

design 决策 7 只说「追加一步」未指定位置，但 SC-WSD-004 要求「追加步骤**之后**的某一步失败」。若按字面追加到 `deleteSteps` 末尾（`delete workspace` 之后），其后无步骤，该场景无法构造。

实际位置：`delete chat pins` 之后、`lock task usage rollup` 之前（`workspace.go:1216-1225`）。这样既有的 **advisory 4246 竞争**就是真实的生产失败注入器——`TestDeleteWorkspace_FailsFastWhenRollupLockHeld` 已证明该路径返回 503——无需新增测试专用钩子、无需改上游失败语义。notice/dispatch_root 无外键无触发器，与 rollup/task 删除无顺序依赖。

`requester.WorkspaceID` 实为 `pgtype.UUID`（首次 `go vet` 报类型不符），按 handler 既有惯例 `uuidToString`（`handler.go:649`）转 string，governance 签名保持决策 7 原样。

---

## 2. 夹具设计

- **19 张表全覆盖**：`newExecutionRows` 按依赖序返回 19 行（notice → dispatch_root → binding_issue → consumption → activation → contract_selection → code_source_freeze → control_reservation → control_command → tool_verdict → control_settlement → task_binding → control_fact → tool_cursor → deployment_head → deployment_snapshot → policy_readiness → policy_activation_event → policy_activation_head），`newExecutionFixture` 断言 `len == 19`。A、B 各一份。
- **随机唯一键（EXP-2026-0001 / ADJ-006）**：所有 id 用 `uuid.NewString()`（crypto 随机），slug 用 UUID 去连字符前 12 位。**不使用 `time.Now().UnixNano()`**——S4 探针已证伪本机时钟粒度（200000 次取值中 199996 次重复）。
- **归属谓词**：7 张表按 `workspace_id`；4 张按 `lineage_id`；6 张按 `scope`；`control_settlement` 按 `request_id`；`task_binding` 按 `reservation_id`。跨表引用走真实链（selection → reservation → command → verdict → settlement / task_binding），尽管 schema 无外键。
- **逐字节比较**：`SELECT t::text FROM <tbl> t WHERE <attr> ORDER BY 1` 取整行文本（复合类型 cast，bytea 为 `\x` 十六进制，jsonb 已规范化），**不是行数比较**——改写 digest 或半删行都会改变它。digest 列用 `sha256(label)` 生成真实 64 位十六进制，满足各表 CHECK，且每行互不相同。
- **分类不第三次复述**：`assertTeardownOutcome` 直接读 `workspaceDeletionManifest[row.table]` 推导期望。S8 的 `workspace_delete_retention_test.go` 已用独立评审映射把该清单钉在决策 7 上，因此本切片验的是「行为是否符合该分类」，不再复制一份分类。
- **串行化**：三个测试都先 `lockRollupSingleton(t)`（advisory 42463980，与生产 4246 刻意不同），避免与 scheduler 的 rollup 单例互相干扰。

---

## 3. RED（实现前）

命令：`node scripts/aifi45-disposable/run-selection.mjs --selections <三条 S9 selection 的临时文件> --evidence-dir validation/s9-wsd-behaviour/red`
（临时文件内容与 `selections.json` 中这三条逐字相同；一个实例、三个一次性库。）

| selection | pass | fail | skip | 首个失败 |
|---|---|---|---|---|
| `handler-wsd-delete` | 0 | 1 | 0 | `:374 cr_execution_notice: delete row for workspace A survived the teardown` |
| `handler-wsd-retain` | 0 | 1 | 0 | `:398` 同上 |
| `handler-wsd-atomic` | 0 | 1 | 0 | `:491` 同上（正向对照处） |

runner exit **1**，实例 released `remaining=0`。

**RED 是断言级而非夹具级**，三点为证：

1. 19 张表 × 2 个 workspace 全部播种成功（无 `seed <table>` 致命错误）。
2. `DeleteWorkspace(A)` 返回 **204**（未在 `:369` / `:393` / `:488` 处失败）。
3. atomic 测试走过了 503 断言（`:467`）、回滚后 A/B 逐字节不变（`:474`/`:475`）、workspace A 仍在（`:482`）、无竞争正向对照 204（`:488`），**只在最后一步「必须真删」处红**——说明 advisory 4246 注入器与回滚语义在实现前就已成立，红的唯一原因是缺 sweep。

证据：`red/handler-wsd-{delete,retain,atomic}.{ndjson,json}`。

---

## 4. GREEN 与 CP 逐条取证

先按临时 selection 文件跑一轮（`green/`），再**按 canonical 锁定的命令原样**逐条重跑（`cp/`）：

```
node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-delete
node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-retain
node scripts/aifi45-disposable/run-selection.mjs --selections scripts/aifi45-disposable/selections.json --only handler-wsd-atomic
```

| CP | 锁定断言 | 首轮实测（649 之前） | 判定（首轮） | 裁定后复验（649 之后） |
|---|---|---|---|---|
| CP-WSD-002 | exit 0 且 stdout 含 `PASS handler-wsd-delete ` | exit **0**，`PASS handler-wsd-delete pass=1 fail=0 skip=0` | **通过** | exit **0**，`pass=1 fail=0 skip=0` |
| CP-WSD-003 | exit 0 且 stdout 含 `PASS handler-wsd-retain ` | exit **1**，`FAIL handler-wsd-retain pass=20 fail=3 skip=0` | **不通过**（见 §7） | exit **0**，`PASS handler-wsd-retain pass=23 fail=0 skip=0`（见 §11） |
| CP-WSD-004 | exit 0 且 stdout 含 `PASS handler-wsd-atomic ` | exit **0**，`PASS handler-wsd-atomic pass=1 fail=0 skip=0` | **通过** | exit **0**，`pass=1 fail=0 skip=0` |

`green/` 与 `cp/` 两轮结果一致（retain 同为 20/3/0，失败子测试同名）。每条命令各自新建并释放一次性实例，`remaining=0`。裁定后的复验证据在 `green-649/`，命令与上表锁定命令**逐字相同**。

### 4.1 SC-WSD-003 首轮已通过的部分（TRUNCATE 缺口见 §7，修复见 §11）

`pass=20` 的构成：**11 个 `plain_delete_<table>` 全部通过** + **9 个 `truncate_<table>` 通过**。父测试在 `:398`/`:399` 的逐字节断言处**未失败**（否则不会进入子测试），即：

- retain 类 A 行逐字节不变（含 digest 列）——通过
- keep 类 A 行不变——通过
- B 的全部 19 行不变——通过
- 11 张 retain 表的普通 DELETE 仍被触发器拒绝，且错误报文含表名（排除「因无关原因被拒」）——通过

### 4.2 SC-WSD-004 的正向对照

atomic 测试末尾在释放 4246、把超时调回 5s 后**再删一次并要求 204 + A 的 delete 类行真消失**。没有这一步，「什么都没变」会被一个**根本不存在 sweep** 的实现空洞地满足。变异 m4 正是靠这条对照之外的回滚断言抓到的（见 §5）。

---

## 5. 变异验证 4/4 DETECTED

脚本：逐条改一处生产代码 → 在一次性库真跑对应 selection → **立即按原字节还原并核对 sha256**。

baseline sha256：
- `workspace_delete_execution.go` = `eaf5ce61cf9dcfb8133b9b74e7d64a0b32cc4a6c33d8c114b0a794cd303fe841`
- `workspace.go` = `61006566ab1f8d59c139791167a1255a47739fd56053218cecce30c3062b7a4e`

| 变异 | 改动 | selection | 结果 | 报文 |
|---|---|---|---|---|
| m1 | 删掉 notice 的 DELETE | `handler-wsd-delete` | **DETECTED** exit 1 | `cr_execution_notice: delete row for workspace A survived the teardown` |
| m2 | 删掉 dispatch_root 的 DELETE | `handler-wsd-delete` | **DETECTED** exit 1 | `cr_execution_dispatch_root: … survived the teardown` |
| m3 | 把 sweep **加宽**到 retain 表（多删 `cr_execution_consumption`） | `handler-wsd-delete` | **DETECTED** exit 1 | `expected 204 … got 500`——append-only 触发器拒绝了加宽 |
| m4 | 把 sweep 改成**自开事务并立即 Commit**（脱离 teardown 事务） | `handler-wsd-atomic` | **DETECTED** exit 1 | `:474 cr_execution_notice (delete) row for workspace A changed` |

四次各自新建并释放实例；每次还原后 sha256 与 baseline 逐字相同，脚本末尾再总核一遍两个文件。**m3 证明 retain 触发器是承重的**（sweep 不能悄悄加宽），**m4 证明「在既有事务内」是被断言的保证**。

证据：`mutations/<mN>/{selection.json,runner-output.txt,mutated.diff.txt,<name>.ndjson,<name>.json}`。

---

## 6. 回归

### 6.1 node 目录全量

`node --test "scripts/aifi45-disposable/*.test.mjs"` → **154 pass / 0 fail / 0 skip**，exit 0（与 S6/S7/S8 一致，本切片未改 node 代码）。
证据：`regression-directory.tap`。（Windows Node 24 必须用 glob 形式。）**649 裁定改了 `selections.json`，故另复跑一次：154/0/0，见 §11.7 与 `regression-directory-649.tap`。**

### 6.2 handler 整包（一次性实例真跑）

`--selections scripts/aifi45-disposable/selections.baseline.json --only baseline-handler`，注入 `CRCTL_MJS` / `AIFI45_TOOLS_ROOT`（tools `e52b8081f159`，与 S4/S8 同条件）。

| | pass | fail | skip |
|---|---|---|---|
| S4 基线 | 4507 | 3 | 47 |
| S8 回归 | 4506 | 5 | 47 |
| **S9 回归** | **4529** | **7** | **47** |

**按测试名逐条对账**（`regression-handler-failing-diff.txt`，遵循 ADJ-006 的裁定：不得以计数差直接判回归）：

- S9 失败集合（7）：`TestGetPresenterStateVisibility`、`TestPresenterIllegalTransitions`、`TestPresenterIllegalTransitions/non-presenter_cannot_transfer`、`TestSearchIndexChangesScopeToWorkspace`、`TestWorkspaceDeletionKeepsRetainedEvidenceByteForByte`（+ 2 个 `truncate_` 子测试）
- 相对 S8 **新增 4**：3 个是本切片的 TRUNCATE 缺口（§7），1 个是 presenter 家族新受害者
- 相对 S8 **不再失败 2**：`TestPresenterIllegalTransitions/approve_while_a_presenter_is_already_active`、`TestPresenterTransferFlow`（均为 presenter）
- presenter 净变化 −1，本切片缺口 +3 → fail 净 **+2**；pass 净 **+23** = 22 个新通过名 + presenter 净 +1
- `TestSearchIndexChangesScopeToWorkspace` 与 S4 基线**同名同因**，属 S4 归属表已定性的范围外项，本切片未触碰
- skip 集合数量不变（47）

**presenter 家族第三次观察到受害者移动**（S4 基线 = `MemberRemovalLinkage`；S8 = `TransferFlow` + `IllegalTransitions/approve_while…`；S9 = `GetPresenterStateVisibility` + `IllegalTransitions/non-presenter…`），报文同型（`create member user: duplicate key user_email_key`）。S8 已用 `-run '^TestPresenter'` 单独连跑两次证明其与本 change 无因果关系，本切片沿用该定性，**未修改任何上游 presenter 测试**。

### 6.3 覆盖没有丢失（UUID 改名核对）

按名对账时发现 6 个 `TestPluginRoutesRequireWorkspaceAdmin/…` 子测试名「新增」——它们的名字里嵌了**随机 workspace UUID**，每次运行都不同。用 UUID 规范化后复核（`regression-name-stability.txt`）：

- 规范化后 S8 = 4558 名、S9 = 4583 名
- **规范化后新增 25 名，全部是本切片的 3 个顶层测试 + 22 个子测试**
- **规范化后移除 0 名**
- 6 个「新」原始名 ↔ 6 个「消失」原始名，规范化后一一对应

结论：**没有丢失任何测试覆盖**，计数差完全由本切片新增的 25 个测试实体与 presenter flake 解释。

---

## 7. 发现的规格冲突：两张 retain 表没有 TRUNCATE 守卫（ADJ-014，major，**已裁定并修复，见 §11**）

> 本节是**发现当时**的原始记录，逐字保留（含「未采取任何一条」「待裁定」等当时的状态陈述），用于证明 Agent 没有自行选边、没有放宽断言。最终状态以 §11 与文首结论为准。

### 7.1 实测

`handler-wsd-retain` 的 22 个子测试中，**恰好 2 个失败**：

```
workspace_delete_execution_test.go:420: cr_execution_binding_issue accepted TRUNCATE; a row-level guard does not fire on TRUNCATE
workspace_delete_execution_test.go:420: cr_execution_consumption accepted TRUNCATE; a row-level guard does not fire on TRUNCATE
```

即 `TRUNCATE cr_execution_binding_issue` 与 `TRUNCATE cr_execution_consumption` **被数据库接受**，整表清空成功。其余 9 张 retain 表的 TRUNCATE 均被拒绝。

### 7.2 根因（迁移原文，非本切片造成）

| 迁移 | 表 | 触发器 | TRUNCATE 守卫 |
|---|---|---|---|
| 643 | `cr_execution_binding_issue` | 仅 `cr_execution_binding_issue_no_mutation`：`BEFORE UPDATE OR DELETE … FOR EACH ROW` | **无** |
| 644 | `cr_execution_consumption` | 仅 `cr_execution_consumption_no_mutation`：`BEFORE UPDATE OR DELETE … FOR EACH ROW` | **无** |
| 645 | `cr_execution_activation` | row UPDATE/DELETE + `BEFORE TRUNCATE FOR EACH STATEMENT` | 有 |
| 648 | 其余 12 张 | row 守卫 + `BEFORE TRUNCATE FOR EACH STATEMENT` | 有 |

`grep -rn TRUNCATE server/migrations/*.up.sql` 与 `grep -rln 'cr_execution_binding_issue\|cr_execution_consumption' server/migrations/*.sql` 确认：**没有后续迁移补过这两个守卫**（只有 643/644 各自的 up/down 提到这两张表）。

PostgreSQL 的 **TRUNCATE 不触发行级触发器**，所以只有 row 守卫等于没有守卫。648 自己的头注释明文声明了这条不变量：

- 第 11–12 行：`retained evidence tables reject UPDATE/DELETE row-level AND TRUNCATE statement-level. TRUNCATE does not fire row triggers, so a row-only guard would …`
- 第 406 行：`TRUNCATE does not fire row triggers; every retained table needs this statement guard.`

**即 schema 自述的规则被两张早于 648 的表违反。** 本切片未新增或修改任何迁移，`git status --porcelain -- server/migrations/` 为空。

### 7.3 为什么这是锁定规格的内部冲突

- **canonical SC-WSD-003**（Gate 2 锁定）：「对 retain 表的普通 DELETE **与 TRUNCATE** SHALL 仍被触发器拒绝」
- **canonical CP-WSD-003**：exit 0 且 stdout 含 `PASS handler-wsd-retain `
- **canonical SC-WSD-002**：「SHALL **不新增迁移**、不新增触发器例外、不改 sqlc 查询」
- **design.md 决策 7** 行为测试段只写「对 retain 表的普通 `DELETE` 仍被触发器拒绝」，**未含 TRUNCATE**；逐表映射的列名是「DELETE 触发器」，且只为 activation 标注「含 no_truncate」——design 对 DELETE 触发器的描述是准确的，并未声称这两张表有 TRUNCATE 守卫。

按 **canonical-first**，canonical 比 design 多出的 TRUNCATE 半句生效，因此断言保留原样、如实报红。要让它变绿只有两条路，**两条都超出 Agent 授权**：

1. 新增迁移补两个 `BEFORE TRUNCATE FOR EACH STATEMENT` 守卫 → 违反 SC-WSD-002 的「不新增迁移」
2. 把 SC-WSD-003 的 TRUNCATE 半句收窄到「已有语句级守卫的表」→ 修改 Gate 2 锁定的 canonical

**未采取任何一条**：未改 canonical、未放宽或删改断言、未新增迁移、未改触发器、未把这两个子测试加进任何排除名单。

### 7.4 安全影响

具备数据库写权限者可以 `TRUNCATE` 清空 **binding 签发证据**与**消费回执**这两类审计记录而不被拒绝。这正是 645/648 为其余表加语句级守卫所要防的事。属既有缺陷，本 change 的发现而非引入。

### 7.5 待裁定（当时状态；裁定结果见 §11）

已记 **ADJ-014（major，resolved: false）**，与 ADJ-005 同为本 change 的 major 未决项。Slice 9 **未标记 done**，`tasks.md` 9.3 保持未勾选。

**后续**：用户选择 §7.3 的第 1 条路（补迁移），并要求按 STDD revision 修订 SC-WSD-002 后重签 Gate 2。ADJ-014 现为 `resolved: true`；ADJ-005 仍未决。

---

## 8. 容器与凭据边界

- 全部数据库验证只经 `run-selection.mjs` **自建的一次性 podman 实例**；每条 selection 一个一次性库，用完 `dropDisposableDatabase`，实例 `releaseInstance` 后 `remaining=0`。
- **未连接 `localhost:5432` 旧库，未操作 `multica-postgres` / `multica-backend`**。
- 运行前后 `podman ps -a --format …` 按排序集合比对：**无差异**，只有两个既有旧容器且均 `Exited`（`containers-before.txt` / `containers-after-red.txt` / `containers-after.txt`，比对结果 `INVENTORY_UNCHANGED`）。
- **未放宽 nonce 门禁**：本切片未改 `verifyDisposableTestDatabase` 或任何身份校验代码。
- **未读取、打印任何 PAT 或凭据**；`CRCTL_MJS` / `AIFI45_TOOLS_ROOT` 只指向 tools 工作区路径，未涉及 secret。
- tools 仓 HEAD 核实为 `e52b8081f159`（与 `.github/aifirst-tools-pin` 一致），其既有未提交改动**未触碰**；multica HEAD 核实为 `903a46c5a`。
- **裁定后（迁移 649）各轮同样满足以上全部边界**，逐轮清单与实例 id 见 §11.8（`containers-before-649.txt` / `containers-after-649.txt` / `containers-before-node649.txt` / `containers-after-node649.txt`）。

---

## 9. 未验证 / 未完成（如实列出）

| 项 | 状态 | 原因 |
|---|---|---|
| CP-WSD-003 / SC-WSD-003 TRUNCATE 半句 / TC-WSD-003 | **通过**（裁定后） | 首轮不通过 → 用户裁定补迁移 649 → 复验 exit 0 `pass=23 fail=0 skip=0`，见 §11 |
| Slice 9 `slices_completed` | **已写入** | `status: done`、`tc_coverage: 3/3`、`new_tests: 25`、`verified_at: 2026-11-12T23:01:31` |
| `tasks.md` 9.3 | **已勾选** | 同上；发现当时的记录逐字保留 |
| CP-WSD-005 / `handler-wsd-no-recreate` | 未执行 | 属 Slice 10（U3 上报点） |
| CI-linux（ubuntu-latest）上跑这三条 selection | **未验证** | 需真实 CI run（TC-CBE-005 / S13），本机结果不能外推 |
| presenter flake 在 CI-linux 是否复现 | **未验证** | 同上；不得提前报绿 |
| `make test` | **未执行** | U5 明确排除 |
| 真实 Postgres up/down（ci-provision） | 未执行 | 属 S13 + TC-CBE-005；649 的 down 已由 `TestExecutionMigrationDownRoundTrip` 在一次性库真跑（§11） |
| Git 提交 / 推送 | **未做** | Gate 确认不自动推导授权；须单独取得授权 |
| ADJ-005（tools `rules.json` show 形状缺口，major） | **仍未决** | 需用户裁定后才能进 S13 设 `MULTICA_CONTROLLED_SHELL_RULES` |

---

## 10. 证据文件清单

```
red/handler-wsd-{delete,retain,atomic}.{ndjson,json}      RED 三条（实现前）
green/handler-wsd-{delete,retain,atomic}.{ndjson,json}    GREEN 三条（临时 selection 文件）
cp/handler-wsd-{delete,retain,atomic}.{ndjson,json}       按 canonical 锁定命令原样重跑
mutations/m1-drop-notice-delete/                          变异 1（含 selection.json / runner-output.txt）
mutations/m2-drop-dispatch-root-delete/                   变异 2
mutations/m3-widen-sweep-to-retained-table/               变异 3
mutations/m4-sweep-commits-outside-teardown-tx/           变异 4
regression-directory.tap                                  node 目录全量 154/0/0
regression-handler/baseline-handler.{json,ndjson}         handler 整包真跑
regression-handler-failing-diff.txt                       与 S4/S8 按测试名逐条对账
regression-name-stability.txt                             UUID 规范化核对：新增 25、移除 0
containers-before.txt / containers-after-red.txt / containers-after.txt   podman 清单（排序后逐字相同）
red-green-selection.json                                  RED/GREEN 用的临时 selection 文件（与 selections.json 三条逐字相同）

--- 裁定后（迁移 649）追加，见 §11 ---
green-649/handler-wsd-{delete,retain,atomic,manifest}.{ndjson,json}      按锁定命令原样复验（retain 23/0/0）
green-649-governance/governance-migration-roundtrip.{ndjson,json}        649 纳入 down/up 循环后真跑（1/0/0）
green-649-governance/channel-migration-{up,down,reapply}.{ndjson,json}   648 家族三种状态复验（19/22/15，全 0 fail）
mutations-649/m1-drop-binding-issue-truncate-guard/                     变异 1（含 selection.json / mutated.diff.txt / runner-output.txt）
mutations-649/m2-drop-consumption-truncate-guard/                       变异 2
mutations-649/m3-down-drops-trigger-on-wrong-table/                     变异 3（证明 down 文件真被执行）
regression-handler-649/baseline-handler.{json,ndjson}                   handler 整包真跑（4533/3/47）
regression-governance-649/baseline-governance.{json,ndjson}             governance 整包，本 shell 未设 tools env（1312/59/1）
regression-governance-649-toolsenv/baseline-governance.{json,ndjson}    governance 整包，tools env 已设（1344/48/1）
regression-649-reconcile.txt                                            三组按测试名 + UUID 规范化逐条对账
regression-directory-649.tap                                            node 目录全量复跑 154/0/0（selections.json 改后）
containers-before-649.txt / containers-after-649.txt                    649 各轮 podman 清单（排序后逐字相同）
containers-before-node649.txt / containers-after-node649.txt            node 复跑前后清单（INVENTORY_UNCHANGED，153 字节）
```

---

## 11. ADJ-014 裁定与修复：迁移 649 补 TRUNCATE 守卫

### 11.1 用户裁定（原文）

> **补迁移修缺口（修订 SC-WSD-002）**：新增迁移 649，给这两张表加 `BEFORE TRUNCATE FOR EACH STATEMENT`，复用各自已有的 `append_only` 函数（纯加强，不开任何删除例外，不违反 D2 的实质 concern）。需按 STDD revision 修订 SC-WSD-002 的「不新增迁移」并重签 Gate 2。结果：SC-WSD-003 全绿，真实修掉一个审计证据可被清空的缺口。代价：本 change 首次触碰 schema，需配套 down 迁移。

### 11.2 先修订、后实现（顺序不可颠倒）

1. `design.md` 新增 **修订记录 R4**（原文 / 核实依据 / 用户裁定 / 修订后 / 影响范围五段），并同步决策 7 的删除实现、逐表映射标注、行为测试段（DELETE **与 TRUNCATE**）、「为什么」段与两行风险表。
2. **canonical** `canonical/specs/code/workspace-delete-execution-tables.yaml:29` 的 SC-WSD-002 改为：

   > SHALL **除补 TRUNCATE 守卫的迁移 649 外**不新增迁移、不新增触发器例外（不得为 append-only 触发器开任何删除例外）、不改 sqlc 查询；649 SHALL 只加语句级 TRUNCATE 拒绝、复用 `cr_execution_binding_issue` 与 `cr_execution_consumption` 各自已有的 `append_only` 函数，并 SHALL 配套 down 迁移。

   SC-WSD-003 与全部 CP-WSD-* **逐字未动**（断言没有被放宽）。
3. 人类视图 `specs/workspace-delete-execution-tables/spec.md:22`、`test-plan.md:265` 手工镜像同一句。**工具限制已如实登记 ADJ-015**：`stdd canon generate --type spec <change>` 忽略 `--type`（`canon.py:330` → `_generate_one:688-712`），单变更模式只重渲染 proposal.md；spec 人类视图仅在 `--all` 分支生成，而该分支会用 `datetime.now()` 重渲染**所有** change 的 proposal.md，将混入他人未提交记录。195 文件 sha256 快照证明单变更调用前后逐字节相同。**未使用 `--all`**。
4. **Gate 2 重签**：`stdd gate approve 2026-11-12-fork-ci-test-evidence-trust --gate 2 --confirmed-by dialog --reapprove --evidence "<用户选项原文>"`。旧回执 `gate2-2026-11-12T16:28:26` 标 `superseded`，新回执 `confirmed_at: 2026-11-12T22:34:11`，`input_fingerprint: 82de564f…`，受审清单中 `canonical/specs/code/workspace-delete-execution-tables.yaml` = `b75f1b78…`、`design.md` = `d40edf5c…`、`specs/…/spec.md` = `003e1e8d…`、`test-plan.md` = `e4d2ba50…`，与修订后文件一致。
5. 之后才写迁移与测试。

### 11.3 迁移 649 内容

`server/migrations/649_cr_execution_truncate_guard.up.sql`（LF，sha256 `95507243e32b003dd650b3469df2164bf5239418ef7967b2a93bfbdcffc51129`）：

```sql
CREATE TRIGGER cr_execution_binding_issue_no_truncate
    BEFORE TRUNCATE ON cr_execution_binding_issue
    FOR EACH STATEMENT EXECUTE FUNCTION cr_execution_binding_issue_append_only();

CREATE TRIGGER cr_execution_consumption_no_truncate
    BEFORE TRUNCATE ON cr_execution_consumption
    FOR EACH STATEMENT EXECUTE FUNCTION cr_execution_consumption_append_only();
```

`…down.sql`（LF，sha256 `5b29747463f695a7055bf45b20380bf3e8bee73c7030fa126237bf5adcbe74f6`）：两条 `DROP TRIGGER IF EXISTS … ON …`。

- **复用各表自己的 `append_only` 函数**，因此拒绝报文与 row 守卫完全同型，不引入新函数、新错误语义。
- **只拒绝，不放行**：没有为任何表开删除/更新例外，643/644/645/648 逐字节未动，`server/pkg/db/` 无改动。
- `CREATE TRIGGER` 无 `IF NOT EXISTS`，依赖 `schema_migrations` 保证只应用一次（与 645/648 同惯例）；down 幂等。
- **合并注意**：既有数据库升级后会开始拒绝这两张审计表的 TRUNCATE——这是**有意的安全加强，不是回归**。已写入 CUSTOM.md #326。

### 11.4 为什么必须同时改 roundtrip 测试（ADJ-016）

`execution_migration_roundtrip_test.go` 会把 643–647 **down 再 up**。down 的 `DROP TABLE` 会连带删掉 649 建在表上的触发器，而原来的 up 列表不含 649 → **不会重建**。若不把 649 纳入循环，整包运行中该测试之后的所有测试都会跑在「两张表失去 TRUNCATE 守卫」的降级 schema 上，且**无声**。

改动（净增 7 行 / 删 3 行，fork 独有文件，CUSTOM.md #204）：
- `executionMigrationFiles` 追加 `"649_cr_execution_truncate_guard"`；
- 清单中两行的 `triggers` 各加 `…_no_truncate`；
- 头注释说明 649 必须加入循环。

附带收益：**649 的 down 文件第一次被真实执行**（此前没有任何测试跑过它）。新增 selection `governance-migration-roundtrip`（`^TestExecutionMigrationDownRoundTrip$`）以便按锁定入口单独取证。

### 11.5 复验结果（全部一次性 podman 实例）

| selection | pass | fail | skip | ok |
|---|---|---|---|---|
| `handler-wsd-retain`（**CP-WSD-003**） | **23** | **0** | 0 | true，exit **0** |
| `handler-wsd-delete`（CP-WSD-002） | 1 | 0 | 0 | true，exit 0 |
| `handler-wsd-atomic`（CP-WSD-004） | 1 | 0 | 0 | true，exit 0 |
| `handler-wsd-manifest`（S8 清单，CP-WSD-001） | 2 | 0 | 0 | true，exit 0 |
| `governance-migration-roundtrip` | 1 | 0 | 0 | true，exit 0 |
| `channel-migration-up`（state=migrated） | 19 | 0 | 0 | true |
| `channel-migration-down`（state=648-down） | 22 | 0 | 0 | true |
| `channel-migration-reapply`（state=648-down-up） | 15 | 0 | 0 | true |

`pass=23` 的构成：**11 个 `plain_delete_<table>` + 11 个 `truncate_<table>` + 1 个父测试**。SC-WSD-003 的三半句（retain 逐字节不变含 digest、keep 不变、普通 DELETE **与 TRUNCATE** 均被拒）全部成立。

### 11.6 变异验证 3/3 DETECTED（逐表归因）

| 变异 | 改动 | selection | 结果 | 唯一变红的断言 |
|---|---|---|---|---|
| m1 | 删掉 binding_issue 的 TRUNCATE 守卫 | `handler-wsd-retain` | **DETECTED** exit 1，`pass=21 fail=2` | `truncate_cr_execution_binding_issue`（+ 父） |
| m2 | 删掉 consumption 的 TRUNCATE 守卫 | `handler-wsd-retain` | **DETECTED** exit 1，`pass=21 fail=2` | `truncate_cr_execution_consumption`（+ 父） |
| m3 | down 改成 DROP **另一张表**的触发器（去掉 IF EXISTS） | `governance-migration-roundtrip` | **DETECTED** exit 1 | `execution_migration_roundtrip_test.go:128`：`trigger "cr_execution_consumption_no_truncate" for table "cr_execution_binding_issue" does not exist (SQLSTATE 42704)` |

m1/m2 **各自只打红自己那张表**，证明两条守卫分别承重、断言不是笼统的「有守卫就行」。m3 证明 **down 文件真的被应用**（不是写了没人跑）。三次各自新建并释放一次性实例，每次按原字节还原并核对 sha256（`95507243…` / `5b297474…`），脚本末尾总核，`MUTATE_EXIT=0`。

S9 首轮的 4 个变异（m1–m4，针对 sweep 实现）结论不变，见 §5；两个生产文件 sha256 复核仍为 `eaf5ce61…` / `61006566…`。

### 11.7 回归：按测试名对账，不按计数差下结论

**handler 整包**（`regression-handler-649/`，tools env 已设）：

| | pass | fail | skip |
|---|---|---|---|
| S9 首轮（649 前） | 4529 | 7 | 47 |
| **S9 复验（649 后）** | **4533** | **3** | **47** |

- **新增失败名 0**；不再失败 4 = `TestGetPresenterStateVisibility`（presenter flake 受害者移动）+ retain 父测试 + 2 个 `truncate_` 子测试（**正是被修好的缺口**）
- 剩余 3 个失败 = `TestPresenterIllegalTransitions`（+1 子测试）与 `TestSearchIndexChangesScopeToWorkspace`，均为 S4 归属表已定性的范围外项
- skip 集合 new=0 gone=0；**UUID 规范化终态名 4583 → 4583，新增 0、移除 0**（649 只改既有测试的通过状态，不新增测试实体）

**governance 整包**：本 shell 首轮跑出 1312/59/1，**11 个新失败名全部是 `CRCTL_MJS is required: … a dev-machine default is not evidence`**。核实 `AIFI45_TOOLS_ROOT` 与 `CRCTL_MJS` 在本 shell 均 `<unset>`，而 S4 基线两者已设（`s4-baseline-ownership/README.md:98`）——**这是环境差异，不是 649 或上游回归**。按 S4 同条件补设两个变量（指向已核实的 tools checkout `e52b8081f1`，crctl 在 `skills/shared/crctl/scripts/crctl.mjs`）后重跑：

| | pass | fail | skip |
|---|---|---|---|
| S4 基线 | 1328 | 48 | 1 |
| **649 后（tools env 已设）** | **1344** | **48** | **1** |

- **新增失败名 0、不再失败名 0**，skip 集合不变
- 规范化名 1377 → 1393，**新增恰好 16 名 = S7 的 `TestDisposableIdentityGateRefusesEachConditionAlone*` 家族**（S4 基线早于 S7），移除 0
- 两次运行都保留为证据（`regression-governance-649/` 与 `regression-governance-649-toolsenv/`），**不把环境失败归因给上游，也不归因给 649**
- **对 S13 的硬结论**：CI 的 backend-tests 必须显式注入 `AIFI45_TOOLS_ROOT` 与 `CRCTL_MJS`，否则这 11 个测试会在 CI 上以同样方式失败。已记入 S13 待办。

**node 目录全量**（`selections.json` 改后必须复跑）：`node --test "scripts/aifi45-disposable/*.test.mjs"` → **154 pass / 0 fail / 0 skip**，exit 0（`regression-directory-649.tap`）。

### 11.8 边界复核（649 各轮）

- 全部经 runner 自建一次性 podman 实例；6 个实例 id 均 `released … remaining=0`（`507de7f4a8f2`、`a916b7b24034`、`6edcf27b5723`、`949d5d2523e6`、`088aab08b22d`、`c63dec4ddd64`）
- `podman ps -a` 排序集合比对：649 各轮前后无差异；node 复跑前后 `INVENTORY_UNCHANGED`（153 字节逐字相同），始终只有 `multica-postgres` / `multica-backend` 两个既有 **Exited** 旧容器
- **未连接 localhost:5432、未操作旧容器、未放宽 nonce 门禁、未读取或打印任何凭据**
- tools HEAD `e52b8081f159` 与 `.github/aifirst-tools-pin` 一致，其未提交改动未触碰；multica HEAD `903a46c5a` = origin/main
- **未提交、未推送**

### 11.9 记账

- `CUSTOM.md` 新增 **#326**（M31 段，1093 行，全 CRLF 1093 / 裸 LF 0），登记 649 up/down、roundtrip 扩展、新 selection、全部证据与变异结果、两个 sha256 前缀、合并注意；M31 标题改为「10 行：#317–#326」，汇总表改 `#317–#326 | 10 |` 并扩列文件清单。**#324 逐字节未动**；**#325 原文逐字保留**，仅追加 159 字 forward-pointer 说明「本行描述的是发现当时的状态」。
- `pending-adjustments.yaml`：16 条；**ADJ-014 → resolved: true**（附完整处置），新增 **ADJ-015**（canon generate 工具限制，minor，resolved）、**ADJ-016**（roundtrip 扩展 + 新 selection，minor，resolved）。YAML 可解析性与字段核对通过。未决项仍为 ADJ-002/003/**005（major）**/006/007/009。
- `tasks.md`：9.3 → `[x]`（保留发现当时记录）、9.5 改题为「确认除迁移 649（R4 裁定）外不新增迁移…」并更新回归数字、新增 **9.6** 记录本节全过程。
- `.stdd.yaml`：`phases.build.slices_completed['9'] = {status: done, tc_coverage: 3/3, new_tests: 25, verified_at: 2026-11-12T23:01:31}`。**TC-WSD-001 属 Slice 8，TC-WSD-005 属 Slice 10**，故本切片分母为 3。