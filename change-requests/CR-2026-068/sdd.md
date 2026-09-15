---
id: CR-2026-068-sdd
type: SDD
cr-ref: CR-2026-068
title: CR-P2：plan/TASK 返工成本与执行前提 技术设计
target-version: 0.41
status: draft
created: 2026-09-15T20:52:00+08:00
updated: 2026-09-15T20:52:00+08:00
---

# 1. 架构概览

## 1.1 设计目标与不变量

本 CR 的技术设计只做一件事：**把「plan/TASK 回修」「证据命令证明力」「环境执行前提」三处合同缺的可判定承载体，原位补进既有 Skill 段落与一处 pipeline 人工审批提示文本**。设计输入是需求合同（`dep-1`：FR-1~FR-6 / AC-1~AC-9）与需求来源（`dep-2` §6.1~§6.7），设计边界由 `dep-1` §1.3.1 / §7 与 `dep-2` 边界段落钉定：**零新增结构承载**（无新节点、无新账本字段、无新评审维度、无新观测指标）。

落成六条设计不变量（供 `review-tech-design` 与 `plan/TASK` 逐条核对）：

| # | 设计不变量 | 判据落点 |
|---|---|---|
| I1 | **回修以 delta 为输入，不以「整轮」为输入**：upstream SDD 重新批准后，plan 与 TASK 两层都只重算受影响面（章节 / 稳定表行 / 证据 / 回滚 / 受影响 TASK 的下游依赖闭包），未受影响内容逐字保留 | FR-1 / FR-2、§4.1 / §4.2、AC-1 / AC-2 |
| I2 | **同一文件内不存在两套回修规则**：delta 语义只写在既有回修模式段落内部（`dep-3` / `dep-4` 所指段落），文件内不得并存「全量重建」与「delta 重算」两种规则 | FR-2.3、NFR-3、§4.2、AC-2③ |
| I3 | **证据命令的判据是「观测面 ≥ 声称面 + 形态在受控边界内」**，写侧与评侧使用同表述、同强度；既有概括反假绿句保留，不另立第二句概括 | FR-3、§4.3、AC-3 |
| I4 | **回滚单元 = 受影响下游消费者的依赖闭包**：共享改动的回滚不得声明为单点回滚，且与风险节逆拓扑顺序一致 | FR-4、§4.4、AC-4 |
| I5 | **环境前提分三层、各自单点**：plan 侧静态声明（owner / 建立方式 / 可获得性 / readiness / 缺失处置）、dev-start 侧只确认静态前提、implement 侧在首个环境依赖 TASK 前即时执行 readiness；动态健康不入人工审批、不入账本 | FR-5、§4.5、AC-5 / AC-6 |
| I6 | **零新增面无例外**：状态机、gate、reviewLoop / replayNodes、账本字段、评审维度名、`cmd-NN` 合同、`ENVIRONMENT_MISMATCH` 语义、pipeline 节点数（5/4/12）与全部既有测试断言保持 | FR-6、§4.6、§9 `zero_diff`、AC-7 / AC-8 / AC-9 |

## 1.2 变更面鸟瞰

**一批纯文本原位修订**：交付 diff 只含 5 个 tools 文件（其中 4 个 SKILL.md + 1 个 pipeline JSON 的一个字符串字段），共 7 处落点：

```text
../tools（本 CR 代码实施面全部在此；SHA 见 dep-5 取证口径）
  skills/develop/write-dev-plan/SKILL.md        ← FR-1（Step 2a upstream 轨）+ FR-3（两张稳定表说明）
                                                   + FR-4（交付覆盖表 `回滚` bullet）
                                                   + FR-5（章节 5「验收与发布策略」）      = 4 处
  skills/develop/write-dev-tasks/SKILL.md       ← FR-2（Step 2a 第 1 条原位改写）          = 1 处
  skills/develop/review-dev-plan/SKILL.md       ← FR-3 评侧（既有 acceptance-verifiability） = 1 处
  skills/develop/implement-code/SKILL.md        ← FR-5 implement 侧（既有环境节同节共生）   = 1 处
  pipeline-templates/code-implementation.pipeline.json ← FR-5 dev-start 侧（`…0004` approvalPrompt 值替换） = 1 处
ai-first-platform-docs（KB：只承载本 CR 过程产物；不改 specs/ delivery/ docs/）
  change-requests/CR-2026-068/{prd.md（冻结，零触碰）, sdd.md（本文档）}
../multica：零 diff（不改 Agent Prompt 部署副本、不改 Go/TS 代码、不改 CUSTOM.md）
```

**改动量上界**：4 处「既有段落内原位扩写 / 原位改写」＋ 2 处「既有 bullet 原位扩写」＋ 1 个 JSON 字符串值替换。**无新增文件、无删除文件、无新增章节、无 Step 重编号、无新增列、无新增枚举值。**

## 1.3 依赖方向与分层与多仓口径（不变）

```text
Pipeline（pipeline-templates/*.pipeline.json）   编排 Skill 调用顺序（本 CR 仅改 …0004 的提示文本，编排零变化）
   ↓
Skill（write-dev-plan / write-dev-tasks / review-dev-plan / implement-code）  提示词合约 ← 本 CR 改动层
   ↓
crctl（crctl.mjs + lib/**）                      状态与账本唯一写入执行器（本 CR 零 diff）
```

三条硬约束取自 `dep-5`（`## 4. 分层与依赖方向`、`## 5. 硬不变量`），本轮实读全文，本设计逐条不冲突：

- **不变量 1 / 2（状态与账本单一写入通道）**：本 CR 不新增任何状态写入口或账本写入口；plan/TASK 的产物仍是 KB 过程文档，任务索引刷新仍唯一经 `crctl`（`dep-6` 所指既有指引不动）。
- **不变量 3（零第三方依赖）**：本 CR 不新增依赖、不新增脚本、不改 `skills/shared/crctl/scripts/**`。
- **不变量 4（行尾与硬失败纪律）**：新增/改写文本读写前后一律 `\r\n → \n` 归一；跨行解析失败硬失败（§7.1）。
- **不变量 8（Skill 通用、约束归仓）**：四处新增文本只写通用写作/评审判据，不出现任何使用方仓库的产品专属约束（表结构、迁移框架、锁原语、DDL 规范）。

**多仓口径（FR-08.4 对应面）**：

| 项 | 本 CR 口径 |
|---|---|
| 路径 authority | 一切 worktree 路径只取 `crctl workspace inspect` 的 `operationalWorkspace` / `resources[].worktreePath` 原样值（`dep-1` 为 KB 过程文档权威路径；`dep-5` 指出的目标仓只按 `resources` 匹配 `repo` 取 `worktreePath`），不按 `.rayai-worktrees/{repo.id}/...` 目录命名拼接 |
| 跨仓依赖方向 | KB（需求/设计/任务文档）→ tools（被改文本）；`../multica` 不被依赖也不被修改；依赖只朝下，无反向依赖 |
| 各仓提交口径 | 按既有 FR-07.2 口径：文本改动在 `resources[].worktreePath` 各自提交，不要求同一 commit；阶段终点由 `review-tech-design` PASS 分支的既有 `push-progress`（`crctl checkpoint`）纳入同一批发布（本 Skill 不新增发布动作） |

## 1.4 关键流程

### 1.4.1 upstream 后 plan 增量回修（FR-1）

```text
触发：review-dev-plan 走 UPSTREAM 轨（repair-target=write-tech-design，dep-7 所指既有双轨路由）
      → 人工修订 SDD → 重新评审（review-tech-design）→ 重新批准（approve-tech-design）
      → 按 pipeline 既有 reviewLoop.replayNodes 重放（dep-8 所指条目）
输入：① 新旧批准 SDD 的变更 delta；② 同轮未闭合 plan blockers（canonical feedback 引用）
动作（全部在 dep-3 所指既有 Step 2a 段落内原位扩写，不新增小节）：
  ① 既有普通轨三条逐字保留；
  ② upstream 轨：在同一份 plan.md 上只重算受影响章节、稳定表行（两张稳定表的行）、
     证据与回滚；未受影响内容逐字保留；
  ③ coordinator 只传 subject / delta / canonical feedback 引用，不指定具体行如何修改。
不改：review-route 枚举、repair-target 单值语义、Step 编号（Step 1/2/2a/3/4 不变）。
判据落点：§6.5-A
```

### 1.4.2 TASK 及依赖闭包 delta 重算（FR-2）

```text
触发：write-dev-plan 完成 SDD→plan delta 后，pipeline 按既有顺序重放 write-dev-tasks（dep-8；dep-4 所指段落）
动作（在该段第 1 条内原位改写，不新增第 4 条、不在别处另写一段）：
  ① 继续执行 plan→TASK delta：重算「直接受影响 TASK」（普通轨 blockers 指向的 TASK + upstream delta 波及的 TASK）
     及其下游依赖闭包（depends-on 可达的传递闭包）；
  ② 同步更新受影响 TASK 的输入、输出、接口（接口契约节的消费/产出签名）、命令、depends-on、完成标志、回滚；
  ③ 未受影响 TASK 保留；被评审判废/删除的 TASK 从文件集移除；
  ④ crctl task init 只用于刷新 tasks/_index.yml 索引，不承担重算语义（索引刷新契约见 dep-7 / dep-6）。
禁止：只修 plan 而把旧 TASK 留给下一轮评审发现；文件内并存两套回修规则（I2）。
不改：节点集 / 节点数 / replayNodes 条目 / `purpose: regenerate-tasks` 标签文本（dep-8）。
判据落点：§6.5-D
```

### 1.4.3 证据命令的观测面与受控形态（FR-3）

```text
写侧（dep-9 所指两张稳定表说明，原位扩写；既有概括反假绿句保留，不另立第二句概括）：
  ① 观测面 ≥ 声称面：每个 cmd-NN 必须能观测该表行声称的 AC 结果；
  ② 四类典型错配：--list 类命令不能证明浏览器行为；文件级 --name-only 不能证明符号级不变量；
     子集测试不能声称全量；涉 Git 的命令必须使用 rules.json 已允许的受控入口（dep-10，不新开裸面、不改列白名单）；
  ③ 命令算法唯一事实源 = 证据命令表行，不再通过委派评论补写命令算法。
评侧（dep-11 所指既有 acceptance-verifiability 增量维度内原位扩写同一判据）：
  观测面窄于声称面即 blocker；命令形态越受控边界即 blocker；不留到 implement 阶段才暴露。
不改：两张稳定表的表头 / 列集 / 「验收证据 ↔ 证据ID」双向唯一映射合同（dep-7 覆盖矩阵节机械核对）；
      八类维度表与四个增量维度名；不新增证据账本。
判据落点：§6.5-B（写侧）+ §6.5-E（评侧）
```

### 1.4.4 回滚单元是依赖闭包（FR-4）

```text
目标：dep-9 所指交付覆盖表既有 `回滚` bullet（原位扩写，不新增列）
  ① 被其它 TASK 消费的共享改动，其回滚单元必须包含受影响下游消费者；
  ② 与 plan.md 第 4 章「风险与回滚策略」的逆拓扑顺序一致；
  ③ 单点 revert 会破坏下游时不得声明为单点回滚。
判据落点：§6.5-B
```

### 1.4.5 环境责任与即时 readiness 三侧（FR-5）

```text
plan 侧（dep-12 所指 chapter 5「验收与发布策略」，原位扩写，不新增第八节）：
  证据依赖常驻服务 / 浏览器 / 数据库时，本节写明五要素：
    ① 环境 owner；② 建立方式；③ 可获得性；
    ④ readiness 证据 = 复用该环境所保障的那一行 FR 的既有 cmd-NN（证据ID 照抄证据命令表，不新增命令行）；
       两张稳定表双向唯一映射不放宽；无法复用 → 另立 CR（本 CR 不放开）；
    ⑤ 缺失时按既有 ENVIRONMENT_MISMATCH 标签与处置入口（只引用不复述，唯一详细事实源见 dep-13）。

dev-start 侧（dep-14 所指 `…0004` approvalPrompt，值原位替换）：
  只确认静态前提（owner / 建立方式 / 可获得性）；不要求审批时所有服务在线；动态健康状态不入人工审批；
  保留 ✅ / ❌ 两分支结构化决定；不得出现 git / journal 字样（dep-15 的既有零命中断言）；
  不得残留 review-annotations 路径与 reject_reason 引导；节点对象其余字段与节点集零变化。

implement 侧（dep-13 所指既有环境节，同节共生追加 bullets，不改写既有 bullets）：
  ① 在第一个依赖环境的 TASK 前执行 plan 指定的 readiness cmd-NN（属于既有「一次环境检查」的执行内容，
     不是新的反复探测；仍受「最多一次重跑」、timeout 与受控入口约束）；
  ② 失败按既有 ENVIRONMENT_MISMATCH 中止并报告所需建立动作；
  ③ 环境无关 TASK 不被提前阻断。
判据落点：§6.5-C（plan）+ §6.5-F（implement）+ §6.5-G（dev-start）
```

### 1.4.6 零新增与门禁面（FR-6）

```text
零 diff 面（逐条见 §9 zero_diff）：skills/shared/crctl/scripts/**（含全部测试与 gate-registry.json）、
  write-tech-design / review-tech-design / review-code / write-test-report / coding-discipline、
  pipeline 节点集与 reviewLoop、tools/agents/**、agent-skill-matrix.yml、../multica/**、
  KB specs/ delivery/ docs/（来源文档只读）
计数面：节点数保持 5 / 4 / 12，与 dep-16 登记值一致
测试面：dep-15 / dep-17 / dep-18 / dep-19 全部既有断言保持；dep-20 的 manifest.cases 保持 36、exceptions 保持 []
  （本 CR 预期零测试改动，dep-1 §1.5 第 2 条）
账本面：不改 upstream attempts 账本、不新增 review-events、不改 traceability schema、不做聚合指标
旧字段：不复活 recoverCommand / recover_command（dep-18 整树零命中）
```

## 1.5 与 PRD §1.5 七条口径的承接

| PRD §1.5 | 性质 | SDD 落点 |
|---|---|---|
| 第 1 条（FR-3 写侧不是从零新增反假绿句） | 事实核对 | §6.5-B 只保留既有概括句并在其后追加判据，不另立第二句（AC-3① 末句） |
| 第 2 条（本 CR 预期零测试改动） | 事实核对 / 门禁 | §6.4、§6.6、§9 `zero_diff`；`manifest.cases` 保持 36（`dep-20`） |
| 第 3 条（`…0004` approvalPrompt 的「原位改为」落点） | 需人工确认 | §6.5-G 在既有拆分确认语境上扩写环境静态前提，保留 ✅/❌ 两分支 |
| 第 4 条（`ENVIRONMENT_MISMATCH` 单一事实源纪律） | 本 PRD 钉定 | §6.5-C ⑤ 只引用标签与处置入口；§6.5-F 新文字加在 `dep-13` 同节内、不改写既有 bullets |
| 第 5 条（「一次环境检查」与 readiness 的关系） | 需人工确认 | §1.4.5 implement 侧 ①：readiness 是既有一次检查的执行内容，不是反复探测 |
| 第 6 条（readiness 无法复用既有 `cmd-NN`） | 本 PRD 钉定 | §6.5-C ④ 硬边界 + §9 `follow_up` 第 1 项（另立 CR） |
| 第 7 条（`purpose: regenerate-tasks` 标签语义钉定） | 本 PRD 钉定 | §1.4.2 不改标签文本与 replayNodes；delta 语义只写在 `dep-4` 正文内 |

**需求期 canonical suggestion（`dep-21`：PRD §1.4 事实 21 的「cmp 逐字节一致 / 33,478 B」只在 EOL 归一后成立）的承接**：本设计**不依赖**该字节级断言——设计输入按「内容一致（EOL 归一后）」理解，且未在任何目标文本中写入 `cmp` / 逐字节 / 字节数口径；§7.1 同时约定新增文本的行尾纪律与硬失败（SDD-CLOSE-05）。该处属需求文本，本 CR 不改 `prd.md`（§9 `scope_out`）。

---

# 2. 数据模型

## 2.1 零新增实体、字段与账本（NFR-2 落点）

| 面 | 结论 |
|---|---|
| 新增实体 / 表 / schema | 无（本 CR 无数据库变更，见 §2.6） |
| 新增账本字段 / 文件 | 无：不改 `cr.md` / `_backlog.yml` / `_history.yml` / `tasks/_index.yml` / `traceability.yml` / `review-loop.yml` 的结构或字段集 |
| 新增稳定表列 | 无：交付覆盖表仍 5 列、证据命令表仍 6 列（`dep-9`） |
| 新增枚举值 | 无：review-route 枚举、`repair-target` 单值语义、状态机状态与转移全部不变 |
| 新增观测指标 | 无：不新增 SLO / 轮数承诺 / 计数门禁（`dep-2` §1.4「不增加观测指标」） |

## 2.2 本 CR 改动的「数据形状」（全部为既有文档的文本形状）

| # | 形状 | 承载 | 变化方式 |
|---|---|---|---|
| S1 | plan.md 章节 5 的**环境声明五要素**（owner / 建立方式 / 可获得性 / readiness 复用既有 `cmd-NN` / 缺失处置引用） | `dep-12` 所指章节项 | 在该项说明内原位扩写；章节数仍为 7 |
| S2 | 交付覆盖表 `验收证据` 列的**观测面判据**（观测面 ≥ 声称面 + 四类错配 + 命令算法唯一事实源） | `dep-9` 所指 bullet | 既有概括句保留、其后追加判据；列集不变 |
| S3 | 交付覆盖表 `回滚` 列的**闭包判据**（含下游消费者 + 逆拓扑一致 + 单点回滚禁令） | `dep-9` 所指 bullet | 原位扩写；列集不变 |
| S4 | **TASK 卡 delta 面**：受影响 TASK 的输入 / 输出 / 接口 / 命令 / `depends-on` / 完成标志 / 回滚同步更新 | `dep-4` 所指段落 + TASK 卡既有结构（`dep-6`） | 语义收紧；TASK frontmatter 与正文 6 节结构不变 |
| S5 | `…0004` approvalPrompt 的**静态前提确认内容** | `dep-14` 所指字符串值 | 值替换；JSON 结构与节点对象字段不变 |
| S6 | 现有实现事实的**单一表达点**（`dep-N` 表） | 本文档 §6.3 | 依 `dep-5` 的既有 `dep-N` 合同表达 |

S4 的「依赖闭包」定义为 `depends-on` 有向边上的**传递闭包**（受影响 TASK 可达的全部下游 TASK）；口径与边界场景见 §2.4 的 `TERM-02`。S1~S5 均不引入新的可查询实体，因此不存在「字段完整性 / 迁移」问题。

## 2.3 既有结构引用（只读、逐字沿用）

以下既有结构在本 CR 中被引用但**零改动**，取证见 §6.3：两张稳定表的表头与列集、`验收证据 ↔ 证据ID` 双向唯一映射合同与覆盖矩阵节机械核对（`dep-7`、`dep-9`）、TASK 索引三步断言与受控账本指引（`dep-6`）、`ENVIRONMENT_MISMATCH` 标签语义与其唯一详细事实源地位（`dep-13`）、`rules.json` 的 git 白名单与 `protectedPaths.deny`（`dep-10`）、状态机与 gates（`dep-5`）、pipeline 节点集与 reviewLoop（`dep-8`、`dep-16`）。

## 2.4 术语预检（Step 2.5，结论）

预检范围：只处理进入「数据模型 / 状态机 / 接口契约」且存在歧义、别名或边界风险的术语。目标仓（`dep-5` 所指 tools 仓根）**无 `CONTEXT.md`、无术语表**（本轮实读：仓根与 `docs/` 均无该文件；`docs/` 下无覆盖本 CR 术语的定义），因此无既有权威定义可沿用、也不存在与既有口名的命名冲突。逐条结论（每个风险术语给出一个代表性边界场景）：

| 术语 | 结论 | 代表性边界场景（验证结果） |
|---|---|---|
| `TERM-01` **观测面 / 声称面** | 本 CR 新引入的判据对，不是既有概念别名；无需裁决，直接采用 `dep-1` FR-3 的表述 | 「声称面 = 交付覆盖表该行 FR/关键AC 的 AC 结果；观测面 = `cmd-NN` 实际能观测到的结果」→ 一条只跑单元测试的 `cmd-NN` 声称「浏览器交互可用」：观测面窄于声称面 → 判 blocker（不是「测试不够多」这类不可判定表述） |
| `TERM-02` **直接受影响 TASK / 下游依赖闭包** | 新引入的判定口径，与 `dep-2` §6.2 用词一致；无同名冲突 | TASK-02 直接受影响、TASK-05 经 `depends-on: [TASK-02]` 传递可达、TASK-07 与本链无关 → delta 重算集 = {TASK-02, TASK-05}，TASK-07 逐字保留（不被无理由重建） |
| `TERM-03` **readiness 证据** | 借用 `dep-2` §6.5 的用词；本 CR 把它钉为「复用既有 `cmd-NN`」，不新增第二套验证语义 | 环境 E 保障 FR-2 主路径：readiness 取该行既有 `cmd-NN`；若某 TASK 想为 readiness 另立命令 → 无 `cmd-NN` 下标、无 `test-evidence/cmd-NN.log`，不构成合法 `cmd-NN` → 判「另立 CR」而非本 CR 内放宽映射 |
| `TERM-04` **共享改动 / 受影响下游消费者** | 新引入的判定口径，与 `dep-2` §6.4 用词一致 | TASK-03 改签名的共享接口被 TASK-04 消费：回滚单元 = {TASK-03, TASK-04}，不得声明为「单点 revert TASK-03」 |

无术语语义冲突，**不需要**要求需求负责人澄清（若后续评审发现冲突，按既有「不自行裁决」规则停止并澄清）。本项不新增术语表文件、不新增 Skill 参数。

## 2.5 状态与门禁（零变化）

不新增状态、不新增转换、不改 `gates.json` 与目标 workspace 的 `dir-graph.yaml#change-request-track.state_machine`；本 CR 的状态链仍为既有 `tech-designing → tech-design-review-pending → tech-design-reviewed → task-breakdown → developing` 等既有路径。`upstream-design-blocker` 的重放路径完全复用既有转换（`dep-7`、`dep-8`）。

## 2.6 数据 / schema 变更与写路径鉴权完整性：N/A

**N/A（本 CR 无数据库 schema 变更、无数据迁移、无写路径鉴权改动）**。理由：本 CR 的 diff 只落在 4 个 Markdown 提示词文件与 1 个 pipeline JSON 的一个字符串字段；不新增表 / 列 / 索引 / 迁移，不触碰任何鉴权判定、事务边界或锁原语。`dep-5` §5 不变量 1/2 约束的「状态/账本写入通道」在本 CR 中零新增入口，因此不存在「约束缺失窗口」「回滚 down 脚本」「事务内鉴权复核」的适用面。

---

# 3. 接口契约

## 3.1 Skill 调用契约：零变化

`dep-1` §1.3.3 已钉定：本 CR 五份目标文件涉及的 Skill（write-dev-plan / write-dev-tasks / review-dev-plan / implement-code）的**必填参数、落盘路径、允许的状态转换、失败码、与 `crctl` 的唯一写入边界全部不变**。本 CR 改的是 SKILL 正文内的 Prompt 判据与 pipeline 人工审批提示文本，不新增/删除参数，不改参数类型或必填性。

## 3.2 crctl CLI 契约：零变化

不新增/删除子命令与 flag，不改任何 JSON 输出形状、退出码、错误码、调用者约束；`dep-10`（`git` 白名单与 `protectedPaths.deny`）零 diff；`skills/shared/crctl/scripts/**` 全量零 diff。

## 3.3 文本合同面（本 CR 的「接口」）

本 CR 的「接口」= 7 处文本判据（§6.5 给出逐字目标文本）。每处的可核对面 = 「必含判据」与「必须保持不变」两侧：

| # | 落点（`dep-N`） | 必含判据（设计产物） | 必须保持不变（保持性约束） |
|---|---|---|---|
| C1 | `dep-3`（write-dev-plan Step 2a） | upstream 轨四条（§6.5-A ②~⑤） | 普通轨三条逐字保留；Step 编号 1/2/2a/3/4 |
| C2 | `dep-9`（两张稳定表说明） | S2 六项观测面判据 + S3 三项回滚闭包判据 | 既有概括反假绿句；两张表表头 / 列集；双向唯一映射 |
| C3 | `dep-12`（plan 章节 5） | 环境五要素 | plan.md 章节数 7（不新增第八节）；不新增 `cmd-NN` |
| C4 | `dep-4`（write-dev-tasks Step 2a 第 1 条） | delta 重算 + 依赖闭包同步 + 未受影响保留 + `crctl task init` 只刷新索引 | 同节第 2、3 条；`tasks/_index.yml` 受控账本句；文件内无第二套回修规则 |
| C5 | `dep-11`（review-dev-plan `acceptance-verifiability`） | 两条 blocker 判据（同 C2 判据对） | 八类维度表与四个增量维度名；`dep-15` 的 S-13 三 token 零命中 |
| C6 | `dep-13`（implement-code 环境节） | readiness 即时性 + 失败标签 + 环境无关 TASK 不提前阻断 | 既有六个 bullets 原样；`ENVIRONMENT_MISMATCH` 唯一事实源地位 |
| C7 | `dep-14`（`…0004` approvalPrompt） | 静态前提确认 + 不要求服务在线 | ✅/❌ 两分支；无 `git`/`journal`；无 `review-annotations`/`reject_reason`；节点对象其余字段 |

## 3.4 错误语义：零新增

不新增错误码、不改变既有错误语义：`ENVIRONMENT_MISMATCH` 的语义与边界（不写 crctl 状态 / gate / 账本 / 评审 blocker / 测试证据 schema，由既有 `onFail=abort` 中止）逐字保留（`dep-13`）；`TASK_COUNT_MISMATCH`、`LOOP_EXHAUSTED`、`CONTRACT_DRIFT` 等既有码不受影响。

## 3.5 HTTP / REST / IPC / 事件契约：N/A

**N/A（本 CR 无任何 HTTP API、IPC 或事件契约新增/修改）**，故不编写 OpenAPI 片段（Skill Step 2.5「HTTP/REST 契约条件触发基线」不触发）。

---

# 4. 关键算法与流程

## 4.1 写侧：upstream delta 回修算法（FR-1，`dep-3`）

```text
输入：approvedSddOld, approvedSddNew, openPlanBlockers, canonicalFeedbackRef
① delta ← diff(approvedSddOld, approvedSddNew)        # 变更面，而非整份 SDD
② 输入集 ← delta ∪ openPlanBlockers                    # 同轮未闭合 blockers 与之并列
③ 受影响面 ← 由 ② 推导：受影响章节 / 受影响稳定表行 / 受影响证据 / 受影响回滚单元
④ for each 章节 in plan.md:
       if 受影响: 只重算该章节中与 ② 相关的行
       else: 逐字保留
⑤ for each 稳定表行: 仅 ② 命中行重算（新增行 / 修改行 / 删除行；其它行逐字保留）
⑥ for each 证据: 仅 ② 命中行重算 cmd-NN（保持双向唯一映射）
⑦ for each 回滚: 仅 ② 命中行重算（闭包判据见 4.4）
⑧ coordinator 合同：只传 subject / delta / canonicalFeedbackRef；不指定具体行如何修改
不变量：重写面 ∝ delta；route 枚举与 repair-target 单值语义不变
```

**边界**：若 ② 为空（无 delta、无未闭合 blocker），本轨不产生任何重写——由 `review-dev-plan` 既有 BLOCK 机制兜底，不空转（对应 `dep-3` 所指既有第 2 条）。

## 4.2 写侧：TASK 及依赖闭包 delta 重算算法（FR-2，`dep-4`）

```text
输入：planDelta（4.1 的产物）, taskGraph（depends-on 有向边）, openTaskBlockers
① direct ← {TASK | blockers 指向 ∪ planDelta 波及}          # 直接受影响
② closure ← 传递闭包(direct, taskGraph)                      # 下游消费者
③ for each T in closure:
       同步 T 的 输入 / 输出 / 接口（消费·产出签名）/ 命令 / depends-on / 完成标志 / 回滚
④ for each T ∉ closure: 逐字保留（不重建、不改 depends-on）
⑤ 文件集 ← 原集合 − 被评审判废/删除的 TASK
⑥ crctl task init → 仅刷新 tasks/_index.yml 索引（不承担重算语义；账本唯一写入通道不变）
禁止：只修 plan 不修 TASK；文件内并存「全量重建」规则
```

**边界（TERM-02 场景）**：闭包为空（无直接受影响 TASK）时，TASK 文件集与索引不变，仅刷新索引即可；闭包非空时，跨 TASK 的共享契约必须整体同步（不允许只改产出方而留下消费方旧签名）。

## 4.3 写侧 + 评侧：观测面判据（FR-3）

```text
写侧（dep-9，每个 cmd-NN 行级自查）：
  声称面(row) = 交付覆盖表该行「FR/关键AC」的 AC 结果
  观测面(cmd) = 该命令实际能观测到的结果
  判据：observable(cmd) ⊇ claimed(row)，否则必须换命令或调整声称（不得留下假绿）
  四类典型错配（判「窄」）：
    ① --list 类命令声称浏览器行为
    ② 文件级 --name-only 声称符号级不变量
    ③ 子集测试声称全量
    ④ 涉 Git 命令未走 rules.json 已允许的受控入口（dep-10）
  唯一事实源：命令算法写在证据命令表行内；不经委派评论补写
评侧（dep-11，同表述、同强度）：
  观测面窄于声称面 → blocker
  命令形态越受控边界 → blocker
  时机：在 dev-plan 阶段拦截，不留到 implement 阶段
不变量：两张稳定表表头/列集与双向唯一映射不被修改
```

## 4.4 回滚单元闭包算法（FR-4，`dep-9`）

```text
输入：riskSectionOrder（plan.md 第 4 章的风险与回滚策略）, taskGraph
① 若改动被其它 TASK 消费（共享改动）：
       回滚单元 ← {改动} ∪ 受影响下游消费者（依赖闭包，同 4.2 ②）
② 校验：回滚单元在风险节的执行顺序 = 逆拓扑顺序（先回滚下游消费者，再回滚上游改动）
③ 若单点 revert 会破坏下游 → 不得声明为单点回滚（必须写闭包回滚单元）
```

## 4.5 环境责任与即时 readiness 流程（FR-5，三侧）

```text
plan 侧（dep-12）：若证据依赖常驻服务/浏览器/数据库 →
   声明 {owner, 建立方式, 可获得性, readiness=复用该环境所保障行 FR 的既有 cmd-NN, 缺失处置=引用 ENVIRONMENT_MISMATCH}
   readinesMap：environment → cmd-NN（必须已存在于证据命令表且被交付覆盖表引用）
dev-start 侧（dep-14）：人工只确认上述静态前提 → 不要求服务在线（动态健康不入审批）
implement 侧（dep-13）：执行顺序
   for each TASK in topoOrder(tasks):
       若 TASK 依赖环境 E 且 E 尚未 readiness 验证:
           执行 plan 指定的 readinesMap[E]（既有「一次环境检查」的执行内容；最多一次重跑）
           fail → ENVIRONMENT_MISMATCH 中止 + 报告所需建立动作（不写账本/状态/评审 blocker）
       否则：照常执行（环境无关 TASK 不被提前阻断）
不变量：不新增环境 Pipeline 节点；coordinator 不启停共享服务
```

**边界**：环境无关 TASK 排在首位时先执行，不被环境依赖 TASK 的 readiness 阻塞；同一环境的 readiness 只验证一次（不反复探测），与 `dep-13` 既有「一次环境检查」bullet 一致。

## 4.6 零 diff 面与保持性约束（FR-6）

```text
diff(本 CR) ⊆ { dep-3, dep-9, dep-12 所在文件（write-dev-plan/SKILL.md）,
                dep-4 所在文件（write-dev-tasks/SKILL.md）,
                dep-11 所在文件（review-dev-plan/SKILL.md）,
                dep-13 所在文件（implement-code/SKILL.md）,
                dep-14 所在文件（code-implementation.pipeline.json 的 …0004 approvalPrompt 值）,
                KB 的 change-requests/CR-2026-068/** }
保持不变量：
  ① 节点数 5/4/12（dep-16）且 pipeline 节点集、reviewLoop.replayNodes、purpose 标签逐字不变（dep-8）
  ② dep-10 的 git 白名单与 deny 面零改动
  ③ dep-15 / dep-17 / dep-20 / dep-22 / dep-18 / dep-19 既有断言全部仍绿（§6.6）
  ④ 四个 review SKILL 的 Step 1.0 / Step 5 / Step 6 四要素与三 token 反向断言零命中（dep-15）
  ⑤ 不复活 recoverCommand / recover_command（dep-18）
```

---

# 5. 技术选型与替代方案

决策记录判据（三判据同时满足才记录）：难以逆转 + 无上下文会疑惑 + 有真实权衡替代。以下六项均满足；不伪造替代方案，不新增 ADR 文件或审批节点。

## D-1 承载体：原位改既有段落（选定）

- **Decision**：7 处改动全部落在既有段落/既有 bullet 内部（原位扩写或原位改写），不新增小节、不新增章节、不重编号 Step。
- **Context**：PRD §1.3.1 修订面表与 §7 明确「原位改四份 Skill 的既有段落 + 一处 pipeline 人工审批提示文本，零新增结构承载」；`dep-1` §8 规定普通 Skill 措辞调整不改 `ARCHITECTURE.md`。
- **Alternatives**：① 新增独立「增量回修」小节（否决：会与既有段落并存两套规则，直接违反 I2 与 NFR-3/AC-2③）；② 新增 plan.md 第八节承载环境声明（否决：违反 AC-5① 与 FR-5「不新增第八节」）。
- **Consequences**：改动面小、评审可逐字核对；代价是单段落变长，必须靠判据而非结构分隔可读性（由观测面判据与 blocker 强度兜底）。

## D-2 输入形态：新旧批准 SDD delta + 同轮未闭合 blockers（选定）

- **Decision**：upstream 轨的输入是「新旧批准 SDD 的变更 delta」与「同轮未闭合 plan blockers」，不把旧 plan 整轮作废。
- **Context**：PRD FR-1 第 2 条；`dep-2` §6.1「原文问题」指出全量重建是返工成本被放大的第一形态。
- **Alternatives**：把 canonical blockers 当作唯一输入（否决：upstream 轨的 blocker 来自 SDD 变更，不是 plan 评审意见）；要求 coordinator 传「受影响行清单」（否决：PRD §1.3.1 与 US-3 明确 coordinator 只传 subject/delta/canonical feedback 引用，不指定具体行）。
- **Consequences**：重写面与 delta 成正比；风险是 delta 判定依赖 SDD 两版对比，若 SDD 只有一处小改却影响大量稳定表行，仍会触发大范围重算——这是正确行为（影响面真实存在），不算回退。

## D-3 readiness 证据：复用既有 `cmd-NN`（选定）

- **Decision**：readiness 证据必须复用该环境所保障的那一行 FR 的既有 `cmd-NN`；无法复用时另立 CR。
- **Context**：PRD FR-5 第 4 条、AC-6；两张稳定表「验收证据 ↔ 证据ID」双向唯一映射合同（`dep-2` §6.5 已给出理由：不被交付覆盖表引用的命令行进表即 blocker，不进表则不构成合法 `cmd-NN`）。
- **Alternatives**：为 readiness 单独申请新 `cmd-NN`（否决：会放宽双向唯一映射，需改稳定表合同与评审判据，超出本 CR 边界）；用「非 `cmd-NN` 的自由命令」承载 readiness（否决：无 `executable`/`args`/`timeout` 与 `crctl test` 机器区下标，无法被既有机械核对覆盖，等于新增第二套验证语义）。
- **Consequences**：映射不破坏、环境声明可机械核对；代价是某些环境诉求被推迟到后续 CR（记入 `follow_up`）。

## D-4 索引刷新与重算语义分离（选定）

- **Decision**：`crctl task init` 只用于刷新 `tasks/_index.yml` 索引，不承担 delta 重算语义；重算语义写在 `dep-4` 所属 Skill 正文内。
- **Context**：`dep-7` / `dep-6` 的账本契约（受控账本唯一写入通道 + 三步断言）；PRD FR-2 第 1 条与 §1.5 第 7 条。
- **Alternatives**：让 `crctl task init` 承担「重算」语义（否决：CLI 契约零 diff 是本 CR 的 `zero_diff` 面，且账本写入口不应承担业务重算语义，会引入第二事实源）；新增 TASK append/rebuild 子命令（否决：新增子命令违反 FR-6③）。
- **Consequences**：`purpose: regenerate-tasks` 标签语义在 Skill 正文内明确，节点层零改动（不撞节点数与 `_index.yml` 断言）。

## D-5 dev-start 只确认静态前提（选定）

- **Decision**：`…0004` approvalPrompt 只确认环境 owner / 建立方式 / 可获得性等静态前提，不要求审批时所有服务在线。
- **Context**：PRD FR-5 第 6 条、US-5；`dep-2` §6.5 dev-start 侧。
- **Alternatives**：审批时要求环境全部在线（否决：把动态健康状态写成人工长期事实，审批会为瞬时状态背书，且会在 implement 之前制造伪阻塞）；把环境确认放进 implement 由 Agent 自证（否决：静态前提缺少人类确认点，环境 owner 与可获得性无人负责）。
- **Consequences**：静态与动态职责分离；风险是审批人可能误以为服务已在线——由提示文本显式写明「动态健康状态由 implement 侧即时验证、审批不为其背书」消解。

## D-6 本 CR 自身 SDD 的依赖表形态：`dep-N` 固定结构（选定）

- **Decision**：本文档 §6.3 采用 `dep-N` 固定结构（`repo` / `relative path` / `stable symbol/对象` / `40 位 commit SHA` / `依赖结论`）。
- **Context**：`dep-5` 的 `dep-N` 合同自 CR-2026-067 合并起对后续 SDD 生效；CR-2026-067 SDD 的 `D-6` 因当时合同尚未生效而使用实施前的编号列表形态，本 CR 不适用该时序差。
- **Alternatives**：沿用编号列表形态（否决：与本 CR 生效中的写作合同冲突，会形成第二套形态）。
- **Consequences**：正文对既有实现事实只写「设计依赖 `dep-N`」；编号按正文首次出现顺序分配（KB 设计输入与 tools 实现事实混排，不按仓分组，同一仓的条目编号不保证连续），本 CR 共 22 项。

---

# 6. FR 到技术实现映射

## 6.1 FR 逐条映射

| FR | 技术方案条目 | 目标落点 | 验收证据（PRD AC） |
|---|---|---|---|
| FR-1 upstream 后 plan 增量回修 | §1.4.1（I1）、§4.1（算法）、§6.5-A（逐字文本）；普通轨三条保留、upstream 轨四条新增、路由面不变 | `dep-3`（write-dev-plan Step 2a） | AC-1①~⑤ |
| FR-2 TASK 及依赖闭包重算 | §1.4.2（I2）、§4.2（算法）、§6.5-D（逐字文本）；「重新生成」零残留、`crctl task init` 只刷新索引、节点层零改动 | `dep-4`（write-dev-tasks Step 2a 第 1 条） | AC-2①~⑤ |
| FR-3 证据命令可执行性与证明力 | §1.4.3、§4.3（判据算法）、§6.5-B（写侧六项）、§6.5-E（评侧两条 blocker 判据） | `dep-9`、`dep-11` | AC-3①~⑤ |
| FR-4 回滚单元是依赖闭包 | §1.4.4、§4.4（算法）、§6.5-B（`回滚` bullet 三项） | `dep-9` | AC-4①~④ |
| FR-5 环境责任与即时 readiness | §1.4.5、§4.5（三侧流程）、§6.5-C / §6.5-F / §6.5-G | `dep-12`、`dep-13`、`dep-14` | AC-5①~③、AC-6①~③ |
| FR-6 边界与零新增 | §1.4.6、§4.6（零 diff 面）、§6.4（改动/零改动清单）、§6.6（门禁回归面）、§9 `zero_diff` | 全量（无新增承载） | AC-7①~④、AC-8①~④、AC-9①~③ |

## 6.2 AC 逐项设计与验收映射

> 每条 AC 给出「设计落点 / 可观测结果 / 可达性说明」。设计落点中的 `dep-N` 指 §6.3 的既有实现事实；`§6.5-X` 指本文档的目标文本条款。

**AC-1（FR-1）**

- 设计落点：`§6.5-A` 对 `dep-3` 所指 Step 2a 段落原位扩写（既有三条之后追加 upstream 轨）。
- 可观测结果：该段落文本可逐条核对——普通轨三条逐字保留；含「以新旧批准 SDD 变更 delta + 同轮未闭合 plan blockers 为输入」「同一份 plan 上只重算受影响章节 / 稳定表行 / 证据 / 回滚」「未受影响内容保留」「coordinator 只传 subject / delta / canonical feedback 引用」；`review-route` 枚举与 `repair-target` 单值语义未被修改；Step 编号 1/2/2a/3/4 未变。
- 可达性说明：`dep-3` 所指段落是 `write-dev-plan` 唯一的回修模式承载点（同文件无第二处回修规则），改写不依赖任何前置状态或过滤条件；upstream 轨的触发路径（`dep-7` 双轨路由 + `dep-8` replayNodes）在既有状态机上已连通，不需要新增转换。

**AC-2（FR-2）**

- 设计落点：`§6.5-D` 对 `dep-4` 所指 Step 2a 第 1 条原位改写。
- 可观测结果：「重新生成」措辞零残留（同一文件全文可检索）；该段表达 delta 重算 + 下游依赖闭包同步 + 输入/输出/接口/命令/`depends-on`/完成标志/回滚同步 + 未受影响 TASK 保留；写明 `crctl task init` 只刷新索引；文件内无第二套回修规则；`dep-6` 的「禁止 Agent/Skill 手写」句仍在；节点集 / 节点数 / `replayNodes` / `purpose: regenerate-tasks` 标签文本未变。
- 可达性说明：`dep-17` 的 CR-2026-037 用例两条 match 断言与一条 doesNotMatch 断言分别落在该段与 `dep-6`；本设计的改写使 doesNotMatch 天然仍绿（删词而非改词），不引入需要新断言的取值；`dep-8` 的节点层条目不在 diff 面内。

**AC-3（FR-3）**

- 设计落点：`§6.5-B`（`dep-9` 两张稳定表说明）+ `§6.5-E`（`dep-11` 的 `acceptance-verifiability`）。
- 可观测结果：写侧六项判据齐备且既有概括反假绿句保留（未另立第二句概括）；评侧两条 blocker 判据齐备；八类维度表与四个增量维度名未变；`dep-15` 的 S-13 三 token（`push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`）在 `dep-11` 文件内零命中；两张稳定表列集与双向唯一映射未变。
- 可达性说明：写侧判据加在既有列说明的同一 bullet 内（不依赖新列）；评侧判据加在既有维度行内（不新增维度名、不新增账本）；`dep-11` 文件的既有 Step 5 发布段与 Step 1.0 前置段不在改动面内，反向断言不会被新文字命中。

**AC-4（FR-4）**

- 设计落点：`§6.5-B` 的 `回滚` bullet 原位扩写（`dep-9`）。
- 可观测结果：该 bullet 含「共享改动的回滚单元必须包含受影响下游消费者」「与第 4 章风险与回滚策略逆拓扑顺序一致」「单点 revert 会破坏下游时不得声明为单点回滚」；交付覆盖表列集仍为 5 列。
- 可达性说明：`回滚` 列在既有稳定表中已存在且每行必填（不存在空值旁路），判据只是收紧该列的写作口径，不依赖新前置；逆拓扑一致性由风险节既有章节（`dep-9` 所属文件的 plan.md 章节 4）承载，无需新章节。

**AC-5（FR-5）**

- 设计落点：`§6.5-C`（plan 章节 5，`dep-12`）+ `§6.5-F`（implement 环境节，`dep-13`）+ `§6.5-G`（`…0004` approvalPrompt，`dep-14`）。
- 可观测结果：① plan 章节 5 含环境五要素（owner / 建立方式 / 可获得性 / readiness 复用既有 `cmd-NN` / 缺失时 `ENVIRONMENT_MISMATCH` 处置引用），plan.md 章节数仍为 7；② 提示文本只确认静态前提、不要求服务在线、无 `git`/`journal` 字样、保留 ✅/❌ 两分支、无 `review-annotations`/`reject_reason` 残留，节点对象其余字段与节点集零变化；③ implement 环境节含 readiness 即时性、失败按既有标签中止并报告建立动作、环境无关 TASK 不被提前阻断，且既有 bullets 未改写。
- 可达性说明：三侧各自有唯一承载点（plan 章节 5 说明 / `…0004` approvalPrompt 值 / `dep-13` 环境节），互不覆盖；`dep-15` 的 git/journal 零命中断言是保持性断言（本设计通过不写这些字面量满足，不需新增断言）；`dep-13` 的六条既有 bullets 原样保留，新 bullets 同节共生。

**AC-6（FR-5，映射不破坏）**

- 设计落点：`§6.5-C` ④（readiness 复用既有 `cmd-NN`）+ §4.5 的 `readinesMap` + §9 `follow_up` 第 1 项。
- 可观测结果：两张稳定表「验收证据 ↔ 证据ID」双向唯一映射未被放宽或修改（`dep-7` 覆盖矩阵节机械核对判据原样保留）；全文无「为 readiness 单独申请新 `cmd-NN`」的形态文字；无法复用场景的文字指向「另立 CR」。
- 可达性说明：`dep-9` 的证据命令表要求每条命令有 `证据ID`/`executable`/`args`/`timeout` 且被交付覆盖表引用（`dep-7` 双向核对），因此「合法 `cmd-NN`」的定义域不含「仅 readiness 用」的命令行；本设计只引用既有行，不产生不可达的目标对象。

**AC-7（FR-6，零新增）**

- 设计落点：§4.6 的 diff 上界 + §6.4 的改动/零改动清单 + §9 `scope_in`/`zero_diff`。
- 可观测结果：交付 diff 只含 §1.3.1 表内 5 个文件（7 处落点）；`skills/shared/crctl/scripts/**`（含全部测试与 `gate-registry.json`）、`write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline`、pipeline 节点集与 reviewLoop、`tools/agents/**`、`agent-skill-matrix.yml`、`../multica/**`、KB `specs/`/`delivery/`/`docs/` 零 diff；节点数 5/4/12 与 `dep-16` 一致；账本字段 / 评审维度 / 观测指标 / crctl 子命令 / flag / 错误码零新增。
- 可达性说明：diff 面由 §6.5 的 7 处落点穷举（无第八处）；零 diff 面由 `dep-15` / `dep-17`~`dep-19` 的既有断言与 `dep-20` / `dep-22` 的门禁登记与 `dep-16` 的计数投影覆盖，不依赖人工记忆；`dep-16` 的节点计数是跨文件投影的唯一登记处，本设计不改该文件即可保持。

**AC-8（FR-1~FR-6，CR-2026-066 / 067 面零 diff）**

- 设计落点：§4.6 ④ + §6.4 零改动核对清单 + §9 `zero_diff`。
- 可观测结果：四个 review SKILL 的 Step 1.0 clean 前置与 Step 5 PASS 发布对账四要素（`phase` / `batchId` / `repositories[]` / `metadataCommit`）逐字保留；四 SKILL 不含 `crctl checkpoint`、不含三 token；`write-tech-design` / `review-tech-design` 零 diff；`dep-15`（CR-2026-043 / CR-2026-037 / 节点数 5/4/12）、`dep-17`（CR-2026-029）用例全部仍绿。
- 可达性说明：本设计的 diff 面不含这四个 SKILL 的 Step 1.0 / Step 5 / Step 6 与两份 CR-2026-067 目标文件，零 diff 是结构性结论（不是「未观察到」）；`dep-11` 文件的新增文字只进增量维度行，S-13 三 token 在新增文字中零出现（§6.5-E 逐字文本可直接核对）。

**AC-9（边界与串行）**

- 设计落点：§9 `scope_out` + §6.6 门禁回归面 + 本 CR 的串行事实（`dep-1` §7 顺序约束）。
- 可观测结果：实施与交付期间 `change-requests/_backlog.yml` 在途条目只有本 CR（CR-2026-063/064/065/066/067 均为 `archived`，`crctl status` 可核）；本 CR 在 CR-P1(067) 之后落地（本轮实读 067 = `archived` / terminal）；`suite-gate --run` 全量绿、`dep-20` 的 `manifest.cases` 与实际顶层用例数一致（36）、`exceptions` 为空数组。
- 可达性说明：串行与顺序是实施期可核事实（不属于本 SDD 的产物，由实施/交付期核对）；门禁面由 `dep-22` 的判据语义（`cases <` 登记值即红）机械判定，本设计预期零测试改动，故不存在「登记值需同步」的前置条件；若实施期用例数意外变化，按 `dep-1` §1.5 第 2 条同 CR 同步登记值、不签例外。

## 6.3 既有实现依赖与事实

**收录判据**：SDD 正文引用到的既有实现事实必须入册——① 设计判据的成立前提（文本形态、结构、调用顺序、断言面）；② 本 CR 直接修改的既有文本；③ §9 `zero_diff` 中设计所依赖的既有文本；④ SDD-CLOSE 的证据。**编号按正文首次出现顺序分配，只增不改；本文档无删除条目，故无编号空洞。**

**排序**：严格按正文首次出现顺序（不按仓分组）：编号即正文首次引用序，KB 设计输入与 tools 实现事实混排，因此同一仓的条目编号不保证连续；本文档无删除条目，故无编号空洞。正文对 `dep-1` 的 FR/AC 编号引用（如「FR-3」「AC-5」）是**需求合同标识引用**，不是既有实现事实。

**取证口径（SHA 三仓）**：

- `tools` 条目：`commit SHA` = 本 CR `tools` worktree HEAD `49fa37748d9b2fc7fc58fd53f839e2ed293bde17`（= `tools` trunk；`crctl workspace inspect` 实读 `head` 即该分支）。
- `ai-first-platform-docs`（KB）条目：`commit SHA` = 各过程产物的**引入提交**（本节逐条给出），KB worktree 起草时 HEAD = `a459fde8cb8af126cdb4edc5f89124acc0568c16`（`[cr] status CR-2026-068 requirement-approved -> tech-designing`），其前一步 `6e4d849bbc14ed0635f1053ae1d254daa6616acd` 为需求审批发布的 checkpoint metadata commit。
- `../multica` 条目：本 CR 无匹配依赖（零 diff，无常量事实被引用），故不登记；如需核对「未触碰」事实，以 `multica` worktree HEAD `d4a49e2b9ca7d83368737cd57d6a697d3bd042b4` 为基线。

```text
dep-1
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-068/prd.md
  stable symbol/对象: FR-1~FR-6、AC-1~AC-9、§1.3.1 修订面表与零 diff 清单、§1.3.3 契约说明（四查 N/A 的三条理由）、§1.4 事实 1~21、§1.5 七条口径、§7 范围排除
  commit SHA: bd86a82a50ad53f13d67d2a2dd7eb0e1a80c56e4
  依赖结论: 本 CR 的全部 FR/AC 与边界取自该需求合同（本轮实读全文 297 行）；SDD 的 §1.5 承接表、§6.4 零 diff 清单、§9 四字段均以它的明文为判据。其 §1.4 事实 21 的「cmp 逐字节一致 / 33,478 B」只在 EOL 归一后成立（该断言不构成本设计的任何前提，见 §1.5 末段与 SDD-CLOSE-05）。
```

```text
dep-2
  repo: ai-first-platform-docs
  relative path: docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md
  stable symbol/对象: §6（CR-P2，§6.1~§6.7 与边界段落）、§1.4「不增加观测指标」、§7「继续复用、不再造」清单、§8 实施顺序第 6 条
  commit SHA: 8c0df453ea1b59a38946515784538732249ad9f2
  依赖结论: 需求来源，钉定四项问题的根因与「原位改 + 零新增承载」的杠杆；本设计 §1.4.1~§1.4.5 的判据与 §5 的替代方案否决理由逐条对应该节原文。
```

```text
dep-3
  repo: tools
  relative path: skills/develop/write-dev-plan/SKILL.md
  stable symbol/对象: `### Step 2a — 回修模式（CR-2026-026 FR-8/FR-9）` 段落（普通轨三条；无 upstream 轨文字）与 TOC 的 Step 1 / Step 2 / Step 2a / Step 3 / Step 4 编号
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-1 的唯一修订面与不可破坏面（普通轨三条逐字保留、Step 编号不重编）；本设计在该段落内原位追加 upstream 轨，不新增小节。
```

```text
dep-4
  repo: tools
  relative path: skills/develop/write-dev-tasks/SKILL.md
  stable symbol/对象: `### Step 2a — 回修模式（CR-2026-026 FR-8/FR-9）` 第 1 条（现行「重新生成」段）与同节第 2、3 条
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-2 的唯一改写面；现行文字与 delta 语义直接矛盾（`重新生成` + `不保留旧 TASK`），本设计在同一段第 1 条内原位改写且保持 3 条结构，避免两套规则并存。
```

```text
dep-5
  repo: tools
  relative path: ARCHITECTURE.md
  stable symbol/对象: `## 4. 分层与依赖方向`（Pipeline → Skill → crctl 依赖只朝下）、`## 5. 硬不变量`（不变量 1 状态单一写者、2 账本单一写入通道、3 零第三方依赖、4 行尾与硬失败纪律、8 Skill 通用约束归仓）、`## 6. 刻意不做` 第 1 行、`## 8. 本文档的维护规则` 第 2 条（普通 Skill 措辞调整不需要改本文档）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: §1.3 的三条硬约束与多仓口径、§1.1 的 I1~I6 逐条取自本文件（本轮实读全文）；本 CR 不新增层级、不新增写入口与账本文件，且属「普通 Skill 措辞调整」故本文档零 diff。
```

```text
dep-6
  repo: tools
  relative path: skills/develop/write-dev-tasks/SKILL.md
  stable symbol/对象: `### Step 4 — TASK 数量三步断言与索引初始化`（三步断言 + `crctl task init --count-hint` + `TASK_COUNT_MISMATCH`）与「`tasks/_index.yml` 是受控账本，禁止 Agent/Skill 手写」句；Step 3 的 TASK frontmatter 与正文 6 节结构
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 索引刷新与账本写入通道的既有契约（也是 `dep-17` 用例的载体）；本设计只把 `crctl task init` 的角色钉为「只刷新索引」，不改其调用形态、不手写账本、不改 TASK 卡结构。
```

```text
dep-7
  repo: tools
  relative path: skills/develop/review-dev-plan/SKILL.md
  stable symbol/对象: `### Step 4 — 路由处理（双轨，CR-2026-026 FR-6/FR-6a/FR-6b）` 的 NORMAL / UPSTREAM 分支；`### 覆盖矩阵与流程控制核验` 的「两张稳定表同口径复核（CR-2026-060 AC-07）」双向唯一映射判据
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: upstream 轨的进入路径（`review-dev-plan:upstream-design-blocker` → `tech-design-review-pending`）与「验收证据 ↔ 证据ID」双向唯一映射的机械核对在该文件的既有段落内；本设计复用不修改（`zero_diff` 面），readiness 复用 `cmd-NN` 的硬边界以此为前提。
```

```text
dep-8
  repo: tools
  relative path: pipeline-templates/code-implementation.pipeline.json
  stable symbol/对象: 节点顺序 `…0001 write-dev-plan → …0002 write-dev-tasks → …0014 review-dev-plan → …0004 human_approval → …0005 approve-dev-start`；`…0014.reviewLoop.replayNodes` 三项（`repair-plan` / `purpose: regenerate-tasks` / `rerun-current-review`）与 `maxAttempts: 3`
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 「两个 authoring 节点 + 复审」的重放路径已存在，本 CR 只在 Skill 正文内明确 `purpose: regenerate-tasks` 的 delta 语义，节点集/顺序/replayNodes 逐字不变。
```

```text
dep-9
  repo: tools
  relative path: skills/develop/write-dev-plan/SKILL.md
  stable symbol/对象: `### Step 2 — 生成 plan.md` 的章节 6「两张稳定表」说明：交付覆盖表 5 列（`FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`）与证据命令表 6 列；`验收证据` bullet（既有概括反假绿句）与 `回滚` bullet（现文「该 FR 的回滚单元（如 revert 某 TASK commit）」）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-3 写侧与 FR-4 的唯一修订面，也是两张稳定表列集与双向唯一映射的判据来源；本设计只在该说明的既有 bullets 内扩写，列集与表头不动。
```

```text
dep-10
  repo: tools
  relative path: skills/shared/controlled-shell/rules.json
  stable symbol/对象: `git` 白名单（子命令 + 形态 + 调用者三元）、`forbiddenFlags`、`protectedPaths.deny`（`change-requests/...`、`approval.yml`、`review-loop.yml`、`review-annotations/*.yml`）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-3 的「涉 Git 命令必须使用已允许的受控入口」以本文件为唯一事实源；本 CR 零 diff（不新开裸面、不放宽 deny），因此新文字只写「按 rules.json 既有允许面」而不复述规则细节。
```

```text
dep-11
  repo: tools
  relative path: skills/develop/review-dev-plan/SKILL.md
  stable symbol/对象: `### 增量职责与事实核验（CR-2026-055）` 的 `acceptance-verifiability` 行；`### Step 2 — 八类维度评审（FR-3）` 的「验收可验证性」行
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-3 评侧的唯一落点；现行文字只有概括判据（真实责任边界组合证明 AC、拒绝假绿短路），本设计在同一条内补齐两条可判定 blocker 判据，不新增维度名。
```

```text
dep-12
  repo: tools
  relative path: skills/develop/write-dev-plan/SKILL.md
  stable symbol/对象: `### Step 2 — 生成 plan.md` 的章节清单第 5 项「验收与发布策略」（现行说明仅「发布前 checklist / feature-flag 计划」）与章节总数 7
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-5 plan 侧的唯一修订面；本设计在该章节项说明内原位扩写环境五要素，章节总数保持 7（不新增第八节）。
```

```text
dep-13
  repo: tools
  relative path: skills/develop/implement-code/SKILL.md
  stable symbol/对象: `## 环境验证与 ENVIRONMENT_MISMATCH` 节（六条既有 bullets：一次环境检查 / 最多一次重跑 / timeout 与测试入口 / 标签不写 crctl 状态·gate·账本·评审 blocker·测试证据 schema / 临时隔离实例例外 / 受控建立归因）与「本 Skill 是有界验证与 ENVIRONMENT_MISMATCH 的唯一详细事实源」声明
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-5 implement 侧的唯一落点与该标签的单一事实源；本设计同节追加 readiness 即时性与「环境无关 TASK 不提前阻断」两条 bullets，既有六条逐字保留。
```

```text
dep-14
  repo: tools
  relative path: pipeline-templates/code-implementation.pipeline.json
  stable symbol/对象: 节点 `00000000-0000-0000-0015-000000000004`（kind=human_approval，label「确认进入代码开发」）的 `approvalPrompt` 现行值（拆分完成确认 + ✅ 通过 / ❌ 暂缓 两分支）与节点对象其余字段（id / kind / label / onFail / timeoutMinutes）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-5 dev-start 侧的唯一修订面；现行值不含环境内容，本设计只替换该字符串值（保留两分支、不写 git/journal、不残留 review-annotations 与 reject_reason），节点对象其余字段与节点集不变。
```

```text
dep-15
  repo: tools
  relative path: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
  stable symbol/对象: CR-2026-043 用例（全部节点 `prompt` 与 `approvalPrompt` 对 `\bgit\b` / `\bjournal\b` 零命中）、CR-2026-050 FR-01 用例（human_approval 无 `review-annotations` / `reject_reason`、保留 approve/reject）、CR-2026-066 S-13 反向断言（四个 review SKILL 无 `crctl checkpoint` 与三 token）、节点数/顺序断言（12 节点、`…0014 < …0004 < …0005`）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 本 CR 新增文字的保持性约束来源（尤其 `…0004` approvalPrompt 的字面禁令与 `dep-11` 文件的三 token 禁令）；本设计通过约束写法满足这些断言，不新增/不修改测试。
```

```text
dep-16
  repo: tools
  relative path: pipeline-templates/_index.yml
  stable symbol/对象: `requirement-authoring-v1 nodes: 5`、`architecture-design-v1 nodes: 4`、`code-implementation-v1 nodes: 12` 三处计数（跨文件投影的唯一登记处）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 节点数口径 5/4/12 的唯一登记值与 CR-2026-066 的注释来源；本 CR 零 diff，故两侧计数天然一致（`dep-15` / `dep-17` 的等式断言仍绿）。
```

```text
dep-17
  repo: tools
  relative path: skills/shared/crctl/scripts/test/crctl.test.mjs
  stable symbol/对象: CR-2026-037 用例（`write-dev-tasks/SKILL.md` 必含 `crctl task init` 与 `禁止 Agent/Skill 手写`；不得含 `/重新生成.*TASK 与 `_index\.yml`/`；pipeline 节点数 ≡ `_index.yml`；节点 prompt 对受治理账本写指令零命中）与 CR-2026-029 用例（write-dev-tasks 与 pipeline 不含发布联调类 TASK 拆分指引）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-2 改写后仍须满足的既有断言载体；本设计删除「重新生成」措辞使 doesNotMatch 天然仍绿，并保留两条 match 断言所需的字面量。
```

```text
dep-18
  repo: tools
  relative path: skills/shared/crctl/scripts/test/contract-scan.test.mjs
  stable symbol/对象: AC-1 扫描面（3 个 pipeline JSON + 11 个 SKILL.md 对 `repair-instructions` / `fixed-blockers` / `suggestion_policy` / `suggestion-policy` 零命中）与 RETIRED_RECOVERY（`recoverCommand` / `recover_command`）整树零命中
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 本 CR 新增文字不得引入退役字段名（`dep-1` FR-6 第 5 条）；该扫描面包含本 CR 的四个目标 SKILL 之一与 code-implementation pipeline，本设计零命中。
```

```text
dep-19
  repo: tools
  relative path: skills/shared/crctl/scripts/lint-prompts.mjs
  stable symbol/对象: R1~R13 规则集（R1 guard-deny 手写、R2 裸 git、R3~R5 字面黑名单、R7 crctl 参数形态、R9「下一步」收敛等）与 enforce 模式
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 新增文字在 Skill 内不得命中「手写受保护账本 / 裸 git / 手写 review-loop 记账 / 手写 test-report / 自造下一步映射」等规则；本设计的新文字只描述判据与写作口径，不出现裸 git 命令、不指示手写账本、不写状态映射副本。
```

```text
dep-20
  repo: tools
  relative path: skills/shared/crctl/scripts/test/gate-registry.json
  stable symbol/对象: `manifest.cases["pipeline-structure.test.mjs"] = 36` 与 `exceptions: []`（登记面）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 门禁登记值当前与实际一致（CR-2026-067 已同步）；本 CR 预期零测试改动，故不触碰该文件、不签任何例外。
```

```text
dep-21
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-068/review-annotations/requirement.yml
  stable symbol/对象: canonical 需求评审结论（verdict=pass / blockers=[] / suggestions 含「PRD §1.4 事实 21 的 EOL 事实」一条）与 review-loop.yml 的 attempt 记录
  commit SHA: 8895e9e6f48aad4a6c5ed54c074b78607799839a
  依赖结论: 需求期评审已闭合、无 blocker；该 suggestion 指明「字节级断言只在 EOL 归一后成立」，本设计据此按「内容一致（EOL 归一后）」理解来源对齐，且不在任何目标文本中写 `cmp`/字节数口径。
```

```text
dep-22
  repo: tools
  relative path: skills/shared/crctl/scripts/test/suite-gate.mjs
  stable symbol/对象: 门禁判据语义「每文件用例数 `<` `manifest.cases` 登记值即红（`SUITE_MANIFEST_CASE_DROP`）」，不变量 I1~I3（文件集合事实源、逐文件 TAP 归属、不可判即硬失败）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: AC-9③「suite-gate 全量绿 + 登记值一致 + 零例外」的判据来源；本 CR 不改该文件，改动面不新增用例也不删除用例。
```
## 6.4 既有测试面改动清单与零改动核对清单

**改动清单：无。** 本 CR 预期不新增、不修改任何测试文件（`dep-1` §1.5 第 2 条）。逐条理由：

| 既有断言 | 与本次改动的关系 | 结论 |
|---|---|---|
| `dep-17` CR-2026-037 `doesNotMatch(/重新生成.*TASK 与 `_index\.yml`/)` | 「重新生成」措辞被删除 | 天然仍绿（删词不改结构） |
| `dep-17` CR-2026-037 两条 `match`（`crctl task init` / `禁止 Agent/Skill 手写`） | 两处字面量均在，`dep-6` 句未触碰 | 保持 |
| `dep-17` pipeline 节点数与受治理账本写指令零命中 | `…0004` 只改 approvalPrompt 值；新文本不含账本写指令；节点数不变 | 保持 |
| `dep-15` `\bgit\b` / `\bjournal\b` 零命中（全部节点 prompt + approvalPrompt） | 新 approvalPrompt 文本不使用这两个字面量 | 保持 |
| `dep-15` CR-2026-050 FR-01（human_approval 无 `review-annotations` / `reject_reason`，保留 approve/reject） | 新 approvalPrompt 保留 ✅/❌ 两分支、无违规残留 | 保持 |
| `dep-15` S-13 三 token 与 `crctl checkpoint` 零命中（四个 review SKILL） | `dep-11` 新文字不含这四个 token | 保持 |
| `dep-18` FORBIDDEN / RETIRED / RETIRED_RECOVERY 零命中 | 新文字不含这些字段名 | 保持 |
| `dep-20` `manifest.cases["pipeline-structure.test.mjs"] = 36`、`exceptions: []` | 零测试改动 | 保持（不签例外） |

**零 diff 核对清单（AC-7② / AC-8③ 的可核对形式）**：

| 零 diff 对象 | 核对方式 |
|---|---|
| `skills/shared/crctl/scripts/**`（含 `test/**`、`gate-registry.json`） | diff 面穷举（§6.5 无落点） |
| `write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline` | diff 面穷举（CR-2026-067 面） |
| 四个 review SKILL 的 Step 1.0 / Step 5 / Step 6 | `dep-15` 反向断言 + diff 面穷举 |
| `pipeline-templates/**` 除 `…0004` approvalPrompt 值以外 | diff 面穷举；节点集 / reviewLoop / 其余 prompt 与 `dep-8` 逐字一致 |
| `tools/agents/**`、`agent-skill-matrix.yml`、`dir-graph.yaml`、`ARCHITECTURE.md` | diff 面穷举 |
| `../multica/**` | diff 面穷举（不触碰该仓 worktree） |
| KB `specs/` / `delivery/` / `docs/` | diff 面穷举（`dep-2` 来源文档只读） |

**四字段自洽前置核对（`dep-7` / 评审 Step 2 的批准范围前置）**：① `scope_in` 与 `zero_diff` 无同对象冲突（§9 逐条比对：`scope_in` 的 7 处落点与 `zero_diff` 的零 diff 集合互斥）；② 无「外部治理规则强制修改」面——`dep-15` / `dep-17` / `dep-18` 对本 CR 的约束是**保持性**（不写某些字面量），不是强制修改，已在 §9 给出合法出口（约束写法而非改测试）；③ `scope_out` 未隐藏当前交付必须发生的修改（7 处落点全部列入 `scope_in`）；④ `follow_up` 未承载任何当前 AC 的必要条件。

## 6.5 目标文本清单（实施时逐字写入）

> 说明：以下为**逐字目标文本**（设计产物）。`…` 表示「原文逐字不变、此处省略」。7 处均为**原位替换或原位追加**：不新增小节、不新增章节、不重编号 Step、不新增列。目标文本内**不出现 `dep-N`**（`dep-N` 是 SDD 的引用形态，不进 Skill/pipeline 文本）。

### 6.5-A `write-dev-plan/SKILL.md` — Step 2a 段落（`dep-3`）末尾原位追加 upstream 轨

**追加目标（既有三条之后，作为同节内的加粗小标题 + 四条，不另起 `###` 标题）**：

```text
**upstream 轨（SDD 重新批准后的增量回修）**：当回修输入来自 `review-dev-plan:upstream-design-blocker` 之后的 SDD 修订与重新批准（人工修订 → 重新评审 → 重新批准 → 按 pipeline 既有 reviewLoop 重放本节点）时：

1. 输入 = **新旧批准 SDD 的变更 delta** 与**同轮未闭合 plan blockers**；不把旧 plan 当作整轮作废。
2. 在**同一份 `plan.md`** 上只重算受影响章节、稳定表行、证据与回滚；未受影响内容逐字保留（重写面与 delta 成正比）。
3. coordinator 只传 subject、delta 与 canonical feedback 引用，**不指定具体行如何修改**。
4. 本轨不修改 review-route 枚举、不把 `repair-target` 改成多值：路由仍由既有 `review-dev-plan` Step 4 UPSTREAM 分支与状态机既有转换承载。
```

### 6.5-B `write-dev-plan/SKILL.md` — 两张稳定表说明（`dep-9`）三处原位扩写

**（B-1）`验收证据` bullet：既有句逐字保留，其后追加三条子项**：

```text
   - `验收证据`：稳定标识 `cmd-NN`（两位十进制，与 `crctl test` 机器区 `commands` 1-based 下标及 `test-evidence/cmd-NN.log` 全等）；该命令必须实际覆盖本行所声称的验收面，不得只覆盖其中一部分造成假绿。
     - 观测面 ≥ 声称面：每个 `cmd-NN` 必须能观测该表行声称的 AC 结果；命令必须可执行（`executable` 直接可 spawn 的单个可执行文件，`args` 为 JSON token 数组，`cwd` 为 tools CR worktree 内相对路径，`timeout` 为秒）。
     - 四类典型错配：`--list` 类命令不能证明浏览器行为；文件级 `--name-only` 不能证明符号级不变量；子集测试不能声称全量；涉及 Git 的命令必须使用 `rules.json` 已允许的受控入口（不新开裸面、不改 `rules.json`）。
     - 命令算法唯一事实源 = 证据命令表行；不得通过委派评论补写命令算法。
```

**（B-2）`回滚` bullet：既有句逐字保留，其后追加闭包判据**：

```text
   - `回滚`：该 FR 的回滚单元（如 revert 某 TASK commit）；被其它 TASK 消费的共享改动，其回滚单元必须包含受影响下游消费者，并与第 4 章「风险与回滚策略」的逆拓扑顺序一致；单点 revert 会破坏下游时不得声明为单点回滚。
```

**（B-3）证据命令表 bullets 之后追加一句（不改既有 bullets）**：

```text
   - 证据命令表的命令行是 `cmd-NN` 的唯一事实源：命令算法只写在表内（`executable` / `args` / `cwd` / `timeout`），不得另行改写或补写。
```

### 6.5-C `write-dev-plan/SKILL.md` — 章节清单第 5 项（`dep-12`）原位扩写

**替换目标（该行说明整体替换；章节数保持 7、不新增第八节）**：

```text
5. **验收与发布策略** — 发布前 checklist / feature-flag 计划；若验收证据依赖常驻服务、浏览器或数据库，本节必须同时写明环境的静态前提与即时验证口径（不新增第八节）：
   - 环境 owner、建立方式、可获得性：责任人与获得途径，不写具体命令；
   - readiness 证据：必须复用**该环境所保障的那一行 FR 的既有 `cmd-NN`**（证据ID 照抄证据命令表，不新增命令行）。两张稳定表「验收证据 ↔ 证据ID」双向唯一映射不得放宽；确实无法复用时，该诉求超出本计划边界，**另立 CR** 修改稳定表合同与对应评审判据，本计划不放宽该映射；
   - 缺失时处置：按既有 `ENVIRONMENT_MISMATCH` 标签中止并报告所需建立动作（该标签的唯一详细事实源是 `implement-code`，此处只引用不复述）。
```

### 6.5-D `write-dev-tasks/SKILL.md` — Step 2a 第 1 条（`dep-4`）原位改写

**替换目标（第 1 条整体替换；第 2、3 条逐字保留，条目数仍为 3）**：

```text
1. 逐条消费 blockers（每条内含可执行修复说明），并执行 plan→TASK delta 重算：`write-dev-plan` 完成 SDD→plan delta 后继续同步 plan→TASK；重算**直接受影响 TASK**（普通轨 blockers 指向的 TASK 与 SDD→plan delta 波及的 TASK 都是「直接受影响」的来源）及其**下游依赖闭包**（`depends-on` 可达的传递闭包），同步更新受影响 TASK 的输入、输出、接口（接口契约节的消费/产出签名）、命令、`depends-on`、完成标志与回滚；未受影响 TASK 保留；`crctl task init` 只用于刷新 `_index.yml` 索引，不承担重算语义（被评审判废/删除的 TASK 从文件集移除后由索引刷新反映）。
```

**保持项**：第 2 条（禁空转）与第 3 条（`tech-design-reviewed` 重放态）逐字保留；文件内不得出现第二套回修规则；`重新生成` 措辞在本文件内零残留。

### 6.5-E `review-dev-plan/SKILL.md` — 增量维度 `acceptance-verifiability`（`dep-11`）同一条原位扩写

**替换目标（该 bullet 整体替换）**：

```text
- `acceptance-verifiability`：核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路；同一判据覆盖证据命令的证明力——**观测面窄于声称面即 blocker**（命令无法观测该表行声称的 AC 结果、`--list` 类命令声称浏览器行为、文件级 `--name-only` 声称符号级不变量、子集测试声称全量），**命令形态越受控边界即 blocker**（涉及 Git 的命令未使用 `rules.json` 已允许的受控入口、命令算法只存在于委派评论而不在证据命令表行），不留到 implement 阶段才暴露。判据落在既有维度内，不新增维度名或证据账本。
```

### 6.5-F `implement-code/SKILL.md` — 环境节（`dep-13`）末尾原位追加两条 bullets

**追加目标（既有六条 bullets 逐字保留，同节共生）**：

```text
- 即时 readiness：在**第一个依赖环境的 TASK 前**执行 plan 指定的 readiness `cmd-NN`；该命令是既有「一次环境检查」在环境依赖 TASK 上的执行内容（不是新的反复探测），仍受「最多一次重跑」、测试计划 timeout 与受控入口约束。
- 失败时按既有 `ENVIRONMENT_MISMATCH` 中止并报告所需建立动作；**环境无关 TASK 不被提前阻断**（readiness 未通过只阻断依赖该环境的 TASK）。
```

### 6.5-G `code-implementation.pipeline.json` — 节点 `…0004` 的 `approvalPrompt` 值替换（`dep-14`）

**替换目标（JSON 字符串值；节点 id / kind / label / onFail / timeoutMinutes 不变，节点集不变）**：

```json
"approvalPrompt": "TASK 拆分已完成（change-requests/{{inputs.cr_id}}/plan.md 与 tasks/），当前应为 task-breakdown。请确认是否进入代码开发，并一并确认 plan.md「验收与发布策略」声明的环境静态前提：\n\n环境静态前提（只确认静态事实，不要求审批时所有服务在线）：环境 owner 已明确、建立方式已写明、可获得性已声明。动态健康状态由 implement-code 在第一个依赖环境的 TASK 前用 plan 指定的 readiness 证据即时验证，审批不为其背书。\n\n✅ 通过：勾选此 Todo，下一节点 approve-dev-start 会记录确认并推进到 developing\n❌ 暂缓：补充任务拆分意见或环境前提说明，重新执行 write-dev-tasks 后再确认"
```

**字面量自查（逐条对应 `dep-15`）**：不含 `git` / `journal`（词边界、大小写不敏感均零命中）；不含 `review-annotations` / `reject_reason`；保留 ✅ 通过 / ❌ 暂缓两分支结构化决定。

## 6.6 门禁与回归面（NFR-1 / NFR-5）

| 项 | 结论 |
|---|---|
| 单元 / 集成测试改动 | **零**（§6.4）：既有断言全部为保持性关系，无一需要同步修改 |
| `dep-22` `suite-gate --run` | 期望全量绿；判据语义不变（`cases <` 登记值即红） |
| `dep-20` 登记面 | `manifest.cases` 保持 36、`exceptions` 保持 `[]`（不签任何新例外） |
| `dep-15` 字面禁令 | 新文本零命中（§6.5-G 自查；`dep-11` 新文字零命中三 token） |
| `dep-18` 退役字段 | 新文本零命中 |
| `dep-19` lint-prompts enforce | 新文本不得命中 R1~R13（不手写受保护账本、不裸 git、不手写 review-loop/test-report、不自造「下一步」映射） |
| CI | tools 仓既有 workflow 保持，无新增 step |
| 行尾 | 目标文件保持 LF 检出内容一致；读取方按既有 `readAllNormalized` / `replaceAll('\r\n','\n')` 归一（NFR-5、`dep-5` 不变量 4） |

## 6.7 SDD-CLOSE 关闭义务（CR-2026-060 AC-06）

**预检结论**：`dep-1` 全文（本轮实读 297 行）**未出现**「留待 SDD」「延后到设计」「设计期确定」类显式延后项（检索面：`dep-1`）；因此不存在「PRD 显式延后到 SDD 的设计项」这一义务来源。为便于 `review-tech-design` 机械核对，本 SDD 仍把四项需求期只给语义、需设计期钉定到可实施形态的事项逐项关闭（编号从 `SDD-CLOSE-01` 起，只在本节定义）：

| 编号 | 事项（需求期状态） | 关闭结论 | 覆盖层（数据生产 / 存储·传输 / 响应·schema / 消费 / 兼容降级） |
|---|---|---|---|
| SDD-CLOSE-01 | plan 侧环境声明的**书写形态**（`dep-1` FR-5 只钉「不新增第八节」） | 关闭：写入章节清单第 5 项说明内的三条子项（§6.5-C），章节总数仍 7、不新增节、不新增表 | 生产 = 计划写作（Skill 正文）；存储·传输 = `plan.md` 章节 5 文本；schema = plan.md frontmatter 与章节集不变；消费 = `write-dev-tasks` / `implement-code` / dev-start 审批人；兼容降级 = 无 `cmd-NN` 复用 → 另立 CR |
| SDD-CLOSE-02 | `…0004` approvalPrompt 的**最终文字**（`dep-1` FR-5 第 6/7 条只给约束：保留两分支、无 git/journal、无 review-annotations/reject_reason） | 关闭：§6.5-G 给出逐字目标值并通过字面量自查；节点对象其余字段与节点集零变化 | 生产 = pipeline JSON 值替换；存储·传输 = `pipeline-templates/code-implementation.pipeline.json`；schema = 节点对象字段集不变；消费 = human_approval 节点展示 + `approve-dev-start`；兼容降级 = 无（纯文本） |
| SDD-CLOSE-03 | readiness 复用既有 `cmd-NN` 的**引用形态**（`dep-1` FR-5 第 4 条只给硬边界） | 关闭：§6.5-C 第二条子项——「证据ID 照抄证据命令表，不新增命令行」，且不放宽双向唯一映射；无法复用 → 另立 CR | 生产 = plan 章节 5 文本；存储·传输 = 同上；schema = 稳定表列集与证据ID空间不变；消费 = implement 侧 readiness 执行 + `review-dev-plan` 覆盖矩阵核对；兼容降级 = 另立 CR 出口 |
| SDD-CLOSE-04 | 「直接受影响 TASK」与「下游依赖闭包」的**判定口径**（`dep-1` FR-2 只给语义） | 关闭：§4.2 给出传递闭包口径（`depends-on` 可达），并由 §2.4 `TERM-02` 的边界场景验证（含无关 TASK 逐字保留） | 生产 = TASK 写作（Skill 正文）；存储·传输 = `tasks/TASK-*.md` 与 `tasks/_index.yml`；schema = TASK frontmatter 与 6 节结构不变；消费 = `review-dev-plan` 依赖拓扑维度与 `implement-code`；兼容降级 = 闭包为空时仅刷新索引 |

**未关闭项：无。** `dep-1` §7 明确交出的面（readiness 无法复用既有 `cmd-NN` 的诉求）已按需求合同落为 §9 `follow_up` 第 1 项（另立 CR），属需求期已钉定的出口，不是本 SDD 未关闭项。

**需求期 canonical suggestion 的承接（`dep-21`）**：`dep-1` §1.4 事实 21 的「`cmp` 逐字节一致 / 33,478 B」只在 EOL 归一后成立——本设计按「内容一致（EOL 归一后）」理解来源对齐，且**未在任何目标文本中写入 `cmp` / 逐字节 / 字节数口径**；该处属需求文本，本 CR 不改 `prd.md`（§9 `scope_out`）。相关行尾与硬失败纪律见 §7.1（SDD-CLOSE-05）。

---

# 7. 安全与性能考量

## 7.1 行尾纪律与硬失败（NFR-5）

- 新增/改写文本在四个 SKILL 与 pipeline JSON 中保持 **LF 检出内容一致**；实施期一次落盘后以二进制读取复核（不得出现混合 EOL）。
- 任何对仓库文件做哈希、跨行正则或逐行解析的步骤（含实施期的自查脚本）读入先 `\r\n → \n` 归一；跨行正则匹配失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」（`dep-5` 不变量 4）。
- **SDD-CLOSE-05**：本次不是新写解析器，而是新写文本；因此该纪律的落点是「实施后自查」：对 7 处落点做取证时，任何"以字节数或 `cmp` 判定一致"的做法都必须先归一行尾，或直接改用归一后文本比对——避免按字面字节复核产生假失败（`dep-21` 记录的需求期同类教训）。

## 7.2 边界与越权面

| 风险 | 控制 |
|---|---|
| 借 upstream 轨扩大重写面 | 只重算 `dep-1` 定义的受影响面；未受影响内容逐字保留（I1）；coordinator 不得指定具体行（`dep-3` 新文字第 3 条） |
| 借 delta 之名少修（漏修下游） | 依赖闭包强制同步（I2/§4.2）；`review-dev-plan` 既有依赖拓扑与 `acceptance-verifiability` 维度兜底 |
| 借「环境前提」新增账本/状态/节点 | §9 `zero_diff` 硬边界 + AC-7/AC-8 逐条核对；`ENVIRONMENT_MISMATCH` 不写账本、不写状态（`dep-13` 既有边界不变） |
| readiness 成为第二套验证语义 | 复用既有 `cmd-NN`（D-3）；write-dev-plan 侧只引用标签不复述语义（D-5、`dep-1` §1.5 第 4 条） |
| 新增文字触发既有 lint / 断言 | §6.6 逐条：字面量禁令自查 + lint-prompts R1~R13 面（`dep-19`） |
| 越权修改受保护文件 | 本 CR 不改 `_backlog.yml` / `cr.md` / `approval.yml` / `review-loop.yml` / `review-annotations/*`（`dep-10` deny 面）；状态推进唯一经 `crctl` |

## 7.3 唯一强度变化的兼容性说明

本 CR 的**唯一**语义强度变化是 `review-dev-plan` 的 `acceptance-verifiability` 判据收紧：观测面窄于声称面 → blocker；命令形态越受控边界 → blocker。该变化不改变任何 crctl 状态转换、错误码或 Skill 调用契约，只改变 `review-dev-plan` 的 blocker 判定输入；按 `dep-1` §1.3.3 第 4 条，评审判据只对评审发生时的 SKILL 版本生效，**对既有已归档 CR 无追溯效力**。其余六处改动均为表达与写作口径的原位扩写，不改变任何判定结果的目标集合（不新增维度名、不新增错误语义）。

## 7.4 性能与观测

- **性能**：本 CR 无运行时路径改动（纯提示词与人工审批文本），无性能目标面。
- **观测**：不新增任何观测指标 / SLO / 计数门禁（`dep-2` §1.4「不增加观测指标」）；`dep-1` §6 的成功指标是**实施后可统计的既有事实**（未受影响内容改写数 = 0、readiness 复用比例 = 100%、新增结构件 = 0 等），不落成新的账本字段或指标系统。

---

# 8. Prompt 采纳影响

**本节按条件性小节判定为「不适用」，理由（逐条对应条件）：**

- 本 CR 的 diff **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支（该文件零 diff，§9 `zero_diff`）；
- 本 CR 的 diff **不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（`dep-10` 零 diff）；
- 因此不存在「crctl 新增/扩展子命令后某 skill 该采纳却未采纳」的清单面，无需列举应改调用方式的 skill。

（判定依据：`write-tech-design` 章节 8 的触发条件与 `review-tech-design` Step 2「Prompt 采纳影响」行；本 CR 的唯一 Skill 侧改动都是写作/评审判据，不涉及命令面采纳。）

---

# 9. 批准范围

## scope_in（当前 CR 必须交付的 FR/AC）

本 CR 必须交付 FR-1~FR-6 与 AC-1~AC-9，落为 **5 个 tools 文件、7 处原位落点**（逐字目标文本见 §6.5）：

1. `dep-3`：`write-dev-plan/SKILL.md` Step 2a 段落追加 upstream 轨四条（§6.5-A）
2. `dep-9`：同文件两张稳定表说明三处原位扩写（§6.5-B：`验收证据` 观测面判据 / `回滚` 闭包判据 / 证据命令表唯一事实源句）
3. `dep-12`：同文件章节清单第 5 项原位扩写环境五要素（§6.5-C）
4. `dep-4`：`write-dev-tasks/SKILL.md` Step 2a 第 1 条原位改写为 delta 重算 + 依赖闭包同步（§6.5-D）
5. `dep-11`：`review-dev-plan/SKILL.md` 既有 `acceptance-verifiability` 同条原位扩写两条 blocker 判据（§6.5-E）
6. `dep-13`：`implement-code/SKILL.md` 既有环境节末尾追加 readiness 即时性与环境无关 TASK 隔离两条 bullets（§6.5-F）
7. `dep-14`：`pipeline-templates/code-implementation.pipeline.json` 节点 `…0004` 的 `approvalPrompt` 值替换（§6.5-G）

## scope_out（明确排除的路径和能力）

- **不新增 Pipeline 环境节点**；不改节点集与节点数（保持 5/4/12）、不改 `…0014.reviewLoop.replayNodes` 条目、不改 `purpose: regenerate-tasks` 标签文本、不改 `review-route` 枚举、不把 `repair-target` 改成多值。
- **不做动态环境人工门禁**：dev-start 不要求审批时服务在线；不允许 coordinator 启停共享服务。
- **不新增评审观测指标**：无 SLO / 轮数承诺 / 计数门禁 / 聚合指标。
- **不改 upstream attempts 账本**：不把 upstream block 追加到 `attempts[]`、不新增 review-events、不改 `traceability.yml` schema。
- **不新增任何结构件**：账本字段 / 评审维度名 / crctl 子命令 / flag / 错误码 / Skill 参数 / 落盘文件 / lint 规则 / CI step 一律零新增。
- **零 diff 路径**：`skills/shared/crctl/scripts/**`（含全部测试与 `gate-registry.json`）；`write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline`；`pipeline-templates/**` 中除 `…0004` approvalPrompt 值以外的全部内容；`tools/agents/**`；`agent-skill-matrix.yml`；`dir-graph.yaml`；`ARCHITECTURE.md`；`../multica/**`；KB 的 `specs/` / `delivery/` / `docs/`（`dep-2` 来源文档只读）；KB 的 `prd.md`（需求文本，含 `dep-21` 记录的事实 21 表述）。
- **交给后续 CR 的能力**：readiness 无法复用既有 `cmd-NN` 时的稳定表合同与评审判据修改（见 `follow_up` 第 1 项）。

## zero_diff（明确不得改动的调用点 / 签名）

| 对象 | 不得改动的理由 / 出口 |
|---|---|
| 两张稳定表的表头与列集（交付覆盖表 5 列、证据命令表 6 列）与「验收证据 ↔ 证据ID」双向唯一映射合同 | `dep-7` 覆盖矩阵节机械核对；本 CR 只改列内写作判据（AC-3⑤、AC-6①） |
| `tasks/_index.yml` 受控账本形状与 `crctl task init` / `task done` 的调用形态与契约 | `dep-6` / `dep-17`；账本写入唯一经 crctl（`dep-5` 不变量 2） |
| `ENVIRONMENT_MISMATCH` 标签语义与其「唯一详细事实源」地位（`dep-13` 节内既有六条 bullets 逐字保留） | `dep-1` §1.5 第 4 条；write-dev-plan 侧只引用不复述 |
| 四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账四要素、Step 6 摘要 | CR-2026-066 面（`dep-15` 反向断言；AC-8①） |
| `skills/shared/crctl/scripts/**`（含 `gate-registry.json`）与 crctl CLI 契约 | AC-7②；`dep-10` 的 `protectedPaths.deny` 与 git 白名单 |
| `pipeline-templates/**` 的节点集 / reviewLoop / 其余 prompt / `_index.yml` 计数 | `dep-8` / `dep-16`；AC-7③ |
| 状态机与 gates 声明（`dir-graph.yaml#change-request-track.state_machine`、`gates.json`） | `dep-5` 不变量 1 / 5 |

## follow_up（发现但留给后续 CR 的缺口）

1. **readiness 无法复用既有 `cmd-NN` 的场景**：需修改两张稳定表「验收证据 ↔ 证据ID」双向唯一映射合同与对应评审判据（本 CR 不放宽该映射）；出口 = 另立 CR（`dep-1` FR-5 第 4 条、§7）。
2. **需求文本的 EOL 表述**：`dep-1` §1.4 事实 21 的「`cmp` 逐字节一致 / 33,478 B」建议在后续需求侧 revision 改写为「内容一致（EOL 归一后逐字节一致）」并注明结论不受影响（`dep-21` 的 canonical suggestion）；该处属需求文本、非本 CR 交付面。
3. **观测面判据的机械化**：本 CR 的判据以 Prompt 合同形式落在写侧与评侧，尚无可判定的机械校验面；若未来需要机械校验（如证据命令表行的静态扫描），需另立 CR 评估（本 CR 不新增 lint 规则 / crctl 校验面）。
