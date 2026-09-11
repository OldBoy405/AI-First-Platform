---
id: CR-2026-063-sdd
type: SDD
cr-ref: CR-2026-063
title: CR-P0 流程正确性止血 — `_context.md` 合同退役、Prompt 源/overlay 归位、委派合同收紧、crctl 原子性与错误可操作化 技术设计
target-version: 0.36
status: draft
created: 2026-09-11T18:22:49+08:00
updated: 2026-09-11T20:18:49+08:00
---

# 0. 阅读约定

- 本 SDD 的技术输入是 `change-requests/CR-2026-063/prd.md`（修订 0.1.1，SHA256 `9247c107b1f87b72a5ee4ec5750f2f1da8be784aed04d23f47bb8d153eabda70`，已人工审批绑定）。**本 SDD 不改 `prd.md`**；所有措辞修正、口径补充、被 PRD 显式延后到 SDD 的设计项均只写在本文件。
- 正文对既有实现的引用一律以 `dep-N` 形式指向第 10 节「既有实现依赖与事实」的唯一定义（第 10 节按正文首次出现顺序编号）；正文不复述既有行为细节，避免第二份事实定义。
- 路径 authority：所有代码事实只按 `crctl workspace inspect CR-2026-063` 返回的 `resources[].worktreePath` 取（本 CR 三个资源见 §1.4），**不拼接** `.rayai-worktrees/...`，不回退主工作区。

# 1. 架构概览

## 1.1 变更性质：原位修订，不新增架构层

本 CR 是**流程正确性止血**：7 组改动全部落在既有模块的既有位置（既有函数 / 既有 Skill 段落 / 既有测试 / 既有 Prompt 文件），不新增模块、不新增依赖方向、不新增状态或账本文件（PRD §1.1、FR-11）。

改动分布在四个层次，各自只做"原位替换"：

| 层 | 落点 | 改动性质 |
|---|---|---|
| CLI 契约层 | `crctl.mjs`（`cmdGate` pre-review 分支、`cmdReviewLoopReset`） | 一处错误体补字段；一处写入路径由直写改为事务提交 |
| 持久化原语层 | `lib/durable-tx.mjs`（ledger write-set 前置条件） | 一处数值放宽（`< 2` → `< 1`），语义边界不动 |
| 工作区事务层 | `lib/workspace-transactions.mjs`（post-review `allowed` 集合） | 删除一个白名单条目与其注释 |
| 提示词/校验层 | `multica/cr-prompts-revised/*`、`multica/CUSTOM.md`、`tools/agents/dev-agent.md`、`tools/skills/**/SKILL.md`、`lint-prompts.mjs` | 文本原位替换 + 一条既有规则内新增配对判据 |

**架构不变量核对（`tools/ARCHITECTURE.md` §5，逐条；dep-25）**：

- 不变量 1（状态单一写者）：`reset` 不写 CR status，本 CR 不改 `advance` 路径 ✅
- 不变量 2（账本单一写入通道）：`reset` 仍经 crctl 写入，且本次改造把它从"直写"升级为"经既有 ledger 事务写入"，方向与不变量一致 ✅
- 不变量 3（零第三方依赖）：无新增 import，无新增依赖 ✅
- 不变量 4（行尾与硬失败纪律）：`reset` 的 CAS 取哈希使用未归一的原文读取结果（与事务内部 `readHash` 同源，见 §4.2 步骤 4），`renderLoopText` 输出 LF-only；本 CR 不新增可能静默降级的跨行正则 ✅
- 不变量 5（状态机口径唯一）：不改 `dir-graph.yaml` / `gates.json` / 状态机声明 ✅
- 不变量 6（git 权威、outbox 投影）：`reset` 不新增 outbox 事件；本 CR 不改事件面 ✅
- 不变量 7（人工审批无旁路）：`reset` 的非 TTY 硬检查保持原样（无旁路参数/环境变量）✅
- 不变量 8（Skill 通用、约束归仓）：改动只提升/落实现有通用合同，不引入产品专属约束 ✅
- §6 刻意不做：不新增账本脚本库、不新增第二套 WAL/事务框架、不引入 YAML 库 ✅

## 1.2 模块边界与依赖方向

```text
multica/cr-prompts-revised/*  （平台 Prompt 副本 / coordinator overlay，部署侧）
multica/CUSTOM.md             （fork 台账，登记口径）
        │  owner 部署（不在本 CR 范围）
        ▼
tools/agents/*.md             （公共 Agent Prompt 唯一事实源）
tools/skills/**/SKILL.md      （流程合同；只描述"读什么/写什么/调哪个子命令"）
        │  crctl 为唯一账本写入执行器（依赖只朝下）
        ▼
tools/skills/shared/crctl/scripts/crctl.mjs          （CLI + 门禁 + 事务编排）
        ├─ lib/durable-tx.mjs          （journal / 锁 / recoverable write-set）
        └─ lib/workspace-transactions.mjs（repository/workspace 事务与账本编解码）
```

本 CR 不改变上述方向：`lib/` 不被 CLI 之外的东西依赖，`crctl.mjs` 不 import `multica/`，multica 侧改动全部是文本文件（Prompt / 台账 / Markdown），不引入任何构建或运行时耦合。跨仓依赖方向为**单向声明式**：multica 的部署副本以 tools 为事实源（FR-3 的登记口径），不存在反向引用。

## 1.3 关键流程

**流程 A：`_context.md` 活跃合同退役（FR-1/FR-2）**

```text
tools 侧：删除 post-review allowed 条目 ──┐
                                        ├─► 退役后语义：_context.md 与其它非白名单文件同等处理
tools 侧：CR-2026-057 测试原位改为退役测试 ─┘   （评审后新增/修改 → post-review-path-drift 拒绝）
multica 侧：两份部署副本删除 _context.md 段落 ──► owner 后续部署时不再把旧缓存合同复制上平台
全量核对：计入集合（agents/skills/pipeline-templates + multica/cr-prompts-revised）命中数必须为 0
```

**流程 B：Prompt 事实源归位（FR-3/FR-4）**

```text
CUSTOM.md#75 职责单元格改写（五要素）  → 公共 Prompt 唯一事实源 = tools/agents/
                                        coordinator = Multica 专属 overlay
                                        DB = 部署投影（非事实源）
矩阵与索引：零改动（反向验收对象）
```

**流程 C：`review-loop reset` 原子提交（FR-9）**

```text
TTY 硬检查 → 参数检查 → 残留事务恢复 → 耗尽判定 → 读取 expected hash
   → 单文件 write-set 事务写（review-loop.yml） → git add（只该路径）
      → 提交隔离前置（index 恰等于 write-set 且无其它 unstaged 变更）
         → git commit（带 tx trailer）
            ├─ 成功 → finish 事务 → 审计 → 输出（字段与改造前一致，不含 recoverCommand）
            └─ 隔离前置不成立 / commit 失败
                  → 按 journal 回滚文件 → syncLedgerIndex 恢复 index → clean 复核
                     ├─ 复核通过 → 审计（result=commit-failed）→ REVIEW_LOOP_RESET_COMMIT_FAILED + recoverCommand → 退出 1
                     └─ 复核/恢复失败 → 审计（同语义，先于 fail）→ REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED + affected → 退出 1
```

**流程 D：错配错误的可操作化（FR-7/FR-8）**

```text
crctl gate --mode pre-review --for <非 requirement-reviewing>
   → BAD_ARGS + 零写入 + contractDrift:true + recoverCommand（固定形态，无自由输入）
lint-prompts R7（版本化 Prompt 侧配对检查）
   → 出现 gate + --mode pre-review 而未声明 --for requirement-reviewing ⇒ R7 finding
```

## 1.4 多仓边界与提交/checkpoint 口径

`crctl workspace inspect CR-2026-063` 返回的三个资源（本次运行实测，`HEAD` 由受控只读取得）：

| repo | worktreePath（路径 authority 原样值） | 分支 | HEAD |
|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-063` | `requirement/CR-2026-063` | `132c953da23c83546c95baf21bc9c2e39c2ec2a0` |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-063` | `requirement/CR-2026-063` | `5fde81c1f463e7031663ef8111ee0b7ce39aac3c` |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-063` | `requirement/CR-2026-063` | `ebdd6290f1523ffb682609b7ad6ab83e7d30245e` |

表内 HEAD 为采写时刻（`crctl workspace inspect` + 受控只读）的快照。knowledge-base 仓的 HEAD 会随本 CR 的每次产物/状态提交前移（本 SDD 自身的落盘与状态推进提交均在其后），按 CR-2026-060 的同款口径，**KB 的 HEAD 不作为依赖证据**；第 10 节的既有实现依赖只绑定 tools（`ebdd6290…`）与 multica（`5fde81c1…`）两仓 HEAD，评审时以受控只读重核这两个 SHA 未变即可。

- 本 SDD 落 knowledge-base 的 operational workspace（`change-requests/CR-2026-063/sdd.md`），**不写 `specs/`**。
- 代码/文本改动按所属仓分别落在该仓 worktree：`multica` 4 个文件、`tools` 为代码与 Prompt 主体（清单以 PRD §1.3.1 为准）；各仓分别提交，架构审批后由同一批 `crctl checkpoint` 纳入（PRD §1.3.2）。
- 跨仓改动不存在运行时依赖，只有"事实源 → 部署副本"的登记关系；因此不需要跨仓事务，`checkpoint` 的既有"全仓 source commit → publish"语义足够。

# 2. 数据模型

## 2.1 无 DDL / schema 变更（N/A + 理由）

本 CR 不涉及数据库 schema、迁移、迁移登记或写路径鉴权（PRD §1.3.3：本 CR 不新增 API、子命令、账本字段或账本条目；`reset` 的权限模型沿用既有"仅交互式 TTY 人类在环"约束）。因此**不触发** write-tech-design 的"数据/schema 变更与写路径鉴权完整性"条件节；不涉及 down migration、约束缺失窗口或 DDL 规范。

## 2.2 受影响的数据实体（全部为既有文件，结构不变）

| 实体 | 位置 | 本 CR 的影响 | 结构 |
|---|---|---|---|
| `review-loop.yml` | `change-requests/{CR-ID}/review-loop.yml` | 写入路径由"直写 + 无 CAS + 无 commit"改为"单文件 ledger 事务 + commit"；语义（`current-cycle+1`、`current-attempt=0`、`attempts[]` 保留）不变 | **不变**（仍由 `renderLoopText` 全量生成，LF-only，dep-11） |
| ledger journal | `{toolsRoot}/.crctl/transactions/ledger/{key}/{txId}` | `reset` 首次使用该域：键 `reset-{CR-ID}-{loopRef}`（`ledgerTxKey`，dep-3） | **不变**（沿用既有 envelope 与 write-set slot，dep-8） |
| `gate` 错配错误体 | stderr JSON | 新增两个字段 `contractDrift`、`recoverCommand` | 既有 `{error:{code,message,...extra}}` 形态不变（dep-1） |
| `CUSTOM.md` #75 行 | `multica/CUSTOM.md` | 第 3 列（职责/改动）单元格文本重写 | 表结构与列语义不变（dep-24） |
| 四类 Prompt/文档 | multica 3 个 prompt + tools 1 个 agent prompt + tools 5 处 SKILL.md | 段落级原位替换/补写 | 文件结构（章节、frontmatter、表格列）不变 |

无新增实体、无新增字段落到任何账本文件。

## 2.3 文件级回滚语义（`reset` 的数据变更回滚）

`reset` 是本 CR 唯一的"数据变更 + 回滚"复合改动，其回滚语义按既有机制族给出（dep-8、dep-3）：

| 阶段 | 崩溃/失败点 | 回滚依据 | 回滚后状态 |
|---|---|---|---|
| apply 完成、complete 前 | journal `phase=prepared`/`written` | `recoverLedgerTransaction` 读 journal payload 的 `beforeText` 逐条还原 | 文件回到执行前内容 |
| 提交隔离前置不成立（执行前已有 staged 变更） | 不进入 commit（步骤 12 判定） | 同下一行（不 commit 本身也是回滚理由） | 文件与 index 回到执行前；**外来 staged 变更不属本命令，不被回滚也不被夹带**（随后 clean 复核将不过 → `..._ROLLBACK_FAILED`） |
| commit 失败（进程内） | 事务对象仍在手 | `abortLedgerTransaction(tx)` + `syncLedgerIndex` | 文件与 index 都回到执行前（执行前 tracked-clean 时为完全 clean） |
| commit 成功后、complete 前 | HEAD 含 `AI-First-Tx: <txId>` | `recoverLedgerTransaction` 用 trailer 判定"已提交"，只清 journal | 保留已提交事实，不重复写入 |

部分状态语义：**不存在"文件已改但 index 未改"的可观测中间态**——失败路径先还原文件再 `git add -A -- <relpath>` 使 index 与还原后内容一致（dep-3 `syncLedgerIndex`）。**恢复链自身失败**（journal 还原遇第三值、index 恢复的 `git add` 失败等）不产生第三种中间态：它先落审计再以 `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED` 退出，**不得**以内部 `TX_*` 码对外（§3.2、§3.5、§4.2.1 步骤 13）。

# 3. 接口契约

## 3.1 `crctl gate --mode pre-review` 错配错误体（FR-7）

**触发条件**：`crctl gate <CR-ID> --mode pre-review` 且 `--for != requirement-reviewing`。

**契约（stderr JSON，进程退出码 1，零写入）**：

```json
{
  "error": {
    "code": "BAD_ARGS",
    "message": "--mode pre-review 仅支持 --for requirement-reviewing；该调用与版本化 Skill/Pipeline 的声明不一致（contractDrift=true），请复核权威 Skill/Pipeline 中该 stage 的门禁入口，勿继续按当前参数重试",
    "contractDrift": true,
    "recoverCommand": "crctl workspace inspect CR-2026-063"
  }
}
```

| 字段 | 类型 | 状态 | 语义 |
|---|---|---|---|
| `error.code` | string | 不变 | 恒为 `BAD_ARGS`（PRD FR-7 第 1 条；不换错误码） |
| `error.message` | string | 改写 | 说明唯一支持的 `--for`，并声明须复核权威 Skill/Pipeline |
| `error.contractDrift` | boolean | **新增** | 恒为 `true` 的固定常量（见 §3.1.1） |
| `error.recoverCommand` | string | **新增** | 固定形态恢复方向，取值算法见 §4.1.1；不含任何自由文本输入 |

**副作用**：零写入（`fail()` 只写 stderr 后 `process.exit(1)`，dep-1）；可任意重放。

**`--for requirement-reviewing` 的正常路径**：既有检查序列与输出**完全不变**（AC-7 的"既有行为不变"约束）。

### 3.1.1 `contractDrift` 恒为 `true` 的定位（PRD 显式延后到 SDD 的设计项）

- 本字段**不携带区分信息**：本 CR 只有一种错配形态（`--mode pre-review` 与非 requirement stage 组合），因此恒为 `true`。
- 它的语义是**固定提示**："该调用与版本化 Skill/Pipeline 的声明不一致，须复核权威 Skill/Pipeline"。它**不是**漂移类型分类器，调用方**不得**据此反推"漂移发生在本轮调用的哪一侧"。
- 调用方的正确处理：停止按当前参数重试 → 按 `recoverCommand`（`crctl workspace inspect <CR-ID>`）复核 workspace 与 resources → 回到对应 stage 的权威 Skill/Pipeline 声明的门禁入口。
- 结构化恢复合同（`recoverCommand` → `recovery`）属独立 CR-R（PRD §7），本 CR 只保证字段存在且值确定。

## 3.2 `crctl review-loop reset` 命令契约（FR-9）

**调用形态（不改）**：`crctl review-loop reset <CR-ID> --loop <ref> --reason <text> [--workspace <path>]`

| 维度 | 契约 |
|---|---|
| 权限 | 仅交互式 TTY 人类在环，无旁路参数/环境变量（非 TTY → `NOT_TTY`，exit 1，零写入） |
| 输入约束 | `--loop` 必填且须为 `gates.json` 已声明 reviewLoop（否则 `UNKNOWN_LOOP`）；`--reason` 必填非空（否则 `BAD_ARGS`） |
| 前置状态 | 该 loop 已耗尽（`current >= maxAttempts`）；否则 `LOOP_NOT_EXHAUSTED`，零写入 |
| 成功副作用 | `review-loop.yml` 内容变更**已被提交**（提交只含该文件，消息 `[cr] ` 前缀 + `AI-First-Tx: <txId>` trailer）；`current-cycle` 递增 1；`current-attempt=0`；`attempts[]` 历史条目保留；`.crctl/audit.log` 追加一条 `kind=review-loop-reset` |
| 成功输出 | **与改造前字段集完全一致**：`op`/`cr`/`loop`/`current-cycle`/`current-attempt`/`file`/`reason`（exit 0）；**不含 `recoverCommand`**（见下「`recoverCommand` 出现面」行） |
| 提交隔离前置（步骤 12，FR-9 第 4 条的唯一保证手段） | `git add` 只 stage `review-loop.yml` 一个路径；**commit 之前**断言 `queryTrackedChanges`（dep-7）的 `unstaged` 为空且 `staged` 恰为 `[review-loop.yml]`（镜像 dep-5 的 `owner-set` L2541–2543 / `version-set` L2832–2833 同款断言）。断言不成立（含执行前已存在 staged 变更、或 `git add` 本身失败）⇒ **不执行 commit**，直接进入步骤 13 的失败回滚路径（因此外来 staged 变更永不被夹带进提交） |
| 失败输出（commit 失败） | exit 1；`error.code = REVIEW_LOOP_RESET_COMMIT_FAILED`；extra `{changed:false, rolled_back:true, recoverCommand}`；**两个产生点**：①步骤 12 的提交隔离断言不成立；②断言成立但 `git commit` 命令失败；文件与 index 已回到执行前（执行前 tracked-clean 时即完全 clean）；审计已写（`kind=review-loop-reset`、`result: commit-failed`） |
| 失败输出（回滚未完成） | exit 1；`error.code = REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`；extra `{affected:[<relpath>]}`（与 dep-5 的 `OWNER_COMMIT_ROLLBACK_FAILED` 同族口径）；**唯一产生点 = 步骤 13 的 try/catch**：恢复链三步任一失败——①`abortLedgerTransaction` 的 journal 还原（可抛 `TX_JOURNAL_INVALID` / `TX_RECOVERY_CONFLICT`，dep-8）、②`syncLedgerIndex` 的 index 恢复（可抛 `TX_GIT_FAILED`，dep-26）、③还原后的 tracked-clean 复核（含执行前已存在 staged 变更使 clean 复核不过的情形）。这三步在步骤 13 内**直接 `await` / 直接调用**，**禁止**经 `runTxAsync` 包装（该 helper 捕获 `TxError` 后调用 `fail()` → `process.exit(1)`，会让本地 `catch` 与审计永不执行，dep-3），因此上述内部 `TX_*` 码一律被本地 `catch` 收敛为本码、**不得**作为对外退出码出现；审计在 `fail()` 之前落盘，语义同上一行 |
| `recoverCommand` 出现面 | **只出现在失败结果与 FR-7 错误体**：`REVIEW_LOOP_RESET_COMMIT_FAILED` 的 `error.recoverCommand`、`crctl gate --mode pre-review` 错配错误体（§3.1）；`..._ROLLBACK_FAILED` 携带 `affected` 而不携带 `recoverCommand`（同族口径）；成功结果**不含该字段**（字段集不变，NFR-1）。因此对恢复串的断言（AC-7/AC-9③）**只以失败结果与 FR-7 错误体为对象**，不对成功结果作恢复串断言 |
| 幂等与可重入 | 以目标文件 expected hash 为前提；同事务键残留先恢复再执行；失败回滚后重跑等价于一次干净执行（NFR-2） |
| 无自由输入进入恢复串 | `recoverCommand` 的 `--reason` 位置使用占位符 `<reason>`，用户文本永不拼接（NFR-3）；CR-ID 位置按 §4.1.1 的语法判定内插或回退占位符 |

## 3.3 `beginLedgerTransaction` 的 ledger write-set 前置条件（FR-9 第 3 条，内部契约）

| 项 | 改造前 | 改造后 |
|---|---|---|
| 前置条件 | `writes.length < 2` → `TX_WRITESET_INVALID`（dep-8） | `writes.length < 1` → `TX_WRITESET_INVALID` |
| 空 write-set | 由本前置条件与 `applyWriteSet` 双重拒绝（dep-8） | 仍被双重拒绝（行为不变） |
| 单文件 write-set | 被拒 | 接受，走同一 prepare/apply/rollback 路径 |
| 既有 4 个调用点（`approve`/`owner-set`/`version-set`/`review-record`，文件构成与行号见 dep-8） | 全部 ≥2 文件 | **零行为差异**（全部满足 `< 1` 判定） |
| journal / manifest 结构、`recover`/`abort`/`finish` 语义、导出面 | — | **零改动**（PRD §1.3.1 第 11 行"仅放宽前置条件"） |

## 3.4 非 CLI 契约

**A. `lint-prompts` R7 判定契约（FR-8）**

- 触发（行级，判定面与既有 R7 子判据一致，均为"段落内逐行"）：同一行同时满足 `\bgate\b` 与子串 `--mode pre-review`。
- 必要条件：同一行包含 `--for requirement-reviewing`。
- 违反输出：`rule = R7`，`level = CONTRADICTS`，`file:line` + why，**不新增规则编号**（不引入 R14 之类）。
- 豁免：沿用既有 `<!-- lint-prompts:ignore -->` ±1 行机制（dep-15）；`--mode report` 仍退出 0，`--mode enforce` 命中即 `LINT_DRIFT` 退出 1。
- 声明边界：本规则只防**版本化 Prompt 漂移**，不声称约束真实运行期评论（PRD FR-8 约束段）。

**B. Prompt 文本契约（FR-1/FR-3/FR-5/FR-6）**

- multica 两份部署副本：`_context.md` 段落被 §6 FR-1 给出的目标文本原位替换；替换后两份文件均不出现 `_context.md`。
- coordinator overlay：三节的目标文本**逐字固化在本 SDD §6.2**（含三块的替换边界、旧块/替换块的逐块 `sha256`、LF 归一口径与来源文件 SHA256）；实现期**逐字复制，不得转述**，不得改写标点、空格、换行或代码标记（AC-5 的锚点因此落在 CR worktree 内，不再依赖 worktree 之外的来源副本）；**块 3 按 §6.2 的两行替换块固化（旧 bullet 逐字保留 + 行首两空格的插入行）**，不是“在节内找个位置插一段”的自由形式；其余四节与 frontmatter 保持原样。
- `tools/agents/dev-agent.md`：`## 委派路由合同（评审）` 内含六条要求（新 task/run、Runner、只传声明输入与 canonical 引用、不复述步骤/门禁/advance/修法、只读 `BAD_ARGS` 可恢复一次、版本化来源错误须同时报 `CONTRACT_DRIFT`）。
- `CUSTOM.md` #75 职责单元格含五要素（AC-3）。

**C. HTTP / REST 契约**：N/A。本 CR 不新增或修改任何 HTTP API，不触发 FR-08 的条件基线。

## 3.5 契约确定性四查（对应 PRD §1.3.3 的落点）

| 检查 | `gate --mode pre-review` 错配（FR-7） | `review-loop reset`（FR-9） |
|---|---|---|
| 幂等 | 只读路径，可任意重放，无副产物 | 以 expected hash 为前提；同命令残留按 journal 恢复；重复调用在"未耗尽"时拒绝（不产生第二个 cycle） |
| 权限 | 无权限面（零写入只读 CLI） | 既有 TTY 人类在环硬检查，无旁路；不改 `rules.json`（受控 git 仍按既有白名单三元组放行） |
| 错误闭包 | `BAD_ARGS` + `contractDrift` + `recoverCommand`（§3.1） | `NOT_TTY` / `BAD_ARGS` / `UNKNOWN_LOOP` / `LOOP_NOT_EXHAUSTED` / `CAS_CONFLICT`（事务内抖动）/ `REVIEW_LOOP_RESET_COMMIT_FAILED`（步骤 12 隔离断言不成立或 commit 命令失败）/ `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`（步骤 13 恢复链任一环失败，镜像 dep-5）。**对外错误闭包到此为止**：恢复链内部抛出的 `TX_JOURNAL_INVALID` / `TX_RECOVERY_CONFLICT`（dep-8 的 journal 还原）与 `TX_GIT_FAILED`（dep-26 的 index 恢复）是**内部底层原因**，一律由步骤 13 的本地 catch 映射为上述唯一码后对外，不得以 `TX_*` 形式退出（§3.2「失败输出（回滚未完成）」行、§4.2.1 步骤 13） |
| 副作用 | 零写入 | 单文件 commit + 审计一条；**两条失败路径同样落审计**（`kind=review-loop-reset`、`result: commit-failed`，含 `fromCycle`/`toCycle`/`reason`/`by`，不新增字段）；无 outbox、无状态推进、无网络 |

# 4. 关键算法与流程

## 4.1 `cmdGate` pre-review 分支的错配返回（FR-7）

### 4.1.1 `recoverCommand` 的取值算法（确定性 + 无自由输入）

```text
输入：cr（cmdGate 的位置参数，即被调用的 CR）
1. crId = /^CR-\d{4}-\d{3,}$/.test(String(cr)) ? String(cr) : '<CR-ID>'
2. recoverCommand = `crctl workspace inspect ${crId}`
```

- **为什么内插 CR**：PRD FR-7 第 3 条要求"`<cr_id>` 取自被调用的 CR"——恢复方向必须指向本次调用的对象，才是可执行方向。
- **为什么先做语法判定**：CR-ID 是本命令自身的位置参数（命令主语），不是自由文本；但 `requireCr()`（dep-6）只判"非空"，不判语法。加一层语法判定后，任何非规范形态的回退为占位符 `<CR-ID>`，从而保证恢复串**永不包含任意 argv 文本**，满足 NFR-3「不含任何用户输入」与 AC-7「固定字符串、不含任何用户输入」的严格读法。
- 占位符形态有既有先例：`crctl test` 的 `recoverCommand` 同样带 `<plan>` / `<worktree>` 占位符（dep-11）。
- 该 helper 供 FR-7 与 FR-9 共用（一处定义、两处调用，避免复制正则）。

### 4.1.2 判定树

```text
cmdGate(ws, cr, gates, flags)
  if (!flags.for) → fail(BAD_ARGS, 'gate 需要 --for <target-status>')            [不变]
  if (flags.mode === 'pre-review'):
      if (flags.for !== 'requirement-reviewing'):
          fail('BAD_ARGS',
               '--mode pre-review 仅支持 --for requirement-reviewing；…（§3.1 message）',
               { contractDrift: true,
                 recoverCommand: `crctl workspace inspect ${crIdForRecover(cr)}` })
      else:
          runPreReviewGateChecks(...)   [既有序列，行为与输出不变]
  else:
      runGateChecks(...)                [不变]
```

关键性质：两条 `fail` 分支都在**任何写入之前**（`cmdGate` 全程无写路径），因此"零写入"由结构保证，不依赖额外检查。

## 4.2 `cmdReviewLoopReset` 原子提交时序（FR-9）

### 4.2.1 步骤

```text
async function cmdReviewLoopReset(ws, cr, gates, flags):
  1  非 TTY → fail('NOT_TTY')                                        [不变，在一切写入之前]
  2  --loop 缺失 → fail('BAD_ARGS')                                   [不变]
  3  --reason 缺失/空白 → fail('BAD_ARGS')                            [不变]
  4  await recoverLedgerCommand(ws, ledgerTxKey('reset', cr, loopRef))
        # 本事务键下的残留幂等回滚/确认；必须先于任何状态判断，
        # 否则上一轮崩溃留下的"新内容"会被误判为"未耗尽"而永久卡住
  5  state = readAttempts(ws, cr, loopRef, gates)                     [既有：取 current/max/attempts/cycle]
  6  !state.exhausted → fail('LOOP_NOT_EXHAUSTED', …, {current, max})  [不变]
  7  p = attemptsFilePath(ws, cr); raw = readFileChecked(p)
     expectedHash = raw == null ? null : sha256(raw)
        # 与事务内部 readHash 同源（同为未归一原文的 utf8 sha256），保证 CAS 判定一致；
        # 文件不存在时传 null（事务按"新建文件"处理），不新造错误分支
  8  由 state.data 组装 all.loops[loopRef] = { current-cycle: fromCycle+1, current-attempt: 0,
                                              attempts: [...(prev.attempts||[])] }
     newText = renderLoopText(all.loops)                              # LF-only（dep-11）
  9  rel = path.relative(ws, p).split(path.sep).join('/')
  10 ledgerTx = await beginLedgerCommand(ws, key,
                    [{ path: p, expectedHash, newText }], true /* commitRequired */)
        # 单文件 write-set：依赖 §3.3 的前置条件放宽；CAS 由事务按 expectedHash 自行校验
  11 addR = controlledGit(ws, 'add', ['-A', '--', rel], ws, 'crctl-review-loop-reset')
  12 # 提交隔离前置（镜像 dep-5 的 owner-set L2541–2543 / version-set L2832–2833）：
     iso = queryTrackedChanges(ws, { audit:false })      # staged = git diff --name-only --cached；unstaged = git diff --name-only -- .（dep-7）
     isolated = addR.ok && iso.ok && iso.unstaged.length === 0 && JSON.stringify(iso.staged) === JSON.stringify([rel])
        # isolated=true ⇒ index 恰等于 write-set 且工作区无其它 tracked 未暂存变更 ⇒
        #   commit 只可能包含 review-loop.yml（FR-9 第 4 条）
        # isolated=false（含执行前已存在 staged/unstaged 变更、或 git add 失败）⇒ 不执行 commit，直接进步骤 13
     commitR = isolated
       ? controlledGit(ws, 'commit', ['-m',
           `[cr] review-loop reset ${cr} ${loopRef} cycle ${fromCycle} -> ${nextCycle}\n\nAI-First-Tx: ${ledgerTx.txId}`],
           ws, 'crctl-review-loop-reset')
       : { ok:false, code:'NOT_ISOLATED' }                # 不为该情形新造错误码，统一走步骤 13 的两类失败码
     success = isolated && commitR.ok
  13 if (!success):
         try {                                              # 恢复链：与 dep-5 的 rollbackOwnerWrite / rollbackVersionWrite 同构
             rolled = await abortLedgerTransaction(ledgerTx)                  # 按 journal 的 beforeText 还原文件
                                                                             # 直接 await：TxError 原样抛出，交本 catch 映射
                                                                             # （runTxAsync 会把 TxError 转成 fail()→process.exit(1)，本 catch 永不执行，dep-3）
             if (rolled.paths.length) syncLedgerIndex(ws, rolled.paths, 'crctl-review-loop-reset')
                                                                             # git add -A -- <rel>：index 与还原后内容一致
                                                                             # 直接调用：失败抛 TX_GIT_FAILED，同样由本 catch 映射
             clean = queryTrackedChanges(ws, { audit:true })
             if (!clean.ok || clean.staged.length || clean.unstaged.length) {
               throw new Error(`clean baseline 复核失败 staged=[${(clean.staged||[]).join(',')}] unstaged=[${(clean.unstaged||[]).join(',')}]`)
             }
         } catch (e) {
             auditLog(ws, { kind:'review-loop-reset', cr, loop:loopRef, fromCycle, toCycle:nextCycle,
                            reason, by: identity(ws), result:'commit-failed' })   # 审计先于 fail，语义同下一行
             fail('REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED',
                  `提交失败后的恢复未完成：${String(e && e.message || e)}`, { affected: [rel] })
         }
         auditLog(ws, { kind:'review-loop-reset', cr, loop:loopRef, fromCycle, toCycle:nextCycle,
                        reason, by: identity(ws), result:'commit-failed' })
         fail('REVIEW_LOOP_RESET_COMMIT_FAILED', '…已按 journal 还原并撤销暂存', {
              changed:false, rolled_back:true,
              recoverCommand: `crctl review-loop reset ${crIdForRecover(cr)} --loop ${loopRef} --reason <reason>` })
  14 else:
         await injectLedgerFault('ledger-after-commit')      # 与 approve 同款崩溃窗口挂接（dep-5）
         await runTxAsync(finishLedgerTransaction(ledgerTx))
         auditLog(ws, { kind:'review-loop-reset', cr, loop:loopRef, fromCycle, toCycle:nextCycle,
                        reason, by: identity(ws) })
         ok({ op:'review-loop-reset', cr, loop:loopRef, 'current-cycle':nextCycle,
              'current-attempt':0, file:p, reason })          # 字段集与改造前一致（不含 recoverCommand）
```

步骤 12/13 的三条设计要点（对应本轮上游回修 B-01；PRD FR-9 第 4/5/6 条）：

1. **FR-9 第 4 条的保证手段唯一定位在步骤 12**：仅靠"`git add` 只加了一个路径"不能保证 commit 的内容（`git commit` 提交整个 index）。步骤 12 的 `isolated` 断言把"提交只含 `review-loop.yml`"变成可在提交前判定的事实，并且不成立时**不提交**——执行前已存在的 staged 变更因此永远进不了 commit（也不会被本命令回滚或改写，只会在步骤 13 的 clean 复核处暴露）。
2. **`REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED` 的唯一产生点是步骤 13 的 catch，且恢复链不经过 `runTxAsync`**：`abortLedgerTransaction` / `syncLedgerIndex` / clean 复核三者任一失败都在此转成该码（不再像改造前那样以 `TX_*` 透传），与 dep-5 的 `OWNER_COMMIT_ROLLBACK_FAILED` / `VERSION_SET_COMMIT_ROLLBACK_FAILED` 同族同形（`{affected}`、无 `recoverCommand`）。**实现约束**：恢复链两步必须在本地 `try` 内直接调用（`await abortLedgerTransaction(tx)`、`syncLedgerIndex(ws, rolled.paths, 'crctl-review-loop-reset')`）——若包进 `runTxAsync`，`TxError` 会先被该 helper 交给 `fail()` → `process.exit(1)`，本 catch 与其审计都不会执行，「唯一产生点」被破坏（本轮上游回修 B-01 的根因）；可验向量见 §4.2.2 W2c。
3. **两条失败路径的审计语义相同且显式**：`kind='review-loop-reset'`、`result='commit-failed'`（既有字段与取值，不新增审计字段）、`fromCycle`/`toCycle`/`reason`/`by` 与成功路径同形；两者的区分由**返回错误码与 `error.extra`** 承担，而不是审计字段（NFR-5 只要求"失败路径同样落审计"）。

> 既有用例夹具（AC-9⑤，dep-14）：`crctl.test.mjs:3430` 现有 reset 耗尽态用例使用**非 git** 夹具 `makeWorkspace()`；改造后步骤 11–12 必做 `git add`/`git commit`，该用例**必须**迁移到 `makeGitWorkspace()`（必要时补一次基线 commit 以建立 HEAD）且**断言与断言语义逐字不变**；该迁移属 PRD §1.3.1 第 14 行"既有测试修订"面，不是对 `reset` 契约的放宽。

### 4.2.2 崩溃/失败窗口真值表（AC-9① ② 与 FR-9 第 4 条的判定口径）

| 窗口 | 注入方式（既有机制，不新增 fault point） | 中断时盘上状态 | 同命令下次行为 |
|---|---|---|---|
| W1 apply 完成、complete 标记前 | `CRCTL_FAULT_POINT=tx-apply-before-complete`（dep-9） | 文件=新内容；journal=`prepared/written`；HEAD 未变 | 步骤 4 判定未提交 → 按 journal 还原到执行前 → 继续执行一次干净 reset（只递增一次 cycle） |
| W2 add/commit 失败（进程内） | git `pre-commit` hook `exit 1`（dep-13 先例） | 文件=新内容且已暂存；HEAD 未变 | 步骤 13 立即还原文件 + 恢复 index；退出 1 并写审计；重跑（修好 hook 后）等价于一次干净执行 |
| W2b 提交隔离前置不成立（执行前已有 staged 变更） | 测试夹具在 reset 前 `git add` 一个无关文件（同一 git 夹具） | 文件=新内容且已暂存；无关文件仍 staged；HEAD 未变 | 步骤 12 判定 `isolated=false` ⇒ **不执行 commit**；步骤 13 还原 `review-loop.yml` 并恢复其 index；clean 复核因无关 staged 仍在而失败 ⇒ `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`（`affected:[<relpath>]`）；无关 staged 变更保持原样、未被提交、未被夹带 |
| W2c 恢复链自身失败（`TxError` 向量） | git `pre-commit` hook **先把 `review-loop.yml` 写成第三值、再 `exit 1`**（同一既有 `core.hooksPath` + hook 机制，dep-13；不新增 fault point） | 文件=第三值；journal 仍在（`prepared`/`written`）；HEAD 未变 | 步骤 12 提交失败 → 步骤 13 的 `abortLedgerTransaction` 按 journal 校验当前 hash ∈ {before, after} 失败 ⇒ 抛 `TX_RECOVERY_CONFLICT`（dep-8）⇒ 本地 catch 映射 `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`（`affected:[rel]`）+ 审计（`result=commit-failed`）+ exit 1；**不得**以 `TX_RECOVERY_CONFLICT` 退出——该项即「恢复链不经 `runTxAsync`」的可验向量 |
| W3 commit 成功、complete 前 | `CRCTL_FAULT_POINT=ledger-after-commit` | 文件=新内容**且已提交**（HEAD 含 `AI-First-Tx: <txId>`）；journal 未清理 | 步骤 4 用 trailer 判定"已提交"→ 只清理 journal，**不重复递增**；随后按当前状态返回 `LOOP_NOT_EXHAUSTED`（重置已成事实） |
| W4 无残留 | — | clean | 正常执行 |

W3 的分支价值：验证 `commitRequired=true` 的"已提交/未提交"判定口径与 `approve` 一致；W1/W2 覆盖"未提交 → 必须回滚且不留 dirty 中间态"；W2b 覆盖"外来 staged 变更不被夹带"；W2c 覆盖"恢复链内部 `TxError` 被收敛为唯一对外码、不泄漏 `TX_*`"。

步骤 5 的 `readAttempts`、步骤 7 的 `attemptsFilePath`/`readFileChecked`/`sha256`、步骤 13/14 的 `auditLog`/`identity` 均为既有符号（dep-7、dep-3），本 CR 不重写它们。

## 4.3 `lint-prompts.mjs` R7 配对判定算法（FR-8）

在既有 R7 段落内（dep-15）的逐行循环中新增一个子判据（**位置：既有 `advance` / `backlog-set` / `commit --template` 三个子判据之后，仍在 `for (let li = 0; li < lines.length; li++)` 循环内**）：

```text
for each line l of paragraph:
    hasGate      = /\bgate\b/.test(l)
    hasMode      = l.includes('--mode pre-review')
    hasForPair   = l.includes('--for requirement-reviewing')
    if (hasGate && hasMode && !hasForPair):
        findings.push({ rule:'R7', level:'CONTRADICTS', file: ctx.file, line: para.startLine + li,
                        why: 'gate --mode pre-review 必须同时声明 --for requirement-reviewing' })
```

设计要点：

1. **为什么用 `\bgate\b` 而不是字面 `gate --mode pre-review`**：真实命令形态是 `crctl gate <CR-ID> --for <stage> --mode pre-review`，`gate` 与 `--mode pre-review` 之间隔着 `--for`，字面相邻匹配抓不到任何真实漂移。用词边界 `\bgate\b`（`\b` 视 `-` 为非词字符，故不会命中 `gateway`/`delegate`）与 `--mode pre-review` 组合，既覆盖 AC-8 的字面向量（`gate --mode pre-review` 同时含两 token），也覆盖真实的错序形态。
2. **为什么必要条件放在同一行**：既有 R7 的四类子判据全部是行级判定（`l.includes(...)` 模式），保持同族；行级判定使 finding 的 `file:line` 直接指向需要修改的物理行。
3. **不新增规则编号**：finding 的 `rule` 仍是 `R7`，与 PRD FR-8 约束一致（不新增 R14 之类委派 lint）。
4. **零误报证据**：本 CR 基线（dep-21）中 `--mode pre-review` 在 lint 扫描面内只出现 1 行，该行同时含 `--for requirement-reviewing` → 加入本条判据后 `lint-prompts --mode enforce` 在 tools 基线仍为 0 findings。

## 4.4 `_context.md` 退役后的 post-review 漂移判定（FR-1③）

删除 `allowed` 集合中的该条目后（dep-10），漂移判定保持既有算法不变：

```text
unexpected = changedPaths(reviewedSha..HEAD) \ (allowed ∪ review-annotations/ 前缀)
unexpected 非空 → bad('code', { reason:'post-review-path-drift', repo, unexpected })
```

删除后的语义 = `_context.md` 与任意其它非白名单文件同等处理（评审后新增或修改 → 拒绝）；**不新增** `crProcessCachePath()`，**不放宽** `classifyRepoWorkspace()` 的 dirty 语义（PRD FR-1③ 明文）。

## 4.5 AC-2 的检索核对算法（口径落地，PRD §1.5 已由人工审批确认）

按已确认口径执行，**不重新解释、不放宽**：

```text
计入集合（必须为 0 命中）：
  tools   : agents/  skills/  pipeline-templates/        全文件（.md/.mjs/.js/.yml/.yaml/.json/.ts）
  multica : cr-prompts-revised/                          全文件（同扩展面）
排除集合（不作归零要求，但命中必须全部为负向断言语义）：
  tools   : skills/shared/crctl/scripts/test/**
```

执行方式（作为交付证据记录命令与命中清单）：

```powershell
$repo = '<resources[].worktreePath>'
$inc = @('agents','skills','pipeline-templates') | ForEach-Object { Join-Path $repo $_ }
Get-ChildItem -Path $inc -Recurse -File `
  | Where-Object { $_.FullName -notmatch '\\scripts\\test\\' } `
  | Select-String -Pattern '_context.md' -SimpleMatch
# 期望：无输出（命中数 0）

Get-ChildItem -Path (Join-Path $repo 'skills\shared\crctl\scripts\test') -Recurse -File `
  | Select-String -Pattern '_context.md' -SimpleMatch
# 期望：仅退役测试的负向断言（测试名/断言字符串），无正例放行断言
```

判定与证据要求：

- 字面量检索不受行尾差异影响；命中清单仍须按工作区纪律 #1 报"检索命令 + 归一后行号"。
- 排除集合内的每一处命中都必须能读出「拒绝 `_context.md`」语义；出现任何「放行 `_context.md`」的正例断言即判不通过（AC-2）。
- 该判定是**人工逐条 + 命中清单证据**（S-5：机械化属新 lint/新规则范围，不在本 CR）。

## 4.6 验收证据命令契约（AC-12 全量回归分区 / `crctl test` 执行语义）

本节固定 canonical 证据命令（`plan.md` 证据命令表 → `cr-test-plan/v1` → `crctl test`）必须满足的契约；它是 AC-12 可达性的前提，也是本轮上游回修 B-04/B-05 的 SDD 侧落点（执行细节仍由 `write-test-report` 与 `crctl test` 承担，本 CR 不改它们）。

### 4.6.1 执行语义（既有契约，不得假设其它语义；dep-28）

`crctl test` 对每条命令以 `spawnSync(executable, args, { cwd: <repo worktree>/<cwd>, shell:false, env: 去掉 CRCTL_OPERATIONAL_WORKSPACE })` 执行，并逐条发布：

- `sourceRevision` = 该命令 `cwd` 目录的 `git rev-parse HEAD`，即 **`repo` 列对应仓 worktree 的 HEAD**（不是执行脚本所在仓的 HEAD）；
- `test-evidence/cmd-NN.log` 及其 `logSha256`；`skipped` 只按 stdout/stderr 两段匹配冻结模式表计算。

推论（命令设计必须遵守）：

1. **`repo` 列是"被测仓"，也是该命令 `sourceRevision` 的唯一绑定面**：`cwd` 必须是**相对路径且落在该仓 worktree 内**（`parseTestPlan` 对绝对路径 / `..` / 越出 worktree 一律 `TEST_CWD_ESCAPE`），`sourceRevision` = **该仓 worktree 的 HEAD**（同一 worktree 下任何 `cwd` 取值都是同一个 HEAD，dep-28）。因此：
   - `args` 里的**相对路径一律从该仓 worktree 解析**：`repo=multica` 的命令不得引用只存在于 `tools` 仓的相对脚本（旧 plan 的 `cmd-09` 即此错）。
   - **跨仓只读核对不得把 `repo` 改成"脚本所在仓"**：脚本用**绝对、正斜杠化**路径引用（脚本可以在 `tools`，`repo` 仍保持为被验收对象仓），否则 `sourceRevision` 只会绑定到脚本所在仓、无法证明目标仓对应修订上的验收事实（例如 tools 脚本读 multica 时，日志不绑定 multica 的被测 SHA）；`crctl git` 的 `--cwd`/`--workspace` 是 crctl 自旗标、不透传给 git，只能作为命令内部的读手段，不改变 `repo` 列与 `sourceRevision` 的绑定关系。
   - **被读仓的 revision 必须由同一 plan 内的另一条 canonical 命令绑定**：对每条跨仓断言，plan 必须同时包含 `repo` = 每个被读仓的绑定命令（`args` 只引用该仓内路径或绝对路径，例如既有的 `crctl git --cwd <该仓 worktree 绝对路径> rev-parse HEAD`），其 `sourceRevision` + `cmd-NN.log` 即该仓 revision 的证据；一条跨仓断言的证据面 = 「对象仓 `sourceRevision`」+「被读仓 `sourceRevision`」两条记录的组合，缺一即该断言不可证明。
   - 若某断言无法用"对象仓 `repo` + 绝对脚本路径"表达（例如断言主体本身就是脚本所在仓），则**拆成两条命令**分属两仓、各自绑定 `sourceRevision`，不得合并为一条。
2. **路径注入必须 JSON/JS 安全**：把 worktree 绝对路径注入 `node -e` 脚本的字符串字面量时，必须使用正斜杠形式（`C:/Users/...`）或 JSON 安全转义（`C:\\Users\\...`）；**禁止**把反斜杠路径原样拼进单引号字面量（`\U` 会被吞成 `U`，脚本静默指向错误路径）。
3. **冻结前必须按同一语义干跑**：每条含脚本路径或注入路径的 cmd-NN 在写入 plan 证据表之前，必须以 `spawnSync(executable, args, { cwd, shell:false })` 在真实 worktree 上执行一次，并把干跑结论（可达性 + 当前预期失败集/命中清单）记入 plan 对应行；"表格可读"不等于"命令可执行"。

### 4.6.2 AC-12 全量回归分区

- **全集定义（枚举，不断言计数）**：`tools/skills/shared/crctl/scripts/test/` 下全部 `*.test.mjs`（本轮枚举 **21** 个，逐文件清单见 §6.3）。该目录另有 1 个非测试辅助模块 `merge-fixture.mjs`（被测试 import、不含 `test()`）：plan 必须对其给出显式处置（纳入某条命令以证明可加载，或声明非测试文件并给出依据），**不得静默遗漏**；两类文件的并集 = 目录内全部 22 个文件（旧 plan 的"22 个"是目录文件总数；`*.test.mjs` 枚实为 21 个 —— 计数口径必须以枚举派生，不得写成断言）。
- **无重不漏分区**：全集必须被 canonical `cmd-NN` 的 args **恰好一次**覆盖——各命令的测试文件集合两两不相交，并集等于全集。不得把任何文件留在 `cmd-NN` 之外以"implement 期验证项"形式承载（那样没有 `sourceRevision`/日志绑定，也无固定证据）。
- **预算可达**：全集单跑实测 **857 s**（§6.3：21 个文件、dot reporter、exit=1 因 5 条登记基线红），加上 lint 与断言类命令后必须落在 `write-test-report` 节点 `timeoutMinutes=20` 的预算内；任一条命令的 `timeoutSeconds` 必须 ≥ 该命令实测时长。
- **例外锚定**：`--test-skip-pattern` 只准排除 §6.3 登记的 5 条**完整测试名**，模式必须是这些名字（正则元字符转义后）的**锚定交替**（`^(?:名字1|名字2|…)$`）；**禁止**未锚定片段（片段会连带静默跳过名字包含该片段的新用例 → 假绿）。fail-closed：例外拼写失效 → 该用例真跑 → 红 → exit 1。
- **`skipped` 语义**：全部命令统一 `--test-reporter=dot`（冻结模式表会把 node 默认 spec reporter 摘要中的 `skipped` 字样误判为 skip）；任一命令 `skipped=true` 不接受为通过。

# 5. 技术选型与替代方案

按 write-tech-design Step 2.5 的三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代）记录 3 条决策；不满足三判据的事项不记录（§5.4 列出未记录项及理由）。

## 5.1 D-1：单文件 write-set 走"原位放宽前置条件"

- **Decision**：`reset` 的 write-set 只含 `review-loop.yml`，把 `lib/durable-tx.mjs` 的 `writes.length < 2` 原位放宽为 `< 1`（dep-8）。
- **Context**：`reset` 唯一需要提交的账本文件是 `review-loop.yml`（`auditLog` 走 `.crctl/` 审计域，不进 git 事务）；既有 4 个 ledger 事务调用点全部 ≥2 文件，无单文件先例；该前置条件当前**无测试守卫**（dep-8 事实条目）。
- **Alternatives**：
  - (a) 原位放宽共享前置条件（采用）；
  - (b) write-set 中塞入一个内容不变的第二个文件：会让"commit 只包含 `review-loop.yml`"（FR-9 第 4 条）与 FR-11 的零无关改动口径变成假象；
  - (c) 绕开 `beginLedgerCommand` 自建写入路径：被 FR-9 第 7 条禁止，且单文件直写不提供崩溃可恢复与 index 回滚，无法满足 AC-9②。
- **Consequences**：单条目与多条目的 prepare/apply/rollback 路径同构（逐条 CAS、逐条 before 快照），故 4 个既有调用点零行为差异；空 write-set 仍被双重拒绝；代价是共享原语的边界值语义被放宽，风险由 AC-9⑥ 的可验断言 + 既有 4 调用点事务测试全绿兜住。

## 5.2 D-2：`reset` 提交失败使用 op-scoped 错误码

- **Decision**：新增 `REVIEW_LOOP_RESET_COMMIT_FAILED` / `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED` 两个错误码，不改变 `BAD_ARGS`/`NOT_TTY`/`LOOP_NOT_EXHAUSTED` 三条既有码。
- **Context**：`reset` 改造后首次出现"提交失败但事务已回滚"这一可观测结果；调用方（人类在 TTY）需要区分"参数/状态不对"与"提交失败但不留中间态"。
- **Alternatives**：(a) 新增 op-scoped 码（采用，与 `OWNER_COMMIT_FAILED`/`VERSION_SET_COMMIT_FAILED` 同族，dep-5）；(b) 复用 `TX_GIT_FAILED`：该码语义是"回滚后 index 恢复失败"（dep-3），用它表达"提交失败已回滚"会丢失关键区分度；复用裸 `BAD_ARGS` 则完全丢失"已回滚"这一事实。
- **Consequences**：两个码各有唯一产生点（§4.2.1 步骤 12/13）：`..._COMMIT_FAILED` = 隔离断言不成立或 commit 命令失败；`..._ROLLBACK_FAILED` = 恢复到干净基线的恢复链未完成（含执行前已有 staged 变更时 clean 复核不过的情形）。CR-R 迁移结构化 `recovery` 时，这两个码与 `recoverCommand` 一并在同 CR 内替换（PRD §7 的 CR-R 边界）；错误码是新增的对外可观测面，属"错误闭包"的必要组成（PRD §1.3.3 已把 FR-9 列入四查面）。

## 5.3 D-3：`recoverCommand` 内插规范形态 CR-ID

- **Decision**：恢复串为 `crctl workspace inspect <CR-ID>` / `crctl review-loop reset <CR-ID> --loop <ref> --reason <reason>`；CR-ID 仅在匹配 `^CR-\d{4}-\d{3,}$` 时内插，否则回退占位符 `<CR-ID>`；`reason` 一律用占位符（§4.1.1）。
- **Context**：PRD FR-7 第 3 条要求 `<cr_id>` 取自被调用的 CR（可执行方向），而 FR-7/AC-7 与 NFR-3 同时要求"不含任何用户输入"（防止把用户文本拼进可被复制的命令）；两者在"CR-ID 是否是用户输入"上存在读法差异。
- **Alternatives**：(a) 语法判定后内插（采用）；(b) 一律输出纯字面模板 `crctl workspace inspect <CR-ID>`：绝对满足"固定字符串"，但丢失"取自被调用的 CR"、方向不可直接复制；(c) 无条件内插：把任意 argv 文本引入恢复串，直接违反 NFR-3 的立意。
- **Consequences**：正常 CR-ID（工作区唯一真实形态）得到可执行方向；畸形 argv 退化为占位符，恢复串在任何输入下都不含自由文本；代价是多一层 3 行语法判定（与既有 `archive` 的 `/^CR-\d{4}-\d{3,}$/` 校验形态一致）。

## 5.4 未记录为决策的事项（不满足三判据）

| 事项 | 不记录理由 |
|---|---|
| `contractDrift` 恒为 `true` | 不可逆性低、无真实替代方案（本 CR 只一种错配形态），按 §3.1.1 作为设计说明，不立决策 |
| R7 配对判据的行级判定粒度 | 与既有 R7 四类子判据同族，属同构选择，无实质权衡 |
| `_context.md` 退役的落地方式 | 已由来源文档 §1.2 与 PRD 拍板（删除为主，不迁移、不新增生成器），非本 SDD 待决项 |

# 6. FR 到技术实现映射

标注列含义：**落点** = 承载改动的仓/文件/位置；**原位落法** = 说明该改动是替换/删除/补写，而非追加第二套；**AC** = 覆盖该 FR 的验收标准。

## FR-1 `_context.md` 活跃合同退役

| # | 落点 | 原位落法 | 目标内容 | AC |
|---|---|---|---|---|
| ① | `multica` `cr-prompts-revised/dev-agent.md`（`## 环境与代码边界` 末段，基线 L45–49） | **整段替换**（不得"保留旧段 + 段后追加说明"） | 目标段落原文（保留反引号格式）：「不得手工修改受控账本、`review-annotations`、`review-loop`、`traceability` 或 `specs/`；对应写入必须经专用 Skill/crctl。恢复或返工时直接读取 `crctl status {cr_id}`、`crctl next {cr_id}`、`cr.md`、`review-loop.yml` 与 canonical review annotations；不得创建或读取 `_context.md` 等上下文副本，也不得让缓存替代状态、评审证据或门禁。」 | AC-1① |
| ② | `multica` `cr-prompts-revised/quality-reviewer-agent.md`（`## 入口识别与证据` 首段，基线 L19） | 段内**删除** `_context.md` 引用并改写为 canonical 口径 | 首句保留"不凭评论文字猜阶段"；证据面改为 `dir-graph.yaml` + `crctl status/next` 返回 + 当前 CR canonical 产物 + 该 Skill 指定证据，并保留"canonical 事实优先于缓存、评论和执行方自报"（两处落点基线 dep-22） | AC-1② |
| ③ | `tools` `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（post-review `allowed` 集合，基线 L1317–1318） | 删除**条目 + 其上方注释**；不新增 `crProcessCachePath()`、不放宽 `classifyRepoWorkspace()` | 删除后判定见 §4.4（dep-10） | AC-1③ |
| ④ | `tools` `skills/shared/crctl/scripts/test/crctl.test.mjs`（CR-2026-057 白名单测试，基线 L4554 起） | 同一测试**原位改为退役合同测试**（禁止"保留原测试 + 旁边新增反向测试"） | 断言改为：① 评审后新增/修改 `_context.md` → `RELEASE_SUBJECT_DRIFT` / `reason=post-review-path-drift` 且 `approval.yml` 零写入；② `_context2.md` 非白名单断言保留（证明不存在前缀式放宽）（测试基线 dep-12） | AC-1④ |

## FR-2 活跃引用全量核对

- 落点：**无代码改动**；交付物是"检索命令 + 命中清单"证据（§4.5）。
- 原位落法：不适用（核对项）。历史 CR 目录、历史 `traceability.yml`、归档 delivery 证据不改。
- AC：AC-2。

## FR-3 Prompt 事实源归位（`CUSTOM.md` #75）

- 落点：`multica` `CUSTOM.md` 第 387 行所在第 75 行，**第 3 列（`改动`，即该行职责单元格）**。
- 原位落法：**同一单元格内重写**，不新增登记行、不改表结构、不动其它行；第 5 列（`合并注意`）现有的"与 tools 仓实际生效 prompt 分叉时以 tools 仓为准并人工对齐"与新口径一致，无需改动；第 4 列（`原因 / 追溯`）记录的是该目录内容的来源提交（历史 provenance），不构成"公共副本是独立事实源"的声明，故不改动（最小 diff 面，满足 AC-3 的"其它行文字零 diff"）。
- 目标内容（五要素齐备）：公共 Agent Prompt 唯一事实源为 `tools/agents/`；`cr-prompts-revised/cr-coordinator-agent.md` 是 Multica 专属 overlay；目录内公共 Prompt 副本**不再独立演进**（原"仓库侧快照"定性由本单元格取代），owner 部署时以 tools 同名文件覆盖平台公共 Agent；DB 是部署投影、不是事实源（禁止把 DB/UI 临时编辑反向当规范）；`cr-coordinator-agent` 不进入 tools agent index。
- AC：AC-3。

## FR-4 矩阵与索引不改动（反向验收对象）

- 零改动清单：`tools/agents/_index.yml`（仍 9 个 agent）、`tools/agent-skill-matrix.yml`（保留 `cr-coordinator-agent` system actor 声明）、`multica/cr-prompts-revised/agent-skill-matrix.yml`。
- 原位落法：不适用（`zero_diff` 项，见 §9）。
- AC：AC-4。

## FR-5 Multica coordinator overlay 三处原位替换

- 落点：`multica` `cr-prompts-revised/cr-coordinator-agent.md` 的 `## 委派与评论`（基线 L38）、`## 评审闭环`（L45）、`## 失败与输出`（L63）；章节结构基线 dep-23。
- 目标文本的权威锚点 = **本 SDD §6.2**（三块逐字文本 + 替换边界 + 逐块 `sha256` + 来源文件 SHA256）；不再依赖 CR worktree 之外的来源副本，实现者与评审者均可在仓内逐字核对。
- 原位落法：**三处按 §6.2 逐字复制**（§3.3.1 整节含标题行替换；§3.3.2 仅替换标准评审入口段、保留既有 BLOCK/Suggestions/alignment 边界；§3.3.3 在既有失败 bullet 内插入给定段）；保留 `职责`、`事实源与读取`、`路由`、`平台层权限` 四节与 frontmatter；不整文件重写、不追加第五节。
  - §3.3.1：标准 Pipeline 节点只经既有 Runner 启动；计划外人工委派只传事实清单（CR-ID、节点/Skill 名、`crctl status/next` 返回、workspace/resources 原样值、canonical feedback 引用、当前责任 Agent）；不复述 Skill/Pipeline 步骤，不内联状态推进或 Git 命令，不把 blocker 正文改写成执行步骤，不声明未来节点已满足；`mention://agent/<id>` 是工作委派不是抄送；一条评论只 mention 一个当前目标；每次触发记录一次 squad activity。
  - §3.3.2：标准评审由 Runner 启动新的 reviewer task/run，协调者不得用评论重建 review Skill 步骤；BLOCK 按 `review-record` 返回的 `repair-target` 与 Pipeline `reviewLoop` 处理；介入条件限定为 repair target 无效、最大轮次耗尽、权限/事实冲突、技术失败或人工 gate。
  - §3.3.3：在 `## 失败与输出` 的**第 1 条**既有失败 bullet 后，按 §6.2 的两行替换块插入该段（内容 = 评论/Prompt 与当前 Skill/Pipeline 事实冲突时停止该次手工委派并报告 `CONTRACT_DRIFT` 与冲突两侧；来自 crctl 的恢复信息只逐字段转发、不改写成协调者自己的 Git/状态序列）；第 2 行行首恰两个半角空格，旧 bullet 行逐字保留、不加其它列表标记。
- 交付性质声明：这是 **Prompt 合同缓解**，不宣称平台新增运行时校验；owner 复制该文件到平台后才生效（部署不在本 CR 范围）。
- AC：AC-5。

## FR-6 公共 dev-agent 委派合同收紧

- 落点：`tools` `agents/dev-agent.md` `## 委派路由合同（评审）`（基线 L31；dep-20）。
- 原位落法：节内文本原位收紧，**保留**"作者不得在同一运行中自评""创建路径必须携带可信来源上下文（来源 Issue 或父 task）""不接受时停在 review 节点提示另开独立会话（不得退化为作者自评）"三条既有内容，**新增/明确**六条要求：
  1. 每轮评审使用**新的** reviewer task/run；
  2. 标准节点走 Pipeline Runner；
  3. 只传 review Skill 已声明的结构化输入与 canonical 引用（CR-ID、权威 workspace、resources 原样值）；
  4. 不在委派评论中复述 Skill 步骤、门禁命令、`advance` 参数或 blocker 修法；
  5. 只读命令出现零写入 `BAD_ARGS` 时，可按 crctl 明示的恢复方向恢复一次；
  6. 错误命令来自**版本化 Skill/Pipeline** 时，当前 run 可按安全恢复完成，但**必须同时报告 `CONTRACT_DRIFT`**，不得以成功掩盖合同错误。
- 约束：**不新增** R14 或等价委派 lint（来源 §1.3/§3.4：无法检查真实运行期评论）。
- 文本纪律（本文件被 `lint-prompts` 的 R12/R13 判定覆盖，dep-15）：新段落不得出现 ≥3 个具名状态，也不得把 `_backlog.yml` 与状态判断写进同一段；不出现 guard-deny 文件路径 + 写动词的组合。
- AC：AC-6。

## FR-7 `gate --mode pre-review` 错配可操作化

- 落点：`tools` `skills/shared/crctl/scripts/crctl.mjs` `cmdGate()` 的 `--mode pre-review` 分支（基线 L957–960）+ 一个文件内 helper（§4.1.1）。
- 原位落法：**在原 `fail(...)` 调用上补 extra 字段**（不新增分支层级、不改 `--for requirement-reviewing` 的正常序列、不改 `fail()` 本身的输出协议）。
- 契约细节见 §3.1、算法见 §4.1；`contractDrift` 定位见 §3.1.1。
- AC：AC-7。

## FR-8 版本化 Prompt 的配对 lint

- 落点：`tools` `skills/shared/crctl/scripts/lint-prompts.mjs` R7 规则内（基线 L249–284）。
- 原位落法：在既有逐行循环内**新增一个子判据**（§4.3），不改既有四类子判据的判据与命中文本，不新增规则编号，不改 lint 的退出语义与豁免机制。
- AC：AC-8。

## FR-9 `review-loop reset` 原子提交

- 落点：`tools` `skills/shared/crctl/scripts/crctl.mjs` `cmdReviewLoopReset`（基线 L1821–1848）→ 改为 `async`；`tools` `skills/shared/crctl/scripts/lib/durable-tx.mjs` 前置条件一处数值（基线 L487）。既有符号与调用点见 dep-2 / dep-8 / dep-3 / dep-6。
- 原位落法：同一函数内**替换写入与返回段**（读参、TTY 检查、耗尽检查、审计字段与输出字段集不变）；`durable-tx.mjs` 只改一处比较数值。
- dispatcher（`case 'review-loop'`，dep-6）与调用形态**不改**：`return cmdReviewLoopReset(...)` 在 `async main()` 内已返回 Promise，`main().catch(...)` 已有统一兜底。
- 时序、崩溃窗口、错误码与契约见 §4.2 / §3.2；write-set 前置条件见 §3.3。
- AC：AC-9。

## FR-10 `review-record` payload 的 YAML 子集边界

- 落点（文档侧，5 处原位补写；dep-18、dep-19）：
  1. `tools` `skills/shared/crctl/SKILL.md` 的 `review-record` 行（基线 L34）：写明 `blockers`/`suggestions` 等值必须使用 YAML 子集支持的**单行标量**，不得使用多行引号标量或折叠块；依据是既有 `lib/yaml-subset.mjs` 的解析边界（块标量 `|`/`>` 仅保守拼接为文本；锚点/别名/tag/多文档不支持，dep-19）。
  2. `tools` `skills/requirement/review-requirement/SKILL.md`
  3. `tools` `skills/develop/review-tech-design/SKILL.md`
  4. `tools` `skills/develop/review-dev-plan/SKILL.md`
  5. `tools` `skills/develop/review-code/SKILL.md`
- 原位落法：在**既有 payload 示例处补同一约束注释**，不新增字段、不新增评审维度、不改示例结构（字段名与层级）。
- 约束：`lib/yaml-subset.mjs` 行为与实现**零改动**（不换解析器、不放宽边界）。
- AC：AC-10。

## FR-11 零新增与不修改边界

- 落点：无（交付 diff 的自洽性约束）。
- 原位落法：不适用；由 `zero_diff`（§9）与 AC-11 的 diff 核对承担。
- AC：AC-11。

## 6.1 AC 逐项设计与验收映射

| AC | 覆盖 FR | 设计落点（负责产生结果的模块/流程/字段） | 可观测结果 | 可达性说明 |
|---|---|---|---|---|
| AC-1 | FR-1 | ①multica `dev-agent.md` 段替换；②multica `quality-reviewer-agent.md` 段改写；③`workspace-transactions.mjs` `allowed` 集合删除；④`crctl.test.mjs` 退役测试 | ①两份副本文件内 `_context.md` 命中 0 且含 canonical resume 口径；②同左；③`allowed` 集合不含该条目（`crProcessCachePath` 不存在、`classifyRepoWorkspace` 零 diff）；④测试断言 `post-review-path-drift` + `_context2.md` 拒绝，且无"旧放行 + 新拒绝"并存 | 四处改动互相独立；③的删除由 `git diff` 直接可读；④的语义由既有 `runCodeReviewAndAdvance` + `makeCodeGrant` 夹具承载（dep-12），删除白名单条目后拒绝路径必然触发（判定算法 §4.4 未改） |
| AC-2 | FR-2、FR-1 | §4.5 的检索流程（计入/排除集合 + 命令 + 命中清单） | 计入集合命中数 0；排除集合命中全部为拒绝语义；交付证据含检索命令与清单 | 计入集合的非零命中只可能来自三处改动的遗漏；三处改动都在本 CR 的 scope_in 内，无需外部依赖 |
| AC-3 | FR-3 | `CUSTOM.md` #75 第 3 列单元格 | 单元格含五要素；其它行文字零 diff，行数不变 | 单元格文本由实现期一次写入；核对用 `git diff -U0 CUSTOM.md` 只应命中该行 |
| AC-4 | FR-4 | 三个零改动文件 | `git diff` 对三者零改动；`_index.yml` 仍 9 个 agent；矩阵 `cr-coordinator-agent`（`kind: system`/`mode: leader`）声明保留 | 本 CR 不产生任何写这些文件的步骤（§9 `zero_diff`），故天然可达 |
| AC-5 | FR-5 | coordinator overlay 三节正文 | 三节逐条对应来源 §3.3.1/3.3.2/3.3.3；四节 + frontmatter 原样（派生核对：整文件 `sha256` = `872457e6…`）；文件内无 Skill/Pipeline 步骤复述；**块 3 以 §6.2 的两行替换块形式出现**（`fc247a12…`；旧块 `de2554c9…` 不单独出现，第 2 行 = 两空格 + 插入段 `ed1941…`） | 三节为独立 Markdown 节，替换互不影响；"无步骤复述"以"新文本不含 `crctl advance`/`git` 等可复制推进命令"为判据（`## 平台层权限` 的**禁止清单**按 FR-5 要求保留原文，不属于可复制执行的推进命令） |
| AC-6 | FR-6 | `tools/agents/dev-agent.md` 委派合同节 | 六条要求齐备；`lint-prompts.mjs` 不存在 R14 或等价委派 lint | 六条为同节文本；R14 不存在由 FR-8 只改 R7 且 dep-15 的规则清单不变保证 |
| AC-7 | FR-7 | `cmdGate` pre-review 错配分支 + §4.1.1 取值算法 | 退出码非 0；`error.code === 'BAD_ARGS'`；`error.contractDrift === true`；`error.recoverCommand` 为固定形态串且不含用户输入，两个向量均必须成立：①**规范 CR-ID 向量**（真实 CR，如 `CR-2026-063`）⇒ 内插该 CR（`crctl workspace inspect CR-2026-063`）；②**非规范位置参数向量**（如 `CR-X`）⇒ 回退占位符 `<CR-ID>`（不内插）；执行前后 worktree 文件哈希集合零变化；`--for requirement-reviewing` 路径行为与既有测试不变 | 分支在 `runGateChecks` 之前 `fail()`，结构上零写入；恢复串只由 `cr` 经语法判定（§4.1.1）派生，自由文本无入口 |
| AC-8 | FR-8 | §4.3 的 R7 子判据 + `test/lint-prompts.test.mjs` 向量（dep-16） | 向量 A（含 `gate … --mode pre-review` 缺 `--for requirement-reviewing`）产生 R7 finding；向量 B（两者同现）不产生；既有三类 R7 向量结果不变；无新增规则编号 | 向量由独立临时 fixture 驱动（`makeFixture`），不依赖真实 tools 内容；基线零误报由 dep-21 保证 |
| AC-9 | FR-9 | §4.2 时序 + §3.2 契约 + `test/crctl.test.mjs` 新用例 | ①成功路径：变更已提交（提交只含该文件、消息含 `[cr] ` 与 tx trailer）、`git status --porcelain` 为空；②W2 窗口：失败返回 + 文件/index 回到执行前 + 审计已写；W2b 窗口（执行前已有 staged 变更）：不 commit、不夹带，按 §4.2.2 得到 `..._ROLLBACK_FAILED`；**W2c 窗口（恢复链自身失败：`pre-commit` hook 写第三值后 `exit 1`）**：`abortLedgerTransaction` 抛 `TX_RECOVERY_CONFLICT`（TxError）⇒ 本地 catch 映射 `..._ROLLBACK_FAILED`（`affected:[rel]`）+ 审计，**不得**以 `TX_RECOVERY_CONFLICT` 退出；W1 窗口：下次同命令按 journal 还原后干净执行一次；③恢复串断言**只以失败结果为对象**：`REVIEW_LOOP_RESET_COMMIT_FAILED` 的 `error.recoverCommand` 不含 `reason` 用户文本，且两个向量分开断言（规范 CR-ID 内插 / 非规范输入回退 `<CR-ID>`）；**成功结果不含 `recoverCommand`，不作恢复串断言**（§3.2 出现面行）；④三条既有拒绝行为不变；⑤cycle+1、attempt=0、attempts 保留；⑥`writes.length===1` 被接受、空集仍 `TX_WRITESET_INVALID`、4 个既有调用点事务测试全绿 | ①②③⑤需要 git 仓夹具（既有 `makeGitWorkspace`/hook 先例，dep-13/dep-14）；⑤的既有用例 `crctl.test.mjs:3430` 现用非 git 的 `makeWorkspace()`，**必须**迁到 `makeGitWorkspace()` 且断言逐字不变（dep-14）；⑥只需 `durable-tx.test.mjs` + 既有事务测试；W1/W3 由既有 fault point 驱动（dep-9），W2b 由同一 git 夹具的预置 staged 变更驱动，W2c 由同一 git 夹具的 `pre-commit` hook（写第三值 + `exit 1`）驱动，均无新增注册项 |
| AC-10 | FR-10 | 5 处文档补写 | 5 处均出现"单行标量"边界说明（含"不得使用多行引号标量或折叠块"）；`lib/yaml-subset.mjs` 零 diff；示例结构未变 | 5 处为独立文档位置；lint R1~R13 不因这些补充文本产生新 finding（补充文本为约束说明，不含 guard-deny 路径 + 写动词组合，不含状态机副本） |
| AC-11 | FR-11 | 交付 diff 与 §9 `zero_diff` | diff 中无新增 SLO/M1–M8/P50–P90/计数门禁/账本字段/评审维度/Pipeline 节点；无 `crProcessCachePath`；`rules.json` 零 diff；`multica/aifirst/agent-import.mjs` 零 diff；multica 侧除 4 个文件外无其它改动 | `zero_diff` 项不进入任何 TASK 写入面，核对方式为 `git diff --name-only` 白名单比对 |
| AC-12 | 全部 | 全部既有测试文件（§6.3 的基线红例外登记，依赖事实见 dep-29）+ 本 CR 新增/修订用例 | ①`tools/skills/shared/crctl/scripts/test/` 下**全部** `*.test.mjs`（本轮枚举为 21 个，逐文件清单与计数见 §6.3）在改动后被真实执行，失败集合**恰等于** §6.3 登记的 5 条基线红（不多不少；**不得新增任何红**，也不得靠 skip/删测试制造假绿）——该口径相对 PRD AC-12/NFR-1 原文的差异属**已由 owner 显式授权的目标放宽**（选项 A，授权记录见 **§6.4**）；②全部文件按 §4.6 的**无重不漏分区**纳入 canonical cmd-NN（每条带 `sourceRevision` 与 `test-evidence/cmd-NN.log` 绑定），例外仅以锚定完整测试名的模式排除，`skipped=true` 不接受为通过；③multica 被改文件结构完好（Markdown 表格/frontmatter 完整） | 新用例与既有用例共享同一 runner；`durable-tx.mjs` 的放宽对 4 个既有调用点零行为差异（§3.3）；§6.3 的 5 条红在未改动基线上已逐条复现，与本 CR 改动面无关（全部落在 `zero_diff` 对象上）；①的**可观测性**（同样可机械核对）与「验收通过」的成立条件均由 §6.4 授权记录的唯一口径确定，本 CR 不再有第二种通过定义 |

**AC 反查结论**：逐条从 AC 回查正文——每条 AC 的设计落点均在 §1–§5 有对应设计（AC-1/2→§4.5、AC-3/5/6/10→§6 各行、AC-7→§3.1+§4.1、AC-8→§4.3、AC-9→§3.2+§4.2、AC-11→§9、AC-12→§4.6+§6.3）；无"设计落点缺失"、无"与 PRD 契约冲突"、无"结果不可观察"；关键前置（TTY 门槛、耗尽门槛、healthy workspace、CR-ID 语法判定）均不会过滤掉 AC 目标对象——其中 TTY 与耗尽门槛是 AC-9④ 的**被验对象**而非阻碍，CR-ID 语法判定的非常规分支正是 AC-7 的第二个向量。

## 6.2 coordinator overlay 三节逐字目标文本（权威锚点，AC-5）

**来源身份（可复核）**：需求来源文档《AIFI-18_SDD到planTASK_原位修订方案.md》——Issue AIFI-24 附件（`cr.md source`）与主 checkout 副本 `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md` 在 CRLF→LF 归一后一致（PRD §1.4 事实 1）；本轮直接从主 checkout 副本（24585 B、CRLF=0、SHA256 `b774e41da19e207b163d6e4cfff818bf949cb1b830223832c76f443f21bd3777`）按块锚点（§3.3.1/§3.3.2/§3.3.3 的 ` ```text ` 代码块）提取下列三块并计算摘要。**本 SDD 即三节目标文本在 CR worktree 内的权威锚点**；实现期不再回读来源副本。

**块文本口径**：块内文本按 LF 归一（`\r\n → \n`）、**去掉块末换行**后的 UTF-8 字节串；下表 `sha256` 即按该字节串计算。核对方式：从 `multica/cr-prompts-revised/cr-coordinator-agent.md` 按下列替换边界提取对应文本 → LF 归一 → 去尾换行 → `sha256` 必须等于表内值。

| 块 | 来源节 | 目标文本在该节内的形式 | 行数 / 字节（去尾换行） | `sha256`（LF 归一、去尾换行） |
|---|---|---|---|---|
| 块 1 | §3.3.1 | 替换 `## 委派与评论` **整节**（含该标题行，至下一 `## ` 之前） | 7 / 975 | `833517ffb7a70b238d338be51e4579736bc961cb4035c4c9513287a419a31525` |
| 块 2 | §3.3.2 | 替换 `## 评审闭环` 内的**标准评审入口段**（保留该节标题与其它段） | 1 / 373 | `dcd3b8e45b8cadd858f4f59789e31535e0b19835a064b27e039513521a5c8da8` |
| 块 3 | §3.3.3 | **插入段正文**（不含任何缩进；作为 `## 失败与输出` 第 1 条既有失败 bullet 的紧跟下一行插入） | 1 / 278 | `ed1941707f03c8691325737471c1c08698269eea9d96e52bb664f8d5f3550115` |

**三块的旧块 / 替换块边界（唯一定义，落在目标文件内；均按 LF 归一去尾换行计数）：**

| 块 | 旧块（替换前，逐字定位） | 旧块 行数 / 字节 / `sha256` | 替换块（替换后，完整目标块） | 替换块 行数 / 字节 / `sha256` |
|---|---|---|---|---|
| 块 1 | `## 委派与评论` 标题行起、至该节**最后一个非空内容行**止（含标题行；节与下一节之间的空行不计入） | 6 / 574 / `fd0e9ce6c039b512362c3033902236a6c1010e91c13b9e23b53e59c320453daa` | 块 1 全文（上表，7 行） | 7 / 975 / `833517ffb7a70b238d338be51e4579736bc961cb4035c4c9513287a419a31525` |
| 块 2 | `## 评审闭环` 内首个非空段（整行、单行；该节其它 3 段保持原样） | 1 / 300 / `06b084c200e3c982475d63461d069ae5e012452bc8c49585d0826f02d5083148` | 块 2 全文（上表，1 行） | 1 / 373 / `dcd3b8e45b8cadd858f4f59789e31535e0b19835a064b27e039513521a5c8da8` |
| 块 3 | `## 失败与输出` 的**第 1 条**既有失败 bullet（以 `- 任何权限缺失、事实冲突或不可恢复技术错误：` 开头，至该行末），整行、单行 | 1 / 141 / `de2554c90a9218dcd6d64e9ae1fe8948203584b9e34cf5f06122c8650c8537a8` | **两行**：第 1 行 = 旧块逐字保留；第 2 行 = 两个半角空格 + 块 3 插入段正文（即 `"  "` + 278 B 块文本，自身 280 B） | 2 / 422 / `fc247a12436ea84e0bd6403b36c7151d149717fc30b5537f12cca91798a32f38` |

- **块 3 的机械提取规则（唯一旧块起止）**：在 `## 失败与输出` 节内，该 bullet 行必须**恰**由上述替换块的两行组成——第 1 行逐字等于旧块（`de2554c9…`）；第 2 行逐字等于「`"  "` + 块 3 正文」（`0fdd50aca448ac9debd1bfaea9ccd26c5f88de9c3d6e5054e659b0d3543f850c`，280 B）。该 bullet 行下**不得**出现不含那个两空格缩进行的裸 bullet 形态（否则“原样插入、未入 bullet 内”判不通过），也**不得**把插入段写成其他列表标记（会改变替换块 `sha256`，同样判不通过）；插入位置固定为 bullet 行之后、该节第 2 条 bullet（`- 不重试跨节点…`）之前。
- **插入段正文仍逐字可校验**：第 2 行去掉行首两个半角空格后 = 上表块 3（`ed1941…`）；“逐字复制、不得转述”的校验对象因此是两个：完整替换块（`fc247a12…`）与插入段正文（`ed1941…`）。
- **整文件派生核对项**：三处按上表替换完成后，`cr-coordinator-agent.md` 的 LF 归一去尾换行 `sha256` = `872457e62ddfbadd40637dc7a293660fa8669c2e220afafa31454c53d271281c`（6019 B / 69 行；构造口径 = 块 1/块 2/块 3 按上表替换，节间空行与其余四节 + frontmatter 保持原样）。该哈希只作派生核对，不是独立判据；若它不等而三块各自相等，优先复核未替换区域的空白/换行差异。

**块 1（替换 `## 委派与评论` 整节）**

```text
## 委派与评论

标准 Pipeline 节点只通过平台已有 Runner 启动目标 Agent；Runner 提供的固定 PipelinePrompt、canonical feedback、attempt、source task 与 executor 是该次委派的权威输入，本 Agent 不在评论中复制它们的执行算法。

计划外人工委派只传以下事实：CR-ID、当前 Pipeline 节点或 Skill 名、`crctl status/next` 的当前返回、权威 workspace/resources 原样值、canonical feedback 路径或对象引用、当前责任 Agent。不得复述 Skill/Pipeline 步骤，不得内联状态推进或 Git 命令，不得把 blocker 正文改写成新的执行步骤，不得声明未来节点已经满足。

`mention://agent/<id>` 是立即创建/唤醒目标 task/run 的工作委派，不是抄送。串行交接的一条评论只 mention 一个当前目标；下一节点或复评者只作纯文本说明，不提前触发。每次触发后记录一次 squad activity，避免重复委派和轮询。
```

**块 2（替换 `## 评审闭环` 的标准评审入口段）**

```text
标准 Pipeline 评审由 Pipeline Runner 按 registry 节点启动新的 quality-reviewer-agent task/run；协调者不得用评论重建 review Skill 的步骤。评审 BLOCK 按 review-record 返回的 repair-target 与 Pipeline reviewLoop 处理；协调者只在 repair target 无效、最大轮次耗尽、权限/事实冲突、技术失败或人工 gate 时介入。
```

**块 3（在 `## 失败与输出` 的既有失败 bullet 内插入）**

```text
当评论、Agent Prompt 与当前 Skill/Pipeline 事实发生冲突时，停止该次手工委派，报告 `CONTRACT_DRIFT` 与冲突两侧，不自行选择一套步骤继续。来自 crctl 的恢复信息只逐字段转发，不改写为协调者自己的 Git/状态序列。
```

**实现与验收纪律**：三块**逐字复制，不得转述**；除替换边界外不得改动标点、空格、换行或代码标记（包括反引号）。AC-5 的"与来源 §3.3.1/3.3.2/3.3.3 逐条对应"因此升级为三个可机械核对的判据：①三块按上表边界出现在目标文件内（逐块 `sha256` 相等）；②**块 3 必须以上表的**两行替换块**形式出现（旧块 `de2554c9…` 不单独出现，第 2 行 = 两空格 + `ed1941…`）；③四节与 frontmatter 原样（派生核对：整文件 `sha256` = `872457e6…`）、全文不出现可复制的推进命令。

## 6.3 既有测试基线红例外登记（AC-12 的绑定对象）

**登记依据（本轮在 tools CR worktree `ebdd6290…` 未改动工作区复测；逐条事实作为既有实现依赖 **dep-29** 入§10）**：`node --test --test-reporter=dot <test/ 下全部 *.test.mjs，共 21 个>` → **exit=1、耗时 857 s、失败标记恰好 5 个**（dot 串：`.` × 548 pass、`X` × 5 fail），失败测试名逐字如下表。5 条全部在**本 CR 改动前即红**，且均落在本 CR 的 `zero_diff` 对象或 `scope_out` 面（无一是本 CR 改动面）。

| # | 文件:行（测试定义 / 失败断言） | 测试名（逐字；锚定例外的唯一匹配对象） | 失败事实（本轮实测） | 归属 |
|---|---|---|---|---|
| BR-1 | `crctl.test.mjs:1335` / `:1343` | `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引` | `AssertionError: The input did not match the regular expression /crctl task init/`（`code-implementation.pipeline.json` 无该串） | `pipeline-templates/**` 在 `zero_diff` 内；根因修复归 CR-2026-060 §5.3 follow_up |
| BR-2 | `checkpoint-tx.test.mjs:480` / `:489` | `checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints[]` | `AssertionError: The expression evaluated to a falsy value`（`alignment` 不含 `latest-checkpoint`） | `checkpoint` 与 `pipeline-templates/**` 均不在 `scope_in` |
| BR-3 | `crctl.test.mjs:4585` / `:4597` | `TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）` | `AssertionError: CR-2026-031 TASK-06 后声明转移 = 28` / `31 !== 28`（`dir-graph.yaml` 现 31 条声明） | `dir-graph.yaml` 在 `zero_diff` 内（本 CR 不改状态机） |
| BR-4 | `crctl.test.mjs:4797` / `:4803` | `CR-2026-042 静态合同：已知 Skill 越界文本零命中` | `AssertionError: write-requirement-prd 保留等价文档校验`（该 SKILL 措辞与期望正则不符） | 本 CR 不改 `write-requirement-prd/SKILL.md`（FR-10 只改 `crctl/SKILL.md` + 4 份 review SKILL） |
| BR-5 | `archive-tx.test.mjs:373` / `:391` | `TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖` | `actual: [{ code: 'EMIT_FAILED', event_kind: 'archive' }]` vs `expected: []` | `archive` 不在 `scope_in`；根因修复归 CR-2026-060 §5.3 follow_up |

**全量文件清单（21 个，= AC-12 的分区全集；按文件名升序枚举）**：

```text
archive-tx.test.mjs            check-agents-contract.test.mjs  checkpoint-tx.test.mjs
check-skill-matrix.test.mjs    contract-scan.test.mjs         crctl.test.mjs
durable-tx.test.mjs            fault-harness.test.mjs         lint-prompts.test.mjs
merge-tx.test.mjs              pipeline-structure.test.mjs    register-tx.test.mjs
test-cr.test.mjs               trace-outbox.test.mjs          trace-semantic.test.mjs
upgrade-check.test.mjs         version-set.test.mjs           workspace-freshness.test.mjs
workspace-resolver.test.mjs    writeback-tx.test.mjs          yaml-subset.test.mjs
```

目录内另有非测试辅助模块 `merge-fixture.mjs`（被测试 import、不含 `test()`）：plan 必须对其显式处置（§4.6.2），不得静默遗漏；与上表并集 = 目录内全部 22 个文件。

**判定规则（冻结，fail-closed）**：

- AC-12 判据 = 「上表 21 个文件全部被 canonical `cmd-NN` 真实执行；失败集合**恰等于**上表 5 条（既不多也不少）；不得新增红」（实现 PRD §6 成功指标“既有测试回归数 = 0”的可复核口径）。该口径相对 PRD NFR-1/AC-12 “全量既有测试通过”的差异属**已由 owner 显式授权的目标放宽（选项 A）**——裁决人、裁决时间、权威评论与授权范围见 **§6.4 授权记录**；本 SDD 只承接该已授权口径，不再保留第二种通过定义。
- 例外模式 = 上表 5 个**完整测试名**（正则元字符转义）的锚定交替 `^(?:名字1|…)$`；禁用未锚定片段（片段会连带静默跳过名字包含该片段的新用例）。拼写失效 → 该用例真跑 → 红 → exit 1（fail-closed），**不产生假绿**。
- 任一命令 `skipped=true` 不接受为通过（全套命令统一 `--test-reporter=dot`）。
- 单跑 857 s 是**全集**一次运行的上限依据；§4.6.2 的无重不漏分区必须让「全集 + lint + 断言类命令」总时长落在 `write-test-report` 节点 20 min 预算内。
- BR-1/BR-5 的根因修复属 CR-2026-060 §5.3 的 follow_up，本 CR 不修（不扩大 `scope_out`）；BR-2/BR-3/BR-4 各自的对象均在 `zero_diff` 或 `scope_out` 面（逐条归属见 §9 `follow_up` 第 6 条与 dep-29）。本表 5 条与 AC-12 口径的授权关系见 §6.4。

## 6.4 AC-12 口径授权记录（owner 显式授权 **选项 A**，已闭环）

**授权记录（本 CR AC-12 的唯一有效口径）**

| 项 | 值 |
|---|---|
| 裁决人 | `Ray`（需求 owner，本 CR `owners.requirement`） |
| 裁决 | **选项 A**（授权例外口径） |
| 裁决时间 | `2026-09-11T13:13:00Z`（本地 `2026-09-11T21:13:00+08:00`） |
| 权威评论 | `01a09099-97cf-7b5c-887e-4a8a369fa80e`（Issue AIFI-24 线程；由 `cr-coordinator-agent` 以正式 mention 转派并留档于 `01a0909a-9764-7778-8ee2-078f92bbbc94`） |
| 授权范围 | AC-12 = 「21 个文件全部被真实执行；**失败集合恰等于**改动前基线集合（BR-1~BR-5，逐条见 §6.3）；不得新增红，**也不得少**（skip / 删除 / 改名制造假绿即判不通过）」——即 PRD NFR-1/AC-12「`../tools` 全量既有测试通过」在本 CR 的落地口径；5 条红的根因修复留 `follow_up`（§9 第 6 条） |
| 授权边界 | 只覆盖本 CR（`CR-2026-063`）的 AC-12 验收口径；**不改 `prd.md`**（审批绑定 `9247c107…`）、不改 PRD 其它条目、不扩大 `scope_in` |
| 与人工 gate 的关系 | 下一步人工 gate `crctl approve --stage tech-design` 签的即包含本口径（PRD NFR-1/AC-12 在本 CR 由「失败集恰等于已登记 5 条基线红」落地）；授权决策项从此关闭，不再有第二种通过定义 |

**PRD 目标契约（原文，本 SDD 不改动、不代签）**：NFR-1「`../tools` 全量既有测试（crctl、ledger/durable-tx、prompt lint、pipeline structure、contract-scan 等）保持通过」；AC-12「`../tools` 全量既有测试通过」。

**基线事实（§6.3 表、dep-29，tools `ebdd6290…` 未改动工作区实测）**：全集 21 个 `*.test.mjs` 单跑 exit=1、857 s、失败标记恰好 5 个（BR-1~BR-5）。五条的根因对象分别落在本 CR §9 的 `zero_diff`（`pipeline-templates/**`、`dir-graph.yaml`、`write-requirement-prd/SKILL.md`）或 `scope_out`（`checkpoint`、`archive`）面；BR-1/BR-5 的根因修复已由 CR-2026-060 §5.3 登记为 follow_up。

**冲突成因与本次解决（记录备查）**：PRD 原文口径要求这 5 条也通过；而“让它们通过”的对象不在本 CR 的 `scope_in` 内（§9），二者不可同时成立——这必须由人裁决，不是实现细节。该冲突已由上方授权记录以**选项 A** 解决：**本 SDD 既不擅自放宽 PRD 的验收目标，也不擅自扩大批准范围**，只在授权范围内原样承接唯一口径；未采纳的选项 B 记录见下。

**被授权的口径（选项 A，= 本 SDD §6.1/§6.3 现行口径）**：AC-12 = 「21 个文件全部被真实执行；**失败集合恰等于**改动前基线集合（BR-1~BR-5，逐条见 §6.3）；不得新增红，**也不得少**（skip / 删除 / 改名制造假绿即判不通过）」。比 PRD 原文更严的部分 = 枚举全集 + 无重不漏分区 + 锚定例外 + 失败集必须与基线逐条相等；比 PRD 原文更弱的唯一部分 = 接受 5 条既有基线红（不要求它们在本 CR 内转绿）。这就是 PRD §6 成功指标「既有测试回归数 = 0」的可复核落地。

**未采纳的选项 B（不授权例外，记录备查）**：AC-12 保持 PRD 原文（全绿），并须在同一决策中给出 5 条基线红的处理归属，二者之一：①扩大 `scope_in` 到 `pipeline-templates/**`、`dir-graph.yaml`、`write-requirement-prd/SKILL.md`、`checkpoint`、`archive` 内核（等于把一个新 CR 的工作并入本 CR）；②把 AC-12 的交付责任改为“随 follow_up CR 转绿”，并在 `follow_up`（§9）中逐条登记 5 条的根因归属。本次未采纳该选项，无需再指定归属，`approve-dev-start` 的前置不因该项受阻。

**决策落点与状态机边界**：`change-request-track.state_machine` 中 `tech-designing` / `tech-design-review-pending` 的出边只有 `→ tech-design-review-pending`、`approve-tech-design:reject → tech-designing`（以及任意活动态 → `rejected`/`withdrawn`），**没有回到需求侧（`write-requirement-prd`）的转移**——唯一的 `write-tech-design:prd-blocker` 边挂在 `requirement-approved` 上，本 CR 首次 `write-tech-design` 进入时已经跨过。因此 PRD 级口径的确认点只能是：本节点的 owner 决策项，或人工 gate——本 CR 已按前者取得显式授权（见上方授权记录），并将在人工 gate 一并签核。`prd.md` 保持审批版本（`9247c107…`）不变；该授权口径的需求侧记录随回写期 `specs/` 累积文档与后续需求 CR 承载，**不在本 CR 内改 `prd.md`**。

# 7. 安全与性能考量

## 7.1 安全控制点

| 控制点 | 设计 | 依据 |
|---|---|---|
| 恢复串无自由输入 | FR-7/FR-9 的 `recoverCommand` 只由 `cr`（经语法判定）与 `loopRef`（经 `gates.json` 声明集校验）派生；`reason` 一律占位符 | NFR-3；§4.1.1；§4.2 |
| 零写入错误路径 | `gate` 错配分支在任何写路径之前 `fail()`；`reset` 的三条拒绝（`NOT_TTY`/缺参/未耗尽）在步骤 7 之前完成 | PRD FR-7/FR-9；§4.2 |
| 人类在环无旁路 | `reset` 的 `process.stdin.isTTY`/`stdout.isTTY` 检查保持原样，不新增环境变量或参数入口 | 不变量 7；PRD FR-9 第 8 条 |
| 受控 git 边界 | `reset` 只使用既有白名单形态：`add -A -- <path>`、`commit -m "[cr] …"`（带 `s` 旗标以容纳多行 trailer）、`diff --name-only`、`rev-parse HEAD`；`rules.json` **零 diff** | dep-17；AC-11 |
| 事务边界不被绕过 | 不新增第二条写入通道：仍走 `beginLedgerCommand` → `controlledGit` → `abort/finish`；`review-loop.yml` 仍由 crctl 独占 | 不变量 2、§6 Negative Space |
| 提交不夹带外来变更 | 步骤 12 在 `git commit` 前断言 index 恰等于 write-set（`unstaged` 空 + `staged == [rel]`）；不成立则不提交并走失败回滚路径 | FR-9 第 4 条；§4.2.1 步骤 12；镜像 dep-5 的 `owner-set`/`version-set` |
| 审计不丢 | 成功与失败两条路径都 `auditLog`；失败路径含 `result: commit-failed` | NFR-5；AC-9② |
| 缓存不再是事实副本 | 删除 `_context.md` 的 Prompt 合同与白名单放行；退役测试把"放行"钉成"拒绝" | PRD FR-1；US-1 |

## 7.2 性能与资源

- `reset` 的事务规模为**单文件单条目**，不存在多条目重放或大文件拷贝；`applyWriteSet` 对单条目只做一次 CAS 读 + 一次 blob 写 + 一次 rename。
- 无新增网络访问、无轮询、无后台任务；`gate` 错配路径与既有 `gate` 同量级（纯内存 + 一次 state machine 载入）。
- `lint-prompts` 新增子判据是既有循环内的一次正则与两次字符串包含，不改变文件遍历面（dep-15），不引入新的 IO。
- 验收证据命令的预算：AC-12 的全量回归按 §4.6.2 做无重不漏分区后纳入 `crctl test`，总时长（含 lint 与断言类命令）必须落在 `write-test-report` 节点 `timeoutMinutes=20` 的预算内；本 CR 不新增观测指标，节流手段是分区而非跳过用例。
- 无性能目标变更，不新增观测指标（PRD FR-11 / §7）。

# 8. Prompt 采纳影响（条件性小节）

**结论：N/A（本 CR 不触发该条件），应改为调用新能力/新命令的 skill 清单为空。**

触发判据是"diff 触及 `crctl.mjs` 的 dispatch 分支或 `rules.json#protectedPaths.deny`（crctl 命令面或 guard deny 面有新增/变更）"。逐项核验：

| 核验项 | 结论 | 证据 |
|---|---|---|
| 是否新增/变更 crctl 子命令或 dispatch 分支 | **否**：FR-9 只改 `cmdReviewLoopReset` 的函数体（同步→async），dispatcher 的 `case 'review-loop'` 行**不改**；`async main()` 与 `main().catch(...)` 已能接管 Promise | dep-6 |
| 是否变更 `protectedPaths.deny` / `rules.json` | **否**：`rules.json` 零 diff（AC-11） | dep-17 |
| 是否有 skill 需要改为调用新增/扩展子命令 | **无**：在 lint 的扫描面（`**/SKILL.md` + `*.pipeline.json` + `README.md` + `agents/*.md`，dep-15）上检索 `review-loop reset` 为 0 命中，因此没有 skill/agent 在描述既有的直写语义需要改写 | dep-15 |
| 是否有 prompt 与 FR-7/FR-8 的新判定冲突 | **无**：`gate --mode pre-review` 在扫描面内只有 1 行命中，且该行已同时声明 `--for requirement-reviewing`，FR-8 加入后不产生新 finding、也无需修改该 prompt 文本 | dep-21 |

因此本节不含采纳清单；若后续 CR 新增 crctl 子命令，再按该 CR 的 SDD 补本节。

# 9. 批准范围

## scope_in（当前 CR 必须交付）

- **FR-1 ~ FR-11** 与 **AC-1 ~ AC-12** 全部条目。
- 改动文件面：以 PRD §1.3.1 的 14 行「仓 + 文件」表为准（`tools/**` 为主：`crctl.mjs` × 2 处、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`、`lint-prompts.mjs`、`agents/dev-agent.md`、`crctl/SKILL.md`、4 份 review SKILL、上述 4 个脚本的既有测试；`multica/**` 恰 4 个文件：`cr-prompts-revised/{dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md` + `CUSTOM.md`）。
- 本 SDD 自身（`change-requests/CR-2026-063/sdd.md`）与实现期产生的新增测试用例。
- `tools` `skills/shared/crctl/scripts/test/crctl.test.mjs` 的**既有 reset 用例夹具迁移**（`makeWorkspace()` → `makeGitWorkspace()`，断言逐字不变）与新增 W2b / 恢复串向量用例 —— 属 PRD §1.3.1 第 14 行「上述 4 个脚本的既有测试」面。
- 交付证据：AC-2 的检索命令与命中清单；AC-12 的全量测试结果（按 §4.6 的分区命令，含 `sourceRevision` 与 `cmd-NN` 日志绑定）。

## scope_out（明确排除）

- 来源 §1.4/§7 与 PRD §7 的全部排除项：SLO / M1–M8 / P50-P90 / 连续 N 个 CR 统计 / 计数门禁 / 为新指标新增账本字段或 Prompt 要求；R14 委派 lint；更换或放宽 YAML 解析器；历史 CR 目录、历史 `traceability.yml`、归档 delivery 证据的批量迁移。
- 独立 CR（不得并入）：**CR-R**（`recoverCommand` → 结构化 `recovery` 原子迁移）、**CR-P1**（评审输入结构与回修闭合）、**CR-P2**（plan/TASK 返工成本与执行前提）。
- 部署面：平台 DB 的 Prompt 投影、`multica/aifirst/agent-import.mjs`、`multica agent update` 等部署动作（由 owner 在 CR 落地后执行）。
- 知识库文档：KB 的 `specs/`、`delivery/`、`docs/`（含主工作区 `docs/analysis/` 的未提交变动）。
- CR-P1 的 `dep-N` 结构化方案**不适用**于本 SDD：本 CR 尚未实施 CR-P1，因此本 SDD 仍按当前 `write-tech-design` 的"既有实现依赖与事实"固定结构逐项给出 repo/path/symbol/SHA/结论（第 10 节），不引入 `dep-N` 之外的第二套事实定义格式（正文只持引用）。

## zero_diff（明确不得改动）

| 对象 | 说明 |
|---|---|
| `tools/skills/shared/controlled-shell/rules.json` | 白名单/deny/forbiddenFlags 全部不变（AC-11） |
| `tools/skills/shared/crctl/scripts/lib/yaml-subset.mjs` | 解析行为与实现不变（AC-10） |
| `tools/skills/shared/crctl/gates.json`、`dir-graph.yaml`、`pipeline-templates/**` | 状态机、门禁、Pipeline 编排不变 |
| `tools/agents/_index.yml`、`tools/agent-skill-matrix.yml`、`multica/cr-prompts-revised/agent-skill-matrix.yml` | AC-4 反向验收 |
| `crctl gate --for requirement-reviewing --mode pre-review` 的正常检查序列与输出 | AC-7 既有行为不变 |
| `reset` 的三条既有拒绝（`NOT_TTY` / 缺 `--loop`/`--reason` 的 `BAD_ARGS` / `LOOP_NOT_EXHAUSTED`）与成功输出的**字段集** | AC-9④、NFR-1 |
| `lib/durable-tx.mjs` 除 `writes.length` 比较数值外的任何内容（导出面、journal/manifest 结构、`recover`/`abort`/`finish` 语义、FAULT_POINTS 表） | PRD §1.3.1 第 11 行"仅"边界 |
| `multica/aifirst/agent-import.mjs`、平台 DB、`multica` 侧除 4 文件外的文件 | PRD §1.3.1、AC-11 |
| `crctl.mjs` 中 `cmdReviewLoopReset` 与 `cmdGate` + `crIdForRecover` helper 之外的段落；`review-record` / `approve` / `owner-set` / `version-set` 的调用点 | 避免"顺手重构"扩大 diff |

## follow_up（发现但留给后续 CR）

1. `tools/skills/shared/crctl/SKILL.md` 的「写入」行仍写 `review-loop.yml`（仅 `attempt`），未包含 `review-loop reset`——本 CR 的 `scope_in` 只授权该文件的 `review-record` 行（§1.3.1 第 12 行），故不改；建议由后续 CR 或 CR-R 一并收口。
2. `multica/CUSTOM.md` #75 行的第 4 列（`原因 / 追溯`）保留"对照快照"这一历史 provenance 措辞；本 CR 按 AC-3"其它行零 diff"与 FR-3"不改变该表其它行"的最小 diff 原则不改，后续如需语义统一可单独修订。
3. AC-2 的"计入/排除"判定目前是人工逐条 + 命中清单证据（S-5）；机械化为检索 lint 属新规则范围，本 CR 不做。
4. CR-R：`recoverCommand`（`gate` 错配 + `reset` 失败）→ 结构化 `recovery` 的原子迁移，以及本 CR 新增的两个 `REVIEW_LOOP_RESET_COMMIT_*` 错误码的消费迁移，全部归 CR-R。
5. 历史 CR 目录内的既有 `_context.md` 不迁移、不清洗（随 CR 自然归档）。
6. **基线红 BR-2 / BR-3 / BR-4 的根因修复**：`checkpoint` 的 alignment reader 不读 `latest-checkpoint`（BR-2）；`dir-graph.yaml` 状态机声明数与既有断言口径（BR-3，测试断言 28 条声明、当前 31 条）；`write-requirement-prd/SKILL.md` Step 4 措辞（BR-4）。三者对象均在本 CR 的 `zero_diff` 或 `scope_out` 面，本 CR 不修（不扩大批准范围）；BR-1/BR-5 沿用 CR-2026-060 §5.3 的 follow_up。AC-12 的口径授权见 §6.4。
7. **AC-12 口径的需求侧记录**：owner 已显式采纳 §6.4 选项 A（接受 5 条已登记基线红，授权记录见 §6.4），该口径的需求侧记录随回写期 `specs/` 累积文档与后续需求 CR 承载；本 CR 内不改 `prd.md`（审批绑定 `9247c107…`），需求侧口径以 §6.4 授权记录为唯一依据。

# 10. 既有实现依赖与事实

本节按 write-tech-design 的固定结构列出，**顺序 = 正文首次依赖出现顺序**（§1 → §8）；正文以 `dep-N` 引用本节第 N 项。全部在本 CR 三个 worktree 的当前 HEAD 上核实（SHA 见 §1.4 表）。

> 本轮（2026-09-11 上游回修，如 §13）补入 **dep-26 / dep-27 / dep-28** 三条（正文首次引用分别在 §3.5、§4.1.1+§5.3、§4.6.1），cycle 2 回修再补入 **dep-29**（§6.3 基线红例外登记的事实依据）；为避免全表重编号，这四条追加于表尾，其编号不再对应首次出现序；其余各项仍按首次出现序编号。

1. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: cmdGate() 的 `--mode pre-review` 分支（L957–960）与 fail()（L43–47）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: 现状仅返回裸 BAD_ARGS（extra 为空）；FR-7 的原位修订点，也是"零写入"结构性保证的来源（fail 只写 stderr 后 exit 1）

2. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: cmdReviewLoopReset（L1821–1848，同步；L1844 fs.writeFileSync 直写 review-loop.yml；无 CAS/事务/commit）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-9 的改造对象；既有语义（非 TTY 拒绝、`--loop`/`--reason` 必填、未耗尽拒绝、cycle+1/attempt=0/attempts 保留、auditLog kind=review-loop-reset）必须原样保留

3. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: ledger 助手族 —— controlledGit(L412)、sha256(L58)、readFileChecked(L154)、casWrite(L672)、ledgerTxKey(L678)、syncLedgerIndex(L682)、recoverLedgerCommand(L691)、beginLedgerCommand(L705)、runTxAsync(L3190)、injectLedgerFault
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-9 复用既有一次性写入原语，不新写事务框架（FR-9 第 7 条）；syncLedgerIndex 以 git add -A -- <relpath> 使 index 与回滚后内容一致

4. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: cmdReviewRecord 的 ledger 写入先例（L2177–2195：writes[{path,expectedHash,newText}] → beginLedgerCommand → finishLedgerTransaction；expectedHash 由 readFileChecked 取原文 + sha256，L2183/L2193）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-9 第 2 条要求的 expected hash 取值口径的唯一先例；readAttempts 只返回状态投影（current/max/attempts/cycle/cycleAttempts/exhausted/data），不返回原文或哈希，不承担 CAS 取值

5. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: cmdApprove 的提交失败回滚先例（L1130–1145：beginLedgerCommand(...,true) → controlledGit add/commit → 失败 abortLedgerTransaction + syncLedgerIndex；成功 injectLedgerFault('ledger-after-commit') + finishLedgerTransaction）与错误码族 OWNER_COMMIT_FAILED/OWNER_COMMIT_ROLLBACK_FAILED(L2481–2483)、VERSION_SET_COMMIT_FAILED/VERSION_SET_COMMIT_ROLLBACK_FAILED(L2735–2737)、rollbackVersionWrite(L2725)、rollbackOwnerWrite(L2471)
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-9 第 4/5 条的"口径同 approve"与 D-2 的错误码命名族依据

6. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: dispatcher 的 `case 'review-loop'`（L3457 `return cmdReviewLoopReset(...)`）、async main()（L3440 起）、requireCr（L3531）、main().catch(...)（L3536）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: 证实 FR-9 第 1 条"函数改 async、dispatcher 保持 return"不需要改调用形态；同时证实 requireCr 只判非空、不判 CR-ID 语法（§4.1.1 的语法判定因此必要）

7. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: auditLog(L265)、identity(L255)、attemptsFilePath(L844)、readAttempts(L846)、queryTrackedChanges(L2350)
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-9 的审计字段（kind/fromCycle/toCycle/reason/by）与状态读取来源；NFR-5 依赖既有审计域（.crctl/audit.log，不进 git 事务）

8. repo: tools
   relative path: skills/shared/crctl/scripts/lib/durable-tx.mjs
   stable symbol/对象: beginLedgerTransaction 的 ledger write-set 前置条件（L487 `writes.length < 2` → TX_WRITESET_INVALID；L492 writes.map；L514 abortLedgerTransaction；L519 finishLedgerTransaction；recoverLedgerTransaction 的 trailer 判定 `AI-First-Tx: <txId>`；rollbackLedgerPayload 的逐条 beforeText 还原）；applyWriteSet 的空集独立拒绝（L311 `entries.length === 0`）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-9 第 3 条与 §3.3 的唯一放宽点；单条目与多条目路径同构（逐条 CAS 校验、逐条 before 快照、无长度假设）；**该 ≥2 规则当前无任何测试守卫**——durable-tx.test.mjs 的 9 个用例覆盖锁竞争矩阵（L59）、journal 创建/幂等加载/envelope（L93）、applyWriteSet 全 redo/幂等 skip/第三值冲突（L121）、真实 kill-restart 恢复（L159、L198）、recoverWriteSet 定向恢复（L230）、cleanupTxBlobs 幂等与 blob 校验（L254）、checkpoint payload slot（L272），其中无 write-set 规模断言；crctl.test.mjs:1432 仅断言源码文本含 beginLedgerCommand。既有 4 个 ledger 调用点的文件构成（全部 ≥2）：approve = approval.yml + cr.md（L1130–1133，dep-5）、owner-set = cr.md + _backlog.yml（L2535–2538）、version-set = cr.md + _backlog.yml + 已存在派生产物（L2820–2828）、review-record = annotation + traceability（bump 时再 + review-loop，L2177–2195）

9. repo: tools
   relative path: skills/shared/crctl/scripts/lib/durable-tx.mjs
   stable symbol/对象: FAULT_POINTS 登记表（L23–30，含 tx-apply-between-rename / tx-apply-before-complete / ledger-after-commit）与 faultPoint（L56–60）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: AC-9 的 W1/W3 窗口用既有注入点驱动；本 CR **不新增**登记项（也不改该表——PRD §1.3.1 第 11 行的"仅"边界）；单条目 write-set 下 tx-apply-between-rename 不会触发，故 W1 用 tx-apply-before-complete

10. repo: tools
   relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
   stable symbol/对象: post-review path drift 的 allowed 集合（L1311–1319，含 L1317–1318 的 _context.md 注释与条目）、unexpected 判定与 bad('code',{reason:'post-review-path-drift'})
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-1③ 的删除落点与 §4.4 的判定语义；删除后 _context.md 与其它非白名单文件同等处理

11. repo: tools
   relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
   stable symbol/对象: renderLoopText（L3791–3804，LF-only + 尾换行）；recoverCommand 出现面 —— register(L777)、syncWorkspaceToTrunk(L1074，属 crctl workspace sync)、merge(L1514/L1559)、checkpoint(L1945)、writeback(L2814/L2882)、archive(L3460)、**crctl test 的 buildTestResponse(L4186，含 `<plan>`/`<worktree>` 占位符先例)**
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-9 的写文本由既有渲染器生成；FR-7/FR-9 的 recoverCommand 命名与"占位符先例"依据（该字段并非只出现在事务返回中，也出现在 crctl test 与 workspace sync 的返回/错误体）

12. repo: tools
   relative path: skills/shared/crctl/scripts/test/crctl.test.mjs
   stable symbol/对象: CR-2026-057 白名单测试（L4554 起，名含 `_context.md` 白名单放行；L4560/L4561/L4565 为 _context.md / _context2.md 断言）+ 夹具 runCodeReviewAndAdvance / makeCodeGrant
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-1④ 的原位退役对象与 AC-1④ 的验收载体

13. repo: tools
   relative path: skills/shared/crctl/scripts/test/crctl.test.mjs
   stable symbol/对象: commit 失败注入先例 —— owner-set（L3958–3975：.githooks/pre-commit `exit 1` + core.hooksPath，断言 OWNER_COMMIT_FAILED/changed=false/rolled_back=true + 原文恢复 + tracked clean + HEAD 不变 + 无成功 audit + 无 outbox）与 approve（L4224–4243：同款 hook，断言失败后状态回滚、可安全重试）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: AC-9② 的 W2 窗口测试口径与 AC-9 其余断言的既有写法；证明"进程内 commit 失败 → 回滚 → 无 dirty 残留"可用真实 git 失败确定性构造，无需新增 fault point

14. repo: tools
   relative path: skills/shared/crctl/scripts/test/crctl.test.mjs
   stable symbol/对象: reset 既有两测试 —— `L3420–3428`（`CR-2026-049：review-loop reset 非交互式调用拒绝（人类在环，无旁路）`）与 `L3430–3452`（`CR-2026-049：review-loop reset 耗尽态开启下一 cycle，保留 attempts 历史`），两者当前均用**非 git** 夹具 `makeWorkspace()`；既有 git 夹具 `makeGitWorkspace()`（L3688）；TTY runner `runCrctlInTty`/`runCrctlWrapped`（L43–56）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: AC-9④ 的既有断言语义必须继续通过；**AC-9⑤ 的既有用例（L3430–3452）必须迁移夹具**——`makeWorkspace()`（L62–69：只建临时目录 + `dir-graph.yaml`，无 `git init`）在改造后必然让步骤 11–12 的 `git add`/`git commit` 失败（旧写法下 reset 直写不提交，所以从未暴露）；刷新 plan/TASK 时须写明：改用 `makeGitWorkspace()`（L3688 = `makeWorkspace()` + `git init -b master` + user 配置；必要时补一次基线 commit 以建立 HEAD），**断言与断言语义逐字不变**（仍断言 `status==0`、`current-cycle==2`、`current-attempt==0`、`attempts` 历史 3 条）。允许原因：该用例属 PRD §1.3.1 第 14 行的既有测试修订面，不是对 reset 契约的放宽；`runCrctlWrapped` 目前不透传 env，W1/W3 窗口用例需要给 TTY runner 增加可选 env 形参（向后兼容的测试侧改动）

15. repo: tools
   relative path: skills/shared/crctl/scripts/lint-prompts.mjs
   stable symbol/对象: R7 实现（L249–284，逐行 l.includes(...) 四类子判据）、规则清单注释（L14，R1~R13，无 R14）、文件遍历面 walkFiles（L167–183：SKILL.md / *.pipeline.json / README.md / agents/*.md）、段落切分 splitMarkdown（L185–200）、豁免 isIgnored（±1 行）、report/enforce 退出语义（L340–360）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-8 的落点与判定粒度依据；规则清单不含 R14，本 CR 也不新增（AC-6）

16. repo: tools
   relative path: skills/shared/crctl/scripts/test/lint-prompts.test.mjs
   stable symbol/对象: makeFixture / runLint / MINI_DIR_GRAPH（L21–40）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: AC-8 的单元向量载体（临时 fixture + 黑盒 spawnSync），无需真实 tools 内容

17. repo: tools
   relative path: skills/shared/controlled-shell/rules.json
   stable symbol/对象: git 白名单 —— add: `^-A$` / `^-A -- .+$` / `^[^-].*$`；commit: `^-m (wip: |\[cr\] |merge\().*$`（flags s）；diff: `^--name-only .+$`；rev-parse: `^(HEAD|origin/\S+)$`
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-9 的 `git add -A -- <relpath>` 与 `[cr] …` 多行 commit 消息已被既有白名单放行，因此 rules.json **零 diff**（AC-11）；callers 字段当前仅记录不校验

18. repo: tools
   relative path: skills/shared/crctl/SKILL.md（review-record 行，L34）、skills/requirement/review-requirement/SKILL.md、skills/develop/review-tech-design/SKILL.md、skills/develop/review-dev-plan/SKILL.md、skills/develop/review-code/SKILL.md
   stable symbol/对象: review-record 子命令契约行与四份 payload 示例（verdict/blockers/dimensions/suggestions）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-10 的 5 处原位补写落点；四处示例结构都不含"单行标量"边界说明

19. repo: tools
   relative path: skills/shared/crctl/scripts/lib/yaml-subset.mjs
   stable symbol/对象: 头注释声明的解析边界（L1–5：支持块映射/块序列/flow/引号字符串/注释/`|` 与 `>` 保守拼接；不支持锚点、别名、tag、多文档）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-10 说明文本的事实依据；本 CR 不改该文件（AC-10）

20. repo: tools
   relative path: agents/dev-agent.md（`## 委派路由合同（评审）`，L31）、agents/_index.yml、agent-skill-matrix.yml
   stable symbol/对象: 现有委派合同段文本；_index.yml 9 个 agent（无 coordinator）；agent-skill-matrix.yml:25–29 的 cr-coordinator-agent（kind: system / mode: leader）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-6 的原位落点与 FR-4/AC-4 的反向验收基线

21. repo: tools
   relative path: skills/requirement/review-requirement/SKILL.md
   stable symbol/对象: Step 1.5 pre-review 门禁（L37–47）中的唯一命令形态 `crctl gate {cr_id} --for requirement-reviewing --mode pre-review --workspace <worktree>`（L42）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: FR-8 的零误报证据 —— 在 lint 扫描面内 `--mode pre-review` 仅此一处，且已同含 `--for requirement-reviewing`

22. repo: multica
   relative path: cr-prompts-revised/dev-agent.md、cr-prompts-revised/quality-reviewer-agent.md
   stable symbol/对象: dev-agent.md `## 环境与代码边界` 末段的 _context.md 维护规则（L47）；quality-reviewer-agent.md `## 入口识别与证据` 首段的 _context.md 引用（L19）
   commit SHA: 5fde81c1f463e7031663ef8111ee0b7ce39aac3c
   依赖结论: FR-1①② 的两个原位替换点；两份副本是与 tools 公共 Prompt 已分叉的部署副本（tools/agents/** 中 _context.md 命中为 0）

23. repo: multica
   relative path: cr-prompts-revised/cr-coordinator-agent.md
   stable symbol/对象: 章节结构 L11 职责 / L15 事实源与读取 / L24 路由 / L38 委派与评论 / L45 评审闭环 / L55 平台层权限 / L63 失败与输出
   commit SHA: 5fde81c1f463e7031663ef8111ee0b7ce39aac3c
   依赖结论: FR-5 的三节原位替换边界与 AC-5 的"四节 + frontmatter 原样"判定基线

24. repo: multica
   relative path: CUSTOM.md
   stable symbol/对象: 第 75 行登记条目（第 3 列"改动"的"仓库侧快照"定性；所在表头 `| # | 位置 | 改动 | 原因 / 追溯 | 日期 | 合并注意 |`）
   commit SHA: 5fde81c1f463e7031663ef8111ee0b7ce39aac3c
   依赖结论: FR-3 的单元格级落点与 AC-3 的"其它行零 diff"判定基线

25. repo: multica（含 tools 仓同名文档）
   relative path: ARCHITECTURE.md（multica 仓根；tools 仓根同名文档）
   stable symbol/对象: multica §4 依赖方向 / §5 不变量 4（CR authority split）与 9（新增或修改的源码注释必须英文）/ §6 Negative Space；tools §4 分层与依赖方向 / §5 硬不变量 1~8 / §6 刻意不做
   commit SHA: multica = 5fde81c1f463e7031663ef8111ee0b7ce39aac3c；tools = ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: 本 CR 不新增架构层、状态、账本通道或第三套依赖方向（tools 不变量 1/2/3/4/6/7/8 与 §6）；multica 侧改动全部为 Prompt/Markdown 文本，不触碰 Go 代码、不新增第二写者（不变量 4/9 与 Negative Space）

26. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: `syncLedgerIndex`（L682–689）在 index 恢复失败时抛出的 `TX_GIT_FAILED`（L688，携 `{paths}`）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: 恢复链中 `TX_GIT_FAILED` 的**内部**产生点（本轮补条）；步骤 13 直接调用 `syncLedgerIndex` 并由本地 catch 把它（连同 `TX_JOURNAL_INVALID` / `TX_RECOVERY_CONFLICT`）映射为 `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`，因此它**不在 reset 的对外错误闭包内**（§3.2、§3.5、§4.2.1 步骤 13，cycle 2 回修 B-01）

27. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs；skills/shared/crctl/scripts/lib/workspace-transactions.mjs
   stable symbol/对象: CR-ID 语法校验形态 —— `crctl.mjs` L2741 / L3273 / L3329 / L3335 / **L3513（`archive`）** / L3589 的 `/^CR-\d{4}-\d{3,}$/` 前置校验；`workspace-transactions.mjs` L36 `CR_DIR_RE = /^CR-\d{4}-\d{3,}$/` 与 **L3453（`ARCHIVE_CR_INVALID`）**
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: §4.1.1 的 `crIdForRecover` 语法判定与既有 `archive`/`version-set` 校验形态一致（同一正则、同一回退语义）；本轮补条（§5.3 D-3 与 §4.1.1 均引用它）

28. repo: tools
   relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs；skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: `cr-test-plan/v1` 执行器 `runTestPlan`（L4027–4084：逐条 `spawnSync(executable, args, { cwd: cmd.absoluteCwd, shell:false, timeout, env })`；`sourceRevision` 取 `cmd.absoluteCwd` 的 `git rev-parse HEAD`；每命令写 `cmd-NN.log` + `logSha256`；`skipped` 只在 stdout/stderr 两段上按冻结模式表判定）；`FROZEN_SKIP_PATTERNS`（L3993–3999）；`renderTestMachineReport`（L4104–4130）；`crctl git` 的 `--cwd`/`--workspace` 自旗标（`crctl.mjs` L3156–3160；L3427 `CRCTL_FLAGS` 不透传给 git）
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: §4.6 的四条证据命令契约均基于该执行器的真实语义（`repo` 列 = 被测仓/cwd 解析面与 `sourceRevision` 绑定面；`shell:false`；dot reporter 下 skip 不可见）；本 CR 不改该执行器

29. repo: tools
   relative path: skills/shared/crctl/scripts/test/crctl.test.mjs（BR-1 / BR-3 / BR-4）、skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs（BR-2）、skills/shared/crctl/scripts/test/archive-tx.test.mjs（BR-5）
   stable symbol/对象: 五个既有测试用例（完整测试名逐字 + 定义行 / 失败断言行，行号为采写时刻基线）：
     BR-1  crctl.test.mjs:1335 / 断言 :1343 — `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引`
     BR-2  checkpoint-tx.test.mjs:480 / 断言 :489 — `checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints[]`
     BR-3  crctl.test.mjs:4585 / 断言 :4597 — `TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）`
     BR-4  crctl.test.mjs:4797 / 断言 :4803 — `CR-2026-042 静态合同：已知 Skill 越界文本零命中`
     BR-5  archive-tx.test.mjs:373 / 断言 :391 — `TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖`
   commit SHA: ebdd6290f1523ffb682609b7ad6ab83e7d30245e
   依赖结论: 在未改动基线（该 SHA）上整目录实测 `node --test --test-reporter=dot`（21 个 `*.test.mjs`）→ exit=1、857 s、失败标记恰好 5 个（548 pass / 5 fail），逐条失败事实与归属见 §6.3 表；五条在本 CR 改动前即红，其根因对象分别落在本 CR 的 `zero_diff`（`pipeline-templates/**`、`dir-graph.yaml`、`write-requirement-prd/SKILL.md`）或 `scope_out`（`checkpoint`、`archive`）面，因此它们是**基线事实**而非本 CR 的回归；AC-12 的口径授权与 owner 决策项见 §6.4

**待核实依赖**：无（上列 29 项均已在三个 worktree 的当前 HEAD 上逐条核实）。

# 11. SDD-CLOSE 关闭清单

PRD 显式延后到 SDD 的设计项与需要 SDD 补齐的口径，逐项关闭如下。

```text
SDD-CLOSE-01  contractDrift 的定位（PRD FR-7 明文"该定位的说明归 SDD"）
  关闭结论: 恒为 true 的固定常量，只表示"该调用与版本化 Skill/Pipeline 声明不一致，须复核权威 Skill/Pipeline"；
            不携带区分信息、不是漂移类型分类器；调用方不得据此分支；与 recoverCommand 组合使用。
  覆盖层: 契约字段（§3.1）→ 语义定位（§3.1.1）→ 调用方处理流程（§1.3 流程 D）→ 验收（AC-7）。
  状态: 已关闭

SDD-CLOSE-02  gate 错配 recoverCommand 的精确形态
  关闭结论: `crctl workspace inspect <CR-ID>`；CR-ID 仅在匹配 ^CR-\d{4}-\d{3,}$ 时内插，否则回退占位符；
            无任何自由文本入口；不新增其它字段；与既有 recoverCommand 命名一致（dep-11）。
  状态: 已关闭

SDD-CLOSE-03  reset 的 expected hash 取值与 CAS 校验位置（PRD FR-9 第 2 条，S-4 后续）
  关闭结论: 用 readFileChecked 取原文 + sha256 作 expectedHash（先例 dep-4）；文件不存在时传 null；
            事务内部按 expectedHash 自行 CAS 校验；不经过 casWrite、不使用 readAttempts 取哈希。
  覆盖层: 数据生产（§4.2 步骤 7）→ 传输/事务入参（步骤 10）→ 校验实现（dep-8）→ 兼容降级（文件缺失 → null）。
  状态: 已关闭

SDD-CLOSE-04  reset 失败回滚与 index 一致化机制（PRD FR-9 第 5 条）
  关闭结论: 进程内失败 → abortLedgerTransaction 按 journal 的 beforeText 还原 → syncLedgerIndex（git add -A -- <relpath>）
            使 index 与还原后内容一致；崩溃窗口 → 下次同命令 recoverLedgerCommand 按 journal/trailer 分流（§4.2.2 真值表）。
  状态: 已关闭

SDD-CLOSE-05  reset 的提交消息与事务记账
  关闭结论: 提交消息 `[cr] review-loop reset <CR-ID> <loopRef> cycle <from> -> <to>` + 空行 + `AI-First-Tx: <txId>`；
            事务以 commitRequired=true 入账，"已提交/未提交"判定口径同 approve（dep-5）；commit 只含 review-loop.yml。
  状态: 已关闭

SDD-CLOSE-06  单文件 write-set 的具体改动点与零行为差异论证（PRD FR-9 第 3 条）
  关闭结论: 只改 lib/durable-tx.mjs 的比较数值；同构性论证见 §3.3 与 D-1；4 个既有调用点全部 ≥2 文件 → 零行为差异；
            空集仍被双重拒绝；不新增导出、不改 journal/manifest 结构、不改 recover/abort/finish 语义。
  覆盖层: 校验（§3.3）→ 事务入参（§4.2 步骤 10）→ 原语实现（dep-8）→ 既有消费者回归（AC-9⑥）。
  状态: 已关闭

SDD-CLOSE-07  R7 配对判据的判定范围与豁免
  关闭结论: 行级判定（与既有 R7 四类子判据同族）；触发 = 同行含 \bgate\b 与 `--mode pre-review`；必要条件 = 同行含
            `--for requirement-reviewing`；豁免沿用 ±1 行 ignore；不新增规则编号；零误报证据 dep-21。
  状态: 已关闭

SDD-CLOSE-08  AC-2 的验证方式（tech_context 指定：按 PRD §1.5 已确认口径设计，不重新解释）
  关闭结论: 计入集合（tools 的 agents/skills/pipeline-templates 全文件 + multica 的 cr-prompts-revised 全文件）命中 0；
            排除集合（tools 的 scripts/test/**）命中必须全为拒绝语义；交付检索命令与命中清单；
            不做语义机械化（S-5 范围外）。算法见 §4.5。
  状态: 已关闭

SDD-CLOSE-09  多仓路径 authority 与提交/checkpoint 口径
  关闭结论: 代码事实取 resources[].worktreePath（本 CR 三仓路径见 §1.4），不拼接 .rayai-worktrees；SDD 落 KB
            operational workspace；改动的两仓分别提交，架构审批后由同一批 crctl checkpoint 纳入；跨仓无运行时依赖，
            不需要跨仓事务（§1.4）。
  状态: 已关闭

SDD-CLOSE-10  需 SDD 承载的 PRD 措辞/机制补充（PRD 已被审批绑定，不得改）
  关闭结论: S-6 / S-7 两条 suggestion 的事实修正在本 SDD 的 dep-8 / dep-11 事实条目中落实（见 §12）；
            PRD 文本保持审批版本不变。
  状态: 已关闭

SDD-CLOSE-11  reset 失败错误闭包的唯一产生路径与审计语义（本轮 upstream 回修 B-01/S-1）
  关闭结论: REVIEW_LOOP_RESET_COMMIT_FAILED = 步骤 12 隔离断言不成立 或 commit 命令失败
            （{changed:false, rolled_back:true, recoverCommand}）；
            REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED = 步骤 13 恢复链（journal 还原 / index 恢复 / clean 复核）
            任一失败（{affected:[<relpath>]}，不带 recoverCommand）；
            两条失败路径都在 fail() 之前落 kind=review-loop-reset、result=commit-failed 的审计（不新增审计字段）。
  覆盖层: 契约（§3.2）→ 算法（§4.2.1 步骤 12/13）→ 窗口（§4.2.2 W2/W2b）→ 决策（§5.2 D-2）→ 验收（AC-9②③）。
  状态: 已关闭

SDD-CLOSE-12  「commit 只含 review-loop.yml」的保证手段（本轮 upstream 回修 B-01/S-2）
  关闭结论: 步骤 12 在 commit 前断言 queryTrackedChanges 的 unstaged 为空且 staged 恰为 [rel]（镜像 dep-5 的
            owner-set/version-set）；不成立则不 commit 并走失败回滚路径 ⇒ 外来 staged 变更永不被夹带；
            该前置不成立时的完整可观测结果见 §4.2.2 W2b。
  覆盖层: 契约（§3.2 提交隔离前置行）→ 算法（§4.2.1 步骤 12）→ 窗口（W2b）→ 安全控制点（§7.1）→ 验收（AC-9①②）。
  状态: 已关闭

SDD-CLOSE-13  AC-12 的可复核口径落地（本轮 upstream 回修 B-02/U-6、B-05；cycle 2 由评审 B-02 补强 + owner 授权闭环）
  关闭结论: AC-12 的**可复核判据** = 「全部 *.test.mjs（本轮枚举 21 个）被执行，失败集合恰等于 §6.3 登记的
            5 条基线红（不多也不少），不得新增红」；全量回归按 §4.6.2 做无重不漏分区纳入 canonical cmd-NN（每条带
            sourceRevision 与 cmd-NN.log 绑定）；例外仅以 5 条完整测试名的锚定模式排除，skipped=true 不作为通过；
            merge-fixture.mjs 需显式处置。基线红事实作为 dep-29 入§10（repo/path/测试名逐字/失败结论/SHA）。
            该口径相对 PRD AC-12/NFR-1 原文属目标放宽，其**授权不由 SDD 自行完成**，已由 owner 显式给出（选项 A；裁决人 Ray /
            权威评论 01a09099-97cf-7b5c-887e-4a8a369fa80e），授权记录见 §6.4；复评与人工 gate 均按该唯一口径。
  覆盖层: 契约（§4.6）→ 登记（§6.3）→ 依赖事实（dep-29）→ 授权记录（§6.4）→ 验收（AC-12）→ 预算（§7.2）。
  状态: 已关闭（口径落地完成；owner 授权已闭环，见 §6.4 授权记录）

SDD-CLOSE-14  FR-5 目标文本的仓内权威锚点（本轮 upstream 回修 B-03/S-5；cycle 2 由评审 B-03 补强）
  关闭结论: 三节目标文本逐字固化于 §6.2（含替换边界、LF 归一口径、逐块 sha256、来源文件 SHA256 与字节数）；
            块 3 额外冻结"旧块 + 两空格缩进行"的两行替换块（旧块 de2554c9… / 替换块 fc247a12… / 插入段 ed1941…），
            旧块起止唯一（该 bullet 行必须紧跟插入行，不得出现裸旧块或其它列表标记）；
            实现期逐字复制、不得转述；核对方式 = 按边界提取 + LF 归一 + 去尾换行 + sha256 比对（含整文件派生值 872457e6…）。
SDD-CLOSE-15  reset 恢复链的错误码收敛与 `TxError` 可验向量（cycle 2 评审 B-01 补强）
  关闭结论: 恢复链三步（abort / syncLedgerIndex / clean 复核）在步骤 13 内直接调用，不经 runTxAsync；
            内部 TxError（TX_JOURNAL_INVALID / TX_RECOVERY_CONFLICT / TX_GIT_FAILED）一律由本地 catch 映射为
            REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED（{affected}）+ 审计，不得以 TX_* 退出；可验向量 §4.2.2 W2c。
  覆盖层: 契约（§3.2 失败输出行）→ 错误闭包（§3.5）→ 算法（§4.2.1 步骤 13）→ 窗口（W2c）→ 决策（§5.2 D-2）→ 验收（AC-9②）。
  状态: 已关闭

SDD-CLOSE-16  跨仓证据命令的 revision 绑定（cycle 2 评审 B-04）
  关闭结论: repo 列 = 验收对象仓，sourceRevision = 该仓 worktree HEAD（cwd 必须相对且不越界，dep-28）；
            跨仓只读核对保持 repo = 对象仓、脚本用绝对正斜杠化路径；被读仓 revision 由同一 plan 内 repo = 该仓的
            绑定命令给出（“对象仓 + 被读仓”两条 sourceRevision 的组合才是完整证据面）；无法表达时拆两条命令。
  覆盖层: 契约（§4.6.1 推论 1）→ 分区（§4.6.2）→ 执行器语义（dep-28）→ 验收（AC-12②）。
  状态: 已关闭
```

# 12. 需求评审第 2 轮 carry-over 处理

| 项 | 状态 | 处理 |
|---|---|---|
| **S-6**：PRD §1.4 事实 10 括注把 `durable-tx.test.mjs` 说成"只测 write-set entry 校验与 journal 形状"，过窄 | **已处理**（落 SDD 事实） | 采纳 reviewer 建议的准确口径，写入 dep-8：该文件 9 个用例覆盖锁/竞争矩阵、journal 幂等加载、`applyWriteSet` redo/幂等/第三值冲突、kill-restart 恢复、`recoverWriteSet`、`cleanupTxBlobs`、checkpoint payload slot，其中**无 ledger write-set 规模断言**；`crctl.test.mjs:1432` 仅断言源码文本含 `beginLedgerCommand`。核心断言（无测试守卫 `≥2` 规则）成立，且因本 CR 放宽该规则，AC-9⑥ 明确要求新增该规则的可验断言。PRD 原文不改（审批绑定）。 | 
| **S-7**：PRD §1.4 事实 7 的 `recoverCommand` 出现面枚举漏 `crctl test`，且所列 `workspace-transactions.mjs:1074` 实属 `syncWorkspaceToTrunk` | **已处理**（落 SDD 事实） | 不再使用"只出现在"表述：dep-11 明确 `recoverCommand` 的出现面 = `register`/`checkpoint`/`merge`/`writeback`/`archive` 的事务返回与 `TxError` extra、`crctl test` 的 `buildTestResponse`（L4186）、`crctl workspace sync` 的 `syncWorkspaceToTrunk`（L1074）。结论（FR-7 沿用既有命名）不受影响。PRD 原文不改（审批绑定）。 |

两条均为**非阻塞项**，处理不扩大 scope_in、不改动范围（不据此新增或删除任何 FR/AC）。

# 13. 修订记录

- 初稿（2026-09-11，architecture-design node-1 `write-tech-design`）：以 PRD 修订 0.1.1 为输入起草。FR-1~FR-11 逐条给出「仓 + 文件 + 原位落法」；AC-1~AC-12 逐条给出设计落点/可观测结果/可达性；关闭 SDD-CLOSE-01~10；既有实现依赖 25 项（三仓当前 HEAD）；记录 D-1/D-2/D-3 三条决策；`review_feedback` 为空（首轮）。
- 修订 0.1.1（2026-09-11，`review-dev-plan` upstream blocker 回修 → `write-tech-design`）：按 canonical `review-annotations/dev-plan.yml`（`route=upstream`、`repair-target=write-tech-design`）逐条收口，并同轮落地技术设计评审的 5 条 suggestion（S-1~S-5）：
  - **B-01 / S-1 / S-2（`reset` 错误闭包与提交隔离）**：§4.2.1 步骤 12 新增"index 恰等于 write-set"的提交前断言（镜像 dep-5 的 `owner-set`/`version-set`），步骤 13 增补 try/catch 并明确 `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED` 的唯一产生点与两条失败路径的审计语义；§3.2 / §3.5 / §4.2.2（新增 W2b 窗口）/ §5.2 D-2 / §1.3 流程 C / §2.3 / §7.1 同步；两个 `REVIEW_LOOP_RESET_COMMIT_*` 码从此都有唯一产生路径，TASK 侧无需自行补手段。
  - **B-02 / S-3 / U-6（夹具与 AC-12 口径）**：dep-14 更正测试与行号并明文要求既有 reset 成功路径用例迁移到 `makeGitWorkspace()`、断言逐字不变（§4.2.1 尾注、AC-9 可达性列、§9 `scope_in`）；AC-12 由"全量既有测试通过"改为"失败集 ⊆ §6.3 登记基线红集合、不得新增红"，基线集合与归属成为可复核事实（§6.3）。
  - **B-03 / S-5（FR-5 逐字锚点）**：新增 §6.2，把 coordinator overlay 三节的目标文本逐字固化进本 SDD（含三块的替换边界、LF 归一口径、逐块 `sha256` 与来源文件 SHA256），并把 §3.4-B 与 §6 FR-5 改为引用该锚点、明文"逐字复制、不得转述"——AC-5 因此可在 CR worktree 内逐字核对。
  - **B-04 / B-05（证据命令可执行性与全量分区）**：新增 §4.6 固定 `crctl test` 执行语义（`repo` 列 = 被测仓 / cwd 与 `sourceRevision` 绑定面、`shell:false`、路径注入的 JSON 安全、冻结前干跑）与 AC-12 全量回归的"无重不漏分区 / 例外锚定 / 预算可达"契约；§4.6.2 明确 21 个 `*.test.mjs` 的枚举口径与 `merge-fixture.mjs` 的显式处置（旧 plan 的"22"= 目录文件总数）。
  - **B-06（恢复串断言面与向量）**：§3.2 新增"`recoverCommand` 出现面"行（只在失败结果与 FR-7 错误体；成功输出字段集不变、不含该字段），AC-7 与 AC-9③ 改为"只对失败结果断言 + 规范 CR-ID / 非规范输入两个向量分开断言"。
  - **U-4 / S-4（§10 补条）**：新增 dep-26（`syncLedgerIndex` 的 `TX_GIT_FAILED`）、dep-27（archive / version-set / workspace 的 CR-ID 校验正则，含 `ARCHIVE_CR_INVALID`）、dep-28（`crctl test` 执行器 `runTestPlan` 与 `crctl git --cwd` 语义）；§10 表头说明补条编号不再等于首次出现序。
  - 约束核对：未触碰 `prd.md`（审批绑定 `9247c107…`）；`scope_in`/`scope_out`/`zero_diff` 的边界未变（本轮新增条目均为既有批准范围内的设计澄清与证据契约）；`FR 11/11`、`AC 12/12` 覆盖不变。
- 修订 0.1.2（2026-09-11，`review-tech-design` cycle 2 BLOCK 回修 → `write-tech-design`）：按 canonical `review-annotations/sdd.yml`（`route=repair`、`repairTarget=write-tech-design`、attempt 1/3）逐条收口四条「部分解决」的 blocker（B-01~B-04）；B-05/B-06 的关闭结论不受影响：
  - **B-01（`reset` 恢复链的错误码收敛）**：§4.2.1 步骤 13 改为**直接** `await abortLedgerTransaction` / 直接调用 `syncLedgerIndex`（删除 `runTxAsync` 包装），恢复链的内部 `TxError`（`TX_JOURNAL_INVALID` / `TX_RECOVERY_CONFLICT` / `TX_GIT_FAILED`）一律由本地 catch 映射为 `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`；§3.2 失败输出行、§3.5 错误闭包（**删除** `TX_GIT_FAILED` 的对外码地位，改为"内部底层原因"）、§2.3、§5.2 D-2、dep-26 结论同步；新增 §4.2.2 **W2c** 窗口（`pre-commit` hook 写第三值后 `exit 1` ⇒ `TX_RECOVERY_CONFLICT` ⇒ 映射码 + 审计，不得以 `TX_*` 退出）作为"恢复链不经 `runTxAsync`"的可验向量，AC-9② 同步；`SDD-CLOSE-15`。
  - **B-02（AC-12 口径与基线事实）**：基线红 5 条逐条进入 §10 **dep-29**（repo / relative path / 测试名逐字 + 定义行 + 失败断言行 / 失败结论 / commit SHA），§6.3 从其引用；AC-12 与 §6.3 判据从"失败集 ⊆ 5 条"改为"失败集合**恰等于** 5 条（不多不少）"；新增 **§6.4** 把该口径相对 PRD AC-12/NFR-1 原文的放宽写为 **owner 人工决策项**（选项 A 授权例外 / 选项 B 保持全绿并指定 5 条红的归属），并说明本 node 在状态机上无回需求侧的边、`prd.md` 保持审批版本；§9 `follow_up` 补第 6/7 条；`SDD-CLOSE-13` 更新。
  - **B-03（FR-5 块 3 的唯一插入边界）**：§6.2 把块 3 从"在既有失败 bullet 内插入段"冻结为**两行替换块**——第 1 行 = 旧 bullet 逐字保留（141 B / `de2554c9…`）、第 2 行 = 行首两个半角空格 + 插入段正文（280 B / `0fdd50ac…`，去缩进后 = 块 3 的 `ed1941…`）；替换块整体 422 B / `fc247a12…`，并给出块 1/块 2 的旧块 `sha256` 与整文件派生值 `872457e6…`；§3.4-B、§6 FR-5 的 §3.3.3 条目与 AC-5 的判据同步为可机械核对的三个判据；`SDD-CLOSE-14` 更新。
  - **B-04（跨仓证据命令的 revision 绑定）**：§4.6.1 推论 1 改为"`repo` 列 = 验收对象仓，且是该命令 `sourceRevision` 的唯一绑定面（`cwd` 必须相对且不越界）"，明确跨仓只读核对**不得**把 `repo` 换成脚本所在仓（脚本用绝对、正斜杠化路径），并要求被读仓 revision 由同一 plan 内 `repo` = 该仓的绑定命令给出（"对象仓 + 被读仓"两条 `sourceRevision` 的组合才是完整证据面）；无法表达时拆两条命令；`SDD-CLOSE-16`。
  - 约束核对：未触碰 `prd.md`（审批绑定 `9247c107…`）；`scope_in` / `scope_out` / `zero_diff` 的边界未变（§9 只新增两条 `follow_up` 登记）；FR 11/11、AC 12/12 覆盖不变；tools / multica 两仓零改动。
- 结构规模：9 个 Skill 规定章节 + 既有实现依赖与事实（29 项，含本轮补条 dep-26~29）+ SDD-CLOSE 关闭清单 + carry-over 处理 + §4.6 证据命令契约 + §6.2 逐字锚点 + §6.3 基线红例外登记 + §6.4 AC-12 口径授权项；FR 覆盖率 11/11，AC 覆盖率 12/12。
