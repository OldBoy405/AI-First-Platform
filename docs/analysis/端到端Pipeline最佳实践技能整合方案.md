# 端到端 Pipeline 最佳实践技能整合方案

> 版本：v2.3（经拷问评审 + 追加决策）｜ 日期：2026-08-08 ｜ 状态：结论已定，CR 交付方式待定
> 适用范围：AI-First 研发协同平台 Phase0 Tools 包
> v1.0 依据：对 `C:\Users\GOBAO\Downloads\AI\skills` 下 10 个开源技能包的完整分析
> v2.0 变更：v1.0 经过一轮逐项拷问评审，约六成内容被事实证伪或推翻，本版为评审后的最终结论
> v2.1 变更：识别出一处真实空白——`review-code`/`write-test-report` 回修循环缺少"先定位根因再动手改"的步骤；`systematic-debugging` 的核心思想并入 `coding-discipline` §3（§4.2 的声明删除结论不变，删的是死声明，不是能力）
> v2.2 变更：对 `writing-plans` / `verification-before-completion` 做全文重读（此前仅读到 description 摘要），发现四处真实价值：TASK 接口契约、TASK 类型一致性自查、占位符判据具体化、评审证据无条件重新验证；同时修正 v2.1 自身的一处粒度错误——`coding-discipline` §2 把 superpowers"Step"（2-5 分钟）误写成了 TASK 粒度，与 `write-dev-tasks` 既有的"1-3 天"TASK 定义矛盾
> v2.3 变更：明确并统一并入方式——全部内化条目均为**直接改写本包 SKILL.md 正文**（用本包语汇重述规则），不是"声明调用外部技能"；技能名仅作来源标注或可选加速器出现，不作为执行前提。本次把 §4.3 已用于 `systematic-debugging` 的甲路线加速器条款，同样补齐到 §4.6（`writing-plans`）与 §4.7（`verification-before-completion`）

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

**批次二 · 内化（真实行为变更）**

| 文件 | 修改内容 |
|---|---|
| `skills/develop/coding-discipline/SKILL.md`（新建） | §1 极简阶梯 + §2 拆解粒度 + §3 根因排查 |
| `skills/_index.yml` | 登记 `coding-discipline` 为 active |
| `agent-skill-matrix.yml` | `dev-agent` owns 追加 `coding-discipline`；`quality-reviewer-agent` can-call 追加 |
| `AGENT-SKILL-MATRIX.md` | 主责矩阵表格同步 |
| `dir-graph.yaml` | 登记新 skill 路径 |
| `skills/develop/implement-code/SKILL.md` | Step 3 引用 `coding-discipline` §1+§2 |
| `skills/planning/write-dev-plan/SKILL.md`（或对应路径） | 引用 `coding-discipline` §2 |
| `AGENTS.md` | 第 56 条修订（甲路线：自有规则兜底 + 外部可选加速） |
| `skills/develop/review-code/SKILL.md` | 追加第五维度（仅可验证项）；Step 1 改为无条件重新执行验证命令（§4.7） |
| `skills/develop/write-dev-tasks/SKILL.md` | TASK 正文追加接口契约小节；Step 4 追加类型一致性核对；注意事项替换为具体占位符判据（§4.6） |
| `pipeline-templates/code-implementation.pipeline.json` | 节点 9（`review-code`）prompt 同步第五维度与无条件重验；节点 2（`write-dev-tasks`）prompt 同步接口契约要求 |
| `skills/requirement/write-requirement-prd/SKILL.md` | 追加：优先采纳 `summary` 中已确认边界/排除项 |
| `ARCHITECTURE.md` §8 | 登记本次 CR（§3 代码地图新增一个 owns skill） |
| `openwiki/` | 相关页面同步 |

**每批验证关卡**：`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce` 通过 + 1 个真实 CR 回归验证状态机推进正常。

---

## 7. 待定事项

- **CR 交付方式未定**：本 checkout（`phase0-tools`，`role: platform-tools-package`）不持有 `change-requests/`，无法自行开 CR——历史上 CR-2026-021/022/023 均建于目标 workspace（knowledge-base），本包侧只接收带 CR 编号的提交。本次沿用该模式或采用其他路径，由用户后续决定。
- **check-skill-matrix.mjs 增强**（校验 external 声明必须有真实引用点）：已识别为独立漂移治理项，本次不做，避免让当前改动背负存量债务（`systematic-debugging` 等死声明清理后不会立即触发新检查报红）。

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

完整软件开发方法论（v6.2.0）。14 技能：brainstorming、using-git-worktrees、writing-plans、subagent-driven-development、test-driven-development、requesting/receiving-code-review、finishing-a-development-branch 等。**注意**：其中的 "SDD" 指 Subagent-Driven Development，与本包"技术设计文档"的 SDD 缩写撞车（§2）。**本方案用途**：`writing-plans` 的 Step 拆解粒度、TASK 接口契约、类型一致性自查、占位符判据思想分别内化进 `coding-discipline` §2 与 `write-dev-tasks`（§4.3、§4.6，v2.0 首次评审时只读了 description 摘要，v2.2 全文重读后补充后三项）；`systematic-debugging` 的根因排查思想内化进 `coding-discipline` §3（§4.3）；`verification-before-completion` 的"不信自报、独立重验"思想揭示了 `review-code` 证据链的真实漏洞，其无条件重验规则与回归测试红绿验证分别内化进 `review-code` Step 1 与 `coding-discipline` §3（§4.7，v2.2 新增）；`test-driven-development` 不采用（与本包 SDD 驱动主链矛盾，§4.3）；`requesting/receiving-code-review` 不采用（与既有 reviewLoop 账本重复）；`executing-plans` / `subagent-driven-development` 作为可选加速器保留声明；`using-superpowers` 不采用（其"响应前查技能"的自由裁量场景在预定义 pipeline 节点序列下不成立）。

### 8.9 skills（mattpocock）

TypeScript 资深工程师工作流配置。核心技能实际安装名为 **`grilling`**（v1.0 误写的 `grill-me`/`grill-with-docs` 不存在）。**本方案用途**：拷问能力用于需求硬化，发生在流水线之外（§4.1），不作为 pipeline 节点。

### 8.10 taste-skill

"The Anti-Slop Frontend Framework for AI Agents"。三拨盘机制（DESIGN_VARIANCE / MOTION_INTENSITY / VISUAL_DENSITY）+ 排版/配色/间距/动效四大规范。**本方案用途**：仅可验证项（a11y 对比度、状态完整性）纳入 review-code 第五维度；审美主张类不内化，作为已安装的可选 external 参考（§4.4）。

---

## 结语

v1.0 提出的"强编排 + 优方法论"分工组合方向没有错，但其具体注入点半数建立在未经核实的假设上：external 声明从未被校验、TDD 与本包 SDD 主链矛盾、ocr 与刚落地的评审留痕机制冲突、审美规范不可验证。v2.0–v2.2 沿用同一判据贯穿始终——**能否被本包既有的可执行守卫（crctl CAS、guard deny、lint-prompts、两个 checker）验证，以及是否对应一处真实存在的机制空白**——筛掉了不可执行的社交纪律与审美主张，最终只保留真实空缺：`coding-discipline`（§1 极简阶梯 + §2 步骤粒度 + §3 根因排查与回归验证）承接 dev-agent 侧的开发纪律；`write-dev-tasks` 的接口契约与类型一致性自查堵住跨 TASK 断裂的口子；`review-code` 的无条件重新验证堵住证据链"自报即采信"的口子。外部同名技能（ponytail / writing-plans / systematic-debugging / verification-before-completion）全部降级为可选加速器而非前置依赖——这也是 v2.2 的教训：v1.0/v2.0 只读 description 摘要就下结论，两次全文重读（systematic-debugging 触发、writing-plans/verification-before-completion 触发）各挖出一处此前被误判为"纯重复"的真实空白，说明"重复"判断本身需要读全文才能下，不能停在标题。
