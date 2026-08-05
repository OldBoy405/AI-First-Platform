---
id: CR-2026-021-prd
type: PRD
cr-ref: CR-2026-021
title: 治理工具链 — prompt 对齐 crctl（写入面补齐 S1~S11+inbox-emit + prompt 分阶段收敛 + lint-prompts 漂移防线 + D13 溯源）
target-version: tbd
owner: Ray
owner-role: requirement
status: draft
created: "2026-08-05T10:30:00+08:00"
updated: "2026-08-05T10:50:00+08:00"
---

# PRD — prompt 对齐 crctl（写入面补齐 + prompt 收敛 + 漂移防线）

## 1. 概述

### 1.1 问题陈述

crctl（CR-2026-019 账本子命令 / CR-2026-020 回写脚本）与 `controlled-shell` 的 PreToolUse guard 的能力扩张跑在了 SKILL/pipeline prompt 前面，导致两类问题：

**guard 锁死但无工具出口（孤儿写入）**：`rules.json#protectedPaths.deny` 锁死 `_backlog.yml`（整文件）、`review-annotations/*.yml`、`cr.md`、`approval.yml`、`review-loop.yml`、`_history.yml`，但 crctl 现有写口只覆盖其中一部分。`_backlog` 的 `prd-path`/`owners`/`checkpoints`/`remote-ref`/`notify-log` 字段、`review-annotations/{stage}.yml` 整文件、`approval.yml` 的 `supplemental-reviews[]` 段均属 deny 但无对应 crctl 写命令——prompt 只能手写这些文件，当场被 guard 拦截。生命周期最前端的 CR-ID/TASK-ID 顺序分配同样无 CAS 保护，并发注册会撞号。

**已有工具但 prompt 未采纳（漂移）**：20+ SKILL/pipeline prompt 仍手把手教手动操作——手写 `approval.yml`、裸 `git` 命令、引用已被 `crctl advance` 取代的 `cr-status-set`、按已作废的 6 字段口径校验 `merge-commits`——即便 crctl 已提供对应能力。此漂移积累了三个 CR（CR-2026-019/020/021）才被审计发现，说明"清理一次"不治本，需要机械化的漂移检测防线，而非再靠人工记性。

### 1.2 解决方案摘要

分两大块，①先行、②依赖①：

**① crctl 补齐写入面**：新增 purpose-specific、字段白名单的子命令族（而非通用 `patch`，避免退化为绕过治理模型的第二条不受控写入通道），每个自带前置态守卫 + CAS + 审计，与现有 `task done`/`merge-metadata`/`archive-move` 同构。共 9 个写子命令（`review-record`/`review-note`/`checkpoint-add`/`owner-set`/`backlog-set`/`next-cr-id`/`task allocate`/`cr-init`/`inbox-emit`）+ 2 个只读子命令（`worktree-path`/`report`+`cr-metrics`）+ 1 处既有 `git commit` 扩展（`--template`）。`next-cr-id`/`cr-init` 因处于同一注册流程相邻两步，合并实现共享一个 `casWrite` 事务。`review-record` 采用"判断/写入分离"：agent 把评审判断写成非受控临时 payload，crctl 只做 schema 校验后的确定性 canonical 写入。PRD/SDD schema 校验（`validate-doc`）不直接开新命令，先溯源调查 engineering-docs 的 `prd.schema.json`/`sdd.schema.json` 在 v0.4.0 下线的原因，再决定复活路线或维持现状。

**② prompt 分阶段收敛为调用 crctl**：不依赖新命令、当场会失败的问题（`merge-commits` 字段口径、`approve-*` 手写 `approval.yml`、裸 `git`、`test-report.md` frontmatter）先改（Phase 1）；`cr-status-set` 全仓系统性清退（Phase 2）；依赖新子命令的账本写入迁移到 Phase 0 产出的命令（Phase 3）；冗余精简与文档 staleness 收尾（Phase 4）。

**③ 根治机制**：新增 `lint-prompts` 漂移 linter（R1~R6 规则，判据直接读 `rules.json`/`crctl.mjs` 源码，不设专门的能力快照测试——git diff 本身就是"crctl 能力面变了"的信号）接入 pre-commit 钩子（提交时拦截）与 feature-writeback 归档前 gate（CI 侧兜底）两层机械防线；linter 覆盖不到的"crctl 新增能力、某 skill 该采纳但还没采纳"这类，交由 SDD 强制小节 + 评审兜底的人工残余清单项承接。

### 1.3 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| `rules.json#protectedPaths.deny` 锁死 `_backlog.yml`/`review-annotations/*.yml`/`cr.md`/`approval.yml`/`review-loop.yml`/`_history.yml` 六类文件 | `tools/skills/shared/controlled-shell/rules.json` |
| crctl 现有写口（`advance`/`approve`/`attempt`/`merge-metadata`/`archive-move`）已覆盖 `cr.md` status、`approval.yml` 门禁段、`review-loop.yml`、`_backlog` merge-commits/归档移除、`_history.yml`；`_backlog` 的 prd-path/owners/checkpoints/notify-log 与整个 `review-annotations/{stage}.yml` 无写口 | `crctl.mjs` dispatch（`status`/`gate`/`advance`/`approve`/`validate`/`attempt`/`task`/`merge-metadata`/`archive-move`/`test`/`next`/`migrate-backlog`/`git`） |
| review-annotations 文件名与评审阶段非同名映射：`requirement`→`requirement.yml`、`tech-design`→**`sdd.yml`**（非 `tech-design.yml`）、`code`→`code.yml`，门禁读取即按此口径 | `crctl.mjs:1230,1524,1534,1549/1554` |
| `requirement-register/SKILL.md:48` 由 agent 读 `_index.yml` 扫最大编号手算 `+1` 分配 CR-ID，无 CAS，并发注册可撞号；`:53-97` 全量手写 cr.md 初始 frontmatter；`:127-133` 手工拼接 worktree bucket/path；`:114` 手拼 commit message | `requirement-register/SKILL.md` |
| `write-dev-tasks/SKILL.md:45,64` 手动顺序分配 TASK-ID 并拼 slug 兜底命名；`:80` 手拼 commit message；`:87` 手动加总 TASK 估时 | `write-dev-tasks/SKILL.md` |
| `merge-feature-branch`/`push-progress`/`resume-from-remote` 各自用 prose 重复描述同一条 worktree 拼接规则（4+ 处） | 对应 SKILL.md |
| `cr-dashboard`/`spec-dashboard` Step 2 手动统计状态直方图/SLA 阈值/周期活动计数 | 对应 SKILL.md |
| `validate-doc/SKILL.md` 教 agent 用眼睛核对 PRD/SDD frontmatter/命名/路径；engineering-docs 自带 `prd.schema.json`/`sdd.schema.json` + `validateFrontmatter`/`validateNaming` 在 v0.4.0 已下线，下线原因未知 | `validate-doc/SKILL.md`；engineering-docs 包 |
| 生产者（`merge-feature-branch`/FR-8）已产出 `merge-commits` 3 字段 `{repo,trunk,sha}`（branch 可选），但 `writeback-traceability/SKILL.md:84,107,120`、`feature-writeback.pipeline.json` node-4:67 仍按旧 6 字段校验，必然失败 | 对应 SKILL.md / pipeline JSON |
| `resume-cr` node-1:40 用裸 `git ls-remote --heads origin 'requirement/...'` 带分支名参数，但 `controlled-shell/rules.json#git` 当前只放行 `^--heads origin$`（不带参数固定形态）——迁移到 `crctl git` 前必须先补白名单 shape，否则当场被拒 | `rules.json#git`；`resume-cr/SKILL.md` node-1 |
| `cr-status-set` 已被 `crctl advance` 取代，但 `approve-*`、`review-code:132-133`、`review-tech-design:95`、`review-requirement:111`、`write-dev-tasks:79`、`cr-review-record:53-54`、`cr-archive:54` 仍引用 | 对应 SKILL.md |
| `resume-cr` node-3 与 `resume-from-remote:99-113` 各自硬编码一张 status→下一节点映射表，`crctl next` 已存在但未被两处采纳 | 对应 SKILL.md / pipeline JSON |
| tools 仓 `.githooks/pre-commit` 已有先例：每次 commit 跑 `check-skill-matrix.mjs` + `check-agents-contract.mjs`，新增检查项成本低 | `tools/.githooks/pre-commit` |
| 本次漂移历时 CR-2026-019/020/021 三个 CR 才被审计发现（`docs/analysis/tools包-prompt过时冗余审计.md`），证明纯人工"记得扫一遍"不可持续 | `docs/analysis/tools包-prompt过时冗余审计.md` |

## 2. 用户故事

- **US-1** 作为评审 agent，我执行 `crctl review-record` 把评审判断写入 `review-annotations/{stage}.yml`，不再被 guard 当场拦截，也不再有 stage→文件名映射错误导致门禁读不到评审结论的风险。
- **US-2** 作为评审流程的执行者，我用 `crctl review-note` 追加 `approval.yml` 的 `supplemental-reviews[]`，不再手写受控文件。
- **US-3** 作为推送进度的维护者，我用 `crctl checkpoint-add` 记录推送元数据（checkpoints/remote-ref/last-push），不再手改 `_backlog`。
- **US-4** 作为交接 CR 的维护者，我用 `crctl owner-set` 变更 owners 字段，不再手改 `_backlog`。
- **US-5** 作为登记 PRD 路径的维护者，我用 `crctl backlog-set --field prd-path` 写入白名单标量字段，不误碰 status/owners/merge-commits 等有专命令的字段。
- **US-6** 作为发起新 CR 注册的 agent，我用 `crctl next-cr-id` 拿到 CAS 保护的编号、用 `crctl cr-init` 生成初始 `cr.md`，不再手算 max+1、不再有并发撞号风险。
- **US-7** 作为拆分开发任务的 agent，我用 `crctl task allocate` 拿到 CAS 保护的 TASK-ID 与 slug，不再手动顺序分配。
- **US-8** 作为多处需要 worktree 路径的 SKILL 作者，我调用 `crctl worktree-path` 得到统一派生结果，不再各自维护一份拼接 prose。
- **US-9** 作为需要生成 commit message 的 agent，我用 `crctl git commit --template <kind>` 得到规范格式，不再各自拼 prose。
- **US-10** 作为查看治理仪表盘的维护者，我用 `crctl report`/`crctl cr-metrics` 得到跨 CR 统计，不再手动统计状态直方图/SLA。
- **US-11** 作为发起 inbox 通知的 agent，我用 `crctl inbox-emit` 追加 notify-log，不再手写 `_backlog`。
- **US-12** 作为处理 PRD/SDD 校验的维护者，我知道 `validate-doc` 是否应复活 engineering-docs 的 schema validator 有明确结论（复活或记录暂缓原因），不必臆测。
- **US-13** 作为执行 Phase 1~3 prompt 改造的维护者，我改完的 SKILL/pipeline 不再有 `merge-commits` 6 字段校验、手写 `approval.yml`、裸 `git`、`cr-status-set` 引用等会当场失败或已被取代的操作。
- **US-14** 作为治理工具链的维护者，我在 pre-commit 阶段就能拦住"prompt 又开始教手写 deny 文件/裸 git/引用 deprecated 机制"的漂移，不必等下一次人工审计才发现。
- **US-15** 作为归档 CR 的评审者，我在 CR 归档前有一道 `lint-prompts` gate 兜底，即使有人绕开本地 pre-commit 钩子，漂移的 prompt 也无法归档。
- **US-16** 作为 SDD 撰写者，当我的 CR 改动了 `crctl.mjs` dispatch 或 `rules.json` deny 面时，我在 SDD 中有一个强制小节列出"应改为调用新命令的 skill 清单"，不靠回写期临时记性。

## 3. 功能需求

### Phase 0：crctl 写入面补齐（前置）

- **FR-1（`crctl review-record`）**：`review-record <cr> --stage <requirement|tech-design|code> --from <payload.yml> [--bump-attempt]`。schema 校验 payload（`verdict∈{pass,block}`、`blockers` 为列表、`dimensions` 齐全）后写入对应文件（CAS+审计），可选级联 `attempt`。stage→文件名映射显式实现为 `requirement`→`review-annotations/requirement.yml`、`tech-design`→`review-annotations/sdd.yml`、`code`→`review-annotations/code.yml`，与门禁读取口径一致。payload 落点统一为非受控的 `.crctl/tmp/review-{stage}.yml`（`.gitignore` 补一条 `.crctl/tmp/`），消费成功后自动删除，避免残留误提交或跨 CR 串味。
- **FR-2（`crctl review-note`）**：`review-note <cr> [--stage <s>] --note <text>`。向 `approval.yml` 的 `supplemental-reviews[]` 追加一条记录（CAS+审计）；操作者身份由 crctl `identity(ws)` 生成，不接受 `--by` 参数。
- **FR-3（`crctl checkpoint-add`）**：`checkpoint-add <cr> --repo <r> --sha <sha> [--remote-ref <ref>]`。`_backlog` 条目 `checkpoints[]` 追加 + 更新 `remote-ref`/`last-push-at`（crctl 生成）/`last-push-by`（identity）。
- **FR-4（`crctl owner-set`）**：`owner-set <cr> --role <requirement|development|test> --id <id>`。写 `_backlog` 条目 `owners.{role}.id` + `assigned-at`（crctl 生成）；`--id` 是被指派人身份（业务数据），由调用方传入，不违反"操作者身份必须 crctl 生成"原则。
- **FR-5（`crctl backlog-set`）**：`backlog-set <cr> --field <name> --value <v>`。白名单标量字段：仅 `prd-path`、`sdd-path`（及未来静态注册字段）；硬拒 `status`/`updated-at`/`owners`/`merge-commits`（各有专命令）。
- **FR-6（`crctl inbox-emit`）**：`inbox-emit <cr> --event ...`。专命令处理 `_backlog` 的 `notify-log`/`notify-pending` 事件追加（不复用 `backlog-set`，因事件追加语义比标量 set 重）。
- **FR-7（`crctl next-cr-id` + `crctl cr-init`，合并实现）**：`next-cr-id [--year Y]` 做 CAS 保护的 CR-ID 分配（读 `_index.yml`/`_backlog.yml` 现有最大编号抢占式返回下一个，并发请求失败重试不撞号）；`cr-init <cr-id> --title <t> --owner-requirement <id>` 生成初始 `cr.md`（owners/owner-history/时间戳全部 crctl 生成）+ 级联首次登记进 `_backlog`。二者共享同一个 `casWrite` 事务，减少中间态窗口。
- **FR-8（`crctl task allocate`）**：`task allocate <cr> [--slug <s>]`，扩展现有 `task` 子命令族。CAS 保护的 TASK-ID 分配，`TASK-{NN}` + slug 兜底命名。
- **FR-9（`crctl worktree-path`，只读）**：`worktree-path <cr> --repo <r>`。只读派生输出 worktree bucket/path（`role==knowledge-base?"knowledge-base":repo.id` + 固定模板拼接），不写文件、无需 CAS。
- **FR-10（`crctl git commit --template`，既有命令扩展）**：给现有 `git commit` 加 `--template <kind>` 分支（`register`/`task-breakdown`/`writeback`/…），按 kind 生成规范 commit message。不是新增顶层子命令，同现有 git commit 白名单前置态。
- **FR-11（`crctl report` / `crctl cr-metrics`，只读）**：跨 CR 状态直方图、SLA 阈值比较、周期活动计数聚合，`--period P` 可选。
- **FR-12（D13 溯源调查与条件实现）**：Phase 0 门槛任务，可与 FR-1~FR-11 并行：① 查 engineering-docs `v0.4.0` changelog/commit 历史，确认 `prd.schema.json`/`sdd.schema.json` + `validateFrontmatter`/`validateNaming` 下线的具体原因；② 若原因已解决或不再成立，复活并二选一：(a) 并入 `crctl validate --doc-type prd|sdd`，或 (b) `validate-doc` 改为直接调用 engineering-docs 自身 CLI（更合适，PRD/SDD 校验不属于 CR 账本类产物）；③ 若原因仍成立，本轮不复活，在 SDD 中记录排查结论（已排查、暂缓、原因 XXX），不写代码。
- **FR-13（配套：文档更新 + 白名单补齐）**：更新 `crctl help`、`ARCHITECTURE.md §3 code map`、`skills/_index.yml:274` 的 crctl brief（补全 CR-2026-019 已加但漏列的 `task done`/`merge-metadata`/`archive-move`/`migrate-backlog` + 本轮全部新增/扩展子命令）；逐条核对 Phase 1-C 待迁移的裸 git 命令是否已在 `controlled-shell/rules.json#git` 白名单内，补齐缺失 shape（含 `ls-remote` 带分支参数的形态）。

### Phase 1：P0 prompt 修正（不依赖新命令，当场会失败）

- **FR-14（D7 merge-commits 3 字段）**：`writeback-traceability/SKILL.md:84,107,120`、`feature-writeback.pipeline.json` node-4:67 的 6 字段校验改为 `{repo,trunk,sha}` 必填、`branch` 可选。
- **FR-15（approve-* 折叠为 `crctl approve`）**：`approve-code`/`approve-tech-design`/`approve-dev-start`/`approve-requirement` 删手写 `approval.yml` 段、删 `cr-status-set` 步、删"回滚 approval.yml"错误处理，改为运行 `crctl approve --stage X`（TTY），由其校验证据、写 `approval.yml`、级联 `advance`。
- **FR-16（裸 git → `crctl git`）**：`review-code:37-42`、`write-dev-plan:58-60`、`write-dev-tasks:81`、`writeback-{prd-sdd,tasks,traceability}` 提交步、`resume-cr` node-1:40 一律改 `crctl git <sub> --cwd`；改前逐条核对 `rules.json#git` shape 白名单是否已放行目标命令，缺的随 FR-13 一并补齐。
- **FR-17（D3 test-report frontmatter）**：`write-test-report:51-84` 的 frontmatter 交 `crctl test --cmd` 生成，模型只写 `<!-- crctl:analysis-below -->` 以下分析段。

### Phase 2：系统性清理 `cr-status-set`

- **FR-18**：`cr-status-set/SKILL.md` 标注 legacy/deprecated，正文改述"状态推进见 crctl advance"，保留仅为历史兼容。全仓引用（`approve-*`/`review-code:132-133`/`review-tech-design:95`/`review-requirement:111`/`write-dev-tasks:79`/`cr-review-record:53-54`/`cr-archive:54`）改指 `crctl advance --to X --trigger Y --expect Z`。`cr-archive/SKILL.md:84-93` 删 Step 5 手写 `_index.yml`（`archive-move` 已一并更新）与 `:92` 手改 status。

### Phase 3：账本写入改走新子命令（依赖 Phase 0）

- **FR-19**：`review-code`/`review-tech-design`/`review-requirement` 改调 `crctl review-record`（FR-1）；`write-test-report` 改调 `crctl attempt`；`cr-review-record` 改调 `crctl review-note`（FR-2），reject/withdraw 走 `advance`，重新定位该 skill 为"补充意见记录 + 状态推进转发"；`handover-cr:66-68`/`resume-from-remote:86` 改调 `crctl owner-set`（FR-4）；`push-progress:63-77` 改调 `crctl checkpoint-add`（FR-3）；`write-requirement-prd:87-89` 改调 `crctl backlog-set --field prd-path`（FR-5）；`inbox-emit` 改调 `crctl inbox-emit`（FR-6）；`requirement-register:48` 改调 `crctl next-cr-id`（FR-7）；`write-dev-tasks:45,64` 改调 `crctl task allocate`（FR-8）；`requirement-register:53-97` 改调 `crctl cr-init`（FR-7）；`requirement-register:127-133`/`merge-feature-branch`/`push-progress`/`resume-from-remote` 改调 `crctl worktree-path`（FR-9）；`requirement-register:114`/`write-dev-tasks:80`/`writeback-traceability:75` 改调 `crctl git commit --template`（FR-10）；`cr-dashboard`/`spec-dashboard` Step 2 改调 `crctl report`/`crctl cr-metrics`（FR-11）；`validate-doc` 视 FR-12 结论决定是否及如何改。

### Phase 4：冗余精简 + 文档 staleness

- **FR-20（D8 状态映射去重）**：`resume-cr` node-3、`resume-from-remote:99-113`、`pull-progress:64-66`、`implement-code:67` 收敛为"跑 `crctl status`（含 STATUS_DIVERGED）+ `crctl next`"，删两处重复硬编码状态表。
- **FR-21（D15 工时求和精简）**：`write-dev-tasks:87` 手动加总 TASK 估时的措辞改为"按 TASK 列表求和"一句话带过或直接删，不开新命令。
- **FR-22（其余冗余）**：`feature-writeback.pipeline.json` inputs/node-2/node-3 冗长"必须显式提供否则空路径" prose 精简（缺参现 BAD_ARGS fail-fast 兜底）；`skills/_index.yml` 各 brief 补齐（含全部新增/扩展子命令）；`AGENTS.md（主仓）#6` 把"cp 覆盖"危害降为历史注脚；writeback 系 brief 补提 CR-2026-020 脚本。

### 根治机制：prompt↔crctl 漂移防线（归入 Phase 0）

- **FR-23（`lint-prompts` 漂移 linter）**：新增 `crctl lint-prompts`（或独立 `lint-prompts.mjs`，复用 `check-agents-contract.mjs` 模式），扫 `skills/**/SKILL.md` + `pipeline-templates/*.json` 的 prompt 串，按 R1~R6 规则集判漂移，命中即输出 `file:line` + 规则 + 非零退出：

  | 规则 | 检测 | 判据来源 | 级别 |
  |---|---|---|---|
  | R1 手写 guard-deny 文件 | 指示 write/create/编辑 deny 文件，且附近无对应 `crctl <cmd>` 调用 | `rules.json` deny 面（直读） | CONTRADICTS |
  | R2 裸 git | prompt 内 `git <sub>` 字面且非 `crctl git` | `rules.json#git` | CONTRADICTS |
  | R3 引用 deprecated 机制 | 出现 `cr-status-set` | `crctl advance` 已取代 | STALE-REF |
  | R4 merge-commits 过时口径 | `source-sha`/`merged-at`/"六字段"作为必填 | FR-8（CR-2026-020）契约 | CONTRADICTS |
  | R5 手写 review-loop 记账 | `review-loop.current-attempt`/`attempts[]` 配合 write/持久化动词 | `crctl attempt` 独占 | OUTDATED |
  | R6 手写 test-report frontmatter | `test-report.md` 配合手写 `status:`/`commands:` | `crctl test` 生成 | CONTRADICTS |

  判据直接读 `rules.json`/`crctl.mjs` 源码，不经过任何派生快照（`crctl capabilities` 之类），与 crctl 能力面变更天然解耦——deny 面/dispatch 改了，linter 判据自动跟着变。R1 用"提及 deny 文件写动作且同段无 crctl 调用"的邻近判定而非裸关键词，避免"教手写"和"解释为什么不该手写"的说明性文本混淆。提供显式豁免：`<!-- lint-prompts:ignore -->` 注释使 linter 跳过该段落检测。
- **FR-24（两层机械防线接入，分阶段启用）**：`lint-prompts` 接入两处 gate，但**强制阻断模式的启用有严格时序，避免与 Phase 0→3 依赖顺序自举冲突**：
  - **pre-commit 钩子**（tools 仓 `.githooks/pre-commit`，已有 `check-skill-matrix`/`check-agents-contract` 先例）：**Phase 0~2 期间以 report-only / warn 非阻断模式运行**（输出 `file:line` 漂移清单但不 fail 提交），使本 CR 自身开发期（含 tools 仓 crctl.mjs/skills/pipeline 的增量提交）不被尚未清理的存量漂移拦死；**Phase 3 漂移清零后转为硬阻断模式**，此后漂移提交不进来。
  - **feature-writeback 归档 gate**（cr-guard 或归档前 passCondition）：CR 归档前 `lint-prompts` 必须 pass。此 gate 不受上述分阶段影响——归档必然发生在 Phase 3 漂移清零之后，天然安全，作为兜住绕过本地钩子的 CI 侧兜底。
  - 不设专门的"crctl 能力快照测试"层——git diff 本身即"能力面变了"的信号。
- **FR-25（人工残余回写清单项）**：feature-writeback 回写清单新增一条：「本 CR 若 diff 触及 `crctl.mjs` 的 dispatch 或 `rules.json` 的 `protectedPaths.deny`：① 跑 `crctl lint-prompts` 清零 CONTRADICTS/STALE；② 对新增子命令，在 SDD『prompt 采纳影响』小节列出应改为调用它的 skill 清单并逐一改，由评审兜底。」该清单项承接 linter 抓不到的"新增能力未被采纳"类漂移。

## 4. 非功能需求

- **NFR-1（前置态守卫一致性）**：所有新写子命令必须复用现有 `matchEntryBlock` + `casWrite`/`casWriteMulti` + `auditLog` + `nowIso`，与既有 `task done`/`merge-metadata`/`archive-move` 同一前置态校验模式，不引入第二套写入范式。
- **NFR-2（时间戳/身份一律 crctl 生成）**：所有操作者身份（`--by` 类）与时间戳字段一律由 crctl 内部生成（`identity(ws)`/`nowIso()`），拒绝调用方传入；仅"指派给谁"这类业务身份（如 `owner-set --id`）例外，由调用方传入。
- **NFR-3（不做通用 patch）**：不提供 `crctl patch <file> <dotpath> <value>` 或等价的任意路径写入通道；所有写口均为 purpose-specific + 字段白名单。
- **NFR-4（零新增第三方依赖）**：新增子命令与 `lint-prompts` 均只用 Node 标准库与 crctl 既有工具函数。
- **NFR-5（只读命令无副作用）**：`worktree-path`/`report`/`cr-metrics` 不修改任何受保护文件，不需要 CAS/审计。
- **NFR-6（linter 判据零派生物）**：`lint-prompts` 的判据直接读源文件（`rules.json`/`crctl.mjs`），不依赖任何需要手工同步维护的中间快照/生成物。
- **NFR-7（CAS 并发安全）**：`next-cr-id`/`task allocate` 在并发调用下必须通过重试机制保证不产生重复编号（撞号）。

## 5. 验收标准

- **AC-1**（FR-1）：对同一 stage 连续两次调用 `review-record`（一次 requirement、一次 tech-design），生成的文件分别是 `review-annotations/requirement.yml` 与 `review-annotations/sdd.yml`（非 `tech-design.yml`）；payload 中 `verdict` 非法值时非零退出且不写入；成功后 `.crctl/tmp/review-{stage}.yml` 被自动删除。
- **AC-2**（FR-2）：调用 `review-note` 后 `approval.yml.supplemental-reviews[]` 追加一条含操作者身份（crctl 生成）的记录；传入 `--by` 参数报错拒绝。
- **AC-3**（FR-3/FR-4/FR-5/FR-6）：`checkpoint-add`/`owner-set`/`backlog-set`/`inbox-emit` 分别正确更新 `_backlog` 对应字段；`backlog-set --field status` 硬拒（非零退出，提示改用 `advance`）。
- **AC-4**（FR-7）：并发调用 `next-cr-id` 两次，两次返回不同编号（无撞号）；`cr-init` 生成的 `cr.md` frontmatter 完整（owners/owner-history/时间戳）且已登记进 `_backlog`。
- **AC-5**（FR-8）：并发调用 `task allocate` 两次，TASK-ID 不重复；slug 缺失时按兜底命名生成。
- **AC-6**（FR-9/FR-10/FR-11）：`worktree-path` 给定输入返回确定性路径且不写任何文件；`git commit --template register` 生成的 message 符合约定格式；`report`/`cr-metrics` 输出的统计与手动核对的账本状态一致。
- **AC-7**（FR-12）：D13 溯源结论已写入 SDD（复活路线或暂缓原因二选一），若选择复活，对应 `crctl validate --doc-type` 或 `validate-doc` 改调用行为已实现并有测试。
- **AC-8**（FR-13）：`crctl help` 输出含全部新增/扩展子命令；`rules.json#git` 白名单已补齐 Phase 1-C 迁移所需的全部裸 git shape（含 `ls-remote` 带分支参数形态）。
- **AC-9**（FR-14~FR-17，Phase 1）：`writeback-traceability` 对 3 字段 `merge-commits` payload 校验通过；`approve-*` 系列 SKILL.md 不再含手写 `approval.yml` 的 YAML 段；Phase 1-C 覆盖的裸 git 命令全部替换为 `crctl git`；`write-test-report` 不再手写 frontmatter。
- **AC-10**（FR-18，Phase 2）：`grep -r "cr-status-set"` 除 `cr-status-set/SKILL.md` 自身的 legacy 说明外无其他 SKILL 引用；`cr-archive/SKILL.md` 不含手写 `_index.yml`/status 的步骤。
- **AC-11**（FR-19，Phase 3）：Phase 3 表内列出的每个文件均已改调对应新子命令，`grep` 相应 SKILL.md 不再含手写受控文件的指引。
- **AC-12**（FR-20~FR-22，Phase 4）：`resume-cr`/`resume-from-remote`/`pull-progress`/`implement-code` 不再各自硬编码状态映射表；`write-dev-tasks:87` 措辞已精简；`skills/_index.yml` brief 含全部新增子命令。
- **AC-13**（FR-23）：对 6 类规则各构造一个已知漂移的 fixture prompt，`lint-prompts` 全部命中且输出 `file:line`；对含 `<!-- lint-prompts:ignore -->` 的段落不误报；对 Phase 1~3 改造完成后的仓库运行 `lint-prompts`，CONTRADICTS/STALE-REF 计数为 0。
- **AC-14**（FR-24）：`.githooks/pre-commit` 新增 `lint-prompts` 步骤；**Phase 0~2 期间对 tools 仓的 commit（即使存量漂移未清）不被阻断**（report-only 模式，非零退出仅出现在归档 gate）；**Phase 3 漂移清零并将钩子转为硬阻断模式后**，构造一个带漂移的 commit 尝试被本地钩子拦截（非零退出）；feature-writeback 归档前 passCondition 含 `lint-prompts` 校验，任意阶段带漂移的 CR 无法归档。
- **AC-15**（FR-25）：feature-writeback 回写清单模板中存在该新增条目文本；对一个 diff 触及 `crctl.mjs` dispatch 的测试 CR，SDD 模板渲染出"prompt 采纳影响"小节。

## 6. 成功指标

- crctl 写入面与 guard deny 面完全对齐：`grep` `rules.json#protectedPaths.deny` 六类文件，每一类都有对应 crctl 写口（无孤儿写入）。
- 全仓 `lint-prompts` 扫描 CONTRADICTS/STALE-REF 计数为 0（Phase 1~3 改造完成后）。
- CR-ID/TASK-ID 分配从"手算 + 无 CAS"变为 100% 走 `next-cr-id`/`task allocate`，并发注册不再有撞号风险（此前为已知风险，未发生过真实撞号事故，但无防护）。
- 下一次 prompt↔crctl 漂移不再需要等到"审计三个 CR 后才发现"——pre-commit 与归档 gate 在漂移引入的第一次 commit/归档即拦截。

## 7. 范围排除

**本 CR 包含**：Phase 0（crctl 新增 9 个写子命令 + 2 个只读子命令 + 1 处既有命令扩展 + D13 溯源调查）+ Phase 1~4（全部 SKILL/pipeline prompt 收敛）+ `lint-prompts` 漂移 linter + 两层机械防线接入（pre-commit + feature-writeback gate）+ 人工残余回写清单项。D9~D16 已按决定并入本轮单次施工，不再拆分下一轮。

**本 CR 不包含**：
- 通用 `crctl patch <file> <dotpath> <value>` 命令（已否决，见 §1.1/NFR-3）。
- `crctl capabilities` 派生快照测试层（已在方案中砍除，git diff 本身即触发信号，见 FR-24）。
- D13 若溯源结论为"不复活"，则不实现 PRD/SDD schema 校验代码，仅记录排查结论。
- 账本状态机/CAS 基础设施本身的重新设计（复用 CR-2026-018/019 已定型的 `casWrite`/`casWriteMulti`/`auditLog` 机制，不改造）。
- 与本次治理无关的 crctl 既有子命令行为变更（`status`/`gate`/`validate`/`test`/`next`/`migrate-backlog` 等维持现状）。
- `merge-feature-branch` 的合并/补偿逻辑本身（CR-2026-020 已固化其 SKILL 事实基线，本 CR 不改）。
