# AIFI-45 授权内自治执行与有界修复 — tools 技术设计

> BUILD安全修正：未接可信平台current-head/revoke/claim与既有消费事务前，不允许live消费。历史独立receipt writer已撤回；grant→fresh proof→source子集通过后仍`EXECUTION_CONSUMPTION_REQUIRED`，预置receipt不可激活。以下消费/预算/恢复为目标设计，不是当前完成声明。真实CLI隔离PoC与受保护trust root仍按major调整验证，详见`isolation-evidence.md`/`build-evidence.md`。

> Gate2已按原文“确认 Gate 2”登记。BUILD发现的可信绑定/来源漏项已由用户明确采纳修订方向并授权“继续别停下来等指令”；普通模式不变，非Gate3/上线批准。
> BUILD补正的跨仓精确字段、来源bytes和当前绑定协议见[wire contract](wire-contract.md)，与本文共同约束实现。需求：[目标方案](../../../../docs/AIFI-45-CR流程减负目标方案.md)。
> 本轮开发采用 STDD，不注册或推进真实 CR；附件 §9.1/§11.2 的实施方式按用户明确要求调整，不据此绕过产品运行时门禁。
> `T`=sibling tools 仓，`M`=sibling multica 仓。设计不等于已实现；实际进展与验证只以phase-context/tasks及测试记录为准，不由本设计文字推定CLI/运行时已支持。

## Context

- 已核实 T HEAD=`9e41ad74ce631459bc007a29c3d0cdaaa1e49e75`，M HEAD=`f6e90ab8090c8a712c7fe2a324e977f10a39499c`。T 有既有未跟踪 `.crctl/`，M 工作树干净；均不等于线上版本。
- `T/skills/shared/crctl/scripts/crctl.mjs` 已有 Ed25519 阶段 grant、对象 evidence digest、相邻结果态幂等和 review-record 证据提交。旧签名串为 `v1|cr_id|stage|decision|approver|approved_at|evidence_digest`，不绑定 project/workspace、流程版本或修复身份，不能直接改名当完整授权包。
- `approval.yml` 是已消费审批结果，`review-loop.yml` 是现有 loop/cycle/attempt 历史。各 loop 上限不等于 CR 累计纠正性修复次数；首次/PASS 评审也可能计 loop attempt。reset 保留历史但当前 cycle 次数归零。
- `lib/durable-tx.mjs` 已有 CAS、before/after journal、提交标记和崩溃恢复；旧 approve/review/reset 的锁按操作分开，并无统一 CR 写锁。review-record 有隔离 index 提交，不能把普通 approve 或 checkpoint 误当相同能力。
- 四阶段 registry、node_id/executor 与 digest 已存在；不要重做。代码及回写的实际启动/wake/恢复仍需在 M 配套核实接通。
- 本轮 STDD 为 thorough，初评 17/17（跨仓预计 20+ 文件、1000+ 行、4+ 能力、高风险、数据/API、授权安全；是工作量初评，不是实现承诺）。无 model_tiers 配置，主会话设计，事实核对不是额外 planner 升档。
- JavaScript/Go 经验库 CLI 均返回 `[]`。历史 STDD 只作 L3 模式锚定，不复用旧批准、旧测试结果或历史缺陷断言。

## Decisions

### 1. 新合同显式 opt-in；保留旧状态图与审批路径

**方案**：新增不可变版本 `authorized-execution/v1`。新注册 CR 仅在完整配套能力已确认且明确试点时，在 `cr.md` 记录 `execution-contract`、可信 workspace/project 绑定及授权引用；无该字段视为 legacy。默认规则唯一放在 `T/skills/shared/crctl/gates.json` 的版本化 execution policy（默认累计 6、无进展 2），不在提示词和 Runner 各维护一个数值。

- 继续使用 `T/dir-graph.yaml` 的同一状态机，不另造状态机或复制每个版本的图。保留既有审批端点/状态及其条件；针对新 policy，既有 approve-* Skill 消费执行授权而不是再要求阶段人工确认；legacy 仍走原阶段审批。
- 旧 `crctl approve` 的TTY/阶段grant语义仅对legacy保持。所有写入口（包括approve/advance/review/reset及新原语）先从权威已提交注册/迁移事实读取合同：新policy不能用旧grant或TTY绕过新规则，删除本地cr.md字段也不能降级legacy；合同切换必须持可信迁移授权在同一CR锁内CAS提交。
- 新增 `authorization-bind` 和 `authorization-consume --stage` 深原语；后者通过既有对应阶段转移，审计显式 `basis=execution-authorization`，不得伪造approver或签发虚构的人类阶段批准。
- 模板中原 gate 节点增加 policy 条件的 admission 元数据；新 policy gate 可由授权裁决满足，缺少授权则只请求必要补充。原节点 ID 与 review executor 保留；节点类型、语义和 schema 必须由 emitter、Go generator/parser、Runner 同步理解并进入 digest，不能只改 label 或 prompt。
- `status/next/gate` 对新 policy 输出适用的授权缺口、累计消耗、停止原因及 receipt 引用；不得在缺授权、额度耗尽或独立验证未完成时建议“人工继续即可”。现有状态机声明数量不硬编码进新文档或测试。

**为什么**：允许在同一权威门禁内减少机械审批，而不把本次维护或 Agent 自报当审批旁路。

**备选排除**：全局删除 approvalStages 会追溯影响旧 CR；复制新流程图会双写；让 Agent 根据文本自行跳节点无法证明运行时已生效。

### 2. 平台持有可信原始授权，crctl 验签、绑定并消费

**新签名合同（跨仓唯一字段定义见本节）**：复用 Ed25519 和已安装公钥，新增独立签名域 `execution-authorization/v1\0`。服务端将 payload 序列化一次，签名域前缀加**原始 payload bytes**；传输 `{key_id,payload_b64,signature}`，消费者验签后解析同一 bytes，不在 Node/Go 各自重序列化。payload 内 key_id 必须与 envelope 一致，未知版本/字段类型、非法路径/整数、无可信公钥均 fail closed。私钥不进入仓库、任务或日志。字节级 golden fixture 覆盖中英文、分隔符、CRLF 和 tamper，不沿用旧 `v1|...` 签名域。

| payload 内容 | 约束 |
|---|---|
| schema、grant_id、purpose、key_id、issuer、approved_at、authorization_revision | purpose为initial/extend/migrate/sensitive/revoke；revision为同授权lineage递增整数，grant_id来自平台可信记录，不能按作者评论ID自报 |
| workspace_id、project_id、cr_id | 与当前验证绑定一致；同名 CR、错误 worktree、其他 workspace 不得复用 |
| source_event_id、source_digest、source_bindings、authorizer_user_id | 原请求来自认证人类owner/admin；每个scope字段关联原文明确内容、明确接受的引用附件snapshot或默认规则版本，平台核对原始source与绑定，不接受候选解释新增语义；task-token/转述不构成批准 |
| goal、scope_revision、allowed_repositories、allowed_paths、delivery_targets | 仓库身份用已验证绑定，不等同本机目录；路径必须规范化、禁越界与符号链接逃逸，正向清单不能隐含任意行为 |
| acceptance、prohibitions、sensitive_actions | 验收不可静默放宽；生产发布、破坏性数据、权限扩大、对外承诺/支出逐项限定动作、对象、环境和次数/额度，未列明即不授权 |
| policy_version、policy_digest、template_digest、target_version、target_spec_id | 与实际执行合同匹配；授权 scope 不等于中间每个 commit 的内容 hash；每次验证/交付仍绑定当前 subject |
| repair_limit、supersedes_grant、additional_repairs（适用时） | 非负安全整数；初始默认取有版本规则并明确接受；追加必须签出正增量且引用旧授权，累计消耗不归零 |

充分的**原始可信请求本身**可形成包，不要求用户再确认同一事实；平台只能绑定原请求中已有的结构化内容或明确已接受的默认规则。Agent 可调查事实、提出解释，不能把其补写内容签成原人类授权；关键语义不足才询问。自由文本没有可靠充分性证明时不默认为低风险。

**落点**：平台保存原始请求和签名包；T扩展既有`approval.yml.execution`，保存已验包、digest、适用范围、唯一活动head及追加/迁移/撤销历史。`cr.md`只保存合同与引用；grant文件在安装根`.crctl/grants/`，命名含可信scope hash+grant ID。旧stage grant不升级为新包。

**活动head与追加公式**：lineage固定为初始grant ID；`total_limit=initial.repair_limit + Σ(唯一已接受extend.additional_repairs)`，extend不再携带可重置的repair_limit。每份extend/scope替换/revoke引用精确前驱head和revision，在同一CR锁CAS接受；并发同前驱最多一份成功，另一份必须由有权者重新签发，不能自动改前驱。原grant重放只返回历史，不回滚活动scope/revision，不重复追加。更宽scope不重置预算；修复消耗始终来自累计准入历史。

**撤销与新鲜度**：首版不新增时钟到期功能，不宣称支持“过期grant”。显式撤销是同lineage的签名revoke revision；平台在新根任务入队/实际启动前验证其当前head，T在准入时核验同revision的可信dispatch attestation。平台失联/无法证明当前head时不允许新准入或敏感动作。较新revision已存在时旧ticket失效；已经授权并开始的不可逆动作不承诺瞬间回滚，收到撤销后只允许既有有界安全收尾、只读核验或补偿，禁止新副作用并通知维护者。撤销前已提交的消耗保留，未启动任务取消而不重派；已admitted但未执行的名额不因取消返还。此保守计次边界须Gate2明确接受。

**原文提取边界**：对已有可信自由文本事件，候选每个字段必须逐项引用原文span或已接受默认版本；独立验证者检查只是提取、没有新增语义后可形成签名包。无法证明充分则只补问欠缺内容，不要求重新确认原文已有事实；平台不直接信任作者候选。

**阶段消费**：共用锁内复验签名、活动head、scope/version、当前阶段/subject和独立证据；按`(grant_digest,stage,subject_digest)`写幂等receipt并与状态变化隔离提交。原授权可覆盖多个阶段，阶段receipt是系统应用事实，不是新人工批准。

**敏感动作消费**：额度聚合键为`(scope,lineage,action_scope_id,target,environment)`，**不含operation_id**；操作幂等键在聚合键上加operation_id。同操作重试返回原receipt，不同operation共享原次数/额度，换ID不能重新获额。续签沿同lineage/action_scope_id继承已消耗；扩额只能签显式增量。发布重试复用operation_id，下载/ACK不消费。

**备选排除**：仅把评论 UUID 放 CLI 参数、复用旧阶段 grant、ACK=已执行、作者自填 scope 或维护权限=业务授权，均不满足信任边界。

### 3. 一次逻辑修复先准入、后派发；额度在既有 CR 记录中裁决

新增 `repair-admit`（受控运行上下文）、`repair-status`（只读）和 `repair-assess`（独立评审证据）公开深原语。实施时在 shared crctl Skill 登记，权限不扩给作者伪造评审或协调者业务推进。

- `review-loop.yml` 增加 `execution.repair-history`：每项含 repair_id、不可变 origin-review 身份、repair_target、授权 digest、admission_tx、消费序号、subject、状态及 assessment 引用。`consumed` 从已提交 admission 条目推导，不另建可漂移计数；追加量从已验授权历史推导。
- 逻辑 origin 由触发纠正的**已接受独立评审/测试阻断事件**及其原始 run/node/attempt/task、对象摘要和 repair target 组成。平台沿用既有节点/任务身份传递，T 验证来源与该阻断匹配；repair_id 与 origin 一一绑定，不能靠换 ID、cycle 或模板版本使同一修复重新准入。原阻断跨恢复/supersede须携带原 origin。
- 调度身份来自平台已验证执行上下文，不接受 Agent 自报 UUID。必要的机器 dispatch attestation 复用签名通道但独立域 `execution-dispatch/v1\0`，只证明 workspace/project/run/node/task/template/subject/origin 归因，不授予业务范围或额度。
- 首次正常实施不扣额；进入纠正性 writer 执行前消费一次，随后失败也不返还。内部命令、提交、有界技术重试与同次修复的验证不另扣额，也不获得无限重试。
- 准入顺序：恢复该 CR 未决事务 → 校验当前授权/停机条件 → 查 origin/repair 幂等 → 校验额度 → 记录 admission 并提交 → 返回 `{repair_id,receipt_ref,committed_source,changed}`。同 origin 同语义重放返回旧 receipt；同 ID 不同 origin/subject/payload 明确冲突。已允许修复可完成验证，即使它已花完最后一个名额；禁止的是**新纠正性执行**，不是交付 PASS。
- Runner收到已提交receipt才入队；准入后入队前崩溃恢复同receipt，不重新消费。任务是否创建未知先查原identity，不另造repair ID。
- 拆分不可变origin/repair_id/原logical_step与当前执行binding。supersede接管必须用平台可信映射绑定旧run/node/根任务→新run/node和原receipt，T在锁内记录adoption receipt；不新增修复消费。原任务归因不被覆盖，新run只有经显式映射且当前subject/template/授权适用性重新验证后才能接收其结果。没有映射的旧run证据仅留历史；subject改变需新独立重验，不能用换key重派。
- 新 policy 的 review-record/reset/授权消费/额度追加/迁移等写入共用按可信 workspace+project+CR 命名的 admission ledger 锁；复用 durable-tx CAS/提交标记/恢复和 review-record 的 index 隔离。锁顺序固定“CR admission → 操作子事务”，不能反向取锁；不声称现有操作锁已经足够。
- 读取签名和业务 preflight 后，提交前必须在同一锁中复核 write-set CAS、最新授权、历史和证据 digest，避免锁外 TOCTOU。失败回滚本次 write-set/index，保留其他人改动；有第三值冲突或提交结果未知则技术中止，不能扣额后偷偷重试一次新修复。
- reset 仍可恢复旧 loop/cycle；新 policy 不通过 reset 获得新额度或取消停止决定。额度追加必须显式签授权，累计消耗与原历史保留。

**为什么**：Git 业务账本与平台 DB 不可能做单个跨进程事务，采用已提交准入 receipt + 原任务幂等恢复，而不宣称任意副作用 exactly-once。

**备选排除**：按报告/commit/测试数计费语义错误；仅平台内存计数会在恢复丢失；为所有项目建新总账或仅依赖 run 内唯一键不能覆盖跨 cycle/supersede。

### 4. 无进展必须有独立核验、稳定根因与可追溯证据

`repair-assess` 引用当前修复的独立 reviewer 身份、前后 subject、稳定 root_cause_ref 和已有测试/诊断/评审证据。进展仅有两类：可核验的验证结果改善；有效排除相关假设且新证据足以改变后续判断。每项都须指向具体 artifact/测试身份、前后结果和判断影响；自报改善、改日志措辞、重复同输入不算。

- 连续两次**已执行纠正性尝试**后同根因仍阻断且两次都无上述进展，持久化 `stopped:no-progress`，禁止新 admission 并附所需动作。
- 有真实进展可继续，不以 blocker 数量或同名 blocker 单独判断；额度仍累计。
- 缺独立评审、证据不适用、根因改名无解释或 assessment 未完成，返回“等待有效独立评估”，不得假设有进展、清零 streak 或放行。
- 判定语义由独立 reviewer 负责，crctl 验证来源、证据适用性及规则并存储裁决；不宣称纯计数器能够自动推断因果关系。改变 root_cause_ref 必须有独立诊断证据关联，不能避开两次停止。
- 无进展后的“继续”或cycle reset不解除停止。新增`repair-resume`须引用停止receipt/version、明确签名恢复授权（含改变路径及需要的追加量）和适用新证据的独立assessment；同一CR锁内CAS把该stop标为resolved并记录新progress_epoch，累计消耗及旧streak/stop历史均保留。新epoch只基于已核验的新信息开启，不能靠换措辞重置；相同恢复操作重放同receipt，不允许跳过额度再准入。
- 停机期间只允许复用已有证据的只读有界取证，沿既有节点时限/技术重试上限；需要新纠正性执行或副作用的诊断仍必须有显式恢复授权与余额，不能另开无界诊断循环。

### 5. 内容型文档与交付独立验证，不能仅删除文件检查

新 policy 的 gates 改为检查现有最小记录里的目标/范围/授权/结果/证据，以及必要长期规则更新，不强制每个 CR 复制 PRD+SDD+plan 套餐。旧 CR 仍按旧 gates。

- 现有 writer、reviewer、writeback Skill 和脚本同步支持内容型记录；`writeback-prd-sdd.mjs` 等不得继续假设源套餐必存在。长期规则仍回现有配置/契约/基线；平台级设计不强搬 specs，累积基线不能覆盖。
新旧policy内容检查对照（载体均复用现有记录/权威源，不新增全局规范副本）：

| 检查 | legacy | authorized-execution/v1 |
|---|---|---|
| 目标/范围/验收 | 既有PRD/SDD及阶段evidence | approval.yml.execution中的已签scope＋最小变更记录引用；scope revision/digest匹配 |
| 设计/计划理由 | 既有SDD/plan固定产物 | 最小记录中不能从代码推导的必要决策；重要独立决策才新增设计，gate检查内容不检查套餐数量 |
| 实施/任务 | 既有TASK索引与开发计划 | 当前机器任务输出及最小结果索引，不抄写Runner账本 |
| 验证/交付 | 阶段annotation、测试报告、release-subjects | 同等适用独立证据＋当前subject；机械例外按本节严格条件 |
| 回写 | 现有PRD/SDD分节累积脚本 | writer声明实际长期权威源和必要增量；无规则变化只归档最小记录，不制造PRD/SDD，累积基线不覆写 |

- reviewer检查真实diff、当前release-subjects与规范机器测试证据，作者不能靠PASS自报、task UUID标签或旧版本报告交付。
- 机械例外仅用于相同输入/工具下可证明无语义的变化，由不同执行身份的确定性检查产生证据。规则、输入、生成工具、授权、验收有语义变化，一律仍需独立评审，不能“生成可复现”就免审。
- `approval.yml` 的授权适用性、`review-loop.yml` 的消耗、release-subjects 的内容身份各有唯一用途，不能把 scope 不变等同代码证据始终适用。
- 发布失败仅恢复既有 checkpoint/merge/writeback 事务，不重新消费授权或修复名额；若业务修复确实需要新纠正性执行，按新 origin 正常准入。stage/release drift 的最小重验仍保留。

### 6. 上线、显式迁移和失效回退

配套发布按“代码/生成物/安装文本一致 → 隔离三路径与故障测试 → 显式新 CR 试点 → 独立验收 → 再扩展”。本轮本地测试不等于真实新 CR 试点或上线完成。

- 旧 run/CR 保留原合同、pin、授权和历史。切换必须绑定新授权、原策略/新策略 digest、已核实历史消耗、剩余额度及已有任务处理证据；历史无法核实不得静默迁移。
- 模板/权限/policy 改动进入 canonical registry 和生成校验，部署 gate 检查源 SHA、生成 digest、安装 Agent/Skill 版本和实际 Runner 二进制/开关；缺任一项标未就绪，不删除旧派发/恢复能力。
- 回退关闭新**准入**，不取消已消费历史或把新 CR 降级成无门禁 legacy。已 admitted 任务按原绑定安全恢复；新动作等待人工处置。

## Architecture

```text
认证人类原请求（充分范围 / 已接受默认）
  → M 保存原事件、签 execution-authorization/v1
  → 既有 daemon 可信传输、装公钥和grant、ACK（只表示送达）
  → T authorization-bind：验签、scope/version绑定、隔离事务提交
  → Runner 在阶段 gate 请求 T 业务裁决（不伪造人类阶段批准）
  → 正常 writer → 适用测试 → 独立 reviewer
      BLOCK → T repair-assess / repair-admit（锁内消耗一次）
        → 已提交receipt → M按原执行身份入队/恢复 → 验证 → 独立assessment
      PASS → 适用交付gate → 复用checkpoint/merge/writeback → 最小结果通知
      缺授权/上限/无进展/维护阻断 → 证据化停止 → 找对责任人
```

配套 [multica 设计](../../../multica/changes/2026-10-22-aifi-45-authorized-execution/design.md) 负责实际认证、DB入队、四阶段wake及通知；不复制本节签名或额度裁决字段定义。

### 拟修改范围与验证边界

| T 路径（已有，除注明外） | 责任 / 最小测试边界 |
|---|---|
| `skills/shared/crctl/scripts/crctl.mjs`、`gates.json`、`scripts/lib/durable-tx.mjs` | 新授权、修复准入和恢复；以公开 CLI + 隔离 Git/workspace 断言，不测私有 helper |
| `scripts/lib/workspace-transactions.mjs`、`summary-projectors.mjs`、`outbox-contract.mjs` | 已提交事实、公开status/next及事件适用性；跨操作CAS和发布恢复 |
| `dir-graph.yaml`、`pipeline-templates/*.pipeline.json`、`emit-registry.mjs` | 同一状态图、版本化gate元数据、完整digest；保留独立executor |
| `agent-skill-matrix.yml`、相关 `_index.yml`、Agent/Skill、writeback脚本 | 权限最小化、长期规则与新旧内容合同同步；节点数量按实际声明验证 |
| `skills/shared/crctl/scripts/test/*.test.mjs`、`output-guard/test/*.test.mjs`、`pipeline-templates/*.test.mjs` | 现有回归与新增隔离CLI/合同测试；不排除慢例，不把skip报告PASS |
| `README.md`、`AGENTS.md`、`ARCHITECTURE.md`及实际受影响契约 | 更新持续有效规则，不复制机器账本 |

### BUILD 切片建议（Gate 2 后才执行）

1. 先写跨语言签名/授权边界失败测试，最小实现绑定；旧 grant 回归保持。
2. 一条修复准入 RED→GREEN，再加入六次上限、锁/CAS、崩溃重放；随后加入独立进展评估。
3. 内容型gates/机械例外/旧CR兼容逐条测试；同步registry、模板、文档与生成消费合同。
4. M 实际wake+TaskService配套后进行三条代表路径及失效注入联合验证，独立审查再请求Gate3。

## Risks / Trade-offs

| 风险 | 缓解 / 明确限制 |
|---|---|
| 充分授权语义被模型扩大 | 可信原事件和版本化默认绑定；不清则只问关键取舍，不能自签候选 |
| 不同操作锁导致TOCTOU | 新policy公共CR锁、锁内CAS复核、隔离write-set、崩溃恢复；旧操作行为单独回归 |
| Git/DB之间存在不确定提交窗口 | 先持久化准入，再幂等入队；原identity查询恢复，不声称任意副作用exactly-once |
| 无进展涉及因果判断 | 独立reviewer＋具体证据＋未知fail-closed，不以作者措辞或计数替代 |
| 产物变化破坏门禁/回写 | writer、gates、writeback与新policy配套；legacy保持旧合同 |
| 先改文本而平台未部署 | 实际路由、安装和版本证明是启用前置；缺部署证据明确未验证 |
| 默认6并非最佳或费用保障 | 仅有版本的试运行初值，后续按真实结果校准，不暗改已授权上限 |
| 研发授权被误当上线授权 | 本轮仅本地规格/实现/隔离验证；生产、迁移、Git发布另需明确授权 |

## 证据与设计置信度

- L3 锚定：现有 Ed25519 grant、durable ledger transaction、review-record 幂等、task lineage 与旧 STDD 两个 change。新策略不伪装为旧协议兼容。
- 高置信：附件明示授权、6次、两次无进展、独立验证及12项AC。中置信：新命令/字段、准入锁组合、内容型gates实现，需Gate2审核和BUILD失效测试。
- 上述为Gate2前设计快照；Gate2已由原生CLI登记、普通BUILD进行中。组件代码/隔离执行证据见phase-context/build-evidence，完整业务TC和切片完成仍0；没有线上/真实CR试点。原Gate evidence不改，未自行Gate3。
- STDD `extract-proposal` 将 capability 误归 what_changes 且返回空能力/impact；已运行CLI并核对已批准canonical YAML，能力以该YAML为准。本轮不扩大去修改STDD产品。
