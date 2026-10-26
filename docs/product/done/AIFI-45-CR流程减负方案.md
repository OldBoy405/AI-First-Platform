# AIFI-45：四阶段统一 Runner 与 CR 流程减负方案

## 1. 目标与已确认决策

**目标：删除重复配置、重复调度与人工接力，让正常流程只有一个推进者；不靠新增门禁、检查命令或补偿系统维持多套路径。**

本方案覆盖注册后的四阶段：**需求 → 技术设计 → 开发 → 合入、回写与归档**。统一复用现有 Runner、任务队列和 crctl 深原语，不另造多个独立 Runner 或通用工作流引擎。

| 事项 | 已确认决策 |
|---|---|
| 编排责任 | 四阶段的正常自动推进统一由 Runner 承担；不长期保留 Runner-off、Leader 续接等另一套平台自动模式 |
| 阶段授权 | 需求批准后自动进入设计；设计批准后自动进入开发；代码批准后自动合入、回写、归档，不再请求启动或发布指令 |
| 人工审批 | 保留既有需求、技术设计、代码审批，不恢复默认开发启动审批；审批不由 Runner 或模型代签 |
| 业务产物 | 保留 PRD、SDD、计划、任务、测试报告及既有评审链；删除重复输入、事实副本和评论接力，不重构方法论本身 |
| 上游回修 | Runner 自动接续同一 CR 的既有技术复评、必要修订、重审、设计审批和开发恢复路线，不新建 CR 或审批节点 |
| 版本选择 | 注册允许 `unassigned`；需求评审前由需求负责人确认真实版本，Agent 使用既有 `version-set` 更新后自动继续 |
| 自动恢复 | 协调层暂态故障持续自动续接；Agent 重试沿用明确分类、预算与退避，不无限重跑、不自动抬高预算 |
| KB 接入 | 项目目录资源经现有 HTTP/WS heartbeat 下发，采集、定位、投递共用同一来源，不再逐 KB 填采集环境变量 |
| 密钥范围 | 自动安装当前签发公钥，保留已有旧 key；不扩展为完整历史密钥服务或多 daemon 副本协议 |
| 发布与存量 | 短维护窗口统一升级；已知受影响记录使用现有入口一次性受控恢复，不做全历史自动修复 |
| 完成标准 | AIFI-45 解阻不等于方案完成；四阶段编排、KB 一次接入和自动恢复都必须闭环 |

### 执行边界

- 本次维护沿用经人类确认的**普通 Issue + PR**方式，不另注册 CR、创建 CR 目录或走业务 Pipeline；不豁免在途业务 CR 的既有评审、审批和状态门禁。
- 注册保留既有入口，不重做 AIFI-71 的编号、注册事务或 trunk 解析。注册后的首次 Runner 接入复用现有 start/resume 能力，不增加人工启动步骤或依赖作者临时补命令。
- 不新增业务状态、审批节点、CLI 命令、flag、健康检查、账本或独立重试系统。必要的内部事务、事件载体和既有响应字段扩展属于接线，不变成用户操作步骤。
- 保留 workspace 隔离、来源归属、签名与证据验证、作者与评审者分离。实现测试不是新增运行时门禁。
- 代码审批授权的交付仅指已有合入、回写和归档，**不包含生产环境部署、安装包或商店发布**。
- 本文是待实施方案；本次文档更新不表示代码、部署、运维或 CR 状态操作已经执行。

## 2. 背景、根因与核查基线

[AIFI-45](mention://issue/01a0fcb2-82bb-7edc-a1c6-580e6f911ac2)（CR-FS-2026-004）经历了多次非业务风险阻断。注册相关问题已由 [AIFI-71](mention://issue/01a14df2-c40f-77c0-bc53-ad09d6c60c46) 处理，本方案不重复。以下是原事故记录，不作为实时线上观测。

| 编号 | 事故或机制缺口 | 根因及收敛方向 |
|---|---|---|
| B1 | 金融 KB 未被采集，出现 `CR not found`，曾靠配置与重启恢复 | 项目目录已配置，采集器另依赖启动环境变量；改为复用已有项目资源 |
| B2 | ack 持续报 `leader-missing`，历史记录拖住同批新记录 | 投递确认耦合 squad Leader 解析与续接；四阶段接管后删除这条业务推进路径 |
| B3 | 金融 KB 缺公钥，曾人工复制后恢复 | grant 自动投递而公钥未接入同一通道；改为目标 key、grant 一并就绪后 ack |
| B4 | 设计期报 `RUNNER_SKILL_MISSING` | 调用者被当成全部节点执行者；改为消费 registry 的节点执行绑定，区分 Skill 归属与实际执行者 |
| B5 | 阶段之间仍需协调者转述和作者启动 | 缺少持久、可恢复的阶段交接；统一由 Runner 完成 |
| B6 | 开发、回写有模板与投影，却未真正接管执行 | Runner、registry、claim 及事件载体只接了需求、设计；补齐四阶段，不将投影 run 当执行证明 |
| B7 | 一次唤醒失败后可能长期停住 | 只有事件唤醒与启动扫描；复用现有后台 tick 与任务技术恢复，不要求人工补命令或重启 |

核查基线：multica `b0b60a15b`、tools `a5ecb57`。下文 multica 路径相对 `../multica/server/`，tools 路径相对 `../tools/`；实施时按符号重新定位，不依赖固定行号。

| 已核实事实 | 证据入口 |
|---|---|
| 当前 Runner 执行切片只有需求、技术设计，开关默认关闭；不能据源码断言线上已启用 | `cmd/server/router.go`；`internal/governance/runner*.go`；tools `pipeline-templates/emit-registry.mjs` |
| 设计执行者取调用者，技能检查遍历全部节点 | `runner.go`：`StartArchitecture`、`checkExecutorSkills`、`enqueueNode`；节点 owner 已在 `gate_nodes_gen.go` |
| ack 每条记录都走 squad→Leader 续接，失败整批回滚；Reconcile 无活动 run 可返回 nil | `internal/governance/approval.go`；`pkg/db/queries/approval.sql`；`runner.go`、`runner_requirement.go` |
| coding 模板和真实任务、测试原语已有，平台执行、评审结果投影及 carrier 接线不全 | tools `code-implementation.pipeline.json`、crctl `cmdTaskDone`、`testCr`；平台 `gate_projection.go`、`internal/handler/daemon.go` |
| merge/writeback/archive 深原语已有；回写模板输入与新模式 Skill 存在漂移 | tools `feature-writeback.pipeline.json`、`skills/writeback/`、`workspace-transactions.mjs` |
| 上游设计回退路线已有；需求评审前已有真实版本约束，晚改版本会改变评审摘要 | tools `dir-graph.yaml`、`cmdNext`、`cmdVersionSet`、`review-record`、`release-subjects` |
| heartbeat 两条传输均需接线；WS lease 未保留已查到的 runtime daemon ID | `internal/handler/{daemon,daemon_ws}.go`；`internal/daemonws/hub.go`；`pkg/protocol/messages.go` |
| 任务层已有技术重试和终态补报，但 Runner 尚无周期续接，终态载体未完整传递 crctl recovery | `internal/service/task.go`；`pkg/taskfailure/`；`internal/daemon/{terminal_report_queue,pipeline_task}.go` |

此前本地核查中，CR-FS-2026-004 的**权威 worktree**已为 `requirement-approved` 且有审批记录，主 checkout 仍是旧快照。恢复时重新读取权威状态、服务端投影及 run/task，不能据旧快照重新审批。

## 3. 目标责任模型

```text
既有注册入口 → 需求 Runner
  → 既有需求评审与人工审批
  → 设计 Runner：设计、独立评审、既有人工设计审批
  → 开发 Runner：计划、任务、实现、测试、独立评审、既有人工代码审批
  → 交付 Runner：合入、回写、归档

开发上游 blocker → 既有技术复评/修订链 → 既有设计审批 → 增量回修并恢复开发
```

上图表达责任与授权，不另作节点事实源。具体节点、reviewLoop、状态转换仍归属现有 Pipeline、状态机与 crctl。

| 责任方 | 只负责 | 不再负责 |
|---|---|---|
| Runner | 节点派发、等待事实、回修路由、持久交接、自动续接 | 不代替 crctl 写状态、验签、合并或归档，不自行增加业务判断 |
| 节点 Agent | 执行当前 Skill，返回可归因的业务结果或技术错误 | 不评论接力、不跨节点派发、不在 Skill 尾部启动下一阶段 |
| crctl | 状态、审批、门禁、账本、Git 与交付事务 | 不复制另一份平台编排规则 |
| 协调者 | 入口协调、异常汇总、必要的人类业务输入与授权 | 不承担正常审批转述、评审回修或阶段启动 |
| daemon | 根绑定、执行环境、投递、终态报告与已有技术恢复 | 不将进程退出 0 当业务完成，不维护第二份根配置 |

## 4. 实施项

### M1　统一四阶段 Runner 底座与节点执行绑定

**范围**：tools `pipeline-templates/emit-registry.mjs`、四阶段模板的对应合同；平台 `internal/governance/runner*.go`、registry 生成器、`internal/handler/daemon.go` 的 claim/carrier、现有任务服务。

- 扩展已有 registry 导出、编译、派发和结果载体，覆盖 `requirement-authoring`、`architecture-design`、`code-implementation`、`feature-writeback`。仅有 Pipeline 投影 run 不算已接管执行。
- 从既有节点执行中收敛公共部分：入队、等待、canonical 结果读取、节点重入、人工 gate 与 reviewLoop。消费既有声明，不再用固定四节点 walker 解释所有阶段；无评审的交付阶段不得硬造 reviewLoop。
- registry 是唯一派发合同，但 **Skill 的 owns 不等于每次派发的执行者**。利用已有 `pipelineOwner`、owns/can-call 和独立评审规则生成按 node_id 确定的执行绑定：共享 Skill 交给已获授权的阶段 Agent，评审交给独立 reviewer。确需节点声明时放在既有模板，不能另建路由配置或给逻辑 system 身份新建执行 Agent。
- 既有导出合同核对绑定与授权并纳入 digest，不新增检查命令或独立 lint。运行时只消费节点执行绑定，复用 `agentByName`、同 workspace、未归档、runtime 及节点能力约束，不从 Skill owner、调用者或 Agent 可用性临时回退。删除 `checkExecutorSkills` 和对 `executor_agent_id` 的派发依赖。
- 来源 task 与执行 agent 保持分离。source task 可已完成，但必须保留真实 agent、workspace、issue/project、originator/accountable；不伪造协调者或审批人身份。
- 节点成功以既有业务结果和权威证据为准。task completed、CLI 退出 0、模型自报 PASS 均不能替代任务账本、测试结果、评审或审批事实；不在 Runner 重复实现这些判据。
- dirty-start 按各节点现有输入合同及必要轮次适配，不照搬需求节点例外或全局放宽 clean 前置；要求 clean 的节点由原产出/提交责任收尾，不能因遗留 dirty 就新增放行白名单。
- 旧 run 的遗留 executor 字段无需批量迁移，但不再决定派发；已 queued/running 的错误任务不会自动改派，按存量恢复处理。

### M2　接管开发期与既有上游设计回修

**范围**：开发 Pipeline 的 Runner 执行、review/test 事件投影与 carrier；`gate_projection.go`；tools 开发相关 Skill/模板的接线合同。

- 接管现有计划、任务、计划评审、finalize、freshness、实现、测试、代码评审和审批收尾，不新添业务节点，不恢复默认 `dev-start` 人工卡。
- 计划、测试、代码的回修分别使用各自既有 reviewLoop、replayNodes、轮次与 canonical 结果；技术任务重试不消耗或重置业务评审次数。
- 补齐 dev-plan、测试结果与 upstream 路由的投影。代码评审消费已有 `release-subjects`，不能照搬设计评审的单一 `subject_sha256` 判定。测试由既有 `testCr` 真实执行，不能只检查报告文件存在。
- 普通 BLOCK 按模板回修并重放必要证据节点，不由协调者转述，也不把失败任务直接当作已完成节点。
- `review-dev-plan:upstream-design-blocker` 走现有 `task-breakdown → tech-design-review-pending`，消费 `repair-target`；先技术复评，确认 BLOCK 后才走已有转换回编写态，禁止直接退到 `tech-designing` 或沿旧 PASS 直接审批。
- 设计修订、独立重审、既有设计审批后，按已有增量规则修订计划/TASK 并恢复开发。平台补齐设计合法重入与开发续接，不能原样调用只接受 `requirement-approved` 的旧 `StartArchitecture`。
- 合法上游回修可按既有规则进入新设计 cycle；这不等于复活失败/取消 run、任意重置轮次或自动代批。开发 run 依据现有路由与状态等待设计链，不新增“回修等待”业务状态。

### M3　接管合入、回写与归档，保留工作目录边界

**范围**：`feature-writeback` registry、Runner 与事件接线；daemon 的 Pipeline 绑定、terminal settle；tools 现有 merge/writeback/archive Skill 与深原语合同。

- 代码审批即授权 Runner 执行已有合入、PRD/SDD 回写、任务回写、traceability 与归档节点；不另建合并、归档执行器，不增加发布审批。
- merge 返回 `phase=release-drift`、`advanced` 时是既有 `code-approved → developing` 业务回退，即使退出 0 也不是合并成功。停止交付链，按既有转换持久接回开发修复、测试、评审与代码审批；不能沿旧 code grant 继续，也不能技术重试 merge。只消费深原语实际返回的回退分支，部分发布后的漂移仍保留现有阻断。
- `spec_id`、`target_version` 从 crctl 的 authority 解析和既有机器输出继承，来源为合法 CR 元数据，不从 Issue 标题猜、不让用户在交付阶段重复填写。必要时最小扩展已有输出/载体，不新增查询命令。
- 对齐模板与新模式 Skill：新模式不强行要求 legacy 的 milestone 输入，节点实际接收的参数与深原语一致。缺 spec 或真实版本不静默降级、不生成同义占位值。
- **merge 完成后结束旧 task，下一节点重新绑定 operational workspace**；不能修改仍运行 task 的 env 来跨工作目录续跑，也不能让 server 猜本机路径。
- 归档节点从不会被自身清理的安装根启动，由 crctl 决定业务 authority；安装根继续承载审计、outbox 与 terminal settle。归档清理后重入不得重新要求已删除的 txws 存在，更不能因此绕过 authority 解析。
- `cleanup-pending` 按现有语义属于归档业务成功，不另派清理任务或要求重归档。terminal settle 失败只能触发技术恢复，不是交付完成证明。
- 调整投影与执行的归属：`archived` 事件可更新 CR 展示，但不能抢先关闭 Runner 所属 run、漏掉最终节点结果与收尾。由 Runner 汇合既有归档事实和最终任务结果后完成执行。

### M4　统一持久交接，删除模型与协调者接力

**范围**：既有 start/resume、run 分配、阶段 Reconcile、状态/评审事件接线及相关集成测试。

- 需求批准→设计、设计批准→开发、代码批准→交付，以及合法上游回修、release-drift 开发回修，都走 Runner 的统一交接逻辑，不在 approve Skill 尾部执行 CLI，也不让作者按评论续派。
- `APPROVAL_DECLINED_ROLLED_BACK` 是人工驳回已完成业务回退：停止当前正向路径，不进入技术重试、不沿旧 grant 继续。保留原 Pipeline 的 abort/等待输入要求，是否自动修订及如何接续只由既有路由与输入合同决定，不新增“驳回后一律自动重写”政策。
- 从现有启动逻辑复用并收敛“校验＋创建/接管 run”的内部实现；不复制多套 starter。入口状态不同的回修使用已有合法转换，不扩大普通 start 的任意重启权限。
- 将既有 start/resume 的内部分派与受控接管能力扩展到四阶段，复用已有合同确认参数与权限，不新增命令、flag。当前具名 digest 确认主要在需求切片，设计期并非已具备同等恢复入口；本项必须补齐，不能靠改存量 digest 绕过校验。
- **同一数据库事务**持久化下游 run 的可恢复 context 与上游的完成/交接结果；相关查询、upsert 和更新实际使用同一 `pgx.Tx`，不能外层套事务、内部仍走 `r.pool`。
- 提交并释放上游锁、连接后，再调用下游 Reconcile；事务内不派 task、不调用包含 Reconcile 的完整公开 starter，不嵌套获取下游锁或靠同步事件递归解锁。
- 上下文继承原 source task 的实际 agent 与已有 `started_by` 等事实，不把节点 owner 当来源调用者；保留 digest、workspace 和归因约束。
- 上游批准事实不因下游分配失败而撤销。提交前失败保留可续接上游；提交后崩溃由已存在的下游 run、既有事件/启动扫描及 M7 周期续接恢复。
- 复用活跃 run/node/task 去重。除既有上游回修、release-drift 等明确业务转换外，失败、取消或完成的下游记录不因“当前没有活跃 run”被自动重开；记录矛盾按现有错误与受控恢复处理。合法回修须处理原阶段已完成的情况，不等于复活旧执行记录。
- 注册后的首次接入沿用既有入口与 source context；技术上确定性调用现有接入逻辑，不把“注册后记得 resume”留作模型待办。注册已提交但接入未完成的窗口须能从既有注册/来源事实重入，不伪称 Git 与平台数据库跨库原子。

### M5　ack 回归纯投递确认，删除审批续接分支

**范围**：`internal/governance/approval.go`、`approval_continuation` 接线、`WakeGrant`、workspace 限定 SQL 及现有测试。

四阶段统一后，原方案的“有 Runner 唤醒、无 Runner 找 Leader”双路分流不再作为正常模式保留。

- `delivered_at` 只表示 grant 已实际投递，不表示 crctl 已消费、审批收尾完成或下一阶段已开始。
- 从正常 ack 路径删除 `resolveContinuationTarget`、`EnqueueApprovalContinuation` 及只为续接存在的 reasons 整批回滚逻辑。保留接入认证与 workspace 限定，不在 ack 重跑业务阶段前置。
- 复用现有 workspace＋record IDs 批量更新与幂等；无需为了兼容旧续接再增加逐条事务系统。单条 CR/run 异常不撤销其他送达确认；真实数据库提交失败仍由既有 pending 重投恢复。
- 提交后按实际阶段唤醒对应 Runner；一个 run 唤醒失败不阻断其他记录。Runner 从当前 run、阶段与权威证据消费匹配 grant，不把旧 ack 事件直接当推进指令。
- 终态 CR 不创建新执行；没有活动 run 不解释为推进成功，也不回退 Leader 续接。正常 run 由入口与持久交接保证，缺失的已知存量通过现有入口恢复。
- 唤醒丢失或报错由 M7 从持久 run 续接，不新增“审批已消费”状态、续接队列、去重表或另一套投递重试器。
- 历史显式 `dev-start` 的审批事实和兼容读取保留，但不恢复默认审批卡或自动 Leader 续接。遗留 queued/running 续接任务只作一次性受控处置，不能与新 Runner 并行推进。

### M6　KB 一次接入：项目资源、公钥与 grant 同源

**范围**：`internal/handler/{daemon,daemon_ws}.go`、`internal/daemonws/hub.go`、`pkg/protocol/messages.go`、项目资源 SQL；daemon 的 config/client、heartbeat、collector、根绑定与投递接线；现有公钥输出。

#### 目录来源

1. 通过已有 HTTP/WS heartbeat 增加可选目录资源快照对象。按当前已授权 runtime 的 workspace、daemon 下发完整 `local_directory` 资源；查询限定所属项目，不做列项目再逐项读取的 N+1，不新增 endpoint。
2. WS 将鉴权查询已读取的 runtime `daemon_id` 带入 lease；不能依赖 PAT 上未必存在的 daemon ID，不增加客户端自报身份。沿用既有授权模型与撤销窗口，不宣称新增机器级认证。
3. 两条传输共用读取和消费逻辑，HTTP 手工响应也带出快照；正常 WS 工作时 HTTP heartbeat 会被跳过，不能漏接 WS。
4. 按 workspace/daemon **替换**资源投影而非追加。成功空快照代表移除；缺字段/读取失败不伪装为空、不清掉已有有效投影；后续成功 heartbeat 使改路径、删除、断网恢复收敛。查询失败不得丢失 heartbeat 已领取的 pending actions。
5. 复用目录匹配、路径验证与 KB 识别，每根保留 workspace。采集、Pipeline 定位、terminal settle、pending 与 ack 共用来源；请求沿既有 `X-Workspace-ID` 按 workspace 分组，ack IDs 不串批，不修改共享 client 的全局选择值。
6. collector/投递循环启动不再取决于环境变量非空。冷启动第一次有效 heartbeat 即恢复适用目录，无需先认领任务；账本稍后出现也可按已有节拍识别。新 KB 初始化仍使用既有 `kb init`。
7. 不靠任务历史或本地持久化根缓存恢复接入；runtime/workspace 退出按现有生命周期清理对应运行期投影。普通任务仍受原项目边界限制，发现根不等于授予跨项目访问。

本平台版本移除 `MULTICA_CR_WORKSPACES` 作为根来源，不实现新旧双模式或能力协商。首次快照失败等待后续 heartbeat，不回退环境变量，成功空快照不能被旧列表补回。上线时移除重复配置；新 daemon＋旧服务端不是支持组合。

覆盖前提为该 workspace 有本 daemon 的活跃 heartbeat runtime，且资源指向可识别 KB 根。不递归猜未知嵌套 KB，不将任意产品目录等同于 KB。两处 `CR not found` 补充 workspace/CR、资源、daemon/runtime 与投影线索，不能以改报错替代以上根治。

#### 公钥与 grant

- 已有 pending 响应增加 `public_key: {key_id, pem}`，复用 `PublicKeyPEM()`，不改 crctl 验签算法或增加验钥命令。
- 在所属 workspace 的可信根中复用已有 CR 定位规则确定目标 KB；零匹配或歧义保持 pending，不向全部根广播，不以任意根写成功当作目标投递成功。
- 顺序固定为：**对应公钥就绪 → grant 完整落盘 → 加入 ack IDs**。已有 key 不覆盖；内容冲突、缺对应 key、写失败不 ack，复用 pending 重投；不暴露半份文件。
- 首次安装沿用可信服务端连接，远程使用有效 TLS，本地回环沿既有边界；不把不可信明文响应中的 key 与 grant 当作彼此自证，不另建密钥管理系统。
- 只自动安装当前签发 key。旧 grant 已有对应可信 key 时可消费；缺旧 key 时保留并作已知存量恢复，不声称完整轮换或每台 daemon 副本投递已自动化。
- 运行时文件不制造工作区 dirty：复用 crctl 已有 `.crctl/.gitignore` 默认 `*`，一次性收敛平台 KB 的 `!keys/**` 例外；不删已跟踪信任锚、不覆盖 key，不要求逐 KB 再维护一份忽略配置。

### M7　复用周期续接与任务技术恢复，不要求人工补命令

**范围**：`cmd/server/runtime_sweeper.go`、现有 Runner 事件/启动扫描、TaskService 重试、`pkg/taskfailure/`、daemon 终态载体与 crctl recovery 传递。

- 事件用于及时唤醒，启动扫描用于进程恢复；在既有 runtime sweeper 的 30 秒 tick 接入有界 Runner 回调，按 pipeline 续接 Runner 所属活动 run。限批、超时并隔离单 run 失败，不能阻塞存活检测或饿死其他 run；不新建扫描服务或重试系统。
- 暂态协调错误不立即终止 run。周期续接复用锁、节点与任务去重，覆盖短暂数据库/网络故障、丢失唤醒、提交后尚未派发等窗口；不依赖新事件碰巧到来或人工重启。
- 节点遇到 failed task 时先识别已有 retry child、待补报结果及可恢复技术中断，复用 `FailTaskWithTransition`、`MaybeRetryFailedTask` 等现有机制，不能先结束 run 再指望活动扫描找到它。
- 技术 task attempt 与业务 reviewLoop attempt 分离；恢复沿用原 node-run、责任人、执行权限与审批授权，不重置评审轮次、不重复执行已完成的评审和审批。
- 现有重试分类不是“所有 platform 错误可重试”。保留机器可读 `failure_reason`、crctl 错误码和结构化 recovery；`TX_GIT_FAILED`、`process_failure` 等混合错误不整体加入白名单，更不能让模型凭错误文字猜授权。
- 只消费已证明安全、无需新输入、在原权限内的幂等恢复。复用已有 journal、恢复 argv 与终态补报队列，不新建执行器、补偿文件或重试表。
- Agent 重试沿用现有预算与退避；预算耗尽明确停止、保留现场并报告责任方，不把会抬高预算的人工 resume 入口挂到周期 tick，不承诺耗尽后仍全自动。
- 业务 BLOCK 走既有回修，人工驳回与发布漂移按 M3/M4 消费业务结果，均不进入技术重试。等待版本/人工审批不消耗重试次数；认证、余额、权限、签名或证据冲突不盲重试。显式取消、既有失败终态不被扫描器复活。

### M8　对齐版本输入、模板与提示词，删除最后的接力

**范围**：tools 四阶段模板/registry 合同、`agents/{requirement-writer,dev-agent,quality-reviewer-agent,delivery-agent,cr-coordinator-agent}.md`、相关 Skill 与 `README.md`；线上对应部署产物。

- 注册继续允许 `unassigned`。需求评审前缺真实版本时，沿现有业务输入交互请需求负责人确认，由 Agent 调用既有 `version-set`，Runner 自动继续；不猜版本、不另加审批节点、表单或要求用户运行 CLI。
- 这不是新增前置：现有新模式在需求评审前已要求真实版本。不要拖到代码审批后定版；晚改会改变 PRD/SDD/PLAN/TASK 与 release 摘要，不能承诺旧评审或旧 grant 仍有效。
- spec/version 从既有 authority 和机器输出继承；不完整 legacy 元数据不猜填、不作为另一条正常自动模式。已知存量逐项确认并沿现有可用入口恢复，不批量改账本或绕过门禁。
- 对齐 coding/writeback 模板输入、canonical 结果、reviewLoop 和实际深原语，更新已有索引、导出、生成与 digest 合同；不改变业务节点与产物的必要性，不新增 lint。
- 作者、reviewer、delivery Agent 只执行当前节点。删除评论委派、审批后自行 start、跨阶段“按 next 继续”等重复编排；approve Skill 只完成当前审批收尾，不带下一阶段启动尾命令。
- 协调者不再承接四阶段正常审批信号或启动，只处理入口、异常汇总与必要人类输入。状态、门禁、下一步仍引用 `crctl status/next`，不在提示词复制路由表。
- 简短失败回执展示 CR-ID/registration key、错误与影响摘要；原始输入、机器错误和 recovery 保留在已有 run 记录。key 只是同键同输入的幂等标识，不是全部恢复参数。
- 有权限的 CLI 动作由 Agent 执行，不转交人类复制。tools 源合入后同步线上 instructions 与 Skill/registry 部署，不能把 checkout 更新当作线上指令已生效。

## 5. 发布与已知存量恢复

### 统一发布

1. multica/tools 按上述责任分块提交并带现有测试的修改，先在非生产环境对齐四阶段模板、导出、生成、carrier 和深原语；不把相互依赖的半套行为单独启用。
2. 短维护窗口先暂停受影响的正常派发、领取、投递/ack，保存恢复事实。已运行旧执行须完成或通过现有受控方式停止并确认退出；仅暂停领取不能视为旧 Agent 已停止，不抢改运行中任务。
3. 更新服务端、daemon、tools 及线上 instructions，安排既有进程启停/Runner 开关，使正常调度尚未恢复；不假设存在新维护模式。恢复前完成已知旧任务/重复续接的受控处置，以及旧 run 的 context/digest 接管。
4. 存量接管使用 M4 扩展后的同一受控入口和原有确认参数，不把需求切片已有能力泛称为设计期已有能力；不覆盖 digest、不绕过校验，不做全量自动迁移。
5. 新 daemon 的 HTTP/WS、根快照、公钥和投递接线生效、旧执行与旧续接均已收尾后，再恢复正常领取与统一 Runner 编排，移除环境变量重复配置。旧 daemon 可能忽略公钥却提前 ack，必须避免混跑窗口，不能仅以响应字段兼容保证安全。
6. 发布后不留 Leader 续接兜底。runtime、模板、二进制与线上提示词均核对实际版本，不只看仓库 HEAD；恢复正常调度后执行下述 O2 确认。

### 交还 AIFI-45（O2）

- 重读权威 worktree 的 `crctl status/next`，分别核对服务端投影、各阶段 run 与 task；主 checkout 不作进度依据。
- 通过新采集通道同步事实并处理 pending。已记入权威结果的审批不重新批准，不假设 ack 后一定重放 approve Skill。
- 活动需求 run 由持久交接进入设计；部署前已 completed、当前仍为 `requirement-approved` 且没有设计执行的记录，用既有 `multica cr pipeline start CR-FS-2026-004` 一次性补接。已有设计执行使用 M4 扩展后的同一受控恢复入口，不假称原实现已支持，也不借 start 重开失败或完成记录。
- 派错和重复任务使用现有受控任务入口核对处置，不抢改运行中任务、不手改数据库、CR 状态或账本；缺历史 key 等已知异常同样一次性恢复，不增加常驻修复机制。
- 以权威状态、run/task 归属及 canonical 结果确认设计可继续，再将 AIFI-45 从 `blocked` 改为 `in_progress`。ack 200、task 排队或进程退出 0 都不单独证明进入设计期。

这是一次性 Agent/运维动作，人类仅提供必要业务确认和授权。未知历史记录不纳入全量自动修复承诺；Issue 状态也不替代 CR 阶段。

## 6. 验收与验证方式

以下替换旧验收，不新增运行时门禁或交付报告文件。

| 项目 | 完成判据 |
|---|---|
| 四阶段执行 | 不只产生投影 run；registry、claim、派发、结果和恢复均接通，含 checkpoint/freshness 的共享节点按已授权执行绑定派发，独立 reviewer 不变，无统一执行者技能检查 |
| 自动阶段交接 | 三个既有审批后的后续阶段自动分配；并发、重入及交接提交前后故障不漏接、不重复派发、不要求作者补命令 |
| 开发期 | 任务账本、真实测试、dev-plan/code 证据正确消费；普通 BLOCK 按既有 loop 修复，不把 task completed 当业务成功 |
| 上游回修 | 同 CR 按合法回退先技术复评，再必要修订、重审、既有设计审批并恢复开发；不沿旧 PASS、不重置轮次 |
| 业务回退 | 人工驳回保留原 abort/等待输入合同，不技术重试；merge 的 release-drift 即使退出 0 也停止交付、接回既有开发回修并重新审批，不沿旧 grant 合入 |
| 交付归档 | 代码批准后自动合入回写归档；输入不重复填，merge 后新 task 绑定 txws，归档自清理和 cleanup-pending 可正确收尾，投影不抢先结束执行 |
| 审批与 ack | 送达确认不查 Leader、不派重复续接；单 CR 唤醒失败不撤销其他 ack；缺 run、终态、旧 grant 均不假推进，唤醒丢失可自动续接 |
| KB 接入 | 资源已指向 KB 时不另填环境变量；HTTP/WS、无任务冷启动、目录稍后出现、改路径、删除、断网恢复均收敛；请求 workspace 正确，不串根/串批 |
| 公钥投递 | 新 KB 不手拷当前 key；目标 key、grant 就绪才 ack；冲突、缺 key、写失败、目标歧义不假成功，已有 key 不覆盖 |
| 自动恢复 | 注入短暂数据库/网络、丢失事件、进程中断后无需手动 start/resume/重启；已有 retry child 和终态补报不被误判为业务终结 |
| 恢复边界 | Agent 重试不增加预算或重置 reviewLoop，耗尽明确停止；取消不复活，权限/签名冲突不盲重试，人工 gate 不越过 |
| 版本与提示词 | 未排期可注册，需求评审前完成版本确认；正常全程无协调者评论接力、Skill 尾启动或重复元数据填写，线上指令与源一致 |
| 发布与存量 | 无旧 daemon 提前 ack 窗口；已知在途记录受控接管，AIFI-45 可继续工作，不重复审批、不批量改历史 |

验证复用现有 Runner、任务重试、审批、daemon heartbeat/collector/grant、回写/归档及提示词合同测试，按变化修改断言并补最小回归，不建新测试平台或要求评审者重复全量测试。

- multica 在 `server/` 运行对应 Go 测试，包含实际修改的 governance、service、handler、daemonws、daemon、协议和 sweeper 范围；SQL 与 registry 使用已有生成/一致性检查。
- **governance 必须连到测试数据库并确实执行**：其 TestMain 在数据库不可达时可成功退出。PR 摘要区分实际执行与跳过，不拿空跑退出码作证据，不操作共享生产实例。
- tools 复用现有 lint、Skill 矩阵、Agent 合同、registry 导出及所改深原语测试。跨仓模板 digest、导出与编译产物一起对齐，不新增另一份节点事实源。
- multica 代码按现行 `CUSTOM.md` 结构登记，追溯本维护 Issue，不编造 CR/TASK 编号。证据摘要留在已有 PR/Issue，不新增过程产物。
- 所有主线验收完成后，本维护 Issue 才置为 `in_review`。只修报错、只解阻 AIFI-45、只接两阶段或仅保证“可人工恢复”均不算本方案完成。

## 7. 本次不做

- 不裁减业务产物与既有评审审批，不给作者增加评审技能，不把 Issue 改派 squad 绕过错误模型。
- 不新增状态、审批节点、用户命令、flag、健康检查、账本、独立扫描/重试系统或通用工作流引擎。
- 不保留四阶段之外的正常 Leader 续接或新旧双模式；本地 crctl/TTY 能力不因此取消，但不作为平台自动编排兜底。
- 不递归发现未知 KB，不新增全量资源 endpoint、持久化根账本、配置版本同步系统或机器级认证。
- 不做完整历史密钥轮换、多 daemon 副本协议、全历史元数据与已完成 run 自动修复。
- 不无限重跑 Agent、不自动追加模型预算、不绕过权限/证据/人工审批，不把取消当暂态故障。
- 不包含生产部署、安装包发布；CI 账单、停用/恢复和历史 Windows 基线失败另作运维决定，不转为每次人工全量复跑，也不捆绑 Ubuntu CI 恢复条件。

**完成标准：一次业务确认只作一次，正常推进只有一个编排者；接入不重复配置，暂态故障自行恢复，异常不静默假成功。**
