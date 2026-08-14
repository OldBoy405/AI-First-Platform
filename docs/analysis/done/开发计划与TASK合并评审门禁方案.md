# 开发计划与 TASK 合并评审门禁方案

> 日期：2026-08-09  
> 适用范围：AI First Platform sibling `../tools/` 方法论包  
> 文档性质：PRD 编写前的方案依据，不直接作为状态机或门禁的实现声明  
> 建议结论：在 `write-dev-tasks` 与开发启动人工审批之间增加一个 `review-dev-plan` LLM 合并评审节点；不拆成 plan、TASK 两个评审，不新增人工审批，不新增独立轮次账本。

## 1. 背景与问题

### 1.1 当前流程

`code-implementation` pipeline 当前在编码前的主链为：

```text
write-dev-plan
  → write-dev-tasks（status → task-breakdown）
  → push-progress（可跳过）
  → human_approval「确认进入代码开发」
  → approve-dev-start（status → developing）
  → implement-code
```

现有职责分工：

- `write-dev-plan` 读取已审批的 `sdd.md`，生成 `plan.md`。
- `write-dev-tasks` 读取 `plan.md` 与 `sdd.md`，生成 `tasks/TASK-*.md` 和 `tasks/_index.yml`，并推进到 `task-breakdown`。
- `task-breakdown` 状态门禁只检查 `plan.md` 存在、`tasks/` 下至少有一个 TASK 文件。
- `approve-dev-start` 只校验 `plan.md`、`tasks/_index.yml` 等前置产物存在，由人类确认后推进到 `developing`。
- `review-code` 在代码与测试完成后读取真实 diff、`sdd.md`、全部 TASK、`test-report.md` 和技术评审记录，检查“代码 ↔ TASK ↔ SDD”一致性。

### 1.2 真实缺口

当前没有一个强制 LLM 节点回答以下问题：

1. `plan.md` 是否完整承接已审批 SDD，而不是只满足文件存在。
2. TASK 集合是否完整覆盖 plan 与 SDD，而不是只满足至少有一个 TASK。
3. TASK 的依赖、接口签名、验收条件和涉及文件是否彼此一致、足以直接驱动编码。
4. `write-dev-tasks` 输出的 WARN（估算不一致、接口签名不一致）是否已被处理，而不是带着风险进入开发。

这些问题可能在 `review-code` 被间接发现，但该时点已经完成编码，且代码评审的标准回修目标是 `implement-code`，无法自然修订 `plan.md` 和 TASK。结果是：发现得晚、修复路由不准确、已完成代码可能建立在错误任务拆分上。

### 1.3 问题边界

本方案补的是“已审批技术设计 → 可执行开发任务”之间的质量门禁，不重新评审 PRD，也不替代技术设计评审：

```text
PRD ──需求评审/审批──> SDD ──技术评审/审批──> plan + TASK ──本方案──> 编码
```

本节点以已审批 `sdd.md` 为上游事实源。只有在 plan/TASK 明显暴露 SDD 自相矛盾或无法实施时，才把问题报告为“上游设计疑点”，停止开发启动并请求人工决定是否回到技术设计流程；不得在本节点擅自改写 SDD 或重新定义需求。

## 2. 设计目标与原则

### 2.1 目标

- 在编码前机械阻断遗漏、矛盾或不可执行的 plan/TASK。
- 用一次合并评审同时检查 `SDD → plan → TASK`，避免两个评审节点重复读取同一上下文。
- 复用既有 `review-record`、`review-loop.yml`、`traceability.yml` 和 `reviewLoop` 回修能力。
- 评审通过后仍保留现有开发启动人工审批，人类继续拥有是否进入编码的最终决定权。
- 失败时回到正确的文档生产链，而不是等到代码评审后错误地回到 `implement-code`。

### 2.2 原则

1. **一个评审节点**：新增 `review-dev-plan`，同时评审 plan 与 TASK；不新增 `review-plan` + `review-tasks` 两套节点。
2. **一个回修入口**：所有 blocker 统一回到 `write-dev-plan`，随后依序重跑 `write-dev-tasks` 和 `review-dev-plan`；不在首版设计动态选择多个 repair node。
3. **不新增状态**：评审在既有 `task-breakdown` 状态执行；PASS 时保持 `task-breakdown`，BLOCK 时回到 `tech-design-reviewed`。
4. **不新增账本类型**：只新增阶段证据 `review-annotations/dev-plan.yml`；轮次继续写入既有 `review-loop.yml`，追溯继续投影到既有 `traceability.yml`。
5. **不新增人工节点**：沿用现有“确认进入代码开发”人工审批。
6. **不过度追溯 PRD**：评审主链以 SDD 为准，不重新逐条评审 PRD；PRD→SDD 的完整性仍由既有技术评审负责。
7. **失败早、修复全**：即使 blocker 只发生在 TASK，首版也重跑 plan→TASK，牺牲少量生成时间换取简单、确定的闭环。

## 3. 建议流程

### 3.1 调整后的编码前流程

```text
write-dev-plan
  → write-dev-tasks（status → task-breakdown）
  → review-dev-plan
      ├─ PASS：保持 task-breakdown
      │    → push-progress（可跳过）
      │    → human_approval「确认进入代码开发」
      │    → approve-dev-start（status → developing）
      └─ BLOCK：status → tech-design-reviewed
           → write-dev-plan
           → write-dev-tasks
           → review-dev-plan
```

评审循环最多 3 轮，与 requirement、tech-design、code 评审保持一致。达到上限仍有 blocker 时停止，不进入人工开发启动审批，由人类处理剩余问题或调整上游设计。

### 3.2 pipeline 节点位置

在 `code-implementation.pipeline.json` 中，将新节点放在 `write-dev-tasks` 后、编码前的 `push-progress` 前：

```text
1  write-dev-plan
2  write-dev-tasks
3  review-dev-plan             ← 新增，reviewLoop
4  push-progress（可跳过）
5  human_approval（开发启动）
6  approve-dev-start
7  implement-code
...
```

选择该位置的原因：评审失败时不把已知有问题的 plan/TASK 推送为 checkpoint；评审通过后才进入现有推送与人工确认流程。

### 3.3 reviewLoop 建议配置

概念配置如下，实际 UUID 在实施时按仓库规则分配：

```json
{
  "ref": "review-dev-plan",
  "reviewLoop": {
    "repairRef": "write-dev-plan",
    "feedbackInput": "review_feedback",
    "attemptInput": "self_repair_attempt",
    "replayPolicy": "rerun-listed-nodes-in-order",
    "replayNodes": [
      { "ref": "write-dev-plan", "purpose": "repair-plan" },
      { "ref": "write-dev-tasks", "purpose": "regenerate-tasks" },
      { "ref": "review-dev-plan", "purpose": "rerun-current-review" }
    ],
    "maxAttempts": 3,
    "passCondition": {
      "allOf": [
        { "path": "verdict", "equals": "pass" },
        { "path": "blockers", "isEmpty": true }
      ]
    },
    "onBlock": "route-to-repair-node"
  }
}
```

`write-dev-plan` 与 `write-dev-tasks` 的 prompt 需要接受 `review_feedback`、`self_repair_attempt`，并输出 `fixed-blockers`。回修时只处理评审指出的问题，不扩散 SDD 范围。

## 4. 评审输入、维度与判定

### 4.1 强制输入

`review-dev-plan` 必须读取：

- `change-requests/{cr}/sdd.md`：已审批技术设计、接口与约束的权威输入。
- `change-requests/{cr}/plan.md`：交付里程碑、依赖、风险、回滚、验收与发布策略。
- `change-requests/{cr}/tasks/_index.yml`：TASK 集合、估算、状态、`depends-on` 拓扑。
- `change-requests/{cr}/tasks/TASK-*.md`：目标、输入输出、涉及文件、实现要点、验收条件和接口契约。
- `change-requests/{cr}/review-annotations/sdd.yml`：技术评审已知风险和建议，避免任务拆解遗漏已确认约束。

可按需抽查 `prd.md`，但不得把 PRD 全量复审作为本节点的常规职责，也不得因非本阶段的措辞建议阻塞开发启动。

### 4.2 评审维度

| 维度 | 必查内容 | 典型 blocker |
|---|---|---|
| SDD → plan 覆盖 | SDD 的模块、接口、迁移、验证、回滚和风险是否进入计划 | SDD 关键实施面在 plan 中完全缺失 |
| plan → TASK 覆盖 | 每个计划交付项是否至少落到一个 TASK；每个 TASK 是否能回指 plan/SDD | 存在无人实施的里程碑或无来源 TASK |
| TASK 可执行性 | 目标、输入、输出、文件、实现要点、完成标志是否明确；不得含 TBD/空泛指令 | TASK 无法直接驱动编码或依赖未定义类型 |
| 验收可验证性 | 每个 TASK 至少有可执行验证步骤，且总体覆盖 SDD 验收面 | 关键 TASK 无测试/验证或只能主观判断 |
| 依赖拓扑 | `depends-on` 无悬空引用，顺序符合产出/消费关系，不能形成无法启动的环 | 下游先于上游、悬空依赖、循环互锁 |
| 接口契约一致性 | 上游产出与下游消费的函数名、参数、返回类型、事件/schema 一致 | 同一接口在不同 TASK 中签名不一致 |
| 范围与极简性 | TASK 不引入 SDD 未批准的新能力或投机性抽象；拆分粒度为 1–3 天 | 擅自扩范围或单 TASK 包含整个功能 |
| 风险与回滚 | 高风险变更有验证、开关、迁移或回滚安排 | 不可逆数据变更无回滚/恢复方案 |
| 估算一致性 | plan 总工时与 TASK estimate 求和差异有解释 | 差异足以改变里程碑或资源决策且未说明 |

### 4.3 blocker 与 suggestion 边界

应记为 blocker：

- SDD 必要内容未进入 plan/TASK。
- TASK 集合缺项、依赖错误、接口矛盾、验收不可执行。
- TASK 擅自新增 SDD 未批准的能力或结构性约束。
- 任务拆分无法直接驱动实现，仍需开发者重新设计核心方案。
- 风险可能造成数据丢失、安全问题或不可恢复变更且没有控制措施。

应记为 suggestion：

- 不影响执行的标题、排序、措辞或格式改进。
- 小幅估算差异且不影响里程碑、依赖或人员安排。
- SDD 范围外的未来优化、重构或抽象建议。

本评审默认采用 strict：只按当前 CR 已批准范围判断 pass/block，范围外改进进入 suggestions，不借评审扩展需求。

## 5. 证据与账本设计

### 5.1 stage 与文件映射

建议使用统一、较短的 stage 名：`dev-plan`。

| 项目 | 建议值 |
|---|---|
| Skill / pipeline ref | `review-dev-plan` |
| `review-record --stage` | `dev-plan` |
| 临时判断 payload | `.crctl/tmp/review-dev-plan.yml` |
| canonical annotation | `review-annotations/dev-plan.yml` |
| review loop ref | `review-dev-plan` |
| traceability 投影 | `reviews.dev-plan` |
| repair target | `write-dev-plan` |

`dev-plan.yml` 只保存本阶段评审事实；轮次继续由 `review-loop.yml` 统一管理；`traceability.yml#reviews.dev-plan` 继续是同步投影。不要为本阶段另建独立 loop 文件或第二份 TASK 评审文件。

### 5.2 临时 payload

```yaml
verdict: pass | block
blockers: []
dimensions:
  sdd-to-plan: pass | block
  plan-to-tasks: pass | block
  task-executability: pass | block
  dependency-topology: pass | block
  interface-contracts: pass | block
  acceptance-verifiability: pass | block
  scope-and-simplicity: pass | block
  risk-and-rollback: pass | block
  suggestion-policy: strict
  reviewer-model: "<model/runner self report>"
suggestions: []
```

LLM 只写临时 payload；`crctl review-record` 负责 schema 校验、身份和时间注入、canonical 写入、轮次记账及 traceability 投影。模型不得直接手改 `dev-plan.yml`、`review-loop.yml` 或 `traceability.yml`。

### 5.3 `crctl review-record` 映射扩展

在现有共用 stage 映射中增加一项，不新增子命令：

```text
REVIEW_STAGE_FILES.dev-plan          = dev-plan.yml
REVIEW_STAGE_LOOPS.dev-plan          = review-dev-plan
REVIEW_STAGE_EXPECT.dev-plan         = [task-breakdown]
REVIEW_REPAIR_TARGETS.dev-plan       = write-dev-plan
```

投影、CAS、payload 删除和审计均复用已有 `review-record` 通用路径，不给 `dev-plan` 编写独立写账本实现。

## 6. 状态机与门禁

### 6.1 状态机

不新增具名状态，只新增一条自动评审失败转换：

```text
task-breakdown
  -- "review-dev-plan:block -> write-dev-plan"
  --> tech-design-reviewed
```

PASS 时不推进状态，继续保持 `task-breakdown`，等待现有 human approval。`write-dev-tasks` 已支持 `task-breakdown → task-breakdown` 自环，可继续保留供人工调整 TASK 后重跑。

### 6.2 开发启动审批门禁

`gates.json#approvalStages.dev-start` 应从“只检查文件存在”升级为：

- `review-annotations/dev-plan.yml` 存在。
- 使用 `code-implementation#review-dev-plan.reviewLoop.passCondition`，要求 `verdict=pass` 且 `blockers=[]`。
- `plan.md`、`tasks/_index.yml` 与至少一个 `TASK-*.md` 仍存在。
- 人工审批仍由 `crctl approve --stage dev-start` 完成，Agent 不得代写 `approval.yml`。

建议将开发启动审批的 evidence 至少声明为：

```json
{
  "$default": "change-requests/{cr}/review-annotations/dev-plan.yml",
  "plan": "change-requests/{cr}/plan.md",
  "task-index": "change-requests/{cr}/tasks/_index.yml"
}
```

这样审批后的 `evidence-digest` 至少绑定评审结论、plan 和 TASK 拓扑；审批后修改这些文件会触发既有 `EVIDENCE_DRIFT`。

首版不为 TASK 文件 glob 新造通用摘要协议。TASK 正文的“评审后变更检测”与 tech/code 阶段的被评审对象 freshness 属于通用问题，如需机械绑定全部 `TASK-*.md`，应另行设计通用多文件/glob subject digest，不在本方案中只给 `dev-plan` 做特判。

### 6.3 developing 目标态门禁

为避免在 `task-breakdown` 后删除产物仍能审批进入开发，建议在 `developing` 目标态门禁中同时保留：

- `plan.md` 存在；
- `tasks/_index.yml` 存在；
- `tasks/TASK-*.md` 非空；
- `dev-start` 自动评审 passCondition 通过；
- `approval.yml#development-start` 为合法人工审批记录。

全部使用现有 `fileExists`、`globNonEmpty`、`passCondition`、`approval` 门禁类型，不新增新的门禁解释器。

## 7. 需要修改的 tools 面

| 改动面 | 最小修改 |
|---|---|
| `skills/develop/review-dev-plan/SKILL.md` | 新增合并评审 Skill，定义输入、维度、payload、回修和落盘规则 |
| `pipeline-templates/code-implementation.pipeline.json` | 在 write-dev-tasks 后插入 reviewLoop 节点，配置 replayNodes 与 passCondition；后续节点顺序后移 |
| `skills/develop/write-dev-plan/SKILL.md` | 支持消费 review_feedback/self_repair_attempt，逐条修复并输出 fixed-blockers |
| `skills/develop/write-dev-tasks/SKILL.md` | 支持消费 review_feedback；回修时重新生成 TASK 与索引，不保留已被删除的旧 TASK |
| `skills/shared/crctl/scripts/crctl.mjs` | 在四个 REVIEW_STAGE_* 映射中加入 dev-plan；保持通用实现 |
| `skills/shared/crctl/gates.json` | 增加 `review-dev-plan` loop 映射；dev-start 增加 evidence/passCondition；developing 加完整门禁 |
| `dir-graph.yaml` | 增加 task-breakdown → tech-design-reviewed 的 review block 转换 |
| `skills/_index.yml` | 登记新 Skill；更新 code-implementation 节点数与摘要 |
| `agent-skill-matrix.yml` / 生成文档 | 为既有开发角色登记 `review-dev-plan` owns，不新增 actor |
| `README.md` / `ARCHITECTURE.md` | 更新节点流程、受控评审 stage 与状态转换说明；按维护规则登记 |
| `crctl.test.mjs` / prompt lint tests | 增加 stage 映射、门禁、轮次、状态转换、失败原子性和 prompt 漂移回归 |

不需要修改：审批方式、人工 TTY 限制、代码实现节点、代码评审判据、writeback 数据模型。

## 8. 可直接转写为 PRD 的需求候选

### 8.1 功能需求候选

- **FR-1**：`code-implementation` 在 `write-dev-tasks` 后、开发启动 push/human approval 前执行 `review-dev-plan`。
- **FR-2**：`review-dev-plan` 必须读取 SDD、plan、TASK 索引、全部 TASK 和 SDD 技术评审记录。
- **FR-3**：评审必须覆盖 SDD→plan、plan→TASK、TASK 可执行性、依赖拓扑、接口一致性、验收可验证性、范围、风险与回滚八类维度。
- **FR-4**：评审判断经 `.crctl/tmp/review-dev-plan.yml` 输入 `crctl review-record --stage dev-plan --bump-attempt`，生成 `review-annotations/dev-plan.yml`，并同步更新统一 review loop 与 traceability 投影。
- **FR-5**：PASS 条件为 `verdict=pass && blockers=[]`；通过时保持 `task-breakdown` 并允许进入现有开发启动人工审批。
- **FR-6**：BLOCK 时经新状态转换回到 `tech-design-reviewed`，按 write-dev-plan→write-dev-tasks→review-dev-plan 顺序重放。
- **FR-7**：评审循环最多 3 轮；轮次耗尽仍未通过时停止，不得进入 human approval。
- **FR-8**：`approve-dev-start` 必须校验 dev-plan 自动评审通过，且 plan、索引和 TASK 文件仍存在；自动评审不通过时返回 GATE_BLOCKED。
- **FR-9**：人工 dev-start 审批的 evidence digest 至少覆盖 dev-plan annotation、plan.md 和 tasks/_index.yml。
- **FR-10**：回修后的 write-dev-plan/write-dev-tasks 必须逐条输出 fixed-blockers；禁止只刷新评审证据而不修改被指出的产物。
- **FR-11**：新阶段必须复用通用 `review-record`，不得另建写 annotation/loop/trace 的脚本或模型直写旁路。
- **FR-12**：现有 requirement、tech-design、write-test-report、code reviewLoop 行为不得回归。

### 8.2 非功能需求候选

- **NFR-1（最小改造）**：不新增 CR 具名状态，不新增审批 stage，不新增独立账本类型。
- **NFR-2（确定性写入）**：annotation、review-loop 和 traceability 的同轮数据必须共享同一 reviewer、时间、attempt、verdict 与 blocker-count；任一前置校验/CAS 失败不得产生部分写入。
- **NFR-3（行尾纪律）**：所有哈希、逐行解析和定点编辑先规范化 CRLF；结构无法唯一定位时硬失败，不静默降级。
- **NFR-4（兼容性）**：历史 CR 没有 `dev-plan.yml` 时不做批量迁移；只有新流程进入 dev-start approval 时要求新证据。
- **NFR-5（不过度设计）**：首版统一回修 plan→TASK，不实现按 blocker 动态选择 write-dev-plan/write-dev-tasks，不新增专用 LLM 选择暂停节点。
- **NFR-6（可审计）**：评审证据记录 reviewer-model 与 suggestion-policy，pipeline 输出 current-attempt、repair-target、repair-instructions 和摘要。

## 9. 验收标准候选

1. SDD 中存在一个关键模块但 plan 完全未覆盖时，评审 BLOCK，blocker 指明 SDD 章节与缺失计划面。
2. plan 中存在交付项但没有任何 TASK 承接时，评审 BLOCK。
3. TASK 的 `depends-on` 指向不存在任务、形成互锁环或顺序与接口产出相反时，评审 BLOCK。
4. 上游 TASK 产出与下游 TASK 消费的函数名、参数或返回类型不一致时，评审 BLOCK。
5. 关键 TASK 没有至少两条可执行验收步骤或仍含 TBD/空泛实现说明时，评审 BLOCK。
6. plan/TASK 擅自加入 SDD 未批准能力时，评审 BLOCK；纯命名和非本 CR 优化进入 suggestions。
7. 全部维度通过时生成 `dev-plan.yml`，`review-loop.yml#loops.review-dev-plan.current-attempt=1`，`traceability.yml#reviews.dev-plan` 与 annotation 一致。
8. BLOCK 后 status 从 `task-breakdown` 回到 `tech-design-reviewed`，pipeline 依次重跑 plan、TASK、评审；不得直接进入 implement-code。
9. 第 2 轮通过时 traceability attempts 同时保留第 1 轮 block 与第 2 轮 pass；三账本时间、轮次、结论一致。
10. 评审未通过、证据缺失或 blockers 非空时执行 `crctl approve --stage dev-start`，必须返回 GATE_BLOCKED，且不写合法审批段、不推进 developing。
11. 评审通过且 plan/index/TASK 存在时，人工审批行为与现状一致，仍只能由 TTY 或合法签名 grant 完成。
12. 审批后修改 dev-plan annotation、plan 或 task index，后续门禁识别 EVIDENCE_DRIFT。
13. 三轮均 BLOCK 时返回 LOOP_EXHAUSTED 并停止，不进入 human approval。
14. requirement、tech-design、write-test-report、code 的既有 review-record、attempt、gate、approve 与 traceability 投影测试全部通过。
15. `check-skill-matrix.mjs`、`check-agents-contract.mjs`、`lint-prompts.mjs --mode enforce` 和相关 Node 测试全绿。

## 10. 风险、取舍与排除项

### 10.1 已接受取舍

- TASK-only blocker 也会重跑 plan，可能多消耗一次 LLM 生成，但避免动态 repair target、状态分支和半套回修链。
- 本节点仍可能由生成 plan/TASK 的同一模型执行；首版只要求 reviewer-model 留痕，不增加模型选择暂停。模型独立性若有强需求，应作为单独产品决策处理。
- 首版审批摘要覆盖 annotation、plan 和 task index，不为 TASK glob 增加专用摘要协议；完整 subject freshness 留给跨 stage 的通用方案。

### 10.2 排除项

- 不拆成 plan review 与 TASK review 两个节点。
- 不新增 `plan-reviewing`、`task-reviewing` 等状态。
- 不修改 PRD/SDD 的既有评审与审批责任边界。
- 不在此节点执行代码 diff、lint、test、build；这些仍属于 write-test-report/review-code。
- 不新增 `review-dev-plan-loop.yml`、`task-review.yml` 等账本。
- 不把所有 TASK 内容复制到 annotation 或 traceability。
- 不在本方案中解决所有阶段的被评审对象 freshness；如需解决，应统一覆盖 requirement/tech-design/dev-plan/code，避免只给一个 stage 特判。

## 11. 建议决策

建议以独立 CR 实施，不并入 CR-2026-025。PRD 可直接采用以下产品级决策：

1. 新增一个且仅一个 `review-dev-plan` 合并评审节点。
2. 节点位置固定在 TASK 拆分后、首次 plan/TASK push 与开发启动人工审批前。
3. PASS 保持 `task-breakdown`；BLOCK 统一回 `tech-design-reviewed`，完整重跑 plan→TASK→review。
4. 复用现有三账本模型，只新增 `dev-plan.yml` 阶段证据。
5. dev-start 人工审批增加自动评审 passCondition，blocker 未清空不得进入编码。
6. 首版不引入动态回修、额外状态、额外人工节点或专用 freshness 框架。

这套方案补齐的是编码前最后一个实质质量空档，同时保持 tools 包现有“LLM 判断 + crctl 确定性落盘 + 人类最终审批”的主逻辑不变。
