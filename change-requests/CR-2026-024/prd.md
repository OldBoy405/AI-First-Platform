---
id: CR-2026-024-prd
type: PRD
cr-ref: CR-2026-024
title: Phase0 Tools 技能整合 — 端到端 Pipeline 最佳实践（六条内化项 + 存量缺口收口 + external 死声明清理）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-08T17:20:00+08:00"
updated: "2026-08-08T21:30:00+08:00"
---

# PRD — 端到端 Pipeline 最佳实践技能整合（方案 v2.6 落地）

## 1. 概述

### 1.1 问题陈述

社区涌现大量 Agent Skills 生态项目（superpowers、mattpocock skills、ponytail、taste-skill 等），覆盖需求、设计、计划、开发、审查全研发链路。本工具包（Phase0 Tools）已具备完整编排层（pipeline + crctl 状态机 + agent-skill-matrix 治理 + engineering-docs 文档体系）。《端到端Pipeline最佳实践技能整合方案》v1.0 提出以 external 身份注入外部方法论；经逐轮拷问评审（v2.0–v2.6），多数注入点被证明与本包既有机制冲突、重复或建立在错误事实上，最终按同一判据——**能否被本包既有的可执行守卫（crctl CAS、guard deny、lint-prompts、check-skill-matrix、check-agents-contract）验证，以及是否对应一处真实存在的机制空白**——筛出两类真实缺口：

- **外部技能对照发现的六条内化项**（§4.3–§4.9-③）：`coding-discipline`（极简阶梯/步骤粒度/根因排查）、TASK 接口契约与类型一致性、评审证据无条件重新验证、TASK 依赖拓扑排序、suggestions 策略化分流。三次全文重读（`systematic-debugging` → 根因排查；`writing-plans`/`verification-before-completion` → 接口契约与独立重验；`dispatching-parallel-agents` → 依赖排序）各挖出一处被 v1.0 误判为"纯重复"的真实空白——它们的共同特征不是"缺少某个外部工具"，而是**本包自己已声明了一半的机制没有闭环**（TDD 引用悬空、`depends-on` 无消费方、验证结果自报即采信）。
- **本包自查发现的四条存量缺口**（§4.9，与外部技能无关）：`capabilities` 声明与事实相反、`forbidden` 性质误导（像闸实为文档）、`suggestions` 只写不读、`assignee` 死字段。

核心结论不变：外部技能只填补方法论空缺，**不新增 owns、不改状态机、不破坏单一事实源**；已安装的同名外部技能（ponytail / writing-plans / systematic-debugging / verification-before-completion / dispatching-parallel-agents）全部降级为**可选加速器**，不构成执行前提，也不要求任何跨运行时探测机制。

### 1.2 解决方案摘要

按方案 v2.6 分两批实施：

**批次一 · 收口（纯删除与对齐，零新增行为）**：删 actor 级零引用 external 死声明（`system-orchestrator.external`：`using-superpowers` / `writing-plans` / `verification-before-completion`；`dev-agent.external`：`test-driven-development`——随本 CR 删其唯一真实引用即变零引用，须同批清除；`systematic-debugging` 仅存于顶层纯文档块不动，见 SDD §0 C-2/C-5）；`implement-code` 与 `code-implementation.pipeline.json` 节点 6 删 TDD 悬空引用并补 `executing-plans`/`subagent-driven-development` 降级路径；`agents/_index.yml` 三项 capabilities 从 `supported` 挪进 `pending` 且 `known-gaps` 前两条删除；`AGENT-SKILL-MATRIX.md` 与 openwiki 写明 `forbidden` 为声明性边界（无调用级拦截）；`write-dev-tasks` 删 `assignee` 死字段。

**批次二 · 内化（真实行为变更）**：新建 `coding-discipline` skill（§1 极简阶梯 + §2 步骤粒度 + §3 根因排查与回归验证）并完成登记/矩阵/消费方引用闭环；`review-code` 新增「前端质量」维度（仅可验证项）与 Step 1 无条件重新执行验证命令；`write-dev-tasks` 追加接口契约小节、类型一致性自查与占位符判据；`implement-code` 追加 `depends-on` 拓扑排序与并发边界；`code-implementation.pipeline.json` 新增触发参数 `suggestion_policy`（select，strict/lenient，default strict）驱动评审期 suggestions 策略化分流，`approve-code` 追加 suggestions 经 `record-idea` 落 `docs/ideas/`；`write-requirement-prd` 优先采纳 summary 已确认边界；AGENTS.md 第 56 条修订为甲路线表述。

**范围口径**：全部改动对象位于 tools 包（`../tools/`），经本 CR worktree 流程追踪，tools 仓提交带 CR 编号溯源、合入 `custom/main`（对齐 CR-2026-021/022/023 先例）。

### 1.3 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 依据 |
|---|---|
| `agent-skill-matrix.yml` 的 `external:` 字段只被 `check-skill-matrix.mjs` 用作"豁免 owns 唯一性检查"，从未校验外部技能是否存在或被引用；4 个死声明多 CR 周期零引用点、CI 从未报警 | `check-skill-matrix.mjs` + 方案 §4.2 取证 |
| `implement-code/SKILL.md` 第 75 行要求遵循未安装的 external `test-driven-development`，规则静默蒸发，下游 `test-report.status=pass` 门禁照常要求证据——纪律与门禁脱钩的悬空引用 | 方案 §4.3 问题根源 |
| `depends-on` 已声明（`write-dev-tasks/SKILL.md:41`）、已写入 frontmatter（:58）、已汇总进 `tasks/_index.yml`（:75）、已被 `validate-doc` 校验指向有效（`validate-doc/SKILL.md:15`），但**无任何消费方用它决定执行顺序** | 方案 §4.8 表格 |
| `agents/_index.yml` 的 `capabilities.supported` 宣称三项能力而 `agent-skill-matrix.yml` 的 `known-gaps` 同时承认其无对应 Skill；`pending` 字段 9 个 agent 全为 `[]` | 方案 §4.9-① |
| `check-agents-contract` 白名单校验只作用于 `references[]`，不覆盖 SKILL.md 正文让 agent 调用什么；`pretooluse-guard.mjs` 只管文件路径不管技能调用——`forbidden` 想管的运行时调用面无人看守 | 方案 §4.9-② |
| 三个 review skill 声明 `suggestions`、crctl 落盘进 `review-annotations/{stage}.yml`，但回修链只读 `blockers`/`repair-instructions`，`approve-code` 全文零次提及、`writeback-*` 零消费 | 方案 §4.9-③ |
| `review-code/SKILL.md:46` 现状"若缺失必须重新运行或要求补齐"——implement-code 自报即采信 | 方案 §4.7 问题根源 |
| `assignee: ""` 全仓仅 1 处（`write-dev-tasks/SKILL.md:59` 模板自身），零读取方，连 `tasks/_index.yml` 汇总都不含它 | 方案 §4.9-④ |
| 现有三个 `select` 型 input（`focus_dimension`/`insight_type`/`new_owner_role`）全部为 `required: false` + `default` 组合，全仓 `required: true` 与 `default` 并存零先例 | 方案 §4.9-③ 形态对齐依据 |
| `review-code` 的 `reviewLoop.replayNodes` 按显式 nodeId 引用而非位置序，新增 input 不在任何 replay 列表内，天然不被重放 | CR-2026-023 PRD §1.4 同源事实 |
| 本工具包是文档驱动（SDD：技术设计文档驱动）而非测试驱动；测试报告在代码之后，测试角色是证明 TASK 验收条件而非驱动实现 | 方案 §2 术语澄清 |

### 1.4 方案遗留决策点（本 PRD 拍板）

方案 v2.6 §7 的待定项中，与 PRD 范围直接相关的由本 PRD 给出决定，SDD/实施期不得再次悬置：

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 方案 §7"CR 交付方式未定" | **沿用 knowledge-base 注册模式**（已在 CR-2026-024 注册时落地），tools 仓改动经 CR 编号溯源合入 `custom/main` | 与 CR-2026-021/022/023 一致，零新机制 |
| D-2 | `check-skill-matrix.mjs` 增强（external 声明必须有真实引用） | **不做，列入范围排除** | 独立漂移治理项；本次不做避免让当前改动背负存量债务（死声明清理后不会触发新检查报红） |
| D-3 | `capabilities` 真闭环（Level C，约 40 条目） | **不做，列入范围排除** | 工作量自成一个 CR；本次只做数据订正（Level A） |
| D-4 | `requirement`/`tech-design` 阶段的 suggestions 分流 | **不做，本次只做 code 阶段** | 另两阶段机制同构，且其 suggestions 更可能在当轮被吸收进 PRD/SDD 迭代，优先级低 |
| D-5 | `crctl task done` 依赖守卫（§4.8 的可执行化） | **不做，列入后续项** | 涉及 crctl 新增校验逻辑与测试向量，属独立 CR；本次 §4.8 落在 prompt 层 |
| D-6 | TDD 铁律 / superpowers requesting·receiving-code-review | **不采用，列入范围排除** | TDD 与本包 SDD 驱动主链矛盾且不可验证；社交纪律与既有 reviewLoop 账本重复且后者更强（有留痕） |
| D-7 | ocr / taste-skill 审美 / `redesign-existing-projects` | **不引入，列入范围排除** | ocr 与 CR-2026-023 评审模型留痕冲突；审美不可验证；redesign 属投机需求（详见范围排除） |

## 2. 用户故事

- **US-1** 作为 `dev-agent`（实现者），实现单个 TASK 时按 `coding-discipline` §1 极简阶梯选方案、§2 按 2-5 分钟粒度切分步骤、自修复分支先按 §3 定位根因再动手，不再逐条症状打补丁。
- **US-2** 作为 `dev-agent`（实现者），开始某 TASK 前先读 `tasks/_index.yml` 的 `depends-on` 做拓扑排序，前置 TASK 未 done 时不启动并留痕，不再按索引顺序撞序实现导致上游断裂。
- **US-3** 作为 `quality-reviewer-agent`（评审者），评审前端 diff 时有「前端质量」维度（a11y 对比度/组件状态完整性/构建体积），评审证据 Step 1 无条件重新执行验证命令而非采信 implement-code 自报。
- **US-4** 作为流水线启动者，触发 `/coding` 时通过 `suggestion_policy` 选择交付节奏——默认 strict 只判 CR 本身 pass/block，想清技术债时改选 lenient 把该修的升格进 blockers。
- **US-5** 作为审批人，评审输出能看到本轮所用 policy 与 Suggestions 条数；剩余 suggestions 可经 `record-idea` 转入 `docs/ideas/`，不再"只写不读"静默丢失。
- **US-6** 作为计划编写者（`write-dev-tasks`），TASK 正文含「接口契约」小节（消费/产出精确签名），Step 4 核对跨 TASK 签名一致性，命名对不上时输出 WARN 而非静默覆盖。
- **US-7** 作为维护者，`agents/_index.yml` 的 capabilities 与 `agent-skill-matrix.yml` 的 known-gaps 不再自相矛盾；`forbidden` 的性质被文档写明是声明性边界而非闸。
- **US-8** 作为需求撰写者（`write-requirement-prd`），当 `summary` 已携带拷问阶段确认的边界与排除项时，优先采纳不再重新询问。

## 3. 功能需求

### 批次一 · 收口（纯删除与对齐，零新增行为）

- **FR-1（删死声明 external）**：`agent-skill-matrix.yml` actor 级 external 删除五项零引用声明——`system-orchestrator.external` 的 `using-superpowers`、`writing-plans`、`verification-before-completion`（actor 级仅此三项，`systematic-debugging` 仅存于顶层纯文档块，不动，见 SDD §0 C-2）；以及 `dev-agent.external` 的 `test-driven-development`（FR-2/FR-3 删其唯一真实引用后即变零引用，须同批清除，否则本 CR 自造新死声明，见 SDD §0 C-5）；保留 `executing-plans`、`subagent-driven-development`（`implement-code` 有真实引用）；`brainstorming` 不动（唯一四件套齐全的样板）。
- **FR-2（implement-code 删 TDD 引用 + 补降级路径）**：`skills/develop/implement-code/SKILL.md` 删第 75 行「必须遵循目标运行时已安装的 external `test-driven-development`」；`executing-plans`/`subagent-driven-development` 按 `brainstorming` 写法补降级路径——批次一仅落「未提供 subagent-driven-development 时按 TASK 顺序串行实现（等价降级到 executing-plans 语义），节点输出注明降级」；后半句「两者均未提供时按 `coding-discipline` §2 粒度自行拆解执行」归批次二（与 coding-discipline 新建同批，避免批次一携带指向未来产物的悬空引用，批次拆分以 SDD §3.4/§4.1/§4.2 为准）。
- **FR-3（pipeline 节点 6 prompt 同步）**：`pipeline-templates/code-implementation.pipeline.json` 节点 6（implement-code）prompt 同步删除 TDD 表述、补降级路径表述。
- **FR-4（capabilities 订正，§4.9-①）**：`agents/_index.yml` 将 `knowledge-agent` 的 `tech-note-write`/`insight-write` 与 `customer-support-agent` 的 `unresolved-feedback-record` 从 `capabilities.supported` 挪进 `pending`；`agent-skill-matrix.yml` 的 `known-gaps` 前两条删除（`pending` 已表达同一事实），第三条 `writeback-agent-entry` 与 capabilities 无关保留。
- **FR-5（forbidden 性质说明，§4.9-②）**：`AGENT-SKILL-MATRIX.md` 与 `openwiki/architecture/agent-skill-matrix.md` 写明 `forbidden` 的性质——声明性边界，执行靠 agent 自觉 + `protectedPaths` 文件守卫，**不存在调用级拦截**；不加运行时钩子（`protectedPaths` 已覆盖高危面）。
- **FR-6（删 assignee 死字段，§4.9-④）**：`skills/develop/write-dev-tasks/SKILL.md` 删 TASK frontmatter 的 `assignee` 字段；真要多人协作时 `cr.md` 需先支持多开发负责人，不是加字段就够。

### 批次二 · 内化（真实行为变更）

- **FR-7（新建 coding-discipline skill，§4.3）**：新建 `skills/develop/coding-discipline/SKILL.md`，内容为本包自有、可被 lint-prompts 覆盖的规则（而非指向外部技能名）：
  - **§1 极简阶梯**（源自 ponytail，本包语汇重写）：需要存在吗（YAGNI）→ 代码库已有 → 标准库 → 平台原生 → 已装依赖 → 一行 → 最小可用实现。信任边界校验、错误处理、安全、可访问性不在精简范围内。
  - **§2 执行步骤粒度**（源自 writing-plans）：执行单个 TASK 时内部步骤按 2-5 分钟粒度切分（写验证用例→跑到失败/明确当前状态→实现→复验→提交），每步含精确文件路径与验证步骤，禁止 TBD/占位符。TASK 本身粒度（1-3 天）由 `write-dev-tasks` 定义，不受本节约束。
  - **§3 根因排查 + 回归验证**（源自 systematic-debugging + verification-before-completion）：进入自修复模式（`review_feedback` 存在）时，动手改前先定位根因（哪个 TASK、哪一行、什么假设不成立），同一根因下所有失败点一次修完；节点输出必须含 `root-cause` 字段（与 `fixed-blockers` 并列）。若修复针对 bug（非纯新功能缺口），对应回归测试先验"红"（临时还原修复前代码跑一次确认失败）再验"绿"（恢复修复跑一次确认通过），两次结果写入节点输出。
  - **甲路线措辞**：已装完整 external 技能（ponytail/systematic-debugging/writing-plans）时优先走其完整流程，未装按本节规则执行，二者等价；`coding-discipline` 是兜底事实源，不依赖跨运行时探测。
- **FR-8（coding-discipline 登记与归属）**：`skills/_index.yml` 登记为 active；`agent-skill-matrix.yml` 下 `dev-agent` owns、`quality-reviewer-agent` can-call；`AGENT-SKILL-MATRIX.md` 主责矩阵表格同步；tools 仓 `dir-graph.yaml` 登记路径；`ARCHITECTURE.md` §8 代码地图登记。
- **FR-9（implement-code 消费 coding-discipline，§4.3/§4.8）**：`implement-code/SKILL.md` Step 3 引用 §1+§2，自修复分支额外引用 §3；追加 `depends-on` 拓扑排序规则——执行前读 `tasks/_index.yml` 的 `depends-on` 拓扑排序，前置 TASK 未 done 不得开始并注明被阻塞项与等待的前置项。
- **FR-10（write-dev-plan 消费 coding-discipline）**：`skills/develop/write-dev-plan/SKILL.md` 引用 `coding-discipline` §2（步骤粒度约束）。（路径订正：技术评审 M-3 实测该 skill 在 develop 域，原 planning 域表述错误，以 SDD §0 C-4 为准）
- **FR-11（review-code 前端质量维度，§4.4）**：`review-code/SKILL.md` Step 3 评审维度表新增「前端质量」维度（仅前端 diff 触发；按维度名验收不用序数——实测现有 6 行，新增为第 7 行；`code-implementation.pipeline.json` nodes[9].prompt 的 ①②③④ 枚举同步追加 ⑤，见 SDD §0 B-4）：a11y 对比度达 WCAG AA（破 AA 升 blocker）、组件 loading/empty/error 状态完整覆盖、构建体积在预算内（其余 minor）；触发条件为 diff 命中 `*.tsx`/`*.vue`/`*.css`/`*.html`。`dimensions` 为自由映射（crctl 仅校验非空），加键零结构成本。
- **FR-12（review-code 无条件重验，§4.7）**：`review-code/SKILL.md` Step 1 改为**无条件重新执行**验证命令（lint/test/build），不再是"缺失才补跑"；implement-code 自报结果仅作参考对照，不一致时以本轮重新执行结果为准并在 blockers 注明差异。评审判据细化：「测试通过」必须是本轮重新执行的完整命令输出（0 failures），"看起来通过"或"之前跑过"不构成证据。甲路线措辞：无条件重验是 `review-code` 自身最低要求，不因是否装外部技能而增减，不弱化为"可选加速"；已装 `verification-before-completion` 时可用其 Gate Function/Common Failures 表作补充参考。
- **FR-13（suggestion_policy 触发参数，§4.9-③/v2.6）**：`code-implementation.pipeline.json` `inputs` 新增 `{ key: suggestion_policy, label: 改进建议处置策略, type: select, options: [strict, lenient], required: false, default: "strict", description: strict=不升格（默认，保守交付）；lenient=按三条判据把本 CR 内该修的升格进 blockers（清技术债场景） }`——形态严格对齐包内三个既有 `select` input（required:false + default），UI 预选中 strict。
- **FR-14（review-code 策略化分流，§4.9-③）**：策略参数由 `code-implementation.pipeline.json` nodes[9].prompt 的 `{{inputs.suggestion_policy}}` 插值承载（插值只发生在 pipeline JSON；`review-code/SKILL.md` Step 3 只写模式无关表述「按本轮策略参数执行，缺省 strict」，正文不含插值语法，同源先例 review_llm，见 SDD §0 B-1）。`lenient` 模式下非阻塞发现同时满足三条升格判据且通过轮次闸才进 blockers——① 改动不超出本 CR 已触碰的文件（不扩大 diff）；② 有明确"改成什么"（能写进 `repair-instructions`）；③ 不需要产品/架构决策（纯实现层）；④ 轮次闸：仅首轮评审（attempt=1）允许升格，第 2 轮起一律 suggestions——防升格消耗 maxAttempts=3 耗尽轮次、停在 developing 无法进入审批。同一轮多条升格项写进同一批 blockers（成批升格）。留痕：dimensions 写 `suggestion-policy: {strict|lenient}`，canonical 化进 `review-annotations/code.yml`（跨 CR 可比性依赖 canonical，节点输出不是账本，见 SDD §2.5）；Step 6 输出模板补 `Suggestions : {N} 条` 与本轮 policy。`strict` 模式（默认）所有非阻塞发现一律进 suggestions。语义校准：blockers=本 CR 内要处理的，suggestions=本 CR 内不处理的。
- **FR-15（approve-code 承接 suggestions，§4.9-③）**：`approve-code/SKILL.md` 追加——剩余 `suggestions` 可选经 `record-idea` 转入 `docs/ideas/`（CR worktree 内，随分支合并进 trunk；`feature-writeback` 硬边界只写 specs/delivery，故必须在 approve-code 期做），不设默认、不阻塞本 CR；不转则仅留档 `review-annotations`，无损失。
- **FR-16（agent-skill-matrix 登记 record-idea，§4.9-③）**：`agent-skill-matrix.yml` `dev-agent` can-call 追加 `record-idea`（按 AGENTS.md:135 登记要求，因 FR-15 新增真实引用点）。
- **FR-17（write-dev-tasks 接口契约，§4.6）**：`write-dev-tasks/SKILL.md` 三处修改——① TASK 正文追加「接口契约」小节：**消费**（本 TASK 使用哪些上游 TASK 产出的精确函数名/参数/返回类型）、**产出**（本 TASK 暴露给下游 TASK 的精确签名）；② Step 4（生成 TASK 索引后）追加核对步骤——核对所有 TASK 声明的接口签名是否一致，命名对不上时输出 WARN 并列出差异（比照"估算交叉校验"写法：不静默覆盖，由计划负责人决定）；③ 「注意事项」的"不得模糊描述"替换为具体判据清单（源自 writing-plans No Placeholders）：禁止 TBD/"待定"；禁止"加适当的错误处理"这类无实际内容的描述；禁止"同 TASK-03"这类引用而不给出实际代码/签名；禁止引用未在任何 TASK 中定义的类型或函数。甲路线措辞：以上为自有规则，已装 `writing-plans` 完整版时可引用其 Task Structure 模板作排版参考，两者不冲突不要求探测。
- **FR-18（write-requirement-prd 采纳 summary 边界，§4.1）**：`write-requirement-prd/SKILL.md` 追加一行——若 `summary` 携带已确认的边界与排除项，优先采纳，不再重新询问。
- **FR-19（pipeline prompt 同步，§4.8/§4.6/§4.9-③）**：`code-implementation.pipeline.json` 节点 9（review-code）prompt 同步第五维度、无条件重验与策略化升格判据；节点 2（write-dev-tasks）prompt 同步接口契约要求；节点 6（implement-code）prompt 同步拓扑排序规则。
- **FR-20（AGENTS.md 第 56 条修订，§4.5）**：tools 仓 `AGENTS.md` 第 56 条「外部 superpowers 能力由目标运行时提供，phase0 tools 不复制同名 SKILL.md，只在需要处声明依赖」改为甲路线表述——本包自有规则（`coding-discipline`）为兜底事实源，外部同名技能为可选加速器，二者不冲突、不要求探测。第 160 条「禁止把外部方法论 Skill 打包进 phase0 tools」保持不变（`coding-discipline` 非复制上游 SKILL.md，是本包语汇重写的自有规则）。
- **FR-21（openwiki 同步）**：`openwiki/` 相关页面同步（含 `architecture/agent-skill-matrix.md` 的 forbidden 性质说明与主责矩阵更新）。

### 收尾 —— 台账同步与验收

- **FR-22（批次原子性）**：批次二内部引用闭环——`coding-discipline` 新建 + `skills/_index.yml` 登记 + `agent-skill-matrix.yml` owns/can-call + `AGENT-SKILL-MATRIX.md` + 消费方引用（FR-9/FR-10）必须在**同一批提交**，否则 check-skill-matrix 报"active skill 无 owns"或"孤儿引用"。批次一与批次二**分开提交**（批次一零行为变更，便于回归定位）。
- **FR-23（验证关卡）**：每批完成后执行 `check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce` 全绿 + 1 个真实 CR 回归验证状态机推进正常（`crctl next`/`crctl status`/`crctl gate` 佐证无越级）。
- **FR-24（溯源标注）**：commit message 与代码注释注明需求来源为《端到端Pipeline最佳实践技能整合方案》v2.6 与本 CR（CR-2026-024）；全部改动不引入本机绝对路径（可移植性）。

## 4. 非功能需求

- **NFR-1（批次一零行为变更）**：批次一所有改动为纯删除与数据对齐，不改变任何运行时行为；回归验证应确认状态机推进、三件套守卫结果与改动前一致（除死声明减少导致的 `check-skill-matrix` 报告差异为预期）。
- **NFR-2（批次二同批原子性）**：FR-22 的同批提交是硬约束——`coding-discipline` 的登记与消费方引用拆开会触发 pre-commit 三件套自阻断（孤儿 skill / 缺失 owns）。
- **NFR-3（不新增 owns、不改状态机）**：`coding-discipline` 的 owns 为 `dev-agent`（既有 actor），不新增 actor；不新增/修改状态机状态与转换（15 具名状态 + 注册前 (new)，25 条声明转移，CR-2026-022 后含两条 reject 转换）。
- **NFR-4（甲路线，零探测依赖）**：外部同名技能全部为可选加速器，`coding-discipline`/拓扑排序/无条件重验等内化规则不依赖任何跨运行时探测机制（本包无此设施且为此新增成本远高于内化文本）。
- **NFR-5（零新增第三方依赖）**：本 CR 全部改动为 SKILL.md 正文、pipeline JSON、YAML 账本与文档，不引入新脚本依赖；不新增 crctl 子命令（D-5 决策：依赖守卫另立项）。
- **NFR-6（suggestion_policy 形态对齐先例）**：新 input 的形态（select + required:false + default）严格对齐包内三个既有 select input，不引入 `required:true + default` 并存的新形态（全仓零先例）。
- **NFR-7（lenient 模式口径留痕）**：`lenient` 模式下 blockers 语义扩大导致 `review-code` 输出的 Critical/Major 计数口径改变，评审输出必须注明本轮所用 policy，避免历史 CR 数据与 strict 模式直接比较时产生误读。
- **NFR-8（行尾纪律，纪律 #1）**：实施期涉及逐行解析/跨行正则的代码或验证，读入后先 `\r\n → \n` 规范化，解析失败硬失败，禁止静默降级。
- **NFR-9（可移植性）**：approvalPrompt/文档描述中的外部 CLI runner、验证命令由目标运行时提供，tools 包不硬编码模型名；全部改动不含本机绝对路径。
- **NFR-10（基线协调）**：若 tools 仓工作区存在与本 CR 无关的未提交修改，实施期对同一文件的改动必须叠加在其上、按变更归属拆分 commit，不得混入或覆盖（对齐 CR-2026-023 NFR-6 先例）。

## 5. 验收标准

- **AC-1**（FR-1）：`agent-skill-matrix.yml` actor 级 external 中 grep 不到 `using-superpowers|writing-plans|systematic-debugging|verification-before-completion|test-driven-development` 任一名称（订正：actor 级前三项位于 system-orchestrator.external，test-driven-development 位于 dev-agent.external，随本 CR 删其唯一真实引用而同批清除，见 SDD §0 C-2/C-5）；`executing-plans`、`subagent-driven-development`、`brainstorming` 保留；`check-skill-matrix.mjs` 通过。
- **AC-2**（FR-2/FR-3）：`implement-code/SKILL.md` grep 不到 `test-driven-development` 引用；含 executing-plans/subagent-driven-development 降级路径文本；`code-implementation.pipeline.json` 节点 6 prompt 同步；JSON 可解析。
- **AC-3**（FR-4）：`agents/_index.yml` 中三项能力位于对应 agent 的 `pending` 而非 `supported`；`agent-skill-matrix.yml` `known-gaps` 恰剩 `writeback-agent-entry` 一条（或与 capabilities 无关的保留项）；`check-agents-contract.mjs` 通过。
- **AC-4**（FR-5）：`AGENT-SKILL-MATRIX.md` 与 `openwiki/architecture/agent-skill-matrix.md` 均含"声明性边界"与"不存在调用级拦截"表述；grep 无"调用级拦截"的错误承诺。
- **AC-5**（FR-6）：`write-dev-tasks/SKILL.md` grep 不到 `assignee` 字段（模板与正文均无）。
- **AC-6**（FR-7/FR-8）：`skills/develop/coding-discipline/SKILL.md` 存在且含 §1 极简阶梯/§2 步骤粒度/§3 根因排查三节与甲路线措辞；`skills/_index.yml` 登记 active；`agent-skill-matrix.yml` `dev-agent` owns、`quality-reviewer-agent` can-call；`AGENT-SKILL-MATRIX.md` 与 tools `dir-graph.yaml`、`ARCHITECTURE.md` §8 同步；三件套通过。
- **AC-7**（FR-9/FR-10）：`implement-code/SKILL.md` Step 3 含 coding-discipline §1+§2 引用、自修复分支 §3 引用、depends-on 拓扑排序规则；`write-dev-plan/SKILL.md` 含 §2 引用。
- **AC-8**（FR-11）：`review-code/SKILL.md` Step 3 维度表含名为「前端质量」的新维度行（订正：按维度名验收，不用序号——实测现有 6 行，新增为第 7 行，见 SDD §0 B-4）且触发条件为 `*.tsx|*.vue|*.css|*.html`；破坏 WCAG AA 判 blocker、其余 minor；`code-implementation.pipeline.json` nodes[9].prompt 同步追加维度 ⑤；不含字体/配色/拨盘等审美主张。
- **AC-9**（FR-12）：`review-code/SKILL.md` Step 1 为无条件重新执行（无"缺失才补跑"表述）；含"0 failures"与"之前跑过不构成证据"判据；甲路线措辞不弱化为"可选加速"。
- **AC-10**（FR-13）：`code-implementation.pipeline.json` `inputs` 含 `suggestion_policy`（type=select，options=[strict,lenient]，required=false，default="strict"）；形态与既有三个 select input 一致；JSON 可解析。
- **AC-11**（FR-14）：验收对象以 pipeline JSON 为主（订正：`{{inputs.*}}` 插值只发生在 pipeline JSON，见 SDD §0 B-1）——`code-implementation.pipeline.json` nodes[9].prompt 含 `{{inputs.suggestion_policy}}` 插值读取与三条升格判据（lenient 才生效）、轮次闸（仅 attempt=1 允许升格）与成批升格要求；`review-code/SKILL.md` Step 3 为模式无关表述且正文不含 `{{inputs.` 插值语法；`review-annotations/code.yml` dimensions 含 `suggestion-policy` 留痕键（M-1）；Step 6 输出模板含 `Suggestions : {N} 条` 与本轮 policy；strict 模式不升格的语义明确。
- **AC-12**（FR-15/FR-16）：`approve-code/SKILL.md` 含 suggestions 经 record-idea 转 docs/ideas/ 的条款（不设默认、不阻塞）；`agent-skill-matrix.yml` `dev-agent` can-call 含 `record-idea`；check-skill-matrix 通过。
- **AC-13**（FR-17）：`write-dev-tasks/SKILL.md` 含接口契约小节（消费/产出）、Step 4 签名一致性核对（WARN 不静默覆盖）、占位符判据清单（TBD/待定/适当错误处理/同 TASK-XX/未定义引用 四类禁止）。
- **AC-14**（FR-18）：`write-requirement-prd/SKILL.md` 含"优先采纳 summary 已确认边界/排除项"条款。
- **AC-15**（FR-19）：pipeline 节点 2/6/9 prompt 分别同步接口契约、拓扑排序、第五维度+无条件重验+策略化升格；JSON 可解析；节点编号不变。
- **AC-16**（FR-20）：tools `AGENTS.md` 第 56 条为甲路线表述（自有规则兜底 + 外部可选加速），第 160 条保持不变。
- **AC-17**（FR-21）：openwiki 相关页面同步 forbidden 性质与主责矩阵。
- **AC-18**（FR-22/FR-23）：批次一与批次二分开提交；每批三件套（check-skill-matrix + check-agents-contract + lint-prompts enforce）全绿；1 个真实 CR 回归验证 `crctl next/status/gate` 无越级。
- **AC-19**（FR-24）：commit message 含方案 v2.6 与 CR-2026-024 溯源；grep 全改动无本机绝对路径（如 `C:\\Users`）。
- **AC-20**（端到端）：① strict 场景——默认触发 `/coding` 走完评审，非阻塞发现全进 suggestions、verdict 不受影响；② lenient 场景——改选 lenient，满足三条判据的发现升格进 blockers 并经 reviewLoop 在本 CR 修复，评审输出注明 policy=lenient；③ 审批场景——approve-code 期 suggestions 经 record-idea 落 docs/ideas/ 成功合并进 trunk。

## 6. 成功指标

- 批次一完成后 `agent-skill-matrix.yml` 死声明数为 0，`capabilities`/`known-gaps` 无自相矛盾，`assignee` 全仓零残留。
- 批次二完成后 `coding-discipline` 三件套全绿且被 implement-code/write-dev-plan 真实引用（非孤儿）。
- 评审证据链"自报即采信"漏洞关闭：`review-code` Step 1 无条件重验，`review-annotations/code.yml` 证据可追溯到本轮执行。
- suggestions 不再"只写不读"：lenient 模式下该修项经 reviewLoop 本 CR 解决，strict 模式下剩余项经 record-idea 进 docs/ideas/，留档率与流转率可观测。
- TASK 跨依赖断裂率下降：`depends-on` 拓扑排序使实现顺序与依赖一致，接口契约 WARN 提前暴露签名不一致。
- 全部改动通过三件套 + 1 个真实 CR 回归，状态机推进零越级。

## 7. 范围排除

**本 CR 包含**：方案 v2.6 §4.3–§4.9 全部落地项（批次一 6 项收口 + 批次二 15 项内化/同步），以及收尾原子性与端到端验收。

**本 CR 不包含**：
- `check-skill-matrix.mjs` 增强（external 声明必须有真实引用点）——独立漂移治理项（D-2）。
- `capabilities` 真闭环 Level C（`capability → 实现 skill[]` 映射 + check-agents-contract 第 5 条不变式，约 40 条目）——工作量自成 CR（D-3）。
- `requirement`/`tech-design` 阶段的 suggestions 分流——另两阶段机制同构，本次只做 code 阶段（D-4）。
- `crctl task done` 依赖守卫（§4.8 的可执行化）——涉及 crctl 新增校验与测试向量，独立 CR（D-5）。
- TDD 铁律 / superpowers requesting·receiving-code-review 社交纪律——与本包 SDD 驱动主链矛盾或与既有 reviewLoop 账本重复（D-6）。
- ocr 确定性预检 / taste-skill 审美规范（字体/配色/拨盘）/ `redesign-existing-projects`——与 CR-2026-023 评审模型留痕冲突 / 不可验证 / 投机需求（D-7）。
- OpenSpec 文档体系 / ECC 全家桶 / CopilotKit / i-have-adhd / 图像生成类技能——与 engineering-docs 同构冲突 / owns 唯一性无法治理 / 非通用方法论 / 产物不可验证（方案 §5）。
- `crctl.mjs`、`gates.json`、`rules.json` 本体改动——本 CR 无状态机/守卫变更需求（NFR-3/NFR-5）。
- 其他 7 条 pipeline 模板、与 CR 上下文无关的 skill 文档修订。

## 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-08 | v0.1.0 | Ray | 初始草稿（方案 v2.6 全量落地） |
| 2026-08-08 | v0.1.1 | Ray | 技术评审回修同步：attempt 1 订正 FR-10 路径与 AC-1/AC-8/AC-11；attempt 2 订正 FR-1/FR-2/FR-11/FR-14 正文与 SDD §0 C-2/C-4/C-5、§3.3/§3.4 对齐（B-5~B-8） |
