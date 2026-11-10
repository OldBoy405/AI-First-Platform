# AIFI-45 可信 verdict：签发主体与信任根的只读源码调研

## 范围、路径和结论

仅研究签发主体、key、信任根及独立验签与其必要结果绑定。**不能从 Ray 的草案负责人角色推断签发者。** 归档设计要求的候选签发方是隔离的 daemon control 服务所持 T/Node worker；当前所查源码只展示签名、判定、存储和验签组件，**没有建立从权威 command 生产、Node 执行、受保护 verdict 签发到 M ingest/settlement 的现网端到端事实**。真实生产者、私钥控制者、manifest pin 和部署均未知。

路径基准：`W/` 指本工作区 `AI First Platform/`；`T/` 指同级源码仓 `../tools/`；`M/` 指同级源码仓 `../multica/`。行号是此次读取的工作树行号，不是旧快照的行号。本文只静态读取文件；未访问服务、数据库、容器，未运行测试或修改任何源码、状态、已审文档；也未读取部署凭据或运行环境值。

## 主源索引与证据等级

1. **人审归档规范**：`W/projects/multica/archive/2026-10-27-trusted-verdict-channel/.stdd.yaml` 和 `W/projects/tools/archive/2026-10-27-trusted-verdict-channel/.stdd.yaml` 记录 Gate1/2/3 对话确认、归档；两侧 `design.md` 虽保留 BUILD 中的历史页首，状态以 `.stdd.yaml` 及 M 侧 `validation/gate3-readiness.md:132-175` 的范围为准。Gate3 是 `channel-component` 口径，不是 strict-production、Windows 隔离、agent 隔离或 AIFI-45 RUN 已完成的证明（同文 `:103-111,145-175`）。
2. **批准的正文及机器可读规范**：M `design.md:27-65,95-113,126-144`；`canonical/specs/code/verdict-channel.yaml:20-25,57-81,107-115,140-155,201-208,229-235,337-347`，对应 `specs/verdict-channel/spec.md` 的 SC-VC-002/006–008/012/015–016/022/025/037；`canonical/specs/code/deployment-readiness.yaml:11-37` 与 `specs/deployment-readiness/spec.md` 的 SC-DR-001–003。T `design.md:62-92`；`canonical/specs/code/verdict-channel-runtime.yaml:11-65,99-120` 与 `specs/verdict-channel-runtime/spec.md` 的 SC-TR-001–007/012–013。两侧路径的完整前缀分别为 `W/projects/{multica,tools}/archive/2026-10-27-trusted-verdict-channel/`。另核 T `canonical/specs/code/trusted-merge-gate.yaml` 与 `specs/trusted-merge-gate/spec.md`：merge 事实/发布 gate 不能代替 verdict 签发主体。
3. **设计输入，非独立批准的完整结果字段合同**：`W/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/trusted-verdict-channel-implementation-plan-20261026.md:41-50,83-98,106,169-183,194-202`。其中对 command/verdict 和 `disposition` 有具体提议，但归档 canonical SC-VC-006 没有批准完整 verdict 字段表；未知字段不自动产生授权事实。M 归档 `design-adjustments.md:87-97,126-140` 的 ADJ-8/11 记录三 purpose 及 manifest 两种公钥表达形式。
4. **前序静态分析，不是现网调查**：同一 validation 目录中的 `verdict-outcome-pre-spec-evidence-20261030.md`、`verdict-outcome-contract-20261029.md`、`verdict-outcome-spec-review-20261030.md`。后者记录 outcome-binding 新草案 Gate2 BLOCK；不能把草案候选、验收计划或协调者旧哈希当成本次批准/运行结果。
5. **当前源码一手证据**见下节；测试文件只证明测试代码意图及构造，未在本次执行，不代表生产配置或通过结果。

## 已批准设计要求：角色与 key

- **链路分工**：M 固定可信 selection、reservation/候选与 command；按批准的方案 C，受保护 daemon control 服务持有隔离 T worker，T/Node 处理 command、产生并提交裁决，再由 M 独立验签入账及在事务里复核并结算。具体发送路径仍是设计接口而非部署证明。reservation 不可执行，permit 后才可固定候选 enqueue；ACK 只确认 ingest，不是效果或释放 slot 的证明（M design §2–3、§6；SC-VC-002/012/022/025）。M/DB、operator 受保护 manifest、control 服务和 T runtime 一起属于该威胁模型信任根；agent stdout、可写 workspace/Git、平台 receipt 不是该根。root/DB 超级用户/恶意 operator 越界。
- **authority 与 attestation 至少是两种不同 purpose，不是同一把 key**：默认 `control-command` 授权 command；受隔离的 `tool-attestation` 签 verdict/checkpoint；human-authorizer 用另一个 `human` purpose 签 resume。SC-VC-008 明确 attestation 或 human 签 command 均拒；SC-TR-002 禁 attestation 签 human 动作。M ADJ-8 明确不是两类而是上述**三类**；D7 observer 另有登记身份/用途。此处“authority”应区分 command authority 与 human grant/approval authority，不能笼统等同。设计输入 §2 的 D7 行又限定各 readiness 域须加入 allowlist；不要推断所有 attestation key 都可签所有 readiness 内容。
- **manifest 与 M 验证**：独立 `execution-control-trust-manifest/v1` 由 operator 固定受保护的绝对路径和原始文件 SHA-256，条目限定 purpose、domain、scope、有效期；拒交叉用途、重复键及不可信路径，禁 agent enrollment。M 对 T 发来的原始 envelope 独立校验 purpose/domain/scope 和签名，未知字段无授权事实；普通 restart 不换 epoch/sequence，key 轮换仅用于新 verdict，历史验证需旧 key 与可信历史策略。它**不是**既有四字段 `execution-contract-manifest/v1`。归档 ADJ-11 允许 pin 公钥文件或内联公钥二选一；对整个 manifest 的 operator pin 仍是单独要求。
- **readiness 与业务 verdict 分开**：T 决定 readiness，M 检身份、绑定、generation、时效及 CAS 后决定启用；观测者签名和 `READY_COMPONENT` 不等同生产 activation 或 business permit（SC-DR-001/003、T design §7）。P0 须真实受限身份隔离；失败 C 路径停止，转 B 要另审，不能 silent fallback（SC-VC-037、SC-TR-013）。

## 当前源码静态事实（不等于现网）

### T/Node：有哪些构件，尚未证明整链

- `T/skills/shared/crctl/scripts/lib/execution-control-protocol.mjs:35-56,195-327,340-399,410-431`：operation 表将 command 指向 `control-command`、verdict/checkpoint 指向 `tool-attestation`、resume 指向 `human`；`verifyControlEnvelope` 从所给 manifest 取公钥，检查操作、purpose、domain、scope、key 有效期、签名及原 payload 的绑定。签名前像为 domain、NUL、原 payload 字节；签名函数由调用者提供私钥，并非 manifest 持有私钥。**注意静态限制**：`signControlEnvelope` 的 manifest 参数实际可省略；给定 manifest 时只调用 domain/scope/时间策略，未在该签名函数中核用途与私钥对应关系；最终 verifier 才核用途和签名。
- 同文件 `loadControlTrustManifest` 仅要求 manifest 绝对路径、解析并返回其 SHA-256；它没有接收/比较预期的 manifest pin。对条目，支持公钥内联或绝对路径+文件 SHA-256 二选一；`forbiddenRoots` 由调用者提供，缺省为空。故不能将 loader 本身等同于已由 operator 固定并隔离的 manifest。
- `T/skills/shared/crctl/scripts/lib/execution-control-worker.mjs:29-48` 的 `applyOperation` 是对输入的 fence/序号检查并返回对象，**不执行业务命令、不签 verdict**。`execution-control-policy.mjs:20-65` 的 `admitRepairWithFacts` 是规则函数，依赖调用者提供的 verified facts；不自行建立这些 facts 的权威来源。`execution-control-readiness.mjs:27-69` 为纯 readiness 求值，不自行签发。
- `T/skills/shared/crctl/scripts/lib/execution-control-store.mjs:1-16,111-127,149-181,194-267`：`applyOnce` 调用调用者提供的 `produce` 并冻结结果；接收外部提供的签名，`assertFrameChain` 只验签名形状与帧摘要，文件头明确**不认证历史、不验签、不串行化并发写入**。因此这些组件本身不足以证明受保护的签发/提交组合。限定对 `T/skills/shared/crctl/scripts` 的导入与调用检索，相关协议、store、worker、readiness 实际调用主要见测试；不能因此断言仓外或部署不存在调用者。

### M/Go：独立验签能力与装配边界

- `M/server/internal/governance/execution_control_protocol.go:32-47,74-89,382-403,408-590,614-723`：`LoadControlTrustManifest` 与 `VerifyControlEnvelope` 使用独立 Go 实现；要求公钥 Ed25519、key purpose、domain、scope、时间及原字节签名；递归拒重复键。M 支持额外 `deployment-observer` 用途；T 操作表和 `KEY_PURPOSES` 当前不包含该用途，T loader 拒该类条目（`execution-control-protocol.mjs:56,246`）；含 observer key 的同一 manifest 不能直接假定两侧均可加载，D7 兼容与作用范围待审。M loader 也只返回 manifest digest，未接收期望 digest；来源/pin/禁写根仍需可信上层提供。`SignControlPayloadBytes`（`:761-800`）是通用签名 helper，私钥来自调用者，manifest 可空，非生产 key 托管证据。
- `M/server/internal/governance/execution_control_store_state.go:48-128,148-157`：`ApplyControlCommandTx` 接收已签 command，`verifyControlCommand` 验签并检查其请求、序号、前驱、lineage、fence、reservation 等子集；注释明确完整 B 与 manifest 权威来源需生产调用者独立确定。它**不是 command 生成或签发器**。
- 同文件 `:320-399,404-496`：`verifyVerdictAttestation` 使用调用者提供的 manifest 和 scope，校验 verdict 原签名字节与 store/lineage，`verifyVerdictSubject` 绑定 request、epoch、sequence、previous digest；`AppendVerdictFrameTx` 核链尾并入库。其当前只核这些主体/链字段，未将认证的裁决结果与实际 effect 绑定。另注意协议 verifier 的 digest 是域分隔前像 SHA-256（`execution_control_protocol.go:614-619,719-723`），此入链函数当前计算的是 payload 字节 SHA-256（`execution_control_store_state.go:413-415`）；不能混为同一 digest。它在更新 cursor 时清 `open_request_id`（`:493-496`），与批准设计 ACK 不释放 slot 的要求须按完整路径另审，不能只凭函数注释证明符合。
- `M/server/internal/daemon/execution_control_worker.go:42-87,140-232,236-287`：`ControlWorker.ApplyTx` 核 fence 后调用 Go 入链函数，消费**外部传入**的 verdict frame；不生成或签裁决。`M/server/internal/daemon/execution_control_client.go:15-42` 提供原字节 POST 客户端，路径是 `/api/daemon/execution-control/verdict`；对 `M/server/**/*.go` 的静态检索只发现客户端常量，未发现该路径或批准设计中 commands/verdicts/checkpoints 路由的注册。所查 `ApplyTx`、`PostControlVerdictBytes`、`SettleCandidateTx` 调用点为测试或定义；这不是对其他部署/外部调用者的证明。
- `M/server/internal/governance/execution_contract_manifest.go:21-39,46-85` 的既有四字段 contract loader 实际比较调用者提供的 manifest 原字节 SHA-256；与 control trust manifest 是不同对象。`M/server/cmd/server/main.go:701-720` 的默认 router 装配未提供 `AdmissionDecider`；`M/server/cmd/server/router.go:253-255,1614-1623` 在 runner 启用时要求非 nil decider，否则退出。非 nil 本身也不确立可信 ingest。
- `M/server/internal/governance/execution_control_settlement.go:31-69,72-148,157-179`：`Kind` 是调用方输入，校验形状、不从已验签 verdict 判定结果；已有结算先重放；撤销为真时可降为 no_effect。缺 selection→CR 链时 `pgx.ErrNoRows` 返回 false、nil，decision 为 nil 亦为 false，不能由附近“不猜”注释认定缺链 fail-closed。`execution_admission.go:151-188` 查询 effect settlement、关联 verdict、cursor 覆盖；不重验 manifest 来源、签名或 settlement 权威，并明示 `request_id=task_id` 是待生产路径核实的假设。静态缺口不证明现网可达或实际攻击。
- 不能只检查单一 settlement：`M/server/internal/governance/execution_channel_admission.go:71-73,179-217`、`execution_control_policy.go:143-147,219,244-245,301,330-331,370`、`execution_merge_effect.go:200-217` 还有不同写入者；`execution_sensitive_action.go:141` 有对其中敏感动作函数的非测试调用。`ConsumeResumeEpochTx` 经 `ResolveVerifiedGrantTx` 查 approval_record 并核 grant 字段，本函数未核 human 签名 envelope；与归档 human purpose 合同如何衔接待审，不能据此推断生产可达或声称其他层均未验签。各入口的权限、效果对象及实际可达性须逐项核，不可直接外推。
- effect 调研另发现静态状态机差异：`SettleControlCommandTx` 对 `issued` 或 `result_ready` 均通过前置状态检查，但之后调用的 `TransitionControlCommandTx` 不允许 `issued` 直接转 `settled_*`（`execution_control_settlement.go:122-149`；`execution_control_store_state.go:284-295`）。前者先在调用方事务中执行 INSERT 后才转换；错误时调用方是否一律回滚、完整调用是否可达仍需核实。不能据此宣称线上已产生部分结算。
- readiness 亦不可混为已验签：`M/server/internal/governance/execution_policy_readiness.go:241-273` 保存调用者字节；`execution_deployment.go:72-90,109-126` 从该字段直接 JSON 解码并检查结果。其完整可信验签接线未由这两处证明。

### Test fixture / 测试代码仅作边界说明

- 既有 `verdict-outcome-pre-spec-evidence-20261030.md` 第 2–3 点记录 T 的一个测试向量使用 `seq` 而非 M writer 需要的 `sequence`，还缺若干帧主体字段；其基础 envelope 例子不能证明可直接入链或产生真实 effect。这里不复制 fixture 内容。
- `M/server/internal/governance/crosslang_test/interop_test.go:1-5,26-35,41-52,64-106` 是测试内动态生成临时 key 和内存 manifest，用 Node helper 签 verdict；不是现网签发人或密钥来源。它也不证明真实 T worker 已装配。`M/server/cmd/server/execution_run_003_test.go:330-405` 为测试内构造 key、manifest、settlement 并直接调用 Go writer；不证明生产 command→T→M 链路。

## 旧 SHA 与本次快照限制

旧 raw SHA 和范围见上述两个 pre-spec/contract 文档；`W/projects/multica/changes/2026-10-22-aifi-45-authorized-execution/validation/verdict-outcome-source-20261029/` 留有部分旧字节副本。调研者受限于只读文件工具，未计算当前 raw SHA，也未对全部文件做逐字节比较；协调者随后核算下列 protocol 文件及 `verdict-outcome-pre-spec-evidence-20261030.md` 中 M 的 6 个通道/结算相关文件，后六者本轮 raw SHA 与前述文档一致。其他文件是否等于旧 SHA 未知；不能把旧 hash 贴到当前文件或将旧测试结果视为覆盖当前工作树。

已直接发现一个确定差异：`M/server/internal/governance/execution_control_protocol.go:626-640` 当前 `VerifyControlEnvelope` 新增了 `domain != operation.domain` 的拒绝；旧副本 `verdict-outcome-source-20261029/multica-server/internal/governance/execution_control_protocol.go:626-637` 没有该分支。故当前文件**不等于**旧文所列 SHA-256 `f808f2e4d2b112467707f9f2a2aa45db4adb98988ec8b330b26b1d5758ef2641`。协调者补算当前文件 raw SHA-256 为 `6a767571cdd7961a01c84da385361398c6563a7409d06aeafa95001ffb885dda`，旧副本 raw SHA 与旧文一致；这些哈希不代表研究者亲自签核。当前行号以当前文件为准，旧 snapshot 的分析只适用于当时字节。

## 未知事实与建议候选（不是部署决定）

**待有权人确认**：实际部署的 producer/command 发起者和执行者；command key、attestation key、human key 的控制主体及隔离；manifest 由谁批准、从何处读取和如何 pin/轮换/撤销；哪些实例和版本能签、写、接单，可信签发时间；既存 verdict/历史与 schema 的真实存量、适配路径；效果权威来源及 `request_id` 与 task/generation 的关系。只请求角色、机制、版本和非敏感证明，不请求密钥、凭据或环境变量值。

**建议候选**：优先以已批准的隔离 daemon control + T/Node worker 作为核对起点，而非宣称它现已上线；若无法满足 P0，不自动改用 B，须重新设计并获审。让有权人确认 command 与 verdict 分权、operator-pinned manifest 的可信加载与 M 独立验签，明确受保护 commit/重放、可信时间和历史旧 key 策略，再针对每一种 effect 明确经认证结果、冻结 command、request/lineage/generation 与真实 effect 的绑定以及 no_effect/unknown 的区别。先评估既有合同能否满足，必要时经双方批准兼容方案或新版本；不预设 v2、字段扩展或现网为空。不同 settlement 写入口和 readiness 均需单独确定责任与 fail-closed 行为；Gate2 前不能把本调研当签核、部署许可或 AIFI-45 验收。
