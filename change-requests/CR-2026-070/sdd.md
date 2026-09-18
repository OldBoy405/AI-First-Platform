---
id: CR-2026-070-sdd
type: SDD
cr-ref: CR-2026-070
title: Agent Skill 路由与 Pi bash 默认超时：评审无限阻塞最小治理 技术设计
target-version: 0.43
status: draft
created: 2026-09-18T10:20:00+08:00
updated: 2026-09-18T10:40:00+08:00
---

# CR-2026-070 技术设计（SDD）

> 输入：`dep-1`（PRD v0.2，已人工审批）与 `dep-2`（收敛版来源）。
> 本 SDD 只做技术设计，不改需求合同；PRD 是 FR/AC 的权威，冲突以 PRD 为准。

---

# 1. 架构概览

## 1.1 设计目标与不变量

**目标**（严格对应 `dep-1` 的 FR-1／FR-2，不多做）：把 AIFI-33 事故链的两个缺口各自封住一处——① Agent 侧的 Skill 路由权威（`dep-1` FR-1）；② Pi 内置 shell 工具在未显式传 `timeout` 时的无界等待（`dep-1` FR-2）。第三个 FR（`dep-1` FR-3）不是改动单元，而是本次两个改动共同必须遵守的复用合同。

**不变量清单**（违一即评审 blocker，全部来自 `dep-1` FR-3／§4 NFR 与 `dep-3` 的硬不变量）：

| 编号 | 不变量 | 设计落点 |
|---|---|---|
| I1 | Skill 路由规则**只有一处**生效；`review-*` Skill、Agent Prompt（含平台侧副本）、README、Pipeline JSON 零复制 | §2.2、§4.3、§6.2 AC-1 |
| I2 | 不新增 Skill Locator／manifest／注册表／路径映射／索引缓存；不改变 Skill 名称、frontmatter 与既有注入目录 | §1.2、§6.4 |
| I3 | 不改 OutputGuard（`core.mjs`／`policy.json`／`capabilities.json`／compound passthrough 合同），不新增第二 Guard、不改 Shell 解析 | §4.5、§6.2 AC-9 |
| I4 | 计时与清理只有一套：Pi 既有 `setTimeout`／AbortSignal／timeout 错误／`killProcessTree()`；不在 Multica／OutputGuard／Agent／Skill／Pipeline 侧另设计时器 | §4.1、§4.2 |
| I5 | 不新增状态、错误码、账本字段、metrics、数据库、sidecar、事务框架、Pipeline 节点 | §2.1、§3.4 |
| I6 | 零新增依赖（multica 无新 Go 依赖，Pi 侧无新 npm 依赖） | §2.1、§6.2 AC-11 |
| I7 | FR-1 规则文本 Provider-neutral：不硬编码任一 Provider 私有目录，不枚举 Provider 路径表 | §3.2、§4.3 |
| I8 | `dep-3` §5 硬不变量（工作区隔离、单一任务路径、Git/crctl 为 CR 权威、生成物不手改、英文注释）零违反 | §1.3、§7.2 |

## 1.2 变更面鸟瞰

本 CR 的交付 diff 有且只有两个改动单元 + 一项治理登记 + 本 SDD 自身：

```text
单元 A（FR-1，multica 仓，落点唯一）
  server/internal/daemon/execenv/runtime_config_sections.go
    └ writeSkills()               ← 规则文本在此合成（dep-4）
    └ (同文件) 既有 ## Skills 段形状不变：仍是 slug 索引，无描述、无 per-provider 分支
  server/internal/daemon/execenv/runtime_config_test.go
    └ 既有形状钉子测试扩展（新增断言，不改既有断言语义）

单元 B（FR-2，Pi 包版本化源码，路线相关，落点唯一）
  <选定路线的源码仓>/src/core/tools/bash.ts
    └ DEFAULT_TIMEOUT_MS 常量 + resolveTimeoutMs 的 undefined 分支
    └ 超时错误文本的秒数来源改为「实际生效值」
    └ bashSchema 的 timeout 说明文案
    └ 该仓既有测试面内新增/扩展用例（场景与判据见 §4.4/§6.4，不预定文件路径）

治理登记（强制，非可选项）
  multica/CUSTOM.md                ← 本次定制的台账条目（AGENTS.md 工程纪律 10 强制）

过程产物
  change-requests/CR-2026-070/sdd.md   ← 本文件（ai-first-platform-docs 仓）
```

**下发链（单元 A，纯文本，无新代码路径）**：规则文本在 `writeSkills` 内与 Skill 列表同段落下发（`dep-4`），经 `buildMetaSkillContentSlim` → `buildMetaSkillContent` → `InjectRuntimeConfig` 写入各 Provider 的原生配置文件（claude 的 `CLAUDE.md`、Pi 的 `AGENTS.md` 等）（`dep-5`），或对无文件目标的 Provider 内联下发。**规则文本不新增任何字段、不新增解析器、不新增分支**。

**注入条件（单元 A 的关键前置，必须与规则语义一致）**：`## Skills` 段仅在「至少一个模型可见 Skill」时输出（`dep-6` 的 `modelVisibleSkills`／`skillModelInvocationVisible` 过滤后非空，`dep-7` 的 `writeContextFiles` 只在 `AgentSkills` 非空时写 Skill 文件）。规则文本**随该段一起出现或一起不出现**，不为其单开第二条注入路径（I2）。

**既有测试面与治理登记**：单元 A 的新增断言落在既有形状钉子测试（`dep-8`：slug 索引、无描述、无 Provider 分支、空集不注入）内；multica 侧 diff 另含一条台账条目（`dep-9` 的 `CUSTOM.md`，AGENTS.md 工程纪律 10 强制，不受 `zero_diff` 约束）。

**改动面之外（零 diff 声明见 §9）**：Multica 的 Skill 注入实现（`dep-7`）、Agent Prompt 副本池、Pipeline JSON、crctl、状态机、四类 `review-*` Skill 与全部受控账本。

## 1.3 多仓边界、路径 authority 与交付证据形态（FR-08.4）

**路径 authority**：全部代码事实与落点一律取 `crctl workspace inspect {cr_id}` 的 `resources[].worktreePath` 原样值（禁止 `\.rayai-worktrees\...` 目录名拼接、禁止回退主 checkout——`CRCTL_WORKSPACE` 当前指向主 checkout，其视图为陈旧 `drafting`）；过程文档取 `operationalWorkspace`。本 SDD 的所有行号与符号均在该 worktree 的 HEAD 上取证（`dep-3`～`dep-9`、`dep-10`）。

**参与仓与依赖方向**（`dep-11` 的 `repositories` 声明面）：

| 仓 | 本 CR 角色 | diff 面 | 提交口径 |
|---|---|---|---|
| `ai-first-platform-docs`（KB） | 过程文档 | `change-requests/CR-2026-070/sdd.md`（本文件） | 本 CR worktree 内提交 |
| `multica` | 单元 A（FR-1）+ 台账登记 | `server/internal/daemon/execenv/runtime_config_sections.go`、`.../runtime_config_test.go`、`CUSTOM.md` | 同 worktree 内提交（与 KB 各仓分别提交，不要求同一 commit） |
| `tools` | **零 diff**（AC-9／AC-10 的取证面与零复制面） | 无 | 只复跑既有测试，不写 |
| Pi 源码仓 | 单元 B（FR-2） | 选定路线的版本化源码与其测试文件 | **不在 `dep-11` 的 `repositories` 声明内**（DEC-3），以其自身版本控制的 commit range 作为取证对象 |

**依赖方向**：规则文本从 Multica daemon 流向 Runtime 配置文件（`dep-5`），不反向；Pi 侧改动不得引用 Multica 侧任何符号（跨仓无编译期依赖）。**方向禁令**：不得为让 Pi 侧改动"可 checkpoint"而改动 `dep-11` 的仓库声明（DEC-3）。方法论包侧的约束（`dep-12`：状态机／gates／Pipeline 声明的唯一事实源在 tools 包）在本 CR 内只读不触碰。

**Pi 侧交付证据形态（路线无关，`dep-1` AC-12）**：

- R-A／R-C：fork 仓的「分支 + commit range（起止 40 位 SHA）+ 构建产物版本号」，记为 CR 交付证据；
- R-B：上游 PR 链接 + 上游发布的版本号，本 CR 的 Pi 侧 diff 到该 PR 的源码 diff 为止；
- 三种路线下**都不**把已安装包目录（`{npm root -g}\@earendil-works\pi-coding-agent\**`）纳入任何交付 diff（`dep-1` FR-2 交付边界、AC-12）；
- 「运行环境 PATH 上的 `pi` 换成新版本」一律发生在 **CR 合并之后**，属运行环境维护，不是 CR 交付物。

**isolation / 并发**：单元 A 与单元 B 落在不同仓，可并行实施；同一仓内不并发写（`dep-9` 的 `CUSTOM.md` 与 `dep-4` 的源码文件同属 multica 仓，须同一提交者顺序提交）。

## 1.4 术语预检（Step 2.5 结论）

| 术语 | 风险 | 裁决口径 | 代表边界场景 | 证据 |
|---|---|---|---|---|
| 「已列出的 Skill 名称」 | brief 里有**显示名**与**目录 slug**两套写法，若口径不唯一，AC-1／AC-4 的核对会指向不同对象 | 本 CR 的口径＝**slug**：brief 中 `- **{slug}**` 的 slug，与 `writeSkillFiles` 实际落盘目录名同源（都由 `resolveSkillSlugs` 在批次内去重后派生）。不新增显示名→路径映射 | `"A B"` 与 `"A-B"` 两个 Skill：第二个落 `a-b-multica`，列表也列 `a-b-multica`，Agent 按列表名可直接命中 | `dep-6`、`dep-7`、`dep-8`（`skill_visibility_test.go` 的碰撞用例） |
| 「timeout 秒数」 | 对外是秒、对内是毫秒，且上限值本身是小数秒；错误文本若回传原始入参会出现 `undefined` | 对外契约单位＝**秒**；内部换算点唯一（`resolveTimeoutMs`）；错误文本报告**实际生效秒数**；上限 2147483.647 秒按现有取整规则原样沿用 | 未传 → 300；`timeout:1200` → 1200；`0`／负数／`NaN`／`Infinity` → 第 1 档非法；`2147484` → 第 2 档超上限 | `V-2` |
| 「技术中止」 | 易被读成需要新错误码 | 复用**既有**工具/节点失败语义：Agent 停止当前节点并按既有报告路径输出缺失能力事实；不新增 `SKILL_NOT_FOUND` 类平行错误体系 | 预期 Skill 不在列表 → 中止并报告（Skill 名／Runtime／任务），零业务 verdict、零账本写入 | `dep-1` FR-1 第 4 项 |

术语预检结论：三处口径均由既有实现与 `dep-1` 唯一确定，**无需需求负责人澄清**，可直接进入 SDD 落盘与状态推进。

## 1.5 与 PRD §1.5「需求期不下结论的实现细节」的承接

| `dep-1` §1.5 条目 | 承接位置 | 关闭编号 |
|---|---|---|
| 第 1 条：FR-1 规则正文的最终措辞与落点选择 | §3.2（逐字文本）、§4.3（合成与唯一性）、DEC-1 | SDD-CLOSE-01 |
| 第 2 条：FR-2 默认值与内部 `timeout:` 错误传递的接线方式 | §4.1、§4.2（实际生效秒数的传递）、DEC-4 | SDD-CLOSE-02 |
| 第 3 条：Pi 侧交付路线、版本产出方、PATH 切换记录 | §1.3、§4.6、DEC-3；**路线选择归 `write-dev-plan`**（`dep-1` §7 第 11 条） | SDD-CLOSE-03 |

---

# 2. 数据模型

## 2.1 零新增实体、字段与账本（I5／I6）

本 CR **不新增**：数据库表/列/索引、迁移、sidecar 文件、账本字段、metrics、配置键、环境变量、错误码枚举、CR 状态或转移。`dep-1` FR-3 的复用合同在本章体现为「新增的数据形状只有两个常量级文本」（§2.2），没有第三个。

## 2.2 本 CR 新增的两个数据形状

### 2.2.1 形状 1 — Skills 段的规则文本（FR-1）

- **载体**：`dep-4` 的 `writeSkills` 内一段固定英文字符串常量（§3.2 逐字给出），随 `## Skills` 段一起下发。
- **字段**：无（不是结构化数据）；契约面 = 文本逐字 + 出现次数 + 出现条件。
- **唯一性约束**：全文只允许出现一次；跨 Provider 逐字相同（I7）。
- **出现条件**：`modelVisibleSkills(ctx.AgentSkills)` 过滤后非空（`dep-6`），与既有段输出条件完全一致。
- **确定性**：常量字符串，不随 run、Provider、时间变化 → brief 仍按 run 内幂等（`dep-4` 的缓存前缀稳定性口径不受影响）。

### 2.2.2 形状 2 — `DEFAULT_TIMEOUT_MS` 常量与说明文案（FR-2）

- **常量**：值 `300_000`（毫秒），单位换算只此一处（秒→毫秒仍由既有 `timeout * 1000` 完成）。
- **说明文案**：工具入参 `timeout` 的 schema 描述，必须与默认值一致（不得再声明 `no default timeout`，`dep-1` AC-5 的 S-4 核对点）。
- **错误文本**：`Command timed out after <实际生效秒数> seconds`（既有格式，值来源改为实际生效值，§4.2）。
- **无配置面**：不引入配置文件/环境变量/远程开关（`dep-1` §7 第 8 条）。

## 2.3 已知设计边界（B-1／B-2，显式登记而非默认成立）

| 编号 | 边界 | 内容 | 与 AC 的关系 |
|---|---|---|---|
| B-1 | 零 Skill 任务 | `AgentSkills` 为空或全部 `disable-model-invocation: true` 时 `## Skills` 段整段不注入，规则文本随之不出现 | 既有语义，由 `dep-8` 的两条测试钉住；**AC-4 的场景构造不得使用该情形**（否则规则文本不在场，构造无效）。零 Skill 任务的同类治理列为 `follow_up`、不属本 CR |
| B-2 | 自定义 operations seam | 内置 bash 工具的「工具入参 → operations」接口（传给 `ops.exec` 的 `timeout` 参数与 `BashOperations` 签名）**不变**；默认值只在内置本地执行路径内解析 | `dep-1` FR-2 实现边界「只修改现有 timeout 解析点」；扩展自带 operations 时的行为不变（§9 `zero_diff` Z-3） |

## 2.4 数据库 schema / 写路径鉴权完整性：N/A

本 CR 无数据库 schema、迁移、约束或写路径鉴权改动（无新增表/列、无新 DDL、无新鉴权判定），因此不适用 `write-tech-design` 的「数据/schema 变更与写路径鉴权完整性」条件章节，不写回滚 down 脚本与锁原语。

## 2.5 状态与门禁（零变化）

CR 状态机、门禁、reviewLoop、审批合同、受控账本字段全部零变化（I5）。本 CR 的交付证据以文件形态落在 CR worktree 与 Pi 源码仓版本控制内，不新增状态、不新增账本字段。

---

# 3. 接口契约

## 3.1 内置 bash 工具 `timeout` 参数契约（FR-2，Agent 可调用面）

对外契约（模型可见的入参语义；实现落点见 §4.1）：

```text
参数: timeout?: number            # 单位：秒
解析顺序（固定，互斥，先判定先返回）:
  1) 已传且 (!Number.isFinite(v) || v <= 0)   → 非法：Invalid timeout: must be a finite number of seconds
  2) 已传且 v * 1000 > MAX_TIMEOUT_MS        → 非法：Invalid timeout: maximum is 2147483.647 seconds
  3) 已传且合法                              → 使用 v（含 v = 1200），不被默认值覆盖
  4) 未传                                    → 使用 DEFAULT_TIMEOUT_MS = 300_000（= 300 秒）
等价性/幂等: 同一输入必得同一解析结果；「未传」与「传 300」解析结果等价（300_000 ms），
             其余显式值不等价于默认值
超时结果（顺序确定）:
  1) killProcessTree(child.pid) 清理本次调用进程树（父进程及其后代）
  2) 错误文本 Command timed out after <实际生效秒数> seconds（默认值生效时为 300）
  3) 交回当前 Skill/节点的既有失败语义
副作用: 只清理本次工具调用的进程树；无 CR 状态/门禁/审批/账本副作用；无新增持久资源
```

**契约不变量（AC-8 的核对面）**：非法值与超上限的判定发生在**启动进程之前**（零启动、零写入）；AbortSignal 提前取消的路径与默认值正交（`signal.aborted` → `Command aborted`，不受本次改动影响）；错误文本格式与错误类不新增平行结构（I5）。

**判定顺序的边界值表**（实现与测试共用，避免并列歧义）：

| 输入 | 档位 | 生效值 | 结果文本 |
|---|---|---|---|
| 未传 | 4 | 300 秒 | `Command timed out after 300 seconds` |
| `300` | 3 | 300 秒 | `Command timed out after 300 seconds` |
| `1200` | 3 | 1200 秒 | `Command timed out after 1200 seconds` |
| `0` / `-1` / `NaN` / `Infinity` | 1 | — | `Invalid timeout: must be a finite number of seconds` |
| `2147484` | 2 | — | `Invalid timeout: maximum is 2147483.647 seconds` |
| `2147483` | 3 | 2147483 秒 | 生效（上限内） |

## 3.2 Skills brief 段的文本契约（FR-1，Agent 可读面）

**落点**：`dep-4` 的 `writeSkills` 内，`## Skills` 段的**末尾**（Skill 列表与平台 Skill 召回提示之后）；理由：召回提示的指代对象是紧邻上方的列表，插在中间会切断指代；规则统领整段，收尾处最不易与列表项混淆。

**逐字文本（英文，随 multica 代码规则；contract 面，评审与 AC-1 按此逐字核对）**：

```text
Treat that list as the authoritative entry point for skill selection: the runtime has already discovered those skills for this task, so use the discovered copy directly, before any repository exploration. Do not hunt for a skill on the filesystem — no recursive search for `SKILL.md` (or its shell equivalents) and no reads under guessed runtime-private directories; per-provider paths are deliberately not listed here. If a skill this task expects is not in the list, stop the current node and report the missing capability (skill name, runtime, task) through the existing technical-abort path: do not produce a business verdict, and do not write any CR state or ledger.
```

**文本契约的四个可核对子句**（对应 `dep-1` FR-1 行为合同 4 项）：

| 子句 | 对应 FR-1 项 | 机械核对方式 |
|---|---|---|
| `Treat that list as the authoritative entry point for skill selection` | 1 | 该短语为 AC-1 的检索锚：落点面（`dep-4`）命中 1 次、零复制面（见下）命中 0 次 |
| `use the discovered copy directly, before any repository exploration` | 2 | 文本存在性 + 与列表同段落（同一 `b.WriteString` 序列） |
| `no recursive search for \`SKILL.md\` ... no reads under guessed runtime-private directories; per-provider paths are deliberately not listed here` | 3 | 断言该段**不含**任一 Provider 私有目录字面量（表驱动负向断言，I7） |
| `stop the current node and report the missing capability ... do not produce a business verdict, and do not write any CR state or ledger` | 4 | 文本存在性；行为证据见 AC-4（§4.4） |

**零复制面（AC-1 的取证对象，＝本 CR 落点之外）**：`dep-13`（Multica 侧 Agent Prompt 副本与 `server/internal/**` 中本 CR 落点 `dep-4`／`dep-8` **之外**的文件）与 `dep-10`（tools 侧的 `skills/**`、`pipeline-templates/**`）中，检索锚短语命中数必须为 **0**；同一检索在落点面（`dep-4` 的 `runtime_config_sections.go`）的命中数恰为 **1**。二者是**同一次检索的互补结果**（零复制面＝落点之外），不是两个互相独立的判据；该限定的唯一裁决见 §6.3 `dep-13` 与 §9 Z-5。

## 3.3 注入面契约（FR-1 的下发路径，零改动）

`## Skills` 段经 `dep-4` → `dep-5` 写入各 Provider 的原生配置目标文件（claude 的 `CLAUDE.md`、Pi 的 `AGENTS.md`、Qwen 的 `QWEN.md` 等），对**全部任务类别**（issue／chat／quick-create／autopilot）输出（`dep-8` 的类别矩阵行 `{"## Skills", allKinds}`）。本 CR 不新增目标文件、不改映射表、不改写入/清理配对逻辑。

## 3.4 HTTP / REST / IPC / 事件契约：N/A

本 CR 不新增或修改任何 HTTP API、IPC、事件接口、CLI 子命令或 flag（`dep-1` §1.3.3 三项 N/A 的技术侧复述），因此不产出 OpenAPI 片段。

## 3.5 错误语义：零新增错误码

| 面 | 既有错误 | 本 CR 动作 |
|---|---|---|
| Pi timeout | `Command timed out after N seconds`（既有文本，`V-2`） | 值来源改为实际生效秒数（§4.2），**格式不变**、不新增错误类 |
| Pi 非法入参 | `Invalid timeout: must be a finite number of seconds` / `Invalid timeout: maximum is ... seconds` | 逐字不变 |
| Pi abort | `Command aborted` | 逐字不变 |
| Multica Skill 缺失（FR-1 第 4 项） | 既有技术中止路径 | 不新增 `SKILL_NOT_FOUND` 类错误码/账本状态 |

---

# 4. 关键算法与流程

## 4.1 A1 — timeout 解析算法（FR-2 的核心，唯一改动点）

现状（`V-2`）：`resolveTimeoutMs(timeout)` 在 `timeout === undefined` 时返回 `undefined`，调用方据此**不挂** `setTimeout`（`if (timeoutMs !== undefined)`），于是未显式传参的调用无上界。

设计（改动最小化，落在**同一个**解析点，I4）：

```text
const DEFAULT_TIMEOUT_MS = 300_000;              # 新增：唯一 owner

function resolveTimeoutMs(timeout):               # 唯一改动点
    if (timeout === undefined) return DEFAULT_TIMEOUT_MS;   # ← 由「返回 undefined」改为默认值
    if (!Number.isFinite(timeout) || timeout <= 0) throw 非法错误          # 档 1，逐字不变
    const timeoutMs = timeout * 1000                                       # 逐字不变
    if (timeoutMs > MAX_TIMEOUT_MS) throw 超上限错误                       # 档 2，逐字不变
    return timeoutMs                                                        # 档 3，逐字不变
```

**算法性质**：

1. **判定顺序与 PRD §3 FR-2 五档逐档对应**（§3.1 边界值表即该算法的可机械核对面）；
2. **不新增分支**：默认值让既有的 `timeoutMs !== undefined` 分支恒成立，`setTimeout` + `killProcessTree` 路径因此对「未传」调用**首次可达**——这正是 AC-6 的取证对象；
3. **显式路径零回归**：档 1/2/3 的判定顺序与文本逐字未变（AC-7／AC-8）；
4. **自定义 operations 不受影响**：默认值只在**内置本地执行路径**内解析，传给 `ops.exec` 的入参仍是工具原始入参（B-2）；
5. **上限**（`MAX_TIMEOUT_MS = 2147483647`）与非法值校验位置不变，仍在启动子进程之前（`V-2`）。

## 4.2 A2 — 超时错误文本的秒数传递（`dep-1` §1.5 第 2 条的关闭）

现状（`V-2`）：超时分支抛出的信号携带**调用方原始入参**（`timeout:${timeout}`），工具层从该字符串尾部取出秒数拼进错误文本。默认值生效时为「未传」，该值即 `undefined` → 错误文本会变成 `Command timed out after undefined seconds`。

设计：信号携带**实际生效秒数**（未传＝默认值 300 秒，已传＝调用方原始入参本身），工具层的解析与文本拼接逻辑逐字不变。

```text
现状: throw new Error(`timeout:${timeout}`)          # 未传时为 undefined（缺陷）
设计: throw new Error(`timeout:${timeout === undefined ? DEFAULT_TIMEOUT_MS / 1000 : timeout}`)
```

**等价性证明**（不改变既有可观察行为）：

- 显式合法值 v：信号值即 `v` 本身（**不**经 `v * 1000 / 1000` 的二次浮点往返），模板求值与现状**逐字相同**（含小数秒，如 `0.5`，及 `1958978.455463335` 这类往返不精确的双精度值）→ NFR-1「显式传 timeout 的调用行为逐字不变」在全值域字面成立；
- 未传：现状 `undefined`（无意义），设计为 `300` → 错误文本首次有意义（`dep-1` FR-2 超时结果第 2 项的显式要求）；
- 该信号的解析点（工具层 `startsWith("timeout:")` 分支与文本模板）**零 diff**。

## 4.3 A3 — 规则文本的合成与唯一性（FR-1）

```text
function writeSkills(b, ctx):
    skills ← modelVisibleSkills(ctx.AgentSkills)        # dep-6
    if len(skills) == 0: return                          # B-1：整段不注入，本 CR 不动此早退
    写 "## Skills" 段头 + "discovered automatically" 列表（逐行 slug）
    if 平台 Skill 命中: 写平台召回提示（既有，逐字不变）
    写 RULE_TEXT 常量（§3.2 逐字，末尾一次）              # ← 本 CR 唯一新增输出
```

**唯一性论证**（AC-1 的机械面）：

1. 规则文本是**函数内单一常量**，只在一个 `WriteString` 调用点出现 → 单次 run 内出现次数恒为 1；
2. `writeSkills` 是本 brief 中输出 `## Skills` 段头的**唯一**函数（`dep-4` 的 grep 面唯一），其他段头各有唯一函数 → 不存在第二个"顺手也写一段路由规则"的位置；
3. 平台 Skill 召回提示是既有文本且指名一个 Skill（`dep-4`），与本规则不构成同义重复（前者是"去哪查 Multica 合同"，后者是"Skill 从哪来"）；
4. 复制面（`dep-10`／`dep-13`，其中 `dep-13` 按 §6.3 的落点 carve-out）不在本 CR diff 内，检索锚零命中即为 I1 的机械证据（落点面命中 1 次、复制面命中 0 次，同一检索的互补结果，见 §6.2 AC-1）。

**Provider-neutral 论证（I7）**：文本只使用 runtime 通用词（`the runtime`、`the current node`），不出现任何 Provider 名或目录字面量；负向断言（§6.4）对已知 Provider 目录名表驱动核对。

## 4.4 A4 — 复现与场景验证设计（AC-2／AC-3／AC-4）

三条 AC 都是**行为**验收，不能由静态断言替代（`dep-1` §5 补充判定口径）。

**观察面**：Multica 任务 run 的会话记录（`toolCall` 名称 + `arguments.command` 文本）与任务输出，**不新增可观测性设施**（I5）。

| AC | 场景构造（可复现口径） | 通过判据（机械） | 失败/中止口径 |
|---|---|---|---|
| AC-2 | 以 `quality-reviewer-agent` 重放第一次事故场景：读取 Issue 上下文后**首次加载当前 `review-*` Skill** | 该 run 中 bash 调用里同时含 `SKILL.md` 与递归搜索命令族（`find`／`Get-ChildItem -Recurse` 等）的调用数 = **0**；且 Skill 内容取自 brief 列出的 slug | 出现 ≥1 次即该 AC 不达成；不得以"最后仍然完成了评审"通过 |
| AC-3 | 同 AC-2，重放第二次事故场景（先尝试 HOME 级 Skill 目录 → 再根目录搜索） | 同上，且额外断言：对 `~/.pi/agent/skills`、`~/.multica/skills` 等猜测路径的访问尝试数 = 0 | 同上 |
| AC-4 | 构造：保留 ≥1 个其他 Skill（保证 `## Skills` 段与规则文本在场，B-1），移除被评估节点的预期 Skill | ① run 输出报告缺失能力事实（Skill 名／Runtime／任务）；② run 前后 `cr.md`、`_backlog.yml`、`review-annotations/*.yml`、`review-loop.yml`、`traceability.yml` 的 sha256 逐一致；③ 无业务 verdict 落盘 | 出现文件系统兜底搜索或任一账本变化 → 该 AC 不达成 |

**可达性说明**：三条场景的前置（Agent 已装 Skill、节点要求加载指定 Skill）与两次事故完全一致；规则文本随段注入的时间点**先于**任何工具调用（`InjectRuntimeConfig` 在任务准备期写配置文件，`dep-5`），因此判据的观察窗口覆盖事故发生的时刻。AC-4 的构造充分性依赖 B-1 的边界声明，已显式登记。

## 4.5 A5 — 回归面复跑设计（AC-8／AC-9／AC-10／AC-11）

| 面 | 复跑入口 | 期望 |
|---|---|---|
| Pi 既有 shell 行为（AC-7／AC-8） | 选定路线的源码仓既有测试面，命令按该仓既有 `test` 脚本 | 全绿；新增断言见 §6.4 |
| OutputGuard conformance（AC-9） | `node --test output-guard/test/*.test.mjs`（`dep-14` 的 CI 同命令） | 全绿；`output-guard/**` 零 diff |
| CR 流程与账本面（AC-10） | `crctl git diff --name-only` 对 §6.4 零改动清单 | 交集为空 |
| 零新增基础设施（AC-11） | diff 面核对（依赖清单、迁移目录、错误码常量、metrics 注册点） | 无命中 |

**复跑不新增测试基础设施**（`dep-1` §5 补充判定口径）：Pi 侧用例落在该仓既有测试框架内；tools 侧只复跑既有两条命令。

## 4.6 A6 — Pi 侧交付证据的取证算法（AC-12）

```text
输入: 选定路线（dev-plan 决定）+ 该路线的 Pi 侧交付面
输出: 文件路径清单 → 归属判定
规则:
  1) 逐份 diff 取文件路径清单（R-A/R-C：fork 分支 commit range；R-B：上游 PR 的 diff）
  2) 每条路径必须落在「版本化源码」或「其测试文件」两类之内
  3) 已安装包目录（{npm root -g}\@earendil-works\pi-coding-agent\**）出现 0 次
  4) 产出方与升级时点另行记录（产出方 = 路线对应主体；时点 = CR 合并之后）
硬失败: 清单不可枚举（无法给出 commit range／PR 链接）→ 该 AC 取证不成立，按技术失败上报，不得以「运行环境已升级」之类的替代证据顶替
```

**路线无关性**：三种路线下 1)～4) 均可执行；R-B 下 2) 的对象是 PR 内的源码文件集合。**不要求**验证运行环境已升级（`dep-1` AC-12 明文）。

---

# 5. 技术选型与替代方案

> 三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代）同时满足才记录；不伪造替代方案。

## DEC-1 FR-1 落点：`writeSkills` 段内（选定）vs 独立公共 contract 段（否决）vs 各 review Skill 复制（否决）

- **Context**：`dep-1` FR-1 给出两个合法落点（单一共享 Skills brief 段，或既有等价且单一的公共 Agent contract），并要求二者不得同时持有完整语义。`dep-1` §1.4 事实 3 已核实：**当时代码中不存在**等价且单一的公共 Agent 行为 contract（相关命中均为说明性注释）。
- **选定**：写入 `dep-4` 的 `writeSkills` 段内（§3.2、§4.3）。
- **替代 A（否决）**：另建一段公共规则的 brief 段（如新的 `## Agent Contract` 段）并在 `writeSkills` 内只引用。否决理由：等价于新增第二段"总则"面，且必须再造一套"谁引用谁"的约束；当前不存在第二个消费方，收益为零（YAGNI），与"最小改造"直接冲突。
- **替代 B（否决）**：写入四类 `review-*` Skill 或各 Agent Prompt。否决理由：违反 I1（多处 → 漂移），且 `dep-10`／`dep-13` 的复制面正是事故复发的温床（改一处、漏一处）。
- **Consequences**：规则的作用域＝「有模型可见 Skill 的任务」，零 Skill 任务不注入（B-1，显式登记为 follow_up）。

## DEC-2 FR-2 落点：共享解析点 `resolveTimeoutMs`（选定）vs per-tool 默认值（否决）

- **Context**：`resolveTimeoutMs` 位于内置 bash 工具模块（`V-4` 的 `src/core/tools/bash.ts`），并被内置 **PowerShell** 工具经 `createShellToolDefinition`／`createLocalShellOperations` 复用（`V-3`）；两者的 `timeout` 入参 schema 与说明文案也是同一份对象（`V-2`／`V-3`）。
- **选定**：改共享解析点（§4.1）。**由此产生的明确后果：内置 PowerShell 工具的「未传 timeout」路径同样获得 300 秒默认值**；说明文案随之同步（不必拆分 schema）。
- **替代（否决）**：为工具配置新增 `defaultTimeoutMs` 字段，只在 bash 配置里给 300，PowerShell 保持无界。否决理由：① 违反 NFR-6「timeout 默认值的 owner 只有一处」（会变成「配置项 + 解析点」两处）；② 由于两个工具共享同一 `bashSchema` 与同一段说明文案，必须再拆出一份 per-tool schema 才能保持文案诚实——为"让另一个工具继续保持无界"引入比修复本身更大的结构改动，与最小改造冲突；③ 两个工具面对的是同一类风险（无界的本地 shell 调用），对其中一个放任无界没有安全或产品上的理由。
- **Consequences**：本 CR 的 diff 语义上是「内置 shell 工具族的默认上界」，落点上仍是「Pi 内置 bash 的现有解析点」。若产品明确要求 PowerShell 保持无界，须另立需求或在评审阶段裁决后改采替代方案（评审显式确认项，见 §9 `follow_up` F-1）。

## DEC-3 Pi 源码仓不纳入 `dir-graph.yaml#repositories`（选定）vs 架构期扩充参与仓（否决）

- **Context**：`dep-1` §1.3.2 共用边界 4 把「是否把 Pi 源码仓纳入 CR worktree 集合」列为**架构期决策**；AC-12 的判据是交付 diff 的**文件集合归属**，不依赖 worktree 成员关系。
- **选定**：**不在本 CR 内**扩充 `dep-11` 的仓库声明；Pi 侧交付证据按 §1.3 的「分支 + commit range」形态记录。
- **替代（否决，且在当前时点不可执行）**：在架构期就为 Pi 源码仓新增 `repositories` 条目。否决理由：① 仓 URL 在路线选定并完成建仓前不存在（R-A 需要本团队建仓权，`dep-1` §1.4 事实 9 已证实当前无发布/建仓路径），提前声明会让 `crctl workspace inspect`／checkpoint 在实现期直接技术中止；② R-B 路线下根本不需要本团队仓库；③ 这属 workspace 级治理变更，超出本 CR 批准范围，收益（让 Pi 改动进入 checkpoint）对 AC-12 并不必要。
- **Consequences**：Pi 侧改动不进 crctl 的 checkpoint 面，其证据以 commit range／PR 链接形式进入 CR 交付证据；若 dev-plan 选定 R-A／R-C 且确实需要纳入 worktree 集合，由该阶段提出并走既有仓库声明变更流程（`follow_up` F-2）。

## DEC-4 超时错误秒数的传递：改信号的值为生效值（选定）vs 在调用点回填 `timeout` 参数（否决）

- **Context**：`dep-1` §1.5 第 2 条要求「默认值生效时错误文本必须报告实际生效秒数」，而现状把调用方原始入参一路带到错误文本（`V-2`）。
- **选定**：在解析点把信号值改为「未传取 `DEFAULT_TIMEOUT_MS / 1000`＝300、已传取调用方原始入参本身」（§4.2），工具层拼接逻辑零 diff。
- **替代（否决）**：在工具层调用 `ops.exec` 处回填 `timeout ?? 300`。否决理由：① 该处是「工具 → operations」的公开 seam，回填会把默认值**外泄给自定义 operations 实现**（改变扩展可观察行为，B-2）；② 非法值与上限校验会因此前移到工具层，等于把校验点搬走——`dep-1` FR-2 的「复用现有校验顺序」不再成立。
- **Consequences**：错误文本格式不变、语义变准；自定义 operations 的行为与接口签名零变化。

---

# 6. FR 到技术实现映射

## 6.1 FR 逐条映射

| FR | 技术方案条目 | 落点 |
|---|---|---|
| FR-1（Agent 使用 Runtime 已发现的 Skill） | 单点规则文本（§3.2）→ 单点合成（§4.3）→ 随 `## Skills` 段下发（§3.3）；行为证据按 §4.4 | `dep-4`（multica） |
| FR-2（Pi bash 默认 300 秒） | 解析点默认值（§4.1）+ 错误秒数传递（§4.2）+ schema 文案同步（§2.2.2） | 选定路线的 `src/core/tools/bash.ts`（`V-4`） |
| FR-3（既有能力复用合同） | I1～I8 不变量清单（§1.1）+ 零改动与零复制核对清单（§6.4）+ 复用面复跑（§4.5） | 全 CR，无独立落点 |

## 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §3.2 文本契约 + §4.3 唯一性论证 + §6.4 零复制面 | 以 §3.2 第 1 子句短语检索，同一次检索的互余两侧：① 落点面（`dep-4` 的 `runtime_config_sections.go`）命中数 = 1，即命中集 = `{runtime_config_sections.go}`；② 零复制面（§3.2＝落点之外：`dep-13` 的 Prompt 副本面与 `server/internal/**` 中除 `runtime_config_sections.go`／`runtime_config_test.go` 外的文件、`dep-10`）命中数 = 0。另断言 `strings.Count(brief, RULE_TEXT) == 1` 且对 claude／codex／pi 等多 Provider 逐字一致（断言引用常量符号，不内联锚短语） | 零复制面（`dep-13` 按 §6.3 的落点 carve-out、`dep-10`）与本 CR diff 无交集；文本为函数内常量，不存在第二写入点 |
| AC-2 | §3.2／§3.3（规则在场）+ §4.4 重放设计 | 真实 smoke run 的会话记录中「含 `SKILL.md` 的递归搜索调用」数 = 0；Skill 内容取自 brief 列出的 slug | 规则文本注入时刻早于任何工具调用；两次事故的前置条件（已装 Skill + 要求加载 review Skill）可复现；run 必须真实执行（R-2） |
| AC-3 | 同 AC-2 | 同上，额外断言猜测路径（`~/.pi/agent/skills`、`~/.multica/skills`）访问数 = 0 | 同上；规则文本中不出现任何 Provider 路径，避免"提示了路径反而诱导访问"（I7） |
| AC-4 | §3.2 第 4 子句 + §4.4 场景构造 | run 报告缺失能力事实；run 前后五个受控文件 sha256 逐一致；无 verdict 落盘 | 构造必须保留 ≥1 其他 Skill（B-1）；否则规则文本不在场，构造无效——已在 §2.3 显式登记，不作为本 AC 的前置 |
| AC-5 | §4.1（默认值）+ §2.2.2（文案） | ① `resolveTimeoutMs(undefined) === 300_000`；② 假时钟 + 真实子进程用例：未传 timeout 时 300 秒到期并抛 `Command timed out after 300 seconds`；③ schema 描述不再含 `no default timeout` 且与 300 一致 | 默认值使既有 `timeoutMs !== undefined` 分支恒成立，无需新增代码路径；假时钟只替换计时器推进，解析与 cleanup 路径不变（`dep-1` §5 补充口径） |
| AC-6 | §4.1 第 2 条 + 既有 `killProcessTree` 调用（`V-2`） | 用例启动带后代的子进程 → 超时后断言父与后代 PID 均不存在（Windows `tasklist`／POSIX `ps`）；Multica daemon PID 前后一致 | 默认值使超时分支对「未传」调用首次可达；cleanup 复用既有实现，不新增清理代码 |
| AC-7 | §3.1 档 3 | `resolveTimeoutMs(1200) === 1_200_000`；显式值超时的文本为 `... after 1200 seconds`；既有 `timeout:1200` 长任务用例全绿 | 默认值仅在 `undefined` 分支注入，与显式路径互斥（判定顺序第 3 档） |
| AC-8 | §3.1 档 1／2 + AbortSignal 分支 | 0／负数／`NaN`／`Infinity` → 非法错误逐字；`2147484` → 超上限错误逐字；abort → `Command aborted`；既有测试全绿 | 三档判定与 signal 分支的代码路径未改（§4.1 性质 3）；校验仍在启动进程之前 |
| AC-9 | §4.5 复跑 + §6.4 零改动清单 | `node --test output-guard/test/*.test.mjs` 全绿；`output-guard/**` diff 为空 | 本 CR 无 tools 改动；命令为 `dep-14` 的既有 CI 步骤，不新增测试基础设施 |
| AC-10 | §9 `zero_diff` + §6.4 核对清单 | 三仓 `crctl git diff --name-only` 与清单交集为空 | 改动面（§1.2）与清单无交集（含 `dep-13` 的 Prompt 副本面）；`dep-9` 的台账条目按 `scope_in` 显式排除在 zero_diff 之外 |
| AC-11 | §1.2 变更面 + §2.1 | diff 中无依赖清单文件、无迁移目录、无错误码常量、无 metrics 注册；新增字面量仅 1 个常量 + 1 段文本 | 两处改动都是既有函数内的值/文本变更，无新增依赖面 |
| AC-12 | §1.3 证据形态 + §4.6 取证算法 + §6.4 | 逐份交付 diff 的文件路径清单：Pi 侧改动全部落在版本化源码与其测试文件内；已安装包目录出现 0 次；产出方与升级时点（CR 合并之后）已写明 | 判据路线无关（R-A/R-B/R-C 均可枚举文件集合）；不要求验证运行环境已升级；R-B 下 Pi 侧 diff = 上游 PR 的源码 diff（`dep-1` AC-12 补充口径） |

## 6.3 既有实现依赖与事实

下表按**正文首次出现顺序**编号（`dep-1` 起，只增不改；删除条目留空洞、编号不复用）。每项以稳定标识开头，固定五要素；正文只以 `dep-N` 引用承载实现事实，不重复陈述"当前代码已经如何工作"。

```text
dep-1
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-070/prd.md
  stable symbol/对象: PRD v0.2 全文（§1.3.1 范围原文、§1.3.2 交付路线待定项 + R-A/R-B/R-C 与共用边界、§1.4 事实 1～9、§1.5 三条延后项、§3 FR-1～FR-3、§4 NFR-1～7、§5 AC-1～AC-12 与补充判定口径、§6 成功指标与发布次序、§7 十四条范围排除）
  commit SHA: 54f69aae89ed0dc3a73f6690c0ab218e8538483a
  依赖结论: 本 CR 的需求合同（人工审批已落盘，approval.yml requirement.evidence-digest 1e4d3d9e…）。blob f7a19ce6e62a1e1bfb51ed773caaa2b849109294、34769 B，自 54f69aae 起逐字未变（LF-only sha256 8972e5c5d8e62389c1cb44b7d8bd7974378da03be754d145c5cb46884a3130f8 = 需求评审 subject-sha256）。本 SDD 只读引用；任何修订必须回需求侧

dep-2
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-070/sources/CR需求来源_Agent_Skill路由与Pi工具默认超时_收敛版.md
  stable symbol/对象: 收敛版来源（§1 首项/次项、§2.1～§2.4 事故与根因链、§3.1～§3.3 既有能力核实点、§5 FR-1、§6 FR-2 与 §6.2 交付禁令、§7 十二条 AC、§8 验证口径、§9 发布顺序与回滚、§10 风险表）
  commit SHA: c7fde42bd94214a30796aff4493af9428802df75
  依赖结论: 范围权威来源（blob 8fcea01bd5349d6274439b8cf6e520a207f7b0e1、17049 B，未再修改）。本 SDD 的 AC 编号与来源 §7 的对应关系沿用 PRD，不改写

dep-3
  repo: multica
  relative path: ARCHITECTURE.md
  stable symbol/对象: §2 入口点（`server/internal/daemon/` = 本地执行控制面：任务领取、隔离环境准备、Skill 交付、Provider CLI 启动）、§3 代码地图、§4 依赖方向、§5 硬不变量 1～9（含工作区隔离、单一任务路径、生成物不手改、英文注释）、§6 Negative Space、§7 前后端切面（Fork tracking）
  commit SHA: 59b47993810fabd12fcc393c2fa2e46611f9530d
  依赖结论: 本设计的架构约束来源。单元 A 落在「Skill 交付」边界内，不新增跨层依赖、不新增第二任务路径、不改生成物；§5 第 9 条要求新增/修改注释为英文——本 CR 的新增注释与规则文本均为英文

dep-4
  repo: multica
  relative path: server/internal/daemon/execenv/runtime_config_sections.go
  stable symbol/对象: `writeSkills`（生成 `## Skills` 段：段头 + `discovered automatically` 列表 + 平台 Skill 召回提示；空列表早退）、`buildMetaSkillContentSlim`（brief 装配入口，`writeSkills(&b, ctx)` 对全部任务类别调用）
  commit SHA: 59b47993810fabd12fcc393c2fa2e46611f9530d
  依赖结论: FR-1 的**唯一**写入点：`## Skills` 段的段头与列表只在本函数生成，brief 内不存在第二个写入同段落的函数；函数内输出为纯文本追加，无 Provider 分支、无描述字段（避免形成第二事实源的既有裁决）。本 CR 只在该函数末尾追加一段固定文本常量

dep-5
  repo: multica
  relative path: server/internal/daemon/execenv/runtime_config.go
  stable symbol/对象: `InjectRuntimeConfig`（每任务写 Provider 原生配置文件并返回内容；无文件目标的 Provider 走 prompt-only）、`runtimeConfigPath`（Provider → 配置文件路径的唯一映射表）、`buildMetaSkillContent`（thin wrapper）
  commit SHA: 59b47993810fabd12fcc393c2fa2e46611f9530d
  依赖结论: 规则文本的下发路径：注入发生在任务准备期，早于任何工具调用；各 Provider 目标文件由该映射表唯一决定。本 CR 零 diff——不新增目标文件、不改映射、不动写入/清理配对

dep-6
  repo: multica
  relative path: server/internal/daemon/execenv/skill_visibility.go
  stable symbol/对象: `modelVisibleSkills`（过滤不可见 Skill 并回填 slug）、`resolveSkillSlugs`（批次内去重后派生目录 slug）、`skillModelInvocationVisible`
  commit SHA: 59b47993810fabd12fcc393c2fa2e46611f9530d
  依赖结论: ① `## Skills` 段的输出条件 = 过滤后非空，本 CR 的规则文本与列表同条件（B-1 的来源）；② brief 列出的标识与落盘目录名同源，二者不会互相漂移 —— 这是 §1.4 术语裁决「Skill 名称 = slug」的实现依据

dep-7
  repo: multica
  relative path: server/internal/daemon/execenv/context.go
  stable symbol/对象: `writeContextFiles`（sidecar 写入；`AgentSkills` 非空才解析/写 Skill 目录，hermes/codex 走各自 per-task home）、`resolveSkillsDir`／`skillsDirPath`（Provider → 原生 Skill 目录映射，无 per-Provider 分支回退到 `.agent_context/skills/`）、`writeSkillFiles`（写 `SKILL.md` 与附属文件、frontmatter 补齐、目录名碰撞处理）
  commit SHA: 59b47993810fabd12fcc393c2fa2e46611f9530d
  依赖结论: 「Runtime 已原生发现 Skill」这一前提的实现面（FR-1 的事实基础）：Skill 被写入各 Provider 的原生发现目录，因此 Agent 侧不需要任何文件系统搜索。本 CR 零 diff——不改注入目录、不改文件名、不改 frontmatter

dep-8
  repo: multica
  relative path: server/internal/daemon/execenv/runtime_config_test.go、runtime_config_kind_test.go、execenv_test.go、skill_visibility_test.go
  stable symbol/对象: `TestBriefSkillsListIsNamesOnly`（钉住 `## Skills` 段形状：slug 索引、无描述、无 Provider 分支、保留 `discovered automatically`）、类别×段落矩阵中的 `{"## Skills", allKinds}` 行、`TestInjectRuntimeConfigNoSkills`（无 Skill 时不得出现 `## Skills`）、模型不可见设置下的段落缺席断言
  commit SHA: 59b47993810fabd12fcc393c2fa2e46611f9530d
  依赖结论: 单元 A 的既有测试钉子：新增长度/形状断言必须收窄在既有段内追加，且**不得**改变空集与全隐藏两种情形下「整段不出现」的既有语义（B-1 的机械证据）

dep-9
  repo: multica
  relative path: CUSTOM.md
  stable symbol/对象: fork 二开台账（按 CR 里程碑分节、行号 `#N` 为稳定 ID、含关联 CR/阶段/完成状态/涉及文件/延后项、「合并注意」列与核对口径）
  commit SHA: 59b47993810fabd12fcc393c2fa2e46611f9530d
  依赖结论: AGENTS.md 工程纪律 10 的登记载体：任何落在 multica 仓的定制必须在**其当时实际结构**下顺延编号登记。因此本 CR 在 multica 侧的 diff 除源码与测试外**必须**含一条台账条目（§9 `scope_in` 第 3 项），该条目不受 `zero_diff` 约束

dep-10
  repo: tools
  relative path: skills/**（四类 `review-*` Skill 与其余 Skill 文本）、pipeline-templates/*.pipeline.json、dir-graph.yaml、agent-skill-matrix.yml、skills/shared/crctl/**
  stable symbol/对象: Pipeline 节点顺序与 reviewLoop 声明、Skill 合同文本、crctl 状态机与门禁声明面、受控 shell guard 规则面（`skills/shared/controlled-shell/rules.json` 的 git 白名单与 `protectedPaths.deny`／`ask`）、Agent/Skill 权限矩阵
  commit SHA: c3e7c934ef2636c56cc840543cadb4feb5f554aa
  依赖结论: AC-1 的零复制面与 AC-10 的零 diff 核对面（含「状态机与 gates 唯一事实源」的声明面）。本 CR 对这些路径零 diff、零复制

dep-11
  repo: ai-first-platform-docs
  relative path: dir-graph.yaml
  stable symbol/对象: `repositories` 段（`ai-first-platform-docs`／`multica`／`tools` 三仓声明）、`workspace.tools_package_path`（Tools Root 唯一解析入口）
  commit SHA: c1db7b9e797714aa952deebd44df15ce303b9149
  依赖结论: 参与仓集合与路径 authority 的声明面；单元 B 的落点仓**不在**该集合内（DEC-3 的前提事实）。本 CR 零 diff

dep-12
  repo: tools
  relative path: ARCHITECTURE.md
  stable symbol/对象: §3 代码地图、§4 分层与依赖方向、§5 硬不变量、§6 刻意不做、§8 维护规则
  commit SHA: c3e7c934ef2636c56cc840543cadb4feb5f554aa
  依赖结论: 方法论包侧约束：状态机/gates 的唯一事实源在 tools 包，本仓库不复刻副本；本 CR 对该仓零 diff。§1.3 的「零 diff 声明」以此节为主线

dep-13
  repo: multica
  relative path: cr-prompts-revised/（五个 Agent Prompt 副本：cr-coordinator-agent、delivery-agent、dev-agent、quality-reviewer-agent、requirement-writer）、server/internal/** 中本 CR 落点**之外**的文件（落点＝dep-4 的 server/internal/daemon/execenv/runtime_config_sections.go 与 dep-8 中改动的 server/internal/daemon/execenv/runtime_config_test.go；其余为 daemon／governance 侧运行时文本与生成物）
  stable symbol/对象: 平台侧 Agent Prompt 副本与其交付形态、governance 运行时与生成物（落点文件除外）
  commit SHA: 59b47993810fabd12fcc393c2fa2e46611f9530d
  依赖结论: AC-1 的零复制面在 multica 侧的对象（Prompt 副本池 + 落点之外的 server/internal 面）；AC-10 的核对面。本 CR 对这些路径零 diff、零复制——FR-1 的规则文本**不得**在此追加第二份。carve-out 的必然性：dep-4／dep-8 的落点文件由 §9 scope_in 第 1～2 项要求修改，按定义不在「零复制／零 diff 面」内；本项与 §6.4 核对清单、§9 Z-5 使用同一限定表述（唯一裁决）

dep-14
  repo: tools
  relative path: output-guard/**（core.mjs、policy.json、capabilities.json、conformance.json、adapters/、test/）、.github/workflows/crctl-ci.yml
  stable symbol/对象: OutputGuard Core 与 Adapter、跨 Adapter 共享测试向量、CI 中的 `paths` 触发面与 `node --test output-guard/test/*.test.mjs` 测试步骤
  commit SHA: c3e7c934ef2636c56cc840543cadb4feb5f554aa
  依赖结论: AC-9 的既有取证入口（复跑同一命令即可，不新增测试基础设施）与「compound passthrough 合同不变」的既有回归保护面。本 CR 零 diff
```

**依赖引用规则自查**：① 正文出现的每个 `dep-N` 均在本节有定义，且首现序单调（§1.1 起 → §6.2 止，1～14 连续、无空洞、无未定义引用）；② 本节编号只增不改，本轮为首次生成，无删除条目；③ 无法绑定 `repo` + 40 位 `commit SHA` 五要素的引用（本机全局安装的 Pi 包）全部在「待核实依赖」单列，正文只以 `V-N` 引用；④ 本 CR 确有既有实现依赖，故本节不写 `N/A`。

**本 SDD 引用的 commit SHA（40 位实测值，取证时刻见各条「依赖结论」）**：

```text
dep-1   ai-first-platform-docs  54f69aae89ed0dc3a73f6690c0ab218e8538483a   # 最后修改 prd.md 的提交（blob f7a19ce6…，自该提交起逐字未变）
dep-2   ai-first-platform-docs  c7fde42bd94214a30796aff4493af9428802df75   # 登记来源附件与 PRD 初稿的 checkpoint 提交
dep-11  ai-first-platform-docs  c1db7b9e797714aa952deebd44df15ce303b9149   # 本 SDD 落盘前的本 CR worktree HEAD（dir-graph.yaml 未变）
dep-3/4/5/6/7/8/9/13  multica   59b47993810fabd12fcc393c2fa2e46611f9530d
dep-10/12/14          tools     c3e7c934ef2636c56cc840543cadb4feb5f554aa
```

**核验命令（可复跑；`{TOOLS_ROOT}` 由 KB `dir-graph.yaml#workspace.tools_package_path` 解析，路径取 `resources[].worktreePath` 原样值）**：

```text
node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs git rev-parse HEAD --cwd "<multica worktreePath>"   # 59b47993…
node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs git rev-parse HEAD --cwd "<tools worktreePath>"     # c3e7c934…
node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs git rev-parse HEAD --cwd "<KB worktreePath>"        # 本 SDD 提交前为 c1db7b9e…
git log --format=%H -1 -- change-requests/CR-2026-070/prd.md   # dep-1 的 40 位值 = 54f69aae…
```

> 口径：`dep-N` 的 `commit SHA` 取「该事实在其上成立且可复跑核验」的提交。KB 侧取各文件最后一次被修改的提交（`dep-1`／`dep-2`）或本 SDD 落盘前的 worktree HEAD（`dep-11`）；`multica`／`tools` 侧取本 CR worktree 的 HEAD（评审前若上游 rebase，须按评审时 HEAD 复核行号锚点，只改锚点、不改行为合同）。
### 待核实依赖（`V-1`～`V-6`）

以下引用是**本机全局安装**的 Pi 包的现状事实，无法绑定 `repo` + 40 位 `commit SHA`（无版本化源码检出：`dep-1` §1.4 事实 9 已核实 `C:\Users\GOBAO\Downloads\AI` 下无 pi 源码检出）。因此单列于此，正文只以 `V-N` 引用；每条给出可复跑核实命令与「核实失败时的唯一合法动作」。编号按语义分组（V-1～V-4 = Pi 包，V-5 = 相邻实现，V-6 = 安装树观察），顺序规则只适用于 `dep-N`。

```text
V-1  Pi 包安装事实（@earendil-works/pi-coding-agent 0.85.1，全局安装）
  声明: `bin.pi` → `dist/bundle/cli.js`（CLI 入口为打包产物）；`repository = git+https://github.com/earendil-works/pi.git`（directory packages/coding-agent）；`author = Mario Zechner`；`license = MIT`；子依赖 `@earendil-works/pi-agent-core` 同为 0.85.1
  证据: `{npm root -g}/@earendil-works/pi-coding-agent/package.json`、`where pi` → `D:\tools\npm-global\pi.cmd`
  核实命令: PI="$(npm root -g)/@earendil-works/pi-coding-agent"; node -e "const p=require(process.argv[1]+'/package.json');console.log(p.version,p.bin,p.repository)" "$PI"
  失败动作: 版本/入口若不同 → 以实施时实测为准复核 V-2 的行号锚点，只改行号、不改行为合同与判据

V-2  Pi 内置 bash 的 timeout 现状（模型可见契约与会话内行为）
  声明: `resolveTimeoutMs(timeout)` 在 `timeout === undefined` 时返回 undefined（无默认分支）；输入 schema 的 `timeout` 描述为 `Timeout in seconds (optional, no default timeout)`；`setTimeout` 仅在 `timeoutMs !== undefined` 时挂载，回调内置 `killProcessTree(child.pid)` 并置 timedOut 标志；超时信号为 `timeout:${timeout}`（携带**调用方原始入参**），工具层据该前缀拼出 `Command timed out after ${timeoutSecs} seconds`；非法值/超上限错误文本与上限常量（MAX_TIMEOUT_MS = 2147483647，MAX_TIMEOUT_SECONDS = 2147483.647）逐字如上；AbortSignal 分支独立（`Command aborted`）
  证据: `{npm root -g}/@earendil-works/pi-coding-agent/dist/core/tools/bash.js`（本机实测：解析函数在 L14-24、schema 描述 L28、非法值 L18、超上限 L22、超时信号 L95、`setTimeout`+kill 在 L71-76、工具层文本拼接 L255-257；`killProcessTree` 由 `../../utils/shell.js` 导入，L6）
  核实命令: PI="$(npm root -g)/@earendil-works/pi-coding-agent"; sed -n '12,30p' "$PI/dist/core/tools/bash.js"; sed -n '60,80p' "$PI/dist/core/tools/bash.js"; sed -n '250,260p' "$PI/dist/core/tools/bash.js"
  失败动作: 任一条不符 → 本 SDD 的落点符号与判据必须按实测重写后再评审；不得以「大致相同」通过

V-3  Pi 工具装配路径（改动点的覆盖范围）
  声明: 内置 shell 工具由 `createShellToolDefinition(cwd, config, options)` 统一构造，`parameters` 取共享的 `bashSchema`；`createCodingTools` 装配 `createBashTool(cwd, …)`；PowerShell 工具（`dist/core/tools/powershell.js`）自 `./bash.js` 导入 `createLocalShellOperations` 与 `createShellToolDefinition`，因此与 bash 共享解析点与 schema
  证据: `{npm root -g}/@earendil-works/pi-coding-agent/dist/core/tools/index.js`（`createCodingTools`）、`dist/core/tools/powershell.js` 首 30 行
  核实命令: PI="$(npm root -g)/@earendil-works/pi-coding-agent"; grep -n "createCodingTools" -A 10 "$PI/dist/core/tools/index.js"; head -30 "$PI/dist/core/tools/powershell.js"
  失败动作: 若装配路径不同（例如 bash 与 PowerShell 不共享解析点）→ DEC-2 的选型前提消失，按 per-tool 方案重做 §4.1 与 §2.2.2，并重评 AC-5 的可达性

V-4  Pi 版本化源码的对应路径
  声明: 已安装 `dist/core/tools/bash.js` 的源文件为 `src/core/tools/bash.ts`（随包发布的 `.d.ts.map` 的 `sources`/`sourcesContent` 直接给出 TypeScript 原文，与 `dist` 逐点对应）
  证据: `{npm root -g}/@earendil-works/pi-coding-agent/dist/core/tools/bash.d.ts.map`（`sources: ["../../../src/core/tools/bash.ts"]` + `sourcesContent`）
  核实命令: PI="$(npm root -g)/@earendil-works/pi-coding-agent"; node -e "const m=require(process.argv[1]+'/dist/core/tools/bash.d.ts.map');console.log(m.sources)" "$PI"
  失败动作: 若源码路径不同 → 单元 B 的落点符号以选定路线仓的实际路径为准（符号名与行为合同不变），不改 AC-12 判据

V-5  相邻实现（不属本 CR 改动面）
  声明: 同包内另有一套 harness 工具实现（`@earendil-works/pi-agent-core` 的 `dist/harness/tools/bash.js`，使用 `validateTimeout` 而非 `resolveTimeoutMs`）。CLI 的编码工具面来自 `dist/core/tools/**`（V-3），harness 面不是 CLI 的 bash 工具来源
  证据: `{npm root -g}/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core/dist/harness/tools/bash.js`；V-3 的装配命令
  核实命令: PI="$(npm root -g)/@earendil-works/pi-coding-agent"; grep -rn "validateTimeout" "$PI/node_modules/@earendil-works/pi-agent-core/dist/harness/tools/bash.js" | head
  失败动作: 若评审认定 CLI 实际使用 harness 面 → 本 CR 的落点需相应改址（行为合同与判据不变），并在 SDD 修订行登记

V-6  安装树历史痕迹（不计入本 CR 交付面）
  声明: 已安装包目录内存在 `dist/bundle/chunks/chunk-JVUZSMYM.js.orig-ray-backup`，与当前同名 chunk 文件**不一致**（大小差 1017 B），来源不明
  证据: 该目录的文件清单与大小
  核实命令: PI="$(npm root -g)/@earendil-works/pi-coding-agent"; ls -la "$PI/dist/bundle/chunks/" | grep -i backup
  影响与处置: 说明该机器曾出现**就地改 dist** 的做法（正是 `dep-1` AC-12 所禁止的路径）。本 CR 不修改、不清理、不依赖该文件；设计只依赖 V-2 的两条模型可见事实（均已在当前文件复核），不依赖安装树与上游发布物的逐字一致
  失败动作: 不适用（观察项，不构成设计前提）
```

## 6.4 既有测试面改动清单与零改动核对清单

**改动清单（全部为「增项」，不改既有断言语义）**：

| 面 | 动作 | 触发原因 |
|---|---|---|
| `dep-8` 的 `runtime_config_test.go` | 在既有形状钉子测试内**追加**断言：规则文本出现次数 = 1；多 Provider 逐字一致；不含任一 Provider 目录字面量。断言引用被测常量符号（同文件内的常量），**不**把检索锚短语内联进测试文件——否则 AC-1 的落点面会从 1 文件扩为 2 文件 | AC-1 的机械面（单点性 + Provider-neutral） |
| `dep-8` 的其它三条测试 | **零改动**，必须继续全绿 | B-1（空集与全隐藏情形整段不出现）与类别矩阵 |
| 单元 B 选定路线的源码仓测试面 | 新增/扩展用例：① 未传 timeout → 解析为默认值；② 假时钟 + 真实子进程，未传时 300 秒到期、进程树被清理、文本为 `Command timed out after 300 seconds`；③ 显式 `1200` 不被覆盖；④ 0/负数/NaN/Infinity 与超上限、abort 的既有行为；⑤ schema 描述与默认值一致 | AC-5～AC-8 的可机械核对面 |
| `dep-9` 的 `CUSTOM.md` | 新增本次定制的台账条目（编号顺延、原因追溯含 CR-ID 与 TASK、填写「合并注意」） | AGENTS.md 工程纪律 10；**不受** `zero_diff` 约束 |

**零改动核对清单（提交前逐条核对 diff 文件名）**：`dep-7` 的注入实现（`context.go` 及其 Provider 映射）、`dep-6`、`dep-5`、`dep-10` 全部路径（`tools/skills/**`、`pipeline-templates/**`、`tools/dir-graph.yaml`、`agent-skill-matrix.yml`、`crctl/**`）、`dep-14`（`output-guard/**` 与 CI 步骤）、`dep-13`（`cr-prompts-revised/**` 与 `server/internal/**` 中除本 CR 落点 `dep-4`／`dep-8` 外的文件，同一限定见 §6.3）、`dep-11`（KB `dir-graph.yaml`）、`dep-1`／`dep-2`（PRD 与来源）、`specs/`、`delivery/`、全部受控账本（`_backlog.yml`、`cr.md` 的 status 行由 crctl 写入不计、`review-loop.yml`、`traceability.yml`、`review-annotations/*`）。

**单元 B 的 diff 面例外**：选定路线的版本化源码与其测试文件（§1.3），不适用本仓库的零改动清单，但受 AC-12 的文件集合判据约束。

## 6.5 SDD-CLOSE 关闭义务（CR-2026-060 AC-06）

`dep-1` 显式延后到 SDD 的设计项逐项关闭如下（覆盖该事项实际涉及的各层）：

| 编号 | 待关闭项（来源） | 关闭结论 | 覆盖层 |
|---|---|---|---|
| SDD-CLOSE-01 | FR-1 规则正文的最终措辞与落点选择（`dep-1` §1.5 第 1 条） | **落点＝`writeSkills` 段末尾单点；文本逐字固定见 §3.2；四子句与 FR-1 四行为合同一一对应**（§4.3、DEC-1）。不存在与之并存完整语义的第二落点（`dep-1` §1.4 事实 3 已证无既有等价公共 contract） | 生产（常量合成）／传输（brief 段 → Provider 配置文件，`dep-5`）／消费（Agent 读取与选择 Skill）／降级（零 Skill 情形整段不注入＝B-1，显式登记） |
| SDD-CLOSE-02 | FR-2 默认值与内部 `timeout:` 错误传递的接线方式（`dep-1` §1.5 第 2 条） | **默认值在 `resolveTimeoutMs` 的 `undefined` 分支注入（唯一 owner）；超时信号改为携带实际生效秒数（未传取 `DEFAULT_TIMEOUT_MS / 1000`、已传取调用方原始入参本身，显式路径模板求值逐字相同），错误文本格式与工具层解析零 diff**（§4.1、§4.2、DEC-4） | 生产（解析常量）／传输（超时信号字符串）／消费（工具层错误文本与 Agent 失败语义）／降级（默认值失效即回归无界，由 AC-5 断言兜底） |
| SDD-CLOSE-03 | Pi 侧交付路线、被升级版本产出方、PATH 切换记录（`dep-1` §1.5 第 3 条、§1.3.2） | **路线选择不属本阶段**：`dep-1` §7 第 11 条把它交给 `write-dev-plan`；本 SDD 关闭其路线无关部分＝落点符号（§4.1／V-4）、行为合同（§3.1）、测试判据（§6.4）、证据形态（§1.3／§4.6）、产出方与时点的记录字段（§1.3）。路线选定后由 PLAN/TASK 记录并在 SDD 的修订行追加「选定路线 + 产出方 + 时点」一栏，**不改变本节设计** | 生产（源码改动与构建）／传输（artifact 版本号／PR 链接）／消费（运行环境替换 `pi` 可执行文件，发生在 CR 合并之后）／降级（R-B 下 AC-5～AC-8 的运行环境侧验证顺延至上游发版后，`dep-1` AC-12 补充口径） |

**PRD 侧未闭合 suggestion 的处置**：需求评审 S-6（`dep-1` §7 第 14 条与 §1.3.2 的 R-A 字面冲突）为非阻塞建议，需求评审已给出修复方向（「需求期不预先新建，是否建设施由开发计划按 §1.3.2 选定路线后决定」）。本 SDD **不删除** R-A／R-C，也不预设新建设施：§7 第 14 条按该修复方向理解为「需求期不预先建设施」，与 DEC-3（本 CR 内不扩充仓库声明）一致；实现期若选定 R-A／R-C，其建仓动作由 dev-plan 侧决定（`follow_up` F-2），不改本 SDD 的行为合同与 AC 判据。

**DEC-2 后果的取证归属（本轮订正，评审 S-4）**：内置 PowerShell 工具的「未传 timeout」路径（§9 `scope_in` 第 5 项）在 PRD 的 AC 集里没有独立观察点，其取证归入 AC-5 的同一判据（`resolveTimeoutMs(undefined)` 与共享 schema 的用例），dev-plan／TASK **不**为该行为另造验收面或另加判据；若产品要求 PowerShell 保持无界，出口仍是 `follow_up` F-1。

**R-A／R-C 建仓动作的归属（本轮订正，评审 S-5）**：Pi 源码仓的**建仓／源码检出**属本 CR dev-plan 的决策动作（供其选定路线后执行），`follow_up` F-2 **只**承载「`repositories` 声明变更」这一后续事项——因此四字段自洽判据 ④（`follow_up` 不得承载当前 AC 的必要条件）不被命中：F-2 不是任何当前 AC 的必要条件。

---

# 7. 安全与性能考量

## 7.1 行尾纪律与硬失败（工程纪律 1）

本 CR 的两处改动都**不引入解析器**：单元 A 是常量文本追加，单元 B 是数值分支与字符串模板。但实现与验证期的以下动作必须遵守行尾纪律，落地判据独立于此设计：

1. 任何对仓库文件做哈希、跨行正则或逐行解析的验证脚本（例如 AC-12 的 diff 文件清单核对、AC-4 的账本 sha256 比对）**必须先 `\r\n → \n` 归一**，逐行用 `split(/\r?\n/)`；
2. 跨行正则解析失败必须**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」；
3. 本 SDD 自身引用的 sha256 口径为 **LF-only**（与需求评审 subject-sha256 同口径），复算前先归一。

## 7.2 安全边界（与既有控制面正交）

| 面 | 本 CR 的关系 |
|---|---|
| 受控 shell 白名单 / `protectedPaths` | 零改动（`dep-10`）；不新增 deny/ask 条目——本 CR 不新增命令面 |
| OutputGuard（调用前判定与结果侧治理） | 零改动、零绕过（I3）；compound passthrough 合同由 AC-9 复跑取证 |
| 权限与审批 | 零改动；不涉及 grant、审批签名或人类审批边界 |
| 内部/敏感信息 | 规则文本与常量文本不含路径、凭据、内网地址；不新增日志输出 |
| 生成物 | multica 的 sqlc/governance 生成物不手改（`dep-3` §5 第 5 条）；单元 A 不触及生成物 |
| 改动载体 | **禁止**把已安装 Pi 包的 `dist` 作为改动或交付载体（`dep-1` FR-2 交付边界）；V-6 记录的安装树历史痕迹不清理、不复用、不作为设计前提 |

**默认值的定位**：300 秒是**有界等待**（可用性护栏），不是安全边界；它不替代任何权限判定、不改变失败语义、不把工具错误升级为 CR 业务状态（I5）。

## 7.3 性能与可观测

1. **Brief 体积**：单元 A 只增加一段固定文本（实读 108 个空白分隔词、其中 107 个含字母），相对该段既有体积（`dep-1` §1.4 事实 2 记录的实测口径）为个位数百分比级别；不新增 per-run 变量，缓存前缀稳定性不受影响（`dep-4` 的既有裁决）。
2. **工具调用寿命**：未显式传 `timeout` 的调用从「无界」变为 ≤300 秒（`dep-1` NFR-4）；显式路径零变化。
3. **可观测性**：不新增 metrics、字段或 UI（I5）；AC-2／AC-3 的观察面复用既有会话记录，不加埋点。

## 7.4 残余风险（实施期必须被看见，而不是被假设掉）

| 编号 | 风险 | 口径与处置 |
|---|---|---|
| R-1 | 300 秒误伤**隐式长调用**（未显式声明 timeout 的长测试/build/migration、共享 brief 要求的前台阻塞命令等） | `dep-1` NFR-1 与 §7 第 13 条已把该面显式排除在本 CR 之外（属调用方运行约定）；回滚粒度为「Pi 版本 / 固定默认值」单一处；观察点＝`suite-gate` 冒烟（`dep-1` §6）。若实测误伤，按 §6 回滚粒度处理并另立需求，不在本 CR 内加配置开关 |
| R-2 | AC-2／AC-3 依赖**真实 smoke run**，无法由单元测试替代 | `dep-1` §5 明文要求真实行为验证。若复现环境不可用 → 该节点按技术失败中止并上报，不得退化为静态断言通过（禁止自报替代证据） |
| R-3 | 零 Skill / 全 `disable-model-invocation` 任务的规则不在场（B-1） | 显式边界：既有测试钉住该语义，本 CR 不为其新增第二条注入路径；同类治理列入 `follow_up` F-3 |
| R-4 | 单元 B 的**验证时点受路线影响** | R-A／R-C：可在本 CR 内完成源码侧验证；R-B：AC-5～AC-8 的运行环境侧验证须等上游发版（`dep-1` §5 补充口径）。本 CR 不承诺路线结果，也不得因路线未定而跳过源码侧判据 |
| R-5 | 安装树存在历史就地修改痕迹（V-6） | 不清理、不依赖；设计只依赖 V-2 的两条模型可见事实。若实施期发现有人以改 `dist` 的方式"验证"本 CR，视为交付违规（AC-12 判据命中） |
| R-6 | 规则文本与 Skill 列表的**语义分工**可能被 Agent 误读为「列表外的 Skill 也存在，只是没列」 | 文本第 4 子句已给出唯一合法动作（中止并报告）；AC-4 用零账本写入与零兜底搜索双侧取证 |

---

# 8. Prompt 采纳影响

**不适用**，判据如下（`write-tech-design` 章节 8 的条件）：本 CR 的 diff **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，也**不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`——单元 A 的落点在 multica 的 daemon 文本合成，单元 B 的落点在 Pi 源码，两处都不在 `dep-10` 的 crctl／guard 面上（§6.4 零改动清单已覆盖该判定）。

---

# 9. 批准范围

## scope_in（当前 CR 必须交付的 FR/AC）

1. **FR-1**（AC-1～AC-4）：在 `dep-4` 的 `writeSkills` 内以**单点常量**追加 §3.2 的 Provider-neutral 规则文本，随 `## Skills` 段下发；同步扩展 `dep-8` 的形状钉子测试（单点性、跨 Provider 逐字一致、无 Provider 路径字面量）。
2. **FR-2**（AC-5～AC-8、AC-12）：在**选定路线的 Pi 版本化源码**内落地 `DEFAULT_TIMEOUT_MS = 300_000`、`resolveTimeoutMs` 的 `undefined` 分支、超时信号的实际生效秒数、`timeout` 参数的 schema 说明文案，及其在该仓既有测试面内的用例。
3. **治理登记**（`dep-9`，AGENTS.md 工程纪律 10 强制）：在 `CUSTOM.md` 按其当时实际结构顺延编号登记本次 multica 侧定制（原因追溯含 CR-ID 与 TASK、填写「合并注意」）。该条目是本 CR 在 multica 仓 diff 的组成部分，不受 `zero_diff` 约束（而单元 A 的落点本身受 §6.4 的核对清单排除在 zero_diff 之外）。
4. **过程产物**：本 SDD 及实现期按 §1.3／§4.6 记录的 Pi 侧交付证据（commit range／PR 链接、产出方与升级时点字段）。
5. **DEC-2 的显式后果**：内置 PowerShell 工具沿用同一解析点，其「未传 timeout」路径同样获得 300 秒默认值——该行为属本 CR 交付面（不是副作用）与 AC-5 的同一判据。

## scope_out（明确排除的路径和能力）

1. `dep-1` §7 全部十四条排除项，逐条不重复展开，其中与本设计最相关的：不新建 npm scope／私有 registry／Pi fork 仓库（需求期不预先建设施，S-6 修复方向）；不向上游提 PR 的**结果保障**；不在 Multica／OutputGuard／Agent／Skill／Pipeline 侧另设第二套计时器。
2. 逐条排查或代改现存**隐式 timeout 长调用面**（§7.4 R-1）。
3. 零 Skill / 全 `disable-model-invocation` 任务的同类治理（B-1、R-3）。
4. 新增任何 Skill Locator／manifest／注册表／路径索引／第二 Guard／Shell parser／错误码／metrics／数据库／sidecar／状态／账本字段／事务框架／Pipeline 节点。
5. 把 Pi 源码仓纳入 `dep-11` 的 `repositories` 声明（DEC-3）。
6. 运行环境 PATH 上 `pi` 可执行文件的替换动作（发生在 CR 合并之后，属运行环境维护）。

## zero_diff（明确不得改动的调用点 / 签名）

| 编号 | 对象 | 说明 |
|---|---|---|
| Z-1 | `dep-7` 的 `writeContextFiles`／`resolveSkillsDir`／`skillsDirPath`／`writeSkillFiles` | 注入目录、文件名、frontmatter 语义与碰撞处理一律不改（I2） |
| Z-2 | `dep-6` 的 `modelVisibleSkills`／`resolveSkillSlugs`／`skillModelInvocationVisible` | 可见性过滤与 slug 派生语义不改（§1.4 术语口径的载体） |
| Z-3 | Pi 侧 `BashOperations` 接口签名与「工具入参 → `ops.exec`」的传参 | 自定义 operations 的可观察行为不变（B-2、DEC-4） |
| Z-4 | Pi 侧 `killProcessTree`／AbortSignal 分支／`MAX_TIMEOUT_MS` 上限常量与档 1／2 的错误文本 | 逐字不变（AC-8）；不得新增清理逻辑或第二计时器 |
| Z-5 | `dep-10` 的全部路径（`tools/skills/**`、`pipeline-templates/**`、`tools/dir-graph.yaml`、`agent-skill-matrix.yml`、crctl 与 guard 声明）与 `dep-13`（`cr-prompts-revised/**` 与 `server/internal/**` 中除本 CR 落点 `dep-4`／`dep-8` 外的文件，同一限定见 §6.3） | AC-1 零复制面 + AC-10 零 diff 面；含四类 `review-*` Skill 与 Agent Prompt 副本。**本项不含 `dep-4`／`dep-8` 的落点文件**——后者由 `scope_in` 第 1～2 项要求修改（判据 ①：同一对象不得同时被要求修改与不修改） |
| Z-6 | `dep-14`（`output-guard/**` 与 CI 触发/步骤） | AC-9；不新增测试基础设施 |
| Z-7 | `dep-11`（KB `dir-graph.yaml`）、`dep-1`／`dep-2`（PRD 与来源）、`specs/`、`delivery/`、全部受控账本与 `dep-4` 的 `## Skills` 段形状（slug 索引、无描述、无 Provider 分支） | 段形状是本 CR 追加文本的容器，不得借本次改动重排 |
| Z-8 | `dep-3` §5 的生成物（sqlc/governance） | 不手改 |

## follow_up（发现但留给后续 CR 的缺口）

| 编号 | 缺口 | 说明 |
|---|---|---|
| F-1 | 内置 PowerShell 工具是否应保持无界 | DEC-2 的选定后果是"同样获得 300 秒默认值"。若产品明确要求 PowerShell 保持无界，须另立需求（或经本阶段评审裁决后改采 per-tool 方案），本 CR 不预留开关 |
| F-2 | Pi 源码仓是否纳入 CR worktree 集合（`repositories` 声明变更） | 若 dev-plan 选定 R-A／R-C 且需要 checkpoint/对账覆盖 Pi 改动，由该阶段提出并走既有仓库声明变更流程（DEC-3）；本项**只**承载 `repositories` 声明变更，「建仓／源码检出」动作属本 CR dev-plan 的决策动作（§6.5） |
| F-3 | 零 Skill / 全 `disable-model-invocation` 任务的同类治理 | 该情形下规则文本不在场（B-1、R-3），需要另外的设计决策（例如规则段与列表解耦），不在本 CR 范围 |
| F-4 | 隐式长调用面的显式 timeout 声明指引 | `dep-1` §7 第 13 条排除；若 300 秒在真实使用中误伤（R-1），需要的是调用方约定或配置面（后者已被 §7 第 8 条排除），须另立需求 |
| F-5 | 已安装 Pi 包安装树的历史就地修改痕迹（V-6） | 来源不明、与本 CR 无关；双周 rebase 核对时可顺带确认 `dist` 是否被就地改过（与本 CR 的 AC-12 判据同源） |

---

# 修订记录

| 版本 | 时间 | 作者 | 说明 |
|---|---|---|---|
| 0.1 | 2026-09-18 | dev-agent | 初稿：按 `dep-1` PRD v0.2 与 `dep-2` 来源出具技术设计；单元 A（FR-1 单点规则文本）与单元 B（FR-2 默认值 + 错误秒数传递）两个改动单元；§6.3 既有实现依赖 14 项 + 待核实依赖 6 项；§6.5 关闭 `dep-1` §1.5 三条延后项；四个决策（DEC-1～DEC-4，均满足三判据；DEC-2 的 PowerShell 继承后果已显式进入 `scope_in`）；`dep-1` §5 的 Pi 侧路线选择按 §7 第 11 条保留给 `write-dev-plan` |
| 0.2 | 2026-09-18 | dev-agent | 技术评审 attempt 1 回修（repair-target=write-tech-design）。**B-1**：统一 AC-1 的零复制面口径——`dep-13` 的 `server/internal/**` 收窄为「本 CR 落点 `dep-4`／`dep-8` 之外的文件」，§3.2 零复制面、§6.2 的 AC-1 行、§6.3 `dep-13`、§6.4 核对清单与 §9 Z-5 五处使用同一限定（消除 `zero_diff` 与 `scope_in` 第 1～2 项对同一对象的矛盾，并写明落点面命中 1／零复制面命中 0 是同一次检索的两侧）；§6.4 补「断言引用常量符号、不内联锚短语」以保持落点面为 1 文件。**S-1** §6.3 的 tools 面编号 `dep-12/12/13`→`dep-10/12/14`；**S-2** §4.2 信号值改为「未传取 `DEFAULT_TIMEOUT_MS / 1000`、已传取调用方原始入参本身」，使显式路径与现状逐字相同（消除双精度往返误差，NFR-1 字面成立；DEC-4 与 SDD-CLOSE-02 同步）；**S-3** §7.3 词数订正为实读值（108 空白分隔词／107 含字母词）；**S-4** §6.5 写明 PowerShell 后果的取证归入 AC-5、不另造验收面；**S-5** §6.5 与 F-2 写明建仓／源码检出属 dev-plan 决策动作、F-2 只承载 `repositories` 声明变更。FR／AC 合同、`scope_in` 交付面、`target-version` 与四个决策的选定结论均未改动。 |
