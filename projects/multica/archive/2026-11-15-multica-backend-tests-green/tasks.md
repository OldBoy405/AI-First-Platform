# 2026-11-15-multica-backend-tests-green 任务清单

> 交付物在业务仓 `../multica`（trunk `main`，改前 clean，HEAD `b726f5131`）。记录仓为本工作区。
> 顺序沿用 design 的 C1→C2→C4→C3→C5→C6；C2 的归属表部分与 C4 合并为一个切片（同一文件，避免二次编辑）。

## 1. backend-tests-ownership：bigm 用例改读 `pg_stats`（P0）
- [x] 1.1 RED：在 `scripts/aifi45-disposable/selections.json` 新增 `bigm-restricted-role`（`./cmd/migrate`，`^TestIssuePropertiesBigramIndexBuildsOnlyWherePGBigmExists$`），`run-selection.mjs --only` 实测在受限角色下失败于 `pg_statistic` 权限
- [x] 1.2 GREEN：`server/cmd/migrate/migrate_issue_properties_bigm_index_test.go` 的 `statisticsRowCount` 改查 `pg_stats`（`FROM pg_stats WHERE schemaname=$1 AND tablename=$2`），语义不变
- [x] 1.3 验证：`run-selection.mjs --only bigm-restricted-role` 退出 0、`PASS bigm-restricted-role `、`skip=0`（TC-BTO-001）

## 2. backend-tests-ownership：归属表登记 4 条（P0）
- [x] 2.1 `test-ownership.json` 新增 3 条 `owner: ci-admin`（`./cmd/backfill_codex_usage_cache` 的 `TestExecuteBackfillUpdatesOnlyEligibleCodexRowsAndRebuildsRollup`；`./internal/taskusagebackfill` 的 `TestHook_DirectV034Upgrade`、`TestHook_FreshDatabaseStampsWatermarkOnly`），`entry` 指向 ci.yml 的新 step
- [x] 2.2 新增 1 条 `owner: independent`（`./internal/governance` 的 `TestExecutionMigrationDownRoundTrip`），`entry` 指向既有 `governance-migration-roundtrip` selection
- [x] 2.3 验证：`test-ownership.mjs check` → `8 entry(ies)`；`skip-regex` 含 4 个新测试名；原 4 条 independent 与 allowed-skips 保留（TC-BTO-002）
- [x] 2.4 验证：`run-selection.mjs --only governance-migration-roundtrip` 退出 0、`skip=0`（TC-BTO-003；该用例此后不再由 CI 共享 run 运行）

## 3. ci-admin-test-ownership：管理员流对账（P0）
- [x] 3.1 RED：`ci-evidence.test.mjs` 追加 6 个用例（标题含 `TCCAO001`）：好样本 + 5 类坏样本（skip / 缺失 / fail / 流不完整 / 重复 pass），先因 `reconcileAdminStream` 不存在而失败
- [x] 3.2 GREEN：`ci-evidence.mjs` 新增导出 `reconcileAdminStream({ ndjson, entries })` 与 CLI 模式 `--admin-stream <file> --table <file>`，复用 `parseStream`；每条 `owner === "ci-admin"` 的测试要求恰好一条顶层 `pass`
- [x] 3.3 `.github/workflows/ci.yml` 在 `Test` 之后、`Reconcile the Go test evidence` 之前新增 `Run the admin-owned tests`（step 级 `DATABASE_URL: ${{ env.AIFI45_CI_ADMIN_URL }}`，`go test -json -count=1 -run '^(三个名字)$' ./cmd/backfill_codex_usage_cache ./internal/taskusagebackfill > "$RUNNER_TEMP/aifi45-admin-test.json"`），并在同一位置调用管理员流对账
- [x] 3.4 验证：`node --test scripts/aifi45-disposable/ci-evidence.test.mjs` 全绿、`pass 6 fail 0`（TC-CAO-001）
- [x] 3.5 验证（人工）：本地 podman 管理员 PG 上跑该 step 的命令 + 对账，3 条各一条 pass、退出 0（TC-CAO-002；本地结果不替代真实 CI）

## 4. governance-runner-run-lock：`withRunLock` 与池固定（P0）
- [x] 4.1 RED：新增 `TestWithRunLockSerialisesSameRun`、`TestWithRunLockCancelReleasesWaiter`（`internal/governance`），因 `withRunLock` 不存在而失败
- [x] 4.2 RED：`crsync_test.go` 的 `TestMain` 改为 `pgxpool.ParseConfig` + `MaxConns = 4` + `NewWithConfig`；同条件跑既有 `TestMTick003` 复现挂起（池 4 红样本已于 2026-11-15 实测）
- [x] 4.3 GREEN：新增 `withRunLock`（`pg_try_advisory_lock` + 失败释放连接 + 50ms 退避，取消返回 `ctx.Err()`，`defer` 在同一连接上 `pg_advisory_unlock` 后 `Release`），替换 `runner.go:732`、`runner_code.go:49`、`runner_requirement.go:48` 三处；`runner_requirement_entry.go:171` 不改
- [x] 4.4 `selections.json` 新增 `governance-mtick003`、`governance-run-lock`（并已在 1.1 加 `bigm-restricted-role`）
- [x] 4.5 验证：`run-selection.mjs --only governance-mtick003` 与 `--only governance-run-lock` 均退出 0、`skip=0`（TC-RRL-001、TC-RRL-002）
- [x] 4.6 验证：`pg_advisory_lock(` 全文搜索确认三处已替换、entry 文件无改动；`go test ./internal/governance/...` 在池 4 下全包通过（TC-RRL-003 + 池固定风险；启动扫描的额外修复见 ADJ-BTO-1）

## 5. claim deadline 用例定性（P1，执行交 balanced 子代理、主会话验收）
- [x] 5.1 在 `--cpus=2` 的 Go 容器 + 一次性库上重复运行 `TestClaimTasksByRuntime_PartialSuccessFitsClientDeadlines` ≥20 次，优先带 `-race`；记录次数、失败数、错误全文、是否带 race（TC-BTO-004）
- [x] 5.2 结论写入 `design-adjustments.md`（能复现→按根因修；不能→如实记录并说明依据）；不 skip、不改被测行为

## 6. CUSTOM.md 台账（P1）
- [x] 6.1 按台账行模板登记本 change 触达的 multica 定制（ci.yml step、ci-evidence 管理员模式、`withRunLock` 及三处调用点、`crsync_test.go` 池 4、selections/ownership 登记），写合并保留要点
- [x] 6.2 验证：登记行存在；文件 CRLF、无裸 LF（TC-BTO-006）

## 7. 质量验证与交付（P0，C1–C7）
- [x] 7.1 C1 三路并行评审（code=strong、test_config=balanced、docs_skills=economy）并逐条处置
- [x] 7.2 C2 全量质量检查（Go 包测试、node 测试、lint/typecheck、证据计划 run）
- [x] 7.3 C3 逐文件 diff 审查；C4 失败模式清单逐项执行
- [x] 7.4 C5 经验记录；C6 汇总 `design-adjustments.md`；C7 生成 `test-report.md`
- [ ] 7.5 Gate 3 由用户确认（不代签）；`stdd gate approve ... --run <run-id>` 后才可进 DELIVER

## 8. 真实 CI（P0，阻塞于推送授权）
- [x] 8.1 真实 CI（TC-BTO-005）：修复已提交 `8c097e524`、`294d793a9`；第二轮因 GitHub Actions 账单/额度未启动（run 43727687773）。2026-11-15 用户同意标为 `not_applicable`，以第一轮 CI + 本地 CI-equivalent 收口（见 test-report §8/§9）；真实 CI 未执行

<!--
优先级说明：
- P0：阻塞性任务，完成前无法进入下一阶段
- P1：重要任务，应在当前阶段完成
- P2：可延后到后续版本的任务
-->
