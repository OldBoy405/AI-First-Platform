# AIFI-45 M12 — nodeId 执行绑定与独立 review

> 最新状态：**M12两动作验收完成，未提交/部署/执行真实CR/清理PG。** 原独立Spec复核P1/current UUID与P2/known selected completed execution identity已闭合，Standards无硬P；只闭合M12绑定动作，不宣称CP001/002/004所有语义/历史作者证明或M13–15/M20链路完成。

## Main 最终验收（以下保留作者过程）

- 作者真实原行为RED→GREEN，P1架构同UUID与P2改名/实际legacy self-review反例均实际失败后修复；最终TC selection **3父+9子/12RUN，全PASS/0skip**，原相关83RUN全P；原assert/70parsercases/427prefix与四生成物/tools073c…保持。
- Main独立完整governance **native0/38.092139600s、199父+186子PASS/1原LiveGitHubSKIP、386RUN/386完结、0FAIL/DBskip**；gencheck0/0.295488300s、vet0/0.487576000s、build0/3.441863300s；3594server/259tools源前后稳定。原生证据`%TEMP%/aifi45-m12-main-final/`，旧首版382与各RED分开保留。
- 最终LF：runner.go `98d7e2c61ea446e896286af7d8a9d603f778668a97c1a3f860266457074f845c`；runner_requirement.go `b3f350a90dbd0fe34ea88b4c6c725bc5955afacb72a3adbd69b96cca8bf8d407`；integration-test `3428f53f814646706a46bd06aa12d1b0e01a36ec2237bea891b271228073cfb9`。
- Standards/Spec最终独立delta均无新硬P，未亲跑suite。已知执行守卫沿既有同selected record/同run-node-attempt，不新forensic选择/账本，不改派旧任务；无authorqueue旧direct/adopt路径保原行为、历史产出身份未证明，本次不运行真实CR/存量接管；完整code walker/重入与全SC002仍后续验收。matrix actor kind/owns/can-call/forbidden由受控producer/digest证明，不捏造DB.Agent.kind或造第二matrix源；runtime检查真实Agent/runtime/节点Skill.enabled及Workspace一致。
- tasks两动作即时勾选、CUSTOM#141；下一步M13–15合并同域批次/逐步TDD/一次联合复核，不再重复整套规范与小步过程文档。

## 范围与冻结

- 唯一写域：`server/internal/governance/runner.go`、`runner_requirement.go`、`runner_integration_test.go`。未改 M20 状态机、`runner_requirement_entry.go`、generated/producer、handler/daemon、DDL/SQL、API/CLI flag、依赖或 tools。
- 四份生成物、`runner_requirement_registry.go`、`runner_contract_test.go` 均未改；实际 raw SHA-256 与 M11 冻结值一致，见文末。
- 本切片没有新增 StartCode/Writeback route/walker，也没有新增名称翻译、`SystemKey`、installer、大小写/双名 fallback 或运行时账本。

## 实现

1. **唯一节点绑定解析**：新增 `runner.go::resolveNodeExecutor`。键只来自 `node.Executor`，空值才按该 registry 的 `pipelineOwner`；随后 `agentByName`（同 workspace、未归档）、`checkExecutorAgent`（runtime）、`checkRequirementSkills`（该节点 ref 的 `Skill.enabled`）。human 节点直接失败关闭，不 lookup、不建 task。调用者、旧 `execution_context.executor_agent_id`、owner、Skill owner 都不是回退来源。未新增 DB `kind`/active/disabled 猜测：真实 Agent 身份由同 workspace 的 `agent` 行与已绑定 runtime 证明，逻辑 system owner 不会被创建成执行行。
2. **StartArchitecture**：保留真实 source task 校验；删除调用者 `checkExecutorAgent` + `checkExecutorSkills`。旧 `executor_agent_id` 仍按兼容语义写入运行上下文，但已不参与选人，也不批量改写旧 run。
3. **Architecture enqueue**：`enqueueNode` 不再解析 `executor_agent_id` 作为派发者；source task 仍独立读取，每个节点在入队时按本节点 registry executor 解析。对 `review-*` 节点，`checkIndependentReview` 先用 `reviewLoop.repairNodeId`（优先）或唯一 `repairRef` 定位作者节点，双方走同一 `resolveNodeExecutor`（含 runtime/Skill）比较当前真实 UUID；再查作者 nodeRun（同 run + 同业务 attempt）的**同一条 latestTaskState selected record**，若有 completed 作者 task 且其 `agent_id` 等于新 reviewer UUID，则失败关闭。非 `review-*` 的自测 loop（如 `write-test-report`）不触发独立 review 限制。已有 queued/running 仍走原 `latestTaskState` 等待分支，不改派。
4. **Requirement**：`resolveRequirementAgents` 改用 writer/review 两个精确节点的 executor 绑定；两次解析及节点 Skill 校验都成功后才比较解析出的真实 UUID，相同即 `RunnerErrAuthorityMismatch`。正常/恢复派发与 approval closing 节点均在 `enqueueRequirementNode` 按当前节点绑定解析，并复用同一 `checkIndependentReview`；不再使用缓存的角色 UUID 决定新任务执行者。旧 context 角色仍做一致性读取，但不再充当新执行者决策。`checkRequirementSkills` 同时要求 `skill.workspace_id = agent.workspace_id`；Builtin skill 在 DB 无行，不受影响。
5. **消费旧 review task**：`reconcileSkillTask` / `reconcileRequirementNode` 在 review 节点 completed 时，用同一 `selectedTask` 读取 review 实际 `agent_id`，并与同 run/attempt 的作者节点同 selected completed record 比较；相同则 `RunnerErrAuthorityMismatch` 停止消费，不重新派发该 task，也不因当前 Agent 改名/重解析误拒独立旧 task。
6. **删除 `checkExecutorSkills`**：生产代码无该函数；`executor_agent_id` 只剩兼容写入与注释。静态证据见 evidence `static-paths.log` / `review-fixes-actual/static-p2.log`。

## 测试与 fixture

新增三个实际命中 CP locator 的测试：

- `TestMBinding001`：coding registry 两个 `write-dev-tasks` 不同 nodeId；逐节点五字段 permission、默认 pipelineOwner、同 ref 不同 executor 的 helper 选择；再走现架构 `enqueueNode` 低级 seam，为两个确切 nodeId 分别建 nodeRun/task，断言 `NodeID`/`NodeRunID` 不同、执行者各自为 `dev-agent`，不新增 StartCode/walker。
- `TestMBinding002`：human 零 lookup/task；`system-orchestrator` owner 与 `dev-agent` executor 分离且不创建 system Agent；missing/archived/cross-workspace/runtime-unbound/skill-disabled/wrong-ref 失败关闭；独立 review 在两次精确 lookup 和两次 Skill 校验都成功后，以相同真实 UUID 被拒；**architecture** same-UUID 内部 fixture 把 review executor 指向 writer 的 `dev-agent`，并给 dev 授予 review Skill；不同 UUID 正例仍实际入队；另有：A 完成 writer task（queue agent=A）后 B 接 writer key、A 接 reviewer key（两 lookup/Skill 全成功）→ 新 review 必拒且 review task 增量 0；B≠A 的已完成作者 task 下 review 合法入队；真实 completed review queue 的 agent=A 且作者 queue=A 时 `Reconcile` 以 `RUNNER_AUTHORITY_MISMATCH` 停止消费，不改派/不改写该 task。
- `TestMBinding003`：caller 无任何节点 Skill 仍可 StartArchitecture；旧 `executor_agent_id` 与 registry executor 不同也不影响选人；已有 running task 不被改派；后续 review 使用独立 reviewer。

Fixture 语义修正（保留原断言）：

- `setupRunnerIntegration` 增种 `dev-agent` / `quality-reviewer-agent` 两个真实 Agent（复用测试 runtime），按 architecture registry 节点授予 Skill；旧 caller/source Agent 保持独立。
- fake enqueuer 现在按 `spec.ExecutorAgentID` 写队列，并在 cleanup 中按三个 Agent 清理 task/agent_skill/agent；`TestStartArchitecture...` 的重置由“只删 caller task”改为“删 source 以外 task”，因为任务现在归属于真实节点 executor。
- 未删除、跳过或弱化任何既有测试/断言。

## RED（真实行为失败）

测试文件不改，仅用保存的工作副本临时恢复 pre-M12 派发行为（旧 caller 全 Skill 检查、旧 context executor 派发、旧 `ownerOf` 角色解析）后运行同一选择，native exit **1**：

- `TestMBinding002/human_gate_enqueues_no_task`：write executor = caller `…045`，want registry `…051`。
- `TestMBinding002/review_refuses_the_author's_actual_UUID`：相同解析 UUID 未被拒。
- `TestMBinding003`：`RUNNER_SKILL_MISSING: executor agent missing skill: write-tech-design`，caller 仍被要求全部 Skill。
- 同轮 owner/human-node 子例也因缺少按节点绑定 seam 失败。

RED 为 2 个顶层测试、4 个子例失败；日志 `review-fixes/red-legacy.log`。随后恢复当前实现，测试未改。

P1 review guard 的独立 RED：保留当前测试，仅临时移除 `enqueueNode` 的 `checkIndependentReview` 调用，`^TestMBinding002$` 的 `architecture_review_refuses_same_UUID` 实际失败（`got <nil>`），其余子例通过；日志 `review-fixes/red-p1-architecture.log`。恢复后通过。

P2 known-historical execution RED：保留当前测试，仅临时移除 historical-author enqueue comparison 与架构 consume guard；`historical_author_UUID_refuses_renamed_reviewer` 实际入队、`legacy_review_task_by_the_author_is_not_consumed` 被消费并走到 `RUNNER_REVIEW_DELIVERY_MISSING`；日志 `review-fixes-actual/red-p2-known-author.log`。恢复后通过。

## GREEN 与回归

- M12 定向：native exit **0**；JSON **12 RUN = 3 顶层 + 9 子例 / 13 PASS event / 0 FAIL / 0 SKIP**；范围 `^TestMBinding00[123]$`，三个顶层名全部实际执行。
- 原相关回归：`^(TestRunner|TestStartArchitecture|TestEnqueuePipelineTask|TestRequirement|TestAIFI60)`，native exit **0**；**83 RUN = 63 顶层 + 20 子例，83 PASS，0 FAIL，0 SKIP**。包含既有 same-agent、resume/handover、human gate、attribution、repair loop 正例。
- `go vet ./internal/governance` 0；`go build ./...` 0；`git diff --check` 0。
- 生成一致性未重跑；四份 generated 文件与 M11 冻结 raw 哈希逐字节相同，故本切片没有新的 gen-check 证据，也不冒充。

## 哈希与冻结

| 文件 | M11 LF before | 当前 raw | 当前 LF | 行数 / 行尾 |
|---|---|---|---|---|
| `runner.go` | `3c7e58d1…117ac8f` | `79b93d2e…8f5e` | `98d7e2c6…845c` | 1505 / 全 CRLF |
| `runner_requirement.go` | `27fa7d14…e112` | `d3045433…04a9` | `b3f350a9…d407` | 722 / 全 CRLF |
| `runner_integration_test.go` | `5817850f…df7a9` | `002cf654…4b66` | `3428f53f…cfb9` | 1109 / 全 CRLF |

冻结文件当前 raw 哈希：

- `requirement_registry_gen.go` `90ee5d1f…8951`（M11 同）
- `gate_nodes_gen.go` `e9a923b2…00e`（M11 同）
- `code_registry_gen.go` `2a19bd87…e3e5`（M11 同）
- `writeback_registry_gen.go` `44819dcb…c242b`（M11 同）
- `runner_requirement_registry.go` raw `407434bf…4ec2` / LF `27fa7d14…e112`（M11 同）
- `runner_contract_test.go` raw `b92225ce…4b0d` / LF `5817850f…df7a9`（M11 同）
- SourceMeta/tools 未触碰。

## P2 实际产出身份 — 已最小实现（known execution guard）

- `selectedTask` 用原 `ORDER BY created_at DESC LIMIT 1` 同一 query 返回 `id/agent_id/status`；`latestTaskState` 是薄 wrapper，所有 state 读仍走这一条记录。没有 first/latest-completed、新账本或产出选择算法。
- `selectedAuthorTask` 用 writer 模板 node（reviewLoop `repairNodeId` 优先，无 ID 唯一 ref）找同 `run_id` + 同业务 `attempt` 的 author nodeRun，再读该 nodeRun 的同 selected record；只有 `status=completed` 才算真实作者证据。
- review 入队：当前 binding pair guard 保留；若有 completed author task 且其 `agent_id` 等于新 reviewer UUID，则拒绝。消费：review 节点 completed 时，将同 selected review task 的 `agent_id` 与同 selected completed author task 比较，相同则 `RunnerErrAuthorityMismatch` 停止，不消费、不改派、不改写。
- 无 author queue/nodeRun 证据时保持原行为：requirement 在 `requirement-reviewing` 直接派 review（无 writer task）、`recordEmptyFailedRun` fresh-run resume、projector adoption 均不破坏；这些路径不被声称为历史产出身份证明，也没有新增 fallback。**正常链具体分支**：CR 已处于 `requirement-reviewing` 时 `StartRequirement` 会直接派 review，这是现有正常入口，不是仅 old adopt；本轮按原合同保留。
- 测试使用真实 queue 落表（`pipeline_node_run_id` 关联），不以 fake context 的 `node_id` 代替 nodeRun；service 的 `context.node_id` 是模板 UUID，节点定位仍用 nodeRun 的模板 `node_id`/`pipeline_node_run_id`。

## 边界 / 未完成

- **已实现的是 known completed execution guard，不是完整历史身份体系**：只有同一 nodeRun 的 latest selected task 为 `completed` 时才比较真实 `agent_id`；无 author task/nodeRun（含 requirement-reviewing 直接恢复）保持原行为且不被证明历史产出。没有 first/latest completed、SourceTask、旧 executor 或当前 Agent 重解析作为作者 fallback；实际四阶段/SC002 历史闭环仍待后续 walker/恢复联调。
- M13 source 归因、completed source、issue/project/originator/accountable 校验未做；`SourceTaskID` 与 `ExecutorAgentID` 仍由既有 service SQL 分离。
- 未改派既有 queued/running；未新增 StartCode/Writeback walker；未证明 CP004/005/006、CP002/003 的完整业务闭环。
- 未勾选 M12.1/M12.2，未写 CUSTOM/tasks/phase-context/ledger，未 commit/push/deploy，未清理 PG。

## 证据

固定目录 `C:\Users\GOBAO\AppData\Local\Temp\aifi45-m12-evidence\`；本轮 review-fixes 写入新子目录，不覆盖旧证据：

- `review-fixes/green-p1-final.json`、`green-p1-final-stderr.log`
- `review-fixes/red-p1-architecture.log`
- `review-fixes/related-p1.log`
- `review-fixes/vet-p1.log`、`build-p1.log`、`static-paths-p1.log`
- `review-fixes/summary-p1.json`（目标为 `127.0.0.1:33551 / aifi45_test / aifi45`，run_id `aifi45-m10-repair-e4o5e8vm`；不记录 DSN/password）
- 旧 `green-final.*`、`red-legacy.log`、`related-regression.log`、`summary.json` 保留未覆盖。

**精确停点：** 等 Main 以当前工作树跑完整 governance + 独立两轴/ delta review；若整包或 review 暴露 M12 与既有恢复/角色语义冲突，用当前证据定位后最小修复，不扩大到 M13/M20 或新选择策略。DB 容器/卷与最终清理仍归 Main。
