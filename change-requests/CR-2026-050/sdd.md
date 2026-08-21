---
id: CR-2026-050-sdd
type: SDD
cr-ref: CR-2026-050
title: Pipeline 流程优化 — 职责边界与契约漂移修复 技术设计
status: draft
created: 2026-08-21T10:48:42+08:00
updated: 2026-08-21T11:12:30+08:00
---

# 1. 架构概览

本 SDD 落地 PRD（change-requests/CR-2026-050/prd.md）13 条 FR 的技术实现。改动本质是**文本契约收敛与最小输入契约扩展**：不新增事务框架、状态投影、通用 Runner、crctl 子命令或账本结构；净效果以删除重复合同为主，辅以少量既有 Skill 输入字段的显式化。

## 1.1 变更对象总览

| 仓库 | 变更对象 | 变更性质 |
|---|---|---|
| tools | `pipeline-templates/*.pipeline.json`（8 条） | prompt 收敛：P0 契约修复 + P1/P2 重复删除；机器字段（node/ref/reviewLoop/replayNodes/passCondition/onFail/timeout）不动 |
| tools | `skills/planning/extract-market-insight/SKILL.md` | FR-03.2 最小输入扩展（`mode=brief`、`raw_insight_path`） |
| tools | `skills/competitive/report-to-planning-suggestion/SKILL.md` | FR-04.3 输入扩展（`reportDraft`）+ 同步修订前置条件、错误处理表首行（reportPath 缺失即中止）、读写清单；保留「前端按 reportPath 触发」入口契约 |
| tools | `skills/develop/write-tech-design/SKILL.md` | **FR-07.1/FR-07.2 的真实漂移落点**：删除 Step 1 的 `.rayai-worktrees/{repo.id}/requirement/{cr_id}` 路径约定，改消费 `operational_workspace`/`resources[].worktreePath`；把「ARCHITECTURE.md 与 sdd.md 同一 commit 提交」改为「各仓在所属 worktreePath 分别提交，架构审批后由同一批 checkpoint 纳入」；FR-08.1~3 三项能力收窄；提交前缀对齐（§5 DD-7） |
| tools | `skills/develop/review-tech-design/SKILL.md` | FR-06.3/FR-08.4 评审维度扩展 |
| tools | `skills/cr/cr-show/SKILL.md` | FR-10.1 输出契约补「最近三次 checkpoint」展示项 |
| tools | `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | FR-12/AC-12 扩展确定性断言 + 按 §5 DD-4 处置既有冲突断言（不新建测试框架） |
| tools | `skills/develop/write-dev-plan/SKILL.md`、`skills/planning/write-roadmap/SKILL.md` | DD-7 同类提交前缀漂移（`feat(` / `[planning] ` 均不在白名单）一并对齐 |
| multica | `server/internal/governance/gate_nodes_gen.go` | **再生**（architecture-design pipeline prompt 变更后，嵌入 registry + digest 必须同步，§4.2） |
| multica | `CUSTOM.md` | 登记再生变更（台账纪律，AGENTS.md 第 10 条） |
| ai-first-platform-docs | `change-requests/CR-2026-050/*` | 本 SDD 及后续 plan/tasks/评审证据 |

**不修改**：`crctl.mjs` dispatch 面、`gates.json`、`dir-graph.yaml#change-request-track.state_machine`、`controlled-shell/rules.json#protectedPaths`、审批 grant、reviewLoop 业务语义、traceability evidence 结构、pipeline 节点数量与 UUID（competitive-radar node-5 无需加节点，§5 DD-2）。

**`tools/ARCHITECTURE.md` 不修订**：本 CR 无 skills 顶层分组变化、无 Pipeline 结构（节点数/依赖方向）变化、无 crctl 写入子命令变化、无状态机口径变化；DD-1~DD-3 是本 CR 的实现选择而非仓库级长期否决项，按该文档「维护规则」不触发修订条件。

## 1.2 模块边界（继承 PRD §1）

| 模块 | 本 CR 之后的职责 |
|---|---|
| Pipeline JSON | 节点顺序、ref、输入传递、reviewLoop、失败中止；每节点 prompt 最多五要素（调哪个 Skill、传什么、依赖哪些前序输出、消费哪些结果、失败去哪） |
| Skill | 业务判断、编排步骤、输入输出、失败语义 |
| crctl | 状态、门禁、账本、CAS、审批、审计（本 CR 零改动） |
| 版本化脚本 | 确定性文档转换（本 CR 零改动） |
| multica Runner | 消费嵌入 registry（gate_nodes_gen.go）执行 architecture Core（本 CR 只再生其输入，不改逻辑） |

## 1.3 依赖图

```text
tools/pipeline-templates/architecture-design.pipeline.json
   ├─(emit-registry.mjs --pipeline architecture-design)→ registry JSON + digest
   │        └─(multica gen/generate-gate-nodes.mjs)→ gate_nodes_gen.go（嵌入 + digest 校验）
   └─(Agent 执行其余 7 条 pipeline prompt)→ skills/{组}/{name}/SKILL.md → crctl（只读+受控写入）
tools/skills/**/SKILL.md —— 被 pipeline prompt 引用，输入契约以 SKILL.md 为唯一事实源
multica/server/internal/governance/runner.go —— 只消费 gate_nodes_gen.go 常量，零逻辑改动
```

## 1.4 关键流程

1. **两阶段实施**（AC-14）：阶段一先完成 FR-01～FR-05 且对应契约断言通过（§4.4 的 gate 清单），再进入阶段二按 `architecture-design → requirement-authoring → code-implementation → resume-cr → feature-writeback → 规划类` 顺序完成 FR-06～FR-13。AC-14 的验收证据形态 = TASK 顺序 + 各阶段 checkpoint/commit 时序（阶段一 gate 通过的 checkpoint 早于阶段二首个实现 commit）。
2. **competitive-radar 闭环**（FR-04）：node-2 草稿（confirmed=false）→ node-3 消费 reportDraft → node-4 人工确认 → node-5 confirmed=true 落盘正式报告再落规划条目（§4.1）。
3. **registry 再生链**（FR-07/FR-12 的隐式依赖）：architecture-design.pipeline.json 任何变更 → 重跑 multica 生成器 → 提交 gate_nodes_gen.go（§4.2）。

# 2. 数据模型

本 CR **不新增数据库表、迁移、账本文件或 crctl 字段**。仅有的「数据结构」变化是两处既有 Skill 的输入契约显式化：

## 2.1 reportDraft 最小结构（FR-04.3）

`report-to-planning-suggestion` 新增可选输入，与 `reportPath` 二选一：

```yaml
reportDraft:            # node-2 write-competitive-report(confirmed=false) 的结构化草稿
  body: <草稿正文 markdown>
  competitorId: <competitor-id>
  reportDate: YYYY-MM-DD
  sourceNodeId: <node-2 UUID>
  sourceRef: write-competitive-report
```

规则：`reportPath` 与 `reportDraft` 同时存在时优先 `reportPath`；草稿模式只消费输入生成规划建议，不落盘竞品报告。

## 2.2 extract-market-insight 简报模式（FR-03.2）

新增两个可选输入：

```yaml
mode: insight | brief        # 可选，默认 insight（缺省行为与现状完全一致）
raw_insight_path: <简报原始洞察文件路径>   # mode=brief 时必填
```

`mode=brief` 复用同一 Skill 现有 Step 3.5「简报附加区块」，该步骤的触发条件由 `mode` 驱动（不再靠调用方措辞推断）；`mode=brief` 且 `raw_insight_path` 缺失或不可读时按该 Skill 现有错误码风格硬失败（`INSIGHT_SOURCE_EMPTY` 同族，不静默降级为 insight 模式）。Pipeline 只传这两个业务参数，brief 正文/路径/index 状态仍由 Skill 负责。废除 Pipeline 中未声明的 `source` 伪造参数。

## 2.3 上游上下文输入的产出方（BLK-1 修复）

`updates-block` 与 `product-snapshot` 不是本 CR 新增结构，而是既有 Skill 的既有输出，本 CR 只固定「谁产出、谁消费」：

| 输入 | 结构与产出方 | 消费方 |
|---|---|---|
| `updates-block` | `fetch-competitor-updates` 输出的 competitor 条目（含 `updates[]`/`source-urls`） | `write-competitive-report`（必填） |
| `product-snapshot` | `gather-product-context` 输出的 Markdown 快照或其结构化摘要 | `write-competitive-report`（必填） |
| `context` | `gather-product-context` 输出的产品上下文快照（Markdown） | `planning-draft`（必填） |

三者的取得方式见 §4.3（在不增节点前提下由节点 prompt 顺序调用既有 Skill）。

## 2.4 保持不动的机器字段

- reviewLoop：`repairNodeId/repairRef/feedbackInput/attemptInput/replayPolicy/replayNodes/passCondition/onBlock/maxAttempts`（原样保留，不搬回 Skill 文本）；
- execution_context：`cr_id/owners/knowledge_base_worktree/operational_workspace`（传递语义不变）；
- node UUID 与 `_index.yml#nodes` 计数（本 CR 不增删节点）。

# 3. 接口契约

## 3.0 五要素之外的机器契约保留项（BLK-2 修复）

以下内容**不属于**被收敛的「重复算法」，收敛时必须逐字保留，且已有确定性断言守护：

| 保留项 | 适用范围 | 现有断言 |
|---|---|---|
| `crctl workspace inspect` 入口校验（全部 `resources[].classification=healthy`、消费 `operationalWorkspace`、非 healthy 指向 `/resume`） | architecture-design **每个**节点（CR-2026-045 每节点独立 inspect），code-implementation 首节点 | `pipeline-structure.test.mjs:165-183` |
| 不依赖 `node-1.md`（architecture-design 后续节点） | architecture-design nodes[1..] | 同上 `:179` |
| `execution_context.operational_workspace` 消费 | code-implementation 后续节点 | 同上 `:176-183` |
| `execution_context.resources[].worktreePath` 且不得出现 `.rayai-worktrees/` 拼接 | code-implementation `implement-code` | 同上 `:185-187` |
| 代码审批节点（`…0010`）approvalPrompt 含「评审后 checkpoint phase=complete」前提 | code-implementation | 同上 `:114-119` |

## 3.1 收敛后节点 prompt 五要素模板

```text
调用 {skill-name}：
- 业务输入：{…}（参数名以该 Skill 的 SKILL.md 为唯一事实源）
- 前序依赖：{node-N.md 的结构化输出 / execution_context}
消费 {结构化结果字段}；失败按 {abort|skip|route} 处理。
```

反模式（一律删除并加负向测试断言）：评审维度正文、临时 payload 与 review-record 调用、`crctl` 命令细节、TTY/grant/CAS 流程、账本与 annotation 写入、Git 命令序列、章节/路径/索引规则、写死下一 pipeline 名。

## 3.2 逐 Pipeline 关键节点契约

| Pipeline | 节点 | 收敛后输入 | 消费结果 |
|---|---|---|---|
| architecture-design | write-tech-design | cr_id、tech_context、operational_workspace、resources、review_feedback、self_repair_attempt | execution_context（SDD 路径、FR 覆盖率） |
| architecture-design | review-tech-design | cr_id、workspace、review_feedback、attempt | verdict/blockers/repair-target/current-attempt |
| architecture-design | human approval | cr_id + sdd.yml verdict | approve/reject 结构化决定（不改 annotation） |
| architecture-design | approve-tech-design | cr_id（+ workspace inspect 入口，见 §3.0）；**approver 不由 Pipeline 取值** | 审批记录、当前 status |
| architecture-design | push-progress | cr_id、message=架构设计已审批（+ workspace inspect 入口） | batchId、repositories、phase（保留「阶段终点/phase=complete/失败只重跑」语义） |
| requirement-authoring | register/PRD/review/approve | 同 skill 输入表，删除命令/路径/章节副本 | execution_context / verdict / 审批记录 |
| code-implementation | plan/TASK/review-dev-plan/approve-dev-start/implement/test-report/review-code/freshness/approve-code | 见 PRD FR-06/FR-07 | 结构化结果 + reviewLoop 路由 |
| product-planning | feedback/market/current-product | topic、skip 标志 | 结构化分析结果 |
| product-planning | node-3 write-competitive-report | 顺序调用链（§4.3）：`fetch-competitor-updates` → `gather-product-context` → `write-competitive-report(updates-block, product-snapshot, confirmed=false)` | 草稿报告（本 pipeline 的人工节点在 node-7，故 node-3 只出草稿不落盘） |
| product-planning | write-planning-report | prev_outputs、review_feedback、self_repair_attempt、topic、target_version | 报告路径 + reviewLoop 消费字段 |
| product-planning | review-planning-report | 报告路径、reviewer、topic、target_version、feedback、attempt | approved/blockers/repair-target/current-attempt |
| product-planning | node-7 human approval | 结构化 approve/reject+reason | 决定（不改报告文件；驳回中止正向链） |
| product-planning | node-8 write-roadmap | topic、target_version、planning_report_path | roadmap 更新结果（不写规划报告 `_index.yml`） |
| market-to-plan | extract-market-insight（node-1/2） | insight_source、insight_type、target_version；node-2 加 mode=brief、raw_insight_path | 洞察/简报结构化结果 |
| market-to-plan | node-3 planning-draft | 顺序调用链（§4.3）：`gather-product-context` → `planning-draft(context=快照, intent=从简报提炼的一句话意图, target_version)` | 草稿路径 |
| market-to-plan | write-planning-entry | source、target_version | 规划条目（不碰 market-insights index） |
| competitive-radar | node-1 | competitor-id/competitor-ids[]、lookback-days（Pipeline 只做参数名映射；`slug → competitor-id` 的索引解析归 `fetch-competitor-updates`，Pipeline 不读竞品索引） | updates 结构化输出 |
| competitive-radar | node-2 | 顺序调用链（§4.3）：`gather-product-context` → `write-competitive-report(updates-block, product-snapshot, confirmed=false)` | 草稿（不落盘） |
| competitive-radar | node-3 | reportDraft（或 reportPath） | 规划建议 |
| competitive-radar | node-5 | updates-block、product-snapshot、confirmed=true → write-competitive-report；再 write-planning-entry(source=node-3 输出) | 正式报告 + 规划条目 |
| feature-writeback | node-1 | cr_id（删除 status=code-approved 预检文本） | merge 事务结果 |
| resume-cr | node-3 | cr-id、section=all（调用 cr-show） | cr-show 结构化详情（含最近三次 checkpoint，由 cr-show 输出契约承载） |

**approve-\* 节点的 approver 取值（统一规则）**：Pipeline 只传 `cr_id`，**不传也不拼 approver**；owners 由 `approve-*` Skill 经 crctl 读取（`crctl approve` 的 approver 缺省即 `cr.md owners.{角色}.id`）。这样既满足 PRD FR-05.2「不遗漏 CR-ID」，又不与 architecture-design「后续节点不依赖 node-1.md」的既有断言冲突（§3.0），也避免 Pipeline 复制 owners 解析逻辑。

## 3.3 不新增的接口

- 不新增 crctl 子命令/参数（FR-13）；
- 不新增 Skill；`skills/_index.yml` 与 `agent-skill-matrix.yml` 无新增 ref，预期零改动（实施期验证 FR-13.5）；
- 不修改 controlled-shell `rules.json`（deny/白名单零改动）。

# 4. 关键算法与流程

本 CR 无新增算法；三个关键流程如下。

## 4.1 competitive-radar 草稿/落盘闭环

```text
node-1 fetch-competitor-updates → updates-block（结构化）
node-2 write-competitive-report(confirmed=false) → 仅生成草稿，不落盘
node-3 report-to-planning-suggestion(reportDraft) → 规划建议（无合法 reportPath 时不再报错）
node-4 human_approval 人工确认
node-5 顺序调用：
     ① write-competitive-report(confirmed=true, updates-block, product-snapshot) → 正式报告落盘 + reports index
     ② write-planning-entry(source=node-3 输出) → 规划条目落盘
```

实现要点：node-5 的 prompt 按顺序描述两次 Skill 调用与各自的输入传递（含 node-2 已取得的 `updates-block`/`product-snapshot`）。competitive-radar 无 server Runner（multica Runner 仅 architecture Core，已核实 `runner.go` 只有 `StartArchitecture`），由 Agent 依 prompt 执行，单节点顺序调用两个 Skill 不需要运行时改动；因此不触发 FR-04.4 的「运行时显式支持」分支（该分支为条件性兜底，本 CR 不落地）。

## 4.2 multica registry 再生链（architecture-design 变更的硬依赖）

已核实的事实：

1. `multica/server/internal/governance/gate_nodes_gen.go` 嵌入 `ArchitectureCoreRegistryJSON`（architecture-design 全部 5 节点含 **prompt 全文**、permissions、reviewLoop 契约）与 `ArchitectureCoreRegistryDigest`；
2. `runner.go#parseCoreRegistry` 对 digest 与 5 节点结构 fail-closed；
3. 生成链：`tools/pipeline-templates/emit-registry.mjs --pipeline architecture-design` → registry JSON + `sha256:` digest → `multica gen/generate-gate-nodes.mjs` → 重写 `gate_nodes_gen.go`；
4. `--check` 模式由 multica CI 守卫漂移（比对时剥离 `// Source: tools@<sha>` 行，SHA 变化本身不误报）。
5. **prompt token 硬约束**：`emit-registry.mjs` 的 `ALLOWED` 白名单只放行 `{{inputs.cr_id}}` 与 `{{inputs.tech_context}}`，architecture prompt 重写若引入任何新 `{{…}}` token 会 `REGISTRY_PROMPT_TOKEN_INVALID` 硬失败——这是 architecture-design 收敛的实施前置约束。

结论：**修改 architecture-design.pipeline.json 的 prompt（本 CR FR-01/05/06/07/08/09 必改）后，必须在 multica worktree 重跑生成器并提交 gate_nodes_gen.go**，否则服务器端 Runner 执行的是旧 prompt——FR-01 的受保护路径修复在运行时不会生效，且 CI 漂移检查失败。本 CR 不改 runner 逻辑与 registry schema，只更新其生成产物。

实施顺序约束：architecture-design 的 pipeline 修改与 gate_nodes_gen.go 再生同批完成（阶段二第 1 项内闭环）；再跑 multica 既有 governance 测试（`runner_contract_test.go`、`gate_nodes_gen --check`）。

## 4.3 上游上下文取得：单节点顺序调用既有 Skill（BLK-1 修复）

三条规划 Pipeline 都缺少 `fetch-competitor-updates` / `gather-product-context` 节点，而下游 Skill 的必填输入正来自它们；PRD FR-12.4 又要求节点数不变。采用与 §4.1/DD-2 相同的模式：**在既有节点的 prompt 内按顺序调用既有 Skill**，不新增节点、不新增 Skill、不改运行时（三条规划 Pipeline 均无 server Runner）。

```text
product-planning node-3：
  fetch-competitor-updates(竞品范围, lookback) → updates-block
  gather-product-context()                    → product-snapshot
  write-competitive-report(updates-block, product-snapshot, confirmed=false)
  # confirmed 固定 false：本 pipeline 的人工节点在 node-7，node-3 阶段无人工确认，按 Skill 两阶段协议只出草稿

competitive-radar node-2：
  gather-product-context() → product-snapshot
  write-competitive-report(updates-block=node-1 输出, product-snapshot, confirmed=false)

market-to-plan node-3：
  gather-product-context() → context
  planning-draft(context, intent=从洞察简报提炼的一句话规划意图, target_version)
```

各 Skill 的落盘、索引与业务算法仍归其自身；Pipeline 只声明调用顺序与参数传递（仍在五要素范围内："调用哪些 Skill、传什么、消费什么"）。

## 4.4 两阶段实施 gate（AC-14）

阶段一完成判定（全部满足才进入阶段二）：

- AC-01（受保护账本指引为 0）、AC-02、AC-03、AC-04、AC-05（approve 节点契约）对应断言通过；
- 8 条 JSON 可解析、`lint-prompts.mjs` 通过、pipeline-structure 测试通过；
- product-planning / market-to-plan / competitive-radar 三条规划的必填输入映射齐全。

## 4.5 reviewLoop 回修语义（不变）

本 CR 不修改任何 reviewLoop 的 `replayPolicy/replayNodes/maxAttempts/passCondition`；review-tech-design 的回修语义（block → write-tech-design 回修 → 重审）原样保留。PRD FR-08.4 的评审维度扩展只进入 `review-tech-design` SKILL.md 的评审维度正文，不新增评审节点。

# 5. 技术选型与替代方案

- **DD-1 修改面 = prompt 文本 + Skill 最小输入扩展**（不写运行时拦截器）。替代：在 runner/gitguard 加校验拦截越权提示——否决，多一份可执行事实源且触及受控面；现状问题全部可通过收敛文本消除。
- **DD-2 node-5 顺序双 Skill 用 prompt 表达**（不新增节点、不改 multica runner）。替代：拆分两个节点或扩展 runner 支持多 ref——否决，competitive-radar 无 server runner，新增节点会连锁改动 `_index.yml` 与 gate-nodes 生成器；prompt 顺序调用已是 Agent 执行的现有能力。
- **DD-3 multica gate_nodes_gen.go 再生为必经路径**（FR-07 的隐式技术依赖）。替代：改 runner 使其运行时读 tools 文件——否决，破坏「构建 multica 无需 tools checkout」的既有设计（生成器头注释明示），且 digest fail-closed 是安全特性。
- **DD-4 自检防线 = 复用并扩展 `pipeline-structure.test.mjs`**（node --test，零依赖）。替代：新建语义解释器/通用检查框架——否决（PRD FR-13.1 明确禁止）。扩展内容：requirement-authoring 关键顺序与 auto_push 分支断言、code-implementation 两条关键顺序与 reviewLoop replayNodes 断言、P0/P1 收敛的负向文本断言（受保护账本指引/评审维度正文/crctl 命令细节/写死 next 等）。

  **既有断言处置清单（BLK-2 修复，实施必读）**：

  | 位置 | 现有断言 | 处置 | 理由 |
  |---|---|---|---|
  | `:149` | architecture push 节点 prompt 必须匹配 `/crctl checkpoint \{\{inputs\.cr_id\}\} --message/` | **修订**为「prompt 不含 `crctl checkpoint` 命令字面量，且含 `phase` 消费与阶段终点语义」 | 与 FR-07.3 直接互斥；CR-2026-044 FR-07 要保的是「架构终点 checkpoint 不可跳过、失败只重跑」，该语义改由 `onFail=abort` + phase 断言承载，不回退 |
  | `:141-153` 其余项（唯一 push 节点、`onFail=abort`、无 skip 分支、无未解析 workspace 占位符、5 节点） | — | **逐字保留** | 均为本 CR 明确不改的语义 |
  | `:165-183` | 首节点 inspect/healthy/resume/execution_context；architecture 后续节点必须含 `crctl workspace inspect` 且不得含 `node-1.md`；code 后续节点含 `execution_context.operational_workspace` | **逐字保留** | CR-2026-045 设计；§3.0 已把它列为五要素之外的保留项 |
  | `:185-187` | `implement-code` 用 `resources[].worktreePath`、不得出现 `.rayai-worktrees/` | **逐字保留** | 与 FR-07.6 同向 |
  | `:114-119` | code 审批节点（`…0010`）approvalPrompt 含评审后 checkpoint `phase=complete` 前提 | **逐字保留**（FR-01 改写该 approvalPrompt 时保留该句） | 审批前置证据语义 |
  | `:77-90` | pipeline prompt 无 git/journal 字样；write-test-report replayNodes 未改动 | **逐字保留** | 与 FR-06/FR-07 同向 |
  | `:91-107` | `_index.yml#nodes` 与 JSON 一致；`node.ref` 全为 active；gates/状态机零耦合 | **逐字保留** | FR-12.5/FR-13.2 |
- **DD-5 「最近三次 checkpoint」保留展示、写入 cr-show 输出契约**。替代：删除展示项——否决，属 resume-cr 的产品展示需求；留在 pipeline prompt——正是本次要消灭的重复。
- **DD-6 术语硬化/REST/决策收窄写入 SKILL.md 正文**（按 PRD FR-08 收窄范围文案）。替代：独立术语中心/ADR——否决（PRD FR-13.1）。
- **DD-7 提交前缀对齐**：`controlled-shell/rules.json` commit 白名单仅允许 `wip: `、`[cr] `、`merge(`，而三处 Skill 指引越界——`write-tech-design/SKILL.md:88` `feat({cr_id}): draft SDD - tech design`、`write-dev-plan/SKILL.md:70` `feat({cr_id}): draft dev plan`、`write-roadmap/SKILL.md:64` `[planning] …`。同属「命令契约漂移」，归入 FR-07 一并改为白名单内前缀（CR 类用 `[cr] `；本 CR 自身即按 `[cr] draft SDD CR-2026-050` 提交）。承载断言：在 `pipeline-structure.test.mjs` 增加一条扫描——所有 `SKILL.md` 的 `Commit：` 指引前缀必须命中 `rules.json` 的 commit shapes（读文件先 CRLF 归一，匹配失败硬失败）。替代：扩展白名单接受 `feat(`/`[planning] `——否决，白名单最小化优先，`[cr] ` 已满足审计需求。

# 6. FR 到技术实现映射

| FR | 技术实现条目 |
|---|---|
| FR-01 | requirement-authoring（`…0011-…0005`）、architecture-design（`…0016-…0003`）、code-implementation **代码审批节点 `…0015-…0010`**（不动 `…0004` 开工确认语义）的 human approval prompt 改为「人工只提交 approve/reject 决定及理由；reject 走 approve-* reject 流程；证据/CAS/回退由 crctl approve 完成」；删除 review-annotations/*.yml 编辑指引，保留 `…0010` 的 checkpoint `phase=complete` 前提句（§3.0）；负向断言覆盖。multica 侧随 architecture 再生生效。 |
| FR-02 | product-planning.pipeline.json：node-1/2/4 传 topic；node-3 按 §4.3 顺序调用 fetch-competitor-updates→gather-product-context→write-competitive-report(confirmed=false)；node-5 传 prev_outputs/review_feedback/self_repair_attempt；node-6 只传契约输入；**node-7（human approval）**改结构化 approve/reject+reason、驳回中止正向链；**node-8（write-roadmap）**只传 topic/target_version/planning_report_path 并删除规划报告 `_index.yml` 跨文档写入。 |
| FR-03 | market-to-plan.pipeline.json：node-3 按 §4.3 顺序调用 gather-product-context→planning-draft(context,intent)；node-2 传 mode=brief、raw_insight_path（extract-market-insight SKILL.md 同步增加两个输入、默认值与缺参硬失败，见 §2.2）；node-5 删 market-insights/_index.yml published 写入。 |
| FR-04 | competitive-radar.pipeline.json：node-1 只做参数名映射（competitor_slug→competitor-id、since_days→lookback-days），slug→id 的索引解析归 fetch-competitor-updates；node-2 按 §4.3 补 product-snapshot 并 confirmed=false；node-3 支持 reportPath/reportDraft 二选一（report-to-planning-suggestion SKILL.md 增加 reportDraft 输入契约 + 优先级规则 + 同步修订前置条件/错误处理表/读写清单）；node-5 顺序双 Skill 并传递 updates-block/product-snapshot/confirmed=true（§4.1）。 |
| FR-05 | 四条 JSON 的 approve-requirement/approve-tech-design/approve-dev-start/approve-code 节点收敛为「传 cr_id、消费结构化结果、下一步以 crctl next 为准」；approver 由 Skill 经 crctl 从 owners 取（§3.2 统一规则），Pipeline 不拼 owners；删除命令细节/TTY/grant/CAS/状态级联文本。 |
| FR-06 | 三条 JSON 的 review 节点 + code-implementation 的 write-test-report/review-code 节点：删除评审维度正文、payload 与 review-record 调用、annotation/traceability 写入、取证命令、测试机器区算法；保留 reviewLoop 机器字段与 replayNodes；review-tech-design SKILL.md 补 FR-08.4 维度。 |
| FR-07 | **SKILL.md 侧（BLK-3 真实落点）**：`write-tech-design/SKILL.md` 删除 Step 1 的 `.rayai-worktrees/...` 路径约定改消费 `operational_workspace`/`resources[].worktreePath`（FR-07.1）、把「与 sdd.md 同一 commit 提交」改为各仓分别提交 + 同批 checkpoint（FR-07.2）、显式声明两个输入、提交前缀对齐（DD-7）。**Pipeline 侧**：architecture-design push-progress 节点删 checkpoint 命令只传 cr_id/message 消费 phase（FR-07.3，配合 DD-4 的 `:149` 断言修订）；requirement-authoring register/PRD 节点删命令与路径副本（FR-07.4/07.5）；code-implementation implement/freshness/write-dev-plan/write-dev-tasks 节点收敛（FR-07.6~07.9）。全程保留 §3.0 的 inspect 入口与 authority path 契约。 |
| FR-08 | write-tech-design SKILL.md：术语硬化收窄（仅模型/状态机/接口契约且歧义/别名/边界风险，每风险术语至少一个代表性边界场景，预检在首次 crctl advance 前）、HTTP/REST 条件触发基线（仓库约定优先）、决策记录三判据；review-tech-design SKILL.md：四维度扩展（数据模型完整性/接口契约/架构合理性/多仓约束）。 |
| FR-09 | 8 条 JSON 删除固定章节、slug 派生、_index.yml 字段/排序、annotation 文件结构、roadmap 幂等追加、竞品报告固定章节描述（并入各 FR 的节点收敛中一次性完成）。 |
| FR-10 | resume-cr.pipeline.json node-3 收敛为调用 cr-show(section=all)；cr-show SKILL.md 输出契约补「最近三次 checkpoint」；四个 CR approve 节点输出不写死下一 pipeline。 |
| FR-11 | feature-writeback.pipeline.json node-1 删除 status=code-approved 预检文本，保留失败中止。 |
| FR-12 | pipeline-structure.test.mjs 按 §5 DD-4 处置既有断言并扩展新断言；机器字段零改动、节点数/UUID 零改动；§3.0 保留项纳入断言面。 |
| FR-13 | 实施期运行三条自检命令 + Skill 自检清单（index/matrix 不漂移、validate-doc 等价校验、controlled-shell、crctl next、受保护账本、CRLF/硬失败）；不新增任何禁止项。 |

# 7. 安全与性能考量

- **受保护面零扩张**：`protectedPaths.deny` 与受控 shell 白名单零改动；所有账本/annotation 写入仍唯一经 crctl；human approval 不再引导直接编辑受保护文件（FR-01 的核心安全修复）。
- **registry 完整性**：architecture-design 变更与 gate_nodes_gen.go 再生同批提交，digest fail-closed 防止运行时执行漂移 prompt；multica CI `--check` 兜底。
- **CRLF/硬失败纪律**：pipeline-structure.test.mjs 读取 JSON 先 `replaceAll('\r\n','\n')`；任何新增解析失败必须硬失败，禁止静默降级（tools ARCHITECTURE.md 硬不变量 4）。
- **性能**：纯文本/契约变更，无运行时开销；唯一执行面影响是 architecture Runner 后续任务使用更新后的嵌入 prompt（同等模型调用成本）。
- **lint 防线**：`lint-prompts.mjs` 现有 R9（下一步统一 crctl next）等规则继续约束 Skill 侧；本 CR 不新增 lint 规则，负向断言与提交前缀扫描（DD-7）由 pipeline-structure 测试承担。
- **非确定性验收项的证据形态**：AC-08（Skill 正文收窄质量）由 `review-tech-design` 的对应维度结论 + SKILL.md diff 作证；AC-14（两阶段顺序）由 TASK 顺序与 commit/checkpoint 时序作证（§1.4）；DD-7 由新增的提交前缀扫描断言作证。

# 8. Prompt 采纳影响（条件性评估）

按 write-tech-design SKILL.md 规定，本节在「触及 crctl.mjs dispatch 或 rules.json protectedPaths.deny」时必填。**本 CR 不触及二者**：不新增/修改任何 crctl 子命令、参数或 dispatch 分支；deny 面零改动；Skill 输入扩展（mode/reportDraft）不改变 crctl 命令面。因此本节不列「应改为调用新增子命令」的采纳清单。

但存在一个**非 crctl 面的采纳依赖**，已在 §4.2 单列为硬依赖：architecture-design.pipeline.json 的 prompt 变更必须通过 emit-registry.mjs → generate-gate-nodes.mjs 再生 multica 嵌入 registry——这是「生成链漂移」而非「crctl 命令面采纳」，由实施 TASK 与 CI --check 覆盖。

# 9. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 过度删除真实业务判断（PRD R-01） | 每节点保留五要素；负向断言只针对明确列出的禁止文本 |
| 规划流程闭环破坏（PRD R-03） | competitive-radar 按 §4.1 顺序验证：draft 不落盘、reportDraft 可消费、confirmed=true 落盘在前 |
| multica registry 漂移 | 与 architecture JSON 同批再生 + digest 校验 + --check |
| 测试断言过严导致误报 | 断言面向 machine fields（顺序/ref/onFail/replayNodes）与明确反模式文本；正例反例成对 |
| 与既有断言冲突（BLK-2） | 按 §5 DD-4 的既有断言处置清单逐条修订或保留，禁止为让测试通过而回退 CR-2026-044/045 的语义 |
| 部署新 digest 时在跑的 architecture run 命中 `RunnerErrTemplateDigestMismatch`（`runner.go:574-581`） | 该错误按设计保持 run 存活（非终态）：选择等待在跑 run 收敛后再部署，或临时回滚到其 digest 恢复；本 CR 不改该语义 |
| architecture prompt 引入新 `{{…}}` token 触发 `REGISTRY_PROMPT_TOKEN_INVALID` | 重写时只使用既有两个 token（§4.2 第 5 条），再生前先本地跑 `emit-registry.mjs` 验证 |

# 10. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-21 | v0.1.1 | Ray | 首轮技术评审回修（attempt 1，4 条 blocker）：新增 §2.3 上游输入产出方与 §4.3 单节点顺序调用链（BLK-1）；新增 §3.0 机器契约保留项与 DD-4 既有断言处置清单（BLK-2）；FR-07.1/07.2 改到 write-tech-design SKILL.md 真实落点（BLK-3）；修正 product-planning 节点编号与代码审批节点 UUID（BLK-4）；并收纳 approver 取值、token 白名单、digest 风险、DD-7 扩面等建议 |
| 2026-08-21 | v0.1.0 | Ray | 初始 SDD：两阶段实施、8 pipeline 收敛契约、competitive-radar 闭环、multica registry 再生链、DD-1~DD-7 决策 |
