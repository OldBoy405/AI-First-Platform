# multica backend-tests 在 CI 变绿，并让「是否真的跑了」可核对

<!-- source_hash: 8ca3143406f9889a -->
<!-- generated_at: 2026-11-15T17:16:50.257579 -->
<!-- canonical: canonical/proposals/2026-11-15-multica-backend-tests-green.yaml -->

## Why

multica 的 CI job backend-tests 自 2026-11-09 起每次真正执行都失败；近 60 次 run 从未通过，只有被路径过滤跳过的 run 是绿的。
此前它被 CI 令牌失效（401）掩盖，根本没跑起来；令牌恢复后（2026-11-15）暴露出 8 个失败用例（run 43687569973，sha b726f5131）。
2026-11-15 的取证（podman + 一次性库，复现过）显示它们是 3 个互相独立的根因，而不是 8 个孤立缺陷：
A. 测试需要的权限超出一次性库角色（NOSUPERUSER NOCREATEDB）。bigm 用例读 pg_statistic，受限角色无权；改读 pg_stats 后受限角色实测通过。
   另 3 个用例（backfill_codex_usage_cache、taskusagebackfill 两例）用 CREATE DATABASE 建临时库，受限角色失败、管理员 DSN 实测通过。
   这 3 个用例在 DATABASE_URL 不可达时会 SKIP 而整包仍 ok，即「没跑」和「通过」在事件流里无法区分。
B. governance 的 Runner 在四处用 pg_advisory_lock 阻塞等锁并一直占着一个池连接。同一 run 的 N 个并发唤醒占满连接池后，锁持有者拿不到第二个连接，永久挂起。
   TestMTick003 实测：池上限 16 通过、池上限 4 挂起（7 个 goroutine 全卡在 pgxpool Acquire）。生产池上限默认 25，CI runner 2–4 核即上限 4，故只在 CI 暴露。
C. TestExecutionMigrationDownRoundTrip 执行 down 脚本删除 cr_execution_* 表并统计 agent_task_queue 行数，而 go test 的各包并行共用同一个库。
   并发跑它与 handler.DeleteWorkspace 用例，150 次里 31 次复现 CI 的原错误 relation "cr_execution_notice" does not exist；agent_task_queue 82→83 是反方向的同一类干扰。
另有 1 个用例（claim deadline 的 http/recovery_0s）单跑通过、CI 报错被截断，无法归入以上三类，需先定性。


## What Changes

- bigm 用例（cmd/migrate）把 pg_statistic 查询改为 pg_stats，使受限角色可读；不给一次性库角色加 CREATEDB / pg_read_all_stats。
- 3 个需要建库的用例在 test-ownership.json 登记 owner=ci-admin，从受限 run 排除；CI 新增一步用 AIFI45_CI_ADMIN_URL 单独跑它们，并由 ci-evidence.mjs 新增一个小模式断言每个都有一条 pass（不得 skip、不得缺失）。
- governance 四处 pg_advisory_lock（runner.go、runner_code.go、runner_requirement.go、runner_requirement_entry.go）抽成共用 withRunLock：改用 pg_try_advisory_lock 加退避重试，等待期间释放连接，使同一 run 的并发唤醒最多占用 1 个池连接。TestMTick003 原样保留，用池上限 4 运行。
- TestExecutionMigrationDownRoundTrip 登记为 independent，并在 selections.json 增加一条 selection（与 channel-migration-* 同口径），不再与其他包共库并行。
- claim deadline 用例（http/recovery_0s）先定性：C1–C4 落地后，在与 CI 同条件（2 核、-race）下重复运行至少 20 次；能复现则按根因修，复现不了则写入 design-adjustments.md，不修也不 skip。
- CUSTOM.md 按台账行模板登记本 change 对 multica 的定制（含 server/internal/governance 的 withRunLock）。

### New Capabilities

- **ci-admin-test-ownership**：有权限需求的测试有显式的归属（ci-admin），并有「每个必须 PASS」的事件流核对，防止静默 SKIP。

### Modified Capabilities

- **governance-runner-run-lock**：同一 run 的并发唤醒不再在持有池连接的状态下阻塞等锁；行为语义（同一 run 内串行化、重复唤醒只派发一次）不变。
- **backend-tests-ownership**：test-ownership.json / selections.json 对破坏性迁移测试与需要管理员的测试的归属口径。

## Success Criteria

- [ ] bigm 用例（TestIssuePropertiesBigramIndexBuildsOnlyWherePGBigmExists）在受限角色的一次性库上通过。
- [ ] 3 个 ci-admin 用例在管理员 step 的事件流里各有一条 pass；把其中任一个改成 skip 或让 DSN 不可达，该 step 失败。
- [ ] TestMTick003 在测试库池上限 4 时通过；同一测试在本 change 之前的代码上池上限 4 时挂起（已有失败样本）。
- [ ] TestExecutionMigrationDownRoundTrip 不出现在共享 run 的事件流里；单独经 run-selection 运行通过。
- [ ] 落地后的真实 CI run 中，backend-tests 不再出现原 7 个失败（4 个权限、DownRoundTrip、TestMTick003 超时、DeleteWorkspace）；claim deadline 用例有定性记录（复现次数与结论）。
- [ ] CUSTOM.md 登记本 change 的 multica 定制，且为 CRLF、无裸 LF。
