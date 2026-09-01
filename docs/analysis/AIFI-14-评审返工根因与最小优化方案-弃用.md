# AIFI-14 评审返工根因与 tools 最小优化方案

> 审核后方案基线
>
> 分析对象：AIFI-14 / CR-2026-056「会话级配置与 Team Agent 闭环」
>
> 分析日期：2026-08-30
>
> 文档性质：平台流程优化方案，可作为后续 tools 优化 CR 的前置依据；不直接实施代码，不替代后续 CR 的 PRD、SDD、TASK、代码评审或人工审批。

## 1. 审核结论

本方案的目标是：**带着降低后续 CR 返工的目标设计评审流程，使评审在首轮尽可能完整地发现当前范围内的独立根因，同时不降低 blocker 判断标准、不扩大 CR 范围、不重复建设已经存在的治理基础设施。**

“降低后续 CR 返工”是本方案的设计目标和取舍标准，不是 tools 的新业务功能。它不引入返工率字段、统计账本、看板、专用 Pipeline、状态、traceability 字段或第二套 review ledger。

本次审核对原方案的优先级重新排序：原先针对在途 AIFI-14 的 P0 已因问题解决而移出待办，review Skill 流程优化上升为 P0，静态检查保留为条件触发的 P1。因此本文只保留两个有明确内容的后续优化层，不虚构一个没有实施内容的 P2。

审核后的方案作出以下决策：

1. **复用现有基础设施**：状态、门禁、CAS、受控账本写入、审计、原子提交、reviewLoop、attempt 记账和评审记录继续由现有 `crctl` 与 Pipeline 机制负责。
2. **P0 只优化 review Skill**：优化四类现有评审 Skill 的输入边界、评审清单、严重性分级、调用者闭包和回修反馈语义。
3. **P1 只作条件触发候选**：只有真实失败重复出现且能够由确定性规则判断时，才考虑补充静态检查；不因“可能有用”提前建设。
4. **严格保持职责边界**：不把 Agent、Pipeline、Skill、`crctl`、版本化脚本或 README 变成另一个模块的职责承载者。
5. **后续 CR 必须重新核验事实**：本文提供决策基线和历史证据，但不冻结会变化的仓库、Skill、代码或运行时事实。

本方案通过不等于 tools 变更已经实施，也不等于后续 CR 获得实施审批。后续 CR 仍须分别完成需求、技术设计、开发计划、代码评审和人工审批。

## 2. 目标与边界

### 2.1 设计目标

后续 CR 应能够在评审前和首轮评审中完成以下工作：

- 明确当前 CR 的批准范围、排除项和本轮实际变更；
- 对同一 API、任务、共享函数或公共组件一次性检查完整契约；
- 对会影响共享路径的设计先闭合调用者范围，再决定修改、兼容保留或排除；
- 把影响实现、验收、安全、编译或范围判断的缺陷及时列为 blocker；
- 让回修只围绕当前 CR 必须处理的 blocker 展开，不因修复而无界扩大范围；
- 使 review feedback、当前产物和真实仓库事实保持一致。

### 2.2 明确不做

本方案不做以下事项：

- 不重新修复已经解决的 AIFI-14 在途问题；
- 不修改 `../multica` 产品代码；
- 不在本次方案审核中修改 `../tools`；
- 不新增 Agent、Pipeline、Runner 或通用工作流引擎；
- 不新增第二套状态机、门禁、CAS、Git 算法、事务框架或 review ledger；
- 不让 Skill 手写 YAML 账本、review annotation、review-loop 或 traceability；
- 不让 reviewer 在代码评审阶段自行重跑测试以代替正式证据；
- 不把降低返工转化为 tools 的业务字段、统计产品或硬性通过率指标；
- 不把 README 变成可执行事实源；
- 不保证复杂 CR 必然一次评审通过，也不通过放宽 blocker 标准换取通过率。

## 3. AIFI-14 案例与事实

### 3.1 需求评审暴露的根因

AIFI-14 的 PRD 评审经历三轮：

| 阶段 | 事实 |
|---|---|
| 第 1 轮 | 发现 B-001、B-002；同时指出 runtime offline、四语 parity、NFR-8 schema/fallback、草稿 TTL 等建议补充项 |
| 第 2 轮 | B-004、B-005 与第 1 轮建议相关的关键语义被升级为 blocker；B-003 与 B-002 属于同一 HTTP 契约未一次闭合 |
| 第 3 轮 | PRD 通过 |

两个问题具有代表性：

- B-002 检查了显式创建容器的 endpoint、request 和幂等关系，但没有同时闭合 response schema 与 `session_id`/`issue_id` 观察点；B-003 因此在下一轮才暴露。
- runtime offline、catalog 来源和 fallback 的语义会直接影响当前 FR/AC 是否能够实现和验收，却被首轮放入 suggestion。作者补充了表面 AC 后，关键行为仍不唯一，下一轮才升级为 blocker。

这说明需求评审需要按完整契约审查，而不是按“先找几个 blocker、其余以后再看”的顺序推进。

### 3.2 技术设计评审暴露的根因

AIFI-14 的 SDD 评审经历三轮。首轮发现的 session 隔离、首次发送原子性、显式 container readiness、`chat_config` 快照、草稿对象清理和 Private Ask 查询条件等问题，属于应保留的质量要求。

后续评审暴露了两个流程层面的典型问题：

1. 修复共享 Team Agent 容器路径时，没有在写方案前列出所有 caller，直到后续才发现 Discussion Coordinator 转投路径也会受影响。
2. 方案为解决接口问题先写了 service 伪代码，但没有先绑定真实 `pkg/agent` API，产生了未导出 symbol 和 loader/Catalog 签名不一致的问题。

AIFI-14 后续已经完成处置。本节只保留案例结论：**共享路径修复必须先闭合调用者和兼容边界；既有领域能力必须先核验真实 symbol、签名和行为，再写设计接口。**

### 3.3 计划与代码评审的同类问题

历史评审记录显示，开发计划和代码评审也存在首轮不收敛，但不应把所有多轮评审都归因于 reviewer 漏审。

开发计划评审中出现过：

- SDD 到 plan/TASK 覆盖缺失；
- 依赖拓扑、实际 cwd、worktree 和命令不可执行；
- 虚构或错误的 `crctl` 命令参数；
- 共享 generated 目录并行冲突；
- TASK 验收命令和责任边界不具体。

代码评审中出现过：

- 跨 workspace source task 隔离风险；
- 测试报告声称真实数据库测试但实际 skip；
- TASK 状态仍为 pending；
- test report、traceability、测试日志和当前代码变更不一致。

这些属于应保留的质量 blocker。流程优化的方向是把能够确定判断的路径、命令、签名、依赖和证据一致性问题前移，而不是让 reviewer 放宽标准或让代码评审承担更多测试执行权限。

## 4. 已解决基础设施：继续复用，不再重造

以下能力已经存在，是本方案的基础，不属于本次改造对象：

| 能力 | 既有承载 | 本方案处理 |
|---|---|---|
| 状态、门禁、CAS、受控账本写入 | `../tools/skills/shared/crctl/` | 继续复用，不新增事务框架 |
| 评审原子记录 | `crctl review-record` 同批写 annotation、review-loop、traceability | Skill 只产出临时判断，不直接写三本账 |
| 评审轮次与上限 | Pipeline `reviewLoop.maxAttempts`、`crctl attempt` | 不提高轮次上限掩盖漏审 |
| reviewLoop 回放 | Pipeline `replayNodes[]` | 只修正回放输入和目标，不增加隐藏节点 |
| workspace/resource authority | `workspace inspect`、`execution_context` | 继续消费原样路径，不拼接或回退路径 |
| plan/TASK 账本 | `crctl task init/done/append` | 不造任务状态写入器 |
| 代码测试证据 | `crctl test`、test report、test evidence、subject digest | reviewer 继续只读取证据，不重跑测试 |
| PRD/SDD/TASK 转换 | 现有版本化脚本和模板 | 不新增转换器 |

职责原则是：**已有底座负责确定性状态和受控写入，评审 Skill 只负责业务判断与评审编排。**

## 5. P0：review Skill 最小流程优化

P0 是本方案唯一的直接优化方向，后续应作为 tools 优化 CR 的最小范围。P0 不改变状态机、Pipeline 节点数量、`crctl` 命令或账本格式。

### 5.1 所有评审 Skill 的共同要求

四类 review Skill 共享以下原则，但不复制成完全相同的评审算法：

1. **评审前冻结范围**：读取当前阶段的批准基线、当前产物、明确排除项和实际 diff。范围外发现记录为上游需求或后续 CR，不得直接扩大当前产物。
2. **首轮完成全量适用维度**：不得在发现第一个 blocker 后提前结束；先完成全部适用维度，再统一生成 verdict。
3. **按契约闭合检查**：对 API、任务、共享函数、事件或公共组件，按适用情况检查 input/request、output/response、错误、权限、并发/幂等、观测和测试。
4. **共享调用者闭包**：若设计或修复涉及已有函数、查询、索引、队列内核或公共组件，先列出所有 caller，并为每个 caller 标注 `modify`、`compatibility` 或 `out-of-scope`。
5. **先核验真实事实**：设计中引用的已有 symbol、路径、签名、命令和行为，必须按目标 worktree 和既有 authority 核验；跨行或结构化解析失败必须报错，不得静默当作空结果。
6. **统一严重性分级**：
   - `blocker`：当前 CR 无法唯一实现、无法验收、造成数据/权限/安全风险、可能编译失败、接口不一致，或违反已批准范围；
   - `suggestion`：不影响当前实现、测试、发布安全和范围判断的表达、可读性、未来优化或人工审批前补充信息。
7. **建议不静默升级**：上一轮 suggestion 不得仅因作者没有采纳就自动变成 blocker。只有本轮核实其实际影响当前范围内的实现或验收时，才能作为新的 blocker，并写出影响链。
8. **回修反馈以 blocker 为强制输入**：回修节点必须逐条复核上一轮 blocker；suggestion 可以记录采纳、不采纳或后续处理意图，但不新增账本，不成为隐藏的回修任务。
9. **继续复用既有落盘链路**：评审判断写入现有 `.crctl/tmp/` payload，canonical annotation、review-loop、traceability 和 attempt 仍交由 `crctl review-record` 原子处理。
10. **评审结论不替代状态推进**：状态、路由和下一步仍以既有 `crctl` 与 Pipeline 契约为准。

### 5.2 `review-requirement` 的最小调整方向

需求评审重点前移到“需求是否可以一次实现和验收”：

- 对每个 FR/AC 标出范围、行为、输入、输出、错误和观察点；
- 对 HTTP/API 契约一次检查 endpoint、request、response、错误、幂等、权限和验收断言；
- 对离线、空值、fallback、权限失败、重复请求等会改变验收结论的分支明确判定；
- 影响当前 FR/AC 成立的缺口直接列 blocker，不以“建议补充”延迟；
- 需求外的未来能力、措辞和格式优化仍列 suggestion；
- 回修时逐条复核旧 blocker，并确认新增 AC 是否真正补足行为，而不是只增加编号或表面文字。

### 5.3 `review-tech-design` 的最小调整方向

技术设计评审重点前移到“设计是否在批准范围内且能按真实系统实现”：

- 以已批准 PRD 的范围和排除项作为冻结基线；
- 每条 AC 继续检查设计落点、可观察结果和可达性；
- SDD 引用既有实现时，先维护 `repo`、relative path、稳定 symbol/对象、依赖结论和必要 SHA；
- 涉及共享路径时先列出 callers，逐个决定修改、兼容或排除；
- 在设计新接口前核验真实导出 symbol、函数签名、类型和 loader 责任；
- 不把“发现了相关 caller”直接等同于“当前 CR 应改造该 caller”；
- 发现范围冲突时回到需求边界，不通过 SDD 偷渡新范围。

### 5.4 `review-dev-plan` 的最小调整方向

开发计划评审继续保持 SDD→plan→TASK 的增量评审，不重新裁决已批准 SDD。应前移能够确定的错误：

- SDD 交付物、验证面、风险和回滚安排是否全部进入 plan/TASK；
- 任务依赖是否悬空、有环或顺序错误；
- TASK 引用的函数、事件、SQL、命令、参数、路径和 worktree 是否真实可执行；
- 每个 TASK 是否有明确输入、输出、文件、责任边界和可执行验收步骤；
- 共享文件或 generated 目录是否存在并行冲突；
- 普通估算差异仍是 suggestion，只有暴露任务拆分、依赖或验收结构问题时才是 blocker；
- 若事实反证已批准 SDD，使用现有 `repair-target` 回到技术设计，不在计划评审中偷偷改设计范围。

### 5.5 `review-code` 的最小调整方向

代码评审继续只读取当前变更和正式测试证据，不扩大测试权限：

- 以最终 checkpoint 对应的 diff、TASK、SDD 和 test report 为评审对象；
- 在评审前核对 test report、traceability、测试日志、TASK done 状态和 subject digest 是否属于同一最终变更；
- 缺少可信证据、证据漂移、TASK 未完成或测试状态失败，按现有规则阻断；
- reviewer 不因方便而自行重跑测试，也不采信无法关联当前变更的共享实例输出；
- 环境无法建立时使用既有 `ENVIRONMENT_MISMATCH` 技术中止语义，不把环境问题伪装成代码 blocker；
- 代码质量、需求对齐、安全、测试覆盖和前端质量继续按当前阶段适用维度判断；
- 非阻塞发现进 `suggestions`，不为了提高通过率删除真实风险。

## 6. P1：条件触发的静态检查候选

P1 不属于当前必须实施的改造，只在 P0 落地后由真实失败证据触发。满足以下条件后，后续 CR 才应考虑增加规则：

- 同类错误在真实 CR 中重复出现；
- 规则能够依据仓库、Skill、Pipeline 或 `crctl` 的现有事实确定判断；
- 现有 Skill 契约和检查器无法以更小改动覆盖；
- 检查成本小于继续由 reviewer 人工发现的成本；
- 不需要新增状态、账本、事务框架、通用 Runner 或第二套事实源。

候选规则可以包括：

- SDD 依赖清单中的文件或稳定 symbol 在目标 worktree 中存在；
- Pipeline 的 `repairRef`、`replayNodes` 和引用 Skill 真实存在；
- review Skill 使用的命令和 trigger 能命中既有 capability/state machine；
- 任务验收命令、路径和参数符合已有受控 shell 与 worktree 约束。

不可由确定性规则证明的范围判断、业务设计判断、质量判断和 LLM 评审结论仍留给 reviewer。P1 不建设通用 Runner、YAML patch framework、第二份 review ledger 或新的事务机制。

## 7. 模块职责边界

| 模块 | 应该拥有 | 不应该拥有 |
|---|---|---|
| Agent | 路由、职责判断、选择 Pipeline/Skill | 状态机、Git 算法、受控文件写入 |
| Pipeline | 节点顺序、输入传递、reviewLoop、失败中止 | 复制 Skill 完整算法、手写账本操作 |
| Skill | 业务判断、评审编排、输入输出、失败语义 | 手写原子账本逻辑、重复实现 `crctl` |
| `crctl` | 状态、门禁、CAS、受控账本写入、审计、原子提交 | 业务设计判断、LLM 评审结论 |
| 版本化脚本 | PRD/SDD/TASK/traceability 等确定性转换 | 状态推进、人工审批 |
| README | 面向人的流程总览、权威文件链接 | 另一份可执行细节事实源 |

本次 P0 属于 Skill 的业务判断和编排步骤，不改变其他模块的职责。任何实现提案若需要修改其他模块，必须在后续 CR 中单独证明必要性，并重新经过对应评审。

## 8. 后续 CR 输入约束

后续 tools 优化 CR 可以引用本方案，但注册时必须重新核验：

1. 当前目标 workspace 的 `dir-graph.yaml`、仓库和 worktree authority；
2. `../tools` 当前 `AGENTS.md`、`agent-skill-matrix.yml`、相关 `_index.yml` 和 Pipeline JSON；
3. 四类 review Skill 的当前输入、输出、落盘和失败契约；
4. `crctl review-record`、attempt、CAS、reviewLoop 和 traceability 的当前行为；
5. AIFI-14 案例对应的实际评审记录和处置结果；
6. 相关调用者、symbol、路径、命令和签名是否仍与本方案中的历史事实一致；
7. 事实变化是否影响本方案结论、P0 范围或非目标。

后续 CR 的 PRD 至少应明确：

- 复用本方案的哪些原则和最小改造项；
- 本 CR 的目标 Skill 和不修改的模块；
- 当前批准范围、排除项和范围外发现的处理方式；
- blocker/suggestion 的判定和回修输入；
- 不新增状态、账本、事务框架或第二套事实源的约束；
- 可验证的 Skill 行为变化和回归证据。

本文不能直接替代这些内容，也不能成为绕过后续需求审批的依据。

## 9. 方案审核通过标准

本方案达到以下条件，才适合作为后续 CR 的前置依据：

- AIFI-14 的关键返工根因有事实证据，而不是只写主观判断；
- 已解决的基础设施、AIFI-14 处置结果和本次建议的 tools 优化明确分开；
- “降低后续 CR 返工”被定义为设计目标，而不是 tools 新业务；
- P0 明确聚焦四类现有 review Skill，范围可执行且不过度设计；
- P1 明确为真实证据触发的静态检查候选，而不是隐含的立即建设承诺；
- Agent、Pipeline、Skill、`crctl`、版本化脚本和 README 的职责边界清楚；
- 非目标明确排除 multica、状态机、事务框架、账本、review ledger 和通用 Runner；
- 后续 CR 可以引用本文的原则、范围、非目标和最小改造清单；
- 后续 CR 必须重新核验事实，且事实变化有影响评估入口；
- 方案评审通过不被表述为代码或 tools 已实施，也不替代后续 CR 的独立评审和审批。

## 10. 复盘与效果判断

本方案不新增正式指标能力。后续复盘可以利用现有 `review-annotations`、`review-loop` 和 `traceability.yml`，观察首轮是否更完整、回修后是否出现新的独立 blocker，以及评审轮次是否减少；这些观察不改变 blocker 标准，不写入新的 tools 业务账本，也不作为自动状态门禁。

判断方案是否有效的核心问题是：

> 后续 CR 是否在不扩大范围、不重复建设治理基础设施的前提下，更早发现当前范围内影响实现和验收的独立根因？

如果答案是否定的，应先复盘 P0 的评审输入、范围冻结和事实核验是否执行，再决定是否需要 P1 静态规则；不能先增加轮次、事务或新的治理系统。

## 11. 参考位置

- tools 需求评审 Skill：`../tools/skills/requirement/review-requirement/SKILL.md`
- tools 技术设计评审 Skill：`../tools/skills/develop/review-tech-design/SKILL.md`
- 开发计划评审 Skill：`../tools/skills/develop/review-dev-plan/SKILL.md`
- 代码评审 Skill：`../tools/skills/develop/review-code/SKILL.md`
- tools 行为约束：`../tools/AGENTS.md`
- tools 权限矩阵：`../tools/agent-skill-matrix.yml`
- tools 人读流程总览：`../tools/README.md`
- 当前 workspace 目录图：`dir-graph.yaml`
- AIFI-14 需求评审历史：CR-2026-056 历史 requirement worktree 中的 `change-requests/CR-2026-056/review-annotations/requirement.yml`
- AIFI-14 技术评审历史：CR-2026-056 历史 requirement worktree 中的 `change-requests/CR-2026-056/review-annotations/sdd.yml`
- 现有流程/职责审计：`docs/analysis/done/tools-text-contract-audit.md`
