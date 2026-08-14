# 端到端 Pipeline 最佳实践技能整合方案

> 版本：v2.6（经拷问评审 + 追加决策）｜ 日期：2026-08-08 ｜ 状态：结论已定，CR 交付方式待定
> 文档位置：`AI First Platform/docs/analysis/`（v2.4 起，此前位于 tools 包 `docs/`）
> 适用范围：AI-First 研发协同平台 Phase0 Tools 包
> v1.0 依据：对 `C:\Users\GOBAO\Downloads\AI\skills` 下 10 个开源技能包的完整分析
> v2.0 变更：v1.0 经过一轮逐项拷问评审，约六成内容被事实证伪或推翻，本版为评审后的最终结论
> v2.1 变更：识别出一处真实空白——`review-code`/`write-test-report` 回修循环缺少"先定位根因再动手改"的步骤；`systematic-debugging` 的核心思想并入 `coding-discipline` §3（§4.2 的声明删除结论不变，删的是死声明，不是能力）
> v2.2 变更：对 `writing-plans` / `verification-before-completion` 做全文重读（此前仅读到 description 摘要），发现四处真实价值：TASK 接口契约、TASK 类型一致性自查、占位符判据具体化、评审证据无条件重新验证；同时修正 v2.1 自身的一处粒度错误——`coding-discipline` §2 把 superpowers"Step"（2-5 分钟）误写成了 TASK 粒度，与 `write-dev-tasks` 既有的"1-3 天"TASK 定义矛盾
> v2.3 变更：明确并统一并入方式——全部内化条目均为**直接改写本包 SKILL.md 正文**（用本包语汇重述规则），不是"声明调用外部技能"；技能名仅作来源标注或可选加速器出现，不作为执行前提。本次把 §4.3 已用于 `systematic-debugging` 的甲路线加速器条款，同样补齐到 §4.6（`writing-plans`）与 §4.7（`verification-before-completion`）
> v2.4 变更：新增第 6 条内化项——**TASK 依赖排序**（§4.8）。全文重读 `dispatching-parallel-agents` 后发现：`depends-on` 字段已声明、已汇总进 `tasks/_index.yml`、已被 `validate-doc` 校验指向有效，但**没有任何消费方用它决定执行顺序**；并发执行作为其甲路线加速器（不影响产出，只影响耗时）
> v2.5 变更：按"声明了一半的机制没闭环"这一判据对全包做专项自查，新增 §4.9 **存量缺口收口**四条（`capabilities` 错误声明、`forbidden` 性质误导、`suggestions` 只写不读、`assignee` 死字段）。**来源与前六条不同**：前六条来自外部技能对照，这四条来自本包自查，与 superpowers 生态无关。自查同时确认六个面健康（pipeline inputs 零死参数、gates.json 七键全消费、55 个 active skill 无孤儿、`slug`/`estimate` 闭环完整、`reviewLoop.repairNodeId` 等由平台运行时消费不算缺陷）
> v2.6 变更：§4.9-③ 的评审期分流改由**触发参数 `suggestion_policy` 控制**（`type: select`，`options: [strict, lenient]`，`required: false` + `default: "strict"`——严格对齐包内三个既有 `select` input 的形态；UI 预选中 `strict`，启动人直接确认或改选）。分流本身仍由评审 LLM 执行（skill 节点无法中途插人工暂停，逐条人选需多烧一轮 `maxAttempts`），但"要不要在本 CR 顺手清技术债"这个交付节奏决策交还给启动流水线的人；形态与 `review_llm` 的"一次选择全程复用"同构，零新增节点

---

## 目录

1. [背景与目标](#1-背景与目标)
2. [术语澄清（v1.0 的关键概念混淆）](#2-术语澄清v10-的关键概念混淆)
3. [决策总览](#3-决策总览)
4. [最终设计](#4-最终设计)
5. [明确排除项及理由](#5-明确排除项及理由)
6. [配置修改清单汇总](#6-配置修改清单汇总)
7. [待定事项](#7-待定事项)
8. [附录：技能包详解卡片](#8-附录技能包详解卡片)

---

## 1. 背景与目标

社区涌现出大量 Agent Skills 生态项目（superpowers、mattpocock skills、ponytail、taste-skill 等），覆盖需求、设计、计划、开发、审查全研发链路。本工具包（Phase0 Tools）已具备完整的编排层（pipeline + crctl 状态机 + agent-skill-matrix 治理 + engineering-docs 文档体系）。v1.0 提出以 external 身份注入外部方法论；经拷问评审，多数注入点被证明与本包既有机制冲突、重复、或建立在错误事实上。v2.0 是评审后的最终方案。

**核心结论没有变**：外部技能只填补方法论空缺，不新增 owns、不改状态机、不破坏单一事实源。**变的是"哪些空缺是真的"**。

---

## 2. 术语澄清（v1.0 的关键概念混淆）

v1.0 最大的事实错误：把两个不同领域的 "SDD" 缩写当成了同一个东西。

| 缩写 | 本包语境 | superpowers 语境 |
|---|---|---|
| SDD | **技术设计文档**（`sdd.md`，有 JSON Schema、模板、校验器、`tech-design-review-pending` 门禁） | **S**ubagent-**D**riven **D**evelopment（一种子代理执行模式，`subagent-driven-development` 技能） |

v1.0 §3「写 SDD」给 superpowers ⭐⭐⭐ 评级，实为缩写撞车——superpowers 的 14 个技能（brainstorming / dispatching-parallel-agents / executing-plans / finishing-a-development-branch / receiving-code-review / requesting-code-review / subagent-driven-development / systematic-debugging / test-driven-development / using-git-worktrees / using-superpowers / verification-before-completion / writing-plans / writing-skills）**没有任何一个产出设计文档**。

其次，**本工具包是文档驱动（SDD: 技术设计文档驱动），不是测试驱动（TDD）**。主链：`PRD → sdd.md → plan.md → TASK → 代码 → test-report.md → review`。测试报告在代码**之后**（`code-implementation.pipeline.json` 节点 6 `implement-code` → 节点 7 `write-test-report`），测试的角色是证明 TASK 验收条件，不是驱动实现。v1.0 引入 TDD 铁律与本包既有节点顺序自相矛盾（详见 §4.3）。

其三，v1.0 引用的 `grill-me` / `grill-with-docs` **在当前会话可用技能清单里不存在**——mattpocock 那套装进来的技能名是单一的 `grilling`。

---

## 3. 决策总览

| # | 议题 | v1.0 方案 | v2.0 结论 |
|---|---|---|---|
| 1 | 需求拷问落点 | requirement-authoring 插入拷问节点 | **不插节点**。拷问发生在 `/requirement` 调用之前，硬化结论作为 `summary` 输入；`write-requirement-prd` 优先采纳其中已确认边界 |
| 2 | external 声明策略 | 预先登记 8+8 个 external | **用时才登记**：仅当某处 prompt/SKILL.md 真实引用时，同批提交才登记 |
| 3 | superpowers 8 个声明 | 全部保留并补装 | **删 4 个死声明的 external 声明**（using-superpowers / writing-plans / systematic-debugging / verification-before-completion，零引用点）；其中 **systematic-debugging 的根因排查思想内化进 `coding-discipline` §3**（见 §4.3），声明照删、能力不丢；`executing-plans` / `subagent-driven-development` 保留并补齐降级路径 |
| 4 | TDD 铁律 | 内化为开发纪律 | **不采用**。与本包 SDD 驱动主链矛盾，且不可验证（CR worktree 提交历史被 crctl 收敛，无法核实"测试先于实现"）。既有证据链（TASK 验收条件→验证→test-report→review 维度→门禁）已覆盖"必须有测试" |
| 5 | ponytail / bite-size 拆解 / 根因排查 | 声明 external，运行时缺失即静默失效 | **内化**为本包自有 skill `coding-discipline`（§1 极简阶梯 + §2 拆解粒度 + §3 根因排查），作为兜底事实源；已安装的同名 external 技能作可选加速器，不作前置条件 |
| 6 | 代码评审前自检/响应纪律（superpowers requesting/receiving-code-review） | 引入 | **不引入**：本包 reviewLoop 的 `repair-instructions` + `fixed-blockers` 账本机制已覆盖同一诉求，且比社交纪律更强（有留痕） |
| 7 | open-code-review（ocr）确定性预检 | Phase 3 引入 | **不引入**：①与 CR-2026-023 刚建立的「评审 LLM 人工选定 + reviewer-model 留痕」直接冲突；② findings 写入的 `evidence` 段在 `crctl.mjs` 序列化逻辑中不存在，会被静默丢弃；③ 需扩 `controlled-shell/rules.json`（git 专用白名单）三个消费方的 schema；④ review-code Step 1 的 `merge-base` 确定性取证已解决 ocr 要解决的问题 |
| 8 | 前端专项（taste-skill） | 全套规范注入 + 两个 external | **收窄为可验证项**：review-code 第五维度只收 a11y 对比度（破 AA 升 blocker）、组件状态完整性、构建体积；字体/配色/拨盘基线等审美主张留给已安装的可选 external `design-taste-frontend`，不内化 |
| 9 | Phase 划分 | 4 个阶段渐进上线 | **合并为两批**：批次一收口（纯删除，零新增行为）；批次二内化（`coding-discipline` + 第五维度 + 拷问措辞 + `AGENTS.md` 修订） |
| 10 | TASK 粒度定义 | 未涉及 | `coding-discipline` §2 原写"TASK 为 2-5 分钟粒度"，与 `write-dev-tasks` 既有"1-3 天"TASK 定义矛盾——**已修正**：2-5 分钟是 TASK 内部的 Step 切分，不是 TASK 本身粒度（§4.3） |
| 11 | writing-plans 的接口契约/类型一致性/占位符判据 | 未识别（v1.0/v2.0 只读了 description） | **内化**：TASK 接口契约（消费/产出精确签名）+ 类型一致性自查 并入 `write-dev-tasks`；占位符判据具体化替换现有一句话（§4.6） |
| 12 | verification-before-completion | 归入死声明直接删除 | **部分内化**：核心洞察"不信自报，必须独立重验"揭示 `review-code` Step 1 的真实证据链漏洞（现状是"缺失才补跑"，即自报即采信）——**改为无条件重新执行验证命令**；回归测试红绿验证并入 `coding-discipline` §3（§4.7） |
| 13 | dispatching-parallel-agents / TASK 依赖排序 | 未识别 | **内化**（第 6 条内化项）：`depends-on` 已声明、已汇总、已校验指向有效，但无消费方用它排序——`implement-code` Step 3 追加拓扑排序规则；同层无依赖 TASK 的并发执行作为甲路线加速器（§4.8） |
| 14 | `capabilities` 声明与事实相反 | 未识别（自查发现） | **订正数据**：`knowledge-agent` 的 `tech-note-write`/`insight-write`、`customer-support-agent` 的 `unresolved-feedback-record` 从 `supported` 挪进 `pending`；`known-gaps` 前两条随之删除（§4.9-①） |
| 15 | `forbidden` 性质误导 | 未识别（自查发现） | **文档写明性质**：声明性边界，执行靠 agent 自觉 + `protectedPaths` 文件守卫，**不存在调用级拦截**；不加运行时钩子（§4.9-②） |
| 16 | `suggestions` 只写不读 | 未识别（自查发现） | **评审期分流（策略可控）+ 想法池承接**：新增 input `suggestion_policy`（`select`，`required:false` + `default:"strict"`，UI 预选中）；`strict`=不升格，`lenient`=按三条判据把本 CR 该修的升格进 `blockers`（走既有 reviewLoop 在本 CR 解决）。剩余 `suggestions` 经 `record-idea` 落 `docs/ideas/`，不阻塞本 CR（§4.9-③） |
| 17 | `assignee` 死字段 | 未识别（自查发现） | **删字段**：全仓仅 1 处出现（模板自身），零读取方，连 `tasks/_index.yml` 汇总都不含它；数据模型是"一 CR 一开发负责人"，该字段为不存在的多人模型而设（§4.9-④） |

---

## 4. 最终设计

### 4.1 需求拷问不入流水线

本包流水线只有三种节点：`skill`（单发式，prompt 进→`node-N.md` 出）、`human_approval`、`code_generation`。拷问的价值在于人的多轮回答，塞进单发式 `skill` 节点只会退化为 agent 自问自答——恰是拷问要防的"agent 编造需求"失效模式。

**落地方式**：拷问发生在调用 `/requirement` 之前，由用户在会话中与 grilling 技能完成；硬化后的结论直接构成 `requirement-authoring.pipeline.json` 的 `summary` 输入（已是 `required: true` 字段）。`skills/requirement/write-requirement-prd/SKILL.md` 追加一行：若 `summary` 携带已确认的边界与排除项，优先采纳，不再重新询问。

零流水线改动，零节点重编号。

### 4.2 external 声明：用时才登记

`agent-skill-matrix.yml` 的 `external:` 字段只被 `check-skill-matrix.mjs` 用作"豁免 owns 唯一性检查"，从未校验外部技能是否存在、是否被引用。证据：`systematic-debugging` 声明多个 CR 周期，零引用点，CI 从未报警。顶层 `external-skills:` 块因缩进不匹配检查器正则，**从未被解析**，是纯文档。

**规则**：不预先声明。某个 external 技能被某处 prompt/SKILL.md 真实引用时，同批提交才在对应 actor 的 `external:` 下登记。

**存量清理**（本次一并做）：
- 删除 4 个零引用死声明：`using-superpowers`、`writing-plans`、`systematic-debugging`、`verification-before-completion`
- 保留 `executing-plans`、`subagent-driven-development`（`implement-code` 有真实引用），补充降级路径（见 4.3）
- `brainstorming` 不动——它是本包唯一四件套齐全的样板（声明 + 引用点 + 显式降级 + 错误处理，见 `skills/competitive/report-to-planning-suggestion/SKILL.md`）

> 后续治理项（本次不做，超出范围）：给 `check-skill-matrix.mjs` 补一条检查——`external:` 声明必须有 ≥1 处真实引用，避免死声明再次沉积。留作独立的漂移治理提案。

### 4.3 开发纪律内化：`coding-discipline` skill

**问题根源**：`implement-code/SKILL.md` 当前写「必须遵循目标运行时已安装的 external `test-driven-development`」，但该技能未安装，规则静默蒸发，而下游 `test-report.status=pass` 门禁照常要求证据——纪律与门禁脱钩的悬空引用。

**修法**：新建 `skills/develop/coding-discipline/SKILL.md`，内容为本包自有的、可被 lint-prompts 覆盖的规则（而非指向外部技能名）：

- **§1 极简阶梯**（源自 ponytail，已改写为本包语汇）：需要存在吗（YAGNI）→ 代码库已有 → 标准库 → 平台原生 → 已装依赖 → 一行 → 最小可用实现。信任边界校验、错误处理、安全、可访问性不在精简范围内。
- **§2 执行步骤粒度**（源自 superpowers writing-plans，v2.2 修正措辞）：`implement-code` 执行单个 TASK 时，内部步骤按 2-5 分钟粒度切分（写验证用例→跑到失败/明确当前状态→实现→复验→提交），每步含精确文件路径与验证步骤，禁止 TBD/占位符。**注意**：TASK 本身的粒度（1-3 天、一个模块/一类接口）由 `write-dev-tasks/SKILL.md` 定义，不受本节约束——v2.1 曾误把 Step 粒度写成 TASK 粒度，已在 v2.2 更正（§3 决策总览 #10）。
- **§3 根因排查 + 回归验证**（源自 superpowers systematic-debugging + verification-before-completion，v2.2 补充）：进入自修复模式时（`review_feedback` 存在），动手改代码前先定位失败根因——是哪个 TASK、哪一行、因为什么假设不成立导致 blocker；同一根因下的所有失败点一次修完，不逐条症状打补丁。节点输出必须包含 `root-cause` 字段（与既有 `fixed-blockers` 并列），说明本轮修复对应的根因而非仅列出改了哪些症状。**若本轮修复针对的是一个 bug（而非纯新功能缺口）**，对应的回归测试必须先验证"红"再验证"绿"：临时还原修复前代码跑一次该测试确认它会失败（证明测试真的在测这个 bug，不是一个自始至终都通过的假测试），再恢复修复跑一次确认通过，两次结果都写入节点输出。

**为什么加 §3**：`review-code`/`write-test-report` 的回修循环今天只要求「逐条消费 blockers、只修被指出的问题」，没有强制先查根因这一步——`maxAttempts` 耗尽前完全可能把同一根因当成多个不同症状反复打补丁，直到额度用完才转人工。`systematic-debugging` 的"先根因、后动手"铁律正好补这个洞，且与 §1/§2 同一批消费方（`dev-agent`/`implement-code`），并入同一 skill 不新增登记面。

**不含 TDD**：与本包 SDD 驱动主链矛盾，且不可验证（见 §2 术语澄清）。两处悬空引用直接删除：
- `skills/develop/implement-code/SKILL.md` 第 75 行
- `pipeline-templates/code-implementation.pipeline.json` 节点 6（`implement-code`）prompt 中的同义表述

**不含评审前自检/响应纪律**：`implement-code/SKILL.md` 已规定自修复模式下「逐条消费 blockers、只修被指出的问题、避免无关重构」，reviewLoop 账本（`repair-instructions` / `fixed-blockers`）已提供留痕，比 superpowers 的社交纪律更强，不重复引入。

**归属**：`skills/_index.yml` 登记为 active；`agent-skill-matrix.yml` 下 `dev-agent` owns，`quality-reviewer-agent` can-call；`AGENT-SKILL-MATRIX.md` 表格同步；`dir-graph.yaml` 登记路径。

**消费方**：
- `implement-code` Step 3 引用 §1 + §2；自修复分支额外引用 §3
- `write-dev-plan` 引用 §2

**已安装 external 技能的定位（甲路线）**：若目标运行时已装 `ponytail` / `subagent-driven-development` / `executing-plans` / `systematic-debugging` / `writing-plans` 等完整版技能，视为**可选加速器**，SKILL.md 措辞为「已装完整技能则优先走其完整流程，未装则按本节规则执行」。例如 §3 可补一句：「目标运行时已装 external `systematic-debugging` 时优先走其完整排查流程，未装时按本节规则执行，二者均需在节点输出留 `root-cause` 字段」；§2 可补一句：「已装 external `writing-plans` 时可直接用其 Step 结构落盘，未装时按本节 2-5 分钟粒度自行切分，二者产出等价」。`coding-discipline` 是兜底事实源，不依赖任何跨运行时探测机制（本包目前没有，且 4 个 adapter 形态各异，为此新增探测基础设施成本远高于内化 30 行文本）。

**`executing-plans` / `subagent-driven-development` 降级路径补齐**（比照 `brainstorming` 写法）：
```
目标运行时未提供 subagent-driven-development 时，按 TASK 顺序串行实现（等价于降级到
executing-plans 语义），在节点输出注明降级；两者均未提供时，按 coding-discipline
§2 的粒度自行拆解执行，无需额外声明。
```

### 4.4 代码评审第五维度（仅可验证项）

`review-code/SKILL.md` Step 3 评审维度表追加第五维度，`dimensions` 字段本就是自由映射（`crctl.mjs` 仅校验非空），加键零结构成本：

| 维度 | 检查项 | 触发条件 |
|------|-------|---------|
| ⑤ 前端质量（仅前端 diff 触发） | a11y 对比度是否达 WCAG AA；组件 loading/empty/error 状态是否完整覆盖；构建体积是否在预算内 | diff 命中 `*.tsx`/`*.vue`/`*.css`/`*.html` |

判据：破坏 WCAG AA 对比度升级为 `blocker`，其余为 `minor`。

**不含**：字体/配色规范、强调色数量限制、拨盘基线值、动效动机等审美主张——这些不可机械验证，属于一家工作室的品味主张，强加进通用工具包会对所有目标项目的既有设计系统造成侵入。需要时用已安装的可选 external `design-taste-frontend` 作补充参考，不内化、不进 `coding-discipline`、不进矩阵。

**不引入 ocr**：确定性预检的价值（避免无边界翻仓库）已被 `review-code` Step 1 的 `merge-base` 定界取证覆盖；引入会与 CR-2026-023 刚建立的评审 LLM 人工选定机制冲突，且其 findings 载体（`evidence` 段）在 crctl 序列化逻辑中不存在。

**不引入 `redesign-existing-projects`**：纯投机需求，目标 workspace 是否有前端历史包袱未知，YAGNI。

### 4.5 `AGENTS.md` 修订

第 56 条「外部 superpowers 能力由目标运行时提供，phase0 tools 不复制同名 SKILL.md，只在需要处声明依赖」，改为反映 4.3 的甲路线：本包自有规则（`coding-discipline`）为兜底事实源，外部同名技能为可选加速器，二者不冲突、不要求探测。

第 160 条「禁止把外部方法论 Skill 打包进 phase0 tools」保持不变——`coding-discipline` 不是复制上游 SKILL.md，是本包语汇重写的自有规则，未违反该条。

### 4.6 TASK 契约强化（write-dev-tasks，v2.2 新增）

**问题根源**：`write-dev-tasks/SKILL.md` 的 TASK 正文只有"涉及文件/模块"，没有跨 TASK 接口声明。而 `implement-code` 是逐 TASK 独立实现（可能子 agent 隔离，"实现者只看得到自己那个 TASK"），容易出现命名/签名断裂——如 TASK-03 定义 `clearLayers()`，TASK-07 却按 `clearFullLayers()` 使用。

**修法**：

- TASK 正文追加「接口契约」小节：**消费**（本 TASK 使用哪些上游 TASK 产出的精确函数名/参数/返回类型）、**产出**（本 TASK 暴露给下游 TASK 的精确签名）。
- `write-dev-tasks` Step 4（生成 TASK 索引后）追加一步：核对所有 TASK 声明的接口签名是否一致，命名对不上时输出 WARN 并列出差异（比照现有"估算交叉校验"的写法：不静默覆盖，由计划负责人决定）。
- 「注意事项」的"不得模糊描述"替换为具体判据清单（源自 writing-plans No Placeholders）：禁止 TBD/"待定"；禁止"加适当的错误处理"这类无实际内容的描述；禁止"同 TASK-03"这类引用而不给出实际代码/签名；禁止引用未在任何 TASK 中定义的类型或函数。

**已安装 external 技能的定位（甲路线）**：以上三条是 `write-dev-tasks` 自有规则，不依赖任何外部技能。若目标运行时已装 `writing-plans` 完整版，可直接引用其 Task Structure 模板作为 TASK 落盘格式的参考细化（如接口契约段落的具体排版）；未装时本节规则本身已是完整可执行的格式定义，两者不冲突、不要求探测。

### 4.7 评审证据无条件重新验证（review-code，v2.2 新增）

**问题根源**（本轮最大发现）：`skills/develop/review-code/SKILL.md:46` 现状是「读取 implement-code 节点输出中的验证命令与结果；**若缺失**，必须重新运行或要求补齐」——即只要 `implement-code` 自报了验证结果，评审就采信，不要求独立重跑。这与 TDD 证据链悬空（§4.3 起因）、回修循环缺根因排查（§4.3 §3）是同一类问题：证据链里有一环允许"自己说了算"。

**修法**：`review-code` Step 1 改为**无条件重新执行**验证命令（lint/test/build），不再是"缺失才补跑"；implement-code 节点的自报结果仅作参考对照，两者不一致时以本轮重新执行的结果为准并在 blockers 中注明差异。评审判据细化（源自 verification-before-completion 的 Common Failures 表）：「测试通过」必须是本轮评审重新执行的完整命令输出（0 failures），"看起来通过"或"之前跑过"不构成证据。

**已安装 external 技能的定位（甲路线）**："无条件重新执行"是 `review-code` 自身的最低要求，不因是否安装外部技能而增减——这条不能弱化为"可选加速"，否则又回到本节要修的漏洞（自报即采信）。若目标运行时已装 `verification-before-completion` 完整版，可用其 Gate Function 五步流程与 Common Failures 表作为执行细则的补充参考；未装时按本节最低要求（重新执行、读完整输出、核对 exit code）独立执行，达到同一证据强度。

### 4.8 TASK 依赖排序（implement-code，v2.4 新增 · 第 6 条内化项）

**问题根源**：`depends-on` 字段处于"声明齐全但无人消费"的状态——

| 环节 | 现状 | 位置 |
|---|---|---|
| 声明要求 | 「跨模块依赖必须通过 `depends-on` 字段声明」 | `write-dev-tasks/SKILL.md:41` |
| 写入 TASK | `depends-on: []` 在 frontmatter | `write-dev-tasks/SKILL.md:58` |
| 汇总索引 | 汇总进 `tasks/_index.yml` | `write-dev-tasks/SKILL.md:75` |
| 引用校验 | 校验 depends-on 指向的目标文件存在 | `validate-doc/SKILL.md:15` |
| **执行排序** | **无任何消费方** | — |

`implement-code` Step 3 只说"按 TASK 实现代码"，没有排序规则；`crctl task done`（账本唯一写入通道）也不校验前置 TASK 是否已 done。依赖关系被完整声明、被校验指向有效，却在真正执行时被忽略——TASK 可能按索引顺序（TASK-01/02/03…）实现，而非按依赖顺序。这与 §4.6 的接口契约是同一个失效面的两半：契约管"签名对不对得上"，排序管"上游做完了没有"。

**修法**：`implement-code` Step 3 追加排序规则——执行前读取 `tasks/_index.yml` 的 `depends-on` 做拓扑排序，按依赖顺序实现；`depends-on` 指向的前置 TASK 在 `_index.yml` 中未标记 `done` 时，不得开始本 TASK，并在节点输出注明被阻塞的 TASK 与其等待的前置项。

**已安装 external 技能的定位（甲路线）**：拓扑排序本身是 `implement-code` 自有规则，不依赖任何外部技能——未装时按拓扑序**串行**执行即可，完全正确。若目标运行时已装 `dispatching-parallel-agents`，可用其"独立域分组 + 同一响应内多次派发 = 并发执行"模式，把同一拓扑层级上互不依赖的 TASK 并发实现，并按其 Verification 段落要求在子代理返回后核对改动是否冲突、重跑全量验证。**并发只影响耗时，不影响产出**——两条路径的 TASK 完成集合与 `crctl task done` 记账完全等价，这正是甲路线"可选加速器"的标准形态。

**并发的边界**（源自 dispatching-parallel-agents 的 When NOT to Use，结合本包 CR workspace contract）：同一 repo worktree 内会修改同一文件的多个 TASK 不构成独立域，必须串行；跨 repo 的 TASK 因 worktree 天然隔离，可安全并发。回修模式下（`review_feedback` 存在）默认串行——多个 blocker 常同源，§4.3 §3 要求先定位根因，并发反而会让同一根因被并行打多份补丁。

### 4.9 存量缺口收口（自查发现，v2.5 新增）

**与前六条的来源差异**：§4.1–§4.8 来自外部技能对照，本节四条来自对本包的专项自查——判据是同一条（"声明了一半的机制没闭环"），但与 superpowers 生态无关，即使不做任何外部整合也应处理。

自查同时确认**六个面健康**，一并记录避免后续重复排查：pipeline inputs 零死参数（8 个模板全覆盖）、`gates.json` 七个键全部有消费方、55 个 active skill 无孤儿、`slug` 与 `estimate` 闭环完整（前者 write→read→有 fallback，后者有 FR-23 交叉校验）、`reviewLoop.repairNodeId`/`feedbackInput` 等 crctl 零引用但**消费方是平台运行时（本包之外），不算缺陷**。

#### ① `capabilities` 声明与事实相反

**现状**：`agents/_index.yml` 的 `capabilities.supported` 宣称 `knowledge-agent` 能 `tech-note-write`/`insight-write`，`customer-support-agent` 能 `unresolved-feedback-record`——而 `agent-skill-matrix.yml` 的 `known-gaps` **同时承认这三个没有对应 Skill**（`knowledge-agent` 的 `owns` 更是空数组 `[]`）。同一个包里，A 文件宣称 supported，B 文件用散文记录"其实没实现"。而 `pending`——专为此设计的字段——**9 个 agent 全是 `[]`**。

**影响**：本包的工作方式就是"AI 读文件自己判断"（`CLAUDE.md` 规定读 AGENTS.md → dir-graph → README → 任务文件），所以错误声明会直接变成错误路由。

**修法（Level A，本次做）**：三项从 `supported` 挪进 `pending`；`known-gaps` 前两条删除（`pending` 已表达同一事实，第三条 `writeback-agent-entry` 与 capabilities 无关，保留）。

**明确不做（Level C，另立项）**：`capabilities` 仍无消费方、无校验、全仓零文档，且命名体系混着三种风格（抽象能力名 `usage-guidance` / skill 别名 `PRD-write` / 确切 skill 名 `planning-draft`），**无命名规则就无法写校验**。真闭环需把 `supported` 改成 `capability → 实现 skill[]` 映射 + `check-agents-contract.mjs` 加第 5 条不变式，约 40 个条目要填，且填的过程会牵出新的 pending 项。工作量自成一个 CR，不搭车。

#### ② `forbidden` 性质误导

**现状**：`check-agents-contract` 的白名单校验**只作用于 `agents/_index.yml` 的 `references[]`**（不变式 3），不检查 SKILL.md 正文让 agent 调用了什么，也不检查运行时实际调用。`pretooluse-guard.mjs` 只管文件路径（`protectedPaths`），不管技能调用。而 `forbidden` 的自述用途是「明确禁止调用，避免跨域越权」——**"调用"是运行时行为，而运行时这一层没有任何东西在看**。

**影响**：白名单管的是"静态声明面"，`forbidden` 想管的是"运行时调用面"，两者不是同一个面。它读起来像一道闸，实际指向一个无人看守的地方。缓解因素：最危险的越权（写受控账本）已被 `protectedPaths` 的 deny 面挡住。

**修法（本次做）**：在 `AGENT-SKILL-MATRIX.md` 与 `openwiki/architecture/agent-skill-matrix.md` 写明其性质——**声明性边界，执行靠 agent 自觉 + 文件路径守卫，不存在调用级拦截**。不加运行时钩子（成本远高于收益，且 `protectedPaths` 已覆盖高危面）。

#### ③ `suggestions` 只写不读

**现状**：三个 review skill 都声明该字段，crctl 落盘进 `review-annotations/{stage}.yml`，但回修链只读 `blockers`/`repair-instructions`；`approve-code/SKILL.md` 全文零次提及（审批人看不到）；`writeback-*` 零消费。`review-code/SKILL.md` Step 6 输出模板也没有它——**与节点 9 prompt 要求的「输出…验证证据与建议」不一致**（既有漂移，一并修）。

**关键推理——为什么消费点必须在评审期而不是审批期**：§4.7 刚刚确立"证据必须来自本轮重新执行"。而 `verdict=pass` 是针对**当时那份代码**的；审批期若改代码，评审证据描述的对象已不存在。所以**任何"本 CR 内消费"的路径，最后都必须回到重新评审**——而"改完重审"正是 `reviewLoop` + `replayNodes` 做的事。这条推理排除了所有"审批期顺手改"的方案。

**修法（本次做）**：分流点前移到评审期，分流强度由**触发参数**控制。

```
review-code 发现一个非阻塞问题
├─ suggestion_policy=lenient 且满足三条升格判据
│     → 写进 blockers → verdict=block
│     → reviewLoop 自动 replayNodes 回 implement-code 修 → 重审 ✅ 本 CR 内解决
└─ 其余（含 strict 模式下的全部非阻塞发现）
      → 写进 suggestions → record-idea 落 docs/ideas/，不阻塞本 CR
```

语义随之校准：`blockers` = **本 CR 内要处理的**（不论轻重）；`suggestions` = **本 CR 内不处理的**。**零新增机制**，完全复用既有 reviewLoop。

**为什么分流由评审 LLM 执行而非人工逐条选**：`review-code` 是单个 skill 节点，内部一气呵成——写 `.crctl/tmp/review-code.yml` → `crctl review-record` 原子完成三件不可逆的事（CAS 写 canonical、`--bump-attempt` 记账、删除临时 payload，见 `crctl.mjs:1423-1429`）。skill 节点中途没有可插人工暂停的钩子；等人能看见 `node-9.md` 时一切已落盘。逐条人选需要改回 canonical + 再 bump 一次 attempt，**为一个决策烧掉一轮宝贵的 `maxAttempts=3`**，不划算。

**控制权交给触发参数（本次新增）**：`code-implementation.pipeline.json` 新增 input：

```json
{
  "key": "suggestion_policy",
  "label": "改进建议处置策略",
  "type": "select",
  "required": false,
  "options": ["strict", "lenient"],
  "default": "strict",
  "description": "strict=不升格，所有非阻塞改进建议一律进 suggestions，评审只判 CR 本身的 pass/block（保守交付，默认）；lenient=按三条判据把本 CR 内该修的升格进 blockers，走 reviewLoop 在本 CR 内解决（清技术债场景）"
}
```

**形态严格对齐包内先例**：现有三个 `select` 型 input（`focus_dimension` / `insight_type` / `new_owner_role`）全部是 `required: false` + `default` 的组合；而全仓 `required: true` 与 `default` **并存零先例**。本参数沿用前者——UI 预选中 `strict`，启动人直接确认即可，想清技术债时改选 `lenient`。

**默认 `strict`（不升格）**——保守交付优先：默认状态下评审只判 CR 本身的 pass/block，不因改进建议触发额外回修轮次。这与 `review_llm` 的"一次选择全程复用"同构（`b35c7b2` 的设计），零新增节点、不动节点编号、不碰 `replayNodes`。

**取舍需明示**：默认 `strict` 意味着"本 CR 内解决改进项"这条路**默认关闭、按 CR 显式开启**——交付节奏的决定权归启动流水线的人，评审 LLM 只在既定策略内执行机械判断。代价是启动人若未留意该项，改进建议会静默流向想法池而不在本 CR 处理；`description` 已写明两种模式的适用场景以降低误选。

**升格判据（仅 `lenient` 生效，三条同时满足才进 blockers）**：① 改动不超出本 CR 已触碰的文件（不扩大 diff）；② 有明确的"改成什么"（能写进 `repair-instructions`，不是"优化一下"）；③ 不需要产品/架构决策（纯实现层）。任一不满足 → `suggestions`。

**成批升格（仅 `lenient` 生效）**：`maxAttempts=3` 是硬上限，同一轮的多条升格项必须写进**同一批 blockers**，不得一轮一条——与 §4.3 §3「同一根因下的所有失败点一次修完」同一条纪律。

**落点为何是 `docs/ideas/` 而非 `delivery/`**：① `delivery/` 是交付归档区，写进去仍没人主动翻，只是换个目录继续"只写不读"；`docs/ideas/` 是想法池入口，有完整下游通路（ideas → 被认领 → requirement pipeline 注册 CR）。② 写 `docs/ideas/` 必须在 approve-code 期做（CR worktree 内，随分支合并进 trunk）——`feature-writeback` 的硬边界是「只写 `specs/` 与 `delivery/` 内容文件」，`docs/ideas/` 不在允许范围。

**转想法池不设默认**：经评审期分流后，剩余 `suggestions` 已是"明确不做"的过滤结果，由审批人判断是否值得进入下轮规划；不转则仅留档 `review-annotations`，无损失。

**副作用需在同一改动中说清**：`blockers` 语义扩大后（仅 `lenient` 模式实际发生），`review-code` 输出的 `Critical/Major` 计数口径改变，该模式下的历史 CR 数据不可与 `strict` 模式直接比较；评审输出需注明本轮所用 policy。

**本次只做 code 阶段**：`requirement`/`tech-design` 两阶段机制完全同构，但那两阶段的 suggestions 更可能在当轮就被吸收进 PRD/SDD 迭代（文档本就在改），优先级低，同理可扩。

#### ④ `assignee` 死字段

**现状**：`assignee: ""` 全仓**只出现 1 次**（`write-dev-tasks/SKILL.md:59` 模板自身），写进每个 TASK 的 frontmatter，零读取方——连 Step 4 的 `tasks/_index.yml` 汇总都不含它。比 `depends-on` 更彻底：后者至少被 `validate-doc` 校验过指向有效。

**为什么它是死的**：数据模型是"一个 CR 一个开发负责人"（`cr.md` 只有一个 `owners.development.id`），每个 TASK 的执行人恒等于那个人。它是为"一 CR 多人"设计的字段，而那个模型今天不存在。§4.8 的并发执行虽逼近该场景，但 `crctl task done` 已往 `.crctl/audit.log` 逐条记账（带时间戳），需求已被覆盖。

**修法（本次做）**：删字段。真要多人协作时，`cr.md` 需先支持多开发负责人，不是加个字段就够。

---

## 5. 明确排除项及理由

| 事项 | 排除理由 |
|---|---|
| OpenSpec 文档体系 | 与 engineering-docs 同构且更弱；引入形成双文档体系 |
| ECC 全家桶 | 与 pipeline 编排重复；281 技能无法通过 owns 唯一性治理 |
| TDD 铁律（superpowers / mattpocock） | 与本包 SDD 驱动主链矛盾；不可验证；既有证据链已覆盖诉求（§2、§4.3） |
| superpowers requesting/receiving-code-review | 与既有 reviewLoop 账本机制重复，且后者更强 |
| open-code-review（ocr） | 与 CR-2026-023 评审模型留痕冲突；findings 载体不存在；重复 review-code 已有确定性取证（§4.4） |
| taste-skill 审美规范（字体/配色/拨盘） | 不可验证，侵入目标项目既有设计系统 |
| `redesign-existing-projects` | 纯投机需求，目标仓前端现状未知 |
| CopilotKit | 仅当产品做 agent-native UI 才需要 |
| i-have-adhd | "无开场白/无总结"规则会破坏 engineering-docs 结构化章节 |
| 图像生成类技能 | 产物不可验证，与 reviewLoop 证据机制冲突 |
| 4 个死声明的 superpowers 技能 | 零引用点，多 CR 周期未被使用（§4.2） |

---

## 6. 配置修改清单汇总

**批次一 · 收口（纯删除与对齐，零新增行为）**

| 文件 | 修改内容 |
|---|---|
| `agent-skill-matrix.yml` | 删 4 个死声明 external |
| `skills/develop/implement-code/SKILL.md` | 删第 75 行 TDD 悬空引用；`executing-plans`/`subagent-driven-development` 补降级路径 |
| `pipeline-templates/code-implementation.pipeline.json` | 节点 6 prompt 同步删除 TDD 表述、补降级路径表述 |
| `agents/_index.yml` | `tech-note-write`/`insight-write`/`unresolved-feedback-record` 从 `supported` 挪进 `pending`（§4.9-①） |
| `agent-skill-matrix.yml` | `known-gaps` 前两条删除（`pending` 已表达；第三条 `writeback-agent-entry` 保留）（§4.9-①） |
| `AGENT-SKILL-MATRIX.md` / `openwiki/architecture/agent-skill-matrix.md` | 写明 `forbidden` 为声明性边界、无调用级拦截（§4.9-②） |
| `skills/develop/write-dev-tasks/SKILL.md` | 删 TASK frontmatter 的 `assignee` 字段（§4.9-④） |

**批次二 · 内化（真实行为变更）**

| 文件 | 修改内容 |
|---|---|
| `skills/develop/coding-discipline/SKILL.md`（新建） | §1 极简阶梯 + §2 拆解粒度 + §3 根因排查 |
| `skills/_index.yml` | 登记 `coding-discipline` 为 active |
| `agent-skill-matrix.yml` | `dev-agent` owns 追加 `coding-discipline`；`quality-reviewer-agent` can-call 追加；`dev-agent` can-call 追加 `record-idea`（§4.9-③，按 AGENTS.md:135 登记要求） |
| `AGENT-SKILL-MATRIX.md` | 主责矩阵表格同步 |
| `dir-graph.yaml` | 登记新 skill 路径 |
| `skills/develop/implement-code/SKILL.md` | Step 3 引用 `coding-discipline` §1+§2；自修复分支引用 §3；追加 `depends-on` 拓扑排序规则与并发边界（§4.8） |
| `skills/planning/write-dev-plan/SKILL.md`（或对应路径） | 引用 `coding-discipline` §2 |
| `AGENTS.md` | 第 56 条修订（甲路线：自有规则兜底 + 外部可选加速） |
| `skills/develop/review-code/SKILL.md` | 追加第五维度（仅可验证项）；Step 1 改为无条件重新执行验证命令（§4.7）；Step 3 加 `suggestion_policy` 读取 + 三条升格判据与成批升格要求（仅 `lenient` 生效）、Step 6 输出模板补 `Suggestions : {N} 条` 与本轮 policy（§4.9-③） |
| `skills/develop/approve-code/SKILL.md` | 追加：`suggestions` 可选经 `record-idea` 转入 `docs/ideas/`，不设默认、不阻塞本 CR（§4.9-③） |
| `skills/develop/write-dev-tasks/SKILL.md` | TASK 正文追加接口契约小节；Step 4 追加类型一致性核对；注意事项替换为具体占位符判据（§4.6） |
| `pipeline-templates/code-implementation.pipeline.json` | **新增 input `suggestion_policy`（`type: select`，`options: [strict, lenient]`，`required: false`，`default: "strict"`）**；节点 9（`review-code`）prompt 同步第五维度、无条件重验与策略化升格判据；节点 2（`write-dev-tasks`）prompt 同步接口契约要求；节点 6（`implement-code`）prompt 同步拓扑排序规则 |
| `skills/requirement/write-requirement-prd/SKILL.md` | 追加：优先采纳 `summary` 中已确认边界/排除项 |
| `ARCHITECTURE.md` §8 | 登记本次 CR（§3 代码地图新增一个 owns skill） |
| `openwiki/` | 相关页面同步 |

**每批验证关卡**：`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce` 通过 + 1 个真实 CR 回归验证状态机推进正常。

---

## 7. 待定事项

- **CR 交付方式未定**：本 checkout（`phase0-tools`，`role: platform-tools-package`）不持有 `change-requests/`，无法自行开 CR——历史上 CR-2026-021/022/023 均建于目标 workspace（knowledge-base），本包侧只接收带 CR 编号的提交。本次沿用该模式或采用其他路径，由用户后续决定。
- **check-skill-matrix.mjs 增强**（校验 external 声明必须有真实引用点）：已识别为独立漂移治理项，本次不做，避免让当前改动背负存量债务（`systematic-debugging` 等死声明清理后不会立即触发新检查报红）。
- **`capabilities` 真闭环（Level C）**：§4.9-① 本次只做数据订正，`capabilities` 仍无消费方、无校验、全仓零文档，命名体系混着三种风格（抽象能力名／skill 别名／确切 skill 名），无命名规则即无法写校验。真闭环需 `supported` 改为 `capability → 实现 skill[]` 映射 + `check-agents-contract.mjs` 加第 5 条不变式（约 40 个条目要填，过程会牵出新的 pending 项），工作量自成一个 CR。**未做此项前，§4.9-① 的订正仍可能再次漂移**。
- **`requirement`/`tech-design` 阶段的 suggestions 分流**：§4.9-③ 本次只做 code 阶段，另两阶段机制同构，同理可扩。
- **`crctl task done` 依赖守卫**（§4.8 的可执行化）：本次 §4.8 落在 prompt 层（`implement-code` 自觉按拓扑序执行），**没有可执行守卫兜底**。与 TDD 那类"本质不可验证"的规则不同，这一条是**可以**被机械校验的——`crctl task done` 已经读写 `tasks/_index.yml`，加一条"`depends-on` 前置未 done 则拒绝标记本 TASK"的检查是自然延伸，且与 crctl「账本唯一写入通道 + 状态机守卫」的既有哲学一致。本次不做的理由是范围控制（涉及 crctl 新增校验逻辑与测试向量，属于独立 CR），但应登记为后续项，避免 §4.8 长期停留在"靠自觉"状态。

---

## 8. 附录：技能包详解卡片

（以下 10 项调研结论在拷问评审中未被推翻，予以保留；superpowers 一项已修正 v1.0 的缩写混淆错误）

### 8.1 ECC（Everything Claude Code）

生产级 AI 编码 Agent 操作系统（v2.1.0，MIT）。281 技能 / 94 命令 / 67 代理 / hooks 持续学习系统。**本方案用途**：理念借鉴，不引入实体（与 pipeline 编排重复，owns 唯一性无法治理如此规模）。

### 8.2 CopilotKit

agent-native 应用全栈 SDK，AG-UI 协议缔造者。14 个技能均为"教 agent 使用 CopilotKit"，非通用方法论。**本方案用途**：默认排除。

### 8.3 OpenSpec

AI 原生规格驱动开发系统，`/opsx:propose` 生成 proposal + specs + design + tasks 全套 artifacts。**本方案用途**：排除实体（与 engineering-docs 同构冲突），借鉴"先规格后代码"理念。

### 8.4 graphify

代码库 → 可查询知识图谱；tree-sitter AST 本地解析，Token 成本比直接读文件低 71.5 倍。**本方案用途**：可选工具，架构设计阶段取证辅助，不进矩阵。

### 8.5 i-have-adhd

让 AI 输出"行动优先、无废话"。**本方案用途**：默认排除，与 engineering-docs 结构化章节冲突。

### 8.6 open-code-review（ocr）

阿里内部 AI 代码审查助手开源版，确定性管道 × LLM 混合。50 仓库/200 PR/10 语言/80+ 工程师标注基准。**本方案用途**：**不引入**（§4.4、§5）——与 CR-2026-023 评审模型留痕冲突，findings 载体不存在，功能与 review-code 既有取证重复。

### 8.7 ponytail

极简编码七级阶梯。真实会话实测：LOC -54%、Token -22%、成本 -20%、时间 -27%、安全 100%。**本方案用途**：核心思想内化为本包自有 `coding-discipline` §1（§4.3）；已安装的完整版技能作可选加速器。

### 8.8 superpowers

完整软件开发方法论（v6.2.0）。14 技能：brainstorming、using-git-worktrees、writing-plans、subagent-driven-development、test-driven-development、requesting/receiving-code-review、finishing-a-development-branch 等。**注意**：其中的 "SDD" 指 Subagent-Driven Development，与本包"技术设计文档"的 SDD 缩写撞车（§2）。**本方案用途**：`writing-plans` 的 Step 拆解粒度、TASK 接口契约、类型一致性自查、占位符判据思想分别内化进 `coding-discipline` §2 与 `write-dev-tasks`（§4.3、§4.6，v2.0 首次评审时只读了 description 摘要，v2.2 全文重读后补充后三项）；`systematic-debugging` 的根因排查思想内化进 `coding-discipline` §3（§4.3）；`verification-before-completion` 的"不信自报、独立重验"思想揭示了 `review-code` 证据链的真实漏洞，其无条件重验规则与回归测试红绿验证分别内化进 `review-code` Step 1 与 `coding-discipline` §3（§4.7，v2.2 新增）；`test-driven-development` 不采用（与本包 SDD 驱动主链矛盾，§4.3）；`requesting/receiving-code-review` 不采用（与既有 reviewLoop 账本重复）；`executing-plans` / `subagent-driven-development` 作为可选加速器保留声明；`dispatching-parallel-agents` 的"独立域分组 + 并发派发"模式作为 §4.8 拓扑排序的可选加速器（并发只影响耗时不影响产出），其 When NOT to Use 判据内化为本包并发边界规则（v2.4 新增）；`using-superpowers` 不采用（其"响应前查技能"的自由裁量场景在预定义 pipeline 节点序列下不成立）。

### 8.9 skills（mattpocock）

TypeScript 资深工程师工作流配置。核心技能实际安装名为 **`grilling`**（v1.0 误写的 `grill-me`/`grill-with-docs` 不存在）。**本方案用途**：拷问能力用于需求硬化，发生在流水线之外（§4.1），不作为 pipeline 节点。

### 8.10 taste-skill

"The Anti-Slop Frontend Framework for AI Agents"。三拨盘机制（DESIGN_VARIANCE / MOTION_INTENSITY / VISUAL_DENSITY）+ 排版/配色/间距/动效四大规范。**本方案用途**：仅可验证项（a11y 对比度、状态完整性）纳入 review-code 第五维度；审美主张类不内化，作为已安装的可选 external 参考（§4.4）。

---

## 结语

v1.0 提出的"强编排 + 优方法论"分工组合方向没有错，但其具体注入点半数建立在未经核实的假设上：external 声明从未被校验、TDD 与本包 SDD 主链矛盾、ocr 与刚落地的评审留痕机制冲突、审美规范不可验证。v2.0–v2.4 沿用同一判据贯穿始终——**能否被本包既有的可执行守卫（crctl CAS、guard deny、lint-prompts、两个 checker）验证，以及是否对应一处真实存在的机制空白**——筛掉了不可执行的社交纪律与审美主张，最终保留六条内化项：`coding-discipline`（§1 极简阶梯 + §2 步骤粒度 + §3 根因排查与回归验证）承接 dev-agent 侧的开发纪律；`write-dev-tasks` 的接口契约与类型一致性自查堵住跨 TASK **签名**断裂的口子；`implement-code` 的依赖拓扑排序堵住跨 TASK **时序**错乱的口子（同一失效面的两半）；`review-code` 的无条件重新验证堵住证据链"自报即采信"的口子。外部同名技能（ponytail / writing-plans / systematic-debugging / verification-before-completion / dispatching-parallel-agents）全部降级为可选加速器而非前置依赖。

这也是 v2.2–v2.4 反复出现的教训：v1.0/v2.0 只读 description 摘要就把四个技能判为"纯重复"并归入死声明，三次全文重读（`systematic-debugging` → 根因排查；`writing-plans`/`verification-before-completion` → 接口契约与独立重验；`dispatching-parallel-agents` → 依赖排序）各挖出一处被误判的真实空白。**"重复"这个判断本身必须读全文才能下，不能停在标题**——而且三次挖出的空白有一个共同特征：它们都不是"缺少某个外部工具"，而是**本包自己已经声明了一半的机制没有闭环**（TDD 引用悬空、`depends-on` 无消费方、验证结果自报即采信）。外部技能真正的价值不是填补功能，是当作一面镜子照出自己声明与执行之间的裂缝。
