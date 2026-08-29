---
id: CR-2026-055-prd
type: PRD
cr-ref: CR-2026-055
title: 评审分层最小改造 — 技术设计评审前移 AC 可达性与可观测验收、SDD 自引用代码事实核验、plan 评审翻译增量职责、reviewer 受控只读取证授权
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-29T22:09:10+08:00
updated: 2026-08-29T22:09:10+08:00
---

# 1. 概述

## 1.1 问题陈述

当前评审链路已经具备独立 reviewer task、Pipeline reviewLoop、UPSTREAM 路由、`crctl review-record` 和三账本审计能力，但技术设计评审与开发计划评审的事实边界仍不够清晰：

- `review-tech-design` 主要按 FR 检查 SDD，可能遗漏 AC 级设计落点不可达、验收结果不可观察，以及 SDD 明确引用的既有代码事实错误。
- `review-dev-plan` 可能在 SDD 已审批后才发现设计落点无法实施；同时对 TASK 新造的函数、事件、SQL、nil 责任层和验收短路风险约束不足。
- BLOCK 回修时可能重复建立上下文，或将同一轮能够发现的多个独立 blocker 分散到多轮暴露，增加回修成本。
- reviewer 若没有获得 Pipeline 传入的真实 worktree 资源和受控只读取证授权，代码事实核验只能停留在提示词层面。

## 1.2 解决方案摘要

在不改变状态机、Pipeline 节点、reviewLoop、评审账本和 `crctl` 确定性落盘能力的前提下，完成一个 tools 侧的最小闭环改造：

1. 强化 `review-tech-design`：首轮完成全部适用维度后统一形成结论，检查每个 AC 的设计落点、可达性、可观测验收和 SDD 自引用的既有代码事实；回修优先处理上一轮 blocker 与本轮变化，同时保留未受影响维度的有依据复核。
2. 明确 `review-dev-plan`：聚焦 SDD/AC 到 plan/TASK 的翻译增量，检查 TASK 新造或细化的实现事实、真实责任边界、验收证明能力和无关短路假绿；发现 SDD 缺陷时继续走 UPSTREAM。
3. 完善 `write-tech-design`：在现有 FR 到技术实现映射中补充 AC 级的设计落点、可观测结果和可达性说明。
4. 让两个 Pipeline 原样传递 `workspace`、`resources`、`review_feedback` 和 `self_repair_attempt`；让 reviewer 通过既有受控只读能力核实事实。
5. 通过现有结构测试和静态检查验证输入合同、权限关系、回放路由、UPSTREAM 和 `maxAttempts=3` 不回归。

## 1.3 目标与边界

目标仓库为 sibling `../tools/`，修改范围固定为以下 8 个文件：

```text
skills/develop/review-tech-design/SKILL.md
skills/develop/review-dev-plan/SKILL.md
skills/develop/write-tech-design/SKILL.md
skills/shared/controlled-shell/SKILL.md
agent-skill-matrix.yml
pipeline-templates/architecture-design.pipeline.json
pipeline-templates/code-implementation.pipeline.json
skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
```

本 CR 的知识来源为 `docs/product/评审分层最小改造方案.md`。本 CR 只改变新进入对应评审节点的行为，不迁移或重审历史 CR。

# 2. 用户故事

- **US-1 平台需求负责人**：作为需求负责人，我希望 SDD 阶段就能发现 AC 不可达、不可观察或依赖事实错误的问题，从而避免问题延迟到开发计划或编码阶段。
- **US-2 技术设计作者**：作为技术设计作者，我希望每个 AC 在 SDD 中都有明确的设计落点、可观测结果和可达性说明，从而可以直接据此编写 plan/TASK。
- **US-3 开发计划作者**：作为开发计划作者，我希望 plan 评审明确区分 SDD 已确认内容与 TASK 新增事实，从而知道哪些问题应在当前阶段修复，哪些问题必须回退到技术设计阶段。
- **US-4 独立 reviewer**：作为独立 reviewer，我希望获得正确的 operational workspace 和 resources，并能通过受控只读能力核实既有代码事实，从而给出可复现的评审证据。
- **US-5 CR 协作者**：作为 CR 协作者，我希望一次评审汇总同一轮发现的独立 blocker，并在回修后看到旧 blocker 的解决状态和新 blocker，从而减少重复评审和信息丢失。
- **US-6 平台维护者**：作为平台维护者，我希望改造复用现有 Pipeline、reviewLoop、`crctl review-record` 和权限模型，不增加新的状态、账本或运行时框架，从而保持流程可维护和可回滚。

# 3. 功能需求

## FR-1 技术设计评审输入合同

`review-tech-design` 必须声明并消费以下输入：

- 必填 `cr_id`、`workspace`、`resources`；
- 可选 `review_feedback`、`self_repair_attempt`；
- `resources` 必须是 Pipeline 原样传入的 `{repo, worktreePath}` 清单。

Skill 只能使用 `resources[].worktreePath` 访问目标仓库，不得拼接私有 worktree 路径、回退主工作区、替换为会话中其他仓库，或自行发现仓库路径。

## FR-2 技术设计评审必须覆盖 AC 闭环和 SDD 自引用事实

首次技术设计评审必须完成全部适用的既有 8 个维度后再形成 verdict：

1. PRD 与 SDD 对齐；
2. 架构合理性；
3. 数据模型完整性；
4. 接口契约；
5. 多仓架构约束；
6. 性能与安全；
7. 可测试性，具体检查可观测验收可行性；
8. Prompt 采纳影响（按既有条件触发）。

其中 PRD 与 SDD 对齐维度必须检查每条 FR 是否有技术方案、每个 AC 是否有设计落点，以及设计落点是否能产生 AC 要求的可观测结果。关键前置条件不得提前过滤掉 AC 所要求的目标对象、状态、字段、行为或原因。

可测试性维度必须检查每个 AC 的观察结果和明确的设计层验收位置。SDD 明确引用或依赖既有函数、类型、事件、数据库结构、配置、模块行为、调用顺序、责任边界、API、OpenAPI、协议或代码路径时，必须核实其事实；事实证据至少包含 repo、commit SHA、relative path、stable symbol 和核实结论。纯绿地设计无既有实现依赖时，必须明确记录 `N/A（本 CR 无既有实现依赖）`，不得用 N/A 掩盖已写入的事实依赖。

## FR-3 技术设计评审必须统一汇总 blocker 并支持回修复核

首次评审不得在发现第一个 blocker 后结束。评审必须在完成全部适用维度后统一汇总：

- 同一根因的多个位置合并为一个 blocker；
- 不同根因分别列出；
- 每个 blocker 只表达一个可执行问题；
- 当前 CR 必须处理的问题进入 `blockers`，普通建议和未来优化进入 `suggestions`。

当存在 `review_feedback`、上一轮 SDD annotation 为 BLOCK 或 `self_repair_attempt > 0` 时，评审进入回修模式：读取上一轮 annotation 和反馈，优先核对旧 blocker 与本轮 SDD 变化；逐条标记旧 blocker 已解决、部分解决、未解决或需重新判断；对未受影响维度也给出有依据的快速复核；新独立 blocker 必须在本轮一并列出。达到 reviewLoop 的 `maxAttempts=3` 后停止自动回修，不由 Skill 自动 reset cycle。

## FR-4 开发计划评审聚焦翻译增量和 TASK 新事实

`review-dev-plan` 必须保留现有八类检查：

- SDD 到 plan 覆盖；
- plan 到 TASK 覆盖；
- TASK 可执行性；
- 依赖拓扑；
- 接口契约一致性；
- 验收可验证性；
- 范围与极简性；
- 风险与回滚。

职责边界必须明确为：

- `sdd-to-plan` 检查 AC 设计落点是否完整继承到 plan/TASK，不对 SDD 做无差别重复评审；
- `task-executability` 检查 TASK 新造或细化的目标、输入、输出、责任层和完成标志，以及实现断言是否有权威 worktree 依据；
- `interface-contracts` 检查 TASK 新造的函数名、参数、返回类型、事件、SQL 和 nil 责任层事实；
- `acceptance-verifiability` 检查验收步骤是否能组合证明 AC、是否位于真实责任边界，以及是否可能被无关依赖短路形成假绿。

资源缺失、symbol 不存在或行为不符不得猜测，也不得静默写 N/A；纯绿地且无既有实现依赖时才允许明确写 N/A。

## FR-5 保留 UPSTREAM 安全网和现有评审落盘路径

以下情况必须继续报告 `repair-target=write-tech-design` 并沿用现有 UPSTREAM 路由：

- plan 阶段发现 SDD 设计断裂；
- 新依赖、新路径或 TASK 新事实反证 SDD；
- SDD 评审后发生 PRD 修订或代码基线变化。

同一轮同时存在 SDD blocker 和 TASK blocker 时，不拆分状态或账本，必须保留全部 blocker，先修复 SDD，再按现有 `replayNodes` 重新生成并评审 plan/TASK。评审结论继续通过现有 `crctl review-record` 落盘，复用现有 annotation、attempt、traceability 和状态推进机制，不新增 payload 字段或写入器。

## FR-6 SDD 必须输出 AC 级设计映射

`write-tech-design` 在现有第 6 节“FR 到技术实现映射”中，为每个 AC 补充以下信息：

```text
AC-xx
设计落点：负责产生结果的模块、流程、接口或数据字段
可观测结果：评审或测试时能观察到的状态、字段、事件或行为
可达性说明：关键前置条件不会提前过滤掉目标对象
```

只有依赖既有实现的断言才附代码事实证据。回修时优先依据上一轮 blocker 定点修订，不得无理由重写已确认的整体方案。

## FR-7 Pipeline 必须原样传递资源和回修上下文

`architecture-design.pipeline.json` 调用 `review-tech-design` 时，必须原样传递：

- `workspace`：`workspace inspect` 返回的 `operationalWorkspace`；
- `resources`：`workspace inspect` 返回的资源清单；
- `review_feedback`；
- `self_repair_attempt`。

`code-implementation.pipeline.json` 调用 `review-dev-plan` 时，必须从 node-1 的 `execution_context` 取得并原样传递相同字段。Pipeline 只负责输入传递、reviewLoop 和失败中止，不复制 AC 判断、事实核验或 blocker 合并算法。两个 Pipeline 不增加节点，不修改既有节点顺序、双轨路由、`replayNodes` 或 `maxAttempts=3`。

## FR-8 Reviewer 必须具备受控只读取证授权并有结构回归检查

`quality-reviewer-agent` 必须能够调用现有 `controlled-shell` 只读能力；`controlled-shell/SKILL.md` 必须将 `review-tech-design` 和 `review-dev-plan` 纳入只读 Git 取证调用者说明。授权只覆盖原生文件读取和已有 `crctl git` 只读能力，包括必要的 `rev-parse HEAD`、`diff`、`log`；不扩展 Git 子命令白名单，不允许任意 shell、写操作、状态推进或账本写入。

更新现有 `pipeline-structure.test.mjs`，至少验证：

- 两个评审 Skill 的输入合同；
- 两条 Pipeline 的 resources 原样传递；
- reviewer 与 controlled-shell 的权限关系；
- 节点顺序、reviewLoop、UPSTREAM 和 `maxAttempts=3`；
- 未新增状态、节点、账本、payload 字段或禁止范围文件的结构约束。

# 4. 非功能需求

## NFR-1 正确性与可审计性

- 评审必须区分技术失败与业务 blocker。资源、worktree、只读取证、reviewer task、临时 payload 或 `review-record` 不可用时，必须中止且不写 canonical review；证据证明设计或翻译错误时，必须完成本轮并正常落盘 blocker。
- 事实核验不得以行号作为唯一证据；稳定证据必须包含 repo、commit SHA、relative path 和 stable symbol。
- 继续复用 `crctl` 的 schema 校验、CAS、annotation、attempt、traceability 和审计能力。

## NFR-2 兼容性

- 不改变现有 annotation payload schema、状态机、状态转换、人工审批、reviewLoop 和 UPSTREAM 转换。
- 历史 CR 的 SDD、dev-plan、review-loop、traceability 和评审记录不迁移、不重审；新规则只对 tools CR 合入并安装后新进入对应评审节点的 CR 生效。
- 现有 plan 评审八维度和双轨路由继续可用。

## NFR-3 安全与权限最小化

- reviewer 只能读取 Pipeline 提供的目标 worktree，不得回退主工作区或串读其他仓库。
- 只读取证不得拥有任意 shell、写文件、账本写入或状态推进权限。
- 不修改 `skills/shared/crctl/scripts/crctl.mjs`、`gates.json` 或 `rules.json`。

## NFR-4 可回滚性与最小变更

- 仅修改已批准的 8 个 tools 文件，不新增依赖、状态、节点、缓存、索引、digest、事务框架、评审 Agent 或行为遥测。
- 发生 resources 串读、reviewLoop/UPSTREAM/review-record 回归、非法 payload 或静态/现有 crctl 测试失败时，应可通过普通 Git 修复提交或回退恢复，不手工修改 CR 状态。

# 5. 验收标准

| 编号 | 对应需求 | 验收标准 |
|---|---|---|
| AC-1 | FR-1 | `review-tech-design` 的文档合同明确声明 `cr_id`、`workspace`、`resources`、`review_feedback`、`self_repair_attempt`；实现只消费 Pipeline 传入的 `resources[].worktreePath`，不存在私有路径拼接、主工作区回退或自行发现路径。 |
| AC-2 | FR-2 | 首次技术设计评审的 annotation dimensions 覆盖全部适用 8 个维度；每条 FR 有技术方案、每个 AC 有设计落点、可观测结果和可达性检查；明确引用既有实现时，评审证据包含 repo、commit SHA、relative path、stable symbol 和结论；无依赖的绿地设计明确记录 N/A。 |
| AC-3 | FR-3 | 构造至少包含两个独立 blocker 的首次评审场景，评审在同一轮完成全部适用维度并一次性汇总；构造带上一轮 blocker、变化和新 blocker 的回修场景，旧 blocker 逐条复核、新 blocker 不被忽略；reviewLoop 达到 3 次后不自动 reset。 |
| AC-4 | FR-4 | plan 评审文档保留 8 类维度，并明确 `sdd-to-plan`、`task-executability`、`interface-contracts`、`acceptance-verifiability` 的边界；TASK 新造或细化事实在目标 worktree 中可核实，事实不存在或不符时形成 blocker，不静默写 N/A；发现 SDD 缺陷时可进入 UPSTREAM。 |
| AC-5 | FR-5 | review-record 仍是评审 canonical 写入入口；同轮同时存在 SDD blocker 和 TASK blocker 时，所有 blocker 保留在既有记录中并按现有 replayNodes 先回修 SDD；不新增 annotation payload 字段、账本或写入器。 |
| AC-6 | FR-6 | 生成的 SDD 第 6 节对每个 AC 包含“设计落点、可观测结果、可达性说明”；回修输入存在时能够依据上一轮 blocker 定点修改，不无理由重写已确认方案。 |
| AC-7 | FR-7 | 结构测试确认 architecture-design 和 code-implementation 分别把 `workspace`、`resources`、`review_feedback`、`self_repair_attempt` 原样传给对应 reviewer Skill；节点数量、顺序、reviewLoop、replayNodes、UPSTREAM 和 `maxAttempts=3` 与现状保持一致。 |
| AC-8 | FR-8 | 权限矩阵将 `controlled-shell` 置于 `quality-reviewer-agent.can-call`，controlled-shell 文档仅授权两个 reviewer Skill 进行只读取证；结构测试确认未放开任意 shell、写操作、状态推进或账本写入。 |
| AC-9 | FR-8 | 在 tools 仓执行 `lint-prompts.mjs --mode enforce`、`check-skill-matrix.mjs`、`node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`，并完成相关 crctl 测试及 Pipeline JSON 解析检查，全部通过。 |
| AC-10 | NFR-1 | 对 resources/worktree/只读取证/reviewer task/临时 payload/review-record 不可用场景，流程返回结构化技术失败且不写 canonical review；对业务设计错误场景，完成评审并写入 blocker。 |
| AC-11 | NFR-2/NFR-3/NFR-4 | 变更 diff 仅包含批准的 8 个文件；不存在新增状态、Pipeline 节点、账本、缓存、索引、digest、事务框架、评审 Agent 或新依赖；`crctl.mjs`、`gates.json`、`rules.json`、状态机和目标业务仓代码无修改。 |

# 6. 成功指标

- 新 CR 的技术设计评审能够在 SDD 阶段识别 AC 不可达、不可观察和 SDD 自引用事实错误，且这些问题不再依赖 plan/TASK 阶段首次暴露。
- plan 评审能够清晰区分 SDD 已确认内容与 TASK 翻译增量；TASK 新造事实、责任边界和假绿问题能够在编码前被识别，SDD 缺陷能够沿 UPSTREAM 回退。
- 首轮评审的独立 blocker 在同一轮完成汇总，回修评审能够保留旧 blocker 复核结果并识别本轮新增 blocker，不因增量模式漏检。
- 资源传递、受控只读取证、reviewLoop、UPSTREAM、review-record、三账本和 `maxAttempts=3` 的现有行为不发生回归。
- 自动检查和既有相关测试全部通过，且不引入新的运行时框架、缓存或遥测系统。

# 7. 范围排除

以下内容明确不在本 CR 范围内：

- 不新增 CR 状态、状态转换、人工审批节点或 Pipeline 节点。
- 不修改 `skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/gates.json`、`skills/shared/controlled-shell/rules.json`、状态机或 `dir-graph.yaml`。
- 不修改 `skills/_index.yml`、`pipeline-templates/_index.yml`、`agents/*.md` 或 README。
- 不新增 `facts`、`evidence` 等 annotation payload 字段，不新增评审账本、attempt 文件、缓存、索引、digest、Git 服务、规则引擎或事务框架。
- 不新增 reviewer Agent、leader Agent 或并行 reviewer 小组；继续使用每轮独立的 `quality-reviewer-agent` task/run。
- 不执行 lint、build 或测试作为 reviewer 的事实取证步骤；这些属于后续验证阶段。
- 不迁移、不重审历史 CR，不让 CR-2026-054 追溯使用本规则。
- 不修改任何目标业务仓代码；本 CR 只实施 tools 平台能力改造。
