# Pending Adjustments — 2026-11-17-execution-admission-simplification

> 长程模式下的小偏离记录（不改受审文档承诺的实现选择）。交付时汇总进 design-adjustments.md。
> 状态取值：open（已记录未处理）/ applied（已实现）/ resolved（已验证）。

## PA-001 长程预授权的执行口径（2026-11-17T23:36）

- 用户原话「确认全部」；范围见会话中的授权清单。相对 Skill 模板的两处收紧（已向用户展示并获确认）：A3 阻塞绕不过即暂停、不跳过切片；A4 迭代到 10 轮上限即暂停报告。
- 平台差异：本会话在 pi，Step 8a.5 的 `.claude/settings.local.json` 权限配置不适用，未修改该文件（multica 的该文件为他人未跟踪文件），未改 pi 全局配置。
- 强制暂停点：TC-RUN-105 digest 不一致；daemon strict 依赖导致成功标准 #8 失败；CUSTOM-LEDGER 标识格式不接受 STDD change 标识；受审文档需改动或指纹漂移；安全问题 / 同一问题 3 次修复失败 / 通过率 < 95% / 0 TC 覆盖；Gate 3。
- 状态：applied（`.stdd.yaml.long_range` 已写入）。

## PA-002 切片重排：驱动改造与默认契约实现合为 S1（2026-11-17T23:5x）

- 原 slices.md：S1 只改驱动（诊断）、S2 实现 D3/D4。核实事实：(1) `decodeExecutionRawRequest`（execution_authorization.go:548-553）要求三个契约字段必须存在，不改 server 无法用省略字段的请求走通；(2) architecture-stub 场景固定以 `INCONCLUSIVE … SUBSTITUTE_NOT_EVIDENCE` / exit 2 结束（scenario-stub.mjs:1264-1266，README 明文），该语义不改，CP-RUN-105 的 exit 0 只能由新增的 `--default-contract` 模式给出。
- 调整：S1 = D3/D4 最小实现（TC-RUN-102/103/104）+ 驱动 `--default-contract` + TC-RUN-105 联调；S2 取消；S4、S3 不变。不改任何受审承诺（TC/SC/CP 映射、行为规格、默认契约方案均不变），只改执行顺序与切片边界；slices.md、tasks.md 已同步。
- 驱动新增行为：`--default-contract` 模式下全部断言通过且清理干净时输出 `PASS <label> scenario architecture-stub-default-contract` 并 exit 0，仍附 NOTE“不是真实模型证据”；既有 stub/main/revoke 模式输出不变。
- 状态：applied。

## PA-003 前置核实结论（2026-11-17T23:5x）

- 一次性实例：`run-selection.mjs` 自建 pgvector/pgvector:pg17（`--pull=never`，需本地已有镜像）、tmpfs、随机端口/密码、TTL 3600s；每 selection 独立库 `aifi45_tmp_<nonce>` 与受限角色；子进程注入 `DATABASE_URL`、`AIFI45_DISPOSABLE`、`AIFI45_DISPOSABLE_NONCE`；先 `cmd/migrate up` 再 `go test <pkg> -run <re> -count=1 -json`；无 `expected` 时要求 exit 0、≥1 pass、0 fail/skip；有 `expected` 时逐项核对。新增 selection 一律带 `expected`。
- 全量回归不得用 `make test`（.env → docker compose → 现网库）；参照 CI backend-tests：`ci-provision.mjs up` 写 DATABASE_URL/nonce → migrate → `test-go.sh --race --only regular --skip-regex … --json-out …` → CREATEDB 测试对账 → 清理。具体命令在 Part C 前按 ci.yml:413-458,548-560 核实。
- CUSTOM-LEDGER：追溯列接受 `STDD <change>（原生 STDD，非 CR）`（#336/#337）；当前最大 #344；C3 暂停点解除。
- 状态：applied。

## PA-004 S1 实现中的小偏离与驱动修复（2026-11-18T00:1x）

- 补齐位置：`BuildExecutionAuthorization` 与 HTTP 处理器（重放比较之前）各调用一次 `completeExecutionContractFields`；`decodeExecutionRawRequest` 拆为形状校验 + 必填校验，head 读取路径仍要求完整请求（冻结源已补齐）。受审承诺不变。
- `router.go` 新增 `routerStartupRefusal` 函数变量（生产仍 `slog.Error`+`os.Exit(1)`），只为让装配拒绝可在测试中观察；否则 TC-RUN-103 的“manifest 无密钥拒绝启动”无法在不退出进程的情况下断言。属实现接缝，不改行为。
- 驱动 `--default-contract` 模式：不生成 manifest、不传 flag、请求省略三字段；全部断言通过时 `PASS stub-run scenario architecture-stub-default-contract` exit 0，其余模式输出不变。新增行为已在 slices.md/PA-002 登记。
- 驱动既有缺口修复（不改 server）：(1) tools HEAD 已含 `git-shim-path.mjs`，`stageCrctl` 的“HEAD 已含即拒绝”在 HEAD 模式下必失败 → 新增 `ref` 参数，默认契约模式按 `.github/aifirst-tools-pin`（7a0a2ab5）暂存该提交自身字节，不读工作树；(2) `seedStatements` 的 daemon_token 未写 `owner_id`，迁移 588 后注册被拒（“daemon credential is not bound to a runtime owner”）→ 写入已种子的 owner。两者均为驱动与当前 schema/tools 状态脱节，与本变更行为无关但阻塞 TC-RUN-105。
- 测试修正：`malformed digest` 预期改为既有 `EXECUTION_SCOPE_INVALID`（`executionDigest` 的现行错误码）；字段值比较改用 `executionJSONEqual`（重编码后空白不同但值相同）。
- 证据：run-default-contract-issue 18 PASS、run-default-contract-wiring 3 PASS、run-authz-boundary 4 PASS、run-routes 16 PASS、run-admission-support 55 PASS、m005-consumption-effect 20 PASS（后三者为既有回归）；`node --test` real-run+disposable 371 项 368 PASS/0 fail/3 skip（既有平台 skip）；隔离栈默认契约模式 exit 0，policy=c0e9f4c9 template=b9592537，清理 remaining=0，无新残留容器。台账 #345 / M33 已登记。
- 状态：applied。

## PA-005 Part C 评审与回归归因（2026-11-18T01:4x，暂停待用户裁定）

### 全量回归归因（CI 等价：一次性库 + tools pin 7a0a2ab5 + redis + test-go.sh --race --only regular --skip-regex）
- 303 test-level fail / 122 skip，散布于 chat/repo checkout/claim/search/CLI config/migration 等**本变更未改动**的包；多为 Windows 平台性（git worktree/路径/home/时序）与独立迁移空表断言、AIFI45_TOOLS_ROOT/CRCTL_MJS 跨语言互操作、redis 行为。
- 唯一落在改动包的 TestTC_RUN_003 全量失败（issue_id NULL / 缺表变体）经 balanced 子代理决定性核实：**不可归因本变更**。根因为共享库跨包交互（governance TestExecutionMigrationDownRoundTrip 中途 DROP cr_execution_* 表；TestMain 收尾 DELETE cr_id LIKE 'CR-9%' 命中 run_003 的 CR-9030-* 派发任务）。CreatePipelineTask 的 issue_id IS NOT NULL 守卫 + FK ON DELETE CASCADE 使当前树不可能产生 NULL 行；agent.sql.go 未被本变更改动；issue_id 断言本变更原有。单独 run-003 与 run-routes（002+003+010）均 PASS。S3 把派发提前只是拉长暴露窗口，非正确性缺陷。
- 结论：curated selections（每 selection 独立一次性库）全部 PASS 是有效证据；全量 "." 失败为环境/共享库产物。

### C1 三路评审发现（code/test_config/docs_skills）
**已处置（主会话验收 + balanced 修复）：**
- code HIGH（router.go GET 子路由遮蔽 POST）：经新增共存测试 TestPipelineRunsPostRoutesSurviveProgressGetMount 走真实路由证实**误报**，两 POST 未被遮蔽（4 PASS）。保留该测试作回归证据。
- code MEDIUM（completeExecutionContractFields 在“另一字段省略 + 本字段非字符串”时悄悄默认化非法值）：真实窄口 bug，balanced 已修（仅缺席/空串才补齐，非字符串/非法值原样保留交解析器拒绝）+ 2 新子测试；run-default-contract-issue 20 PASS。非字符串 digest 期望码为 SOURCE_INVALID（生产解析器固定，与既有用例一致），malformed 字符串为 SCOPE_INVALID。
- code LOW（CLI 帮助文案仍说等待 trusted verdict；validateExecutionContractFields 注释误称生产 head 读取使用）：balanced 已修。

**待用户裁定（需改受审文档 → Gate 2 重审）：**
- H1（test_config+docs）：CP-RUN-105 断言 `PASS architecture-stub-default-contract ` 与驱动实际输出 `PASS stub-run scenario architecture-stub-default-contract …` 不匹配，成功执行也无法满足 CP。需改 agent spec 断言（或驱动输出）。
- docs#8：spec/design 称“任一显式不等均 409”，但格式非法 digest 实际先返回 EXECUTION_SCOPE_INVALID（非 409）。需修 spec 措辞。
- docs#2：design 称省略与显式必为不同请求；若显式字节恰等于补齐结果可被视为同一请求。需修 design 重放承诺措辞。
- M1（test_config）：所有命令型 CP 断言只有 exit_code+PASS 标签+skip=0，无业务观测值。带 expected 的 selection 其 PASS 由精确测试身份对账支撑（非裸标签），但 CP 断言文本本身未列业务观测。需裁定：强化 agent spec 断言，或认可“命令 CP 委托 expected 对账”的设计。

**待用户裁定（测试/selection 强化，不改受审文档）：**
- H2：ath-head-matrix selection 未选非法入参/空事务测试（execution_admission_test.go）与公开 reconcile 等待转成功。
- M4/docs#10：m005-consumption-effect selection 无 expected 名单。
- M8：waiting_human fixture 实为 kind=skill，应为 human_approval；无任务 running human 节点 idle 变体未构造。
- M2：矩阵只读 admission 字符串+mock enqueue 次数，未逐动作断言 wait_reason/run 未失败/真实队列行数。
- M3：source-task CP 只测普通入队，requirement 入队缺失/非法来源不在该 CP。
- M6：run-default-contract-wiring 未选 manifest loader 失败用例（半配置/相对路径/digest 错/超限）。
- M9：回执 in-flight/读失败只测 helper，未经 architecture start handler 验证。
- M10：ewv CLI CP 未断言所选 resume 路由测试 PASS，start 请求体/令牌测试未选。
- H3/H4/H5（覆盖深度）：H3 锁测试未断言并发真实撤销等待入队效果完成；H4 run_003 用手动 WakeGrant 而非真实 ACK 回调/周期唤醒/撤销头；H5 requirement 形态先签头再 StartRequirement，而非无头已注册 run 经 ResumeActiveRuns 推进（SC-RUN-109 承诺“发现路径”）。

**过程项：**
- docs#3：S3 已登记 done（8/8 自动 TC），但 TC-ATB-106 人工矩阵核对仍待办（Part C 交付），TC-RUN-101 任务行未勾选。切片登记覆盖自动 TC，人工核对属 Part C。
- docs#4：全量回归已以正确环境执行并归因（见上），不再是“延至 Part C 未做”。
- docs#11：pending-adjustments 格式 Markdown vs YAML 的 Skill 歧义；本 change 沿用 Markdown（spec Skill 口径），保留内容。
- docs#12：design/test-plan 历史行号为实施前快照，宜标注。

### 暂停理由
H1/docs#8/docs#2/M1 需改受审文档（agent spec/spec/design），按长程预授权 C4 暂停重审 Gate 2；覆盖深度项需用户裁定强化或接受为已知限制。未自行改受审文档、未代签 Gate。

## PA-006 C2 证据 run 暴露并修复 GET 路由遮蔽（2026-11-18T08:5x）

- 首个证据 run（fd15df82）CP-RUN-105 真实失败：source task `multica cr pipeline start` 返回 404。根因即 C1 代码评审 HIGH——S4 用 `r.Route("/api/workspaces/{workspaceID}/pipeline-runs", …)` 在父路径 Mount GET 子路由，chi 遮蔽了同路径的 architecture start POST（及 /requirement）。
- 原共存测试用**无凭证** POST 只断言 ≠404/405，但无凭证时主路由 Auth 与挂载子路由成员中间件都返回 401，无法区分遮蔽 → 假阴性。
- 修复（router.go）：GET 改为叶子路由 `r.With(RequireWorkspaceMemberFromURL).Get("…/pipeline-runs/{runID}", …)`，不在父路径 Route/Mount。共存测试改用真实 task token：POST→400（到达处理器，CR 不存在）、GET 叶子存在，4 PASS。
- 直接跑真实运行驱动 architecture-stub --default-contract：exit 0，全阶段 PASS（authorization 201、source/writer/reviewer/approval-gate/restart-dedup），清理 remaining=0。
- 属同一合同下的实现缺陷（revision-rules：退回 BUILD 仅重审 Gate 3，不需再重审 Gate 2）。需以新 run 重取证后 confirm TC-ATB-106。

## PA-007 TC-ATB-106 矩阵证据补齐与 Gate 3 重签（2026-11-18）

- 发现：Gate 3 确认后复核发现 TC-ATB-106/SC-ATB-110 要求「矩阵 + 改写前后各格计数 + 被删用例指向取代条款」写入 test-report，原报告只有一行引用；原 confirm 声明对「人工门×幂等」过度声称。
- 核实：`ath-discovery` 的 ATB_008/009 均未走到 human gate（ATB_008 首任务未完成；ATB_009 止于 review running），且基线（HEAD 3b43b62ce）本身也没有「人工门通过 × 幂等」用例——是该格从未落地，非改写退化。
- 补齐：新增 `server/internal/governance/execution_admission_human_gate_discovery_test.go`（真实授权头 + 真实 Runner；完成 write/review + 持久化业务审批后首次发现经 passHumanApprovalNode 真实 passed 并派发下游，重复发现两次断言节点行/approval id/下游 task id/计数/run 状态/头指针不变）；`selections.json` 的 `ath-discovery` 加入该测试（7 PASS）。人工门 `completed_at` 每次唤醒会被刷新，未纳入幂等声明（只钉非空不回退）。
- 报告：test-report.md 新增「TC-ATB-106 覆盖矩阵逐格核对」节（计数口径、20 格 基线→现在、每格 leaf 清单、重复计数披露、被删→取代条款、无 skip、证据强度限制）。
- 证据：新 run `42730f14-b520-4acb-85cc-83cd6eceaa45`，15 命令 CP 全 PASS，`ci check-failures` 9/9 0 错误，TC-ATB-106 经 `agent confirm --tc TC-ATB-106` 记录（subject 8e01623e…）。旧 run c4c2a25e 的回执保留不变。
- 因受测输入变化，Gate 3 现为 stale；需用户以新 run 明确重签（`--reapprove`）。

## PA-008 字面 null 被补齐为默认值（在途 change 违反自身已批准规格，2026-11-18）

- 缺陷：`completeExecutionContractFields` 用 `var text string` 解码，字面 JSON `null` 解码不报错且留下空串，于是被当成"省略/空串"补齐为部署契约值。SC-RUN-104 的 AND 明确要求格式非法的值（非字符串）在契约比较前按 `EXECUTION_SOURCE_INVALID`/`EXECUTION_SCOPE_INVALID` 拒绝，不被补齐。现行 `executionNonEmptyString` 对 `null` 正好返回 `EXECUTION_SOURCE_INVALID`，即契约要求拒绝。
- 影响取证：仅保留填充循环缺陷时，「一个字段字面 null + 其余省略」的请求返回 **201 并签发记录**（应拒绝）；用户案组亦可签发本应被拒的授权。此前未被发现，是因为测试 fixture 的 `nil` 覆盖是**删除键**（=省略），从未发出字面 null。
- 修复：两处循环改用 `*string`——`null` 得到 nil 指针（原样保留交解析器拒绝），只有键缺席或值确为空串才补齐。生产行为变更仅此一处。
- 用例：`TestExecutionAuthorizationContractFieldsOptional/literal_null_is_refused,_not_completed`（单元，三字段）与 `TestExecutionAuthorizeDefaultContractOmittedFieldsHeadValid/literal-null-refused`（真实 HTTP，两种形式：其余省略、其余显式相等；断言 400 `EXECUTION_SOURCE_INVALID`、未写记录、未移动头）。
- RED 证据（临时回退后复现，已恢复）：填充循环缺陷存在时，该 HTTP 用例 201 签发；修复后 400 拒绝。
- 属实现缺陷修正，不改变已批准承诺（SC-RUN-104 未改），按 revision-rules 只需重跑证据并重签 Gate 3。

## PA-009 恢复 selections 中丢失的 state 键（2026-11-18）

- 发现：`scripts/aifi45-disposable/selections.json` 的 `channel-migration-up/down/reapply` 三条相对 HEAD 丢失必填 `state` 键（migrated / 648-down / 648-down-up），此次编辑 selections 时暴露。无法确定由哪一步丢失；不是本 change 的设计变更。
- 处置：按 HEAD 值恢复这三个 `state` 键；重新序列化时保持 HEAD 条目多行、本次新增条目单行的原有格式，未改其他条目字节。
- 现 selections 相对 HEAD 的差异仅为：新增 12 条 selection、m005 的 run 正则与 expected、恢复的 state 键。
