# 可信 T committed verdict channel：实施方案 v0.5
> 原文件原位修订；保留历史 v0.1 与 v0.2 评审记录，不冒称旧评审覆盖新增设计。
> v0.3（2026-10-26）：落实用户“D8 选 A；D7 同意挂到通道 change，并给出独立解决方案，在原方案文档修订”。D7 完整方案见 Spec §7、S8；D8 见 Spec §5。
> v0.4（2026-10-26，经三路复核补正）：按用户要求，把 Gate3 评审（`V/gate3-review-20261026/`）待办 B 中**必须依赖可信 T 已提交裁决、受保护 store 或持久 selection 才能修好**的项并入本方案对应位置；逐项核实与归属见 `V/backlog-b-disposition-20261026.md`。不并入（AIFI-45 就地修或决策）：B1 签发/消费绑定完整 generation、B2 锁图与行锁、B3 过渡 fence 事实、B11 实际 diff、B12a EVD-005 报告与收集接线、B16 RPR 业务身份规则、EVD-001/002/004 gate 接线；B13、B15 改为决策项。v0.4 增量由主会话起草（不是 `01a176ef` 作者会话）；初稿经 strong BLOCK、balanced/economy INCOMPLETE 后补正，复核记录 `trusted-verdict-channel-v04-review-20261026.md`。v0.4 新增内容不继承 v0.3 的计划级结论。
> v0.5（2026-10-26）：落实用户“采纳”B11 挂接建议。AIFI-45 已交付只读自检命令 `crctl authorization-scope`（`V/tc-coverage-20261025T153000Z.md` 增量 25/26），并在 `implement-code` 增加执行者自检步骤；它们**不是强制闸门**。**merge 强制范围核对**需要本方案的持久 strict selection 与可信当前 grant/当前平台绑定，因此并入 Spec §3 与 S5。v0.5 增量由主会话起草，已经两轮三路复核（首轮 strong BLOCK / balanced.incomplete / economy.incomplete；修订后第二次复核三路均 BLOCK，见 `V/trusted-verdict-channel-v05-review-20261026.md` 与 `V/v05-rerun-20261026T235224Z/CLOSEOUT.md`），**当前仍是修订稿，BLOCK 未解除**，不继承 v0.4 的复核结论。
> 作者身份沿用：STDD `design/strong`，作者会话 `01a176ef-402a-77b9-a3c5-0f47830ba4c7`；requested `OpenAIPersonal/gpt-6.1-sol:high`，actual 无后端回执，记 unknown。
> **状态：已搁置（用户 2026-10-26 决定）。**本方案暂不实施，由用户自行另开 change；本文件仅存档备查，在 AIFI-45 内不作为待办、不得据此建 change、建目录或写源码。
>
> 历史评审：v0.2 的三路计划级结论见 `trusted-verdict-channel-v02-review-20261026.md`；不得沿用为 v0.3 的批准。v0.3 由主会话整合；D7 的 STDD design/strong 只读顾问会话 `01a17769-d4a5-77b9-a3c5-0f5ce38d3fc4`（requested `OpenAIPersonal/gpt-6.1-sol:high`，actual unknown）提供独立方案建议，非 Gate3 或上线许可。v0.3 新增设计经独立复核补正后：strong APPROVABLE-AS-PLAN、balanced SUFFICIENT-AS-PLAN、economy PASS；均仅计划层，见 `trusted-verdict-channel-v03-review-20261026.md`，不表示已实现、动态验证或可启用。
> 本文件暂存 AIFI-45 `validation/` 仅为依赖资料，不属于 AIFI-45 实施范围，也不表示新 change 已注册；未来实现与验证产物须在新 change 登记后进入其自身记录目录。
> 本次仅修订方案与决策记录；未修改产品源码、运行产品测试、访问 DB 或验证部署。以下新增接口、文件、协议、表及测试均为 **proposed / UNVERIFIED**，不表示已经存在。

## Goal
- 将 T 实际提交的 execution consumption、repair admit/outcome/assessment/stop/resume、exact sensitive-action consumption、evidence-delivery verdict 转为可验证、可恢复、完整绑定的 admission 输入。
- 所有预算、重试、no-progress、evidence 与专项规则仍只在 T 求值；M 只验证来源、绑定、顺序及事务效力，不增加第二套规则引擎或摘要算法。
- **不增加第三个 Foundation change。**新 Channel change 自己拥有首个可独立真实验收的 Foundation 切片；完整 AdmissionDecider、单 effect Runner、全业务 E2E 留给 AIFI-45。
- 组件通过不自动回填 AIFI-45 的 TC-RUN-002/003/006/010，不改变原 41/49，不跨 change 双计。
- **D7 由本 Channel change 拥有**：交付 EVD-007 / RUN-008 共同依赖的独立部署就绪控制面；T 唯一求值、M 原子启用，禁止新增 Go 规则引擎。完整业务 TC 仍由 AIFI-45 各自验收；EVD-009 发布恢复接线不转移到本方案。
- **D8 已决定不迁移存量**：仅合规新 CR/新 lineage 切入，不提供 legacy 业务历史迁移入口；旧 run/合同/历史不变，不以新 lineage 清零债务。范围决定不等于 EVD-008 整条功能已完成。
- **v0.4 并入 Gate3 待办 B**（编号见 `V/backlog-b-disposition-20261026.md` §1）：B4/B12b strict 与合同选择不可降级（M、T 两侧；legacy 须由可信历史目录证明）；B5 repair-admit 只认验签 grant，额度事实绑定 command；B6 sensitive 账本整体进受保护 store（额度键与幂等键分离、旧账本连续、授权效力在 M settlement 线性化）；B7 F1 改为 daemon 自填进程事实 + 每 run 私有 socket + pidfd 进程树校验，P0 身份隔离仍是主控制；B8 dispatch_root adoption/terminal 并发；B9 repair 追加授权新域与 CAS；B10 签名 resume（既有 S5）；B3 终态 fence 最终规则 = 持久单调 fence 事实 ∪ strict selection。B14 正链不放行维持原设计。B15 的原消费引用在本方案提供消费裁决后由 AIFI-45 绑定；原操作冻结语义另为决策项 X5。
- **v0.5 并入 B11 的强制部分（经 balanced/economy 复核修订）**：merge 前强制做 SC-AUTH-004 范围核对。三项输入各自的权威来源见 Spec §3，且**不得由 `--grant`、`--workspace` 等调用方参数或 agent 可写文件单独决定**：selection 读 M 持久事实，grant 读 M 当前 head，改动集合必须覆盖 merge 实际发布的提交区间。判定**规则**复用 AIFI-45 的 `evaluateChangeScope`（纯函数），**收集**侧新写（见 §3“复用边界”）。
- 路径：`M=C:/Users/GOBAO/Downloads/AI/multica`；`G=M/server/internal/governance`；`D=M/server/internal/daemon`；`T=C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts`。
- `V=C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation`；引用以路径及符号为准，行号仅当前快照。

## Architecture
### 已核实基线与纠正
- 已完整阅读 `V/trusted-verdict-channel-review-20261026-strong.md`、`V/f4-test-doc-review-20261026.md`、历史 v0.1 与 dispatch-admission design；strong 的 BLOCK 针对 v0.1，不是 Gate 决议。
- **F4 已完成，不是本 change 待实现项。**`G/execution_head_lock.go::lockExecutionAuthorizationHead` 同事务锁 CR 及 workspace/CR-scoped referenced head；新 effect 复用，不另写弱化版本。
- `G/execution_head_row_lock_test.go::TestExecutionBindingHoldsTheHeadRecordLockAcrossValidation` 的 binding 路径具有独立 UPDATE/DELETE 夹具、仅认 SQLSTATE `55P03`，提交后同 SQL 影响一行；不声称另两处理器也各有该探针。
- 既有 `V/f4-lockstate-20261026-regression-v2.meta.json` 记录 256/256、0 fail/skip、229 PASS leaf；这是既有证据，不是本次复跑或 Channel 验收。
- RUN009 run 补丁已撤回，缺陷仍在：稳定轮次/代次绑定、乱序评审及 Runner 终态同步不能宣称已修；见 `V/f4-run009-review-20261026-strong.md`。
- `G/execution_dispatch_root.go` 已有永久 logical root、terminal/adoption/cap 约束；`M/server/internal/service/task.go::EnqueuePipelineTask` 已从真实 source task 复制归属；**caller-owned Tx、fixed-ID enqueue、postcommit notification 尚须实现**。
- `D/execution_verifier.go::prepareClaimedPipelineTask` 当前使用 trigger 文本判 strict；新可信选择不能继续依赖它。`execution_task_claim.go` 的 claim metadata 不是 admission evidence。
- v0.4 只读核实（行号为当前快照，经 strong 复核更正）：`T/crctl.mjs::readRepairGrantPayload`（约 `:1600-1618`）只解码 `payload_b64`，校验 CR/非 revoke 后直接把 `repair_limit` 交 `admitRepair`（约 `:1736-1745`）。execution grant 的静态验签在 `T/lib/execution-authorization.mjs::readExecutionGrant`/`verifyExecutionEnvelope`（约 `:300,:321`），只证明包有效，**不证明当前 head/未撤销**。`cmdSensitiveAction`（约 `:1827-1837`）的账本是 `grant.installDir/actions`（`T/lib/execution-sensitive-action.mjs:33-40`），`installDir` 由调用方 `--trust-root` 决定；同 operation_id 重放返回原 receipt 是 SC-AUTH-006 的正当行为，真正违规是复制根后换新 operation_id 重获额度。`D/execution_binding_endpoint.go`（约 `:129-146`）是 loopback TCP，把请求体 challenge（含自报 pid/root）原样交 signer。`M/server/internal/handler/daemon_terminal_claim.go`（约 `:31-43`）在 `runtime_id`、`dispatched_at` **两者都缺**时走无 fence 旧终态（只给一个会被拒）。`G/execution_consumption.go`（约 `:165-168`）判签发存在只比 grant+challenge；签发签名与重放（`G/execution_binding_issue.go` 约 `:251-255,:295-299,:325-342`）也不含 `dispatched_at`；读 claim（约 `:99`）不锁任务行，而 `BindCurrentTaskToCR` 是 task UPDATE→CR UPDATE、消费是 CR SHARE→（若加）task SHARE，直接加行锁会成环。B1/B2 这几处由 AIFI-45 处理，不属本方案。
- `T/crctl.mjs::emitOutboxEvent` 可发射失败而主操作成功；`D/crevents.go` 扫描本地 outbox/Git fallback；`G/crsync.go::OutboxEvent` 无 producer signature。relay auth、commit SHA、ACK/receipt 均不证明 T commit。
- `G/reconcile_github.go` 的 GitHub token 只认证读取；`gate_projection.go` 的 status/review 与 `reconcile.go::ApplySnapshot` 都必须纳入 strict fence。
- `D/daemon.go:848–852,8764–8766` 实际启用 delivery recorder；`execution_consumption_client.go` 的 production-off 注释已陈旧；delivery receipt 仍不等于 T consumption。
- `T/lib/durable-tx.mjs` 当前为 best-effort fsync/recoverable write-set；`execution-transaction.mjs` 的 Git adapter 不拥有 repair/action ledgers，不能直接升级为本方案提交证明。
- `G/execution_contract_manifest.go::LoadExecutionContractManifest` 仅双参数未配置才返回 nil；`cmd/server/main.go` 已有 manifest injection，不能称 production 永远 nil。现有四字段 manifest 保持不变。

### Options、信任根与选择条件
| 方案 | 结论 |
|---|---|
| A：signed verdict 经 crsync 运输 | 可做以后运输适配；仍需可信 producer、protected commit、独立验证及 fencing，现成 unsigned projection 不可用作 authority。 |
| B：可信 server-hosted Node 重执行同一 T engine | 可行，但需另做部署、隔离、repo capture、唯一 store owner 设计；不是 Go 重写规则。 |
| C：daemon control 服务持有隔离 T worker 与 attestation key | **仅 P0 通过后推荐选择**；复用 Node/daemon 边界，不复用普通 CLI stdout/F1 作为 signer 输入。 |
- 首期仅支持**经过实测的 Linux 独立受限服务身份与 agent 身份**。当前环境是否具备该边界为 **UNVERIFIED**；Windows 未验，不称支持。
- agent/repo writer 可控制 stdout、workspace、Git、annotations、任务参数及泄露的 F1 bearer；不得读取服务私钥/MDT、修改 worker/runtime/store、访问控制 IPC 或注入服务环境。
- server/DB、operator trust manifest、受保护 control 服务及 T runtime 为信任根；其被攻陷、root/DB-superuser、恶意 operator 不在保证内。
- P0 失败即停止 C 路径；记录失败证据。转 B 必须重新提出 server 部署方案并获审阅，**禁止运行时 silent fallback**。

### 无环 DAG 与归属
`计划审阅 + 隔离操作授权 → P0 → Channel S1 Foundation → S2–S6 channel core → S7 reader组件验收 → S8 部署就绪控制面`；`AIFI45剩余集成 + strict生产profile验收` 是下游，不阻塞 Channel 的独立组件验收。S8 在独立部署命名空间工作，不先要求业务 lineage 已消费或已可派发，避免自举循环。
| 归属 | 交付及依赖 |
|---|---|
| 已交付 AIFI-45 基线 | grant/verifier、F4、643–647/plumbing（迁移只核过 up；643–647 的 down 往返尚未执行，见 AIFI-45 待办 A）；实施前记录 commit、相关 worktree 原始 SHA256、tools runtime digest、迁移摘要，形成版本锁，不追随浮动分支。 |
| Channel S1 | 可信 contract-selection、不可执行 reservation、固定 candidate 映射、Tx root/fixed-ID enqueue/postcommit notification；真实 DB 正反验收，不等待 decider。 |
| Channel S2–S7 | keys/wire、protected store、owner recovery、T operations、ingest/settlement/start-binding、DB-only reader、projection fence；组件 composition 调真实实现。 |
| Channel S8（D7） | 可信完整部署观测、唯一 T readiness、签名结果、generation fence、启用/停新准入事务及精确恢复约束；组件 profile 可独立验收。 |
| AIFI-45 剩余 | 完整 AdmissionDecider、四阶段及 resume 单 effect Runner、RUN009 修复、业务 TC/E2E；提供 strict 生产 profile 必需的真实安装/接线证据，不反向阻塞 Channel 组件交付。 |

## Tech stack
- Go/pgx/PostgreSQL；Node ESM、既有 T 规则函数与 Node crypto/fs；Ed25519、SHA256，沿用 `{key_id,payload_b64,signature}` 与原始字节签名约定。
- Linux 预置身份及受审核 launcher/supervisor；不新增第三个决策服务，不自行创建用户、修改系统权限或部署。
- 新协议域只扩展固定 allowlist；`G/execution_authorization.go::ExecutionGrantDigest`、`T/lib/execution-binding.mjs::toolsRuntimeDigest` 等既有摘要定义保持不变。

## Spec
### 1. Foundation：可信选择、冷启动与固定候选
- 新增持久 `cr_execution_contract_selection`；来源仅为 operator-pinned scope policy 与 server-validated scope/真实 source attribution，创建时冻结。agent、Git、trigger 文本不能写 selection。
- `Selection=Legacy{selection_id,policy_ref}|Strict{selection_id,contract_digests,lineage_id,activation_event_id}|Unknown`；Unknown、缺记录、读失败均拒绝新增 effect，**不由 nil/缺字段推断 legacy**。
- **selection 不可降级（v0.4，B4/B12b）**：Strict selection 持久化后，若 trigger 评论的 `context.execution.contract` 或 tools `cr.md` 合同字段被删除、改空或改写，只能得到 `T_VERDICT_BINDING_MISMATCH`，不得改判 Legacy，也不得经 Unknown 落回 legacy。T 侧同理：合同选择写入 Spec §3 受保护 store，`cr.md` 字段只作展示投影，与 store 不一致即拒，字段缺失不等于 legacy。Legacy 只能由 Spec §5 的可信历史目录（legacy-origin-catalog）证明；缺行或读失败一律按 Unknown 拒绝新增 effect。从未建立 selection、且被目录证明为 legacy 的在途 CR，仍按 SC-EVD-006 保持原 gates。
- Strict 首次 selection 引用 Spec §7 的有效 activation；D8 下仅可信注册确认的新工作可建立新 lineage。Legacy/Strict 的既有 selection 不被升级、改名或删除后重建，不能迁移同一业务 origin 清零。
- strict 已持久选择但 reader/组件未装配→`T_VERDICT_UNAVAILABLE`；既有 nil legacy 路径保持原行为，不因此自动引入授权派发。
- `ResolveCandidateTx(ctx,tx,input) -> Candidate`：从 DB scope/source/run/node 与 compiled registry 得到真实映射；冻结服务端 proposed task UUID、executor、logical step/origin、subject/revisions。
- source task 是真实归属来源，可已完成，不充当 active generation proof；跨租户、无来源或无合法归属直接拒绝，不借无关 active task。
- `ExecutionTarget` 为 exact-key tagged union：`{"kind":"control","reservation_id":UUID,"owner_fence":N}` **或** `{"kind":"task","task_id":UUID,"runtime_id":UUID,"dispatched_at":timestamp,"daemon_id":UUID}`。
- 冷启动使用 control reservation；它不进入 `agent_task_queue`、不可 claim、不可执行代码，不伪造 runtime/null task；候选 task UUID 与 reservation 固定绑定。
- 原 active-claim SQL 不放宽；实际任务尚不存在不阻止 control worker 完成 T consumption。T permit 后才允许该候选真实 enqueue。
- proposed：`AdmitDispatchRootTx(ctx,tx,RootRequest) -> RootResult`、`EnqueuePipelineTaskTx(ctx,tx,fixedID,spec) -> Task,NotificationIntent`；不 commit、不通知。
- 既有 wrappers 保持行为；新 enqueue 继续单次 INSERT 从真实 source 复制归属，固定 ID 冲突须逐字段等同，不能盲目 `DO NOTHING` 当成功。
- root+task+settlement 同 Tx；commit 后发布 notification。通知丢失可重投同 task ID，不能重建 task；rollback 不发送通知。

### 2. Key-purpose 与 wire
- 独立 proposed `execution-control-trust-manifest/v1`：`schema,manifest_id,keys[],deployments[]`；绝对路径+原始 SHA256 pin，exact keys，禁止 agent enrollment。v0.3 的 deployment 绑定非空 required profile、成员/observer 身份及 trust revision，细节见 Spec §7；既有四字段 execution-contract manifest 不承载这些新字段。
- 每 key：`key_id,public_key,purpose,domains,scope,valid_from,valid_until`；scope 精确限制 workspace/project/CR、daemon/store 与适用 lineage；签发、验签两端均检查。
- **默认独立 command key**：purpose=`control-command`；不默认复用 human approval 权限。若将来复用，需独立审阅明确双用途，不在本期默认路径。
- attestation key purpose=`tool-attestation`，仅签 verdict/checkpoint；不得签 human grant/resume。human resume 继续既有 human-authorizer 权限，另域验签。
- 业务域为 `execution-control-command/v1\0`、`execution-verdict/v1\0`、`execution-control-checkpoint/v1\0`、`execution-repair-resume/v1\0`；digest=`SHA256(domain || 原始 payload bytes)`。
- **repair 追加授权（v0.4，B9）**：新增域 `execution-repair-extension/v1\0`，exact-key 字段 `schema,key_id,extension_id,lineage_id,grant_id,predecessor{record_id,digest,authorization_revision,accepted_limit},increment,reason_ref,issued_at`。只允许 human-authorizer purpose 签（与 resume 同权限、另域），command/attestation key 不得签。T 在 lineage 独占锁内做 CAS：`predecessor` 必须等于当前已接受的总额状态，接受后总额 = `accepted_limit + increment`，原消耗保留；同 `extension_id` 原字节重放返回原结果，同 ID 异内容拒绝；同一前驱的两份追加只接受先提交的一份。追加不是新 grant，现有 initial grant schema 的 `lineage_id == grant_id`（`T/lib/execution-authorization.mjs` 约 `:183-189`）不改。M 只验来源、绑定与顺序，不重算额度。
- D7 另用 `execution-policy-readiness-request/v1\0`、`execution-deployment-observation/v1\0`、`execution-policy-readiness/v1\0`；独立 exact-key schema，不加进业务 operation enum，不复用业务 B/lineage sequence。command/attestation key 仅在新增 purpose/domain/scope allowlist 后可分别签请求/就绪结果；部署观测使用独立 purpose=`deployment-observer` 的登记密钥，不能由 agent enrollment 取得。
- 各域均 exact-key schema；UTF-8、safe integer、canonical base64、拒绝重复键/未知字段；command/verdict 各限 256 KiB，大 evidence 只放固定摘要引用。
- command 字段：`schema,key_id,request_id,operation,nonce,expected_seq,previous_verdict_digest,B,fact_refs,operation_input`。
- `B`：`selection_id,workspace_id,project_id,cr_id,lineage_id,owner_fence,daemon_id,store_id,store_epoch,execution_target,candidate,subject,head,policy_digest,template_digest,tools_digest`。
- candidate：`reservation_id,intent,proposed_task_id,source_task_id,executor_agent_id,run_id,pipeline_id,node_id,node_run_id,attempt,logical_step,origin_ref`；subject 含既有 subject digest 及每 repo 固定 revision。
- head：`record_id,grant_id,digest,authorization_revision`；operation_input 为闭集分支，不适用字段不存在，专项完整绑定 `kind,target,environment,operation_id,action_scope_id`。
- verdict 字段：`schema,key_id,request_id,command_digest,sequence,previous_verdict_digest,B,operation,commit_ref,receipt_ref,disposition,code,replayed,after_state_digest,operation_result`。
- `commit_ref={store_id,store_epoch,sequence,tx_id}`；disposition=`permit|continue-exact|deny|stopped|pending`；诊断累计值不得成为 M 的规则输入。
- operation=`execution-consume|repair-admit|repair-outcome|repair-assess|repair-resume|sensitive-consume|evidence-delivery`；operation 成功不自动授权任意 enqueue。

### 3. Protected commit、签名与网络边界
- worker 只接收已验 server command，使用固定绝对 executable/runtime、净化环境、私有 ledger root；禁止任务提供 argv/root、`NODE_OPTIONS`、Git hooks 或动态模块注入。
- 复用 T repair/action/evidence 函数，注入 `LedgerStore` 与可信 facts；普通 CLI 保持原模式，trusted 路径不签 CLI 输出、不扫描 workspace JSON 判断提交。
- reviewer identity/allowed reviewers 从 server 持久 task assignment 与认证结构化提交取得；subject/test capture 绑定实际 attempt、固定 revision、命令及 artifact digest，不从 repo `by`/stdout 自报。
- 测试/被审代码只能在 agent 受限执行域运行；control worker 不以持 key 身份执行 repo 脚本。评审意见是可归属声明，不保证判断正确或测试充分。
- T 每 lineage 持独占锁；先查 request-result index，再调用唯一规则；同 request/different command digest 拒绝。
- strict durable primitive 对 fsync/rename/目录 fsync 的错误必须失败；一个 bundle 原子发布业务 after-image、request-result index、完整 verdict envelope 与 durable outbox，journal 含 prepare/redo 信息。
- **首次 protected commit 冻结完整 payload、key_id、sequence、prev digest、业务 `replayed` 及签名 bytes**。签名可在内存准备，但仅 commit 成功后可从私有 committed frame 对外发布。
- 重投读取原 envelope，不重新调用规则、不重包装累计诊断、不改变 signed `replayed`；transport delivery count 只存非授权元数据。
- M 不读取 T 文件；worker frame 只能来自登记进程及私有 IPC，不存在通用 `sign(payload)` endpoint，F1 无新增权力。
- **repair-admit 只认验签（v0.4，B5）**：trusted 路径下 repair admit 的 `repair_limit/grant_id/supersedes_grant`，只取自 `readExecutionGrant`/`verifyExecutionEnvelope` 完整验签后的 payload，并作为 command `fact_refs` 绑定；未验签的 `payload_b64` 解码路径不进入 trusted 路径，也不能作为额度来源。静态验签不代表当前有效：当前 head 与撤销在 M settlement 判定（见下条）。
- **sensitive 账本（v0.4，B6；整体归本方案）**：exact action 账本属于本节受保护 store。**额度聚合键**为 `(workspace_id,cr_id,lineage_id,kind,target,environment)`，**幂等键**为 `(额度聚合键,operation_id,action_scope_id)`；grant 只是授权引用，不是新的额度桶，续签不能分桶重获额度。`--trust-root` 只用于定位验签公钥，不决定账本位置。**旧账本连续性**：启用前把既有 `grant.installDir/actions` 记录验证后一次性导入，并冻结来源摘要；来源无法核实的，拒绝该聚合键的新增消费，不得因换位置归零。**授权效力在 M 的 settlement 事务里线性化**：M 在同一 Tx 重验当前 head/撤销，撤销先提交则结算为 no_effect；T commit 只是消费记录，不等于动作获准；外部动作只能在 M settlement permit 之后执行。普通 CLI 不得为 Strict 另发离线 receipt。
- **merge 范围核对（v0.5 修订版，B11）**：Strict CR 的 `crctl merge` 在进入 `mergeCr`（`lib/workspace-transactions.mjs`）的 prepare 之前强制执行 SC-AUTH-004 范围核对；越界或无法核实一律 fail-closed。
  - **第二轮修订（strong 复核 BLOCK 后）——核对对象必须等于实际发布对象**：`mergeCr` 的首次发布 preflight 冻结的是**远端 requirement ref == 工作区 HEAD**，不是批准 SHA；KB 允许批准 SHA 是 HEAD 的祖先并允许其后 approval/`cr.md`/review 变化，代码仓本地信任允许 HEAD 与批准 SHA 不同但 tree 相等。因此“工作区不是将发布的内容”推不出“批准 SHA 完整代表将发布的内容”。
  - **R1 已决（2026-10-26，用户选择 (a)）——核对对象 = merge 实际发布的候选写集**。原 (b)（只核对批准 SHA、禁止 tree 相等放行与 KB 审批后写入）**不采纳**：它与现行“KB 允许批准 SHA 为祖先”的行为正面冲突，会拒绝大量已批准 CR。采用 (a) 后必须同时满足五条，缺一不可：
    1. **核对区间** = 该仓实际将发布的 source 区间 `trunk...<candidate source SHA>`（下文“核对集合 = 发布集合”已按 `trunk...HEAD` 写；二者在首发时是同一对象，恢复/rebuild 时必须重算而不是沿用旧值）。
    2. **批准后的实际 source HEAD 必须有独立冻结记录**：批准事实（per-repo approved source sha）来自 M；**实际候选 HEAD 由本地在预检时确定并写入 merge journal/receipt**，作为“到底发布了什么”的持久事实。二者的关系是“批准是该范围内已存在且未撤销的下界”，不是“批准 SHA 等于发布 sha”。journal 是本地审计记录，**不得**反过来被当成授权凭据。
    3. **KB 审批后写入**（`approval.yml`、`cr.md`、review 记录等）**属核对范围**——这正是 X7 要守的“先改文档事后追认”面，不得排除。
    4. **finalize 生成写集必须显式在 `allowed_paths`**：`cr.md`、`merge-commits.yml`、`merge-verification.md` 三个路径逐项列出（按仓/根定位），**漏列即 `AUTH_SCOPE_PATH_NOT_ALLOWED`**，不得以“系统生成”为由暗设豁免。finalize 会重建并再次发布，故与 merge 同等纳入。
    5. **rename 源/目标、symlink、删除** 全部按“选定提交树/blob”判定，不是工作树 realpath、也不是 index mode（AIFI-45 侧已按增量 33/34 对自检做同等加固）。
  - **恢复与 rebuild 的输入**：journal 恢复沿用原 journal 冻结的 `sourceSha`；rebuild 可能更换 base。规定：恢复必须复用**原冻结输入**，输入变化即拒，不得用新批准对象给旧发布源背书。
  - **插入点（strong 复核修正）**：不是“现有 gate 里加一个检查类型”。现有 `runGateChecks` 的 `approval` 分支在 evidence drift 时会 `emitDriftAudit` → 写 `.crctl/outbox`，**不是零副作用**；`mergeCr` 内的 `acquireLock`（写 `owner.json`）、journal 创建与 `recoverWriteSet` 也早于它读取 release subjects。因此改为：`cmdMerge` 在只读定位/状态确认之后、现有 `runGateChecks` **之前**，执行**独立、必执行**的只读范围预检（不随 gate 声明开关变化），拒绝时不进入 `mergeCr`。
  - **首次拒绝 vs 并发失败**：预检首次拒绝 = 零新增写入；预检通过后发生并发变化（head 前移/撤销/ref 漂移）= 停止后续 effect，但**不得声称此前连锁文件都没写过**（锁、journal、outbox 可能已产生）。不得为追求零写入取消事务互斥。
  - **授权效力线性化边界**：单次 merge 含 prepare → 逐仓 publish → rebuild 多段，开始时查到当前 head 不保证发布时仍有效。规定：预检冻结 `{selection, head/revision, repo identity, approved source sha set, base sha}`；publish 前在锁内重验同一冻结输入；撤销/head 前移发生在**部分发布之后** → 停止后续 publish、**保留原 journal/receipt**、转人工处理；不得自动新建事务或换源解除阻断，也不得把后续新授权解释为对已越权历史写入的追认。
  - **空集合不得放行（strong 复核修正）**：`evaluateChangeScope` 对缺失/非数组 `changes` 当空数组并返回 allowed——它是判定器，不是采集完整性验证器。适配层必须证明四件事，缺一即 `AUTH_SCOPE_UNVERIFIABLE`：仓集合完整（**不得仅因当前 graph 删项而缩小**）、每仓取到目标 SHA、采集成功、路径集合非空或有显式“零改动”证明。
  - **SHA 采集适配细节**：rename 的源路径与目标路径都查；symlink 从**选定 tree/blob** 的 mode `120000` 与树内目标核验，不读工作树；路径用无损分隔与引号解转义，不用换行拆分 + `trim()`；对象缺失/采集失败不得退化为空集合。
  - **Legacy 口径收窄**：“legacy merge 行为不变”仅指**可信历史目录证明的 legacy**；Unknown selection、目录读失败、Strict 删除投影三类入口各有正反例（与 Spec §1 一致，这里显式挂到 merge）。
  - **X7 合法恢复流程（strong 复核补）**：① 新 Strict 签发前校验必要的 KB 仓、CR 路径与共享账本路径已获授权，不满足则拒绝进入会产生这些写入的流程；② 已持久 Strict 且漏列 KB 的 CR 保持阻断，不降 Legacy、不加隐藏豁免；③ 由有权签发方签发满足范围的当前授权，保留原 origin/lineage/消费历史，重跑受授权摘要变化影响的测试/证据/审批后再核对 merge；④ 部分发布后的处置见上一段（保留原 journal/receipt）。
  - **归属划分（strong 复核补）**：可信 selection、current-head facts、受保护 merge 绑定与恢复契约归本方案；而自检采集器的通用缺陷（路径编码、rename 处理、symlink 核验来源）**在 AIFI-45 就地修**，修好后两条输入路径共用，不在本方案重写。
  - **零写入的精确外延**：不建 merge journal、不 publish、不推进 CR 状态、不写 receipt/effect mapping。既有 `cmdMerge` 前置链（`freezeTerminalActor`/`loadGates`/`runGateChecks`/`resolveCrState`）产生的 audit 与 gate 结果**不在**本承诺内，如实写明而非声称“零写入”。
  - **① 是否受约束**：读 Spec §1 持久 selection；`cr.md` 合同字段只作投影，删字段不改判。selection/grant 查询所用的 workspace/CR **由 M 解析**，CLI 的 `--workspace` 与 `dir-graph.yaml` 只定位本地仓、不决定查询目标。
  - **② 授权范围与仓库身份**：读 M 当前 head 对应的已验签 grant，经 `ResolveFactsTx` 得到 typed facts（`allowed_repositories`/`allowed_paths`/`repository_bindings`）。不扫描 `grants/` 目录挑“最新”，merge 不提供 `--grant` 参数；撤销或 head 已前移即拒；每仓除比对冻结身份外，还须有当前平台绑定确认（wire-contract §2.1/§3；裸 CLI 做不到，需 §6 只读端点提供）。
  - **③ 改动集合（本次修订核心）**：权威来源是 **M 侧持久 code 批准记录中冻结的 source sha**，`approval.yml#code.release-subjects` 只作投影；读取后须与 M 记录逐字段相等，不等即拒（`approval.yml` 位于 agent 可写的控制根，单独作为权威来源与 Goal 矛盾）。
  - **核对集合 = 发布集合**：核对区间为 `trunk...HEAD`（merge 实际发布的提交），而不是 `trunk...<release subject sha>`。后者会把 release subject 之后的提交（含 `approval.yml` 自身与 KB 文档）整段漏检——那正是 X7 要守的「先改文档事后追认」面。release subject sha 仅作为“该批准必须已存在且未被撤销”的下界参考。
  - **与既有 `verifyReleaseSubjects` 的关系**：merge 侧既有 release-subjects 校验（`allowLocalDrift: codeTrust.ok`）**先于**范围核对执行且必须通过；本地信任下的正文漂移不得放宽到范围核对。越界时拒（不转 `release-drift` 回退：回退会把状态写回 `developing`，属于写入）。
  - **失败码闭集**（每条各配 leaf）：`AUTH_SCOPE_VIOLATION`（越界）、`AUTH_SCOPE_UNVERIFIABLE`（收集/定位失败、release-subjects 缺失、`approval.yml` 与 M 记录不等）、`EXECUTION_AUTHORIZATION_REVOKED`（撤销）、`EXECUTION_AUTHORIZATION_HEAD_MOVED`（head 前移）、`EXECUTION_AUTHORIZATION_UNAVAILABLE`（端点不可达/超时/5xx/认证被拒）。**各码的判定条件与优先级以 v0.6 节 R2.4 表为唯一权威**（可达但 facts 缺失/不全/未知归 `AUTH_SCOPE_UNVERIFIABLE`，已知越界永远 `AUTH_SCOPE_VIOLATION`）。退出码统一非零，状态保持 `code-approved` 不变。
  - **symlink 逃逸**：tree-based 收集下 `escaped` 取自 git tree entry mode `120000` 并在树内解析目标；无法判定时记 problem（→ UNVERIFIABLE），不放行。
  - **复用边界（写实）**：复用 `evaluateChangeScope`（纯判定，不触 git/fs）与 `AUTH_SCOPE_*` 封闭码；**新写** `collectCommittedPaths(base, sha)`（committed 区间 + tree mode 逃逸判定），不复用 `collectChangedPaths`（它含工作区/untracked 与 `origin/trunk` 回退，语义不同）。AIFI-45 自检走工作区、merge 走已提交区间，这一差异是有意的，不是同一实现的两种用法。
  - **Legacy**（由可信历史目录证明）merge 行为不变（SC-EVD-006）：不核对范围、不要求 grant。
  - **重试**：head 前移或撤销后重试 merge 须重新核对，不复用旧结论；不按“批准时快照”比对（与重试要求互斥的旧表述已删）。
  - **X7 已决（2026-10-26，不设豁免）**：控制根里的 CR 账本与文档改动不列入豁免。签发侧须**同时**写 `allowed_repositories`（repo id）与 `allowed_paths[repo]`（该仓的路径前缀）——只列 repo 不列前缀，控制根每次文档改动都会 `AUTH_SCOPE_PATH_NOT_ALLOWED`。仓库集合**不得**经 Spec §2 的 repair 追加域扩展（追加只扩额度）；遗漏时只能重签 grant，无豁免、无例外路径。
- 网络在 DB Tx 外；T 与 M 无分布式事务。T commit 后 M rollback→重发原 bytes；M effect commit 后响应丢失→只返回既有 effect mapping；T 已消费不退款。

### 4. Schema、状态机与 effect 线性化
- 当前最大 migration 为 **647**；proposed `M/server/migrations/648_cr_execution_control.up.sql`，含下表及约束。实施时 648 若占用，先更新规范及全部命令，不覆盖。
| 表名后缀（均以 `cr_execution_` 开头） | 关键字段及约束 |
|---|---|
| `contract_selection` | `id,workspace_id,project_id,cr_id,lineage_id,mode,policy_ref,contract_digests,source_ref,origin_id,fresh_work_ref,created_at`；scope/lineage unique；同 workspace/project/origin 仅一归属，immutable，不因换 CR 重新起算。 |
| `control_reservation` | `id,selection_id,scope,lineage_id,candidate_bytes,candidate_digest,created_at`；fixed proposed task unique，immutable；无 task/runtime 占位行。 |
| `control_command` | `request_id,scope,lineage_id,reservation_id,owner_fence,effective_fence,seq,prev_digest,command_bytes,envelope,state,verdict_id,admission_event_ref,admission_seq,issued_at`；issued 时冻结准入边界，签名字段 immutable，状态受限转换；每 lineage 最多一个 open。 |
| `tool_verdict` | `id,scope,lineage_id,request_id,store_id,epoch,seq,prev_digest,payload_bytes,envelope,digest,commit_ref,receipt_ref`；request unique、store/epoch/seq unique；拒绝 UPDATE/DELETE/TRUNCATE。 |
| `tool_cursor` | `scope,lineage_id,store_id,epoch,last_seq,last_digest,owner_fence,owner_id,open_request_id,frozen_reason,reconcile_proof`；行锁+CAS；无预算累计器。 |
| `control_settlement` | `request_id,verdict_id,kind,effect_kind,effect_ref,fixed_candidate_digest,head_ref,reason,settled_at`；request unique、immutable；kind=`effect|no_effect`。 |
| `task_binding` | `reservation_id,command_id,verdict_id,task_id,runtime_id,dispatched_at,daemon_id,binding_digest,launch_id,launch_lease_ref,install_snapshot_ref,launch_permit_bytes`；实际 generation unique、immutable；只绑定原候选及固定加载快照。 |
| `control_fact` | `id,scope,kind,origin_id,source_authority,source_record_id,registry_revision,actor_assignment_ref,attempt_ref,subject_ref,capture_ref,payload_bytes,digest,created_at`；认证来源+immutable；kind 决定 provenance tagged union，FreshWork 不伪造 task/attempt。origin-registration 对 scope/origin 及 scope/source_authority/source_record_id 分别 partial unique；command 固定 refs。 |
| `deployment_head` | `scope,generation,snapshot_digest,state,registry_revision,legacy_catalog_ref,legacy_gate,legacy_work_revision`；scope unique，generation/registry/work revision 单调，legacy_gate=`OPEN|DRAINING|RETIRED`；禁止删行归零；缺失拒绝启用/退役。 |
| `deployment_snapshot` | `scope,generation,profile_digest,inventory,facts_bytes,evidence_refs,digest`；scope/generation unique、immutable，完整实例/安装集合。 |
| `policy_readiness` | `request_id,scope,target,nonce,generation,expiry,command_bytes,observation_frames,verdict_bytes,digest`；nonce/request unique，request 冻结后每 slot 仅可 CAS 登记一份原观测（同 bytes 重投幂等、异内容拒绝），最终 signed result 原字节不可改。 |
| `policy_activation_head` | `scope,target_policy,revision,event_id,last_issued_admission_seq`；scope/target unique，启用及 issued/停新单共享 CAS/锁点；序号只做因果边界，不计预算。 |
| `policy_activation_event` | `id,scope,target_policy,previous_id,mode,generation,verdict_ref,actor,reason,cutoff_admission_seq,committed_at`；append-only，mode=`ACTIVE|STOP_NEW`；停新单固化已 issued 边界。 |
| `code_source_freeze` | `workspace_id,cr_id,repo_id,approved_source_sha,approved_revision,approval_record_id,authorization_head_id,approved_at,superseded_at,revoked_at,digest`；`UNIQUE(workspace_id,cr_id,repo_id,approved_revision)` + 部分唯一 `UNIQUE(workspace_id,cr_id,repo_id) WHERE superseded_at IS NULL`（每仓至多一条当前行）；只由 code 批准事务追加写，撤销置 `revoked_at`，历史行不改写（v0.6.1 R2.1） |
- 合计 **14 张新表**（原业务通道 8 + D7 5 + v0.6.1 merge facts 1：`code_source_freeze`），均在本 change 的同一 proposed migration 中，up/down/索引/immutable 测试按此清单核对，不另开 Foundation change。
- 无新 FK/cascade；软引用逐次验证。workspace deletion 分类：audit/selection/settlement/binding/fact 保留，command/cursor 禁新建并收敛；unknown open 不强行清空。
- command：`created → issued → result_ready → settled_effect|settled_no_effect`；结果未知进入 `uncertain`，lineage freeze。ingest ACK 只确认持久化，**不释放 slot**。
- `BeginOwnerTx` 持久递增 fence；`EnsureRequestTx` 锁 cursor，固定 candidate 与序号；禁止并行第二 command 或自动换 request。
- v0.3 固定锁序：deployment head→policy activation head→CR→referenced head→scope/source/run/node等业务行→cursor/command→dispatch root/task。启用、停新准入、部署变更及所有新增 effect 按此顺序；单纯 revoke 保持既有 CR 锁路径且不反向获取 deployment 锁，不等待 command slot。Tx 内不调用网络。
- effect 线性化点为 caller Tx commit：同 Tx 重验 current signed head、selection、cursor/fence、原 candidate、root，写 root/task/effect mapping/settlement 并释放 slot。
- revoke 使用既有 CR 锁路径，**不等待 command slot**。revoke 先提交→旧 permit 只能 no_effect；effect 先提交→后续 revoke 不追溯撤销该已提交事实。
- stop 按 T sequence 生效；前一 effect 已 settlement 才能发后续 stop command，不追溯撤销旧 effect；即时撤权使用 revoke，不伪称 stop 可越序。
- 已提交 pending/deny/stopped verdict 明确 `no_effect` settlement；permit 过时/撤销也 no_effect，保留消费。只有从未 issued 的 created command 可直接取消。
- issued/timeout 无结果不能推断未消费、不能释放 slot；恢复原 request 或 freeze。settled replay 只读原 effect；未 settled 只允许原 candidate，不借 receipt 换动作。

### 5. Restart、迁移与恢复
- restart 接业务 command 前先取得 M 新 fence，隔离旧 worker；worker 持久接受新 fence 后才返回 signed checkpoint；旧 fence 不再执行新操作。
- checkpoint 字段：`schema,key_id,scope,lineage_id,store_id,epoch,accepted_fence,last_seq,last_digest,after_state_digest,journal_state,open_request_id,open_command_digest,result_digest`。
- M reconcile DB cursor、T checkpoint、journal、open command，并保存 proof；旧 command bytes 不改，验证恢复后仅更新非签名 `effective_fence`，允许完成原 request。
| 观察 | 固定恢复动作 |
|---|---|
| T/M tail 相同、after-image 完整、open journal 相符 | 对齐新 fence；恢复原 request；无 open 才可接下一单。 |
| T 恰领先一项且匹配唯一 open command/链 | 导入原 verdict bytes，再按正常 current-head 检查 settlement；不新消费。 |
| M 已 settled、T outbox 未见 settlement | 返回原 mapping；重发确认，不重做 effect。 |
| journal prepared 且旧 published bundle 完整 | 在新 fence 下重放原 command，原子完成；commit 后才发结果。 |
| store/checkpoint 缺失、T 落后、分叉、多项超前、after-image 损坏、issued 无对应 journal | freeze；不猜“未消费”，不清 slot、不建空 store。 |
- 普通 restart 不变 store epoch/sequence；key rotation 只影响新 verdict，保留旧 key 验证历史，不重签历史。
- **D8=A（用户已决定）**：本期不做 legacy 业务合同/历史迁移，不自动或显式导入旧 workspace ledger，不新增迁移动词；既有 run 沿原合同与原安全恢复路径运行。只为权威注册证明无承接历史债务的新工作建立新 CR/新 lineage；旧审批/额度/消耗/未决任务不改、不重新起算。
- 同一 CR、logical origin 或已知历史债务不能以新 grant、新 lineage、删 selection、换 store/epoch 伪装成新工作。历史归属不明或有未决命令即拒绝新准入并冻结相关 lineage，不能把“无法核实”当“没有历史”。82 条审批等数量本身不证明是否需要或允许迁移。
- 普通 restart、key rotation、原 command/receipt 的精确恢复不是业务历史迁移，仍按本节恢复表执行；灾难恢复只能使用可核实的同一 lineage/store 连续性与原始 bytes，不清余额/slot/root。跨 store 搬迁或 epoch 变更的连续性迁移不在本期实施，若以后需要须另经 SPEC/审阅，禁止运行时 fallback 到空 store。
- **FreshWork 权威注册契约（proposed）**：`RegisterFreshWorkTx(scope,sourceRef)->FreshWorkRef|EXISTING|UNKNOWN` 只接受 operator-pinned intake authority 的不可改 source record，不接受 agent 任意 UUID/CR 名作为 origin。intake authority 负责把重开/拆分/别名映射到同一稳定 `origin_id`；系统不声称能从自由文本推断业务等价，恶意受信任 intake/operator 不在保证内。
- 首次切入前，受保护登记员以 `control_fact(kind=legacy-origin-catalog)` 保存所管 workspace/project 的历史 CR/授权/消耗/未决任务、来源别名及未知项的完整索引，`deployment_head.legacy_catalog_ref` 固定其覆盖证明；源不可读/缺失/索引不完整的 scope 只能 UNKNOWN，不能按“数据库没查到”签无历史证明。原 HOLD 库的缺失历史也不能借此当不存在。
- 每次注册在 deployment 锁内校验来源、既有 origin/alias、legacy 索引与当前未决集；唯一 `control_fact(kind=origin-registration)` 固定 `{origin_id,source_authority,source_record_id,cr_id,actor_ref}`，首次登记/来源映射更新才递增 registry_revision。另追加 `control_fact(kind=fresh-work-proof)` 固定 `{registration_ref,legacy_catalog_ref,registry_revision,classification,unresolved_refs,actor_ref}`，classification 仅 `NEW|EXISTING|UNKNOWN`；只有 NEW 且 unresolved_refs 为空可供首次 selection。proof 由 DB 认证，不从 CLI/仓库签入。
- selection/reservation 同 Tx 在相同外层锁内回读 proof、登记身份及当前 registry revision、关联同一 source/origin/CR，并写唯一归属；同 origin 跨 CR 并发靠 registration 的 partial unique + selection 的 origin unique 拒绝第二次额度。revision 漂移须重新核实并追加新 proof，不修改历史 proof，也不重复创建 identity；UNKNOWN 有新可信证据时可重新核实，不能永久吞掉合法更新。旧 CR/来源别名不能另取 origin，覆盖未知一律拒绝，不通过新 source task 逃逸。
- **EVD-008 的范围与验收分开**：既有 `evaluateExplicitMigration` 正/反分支和 SC-EVD-008 原文不被本计划删除或改成“永久拒绝”；D8 解决本期 rollout 范围，不自动完成 AIFI-45 的生产迁移能力。如要调整其原交付承诺，须另行修订规格/追踪并审阅；当前保留 CP 单测口径与“无生产入口”标记，不增加 PRESENT 或解除 Gate。

### 6. API、task-start 与 reader
- proposed `GET /api/daemon/execution-control/commands`、`POST /api/daemon/crs/{crID}/execution-verdicts`、`POST /api/daemon/execution-control/checkpoints`，以及 v0.6.1 新增 `GET /api/daemon/execution-control/merge-facts/{crID}`（R2.2）与 `POST /api/daemon/crs/{crID}/merge-effects`（`op=reserve|report`，R3.1）；仅 MDT+enrolled key/owner scope，拒绝 PAT/JWT/task-token fallback。
- `merge-facts` 为只读 GET：200 / `400 MERGE_FACTS_INVALID` / `403 MERGE_FACTS_UNTRUSTED` / `404 MERGE_FACTS_NOT_FOUND` / `503 MERGE_FACTS_UNAVAILABLE`，未知 code 按不可用处理；到 CLI 外层码的映射见 R2.4。`merge-effects` 沿用下行 POST 规则，closed codes `MERGE_EFFECT_{INVALID,NOT_FOUND,UNTRUSTED,REVOKED,HEAD_MOVED,INPUT_MISMATCH,CONFLICT,UNAVAILABLE}`，码序见 R3.1；PAT/JWT/task-token 对两端点一律 `403 …_UNTRUSTED`。
- POST 首次有效入账 201、exact replay 200、冲突 409；invalid 400、untrusted 403、unavailable 503。未知字段/域/绑定/序号不产生授权事实或 effect。
- closed codes：`T_VERDICT_{UNTRUSTED,INVALID,BINDING_MISMATCH,CONFLICT,SEQUENCE_GAP,STALE,STORE_UNAVAILABLE,FENCED,RECOVERY_REQUIRED,UNAVAILABLE}`；按固定枚举映射，未知 code 拒绝。
- 保留 `WAIT_CONSUMPTION/WAIT_EVIDENCE/DENY_STOPPED/DENY_RESUME/DENY_SPECIAL_AUTHORIZATION`；quota deny 只消费 T 裁决，不读取 consumed/limit 推理。
- 真实 code task **已交付、启动前**按真实 task/runtime/dispatched_at/daemon generation 验证 643 binding issue、644 consumption、645 activation，并逐字段核 issuance envelope/head/challenge。
- generation binding 只将已提交 reservation consumption 绑定到原真实 task，不二次消费；失败/未完成之前不启动 agent。后续 control operation 使用真实 task 分支，旧 active-claim 语义不变。
- proposed `CommittedTReader.ReadCommitted(ctx,tx,ReadKey) -> CommittedDecision,error`；ReadKey 含 selection/reservation/request/完整 candidate，内部仅读 verified DB facts，不调用 Node、网络或文件。
- proposed `SettleCandidateTx(ctx,tx,key,verdictID) -> EffectRef,NotificationIntent,error`；复用 Foundation primitives，重复 settled 仅返回原 mapping，未 settled 不接受替换候选。
- projection fence 属于 **Channel**：覆盖 `gate_projection.go`、`crsync.go`、`reconcile.go::ApplySnapshot` 及 strict task preflight；unsigned status/review/snapshot 只能更新诊断区，不写 strict Runner 权威状态或 facts。
- strict fence 按持久 selection 查询；Unknown/查询失败不能 legacy 降级。AIFI-45 后续仍负责其所有 Runner mutation/queue/resume 入口汇入单 effect。
- **终态 fence 最终规则（v0.4，B3）**：是否必须带 claim，由服务端持久、单调的事实决定：`fence_required(task) = 该 task 任一 generation 已有 644 消费行 ∨ 该 task 创建于 Strict selection 之下`。该事实只增不减，任务重领（换 generation）不清除；本方案装配后与 AIFI-45 过渡规则**取并集**，不是替换，legacy 已消费任务装配后仍须带 claim。判定在终态事务内、持任务行锁后进行，并校验真实 generation；读失败即拒。只有两个字段都缺**且** `fence_required=false` 才允许旧终态路径。终态上报属于原运行的安全收尾：STOP_NEW 或授权过期不阻止它，也不让它跳过 generation fence。该写路纳入本节 projection fence 清单。
- signed resume 绑定 `grant_id,lineage,origin,stop_ref,subject,head/revision,expected_epoch,evidence_refs`；human 权限复用现有校验，T 验签后调用唯一 resume 规则；只一次 epoch、不清预算、不复活 revoked/terminal root。

### 7. D7 独立解决方案：部署就绪控制面（EVD-007 / RUN-008 共享依赖）

#### 7.1 归属与检查对象
- **T 决定 ready，M 决定是否原子启用**：T 复用并加固 `T/lib/component-readiness.mjs::evaluateComponentReadiness`；M 只做身份、绑定、不可变性、当前 generation/有效期/CAS 的效力检查，不重写版本匹配、组件集合或恢复能力规则。不新增第三个 change/服务。
- 对象是 `scope × target_policy × deployment_generation`，不是某个 lineage 的预算操作。接口（均 proposed）：`RequestReadiness(scope,target,action)->RequestRef`、`Worker.EvaluateReadiness(requestID)->FrozenEnvelope`、`RecordReadinessTx(envelope)->ReadinessRef`、`ActivatePolicyTx(scope,target,requestID,expectedGeneration)->ActivationRef`、`StopNewAdmissionsTx(scope,target,reason)->ActivationRef`。
- action 闭集为 `verify-channel|enable-policy|retire-legacy-relay`；profile purpose 为 `channel-component|strict-production`。二者及目标 policy/profile 摘要均入签名，`verify-channel` 的结果只能记 `READY_COMPONENT`，不得调用生产 activation，也不得当作 business permit。
- 现状：纯比较函数可复用，但空声明/空观测可返回 ready、缺配置可折叠为空、重复 observed 可覆盖；当前无生产调用点。四个 marker 的摘要、环境变量观测及已加载 contract manifest 都不是上线证明；`AdmissionDecider` 尚未装配，不能称已可启用 strict。

#### 7.2 可信 expected/observed，与全部副本的闭包
- **Expected**：operator 在受保护新 trust manifest 中批准并 pin 非空 required profile，冻结 policy/template、组件 ID、版本语义、摘要算法/值、安装目标和恢复能力。仓库 `workspace.components` 仅是候选声明，须与此 profile 完整绑定；缺失、为空、损坏或删必需项均不得产生可信 READY。
- **Observed**：受保护 supervisor/installer 绑定已登记实例与实际进程/安装根，测量真实 executable/runtime、生成 registry、实际安装 Agent/Skill、boot/install generation、加载配置及已批准恢复探针证据。observer 对 nonce/generation/实例事实签名；worker 校验登记身份后自行读取固定 facts，不能由 M 直接传入 `ready:true` 盖章。
- agent 可写的安装根、repo JSON、Git SHA、stdout、`MULTICA_COMPONENT_*`、普通同 UID 文件和仅声明“支持恢复”均不是真实观测。观测控制者必须控制实际加载/切换与实例接单资格；无法证明就 NOT_READY，不以代码自报版本替代。
- tools 在受保护实际 runtime 根复用既有 `toolsRuntimeDigest` 定义，marker digest 仅用于原身份诊断，不能混作全量 runtime digest。对其他产物冻结各自版本/摘要语义；`not-applicable` 只允许 profile 明确批准的项目，不能使 Runner 等跳过版本检查。
- inventory 包含**所有仍有资格处理该 scope 的 server/daemon/worker、入口/恢复实现和安装目标**，不是随便一台或仅当前在线实例。离线旧实例须核实或先撤销接单/写入资格；多实例按稳定 ID 分别比较，不能覆盖、平均或取最新一条。
- 新副本、重启、滚动更新、安装/配置/路由/信任根变化，均须先在 deployment 锁内递增 generation、使旧 verdict 不适用，再由受保护 supervisor 切换并登记新观测；未登记实例无权服务 strict。旧二进制可绕过 fence 时必须先 fence/隔离其写入与路由资格，不能只让新版本自查。
- 严格 profile 校验与版本/能力求值全部加在 T：拒绝空/非法配置、必需项遗漏、重复声明或观测、unknown、版本/摘要缺失或不匹配、安装/恢复能力无证明。旧诊断兼容可保留，但宽松结果不可签发 deployment verdict。

#### 7.3 请求、签名、持久化与启用
- D7 不占业务 command slot、不推进业务 sequence、不消费或退款预算；复用受保护 worker、密钥边界和严格持久原语，但使用独立部署命名空间/request-result index。无需先创建业务 lineage/任务才能判自身就绪。
- 以下是 D7 的**完整字段闭集**（不是“至少含”）：request=`{schema,request_id,nonce,scope,deployment_id,action,profile_purpose,target_policy_digest,template_digest,profile_digest,deployment_generation,inventory_digest,observation_slots,trust_revision,issued_at,expires_at,context}`；observation=`{schema,key_id,observation_id,request_id,command_digest,nonce,scope,deployment_id,profile_digest,deployment_generation,inventory_digest,trust_revision,instance_id,role,boot_id,install_generation,measurements,recovery_evidence_refs,issued_at,expires_at}`；verdict=`{schema,key_id,request_id,command_digest,nonce,scope,deployment_id,action,profile_purpose,target_policy_digest,template_digest,profile_digest,deployment_generation,inventory_digest,observation_refs,facts_digest,evidence_refs,trust_revision,issued_at,expires_at,ready,code,findings,context,commit_ref}`。
- **无环构造顺序**：①先按受保护 inventory 预分配 observation_slots=`[{id,instance_id,role}]`（不含观测内容 digest），冻结原 request/command_digest；②每个登记 observer 对对应 observation_id 签原 request digest，M/worker 校验该 slot 的 instance/role/nonce/generation，只可登记一份不可变原 payload；③全部 slot 完整后，最终 verdict 才冻结 observation_refs=`[{id,digest}]` 与 facts_digest。slot/ref 一一对应、顺序与 request 相同；缺项/换槽/重复/异摘要均拒绝。inventory_digest/snapshot_bytes 只含此前冻结的 profile/成员与安装登记事实，不含本轮 request/观测/verdict 的待生成摘要；预存恢复证据也不引用本轮 verdict，禁止摘要依赖环。
- 共同类型闭集：scope=`{workspace_id,project_id}`；各 ID 为 UUID，nonce 为 32 随机 bytes 的 canonical base64，所有 digest 为 64 小写 hex；generation/revision/UTC seconds 为 safe non-negative integer。role=`server|daemon|worker|installation`；measurement=`{component_id,version,digest_kind,digest,install_root_ref,capabilities,evidence_refs}`，version 为非空字符串（仅 profile 允许的 tools 使用 `not-applicable`），digest_kind=`existing-tools-runtime|sha256`，install_root_ref 为受保护登记 ID，不是 caller path；capabilities 为去重非空字符串数组；ref=`{id,digest}`；finding=`{code,component_id,detail}`，component_id 可为 null，code 沿唯一 T finding allowlist。任何嵌套对象均拒绝未知/缺字段，数组 ID 不重复；不适用不省略，必须由 schema 的明确 union 分支表示。
- context 是 exact-key union：verify-channel=`{kind:"component"}`；enable-policy=`{kind:"activation"}`；retire-legacy-relay=`{kind:"retirement",drain_ref,legacy_work_revision,workset_digest}`；证据中 echo 原 request context，observation 通过 command_digest 绑定它。commit_ref 沿 Spec §2 形状，但属于 deployment 私有 store，不是业务 lineage tail。schema 分别固定为 `execution-policy-readiness-request/v1`、`execution-deployment-observation/v1`、`execution-policy-readiness/v1`。
- request/observation/verdict 各≤256 KiB；每数组≤256 项，字符串≤4096 UTF-8 bytes；超过即拒绝，不截断大型 inventory，应缩小实际授权 scope/先完成分批设计。签名/digest 只覆盖对应域+原始 payload bytes，不重序列化。facts_digest=`SHA256("execution-readiness-facts/v1\0" || u32be(len(snapshot_bytes)) || snapshot_bytes || Σ[u32be(len(observation_payload_bytes)) || observation_payload_bytes] || Σ[ref.id ASCII || NUL || ref.digest ASCII || LF])`；前一 Σ 严格按 request.observation_slots 顺序取已验原 payload，并核最终 observation_refs 的原字节域摘要，后一 Σ 按 verdict.evidence_refs 的冻结顺序；snapshot_bytes 是 immutable deployment_snapshot 原事实 bytes。worker 聚合 verified bundle 上限 16 MiB，超限拒绝，不让 Go/Node 各排一遍或重编码。
- D7 key scope 为 exact-key `{workspace_id,project_id,deployment_id,target_policy_digest,profile_purpose}`，与业务 CR/lineage key scope 是不同 schema 分支；三端签发/验签均检查 purpose/domain/scope/trust revision。observer 的 key scope 另含 exact `instance_id,role`，不能替另一实例签；不靠 business key 的 CR scope 隐式放宽。业务 verdict、普通 CLI 输出及 F1 bearer 均不可替代。
- action×purpose 只允许：`verify-channel × channel-component → READY_COMPONENT`（只入账）；`enable-policy × strict-production → READY_STRICT`（仅此可调用 ActivatePolicyTx）；`retire-legacy-relay × strict-production → READY_TO_RETIRE`（仅可交退役屏障）。其他组合拒绝；非 ready 固定 code=`NOT_READY`，ready 与 code 不一致也拒绝。
- 首版证据最长 120 秒，result 有效期不得超过最早一项 observation/探针证明的有效期；M 用 DB 当前时间核验。相同 request 只重发原 envelope；过期必须新 request/nonce 重新观测/求值，不能重签旧结果续命。时钟失准/无法核时拒绝启用。TTL 只限制陈旧，不代替 generation/成员集/fence。
- facts 收集和网络调用在 Tx 外；M 验签并入账后，`ActivatePolicyTx` 锁 deployment head→activation head，重验 scope/目标/purpose、当前完整 snapshot/generation/trust revision、有效期、nonce/request 和调用者的 operator 权限，CAS 追加 ACTIVE event 并移动 activation head；同请求响应丢失只返回原 event，不额外激活。
- 使用 Spec §4 新增 5 表；snapshot/结果/event 保留原 bytes 或固定摘要引用，不级联删除。generation 缺失/不明不能重建为零；DB 查询失败/分叉、过期或 NOT_READY 不写 ACTIVE，也不改既有 selection/历史。
- 每次首次 strict selection 和新增业务 effect 都在 caller Tx 复核当前 activation、deployment generation、目标实例/安装资格，再走原 head/cursor/root/task 校验；不是启动时缓存一次。旧 selection 引用历史 activation event 以保审计，当前准入资格必须读当前 head，不能凭历史 event 永远放行。
- **实际加载的线性化点**：只做 preflight 不够。proposed `Supervisor.PrepareLaunch(actualTuple,installSnapshot)->LeaseRef` 在 DB Tx 外 pin 受保护、只读、按摘要定位的完整安装快照（executable/runtime/registry/Agent/Skill/依赖），禁止后续经 `current` symlink、可写 PATH 或工作区重新解析。task binding Tx 写固定 lease/snapshot 与一次 launch_id，server 只在 commit 后发布原字节 launch permit；同 mapping 重投不生成新 launch ID。
- proposed `Supervisor.CommitLaunch(permit)` 在 supervisor 的 install/launch 互锁内验证固定 task/runtime/dispatched_at/daemon/boot/install generation、lease/snapshot、期限与服务端签名，持久记一次启动 intent，再以 agent UID 从该不可变快照执行 backend；这一步是实际 launch/load 线性化点，不是 `StartTask` 预检返回。切换不能改/删除已 pin 快照或让旧 lease 改载新安装；若互锁不能保留原已批准快照就拒绝 launch。无可核实启动结果时 freeze/查询原 launch，不盲目 spawn 第二个进程；不承诺外部副作用 exactly-once。
- launch permit 字段闭集=`{schema,key_id,launch_id,request_id,scope,selection_id,task_binding_id,execution_target,boot_id,install_generation,install_snapshot_ref,lease_id,activation_event_id,head,issued_at,expires_at}`；schema/domain=`execution-launch-permit/v1` / `execution-launch-permit/v1\0`，仅 control-command key allowlist 可签，scope 沿原业务授权绑定；execution_target 只取 Spec §1 的 task 分支，head 沿 Spec §2，ref/类型/限额同本节。supervisor 持久去重 launch_id；permit 过期或快照不确定只冻结原 mapping，不换候选、不新消费。
- 部署先停新准入/递增 generation 并 fence 所有 supervisor，再切换安装资格；已签原 permit 仅能执行已固定且获授权的原快照，不能加载未经核验新安装。运行中快照保留到原 lease 确认结束；仍 uncertain 不 GC。实际 backend 及所有启动适配器都必须消费此 lease/固定快照；存在旁路或不能证明 pin 时 NOT_READY。

#### 7.4 回退、恢复入口矩阵与旧接力退役
- `StopNewAdmissionsTx` 无需 READY 裁决即可在同锁序追加 STOP_NEW：回退只停新准入，不删 selection、不退消费、不清 slot/root/history，不把已选 strict 降级成 legacy。deadline 到期同样只阻断新准入。
- **持久截止边界**：每次 created→issued 必须先锁 activation head、核 ACTIVE/未过期，以 DB 时间写 issued_at、递增并冻结 admission_seq/admission_event_ref。STOP_NEW 同锁固化 cutoff_admission_seq；过期的边界为原 activation 的 expires_at。只有停止前已 issued（含 uncertain/result_ready）且 issued_at 在原有效期内、seq≤对应停止 cutoff 的原 request 可申请精确恢复；created 未 issued 不在例外内。反复 STOP/ACTIVE 不延长旧 permit、也不使原拒绝请求变新准入。
- 统一 proposed `CheckDeploymentAccessTx(op,persistedRefs)->NewAdmission|ExactRecovery|AuditOnly|Denied` 由服务端路由 op + DB 原事实解析，不信 caller `is_recovery`。恢复须逐字段相等：request/command digest、selection/origin/lineage、candidate/reservation/task UUID、subject/revisions、store/epoch/seq、原 effect mapping/actual generation（如已存在）；仅同 origin 不足。恢复结果不代表重新启用生产 policy。
| 入口 op | STOP_NEW / expiry 后的唯一允许动作 |
|---|---|
| checkpoint / verdict ingest / 原 bytes 查询 | 认证与 scope/链完整后可收集/补入原请求证据；不创建新业务 request，不因 ACK 放 slot。 |
| no_effect settlement | 可将原请求明确结算为无 effect，保留原消费/历史；revoked/terminal 时不得改成 effect。 |
| 原未结算请求完成 | 只限截止前 issued 的同一请求；可重取原 verdict/完成原 T journal，不重新消费；效果仍须 current head/撤销/终态、T stop/resume、原 root/cap 与恢复安装兼容通过。 |
| 原 mapping 的 bind/start | 只返回/绑定原 mapping、同实际 generation；遵守固定快照 lease/permit，不换候选/installation。已启动只能查询原 launch，未知 freeze。 |
| resume | 可收录认证的人类 resume 意图；新的 T resume 消费/发任务须先重新合法 ACTIVE。截止前已 issued 的 resume 仅按原请求恢复，不赋予后续派发权。 |
| 新 selection / command issue / 新 candidate/effect | 拒绝；新 grant/lineage、同 origin 或新 nonce 都不构成恢复例外。 |
- 精确恢复不把旧 readiness 续期，也不要求 policy 重新 ACTIVE；须取新的受信观测/必要的 T 部署兼容裁决以证明仍适用原 policy 与已 pin 安装，其结果只作本次原 request 的恢复证明，不移动 activation、不授权新 request。必须有**当前登记可核实**的原恢复实现/固定安装快照与兼容证据、原授权与终态校验；证据不足/缺 store/checkpoint/映射不明就 freeze。不以要求 ACTIVE 堵死已消费恢复，也不把例外变成新准入。
- **退役最终屏障**：`BeginLegacyDrainTx(scope)` 先在 deployment 锁内将 legacy_gate 置 DRAINING，阻断所有相关 legacy 新工作入口；原工作/恢复可继续，但任何 run/未决集变化均在同锁递增 legacy_work_revision。所有相关 writer 必须纳管；有旁路/离线未隔离 writer、历史覆盖未知即不得退役。
- T 的 retirement 请求 context 绑定 drain_ref、legacy_work_revision 和权威 workset_digest；先证明旧 run/未决结果已收敛且替代恢复实现匹配。`FinalizeLegacyRetirementTx` 锁 deployment→activation，CAS 复核 DRAINING、同 work revision、同 generation/snapshot/trust 与有效 retirement verdict，再将 legacy_gate 置 RETIRED、撤销接力的服务资格并留 immutable fact。观测后多出工作/恢复或 revision 漂移均拒绝；不能删历史制造空集。
- READY_TO_RETIRE 只是此前置证据，不授权直接删文件/恢复路径。实际发布/移除须另有发布授权，由受保护 supervisor 仅消费上述最终 CAS 的 retirement ref，先确认旧服务资格已撤销；失败保留 artifact 和证据，不悄悄重开 legacy_gate。没有全部 writer 的最终屏障，就一直保留旧接力。
- 受保护控制面只能确认受信任 operator 的变更意图；恶意 root/DB superuser/operator/intake 攻破本方案信任根不在保证内。部署无法做到完整 inventory、受控加载或历史覆盖时，结论固定为 NOT_READY。

#### 7.5 独立验收与下游启用的分界
- Channel 的 `channel-component` profile 以真实 worker→T 求值→签名→DB `READY_COMPONENT` 为正例；证明缺任何必需通道组件即拒绝，缺 decider 时 `strict-production` 必拒。activation CAS/锁竞争用隔离夹具验证真实事务原语，不称已获生产 READY。
- 真实 `strict-production` profile 必须包括实际 AdmissionDecider、四阶段/恢复单 effect 入口、生成 registry、实际安装及恢复兼容证据；其完整正例待 AIFI-45 下游集成。没有这些时可以交付 Channel 组件，但不能声称任何生产 strict 已启用，不形成 Channel 先依赖完整 AIFI-45 的环。
- EVD-007/RUN-008 的业务 TC 分别验收；S8 通过不自动回填。D8 只解决范围，EVD-008 既有正分支/无生产入口的区别仍保留；EVD-009 仍按当前主线单独实施。

## Global constraints
- D7 随 Channel 交付但仍不授权实施；required profile、可信 observer 身份、全部实例 fencing、受保护安装及恢复证据是后续启用前置。不能给空 components 或环境自报补一个默认 READY。
- 生产默认**不装配**新 channel/reader/decider；无新增 env 启用开关。测试 composition 显式注入真实组件；既有 manifest wiring 不等于启用 admission。
- 两类前置审批分开：①人类确认本计划/归属及后续正常实施流程；②明确授权 Linux 隔离探针的身份、launcher、目录、操作范围。均不等于部署或 Gate3。
- 不修改 DB runner/白名单，不直接对保留 DB 跑测试；新 change 使用既有 runner 前取得该共享验证资源的独占授权。
- 不承诺外部副作用 exactly-once；executor 必须以稳定 operation ID 持久幂等，结果未知先查原 operation，不能换 ID 重做。

## Vertical slices：P0 + 八片
以下文件及签名均 **proposed**；每片保留 source freeze、mutation diff、RED/GREEN raw logs，独立复核不得由作者自批。
### P0：先证明隔离，才决定采用 C
- 文件：`D/execution_control_isolation_linux_test.go`、`T/test/execution-control-isolation.test.mjs`；`ProbeIsolation(ApprovedLinuxProfile)->{service_euid,agent_euid,attacks,positive_controls}`。
- [ ] RED：同 UID 或 task 可读 key/写 store 的 profile 必须不合格；[ ] 最小 GREEN：在预置真实不同受限身份下运行 actual launcher，验证代码/runtime/key/store/IPC/env 隔离；[ ] 独立复核身份及证据。
- GWT 正：Given 获授权服务身份，When 提交测试 command，Then 可持久写/签且验证成功；反：agent 尝试读 `/proc`/fd、ptrace、写 root、连 IPC、替换 Node/模块、注入 env/F1，均不能产生 accepted verdict。
- mutation：把实际 agent launch 改回服务 UID，必须使隔离断言 RED；只有“全部拒绝”的 mock 不算通过。缺 Linux/profile 为失败或未验证，不以 SKIP 记交付。
- **F1 代签（v0.4，B7）**：主控制仍是本片的不同身份隔离；以下只把 binding endpoint 从“代签自报值”收窄为“只证明本 run 发起了请求”。① challenge 里的进程事实（pid、ppid、install root、operational root、tools digest）由 daemon 按自己的 launch 登记填写；daemon 自 spawn 起持有 pidfd，不按数字 PID 事后查 `/proc`；请求体只允许提供 nonce 与 operation。② 每个 run 一个私有 Unix socket，fd 只交给该 run 的子进程，设 CLOEXEC，拒收 SCM_RIGHTS。③ `SO_PEERCRED` 只作辅助：peer pid 必须经 pidfd 落在该 run 的已登记进程树内。不把 `/proc/<pid>/root` 当成工具安装根，也不以 `exe` 证明加载了哪个 JS。P0 daemon 隔离用例增设子例 `peer_credential_match`（正对照）、`self_reported_fact_ignored`（请求体自报 pid/root 被忽略，证明里只出现登记值）、`foreign_run_socket`（同 UID 的其他 agent 连本 run socket 被拒）、`fd_transfer`（socket fd 转给树外进程被拒）、`pid_reuse`（原进程退出后同 PID 新进程被拒）。mutation：改回信任请求体 pid、改回数字 PID 查 `/proc`，分别 RED。缺 Linux/profile 必须 `t.Fatalf`，禁止裸 `return`。X1 已决（2026-10-26）：Windows 属 strict 生产平台，因此 P0 必须同时交付 Windows 身份证明（命名管道 client pid + 进程句柄/令牌 SID + daemon launch 登记，拒绝请求体自报），与 Linux `SO_PEERCRED` 路径各自出证据，缺一即 unverified。

### S1：Channel 自有 Foundation，独立真实验收
- 新建：上述 648 up/down、`G/execution_contract_selection{,_test}.go`、`G/execution_control_reservation{,_test}.go`；修改：`G/execution_dispatch_root.go`、`M/server/internal/service/task.go`、`M/server/pkg/db/queries/agent.sql`，用固定版本 sqlc 生成 `M/server/pkg/db/generated/agent.sql.go`；实现 Spec §1 的 Tx 签名，不手编生成列。两组 Go 验收分别命名 `TestChannelFoundationSelection`、`TestChannelFoundationReservation`，模板单独选取，不被其他片的 PASS 遮住缺测。
- 本片同时实现 Spec §5 的 `G/execution_fresh_work{,_test}.go` / `RegisterFreshWorkTx`、control_fact 的权威 origin/历史覆盖与 partial unique，selection/reservation 同事务固定 FreshWorkRef；顶层 `TestChannelFoundationFreshWork` 独立验收来源/唯一性/UNKNOWN。不新增第 14 表；S8 的 `TestChannelReadinessFreshWork` 是复用此实现的跨控制面 D8 反用测试，不代替本片基础验收。
- [ ] RED：跨 scope candidate、非固定 ID 或 Tx rollback 后遗留 task/通知；[ ] 最小 GREEN：真实 DB selection→reservation→同 Tx root/fixed task→commit 后 notify；[ ] 复核 wrappers 与 attribution。
- GWT：合法 source/固定 candidate commit 得唯一真实 root/task；rollback 得零持久新增且零通知；control reservation 自身永不 runnable。mutation：提前通知、删除 fixed-ID 相等校验分别 RED。
- **adoption/terminal 并发（v0.4，B8）**：`TestChannelFoundationReservation` 增设子例 `root_adoption_terminal_race`。用 F4 手法验证锁，不数结局：在 `ValidationTestHook` 内，另一连接 `set_config('lock_timeout','300ms')` 后尝试改同一 logical root 的终态，只认 SQLSTATE `55P03`，另设无锁冲突的正对照。mutation：去掉根行锁必须 RED，失败断言不能是超时或连接错。**green 前置（v0.5 复核更正）**：该并发本身**不需要可信事实**，归属 AIFI-45（`V/m001-m002-evidence-gap-ledger-20261026.md` G5：adopter 先普通 SELECT 读到可 adopt 根、另一事务标终态、随后无 `terminal_at IS NULL`/generation 条件的 UPDATE 仍成功）——**G5 未修则本 leaf 必然 RED**，本片只负责接线与 `55P03` 探针，锁修复不属本方案，也不得把未修状态记为本片完成。结局语义（不得 adopt 已终态根、终态后不得重建同逻辑根）另用顺序用例覆盖。本片把 dispatch_root 从“仅测试调用”变成组件级真实接线；TC-RUN-004/005 的计数仍由 AIFI-45 自行核算。同时补齐 v0.3 遗留：service 侧新建 `M/server/internal/service/execution_channel_task_tx_test.go`，顶层 `TestChannelTaskTx`，承接模板 `task-tx` label。
- 此片不等待 T/decider；测试直接验收真实 primitives，不宣称已经具备生产 admission permission。

### S2：协议、key-purpose 与跨语言向量
- 文件：`G/execution_control_protocol{,_test}.go`、`D/execution_control_trust.go`、`T/lib/execution-control-protocol.mjs`、`T/test/execution-control-protocol.test.mjs`。
- governance 顶层固定 `TestChannelProtocol`（D7 另用 `TestChannelReadinessProtocol`），未来模板各自精确命中。接口：`VerifyEnvelope(raw,expectedPurpose,domain,scope)->VerifiedBytes`；[ ] RED purpose/domain/scope 混用；[ ] 最小 GREEN Go↔Node 合法原 bytes 向量；[ ] 复核全部 exact-key 分支。
- GWT：合法 command/verdict 双向通过；attestation key 签 resume、human key 擅签 command、重复键及 union 双分支均拒绝。mutation：删 purpose 检查/忽略 control target fence，分别 RED。

### S3：一次 protected commit 与原字节重放
- 文件：`T/lib/execution-control-store.mjs`、`durable-tx.mjs`、repair/action store seam、`T/test/execution-control-store.test.mjs`；`ApplyOnce(command,fn)->FrozenEnvelope`。
- [ ] RED commit 前 frame/fsync 错误仍成功；[ ] 最小 GREEN journal+原子 bundle+完整冻结 envelope；[ ] 复核所有故障点与旧 CLI 回归。
- GWT：同 admit/assessment/resume 请求并发、rename 前后 kill，恢复后仅一次业务变化且 bytes 相同；fsync 失败无 frame。mutation：重投重算 `replayed`、提前发布 frame，分别 RED。
- **冻结帧链完整性（v0.4，B9 的存储侧）**：每条 repair/action 记录只能经冻结 envelope 链入账（`sequence` 连续、`previous_verdict_digest` 指向上一帧）；断链、跳号或占位签名（如现有测试里的 `signature=AA==`）一律拒绝。mutation：跳过 prev digest 校验，必须 RED。**这只保证账本不可篡改，不等于 RPR-007/008 的追加授权**；追加授权正链见 Spec §2 追加域与 S5。

### S4：固定 worker、monotonic fence 与恢复
- 新建：`D/execution_control_worker{,_test}.go`、`D/execution_control_recovery{,_test}.go`、`T/lib/execution-control-worker.mjs`、`T/test/execution-control-worker.test.mjs`、`T/test/execution-control-recovery.test.mjs`。
- 接口：`BeginOwnerTx()->Fence`、`ReconcileOwnerTx(checkpoint)->Ready|Frozen`、`Worker.Apply(command)->CommittedFrame`；[ ] RED 旧 owner 接单/缺 checkpoint 继续；[ ] 最小 GREEN Spec 恢复表；[ ] 复核真实进程身份。
- GWT：普通 restart 保持 epoch/seq 并重发原 bytes；旧 worker、缺 store、落后/分叉均冻结，合法一致 checkpoint 可继续。mutation：restart 清 seq、接受旧 fence，分别 RED。

### S5：可信 facts、repair/resume/evidence 与 exact action
- 新建：`G/execution_control_fact{,_test}.go`、`G/execution_repair_resume{,_test}.go`、`T/test/execution-control-policy.test.mjs`；修改 `T/lib/repair-governance.mjs`、`T/lib/execution-sensitive-action.mjs` 及 evidence commit wrapper。Go 用例分别命名 `TestChannelPolicyFacts`、`TestChannelPolicyResume`，单独命中验收，不只依赖整包计数。
- 接口：`ResolveFactsTx(refs)->TypedFacts`、`ApplyOperation(command,facts,store)->TResult`；[ ] RED 自报 reviewer/unsigned resume/专项改 target；[ ] 最小 GREEN 真实归属 facts+唯一 T 规则；[ ] 复核无 Go 预算分支。
- GWT：两次 no-progress 提交 stop；合法 signed resume 一次 epoch、原消费不清；quota exhausted 有旧 receipt 仍拒新准入；专项只允许 exact target/environment。mutation：quota→permit、跳过 resume stop_ref/签名、删 target equality，均 RED。
- **v0.4 补充（B5/B6/B9/B10）**：`TestChannelPolicyFacts` 增设 `repair_admit_fact_refs_verified`（command `fact_refs` 必须指向已验签 grant，额度不得来自解码 payload）、`sensitive_copy_root_new_operation`（复制安装/信任根后用**新** operation_id 消费，必须 EXHAUSTED，原账本计数不变）、`sensitive_same_operation_replay`（同 operation_id 原字节重放返回原 receipt、不再消费，对应 SC-AUTH-006）、`sensitive_revoke_interleaving`（交错矩阵：撤销先于 M settlement 提交时，即使 T 已提交也结算为 no_effect，外部动作不执行）、`sensitive_legacy_ledger_unverified`（旧账本来源不可核实时拒绝新增消费）。`TestChannelPolicyResume` 增设 `repair_extension_append`、`repair_extension_double_append_race`、`repair_extension_replay`；签名 resume（B10）沿用既有覆盖。Node `T/test/execution-control-policy.test.mjs` 固定 leaf：`repair-admit 拒绝未验签 payload`、`repair 追加 CAS 只接受一份`、`cr.md 合同字段与 store 不一致即拒`。mutation 与 RED leaf 一一对应：恢复未验签解码 → Node `repair-admit 拒绝未验签 payload`；账本改回随 trust-root 定位 → Go `sensitive_copy_root_new_operation`；去掉 M settlement 的 head/撤销重验 → Go `sensitive_revoke_interleaving`；去掉追加 CAS → Go `repair_extension_double_append_race` 与 Node `repair 追加 CAS 只接受一份`；去掉 store 比对 → Node `cr.md 合同字段与 store 不一致即拒`。trusted facts 提供 repair 的真实尝试/assessment 身份、subject、epoch；对应业务规则缺陷（B16）由 AIFI-45 在 T 侧修，本方案不重写规则。
- **v0.5 补充（B11，经 balanced/economy 复核修订）**：Node `T/test/execution-control-policy.test.mjs` 增设固定 leaf 与**一一对应**的 mutation：
  - **第二轮修订（strong 复核）补充的 leaf 与 mutation**：`merge 范围 rename 源与目标都查`（只查目标路径 → RED）、`merge 范围 symlink 取自发布候选树`（按选定提交的 tree/blob mode 与链接目标判定，不读工作树 realpath、不读 index mode；mutation：改读工作树 realpath → RED；再一条 mutation：改用 index mode → RED。R1 定 (a) 后本 leaf 由“取自批准树”改写，原形态只在 (b) 成立）、`merge 范围空集合不可放行`（仓集合缺一项/采集失败 → `AUTH_SCOPE_UNVERIFIABLE`；mutation：把缺失当空集合）、`merge 范围 Unknown selection 即拒`（目录缺行/读失败 → 拒，不降 legacy；mutation：Unknown 当 legacy 放行）、`merge 范围恢复沿用原冻结输入`（恢复时 YAML 已变 → 拒；mutation：恢复改读当前 YAML）、`merge 范围撤销发生在部分发布后`（publish 中途撤销 → 停止后续 publish 且保留原 journal/receipt；mutation：改为自动新建事务解除阻断）。
  - **既有 mutation 的触发条件补强**（strong 复核）：`legacy merge 不核对范围` 的 mutation 必须是“对**可信目录证明的 legacy** 也强制核对”，并用原本可 merge、但不满足 Strict 范围条件的夹具精确打红；`merge 范围不受 grants 目录旧文件影响` 必须让该旧 grant 在错误扫描策略下**确定被选中**（否则 mutation 打不到）；`merge 范围 head 撤销即拒` 必须在首次读取之后、效力检查之前**确定性交错**撤销或 head 前移（若一开始就撤销，删掉后续重读也不会变色）；`merge 范围核对越界零写入` 需补“移到 journal 之后、prepare 之前”的反例 mutation，并观测 journal/锁/outbox/Git 写命令而非只验目录。
  - `merge 范围核对越界零写入`（`trunk...HEAD` 含授权外路径 → `AUTH_SCOPE_VIOLATION`；断言无 journal、无 publish：注入 publish 端口并断言零调用，而不只验退出码）↔ mutation：把核对移到 publish 之后。
  - `merge 范围只看已批准 source sha`（`approval.yml` 的 release subject 与 M 持久记录**不等** → `AUTH_SCOPE_UNVERIFIABLE`；相等且区间内无越界 → 通过）↔ mutation：改用工作区/untracked 作为输入。
  - `merge 范围核对覆盖发布集合`（release subject **之后**的提交含授权外路径 → 拒；这正是 `trunk...<subject sha>` 写法会漏检的那一段）↔ mutation：把核对区间收窄成 `trunk...<release subject sha>`。
  - `merge 范围删合同字段仍 strict`（删 `cr.md` 合同字段后仍按 strict 判定，缺 T 裁决即拒）↔ mutation：改读 `cr.md` 合同字段。
  - `merge 范围不受 grants 目录旧文件影响`（放入一份更宽的旧 grant 不放宽结论）↔ mutation：改为扫描 `grants/` 目录取最新。
  - `merge 范围 head 撤销即拒`（`EXECUTION_AUTHORIZATION_REVOKED`）与 `merge 范围 head 前移即拒`（`EXECUTION_AUTHORIZATION_HEAD_MOVED`；含“不等于批准时快照、按当前 head 判”的正例）↔ mutation：去掉 head/撤销重读；以及 mutation：按批准时快照比对。
  - `legacy merge 不核对范围`（可信历史目录证明的 legacy CR：不核对、不要求 grant，行为不变）↔ mutation：让 legacy 分支也进入范围核对（必须 RED）。
  - `merge 范围 release-subject 缺失即拒` 与 `merge 范围无法核实即拒`（收集失败/定位失败 → `AUTH_SCOPE_UNVERIFIABLE`）↔ mutation：把缺省当空集合放行。
  - `merge 范围越界不推进状态`（越界后 CR 状态仍为 `code-approved`，不回退 `developing`）↔ mutation：越界时改走 release-drift 回退。
- **R1 定 (a) 后新增 leaf**：`merge 范围 finalize 写集逐项授权`（`cr.md`/`merge-commits.yml`/`merge-verification.md` 三个生成路径分别出现在 `allowed_paths` 时通过；任一漏列 → `AUTH_SCOPE_PATH_NOT_ALLOWED`，不得以“系统生成”豁免）↔ mutation：给 finalize 生成路径加隐式豁免 → RED。同批：`merge 范围核对含 KB 审批后写入`（获批后新增/修改 `approval.yml`、`cr.md` 落进区间 → 必须被核对；mutation：把 KB 控制根排除出核对范围 → RED）。

### S6：真实 ingest、settlement 与 task-start binding
- 新建：`G/execution_tool_ingest{,_test}.go`、`G/execution_control_settlement{,_test}.go`、`G/execution_control_migration_test.go`、`D/execution_control_client{,_test}.go`；修改 `D/execution_verifier.go`。迁移专例共享单一 `ChannelTableNames` 清单（精确 14 个 DB 全名、无重复；§4 表格只列后缀）与本 migration 对象清单；`TestChannelMigrationAfterUp` 对完整 up 逐表/trigger/index/constraint 检查；`TestChannelMigrationAfterDown` 检查全部 14 张新表及其触发器/索引均已撤销；`TestChannelMigrationAfterReapply` 检查同名对象/约束恢复、无遗留业务行，分别在 up、up→down、up→down→up 的新库中运行，不混入普通回归。三例每表各一 `t.Run`，每例至少 14 PASS leaf。另 `TestChannelMigrationProtectedData` 在本次独占 nonce 库 up 状态先造 643–647 夹具，再由该隔离测试按精确 648 down/up 做生命周期验证，断言原夹具行/对象不变及无 648 孤儿对象；不修改 DB runner、不接触 HOLD 库。
- 本片的 settlement/binding 顶层分别命名 `TestChannelIngestSettlement`、`TestChannelIngestBinding`，daemon client 为 `TestChannelWorkerClient`，均由未来模板独立精确命中，不能凭文件名或整包 PASS 推定已跑。
- `TestChannelIngestRevokedPermit` 的失败分支固定子例 `revoked_permit_effect`，仅在撤销先提交却仍产生 effect 的失败断言输出 `CONTROL_REVOKED_PERMIT_EFFECT`；另留 `unmutated_control` 正对照。不许无条件 t.Log marker，不把编译/连接/无匹配错误当 RED。
- 接口：`IngestTx(envelope)->VerdictRef`、`SettleCandidateTx(...)`、`BindDeliveredGenerationTx(reservation,actualTuple)->Binding`；[ ] RED ACK 释放 slot/假 generation；[ ] 最小 GREEN auth→真实 worker→DB→固定 task；[ ] 复核 revoke/stop barriers。
- GWT：T commit/M rollback 重送；effect commit/响应丢失仅原 mapping；revoke 先赢得 no_effect；ingest ACK 不发 task，start 前真实 643–645 全匹配。mutation：result_ready 释放 slot、删 current-head 重验，各自 RED。
- **AIFI-45 修复的不绕过断言（v0.4，B1/B2）**：`TestChannelIngestBinding` 增设 `cross_issuance_challenge`（task A 签发的 challenge 用于 task B）、`same_task_redispatch_challenge`（同 task/runtime、不同 `dispatched_at` 的旧 challenge）、`same_nonce_different_proof`（相同 nonce、不同证明内容）与 `claim_terminated_before_consume`（读 claim 后任务转终态，不得写入消费；用 `55P03` + `lock_timeout` 探针，不接受超时当 RED）。**green 前置（v0.5 复核更正）**：AIFI-45 的 B1（签发与消费绑定完整 generation）、B2（统一锁图）、B3（终态 CAS 后同事务 fence）已合入，但仍**不够**：`claim_terminated_before_consume` 的真实前置是 **G1**（读完 active generation 后暂停时，另一事务取消/重领或改 runtime 归属并提交，原事务仍可写 receipt/activation——需三写端点共用完整校验事务、锁 task/runtime 归属行至提交、`55P03` 探针），叠加 **G2 残余**（签名 payload 仍不含 `dispatched_at`）与 **G4 残余**（strict 全 tuple）。G1/G2/G4 未修时这几条按设计为 RED，不得把本片记为完成。修复本身不属本方案。

### S7：reader 组件与 strict fence 的真实正反验收
- 文件：`G/execution_tool_reader.go`、`execution_tool_reader_integration_test.go`、`execution_projection_fence.go`，修改上述 projection 写路；`cmd/server/execution_control_composition_test.go`。本片 composition 顶层用例命名 `TestChannelComposition`（分支使用 `t.Run`），与 S8 的 `TestChannelCompositionReadiness` 分开匹配。
- governance 顶层固定 `TestChannelReader`，未来模板精确命中。接口：`ReadCommitted(ctx,tx,key)` 与测试 composition 中真实 `SettleCandidateTx`；[ ] RED 缺 T permit/移除 fence；[ ] 最小 GREEN 真实 worker+MDT+DB+reader+Tx primitives；[ ] 非作者核查证据。
- GWT：ACK/平台 receipt/伪 Git pass 无 committed T 时零 root/task；合法 T permit 创建唯一原候选，重复仅旧 mapping；Unknown/strict 缺 reader 拒绝。mutation：missing-T→permit、允许 snapshot 写 strict state、replay 换 candidate，均 RED。
- **v0.4 补充（B4/B12b、B3）**：`TestChannelReader` 增设 `selected_strict_field_deleted`（selection 已为 Strict，删除 trigger 合同字段后仍按 strict 判定，缺 T 裁决即拒）、`never_selected_legacy_unchanged`（被可信历史目录证明的 legacy 任务行为不变，对应 SC-EVD-006）、`unknown_selection_not_legacy`（目录缺行/读失败按 Unknown 拒绝）、`terminal_report_without_claim`（`fence_required` 任务两字段都缺上报终态必须 409）、`terminal_fence_survives_reclaim`（generation A 已消费、重领为 B 后省略 claim 仍 409）、`legacy_consumed_keeps_fence`（无 selection 但已消费的任务在本规则装配后仍须带 claim）、`terminal_fence_read_failure`（判定读失败即拒）。mutation：按 trigger 文本判 strict、按请求是否带 tuple 选分支、把并集改成替换，分别 RED。
- 本片证明组件正路径，不实现/冒称完整 Runner decider；本 change 不回填 AIFI-45 的 41/49。后续 TC-RUN-002/003/006/010 及 RUN009 的业务验收、计数更新由 AIFI-45 自行完成，41/49 不是永久冻结。
- 命名约束：governance 普通用例为 `TestChannelFoundation|Protocol|PolicyFacts|PolicyResume|Ingest|Reader…`，D7 为 `TestChannelReadiness|Deployment|PolicyActivation…`（协议为 `TestChannelReadinessProtocol`）；生命周期专例 `TestChannelMigration…`。daemon 普通为 `TestChannelWorker|Recovery…`，D7 为 `TestChannelDeployment…`，P0 为 `TestChannelIsolation…`；service 为 `TestChannelTaskTx…`；cmd/server 分为顶层 `TestChannelComposition` 与 `TestChannelCompositionReadiness`。文件名不是 `-run` 匹配依据。

### S8：D7 独立部署就绪、启用与回退（R0–R4）
- 所有文件/接口仍 proposed；本片不注册新 change，不消费业务预算。R0 是 Spec §7 的事实契约与受控部署前提，不得以代码先行代替身份/部署授权。
| 顺序 | 文件与接口 | RED → GREEN / mutation 验收 |
|---|---|---|
| R0 可信 facts/完整 inventory | `D/execution_deployment_observer{,_test}.go`，顶层固定 `TestChannelDeploymentObserver`；`CaptureDeployment(ApprovedProfile,Nonce)->SignedObservations`，复用 P0 受保护身份、实际 runtime/安装根与受控 probe，批准的 profile/实例/安装目标清单随新 change SPEC 固定 | agent/env/Git 伪造、一个合格副本掩盖离线旧副本、安装路径可写时均拒绝；真实受保护组件测量为正对照；删成员检查须业务 RED。 |
| R1 唯一 T readiness | 修改 `T/lib/component-readiness.mjs`；新 `T/test/execution-control-readiness.test.mjs`；严格入口 `EvaluateDeploymentReadiness(profile,observations)->ReadinessResult` 调唯一 evaluator | 空/缺 components、重复 observed、遗漏/unknown/NA 绕过、只有 marker 一致但 runtime/安装变化、恢复能力未知均 NOT_READY；合法非空 profile 正例。T 中加固，不另写 Go 比较器。 |
| R2 独立 worker/domain | `T/lib/execution-control-readiness.mjs`、`G/execution_policy_readiness_protocol{,_test}.go`，扩展既有 worker；实现 `Worker.EvaluateReadiness` 和 Spec §7 request/verdict exact-key schema | 跨语言真实正例必须按“冻结 request slots→各 observer 签发→最终 verdict”顺序构造；换 slot/摘要、重复或缺观测、错 purpose、跨 scope/policy/vector/nonce、过期及重签续期均拒绝；同 request 丢响应/重启只返回原 bytes；无业务 lineage/slot 也可求值。 |
| R3 持久与原子启停 | `G/execution_deployment{,_test}.go`、`G/execution_policy_activation{,_test}.go`，扩展 proposed 648；实现 `RecordReadinessTx`、`ActivatePolicyTx`、`StopNewAdmissionsTx`、`BeginLegacyDrainTx`、`FinalizeLegacyRetirementTx`；控制面挂在仅 operator 可调用的服务入口，不引入 PAT/task-token fallback | 签后部署变代、activation/update 并发、response 丢失、nonce 重放、generation 删除归零、DB 失败均不误激活；真实 DB 证明 CAS/锁及 append-only，STOP_NEW 不改历史/预算；观测后旧工作 revision 漂移必须阻止 RETIRED。 |
| R4 selection/effect/start 共用 fence | 修改 S1/S6/S7 的 selection、settlement、task preflight/所有 backend 启动适配器与测试 composition；`G/execution_deployment_fence{,_test}.go` 实现 `CheckDeploymentAccessTx(op,persistedRefs)->AccessClass`；新 `D/execution_launch_snapshot{,_test}.go` 实现 `PrepareLaunch/CommitLaunch` 与固定快照/原字节 permit | 原 issued 请求在 STOP_NEW/expiry 后精确恢复，created 未 issued/新候选/换 origin 不能；在 preflight 与 backend.Execute 之间暂停换代，只能拒绝或加载原已批准固定快照；不能改载新安装、重签 ID 或盲目重启。移除 cutoff、pin 或 generation 校验分别须业务 RED。 |
- `TestChannelReadiness…`（governance）、`TestChannelDeployment…`（daemon）、`TestChannelCompositionReadiness…`（cmd/server）匹配新模板；原生命周期测试随 14 表清单复核。
- 真实 component profile 正例 + strict 缺 decider 反例是本片独立交付证据；真实 strict 生产正例另在 AIFI-45 集成与发布验证，不能用隔离夹具或 P0 代替。
- `retire-legacy-relay` 必测旧 run 存活/未知未决任务时拒绝删除，签发后新增 legacy 工作/恢复令 work revision 漂移仍拒绝最终退役；未纳管 writer 不能出 drain 证明。STOP_NEW 后缺 store/checkpoint 冻结、原映射恢复成功且历史/slot/消费/root 不变。
- D8 成对断言固定为 `TestChannelRecoveryD8`（daemon）及 `TestChannelReadinessFreshWork`（governance）：同 lineage/store/epoch 重启保留原 command/receipt bytes、effect mapping、历史与 slot/root/累计消费；同 CR/origin 换 grant/lineage/store/epoch、删 selection、换 CR/source alias 及并发注册均不能清零；历史覆盖缺失必须 UNKNOWN，旧 legacy run/合同不改。
- component/strict 分界固定 `TestChannelReadinessComponentBoundary`：真实 worker→T→签名→DB 只能写 READY_COMPONENT，activation head/event 必须不变；该结果或 retirement 结果用于 ActivatePolicyTx 一律类型化拒绝/零 ACTIVE；真实 strict inventory 缺 AdmissionDecider 返回 NOT_READY。strict 完整正例仍是下游，不计本片已上线。
- S8 其余顶层名称固定：`TestChannelReadinessProtocol`、`TestChannelDeploymentAccess`（§7.4 矩阵每行独立子例）、`TestChannelPolicyActivation`、`TestChannelReadinessRetirement`、daemon `TestChannelDeploymentLaunch`、`TestChannelCompositionReadiness`；模板逐一命中，不用其他 family 的 PASS 掩盖缺组。

### 验收证据检查（S8 一并交付，不改变 DB runner）
- 新 change 的 SPEC 先冻结 `validation/channel-test-expectations.json`：schema=`channel-test-expectations/v1`，每个命令 label 明列必达的**实际 leaf 全名**，禁止由本次输出反推名单；aggregate label 只能额外回归，不替代单片名单。Go 名字含父/子路径，Node leaf title 在对应文件内必须唯一；矩阵、D8 正/负、组件/strict 反用、launch 换代、退役 revision 竞争各自列出，不以一个父测试名代替。
- proposed `M/scripts/aifi45-verify/channel-evidence.mjs`（stdlib-only，只读证据）及其 `.test.mjs`：`VerifyChannelEvidence(format,phase,label,prefix,expected,failLeaf,marker)->Report`。green 对照名单逐一要求真实非 skipped PASS leaf；缺组/少子例/仅父 PASS、重名、全 skip、setup/编译失败都拒绝。读取 raw Go JSON 与 TAP 树，不靠 summary 数字猜叶子。
- red 除 runner 非零外，必须是名单中指定的失败 leaf，marker 位于该 leaf 的条件失败断言输出；只允许其父级因子例失败而 fail，不接受其他失败或无条件日志 marker，且有一个未受 mutation 影响的 PASS control leaf。Go 的正常包级 FAIL 汇总不当成独立错误；编译/setup/连接错均不是预期 RED。checker 自检须含“summary 看似成功但缺期望 leaf”等反例。
- 每项 mutation 保存 patch hash、基线与恢复后 source hash、实际 argv、匹配的失败 leaf 和条件断言；恢复 hash 相同后另起 nonce 跑 green。无此证据不得把基本 wrapper 的 exit/count 屏幕判定当完整验收。
- **v0.4 必达 leaf（进 `channel-test-expectations.json`）**：`TestChannelFoundationReservation/root_adoption_terminal_race`；`TestChannelPolicyFacts/{repair_admit_fact_refs_verified,sensitive_copy_root_new_operation,sensitive_same_operation_replay,sensitive_revoke_interleaving,sensitive_legacy_ledger_unverified}`；`TestChannelPolicyResume/{repair_extension_append,repair_extension_double_append_race,repair_extension_replay}`；`TestChannelIngestBinding/{cross_issuance_challenge,same_task_redispatch_challenge,same_nonce_different_proof,claim_terminated_before_consume}`；`TestChannelReader/{selected_strict_field_deleted,never_selected_legacy_unchanged,unknown_selection_not_legacy,terminal_report_without_claim,terminal_fence_survives_reclaim,legacy_consumed_keeps_fence,terminal_fence_read_failure}`；P0 `TestChannelIsolation/{peer_credential_match,self_reported_fact_ignored,foreign_run_socket,fd_transfer,pid_reuse}`；以及 S5 列出的三条 Node leaf。`rungo`/`runnode` 的 exit/count 只是前置；该 label 名单为空，或任一 leaf 缺失、为 SKIP、只有父级 PASS，均判未验证。
- **v0.5 必达 leaf**：S5 “v0.5 补充（B11）”列出的 Node leaf（**逐个以其条目为准，本文件不以整数指代**；当前为 19 个（R1 定 (a) 后新增两条）：`merge 范围 rename 源与目标都查`、`merge 范围 symlink 取自发布候选树`、`merge 范围空集合不可放行`、`merge 范围 Unknown selection 即拒`、`merge 范围恢复沿用原冻结输入`、`merge 范围撤销发生在部分发布后`、`legacy merge 不核对范围`、`merge 范围不受 grants 目录旧文件影响`、`merge 范围 head 撤销即拒`、`merge 范围核对越界零写入`、`merge 范围只看已批准 source sha`、`merge 范围核对覆盖发布集合`、`merge 范围删合同字段仍 strict`、`merge 范围 head 前移即拒`、`merge 范围 release-subject 缺失即拒`、`merge 范围无法核实即拒`、`merge 范围越界不推进状态`、`merge 范围 finalize 写集逐项授权`、`merge 范围核对含 KB 审批后写入`）；另加 v0.6.1 节 R2.5 与 R3.5 列出的 leaf；判定口径同上（缺失、SKIP、只有父级 PASS 均判未验证）。**mutation 并非天然 1:1**：`merge 范围核对越界零写入` 要求**两条** mutation（移到 publish 之后；移到 journal 之后、prepare 之前），`merge 范围 release-subject 缺失即拒` 与 `merge 范围无法核实即拒` **共用**一条“缺省当空集合放行”的 mutation。任何清单必须显式写出这两处不对称，不得再用“N:N 一一对应”概括。

## 未来验证命令模板
仅在新 change 已登记、测试已实现且验证资源获授权后执行；**现在不运行**。Git Bash 模板捕获真实退出码，预期 RED 不被 `set -e` 中途吞掉；每次 fresh nonce、阶段标签、绝对路径。
```bash
set -euo pipefail
M='C:/Users/GOBAO/Downloads/AI/multica'
T='C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl/scripts'
C='C:/Users/GOBAO/Downloads/AI/AI First Platform/projects/multica/changes/2026-10-26-aifi-trusted-tools-verdict-channel'
test -f "$C/.stdd.yaml"  # 未登记则停止，不创建貌似已登记的目录
EV="$C/validation/channel-v03"
EXPECT="$C/validation/channel-test-expectations.json"
test -f "$EXPECT" && test -f "$M/scripts/aifi45-verify/channel-evidence.mjs"
export AIFI45_TOOLS_ROOT='C:/Users/GOBAO/Downloads/AI/tools'
mkdir -p "$EV"
nonce() { node -e 'console.log(require("node:crypto").randomBytes(8).toString("hex"))'; }
runnode() {
 local phase="$1" label="$2" n rc=0 p; shift 2; n="$(nonce)"; p="$EV/node-$phase-$label-$n"
 (cd "$T"; node --test --test-reporter=tap "$@") >"$p.tap" 2>"$p.stderr.log" || rc=$?
 node -e 'const a=require("node:assert/strict"),f=require("node:fs"),[s,p,r,x]=process.argv.slice(1),t=f.readFileSync(p,"utf8"),n=k=>Number(t.match(new RegExp("^# "+k+" (\\d+)$","m"))?.[1]??NaN);a(["green","red"].includes(s));a(n("tests")>0);a.equal(n("skipped"),0);a.equal(n("todo"),0);a.equal(n("cancelled"),0);if(s==="green"){a.equal(+r,0);a(n("pass")>0);a.equal(n("fail"),0)}else{a.notEqual(+r,0);a(n("fail")>0);a(x&&t.includes(x))}console.log(s,p,r)' "$phase" "$p.tap" "$rc" "${RED_ASSERTION:-}"
 node "$M/scripts/aifi45-verify/channel-evidence.mjs" --format node --phase "$phase" --label "$label" --prefix "$p" --expect "$EXPECT" --fail-leaf "${RED_TEST:-}" --marker "${RED_ASSERTION:-}"
}
runnode green protocol ./test/execution-control-protocol.test.mjs
runnode green store ./test/execution-control-store.test.mjs
runnode green worker ./test/execution-control-worker.test.mjs
runnode green recovery ./test/execution-control-recovery.test.mjs
runnode green policy ./test/execution-control-policy.test.mjs
runnode green readiness ./test/execution-control-readiness.test.mjs
runnode green repair-regression ./test/repair-governance.test.mjs
MIG=(
 '-migration=server/migrations/643_cr_execution_binding_issue.up.sql'
 '-migration=server/migrations/644_cr_execution_consumption.up.sql'
 '-migration=server/migrations/645_cr_execution_activation.up.sql'
 '-migration=server/migrations/646_cr_execution_notice.up.sql'
 '-migration=server/migrations/647_cr_execution_dispatch_root.up.sql'
 '-migration=server/migrations/648_cr_execution_control.up.sql'
)
rungo() {
 local phase="$1" label="$2" pkg="$3" re="$4" n rc=0 p; shift 4; n="$(nonce)"; p="$EV/go-$phase-$label-$n"
 (cd "$M"; node scripts/aifi45-db/run.mjs "$pkg" "$re" "$p" "${MIG[@]}" "$@") >"$p.runner.log" 2>&1 || rc=$?
 node -e 'const a=require("node:assert/strict"),f=require("node:fs"),[s,p,r,x]=process.argv.slice(1),d=JSON.parse(f.readFileSync(p+".meta.json","utf8")),c=d.test.counts;a(["green","red"].includes(s));a(d.original_unchanged&&d.owned_resources_cleaned);a.equal(d.original_release.sessions,0);a.equal(d.original_release.locks,0);a(c.run>0);a.equal(c.skip,0);if(s==="green"){a.equal(+r,0);a.equal(d.test.exit,0);a.equal(c.fail,0);a(c.pass>0&&d.test.leaf_pass>0)}else{a.notEqual(+r,0);a(c.fail>0);a(x&&f.readFileSync(p+".stdout.jsonl","utf8").includes(x))}console.log(s,p,r)' "$phase" "$p" "$rc" "${RED_ASSERTION:-}"
 node "$M/scripts/aifi45-verify/channel-evidence.mjs" --format go --phase "$phase" --label "$label" --prefix "$p" --expect "$EXPECT" --fail-leaf "${RED_TEST:-}" --marker "${RED_ASSERTION:-}"
}
rungo green foundation-selection ./internal/governance '^TestChannelFoundationSelection$'
rungo green foundation-reservation ./internal/governance '^TestChannelFoundationReservation$'
rungo green foundation-fresh-work ./internal/governance '^TestChannelFoundationFreshWork$'
rungo green policy-facts ./internal/governance '^TestChannelPolicyFacts$'
rungo green policy-resume ./internal/governance '^TestChannelPolicyResume$'
rungo green protocol ./internal/governance '^TestChannelProtocol$'
rungo green settlement ./internal/governance '^TestChannelIngestSettlement$'
rungo green binding ./internal/governance '^TestChannelIngestBinding$'
rungo green reader ./internal/governance '^TestChannelReader$'
rungo green client ./internal/daemon '^TestChannelWorkerClient$'
rungo green d8-recovery ./internal/daemon '^TestChannelRecoveryD8$'
rungo green revoked-permit ./internal/governance '^TestChannelIngestRevokedPermit$'
rungo green core ./internal/governance '^TestChannel(Foundation|Protocol|PolicyFacts|PolicyResume|Ingest|Reader)'
rungo green worker ./internal/daemon '^TestChannel(Worker|Recovery)'
rungo green task-tx ./internal/service '^TestChannelTaskTx'
rungo green composition ./cmd/server '^TestChannelComposition$'
rungo green readiness-protocol ./internal/governance '^TestChannelReadinessProtocol$'
rungo green readiness-access ./internal/governance '^TestChannelDeploymentAccess$'
rungo green readiness-activation ./internal/governance '^TestChannelPolicyActivation$'
rungo green readiness-fresh-work ./internal/governance '^TestChannelReadinessFreshWork$'
rungo green readiness-retirement ./internal/governance '^TestChannelReadinessRetirement$'
rungo green readiness-component ./internal/governance '^TestChannelReadinessComponentBoundary$'
rungo green deployment-observer ./internal/daemon '^TestChannelDeploymentObserver$'
rungo green deployment-launch ./internal/daemon '^TestChannelDeploymentLaunch$'
rungo green readiness-composition ./cmd/server '^TestChannelCompositionReadiness$'
rungo green migration-up ./internal/governance '^TestChannelMigrationAfterUp$'
rungo green migration-protected ./internal/governance '^TestChannelMigrationProtectedData$'
rungo green migration-down ./internal/governance '^TestChannelMigrationAfterDown$' '-migration=server/migrations/648_cr_execution_control.down.sql'
rungo green migration-reapply ./internal/governance '^TestChannelMigrationAfterReapply$' '-migration=server/migrations/648_cr_execution_control.down.sql' '-migration=server/migrations/648_cr_execution_control.up.sql'
# RED 独立运行示例：仅在 S6 对应 mutation 已应用后取消下一行注释；恢复代码后用新 nonce 跑 green。
# RED_TEST='TestChannelIngestRevokedPermit/revoked_permit_effect' RED_ASSERTION='CONTROL_REVOKED_PERMIT_EFFECT' rungo red revoked-head ./internal/governance '^TestChannelIngestRevokedPermit$'
```
- P0 另在获授权的 Linux 测试机、批准 profile 和对应 source/evidence 根中单独运行 `runnode green isolation ./test/execution-control-isolation.test.mjs`、`rungo green isolation ./internal/daemon '^TestChannelIsolation`。模板内的 Windows 路径不能冒称 Linux 实跑；profile 必须绑定真实两个 UID、受审核 launcher、私有根与 pin，环境未获批准则 P0 未执行，不能以组件 PASS 替代。`。模板内的 Windows 路径不能冒称 Linux 实跑；profile 必须绑定真实两个 UID、受审核 launcher、私有根与 pin，环境未获批准则 P0 未执行，不能以组件 PASS 替代。 v0.4：daemon 隔离顶层固定为 `TestChannelIsolation`（精确锚定），label `isolation` 同样进 EXPECT 名单；缺 profile 必须 `t.Fatalf`，不得裸 `return`。
- 生命周期专例每次独占新库；普通回归的正则不选择 `TestChannelMigration…`，防止 down 后缺表混成业务失败；不得在保留库或含真实审计的库执行 down。
- Go 仅使用上述既有白名单包，runner 自带 180s，不重复 timeout；migration up/down、immutable triggers、冲突、删除分类测试放这些包内，不放宽 whitelist。
- 单执行者逐条运行；每次检查原库 unchanged、无残留 session/advisory lock、临时 DB/role cleanup、非零非 skipped leaf。RED 预期 runner 非零，需独立记录；不得把编译失败/无匹配当业务 RED。
- mutation 在未来获授权的可丢弃 worktree 中逐个执行、逐个恢复核 hash；保存 baseline/source manifest、实际 argv、迁移摘要与业务断言，不把事后 manifest 冒称既有运行时 freeze。

## 修订记录
| 版本 | 内容与效力 |
|---|---|
| v0.1（历史单独文件） | 早期方案及 BLOCK 留作历史，不能用于实施。 |
| v0.2（本文件上一版） | Foundation、可信 commit/恢复协议与组件验收；旧三路结论仅覆盖当时方案，随后用户决定搁置。 |
| v0.3（2026-10-26） | 按用户 D8=A 明确不迁移存量/不借新 lineage 清零；按 D7 转交通道的决定新增 Spec §7 + S8 独立就绪控制面；原位更新 13 表清单、锁序、测试选择器、追踪与边界。仍未注册/未实施，不继承旧批准。 |
| v0.4（2026-10-26） | 并入 Gate3 待办 B 中依赖可信 T 裁决、受保护 store 或持久 selection 的项：Spec §1 selection 不可降级（legacy 须由可信目录证明）；§2 repair 追加授权新域与 CAS；§3 repair-admit 验签、sensitive 账本（额度/幂等键分离、旧账本连续、M settlement 线性化）；§6 终态 fence 持久单调事实并集；P0 F1 改为 daemon 自填事实 + 私有 socket + pidfd；S1/S3/S5/S6/S7 子例与 mutation 一一对应（挂在既有精确锚定的顶层用例下）；补 service `TestChannelTaskTx` 归属与 revoked-permit 独立 label；验收证据检查列出 v0.4 必达 leaf。初稿 strong BLOCK、balanced/economy INCOMPLETE，按其 findings 补正，见 `trusted-verdict-channel-v04-review-20261026.md`。仍搁置、未注册；补正后内容未经再复核不得称已批准。 |
| v0.5（2026-10-26） | 用户采纳 B11 挂接建议：Spec §3 新增 merge 范围核对。初版经 balanced/economy 两路复核判 INCOMPLETE 后修订：三项输入的权威来源逐条钉死（selection 读 M 持久事实、grant 读 M 当前 head、改动集合读 M 持久 code 批准记录且 `approval.yml` 仅作投影）；核对集合改为 `trunk...HEAD`（= 发布集合）；补失败码闭集、零写入精确外延、与 `verifyReleaseSubjects` 的顺序、复用边界（规则复用/收集新写）、X7 字段语义修正（repo id + 路径前缀同时给）；S5 leaf/mutation 由 6:5 补到 **17 leaf / 16 mutation（含两处显式不对称，见“v0.5 必达 leaf”）**。AIFI-45 侧只读自检命令与 implement-code 自检步骤已交付（非强制闸门）。**第二次三路复核仍全 BLOCK**（发布语义 (a)/(b) 未选、可信 merge facts 端点未定义、撤销线性化未闭合、leaf 清单仍写“十条”），结论见 `V/v05-rerun-20261026T235224Z/CLOSEOUT.md`；本行为当时的修订记录，闭合状态以该 CLOSEOUT 为准。 |
| v0.5 二轮（2026-10-26） | strong 复核判 BLOCK/INCOMPLETE 后修订：核对对象必须等于实际发布对象（`mergeCr` 冻结的是远端 ref==HEAD，不是批准 SHA；KB 允许批准 SHA 为 HEAD 祖先）；插入点改为 `cmdMerge` 现有 gate **之前**的独立只读预检（现有 gate 的 approval 分支会写 outbox，非零副作用；锁/journal/recoverWriteSet 也早于 release-subjects 读取）；补授权效力线性化边界与部分发布后处置；空集合不得放行 + 采集完整性四证明；SHA 采集适配（rename 双向、symlink 取自树、无损分隔）；Legacy 口径收窄为可信目录证明；X7 补合法恢复流程；归属划分（采集器通用缺陷归 AIFI-45 就地修）。S5 leaf/mutation 再扩充。**修订后仍未复核。** |
| v0.6（2026-10-26） | **R1 由用户决定为 (a)：核对对象 = merge 实际发布的候选写集**。(b) 不采纳（与“KB 允许批准 SHA 为祖先”冲突，会大面积误拒）。据此补五条约束：核对区间取该仓实际候选 source；批准事实来自 M、**实际候选 HEAD 由预检写入 journal/receipt**，二者是“批准为区间内已存在且未撤销的下界”而非相等；KB 审批后写入属核对范围；finalize 三个生成路径（`cr.md`/`merge-commits.yml`/`merge-verification.md`）必须逐项出现在 `allowed_paths`，漏列即拒、无暗设豁免；rename/symlink/删除按选定提交树判定。S5 必达 leaf 由 17 增至 **19**（新增 `merge 范围 finalize 写集逐项授权`、`merge 范围核对含 KB 审批后写入`），`merge 范围 symlink 取自批准树` 改写为 `…取自发布候选树`（按 tree/blob 判定，两条 mutation）。同轮另修 R4（删“十条/10:10”，改逐个枚举+显式不对称）与 R7（S1 增 G5 前置、S6 前置改 B1/B2/B3+G1+G2/G4），并给出 R2/R3 合同草案。**R1 已决不等于方案通过：R2/R3 草案未经复核，三路 BLOCK 其余项未闭合。** |
| v0.6.1（2026-10-26） | r2r3 复核（R2 三路 BLOCK、R3 strong BLOCK/balanced INCOMPLETE）后**整节改写而非追加**：用户采纳 `merge-facts` 端点随本 change 交付、删除 `workspace_revision`、残余风险入册。R2：存储改追加写 + 部分唯一索引（每仓至多一条当前行），语义固定为祖先下界；workspace 由认证主体解析；响应加 `expected_repo_count`/`repos_digest`/`current_binding` 三态/`provenance_digest`；失败码分层表成为唯一权威（§3 改为引用），优先级 UNAVAILABLE>REVOKED>HEAD_MOVED>VIOLATION>UNVERIFIABLE。R3：沿用 §4 已定 effect 语义，每次 push（含 finalize）复用 command/settlement（`effect_kind=merge_publish`），以 `merge-effects reserve` 提交为授权排序点、push 在 Tx 外、report 为远端确认点；journal 三态与远端只读核实三分支；不新增 CR 状态；恢复矩阵与 `input_digest`。§4 表 13→14，§6 端点 3→5。**仍为作者稿、未复核。** |
| v0.6.2（2026-10-26） | v0.6.1 复核（strong R2 PASS/R3 BLOCK；balanced R2/R3 INCOMPLETE；economy R2 BLOCK/R3 INCOMPLETE）后单点修订：表名统一（DB 全名 `cr_execution_code_source_freeze`、§4 只列后缀、`ChannelTableNames` 登记全名）；撤销提交点唯一谓词＝当前冻结行 `revoked_at IS NOT NULL` 可见；`current_binding`/`head_revoked`/`provenance_digest` 判据；R2.4 补本地下界校验行、子码说明、403 归口、优先级措辞；R3 补 reserve attempt 语义与 merge-effects 码序（含 NOT_FOUND）、push 前先持久 `unknown`、状态×远端恢复表（`unknown`+prev 保持 uncertain、`confirmed`+prev 判改写）、halted reason 扩展与映射；R2.5/R3.5 各增 2 条至 11 条。仍未复核。 |
| v0.6.3（2026-10-26） | v0.6.2 复核（strong R2 PASS/R3 BLOCK；economy R2 PASS/R3 BLOCK；balanced R2 INCOMPLETE/R3 BLOCK）后单点修订：R3.2 远端分类改按祖先关系（与 `classifyRemoteCommit` 一致，远端正常前进不判改写），补服务端 `settled_no_effect` 终态格并定“服务端终态优先”；码序补 `INVALID` 并把 `UNTRUSTED` 置于 `NOT_FOUND` 前；reserve 非授权类失败不写 halted；base_drift 由 CLI 逐项比对判定、publish_failed 排除 not_attempted；部分唯一索引写明列；R2.4 拆分 404 行并写明 grant 派生字段每次重读；R2.5 逐条给 mutation 与总则（11 条），R3.5 消除 #5/#10 互斥并补 attempt、head 先判、认证归属码序、no_effect 终态、正常前进共 16 条。仍未复核。 |
| v0.6.4（2026-10-26） | v0.6.3 复核（strong R2/R3 PASS；economy R2/R3 PASS；balanced R2 INCOMPLETE/R3 BLOCK）后 leaf 级单点修订：R2.5 #4 补严格祖先正例与区间负例、#1 限合法 MDT 并改 mutation；R3.1 attempt 三情形互斥；R3.2 首行改为服务端 `settled_effect` 并写明 `confirmed` 无终态→uncertain；R3.5 #7 只改 base、#9 只改非 base 分量（消除互斥），#13 三支互斥，#15 补 503 支。leaf 数不变（11+16）。仍未复核。 |
| v0.6.5（2026-10-26） | v0.6.4 复核（strong R2/R3 PASS；economy R2/R3 PASS；balanced R2 INCOMPLETE/R3 PASS）后修订：R2.5 #5 补“同计数替换 repo_id”支（唯一实质缺口）；nit 一并收：#1/#2 补 CLI 外层码，`head_revoked` 定为全部当前行已撤销、部分撤销归事实不一致，R3.1/#13 补“前 attempt 已 settled_effect → 200 原 mapping”，R3.4 部分发布格拆 base_drift/input_mismatch，#9 夹具限只改候选 HEAD，#13 写明 reason 记在 journal，#15 写明 400 只断端点，§7 生命周期测试 13→14。leaf 数不变（11+16）。仍未复核。 |
- v0.3 轮只做文档静态校验和独立计划复核，结果另记 `trusted-verdict-channel-v03-review-20261026.md`；v0.4 轮同样只做静态校验与三路非作者计划复核，结果另记 `trusted-verdict-channel-v04-review-20261026.md`。均不冒称动态测试或部署验证。

## Review Focus
| strong finding | v0.3 + v0.4 必核闭合点（历史批准不覆盖新增项） |
|---|---|
| 隔离未证明 | P0 真实身份正对照先行；失败停止 C，B 另设计。 |
| 冷启动循环 | exact-key control/task union；reservation 不可执行；643–645 延至实际交付、启动前。 |
| change 依赖循环 | Channel 自有 S1→core→reader 真实验收；完整 AIFI45 集成仅为下游。 |
| 重投签名字节漂移 | 首次 commit 冻结 envelope/key/seq/prev/replayed；只重发原 bytes。 |
| restart/rollback | M monotonic fence、checkpoint/journal/open reconcile；异常 freeze、不重置额度。 |
| revoke/stop/slot | current-head 同 Tx、revoke 不等 slot、stop 按序、unknown 冻结、显式 no_effect。 |
| key-purpose | 独立 command key，签发与验签双侧 purpose/domain/scope，attestation 不得签 human。 |
| selection/replay | 持久可信 selection、Channel-owned fence；settled 仅旧 effect、未 settled 仅原 candidate。 |
| D7 伪就绪/缺成员 | 非空 operator-pinned profile + 全副本/安装 inventory + 可信 observer；T 唯一求值，Go 不重写版本规则。 |
| D7 TOCTOU/回退 | deployment→activation 外层锁、每次 effect/start 重验、120 秒上界非唯一保护；STOP_NEW 仅精确恢复，不降 legacy、不清 slot/history。 |
| D7 验收循环/退役 | component 正例与 strict 缺 decider 反例独立交付；生产 strict 另验，旧 run/未决结果阻止删除旧接力。 |
| D8 范围越权 | 不迁移不是永久删正分支或 TC PASS；新 lineage 不能清旧债，Canonical/计数/Gate 不自动改变。 |
| B4/B12b strict 降级 | Strict 持久化后删 trigger/`cr.md` 字段只能拒绝；legacy 须由可信历史目录证明，缺行/读失败按 Unknown 拒绝。 |
| B5/B6 repair/sensitive | repair 额度只来自验签 grant 并绑定 fact_refs；sensitive 额度键与幂等键分离、grant 不是额度桶、旧账本连续；当前 head/撤销在 M settlement 线性化，T commit 不等于获准。 |
| B7 F1 | 进程事实由 daemon 按 launch 登记自填，私有 socket + pidfd 进程树；peer credential 只作辅助，主控制仍是 P0 身份隔离；Windows 属 strict（X1 已决），P0 须补 Windows 身份证明。 |
| B3 终态 fence | `fence_required` 持久单调（任一 generation 已消费 ∨ Strict 下创建），与 AIFI-45 过渡取并集；重领不清除，终态 Tx 持行锁判定，读失败即拒。 |
| B8/B9 | adoption/terminal 用 `55P03` 锁探针而非结局计数；帧链只防篡改，追加授权走 §2 新域 + CAS，双追加只接受一份。 |
| B11 merge 范围（v0.5 修订版） | 三项输入不得由调用方参数或 agent 可写文件单独决定；改动集合的权威来源是 M 持久 code 批准记录（`approval.yml` 仅投影，逐字段相等）；核对区间 = 发布区间 `trunk...HEAD`；越界在 `mergeCr` prepare 前拒，零写入外延为“不建 journal/publish/不推状态/不写 receipt”（既有 audit/gate 不在内）；规则复用 `evaluateChangeScope`、收集新写；X7 已决：签发侧须同时给 repo id 与路径前缀，仓库集合不经 repair 追加域扩展。 |
| 范围外但须先行 | B1 签发/消费绑定完整 generation、B2 统一锁图（CR-bind↔消费成环）、B3 终态 CAS 后同事务 fence 是 S6 green 的前置；但 S6 的 `claim_terminated_before_consume` 还需 **G1**（三写端点共用校验事务 + 锁 task/runtime 归属行）与 **G2/G4 残余**，S1 的 `root_adoption_terminal_race` 还需 **G5**（root 行锁 + generation CAS）——两者都归 AIFI-45，未修则对应 leaf 按设计 RED（v0.5 复核更正：先把 B8 一律并入本方案的旧表述作废，B8 中**不需要可信事实**的那半在 AIFI-45）。B11 只读自检命令与 implement-code 自检步骤（已交付，增量 25/26；逃逸判定已按增量 33/34 加固）、B12a EVD-005 报告/收集接线、B16 RPR 业务身份规则、EVD-001/002/004 gate 接线归 AIFI-45；B10 见 S5 既有 resume；B14/B15 见 Goal。 |
- 用户已定：D8=A 不迁移存量；D7 由 Channel 拥有。人类环境确认仍包括首期 Linux 身份/launcher/observer/全部实例与安装目标的操作授权、独立 keys 管理及受保护 required profile；不能把“已决定范围”理解为部署身份/能力已经核实。
- 主要残余风险：merge 范围核对只保证事实可信、不保证执行强制（持 push 权限者可绕过 CLI；仓库侧强制闸门不在本 change，见 R2.6）；隔离部署复杂、严格冻结降低可用性、审计增长/磁盘耗尽、review/test 内容真实性上限、外部 action 结果未知；容量不足 fail-closed，不能自动删审计或补签历史。
- 最终验收需非作者独立复核；本文不授予 Gate、commit/push、建用户、系统权限变更或部署授权。

## v0.6 修订草案（2026-10-26，回应第二轮复核 R1/R2/R3；R2/R3 已按 r2r3 复核 Q1–Q13 合并为 v0.6.1 合同稿；**未复核，不得称已批准**）

本轮只修 R4/R7 与记录性错误（已落盘）。以下三项是设计层：R2/R3 给出可评审合同草案，**R1 仍需人类决策**，本文不代选。

### R2（原 STR-02/E07）：可信 merge facts 合同（v0.6.1 合并稿：回应 r2r3 复核 Q1–Q8）

**交付面已定（2026-10-26，用户采纳）**：`merge-facts` 只读端点**随本 change 交付**；删除 `workspace_revision` 参数。理由与边界：merge 发布只在 tools 执行（`workspace-transactions.mjs::mergeCr`，multica 无对应代码），需要可信事实的一方就是 CLI，“M 内部调用”不成立。

**R2.1 存储（Q2/Q7）**：§4 新增第 14 张表——DB 对象全名 `cr_execution_code_source_freeze`；§4 表格按表头约定只写后缀 `code_source_freeze`；`ChannelTableNames` 一律登记 DB 全名（列 `workspace_id,cr_id,repo_id,approved_source_sha,approved_revision,approval_record_id,authorization_head_id,approved_at,superseded_at,revoked_at,digest`）。
- **追加写**：只由 code 批准事务写入；同 `(workspace_id,cr_id,repo_id)` 再批准时，在同一事务内 `FOR UPDATE` 锁当前行、置 `superseded_at` 并插入 `approved_revision+1`。约束 `UNIQUE(workspace_id,cr_id,repo_id,approved_revision)` 加部分唯一索引 `UNIQUE(workspace_id,cr_id,repo_id) WHERE superseded_at IS NULL`，保证**任一时刻每仓至多一条当前行**；多条或零条当前行均视为事实缺失。
- **语义固定为“祖先下界”**（R1=(a)，不设 `bound_kind`）：合法当且仅当 `approved_source_sha` 是该仓实际候选 HEAD 的祖先（含相等），且位于 `trunk...<candidate HEAD>` 区间内。表**不存**实际候选 HEAD（它由本地预检写入 journal/receipt，仅为本地审计事实，不是授权凭据）。
- 撤销：授权 head 撤销时同事务置该 CR 全部当前行 `revoked_at`；不删除、不改写历史行。**撤销提交点的唯一可观测标识 = 该 CR 当前冻结行 `revoked_at IS NOT NULL` 在另一连接可见**；R2.3 的 `head_revoked`、R3.1 的排序与夹具均只认这一谓词。head 前移（`cr.execution_authorization_head_id` 改变）是另一事实，对应 `HEAD_MOVED`，不与撤销混用。

**R2.2 端点与认证（Q4/Q8）**：`GET /api/daemon/execution-control/merge-facts/{crID}`。
- 认证沿用 §6 既有主体（MDT + enrolled key/owner scope），拒绝 PAT/JWT/task-token 回退。
- **workspace 由服务端从已认证主体的绑定解析**；请求只携带 `crID`。`crID` 不属于该 workspace → `404 MERGE_FACTS_NOT_FOUND`。不接受 `--workspace`/`--grant`/revision 等任何调用方提供的目标或版本参数。
- 当前授权 = `cr.execution_authorization_head_id` 指向的已验签 grant；`expected_repo_count` 与仓库集合的权威 = 该 grant 的 `allowed_repositories`。

**R2.3 响应闭集（Q3/Q6）**：单个 REPEATABLE READ 读事务内产出，未知字段拒收：
`{cr_id, workspace_id, selection_kind: strict|legacy_proven, provenance_digest, authorization_head_id, grant_digest, head_revoked, read_at, expected_repo_count, repos_digest, repos:[{repo_id, identity_digest, current_binding: ok|mismatch|unknown, approved_source_sha, approved_revision, freeze_revoked}]}`
- `provenance_digest` 在 `selection_kind=legacy_proven` 时必填，否则必须缺省；缺失或与可信目录证明不符一律按事实缺失处理（不降 legacy）。
- `repos_digest = sha256(按 repo_id 排序后逐项 repo_id‖identity_digest‖approved_source_sha‖approved_revision)`；CLI 必须校验 `len(repos)==expected_repo_count`、repo_id 唯一且集合等于 grant 的 `allowed_repositories`、摘要自洽。
- `repos_digest` 只证明集合完整与授权事实；`current_binding`、`freeze_revoked` 等易变字段不入摘要，按 R2.4 单独判定。
- `current_binding` 生成判据（同一读事务内按 repo_id 读）：无当前绑定行或身份摘要不可得 → `unknown`；绑定行身份摘要 ≠ grant `repository_bindings` 冻结身份 → `mismatch`；相等 → `ok`。
- `head_revoked` := 该 CR 全部当前冻结行 `revoked_at IS NOT NULL`（见 R2.1 唯一谓词；撤销事务同时写全部当前行）。仅部分仓 `freeze_revoked` 属事实不一致，按 R2.4 归 UNVERIFIABLE。
- `provenance_digest` := 可信历史目录证明记录（§1 legacy 证明）规范化原始字节的 SHA256；CLI 以同一记录比对，不接受自报。
- 只返回批准下界与当前 head，**不返回也不接受**调用方提供的实际候选 HEAD。

**R2.4 失败码分层（Q1/Q5，唯一权威；§3 失败码闭集引用本表）**：

| 条件 | 端点返回 | CLI 外层码 |
|---|---|---|
| 连接失败/超时/5xx/`503 MERGE_FACTS_UNAVAILABLE`；`403 MERGE_FACTS_UNTRUSTED`（含 PAT/JWT/task-token 一律 403）；`400 MERGE_FACTS_INVALID`；未知 code | 非 200 | `EXECUTION_AUTHORIZATION_UNAVAILABLE` |
| `head_revoked=true` | 200 | `EXECUTION_AUTHORIZATION_REVOKED` |
| 预检冻结的 `authorization_head_id` 与重读值不同 | 200 | `EXECUTION_AUTHORIZATION_HEAD_MOVED` |
| 本地 findings 非空（越界路径、`current_binding=mismatch` → finding 子码 `AUTH_SCOPE_REPOSITORY_IDENTITY_MISMATCH` 等；子码不是新外层码） | 200 | `AUTH_SCOPE_VIOLATION` |
| CLI 侧本地下界校验失败：`approved_source_sha` 不是候选 HEAD 的祖先或不在 `trunk...<candidate HEAD>` 内（端点看不到候选 HEAD，只能 CLI 判） | 200 | `AUTH_SCOPE_UNVERIFIABLE` |
| `404 MERGE_FACTS_NOT_FOUND`（仅 crID 不属于主体 workspace） | 404 | `AUTH_SCOPE_UNVERIFIABLE` |
| 任一仓无当前冻结行，或仅部分仓 `freeze_revoked`（事实不一致）；计数/集合/摘要不符；`current_binding=unknown`；`provenance_digest` 缺失或与目录记录不符；本地采集 problems | 200（端点如实返回事实，判定在 CLI） | `AUTH_SCOPE_UNVERIFIABLE` |

**优先级**：`UNAVAILABLE` > `REVOKED` > `HEAD_MOVED` > `VIOLATION` > `UNVERIFIABLE`。已知越界在与 `UNVERIFIABLE` 并存时输出 `VIOLATION`，不得降级；端点不可达时 grant 不可得、本地无法计算越界，故不存在 `UNAVAILABLE` 与 `VIOLATION` 并存的情形；该前提要求 grant 派生字段（`allowed_repositories`、`allowed_paths` 等）**每次核对都从端点重读**，journal 只记其摘要供审计与 `input_digest`，不作为授权来源（与现 `crctl.mjs:1883–1884` 先 findings 后 problems 一致）。所有码退出非零、CR 状态保持 `code-approved`。

**R2.5 必达 leaf（随本节冻结进入 `channel-test-expectations.json`；共 11 条）**：除另注外，leaf 5–7 只断 CLI 外层码，端点侧只断 R2.4 所列 status。
1. `merge-facts 只按认证主体解析 workspace`：合法 MDT 凭据 + 他人 crID → 404 NOT_FOUND，CLI 外层 `AUTH_SCOPE_UNVERIFIABLE`。mutation：按 CR 行的 workspace 返回、跳过与认证主体的比对。
2. `merge-facts 拒绝 PAT/JWT/task-token`：三类凭据 → 403 UNTRUSTED，CLI 外层 `EXECUTION_AUTHORIZATION_UNAVAILABLE`。mutation：接受任一回退凭据。
3. `merge-facts 当前冻结行唯一`：同仓插入 `approved_revision+1` 且不 supersede 旧行 → 被部分唯一索引拒。mutation：删除该部分唯一索引。
4. `merge-facts 批准下界须为候选祖先`：正例——`approved_source_sha` 为候选 HEAD 的严格祖先（候选在其后又有提交）→ 放行；负例——非祖先 → UNVERIFIABLE；是祖先但不在 `trunk...<candidate HEAD>` 内（已是 trunk 的祖先）→ UNVERIFIABLE。mutation：改为精确相等（正例 RED）、不校验（负例 RED）、不校验区间（区间负例 RED）。
5. `merge-facts 仓库集合与 grant 精确相等`：漏一仓/多一仓、摘要不符、同计数但替换一个 repo_id（摘要按替换后集合自洽）各一支 → UNVERIFIABLE。mutation：跳过集合比较（替换支 RED）、只比计数不校摘要（摘要不符支 RED）。
6. `merge-facts current_binding 三态`：mismatch → VIOLATION，unknown → UNVERIFIABLE。mutation：unknown 当 ok。
7. `merge-facts legacy 证明缺失或不符即拒`：缺失、与目录记录不符各一支 → UNVERIFIABLE。mutation：以响应自报 `provenance_digest` 为准、不比对目录记录。
8. `merge-facts 失败码优先级`：越界 + 不可核实同时存在 → VIOLATION。mutation：先判 problems。
9. `merge-facts 不可用即 UNAVAILABLE`：不可达/超时/5xx/400/未知 code 各一支 → UNAVAILABLE。mutation：任一支当 UNVERIFIABLE 或放行。
10. `merge-facts 撤销即 REVOKED`：当前冻结行 `revoked_at` 非空 → REVOKED。mutation：忽略 `head_revoked`。
11. `merge-facts head 前移即 HEAD_MOVED`：预检冻结 head 与重读不同 → HEAD_MOVED。mutation：不重读 head。
- 总则：每条 mutation 使对应 leaf 断言失败（AssertionError 或等价断言）；超时、连接错、编译错、夹具错、崩溃不计为 RED。

**R2.6 残余风险（不得冒称）**：端点只保证**事实可信**，不保证**执行强制**——CLI 运行在 agent 控制的主机上，持有 push 权限者可以不调用端点直接推送。真正不可绕过的闸门在仓库侧（例如分支保护要求 M 签发的状态检查），**不在本 change 范围**；端点交付后也不得表述为“merge 已强制”。

### R3（原 STR-03）：撤销与实际发布的线性化（v0.6.1 合并稿：回应 Q9–Q13）

**原则**：直接沿用 §4 已定语义（effect 线性化点 = caller Tx commit；revoke 先提交 → 旧 permit 只能 no_effect；effect 先提交 → revoke 不追溯；结果未知进入 `uncertain`）。每次远端 push（含 finalize push）是一个独立 effect，复用 §4 的 command/settlement 状态机，`effect_kind='merge_publish'`、`effect_ref={repo_id, ref, expected_sha, prev_sha}`，**不新增表**。

**R3.1 三个时点分离（Q9/Q13）**：
1. **授权排序点** = `POST /api/daemon/crs/{crID}/merge-effects`（`op=reserve`）事务提交。该事务按 §4 锁序取 CR 行（`FOR SHARE`）与授权 head，**同事务**重验当前 head、`head_revoked`、当前冻结行与预检冻结的 `input_digest`，写入 issued command。撤销走既有 CR 锁路径（`FOR UPDATE`），因此撤销与 reserve 由行锁串行（不等待 command slot，只等行锁）。
2. 事务提交、释放 DB 连接后，CLI 才执行 push（Tx 内不调用网络）。
- **reserve 语义**：同一 `effect_id` 的每次尝试带单调 `attempt`。四种情形互斥：同 attempt 原字节重放 → `200` 返回原结果；前 attempt 已 `settled_effect` 时的新 attempt → `200` 返回原 effect mapping、不新建 command（与 §6“重复 settled 仅返回原 mapping”一致）；新 attempt 且无未终结的前 attempt → 服务端完整重验后 `201` 新 command；新 attempt 但前 attempt 未终结（issued/uncertain）→ `409 MERGE_EFFECT_CONFLICT`。
- **merge-effects 码序**（merge-facts 的非 200 码同序）：`INVALID`（解析层先判）> `UNTRUSTED`（认证先于资源查找，故 PAT + 他人 crID 恒 403）> `NOT_FOUND`（crID 不属于主体 workspace）> `REVOKED` > `HEAD_MOVED` > `INPUT_MISMATCH` > `CONFLICT` > `UNAVAILABLE`。服务端先判撤销与 head，再比对 `input_digest`，因此 head 前移恒报 `HEAD_MOVED` 而不是被 `INPUT_MISMATCH` 遮盖。
3. **远端确认点** = push 返回后 `op=report`：成功 → `settled_effect`；失败可判定未发布 → `settled_no_effect`；无法判定 → `uncertain`。
- **撤销提交点的可观测标识**：只认 R2.1 唯一谓词（当前冻结行 `revoked_at IS NOT NULL` 在另一连接可见）；head 前移另以 `cr.execution_authorization_head_id` 改变判 `HEAD_MOVED`。测试夹具在 reserve 事务的 `after-head-read` 钩位持有，另一连接以 `lock_timeout` 尝试撤销，只认 `55P03`；再各跑一支“撤销先提交”“reserve 先提交”的顺序用例。
- **排序结论**：reserve 先提交 → 该 effect 已获授权，随后的撤销不追溯，push 可完成；撤销先提交 → reserve 返回 `REVOKED`，零 effect。“此前失败=零 effect”只指**当前**仓，不抹去之前已 settled 的仓。

**R3.2 journal 事实分级与恢复判定（Q10）**：本地 journal 按 effect 持久三态，且**在发出 push 之前**先把状态写成 `unknown`：`intent`（reserve 已提交、push 从未发出）/`unknown`（push 已发出或可能在途、结果未记）/`confirmed`（已 report `settled_effect`）。恢复时先结合 journal 与服务端 command 终态，再只读核实远端（`git ls-remote <repo> <ref>`）：

远端分类以祖先关系为准（与 `workspace-transactions.mjs::classifyRemoteCommit` 一致）：**含 expected** = `git merge-base --is-ancestor <expected_sha> <remote>` 成立（含相等）；**== prev** = 远端等于 `prev_sha` 且不含 expected；**其他** = 不含 expected 且 ≠ prev，或祖先关系因对象缺失等原因无法证明。服务端 command 终态优先于本地 journal 状态；journal `confirmed` 而服务端无终态属事实不一致，一律 `uncertain`、转人工。

| 服务端终态 / journal 状态 | 含 expected | == prev | 其他 |
|---|---|---|---|
| 服务端 `settled_effect`（journal `confirmed`，或 report 成功后崩溃停在 `unknown`） | 无动作（远端正常前进也属此格） | 证实已不含：**history rewrite**，`uncertain`、冻结、转人工，不重推 | `uncertain`、转人工（不直接称改写） |
| `settled_no_effect`（push 确定失败后已结算；journal 可能停在 `unknown`） | 冲突：`uncertain`、转人工 | 旧 attempt 已由服务端终结：以 `attempt+1` 重新 reserve（服务端完整重验；已撤销则 `REVOKED`，不 push） | `uncertain`、转人工 |
| 无终态 + journal `unknown`（push 可能在途） | `report settled_effect`（幂等） | **保持 `uncertain`**：旧 push 可能延迟完成；仅观察到 prev 不构成终止证据，不得重推、不得结算 `no_effect` | `uncertain`、转人工 |
| 无终态 + journal `intent`（push 从未发出） | 异常：`uncertain`、转人工 | 先 `report settled_no_effect(reason=not_attempted)` 终结旧 attempt，再以 `attempt+1` 重新 reserve | `uncertain`、转人工 |

- `unknown`/`uncertain` 状态下**禁止发起任何新 publish**；确认旧 effect 不授权后续 effect；finalize push 同样适用本表。

**R3.3 中止与人工出口（Q11）**：不新增 CR 状态机状态（状态机唯一事实源在 tools `dir-graph.yaml`，本方案不改）。中止时 CR 保持 `code-approved`；journal 记 `halted:{at_effect, reason ∈ revoked|head_moved|base_drift|input_mismatch|publish_failed|uncertain}`（映射：reserve `REVOKED`→revoked；`HEAD_MOVED`→head_moved；`INPUT_MISMATCH` 时由 CLI 逐项比对 journal 中的预检分量与当前分量，仅 base 不同→base_drift，其余→input_mismatch；push 可判定失败并 report `settled_no_effect`（`not_attempted` 除外）→publish_failed；R3.2 表中 `uncertain` 各格与 reserve `CONFLICT`→uncertain）；reserve 返回 `INVALID`/`UNTRUSTED`/`NOT_FOUND`/`UNAVAILABLE` 时**不写 halted**、非零退出、journal 保持原状态（未发 push，可修正后重入）；receipt 不改写；对应 command 停在原状态或 `uncertain`。唯一自动入口为既有恢复路径（`crctl merge` 重入 → `recoverWriteSet`），且 `input_digest` 不同即拒；放弃/改写历史须人类按既有恢复流程处理，本方案不新增 abort 命令。

**R3.4 恢复矩阵与输入同一性（Q12）**：`input_digest = sha256(trunk ‖ 每仓 base_sha ‖ 每仓 candidate HEAD ‖ selection_kind ‖ 按 repo_id 排序的 (approved_source_sha, approved_revision) ‖ authorization_head_id ‖ grant_digest)`，预检时写入 journal，reserve 时服务端比对。
| 状态 | base/输入变化 | 撤销 | 新授权 |
|---|---|---|---|
| 零发布 | 拒，journal 可按既有恢复放弃后以新事务重来（无 effect 可被洗白） | 拒 | 只能用于新事务 |
| 部分发布 | base 不同 → `halted: base_drift`，其余输入变化 → `halted: input_mismatch`；转人工，**不得**换 base 续跑 | 已 settled 的仓不追溯，后续仓停 | **不得**续旧 journal |
| 全部发布、finalize 待发 | finalize push 同样 reserve/report；finalize rebuild 导致输入变化 → `halted`，转人工 | finalize reserve 返回 REVOKED，不推 | 不得续旧 journal |

**R3.5 必达 leaf（随本节冻结；共 16 条）**：
1. `merge-effect reserve 持 CR 共享锁`：`55P03` 探针。mutation：去掉 `FOR SHARE`。
2. `merge-effect 撤销先提交则零 effect`：reserve → REVOKED，无 push。mutation：reserve 不重验撤销谓词。
3. `merge-effect reserve 先提交则撤销不追溯`：随后 push 完成并 `settled_effect`。mutation：push 前再次以撤销为由拒绝。
4. `merge-effect 远端含 expected 不重推`：journal `unknown` + 远端等于 expected 或其后继 → `settled_effect`，无 push。mutation：只认精确相等或重推。
5. `merge-effect intent 且远端未变须重新 reserve`（限 journal `intent`）：先 not_attempted 结算，再 attempt+1。mutation：直接 push 不重新 reserve。
6. `merge-effect 远端分叉进入 uncertain 且禁止新 publish`。mutation：分叉后继续后续 effect。
7. `merge-effect 部分发布后 base 漂移即 halted`（夹具只改 base，其余分量不变）：断言 `INPUT_MISMATCH` 与 `reason=base_drift`。mutation：换 base 续跑，或不做逐项比对一律记 input_mismatch。
8. `merge-effect finalize 也须 reserve`。mutation：finalize push 跳过 reserve。
9. `merge-effect 非 base 输入变化拒绝恢复`（夹具 base 与授权 head 均不变，只改候选 HEAD）：断言 `INPUT_MISMATCH` 与 `reason=input_mismatch`。mutation：不比对摘要。
10. `merge-effect 旧 push 延迟完成不得误判零 effect`（限 journal `unknown`、无服务端终态）：远端仍为 prev → 保持 uncertain。mutation：按 prev 结算 no_effect 或重推。
11. `merge-effect 已确认后回退至 prev 判为改写`：`confirmed` + 远端 prev → uncertain，不重推。mutation：允许重新 reserve。
12. `merge-effect 服务端 no_effect 终态后以新 attempt 恢复`：`settled_no_effect` + journal `unknown` + 远端 prev → attempt+1 reserve。mutation：仍按无终态保持 uncertain，或复用旧 attempt。
13. `merge-effect attempt 语义`（四支互斥）：同 attempt 原字节重放 → 200 原结果；前 attempt 已 `settled_effect` 的新 attempt → 200 原 mapping、无新 command；无未终结前 attempt 的新 attempt → 201；前 attempt 未终结时的新 attempt → 409 CONFLICT，且 CLI 在 journal 记 `halted.reason=uncertain`（409 body 不含 reason）。mutation：重放返回 201、已 settled 仍新建 command，或允许并行 attempt。
14. `merge-effect 先判 head 再比摘要`：head 前移且摘要也不同 → HEAD_MOVED。mutation：先比 `input_digest`。
15. `merge-effect 认证与归属码序及非授权失败`：畸形请求 → 400 INVALID；PAT + 他人 crID → 403 UNTRUSTED；合法凭据 + 他人 crID → 404 NOT_FOUND；服务端不可用 → 503 UNAVAILABLE；四者均不写 halted、journal 不变（400 支为端点直调，只断端点 status）。mutation：先查 crID 再认证，或任一支写 halted。
16. `merge-effect 远端正常前进不判改写`：`confirmed` + 远端为 expected 的后继 → 无动作。mutation：以精确相等判定。
- 总则：每条 mutation 使对应 leaf 断言失败；超时、连接错、编译错、夹具错、崩溃不计为 RED。

### R1（原 STR-01）：已由用户决定为 (a)（决策记录，不再重开）

- **(a) 覆盖真实候选写集**（推荐）：核对对象 = merge 实际将发布的 source 区间 + KB 审批后写入 + finalize 生成写集（`cr.md`/`merge-commits.yml`/`merge-verification.md`）。需要为“批准后实际 source HEAD”建立独立冻结绑定（R2 §1 只冻结“批准下界”；实际候选区间与 HEAD 由本地预检写入 journal/receipt，不写进该表），finalize 生成路径必须显式列入 `allowed_paths`，无暗设豁免。
- **(b) 仅批准 SHA**：禁止 KB 审批后提交与 tree-相等放行，并须另行规定 finalize KB 路径如何受 grant 约束；语义最窄但会与现行 “KB 允许批准 SHA 为祖先” 行为冲突，实际会拒绝大量已批准 CR。

**已决（2026-10-26，用户选择 (a)）**：本段保留为决策记录。(a) 生效后 S5 的 19 个 merge leaf 夹具形态已可全部固定——`merge 范围 symlink 取自发布候选树` 按选定提交树判定，finalize 三个生成路径必须显式在 `allowed_paths`（漏列即拒，无暗设豁免），`channel-test-expectations.json` 可按此冻结。以下两支后果仅作背景：
