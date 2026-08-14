# tools 工具包 Prompt 审查报告

- **日期**：2026-08-05
- **范围**：`skills/`（59 个 SKILL.md）、`pipeline-templates/`（8 个 pipeline + 索引/README）、`agents/`（9 个 agent + 索引）
- **视角**：死文件（不会用到）/ 大段冗余 / 描述歧义（歧义、自相矛盾、接口漂移）
- **方法**：引用图静态分析（59 skill × 全仓引用计数）+ 5 组并行精读 + 对高危/方案争议项亲自坐实（命令串格式、inbox-emit 接口、pipeline UUID、crctl advance 权威旗标、状态机自环转换、repairNodeId 连带引用）。全部方案已过一轮源码级复核，事实判定无一虚报；后续 CR-2026-022 实际注册执行又坐实 4 条本稿未覆盖的摩擦（均在 `requirement-register` 入口 skill 本身及其依赖的 `cr-init`/`--template` 接口）；再后续对**其余 7 条流水线**（架构设计/代码实现/需求编写剩余节点/回写+接手/竞品雷达+洞察转规划/调研规划）做了逐节点模拟执行走查（7 组并行精读，方法与前两轮一致：不满足于通读找 typo，而是追问"照着这份 SKILL.md 执行的人/AI 走到这一步会不会卡住、矛盾、多此一举"，任何涉及 crctl 命令/字段的判断都回源码坐实）。三轮发现均已折叠进对应小节，不再单列复核章节。
- **结论**：共 **97 条**发现（原稿 75：dead 22 / redundant 22 / ambiguous 31；CR-2026-022 注册实录补充 4；7 条流水线执行走查补充 18：高危新增 5 组 / redundant +4 / ambiguous +9）。无「登记了但整份文件零消费者」的纯死 skill（`focus-briefing`、`record-idea` 一度可疑，但其产物 `focus.yml` / `docs/ideas/` 有下游读者，**不可删**）；真正的问题集中在**接口漂移 + 命令串畸形 + 大段样板重复**，且入口 skill（requirement-register）、乃至 crctl 本体的核心状态机函数（`cmdCheckpointAdd`/`cmdApprove`）本身都不例外——本轮走查坐实的高危项已经不是"文档写错了"，而是**crctl 代码本身存在没被兑现的承诺**（详见 2.1-G/H/I）。

---

## 一、摘要：按严重度分层

| 层级 | 类别 | 数量 | 性质 |
|---|---|---|---|
| 🔴 高危 | 会导致执行失败 / 功能断裂 | 11 组 | AI 照抄命令必失败；通知链实际发不出；pipeline 幂等被破坏；手写状态字段绕过唯一写入口；注册入口 cr-init 缺字段写口逼出违纪手写；**push-progress 的账本写入承诺自相矛盾且跨 3 条流水线**；**审批驳回全线无路可退**；review-loop 质量关口是死配置且拖累 lint 自身规则失效；合并/写入前的一致性校验缺失 |
| 🟠 死内容 | 死引用 / 僵尸产物 / 废弃未清 | 8 项 | 指向不存在的文件/skill；已弃用却仍标 active |
| 🟡 冗余 | 可抽 shared 的大段样板（**非默认抽取，见 2.3 前言**） | 9 组 | 多文件逐字重复，改一处要改 N 处；但抽取本身对 prompt 有代价，需先判断是否值得 |
| 🟢 歧义 | 描述含糊 / 自相矛盾 | 21 项 | AI 读了不确定怎么做，或前后表述冲突 |

**根因级元发现**：高危项 (A)(B) 都没被 `lint-prompts` 漂移检测器抓到——它的 R2 只查裸 `git`，不校验 `crctl advance` 的参数格式，也不校验 `inbox-emit` 的接口。建议补两条规则（具体设计见「三、修复批次建议」批 3.5）：
- **R6**：行内出现 `crctl advance` 必须匹配 `--to\s+\S+` 与 `--trigger`；`trigger=`、`expected_current_status=`、`commit_mode=`、以及全角 `，`/`、`/`）` 进 `LITERAL_BLACKLIST`。
- **R7**：函数式 `inbox-emit(` 直接判违例；CLI 形态下校验 `--event` 取值是否属于 `inbox-emit/SKILL.md` 声明的枚举。
两条规则都需要在 `lint-prompts.test.mjs` 补测试向量，且应在批 4（抽 shared）之前落地，防止大改动引入新的漂移无人发现。

CR-2026-022 注册实录进一步证明这不是 (A)(B) 独有：`backlog-set` 字段白名单（仅 `prd-path|sdd-path`）与 `--template` 提交的 subject 编号规则同样是「SKILL 描述 ≠ crctl 实际接受参数」的同类漂移（见 2.1-F）。R6/R7 的校验范围需相应扩大到这两处，不能只锁死 `advance`/`inbox-emit` 两个命令名。

7 条流水线执行走查又挖出更深一层：**lint-prompts 自身有个 bug**——`<!-- lint-prompts:ignore -->` 的豁免判断对整段 `node.prompt` 生效而非只豁免邻近行，导致 `product-planning.pipeline.json:109` 里一条不相关的豁免注释把本该命中 R5（手写 review-loop 记账）的内容也一并放行（见 2.1-I）。这意味着 R6/R7 补上之后，如果不修这个豁免范围 bug，未来同样可能被"顺手带过"——**建议 R6/R7 与豁免范围修复算同一批（批 3.5）一起改**。

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
| pipeline-templates/market-to-plan.pipeline.json | 76（节点 5） | 字段对齐 | node-5 prompt 写"将 `docs/market-insights/_index.yml` 对应条目 status 更新为 `planned`"，与上面目标 schema 终态 `published` 不一致（本条为流水线执行走查新增坐实）；且 `write-planning-entry/SKILL.md` 全文没有"回写 market-insights 状态"这一步，这条状态推进指令只存在于 pipeline prompt 里、技能定义完全没提。统一改为 `published`，并明确这一步该由 write-planning-entry 还是 planning-draft 执行 |

#### (E) sync 手写 owner 变更绕过 `crctl owner-set` —— 正确性问题，非纯冗余

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/sync/handover-cr/SKILL.md | 53-73 | 字段对齐 | description（L3）已称「经 crctl owner-set 变更 owners（S4）」，但 Step3/Step4 正文仍指示直接编辑 `cr.md`/`_backlog.yml` 的 owners 字段，未提 crctl owner-set，两者矛盾且违反 crctl 独占写纪律。正文统一改为调用 `crctl owner-set` |
| skills/sync/resume-from-remote/SKILL.md | 79-89 | 字段对齐 | Step4 更新 owner 的逻辑（`owners.{role}.id`/`assigned-at` + 顶层 `owner` + `owner-history`/`handover-history` + 同步 `_backlog`）与 handover-cr 近乎逐字重复，且同样绕过 `crctl owner-set`。统一改调 `crctl owner-set` |

> 该项原属「冗余批」里 sync 组的第③点，因其本质是**绕过唯一写入口的正确性缺陷**（不是单纯的文字重复），改判归入高危批，修复顺序提前。

#### (F) requirement-register 注册路径：cr-init 缺字段写口 + 死参数 + `--template` 反向解析 —— CR-2026-022 注册实录坐实

原稿未覆盖 `requirement-register` 自身的注册路径；CR-2026-022 实际注册执行时坐实以下三处问题，彼此因果相连（第一条是根，后两条是它逼出的连带症状）。

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/shared/crctl/scripts/crctl.mjs（`cmdCrInit`） | 1711-1751 | 修正（新增能力） | `cmdCrInit` 硬编码 `summary: ""` / `source: manual` / `target-version: tbd`，不收这三个值的旗标；`BACKLOG_SET_FIELDS` 白名单（:1564）也只有 `prd-path\|sdd-path`，同样不含它们。**结果是 SKILL Step 2「模型不得手写 cr.md」与「这三个字段无路可写」直接矛盾**——唯一能落地的做法是违纪手写，注册实录中正是这么做的。补 `cr-init --summary --source [--target-version]` 三个可选旗标，注册时一次原子写齐，消灭违纪路径，同时省掉「先建档、再补字段」这两步 |
| skills/requirement/requirement-register/SKILL.md | 28 | 删除内容 | 参数表 `cr_id`「仅预览/校验用途」——`cmdCrInit` 只读 `title`/`owner-requirement`/`year`，`cr_id` 传了也被忽略，是僵尸参数；它也是 Step 1「读三账本核对编号」这一步冗余读的唯一动机（cr-init 内部 `scanMaxCrNumber+1` 才是权威分配）。删除该参数与其对应的格式/占用校验 |
| skills/shared/crctl/scripts/crctl.mjs（`resolveTemplateCr`） | 1953-1961 | 修正 | `--template` 提交靠「分支名 `requirement/CR-*` 探测 → subject 正则兜底 → 无则 fail」反向解析 CR 号；但注册场景发生在 master 分支，分支探测必然落空，只能靠 subject 强制带编号——而调用方（requirement-register Step 4）此时手里已经有 Step 2 `cr-init` 刚返回的 `cr_id`，属于「问一个已知答案」。注册实录复现了后果：`-m title` 因缺编号首次提交即 `BAD_ARGS`。补显式 `--cr <cr-id>` 旗标，调用方直传已知值，跳过反向解析 |

> 本组由 `docs/analysis/CR-2026-022-注册流程复盘.md` 的实际注册执行坐实，属原审查的覆盖盲区（引用图/精读都没有把「入口 skill 自身如何被执行」纳入检查对象）。**修法涉及 crctl 新增写入参数，触发 `ARCHITECTURE.md` §8「crctl 新增写入子命令」评审门槛，不属零风险机械修正**——需单独出技术设计，建议随 CR-2026-022 一并提交（见「三、修复批次建议」新增行）。

#### (G) `push-progress`/`checkpoint-add` 承诺自相矛盾 —— 3 条流水线通病，本轮最高杠杆发现

对 requirement-authoring / architecture-design / code-implementation 三条流水线逐节点模拟执行坐实：`push-progress` 这个 skill 在三条流水线里都被复用，同一个缺陷出现三次。

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/sync/push-progress/SKILL.md | 47-81（Step 2-3） | 修正（需先定设计） | Step 2-3 全程只调 `runGit`，从未出现一行 `crctl checkpoint-add` 调用；Step 3 直接展示 `_backlog.yml` 目标 YAML 让执行者「照着改」，等同手工编辑账本文件，违反 ARCHITECTURE.md §5 不变量 2。但三条流水线的节点 prompt 都写「经 `crctl checkpoint-add` 更新 _backlog」——SKILL 正文与调用方指令自相矛盾，照哪边执行都错。改为 Step 3 对每个 active repo 显式循环调用 `crctl checkpoint-add --repo <r> --sha <sha>`（`crctl.mjs:1576` 逐仓单次接口），删除「展示 YAML 让人抄」的写法 |
| skills/shared/crctl/scripts/crctl.mjs（`cmdCheckpointAdd` 的 `LEGAL` 常量） | 1578-1579 | 修正（新增能力，需评审） | 合法前置状态列表 `['developing','code-reviewing','code-approved','merging','writing-back']` 不含 `drafting`/`requirement-reviewing`/`requirement-approved`/`tech-designing`/`tech-design-review-pending`/`tech-design-reviewed`/`task-breakdown`——但 push-progress 节点在 requirement-authoring（`drafting` 态）、code-implementation 节点 3（`task-breakdown` 态）都会被调用。上一条把 checkpoint-add 落到实处后，这几个状态下必炸 `ILLEGAL_LEDGER_STATE`。需要把 `LEGAL` 扩到覆盖所有存在 push-progress 节点的非终态，而不是只服务 develop/writeback 阶段的窄列表 |
| pipeline-templates/code-implementation.pipeline.json | 217（节点 12） | 字段对齐 | 该节点（第三次 push-progress）的 prompt 唯独不提 checkpoint-add，只说「经 crctl git add/commit 提交…账本 code-approved 状态」，与节点 3/8（都明写 checkpoint-add）不一致。补齐 checkpoint-add 调用描述，三处保持一致 |
| pipeline-templates/{requirement-authoring, architecture-design, code-implementation}.pipeline.json | 各 push-progress 节点 `onFail` | 修正 | 三处 push-progress 节点 `onFail` 均为 `"skip"`——checkpoint-add 若按上两条继续调用而失败，会被静默吞掉，CR 已推进但账本 checkpoint 永久缺失且无人发现。上两条修好之后，`onFail` 应改为至少产出一条可见告警（不宜直接 abort，因为 git push 本身可能已成功），不能维持「skip=什么都不记录」 |

> 一个 skill + 一处 crctl 状态白名单改一次，同时修复三条流水线里的同类问题，不是三处孤立小修。**涉及 crctl 状态白名单扩展，触发 ARCHITECTURE.md §8 评审门槛**。

#### (H) `crctl approve` 驳回后无路可退 —— 四个人工审批门禁通病

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/shared/crctl/scripts/crctl.mjs（`cmdApprove` 非 TTY-yes 分支） | 1072-1077 | 修正（核心状态机逻辑，需设计评审） | 审批人终端回答非 `yes` 时只 `fail('APPROVAL_DECLINED', '审批人未确认，未写入任何文件')`，从不调用 `dir-graph.yaml` 里已声明的 `{stage}:reject -> write-{stage}` 回退转换（如 `approve-tech-design:reject -> write-tech-design`，`dir-graph.yaml:220`）。AGENTS.md:109 明文强制"驳回必须走这个显式回退转换"，代码从未兑现。需要在 decline 分支里查表调用对应的 `crctl advance --to <前一阶段> --trigger "{stage}:reject -> write-{stage}"`，把承诺的回退转换真正执行掉 |
| dir-graph.yaml（需求阶段状态机段） | 212-217 | 修正（需先决策） | 需求阶段状态机**完全没有** `requirement-reviewing → drafting` 的驳回转换（对照 tech-design/code 阶段都有），approve-requirement 被拒后无处可去，唯一正式退出通道是 `cr-review-record:reject → rejected`（直接判 CR 死刑）。**需要产品/架构决策**：是新增一条 `requirement-reviewing:reject -> drafting` 转换（允许打回重写 PRD），还是维持"需求驳回=CR 终止，另开新 CR"的现状并把这一点显式写进 SKILL 文档？两种都合理，但目前是"没人做决定，文档和代码各自沉默" |
| skills/develop/approve-dev-start/SKILL.md、skills/develop/approve-code/SKILL.md、skills/develop/approve-tech-design/SKILL.md、skills/requirement/approve-requirement/SKILL.md | 各自错误处理表 | 修正 | 四份文档的错误处理表都没有"审批人在终端回答非 yes"这一行；approve-dev-start 的错误表甚至建议"重跑 write-dev-plan"，但 `task-breakdown` 状态在状态机里没有回到 `tech-designing`（write-dev-plan 前置要求）的转换，这条建议本身不可达。上一条 crctl 修复落地后，四份文档需统一补上"驳回后 CR 自动回到 XXX 状态，请重新执行 YYY"这一行，且要跟状态机实际转换对齐，不能各自瞎猜 |
| skills/requirement/approve-requirement/SKILL.md | 31, 36 | 修正 | 声称 `crctl approve` "无旁路"，但 `crctl.mjs:1037` 的 `--grant` 分支在 TTY 检查之前就已分流（P1 签名审批），与"无旁路"字面矛盾。改为准确描述："交互式终端或 Ed25519 签名授权（`--grant`）二选一，两者都不可绕过审批本身" |

> 涉及 crctl 核心状态机逻辑（decline 分支要触发真实回退转换）+ 一处状态机声明缺口需要产品决策，**触发 ARCHITECTURE.md §8「状态机语义变化」评审门槛，不是机械修正**。

#### (I) review-loop 质量关口存在死配置 + lint 自身规则被误伤放行

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/shared/crctl/gates.json | 100 | 修正/评估下线 | `reviewLoops.review-planning-report` 声明了 pipeline 归属，但 `evaluatePassCondition`/`readAttempts`（crctl.mjs）只服务 requirement/tech-design/code 三个 CR 阶段的 gate，从未引用这条 loop 配置——是一条声明了但从未被任何门禁实际调用的死配置。且它假设的 attempts 持久化路径需要 `change-requests/{cr}/` 上下文，而 product-planning 全程在主分支跑、没有 CR 上下文，路径本身就不成立。**需要决策**：要么把 review-planning-report 的 attempts 记账正式接入一条不依赖 CR 上下文的 crctl 子命令（如按 report-id 落盘），要么删除 gates.json 里这条死配置、如实说明"该 reviewLoop 目前靠 review-planning-report 自行落盘 `docs/product-planning/review-annotations/{report-id}.yml`，未经 crctl" |
| pipeline-templates/product-planning.pipeline.json | 109 | 修正 | node-6 prompt 写"每次评审必须持久化 `review-loop.attempts[]`"，但没有 crctl 命令支撑这句话（同上）。删除这句误导性的"必须持久化"承诺，或换成准确描述当前的自行落盘机制 |
| skills/shared/crctl/scripts/lint-prompts.mjs | 86-110（`splitPipelineJson` + 豁免判断） | 修正（lint 工具自身 bug） | `<!-- lint-prompts:ignore -->` 的豁免判断对整个 `node.prompt` 字符串生效，而不是只豁免紧邻的那一行。`product-planning.pipeline.json:109` 里一条为了给"docs/ 路径非 guard deny 面"消音的豁免注释，把同一段后面出现的 `review-loop.attempts[]`（本该命中 R5 黑名单、判 OUTDATED）也一并放行了。需要把豁免判断收窄到"注释所在行的邻近范围"，不能整段生效——否则 R5 规则对 pipeline JSON 里的 node.prompt 形同虚设 |

> lint-prompts 自身的 bug 优先级很高：它是本报告 R6/R7 护栏能生效的前提，如果豁免机制本身有"整段生效"这个洞，R6/R7 补了也可能被同样方式绕过去。**建议和批 3.5 的 R6/R7 一起修，同一批次**。

#### (J) `merge-feature-branch` 缺本地/远端 HEAD 一致性校验

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/writeback/merge-feature-branch/SKILL.md | 73（Step1.4） | 修正 | 只校验"CR worktree 无未提交变更 + origin/requirement/{cr_id} 存在"，不校验本地 HEAD 是否等于远端 HEAD；但 Step2/3 合并的是 `origin/requirement/{cr_id}`（远端分支）。若 code-implementation 最后一次 push-progress 因 `onFail:skip` 静默失败（见 (G)），本地已是 `code-approved` 但远端分支缺最后一次提交（评审/审批证据 commit），merge-feature-branch 会照常合并"缺最后一次提交"的远端分支，没有任何环节核对这个落差。补一步：Step1.4 增加 `git rev-parse HEAD` vs `git rev-parse origin/requirement/{cr_id}` 比对，不一致时先要求 push-progress 补跑，而不是直接合并 |

#### (K) `write-competitive-report` 写入目标文件搞混 + 两阶段确认协议被绕过

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| pipeline-templates/competitive-radar.pipeline.json | 51（节点 2 prompt） | 字段对齐 | prompt 让节点"结果写入 node-2.md，同时追加一条 entry 到 `docs/competitive/_index.yml`"；但 `write-competitive-report/SKILL.md:122-126` 的读写清单里根本没有这个目标，真实写入是 `docs/competitive/reports/*.md`、`docs/competitive/{id}.md`（updates[]）、`docs/competitive/reports/_index.yml`——`_index.yml`（竞品档案注册表）和 `reports/_index.yml`（报告索引）是两个不同文件。按 prompt 字面执行会把报告条目误写进竞品注册表。改为与 SKILL 一致的 `docs/competitive/reports/_index.yml` |
| pipeline-templates/competitive-radar.pipeline.json | 51 vs `write-competitive-report/SKILL.md:12` | 管控缺失 | write-competitive-report 自身要求落盘前必须拿到 `confirmed` 参数确认，但 pipeline node-2 prompt 没有传递/提及这个参数，且 `human_approval` 门禁（节点 4）排在 write-competitive-report **之后**——报告和索引在审批门禁之前就已落盘，一旦驳回（`onFail:abort`）没有回滚机制。补：node-2 prompt 显式传 `confirmed=false`（先出草稿），把真正落盘挪到 human_approval 通过之后 |

> (G)(H)(I) 三组均涉及 crctl 核心代码，(J)(K) 涉及正确性缺口，全部由**本轮 7 条流水线执行走查**坐实，原审查（静态引用图 + 精读）未覆盖——因为它们只在"模拟真实执行、追问异常分支"时才会暴露，通读文档看不出来。

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
| pipeline-templates/code-implementation, architecture-design, requirement-authoring | push-progress 节点 prompt | 抽 shared | 「若=false 输出 SKIPPED…经 crctl checkpoint-add 更新 _backlog」样板多处逐字重复。抽成 push-progress skill 默认说明，节点只传差异参数——风险较低，因为引用目标是已存在且被复用的同一个 skill，不是新建的 shared 片段（本条落地前提是 2.1-G 先把 push-progress 自身的 checkpoint-add 矛盾修好，否则抽的是一段本身就错的样板） |
| skills/planning/write-insight-brief/SKILL.md | 全文 | 评估下线（可省略节点） | 正文六项（执行摘要/核心机会/风险与不确定性/建议关注方向/待人工决策问题）与 `extract-market-insight/SKILL.md:68-75` 的六项（原始素材摘要/关键信号/机会点/量化证据/可信度与局限/待验证问题）内容高度重叠，唯一硬性增量是「≤800 字」篇幅约束和 status `raw→briefed` 推进。建议评估把「简报」合并为 extract-market-insight 输出的附加区块，砍掉一个独立 skill + 落盘文件 + 索引状态跳变（本条为流水线执行走查新增） |
| skills/planning/run-competitive-analysis/SKILL.md | 15, 34-42 | 冗余（评估合并） | Step2/3 完全委托 `fetch-competitor-updates`/`write-competitive-report` 落盘，自有产出只剩 Step4「规划启示摘要」一段。三层调用（pipeline → run-competitive-analysis → fetch/write-competitive-report）里这层薄封装除摘要提炼外没有不可替代价值，可考虑把 Step4 并入 write-planning-report 的「市场与竞品信号」章节，省一层调用（本条为流水线执行走查新增） |
| skills/cr/list-remote-checkpoints/SKILL.md vs skills/sync/resume-from-remote/SKILL.md:34-53 | — | 冗余（可省） | resume-cr 节点 1（list-remote-checkpoints）对每个 active repo 做 `ls-remote` 存在性检查，缺失就 abort；节点 2（resume-from-remote Step1）又对每个 active repo 做同样的存在性预检，缺失同样 abort。节点 1 相对节点 2 真正的增量价值只有「checkpoints[] SHA 是否漂移」的告警，其余（分支是否存在）被节点 2 完整重做了一遍。可以让节点 2 直接复用节点 1 已产出的存在性结论，不重新查一遍（本条为流水线执行走查新增） |
| pipeline-templates/product-planning.pipeline.json:64,73,82,91 + 四个调研节点 SKILL.md 各自的跳过判断 | — | 抽 shared | 同一件「若 `skip_X=true` 则输出 SKIPPED 并 return」的逻辑在 pipeline node prompt（4处）和 SKILL.md（4处）里几乎逐字重复共 8 处，且措辞不完全对齐（pipeline 只说「输出 SKIPPED」，SKILL.md 还带 `skip_feedback=true` 这种回显格式），后续改一处不改另一处就会分叉。建议只在 SKILL.md 写一次，pipeline node prompt 改为引用而非重复全文（本条为流水线执行走查新增） |

### 2.4 🟢 歧义批（择要）

| 文件 | 行 | 类型 | 修改内容 |
|---|---|---|---|
| skills/cr/cr-show/SKILL.md | 91-110 | 修正 | 硬编码 status→下一节点映射表，与 CR-2026-021 D8「唯一收敛为 crctl next」冲突，易随状态机漂移；且该表**只覆盖到 code-approved**，完全没有 merging/writing-back/archived/rejected/withdrawn 几个状态——而 cr-show 恰恰是 resume-cr（接手在途 CR）流水线的收尾节点，正需要覆盖 writeback 期状态。`resume-cr.pipeline.json:62` 节点 prompt 自己就写着「不再本地维护映射表，跑 crctl next」，跟 cr-show 的实现自相矛盾（覆盖缺口为流水线执行走查新增坐实）。改调 `crctl next`，删硬编码表 |
| skills/shared/crctl/scripts/crctl.mjs（`cmdNext`） | 约 2220 | 修正 | `status=writing-back` 分支判断"追溯链已生成、可归档"时，检查的是 `change-requests/{cr}/traceability.yml`——这是 write-test-report 在 developing 阶段就写好的开发期工作稿，从 merging 一路带到 writing-back 全程存在，跟 writeback-traceability 有没有跑过毫无关系；真正应检查的是 writeback-traceability 的产物 `specs/{spec_id}/traceability.yml`。当前逻辑会让 `crctl next` 在 writeback-tasks/writeback-traceability 还没跑时就误判"可以归档"（`crctl advance --to archived` 的门禁 `gates.json:85-92` 最终会拦下来，但"建议"本身持续给错答案，来回试错。本条为流水线执行走查新增） |
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
| skills/requirement/requirement-register/SKILL.md | 77-94（Step 5） | 修正 | 错误表只覆盖 `EXEC_FAILED`/重复分支，未规定单仓 `fetch` 失败（如证书问题）时怎么办；正文却说「任一 active repo 创建失败时…不得继续写 PRD」。CR-2026-022 实录：multica `fetch` 因 SSL 证书校验失败，仍从**本地旧 main**（滞后于远端）派生 worktree 并继续执行——既违反「不得继续」的字面表述，产出的 worktree 也未标注其基线已过期。补一条：`fetch` 失败时降级为「从本地 trunk 派生，并在摘要输出中标注 `STALE_BASE`」，不是直接 abort，也不是静默视为成功 |
| skills/planning/write-planning-report/SKILL.md | 35 vs 90 | 修正 | Step1 规定"若某节点标记为 SKIPPED，对应章节填写'本次调研跳过此维度'"；错误处理表里"所有上游节点均 SKIPPED"这一情形却规定"各章节填写'数据不可用'"。同一个"节点被跳过"的条件，在"部分跳过"和"全部跳过"两种场景下给出两种不同占位文案，自相矛盾。统一为一种表述（本条为流水线执行走查新增） |
| pipeline-templates/competitive-radar.pipeline.json:61 vs market-to-plan.pipeline.json:60 | — | 修正 | 两条结构镜像的流水线里，职责等价的"转规划建议"节点（report-to-planning-suggestion vs planning-draft）`onFail` 策略相反（skip vs abort）。competitive-radar 允许失败后跳过继续跑，但下游 human_approval/write-planning-entry 的 prompt 都写死要读 node-3.md，一旦真的 skip 会读空文件。统一为 abort，或给 skip 分支补"文件不存在时的降级展示"（本条为流水线执行走查新增） |
| pipeline-templates/market-to-plan.pipeline.json | 59（节点 3） | 修正 | node-3 prompt 要求 planning-draft 输出"每条含标题/背景假设/成功指标/优先级（P0-P3）"，但 `planning-draft/SKILL.md` 优先级表只到 **P0-P2**（全文搜不到"P3"），且真实输出格式是固定 6 章节 DESIGN-DOC 而非"3-5 条建议列表"。pipeline prompt 凭空发明了一套跟技能真实契约不符的输出格式。改为如实引用 planning-draft 真实的 6 章节格式与 P0-P2 优先级（本条为流水线执行走查新增） |
| skills/competitive/report-to-planning-suggestion/SKILL.md | 47 | 修正 | "④ 委托 planning-draft → 传入 brainstorming 结论 + 产品快照"，但 `planning-draft/SKILL.md:26-30` 声明必填参数是 `context`（产品快照）和 `intent`（用户规划意图字符串）。"brainstorming 结论"不等于 `intent`，调用者要跳查才能发现参数对不上。改为明确"`intent`=从 brainstorming 结论提炼的一句话规划意图，`context`=产品快照"（本条为流水线执行走查新增） |
| skills/planning/write-planning-entry/SKILL.md | 16-21 vs 31-38 | 修正 | 参数表用 `target_version`（snake_case），但自己写出的索引字段是 `target-version`（kebab-case）——同一份文档内参数名和产物字段名对不上。且同一批 planning 域姐妹索引文件三套命名风格并存：write-planning-entry（kebab）/ extract-market-insight（snake）/ write-competitive-report（camelCase `competitorId`/`reportDate`）。建议至少让本文件内部先统一，姐妹文件风格统一列入批 4 冗余批一并评估（本条为流水线执行走查新增） |
| skills/sync/resume-from-remote/SKILL.md | 108-116 | 修正 | 错误表只处理了 stderr 含"already exists"的情形，建议改跑 pull-progress；但 `cr-archive/SKILL.md:130` 自己点名过 Windows 下 `git worktree remove` 因"Filename too long"失败会残留 `.git/worktrees/<name>` 元数据，挡下一个同名分支的 `worktree add`——这是"worktree 目录不存在但 git 认为它还注册着"的损坏态，报错文本不是"already exists"。补一行：命中"is not a valid path"等元数据冲突错误时，指引先跑 `git worktree prune` 清理残留元数据（本条为流水线执行走查新增） |
| pipeline-templates/resume-cr.pipeline.json | 44（节点 1 prompt） | 字段对齐 | prompt 让每个仓执行 `crctl git ls-remote --heads origin 'requirement/{cr_id}'`——按单 CR 过滤；但 `list-remote-checkpoints/SKILL.md` 参数表没有 `cr_id`/`filter_cr_id` 参数，Step1 描述的是全量 `ls-remote --heads origin 'requirement/*'` 扫所有在途分支、Step3 才做筛选。这个 skill 被设计成"看所有在途 CR"的通用查询工具，resume-cr 的 prompt 却悄悄把它改写成单 CR 查询。改为如实调用全量扫描+本地筛选，或给 skill 补一个可选的 `cr_id` 过滤参数（本条为流水线执行走查新增） |
| skills/develop/write-dev-plan/SKILL.md（章节 5 资源与分工）vs write-dev-tasks/SKILL.md:57（`estimate` 字段） | — | 修正 | plan.md 独立产出一次"估算总工时"，write-dev-tasks 又独立产出一次 TASK 级 `estimate` 求和，两处互不校验，可以静默不一致。建议 write-dev-tasks 生成后回填/核对 plan.md 的估算是否与 TASK 级求和一致，不一致则在错误表里给出 WARN（本条为流水线执行走查新增） |

---

## 三、修复批次建议（按优先级重排为可执行清单）

7 条流水线执行走查坐实了好几处 **crctl 本体的代码缺陷**（push-progress/checkpoint-add 矛盾、approve 驳回死路、review-loop 死配置），杠杆和风险都高于原有批次，因此在批 2、批 3 之间插入新的**批 2.5**，把所有「需要 crctl 新增能力或修状态机逻辑、必须过 ARCHITECTURE.md §8 评审」的项目收在一起，一次设计评审全部过审，不要拆成好几轮评审。批次编号在原有基础上插入，不打乱已执行/已引用的批 1/2/3/3.5/4。

### 批 1 —— 零风险机械修正（可直接改，无需评审）

- [ ] 2.1-A：`crctl advance` 命令串 12 处（review-requirement 按上文说明**省略** `--expect`，不要写死 `drafting`）
- [ ] 2.4：`<!-- lint-prompts:ignore -->` 注释外移（review-code / requirement-register:17 / implement-code:77，共 3 处）
- [ ] 2.2：`pipeline-templates/_index.yml:118` 的 `tools/old/` 死引用行、`agents/knowledge-agent.md:39` 的 validate-doc 死路径
- [ ] 2.4：requirement-register「三件事→四件事」编号补齐、merge-feature-branch「两阶段→四阶段」措辞澄清、spec-dashboard 状态分布表补全六个漏列状态

风险：**零**（纯机械文本修正）。

### 批 2 —— 死内容清理（低风险，删除前需确认无外部读者）

- [ ] cr-status-set 整体下线 / 标 deprecated（`skills/_index.yml:287` 同步）
- [ ] `skills/_index.yml:281` cr-review-record brief 改「经 crctl advance 推进」
- [ ] validate-doc 死维度（默认删除「gate 合规性」这条，除非能给出排期 TASK/CR 编号）+ 移除 writeback-* 自动调用的失实声明
- [ ] focus-briefing 两处反向修（status:new 由 write-competitive-report 补写，而非去掉过滤；pipeline 注册表路径先向运行时确认，确认不了就整体删数据源）
- [ ] report-to-planning-suggestion 补具体降级路径（brainstorming 缺席时委托 planning-draft）
- [ ] `agents/_index.yml` 5 处 `pending` 能力清空为 `[]`（保留键，不删）
- [ ] `record-adr`/`adrs.yml` 确认无读者后评估整体删除

风险：低，但 cr-status-set、`adrs.yml` 两项动手前必须先确认无外部读者。

### 批 2.5（新）—— crctl 核心能力补齐与缺陷修复 —— 本轮最高优先级，需**一次性**设计评审

这一批全部涉及 crctl.mjs 核心代码或状态机语义，触发 ARCHITECTURE.md §8 门槛，**不是文档整理**；建议合并成一份技术设计一次评审通过，理由是它们互相独立、不冲突，分批评审只会增加沟通成本。

- [ ] **(2.1-F) cr-init 缺字段写口**：`cr-init` 补 `--summary --source [--target-version]` 三个可选旗标，一次原子写齐；删 `requirement-register/SKILL.md:28` 的 `cr_id` 死参数与对应校验
- [ ] **(2.1-F) `--template` 反向解析**：`resolveTemplateCr` 补显式 `--cr <cr-id>` 旗标，调用方直传已知值，跳过「分支名探测→subject 正则兜底」
- [ ] **(2.1-G，最高杠杆，一处改动惠及 3 条流水线)**：
  1. `cmdCheckpointAdd` 的 `LEGAL` 状态白名单扩到覆盖所有存在 push-progress 节点的非终态（含 `drafting`/`requirement-reviewing`/`task-breakdown` 等）
  2. `push-progress/SKILL.md` Step 3 改为对每个 active repo 显式循环调用 `crctl checkpoint-add --repo <r> --sha <sha>`，删除「展示 YAML 让人抄」的写法
  3. `code-implementation.pipeline.json:217`（节点 12）补齐 checkpoint-add 调用描述，与节点 3/8 保持一致
  4. 三处 push-progress 节点 `onFail` 从 `skip` 改为产出可见告警（不宜直接 abort）
- [ ] **(2.1-H) approve 驳回死路**：
  1. **先决策**：需求阶段状态机是否新增 `requirement-reviewing:reject -> drafting` 转换（当前唯一出口是直接判 CR 死刑）
  2. `cmdApprove` 的非 TTY-yes 分支改为真正调用状态机已声明的 `{stage}:reject -> write-{stage}` 回退转换，不再只是 `fail('APPROVAL_DECLINED')`
  3. 四份 approve-*/SKILL.md 错误处理表补「审批人回答非 yes」分支，与状态机实际转换对齐（尤其 approve-dev-start 现有的"重跑 write-dev-plan"建议在状态机上不可达，需订正）
  4. approve-requirement 改正"无旁路"表述（`--grant` 签发是官方设计的旁路，不是漏洞）
- [ ] **(2.1-I) review-loop 死配置**：决定 review-planning-report 的 attempts 记账是否正式接入 crctl（需要一条不依赖 CR 上下文的持久化子命令），或删除 `gates.json:100` 的死配置、如实描述当前的自行落盘机制；同步删除 `product-planning.pipeline.json:109` 里"必须持久化"的失实承诺
- [ ] **(2.4) requirement-register Step 5**：`fetch` 失败降级为「从本地 trunk 派生，标注 `STALE_BASE`」，不是直接 abort 也不是静默视为成功

风险：中（crctl 新增/修改核心写入与状态机逻辑）。**建议随 CR-2026-022 一并提交技术设计**，且应先于批 3/批 4 落地——批 3 的几项功能修复不依赖这批，可以并行推进，但批 4（抽 push-progress 节点样板）必须等这批把 push-progress 本身修对之后再抽，否则抽的是一段本身就错的样板。

### 批 3 —— 功能正确性修复（中风险，逐项验证）

批内按「功能断裂者优先」排序：(B)(J)(K) 三项直接造成通知链断裂/合并证据缺失/审批门禁被绕过，排在批首。

- [ ] 2.1-B：inbox-emit 接口对齐（三处枚举同步：触发意图列表 + 参数表 + 下游消费方）
- [ ] 2.1-J（新）：`merge-feature-branch` 补本地/远端 HEAD 一致性校验（Step1.4 增加 `git rev-parse` 比对）——**与 2.1-G 直接联动**：push-progress 静默失败未被完全堵死前，此校验是防止「合并缺最后一次提交的远端分支」的最后一道防线
- [ ] 2.1-K（新）：`write-competitive-report` 写入目标从 `docs/competitive/_index.yml` 修正为 `docs/competitive/reports/_index.yml`；`confirmed` 两阶段确认协议调整到 human_approval 之后再落盘（**涉及两阶段确认协议被绕过，可能导致审批门禁失效**）
- [ ] 2.1-C：pipeline UUID 撞号（5 节点整体迁移到 `0016-*` + `repairNodeId` 同步）
- [ ] 2.1-D：market-insights 索引统一（`insights:` / `MARKET_INSIGHT` / `raw→briefed→published`），**含新增的 `market-to-plan.pipeline.json:76` 终态 `planned`→`published` 修正**
- [ ] 2.1-E：sync 手写 owner 变更改调 `crctl owner-set`（handover-cr + resume-from-remote）
- [ ] 2.4（新）：`cmdNext` 的 `writing-back` 分支改查 `specs/{spec}/traceability.yml` 而非开发期工作稿
- [ ] 2.4（新）：cr-show 硬编码表补齐 merging/writing-back/archived/rejected/withdrawn 几个状态（或直接改调 `crctl next`，一步到位）
- [ ] 2.4（新）：write-planning-report 的 SKIPPED 占位文案统一（"部分跳过"与"全部跳过"目前是两种不同措辞）
- [ ] 2.4（新）：competitive-radar/market-to-plan 的 `onFail` 策略统一（skip vs abort 二选一，并处理 skip 分支的空文件降级）
- [ ] 2.4（新）：`report-to-planning-suggestion` 委托 `planning-draft` 的参数改为如实传 `intent`/`context`；`market-to-plan.pipeline.json:59` 的输出格式描述改为 planning-draft 真实的 6 章节 + P0-P2
- [ ] 2.4（新）：`resume-cr.pipeline.json:44` 改为如实调用 `list-remote-checkpoints` 的全量扫描逻辑（或给该 skill 补可选 `cr_id` 过滤参数）
- [ ] 2.4（新）：`resume-from-remote` 错误表补"worktree 元数据残留（非 already-exists）"分支，指引先跑 `git worktree prune`
- [ ] 2.4（新）：write-dev-plan 与 write-dev-tasks 的工时估算补交叉校验（不一致给 WARN）

风险：中（涉及接口/枚举/结构约定，多数是正确性修复不只是文档整理）。需逐项对照目标形态验证。

### 批 3.5 —— lint 护栏先行（低风险，但决定后续批次是否可信）

- [ ] 补 R6（`crctl advance` 参数格式校验）、R7（`inbox-emit` 接口/枚举校验），校验范围同时覆盖 `backlog-set` 字段白名单与 `--template` 的 subject 编号规则（不能只锁死 `advance`/`inbox-emit` 两个命令名）
- [ ] **（新）修复 lint-prompts 自身 bug**：`<!-- lint-prompts:ignore -->` 的豁免判断从"整段 `node.prompt` 生效"收窄到"只豁免邻近行"，否则 R5（及新增的 R6/R7）在 pipeline JSON 里可能被无关的豁免注释连带误伤放行
- [ ] 补 `lint-prompts.test.mjs` 测试向量（含新豁免范围场景）

风险：低。**必须在批 4 之前落地**——在批 4 大改动前先建立护栏，且护栏本身的漏洞（豁免范围 bug）也要先堵上，否则批 4 引入的新漂移可能既过不了 R6/R7、又被豁免范围 bug 放行。

### 批 4 —— 冗余批（中高风险，改动面最大）

- [ ] 按「先对齐、必要才抽」原则处理 approve-* 四兄弟
- [ ] 抽 writeback 三兄弟共享片段
- [ ] sync 免责声明部分收敛（保留 SHELL_UNAVAILABLE 摘要）+ bucket 计算改调 `crctl worktree-path`
- [ ] 删 `agents/_index.yml` 冗余 constraints
- [ ] 抽 pipeline push-progress 节点样板（**前提：批 2.5 已把 push-progress 自身的矛盾修好**）
- [ ] （新）`write-insight-brief` 评估下线，合并进 `extract-market-insight` 的附加区块
- [ ] （新）`run-competitive-analysis` 评估合并，把 Step4 摘要并入 write-planning-report
- [ ] （新）`list-remote-checkpoints`/`resume-from-remote` 去重存在性校验（后者直接复用前者结论）
- [ ] （新）`product-planning` 四调研节点的「跳过检查」逻辑只在 SKILL.md 保留一份，pipeline node prompt 改引用

风险：中高（改动面最大）。前置条件：批 3.5 的 lint 护栏必须先落地；且需先给 lint 补「shared 引用一致性」检查，否则把「N 处漂移」换成「引用失效」。

### 收尾 —— 台账同步与自检（低但必做）

- [ ] 按 AGENTS.md 要求同步三台账（`skills/_index.yml`、`agents/_index.yml`、`agent-skill-matrix.yml`）
- [ ] 跑 `check-skill-matrix.mjs`
- [ ] 对改过 UUID/节点数的 pipeline 做 JSON 解析自检
- [ ] 批 2.5 落地后跑 `crctl.test.mjs` 全量回归（`LEGAL` 状态白名单扩展、`cmdApprove` decline 分支改动都是核心路径，必须有测试覆盖新分支）

### CR 必要性判据 —— 哪些改动可以现场直改，不必登记 CR

**判据（四条同时满足才算「纯提示词」）**：
1. 不修改 `crctl.mjs`（不新增/改写子命令，不改状态机 `LEGAL` 状态表或转换定义）；
2. 不定义/变更**多个 skill 共享**的数据 schema（字段名、枚举、状态生命周期）——即使改动形式是编辑 SKILL.md 文本，只要这段文本在「教下游怎么写一份大家共用的文件」，性质上就是接口契约变更，不是纯措辞；
3. 不改变 pipeline 节点数量/顺序/UUID（哪怕只改一个内部 ID 值，也可能影响 seed 幂等）；
4. 改动范围收在单个 skill 自身的文本/步骤内，不会因为漏改另一个文件而重新产生漂移。

四条都满足 → 可现场直改，走正常 PR/commit 即可，不必登记为 CR。这个判据是 ARCHITECTURE.md §8「普通 Skill 文档措辞调整…不需要改本文档」的自然延伸，本报告把它落到具体批次上：

| 批次 | 是否需要走 CR | 理由 |
|---|---|---|
| 批 1（命令串/frontmatter/编号） | **否** | 纯文本修正，照抄既有 crctl 接口，四条判据全满足 |
| 批 2（死内容清理） | **否** | 纯文本/YAML doc-only；删除 `cr-status-set`、`adrs.yml` 前需先确认无外部读者，但这是尽职调查，不是 CR 门槛 |
| 批 2.5（crctl 核心能力/缺陷修复） | **是** | 全部改 `crctl.mjs` 核心代码或状态机语义（判据 1 不满足），明确触发 §8，必须走设计评审 |
| 批 3（功能正确性修复） | **视具体项** | 见下方拆分，不能整批一刀切 |
| 批 3.5（lint-prompts 修复） | **否，但要走正常代码评审** | 改的是治理工具脚本代码，不是提示词，也不是 crctl 写入路径/状态机——不必登记 CR，但要有 PR review + 测试，不能"现场改完直接合" |
| 批 4（冗余/抽 shared） | **否** | 纯文本合并/抽取；新建的 `shared/approve-common` 之类文件属于既有 `shared/` 组内新增文件，不构成"新增顶层分组" |
| 收尾 | **否** | 台账同步/自检，本身就是收尾动作 |

**批 3 拆分**（这一批是混合的，逐项判定）：

- **可现场直改**（纯文本，判据全满足）：inbox-emit 接口对齐、sync owner-set 改调、merge-feature-branch HEAD 校验补充、write-competitive-report 写入目标修正、cr-show 硬编码表补齐、write-planning-report SKIPPED 文案统一、report-to-planning-suggestion/planning-draft 参数对齐、resume-cr 过滤范围修正、resume-from-remote 损坏处理补充、write-dev-plan/write-dev-tasks 估算交叉校验。
- **需要单独留意的灰色地带**（不是不能改，是不能当"纯文本"那样轻描淡写地改）：
  1. **`cmdNext` 的 writing-back 路径 bug**——这是 `crctl.mjs` 里的可执行代码，判据 1 不满足。它不新增能力、不改状态机，性质接近"只读逻辑 bug 修复"而非"新增写入子命令"，§8 字面条款没直接覆盖这种情况。**建议**：不必登记 CR，但必须有代码 review + `crctl.test.mjs` 补测试用例，不能"现场改了就直接合并"。
  2. **market-insights 索引 schema 统一**——形式上是改三份 SKILL.md 的文本，实质是给三个 skill 共用的数据文件定契约（判据 2 不满足），这正是它当初漂移出来的原因。**建议**：不必登记 CR，但三份文件必须**同一个 commit 原子提交**，不能像最初那样分开改；若 `docs/market-insights/_index.yml` 已有历史数据用旧字段名，还需要一步一次性迁移（脚本或手工），这一步要单独在 PR 描述里写清楚，不能悄悄发生。
  3. **pipeline UUID 撞号修复**——改的是 JSON 里的内部 ID 值和 `repairNodeId` 自引用，不是 prose，但也没有改变节点数量/顺序，严格说不构成 §8 定义的"Pipeline 结构性变化"。**建议**：不必登记 CR，但风险不低（同时影响两条流水线的 seed 幂等），改完必须跑一次 JSON 解析自检 + 两条流水线各自的手工验证，不能只凭 diff review 就合并。
  4. **competitive-radar/market-to-plan 的 `onFail` 策略统一**——改的是配置值（`skip`→`abort` 或反之），不是 prose，也不新增字段，但这是**运行时行为变更**：原来会被静默吞掉的失败，改完之后会真的中止流水线。判据本身不禁止现场改，但**建议改动时在 PR 描述里明确标注"这会让 XX 场景从静默跳过变成真的中止"**，让评审人知道这不是纯粹的措辞调整，避免被当成无害的文本 PR 一带而过。

一句话总结：**批 1/2/4 可以放心现场改；批 2.5 必须走 CR；批 3 里"改哪个文件"是文本、"改的是什么"才决定要不要开 CR**——凡是touch 到 `crctl.mjs`、touch 到多个 skill 共用的数据契约、或者改变了运行时行为（哪怕只改一个配置值），都值得停下来多想一步，而不是看 diff 是 Markdown 就默认"纯提示词，随手改"。

---

## 四、技术实现方案（批 2.5 与批 3.5 核心项）

本节给出需要改 crctl 代码/lint 代码的各关键项的参考实现骨架，用于统一修复方向的理解；**最终实现以 ARCHITECTURE.md §8 技术设计评审通过的方案为准**，伪代码不构成评审输入本身。

### 4.1 (2.1-G) push-progress/checkpoint-add

**① `cmdCheckpointAdd` 的 `LEGAL` 白名单扩展**（crctl.mjs，覆盖所有存在 push-progress 节点的非终态）：

```javascript
const LEGAL = [
  'drafting', 'requirement-reviewing', 'requirement-approved',
  'tech-designing', 'tech-design-review-pending', 'tech-design-reviewed',
  'task-breakdown',
  'developing', 'code-reviewing', 'code-approved',
  'merging', 'writing-back'
];
```

明确列出全量非终态而非「drafting 等」式枚举，避免实现时遗漏某个阶段再次炸 `ILLEGAL_LEDGER_STATE`。

**② `push-progress/SKILL.md` Step 3** 改为对每个 active repo 显式循环调用，删除「展示 YAML 让人抄」：

```text
对每个 active repo：
1. sha = git rev-parse HEAD
2. crctl checkpoint-add --repo <repo-name> --sha <sha>
3. 禁止手工编辑 _backlog.yml
```

**③** `code-implementation.pipeline.json` 节点 12 补齐 checkpoint-add 描述（与节点 3/8 一致）；三条流水线的 push-progress 节点 `onFail` 从 `skip` 改为产出可见告警——**不宜直接 abort**，因为 git push 本身可能已成功，abort 会造成更大的状态混乱。

### 4.2 (2.1-H) approve 驳回回退

`cmdApprove` 的 decline 分支改为查表执行状态机已声明的回退转换：

```javascript
if (answer !== 'yes') {
  const t = findRejectTransition(stage, currentStatus); // 查 "{stage}:reject -> write-{stage}"
  if (t) {
    await executeAdvance(t.to, `${stage}:reject -> write-${stage}`);
    log(`APPROVAL_DECLINED，CR 已回退到 ${t.to}，请重跑对应 write skill`);
  } else {
    fail('APPROVAL_DECLINED', '审批人未确认，且状态机未声明回退转换');
  }
}
```

**前置决策**（本节唯一需要产品/架构拍板的点）：需求阶段是否新增 `requirement-reviewing:reject -> drafting` 转换。不做决策，approve-requirement 的回退路径无从落地——decline 分支查到该 stage 无回退转换时只能继续 fail，等于没修。

### 4.3 (2.1-F) cr-init 字段写口 + --template 显式 CR 号

```javascript
// cmdCrInit 补可选旗标，注册时一次原子写齐
// 新增旗标：--summary <s>  --source <s>  [--target-version <v>]
// 缺省值与现硬编码同义：summary="" / source=manual / target-version=tbd（向后兼容既有调用）

// resolveTemplateCr 优先显式旗标，跳过反向解析
if (flags.cr) return flags.cr;   // 调用方直传已知值（requirement-register Step 2 已拿到 cr_id）
// 原有「分支探测 → subject 正则兜底」保留为兜底路径，不破坏存量调用
```

同步删除 `requirement-register/SKILL.md:28` 的 `cr_id` 死参数及其对应的格式/占用校验（cr-init 内部 `scanMaxCrNumber+1` 才是权威分配）。

### 4.4 (批 3.5) R6/R7 规则骨架

```javascript
// R6：crctl advance 参数格式校验
// - 必须匹配 --to\s+\S+ 与 --trigger\s+\S+
// - LITERAL_BLACKLIST：trigger= / expected_current_status= / commit_mode=
// - 全角字符 ，、） 判违例
// - 旗标用反引号包裹判违例
// - 校验范围不锁死 advance 一个命令：backlog-set 字段白名单、
//   --template 的 subject 编号规则同样纳入（CR-2026-022 实录坐实的同类漂移）

// R7：inbox-emit 接口校验
// - 函数式 inbox-emit( 直接判违例
// - CLI 形态校验 --event 取值属于 inbox-emit/SKILL.md 声明的枚举
```

### 4.5 (批 3.5) `<!-- lint-prompts:ignore -->` 豁免范围收窄

```javascript
// 豁免判断从「整段 node.prompt 生效」改为「逐行判断，只豁免注释所在行的邻近范围」
function isIgnored(lines, i, radius = 1) {
  for (let k = Math.max(0, i - radius); k <= Math.min(lines.length - 1, i + radius); k++)
    if (lines[k].includes('<!-- lint-prompts:ignore -->')) return true;
  return false;
}
```

`radius` 取值需在测试向量中固化（邻近行边界本身就是契约）。`lint-prompts.test.mjs` 同步补三类测试向量：R6 违规（全角字符 / 反引号旗标 / 缺 `--to` 或 `--trigger`）、R7 违规（函数式调用 / 枚举外 event）、豁免范围（豁免注释与违规行同段时违规行仍须命中，复现 `product-planning.pipeline.json:109` 场景）。

### 4.6 (2.1-B) inbox-emit 三处同步的文档结构

```text
inbox-emit/SKILL.md：
  ① 触发意图列表：补 owner-handover（CR 负责人移交）
  ② 输入参数表：event 枚举补 owner-handover；to 必填，取值来源写明
     （CR owners.*.id 或 feedback 发起人），否则接口修完 AI 仍不知道该填谁
  ③ 下游消费方：声明 handover-cr 为 owner-handover 的消费方

handover-cr/SKILL.md Step4 迁到 CLI 形态：
  crctl inbox-emit <cr-id> --event owner-handover \
    --to <new-owner-id> --payload '{"subject": "...", "body": "...", "from": "..."}'
```

---

## 五、风险控制措施

### 5.1 回滚方案

| 批次 | 回滚策略 |
|---|---|
| 批 2.5 | 所有 crctl.mjs 核心改动保持**单 commit 可 revert**；状态机转换声明（dir-graph.yaml）改动前留存改动前版本对照；发现严重问题直接 revert 对应 commit——依赖 git 本身回滚，与「git commit 本身即历史与审计」纪律一致，不另制备份目录 |
| 批 3 | market-insights 索引 schema 统一前，先核实 `docs/market-insights/_index.yml` 是否有旧字段名历史数据，有则准备一次性迁移脚本（入库、版本化，遵守「账本操作禁止会话内现写脚本」纪律）并在 PR 描述写清；pipeline UUID 撞号修复后若 seed 幂等被破坏，revert UUID 值重新分配前缀 |
| 批 3.5 | lint 规则改动为纯增量；若 R6/R7 误报过多，先降级为 warning 输出，规则修准后再启用阻断，避免护栏本身阻塞正常工作流 |

### 5.2 监控与告警

| 指标 | 修复后预期 | 告警触发 |
|---|---|---|
| `crctl checkpoint-add` 调用成功率 | 接近 100% | push-progress 节点 `onFail` 告警触发时通知 CR owner |
| approve 驳回回退转换执行率 | 状态机声明转换的 stage 为 100% | decline 分支执行失败时告警审批人与工具维护者 |
| lint-prompts R6/R7 命中数 | 批 1/批 3 完成后收敛为 0 | 持续非零命中即新漂移信号，纳入每周扫描跟踪 |
| lint 豁免注释 | 无「无关行被连带豁免」 | 发现误放行即告警工具维护者 |

### 5.3 灰度推进

批 2.5 改动 crctl 核心写入路径与状态机语义，建议先以**测试 CR**（或一次完整的演练注册，形式参照 CR-2026-019 AC-9 演练入库）走一遍「push-progress → checkpoint-add 落账」「approve 驳回 → 回退转换」「cr-init 新旗标原子写入」三条新路径，验证通过后再对全部在途 CR 生效。

---

## 六、后续验证计划

### 6.1 分阶段验证（与批次对应）

| 阶段 | 批次 | 验证方法 | 验收标准 | 预计时长 |
|---|---|---|---|---|
| 1 | 批 1 + 批 2 | diff review + lint-prompts 自检 | 12 处命令串全部符合权威旗标；frontmatter 内无豁免注释；死引用清零 | 1-2 天 |
| 2 | 批 3.5 | `lint-prompts.test.mjs` 全量 + 用新规则复扫批 1/2 改动面 | R6/R7 能命中全部已知违规形态；豁免范围 bug 修复（含 4.5 测试向量通过） | 2-3 天 |
| 3 | 批 2.5 | `crctl.test.mjs` 全量回归 + 模拟执行 3 条流水线 push-progress 节点 + 模拟 4 个 approve-* 驳回场景 + 模拟 requirement-register 注册 | 全部非终态 checkpoint-add 可用；驳回正确回退；cr-init 三字段一次写齐；`--cr` 直传跳过反向解析 | 5-7 天（含设计评审） |
| 4 | 批 3 | 逐项对照目标形态验证 | owner-handover 通知可发出；market-insights 三写入方读写正常；UUID 不撞号且 seed 幂等恢复 | 3-5 天 |
| 5 | 批 4 | lint「shared 引用一致性」检查 + JSON 解析自检 + 引用计数 | 无死引用；pipeline 解析无错误；无新增漂移 | 3-5 天 |

### 6.2 端到端验收测试

**场景 1：完整 CR 生命周期**（串联验证批 2.5 F/G/H、批 3 J、2.4 cmdNext 修复）：注册（cr-init 新旗标）→ 需求编写（checkpoint-add 真被调用）→ 需求审批驳回（回退转换执行）→ 技术设计审批通过 → 代码实现（checkpoint-add）→ 代码审批驳回（回退 developing）→ 合并（HEAD 不一致时校验拦截，要求补跑 push-progress）→ 回写（writeback 未跑完时 `crctl next` 不再误判「可归档」）。

**场景 2：通知链完整性**：`feedback-writeback-done` 与 `owner-handover` 各发送一次，验证接收方收件可见。

**场景 3：lint 护栏有效性**：故意注入三类违规（全角字符命令串 / 函数式 inbox-emit / 豁免注释同段内的 R5 违规行），验证 R6/R7/R5 分别命中且不被连带豁免。

### 6.3 回归测试计划

**每次改动后必跑**：

```bash
node ../tools/skills/shared/crctl/scripts/crctl.test.mjs
node ../tools/skills/shared/crctl/scripts/lint-prompts.test.mjs
node ../tools/skills/shared/scripts/check-skill-matrix.mjs
# 另对每个改过的 pipeline 做一次 JSON 解析自检
```

**每周一次**：全仓 `lint-prompts.mjs` 全量扫描，跟踪 R6/R7 命中数收敛趋势。

### 6.4 文档更新计划

| 时机 | 更新内容 |
|---|---|
| 批 2.5 落地后 | ARCHITECTURE.md §8 评审记录；crctl/SKILL.md（cr-init 新旗标、`--cr` 旗标）；四份 approve-*/SKILL.md 错误表补「审批人回答非 yes」分支，且与状态机实际转换逐一对齐 |
| 批 3 落地后 | inbox-emit/SKILL.md（owner-handover 枚举三处同步）；market-insights 索引头「单一事实源」声明；merge-feature-branch/SKILL.md 补 HEAD 一致性校验步骤 |
| 批 3.5 落地后 | lint-prompts.mjs 头部规则说明（R6/R7 + 豁免范围契约）；测试向量 |
| 批 4 落地后 | AGENTS.md 抽 shared 原则；skills/_index.yml 新增 shared 条目 |

---

## 七、长期改进建议

1. **关键成功因素**（重申，防执行期走样）：批 2.5 一次设计评审全过（各项互相独立、不冲突，分批评审只增沟通成本）；批 3.5 护栏必须在批 4 之前落地；批 4 抽 push-progress 节点样板必须等批 2.5 把 push-progress 本身修对。
2. **风险缓解**：批 2.5 先经测试 CR 灰度验证（见 5.3）再对全部在途 CR 生效；所有核心改动保持单 commit 可 revert。
3. **方法论改进**：静态引用图分析对**入口/单次性流程类 skill、被多条流水线复用的公共 skill、审批/驳回等异常路径**存在系统性盲区——正常路径写得对、异常路径无路可走这类问题，通读文档看不出来，须配合至少一次实际执行走查（本轮 CR-2026-022 实录与 7 条流水线走查已两次坐实）。建议把「每条新流水线首次启用前做一次逐节点执行走查」固化为流程纪律。
4. **工具链完善**：给 lint-prompts 补「shared 引用一致性」检查（引用是否仍指向真实 shared 片段），否则批 4 会把「N 处漂移」换成「引用失效」，风险不降反升。
5. **文档规范**：凡写入 SKILL.md/pipeline prompt 的 crctl 命令与字段描述，落笔前必须回 `crctl.mjs` 源码坐实，不采信 SKILL 文档自身描述——本报告的 97 条发现中，高危项全部是「SKILL 描述 ≠ crctl 实际行为」的变体。

---

## 八、审查覆盖与方法附录

- **引用图**：对 59 个 skill id 做全仓引用计数，最低者 `focus-briefing`(1)/`record-idea`(2)/`cr-inbox`(2) 逐一坐实——均有产物下游读者，无纯死 skill。
- **反向校验**：8 个 pipeline 的 37 处 `"ref"` 全部命中真实 skill，无拼错/死引用（node UUID 撞号除外）。
- **亲验项**（不依赖 agent 判断，已用源码/grep 坐实）：crctl advance 权威旗标与 `--expect` 单值语义（`cmdAdvance` 源码）、12 处坏命令串精确行号、inbox-emit 真实入参、pipeline UUID 撞号、`requirement-reviewing` 自环转换（`dir-graph.yaml`）、`architecture-design.pipeline.json` 的 `repairNodeId` 自引用、UUID 前缀占用表。
- **两处判断修正**（均已体现在上文对应小节，不再单列）：
  1. `focus-briefing` 最初按「零引用」疑似可删，经查它是 `focus.yml` 唯一写入者、而 `focus.yml` 被 analyze-current-product / gather-product-context 读取，**改判不可删**。
  2. 原稿曾建议 review-requirement:91 写死 `--expect drafting`，经核对状态机自环转换定义后**改判为省略 `--expect`**（见 2.1-A）；同批还纠正了 architecture-design 的 UUID 迁移范围（全部 5 节点而非只改撞号的 3 个，且必须同步 `repairNodeId`）、sync 组的 owner 变更问题定性（由「冗余」改判为「正确性缺陷」，移入高危批）、以及 focus-briefing/report-to-planning-suggestion/validate-doc 三处死内容的修复方向（均改为「先确认或反向修」而非直接删/直接标注）。
- **CR-2026-022 补充坐实（2.1-F、2.4 Step 5）**：来源 `docs/analysis/CR-2026-022-注册流程复盘.md`——这是本报告注册为 CR 后的一次真实注册执行记录，不是二次通读。它暴露了原方法论的一个盲区：引用图静态分析 + 精读覆盖的是「skill 之间怎么互相引用」，没有覆盖「入口 skill 自身被实际执行一遍会撞上什么」——`requirement-register` 恰好是全仓唯一的流程入口节点，静态分析反而对它扫得最浅（原稿 2.4 只抓到编号跳号这类表面问题）。**结论**：静态引用图分析对入口/单次性流程类 skill 有系统性盲区，宜配合至少一次实际执行走查。
- **7 条流水线执行走查（2.1-G/H/I/J/K 及 2.3/2.4 新增各项）**：针对除 requirement-register 之外的全部流水线（架构设计/代码实现前后半段/需求编写剩余节点/回写+接手/竞品雷达+洞察转规划/调研规划），派 7 组并行精读，方法与 CR-2026-022 一致——不满足于通读找 typo，而是逐节点模拟「照着这份 SKILL.md 执行的人/AI 走到这一步会不会卡住、矛盾、多此一举」，任何涉及 crctl 命令/字段的判断都回 `crctl.mjs` 源码坐实，不采信 SKILL 文档自身的描述。**这一轮的性质与前两轮不同**：CR-2026-022 暴露的是「入口 skill 文档写错了」，这一轮暴露的是**crctl 本体的代码缺陷**——`push-progress` 从未真正调用它自己承诺的 `crctl checkpoint-add`（且 `checkpoint-add` 的状态白名单本就覆盖不到 push-progress 实际被调用的阶段）、`cmdApprove` 的驳回分支从不执行状态机声明的回退转换、`review-planning-report` 的 reviewLoop 在 `gates.json` 里是从未被调用的死配置，外加 lint-prompts 自身「豁免注释整段生效」的 bug——这些都不是靠改 SKILL.md 文案能解决的，需要过 ARCHITECTURE.md §8 评审并改 crctl.mjs 核心代码（见「三」批 2.5）。**结论**：静态方法论的盲区不止「入口 skill」一类，任何被多条流水线复用的公共 skill（push-progress）、任何声明了但缺少调用方的 gate 配置（reviewLoop）、任何审批/驳回这类"异常路径"，都需要执行走查才能发现——通读文档看不出"正常路径写得对、异常路径无路可走"这种问题。

---

## 九、97 条发现落地核对表（CR-2026-022 实施期追加，2026-08-06）

> 本 CR 全量落地 97 条发现（不采纳「批 1/2/3.5/4 可现场直改」分流，PRD §1.2 口径）。tools 仓提交链：`f0b8a54`（批 1）→ `e5bcb31`（批 2）→ `73250dd/acdcfc0/a1c36e2/199e3b8/1192c0b`（批 2.5）→ `42a518b/de65bbc`（批 3）→ `905eb63`（批 3.5）→ `f103e61/114cf97/3308d14`（批 4）→ `62f34d8`（收尾文档）；multica `cf43f14f8`（transitions_gen.go 重生成）；主仓 AGENTS.md #2 口径 25/47。

| 批次 | FR | 落地内容 | 验证 |
|---|---|---|---|
| 批 1 | FR-1~3 | 12 处命令串权威形态（review-requirement 省 --expect）；豁免注释移出 frontmatter/并入关联行；tools/old 与 validate-doc 死引用清零；三件事→四件事、两阶段→四阶段、spec-dashboard 状态表补齐 | lint R7 复扫零命中；反引号配对校验全过 |
| 批 2 | FR-4~8 | cr-status-set/record-adr 下线（matrix/QODER/agent 引用同步清退）；validate-doc 死维度与失实声明删除；focus-briefing 反向修（status:new 生产侧补齐 + 消费翻转 seen + 删不可确认数据源）；pending 清空；降级路径 | 55 active skills matrix 一致；cr-status-set 仅历史文档/黑名单残留 |
| 批 2.5 | FR-9 | cr-init 三旗标（缺省同义）+ cr_id 僵尸参数删除 + pipeline 提示对齐 | 测试：三旗标一次写齐 + 缺省兼容 |
| 批 2.5 | FR-10 | --cr 显式直传 + COMMIT_TEMPLATES 形态对齐白名单（现场坐实修复） | 测试：master 直传/非法格式拒绝/模板白名单 |
| 批 2.5 | FR-11 | checkpoint-add LEGAL 状态机派生 + push-progress Step 3 逐仓调用 + CHECKPOINT_ALERT + 节点 12 补齐 | 测试：终态拒绝/非终态可用；CR-2026-022 真实落账 |
| 批 2.5 | FR-12 | 状态机两条 reject 转换（25/47）+ REJECT_ROLLBACK 回退 + 四 approve-* 错误表 + 无旁路表述 | 测试：四 stage legalNext 含 reject 转换；multica gen 重生成 |
| 批 2.5 | FR-13 | gates.json 死配置删除 + node-6 承诺订正与 R5 违规面清理 | JSON 解析通过 |
| 批 2.5 | FR-14 | fetch 失败 STALE_BASE 降级 | lint 复扫零命中 |
| 批 3 | FR-15 | inbox-emit 三处同步（owner-handover）+ 两调用方迁 CLI | lint R8 复扫零命中 |
| 批 3 | FR-16/17 | HEAD 一致性校验；competitive-radar 两阶段确认 + reports/_index.yml 目标 | 文档落地 |
| 批 3 | FR-18 | UUID 0014→0016 全量迁移含 repairNodeId | JSON 解析 + 无撞号（resume-cr 0014 保留） |
| 批 3 | FR-19 | market-insights 统一 schema + 单一事实源声明 + 节点 5 终态 published | 三写入方对齐 |
| 批 3 | FR-20~22 | owner-set 改调；cmdNext writing-back 改查 specs 产物；cr-show 收敛 crctl next | 测试：cmdNext 三分支 |
| 批 3 | FR-23 | 八项歧义订正（SKIPPED 文案/onFail abort/intent-context/6 章节 P0-P2/cr_id 过滤/worktree prune/估算交叉校验） | lint 复扫零命中 |
| 批 3.5 | FR-24~26 | lint R7/R8（命令形态+inbox-emit 接口，判据直读）+ 豁免 ±1 行契约 + 5 类测试向量；存量 10 处违例修复 + write-test-report R5 手写块清理（报告 2.4 补漏项） | lint 15 + crctl 87 用例全绿；全仓 0 findings |
| 批 4 | FR-27/28 | approve-* 对齐（删前置条件节）；writeback 抽 shared 评估定案不抽（报告 2.3 原则 2） | lint 复扫零命中 |
| 批 4 | FR-29~31 | sync bucket 改调 worktree-path；SHELL_UNAVAILABLE 已单行摘要；constraints 9 处删除；push-progress 样板已由 TASK-05 统一 | agents.contract 通过 |
| 批 4 | FR-32 | write-insight-brief/run-competitive-analysis 合并下线（简报区块 + 市场竞品章节 + node ref 切换 + 全引用清退）；list-remote 去重；跳过检查单份化定案 | 55 active skills 一致；lint 0 |
| 收尾 | FR-33/34 | 三台账同步；口径 25/47 全仓核查（历史备份除外）；ARCHITECTURE.md §8 登记；crctl/SKILL.md 更新；AGENTS.md #2 同步 | 全回归绿；pipeline JSON 全解析通过 |

