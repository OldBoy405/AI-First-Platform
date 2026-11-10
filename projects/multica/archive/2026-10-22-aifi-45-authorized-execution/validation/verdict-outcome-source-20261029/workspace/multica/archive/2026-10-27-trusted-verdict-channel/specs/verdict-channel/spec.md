# Spec: verdict-channel

> Change: 2026-10-27-trusted-verdict-channel | Auto-generated Human View

## Requirements

### Requirement: 可信选择与冷启动：selection 持久且不可降级，候选由服务端固定，control reservation 不可执行。

#### Scenario: SC-VC-001

- **GIVEN** CR 已在可信 selection 中登记为 Strict，或其 trigger 合同字段被删除、改空或改写；或 selection 记录缺失、读取失败；或该 CR 由可信历史目录证明为 legacy。
- **WHEN** 解析该 CR 的 selection 并尝试产生新增 effect。
- **THEN** SHALL 只按持久 selection 判定，Strict 被删字段时返回 `T_VERDICT_BINDING_MISMATCH`，不降级为 Legacy，也不经 Unknown 落回 legacy。
- **AND** Unknown、缺记录、读失败一律拒绝新增 effect，不由 nil 或缺字段推断 legacy。
- **AND** Legacy 只能由可信历史目录证明；从未建立 selection 且被证明为 legacy 的在途 CR 保持原 gates。

#### Scenario: SC-VC-002

- **GIVEN** 冷启动场景下尚无真实 agent task，只有服务端冻结的 proposed task UUID 与 execution target。
- **WHEN** control worker 消费 T 裁决并在 permit 后尝试派发真实任务。
- **THEN** SHALL 使 control reservation 不进入任务队列、不可 claim、不可执行代码，并只在 permit 后按固定候选 enqueue。
- **AND** 原 active-claim SQL 不放宽；实际任务不存在不阻止 control worker 完成 T consumption。

#### Scenario: SC-VC-003

- **GIVEN** 同一 root+task+settlement 请求，分别注入事务回滚与固定 ID 已存在的冲突。
- **WHEN** 执行 `AdmitDispatchRootTx` 与 `EnqueuePipelineTaskTx`。
- **THEN** SHALL 在同一 Tx 内写 root、task、settlement，commit 后才发通知；rollback 得零持久新增且零通知。
- **AND** 固定 ID 冲突必须逐字段等同才视为成功，不得盲目 `DO NOTHING`。

#### Scenario: SC-VC-004

- **GIVEN** 在 `ValidationTestHook` 内，另一连接以 `lock_timeout` 尝试改同一 logical root 的终态；另设无锁冲突的正对照。
- **WHEN** 原事务继续推进 root adoption。
- **THEN** SHALL 以行锁阻止并发终态写入，失败断言只认 SQLSTATE `55P03`，不接受超时或连接错误。
- **AND** 已终态根不得被 adopt，终态后不得重建同逻辑根（顺序用例覆盖该语义）。

### Requirement: FreshWork 权威注册：来源、历史覆盖与唯一归属由 DB 认证，agent 不能自报 origin。

#### Scenario: SC-VC-005

- **GIVEN** 同一 origin 在已登记/重开/别名三种来源下分别注册，存在历史覆盖未知项或第二次跨 CR 注册。
- **WHEN** 调用 `RegisterFreshWorkTx` 并据此建立 selection/reservation。
- **THEN** SHALL 只接受 operator-pinned intake authority 的不可改 source record，并对同 origin 的第二次注册拒绝，不给出第二份额度。
- **AND** 只有 classification=NEW 且 unresolved_refs 为空的 proof 可供首次 selection；新证据只能追加新 proof，不改历史。
- **AND** 历史覆盖缺失或源不可读的 scope 只能 UNKNOWN，不能按「数据库没查到」签无历史证明。

### Requirement: wire 与信任根：key-purpose、exact keys 与 Go↔Node 原字节一致性。

#### Scenario: SC-VC-006

- **GIVEN** 分别用正确 purpose/domain/scope、错 purpose、错 domain、错 scope 与缺失字段的 envelope 请求验签。
- **WHEN** 调用 `VerifyEnvelope(raw,expectedPurpose,domain,scope)`。
- **THEN** SHALL 只接受三元组完全匹配的原始字节，任一错用或缺字段即拒，未知字段不产生授权事实。

#### Scenario: SC-VC-007

- **GIVEN** Go 与 Node 各自生成合法 command/verdict 向量及对应签名。
- **WHEN** 两个实现互相验证对方产出的原字节。
- **THEN** SHALL 双向通过合法向量，且对同一字节得到相同 digest；任何一侧重序列化都不算通过。

#### Scenario: SC-VC-008

- **GIVEN** 用 attestation key 签 command 或 resume、用 human key 签 command、manifest 含重复键或 union 双分支、manifest 指向 agent 可写路径。
- **WHEN** 加载 trust manifest 并验签。
- **THEN** SHALL 全部拒绝，且 manifest 只接受绝对路径与原始 SHA256 pin 的 exact keys。
- **AND** 禁止 agent enrollment；既有四字段 execution-contract manifest 不承载新字段。

### Requirement: 受保护 store：一次提交、原字节重放与不可篡改的冻结帧链。

#### Scenario: SC-VC-009

- **GIVEN** 同一 request 的并发写入、原字节重放、以及事务回滚后的重投。
- **WHEN** 写 `control_command`、`tool_verdict` 与 `control_settlement`。
- **THEN** SHALL 由 request/store-epoch-seq 唯一约束保证同请求只有一条记录，重放返回原记录与原 bytes。
- **AND** 回滚不得留下 command、slot 或 settlement；文件侧一次提交与原字节冻结由 tools 侧 store 保证。

#### Scenario: SC-VC-010

- **GIVEN** 入库的 verdict 帧出现断链、跳号、`prev_digest` 不指向前一帧，或携带占位签名（如 `signature=AA==`）。
- **WHEN** 校验该记录链并比较 cursor 的 `last_digest`。
- **THEN** SHALL 拒绝入账与推进，不把不可篡改账本当成追加授权。

#### Scenario: SC-VC-011

- **GIVEN** 同一 lineage 已有一个 open command，或旧 owner 仍持有旧 fence。
- **WHEN** 发起第二个 command 或由旧 fence 写操作。
- **THEN** SHALL 由 `EnsureRequestTx` 锁 cursor 并拒绝并行第二 command，旧 fence 不得执行新操作。
- **AND** fence 由 `BeginOwnerTx` 持久递增；不自动切换 request。

#### Scenario: SC-VC-012

- **GIVEN** command 处于 created、issued、result_ready、settled 与 uncertain 各状态，并收到 ingest ACK。
- **WHEN** 推进状态或尝试取消。
- **THEN** SHALL 只允许 `created→issued→result_ready→settled_effect|settled_no_effect` 的受限转换，uncertain 冻结 lineage。
- **AND** ACK 只确认持久化，不释放 slot；只有从未 issued 的 created command 可直接取消。
- **AND** `tool_verdict` 拒绝 UPDATE/DELETE/TRUNCATE，settlement 与 task_binding immutable。

### Requirement: 撤销与停止的线性化：先提交者决定 effect 归属，不追溯、不越序。

#### Scenario: SC-VC-013

- **GIVEN** 撤销与 effect 提交分别在不同交错顺序下竞争，且撤销发生在部分仓已发布之后。
- **WHEN** 旧 permit 继续尝试产生效果。
- **THEN** SHALL 在撤销先提交时把旧 permit 结算为 `no_effect`，在 effect 先提交时不追溯撤销该已提交事实，且撤销不等待 command slot。
- **AND** 部分发布后撤销：停止后续 publish、保留原 journal/receipt、转人工，不自动新建事务。

#### Scenario: SC-VC-014

- **GIVEN** 前一 effect 尚未 settlement，随后到达 stop 指令；或试图用 stop 撤销已提交 effect。
- **WHEN** 处理 stop 指令。
- **THEN** SHALL 按 T sequence 生效，前一 effect settled 后才能发后续 stop，且不伪称 stop 可越序撤销。
- **AND** 即时撤权使用 revoke 路径；stop 不追溯撤销旧 effect。

### Requirement: 恢复：checkpoint 与 journal 对齐后只允许方案恢复表列出的固定动作。

#### Scenario: SC-VC-015

- **GIVEN** 出现 tail 相同、T 恰领先一项、M 已 settled 而 outbox 未见、journal prepared 且 bundle 完整、以及缺失/落后/分叉/多项超前/issued 无 journal 各类观察。
- **WHEN** 执行 `ReconcileOwnerTx` 并读取 checkpoint/journal/open command。
- **THEN** SHALL 按恢复表逐类给出固定动作：恢复原 request、导入原 verdict bytes、返回原 mapping、重放原 command，或 freeze。
- **AND** freeze 时不猜「未消费」、不清 slot、不建空 store。

#### Scenario: SC-VC-016

- **GIVEN** 普通 restart、key rotation、旧 fence worker 继续接单，或 checkpoint 字段缺失。
- **WHEN** 恢复 worker 并继续服务。
- **THEN** SHALL 保持 epoch/sequence 并重发原 bytes，只让新 verdict 使用新 key、历史仍用旧 key 验证。
- **AND** 旧 fence、缺 checkpoint 不得继续接单；缺依赖一律 freeze 而非降级。

### Requirement: facts 与 repair/resume/sensitive action 只消费已验签事实，额度与范围不可被 payload 扩大。

#### Scenario: SC-VC-017

- **GIVEN** repair admit 的 `fact_refs` 指向未验签记录、解码 payload 自带额度或 reviewer，或来源账本不可核实。
- **WHEN** 调用 `ResolveFactsTx` 与 `ApplyOperation` 做准入判定。
- **THEN** SHALL 只使用已验签 grant/DB facts，拒绝未验签 payload，且额度不来自解码内容。
- **AND** 不新增 Go 侧预算分支；quota deny 只消费 T 裁决。

#### Scenario: SC-VC-018

- **GIVEN** repair 追加域请求同时试图新增仓库，或同一追加被并发提交两次，或原请求被重放。
- **WHEN** 处理追加授权。
- **THEN** SHALL 只允许追加额度、不扩仓库集合，并让 CAS 只接受一份，重放返回原结果。

#### Scenario: SC-VC-019

- **GIVEN** 合法 signed resume、越权 resume、已 revoked/terminal 的 root，以及重复调用。
- **WHEN** 执行 resume。
- **THEN** SHALL 绑定 grant/lineage/origin/stop_ref/subject/head/revision/expected_epoch 并只消耗一次 epoch。
- **AND** 不复活 revoked/terminal root，不清预算。

#### Scenario: SC-VC-020

- **GIVEN** 专项动作指向精确 target/environment；复制安装或信任根后使用新 operation_id；同 operation_id 原字节重放；撤销与 settlement 交错；旧账本来源不可核实。
- **WHEN** 执行 sensitive action。
- **THEN** SHALL 只允许 exact target/environment，新 operation_id 必须 EXHAUSTED 且原账本计数不变，重放返回原 receipt 不再消费。
- **AND** 撤销先于 settlement 提交时即使 T 已提交也结算为 no_effect，外部动作不执行。
- **AND** 旧账本不可核实即拒绝新增消费。

### Requirement: ingest、settlement 与 task-start binding 以真实 generation 为单位，不二次消费。

#### Scenario: SC-VC-021

- **GIVEN** T commit 后 M rollback 并重发原 bytes；或 M effect commit 后响应丢失。
- **WHEN** 重新 ingest 或重试结算。
- **THEN** SHALL 重发原 bytes 时返回与首次相同结果，已 settled 只返回既有 mapping，且 T 已消费不退款。

#### Scenario: SC-VC-022

- **GIVEN** ingest 返回 ACK；以及 pending/deny/stopped verdict、permit 过时或被撤销。
- **WHEN** 后续尝试产生 effect。
- **THEN** SHALL 让 ACK 只确认持久化、不释放 slot、不发 task，并把上述判决明确结算为 `no_effect`。
- **AND** 结果未知（issued/超时）不得推断未消费，也不释放 slot。

#### Scenario: SC-VC-023

- **GIVEN** 真实 task 已交付、启动前，其 task/runtime/`dispatched_at`/daemon generation 与 643–645 记录一致或故意不一致。
- **WHEN** 执行 task-start preflight 并尝试启动 agent。
- **THEN** SHALL 逐字段核 binding issue、consumption、activation 与 issuance envelope/head/challenge，任何不一致或未完成都不启动。
- **AND** generation binding 只把已提交 reservation consumption 绑定到原真实 task，不二次消费。

#### Scenario: SC-VC-024

- **GIVEN** task A 的 challenge 用于 task B；同 task/runtime 但旧 `dispatched_at`；相同 nonce 不同证明；读 claim 后任务转终态。
- **WHEN** 尝试写入消费或 activation。
- **THEN** SHALL 拒绝跨签发与过期 challenge，拒绝同 nonce 异证明，并以 `55P03` 证明 claim 行锁阻止终态后写入。
- **AND** 该 leaf 的真实前置是 AIFI-45 的 G1 与 G2/G4 残余；未修时按设计为 RED，不得登记完成。

### Requirement: reader 与 projection fence：严格模式只由已提交可信事实驱动，终态 fence 取并集。

#### Scenario: SC-VC-025

- **GIVEN** 出现 ACK、平台 receipt、伪 Git pass 而无 committed T；或对已 settled 请求再次 settle；或试图用新候选替换未 settled。
- **WHEN** 调用 `CommittedTReader.ReadCommitted` 与 `SettleCandidateTx`。
- **THEN** SHALL 在无 committed T 时产生零 root/task，重复 settle 只返回原 mapping，未 settled 不接受替换候选。
- **AND** reader 只读已验签 DB facts，不调用 Node、网络或文件。

#### Scenario: SC-VC-026

- **GIVEN** selection 已为 Strict 但 trigger 合同字段被删；目录缺行或读失败；以及被可信目录证明的 legacy 任务。
- **WHEN** 执行 strict fence 判定。
- **THEN** SHALL 仍按 strict 拒绝缺 T 裁决的路径，Unknown 不降 legacy，已证明的 legacy 行为不变。

#### Scenario: SC-VC-027

- **GIVEN** 终态上报时分别缺少两个 claim 字段；`fence_required` 由任一 generation 已有 644 行或 Strict selection 下创建决定；任务重领换 generation；判定读失败。
- **WHEN** 在终态事务内持任务行锁判定并写入。
- **THEN** SHALL 按并集规则要求 claim，缺 claim 返回 409，重领后仍 409，判定读失败即拒。
- **AND** 只有两字段都缺且 `fence_required=false` 才允许旧终态路径；STOP_NEW 或授权过期不阻止该安全收尾。

### Requirement: 迁移生命周期：单迁移建 14 表，down/reapply 干净且不触碰既有数据。

#### Scenario: SC-VC-028

- **GIVEN** 新 nonce 库分别处于空、已 up、up→down、up→down→up 状态。
- **WHEN** 执行 648 up/down/reapply。
- **THEN** SHALL 在 up 后具备 14 张表及全部触发器/索引/约束，down 全部撤销，reapply 恢复同名对象且无遗留业务行。
- **AND** 每张表至少一个独立 `t.Run` leaf；`ChannelTableNames` 登记 14 个 DB 全名。

#### Scenario: SC-VC-029

- **GIVEN** 同一隔离库在 up 状态已存在 643–647 夹具行与对象。
- **WHEN** 按精确 648 down/up 做生命周期验证。
- **THEN** SHALL 保持原夹具行与对象不变，且不留下 648 孤儿对象。

### Requirement: merge-facts 端点只按认证主体解析事实，响应闭集且不返回调用方提供的版本参数。

#### Scenario: SC-VC-030

- **GIVEN** 合法 MDT 凭据请求本 workspace 的 CR、请求他人 workspace 的 crID、以及携带 PAT/JWT/task-token 的请求。
- **WHEN** 调用 `GET /api/daemon/execution-control/merge-facts/{crID}`。
- **THEN** SHALL 由服务端从认证主体解析 workspace，他人 crID 返回 404，回退凭据一律 403，且认证先于资源查找。
- **AND** 不接受 `--workspace`/`--grant`/revision 等调用方提供的目标或版本参数。

#### Scenario: SC-VC-031

- **GIVEN** 同一仓库再次批准、授权 head 撤销、以及历史行已存在。
- **WHEN** 写 `code_source_freeze`。
- **THEN** SHALL 由 code 批准事务追加写并 supersede 旧行，撤销在同一事务置 `revoked_at`，不删行、不改写历史。
- **AND** 部分唯一索引保证任一时刻每仓至多一条当前行；多条或零条当前行按事实缺失处理。

#### Scenario: SC-VC-032

- **GIVEN** 响应分别满足集合完整、少一仓/多一仓、同计数但替换 repo_id、摘要不符、`current_binding` 三态、部分仓 `freeze_revoked`。
- **WHEN** 生成响应并由调用方校验。
- **THEN** SHALL 返回闭集字段与自洽的 `repos_digest`，并如实标注绑定三态与 `head_revoked`。
- **AND** 易变字段不入摘要；`provenance_digest` 仅在 legacy_proven 时必填。

#### Scenario: SC-VC-033

- **GIVEN** 出现连接失败/超时/5xx/400/未知 code、撤销、head 前移、越界与不可核实并存等组合。
- **WHEN** 端点返回并由 CLI 映射外层码。
- **THEN** SHALL 只用闭集非 200 码表达端点侧失败，并按 `UNAVAILABLE>REVOKED>HEAD_MOVED>VIOLATION>UNVERIFIABLE` 分层。
- **AND** 端点如实返回事实，越界判定与优先级在 CLI；不可达时不存在与 VIOLATION 并存的情形。

### Requirement: merge-effects 以 reserve/report 兑现撤销线性化，attempt 互斥且码序固定。

#### Scenario: SC-VC-034

- **GIVEN** reserve 事务与撤销并发，且预检冻结了 base/head/候选写集摘要。
- **WHEN** 提交 `op=reserve`。
- **THEN** SHALL 以 CR 行 `FOR SHARE` 与授权 head 串行，同事务重验 head/`head_revoked`/冻结行/`input_digest` 后写 issued command。
- **AND** 撤销走 `FOR UPDATE` 既有路径，与 reserve 由行锁串行；Tx 内不调用网络。

#### Scenario: SC-VC-035

- **GIVEN** 同一 `effect_id` 的同 attempt 原字节重放、前 attempt 已 settled、无未终结前 attempt、前 attempt 未终结四种情形。
- **WHEN** 提交 reserve。
- **THEN** SHALL 分别返回 200 原结果、200 原 mapping、201 新 command、409 CONFLICT。
- **AND** 前 attempt 已 settled 的新 attempt 不新建 command；未终结时不接受并行 attempt。

#### Scenario: SC-VC-036

- **GIVEN** 畸形请求、PAT + 他人 crID、合法凭据 + 他人 crID、服务端不可用、head 前移且摘要也不同、finalize push。
- **WHEN** 提交 reserve/report。
- **THEN** SHALL 分别返回 400/403/404/503/HEAD_MOVED 且非授权失败不写 halted、journal 不变。
- **AND** 码序固定 `INVALID>UNTRUSTED>NOT_FOUND>REVOKED>HEAD_MOVED>INPUT_MISMATCH>CONFLICT>UNAVAILABLE`；每次远端 push 含 finalize 都是独立 `merge_publish` effect，不新增表。

### Requirement: P0 隔离证明：daemon 侧只承认登记的 run 进程身份，Linux 与 Windows 各自出证，失败即停止 C 路径。

#### Scenario: SC-VC-037

- **GIVEN** 获授权的受限服务身份与 agent 身份分离；请求体自报 pid/root、同 UID 其他 agent 连本 run 的 socket 或命名管道、socket fd 转给树外进程、原进程退出后 PID 复用。
- **WHEN** daemon 为本 run 填写 challenge 进程事实并接受连接。
- **THEN** SHALL 只使用 daemon 自 spawn 起登记的进程事实（Linux pidfd 与 SO_PEERCRED，Windows 命名管道 client pid 与令牌 SID），拒绝自报值与树外/他 run 连接。
- **AND** Linux 与 Windows 证据各自独立，缺一即 UNVERIFIED；缺 profile 必须 t.Fatalf，不得 skip 或裸 return。
- **AND** P0 失败即停止 C 路径；转 B 须另行提审，禁止运行时 silent fallback。
