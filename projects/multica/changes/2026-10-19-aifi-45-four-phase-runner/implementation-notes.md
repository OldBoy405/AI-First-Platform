# AIFI-45 multica — Phase 3 只读核实与接口细化

> 当前没有multica业务改动、DB连接或测试结果。这里细化已批准L2的未定字段，不新增产品能力或授权；以tasks/slices依赖顺序实施。

## I1 可选目录快照字段（确定命名，行为未实现/未验证）

采用同一HTTP/WS字段 `local_directory_snapshot`，形状：

```json
{
  "local_directory_snapshot": {
    "workspace_id": "authenticated-workspace-uuid",
    "daemon_id": "authorized-runtime-daemon-id",
    "resources": []
  }
}
```

- 成功非空：替换该workspace+daemon的资源投影；成功`resources: []`：移除该身份投影。
- 外层省略/null/查询失败：不清空旧投影；资源查询失败不吞掉已领取actions。`resources`缺失/null或非法身份不能伪装成成功空快照。
- JSON身份来自服务端已授权runtime/lease；不能取客户端自报、PAT下可能为空的ClientIdentity.DaemonID，或把resource/project UUID当workspace UUID。
- 不新增schema/endpoint/能力开关；不恢复MULTICA_CR_WORKSPACES来源。根采集、定位、settle、pending/ack共用此来源；路径合法性与KB识别仍由原验证流程决定。

这只是原可选快照合同的命名与空值表达落定，不改变Gate2已确认的信任、替换/保留语义。B-TRANSPORT的命名部分据此解除；实现前仍须核对既有类型复用与HTTP/WS对等测试，不把本记录当测试已通过。

## I2 已核实的资源/传输事实

以下路径相对multica/server，由主会话委派的只读Agent核实：

- `internal/handler/project_resource.go::ProjectResourceResponse`现有字段为`id/project_id/workspace_id/resource_type/resource_ref/label/position/created_at/created_by`。`id`是资源UUID，不是workspace。
- 源码没有`knowledge_base`资源枚举；本需求的知识库根来自项目`local_directory`资源，经既有路径/KB账本识别后采用，不能造一个新的资源类型。
- `resource_type=local_directory`的`resource_ref`必含`local_path/daemon_id`，可含`label/execution_mode`。快照元素复用既有资源表示/转换，不另建根配置事实源；最小共享wire类型或现有类型alias的具体代码落点在实施切片确定，不复制第二套业务验证。
- `pkg/protocol/messages.go::DaemonHeartbeatAckPayload`与`internal/handler/daemon.go::DaemonHeartbeat`手工HTTP响应须同源携带快照；daemon HeartbeatResponse已是ack别名，两传输共用handleHeartbeatActions。
- `internal/handler/daemon_ws.go::buildDaemonWebSocketIdentity`已查询runtime.daemon_id，但`internal/daemonws/hub.go`的RuntimeLease/RuntimeLeaseState/NewRuntimeLease/Snapshot尚未保存/透出它。
- 资源查询同时约束资源和项目workspace以及ref.daemon_id；workspace请求按X-Workspace-ID分组，不改共享client的全局身份。

## I3 周期回调预算（事实与未决项分离）

- 已有`sweepInterval=30s`；offline/reconnect/queued批量各500，chat批量100。主轮目前无统一timeout，不能说现有Runner已经有界。
- 独立小时GC已有500/15s/5s三个批量/轮次/操作量级；它们不是Runner当前预算，也不是已承诺恢复SLA。
- 继续使用原30s触发和既有Reconcile/重试预算；回调单飞、限批、公平续扫、逐run隔离。不得起第二套扫描/重试系统，不用新goroutine泄漏绕过不可取消锁。
- 具体batch与ctx预算留隔离测试实测；可借已有量级作为试验起点，但未测前不写正式常量或解除相应预算阻塞。取消/锁清理必须有测试，不通过提高业务重试预算补偿慢轮次。

## I4 测试数据库是显式前置

- governance TestMain在DB不可达时exit0，包内纯函数case也可能全没执行；exit0不是通过证据。
- 本轮仅核实文件与源码，未读取环境文件中的凭据、未连接DB、未调用Docker服务；数据库可用性未知。
- 开工治理集成测试前必须明确获准的隔离且已迁移数据库、连接目标和实际case执行统计；禁止使用不明默认.env或共享/生产库。缺此条件按混合策略暂停询问，不做无意义绿灯。

## I5 四阶段消费链只读核对（T01实施期间；非平台通过）

核查Agent `01a153c5-f174-75ce-a57c-1b7f5e13d082`未改文件、运行生成器/Go测试或连接DB；已确认目标合同一致，无需另定schema/字段。

- `server/internal/governance/gen/generate-gate-nodes.mjs`目前只生成需求/设计，校验digest格式但不复算body；沿同一生成/check链增加代码/回写，保留原三个审批/评审投影，不给writeback造loop/gate。
- `runner.go::coreRegistry/coreNodePermission/coreNode`和`runner_requirement_registry.go`需要完整inputs、nodeId/executor、approvalPrompt/timeout/passCondition；当前固定4/6节点、ref唯一索引及owner派发均不适用于新合同。用nodeId验证精确非human覆盖、kind和各loop，重复ref合法。
- `PipelineReviewMaxAttempts/ReviewMaxAttemptsFromSnapshot`与handler的`hydratePipelineContextWith`还有两pipeline/单loop假设；只扩allowlist不会完成真实执行闭环。
- 已有`PipelineTaskSpec`区分SourceTaskID/ExecutorAgentID；继续使用，不能把调用者全集Skill权限或历史executor当新节点执行者。runtime实际Agent UUID隔离仍需后续验证。
- 生成头及CI目前指向tools `9d0a6a7fd7690c5e43b1dab829a20ff430ae9828`；生成器实际读working tree却用HEAD标头，`--check`还忽略该标头。未提交候选必须另留规范化内容哈希/实际body digest，不能以HEAD冒充完整候选revision，也不能覆盖存量run digest消除漂移；交付提交及CI pin对齐仍需后续人类授权。
- 现有Go测试中的部分fixture刻意改body而保留digest。是否复算、如何保持原始JSON序列化必须按批准信任边界实现，不得对丢字段的Go struct计算“等价”digest冒充源合同。
- 此 I5 为当时只读核对历史，不把这些事实或四个 PipelineIDs 当四阶段已接通；后续真实 M00 与授权见 M00-db-baseline.md / phase-context.md。

## I6 digest 的编译期与运行时信任边界（M11 实施细化，非新增能力）

- 依据：`canonical/specs/code/four-phase-runner-dispatch.yaml` 的 M-REQ-DISPATCH-003 / M-SC-DISPATCH-005、同名 agent CP005 与 `design.md` §digest。完整 `pipeline`、`pipelineOwner`、`nodePermissions` 的 canonical body 由 tools Node exporter 定义；M10 原 Node 编译链独立复算，必须对输入/执行/绑定变异敏感、CRLF→LF/键序稳定、顶层 input keys 不一致硬拒绝。
- M11 当前生产入口只消费编译产物 JSON 与其独立预期 digest；既有 req/arch parse 函数是本地受控入口，不是任意请求/DB 传入 registry body 的认证器。保留 schema/pipeline/envelope/expected-digest 校验，以及 run context 的 `template_digest` 身份/恢复校验；不得改成信任请求或持久记录中自报 digest，不覆盖旧 run digest。
- 不另写 Go canonicalizer，不对丢字段的 typed struct 计算“等价 SHA”。普通 Go JSON marshal 在 HTML、U+2028/U+2029、数字表示、UTF-16 键序等处不等同 Node；该近似不得用于诚信声明。若未来要开放任意 registry-body 输入，须先明确新增信任边界，不能借这次内部 parser 重构默认开放。
- parser 保留完整原始 wire envelope（`json.RawMessage`），typed inputs/nodes/permissions/loops 仅作派生视图，未知 raw 执行字段不能丢失；重复 ref 合法，权限以 nodeId 精确覆盖非 human，repair 显式 ID 优先、无 ID 仅唯一 ref 可用，coding 三 loop 与 writeback no-loop 原样保留。
- 当前 handler claim 只从 task context 和编译 registry 取 attempt bounds，尚缺完整 digest/node/membership carrier 校验；M14/M15 必须按 M-SC-DISPATCH-006 加负例后补齐，不以编译期 SHA 已验证替代载荷真实性。
- 现有 attempt-bound/handler 测试通过受控回调更换 body、保留 digest，是内部 policy fixture seam；不自动套新运行时 rehash 或删除它们求绿。是否需要更新 fixture，应以实际变化的受控接口为准，不能加生产豁免。
- M00 仅解除实跑阻塞：TC-MDISPATCH-007 对应 CP 仍要求后续 `TestMDispatch001/005` 的原生 PASS；193 父/75 子基线及唯一 GitHub 外部 skip 不算它们的实现验收。

## I7 M12/M13 既有执行者/来源接缝（只读 planner 结果，未实施）

- 只读会话 `01a15422-1fee-75ce-a57c-1b959fd544db` 核对：`runner_requirement.go::agentByName` 实际按 workspace + `agent.name` + 未归档查找；`046_agent_unique_name.up.sql` 已有 `(workspace_id,name)` 唯一约束，旧 importer“无唯一约束”注释不能当事实。解析器仍应要求唯一真实结果，不能选择首条或模糊名回退。
- 工具矩阵 actor key 与展示 name 不是同字段：`agents/_index.yml` 例如 requirement-writer/Requirement Writer、dev-agent/Dev Agent、quality-reviewer-agent/Quality Reviewer Agent。`aifirst/agent-import.mjs` 仍读 markdown frontmatter，但这几份当前 agent 文档已无 frontmatter；这是已证来源/命名契约缝隙，**不是已证部署数据库中名字错误**。M12 实施前须依真实既有导入/绑定合同处理，不能假造 slug/actor_key DB 字段、把 key 当 UUID、或发明名称猜测回退；保持五字段 nodePermissions 事实源。
- Agent.status 是工作状态，不是 active/disabled 枚举。复用 `checkExecutorAgent` 的同 workspace、未归档、runtime 检查及节点 Skill enabled 约束；运行时作者 UUID 与 reviewer UUID 必须不同，human 不派发 task。不用调用者全 Skill、历史 executor 或旧绑定缓存作为新节点执行者回退，不改派已有 queued/running task。
- `service.PipelineTaskSpec` 已分离 SourceTaskID/ExecutorAgentID，现有 `agent.sql` 任务创建复制归因及 issue/project；completed source 可合法继承。M13 尚须补 source 与目标 CR/project 关联验证，不能依 CR 上不存在的 project_id 字段或伪造归因。
- pipeline_run.started_by 来自认证 UserID；task-token middleware 的 UserID 可以是受锁定 runtime owner，不应强求它等于 source.originator 或改写成 executor。创建/恢复均须保真 originator/accountable/issue/project/started_by，验证真实 service SQL，不用 fake enqueuer 作为完整证据。
- 本段为当时只读事实，没有新增运行时行为、测试PASS或规范字段。后来子代理恢复、source修订与完整整包/独立复审已闭合M10（详M10-review）；M11现单writer进行，M12/M13仍未开始，不能据本只读段跳级。

## I8 M12 身份来源与既有精确命名合同（只读事实，复用既有行为）

- 同一planner实际读完整agent-import链：`activeAgents`仅从_index取id/path/status（agent-import.mjs:45–57），不取name。parseAgentDoc(:61–83)强制frontmatter起首，没有filename/H1 fallback；当前writer文档首行为H1会在:64抛no-frontmatter，**尚未构造POST**，不是发送undefined Name。
- payload name只来自fm.name(:116–121)，缺name在:104先拒；幂等GET后按精确a.name Set判已有跳过(:97/108–112)，不是upsert/actor-key映射。目录已有明确id/name/path声明，不能据此推断真实已装记录名字。
- Agent模型(models.go:26–59)没有origin/template/source/metadata安装身份字段，:93 Metadata属于AgentRuntime，不得挪作Agent来源。CreateAgentRequest.Template仅analytics标签不落Agent INSERT；SystemKey是产品内置Org Admin命名空间，不能拿来填tools actor映射。其它CLI/UI/copy路径都显式沿用用户/draft/source名，不补接线。
- 后续补读所有真实调用纠正上述缺口范围：缺的是installer→实例来源映射，不是既有runtime命名合同。StartRequirement→resolveRequirementAgents明确把registry.PipelineOwner及ownerOf(review-requirement)原样传agentByName；当前值requirement-writer/quality-reviewer-agent。setupRequirement按同样key seed Agent.name；design.md:18/126已明确executor actor key→同workspace agentByName→UUID，而非_index显示名翻译。
- Main确认M12沿用已有 **actor key＝Agent.name** 精确命名行为，仅把每节点声明的executor key交既有helper（不得改用owner/PipelineOwner/调用者或历史executor来猜新执行者），缺失即失败。没有新身份字段、翻译表、SystemKey挪用/双名fallback/模糊匹配/按Skill猜角色，不修installer或迁移真实部署数据；只按显示名安装的实例不在本次增加支持。不宣称线上记录满足这个前提。
- 现TestRequirementSameAgentForBothRolesIsRefused只改名就可能在writer-name缺失处失败，不足以独立证明same UUID比较真正执行；M12必须补能命中对应真实作者UUID等于reviewer的明确反例，不能拿该既有绿当完整独立评审证据。
- 本轮未跑import脚本/fetch/DB、未写测试、未修installer。可未来离线fixture验证当前H1文档失败并POST=0，但这不是已执行结果；不能将本地代码缺口说成线上实例已经错误。

## I9 M12 作者身份现成证据字段（只读事实，不新增选择策略）

- PipelineNodeRun模型没有task_id；真实关联方向是`agent_task_queue.pipeline_node_run_id → pipeline_node_run.id`，真实执行UUID字段为`db.AgentTaskQueue.AgentID`。`CreatePipelineTask`写选定a.id到队列agent_id；completed作者不能用仅查active的GetActivePipelineTask找，已知taskID可GetAgentTask。
- service/task.go:399–421的context.node_id是模板nodeUUID，独立列才是node-runUUID；旧requirement fake把NodeRunID放进context.node_id，不能把fake上下文当完整真实service/carrer证据。模板nodeId、node-run、业务attempt不能混同。
- 迁移102注释说明queue.agent_id插入后immutable约定，技术retry复制原p.agent_id；Agent.name/runtime可改，不改旧执行UUID。它不是数据库禁止任意UPDATE的强约束。旧executor_agent_id是execution_context键，不是PipelineRun列；来源source_task_id和角色缓存不能冒充已完成作者执行记录。
- 多条终态queue记录可关联一个node-run，node-run无唯一产出task指针；任务删除/仅投影也可能无作者证据，Agent删除会级联queue。不得盲选首个/latest completed作为本次被评产出的身份，不以source task/历史executor兜底。若M12需要实际产出作者选择，必须依批准当前阶段/业务attempt语义明确边界，不能自行扩为新forensic账本或改变既有接管策略；如无法在既有合同中确定，提Main而非猜。
- 更强same-UUID反例的可测思路（未执行、不等于新增验收范围）：保存A实际写节点queue记录，改名时B承接writer key、A承接reviewer key，使两个精确lookup都成功且新writerB≠reviewerA；验证实际作者A不能评自己，排除缺名/缺Skill提前拒绝掩盖目标路径。当前直接UUID比较helper可另以相同真实UUID上下文命中RunnerErrAuthorityMismatch；不拿旧仅改名的失败断言当完整UUID路径证据。

## I10 M20 权威推进事实裁定（writer/checkpoint 不得被 completed 单凭推进）

- **状态机权威**：`tools/dir-graph.yaml#change-request-track.state_machine` 定义 `{from: drafting, to: requirement-reviewing, trigger: review-requirement}`。drafting→requirement-reviewing 是 **review 节点**的转换，不是 writer 的；因此禁止要求 writer 完成时 cr.status 已变为 requirement-reviewing，否则等于把 review 职责塞给 writer。requirement writer 只在 drafting 下可达（现有 round path 已保证）。
- **规范硬约束**：`four-phase-runner-dispatch.yaml M-SC-DISPATCH-002` 明写“SHALL 不在 Runner 复制 crctl 业务判据或补造证据”。因此**不得**新增版本号非空/PRD 存在/状态跃迁等业务判据，也不得为 writer 造证据。
- **可用的非业务事实**：`crsync.go` 文件头注释与实现说明 Git 为权威，乱序/未知转换一律置 `cr.needs_reconcile=TRUE` 而不猜，由 reconcile job 从 KB 仓修正。这是**投影新鲜度**信号，不是 crctl 业务规则；`reconcile.go`/`crsync.go` 已在用。
- **M20 最小实现**：requirement writer/checkpoint 的 completed task 在 `cr.needs_reconcile=TRUE` 时不得 markNode passed，写现有 `setRunnerDetail` 的 wait_reason 后等待；置 FALSE 后保持原 handoff 语义。review/approval 的 evidence/approval_record/closing status 门已符合规范，用 RED 验证其确实阻断、已有阻断不重写。不新增状态/账本/列/字段；不改 crctl/tools。
- 本裁定不是新业务规则，而是把已有投影新鲜度与已有证据门接入结果消费；仍不声称四阶段 walker 或真实 CR 执行完成。
