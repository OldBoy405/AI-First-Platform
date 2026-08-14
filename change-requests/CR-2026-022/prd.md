---
id: CR-2026-022-prd
type: PRD
cr-ref: CR-2026-022
title: 治理工具链 — tools 包 prompt 审查修复（97 条发现：批 2.5 crctl 核心缺陷修复 + checkpoint-add 承诺兑现 + approve 驳回回退 + lint R6/R7 与豁免修复 + 冗余收敛）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-06T07:10:00+08:00"
updated: "2026-08-06T07:10:00+08:00"
---

# PRD — tools 包 prompt 审查修复（97 条发现全量落地）

## 1. 概述

### 1.1 问题陈述

tools 包 prompt 审查（`docs/analysis/prompt-audit-report-2026-08-05.md`，97 条发现 = 原稿 75 + CR-2026-022 注册实录补 4 + 7 条流水线执行走查补 18）揭示的问题已从"文档写错了"升级为**crctl 代码本身存在没被兑现的承诺**：

- **命令串畸形与接口漂移**：12 处 `crctl advance` 坏形态命令串（全角分隔符、旗标用反引号包裹）、`inbox-emit` 函数式调用与缺必填字段，AI 照抄必失败、通知链实际断裂。
- **crctl 本体缺陷**（7 条流水线逐节点模拟执行走查坐实）：`push-progress` 从未真正调用它承诺的 `crctl checkpoint-add`（且 `LEGAL` 状态白名单覆盖不到 push-progress 实际被调用的阶段）；`cmdApprove` 的驳回分支从不执行状态机已声明的 `{stage}:reject -> write-{stage}` 回退转换，四个人工审批门禁驳回后无路可退；`gates.json` 的 `reviewLoops.review-planning-report` 是从未被任何门禁调用的死配置；`cr-init` 硬编码 `summary/source/target-version` 无旗标写口，逼出违纪手写 cr.md。
- **lint 防线自身有洞**：`lint-prompts` 不校验命令参数形态（R6/R7 缺位）；且 `<!-- lint-prompts:ignore -->` 豁免判断对整段 `node.prompt` 生效，一条无关豁免注释可连带放行 R5 违规。
- **死内容与大段样板重复**：`cr-status-set` 等废弃残留、8 类死引用/僵尸产物、多组逐字重复的样板（改一处要改 N 处）。

### 1.2 解决方案摘要

按审查报告批次结构全量实施（批 1 → 2 → 2.5 → 3 → 3.5 → 4 → 收尾）：

1. **批 1/2**：零风险机械修正与死内容清理（纯文本）。
2. **批 2.5**（新，最高优先级）：crctl 核心能力补齐与缺陷修复，全部触发 ARCHITECTURE.md §8 评审门槛，合并成一份技术设计一次评审通过。
3. **批 3**：功能正确性修复（接口/枚举/结构约定对齐），功能断裂者优先。
4. **批 3.5**：lint 护栏先行（R6/R7 + 豁免范围 bug 修复），必须在批 4 之前落地。
5. **批 4**：冗余收敛，按「先对齐、必要才抽」原则；抽 push-progress 样板必须以批 2.5 修对为前提。
6. **收尾**：三台账同步 + 自检 + `crctl.test.mjs` 全量回归 + 端到端验收。

**范围口径（本 CR 的既定决策）**：审查报告「CR 必要性判据」一节建议批 1/2/3.5/4 可现场直改、不必走 CR；**本 CR 决定不采纳该分流建议——97 条发现全部在本 CR 内落地**，以获得统一的状态机追踪、评审记录与回写基线。报告 §三 的批次时序与前置约束（批 3.5 先于批 4、批 2.5 先于批 4 样板抽取等）仍全部遵守。

### 1.3 报告遗留决策点（本 PRD 拍板）

报告中有三处"需要决策"的开放项，本 PRD 直接给出决定，SDD/实施期不得再次悬置：

| # | 决策点 | 本 PRD 决定 | 理由 |
|---|---|---|---|
| D-1 | 需求阶段状态机是否新增 `requirement-reviewing:reject -> drafting` 转换 | **新增**该转换（`dir-graph.yaml` 状态机声明 + crctl approve decline 分支联动） | 与 tech-design/code 阶段对齐；"需求驳回=CR 死刑"过于刚性，打回重写 PRD 是常态诉求；`cr-review-record:reject → rejected` 仍保留为终止通道 |
| D-2 | review-planning-report 的 attempts 记账：接入 crctl 还是删死配置 | **删除 `gates.json` 死配置**，如实描述当前自行落盘机制（`docs/product-planning/review-annotations/{report-id}.yml`）；同步删除 `product-planning.pipeline.json:109` 的"必须持久化"失实承诺 | product-planning 全程主分支运行、无 CR 上下文，为它新开一条 crctl 持久化子命令收益不成比例 |
| D-3 | competitive-radar/market-to-plan 镜像节点 `onFail` 相反（skip vs abort） | **统一为 abort**；同时删除 competitive-radar 下游节点对 node-3.md 的写死读取依赖检查（abort 后不会读到空文件） | skip 分支读空文件的降级展示是额外复杂度，abort 语义与 human_approval 前置失败处理一致 |

另两处报告"建议评估"项，本 PRD 一并定案：**`write-insight-brief` 合并进 `extract-market-insight` 附加区块后下线**（唯一硬性增量 ≤800 字约束与 `raw→briefed` 状态推进并入）；**`run-competitive-analysis` Step4 摘要并入 `write-planning-report`「市场与竞品信号」章节后下线**该封装层。

### 1.4 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| 12 处 `crctl advance` 坏形态命令串（8 个文件），权威旗标为 `--to <s> --trigger <t> [--expect <cur>] [--embedded]`，`--expect` 单值比较 | 审查报告 2.1-A；`crctl.mjs` `cmdAdvance`（`flags.expect !== current`） |
| `cmdCheckpointAdd` `LEGAL` 白名单仅 `['developing','code-reviewing','code-approved','merging','writing-back']`，不含 push-progress 实际被调用的 `drafting`/`task-breakdown` 等阶段 | `crctl.mjs:1578-1579` |
| `push-progress/SKILL.md` Step 2-3 全程只调 `runGit`，无一行 `checkpoint-add`；三条流水线节点 prompt 却写「经 crctl checkpoint-add 更新 _backlog」 | `push-progress/SKILL.md:47-81`；三条 pipeline JSON |
| `cmdApprove` 非 TTY-yes 分支只 `fail('APPROVAL_DECLINED')`，从不调用已声明的 `{stage}:reject -> write-{stage}` 回退转换；需求阶段状态机完全没有驳回转换 | `crctl.mjs:1072-1077`；`dir-graph.yaml:212-220` |
| `cmdCrInit` 硬编码 `summary:""`/`source:manual`/`target-version:tbd`；`BACKLOG_SET_FIELDS` 白名单仅 `prd-path\|sdd-path` | `crctl.mjs:1711-1751, 1564` |
| `resolveTemplateCr` 靠「分支探测→subject 正则兜底」反向解析 CR 号；注册场景在 master 分支必然落空（本 CR 注册实录首次提交即 BAD_ARGS） | `crctl.mjs:1953-1961`；`docs/analysis/CR-2026-022-注册流程复盘.md` |
| `architecture-design.pipeline.json` 5 个节点 UUID 前缀 `0014-*` 与 `resume-cr.pipeline.json` 撞号，且 `repairNodeId` 是 node-1 自引用 | `architecture-design.pipeline.json:36,45,51,74,82,91` |
| `lint-prompts` 豁免判断对整段 `node.prompt` 生效，`product-planning.pipeline.json:109` 一条无关豁免注释连带放行 R5 违规 | `lint-prompts.mjs:86-110` |
| `gates.json:100` `reviewLoops.review-planning-report` 从未被 `evaluatePassCondition`/`readAttempts` 引用（死配置） | `gates.json`；`crctl.mjs` |
| `cmdNext` 的 `writing-back` 分支检查开发期工作稿 `change-requests/{cr}/traceability.yml` 而非 writeback 产物 `specs/{spec_id}/traceability.yml`，误判"可归档" | `crctl.mjs` `cmdNext`（约 :2220） |

## 2. 用户故事

- **US-1** 作为执行任意 SKILL 的 agent，我照抄正文里的 `crctl advance` 命令串即可成功执行，不再撞上全角字符/反引号旗标导致的参数解析失败。
- **US-2** 作为推送进度的维护者，我照 `push-progress` SKILL 逐仓调用 `crctl checkpoint-add` 即完成记账，且在任何存在 push-progress 节点的非终态（含 `drafting`/`task-breakdown`）都不再炸 `ILLEGAL_LEDGER_STATE`。
- **US-3** 作为审批人，我在终端回答非 `yes` 时 CR 自动回退到前一阶段并提示重跑哪个 write skill，不再无路可退；需求阶段驳回可回到 `drafting` 重写 PRD。
- **US-4** 作为注册新 CR 的 agent，我用 `cr-init --summary --source [--target-version]` 一次原子写齐字段，用 `git commit --template register --cr <cr-id>` 直传已知 CR 号，不再违纪手写 cr.md、不再因 subject 缺编号首次提交失败。
- **US-5** 作为发起 inbox 通知的 agent，我按对齐后的 `inbox-emit` 接口（`cr-id`/`event`/`to`/`payload`）发送 `feedback-writeback-done` 与 `owner-handover` 事件，通知链真实可达。
- **US-6** 作为合并 feature 分支的执行者，merge 前有本地/远端 HEAD 一致性校验，不会把"缺最后一次提交"的远端分支合进 trunk。
- **US-7** 作为治理工具链维护者，`lint-prompts` 的 R6/R7 能拦住命令参数形态漂移，豁免注释不再连带放行无关违规行，批 4 大改动引入的新漂移不会无人发现。
- **US-8** 作为查阅 CR 进度的维护者，`cr-show`/`crctl next` 对 writeback 期状态给出正确建议，不再误判"可归档"。
- **US-9** 作为修改任一 prompt 的维护者，改完一处不再需要同步改 N 处逐字重复的样板；共享片段有 lint 引用一致性检查兜底。
- **US-10** 作为阅读 `agents/_index.yml`/`skills/_index.yml` 的维护者，台账不再有死引用、僵尸产物与长期挂空的 pending 能力。

## 3. 功能需求

### 批 1 —— 零风险机械修正

- **FR-1（命令串畸形 12 处）**：按审查报告 2.1-A 目标形态修正 8 个文件的 12 处 `crctl advance` 命令串；其中 `review-requirement/SKILL.md:91` **省略 `--expect`**（需求阶段存在 `drafting→requirement-reviewing` 与自环两条合法转换，`--expect` 单值写死会误拒合法自环）。
- **FR-2（frontmatter 豁免注释外移）**：`review-code`/`requirement-register:17`/`implement-code:77` 共 3 处 `<!-- lint-prompts:ignore -->` 移出 YAML frontmatter / 删孤立行。
- **FR-3（死引用与措辞订正）**：删 `pipeline-templates/_index.yml:118` 的 `tools/old/` 死引用行；修 `agents/knowledge-agent.md:39` validate-doc 死路径为 `tools/skills/shared/validate-doc/SKILL.md`；requirement-register「三件事→四件事」编号补齐、merge-feature-branch「两阶段→四阶段」措辞澄清、spec-dashboard 状态分布表补齐六个漏列状态。

### 批 2 —— 死内容清理

- **FR-4（cr-status-set 整体下线）**：删除 `skills/cr/cr-status-set/SKILL.md` 与 `skills/_index.yml:287` 条目；`skills/_index.yml:281` cr-review-record brief 改「经 crctl advance 推进」。
- **FR-5（validate-doc 订正）**：删除维度 2「gate 合规性」（无排期背书不留）；移除 writeback-* 写入后「自动调用本 Skill」的失实声明。
- **FR-6（focus-briefing 反向修）**：竞品报告过滤改为由 `write-competitive-report` 写索引时补 `status: new`、消费后翻转为 `seen`（不直接去掉过滤）；pipeline 注册表数据源先向运行时确认真实路径，确认不了即整体删除该可选数据源。
- **FR-7（降级路径与 pending 清空）**：`report-to-planning-suggestion` 补「目标运行时未提供 brainstorming 时直接委托 planning-draft」降级路径（不移除 external delegate）；`agents/_index.yml` 5 处 `pending` 能力清空为 `[]`（保留键不删）。
- **FR-8（record-adr 下线）**：确认 `constraints/adrs.yml` 无读者后，连 `record-adr` skill 一并删除。

### 批 2.5 —— crctl 核心能力补齐与缺陷修复（一次设计评审过 ARCHITECTURE.md §8）

- **FR-9（cr-init 字段写口，2.1-F）**：`cr-init` 补 `--summary <s> --source <s> [--target-version <v>]` 三个可选旗标（缺省值与现硬编码同义，向后兼容），注册时一次原子写齐；删除 `requirement-register/SKILL.md:28` 的 `cr_id` 僵尸参数与其格式/占用校验。
- **FR-10（--template 显式 CR 号，2.1-F）**：`resolveTemplateCr` 补显式 `--cr <cr-id>` 旗标，优先取旗标值、跳过「分支探测→subject 正则」反向解析；原路径保留为兜底，不破坏存量调用。
- **FR-11（checkpoint-add 承诺兑现，2.1-G，一处改动惠及 3 条流水线）**：① `cmdCheckpointAdd` `LEGAL` 白名单扩至全部非终态：`drafting/requirement-reviewing/requirement-approved/tech-designing/tech-design-review-pending/tech-design-reviewed/task-breakdown/developing/code-reviewing/code-approved/merging/writing-back`（全量列出，不用枚举省略式）；② `push-progress/SKILL.md` Step 3 改为对每个 active repo 循环 `git rev-parse HEAD` + `crctl checkpoint-add --repo <r> --sha <sha>`，删除「展示 YAML 让人抄」；③ `code-implementation.pipeline.json` 节点 12 补齐 checkpoint-add 描述（与节点 3/8 一致）；④ 三条流水线 push-progress 节点 `onFail` 从 `skip` 改为产出可见告警（不 abort——git push 可能已成功）。
- **FR-12（approve 驳回回退，2.1-H）**：① `dir-graph.yaml` 新增 `requirement-reviewing:reject -> drafting` 转换（D-1 决策）；② `cmdApprove` decline 分支查表执行已声明的 `{stage}:reject -> write-{stage}` 回退转换并输出回退提示，无回退转换时才 `fail`；③ 四份 `approve-*/SKILL.md` 错误处理表补「审批人回答非 yes」分支（与状态机实际转换逐一对齐；approve-dev-start 现有"重跑 write-dev-plan"的不可达建议订正）；④ approve-requirement 改正"无旁路"表述为「交互式终端或 Ed25519 签名授权（`--grant`）二选一，两者都不可绕过审批本身」。
- **FR-13（review-loop 死配置，2.1-I）**：按 D-2 决策删除 `gates.json:100` 的 `review-planning-report` 死配置；`product-planning.pipeline.json:109` 删"必须持久化 review-loop.attempts"承诺、改为如实描述 skill 自行落盘 `docs/product-planning/review-annotations/{report-id}.yml` 的机制。
- **FR-14（fetch 失败降级，2.4 Step 5）**：`requirement-register/SKILL.md` 错误表补：单仓 `fetch` 失败时降级为「从本地 trunk 派生 worktree，并在摘要输出中标注 `STALE_BASE`」——不直接 abort，也不静默视为成功。

### 批 3 —— 功能正确性修复（功能断裂者优先）

- **FR-15（inbox-emit 接口对齐，2.1-B）**：`feedback-writeback/SKILL.md:98-108` 迁到 `crctl inbox-emit <cr> --event feedback-writeback-done --to ... --payload ...` 形态（补必填 `to`，取值来源写明为 CR `owners.*.id` 或 feedback 发起人）；`handover-cr/SKILL.md:77-84` 补 `owner-handover` 事件并迁 CLI 形态（`subject/body` 进 payload）；`inbox-emit/SKILL.md` 三处同步补 `owner-handover`：触发意图列表 + 参数表 event 枚举 + 下游消费方声明。
- **FR-16（HEAD 一致性校验，2.1-J）**：`merge-feature-branch/SKILL.md` Step1.4 增加 `git rev-parse HEAD` vs `git rev-parse origin/requirement/{cr_id}` 比对，不一致时先要求 push-progress 补跑再合并。
- **FR-17（write-competitive-report 订正，2.1-K）**：`competitive-radar.pipeline.json` 节点 2 写入目标改为 `docs/competitive/reports/_index.yml`（与 SKILL 读写清单一致）；node-2 prompt 显式传 `confirmed=false` 出草稿，真正落盘挪到 human_approval 通过之后。
- **FR-18（pipeline UUID 撞号，2.1-C）**：`architecture-design.pipeline.json` 全部 5 个节点统一迁到未占用前缀 `0016-*`（不只改撞号的 3 个），同步 `repairNodeId` 自引用；改后跑 JSON 解析自检 + 两条流水线 seed 幂等验证。
- **FR-19（market-insights 索引统一，2.1-D）**：三个写入方统一目标 schema——顶层 `insights:`、type `MARKET_INSIGHT`、生命周期 `raw → briefed → published`、conduct-market-research 补 `file:` 字段、索引头补「单一事实源」声明；`market-to-plan.pipeline.json` 节点 5 的终态 `planned` 改为 `published` 并明确执行方；三份 SKILL.md 同一 commit 原子提交，若 `docs/market-insights/_index.yml` 有旧字段名历史数据则一次性迁移并在提交说明写清。
- **FR-20（sync owner 改调 crctl，2.1-E）**：`handover-cr` Step3/4 与 `resume-from-remote` Step4 的手写 owners 段统一改为调用 `crctl owner-set`。
- **FR-21（cmdNext 误判修复，2.4）**：`cmdNext` 的 `writing-back` 分支改查 writeback 产物 `specs/{spec_id}/traceability.yml`，不再以开发期工作稿判断"可归档"；`crctl.test.mjs` 补对应用例。
- **FR-22（cr-show 收敛）**：`cr-show/SKILL.md` 删硬编码 status→下一节点映射表，改调 `crctl next`（一步到位覆盖 merging/writing-back/archived/rejected/withdrawn）。
- **FR-23（planning 域歧义订正）**：`write-planning-report` SKIPPED 占位文案统一（部分跳过与全部跳过同一表述）；competitive-radar/market-to-plan 镜像节点 `onFail` 统一 abort（D-3 决策）；`report-to-planning-suggestion` 委托 planning-draft 参数改为如实传 `intent`/`context`；`market-to-plan.pipeline.json` 节点 3 输出格式描述改为 planning-draft 真实的 6 章节 DESIGN-DOC + P0-P2 优先级；`resume-cr.pipeline.json:44` 给 `list-remote-checkpoints` 补可选 `cr_id` 过滤参数并如实调用；`resume-from-remote` 错误表补「worktree 元数据残留（非 already-exists）」分支指引 `git worktree prune`；write-dev-plan 与 write-dev-tasks 工时估算补交叉校验（不一致 WARN）。

### 批 3.5 —— lint 护栏先行（先于批 4）

- **FR-24（R6/R7 规则）**：`lint-prompts.mjs` 补 R6（`crctl advance` 必须匹配 `--to\s+\S+` 与 `--trigger`；`trigger=`/`expected_current_status=`/`commit_mode=`/全角 `，、）` 进 `LITERAL_BLACKLIST`；校验范围同时覆盖 `backlog-set` 字段白名单与 `--template` subject 编号规则）与 R7（函数式 `inbox-emit(` 直接判违例；CLI 形态校验 `--event` 取值属于 `inbox-emit/SKILL.md` 声明枚举）。
- **FR-25（豁免范围 bug 修复）**：`<!-- lint-prompts:ignore -->` 豁免判断从"整段 `node.prompt` 生效"收窄到"只豁免注释所在行的邻近范围"（`radius` 取值在测试向量中固化为契约）。
- **FR-26（测试向量）**：`lint-prompts.test.mjs` 补三类向量：R6 违规（全角字符/反引号旗标/缺 `--to` 或 `--trigger`）、R7 违规（函数式调用/枚举外 event）、豁免范围（豁免注释与违规行同段时违规行仍须命中，复现 `product-planning.pipeline.json:109` 场景）。

### 批 4 —— 冗余收敛（先对齐、必要才抽）

- **FR-27（approve-* 四兄弟对齐）**：删 approve-dev-start 独有的「前置条件」节与「读取 AGENTS.md/dir-graph.yaml 解析路径」段，四者对齐一致；对齐后样板仍长才评估抽 `shared/approve-common`。
- **FR-28（writeback 三兄弟抽 shared）**：抽「writeback 脚本执行约定」（机械步骤由入库脚本执行 + `crctl git commit --template writeback` 骨架 + BAD_ARGS/CR_STATUS_MISMATCH/SELF_CHECK_FAILED 错误表）为一处引用。
- **FR-29（sync 免责收敛 + bucket 改调）**：「受控 shell + 禁手工指引 + SHELL_UNAVAILABLE」样板收敛到 `controlled-shell/SKILL.md` 单点引用，但各 skill 保留一行「SHELL_UNAVAILABLE 禁止降级为手工指引」摘要；bucket/worktreePath 计算三处改调 `crctl worktree-path`。
- **FR-30（台账冗余删除）**：删 `agents/_index.yml` 各 agent `constraints:` prose（机读台账只留 id/path/status/consumers/capabilities，禁止行为以 md 为唯一来源）。
- **FR-31（pipeline push-progress 样板抽取）**：三条流水线 push-progress 节点 prompt 抽成 push-progress skill 默认说明、节点只传差异参数；**前置：FR-11 已把 push-progress 本身修对**。
- **FR-32（评估项落地，D-3 后两项决策）**：`write-insight-brief` 合并进 `extract-market-insight` 附加区块后下线；`run-competitive-analysis` Step4 并入 `write-planning-report` 后下线；`list-remote-checkpoints`/`resume-from-remote` 存在性校验去重（节点 2 复用节点 1 结论）；`product-planning` 四调研节点「跳过检查」逻辑只在 SKILL.md 保留一份、pipeline node prompt 改引用。

### 收尾 —— 台账同步与验收

- **FR-33（台账与自检）**：同步 `skills/_index.yml`/`agents/_index.yml`/`agent-skill-matrix.yml` 三台账；跑 `check-skill-matrix.mjs`；对改过 UUID/节点数的 pipeline 做 JSON 解析自检；批 2.5 落地后跑 `crctl.test.mjs` 全量回归（LEGAL 扩展与 decline 分支必须有测试覆盖新路径）。
- **FR-34（文档更新）**：按报告 §6.4 时机表更新 ARCHITECTURE.md §8 评审记录、`crctl/SKILL.md`（cr-init 新旗标与 `--cr` 旗标）、`lint-prompts.mjs` 头部规则说明、AGENTS.md 抽 shared 原则。

## 4. 非功能需求

- **NFR-1（评审门槛）**：批 2.5 全部项目（FR-9~FR-14）触发 ARCHITECTURE.md §8「crctl 新增写入子命令/状态机语义变化」评审门槛，合并为一份技术设计一次评审通过；SDD 必须包含报告 §四 参考实现骨架的取舍说明。
- **NFR-2（可回滚）**：批 2.5 所有 crctl.mjs 核心改动保持单 commit 可 revert；`dir-graph.yaml` 状态机改动前留存改前版本对照；不另制备份目录（git commit 本身即历史与审计）。
- **NFR-3（原子提交）**：FR-19 的三份 SKILL.md + 索引迁移必须同一 commit 原子提交；market-insights 旧字段历史数据迁移用入库版本化脚本，禁止会话内现写脚本（纪律 #7）。
- **NFR-4（护栏时序）**：FR-24~FR-26（批 3.5）必须先于批 4 落地；抽 shared 前先给 lint 补「shared 引用一致性」检查，防止把「N 处漂移」换成「引用失效」。
- **NFR-5（灰度）**：批 2.5 先以测试 CR（或一次完整演练注册，形式参照 CR-2026-019 AC-9）走通「push-progress → checkpoint-add 落账」「approve 驳回 → 回退转换」「cr-init 新旗标原子写入」三条新路径，验证通过后再对全部在途 CR 生效。
- **NFR-6（零新增第三方依赖）**：crctl.mjs 与 lint-prompts.mjs 改动只用 Node 标准库与既有工具函数。
- **NFR-7（行尾纪律）**：凡涉及哈希/跨行解析的新代码（lint 规则、测试向量）遵守纪律 #1：读入先 `\r\n → \n` 规范化，跨行匹配失败硬失败不静默降级。
- **NFR-8（multica 仓注释英文）**：本 CR 落点全部在 tools 仓，不涉 multica；若实施期发现需联动，先读其 CLAUDE.md。

## 5. 验收标准

- **AC-1**（FR-1）：12 处命令串逐一与报告 2.1-A 目标形态 diff 为空；`review-requirement` 在 `requirement-reviewing` 自环场景重跑不被 `CR_STATUS_CURRENT_MISMATCH` 误拒。
- **AC-2**（FR-2/FR-3）：三份 SKILL.md frontmatter 内无豁免注释；`grep "tools/old"` 在 pipeline-templates/_index.yml 零命中；knowledge-agent 引用的 validate-doc 路径真实存在。
- **AC-3**（FR-4~FR-8）：`grep -r "cr-status-set"` 除 lint 黑名单定义外零引用；validate-doc 无未执行维度与失实自动调用声明；focus-briefing 竞品过滤可命中（补 status 后）；`agents/_index.yml` 各 `pending` 为 `[]` 且键保留；record-adr/adrs.yml 删除前有"无读者"核实记录。
- **AC-4**（FR-9/FR-10）：`cr-init --summary S --source X --target-version v` 一次写齐三字段（缺省值与旧硬编码同义）；`git commit --template register --cr CR-2026-NNN` 在 master 分支直传成功、不触发反向解析；`requirement-register` 参数表无 `cr_id`。
- **AC-5**（FR-11）：在 `drafting`/`task-breakdown` 等非终态调用 `checkpoint-add` 成功落账；push-progress 按新 Step 3 执行后 `_backlog` checkpoints 与远端 SHA 一致；节点 12 prompt 含 checkpoint-add；三处 `onFail` 失败时产出可见告警且不 abort。
- **AC-6**（FR-12）：四个 stage 各模拟一次 decline，CR 分别回退到对应前一阶段（requirement 回 `drafting`）并输出重跑提示；四份 approve-* 错误表含该分支且与状态机一致；approve-requirement 无"无旁路"失实表述。
- **AC-7**（FR-13）：`gates.json` 无 `review-planning-report` 条目；`product-planning.pipeline.json` node-6 无"必须持久化"承诺、含自行落盘机制的准确描述。
- **AC-8**（FR-14）：模拟单仓 fetch 失败，注册流程从本地 trunk 派生 worktree 且摘要输出含 `STALE_BASE` 标记，不 abort。
- **AC-9**（FR-15）：`feedback-writeback-done` 与 `owner-handover` 各发送一次，接收方收件可见；inbox-emit/SKILL.md 三处（触发意图/参数表/消费方）均含 `owner-handover`。
- **AC-10**（FR-16）：构造本地 HEAD ≠ 远端 HEAD 场景，merge-feature-branch 在 Step1.4 拦截并提示补跑 push-progress，不执行合并。
- **AC-11**（FR-17）：competitive-radar 节点 2 写入目标为 `reports/_index.yml`；human_approval 驳回（abort）时无已落盘的报告/索引残留。
- **AC-12**（FR-18）：`architecture-design.pipeline.json` 5 节点全在 `0016-*` 前缀、`repairNodeId` 指向新 node-1；两条流水线 JSON 解析通过、seed 幂等（重复 seed 不产生重复节点）。
- **AC-13**（FR-19）：三个写入方按统一 schema 读写 `docs/market-insights/_index.yml` 互不破坏；索引头含单一事实源声明；market-to-plan 节点 5 终态为 `published`；三份 SKILL.md 在同一 commit。
- **AC-14**（FR-20）：handover-cr/resume-from-remote 不再手写 owners 字段，owner 变更全部经 `crctl owner-set` 落账。
- **AC-15**（FR-21/FR-22）：writeback-traceability 未跑时 `crctl next` 在 `writing-back` 态不建议归档；跑完后建议正确；cr-show 无硬编码映射表。
- **AC-16**（FR-23）：八项歧义订正逐条对照报告 2.4 目标形态验证通过；competitive-radar 镜像节点 `onFail` 统一 abort 且在提交说明中标注运行时行为变化。
- **AC-17**（FR-24~FR-26）：三类测试向量全部通过；故意注入全角字符命令串/函数式 inbox-emit/豁免同段 R5 违规行，R6/R7/R5 分别命中且不被连带豁免；对批 1/批 3 改动面复扫零误报。
- **AC-18**（FR-27~FR-32）：approve-* 四者结构一致；writeback 三兄弟引用同一 shared 片段；sync 各 skill 保留 SHELL_UNAVAILABLE 一行摘要；`agents/_index.yml` 无 constraints prose；push-progress 节点样板抽取后三流水线行为等价；write-insight-brief/run-competitive-analysis 下线后引用计数清零且下游（briefed 状态推进、市场信号章节）功能不丢失。
- **AC-19**（FR-33）：`check-skill-matrix.mjs` 通过；`crctl.test.mjs`/`lint-prompts.test.mjs` 全量绿；改过的 pipeline JSON 全部可解析。
- **AC-20**（端到端，报告 §6.2）：场景 1 完整 CR 生命周期串联通过（注册新旗标 → checkpoint-add 真被调用 → 需求驳回回退 → 代码驳回回退 developing → HEAD 不一致拦截 → writeback 未完不误判可归档）；场景 2 通知链两条事件可达；场景 3 lint 护栏三类违规命中。

## 6. 成功指标

- 97 条发现全部关闭（逐项对照报告清单勾验），无"现场直改绕过本 CR"的分流。
- 全仓 `lint-prompts` 扫描 R6/R7 命中数在本 CR 完成后收敛为 0，且豁免范围 bug 复现场景转为命中。
- `checkpoint-add` 在所有非终态可用；approve 驳回回退转换执行率 100%（状态机声明转换的 stage）。
- 注册新 CR 一次成功（cr-init 三字段一次写齐 + `--cr` 直传），不再复现本 CR 注册实录中的 BAD_ARGS 重试与违纪手写。

## 7. 范围排除

**本 CR 包含**：审查报告 97 条发现对应的批 1/2/2.5/3/3.5/4 全部修复项 + 收尾台账同步与端到端验收（报告「CR 必要性判据」建议的"批 1/2/3.5/4 可现场直改不走 CR"分流**不采纳**，全部纳入本 CR，见 §1.2 范围口径）。

**本 CR 不包含**：
- `controlled-shell/rules.json` 提交白名单新增"分析文档入库"形态（注册复盘缺陷 3，非纯 prompt、涉及三方消费的运行时放行行为，留待后续单独决策）。
- 为 product-planning 新开 crctl 持久化子命令（D-2 已决策为删死配置路线）。
- 账本状态机/CAS 基础设施本身的重新设计（复用既有 `casWrite`/`casWriteMulti`/`auditLog` 机制）。
- multica 仓 SSL 证书环境配置（运维事项，不入 CR）。
- 与本审查无关的 crctl 既有子命令行为变更（`status`/`gate`/`validate` 等维持现状；`cmdNext` 仅修 writing-back 判断依据这一只读 bug）。
