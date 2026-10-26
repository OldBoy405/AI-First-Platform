# Design addendum：multica dispatch admission（AIFI-45）

> 产出方式：STDD `design` 档（`model_tiers.design: strong`）只读作者会话 `01a176d1-9357-77b9-a3c5-0f3eb9480d39`；requested `OpenAIPersonal/gpt-6.1-sol:high`，actual 无后端回执 = unknown。作者只读、不能写文件；本文件由主会话按其最终回复原样落盘。
> 状态：历史设计草案，非 Gate3 批准；整体未作为实施许可。
> 当前执行状态（主会话补注，2026-10-26）：仅 §4 的 F4 锁修复已按用户授权实施、RED→GREEN，并完成独立 strong 代码复核（无 F4 finding）；见 CUSTOM #199、`f4-run009-review-20261026-strong.md`。其余新增接口、可信 reader、Tx primitives 尚未实现。下文“当前 helper 仅锁 cr”等为修复前快照，定位以符号名而非旧行号为准；不据本草案宣称完整准入已交付。

Change：`2026-10-22-aifi-45-authorized-execution`。
路径约定：`M=C:/Users/GOBAO/Downloads/AI/multica`；`G=M/server/internal/governance`；`T=C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts`。
作者本次仅 read/grep 核查；没有修改文件、运行测试或访问数据库。以下新增接口均为 **PROPOSED**，不冒称已经存在。

## 1. Scope、事实复核与非目标
- 增加可注入、逐 effect、fail-closed 的 admission 边界；授权签发、binding、平台 consumption/activation 均不是 dispatch permission。
- **不增加 env switch；不改 DB test runner 或其 arg whitelist；Gate3 人工批准前不在 `main.go` 接入 `AdmissionDecider`；不实现第二套 budget、no-progress、evidence 或 sensitive-action 决策引擎。**
- 保留现有 legacy 行为、签名字节和协议域；不通过 `FeatureFlags`、manifest 配置或 Agent 请求偷偷启用 admission。
- **题述“production nil”需要纠正**：`RouterOptions.ExecutionContract` 及 nil→503 注释确在 `M/server/cmd/server/router.go:249–252`，`FeatureFlags` 在 `:248`；但 production 已有 manifest loader 和注入，见 `main.go:341–342,712`。只有未提供两项 manifest 参数时返回 nil（`G/execution_contract_manifest.go:42–47`）；不能断言 production 永远 nil。测试显式注入见 `M/server/cmd/server/execution_authorization_head_test.go:84–88`。
- claim 注释准确：`M/server/internal/daemon/execution_task_claim.go:22–23` 明言只读平台 claim metadata，不是 admission evidence。
- plumbing 已核实：授权 routes（`G/execution_authorization_routes.go:20–60`）；643 binding ledger（`M/server/migrations/643_cr_execution_binding_issue.up.sql:5–19`）；644 consumption、645 activation 按 generation 唯一（相应 `.up.sql:8–23,9–25`）。
- notices API 已核实：`G/execution_notice.go:235,387,464` 分别为 `DeliverNotice`、`BusBroadcaster`、`ResolveNoticeRecipient`；646 为独立 notice ledger，不授予执行权。
- dispatch root 647 的结果语义准确（`G/execution_dispatch_root.go:84–96,172–210`）；**“cap 3”是调用者必须执行的错误边界，不是计数不会超过 3**：第四次仍先递增再报错（`:219–239`）。
- Runner 位置准确：`G/runner.go:548,682,729,1013`；实际 enqueue 在 `:1040`。但它不是全阶段唯一入口：requirement 还有直接 enqueue（`G/runner_requirement.go:674`），writeback 在 `G/runner_code.go:317`。
- **nil 的兼容目标只能是“无新增授权自治派发”**，不能声称今天没有任何自动派发：现有 deployment switch 在 `G/runner.go:58–65`，router 已按其构建 Runner（`router.go:1608–1614`）。本片不修改该旧开关。

## 2. `DecideAdmission` contract
### 2.1 接口、显式请求与可信输入
```go
type AdmissionDecider interface {
    DecideAdmission(context.Context, pgx.Tx, AdmissionRequest) (AdmissionDecision, error)
}
```
`AdmissionRequest` 是进程内类型，不绑定 HTTP JSON：包含 `WorkspaceID, CRID, RunID, Intent, Candidate`。
`Intent` 闭集为 `NewRoot | AdvanceActualState | VerifyExisting | Resume | SensitiveAction | Adopt`。
`Candidate` 精确包含 `PipelineID, NodeID, NodeRunID, Attempt, SourceTaskID, ExecutorAgentID, ProposedTaskID, SubjectRef, LogicalStep`；现有任务另带 `TaskID, RuntimeID, DispatchedAt`。
仅 `SensitiveAction` 可带 `{Kind, Target, Environment, OperationID}`；仅 `Adopt` 可带 `{FromRootID, MappingRef}`；仅 `Resume` 可带 `ResumeGrantRef`。不适用字段必须为空；未知 intent、字段组合或来源一律拒绝。
这些值只是定位符/候选值；decider 必须在调用者事务中重读并校验下列完整输入，不能信任候选值自证：

| 输入及精确内容 | Trusted source／现有锚点 |
|---|---|
| `Contract{PolicyVersion,PolicyDigest,TemplateDigest}`、签名验证器 | pinned operator manifest；`G/execution_contract_manifest.go:42–123`；复用 head verifier 的签名检查，`G/execution_authorization_head.go:99–143`。 |
| `Scope{WorkspaceID,ProjectID,CRID}`、`AuthorizerUserID` | workspace-scoped `cr→issue→project→approval_record`，`M/server/pkg/db/queries/approval.sql:25–35`；签名/source 与该身份交叉检查，`G/execution_authorization_head.go:132–204`。不接受 Agent 自报 actor。 |
| `Run/Step{RunID,PipelineID,NodeID,NodeRunID,Attempt,SourceTaskID,ExecutorAgentID}` | persisted run/node/task + compiled registry；`G/runner.go:492–531,1013–1044`。task attribution 必须继续从 source task 继承，`M/server/internal/service/task.go:395–402`。`ProposedTaskID` 仅由服务端生成。 |
| `Generation{TaskID,RuntimeID,DispatchedAt,DaemonID,Status}` | 实际 DB task/runtime/agent join，`M/server/pkg/db/queries/execution_binding.sql:7–18`；不是请求 header，也不是 PID。历史收尾使用已持久化绑定，不要求已完成任务仍满足 active claim。 |
| `Head{RecordID,GrantID,LineageID,GrantDigest,Revision,Purpose,Source,ScopeBindings}` | 同锁下的 current pointer + signed record；`approval.sql:25–35`、`G/execution_authorization_head.go:99–204`、`G/execution_authorization_revoke.go:349–390`。不能以 initial 历史替代 current head。 |
| `PlatformProof{Issue,ConsumptionID,ActivationID,Challenge,GrantDigest,Generation}` | 643/644/645 ledger，必须全 tuple 相等；`G/execution_consumption.go:168–210`、`G/execution_activation.go:166–218`。这些只是必要条件，不证明 T 已提交业务消费。 |
| `TDecision{Schema,Scope,Lineage,Origin,LogicalStep,GenerationBinding,Subject,HeadDigest,Revision,CommitRef,ReceiptRef,Disposition,Code}` | T 已提交事务经可信控制通道验证后的结果。规则源：`T/lib/repair-governance.mjs:165–255,331–410`；evidence 源：`T/lib/evidence-delivery.mjs:30–112`。**UNVERIFIED：该完整传输/绑定协议目前不存在可核实实现。** |
| `ResumeProof{SignedGrantRef,StopRef,Subject,Epoch,CommitRef}` | T 验证签名恢复授权并提交后的结果；现有 `resumeRepair` 仅核 reviewer/current subject 并写 epoch（`T/lib/repair-governance.mjs:412–458`），不能冒称已证明 signed resume。 |
| `Action{Kind,Target,Environment,OperationID,ActionScopeID,ReceiptRef,Replayed}` | 请求对象是候选，许可仅来自 T 的精确匹配与消费结果；`T/lib/execution-sensitive-action.mjs:72–130`。M 不自行比较额度或扣额。 |
| `Root{ID,LogicalKey,RootTaskID,Generation,Terminal,Attempts}`、`AdoptionMapping` | 647 持久行及服务端重验映射；`G/execution_dispatch_root.go:47–68,159–210`。`Adoption.Verified` 布尔值本身不是可信证据（`:39–44`）。 |

`SubjectRef`、`LogicalStep`、origin 必须解析到 T 已接受的具体对象/阻断，而非 Agent 标签；origin derivation 现有锚点为 `T/lib/repair-governance.mjs:47–53`。
逻辑 key 提议：`SHA256(domain || scope || lineage || immutable_origin || original_logical_step || optional_action_scope_and_operation)`；不含当前 run/runtime/task、cycle、revision 或 template，防止换执行身份重开根。
**UNVERIFIED：现有 T repair receipt 没有上述完整 run/node/generation 绑定；必须补可信映射，不能直接接受 CLI stdout。**

### 2.2 输出与闭集 decision codes
`AdmissionDecision` 精确为 `{Code, Effect, BindingDigest, HeadRecordID, Revision, TCommitRef, TReceiptRef, RootID, RootTaskID, RootGeneration, ReasonCode}`。
`Effect` 闭集：`None | AdvanceActualState | EnqueueRoot | ContinueExactRoot | SettleOnly | LegacyPath`；permit 仅限当前事务、当前候选 effect，不可缓存或通过网络转交。
`ReasonCode` 仅作诊断，可保留 T 原错误码；不能据其文本放宽许可。

| Code 闭集 | 唯一许可 |
|---|---|
| `ADMIT_NEW_ROOT` | `EnqueueRoot`；有效 T 已提交许可，且该 logical key 无根。 |
| `CONTINUE_EXISTING` | `ContinueExactRoot` 或 `AdvanceActualState`；仅精确既有 root/receipt；action replay 为 `None`，返回原引用。 |
| `WIND_DOWN_ONLY` | `SettleOnly`；接收已有任务结果、保存审计和安全终止，不新启动代码、不推进业务阶段。 |
| `LEGACY_UNCHANGED` | `LegacyPath`；仅明确证明仍属 legacy、未迁移的对象；不是新授权能力。 |
| `WAIT_AUTHORIZATION`, `WAIT_CONSUMPTION`, `WAIT_EVIDENCE`, `WAIT_ADOPTION` | `None`；等待不是授权。 |
| `DENY_BINDING`, `DENY_REVOKED`, `DENY_STOPPED`, `DENY_T_VERDICT` | `None`；额度耗尽映射为 `DENY_T_VERDICT`，M 不计算额度。 |
| `DENY_SPECIAL_AUTHORIZATION`, `DENY_RESUME`, `DENY_TERMINAL`, `DENY_UNAVAILABLE`, `DENY_UNKNOWN` | `None`。 |

零值、未知 code/effect、缺少必填引用、DB/网络错误、deadline、未知 T schema 均不得产生 effect；`error != nil` 时输出许可无效。
`LEGACY_UNCHANGED` 不能由“缺少新字段”推断；无法证明合同选择时为 `DENY_UNKNOWN`。

### 2.3 求值顺序（首个适用结果，未知即拒绝）
1. 严格校验 request/intent、可信部署合同、authoritative contract selection、DB scope、step、generation、subject 和来源绑定；任何串租户/串对象为 `DENY_BINDING`。
2. 按 §4 锁序读取 current head、root 和已提交 admission 映射；terminal root 不得重新入队。禁止先按 receipt replay 短路 current-head 校验。
3. 若请求是**精确已准入任务**的收尾，先识别其持久许可：revoked/stopped 时最多 `WIND_DOWN_ONLY`；不可达时也只能做本地安全收尾，不能新建验证任务。
4. 对 new/advance/resume/adopt/action，缺 head 为 `WAIT_AUTHORIZATION`；撤销为 `DENY_REVOKED`，不可用/损坏为拒绝。已有 receipt 不豁免此检查。
5. 必须同时具备匹配的平台 proof/consumption/activation **和 T committed consumption**；ACK、binding 或 activation 单独存在均为 `WAIT_CONSUMPTION`。T 未提交前不得创建 execution task 或标记节点 passed。
6. 消费 T verdict：stop→`DENY_STOPPED`；拒绝/额度耗尽→`DENY_T_VERDICT`；pending→`WAIT_EVIDENCE`；不可达→`DENY_UNAVAILABLE`。不得从 `consumed/limit`、blocker 数或本地计数反推放行。
7. 最后一个已准入任务的 `VerifyExisting` 可依据 T 的精确 continuation verdict 继续，即使新 admission 被拒；绝不能把其旧 receipt 搬给新 origin/root。
8. `Resume` 必须有 T 验证并提交的 signed resume、匹配 stop/subject/epoch；普通请求、剩余额度或旧 repair replay 不解除 stop。revoked lineage 不能靠 repair-resume 复活。
9. `SensitiveAction` 必须有 T 对 exact kind/target/environment/operation 的消费结果；缺专项许可即拒绝。replayed receipt 只查回原执行引用，不再次执行或再次索要同事实确认。
10. 有既有 root、无有效 adoption mapping→`WAIT_ADOPTION`；重验通过也只接管同一 root task。新 root 仅在全部通过后与任务一次提交；之后广播。

## 3. Injection seam、单一调用点与事务边界
- 新增 `RunnerOptions{AdmissionDecider AdmissionDecider}` 和 `NewRunnerWithOptions`；保留 `NewRunner` 为零 options 包装器。构造锚点为 `G/runner.go:538–555`，不修改现有调用方默认行为。
- concrete decider 由测试 composition root 构造：`NewAdmissionDecider(contract, headVerifier, trustedTReader)`；集成测试注入真实实现，stub 仅用于故障注入/调用次数验证。
- `RouterOptions.AdmissionDecider` 仅供测试转交 Runner；production 保持 nil。原 `ExecutionContract` wiring 不等于此新 wiring。
- **唯一 `DecideAdmission` 调用表达式**放在新增 `Runner.reconcileAdmissionLocked` 中；architecture 接入的精确现有锚点是 `Runner.Reconcile` 的 `G/runner.go:721`（当前调用 `reconcileLocked`）。新增函数尚无现有行号，不能伪造。
- 不能只在 `enqueueNodeFor:1040` 前加判断：旧 walker 会先写 passed（`runner.go:741,778`），requirement 又有独立 enqueue（`runner_requirement.go:674`）。
- 非 nil 路径须将现有遍历拆为“只读 plan → 单一 decider 调用 → 一个受限 effect → 重读”；不得在获得许可后直接运行整段可变旧 walker。
- 四阶段入口、manual resume 都必须汇入该 helper，且在各自第一项 mutation 前分流：`runner.go:682`、`runner_requirement.go:31`、`runner_code.go:28,317`；resume 的直接 retry 在 `runner_requirement_resume.go:290,337` 不能旁路。
- nil 路径直接走原函数体：不构造 T reader、不加 DB read/lock、不新订阅 wake、不创建 root/notice。这样保留旧请求/队列/事件行为；用 nil 基线差分测试证明，而非声称 machine code 相同。
- decider 不提交事务、不发消息、不调用 executor；调用者使用同一 `pgx.Tx` 完成检查、root/adoption、固定 task ID 入队及推进，commit 后通知。
- **必须补事务型 root/task primitives**：当前 root 自开/提交事务（`execution_dispatch_root.go:112,146`），TaskService 使用自身 Queries 并立即通知（`M/server/internal/service/task.go:417–460`），不能直接组合成原子 admission。
- 新增 `admitDispatchRootTx`、带固定 task ID 的 `EnqueuePipelineTaskTx`；legacy wrappers 不变。root 重读加 `FOR UPDATE`，adoption UPDATE 加 terminal/generation CAS，防现有 `execution_dispatch_root.go:159–201` 的检查后竞争。

## 4. F4 disposition、F2 与 F1
- **选择 (a)：先修 F4，再允许注入真实 admission 取得正许可。**
- 当前 helper 仅锁 `cr`（`G/execution_head_lock.go:27–39`）；这确实阻塞 revoke 的 `FOR UPDATE OF c` 和 pointer CAS（`G/execution_authorization_revoke.go:210–216,310–317`），不锁 `approval_record`。
- JOIN fail-closed 只覆盖“head row 删除先于查询提交”；校验后删除仍可穿过窗口，不能称整个窗口安全。head JOIN 见 `approval.sql:25–35`。
- 修复共享 helper：在同一 READ COMMITTED 事务按 **CR row → referenced approval head row → scope/resource rows → root** 顺序取锁；head record 取 `FOR SHARE`，锁后重读并验签。binding/consumption/activation/admission 全部复用；删除先赢则拒绝，校验先赢则删除等 commit。
- concurrency 测试必须探测真实 conflicting UPDATE **及 DELETE**，不能比较 `created_at`；现有 race test 仅探测 CR UPDATE（`G/execution_revocation_race_test.go:30–94`）。
- F4 residual：superuser/DDL 绕锁、T Git 与 M DB 非分布式事务、许可提交后的撤销与已运行进程不能被此锁回收；必须保持新 admission 关闭、已有任务安全 wind-down。
- F2 已核实：issuance replay key 不含 task/runtime（643 migration `:19`；`execution_binding_issue.go:251–259`）。消费只查 head/challenge 的 EXISTS（`execution_consumption.go:171–176`），不能把它当精确 generation proof。
- admission 必须核 issuance 所存 runtime/task/daemon、signed envelope、consumption/activation 全 tuple。647 只解决**同一稳定 logical key 的重复 root**，不修正错误身份绑定；换 key 或错误 key derivation 仍可绕过。
- F1 已核实并保留为已知限制：per-run URL 由随机路径构成并交给 child（`M/server/internal/daemon/execution_binding_endpoint.go:30–32,84–102`）；持 URL 者可请求该能力，不证明进程身份。不得将此 endpoint 扩成 admission/resume oracle。

## 5. TC 实施与 RED mutation
统一 Arrange：隔离 DB、自建身份与 CR；真实 `Auth`/workspace route + 注入真实 decider；统计该 fixture 新增 task/root/effect，排除明示的 bootstrap 基线。
每例须有可派发的正对照、decider 调用观测、完整 DB 身份/receipt 断言；只有拒绝 HTTP、或只注入恒拒 stub，不算业务 TC。

| TC | Seam 与核心断言 | 必须使测试 RED 的单一 mutation |
|---|---|---|
| **002** | `NewRouterWithOptions` + decider；task-token、伪 `X-User-ID`/actor、普通 member 越权、Agent candidate packet 经真实授权 route。无有效 grant/head、无新增 root/task；actor 取 middleware 身份。另以真实 owner 请求证明本测试配置能成功签发并经 admission 派发。 | 删除 `M/server/internal/middleware/auth.go:135` 的 task-token actor 标记；让 originator 为 owner 的 task token 暴露为人类，必须被 TC 捕获。 |
| **003** | 真实 `/approvals/ack` + committed wake + `ResumeActiveRuns`；用 barrier 留住 T commit。ACK 后仅 delivery/wake，`WAIT_CONSUMPTION`、节点不 passed、无 task/root、无旧 continuation；T commit/投影后重新读取实际状态，只派正确下一步；重复 wake 不增加执行。 | 将 missing-T-commit 的 `WAIT_CONSUMPTION` 分支改成允许当前候选 effect；必须破坏 decision/effect 零副作用断言。 |
| **006** | trusted T adapter 故障 seam + 真实 root/task/resume；分别覆盖 reject、stop/no-progress、unreachable、quota 刚耗尽且有旧 receipt、revoked revision。新 admission 均无新根；原精确任务可完成验证/收尾；revoked 只能 settle；无签名 resume 不恢复，合法 resume 仅一次 epoch，且不复活 terminal root。改传输中的 consumed/limit 不改变 T verdict 的裁决结果。 | 将 `REPAIR_QUOTA_EXHAUSTED` 映射为 `ADMIT_NEW_ROOT`；“有旧 receipt 仍拒绝新 admission”断言必须 RED。 |
| **010** | 真实 T sensitive-action consumer + 注入 decider + 可观测、支持 operation-id 幂等的测试 executor。普通授权无动作；exact 专项一次消费/一次执行；同 operation redelivery 返回原引用；target/environment 改变拒绝；通知/确认数不因同事实重放增加。 | 删除 `T/lib/execution-sensitive-action.mjs:90–91` 匹配中的 target equality；对象变化反例必须产生 RED。 |

- **无注入时会 vacuous 的断言**：002 的“无执行任务”、003 的“消费前无派发”、006 的“拒绝新根”、010 的“缺专项无动作”都可能仅因 admission 从未启用而通过；正对照与调用观测不可省略。
- ACK 已是 delivery-only（`G/approval.go:605–626`），execution-stage ACK 当前还跳过 callback；003 不得声称测试过不存在的 callback，应分别覆盖普通 stage ACK、execution ACK 的纯 delivery，以及周期 wake。
- notices 只消费 decision reason：commit 后经既有 recipient/dedupe/delivery API 发出；ACK/progress 保持 silent（`execution_notice.go:50–57,130–135`），不将提醒当许可。

## 6. 依赖、风险与验证顺序
1. 先 F4 锁修复及真实 UPDATE/DELETE race RED→GREEN；再加 nil 回归、闭集 decoder/default-deny 单测。
2. 接事务型 root/task primitives、单 effect Runner seam；覆盖每个入口、adoption/terminal 并发、T commit 后 DB 前和 DB commit 后丢响应恢复。
3. **UNVERIFIED／阻塞正向完整 TC**：可信 T committed verdict transport、generation→pipeline-run 映射、authoritative contract-selection 读源及 signed resume 验证尚未核实；现有 `T/crctl.mjs:1892–1894` 仍明确 `EXECUTION_CONSUMPTION_REQUIRED`。不能用平台 receipt、磁盘 JSON 或 Agent stdout 替代。
4. T repair CLI 目前只读 payload、并非完整验签入口（`T/crctl.mjs:1596–1617`）；本片只能消费经可信链验证的 T verdict，不把该 CLI 当前输出升级成安全授权。
5. sensitive ledger exactly-once consumption 不等于外部副作用 exactly-once；executor 必须以 operation ID 持久幂等，未知执行结果先查原操作，禁止新 ID 重做。
6. 验证沿用 `M/scripts/aifi45-db/run.mjs:63–69` 已允许的 package/flags/migrations，逐命令独占可丢弃 DB；runner 自检、原库摘要、精确 cleanup、非零 leaf、无全 SKIP 都必需。不改变 runner 以让测试变绿。
7. 每个 TC 保存真实 RED/GREEN、raw logs、所选测试名与 mutation diff；stub/组件通过不冒称完整 TC。最后独立核查所有 mutation/queue/resume 旁路，再由人类决定 Gate3 与 production wiring。
