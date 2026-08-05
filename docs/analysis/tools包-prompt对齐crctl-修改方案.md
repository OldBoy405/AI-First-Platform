# tools 包「prompt 对齐 crctl」修改方案

> 承接：`docs/analysis/tools包-prompt过时冗余审计.md`（分级 finding 清单）
> 触发：crctl（CR-2026-019 账本子命令 / CR-2026-020 回写脚本 / 本轮 FR-2/4/5/8）与 PreToolUse guard 的能力跑在了 prompt 前面
> 日期：2026-08-05　范围：本文件是修改方案（未改动任何 tools 文件）
> 结论先行：分两大块——**① crctl 补齐对 `_backlog`/`review-annotations` 的写入面（消除"guard 锁死但无工具出口"的孤儿写入，含用户点名的 supplemental-reviews）；② 把一批 SKILL/pipeline prompt 从"手把手教手动操作"改为"调用 crctl"**。②依赖①，故①先行。

---

## 第一部分：crctl 补写入子命令（决策 = 补，但用"受控白名单子命令族"而非通用 patch）

### 1.1 为什么不是一个通用 `crctl patch <file> <dotpath> <value>`

通用 patch 能写任意路径任意值——这正是 `ARCHITECTURE.md §6` 否决"独立账本操作脚本库"要防的**第二条不受控写入通道**：它会绕过"每个写入都有语义 + 前置态 + schema 校验"的门禁模型，退化成万能逃生口。所以采用**purpose-specific、字段白名单**的小子命令族，每个自带前置态守卫 + CAS + 审计，与现有 `task done`/`merge-metadata`/`archive-move` 同构。

### 1.2 根因：guard 的 deny 面 ⊋ crctl 的写入面

`rules.json#protectedPaths.deny` 锁死了 `_backlog.yml`（整文件）、`review-annotations/*.yml`、`cr.md`、`approval.yml`、`review-loop.yml`、`_history.yml`。但 crctl 现有写口只覆盖其中一部分：

| 受控文件（guard deny） | crctl 现有写口 | 缺口（孤儿写入） |
|---|---|---|
| `cr.md` status | `advance` / `approve` 级联 | ✅ 无缺口 |
| `approval.yml` 门禁段 | `approve` | supplemental-reviews 段无写口 |
| `review-loop.yml` | `attempt` | ✅ 无缺口 |
| `_backlog` merge-commits | `merge-metadata` | — |
| `_backlog` 条目（归档移除） | `archive-move` | — |
| `_history.yml`（归档写入） | `archive-move`（crctl.mjs:1319 一并写 `_history.yml`） | ✅ 无缺口（§1.2 对账补全，deny 面 6 类文件逐条已有写口对应） |
| **`_backlog` prd-path / owners / remote-ref / checkpoints / notify-log** | **无** | ❌ 孤儿：guard deny、无工具、prompt 只能硬写→被拦 |
| **`review-annotations/{stage}.yml`** | **无（只有 validate 读）** | ❌ 孤儿：评审必写、guard deny、无工具 |

### 1.3 新增子命令族（5 个，按优先级）

所有新命令复用现有 `matchEntryBlock` + `casWrite` + `auditLog` + `nowIso`（时间戳/身份一律 crctl 生成，拒绝调用方传入），零新依赖。

| # | 子命令 | 语义 | 前置态 | 取代的手写 | 优先级 |
|---|---|---|---|---|---|
| S1 | `crctl review-record <cr> --stage <requirement\|tech-design\|code> --from <payload.yml> [--bump-attempt]` | schema 校验 payload 后写入对应文件（可选级联 `attempt`）。**stage→文件名非同名映射，必须显式做**：`requirement`→`review-annotations/requirement.yml`、`tech-design`→**`review-annotations/sdd.yml`**（非 `tech-design.yml`）、`code`→`review-annotations/code.yml`（与 crctl.mjs:1524,1534,1549/1554 门禁读取的文件名对齐，否则 gate 读不到评审结论、`--stage tech-design` 写出的文件不会被消费） | 对应评审态 | 所有 review-* skill 直接 Write review-annotations | **P0**（同时修 guard 孤儿 + 高频 + 门禁关键文件） |
| S2 | `crctl review-note <cr> [--stage <s>] --note <text>` | 向 `approval.yml` 的 `supplemental-reviews[]` **追加**一条补充审查记录（CAS+审计）；操作者身份由 crctl `identity(ws)` 生成，**不接受 `--by` 参数**——与 §1.3 开头"时间戳/身份一律 crctl 生成，拒绝调用方传入"的原则一致，也与 `attempt`/`task done` 同构 | 非终态 | cr-review-record 写 supplemental-reviews 段 | **P0**（用户点名） |
| S3 | `crctl checkpoint-add <cr> --repo <r> --sha <sha> [--remote-ref <ref>]` | `_backlog` 条目 `checkpoints[]` 追加 + 更新 `remote-ref`/`last-push-at`(crctl 生成)/`last-push-by`(identity) | developing~writing-back | push-progress 手写推送元数据 | P1 |
| S4 | `crctl owner-set <cr> --role <requirement\|development\|test> --id <id>` | 写 `_backlog` 条目 `owners.{role}.id` + `assigned-at`(crctl 生成)。**`--id` 与 S2 的 `--by` 不同**：这是"指派给谁"的业务数据（被指派人的身份，本就该由调用方传入），不是"谁在操作 crctl"的操作者身份，不违反§1.3 的时间戳/身份生成原则 | 任意非终态 | handover-cr / resume-from-remote 手改 owners | P1 |
| S5 | `crctl backlog-set <cr> --field <name> --value <v>` | 白名单标量字段写入：仅允许 `prd-path`、`sdd-path`（及未来静态注册字段）；**硬拒** `status`/`updated-at`/`owners`/`merge-commits`（各有专命令） | 任意非终态 | write-requirement-prd 手改 prd-path | **P1**（与 S3/S4 同属"每 CR 必经 + 当场被 guard 拦"的孤儿，原判 P2 仅按频率排序，应与 S3/S4 同级） |

**inbox-emit 的 `notify-log`/`notify-pending`**：同属 `_backlog` 孤儿写入（`_backlog.yml` 在 deny 名单，agent 早前判"非 deny"有误）。两条路线择一（方案里列，落地时定）：
- (a) 扩 S5 白名单允许 `notify-log`（数组追加语义）；或
- (b) 专命令 `crctl inbox-emit <cr> --event ...`。
建议 (b)——notify-log 是事件追加，语义比标量 set 重，且已有同名 skill 可改为调用它。

### 1.4 S1（review-record）的关键设计：判断与写入分离

review-annotations 的**内容是评审 agent 的判断**（verdict=pass/block、blockers 列表），crctl 不能替它判断。所以：
- agent 把判断写成 payload（落**非受控**的临时路径，如 `.crctl/tmp/review-{stage}.yml`，不在 deny 面）；
- `crctl review-record` 做**确定性部分**：schema 校验（verdict∈{pass,block}、blockers 是列表、dimensions 齐全）→ canonical 写入 `review-annotations/{stage}.yml`（CAS+审计）→ 可选 `--bump-attempt` 级联 attempt。stage→文件名映射必须与门禁读取口径一致（见 §1.3 S1 行的显式映射，尤其 `tech-design`→`sdd.yml` 这一非同名映射，是最容易实现错的地方）。

这样"判断=agent、确定性文件写入=crctl"的缝切干净，且让 gate 依赖的 review-annotations 变成 crctl 独占写、有审计——与 approval.yml/review-loop 同一治理模型，**顺带消除 guard 锁死却无写口的 latent bug**。

> 更省的替代：把 `review-annotations/*.yml` 从 deny 降为 ask（人工放行每次评审写）。**不推荐**，但理由要说准确：无论 deny+S1 还是 ask，agent 都仍是"判断"的来源（S1 的 payload 里 verdict 照样由 agent 写），S1 并不能阻止 agent 在 payload 里写假 verdict——真正兜底造假的是 `crctl approve` 的人工/TTY 环节，不是 S1 本身。S1 相对 ask 的真实收益是：schema 校验（拒绝格式错误的 payload）+ CAS（防并发覆盖）+ 审计（可追溯谁在什么时候写了什么）+ 消除"guard 锁死但无合法写口"的孤儿状态 + 免去每次评审都要人工放行的摩擦。这些收益已经足够支撑"不用 ask"的结论，不必夸大成"防造假"。

---

## 第二部分：还有哪些"确定性的事"仍由 prompt 管（Part 1 之外的梳理）

"确定性"= 给定输入有唯一正确的机械输出、可由工具承接。按是否已被 guard 锁死排序：

| # | 确定性操作 | 现状 | 归口 |
|---|---|---|---|
| D1 | **写 `review-annotations/{stage}.yml`**（schema 固定，内容是判断、格式是机械） | guard deny + 无 crctl 写口 → 评审 skill 直接 Write 会被拦 | → **S1 review-record** |
| D2 | **`review-loop.current-attempt`/`attempts[]` 记账** | crctl attempt 已是唯一记账点，但 write-test-report/review-code/review-tech-design 仍手写进 traceability | → 一律 `crctl attempt`（已存在，无需新命令） |
| D3 | **test-report.md frontmatter**（status/commands 按真实退出码） | crctl test 已生成、明标"模型不得改写"，但 write-test-report Step3 仍手写 | → `crctl test`（已存在） |
| D4 | **`_backlog` 非 status 字段写入**（prd-path/owners/checkpoints/notify-log） | guard deny + 无写口 → 孤儿 | → **S3/S4/S5 + inbox-emit** |
| D5 | **approval.yml supplemental-reviews** | guard deny + 无写口 → 孤儿 | → **S2 review-note** |
| D6 | **状态推进**（cr.md status 写 + 门禁 + commit） | crctl advance 已是唯一入口，但全仓仍引用 cr-status-set（直接写 cr.md、不跑门禁） | → 一律 `crctl advance`（已存在） |
| D7 | **merge-commits 字段校验口径** | 生产者 3 字段，下游 prompt 仍校验 6 字段 → 必失败 | → 改 prompt 为 3 字段（无需新命令） |
| D8 | **status→下一节点决策** | `crctl next` 已存在，但 resume-cr node-3 / resume-from-remote Step5 各硬编码一张状态映射表（两处重复维护） | → 一律 `crctl next` |

D2/D3/D6/D7/D8 **不需要新 crctl 能力**，纯 prompt 改（工具早已就位，prompt 没跟上）。D1/D4/D5 需要第一部分的新子命令。

---

## 第三部分：「prompt 对齐 crctl」分阶段修改方案

依赖顺序：**Phase 0（crctl 补命令）→ 依赖新命令的 prompt 改（Phase 3）**；不依赖新命令的 prompt 改（Phase 1/2）可与 Phase 0 并行。

### Phase 0 — crctl 能力补齐（前置，需测试）

- 实现 S1~S5 + inbox-emit 子命令（§1.3），各配 crctl 测试（正常 / 前置态非法 / CAS 冲突 / schema 拒绝）。
- 更新 `crctl help`、`ARCHITECTURE.md §3 code map`、`skills/_index.yml:274` 的 crctl brief（补全 CR-2026-019 已加但漏列的 `task done`/`merge-metadata`/`archive-move`/`migrate-backlog` + 本次新增子命令）。
- **S1 payload 落点约定**：agent 判断写入的临时 payload（§1.4）统一放 `.crctl/tmp/review-{stage}.yml`，需在 `.gitignore` 补一条 `.crctl/tmp/`，且 `review-record` 消费成功后自动删除该临时文件，避免残留误提交或跨 CR 串味。
- 逐条核对 Phase 1-C 待迁移的裸 git 命令是否已在 `controlled-shell/rules.json#git` 白名单内，缺的 shape（例如 `ls-remote` 带分支参数的形态）随本 Phase 一并补齐。
- **落点**：tools 仓 `crctl.mjs` + `test/crctl.test.mjs`。这是账本权威工具的写入面扩张，**必须走 CR**（见文末"是否开 CR"）。

### Phase 1 — P0 prompt 修正（会当场失败/被拦，且不依赖新命令）

| 主题 | 文件 | 改法 |
|---|---|---|
| D7 merge-commits 3 字段 | `writeback-traceability/SKILL.md:84,107,120`、`feature-writeback.pipeline.json` node-4:67 | 6 字段校验 → `{repo,trunk,sha}` 必填，branch 可选（与 merge-feature-branch/FR-8 对齐）。**最紧：不改则每个 CR 回写必 MERGE_COMMITS_MISSING** |
| A approve-* 手写 approval.yml | `approve-code/tech-design/dev-start/requirement` 各 Step | 删手写 YAML 段 + 删 cr-status-set 步 + 删"回滚 approval.yml"错误处理，整体折叠为"运行 `crctl approve --stage X`（TTY），它校验证据+写 approval.yml+级联 advance" |
| C 裸 git | `review-code:37-42`、`write-dev-plan:58-60`、`write-dev-tasks:81`、`writeback-{prd-sdd,tasks,traceability}` 提交步、`resume-cr` node-1:40 | 一律改 `crctl git <sub> --cwd`（与 sync/merge SKILL runGit 一致）。**改前必须逐条核对 `controlled-shell/rules.json#git` 的 shape 白名单是否已放行目标命令**——已有实锤反例：`resume-cr` node-1:40 的 `git ls-remote --heads origin 'requirement/...'` 带分支名参数，但白名单当前只有 `^--heads origin$`（不带参数的固定形态），照方案原样改 `crctl git ls-remote` 会被当场拒绝。缺的 shape 需随 Phase 0 一并加进 rules.json，不能假设"改成 crctl git 就必然放行" |
| D3 test-report frontmatter | `write-test-report:51-84` | frontmatter 交 `crctl test --cmd` 生成，模型只写 `<!-- crctl:analysis-below -->` 以下分析段 |

### Phase 2 — 系统性清理 `cr-status-set`（D6，牵涉最广）

- `cr-status-set/SKILL.md`：标注 **legacy/deprecated**，正文改述"状态推进见 crctl advance"，保留仅为历史兼容。
- 全仓引用改指 `crctl advance --to X --trigger Y --expect Z`：`approve-*`（删独立推进步，approve 已级联）、`review-code:132-133`、`review-tech-design:95`、`review-requirement:111`、`write-dev-tasks:79`、`cr-review-record:53-54`（reject/withdraw）、`cr-archive:54`。
- `cr-archive/SKILL.md:84-93`：**删 Step 5 手写 `_index.yml`**（Step 3 的 `crctl archive-move` 已一并更新 index，Step 5 属半迁移遗留 + 违反 #7）；`:92` 删手改 cr.md status。

### Phase 3 — 账本写入改走新子命令（依赖 Phase 0）

| 文件 | 现状 | 改为 |
|---|---|---|
| review-code / review-tech-design / review-requirement | 直接 Write `review-annotations/{stage}.yml` + 手写 review-loop | `crctl review-record --stage X --from <payload> --bump-attempt`（D1+D2） |
| write-test-report | 手写 review-loop 进 traceability | `crctl attempt`（D2） |
| cr-review-record | 写 approval.yml supplemental-reviews | `crctl review-note`（S2）；reject/withdraw 走 advance；**重新定位该 skill = 补充意见记录 + 状态推进转发** |
| handover-cr:66-68 / resume-from-remote:86 | 手改 `_backlog` owners | `crctl owner-set --role X --id Y`（S4） |
| push-progress:63-77 | 手写 remote-ref/last-push/checkpoints | `crctl checkpoint-add`（S3） |
| write-requirement-prd:87-89 | 手改 `_backlog` prd-path | `crctl backlog-set --field prd-path`（S5） |
| inbox-emit | 手写 `_backlog` notify-log | `crctl inbox-emit`（§1.3 路线 b） |

### Phase 4 — 冗余精简 + 文档 staleness（D8 + 主题 G/H）

- **D8 状态映射去重**：`resume-cr` node-3、`resume-from-remote:99-113`、`pull-progress:64-66`、`implement-code:67` → 收敛为"跑 `crctl status`（含 STATUS_DIVERGED）+ `crctl next`"，删两处重复的硬编码状态表。
- **主题 G spec-id/version prose**：`feature-writeback.pipeline.json` inputs/node-2/node-3 冗长"必须显式提供否则空路径" → 精简（缺参现 BAD_ARGS fail-fast 兜底）。
- **主题 H 文档**：`skills/_index.yml` 各 brief 补齐；`AGENTS.md（主仓）#6` 把"cp 覆盖"危害降为历史注脚（writeback-prd-sdd 已脚本化，危害已消除）；writeback 系 brief 补提 CR-2026-020 脚本。
- **流程改进（治本）**：把"crctl 能力变更 → prompt 对齐"从"记得扫一遍"升级为**机械化防线**（linter + gate，diff 本身即触发器，不设专门快照测试——见 §4.0），详见 **第四部分**（这是防止本次清理若干个 CR 后重新漂移的关键，不做则本方案只是又一次一次性清理）。

---

## 第四部分：根治机制——prompt↔crctl 漂移的机械化防线

> 本次漂移能积累三个 CR 才被审计出来，说明"清理一次"治标不治本。但**"把'记得扫 prompt'加进回写清单"这条治本方案本身，如果只是一句嘱托，就又是一个靠人记性的脆弱缓解**——正是本系列复盘反复批的东西（文档/记忆/行为清单防不住漂移）。真正的根治必须机械可执行、能 fail。故落成**两层机械防线 + 一条无法机械化的人工残余项**（本轮定案：原方案的"层 1 crctl 表面快照测试"予以砍除，理由见下）。

### 4.0 为什么砍掉"层 1 快照测试"

原方案设想的层 1 用来解决"怎么知道 crctl 能力面变了"——但这个触发器本身是多余的：**改 `crctl.mjs` 的 dispatch 或 `rules.json` 的 `protectedPaths.deny` 就是一次显式 git diff**，评审天然看得到，不需要再加一层"必须先更新 golden 快照才能过测"的仪式去提醒"能力变了"。加上它反而有维护成本：`crctl capabilities --json` 是新写的派生输出，golden 文件要跟着每次子命令新增/改名同步，且无关的 crctl 改动（比如内部重构、只加测试不改 API）也可能误触发快照 diff。**层 2 linter（下方改称层 1）不需要它也能跑**——linter 直接读 `rules.json` 做 R1 规则判据（§本节 R1 行），不依赖 `crctl capabilities` 输出，两者本就解耦。故砍掉快照层，linter 直接作为 pre-commit 的常规检查项每次提交都跑（和 `check-skill-matrix`/`check-agents-contract` 一样，不需要"变更触发"的中间层）；§4.2 人工残余项的触发条件相应改为"本 CR 的 diff 是否触及 `crctl.mjs` dispatch 或 `rules.json` deny 面"（用 diff 本身当触发器，而不是额外造一层快照）。

### 4.1 两层机械防线

**层 1 — prompt↔crctl 漂移 linter（检测器：哪些 prompt 掉队了）**

新增 `crctl lint-prompts`（或独立 `lint-prompts.mjs`，复用现有 `check-agents-contract.mjs` 的模式）：扫 `skills/**/SKILL.md` + `pipeline-templates/*.json` 的 prompt 串，按规则集判漂移，命中即输出 `file:line` + 规则 + 非零退出。规则集 = **把本次多 agent 审计的 grep 固化下来**，判据直接读 `rules.json`/`crctl.mjs` 源码（§4.0：不经过任何派生快照，两者解耦）：

| 规则 | 检测（prompt 里出现） | 判据来源 | 级别 |
|---|---|---|---|
| R1 手写 guard-deny 文件 | 指示 write/create/编辑 `approval.yml`/`review-annotations/*.yml`/`_backlog.yml`/`cr.md`/`review-loop.yml`，且**附近无对应 `crctl <cmd>` 调用** | rules.json deny 面（层 1 读取） | CONTRADICTS |
| R2 裸 git | prompt 内 `git <sub>` 字面且非 `crctl git` | guard `:126` | CONTRADICTS |
| R3 引用 deprecated 机制 | 出现 `cr-status-set` | 已被 `crctl advance` 取代 | STALE-REF |
| R4 merge-commits 过时口径 | `source-sha`/`merged-at`/"六字段" 作为必填 | FR-8 契约（必填 3 字段） | CONTRADICTS |
| R5 手写 review-loop 记账 | `review-loop.current-attempt`/`attempts[]` 配合 write/持久化动词 | `crctl attempt` 独占 | OUTDATED |
| R6 手写 test-report frontmatter | `test-report.md` 配合手写 `status:`/`commands:` | `crctl test` 生成 | CONTRADICTS |

关键：**R1 从 rules.json 读 deny 面**——crctl 未来把新文件纳入 deny，R1 自动覆盖，无需改 linter。R3/R4 是字面黑名单，随 deprecated/契约变更维护（小）。linter 需容忍"正确示范"（prompt 里教"改用 crctl approve"这种反例说明文本不该误报）→ 用"提及 deny 文件写动作 且 同段无 crctl 调用"的邻近判定，而非裸关键词。

**误报出口（必须有，否则每次误报都得改规则本身）**：启发式邻近判定对 prose 文本天然会有误报（比如一段解释"为什么不能手写 approval.yml"的说明文字，可能被 R1 当成教手写）。给 linter 一个显式豁免手段：在 SKILL.md/pipeline JSON 的对应段落附近放 `<!-- lint-prompts:ignore -->` 注释，linter 遇到即跳过该段落的检测。没有这个出口，规则集会在维护中不断被"改窄以避免误报"侵蚀，反而降低命中率。

**层 2 — gate 接入（强制：漂移怎么就进不来）**

- 接进 tools 仓 **pre-commit 钩子**（已有先例：每次 commit 跑 skill-matrix + `check-agents-contract`）——加 `lint-prompts`，漂移**提交不进来**。这是最强一道（提交时拦截，不等回写），且不依赖任何"变更触发"信号，每次 commit 常规跑（呼应 §4.0：不需要层 1 快照来告诉它"该跑了"）。
- 再接进 **feature-writeback 的 cr-guard**（或归档前 passCondition）：CR 归档前 `lint-prompts` 必须 pass → **带 prompt 漂移的 CR 无法归档**（CI 侧远端复核，兜住绕过本地钩子的路径）。

### 4.2 人工残余项（linter 抓不到、才需要清单）

linter 机械覆盖的是 **"prompt 多做了 crctl 已接管/已禁的事"（CONTRADICTS/STALE）**。但有一类抓不到：**crctl 新增了能力、某 skill 本该采纳却还没采纳**——prompt 没"做错"，只是没跟上更好的做法，这需要人判断"哪些 skill 该用新命令"。这一类才交回写清单，且清单项必须是**可执行动作**而非嘱托：

> feature-writeback 回写清单新增一条（engineering-docs SDD 模板固化）：
> **「本 CR 若 diff 触及 `crctl.mjs` 的 dispatch 或 `rules.json` 的 `protectedPaths.deny`（= 改动了 crctl 命令面 / deny 面，§4.0 用 diff 本身作触发器，不设专门快照测试）：① 跑 `crctl lint-prompts` 清零 CONTRADICTS/STALE；② 对新增子命令，在 SDD『prompt 采纳影响』小节列出应改为调用它的 skill 清单并逐一改，由评审兜底。」**

②的"应改 skill 清单"是人工判断，但被 SDD 强制小节 + 评审兜底（与 FR-6"事实断言列核实命令"同机制）——不靠回写期临时记性。

### 4.3 为什么这样不算过度设计

- 层 1 linter = 把**我这次手工跑的多 agent 审计固化成一条可重复命令**，一次投入换掉往后每次人肉审计，高杠杆。
- 层 2 = 复用**已存在**的 pre-commit 钩子（`check-agents-contract` 就在里面），不新建基建；feature-writeback gate 也是复用现有 passCondition 机制。
- 两层零第三方依赖，与 crctl 约束一致。
- **原方案的"层 1 快照测试"已在 §4.0 砍掉**——它想用一层额外机械信号去提醒"crctl 能力面变了"，但 git diff 本身就是这个信号，专门造一层快照测试属于为一个已经存在的信号再造一个信号，是本方案里唯一值得警惕的过度设计苗头，故直接砍而非"留作后补增益"。
- **落地顺序：先做层 1 linter（最高价值），层 2 gate 接入紧随其后**（钩子已现成，加一行成本极低，不必等"增益阶段"）。

### 4.4 落点与归属

层 1 落 tools 仓 `scripts/lint-prompts.mjs` + `test/`；层 2 落 crctl/adapters 的 pre-commit 钩子 + feature-writeback pipeline。**归入 Phase 0**（与新子命令同批：lint 规则直接读 `rules.json`/`crctl.mjs` 源码即可判据，不依赖任何派生 capabilities 输出；且 Phase 1~3 改完的 prompt 正好用 linter 验收"改干净了"）。

## 是否开 CR：这次建议开（与上一个轻量修复相反）

上一个漂移修复我判"不开 CR"（几处小改）。这次相反，**建议开一个治理 CR**，因为：
1. **动账本权威工具的写入面**（Phase 0 新增 6 个写子命令），是 CR-2026-019 同级别的 scope，必须走门禁 + 人工审批 + 测试。
2. **跨 20+ SKILL/pipeline 的协同改动**，且 Phase 有严格依赖顺序（0→3），需要 plan/tasks 编排。
3. **有真实设计决策待评审**：review-record 的判断/写入分离、supplemental-reviews 落点、review-annotations deny-vs-ask、inbox-emit 路线 a/b——这些正是 SDD 评审该拍的。
4. dogfooding：这是治理工具链自身的改进，最不该跳过治理流程。

**里程碑建议 T1.3**（延续 CR-2026-019 T1.1 / CR-2026-020 T1.2）。可作为 CR 立项素材直接引用本方案 + 审计报告。

---

## 优先级速览（若资源受限先做哪些）

1. **P0 立即（会当场失败）**：Phase 1 全部——尤其 D7 merge-commits 3 字段（否则回写必挂）、approve-* 手写 approval.yml（被 guard deny）。这些**不依赖新命令**，可在 Phase 0 完成前先改；主题 C 裸 git 迁移前记得核对 rules.json git shape 白名单（见 Phase 1 表内 `ls-remote` 反例）。
2. **P0 需 Phase 0**：S1 review-record（修 guard 孤儿 + 高频，注意 stage→文件名映射，`tech-design`→`sdd.yml`）、S2 review-note（用户点名）。
3. **防复发单点最高杠杆**：第四部分层 1 `lint-prompts`——把本次审计固化为可重复检查，投入小、价值最高。**建议随 Phase 0 落，并作为 Phase 1~3 的验收工具**（改完跑一遍确认 CONTRADICTS/STALE 清零）。层 2 gate 接入（pre-commit + feature-writeback）可紧随其后一起做，成本很低，不必单列后补项；原方案的快照测试层已砍（§4.0）。
4. **P1**：Phase 2（cr-status-set 系统性清理）、S3/S4/S5（sync 账本写入，S5 由 P2 上调为 P1）。
5. **P2**：inbox-emit、Phase 4 其余（精简 + 文档）。
