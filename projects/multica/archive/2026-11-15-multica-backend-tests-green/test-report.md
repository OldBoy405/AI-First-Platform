# 2026-11-15-multica-backend-tests-green — 测试报告

- 业务仓：`../multica`（trunk `main`）；改前 HEAD `b726f5131`，本 change 提交 `8c097e524`、`294d793a9`（2026-11-15 推送 origin/main）；记录仓：本工作区。
- 真实 CI：第一轮 run `43725057558`（提交 `8c097e524`）backend-tests 失败，暴露两个新问题（见 §8）；第二轮 run `43727687773`（提交 `294d793a9`）因 GitHub Actions 账单/额度限制未启动（所有 job skipped，`changes` job 报 billing failure）。
- 选定 run：`validation/runs/bto-20261115-3/`（`agent-verification-report.md`、`tc-evidence.json`）；冻结输入为 HEAD `294d793a9`（工作区干净，0 个输入需注意）。
- 2026-11-15 用户同意将 TC-BTO-005（真实 CI）标为 `not_applicable`，以上述替代证据收口；Gate 2 已按该确认原文重签。

## 1. TC 覆盖（11 项计划）

| TC | 检查点 | 结果 | 证据 |
|----|--------|------|------|
| TC-BTO-001 | CP-BTO-001 | PASS | `run-selection --only bigm-restricted-role`：`PASS ... pass=1 fail=0 skip=0`；RED 为 `permission denied for table pg_statistic (SQLSTATE 42501)` |
| TC-BTO-002 | CP-BTO-002 | PASS | `test-ownership check` → `8 entry(ies)`；`skip-regex` 含 4 个新名；node 套件 180/180 |
| TC-BTO-003 | CP-BTO-003 | PASS | `PASS governance-migration-roundtrip pass=1 fail=0 skip=0` |
| TC-CAO-001 | CP-CAO-001 | PASS | `node --test --test-name-pattern TCCAO001` → `pass 6 fail 0`；整文件 28 pass |
| TC-CAO-002 | 人工确认 | PASS（本地 + 首轮 CI） | 管理员 PG：3 条顶层 pass；`admin evidence OK`；第一轮 CI run 43725057558 的 admin step 与对账均为 success |
| TC-RRL-001 | CP-RRL-001 | PASS | 池 4 `PASS governance-mtick003 pass=1 fail=0 skip=0`；改前 RED：120s 超时、pass=0 |
| TC-RRL-002 | CP-RRL-002 | PASS | `PASS governance-run-lock pass=2 fail=0 skip=0` |
| TC-RRL-003 | 人工确认 | PASS | 三处调用 `withRunLock`；仅 `runner_requirement_entry.go:171` 保留 `pg_advisory_lock(` 且无 diff |
| TC-BTO-004 | 人工确认 | PASS（无法复现） | 20/20 PASS，`-race`，2 核上限；见 `design-adjustments.md` |
| TC-BTO-005 | 真实 CI | **N/A（用户同意）** | GitHub Actions 账单/额度阻塞（run 43727687773 未启动）；替代证据：第一轮真实 CI run 43725057558（除已修复的 reservation 外全绿）+ 本地 CI-equivalent（四个关键用例、admin step、两种对账通过）。详见 §8 |
| TC-BTO-006 | 人工确认 | PASS | `CUSTOM.md` #341/#342；1119 CRLF / 0 裸 LF；ci.yml 1109 CRLF / 0 裸 LF |

**覆盖：11/11（10 个 required 全 PASS + 1 个 not_applicable）。** `stdd ci check-failures --run bto-20261115-3`：9 项通过、0 错误、0 跳过。

## 2. 覆盖率

证据计划声明 `not_applicable`：被测对象为 Go、Node 与 CI 配置，覆盖率采集目前只支持 pytest-cov；项目配置 `quality.coverage.enabled=false`。检查 (j) 通过，无覆盖保证。

## 3. 切片验证

| # | 内容 | TC | 新测试 | 结果 |
|---|------|----|--------|------|
| 1 | bigm 改读 `pg_stats` + selection | TC-BTO-001 | 0（改既有测试 + 新增 selection） | done |
| 2 | 归属表 4 条 | TC-BTO-002/003 | 0 | done |
| 3 | 管理员流对账 + ci.yml | TC-CAO-001/002 | 6 | done |
| 4 | `withRunLock` + 池 4 + selections | TC-RRL-001/002/003 | 2 | done |
| 5 | claim 定性 | TC-BTO-004 | 0（定性切片） | done |
| 6 | CUSTOM.md 台账 | TC-BTO-006 | 0 | done |
| 7 | 质量验证 + 真实 CI | TC-BTO-005 | — | 完成（TC-BTO-005 经用户同意 N/A） |

未发生第三轮修复。

## 4. 执行过的检查

| 检查 | 结果 |
|------|------|
| `go vet ./internal/governance ./cmd/migrate ./internal/handler` | 通过 |
| `go build ./...` | 通过 |
| `governance` 全包 @池 4（CI 同款 skip-regex、共享一次性库） | `2264 pass / 0 fail / 2 skip`，exit 0；skip 为 `TestWindowsJobCapability`、`TestReconcileLiveGitHub`（后者已声明） |
| `node --test scripts/aifi45-disposable/*.test.mjs` | 180 pass / 0 fail |
| `bash scripts/test-go.test.sh` | PASS |
| `pnpm lint` | 0 errors（21 个既有 warning） |
| `pnpm typecheck` | 10/10 tasks 成功 |
| 本地管理员 PG（pgvector:pg17）3 个 ci-admin 测试 + 对账 | 3/3 pass，对账 exit 0 |
| C5 重复运行 | 20/20 PASS，`-race`，包耗时 18.237–19.180s |
| `make test`（`quality.test`） | **未执行成功**：`make test` 在 `scripts/ensure-postgres.sh` 处依赖 `docker compose`，本机没有 compose provider（`docker-compose`/`podman-compose` 均不在 PATH），exit 125。即使有 compose，dev 库 `multica` 也不满足 `governance` TestMain 的 disposable 身份门（`crsync_test.go:106-129` 要求库/角色/marker 与 nonce 匹配）。全量套件的权威证据改用第一轮真实 CI 与本地 CI-equivalent（见 §8/§9） |

## 5. C1 评审与处置

- code（strong）、test_config（balanced）、docs_skills（economy）三路均返回；未产生 critical。
- 已修复：启动扫描的取消传播、admin CLI usage、锁测试的「回调真的跑了 / 等待确实发生」、坏样本精确断言、台账计数/索引/日期/粘连行、ci.yml 注释归位。
- 已记录不改：锁键与活动 run 变化（改前同样存在）、解锁无超时（设计明确与原先一致）、pg_bigm 分支未被绿样本覆盖、`ci-scope` 未覆盖新增两步、管理端测试的 DSN 回退、CP-BTO-002 未含原 4 条、`governance-run-lock` 无 `expected` 清单（`selection.mjs` 不接受 Go 1.27 的 `OutputType`，实测 `EVENT_INVALID` 后回退）、受审文档的文档级瑕疵。详见 `design-adjustments.md` C1 评审判定。

## 6. 失败模式检查（C4 语义项）

| ID | 结论 | 依据 |
|----|------|------|
| (a) hallucination | PASS | CLI 文件存在检查通过；报告中的结果均附原始输出/日志路径 |
| (b) scope_creep | PASS（有记录） | `git status` 的 14 个文件全部对应 tasks/slices；启动扫描修复是 ADJ-BTO-1，已记录 |
| (c) cascading_errors | PASS | 共享流对账规则未变（28 pass）；selection 决策未变；单点修复未扩散到未声明路径 |
| (d) context_loss | PASS | CLI TC-ID 唯一（11）；spec/agent/test-plan 的 ID 与计划一致 |
| (e) tool_misuse | PASS | 一律用仓内既有入口（run-selection、node --test、go test）；未用 `--cpus` 等被拒参数 |
| (f) runtime_deviation | PASS | CLI THEN/SHALL 检查通过；池 4 行为有 selection 证据 |
| (g) pipeline_break | PASS | CLI AND 计数与 6 个切片的验证证据均通过 |
| (h) content_quality | PASS | tasks/slices/phase-context/design-adjustments/test-report 齐备；命令与日志路径可复核 |
| (i) instruction_decay | PASS（有注记） | 本轮跨多个切片与评审，流程步骤仍按 build.md 执行；C2 的 `make test` 缺口如实列出 |
| (j) coverage_vacuum | PASS（豁免） | 计划明确 `not_applicable`；CLI 通过 |
| (k) contract_gap | PASS | CLI 契约一致（3 capabilities） |
| (l) anchor_missing | PASS | non-critical change，无需锚定 |
| (m) agent_cp_failure | PASS（有局限） | 各 CP 断言含可区分观测值（pass 6 / 8 entry / skip=0）；TC-RRL-002 的 `pass=2` 未被 CP 断言，已记录 |
| (n) cross_system_mismatch | PASS | 本地 20/20 与 CI 失败不矛盾：CI 错误是响应后 `no rows`，非时序；结论与日志一致 |

## 7. 已知问题与未完成项

1. **TC-BTO-005 真实 CI 未执行（用户同意 N/A）**：GitHub Actions 账单/额度阻塞；替代证据为第一轮真实 CI + 本地 CI-equivalent（见 §8）。影响：本地/首轮 CI 之外的完整 GitHub runner 结果仍未验证；报告不声称 backend-tests 已在真实 CI 变绿。
2. **锁键与活动 run 变化**（C1 code HIGH）：改前同样存在，不在本 change 承诺内；建议后续 change 单独修。
3. **解锁无超时**：沿袭原实现；连接异常断开时由 PG 释放会话锁。
4. **pg_bigm 索引分支未执行**：镜像无 pg_bigm，`statisticsRowCount` 的索引关系统计路径未被绿样本覆盖。
5. **`governance-run-lock` 少一个测试仍是 PASS**：`selection.mjs` 不接受 Go 1.27 `-json` 的 `OutputType`，`expected` 清单回退；如需强制，另立 change 改 `selection.mjs`。
6. **`ci-scope.test.mjs` 未覆盖新增两步**：步骤顺序/条件无自动化断言。
7. **`make test` 未执行成功**：本机无 compose provider；且 dev 库不满足 governance 的 disposable 身份门。见 §4；全量套件见 §8/§9。
8. **受审文档的文档级瑕疵**：见 `design-adjustments.md` C1 第 7 条；修 test-plan/design 会使 Gate 2 失效，留待 DELIVER 时决定是否重审。

## 8. 真实 CI 第一轮（run 43725057558，提交 8c097e524）

backend-tests job `132845145487` 失败，`Test` step 只挂一个用例：

- `TestChannelFoundationReservation/control_reservation_not_runnable`：`reservation must not enqueue anything, queue holds 2 rows`。根因是它断言全库 `agent_task_queue` 为空，而共享 run 里其它包在并行插入任务。**修复**：计数限定到该用例自己的 CR（经 `pipeline_node_run` / `pipeline_run` 关联 `workspace_id`+`cr_id`）；ADJ-BTO-2。

`Reconcile the Go test evidence` 另有 37 个问题（非测试失败，但让 job 红）：

- 14 个无测试文件的包被规则 4 判为「no package-level conclusion」，并被规则 2 判为不可声明的包级 skip（28 条）；**修复**：包级 `skip` 作为终止结论、无测试事件的包不再要求 allowed-skips；ADJ-BTO-3。
- 7 个真实环境跳过未声明（pg_bigm 缺失 2 条、CLI known-limitation、DSH app-data 2 个子测试、macOS 路径子测试、Windows-only `TestIsDriveRoot`、RE2 rules 不可定位）；**修复**：按 CI 日志原文补入 `allowed-skips`（4 → 11 条）。

管理员 step（`Run the admin-owned tests`）与管理员流对账在本轮 CI 均为 **success**。

修复后的本地验证：node 套件 182/182；`go test ./internal/governance/... ./internal/handler/...` 共享库并行包时 governance 全绿（handler 有一个与本 change 无关的本地时序失败 `TestClaimTasksByRuntime_ResponsePrecedesRecoveryNotifications/ws`，同一用例在本轮 CI 通过）。

**收口决定（2026-11-15）**：用户确认原文「同意将 TC-BTO-005 标为 not_applicable，以上述替代证据收口」。`test-plan.md` 的 TC-BTO-005 已改为 `not_applicable` 并写明原因；Gate 2 已按该原文重签；新 run `bto-20261115-3` 覆盖 11/11（10 required + 1 N/A），`check-failures` 9/9 通过。

## 9. 本地 CI-equivalent（2026-11-15）

在原 GitHub job 无法启动后，按 backend-tests job 的原始步骤在本机执行（原始日志 `%TEMP%/bto-ci-job/`：`status`、`aifi45-go-test.json`、`shared-reconcile.log`、`admin-reconcile.log`、`test-step.err`）。

环境：pgvector:pg17 + redis:7-alpine 一次性实例；测试在 golang:1.26.9-alpine 容器内（gcc 15.2.0、`-race`、GOMAXPROCS=4、GOFLAGS=-count=1）；tools 按 `.github/aifirst-tools-pin`（`e52b8081`）导出到临时目录；仓库为 HEAD `294d793a9`。

| 步骤 | 结果 |
|---|---|
| provision / migrate / `test-go.test.sh` | 通过 |
| `test-go.sh --race --only regular --skip-regex` | exit 1：31 个顶层失败（含子测试 81），**全部为容器环境原因** |
| 共享流对账 | exit 1：36 个问题，均为本机环境跳过；`no package-level conclusion` = 0、包级 skip 问题 = 0（修复已生效） |
| 管理员 step + 管理员流对账 | 均 exit 0（3/3 pass） |
| `test-ownership check` | exit 0 |

**本 change 关键用例均 PASS**：`TestWithRunLockSerialisesSameRun`、`TestWithRunLockCancelReleasesWaiter`、`TestMTick003`、`TestChannelFoundationReservation`。

环境失败分类（均不是本 change 代码）：9 个顶层因容器无 `node`（crctl 互操作/crosslang/生成器）；7 个因容器以 root 运行，daemon 拒绝 `bypassPermissions`；1 个因无 `pwsh`；其余为容器内进程树/端口/权限限制。这些包在第一轮真实 CI 中均通过。

**结论**：本地 CI-equivalent 不能作为“整 job 绿”的替代；它验证的是本 change 的 delta（对账修复、reservation 计数、锁测试、admin 接线）。完整 runner 形状的结论仍缺，已如实记在 §7。
