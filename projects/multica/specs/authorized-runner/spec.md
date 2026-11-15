# Spec: authorized-runner

> Change: 2026-10-22-aifi-45-authorized-execution（最新修订并入 2026-11-13-aifi-45-real-execution-closure） | Auto-generated Human View

## Requirements

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
