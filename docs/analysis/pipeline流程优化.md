# Pipeline 职责边界与契约漂移审计

> 本文合并 `write-tech-design` / `architecture-design` 评审，以及其余 active Pipeline 的只读审计结果。
>
> 文档定位：问题分析与改造建议，不构成当前实施授权；不替代 Pipeline JSON、Skill、`crctl` 或状态机事实源。
>
> 审计范围：`../tools/pipeline-templates/` 下当前 8 条 active Pipeline，以及对应 Skill、`crctl`、受控 shell 和文档校验能力。

## 1. 结论摘要

当前 Pipeline 的**节点顺序、`reviewLoop`、`replayNodes`、`passCondition` 和 `onFail` 总体合理**，问题主要分为两类：

1. **真实契约错误**：Pipeline 没有按对应 Skill 的真实输入输出调用，可能导致运行失败、流程无法闭环或绕过已有安全边界。
2. **职责重复**：Pipeline prompt 复制了 Skill 的业务判断、文档章节、评审维度、`crctl` 命令和账本写入算法，形成第二份易漂移事实源。

优先级判断：

- **P0 / Blocker**：受保护评审账本被人工审批提示直接修改；规划/竞品流程存在输入缺失或流程无法闭环。
- **P1**：审批、评审、测试、TASK、workspace freshness 等节点复制了已由 Skill/crctl 承担的关键算法；或已有命令契约出现遗漏 CR-ID、遗漏 grant 模式等漂移。
- **P2**：章节清单、文件路径、索引格式、展示字段等非阻断性重复，应在职责收敛 CR 中删除。

总体建议：

1. 在同一个 CR 内先修复受保护路径提示和实际输入契约错误；
2. 仍在同一个 CR 内删除 Pipeline prompt 中的重复算法；
3. 实施顺序是“先正确性、后职责收敛”，不是拆分多个 CR；
4. 不新增事务框架、状态账本、恢复框架、Pipeline 专用脚本或新的 crctl 替代实现。

## 2. 逻辑架构约束

各模块应遵循以下职责边界。

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、编排步骤、输入输出、失败语义 | 手写原子账本逻辑、重复实现 crctl |
| crctl | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 人读流程总览 | 另一份可执行细节事实源 |

实现选择继续遵循 ponytail 优先级：

```text
复用现有能力
> 标准库
> 原生 Git/文件 API
> 已有依赖
> 一行代码
> 最小新增代码
```

判断一个 Pipeline prompt 是否越界，可以问五个问题：

1. 这段内容是否已经由被调用 Skill 的 `SKILL.md` 定义？如果是，Pipeline 不应复制。
2. 这段内容是否已经由 `crctl`、`controlled-shell` 或版本化脚本确定性执行？如果是，Pipeline 只传业务输入并消费结果。
3. 这段内容是否决定节点顺序、输入传递、reviewLoop 或失败分流？如果是，保留在 Pipeline。
4. 这段内容是否是业务设计判断或内容质量判断？如果是，放入 Skill。
5. 删除这段自然语言后，机器可执行的 Pipeline 行为是否改变？如果不改变，优先删除。

## 3. 已经解决的基础设施

以下能力已经存在，本轮应直接复用，不得再造一套事务、状态、恢复或账本框架。

| 能力 | 已有权威实现 | Pipeline 的最小职责 |
|---|---|---|
| 工作区事实解析 | `crctl workspace inspect` | 入口校验 healthy，传递 `operationalWorkspace` 和 `resources` |
| 工作区新鲜度 | `workspace-freshness` Skill + `crctl workspace freshness/sync` | 声明 gate 节点，消费 `continue/synced-continue/replay/manual` |
| CR 注册与 worktree | `requirement-register` + `crctl register` | 传注册业务参数，消费结构化结果 |
| 状态和门禁 | `crctl status/next/gate/advance` | 不复制状态转换算法，不手写 status |
| 评审记录与轮次 | `crctl review-record` / `attempt` | Pipeline 声明机器可读 reviewLoop，Skill 形成评审判断 |
| 人工审批 | `approve-*` Skill + `crctl approve` | 编排 `human_approval → approve-*`，不复制 grant、CAS、回退算法 |
| TASK 索引和任务状态 | `crctl task init/append/done` | 不手写 `tasks/_index.yml` |
| 测试证据 | `write-test-report` + `crctl test` | 编排实现 → 测试报告 → 代码评审 |
| 受控 Git | `controlled-shell` / `crctl git` | 不内联裸 Git 命令序列 |
| checkpoint | `push-progress` + `crctl checkpoint` | 传 `cr_id` 和阶段 message，检查结构化 phase |
| 跨仓合并 | `merge-feature-branch` + `crctl merge` | 传 `cr_id`，消费 merge transaction 结果 |
| 回写转换 | `writeback-*` + `writeback-apply` + 版本化 generator | 传 `cr_id/spec_id/target_version` 等业务输入 |
| 归档和清理 | `cr-archive` + `crctl archive` | 传业务参数，消费 `complete/cleanup-pending` |
| 工程文档骨架和校验 | `engineering-docs`、`validate-doc` | Skill 调用并消费校验结果，不在 Pipeline 复制 schema |

### 3.1 本轮明确不新增

- 不新增 Pipeline 专用事务层；
- 不新增 Pipeline 专用状态投影；
- 不新增第二套 review-loop 账本；
- 不新增第二套测试证据格式；
- 不新增 candidate/manifest/merge/recovery 算法；
- 不把 `crctl` 逻辑复制到 Pipeline；
- 不因为 prompt 重复就新建通用 Runner 框架。

## 4. 全量审计总表

| Pipeline | 当前判断 | 主要问题 | 建议优先级 |
|---|---|---|---|
| `architecture-design` | 重复最重，且有受保护路径误导 | node-1/2/4/5 复制 Skill/crctl；human approval 要求改 `review-annotations/sdd.yml` | P0/P1 |
| `requirement-authoring` | 节点结构合理，多个 prompt 复制算法 | approve、review、register、PRD 节点重复 crctl/Skill 契约；reject 提示越界 | P0/P1/P2 |
| `code-implementation` | review/test/approve 节点重复最重 | 复制 `crctl test`、review-record、代码取证、审批和 freshness 路由 | P0/P1/P2 |
| `product-planning` | 有真实输入缺失和跨 Skill 流程错配 | feedback/topic 缺失；竞品节点输入不完整；回修输入不传；roadmap 规则复制 | P0/P1 |
| `market-to-plan` | 有 Skill 参数不匹配和跨文档写入越界 | brief 调用契约不完整；planning-draft 缺 context/intent；Pipeline 额外改 market index | P0/P1 |
| `competitive-radar` | 两阶段确认流程无法按现有 Skill 契约闭环 | report 输入缺失；draft 尚未落盘却要求 reportPath；node-5 混调两个 Skill | P0 |
| `feature-writeback` | 已基本符合职责边界 | node-1 重复 code-approved 预检 | P2 |
| `resume-cr` | 基本合理，展示节点偏重 | `cr-show` 的详情构造和 next/status 逻辑被 Pipeline 复制 | P2 |

## 5. architecture-design 审计

文件：`../tools/pipeline-templates/architecture-design.pipeline.json`

### 5.1 node-1：复制 `write-tech-design` 完整业务算法

节点：`ref=write-tech-design`。

当前 prompt 复制了：

- SDD 章节清单；
- 初次生成和 reviewLoop 回修判断；
- `review_feedback` 消费规则；
- SDD 写入路径；
- `crctl advance` 两次状态推进；
- `git add` / `git commit` 文件和提交消息；
- node 输出字段和 `execution_context` 结构。

这些属于 `write-tech-design` Skill 或 `crctl`，Pipeline 不应复制。当前重复还已经造成工作区路径、commit message 和输入契约漂移风险。

**保留：**

- 执行 `workspace inspect`；
- 要求所有 `resources[].classification=healthy`；
- 要求 `operationalWorkspace` 非空；
- 将 `cr_id`、`tech_context`、`operationalWorkspace`、`resources`、review feedback 和 attempt 传给 Skill；
- Skill 失败时 abort；
- 输出节点间所需的结构化 execution context。

**删除：**

- SDD 章节清单；
- 术语、REST、决策记录等业务规则；
- 具体 `crctl advance` 命令；
- 具体 Git 命令和 commit 算法；
- blocker 逐条修复算法。

建议保留的最小形态：

```text
执行 write-tech-design。

先运行 `crctl workspace inspect {{inputs.cr_id}}`：
- 全部 resources[].classification 必须为 healthy；
- operationalWorkspace 必须非空；
- 失败则中止并指向 /resume，不猜测或拼接路径。

调用 write-tech-design，传入：
- cr_id
- tech_context
- operational_workspace
- resources
- review_feedback
- self_repair_attempt

SDD 内容、术语硬化、接口契约、文档校验、受控 Git、状态推进和回修语义，
均按 write-tech-design Skill 契约执行；Pipeline 不复制其算法。

消费 Skill 的结构化结果并输出 execution_context。
```

### 5.2 workspace 路径必须以 `workspace inspect` 为权威

Skill 和 Pipeline 不应拼接：

```text
.rayai-worktrees/{repo.id}/requirement/{cr_id}
```

正确边界：

1. Pipeline 调用 `crctl workspace inspect {cr_id}`；
2. 文档读写使用返回的 `operationalWorkspace`；
3. 各代码仓文件使用对应 `resources[].worktreePath`；
4. 资源不健康时中止并指向 `/resume`；
5. 禁止扫描目录、猜测 worktree 或使用会话中最近访问的其他仓库。

`write-tech-design` 的输入应显式接受：

```yaml
operational_workspace: string
resources: array
```

### 5.3 `ARCHITECTURE.md` 与 `sdd.md` 不能跨仓同一 commit

`sdd.md` 位于 knowledge-base worktree；`ARCHITECTURE.md` 可能位于独立代码仓。不同 Git 仓库不能共用一个 commit。

应改成：

> 新起草的 `ARCHITECTURE.md` 与 `sdd.md` 属于同一轮技术设计变更，但按各自 `resources[].worktreePath` 在所属仓库分别提交，最终由架构审批后的 checkpoint 纳入同一批次。

如果保留缺失时懒加载起草：

- 只为本 CR 实际涉及的代码仓起草；
- 各仓分别提交；
- Pipeline 必须提交这些实际新增文件，否则下一节点的 healthy 检查可能因为 dirty worktree 失败；
- 不得声称与 SDD 处于同一个 Git commit。

### 5.4 node-2：复制评审和 `review-record` 算法

节点：`ref=review-tech-design`。

当前 prompt 复制了：

- 具体评审维度；
- `.crctl/tmp/review-tech-design.yml` payload 格式；
- `crctl review-record` 调用方式；
- canonical annotation 写入；
- blocker 回退和 reviewLoop 处理。

应保留：

- workspace inspect 入口；
- `cr_id`、workspace context、review feedback、attempt 传递；
- 机器可读 `reviewLoop`、`replayNodes`、`passCondition`、`maxAttempts`；
- Pipeline 对 `verdict/blockers/repair-target/current-attempt` 的消费和路由。

应删除：

- 评审业务维度正文；
- 临时 payload 和 canonical 文件落盘算法；
- annotation、review-loop、traceability 写入细节；
- `crctl advance` 回退命令。

### 5.5 human approval：禁止直接改受保护 annotation

架构设计的人工审批提示要求：

```text
在 review-annotations/sdd.yml 补充 reject_reason
```

这是错误的。`review-annotations/*.yml` 在 `controlled-shell/rules.json#protectedPaths.deny` 中，由 `crctl review-record` / `crctl approve` 独占写入。

应改成：

```text
驳回：通过 approve-tech-design 的 reject 流程记录理由并回退到 tech-designing。
```

人工决定只进入 `approve-tech-design` 的受控流程；审批证据、CAS、审计和状态回退均由 `crctl approve` 完成。

### 5.6 node-4：复制审批实现

节点：`ref=approve-tech-design`。

当前 prompt 复制：

- grant 和 TTY 两条审批路径；
- `crctl approve` 命令；
- reject 业务结果码；
- approval evidence 和状态级联。

这些内容已经由 `approve-tech-design` Skill 和 `crctl approve` 承担。

Pipeline 只应：

```text
调用 approve-tech-design：
- cr_id
- approver

消费审批记录、当前状态和结构化结果；失败按 Skill 语义 abort。
```

摘要下一步统一使用：

```text
以 `crctl next {cr_id}` 为准
```

不得写死下一条 Pipeline 或 Skill。

### 5.7 node-5：复制 checkpoint 深原语

节点：`ref=push-progress`。

当前 prompt 复制 `crctl checkpoint`、daemon workspace 注入、phase complete 和重跑语义。

Pipeline 可以保留：

- 这是架构阶段终点 checkpoint；
- `phase` 非 complete 时本节点失败；
- checkpoint 失败不重新审批。

但具体 checkpoint 命令、workspace resolver、事务恢复和 Git 算法由 `push-progress` / `crctl` 负责。

最小输入：

```text
cr_id: {{inputs.cr_id}}
message: 架构设计已审批
```

## 6. `write-tech-design` 三项新增能力评审

### 6.1 术语硬化：采纳，但收窄范围

只处理以下术语：

- 会进入数据模型、状态机或接口契约；
- 存在一词多义、多词同义或代码别名；
- 边界会影响 FR/AC、角色权限或验收语义。

已有 `CONTEXT.md`、术语表或领域文档时，先只读并优先沿用；本 Skill 不新增跨 CR 长期术语资产。

技术设计不能改变已审批 PRD 的业务语义：

- 纯命名差异：以 PRD 业务语义为权威，记录 `PRD canonical term → 代码现有别名`；
- 会改变 FR/AC、权限、实体边界或验收语义：在首次状态推进前停止，要求需求负责人澄清；
- 不允许由 SDD 自行选择“采纳 PRD 还是代码一侧”。

建议文案：

> 仅硬化会进入数据模型、状态机或接口契约，且存在歧义、别名或边界风险的术语；每个风险术语至少用一个代表性边界场景验证。无歧义术语无需逐项展开。命名冲突记录 PRD 术语与代码别名映射；语义冲突不得由技术设计自行裁决。

术语预检应位于首次 `crctl advance` 之前，避免发现需求级歧义后留下没有 SDD、没有评审记录的 `tech-designing` 状态。

### 6.2 HTTP/REST 契约基线：条件触发、仓库约定优先

技术设计发生在编码前，不能以“diff 命中 REST 端点特征”触发。应改为：

> 当 PRD、tech_context 或拟定技术方案表明本 CR 将新增或修改 HTTP API 时触发。

优先级：

1. 目标仓 `ARCHITECTURE.md`、既有 OpenAPI/API 契约；
2. 现有客户端兼容性要求；
3. 两者均无规范时，才采用 Skill 默认基线。

默认基线可以要求：

- 资源化 URL；
- HTTP 方法语义正确；
- 成功/错误状态码有明确语义；
- 错误结构统一；
- 无界或大列表有分页策略；
- 偏离默认值时说明领域或兼容性理由；
- 禁止用 HTTP 200 包装所有错误。

不宜无条件强制复数资源名、kebab-case、固定 `error.code/message/details`、全部列表分页、固定 400/404/409/422 或所有创建都 `201 + Location`，因为 singleton、动作型端点、异步任务和既有客户端兼容性可能不适合这些规则。

SDD 写接口概要、输入、输出、错误、鉴权，以及条件性的幂等/分页约束即可；复杂或高风险接口再附最小 OpenAPI 片段，不要求在 SDD 中生成完整契约文件。

### 6.3 关键决策记录：轻量化

三判据同时满足时才记录：

1. 难以逆转；
2. 没有上下文会疑惑；
3. 存在真实权衡和替代方案。

推荐结构：

```text
Decision：最终选择
Context：问题和约束
Alternatives：真实考虑过的 1–2 个替代方案及未采用原因
Consequences：得到什么、失去什么
```

不要伪造替代方案，不新增独立 ADR 文件或审批节点。改变仓库级模块边界、依赖方向或硬不变量时，应按照 `ARCHITECTURE.md` 维护规则处理。

### 6.4 评审闭环必须同步

`review-tech-design` 应扩展现有维度，而不是新增评审节点：

- 数据模型完整性：术语唯一且与已审批 PRD 语义一致；
- 接口契约：按接口类型及目标仓既有规范应用条件基线；
- 架构合理性：满足三判据的决策包含真实 Alternatives 和 Consequences；
- 多仓架构约束：按 `resources[].worktreePath` 读取相关仓的 `ARCHITECTURE.md`。

## 7. requirement-authoring 审计

文件：`../tools/pipeline-templates/requirement-authoring.pipeline.json`

### 7.1 human approval：与架构审批相同的受保护路径问题

人工审批提示要求：

```text
在 review-annotations/requirement.yml 补充 reject_reason
```

这同样越过 `protectedPaths.deny`。应改为通过 `approve-requirement` 的 reject 流程记录理由并回退到 `drafting`，不得让人工直接编辑 annotation。

### 7.2 approve-requirement：复制审批实现且输入契约漂移

节点：`ref=approve-requirement`。

当前 prompt 直接描述：

- `crctl approve --stage requirement`；
- TTY 审批路径；
- `approval.yml`；
- 状态级联；
- 下一条 architecture pipeline。

问题：

- 缺少 `{cr_id}` 的完整命令形态；
- 只描述 TTY，遗漏 Skill 已支持的非 TTY signed grant；
- 复制 `crctl` 的证据、CAS 和状态算法；
- 下一步写死为 architecture pipeline，违反统一的 `crctl next` 规则。

最小改造：

```text
读取 execution_context，调用 approve-requirement：
- cr_id: {execution_context.cr_id}
- approver: {execution_context.owners.requirement.id}

消费审批记录、当前状态和结构化结果；下一步以 `crctl next {cr_id}` 为准。
```

### 7.3 review-requirement：复制 review-record 和评审业务

节点：`ref=review-requirement`。

当前 prompt 复制：

- US/FR/AC 评审维度；
- 临时 review payload；
- `crctl review-record`；
- annotation、review-loop、traceability 写入；
- blocker 回修算法。

`reviewLoop` 的机器字段应保留在 Pipeline；评审内容、payload、canonical 写入和状态路由由 `review-requirement` Skill 与 `crctl` 拥有。

### 7.4 requirement-register：已有下沉声明，但仍复制命令和路径结构

节点：`ref=requirement-register`。

当前 prompt 已声明“Pipeline 不展开注册、账本、Git、worktree 或恢复算法”，方向正确，但仍内联：

- 完整 `crctl register` 参数序列；
- registration key 派生示例；
- 绝对路径形式的 execution context 示例；
- repo worktree 结构。

可保留输入映射和结构化结果消费，删除具体命令、路径派生和账本细节。路径值应由 Skill/crctl 返回，Pipeline 不自行构造。

### 7.5 write-requirement-prd：复制 PRD 内容和回修算法

节点：`ref=write-requirement-prd`。

当前 prompt 复制：

- PRD 章节清单；
- 主 workspace 禁写规则；
- 具体落盘路径；
- blocker 逐条修复。

这些属于 `write-requirement-prd` Skill。Pipeline 只传 `cr_id`、`source`、review feedback、attempt 和运行时 context。

### 7.6 requirement-authoring 应保留的内容

- register → PRD → optional checkpoint → review → human approval → approve → checkpoint 顺序；
- `auto_push_after_prd` 的 skip/execute 编排；
- reviewLoop 机器字段；
- `onFail`；
- execution context 的节点间传递；
- 人工审批节点本身。

## 8. code-implementation 审计

文件：`../tools/pipeline-templates/code-implementation.pipeline.json`

### 8.1 approve-dev-start：复制审批实现

节点：`ref=approve-dev-start`。

当前 prompt 复制：

- owners 和 assigned-at 校验；
- plan、tasks、TASK 文件存在性；
- `crctl approve`；
- approval.yml；
- 状态级联；
- 下一步 implement-code。

应由 `approve-dev-start` Skill 和 `crctl approve` 负责。Pipeline 只传 `cr_id`、approver，消费结构化结果，并用 `crctl next` 提示下一步。

### 8.2 approve-code：同类审批复制和契约漂移

节点：`ref=approve-code`。

当前 prompt：

- 复制 `crctl approve --stage code`；
- 复制 test-report tester 与 owner 的校验；
- 复制 approval.yml 和 status 写入；
- 只描述 TTY；
- 下一步写死为 writeback pipeline。

应只调用 `approve-code`，传入 CR-ID、approver，消费审批结果。grant、证据 digest、审批回退和状态推进交给 Skill/crctl。

### 8.3 human approval：直接修改代码评审账本

代码审批提示要求：

```text
在评审批注中补充 reject_reason
```

这里没有明确文件名，但在当前流程中会导向 `review-annotations/code.yml`。人工审批不得直接改 canonical annotation，应由 `approve-code` 的 reject 流程记录并回退到 `developing`。

### 8.4 review-dev-plan：复制八维评审和双轨回退算法

节点：`ref=review-dev-plan`。

当前 prompt 复制：

- SDD→plan→TASK 八类评审维度；
- 临时 payload 和 `crctl review-record`；
- annotation、traceability、review-loop 写入；
- `NORMAL` / `UPSTREAM` 双轨状态回退；
- `--embedded` 和完整 trigger。

这些已经由 `review-dev-plan` Skill 和 `crctl review-record/advance` 定义。Pipeline 只保留：

- 传入 CR-ID、workspace context、review feedback、attempt；
- 消费 verdict、blockers、repair-target；
- 以 `reviewLoop.replayNodes` 编排普通回修；
- upstream 结果触发 Pipeline abort 或既有路由。

### 8.5 write-test-report：复制 `crctl test` 深原语

节点：`ref=write-test-report`。

当前 prompt 复制：

- `cr-test-plan/v1` schema；
- executable/args/timeout 白名单；
- `crctl test` 命令；
- test-report 机器区和 marker；
- traceability/review-loop 原子更新；
- status=block 的证据语义。

这些由 `write-test-report` Skill 和 `crctl test` 拥有。Pipeline 只传：

```text
cr_id
source_node
 tester
review_feedback
self_repair_attempt
```

并消费 `status`、`blockers`、报告路径。`reviewLoop` 保留实现 → 测试报告的重放关系。

### 8.6 review-code：复制完整代码评审取证算法

节点：`ref=review-code`。

当前 prompt 复制：

- reviewer runner 选择；
- review payload 和 `review-record`；
- diff/log/merge-base 取证命令；
- test-report、traceability、test-evidence 证据规则；
- 代码评审维度；
- blocker/suggestions 语义；
- 回修时实现、测试、checkpoint、freshness 重建算法。

应保留：

- 传入 CR-ID、workspace、resources、review feedback、attempt；
- 消费 verdict、blockers、test-report.status、repair-target；
- `reviewLoop.replayNodes`：implement → test-report → checkpoint → freshness → review-code。

其余删除，交给 `review-code` Skill、`crctl test`、`review-record` 和现有 freshness Skill。

### 8.7 write-dev-plan：复制 plan 章节

节点：`ref=write-dev-plan`。

当前 prompt 复制 plan 章节、status 校验和输入文件。`write-dev-plan` Skill 已拥有这些内容。

Pipeline 只传：

```text
cr_id
 target_version
review_feedback
self_repair_attempt
operational_workspace/resources
```

### 8.8 write-dev-tasks：复制 TASK 格式和 task init

节点：`ref=write-dev-tasks`。

当前 prompt 复制：

- TASK 文件内容结构；
- 接口签名规则；
- `crctl task init`；
- estimate 交叉校验；
- 索引失败语义。

`write-dev-tasks` Skill 负责业务拆分，`crctl task init` 负责受控索引。Pipeline 只传输入并消费 TASK 列表、估算和结构化结果。

### 8.9 implement-code：已部分正确，继续收窄

节点：`ref=implement-code` 已明确由 Skill 负责 runtime、仓库路径、依赖顺序、并发和写入边界，这是正确方向。

仍可删除：

- Pipeline 自己描述 runtime fallback；
- PRD/SDD/TASK 读取清单；
- TASK 依赖、回修根因和验证算法。

保留：

- execution context 和 `resources[].worktreePath` 传递；
- 调用 `implement-code`；
- 消费变更范围、runtime、session、验证结果；
- reviewLoop 回修输入。

### 8.10 workspace-freshness：重复 Skill 路由算法

实施前和评审前两个节点均复制了 `workspace-freshness` Skill 的：

- syncable 条件；
- freshness/sync 调用；
- continue/synced-continue/replay/manual 路由；
- 逐仓失败处理。

Pipeline 应只传 `cr_id` 和 gate 名称，消费 route：

- `continue` / `synced-continue`：继续；
- `replay`：按现有 reviewLoop 重放；
- `manual`：abort。

具体 freshness 分类和同步算法由 `workspace-freshness` Skill + `crctl` 拥有。

### 8.11 code-implementation 应保留的内容

- plan → TASK → review-dev-plan → human approval → developing；
- 实施前 freshness gate；
- implement → test-report → checkpoint → freshness → review-code；
- reviewLoop 的 replayNodes、passCondition 和 maxAttempts；
- 代码评审前必须已有 test-report；
- 代码审批前必须经过 checkpoint 和人工审批。

## 9. product-planning 审计

文件：`../tools/pipeline-templates/product-planning.pipeline.json`

规划 Pipeline 没有 CR 上下文，因此规划评审的本地 `review-annotations` 可以继续由 `review-planning-report` Skill 持久化，不需要引入 `crctl review-loop`。但是 Pipeline 仍不应复制这些 Skill 的算法。

### 9.1 node-1：缺少 `topic`，同时复制反馈分析算法

节点：`ref=analyze-user-feedback`。

Skill 的必填参数是 `topic`，当前 prompt 只处理 `skip_feedback`，没有传主题。应至少传：

```text
topic: {{inputs.topic}}
skip_feedback: {{inputs.skip_feedback}}
```

TOP5、分类统计、引用原文和评分规则由 Skill 负责，Pipeline 不复制。

### 9.2 node-2：缺少 `topic`，同时复制市场报告落盘规则

节点：`ref=conduct-market-research`。

Skill 的必填参数是 `topic`，当前 prompt 只处理 skip 和 topic 的文字展示，没有形成明确参数映射；同时复制具体路径、frontmatter id 和 `_index.yml` 规则。

应由 Pipeline 传 `topic`、`target_version` 和 skip 标志，Skill 负责落盘、命名和索引。

### 9.3 node-3：竞品报告调用契约不完整

节点：`ref=write-competitive-report`，但 prompt 声称“经 fetch-competitor-updates 采集 + write-competitive-report 生成”。

`write-competitive-report` 的必填输入包括：

- `updates-block`；
- `product-snapshot`；
- `confirmed`。

当前 product-planning Pipeline 没有明确的 fetch 节点、产品快照节点或这些输入映射，因此不是单纯 prompt 过长，而是流程契约不完整。

最小改造方向：

- 明确该 Pipeline 如何取得现有 `fetch-competitor-updates` 输出和 `gather-product-context` 快照；或
- 让现有 Skill 自己调用已经存在的上下文能力；
- 不要在 Pipeline prompt 中假装一个 `write-competitive-report` 节点同时拥有两个 Skill 的输入和业务逻辑。

### 9.4 node-4：应传主题，删除产品现状读取算法

节点：`ref=analyze-current-product`。

Skill 的必填参数是 `topic`；当前 prompt 没有明确传入。`specs/_index.yml`、`_history.yml`、metrics 等读取清单和 gap 分析规则属于 Skill，应删除。

### 9.5 node-5：回修输入没有传递

节点：`ref=write-planning-report`。

当前 prompt复制章节、路径和索引规则，但没有明确传：

- `prev_outputs`；
- `review_feedback`；
- `self_repair_attempt`。

这会使 `reviewLoop` 回修无法可靠消费 blocker。建议传上游结构化产物、主题、目标版本、review feedback 和 attempt，报告章节、文件名与 `_index.yml` 由 Skill 负责。

### 9.6 node-6：复制规划评审持久化

节点：`ref=review-planning-report`。

当前 prompt复制：

- 评审维度；
- review annotation 路径；
- `_index.yml` 状态更新；
- 轮次持久化；
- blocker 回修说明。

规划类没有 CR 上下文，Skill 自己持久化本地评审记录是合理的；但这些规则不应再在 Pipeline prompt 复制。Pipeline 只传报告路径、reviewer、topic、target version、feedback 和 attempt，消费 `approved/blockers/repair-target/current-attempt`。

### 9.7 node-7：复制 roadmap 写入算法

节点：`ref=write-roadmap`。

当前 prompt复制：

- 按版本/季度分组；
- 幂等追加；
- 保留既有条目；
- `_index.yml` 状态更新。

这些属于 `write-roadmap` Skill。Pipeline 应传 `topic`、`target_version`、`planning_report_path`。

此外，当前 prompt要求同步更新规划报告 `_index.yml` 为 `approved`，但 `write-roadmap` Skill 的明确写入范围是 `roadmap.md`，这个额外写入不能临时放在 Pipeline 中。应删除，或在 Skill 契约中明确增加该能力；优先删除，避免跨文档写入越界。

### 9.8 人工审批提示

规划类人工审批提示要求在报告末尾补 `reject_reason`。规划文档不属于 CR 受保护 annotation，但人工审批节点仍应只表达结构化的 `approve/reject + reason`，不把修改产物的操作混入 approval prompt。驳回即中止当前正向链；若需要修订，按正常 Pipeline 重跑或既有 reviewLoop 处理，不要求人工直接改报告。

## 10. market-to-plan 审计

文件：`../tools/pipeline-templates/market-to-plan.pipeline.json`

### 10.1 node-1：输入映射基本正确，但业务细节不应复制

节点：`ref=extract-market-insight`。

`insight_source`、`insight_type`、`target_version` 的输入映射方向正确。TOP5、可信度、索引状态和 raw 文件格式属于 Skill，应删除。

### 10.2 node-2：brief 调用契约没有在 Skill 中明确

节点再次调用 `ref=extract-market-insight`，当前 prompt 使用：

- `source`，但该字段不是 Skill 声明的输入；
- raw 文件路径；
- 独立 `brief-*.md` 路径；
- brief 章节和状态更新。

当前 Skill 已将原 `write-insight-brief` 合并为“简报附加区块”，但没有明确一个机器可传的 `mode` 或 `raw_insight_path` 参数。因此这里既有 Pipeline 重复算法，也有 Skill 输入契约不完整。

最小改造：

- 为 Skill 增加最小显式模式/来源输入，例如 `mode=brief`、`raw_insight_path`；
- Pipeline 只传这两个业务参数；
- brief 正文、路径和 index 状态仍由 Skill 负责。

不要在 Pipeline 里临时用 `source` 伪造 Skill 参数。

### 10.3 node-3：`planning-draft` 缺少必填 `context` 和 `intent`

节点：`ref=planning-draft`。

Skill 的必填输入是：

- `context`；
- `intent`。

当前只传洞察简报文本和 `target_version`，没有对齐这两个参数，同时复制了固定章节和优先级规则。

最小改造：传：

```text
context: {产品上下文或既有上下文 Skill 的结构化输出}
intent: {从洞察简报提炼的一句话规划意图}
scope/focus: {已有输入，如适用}
```

如果当前 Pipeline 无法提供产品上下文，应先明确复用已有 `gather-product-context`，不要让 `planning-draft` 接收一个未声明的“简报”替代 `context`。

### 10.4 node-5：Pipeline 额外修改 market-insights index

节点：`ref=write-planning-entry`。

该 Skill 的明确职责是将已审批草稿写入 `docs/product-planning/` 并维护该目录 index。当前 prompt额外要求修改 `docs/market-insights/_index.yml` 的生命周期状态为 `published`。

这是跨文档账本写入，且不在 `write-planning-entry` 的参数和写入契约中。最小选择只有两个：

1. 删除 Pipeline 中这项跨文档写入；
2. 另行扩展 `write-planning-entry` 的明确输入和职责。

不能让 Pipeline 临时拥有这项账本算法。更保守的默认是删除，待真实需求证明需要再单独设计。

## 11. competitive-radar 审计

文件：`../tools/pipeline-templates/competitive-radar.pipeline.json`

这是当前最明显的流程闭环问题之一。

### 11.1 node-1：输入名称与 Skill 不一致

Pipeline 使用：

- `competitor_slug`；
- `since_days`；
- `focus_dimension`。

`fetch-competitor-updates` Skill 使用：

- `competitor-id` / `competitor-ids[]`；
- `lookback-days`。

Pipeline 必须做显式参数映射，或统一 Skill 参数名，不能让 prompt 自行猜测。`slug` 与竞品 ID 不是天然等价，必要时先按现有竞品索引解析。

### 11.2 node-2：缺少报告生成所需输入

节点：`ref=write-competitive-report`。

Skill 必填：

- `updates-block`；
- `product-snapshot`；
- `confirmed`。

当前只传前一节点输出和 focus，缺少 `product-snapshot`，也没有明确结构化的 `updates-block` 映射。

报告固定章节、报告路径、竞品主文件 updates、reports index 和两阶段落盘规则属于 Skill，不应复制到 Pipeline；但必填输入必须补齐。

### 11.3 node-3：报告尚未落盘，却要求 `reportPath`

节点：`ref=report-to-planning-suggestion`。

`report-to-planning-suggestion` 当前要求读取已经存在的：

```text
docs/competitive/reports/{competitor-id}-{YYYY-MM-DD}.md
```

但 node-2 使用 `confirmed=false`，按 Skill 契约只生成草稿、不落盘。node-3 无合法 `reportPath` 可读，流程无法执行。

在不增加节点、不提前落盘正式报告的前提下，采用最小契约扩展：

- `report-to-planning-suggestion` 支持 `reportPath` 与 `reportDraft` 二选一；
- `reportDraft` 至少包含草稿正文、`competitorId`、`reportDate` 和来源节点/来源标识；
- `reportPath` 与 `reportDraft` 同时存在时优先使用 `reportPath`；
- 草稿模式只消费输入并生成规划建议，不落盘竞品报告；
- node-5 人工确认后先以 `confirmed=true` 落盘正式报告，再由 `write-planning-entry` 落盘规划建议。

不允许在 Pipeline 中把 `node-2.md` 伪装成 `reportPath`。

### 11.4 node-5：一个节点混合两个 Skill 的写入

节点 `ref=write-planning-entry` 的 prompt 又要求：

- 调用 `write-planning-entry` 写规划文档；
- 调用 `write-competitive-report confirmed=true` 写竞品报告和索引。

这使一个 Pipeline node 的 `ref` 与实际职责不一致，也没有传递报告 Skill 阶段 B 所需的 `updates-block`、`product-snapshot` 等输入。

最小改造方向：

- node-5 在人工确认通过后，顺序调用两个已有 Skill：先调用 `write-competitive-report(confirmed=true)` 落盘正式竞品报告，再调用 `write-planning-entry(source=node-3.md)` 落盘规划条目；
- 两个 Skill 的写入算法、校验和路径规则仍分别归各自 Skill，Pipeline 只编排调用顺序和传递 `updates-block`、`product-snapshot`、`confirmed` 等输入；
- 如果运行时的单个 node 不允许顺序调用多个 Skill，应在现有运行时编排能力中显式支持该调用，不新增业务 Skill 或事务层；
- 不在 `write-planning-entry` prompt 中复制另一份报告落盘算法。

## 12. feature-writeback 审计

文件：`../tools/pipeline-templates/feature-writeback.pipeline.json`

该 Pipeline 已基本完成职责下沉：

- node-1 调用 `merge-feature-branch`，没有展开跨仓 merge saga；
- node-2/3/4 只传 `cr_id/spec_id/target_version` 等业务输入；
- node-5 调用 `cr-archive`，没有复制清理和恢复算法；
- writeback generator、manifest、Git、状态和事务均由深原语拥有。

仍有一处轻度重复：

```text
校验 cr.md 当前 status=code-approved，否则 abort
```

这已经由 `merge-feature-branch` / `crctl merge` 校验。Pipeline 可以保留失败中止，但应删除这条具体 status gate，避免与 Skill/crctl 形成第二份判断。

node-2 至 node-5 目前接近最小形态，无需重构。

## 13. resume-cr 审计

文件：`../tools/pipeline-templates/resume-cr.pipeline.json`

### 13.1 node-1/node-2 基本合格

- `list-remote-checkpoints` 负责 checkpoint、SHA、drift 和 active repo 事实；
- `resume-from-remote` 负责 fetch、worktree、路径派生和恢复算法；
- Pipeline 只消费结构化结果。

### 13.2 node-3：复制 `cr-show` 详情和 next/status 算法

节点：`ref=cr-show`。

当前 prompt要求 Pipeline 自行读取并组织：

- `_backlog.yml`；
- `cr.md`；
- PRD/SDD/TASK/test-report/review annotations；
- 最近三次 push-progress；
- `crctl next`；
- `crctl status` 与 `STATUS_DIVERGED`。

`cr-show` Skill 已拥有 CR 定位、关联文件读取、详情构造和 `crctl next`。Pipeline 不应维护这份字段清单和账本定位规则。

建议：

```text
调用 cr-show：
- cr-id: {{inputs.cr_id}}
- section: all

消费并输出 cr-show 的结构化详情。
下一步由 cr-show 内部调用 `crctl next` 计算。
```

如果“最近三次 checkpoint”是产品必需展示项，应补入 `cr-show` Skill 的输出契约，而不是只写在 Pipeline prompt 中。

## 14. P0 / Blocker 清单

以下问题应优先进入正确性 CR。

### 14.1 受保护评审账本的直接修改指引

涉及：

- `requirement-authoring` human approval；
- `architecture-design` human approval；
- `code-implementation` human approval。

修正统一为：

```text
人工只提交 approve/reject 决定及理由；
approve-* Skill 调用 crctl approve；
crctl 负责 approval、CAS、审计、证据绑定和状态回退。
```

### 14.2 product-planning 竞品节点输入不完整

`write-competitive-report` 必须有 `updates-block`、`product-snapshot`、`confirmed`。当前 Pipeline 没有完整提供，且没有明确 fetch/context 来源。

### 14.3 market-to-plan 的必填参数缺失

`planning-draft` 缺 `context` 和 `intent`。这会使节点无法按 Skill 契约执行。

### 14.4 competitive-radar 的草稿/落盘顺序矛盾

node-2 `confirmed=false` 不落盘，node-3 却要求已落盘 `reportPath`；node-5 又混合两个 Skill 的落盘职责。必须先决定最小业务闭环，不能只改文字。

## 15. P1 清单

### 15.1 审批节点

- `approve-requirement`：删除 `crctl approve` 细节、补完整 CR-ID 输入、支持 Skill 统一的 grant/TTY 契约、下一步改 `crctl next`。
- `approve-tech-design`：删除 grant/TTY/reject 细节，只保留 Skill 输入输出。
- `approve-dev-start`：删除 owners/plan/tasks/approval/CAS/status 细节。
- `approve-code`：删除 test-report owner 校验复制和审批实现复制，下一步改 `crctl next`。

### 15.2 评审和测试节点

- `review-requirement`：删除评审维度、临时 payload、review-record、annotation 和轮次写入细节。
- `review-tech-design`：同上，并把新增术语/REST/决策要求补回 Skill 评审维度。
- `review-dev-plan`：删除八维业务评审、双轨 advance 和 embedded 细节，仅保留 reviewLoop。
- `write-test-report`：删除 test plan schema、marker、traceability 原子更新描述。
- `review-code`：删除 diff/log/merge-base、test evidence、review-record 和评审算法复制。

### 15.3 输入和工作区

- `write-tech-design`：以 `workspace inspect` 的 `operationalWorkspace/resources` 为唯一路径事实。
- requirement register：删除完整 register 命令和路径结构示例。
- code implement：删除 runtime fallback、读取清单和并发算法复制。
- freshness：Pipeline 只传 gate，Skill 负责 route。

## 16. P2 清单

### 16.1 文档章节和落盘路径

应从 Pipeline 删除：

- PRD/SDD/PLAN/TASK/规划报告固定章节；
- 文件名和 slug 派生；
- `_index.yml` 字段和排序规则；
- review annotation 文件结构；
- roadmap 幂等追加细节；
- 竞品报告固定章节。

这些内容由对应 Skill 或 `engineering-docs`/版本化脚本负责。

### 16.2 展示节点

- `resume-cr` node-3 的 CR 详情字段和状态映射回 `cr-show`；
- human approval 的输出统一消费 Skill 结果，不写死下一 Pipeline。

### 16.3 feature-writeback

仅删除 node-1 的重复 `code-approved` 预检，其他节点保持现状。

## 17. Pipeline 中应保留什么

每个 `kind=skill` 节点的 prompt 最多保留：

1. 调用哪个 Skill；
2. 传入哪些参数；
3. 依赖哪个前序节点的结构化输出；
4. 消费哪些结构化结果；
5. 失败如何 `abort/skip` 或进入 reviewLoop。

Pipeline JSON 继续作为以下机器事实源：

- node 顺序；
- `ref`；
- 输入传递；
- `reviewLoop`；
- `replayNodes`；
- `passCondition`；
- `onFail`；
- timeout；
- human approval 节点。

不要把上述机器字段搬回 Skill 文本，也不要让 Skill 另写一份 reviewLoop 规则。

## 18. 一个 CR 内的两阶段改造

### 18.1 阶段一：先修能失败或越权的问题

范围：

1. 三条 CR Pipeline 的 human approval reject 指引；
2. `product-planning` 的 topic、竞品输入和回修输入；
3. `market-to-plan` 的 `context/intent` 与 brief 输入契约；
4. `competitive-radar` 的 report draft/confirmed 流程；
5. approve 节点遗漏 CR-ID、grant 模式和 `crctl next` 的明显契约漂移。

### 18.2 阶段二：同一 CR 内收敛职责

按以下顺序：

1. `architecture-design`：node-1/2/4/5；
2. `requirement-authoring`：register/PRD/review/approve；
3. `code-implementation`：plan/TASK/review-dev-plan/test/review-code/approve；
4. `resume-cr`：cr-show；
5. `feature-writeback`：一行级预检删除；
6. 规划类 Pipeline：章节、路径、索引和评审持久化下沉。

两阶段只表示同一个 CR 内的实施顺序，最终一次性完成该 CR 的评审、代码验证和回写，不拆成多个 CR。

不改：

- Pipeline 节点数量，除非 competitive-radar 的业务闭环无法在现有节点内表达；
- 状态机；
- gates；
- crctl 深原语；
- 事务框架。

## 19. 不应顺手处理的内容

以下内容不属于本次 prompt 职责治理的必要范围：

- 新建通用 Runner 框架；
- 统一所有历史文档 schema；
- 把规划类本地 review annotations 强行迁移到 crctl；
- 为每个 Pipeline 新建事务日志；
- 重新实现 worktree、merge、checkpoint、archive；
- 改造状态机或增加 gate；
- 新增独立 ADR、跨 CR CONTEXT 或术语中心；
- 把 README 扩展成可执行 Pipeline 事实源。

## 20. 建议自检

修改 Pipeline JSON 后：

```bash
node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8')); console.log('json ok')"
node skills/shared/crctl/scripts/lint-prompts.mjs
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
```

修改 Skill 后还应检查：

- `skills/_index.yml` 无需变化时确认 active ref 未变；
- `agent-skill-matrix.yml` 无新增 Skill 时无需变化；
- 写入型 Skill 明确调用 `validate-doc` 或等价校验；
- 涉及 Git/shell 的调用符合 `controlled-shell`；
- CR 上下文摘要统一写“以 `crctl next {cr_id}` 为准”；
- 不直接写受保护账本；
- 所有跨行解析和哈希逻辑遵守 CRLF 规范化及硬失败纪律。

## 21. 最终建议

当前问题的本质不是缺少基础设施，而是基础设施已经存在后，旧的过程细节仍被复制在 Pipeline prompt 中。

正确的最小方向是：

```text
Pipeline：调用哪个 Skill、传什么、按什么 reviewLoop 重放、失败去哪
Skill：业务判断、内容生成、结果分类和失败语义
crctl：状态、门禁、账本、CAS、审批、测试证据和原子事务
版本化脚本：确定性文档转换
```

因此：

- 先修正 P0 输入契约和受保护路径问题；
- 再删除 P1/P2 重复算法；
- 继续复用现有 `workspace inspect`、`crctl` 深原语、`review-record`、`approve`、`test`、`task`、checkpoint、writeback generator 和领域 Skill；
- 不引入新的事务框架或 Pipeline 专用治理层。

本文件是本轮审计建议的汇总，不代表已修改任何 tools 文件或已经创建 CR。当前规划为一个 CR 内按“先正确性、后职责收敛”完成全部 P0/P1/P2 改造。
