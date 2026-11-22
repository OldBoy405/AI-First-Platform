# Spec: authorized-runner

> Change: 2026-10-22-aifi-45-authorized-execution（已并入 2026-11-17-execution-admission-simplification） | Auto-generated Human View

## Requirements

> 合并 change 2026-11-18-defensive-trim-multica（变更日期 2026-11-18）：新增 REQ-RUN-201～203 / SC-RUN-201～207；SC-RUN-102～104 的首发结果及 SC-RUN-107 的请求体范围不符出口限定于首次签发，精确重放及非精确重放见 SC-RUN-202。

> 修订 2026-11-18（change 2026-11-17-execution-admission-simplification）：SC-RUN-003 的触发条件「锚点 task 当前 generation 的 consumption 回执或它自己的 effect 尚未提交」已由 SC-RUN-101 的「CR 当前授权头有效即放行」取代；SC-RUN-003 其余 AND 条款（真实 daemon_token、project/resource 投影、verdict 验签与绑定等）原样保留。新增 SC-RUN-102～109（默认部署可签发、入口边界不放宽、默认契约与 daemon strict 链联调）。

> 修订 2026-11-15（change 2026-11-13-aifi-45-real-execution-closure）：SC-RUN-001 收紧为 requirement/architecture 两类 run，SC-RUN-006 的撤销分支改为「不派发、不推进、admission=HEAD_REJECTED、历史行不改写」，SC-RUN-007 的范围收敛到有生产启动入口的 run 类型。其余分支与条款保持原文。

### Requirement: 实际认证入口绑定充分授权，ACK与已提交业务消费分离。

#### Scenario: SC-RUN-001

- **GIVEN** 认证 owner/admin 原请求包含完整授权包，且新 policy 配套已就绪。
- **WHEN** 通过真实认证入口启动 requirement 或 architecture 类普通变更，并由真实 daemon 与真实 agent 执行其节点。
- **THEN** SHALL 绑定原授权并经 crctl 适用裁决自动推进，不要求重复阶段人类确认。
- **AND** 原 SC-RUN-001 的其余 AND 条款（原请求字节与资源选择冻结、实际数据库校验、初始已签 repository_bindings 与 coordinator_binding、同原请求返回原包）保持不变。
- **AND** 范围收敛：开发（code）与回写阶段在生产中没有 run 启动入口，不在本场景保证内。本 change 的真实运行证据只覆盖 architecture；requirement run 的真实运行仅在 Gate 2 另选时才产生，否则只有静态节点表与组件测试。

#### Scenario: SC-RUN-002

- **GIVEN** 请求仅为task-token、伪header、自报actor、Agent补写候选包或越权成员。
- **WHEN** 调用授权入口。
- **THEN** SHALL 不签发有效execution授权，不创建执行任务，不把转述视为人类批准。

#### Scenario: SC-RUN-003

> 注（2026-11-18）：本节 GIVEN/THEN 中的 consumption/effect 触发条件已由 SC-RUN-101 取代，其余 AND 条款保留。

- **GIVEN** grant 送达落盘并 ACK，但该受保护动作的锚点 task 当前 generation 的平台 consumption 回执或它自己的 effect 尚未提交。
- **WHEN** ACK 回调及 periodic wake 发生。
- **THEN** SHALL 只唤醒核验，不完成业务 gate 或直接派旧 continuation；该锚点 task 的 effect 提交后才依实际状态推进。
- **AND** 锚点由 admission-task-binding 能力规定：派发、人工门及无 own-task 的完成为 run 的 source task，完成有 own-task 的节点为其当前任务；CR 内其他 task、其他 CR 或旧 generation 的消费事实不得放行。
- **AND** 对execution-consume，上述“提交”由consumption-effect能力（平台签发）满足；T的裁决只是候选，不入链，也不被当作提交。
- **AND** 新控制链须真实daemon_token、DB当前claim与本机实际子进程/资源匹配；普通PAT/JWT兼容认证不自动获得新控制签发能力。
- **AND** project/resource投影仅保留身份不等于fresh证明；旧快照、graph换根或复制sidecar不能开放消费。
- **AND** verdict写入须核实可信签名及原始载荷字节，并将签名中的request_id、epoch、sequence、previous_verdict_digest与实际入链帧逐项绑定；首帧previous_verdict_digest为空字符串，缺失或null拒绝。新command/verdict在相关锁等待后、首次写入前须按服务端当前时钟重验密钥有效期；这不证明caller-supplied密钥根可信，也不是提交时刻保证。同request仅在通过所提供信任参数的验签且签名载荷字节和已存不可变字段一致时重放原帧，否则冲突，不得引用请求中伪造的新帧ID；过期历史key的恢复策略尚待确定。现有envelope为JSONB，仅能比较结构值，不能证明原始信封字节一致。这是最低关联要求，不替代完整B、受保护信任根、生产producer/ingest及当前代次的验证。

> 修订 2026-11-11（change 2026-11-11-aifi-45-admission-task-binding）：SC-RUN-003 按锚点 task 及当前 generation 收紧消费回执和 effect 的要求，保留原有 AND 条款；增量原文见 archive/2026-11-11-aifi-45-admission-task-binding/specs/authorized-runner/spec.md。

### Requirement: 修复准入后以持久化逻辑步骤身份入队，跨run恢复不重复消费或根派发。

> 修订 2026-11-10（change 2026-11-10-aifi-45-m005-consumption-effect）：SC-RUN-003 的“T 提交”改为“平台 consumption effect 提交”，并新增第一条 AND；其余 AND 不变。原文见 archive/2026-10-22-aifi-45-authorized-execution/specs/authorized-runner/spec.md。

#### Scenario: SC-RUN-004

- **GIVEN** 同一repair receipt经并发wake、跨cycle或supersede反复返回。
- **WHEN** 实际TaskService创建纠正性根任务。
- **THEN** SHALL 按永久logical_dispatch_key只保留一个根任务并返回赢家，终态后也不能重新创建同逻辑根。
- **AND** tenant/project归因由可信run与task绑定校验。
- **AND** receipt引用保存在现有execution_context/detail/context且不被upsert覆盖。
- **AND** 跨run必须有可信adoption映射和当前subject/版本重验才接收原结果；不改原根归因。

#### Scenario: SC-RUN-005

- **GIVEN** T准入提交后入队前、DB入队提交后响应前分别崩溃，随后出现技术重试。
- **WHEN** 启动恢复及查询原任务lineage。
- **THEN** SHALL 恢复原根及有界子链，不重复准入或消费，不复活终态根来规避上限。

#### Scenario: SC-RUN-006

- **GIVEN** T拒绝新准入或查询故障；另有已花完最后名额的有效receipt、撤销revision及签名resume分支。
- **WHEN** Runner处理新修复、原修复验证恢复或继续请求；撤销情况下经下一次认领、节点完成或 ResumeActiveRuns 发现路径处理，包括服务重启之后。
- **THEN** SHALL 拒绝新的未准入修复但允许最后已准入修复的测试、独立验证和PASS交付，不能自算预算或伪装首次实施。
- **AND** 撤销时未启动任务停止，已运行只允许有界安全收尾且不返还消耗（原条款保持）。
- **AND** 撤销后的停止 SHALL 由本 change 保证：不派发新的节点任务、不推进节点，等待原因可被查询为 admission（HEAD_REJECTED）；已有历史行（CR 更新、审批记录、任务、回执、effect）SHALL NOT 被删除或改写，run 不被伪造成 completed 或 failed。
- **AND** 无进展后仅适用T已提交resume receipt可恢复，不以ACK或模糊继续代替。
- **AND** 原 SC-RUN-006 的其余分支（新准入修复的测试与交付、已运行任务有界收尾）不在本 change 保证内，保持原文，列后继登记。

### Requirement: 唯一Runner必须接通实际四阶段入口、事件、启动发现和失败恢复。

#### Scenario: SC-RUN-007

- **GIVEN** 新 policy 的普通已授权变更的 architecture run（或 requirement run）推进到节点交接处，服务在该处重启。
- **WHEN** 经真实认证入口、统一 Reconcile、periodic 发现和真实 TaskService 驱动。
- **THEN** SHALL 每个节点恰有一个任务（无重复、无遗漏），已推进的节点不回退，不依赖人工命令或直接调用 walker。
- **AND** 范围收敛：开发（code）与回写阶段在生产中无启动入口，ResumeActiveRuns 只扫描 requirement 与 architecture；原 SC-RUN-007 对这两个阶段的要求不在本 change 满足，不得宣称。

#### Scenario: SC-RUN-008

- **GIVEN** 旧run仍存活，或新policy任一入口/恢复/安装版本尚未配套。
- **WHEN** 尝试切换、迁移或回退。
- **THEN** SHALL 保留旧合同和历史，拒绝未就绪切换；回退仅停新准入，不能清历史或双派发。

### Requirement: 独立评审与证据以联合执行身份适用，敏感动作不可借正常授权执行。

#### Scenario: SC-RUN-009

- **GIVEN** 证据在run、node、attempt、cycle、subject、template/policy、receipt或reviewer真实UUID任一项不适用。
- **WHEN** 投影迟到评审、进展assessment或请求交付。
- **THEN** SHALL 仅保留历史而不推进当前节点，作者不能自评PASS，缺实际差异和测试不能交付。

#### Scenario: SC-RUN-010

- **GIVEN** 已授权普通实施，但当前生产/数据/权限/支出动作缺对应专项授权，另有精确专项授权正例。
- **WHEN** Runner请求具体action/target/environment/operation_id的裁决。
- **THEN** SHALL 在缺授权分支不执行，在精确正例中只应用授权边界并幂等消费，不再重复确认同一事实。

### Requirement: grant 送达并 ACK 后的唤醒与周期唤醒，只在 CR 当前授权头有效时才推进业务 gate 或派发；不再等待锚点任务的 consumption 回执与 effect。

#### Scenario: SC-RUN-101

- **GIVEN** grant 送达落盘并 ACK；CR 当前头为 approve，且没有任何锚点任务回执或 effect。
- **WHEN** ACK 回调及周期唤醒发生。
- **THEN** SHALL 依授权头放行并推进；同一 CR 无头或头被撤销时 SHALL 只唤醒核验、不完成业务 gate、不直接派发。
- **AND** ACK 回调与周期唤醒重复发生时不重复派发，不产生第二个任务。
- **AND** 新控制链仍须真实 daemon_token 与 DB 当前 claim；普通 PAT/JWT 兼容认证不自动获得新控制签发能力（SC-RUN-003 对应条款保持）。

### Requirement: 默认部署（不传任何契约启动参数）在存在审批签名服务时，使用内置默认契约即可签发人工执行授权；显式 manifest、半配置失败与无签名服务时功能关闭的既有行为不变。

#### Scenario: SC-RUN-102

- **GIVEN** 审批签名服务存在；未传 manifest 路径与 sha256；工作区 owner 已认证；CR 有可解析的 project，尚无初始授权记录和授权头，且其余首发条件满足。
- **WHEN** 提交授权请求，且省略 policy_version、policy_digest、template_digest 三个字段。
- **THEN** SHALL 返回 201 并设置该 CR 的授权头；签名 payload、冻结请求与部署契约三者的三个值一致， 随后读取该头为有效（不得出现 EXECUTION_AUTHORIZATION_HEAD_INVALID）。
- **AND** 满足 SC-RUN-202 条件的精确重放返回 200 reused=true 和原记录，不写新记录、不更新头。

#### Scenario: SC-RUN-103

- **GIVEN** 同 SC-RUN-102 的部署与 CR（首次签发）。
- **WHEN** 提交授权请求，三个字段显式给出且与部署契约逐一相等。
- **THEN** SHALL 返回 201 并设置授权头。

#### Scenario: SC-RUN-104

- **GIVEN** 同 SC-RUN-102 的部署与 CR（首次签发）。
- **WHEN** 提交授权请求，三个字段中任意一个给出了格式合法但与部署契约不同的值。
- **THEN** SHALL 返回 409 EXECUTION_CONTRACT_MISMATCH，不写入任何授权记录，不改变头。
- **AND** 字段显式给出空字符串按省略处理；多出未知字段仍被拒绝。
- **AND** 首次签发时，格式非法的值（非字符串、非小写 64 位 hex）在契约比较之前先按 EXECUTION_SOURCE_INVALID / EXECUTION_SCOPE_INVALID 拒绝，不被补齐为默认值。

#### Scenario: SC-RUN-105

- **GIVEN** 未配置审批签名密钥，也未传 manifest。
- **WHEN** 服务启动并收到授权请求。
- **THEN** SHALL 正常启动，授权端点返回 503 EXECUTION_AUTHORIZATION_DISABLED，不因默认契约而启动失败。
- **AND** 已传 manifest 但无签名密钥时仍拒绝启动（既有行为）。

#### Scenario: SC-RUN-106

- **GIVEN** 传了显式 manifest 与匹配的 sha256，且签名服务存在。
- **WHEN** 服务启动并签发授权。
- **THEN** SHALL 以 manifest 的契约为准，默认契约不生效；只传其中一个参数、路径非原生绝对路径、sha256 不匹配或字节超限时 SHALL 仍拒绝启动，不回退到默认契约。

### Requirement: 授权签发的入口边界不放宽：只有经认证的人类 owner/admin 可签发，project 范围只取自 CR 到同 workspace shell issue 的关系。

#### Scenario: SC-RUN-107

- **GIVEN** 默认部署，签名服务存在。
- **WHEN** 分别以 task token、cloud PAT、非 owner/admin 成员的身份提交授权请求；以及对一个 shell issue 缺失或无 project 的 CR 提交请求。
- **THEN** SHALL 对 task token 与 cloud PAT 返回 403 EXECUTION_HUMAN_SOURCE_REQUIRED；对非 owner/admin 返回 403 FORBIDDEN_AUTHORIZER； 对无法解析 project 的 CR 返回 409 EXECUTION_SCOPE_UNRESOLVED；以上均不写入授权记录。
- **AND** project 不取自请求体；首次签发时，请求体里的 workspace/project/CR 与可信范围不一致仍为 400 EXECUTION_SCOPE_INVALID。通过通常认证、项目解析和请求大小及形状检查后，冻结字节不同的重放返回 409 EXECUTION_AUTHORIZATION_CONFLICT；精确重放见 SC-RUN-202。

### Requirement: 默认契约签发的头能走通 daemon 的 strict 预验证链（binding、crctl 检查、节点预消费）；这是联调证据，不是对 daemon 的修改。

#### Scenario: SC-RUN-108

- **GIVEN** 一次性隔离环境；真实 server（默认契约，无 manifest 参数）、真实 daemon、可用的 crctl 与 node、不消耗模型的 stub 执行器；CR 的授权头经省略字段的请求签发。
- **WHEN** 运行 architecture 流水线直到首个节点任务被 daemon 认领并启动。
- **THEN** SHALL daemon 的 strict 路径对该节点完成 grant 安装、crctl 检查、binding 与平台 receipt，节点任务启动并完成； 任一环节因 policy_digest 或 template_digest 不一致被拒绝时 SHALL 判定本变更失败并停下复核设计，不得继续堆实现。
- **AND** 该场景不触碰现网数据库与现网 daemon；实例与容器由驱动自建并按 nonce 释放。

#### Scenario: SC-RUN-109

- **GIVEN** 与 DAYA-5 同形的 requirement run：源任务是从未消费的普通任务，CR 起初无头；授权头经真实授权路由（默认契约）签发。
- **WHEN** 发现路径运行：writer 任务入队，完成并投影后再次发现。
- **THEN** SHALL writer 任务带 cr_id 与 pipeline_node_run_id 入队，完成后 review-requirement 节点的任务被派发；全程不出现对源任务消耗回执的等待。
- **AND** 不接触现网数据；与 SC-RUN-108 合起来共同支撑提案成功标准第 8 条。

### Requirement: 授权入口一次准备请求，重放与首次签发共用准备结果。

#### Scenario: SC-RUN-201

- **GIVEN** 已认证授权人有一个 CR 及适用部署合同；CR 有可解析的 project，尚无初始授权记录和授权头，且其余首发条件满足。
- **WHEN** 通过签发 HTTP 入口提交合同字段缺失、为 ""、显式相等或合法但不同的申请。
- **THEN** SHALL 对缺失或 "" 补部署值；合同字段相等时签发，返回 201 并在同一事务保存记录和设置初始头。
- **AND** 合法但不同返回 409 EXECUTION_CONTRACT_MISMATCH，且不写授权记录、不更新头。

#### Scenario: SC-RUN-202

- **GIVEN** CR 已有初始授权记录。
- **WHEN** 通过签发 HTTP 入口重送请求，并通过通常认证、项目解析和请求大小及形状检查。
- **THEN** SHALL 在授权人、冻结字节与摘要、锁内解析的项目都匹配原授权时返回 200 reused=true 和原信封，不写新记录、不更新头。
- **AND** 任一不匹配返回 409 EXECUTION_AUTHORIZATION_CONFLICT。
- **AND** 重放不重查当前资源绑定、不核验当前头；返回原记录不代表当前头有效。

#### Scenario: SC-RUN-203

- **GIVEN** 基线有完整及需补值的合法申请样本，且签发所用密钥、ID、时间及可信事实相同。
- **WHEN** 经准备和签发生成冻结原文、payload 和签名。
- **THEN** SHALL 生成与基线逐字节相等的冻结原文（完整输入的 CRLF 和 -0 原样）、原始 payload 和 Ed25519 签名。

### Requirement: 头读取核验存储协议和当前授权事实，不按现行申请规则重审历史。

#### Scenario: SC-RUN-204

- **GIVEN** 历史批准符合存储协议和当前授权事实，但冻结原文有现行新申请不允许的字段。
- **WHEN** 经生产授权头 GET 读取该批准及其冻结原文被篡改的对照。
- **THEN** SHALL 对有效批准返回 200 和原头摘要、原 record、原公钥。
- **AND** 冻结原文被篡改、与已签摘要不符时拒绝读取。

#### Scenario: SC-RUN-205

- **GIVEN** CR 有已签的撤销记录及其初始批准。
- **WHEN** 通过生产授权头 GET 读取有效撤销链，以及前驱、签名或 revision 损坏的对照。
- **THEN** SHALL 返回有效撤销记录并拒绝损坏链。

### Requirement: 敏感动作与撤销共享 CR 排他锁，按提交顺序确定结算结果。

#### Scenario: SC-RUN-206

- **GIVEN** 两个独立 CR 均有有效专项授权。
- **WHEN** 经生产入口交错发起动作与撤销，分别让动作和撤销先取得 CR 排他锁。
- **THEN** SHALL 在动作先行时返回动作 200 且仅写一笔 effect，随后撤销返回 201。
- **AND** 撤销先行时，动作返回 409 EXECUTION_AUTHORIZATION_HEAD_INVALID，不查重、不扣额、不写 effect。

#### Scenario: SC-RUN-207

- **GIVEN** 头有效，且有专项列明和未列明的动作。
- **WHEN** 重试同一已列明动作的 operation_id，并请求未列明动作。
- **THEN** SHALL 对同一 operation_id 仅写一条 effect，返回原回执且不多扣额度。
- **AND** 未列明的动作结算为零（ordinary_grant_has_no_effect）。
