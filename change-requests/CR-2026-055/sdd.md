---
id: CR-2026-055-sdd
type: SDD
cr-ref: CR-2026-055
title: 评审分层最小改造技术设计
owner: Ray
owner-role: development
target-version: tbd
status: draft
created: 2026-08-29T22:45:00+08:00
updated: 2026-08-29T22:45:00+08:00
---

# 1. 架构概览

## 1.1 设计目标

本 CR 修改的是 sibling `../tools/` 方法论包的提示词合同、Pipeline 输入传递、Agent 权限声明和既有结构测试，不修改业务仓代码。目标是把“评审需要哪些事实”和“事实由哪个评审阶段负责”落实到现有分层中：

```text
PRD
  -> review-requirement / approve-requirement
  -> write-tech-design
  -> review-tech-design
       - 全量检查 8 个适用维度
       - AC 设计落点/可达性/可观测结果
       - SDD 明确引用的既有代码事实
  -> approve-tech-design
  -> write-dev-plan / write-dev-tasks
  -> review-dev-plan
       - SDD/AC 到 plan/TASK 的翻译增量
       - TASK 新造事实/责任边界/验收组合证明
       - SDD 反证时走 UPSTREAM
  -> approve-dev-start / implement-code
```

实现遵循现有 `tools/ARCHITECTURE.md` 的依赖方向：Pipeline 只编排和传参，Skill 负责业务判断，`crctl` 继续负责状态、评审账本、CAS、attempt 和 traceability。新设计不增加状态、Pipeline 节点、账本、payload 字段、digest、缓存、事务框架或 Agent。

## 1.2 参与模块与职责

| 模块 | 本 CR 变化 | 责任边界 |
|---|---|---|
| `skills/develop/review-tech-design/SKILL.md` | 增加输入合同、AC 闭环、SDD 自引用事实、首轮全量和回修规则 | 只做技术设计业务评审；不写 canonical annotation，不推进状态 |
| `skills/develop/review-dev-plan/SKILL.md` | 增加输入合同和 SDD/AC→plan/TASK 增量检查 | 只做计划/TASK 业务评审；不重复无差别重审 SDD |
| `skills/develop/write-tech-design/SKILL.md` | 约束 SDD 输出每个 AC 的设计落点、可观测结果、可达性说明 | 生成/回修 SDD；状态和账本仍经 `crctl` |
| `skills/shared/controlled-shell/SKILL.md` | 把两个 reviewer 纳入既有只读 Git 取证合同说明 | 只声明既有受控能力的调用边界；不改白名单 |
| `agent-skill-matrix.yml` | `quality-reviewer-agent.can-call` 增加 `controlled-shell` | 只补权限关系；不赋予审批、写入或状态权限 |
| `pipeline-templates/architecture-design.pipeline.json` | review-tech-design 调用原样传递 `resources` | 只消费 workspace inspect 结果，不复制评审算法 |
| `pipeline-templates/code-implementation.pipeline.json` | review-dev-plan 从 node-1 execution_context 原样传递 `resources` | 保持 16 节点、双轨路由和回放顺序 |
| `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | 增加合同、传参、权限和禁止范围断言 | 结构回归，不执行 LLM 评审、不新增测试框架 |

## 1.3 数据流与权威路径

`architecture-design` 和 `code-implementation` 的首个写入节点都执行一次 `crctl workspace inspect`。它返回：

- `operationalWorkspace`：knowledge-base CR worktree，作为 PRD/SDD/plan/TASK 等过程文档的业务权威路径；
- `resources[]`：各 active repository 的资源记录，至少包含 `repo`、`worktreePath`，实际还可能包含 `branch`、`classification` 等运行时字段。

本 CR 的 reviewer 传参规则如下：

```text
workspace <- workspace inspect.operationalWorkspace
resources <- workspace inspect.resources
```

Skill 可以读取：

```text
workspace/change-requests/{cr_id}/prd.md
workspace/change-requests/{cr_id}/sdd.md
workspace/change-requests/{cr_id}/plan.md
workspace/change-requests/{cr_id}/tasks/
```

需要核实既有代码事实时，只能按 `resources[].worktreePath` 找到目标仓根目录。Skill 不拼接 `.rayai-worktrees`，不回退主工作区，不使用会话中最近读过的其他仓库，也不把 `tools` 仓的事实替代其他目标仓事实。

`review-record` 仍是评审判断的唯一 canonical 写入入口。模型只产生既有 schema 的临时 payload，随后由 `crctl review-record` 写入 `review-annotations/{stage}`、`review-loop.yml` 和 `traceability.yml`。本 CR 不增加 payload 字段；事实证据写入既有 `dimensions` 或 `blockers` 字符串。

## 1.4 依赖方向

```text
目标 workspace
   -> workspace inspect / resources
   -> Pipeline prompt
   -> reviewer Skill 输入合同
   -> controlled-shell 只读取证
   -> LLM 业务判断
   -> .crctl/tmp/review-*.yml
   -> crctl review-record
   -> annotation + review-loop + traceability
```

依赖方向保持单向：

- Pipeline 不调用 `crctl review-record`，不复制评审维度和回修算法；
- Skill 不直接编辑 `cr.md`、`_backlog.yml`、`review-annotations` 或 `review-loop.yml`；
- `controlled-shell` 不拥有状态推进和账本写入能力；
- `crctl` 不理解 AC、SDD 或 TASK 的自然语言语义；
- 结构测试只读取 Pipeline、Skill 和权限声明，不改变生产运行时。

## 1.5 架构不变量核对

| 不变量 | 设计保证 |
|---|---|
| 状态单一写者 | `review-tech-design` 和 `review-dev-plan` 仍只描述调用既有 `crctl advance` 分流；本 CR 不增加状态或状态写入口 |
| 账本单一写入通道 | 评审仍使用临时 payload + `crctl review-record`，不手工写 canonical annotation、review-loop 或 traceability |
| 零第三方依赖 | 仅修改 Markdown、JSON、YAML 权限声明和既有 Node `node:test` 文件；不引入包 |
| 行尾与硬失败纪律 | 本 CR 不增加账本解析代码；测试读取文本时继续先做 CRLF→LF 规范化 |
| Git 是权威 | 评审文件和状态推进仍由现有 `crctl` 事务/提交路径负责 |
| 人工审批无旁路 | reviewer 只读取，不获得 `approve-*`、状态或账本写权限 |

## 1.6 既有实现事实证据

本 SDD 引用的既有实现事实已在目标 `tools` worktree 核实：

| repo | commit SHA | relative path | stable symbol/对象 | 核实结论 |
|---|---|---|---|---|
| `tools` | `fdc40b0b3fcaaa803a40df58af7536849ad64546` | `skills/develop/review-tech-design/SKILL.md` | `review-tech-design` / `参数`、`Step 2` | 当前只有 `cr_id`、`reviewer`、`self_repair_attempt`，维度已有 8 项语义但未包含本 CR 要求的 AC/事实合同 |
| `tools` | `fdc40b0b3fcaaa803a40df58af7536849ad64546` | `skills/develop/review-dev-plan/SKILL.md` | `review-dev-plan` / `参数`、`Step 2` | 当前已有八类 plan/TASK 维度，但未声明 `workspace/resources`，也未明确 TASK 新造事实和责任边界核验 |
| `tools` | `fdc40b0b3fcaaa803a40df58af7536849ad64546` | `pipeline-templates/architecture-design.pipeline.json` | node `...0002` / `review-tech-design` | 当前传递 `workspace`、反馈和轮次，但没有传递 `resources` |
| `tools` | `fdc40b0b3fcaaa803a40df58af7536849ad64546` | `pipeline-templates/code-implementation.pipeline.json` | node `...0014` / `review-dev-plan` | 当前从 node-1 传递 workspace，但没有传递 `execution_context.resources` |
| `tools` | `fdc40b0b3fcaaa803a40df58af7536849ad64546` | `agent-skill-matrix.yml` | `quality-reviewer-agent` | 当前可调用评审相关 Skill，但 `can-call` 没有 `controlled-shell` |
| `tools` | `fdc40b0b3fcaaa803a40df58af7536849ad64546` | `skills/shared/controlled-shell/rules.json` | `git.diff/log/rev-parse` 规则 | 现有只读 Git 规则已经存在；本 CR 不修改该文件 |
| `tools` | `fdc40b0b3fcaaa803a40df58af7536849ad64546` | `skills/shared/crctl/scripts/crctl.mjs` | `cmdReviewRecord` | 现有 review-record 已按 stage 写 annotation、review-loop、traceability，并为 requirement/tech-design/dev-plan 写 subject digest；本 CR 不修改该文件 |
| `tools` | `fdc40b0b3fcaaa803a40df58af7536849ad64546` | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | architecture/code pipeline tests | 已有节点顺序、reviewLoop、权限和禁止范围测试，可增量扩展 |

由于本 CR 没有修改 `crctl.mjs` 的 dispatch，也没有修改 `rules.json#protectedPaths.deny`，不新增“Prompt 采纳影响”章节；该条件性章节为 N/A，不掩盖任何已声明的既有实现依赖。

# 2. 数据模型

## 2.1 不新增持久化实体

本 CR 不新增数据库表、YAML 文件、JSON ledger、缓存或索引。既有数据模型继续使用：

```text
change-requests/{cr_id}/prd.md
change-requests/{cr_id}/sdd.md
change-requests/{cr_id}/plan.md
change-requests/{cr_id}/tasks/_index.yml
change-requests/{cr_id}/review-annotations/{requirement|sdd|dev-plan|code}.yml
change-requests/{cr_id}/review-loop.yml
change-requests/{cr_id}/traceability.yml
```

新增或改写的只是这些既有文档的提示词输出约束和结构测试，不改变其 schema。

## 2.2 Pipeline runtime input

`resources` 不是新的持久化字段，而是 `workspace inspect` 的运行时返回值，Pipeline 原样传给 reviewer Skill。逻辑形状为：

```yaml
workspace: "{workspace inspect.operationalWorkspace}"
resources:
  - repo: "ai-first-platform-docs"
    worktreePath: "{absolute-or-runtime-worktree-path}"
    classification: healthy
    branch: "requirement/CR-YYYY-NNN"
  - repo: "tools"
    worktreePath: "{tools worktree path}"
    classification: healthy
    branch: "requirement/CR-YYYY-NNN"
```

评审 Skill 只依赖 `repo` 和 `worktreePath`。`classification` 等其他字段由 Pipeline 原样保留，但不被 Skill 改写或重新推导。缺失、重复、不可读取的资源属于技术失败，不写评审 payload。

## 2.3 既有 review payload

两个 reviewer 仍产生既有最小 payload：

```yaml
verdict: pass | block
blockers: []
dimensions:
  <existing-dimension-key>: pass | block | "带证据的结论"
suggestions: []
```

`review-tech-design` 的 dimension 键继续对应既有 8 个技术设计维度；AC、事实证据、旧 blocker 复核写入对应 dimension 文本或 blocker 文本。`review-dev-plan` 继续使用既有八个键和可选 `repair-target`。不增加 `facts`、`evidence`、`ac-results` 或其他字段。

## 2.4 事实证据结构

事实证据不作为 payload 新字段，而作为现有 dimension/blocker 的可读文本，必须包含：

```text
repo=<repo id>; commit=<40-char SHA>; path=<relative path>; symbol=<stable symbol>; conclusion=<核实结论>
```

纯绿地、没有既有实现依赖时写：

```text
N/A（本 CR 无既有实现依赖）
```

资源缺失、路径不可读、symbol 不存在或行为不符不能写 N/A，必须返回技术失败或形成业务 blocker：

- 无法取得必要证据 = 技术失败，中止且不写 canonical review；
- 证据明确证明设计/计划错误 = 业务 blocker，完成本轮并经 `review-record` 落盘。

# 3. 接口契约

## 3.1 Skill 输入合同

### `review-tech-design`

| 参数 | 类型 | 必填 | 来源/约束 |
|---|---|---:|---|
| `cr_id` | string | 是 | Pipeline/调用上下文提供 |
| `workspace` | string | 是 | `workspace inspect.operationalWorkspace` 原样值 |
| `resources` | array | 是 | `workspace inspect.resources` 原样值，元素含 `repo`、`worktreePath` |
| `reviewer` | string | 否 | 缺省 `ai-reviewer` |
| `review_feedback` | object | 否 | 当前 reviewLoop 的回修反馈 |
| `self_repair_attempt` | number | 否 | 当前 reviewLoop 轮次，首次为 0 |

### `review-dev-plan`

| 参数 | 类型 | 必填 | 来源/约束 |
|---|---|---:|---|
| `cr_id` | string | 是 | Pipeline execution_context 提供 |
| `workspace` | string | 是 | node-1 execution_context.operational_workspace 原样值 |
| `resources` | array | 是 | node-1 execution_context.resources 原样值，元素含 `repo`、`worktreePath` |
| `reviewer` | string | 否 | 缺省 `ai-reviewer` |
| `review_feedback` | object | 否 | 当前 reviewLoop 的回修反馈 |
| `self_repair_attempt` | number | 否 | 当前 reviewLoop 轮次，首次为 0 |

两个 Skill 都必须明确：不得通过路径命名约定、自行发现或会话记忆替代 `resources`。`workspace` 用于过程文档；代码事实用 `resources[].worktreePath`。这两个概念不得混用。

## 3.2 Pipeline 传参契约

### architecture-design

node `review-tech-design` 继续在调用前执行一次 `workspace inspect`，并传递：

```text
cr_id: {{inputs.cr_id}}
workspace: {workspace inspect.operationalWorkspace 原样值}
resources: {workspace inspect.resources 原样值}
review_feedback: {reviewLoop.review_feedback，可为空}
self_repair_attempt: {reviewLoop.self_repair_attempt，可为空}
```

节点仍为现有 node `...0002`，不增加节点、不改变 node ID、不改变 reviewLoop。

### code-implementation

node `review-dev-plan` 读取 node-1 的 `execution_context`，并传递：

```text
cr_id: {execution_context.cr_id}
workspace: {execution_context.operational_workspace}
resources: {execution_context.resources}
review_feedback: {reviewLoop.review_feedback，可为空}
self_repair_attempt: {reviewLoop.self_repair_attempt，可为空}
```

这里的 `resources` 必须是 node-1 由 `workspace inspect.resources` 原样传下来的值，而不是在 node-3 重新 inspect、重新发现或拼接路径。

## 3.3 `controlled-shell` 只读取证合同

`controlled-shell/SKILL.md` 的调用者说明补充 `review-tech-design` 和 `review-dev-plan`。两个 reviewer 只可调用现有只读 Git 适配能力：

- 原生文件读取目标 `worktreePath` 下的文件；
- `crctl git rev-parse HEAD` 获取证据 commit；
- 必要时使用已有 `diff`、`log`、`merge-base` 只读能力。

本 CR 不修改 `rules.json`，不增加 Git 子命令、参数形态、protected path 或写操作。reviewer 仍不能调用 commit、add、push、merge、approve、advance 或任何账本写入入口。

## 3.4 错误契约

技术失败返回现有结构化错误语义，不写临时 payload：

```yaml
error:
  code: SHELL_UNAVAILABLE | EXEC_FAILED | UNEXPECTED
  message: "可读说明"
  cwd: "目标 worktree"
  stdout: "截断输出"
  stderr: "截断输出"
```

以下错误属于技术失败：

- `workspace` 或 `resources` 缺失/结构非法；
- 目标 `worktreePath` 不可读、资源串读或无法取得 commit SHA；
- 受控只读能力不可用；
- 独立 reviewer task 创建/绑定失败；
- 临时 payload 或 `review-record` 不可用。

以下属于正常业务 blocker：

- AC 设计落点不可达或不可观察；
- SDD 引用的既有事实不存在或不支持设计；
- TASK 新造函数、事件、SQL、nil 责任层等事实与权威 worktree 不符；
- 计划漏继承 AC 设计落点；
- 验收步骤不能组合证明 AC 或存在无关短路假绿。

## 3.5 `write-tech-design` 输出合同

SDD 第 6 节对每个 AC 至少包含：

```text
AC-xx
设计落点：负责产生结果的模块、流程、接口或数据字段
可观测结果：评审或测试时能观察到的状态、字段、事件或行为
可达性说明：关键前置条件不会提前过滤掉目标对象
```

涉及既有实现时追加第 2.4 节定义的 repo/commit/path/symbol/conclusion 证据；无既有依赖时明确写 N/A。

# 4. 关键流程与算法

## 4.1 首次技术设计评审

`review-tech-design` 首轮按以下顺序执行，只有全部适用维度完成后才产生 verdict：

1. 校验 `cr_id`、`workspace`、`resources` 和目标文档可读性；
2. 以 `workspace` 读取 PRD、SDD 和架构文档；
3. 按 `resources[].worktreePath` 解析 SDD 明确引用的既有实现依赖；
4. 顺序检查既有 8 个维度：PRD↔SDD 对齐、架构合理性、数据模型完整性、接口契约、多仓架构约束、性能与安全、可测试性、Prompt 采纳影响（条件触发）；
5. 在 PRD↔SDD 对齐中逐条核对 FR→技术方案和 AC→设计落点；
6. 在可测试性中核对 AC 可观测结果和设计层验收位置；
7. 对每个明确引用的既有事实形成稳定证据；绿地无依赖明确记录 N/A；
8. 合并同根因问题，拆分不同根因问题；
9. 统一生成 verdict、blockers、dimensions、suggestions；
10. 通过既有临时 payload + `crctl review-record --stage tech-design --bump-attempt` 落盘，再按 route 执行既有状态分流。

首轮发现第一个 blocker 后不能提前结束，因为该行为会把同轮可发现的独立问题推迟到后续轮次。

## 4.2 技术设计评审的 AC 闭环

对每个 AC 执行以下判定：

```text
if no_design_landing(ac): blocker("缺少设计落点")
else if landing_cannot_produce_observable_result(ac): blocker("结果不可观察")
else if prerequisite_filters_required_target(ac): blocker("关键前置条件使 AC 不可达")
else: pass with landing + observable + reachability evidence
```

这不是新增 annotation dimension，而是既有“PRD↔SDD 对齐”和“可测试性”维度的检查细化。关键前置条件包括但不限于过滤条件、状态门槛、权限判定、事件触发顺序、空值分支和跨仓依赖初始化。

## 4.3 SDD 自引用事实核验

仅核验 SDD 明确写入且设计成立依赖的既有实现事实，不对整个代码库做无界扫描：

```text
for dependency in sdd.explicit_existing_dependencies:
  resource = resources.find(r => r.repo == dependency.repo)
  if resource missing or worktree unreadable:
    technical_failure_without_payload()
  sha = controlled_readonly("rev-parse HEAD", resource.worktreePath)
  fact = controlled_readonly(file/symbol evidence, resource.worktreePath)
  if fact absent or behavior differs:
    business_blocker_with_evidence()
  else:
    record(repo, sha, relative_path, stable_symbol, conclusion)
if explicit_existing_dependencies is empty:
  record("N/A（本 CR 无既有实现依赖）")
```

行号只能作为辅助信息，不能作为唯一证据。评审不执行 lint、build 或测试；这些属于后续验证阶段。

## 4.4 回修评审

当存在 `review_feedback`、上一轮 SDD annotation 为 BLOCK 或 `self_repair_attempt > 0` 时：

1. 读取上一轮 annotation 和反馈中的 blocker；
2. 优先按 blocker 对本轮 SDD 变化做定点复核；
3. 将每个旧 blocker 标为已解决、部分解决、未解决或需重新判断；
4. 本轮变化影响的维度重新核验；
5. 未受影响维度仍写入 dimensions，并给出有依据的快速复核，不直接继承旧 PASS；
6. 新独立 blocker 同轮加入；
7. 继续使用现有 `maxAttempts=3`；达到上限后停止自动回修，不 reset cycle；
8. review-record 和现有 `replayNodes` 不改变。

## 4.5 开发计划评审增量算法

`review-dev-plan` 保留八类维度，但职责收窄为：

```text
sdd-to-plan:
  verify every AC landing and SDD deliverable is represented in plan/TASK
  do not reopen every already-approved SDD decision

task-executability:
  inspect TASK new/refined facts, target, input, output, ownership, done criteria

interface-contracts:
  verify TASK-created function/event/SQL/signature/nil-responsibility facts

acceptance-verifiability:
  verify TASK steps compose to prove AC at the real responsibility boundary
  reject unrelated dependency shortcuts that can produce false green

other four dimensions:
  retain plan-to-tasks, dependency-topology, scope-and-simplicity, risk-and-rollback
```

如果新 TASK 事实反证 SDD，或 SDD 设计落点本身断裂，则将 `repair-target` 设为 `write-tech-design`，沿现有 UPSTREAM 转换；不覆盖 `review-annotations/sdd.yml`。若只有计划/TASK 翻译问题，则沿现有 `write-dev-plan` 普通回修轨。

同一轮存在两类问题时，所有 blocker 都进入同一个既有 payload；路由优先 UPSTREAM，随后由既有 `replayNodes` 重建 plan/TASK 并重审，不拆状态和账本。

## 4.6 Pipeline reviewLoop

保留以下机器配置不变：

### architecture review-tech-design

```yaml
repairRef: write-tech-design
replayPolicy: rerun-listed-nodes-in-order
replayNodes:
  - write-tech-design
  - review-tech-design
maxAttempts: 3
passCondition: verdict=pass and blockers=[]
```

### code review-dev-plan

```yaml
repairRef: write-dev-plan
replayPolicy: rerun-listed-nodes-in-order
replayNodes:
  - write-dev-plan
  - write-dev-tasks
  - review-dev-plan
maxAttempts: 3
passCondition: verdict=pass and blockers=[]
```

只改变 reviewer prompt 的输入传递，不改变节点 ID、顺序、回放数组、双轨 route 或 `onFail`。

## 4.7 评审落盘与状态流转

评审判断仍按现有路径：

```text
临时 payload
  -> crctl review-record
  -> canonical annotation + review-loop + traceability
  -> pass: 保持待审批状态
  -> block: 既有回修/UPSTREAM 状态转换
```

本 CR 不在 Skill 中实现原子写、CAS、attempt 或 traceability 投影，也不新增 payload 字段。状态转换仍以 `crctl next` 和状态机为准。

# 5. 技术选型与替代方案

## 5.1 选型

| 选择 | 原因 |
|---|---|
| 在现有 SKILL.md 增量补充合同 | Skill 已是评审业务规则的权威入口，避免新建评审 Agent 或规则引擎 |
| 复用 `workspace inspect` resources | 它已经是 workspace authority resolver 的现有输出，避免 reviewer 自行发现路径 |
| 复用 controlled-shell 只读能力 | 已有 Git 白名单和 `crctl git` 适配，满足最小授权，不增加命令面 |
| 复用现有 review-record | 保持 annotation、attempt、traceability、CAS 和审计语义一致 |
| 扩展既有结构测试 | 已覆盖节点顺序、reviewLoop、权限和禁止范围，新增断言能直接防回归 |

## 5.2 否决方案

### 新增 `ac-reachability` 或 `code-facts` 独立评审节点

否决原因：会改变 Pipeline 节点数、人工审批前置关系和 reviewLoop 回放模型；AC 闭环属于技术设计评审既有维度的细化，代码事实属于该维度的取证要求，不需要新状态或新节点。

### 增加 annotation 的 `facts`/`evidence` 字段

否决原因：PRD 明确要求兼容既有 payload schema；事实证据可以写入既有 dimensions/blockers 文本，增加字段会扩大 `crctl` schema、投影和回写影响面。

### 修改 `crctl.mjs` 或 `rules.json`

否决原因：现有 `review-record`、digest、CAS、状态机和 Git 只读白名单已经足够；本 CR 只补调用方合同和权限说明，修改底层会扩大事务与安全面。

### reviewer 自行解析或拼接 worktree

否决原因：会绕过 `workspace inspect` 的 authority resolver，可能串读主工作区或其他仓库；所有路径必须来自 Pipeline 提供的 `resources[].worktreePath`。

### 复用上一轮 PASS 代替回修复核

否决原因：回修可能改变未直接命中的维度或引入新 blocker。未受影响维度也必须有依据地快速复核，不能无证据继承 PASS。

### reviewer 执行 lint/build/test 取证

否决原因：这些属于后续验证阶段，不是设计事实核验；将其塞入 reviewer 会扩大执行权限和环境依赖，违反最小授权。

## 5.3 无 HTTP API

本 CR 不新增或修改 HTTP/REST、IPC、事件协议或数据库接口，因此不编写 OpenAPI 片段，也不引入鉴权、分页或幂等契约。现有 `crctl` CLI 作为被调用能力保持不变。

# 6. FR 到技术实现映射

## FR-1 技术设计评审输入合同

- **设计落点**：`review-tech-design/SKILL.md` 和 `review-dev-plan/SKILL.md` 的参数表、前置校验；两个 Pipeline reviewer 节点的 prompt；`pipeline-structure.test.mjs` 的输入合同断言。
- **可观测结果**：Skill 文档明确列出 `cr_id`、`workspace`、`resources`、`review_feedback`、`self_repair_attempt`；结构测试能检查必填合同和资源传递文本。
- **可达性说明**：reviewer 的目标路径只由 `resources[].worktreePath` 产生；不存在私有路径拼接、主工作区回退或跨会话仓库替代。

## FR-2 技术设计评审必须覆盖 AC 闭环和 SDD 自引用事实

- **设计落点**：`review-tech-design/SKILL.md` 的八维度表、AC 闭环算法、事实核验算法和证据文本模板；既有 payload dimensions。
- **可观测结果**：每条 FR/AC 都能在评审 notes/blocker 中找到方案、落点、可观测结果、可达性和必要的 repo/SHA/path/symbol/conclusion；绿地依赖明确为 N/A。
- **可达性说明**：评审先完成全部适用维度再统一 verdict；没有因为首个 blocker 或错误的前置过滤而跳过 AC 和事实检查。

## FR-3 技术设计评审必须统一汇总 blocker 并支持回修复核

- **设计落点**：`review-tech-design` 的首轮流程、回修流程、同根因合并规则和 `maxAttempts=3` 约束；现有 architecture reviewLoop。
- **可观测结果**：同一轮 payload 的 blockers 同时包含独立根因；回修记录逐条标识旧 blocker 状态并包含新 blocker；达到 3 次后出现 LOOP_EXHAUSTED 而不 reset。
- **可达性说明**：现有 replayNodes 仍按 write-tech-design→review-tech-design 重放，反馈和 attempt 原样传递，回修有入口。

## FR-4 开发计划评审聚焦翻译增量和 TASK 新事实

- **设计落点**：`review-dev-plan` 八维度表中的四个职责边界，以及 `resources` 事实核验合同；既有 plan/TASK 文档和 review payload。
- **可观测结果**：评审能区分 SDD→plan 遗漏、TASK 新造事实错误、接口/nil 责任层错误和验收假绿；资源缺失/事实不符不会静默写 N/A。
- **可达性说明**：SDD 已审批内容不被无差别重审，但新证据反证 SDD 时保留 UPSTREAM 路由，既能减少重复工作又不丢安全网。

## FR-5 保留 UPSTREAM 安全网和现有评审落盘路径

- **设计落点**：`review-dev-plan` 的 `repair-target` 双轨处理；`crctl review-record --stage dev-plan`；现有 code Pipeline replayNodes。
- **可观测结果**：混合 blocker 保留在同一 annotation；`repair-target=write-tech-design` 走 UPSTREAM，普通翻译问题走 `write-dev-plan`；不会写或覆盖 SDD annotation。
- **可达性说明**：不新增状态或账本，沿既有 `task-breakdown → tech-design-review-pending` 和 plan 普通回退转换完成路由。

## FR-6 SDD 必须输出 AC 级设计映射

- **设计落点**：`write-tech-design/SKILL.md` 第 6 节输出约束；SDD 的“FR 到技术实现映射”章节。
- **可观测结果**：生成的 SDD 每个 AC 都出现“设计落点、可观测结果、可达性说明”，已有实现断言带稳定代码事实，绿地依赖写 N/A。
- **可达性说明**：AC 映射与既有 FR 映射同属 SDD，不改变状态机、文件落点或审批节点；回修只按 blocker 定点修改。

## FR-7 Pipeline 必须原样传递资源和回修上下文

- **设计落点**：architecture-design reviewer prompt 增加 `resources`；code-implementation reviewer prompt 增加 `execution_context.resources`；reviewLoop 字段保持原状。
- **可观测结果**：结构测试逐字确认两个节点都传递 workspace、resources、review_feedback、self_repair_attempt，并确认 node-1 是 code reviewer 的 resources 来源。
- **可达性说明**：资源先由 workspace inspect 产生，再经 execution_context 或同节点 prompt 传递；不要求新节点、不依赖运行时自行发现路径。

## FR-8 Reviewer 必须具备受控只读取证并有结构回归检查

- **设计落点**：`agent-skill-matrix.yml` 的 quality-reviewer-agent.can-call；`controlled-shell/SKILL.md` 调用者说明；结构测试的权限和负向断言。
- **可观测结果**：矩阵中 reviewer 可调用 controlled-shell；文档只授权文件读取和已有只读 Git；测试确认没有任意 shell、写操作、审批或状态权限。
- **可达性说明**：现有 rules.json 白名单继续提供 rev-parse/diff/log/merge-base 等能力，不需要新增命令或修改 protected paths。

# 7. 安全与性能考量

## 7.1 安全

1. **路径隔离**：reviewer 只能访问 Pipeline 提供的 `resources[].worktreePath`；资源缺失、重复或不可读直接技术失败。
2. **权限最小化**：`quality-reviewer-agent` 增加的只是 `controlled-shell` 调用权；controlled-shell 仍不提供任意 shell、写文件、账本写入、状态推进和人工审批能力。
3. **凭据保护**：沿用现有 controlled-shell 日志截断和凭据过滤规则；证据只记录 repo、SHA、相对路径、稳定符号和结论，不记录 token。
4. **证据可信度**：commit SHA 来自目标 worktree 的只读 `rev-parse HEAD`；行号不是唯一证据；事实不符形成 blocker，不能用 N/A 绕过。
5. **账本保护**：reviewer 不直接写 canonical annotation；`crctl review-record` 继续负责 schema、CAS、attempt、traceability 和临时 payload 清理。
6. **状态保护**：本 CR 不改变状态机；评审通过/阻断的状态流转仍须经过既有 `crctl advance` 和 reviewLoop。
7. **独立性**：Pipeline 继续要求每轮新建独立 `quality-reviewer-agent` task/run，作者会话不得自评。

## 7.2 性能

- 评审只核验 SDD 明确引用的既有实现事实，不进行全仓库无界扫描。
- `workspace inspect` 维持每个 Pipeline reviewer 节点已有的一次检查；code Pipeline 不在 review-dev-plan 节点重复 inspect。
- 只读取 Git 命令为按需调用；不新增索引、缓存、digest 或后台服务。
- 首轮一次汇总多个 blocker 可能增加单轮阅读量，但减少同一根因被拆分到多轮的重复上下文建立；这是评审调用量和反馈完整性的权衡，不以删除 gate 或测试换取性能。
- 结构测试仍是零依赖 `node:test`，不会增加运行时依赖。

## 7.3 可观测性与审计

- 评审结果仍由 canonical annotation、review-loop、traceability 和 `.crctl/audit.log` 观察。
- blocker 数量、verdict、attempt 和 route 继续由既有 `crctl review-record` 输出。
- 代码事实证据写入既有 dimensions/blockers 文本，使用 repo/SHA/path/symbol 格式，便于人工复核。
- 不新增行为遥测、指标服务或审计表。

## 7.4 验收位置

| 验收目标 | 设计/测试位置 |
|---|---|
| Skill 输入合同 | 两个 reviewer SKILL.md 参数表、前置校验；结构测试合同断言 |
| AC 设计落点/可达性/可观测性 | review-tech-design SKILL.md Step 2/算法；SDD 第 6 节；人工固定场景 |
| SDD 事实核验 | review-tech-design SKILL.md Step 2/事实算法；人工错误事实场景 |
| plan/TASK 翻译增量 | review-dev-plan SKILL.md 八维度表；人工 TASK 新事实/假绿场景 |
| resources 原样传递 | 两个 Pipeline reviewer prompt；结构测试 |
| UPSTREAM 和 replay | 两个 Pipeline 的 reviewLoop；已有节点顺序/数组断言 |
| 只读取证和权限 | agent-skill-matrix.yml、controlled-shell SKILL.md、rules.json 不变断言 |
| canonical 落盘不变 | 既有 crctl review-record 相关测试和三账本结果核对 |

# 8. 实施计划、测试与回滚

## 8.1 实施顺序

1. 修改 `review-tech-design/SKILL.md`：输入合同、八维度细化、AC 闭环、事实核验、首轮汇总、回修和技术失败语义。
2. 修改 `review-dev-plan/SKILL.md`：输入合同、资源边界、四个增量职责、事实错误处理和 UPSTREAM 混合 blocker 说明。
3. 修改 `write-tech-design/SKILL.md`：第 6 节补 AC 级输出合同和回修定点规则。
4. 修改 `controlled-shell/SKILL.md`：增加两个 reviewer 的只读调用者说明，不改 `rules.json`。
5. 修改 `agent-skill-matrix.yml`：仅给 `quality-reviewer-agent.can-call` 增加 `controlled-shell`。
6. 修改 architecture/code 两个 Pipeline：分别补 reviewer 的 `resources` 原样传参，保持节点和 reviewLoop 不变。
7. 增量修改 `pipeline-structure.test.mjs`：加入输入、资源、权限、禁止范围和节点不变断言。
8. 运行 prompt lint、权限矩阵检查、Pipeline 结构测试、Pipeline JSON 解析和相关 crctl 测试。

## 8.2 结构测试向量

至少覆盖：

| 向量 | 预期 |
|---|---|
| 两个 reviewer Skill 输入参数 | `workspace/resources` 必填；反馈和轮次可选；只消费 resources worktree |
| architecture reviewer prompt | 含 workspace、resources、feedback、attempt 原样传参 |
| code reviewer prompt | 含 execution_context.workspace/resources、feedback、attempt；不重新发现资源 |
| reviewer 权限 | matrix 含 controlled-shell；controlled-shell 文档含两个 reviewer |
| architecture reviewLoop | 2 个 replayNodes、顺序和 maxAttempts=3 不变 |
| code reviewLoop | 3 个 replayNodes、顺序和 maxAttempts=3 不变 |
| Pipeline 结构 | architecture 5 节点、code 16 节点，节点顺序不变 |
| 禁止范围 | 无新增节点/状态/账本字段；不修改 `crctl.mjs`、`gates.json`、`rules.json` 声明；不新增 Agent/依赖 |
| reviewer prompt 负向 | 不含 review-record 细节、账本写入算法、任意 shell 或测试执行要求 |

## 8.3 自动检查

在 `../tools` 仓执行：

```text
node skills/shared/lint-prompts/scripts/lint-prompts.mjs --mode enforce
node skills/shared/check-skill-matrix/scripts/check-skill-matrix.mjs
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node -e "const fs=require('fs'); for (const f of ['architecture-design.pipeline.json','code-implementation.pipeline.json']) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"
```

再运行与 review-record、workspace resolver、Pipeline 结构相关的现有 `node --test` 套件。评审阶段不把 lint/build/test 的执行结果当作事实核验结果；上述命令属于实施后的验证证据。

## 8.4 回滚

回滚只使用普通 Git 修复或回退提交，且不手工修改 CR 状态。回滚触发条件包括：

- reviewer 资源串读或回退主工作区；
- `controlled-shell` 授权扩大到写操作或任意 shell；
- reviewLoop、UPSTREAM、节点顺序或 `review-record` 语义回归；
- 任一结构/权限/prompt 检查失败；
- 生成的 payload 不符合既有 schema；
- 变更超出批准的 8 个文件。

由于本 CR 不修改状态机、crctl、rules.json、业务仓代码或持久化 schema，普通 Git 回滚即可移除新提示词和传参合同，不需要数据迁移或补偿事务。

## 8.5 完成判据

本 SDD 进入技术设计评审前必须满足：

- 每个 FR 都有技术落点、可观察结果和可达性说明；
- 每个 AC 都有对应设计/验收位置；
- 8 个批准文件的修改职责和边界明确；
- 现有状态、节点、reviewLoop、UPSTREAM、账本和 payload schema 不变；
- 既有实现事实均附 repo、commit SHA、relative path、stable symbol 和结论；
- 不涉及既有代码依赖的部分明确写 N/A；
- 技术失败与业务 blocker 的分流可执行；
- 测试、lint 和 JSON 解析命令可在实施后复现。
