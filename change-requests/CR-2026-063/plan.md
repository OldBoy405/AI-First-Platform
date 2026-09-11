---
id: CR-2026-063-plan
type: PLAN
cr-ref: CR-2026-063
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
status: draft
created: 2026-09-11T22:54:10+08:00
updated: 2026-09-12T00:08:00+08:00
---

# CR-2026-063 开发计划（CR-P0 流程正确性止血 —— `_context.md` 合同退役、Prompt 源/overlay 归位、委派合同收紧、crctl 原子性与错误可操作化）

**权威输入（审批绑定，本计划不改其一个字节）**

| 输入 | 版本 | SHA256 | 绑定 |
|---|---|---|---|
| `change-requests/CR-2026-063/sdd.md` | SDD 修订 **0.1.4**（§13 修订记录末条；owner 授权记录落在 §6.4「AC-12 选项 A」与 **§6.5「FR-1① 目标段落文本口径甲」**） | `e1d44437202ed7aee59655e75df61ed798c1abffb70a9be66076a0fc3977525b` | `review-annotations/sdd.yml#subject-sha256`（cycle 3 / attempt 1，`verdict=pass`、`blockers=[]`）+ `approval.yml#tech-design`（`c05a6c02c8cf950319b92595f8141bb622af3cb652064e13a2798bf5a3cb98c8`，`2026-09-11T23:56:39+08:00`，target `tech-design-reviewed`） |
| `change-requests/CR-2026-063/prd.md` | PRD 修订 0.1.1 | `9247c107b1f87b72a5ee4ec5750f2f1da8be784aed04d23f47bb8d153eabda70` | 需求人工审批 evidence |

- **两个硬边界**：①**不改 `sdd.md`**；②**不改 `prd.md`**。二者哈希均被人工审批绑定，任何正文修订都必须走既有上游轨（`review-tech-design` → 二次人工审批），不得在 plan/TASK 里静默改写设计。
- **本计划版本谱系（三版，同一份文件）**：① `327a4cf8…`（照 SDD 0.1.0 写的初版，被 `review-dev-plan` 判 `route=upstream`、`repair-target=write-tech-design`，6 条 blocker，**整份作废**）；② 本版正文（按 SDD 0.1.2 = `ce51c168…` 从零重做，含 B-01~B-06 / S-1~S-5 的全部回修与 owner 对 AC-12 的选项 A 授权，TASK 卡同步重写）；③ **本轮定向刷新**（同一份 plan/TASK，SDD 修订 **0.1.4** = `e1d44437…` 定稿并重签后，只刷新 R-13 相关文本与全份对 SDD 修订号/哈希/审批证据摘要的引用——见 §4.1 R-13 与 §8 末行；**其余 10 个 FR 的 plan/TASK 与 `cmd-01`~`cmd-06` 六条证据命令逐字未动**，上一轮已被独立复评核验通过）。§8 给出评审发现的收口对照。
- 目标版本 `0.36`：继承 `cr.md#target-version`（未改写、无 `tbd`）。
- 交付面**唯一白名单** = PRD §1.3.1 的 14 行「仓 + 文件」表；`zero_diff` 清单见 SDD §9。本计划 §6.2 的 `cmd-03` / `cmd-04` 把该白名单做成机器判据。

## 0. 基线与工作区事实（落笔实读，一次读，未轮询）

- status = `tech-design-reviewed`；`crctl next CR-2026-063` = `write-dev-plan`（`humanApproval=false`）。架构阶段终点 checkpoint 曾于 SDD 修订**前**的基线上闭合（`crctl checkpoint --message 架构设计已审批`：`phase=complete`、`changed=true`、`batchId=f0a5978edf89bd03`、`metadataCommit=a7c0e28bd047572f857fbbbe531dfdae57b15fd3`，三仓 `confirmed=true`）；**该批次不覆盖 SDD 修订 0.1.4 之后的架构基线**（SDD 修订 `ab0b102b`、复评 `90226cf`、重签 `ab14322c` 均在其后）。按 `push-progress` 的既有口径（阶段终点 checkpoint 失效时**重跑同一 checkpoint、不重新审批**），本轮收尾以一次 `crctl checkpoint --message 架构设计重签后基线；开发计划与任务` 重新补齐，使远端重新拿到一个完整批次（结果随本次 Issue 汇报，不回写本文件）。
- `crctl workspace inspect CR-2026-063`：三个资源全部 `classification=healthy`、`dirty=false`、`localBranch/remoteBranch=true`；`operationalWorkspace` = KB requirement worktree（非空）。
- 路径 authority（`resources[].worktreePath` 原样值，**不拼接、不回退主工作区**）：

| repo | worktreePath | 分支 | HEAD（本计划落笔时刻） |
|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-063` | `requirement/CR-2026-063` | `a7c0e28bd047572f857fbbbe531dfdae57b15fd3`（KB HEAD 随 CR 产物/状态提交前移，**不作依赖证据**） |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-063` | `requirement/CR-2026-063` | `5fde81c1f463e7031663ef8111ee0b7ce39aac3c` |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-063` | `requirement/CR-2026-063` | `ebdd6290f1523ffb682609b7ad6ab83e7d30245e` |

- 实施落点：`tools`（`crctl.mjs`、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`、`lint-prompts.mjs`、`agents/dev-agent.md`、`crctl/SKILL.md` + 4 份 review SKILL、`scripts/test/**` 既有测试）+ `multica`（恰 4 文件：`cr-prompts-revised/{dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md` + `CUSTOM.md`）。KB 只承载本 CR 过程文档（plan / tasks / test-report / 证据），**不写 `specs/`、`delivery/`、`docs/`**。
- 无 DDL / 迁移 / 数据模型改动（SDD §2.1 N/A）；无新增子命令、账本字段、Pipeline 节点、评审维度（PRD §1.3.3 / FR-11）。
- 代码事实一律按 **stable symbol** 定位（SDD §10 的 dep-1~dep-29 已逐条绑定 repo / relative path / symbol / SHA），不按行号硬编码；开工前每个 TASK 重跑 `crctl workspace freshness CR-2026-063`（gate=implement-start）。

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 TASK | 估时 |
|---|---|---|---|
| M1 设计冻结 | PRD 修订 0.1.1 + SDD 修订 **0.1.4** `e1d44437…`（`tech-design-reviewed` + 人工重签 `c05a6c02…`）+ 架构阶段终点 checkpoint（重签后基线于本轮重新补齐，见 §0） | 已发生 | 0 |
| M2 计划与任务拆分 | 本 `plan.md` + `tasks/TASK-01…04.md` + `tasks/_index.yml`（`crctl task init --count-hint 4`）+ 推进 `task-breakdown` | 流程节点（非交付 TASK） | 0.5 人天 |
| M3 `gate` 错配可操作化与配对 lint | `crctl.mjs` `cmdGate` 错配分支 + `crIdForRecover` helper；`lint-prompts.mjs` R7 配对子判据；两侧用例（含 AC-7 双向量） | CR-2026-063-TASK-01 | 12h |
| M4 `review-loop reset` 原子提交 | `cmdReviewLoopReset` 改 async + 单文件 ledger 事务 + `git add`/commit + 提交隔离前置 + 失败回滚（`abort`→`syncLedgerIndex`→clean 复核）+ 审计；`lib/durable-tx.mjs` 前置条件一处放宽；新用例 W1/W2/W2b/W2c + 成功路径夹具迁移 | CR-2026-063-TASK-02 | 16h |
| M5 `_context.md` 合同退役 | `workspace-transactions.mjs` post-review `allowed` 条目+注释删除；CR-2026-057 既有测试**原位**改为退役合同测试；AC-2 计入集合归零 + 排除集合逐条语义判定 | CR-2026-063-TASK-03 | 8h |
| M6 Prompt/文档原位修订与范围收口 | multica 3 份 Prompt（两份部署副本退役 + coordinator 三节 §6.2 逐字替换）+ `CUSTOM.md#75` 单元格；`tools/agents/dev-agent.md` 委派合同六条；5 处 YAML 子集边界说明；AC-4/AC-11 反向验收与交付 diff 白名单核对 | CR-2026-063-TASK-04 | 16h |
| M7 评审与人工审批 | `review-dev-plan` → `approve --stage dev-start` → `implement-code` → `write-test-report`（`crctl test` 跑 §6.2 六条命令）→ `review-code` → `approve --stage code` | 流程节点 | 流程 |
| M8 发布 | `merge-feature-branch` / writeback / archive | 流程控制节点 | 流程 |

**估算总工时（TASK 账本口径）= 52h**（12h + 16h + 8h + 16h），与 `tasks/_index.yml#totalEstimateHours` 一致（`crctl task init` 返回值交叉校验）。M2 的 0.5 人天与 M7/M8 是流程节点，不进 TASK 账本。发布经既有 CR merge 流程，**不建交付 TASK**（流程控制 TASK 禁止：完成边界必须落在 `developing` 内可被 `crctl task done` 登记的事件，见 `write-dev-tasks` Step 2）。

## 2. 任务依赖图

```text
TASK-01 (tools：cmdGate 错配错误体 contractDrift+recoverCommand
         + crIdForRecover(cr) helper（一处定义，FR-7/FR-9 共用）
         + lint-prompts R7 配对子判据
         + crctl.test.mjs / lint-prompts.test.mjs 用例)
   │ 产出：crIdForRecover(cr) -> string（TASK-02 失败分支消费）；
   │        gate 错配错误体契约（BAD_ARGS + contractDrift:true + recoverCommand）；
   │        R7 finding 行为（不新增规则编号）
   ▼
TASK-02 (tools：cmdReviewLoopReset 原子提交（async + 单文件 ledger 事务
         + add/commit + 提交隔离前置 + abort/syncLedgerIndex/clean 复核回滚 + 审计）
         + durable-tx.mjs writes.length < 2 → < 1
         + crctl.test.mjs/durable-tx.test.mjs 用例（W1/W2/W2b/W2c、单文件 write-set、
           成功路径既有用例 makeWorkspace() → makeGitWorkspace() 且断言逐字不变）)
   │ 产出：reset 成功/失败契约与两个 op-scoped 错误码、单文件 write-set 能力
   ▼
TASK-03 (tools：workspace-transactions.mjs post-review allowed 删条目+注释
         + crctl.test.mjs CR-2026-057 测试原位改为退役合同测试（保留 _context2.md 反例）
         + AC-2 检索命令与命中清单证据)
   │
   ▼
TASK-04 (multica + tools 文本层：dev-agent.md / quality-reviewer-agent.md 段替换、
         cr-coordinator-agent.md 三节按 SDD §6.2 逐字替换、CUSTOM.md#75 单元格、
         tools/agents/dev-agent.md 委派合同、crctl/SKILL.md + 4 份 review SKILL 边界说明
         + AC-4/AC-11 反向验收与交付 diff 白名单核对)
```

- 依赖全部是「上游产出 → 下游消费」或「收口核对」：TASK-02 消费 TASK-01 的 `crIdForRecover`（SDD §4.1.1 明文「该 helper 供 FR-7 与 FR-9 共用」）；TASK-04 的 AC-11 白名单核对与 AC-12 全量回归收口消费 TASK-01/02/03 的全部产物。
- TASK-03 与 TASK-01/02 无逻辑依赖（`workspace-transactions.mjs` 与其它改动文件互不重叠），但同属 tools 仓 → **同一实现者串行执行**（同 repo 不并行写）。
- 无环、无悬空引用；`depends-on` 只声明真实产出/消费关系。
- **组映射（`write-dev-tasks` 三步断言的输入，`task_count_hint = 4`）**：G1 = `_context.md` 合同退役与活跃引用核对（FR-1③④、FR-2）→ TASK-03；G2 = `gate` 错配可操作化与配对 lint（FR-7、FR-8）→ TASK-01；G3 = `reset` 原子提交（FR-9）→ TASK-02；G4 = Prompt/文档归位、委派合同与范围收口（FR-1①②、FR-3、FR-4、FR-5、FR-6、FR-10、FR-11）→ TASK-04。每组恰一个 TASK、每个 TASK 恰属一组。

## 3. 资源与分工

- `cr.md` owners（权威）：requirement / development / test 均为 Ray（`assigned-at` 齐备，实施期从 `cr.md` 读取，不用本文件的缓存）。
- 实施执行：`dev-agent`（TASK-01…04）；测试报告由 `cr.md owners.test.id` 执行 `write-test-report` 并消费 `implement-code` 的真实验证结果；计划/代码评审由**新建的独立** `quality-reviewer-agent` task/run 执行（不自评、不复用作者会话）。
- 实施只写 `resources[].worktreePath` 指向的 worktree：tools 改动落 tools CR worktree，multica 改动落 multica CR worktree，过程文档落 KB worktree。

| TASK | 估时 | 仓库 | 说明 |
|---|---|---|---|
| CR-2026-063-TASK-01 | 12h | tools | `crctl.mjs`（`cmdGate` 错配分支 + `crIdForRecover`）、`lint-prompts.mjs` R7 子判据 + 两侧用例 |
| CR-2026-063-TASK-02 | 16h | tools | `crctl.mjs`（`cmdReviewLoopReset`）、`lib/durable-tx.mjs` 前置条件 + 新用例（W1/W2/W2b/W2c、单文件 write-set、夹具迁移） |
| CR-2026-063-TASK-03 | 8h | tools | `lib/workspace-transactions.mjs` `allowed` 集合、`crctl.test.mjs` 退役测试、AC-2 检索证据 |
| CR-2026-063-TASK-04 | 16h | multica + tools | 4 份 multica 文件 + 6 处 tools Prompt/文档 + AC-4/AC-11 反向验收与收口 |

## 4. 风险与回滚策略

### 4.0 回滚单元（逆拓扑组合回滚，唯一事实）

每个 TASK 的提交仍是独立 commit，但**回滚单元 = 含该 TASK 及其全部下游消费者的 commit 组合**，revert 顺序恒为 TASK 编号降序（先叶子后上游）。改动仓为 tools（`crctl.mjs` 由 TASK-01/02 共写、TASK-02 消费 TASK-01 的 helper）与 multica（仅 TASK-04）：

| 回滚单元 | 成员（revert 顺序） | 适用 |
|---|---|---|
| RU1 | TASK-04（仅叶子） | TASK-04 交付物缺陷（Prompt/文档文本、`CUSTOM.md#75` 单元格）；无下游消费其行为 |
| RU2 | TASK-04 → TASK-03 | TASK-03 缺陷（`allowed` 集合删除 / 退役测试）；TASK-04 的收口核对依赖它 |
| RU3 | TASK-04 → TASK-02 | TASK-02 缺陷（`reset` 原子提交 / durable-tx 放宽）；TASK-04 的收口核对依赖它 |
| RU4 | TASK-04 → TASK-02 → TASK-01 | TASK-01 缺陷（gate 错误体 / `crIdForRecover` / R7）；TASK-02 消费该 helper，故必须连带回退 |

- 任何 TASK 的缺陷：回滚 = 含该 TASK 的最小 RU，经**受控** `crctl git revert --no-edit <sha> --cwd <worktree>`（白名单形态 `^--no-edit (-m 1 )?\S+$`），按 RU 内顺序逐个执行。
- 唯一独立兼容性例外：若某 TASK 的 diff 经评审确认不依赖上游改动，可在 plan revision 中降级其回滚单元并注明依据；未证明前一律按上表。

### 4.1 风险表

| # | 风险 | 等级 | 应对 | 回滚 |
|---|---|---|---|---|
| R-01 | `lib/durable-tx.mjs` 共享前置条件放宽影响既有 4 个 ledger 调用点（`approve`/`owner-set`/`version-set`/`review-record`） | 高 | 只改一处比较数值（`< 2` → `< 1`），空 write-set 仍被双重拒绝（`applyWriteSet` 独立拒绝）；AC-9⑥ 断言单文件被接受 + 空集仍 `TX_WRITESET_INVALID`；既有 4 调用点事务测试在 cmd-01 内全绿 | RU3 |
| R-02 | `reset` 提交失败后回滚不彻底，留下 dirty 中间态（本 CR 的核心止血目标） | 高 | W1/W2/W2b/W2c 四窗口逐行测试（SDD §4.2.2 真值表）：失败路径断言「文件与 index 回到执行前 + tracked clean + HEAD 不变 + 审计已写」；W2c 断言恢复链内部 `TxError` 被本地 catch 收敛为 `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`、**不得以 `TX_*` 退出**（恢复链不经 `runTxAsync` 的可验向量） | RU3 |
| R-03 | 成功路径既有用例（`crctl.test.mjs` `CR-2026-049：review-loop reset 耗尽态开启下一 cycle，保留 attempts 历史`）用非 git 夹具 `makeWorkspace()`，改造后必走 commit 失败分支 | 中 | 按 SDD dep-14 迁移到 `makeGitWorkspace()`（必要时补一次基线 commit 以建立 HEAD），**断言与断言语义逐字不变**（仍断言 `status==0`、`current-cycle==2`、`current-attempt==0`、`attempts` 历史 3 条）；属 PRD §1.3.1 第 14 行既有测试修订面，不是契约放宽 | RU3 |
| R-04 | `crIdForRecover` 的 CR-ID 语法判定与占位符回退被复制成第二份正则 | 低 | helper 一处定义、两处调用（SDD §4.1.1）；TASK-01 产出、TASK-02 消费，`depends-on` 显式声明；接口契约逐字对齐 SDD §4.1.1（`^CR-\d{4}-\d{3,}$` 命中内插、否则 `<CR-ID>`） | RU4 |
| R-05 | 新 R7 子判据在真实仓库产生误报 | 中 | cmd-02（`lint-prompts --mode enforce`，真实仓库 0 findings——本计划干跑已实测）+ cmd-01（既有 R7 向量不回归）；SDD §4.3 零误报证据 dep-21 | RU4 |
| R-06 | 新 Prompt 段落违反文本纪律（R12/R13：≥3 个具名状态同段 / `_backlog.yml` 与状态判断同段 / guard-deny 路径 + 写动词） | 中 | cmd-02 以真实仓库 R1~R13 扫描；TASK-04 完成标志含「lint 零 finding」 | RU1 |
| R-07 | 基线红掩盖新红 | 中 | 例外**只**用 SDD §6.3 登记的 5 条完整测试名的锚定交替（`^(?:…)$`，正则元字符转义）；拼写失效 → 该用例真跑 → 红 → exit 1（fail-closed，无假绿）；全集与例外集合的对应关系已实测（§6.3 干跑记录③）；全套命令统一 `--test-reporter=dot` | 非代码缺陷，不触发 RU |
| R-08 | 证据命令不可按表执行或转录错误（上一版 dev-plan 的 B-04） | 高 | §6.2 的 6 条命令**逐条**按 `spawnSync(executable, args, {cwd, shell:false})` 在真实 worktree 干跑（§6.3 干跑记录）；跨仓脚本用**绝对、正斜杠化**路径（反斜杠不进注入字面量）；两条 `-e` 脚本零 `"`/零 `\`/零 `|`，可 JSON 往返逐字转录；命令集已过 `parseTestPlan` 校验（`command-digest = 841bb486d23b55c0fefd9d1f0f0838d2bc9548278f40539688889b6fa1675f7e`，且可从本文件 §6.2 逐字回抽复算——已实测） | 非代码缺陷，不触发 RU |
| R-09 | 全量回归超出 `write-test-report` 节点 20 min 预算 | 中 | 21 个 `*.test.mjs` 作为**单条** `cmd-01` 覆盖（实测 848.2 s，exit 0），加 lint 与断言类命令合计 §6.3 干跑总时长 ≈ 849 s < 1200 s；实测反证「拆成多条命令会更慢」：按 6 文件/13 文件拆分时 6 文件组单跑 > 600 s 超时、三组墙钟合计 > 954 s，故全集单命令是唯一满足预算且无重不漏的分区 | 非代码缺陷，不触发 RU |
| R-10 | coordinator overlay 三节替换越界或改写（AC-5 的逐字面） | 中 | 目标文本与替换边界由 SDD §6.2 唯一固定（本计划不复述、只引用）；cmd-04 按边界提取 + LF 归一 + 去尾换行 + `sha256` 比对（块 1 `833517ff…`、块 2 `dcd3b8e4…`、块 3 两行替换块 `fc247a12…`、插入段 `ed1941…`、整文件派生 `872457e6…`），并断言旧块 `de2554c9…` 不单独出现 | RU1 |
| R-11 | W2c 向量（恢复链自身失败）构造不当 → 断言恒真或恒假 | 中 | 用既有 `core.hooksPath` + `.githooks/pre-commit` 机制（SDD dep-13 先例）：hook 先把 `review-loop.yml` 写成第三值再 `exit 1`，断言链为「提交隔离失败 → `abortLedgerTransaction` 抛 `TX_RECOVERY_CONFLICT` → 本地 catch 映射 `..._ROLLBACK_FAILED` + 审计 + exit 1」；同时断言 stderr **不含** `TX_RECOVERY_CONFLICT` 作为对外码 | RU3 |
| R-12 | 单文件 write-set 的 journal/manifest 结构被顺手改动（越过 FR-9 第 3 条的「仅」边界） | 中 | `zero_diff` 明列该文件除比较数值外的全部内容；cmd-03 的白名单允许该文件出现，但 AC-9⑥ 与 `cmd-01` 的 `durable-tx.test.mjs` 全绿约束其行为面；review-code 按 SDD §3.3 逐项核对 | RU3 |
| R-13 | **FR-1① 的目标文本与 AC-1①/§4.5 的计入集合互相排斥**——上一轮 `review-dev-plan` 的 upstream blocker，**本轮已收口** | 高（已关闭） | **收口方式（上游轨，已完成）**：owner `Ray` 明文裁决 **口径甲**（权威评论 `01a0911c-b1ed-79bc-9164-99e611e2b51a`，`2026-09-11T15:36:12Z`），SDD 修订 **0.1.4** 据此把 §6 FR-1① 的目标段落改写为**不含 `_context.md` 文件名指称**的禁用句（禁止语义逐字保留），并新增 **§6.5** 授权记录（裁决人 / 时间 / 权威评论 / 授权范围 = 仅该目标段落文本 / 授权边界 = **任何 AC 判定面与阈值不动**）；复评 `review-tech-design` cycle 3 attempt 1 判 `pass` 且 `blockers=[]`，Ray 已在交互式终端重签 `--stage tech-design`（`c05a6c02…`，`gateBlockers` 已归空）。**plan/TASK 侧**：TASK-04 §3.1 的现用措辞（「不得创建或读取工作流上下文缓存副本」，不写出文件名指称）与该授权版文本**天然一致**——本轮只做核对，**未改一个字节**；`cmd-04` 与 `cmd-01`~`cmd-06` 的判据**均无需改动** | RU1 |

无迁移 / DDL / down 语义。回滚一律经受控 `crctl git` 形态执行。

## 5. 验收与发布策略

**估算总工时（TASK 账本口径）= 52h**（TASK-01 12h + TASK-02 16h + TASK-03 8h + TASK-04 16h）。

### 5.1 发布前 checklist

1. §6.2 的 cmd-01…cmd-06 逐条转录入 `cr-test-plan/v1` 并由 `crctl test` 执行且 **exit 0 且机器区每行 `skipped=false`**（cmd-NN 与 `test-evidence/cmd-NN.log` 一一对应，`sourceRevision` 绑定被测仓 HEAD）。
2. `write-test-report` `status=pass` 且 `blockers=[]`（命令集**只**来自 §6.2，不在 plan 之外另造命令；AC-2 排除集合的逐条语义判定随分析段交付）。
3. 独立 `review-dev-plan` `verdict=pass`、`blockers=[]`（plan + TASK 合并评审）。
4. `crctl approve --stage dev-start` 与 `--stage code` 均由人工（Ray）在交互式终端完成；**本轮 SDD 已被审批绑定，若实现期发现需改 SDD，必须走上游轨重新评审 + 二次人工审批**。
5. `../multica` `CUSTOM.md` 台账：本 CR 对 multica 的 4 个文件改动按当时实际结构登记（纪律 #10）；tools 侧无新增自研包，无需登记。
6. 交付 diff ∈ PRD §1.3.1 表（cmd-03 / cmd-04 机器判据 + cmd-05 / cmd-06 原始清单）；`zero_diff`（`rules.json`、`yaml-subset.mjs`、`gates.json`、`dir-graph.yaml`、`pipeline-templates/**`、`agents/_index.yml`、两仓 `agent-skill-matrix.yml`、`aifirst/agent-import.mjs`）零改动。
7. 无新增 SLO / M1–M8 / P50–P90 / 计数门禁 / 账本字段 / Pipeline 节点 / 评审维度（AC-11）。

### 5.2 发布与观测

- 无 feature-flag：本 CR 为原位修订（错误体补字段、内部写入路径原子化、文本合同），不引入开关语义。
- **部署不在本 CR 范围**：平台 DB 的 Prompt 投影与 `multica agent update` 由 owner 在 CR 落地后执行（PRD §1.3.2 / NFR-7）。
- 发布经既有 CR merge 流程（merge / writeback / archive），不进交付 TASK；审计以 `approval.yml`、`merge-commits.yml`、checkpoint 元数据为准。
- 发布后按 PRD §6 成功指标核验：活跃 `_context.md` 合同引用 = 0；post-review 白名单条目 = 0；`gate --mode pre-review` 错配 100% 返回恢复方向 + `contractDrift`；`reset` 成功后的 dirty 中间态 = 0；恢复串含用户输入处 = 0；新增观测指标/门禁/节点/字段 = 0；既有测试回归数 = 0（相对 SDD §6.3 登记的 5 条基线红）。

### 5.3 基线红例外（AC-12 的绑定对象，事实源 = SDD §6.3 / dep-29，本计划不复述）

- **登记事实源**：SDD §6.3「既有测试基线红例外登记（AC-12 的绑定对象）」逐条登记 BR-1~BR-5（文件 / 测试名逐字 / 失败事实 / 归属），其事实依据为 SDD §10 **dep-29**（tools `ebdd6290…` 未改动工作区实测：21 个 `*.test.mjs` 单跑 exit=1、857 s、失败标记恰好 5 个）。本计划**不复制该表**，只给出可执行口径。
- **可执行口径（本计划的机器判据）**：`cmd-01` 的 `--test-skip-pattern` = §6.3 五个**完整测试名**（正则元字符转义后）的锚定交替 `^(?:名字1|…|名字5)$`（本计划 §6.2 给出逐字模式，其中 BR-2 的 `[]` 需转义）；**不得**使用未锚定片段。
- **fail-closed**：模式拼写一旦失效，对应用例会被真正执行并报红 → `cmd-01` exit 1 → test-report `block`；同一命令内任何其它红同样是 `block`。
- **判定**：AC-12 = 「21 个 `*.test.mjs` 全部被 `cmd-01` 真实执行；失败集合**恰等于**登记 5 条（不得新增红、也不得靠 skip/删测试少红）」；该口径相对 PRD AC-12/NFR-1 原文的目标放宽**已由 owner 显式授权（选项 A）**：裁决人 `Ray`、权威评论 `01a09099-97cf-7b5c-887e-4a8a369fa80e`、授权记录 SDD **§6.4**，并已随架构人工审批 `c05a6c02c8cf9503…` 一并签核。本计划只承接该唯一口径，**不新增第二种通过定义**（`cmd-01` 的 `--test-name-pattern` 实测见 §6.3 干跑记录③）。
- **`merge-fixture.mjs` 的显式处置**（SDD §4.6.2 要求）：目录内 22 个文件的并集 = 21 个 `*.test.mjs`（全部进 `cmd-01`）+ 1 个非测试辅助模块 `merge-fixture.mjs`（被测试 `import`、不含 `test()`）。`cmd-03` 对它给出两条机械判据：① 逐行断言不存在 `test(` 定义行；② `require()` 加载成功且导出 `git`/`runCrctl`/`sha256` 三个函数（可加载性证明）。同时 `merge-tx.test.mjs`（在 `cmd-01` 内）本来就 `import` 它，构成第二条加载证据。

### 5.4 证据命令集的预算说明（`write-test-report` 节点 `timeoutMinutes=20`）

- §6.2 六条命令的**实测总时长 ≈ 849 s**（占 20 min 预算的 71%）：cmd-01 `848.2 s`、cmd-02 `0.1 s`、cmd-03 `0.2 s`、cmd-04 `0.2 s`、cmd-05 `0.1 s`、cmd-06 `0.1 s`（逐条干跑记录见 §6.3）。
- 每条命令的 `timeoutSeconds` ≥ 该命令实测时长（cmd-01 声明 1500 s ≥ 848.2 s；其余声明 120 s ≥ 0.2 s）。`timeoutSeconds` 是 kill-switch 上限，不参与预算比较；预算比较对象是实测时长。
- 预算约束下**不允许**把 21 个测试文件拆成多条顺序命令：实测拆分后墙钟上升（6 文件组 > 600 s 超时、三组合计 > 954 s，见 §6.3 干跑记录②），全集单命令是唯一同时满足「无重不漏」与「≤ 20 min」的分区。

## 6. 两张稳定表（契约必填节，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 `_context.md` 活跃合同退役（AC-1①②③④） | §6 FR-1 四行（① multica `dev-agent.md` 整段替换；② multica `quality-reviewer-agent.md` 首段改写；③ `workspace-transactions.mjs` post-review `allowed` 删条目+注释；④ `crctl.test.mjs` 既有白名单测试原位改为退役合同测试）+ §4.4 漂移判定 + dep-10/dep-12/dep-22 | CR-2026-063-TASK-03（关联 CR-2026-063-TASK-04 的①②文本文本面） | cmd-04（①②文本归零 + 结构）、cmd-03（③代码面 + AC-2 计入集合归零）、cmd-01（④退役测试断言 `post-review-path-drift` + `_context2.md` 仍拒绝） | RU2（③④代码面）／RU1（仅①②文本面） |
| FR-2 活跃引用全量核对（AC-2） | §6 FR-2 + §4.5 检索算法（计入/排除集合、检索命令、命中清单；不做语义机械化） | CR-2026-063-TASK-03（关联 CR-2026-063-TASK-04 的 multica 侧扫描面） | cmd-03（tools 计入集合 0 命中 + 排除集合命中清单）、cmd-04（multica `cr-prompts-revised/` 计入集合 0 命中） | RU2 |
| FR-3 Prompt 事实源归位（`CUSTOM.md#75`）（AC-3） | §6 FR-3（第 3 列单元格原位重写、五要素齐备；表结构不变、不新增行） | CR-2026-063-TASK-04 | cmd-04（五要素关键词 + 行数 492 + 其它行零 diff 由 cmd-06 的文件级清单兜底） | RU1 |
| FR-4 矩阵与索引零改动（AC-4） | §6 FR-4 + §9 `zero_diff`（`agents/_index.yml` 仍 9 agent、`agent-skill-matrix.yml` 保留 `cr-coordinator-agent` system actor、multica 矩阵零改动） | CR-2026-063-TASK-04 | cmd-01（`check-agents-contract.test.mjs` / `check-skill-matrix.test.mjs` 真实文件断言）、cmd-03（tools 白名单不含这两个文件 → 改动即失败）、cmd-06（multica diff 恰 4 文件） | RU1 |
| FR-5 coordinator overlay 三节原位替换（AC-5） | §6 FR-5（三处按 SDD §6.2 逐字替换；保留四节 + frontmatter；不整文件重写、不追加第五节） | CR-2026-063-TASK-04 | cmd-04（三块 `sha256` + 块 3 两行替换块 + 整文件派生哈希 + 三块新文本无推进命令）、cmd-06 | RU1 |
| FR-6 公共 dev-agent 委派合同（AC-6） | §6 FR-6（六条要求齐备；保留三条既有内容；不新增 R14 或等价委派 lint；文本纪律） | CR-2026-063-TASK-04 | cmd-03（六条要求关键词 + 既有内容保留 + `lint-prompts.mjs` 无 `R14`）、cmd-02（真实仓库 lint 零 finding） | RU1 |
| FR-7 `gate --mode pre-review` 错配可操作化（AC-7） | §3.1 错误体契约 + §3.1.1 `contractDrift` 定位 + §4.1.1 `crIdForRecover` 取值算法 + §4.1.2 判定树 + dep-1/dep-6/dep-27 | CR-2026-063-TASK-01 | cmd-01（`crctl.test.mjs`：`error.code=BAD_ARGS` + `contractDrift===true` + 恢复串双向量〔规范 CR-ID 内插 / 非规范回退 `<CR-ID>`〕+ 零写入 + `--for requirement-reviewing` 既有路径不变） | RU4 |
| FR-8 版本化 Prompt 的配对 lint（AC-8） | §3.4-A 判定契约 + §4.3 算法（R7 段内新增子判据、不新增规则编号、豁免机制不变） | CR-2026-063-TASK-01 | cmd-01（`lint-prompts.test.mjs` 正负向量 + 既有三类 R7 向量不回归）、cmd-02（真实仓库零 finding → 零误报） | RU4 |
| FR-9 `review-loop reset` 原子提交（AC-9①–⑥） | §3.2 命令契约 + §3.3 write-set 前置条件 + §4.2.1 时序（步骤 12 提交隔离 / 步骤 13 恢复链）+ §4.2.2 真值表（W1/W2/W2b/W2c）+ dep-2/dep-3/dep-8/dep-9/dep-13/dep-14/dep-26 | CR-2026-063-TASK-02 | cmd-01（`crctl.test.mjs`+`durable-tx.test.mjs`：成功路径已提交且 clean、W1/W2/W2b/W2c、恢复串只对失败结果断言、三条既有拒绝不变、cycle+1/attempt=0/attempts 保留、单文件接受/空集拒绝、4 既有调用点事务测试全绿） | RU3 |
| FR-10 `review-record` payload 的 YAML 子集边界（AC-10） | §6 FR-10（5 处原位补写：`crctl/SKILL.md` + 4 份 review SKILL；`yaml-subset.mjs` 零改动；示例结构不变） | CR-2026-063-TASK-04 | cmd-03（5 处均含「单行标量」与「多行引号标量」；`lib/yaml-subset.mjs` 不在白名单 → 改动即失败）、cmd-02（零新 finding） | RU1 |
| FR-11 零新增与不修改边界（AC-11） | §6 FR-11 + §9 `scope_in`/`scope_out`/`zero_diff` | CR-2026-063-TASK-04 | cmd-03（tools diff 白名单机器判据）、cmd-04（multica diff 恰 4 文件）、cmd-05／cmd-06（原始 `git diff --name-only` 清单，供内容级比对） | RU1 |

**表注（防假绿）**

① 「验收证据」列按「主责命令在前」列出覆盖本行验收面的全部 `cmd-NN`；每个 `cmd-NN` 与 §6.2 证据命令表的 `证据ID`、`crctl test` 机器区 `commands` 1-based 下标、`test-evidence/cmd-NN.log` 三者全等。
② FR-2 的排除集合（`tools/skills/shared/crctl/scripts/test/**`）按 SDD §4.5 是**人工逐条 + 命中清单证据**（机械化属 S-5 的范围外项）；`cmd-03` 只提供清单与计入集合的归零判据，不代做语义分类。
③ FR-3 的「其它行文字零 diff」由 `cmd-06` 的文件级清单 + 评审侧 `crctl git diff -U0 CUSTOM.md` 辅助判定承载（SDD §6.1 AC-3 可达性列口径）。
④ FR-4/FR-10/FR-11 的 `zero_diff` 对象**不在** PRD §1.3.1 白名单内，因此「被改动」会被 `cmd-03`/`cmd-04`/`cmd-06` 直接判失败（机器判据），不依赖人工比对；内容级「无新增 SLO/M1–M8/计数门禁…」仍由 `review-code` 按 diff 判定（SDD §6.1 AC-11 的核对方式）。
⑤ FR-5 的逐字面**不依赖本计划复述**：目标文本、替换边界、逐块与整文件哈希的唯一锚点是 SDD §6.2；`cmd-04` 按该锚点做机械比对。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["--test","--test-reporter=dot","--test-skip-pattern","^(?:CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引|checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints\\[\\]|TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）|CR-2026-042 静态合同：已知 Skill 越界文本零命中|TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖)$","skills/shared/crctl/scripts/test/archive-tx.test.mjs","skills/shared/crctl/scripts/test/check-agents-contract.test.mjs","skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs","skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs","skills/shared/crctl/scripts/test/contract-scan.test.mjs","skills/shared/crctl/scripts/test/crctl.test.mjs","skills/shared/crctl/scripts/test/durable-tx.test.mjs","skills/shared/crctl/scripts/test/fault-harness.test.mjs","skills/shared/crctl/scripts/test/lint-prompts.test.mjs","skills/shared/crctl/scripts/test/merge-tx.test.mjs","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs","skills/shared/crctl/scripts/test/register-tx.test.mjs","skills/shared/crctl/scripts/test/test-cr.test.mjs","skills/shared/crctl/scripts/test/trace-outbox.test.mjs","skills/shared/crctl/scripts/test/trace-semantic.test.mjs","skills/shared/crctl/scripts/test/upgrade-check.test.mjs","skills/shared/crctl/scripts/test/version-set.test.mjs","skills/shared/crctl/scripts/test/workspace-freshness.test.mjs","skills/shared/crctl/scripts/test/workspace-resolver.test.mjs","skills/shared/crctl/scripts/test/writeback-tx.test.mjs","skills/shared/crctl/scripts/test/yaml-subset.test.mjs"]` | 1500 |
| cmd-02 | tools | . | node | `["skills/shared/crctl/scripts/lint-prompts.mjs","--mode","enforce"]` | 120 |
| cmd-03 | tools | . | node | `["-e","const fs=require('fs'),path=require('path'),cp=require('child_process');;const T='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-063';;const NL=String.fromCharCode(10),CRLF=String.fromCharCode(13)+NL;;const bad=[];;const pick=(...v)=>{for(const x of v)if(x)return String(x);return '';};;const WL=['agents/dev-agent.md','skills/shared/crctl/scripts/crctl.mjs','skills/shared/crctl/scripts/lint-prompts.mjs','skills/shared/crctl/scripts/lib/durable-tx.mjs','skills/shared/crctl/scripts/lib/workspace-transactions.mjs','skills/shared/crctl/SKILL.md','skills/requirement/review-requirement/SKILL.md','skills/develop/review-tech-design/SKILL.md','skills/develop/review-dev-plan/SKILL.md','skills/develop/review-code/SKILL.md'];;const inScope=p=>WL.includes(p)?true:p.startsWith('skills/shared/crctl/scripts/test/');;const walk=(d,out,skipTest)=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);const n=p.split(path.sep).join('/');if(e.isDirectory()){if(e.name==='.git')continue;if(e.name==='node_modules')continue;if(skipTest&&n.includes('/skills/shared/crctl/scripts/test'))continue;walk(p,out,skipTest);}else{const ls=fs.readFileSync(p,'utf8').split(NL);for(let i=0;i<ls.length;i++){if(ls[i].includes('_context.md'))out.push(n+':'+(i+1)+': '+ls[i].trim());}}}};;const accounted=[],excluded=[];;for(const s of ['agents','skills','pipeline-templates'])walk(path.join(T,s),accounted,true);;walk(path.join(T,'skills/shared/crctl/scripts/test'),excluded,false);;console.log('AC-2 tools accounted-set hits = '+accounted.length);accounted.forEach(h=>console.log(h));;console.log('AC-2 tools excluded-set hits = '+excluded.length+'（逐条须读作「拒绝 _context.md」语义）');excluded.forEach(h=>console.log(h));;if(accounted.length)bad.push('AC-2 tools accounted-set hits = '+accounted.length);;const dev=fs.readFileSync(path.join(T,'agents/dev-agent.md'),'utf8');;const i=dev.indexOf('## 委派路由合同（评审）');;if(i<0){bad.push('agents/dev-agent.md 缺少「## 委派路由合同（评审）」节');}else{const j=dev.indexOf(NL+'## ',i+1);const s=dev.slice(i,j<0?dev.length:j);;for(const k of ['task/run','Runner','canonical','BAD_ARGS','CONTRACT_DRIFT','advance'])if(!s.includes(k))bad.push('dev-agent.md 委派合同缺少六条要求关键词「'+k+'」');;for(const k of ['自评','来源','独立会话'])if(!s.includes(k))bad.push('dev-agent.md 委派合同丢失既有内容「'+k+'」');};const lint=fs.readFileSync(path.join(T,'skills/shared/crctl/scripts/lint-prompts.mjs'),'utf8');;if(lint.includes('R14'))bad.push('lint-prompts.mjs 出现 R14（不得新增规则编号）');;const sites=[['skills','shared','crctl','SKILL.md'],['skills','requirement','review-requirement','SKILL.md'],['skills','develop','review-tech-design','SKILL.md'],['skills','develop','review-dev-plan','SKILL.md'],['skills','develop','review-code','SKILL.md']];;for(const s of sites){const t=fs.readFileSync(path.join(T,...s),'utf8');for(const k of ['单行标量','多行引号标量'])if(!t.includes(k))bad.push(s.join('/')+' 缺少「'+k+'」');};const fx=path.join(T,'skills/shared/crctl/scripts/test/merge-fixture.mjs');;const fxText=fs.readFileSync(fx,'utf8');;if(fxText.split(NL).some(l=>l.trim().startsWith('test(')))bad.push('merge-fixture.mjs 含 test() 定义（应仅为被 import 的辅助模块）');;let mod=null;;try{mod=require(fx);}catch(e){bad.push('merge-fixture.mjs 无法加载: '+String(e&&e.message?e.message:e));};if(mod)for(const e of ['git','runCrctl','sha256'])if(typeof mod[e]!=='function')bad.push('merge-fixture.mjs 未导出函数 '+e);;const crctl=T+'/skills/shared/crctl/scripts/crctl.mjs';;const diffOf=(sha,wt)=>{const r=cp.spawnSync(process.execPath,[crctl,'git','diff','--name-only',sha,'--cwd',wt],{encoding:'utf8'});if(r.status!==0){bad.push('crctl git diff 失败: '+pick(r.stderr,r.stdout).trim());return null;}const parts=String(pick(r.stdout)).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const files=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);return files;};;const d=diffOf('ebdd6290f1523ffb682609b7ad6ab83e7d30245e',T);;if(d){console.log('AC-11 tools diff（基线 ebdd6290f1523ffb682609b7ad6ab83e7d30245e）路径数 = '+d.length);d.forEach(f=>console.log('  '+f));;for(const f of d)if(!inScope(f))bad.push('AC-11 tools diff 越界路径（不在 PRD §1.3.1 白名单）: '+f);};if(bad.length){console.log('tools-audit failures = '+bad.length);bad.forEach(b=>console.log(b));process.exit(1);};console.log('tools-audit failures = 0');"]` | 120 |
| cmd-04 | multica | . | node | `["-e","const fs=require('fs'),path=require('path'),crypto=require('crypto'),cp=require('child_process');;const M='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-063';;const CRCTL='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-063/skills/shared/crctl/scripts/crctl.mjs';;const NL=String.fromCharCode(10),CRLF=String.fromCharCode(13)+NL,PIPE=String.fromCharCode(124);;const pick=(...v)=>{for(const x of v)if(x)return String(x);return '';};;const SH=s=>crypto.createHash('sha256').update(s,'utf8').digest('hex');;const strip=s=>s.endsWith(NL)?s.slice(0,-1):s;;const bad=[];;const read=(...p)=>fs.readFileSync(path.join(M,...p),'utf8').split(CRLF).join(NL);;const walk=(d,out)=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);const n=p.split(path.sep).join('/');if(e.isDirectory()){if(e.name==='.git')continue;if(e.name==='node_modules')continue;walk(p,out);}else{const ls=fs.readFileSync(p,'utf8').split(NL);for(let i=0;i<ls.length;i++){if(ls[i].includes('_context.md'))out.push(n+':'+(i+1)+': '+ls[i].trim());}}}};;const hits=[];walk(path.join(M,'cr-prompts-revised'),hits);;console.log('AC-2 multica accounted-set hits = '+hits.length);hits.forEach(h=>console.log(h));;if(hits.length)bad.push('AC-2 multica accounted-set hits = '+hits.length);;const dev=read('cr-prompts-revised','dev-agent.md');;if(dev.includes('_context.md'))bad.push('cr-prompts-revised/dev-agent.md 仍含 _context.md');;for(const k of ['crctl status','crctl next','cr.md','review-loop.yml','review annotations'])if(!dev.includes(k))bad.push('cr-prompts-revised/dev-agent.md 缺少 canonical resume 口径「'+k+'」');;const rev=read('cr-prompts-revised','quality-reviewer-agent.md');;if(rev.includes('_context.md'))bad.push('cr-prompts-revised/quality-reviewer-agent.md 仍含 _context.md');;for(const k of ['dir-graph.yaml','crctl status','canonical'])if(!rev.includes(k))bad.push('cr-prompts-revised/quality-reviewer-agent.md 缺少证据面「'+k+'」');;const coo=read('cr-prompts-revised','cr-coordinator-agent.md');;const want=['## 职责','## 事实源与读取','## 路由','## 委派与评论','## 评审闭环','## 平台层权限','## 失败与输出'];;const got=coo.split(NL).filter(l=>l.slice(0,3)==='## ').map(l=>l.trim());;if(JSON.stringify(got)!==JSON.stringify(want))bad.push('coordinator 章节集合或顺序不符: '+JSON.stringify(got));;if(coo.split('---').length-1<2)bad.push('coordinator 缺少 frontmatter 分隔符');;const lines=coo.split(NL);;const headIdx=n=>lines.findIndex(l=>l.trim()===n);;const nextH=i=>{for(let j=i+1;j<lines.length;j++)if(lines[j].startsWith('## '))return j;return lines.length;};;let i=headIdx('## 委派与评论'),j=nextH(i),last=j-1;while(last>i&&lines[last].trim()==='')last--;;const b1=lines.slice(i,last+1).join(NL);;if(SH(b1)!=='833517ffb7a70b238d338be51e4579736bc961cb4035c4c9513287a419a31525')bad.push('SDD §6.2 块 1（## 委派与评论 整节）sha256 不符 = '+SH(b1));;i=headIdx('## 评审闭环');j=nextH(i);let k=i+1;while(k<j&&lines[k].trim()==='')k++;;const b2=lines[k];;if(SH(b2)!=='dcd3b8e45b8cadd858f4f59789e31535e0b19835a064b27e039513521a5c8da8')bad.push('SDD §6.2 块 2（## 评审闭环 标准入口段）sha256 不符 = '+SH(b2));;i=headIdx('## 失败与输出');j=nextH(i);k=i+1;while(k<j&&lines[k].trim()==='')k++;;const old3='- 任何权限缺失、事实冲突或不可恢复技术错误：停止当前委派链，报告原始错误和明确的人类/平台动作。';;const l1=lines[k],l2=lines[k+1];;if(l1!==old3)bad.push('SDD §6.2 块 3 第 1 行不是旧 bullet 逐字原文: '+JSON.stringify(l1));;if(!(l2&&l2.slice(0,2)==='  '&&SH(l2.slice(2))==='ed1941707f03c8691325737471c1c08698269eea9d96e52bb664f8d5f3550115'))bad.push('SDD §6.2 块 3 第 2 行不是「两个半角空格 + 插入段正文（ed1941…）」');;if(SH(l1+NL+l2)!=='fc247a12436ea84e0bd6403b36c7151d149717fc30b5537f12cca91798a32f38')bad.push('SDD §6.2 块 3 两行替换块 sha256 不符 = '+SH(l1+NL+l2));;const whole=SH(strip(coo));;if(whole!=='872457e62ddfbadd40637dc7a293660fa8669c2e220afafa31454c53d271281c')bad.push('coordinator 整文件派生 sha256 不符 = '+whole);;for(const t of [b1,b2,l2])for(const c of ['--trigger','--expect','crctl approve --stage','git commit','git push'])if(t.includes(c))bad.push('三块新文本含可复制推进命令「'+c+'」');;const cus=read('CUSTOM.md');const cl=cus.split(NL);const n=cl[cl.length-1]===''?cl.length-1:cl.length;;if(n!==492)bad.push('CUSTOM.md 行数 = '+n+'（期望 492，不得新增行）');;const row=cl.filter(l=>l.startsWith(PIPE+' 75 '+PIPE));;if(row.length!==1)bad.push('CUSTOM.md #75 行匹配数 = '+row.length);else for(const c of ['tools/agents/','overlay','不再独立演进','投影','agent index'])if(!row[0].includes(c))bad.push('CUSTOM.md #75 单元格缺少五要素关键词「'+c+'」');;const want4=['cr-prompts-revised/dev-agent.md','cr-prompts-revised/quality-reviewer-agent.md','cr-prompts-revised/cr-coordinator-agent.md','CUSTOM.md'];;const r2=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','5fde81c1f463e7031663ef8111ee0b7ce39aac3c','--cwd',M],{encoding:'utf8'});;if(r2.status!==0){bad.push('crctl git diff 失败: '+pick(r2.stderr,r2.stdout).trim());}else{const parts=String(pick(r2.stdout)).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const files=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);;console.log('AC-11 multica diff（基线 5fde81c1f463e7031663ef8111ee0b7ce39aac3c）路径数 = '+files.length);files.forEach(f=>console.log('  '+f));;for(const f of files)if(!want4.includes(f))bad.push('AC-11 multica diff 越界路径: '+f);;for(const f of want4)if(!files.includes(f))bad.push('AC-11 multica diff 缺少应改文件: '+f);};if(bad.length){console.log('multica-audit failures = '+bad.length);bad.forEach(b=>console.log(b));process.exit(1);};console.log('multica-audit failures = 0');"]` | 120 |
| cmd-05 | tools | . | node | `["skills/shared/crctl/scripts/crctl.mjs","git","diff","--name-only","ebdd6290f1523ffb682609b7ad6ab83e7d30245e","--cwd","C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-063"]` | 120 |
| cmd-06 | multica | . | node | `["C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-063/skills/shared/crctl/scripts/crctl.mjs","git","diff","--name-only","5fde81c1f463e7031663ef8111ee0b7ce39aac3c","--cwd","C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-063"]` | 120 |

**args 列口径（转录纪律，逐条可机械核对）**

① `args` 为 JSON token 数组，**直接就是 `cr-test-plan/v1` 的 `args` 字段原文**：`write-test-report` 逐字转录，不得重新排版、不得取消转义、不得改写引号。
② `cmd-01` 的 `--test-skip-pattern` 在表内按 **JSON 字符串原文**书写：单元格里出现的 `|` 是锚定交替的分隔符（字面字符），`\\` 序列是 JSON 层转义（`JSON.parse` 后得回正则层 `\[` / `\]`，即 BR-2 测试名里的方括号）。本表**不**对该单元格做 Markdown 转义（与既有 `-run` 正则同惯例）；转录时连同 `\\` 一并逐字落盘，不得改成单个 `\`（那会让 JSON 非法、直接报错失败），也不得改写成 `\x7c` 之类等价写法。解析后的模式原文见 §6.2.1。
③ `cmd-03` / `cmd-04` 的 `-e` 脚本是**单参数**：脚本内**不含**双引号、反斜杠、换行与 `|`（需要 `|` 字符处用 `String.fromCharCode(124)` 构造、需要 CRLF 常量处用 `String.fromCharCode(13)`+`String.fromCharCode(10)` 构造），因此 `JSON.stringify` 往返逐字相同（已实测）。
④ **路径注入一律正斜杠化**（`C:/Users/…`），跨仓脚本用绝对路径；`cwd` 为对象仓 worktree 内的相对路径（本 CR 全部为 `.`），`repo` 列 = **验收对象仓**，即 `crctl test` 计算 `sourceRevision` 的绑定面（`repo=multica` 的两条命令因此不会把 `sourceRevision` 绑到脚本所在仓）。
⑤ **被读仓 revision 的绑定**：`cmd-01`/`cmd-02`/`cmd-03`/`cmd-05` 的 `repo=tools` 绑定 tools HEAD；`cmd-06` 的 `repo=multica` 绑定 multica HEAD；`cmd-04` 内部经绝对路径执行 tools 的 `crctl.mjs`（`crctl git`）读取 multica worktree——其「对象仓」为 multica（自带 `sourceRevision`），「被读仓」为 tools（由同表 `cmd-03`/`cmd-05` 绑定）。两条跨仓断言的证据面 = 「对象仓 `sourceRevision`」+「被读仓 `sourceRevision`」两条记录的组合（SDD §4.6.1 推论 1）。
⑥ 无 shell 字符串、无 pipe/redirect、无 env、无 `command` 字段、无绝对 `cwd`；`executable` 直接可 spawn（`node`）。

#### 6.2.1 cmd-01 的 `--test-skip-pattern` 字样（= SDD §6.3 五条完整测试名的锚定交替）

```text
^(?:CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引|checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints\[\]|TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）|CR-2026-042 静态合同：已知 Skill 越界文本零命中|TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖)$
```

- 该模式与 §6.2 `cmd-01` 行内的值是**同一个字符串**（此处仅供人读；转录以 §6.2 行内为准）。
- 五个名字逐字来自 SDD §6.3 的「测试名（逐字；锚定例外的唯一匹配对象）」列；BR-2 的 `checkpoints[]` 转义为 `checkpoints\[\]`，其余名字无正则元字符。
- 不用未锚定片段：锚点 `^(?:…)$` 保证只匹配完整测试名，新增用例（名称包含上述任一名字片段）不会被静默跳过。

#### 6.2.2 cmd-01 的 21 文件枚举（= AC-12 的分区全集，每文件恰好一次）

按文件名升序，与 SDD §6.3 的「全量文件清单（21 个）」逐条一致：

```text
archive-tx.test.mjs            check-agents-contract.test.mjs  checkpoint-tx.test.mjs
check-skill-matrix.test.mjs    contract-scan.test.mjs         crctl.test.mjs
durable-tx.test.mjs            fault-harness.test.mjs         lint-prompts.test.mjs
merge-tx.test.mjs              pipeline-structure.test.mjs    register-tx.test.mjs
test-cr.test.mjs               trace-outbox.test.mjs          trace-semantic.test.mjs
upgrade-check.test.mjs         version-set.test.mjs           workspace-freshness.test.mjs
workspace-resolver.test.mjs    writeback-tx.test.mjs          yaml-subset.test.mjs
```

非测试辅助模块 `merge-fixture.mjs` 的处置见 §5.3 末段（`cmd-03` 两条机械判据 + `cmd-01` 内 `merge-tx.test.mjs` 的 import）。

#### 6.2.3 cmd-03 / cmd-04 脚本的断言面（人读摘要；权威文本以 §6.2 行内为准）

- **cmd-03（repo=tools，对象仓 = tools）**：① AC-2 tools 计入集合（`agents/`、`skills/`、`pipeline-templates/`，排除 `skills/shared/crctl/scripts/test/**`、`.git`、`node_modules`）`_context.md` 命中数必须为 0；② 打印排除集合命中清单（供 AC-2 人工逐条判定「拒绝」语义）与计入集合清单；③ AC-6：`agents/dev-agent.md` 的 `## 委派路由合同（评审）` 节含六条要求关键词（`task/run`、`Runner`、`canonical`、`BAD_ARGS`、`CONTRACT_DRIFT`、`advance`）且保留既有三项（`自评`、`来源`、`独立会话`）；④ AC-6：`lint-prompts.mjs` 全文无 `R14`；⑤ AC-10：5 份 SKILL 均含「单行标量」与「多行引号标量」；⑥ `merge-fixture.mjs` 无非测试模块不应有的 `test(` 定义行、可 `require()` 加载且导出 `git`/`runCrctl`/`sha256`；⑦ AC-11：经内部 `crctl git diff --name-only <tools 基线>` 取清单，逐条必须在 PRD §1.3.1 白名单内（10 个具名路径 + `skills/shared/crctl/scripts/test/` 前缀）。
- **cmd-04（repo=multica，对象仓 = multica）**：① AC-2 multica 计入集合（`cr-prompts-revised/` 全文件）`_context.md` 命中数必须为 0；② AC-1①②：两份副本无 `_context.md` 且含 canonical resume 口径（`crctl status`、`crctl next`、`cr.md`、`review-loop.yml`、`review annotations`）与证据面（`dir-graph.yaml`、`crctl status`、`canonical`）；③ AC-5：coordinator 七个 `##` 标题集合与顺序、frontmatter 分隔符、块 1/块 2/块 3 两行替换块与插入段正文的 `sha256`（SDD §6.2 值）、整文件派生 `sha256`，且三块新文本不含 `--trigger`/`--expect`/`crctl approve --stage`/`git commit`/`git push`；④ AC-3：`CUSTOM.md` 行数 492 且 `| 75 |` 行含五要素关键词（`tools/agents/`、`overlay`、`不再独立演进`、`投影`、`agent index`）；⑤ AC-11：经内部 `crctl git diff --name-only <multica 基线>` 取清单，必须**恰等于** 4 个文件（`cr-prompts-revised/{dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md` + `CUSTOM.md`），多一个或少一个都失败。

### 6.3 干跑记录（SDD §4.6.1 第 3 条：冻结前必须按同一语义干跑）

干跑语义 = `spawnSync(executable, args, { cwd: <repo worktree>/<cwd>, shell:false, env: 去掉 CRCTL_OPERATIONAL_WORKSPACE })`，在三个真实 CR worktree 上执行（2026-09-11，实施前基线）。

| 证据ID | 可达性 | 实测时长 | exit | 干跑结论（当前预期失败集 / 命中清单） |
|---|---|---|---|---|
| cmd-01 | 可达（`node --test` 正常启动并跑完全部 21 文件） | `848.2 s` | 0 | 5 条登记基线红被锚定模式排除后**全绿**（dot 串 14 行 × 20 + 8，`skipped=false`）；若模式失效则对应用例真跑报红 → exit 1 |
| cmd-02 | 可达 | `0.1 s` | 0 | `lint-prompts enforce: 0 findings`（真实仓库 R1~R13 零误报，含新 R7 子判据上线前的基线） |
| cmd-03 | 可达 | `0.2 s` | 1 | 预期失败（实施前基线）：AC-2 tools 计入集合命中 2（`lib/workspace-transactions.mjs:1317/1318`，TASK-03 将删除）；排除集合命中 4（`crctl.test.mjs:4554/4560/4561/4565`，逐条读作「放行/断言」——TASK-03 原位改为退役合同测试）；六条要求关键词 6 条缺失、5 处 SKILL 边界说明 10 条缺失（TASK-04 补齐）；tools diff 清单 = 0 条（白名单判据通过） |
| cmd-04 | 可达 | `0.2 s` | 1 | 预期失败（实施前基线）：AC-2 multica 计入集合命中 2（`cr-prompts-revised/dev-agent.md:47`、`quality-reviewer-agent.md:19`，TASK-04 删除）；两份副本 canonical 口径关键词缺失；块 1/块 2/块 3 与整文件哈希均等于**旧值**（`fd0e9ce6…`/`06b084c2…`/`0df6a6df…`/`fbdfe8bc…`，TASK-04 替换为 §6.2 目标值）；`CUSTOM.md#75` 五要素关键词缺失；multica diff 清单 = 0 条（4 文件缺失） |
| cmd-05 | 可达 | `0.1 s` | 0 | tools diff 清单 = 空（基线即 `ebdd6290…`，实施后将输出全部改动路径供内容级比对） |
| cmd-06 | 可达 | `0.1 s` | 0 | multica diff 清单 = 空（实施后将输出 4 个文件） |
| 合计 | — | **≈ 849 s** | — | ≤ `write-test-report` 节点 1200 s 预算（余量 ≈ 351 s） |

补充干跑（非 `cmd-NN`，只用于冻结核对依据）：

1. **命令集 schema 校验**：§6.2 六条命令经 `parseTestPlan(plan, resolveRepositories(KB), 'CR-2026-063')` 校验通过，归一化结果为 `cmd-01/02/05 → repo=tools cwd=.`、`cmd-04/06 → repo=multica cwd=.`；`canonicalCommandSubject` digest = `841bb486d23b55c0fefd9d1f0f0838d2bc9548278f40539688889b6fa1675f7e`（该值由本文件 §6.2 逐字回抽后重新计算得到，与冻结值一致）。21 个测试文件在 args 中出现**恰好 21 次**（无重复、无遗漏）。
2. **拆分反证**（R-09）：同语义下按「crctl+durable-tx 组 / 6 个事务用例组 / 其余 13 文件组」三段跑，实测 `141 s` + `>600 s（超时中断）` + `213.2 s`，合计 > 954 s 且第二段超时仍失败；故不采用多命令分区。
3. **例外集合精确性**（R-07/§5.3）：以同一锚定模式改用 `--test-name-pattern`（正向只跑匹配项）在未改动基线上实跑 4 个相关文件，命中**恰好 5 条**测试且全部报红（`CR-2026-037 Prompt…`、`checkpoint T05 contract…`、`TASK-06 ⑤…`、`CR-2026-042 静态合同…`、`TASK-01 RED-7…`，22.7 s，exit 1）——证明锚定模式既不漏（5 条全是真红）也不多（无第 6 条被误排除）。
4. **JSON 往返**：两条 `-e` 脚本经 `JSON.stringify` → `JSON.parse` 往返后与原文逐字相同（脚本内 0 个 `"`、0 个 `\`、0 个 `|`、0 个换行）。

## 7. AC/业务闭环覆盖矩阵（契约必填节，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 四处原位修订全部落地（含 ③ 删除白名单后的 `post-review-path-drift` 拒绝） | §6 FR-1 + §4.4 + §6.1 AC-1 | CR-2026-063-TASK-03 | cmd-01；cmd-03；cmd-04 |
| 业务闭环：两份 multica 部署副本的 `_context.md` 段替换/改写后仍可承载 canonical resume | §6 FR-1①② + dep-22 | CR-2026-063-TASK-04 | cmd-04；cmd-06 |
| AC-2 计入集合 0 命中 + 排除集合命中全为拒绝语义（含检索命令与命中清单证据） | §4.5 + §6.1 AC-2 | CR-2026-063-TASK-03 | cmd-03（计入集合归零 + 排除集合清单）；cmd-04（multica 侧归零） |
| AC-3 `CUSTOM.md#75` 五要素齐备 + 其它行文字零 diff、行数不变 | §6 FR-3 + §6.1 AC-3 | CR-2026-063-TASK-04 | cmd-04；cmd-06 |
| AC-4 三处反向验收对象零改动（`_index.yml` 仍 9 agent、两仓矩阵保留 coordinator 声明） | §6 FR-4 + §9 `zero_diff` | CR-2026-063-TASK-04 | cmd-01；cmd-03；cmd-06 |
| AC-5 coordinator 三节逐条对应并逐字等于 SDD §6.2 锚点；四节 + frontmatter 原样；无步骤复述 | §6 FR-5 + §6.2（逐字锚点） + §6.1 AC-5 | CR-2026-063-TASK-04 | cmd-04；cmd-06 |
| AC-6 六条委派合同要求齐备 + 既有三条内容保留 + 无 R14 或等价委派 lint | §6 FR-6 + dep-15/dep-20 + §6.1 AC-6 | CR-2026-063-TASK-04 | cmd-03；cmd-02；cmd-01 |
| AC-7 `gate --mode pre-review` 错配：退出码非 0 + `BAD_ARGS` + `contractDrift===true` + 恢复串双向量 + 零写入 + 既有路径行为不变 | §3.1/§3.1.1/§4.1 + §6.1 AC-7 | CR-2026-063-TASK-01 | cmd-01 |
| AC-8 R7 配对正负向量 + 既有三类 R7 向量不回归 + 无新增规则编号 + 真实仓库零误报 | §3.4-A/§4.3 + §6.1 AC-8 | CR-2026-063-TASK-01 | cmd-01；cmd-02 |
| AC-9 reset 成功已提交且 clean／W1·W2·W2b·W2c 无 dirty 残留且 `TX_*` 不外泄／恢复串只对失败结果断言／三条既有拒绝不变／cycle+1·attempt=0·attempts 保留／单文件 write-set 被接受且空集仍拒 | §3.2/§3.3/§4.2 + §4.2.2 + §6.1 AC-9 | CR-2026-063-TASK-02 | cmd-01 |
| AC-10 5 处补写 + `yaml-subset.mjs` 零 diff + 示例结构不变 + 零新 finding | §6 FR-10 + §6.1 AC-10 | CR-2026-063-TASK-04 | cmd-03；cmd-02 |
| AC-11 零新增与 `zero_diff` 边界（tools 白名单 + multica 恰 4 文件） | §6 FR-11 + §9 | CR-2026-063-TASK-04 | cmd-03；cmd-04；cmd-05；cmd-06 |
| AC-12 21 个 `*.test.mjs` 全部真实执行、失败集恰等于登记 5 条、例外只锚定完整测试名、`skipped` 不为真 | §4.6/§6.3/§6.4 + dep-29 + §6.1 AC-12 | CR-2026-063-TASK-04（收口面；执行证据由 cmd-01 承载） | cmd-01 |
| 业务闭环：单文件 write-set 能力不改变既有 4 个 ledger 调用点行为 | §3.3 + D-1 + dep-8 | CR-2026-063-TASK-02 | cmd-01 |
| 业务闭环：`review-loop reset` 的两条失败路径都落审计（`result=commit-failed`）且只暴露 op-scoped 码 | §3.2/§3.5/§4.2.1 + D-2 + dep-5/dep-26 | CR-2026-063-TASK-02 | cmd-01 |
| 业务闭环：交付 diff 白名单可机器核对（无脚本/路径转录错误） | §4.6.1（repo/cwd/sourceRevision 契约）+ PRD §1.3.1 | CR-2026-063-TASK-04 | cmd-03；cmd-04；cmd-05；cmd-06 |

> **关键 AC 唯一 owner 说明（机械可判）**
> - **AC-7 / AC-8 唯一 owner = CR-2026-063-TASK-01**（`cmdGate` 错配分支与 `lint-prompts` R7 子判据的实际产生层；证据 cmd-01、cmd-02）。
> - **AC-9 唯一 owner = CR-2026-063-TASK-02**（`cmdReviewLoopReset` + `lib/durable-tx.mjs` 的实际产生层；证据 cmd-01）。
> - **AC-1 / AC-2 唯一 owner = CR-2026-063-TASK-03**（`allowed` 集合删除 + 退役测试 + AC-2 检索的实际产生层；证据 cmd-01、cmd-03、cmd-04）。
> - **AC-3 / AC-4 / AC-5 / AC-6 / AC-10 / AC-11 / AC-12 唯一 owner = CR-2026-063-TASK-04**（文本层与收口层：Prompt/文档落盘、反向验收、白名单核对、全量回归执行面；证据 cmd-02~cmd-06 与 cmd-01 的组合）。
> - 业务闭环行的证据面与关键 AC 行不重叠或可分别机械核验（各 `cmd-NN` 分属且语义不同）。

## 8. 上一轮评审发现的收口对照（旧 dev-plan BLOCK 与旧 plan 的上游项）

`review-annotations/dev-plan.yml`（`route=upstream`、`repair-target=write-tech-design`、attempt 0/3）的 6 条 blocker 已由 SDD 修订收口；本计划按新 SDD 重做，逐条对照如下（旧 plan 的 §8「上游设计修订项 U-1…U-6」整节作废，不再作为本计划的输入）。

| 旧评审发现 | SDD 收口落点 | 本计划的对应处置 |
|---|---|---|
| **B-01** 步骤 13 的回滚失败码无产生路径；步骤 12 缺提交前 index 前置断言 | §4.2.1 步骤 12/13 + §3.2/§3.5 + §5.2 D-2 + §4.2.2 W2b/W2c + `SDD-CLOSE-11/12/15` | TASK-02 按 SDD 实现两处均可验：提交隔离前置（`queryTrackedChanges` 断言 `unstaged` 空且 `staged` 恰为 write-set）+ 恢复链直接调用（不经 `runTxAsync`）；用例覆盖 W2b/W2c |
| **B-02** 非 git 夹具用例改造后必红；AC-12「全量既有测试通过」不可达 | dep-14 明文要求迁移到 `makeGitWorkspace()` 且断言逐字不变；§6.1 AC-12 改为「失败集恰等于登记 5 条」；§6.3 登记表 + §6.4 owner 授权（选项 A）+ §9 `follow_up` 第 6/7 条 | TASK-02 承担夹具迁移（断言不变）；AC-12 的口径与例外模式落到 §5.3 与 `cmd-01`；§7 矩阵的 AC-12 行按授权口径给出 |
| **B-03** AC-5 的三节来源文本在 CR worktree 内无权威锚点、cmd 只查关键词（可假绿） | §6.2 把三节目标文本、替换边界、逐块 `sha256`（含块 3 两行替换块与插入段）与整文件派生哈希固化在 SDD 内；§3.4-B / §6 FR-5 / `SDD-CLOSE-14` 同步 | 本计划**不复述**该锚点，`cmd-04` 直接按 SDD §6.2 做边界提取 + 归一 + `sha256` 比对（含块 3 形态判据） |
| **B-04** 证据命令不可按表直接执行（`cmd-09` 的 repo/cwd 与脚本路径不同仓；Windows 反斜杠被吞） | §4.6.1 固定 `repo` = 验收对象仓、`cwd` 相对且不越界、跨仓脚本用绝对正斜杠路径、被读仓 revision 由同一 plan 的另一条命令绑定；§4.6.1 第 2/3 条要求 JSON 安全注入与冻结前干跑 | §6.2 六条命令全部按该契约重做（`cmd-06` 脚本走绝对正斜杠路径、`repo=multica` 绑 multica、`cmd-03`/`cmd-05` 绑 tools），并逐条干跑（§6.3） |
| **B-05** 目录级全量回归未进 `cmd-NN`（无 `sourceRevision`/日志绑定）；例外用未锚定片段 | §4.6.2 无重不漏分区 + 锚定完整测试名 + `skipped` 语义 + 预算可达；§6.3 枚举 21 个 `*.test.mjs` 与 `merge-fixture.mjs` 的显式处置 | `cmd-01` 把 21 个文件**全部**纳入（每文件恰好一次），例外只用锚定交替；`merge-fixture.mjs` 由 `cmd-03` 显式处置；预算实测见 §5.4/§6.3 |
| **B-06** 恢复串断言面矛盾（成功输出被要求携带 `recoverCommand`） | §3.2「`recoverCommand` 出现面」行 + §6.1 AC-7/AC-9③（只对失败结果断言、两向量分开） | TASK-01/TASK-02 的验收向量按该口径写：成功结果**不作**恢复串断言，失败结果分别断言规范 CR-ID 内插 / 非规范回退 `<CR-ID>` |
| 旧 plan U-1…U-6（5 条技术设计 suggestion + AC-12 口径） | SDD §13 修订 0.1.1/0.1.2 + §6.4 授权记录 + `SDD-CLOSE-11…16` | 整节作废；本条仅作历史对照，不产生任何 TASK 或证据命令 |
| **上一轮 `review-dev-plan` 的 upstream blocker：R-13（FR-1① 目标文本 ↔ §6.1 AC-1① / §4.5 计入集合互斥）** | SDD 修订 **0.1.4** = `e1d44437202ed7aee59655e75df61ed798c1abffb70a9be66076a0fc3977525b`：§6 FR-1① 目标段落按 owner **口径甲** 改为**不含文件名指称**的禁用句（落点为 §3.4-B / §6 FR-1① / §6.1 AC-1① 口径注 / §4.5 口径注 / §11 `SDD-CLOSE-08`），并新增 **§6.5** 授权记录；**AC-1①/AC-2/§4.5 的集合、阈值与 grep 判据一字未动**（这是口径甲的定义性边界）；复评 `review-tech-design` cycle 3 attempt 1 判 `pass`、`blockers=[]`；人工重签 `--stage tech-design` = `approval.yml#tech-design.evidence-digest c05a6c02…`（`gateBlockers` 已归空，不再有 `EVIDENCE_DRIFT`） | **已收口**：TASK-04 §3.1 的既有措辞与该授权版文本天然一致（本轮逐字核对，无差异、未改动）；`cmd-04` 判据、`cmd-01`~`cmd-06` 六条证据命令、§6.2 两张稳定表、§7 覆盖矩阵、§4.0 回滚单元**逐字未动**。本计划本轮只做**定向刷新**：① 全份对 SDD 的修订号引用（0.1.3 → **0.1.4**）与哈希引用（`ce51c168…` → `e1d44437…`）；② 审批证据摘要（`11539869…` → `c05a6c02…`）与签核时间（`2026-09-11T23:56:39+08:00`）；③ §4.1 R-13 与本行（§8）的收口记录；④ §0 的 checkpoint 事实与本节末两条路由约束。其余 10 个 FR 的 plan/TASK **不重做、不改判据** |

- 本节点不修改 `sdd.md` / `prd.md`，不自行调用 `crctl advance` 到 `tech-design-review-pending`。**本轮硬边界**：SDD 修订 0.1.4 已被人工 gate 绑定（`approval.yml#tech-design` 的 `evidence-digest = c05a6c02…`，其证据面 = `review-annotations/sdd.yml`），对其任何字面改动都会再次产生 `EVIDENCE_DRIFT` 并让本次重签失效——因此 plan/TASK 与评审评论均**不得写出、不得暗示任何 SDD 正文修改**（S-1 类的非阻塞观察同样只登记不改动）。
- `review-dev-plan` 若判 `verdict=block` 且 `repair-target=write-tech-design`：按节点契约 `crctl advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker --expect task-breakdown --embedded`，由协调者派回 `write-tech-design`；SDD 修订 + 重跑 `review-tech-design` + 二次人工审批后，本节点按新 SDD 刷新 plan/TASK。**R-13 这一事项已由 SDD 0.1.4 §6.5 收口并重签，不得就同一事项再判 upstream**；若本轮出现新的上游疑点，须给出与该事项不同的、可复核的独立事实（并沿用同一 `advance` 形态）。
- 若判 `verdict=block` 且 `repair-target=write-dev-plan`（普通轨）：按 `write-dev-plan` Step 2a / `write-dev-tasks` Step 2a 回修本 plan/TASK（≤3 轮），**不动 SDD 正文、不扩大 `scope_out`**。

## 9. TASK 拆分预分配（`write-dev-tasks` 的输入，共 4 个，组映射 1:1）

| 变更组 | 覆盖 FR | TASK id | 仓库 | 粒度 | 依赖 |
|---|---|---|---|---|---|
| G2 `gate` 错配可操作化与配对 lint | FR-7、FR-8 | CR-2026-063-TASK-01 | tools | 1.5 天（12h） | — |
| G3 `review-loop reset` 原子提交 | FR-9 | CR-2026-063-TASK-02 | tools | 2 天（16h） | CR-2026-063-TASK-01（消费 `crIdForRecover`） |
| G1 `_context.md` 合同退役与活跃引用核对 | FR-1③④、FR-2 | CR-2026-063-TASK-03 | tools | 1 天（8h） | — |
| G4 Prompt/文档归位、委派合同与范围收口 | FR-1①②、FR-3、FR-4、FR-5、FR-6、FR-10、FR-11 | CR-2026-063-TASK-04 | multica + tools | 2 天（16h） | CR-2026-063-TASK-01、CR-2026-063-TASK-02、CR-2026-063-TASK-03 |

- 每个 in-scope FR 在 §6.1 交付覆盖表**恰出现一次**，主责 TASK 唯一（关联 TASK 不改变主责）。
- `task_count_hint = 4`（= 上表组数 = `tasks/_index.yml` 的 TASK 数）；`totalEstimateHours` 期望 = 52h，与 §1/§5 一致。
- 回滚单元按 §4.0（RU1~RU4，逆拓扑）；TASK 卡接口契约逐字对齐 SDD（`crIdForRecover` 由 TASK-01 产出、TASK-02 消费，见 SDD §4.1.1；`beginLedgerCommand`/`readFileChecked`/`sha256`/`abortLedgerTransaction`/`syncLedgerIndex`/`queryTrackedChanges` 的签名与语义见 SDD §4.2 与 dep-3/dep-5/dep-7/dep-8）。
- 交付 TASK 的完成边界全部落在 `developing` 内可被 `crctl task done` 登记的事件（实现已落盘 + 证据命令全绿 + 任务账本登记），**无 merge/writeback/archive/code-reviewing/code-approved 前置**（流程控制 TASK 禁止）。
