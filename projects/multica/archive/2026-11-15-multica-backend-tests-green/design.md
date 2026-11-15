# multica backend-tests 在 CI 变绿 - 技术设计

## Context

- CI job `backend-tests`（`.github/workflows/ci.yml`）在服务容器 `pgvector/pgvector:pg17` 上运行：`ci-provision.mjs up` 建一次性库与一次性角色（`NOSUPERUSER NOCREATEDB NOCREATEROLE`），`go run ./cmd/migrate up` 迁移，再 `test-go.sh --race --only regular --skip-regex "$(test-ownership.mjs skip-regex)"` 跑全包，最后 `ci-evidence.mjs` 对事件流做对账。
- `AIFI45_CI_ADMIN_URL`（服务容器的超级用户）只用于供给，不在测试步骤里作为 `DATABASE_URL`。
- 2026-11-15 的失败（run 43687569973，sha `b726f5131`）与取证（podman + 一次性库，已复现）归为三个根因，见 proposal 的 why.problem。取证中确认的关键事实：
  - bigm 用例用 `pg_statistic`，受限角色无权；`pg_stats` 在受限角色下可读，替换后用例通过。
  - 3 个 CREATE DATABASE 用例用管理员 DSN 通过；DATABASE_URL 不可达时它们 `SKIP` 且整包 `ok`。
  - `TestMTick003`：池上限 16 通过、4 挂起，7 个 goroutine 全在 `pgxpool.Acquire`。
  - `DownRoundTrip` 与 `handler.DeleteWorkspace` 并发 150 次中 31 次复现 `relation "cr_execution_notice" does not exist`。
- 现成资产：`selections.json` 已有 `governance-migration-roundtrip`（`^TestExecutionMigrationDownRoundTrip$`）；`run-selection.mjs` 自己用 podman 起一次性 Postgres 实例并逐 selection 建库；`test-ownership.json` 的 `owner` 字段是自由文本，`test-ownership.mjs check` 只校验条目指向真实 `func TestX(`；`ci-evidence.mjs` 的规则 3 在共享事件流里禁止出现被排除的测试。

## Decisions

### 1. bigm 用例改读 `pg_stats`（C1）

**方案**：`cmd/migrate/migrate_issue_properties_bigm_index_test.go` 的 `statisticsRowCount` 把 `pg_statistic s JOIN pg_class … JOIN pg_namespace …` 换成 `FROM pg_stats WHERE schemaname=$1 AND tablename=$2`。语义不变：表达式索引的统计在 `pg_stats` 里以索引名作 `tablename` 出现。

**为什么**：两个视图都是对统计的读，`pg_stats` 对表所有者可读；已在受限角色下实测通过。不放大角色权限。

**备选方案及排除原因**：给一次性库角色加 `pg_read_all_stats`——削弱最小权限设计，且只为一条测试。

### 2. 需要建库的 3 个用例归 `owner: ci-admin`，在 CI 里用管理员 DSN 单独跑，并由对账保证「真的通过」（C2）

**方案**：
- `test-ownership.json` 新增 3 条 `owner: "ci-admin"`：`./cmd/backfill_codex_usage_cache` 的 `TestExecuteBackfillUpdatesOnlyEligibleCodexRowsAndRebuildsRollup`，`./internal/taskusagebackfill` 的 `TestHook_DirectV034Upgrade`、`TestHook_FreshDatabaseStampsWatermarkOnly`。`entry` 写明 CI step 名，`reason` 写明「建临时库需 CREATEDB；一次性库角色按设计无此权限」。skip-regex 因此自动把它们排除出共享 run。
- `ci.yml` 在 `Test` 之后、`Reconcile the Go test evidence` 之前增加一步 `Run the admin-owned tests`：`DATABASE_URL: ${{ env.AIFI45_CI_ADMIN_URL }}`（step 级 env，仅此一步），`cd server && go test -json -count=1 -run '^(…三个名字…)$' ./cmd/backfill_codex_usage_cache ./internal/taskusagebackfill > "$RUNNER_TEMP/aifi45-admin-test.json"`，条件与 Reconcile 同。
- `ci-evidence.mjs` 新增导出函数 `reconcileAdminStream({ ndjson, entries })` 与 CLI 模式 `--admin-stream <file> --table <file>`：对每个 `owner === "ci-admin"` 的条目，要求事件流里该包该测试有且仅有一条 `Action: pass`（顶层测试），出现 `skip`、`fail` 或缺失均为问题；流本身不完整（未以换行结尾、解析失败、包无结论）同样失败，复用现有 `parseStream`。该模式在 ci.yml 里于 `Reconcile` 同一位置再调用一次。

**为什么**：这是「没跑」与「通过」的区分点——管理员 DSN 不可达时三个用例会 SKIP 而整包 `ok`，现有规则只在共享流里管「不该出现」，管不到「该出现而没出现」。`-run` 清单写在 ci.yml 里，漏列会被对账判为缺失，所以无需再新增子命令生成它。

**备选方案及排除原因**：
- 给一次性库角色加 `CREATEDB`：全 run 放大权限；用户已裁定不做。
- 改写这 3 个用例用 schema 隔离：它们要在建库后从旧版本升级，隔离到 schema 会改变被测对象。
- `owner: independent`（只登记、CI 不跑）：这三个能在 CI 跑，退为人工等于放弃一道有效检查。

### 3. `withRunLock`：等锁时不占池连接，用 try-lock 加退避（C3）

**方案**：在 `internal/governance` 新增 `func (r *Runner) withRunLock(ctx context.Context, runID string, fn func() error) error`：
1. 循环：`conn := r.pool.Acquire(ctx)` → `SELECT pg_try_advisory_lock(hashtextextended($1, 0))`；拿到则进入 3；没拿到则**释放连接**，`select` 等 50ms 或 `ctx.Done()`（取消返回 `ctx.Err()`），再来一次。
2. 取锁失败路径上从不持有连接超过一次查询。
3. 拿到锁后持有该连接直到 `fn` 返回，`defer` 用 `context.Background()` 在同一连接上 `pg_advisory_unlock` 再 `Release`（与原先一致）。
4. 三处调用点原样替换：`runner.go:732` 附近的 `Reconcile`、`runner_code.go:49` 的 `reconcileCode`、`runner_requirement.go:48` 的 `reconcileRequirement`；`fn` 里保留原先「加锁后重新读取活动 run」的逻辑与后续调用。

**为什么**：死锁的机制是「N 个同 run 的唤醒各占一个池连接阻塞在 `pg_advisory_lock`，持锁者再需要一个连接而池已空」。try-lock 加退避把「等待」挪到不占连接的状态，持锁者只需 1 个等锁连接加 1 个工作连接，N 个同 run 唤醒不再耗尽池。语义不变：同一 run 仍严格串行，取消仍能打断等待，锁仍随持有连接释放（连接异常断开时 PG 自动释放会话锁）。

**备选方案及排除原因**：
- 把 `fn` 里的查询也放到锁连接上：三处的 `reconcileLocked` 等调用链广泛使用 `r.pool`，改动面大，风险高，远超一个测试失败所需。
- 进程内按 run 的 mutex 加 `pg_advisory_lock`：多一份状态（带引用计数的 map）；try-lock 不需要。
- 调大 `MaxConns`：只是把触发条件推远，不是修复。
- 取锁失败时直接跳过（不重试）：丢唤醒。周期扫描会补，但这会把语义从「串行执行」变成「丢弃」，不在本 change 范围内。

**限定**：保证只覆盖「同一 run 的并发唤醒」。「N 个不同 run 同时持锁且各自再取连接」的情形不在保证内，有证据再另立（proposal constraints）。

### 4. `upsertRequirementRun` 不改（对 proposal C3「四处」的缩减，见文末差异表 D1）

**方案**：`runner_requirement_entry.go:171` 的 `pg_advisory_lock` 不迁移。

**为什么**：该函数持锁后在**同一条连接上** `conn.Begin`，整个临界区都走该事务（已核对 155–296 行无 `r.pool` 调用），持锁者不再需要第二条连接，不存在上述死锁；它也不是「唤醒」入口。改它是改一个没有缺陷的路径。

### 5. 测试池固定为 4：让「最小 CI 池」在任何机器上都是同一形状（C3 的检查）

**方案**：`internal/governance/crsync_test.go` 的 `TestMain` 把 `pgxpool.New(ctx, dbURL)` 换成 `ParseConfig` + `cfg.MaxConns = 4` + `NewWithConfig`。`TestMTick003` 原样保留。

**为什么**：CI 2–4 核时池上限 = max(4, 核数) = 4，本地 16 核则是 16，所以只在 CI 暴露。固定为 4 让本地与 CI 同形，且测试自己不再依赖机器核数。

**备选方案及排除原因**：用 DSN 参数 `pool_max_conns`：同一个 DSN 也被 `pgx.Connect` 用于 lease 会话，未知参数会被当作运行时参数发给服务器导致失败（已实测）。

**风险**：包内其他测试在 4 个连接下是否仍通过，BUILD 阶段用全包在 4 个连接下跑一遍确认；有失败则逐个定性，不降低池上限。

### 6. `DownRoundTrip` 登记为 `independent`，复用现有 selection（C4，对 proposal「新增 selection」的缩减，见文末差异表 D2）

**方案**：`test-ownership.json` 新增一条：`package ./internal/governance`，`test TestExecutionMigrationDownRoundTrip`，`owner independent`，`entry` 指向现有的 `run-selection.mjs --selections selections.json --only governance-migration-roundtrip`，`reason` 写明「执行 down 脚本删除 cr_execution_* 表并统计 agent_task_queue 行数，与共享库里并行的其他包互相干扰（150 次并发复现 31 次）」。`selections.json` 对该条不改（新增条目见 6b）。

**为什么**：selection 已存在，只缺登记；与现有三个 `channel-migration-*` 同口径。

### 6b. 为 G1、G3 各补一个 selection，作为「受限角色 + 池 4」的可重复检查（见文末差异表 D3）

**方案**：`selections.json` 新增 3 条（默认 `migrated` 状态，自带一次性库与受限角色）：
- `bigm-restricted-role`：`./cmd/migrate`，`^TestIssuePropertiesBigramIndexBuildsOnlyWherePGBigmExists$`
- `governance-mtick003`：`./internal/governance`，`^TestMTick003$`
- `governance-run-lock`：`./internal/governance`，`^(TestWithRunLockSerialisesSameRun|TestWithRunLockCancelReleasesWaiter)$`

**为什么**：这三个检查必须在受限角色的一次性库上跑才有意义，而 STDD 取证只能用命令；`run-selection.mjs --only` 是仓内已有的、与 CI 同款身份的入口（先例：`rec-001`、`governance-wsd-lock`），不新增机制。

**备选方案及排除原因**：直接在 CP 里写 `go test`——需要先有一次性库和 nonce，等于重写 `run-selection.mjs`。

### 7. claim deadline 用例先定性，不预设修（C5）

**方案**：C1–C4 落地后，在 podman 里用 `--cpus=2` 的 Go 容器对同一一次性库重复运行 `TestClaimTasksByRuntime_PartialSuccessFitsClientDeadlines` 至少 20 次：优先带 `-race`（在容器里装 gcc；若 race 在该镜像不可用则不带并如实写明）。记录次数、失败次数、失败时的错误全文。能复现→按根因修（在同一 change 内）；不能复现→写入 `design-adjustments.md`（含上述数据与「CI 单例失败未复现」），不改代码、不 skip。执行部分交 balanced 子代理，结论由主会话审阅。

### 8. 登记与顺序

`CUSTOM.md` 按台账行模板登记本 change 的 multica 定制（`ci.yml` 新增一步、`ci-evidence.mjs` 新模式、`withRunLock` 及三处调用点、`crsync_test.go`、测试与 ownership 登记），并说明它们各自的上游回合并时的保留要点；CRLF 保持。顺序：C1→C2→C4→C3（含池固定）→C5→C6；每组先 RED 再 GREEN。

## Architecture

```
CI job backend-tests
  provision(one-time role) → migrate → Test (restricted role, skip-regex 排除 independent 与 ci-admin 的 4 个)
                                     → Run the admin-owned tests (admin DSN，仅 3 个用例，-json 流)
                                     → ci-evidence --stream        (共享流：必需包、skip 声明、排除确实生效)
                                     → ci-evidence --admin-stream  (管理员流：3 个各一条 pass)
withRunLock(runID, fn):  [Acquire → try-lock → 失败则 Release+退避] 循环 → 持锁 Acquire 直到 fn 结束
```

## Risks / Trade-offs

| 风险 | 缓解措施 |
|------|----------|
| `withRunLock` 在生产 Runner 路径：退避或重试有误可能丢唤醒或饥饿 | 保持三处原语义；`TestMTick003` @池 4 覆盖并发唤醒；`TestWithRunLock` 覆盖互斥、释放、取消；周期扫描本就是兜底 |
| 管理员流对账出错漏判 SKIP | 用已知好样本与三种坏样本（skip、缺失、fail）先自测，再接入 CI |
| 池固定为 4 暴露包内其他测试的问题 | BUILD 阶段全包 @4 跑一遍，逐个定性 |
| `DownRoundTrip` 改为 independent 后 CI 不再运行 | 与 `channel-migration-*` 同口径；test-report 如实写明，不声称 CI 在跑 |
| try-lock 退避使唤醒延迟增加 50ms 级 | 用户已于 2026-11-15 接受（A11） |

## 与 proposal 的差异（Gate 2 一并审阅）

| 编号 | proposal 的写法 | 本设计的写法 | 原因 |
|------|----------------|-------------|------|
| D1 | C3：4 处 `pg_advisory_lock` 抽成共用 | 只改 3 处，`upsertRequirementRun` 保留 | 该处持锁后在同一连接上开事务，无第二连接需求，无死锁；改它是改无缺陷路径 |
| D2 | C4：登记 independent 并在 `selections.json` 新增 selection | 只登记；复用已有的 `governance-migration-roundtrip` | selection 已存在 |
| D3 | 未提 | `selections.json` 新增 3 条（`bigm-restricted-role`、`governance-mtick003`、`governance-run-lock`） | G1、G3 的检查必须在受限角色一次性库上跑，`run-selection.mjs --only` 是仓内已有的同款入口 |
| D4 | 未提 | `TestMain` 池上限固定为 4（用 `ParseConfig` + `MaxConns`） | 让 CI 的最小池形状在任何机器上相同；DSN 参数方式已实测会被当作运行时参数拒绝 |

