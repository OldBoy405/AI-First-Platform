# 2026-11-17-execution-admission-simplification 任务清单

> 模式 thorough；长程 full_auto（预授权见 pending-adjustments.md PA-001）。切片见 slices.md。
> 所有 Go 代码注释英文；改动按 CUSTOM.md《台账行模板》以 `STDD 2026-11-17-execution-admission-simplification（原生 STDD，非 CR）` 追溯，`#N` 只增不改（当前最大 #344）。

## 0. 前置核实（P0，切片 S1 之前）

- [x] 0.1 一次性测试环境机制核实（build-env.md，主会话抽查 instance/provision/run-selection、Makefile、stack/scenario-stub）：run-selection 自建 pgvector pg17 容器（--pull=never、tmpfs、随机端口/密码、TTL 3600s）、每 selection 独立库与受限角色、注入 DATABASE_URL/AIFI45_DISPOSABLE(_NONCE)、`go test <pkg> -run <re> -count=1 -json`；make test 走 .env + docker compose，**不得用于现网**；全量回归参照 CI：ci-provision + test-go.sh --race --only regular + skip 对账
- [x] 0.2 CUSTOM-LEDGER 追溯格式接受 `STDD <change>（原生 STDD，非 CR）`（#336/#337 先例）；当前最大 #344，新增从 #345 起；归属 M 模块（AIFI-45 授权执行）
- [ ] 0.3 selections.baseline.json / test-ownership.json / ci-evidence 对账规则核实：改名、删除、新增测试须同步哪些文件（S3 前完成）

## 1. authorized-runner — 默认契约与可省略字段（P0，切片 S1）

- [x] 1.1 `governance.DefaultExecutionContract()` + router 装配三情形（TC-RUN-103 / CP-RUN-103：`run-default-contract-wiring` 3 PASS）
- [x] 1.2 签发请求三字段可省略、显式不等仍 409、填充先于冻结（TC-RUN-102 / CP-RUN-102：`run-default-contract-issue` 18 PASS，含签发后 head 读回 200）
- [x] 1.3 签发入口边界在默认契约下复跑（TC-RUN-104 / CP-RUN-104：`run-authz-boundary` 4 PASS）
- [x] 1.4 驱动 `--default-contract`（config/run/stack/stub-flow/scenario-stub/crctl-stage）+ Node 测试；隔离栈 architecture-stub 默认契约模式全部 PASS、exit 0、清理 remaining=0（TC-RUN-105 / CP-RUN-105）
- [x] 1.5 `TestTC_RUN_003` 改写为头判定（TC-RUN-101 / CP-RUN-101：`run-003` 1 PASS）——属 S3（依赖 #2.1）

## 2. admission-task-binding — 准入只看头（P0）

- [x] 2.1 S3：`DecideAdmission` 只保留头查询；删 `TaskID`、两个 WAIT 常量；`decideUnderHeadLock` 去掉 taskID；全仓调用点迁移（EXP-0009）；`go build ./... && go vet ./...`
- [x] 2.2 S3：`markNodeAdmitted`、`passHumanApprovalNode` 去掉准入专用 source 任务读取；入队归因保留（TC-ATB-104 / CP-ATB-104：`ath-source-task` 3 PASS）
- [x] 2.3 S3：判定表 + 四动作矩阵测试，含跨 workspace/CR 头两个独立变体（TC-ATB-101 / CP-ATB-101：`ath-head-matrix` 16 PASS）
- [x] 2.4 S3：既有 ATB_001–010、admission gate/enqueue/human-gate、CE、lock/revoke 测试改写；selections.json 同步（TC-ATB-102/103/105：`ath-lock-revoke` 8 / `ath-discovery` 6 / `m005` 20 PASS）
- [x] 2.5 S3：requirement 形态流转测试（TC-RUN-106 / CP-RUN-106：`run-requirement-shape` 1 PASS）
- [x] 2.6 S3：覆盖矩阵逐格核对写入 test-report（TC-ATB-106，manual，run b267076a agent confirm；含前后计数与取代条款）

## 3. execution-wait-visibility — 等待可见（P0/P1）

- [x] 3.1 S4：`progressOf` 新文件 + 全状态表测试（TC-EWV-001 / CP-EWV-001：`ewv-progress` 25 PASS）
- [x] 3.2 S4：requirement resume / architecture start 回执加 progress；读失败省略（TC-EWV-002 / CP-EWV-002：`ewv-receipt` 6 PASS）
- [x] 3.3 S4：GET pipeline-runs/{runID} 成员级路由 + 权限测试（TC-EWV-003 / CP-EWV-003：`ewv-route` 8 PASS）
- [x] 3.4 S4：CLI `status` 与 table 两列（TC-EWV-004 / CP-EWV-004：cmd/multica 直跑 7 PASS，含既有 resume 用例）

## 4. 台账与登记（P0，随切片即时登记，不积压）

- [ ] 4.1 每个切片完成后在 CUSTOM-LEDGER 追加 `#N` 行（位置/改动/原因追溯/日期/合并注意+验证命令），源码留 `// AIFIRST:` 标记；模块索引、CR 索引与正文一致
- [ ] 4.2 每切片 `stdd state <change> --complete-slice <id> --tc-coverage M/K --new-tests N`；tasks.md 勾选；phase-context.md 追加

## 5. 质量验证（P0，Part C）

- [x] 5.1 C1 三路并行评审（code=strong、test_config=balanced、docs_skills=economy，按 config models）
- [x] 5.2 C2 全量：curated selections 全 PASS；CI 等价 regular 全量已跑并归因（平台性/共享库，非本变更）；覆盖率 not_applicable
- [x] 5.3 C2 同次执行证据：run b267076a，agent verify --run + ci check-failures --run（16/16）；TC-ATB-106 agent confirm（含矩阵逐格计数）
- [x] 5.4 C3 逐文件 diff 审查（仅本变更文件）
- [x] 5.5 C4 (a)–(n) 全部检查，注明所用 run
- [x] 5.6 C5 经验 EXP-2026-0011；C6 design-adjustments.md；C7 test-report.md
- [ ] 5.7 Gate 3 确认框 → 等用户确认（不代签）
