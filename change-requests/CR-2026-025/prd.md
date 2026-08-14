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
updated: "2026-08-09T01:30:00+08:00"
---

# PRD — crctl 守卫与回显收敛

## 1. 概述

### 1.1 问题陈述

本 CR 合并四项独立但同属 Tools 确定性执行层的漂移治理项，它们共享同一个交付面（`crctl.mjs` / `check-skill-matrix.mjs` 本体 + 各自测试向量），且都不改状态机：

**项① — `external` 声明无引用校验（方案 v2.6 §7 的 D-2）**：`agent-skill-matrix.yml` 的 `external:` 字段只被 `check-skill-matrix.mjs` 用作「豁免 owns 唯一性检查」，从不校验被声明的外部技能是否真被引用。后果已由 CR-2026-024 坐实：`using-superpowers` / `writing-plans` / `verification-before-completion` 三个声明多个 CR 周期零引用点、CI 从未报警；`implement-code/SKILL.md:75` 引用未安装的 `test-driven-development` 导致规则静默蒸发。CR-2026-024 清理了存量，但**没有装上防复发的闸**——同一失效模式可以立刻再来一次。

**项② — `depends-on` 无机械强制（方案 v2.6 §4.8/§7 的 D-5）**：`depends-on` 已声明（`write-dev-tasks/SKILL.md:41`）、已写入 TASK frontmatter、已汇总进 `tasks/_index.yml`、已被 `validate-doc` 校验指向有效，CR-2026-024 又给 `implement-code` 补了 prompt 层拓扑排序。但 `crctl task done` 写 `status: done` 时不看依赖——前置 TASK 还是 pending，后继 TASK 照样可以标完成。prompt 层规则靠 agent 自觉，账本层无守卫，这是 CR-2026-024 自己在 §5 决策表里明确留给独立 CR 的部分。

**项③ — gate/advance detail 重复回显 blockers 原文**：`evaluatePassCondition`（`crctl.mjs:551/554`）在失败条件的 detail 中把 `val` 全量写进 `actual`，`why` 又 `JSON.stringify` 一次。`runGateChecks` 生成的 passCondition check 只有 `detail`、没有顶层 `why`；`cmdAdvance` 只汇总顶层 `check.why`，所以 `GATE_BLOCKED` message 本身并不含 blockers 原文，冗余实际位于 `gate.checks[].detail[].actual` 与 `.why` 两处。此项由 CR-2026-024 SDD 评审过程实测发现。

**项④ — `review-record` 追溯投影与 `cmdNext` 回修路由缺口**：三个评审 Skill 均要求将 canonical 评审记录同步投影到 `traceability.yml#reviews.<stage>`，但当前 `review-record` 只写 `review-annotations/<stage>.yml`，再单独写 `review-loop.yml`，既未更新 traceability，也可能在第二步失败时留下半状态；同时 `cmdNext` 在 `drafting` 只看 `prd.md` 是否存在，刚产生 requirement block 时仍错误建议再次评审。若只按“存在 block 就回修”修补，PRD 已回修后旧 block 又会导致永久回修，因此还需以被评审 PRD 的规范化内容摘要判断该证据是否仍然新鲜。

四项的共同点是**本包已有机制但缺最后一环**：①有声明面无校验、②有数据有 prompt 规则无账本守卫、③有单一事实源却重复回显、④有评审证据与最小 runner 却缺投影一致性和回修路由。

### 1.2 解决方案摘要

- **项①**：`check-skill-matrix.mjs` 新增第 4 项检查——每个 actor 级 `external` 声明必须在 `skills/**/*.md` 或 `pipeline-templates/*.json` 中找到至少一处引用点，零引用即报错退出非 0；`agent-skill-matrix.yml` 顶层从未被解析的 `external-skills:` 块**保留不删**、标记为非权威纯文档参考，并同步 `AGENT-SKILL-MATRIX.md`/`skills/_index.yml` 的声明位置表述，明确 actor 级 `external` 是唯一权威且唯一被程序解析的声明位置；顶层块不参与校验、无同步要求。新建 `check-skill-matrix.test.mjs`。
- **项②**：`crctl task done` 在 CAS 写入前校验目标 TASK 的**直接** `depends-on` 前置项均已 `done`，否则以 `DEPENDS_ON_NOT_DONE` 拒写并列出未完成前置（成环的 TASK 天然互相卡在此错误码上，不做传递闭包遍历、不单独检测环）。复用既有 `parseYaml`（实测已能解析 `depends-on: [A, B]` 内联流式数组），零新增解析代码。
- **项③**：仅收敛 `evaluatePassCondition` 的 `isEmpty` 失败分支——数组型 `actual` 保持数组类型并按 `ITEM_MAX=120` 逐项截断，`why` 只给条数并指向 `file` 字段已有的证据文件路径；不改 `equals`、`cmdAdvance` 或 `fail()`。
- **项④**：`review-record` 按既有 stage 映射一次性生成 canonical annotation、review-loop 与 `traceability.yml#reviews.<stage>` 投影，并经既有 `casWriteMulti` 统一写入；requirement 评审记录增加按 `CRLF → LF` 规范化后的 PRD SHA-256。`cmdNext` 在 `drafting` 下用 verdict/blockers 与该摘要判断“尚未回修→`write-requirement-prd`”或“PRD 已变化→`review-requirement`”。

### 1.3 事实基线（已核实，纪律 #4）

| # | 事实 | 位置 / 依据 |
|---|---|---|
| B-1 | `check-skill-matrix.mjs` 现有 3 项检查（active skill 恰一个 owns / owns 目标已注册或声明为 external / md 表格与 yml 一致），无任何引用点校验 | `check-skill-matrix.mjs:6-9,66-89` |
| B-2 | 该脚本把 `external` 解析成**全局 Set**（`externalSkills`），不记录声明它的 actor | `check-skill-matrix.mjs:36,46` |
| B-3 | actor 级 `external` 共 8 处声明、跨 4 个 actor（product-planning-agent / dev-agent / competitive-analyst-agent / system-orchestrator）；实测引用点：`brainstorming`(product-planning-agent)=1、`brainstorming`(competitive-analyst-agent)=1、`executing-plans`=2、`subagent-driven-development`=2、`test-driven-development`=2、`using-superpowers`=0、`writing-plans`=0、`verification-before-completion`=0 | 本 CR 需求期实跑扫描（skills/ + pipeline-templates/，排除 openwiki/old） |
| B-4 | `brainstorming` 被两个 actor 声明，但唯一引用点 `skills/competitive/report-to-planning-suggestion/SKILL.md` 归 `competitive-analyst-agent` owns（`agent-skill-matrix.yml:165`、`AGENT-SKILL-MATRIX.md:28`）——actor 级严格口径会把 `product-planning-agent.external.brainstorming` 判为零引用 | 实跑核对 |
| B-5 | 顶层 `external-skills:` 块（`agent-skill-matrix.yml:222-230`）条目缩进 2 空格，而 checker 的条目正则要求 6 空格（`check-skill-matrix.mjs:44`）——**从未被解析**；但 `AGENT-SKILL-MATRIX.md:57` 写明「外部方法论 Skill 只能出现在 `external` 或 `external-skills` 中」，把它当作合法声明位置 → 两份事实源 | 实跑核对 |
| B-6 | `cmdTaskDone`（`crctl.mjs:1298-1310`）只校验 status=developing、TASK 存在、非已 done 三项，**零依赖校验**；审计记录里 `before.from` 硬编码为 `'pending'` | 源码 |
| B-7 | `tasks/_index.yml` 的 `depends-on` 为内联流式数组（如 `depends-on: [CR-2026-001-TASK-01, CR-2026-001-TASK-02]`）；实测既有 `parseYaml` 能正确解析（含空数组 `[]`） | 需求期对 `parseYaml` 的实跑探针 + CR-2026-001/002/003 真实 `_index.yml` 样本 |
| B-8 | `crctl task allocate` 生成的条目只含 `id`/`slug`/`status` 三字段，不含 `depends-on`（`appendTaskEntry`，`crctl.mjs:1854`）——字段缺失是正常形态 | 源码 |
| B-9 | `evaluatePassCondition` 的 `equals` 与 `isEmpty` 两分支各把 `val` 同时写进 detail 的 `actual` 与 `why` | `crctl.mjs:551,554` |
| B-10 | `runGateChecks` 的 passCondition check 写入 `detail`，但没有顶层 `why`；`cmdAdvance` 仅汇总顶层 `check.why`，因此 blockers 原文未进入 `GATE_BLOCKED` message，只存在于序列化的 `gate.checks[].detail[].actual/.why` | `crctl.mjs:600-604,995-998` |
| B-11 | CR-2026-024 的长 blockers 实测证明 detail 中 `actual`/`why` 重复原文并显著放大输出；具体体积受 JSON 缩进、路径与文案影响，不宜作为跨环境百分比验收基线 | 需求期实跑核对 |
| B-12 | `cmdNext` 在 `drafting` 只检查 `prd.md` 是否存在，存在即返回 `review-requirement`，不读取 requirement annotation；而 requirement block 按既有流程保持 `drafting` | `crctl.mjs:2215-2218` + `review-requirement/SKILL.md:91-92` |
| B-13 | `check-skill-matrix.mjs` **无测试文件**：`skills/shared/crctl/scripts/test/` 下只有 `crctl.test.mjs` 与 `lint-prompts.test.mjs` | 目录实测 |
| B-14 | 测试约定：`node --test <file>`，零第三方依赖，仅用 `node:test`/`node:assert`，通过 `spawnSync` 黑盒调用被测脚本 | `ARCHITECTURE.md:104`、`crctl.test.mjs` 头注释 |
| B-15 | `gates.json` 的 `passCondition` 判据不写死在 crctl 里，运行时从 pipeline JSON 的 `reviewLoop.passCondition.allOf` 读取——本 CR 只改回显形态，不触判据来源 | `crctl.mjs:528-536` |
| B-16 | `review-record` 当前先写 canonical annotation，再调用 `bumpAttempt` 单独全量写 `review-loop.yml`，不触及 `traceability.yml`；任一后续步骤失败会留下已更新 annotation、未更新其他投影的半状态 | `crctl.mjs:1394-1423` |
| B-17 | `review-requirement`、`review-tech-design`、`review-code` 均以同一 `review-record --stage` 命令落盘，stage 已有 annotation 文件与 loop 显式映射 | `REVIEW_STAGE_FILES` / `REVIEW_STAGE_LOOPS` |
| B-18 | 既有 `casWriteMulti` 已提供“全校验→全写 temp→连续 rename”的多文件 CAS 语义，并明确接受连续 rename 间进程崩溃的极小窗口 | `crctl.mjs:684-712` |

### 1.4 决策点（本 PRD 拍板，SDD/实施期不得再次悬置）

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 项①规则粒度：全局名级 vs actor 级 | **全局名级**——同一名称在扫描范围内有 ≥1 引用点即通过，不要求引用点位于声明该 external 的 actor 自己 owns 的 skill 内 | actor 级需新引入「SKILL.md ↔ owns actor」归属映射（当前 checker 无此映射），且按 B-4 会立刻把 `product-planning-agent.external.brainstorming` 判红——而 `brainstorming` 恰是方案认定的「唯一四件套齐全样板」。收紧到 actor 级列为后续项 |
| D-2 | 顶层 `external-skills:` 块处置 | **保留原块**，块上方加注释标记其为纯文档参考、不被任何程序解析；同步修订 `AGENT-SKILL-MATRIX.md:57` 使 actor 级 `external` 成为唯一被 `check-skill-matrix` 解析的声明位置 | 该块从未被解析（B-5），但块内的 `systematic-debugging` 是 CR-2026-024 SDD §0 C-5 明确决定「仅存于顶层纯文档块，不动」的保留位——该名称在仓库内零引用点，整块删除会使其彻底消失，等同静默推翻 024 已拍板的决策。真正的「两份事实源」成因是 `AGENT-SKILL-MATRIX.md:57` 把装饰块写成了合法声明位置，只改这一行即可消除，无需删块 |
| D-3 | 与 CR-2026-024 的实施先后 | **本 CR 必须在 CR-2026-024 批次一合入之后实施** | B-3 实测三处零引用声明由 CR-2026-024 删除；本 CR 若先落，新规则上线即报 3 项红（外加 CR-2026-024 删 `test-driven-development` 引用后的第 4 项），把存量债务算到新守卫头上 |
| D-4 | 项②守卫的失败形态：硬失败 vs WARN | **硬失败拒写**，错误码 `DEPENDS_ON_NOT_DONE`，不提供绕过旗标 | crctl 既有风格一致为拒写（`TASK_ALREADY_DONE`/`ILLEGAL_LEDGER_STATE`/`CAS_CONFLICT` 皆 `fail`）；WARN 会重蹈 `depends-on`「声明了没人消费」的覆辙——本 CR 的存在理由正是把建议升级为强制 |
| D-5 | `depends-on` 字段缺失的语义 | **视为无依赖，放行** | B-8：`task allocate` 生成的条目本就不含该字段，缺失是正常形态而非异常 |
| D-6 | 环检测是否纳入本 CR | **不纳入** | FR-6 校验的是目标 TASK 的**直接** `depends-on`（一跳），不做传递闭包遍历；成环的 TASK（含自引用）里每个成员都在等另一个成员先 done，天然全部卡在 `DEPENDS_ON_NOT_DONE`，依赖顺序已被保证。环检测在一跳口径下是需要额外遍历依赖图才能做到的净新增代码，而非「同一次遍历的副产品」——原决策的前提不成立；提示"这是环"的可读性诉求改由 FR-6 错误文案的一句话覆盖 |
| D-7 | `ITEM_MAX=120` 是否做成可配置项 | **常量，不做配置面** | 包内无同类阈值配置先例；配置项本身要新增读取/校验/文档三处成本，而该值只影响可读性不影响正确性 |
| D-8 | 项①测试形态 | **新建 `check-skill-matrix.test.mjs`**，沿用 `node --test` + `spawnSync` 黑盒（B-14） | 该脚本此前无测试（B-13）；新增可执行规则却不留可执行验证，与本 CR 主题自相矛盾 |
| D-9 | 项③是否修改 `equals`、`cmdAdvance` 或 `fail()` | **不改**——只处理 `isEmpty` 数组失败 detail | B-10 证明 message 没有 blockers 原文；扩大到标量 equals 或错误框架没有收益 |
| D-10 | traceability 投影覆盖范围 | **按既有 stage 映射一次修好 requirement / tech-design / code**，不做 requirement 特判 | 三阶段共享同一 `review-record` 契约；共用一套投影函数比三个阶段分别补丁更小，也避免后续继续漂移 |
| D-11 | `review-record` 多文件一致性 | canonical annotation、`review-loop.yml` 与 `traceability.yml` 在完成全部解析/轮次检查后，使用同一个时间戳生成并交给既有 `casWriteMulti`；不另造事务机制 | 复用 B-18，遵循 tools 账本唯一写入点与失败不写原则 |
| D-12 | `cmdNext` 如何区分“尚未回修”与“已回修” | requirement annotation 记录评审时 `prd.md` 的 LF 规范化 SHA-256；`cmdNext` 比较当前摘要，不使用文件 mtime | 仅检查 block 会形成永久回修；mtime 会被 checkout/autocrlf 扰动，规范化摘要可重复验证且符合行尾纪律 |

## 2. 用户故事

- **US-1** 作为 tools 包维护者，当我在 `agent-skill-matrix.yml` 里声明一个 `external` 技能却没有在任何 SKILL.md 或 pipeline prompt 里真正引用它时，`check-skill-matrix.mjs` 立刻报错，而不是让这条死声明在仓库里躺过多个 CR 周期无人察觉。
- **US-2** 作为 tools 包维护者，我只需在唯一权威位置（actor 级 `external`）声明外部技能依赖；顶层 `external-skills` 仅是非权威历史参考，不参与程序校验，也不要求同步。
- **US-3** 作为 `dev-agent`（实现者），当我试图把一个前置 TASK 尚未完成的 TASK 标记为 done 时，`crctl task done` 拒绝写入并告诉我在等哪几个前置项，而不是静默接受、留下一个依赖顺序被违反却看不出来的账本。
- **US-4** 作为 `dev-agent`，当 `tasks/_index.yml` 的依赖关系意外成环时，环上的每个 TASK 都会因直接前置未 done 被 `crctl task done` 拒写（`DEPENDS_ON_NOT_DONE`），不会出现依赖顺序被违反的账本，命令也不会陷入遍历死循环。
- **US-5** 作为评审者/审批人，当门禁因 blockers 非空而拒绝推进时，`crctl gate` / `crctl advance` 的输出让我一眼看清「哪几条没过」，而不是把同一份长文本 blockers 重复三遍刷屏。
- **US-6** 作为调用 crctl 的上层程序（pipeline runtime / 桌面壳），`gate` 输出的 `actual` 字段仍是数组，我原有的 `.length` 类取值不会因这次改动而失效。
- **US-7** 作为任一评审阶段的执行者，我调用一次 `review-record` 后，annotation、review-loop 与 traceability 的 stage 投影保持一致，不需要模型手改 YAML 账本。
- **US-8** 作为 requirement-authoring 流程执行者，需求评审 block 后 `crctl next` 会先指向 PRD 回修；PRD 内容修订后，同一命令会转为指向重新评审，不会在两个节点间误路由或死循环。

## 3. 功能需求

### 项① · external 声明引用校验（D-2 落地）

- **FR-1（新增检查 4：external 引用点校验）**：`check-skill-matrix.mjs` 新增第 4 项检查——对每个从 actor 级 `external:` 解析出的技能名，在扫描范围内统计引用点数量；为 0 时记入 `errors`，错误文案须包含技能名、声明它的 actor（复数则全列）与「零引用点」判定语，退出码非 0。文件头部注释的「检查项」清单同步补第 4 条。
- **FR-2（引用点扫描口径）**：扫描范围 = `skills/` 与 `pipeline-templates/` 下的 `*.md` 与 `*.json` 文件（递归），**排除** `openwiki/`、`old/`、`node_modules/`、`.git/`；命中判定为文件文本包含该技能名（子串匹配即可，与 CR-2026-024 认定死声明时所用口径一致）。`agent-skill-matrix.yml` 与 `AGENT-SKILL-MATRIX.md` 自身不计入引用点（声明面不能自证）。
- **FR-3（解析器记录声明 actor + 行尾规范化）**：现有解析把 external 收进全局 `externalSkills` Set（B-2），需扩展为同时记录 `externalByActor`（actor → 技能名[]）以支撑 FR-1 的错误文案；检查 2 继续使用全局集合，行为不变。脚本现有文本读入点统一先执行 `\r\n → \n` 规范化，逐行解析使用 `split(/\r?\n/)`；匹配不到预期结构必须硬失败，不得静默降级为空集合。
- **FR-4（顶层 external-skills 块标记为纯文档 + 声明位置文档统一，D-2）**：`agent-skill-matrix.yml` 的顶层 `external-skills:` 块（L222-230）**保留不删**，块上方新增注释「纯文档参考，不被任何程序解析；唯一被 check-skill-matrix 解析的声明位置是 actor 级 external」；同步修订 `AGENT-SKILL-MATRIX.md:57`「外部方法论 Skill 只能出现在 `external` 或 `external-skills` 中」为「只能出现在 actor 级 `external` 中」。`skills/_index.yml:308-310` 现逐一点名 6 个外部技能，同步删除具体名称列举，改写为不点名的通用说明（指向 `agent-skill-matrix.yml` 的 actor 级 `external`），避免该注释随 external 声明增减而过时。
- **FR-5（新建 check-skill-matrix 测试，D-8）**：新建 `skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs`，`node --test` + `spawnSync` 黑盒，零第三方依赖。至少覆盖：① external 有引用点 → 通过；② external 零引用点 → 退出码非 0 且错误含技能名；③ 同一 external 被多 actor 声明且有引用点 → 通过（`brainstorming` 形态，B-4）；④ 同一 external 被多 actor 声明且零引用 → 错误同时列出全部声明 actor；⑤ CRLF 夹具与同内容 LF 夹具结果一致；⑥ 既有三项检查的回归各至少一条（缺归属 / 目标缺失 / md 漂移）。

### 项② · depends-on 依赖守卫（D-5 落地）

- **FR-6（task done 依赖守卫，一跳口径，D-6）**：`crctl task done <cr> --task <TASK-ID>` 在 `casWrite` 之前，解析 `tasks/_index.yml`，读取目标 TASK 的 `depends-on`（仅校验**直接**前置，不做传递闭包遍历）；若其中存在 `status != done` 的前置 TASK，以 `DEPENDS_ON_NOT_DONE` 硬失败拒写（D-4），错误 detail 须列出**未完成前置的 id 与当前 status**，message 末尾追加一句「若前置互相等待，检查 depends-on 是否成环」。校验发生在既有三项前置校验（status=developing / TASK 存在 / 非已 done）之后、写入之前。
- **FR-7（缺失与空值语义，D-5）**：`depends-on` 字段缺失或为空数组 `[]` 时视为无依赖，直接放行；`depends-on` 指向 `tasks/_index.yml` 中不存在的 TASK-ID 时以 `DEPENDS_ON_UNKNOWN` 失败（引用悬空本身即缺陷，不静默忽略）。
- **FR-8（复用既有解析器）**：依赖解析必须复用 crctl 既有的 `parseYaml`（B-7 实测已支持内联流式数组与空数组），**不得**新写 YAML 解析或正则提取；读入后先 `\r\n → \n` 规范化（纪律 #1）。
- **FR-9（用途表与文档同步）**：`skills/shared/crctl/SKILL.md` 的用途表补 `task done` 的依赖守卫说明与两个新错误码（`DEPENDS_ON_NOT_DONE` / `DEPENDS_ON_UNKNOWN`）；`README.md` 若含 `task done` 行为描述则同步。CR-2026-024 在 `implement-code/SKILL.md` 落的 prompt 层拓扑排序表述需补一句「依赖顺序由 `crctl task done` 机械强制」，使 prompt 层规则与账本守卫互为印证而非各说各话。
- **FR-10（crctl 测试向量）**：`crctl.test.mjs` 追加向量覆盖：① 前置未 done → `DEPENDS_ON_NOT_DONE` 且退出非 0、`_index.yml` 未被修改；② 前置全 done → 正常写入 `status: done` 与 `done-at`；③ `depends-on` 缺失/空数组 → 放行；④ 指向不存在 TASK → `DEPENDS_ON_UNKNOWN`；⑤ `depends-on` 写成带引号形态（如 `["CR-2026-XXX-TASK-NN"]`，仓内实测 16 处存在此写法）→ 与不带引号等价放行/拒写（钉住 `parseYaml` 的 unquote 路径）。

### 项③ · gate/advance blockers 回显收敛

- **FR-11（`isEmpty` 数组失败逐项截断）**：在 `evaluatePassCondition` 作用域内引入常量 `ITEM_MAX = 120` 与纯函数 `briefArray(v)`；仅当 `isEmpty` 失败且实际值为数组时，`actual` 保持数组类型并逐项截断，字符串超长时追加 `…(+N字)` 标记，非字符串数组项维持原值。
- **FR-12（`isEmpty` why 收敛）**：仅修改 `isEmpty` 失败分支：数组型实际值的 `why` 写为 `期望 <path> 为空，实际 N 条（详见 <doc.path>）`，不得包含任一完整原文。`equals` 分支、`runGateChecks` 顶层 check、`cmdAdvance` 与 `fail()` 均保持现状。
- **FR-13（`actual` 类型契约不变）**：截断后 `actual` 仍为数组，调用方既有的 `.length`/索引取值不受影响（NFR-3）；全量值仍只存在于 `file` 指向的 canonical 证据文件。
- **FR-14（取舍写进注释）**：改动处须有注释写明——本收敛**只封单条长度、不封条数**，条目数极多时输出仍会线性增长；以及全量原文来源是 `file` 字段指向的 `review-annotations/{stage}.yml`。
- **FR-15（crctl 测试向量）**：`crctl.test.mjs` 追加向量：构造含超长 blockers 的评审证据后跑 `gate --for <评审通过态>` 与失败的 `advance`，断言 ① 退出码非 0；② `checks[].detail[].actual` 仍是数组且每项长度 ≤ `ITEM_MAX + 后缀长度`；③ detail 的 `why` 含条数与 `详见` 指针且不含完整原文；④ `GATE_BLOCKED` message 维持现状且不含 blocker 原文；⑤ 标量 `equals` 失败输出与改动前一致。

### 项④ · review-record 投影一致性与 cmdNext 回修路由

- **FR-16（三阶段 traceability 投影）**：`crctl review-record` 按既有 stage 映射统一更新 `traceability.yml#reviews.<stage>`：`requirement → reviews.requirement`、`tech-design → reviews.tech-design`、`code → reviews.code`。投影至少包含 reviewer、verdict、reviewed-at、blocker-count、annotation 路径、repair-target 及 review-loop 的 current-attempt/max-attempts/attempts；repair-target 分别为 `write-requirement-prd`、`write-tech-design`、`implement-code`。不为三个 stage 分别实现独立写入流程。
- **FR-17（三账本一致写入）**：`review-record` 在任何受控文件落盘前完成 payload schema、stage、前置状态、轮次上限、traceability 结构与 CR-ID 一致性检查；一次生成 `recordedAt`。带 `--bump-attempt` 时，据此构造 canonical annotation、`review-loop.yml` 与 traceability 投影的新文本，再复用既有 `casWriteMulti` 统一写入；未带该旗标时只对 annotation 与 traceability 做多文件 CAS，`review-loop.yml` 保持不变并将其当前轮次投影到 traceability。任一文件前置校验或 CAS 失败时本次涉及的受控文件均不得变化；保留 B-18 已接受的连续 rename 间进程崩溃窗口，不另造事务/恢复系统。
- **FR-18（traceability 创建与定点更新）**：`traceability.yml` 不存在时，`review-record` 可创建最小 `cr-id + reviews` 骨架；已存在时只定点新增或替换目标 `reviews.<stage>`，必须保留其他 stage、tests 及未知扩展段。CR-ID 不匹配、目标 stage 重复或结构无法唯一定位时硬失败，不得静默重写整份账本。行级处理前执行 `\r\n → \n` 规范化，解析/定位失败不得降级。
- **FR-19（requirement 被评审内容摘要）**：`review-record --stage requirement` 在 canonical annotation 中写入 `subject-file: change-requests/<CR-ID>/prd.md` 与 `subject-sha256`；摘要对 UTF-8 文本先执行 `\r\n → \n` 再 SHA-256，时间戳或文件 mtime 不参与判定。tech-design/code 本次不新增摘要消费逻辑。
- **FR-20（cmdNext drafting 路由）**：`cmdNext` 在 `drafting` 按以下优先级决定下一步：① `prd.md` 缺失 → `write-requirement-prd`；② requirement annotation 为 block 或 blockers 非空，且其 `subject-sha256` 等于当前 PRD 规范化摘要 → `write-requirement-prd`，why 含 blocker 条数与 annotation 路径；③同一失败证据的摘要与当前 PRD 不同 → `review-requirement`（说明 PRD 已变化、需刷新证据）；④无失败证据 → 保持现有 `review-requirement`。不得仅凭旧 block 永久回修，也不得使用 mtime。缺少 `subject-sha256` 的旧证据保持改动前兼容行为（PRD 存在即 `review-requirement`），不在本 CR 做历史迁移。
- **FR-21（项④测试向量）**：`crctl.test.mjs` 至少覆盖：① requirement/tech-design/code 三个 stage 均生成正确 `reviews.<stage>` 投影；② `--bump-attempt` 后三账本 attempt/verdict/blocker-count/时间一致，第二轮替换当前投影并保留 attempts 历史；③ trace 缺失时创建、已有其他段时保留；④ trace 结构错误或注入 CAS 失败时三账本内容均不变且 payload 保留；⑤ `drafting + 同摘要 block → write-requirement-prd`；⑥修改 PRD 实质内容后 → `review-requirement`；⑦仅 LF/CRLF 差异不视为已回修；⑧无摘要旧证据维持兼容行为。

### 收尾

- **FR-22（验证关卡）**：`check-skill-matrix.mjs` + `check-agents-contract.mjs` + `lint-prompts.mjs --mode enforce` 全绿；`node --test` 跑通 `crctl.test.mjs`、`lint-prompts.test.mjs`、新增的 `check-skill-matrix.test.mjs` 三个测试文件全部用例。
- **FR-23（溯源标注）**：commit message 注明来源为方案 v2.6 §7（D-2/D-5）、CR-2026-024 SDD 评审实测与 CR-2026-025 需求评审发现的 Tools 流程缺口，并含 CR-2026-025 编号；全部改动不引入本机绝对路径。
- **FR-24（ARCHITECTURE.md 登记）**：若本 CR 改动落在 `ARCHITECTURE.md` §3/§5/§6 覆盖面（crctl 命令面语义扩展、守卫面新增），按 §8 维护规则登记本 CR；测试文件新增同步 §8 代码地图与 `dir-graph.yaml`。

## 4. 非功能需求

- **NFR-1（零新增第三方依赖）**：四项改动全部使用 `node:` 内置模块，测试仅用 `node:test`/`node:assert`（B-14）。
- **NFR-2（状态机与既有核心 schema 稳定）**：不新增/修改 CR 状态与转换，不改 `tasks/_index.yml` 或 `gates.json` schema。项④只落实既有 traceability review 投影契约，并在 requirement annotation 增加两个向后兼容的标量字段 `subject-file`/`subject-sha256`；不新增状态、转换、CLI 子命令或迁移命令。
- **NFR-3（gate 输出向后兼容）**：`actual` 字段类型契约不变（数组仍是数组）；新增的截断标记只出现在字符串内部，不改变 JSON 结构层级或字段名。
- **NFR-4（判据来源不变）**：项③不触碰 `passCondition` 的判据解析路径（B-15：判据仍运行时读自 pipeline JSON 的 `reviewLoop.passCondition.allOf`），只改结果的呈现。
- **NFR-5（实施顺序依赖，D-3）**：本 CR 的项①实施与验证必须在 CR-2026-024 批次一合入 `custom/main` 之后进行；若 CR-2026-024 未合入，FR-22 的 `check-skill-matrix` 全绿要求无法满足（B-3 的 3~4 项零引用声明会报红）。SDD 需据此排定实施顺序。
- **NFR-6（行尾纪律，纪律 #1）**：项① checker 文本、项② `_index.yml`、项④ PRD 摘要与 traceability 文本读入后均先 `\r\n → \n` 规范化再解析/摘要；逐行解析使用 `split(/\r?\n/)`，解析或跨行定位失败硬失败，不静默降级。
- **NFR-7（可移植性）**：改动与测试不含本机绝对路径；测试用临时目录（`mkdtempSync`）构造夹具，与既有 `crctl.test.mjs` 风格一致。
- **NFR-8（不引入通用解析框架）**：项②复用 `parseYaml`（FR-8）；项①沿用 `check-skill-matrix.mjs` 既有行级解析风格；项④只增加 traceability `reviews.<stage>` 的受控定点编辑函数，不引入 YAML 库或通用序列化器。
- **NFR-9（基线协调）**：tools 仓工作区若存在与本 CR 无关的未提交修改（已知存在 `.qoder/repowiki/` 等删除态文件），提交时只 add 本 CR 文件清单，严禁 `git add -A`。
- **NFR-10（投影事实源）**：`review-annotations/<stage>.yml` 与 `review-loop.yml` 是评审结论和轮次的 canonical 证据，`traceability.yml#reviews.<stage>` 是由 `review-record` 同步生成的可追溯投影；模型不得直接手改三者补齐一致性。

## 5. 验收标准

- **AC-1**（FR-1/FR-3）：在 `agent-skill-matrix.yml` 某 actor 的 `external` 下插入一个仓库内零引用的技能名后运行 `check-skill-matrix.mjs`，退出码非 0 且 stderr 含该技能名与声明它的 actor；移除后恢复通过。
- **AC-2**（FR-2）：只在 `openwiki/` 下出现的技能名**不**计为引用点（仍判红）；只在 `pipeline-templates/*.json` 的 prompt 中出现的技能名**计为**引用点（判绿）。
- **AC-3**（FR-1）：`check-skill-matrix.mjs` 文件头注释的「检查项」清单含第 4 条引用点校验描述。
- **AC-4**（FR-4）：`agent-skill-matrix.yml` 顶层 `external-skills:` 块仍存在，块上方含「纯文档参考，不被解析」的注释；`AGENT-SKILL-MATRIX.md` 中该表述已改为「actor 级 `external`」且不再提 `external-skills` 是合法声明位置；`skills/_index.yml:308-310` 的外部方法论技能名枚举已删除，改为不点名的通用说明。
- **AC-5**（FR-4/FR-22）：CR-2026-024 批次一合入后的真实仓库上运行 `check-skill-matrix.mjs` 通过——即 `brainstorming`×2、`executing-plans`、`subagent-driven-development` 四项声明全部有引用点（B-3 预期终态）。
- **AC-6**（FR-3/FR-5/D-8）：`skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs` 存在；`node --test` 跑通且含 FR-5 列出的全部向量，CRLF/LF 夹具结果一致；无第三方依赖 import。
- **AC-7**（FR-6/FR-10）：前置 TASK 为 `pending` 时执行 `crctl task done` → 退出码非 0、错误码 `DEPENDS_ON_NOT_DONE`、detail 列出该前置 id 与 status，且 `tasks/_index.yml` 内容 sha256 与执行前一致（确认未写入）。
- **AC-8**（FR-6）：前置 TASK 全部 `done` 时执行 `crctl task done` → 正常写入 `status: done` 与 `done-at`，行为与改动前一致。
- **AC-9**（FR-7）：`depends-on` 缺失与 `depends-on: []` 两种形态均放行；`depends-on` 指向不存在的 TASK-ID 时报 `DEPENDS_ON_UNKNOWN`。
- **AC-10**（FR-8/NFR-6/NFR-8）：项②的依赖解析不新增 YAML 提取正则或解析器，直接调用既有 `parseYaml`；构造 A→B→A 与自引用 A→A 两种夹具，均在有限时间内返回且报 `DEPENDS_ON_NOT_DONE`（一跳口径下环上每个成员的直接前置均非 done，不产生死循环）。
- **AC-11**（FR-9）：`skills/shared/crctl/SKILL.md` 用途表含 `task done` 依赖守卫与两个新错误码；`implement-code/SKILL.md` 的拓扑排序表述含「由 `crctl task done` 机械强制」一句。
- **AC-12**（FR-11/FR-12/FR-13）：对含 7 条各约 500 字 blockers 的证据跑 `crctl gate --for <评审通过态>`——`checks[].detail[].actual` 仍为数组、每项字符串长度 ≤ `120 + 后缀长度`；`why` 形如 `期望 blockers 为空，实际 7 条（详见 …/sdd.yml）`，两者均不含任一完整 blocker 原文；不使用输出体积百分比作为验收条件。
- **AC-13**（FR-12/FR-15）：同一证据执行失败的 `crctl advance` 时，`GATE_BLOCKED` message 维持现有摘要行为且不含 blocker 原文；序列化的 gate detail 只包含截断后的数组和条数指针；标量 `equals` 失败快照与改动前一致。
- **AC-14**（FR-14）：改动处注释含「只封单条长度、不封条数」与全量原文来源的说明。
- **AC-15**（FR-15/FR-10）：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿，含项②五类与项③五类新增断言。
- **AC-16**（FR-22）：三件套全绿 + 三个测试文件全部用例通过。
- **AC-17**（FR-23/FR-24）：commit message 含 CR-2026-025 与来源溯源；`grep -r "C:\\\\Users"` 在本 CR 改动中零命中；`ARCHITECTURE.md` §8 按需登记，新增测试文件已登记代码地图与 `dir-graph.yaml`。
- **AC-18**（NFR-5/D-3）：SDD 与实施记录显式声明本 CR 在 CR-2026-024 批次一之后实施；AC-5 的验证在该前提下执行。
- **AC-19**（FR-16/FR-18）：分别以 requirement、tech-design、code payload 执行 `review-record`，对应的 `reviews.requirement`、`reviews.tech-design`、`reviews.code` 投影字段、annotation 路径与 repair-target 均正确；更新一个 stage 时其他 stage、tests 与未知扩展段字节内容保持不变。
- **AC-20**（FR-17）：`review-record --bump-attempt` 成功后 annotation、review-loop 与 traceability 中的时间、attempt、verdict、blocker-count 一致；第二轮记录的 current-attempt 为 2 且 trace attempts 同时保留第 1、2 轮结果。任一前置校验/CAS 注入失败时三文件 sha256 均与执行前一致，临时 payload 保留。
- **AC-21**（FR-18）：traceability 缺失时自动创建最小合法骨架；CR-ID 不匹配、重复 stage 或无法唯一定位时结构化失败且不改任何受控文件，不产生静默空投影。
- **AC-22**（FR-19/FR-20）：requirement block 记录生成后立即运行 `crctl next` 返回 `write-requirement-prd`；实际修改 PRD 内容后返回 `review-requirement`；只在 LF/CRLF 间转换时仍返回 `write-requirement-prd`；旧 annotation 缺少摘要时保持“PRD 存在→review-requirement”的兼容行为。
- **AC-23**（FR-21）：`crctl.test.mjs` 包含 FR-21 全部八类向量并通过，且未引入文件 mtime 判定、历史迁移命令或第三方 YAML 库。

## 6. 成功指标

- `external` 死声明的复发被机械阻断：新增一条零引用 external 声明会在 pre-commit/CI 阶段直接报红，不再依赖人工评审发现（CR-2026-024 是靠人工逐条实测才挖出三条）。
- `external` 权威声明位置收敛为一处：actor 级 `external` 是唯一权威且唯一被程序解析的声明；顶层 `external-skills` 明确为非权威历史参考，不参与校验且无同步要求。
- `depends-on` 从「声明了没人消费」升级为账本级强制：任何**声明了 `depends-on`** 的 TASK，违反依赖顺序执行 `task done` 都被拒写并留下可读的未完成前置清单（`crctl task allocate` 生成的条目不含该字段，按 D-5 视为无依赖，不在此列）；`depends-on` 的四层链条（声明→写入→汇总→校验）终于接上第五层（驱动行为）。
- 门禁输出可读性：真实 blockers 场景下 `gate`/`advance` detail 不再重复完整长文本，仍保留失败条数和 canonical 文件指针；不以跨环境不稳定的体积百分比作为指标。
- 三阶段评审记录由一个 `review-record` 写入点同步形成 annotation、轮次与 traceability 投影；任一正常执行后不再出现 stage 投影落后于 canonical 证据的情况。
- requirement block 后 `crctl next` 能稳定形成“回修→内容变化→重审”的闭环，不把未回修 PRD送去重审，也不被旧 block 永久困在回修节点。
- 四项均有可执行测试兜底，`check-skill-matrix.mjs` 从零测试变为有测试。

## 7. 范围排除

**本 CR 包含**：项①②③④的代码改动、各自测试向量、直接相关的用途表/文档同步；项④明确包含 `review-record` 三阶段投影和 `cmdNext` requirement 回修/重审路由。

**本 CR 不包含**：
- **actor 级 external 引用校验的收紧**（要求引用点必须位于声明该 external 的 actor 自己 owns 的 skill 内）——需新引入 SKILL.md↔owns 归属映射，且会牵出 `product-planning-agent.external.brainstorming` 的合法性判断（D-1、B-4），自成独立议题。
- **`can-call` / `forbidden` 的引用校验**——本 CR 只处理 `external`；`forbidden` 已由 CR-2026-024 明确为声明性边界、无调用级拦截，不在此改变其性质。
- **`lint-prompts` 新增「未注册技能名」规则**——CR-2026-024 评审期确认 R1~R9 无此规则，但那属 prompt 正文治理面，与本 CR 的矩阵声明面是两件事。
- **`cmdNext` 其他状态的路由或文案统一重构**——本 CR 只修 FR-20 定义的 `drafting` requirement 失败证据回修/重审路由；tech-design/code 既有路由及其他状态输出保持不变。
- **`ITEM_MAX` 配置化**（D-7）、**按条数封顶的二级截断**——只封单条长度是本 CR 的显式取舍（FR-15），条数封顶会让 `actual` 不再完整反映失败集合，属另一个取舍。
- **`capabilities` 真闭环 Level C**（CR-2026-024 D-3 已列）、**requirement/tech-design 阶段 suggestions 分流**（CR-2026-024 D-4 已列）——与本 CR 无关，继续留在各自后续项。
- **状态机 / `gates.json` / `rules.json` 本体改动**——本 CR 无此需求（NFR-2）；项④只修改最小 runner 的证据读取与下一节点建议，不新增转换。
- **通用 YAML AST/序列化器、跨进程事务日志或崩溃恢复器**——项④复用既有定点编辑与 `casWriteMulti`，接受 B-18 已声明的极小崩溃窗口。
- **tech-design/code 被评审对象摘要与 stale 路由**——本 CR 的摘要只服务 FR-20 的 requirement `drafting` 缺口；另外两阶段不新增摘要消费逻辑。
- **环检测（依赖成环时的显式 `DEPENDS_ON_CYCLE` 判定）**（D-6）——本 CR 只做一跳直接前置校验，成环 TASK 天然被 `DEPENDS_ON_NOT_DONE` 挡住，不做传递闭包遍历。
- **`external` 引用的有效性校验（被引技能在目标运行时是否真的可用）**——FR-2 采子串匹配，只能证明"仓库文本中提到过"，不能证明"引用在目标运行时可解析"；`test-driven-development` 当前判绿正是靠 `implement-code/SKILL.md`/pipeline prompt 里对未安装技能的引用文本本身（即 §1.1 自陈的失效模式本体），CR-2026-024 删除这两处引用后才归零。该上限本 CR 不解，留给运行时按需自行校验。
- **CR-2026-024 自身的任何改动面**——本 CR 与 CR-2026-024 均改动 `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`（024 改 actor 级 external 存量清理，本 CR 改顶层块注释与声明位置表述），文件面有重叠但改动区域不同、无冲突；存在实施顺序依赖（D-3/NFR-5）。

## 8. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|------|------|------|------|
| 2026-08-08 | v0.1.0 | Ray | 初始草稿（D-2 + D-5 + gate 回显收敛三项合并交付；事实基线 15 条经实跑核对，决策点 D-1~D-9 拍板） |
| 2026-08-08 | v0.2.0 | Ray | 需求评审 attempt-1 回修（4 blocker）：B-3 actor 数订正为 4；D-2 改为保留顶层 `external-skills:` 块（不删，避免与 CR-2026-024 SDD §0 C-5 冲突），FR-4 改为加注释 + 同步收敛 `skills/_index.yml` 技能名枚举；D-6/FR-8/AC-10（环检测）整项撤销，改为一跳直接前置校验天然挡环，FR-6~FR-18 顺延重编号；§7 订正"两 CR 文件面不重叠"为"文件重叠但区域不同"，并补环检测、external 引用有效性两条排除项；§6 成功指标限定为"声明了 depends-on 的 TASK"；FR-10 测试向量补带引号 TASK-ID 形态 |
| 2026-08-09 | v0.3.0 | OldBoy405 | 需求评审 attempt-2 回修（3 blocker + 用户确认扩围）：订正项③事实基线，只修改 `isEmpty` detail 并删除不可复算的体积百分比；明确 actor 级 `external` 为唯一权威/程序解析声明，顶层块仅作非权威参考；项①补 CRLF 规范化和回归夹具；新增项④，以共用 stage 映射同步 requirement/tech-design/code trace 投影，并以 LF 规范化 PRD 摘要修复 `cmdNext` 的 requirement 回修/重审路由。 |
