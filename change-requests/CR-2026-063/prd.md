---
id: CR-2026-063-prd
type: PRD
cr-ref: CR-2026-063
title: CR-P0 流程正确性止血 — `_context.md` 合同退役、Prompt 源/overlay 归位、委派合同收紧、crctl 原子性与错误可操作化
target-version: 0.36
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-11T17:27:29+08:00
updated: 2026-09-11T17:56:00+08:00
---

# 1. 概述

## 1.1 问题陈述

CR-2026-062（AIFI-18 全链路执行）暴露出一组**流程正确性**缺陷：它们不改变任何业务能力，但会让后续每一个 CR 的委派、评审、恢复与账本写入持续走偏。需求来源是 Issue AIFI-24 附件《AIFI-18_SDD到planTASK_原位修订方案.md》§3「CR-P0：流程正确性止血」，共 7 组原位修订：

1. **第三事实副本 `_context.md` 仍然活跃**：删除决策（来源 §1.2）已拍板，但盘上仍有 4 处活跃合同——Multica 侧两份旧 Prompt 副本要求维护/读取它，tools 侧的 post-review 白名单放行它，CR-2026-057 引入的测试把「放行」钉成了合同。缓存与 canonical 事实（`cr.md`、`review-loop.yml`、`traceability.yml`、评审记录）并存时，评审与门禁会读到过期导航数据。
2. **Prompt 事实源定位不清**：`multica/cr-prompts-revised/` 既登记为「快照」，又混放 Multica 专属 coordinator 与四个公共 Agent 的副本，且已与 `tools/agents/` 分叉（§1.4 事实 4）。owner 部署时无法判断该复制什么。
3. **委派合同复制流程步骤**：Multica coordinator overlay（`cr-prompts-revised/cr-coordinator-agent.md`）与公共 `tools/agents/dev-agent.md` 的委派段没有明确「只传事实与 canonical 引用」，执行侧凭评论重建 Skill/Pipeline 步骤，错误被复述成新的执行算法。
4. **错配错误不可操作**：`crctl gate --mode pre-review` 在 stage 不匹配时只回 `BAD_ARGS`（`crctl.mjs:960`），调用方看不到当前 stage 的正确下一步，也无法区分「我传错了」与「版本化 Skill/Pipeline 与 crctl 已经漂移」。
5. **`review-loop reset` 留下已写未提交中间态**：`crctl.mjs:1821` 的 `cmdReviewLoopReset` 直接 `fs.writeFileSync`（L1844）后返回，**不提交、不回滚、无 CAS**；一旦 add/commit 环节失败，CR worktree 会停在一个 dirty 的账本上，后续门禁与 post-review 漂移检查都会误判。
6. **`review-record` payload 的 YAML 子集边界没有写明**：blocker/suggestion 值若写成多行引号标量或折叠块，解析结果与作者意图不一致，而调用方没有明文约束可依。

本 CR 只做「止血」：**原位修订既有文件、既有函数、既有 Skill 段落与既有测试**，不新增流程、不新增观测指标、不换实现方案。

## 1.2 解决方案摘要

按来源文档 §3 的 7 组原位修订逐条落地（每组都锚定「仓 + 文件」，见 §1.3 与 §3 各 FR）：

1. **`_context.md` 合同退役**（§3.1）：Multica 侧两份旧 Prompt 副本各原位替换/删除 `_context.md` 段（`cr-prompts-revised/dev-agent.md`、`quality-reviewer-agent.md`）；tools 侧从 post-review 白名单中删除该条目（`workspace-transactions.mjs` `allowed` 集合）；把 CR-2026-057 的既有测试**原位改成退役合同测试**（`crctl.test.mjs`），不在旁边新增反向补丁测试。不新增 `crProcessCachePath()`，不放宽 `classifyRepoWorkspace()` 的 dirty 语义——删除后 `_context.md` 与其它非白名单文件同等处理。
2. **全量核对**（§3.1.5）：活跃 `agents/`、`skills/`、`pipeline-templates/` 的 `_context.md` **活跃合同引用**归零（口径说明见 §1.5，需人工审批一并确认）；历史 CR、历史 traceability、归档 delivery 证据不改。
3. **Prompt 源 / overlay 归位**（§3.2.1）：原位重写 `multica/CUSTOM.md` 的 **#75 行职责单元格**——公共 Agent Prompt 唯一事实源为 `tools/agents/`；`cr-prompts-revised/cr-coordinator-agent.md` 是 Multica 专属 overlay；目录内公共 Prompt 副本不再独立演进，owner 部署时以 tools 同名文件覆盖平台公共 Agent；DB 是部署投影；`cr-coordinator-agent` 不进入 tools agent index。不新增登记行、不追加第二份事实源说明。
4. **不改动的矩阵与索引**（§3.2.2）：`tools/agents/_index.yml` 不新增 coordinator；`tools/agent-skill-matrix.yml` 保留既有 `cr-coordinator-agent` system actor 声明；`multica/cr-prompts-revised/agent-skill-matrix.yml` 不作为公共矩阵独立演进。
5. **Multica coordinator overlay 三处原位替换**（§3.3）：`cr-prompts-revised/cr-coordinator-agent.md` 的 `## 委派与评论`、`## 评审闭环`、`## 失败与输出` 三节按 §3.3.1/§3.3.2/§3.3.3 给定文本原位替换；保留 `职责`、`事实源与读取`、`路由`、`平台层权限` 与只读约束，不整文件推倒重写。
6. **公共 dev-agent 委派合同**（§3.4）：`tools/agents/dev-agent.md` 的 `## 委派路由合同（评审）` 原位收紧为「每轮新 reviewer task/run、标准节点走 Pipeline Runner、只传 Skill 已声明的结构化输入与 canonical 引用、不复述 Skill 步骤/门禁命令/advance 参数/blocker 修法」，并要求对来自版本化 Skill/Pipeline 的错误命令**同时报告 `CONTRACT_DRIFT`**（不以成功掩盖合同错误）。
7. **crctl 错误可操作化与原子性**（§3.5/§3.6/§3.7）：`gate --mode pre-review` 错配保留 `BAD_ARGS` 与零写入，同时给出 stage 专属安全恢复方向与 `contractDrift`；`lint-prompts.mjs` 的 R7 规则内加入配对检查；`review-loop reset` 改为复用既有 ledger 事务助手的一次原子提交；`crctl/SKILL.md` 的 `review-record` 行与各 review Skill 的 payload 示例注释补写 YAML 子集边界。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

删除 `_context.md` 全部活跃合同（Prompt、post-review 白名单、既有测试原位退役）；公共 Agent Prompt 事实源归位 `tools/agents/`、coordinator 保留 Multica overlay；收紧 coordinator 与 dev 委派合同（只传事实与 canonical 引用、冲突报 `CONTRACT_DRIFT`）；`gate --mode pre-review` 错配补 stage 专属恢复方向与 `contractDrift`；`review-loop reset` 改原子提交；补清 `review-record` payload 的 YAML 子集边界。不新增 SLO/M1–M8/P50-P90/计数门禁，不新增 R14 委派 lint，不换 YAML 解析器，不改平台 DB 与 `aifirst/agent-import.mjs`。

### 1.3.1 scope_in 边界（原文前缀，评审核对用）

> `multica/cr-prompts-revised/*` 只是平台部署副本，公共 Agent 正式改动落 `tools/agents/*`，multica 仓只改 coordinator overlay 与 `CUSTOM.md#75`，平台 DB 与 `aifirst/agent-import.mjs` 由 owner 部署。

**该前缀句的限定**（防止前缀句被当作 multica 文件清单直接核对）：前缀句是**公共 Prompt 事实源归位口径**——公共 Agent 的正式改动不落 multica 部署副本；它不排除 FR-1 的两份部署副本退役编辑（下表第 1、2 行）。加上这两处，本 CR 对 `../multica` 的改动共 **4 个文件**：`cr-prompts-revised/{dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md` + `CUSTOM.md`（与 AC-11 的四文件口径一致）。

逐条落到「哪个仓的哪个文件」：

| # | 仓 | 文件 | 原位修订 |
|---|---|---|---|
| 1 | `../multica` | `cr-prompts-revised/dev-agent.md`（`## 环境与代码边界` 末段，基线 L47） | 用 canonical resume 口径替换整段 `_context.md` 规则，不在段后追加说明 |
| 2 | `../multica` | `cr-prompts-revised/quality-reviewer-agent.md`（`## 入口识别与证据` 首段，基线 L19） | 删除 `_context.md` 引用，改为读 `dir-graph.yaml`、`crctl status/next` 返回、当前 CR canonical 产物与 Skill 指定证据 |
| 3 | `../multica` | `cr-prompts-revised/cr-coordinator-agent.md`（`## 委派与评论` L38、`## 评审闭环` L45、`## 失败与输出` L63） | 三节原位替换（§3.3.1/3.3.2/3.3.3 文本） |
| 4 | `../tools` | `agents/dev-agent.md`（`## 委派路由合同（评审）`，基线 L31） | 原位收紧委派合同，加 `CONTRACT_DRIFT` 报告义务 |
| 5 | `../multica` | `CUSTOM.md`（#75 行，基线 L387） | 原位重写同一表格行的职责单元格；不新增行 |
| 6 | `../tools` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（post-review `allowed` 集合，基线 L1311–1319） | 删除 `_context.md` 条目与其注释 |
| 7 | `../tools` | `skills/shared/crctl/scripts/test/crctl.test.mjs`（CR-2026-057 白名单测试，基线 L4554） | 原位改为退役合同测试，保留 `_context2.md` 反例 |
| 8 | `../tools` | `skills/shared/crctl/scripts/crctl.mjs`（`cmdGate` 的 `--mode pre-review` 分支，基线 L959–960） | 错配返回 stage 专属恢复方向 + `contractDrift` + 固定字符串 `recoverCommand` |
| 9 | `../tools` | `skills/shared/crctl/scripts/lint-prompts.mjs`（R7，基线 L249–284） | 内加入 `gate --mode pre-review` ↔ `--for requirement-reviewing` 配对检查 |
| 10 | `../tools` | `skills/shared/crctl/scripts/crctl.mjs`（`cmdReviewLoopReset`，基线 L1821–1848） | 改 async，复用 ledger 事务助手做一次原子提交，失败回滚 |
| 11 | `../tools` | `skills/shared/crctl/scripts/lib/durable-tx.mjs`（`beginLedgerTransaction` 的 ledger write-set 前置条件，基线 L487） | 仅把 `writes.length < 2` 原位放宽为 `< 1`（FR-9 第 3 条：接受单文件 write-set、仍拒空 write-set）；不新增导出、不改 journal/manifest 结构与 recover/abort/finish 语义 |
| 12 | `../tools` | `skills/shared/crctl/SKILL.md`（`review-record` 行，基线 L34） | 原位补写 YAML 子集边界说明 |
| 13 | `../tools` | `skills/{requirement/review-requirement,develop/review-tech-design,develop/review-dev-plan,develop/review-code}/SKILL.md` | 既有 payload 示例注释原位补写单行标量约束 |
| 14 | `../tools` | 上述 8/9/10/11 四个脚本的既有测试（`scripts/test/**`） | 追加/修订覆盖新增行为的测试并有反向用例 |

### 1.3.2 目标仓库与版本

- 代码实施在 `../tools/`（crctl 脚本、`lib/durable-tx.mjs`、lint、公共 Agent Prompt、SKILL.md）与 `../multica/`（coordinator overlay、两份部署副本、`CUSTOM.md`）。
- knowledge-base 承载本 PRD 与来源文档；本 CR 不改 KB 的 `specs/`、`delivery/`、`docs/`。
- **部署不在本 CR 范围内**（来源 §1.1、§3.3）：平台 DB 的 Prompt 投影与 `multica/aifirst/agent-import.mjs` 不改，由 owner 在各 CR 落地后用 `multica agent update` 或平台等价受控入口部署。原因：该 importer **只创建不存在的 Agent，遇到同名 Agent 会 `skip`**，不能用于更新已有 Prompt。
- `target-version` 继承 `cr.md` 的 `0.36`（注册阶段由 Ray 指定），本文件不得改写该字段。`target-spec-id` 为 `ai-first-platform`，由注册事务写入双账本，本文件不得改写。

### 1.3.3 契约说明（确定性四查适用面）

本 CR 定义了两处**用户可调用的 CLI 可观察契约**变更，四查（幂等 / 权限 / 错误闭包 / 副作用）落点为 FR-7、FR-9 与 AC-7、AC-9：

- `crctl gate --mode pre-review` 的错配错误体（FR-7）；
- `crctl review-loop reset` 的原子性与失败回退（FR-9）。

其余 FR 为文档/Prompt/测试侧的原位修订（FR-1~FR-6、FR-10），不定义新的用户可调用契约；其验收以「文本合同 + 测试/检索证据」形式给出。本 CR **不新增**任何 API、子命令、账本字段或账本条目；FR-7 的 `contractDrift` 与补入的 `recoverCommand` 是**既有错误体的字段补充**（沿用既有 crctl 事务错误体 / 事务返回的同名字段命名，见 §1.4 事实 7、16），不构成新的契约面。

## 1.4 当前事实（落笔前核实）

基线（requirement worktree，register 时 ensure）：

| 仓 | worktree HEAD |
|---|---|
| `ai-first-platform-docs`（本 KB） | `00b596f9c2263fecf38c3fc616bcb1c22916bae8` |
| `../multica` | `5fde81c1f463e7031663ef8111ee0b7ce39aac3c` |
| `../tools` | `ebdd6290f1523ffb682609b7ad6ab83e7d30245e` |

以下结论均在上述 SHA 上核实（路径相对各自 worktree 根）：

| # | 结论 | 证据 |
|---|---|---|
| 1 | 需求源两处拷贝在 CRLF→LF 归一后逐字节一致 | Issue AIFI-24 附件《AIFI-18_SDD到planTASK_原位修订方案.md》与主 checkout `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md`（24585 B，SHA256 `b774e41d…`）归一后 `equal=true`；该文件当前在主 checkout 为 untracked，在 CR worktree 分支上不存在（`cr.md source` 记的是 Issue `AIFI-24`，不是路径） |
| 2 | `_context.md` 的 tools 侧活跃引用共 6 处，全部落在两个文件 | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` L1317–1318（条目 + 注释）；`skills/shared/crctl/scripts/test/crctl.test.mjs` L4554（测试名 `CR-2026-057: KB 白名单新增 _context.md…`）、L4560、L4561、L4565。`agents/`、`pipeline-templates/` 与其余 `skills/**` 命中 0 |
| 3 | `_context.md` 的 multica 侧引用共 2 处 | `cr-prompts-revised/dev-agent.md:47`（`## 环境与代码边界` 末段，L43 起）、`cr-prompts-revised/quality-reviewer-agent.md:19`（`## 入口识别与证据` 首段，L17 起） |
| 4 | Multica 副本已与 tools 公共 Prompt 分叉 | 同一检索在 `tools/agents/**` 命中 0——公共 dev/reviewer Prompt 已不含 `_context.md` 规则，Multica 仍保留旧口径 |
| 5 | `CUSTOM.md` #75 行在位且正处于「快照」定性 | `CUSTOM.md:387`：`| 75 | \`cr-prompts-revised/\`（\`agent-skill-matrix.yml\` + 5 个 Agent prompt md） | …快照…与 tools 仓实际生效 prompt 分叉时以 tools 仓为准并人工对齐 |`；该表表头为 `| # | 位置 | 改动 | 原因 / 追溯 | 日期 | 合并注意 |` |
| 6 | coordinator overlay 章节结构 | `cr-prompts-revised/cr-coordinator-agent.md`：L11 `## 职责`、L15 `## 事实源与读取`、L24 `## 路由`、L38 `## 委派与评论`、L45 `## 评审闭环`、L55 `## 平台层权限`、L63 `## 失败与输出`；目录构成 = `agent-skill-matrix.yml` + 5 个 prompt md |
| 7 | pre-review 错配当前只有裸 `BAD_ARGS` | `crctl.mjs` L957–960：`cmdGate` 内 `if (flags.mode === 'pre-review') { if (flags.for !== 'requirement-reviewing') fail('BAD_ARGS', '--mode pre-review 仅支持 --for requirement-reviewing'); … }`；`fail()`（L43–47）输出 `{error:{code,message,...extra}}` 到 stderr 并 `exit 1`，当前 extra **为空**（`gate` 错误体上不存在 `recoverCommand`；该字段名当前只出现在 `register`/`checkpoint`/`merge`/`writeback`/`archive` 的事务返回与 `TxError` extra，如 `workspace-transactions.mjs:777`/`:1074`/`:1514`/`:1945`/`:2882`/`:3460`） |
| 8 | `review-loop reset` 当前直写不提交 | `crctl.mjs` L1821 `function cmdReviewLoopReset(ws, cr, gates, flags)`（同步）；L1844 `fs.writeFileSync(p, renderLoopText(all.loops), 'utf8')` 后 L1845 `auditLog`、L1846 `ok(...)`；无 CAS、无事务、无 commit |
| 9 | reset 的既有语义与人类在环硬检查 | `crctl.mjs` L1822–1824 非 TTY → `NOT_TTY` 无旁路；L1826–1828 `--loop`/`--reason` 缺失 → `BAD_ARGS`；L1829–1832 未耗尽 → `LOOP_NOT_EXHAUSTED`；效果 = `current-cycle+1`、`current-attempt=0`、`attempts[]` 历史保留；`review-loop.yml` 由 crctl 独占（L844 `attemptsFilePath`、`renderLoopText` import L30） |
| 10 | 可复用的事务与提交助手、ledger write-set 前置条件、index 回滚机制族 | `crctl.mjs`：`casWrite` L672、`ledgerTxKey` L678、`syncLedgerIndex` L682、`recoverLedgerCommand` L691、`beginLedgerCommand` L705、`controlledGit` L412；`lib/durable-tx.mjs`：`abortLedgerTransaction` L514、`finishLedgerTransaction` L519。先例：`review-record` 用 `writes[{path,expectedHash,newText}] → beginLedgerCommand → finishLedgerTransaction`（`crctl.mjs` L2177–2195），`expectedHash` 由 `readFileChecked` 取原文 + `sha256`（L2183）。**前置条件缺口**：`beginLedgerTransaction` 拒 `writes.length < 2`（`lib/durable-tx.mjs:487`，`TX_WRITESET_INVALID`），既有 4 个调用点全部 ≥2 文件（`approve` L1130 = approval.yml+cr.md、`owner-set` L2535 = cr.md+_backlog.yml、`version-set` L2828 = cr.md+_backlog.yml+derived、`review-record` L2177–2195 = annotation+traceability，+bump 时再加 review-loop），**无单文件先例**，且当前无测试守卫该 ≥2 规则（`durable-tx.test.mjs` 只测 write-set entry 校验与 journal 形状）；空 write-set 另有 `applyWriteSet` 的 `entries.length === 0` 独立拒绝（`lib/durable-tx.mjs:311`）。**index 回滚机制族**：`syncLedgerIndex`（L682，以 `git add -A -- <relpath>` 使 index 与回滚后内容一致）用于 `approve` 提交失败路径（L1141，caller `crctl-approve`）与崩溃恢复路径（L697，caller `crctl-ledger-recovery`）；同族 `rollbackVersionWrite`（L2725：abort + 撤销暂存 + clean baseline 复核）、`rollbackOwnerWrite`（L2471） |
| 11 | 版本化 Prompt 的 R7 规则在位 | `lint-prompts.mjs` L14 规则清单注释列 R1~R9；R7 实现 L249–284（advance `--to`/`--trigger` 形态、全角/伪旗标、`backlog-set --field` 白名单、`commit --template` subject 含 CR）；当前**无** `gate --mode pre-review` 与 `--for requirement-reviewing` 的配对检查 |
| 12 | `review-record` 契约行与四份 payload 示例在位 | `skills/shared/crctl/SKILL.md:34` 为 `review-record` 行；`skills/requirement/review-requirement/SKILL.md:105–111`、`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/develop/review-code/SKILL.md` 各有 YAML payload 示例（`verdict`/`blockers`/`dimensions`/`suggestions`）；四处均无「必须单行标量」的边界说明 |
| 13 | YAML 子集解析器的既有边界 | `skills/shared/crctl/scripts/lib/yaml-subset.mjs:1–5` 头注释：支持块映射、块序列、flow 映射/序列、引号字符串、注释、`\|` 与 `>`（保守处理为拼接文本）；不支持锚点、别名、tag、多文档 |
| 14 | coordinator 的矩阵声明与 tools index 现状 | `agent-skill-matrix.yml:25–29` `actors.cr-coordinator-agent`（`kind: system`、`mode: leader`）；`agents/_index.yml` 共 9 个 agent，无 coordinator |
| 15 | 公共 dev-agent 委派段在位 | `agents/dev-agent.md:31` `## 委派路由合同（评审）` |
| 16 | CR-R 的先决约束 | 本 CR 未完成 CR-R（`recoverCommand` → 结构化 `recovery` 的原子迁移，需求见 `docs/analysis/crctl_recoverCommand结构化恢复合同_原子迁移方案.md`，独立 CR），故 FR-7/FR-9 的兼容字段 `recoverCommand` 只能是无用户输入的固定字符串。该字段在 `gate` 错误体上**当前不存在**（事实 7：extra 为空），本 CR 沿用既有 crctl 事务错误体 / 事务返回的同名命名，在 FR-7、FR-9 两处错误体上**补入**（是「补入」，不是「保留既有字段」） |

## 1.5 §3.1.5 的口径（对来源文档的解释，须在人工审批时一并确认）

来源 §3.1.5 字面要求：活跃 `agents/`、`skills/`、`pipeline-templates/` 搜索 `_context.md` **结果为 0**。但 §3.1.4 同时要求把 CR-2026-057 的既有测试**原位改成退役合同测试**并保留 `_context2.md` 反例——退役测试里必然仍出现 `_context.md` 字面量（作为「必须被拒绝的对象」）。两条要求不可能同时字面成立。

**本 PRD 采用的解释（不静默缩小 AC）**：

> 目标是「**活跃合同引用**为 0」；`scripts/test/**` 内的**负向断言字符串**不计入。

精确检索口径（AC-2 按其执行）：

- 范围：`../tools` 的 `agents/`、`skills/`、`pipeline-templates/` 三棵子树的全文件（`.md`/`.mjs`/`.js`/`.yml`/`.yaml`/`.json`/`.ts`）。
- 计入：任何**要求创建/读取/维护/放行** `_context.md` 的文本（合同语句、白名单条目、注释性说明）。
- 排除：`skills/shared/crctl/scripts/test/**` 下作为**必须被拒绝的对象**出现的字面量（退役测试名、断言字符串、测试夹具注释）。
- 判定：计入集合为空；排除集合在 `scripts/test/**` 内的出现次数不作归零要求，但必须全部是负向断言语义（正例放行断言一律不允许残留）。

`../multica` 侧同口径适用（两份部署副本归零，无测试例外）。

## 1.6 修订记录

- 初稿（2026-09-11）：按来源文档 §3 与注册摘要（`cr.md` summary）起草；三仓事实在 §1.4 所列三个 worktree HEAD 上逐条核实。§1.5 为对来源 §3.1.5 的口径解释，需人工审批确认。
- 修订 0.1.1（2026-09-11，第 1 轮需求评审回修）：关闭 **B-1**——FR-9 显式择定单文件 write-set 路径（原位放宽 `lib/durable-tx.mjs:487` 的 `writes.length < 2` 为 `< 1`，理由与两条未采用替代写在 FR-9 第 3 条），并在 FR-9 第 5 条与 AC-9② 补齐 index 回滚的既有机制口径、AC-9⑥ 给出该放宽的可验断言；同步 §1.4 事实 10（助手清单 + write-set 前置条件 + index 回滚族）、事实 7 与事实 16（`gate` 错误体 extra 为空，`recoverCommand` 是「补入」不是「保留」）；§1.3.1 的 scope_in 表新增 `lib/durable-tx.mjs` 一行并顺延后续行号，§1.3.2/NFR-1 同步该文件面。同时收口：S-1（§1.3.1 前缀句限定，multica 仓共 4 个文件）、S-2（§1.3.3 的「不新增」限定为账本字段/子命令/API）、S-3（四查落点改为 FR-7、FR-9 与 AC-7、AC-9）、S-4（FR-9 第 2 条 expected hash 改引 `review-record` 先例；`readAttempts` 不返回原文/哈希）。

# 2. 用户故事

- **US-1 后续 CR 的执行 Agent**：作为按 Pipeline 节点干活的 Agent，我希望恢复/返工时只读 canonical 事实（`crctl status/next`、`cr.md`、`review-loop.yml`、评审记录），不再被要求维护或读取 `_context.md` 这类会过期的第三副本，这样我不会基于缓存做出与门禁不一致的判断。
- **US-2 平台 owner（部署者）**：作为把 Prompt 部署进 Multica 的 owner，我希望一眼看清「公共 Prompt 的唯一事实源是 `tools/agents/`，只有 coordinator 是 Multica 专属 overlay」，这样我不会把分叉的旧副本当成规范复制上平台。
- **US-3 需求/开发 Agent 的委派接收方**：作为被委派的 Agent，我希望收到的是 CR-ID、节点/Skill 名、`crctl status/next` 结果、workspace/resources 原样值、canonical 引用与责任 Agent，而不是别人复述出来的 Skill 步骤，这样我不会照着二手算法执行。
- **US-4 自动化调用方（Skill/Pipeline/脚本）**：作为调用 `crctl gate --mode pre-review` 的一方，我希望 stage 传错时拿到「当前 stage 的正确安全恢复方向」与「是否与版本化合同漂移」的信号，而不是一条无法区分责任的 `BAD_ARGS`。
- **US-5 交互式终端前的人（人类在环）**：作为唯一被允许执行 `review-loop reset` 的人，我希望这次重置要么整体生效（文件已提交、工作区干净），要么整体无效（文件与 index 回滚、报错并留审计），这样我不会把 CR 留在一个已写未提交的中间态。
- **US-6 写评审 payload 的 reviewer**：作为写 `review-requirement.yml`/`sdd.yml` 等 payload 的 reviewer，我希望明确知道 `blockers`/`suggestions` 只能写单行标量，这样我的评审内容不会因解析口径而与落盘结果不一致。
- **US-7 评审者（CR 自身）**：作为本 CR 的 reviewer，我希望能逐条核对「哪个仓的哪个文件被原位改了」，使得这次止血不引入第二套流程或新的观测负担。

# 3. 功能需求

## FR-1 `_context.md` 活跃合同退役（来源 §3.1.1–§3.1.4）

四条原位修订，逐条落到「仓 + 文件」，**不追加新章节、不复制第二套流程**：

1. `../multica` `cr-prompts-revised/dev-agent.md`：把 `## 环境与代码边界` 末段（基线 L47）中「`change-requests/{CR-ID}/_context.md` 是允许维护的工作流导航缓存：每次本 Agent run 收尾时…刷新或创建…随 CR 一起提交」整段**替换**为 canonical resume 口径——受控账本/`review-annotations`/`review-loop`/`traceability`/`specs/` 不得手工修改，写入必须经专用 Skill/crctl；恢复或返工直接读 `crctl status {cr_id}`、`crctl next {cr_id}`、`cr.md`、`review-loop.yml` 与 canonical review annotations；**不得创建或读取 `_context.md` 等上下文副本，也不得让缓存替代状态、评审证据或门禁**。不得以「保留旧段 + 段后追加说明」的方式落地。
2. `../multica` `cr-prompts-revised/quality-reviewer-agent.md`：`## 入口识别与证据` 首段（基线 L19）删除 `_context.md` 引用，改为「评审前读取目标 workspace `dir-graph.yaml`、`crctl status/next` 返回、当前 CR canonical 产物和该 Skill 指定的证据；canonical 事实优先于缓存、评论和执行方自报」。目的：避免 owner 后续把旧缓存合同复制上平台。
3. `../tools` `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`：post-review path drift 的 `allowed` 集合（基线 L1311–1319）**删除** `change-requests/${cr}/_context.md` 条目及其上方注释（L1317–1318）。**不新增** `crProcessCachePath()`，**不放宽** `classifyRepoWorkspace()` 的 dirty 语义。删除后：评审后新增或修改 `_context.md` 与其它非白名单文件同等处理（`post-review-path-drift` 拒绝）。
4. `../tools` `skills/shared/crctl/scripts/test/crctl.test.mjs`：把 CR-2026-057 的既有测试（基线 L4554 起，名含 `_context.md` 白名单放行）**原位改成退役合同测试**，断言语义变为「`_context.md` 不再属于 post-review allowed paths；评审后新增或修改该文件必须按普通 unexpected path 拒绝」，并**保留 `_context2.md` 非白名单断言**，证明不存在前缀式放宽。禁止「保留原测试 + 旁边新增反向测试」。

## FR-2 活跃引用全量核对（来源 §3.1.5）

在 CR-P0 的变更范围内，对 `../tools` 的活跃 `agents/`、`skills/`、`pipeline-templates/` 与 `../multica` 的 `cr-prompts-revised/` 执行 `_context.md` 检索：**活跃合同引用为 0**，判定口径与排除项按 §1.5 执行。历史 CR 目录、历史 `traceability.yml`、归档 delivery 证据**不改**（不批量迁移、不重写历史）。

## FR-3 Prompt 事实源归位：`CUSTOM.md` #75 原位重写（来源 §3.2.1）

`../multica` `CUSTOM.md` 的 **#75 行职责单元格**（基线 L387）原位重写，明确：

- 公共 Agent Prompt（requirement/dev/reviewer/delivery 等）的**唯一事实源是 `tools/agents/`**；
- `cr-prompts-revised/cr-coordinator-agent.md` 是 **Multica 专属 overlay**；
- 目录中的公共 Prompt 副本**不再独立演进**，owner 部署时以 tools 同名文件覆盖平台公共 Agent；
- **DB 是部署投影，不是事实源**（禁止把 DB/UI 临时编辑反向当规范）；
- `cr-coordinator-agent` **不进入 tools agent index**。

约束：**不新增登记行**、不在 `CUSTOM.md` 后追加第二份事实源说明、不改变该表其它行；`:387` 所在表结构与列语义不变（`位置`/`改动`/`原因 / 追溯`/`日期`/`合并注意`）。

## FR-4 矩阵与索引不改动（来源 §3.2.2）

以下三处**保持现状**，本 CR 不得改动（作为反向验收对象）：

- `../tools` `agents/_index.yml`：**不新增** `cr-coordinator-agent`（基线 9 个 agent）；
- `../tools` `agent-skill-matrix.yml`：**保留**既有 `cr-coordinator-agent` system actor 权限声明（基线 L25–29）；该声明是平台 actor 的公共权限边界，不因 prompt 文件不在 tools 而另造第二份；
- `../multica` `cr-prompts-revised/agent-skill-matrix.yml`：不作为公共矩阵独立演进（本 CR 不改）。

## FR-5 Multica coordinator overlay 三处原位替换（来源 §3.3）

目标文件 `../multica` `cr-prompts-revised/cr-coordinator-agent.md`。**保留**当前正确的 `## 职责`、`## 事实源与读取`、`## 路由`、`## 平台层权限` 与只读约束（不得整文件推倒重写），**原位替换**以下三处：

1. `## 委派与评论`（基线 L38）：标准 Pipeline 节点只通过平台已有 Runner 启动目标 Agent；Runner 提供的固定 PipelinePrompt、canonical feedback、attempt、source task 与 executor 是该次委派的权威输入，本 Agent 不在评论中复制它们的执行算法。计划外人工委派只传以下事实：CR-ID、当前 Pipeline 节点或 Skill 名、`crctl status/next` 的当前返回、权威 workspace/resources **原样值**、canonical feedback 路径或对象引用、当前责任 Agent；**不得**复述 Skill/Pipeline 步骤，不得内联状态推进或 Git 命令，不得把 blocker 正文改写成新的执行步骤，不得声明未来节点已经满足。`mention://agent/<id>` 是立即创建/唤醒目标 task/run 的工作委派而非抄送；串行交接的一条评论只 mention 一个当前目标，下一节点或复评者只作纯文本说明；每次触发后记录一次 squad activity。
2. `## 评审闭环`（基线 L45）：保留既有 BLOCK / Suggestions / alignment 责任边界，原位改写**标准评审入口**——标准 Pipeline 评审由 Pipeline Runner 按 registry 节点启动新的 `quality-reviewer-agent` task/run，协调者不得用评论重建 review Skill 的步骤；评审 BLOCK 按 `review-record` 返回的 `repair-target` 与 Pipeline `reviewLoop` 处理；协调者只在 repair target 无效、最大轮次耗尽、权限/事实冲突、技术失败或人工 gate 时介入。
3. `## 失败与输出`（基线 L63）：在既有失败 bullet 内**原位扩写**——当评论、Agent Prompt 与当前 Skill/Pipeline 事实发生冲突时，停止该次手工委派，报告 `CONTRACT_DRIFT` 与冲突两侧，不自行选择一套步骤继续；来自 crctl 的恢复信息只逐字段转发，不改写为协调者自己的 Git/状态序列。

约束：本修改是 **Prompt 合同缓解**，不宣称平台已新增运行时委派校验；owner 将该文件复制到平台后才生效（部署不在本 CR 范围）。

## FR-6 公共 dev-agent 委派合同（来源 §3.4）

`../tools` `agents/dev-agent.md` 的 `## 委派路由合同（评审）`（基线 L31）原位修改为：

- 每轮评审使用**新的** reviewer task/run；
- 标准节点走 Pipeline Runner；
- 仅传 review Skill 已声明的结构化输入和 canonical 引用；
- **不**在委派评论中复述 Skill 步骤、门禁命令、advance 参数或 blocker 修法；
- 若 Agent 临时生成的**只读**命令出现零写入 `BAD_ARGS`，可按 crctl 明示的恢复方向恢复一次；
- 若错误命令来自**版本化 Skill/Pipeline**，当前 run 可按安全恢复完成，但**必须同时报告 `CONTRACT_DRIFT`**，不得以成功掩盖合同错误。

约束：**不新增** R14 委派 lint（来源 §1.3/§3.4：无法检查真实运行期评论的规则不引入）。

## FR-7 `gate --mode pre-review` 错配可操作化（来源 §3.5.1）

目标：`../tools` `skills/shared/crctl/scripts/crctl.mjs` 的 `cmdGate()` 中 `--mode pre-review` 分支（基线 L959–960）。行为合同：

- **保留** `BAD_ARGS` 错误码与**零写入**（进程退出码非 0，stderr JSON 形如 `{error:{code:'BAD_ARGS', …}}`）；
- 明确 `--mode pre-review` 仅支持 `--for requirement-reviewing`；
- 对其它 stage 返回**stage 专属安全恢复方向**：固定为 `crctl workspace inspect <cr_id>` 形态（`<cr_id>` 取自被调用的 CR，不含任何用户自由输入）；
- 返回布尔 `contractDrift: true`，提示调用方检查权威 Skill/Pipeline；该字段在本 CR 中**恒为 `true`**，不携带区分信息，只是「须复核权威 Skill/Pipeline」的固定提示，调用方不得据此反推漂移类型（该定位的说明归 SDD）；
- **补入**兼容字段 `recoverCommand`：沿用既有 crctl 事务错误体 / 事务返回的同名命名（`register`/`checkpoint`/`merge`/`writeback`/`archive`，见 §1.4 事实 7、16），在本错误体上新增该字段，值**只能是无用户输入的固定字符串**（本 CR 未完成 CR-R，结构化 `recovery` 不在范围）；
- `--for requirement-reviewing` 的既有 pre-review 检查序列行为**不变**（既有门禁测试全绿）。

## FR-8 版本化 Prompt 的配对 lint（来源 §3.5.2）

`../tools` `skills/shared/crctl/scripts/lint-prompts.mjs` 的 R7 规则内（基线 L249–284）**原位加入配对检查**：文本中出现 `gate --mode pre-review` 时，必须同时出现 `--for requirement-reviewing`，否则产生 `R7` 级 finding。

约束：该规则只防**版本化 Prompt 漂移**；**不**用于声称真实运行期评论已被机械限制；不新增规则编号（不新增 R14 之类的委派 lint），不改变既有 R7 判据（advance 参数形态、`backlog-set --field` 白名单、`commit --template` subject）。

## FR-9 `review-loop reset` 原子提交（来源 §3.6）

目标：`../tools` `skills/shared/crctl/scripts/crctl.mjs#cmdReviewLoopReset`（基线 L1821）。行为合同：

1. 函数改为 `async`；dispatcher 保持 `return cmdReviewLoopReset(...)`，由既有 `async main()` 接管（不改调用形态）。
2. 读取 attempts 状态时取得**目标文件 expected hash**：以 `readFileChecked` 取 `review-loop.yml` 原文 + `sha256` 作为 `expectedHash`（先例 `review-record`，`crctl.mjs` L2183、L2193）。`readAttempts` 只返回状态投影（`current`/`max`/`attempts`/`cycle`/`cycleAttempts`/`exhausted`/`data`），**不返回原文或哈希**，不承担 CAS 取值；事务路径的 CAS 由 ledger 事务按 `expectedHash` 自行校验，不经过 `casWrite`。
3. 复用既有助手完成一次事务写：命令入口先 `recoverLedgerCommand(ws, ledgerTxKey('reset', cr, loopRef))`（本事务键下的残留幂等回滚/确认，外部 dirty 不受影响，口径同 `approve`/`version-set`），随后 `beginLedgerCommand` → `controlledGit` add/commit → `abortLedgerTransaction`/`finishLedgerTransaction`（先例见 §1.4 事实 10）。
   - **write-set 构成（本 CR 择一结论）**：`reset` 的 write-set **只有 `review-loop.yml` 一个文件**（`auditLog` 走 `.crctl/` 审计域，不进 git 事务）。
   - **单文件路径的落地方式**：把 `lib/durable-tx.mjs:487` 的 ledger 前置条件 `writes.length < 2` **原位放宽为 `writes.length < 1`**——仍拒绝空 write-set，但接受单文件 write-set。
   - **理由**：该前置条件的作用只是「拒绝空 write-set」（空集另有 `applyWriteSet` 的 `entries.length === 0` 独立拒绝，`lib/durable-tx.mjs:311`），`>= 2` 的数值来自既有 4 个调用点的形态、不是可回滚性的必要条件——单条目与多条目的 prepare/apply/rollback 路径完全同构（逐条 CAS 校验、逐条 before 快照回滚）；既有 4 个调用点（`approve`/`owner-set`/`version-set`/`review-record`）全部传 ≥2 文件，故该放宽对它们**零行为差异**。
   - **不采用的替代**：(b) 在 write-set 中塞入一个内容不变的第二个文件——会让第 4 条「commit 只包含 `review-loop.yml`」与 FR-11 的零无关改动口径变成假象；(c) 绕开 `beginLedgerCommand` 自建写入路径——被第 7 条禁止，且 `casWrite` 单文件直写不提供崩溃可恢复与 index 回滚，无法满足 AC-9②。
   - 该放宽是本 FR 对 `lib/durable-tx.mjs` 在**行为面**的唯一改动：不新增导出、不改 journal/manifest 结构、不改 `recover`/`abort`/`finish` 语义。
4. commit **只包含 `review-loop.yml`**（`controlledGit add` 只 stage 该路径），提交消息保留 `[cr]` 前缀并带 transaction id（`AI-First-Tx: <txId>` trailer；事务按 `commitRequired=true` 记账，供崩溃后「已提交 / 未提交」判定，口径同 `approve`）。
5. add/commit 失败时按 §1.4 事实 10 的既有机制族回滚，**不得留下 dirty 中间态**：`abortLedgerTransaction(tx)` 按 journal 把 `review-loop.yml` 还原为执行前内容，随后 `syncLedgerIndex(ws, rolled.paths, 'crctl-review-loop-reset')`（`git add -A -- <relpath>`）使 index 与该文件回滚后的内容一致——执行前 tracked-clean 时即回到执行前状态（先例：`approve` 失败路径 `crctl.mjs` L1141、`version-set` 的 `rollbackVersionWrite` L2725、`owner-set` 的 `rollbackOwnerWrite` L2471）；之后写审计并返回失败。
6. 在 CR-R 之前，失败结果可继续返回兼容 `recoverCommand`（沿用既有 crctl 事务错误体的同一命名，在本错误体上**补入**），但**不得把用户输入的 `reason` 拼入字符串**（TTY 重试时重新输入 reason）。
7. **不**新写事务框架 / primitive（仅复用既有 ledger 事务助手 + 上述前置条件数值放宽），**不**把 reset 并入 checkpoint，**不**放宽 controlled-shell 全局规则。
8. 既有语义不变：非 TTY → `NOT_TTY`（无旁路参数/环境变量）；缺 `--loop`/`--reason` → `BAD_ARGS`；未耗尽 → `LOOP_NOT_EXHAUSTED`；成功效果 = `current-cycle+1`、`current-attempt=0`、`attempts[]` 历史保留；`review-loop.yml` 仍由 crctl 独占。

## FR-10 `review-record` payload 的 YAML 子集边界（来源 §3.7）

两处**原位补写**（只说明既有事实，**不换解析器**）：

- `../tools` `skills/shared/crctl/SKILL.md` 的既有 `review-record` 行（基线 L34）：写明 payload 中 `blockers` / `suggestions` 等值必须使用 **YAML 子集支持的单行标量**；不得使用多行引号标量或折叠块；说明依据是既有 `lib/yaml-subset.mjs` 的解析边界（块标量 `|`/`>` 仅保守拼接为文本，锚点/别名/tag/多文档不支持）。
- 各 review Skill 的既有 payload 示例注释（`requirement/review-requirement`、`develop/review-tech-design`、`develop/review-dev-plan`、`develop/review-code`）：在示例处补同一约束，**不新增字段、不新增维度、不改示例结构**。

约束：本 FR 是**文档侧**说明；`lib/yaml-subset.mjs` 行为与实现零改动。

## FR-11 零新增与不修改边界

本 CR 的交付 diff 必须体现下列「不改动」事实（来源 §1.3/§1.4/§7）：

- 不新增 SLO、M1–M8 指标、P50/P90、连续 N 个 CR 统计、为复盘计数新增的账本字段或 Prompt 要求、「评审轮数必须降到某个数」的门禁；
- 不新增 R14 委派 lint；
- 不换 YAML 解析器、不放宽其解析边界；
- 不改平台 DB，不改 `../multica` `aifirst/agent-import.mjs`；
- 不新增 Pipeline 节点、不新增评审维度、不新增委派平台 API、不新增 context 生成器/`crProcessCachePath()`、不为 context commit 放宽 `rules.json`、不让 README 复制可执行步骤事实源；
- 不改 CR 状态机/`gates.json`/状态推进路径。

# 4. 非功能需求

- **NFR-1 兼容性（最重要）**：`../tools` 全量既有测试（crctl、ledger/durable-tx、prompt lint、pipeline structure、contract-scan 等）保持通过；`crctl` 既有子命令的**成功路径输出与退出码不变**（本 CR 只改一份错配错误体、一个内部写入路径及其复用的 ledger write-set 前置条件一处数值，不改任何成功输出契约）。
- **NFR-2 幂等与可重入**：`review-loop reset` 的写入以目标文件 expected hash 为前提；同一次重试不产生第二个 cycle（失败回滚后重跑必须等价于一次干净执行）；`gate --mode pre-review` 保持零写入，可任意重放。
- **NFR-3 确定性（无自由输入进入恢复字符串）**：所有人类可读的恢复方向/`recoverCommand` 字符串**不含**用户输入（`reason` 等），防止把用户文本拼进可被复制的命令。
- **NFR-4 行尾纪律**：所有对仓库文件的哈希、跨行正则、逐行解析相关代码与测试在读写前做 `\r\n → \n` 归一；解析失败**硬失败报错**，禁止静默降级（工作区纪律 #1，本 CR 触及 crctl 脚本与测试，直接适用）。
- **NFR-5 审计与可追溯**：`reset` 保持既有 `auditLog` 记录（`kind: review-loop-reset`，含 `fromCycle`/`toCycle`/`reason`/`by`）；事务提交带 transaction id；失败路径同样落审计。Prompt/文档侧修改不新增运行时埋点。
- **NFR-6 语言与措辞**：`../multica` 仓文档按其 `CLAUDE.md` 规则以中文书写既有内容为准，本 CR 只改写既有中文段落；`../tools` 侧文档/CR 产物用中文，代码注释按既有文件语言。
- **NFR-7 无部署副作用**：本 CR 不触发平台 Agent DB 更新；`multica agent update` 等部署动作由 owner 在 CR 落地后执行。

# 5. 验收标准

| ID | 覆盖 FR | 来源 | 可执行验收 |
|---|---|---|---|
| AC-1 | FR-1 | §3.1.1–§3.1.4 | 四处原位修订全部落地：①`cr-prompts-revised/dev-agent.md` 的 `## 环境与代码边界` 段内不再出现 `_context.md` 且含 canonical resume 口径（`crctl status`/`crctl next`/`cr.md`/`review-loop.yml`/canonical annotations）；②`cr-prompts-revised/quality-reviewer-agent.md` 的 `## 入口识别与证据` 首段不再出现 `_context.md`；③`workspace-transactions.mjs` 的 `allowed` 集合不含 `_context.md` 条目（且无 `crProcessCachePath`、`classifyRepoWorkspace` 零 diff）；④`crctl.test.mjs` 中原 CR-2026-057 测试已原位改为退役语义，新语义断言「`_context.md` 评审后变更 → `post-review-path-drift` 拒绝」，且保留 `_context2.md` 非白名单断言。同一测试文件中不存在「旧放行断言 + 新拒绝断言」并存的重复测试。 |
| AC-2 | FR-2、FR-1 | §3.1.5（口径见 §1.5） | 按 §1.5 口径检索：计入集合（要求创建/读取/维护/放行 `_context.md` 的文本）在 `../tools` 的 `agents/`、`skills/`、`pipeline-templates/` 与 `../multica` 的 `cr-prompts-revised/` 中为 **0**；排除集合（`skills/shared/crctl/scripts/test/**` 的负向断言字面量）出现处均为拒绝语义断言，无正例放行残留。检索命令与命中清单作为交付证据（含 `--include`/排除路径与行尾归一处理）。 |
| AC-3 | FR-3 | §3.2.1 | `CUSTOM.md` 的 **#75 行职责单元格**同时包含五要素：`tools/agents/` 为公共唯一事实源、coordinator 为 Multica 专属 overlay、目录内公共副本不再独立演进（owner 以 tools 覆盖平台公共 Agent）、DB 是部署投影、coordinator 不进 tools agent index；表格行数与其它行文字零 diff（除该单元格）。 |
| AC-4 | FR-4 | §3.2.2 | `git diff` 显示 `tools/agents/_index.yml`、`tools/agent-skill-matrix.yml`、`multica/cr-prompts-revised/agent-skill-matrix.yml` **零改动**；`agents/_index.yml` 仍为 9 个 agent，`agent-skill-matrix.yml` 的 `cr-coordinator-agent`（`kind: system`/`mode: leader`）声明保留。 |
| AC-5 | FR-5 | §3.3 | `cr-coordinator-agent.md` 的 `## 委派与评论`、`## 评审闭环`、`## 失败与输出` 三节内容与 §3.3.1/§3.3.2/§3.3.3 合同逐条对应（含「只传事实与 canonical 引用」「一条评论只 mention 一个当前目标」「标准评审由 Runner 启动新 reviewer task/run」「`CONTRACT_DRIFT` 停手报告」）；`## 职责`/`## 事实源与读取`/`## 路由`/`## 平台层权限` 四节与文件 frontmatter 保持原样；文件内不出现 Skill/Pipeline 步骤复述或 Git/状态推进命令。 |
| AC-6 | FR-6 | §3.4 | `agents/dev-agent.md` 的 `## 委派路由合同（评审）` 含六条要求（新 task/run、Runner、只传声明输入与 canonical 引用、不复述步骤/门禁/advance/修法、只读 `BAD_ARGS` 可恢复一次、版本化来源错误须同时报 `CONTRACT_DRIFT`）；`lint-prompts.mjs` 中不存在 R14 或等价委派 lint 规则。 |
| AC-7 | FR-7 | §3.5.1 | `crctl gate --mode pre-review --for <非 requirement-reviewing 的 stage>` 在真实 workspace 上：退出码非 0；stderr JSON 的 `error.code === 'BAD_ARGS'`；`error.contractDrift === true`；错误体含形如 `crctl workspace inspect <cr_id>` 的恢复方向；`error.recoverCommand` 存在且为固定字符串、不含任何用户输入；执行前后 worktree 文件哈希集合零变化（零写入）。`--for requirement-reviewing` 的既有 pre-review 检查行为与既有测试结果不变。 |
| AC-8 | FR-8 | §3.5.2 | lint 单元向量：文本含 `gate --mode pre-review` 而缺 `--for requirement-reviewing` → 产生 R7 finding；两者同时出现 → 不产生；既有 R7 向量（advance 形态、`backlog-set` 白名单、`--template` subject）结果不变；无新增规则编号。 |
| AC-9 | FR-9 | §3.6 | ①reset 成功路径：`review-loop.yml` 的变更**已被提交**（提交只包含该文件、消息含 `[cr]` 前缀与 transaction id），`git status --porcelain` 为空；②add/commit 故障注入（既有 fault 机制）→ 命令失败返回，`review-loop.yml` 按 journal 还原、index 经 `syncLedgerIndex`（`git add -A --`）回到与执行前一致的状态（无 dirty 残留），审计已写；③失败或成功结果中的 `recoverCommand` 均不含 `--reason` 的用户文本；④非 TTY → `NOT_TTY`、未耗尽 → `LOOP_NOT_EXHAUSTED`、缺参 → `BAD_ARGS` 三条既有行为不变；⑤成功后 `current-cycle` 递增 1、`current-attempt=0`、`attempts[]` 历史条目保留；⑥单文件 write-set 路径成立：`beginLedgerTransaction` 接受 `writes.length === 1` 并完成 prepare/apply/finish，空 write-set 仍抛 `TX_WRITESET_INVALID`，既有 4 个调用点（`approve`/`owner-set`/`version-set`/`review-record`）的既有事务测试全绿。 |
| AC-10 | FR-10 | §3.7 | `crctl/SKILL.md` 的 `review-record` 行与四份 review Skill 的 payload 示例处均出现「单行标量」边界说明（含「不得使用多行引号标量或折叠块」）；`lib/yaml-subset.mjs` 零 diff；payload 示例结构（字段名与层级）不变、未新增字段。 |
| AC-11 | FR-11 | §1.3/§1.4/§7 | 交付 diff 中：无新增 SLO/M1–M8/P50–P90/计数门禁/账本字段/评审维度/Pipeline 节点；无 `crProcessCachePath`；`rules.json` 零 diff；`multica/aifirst/agent-import.mjs` 零 diff；`../multica` 平台侧除 §1.3.1 列出的 4 个文件外无其它改动。 |
| AC-12 | 全部 | §3.8 | `../tools` 全量既有测试通过（crctl、ledger/durable-tx、prompt lint、pipeline structure、contract-scan 及本 CR 新增/修订的用例），且 `../multica` 侧被改文件不引入语法/结构破损（Markdown 表格结构、frontmatter 完整）。 |

来源 §3.8 验收清单与上表映射：活跃 Agent/Skill/Pipeline 不再引用 `_context.md` → AC-1/AC-2；post-review 白名单不再包含 `_context.md` → AC-1③；旧 CR-2026-057 测试已原位改为退役测试 → AC-1④；tools 不新增 coordinator prompt → AC-4；coordinator overlay 不含手写 Skill/Pipeline 步骤 → AC-5；`gate --mode pre-review` 错配由既有 lint 抓住 → AC-8；reset 成功后工作区 clean、add/commit 故障时文件与 index 回滚 → AC-9；recover 字符串不包含用户 reason → AC-9③；全量既有测试通过 → AC-12。

# 6. 成功指标

- 活跃 `_context.md` **合同引用**数 = 0（按 §1.5 口径，含 `../multica` 侧）。
- post-review 白名单中 `_context.md` 条目数 = 0。
- `gate --mode pre-review` 错配时返回「stage 专属恢复方向 + `contractDrift`」的比例 = 100%（无裸 `BAD_ARGS`）。
- `review-loop reset` 成功后的 dirty 中间态数 = 0；add/commit 故障场景的「文件/index 回滚 + 审计落盘」成功率 = 100%。
- 恢复类字符串包含用户输入（`reason`）的处数 = 0。
- 本 CR 新增的观测指标 / 计数门禁 / Pipeline 节点 / 评审维度 / 账本字段数 = 0。
- 既有测试回归数 = 0。

# 7. 范围排除

以下内容明确不做：

**来源文档层面的排除项**

- 新增 SLO、M1–M8 指标、P50/P90、连续 N 个 CR 统计、「评审轮数降到某个数」的门禁，以及为复盘计数新增的账本字段或 Prompt 要求（来源 §1.4）。
- 新增 R14 委派 lint（来源 §1.3/§3.4：无法检查真实运行期评论）。
- 更换 YAML 解析器或放宽其解析边界（来源 §3.7）——本 CR 只补写既有边界说明。
- 历史 CR 目录的 `_context.md`、历史 `traceability.yml`、归档 delivery 证据的批量迁移或重写（来源 §1.2）。
- 平台 DB 的 Prompt 更新与 `../multica` `aifirst/agent-import.mjs` 的改造（来源 §1.1：importer 只创建不更新；部署由 owner 在 CR 落地后执行）。
- coordinator 进入 `tools/agents/_index.yml`；新增平台委派 schema；新事务框架；新 context 生成器；新 Pipeline 节点；新评审维度或观测指标；为 context commit 放宽 `rules.json`；README 复制可执行步骤事实源（来源 §7）。

**CR 边界（独立 CR，不得并入本 CR）**

- **CR-R：结构化恢复合同原子迁移**（全局 `recoverCommand` → `recovery`，生产者/消费者同 CR 迁移，无双写期）——需求文档已存在（`docs/analysis/crctl_recoverCommand结构化恢复合同_原子迁移方案.md`），独立评审、审批与回滚。本 CR 的 `reset` 兼容止血在 CR-R 落地后由其原位替换。
- **CR-P1：评审输入结构与回修闭合**（来源 §5）。
- **CR-P2：plan/TASK 返工成本与执行前提**（来源 §6）。
- 来源 §2 明确：四个 CR 分别评审、审批、回滚，**不得合并为一个发布单元**。

**本次明确不碰的既有资产**

- CR 状态机、`gates/`、`reviewLoop`/`replayNodes`/`maxAttempts` 语义、CAS 与 durable ledger transaction 框架、controlled-shell 与 `rules.json`、`ENVIRONMENT_MISMATCH`、Pipeline Runner 结构化节点输入、版本化 `cmd-NN` 与 test evidence（来源 §7「继续复用、不再造」）。
- KB 的 `specs/`、`delivery/`、`docs/`（本 CR 不改知识库文档；主 checkout 中 `docs/analysis/` 的既有未提交变动属 Ray 的文档归位操作，不在本 CR 范围）。
