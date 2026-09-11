---
id: CR-2026-063-plan
type: PLAN
cr-ref: CR-2026-063
sdd-ref: "change-requests/CR-2026-063/sdd.md"
target-version: 0.36
status: draft
created: 2026-09-11T19:30:00+08:00
updated: 2026-09-11T19:30:00+08:00
---

# CR-2026-063 开发计划（CR-P0 流程正确性止血 —— `_context.md` 合同退役、Prompt 源/overlay 归位、委派合同收紧、crctl 原子性与错误可操作化）

输入：**已审批 SDD**（`change-requests/CR-2026-063/sdd.md`，`review-annotations/sdd.yml` verdict=pass、blockers=[]、`subject-sha256` = `c3319c5ad2b082c8987c73f4332d24fe110f99b5f816281d545b79944d396cbe`，技术评审提交 `3605a27a`，架构人工审批提交 `6c369194`）+ **已审批 PRD 修订 0.1.1**（`9247c107b1f87b72a5ee4ec5750f2f1da8be784aed04d23f47bb8d153eabda70`，人工审批 evidence `e49c2c94…`，需求期 checkpoint batch `53af81ca0e2b60fa`）。目标版本 `0.36`（继承 `cr.md`，未改写）。

> **本计划的两项硬边界（按协调者指令）**：①**不改 `sdd.md`**（其哈希被 `sdd.yml#subject-sha256` 与架构审批 evidence `787600f2…` 双重绑定）；②**不改 `prd.md`**（审批绑定 `9247c107…`）。本轮技术设计评审 5 条 suggestion 的落点判定与「上游设计修订项」单列见 **§8**——不在 plan/TASK 里静默改写设计。

## 0. 基线与工作区事实（落笔时实读，一次读，未轮询）

- status = `tech-design-reviewed`；`crctl next CR-2026-063` = `write-dev-plan`（humanApproval=false，why=技术设计已审批，编写开发计划）。
- `crctl workspace inspect CR-2026-063`：三个资源全部 `classification=healthy`、`dirty=false`、`localBranch/remoteBranch=true`；`operationalWorkspace` = KB requirement worktree（非空）。
- 路径 authority（`resources[].worktreePath` 原样值，**不拼接、不回退主工作区**）：

| repo | worktreePath | 分支 | 基线 HEAD（本计划证据锚点） |
|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-063` | `requirement/CR-2026-063` | `6c369194`（随本 CR 产物提交前移，不作依赖证据） |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-063` | `requirement/CR-2026-063` | `5fde81c1f463e7031663ef8111ee0b7ce39aac3c` |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-063` | `requirement/CR-2026-063` | `ebdd6290f1523ffb682609b7ad6ab83e7d30245e` |

- **基线红实测（本计划 §5.3 的唯一依据，落笔前在 tools CR worktree 的未改动基线上实跑取得）**：`node --test --test-reporter=dot --test-skip-pattern "CR-2026-037 Prompt|TASK-01 RED-7" <22 个 test 文件>` → exit 1，858 s，**3 条红**（`checkpoint-tx.test.mjs:480`、`crctl.test.mjs:4597`、`crctl.test.mjs:4803`）；被 skip 的 2 条另行单跑复现为红（`crctl.test.mjs:1335`、`archive-tx.test.mjs:373`）。合计 **5 条既有红**，全部与本次改动面无关且**改动前即红**。逐条见 §5.3。
- 本 CR 实施落点：`../tools`（crctl 脚本、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`、lint、`agents/dev-agent.md`、5 份 SKILL.md 与 4 个脚本的既有测试）+ `../multica`（恰 4 文件：`cr-prompts-revised/{dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md` + `CUSTOM.md`）。**KB 只承载本 CR 过程文档**（plan / tasks / test-report / 账本），不写 `specs/`、`delivery/`。
- 无 DDL / 迁移 / 数据模型改动（SDD §2.1 N/A）；无新增子命令、账本字段、Pipeline 节点、评审维度（PRD §1.3.3 / FR-11）。
- 交付 diff 的**唯一白名单**是 PRD §1.3.1 的 14 行「仓 + 文件」表（SDD §9 `scope_in`）；`zero_diff` 清单见 SDD §9，由 cmd-09 / cmd-10 机械核对。
- 开工前每个 TASK 重跑 `crctl workspace freshness CR-2026-063`（gate=implement-start 口径）；代码事实按 stable symbol 定位，不按行号硬编码。

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 TASK | 估时 |
|---|---|---|---|
| M1 设计冻结 | PRD 修订 0.1.1 + SDD（`tech-design-reviewed` + 人工审批） | 已发生 | 0 |
| M2 计划与任务拆分 | 本 `plan.md` + `tasks/TASK-01…04.md` + `tasks/_index.yml`（`crctl task init --count-hint 4`）+ 推进 `task-breakdown` | 非交付（流程节点） | 0.5 人天 |
| M3 `gate` 错配可操作化与配对 lint | TASK-01：`crctl.mjs` `cmdGate` 错配分支 + `crIdForRecover` helper；`lint-prompts.mjs` R7 配对子判据；两侧测试 | CR-2026-063-TASK-01 | 12h |
| M4 `review-loop reset` 原子提交 | TASK-02：`cmdReviewLoopReset` 改 async + 单文件 ledger 事务 + add/commit + 失败回滚 + 审计；`lib/durable-tx.mjs` 前置条件一处放宽；新用例（W1/W2/W3、write-set 向量、夹具迁移） | CR-2026-063-TASK-02 | 16h |
| M5 `_context.md` 合同退役 | TASK-03：`workspace-transactions.mjs` `allowed` 条目删除；CR-2026-057 既有测试**原位**改为退役合同测试；AC-2 检索证据（计入集合归零 + 排除集合逐条） | CR-2026-063-TASK-03 | 8h |
| M6 Prompt / 文档原位修订与范围收口 | TASK-04：multica 3 份 Prompt（退役 `_context.md` 段 + 三节 overlay 替换）+ `CUSTOM.md#75` 单元格；`tools/agents/dev-agent.md` 委派合同；5 处 YAML 子集边界说明；反向验收（AC-4 零改动）+ 交付 diff 白名单核对 + 全量回归 | CR-2026-063-TASK-04 | 16h |
| M7 评审与人工审批 | `review-dev-plan` → `approve-dev-start` → `implement-code` → `write-test-report` → `review-code` → `approve-code` | 流程节点（非交付 TASK） | 流程 |
| M8 发布 | `merge-feature-branch` / writeback / archive | 流程控制节点 | 流程 |

**估算总工时（TASK 账本口径，与 `tasks/_index.yml` 的 `totalEstimateHours` 一致）= 52h**（12h + 16h + 8h + 16h）；M2 的 0.5 人天与 M7/M8 为流程节点，不进 TASK 账本。发布经既有 CR merge 流程，**不建交付 TASK**（流程控制 TASK 禁止，`write-dev-tasks` Step 2）。

## 2. 任务依赖图

```text
TASK-01 (tools：crctl cmdGate 错配错误体 + contractDrift/recoverCommand
         + crIdForRecover helper（一处定义，供 FR-7/FR-9 共用）
         + lint-prompts R7 配对子判据 + crctl.test/lint-prompts.test 用例)
   │  产出：`crIdForRecover(cr) -> string`（FR-9 失败分支消费）、
   │        gate 错配错误体契约、R7 finding 行为
   ▼
TASK-02 (tools：crctl cmdReviewLoopReset 原子提交（async + 单文件 ledger 事务
         + add/commit + abort+syncLedgerIndex 回滚 + 审计）
         + lib/durable-tx.mjs writes.length < 2 → < 1
         + crctl.test/durable-tx.test 新用例（W1/W2/W3、write-set、夹具迁移）)
   │  产出：`review-loop reset` 的成功/失败契约与错误码、单文件 write-set 能力
   ▼
TASK-03 (tools：workspace-transactions.mjs post-review allowed 集合删条目
         + crctl.test.mjs CR-2026-057 测试原位改为退役合同测试
         + AC-2 检索命令与命中清单证据)
   │
   ▼
TASK-04 (multica + tools 文本层：dev-agent.md / quality-reviewer-agent.md /
         cr-coordinator-agent.md 三节 / CUSTOM.md#75 / tools/agents/dev-agent.md
         / crctl SKILL.md + 4 份 review SKILL 的 YAML 子集边界
         + AC-4/AC-11 反向验收核对 + 交付 diff 白名单 + 全量回归收口)
```

- 依赖全部为「上游产出 → 下游消费」或「收口核对」：TASK-02 消费 TASK-01 的 `crIdForRecover`（SDD §4.1.1 明文「该 helper 供 FR-7 与 FR-9 共用」）；TASK-04 的 AC-11/AC-12 收口核对与全量回归消费 TASK-01/02/03 的全部产物。
- TASK-03 与 TASK-01/02 无逻辑依赖（`workspace-transactions.mjs` + 测试文件中互不重叠的区域），但同属 tools 仓 → **同一实现者串行执行**（同 repo 不得并行写）。
- 无环、无悬空引用；`depends-on` 只声明真实产出/消费关系。
- **组映射（write-dev-tasks 三步断言的输入）**：G1 = `_context.md` 合同退役与活跃引用核对（FR-1③④/FR-2）→ TASK-03；G2 = `gate` 错配可操作化与配对 lint（FR-7/FR-8）→ TASK-01；G3 = `reset` 原子提交（FR-9）→ TASK-02；G4 = Prompt/文档归位、委派合同与范围收口（FR-1①②/FR-3/FR-4/FR-5/FR-6/FR-10/FR-11）→ TASK-04。每组恰一个 TASK，每个 TASK 恰属一组。

## 3. 资源与分工

- `cr.md` owners（权威）：requirement / development / test 均为 Ray（`assigned-at` 齐备）。
- 实施执行：`dev-agent`（本 Agent，TASK-01…04）；测试报告由 test owner 消费 `implement-code` 的真实验证结果；计划/代码评审由**新建的**独立 `quality-reviewer-agent` run 执行（不自评、不复用作者会话）。
- 实施只写 `resources[].worktreePath` 指向的 worktree：tools 改动落 tools CR worktree，multica 改动落 multica CR worktree，过程文档落 KB worktree；**不拼接、不猜测、不回退主工作区**。

| TASK | 估时 | 仓库 | 说明 |
|---|---|---|---|
| CR-2026-063-TASK-01 | 12h | tools | `crctl.mjs`（`cmdGate` + helper）、`lint-prompts.mjs` R7 子判据 + 两侧用例（含基线红 skip 说明） |
| CR-2026-063-TASK-02 | 16h | tools | `crctl.mjs`（`cmdReviewLoopReset`）、`lib/durable-tx.mjs` 前置条件 + 新用例（W1/W2/W3、单文件 write-set、既有夹具迁移） |
| CR-2026-063-TASK-03 | 8h | tools | `lib/workspace-transactions.mjs` allowed 集合、`crctl.test.mjs` 退役测试、AC-2 检索证据 |
| CR-2026-063-TASK-04 | 16h | multica + tools | 6 份 Prompt/台账 + 5 处 SKILL 文档补写 + 反向验收/白名单/全量回归收口 |

## 4. 风险与回滚策略

### 4.0 回滚单元（逆拓扑组合回滚，唯一事实）

每个 TASK 的提交仍是独立 commit，但**回滚单元 = 含该 TASK 及其全部下游消费者的 commit 组合**，revert 顺序恒为 TASK 编号降序（先叶子后上游）。目标仓是 tools（`crctl.mjs` 由 TASK-01/02 共写、TASK-02 消费 TASK-01 的 helper）与 multica（仅 TASK-04）：

| 回滚单元 | 成员（revert 顺序） | 适用 |
|---|---|---|
| RU1 | TASK-04（仅叶子） | TASK-04 交付物缺陷（Prompt/文档文本、`CUSTOM.md#75` 单元格）；无下游消费其行为 |
| RU2 | TASK-04 → TASK-03 | TASK-03 缺陷（`allowed` 集合删除 / 退役测试）；TASK-04 的收口核对依赖它 |
| RU3 | TASK-04 → TASK-02 | TASK-02 缺陷（`reset` 原子提交 / durable-tx 放宽）；TASK-04 的回归与白名单核对依赖它 |
| RU4 | TASK-04 → TASK-02 → TASK-01 | TASK-01 缺陷（gate 错误体 / `crIdForRecover` / R7）；TASK-02 消费该 helper，故必须连带回退 |

- 任何 TASK 的缺陷：回滚 = 含该 TASK 的最小 RU，经**受控** `crctl git revert --no-edit <sha> --cwd <worktree>`（白名单形态 `^--no-edit (-m 1 )?\S+$`），按 RU 内顺序逐个执行。
- 独立兼容性例外：若某 TASK 的 diff 经评审确认不依赖上游改动（如纯文档改动），可在 plan revision 中降级其回滚单元并注明依据；未证明前一律按上表。

### 4.1 风险表

| # | 风险 | 等级 | 应对 | 回滚 |
|---|---|---|---|---|
| R-01 | `durable-tx.mjs` 共享前置条件放宽影响既有 4 个 ledger 调用点（`approve`/`owner-set`/`version-set`/`review-record`） | 高 | 只改一处比较数值（`< 2` → `< 1`），空集仍双重拒绝；AC-9⑥ 的可验断言（cmd-01）覆盖单文件接受/空集拒绝；事务消费者回归族 cmd-05 全绿为「零行为差异」证据 | RU3 |
| R-02 | `reset` 的 commit 失败回滚不彻底，留下 dirty 中间态（本 CR 的核心止血目标） | 高 | W1/W2/W3 崩溃窗口真值表逐行测试（cmd-01）；失败路径 `abortLedgerTransaction` → `syncLedgerIndex` 后断言「文件与 index 回到执行前 + tracked clean + HEAD 不变 + 审计已写」（镜像 `owner-set`/`approve` 既有先例） | RU3 |
| R-03 | 既有成功路径用例（`crctl.test.mjs:3430–3452`）用非 git 夹具，改造后必走 commit 失败分支 | 中 | TASK-02 显式迁移该用例到 `makeGitWorkspace()`，**断言不变**（SDD 侧口径修订见 §8 U-3；不迁移则 AC-9⑤/AC-12 在该用例上不可达） | RU3 |
| R-04 | `crIdForRecover` 的 CR-ID 语法判定与占位符回退被复制成第二份正则 | 低 | helper 一处定义、两处调用（SDD §4.1.1）；TASK-01 产出、TASK-02 消费，`depends-on` 显式声明；接口契约逐字对齐 SDD §4.1.1 | RU4 |
| R-05 | 新 R7 子判据在真实仓库产生误报（`--mode pre-review` 在扫描面内仅 1 行且已配对） | 中 | cmd-04（`lint-prompts --mode enforce`，真实仓库零 finding）+ cmd-02（既有 R7 向量不回归）；SDD §4.3 零误报证据 dep-21 | RU4 |
| R-06 | Prompt 文本纪律违规（新段落出现 ≥3 具名状态 / `_backlog.yml` 与状态判断同段 / guard-deny 路径 + 写动词） | 中 | cmd-04 以 R1~R13 扫描真实仓库；TASK-04 完成标志含「lint 零 finding」 | RU1 |
| R-07 | 基线红掩盖新红：`crctl.test.mjs` / `archive-tx.test.mjs` / `checkpoint-tx.test.mjs` 已有 5 条红| 中 | §5.3 基线红例外登记表逐条记录（本计划在**未改动基线**上实测）；证据命令用 `--test-skip-pattern` 精确排除这 5 条（模式失败→该用例会被真正执行→红→exit 1，**fail-closed**，不产生假绿） | 非代码缺陷，不触发 RU |
| R-08 | 5 条技术设计评审 suggestion 需改 SDD 正文，实现期若按摘要硬实现会偏离已审批设计 | 高 | §8 单列「上游设计修订项」U-1…U-6（逐条结论 + 理由 + SDD 落点），plan/TASK **不静默改写设计**；由 `review-dev-plan` 判定 upstream 轨 | 非代码缺陷，不触发 RU |

无迁移 / DDL / down 语义。回滚一律经受控 crctl git 形态执行。

## 5. 验收与发布策略

**估算总工时（TASK 账本口径）= 52h**（TASK-01 12h + TASK-02 16h + TASK-03 8h + TASK-04 16h）。

### 5.1 发布前 checklist

1. cmd-01…cmd-10 全部按 §6.2 转录入 `cr-test-plan/v1` 并由 `crctl test` 执行；**exit 0 且机器区 `skipped=false`**（cmd-NN 与 `test-evidence/cmd-NN.log` 一一对应）；关键 AC 的验收证据见 §7。
2. `write-test-report` status=pass 且 blockers=[]（消费 `implement-code` 真实验证结果；命令集逐条转录 §6.2，不在 plan 之外另造命令）。
3. 独立 `review-dev-plan` verdict=pass、blockers=[]（plan + TASK 合并评审）。
4. `crctl approve --stage dev-start` 与 `--stage code` 均经人工（Ray）；本轮技术设计审批已闭环，**再次修订 SDD 需按 §8 的上游轨另行人工审批**。
5. `../multica` `CUSTOM.md` 台账：本 CR 对 multica 的 4 个文件改动按当时实际结构登记（纪律 #10）；tools 侧无新增自研包，无需登记。
6. 交付 diff 白名单核对（cmd-09 / cmd-10）∈ PRD §1.3.1 表；`zero_diff`（`rules.json` / `yaml-subset.mjs` / `gates.json` / `dir-graph.yaml` / `pipeline-templates/**` / `agents/_index.yml` / 两仓 `agent-skill-matrix.yml` / `aifirst/agent-import.mjs`）零改动。
7. 无新增 SLO / M1–M8 / P50–P90 / 计数门禁 / 账本字段 / Pipeline 节点 / 评审维度（AC-11）。

### 5.2 发布与观测

- 无 feature-flag：本 CR 为原位修订（错误体补字段、内部写入路径原子化、文本合同），不引入开关语义。
- **部署不在本 CR 范围**：平台 DB 的 Prompt 投影与 `multica/aifirst/agent-import.mjs` 由 owner 在 CR 落地后执行（PRD §1.3.2 / NFR-7）。
- 发布经既有 CR merge 流程（merge / writeback / archive），不进交付 TASK；审计以 `approval.yml`、`merge-commits.yml`、checkpoint 元数据为准。
- 发布后按 PRD §6 成功指标核验：活跃 `_context.md` 合同引用 = 0；post-review 白名单条目 = 0；`gate --mode pre-review` 错配 100% 返回恢复方向 + `contractDrift`；`reset` 成功后的 dirty 中间态 = 0；恢复串含用户输入处 = 0；新增观测指标/门禁/节点/字段 = 0；既有测试回归数 = 0（相对 §5.3 登记集合）。

### 5.3 基线红例外登记表（R-07，于 tools 基线 `ebdd6290f1523ffb682609b7ad6ab83e7d30245e` 未改动工作区实测）

**实测方式**：tools CR worktree（`dirty=false`）+ `node --test --test-reporter=dot`，22 个 `skills/shared/crctl/scripts/test/*.test.mjs`，858 s，exit 1。5 条红的文件名 / 测试名 / 失败断言如下（**全部在本次改动前即红**，且与 FR-1~FR-11 的改动面无关）：

| # | 文件:行 | 测试名（逐字） | 失败事实 | 与本 CR 的关系 |
|---|---|---|---|---|
| BR-1 | `crctl.test.mjs:1335`（断言 `:1343`） | `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引` | `assert.match(pipelineText, /crctl task init/)` 失败——`code-implementation.pipeline.json` 全文件无 `task init`（仅 `write-dev-tasks/SKILL.md` 有）；CR-2026-060 §5.3 BR-1 已登记、根因修复归 follow_up | `pipeline-templates/**` 在本 CR 的 `zero_diff` 内，不改；本 CR 不改 `write-dev-tasks/SKILL.md` |
| BR-2 | `checkpoint-tx.test.mjs:480`（断言 `:489`） | `checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints[]` | `assert.ok(alignment.includes('latest-checkpoint'))` 失败 | `checkpoint` 不在 scope_in；`pipeline-templates/**` 零改动 |
| BR-3 | `crctl.test.mjs:4597` | `TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）` | `31 !== 28`——`tools/dir-graph.yaml` 现有 31 条声明转移（实测逐条计数），断言仍写 28 | `dir-graph.yaml` 在 `zero_diff` 内，本 CR 不改状态机 |
| BR-4 | `crctl.test.mjs:4803` | `CR-2026-042 静态合同：已知 Skill 越界文本零命中` | `write-requirement-prd/SKILL.md` 的 Step 4 措辞与期望正则 `/重新读取 \`prd\.md\`.*frontmatter 必填字段、七个章节和未替换占位符/` 不符（Skill 已含「以及（定义了用户可调用契约时）下列确定性四查」） | 本 CR 不改 `write-requirement-prd/SKILL.md`（FR-10 只改 `crctl/SKILL.md` + 4 份 review SKILL） |
| BR-5 | `archive-tx.test.mjs:373`（断言 `:391`） | `TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖` | `actual: [{code:'EMIT_FAILED', event_kind:'archive'}]` vs `expected: []`；CR-2026-060 §5.3 BR-2 已登记、根因修复归 follow_up | `archive` 不在 scope_in；本 CR 不改 archive 事件发射内核 |

**判定规则（冻结）**：证据命令的 `--test-skip-pattern` **只准**排除上表 5 条测试名；`crctl test` 机器区 `skipped=true` 一律不接受为通过（node 侧统一 `--test-reporter=dot`）。任何其它红 = 回归，plan/TASK 的完成标志与 test-report 判 block。skip 模式一旦拼写失效，对应用例会被真正执行并报红 → exit 1，**fail-closed**。BR-1/BR-5 的根因修复属后续 CR（CR-2026-060 §5.3 的 follow_up 承接），本 CR 不修（避免扩大 `scope_out`）。

### 5.4 证据命令集的预算说明（write-test-report 节点）

`code-implementation` pipeline 的 `write-test-report` 节点 `timeoutMinutes=20`。§6.2 的 10 条命令实测/估算总时延约 **15–17 min**（其中 cmd-01 ≈ 8 min、cmd-05 ≈ 6 min，其余 ≤1 min）；因此**目录级 22 文件全量运行（单跑 858 s）不作为 cmd-NN 纳入 `crctl test` 计划**，而是作为 implement-code 期的验证项写入 TASK-01/02/04 的完成标志（`implement-code` 节点预算 240 min）。AC-12 的机器证据由 cmd-01（crctl + ledger/durable-tx 族）、cmd-02（prompt lint 族）、cmd-03（pipeline structure / contract-scan / agents-contract / skill-matrix 族）、cmd-05（事务消费者族）四条共同承担，覆盖 SDD §6.1 AC-12 明列的族。若 reviewer 判定需把目录级全量运行也纳入 `crctl test`，落点为 §6.2 增补 `cmd-11`（预计 +5 min，仍在节点预算内）——**该增补是 plan 的可选项，不属 SDD 未批准能力**。

## 6. 两张稳定表（契约必填节，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 `_context.md` 活跃合同退役（AC-1①②③④） | §6 FR-1 四行（multica 两份副本段替换/改写；`workspace-transactions.mjs` `allowed` 删条目+注释；`crctl.test.mjs` 既有测试原位退役）+ §4.4 漂移判定 + dep-10/dep-12/dep-22 | CR-2026-063-TASK-03（关联 CR-2026-063-TASK-04 的两份部署副本文本面） | cmd-01（③④ 的运行时行为：退役测试断言 `post-review-path-drift` + `_context2.md` 拒绝）；cmd-06（①② 文本归零） | RU2（代码面）／RU1（仅文本面） |
| FR-2 活跃引用全量核对（AC-2） | §6 FR-2 + §4.5 检索算法（计入/排除集合、检索命令、命中清单；不做语义机械化） | CR-2026-063-TASK-03 | cmd-06（计入集合 0 命中的机械面）；排除集合的逐条语义判定为人工判据（SDD §4.5「判定与证据要求」，命中清单随 test-report 分析段交付） | RU2 |
| FR-3 Prompt 事实源归位（`CUSTOM.md#75`）（AC-3） | §6 FR-3（第 3 列单元格原位重写、五要素；表结构不变） | CR-2026-063-TASK-04 | cmd-07（五要素字面 + 行数不变）；cmd-09（multica diff 仅 4 文件） | RU1 |
| FR-4 矩阵与索引零改动（AC-4） | §6 FR-4 + §9 `zero_diff`（三处反向验收对象） | CR-2026-063-TASK-04 | cmd-03（`check-agents-contract` + `check-skill-matrix` 读真实文件：9 agent、coordinator system actor 声明在位）；cmd-09／cmd-10（三个文件不出现在 diff 清单） | RU1 |
| FR-5 coordinator overlay 三节原位替换（AC-5） | §6 FR-5（三节正文原位替换；保留四节 + frontmatter；不整文件重写） | CR-2026-063-TASK-04 | cmd-07（七节结构/顺序、四节与 frontmatter 在位、三节关键词、全文无 `crctl advance`/`git` 可复制推进命令）；cmd-09 | RU1 |
| FR-6 公共 dev-agent 委派合同（AC-6） | §6 FR-6（六条要求；不新增 R14；文本纪律） | CR-2026-063-TASK-04 | cmd-08（六条关键词 + `R14` 缺席）；cmd-04（R12/R13 零 finding）；cmd-03 | RU1 |
| FR-7 `gate --mode pre-review` 错配可操作化（AC-7） | §3.1 错误体契约 + §3.1.1 `contractDrift` 定位 + §4.1.1 `crIdForRecover` + §4.1.2 判定树 + dep-1 | CR-2026-063-TASK-01 | cmd-01（`error.code=BAD_ARGS` + `contractDrift===true` + 固定形态 `recoverCommand` + 零写入 + `--for requirement-reviewing` 既有路径不变） | RU4 |
| FR-8 版本化 Prompt 的配对 lint（AC-8） | §3.4-A 判定契约 + §4.3 算法（R7 内新增子判据、不新增规则编号、豁免机制不变） | CR-2026-063-TASK-01 | cmd-02（R7 正负向量 + 既有三类 R7 向量不回归）；cmd-04（真实仓库零 finding） | RU4 |
| FR-9 `review-loop reset` 原子提交（AC-9①–⑥） | §3.2 命令契约 + §3.3 write-set 前置条件 + §4.2.1 时序 + §4.2.2 崩溃窗口真值表 + dep-2/dep-8/dep-9/dep-13/dep-14 | CR-2026-063-TASK-02 | cmd-01（成功路径已提交+clean、W1/W2/W3、单文件 write-set 接受/空集拒绝、恢复串无 `reason`、三条既有拒绝不变）；cmd-05（既有 4 调用点事务测试零行为差异） | RU3 |
| FR-10 `review-record` payload 的 YAML 子集边界（AC-10） | §6 FR-10（5 处原位补写；`yaml-subset.mjs` 零改动；示例结构不变） | CR-2026-063-TASK-04 | cmd-08（5 处均含「单行标量」与「多行引号标量或折叠块」）；cmd-04（零新 finding）；cmd-10（`yaml-subset.mjs` 零 diff） | RU1 |
| FR-11 零新增与不修改边界（AC-11） | §6 FR-11 + §9 `scope_in`/`scope_out`/`zero_diff` | CR-2026-063-TASK-04 | cmd-10（tools diff 白名单 + `zero_diff` 文件不出现）；cmd-09（multica 恰 4 文件）；cmd-03（静态契约族） | RU1 |

**表注（防假绿）**：①FR-2 的「验收证据」只接机械面（计入集合 0 命中）；排除集合的语义判定（每处命中须读作「拒绝 `_context.md`」）按 SDD §4.5 为**人工逐条 + 命中清单证据**，机械化属 S-5 的范围外项（新 lint/新规则不在本 CR）。②FR-1 的 ③④ 行为面（`post-review-path-drift` 拒绝）由 cmd-01 承载，①② 文本面由 cmd-06 承载。③FR-5 的「逐字等于来源 §3.3.1/3.3.2/3.3.3」中，**来源权威定位在 SDD 侧缺写入（§8 U-5）**；cmd-07 只覆盖结构、关键词语义面与「无步骤复述判据」，逐字比对为评审/审批判据（TASK-04 验收条件）。④FR-3 的「其它行文字零 diff」由 cmd-09（文件级）+ 评审侧 `crctl git diff -U0` 辅助判定承载（SDD §6.1 AC-3 可达性列口径）。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["--test","--test-reporter=dot","--test-skip-pattern","CR-2026-037 Prompt|TASK-06 ⑤|已知 Skill 越界文本零命中","skills/shared/crctl/scripts/test/crctl.test.mjs","skills/shared/crctl/scripts/test/durable-tx.test.mjs"]` | 1500 |
| cmd-02 | tools | . | node | `["--test","--test-reporter=dot","skills/shared/crctl/scripts/test/lint-prompts.test.mjs"]` | 300 |
| cmd-03 | tools | . | node | `["--test","--test-reporter=dot","skills/shared/crctl/scripts/test/contract-scan.test.mjs","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs","skills/shared/crctl/scripts/test/check-agents-contract.test.mjs","skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs"]` | 600 |
| cmd-04 | tools | . | node | `["skills/shared/crctl/scripts/lint-prompts.mjs","--mode","enforce"]` | 300 |
| cmd-05 | tools | . | node | `["--test","--test-reporter=dot","--test-skip-pattern","checkpoint T05 contract|TASK-01 RED-7","skills/shared/crctl/scripts/test/version-set.test.mjs","skills/shared/crctl/scripts/test/writeback-tx.test.mjs","skills/shared/crctl/scripts/test/register-tx.test.mjs","skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs","skills/shared/crctl/scripts/test/merge-tx.test.mjs","skills/shared/crctl/scripts/test/archive-tx.test.mjs"]` | 1500 |
| cmd-06 | tools | . | node | `["-e","<AC-2 检索脚本，见下 §6.2-A>"]` | 300 |
| cmd-07 | multica | . | node | `["-e","<multica Prompt 文本合同断言脚本，见下 §6.2-B>"]` | 300 |
| cmd-08 | tools | . | node | `["-e","<tools Prompt/文档 文本合同断言脚本，见下 §6.2-C>"]` | 300 |
| cmd-09 | multica | . | node | `["skills/shared/crctl/scripts/crctl.mjs","git","diff","--name-only","5fde81c1f463e7031663ef8111ee0b7ce39aac3c","--cwd","<resources[].multica.worktreePath>","--workspace","<resources[].ai-first-platform-docs.worktreePath>"]` | 300 |
| cmd-10 | tools | . | node | `["skills/shared/crctl/scripts/crctl.mjs","git","diff","--name-only","ebdd6290f1523ffb682609b7ad6ab83e7d30245e","--cwd","<resources[].tools.worktreePath>","--workspace","<resources[].ai-first-platform-docs.worktreePath>"]` | 300 |

- `cmd-NN` = 机器区 `commands` 的 1-based 下标（两位十进制），与 `test-evidence/cmd-NN.log` 全等，且与 §6.1/§7 的「验收证据」列全等；`args` 为 JSON token 数组（`spawnSync(executable, args, {shell:false})`），无 shell 字符串、无 pipe/redirect、无 env、`cwd` 为对应 repo CR worktree 内相对路径。
- **args 列的转义口径**：`args` 一律按**字面值**书写——正则里的 `|`（cmd-01/cmd-05 的 `--test-skip-pattern`）**不做 Markdown 表格转义**，转录入 `cr-test-plan/v1` 时也按字面 `|` 落盘（与 CR-2026-061 的 `-run` 正则同惯例），不得写成 `\|`。
- **cmd-09 / cmd-10 的 `repo` 列**：命令本体由 tools 仓的 crctl 执行（`executable=node`，args 首 token 指向 tools worktree 内的脚本），`--cwd` 指向被测仓 —— cmd-09 的被测仓是 multica、cmd-10 是 tools；`sourceRevision` 由 `crctl test` 按 `repo` 列绑定 tools HEAD，被核对清单的权威锚点是 args 中的基线 SHA（multica `5fde81c1…` / tools `ebdd6290…`）。判定（清单 ∈ PRD §1.3.1 白名单、`zero_diff` 文件零出现）为 TASK-04 完成标志与 test-report/review-code 的核对动作 —— 该命令只提供**文件级**清单，不证明内容正确性（FR-3/FR-5/FR-6/FR-10 的内容面由 cmd-07/cmd-08 承载）。
- **`--test-reporter=dot` 强制**：`write-test-report` 的 `skipped` 判定模式表会把 node 默认 spec reporter 摘要里的 `skipped` 字样误判为 skip（CR-2026-057 FR-16），故全套命令统一 dot。
- `<resources[].*.worktreePath>` / `<resources[].ai-first-platform-docs.worktreePath>` 占位在 `write-test-report` 转录 `cr-test-plan/v1` 时从 `execution_context.resources` 解析为绝对路径，**不硬编码、不拼接、不回退主工作区**。

#### §6.2-A `cmd-06` 脚本（AC-2 计入集合检索，机械面）

断言：`tools` 的 `agents/`、`skills/`、`pipeline-templates/`（排除 `skills/shared/crctl/scripts/test/**`、`.git`、`node_modules`）与 `multica` 的 `cr-prompts-revised/` 全文件中，字面量 `_context.md` 命中数 = 0；有命中则打印 `路径:行号: 行内容` 并 exit 1。行号按逐行字面检索（不跨行正则、不做语义分类），排除集合 `scripts/test/**` **不在本命令扫描面内**（其命中按 SDD §4.5 人工逐条核对）。

```js
const fs=require('fs'),path=require('path');
const targets=[['<resources[].tools.worktreePath>',['agents','skills','pipeline-templates']],['<resources[].multica.worktreePath>',['cr-prompts-revised']]];
const hits=[];
function walk(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);const n=p.split(path.sep).join('/');if(e.isDirectory()){if(n.includes('skills/shared/crctl/scripts/test')||e.name==='.git'||e.name==='node_modules')continue;walk(p);}else{const lines=fs.readFileSync(p,'utf8').split(String.fromCharCode(10));for(let i=0;i<lines.length;i++){if(lines[i].includes('_context.md'))hits.push(n+':'+(i+1)+': '+lines[i].trim());}}}}
for(const t of targets){for(const s of t[1]){walk(path.join(t[0],s));}}
if(hits.length){console.log('AC-2 accounted-set hits = '+hits.length);hits.forEach(h=>console.log(h));process.exit(1);}
console.log('AC-2 accounted-set hits = 0');
```

#### §6.2-B `cmd-07` 脚本（multica Prompt 文本合同断言）

断言（逐条对应 SDD §6.1 AC-1①/②、AC-3、AC-5 的**机器可判面**；文案语义与来源逐字对应仍为评审判据）。AC-5 的「无步骤复述」判据取**可复制推进命令形态**（`--trigger` / `--expect` / `crctl approve --stage` / `git commit` / `git push`）：SDD §6.1 明列 `## 平台层权限` 的禁止清单与 `## 评审闭环` 的 alignment 责任边界按 FR-5 保留原文，其中保留的 `crctl advance` 文字不属新文本、不纳入本判据：

1. `cr-prompts-revised/dev-agent.md`：无 `_context.md`；含 `crctl status`、`crctl next`、`cr.md`、`review-loop.yml`、`review annotations`（FR-1① 的 canonical resume 口径）。
2. `cr-prompts-revised/quality-reviewer-agent.md`：无 `_context.md`；含 `dir-graph.yaml`、`crctl status`、`canonical`（FR-1② 证据面改写）。
3. `cr-prompts-revised/cr-coordinator-agent.md`：`## ` 级标题集合与顺序 = 〔职责、事实源与读取、路由、委派与评论、评审闭环、平台层权限、失败与输出〕；frontmatter 分隔符恰 2 个 `---`；「委派与评论」含 `Runner`、`canonical`、`原样值`、`squad activity`；「评审闭环」含 `repair-target`、`reviewLoop`、`reviewer`；「失败与输出」含 `CONTRACT_DRIFT`；全文不含可复制推进命令形态 `--trigger`、`--expect`、`crctl approve --stage`、`git commit`、`git push`（AC-5「无步骤复述」判据 —— **保留段不计入**：`## 平台层权限` 的禁止清单与 `## 评审闭环` 的 alignment 责任边界按 FR-5 明文保留原文，其中出现的 `crctl advance` 不属本判据）。
4. `CUSTOM.md`：总行数 = 492（表结构不变、不新增行；按去除尾换行后的行数计，基线实测 `split(String.fromCharCode(10)).length = 493`，末元素为空串）；含 `| 75 |` 的行同时含 `tools/agents/`、`overlay`、`coordinator`、`投影`、`_index.yml`（AC-3 五要素字面面）。

```js
const fs=require('fs'),path=require('path');
const M='<resources[].multica.worktreePath>';
const NL=String.fromCharCode(10);
const bad=[];
const read=(...p)=>fs.readFileSync(path.join(M,...p),'utf8');
const need=(t,name,...ks)=>{for(const k of ks){if(!t.includes(k))bad.push(name+' 缺少「'+k+'」');}};
const forbid=(t,name,...ks)=>{for(const k of ks){if(t.includes(k))bad.push(name+' 不应出现「'+k+'」');}};
const dev=read('cr-prompts-revised','dev-agent.md');
forbid(dev,'dev-agent.md','_context.md');
need(dev,'dev-agent.md','crctl status','crctl next','cr.md','review-loop.yml','review annotations');
const rev=read('cr-prompts-revised','quality-reviewer-agent.md');
forbid(rev,'quality-reviewer-agent.md','_context.md');
need(rev,'quality-reviewer-agent.md','dir-graph.yaml','crctl status','canonical');
const coo=read('cr-prompts-revised','cr-coordinator-agent.md');
const want=['## 职责','## 事实源与读取','## 路由','## 委派与评论','## 评审闭环','## 平台层权限','## 失败与输出'];
const got=coo.split(NL).filter(l=>l.slice(0,3)==='## ').map(l=>l.trim());
if(JSON.stringify(got)!==JSON.stringify(want))bad.push('coordinator 章节集合或顺序不符: '+JSON.stringify(got));
if(coo.split('---').length-1<2)bad.push('coordinator 缺少 frontmatter 分隔符');
const sect=(h)=>{const i=coo.indexOf(h);const j=coo.indexOf(NL+'## ',i+1);return coo.slice(i,j<0?coo.length:j);};
need(sect('## 委派与评论'),'委派与评论','Runner','canonical','原样值','squad activity');
need(sect('## 评审闭环'),'评审闭环','repair-target','reviewLoop','reviewer');
need(sect('## 失败与输出'),'失败与输出','CONTRACT_DRIFT');
forbid(coo,'cr-coordinator-agent.md','--trigger','--expect','crctl approve --stage','git commit','git push');
const cus=read('CUSTOM.md');
const cusLines=cus.split(NL);
const nLines=cusLines[cusLines.length-1]===''?cusLines.length-1:cusLines.length;
if(nLines!==492)bad.push('CUSTOM.md 行数 = '+nLines+'（期望 492，不得新增行）');
const row=cusLines.filter(l=>l.indexOf('| 75 |')===0);
if(row.length!==1)bad.push('CUSTOM.md #75 行匹配数 = '+row.length);
else need(row[0],'CUSTOM.md#75','tools/agents/','overlay','coordinator','投影','_index.yml');
if(bad.length){console.log('multica text-contract failures = '+bad.length);bad.forEach(b=>console.log(b));process.exit(1);}
console.log('multica text-contract failures = 0');
```

#### §6.2-C `cmd-08` 脚本（tools Prompt/文档 文本合同断言 + R14 缺席）

断言（逐条对应 SDD §6.1 AC-6 六条要求、AC-10 五处补写、AC-6 的「不新增 R14」）：`agents/dev-agent.md` 的 `## 委派路由合同（评审）` 节含 `task/run`、`Runner`、`canonical`、`BAD_ARGS`、`CONTRACT_DRIFT`、`advance`，且保留 `自评`、`来源`、`独立会话` 三项既有内容；`skills/shared/crctl/scripts/lint-prompts.mjs` 全文不含 `R14`；5 处文档（`skills/shared/crctl/SKILL.md`、`skills/requirement/review-requirement/SKILL.md`、`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/develop/review-code/SKILL.md`）均含 `单行标量` 与 `多行引号标量`。

```js
const fs=require('fs'),path=require('path');
const T='<resources[].tools.worktreePath>';
const NL=String.fromCharCode(10);
const bad=[];
const read=(...p)=>fs.readFileSync(path.join(T,...p),'utf8');
const need=(t,name,...ks)=>{for(const k of ks){if(!t.includes(k))bad.push(name+' 缺少「'+k+'」');}};
const dev=read('agents','dev-agent.md');
const i=dev.indexOf('## 委派路由合同（评审）');
if(i<0){bad.push('dev-agent.md 缺少委派合同节');}
else{const j=dev.indexOf(NL+'## ',i+1);const s=dev.slice(i,j<0?dev.length:j);
need(s,'dev-agent.md 委派合同','task/run','Runner','canonical','BAD_ARGS','CONTRACT_DRIFT','advance','自评','来源','独立会话');}
const lint=read('skills','shared','crctl','scripts','lint-prompts.mjs');
if(lint.includes('R14'))bad.push('lint-prompts.mjs 出现 R14（不得新增规则编号）');
const sites=[['skills','shared','crctl','SKILL.md'],['skills','requirement','review-requirement','SKILL.md'],['skills','develop','review-tech-design','SKILL.md'],['skills','develop','review-dev-plan','SKILL.md'],['skills','develop','review-code','SKILL.md']];
for(const s of sites){const t=read(...s);need(t,s.join('/'),'单行标量','多行引号标量');}
if(bad.length){console.log('tools text-contract failures = '+bad.length);bad.forEach(b=>console.log(b));process.exit(1);}
console.log('tools text-contract failures = 0');
```

## 7. AC/业务闭环覆盖矩阵（契约必填节，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 四处原位修订全部落地（含 ③ 白名单删除后的 `post-review-path-drift` 拒绝） | §6 FR-1 + §4.4 + §6.1 AC-1 | CR-2026-063-TASK-03 | cmd-01；cmd-06 |
| 业务闭环：AC-1①② 两份 multica 部署副本的 `_context.md` 段替换/改写 | §6 FR-1①② + dep-22 | CR-2026-063-TASK-04 | cmd-06；cmd-07；cmd-09 |
| AC-2 计入集合 0 命中 + 排除集合全为拒绝语义（含检索命令与命中清单证据） | §4.5 + §6.1 AC-2 | CR-2026-063-TASK-03 | cmd-06（机械面）；命中清单为人工逐条证据（§6.1 表注①） |
| AC-3 `CUSTOM.md#75` 五要素 + 其它行零 diff | §6 FR-3 + §6.1 AC-3 | CR-2026-063-TASK-04 | cmd-07；cmd-09 |
| AC-4 三处反向验收对象零改动（含 `_index.yml` 仍 9 agent） | §6 FR-4 + §9 `zero_diff` | CR-2026-063-TASK-04 | cmd-03；cmd-09；cmd-10 |
| AC-5 coordinator 三节逐条对应来源文本、四节 + frontmatter 原样、无步骤复述 | §6 FR-5 + §6.1 AC-5（判据：新文本不含可复制推进命令） | CR-2026-063-TASK-04 | cmd-07；cmd-09（逐字对应面见 §8 U-5） |
| AC-6 六条要求齐备 + 无 R14 或等价委派 lint | §6 FR-6 + dep-15/dep-20 | CR-2026-063-TASK-04 | cmd-08；cmd-03；cmd-04 |
| AC-7 `gate --mode pre-review` 错配：退出码非 0 + `BAD_ARGS` + `contractDrift===true` + 固定恢复串 + 零写入 + 既有路径不变 | §3.1/§3.1.1/§4.1 + §6.1 AC-7 | CR-2026-063-TASK-01 | cmd-01 |
| AC-8 R7 配对向量正负 + 既有 R7 向量不回归 + 无新增规则编号 | §3.4-A/§4.3 + §6.1 AC-8 | CR-2026-063-TASK-01 | cmd-02；cmd-04 |
| AC-9 reset 成功已提交且 clean / W1·W2 回滚无残留 / 恢复串无 `reason` / 三条既有拒绝不变 / cycle 语义不变 / 单文件 write-set 成立 | §3.2/§3.3/§4.2 + §6.1 AC-9 | CR-2026-063-TASK-02 | cmd-01；cmd-05 |
| AC-10 5 处补写 + `yaml-subset.mjs` 零 diff + 示例结构不变 | §6 FR-10 + §6.1 AC-10 | CR-2026-063-TASK-04 | cmd-08；cmd-04；cmd-10 |
| AC-11 零新增与 `zero_diff` 边界 | §6 FR-11 + §9 | CR-2026-063-TASK-04 | cmd-09；cmd-10；cmd-03 |
| AC-12 既有测试不回归（相对 §5.3 登记集合）+ multica 被改文件结构完好 | §6.1 AC-12 + §5.3 例外登记 | CR-2026-063-TASK-04 | cmd-01；cmd-02；cmd-03；cmd-05 |

> **关键 AC 唯一 owner 说明（机械可判）**：
> - **AC-7 / AC-8 唯一 owner = CR-2026-063-TASK-01**（产生该结果的层：`cmdGate` 错配分支与 `lint-prompts` R7 子判据所在的 TASK；证据 cmd-01/cmd-02，辅助 cmd-04）。
> - **AC-9 唯一 owner = CR-2026-063-TASK-02**（`cmdReviewLoopReset` + `lib/durable-tx.mjs` 的实际产生层；证据 cmd-01 主、cmd-05 回归网）。
> - **AC-1 / AC-2 唯一 owner = CR-2026-063-TASK-03**（③④ 的运行时行为与实际产生层：`allowed` 集合删除 + 退役测试；①② 为业务闭环行，归 TASK-04）。
> - **AC-3 / AC-4 / AC-5 / AC-6 / AC-10 / AC-11 / AC-12 唯一 owner = CR-2026-063-TASK-04**（文本层 + 收口层：Prompt/文档落盘、反向验收与交付 diff 白名单核对、全量回归执行面）。
> - 业务闭环行与关键 AC 行的证据面不重叠或可分别机械核验（cmd-NN 分属）。

## 8. 本轮技术设计评审 carry-over：5 条 suggestion 的逐条落点判定 + 上游设计修订项

`review-annotations/sdd.yml`（canonical）的 5 条 suggestion 全部归 `write-tech-design`，且在**已审批** SDD 上恒为 `sdd.md` 正文事实。协调者要求：逐条写明「由哪条 TASK 承载 / 是否需要修订 `sdd.md` 正文」，并**不得在 plan/TASK 里静默改写设计**。判定如下。

### 8.1 逐条落点判定表

| Suggestion | 是否需改 `sdd.md` 正文 | 由哪条 TASK 承载（部分/否） | 理由（一句话） |
|---|---|---|---|
| **S-1** `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED` 在 §3.2 / §3.5 / D-2 声明但 §4.2.1 步骤 13 无产生点 | **是**（U-1） | **否**——契约/算法择一前无法实现 | 取①（补 try/catch 产生路径）则 §4.2.1 步骤 13 与错误闭包需改写；取②（删码）则 §3.2/§3.5/D-2 三处需删除。两条都改变已审批契约或算法，plan/TASK 自行择一即「实现偏离已审批 SDD」 |
| **S-2** commit 前缺「index 恰等于 write-set」前置断言（§4.2 步骤 11–12） | **是**（U-2） | **部分**：CR-2026-063-TASK-02 按 FR-9 第 4 条（commit 只含 `review-loop.yml`）实现 staged 复核，落点 SDD §4.2 步骤 12 需明文 | FR-9 第 4 条已批准「commit 只包含该文件」，但 SDD 算法未写明保证手段；镜像 `owner-set`（L2541–2543）/`version-set`（L2832–2833）先例属 SDD 侧择定 |
| **S-3** 既有成功路径用例用非 git 夹具（`crctl.test.mjs:3430–3452`），改造后必红；dep-14/AC-9⑤ 口径失实 | **是**（U-3） | **部分**：CR-2026-063-TASK-02 迁移夹具（in-scope 测试文件内的必要实现，断言不变），dep-14 结论与 AC-9⑤ 夹具说明需 SDD 侧改写 | 不迁移则 AC-9⑤/AC-12 在该用例上不可达；但 SDD dep-14 现写「既有断言基线必须继续通过」，与实况冲突，属 SDD 事实条目错误 |
| **S-4** §10 清单缺 2 条既有实现锚点（archive CR-ID 正则、`TX_GIT_FAILED`），违反 §0「引用一律 dep-N」 | **是**（U-4） | **否**——纯 §10 清单/正文标注补条 | 无 TASK 能改 SDD 第 10 节；不补条则 §0 的单一定义约定在已审批文档内自相矛盾 |
| **S-5** FR-5 三节目标文本缺权威路径 + SHA + 「逐字复制、不得转述」口径 | **是**（U-5） | **部分**：CR-2026-063-TASK-04 按「逐字复制、不得转述」实现（工作来源见 U-5），权威锚点需 SDD 钉定 | §6 FR-5 给的是摘要式目标内容；AC-5 要求等于来源 §3.3.1/3.3.2/3.3.3 文本，而该来源不在任何 worktree 内，逐字校验需要一个仓内可复现的权威锚点 |
| （本轮新增事实，非评审 suggestion）**AC-12「全量既有测试通过」在基线不可达** | **是（口径澄清）**（U-6） | **否**——plan §5.3 已按 CR-2026-060 先例承载可执行口径，SDD 侧只需一句澄清 | `../tools` 基线实测 5 条既有红（§5.3），AC-12 的字面口径与实况冲突；plan 侧已可执行，是否需 SDD 明文由 reviewer 判定 |

### 8.2 上游设计修订项（plan/TASK 不承载，交 `write-tech-design` 修正 SDD 正文）

> 本节逐条给「结论 + 理由 + SDD 落点」。**plan/TASK 不实现这些修订**；`review-dev-plan` 判定 `repair-target=write-tech-design` 时按既有 upstream 轨（`review-dev-plan:upstream-design-blocker`）回 `tech-design-review-pending`，SDD 修订后重跑 `review-tech-design` + 人工审批，再由本节点按新 SDD 刷新 plan/TASK。

- **U-1（S-1）`reset` 回滚失败码的产生路径**
  - 结论：SDD 需二择一并写明——① 给 §4.2.1 步骤 13 的 `abortLedgerTransaction` + `syncLedgerIndex` 加 try/catch，镜像 `rollbackOwnerWrite`（`crctl.mjs` L2471–2484）/`rollbackVersionWrite`（L2725–2738），命中时 `fail('REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED', …, { affected: [rel] })` 并说明是否写审计；或 ② 从 §3.2 / §3.5 / §5.2 D-2 删除该码。
  - 理由：三处声明（契约、错误闭包、决策）与 §4.2.1 算法不一致——步骤 13 只有 `REVIEW_LOOP_RESET_COMMIT_FAILED` 一个 `fail`，`abort`/`syncLedgerIndex` 经 `runTxAsync` 抛出会转成 `TX_*` 码；两条既有先例均为 try/catch + op-scoped 码，故 ① 与既有族同构、成本最低（reviewer 原文判定）。
  - SDD 落点：§4.2.1 步骤 13（择一后重写该段伪代码）+ §3.2「失败输出（回滚未完成）」行 + §3.5 四查错误闭包行 + §5.2 D-2。
- **U-2（S-2）commit 前的 index 前置断言**
  - 结论：SDD §4.2.1 步骤 12 需显式写明「commit 前断言 unstaged 为空且 staged 恰等于 write-set」，镜像 `owner-set`（L2541–2543）/`version-set`（L2832–2833）。
  - 理由：`git commit` 无 pathspec，提交的是整个 index；仅 add 侧保证不足以防「执行前已有其它暂存变更」，与 FR-9 第 4 条、FR-11/AC-11 的零无关改动口径冲突；两种先例并存，实现期若不自择一将随先例分叉。
  - SDD 落点：§4.2.1 步骤 12（补前置断言）+ §3.2「成功副作用」行（口径联动）。
  - plan 侧处置：TASK-02 的 `reset` 实现按 FR-9 第 4 条**必须**保证「commit 只含 `review-loop.yml`」，其实现手段（staged 复核）落在 TASK-02「实现要点」；SDD 侧明文由 U-2 承接。
- **U-3（S-3）既有用例夹具迁移的 SDD 口径**
  - 结论：SDD dep-14 的「既有断言基线必须继续通过」需改写为「既有用例迁移到 git 夹具（`makeGitWorkspace()`），断言内容不变」，并同步 §6.1 AC-9⑤ 的夹具说明。
  - 理由：既有成功路径用例（`crctl.test.mjs:3430–3452` 耗尽态 `cycle+1`）用非 git 的 `makeWorkspace()`；改造后 `reset` 必做 add/commit，该用例会走失败分支返回 exit 1，与 NFR-1/AC-12 的「既有测试全绿」不可达。
  - SDD 落点：§10 dep-14 依赖结论 + §6.1 AC-9 可达性列（⑤ 夹具说明）。
  - plan 侧处置：TASK-02 承载夹具迁移（该文件在 SDD §9 `scope_in` 与 PRD §1.3.1 第 14 行内），断言不变。
- **U-4（S-4）§10 依赖清单补 2 条锚点**
  - 结论：§10 补条（或在正文标注 dep-N）：① archive CR-ID 正则校验形态（`crctl.mjs:3513`、`workspace-transactions.mjs:3453`）；② `TX_GIT_FAILED`（来自 `syncLedgerIndex`，`crctl.mjs:688`）。
  - 理由：§0 声明「正文对既有实现的引用一律以 dep-N 指向第 10 节」；现状 §5.3 D-3 与 §3.5/§5.2 各有一处引用不在清单内，违反已审批文档自身的单一定义约定。
  - SDD 落点：§10（新增 2 条 dep-N，正文对应处标注）。plan/TASK 侧无改动。
- **U-5（S-5）FR-5 三节目标文本的权威锚点与逐字口径**
  - 结论：SDD 需写明权威路径 + SHA 与「逐字复制、不得转述」（与 FR-1① 给整段原文的口径对齐），并给出实现者与评审者都可复现的锚点（例如把来源 §3.3.1/3.3.2/3.3.3 的逐字文本或内容哈希钉进 SDD）。
  - 理由：来源文档不在本 CR 任何 worktree 内（权威副本 = Issue AIFI-24 附件；主 checkout `docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md`，24585 B、SHA256 `b774e41d…`，且在 KB 仓为 **untracked**，见 PRD §1.4 事实 1）。实现者无法从仓内复现逐字文本，评审者亦无仓内锚点校验「等于来源 §3.3.x」→ AC-5 的逐字面不可机械验证（cmd-07 只覆盖结构/关键词/无步骤复述面）。
  - SDD 落点：§3.4-B「Prompt 文本契约」+ §6 FR-5「目标内容」+（如钉哈希）§10。
  - plan 侧处置：TASK-04 按「逐字复制、不得转述」实现，工作来源写为「Issue AIFI-24 附件（与主 checkout 同名副本归一后逐字节一致，24585 B、SHA256 `b774e41d…`，PRD §1.4 事实 1）」；最终锚点以 SDD 修订结果为准。
- **U-6（本轮新增事实）AC-12 的字面口径与基线实况**
  - 结论：建议 SDD 在 §6.1 AC-12（或 §9/§1.4 基线事实）补一句：**「全量既有测试」的判据 = 失败集 ⊆ 已登记基线红集合（本 CR 为 5 条，见本 plan §5.3），且不得新增红**。
  - 理由：在未改动的 tools 基线 `ebdd6290…` 上实测 `../tools` 既有测试有 5 条红（§5.3 逐条列明文件名/测试名/失败断言），其中 2 条（BR-1/BR-5）由 CR-2026-060 §5.3 已登记，另 3 条（BR-2/BR-3/BR-4）为本轮实测新增记录；全部与本次改动面无关，且本 CR 的 `zero_diff` 明确不改其根因文件（`pipeline-templates/**`、`dir-graph.yaml`、`write-requirement-prd/SKILL.md`、checkpoint/archive 内核）。故 AC-12 的字面读法（「全量既有测试通过」）不可达。
  - SDD 落点：§6.1 AC-12 行（补判据）+（可选）§9 `follow_up` 登记 3 条新基线红的根因修复归属。
  - plan 侧处置：已按 CR-2026-060 §5.3 先例以「基线红例外登记表」承载可执行口径（§5.3），证据命令用精确 `--test-skip-pattern` 且 fail-closed；**是否需要 SDD 侧明文由 reviewer 判定**，plan 侧不阻塞。

### 8.3 与上游轨的关系（本节点的输出边界）

- 本节点不修改 `sdd.md`（哈希被 `sdd.yml#subject-sha256` + 架构审批 evidence 双重绑定），不修改 `prd.md`（审批绑定 `9247c107…`），不自行调用 `crctl advance` 到 `tech-design-review-pending`。
- `review-dev-plan` 若判 `verdict=block` 且 `repair-target=write-tech-design`：按节点契约 `crctl advance --to tech-design-review-pending --trigger review-dev-plan:upstream-design-blocker --expect task-breakdown --embedded`，并由协调者派回 `write-tech-design`；SDD 修订 + 重跑 `review-tech-design` + 人工二次审批后，本节点按新 SDD 刷新 plan/TASK。
- 若 `review-dev-plan` 判 `verdict=block` 且 `repair-target=write-dev-plan`（普通轨）：按 `write-dev-plan` Step 2a / `write-dev-tasks` Step 2a 回修本 plan/TASK（≤3 轮），**不动 SDD 正文、不扩大 `scope_out`**。
- 本轮技术设计评审的 S-6/S-7（需求评审第二轮 carry-over）已由 SDD §12 落 SDD 事实，无需本计划另行处置。

## 9. TASK 拆分预分配（write-dev-tasks 的输入，共 4 个，组映射 1:1）

| 变更组 | 覆盖 FR | TASK id | 仓库 | 粒度 | 依赖 |
|---|---|---|---|---|---|
| G2 `gate` 错配可操作化与配对 lint | FR-7、FR-8 | CR-2026-063-TASK-01 | tools | 1.5 天（12h） | — |
| G3 `review-loop reset` 原子提交 | FR-9 | CR-2026-063-TASK-02 | tools | 2 天（16h） | TASK-01（消费 `crIdForRecover`） |
| G1 `_context.md` 合同退役与活跃引用核对 | FR-1③④、FR-2 | CR-2026-063-TASK-03 | tools | 1 天（8h） | — |
| G4 Prompt/文档归位、委派合同与范围收口 | FR-1①②、FR-3、FR-4、FR-5、FR-6、FR-10、FR-11 | CR-2026-063-TASK-04 | multica + tools | 2 天（16h） | TASK-01、TASK-02、TASK-03 |

- 每个 in-scope FR 恰出现一次于 §6.1 交付覆盖表，主责 TASK 唯一（关联 TASK 不改变主责）。
- `task_count_hint = 4`（= 上表组数 = `tasks/_index.yml` 的 TASK 数）；`totalEstimateHours` 期望 = 52h，与 §5 一致。
- 回滚单元按 §4.0（RU1~RU4，逆拓扑）；TASK 卡的接口契约逐字对齐 SDD（`crIdForRecover` 由 TASK-01 产出、TASK-02 消费，见 SDD §4.1.1；`beginLedgerCommand`/`readFileChecked`/`sha256`/`abortLedgerTransaction`/`syncLedgerIndex` 签名见 SDD §4.2 与 dep-3/dep-8）。
- 交付 TASK 的完成边界全部为 `developing` 内可被 `crctl task done` 登记的事件（实现已落盘 + 证据命令全绿 + 任务账本登记），**无 merge/writeback/archive 前置**（流程控制 TASK 禁止）。
