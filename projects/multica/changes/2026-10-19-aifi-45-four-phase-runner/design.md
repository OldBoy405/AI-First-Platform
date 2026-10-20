# AIFI-45 四阶段统一 Runner — 技术设计（Phase 2 草稿）

## Context

- 状态：Gate1 已由用户确认；本文和全部规格均为**待实现 / 待验证**草稿，Gate2 未批准，未进入 Phase3。本文不是部署、停服、执行测试、审批或存量操作授权。
- 权威范围：`canonical/proposals/2026-10-19-aifi-45-four-phase-runner.yaml`（下称 P），10 个 capability；完整需求为集中记录根 `docs/AIFI-45-CR流程减负方案.md`。canonical 优先于提取器输出：已知 `extract-proposal` 返回空 capabilities，不据此缩减范围，不改 STDD 产品。
- 基线：multica `b0b60a15b`，tools `a5ecb57`；下文 S=`C:/Users/GOBAO/Downloads/AI/multica/server`，T=`C:/Users/GOBAO/Downloads/AI/tools`。源码定位均相对 S/T，不假设固定行号。核实结果只说明源码现状，不说明线上启用状态。
- 当前缺口：registry SCHEMAS 只有需求/设计；通用 parser 固定四节点，需求 parser 固定六节点；coding 多节点复用同一 ref；StartArchitecture/checkExecutorSkills/enqueueNode 将调用者及 executor_agent_id 与执行绑定耦合。开发/交付仍有投影和 carrier 缺口。
- **现状≠目标**：基线emitter的digest body为pipeline/pipelineOwner/nodePermissions，输入key列表在顶层、未完整导出pipeline.inputs；权限项仅ref/owner/pipelineOwnerCanCall。以下目标按tools同次design的Decisions §1统一，完整输入和绑定/执行声明必须受digest保护，不能把现状输入缺口保留为目标。
- 已有可复用机制：`resolveRequirementAgents`/`agentByName` 的角色分离、任务队列、节点锁与去重、crctl authority/账本/评审/审批、`recordRequirementRunContext`/`restoreRequirementRunTx`、TaskService 技术重试、daemon 终态队列、30 秒 runtime sweeper。
- 治理测试风险：`internal/governance/crsync_test.go::TestMain` 在 DB 不可达时 `os.Exit(0)`，**整包测试（含纯函数测试）都可能没运行**。本次只校验文档，不连接任何真实 DB，不执行业务测试。
- 约束：不新增独立 Runner/引擎、业务状态、用户命令/flag、审批节点、运行时报告/账本、扫描服务或重试系统。保留三类人工审批、签名/证据、workspace 隔离及作者评审分离；不恢复默认 dev-start 卡，不保留正常 Leader 续接兜底。

## Decisions

### 1. 唯一 registry，按 JSON nodeId（DB/Go内部node_id）的执行绑定（P.C1；M1）

**方案**：tools从既有四阶段模板、pipelineOwner、owns/can-call和独立reviewer声明派生绑定；multica扩展原生成链及公共节点执行切片。JSON使用nodePermissions `{nodeId,ref,owner,pipelineOwnerCanCall,executor}`，按nodeId唯一；node_id只用于DB/Go内部映射，不再导出同义字段。executor是actor key，不是Agent UUID或历史executor_agent_id；普通非human节点默认pipelineOwner，独立review若需显式executor只在原模板节点声明，平台用同workspace的agentByName解析真实Agent。human保留审批节点但不派Agent、不建执行task；system owner只标Skill维护归属，不充当executor。

完整pipeline.inputs及绑定/节点执行声明进入digest body；顶层inputs若保留，只能是pipeline.inputs同源派生的兼容key列表，不可独立编辑或成为第二输入事实源。执行流程消费原顺序、输入、canonical结果、gate及完整reviewLoop/replayNodes，不固定节点数量、不为交付造loop。

**为什么**：coding的相同ref可对应不同nodeId/轮次；Skill所有者不等于executor。复用需求阶段作者/评审分离并校验actor权限，比给调用者全部Skill更符合边界。

**备选及排除**：按 ref 路由会串节点；给逻辑 system 身份建 Agent 或运行时按可用性/Skill owner 回退会改变授权；复制四套 walker/路由表形成第二事实源。

派发移除 `checkExecutorSkills` 及 executor_agent_id 决策依赖；旧字段可兼容读取，不批量迁移。`SourceTaskID` 与 `ExecutorAgentID` 语义分开，保留真实来源 agent、workspace、issue/project、originator/accountable、started_by；来源 task 可已完成。每节点仍验证同 workspace、未归档 agent、runtime、能力与绑定权限；绑定无效失败关闭，绝不默认选调用者。

### 2. canonical 事实决定节点业务结果（P.C1/C2；M1/M2）

**方案**：task 状态仅说明运输/执行生命周期；Runner 读取已有 canonical 产物和深原语机器结果。开发按原模板接管计划、TASK、计划评审、finalize、freshness、实现、真实 testCr、代码评审及审批收尾；补齐 `gate_projection.go::applyReview` 与 `daemon/crevents.go::buildReviewPayload` 的 dev-plan/test/upstream。

**为什么**：task completed、文件存在、退出 0、模型自报 PASS 都不足以证明账本、测试、评审或审批完成。代码评审必须匹配已有 release-subjects，不可套用设计单一 subject_sha256。

**备选及排除**：Runner 复制业务判据会漂移；仅靠 task completed 或报告存在会放过伪测试；全局 dirty-start 白名单会绕过原 clean 合同。

需求评审前真实版本由负责人确认，经既有 version-set 后继续；等待输入不猜版本、不耗技术预算。dirty-start 逐节点遵循模板与轮次合同，clean 责任由原产出/提交责任方收尾。

### 3. 合法回修是业务路由，不是技术重试（P.C2/C3/C4；M2–M4）

**方案**：`review-dev-plan:upstream-design-blocker` 消费 repair-target，走生成状态机已有 `task-breakdown → tech-design-review-pending`；先技术复评，BLOCK 后才合法转入设计编写，再独立评审、既有设计审批，按增量规则恢复开发。开发 run 依既有路由等待，不新增等待状态。

merge 的机器结果若 `phase=release-drift` 且表明已 advanced，即使退出 0 也停止交付，走既有 `code-approved → developing`，修复/测试/评审/重批后才再交付；部分发布后漂移保留原阻断。`APPROVAL_DECLINED_ROLLED_BACK` 停正向链，保留原 abort/等待输入合同，不技术重试、不规定一律自动重写。

**为什么**：旧 StartArchitecture 只接受 requirement-approved，不能直接承担设计复评重入；重试 merge 或沿旧 PASS/grant 会绕过业务授权。

**备选及排除**：直接退 tech-designing 跳过复评；复活已取消/失败 run 破坏终态；每次回修重置 loop 会变无限重试。

合法回修允许按既有转换建立新 cycle，不复活历史执行，不任意重置业务轮次；新旧 cycle 与 repair-target、digest、当前证据关联。

### 4. 交接先同事务持久化，解锁后协调（P.C4/C8；M4）

**方案**：收敛既有 start/resume 内部的“校验 + 创建/接管”实现，与公开 starter 的 Reconcile 副作用拆开。所有相关查询、upsert、context、上游完成/交接结果使用**同一 pgx.Tx**，不得内层回落 r.pool。复用需求的 context 保存/恢复模式扩展四阶段。

**为什么**：仅外层包事务不能防部分提交；`events.Bus.Publish` 同步回调，锁内发事件可能递归 Reconcile，造成嵌套锁与死锁。

**备选及排除**：事务内调用完整公开 StartArchitecture 会派任务/重拿锁；先完成上游再异步补建下游会漏接；新 outbox/交接账本不必要且违反边界。

事务只落持久事实，不派 task、不调用 Reconcile、不发布可能递归的同步事件。提交并释放连接/所有权锁后才协调下游；提交前失败保留可续接上游，已批准事实不撤销；提交后崩溃由下游持久 context 和周期续接补齐。复用活跃 run/node/task 去重；矛盾终态须受控恢复，不能“无活动 run 就新建”。注册已提交而首次接入未完成，从既有注册/source 事实确定性重入；不宣称 Git 与数据库原子，不新增注册协议或人工步骤。

### 5. 交付节点按 task 切换本机根，最终收尾归 Runner（P.C3；M3）

**方案**：代码批准只授权已有 merge、PRD/SDD/TASK 回写、traceability、archive。spec_id/target_version 从 crctl authority 与既有机器输出继承，缺值阻断，不猜标题/占位，也不强填 legacy milestone。`preparePipelineTask`/`inspectPipelineWorkspace` 每 task 本机解析；merge 后旧 task 完成，下一节点新 task 重绑 operational workspace；server 不猜绝对路径、不修改运行中 task env。

archive 从不会被自身清理的安装根启动，crctl 仍解析业务 authority，安装根承载现有审计/outbox/terminal settle。清理后重入不再要求已删除 txws，亦不绕过 authority；cleanup-pending 是业务成功，不另派清理/重归档。settle 失败只走技术恢复。`projectGateTransitionErr`/`completeRun` 与 archived 事件遵守 run ownership：投影可更新 CR 展示，不抢关 Runner run，Runner 汇合最后 canonical 事实与任务终态后完成。

**为什么**：单 task 跨根和投影抢关会丢最终结果；归档的 cwd 被清理会破坏恢复。

**备选及排除**：原 task 改 env 跨阶段续跑不可恢复；server 猜本机路径不可信；把 archived 或 cleanup-pending 单独当最终执行完成会漏 settle。

### 6. KB 资源单源、两传输共用、请求级 workspace（P.C6；M6）

**方案**：heartbeat 可选 local_directory 完整快照，按已授权 runtime 的 workspace/daemon 替换运行期投影；WS 将鉴权查询已读到的 runtime daemon_id 存入 RuntimeLease。HTTP `processHeartbeat` 后手动响应也携带快照；daemon 两传输共用消费入口。

**为什么**：WS 正常时会跳过 HTTP；只补 HTTP 或依赖 PAT daemon_id 会漏资源。重复根配置造成冷启动和改路径不收敛。

**备选及排除**：追加快照保留旧路径；缺字段/查询失败当空会误删；环境变量兜底、持久根账本和全量 endpoint 形成第二来源。

成功空快照清除该 workspace/daemon 投影；缺字段或读取失败保留上一有效快照，且不能吞掉本次已领取 pending actions。查询限定项目和 runtime，无项目 N+1。collector/投递循环无条件随生命周期启动，等首次有效快照；目录/账本稍后出现由既有节拍识别。采集、任务定位、terminal settle、pending、ack 共用根来源；runtime/workspace 退出清投影。请求通过既有 X-Workspace-ID 分组，不修改共享 client 全局 workspace。移除 MULTICA_CR_WORKSPACES 根来源，不双模式、不递归未知 KB、不因发现根扩大普通任务权限；两处 CR not found 展示 workspace/CR、资源、daemon/runtime 与投影线索。

### 7. 目标 key → 完整 grant → ack；ack 不编排（P.C5/C6；M5/M6）

**方案**：pending 复用 PublicKeyPEM() 增加 `public_key: {key_id,pem}`。按 workspace 下现有 CR 定位规则选唯一可信 KB 根，不广播。对应 key 已可信存在或当前 key 安全安装后，完整 grant 原子落盘，最后收集 ack IDs。已有 key 不覆盖；冲突、缺 key、写失败、零/多目标不 ack。保留旧可信 key；旧 grant 缺旧 key 留 pending，非完整历史轮换承诺。首次安装依可信服务端连接，远端有效 TLS、本地回环沿现有边界。

ack 复用 workspace+IDs 的 SQL 批量幂等更新；delivered_at 仅送达。删正常路径 resolveContinuationTarget、EnqueueApprovalContinuation 和仅为续接存在的整批回滚；保留认证与 workspace。提交后按实际阶段 WakeGrant，一条失败不撤其他 ack/唤醒；缺活动 run 不创建/不声称推进，终态不复活，旧 grant 不当指令。DB 真提交失败仍由 pending 重投。

**为什么**：当前任一根写成功即 ack 会丢目标投递；Leader 缺失不应撤销同批真实送达。

**备选及排除**：先 ack 后写 key/grant 会丢失重投；逐条事务/新续接队列不必要；无 Runner 回退 Leader 重建双编排。

运行时文件沿 crctl 默认 `.crctl/.gitignore` 的 `*`，后续实施一次性核对平台 KB 的 `!keys/**` 例外；不删已跟踪信任锚、不要求逐 KB 新配置。本次不改任何忽略配置。

### 8. 复用 30 秒 sweeper 与技术恢复（P.C7；M7）

**方案**：在 runRuntimeSweeper/runPeriodicSweep 既有 30 秒周期接入 Runner 有界回调，按 pipeline 扫活动 run；限批、超时、逐 run 隔离，公平继续，不阻塞 liveness。事件仍用于及时性，启动扫描用于重启恢复。具体批量/超时数值由隔离测试测定后 Gate2/实现审查确认，不加新用户 flag。

failed task 先查已有 retry child、待终态补报和已证明可恢复技术中断，再决定 failRun；复用 FailTaskWithTransition/MaybeRetryFailedTask、journal/recovery argv、terminal_report_queue。终态队列不只重发 HTTP，还保留结构化 crctl recovery；settleCREventsForTask 失败不得冒报业务已 settle。技术 attempt 与业务 loop attempt 分开，不抬预算，不挂会加预算的 ResumePipelineNodeTask 到 tick。

**为什么**：终止 run 后活动扫描找不到；只重放 HTTP 不能恢复未完成 crctl settle。

**备选及排除**：新扫描器/重试表产生第二系统；所有 platform/TX_GIT_FAILED/process_failure 一律重试不安全；按自由文本猜 recovery 可能越权。

只恢复原权限内、无新输入、已证明安全幂等的动作；认证/余额/权限/签名/证据冲突、业务 BLOCK、人工驳回与 release-drift 非技术重试。预算耗尽明确停止保留现场；取消和既有失败终态不复活；等待真实版本/人工 gate 不耗重试。

### 9. TDD 顺序固定，跨仓整套验收后才考虑启用（P.C1–C8 / constraints；M8）

**方案**：test 基线 → tools registry 合同 → multica 消费 → 执行与恢复 → ack 去续接。最后一步是实现依赖顺序，不意味着中途可启用混合模式。工具提示词删除接力必须与平台接管同一发布窗口；tools C7 测试超时诊断与修复同次纳入，不另开 change、不缩测试范围；用户已确认将诊断修复纳入同次范围，诊断数据来自主会话委派的只读诊断Agent实测而非人类提供/批准结论；6项失败修复仅归tools，当前仍是文档回合。

**为什么**：先删 ack/Skill 尾启动而 Runner 未闭环会产生无人接管；只测两阶段或以空跑充绿灯不能支撑切换。

**备选及排除**：先解阻 AIFI-45 再补剩余不满足完成标准；新旧双模式/Leader 兜底制造长期双编排；只提高超时或排除慢测试伪造验收。

普通 Issue+PR 追溯；multica 后续实现按现行 CUSTOM.md 登记，不编造 CR/TASK。tools 保留 crctl 31、output-guard 3、registry 1 个测试文件及新增回归发现范围。**主会话只读诊断实测（用户已确认范围）**：主会话委派的只读诊断Agent测得crctl整文件358.14s自然exit1，294 case＝288 pass＋6 fail／0 skip；短预算与输出延迟不是挂死。6项失败为5项payload fixture根错位，以及1项cmdTaskDone已知TxError被总catch改成INTERNAL_ERROR。这里仅引用Agent实测，本multica文档回合未重跑；不是人类提供/批准6失败结论，也不是修复完成或整套通过，不补批Gate1。未来仅 tools 同次 C7 先以失败回归锁定这两类已知根因，再修 fixture 根及保真错误，保持完整范围；不在 multica 规避、不重启挂死假说、不以延超时掩盖真实失败。证据摘要只进已有 PR/Issue，不增运行时报告文件。

## Architecture

### L2 跨仓接口锚定（设计约定，待 Gate2 确认）

P 标记 cross_system=true、safety/financial=false，采用 **L2 接口约定**。本节足以承载锚定，不新增 anchor 源码或独立合同文件；不修改 P 或状态中的 anchoring。以下为目标合同，不声称现有字段均已实现。与集中记录根`projects/tools/changes/2026-10-19-aifi-45-runner-contracts/design.md`的Decisions §1对齐；JSON字段、四schema及digest范围已明确，不再列为字段拼写未决。DB/Go内部node_id与JSON nodeId单向对应，不引入第二事实源；快照对象和batch/timeout等其他参数仍待Gate2前确认，不猜实施值。

| 边界 | 输入/输出和不变量 | 拒绝/恢复规则 |
|---|---|---|
| T emit-registry → S generator/parser | nodePermissions字段集合为`{nodeId,ref,owner,pipelineOwnerCanCall,executor}`，每个非human节点恰一项、nodeId唯一且对应pipeline.nodes[].id；executor为actor key，DB/Go映射node_id；来源仅原模板/matrix，重复ref不合并，human不派Agent | 缺/重复nodeId、非法actor、未授权、作者=reviewer、未知pipeline/输入能力均失败关闭；active Skill/唯一owns、executor为真实kind=agent、owns/can-call/forbidden均校验，不临时猜绑定 |
| schema（目标固定） | 保留`ai-first.pipeline-registry/architecture-core-v1`和`ai-first.pipeline-registry/requirement-core-v1`；分别新增code-implementation→`ai-first.pipeline-registry/code-core-v1`、feature-writeback→`ai-first.pipeline-registry/writeback-core-v1` | 不改既有schema名；同名schema不代表旧digest可直接接受，按原受控接管入口确认，不覆盖存量digest |
| digest（目标） | `sha256:`加SHA256(JSON.stringify({pipeline,pipelineOwner,nodePermissions}))；pipeline包含完整pipeline.inputs（类型/required等原声明）及节点真实执行字段/完整loop，nodePermissions包含nodeId/授权/executor绑定；JSON字段生成顺序固定、读入先规范CRLF | 输入声明、绑定/授权/执行声明改变必须改变digest；顶层inputs仅为同源派生兼容key列表，与pipeline.inputs不一致即拒绝，不能独立作为权威。运行时仍检查输入能力，不以digest替代校验；不覆盖存量digest |
| 生成链 | T 模板/emit → S `gen/generate-gate-nodes.mjs` → `internal/governance/gate_nodes_gen.go`、`requirement_registry_gen.go` 等原生成产物；四阶段导出/编译/parser 合同一致 | 不手写第二份节点表；确认既有生成器实际产物后扩展，不另造生成器 |
| claim/task carrier | 节点身份在JSON为nodeId、DB/Go内部为node_id；pipeline、node-run/cycle/attempt、digest、CR/source context完整保留；registry executor actor key经agentByName解析到任务ExecutorAgentID，SourceTaskID独立 | 来源可已完成但归因不可伪造；dirty/clean按节点输入；历史executor_agent_id不参与选择，不能与registry executor混淆 |
| canonical result | 节点声明的结果与 authority 对齐；dev-plan/test/upstream、release-subjects、merge phase/advanced、cleanup-pending、structured recovery 在既有 carrier 中最小扩展 | task completed/exit0 非业务证明；BLOCK/decline/drift 路由与技术重试分类分离；保留来源、签名和证据核验 |
| 事务交接 | 同 pgx.Tx 的上下游查询/upsert/context/上游完成结果，包含 digest/workspace/source/started_by 和合法 cycle 路由；commit+unlock 后 Reconcile | 提交前原子回滚本次交接，不撤审批事实；提交后 crash 由持久 run+tick 恢复；同步事件不在持锁区递归 |
| heartbeat | 可选目录快照对象，当前已授权 workspace/runtime daemon_id；成功非空替换，成功空移除；缺字段/失败保留；HTTP/WS 共用 | 读取失败仍交付已领取 actions；客户端不自报身份；退出生命周期清投影；首次失败不回退 env |
| pending → daemon | workspace 请求级分组；grant 原有身份/签名加 public_key{key_id,pem}；根唯一匹配 | 可信 key→完整 grant→IDs；冲突/缺 key/歧义/写失败 pending；不任意根成功即 ack |
| ack → Runner | 认证+workspace+record IDs，批量幂等 delivered_at；commit 后按实际阶段唤醒 | 唤醒隔离，不 Leader、不新建 run、不消费旧 grant；真实 DB 失败允许重投 |
| tick/recovery | 既有 30s sweeper 有界回调；按活动 run 公平处理，锁/去重、现有 retry budget/backoff、结构化 recovery | 具体批量/超时待隔离实测；单 run 失败不阻塞；不自动提预算/复活取消/重置 loop |

### 正常链与回修链

```text
原注册/start-resume source facts
  → requirement-authoring → 人工需求批准
  → [Tx: 上游交接结果 + 下游 context/run] --commit/unlock→ Reconcile
  → architecture-design → 独立评审 → 人工设计批准
  → [同一交接协议] → code-implementation
      → 计划/TASK/计划评审/finalize/freshness/实现/testCr/代码评审/人工代码批准
  → [同一交接协议] → feature-writeback
      → merge（旧 task 结束）→ 新 task operational workspace → 回写/traceability
      → 安装根 archive → canonical+最终 task/settle 汇合 → Runner complete

upstream blocker → tech-design-review-pending + repair-target
  → 技术复评 → 必要修订/重审/设计审批 → 增量开发续接
merge phase=release-drift, advanced → developing → 修复/测试/评审/代码重批
```

事件及时唤醒 / 启动扫描 / 30s sweeper 共用 Reconcile；它们不是三套编排。根快照服务采集、定位、settle、pending/ack；ack 仅通知送达，不承担阶段分配。

### 原实现落点（待实现，不是修改记录）

| 项 | 主要落点 / 现有回归入口 |
|---|---|
| M1 | S `internal/governance/runner*.go`、生成器、`internal/handler/daemon.go` claim、`internal/service/task.go::PipelineTaskSpec`；runner_integration/runner_requirement；T emit-registry/四模板 |
| M2 | S gate_projection/applyReview、daemon/crevents/buildReviewPayload、transitions_gen 生成源；gate_review/gate_projection/transitions_test；T 既有开发深原语 |
| M3 | S daemon/pipeline_task prepare/inspect、settleCREventsForTask、projectGateTransitionErr/completeRun ownership；pipeline_task/crevents/gate_projection tests |
| M4 | S StartArchitecture/upsertRun、StartRequirement/upsertRequirementRun、runner_requirement_resume；runner_integration/runner_requirement tests |
| M5 | S approval.HandleGrantsAck、WakeGrant、approval_continuation、SQL AckApprovalGrants；approval_continuation/daemon_workspace/approval_crosscheck tests |
| M6 | S handler processHeartbeat/HTTP response、buildDaemonWebSocketIdentity、daemonws RuntimeLease、daemon heartbeat/actions/collector/grants、protocol；handler/daemonws/daemon tests |
| M7 | S cmd/server runtime_sweeper、service/retry_deferred、pkg/taskfailure、daemon/terminal_report_queue；现有 sweeper/retry/terminal tests |

### 发布与 O2：仅设计演练（P.C8）

1. 仅在隔离非生产夹具演练完整四阶段，确认模板/导出/digest/生成产物、服务端/daemon/tools/instructions 一致；无半套启用。
2. **未来另获授权后**才可安排短维护窗口：暂停受影响派发/领取/投递/ack，保存原事实；旧 running 执行须完成或经既有受控入口停止并确认退出，不能把“暂停领取”当已停 Agent。
3. 更新全部配套产物而不恢复调度；按原确认参数处理旧 context/digest 和已知 queued/running Leader 续接，不能覆盖 digest、抢改运行任务或全量迁移。
4. 核实旧执行已退出、新 HTTP/WS 根/公钥/投递有效且线上 instructions 非仅 checkout HEAD 后，才恢复统一调度；不支持新 daemon+旧 server，不保留 Leader 兜底。
5. O2 重新读取权威 worktree status/next、服务端投影、各阶段 run/task（主 checkout 不是权威）。已完成需求且 requirement-approved、无设计执行时，既有 `multica cr pipeline start CR-FS-2026-004` 只作为一次性补接的**演练步骤**；有设计执行使用 M4 扩展后的受控入口，原实现不假定已支持。
6. 不重复批准已记入权威结果的审批，不手改 DB/状态/账本，不批量修历史；缺旧 key/派错任务逐项受控处理。以 canonical+run/task 确认设计可继续后，未来授权执行者才可改 Issue 为 in_progress。维护 Issue 的 in_review 要等全部验收，不只 AIFI-45 解阻。

### 文件组织与追溯

10 个真实 capability 各一份同名 code YAML、agent YAML 和 `specs/<capability>/spec.md`，共30份规格/视图。按用户最新要求，原 `canonical/specs/{code,agent}/2026-10-19-aifi-45-four-phase-runner.yaml` 两份 **stdd new 的 TODO 种子保留**，不作为真实 capability、Requirement、Scenario、TC 或 CP 计数；canon Gate2 会跳过 code TODO 种子。本次不调用 Gate2，不假定种子属于有效验证规格。`.canon-index.yaml`、proposal 和审批状态保持原样，不修 STDD 产品；只用已有 `_generate_spec` 为每份真实 code capability 渲染草稿视图，不写新生成器。

ID定义采用全局M命名空间：M-REQ、M-SC、M-CP、M-TASK；TC为兼容STDD实际正则使用TC类型前缀、M开头的大写能力缩写及三位序号（即TC-M<能力>-<序号>）。每场景一个独立TC，test-plan每case单独详细表，ID只出现一次，关联Spec及GIVEN/WHEN/THEN/AND齐全；其他文档出现同ID为引用而非新定义。agent每场景一个checkpoint。confidence 表示需求推断把握而非已测试覆盖；evidence 使用 P 的真实 YAML 选择器（数组按 `[id=Cx]` 或 `[name=...]`，success_criteria 以原文索引从 0 计）。MD 仅为 canonical 行为的人类视图，不新增事实源。

## Risks / Trade-offs

| 风险 | 缓解措施 / 待确认 |
|---|---|
| L2只约束接口，尚无四阶段实现证据 | 本设计与tools锁定nodePermissions/nodeId/executor、四schema及digest语义；Gate2确认后才TDD，切片2核对原生成链落点 |
| 将现状输入缺口误当目标、顶层inputs形成双事实源 | 目标完整pipeline.inputs和绑定/执行声明进入digest body；顶层仅同源兼容列表且不一致拒绝；digest改变走原受控接管，不覆盖旧记录 |
| 锁内同步事件递归、r.pool 混入 Tx | 同 pgx.Tx 故障注入+锁内禁止派发/同步递归测试；提交后协调由 tick 兜底 |
| 新 cycle 被误实现为复活终态或重置 loop | 对合法业务转换、retry child、终态分别断言；不沿旧 PASS/grant |
| 投影抢关或归档清理掉 cwd | ownership 断言、安装根启动、merge 新 task、cleanup-pending/settle 故障独立用例 |
| 旧 daemon 提前 ack / 任意根广播 | 不支持混跑组合；统一窗口演练，唯一目标、公钥写入顺序及 workspace 请求级隔离 |
| 首次快照失败、丢 action、空快照误删 | 区分 absent/error/empty，保留 actions；无 env 回退；两传输同测试数据 |
| sweeper 阻塞 liveness 或饿死 run | 有界 batch/timeout、公平遍历与单 run 隔离；数值需隔离实测，当前不许宣称恢复时限 |
| governance退出0空跑、tools超时缩范围 | 隔离已迁移测试库+实际case输出；tools C7完整发现范围、真实耗时/退出码/skipped；本次不运行业务测试 |
| STDD文档校验粗粒度 | validate按每case的ID字段计数、同文本TC重复即报错；使用真实逐例表而非摘要凑数。AND整spec累计告警是工具局限，canonical仍逐Scenario≤5，不删断言、不改STDD |
| TODO 种子被误计数或误验证 / 旧索引只含 scaffold | 保留两份原种子、不计有效产出；十组真实文件按 capability 同名，显式过滤 TODO 后用现有函数渲染，索引保持不动 |
| 真实部署/停服/O2 超出授权 | 这里只演练设计，不操作任何生产/真实 CR；将来必须另获明确授权 |
| 未决项 | Gate2待批并审查已对齐的L2；快照对象最终拼写及batch/timeout实测值仍待确认，不猜实施值。registry JSON字段、四schema及digest目标不再互相矛盾；tools6项修复/完整回归、multica隔离库实际case仍待实现验证，不得据此上线 |
