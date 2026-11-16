# pending-adjustments — 2026-11-16-multica-execution-evidence-closure

本文件记录 BUILD 中的技术阻塞与事实更正，不改变已审 proposal/design/spec/test-plan，未触发 Gate 重审。长程预授权不覆盖安装编译器、共享服务、提交/push/CI/部署。

## BLOCK-MEC-01 race 前置不满足（resolved 2026-11-16）

- 原承诺：test-plan TC-MEC-001 / CP-MEC-001 要求 `GOFLAGS='-race -count=1'` 的真实一次性库四测试 selection。
- 实际：`go test -race ./internal/governance -run '^TestWithRunLockSerialisesSameRun$' -count=1` exit 2，报 `go: -race requires cgo; enable cgo by setting CGO_ENABLED=1`；本机 `CGO_ENABLED=0`，PATH 无 gcc。失败发生在测试/数据库之前，不是产品回归 RED。
- 影响：MEC-05–08 未实施；三个恢复入口锁后身份守卫与 `TestReconcileRunIdentity` 未写；`governance-run-lock` 已含该 expected，真实 selection 现在必失败关闭。
- 处置：未安装依赖、未改执行环境、未用非 race 替代、未建一次性库。需要用户授权的环境变更（可用 cgo 编译器）或改由具备该前置的环境执行；不降低 race 保证。
- **解除（2026-11-16，用户原话「授权 cgo/race 环境，以及独立的发布/CI」后）**：上述「未实施/未写」描述的是切片1当时的阻塞状态，现已不成立。已建立 mingw-w64 gcc 16.2.0 ＋ `CGO_ENABLED=1`，`go test -race -c` 编译通过；MEC-05–08 全部落码，三个锁后身份守卫（runner.go/runner_code.go/runner_requirement.go）与 `TestReconcileRunIdentity` 已实现。CP-MEC-001 经既有 run-selection 一次性库 `-race -count=1` 执行：PASS governance-run-lock pass=4 fail=0 skip=0、NODE_EXIT=0、复跑两次一致、完整四项 expected matched。CLI 已登记切片2 tc_coverage=1/1、new_tests=1、verified_at=2026-11-16T02:55:41.207176。race 保证未降低；本地仅证明锁/身份/池4 这一 selection，governance 全量与 backend 回归仍由切片4真实 CI 权威验证。原阻塞条目原样保留供追溯。

## BLOCK-MEC-02 真实 CI 与发布授权缺失（授权已取得；CI 已触发但被账单阻塞 2026-11-16）

- 原承诺：TC-MEC-003 required manual，最终业务 SHA 的真实 CI 核对六测试、真实 rules、backend/admin/对账/合同。
- 实际：本轮授权不含提交/push/触发 CI；未触发任何真实 CI。前驱 `2026-11-15-multica-backend-tests-green` 的 TC-BTO-005 not_applicable 是用户对该前驱的单独验收，不继承到本 change。
- 影响：SC-MEC-006 未验证；仓外部署 rules 副本未覆盖。
- 处置：保持未验证，待独立授权与最终 SHA；不以本地组/fixture/旧绿灯替代。
- **授权更新（2026-11-16，用户原话「授权 cgo/race 环境，以及独立的发布/CI」）**：上文「本轮授权不含提交/push/触发 CI」已被该独立授权取代——本 change 的提交、push、触发真实 CI 现已获授权（MEC-12 完成）。授权不等于结果：SC-MEC-006 仍未验证，须待最终业务 SHA 的真实 CI 实际执行并核对六测试、真实 rules.json 日志、backend/admin/对账步与两个生成 --check 后方可收口；若账单/凭据/`AIFIRST_TOOLS_READ_TOKEN` 阻塞，如实记未验证，不制造运行回执、不继承旧 N/A。仓外部署 rules 副本仍未覆盖。required manual（TC-MEC-003）仍须用户原话确认，AI 不代签。原阻塞条目原样保留供追溯。
- **CI 实际执行（2026-11-16，已提交并 push 后触发）**：业务提交 `f8a23564a0b33ffb36cb535de27d4b515447e255`（13 文件 +430/-24，仅本 change），push `294d793a9..f8a23564a main->main` 成功。真实 CI run **43752944966**（https://github.com/OldBoy405/AI-First-multica/actions/runs/43752944966 ，workflow CI，event push，headSha=f8a23564a，createdAt 2026-11-15T19:31:59Z=本地 2026-11-16T03:31:59+08:00）conclusion=**failure**。**根因＝GitHub 托管 runner 无法分配（账单/额度），非代码失败**：`changes` job `runner_id=0`、`runner_name=""`、`runner_group_name=""`、`labels=["ubuntu-latest"]`、`steps=[]`、2 秒内 failure；`backend`/`frontend` 门控 job 同样 `steps=[]` failure；`backend-tests`、`transitions-contract-check`、`frontend-*`、`sqlc-check` 等全部 **skipped**（从未执行）；`gh run view --log-failed` 报 `log not found: 132930712183`。ci.yml:9-10 台账 #113 已记载私有库免费额度 2000 min/月、实测需 3652 min/月。近期 run 模式佐证额度耗尽：916f57318 于 06:33Z success，其后 b726f5131/8c097e524/294d793a9/f8a23564a 自 06:54Z 起全部 instant-failure。**后果**：TC-MEC-003 六个固定测试、`TestProposedSnapshotReadShapes` 的真实 rules.json 日志、backend Test/对账/admin 步、两个生成 --check **均未执行**；SC-MEC-006 **未验证（账单阻塞）**。这不是绿灯、不是代码回归、也不继承前驱 N/A。**处置**：账单/额度属用户侧外部状态，AI 无权修改支付或额度、不以本地组/fixture 替代真实 CI；保留实际原因，待用户解除额度后对同一最终 SHA 重跑 CI 再核对，或由用户决定 TC-MEC-003 的验收处置。required manual 与 Gate 3 仍须用户原话确认，AI 不代签。
- **用户裁定延期（2026-11-16，原话「修订计划延期 TC-MEC-003」）**：账单/额度短期无法恢复，用户明确裁定本轮把 TC-MEC-003 必需证据延期为 not_applicable（接受风险），先收口其余已验证项。已按 revision-rules 一轮同步受审文档（proposal/ci-backend-environment spec/design/test-plan，agent spec 未变）并重审 Gate 1+2（用户原话「确认重签Gate 1+2」，Gate 1 10:23:55 / Gate 2 10:25:47）；旧证据在新 run `0ccb7130-dbe0-4c0c-b7f4-28aeca9a38a6` 重跑，两命令 CP 真实重通过。**延期不是豁免/绿灯**：SC-MEC-006 权威验证仍未完成，reason 如实保留账单阻塞，额度恢复后对最终 SHA 另行验证；不继承前驱 N/A，非用户裁定的自动 N/A 仍禁止。CLI 机械覆盖 4/4 含 not_applicable，报告/Gate 3 显式标延期未验证。上文「待用户决定验收处置」已由本裁定收口，原阻塞条目原样保留供追溯。

## NOTE-MEC-01 第四数口径未决（open，按用户指示）

- `packages/` 第四数没有获确认测量口径；本轮不测量、不沿用历史 314。CUSTOM 现行说明与测量行已写明未决。TC-MEC-004 人工确认前不登记切片3。
- **更新（2026-11-16）**：TC-MEC-004 已经用户原话「执行 confirm 并继续后续流程」确认（run 0ccb7130），切片3 已 CLI 登记 done（tc 1/1、new_tests 0、verified_at 2026-11-16T11:01:56.826748）。第四数口径仍未决，待用户取；前三数 629/1722/789 经交付树 f8a23564a 实测逐位一致。

## NOTE-MEC-02 CUSTOM 事实更正与既有形状（recorded）

- 当前索引中前驱 backend-tests-green 行由“BUILD/Gate3未过”更正为已归档（Gate3 2026-11-15T23:37:06，业务提交 `294d793a91c8f1dce2f97a549b41cf468e562b1a`）；历史正文与归档文件未改。
- 新增 #343 与测量行；测量行已并入表格。CRLF 保持（1124 CRLF/0 裸 LF）。既有 #338 行未转义竖线数为 8，与 HEAD 相同；既有索引合并行问题未顺手修，避免范围外改动。
- **切片3复登更新（2026-11-16，MEC-09/10）**：上文 1124 是切片1当时的快照。切片2锁身份守卫落码后已在 M4 追加 #344、索引/表头 29→30、CR 索引 #343–#344、新测量行 629/1722/789，并为 #343 追加带日期后续指针；当前 CRLF 1126/0 裸 LF，`git diff --check` 通过。历史正文、稳定编号与既有形状未改。