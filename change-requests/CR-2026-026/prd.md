---
id: CR-2026-026-prd
type: PRD
cr-ref: CR-2026-026
title: 开发计划与 TASK 合并评审门禁 — 新增 review-dev-plan 编码前质量门禁
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-09T05:10:00+08:00"
updated: "2026-08-09T05:10:00+08:00"
---

# PRD — 开发计划与 TASK 合并评审门禁

## 1. 概述

### 1.1 问题陈述

`code-implementation` pipeline 当前编码前主链为：

```text
write-dev-plan → write-dev-tasks（status → task-breakdown）
  → push-progress（可跳过）→ human_approval → approve-dev-start → implement-code
```

现有门禁只检查文件存在（`plan.md` 存在、`tasks/` 下至少一个 TASK 文件），没有一个强制 LLM 节点回答以下问题：

1. `plan.md` 是否完整承接已审批 SDD，而不是只满足文件存在。
2. TASK 集合是否完整覆盖 plan 与 SDD，而不是只满足至少有一个 TASK。
3. TASK 的依赖、接口签名、验收条件和涉及文件是否彼此一致、足以直接驱动编码。
4. `write-dev-tasks` 输出的 WARN（估算不一致、接口签名不一致）是否已被处理。

这些问题可能在 `review-code` 被间接发现，但该时点已完成编码，回修目标是 `implement-code`，无法自然修订 `plan.md` 和 TASK。结果是：发现得晚、修复路由不准确、已完成代码可能建立在错误任务拆分上。

**问题边界**：本 CR 补的是「已审批技术设计 → 可执行开发任务」之间的质量门禁，不重新评审 PRD，不替代技术设计评审。

### 1.2 解决方案摘要

在 `write-dev-tasks` 与开发启动人工审批之间新增一个 `review-dev-plan` LLM 合并评审节点：

- **一次评审**：同时检查 `SDD → plan → TASK` 八类维度，不拆成 plan review + TASK review 两个节点。
- **PASS**：保持 `task-breakdown`，进入现有 push-progress → human_approval → approve-dev-start 流程。
- **BLOCK**：经新状态转换回到 `tech-design-reviewed`，按 `write-dev-plan → write-dev-tasks → review-dev-plan` 顺序重放（最多 3 轮）。
- **复用既有基础设施**：`review-record`、`review-loop.yml`、`traceability.yml`、`reviewLoop` 回修能力。
- **不新增**：具名状态、审批节点、独立账本类型。仅新增阶段证据 `review-annotations/dev-plan.yml`。
- **门禁升级**：`approve-dev-start` 从「只检查文件存在」升级为校验自动评审 passCondition + evidence digest。

### 1.3 事实基线（来源：方案文档 §1）

| # | 事实 | 依据 |
|---|---|---|
| B-1 | `write-dev-plan` 读取已审批 `sdd.md` 生成 `plan.md`；`write-dev-tasks` 读取 plan+sdd 生成 TASK 与 `_index.yml`，推进到 `task-breakdown` | 方案 §1.1 |
| B-2 | `task-breakdown` 状态门禁只检查 `plan.md` 存在、`tasks/` 下至少有一个 TASK 文件 | 方案 §1.1 |
| B-3 | `approve-dev-start` 只校验 `plan.md`、`tasks/_index.yml` 等前置产物存在，由人类确认后推进到 `developing` | 方案 §1.1 |
| B-4 | `review-code` 在代码与测试完成后检查「代码 ↔ TASK ↔ SDD」一致性，回修目标是 `implement-code` | 方案 §1.1 |
| B-5 | 现有 reviewLoop 机制（requirement/tech-design/code）已支持 replayNodes、maxAttempts、passCondition、repair target 路由 | 方案 §3.3 |
| B-6 | `review-record` 已有共用 stage 映射（REVIEW_STAGE_FILES / REVIEW_STAGE_LOOPS / REVIEW_STAGE_EXPECT / REVIEW_REPAIR_TARGETS），新增 stage 只需加映射项 | 方案 §5.3 |
| B-7 | 状态机现有 15 个具名状态 + 注册前 `(new)`；转移 25 条声明（wildcard 展开 47 条） | AGENTS.md 纪律 #2 |

### 1.4 决策点（本 PRD 拍板）

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 评审节点数量 | **一个** `review-dev-plan` 合并评审 | 避免两个节点重复读取同一上下文；方案 §2.2 原则 1 |
| D-2 | 回修入口 | **统一回 `write-dev-plan`**，随后依序重跑 TASK 和评审 | 首版不做动态 repair target 选择，换简单确定的闭环；方案 §2.2 原则 2 |
| D-3 | 状态变更 | **不新增具名状态**；评审在 `task-breakdown` 执行，BLOCK 回 `tech-design-reviewed` | 最小改造；方案 §2.2 原则 3 |
| D-4 | 账本模型 | **不新增账本类型**；只新增 `dev-plan.yml` 阶段证据，轮次写既有 `review-loop.yml`，追溯投影到既有 `traceability.yml` | 方案 §2.2 原则 4 |
| D-5 | 人工节点 | **不新增**；沿用现有「确认进入代码开发」人工审批 | 方案 §2.2 原则 5 |
| D-6 | 评审范围 | **以 SDD 为准**，不重新逐条评审 PRD | 方案 §2.2 原则 6 |
| D-7 | 回修粒度 | **TASK-only blocker 也重跑 plan→TASK** | 牺牲少量生成时间换简单确定闭环；方案 §2.2 原则 7 |
| D-8 | 评审循环上限 | **最多 3 轮**，与 requirement/tech-design/code 一致 | 方案 §3.1 |
| D-9 | TASK glob freshness | **首版不做**；不为 TASK 文件新造通用摘要协议 | 完整 subject freshness 是通用问题，应统一覆盖所有 stage；方案 §6.2 |
| D-10 | suggestion 策略 | **strict**：只按当前 CR 已批准范围判断 pass/block，范围外改进进 suggestions | 方案 §4.3 |

## 2. 用户故事

- **US-1** 作为开发启动审批人，当 plan/TASK 存在遗漏或矛盾时，`review-dev-plan` 在我审批前就阻断进入编码，而不是等代码写完在 review-code 才发现。
- **US-2** 作为 `dev-agent`（实现者），当我拿到 TASK 集合时，每个 TASK 的目标、输入输出、涉及文件、验收条件都足够明确，可以直接驱动编码，不需要自己重新设计核心方案。
- **US-3** 作为 tools 包维护者，`review-dev-plan` 复用既有 `review-record` 通用路径落盘，不引入新的写账本脚本或模型直写旁路。
- **US-4** 作为 pipeline runtime，`review-dev-plan` BLOCK 时状态回到 `tech-design-reviewed`，pipeline 自动按 plan→TASK→评审顺序重放，不需要人工干预路由。
- **US-5** 作为评审者，当评审发现 SDD 自相矛盾或无法实施时，问题被报告为「上游设计疑点」并停止开发启动，而不是在本节点擅自改写 SDD。
- **US-6** 作为开发启动审批人，审批后修改 plan/TASK/annotation 会触发 `EVIDENCE_DRIFT`，防止审批后偷改。

## 3. 功能需求

### 评审节点与 pipeline 集成

- **FR-1（节点位置）**：`code-implementation.pipeline.json` 在 `write-dev-tasks` 后、`push-progress` 前插入 `review-dev-plan` reviewLoop 节点。后续节点顺序后移。
- **FR-2（强制输入）**：`review-dev-plan` 必须读取：`sdd.md`（已审批技术设计）、`plan.md`（交付里程碑）、`tasks/_index.yml`（TASK 集合与拓扑）、全部 `TASK-*.md`（目标/接口/验收）、`review-annotations/sdd.yml`（技术评审已知风险）。可按需抽查 `prd.md`，但不得全量复审 PRD。
- **FR-3（评审维度）**：评审必须覆盖八类维度：SDD→plan 覆盖、plan→TASK 覆盖、TASK 可执行性、依赖拓扑、接口契约一致性、验收可验证性、范围与极简性、风险与回滚。另含估算一致性检查。
- **FR-4（评审判定落盘）**：评审判断经 `.crctl/tmp/review-dev-plan.yml` 输入 `crctl review-record --stage dev-plan --bump-attempt`，生成 `review-annotations/dev-plan.yml`，同步更新 `review-loop.yml` 与 `traceability.yml#reviews.dev-plan`。
- **FR-5（PASS 条件与行为）**：PASS 条件为 `verdict=pass && blockers=[]`；通过时保持 `task-breakdown`，允许进入现有开发启动人工审批。
- **FR-6（BLOCK 行为与回修路由）**：BLOCK 时经新状态转换 `task-breakdown → tech-design-reviewed`（trigger: `review-dev-plan:block`），pipeline 按 `write-dev-plan → write-dev-tasks → review-dev-plan` 顺序重放。
- **FR-7（循环上限）**：评审循环最多 3 轮（`maxAttempts: 3`）；轮次耗尽仍未通过时返回 `LOOP_EXHAUSTED` 并停止，不得进入 human approval。

### 回修能力

- **FR-8（回修 prompt 支持）**：`write-dev-plan` 与 `write-dev-tasks` 的 prompt 须接受 `review_feedback`、`self_repair_attempt` 输入，并输出 `fixed-blockers`。回修时只处理评审指出的问题，不扩散 SDD 范围。
- **FR-9（回修禁止空转）**：回修后的 write-dev-plan/write-dev-tasks 必须逐条输出 fixed-blockers；禁止只刷新评审证据而不修改被指出的产物。

### 门禁升级

- **FR-10（dev-start 审批门禁）**：`gates.json#approvalStages.dev-start` 升级为校验：① `review-annotations/dev-plan.yml` 存在；② passCondition（`verdict=pass && blockers=[]`）通过；③ `plan.md`、`tasks/_index.yml` 与至少一个 `TASK-*.md` 仍存在。自动评审不通过时返回 `GATE_BLOCKED`。
- **FR-11（evidence digest）**：人工 dev-start 审批的 evidence digest 至少覆盖 `dev-plan.yml` annotation、`plan.md` 和 `tasks/_index.yml`。审批后修改这些文件触发既有 `EVIDENCE_DRIFT`。
- **FR-12（developing 目标态门禁）**：`developing` 目标态门禁同时保留：`plan.md` 存在、`tasks/_index.yml` 存在、`tasks/TASK-*.md` 非空、dev-start passCondition 通过、`approval.yml#development-start` 为合法人工审批记录。全部使用现有 `fileExists`、`globNonEmpty`、`passCondition`、`approval` 门禁类型。

### 状态机与映射

- **FR-13（状态转换）**：`dir-graph.yaml`（tools 包）新增一条自动评审失败转换：`task-breakdown --review-dev-plan:block--> tech-design-reviewed`。不新增具名状态。
- **FR-14（crctl 映射扩展）**：`crctl.mjs` 的四个 REVIEW_STAGE_* 映射中加入 `dev-plan`：`REVIEW_STAGE_FILES.dev-plan = dev-plan.yml`、`REVIEW_STAGE_LOOPS.dev-plan = review-dev-plan`、`REVIEW_STAGE_EXPECT.dev-plan = [task-breakdown]`、`REVIEW_REPAIR_TARGETS.dev-plan = write-dev-plan`。保持通用实现，不新增子命令。

### Skill 与文档

- **FR-15（新 Skill）**：新建 `skills/develop/review-dev-plan/SKILL.md`，定义输入、八类维度、payload 格式、回修和落盘规则。
- **FR-16（Skill 登记与矩阵）**：`skills/_index.yml` 登记新 Skill；`agent-skill-matrix.yml` 为既有开发角色登记 `review-dev-plan` owns（不新增 actor）。
- **FR-17（文档同步）**：`README.md` / `ARCHITECTURE.md` 更新节点流程、受控评审 stage 与状态转换说明。

### 收尾

- **FR-18（既有行为不回归）**：requirement、tech-design、write-test-report、code 的既有 reviewLoop 行为不得回归。
- **FR-19（验证关卡）**：`check-skill-matrix.mjs`、`check-agents-contract.mjs`、`lint-prompts.mjs --mode enforce` 全绿；`node --test` 跑通 `crctl.test.mjs` 与 prompt lint tests 全部用例。
- **FR-20（溯源标注）**：commit message 注明来源为 `docs/analysis/开发计划与TASK合并评审门禁方案.md`，含 CR-2026-026 编号。

## 4. 非功能需求

- **NFR-1（最小改造）**：不新增 CR 具名状态，不新增审批 stage，不新增独立账本类型。
- **NFR-2（确定性写入）**：annotation、review-loop 和 traceability 的同轮数据必须共享同一 reviewer、时间、attempt、verdict 与 blocker-count；任一前置校验/CAS 失败不得产生部分写入。
- **NFR-3（行尾纪律）**：所有哈希、逐行解析和定点编辑先规范化 CRLF；结构无法唯一定位时硬失败，不静默降级。
- **NFR-4（兼容性）**：历史 CR 没有 `dev-plan.yml` 时不做批量迁移；只有新流程进入 dev-start approval 时要求新证据。
- **NFR-5（不过度设计）**：首版统一回修 plan→TASK，不实现按 blocker 动态选择 write-dev-plan/write-dev-tasks，不新增专用 LLM 选择暂停节点。
- **NFR-6（可审计）**：评审证据记录 reviewer-model 与 suggestion-policy；pipeline 输出 current-attempt、repair-target、repair-instructions 和摘要。
- **NFR-7（零新增第三方依赖）**：全部使用 `node:` 内置模块，测试仅用 `node:test`/`node:assert`。

## 5. 验收标准

- **AC-1**（FR-2/FR-3）：SDD 中存在一个关键模块但 plan 完全未覆盖时，评审 BLOCK，blocker 指明 SDD 章节与缺失计划面。
- **AC-2**（FR-3）：plan 中存在交付项但没有任何 TASK 承接时，评审 BLOCK。
- **AC-3**（FR-3）：TASK 的 `depends-on` 指向不存在任务、形成互锁环或顺序与接口产出相反时，评审 BLOCK。
- **AC-4**（FR-3）：上游 TASK 产出与下游 TASK 消费的函数名、参数或返回类型不一致时，评审 BLOCK。
- **AC-5**（FR-3）：关键 TASK 没有至少两条可执行验收步骤或仍含 TBD/空泛实现说明时，评审 BLOCK。
- **AC-6**（FR-3/D-10）：plan/TASK 擅自加入 SDD 未批准能力时，评审 BLOCK；纯命名和非本 CR 优化进入 suggestions。
- **AC-7**（FR-4/FR-5）：全部维度通过时生成 `dev-plan.yml`，`review-loop.yml#loops.review-dev-plan.current-attempt=1`，`traceability.yml#reviews.dev-plan` 与 annotation 一致。
- **AC-8**（FR-6）：BLOCK 后 status 从 `task-breakdown` 回到 `tech-design-reviewed`，pipeline 依次重跑 plan、TASK、评审；不得直接进入 implement-code。
- **AC-9**（FR-4/NFR-2）：第 2 轮通过时 traceability attempts 同时保留第 1 轮 block 与第 2 轮 pass；三账本时间、轮次、结论一致。
- **AC-10**（FR-10）：评审未通过、证据缺失或 blockers 非空时执行 `crctl approve --stage dev-start`，必须返回 GATE_BLOCKED，且不写合法审批段、不推进 developing。
- **AC-11**（FR-10）：评审通过且 plan/index/TASK 存在时，人工审批行为与现状一致，仍只能由 TTY 或合法签名 grant 完成。
- **AC-12**（FR-11）：审批后修改 dev-plan annotation、plan 或 task index，后续门禁识别 EVIDENCE_DRIFT。
- **AC-13**（FR-7）：三轮均 BLOCK 时返回 LOOP_EXHAUSTED 并停止，不进入 human approval。
- **AC-14**（FR-18）：requirement、tech-design、write-test-report、code 的既有 review-record、attempt、gate、approve 与 traceability 投影测试全部通过。
- **AC-15**（FR-19）：`check-skill-matrix.mjs`、`check-agents-contract.mjs`、`lint-prompts.mjs --mode enforce` 和相关 Node 测试全绿。

## 6. 成功指标

- 编码前质量空档被机械阻断：plan/TASK 的遗漏、矛盾或不可执行问题在开发启动审批前即被拦截，不再等到 review-code 阶段才发现。
- 回修路由准确：BLOCK 后回到 `write-dev-plan` 重跑完整链条，而不是错误地回到 `implement-code`。
- 复用既有基础设施：不引入新的账本类型、状态或人工节点；`review-record` 通用路径覆盖新 stage。
- 人类保留最终决定权：评审通过后仍需人工确认进入编码；评审只阻断不代行审批。
- 可审计：每轮评审留下 reviewer-model、verdict、blocker-count、时间戳与轮次记录。

## 7. 范围排除

**本 CR 包含**：`review-dev-plan` Skill 新建、pipeline 模板修改、crctl 映射扩展、gates.json 门禁升级、dir-graph.yaml 状态转换、write-dev-plan/write-dev-tasks prompt 回修支持、文档同步、测试向量。

**本 CR 不包含**：
- 不拆成 plan review 与 TASK review 两个节点（D-1）。
- 不新增 `plan-reviewing`、`task-reviewing` 等状态（D-3）。
- 不修改 PRD/SDD 的既有评审与审批责任边界。
- 不在本节点执行代码 diff、lint、test、build（仍属 write-test-report/review-code）。
- 不新增 `review-dev-plan-loop.yml`、`task-review.yml` 等账本（D-4）。
- 不把所有 TASK 内容复制到 annotation 或 traceability。
- 不在本方案中解决所有阶段的被评审对象 freshness；如需解决，应统一覆盖 requirement/tech-design/dev-plan/code（D-9）。
- 不实现按 blocker 动态选择回修目标（D-7/NFR-5）。
- 不新增模型选择暂停节点（评审可由生成 plan/TASK 的同一模型执行，首版只要求 reviewer-model 留痕）。

## 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-09 | v0.1.0 | Ray | 初始草稿（基于方案文档 §1-§11 转写；20 条 FR、7 条 NFR、15 条 AC） |
