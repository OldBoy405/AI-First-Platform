---
id: CR-2026-024-sdd
type: SDD
cr-ref: CR-2026-024
title: Phase0 Tools 技能整合 — 端到端 Pipeline 最佳实践（六条内化项 + 存量缺口收口 + external 死声明清理）技术设计
status: draft
created: "2026-08-08T20:10:00+08:00"
updated: "2026-08-08T20:10:00+08:00"
---

# SDD — 端到端 Pipeline 最佳实践技能整合 技术设计

> 输入：`prd.md`（24 FR / 8 US / 20 AC）。目标仓：**tools 方法论包**（本 CR 目标代码仓即 tools 仓自身，架构基线读 `tools/ARCHITECTURE.md`，已存在、只读引用）。
> 所有落点行级定位已于技术设计期实跑核对（2026-08-08）；实施期行号若漂移，以结构锚点为准并在任务内订正（纪律 #4）。

## 0. 事实订正（技术设计期实跑核对发现的方案漂移）

PRD 与方案 v2.6 的三处表述与 tools 仓现状不符，本 SDD 予以订正，**结论不受影响**：

| # | 方案/PRD 表述 | 实测现状 | SDD 订正 |
|---|---|---|---|
| C-1 | 「implement-code 为 code-implementation pipeline 节点 6、write-dev-tasks 为节点 2」 | CR-2026-023 合入后 pipeline 为 **13 节点**（dev-start 审批与评审 LLM 选择两个 human_approval 插入致数组序漂移）：write-dev-tasks=**nodes[1]**、implement-code=**nodes[5]**、review-code=nodes[9]（恰未漂移） | 实施以实测下标为准；PRD FR-3/FR-19 的节点编号语义不变、下标订正 |
| C-2 | 「删 4 个死声明 external」隐含 4 项均在各 actor `external:` | actor 级 external 死声明实为 **3 项**，全部位于 `system-orchestrator.external`（L217-219：using-superpowers/writing-plans/verification-before-completion）；`systematic-debugging` 仅存在于顶层 `external-skills:` 纯文档块（L229，从未被解析，方案 §4.2 已认定），actor 级无此项 | 批次一清除对象 = `system-orchestrator.external` 三项；顶层 `external-skills:` 块本次**不动**（纯文档、不参与任何校验，整块处置留漂移治理项 D-2） |
| C-3 | 「record-idea 按 AGENTS.md:135 登记要求」 | record-idea 实为 **planning 域**已注册 skill（`skills/planning/record-idea/SKILL.md`，`skills/_index.yml` 在册，planning-agent owns、L153 某 actor 已 can-call）——skill 本体无需新建 | FR-16 仅为 `dev-agent.can-call` 追加引用（跨域调用登记），无新建成本 |

## 1. 架构概览

### 1.1 改动面与模块边界

本 CR 触及 tools 包七个既有模块，**新增 1 个 skill（coding-discipline），不新增 actor、不改依赖方向**（ARCHITECTURE.md §4：依赖只朝下，Skill 不绕过 crctl）：

```
skills/develop/coding-discipline/SKILL.md（新建）      ← 批次二：开发纪律兜底事实源（§1/§2/§3）
skills/develop/{implement-code,review-code,write-dev-tasks,approve-code}/SKILL.md  ← 批次一删改 + 批次二内化
skills/planning/write-dev-plan/SKILL.md                ← 批次二：引用 coding-discipline §2
skills/requirement/write-requirement-prd/SKILL.md      ← 批次二：summary 边界采纳
pipeline-templates/code-implementation.pipeline.json   ← 批次一节点5 prompt + 批次二 inputs(suggestion_policy) + 节点1/5/9 prompt
agent-skill-matrix.yml · agents/_index.yml             ← 批次一死声明/capabilities/known-gaps + 批次二 coding-discipline 归属/record-idea 登记
skills/_index.yml · AGENT-SKILL-MATRIX.md · dir-graph.yaml · ARCHITECTURE.md §8 · openwiki · AGENTS.md(tools) ← 台账与文档同步
```

硬不变量核对（ARCHITECTURE.md §5）：
- **crctl 单一状态写者**：本 CR 不触及 `crctl.mjs` 任何子命令与状态机——合规（PRD NFR-3/NFR-5）。
- **owns 唯一性**：`coding-discipline` 唯一 owns = `dev-agent`（既有 actor）——合规。
- **Skill 文档不得描述账本手工编辑**：全部改动为规则文本/配置数据，无账本手工编辑步骤——合规。
- **lint-prompts 平行治理**：新增 SKILL.md 正文以本包语汇书写、可被 lint-prompts 覆盖，不引用未注册技能名作执行前提——合规。

### 1.2 关键流程（改动后）

**流程 A（suggestion_policy 策略化分流，批次二核心行为变更）**：

```text
/coding 触发 → inputs.suggestion_policy（select，UI 预选中 strict）
 → … nodes[9] review-code：
    读 {{inputs.suggestion_policy}}
    ├─ strict（默认）：非阻塞发现一律进 suggestions；verdict 只判 CR 本身
    └─ lenient：非阻塞发现过三条升格判据（不扩 diff / 有明确改法 / 纯实现层）
         ├─ 三条全满足 → 升格进 blockers（同轮多条成批写入）→ verdict=block → 既有 reviewLoop replayNodes 回修
         └─ 任一不满足 → suggestions
    Step 6 输出补「Suggestions : {N} 条」与本轮 policy 留痕
 → nodes[11] approve-code：剩余 suggestions 可选经 record-idea 落 docs/ideas/（不设默认、不阻塞）
```

**流程 B（depends-on 拓扑排序，implement-code）**：

```text
nodes[5] implement-code Step 3：
 读 tasks/_index.yml 的 depends-on → 拓扑排序
 → 前置 TASK 未 done → 不启动本 TASK，节点输出注明被阻塞项与等待前置
 → 同层无依赖 TASK：未装 dispatching-parallel-agents → 串行；已装 → 可并发（独立域判据见 §4.3）
 → 回修模式（review_feedback 存在）→ 一律串行（先根因，§4.3）
```

## 2. 数据模型

本 CR 无数据库/持久化模型变更，以下为改动涉及的结构定义（均为既有 schema 内的增删）：

### 2.1 pipeline JSON 新增输入（inputs[]，code-implementation）

```json
{ "key": "suggestion_policy", "label": "改进建议处置策略", "type": "select",
  "options": ["strict", "lenient"], "required": false, "default": "strict",
  "description": "strict=不升格，所有非阻塞改进建议一律进 suggestions，评审只判 CR 本身的 pass/block（保守交付，默认）；lenient=按三条判据把本 CR 内该修的升格进 blockers，走 reviewLoop 在本 CR 内解决（清技术债场景）" }
```

追加于现有 4 个 inputs（cr_id / target_version / auto_push_after_task / review_llm）之后。形态对齐三个既有 select input（competitive-radar `focus_dimension` / market-to-plan `insight_type` / resume-cr `new_owner_role`，均为 required:false + default）。

### 2.2 agent-skill-matrix.yml 数据变更

```yaml
# 批次一（删除）
system-orchestrator.external: 移除 using-superpowers / writing-plans / verification-before-completion（L217-219，清后为 []）
known-gaps: 移除前两条（knowledge-agent-write-skills、customer-support-feedback-write，L233-238），保留 writeback-agent-entry

# 批次二（追加）
dev-agent.owns: += coding-discipline
quality-reviewer-agent.can-call: += coding-discipline
dev-agent.can-call: += record-idea
```

顶层 `external-skills:` 块（L222-230）本次不动（C-2 订正）。

### 2.3 agents/_index.yml capabilities 订正

```yaml
knowledge-agent:          # L175
  capabilities:
    supported: [design-doc-support]            # 移出 tech-note-write, insight-write
    pending: [tech-note-write, insight-write]  # pending 字段从 [] 启用
customer-support-agent:   # L220
  capabilities:
    supported: [product-doc-qa, tech-doc-qa, usage-guidance, implementation-explain]  # 移出 unresolved-feedback-record
    pending: [unresolved-feedback-record]
```

### 2.4 TASK frontmatter 删字段（write-dev-tasks）

模板（L58-59 区域）删除 `assignee: ""` 一行；`depends-on: []`（L58）保留（批次二拓扑排序的消费对象）。

### 2.5 review-code 输出模板扩展

Step 6 输出摘要追加两行：`Suggestions : {N} 条` 与 `Policy : {strict|lenient}`（本轮所用策略留痕，NFR-7）。

## 3. 接口契约

### 3.1 coding-discipline SKILL.md（新建，定稿骨架契约）

```markdown
---
name: coding-discipline
description: 开发纪律兜底事实源：极简阶梯选方案、2-5 分钟步骤粒度、先根因后动手与回归红绿验证。dev-agent 实现 TASK 与自修复时遵循。
---

§1 极简阶梯：需要存在吗（YAGNI）→ 代码库已有 → 标准库 → 平台原生 → 已装依赖 → 一行 → 最小可用实现。
   信任边界校验、错误处理、安全、可访问性不在精简范围内。
§2 执行步骤粒度：单 TASK 内部步骤按 2-5 分钟切分（写验证用例→跑到失败/明确当前状态→实现→复验→提交），
   每步含精确文件路径与验证步骤，禁止 TBD/占位符。TASK 本身粒度（1-3 天）由 write-dev-tasks 定义，不受本节约束。
§3 根因排查 + 回归验证：自修复模式（review_feedback 存在）动手前先定位根因（哪个 TASK/哪一行/什么假设不成立），
   同一根因下所有失败点一次修完；节点输出必须含 root-cause 字段（与 fixed-blockers 并列）。
   修复针对 bug 时回归测试先验红（临时还原修复前代码确认失败）再验绿（恢复修复确认通过），两次结果写入节点输出。

甲路线：目标运行时已装 ponytail / systematic-debugging / writing-plans 完整版时优先走其完整流程，
未装按本 skill 规则执行，二者等价；本 skill 是兜底事实源，不依赖跨运行时探测。
```

契约要点：全文本包语汇，不出现「必须遵循 external X」类悬空句式（批次一删除的失效模式不得复现）；external 技能名仅作来源标注/可选加速器。

### 3.2 review-code Step 1 无条件重验（定稿句式契约）

替换 L46 现状「若缺失，必须重新运行或要求补齐」为：**无条件重新执行** implement-code 节点输出中的验证命令（lint/test/build）；implement-code 自报结果仅作参考对照，不一致时以本轮重新执行结果为准并在 blockers 注明差异。「测试通过」必须是本轮重新执行的完整命令输出（0 failures），"看起来通过"或"之前跑过"不构成证据。甲路线补充句：已装 `verification-before-completion` 时可用其 Gate Function/Common Failures 表作执行细则参考，未装按本节最低要求执行——**本条不得弱化为"可选加速"**。

### 3.3 review-code Step 3 升格判据（lenient 生效，定稿契约）

```text
读取 {{inputs.suggestion_policy}}（缺省 strict）。lenient 模式下非阻塞发现同时满足三条才升格进 blockers：
① 改动不超出本 CR 已触碰的文件（不扩大 diff）；
② 有明确的"改成什么"（能写进 repair-instructions，不是"优化一下"）；
③ 不需要产品/架构决策（纯实现层）。
任一不满足 → suggestions。同一轮多条升格项必须写进同一批 blockers（成批升格，maxAttempts=3 硬上限）。
语义：blockers=本 CR 内要处理的（不论轻重）；suggestions=本 CR 内不处理的。
```

### 3.4 implement-code 降级路径 + 拓扑排序（定稿句式契约）

批次一（删 L75 TDD 引用后补降级，比照 brainstorming 样板）：

```text
目标运行时未提供 subagent-driven-development 时，按 TASK 顺序串行实现（等价于降级到
executing-plans 语义），在节点输出注明降级；两者均未提供时，按 coding-discipline
§2 的粒度自行拆解执行，无需额外声明。
```

批次二（Step 3 追加拓扑排序）：执行前读 `tasks/_index.yml` 的 `depends-on` 拓扑排序；前置 TASK 未 done 不得开始本 TASK，并在节点输出注明被阻塞 TASK 与等待的前置项。并发边界：同一 repo worktree 内会修改同一文件的多个 TASK 必须串行；跨 repo 的 TASK 因 worktree 隔离可并发；回修模式默认串行。已装 `dispatching-parallel-agents` 时同层无依赖 TASK 可并发派发（可选加速器，并发只影响耗时不影响产出）。

### 3.5 write-dev-tasks 接口契约小节（定稿骨架）

TASK 正文追加：

```markdown
### 接口契约
- 消费：本 TASK 使用哪些上游 TASK 产出的精确函数名/参数/返回类型
- 产出：本 TASK 暴露给下游 TASK 的精确签名
```

Step 4（生成 `tasks/_index.yml` 后）追加核对：所有 TASK 声明的接口签名一致性，命名对不上输出 WARN 并列出差异（不静默覆盖，由计划负责人决定，比照"估算交叉校验"写法）。「注意事项」的"不得模糊描述"替换为判据清单：禁止 TBD/"待定"；禁止"加适当的错误处理"类空描述；禁止"同 TASK-XX"引用而不给实际签名；禁止引用未在任何 TASK 定义的类型/函数。

### 3.6 approve-code suggestions 承接（定稿句式契约）

追加：剩余 `suggestions` 可选经 `record-idea`（planning 域 skill）转入 `docs/ideas/`——必须在 approve-code 期做（CR worktree 内随分支合并进 trunk；feature-writeback 硬边界只写 specs/delivery）；不设默认、不阻塞本 CR；不转则仅留档 review-annotations，无损失。

### 3.7 AGENTS.md（tools 仓）第 56 条修订

```markdown
2. 外部同名技能由目标运行时按需提供；phase0 tools 以自有规则（如 coding-discipline）为兜底事实源，
   外部技能作可选加速器——已装则优先走其完整流程，未装按本包规则执行，二者等价、不要求探测。
```

第 160 条（禁止把外部方法论 Skill 打包进 phase0 tools）保持不变——coding-discipline 是本包语汇重写的自有规则，非复制上游 SKILL.md。

## 4. 关键算法与流程

### 4.1 批次一执行序列（零行为变更，纯删除/对齐）

```text
1. agent-skill-matrix.yml：system-orchestrator.external 删 3 项（C-2）；known-gaps 删前两条
2. agents/_index.yml：三项 capabilities supported→pending（§2.3）
3. implement-code/SKILL.md：删 L75 TDD 行，补 §3.4 降级路径文本
4. code-implementation.pipeline.json：nodes[5] prompt 同步删 TDD 表述、补降级表述（C-1 下标）
5. write-dev-tasks/SKILL.md：删 L59 assignee 行
6. AGENT-SKILL-MATRIX.md + openwiki/architecture/agent-skill-matrix.md：forbidden 性质说明
   （声明性边界，执行靠 agent 自觉 + protectedPaths 文件守卫，不存在调用级拦截；不加运行时钩子）
↳ 验证：check-skill-matrix + check-agents-contract + lint-prompts --mode enforce 全绿；
  状态机回归确认行为零变化（死声明删除仅影响矩阵报告面）
```

### 4.2 批次二执行序列（同批原子性，FR-22）

```text
commit（同一批）：
  a. 新建 skills/develop/coding-discipline/SKILL.md（§3.1）
  b. skills/_index.yml 登记 active
  c. agent-skill-matrix.yml：dev-agent.owns += coding-discipline；quality-reviewer-agent.can-call += coding-discipline；dev-agent.can-call += record-idea
  d. AGENT-SKILL-MATRIX.md 主责矩阵同步 + dir-graph.yaml 登记路径 + ARCHITECTURE.md §8 代码地图登记
  e. implement-code Step 3 引用 §1+§2、自修复分支引用 §3、追加拓扑排序（§3.4）
  f. write-dev-plan 引用 §2
  g. review-code：第五维度（FR-11 判据表）+ Step 1 无条件重验（§3.2）+ Step 3 策略化分流（§3.3）+ Step 6 输出补两行（§2.5）
  h. approve-code 追加 suggestions 承接（§3.6）
  i. write-dev-tasks 接口契约三处（§3.5）
  j. code-implementation.pipeline.json：inputs += suggestion_policy（§2.1）；nodes[1] prompt 同步接口契约；nodes[5] prompt 同步拓扑排序；nodes[9] prompt 同步第五维度+无条件重验+升格判据（C-1 下标）
  k. write-requirement-prd 追加 summary 边界采纳行
  l. AGENTS.md(tools) 第 56 条修订（§3.7）+ openwiki 页面同步
↳ 原子性依据：a~f 拆开则 check-skill-matrix 报「active skill 无 owns」或孤儿引用；
  g~j 的 prompt 引用 coding-discipline/suggestion_policy 与 a/§2.1 同批才不产生悬空引用（批次一删除的失效模式不得复现）
```

### 4.3 并发独立域判据（implement-code 拓扑排序的并发边界）

```text
可并发 ⇔ 不同拓扑层无依赖 且 独立域：
  独立域 = 跨 repo（worktree 天然隔离），或同 repo 但不触碰同一文件
不可并发：同 repo 同文件多 TASK；回修模式（review_feedback 存在）——多 blocker 常同源，先根因（§3.1 §3）
并发派发仅在已装 dispatching-parallel-agents 时启用，子代理返回后核对改动冲突并重跑全量验证
```

### 4.4 提交批次编排与基线协调（NFR-10）

```text
tools 仓 commit 1（批次一，§4.1 全量）→ 三件套验证 + 行为回归
tools 仓 commit 2（批次二，§4.2 全量，同批原子）→ 三件套验证 + 1 个真实 CR 回归
基线协调：tools 仓工作区现有大量与本 CR 无关的删除态文件（.qoder/repowiki/、README.pdf、
assets/readme-illustrations/ 等，属用户另行变更）——两 commit 仅 add 本 CR 文件清单，
严禁 git add -A；实施期若发现与本 CR 同文件的外部未提交修改，按 hunk 拆分并与用户确认归属
```

## 5. 技术选型与替代方案

| 决策 | 选择 | 否决的替代 | 理由 |
|---|---|---|---|
| 开发纪律承载 | 新建本包自有 `coding-discipline` skill | 声明 external（ponytail 等）运行时引用 | external 未安装即静默蒸发——正是本 CR 要修的失效模式（implement-code L75 TDD 悬空先例）；内化 30 行文本成本远低于新增跨运行时探测设施 |
| 外部技能定位 | 甲路线可选加速器（措辞级） | 强制前置 / 完全排斥 | 已装完整技能者走完整流程不吃亏，未装者有兜底；不要求探测机制 |
| suggestions 分流控制权 | pipeline 触发参数 suggestion_policy | 评审期人工逐条选 / 审批期处置 | skill 节点中途无可插人工暂停钩子，逐条人选要改 canonical + 再烧一轮 maxAttempts=3；审批期改代码则评审证据（针对当时那份代码）失效——任何"本 CR 内消费"路径最终都回到 reviewLoop 重审，分流点只能前移评审期（方案 §4.9-③ 推理） |
| suggestion_policy 默认值 | strict（不升格） | lenient（积极清债） | 保守交付优先：默认不因改进建议触发额外回修轮次；清技术债是按 CR 显式开启的选项；与 review_llm「一次选择全程复用」同构，零新增节点 |
| 剩余 suggestions 落点 | approve-code 期经 record-idea 落 docs/ideas/ | writeback 期写 delivery/ / 仅留档 | feature-writeback 硬边界只写 specs/delivery；delivery/ 写进去仍无人读（换个目录继续只写不读）；docs/ideas/ 有完整下游通路（ideas→认领→requirement 注册 CR） |
| depends-on 排序执行层 | prompt 层（implement-code 自觉） | crctl task done 加依赖守卫 | 守卫涉及 crctl 新增校验与测试向量，属独立 CR（PRD D-5）；prompt 层先行闭环，守卫登记后续项 |
| capabilities 处置 | Level A 数据订正（supported→pending） | Level C 真闭环（capability→skill[] 映射 + 校验不变式） | Level C 约 40 条目且牵出新 pending 项，自成 CR（PRD D-3）；先消除"声明与事实相反"的即时误导 |
| 顶层 external-skills 块 | 本次不动 | 整块删除/改造 | 从未被解析的纯文档（方案 §4.2），删与不删均无运行时影响；整块处置并入 D-2 漂移治理项，避免本 CR 扩面（C-2 订正） |

## 6. FR 到技术实现映射

| FR | 技术实现 | 文件 |
|---|---|---|
| FR-1 | system-orchestrator.external 删 3 项（C-2 订正：actor 级实为 3 项；systematic-debugging 仅在顶层纯文档块，不动） | `agent-skill-matrix.yml` |
| FR-2 | 删 L75 TDD 行 + 补 §3.4 降级路径 | `skills/develop/implement-code/SKILL.md` |
| FR-3 | nodes[5] prompt 同步（C-1 订正：方案"节点 6"= 现 nodes[5]） | `pipeline-templates/code-implementation.pipeline.json` |
| FR-4 | capabilities 订正（§2.3）+ known-gaps 删前两条（§2.2） | `agents/_index.yml` + `agent-skill-matrix.yml` |
| FR-5 | forbidden 性质说明（声明性边界、无调用级拦截） | `AGENT-SKILL-MATRIX.md` + `openwiki/architecture/agent-skill-matrix.md` |
| FR-6 | 删 L59 assignee 行 | `skills/develop/write-dev-tasks/SKILL.md` |
| FR-7 | 新建 SKILL.md（§3.1 定稿骨架） | `skills/develop/coding-discipline/SKILL.md` |
| FR-8 | 登记 active + owns/can-call + 矩阵/dir-graph/ARCHITECTURE §8（§2.2、§4.2 b~d） | `skills/_index.yml` 等 5 文件 |
| FR-9 | Step 3 引用 §1+§2、自修复引用 §3、拓扑排序（§3.4、§4.3） | `skills/develop/implement-code/SKILL.md` |
| FR-10 | 引用 coding-discipline §2 | `skills/planning/write-dev-plan/SKILL.md` |
| FR-11 | Step 3 维度表追加第五维度（判据：破 WCAG AA 升 blocker、触发 `*.tsx|*.vue|*.css|*.html`；dimensions 自由映射加键零成本） | `skills/develop/review-code/SKILL.md` |
| FR-12 | Step 1 无条件重验（§3.2，替换 L46 句式） | 同上 |
| FR-13 | inputs += suggestion_policy（§2.1，形态对齐 3 个既有 select） | `pipeline-templates/code-implementation.pipeline.json` |
| FR-14 | Step 3 策略化分流（§3.3）+ Step 6 输出补两行（§2.5） | `skills/develop/review-code/SKILL.md` |
| FR-15 | suggestions 承接条款（§3.6） | `skills/develop/approve-code/SKILL.md` |
| FR-16 | dev-agent.can-call += record-idea（C-3 订正：skill 本体已存在于 planning 域，仅登记跨域调用） | `agent-skill-matrix.yml` |
| FR-17 | 接口契约小节 + Step 4 签名核对 + 占位符判据（§3.5） | `skills/develop/write-dev-tasks/SKILL.md` |
| FR-18 | 追加 summary 已确认边界优先采纳行 | `skills/requirement/write-requirement-prd/SKILL.md` |
| FR-19 | nodes[1]/[5]/[9] prompt 同步（C-1 订正下标；方案"节点 2/6/9"→ 现 1/5/9，review-code 恰未漂移） | `pipeline-templates/code-implementation.pipeline.json` |
| FR-20 | 第 56 条甲路线修订（§3.7）；第 160 条不动 | tools 仓 `AGENTS.md` |
| FR-21 | forbidden 性质 + 主责矩阵页面同步（实施期按 openwiki 实际页面清单展开） | `openwiki/` |
| FR-22 | 批次一/二分开、批次二内部同批（§4.1/§4.2 编排） | 提交约束 |
| FR-23 | 每批三件套 + 1 个真实 CR 回归（crctl next/status/gate 无越级） | 验证关卡 |
| FR-24 | commit message 注明方案 v2.6 + CR-2026-024 溯源；全改动无本机绝对路径 | 提交规范 |

## 7. 安全与性能考量

- **行为兼容**：批次一零运行时行为变更（纯删除/数据对齐）；批次二中 strict 是默认策略——默认路径下评审行为与改动前一致（非阻塞发现仍进 suggestions、verdict 判据不变），lenient 为显式开启的增量路径。
- **口径留痕**：lenient 模式 blockers 语义扩大，review-code 输出必须注明 policy（§2.5），避免跨模式数据误比（NFR-7）。
- **悬空引用防线**：批次二所有 prompt/SKILL 引用（coding-discipline / suggestion_policy / record-idea）与被引用对象同批落盘——批次一修复的"声明蒸发"失效模式不得在本 CR 自身复现（§4.2 原子性依据）。
- **回滚**：批次一/二为两个独立 commit，可分别 revert；批次二 revert 后 suggestion_policy input 与 prompt 引用同批消失，无残留悬空（因同批原子）。
- **边界条件**：suggestion_policy 缺省即 strict（required:false + default），旧触发方式零感知；拓扑排序遇 depends-on 环（理论不应出现，validate-doc 已校验指向有效）时 implement-code 输出 WARN 并退回索引顺序串行，不静默吞环。
- **基线隔离**：tools 仓大量删除态外部文件（.qoder/repowiki 等）严禁混入本 CR commit（§4.4）。

## 8. Prompt 采纳影响

本 CR diff **不触及** `crctl.mjs` dispatch 分支与 `rules.json#protectedPaths.deny`（无 crctl 命令面新增/变更、无 guard deny 面变更）——按 SDD 条件性小节约定，本节无应采纳清单，留此说明备查。

## 9. 风险与残余

| 风险 | 缓解 |
|---|---|
| 方案文档节点编号陈旧（C-1）导致实施改错节点 | 本 SDD §0 已订正为实测下标（1/5/9）；实施期以 ref 名（write-dev-tasks/implement-code/review-code）为结构锚点，下标二次核对 |
| 死声明分布与方案表述不符（C-2）导致多删/漏删 | 清除对象锁定 system-orchestrator.external 三项；顶层纯文档块不动；实施后 grep 四项名称确认 actor 级零残留、顶层块原样 |
| 批次二同批原子被拆提交触发三件套自阻断 | §4.2 清单作为任务拆分边界——a~l 属同一 TASK 原子单元，禁止跨 commit 拆分 |
| tools 仓删除态外部文件混提 | §4.4：仅 add 本 CR 文件清单，禁 git add -A；提交前 git status --short 核对 |
| openwiki 页面清单未逐一核实（FR-21 较笼统） | 实施期第一步 grep openwiki/ 对 forbidden/主责矩阵的引用点展开清单；评审建议（需求期 suggestion 1）在此承接 |
| depends-on 排序仅 prompt 层、无可执行守卫 | 已登记后续项（crctl task done 依赖守卫，PRD D-5）；本 CR 内 implement-code 节点输出注明被阻塞项提供留痕 |
| capabilities Level A 订正后仍可能再次漂移 | Level C 真闭环已列范围排除与后续项（PRD D-3）；本次先消除即时误导 |
