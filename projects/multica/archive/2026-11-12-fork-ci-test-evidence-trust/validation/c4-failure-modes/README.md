# C4 失败模式检查记录（全量执行）

- change：`2026-11-12-fork-ci-test-evidence-trust`
- 执行日期：2026-11-13
- 业务仓：`C:\Users\GOBAO\Downloads\AI\multica`，HEAD=`903a46c5ae9fa6c3ee644fa4740d189d739dcc91`
- 依据：`<DATA_ROOT>/experiences/` 全部 5 条经验（EXP-2026-0001…0005）+ Skill C4 点名的锚定缺失 / Agent CP 失败 / 跨系统不一致
- 执行方式：**逐项实读代码与目录取证**，无占位符。未实际执行的检查在 §4 明确标注 SKIPPED 并给出边界原因。
- 结论：**8 项检查完成**；2 项命中（1 项已申报限制、1 项继承缺口），均已记录处置，未自行修改代码。

---

## 1. 经验库逐条检查

### EXP-2026-0001 — 常量 id 写多条链，唯一键不含分链维度（severity high）

触发条件：设计里出现跨租户/跨 CR 共用的常量 id，且目标表有不含分链维度的唯一键。

| 检查点 | 取证 | 判定 |
|---|---|---|
| 649 迁移是否引入新唯一键或常量 id | 全文读 `649_…up.sql`(16 行)/`down.sql`(6 行)：只新增两个 `BEFORE TRUNCATE … FOR EACH STATEMENT` 触发器，复用各表自己的 `*_append_only()`；down 只删这两个语句级守卫，保留表、行级守卫与函数 | **无适用面**：未引入任何唯一键或 id |
| 新增行为测试是否用常量 id | `workspace_delete_execution_test.go` 随机 uuid 命中 27 处、`workspace_delete_no_recreate_test.go` 3 处 | PASS |
| `workspace_delete_retention_test.go`（uuid grep 零命中，实读确认） | 该文件是**纯目录/schema 测试**：读 `pg_trigger`/`pg_constraint`，不插行、不建 id；硬编码的是 19 张表的**分类映射**（schema 常量，非行 id），注释明写「manifest 是契约，本文件是对它的复核」 | PASS：无多链写入 |
| 两份 identity 条件测试 | 名字由 nonce 派生；`other = "0000000000000000"` 带碰撞守卫 `if other == nonce { other = "1111111111111111" }` | PASS：刻意取异值，非跨链共用常量 |

**判定：PASS（无适用面 + 新增测试均用随机/派生唯一值）**

### EXP-2026-0002 — ReadCommitted 下「先读后写」守卫放在序列化锁之前（severity high）

触发条件：出现 check-then-act 且序列化锁在 check 之后才取。

**命中 1（已申报限制，本轮不修）**：`server/internal/governance/execution_control_reservation.go:88-96`

```go
// Non-locking read: this closes the sequential teardown case only. A concurrent
// uncommitted DeleteWorkspace can still slip past it, which SC-WSD-005 does not require.
var workspaceExists bool
if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM workspace WHERE id = $1::uuid)`, …)
```

- 实证：`CreateReservationTx` 全函数 grep `pg_advisory|Lock|FOR UPDATE` **零命中**，即该守卫之后也没有序列化锁，属典型 check-then-act。
- 处置：代码注释已**主动申报**该限制，且 SC-WSD-005 不要求并发场景；与用户 ADJ-017/U3 裁定「只修 reservation 半句，command 半句做好记录待以后修订」一致。**不在本轮扩大范围**，记为已申报限制，Gate 3 呈报。

**未命中（实证排除）**：`server/internal/handler/workspace.go` 新增 sweep 阶段

- 实证锁序：`SET LOCAL lock_timeout`(1136) → **`LockWorkspaceForDelete`(1141，workspace 行 FOR UPDATE)** → `ListAgentRuntimeIDsByWorkspace` → `LockChatSessionsByWorkspace` → … → `deleteSteps`(1170+) 内含新增 `delete execution control routing`。
- 故 sweep **在行锁之内**执行，对同一 workspace 的并发拆除已串行化；置于 rollup advisory 4246 **之前**是为了让 4246 争用时 sweep 随整个事务回滚，不留 stranded 行（代码注释亦如此声明）。
- **判定：不是 EXP-0002 违规，是正确设计。**

### EXP-2026-0003 — 校验多行命令输出只取首行（severity medium）

触发条件：对命令/CLI 多行输出写 `[0]`/`head`/第一个匹配，且该输出是安全或归属判断依据。

| 命中点 | 实读上下文 | 判定 |
|---|---|---|
| `ci-evidence.mjs:110-119` `packages.get(matches[0])` | `[0]` 之前有两道守卫：`matches.length === 0` → push problem；`matches.length > 1` → push「ambiguous, matches N packages」。**恰好一个**才取 `[0]` | **PASS，正是本经验要求的 fail-closed 修法** |
| `ci-evidence.mjs:51-52` 流式逐行解析 | `JSON.parse` 的 catch **抛错硬失败**，非静默跳过 | PASS |
| `ci-evidence.mjs:91` `event.Test.split("/")[0]` | 取子测试的顶层测试名用于归属汇总，非安全判断 | PASS（语义正确） |
| `test-ownership.mjs:99`、`ci-provision.mjs:126` `argv[0]` | 命令分派；两者均显式拒绝未知参数（`ci-provision.mjs:132`、`ci-evidence.mjs:162` 抛 `unknown argument`） | PASS |
| 回环/端口校验（本经验原始根因 sites） | 新增 mjs 中 grep `127.0.0.1\|0.0.0.0\|loopback\|port` 无校验逻辑；该校验位于**本 change 未修改**的 `instance.mjs`/`provision.mjs` | 根因 sites 未被触碰 |

**观察项（既有行为，非本 change 引入，不立 ADJ）**：`run-selection.mjs:82` `try { event = JSON.parse(line); } catch { continue; }`

- 实证为**HEAD 既有代码**：`git show HEAD:…run-selection.mjs` 中同一行在 `:76`，且本 change 的 diff 中无任何 `JSON.parse`/`catch`/`continue` 的增删行。
- 与 AGENTS.md「解析失败必须硬失败」存在张力，但 SC-SEL-002 **明确要求未配置 expected 的既有行为逐字不变**，故本轮不得改动。
- 残留缺口需如实呈报：当前 `selections.json` 全部条目未设 `expected`，新的 fail-closed 对账路径不生效，生产路径仍走这条静默跳过的 legacy  totals 循环。新增的 `ci-evidence.mjs` 已硬失败，两者口径不一致属**规格预期的过渡状态**。

**判定：PASS（新增代码全部 fail-closed）；1 项既有行为观察项已留痕**

### EXP-2026-0004 — 真实资源测试清理只覆盖成功路径（severity medium）

触发条件：清理写在断言之后而非 finally，或清理依赖 setup 成功才拿到的句柄。

| 检查点 | 取证 | 判定 |
|---|---|---|
| `run-selection.mjs` 释放路径 | `finally` 三处：`:112`、`:155`（`dropDisposableDatabase`）、`:189`（`releaseInstance`，外套 try/catch） | PASS |
| CI 清理是否覆盖失败 | `ci.yml` 的 Drop database 步骤 `if: ${{ always() }}` | PASS |
| drop 是否仍走生产归属校验 | `provision.mjs:100-117`：drop 前**从服务器重读 marker**，不匹配则 `refusing to drop a database whose disposable marker does not match`；`finally` 关连接 | PASS |
| `ci-provision.mjs` down 的句柄校验 | `:104-111` 校验 JSON 对象且 `database`/`role`/`marker` 均为非空字符串，缺一即抛；无句柄时是成功 no-op | PASS |

**命中 2（继承缺口，本轮不修）**：`provision.mjs createDisposableDatabase` 部分失败不清理已建资源

- 实证：`CREATE ROLE` → `CREATE DATABASE` → `COMMENT ON DATABASE` → `COMMENT ON ROLE` 在同一个 try 内，`finally` **只 `admin.end()` 关连接，不 drop 已建资源**；第二段 `CREATE EXTENSION`/`ALTER SCHEMA` 同样只关连接。
- 后果链：若 `CREATE DATABASE` 成功后任一语句抛错 → 函数抛出 → `ci-provision.mjs:79-82` 捕获并 redact 后重抛 → **`HANDLE_ENV` 从未写入** → `down` 走 `:94-97` 的「no disposable handle; nothing to clean up」no-op → 遗留 role + database。
- 归属：`provision.mjs` **不在本 change 的 49 个文件内**（既有代码），新增的 `ci-provision.mjs` 复用它，故新 CI 入口继承了该缺口。
- 影响收敛（实证边界）：CI 中数据库位于 job 的 service container，job 结束整容器销毁；本地 `run-selection` 的 podman 实例在 `finally` 中 `releaseInstance` 销毁。故遗留被**限制在单次 job/实例生命周期内**，不跨运行累积。
- 处置：记为命中 + 已收敛影响，**不在本轮修改未申报范围的既有文件**，Gate 3 呈报待裁定。

**判定：新增代码 PASS；1 项继承缺口已记录并收敛影响**

### EXP-2026-0005 — 复制出的身份检查只测一个失败条件（severity low）

触发条件：同一校验函数在两个包各存一份，其中一份的测试只覆盖一个拒绝分支。

- **计数陷阱已排除**：`grep -c 't\.Run('` 两份文件各为 **2**，实读后确认是**循环驱动**，非只有 2 个用例。
- 实证两份文件（`server/cmd/server/` 与 `server/internal/governance/`，各 214 行）口径一致：
  - 条件表 **11 条**，且有硬断言 `if len(conditions) != 11 { t.Fatalf(…) }`，条件数退化即红；
  - 逐条 `t.Run(c.condition, …)`，`nonce-format` 再分 3 个子例（`nonce[:15]`、`strings.ToUpper(nonce)`、`""`）；
  - **双阳性对照**：真实 `testPool` 与回放 row 都必须被接受，确保拒绝来自被退化的条件而非 row source 坏掉；
  - `changedIdentityColumns` + `slices.Equal` 断言**只有目标列被退化**，杜绝「一次改多列」造成的假覆盖；
  - `role-name` 条件同时移动 `Role` 与 `SessionRole`，注释说明否则 session_user 比较会先拒绝、name 检查永不被触达；
  - 另有 `TestDisposableIdentityGateRefusesUnreadableIdentity` 覆盖读取失败分支；
  - 10 个条件无法真实构造（nonce 角色非超级用户、不能建角色），用 `identityRow` 实现 `pgx.Row` 回放，注释已申报该手法。
- **判定：PASS，且强于经验要求的最低口径（自身通过 / 畸形值 / 他人值 / 注释不符均有对应）。**

---

## 2. Skill C4 点名的其余类别

| 类别 | 取证 | 判定 |
|---|---|---|
| **锚定缺失** | 锚定等级 L4（按裁定 B 从 L3 升级），11 个锚点已逐一核实；`ci.py:1186-1222` 只比较 level；Gate 2 已按裁定重签，`phases.spec.confirmed_at` 未 stale | PASS |
| **Agent CP 失败** | run `7cd120df-d9d1-4f31-a9b5-e26b5a13606a`：18 个 command CP **18 通过 / 0 失败**，`tc-evidence.json` 实测 18 条全 `kind=command`/`result=pass`/18 个不同 TC，报告已生成。`verify` 自身 `EXIT_CODE=1` 源于 **REVIEW_PENDING**，非 CP 失败 | 命令 CP 无失败；**覆盖判定另计，见下** |
| **跨系统不一致** | canonical YAML ↔ `specs/*/spec.md` ↔ `test-plan.md` ↔ `CUSTOM.md` 三表 ↔ 实际代码已逐项核对（任务 #26/#27）；CUSTOM.md 列数与表头一致，5 行多余竖线全为已转义 `\|` | PASS |
| **证据覆盖结构不完整** | 同 run 的 `ci check-failures` 判 **0/22**，理由「缺少或重复必需 check（当前运行未完成）」。根因 `evidence.py:1033-1034` 要求 `len(checks) == len(plan["checks"])`，18 ≠ 22 → 整个 run 无效、覆盖归零 | **公开缺口，不报通过**（ADJ-040） |

---

## 3. 命中汇总与处置

| # | 经验 | 命中位置 | 性质 | 处置 |
|---|---|---|---|---|
| 1 | EXP-2026-0002 | `execution_control_reservation.go:88-96` 非锁定 `SELECT EXISTS` | 代码注释已主动申报的限制；SC-WSD-005 不要求并发 | 不修，与 ADJ-017/U3 裁定一致，Gate 3 呈报 |
| 2 | EXP-2026-0004 | `provision.mjs createDisposableDatabase` 部分失败不 drop | 既有文件（不在 49 内），新 CI 入口继承 | 不修，影响已被 job/实例销毁收敛，Gate 3 呈报待裁定 |

另有 1 项既有行为观察项（`run-selection.mjs:82` 静默跳过解析失败，HEAD 既有、SC-SEL-002 要求不变）与 1 项新发现 **ADJ-042**（parseArgs fail-open，见 `validation/c3-diff/README.md` §4.1）。

**未自行修改任何代码**：两项命中均涉及超出本 change 申报范围或用户已裁定留待后续的部分，按 U3「停下报告并由用户裁定」处理。

---

## 4. 未执行 / SKIPPED 项（如实标注，不报通过）

| 检查 | 状态 | 边界原因 |
|---|---|---|
| `make test` 全量 | **NOT EXECUTED** | `ensure-postgres.sh:71-72` 会 `docker compose up -d postgres` 连 localhost:5432 旧库，违反「只用 runner 自建一次性 podman 实例、不操作旧 multica-postgres 容器」 |
| `bash scripts/check.sh` | **NOT EXECUTED** | `check.sh:119`/`:129` 会启动 backend 与 web，属会打断在跑服务的动作，未获授权 |
| 4 个 Linux-only daemon 文件的编译与运行 | **SKIPPED（本机不可编译）** | `//go:build linux`，Windows 基线不编译；真实证明属 WSL AIFI-ISO 独立入口（ADJ-024 半句 UNCOVERED） |
| TC-CBE-005 真实 CI run | **SKIPPED** | 推送须单独授权并消耗私有库 Actions 额度（U5），未获授权 |
| TC-CCF-003 管理员 PAT | **SKIPPED** | 外部动作，凭据不可读取、不得创建或修改 |
| TC-TOR-004 WSL 半句 | **UNCOVERED** | ADJ-024，需 WSL AIFI-ISO 独立入口 |
| 4 个人工 TC 的 `agent confirm` | **未确认** | `evidence.py:1071` 固定写 `result=manual-pass`，确认即断言通过；前置未满足者一律不确认，不为凑覆盖伪造 |

**边界守住**：全程未读取或打印任何凭据；未连接 localhost:5432、未操作旧容器；一次性实例运行前后容器清单 diff 为 IDENTICAL，两个旧容器始终 Exited；未提交、未推送、未部署；对 stdd 仓写入次数 **0**；记录仓他人未提交改动未清理、未混入；**Gate 3 未推进**。