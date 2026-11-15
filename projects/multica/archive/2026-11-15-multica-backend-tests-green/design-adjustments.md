# 2026-11-15-multica-backend-tests-green — 设计调整汇总

> 来源：BUILD 期间的 `pending-adjustments.md`（ADJ-BTO-1）+ C5 定性运行。受审文档（proposal/design/spec/test-plan）的字节未改；本文件记录与 `design.md` 的差异，供 Gate 3 复核。

## ADJ-BTO-1：启动扫描持连接（设计只覆盖了锁等待的一半）

- `design.md` Decisions 3 把 TestMTick003 在池 4 的挂起归因于阻塞式 `pg_advisory_lock` 占着池连接等锁，要求只替换三处调用点。
- BUILD 实测：`withRunLock` 落地后，`governance-mtick003` @池 4 仍挂起（`GOFLAGS=-timeout=120s`，exit=1、pass=0）。
- 完整根因：`StartupScan` / `StartupScanRequirement` 在 `pool.Query` 游标打开时调用对应 reconcile，6 个并发扫描各占 1 条连接，池 4 被占满后每个扫描器再要第二条连接 → 池耗尽。锁等待是同一挂起的另一半原因。
- 调整：两个扫描器先收集目标、`rows.Close()` 后逐个 reconcile；不放宽池上限、不改接口或语义。
- 结果：`governance-mtick003` `PASS pass=1 fail=0 skip=0`；`governance` 全包 @4 `2264 pass / 0 fail / 2 skip`。
- 影响：`design.md` 的根因描述不完整（代码已按实际修复）；`spec` 的 SC-RRL-001 不受影响。

## C5 执行方式的两处偏离（claim deadline 定性）

1. **`--cpus=2` 无法在 rootless podman 上设置**（cgroup cpu/cpuset 控制器未向用户 session 委派；`--cpus` / `--cpuset-cpus` 均被 crun 拒绝）。改用 `taskset -c 0,1` + `GOMAXPROCS=2` 近似 2 核上限。这是对 `design.md` Decisions 7 与 TC-BTO-004 预置条件的偏离。
2. **执行者**：按 `design.md` 交 balanced 子代理执行（选模 `GB-JP/deepseek-flash:max`），原始日志与逐次结果留在 `C:/Users/GOBAO/AppData/Local/Temp/c5-post/`；结论由主会话直接核对 `logs/summary.txt`、`logs/run-*.log` 与 race 证据后写入。

## ADJ-BTO-2：`TestChannelFoundationReservation` 的全局队列计数在共享库里失败（2026-11-15，真实 CI 发现）

- 真实 CI run `43725057558`（提交 `8c097e524`）的 `Test` step 里，`TestChannelFoundationReservation/control_reservation_not_runnable` 失败：`reservation must not enqueue anything, queue holds 2 rows`。
- 原因：该子测试用 `SELECT count(*) FROM agent_task_queue` 断言全库为空；共享 run 里 `handler` 等包并行插入任务，计数不为 0。与 `DownRoundTrip` 同类（全局状态假设），不是本次产品代码回归；本地单跑（无并行包）通过。
- 调整：把计数限定到这个用例自己的 CR——`agent_task_queue` 经 `pipeline_node_run`/`pipeline_run` 关联 `workspace_id` + `cr_id`。仍覆盖原注释的威胁（同一 CR 下换一个 id 入队），不再把其他包的合法任务当失败。该文件不在原 14 个文件内，需另行授权提交。
- 验证：`go test ./internal/governance/... ./internal/handler/...`（共享一次性库、并行包）governance 全绿；CI 待下一次 run 确认。

## ADJ-BTO-3：`ci-evidence` 把「无测试文件包」误判为问题，且 7 个环境跳过未声明（2026-11-15，真实 CI 发现）

- 同一 CI run 的 `Reconcile the Go test evidence` 报 37 个问题：
  - 14 个包（如 `internal/agentconfig`、`pkg/db/generated`）的 `go test -json` 只发出 `start` + `output "? pkg [no test files]"` + 包级 `skip`，没有 pass/fail 结论 → 规则 4 报「no package-level conclusion」，规则 2 报「package-level skip cannot be declared」（28 个）。
  - 7 个真实环境跳过未在 `allowed-skips` 声明：`cmd/migrate` 两个 pg_bigm 用例、`internal/cli TestCLIConfig_UnknownFieldsArePreserved`、`internal/daemon` 的 DSH app-data 两个子测试与 macOS 路径子测试、`TestIsDriveRoot`（Windows-only）、`pkg/gitguard TestRealRulesLoadUnderRE2`。
- 调整：
  - `ci-evidence.mjs`：把包级 `skip` 当作终止结论；对「没有任何测试事件」的包不再要求 allowed-skips。仍保留：必需包若只有包级 skip → 规则 1 失败；有测试事件却出现包级 skip → 仍报错。补两个 node 用例。
  - `test-ownership.json`：按 CI 日志里的实际 skip 原文补 7 条 `allowed-skips`（含原因）。总数 4 → 11，`entries` 仍为 8。
- 验证：node 套件 182/182；`test-ownership check` 通过。CI 待下一次 run 确认。

## C5 结果

运行窗口：2026-11-15 22:08–22:18（+08:00）。被测文件 `server/internal/handler/daemon_batch_claim_deadline_test.go` 的 blob 与 HEAD 相同（`server/internal/handler` 工作区零修改）。原始日志：`C:/Users/GOBAO/AppData/Local/Temp/c5-post/logs/run-1.log … run-20.log`、逐次摘要 `logs/summary.txt`、race 证据 `logs/race-evidence.txt`。

| 项 | 值 |
|----|----|
| 运行次数 | 20（每次独立 `go test -count=1`） |
| 失败次数 | 0；每次 4 个子用例全 PASS |
| 是否带 `-race` | 是。`go version -m` 显示 `build -race=true`、`CGO_ENABLED=1`；`go tool nm` 含 15 个 `runtime.race*` 符号；`//go:build race` 探针在 `-race` 下命中 |
| 包耗时 min/max/中位 | 18.237s / 19.180s / 18.333s |
| 响应时间 | `daemon_batch_claim_deadline_test.go:181` ws 3.785–3.883s、http 3.764–3.789s；`elapsed >= 5s` 断言未触发 |
| 环境 | golang:1.26.9-alpine，gcc 15.2.0，`taskset -c 0,1` + `GOMAXPROCS=2`（`nproc`=2）；pgvector:pg17 一次性库 + 受限角色 |
| 结论 | **无法复现**（20/20 通过）。不修代码、不 skip；按 SC-BTO-004 记录依据 |

### CI 侧观察（不是本 change 的结论）

既有 CI 失败（run `43687569973`）里该子用例的 elapsed 为 3.78s（已通过 5s 断言），失败发生在响应之后读取任务时：`GetAgentTask(A)` 返回 `err=no rows in result set`。该窗口内同库还有 governance 用例在运行，指向跨包共享库干扰而非本用例的时序问题；此判断来自 2026-11-15 的日志分析，**本次 20 次运行不能证明或推翻它**。真实结论留给 TC-BTO-005（推送后的真实 CI）。

## C1 评审判定

已修复（不影响 Gate 2 受审字节）：
- 代码：`StartupScan`/`StartupScanRequirement` 在逐目标 reconcile 前检查 `ctx.Err()`，取消仍向上传播；`ci-evidence.mjs` 的 usage 文案覆盖两种模式。
- 测试：`withRunLock` 两个用例加 `calls` 计数与 `AcquireCount` 等待，能区分「第二个调用真的跑了」与「只是启动了」；5 个坏样本改为断言完整 problem 行。
- 台账：M31 计数改 20、M4 位置列补 `crsync_test.go`、CR 行补日期/M30、拆开粘连的 #339 行、ci.yml 注释归位。

记录为已知问题/不再改（附理由）：
1. **锁键与活动 run 变化**（code review HIGH）：`reconcile` 先读 run A、锁 A，回调内重读可能得到 B 并 reconcile B；此行为与改前逐字相同（`design.md` Decisions 3「语义不变」），不是本 change 引入。建议后续 change 用「锁后重读 ID 不变，否则重取锁」单独修。
2. **解锁无超时**：`context.Background()` 上的 `pg_advisory_unlock` 无超时、错误忽略；改前同样如此，`design.md` 明确「与原先一致」。卡住时连接断开会由 PG 释放会话锁；未在本 change 扩大。
3. **pg_bigm 分支未被绿样本覆盖**：CI/一次性镜像无 pg_bigm，bigm 用例走的是「索引跳过、统计仍刷新」路径；索引关系统计读 `pg_stats` 的口径未在真实 pg_bigm 上执行。受限角色的 RED（`pg_statistic` 权限）与 GREEN 已成立；索引分支属证据局限，记入 test-report。
4. **`ci-scope.test.mjs` 未覆盖新增两步**：顺序/条件缺少自动化断言；TC-CAO-002（人工）与 TC-BTO-005（真实 CI）覆盖结果，顺序回归无保护。
5. **管理端测试的 DSN 回退**：两个测试包在 `DATABASE_URL` 为空时回退到本地超管 DSN；CI 每次都从 provision 得到非空 `DATABASE_URL`，若删掉 step env 会以受限角色失败（不是静默跳过），故未加额外断言。
6. **CP-BTO-002 的 grep 未含原有 4 条与 allowed-skips**：这两项由 `test-ownership.test.mjs` 断言；改 CP 会使 Gate 2 失效，故不改受审 agent spec。
7. **`governance-run-lock` 缺少 `expected` 清单**：尝试为 selection 增加 `expected`（两个测试缺一即红），但 `selection.mjs` 的允许事件键不含 Go 1.27 `-json` 新增的 `OutputType`，会报 `EVENT_INVALID`（实测）；改它超出本 change 范围，已回退。selection 仍要求 `skip=0`/`fail=0`/`pass>0`，但两个测试缺一仍为 PASS，这一限制记入 test-report。
7. **受审文档的文档级瑕疵**（不修，避免 Gate 2 失效）：test-plan 引用不存在的 `REQ-CAO-002`（应 `REQ-CAO-001`/SC-CAO-002）、test-plan 多处状态列仍为「待 BUILD」、design 的「三种坏样本」「4 个」「5 个 selection」与实际 5 类/8 条/4 个不一致、实际新增两步且 step 带 `-timeout=10m`。这些不影响实现与断言，作为 DELIVER 时重审或后续修订的输入。
8. **`code-structure-delta.md` 只列 Go/JS**：`ci.yml`、`selections.json`、`test-ownership.json`、`CUSTOM.md` 不在其中，文件清单以 `git status` 为准。
