# Test Report — 2026-11-17-execution-admission-simplification

> 选定 run：`b267076a-0fd0-45d5-b268-5d50a7a48cce`（validation/runs/b267076a-…/），已并入 PA-008 字面 null 修复。先前 run（PA-007 的 `42730f14-…`、矩阵前 `c4c2a25e-…`、路由修复前 `fd15df82-…`）均已取代，旧回执保留。

## TC 覆盖（planned vs actual）
- 计划 16 TC，实际执行 16/16（100%）。15 个命令 CP 真实通过 + 1 个人工 TC（TC-ATB-106）经 agent confirm 记录。
- 覆盖率：not_applicable（Go/Node 被测，覆盖率采集仅支持 pytest-cov；quality.coverage.enabled=false）。无覆盖保证，依项目既定声明。

## 同次执行证据（run b267076a）
| CP | selection/命令 | 结果 |
|---|---|---|
| CP-ATB-101 | ath-head-matrix | 22 PASS / 0 fail / 0 skip |
| CP-ATB-102 | ath-lock-revoke | 9 PASS |
| CP-ATB-103 | ath-discovery | 6 PASS |
| CP-ATB-104 | ath-source-task | 6 PASS |
| CP-ATB-105 | m005-consumption-effect | 20 PASS |
| CP-RUN-101 | run-003 | 1 PASS |
| CP-RUN-102 | run-default-contract-issue（含字面 null 用例） | 22 PASS |
| CP-RUN-103 | run-default-contract-wiring | 10 PASS |
| CP-RUN-104 | run-authz-boundary | 4 PASS |
| CP-RUN-105 | architecture-stub --default-contract（真实运行驱动） | exit 0，全阶段 PASS，清理 remaining=0 |
| CP-RUN-106 | run-requirement-shape | 1 PASS |
| CP-EWV-001 | ewv-progress | 26 PASS |
| CP-EWV-002 | ewv-receipt | 7 PASS |
| CP-EWV-003 | ewv-route | 8 PASS |
| CP-EWV-004 | go test cmd/multica（6 Test） | 6 PASS |
| TC-ATB-106 | 人工覆盖矩阵核对 | 见「TC-ATB-106 覆盖矩阵逐格核对」；agent confirm 记录（run b267076a，subject 279b270f…） |

## 每切片验证状态
- S1（TC-RUN-102/103/104/105）：4/4，new_tests=14，done。
- S4（TC-EWV-001～004）：4/4，new_tests=7，done。
- S3（TC-ATB-101～106、TC-RUN-101、TC-RUN-106）：8/8，new_tests=3（+强化子测试），done。

## C4 失败模式检查（run b267076a；CLI 确定性子集 9/9 通过）
| ID | 类别 | 结果 |
|---|---|---|
| (a) | hallucination | ✓ 必需文件+Spec 存在 |
| (b) | scope_creep | ✓ 人工 C3 diff：改动文件均在声明范围（governance/cmd/scripts），无越界生产文件 |
| (c) | cascading_errors | ✓ 人工：无连锁错误；路由遮蔽为单点缺陷已修 |
| (d) | context_loss | ✓ TC-ID 唯一（16） |
| (e) | tool_misuse | ✓ 人工：CLI/selection 用法正确 |
| (f) | runtime_deviation | ✓ 所有 THEN 含 SHALL；行为证据见 CP |
| (g) | pipeline_break | ✓ AND 数量正常；3 切片均有验证证据 |
| (h) | content_quality | ✓ 人工：文档完整可用 |
| (i) | instruction_decay | ✓ 人工：长程规则未被稀释（暂停点均遵守） |
| (j) | coverage_vacuum | ✓ TC 执行覆盖 16/16；覆盖率 not_applicable 已声明 |
| (k) | contract_gap | ✓ 契约一致（3 capabilities） |
| (l) | anchor_missing | ✓ Non-critical 无需 anchoring |
| (m) | agent_cp_failure | ✓ 人工：15 命令 CP 真实通过（含真实运行驱动），人工 CP 已 confirm |
| (n) | cross_system_mismatch | ✓ 人工：默认 digest 在 server/daemon/crctl 全链一致（真实驱动验证） |

## 全量回归（CI 等价，本地 Windows）
- 一次性库 + tools pin 7a0a2ab5 + redis + test-go.sh --race --only regular --skip-regex：303 test-level fail / 122 skip，均在未改动包（chat/repo checkout/claim/search/CLI config/migration），属 Windows 平台性 + 独立迁移/tools/redis 环境。
- TestTC_RUN_003 全量失败经 balanced 子代理决定性核实**不可归因本变更**：共享库跨包交互（governance TestExecutionMigrationDownRoundTrip DROP cr_execution_* 表 + TestMain DELETE cr_id LIKE 'CR-9%' 命中其夹具）；CreatePipelineTask issue_id IS NOT NULL 守卫 + FK CASCADE 使当前树不可能产生 NULL 行；agent.sql.go 未改；单独/同跑 PASS。
- curated selections（每 selection 独立一次性库）全部 PASS，为有效行为证据。

## 已知问题 + 未完成项
- head-only 不额外查 stage='execution'（依赖 head 指针完整性，威胁模型外）——接受。
- progressOf 瞬态/waiting_approval 取舍按 SC-EWV 明文——接受。
- H3 用 head 指针 UPDATE 模拟撤销锁语义（行锁一致），未走 HTTP 撤销路由——接受。
- 全量 "." 回归平台性失败未在本环境消除（非本变更引入）；CI（Linux）为权威全量环境。
- 未做：Git 提交/推送/部署/DAYA-5 恢复（均需另行授权，不在 BUILD 范围）。

## TC-ATB-106 覆盖矩阵逐格核对（SC-ATB-110）

### 计数口径（先定口径再计数）
- **leaf** = `t.Run` 叶子子测试，或无子测试的顶层测试；无 `t.Run` 的多阶段测试计 1 leaf（相位另列）；父测试不计 leaf。
- 只计**真正执行并断言该动作在该头状态下效果**的 leaf：`direct`（直接调 `markNode`/`passHumanApprovalNode`/`enqueueNodeFor`/`enqueueRequirementNode`）或 `walk`（经 `ResumeActiveRuns`/`Reconcile`/真实路由驱动且 leaf 内有该动作的行级断言）。
- 不计入动作格：decider 级（直接调 `DecideAdmission`）、seam 级（锁探针、panic 清理）、单位级映射、消费写入路径（CE_*、ATB_010）。
- 基线 = `HEAD 3b43b62ce`（该提交未触碰 governance；本 change 全部为工作树改动）。断言 `WAIT_CONSUMPTION` 的旧用例**不**计入「无头」：旧 decider 先查头，能走到消费检查说明头存在。

### 改写前后各格用例数（基线 → 现在）
| 动作 | 无头 | 有效头 | 叫停 | 跨范围头 | 幂等 |
|------|------|--------|------|----------|------|
| 节点置 passed | 0 → 13 | 13 → 21 | 1 → 3 | 0 → 4 | 4 → 6 |
| 人工门通过 | 0 → 5 | 3 → 10 | 0 → 2 | 0 → 4 | 0 → 1 |
| 普通节点入队 | 0 → 9 | 7 → 9 | 1 → 3 | 0 → 2 | 4 → 6 |
| requirement 入队 | 0 → 4 | 3 → 4 | 0 → 1 | 0 → 2 | 1 → 1 |

- **没有任何一格降到 0**；无计数下降格。基线 11 个 0 格全部由本次新增的 effect 级用例补齐（无头、跨范围头的 effect 级覆盖在基线本就不存在，design.md 影响表已预判「需新增，不能只靠改写」）。
- 唯一持平格：requirement 入队 × 幂等 1 → 1，唯一承担者仍是 `TestTC_ATB_008/requirement`；已知薄弱点，记录在此不掩饰。

### 承担 leaf 清单（缩写：HM=head_matrix、TB=task_binding、TD=task_discovery、GT=gate、EQ=enqueue、RQ=requirement_enqueue、HG=human_gate、HD=human_gate_discovery、ST=source_task、RS=requirement_shape_default_contract、RR=execution_revoke_resume、R3=cmd/server/execution_run_003_test.go）
- M1/M2/M3/M4 = `HM:141` `{architecture-design,requirement-authoring}/{none,approve,reject,foreign_workspace+foreign_cr}`（2/2/2/4，direct：markNode 与 passHumanApprovalNode 行级断言）
- E1/E2/E3/E4 = `HM:190` `enqueue/{none,approve,reject,foreign_*}`（1/1/1/2，direct：计数 enqueuer + 真实 TaskService 队列行）
- B5d = `TB:163` `ATB_005/{arch,req}/{source_only,unrelated_only,source_and_unrelated}`（6，direct）；B5r = `TB:179` `retry_uses_newest_task`（2，direct）
- B6n = `TB:249` `ATB_006/{arch,req}_no_own_task_unrelated_consumption`（2）；B6h = `TB:260` `human_{unrelated_task,attached_human_task}`（2）；B6s = `TB:306` `{mark_node,human_approval}_{missing,malformed}_source`（4）
- G = `GT:20` GateHolds（1）；Q = `EQ:39`（1）；R = `RQ:32`（1）——均为「无头拒绝 → 设头放行」两相位
- H2 = `HG:138` `refused while the head is missing`；H3 = `HG:164` `admitted after restoring the head`；S = `ST:23` `SourceTaskOptionalForGates/context_*`（2）
- D8a/D8r = `TD:234` `ATB_008/{architecture,requirement}`（walk）；D9c/D9n = `TD:255` `ATB_009/{consumed,not_consumed}`（walk）
- RC/RRv = `RR:123` `REC_006/{control_head_still_current,revoked_head}`（walk）
- **HD = `HD:125` `TestAdmissionHumanGateDiscoveryIdempotent`（新增，walk）**；RS = `RS:21` RequirementShape（walk）；R3 = `R3:51` RUN_003（walk）

逐格：
- A1 无头 13 = M1+B5d+B5r+B6n+G；有效 21 = M2+B5d+B5r+B6n+B6s(mark×2)+G+S（direct 17）+D9c+D9n+RC+HD（walk 4）；叫停 3 = M3+RRv；跨范围 4 = M4；幂等 6 = B5r+D9c+D9n+RC+HD
- A2 无头 5 = M1+B6h+H2；有效 10 = M2+B6h+B6s(human×2)+H3+S（direct 9）+HD（walk 1）；叫停 2 = M3；跨范围 4 = M4；幂等 1 = HD
- A3 无头 9 = E1+Q+D8a+D9c+D9n+RC+RRv+R3+HD；有效 9 = E2+Q+D8a+D9c+D9n+RC+RRv+R3+HD；叫停 3 = E3+RRv+R3；跨范围 2 = E4；幂等 6 = D8a+D9c+D9n+RC+R3+HD
- A4 无头 4 = E1+R+D8r+RS；有效 4 = E2+R+D8r+RS；叫停 1 = E3；跨范围 2 = E4；幂等 1 = D8r

### 重复计数披露（同一 leaf 计入多格，不掩饰）
M1–M4 每 leaf 同计 A1+A2；E1–E4 每 leaf 同计 A3+A4（真实队列行断言两者共享）；B5d/B5r/B6n/G/Q/R 同计无头+有效（两相位）；B6h 同计 A2 无头+有效；S 同计 A1+A2 有效；D9c/D9n/RC 同计多格；HD 计 7 格（A1 有效/幂等、A2 有效/幂等、A3 无头/有效/幂等）；R3 计 A3 四格；RS 计 A4 两格。

### 被删/语义改写的基线用例 → 取代条款
| 基线用例（HEAD） | 处置 | 取代条款 |
|---|---|---|
| `ATB_001/{missing_task,no_runtime,no_dispatched_at}`（3 decider leaf） | 删除：准入不再读任务快照 | `admission-task-binding` SC-ATB-101～104（SC-ATB-001～004 被取代，见 design.md 取代表）；无效入参仍由新的 `empty_cr/malformed_cr/missing_cr` 承担 SC-ATB-104 的 AND |
| `TestAdmissionDeciderWaitsForCommittedConsumption` 消费链相位 4–8 | 删除；`approve_without_consumption` 方向反转为 ADMITTED | SC-ATB-101（头即放行）；「准入不随消费变化」由 ATB_003 + ATB_010 + CE_001 钉住 |
| `ATB_006/{mark_node,human_approval}_{missing,malformed}_source`（4 leaf，原 AuthorityMismatch 拒绝） | 改写为放行（passed + approval id） | SC-ATB-108（门放行、入队仍拒） |
| `ATB_001/foreign_workspace`（任务跨 workspace）、`ATB_002/other_cr`（回执跨 CR） | 改为头记录跨 workspace / 头指针跨 CR | SC-ATB-104 |
| `ATB_009/not_consumed`（原停留 running/WAIT_CONSUMPTION） | 改写为与 consumed 同断言（passed/2/2） | SC-ATB-107（派发不要求源任务或首任务消费回执） |
| `ATB_010`、`CE_001` 中的准入断言 | 删除，写入语义保留 | SC-ATB-109 |
| `REC_006` 的 `WAIT_TRUSTED_T_COMMIT` 断言字符串 | 改为 `HEAD_REJECTED`，五步唤醒与行不变保留 | SC-ATB-103 |
| `GateHolds`/`StopsEnqueue`/`RequirementEnqueueIsGated` 前置「approve 头+未消费」 | 改为「无头拒绝 → 设头放行」 | SC-ATB-101、102 |
| `ATB_007/{arch,req}_unrelated_consumption` 由 leaf 降为父测试（新增 4 个 source 子测试） | 头相位由 E2、D9n、HD、RS 补回，格数未降 | 头保证 SC-ATB-101；source 归因 SC-ATB-108 |
| 基线尚无「人工门通过 × 幂等」用例（基线 0） | **新增** `TestAdmissionHumanGateDiscoveryIdempotent` | SC-ATB-106/107；规格 REQ-ATB-102 幂等 |

### 无新增 skip、无放宽断言
- 本次所有相关 selection 输出 `fail=0 skip=0`；未新增 `t.Skip`，未删除失败断言（仅按 D1/D2 改变被断言的前置条件与预期码）。
- `completed_at` 不纳入人工门幂等声明：`passHumanApprovalNode` 的 UPDATE 匹配 `status IN ('pending','running','passed')`，重复唤醒会刷新该列；新测试只钉「非空且不回退」，其余业务事实（节点行与 approval id、下游任务 id、节点/任务/队列计数、run 状态、头指针）必须不变。

### 本节的证据强度限制（如实标注）
- 基线各 leaf 的「当时通过」无法证实：HEAD 的 selections 中 atb-001..010/m005/rec-revoke 均无 `expected` 对账，也无归档日志；本节只证明**基线与当前的用例存在性与断言内容**。
- 命令型 CP 只冻结 command + exit_code，不含 stdout；逐测试 PASS 依据 `run-selection.mjs` 的闭集对账（expected 每项须 run→pass，出现任何未列出的测试即 blocked）。

## 第三轮修复
- 无切片触发第三轮 strong 修复（各切片首轮/次轮通过）。两次证据阶段发现的缺陷（GET 路由遮蔽 PA-006、字面 null 被补齐 PA-008）均属实现缺陷，非切片验证失败。

## PA-008 字面 null 证据（run b267076a）
- 缺陷：字面 JSON `null` 被当成空串补齐为部署契约值。RED 复现：仅保留填充循环缺陷时，「一个字段 null + 其余省略」返回 **201 并签发记录**；修复后返回 400 `EXECUTION_SOURCE_INVALID`，未写记录、未移动头。
- 用例：`TestExecutionAuthorizationContractFieldsOptional/literal_null_is_refused,_not_completed`（三字段）与 `TestExecutionAuthorizeDefaultContractOmittedFieldsHeadValid/literal-null-refused`（真实 HTTP，其余省略/其余显式相等两种形式）。
- 未改已批准规格：SC-RUN-104 的 AND 本就要求非字符串值在契约比较前拒绝；本次是使实现回到规格。

## 前端 lint / typecheck / e2e（quality.yaml）
- `pnpm lint` exit 1：42 问题全在 packages/views（lucide-react 直接 import、a11y），属他人未提交前端改动，非本变更（本变更未改 packages/）。
- `pnpm typecheck` exit 1：apps/docs 缺 fumadocs-mdx 依赖（MODULE_NOT_FOUND），turbo 前置中止，packages tsc 未执行 → 无结论，环境问题，非本变更。
- e2e `bash scripts/check.sh`：跳过。quality.e2e.scope=critical_only 且 critical_paths=[]（无指定关键 e2e 路径）；本变更纯 Go server 无前端改动；check.sh source .env 并可能复用现网 backend/前端，对现网有风险。无关键 e2e 义务，记录跳过理由。
