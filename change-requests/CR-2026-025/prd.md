---
id: CR-2026-025-prd
type: PRD
cr-ref: CR-2026-025
title: crctl 守卫与回显收敛（check-skill-matrix external 引用校验 + depends-on 依赖守卫 + gate/advance blockers 回显截断）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-08T21:46:15+08:00"
updated: "2026-08-08T21:46:15+08:00"
---

# PRD — crctl 守卫与回显收敛

## 1. 概述

### 1.1 问题陈述

本 CR 合并三项独立的漂移治理项，它们共享同一个交付面（`crctl.mjs` / `check-skill-matrix.mjs` 本体 + 各自测试向量），且都不改状态机、不改数据模型：

**项① — `external` 声明无引用校验（方案 v2.6 §7 的 D-2）**：`agent-skill-matrix.yml` 的 `external:` 字段只被 `check-skill-matrix.mjs` 用作「豁免 owns 唯一性检查」，从不校验被声明的外部技能是否真被引用。后果已由 CR-2026-024 坐实：`using-superpowers` / `writing-plans` / `verification-before-completion` 三个声明多个 CR 周期零引用点、CI 从未报警；`implement-code/SKILL.md:75` 引用未安装的 `test-driven-development` 导致规则静默蒸发。CR-2026-024 清理了存量，但**没有装上防复发的闸**——同一失效模式可以立刻再来一次。

**项② — `depends-on` 无机械强制（方案 v2.6 §4.8/§7 的 D-5）**：`depends-on` 已声明（`write-dev-tasks/SKILL.md:41`）、已写入 TASK frontmatter、已汇总进 `tasks/_index.yml`、已被 `validate-doc` 校验指向有效，CR-2026-024 又给 `implement-code` 补了 prompt 层拓扑排序。但 `crctl task done` 写 `status: done` 时不看依赖——前置 TASK 还是 pending，后继 TASK 照样可以标完成。prompt 层规则靠 agent 自觉，账本层无守卫，这是 CR-2026-024 自己在 §5 决策表里明确留给独立 CR 的部分。

**项③ — gate/advance 回显同一 payload 三份**：`evaluatePassCondition`（`crctl.mjs:551/554`）对每个失败条件把 `val` 全量写进 `actual`，同一行的 `why` 再 `JSON.stringify` 一次；`cmdAdvance`（`crctl.mjs:996`）按 CR-2026-021 FR-5 把 `why` 抬进 `GATE_BLOCKED` 摘要，而 `fail()` 又会序列化整个 `{ gate }` detail——`advance` 失败路径同一份 blockers 落地三次。此项由 CR-2026-024 SDD 评审过程实测发现（该轮 7 条 blocker 撑出 8.6KB 输出）。

三项的共同点是**本包已有机制但缺最后一环**：①有声明面无校验、②有数据有 prompt 规则无账本守卫、③有单一事实源却重复回显。

### 1.2 解决方案摘要

- **项①**：`check-skill-matrix.mjs` 新增第 4 项检查——每个 actor 级 `external` 声明必须在 `skills/**/*.md` 或 `pipeline-templates/*.json` 中找到至少一处引用点，零引用即报错退出非 0；同时删除 `agent-skill-matrix.yml` 顶层从未被解析的 `external-skills:` 块并同步 `AGENT-SKILL-MATRIX.md` 的声明位置表述（消除第二份事实源）。新建 `check-skill-matrix.test.mjs`。
- **项②**：`crctl task done` 在 CAS 写入前校验目标 TASK 的 `depends-on` 前置项均已 `done`，否则以 `DEPENDS_ON_NOT_DONE` 拒写并列出未完成前置；依赖图成环时以 `DEPENDS_ON_CYCLE` 拒写。复用既有 `parseYaml`（实测已能解析 `depends-on: [A, B]` 内联流式数组），零新增解析代码。
- **项③**：`evaluatePassCondition` 引入逐项截断——`actual` 保持数组类型仅按 `ITEM_MAX=120` 截断每项，`why`/`message` 只给条数并指向 `file` 字段已有的证据文件路径。

### 1.3 事实基线（已核实，纪律 #4）

| # | 事实 | 位置 / 依据 |
|---|---|---|
| B-1 | `check-skill-matrix.mjs` 现有 3 项检查（active skill 恰一个 owns / owns 目标已注册或声明为 external / md 表格与 yml 一致），无任何引用点校验 | `check-skill-matrix.mjs:6-9,66-89` |
| B-2 | 该脚本把 `external` 解析成**全局 Set**（`externalSkills`），不记录声明它的 actor | `check-skill-matrix.mjs:36,46` |
| B-3 | actor 级 `external` 共 8 处声明、跨 5 个 actor；实测引用点：`brainstorming`(product-planning-agent)=1、`brainstorming`(competitive-analyst-agent)=1、`executing-plans`=2、`subagent-driven-development`=2、`test-driven-development`=2、`using-superpowers`=0、`writing-plans`=0、`verification-before-completion`=0 | 本 CR 需求期实跑扫描（skills/ + pipeline-templates/，排除 openwiki/old） |
| B-4 | `brainstorming` 被两个 actor 声明，但唯一引用点 `skills/competitive/report-to-planning-suggestion/SKILL.md` 归 `competitive-analyst-agent` owns（`agent-skill-matrix.yml:165`、`AGENT-SKILL-MATRIX.md:28`）——actor 级严格口径会把 `product-planning-agent.external.brainstorming` 判为零引用 | 实跑核对 |
| B-5 | 顶层 `external-skills:` 块（`agent-skill-matrix.yml:222-230`）条目缩进 2 空格，而 checker 的条目正则要求 6 空格（`check-skill-matrix.mjs:44`）——**从未被解析**；但 `AGENT-SKILL-MATRIX.md:57` 写明「外部方法论 Skill 只能出现在 `external` 或 `external-skills` 中」，把它当作合法声明位置 → 两份事实源 | 实跑核对 |
| B-6 | `cmdTaskDone`（`crctl.mjs:1298-1310`）只校验 status=developing、TASK 存在、非已 done 三项，**零依赖校验**；审计记录里 `before.from` 硬编码为 `'pending'` | 源码 |
| B-7 | `tasks/_index.yml` 的 `depends-on` 为内联流式数组（如 `depends-on: [CR-2026-001-TASK-01, CR-2026-001-TASK-02]`）；实测既有 `parseYaml` 能正确解析（含空数组 `[]`） | 需求期对 `parseYaml` 的实跑探针 + CR-2026-001/002/003 真实 `_index.yml` 样本 |
| B-8 | `crctl task allocate` 生成的条目只含 `id`/`slug`/`status` 三字段，不含 `depends-on`（`appendTaskEntry`，`crctl.mjs:1854`）——字段缺失是正常形态 | 源码 |
| B-9 | `evaluatePassCondition` 的 `equals` 与 `isEmpty` 两分支各把 `val` 同时写进 `actual` 与 `why` | `crctl.mjs:551,554` |
| B-10 | `cmdAdvance` 门禁失败时 `fail('GATE_BLOCKED', …, { gate })`，而 `fail()` 会 `JSON.stringify` 整个 extra——`why` 摘要 + `gate.checks[].detail[].actual` + `.why` 三份同时落地 | `crctl.mjs:29-32,995-998` |
| B-11 | 实测量化（CR-2026-024 tech-design attempt-1 的 7 条 blocker，最长 538 字）：全量序列化一份 2922 字符；`advance` 失败路径 8.6KB、`gate` 只读路径 5.7KB；逐项截断 120 字符后一份 947 字符 | 需求期实跑测算 |
| B-12 | `cmdNext` 只输出 blockers **条数**（`crctl.mjs:2222`），不回显原文——不属本 CR 改动面 | 源码 |
| B-13 | `check-skill-matrix.mjs` **无测试文件**：`skills/shared/crctl/scripts/test/` 下只有 `crctl.test.mjs` 与 `lint-prompts.test.mjs` | 目录实测 |
| B-14 | 测试约定：`node --test <file>`，零第三方依赖，仅用 `node:test`/`node:assert`，通过 `spawnSync` 黑盒调用被测脚本 | `ARCHITECTURE.md:104`、`crctl.test.mjs` 头注释 |
| B-15 | `gates.json` 的 `passCondition` 判据不写死在 crctl 里，运行时从 pipeline JSON 的 `reviewLoop.passCondition.allOf` 读取——本 CR 只改回显形态，不触判据来源 | `crctl.mjs:528-536` |

### 1.4 决策点（本 PRD 拍板，SDD/实施期不得再次悬置）

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 项①规则粒度：全局名级 vs actor 级 | **全局名级**——同一名称在扫描范围内有 ≥1 引用点即通过，不要求引用点位于声明该 external 的 actor 自己 owns 的 skill 内 | actor 级需新引入「SKILL.md ↔ owns actor」归属映射（当前 checker 无此映射），且按 B-4 会立刻把 `product-planning-agent.external.brainstorming` 判红——而 `brainstorming` 恰是方案认定的「唯一四件套齐全样板」。收紧到 actor 级列为后续项 |
| D-2 | 顶层 `external-skills:` 块处置 | **整块删除**，并同步修订 `AGENT-SKILL-MATRIX.md:57` 使 actor 级 `external` 成为唯一声明位置 | 该块从未被解析（B-5），保留即第二份事实源；让 checker 转而去解析一个装饰性块，等于把两份声明面固化下来。删除优于新增解析 |
| D-3 | 与 CR-2026-024 的实施先后 | **本 CR 必须在 CR-2026-024 批次一合入之后实施** | B-3 实测三处零引用声明由 CR-2026-024 删除；本 CR 若先落，新规则上线即报 3 项红（外加 CR-2026-024 删 `test-driven-development` 引用后的第 4 项），把存量债务算到新守卫头上 |
| D-4 | 项②守卫的失败形态：硬失败 vs WARN | **硬失败拒写**，错误码 `DEPENDS_ON_NOT_DONE`，不提供绕过旗标 | crctl 既有风格一致为拒写（`TASK_ALREADY_DONE`/`ILLEGAL_LEDGER_STATE`/`CAS_CONFLICT` 皆 `fail`）；WARN 会重蹈 `depends-on`「声明了没人消费」的覆辙——本 CR 的存在理由正是把建议升级为强制 |
| D-5 | `depends-on` 字段缺失的语义 | **视为无依赖，放行** | B-8：`task allocate` 生成的条目本就不含该字段，缺失是正常形态而非异常 |
| D-6 | 环检测是否纳入本 CR | **纳入**，错误码 `DEPENDS_ON_CYCLE` | 守卫本就要遍历依赖链，环检测是同一次遍历的副产品；CR-2026-024 §7 已把「真正防环」显式指向 D-5，本 CR 即 D-5 |
| D-7 | `ITEM_MAX=120` 是否做成可配置项 | **常量，不做配置面** | 包内无同类阈值配置先例；配置项本身要新增读取/校验/文档三处成本，而该值只影响可读性不影响正确性 |
| D-8 | 项①测试形态 | **新建 `check-skill-matrix.test.mjs`**，沿用 `node --test` + `spawnSync` 黑盒（B-14） | 该脚本此前无测试（B-13）；新增可执行规则却不留可执行验证，与本 CR 主题自相矛盾 |
| D-9 | 项③是否同时收敛 `cmdNext` | **不做** | B-12：`next` 只打条数，本就无冗余，改它属无中生有 |

## 2. 用户故事

- **US-1** 作为 tools 包维护者，当我在 `agent-skill-matrix.yml` 里声明一个 `external` 技能却没有在任何 SKILL.md 或 pipeline prompt 里真正引用它时，`check-skill-matrix.mjs` 立刻报错，而不是让这条死声明在仓库里躺过多个 CR 周期无人察觉。
- **US-2** 作为 tools 包维护者，我只需在**一个位置**（actor 级 `external`）声明外部技能依赖，不必再同步一份从未被任何程序读取的顶层清单。
- **US-3** 作为 `dev-agent`（实现者），当我试图把一个前置 TASK 尚未完成的 TASK 标记为 done 时，`crctl task done` 拒绝写入并告诉我在等哪几个前置项，而不是静默接受、留下一个依赖顺序被违反却看不出来的账本。
- **US-4** 作为 `dev-agent`，当 `tasks/_index.yml` 的依赖关系意外成环时，`crctl task done` 明确报错而不是陷入遍历或静默放行。
- **US-5** 作为评审者/审批人，当门禁因 blockers 非空而拒绝推进时，`crctl gate` / `crctl advance` 的输出让我一眼看清「哪几条没过」，而不是把同一份长文本 blockers 重复三遍刷屏。
- **US-6** 作为调用 crctl 的上层程序（pipeline runtime / 桌面壳），`gate` 输出的 `actual` 字段仍是数组，我原有的 `.length` 类取值不会因这次改动而失效。

## 3. 功能需求

### 项① · external 声明引用校验（D-2 落地）

- **FR-1（新增检查 4：external 引用点校验）**：`check-skill-matrix.mjs` 新增第 4 项检查——对每个从 actor 级 `external:` 解析出的技能名，在扫描范围内统计引用点数量；为 0 时记入 `errors`，错误文案须包含技能名、声明它的 actor（复数则全列）与「零引用点」判定语，退出码非 0。文件头部注释的「检查项」清单同步补第 4 条。
- **FR-2（引用点扫描口径）**：扫描范围 = `skills/` 与 `pipeline-templates/` 下的 `*.md` 与 `*.json` 文件（递归），**排除** `openwiki/`、`old/`、`node_modules/`、`.git/`；命中判定为文件文本包含该技能名（子串匹配即可，与 CR-2026-024 认定死声明时所用口径一致）。`agent-skill-matrix.yml` 与 `AGENT-SKILL-MATRIX.md` 自身不计入引用点（声明面不能自证）。
- **FR-3（解析器记录声明 actor）**：现有解析把 external 收进全局 `externalSkills` Set（B-2），需扩展为同时记录 `externalByActor`（actor → 技能名[]）以支撑 FR-1 的错误文案；检查 2 继续使用全局集合，行为不变。
- **FR-4（删除顶层 external-skills 块，D-2）**：删除 `agent-skill-matrix.yml` 的顶层 `external-skills:` 块（L222-230 整块）；同步修订 `AGENT-SKILL-MATRIX.md:57`「外部方法论 Skill 只能出现在 `external` 或 `external-skills` 中」为「只能出现在 actor 级 `external` 中」，并注明这是唯一被 `check-skill-matrix` 解析的声明位置。
- **FR-5（新建 check-skill-matrix 测试，D-8）**：新建 `skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs`，`node --test` + `spawnSync` 黑盒，零第三方依赖。至少覆盖四类向量：① external 有引用点 → 通过；② external 零引用点 → 退出码非 0 且错误含该技能名；③ 同一 external 被多 actor 声明且有引用点 → 通过（`brainstorming` 形态，B-4）；④ 既有三项检查的回归各至少一条（缺归属 / 目标缺失 / md 漂移）。

### 项② · depends-on 依赖守卫（D-5 落地）

- **FR-6（task done 依赖守卫）**：`crctl task done <cr> --task <TASK-ID>` 在 `casWrite` 之前，解析 `tasks/_index.yml`，读取目标 TASK 的 `depends-on`；若其中存在 `status != done` 的前置 TASK，以 `DEPENDS_ON_NOT_DONE` 硬失败拒写（D-4），错误 detail 须列出**未完成前置的 id 与当前 status**。校验发生在既有三项前置校验（status=developing / TASK 存在 / 非已 done）之后、写入之前。
- **FR-7（缺失与空值语义，D-5）**：`depends-on` 字段缺失或为空数组 `[]` 时视为无依赖，直接放行；`depends-on` 指向 `tasks/_index.yml` 中不存在的 TASK-ID 时以 `DEPENDS_ON_UNKNOWN` 失败（引用悬空本身即缺陷，不静默忽略）。
- **FR-8（环检测，D-6）**：遍历依赖链时检出环（含自引用）以 `DEPENDS_ON_CYCLE` 失败，detail 列出构成环的 TASK-ID 序列；不静默吞环、不无限遍历。
- **FR-9（复用既有解析器）**：依赖解析必须复用 crctl 既有的 `parseYaml`（B-7 实测已支持内联流式数组与空数组），**不得**新写 YAML 解析或正则提取；读入后先 `\r\n → \n` 规范化（纪律 #1）。
- **FR-10（用途表与文档同步）**：`skills/shared/crctl/SKILL.md` 的用途表补 `task done` 的依赖守卫说明与两/三个新错误码；`README.md` 若含 `task done` 行为描述则同步。CR-2026-024 在 `implement-code/SKILL.md` 落的 prompt 层拓扑排序表述需补一句「依赖顺序由 `crctl task done` 机械强制」，使 prompt 层规则与账本守卫互为印证而非各说各话。
- **FR-11（crctl 测试向量）**：`crctl.test.mjs` 追加向量覆盖：① 前置未 done → `DEPENDS_ON_NOT_DONE` 且退出非 0、`_index.yml` 未被修改；② 前置全 done → 正常写入 `status: done` 与 `done-at`；③ `depends-on` 缺失/空数组 → 放行；④ 成环 → `DEPENDS_ON_CYCLE`；⑤ 指向不存在 TASK → `DEPENDS_ON_UNKNOWN`。

### 项③ · gate/advance blockers 回显收敛

- **FR-12（逐项截断助手）**：在 `evaluatePassCondition` 作用域内引入常量 `ITEM_MAX = 120` 与两个纯函数——`briefActual(v)`：数组则逐项截断（字符串超长时截断并追加 `…(+N字)` 标记），非数组原样；`briefWhy(v)`：数组则返回 `{N} 条`，非数组返回原 `JSON.stringify` 形态。
- **FR-13（两分支改用助手）**：`crctl.mjs:551`（`equals` 分支）与 `:554`（`isEmpty` 分支）的 `actual` 改为 `briefActual(val) ?? null`；`why` 改用 `briefWhy(val)` 并在末尾追加 `（详见 ${doc.path}）` 指针。
- **FR-14（`actual` 类型契约不变）**：截断后 `actual` 对数组输入仍返回数组、对标量仍返回标量，调用方既有的 `.length`/索引取值不受影响（NFR-3）。
- **FR-15（取舍写进注释）**：改动处须有注释写明——本收敛**只封单条长度、不封条数**，条目数极多时输出仍会线性增长；以及全量原文的唯一来源是 `file` 字段指向的 `review-annotations/{stage}.yml`。
- **FR-16（crctl 测试向量）**：`crctl.test.mjs` 追加向量：构造含超长 blockers 的评审证据后跑 `gate --for <评审通过态>`，断言 ① 退出码非 0；② `checks[].detail[].actual` 仍是数组且每项长度 ≤ `ITEM_MAX + 后缀`；③ `why` 含条数与 `详见` 指针且**不含**完整原文；④ `advance` 失败路径的 `GATE_BLOCKED` message 同样不含完整原文。

### 收尾

- **FR-17（验证关卡）**：`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce` 全绿；`node --test` 跑通 `crctl.test.mjs`、`lint-prompts.test.mjs`、新增的 `check-skill-matrix.test.mjs` 三个测试文件全部用例。
- **FR-18（溯源标注）**：commit message 注明来源为方案 v2.6 §7（D-2/D-5）与 CR-2026-024 SDD 评审实测发现，并含 CR-2026-025 编号；全部改动不引入本机绝对路径。
- **FR-19（ARCHITECTURE.md 登记）**：若本 CR 改动落在 `ARCHITECTURE.md` §3/§5/§6 覆盖面（crctl 命令面语义扩展、守卫面新增），按 §8 维护规则登记本 CR；测试文件新增同步 §8 代码地图与 `dir-graph.yaml`。

## 4. 非功能需求

- **NFR-1（零新增第三方依赖）**：三项改动全部使用 `node:` 内置模块，测试仅用 `node:test`/`node:assert`（B-14）。
- **NFR-2（不改状态机、不改数据模型）**：不新增/修改 CR 状态与转换；不改 `tasks/_index.yml`、`review-annotations/*.yml`、`gates.json` 的 schema——项②只读既有 `depends-on` 字段，项③只改输出形态不改证据文件。
- **NFR-3（gate 输出向后兼容）**：`actual` 字段类型契约不变（数组仍是数组）；新增的截断标记只出现在字符串内部，不改变 JSON 结构层级或字段名。
- **NFR-4（判据来源不变）**：项③不触碰 `passCondition` 的判据解析路径（B-15：判据仍运行时读自 pipeline JSON 的 `reviewLoop.passCondition.allOf`），只改结果的呈现。
- **NFR-5（实施顺序依赖，D-3）**：本 CR 的项①实施与验证必须在 CR-2026-024 批次一合入 `custom/main` 之后进行；若 CR-2026-024 未合入，FR-17 的 `check-skill-matrix` 全绿要求无法满足（B-3 的 3~4 项零引用声明会报红）。SDD 需据此排定实施顺序。
- **NFR-6（行尾纪律，纪律 #1）**：项②的 `_index.yml` 读入后先 `\r\n → \n` 规范化再解析，解析失败硬失败不静默降级（与既有 `editTaskDone`/`appendTaskEntry` 同款处理）。
- **NFR-7（可移植性）**：改动与测试不含本机绝对路径；测试用临时目录（`mkdtempSync`）构造夹具，与既有 `crctl.test.mjs` 风格一致。
- **NFR-8（不新写解析器）**：项②复用 `parseYaml`（FR-9）；项①沿用 `check-skill-matrix.mjs` 既有的行级正则解析风格，不引入 YAML 库。
- **NFR-9（基线协调）**：tools 仓工作区若存在与本 CR 无关的未提交修改（已知存在 `.qoder/repowiki/` 等删除态文件），提交时只 add 本 CR 文件清单，严禁 `git add -A`。

## 5. 验收标准

- **AC-1**（FR-1/FR-3）：在 `agent-skill-matrix.yml` 某 actor 的 `external` 下插入一个仓库内零引用的技能名后运行 `check-skill-matrix.mjs`，退出码非 0 且 stderr 含该技能名与声明它的 actor；移除后恢复通过。
- **AC-2**（FR-2）：只在 `openwiki/` 下出现的技能名**不**计为引用点（仍判红）；只在 `pipeline-templates/*.json` 的 prompt 中出现的技能名**计为**引用点（判绿）。
- **AC-3**（FR-1）：`check-skill-matrix.mjs` 文件头注释的「检查项」清单含第 4 条引用点校验描述。
- **AC-4**（FR-4）：`agent-skill-matrix.yml` grep 不到 `external-skills`；`AGENT-SKILL-MATRIX.md` 中该表述已改为「actor 级 `external`」且不再提 `external-skills`。
- **AC-5**（FR-4/FR-17）：CR-2026-024 批次一合入后的真实仓库上运行 `check-skill-matrix.mjs` 通过——即 `brainstorming`×2、`executing-plans`、`subagent-driven-development` 四项声明全部有引用点（B-3 预期终态）。
- **AC-6**（FR-5/D-8）：`skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs` 存在；`node --test` 跑通且含 FR-5 列出的四类向量；无第三方依赖 import。
- **AC-7**（FR-6/FR-11）：前置 TASK 为 `pending` 时执行 `crctl task done` → 退出码非 0、错误码 `DEPENDS_ON_NOT_DONE`、detail 列出该前置 id 与 status，且 `tasks/_index.yml` 内容 sha256 与执行前一致（确认未写入）。
- **AC-8**（FR-6）：前置 TASK 全部 `done` 时执行 `crctl task done` → 正常写入 `status: done` 与 `done-at`，行为与改动前一致。
- **AC-9**（FR-7）：`depends-on` 缺失与 `depends-on: []` 两种形态均放行；`depends-on` 指向不存在的 TASK-ID 时报 `DEPENDS_ON_UNKNOWN`。
- **AC-10**（FR-8）：构造 A→B→A 与自引用 A→A 两种夹具，均报 `DEPENDS_ON_CYCLE` 且 detail 含构成环的 id 序列；命令在有限时间内返回（无死循环）。
- **AC-11**（FR-9/NFR-6/NFR-8）：项② diff 中不含新的 YAML 解析实现（grep 无新增 `split(/\r?\n/)` 式自研解析块），依赖解析调用既有 `parseYaml`。
- **AC-12**（FR-10）：`skills/shared/crctl/SKILL.md` 用途表含 `task done` 依赖守卫与新错误码；`implement-code/SKILL.md` 的拓扑排序表述含「由 `crctl task done` 机械强制」一句。
- **AC-13**（FR-12/FR-13/FR-14）：对含 7 条各约 500 字 blockers 的证据跑 `crctl gate --for <评审通过态>`——`checks[].detail[].actual` 仍为数组、每项字符串长度 ≤ `120 + 后缀长度`；`why` 形如 `期望 blockers 为空，实际 7 条（详见 …/sdd.yml）`；输出总字符数较改动前下降 ≥ 60%（B-11 基线：5844 → ~947）。
- **AC-14**（FR-13）：`crctl advance` 门禁失败时 `GATE_BLOCKED` 的 message 与 `gate` detail 中均不含任何一条 blocker 的完整原文（全量原文只存在于 `file` 指向的 canonical 文件）。
- **AC-15**（FR-15）：改动处注释含「只封单条长度、不封条数」与全量原文来源的说明。
- **AC-16**（FR-16/FR-11）：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿，含项②五条与项③四条新增断言。
- **AC-17**（FR-17）：三件套全绿 + 三个测试文件全部用例通过。
- **AC-18**（FR-18/FR-19）：commit message 含 CR-2026-025 与来源溯源；`grep -r "C:\\\\Users"` 在本 CR 改动中零命中；`ARCHITECTURE.md` §8 按需登记，新增测试文件已登记代码地图与 `dir-graph.yaml`。
- **AC-19**（NFR-5/D-3）：SDD 与实施记录显式声明本 CR 在 CR-2026-024 批次一之后实施；AC-5 的验证在该前提下执行。

## 6. 成功指标

- `external` 死声明的复发被机械阻断：新增一条零引用 external 声明会在 pre-commit/CI 阶段直接报红，不再依赖人工评审发现（CR-2026-024 是靠人工逐条实测才挖出三条）。
- `external` 声明位置收敛为一处：仓库内不再存在「写了但没有任何程序读」的第二份外部技能清单。
- `depends-on` 从「声明了没人消费」升级为账本级强制：任何违反依赖顺序的 `task done` 都被拒写并留下可读的未完成前置清单，`depends-on` 的四层链条（声明→写入→汇总→校验）终于接上第五层（驱动行为）。
- 门禁输出可读性：真实 blockers 场景下 `gate`/`advance` 输出体积下降 ≥60%，且失败原因（哪几条、在哪个文件）仍一眼可见。
- 三项均有可执行测试兜底，`check-skill-matrix.mjs` 从零测试变为有测试。

## 7. 范围排除

**本 CR 包含**：项①②③的代码改动、各自测试向量、直接相关的用途表/文档同步。

**本 CR 不包含**：
- **actor 级 external 引用校验的收紧**（要求引用点必须位于声明该 external 的 actor 自己 owns 的 skill 内）——需新引入 SKILL.md↔owns 归属映射，且会牵出 `product-planning-agent.external.brainstorming` 的合法性判断（D-1、B-4），自成独立议题。
- **`can-call` / `forbidden` 的引用校验**——本 CR 只处理 `external`；`forbidden` 已由 CR-2026-024 明确为声明性边界、无调用级拦截，不在此改变其性质。
- **`lint-prompts` 新增「未注册技能名」规则**——CR-2026-024 评审期确认 R1~R9 无此规则，但那属 prompt 正文治理面，与本 CR 的矩阵声明面是两件事。
- **`cmdNext` 的输出收敛**（D-9，B-12：本就只打条数）。
- **`ITEM_MAX` 配置化**（D-7）、**按条数封顶的二级截断**——只封单条长度是本 CR 的显式取舍（FR-15），条数封顶会让 `actual` 不再完整反映失败集合，属另一个取舍。
- **`capabilities` 真闭环 Level C**（CR-2026-024 D-3 已列）、**requirement/tech-design 阶段 suggestions 分流**（CR-2026-024 D-4 已列）——与本 CR 无关，继续留在各自后续项。
- **状态机 / `gates.json` / `rules.json` 本体改动**——本 CR 无此需求（NFR-2）。
- **CR-2026-024 自身的任何改动面**——两 CR 文件面不重叠（本 CR 只碰 `crctl.mjs`、`check-skill-matrix.mjs`、`agent-skill-matrix.yml` 顶层块、`AGENT-SKILL-MATRIX.md` 一行、测试文件与用途表），但存在实施顺序依赖（D-3/NFR-5）。

## 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-08 | v0.1.0 | Ray | 初始草稿（D-2 + D-5 + gate 回显收敛三项合并交付；事实基线 15 条经实跑核对，决策点 D-1~D-9 拍板） |
