# SDD 评审前移校验方案（评审门禁职责边界优化）

> 日期：2026-08-26
> 适用范围：AI First Platform sibling `../tools/` 方法论包
> 文档性质：PRD 编写前的方案依据，不直接作为状态机或门禁的实现声明
> 背景关联：
> - 实证 CR：CR-2026-051（飞书审批提醒卡片），dev-plan 评审触发 UPSTREAM 路由回修 SDD
> - 上游依据：`docs/analysis/done/开发计划与TASK合并评审门禁方案.md`（review-dev-plan 节点设计依据，CR-2026-026 前身）
> - 建议结论：两层各审自己新增的事实。`review-tech-design` 负责 AC 设计落点可达性、SDD 自己引用的既有代码事实与可观测验收可行性；`review-dev-plan` 负责翻译完整性、TASK 新造的代码事实、责任边界与假绿风险。保留 UPSTREAM 安全网，不新增状态、账本、人工节点、小组或 leader Agent。

---

## 1. 背景与问题

### 1.1 现状：两层评审 + 双轨路由

`code-implementation` 编码前存在两道 LLM 评审门禁：

```text
PRD ──review-requirement/approve──> SDD ──review-tech-design/approve──> plan ──review-dev-plan──> TASK ──> 编码
                                       ↑                                                                    │
                                       └────────────── UPSTREAM 路由（回修 SDD）────────────────────────────┘
```

- **review-tech-design**（8 维度）：PRD↔SDD 对齐（"每条 FR-* 是否有对应技术方案"）、架构合理性、数据模型完整性、接口契约、多仓约束、性能安全、可测试性（"方案是否易于测试"）、Prompt 影响（条件性）。**输入全为文档**：`prd.md`、`sdd.md`、`ARCHITECTURE.md`。
- **review-dev-plan**（8 维度）：SDD→plan 覆盖、plan→TASK 覆盖、TASK 可执行性、依赖拓扑、接口契约一致性、验收可验证性（"每个 TASK ≥2 条可执行验收步骤"）、范围与极简性、风险与回滚。**输入含"代码事实当场核实"要求**，并提供双轨路由（NORMAL 回 `write-dev-plan`、UPSTREAM 回 `write-tech-design`）。

双轨路由（`开发计划与TASK合并评审门禁方案` 的 D-13）已经承认"plan 评审可能暴露 SDD 自相矛盾或无法实施"，并提供正确回流路径。但该路由被设计为**兜底**，却在实践中成为**常态返工点**。

### 1.2 问题实证：CR-2026-051 一轮混合 blocker

CR-2026-051 的 SDD 经两轮技术评审后 pass、人工审批通过，进入任务分解。dev-plan 评审产生一轮混合 blocker：其中一项属于 SDD 上游，两项属于 plan/TASK 翻译增量。由于同轮存在上游 blocker，整轮选择 `repair-target=write-tech-design`；这不表示三项根因都在 SDD。

| blocker | 归属 | 真实根因 |
|---|---|---|
| **[UPSTREAM][AC-4]**：PRD AC-4 要求"非 owner/admin"留下可区分跳过原因，但 SDD §4.2/§6 先用 `role IN ('owner','admin')` 提前过滤，9 项 reason 无 non-approver 取值 → 该类原因**永远产不出来** | SDD | FR 映射存在，但 AC 要求的可观测结果不可达；应由 SDD 评审提前拦截 |
| **[PLAN][TASK-03]**：TASK-03 用 `cr:updated > 0` 作 AC-2 零发布矩阵存活证据，但 trace 事件走 `ingestTrace`、不进 `apply()/publish()` → 验收按当前代码事实不可满足 | plan/TASK | `cr:updated > 0` 是 TASK 新造的代码事实，SDD 没有该断言；应由 plan 评审核实翻译增量 |
| **[PLAN][TASK-05]**：TASK-05 要求灌 typed-nil 仍得 `feishu-disabled`，但 SDD 已规定 typed-nil 由 wiring 层判空、提醒器内不反射 → 验收位置与责任边界不一致，或被其他 nil 依赖短路假绿 | plan/TASK | TASK 把验收放错责任层；应由 plan 评审核查责任边界与假绿风险 |

`review-dev-plan` 的 dimensions 记录为：`sdd-to-plan=block`、`task-executability=block`、`acceptance-verifiability=block`，其余 5 项 pass。正确结论不是“问题都在设计”，而是同一轮同时暴露了 SDD 缺陷和 TASK 翻译缺陷。

### 1.3 根因诊断：两层各有一个结构性盲区

**SDD 层盲区：对齐粒度停在 FR 级，不到 AC 级可达性。** FR 是能力声明，AC 才是验收最小单位。FR 级映射覆盖了，不代表每个 AC 都有能产出其要求的可观测结果。AC-4 就是"有 reason 机制，但过滤后走不到 reason 生成点"的典型。

**两层共同的输入缺口：reviewer 没有正式消费权威 worktree 资源。** Pipeline 已能通过 workspace inspect 得到 `resources[].worktreePath`，但当前没有把资源传给两个 reviewer。SDD 自己引用的既有实现事实无法在 `review-tech-design` 定点核实；TASK 新造的实现断言也无法在 `review-dev-plan` 定点核实。解决方式是原样传递已有资源，不新增路径推导或仓库发现机制。

**Plan 层盲区：对 TASK 新增事实、责任边界和假绿风险约束不够明确。** TASK-03 的错误事件断言、TASK-05 的错误验收位置都只能在 plan/TASK 形成后出现，不能靠 SDD 评审预知。因此 plan 评审必须保留事实核查和 UPSTREAM 安全网，不能被全面“收窄”。

`review-alignment`（AL-01~AL-06）不是答案：它检测的是**时间差和文本指纹漂移**（上游改了、下游没同步），抓不到"设计本身在 AC 级断裂"和"实现口径违背真实代码"这两类语义/事实断裂。

---

## 2. 整体架构

### 2.1 目标分层

核心原则：**两层各审自己新增的事实**。SDD 阶段审设计落点是否可达、SDD 自己引用的既有事实是否成立；plan 阶段审翻译是否完整、TASK 新造的事实和验收手段是否成立。前移 AC 可达性不等于削弱 plan 安全网。

```text
PRD ──review-requirement──> SDD ──review-tech-design（强化后）──> approve ──> plan ──review-dev-plan（收窄后）──> TASK ──> 编码
                                │                                                            │
                                ├─ 原有 8 维度（FR 级对齐等）                                ├─ 翻译增量核查（收窄）
                                ├─ 前移：AC 设计落点可达性                                  ├─ 核实 TASK 新造的代码事实/责任边界
                                ├─ 核实：SDD 自引用的既有代码事实                            ├─ plan 独有载体（拓扑/估算/极简/回滚）
                                └─ 收紧：可观测验收可行性                                    └─ 保留 UPSTREAM 安全网
```

### 2.2 前移原则

1. **前道做实、后道查增量**：同一事实不在两个节点全量重复；但后道发现设计缺陷时仍必须报告并走 UPSTREAM。
2. **只前移 SDD 应负责的首次判定**：AC 设计落点可达性和 SDD 自引用事实前移；TASK 新造事实仍由 plan 首次判定。
3. **UPSTREAM 是必要安全网**：保留现有路由和混合 blocker 回放语义，不把“触发次数下降”设为硬门禁或成功条件。
4. **不新增状态、不新增账本、不新增人工节点**：只改 review Skill 的维度定义，复用现有 `review-record`、`review-loop.yml`、`traceability.yml` 三账本。

### 2.3 职责边界总览

| 校验 | SDD 阶段（前移后） | plan 阶段（收窄后） |
|---|---|---|
| AC 设计落点 | 每个 AC 在设计层有能产出其要求的可观测结果且可达的落点 | AC 落点是否被完整继承到 TASK；不做无差别全量 SDD 重审 |
| 代码事实核验 | 只核 SDD **自己明确引用或依赖的**既有实现事实 | 核 TASK **新造或细化的**代码事实；发现 SDD 事实错误仍可 UPSTREAM |
| 验收可行性 | 判断可观测结果和验收位置在设计层是否成立，不提前编写完整 TASK 步骤 | 判断 TASK 验收是否落在真实责任边界、组合后能否证明 AC、是否会无关短路假绿 |

**plan 阶段永远保留、SDD 无法替代的独有载体**：依赖拓扑、估算一致性、范围与极简性、风险与回滚、plan↔TASK 覆盖。这些在 SDD 阶段没有对应产物，天然属于 plan 层。

---

## 3. 关键实施要点

### 3.1 前移项 1：AC 级可实现性维度

**改动位置**：`review-tech-design/SKILL.md` Step 2 的维度表。

**现状**：`PRD↔SDD 对齐` = "每条 FR-* 是否有对应技术方案；无遗漏"。

**目标**：拆为两层，FR 级映射之上增加 AC 级闭环检查：

- 每条 FR 有对应技术方案（原有，保留）；
- **每个 AC 有能产出其要求的可观测形态的落点**：对每个 AC，检查其要求的"可区分原因/状态/字段/行为"是否有一条**能走到的**生成路径，重点拦截"上游条件提前过滤掉目标对象，导致该 AC 要求的可观测形态永远产不出来"这类闭环断裂（CR-2026-051 AC-4 模式）。

**判定标准**：AC 级断裂记 blocker，不再留到 plan 阶段发现。

### 3.2 前移项 2：关键代码事实核验维度

**改动位置**：`review-tech-design/SKILL.md` Step 1 的输入与 Step 2 维度表。

**现状**：Step 1 只读 `prd.md`、`sdd.md`、`ARCHITECTURE.md`；无目标仓代码事实核查要求。

**目标**：给 `review-tech-design` 增加定点事实核验能力，同时为 `review-dev-plan` 补齐 TASK 新造事实的核验纪律：

- 两条 Pipeline 原样传递 workspace inspect 已有的 `resources[].worktreePath`，reviewer 不得自行拼接 worktree 路径或回退主工作区；
- `review-tech-design` 只核 SDD 明确引用或依赖的关键实现事实；证据记录仓库 ID、commit SHA、相对路径、稳定 symbol 与核实结论，行号仅可作辅助；
- `review-dev-plan` 核 TASK 新造或细化的实现断言（如事件、函数分流、nil 责任层、SQL 口径）。资源缺失、symbol 不存在或行为无法确认时 fail closed，不得猜测或静默 `N/A`；纯绿地设计可注明 `N/A（无既有实现依赖）`。

**边界**：不要求全量 diff、lint 或 build（那是后续阶段职责），不新增代码基线 digest、漂移账本或路径解析器。

### 3.3 前移项 3：收紧"可测试性"为"验收断言可行性"

**改动位置**：`review-tech-design/SKILL.md` Step 2 维度表。

**现状**：`可测试性` = "技术方案是否易于单元/集成测试"。

**目标**：改为"可观测验收可行性"，在"易于测试"之上增加两条硬检查：

- 每个 AC 是否有可观测结果和可达的验收位置；
- SDD 自己提出的断言按其依赖的现有代码事实能否成立。

TASK 步骤是否落在真实责任层、是否会被无关 nil 依赖短路假绿，属于 `review-dev-plan` 的翻译增量核查。

### 3.4 plan 阶段职责聚焦但不削弱

**改动位置**：`review-dev-plan/SKILL.md` Step 2 维度表 + Step 1 前置校验说明。

**现状**：八维度能够承接 NORMAL/UPSTREAM 双轨路由，但对 TASK 新造事实、真实责任边界和假绿风险的核验要求不够明确。

**目标**：保留八维度与双轨路由，明确两层责任：

- `sdd-to-plan` 检查 AC 设计落点是否被 TASK 完整继承；
- `task-executability` / `interface-contract-consistency` 检查 TASK 新造事实是否经权威 worktree 核实、验收是否落在真实责任边界；
- `acceptance-verifiability` 检查验收步骤组合能否证明 AC，以及是否存在无关短路假绿；
- 不做无差别全量 SDD 重审，但任何维度发现设计缺陷时仍必须标为 upstream blocker。

### 3.5 UPSTREAM 路由继续作为安全网

不改状态机转换（`task-breakdown -- review-dev-plan:upstream-design-blocker --> tech-design-review-pending` 保留）。UPSTREAM 继续覆盖：

1. plan 阶段发现 SDD 本身的设计断裂；
2. plan 阶段核查时发现新依赖、新路径或 TASK 新事实反证 SDD；
3. SDD 评审后发生 PRD 修订或代码基线漂移。

同轮同时存在 SDD blocker 与 TASK blocker 时，不新增拆分状态或账本：继续复用现有 `repair-target=write-tech-design` 和 replayNodes，先修 SDD，再重新生成并评审 plan。

---

## 4. 落地路径

### 4.1 需要改动的 tools 面

| 改动面 | 最小修改 |
|---|---|
| `skills/develop/review-tech-design/SKILL.md` | 不新增第九维度：在现有对齐维度加入 AC 可达性，在架构/契约维度加入 SDD 自引用事实核验，将可测试性收紧为可观测验收可行性 |
| `skills/develop/review-dev-plan/SKILL.md` | 明确继承完整性、TASK 新造事实、责任边界与假绿检查；保留 UPSTREAM |
| `skills/develop/write-tech-design/SKILL.md` | 每个 AC 写明设计落点与可观测结果；仅对依赖既有实现的断言就地记录代码事实证据 |
| `pipeline-templates/architecture-design.pipeline.json` | 将 workspace inspect 已产生的 `resources` 原样传给 `review-tech-design` |
| `pipeline-templates/code-implementation.pipeline.json` | 将 `execution_context.resources` 原样传给 `review-dev-plan` |
| `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | 断言两个 reviewer 消费权威 `resources[].worktreePath`，且不自行拼接 `.rayai-worktrees` |
| `skills/shared/crctl/gates.json` | 无需改动（维度校验在 Skill 层，不在门禁层） |
| `dir-graph.yaml` | 无需改动（状态机不变） |

**明确不改**：Agent 与 squad 配置、状态机、crctl、gates、review-record 三账本模型、双轨路由、人工审批、README、索引、依赖和 review-alignment。方案不新增小组或 leader Agent。

### 4.2 实施建议

以独立 tools 仓 CR 实施，不并入任何 in-flight 功能 CR。PRD 可直接采用以下需求候选：

- **FR-1**：`review-tech-design` 必须检查每个 AC 的设计落点、可达性与可观测结果；闭环断裂记 blocker。
- **FR-2**：`review-tech-design` 必须对 SDD 明确引用或依赖的既有代码事实做定点核实，违背或不可核记 blocker；纯绿地设计允许明确 `N/A`。
- **FR-3**：`review-tech-design` 的"可测试性"收紧为"可观测验收可行性"，不提前复制完整 TASK 验收步骤。
- **FR-4**：`write-tech-design` 每个 AC 写明设计落点与可观测结果；只有依赖既有实现的断言才记录仓库、commit、相对路径、symbol 与核实结论。
- **FR-5**：`review-dev-plan` 保留八维度和 UPSTREAM，核查 TASK 继承完整性、新造代码事实、真实责任边界及无关短路假绿。
- **FR-6**：两条 Pipeline 原样传递已有 `resources[].worktreePath`，reviewer 不得自行推导路径或回退主工作区。
- **FR-7**：既有 requirement、tech-design、write-test-report、code reviewLoop 行为不得回归。

### 4.3 兼容性与回滚

- 历史 CR 已生成的 `sdd.yml` / `dev-plan.yml` 不迁移、不重审；只有新流程进入对应评审时应用新维度。
- 前移仅收紧 SDD 评审把关，**可能使部分 CR 在 SDD 阶段多一轮回修**（block 提前暴露）；这是预期的成本前移，总返工量下降（避免"SDD pass → plan upstream 返工"的更长回路）。
- 若某 CR 的实施可行性、责任边界或验收断言无法在 SDD 阶段闭环，`review-tech-design` 必须 BLOCK；不得以"未决项"名义通过审批。只有不影响当前 AC 成立的非阻塞信息可以记录后继续。

---

## 5. 验收标准

1. SDD 中存在"上游条件提前过滤目标对象导致某 AC 要求的可观测结果不可达"时，`review-tech-design` BLOCK（CR-2026-051 AC-4 模式）。
2. SDD 明确引用或依赖的既有实现事实与权威 worktree 不符、资源缺失或无法核实时，`review-tech-design` BLOCK；纯绿地且无既有实现依赖时允许明确 `N/A`。
3. TASK 新造的事件、函数、nil 或 SQL 口径与真实代码不符时，`review-dev-plan` BLOCK（CR-2026-051 TASK-03 模式）。
4. TASK 验收放错责任层或可能被无关依赖短路假绿时，`review-dev-plan` BLOCK（CR-2026-051 TASK-05 模式）。
5. `review-dev-plan` 发现 SDD 设计缺陷、上游变化或新事实反证设计时仍可触发 UPSTREAM；状态机、replayNodes 与三账本行为不变。
6. 两个 reviewer 只消费 Pipeline 传入的 `resources[].worktreePath`，不拼接私有 worktree 路径、不回退主工作区。
7. `lint-prompts.mjs --mode enforce`、`check-skill-matrix.mjs`、`pipeline-structure.test.mjs` 与相关 crctl 测试全绿；既有 reviewLoop 无回归。

---

## 6. 风险、取舍与排除项

### 6.1 已接受取舍

- **SDD 阶段多一轮回修**：前移把 block 暴露时点提前，可能增加 SDD 评审轮次；换取的是消除"审批后 upstream 返工"这个成本最高的回路。
- **评审上下文增大**：`review-tech-design` 新增目标仓代码事实核验，单次评审输入变重；但核验范围限定为 SDD 自引用口径，不扩为全量代码审查。
- **plan 阶段不做无差别全量 SDD 重审**：若 SDD 评审因模型能力未抓全，plan 阶段仍必须通过 UPSTREAM 兜底；不得为了降低 blocker 数量而压制上游问题。

### 6.2 排除项

- 不新增 `sdd-reviewing`、`plan-reviewing` 等状态。
- 不新增独立账本或轮次文件，复用三账本模型。
- 不改 `review-alignment` 的职责（时间/指纹漂移），语义/事实断裂由前移后的 SDD 评审负责。
- 不在 SDD 阶段执行代码 diff、lint、build（仍属 review-code / write-test-report）。
- 不解决"模型独立性/评审模型与生成模型同源"问题（属独立产品决策）。
- 不为此新增评审维度、专门账本字段、代码 digest 或 LLM 评审规则引擎；判定写入既有 `dimensions` 维度结论。
- 不新增小组、leader Agent、Agent 类型或平台调度策略；本方案只调整既有 Skill 契约和 Pipeline 输入传递。

---

## 7. 建议决策

1. `review-tech-design` 在现有维度中加强 AC 设计落点可达性、SDD 自引用事实和可观测验收可行性。
2. `review-dev-plan` 保留八维度与双轨路由，明确核查 TASK 继承、新造事实、真实责任边界和假绿风险。
3. 两条 Pipeline 只负责原样传递已有权威 resources；Skill 消费资源并做业务判断；crctl 继续只负责确定性落盘与门禁。
4. 以一个独立 tools 仓 CR 实施，复用 reviewLoop、三账本和 UPSTREAM，不新增状态、账本、人工节点、小组或 Agent。
5. `write-tech-design` 只要求每个 AC 写明设计落点和可观测结果；代码证据仅在依赖既有实现时提供。

这套方案补的是两层不同空档：SDD 层提前拦截 AC 不可达和自身事实错误，plan 层继续拦截 TASK 翻译新增的错误。它保持“LLM 业务判断 + Pipeline 输入传递/reviewLoop + crctl 确定性落盘 + 人类最终审批”的既有主逻辑，不再造事务或评审框架。
