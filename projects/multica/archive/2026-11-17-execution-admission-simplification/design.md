# 执行准入收缩为单一授权头判定，并让等待原因对人可见 - 技术设计

> 模型说明：`model_tiers.design=strong`（配置 `GB/qwen4-max` / max）。派发 planner 时该模型标识在子代理环境中不存在，按共享规则不换供应商、档位或模型，已回退由主会话（`GBClaude/claude-sonnet-5-5`，xhigh）撰写，**未升档**。代码事实由三份只读取证（C1/C2/C3）加一份补充取证（C4）提供，关键断言已由主会话抽查（见各处“抽查”标注）。

## Context

> 快照说明：本节与下文引用的文件行号、判定顺序（含 `WAIT_CONSUMPTION`/`WAIT_TRUSTED_T_COMMIT` 两步）均为**实施前 HEAD 快照**，用于描述被取代的旧准入链；实施后消耗/effect 两步已删除，当前判定见 `server/internal/governance/execution_admission.go`（head-only）。文件名以完整路径为准（`gate.go` 指 `execution_admission_gate.go`）。

- **目标仓**：`multica/server`（Go）。方案范围以 multica 为主，不改 tools 仓，不改 daemon 的预消费与 binding endpoint，不改签名信封，不改 consumption / effect 的写入路径。
- **威胁模型**（用户 2026-11-17）：不以防恶意任务为目标，但叫停、重复派发、串项目、旧证据推进仍须覆盖；敏感动作人工授权不动。
- **现状**：Runner 的四类受保护动作（节点置 passed、人工门通过、普通节点入队、requirement 节点入队）经 `decideUnderHeadLock` 汇入唯一的 `DecideAdmission` 调用（`internal/governance/execution_admission_gate.go:106`，抽查）。判定顺序为：头（`HEAD_UNAVAILABLE`/`HEAD_REJECTED`）→ 源任务当前 generation 的消耗回执（`WAIT_CONSUMPTION`）→ effect/verdict 链（`WAIT_TRUSTED_T_COMMIT`）（`execution_admission.go:116-210`，抽查）。拒绝时调用方不分原因码，统一把 `Reason` 写进 `pipeline_node_run.detail.runner.admission` 并以 `errAdmissionWaiting` 停止本轮，公开入口再把它转成 nil（gate.go:71、195-219）。
- **DAYA-5 的真实形态**：requirement run 由一个**普通 issue 任务**（源任务）发起，该任务不是 strict 任务，永远不会有 consumption 回执，所以第二步永久 `WAIT_CONSUMPTION`；而 CR 本身连授权头都没有，先停在 `HEAD_UNAVAILABLE`。resume 对两种情形都返回 200 + `run_id`。
- **C4 的关键事实**：只要 CR 存在初始 `stage='execution', decision='approve'` 记录，Runner 入队的节点任务被 daemon 认领时，服务端就会设置 `pipeline_execution_contract`，daemon 走 strict 路径：安装 grant、crctl 检查、对**该节点自身**预消费（`internal/handler/daemon.go:3186-3204`，抽查；`internal/daemon/execution_verifier.go:33-61,108-138`）。该链依赖 daemon 机上有 crctl 与 node 并设置 `MULTICA_CONTROLLED_SHELL_RULES`，且服务端 binding / consumption 端点（无契约时返回 503，抽查：`execution_binding_issue.go:130-133`、`execution_consumption.go:48-51`）已启用。**所以：节点自身的执行证据仍由 daemon 预消费产生；本变更摘除的只是 Runner 对“源任务”的消耗证明。**

## Decisions

### D1（C1）准入判定只看 CR 当前授权头

**方案**：`DecideAdmission` 保留现有头查询（不改）：
`cr LEFT JOIN approval_record ON a.id = c.execution_authorization_head_id AND a.workspace_id = c.workspace_id AND a.cr_id = c.cr_id`（`execution_admission.go:139-147`，抽查，范围限定本来就在联结里），然后：无头 → `HEAD_UNAVAILABLE`；`decision <> 'approve'` → `HEAD_REJECTED`；否则 `ADMITTED`。删除消耗回执查询与 effect/verdict 查询两步，删除 `AdmissionRequest.TaskID`、`AdmissionReasonWaitConsumption`、`AdmissionReasonWaitTrustedT`。叫停表达不变：撤销写一条 `decision='reject'` 的记录并以旧头为条件切换指针，下一次判定读到 `HEAD_REJECTED`（C1 取证第 7 项）。

**为什么**：源任务不是执行授权的主体——它是触发 run 的协调任务，非 strict 时根本没有消耗回执可言，要求它有等于要求所有协调任务都走 strict 链。节点自身是否被授权预消费，由 daemon 对该节点任务的 strict 路径负责（见 Context）。头的有效性本来就由“同 workspace + 同 CR 的 approve 记录”表达，且叫停与入队的序列化靠锁（D1 锁序不变），不需要再有证据链来承担。

**备选方案及排除原因**：
- 保留消耗回执、仅删 effect：仍要求源任务 strict，DAYA-5 一类协调任务永不满足，不解决问题。
- 把消耗/effect 检查改成“可选”（有则校验）：判定出现分叉，两条路径都要测、都要解释，违背“一个判定点”。
- 给 DAYA-5 补回执或伪造 effect：回执只能经 binding claim 端点追认（要求任务仍在 dispatched/running），已完成任务无法追认，且伪造回执违背完整性底线。

**锁序**：不变。准入先对 `cr` 行 `FOR SHARE`、再对 head 指向的 `approval_record` 行 `FOR SHARE`（`execution_head_lock.go:34-45`），撤销先对 `cr` 行 `FOR UPDATE`（`execution_authorization_revoke.go:206,273,295`）；入队在另一连接完成，共享锁持有至入队返回，是“线性化于撤销”而不是“同一原子步骤”（gate.go 文件头注释已如实写明，**保留这一说法**，不改成“原子”）。

### D2（C1）摘除后的遗留：调用方、`source_task_id`、旧表

**方案**：
1. `decideUnderHeadLock(ctx, ws, crID, taskID)` 去掉 `taskID`；`markNodeAdmitted`（gate.go:145-170 选 taskID 的逻辑）与 `passHumanApprovalNode`（gate.go:228-245）里**只为准入读取** `source_task_id` 的部分删除。普通/requirement 入队处（`runner.go:1068-1112`、`runner_requirement.go:609-691`）读取 `source_task_id` 是为了 `PipelineTaskSpec.SourceTaskID` 的来源归因（`service/task.go:386-429`），**保留**，其“run 上下文缺失来源任务 → `RunnerErrAuthorityMismatch`”的校验也保留。
2. `cr_execution_consumption`、`cr_execution_control_settlement`、`cr_execution_tool_verdict`、`cr_execution_tool_cursor`、`cr_execution_control_command` 的写入路径一律不动；它们另有非准入读方（activation 读回执并要求匹配 `execution_activation.go:166`；任务终态 fence 经 `terminal_claim.go:66`；敏感动作额度读 `sensitive_action` settlement `execution_control_policy.go:126,194`；合并 effect `execution_merge_effect.go:156,262`），不是悬空写入。准入摘除后它们不再被 Runner 准入读取，仅此而已。
3. `VerifyTrustedVerdictEffect` 及其测试不动（它在准入之外仍被直接测试和跨语言测试引用，且“不改 effect 路径”是 Gate 1 的约束）。
4. 已持久化的 `detail.runner.admission` 里历史值可能是 `WAIT_CONSUMPTION` / `WAIT_TRUSTED_T_COMMIT`；读面对 `admission` 字符串**原样透传，不做枚举校验**。

**为什么**：把“只服务准入”的读取删净，避免留下恒真/恒假的死路径；把有别的读方的部分留在原处，避免连带改写别人的保证。额度没有被误伤：consumption effect 明确“不预留预算”（`execution_consumption_effect.go:16`），敏感动作额度计的是另一种 `effect_kind`，“第 7 次不派发”在本仓 server 范围内未能确认其与授权 `repair_limit` 的完整执行链，本变更不碰它（取证第 4 项，**如实不承诺**）。

**行为变化（须在 Gate 2 明示）**：一个 run 的上下文没有 `source_task_id` 时，人工门与节点置 passed 不再因“缺来源任务”返回 `AUTHORITY_MISMATCH`；入队路径的该校验仍在。

**备选方案及排除原因**：
- 整体删除 `source_task_id` 的校验与字段：归因读方仍在，删除属于顺手重构且改变入队语义。
- 把五张旧表一并清理：违反“不改写入路径”的约束，也与 daemon 预消费、敏感动作额度相冲突。

### D3（C2）默认部署内置默认契约，签名密钥仍是部署前提

**方案**：新增 `governance.DefaultExecutionContract()`（`PolicyVersion = authorized-execution/v1`；`PolicyDigest`、`TemplateDigest` 为对两个固定标签字符串做 SHA-256 得到的小写十六进制，标签写在源码里并注明“改动会使既有授权头失效”）。装配规则只在 `cmd/server/router.go` 里 `approvalSvc` 创建之后判断一次：

```
opts.ExecutionContract != nil            → 现状不变：approvalSvc 为 nil 则拒绝启动；否则 SetExecutionContract(显式契约)
opts.ExecutionContract == nil 且 approvalSvc != nil → SetExecutionContract(DefaultExecutionContract())
opts.ExecutionContract == nil 且 approvalSvc == nil → 现状不变：功能关闭（503），不启动失败
```

`LoadExecutionContractManifest` 与 main.go 里“两个 flag 必须同配、半配置启动失败、字节被 SHA-256 钉住”的行为**一字不改**；`governance.ExecutionContract` 的 `validate()` 照常校验默认值。

**为什么**：
- 签发端点的前置里，契约只是其中一项（C2 取证第 5 项）；契约之外还必须有签名服务。密钥无法有默认值，所以不能把“无密钥”也变成成功——那样会让默认部署启动失败（router 对“有契约无签名服务”拒绝启动，抽查）。把默认注入限定在“签名服务已存在”之后，两条既有 fail-closed 都保住。
- 现有“显式 manifest”机制保留为需要钉死策略/模板的部署的升级路径；默认值面向“不传参数的默认部署”。
- crctl 侧**未发现**按本地策略/模板内容重新计算这两个 digest 的链（它计算的是别名 `tools_digest`），两值只要在“人类请求 → 签名 grant → challenge → binding → consumption/activation”各环节一致即可（C2 取证第 1、2 项）。但“生产真实部署值与由谁填入”**未确认**，所以实施的第一步是一次性环境联调（见 Risks）。

**备选方案及排除原因**：
- 让 `docker/entrypoint.sh` 转发 `$@` 或读环境变量转成 flag：仍要每个部署自己生成 manifest 并算 SHA-256，也就是现在卡住的那件事；还要改上游文件 entrypoint 与 compose。
- 把默认值放进 loader（空/空即返回默认）：会推翻 `execution_contract_manifest_test.go:24-46` 的“空/空返回 nil”并让“完全没配”与“配了默认”无法区分，破坏装配层对三种情形的清晰判断。
- 从迁移或 DB 里派生：要新增存储与读取，没有需求支撑。

### D4（C2）请求体的三个契约字段改为可省略

**方案**：签发请求里 `policy_version / policy_digest / template_digest` 三个字段**省略或为空时取部署契约的值；给出时必须与部署契约逐一相等**，格式合法但不等仍返回 409 `EXECUTION_CONTRACT_MISMATCH`；格式非法（非字符串、非小写 64 位 hex）在契约比较之前先按 `EXECUTION_SOURCE_INVALID` / `EXECUTION_SCOPE_INVALID` 拒绝，不被补齐为默认值（`execution_authorization.go:259-265,323-366`、`execution_authorization_http.go:343-366`）。填充必须发生在构造签名 payload 与冻结来源之前，使“签名 payload 里的值 / 冻结请求 / 部署契约”三者一致。其他校验（未知字段、重复键、scope、验收充分性）不变。

**为什么**：当前三值由请求方自带，而生产里没有任何客户端知道它们（“谁填入”未确认）。只在服务端放默认值而请求仍要求带值，默认部署照样 409。省略即采用部署值，是让“不传参数”真正成立的最小改动，且不放宽比较：显式给错值仍被拒绝。

**陷阱（须由测试覆盖）**：head 读取时服务端会把 payload 里的三值与**当前部署契约**比较，并把 scope 字段与冻结请求逐项比较（`execution_authorization_head.go:77-129,135-171`）。如果填充晚于冻结，head 会在签发之后读成 409 `EXECUTION_AUTHORIZATION_HEAD_INVALID`。另外已有的重放判定按原始请求字节匹配（`execution_authorization_http.go:137-165`）：原请求省略字段、重放也省略则一致；一方带值一方省略通常视为不同请求，仅当显式请求的字节恰好等于补齐后的字节时才被视为同一请求（可接受，不另做规范化）。

**备选方案及排除原因**：新增 GET 契约端点让客户端先读再回填——多一个端点、多一次往返、仍要求客户端实现；放弃比较（服务端不看请求值）——放宽了现有校验，且无理由。

### D5（C3）状态由“运行状态 + 前沿节点 + 最新任务”推出，等待原因只在无活动任务时采信

**方案**：新增只读函数 `progressOf(ctx, runID)`（新文件 `internal/governance/pipeline_progress.go`，fork 独有，避免上游冲突），规则：

| 条件 | `state` | 附带字段 |
|---|---|---|
| `pipeline_run.status = completed / failed / cancelled` | 同名 | `failed` 时带前沿节点 `runner.error.code`（若有） |
| `status = waiting_approval` | `waiting_human` | `node_id` |
| `status = running`，前沿节点（`status='running'`，取 `seq, attempt` 最大者）最新任务为活动态（`queued / deferred / dispatched / waiting_local_directory / running`） | `in_flight` | `node_id, attempt, task_id, task_status` |
| `status = running`，前沿节点无活动任务且 `runner.wait_reason` 非空 | `waiting` | `node_id, attempt, wait_reason`；`wait_reason=admission` 时再带 `admission`（原样字符串）；有最新任务时带 `task_status` |
| 其余（`running` 但无前沿节点，或前沿节点无活动任务也无 `wait_reason`） | `idle` | 空；含义是“当前没有记录任何阻塞或在途工作”，不等于已推进 |

最新任务按 `created_at DESC` 取（`runner.go:1462-1488` 已有 `selectedTask` 同口径）。

**为什么**：`requirementNodeOutcome`（`runner_requirement.go:433-485`）只按任务分类，不读 node 状态与等待信息，且“无任务”既可能是等待、又可能是人工节点或 projector 直接写 passed 的节点（取证 C3 第 3、8 项），**不能复用**。`runner` 子对象会残留旧值——入队成功不清理 `wait_reason`、人工 pass 也不清理（`runner_requirement.go:674-699`、`gate.go:224-260`）——所以不能仅凭 `wait_reason` 断言“正在等待”；推导以节点与任务的**事实**为准，`wait_reason` 只在前沿节点既 `running` 又无活动任务时才作为原因展示，残留标记在已入队或已 passed 的节点上不会被采信。`progressOf` 与具体 pipeline 无关，只读 `pipeline_run / pipeline_node_run / agent_task_queue`，因此 requirement 与 architecture 共用。

**备选方案及排除原因**：
- 在 `reconcile` 过程中收集等待结果并返回：`errAdmissionWaiting` 的设计就是把等待转成 nil 以免被当失败，改它会碰到所有 walker 的返回契约；而且无法服务只读状态。
- 入队后清理 `wait_reason` 以便直接读它：改了写路径，需要为每个写入点补测试，而事实推导无需改写路径即可正确。
- 新增 `waiting_reviewer / waiting_admission` 等枚举：新状态与新错误码，Gate 1 明确不做；`wait_reason` 原样透传即可，调用方不需要我们翻译。

### D6（C3）回执与读面形态：只增不改

**方案**：
1. **回执**：requirement 的 `POST .../pipeline-runs/requirement`（resume）与 architecture 的 `POST .../pipeline-runs`（start；architecture **没有单独的 resume 路由**，同形回执在 start 上，抽查取证 C3 第 1 项）在原有 `run_id`、`changed` 之外新增 `progress` 对象（D5 的字段，空值省略）。`changed` 语义不变（它是“分配/恢复阶段的写入结果”，不是是否入队）。`progressOf` 读取失败时只记日志、不让请求失败、**省略** `progress`——这时 run 已经提交，读失败不等于未启动，也不能装成已推进。
2. **只读读面**：`GET /api/workspaces/{workspaceID}/pipeline-runs/{runID}`，返回 `run_id, pipeline_id, cr_id, status, progress`，挂在 `RequireWorkspaceMember` 组内（成员级口径，与 `GET /api/projects/{id}/gates` 一致；task token 须匹配其绑定 workspace），与 Runner 开关同开同关。run 不属于该 workspace 返回 404。
3. **CLI**：`multica cr pipeline status --run <id>`，用普通客户端认证（不加 `mat_` 前缀限制，因为它是成员级只读）；`start / resume / status` 的 table 输出新增 `STATE`、`REASON` 两列，JSON 输出透传原 map（该 CLI 本来就解码到 `map[string]any`，对新增字段天然兼容，`cmd_cr_pipeline.go:171-190,224-247`）。

**为什么**：现有 CLI 与 start 路由只认 `mat_` 任务令牌，说明回执的直接读者是协调 agent——DAYA-5 就是协调 agent 看到 200 就认为已推进。把状态放进回执，是对症的最小改动。现有只读面 `GET gates` 只给最新周期的节点状态和原始 `detail`，没有 run ID、run 状态、任务状态（取证 C3 第 4、5 项），不足以回答“这次 resume 之后到底发生了什么”，所以补一个按 run ID 的读面；它复用 D5 的同一函数，不新增表。

**备选方案及排除原因**：把 `progress` 并进 `changed`（改语义破坏兼容）；只加回执不加 GET（无法在 resume 之外查询，也无法验证“等待态不被呈现为已推进”的持续性）；GET 仅限 task token（人也要看，且 `gates` 已是成员级）。

### D7 测试改写原则：保证→用例，不按错误码一一对应

按受保护动作 × 五类保证（无头 / 有效头 / 叫停 / 跨范围头 / 幂等）建矩阵，改写后每格至少一个用例。**现有测试里没有“Runner 准入对指向其他 workspace/CR 的头”的专门用例**（取证 C1 第 5 项：`ATB_001` 的 foreign workspace 指任务，`ATB_002` 的 other CR 指回执），属于需要**新增**的覆盖，不能只靠改写。

## 保证 → 检查映射

| 保证 | 由什么支撑 | 如何观测 |
|---|---|---|
| G1 仅人类 owner/admin 的当前授权可启动实施 | 签发端点前置条件不变：认证、task-token/cloud-PAT 拒绝（403 `EXECUTION_HUMAN_SOURCE_REQUIRED`）、owner/admin（403 `FORBIDDEN_AUTHORIZER`）；D1 判定读 `approve` 头 | 端点测试；判定测试“无头不放行” |
| G2 范围正确、叫停后不再派发 | 头联结限定 workspace + cr（现有）；叫停 = reject 记录 + 指针切换；锁序（D1） | 新增“跨范围头=无头”用例；既有 `TC_REC_006`、`AdmissionGateLockBlocksRevocation` |
| G3 敏感动作人工授权不放宽 | 不触碰 `execution_sensitive_action.go` 与额度路径 | 既有敏感动作测试不改且全绿 |
| G4 派发幂等、旧证据不推进 | 活动 run / 活动节点任务部分唯一索引（迁移 670/671）；Runner 自身的 `projection_stale`、`review_evidence`、`authority_postcondition` 后置条件；**准入不再承担“旧任务证据”这一职责**，这部分由节点自身的 daemon 预消费与上述后置条件承担 | 既有 `TestRequirementResumeIsIdempotent`、`runner_requirement_test.go` 投影相关用例；重复 reconcile 行数断言 |
| G5 等待可见带原因 | D5 + D6 | 回执与 GET 的状态用例（见下） |

## Architecture

```
resume / start  ──►  StartRequirement / StartArchitecture ──► (提交) ──► coordinate ──► reconcile
                                                                           │
                                          受保护动作 ×4 ──► decideUnderHeadLock ──► DecideAdmission
                                                                           │            │ 仅读 cr→head(approve?)
                                                          拒绝：写 detail.runner       │ [D1: 不再读消耗回执/effect]
                                                          {wait_reason:admission,      ▼
                                                           admission:<Reason>}      ADMITTED → 入队/置 passed
                                                                           │
     回执/GET ◄── progressOf(runID) ◄── pipeline_run + pipeline_node_run + agent_task_queue（只读，D5）

签发：POST /crs/{id}/execution-authorization
      approvalSvc(签名密钥) ── 存在且无显式 manifest ──► DefaultExecutionContract()（D3）
      请求三字段省略 ⇒ 取部署契约；给出 ⇒ 须相等（D4）

节点任务被 daemon 认领（不变）：有初始 approve 记录 ⇒ strict ⇒ crctl 检查 + 该节点预消费（binding/consumption 端点需契约，D3 使其默认可用）
```

## 影响面与测试改写清单

按文件::函数，**实施前以 `rg` 重新核对**（行号为取证时读到的）：

| 类别 | 用例 | 处理 |
|---|---|---|
| 只固定被移除语义 | `execution_admission_test.go`：`TestAdmissionDeciderWaitsForCommittedConsumption`（无回执/缺链/cursor 覆盖/最终准入，含无头、拒绝头、无效输入）；`execution_admission_task_decider_test.go`：`TestTC_ATB_001–004`（任务/代次、其他 CR 回执、缺链组件、effect/scope/digest；004 同测无头与拒绝头） | 改写为“头判定”表：无头 / 拒绝头 / 有效头无回执即 `ADMITTED` / 跨 workspace 或 CR 的头=无头 / 无效输入；与消耗、effect 相关的断言整段删除 |
| 混合（保留非准入断言，仅改前置） | `execution_admission_task_binding_test.go`：`ATB_005–007`；`execution_admission_task_discovery_test.go`：`ATB_008–010`；`execution_admission_gate_test.go`、`execution_admission_enqueue_test.go`、`execution_admission_requirement_enqueue_test.go`、`execution_admission_human_gate_test.go`；`execution_consumption_effect_test.go`：`TC_CE_001–004`；`cmd/server/execution_run_003_test.go`：`TestTC_RUN_003` | 去掉“先提交消耗再放行”的前置；等待用例改为“无头则等待 → 签发头后放行”；保留“重复 passed 不改行 / approval id / 入队 agent·issue·context / 重复 wake 不重复派发”等断言；`CE_*` 只保留链绑定、回滚、跨 CR 隔离、重放不重复写链，删去其中的准入断言 |
| 独立保护，不改 | `execution_revoke_resume_test.go`（`TC_REC_006`）、`execution_admission_lock_test.go`、`execution_admission_cleanup_test.go`、`execution_admission_failure_branch_test.go`、`admissionguard_test/decider_test.go`、`runnerquery_test/admission_cleanup_test.go` | 仅在编译需要时删去 `TaskID` 实参 |
| 另一条路径，不改 | daemon `execution_preflight_test.go`、`execution_node_preconsume_test.go`（daemon 启动前回执要求） | 不动 |
| 新增 | 判定：跨 workspace/CR 头；C2：默认契约三种装配情形、省略字段签发后 `GET head` 仍有效、显式错值仍 409、显式 manifest 优先、半配置仍启动失败（既有）；C3：`progressOf` 全状态表（含残留 `wait_reason` 不被采信、人工节点、projector 直接 passed 的无任务节点、`failed`/`cancelled`、旧历史 `WAIT_CONSUMPTION` 字符串透传）、回执含 `progress` 且 `run_id/changed` 不变、GET 的成员/非成员（404）/跨 workspace 任务令牌（403）、CLI `status` 与 table 列 | 见 test-plan |
| 测试登记与驱动（Node） | `scripts/aifi45-disposable/selections.json`（及 `selections.baseline.json`，用途 Phase 3 先核实）：现有 `atb-001..010`、`run-admission-support`、`m005-consumption-effect` 的 `run` 正则含将被改写或删除的测试名，**改名或删除测试必须同步改选择，否则对账报“零匹配/名称不存在”**，因此改写时**优先保持函数名**；新增选择 `ath-head-matrix`、`ath-lock-revoke`、`ath-discovery`、`ath-source-task`、`run-003`、`run-default-contract-issue`、`run-default-contract-wiring`、`run-authz-boundary`、`run-requirement-shape`、`ewv-progress`、`ewv-receipt`、`ewv-route`，均带 `expected` 名单。`scripts/aifi45-real-run/{stack.mjs,run.mjs,config.mjs}` 增加 `--default-contract`（不生成 manifest、不传两个 flag、请求省略三字段）及其 `stack.test.mjs` 装配断言；该驱动现有场景只有 architecture，requirement 流水线明确不在其范围内 | 见 test-plan |

代码注释一律英文；`execution_admission.go` 与 `execution_admission_gate.go` 文件头里描述“两个事实”的段落随语义改写，保留“不改成原子”和“不 gated 的路径”两段如实说明。

### 被取代与被修改的基线条款（交付时人工原位合并，基线是累积文档，不得整份覆盖）

| 基线条款 | 处理 | 本变更对应 |
|----------|------|------------|
| `admission-task-binding` SC-ATB-001～004（锚点 task 与 generation 的回执/effect 准入） | 取代 | SC-ATB-101～104 |
| SC-ATB-005～007（按动作取锚点 task） | 取代 | SC-ATB-101、102、108 |
| SC-ATB-008～009（路由提交后不自唤醒；发现路径推进；重复发现不重复派发） | 修改：语义由“消费提交”换为“授权头签发” | SC-ATB-106、107 |
| SC-ATB-010（同 generation 重放与新 generation） | 修改：保留写入语义，删去“准入随之 WAIT_CONSUMPTION/ADMITTED” | SC-ATB-109 |
| `authorized-runner` SC-RUN-003 的触发条件 | 修改：“锚点 task 的回执或 effect 尚未提交”改为“头有效即放行”；其余 AND（真实 daemon_token、project/resource 投影、verdict 验签与绑定）原样保留 | SC-RUN-101 |

### 提案成功标准第 8 条的证据拆分（偏离提案措辞，须 Gate 2 确认）

提案第 8 条要求“在获授权的一次性环境中，用与 DAYA-5 同形的 CR 完成一次真实验证，writer 入队并推进到 review-requirement 派发”。真实运行驱动现只有 architecture 场景，requirement 流水线明确不在其范围内，为它新增真实 daemon 场景属于扩大范围。因此拆成两项证据：**TC-RUN-106**（requirement 形态、真实授权路由与默认契约、源任务从未消费、writer → reviewer，DB 集成，无 daemon）和 **TC-RUN-105**（默认契约下 architecture 的 stub 场景，真实 server + daemon + crctl，验证 daemon strict 链与 digest 一致）。两者合起来覆盖该条的两半，但**不等同于一次 requirement 的全真实验证**；若要严格满足，需另加 requirement 的驱动场景，请在 Gate 2 裁定。

## Risks / Trade-offs

| 风险 | 缓解措施 |
|---|---|
| 准入不再校验源任务消耗与 effect，不再防“Agent 谎报已消费或借用他任务证据”（取代已批准的 M005 信任调整） | 用户已明确接受；节点自身的 daemon 预消费仍在；敏感动作人工门与独立 reviewer 保留；归档变更与既有绑定不改 |
| 摘除后 daemon strict 路径成为新的“最先卡住”的环节：节点任务需要 daemon 机有 crctl、node、`MULTICA_CONTROLLED_SHELL_RULES`，缺失时 daemon 报 `PIPELINE_CRCTL_UNAVAILABLE`（C4 第 5、6 项）。这**不在本变更范围内**，但在成功标准 #8 的关键路径上 | D5 让任务 `failed`/`task_status` 可见而不是静默；成功标准 #8 在一次性环境按真实 daemon 配置跑通；若失败，停止并回到用户裁定（可能另起 change），**不承诺“补好授权头就能跑通”** |
| 默认契约使 head / revoke / binding / consumption / activation 端点在**所有**有签名密钥的部署里默认启用（此前无契约一律 503） | 威胁模型下可接受；仍需认证与 owner/admin；列入 Gate 2 待用户确认；README/部署说明不新增（不扩大范围）但在 CUSTOM 台账行写明 |
| 默认 digest 与 tools 侧是否一致仅静态推断，未经实机联调 | Phase 3 第一个切片：一次性环境里让“签发（省略字段）→ head → binding → crctl 检查 → consumption”按默认值同跑；不一致则停下复核 D3/D4，不继续堆实现 |
| 默认标签字符串一旦发布即成为冻结协议常量（改了会让既有头 409） | 常量旁写明；测试固定其字节值 |
| 请求字段可省略后，重放判定对“带值/省略”不等价 | 视为不同请求，409 冲突可接受；测试固定该行为，不另做规范化 |
| 测试大量断言旧原因码，改写时易误删对叫停、跨范围、幂等的覆盖 | D7 矩阵 + 新增跨范围用例；改写前后统计各格用例数写进 test-report |
| `detail.runner` 残留值导致状态误报 | D5 以事实推导、残留标记不采信；用例专门覆盖 |
| `shell_issue_id` 缺失（CR 注册后未显式 bind）可能不止 DAYA-5，未核实占比 | 不改绑定流程；签发端点保持 409 `EXECUTION_SCOPE_UNRESOLVED` 的明确错误；占比核查需另行授权 |
| `CUSTOM-LEDGER.md` 相对 HEAD 已有他人未提交改动；multica 工作树脏 | 台账只做定点追加（新 `#N` 行），不整文件覆盖；因其已含无关差异，**不放进证据计划的 inputs**（避免指纹混入无关改动），台账登记改在交付评审时逐行 diff 人工核对；提交前逐文件列清单，仅含本变更文件。Phase 3 前先按台账“行模板”核对变更标识格式是否接受 STDD change 标识，不接受则停下确认，不编造 CR 身份 |

### 经验库交叉检查（Step 2，go 经验 7 条中命中 3 条）

| 经验 | 在本变更的落点 |
|------|----------------|
| EXP-2026-0009（给公共入口改签名后只按包 grep 迁移，跨包测试漏迁） | 删除 `AdmissionRequest.TaskID` 与 `decideUnderHeadLock` 的 `taskID` 形参会波及 `cmd/server`、`admissionguard_test`、`runnerquery_test` 等跨包调用点：Phase 3 先全仓 `rg` 列调用点再改，以 `go build ./... && go vet ./...` 为闭合证据 |
| EXP-2026-0008（锁序测试只在锁全取完后才探测） | D1 不改锁序，但 TC-ATB-102 沿用既有锁用例，不新增只在末尾探测的锁测试；任何新增锁相关用例要在获取过程中途探测 |
| EXP-2026-0005（复制出来的身份检查只测一个失败条件） | TC-ATB-101 的“跨范围头”把 workspace 不同、CR 不同拆成两个独立变体，逐个断言，不合并成一个泛化的拒绝用例 |

## 待用户确认（Gate 2 一并审）

1. **D3 默认启用面**：有签名密钥的部署默认启用授权/binding/consumption 等端点，是否接受。
2. **D6 读面口径**：`GET .../pipeline-runs/{runID}` 为成员级可读，是否接受（与 `GET gates` 一致）。
3. **D2 行为变化**：run 缺 `source_task_id` 时，人工门与节点置 passed 不再报 `AUTHORITY_MISMATCH`，是否接受。
4. **C4 依赖**：daemon strict 路径与 crctl/node/`MULTICA_CONTROLLED_SHELL_RULES` 不在本变更内；成功标准 #8 若因此失败，是否同意“停下回来裁定”，而不是在本变更里顺手放宽 daemon。
5. **Phase 3 前置**：需要你授权一次性数据库实例（`run-selection.mjs` 自建 podman 实例）与 `scripts/aifi45-real-run` 驱动（自建隔离栈）；不触碰现网 Podman 库与现网 daemon。
6. **成功标准第 8 条的证据拆分**：同意 TC-RUN-105 + TC-RUN-106 的组合，还是要求另加 requirement 的真实 daemon 驱动场景（扩大范围，估计需要新场景脚本与 stub 流）。
