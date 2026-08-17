---
id: CR-2026-045-prd
type: PRD
cr-ref: CR-2026-045
title: Runner Core：architecture-design 自动调度纵切
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-17T18:30:25+08:00
updated: 2026-08-17T18:38:06+08:00
---

# 1. 概述

当前 tools 已用版本化 Pipeline 声明节点顺序，用 Skill 承载业务步骤，并由 `crctl` 独占状态、门禁、账本、Git、审批和恢复；Multica 也已有 Agent 任务队列、`pipeline_run` / `pipeline_node_run`、CR/review/approval projector、网页审批和签名 grant 投递。但是，一条已审批需求仍需人逐节点判断并启动 `architecture-design`，现有 `crctl next` 只给出确定性下一步，不会在 Multica 中调度 Skill。

本 CR 建设一个有意收窄的 Runner Core，只验证 `architecture-design` 的五节点纵切：

```text
write-tech-design
→ review-tech-design / write-tech-design 回修
→ human_approval
→ approve-tech-design
→ push-progress
```

Core 复用同一 CR Git 权威、同一逻辑 pipeline run、现有 Agent 任务队列、签名审批链和 checkpoint 深原语。它不建设通用工作流引擎，不执行 Git 或账本写入，不解释 LLM 自然语言，不复制 `crctl` 的事务、门禁或 attempt 逻辑。

本 CR 是战略验证：验收通过只证明 architecture 纵切可运行，不自动授权 requirement、code、writeback 或 Runner Main Track。

# 2. 目标逻辑架构

## 2.1 Ponytail 优先级

需求、设计、实现与评审必须按以下顺序选择方案，并在首个足够方案处停止：

1. 复用现有能力。
2. 使用标准库。
3. 使用原生 Git/文件 API。
4. 使用已安装依赖。
5. 一行代码能够解决时不扩张。
6. 最小新增代码。

不得为未来 Pipeline、新节点类型、多机调度或指标分析预建通用抽象。

## 2.2 模块职责

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、`reviewLoop`、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出和失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

Runner Core 只拥有运行生命周期、节点调度、任务关联、等待审批、失败中止和幂等续跑。任何业务状态变化仍必须由对应 Skill 调用 `crctl` 产生。

# 3. 已经解决的基础设施

以下能力已经存在，本 CR 必须直接复用：

| 已有能力 | 当前职责 | 本 CR 的复用方式 |
|---|---|---|
| `architecture-design.pipeline.json` | 声明五节点顺序、prompt、失败动作和 reviewLoop | 作为节点顺序和回修合同的唯一来源 |
| `agent-skill-matrix.yml` | 为 active Skill 指定唯一 owner | 机械解析节点执行 Agent；缺失或不唯一时阻断 |
| `crctl status/next/gate/advance` | 状态、下一步、门禁和合法推进 | Runner 观察结果，不复制状态机 |
| `crctl review-record/attempt` | annotation、traceability、review-loop 与 attempt 原子记账 | Runner 不递增、不重置、不推测 attempt |
| `crctl approve --grant` | 验签、证据重核、审批记录和状态推进 | `approve-tech-design` Skill 继续作为唯一消费入口 |
| `crctl checkpoint` | 多仓提交、发布、lease、journal 与恢复 | `push-progress` Skill 继续作为唯一调用入口 |
| `pipeline_run` / `pipeline_node_run` | 运行与节点状态投影 | 复用现有表和同一逻辑 run，不建第二套运行表 |
| governance projector | 从 CR/review/approval 事件投影 run 和节点状态 | 手动路线与自动路线继续共用，不改变 Git 权威 |
| Agent task queue / TaskService | 入队、claim、start、complete、fail 与恢复 | 作为 Skill 节点的唯一执行通道 |
| `cr_id` / `pipeline_node_run_id` 归因列 | 关联任务、CR 和节点 | Runner 入队时写入现有归因，不建关联账本 |
| 网页审批与 `approval_record` | 校验人类身份、签发 Ed25519 grant、幂等批准 | Runner 不签名、不代替人类审批 |
| daemon grant delivery/ACK | 把 grant 投递到 `.crctl/grants/` 并确认 delivered | delivered 后才允许调度 approve Skill |
| CR gate UI | 显示阶段、blocker 和审批动作 | Core 不新增 Runner 控制台 |
| 手动 Skill + `crctl next` | 无 Runner 时的完整人工推进路线 | 作为兼容和回退路径保留 |

# 4. 本次应复用的最小改造

| 最小改造 | 归属 | 需求结果 |
|---|---|---|
| architecture 回放合同显式化 | 现有 Pipeline JSON | `reviewLoop.replayNodes` 明确列出回修和复审顺序，Runner 不根据 prompt 猜测 |
| 当前节点 registry 刷新 | 现有 governance 生成链 | 消除 tools 当前节点 UUID 与 Multica 旧 generated registry 的漂移；Core 只加载 architecture |
| Runner Core 调度器 | 现有 governance/service 边界 | 启动或接管同一 architecture run，逐节点入队、等待和中止 |
| Runner 窄入队路径 | 现有 TaskService/SQL query | 复用任务生命周期，在入队时关联 run/node/CR，不建第二任务系统 |
| 运行恢复元数据 | 现有 run 字段 | 保存启动模板 digest 和最小执行上下文；不建模板数据库 |
| projector/Runner 协作 | 现有 projector | projector 继续投影 Git 事件，Runner 继续调度；二者不得创建平行 run |
| 最小测试与文档 | 现有 governance/task 测试和人读入口 | 验证纵切、block 回修、审批、幂等、恢复和手动兼容 |

允许修改现有表约束或现有 JSON 字段以满足正确性，但必须优先使用 PostgreSQL 原生约束和已有 JSONB；不得新增运行表、幂等表、模板表、消息总线或事务框架。

# 5. 用户故事

- **US-01 路由 Agent**：当用户要求对一个 `requirement-approved` CR 进行架构设计时，希望选择现有 `architecture-design`，由 Runner Core 继续调度，而不是自行判断状态或写文件。
- **US-02 需求/开发负责人**：希望技术设计、自动评审和 block 回修按现有 Pipeline 自动连续执行，直到评审通过或权威 attempt 耗尽。
- **US-03 架构审批人**：希望 Runner 在人工审批前严格暂停；网页批准并投递签名 grant 后才继续。
- **US-04 CR 协作者**：希望服务重启或事件重复投递后继续同一 run，不重复生成 SDD、评审、审批或 checkpoint。
- **US-05 平台维护者**：希望 Core 复用现有表、TaskService、projector、Skill、`crctl` 和 checkpoint，不维护第二套状态机、Git 或事务实现。
- **US-06 手动路线使用者**：希望 Runner 关闭或未接管时，现有 Skill + `crctl next` 路线行为不变。

# 6. 功能需求

## FR-01 支持范围与启动

1. Core 只接受 `pipeline_id=architecture-design`，入口 CR 必须可由现有权威状态判定为 `requirement-approved`。
2. Pipeline 由路由 Agent 选择；Runner 不根据自然语言自行选择 Pipeline 或 Skill。
3. Core 只支持当前五个节点及其 `onFail=abort` 语义，不实现 `skip`、`code_generation`、通用表达式或其他 Pipeline。
4. 输入只包含现有 Pipeline 所需 `cr_id`、可选 `tech_context` 和由服务端确定的 workspace/user 上下文。
5. unsupported pipeline、未知 node kind、未知 Skill、owner 缺失/不唯一或入口状态不合法时零任务入队并 fail closed。

## FR-02 Pipeline 合同与 digest

1. 节点顺序、`ref`、prompt、`onFail`、reviewLoop 和 passCondition 只来自当前 tools Pipeline JSON。
2. `architecture-design.reviewLoop` 必须复用现有 code Pipeline 的机器合同：`replayPolicy=rerun-listed-nodes-in-order`，`replayNodes` 每项都包含 `nodeId`、`ref`、`purpose`，不得引入 refs 字符串数组等第二种 schema。
3. architecture 回放顺序固定为：
   - `{nodeId: 00000000-0000-0000-0016-000000000001, ref: write-tech-design, purpose: repair-sdd}`；
   - `{nodeId: 00000000-0000-0000-0016-000000000002, ref: review-tech-design, purpose: rerun-current-review}`。
4. 不得修改 requirement Pipeline；本 CR 不为其他 Pipeline 补 replayNodes。
5. Multica 使用的节点 ID/metadata 必须从本 CR 基线 tools 重新生成，旧 `0014` architecture UUID 不得继续作为当前合同。
6. run 启动时保存 Pipeline 合同 digest；恢复时当前 registry digest 不一致则阻断并转人工处理。
7. Core 不保存、加载或猜测旧模板版本。

## FR-03 单一逻辑 run

1. 同一 workspace、CR、pipeline 在任一时刻只允许一个非终态逻辑 run。
2. Core 启动时必须复用 projector 已创建的匹配 run；不存在时创建的 run 必须能被后续 projector 事件复用。
3. 两个并发 start，或 start 与 projector 首个 `tech-designing` 事件并发到达时，竞争方必须取得或重新读取同一个非终态 run；失败竞争不得留下第二个 run、首节点 attempt 或有效任务。具体使用 PostgreSQL 约束、事务锁或既有串行化原语由 SDD 决定。
4. Runner 和 projector 可更新同一 run 的各自字段，但不得互相覆盖已完成节点、attempt 历史或终态。
5. run 只保存调度所需 inputs、execution context、digest 和生命周期状态；CR 业务状态仍以 Git 为权威。
6. terminal run 不因迟到或重复事件重新打开。

## FR-04 Skill 节点调度

1. Skill owner 必须由 matrix 的唯一 `owns` 机械解析，Runner 不维护第二份 node-to-agent 映射。
2. Skill 节点通过现有 TaskService 入队，并在创建时关联 `cr_id`、`pipeline_node_run_id`、run/node 和 attempt。
3. 节点 prompt 必须来自固定 registry 合同，只注入声明输入和结构化前序输出；不得拼接未受控自然语言指令。
4. 同一 run/node/attempt 只能有一个有效任务；重复唤醒必须复用或忽略已有任务。
5. task failed、cancelled、超出既有重试策略或 Skill 返回技术失败时，node/run 进入失败终态，不自动跳过。
6. Skill 节点只有在“Agent task 得到该节点定义的成功终态”且“CR 权威后置条件已由现有结构化事件或确定性重读确认”两个条件同时满足时才算成功；task completed 本身不得触发后继节点。
7. 五节点后置条件如下，Runner 只核对结果，不自行补写证据：

| 节点 | task/人类结果 | 必须同时满足的 CR 权威后置条件 |
|---|---|---|
| `write-tech-design` | Agent task 成功 | `sdd.md` 已形成，CR 为 `tech-design-review-pending` |
| `review-tech-design` pass | Agent task 成功 | `review-annotations/sdd.yml` 为 pass、blockers 为空且 subject digest 当前，CR 保持 `tech-design-review-pending` |
| `review-tech-design` block | Agent task 返回结构化 repair 结果 | annotation 为 block、blockers 非空、CR 为 `tech-designing`，再按 replayNodes 回修 |
| `human_approval` | 无 Agent task；等待 grant delivered | pass review 仍当前且 CR 为 `tech-design-review-pending`；不得把网页记录本身当状态推进 |
| `approve-tech-design` approve | Agent task 成功 | `approval.yml#tech-design` 与当前证据一致，CR 为 `tech-design-reviewed` |
| `approve-tech-design` reject | `APPROVAL_DECLINED_ROLLED_BACK` 业务结果 | CR 已权威回退到 `tech-designing`，当前正向 run 中止 |
| `push-progress` | Agent task 成功 | 现有 checkpoint 结果为 `phase=complete` |

8. task 结果与权威后置条件不一致时，Runner 必须停在当前 node 并记录结构化错误；不得重试后继节点、伪造缺失证据或自行推进状态。

## FR-05 reviewLoop

1. `review-tech-design` 的 verdict、blockers 和 attempt 只消费 `crctl review-record` 产生的结构化事件/投影。
2. pass 且 blockers 为空时进入 `human_approval`；block 时只按 `replayNodes` 执行回修和复审。
3. Runner 不递增 attempt；`crctl` 返回 `LOOP_EXHAUSTED` 时 run 失败并保留最后 blocker。
4. 重启或重复 review 事件不得创建相同 attempt 的第二条节点记录或第二个任务。
5. Runner 不解析 blocker 文本决定路由，只把原始结构化 feedback 传给 Pipeline 声明的 repair Skill。

## FR-06 人工审批与 grant

1. 进入 `human_approval` 后 run 为 waiting，且不得提前创建 `approve-tech-design` 或 `push-progress` 任务。
2. 网页审批仍由现有 ApprovalService 校验人类 actor、stage 和 evidence digest，并签发 Ed25519 grant。
3. 只有 daemon 已把对应 grant 投递到 CR workspace 并 ACK 后，Runner 才调度现有 `approve-tech-design` Skill。
4. Runner 不生成、不修改、不验签 grant；`crctl approve --grant` 继续执行全部验证和状态推进。
5. 合法 approve 推进后才允许 checkpoint；合法 reject 按现有 `APPROVAL_DECLINED_ROLLED_BACK` 回退并中止当前正向 run，不执行 checkpoint。
6. grant 缺失、签名错误、归属不符、stage 错误或 evidence 漂移时 fail closed，保留可审计错误。

## FR-07 checkpoint 与完成

1. `approve-tech-design` 完成并由权威 CR 事实确认 `tech-design-reviewed` 后，Runner 才调度 `push-progress`。
2. `push-progress` 必须调用现有 checkpoint 深原语；Runner 不执行 commit、push、lease、journal 或恢复算法。
3. 只有 checkpoint 返回 `phase=complete` 后，architecture run 才可标记 completed。
4. checkpoint 失败时 CR 保持 `tech-design-reviewed`，run 保持可恢复失败/等待状态；重跑同一恢复入口不重新审批。

## FR-08 恢复与幂等

1. 服务启动时只扫描本 workspace 中 Runner Core 管理的非终态 architecture run。
2. 恢复必须根据 run/node/task 记录和当前 CR 结构化事实决定等待、继续或阻断，不凭自然语言输出猜测。
3. task terminal、CR status、review verdict、approval delivered 等重复或乱序通知不得重复调度。
4. 进程在入队前后、task terminal 前后、审批投递前后或 checkpoint 完成前后重启，最终只能形成一个有效节点执行结果。
5. current digest 不匹配、状态与节点不可调和或权威事实缺失时 fail closed，不自动重置 run。

## FR-09 兼容、观测与停用

1. Runner 未启用、未接管或关闭后，手动 Skill + `crctl next` 路线保持可用。
2. 手动路线产生的 CR/review/approval 事件继续由 projector 投影，不要求迁移历史 run。
3. 现有 CR gate UI 继续显示阶段和 blocker；本 CR 不新增 Runner 控制台。
4. 现有 run/node/task 记录必须足以定位当前节点、attempt、等待原因和失败原因。
5. Core 不生成价值评分、组织指标或新的统计账本。

## FR-10 最小采用边界

1. 不新增 Agent、Pipeline、Skill、公共工作流 DSL、运行表、幂等表、模板表、消息总线或第三方依赖。
2. Pipeline 只增加当前 architecture 回放所需机器字段，不复制 Skill 或 `crctl` 算法。
3. Skill 合同只在 Runner 输入/输出确有缺口时最小修订，不新增 Git、账本、attempt 或审批实现。
4. server 只增加纵切所需的固定调度逻辑和现有表/TaskService 接合，不实现通用 DAG/插件/表达式引擎。
5. README 只更新人读入口和停用/恢复说明，不复制 registry、状态机或数据库算法。

# 7. 非功能需求

- **NFR-01 Fail closed**：合同、owner、workspace、状态、证据、digest 或关联事实缺失/冲突时，零新增后继任务并给出结构化失败。
- **NFR-02 幂等**：重复请求、重复事件和服务重启不得造成重复有效 run、node attempt、Agent task、审批消费或 checkpoint。
- **NFR-03 权威隔离**：Runner 不直接写 CR 受控文件，不执行 Git，不改变 `crctl` 状态机、门禁和事务语义。
- **NFR-04 安全**：人工审批仍要求 TTY 或合法签名 grant；Runner 不持有签名私钥，不提供绕过入口。
- **NFR-05 可恢复**：恢复只向前复用现有记录和深原语 recoverCommand，不清理 journal、不回滚 Git、不猜模板。
- **NFR-06 兼容**：现有手动路线、projector 重放和 CR gate UI 回归通过。
- **NFR-07 跨平台**：涉及路径和进程调用时沿用现有 Windows/Linux 安全路径与 `shell:false` 约束。
- **NFR-08 最小成本**：新增生产依赖、运行表、模板表、消息总线和事务框架数量均为 0。

# 8. 验收标准

- **AC-01（FR-01/02）**：仅 `architecture-design` 可启动；unsupported pipeline、未知节点种类、未知 Skill 或 matrix owner 不唯一时返回结构化错误，且 run/node/task 零新增。
- **AC-02（FR-02）**：tools architecture reviewLoop 复用现有 `replayPolicy=rerun-listed-nodes-in-order` 与 `replayNodes[{nodeId,ref,purpose}]` schema；两项依次为 `…001/write-tech-design/repair-sdd`、`…002/review-tech-design/rerun-current-review`，静态合同测试逐字段通过；requirement Pipeline 节点和 reviewLoop 不变。
- **AC-03（FR-02）**：generated registry 使用当前 `0016` architecture UUID，生成源可追溯到本 CR tools commit；旧 `0014` 不再作为当前节点。
- **AC-04（FR-01/03/04）**：真实 `requirement-approved` CR 启动后，`write-tech-design` 和 `review-tech-design` 各只产生一个有效任务及关联 node run。
- **AC-05（FR-05）**：首次 review 返回 block 时，Runner 只按 `replayNodes` 调度一次 `write-tech-design` 回修和一次 `review-tech-design` 复审，并把 blocker 作为结构化 feedback 传入。
- **AC-06（FR-05）**：连续 block 达到 Pipeline maxAttempts 后，`crctl` 返回 `LOOP_EXHAUSTED`，run 失败、最后 blocker 可见且不进入人工审批。
- **AC-07（FR-05/06）**：复审 pass 后 run 进入 waiting_approval；在 grant delivered ACK 前无 approve/checkpoint 任务。
- **AC-08（FR-06）**：网页 approve → 签名 grant → daemon 投递/ACK → Runner 调度 `approve-tech-design` → Skill 调用 `crctl approve --grant` → CR 进入 `tech-design-reviewed`，链路中 Runner 无签名和受控文件写入。
- **AC-09（FR-06）**：合法 reject 产生权威回退并中止当前正向 run；签名错误、CR/stage/digest 不符时不推进状态、不执行 checkpoint。
- **AC-10（FR-07）**：checkpoint `phase=complete` 后 run 才 completed；checkpoint 故障时保持已审批 CR 状态，重跑恢复入口不重新执行设计、review 或审批。
- **AC-11（FR-08）**：对 task terminal、review、approval delivered 和 CR status 各重复投递至少两次，最终有效 run/node/task 数量及 CR 状态与单次投递相同。
- **AC-12（FR-08）**：在首个 Skill 入队后、review block 后、grant ACK 后和 checkpoint 调用后分别模拟服务重启，均继续同一 run 且无重复有效任务。
- **AC-13（FR-02/08）**：run 启动后替换 registry digest，恢复明确阻断；还原相同 digest 后可继续，不需要多版本模板仓库。
- **AC-14（FR-03/09）**：同一 CR 的手动事件与 Runner 事件由 projector 落入同一非终态 run；无第二套运行表或平行 run。
- **AC-15（FR-09）**：关闭 Runner 后，现有 `write-tech-design` → `review-tech-design` → 人工审批 → `approve-tech-design` → `push-progress` 手动路线回归通过。
- **AC-16（FR-10/NFR）**：静态检查证明 Agent、Pipeline、Skill、`crctl`、版本化脚本和 README 遵守第 2.2 节职责边界。
- **AC-17（FR-10/NFR）**：生产依赖、运行表、模板表、消息总线、通用 DSL/表达式解释器和事务框架新增数量均为 0。
- **AC-18（全范围）**：现有 crctl、TaskService、governance projector、approval grant、daemon delivery、CR gate UI 和手动 architecture Pipeline 相关回归全部通过。
- **AC-19（FR-04）**：对 `write-tech-design`、review pass/block、approve pass/reject 和 `push-progress` 分别注入“task/业务结果已到但对应权威后置条件缺失或陈旧”的场景；Runner 均停在当前 node、无后继任务且不补写任何 CR 证据。补齐真实权威后置条件后，同一 run 只继续一次。
- **AC-20（FR-03）**：分别并发发送两个相同 start，以及并发发送 start 与首个 `tech-designing` projector 事件；每种场景最终只有一个非终态 architecture run、一个首节点 attempt 和一个有效 `write-tech-design` 任务，迟到事件不重开终态 run。

# 9. 成功指标

- 一条真实 CR 可从 `requirement-approved` 自动运行到 architecture checkpoint complete，期间只在人工审批节点等待人。
- 首次 review block 后自动完成一次回修复审，无人工选择下一 Skill。
- 重复事件和指定重启窗口造成的重复有效任务数为 0。
- Runner 直接执行 Git、直接写受控账本、生成审批签名的次数均为 0。
- 新增运行表、模板表、消息总线、事务框架和生产依赖数量均为 0。
- Core 验收前注册 requirement/code/writeback Runner 扩展 CR 的数量为 0。

# 10. 依赖与风险

## 10.1 依赖

- tools 当前 `architecture-design.pipeline.json`、`agent-skill-matrix.yml`、Skill 合同及 `crctl` 状态/评审/审批/checkpoint 深原语。
- Multica 当前 `pipeline_run` / `pipeline_node_run`、governance projector、Agent task queue、TaskService、ApprovalService、daemon grant delivery 和 CR gate UI。
- workspace 已安装与 Multica registry 来源一致的 tools commit；Runner 启动前能取得当前合同 digest。
- 用于 E2E 的真实 daemon、Agent runtime、Ed25519 审批密钥和可发布 CR worktree。

## 10.2 风险

- **R-01 双写重复 run**：Runner 首节点前创建 run，而 projector 可在状态事件到达时找/建 run；必须保证同一逻辑 run 并发下仍唯一。
- **R-02 task terminal 被误当业务成功**：Agent task 完成不一定等于 Skill 已形成预期 CR 状态和证据；Runner 必须消费结构化权威结果后再继续。
- **R-03 模板漂移**：只存 digest 不保存旧模板，因此漂移时必须阻断，不能用当前模板续跑。
- **R-04 审批时序**：网页记录批准不等于 grant 已投递，更不等于 `crctl approve` 已执行；三者必须分开观察。
- **R-05 projector 回放覆盖 Runner 状态**：投影重放不得重开 terminal run、抹除 attempt 或把已完成节点改回 running。
- **R-06 自动重试扩大副作用**：Runner 不新增独立重试策略；只复用 TaskService 既有行为和 Pipeline/`crctl` 的 attempt 上限。
- **R-07 旧 Multica 本地基线**：本 CR 注册时本地 `main` 落后审计用 `origin/main`；SDD/实现前必须通过既有 freshness/同步流程核实真实基线，不能按旧 worktree 推断现状。
- **R-08 Core 被扩成通用引擎**：未知节点、其他 Pipeline 和未来语义直接拒绝，不在本 CR 增加抽象。

# 11. 范围排除

- 不自动执行 requirement、code、test、writeback 或四主 Pipeline 串联。
- 不修改 requirement Pipeline 的 reviewLoop 或补 CR-ID 逻辑。
- 不实现 `onFail=skip`、`code_generation`、DAG、并行分支、插件或通用 passCondition 解释器。
- 不新增 Pipeline DSL、运行表、幂等表、模板数据库、消息总线、WAL、补偿层或事务框架。
- 不让 Runner/Agent/Skill 直接执行 Git、写受控账本、递增 attempt 或推进状态。
- 不让 Runner 生成、修改、验签或代签审批 grant。
- 不建设 Runner 专用控制台、work-viewer、价值复盘 API、统计表或组织评分。
- 不提供多版本模板恢复；digest 漂移只阻断。
- 不把本 CR 验收自动解释为 Runner Main Track 立项批准。

# 12. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-17 | v0.2.0 | Ray | 回修 B-01～B-03：补五节点双重成功后置条件、并发 run 竞态验收、复用现有 replayNodes 机器 schema |
| 2026-08-17 | v0.1.0 | Ray | 初始草稿：architecture 五节点纵切、现有基础设施复用、最小调度接合与结果级验收 |
