---
id: CR-2026-045-sdd
type: SDD
cr-ref: CR-2026-045
title: Runner Core：architecture-design 自动调度纵切 技术设计
status: draft
created: 2026-08-17T19:00:11+08:00
updated: 2026-08-17T19:24:02+08:00
---

# 1. 架构概览

## 1.1 目标

本设计只实现 `architecture-design` 五节点纵切，不实现通用工作流引擎：

```text
write-tech-design
→ review-tech-design / write-tech-design 回修
→ human_approval
→ approve-tech-design
→ push-progress
```

核心方案是一个幂等 `Reconcile(run)`：启动、CR/review 投影、Agent task terminal、grant ACK 和进程启动恢复都只唤醒同一 reconcile。reconcile 读取固定生成 registry、现有 run/node/task/CR 投影和审批记录，最多执行一个确定的下一动作；所有业务状态与 Git 副作用仍由 Agent 执行对应 Skill，再由 Skill 调用 `crctl`。

```text
路由 Agent（选择 architecture-design）
  → StartArchitecture API
  → Runner.Reconcile
  → 现有 TaskService / agent_task_queue
  → Agent 执行固定 Pipeline prompt + 已绑定 Skill
  → Skill 调用 crctl
  → daemon 上报 CR/review/checkpoint 事件
  → 现有 projector + Runner.Reconcile
  → human_approval 时暂停
  → 网页审批 → signed grant → daemon ACK
  → approve-tech-design task → crctl approve --grant
  → push-progress task → crctl checkpoint
```

## 1.2 Ponytail 决策

| 需求 | 采用 | 不采用 |
|---|---|---|
| 运行状态 | 现有 `pipeline_run` / `pipeline_node_run` | 新 run/幂等/恢复表 |
| 并发唯一性 | PostgreSQL partial unique indexes | 新 lease/WAL/分布式锁 |
| Pipeline 合同 | tools JSON 的生成快照 | server 自建 DSL/运行时读取任意模板 |
| digest | 现有 `execution_context` JSONB | 模板版本表/对象存储 |
| 任务执行 | 现有 TaskService、claim/start/complete/fail | 第二任务队列 |
| 唤醒 | 现有 event bus + grant ACK 直接唤醒 + 启动扫描 | 新消息总线/轮询系统 |
| 状态/Git | Skill → `crctl` | Runner 直接写 CR/Git |
| 前端 | 现有 CR gate UI | Runner 控制台 |

## 1.3 模块职责

| 模块 | 本 CR 中拥有 | 明确不拥有 |
|---|---|---|
| Agent | 选择 `architecture-design`；以 task-token 身份启动 run；执行 Skill | 状态机、Git、受控账本 |
| Pipeline | 五节点顺序、prompt、`reviewLoop.replayNodes`、abort | Skill 算法、运行事务 |
| Skill | 业务判断、文档编写/评审、调用 `crctl` | run 调度、账本算法 |
| `crctl` | 状态、门禁、attempt、approval、checkpoint、Git | Pipeline 选择、Agent task |
| 版本化脚本 | 从 tools 权威合同生成 canonical registry | 状态推进、人工审批 |
| Multica Runner | run/node 生命周期、幂等调度、等待和失败 | CR 业务状态、Git、签名、自然语言判断 |
| README | 启动/等待/恢复的人读入口 | registry、SQL、状态机副本 |

# 2. 已经解决的基础设施

| 已有能力 | 权威位置 | 直接复用方式 |
|---|---|---|
| architecture Pipeline 五节点 | `tools/pipeline-templates/architecture-design.pipeline.json` | 生成固定 Core registry |
| Skill owner/can-call | `tools/agent-skill-matrix.yml` | 生成时校验 logical owner 和 pipeline owner 权限 |
| Agent/Skill 定义 | `tools/agents/_index.yml`、`tools/skills/_index.yml` | 校验 active 状态，不在 server 复制台账 |
| 状态、门禁、review attempt | `crctl` + gates/Pipeline | Runner 只消费投影结果 |
| run/node 表 | Multica migration 162 | 原表复用；只增加正确性索引 |
| CR/review/approval projector | `internal/governance/gate_projection.go` | 与 Runner 更新同一逻辑 run |
| Agent task 生命周期 | `internal/service/task.go` | 新增一种窄 task context，不复制 claim/runtime/retry |
| 任务归因列 | `agent_task_queue.cr_id/pipeline_node_run_id` | 入队时直接关联，不再依赖 StartTask 后置猜测 |
| in-process event bus | `internal/events/bus.go` | 订阅既有 task terminal 和 `cr:updated` |
| 网页审批与 grant | `internal/governance/approval.go` | ACK 后直接唤醒 Runner；Runner 不签名/验签 |
| daemon task-token | Auth middleware 的 `mat_` 绑定 | Start API 只接受受信 `X-Agent-ID/X-Task-ID` |
| daemon CR roots | `MULTICA_CR_WORKSPACES` | pipeline task 在本机唯一解析对应 CR root |
| checkpoint | `push-progress` → `crctl checkpoint` | 只认 checkpoint 事件完成，不重建发布算法 |
| CR gate UI | `CrGateCard` / gates API | 无新前端 |

# 3. 本次应复用的最小改造

## 3.1 tools 合同

修改 `architecture-design.pipeline.json`：

1. 在 `review-tech-design.reviewLoop` 增加既有 schema：

```json
{
  "replayPolicy": "rerun-listed-nodes-in-order",
  "replayNodes": [
    {
      "nodeId": "00000000-0000-0000-0016-000000000001",
      "ref": "write-tech-design",
      "purpose": "repair-sdd"
    },
    {
      "nodeId": "00000000-0000-0000-0016-000000000002",
      "ref": "review-tech-design",
      "purpose": "rerun-current-review"
    }
  ]
}
```

2. 保留 5 个节点和所有 `onFail=abort`。
3. `review-tech-design`、`approve-tech-design`、`push-progress` 不再依赖某个本地 `node-1.md` 文件；每个任务只消费 `cr_id`，并通过现有 `crctl workspace inspect` 取得本机 operational workspace。这样服务重启或独立 Agent task 不需要新建节点输出文件协议。
4. requirement/code/writeback Pipeline 不变。

新增 `pipeline-templates/emit-registry.mjs`，使用 tools 已有 `yaml-subset.mjs` 读取 matrix/index，输出 canonical JSON：

```json
{
  "schema": "ai-first.pipeline-registry/architecture-core-v1",
  "pipeline": { "...": "architecture-design.pipeline.json 的 Core 字段" },
  "pipelineOwner": "dev-agent",
  "nodePermissions": [
    { "ref": "write-tech-design", "owner": "dev-agent", "pipelineOwnerCanCall": true }
  ]
}
```

该脚本只做确定性转换与硬校验：CRLF→LF、Pipeline active、Skill active、每个 Skill 恰有一个 owner、pipeline owner 对每个 Skill 有 `owns` 或 `can-call`。prompt 渲染只允许 `{{inputs.cr_id}}` 与 `{{inputs.tech_context}}` 两个字面 token，使用 `String.replaceAll`，`tech_context` 作为有长度上限的数据块附加；生成后仍有 `{{`/`}}` 即硬失败，不实现表达式解释器。失败非零退出，不输出空 registry。

## 3.2 单一生成 registry

扩展现有 `generate-gate-nodes.mjs`，调用 tools 的 `emit-registry.mjs --pipeline architecture-design`：

- 继续刷新 `ApprovalGateNodes` / `ReviewGateNodes`，修正旧 `0014` UUID 为当前 `0016`。
- 在同一个 `gate_nodes_gen.go` 中新增 `ArchitectureCoreRegistryJSON` 与其 canonical SHA-256。
- build/runtime 不读取 tools checkout；Multica 只消费已提交生成物。
- `--check` 忽略 source SHA 注释差异，但必须比较节点、prompt、permissions、replayLoop 和 digest。

不创建第二个 registry 生成器或运行时模板 loader。

## 3.3 数据库正确性约束

不新增表、列或外键。使用两个单语句 migration，均按仓库规则 `CONCURRENTLY`：

```sql
CREATE UNIQUE INDEX CONCURRENTLY ...
ON pipeline_run (workspace_id, pipeline_id, cr_id)
WHERE cr_id IS NOT NULL AND status IN ('running', 'waiting_approval');
```

```sql
CREATE UNIQUE INDEX CONCURRENTLY ...
ON agent_task_queue (pipeline_node_run_id)
WHERE pipeline_node_run_id IS NOT NULL
  AND status IN ('queued', 'deferred', 'dispatched', 'waiting_local_directory', 'running');
```

第一条保证 Runner start 与 projector find/create 竞态最多产生一个非终态 run；第二条保证同一 node attempt 最多一个有效任务，并允许既有 retry 在父任务终态后创建子任务。

`pipeline_node_run` 已有 `UNIQUE(run_id,node_id,attempt)`，直接复用。

## 3.4 Runner reconcile

新增 `internal/governance/runner.go`，只支持 compiled `architecture-design`。

### Start

固定 endpoint：

```http
POST /api/workspaces/{workspaceID}/pipeline-runs
{
  "pipeline_id": "architecture-design",
  "cr_id": "CR-YYYY-NNN",
  "inputs": { "tech_context": "optional" }
}
```

约束：

- 只接受 `X-Actor-Source=task_token`；`X-Agent-ID/X-Task-ID/X-Workspace-ID` 由现有 Auth middleware 盖写。
- CR 投影必须为 `requirement-approved` 且 `needs_reconcile=false`。
- source task、executor Agent 和 CR 必须属于同一 workspace。
- executor Agent 必须 active、runtime-bound，并启用 registry 中所有 Skill ref。
- registry 的 `pipelineOwner=dev-agent` 必须对每个节点拥有 `owns|can-call` 权限；节点 logical owner 单独写入 detail，用于审计，不拿 logical actor 字符串猜 Agent UUID。

run 输入：

```json
{
  "inputs": { "cr_id": "...", "tech_context": "..." },
  "execution_context": {
    "runner": "architecture-core/v1",
    "template_digest": "sha256:...",
    "pipeline_owner": "dev-agent",
    "executor_agent_id": "uuid",
    "source_task_id": "uuid"
  }
}
```

`started_by` 使用 task-token 已绑定的 `X-User-ID`。INSERT 依赖 partial unique index；唯一冲突后重读同一 run，不重试生成第二条。

### Reconcile

入口：`Reconcile(ctx, workspaceID, crID)`。步骤固定：

1. 读取该 CR 的唯一非终态 architecture run；无 run 则返回。
2. 对比 compiled digest 与 `execution_context.template_digest`；不同则将 run failed，错误 `TEMPLATE_DIGEST_MISMATCH`。
3. `SELECT ... FOR UPDATE` 当前 run，重读 CR、node、task、review、approval、checkpoint 投影。
4. 根据 §5 后置条件矩阵确定当前节点。
5. 若当前节点 task 尚在 active 状态，返回。
6. 若 task terminal 但权威后置条件尚未到，保持 node running，在 `detail.wait_reason=authority_postcondition` 后返回。
7. 若节点满足双重成功条件，mark passed 并创建/唤醒下一个节点。
8. task 最终失败且无 active retry 时，node/run failed。
9. 每次调用最多入队一个新 task；提交后依赖现有 TaskService 唤醒 daemon。

Runner 不解析 Agent final text、blocker 文本或 `crctl` stderr 来决定路由。

## 3.5 Pipeline task carrier

新增 `TaskService.EnqueuePipelineTask`，复用现有 Agent/runtime readiness、task queue、claim、retry、broadcast 和 daemon wakeup，只增加固定 context：

```json
{
  "type": "pipeline_node",
  "schema": "ai-first.pipeline-task/v1",
  "workspace_id": "uuid",
  "cr_id": "CR-YYYY-NNN",
  "run_id": "uuid",
  "node_id": "uuid",
  "pipeline_id": "architecture-design",
  "attempt": 1,
  "prompt": "registry 中固定 prompt 经声明输入替换后的文本"
}
```

入队时直接写现有 `cr_id` 与 `pipeline_node_run_id`。新增唯一 sqlc 查询 `CreatePipelineTask`，不是通用 enqueue builder：

1. 以 task-token 盖写的 `source_task_id` 为唯一 attribution 来源；source task 必须属于同一 workspace，且 `source_task.agent_id=executor_agent_id`。
2. 从 source task 原样复制 `originator_user_id`、`accountable_user_id`、`originator_source`、`delegated_from_task_id`、`rule_version_id`、`trigger_evidence_kind`、`trigger_evidence_ref_id`。Pipeline 后继节点是同一用户意图的系统延续，不重新分类 attribution，也不把 logical owner 当用户。
3. executor Agent/runtime 从同 workspace active Agent 行重读；`cr_id` 必须存在于同 workspace `cr` 投影；任一 JOIN/guard 不满足则 INSERT 0 行并返回 `RUNNER_ATTRIBUTION_INVALID`。
4. context、`cr_id`、`pipeline_node_run_id` 与完整 attribution snapshot 在同一 INSERT 中写入。当前 strict `originator→accountable` CHECK 继续机械兜底。
5. 既有 `CreateRetryTask` 已原样继承 attribution、`cr_id` 和 `pipeline_node_run_id`，不新增 retry 分支；只增加合同测试锁定其列清单仍完整。

handler claim path识别 `context.type=pipeline_node` 后填充 task wire 的 `Pipeline*` 字段。daemon 增加 `kindPipeline`：

- `BuildPrompt` 对 pipeline task 直接返回固定 `PipelinePrompt`，不进入 issue/chat/quick-create prompt。
- slim runtime brief 只保留 workspace context、Agent instructions、已绑定 Skills、受控 shell和通用安全规则；不渲染 Issue Metadata、comment workflow 或 quick-create 命令。
- 在 `CRWorkspaceRoots` 中按 `cr_id` 查找唯一 CR root；0 或多于 1 个均 fail closed。
- 复用 `MULTICA_CONTROLLED_SHELL_RULES`：按现有 `prepareCRGuard` 的同一相对关系从 `rules.json` 派生 `crctl.mjs`，不新增第二个路径配置；未配置/文件不存在时仅 pipeline task 返回 `PIPELINE_CRCTL_UNAVAILABLE`，普通任务不变。
- daemon 以 `spawnSync` 等价的 Go `exec.CommandContext(node, crctl, workspace, inspect, ...)` 形态（argv、`shell=false` 语义）对唯一 root 执行一次 `crctl workspace inspect`，要求全部 resources healthy 且 `operationalWorkspace` 非空、realpath 位于该 CR root 内。
- 将 `operationalWorkspace` 作为现有 `PrepareParams.LocalWorkDir`；给 pipeline task 合成 `localDirectoryAssignment` 后复用 `normalizeLocalPath`、realpath、`localPathLocks.Acquire`、local-directory sidecar/runtime-config cleanup，不开第二套路径锁。
- `CRCTL_WORKSPACE` 仍指向唯一 CR root；Agent cwd 为 operational workspace，现有 Pipeline prompt 再执行 inspect 取得同一权威路径。
- GC 继续使用 task-id 查询现有 task terminal 状态，不增加 GC 账本。

## 3.6 唤醒接线

复用现有同步 event bus：

- `cr:updated` → 从 payload 取 `cr_id` 调 `Reconcile`。
- `task:completed` / `task:failed` → 仅当 task 有 `pipeline_node_run_id` 时查 run 并 `Reconcile`。
- `HandleGrantsAck` 更新 `delivered_at` 后，按 ACK IDs 查询受影响 CR，直接调用 `Reconcile`；不新增会被 WS `SubscribeAll` 外发的内部事件。
- server 启动后一次性扫描 `runner=architecture-core/v1` 的非终态 run 并 `Reconcile`。

现有 review event 契约需要一个确定性扩充，且 outbox/commit-scan 两条既有来源必须 parity：

- `crctl review-record` 已经计算 canonical annotation、attempt、blockers、reviewed-at 和 LF-normalized subject digest，因此由它在同一 `event_kind=review` payload 写入 `attempt`、`blockers`、`reviewed_at`、`subject_sha256`。
- daemon `buildReviewPayload` 使用显式 stage→文件映射：`requirement→requirement.yml`、`tech-design→sdd.yml`、`code→code.yml`；读取先 CRLF→LF，再用现有安全 YAML 解析。
- blocker 读取兼容 canonical scalar 字符串和历史结构化对象，归一化为字符串列表；commit-scan 产生的 payload 字段集合与 crctl outbox 完全一致。
- outbox 优先仍保留；两来源同一 commit 的 payload parity 由测试锁定。旧 payload 缺任一 Core 字段时 projector 可维持旧 UI，但 Runner 必须以 `RUNNER_REVIEW_EVIDENCE_INCOMPLETE` fail closed。

这不新增事件通道、命令、状态、账本或判断；只是让同一既有 review 事件的两个采集来源投影相同的已持久化事实。

事件只是唤醒，不是权威事实；丢失唤醒由后续事件或启动扫描恢复。

# 4. 数据模型

## 4.1 run/node

现有字段分工：

| 字段 | 用法 |
|---|---|
| `pipeline_run.inputs` | `cr_id`、`tech_context` |
| `pipeline_run.execution_context` | runner schema、digest、pipeline owner、executor Agent、source task |
| `pipeline_run.status` | running / waiting_approval / completed / failed / cancelled |
| `pipeline_node_run.attempt` | 只投影 `crctl` review attempt；初始 write/approval/checkpoint 为 1 |
| `pipeline_node_run.detail` | review 顶层投影 + `runner` 命名空间；见下方多写规则 |
| `pipeline_node_run.output_note` | Core 不使用；不创建 node-N 文件协议 |

projector 与 Runner 共用同一 row，采用字段级 merge 而不是整段替换：

```json
{
  "verdict": "pass|block",
  "blockers": [],
  "attempt": 1,
  "reviewed_at": "...",
  "subject_sha256": "...",
  "runner": {
    "logical_owner": "dev-agent",
    "task_id": "uuid",
    "wait_reason": "authority_postcondition",
    "error": { "code": "...", "message": "..." }
  }
}
```

- Runner 只用 `jsonb_set(COALESCE(detail,'{}'), '{runner}', ...)` 更新 `detail.runner`。
- `applyReview` 用 `COALESCE(pipeline_node_run.detail,'{}') || $reviewPayload` 合并 review 顶层字段；payload schema 禁止 `runner` 键，因此保留 Runner 数据。
- review payload 右侧覆盖旧 verdict/blockers/attempt；Runner 从不覆盖这些键。
- terminal node/run 的 SQL predicate 禁止迟到 projector 或 Runner wake 重开。

两种写入顺序（Runner→review、review→Runner）与 projector replay 都必须得到同一 JSON。

## 4.2 attempt

- 初始 `write-tech-design` 与第一次 review 使用 attempt 1。
- review block 事件 attempt=N 后，`replayNodes` 的 repair/review 使用 attempt=N+1。
- Runner 不自增 canonical attempt；创建 repair node 前必须已观察 `crctl` 投影的 attempt=N。
- 当 projected canonical review 同时满足 `verdict=block`、`attempt=registry.maxAttempts` 时，Runner 标记 `RUNNER_LOOP_EXHAUSTED` 并停止，不创建 attempt+1。Runner只比较 crctl 已持久化的 attempt 与 Pipeline max，不递增账本、不解析 task stderr；tools 集成测试另行证明真实 `crctl attempt` 的 attempt+1 返回 `LOOP_EXHAUSTED`。

# 5. 节点后置条件

| 节点 | task/人类结果 | CR 权威事实 | 后继 |
|---|---|---|---|
| write | task completed | status=`tech-design-review-pending` | review |
| review pass | task completed | sdd review payload 字段齐全、pass、blockers=[]、attempt 当前，且 `subject_sha256` 等于当前 SDD LF digest 对应的 canonical 事件证据 | human approval |
| review block | task completed | sdd review payload 字段齐全、block、status=`tech-designing`、attempt=N；N=max 时 exhausted | N<max 才 replay write/review attempt N+1 |
| human approval | grant delivered | pass review 当前、status=`tech-design-review-pending` | approve Skill |
| approve | task completed | approval.yml 投影存在、status=`tech-design-reviewed` | push-progress |
| reject | task failed/business reject | approval decision=reject、status=`tech-designing` | run failed，不 checkpoint |
| push-progress | task completed | task started_at 后存在 checkpoint event，commit SHA 非空 | run completed |

任何只有 task completed、没有右侧权威事实的情况都只记录 `wait_reason`，不调度后继。checkpoint 关联必须晚于 push node `started_at`，避免误用需求阶段旧 checkpoint。

# 6. 接口与错误

| Code | 条件 | 副作用 |
|---|---|---|
| `RUNNER_UNSUPPORTED_PIPELINE` | 非 architecture | 零写入 |
| `RUNNER_REQUIRES_AGENT_ROUTE` | 非 task-token | 零写入 |
| `RUNNER_CR_NOT_READY` | CR 非 requirement-approved / needs_reconcile | 零任务 |
| `RUNNER_AGENT_NOT_READY` | executor 缺失、archived、无 runtime | 零任务 |
| `RUNNER_SKILL_MISSING` | 任一节点 Skill 未启用 | 零任务 |
| `RUNNER_CONTRACT_INVALID` | registry/node/matrix 不一致 | server 启动失败或 start 零写入 |
| `TEMPLATE_DIGEST_MISMATCH` | 恢复 digest 不同 | run failed，无新任务 |
| `RUNNER_AUTHORITY_MISMATCH` | task 与 CR 后置条件冲突 | 当前 node 停止，detail.runner 留证 |
| `RUNNER_ATTRIBUTION_INVALID` | source task / Agent / CR workspace guard 或 strict attribution 失败 | 零任务，node failed |
| `RUNNER_REVIEW_EVIDENCE_INCOMPLETE` | review payload 缺 attempt/blockers/subject | 不进入 repair/approval |
| `PIPELINE_CRCTL_UNAVAILABLE` | daemon 无法从现有 rules 路径派生 crctl | task failed，不降级 scratch 写入 |
| `RUNNER_TASK_FAILED` | 无有效 retry 的 task failed/cancelled | node/run failed |
| `RUNNER_LOOP_EXHAUSTED` | `crctl` 权威耗尽 | run failed，保留 blocker |

HTTP 重放同 start 返回同一 run 和 `changed=false`。

# 7. 安全、性能与恢复

- Runner start 只信 Auth middleware 盖写的 task-token headers，不信 body Agent/user/workspace ID。
- Runner 不读取私钥、不生成/验签 grant；只检查 `approval_record.delivered_at`，最终证据由 `crctl approve --grant` 验证。
- fixed registry prompt 只替换 `cr_id`/`tech_context` 两个声明 token；`tech_context` 做长度上限并作为数据块附加，不参与模板/节点选择。
- pipeline task 只在 `workspace inspect` 返回的 operational workspace 中运行，沿用现有 realpath/path lock/sidecar cleanup；绝不降级到 scratch 跨目录写。
- `Reconcile` 以 indexed run/CR/node/task 查询为主，每次最多入队一个 task，无后台全表轮询。
- startup scan 只取 Core 非终态 run；数量与在途 architecture CR 同阶。
- DB unique violation是正常竞态输家路径：重读，不循环重试。
- server crash 在 node upsert 与 task enqueue 之间时，下一次 reconcile 看到“running node 无 task”并补入队。
- task terminal 与 CR event 任意顺序到达都只形成部分后置条件；第二个唤醒完成推进。

# 8. 技术选型与替代方案

| 方案 | 决定 | 原因 |
|---|---|---|
| 通用 DAG/workflow 库 | 否 | Core 只有固定 5 节点，新增依赖和抽象无价值 |
| 独立 runner 表/事务层 | 否 | 现有 run/node + DB constraints 已足够 |
| server 运行时读取 tools | 否 | 部署不保证 sibling checkout；生成快照可审计 |
| 多版本 registry 存储 | 否 | Core digest 漂移直接 fail closed |
| polling worker | 否 | 已有 task/CR event + grant ACK + startup scan |
| logical owner 名称解析 Agent | 否 | system actor 无 Agent UUID，名称可改；使用 route Agent + Skill binding |
| node-N 本地文件 | 否 | 跨 task/重启不稳定；每节点 prompt 自足 |
| hidden Issue 承载 Pipeline task | 否 | 会污染产品域；task queue 已允许无 issue task |

# 9. FR 到技术实现映射

| FR | 技术条目 |
|---|---|
| FR-01 | §3.4 Start endpoint + 固定 registry |
| FR-02 | §3.1/3.2 tools emitter + generated digest |
| FR-03 | §3.3 indexes + §3.4 run upsert |
| FR-04 | §3.5 task context + §5 双重后置条件 |
| FR-05 | §3.1 replayNodes + §4.2 attempt |
| FR-06 | §3.6 grant ACK + §5 approval flow |
| FR-07 | §5 checkpoint correlation |
| FR-08 | §3.4 reconcile + §3.6 startup scan |
| FR-09 | 现有 projector/UI；Runner feature off 时无接管 |
| FR-10 | §1.2、§8 negative decisions |

覆盖率：10/10。

# 10. 变更面

## tools

- `pipeline-templates/architecture-design.pipeline.json`
- `pipeline-templates/emit-registry.mjs` + 窄测试
- `skills/shared/crctl/scripts/crctl.mjs`：只扩现有 review outbox 的确定性 payload + 回归测试
- `server/internal/daemon/crevents.go`：stage 映射、scalar blocker 和 payload parity 修复 + 回归测试
- 现有 Pipeline/contract tests

不改 Agent、Skill、crctl 子命令/状态/gates、状态机、README 算法说明。

## Multica

- `server/internal/governance/runner.go` + tests
- `server/internal/governance/gen/generate-gate-nodes.mjs`、生成物与现有 projector 小修
- 两个 CONCURRENTLY 单索引 migrations
- `server/internal/service/task.go`、`server/pkg/db/queries/agent.sql` + sqlc 生成物
- `server/internal/handler/daemon.go` claim context hydration
- `server/internal/daemon/{types.go,prompt.go,daemon.go}` 与 `execenv` pipeline kind
- `server/internal/governance/approval.go` ACK 唤醒
- `server/cmd/server/router.go` start/runner wiring
- `CUSTOM.md`

不改前端、移动端、CR gate UI、公共状态机和审批签名协议。

# 11. 测试设计

1. tools registry snapshot：replay schema、node UUID、owner/can-call、CRLF canonical digest。
2. generator `--check`：当前 tools 生成 `0016`，registry/digest 不漂移。
3. DB integration：双 start；start 与 projector 并发；同 node 双 enqueue；retry 父终态后可创建。
4. Runner table tests：happy path、block→repair→pass、canonical attempt=max exhausted、reject、checkpoint。
5. 双重后置条件：task terminal 与 CR/review/checkpoint 事件两种顺序；只到一半不前进；subject digest 缺失/陈旧阻断。
6. attribution：source snapshot 全字段复制、strict CHECK 通过、source/Agent/CR 任一跨 workspace 时 INSERT 0 行；retry 列清单保持。
7. detail merge：Runner→review、review→Runner、projector replay 三种顺序结果相同，`runner` 与 verdict/blockers 均不丢。
8. grant：记录未 delivered 不入队；ACK 后一次入队；坏 grant 由 Skill/`crctl` 拒绝后 run failed。
9. review event：commit-scan-only、outbox-only、同一 commit 双来源 parity；tech-design 必须读取 `sdd.yml`，scalar/structured blockers 归一化，digest/attempt 缺失硬失败。
10. daemon：pipeline context hydration、prompt 不含 issue/quick-create workflow、CR root 0/1/2 匹配、inspect 非 healthy、rules/crctl 缺失；LocalWorkDir 与现有 path lock/cleanup 生效。
11. restart：四个 PRD AC 指定窗口启动扫描，只有一个有效 task。
11. 回归：governance projector、TaskService claim/retry、approval、daemon、CR gate API。
12. tools 手动 architecture Pipeline 回归，Runner 未启动时行为不变。

数据库测试必须在真实 PostgreSQL 下看到 `=== RUN` / `--- PASS`，不能把 TestMain skip 当通过。

# 12. 风险与缓解

| 风险 | 缓解 |
|---|---|
| projector 覆盖 run waiting/running | Runner 不以单一 run.status 决定业务后继；每次重算节点/CR事实，UPDATE 不回开 terminal |
| Agent task 完成早于 CR event | 双重后置条件等待第二个唤醒 |
| attribution 新写路径漂移 | 单一 INSERT 从 source task 复制完整 snapshot，strict DB CHECK + 列清单测试 |
| detail 多写覆盖 | review 顶层 merge + `detail.runner` 命名空间，双顺序/replay 测试 |
| matrix logical owner 无 runtime Agent | registry 保留 logical owner；route Agent UUID 作为 executor，并校验 Skill bindings |
| 多个 CR roots 命中同 ID | daemon fail closed，不取第一个 |
| provider sandbox 拒绝跨目录写 | inspect 后 operational workspace 作为现有 LocalWorkDir，并复用 realpath lock/cleanup |
| review outbox 信息不足 | crctl 唯一写者投影 canonical attempt/blockers/subject；legacy payload 对 Runner fail closed |
| 老 checkpoint 被误认 | occurred_at 必须不早于 push node started_at |
| tools 部署漂移 | compiled digest 不同即 run failed，不猜旧模板 |
| generated registry 过大 | Core 只嵌 architecture 五节点；不生成其他 Pipeline |
| 新 task context 侵入 daemon | 单一 `pipeline_node` 分支，不修改现有 issue/chat/quick-create/autopilot 分支 |

# 13. Prompt 采纳影响

本 CR 不修改 `crctl.mjs` 的命令 dispatch、CLI 参数或 `controlled-shell/rules.json#protectedPaths.deny`，因此无需新增“应改为调用新 crctl 子命令”的 Skill。B04 回修只在现有 `review-record` 成功后 outbox payload 中投影它刚刚原子持久化的 canonical attempt/blockers/reviewed-at/subject digest，不新增业务判断或 prompt 调用面。Pipeline prompt 只改为每节点独立调用既有 `workspace inspect`，不新增状态/Git命令。

# 14. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-17 | v0.3.0 | Ray | 回修 SDD-B05：commit-scan 与 outbox review payload parity、显式 stage 文件映射和 blocker 归一化 |
| 2026-08-17 | v0.2.0 | Ray | 回修 SDD-B01～B04：source attribution snapshot、detail.runner merge、operational LocalWorkDir、canonical review outbox |
| 2026-08-17 | v0.1.0 | Ray | 初稿：固定 architecture registry、单一 reconcile、现有 TaskService task carrier、DB 原生唯一约束、grant/checkpoint 接合 |
