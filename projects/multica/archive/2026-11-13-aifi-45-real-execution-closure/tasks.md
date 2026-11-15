# 2026-11-13-aifi-45-real-execution-closure 任务清单

> 🔒 = 需要用户逐项授权（长程预授权不覆盖）：一次性 PG/podman、真实模型、真实 backend/daemon、tools 仓、提交推送部署。

## 1. 节点证据生产者 · endpoint 基数（P0，S1）
- [x] 1.1 RED：`TestTC_REC_003` 子测试——authorized 已预消费节点：X 通过、X 重放幂等、Y 通过、Z 为 409；source/legacy/未预消费：第二个不同 challenge 即 409；任一 proof 通过不新增 consumption
- [x] 1.2 GREEN：endpoint 增加每 run 上限，`executionBindingEndpointForRun` 按「authorized 且已预消费」取 2，其余 1
- [x] 1.3 REFACTOR + `go vet ./internal/daemon`

## 2. 节点证据生产者 · claim 合同值（P0，S2）
- [x] 2.1 RED：`TestTC_REC_002`——无初始记录=空值；有初始记录且 head=approve=`authorized-execution/v1`；有初始记录且 head 已撤销=仍为 `authorized-execution/v1`；合同值不受 body/评论影响 🔒 DB（2026-11-14 经 `run-selection.mjs --only rec-002` 在一次性 PG 通过，pass=6；此前该行写「未执行」已过期）
- [x] 2.2 GREEN：claim 响应 `PipelineExecutionContract`、daemon `Task` 字段
- [x] 2.3 未知非空合同值的拒绝点（在 S3 使用）

## 3. 节点证据生产者 · daemon 预消费（P0，S3，依赖 1、2）
- [x] 3.1 RED：`TestTC_REC_001`——authorized：agent 启动前恰一条当前 generation 回执+自身 effect、run 结束不再消费；任一前置失败不启动 agent；未知值拒绝；空值与改动前一致；同 generation 重放不新增
- [x] 3.2 GREEN：`prepareClaimedPipelineTask` 节点预消费、内存标记、run-end 跳过
- [!] 3.3 核实节点 agent 的 `.crctl` 授权材料来源（E4 结论）：**阻塞，已裁定走成对 tools change** — 静态结论为 agent 的 `crctl advance` 找不到 daemon 信任库里的 grant（crctl 仅认 `--trust-root`，无环境变量；SKILL.md 均不传；daemon 不写 `<root>/.crctl`）。tools 侧变量 `CRCTL_EXECUTION_TRUST_ROOT` 已实现并通过 tools 的 Gate 3（未提交）；daemon 注入见 §9，Gate 2 重审通过后实现，真实可见性要到 §5 的真实 A 才能验证
- [x] 3.4 校正陈旧注释（`daemon.go:765-768`、`execution_consumption_client.go:11-18,55-57`，英文）

## 4. 真实运行驱动与清理冒烟（P0，S4）🔒
- [x] 4.1 RED：`node --test` 驱动单测——缺配置/空模型/Fable/未知 scenario 或参数在创建任何资源前拒绝并非零退出
- [x] 4.2 GREEN：`scripts/aifi45-real-run/run.mjs`、资源登记（nonce + 完整 ID）、EXIT/ERR/INT/TERM 清理、总 deadline
- [x] 4.3 cleanup-smoke：setup 失败、运行中超时、阶段失败，输出 `remaining=0` 🔒 podman（2026-11-14 已在真实 podman 跑通，6 行 PASS，退出码 0，跑前跑后容器列表一致，带本驱动标签的容器为 0）

## 5. 真实 architecture run A（P0，S5）🔒
- [x] 5.0 crctl 固定来源副本 `scripts/aifi45-real-run/crctl-stage.mjs`（ADJ-S5-0；无模型；7 个测试、3 个变异均红并还原；对真实 tools 仓只读演练：覆盖版比 `HEAD` 恰多 22 行，他人未提交改动未进入副本，tools 工作树前后不变）。尚未接入任何场景，随 5.1 接入
- [x] 5.1 `architecture-main` 场景：真实授权来源、篡改拒签、writer 双 advance 一回执、reviewer 零写有回执、人工门、交接处重启（2026-11-15 取证 run `11acf6e8-…` 13/13，CP-REC-004 在真实模型下全绿；观察见 ADJ-A0-9）
- [x] 5.2 BUILD 前确认：模型名（非 Fable）、次数、费用、podman/一次性库/backend/daemon 授权；写 `run-config.json`（不入库）（2026-11-15：`GB-JP/deepseek-flash`、`max_runs=1`、用户 cost_ack；`.local/run-config.json` 已 gitignore）
- [x] 5.3 首次失败：停在止损点，只修 S1–S3（2026-11-15：首次真实运行失败于驱动的 `SOURCE_TRACE_MISSING`——观察层依赖替身 trace，**不是生产缺陷**，未动 S1–S3；已把 main 模式观察改为账本 + 回执，见 ADJ-A0-6）

## 6. 撤销后不推进（P0，S6）
- [x] 6.1 RED：`TestTC_REC_006`——真实撤销路由后 `ResumeActiveRuns` 与新 Runner 不派发、不推进，历史行不变 🔒 DB（`governance/execution_revoke_resume_test.go`，选择 `rec-revoke`；含「未撤销」对照子测试，一次通过即绿，故以 4 个变异证明能红：去 decider 的 head 拒绝、去 markNode 的 admission 门、重启后的 Runner 无 decider、不发撤销请求；连跑 3 次稳定）
- [x] 6.2 GREEN：未补任何生产代码——既有 admission gate（`execution_admission.go` 的 head 判定与 `markNode` 的 passed 门）已满足；只在测试里证明了这一点。未被本测试单独覆盖：派发入口 `decideUnderHeadLock`（`governance/runner.go` 的派发入口，函数定义在 `governance/execution_admission_gate.go`）的独立拒绝（需要「writer 已 passed、撤销后才派发 reviewer」的交错；既有 `TestAdmissionGateLockBlocksRevocation` 只覆盖该入口的持锁，并未单独断言「撤销后不派发 reviewer」。本 change 不声称覆盖，记为未验证项）
- [x] 6.3 `architecture-revoke` 场景（DB 确认 writer running 时撤销，否则 INCONCLUSIVE）🔒 模型（2026-11-15 取证 run `11acf6e8-…` 中 CP-REC-005 真实 B 全绿；重启后出现一条 0 消费的被拒重派，`refused=1`，见 ADJ-A0-9）

## 7. workspace 删除后终态安全（P0，S7）🔒 一次性 PG
- [x] 7.1 RED：`TestWorkspaceDeletionRefusesNewCommand` 保持原断言（当前红）+ 缺 workspace 的 `ErrReservationWorkspaceGone` 用例（新增子测试 `command_for_unknown_workspace`、`command_without_workspace`；已删 workspace 子测试补原因钉住；见 design-adjustments ADJ-S7-4）
- [x] 7.2 GREEN：`ControlCommandInput.WorkspaceID`、`ApplyControlCommandTx` 与 `CreateReservationTx` 的 workspace 锁、生产 handler 在 claim/head 前先锁（实现用 `FOR KEY SHARE`，非设计写的 `FOR SHARE`，见 ADJ-S7-1，Gate 2 已于 2026-11-14T02:46:19 重审通过）
- [x] 7.3 迁移 33 处测试 fixture（balanced 子代理完成，主会话核对：只改 4 个测试文件、换行符保持、未随机填 UUID）
- [x] 7.4 并发探针 `handler-wsd-race`：两种交错、`pg_blocking_pids` 等待确认、deadline；不用生产 hook（见 ADJ-S7-2），另加 `governance-wsd-lock`（ADJ-S7-3）

## 8. 回归与台账（P0，S8）🔒 一次性 PG
- [x] 8.1 `selections.json` 新增选择（`rec-001/002/003/009/rec-revoke`、`handler-wsd-race`、`governance-wsd-lock`）；`test-ownership.json` 移除 command 探针的 `known-finding` 条目，`test-ownership.test.mjs` 的 TC-TOR-001 改为断言提交台账不再有 known-finding（balanced 子代理执行、主会话审 diff：只改这两个文件、LF 保持、合成条目测试一字未改；`test-ownership.test.mjs` 18/18、`scripts/aifi45-disposable/*.test.mjs` 173/173 改前改后一致；恢复条目后新测试变红）
- [x] 8.2 `CUSTOM.md` 登记（STDD `2026-11-13-aifi-45-real-execution-closure`）：新增 M32 节 #334–#337、模块索引行、CR 索引行；#327 末尾追加「已由 #335 修复」；`handler/agent.go` 补 `// AIFIRST:` 标记。列数与既有行一致，CRLF 保持
- [x] 8.3 全组 `run-selection.mjs`：0 FAIL、0 skip、remaining=0（2026-11-14 最终一次：39/39 PASS，退出码 0，每个选择叶子 PASS 数均大于 0，`remaining=0`，podman 容器列表前后一致。全组一共跑过三次：首次由 balanced 取证，暴露 `run-routes` 的 `TestTC_RUN_003` 红（`cmd/server/execution_run_003_test.go` 漏迁移 S7 必填的 `WorkspaceID`，已补；全仓脚本扫描 `ControlCommandInput{` 字面量，其余缺该字段的 5 处走 `ApplyControlPolicyEventTx`、不经 workspace 锁，无需迁移）；C1 评审修复后第二次暴露 `rec-revoke` 偶发红，根因是测试夹具的 `dispatched_at` 拼写（ADJ-C1-2，同时解释了此前未定位的 `TestTC_ATB_009` 非确定性失败），修复后第三次 39/39）
- [x] 8.0 C1 评审修复（ADJ-C1-1/2/3）：`taskExecutionStrict` 统一 strict 推导、信任根按 `EqualFold` 清除、锁序交错测试、`canonicalGeneration`、workspace 并发测试改用独立连接、`TestTC_REC_002` 跨 server/daemon 键、`TestTC_REC_006` 增加节点完成步骤。修复后全组 `run-selection` 重跑 39/39 PASS，remaining=0
- [x] 8.4 `stdd structure delta`、C1–C7 评审与质量检查、test-report、Gate 3 等你确认（2026-11-15：structure delta 已重生成；test-report.md 已写；取证 run `bb5a9173-…` 13/13；**Gate 3 待用户确认**）

## 9. 授权节点的信任根注入（P0，S9，依赖 3 与成对 tools change；须在 5 之前；Gate 2 重审通过后才写代码）
- [x] 9.1 RED：`TestTC_REC_009`——authorized 已预消费任务的 agent 环境含 `CRCTL_EXECUTION_TRUST_ROOT`，其值下存在该任务已安装的 grant；legacy 任务不含；custom_env 同名配置在 legacy 任务被清除、在 authorized 任务不改变注入值；daemon 进程环境不变；并发任务互不影响
- [x] 9.2 GREEN：`Task.ExecutionTrustRoot`（`json:"-"`）在预消费成功处与 `ExecutionPreconsumed` 同时设置；`injectTaskCRWorkspaceEnv` 内先 delete 后按「已绑定且预消费」条件发布；校正 `execution_trust.go` 里 daemon-only 的注释（英文，已做）；发布判据只用 `ExecutionTrustRoot != ""` 一个条件（变异 M2 暴露了与 `ExecutionPreconsumed` 的重复判断）
- [x] 9.3 `selections.json` 新增 `rec-009`

## 10. strict source 任务的预检与预消费（P0，S10，D1.8；Gate 2 重审通过后才写代码；须在 5 之前）
- [x] 10.1 RED：`TestTC_REC_010`——CR 身份来源（comment 声明、任务关联、issue 唯一关联）成功且恰一次消费；无来源、声明与关联冲突、issue 多关联失败关闭零消费；legacy 不变；成功后 `Task.Pipeline*`、`ExecutionPreconsumed`、`ExecutionTrustRoot` 为空、endpoint 为 nil；预检的 CR 根等于运行时 `resolveTaskWorkspaceBinding` 的根
- [x] 10.2 GREEN：`prepareClaimedPipelineTask` 的 source 分支；`consumeClaimedExecution` 与授权安装/head 核对改为接收范围参数（CR 号、CR 根、工作目录），节点路径传原字段，行为不变
- [x] 10.3 `selections.json` 新增 `rec-010`；变异检查（去掉 CR 身份冲突检查、把范围写回 `Pipeline*`）使测试红

## 11. tools 成对 change：inspect 补 authority 字段（P0，S11，D1.9；🔒 tools 修改须其自身 Gate，**并入** `node-trust-root`）
- [x] 11.1 tools 的 `node-trust-root` 修订：proposal/design/canonical spec（REQ-NTR-005、SC-NTR-009/010）/test-plan（TC-NTR-010/011）同步，Gate 1/2 由用户独立确认，Gate 3 实现后重签；纯插入补 `targetSpecId`/`targetVersion`，金样本同步（详见 tools 记录的 tasks.md）
- [x] 11.2 multica `cr-workspace.mjs` 写有效 `target-version`（`x.y.z`）；`crctl-stage` 的「只许增行」检查对覆盖版（含 node-trust-root 与 B2 两处插入）继续成立
- [x] 11.3 补完后重跑 A0，替身 source→writer 越过 `inspectPipelineAuthority`

## 12. 预消费信任根按 task generation 取子目录（P0，S12，D1.10；Gate 2 重审通过后才写代码；须在 A0 重跑与 5 之前）
- [x] 12.1 RED：`TestTC_REC_001` 增一个子用例——同 workspace 内两个不同 generation 的预消费，传给 crctl 的 `--trust-root` 不同，且各自等于该任务的 `ExecutionTrustRoot`；同一 generation 重复准备得到同一个根
- [x] 12.2 GREEN：`ExecutionTrustStore.Generation(taskID, runtimeID, dispatchedAt)`；`prepareClaimedPipelineTask` 在 `OpenExecutionTrustStore` 之后调用并改用返回的 store；`TestTC_REC_009` 子用例的期望值由 workspace 根改为该任务的 generation 根（断言意图不变）；`OpenExecutionTrustStore` 与其既有测试不改。变异检查一项：生产调用点还传 workspace 根，则新子用例红
- [x] 12.3 A0 重跑：source 与 writer 均预消费成功（真实 crctl），writer 越过预消费；失败则按止损点停下汇报（2026-11-15 第 20 次零模型运行、生产形态：`PASS stub-run source … consumption=1 effect=1`；`PASS stub-run writer-advances advances=2 consumption=1 effects=1/1/1 status=tech-design-review-pending trust_root_seen=d1640985 workspace_arg=operational`；末尾仍是 `INCONCLUSIVE stage=reviewer`、exit 2）

## 13. B4：agent 内 crctl 的 git 不经 shim（ADJ-A0-3、ADJ-A0-4；依赖 tools `node-trust-root` 的 S5；无 multica 生产代码；不改受审文档）
- [x] 13.1 `crctl-stage.mjs` 覆盖清单加入新文件 `lib/git-shim-path.mjs`（HEAD 中不存在才允许），`crctl-stage.test.mjs` 增断言；tools S5 实现后做（2026-11-15 完成：`ADDED_FILES_REL`、HEAD 已有则抛错、返回 `addedFiles`；`crctl-stage.test.mjs` 10/10；宿主只读演练真实 tools 工作树，物化副本 `crctl.mjs help` 退出 0）
- [x] 13.2a 替身 pi 的 what-if 去掉，回到生产形态（shim 在 PATH、无规则变量、crctl 不被外部处理 PATH；单元测试层面，real-run 脚本 117 tests / 114 pass / 0 fail / 3 skip）
- [x] 13.2b 在真实整栈上重跑 A0 的 writer 两次 advance（用户已同意：2026-11-15 第 20 次运行，生产形态 shim 在 PATH、无规则变量、由新 crctl 自行剥离；结果同上 12.3）
- [x] 13.3 勾 12.3（已勾）；继续 reviewer、人工门、重启去重阶段（2026-11-15 全部实现并在 A0 与取证中通过）
