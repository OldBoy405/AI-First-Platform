# 2026-11-15-multica-backend-tests-green — 阶段上下文

## Phase 1: UNDERSTAND（completed 2026-11-15T17:33:29）
- Gate 1 由用户确认；T2（claim deadline 定性）保留，其余按专业建议。

## Phase 2: SPEC（completed 2026-11-15T17:57:46）
- Gate 2 由用户确认；design 与 proposal 的差异 D1–D4 一并审阅。
- 修复等待 push：三个 capability 的 code/agent spec、test-plan 的 11 项检查。

## Phase 3: BUILD（in_progress，2026-11-15 起）
- 切片规划：`slices.md` 6 个执行切片 + 真实 CI 收尾；`tasks.md` 同步。
- 切片 1（C1 bigm）：RED `permission denied for table pg_statistic (SQLSTATE 42501)`（selection `bigm-restricted-role`）；GREEN 后 `PASS bigm-restricted-role pass=1 fail=0 skip=0`。TC-BTO-001。
- 切片 2（归属表 4 条）：`test ownership OK: 8 entry(ies)`，skip 正则含 4 个新测试名；`PASS governance-migration-roundtrip pass=1 fail=0 skip=0`。TC-BTO-002/003。
- 切片 3（管理员流对账）：RED = `reconcileAdminStream` 导出缺失；GREEN 后 6 个 `TCCAO001` 用例 `pass 6 fail 0`，整文件 28 pass；本地管理员 PG 上 3 个 ci-admin 测试各一条 pass、对账 `admin evidence OK: 3 ci-admin test(s) passed`。TC-CAO-001/002。ci.yml 新增 step 已接线（YAML 校验、CRLF 保留）。
- 切片 4（运行锁）：RED = `withRunLock` 未定义；池 4 下 TestMTick003 在 120s 内 exit=1/pass=0（另见 ADJ-BTO-1）。GREEN 后 `PASS governance-run-lock pass=2 fail=0 skip=0`、`PASS governance-mtick003 pass=1 fail=0 skip=0`；`governance` 全包 @4 `2264 pass / 0 fail / 2 skip`。TC-RRL-001/002/003。
- 设计偏离：ADJ-BTO-1（启动扫描持连接），见 `pending-adjustments.md`。
- 切片 5（claim 定性）：balanced 子代理在 golang:1.26.9-alpine + `taskset -c 0,1`/`GOMAXPROCS=2` + `-race` + 一次性库里跑 20 次，20/20 PASS（包耗时 18.237–19.180s），无法复现；`-cpus=2` rootless 不可用，偏离记入 `design-adjustments.md`。TC-BTO-004。
- 切片 6（CUSTOM.md）：新增 #341（M31）、#342（M4），模块索引/计数/CR 索引一致，CRLF 保持。TC-BTO-006。
- 质量验证（C1–C7）：三路评审完成并处置（无 critical）；选定 run `bto-20261115-1`，6 个命令 CP 全过；人工确认 TC-CAO-002、TC-RRL-003、TC-BTO-004、TC-BTO-006；`stdd ci check-failures` 8 通过 / 1 错误（恰为 TC-BTO-005）；test-report 已生成。
- 待完成：TC-BTO-005 真实 CI（阻塞于推送授权）→ 补入同一 run → Gate 3 由用户确认。
- 2026-11-15：用户逐文件授权 14 个文件；已提交 `8c097e524` 并推送 origin/main（`b726f5131..8c097e524`）；CI run `43725057558` 正在运行。`make test` 因本机无 compose provider 且 dev 库不满足 disposable 身份门而无法作为本地全量证据，已如实记入 test-report。
- 2026-11-15：第一轮 CI 红，发现并修复两处（ADJ-BTO-2 全局队列计数、ADJ-BTO-3 无测试包与 7 个环境跳过）；用户补充授权 5 个文件后提交 `294d793a9` 并推送。第二轮 CI（`43727687773`）因 GitHub Actions 账单/额度限制未启动，所有 job skipped。
- 新选定 run `bto-20261115-2`（HEAD `294d793a9`，0 个输入需注意）：6 个命令 CP 全过；人工确认 TC-CAO-002、TC-RRL-003、TC-BTO-004、TC-BTO-006；`check-failures` 10/11（缺 TC-BTO-005）。
- 2026-11-15：本地 CI-equivalent 执行完毕（admin step 与两种对账通过，四个关键用例 PASS；其余失败均为容器环境原因，见 test-report §9）。用户同意「将 TC-BTO-005 标为 not_applicable，以上述替代证据收口」；test-plan 已改、Gate 2 已按该原文重签；新 run `bto-20261115-3` 6 个命令 CP 全过、4 个人工确认完成，`check-failures` 9/9、TC 11/11（10 required + 1 N/A）。待 Gate 3 用户确认。
