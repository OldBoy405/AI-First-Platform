# AI First 平台缺口修订与最小落地方案

> 文档性质：后续 CR 的 PRD/SDD 依据，不是实施授权，不替代 CR 审批。
> 实证基线：multica `082a753`（merge CR-2026-031）；tools 已与 `origin/custom/main` 同步至 `462c3e9`（merge CR-2026-044，第一父链含 CR-2026-042/043/044）；CR 台账 36 archived / 8 withdrawn / 0 在途。
> 基线状态（2026-08-17）：tools 本地已 `--ff-only` 快进到远端 CR-044（ahead/behind = 0/0），CR-042（R10-R13、唯一主治理 workflow、Pipeline 静态合同）与 CR-044（16 节点 code Pipeline、checkpoint/发布收敛）均已完整包含；crctl 全量 412/412、writeback 13/13、lint/矩阵/合同检查全部通过。实施 Runner CR 前的增量复验见 §3.2。
> 当前决策入口：本文件 + `docs/product/缺口清单-计划未做.md` + `docs/product/缺口清单-排除与条件触发.md`。较早的优先级和范围排除文档保留为历史来源；与本文件冲突时，以本文件的当前实证结论为准。

## 0. 执行摘要

当前最大的产品闭环缺口仍是 Pipeline Runner：Pipeline、Skill、`crctl`、审批、任务队列和投影 UI 都已存在，但平台不能把它们自动串成一条可暂停、可恢复的 CR 交付流程。

本轮不建设通用工作流引擎。最小路线是：

1. tools 基线已收敛（2026-08-17 与远端 CR-044 对齐，见 §3）；Multica 的 Pipeline 节点常量随 Runner Core CR 重新生成并锁定 source SHA。
2. 复用现有 Pipeline JSON、Agent/Skill 绑定、任务队列、审批链路、`crctl` 和两张运行表。
3. Runner 只做调度：启动运行、创建节点运行、入队、等待结果、按 Pipeline 回边、中止、续跑。
4. 状态、门禁、CAS、Git、账本、审批证据仍由 `crctl` 及既有链路负责。
5. 先用 `architecture-design` 做一个真实纵切；证明成立后再串联四条 CR 主 Pipeline。
6. 用现有时间戳和事件做一份价值复盘 Lite，不先建设 P3 大看板。

本轮只允许两个功能 CR：

- **Runner Core CR**：`architecture-design` 纵切。
- **Runner Main Track CR**：扩展到 requirement → architecture → code → writeback，并加入最小价值复盘。

如果 Runner Core 不能在现有表、现有任务队列和现有审批协议上完成，必须回到 SDD 修订，不能用新增事务框架、模板服务或通用消息总线绕过问题。

## 1. 目标、成功标准与非目标

### 1.1 目标

- 用户或路由 Agent 选择一条受支持的 Pipeline 后，平台自动推进到完成、人工审批等待或明确失败。
- 每个节点都能回答：执行哪个 Skill、由哪个 Agent 承担、关联哪个任务、当前 attempt、为什么停止。
- review 节点返回 block 时，严格按 Pipeline 的 `reviewLoop.replayNodes` 回修，轮次仍由 `crctl` 管理。
- 服务重启或重复事件不会产生第二个相同节点任务。
- 一条真实需求最终走完四条 CR 主 Pipeline，并保留现有 traceability、审批和 Git 权威语义。

### 1.2 成功标准

- 无人工逐节点复制 prompt 或手动判断下一 Skill。
- 人工只在既有审批节点、明确的 blocker 和不可恢复失败时介入。
- Runner 不直接写 `cr.md`、`_index.yml`、`traceability.yml`、Git 分支或审批文件。
- 同一 `(run_id, node_id, attempt)` 最多存在一个有效执行任务。
- Runner 关闭后，原有 IDE Agent + Skill + `crctl` 手动路线仍可工作。
- 复盘至少能给出完成时长、失败节点、review attempts、审批等待时长和任务用量，不新增指标表。

### 1.3 明确非目标

- DAG、并行分支、多机调度、通用工作流 DSL。
- 新 Pipeline 声明格式、模板数据库、运行时模板发布服务。
- 第二套状态机、门禁、CAS、Git 或 durable transaction。
- 让 LLM 输出成为账本或状态推进的直接权威。
- 一次实现 8 条 Pipeline；本轮只覆盖四条 CR 主 Pipeline。
- P3 成熟度总分、组织排名、Wiki、Skill Market 全量交付。
- 审批委托、per-project 审批策略、动态角色策略编辑器。

## 2. 逻辑架构边界

### 2.1 Ponytail 决策顺序

所有 PRD、SDD、TASK 和代码评审都按以下顺序停止在第一个足够方案：

1. 复用现有能力。
2. 标准库。
3. 原生 Git/文件 API。
4. 已安装依赖。
5. 一行代码。
6. 最小新增代码。

任何新表、新依赖、新协议、新后台服务或通用抽象，必须证明前五层都不能满足一个已经出现的验收场景；“以后可能需要”不是理由。

### 2.2 模块职责

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| **Agent** | 判断请求职责、选择 Pipeline/Skill、提供业务输入；无法确定时向人提问 | 状态机、Git 算法、受控文件写入、节点持久化 |
| **Pipeline** | 节点顺序、输入引用、`reviewLoop`、`onFail`、人工节点位置 | 复制 Skill 完整算法、手写账本、实现 Git/审批 |
| **Runner** | 运行生命周期、节点调度、任务关联、等待审批、失败中止、幂等续跑 | 业务设计判断、门禁解释、Git/账本写入、LLM 评审结论 |
| **Skill** | 业务判断、编排步骤、输入输出、失败语义、调用 `crctl`/版本化脚本 | 手写原子账本、重复实现 `crctl`、持有 Pipeline 全局状态 |
| **crctl** | 状态、门禁、CAS、受控账本写入、审计、原子提交、确定性状态查询 | 业务设计判断、选择产品路线、产生 LLM 评审结论 |
| **版本化脚本** | PRD/SDD/TASK/traceability 等确定性转换和校验 | 状态推进、人工审批、运行调度 |
| **Multica server** | 任务队列、Runner 行状态、审批 API、事件消费、权限 | 本地 Git 算法、解析或修改 CR 账本 |
| **daemon** | 领取既有任务、提供受控执行环境、上报任务和 CR 事件 | 决定 Pipeline 顺序、复制 Runner 状态机 |
| **README** | 人读流程总览、入口和故障处理索引 | 另一份可执行细节事实源 |

### 2.3 权威关系

```text
用户请求
  -> 路由 Agent 选择 Pipeline
  -> Pipeline JSON 决定节点顺序
  -> Runner 调度现有 Agent task
  -> Skill 做业务步骤并调用 crctl/版本化脚本
  -> crctl 写 Git 权威状态与证据
  -> daemon 上报既有 task/CR 事件
  -> Multica 投影运行状态和 UI
```

- Git + `crctl` 是 CR 业务状态权威。
- Pipeline JSON 是节点顺序权威。
- `agent-skill-matrix.yml` 是节点 Skill 责任归属权威。
- PostgreSQL 的 `pipeline_run` / `pipeline_node_run` 是可恢复的调度状态和读模型，不反向定义 CR 状态。
- Runner 不因数据库状态自行伪造 `crctl advance`。

## 3. 基线收敛

### 3.1 已完成（tools 侧，2026-08-17）

1. tools `custom/main` 已 `--ff-only` 快进：`8f53058`（CR-043）→ `462c3e9`（CR-044），与 `origin/custom/main` 一致（ahead/behind = 0/0）。
2. 祖先关系已核实：CR-041/042/043/044 均为当前 HEAD 祖先；主线第一父链顺序 CR-041 → CR-043 → CR-042 → CR-044。
3. 收敛后验证全部通过：lint-prompts R1-R13（0 findings）、skill matrix（56 active / 8 actors）、agents contract（9 agents）、Pipeline JSON 全部可解析、crctl 全量 412/412、writeback 13/13。
4. CR-042 交付已确认存在：`check-skill-matrix.yml` 已删除、唯一主治理 `crctl-ci.yml`、Pipeline 静态合同测试绿。
5. CR-044 交付已确认存在：code Pipeline 16 节点、checkpoint/发布收敛、TTY 审批、workspace freshness。

### 3.2 实施 CR 前仍需做的增量复验（multica 侧）

1. 从目标 tools 提交重新生成 Multica `gate_nodes_gen.go`/后续 registry，记录 source SHA；禁止继续使用文件中旧的 `tools@b6889ff` 指针。
2. 跑 Multica governance 生成器校验和现有审批/投影测试。
3. 在一个真实 daemon 环境完成 task claim → Skill → `crctl` outbox → server projection 冒烟。

以上动作不独立立项，作为 Runner Core CR 的第一个任务执行；若其中任一项失败，回到本节修复基线，不在 Runner 中兼容两套模板。

## 4. 已解决基础设施与最小改造

### 4.1 已解决，必须复用

| 能力 | 现有落点 | 本轮用法 |
|---|---|---|
| 8 条版本化 Pipeline JSON | `tools/pipeline-templates/` | 四条 CR 主 Pipeline 是本轮顺序事实源；不复制到 README |
| Agent/Skill 权限与责任矩阵 | `tools/agent-skill-matrix.yml` | 确定节点 Skill 的 owner；无唯一 owner 时 fail closed |
| 状态机、门禁、CAS、审计 | `crctl.mjs` + `gates.json` + tools `dir-graph.yaml` | Skill 继续调用；Runner 不解释 |
| `crctl next` | crctl 既有只读命令 | 人工诊断和恢复提示；不把它升级为第二个 Pipeline 解释器 |
| durable transaction / checkpoint / test / writeback | crctl 既有模块 | 原样复用，不在 server 重做 |
| `pipeline_run` / `pipeline_node_run` | migration 162 | 直接使用；Runner Core 默认不新增表 |
| `agent_task_queue.cr_id` / `pipeline_node_run_id` | migration 162 | 在 Runner 入队时写入，不再依赖事后猜测 |
| task claim/start/complete/fail | Multica TaskService + daemon API | 节点执行生命周期 |
| 签名审批与 daemon grant 路径 | governance approval + daemon polling | 人工门禁等待与恢复 |
| CR/review/approval 投影 | governance projector | 校验和展示 Git 权威事件 |
| CR gate UI | `cr-gate-card.tsx` | Runner Core 不新增流程 UI |
| 生成器模式 | `generate-gate-nodes.mjs` | 扩展为完整节点注册，不建模板服务 |
| Chat `/` Skill 选择和 prompt 注入 | `ChatInputCore` + slash skill + daemon prompt | 认定已实现；不再立“技能选择器从零实现”CR |
| usage、task timestamps、review detail | 既有任务与运行数据 | 价值复盘 Lite，不建指标表 |

### 4.2 本轮最小新增

1. **完整 CR Pipeline 生成注册表**：扩展现有生成器读取四条主 Pipeline 与 Agent/Skill 责任矩阵，生成只读 Go 数据；保留 source SHA/digest。
2. **Runner service**：在 Multica server 内增加一个窄服务，负责创建 run、推进一个节点、等待事件、恢复 stranded run。
3. **内部入队参数**：复用 TaskService 入队路径，增加内部可选的 `cr_id`、`pipeline_node_run_id` 和明确选中 Skill；不新建任务系统。
4. **事件接线**：task terminal、review projection、approval projection 完成后调用同一个 `AdvanceRun(runID)`；启动时/既有 scheduler 低频扫描仅补漏。
5. **一个启动入口**：增加最小 API 和既有客户端薄封装，让路由 Agent 或受权用户提交 `pipeline_id + cr_id/inputs`；不先做新页面。
6. **价值复盘查询**：直接聚合现有 run/node/task/approval 时间戳和 usage，先输出单次运行摘要。

### 4.3 明确不新增

- 数据库表、消息总线、模板服务、工作流依赖、分布式锁服务。
- server 侧 Git 库、YAML 账本编辑器、passCondition 解释器。
- 新的 Agent、Skill 或重复的 Pipeline 定义。
- 为 Runner 专建前端控制台。

## 5. Runner PRD 依据

### 5.1 用户故事

作为项目成员，我希望把一条已确认的 CR 交给平台后，平台按已版本化的 Pipeline 自动调用正确的 Agent/Skill，在评审失败时回修，在人工审批时暂停，并在服务恢复后继续，而不需要我逐节点复制命令或判断下一步。

### 5.2 功能需求

#### FR-01 启动与路由

- 路由 Agent 或有权限用户提交受支持的 `pipeline_id`、项目、可选 `cr_id` 和业务输入。
- Runner 只接受生成注册表中的 Pipeline。
- 高层 Pipeline 选择由 Agent/用户完成；节点到 Agent 的机械映射来自生成时冻结的 owner 关系。
- owner 未安装、无权限或不唯一时返回结构化 `ROUTE_UNRESOLVED`，不得猜测。

#### FR-02 模板固定

- 每个 run 记录生成注册表的 tools source SHA 和 template digest，放入现有 `execution_context`。
- 运行中的 run 使用启动时固定版本；新模板只影响新 run。
- 不保存第二份完整模板 JSON 到数据库。

#### FR-03 节点调度

- Runner 按 `nodes[]` 顺序创建/更新 `pipeline_node_run`。
- Skill/code 节点通过现有任务队列执行，并在入队时关联 `cr_id` 与 `pipeline_node_run_id`。
- `human_approval` 节点不创建 Agent task，只等待既有审批/CR 投影事件。
- 同一时刻一个 run 只允许一个 active node。

#### FR-04 完成与失败

- 普通任务 `completed` 后节点进入 `passed`，再推进下一节点。
- task `failed/cancelled` 时按 Pipeline `onFail` 执行：`abort` 结束 run，`skip` 记录原因并继续。
- review 节点以既有 review 事件中的 verdict/blockers 为准；Runner 不解析自然语言结论。
- Skill 未生成所需证据时，后续 `crctl` 门禁必须失败；Runner 不补造证据。

#### FR-05 reviewLoop

- verdict=block 时，Runner读取生成注册表中的 `replayNodes` 并按序重放。
- attempt 以 `crctl`/`review-loop.yml` 投影值为权威，数据库只镜像。
- 达到 `maxAttempts` 后 run 失败并保留 blocker，不自动扩大次数。

#### FR-06 人工审批

- 治理审批继续使用现有四阶段签名审批链路。
- Runner 只把 run 标为 `waiting_approval`，不签名、不决定审批人、不推进 CR 状态。
- 收到匹配 approval/status 事件后恢复。
- “选择代码评审 LLM”不是治理审批。MVP 复用项目/Agent 已配置的评审模型，不新增第五种签名审批或选择中心；确有逐次选择需求时另立小 PRD。

#### FR-07 幂等与恢复

- `AdvanceRun` 在数据库事务中锁定 run 和当前 node。
- 入队前查询该 node/attempt 已有关联任务；已有非终态或成功任务时不得重复创建。
- task、review、approval 事件可重复投递，重复推进必须 no-op。
- 服务启动或既有 scheduler 扫描 running/waiting run，调用同一个 `AdvanceRun`，不实现第二套恢复流程。

#### FR-08 四主 Pipeline 衔接

- Runner Core 只支持现有 CR 的 `architecture-design`。
- Main Track 在 Core 验收后支持：`requirement-authoring`、`architecture-design`、`code-implementation`、`feature-writeback`。
- Pipeline 之间按 CR 权威状态衔接；一个 Pipeline 完成后可创建下一个 run，但不得跨过人工审批。
- requirement 注册前 `cr_id` 可空；`requirement-register` 完成并产生权威 CR-ID 后，通过既有 CR 事件补入后续 context，不另建临时 CR 账本。

#### FR-09 可观测与复盘

- 每个 run 可查询当前节点、attempt、关联 task、等待原因和最近失败。
- 完成后返回总时长、各节点时长、review attempts、审批等待、失败/跳过节点、task usage。
- 第一版允许 API/日志/测试报告消费，不要求新 dashboard。

### 5.3 PRD 验收标准

- **AC-01**：从 `requirement-approved` 的真实 CR 启动 architecture run，自动完成 SDD → review → 审批等待 → approve → push。
- **AC-02**：构造 review block，Runner 只重放声明的修复节点，attempt 从 1 变 2，并最终 pass。
- **AC-03**：审批前 Runner 不创建后继任务；网页批准后继续，签名和证据校验仍走既有链路。
- **AC-04**：在“节点行已创建”“任务已入队”“任务已完成”“审批已记录”四个时点分别模拟重启，恢复后均不重复入队。
- **AC-05**：task fail + `onFail=abort` 使 run failed；`push-progress` 等 `onFail=skip` 节点失败时记录并继续。
- **AC-06**：Runner 代码不直接写受保护账本、不执行 Git、不实现 passCondition。
- **AC-07**：Main Track 用一条真实需求跑完四主 Pipeline 并归档，traceability 与审批证据完整。
- **AC-08**：运行摘要可回答耗时、失败点、review 次数、审批等待和 usage；不新增统计表。
- **AC-09**：关闭 Runner 后，现有手动 Skill + `crctl` 路线回归通过。

## 6. Runner SDD 依据

### 6.1 最小组件

| 组件 | 最小职责 | 复用点 |
|---|---|---|
| Pipeline registry generator | 读取 Pipeline JSON + matrix，规范化 CRLF，生成四主 Pipeline 节点/owner/reviewLoop/onFail/digest | 扩展现有 generator；不写第二个解析器 |
| Generated registry | 只读 Go 常量和查找函数 | 现有 `gate_nodes_gen.go` 模式 |
| PipelineRunner service | `StartRun`、`AdvanceRun`、`ResumeRuns` | 现有 DB pool、TaskService、governance projector |
| Task enqueue option | 给既有任务写 node/run 归因和选中 Skill | 现有 `agent_task_queue` 两列与 slash skill prompt 语义 |
| Event hooks | task/review/approval 终态后唤醒 Runner | 现有 CompleteTask/FailTask/crsync 流程 |
| Read API | 启动和查询 run | 现有 project route/auth；不建独立控制面 |

### 6.2 数据使用

默认不做新 migration：

- `pipeline_run.inputs`：保留用户业务输入，不放状态机副本。
- `pipeline_run.execution_context`：只放 `template_digest`、`tools_source_sha`、`project_id`、可选 `cr_id/spec_id` 和必要 worktree 引用。
- `pipeline_node_run.detail`：失败码、skip 原因、review 投影摘要；不存完整聊天上下文。
- `pipeline_node_run.output_note`：只有现有 Skill 真实生成 node note 时使用，不强制为每节点造文件。
- `agent_task_queue.pipeline_node_run_id`：Runner 创建任务时写入。

只有在 Runner Core 实测证明无法用行锁防止重复入队时，才允许评估一个窄的唯一约束；不得预先增加 idempotency 表。

### 6.3 调度算法

```text
AdvanceRun(runID):
  BEGIN
  锁定 pipeline_run
  读取固定 registry version 和当前 node
  若 run 终态 -> no-op
  若当前节点等待 task/review/approval -> no-op
  若当前节点已通过 -> 选择 Pipeline 中下一节点
  若下一节点是 human_approval -> 标记 waiting_approval
  否则检查同 node+attempt 是否已有任务
  无任务 -> 通过现有 TaskService 入队并关联 node
  COMMIT
```

review block 的唯一分支：

```text
review event(block, attempt=N)
  -> 读取该节点固定 reviewLoop.replayNodes
  -> 以 attempt=N+1 创建 replay 节点行
  -> 按原序调度
  -> 超 maxAttempts 则 failed
```

不在 Runner 内调用 Git，不在 Runner 内修改 attempt 账本，不从 LLM 文本猜 verdict。

### 6.4 节点输入

任务沿用现有 task context，只增加以下标识或等价字段：

```json
{
  "pipeline_run_id": "uuid",
  "pipeline_node_run_id": "uuid",
  "pipeline_id": "architecture-design",
  "node_ref": "write-tech-design",
  "attempt": 1,
  "cr_id": "CR-2026-NNN",
  "selected_skill": "write-tech-design"
}
```

业务材料仍由 Skill 按既有约定读取 PRD、SDD、TASK、review feedback 和 workspace；Runner 不把全部文件内容复制进数据库。

### 6.5 节点路由

- 用户请求到 Pipeline：由路由 Agent/用户决定。
- Pipeline 节点到 Skill：由 `node.ref` 决定。
- Skill 到责任 Agent：生成时按 `agent-skill-matrix.yml` 的 owner 决定。
- 责任 Agent 到 Multica agent row：复用 tools 安装时的稳定标识；找不到即失败。
- `can-call` 只用于 Agent 内部合法委派，不让 Runner自行选择替代 Agent。

### 6.6 投影与多写者边界

现有 governance projector 继续处理手动路线产生的 approval/review 节点。Runner 路线中：

- Runner 创建 pending/running 行。
- task 终态更新普通节点。
- projector 用同一 `(run_id,node_id,attempt)` 补充 review/approval 权威结果。
- 所有更新使用条件更新/upsert，终态不被较旧事件倒退。
- Git 状态冲突时标记 reconcile/failed，不能以 Runner DB 覆盖 Git。

### 6.7 安全与权限

- Start API 复用 workspace/project membership；Agent task token 只能启动其被授权的 Pipeline。
- 人工审批继续拒绝 task token。
- Runner 不获得本地 shell、Git 私钥或 approval signing key。
- Skill 执行边界继续由 daemon execenv、controlled-shell 和 `crctl` 保护。

### 6.8 最小测试集

1. generator：四主 Pipeline、CRLF/LF 等价、未知 kind/owner/重复 UUID 硬失败、source digest 稳定。
2. Runner unit：顺序、abort/skip、review replay、maxAttempts、approval wait。
3. DB integration：并发两次 `AdvanceRun` 只入队一次；重复 task/review/approval 事件 no-op。
4. 恢复：四个故障窗口各一例，不建设大 fault framework。
5. 真实集成：architecture-design block → repair → pass → approve。
6. Main Track E2E：一条真实 CR 四 Pipeline 归档。
7. 回归：手动 Skill + `crctl` 路线不受影响。

## 7. 分阶段落地

### Phase 0：基线与合同收敛（tools 侧已完成，2026-08-17）

tools 基线已与远端 CR-044 对齐并通过全部验证（见 §3.1）。剩余 multica 侧动作（registry 重生成、生成器校验、真机冒烟）作为 Runner Core CR 的第一个任务执行，见 §3.2。

### Phase 1：Runner Core CR

范围只含：

- 完整 registry 的最小生成能力，但只启用 `architecture-design`。
- `StartRun` / `AdvanceRun` / 恢复补扫。
- TaskService 节点归因。
- reviewLoop、治理审批、abort/skip。
- API 级查询，不建新页面。

退出条件：AC-01～AC-06 全过，至少一次真实 block 回修和一次网页审批。

### Phase 2：Runner Main Track CR

只在 Core 真实运行稳定后扩展：

- requirement 注册后补 CR-ID。
- code implementation 的 TASK/test/review 链。
- feature writeback/归档。
- 四 Pipeline 衔接。
- 单次运行价值复盘摘要。

不得借扩展机会抽象通用 DAG、动态插件或第九条 Pipeline。

### Phase 3：运行后复盘

完成至少 3 条真实 CR 或运行 4 周后再判断：

- 是否需要全局审批中心。
- 是否需要上下文用量 UI。
- 哪些斜杠命令有高频入口价值。
- 是否需要 P3 追溯视图、Wiki 或 Skill 草稿沉淀。

样本不足时只保留现有运行摘要，不建设成熟度评分。

## 8. 周边能力处置

### 8.1 价值复盘 Lite：S1

Runner Main Track 同批交付最小复盘，不单建 P3 平台：

- 完成/失败/取消结果。
- 总时长与节点时长。
- review attempts 与剩余 blocker。
- approval waiting duration。
- task usage、失败原因、context exhausted 次数。

先提供一个 run detail API/报告。只有重复使用证明需要跨 CR 比较时再建读视图；成熟度总分、排名和预测一律后置。

### 8.2 审批周边：条件触发

- 单项目审批卡、签名、角色校验已解决。
- 当前审批角色实际固定为 workspace owner/admin，不存在可直接套 UI 的动态策略配置。
- 当真实出现“至少 2 个项目同时有 pending approval”或审批人反馈漏办时，先做只读聚合列表和计数；点击仍回原审批卡操作。
- 角色策略只有在 CR owner 与 Multica user identity bridge 定义后另立 PRD；不得与审批中心或 Skill 选择器捆绑。

### 8.3 Skill 选择：已解决，降级验收

Team Agent、Private Ask 与通用 Chat 已复用 `ChatInputCore` 的 slash Skill 入口，daemon 已识别显式选择。当前不立功能 CR。

仅验证两个问题：

- 所选 Skill 是否在目标 Agent 权限内。
- “显式强调”是否足以满足用户；只有真实误用证明必须排除其他 Skill 时，才补 `skill_ids` 严格窄化。

### 8.4 tools 静态治理：先收敛，再查残余

CR-2026-042 已声明并验证 R10-R13、唯一主治理 workflow 等交付；本地分支停在更早合入的 CR-043，所以尚看不到这些变化。远端主线随后按 CR-043 → CR-042 → CR-044 收敛，并未最终遗漏 CR-042。当前动作是把本地基线快进到权威远端后复验，不是重开 CR-036，也不是把本地旧快照当成新的治理缺口。

基线对齐后运行现有 checker。只有仍有可复现的规则缺口时才登记小 CR，并随其保护的 Pipeline/Runner 合同一起交付，不能“随时并行”修改同一合同。

### 8.5 P3 与 Wiki：拆分

顺序如下，不捆绑：

1. Runner 自带价值复盘 Lite。
2. 有跨 CR 查询需求时做 traceability 只读视图。
3. 有知识维护频率和 owner 后做 Wiki maintain/query。
4. 有真实 Skill 复用和发布需求后做私有草稿 → 发布门禁 → Market。
5. 有至少 4 周可信数据后再讨论成熟度评分。

## 9. 条件触发项的最小档

| 能力 | 当前决定 | 最小档 | 触发条件 |
|---|---|---|---|
| work-viewer | 不做完整 viewer | changed files + commit/diff deep link | 非开发审批人无法判断证据 |
| 上下文管理 | 条件 backlog | 新会话继续；后续估算 usage | context exhausted/手动重开频繁 |
| 回复线程 | 条件 backlog | 引用回复或复用单层 Issue thread | 长讨论出现上下文错配 |
| Pipeline 斜杠命令 | 条件 backlog | `/进度`、`/工作流` 只读；Runner 后再写命令 | Runner 稳定且入口有高频需求 |
| 导出 Skill 草稿 | 条件 backlog | 选中消息生成私有 Markdown 草稿 | 同类流程被人工复用至少 3 次 |
| 恢复检查点 | 条件 backlog | 恢复到新分支 + 新会话，不删历史 | Runner 恢复仍不能覆盖真实失败 |
| 点踩反馈 | 条件 backlog | 一位负反馈 + 可选文本 + task/message id | 价值复盘无法解释失败原因 |
| mobile | 条件 backlog | 移动审批/只读状态，不做三模式 parity | 移动审批需求形成稳定使用量 |

## 10. 风险与最小控制

| 风险 | 最小控制 | 不采用方案 |
|---|---|---|
| tools/multica 模板漂移 | 生成 source SHA/digest + Phase 0 祖先验证 | 模板数据库、动态同步服务 |
| 重复任务 | DB 事务行锁 + 查询 node 关联任务 | 新 idempotency 服务 |
| projector 与 Runner 冲突 | 同自然键条件 upsert，Git 事件优先 | 第二套 CR 状态机 |
| Agent 报 completed 但产物不完整 | 后续 Skill 的 crctl gate fail closed | Runner 猜测文件内容 |
| run 永久挂起 | terminal event 唤醒 + startup/低频补扫 | 新消息总线 |
| 人工节点语义混杂 | 只把四阶段治理审批接签名链路 | 把所有选择都升级成审批类型 |
| scope 膨胀 | Core 只跑 architecture，Main Track 只跑四主 Pipeline | 8 Pipeline 一次全上 |

## 11. PRD/SDD 起草清单

### 11.1 PRD 必须回答

- 具体用户和当前人工断点是什么。
- 本 CR 只覆盖 Core 还是 Main Track。
- 哪些基础设施直接复用，哪些文件明确不改。
- 每条 FR 对应可运行 AC，尤其 block、approval、restart、duplicate event。
- 哪些指标用于上线后的价值复盘。
- 哪些能力明确不做，触发后才重评。

### 11.2 SDD 必须回答

- 生成注册表如何从 tools 权威数据产生并校验 source SHA/digest。
- `StartRun` / `AdvanceRun` 在哪些现有 service/transaction 中实现。
- node 如何绑定 task，如何防重复入队。
- task、review、approval 哪些事件唤醒同一个推进函数。
- projector 与 Runner 更新同一 node 时的条件更新规则。
- review attempt 如何从 `crctl` 权威投影，不在 DB 自增造事实。
- requirement-register 后如何补 CR-ID。
- 服务重启的补扫入口和上限。
- 为什么不需要新表、新依赖、新事务框架。

## 12. 最终执行序列

```text
Phase 0  tools 基线收敛（已完成 2026-08-17；multica registry 重生成随 Runner Core 首个任务）
   ↓
Runner Core CR  architecture-design 纵切
   - registry / task attribution / reviewLoop / approval / resume
   ↓
Runner Main Track CR  requirement → architecture → code → writeback
   - 四主 Pipeline E2E + 价值复盘 Lite
   ↓
真实运行 3 条 CR 或 4 周复盘
   ├─ 有并行审批压力：审批聚合中心
   ├─ 有高频入口需求：只读 slash commands
   ├─ 有重复经验资产：私有 Skill 草稿
   └─ 有稳定数据：traceability 视图 / Wiki / 后续组织智能
```

执行纪律只有一条：当前阶段的验收没有证明需求时，不提前建设下一阶段的抽象。

## 13. 历史后续工作核对（防遗漏台账）

> 来源：`docs/product/CR后续工作汇总-优先级清单.md`（CR-001~011 全部后续建议汇总）与 `docs/product/CR-F范围排除项-后续交付规划.md`（CR-F 排除项归宿）。以下条目是这两份历史清单中**未被本方案逐条覆盖**的部分。注册新 CR 起草 PRD 时，须逐条核对去向（纳入 / 条件触发 / 明确不做），防止被误判为遗漏。

### 13.1 已被覆盖或已完成（无需再处理）

| 历史条目 | 处置 |
|---|---|
| 1.1 CR-H Pipeline Runner | 本方案 S0-1/S0-2 |
| 1.2 CR-G（DC 协调者 + 合并转发） | 已完成：CR-2026-012 已归档（2026-08-04） |
| 1.3 ChatInput 与全局 store 解耦 | 已完成：随 CR-2026-012 落地（`ChatInputCore` + `ChatInputDraftAdapter`，Team Agent/Private Ask 复用） |
| 2.1 审批周边 | §8.2 条件触发 |
| 2.3 P3 组织智能 + Wiki | §8.5 拆分 |
| §4 中 1/2/3/4/5 与 §5 全部“故意不做” | 缺口清单-排除与条件触发 重分类（维持不做 / 排除完整档 / 条件 backlog / 移出排除） |
| §4-8 runner 轻量档池（多机调度） | §1.3 明确不做 |
| §4-6b Team Agent 附件接线 | 已完成：CR-2026-012 FR-8 附件已接线 |

### 13.2 部署前置验收（计划未做，非功能 CR）

原 §2.2 的 8 项真机补验：本机 daemon 执行链路完整回放、双浏览器 WS 跨会话、跨用户 @提及全链路、web+desktop 双端视觉、真实 commit-scan review 事件与三阶段真实驳回、`cr:updated` 徽标刷新、第二 workspace 注册拒绝、gitguard 三层拦截。

处置：作为“真实部署前 QA 关口”挂起，不进 Runner CR；部署环境就绪时按清单执行。

### 13.3 工具链收尾（计划未做，可并行）

原 §3 P2 六项：上游回馈 PR 整理、mdt_ 单轨化（PAT 回退退役）、59 Skill 安装器化、Traecli/Qoder 测试失败诊断、TaskExecutionCard 迷你门禁指示条、工具摘要聚合专用查询。

处置：不阻塞主流程，随时可并行；不进入本轮 Runner CR。

### 13.4 条件触发（计划未做）

原 §4 P3 剩余：timeline 分页、执行卡耗时实时跳秒、presenter 收件箱/站内信通知中心、多 worktree 并行执行、ContentEditor mention 目标过滤 prop、项目级成员模型、canApprove 补 `cr.owners` 身份桥、仓库转 private 时重核只读 PAT、`_history.yml` 分片/旁路缓存、悬浮 1:1 chat 展示性观察。

处置：触发条件见原文档 §4；本方案不提前建设。

### 13.5 结论

未被覆盖条目中**没有“明确不做”**，均为计划未做（QA 关口 / 工具链并行 / 条件触发）。注册 Runner CR 时无需纳入，但 PRD 应保留一节“历史后续工作核对”，逐条标注去向，防止后续会话把历史清单里的条目误判为当前缺口或遗漏。
