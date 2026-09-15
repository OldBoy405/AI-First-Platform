---
id: CR-2026-067-sdd
type: SDD
cr-ref: CR-2026-067
title: CR-P1：评审输入结构与回修闭合 技术设计
target-version: 0.40
status: draft
created: 2026-09-15T08:30:00+08:00
updated: 2026-09-15T08:45:00+08:00
---

# 1. 架构概览

## 1.1 设计目标与不变量

本 CR 的技术设计只做一件事：**把「SDD 既有实现事实」的表达与「评审闭合」的判据原位收紧到同一套可判定的承载体上**——事实用一个稳定标识 `dep-N` 唯一表达，判据用两侧同口径的关系式与自洽条件表述。设计遵守 PRD §1.3.1 / §7 的零新增面，落成四条设计不变量：

| # | 设计不变量 | 判据落点 |
|---|---|---|
| I1 | **既有实现事实只有一个定义点**：事实只在 `### 既有实现依赖与事实` 表内定义一次；SDD 正文只以「设计依赖 `dep-N`」引用，不重述当前代码行为。任何"重新陈述"都不再是"另一份口径"，而是判据明确禁止的形态 | FR-1.4 / AC-1② |
| I2 | **`dep-N` 是稳定标识，不是序号别名**：编号按正文首次出现顺序分配、只增不改（删除留空洞、编号不复用），因此正文增删一条事实不会引起整表漂移 | FR-1.2 / AC-1⑥ |
| I3 | **两侧对同一条事实只给一个强度**：`commit SHA` 写侧保持必填、评侧由「并可附」改必填；评侧判据是「引用必须已定义」的**关系式**，不再只是「是否漏列」的**集合比较** | FR-2.2 / FR-2.3 / FR-2.4 / AC-2②③④ |
| I4 | **闭合必须发生在 SDD 阶段**：状态链类 blocker 必须整体重证、批准范围四字段冲突必须在本阶段成为 blocker——不得把同根因问题推迟到 dev-plan | FR-4 / FR-5 / AC-4 / AC-5② |

四条不变量共同把「可判定的承载体」钉在**既有段落内部**（不新增小节、不重编号 Step、不新增任何结构件），这也正是本 CR 的边界（FR-7 / AC-7 / AC-9）。

## 1.2 变更面鸟瞰

**一段四文件的纯文本原位修订**，交付 diff 只有两个 SKILL + 一个既有测试文件 + 一个既有门禁登记文件：

```text
../tools（4 个交付文件；本 CR 的代码实施面全部在此）
  skills/develop/write-tech-design/SKILL.md                    ← FR-1 / FR-4 / FR-5（写侧：3 处段落 + 章节 9 末追加）
  skills/develop/review-tech-design/SKILL.md                   ← FR-2 / FR-5（评侧：Step 2.1 两段 + 批准范围前置块）
  skills/shared/crctl/scripts/test/pipeline-structure.test.mjs ← FR-6.1（L616 目标用例两组 term 原位改写）
  skills/shared/crctl/scripts/test/gate-registry.json          ← FR-6.2（manifest.cases["pipeline-structure.test.mjs"] 35 → 36）
ai-first-platform-docs（KB：只承载本 CR 过程产物，不改 specs/ delivery/ docs/）
  change-requests/CR-2026-067/{prd.md（冻结，零触碰）, sdd.md（本文档）, cr.md + _backlog.yml（crctl 独占写）}
../multica：零 diff（不改任何 Agent Prompt 部署副本、不改 Go/TS 代码、不改 CUSTOM.md）
```

**改动量上界**：写侧 3 处段落原位修订（Step 2.6 证据段 / `### 既有实现依赖与事实` 小节 / 回修模式句）＋ 章节 9 末追加一组判据；评侧 2 处段落原位修订（Step 2.1 两段 + Step 2 批准范围前置块末追加同一组判据）；测试 1 个既有用例的两组 term；门禁登记 1 个数值。**无新增文件、无删除文件、无新增小节、无 Step 重编号。**

## 1.3 依赖方向与分层（不变）

```text
Pipeline（pipeline-templates/*.pipeline.json）   编排 Skill 调用顺序（本 CR 零 diff）
   ↓
Skill（write-tech-design / review-tech-design）  提示词合约 ← 本 CR 唯一的改动层
   ↓
crctl（crctl.mjs + lib/**）                      状态与账本唯一写入执行器（本 CR 零 diff）
```

三条对本设计的硬约束（来自 `ARCHITECTURE.md` §4 与 §5，本轮逐条实读）：

- **Skill 通用、约束归仓（不变量 8）**：新增文本只描述通用写作/评审判据，不出现任何使用方仓库的产品专属约束（表结构、迁移框架、锁原语、DDL 规范）；本 CR 的两份 SKILL 不新增任何产品专属名词。
- **状态单一写者与账本单一写入通道（不变量 1、2）**：本 CR 不新增状态写入口、不新增账本字段；两份 SKILL 的写入仍唯一经 `crctl`（评审批注唯一经 `crctl review-record` 落盘），本 CR 只改判据文本，不改任何写入路径。
- **零第三方依赖（不变量 3）与行尾/硬失败纪律（不变量 4）**：测试改动保持既有 `readFileSync(...).replaceAll('\r\n', '\n')` 读取形态与 `assert.ok` 硬失败语义——断言不命中即红，不引入新依赖、不引入"匹配不到 → 静默通过"的降级。

## 1.4 关键流程

### 1.4.1 写侧：`dep-N` 的分配、定义与引用（FR-1）

```text
作者写 SDD：
  ① 覆盖判定：断言命中「既有实现（仓库/路径/符号/配置键/接口·协议/数据库结构/模块行为/调用顺序/责任边界）且是方案成立前置条件」
  ② 两遍法：先按正文顺序识别事实 → 分配 dep-N（首轮 dep-1 起；回修轮取「表中现有最大编号 + 1」续编，不得复用空洞）
  ③ 表内定义一次（五要素齐全；commit SHA 为必填 40 位 SHA）
  ④ 正文该处改写成「设计依赖 dep-N」（不重述「当前代码已经如何工作」）
  ⑤ 自检关系式：正文出现的每个 dep-N 都已在表中定义；无法绑定字段的引用列入待核实依赖且不作为方案前提
判据落点：Step 2.6 证据段 + `### 既有实现依赖与事实` 小节（同一段落群内两处原位）
```

### 1.4.2 评侧：关系式核验与诚实边界（FR-2）

```text
reviewer 核验（Step 2.1，五步，全部在既有段落内）：
  ① 小节存在且名为“既有实现依赖与事实”（显式小节）
  ② 逐项五要素核验（repo / relative path / stable symbol-对象 / commit SHA / 依赖结论），commit SHA 必填（缺失或与取证结果不符 → blocker）
  ③ 关系式：正文出现的 dep-N 必须在表中已定义 —— 未定义即事实引用无承载 → blocker
  ④ 反向：正文出现未被 dep-N 引用承载的当前实现事实 → blocker（集合比较升级为引用关系）
  ⑤ 取证边界不变：不扫描全仓库、不猜测未写出的依赖；取证只读（受控 rev-parse + 文件/稳定符号核验）、不执行 lint/build/test
诚实边界（写进 SKILL 文本）：这是 Prompt 合同，不宣称对自由文本事实的机械识别；不新增 crctl 校验面 / lint 规则 / annotation dimension
```

### 1.4.3 回修：整体重证 + 不扩散（FR-4）

```text
blocker 触及「状态判定 / 活动性 / 事件顺序 / 空值 / 失败回流」
  → 必须重证该状态链的完整输入维度、分支、可见动作与对应 AC（不是只修被点名的一格）
  → 同一标识符 / 锚点 / testid 在全文只有一个裁决
与既有「不无理由重写已确认方案」的关系：两个方向同时约束——整体重证 ≠ 借重证之名重写无关设计
```

### 1.4.4 批准范围四字段自洽（FR-5，写手与 reviewer 同判据）

```text
四字段（既有集合）= scope_in / scope_out / zero_diff / follow_up
冲突四型：
  ① scope_in 与 zero_diff 对同一对象同时要求「修改」与「不修改」
  ② 外部治理规则强制修改，未在 SDD 阶段纳入 scope_in / 修订 zero_diff / 给出已有合法出口
  ③ 用 scope_out 隐藏当前交付必须发生的治理修改
  ④ follow_up 承载当前 AC 的必要条件
两侧同判据（逐条同表述、同字段名）→ 评侧任一一型命中 = SDD 阶段 blocker
  （不得留到 dev-plan 再由 review-dev-plan 的 upstream-design-blocker 轨触发）
边界：只针对四字段之间的自相矛盾与必需条件错位，不针对详尽程度
```

### 1.4.5 断言与门禁基线同步（FR-6）

```text
L616 目标用例：两组 term 原位改写（用例名保持、不新增第二个反向用例、顶层用例数 36 不变）
gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]：35 → 36（与实测顶层用例数一致）
suite-gate 判据语义不变（f.cases < base 即 SUITE_MANIFEST_CASE_DROP），exceptions 保持 []
```

## 1.5 与 PRD §1.5 六条裁定的承接

| PRD §1.5 | SDD 落点 |
|---|---|
| 第 1 条：写侧 `commit SHA` 本就必填，真正收口在评侧 | §6.5-A 保留写侧必填并把依赖形态换成 `dep-N`；§4.2 与 §6.5-E1 把评侧「并可附 `commit SHA`」改为必填（本 CR 唯一的强度变化，兼容性见 §7.3） |
| 第 2 条：`manifest.cases` 登记 35 / 实测 36，采用同步口径 | §4.5、D-5、AC-6③；不在本 CR 改 `suite-gate.mjs` 的判据语义 |
| 第 3 条：`quality-reviewer-agent.md#评审判断` 不存在 ⇒ 该 Agent Prompt 零改动 | §9 `zero_diff`、AC-3②、依赖第 9 项 |
| 第 4 条：`dep-N` 稳定性口径（正文首次出现顺序分配、只增不改、删除留空洞不复用） | I2、§2.2、§4.1、AC-1⑥ |
| 第 5 条：反向 token 约束是**保持性**约束（四个 review SKILL 现状 0 命中）；`write-tech-design` 现存 1 处 `crctl checkpoint` 句**不删** | §4.6、§7.2、AC-2⑦、AC-8② |
| 第 6 条：FR-5 不得把 Step 2.3 的分级边界扩大为「不够详细即 blocker」 | §4.4 末句、AC-5①、依赖第 8 项 |

**附带项（非阻塞 S-1）的处理**：PRD §5 末段「来源 §5.5 的七条验收与上表一一对应」与来源 §5.5 实际的 8 条 bullet 不符。本 SDD **按实际 8 条理解**（AC-1~AC-8 覆盖完整：第 1 条拆为 AC-1/AC-2、第 6 条拆为 AC-7/AC-8，其余逐条对应），并**保留理由**：该处属需求文本、且 `prd.md` 已随需求审批冻结（改哈希即作废审批），修它超出本 CR 的设计范围；判据面不受影响（§6.2 的 AC 映射以 9 条 AC 为准）。

# 2. 数据模型

## 2.1 无新增实体、字段与账本（NFR-2 落点）

本 CR 不新增 pipeline 节点、评审维度名、账本字段、观测指标、crctl 子命令 / flag / 错误码、Skill 参数、落盘文件、lint 规则、CI step。第 2 节因此不定义新实体，只固定三处**既有结构在本 CR 中的精确形状**——它们是实现唯一性的来源，也是 AC-1 / AC-2 / AC-6 的观测面。

## 2.2 `dep-N` 条目（本 CR 唯一改动的"数据形状"）

这是**文本结构**（SKILL 文本内的条目形态），不是账本 / annotation / Skill 参数的字段变更，因此不与 NFR-2 的"零新增字段"冲突：

```text
dep-N                          ← 条目首行：稳定标识，N 为正整数，按正文首次出现顺序分配
  repo: <repository id>        ← 字段 1（必须匹配 resources[].repo）
  relative path: <path from repository root>   ← 字段 2
  stable symbol/对象: <symbol, key, interface, module, behavior, or responsibility>  ← 字段 3
  commit SHA: <40-character SHA>               ← 字段 4（必填）
  依赖结论: <verified current behavior required by this design>                       ← 字段 5
```

| 面 | 目标口径 |
|---|---|
| 标识 | `dep-N` 独立首行；旧 `1. repo: …` 的阿拉伯数字前缀**退役**（`1.` 不再是合法条目起始形态） |
| 字段名 | 五字段名与小节名 `### 既有实现依赖与事实` **逐字不变**（`repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论`） |
| 编号生命周期 | 分配（正文首次出现顺序）→ 定义（本节一次）→ 引用（正文「设计依赖 `dep-N`」）→ 删除（留空洞，编号不复用） |
| 排序 | 既有约束「按正文首次出现顺序」保留；表序 = 编号序 = 正文首现序 |
| 消费口径 | `sdd.explicit_existing_dependencies` 仍只指本节的**有序清单**，语义不变 |

## 2.3 既有结构引用（只读，逐字沿用）

| 既有结构 | 位置 | 本 CR 的处理 |
|---|---|---|
| `sdd.explicit_existing_dependencies` | `write-tech-design` 依赖小节 + `review-tech-design` Step 2.1 | 消费口径逐字不变（仍指有序清单） |
| 评审批注结构（`verdict` / `blockers` / `dimensions` / `suggestions`） | `review-annotations/sdd.yml`（经 `crctl review-record` 落盘） | 零改动；本 CR 不新增 dimension、不改 schema |
| `manifest.cases` / `exceptions` | `skills/shared/crctl/scripts/test/gate-registry.json` | 只改一个数值（35 → 36）；`exceptions` 保持 `[]` |
| 用例数下界判据 | `skills/shared/crctl/scripts/test/suite-gate.mjs` | 零改动（判据语义"低于登记值即红"保持） |

## 2.4 状态与门禁（不新增状态、不新增转换）

本 CR 只消费既有声明，不新增任何状态或转换（口径以 `../tools/dir-graph.yaml#change-request-track.state_machine` 为唯一事实源）：

```text
requirement-approved → tech-designing             trigger: write-tech-design
tech-designing       → tech-design-review-pending trigger: write-tech-design-complete
tech-design-review-pending → tech-designing        trigger: review-tech-design:block -> write-tech-design
tech-design-review-pending → tech-design-reviewed  trigger: approve-tech-design（人工，非本节点）
```

门禁事实（`skills/shared/crctl/gates.json`）：`tech-design-review-pending` 的门禁是 `sdd.md` 存在（`fileExists`）；`tech-designing` 的门禁是 `approval.yml#requirement`。本 CR 不改 `gates.json`，落盘 `sdd.md` 即满足待评门禁。

# 3. 接口契约

## 3.1 Skill 调用契约：零变化（PRD §1.3.3）

| 契约面 | `write-tech-design` | `review-tech-design` |
|---|---|---|
| 参数表 | `cr_id` / `tech_context` / `operational_workspace` / `resources` / `review_feedback` / `self_repair_attempt` 不变 | `cr_id` / `workspace` / `resources` / `reviewer` / `review_feedback` / `self_repair_attempt` 不变 |
| 落盘路径 | `change-requests/{cr_id}/sdd.md` 不变 | canonical 仍为 `review-annotations/sdd.yml`（`crctl review-record` 独占写） |
| 允许的状态转换 | `requirement-approved → tech-designing → tech-design-review-pending` 不变 | PASS 保持待评状态、BLOCK 回退 `tech-designing` 不变 |
| 失败码 / 与 crctl 的写入边界 | 不变 | 不变 |

本 CR 改的是两份 SKILL **正文内的写作与评审判据**（Prompt 合同），不是调用契约——因此 §1.3.3 的四查（幂等 / 权限 / 错误闭包 / 副作用）对本 CR 为 N/A 的结论不受本设计影响。

## 3.2 crctl CLI 契约：零变化

`skills/shared/crctl/scripts/crctl.mjs`、`scripts/lib/**`、`gates.json`、`rules.json` 零 diff：不新增/删除子命令与 flag，不改任何 JSON 输出形状、退出码、错误码与调用者约束。本 CR 自身的过程写入只用既有子命令（`crctl advance` / 既有受控 git 提交）。

## 3.3 文本合同面（本 CR 的"接口"）

本 CR 的"接口"是**两份 SKILL 的目标文本 + 一处既有断言**，全部为逐字可核对的文本合同，目标文本见 §6.5：

| 锚点 | 文件 | 目标（§6.5 编号） |
|---|---|---|
| Step 2.6 既有实现证据段 | `write-tech-design/SKILL.md` | A |
| `### 既有实现依赖与事实` 小节（含固定结构块） | 同上 | B |
| 回修模式句 | 同上 | C |
| Step 2 章节 9「批准范围」末追加 | 同上 | D |
| Step 2.1 既有实现依赖核验两段 | `review-tech-design/SKILL.md` | E1 |
| Step 2「批准范围前置」引用块末追加 | 同上 | E2 |
| L616 目标用例两组 term | `pipeline-structure.test.mjs` | F |
| `manifest.cases["pipeline-structure.test.mjs"]` | `gate-registry.json` | G |

## 3.4 错误语义

本 CR 不新增错误码、不改任何退出码。唯一与"错误语义"相关的既有面是**测试断言的硬失败语义**：term 不命中即 `assert.ok` 失败（红灯），不存在"匹配不到 → 空集 → 静默通过"的降级路径（NFR-5）；本 CR 的 term 改写保持这一形态。

## 3.5 HTTP / IPC / 事件契约：N/A

本 CR 不改任何 endpoint / request / response、不改 IPC、不改事件接口（与 PRD §1.3.3 的四查 N/A 结论一致）。

# 4. 关键算法与流程

## 4.1 写侧 `dep-N` 分配算法（FR-1.2 / FR-1.3）

```text
procedure assign_dep_ids(sdd_body, dep_table):
    next = max(id_of(entry) for entry in dep_table) + 1     # 首轮 dep_table 为空 → next = 1
    for fact_assertion in scan_in_body_order(sdd_body):     # 按正文顺序扫描，不去重跨段重复引用
        if not is_existing_implementation_fact(fact_assertion):
            continue                                        # 目标契约/新增能力设计不分配 dep-N
        if fact_assertion is already defined in dep_table:
            rewrite(fact_assertion, "设计依赖 dep-N_of(that_entry)")
            continue
        id = "dep-" + next; next = next + 1
        dep_table.append(entry(id, repo, relative_path, stable_symbol, commit_sha(40), conclusion))
        rewrite(fact_assertion, "设计依赖 " + id)            # 正文不重述「当前代码已经如何工作」
```

不变量（评审侧可判定）：

- `∀ ref ∈ dep_refs(body): ref ∈ ids(dep_table)`（引用必须已定义）；
- 回修轮只**续编**（`next = max + 1`），不重编号、不复用空洞——保证同一 `dep-N` 在全文只指向一条事实；
- 无法绑定五要素中任一项的引用 → 待核实依赖（不作方案前提）；`N/A` 只在两处均无依赖时可用。

## 4.2 评侧核验算法（FR-2）

```text
procedure verify_existing_dependencies(sdd, resources):
    section = find_explicit_section(sdd, "既有实现依赖与事实")
    if section is null: blocker("缺少显式依赖小节")            # 既有判据保持
    for entry in section.ordered_entries():
        assert_five_fields(entry)                              # repo / relative path / stable symbol-对象 / commit SHA / 依赖结论
        if entry.commit_sha is missing or not 40-hex:
            blocker("commit SHA 缺失或非 40 位")                # 旧「并可附」措辞零残留是本条的可机械核对面
        verify(entry.repo, entry.relative_path, entry.stable_symbol, entry.conclusion)  # 受控只读：rev-parse + 文件/符号核验
    for ref in dep_refs(sdd.body):
        if ref not in ids(section): blocker("正文引用的 dep-N 未定义")   # 关系式，新增
    for fact in existing_facts(sdd.body):
        if fact not carried_by_dep_ref(fact): blocker("正文出现未被 dep-N 引用承载的当前实现事实")  # 集合比较 → 关系式
    # 边界（保持）：不扫描全仓库、不猜测未写出的依赖、不执行 lint/build/test
    # 诚实边界：判定属评审判断，本规则是 Prompt 合同，不宣称对自由文本事实的机械识别
```

## 4.3 回修整体重证（FR-4）

触发面（blocker 文本命中任一）：状态判定 / 活动性 / 事件顺序 / 空值 / 失败回流。要求：

1. 重证该状态链的**完整输入维度、分支、可见动作与对应 AC**——不是只补被点名的那一格；
2. 同一标识符、锚点或 testid 在全文只有一个裁决（同对象不得两处裁决）；
3. 未受该根因影响的已确认方案不得重写（"不扩散"方向同时生效）。

与既有 `reviewLoop`（`maxAttempts=3`、`replayNodes=write-tech-design → review-tech-design`）的关系：本 CR **不改**轮次语义、不新增 blocker 计数或轮数门禁，只改回修动作的判据文本。

## 4.4 批准范围自洽（FR-5）

写手侧与 reviewer 侧使用**同一组判据、同一表述、同一字段名**（§6.5-D 与 §6.5-E2 的 ①~④ 逐字相同）。评侧命中任一一型即形成 blocker，且必须在本阶段形成：

```text
① scope_in ∩ zero_diff 对同一对象同时要求「修改」与「不修改」        → blocker
② 外部治理强制修改未纳入 scope_in / 未修订 zero_diff / 未给出已有出口 → blocker
③ scope_out 被用来隐藏必须发生的治理修改                            → blocker
④ follow_up 承载当前 AC 的必要条件                                  → blocker
禁止留到 dev-plan 的 review-dev-plan:upstream-design-blocker 轨
```

**边界（PRD §1.5 第 6 条）**：判据只针对四字段之间的自相矛盾与必需条件错位（可判定），**不**针对详尽程度——不得把 `review-tech-design` Step 2.3 的既有分级边界（"缺少里程碑 / TASK owner / 任务拆分 / 工时 / 完成标志 / `cmd-NN` / cwd-timeout / 具体测试文件或完整执行命令不得作为 blocker"）扩大为"范围字段写得不够详细即 blocker"。

## 4.5 测试断言与门禁基线同步（FR-6）

1. L616 目标用例的两组 term 原位改写（§6.5-F）：用例名保持 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确`，**不新增第二个反向用例**，顶层用例数保持 36；
2. `gate-registry.json` 的 `manifest.cases` 由 35 同步为 36（与实测一致，§6.5-G）；
3. `suite-gate.mjs` 判据语义（`f.cases < base` 即 `SUITE_MANIFEST_CASE_DROP`）**不改**，`exceptions` 保持 `[]`；
4. CI 六个 step（双平台）全绿；`contract-scan` 的 `RETIRED_RECOVERY` 整树零命中。

## 4.6 零 diff 面与保持性约束（FR-7 / AC-8）

- **零 diff 面**见 §9；其中 AC-8 的核心是"CR-2026-066 的既有断言未被放宽"：四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账四要素（`phase` / `batchId` / `repositories[]` / `metadataCommit`）、BLOCK 分支不发布、权限面四处载体全部逐字保留。
- **反向 token 保持性**：本 CR 在 `review-tech-design` 中的**新增文字**不得出现 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（现值四 token 各 0 命中，§6.5-E1/E2 逐字自查通过）；`write-tech-design` 现存 1 处 `crctl checkpoint` 提交口径句**不删**（不在 CR-2026-066 的 `REVIEW_SKILLS` 反向断言面内）。

# 5. 技术选型与替代方案

## D-1 承载体：原位收紧既有 Step 2.x 判据（选定）

- **Decision**：两组判据全部写进既有段落内部——写侧 Step 2.6 证据段、依赖小节、回修句、章节 9；评侧 Step 2.1 两段、批准范围前置块。
- **Context**：三项问题的共同根因是"判据缺一个可判定的承载体"；既有 Step 2.x 已是唯一被两侧消费的判据面（`review-tech-design` 只读 `sdd.explicit_existing_dependencies` 指向的有序清单）。
- **Alternatives**：（a）新增独立小节承载 `dep-N` 规则 → 否决：违反 FR-7.1/FR-7.4 与 NFR-3（会出现新旧两套判据并存）；（b）新增 annotation dimension 或 crctl 校验面把判据机械化 → 否决：FR-2.6 明写本规则是 Prompt 合同、不宣称机械识别，且违反 FR-7.3/FR-7.4；（c）把规则复制进 `tools/agents/quality-reviewer-agent.md` → 否决：FR-3.2 要求该 Prompt 零 diff（唯一事实源是 review SKILL）。
- **Consequences**：判据的"存在性"可由文本断言机械核对（AC-1/AC-2/AC-4/AC-5），"是否真命题"仍由 reviewer 判断——这正是 PRD 的取舍。

## D-2 标识形态：`dep-N` 独立首行（选定）

- **Decision**：条目以 `dep-N` 开头，五字段改为缩进两格；旧 `1. repo:` 前缀退役。
- **Context**：既有"位置序号"（`1.` `2.`）不是身份——正文增删一条即整表漂移，reviewer 无法用一个稳定 key 交叉核对。
- **Alternatives**：（a）保留 `1. repo:` 序号 + 另加 `dep-N` 别名 → 否决：两个编号面并存，漂移面翻倍，违反 NFR-3；（b）改成 `<dep-N> repo: …` 单行形态 → 否决：会改动字段名可见形态，扩大 diff 与断言面；（c）用 `D-1` / `DEP-001` 等别名 → 否决：与 PRD FR-1.3 明文形态冲突且无收益。
- **Consequences**：`dep-N` 成为全文唯一裁决点（AC-4③），测试 term 组新增 `dep-N`（AC-6①）。

## D-3 评侧判据：引用关系式（选定）

- **Decision**：判据从"正文同类事实是否漏列"的集合比较，升级为"正文引用是否由 `dep-N` 承载"的关系式；旧表述作为该关系式的退化面在新文本中显式保留（"判据从…升级为…"）。
- **Context**：集合比较缺一条可判定的关系式——同一份合同下，作者按写侧写、评审按评侧放宽，闭合无从机械判定。
- **Alternatives**：（a）只把评侧 `commit SHA` 改必填、不动判据形态 → 否决：解决不了"缺关系式"的根因（来源 §5.1.2）；（b）让 reviewer 做全仓扫描来发现漏列 → 否决：PRD 明确边界"不扫描全仓库、不猜测未写出的依赖"。
- **Consequences**：评侧新增两条可判定关系（引用已定义、事实被引用承载），并有明确的诚实边界（Prompt 合同、非机械门禁）。

## D-4 编号生命周期：只增不改 + 删除留空洞（选定）

- **Decision**：`dep-N` 按正文首次出现顺序分配、只增不改；删除的条目留空洞、编号不复用。
- **Context**：来源只写"稳定标识"，未写生命周期；不钉死则 `dep-N` 只是把"序号漂移"换成另一个编号面。
- **Alternatives**：（a）每次修订重编号 → 否决：重编号即漂移，与"稳定标识"意图相反；（b）回收空洞编号 → 否决：同一编号会在两次修订间指向不同事实，破坏评审可对比性；（c）追加式编号但允许重排序 → 否决：与既有"按正文首次出现顺序"排序约束冲突。
- **Consequences**：表序 = 编号序 = 正文首现序，评审可按序核对（AC-1⑥）。

## D-5 `manifest.cases` 收口方向：同步为实测值（选定）

- **Decision**：把 `manifest.cases["pipeline-structure.test.mjs"]` 由 35 同步为 36（与实际顶层用例数一致）。
- **Context**：`suite-gate` 的判据是下限（`f.cases < base` 才红，`manifest.cases` 只校验正整数），因此多出的 1 条用例（CR-2026-066 追加）不触发红灯，但登记值与实际不一致本身就是事实缺口；来源 §5.5 的验收写"已同步"。
- **Alternatives**：（a）保留 35 并注明语义是下界 → 否决：与来源验收的"已同步"相悖，且未来用例回落到 35 条时红灯的判据会变得不可解释；（b）把 `suite-gate.mjs` 判据改为严格相等 → 否决：FR-6.4 明写不改判据语义、不新增门禁机制。
- **Consequences**：交付 diff 增加一个数值改动（PRD §1.3.1 第 4 行已登记为条件性文件）。

## D-6 本 CR 自身 SDD 的依赖表形态：沿用实施前的编号列表（选定）

- **Decision**：本文档 §6.3 仍使用**实施前生效**的编号列表形态（`1. repo: …`，五要素齐全、`commit SHA` 必填），并在 §6.3 节首写明该取舍；正文以显式事实陈述引用，不采用尚未生效的 `dep-N` 引用式。
- **Context**：目标 `dep-N` 形态在本 CR **实施落地后**才成为合同；PRD §1.3.3 已确立"评审判据只对评审发生时的 SKILL 版本生效"。
- **Alternatives**：（a）提前使用 `dep-N` 形态 → 否决：会以尚未生效的合同自我验收，且正文若只写"设计依赖 `dep-N`"将无法陈述"当前文本是什么"这一本 CR 的核心输入；（b）不写依赖表 → 否决：现行 Step 2.6 明确要求，且 reviewer 会按现行合同核验。
- **Consequences**：本 SDD 与目标文本（§6.5 逐字给出）之间的差异是**合同的时序差**，不是判据并存：`dep-N` 形态自实施提交起对其后的 SDD 生效。

# 6. FR 到技术实现映射

## 6.1 FR 逐条映射

| FR | 设计落点 | 承载文件 | 对应 AC |
|---|---|---|---|
| FR-1 既有实现事实唯一表达 | §2.2 条目形状 + §4.1 分配算法 + §6.5-A/B | `write-tech-design/SKILL.md` | AC-1 |
| FR-2 评侧 `dep-N` 核验与两侧同口径 | §4.2 核验算法 + §6.5-E1 | `review-tech-design/SKILL.md` | AC-2 |
| FR-3 首轮全量检查保持原样 | §4.6 保持性约束 + §6.4 零改动核对清单 | `review-tech-design/SKILL.md` Step 2.2 / `agents/quality-reviewer-agent.md` | AC-3 |
| FR-4 状态链整体重证 | §4.3 + §6.5-C | `write-tech-design/SKILL.md` | AC-4 |
| FR-5 批准范围四字段自洽 | §4.4 + §6.5-D/E2 | 两侧 SKILL（同判据） | AC-5 |
| FR-6 测试断言与门禁基线同步 | §4.5 + §6.5-F/G | `pipeline-structure.test.mjs` / `gate-registry.json` | AC-6 |
| FR-7 边界与零新增 | §4.6 + §9（scope_out / zero_diff） | 交付 diff 面本身 | AC-7 / AC-9 |

## 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §6.5-A（Step 2.6 证据段）＋ §6.5-B（依赖小节固定结构） | 小节存在且采用 `dep-N` 固定结构（`dep-N` + 五字段齐全）；正文规则含"只写设计依赖 `dep-N`、不重述当前代码行为"与"事实只在该表定义一次"；`commit SHA` 为必填 40 位 SHA；无法绑定字段者列入待核实依赖且不得作为方案前提；`N/A` 仅在两处均无依赖时可用；编号稳定性口径（首次出现顺序分配、只增不改）已写明 | 六项判据全部落在**同一段落群**的文本上，可由文件读出直接核对；不依赖运行时状态；编号稳定性是写作侧机械规则（§4.1），不要求 reviewer 机械复核 |
| AC-2 | §6.5-E1（Step 2.1 两段） | ① 五要素核验在文；② 含"正文只能引用存在的 `dep-N`"；③ 含"未被 `dep-N` 引用承载的当前实现事实 → blocker"；④ `commit SHA` 必填且旧「并可附 `commit SHA`」措辞零残留；⑤ 保留"不扫描全仓/不猜测未写出的依赖"边界并写明 Prompt 合同、不宣称机械识别；⑥ Step 编号集（1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6）全部存在；⑦ 新增文字不含四个反向 token | ①~⑤ 为文本断言；④ 的"零残留"是全局替换判据（`grep -c '并可附'` 应为 0）；⑥⑦ 分别由节标题集合与 token 扫描核对；均可在 CI 内执行，无外层依赖 |
| AC-3 | §4.6 保持性清单 + §6.4 零改动面 | ① Step 2.2 首轮全量句逐字存在；② `agents/quality-reviewer-agent.md` 相对基线零 diff（`##` 小节集合仍为 7 个）；③ 交付物中不存在"首轮漏检"账本计数、`本轮新增：` 不作为流程质量统计、无评审轮数数字承诺 | ①② 是 CR-2026-066 既有断言的保持性核对（该文件不在本 CR diff 面内）；③ 由"本 CR 不新增任何账本字段/观测指标"（§2.1、§9 scope_out）保证 |
| AC-4 | §6.5-C（回修句原位扩写） | 该段同时含四项判据：状态链类 blocker 必须重证完整输入维度/分支/可见动作/对应 AC；不得只修被点名的一格；同一标识符/锚点/testid 全文只有一个裁决；未受根因影响的已确认方案不得重写 | 四项全部写进**同一句群**；既有"不无理由重写已确认方案"句保留作"不扩散"方向的判据，两方向同时成立 |
| AC-5 | §6.5-D（写侧章节 9）＋ §6.5-E2（评侧前置块） | ① 两侧均含四条同判据且表述与字段名一致；② 评侧要求冲突在 SDD 阶段成为 blocker、不留到 dev-plan upstream；③ 无第五字段、无新账本文件、无新评审维度名、无新状态 | ① 由两侧 ①~④ 段落**逐字相同**保证（可 diff 核对）；② 写在评侧同段；③ 由 §9 与交付 diff 面保证 |
| AC-6 | §6.5-F / §6.5-G + §4.5 | ① 目标用例仍在且两组 term 已改 `dep-N` 口径（写侧覆盖小节名 + `dep-N` 固定结构 + 五字段；评侧覆盖显式小节 + 有序清单 + `dep-N` 引用规则 + `commit SHA` 必填 + `sdd.explicit_existing_dependencies` + 正文漏列）；② 顶层用例数不减少（基线 36）、无第二个反向用例；③ `manifest.cases` 与该文件实际顶层用例数一致（36）；④ `suite-gate --run` 全绿、`exceptions` 为空数组；⑤ `RETIRED_RECOVERY` 整树零命中 | ①~③ 可由测试文件与登记文件直接读出；④ 由既有门禁运行；⑤ 由既有 `contract-scan` 用例运行；本 CR 不新增测试脚手架，全部复用既有入口 |
| AC-7 | §1.2 变更面 + §9（scope_in / scope_out / zero_diff） | ① diff 只含 4 个登记文件；② `crctl.mjs`/`lib/**`/`gates.json`/`pipeline-templates/**`/`agent-skill-matrix.yml`/`AGENT-SKILL-MATRIX.md`/`tools/agents/**`/`../multica/**` 零 diff；③ 无新 annotation dimension/账本字段/评审指标/Pipeline 节点/crctl 子命令·flag·错误码/Skill 参数/落盘文件 | ① 可用 `git diff --name-only` 枚举；② 为 §9 `zero_diff` 表的直接核对；③ 由变更面本身证明（diff 只有 4 文件） |
| AC-8 | §4.6 + §6.4 | CR-2026-066 既有断言实施后仍全绿且未被放宽：四个 review SKILL 的 Step 1.0 / Step 5 四要素逐字保留；四 SKILL 不含 `crctl checkpoint` 与三个 `push-progress`/`checkpoint` 短语；`REVIEW_SKILLS` 四处载体（clean 前置 / PASS 发布 / 对账 / BLOCK 不发布）零改动 | 全部由既有断言 A/B/C/D 覆盖（`pipeline-structure.test.mjs` L656 用例），本 CR 只改 L616 用例；"未放宽"体现为**断言未删未弱**（本 CR 不触碰该用例） |
| AC-9 | §9 + §6.6 | ① 交付 diff 不含 CR-P2 面（`write-dev-plan` / `write-dev-tasks` / `review-dev-plan` 与 `code-implementation.pipeline.json` 的 dev-start 提示）；② 实施与交付期 `_backlog.yml` 在途条目只有本 CR、CR-2026-063/064/065/066 均 `archived`；③ 只收紧不放宽：Step 2.1 的 AC 闭环伪码、Step 2.3 的分级边界与固定前缀句全部保留 | ① 由 diff 文件集枚举；② 由 `crctl status` 查询（可复算）；③ 由 §6.4 的零改动核对清单 + 交付前 diff 复核保证 |

**反查（§6.2 → §3/§4/§6.5 正文）**：每条 AC 的设计落点都能产出所写可观测结果，且不存在"关键前置条件提前过滤目标"的情形：

- AC-1/AC-2 的判据落在**同一文件的两处既有段落**上，不存在跨仓或运行时前置；`commit SHA` 必填的强度变化反向兼容（写侧本就必填，评侧只增不改）。
- AC-2⑥ 的 Step 编号集合是**静态文本事实**，不因本 CR 的段落增删而变（不新增标题层级）。
- AC-5① 用"两侧逐字相同"作为判据，规避了"同判据不同表述"的判定争议；AC-5③ 用"无第五字段/无新文件/无新维度名/无新状态"把扩大面挡在判据之外。
- AC-6④⑤ 依赖的既有门禁入口（`suite-gate --run`、`contract-scan`）在本 CR 中零 diff，不构成不可达前置。
- AC-9② 的"不并发"由已完成事实满足（063~066 均 `archived`，`_backlog.yml` 在途仅本 CR）；其证据在 KB，故列为过程核对项而非 tools 内断言。
- 唯一需要额外证成的是 AC-2④ 的"旧措辞零残留"——它是**全局**判据（`并可附` 计数为 0），可通过 §6.5-E1 的整段替换保证（替换的是包含该措辞的完整句子，不保留任何副本）。

## 6.3 既有实现依赖与事实

**收录判据（单一口径，与 CR-2026-066 SDD 同族）**：SDD 正文引用到的任一既有实现事实都必须入册——① 设计陈述或判据的成立前提（模块行为、文本形态、返回形状、调用顺序、抽取锚点）；② 本 CR 直接修改的既有文本；③ §9 `zero_diff` 中**设计所依赖的**既有实现文本（§9 其余零 diff 对象由该表自身与 AC-7②/AC-9① 的 diff 枚举直接核对，不逐项入册）；④ SDD-CLOSE 的证据。正文出现但未列入本清单的同类事实引用视为漏列。

**排序**：按仓与依赖面分组，组内按正文首次出现顺序排列。

**本 CR 自身依赖表的形态（D-6）**：本节使用**实施前生效**的编号列表形态（五要素齐全、`commit SHA` 必填）。目标 `dep-N` 形态（§6.5-B）自本 CR 实施提交起对其后的 SDD 生效；PRD §1.3.3 已确立"评审判据只对评审发生时的 SKILL 版本生效"，两者是合同的时序差，不是两套判据并存。

**SHA 取证口径**：`tools` 条目的 `commit SHA` = 本 CR tools worktree HEAD `7094e492822594b971699924478ba27ccf612c42`（= `tools` trunk）；`multica` 条目 = `5c1880f2125e73733b1a5bfc7501db310ab7f584`（= `multica` trunk）；KB（`ai-first-platform-docs`）条目 = 起草时 KB worktree HEAD `31db6d201f081d6e78a5fa73e6676d4fa55d319e`（与 CR-2026-066 SDD 的 KB 取证同口径），各 KB 过程产物的**引入提交**另在依赖结论中给出（`prd.md`→`d4f366fa`、评审三件套→`3b74b5ac`、`approval.yml`→`14c2b6c1`）。

1. repo: tools
   relative path: ARCHITECTURE.md
   stable symbol/对象: `## 4. 分层与依赖方向`（Pipeline → Skill → crctl「依赖只朝下」）与 `## 5. 硬不变量`（不变量 1 状态单一写者、2 账本单一写入通道、3 零第三方依赖、4 行尾与硬失败纪律、8 Skill 通用约束归仓）
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: §1.3 的三条硬约束与 §4.6 的保持性论证均取自本文件（本轮实读全文）；四条设计不变量不得与之冲突，本 CR 不新增层级、不新增写入口与账本文件。
2. repo: tools
   relative path: skills/develop/write-tech-design/SKILL.md
   stable symbol/对象: Step 2.6 既有实现证据段（L113）：五要素必填清单（含 `commit SHA`）、待核实依赖、`N/A` 可用条件、「核验必须覆盖正文所声称的实际行为」、「现有/既有/复用/无需新增」断言的前提资格约束
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-1.1 的「覆盖面不缩小」以该段为基线（§6.5-A 只在该段内插入三处判据，不改五要素清单与既有边界句）；也是 AC-1③ 强度口径的来源。
3. repo: tools
   relative path: skills/develop/write-tech-design/SKILL.md
   stable symbol/对象: `### 既有实现依赖与事实` 小节（L115-131）：固定结构块 `1. repo: …`（编号列表形态）、排序约束「正文首次出现顺序」、`sdd.explicit_existing_dependencies` 消费口径句、`N/A` 句、回修模式句（L129）、SDD-CLOSE 义务段（L131）
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-1.2/FR-1.3/FR-1.6/FR-1.7 与 FR-4 的修订面同在这一个小节内；§6.5-B（固定结构与消费口径句）与 §6.5-C（回修句）以它为基线，SDD-CLOSE 义务段保持零 diff。
4. repo: tools
   relative path: skills/develop/write-tech-design/SKILL.md
   stable symbol/对象: Step 2 章节 9「批准范围（契约必填章节，CR-2026-057 FR-5/FR-6）」（L88-90）：四字段承载与"空字段须写 `无`/`N/A`"的存在性判据、`approve-tech-design` 后只读、`review-dev-plan` 双轨回上游
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-5 写侧落点；§6.5-D 在该段末**原位追加**四条自洽判据，既有存在性判据与只读语义逐字保留（AC-9③ 的"只收紧不放宽"核对面之一）。
5. repo: tools
   relative path: skills/develop/write-tech-design/SKILL.md
   stable symbol/对象: Step 1 第 2 条提交口径句（L48，含 `crctl checkpoint` 的唯一 1 处）
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: §1.5 第 5 条与 AC-8② 的"不删该句"事实依据（实测 `grep -c 'crctl checkpoint'` = 1）；该句不在 CR-2026-066 的 `REVIEW_SKILLS` 反向断言面内（依赖第 12 项）。
6. repo: tools
   relative path: skills/develop/review-tech-design/SKILL.md
   stable symbol/对象: Step 2.1 既有实现依赖核验段（L87）：显式小节名、有序清单、四要素 + 旧措辞「并可附 `commit SHA`」、`sdd.explicit_existing_dependencies` 消费边界、「不扫描全仓库或临时猜测」、交叉检查「正文同类事实是否漏列」
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-2.1~FR-2.4 与 FR-2.6 的修订面；§6.5-E1 以该段为基线（旧「并可附」措辞在本 CR 后必须零残留）。
7. repo: tools
   relative path: skills/develop/review-tech-design/SKILL.md
   stable symbol/对象: Step 2.1 核验手段段（L89）：受控只读取证 `crctl git rev-parse HEAD`、文件/稳定符号核验、业务 blocker 的证据面（repo/SHA/path/symbol/conclusion）、资源缺失为技术失败、「正文存在但未列入依赖清单的同类事实引用形成 blocker」、`N/A` 句、「不执行 lint/build/test」
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-2.1/FR-2.3/FR-2.4 的取证与边界基线；§6.5-E1 只把其中的判据句升级为 `dep-N` 引用关系，取证手段与"不执行 lint/build/test"等边界逐字保留。
8. repo: tools
   relative path: skills/develop/review-tech-design/SKILL.md
   stable symbol/对象: Step 2 引用块「批准范围前置（CR-2026-057 FR-5/AC-5）」（L58）与 Step 2.3 分级段（L95-104）的固定前缀句
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-5 评侧落点（§6.5-E2 在 L58 引用块末原位追加同判据）；Step 2.3 的分级边界是 FR-5 判据的**上限**（§4.4 末句），零 diff。
9. repo: tools
   relative path: skills/develop/review-tech-design/SKILL.md
   stable symbol/对象: Step 2.2 首句（L93）与 Step 编号集合（Step 1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6）
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-3.1 与 AC-3① 的零改动核对对象（逐字断言）；FR-7.2 与 AC-2⑥ 的编号核对面（本 CR 不重编号、不新增标题层级）。
10. repo: tools
    relative path: agents/quality-reviewer-agent.md
    stable symbol/对象: `##` 小节集合（7 个：角色定位 / 意图与路由 / 独立会话路径 / 人工决策边界 / 权限事实源 / 发布职责与搭车硬规则 / 约束）；`## 评审判断` 小节不存在
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: FR-3.2 与 AC-3② 的零 diff 判据与"判据唯一事实源 = review SKILL"的成立依据（§1.5 第 3 条复核结论）；`评审判断` 一词仅出现在 `## 意图与路由` 一句内，来源 §5.2 的删除锚点确实不存在。
11. repo: tools
    relative path: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
    stable symbol/对象: L616 目标用例 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确`（写侧 8 项 term / 评侧 4 项 term）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: FR-6.1 的原位改写对象；§6.5-F 给出两组 term 的目标形态，用例名与结构保持。
12. repo: tools
    relative path: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
    stable symbol/对象: 顶层用例计数（`^test(` 实测 36 条、TAP `1..36` 全绿）与 `REVIEW_SKILLS` 常量（L636-641，四个 review SKILL）+ CR-2026-066 断言用例（L656，A/B/C/D）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: AC-6② 的基线（不减少、不新增）与 AC-8 的保持性核对面；`write-tech-design` 不在 `REVIEW_SKILLS` 中，是该文件现存 `crctl checkpoint` 句不在反向断言面内的直接依据（依赖第 5 项）。
13. repo: tools
    relative path: skills/shared/crctl/scripts/test/gate-registry.json
    stable symbol/对象: `manifest.cases["pipeline-structure.test.mjs"] = 35`（L38）与 `exceptions: []`（L243）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: FR-6.2 的唯一改动点（35 → 36）与 FR-6.3 的零例外约束（本 CR 不签例外）。
14. repo: tools
    relative path: skills/shared/crctl/scripts/test/suite-gate.mjs
    stable symbol/对象: 用例数下界判据（L448-453：`f.cases < base` → `SUITE_MANIFEST_CASE_DROP`）与 `manifest.cases` 校验（L123-126：只校验"缺基线/非正整数"）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §4.5/D-5 的取舍依据——判据是**下限**，故多出的 1 条不触发红灯，登记值与实际不一致仍是事实缺口；本 CR 不改该判据语义。
15. repo: tools
    relative path: skills/shared/crctl/scripts/test/contract-scan.test.mjs
    stable symbol/对象: `RETIRED_RECOVERY = ['recoverCommand', 'recover_command']`（整树扫描命中即红）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: AC-6⑤ 与 AC-7③ 的"不复活旧字段名"扫描依据；§6.5 的目标文本不含这两个词。
16. repo: tools
    relative path: skills/shared/crctl/scripts/lint-prompts.mjs
    stable symbol/对象: R1~R13 规则集（R2 裸 git、R7 `crctl advance --to/--trigger` 与 backlog-set 白名单、R9「下一步」收敛 `crctl next`、R12 状态机副本、R13 backlog 状态推断）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §6.6/NFR-1 的 CI 门禁面；§6.5 的目标文本按这些规则逐条自查（无裸 git 命令、无同段 3 个以上具名状态、无"下一步"映射副本、无 guard-deny 文件的手写指示）。
17. repo: tools
    relative path: .github/workflows/crctl-ci.yml
    stable symbol/对象: 六个 step（lint-prompts enforce → check-skill-matrix → check-agents-contract → pipeline JSON 结构断言 → `suite-gate.mjs --run` → writeback 单测）与 ubuntu/windows 矩阵
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: NFR-1 与 AC-6④ 的"CI 全绿、不签例外"验证面；本 CR 不新增 CI step。
18. repo: tools
    relative path: dir-graph.yaml
    stable symbol/对象: `change-request-track.state_machine.transitions` 的三条相关声明（`requirement-approved → tech-designing` trigger `write-tech-design`；`tech-designing → tech-design-review-pending` trigger `write-tech-design-complete`；`tech-design-review-pending → tech-designing` trigger `review-tech-design:block -> write-tech-design`）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §2.4 的三条转换全部为既有声明，本 CR 不新增/不改动状态机；两次状态推进都复用既有 trigger。
19. repo: tools
    relative path: skills/shared/crctl/gates.json
    stable symbol/对象: `statusGates["tech-design-review-pending"] = [{type: fileExists, path: change-requests/{cr}/sdd.md}]`、`statusGates["tech-designing"] = [{type: approval, section: requirement}]`、`approvalStages.tech-design`
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §2.4/§3.1 的门禁事实——SDD 落盘是待评状态的唯一门禁条件，需求审批段是 `tech-designing` 的门禁；本 CR 不改门禁声明（§9 `zero_diff`）。
20. repo: tools
    relative path: skills/shared/crctl/scripts/crctl.mjs
    stable symbol/对象: 状态与账本的唯一写入执行器（`advance` / `review-record` / `checkpoint` / `approve` / `gate` 等子命令的 dispatch 与事务层）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §9 `zero_diff` 点名对象；本 CR 的过程写入只走既有子命令，不新增命令面、不改错误码（§3.2）。
21. repo: tools
    relative path: skills/shared/controlled-shell/rules.json
    stable symbol/对象: `protectedPaths.deny` 与 `git[]` 白名单
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §8「Prompt 采纳影响」判 N/A 的判据面（本 CR 不触及 deny 面与 crctl dispatch），以及 §9 `zero_diff` 的守护声明。
22. repo: tools
    relative path: pipeline-templates/architecture-design.pipeline.json
    stable symbol/对象: `nodes[]`（4 节点：write-tech-design → review-tech-design → human_approval → approve-tech-design）与 `reviewLoop`（`maxAttempts=3`、`replayNodes=[write-tech-design, review-tech-design]`）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §4.3 的"本 CR 不改轮次语义"依据与 §6.6 的节点面；AC-7②/AC-9① 的 zero_diff 对象。
23. repo: tools
    relative path: agent-skill-matrix.yml
    stable symbol/对象: Agent/Skill 权限矩阵（`owns` / `can-call` / `forbidden` 与 reviewer 的只读约束）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: AC-7② 的 zero_diff 点名对象（本 CR 不改任何 actor 的权限面、不新增 Skill）与 `AGENT-SKILL-MATRIX.md` 派生表同批约束。
24. repo: tools
    relative path: skills/develop/write-dev-plan/SKILL.md
    stable symbol/对象: plan 写作合同（回修与 `crctl task init` 口径面）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: AC-9① 与 §9 `scope_out` 的点名对象（plan/TASK 写作合同归 CR-P2）；本 CR 零 diff。
25. repo: tools
    relative path: skills/develop/write-dev-tasks/SKILL.md
    stable symbol/对象: TASK 拆分与 `crctl task init/append` 口径面
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: 同第 24 项（CR-P2 面；本 CR 零 diff）。
26. repo: tools
    relative path: skills/develop/review-dev-plan/SKILL.md
    stable symbol/对象: `upstream-design-blocker` 轨与 acceptance-verifiability 面
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: FR-5 的判据落点边界——本 CR 不在该 Skill 内新增判据，只把"范围冲突必须在本阶段拦下"写进 `review-tech-design`（§6.5-E2）；该文件零 diff（AC-9①）。
27. repo: tools
    relative path: skills/requirement/review-requirement/SKILL.md
    stable symbol/对象: 需求评审 Skill（七个评审维度与固定前缀句的事实源之一）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §1.3.1「四个 review SKILL 中除 `review-tech-design` 外的三个零 diff」的点名对象；AC-8 的 `REVIEW_SKILLS` 四处载体之一。
28. repo: tools
    relative path: skills/develop/review-code/SKILL.md
    stable symbol/对象: 代码评审 Skill（PASS 分支与权限面载体）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: 同第 27 项（零 diff 与 AC-8 保持性核对面）。
29. repo: tools
    relative path: skills/sync/push-progress/SKILL.md
    stable symbol/对象: `crctl checkpoint` 的发布语义与参数面（`cr_id` / `message`）、"审批之后不再有 checkpoint 节点，未发布的审批提交由下一阶段评审 checkpoint 搭车承担"的既有口径
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: 本节点开工前的"上一阶段未闭合发布动作"按该 Skill 的既有语义收口（需求审批提交 `14c2b6c1` 经一次 checkpoint 发布为 batch `0afd3f235aaf3cfb`）；本 CR 不改该文件、不改发布口径。
30. repo: ai-first-platform-docs
    relative path: change-requests/CR-2026-067/prd.md
    stable symbol/对象: 冻结 PRD 本体（285 行 / 51,864 B / LF-only / `sha256(LF)` = `efde31fd0ce727ee58c733de6f97b464b95e069dcdfc615c71488113cbeb0fea`；引入提交 `d4f366fa`）
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: 本 SDD 的全部 FR/AC/§1.5 裁定输入；本 CR 不得触碰该文件（改哈希即作废人工审批，§9 `zero_diff`）；S-1 附带项按"不改 prd.md、按实际 8 条理解"处理（§1.5 末段）。
31. repo: ai-first-platform-docs
    relative path: change-requests/CR-2026-067/cr.md
    stable symbol/对象: frontmatter（`status` / `target-version: 0.40` / `target-spec-id: ai-first-platform` / 三角色 owners = Ray）
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: SDD frontmatter 的 `cr-ref` / `target-version` 继承源与状态推进的唯一权威；本 CR 的 status 写入只经 `crctl advance`。
32. repo: ai-first-platform-docs
    relative path: change-requests/CR-2026-067/review-annotations/requirement.yml
    stable symbol/对象: 需求评审 canonical 记录（`verdict: pass`、`blockers: []`、`dimensions` 八维、`subject-sha256` = PRD 哈希、`review-loop.current-attempt: 1`；引入提交 `3b74b5ac`）
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: 本 SDD 的设计输入前提（需求评审 PASS 且 0 blocker，评审对象与被冻结 PRD 同哈希）；本 CR 不改评审记录。
33. repo: ai-first-platform-docs
    relative path: change-requests/CR-2026-067/approval.yml
    stable symbol/对象: `requirement` 段（`approver: OldBoy405`、`via: crctl-approve`、`target-status: requirement-approved`、`evidence-digest`；引入提交 `14c2b6c1`）
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: `tech-designing` 门禁（`statusGates["tech-designing"] = approval/requirement`）的满足依据，也是本节点开工的前提；本 CR 不改该文件。
34. repo: ai-first-platform-docs
    relative path: change-requests/_backlog.yml
    stable symbol/对象: 在途 CR 条目集合与 `change-requests[].latest-checkpoint` 批次快照结构
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: AC-9② 的"在途只有本 CR、063~066 均 archived"核对面；本 CR 不手工编辑该账本（写入唯一经 crctl）。
35. repo: multica
    relative path: cr-prompts-revised/**
    stable symbol/对象: Agent Prompt 部署副本（`quality-reviewer-agent.md` / `dev-agent.md` 等）
    commit SHA: 5c1880f2125e73733b1a5bfc7501db310ab7f584
    依赖结论: AC-7② 与 §9 `zero_diff` 的点名对象（本 CR 不改任何部署副本；判据唯一事实源是 tools 侧 SKILL）。
36. repo: multica
    relative path: （Go/TS 代码与平台资产，如 `CUSTOM.md` / `aifirst/**`）
    stable symbol/对象: 产品代码与定制台账
    commit SHA: 5c1880f2125e73733b1a5bfc7501db310ab7f584
    依赖结论: §1.2/§9 的 multica 零 diff 声明；本 CR 不落任何 multica 代码，故不触发其 `CUSTOM.md` 登记义务。

## 6.4 既有测试面改动清单与零改动核对清单

**改动（1 个用例 + 1 个登记值）**：

| 位置 | 现状 | 目标 |
|---|---|---|
| `pipeline-structure.test.mjs` L616 写侧 term 组（8 项） | `['### 既有实现依赖与事实','正文首次出现顺序','repo:','relative path:','stable symbol/对象:','commit SHA:','依赖结论:','sdd.explicit_existing_dependencies']` | 追加 `'dep-N'`（其余 8 项逐字保留），见 §6.5-F |
| 同用例评侧 term 组（4 项） | `['名为“既有实现依赖与事实”的显式小节','有序清单','sdd.explicit_existing_dependencies','正文同类事实是否漏列']` | 原位改写为覆盖"显式小节 + 有序清单 + `dep-N` 引用规则 + `commit SHA` 必填 + `sdd.explicit_existing_dependencies` + 正文漏列"的 6 项，见 §6.5-F |
| `gate-registry.json` L38 | `"pipeline-structure.test.mjs": 35` | `36`（与实测顶层用例数一致） |

**零改动核对清单（AC-3 / AC-8 / AC-9③ 的核对面）**：

| 对象 | 零改动判据 |
|---|---|
| `review-tech-design` Step 2.2 首轮全量句 | 逐字存在（含"合并同根因问题、拆分不同根因问题"） |
| `review-tech-design` Step 2.1 AC 闭环伪码（缺设计落点 / 冲突 / 不可观察 / 不可达） | 逐字保留 |
| `review-tech-design` Step 2.3 分级边界与五个固定前缀 | 逐字保留，`本轮新增：` 仍只承担 blocker 文本分类 |
| 四个 review SKILL 的 Step 1.0 clean 前置 / Step 5 PASS 发布与对账四要素 / BLOCK 分支不发布 | 逐字保留（CR-2026-066 断言 A 覆盖） |
| `REVIEW_SKILLS` 四处载体的权限面（`agent-skill-matrix.yml` / `AGENT-SKILL-MATRIX.md` / `quality-reviewer-agent.md`） | 零 diff |
| `write-tech-design` Step 1 / 2.5 / 3 / 4 / 5 与 Step 2.6 的 AC 映射合同、AC 反查闭环、SDD-CLOSE 义务段 | 零 diff |
| `quality-reviewer-agent.md` 的 `##` 小节集合（7 个） | 零 diff（不新增小节、不复制判据） |

## 6.5 目标文本清单（实施时逐字写入）

> 说明：以下为**逐字目标文本**（设计产物）。`…` 表示"原文逐字不变、此处省略"；每处均为**原位替换或原位追加**，不新增小节、不重排 Step 编号。

### 6.5-A `write-tech-design/SKILL.md` — Step 2.6 既有实现证据段（L113）

**替换目标（整段）**：

```text
涉及既有实现（现有仓库、文件路径、稳定符号、配置键、接口/协议、数据库结构、模块行为、调用顺序或责任边界，且是方案成立前置条件）的断言，必须逐项附证据：`repo`、`commit SHA`、`relative path`、`stable symbol/对象`、`conclusion`；每条事实在 `### 既有实现依赖与事实` 表中获得稳定标识 `dep-N`（N 为正整数），其中 `commit SHA` 为必填的 40 位 SHA，编号按正文首次出现顺序分配、只增不改（正文增删条目不重编号，被删除的条目留下空洞、编号不复用）；实现事实只在该表定义一次，SDD 正文只能写「设计依赖 `dep-N`」，不得在正文重新陈述「当前代码已经如何工作」。无法绑定这些字段的引用按待核实依赖列出，不得归入 N/A。无既有实现依赖时才明确写 `N/A（本 CR 无既有实现依赖）`，不得用 N/A 掩盖正文中的事实依赖。核验必须覆盖正文所声称的实际行为，不以「文件或符号存在」代替行为成立。正文中的「现有、既有、复用、无需新增」等断言若在当前资源 HEAD 上不成立，必须改为新增能力设计或列入待核实依赖，不得继续作为方案前提。
```

相对原文的唯一新增内容：`dep-N` 稳定标识句（含"`commit SHA` 为必填的 40 位 SHA"与编号生命周期）＋"事实只在该表定义一次 / 正文只能写设计依赖 `dep-N`"句。

### 6.5-B `write-tech-design/SKILL.md` — `### 既有实现依赖与事实` 小节（L117-127）

**L117 句替换目标**：

```text
当方案依赖既有实现时，必须在本节按正文首次出现顺序列出每项依赖，每项以稳定标识 `dep-N`（N 为正整数）开头，使用以下固定结构：
```

**固定结构块替换目标**：

```text
dep-1
  repo: <repository id>
  relative path: <path from repository root>
  stable symbol/对象: <symbol, key, interface, module, behavior, or responsibility>
  commit SHA: <40-character SHA>
  依赖结论: <verified current behavior required by this design>
```

**结构块后一句替换目标**：

```text
`review-tech-design` 只将本节的有序清单作为 `sdd.explicit_existing_dependencies`，并按 `dep-N` 引用关系核验正文：正文出现的 `dep-N` 必须已在本节定义；正文出现未被 `dep-N` 引用承载的当前实现事实是事实引用无承载。无法绑定字段的引用必须列入待核实依赖；只有本节与正文均无既有实现依赖时，才写 `N/A（本 CR 无既有实现依赖）`。
```

### 6.5-C `write-tech-design/SKILL.md` — 回修模式句（L129）

**替换目标（原位扩写为一句群）**：

```text
回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案。blocker 触及状态判定、活动性、事件顺序、空值或失败回流时，必须重证该状态链的完整输入维度、分支、可见动作与对应 AC，不得只修被点名的那一格；同一标识符、锚点或 testid 在全文只能有一个裁决；未受该根因影响的已确认方案不得重写——「整体重证」与「不扩散」两个方向同时约束，前者防止只修一格，后者防止借重证之名重写无关设计。
```

### 6.5-D `write-tech-design/SKILL.md` — Step 2 章节 9「批准范围」段末追加

**在既有段落末尾（"代码阶段发现实际 diff 越界时只回 `implement-code`。"之后）原位追加**：

```text
四字段自洽判据（与 `review-tech-design` 的「批准范围前置」逐条同表述；判据只针对四字段之间的自相矛盾与必需条件错位，不针对详尽程度）：① `scope_in` 与 `zero_diff` 不得对同一对象同时要求「修改」与「不修改」；② 外部治理规则强制修改时，必须在 SDD 阶段把该对象纳入 `scope_in`、修订 `zero_diff`、或给出已有的合法出口；③ 不得用 `scope_out` 隐藏当前交付必须发生的治理修改；④ `follow_up` 不得承载当前 AC 的必要条件。不新增第五个字段、不新增独立 ledger 文件、不新增状态、不新增评审维度名。
```

### 6.5-E1 `review-tech-design/SKILL.md` — Step 2.1 两段（L87 / L89）

**L87 段替换目标**：

```text
SDD 的既有实现依赖必须来自名为“既有实现依赖与事实”的显式小节。该小节按正文首次依赖出现顺序维护有序清单，每项以稳定标识 `dep-N`（N 为正整数）开头，固定包含 `repo`、`relative path`、`stable symbol/对象`、`commit SHA` 和“依赖结论”五要素，其中 `commit SHA` 为必填的 40 位 SHA（缺失或与取证结果不符形成 blocker）。`sdd.explicit_existing_dependencies` 仅指该清单，不由 reviewer 扫描全仓库或临时猜测；reviewer 还必须核验 `dep-N` 引用规则：正文出现的 `dep-N` 必须在表中已定义，判据从「正文同类事实是否漏列」的集合比较升级为「正文引用是否由 `dep-N` 承载」的关系式——正文出现未通过 `dep-N` 引用承载的当前实现事实形成 blocker。本规则是 Prompt 合同，不宣称对自由文本事实的机械识别——判定仍属评审判断，不新增 crctl 校验面、lint 规则或 annotation dimension。
```

**L89 段替换目标（仅核心句改写，取证边界逐字保留）**：

```text
只核验 SDD 明确写入且设计成立依赖的既有实现事实，不做全仓库无界扫描：对每项依赖按 `resources` 找到匹配 `repo`，用受控只读取证 `crctl git rev-parse HEAD` 取 commit SHA，并核验文件/稳定符号；事实缺失或行为不符形成业务 blocker（附 repo/SHA/path/symbol/conclusion 证据），资源缺失或不可读为技术失败且不写临时 payload。SDD 正文出现未被 `dep-N` 引用承载的当前实现事实形成 blocker；只有正文与依赖清单均无依赖时才记录 `N/A（本 CR 无既有实现依赖）`。行号只作辅助，不作唯一证据；评审不执行 lint/build/test。
```

### 6.5-E2 `review-tech-design/SKILL.md` — Step 2「批准范围前置」引用块（L58）末追加

**在既有引用块（`> **批准范围前置（CR-2026-057 FR-5/AC-5）**：…统一生成 verdict。`）末原位追加**：

```text
四字段自洽判据（与 `write-tech-design` 章节 9 逐条同表述；判据只针对四字段之间的自相矛盾与必需条件错位，不针对详尽程度）：① `scope_in` 与 `zero_diff` 不得对同一对象同时要求「修改」与「不修改」；② 外部治理规则强制修改时，必须在 SDD 阶段把该对象纳入 `scope_in`、修订 `zero_diff`、或给出已有的合法出口；③ 不得用 `scope_out` 隐藏当前交付必须发生的治理修改；④ `follow_up` 不得承载当前 AC 的必要条件。任一一型命中 → blocker（`本轮新增：`），必须在 SDD 阶段形成，不得留到 dev-plan 再由 `review-dev-plan` 的 `upstream-design-blocker` 轨触发。
```

### 6.5-F `pipeline-structure.test.mjs` — L616 目标用例两组 term

**替换目标（用例名与结构不变，仅两组 term 原位改写）**：

```javascript
test('CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确', () => {
  const writer = readFileSync(path.join(TOOLS_ROOT, 'skills/develop/write-tech-design/SKILL.md'), 'utf8').replaceAll('\r\n', '\n');
  for (const term of ['### 既有实现依赖与事实', '正文首次出现顺序', 'dep-N', 'repo:', 'relative path:', 'stable symbol/对象:', 'commit SHA:', '依赖结论:', 'sdd.explicit_existing_dependencies']) {
    assert.ok(writer.includes(term), `write-tech-design 合同含 ${term}`);
  }
  const reviewer = readFileSync(path.join(TOOLS_ROOT, 'skills/develop/review-tech-design/SKILL.md'), 'utf8').replaceAll('\r\n', '\n');
  for (const term of ['名为“既有实现依赖与事实”的显式小节', '有序清单', '`dep-N` 引用规则', '`commit SHA` 为必填的 40 位 SHA', 'sdd.explicit_existing_dependencies', '正文同类事实是否漏列']) {
    assert.ok(reviewer.includes(term), `review-tech-design 规则含 ${term}`);
  }
});
```

term 组的覆盖对照（PRD FR-6.1）：写侧 = 小节名（`### 既有实现依赖与事实`）＋ `dep-N` 固定结构（`dep-N`）＋ 五字段名（`repo:` / `relative path:` / `stable symbol/对象:` / `commit SHA:` / `依赖结论:`）＋ 排序与消费口径（`正文首次出现顺序` / `sdd.explicit_existing_dependencies`）；评侧 = 显式小节（`名为“既有实现依赖与事实”的显式小节`）＋ 有序清单（`有序清单`）＋ `dep-N` 引用规则（`` `dep-N` 引用规则 ``）＋ `commit SHA` 必填（`` `commit SHA` 为必填的 40 位 SHA ``）＋ 消费口径（`sdd.explicit_existing_dependencies`）＋ 正文漏列（`正文同类事实是否漏列`）。

### 6.5-G `gate-registry.json` — L38

`"pipeline-structure.test.mjs": 35` → `"pipeline-structure.test.mjs": 36`（其余条目与 `exceptions: []` 不动）。

## 6.6 门禁与回归面（NFR-1 / NFR-5）

| 面 | 本 CR 的期望 | 依据 |
|---|---|---|
| `lint-prompts.mjs --mode enforce` | 绿（新增文本不含裸 git、状态机副本、下一步映射、deny 面手写指示） | §6.5 文本按 R1~R13 逐条自查 |
| `check-skill-matrix.mjs` / `check-agents-contract.mjs` | 绿（未改 Skill / Agent 集合、未改索引） | 依赖第 23、10 项 |
| pipeline JSON 结构断言 | 绿（`pipeline-templates/**` 零 diff） | 依赖第 22 项 |
| `suite-gate.mjs --run` | 全量绿；`exceptions` 保持 `[]` | FR-6.3/FR-6.4 |
| `pipeline-structure.test.mjs` | 36 条顶层用例全绿（含 L616 改写后的 term 组） | AC-6①③ |
| `contract-scan` | `RETIRED_RECOVERY` 整树零命中 | 依赖第 15 项 |
| 行尾纪律（NFR-5） | SKILL 与测试文件保持 LF 检出内容一致；测试读取仍先 `\r\n → \n` 归一 | ARCHITECTURE.md 不变量 4 |

# 7. 安全与性能考量

## 7.1 行尾纪律与硬失败（NFR-5）

- 本 CR 触及的测试文件对 target 文件做文本断言，读取路径仍是 `readFileSync(..., 'utf8').replaceAll('\r\n', '\n')`（既有形态，依赖第 11/12 项），Windows 检出不会造成假红或假绿；
- 断言失败即 `assert.ok` 抛出，**没有**"匹配不到 → 空集 → 静默通过"的分支——`dep-N` term 若在实施后从文本里消失，红灯是唯一结果；
- 本 CR 不新增解析器、不做跨行正则，故不引入新的归一化面。

## 7.2 边界与越权面

- **不新增判据副本**：`dep-N` 规则与批准范围自洽判据的唯一事实源分别是两份 SKILL 的既有段落；`tools/agents/quality-reviewer-agent.md` 零 diff（AC-3②）。
- **不动写入通道**：评审批注仍唯一经 `crctl review-record` 落盘，状态仍唯一经 `crctl advance`；本 CR 只改判据文本。
- **不放宽既有门禁**：Step 2.1 的 AC 闭环伪码、Step 2.3 的分级边界与固定前缀句、CR-2026-066 的发布与 clean 前置全部保留（AC-9③）。
- **反向 token 保持性**：本 CR 新增文字不含 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（AC-2⑦）；`write-tech-design` 现存 1 处 `crctl checkpoint` 句不删（§1.5 第 5 条）。

## 7.3 唯一强度变化的兼容性说明

评侧 `commit SHA` 由"并可附"改为必填，会让原本可通过的 SDD 在**新口径**下成为 blocker。该变化：

- 不改变任何 crctl 状态转换、错误码、参数或落盘路径（§3.1/§3.2）；
- 只改变 `review-tech-design` 的 blocker 判定输入；
- 对既有已归档 CR **无追溯效力**——判据只对评审发生时的 SKILL 版本生效（PRD §1.3.3，本 SDD 同样据此声明 D-6 的时序差）。

## 7.4 性能与观测

- 本 CR 不新增运行时开销：只改文本判据与一个既有断言的 term 组，测试执行规模不变（顶层用例数 36 不变）；
- 不新增观测指标 / SLO / 计数门禁 / 评审轮数承诺（NFR-2、FR-3.3）；`本轮新增：` 仍只承担 blocker 文本分类；
- 日志与审计面零变化（不新增 crctl 子命令、不改 audit/outbox 语义）。

# 8. Prompt 采纳影响

**N/A（本 CR 不触及触发面）。** 依据 `write-tech-design` Step 2 章节 8 的条件触发判定：只有当本 CR 的 diff 触及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支或 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny` 时才必填。

- `crctl.mjs`：本 CR **零 diff**（不新增/删除子命令、flag、错误码；不改任何 dispatch 分支）。
- `rules.json`：`protectedPaths.deny` 与 `git[]` 白名单 **零 diff**（§9 `zero_diff`，依赖第 21 项）。

因此不存在"crctl 新增了能力、某 Skill 该采纳却还没采纳"的漂移面，本节按规则省略为 N/A。

# 9. 批准范围

## scope_in（当前 CR 必须交付的 FR/AC）

- **FR-1 ~ FR-7 全部**，按 §6.1 的落点表；**AC-1 ~ AC-9 全部**按 §6.2 的映射验收（AC-9 为本 PRD 新增的边界与串行判据）。
- **文件面（4 个交付文件，全部在 `../tools`）**：
  1. `skills/develop/write-tech-design/SKILL.md`（§6.5-A/B/C/D 四处原位修订）；
  2. `skills/develop/review-tech-design/SKILL.md`（§6.5-E1/E2 两处原位修订）；
  3. `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（L616 目标用例两组 term，§6.5-F）；
  4. `skills/shared/crctl/scripts/test/gate-registry.json`（`manifest.cases["pipeline-structure.test.mjs"]` 35 → 36，§6.5-G）。
- **KB 仓**：本 SDD（`change-requests/CR-2026-067/sdd.md`）与状态/评审记录；不改 KB 的 `specs/`、`delivery/`、`docs/`。

## scope_out（明确排除的路径和能力）

- **plan/TASK 写作合同**（`write-dev-plan` / `write-dev-tasks` / `review-dev-plan`、upstream 增量回修、TASK 依赖闭包、证据命令证明力、环境责任与 readiness、`code-implementation.pipeline.json` 的 dev-start 提示）→ 归 **CR-P2**（PRD §7）。
- **crctl 事务层与命令面**：`crctl.mjs`、`scripts/lib/**`、`gates.json`、状态机声明、`rules.json` 零 diff；不新增/删除子命令、flag、错误码。
- **不新增结构承载**：annotation dimension、账本字段、评审指标（SLO / 计数门禁 / 评审轮数承诺）、Pipeline 节点、Skill 参数、落盘文件、lint 规则、CI step。
- **不在 Agent Prompt 造第二份判据**：`tools/agents/quality-reviewer-agent.md` 零 diff（不新增小节、不复制 `dep-N` 规则与首轮全量判据）。
- **不重编号 Step**：`review-tech-design` 的 Step 1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6 与 `write-tech-design` 的 Step 1 / 2 / 2.5 / 2.6 / 3 / 4 / 5 全部保持编号不变。
- **不复活旧字段名**：不引入 `recoverCommand` / `recover_command`；不改结构化 `recovery` 合同（CR-2026-064 面）。
- **不改发布口径**：不为发布点前移或 checkpoint 语义做任何改动（CR-2026-066 已定；本 CR 不删 `write-tech-design` 现存 `crctl checkpoint` 句）。
- **不改 `suite-gate.mjs` 判据语义**，不签任何新例外。
- **`../multica/`**：零 diff（不改部署副本、不改 Go/TS 代码、不登记其 `CUSTOM.md`）。

## zero_diff（明确不得改动的调用点/签名）

| 对象 | 零 diff 约束 |
|---|---|
| `change-requests/CR-2026-067/prd.md` | 零 diff（已审批冻结，`sha256(LF)` = `efde31fd…`；改哈希即作废人工审批）。含 S-1 附带项：**不修**"七条"措辞 |
| `skills/shared/crctl/scripts/crctl.mjs`、`scripts/lib/**` | 全文件零 diff（不改 dispatch、不改事务层与状态/账本写入口） |
| `skills/shared/crctl/gates.json`、`../tools/dir-graph.yaml#change-request-track.state_machine` | 零 diff（不新增状态、转移、门禁） |
| `skills/shared/controlled-shell/rules.json` | 零 diff（`protectedPaths.deny` 与 `git[]` 白名单都不动） |
| `pipeline-templates/**`（含 8 个 pipeline JSON 与 `_index.yml` 的 nodes 计数） | 零 diff（不新增节点、不改 dev-start 提示） |
| `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md` | 零 diff（不改任何 actor 的 `owns`/`can-call`/`forbidden`、不新增 Skill） |
| `agents/quality-reviewer-agent.md`（及 `tools/agents/**`） | 零 diff（`##` 小节集合保持 7 个，无新增小节与判据副本） |
| `skills/develop/{write-dev-plan,write-dev-tasks,review-dev-plan}/SKILL.md` | 零 diff（CR-P2 面） |
| `skills/requirement/review-requirement/SKILL.md`、`skills/develop/{review-dev-plan,review-code}/SKILL.md` | 零 diff（四个 review SKILL 中除 `review-tech-design` 外的三个） |
| `review-tech-design` Step 1 / 1.0 / 2.2 / 2.3 / 3 / 4 / 5 / 6 与 `write-tech-design` Step 1 / 2.5 / 3 / 4 / 5 | 零 diff（含 Step 2.2 首轮全量句逐字保留、Step 2.3 分级边界与固定前缀句逐字保留） |
| `write-tech-design` Step 1 第 2 条的 `crctl checkpoint` 提交口径句 | 零 diff（本 CR 不删该句） |
| `skills/shared/crctl/scripts/test/suite-gate.mjs`、`contract-scan.test.mjs`、`lint-prompts.mjs`、`check-*.mjs` | 零 diff（不改判据语义、不新增扫描面） |
| `pipeline-structure.test.mjs` 除 L616 目标用例外的全部用例（含 L656 CR-2026-066 断言 A/B/C/D 与 `REVIEW_SKILLS` 常量） | 零 diff（不放宽任何既有断言） |
| `../multica/**`（含 `cr-prompts-revised/**`、`CUSTOM.md`、`aifirst/**`） | 零 diff |
| KB `specs/`、`delivery/`、`docs/`、`change-requests/CR-2026-067/{approval.yml,review-annotations/**,review-loop.yml,traceability.yml}` | 零 diff（受控账本，crctl 独占写） |

## follow_up（发现但留给后续 CR / owner 的缺口）

1. **S-1（PRD §5 末段"七条"与来源 §5.5 的 8 条不符）**：`prd.md` 已随需求审批冻结，本 CR 不改该文件；本 SDD 按实际 8 条理解（AC-1~AC-8 覆盖完整）。建议后续需求类 CR 或该 CR 回写期统一措辞（去计数或改为"八条"）。
2. **`dep-N` 形态的历史文档同步**：`docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md` 等分析文本仍按旧编号列表描述依赖表；本 CR 不改写历史分析文档，如需标注"已被 CR-2026-067 取代"另起文档 CR。
3. **`manifest.cases` 的下界语义**：本 CR 只把登记值同步为实测值，不改 `suite-gate` 的"低于登记值即红"语义；若后续需要"登记值 = 实际值"的严格校验，属独立门禁 CR。
4. **评侧 `commit SHA` 必填对新写 SDD 的即时影响**：新口径会拦下缺失 SHA 的 SDD；首个受影响对象是新口径生效后撰写 SDD 的 CR（本 CR 自身的 SDD 按 D-6 沿用实施前形态）。
5. **`review-loop` 达标后的重证质量**：本 CR 只提供回修判据文本（Prompt 合同），不提供机械校验；若后续出现"整体重证"被形式化执行的情况，需要新的观测面（本 CR 明确不新增观测指标）。
6. **PRD §1.4 事实 16 的计数偏差（`review-tech-design` attempt 1/3 的 `范围外` suggestion）**：`CR-2026-055` 相关用例实测为 5 条（`L568` / `L585` / `L602` / `L616` 之外，同文件 `L627` 另有 `test('CR-2026-055 blocker 修复: 权限解释文档同步新增 can-call 关系', ...)`），PRD 写作"4 条"。本 SDD 未继承该计数（§6.3 第 11/12 项只引用 L616 目标用例与顶层总数 36），设计唯一性与验收可达性不受影响；`prd.md` 已随需求审批冻结，本 CR 不改该文件，建议回写期或后续需求类 CR 与本列表第 1 项（S-1）一并修正措辞。

---

# SDD-CLOSE 关闭项（PRD 显式延后到 SDD 的设计项）

**扫描结论**：逐条扫描 PRD（§1.3.3、§1.5、§3 各 FR、§4、§5、§7）后确认——**PRD 中不存在显式延后到 SDD 的设计项**（无"待 SDD 定义/由 SDD 决定/延后到设计期"的表述）；PRD 的三处"需人工一并确认"（§1.5 第 1、2、4 条）已在需求人工审批时确认，不含设计缺口。为可核对，仍按 SDD 承接面逐项关闭如下。

## SDD-CLOSE-01 FR-1 的 `dep-N` 条目形态与编号生命周期（P0）

**结论：已关闭。** 条目形态 = §2.2 表（`dep-N` 首行 + 五字段缩进两格）；编号生命周期 = §4.1 算法（首次出现顺序分配、只增不改、删除留空洞不复用）。覆盖层：产生（写侧 Step 2.6 判据）→ 定义（依赖小节一次）→ 消费（本 SDD §6.3 与评侧 Step 2.1）→ 兼容降级（旧 `1. repo:` 前缀退役，五字段名与小节名不变，`sdd.explicit_existing_dependencies` 语义不变）。

## SDD-CLOSE-02 FR-2 的评侧判据闭包（P0）

**结论：已关闭。** 三条关系式（引用必须已定义 / 事实必须被引用承载 / SHA 必填且与取证一致）全部写进 Step 2.1 的同两段（§6.5-E1），并给出诚实边界（Prompt 合同、非机械门禁、不新增 crctl 校验面与 annotation dimension）。覆盖层：判据文本 → 断言面（§6.5-F 的评侧 6 项 term）→ 消费方（reviewer 的 blocker 判定）。

## SDD-CLOSE-03 FR-5 两侧同判据的"同表述"闭合（P1）

**结论：已关闭。** 四条判据的两侧文本在 §6.5-D 与 §6.5-E2 中**逐字相同**（仅引导句按角色不同），因此 AC-5① 的"表述与字段名一致"可直接 diff 核对；评侧的落点（SDD 阶段 blocker、不留 dev-plan）写在同段（§6.5-E2 末句）。

## SDD-CLOSE-04 FR-6 的断言与基线同步闭合（P1）

**结论：已关闭。** 目标用例的写侧/评侧 term 组逐项给出（§6.5-F），并逐条对照 PRD FR-6.1 的覆盖要求；`manifest.cases` 的收口方向与理由见 D-5（35 → 36）；`suite-gate.mjs` 判据语义与 `exceptions` 保持不动（§4.5）。覆盖层：断言文本 → 门禁登记值 → 门禁判据语义 → CI 回归面（§6.6）。

## SDD-CLOSE-05 本 CR 自身 SDD 与目标合同的时序差（P2）

**结论：已关闭（按 D-6 声明）。** 本 SDD §6.3 沿用实施前的编号列表形态，目标 `dep-N` 形态自实施提交起对其后的 SDD 生效；依据是 PRD §1.3.3 的"评审判据只对评审发生时的 SKILL 版本生效"，因此不构成 NFR-3 所禁止的"新旧两套判据并存"。

## SDD-CLOSE-06 S-1 附带项的处理（P2）

**结论：已处理（不改需求文本）。** 处理方式：设计期按来源 §5.5 实际 8 条理解（§6.2 以 AC-1~AC-9 为验收面，AC-1~AC-8 与 8 条一一对应）；**保留理由**：`prd.md` 已冻结（改哈希即作废需求审批），修它超出本 CR 的设计范围；改进建议登记为 `follow_up` 第 1 项。

---

## 修订记录

- 初稿（2026-09-15）：按冻结 PRD（`change-requests/CR-2026-067/prd.md`，285 行 / 51,864 B / LF-only / `sha256(LF)` `efde31fd…`，引入提交 `d4f366fa`）与来源附件 §5 起草；基线事实在 `tools@7094e492`、`multica@5c1880f2`、KB worktree@`31db6d20` 三个 HEAD 上逐条核实（§6.3 共 36 项依赖）。设计细化的三处落点：① 写侧 `dep-N` 的**分配算法**（§4.1，PRD 只给形态、未给流程）与条目形状表（§2.2）；② 评侧**关系式核验算法**（§4.2）与"集合比较 → 引用关系"的显式升级表述（§6.5-E1）；③ 批准范围四条判据在两侧的**逐字同表述**形态（§6.5-D/E2），使 AC-5① 可 diff 核对。六项 SDD-CLOSE 逐项关闭（其中 SDD-CLOSE-01/02 为 P0 设计项，03~06 为边界与时序项）。
- 本节点开工前的发布收口：上一阶段（需求审批）的本地提交 `14c2b6c1`（`approval.yml` + status）按 `push-progress` 既有语义一次发布为 batch `0afd3f235aaf3cfb`（`ai-first-platform-docs` 源提交 `14c2b6c1` confirmed、`multica` `5c1880f2`、`tools` `7094e492`，metadataCommit `31db6d201f081d6e78a5fa73e6676d4fa55d319e`）；本 SDD 不对发布口径做任何改动。
- 回修 1/3（2026-09-15，`review-tech-design` attempt 1/3 = BLOCK 定点修复，被修复版本 `sha256(LF)` = `b5d91ae3136670947a9e62ca8c80eaf0ea6bca640bb97ac89f184853624a3253`）：① 按 `tools@7094e492` 实测把 §6.3 第 27 项 `relative path` 与 §9 `zero_diff` 对应行中需求评审 SKILL 的仓内前缀由 `skills/develop/` 更正为 `skills/requirement/`（实测 `skills/develop/` 下无 `review-requirement`；该 SKILL 与 `pipeline-structure.test.mjs#REVIEW_SKILLS` 均写 `skills/requirement/review-requirement/SKILL.md`，同行的 `review-dev-plan` / `review-code` 仍在 `skills/develop/` 下，未改），修正后 §6.3 全部 36 项 `relative path` 与 §9 全部字面路径可解析；② 采纳本轮 suggestion，把 §6.3 收录判据 ③ 由「§9 `zero_diff` 点名对象」收窄为「§9 `zero_diff` 中设计所依赖的既有实现文本」，与清单实际收录面一致（§9 其余零 diff 对象由该表与 AC-7②/AC-9① 直接核对）；③ 本轮 `范围外` suggestion（PRD §1.4 事实 16 的计数）登记为 `follow_up` 第 6 项。除上述定点修订外，§6.5 目标文本、§9 其余行、D-1~D-6、SDD-CLOSE-01~06 均未改动。
