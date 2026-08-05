# tools 工具包 Prompt 审查报告

- **日期**：2026-08-05
- **范围**：`skills/`（59 个 SKILL.md）、`pipeline-templates/`（8 个 pipeline + 索引/README）、`agents/`（9 个 agent + 索引）
- **视角**：死文件（不会用到）/ 大段冗余 / 描述歧义（歧义、自相矛盾、接口漂移）
- **方法**：引用图静态分析（59 skill × 全仓引用计数）+ 5 组并行精读 + 对高危/方案争议项亲自坐实（命令串格式、inbox-emit 接口、pipeline UUID、crctl advance 权威旗标、状态机自环转换、repairNodeId 连带引用）。全部方案已过一轮源码级复核，事实判定无一虚报，本稿已把复核中的修正与补充折叠进对应小节（不再单列复核章节）。
- **结论**：共 **75 条**发现（dead 22 / redundant 22 / ambiguous 31）。无「登记了但整份文件零消费者」的纯死 skill（`focus-briefing`、`record-idea` 一度可疑，但其产物 `focus.yml` / `docs/ideas/` 有下游读者，**不可删**）；真正的问题集中在**接口漂移 + 命令串畸形 + 大段样板重复**。

---

## 一、摘要：按严重度分层

| 层级 | 类别 | 数量 | 性质 |
|---|---|---|---|
| 🔴 高危 | 会导致执行失败 / 功能断裂 | 5 组 | AI 照抄命令必失败；通知链实际发不出；pipeline 幂等被破坏；手写状态字段绕过唯一写入口 |
| 🟠 死内容 | 死引用 / 僵尸产物 / 废弃未清 | 8 项 | 指向不存在的文件/skill；已弃用却仍标 active |
| 🟡 冗余 | 可抽 shared 的大段样板（**非默认抽取，见 2.3 前言**） | 5 组 | 多文件逐字重复，改一处要改 N 处；但抽取本身对 prompt 有代价，需先判断是否值得 |
| 🟢 歧义 | 描述含糊 / 自相矛盾 | 12 项 | AI 读了不确定怎么做，或前后表述冲突 |

**根因级元发现**：高危项 (A)(B) 都没被 `lint-prompts` 漂移检测器抓到——它的 R2 只查裸 `git`，不校验 `crctl advance` 的参数格式，也不校验 `inbox-emit` 的接口。建议补两条规则（具体设计见「三、修复批次建议」批 3.5）：
- **R6**：行内出现 `crctl advance` 必须匹配 `--to\s+\S+` 与 `--trigger`；`trigger=`、`expected_current_status=`、`commit_mode=`、以及全角 `，`/`、`/`）` 进 `LITERAL_BLACKLIST`。
- **R7**：函数式 `inbox-emit(` 直接判违例；CLI 形态下校验 `--event` 取值是否属于 `inbox-emit/SKILL.md` 声明的枚举。
两条规则都需要在 `lint-prompts.test.mjs` 补测试向量，且应在批 4（抽 shared）之前落地，防止大改动引入新的漂移无人发现。

---

## 二、修改清单（核心）

修改类型说明：**修正**＝改正文内容；**删除内容**＝删段落/字段/行；**删除文件**＝整份下线；**抽 shared**＝提取公共片段；**字段对齐**＝按真实接口改调用；**标 deprecated**＝改状态标记；**重排**＝编号/结构调整；**评估下线**＝需先确认无外部读者再删。

### 2.1 🔴 高危批

#### (A) `crctl advance` 命令串畸形 —— 12 处（8 个文件）

坏形态特征：全角逗号 `，` / 顿号 `、` 当分隔符、`trigger=`/`expected_current_status=`/`commit_mode=embedded` 用反引号包裹而非旗标、游离的 `）`。
**权威旗标**（源码 `cmdAdvance` + `crctl/SKILL.md:47` 为准）：`--to <s> --trigger <t> [--expect <cur>] [--embedded]`；`--expect` 是**单值**比较（`crctl.mjs:978` `flags.expect !== current`），不支持数组。

| 文件 | 行 | 类型 | 修改为 |
|---|---|---|---|
| skills/cr/cr-archive/SKILL.md | 58 | 修正 | `crctl advance --to archived --trigger cr-archive --expect writing-back --embedded` |
| skills/cr/cr-review-record/SKILL.md | 46 | 修正 | `crctl advance --to rejected --trigger cr-review-record:reject` |
| skills/cr/cr-review-record/SKILL.md | 47 | 修正 | `crctl advance --to withdrawn --trigger cr-review-record:withdraw` |
| skills/develop/review-code/SKILL.md | 97 | 修正 | `crctl advance --to code-reviewing --trigger review-code --expect developing` |
| skills/develop/review-code/SKILL.md | 98 | 修正 | `crctl advance --to developing --trigger "review-code:block -> implement-code" --expect developing`（trigger 含空格与 `->`，须加引号） |
| skills/develop/review-tech-design/SKILL.md | 72 | 修正 | `crctl advance --to tech-designing --trigger "review-tech-design:block -> write-tech-design" --expect tech-design-review-pending` |
| skills/develop/write-dev-tasks/SKILL.md | 79 | 修正 | `crctl advance --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed` |
| skills/develop/write-tech-design/SKILL.md | 47 | 修正 | `crctl advance --to tech-designing --trigger write-tech-design --expect requirement-approved` |
| skills/develop/write-tech-design/SKILL.md | 92 | 修正 | `crctl advance --to tech-design-review-pending --trigger write-tech-design-complete --expect tech-designing` |
| skills/requirement/review-requirement/SKILL.md | 91 | 修正 | `crctl advance --to requirement-reviewing --trigger review-requirement`（**省略 `--expect`**，不要写死 `--expect drafting`：状态机 `dir-graph.yaml:213-214` 定义了 `drafting→requirement-reviewing` 与 `requirement-reviewing→requirement-reviewing` 两条合法转换，`REVIEW_STAGE_EXPECT.requirement=['drafting','requirement-reviewing']` 证实需求驳回须支持在 `requirement-reviewing` 内自环重跑；`--expect` 只收单值，写死 `drafting` 会让合法自环被 `CR_STATUS_CURRENT_MISMATCH` 误拒。省略后 `findTransition` 仍会拦非法转换，两种合法 current 都放行） |
| skills/writeback/merge-feature-branch/SKILL.md | 160 | 修正 | `crctl advance --to merging --trigger merge-feature-branch --expect code-approved --embedded` |
| skills/writeback/writeback-prd-sdd/SKILL.md | 66 | 修正 | `crctl advance --to writing-back --trigger writeback-prd-sdd --expect merging` |

> 注：`cr-archive:15`、`merge-feature-branch:21`、`cr-status-set:9` 已是正确形态，无需改——同一 `cr-archive` 内 L15 对、L58 错，属自相矛盾。

#### (B) `inbox-emit` 接口漂移 —— 通知链实际断裂

真实入参：`cr-id` / `event`（枚举） / `to`（必填列表） / `payload`（可选 JSON）。

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/cr/feedback-writeback/SKILL.md | 98-108 | 字段对齐 | 调用传的 `target/outcome/specs-updated/timestamp` 不合接口，且**缺必填 `to`**。改为 `cr-id` + `event=feedback-writeback-done` + `to=[...]` + `payload={outcome, specs-updated, ...}`；并从函数式 `inbox-emit(...)` 迁到 `crctl inbox-emit <cr> --event ... --to ... --payload ...`。**`to` 的取值来源必须在文档中写明**（建议取 CR `owners.*.id` 或 feedback 发起人），否则接口修完 AI 仍不知道该填谁 |
| skills/sync/handover-cr/SKILL.md | 77-84 | 字段对齐 | 传的 `to/subject/body` **缺必填 `event`**，且枚举里无「移交」事件。需补 `owner-handover` 事件并迁到 `crctl inbox-emit` 形态，`subject/body` 塞进 `payload` |
| skills/cr/inbox-emit/SKILL.md | 22-32, 42-47 | 修正 | 补 `owner-handover` 事件枚举——**需三处同步，不是只改一处**：①触发意图列表（L22-32）②输入参数表的 event 枚举（L42-47）③下游消费方（pipeline / 任何按事件名路由的逻辑）。只改参数表会造成「枚举齐了但触发场景没声明」的新漂移 |

#### (C) pipeline node UUID 全量撞号

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| pipeline-templates/architecture-design.pipeline.json | 36, 45, 51, 74, 82, 91 | 修正 | `0014-000000000001/002/003` 与 `resume-cr.pipeline.json` 的同前缀三个 node id 完全相同，破坏 seed 幂等。**全部 5 个节点**（不是只改撞号的 3 个）统一迁到未占用前缀 `0016-*`——零散只改撞号的会破坏「一条 pipeline 一个 UUID 前缀」的既有约定（已占用前缀：0002/0003/0010/0011/0013/0014/0015）。**必须同步 L51 的 `repairNodeId: "...0014-000000000001"`**：它是 node-1 的自引用（回修路由目标），只改 node id 不改这个字段会让 `onBlock: route-to-repair-node` 指向失效节点 |

#### (D) market-insights 索引结构冲突

真实存在两套不兼容写法，写同一个 `docs/market-insights/_index.yml` 会互相破坏；目标 schema 明确如下：
- 顶层 key 统一为 **`insights:`**（extract-market-insight、write-insight-brief 两个读方都已用它，改动面最小）
- `type` 统一为 **`MARKET_INSIGHT`**（下划线，与 write-insight-brief 的读取校验一致）
- `status` 生命周期统一为 **`raw → briefed → published`**（conduct-market-research 产出成稿直接落 `published`）
- conduct-market-research 的条目补 **`file:`** 字段（其余两个写入方已有）
- 统一后在索引文件头补一条「单一事实源」声明，防止将来第四个写入者再引入新漂移

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/planning/conduct-market-research/SKILL.md | 57, 71 | 字段对齐 | 顶层 `entries:` → `insights:`；type `MARKET-INSIGHT` → `MARKET_INSIGHT`；status `published` 保持（生命周期终态）；补 `file:` 字段 |
| skills/planning/extract-market-insight/SKILL.md | 59, 81 | 字段对齐 | 确认已符合目标 schema（`insights:` / `MARKET_INSIGHT` / `raw`），补「单一事实源」声明 |
| skills/planning/write-insight-brief/SKILL.md | 67 | 字段对齐 | 确认已符合目标 schema，status 写入 `briefed` |

#### (E) sync 手写 owner 变更绕过 `crctl owner-set` —— 正确性问题，非纯冗余

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/sync/handover-cr/SKILL.md | 53-73 | 字段对齐 | description（L3）已称「经 crctl owner-set 变更 owners（S4）」，但 Step3/Step4 正文仍指示直接编辑 `cr.md`/`_backlog.yml` 的 owners 字段，未提 crctl owner-set，两者矛盾且违反 crctl 独占写纪律。正文统一改为调用 `crctl owner-set` |
| skills/sync/resume-from-remote/SKILL.md | 79-89 | 字段对齐 | Step4 更新 owner 的逻辑（`owners.{role}.id`/`assigned-at` + 顶层 `owner` + `owner-history`/`handover-history` + 同步 `_backlog`）与 handover-cr 近乎逐字重复，且同样绕过 `crctl owner-set`。统一改调 `crctl owner-set` |

> 该项原属「冗余批」里 sync 组的第③点，因其本质是**绕过唯一写入口的正确性缺陷**（不是单纯的文字重复），改判归入高危批，修复顺序提前。

### 2.2 🟠 死文件 / 死内容批

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/cr/cr-status-set/SKILL.md | 全文 | 删除文件 / 标 deprecated | 顶部已标 `legacy/deprecated`、lint R3 黑名单、quality-reviewer 明令禁调、状态推进已全改 `crctl advance`，无真实消费者。建议整体删除；若暂留，正文 L21「状态机中心写入点」等误导语须删，`_index.yml` 条目改 deprecated |
| skills/_index.yml | 287 | 修正 | cr-status-set 条目 `status: active` → `deprecated`（或随文件删除移除条目） |
| skills/_index.yml | 281 | 修正 | cr-review-record 的 brief 称「经 cr-status-set 推进终止态」，实际用 `crctl advance --to rejected/withdrawn`。改为「经 crctl advance 推进」 |
| pipeline-templates/_index.yml | 118 | 删除内容 | 注释「废弃条目已迁移至 tools/old/pipeline-templates/_index.yml」——`tools/old/` 不存在，死引用。删除该行 |
| agents/knowledge-agent.md | 39 | 修正 | Skill 引用 `skills/validate-doc.md`（不存在）→ `tools/skills/shared/validate-doc/SKILL.md` |
| skills/shared/validate-doc/SKILL.md | 11 | 删除内容 | 维度 2「gate 合规性」自述「当前阶段跳过此维度校验」，即列了个不执行的检查项。**默认删除该维度**；仅当能给出明确的后续排期记录（例如指向某个 TASK/CR 编号）才允许保留并标注「未实现（排期见 XXX）」——只标「未实现」而无排期背书，等于把死代码改成带注释的死代码，价值有限 |
| skills/shared/validate-doc/SKILL.md | 25 | 修正 | 声称 writeback-* 写入后「自动调用本 Skill」，实际 writeback 三兄弟走脚本自检 + `crctl validate`，从不调它。移除 writeback-* 的自动调用声明 |
| skills/planning/record-adr/SKILL.md | 14 | 评估下线 | 产物 `constraints/adrs.yml` 全仓无任何读者（三个低引用 skill 中唯一可判定的僵尸输出）。确认前端/agent 不再读后，连 skill 一并评估删除 |
| skills/planning/focus-briefing/SKILL.md | 24 | 修正 | 按 `status=new` 过滤竞品报告，但 write-competitive-report 写的报告索引条目不含 `status` 字段——过滤永不命中，简报永远收不到竞品提醒。**不要直接去掉过滤**（会导致历史旧报告天天进简报）：改为让 write-competitive-report 写索引时补 `status: new`，focus-briefing 消费后把状态翻转为 `seen`，保留「只看新报告」的语义 |
| skills/planning/focus-briefing/SKILL.md | 26, 41 | 修正 | 数据源指向 `.rayai/pipelines/_index.yml`，真实注册表是 `pipeline-templates/_index.yml`——但后者是 tools 包内路径，skill 实际运行在目标 workspace，安装后同样不存在。**不要直接改成 `pipeline-templates/_index.yml`**：先向运行时方确认目标 workspace 下真实的 pipeline 注册表路径；确认不了就整体删除该数据源（文档已声明该数据源可选、不存在时静默跳过，删除零副作用） |
| skills/competitive/report-to-planning-suggestion/SKILL.md | 91 | 修正 | delegate 到 `brainstorming`，skills/ 下不存在，但 matrix 已标 `external`，符合 AGENTS.md「外部能力只声明依赖」的边界——**不要移除该 delegate**（会削弱流程完整性）。补具体降级路径：「目标运行时未提供 brainstorming 时，直接委托 planning-draft」 |
| agents/_index.yml | 20,122,149,173,226 | 修正 | 各 agent 的 `pending` 能力（roadmap-diff / version-simulation / contract-query / release-note-write / release-review / multi-competitor-digest / competitor-watch-cron）全部无对应 skill、长期挂空。**不要删除 `pending` 键**（会丢失路线图语义）：保留键、清空为 `pending: []`；确有排期的能力应另立台账追踪 |

### 2.3 🟡 冗余批（先判断是否值得抽 shared，再动手）

**前言（重要，决定本批的默认动作）**：SKILL.md 是一次性喂给模型读的 prompt，不是有编译期解析保障的代码——DRY 在这里不总是净收益。抽 shared 会引入「多读一跳、引用可能失效」的间接性代价，而仓库现状**没有跨文件样板一致性检测**（现有 `digest-vectors` 只测证据摘要）。所以本批默认动作调整为：
1. **样板不长、且真正的问题是"彼此不一致"而非"重复"**（例如四个 approve-*）→ 先对齐不一致，不默认抽 shared；只有对齐后仍确认样板本身很长，才考虑抽。
2. **样板确实长**（例如 writeback 三兄弟的脚本执行段+错误表）→ 值得抽。
3. 无论选哪种，**抽 shared 前必须先落地 R6/R7 等 lint 护栏**（见「一、摘要」根因级元发现），并给 lint 补「引用是否仍指向真实 shared 片段」的一致性检查——否则等于把「N 处漂移」换成「引用失效」，风险不降反升。

| 涉及文件 | 位置 | 类型 | 修改内容 |
|---|---|---|---|
| skills/develop/approve-code, approve-dev-start, approve-tech-design + requirement/approve-requirement | 各 approve-* 执行步骤+错误表 | 先对齐、暂不抽 shared | 四者「3 步执行 + 错误处理表」逐字雷同，仅 stage/status 名不同——**按前言原则 1，先处理的是差异点而非重复本身**：approve-dev-start:28-30 独有的「前置条件」节与 crctl approve 的门禁校验重复，且其他三个 approve 都没有，应删除；独有的「读取 AGENTS.md/dir-graph.yaml 解析路径」段其余三个也不需要，应删除。四者对齐一致后，若样板仍长，再评估抽 `shared/approve-common` |
| skills/writeback/writeback-prd-sdd, writeback-tasks, writeback-traceability | 各 L18 / 脚本执行段 / 错误表 | 抽 shared | 「机械步骤由入库脚本执行」段 + `crctl git commit --template writeback` 骨架 + BAD_ARGS/CR_STATUS_MISMATCH/SELF_CHECK_FAILED 错误表三处大段雷同，符合前言原则 2（样板确实长）。抽「writeback 脚本执行约定」一处引用 |
| skills/sync/pull-progress, push-progress, resume-from-remote, handover-cr | 受控 shell 免责样板 / bucket 计算 | 抽 shared（部分）+ 改调 crctl | ①「受控 shell + 禁手工指引 + SHELL_UNAVAILABLE」样板四处重复 → 收敛到 `controlled-shell/SKILL.md` 单点引用，但**「SHELL_UNAVAILABLE 禁止降级为手工指引」这条纪律必须在各 skill 保留一行摘要**，不能完全藏进 shared 引用——这条是执行时的硬约束，AI 读到本文件时应能就地看到，不应依赖跳转；②bucket/worktreePath 计算三处逐字重复 → 不是抽 shared 问题，是**该改调 `crctl worktree-path`** 这个已存在的只读命令。（owner 变更重复已改判为正确性问题，见 2.1-E，从本批移出） |
| agents/_index.yml | 各 agent constraints 块 | 删除内容 | 每个 agent 的 `constraints:` prose 与对应 md「禁止行为」段逐条复述。机读台账只留 id/path/status/consumers/capabilities，禁止行为以 md 为唯一来源（此项是删冗余、不是抽 shared，前言的抽取代价不适用） |
| pipeline-templates/code-implementation, architecture-design, requirement-authoring | push-progress 节点 prompt | 抽 shared | 「若=false 输出 SKIPPED…经 crctl checkpoint-add 更新 _backlog」样板多处逐字重复。抽成 push-progress skill 默认说明，节点只传差异参数——风险较低，因为引用目标是已存在且被复用的同一个 skill，不是新建的 shared 片段 |

### 2.4 🟢 歧义批（择要）

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/cr/cr-show/SKILL.md | 91-110 | 修正 | 硬编码 status→下一节点映射表，与 CR-2026-021 D8「唯一收敛为 crctl next」冲突，易随状态机漂移。改调 `crctl next`，删硬编码表 |
| skills/develop/write-test-report/SKILL.md | 63 vs 72-81 | 删除内容 | L63 声明记账走 `crctl attempt`，紧接 YAML 又要手写 `review-loop.attempts` 数组，自相矛盾。删手写块，只留 crctl attempt；去掉「TASK-17 起生效」变更备注 |
| skills/develop/write-dev-plan/SKILL.md | 31 | 修正 | 前置校验用软措辞「CR status 应为 tech-design-reviewed」，既无 crctl 校验也无 abort。改为明确「必须为…否则停止」或说明由 write-dev-tasks 的 expected_current_status 兜底 |
| skills/develop/write-dev-plan/SKILL.md | 60 | 修正 | commit 用裸 `feat(...)`，同组 write-dev-tasks 走 `crctl git commit --template`。统一走模板 |
| skills/requirement/requirement-register/SKILL.md | 15, 60 | 重排 | L15「完成以下三件事」却列 4 项；Step 编号从 2 跳到 4（缺 3）。改「四件事」+ 连续编号 |
| skills/writeback/merge-feature-branch/SKILL.md | 18 | 修正 | 正文说「两阶段合并」却列 4 个阶段。改「四阶段」或点明「两阶段」指哪两段 |
| skills/spec/spec-dashboard/SKILL.md | 42-50 | 修正 | 「在途 CR 状态分布」表只列 6 个状态，漏 requirement-reviewing/tech-designing/tech-design-review-pending/task-breakdown/code-approved/merging 等真实态。标注为示例或补齐 |
| skills/review/review-alignment/SKILL.md | 32 | 删除内容 | 读取契约列入 `plan.md`，但 AL-01~AL-07 无一项消费 plan.md。删该未用读取项 |
| skills/planning/conduct-market-research/SKILL.md | 57 | 修正 | type 拼写冲突（见 2.1-D，已并入高危处理，目标形态见该节） |
| skills/planning/review-planning-report/SKILL.md | 94 | 修正 | 假设 `_index.yml` 为 `features[].id` 结构，但 write-planning-report/entry 写的是顶层扁平 `- id:`。**以写入方为准修读取方**——write-planning-report/write-planning-entry 是事实生产者，统一改索引结构描述为扁平 `- id:` |
| skills/planning/gather-product-context/SKILL.md | 81, 34, 206 | 修正 | 竞品分析读 `docs/competitive/*.md`（竞品档案），但报告实际在 `docs/competitive/reports/`。改读 `reports/_index.yml` |
| skills/shared/crctl/SKILL.md | 20-33, 79 | 修正 | 用途表只列 9 条子命令，实际 20+。**定位为契约摘要**：只列 gate 子集 + 注明「完整见 `crctl --help`」，但**跨 skill 依赖必须列出**——spec-dashboard 依赖 `report`、merge-feature-branch 依赖 `merge-metadata`，这两条若不列，依赖图会失真；L79 版本历史的「九个子命令」计数同步更新 |
| skills/develop/review-code/SKILL.md；requirement-register:17；implement-code:77 | frontmatter 内 | 删除内容 | `<!-- lint-prompts:ignore -->` 注释被塞进 YAML frontmatter 内部或正文孤立行，破坏纯净度。移出 frontmatter / 删孤立行 |
| skills/cr/cr-inbox/SKILL.md | 37-45 | 修正 | 过滤逻辑与 cr-query 参数基本重叠（cr-inbox 本质是 owner=当前用户的 cr-query 预设视图）；且依赖的 `reviewer` 字段来源未坐实。改为委托 cr-query + 优先级排序；**若 `reviewer` 字段确认未落库，排序依据改用 `owners.*.id` + `updated` 时间**，不要保留一个永远命中空的过滤条件 |

---

## 三、修复批次建议

| 批次 | 内容 | 风险 | 说明 |
|---|---|---|---|
| **批 1** | 2.1-A 命令串 12 处（review-requirement 按上文说明省略 `--expect`）+ 2.4 frontmatter 注释外移 + 2.2 的 tools/old 死引用、knowledge-agent 死路径 | 零风险（纯机械文本修正） | 可直接改 |
| **批 2** | 2.2 死内容清理（cr-status-set 下线 + `_index.yml` 两处 + validate-doc 死维度 + focus-briefing 两处反向修 + report-to-planning-suggestion 降级路径 + agents/_index.yml pending 清空为 `[]`） | 低 | cr-status-set、`adrs.yml` 两项删除前需先确认无外部读者 |
| **批 3** | 2.1-B/C/D/E 功能修复：inbox-emit 接口对齐（含三处枚举同步）+ UUID 撞号（5 节点整体迁移 + repairNodeId 同步）+ market-insights 索引统一（按目标 schema）+ sync 手写 owner 改调 `crctl owner-set` | 中（涉及接口/枚举/结构约定，且是正确性修复不只是文档整理） | 需逐项对照目标形态验证 |
| **批 3.5** | lint 补 R6/R7 规则（`crctl advance` 参数格式校验 + `inbox-emit` 接口/枚举校验），并补 `lint-prompts.test.mjs` 测试向量 | 低 | **提前到批 4 之前**，在大改动前先建立护栏，防止批 4 抽 shared 时引入新的、当前工具查不出的漂移 |
| **批 4** | 2.3 冗余批：按「先对齐、必要才抽」的原则处理 approve-*；抽 writeback 三兄弟共享片段；sync 免责声明部分收敛（保留 SHELL_UNAVAILABLE 摘要）+ bucket 计算改调 `crctl worktree-path`；删 `agents/_index.yml` 冗余 constraints；抽 pipeline push-progress 节点样板 | 中高（改动面最大） | 前置条件：批 3.5 的 lint 护栏必须先落地；且需先给 lint 补「shared 引用一致性」检查，否则把「N 处漂移」换成「引用失效」 |
| **收尾** | 按 AGENTS.md 要求同步三台账（`skills/_index.yml`、`agents/_index.yml`、`agent-skill-matrix.yml`）；跑 `check-skill-matrix.mjs`；对改过 UUID/节点数的 pipeline 做 JSON 解析自检 | 低但必做 | 尤其是批 3 的 UUID 迁移、批 4 的结构调整之后 |

---

## 四、审查覆盖与方法附录

- **引用图**：对 59 个 skill id 做全仓引用计数，最低者 `focus-briefing`(1)/`record-idea`(2)/`cr-inbox`(2) 逐一坐实——均有产物下游读者，无纯死 skill。
- **反向校验**：8 个 pipeline 的 37 处 `"ref"` 全部命中真实 skill，无拼错/死引用（node UUID 撞号除外）。
- **亲验项**（不依赖 agent 判断，已用源码/grep 坐实）：crctl advance 权威旗标与 `--expect` 单值语义（`cmdAdvance` 源码）、12 处坏命令串精确行号、inbox-emit 真实入参、pipeline UUID 撞号、`requirement-reviewing` 自环转换（`dir-graph.yaml`）、`architecture-design.pipeline.json` 的 `repairNodeId` 自引用、UUID 前缀占用表。
- **两处判断修正**（均已体现在上文对应小节，不再单列）：
  1. `focus-briefing` 最初按「零引用」疑似可删，经查它是 `focus.yml` 唯一写入者、而 `focus.yml` 被 analyze-current-product / gather-product-context 读取，**改判不可删**。
  2. 原稿曾建议 review-requirement:91 写死 `--expect drafting`，经核对状态机自环转换定义后**改判为省略 `--expect`**（见 2.1-A）；同批还纠正了 architecture-design 的 UUID 迁移范围（全部 5 节点而非只改撞号的 3 个，且必须同步 `repairNodeId`）、sync 组的 owner 变更问题定性（由「冗余」改判为「正确性缺陷」，移入高危批）、以及 focus-briefing/report-to-planning-suggestion/validate-doc 三处死内容的修复方向（均改为「先确认或反向修」而非直接删/直接标注）。
