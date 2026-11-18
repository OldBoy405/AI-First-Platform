# Phase Context - SPEC

## 确认与阶段状态

- Change：2026-11-17-execution-admission-simplification；业务仓 multica，记录项目 projects/multica，模式 thorough（复杂度 12，score_confidence=preliminary）。
- Gate 1 经用户原话「确认Gate 1」确认（2026-11-17T22:53:06）。Gate 2 经用户原话「请你裁定的 6 项：采纳你的建议。确认。」确认，CLI 回执时间 2026-11-17T23:29:53。SPEC completed；BUILD pending，进入前按 Skill 选择执行模式。
- Gate 确认不授权 Git 提交、push、部署、重启、对 DAYA-5 的授权或恢复、对现网 `multica-postgres` 或现网 daemon 的任何写入或连接。

## 用户对 Gate 2 六项待确认的裁定（采纳建议）

1. D3：有签名密钥的部署默认启用授权、binding、consumption 等端点——接受。
2. D6：新增 `GET /api/workspaces/{ws}/pipeline-runs/{runID}`，成员级可读——接受。
3. D2：run 缺 `source_task_id` 时，节点置 passed 与人工门不再返回 `AUTHORITY_MISMATCH`；入队路径仍严格——接受。
4. daemon strict 路径依赖（crctl、node、`MULTICA_CONTROLLED_SHELL_RULES`）不在本变更内；成功标准 #8 若因此失败，停下回来请用户裁定，不在本变更里放宽 daemon。
5. Phase 3 需要一次性数据库实例（`run-selection.mjs` 自建 podman 实例）与 `scripts/aifi45-real-run` 驱动（自建隔离栈）——用户采纳该建议；具体实例、命令与范围在 Step 8 的授权清单里逐项列出，不触碰现网库与现网 daemon。
6. 成功标准第 8 条的证据拆分：TC-RUN-106（requirement 形态，DB 集成）+ TC-RUN-105（architecture stub，真实 server+daemon+crctl）。**这是对提案措辞的偏离**，两者合起来不等于一次 requirement 的全真实验证；不另加 requirement 驱动场景。

## 已锁定的关键决策

- D1 `DecideAdmission` 只保留头查询：无头 `HEAD_UNAVAILABLE`、非 approve `HEAD_REJECTED`、其余 `ADMITTED`；删去消耗回执与 effect 两步，删 `AdmissionRequest.TaskID`、`WAIT_CONSUMPTION`、`WAIT_TRUSTED_T_COMMIT` 常量。头锁序不变，仍写“线性化于撤销，不是原子”。
- D2 删除准入专用的 `source_task_id` 读取；入队归因与其 `RunnerErrAuthorityMismatch` 保持。不动 5 张旧表的写路径与 `VerifyTrustedVerdictEffect`；历史 `detail.runner.admission` 原样透传。
- D3 新增 `governance.DefaultExecutionContract()`；`router.go` 里有显式 manifest 用 manifest，无 manifest 且有签名服务装默认契约，无签名服务则功能关闭（503）。不改 loader 与 `main.go` 的两个 flag。
- D4 请求体三个契约字段可省略或空，给出则必须等于部署契约，否则 409 `EXECUTION_CONTRACT_MISMATCH`；填充发生在构造签名 payload 与冻结请求之前。
- D5 新增只读 `progressOf(runID)`（`internal/governance/pipeline_progress.go`），状态为 completed / failed / cancelled / waiting_human / in_flight / waiting / idle；`waiting` 仅在前沿节点无活动任务且 `runner.wait_reason` 非空时采信，残留 runner 标记不采信。
- D6 requirement resume 与 architecture start 回执新增 `progress`，`run_id`、`changed` 不变；新增 GET 路由与 `multica cr pipeline status --run`。
- D7 测试矩阵：受保护动作 × {无头, 有效头, 叫停, 跨范围头, 幂等}；既有“头指向其他 workspace/CR”的 Runner 准入用例不存在，须新增，不得靠改写冒充。

## 用户关注点与证据边界

- 本项目不以防恶意任务为目标；要求用尽可能少且职责清晰的检查支撑有限且可验证的保证，不逐异常补兜底。
- 3 个 capability，12 个 Requirement、28 个 Scenario（高 18、中 10、低 0），16 个 TC（P0 13、P1 3），15 个 required 命令/ 1 个 manual 检查（TC-ATB-106 覆盖矩阵人工核对）。
- `validate`、`canon verify`、`agent verify --dry-run` 通过；`ci check-failures` 的 (l) 为 Non-critical 免锚定；执行证据 0/16 是预期（尚未 BUILD）。
- SPEC 阶段未运行任何 DB 类测试、未改 multica 代码、未触碰现网。
- 默认 digest 与 tools 侧是否一致仅静态推断，TC-RUN-105 是第一个实施切片，不一致则停下复核 D3/D4。
- selection 名称、`--default-contract` 选项、`selections.json` 改动均为计划值，Phase 3 调整须经设计调整记录同步 agent spec。
- `CUSTOM-LEDGER.md` 相对 HEAD 已有他人未提交改动，不在证据计划 inputs 内；只做定点追加新 `#N` 行，Phase 3 前先核对变更标识格式是否接受 STDD change 标识，不接受则停下确认，不编造 CR 身份。
- multica 工作树有大量无关未提交改动（pi agent、chat、`task.go`、`protocol/messages.go` 等）；实施与提交前逐文件列清单，仅含本变更文件。

## 产出物

- design.md、test-plan.md（含同次执行证据计划）。
- canonical/proposals/2026-11-17-execution-admission-simplification.yaml。
- canonical/specs/code/：admission-task-binding.yaml、authorized-runner.yaml、execution-wait-visibility.yaml。
- canonical/specs/agent/：同名三份。
- Gate 2 由 CLI 生成 specs/<capability>/spec.md 三份 Human View，不手改；`.stdd.yaml` 的 Gate 与阶段记录由 CLI 更新，不手改、不代签 Gate 3。

## 被取代的基线条款（交付时人工原位合并）

见 design.md「被取代与被修改的基线条款」：SC-ATB-001～007 取代，SC-ATB-008～010 与 SC-RUN-003 触发条件修改。基线是累积文档，不得整份覆盖。

## Phase 3 进展（长程 full_auto）

### S1 默认契约与可省略字段 + 联调（完成，2026-11-18T00:1x）
- TC 覆盖 4/4（TC-RUN-102/103/104/105），new_tests=14（Go 8 个顶层测试 + Node 6 个），`stdd state --complete-slice S1` 已登记。
- 新文件：`server/internal/governance/execution_default_contract.go`（+2 测试）、`server/cmd/server/execution_default_contract_wiring_test.go`；改动 `execution_authorization.go`、`execution_authorization_http.go`、`router.go`（`routerStartupRefusal` 接缝）、`scripts/aifi45-disposable/selections.json`（3 个新 selection，均带 expected）、`scripts/aifi45-real-run/{config,run,stack,stub-flow,scenario-stub,crctl-stage}.mjs` 与 4 个 `*.test.mjs`。
- 联调结论：默认 digest（policy c0e9f4c9…、template b9592537…）在“签发（省略字段）→ head → binding → crctl 检查 → 预消费 → writer → reviewer → 人工门 → 重启去重”全链一致，隔离栈 exit 0。C1 暂停点未触发。
- 驱动缺口修复见 PA-004（tools pin 暂存、daemon_token.owner_id）。台账 #345 / M33 已登记；未提交、未推送。
- 下一步 S4（等待可见），再 S3（准入收缩）。

### S4 等待可见（完成，2026-11-18T00:3x）
- TC 覆盖 4/4（TC-EWV-001～004），new_tests=7，`stdd state --complete-slice S4` 已登记。
- 新文件 `server/internal/governance/pipeline_progress.go`（+3 测试）、`server/cmd/multica/cmd_cr_pipeline_status_test.go`；改动 runner.go / runner_requirement_entry.go 回执、router.go 成员组挂载、cmd_cr_pipeline.go status 与 STATE/REASON 列；selections 新增 ewv-progress/ewv-receipt/ewv-route（带 expected 含子测试）。
- 证据：ewv-progress 25 PASS、ewv-receipt 6 PASS、ewv-route 8 PASS、CLI 直跑 7 PASS；回归 run-routes 16 / run-admission-support 55 / governance-run-lock 4 / rec-revoke 3 / run-root-and-dispatch 11 均 PASS。台账 #346 / M34。
- 说明：runner.go 与 runner_requirement_entry.go 工作树为 CRLF（autocrlf 检出），gofmt -l 标记为既有 EOL 现象，未整文件重排；git diff 仅 2/4 行。
- 下一步 S3（准入收缩）。

### S3 准入收缩（完成，2026-11-18T00:5x）
- TC 覆盖 8/8（TC-ATB-101～106、TC-RUN-101、TC-RUN-106），new_tests=3，`stdd state --complete-slice S3` 已登记。
- 生产：execution_admission.go head-only；execution_admission_gate.go 去 taskID/source 读取；runner.go/runner_requirement.go 入队调用去 taskID；main.go 注释。consumption/effect 写入、锁序、waitAdmission 不变。
- 测试：子代理改写既有 12 个测试文件（主会话抽查 diff + 复跑 atb-004/atb-008/run-admission-support/m005/run-routes 确认）；主会话新增 head 矩阵、source-task、requirement 形态三测试。selections 新增 ath-head-matrix/ath-source-task/ath-lock-revoke/ath-discovery/run-003/run-requirement-shape（带 expected 含子测试）。
- 证据：ath-head-matrix 16、ath-source-task 3、ath-lock-revoke 8、ath-discovery 6、run-003 1、run-requirement-shape 1、m005 20、atb-001..010、run-admission-support 59、run-routes 16、rec-revoke 3、governance-run-lock 4、run-root-and-dispatch 11 均 PASS。台账 #347 / M35。
- 回归 caveat：`selections.baseline.json` 的 baseline-governance（run:"."）有 93 fail/1 skip，经分类为环境性（独立迁移空表断言、AIFI45_TOOLS_ROOT/CRCTL_MJS 跨语言互操作、redis/终端 claim fixture、648-down 状态），均不涉及 DecideAdmission；CI 等价 regular 全量回归（tools pin + CRCTL_MJS + redis + 一次性库 + skip-regex）留待 Part C C2 以正确环境执行并如实记录。
- 下一步 Part C（C1 三路评审 → C2 全量+证据 run → C3 diff → C4 失败模式 → C5 经验 → C6 调整汇总 → C7 报告 → Gate 3）。

## Part C 质量验证（完成，2026-11-18T09:0x）
- C1 三路评审（code/test_config/docs_skills）发现已逐条处置（见 design-adjustments.md）。
- C2 同次执行证据：run c4c2a25e-7b91-43c9-893c-0973ee684b17，16/16 TC（15 命令 CP 真实通过 + TC-ATB-106 人工 confirm），ci check-failures 9/9、0 错误。前一 run fd15df82 因 GET 路由遮蔽失败，router.go 改叶子路由修复后重取证。
- C3 逐文件 diff：改动均在声明范围，无越界生产文件/调试残留。
- C4 (a)-(n)：CLI 确定性子集 9/9；语义项 (b)(c)(e)(h)(i)(m)(n) 人工核对通过（见 test-report）。
- C5 经验 EXP-2026-0011（chi 父路径 Mount 遮蔽 POST + 无凭证路由测试假阴性）。
- C6 design-adjustments.md、C7 test-report.md 已写。
- 全量回归平台性失败已归因（非本变更）；curated selections 全 PASS。
- 待 Gate 3 用户确认（不代签）。Git 提交/推送/部署/DAYA-5 恢复需另行授权。

## 追加（2026-11-18T14:4x）PA-008/PA-009 与 Gate 3 重签
- PA-008：字面 JSON null 被当成空串补齐为部署契约值，违反已批准 SC-RUN-104 的 AND。已修 `completeExecutionContractFields`（两处循环改用 `*string`）并补两条用例（单元三字段 + 真实 HTTP 两种形式）。RED 决定性复现：仅保留填充循环缺陷时请求返回 **201 并签发记录**；修复后 400 `EXECUTION_SOURCE_INVALID`、未写记录、未移动头。
- PA-009：`selections.json` 的 `channel-migration-{up,down,reapply}` 相对 HEAD 丢失必填 `state` 键，已按 HEAD 值恢复；格式化保持 HEAD 条目多行、新增条目单行，未改其他条目字节。
- 台账：修正 #345/#346/#347 缺日期列、CR 索引过时状态、#346 路由描述（叶子 GET 非父路径 Mount）、补点两个新增测试路径。
- 证据：新 run `b267076a-0fd0-45d5-b268-5d50a7a48cce`，15 命令 CP 全 PASS（run-default-contract-issue 22），`ci check-failures` 9/9 0 错误，TC-ATB-106 已按矩阵事实重新 confirm（subject 279b270f…）。
- Gate 3 已按用户指令以新 run 重签并 current。提交/推送/归档仍未执行。
