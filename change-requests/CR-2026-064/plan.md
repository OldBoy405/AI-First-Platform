---
id: CR-2026-064-plan
type: PLAN
cr-ref: CR-2026-064
sdd-ref: "change-requests/CR-2026-064/sdd.md"
target-version: 0.37
status: draft
created: "2026-09-13T22:05:00+08:00"
updated: "2026-09-13T22:05:00+08:00"
---

# CR-2026-064 开发计划（CR-R：结构化恢复合同原子迁移 —— `recoverCommand`/`recover_command` 全量退役为结构化 `recovery`）

> **本版为整体重写（v2），不是对上一版 `c0750ae5` 的增量补丁。**
>
> 上一版建立在一个**已经不存在的前提**上：「基线 5 条红 + 锚定 `--test-skip-pattern` 例外」。该前提已被 CR-2026-065（`tools@81d31b8`）清除：`gate-registry.json#manifest` 的 `exceptions` 已为 `[]`，CI 全量步骤已改为 `node skills/shared/crctl/scripts/test/suite-gate.mjs --run`；SDD 已在 `6c5c9a11` 把 §6.3 AC-07 的可观测结果定为 CI 的两条现有步骤，并由人工审批（`ab6f9347`，`evidence-digest 2d637724…`）绑定为验收目标。
>
> 因此本版：**不再保留任何例外、skip 模式、并发参数或替代验收口径**；`cmd-01` / `cmd-02` 按 SDD §6.3 AC-07 的命令转录（`cmd-02` 的 reporter 转录注记见 §6.2.1）；§5.3 的全部数字在本节点于新基线（tools `81d31b8`、multica `dead9fe0`、KB `ab6f9347`）上**重新实测**，不沿用上一版任何数值。
>
> 上一轮 `review-dev-plan` 判 **BLOCK / UPSTREAM_DESIGN_BLOCKER**（`review-annotations/dev-plan.yml`，`repair-target: write-tech-design`，`subject-sha256 5fe937a1…`）——该 blocker 的唯一残留点（AC-07 的口径与证据命令在合并后 trunk 上失效）已由 SDD 修订闭合，本轮由此计划承接；`dev-plan.yml` 的旧记录在本节点复评时由 `crctl review-record` 原子刷新。

## 0. 基线与工作区事实（落笔实读，一次读，未轮询）

### 0.1 入口校验 `crctl workspace inspect CR-2026-064`（主 workspace，原样透传）

| repo | worktreePath | classification | dirty | localBranch / remoteBranch |
|---|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-064` | **healthy** | false | true / true |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-064` | **healthy** | false | true / true |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-064` | **healthy** | false | true / true |

`changed: false`；`operationalWorkspace = "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\knowledge-base\\requirement\\CR-2026-064"`（非空）；`operationalWorkspaceError: null`。三仓全 healthy，入口条件满足。

### 0.2 三仓 HEAD（本计划落笔时刻）与职责

| repo | HEAD | 职责与代码事实绑定 |
|---|---|---|
| `ai-first-platform-docs` | `ab6f9347`（`[cr] approve CR-2026-064 tech-design approval+status -> tech-design-reviewed`） | 只承载本 CR 过程文档（plan / tasks / test-report / 证据）；**不写** `specs/`、`delivery/`、`docs/`（回写属 `feature-writeback`） |
| `multica` | `dead9fe0d5a24118547a5be56d59241fdcc443a8`（`merge CR-2026-065: multica`） | 只改 `cr-prompts-revised/delivery-agent.md`（2 行 / 2 次旧字段命中）；`server/internal/governance/testdata/traceability-golden.{yml,json}` 为历史黄金数据（排除，不改） |
| `tools` | `81d31b8b9d4c36cfef24cd076bf9fe635b67b2b6`（`merge CR-2026-065: tools`） | 本 CR **唯一代码变更仓**；§5.3 扫描面/门禁/守卫数字、§8 盘点、`cmd-01`/`cmd-03`/`cmd-05` 的 diff 基线均绑此 SHA（`git status` clean） |

### 0.3 输入产物与绑定

| 输入 | 版本 | SHA256 | 绑定事实 |
|---|---|---|---|
| `change-requests/CR-2026-064/sdd.md` | commit `6c5c9a11`（91780 B，纯 LF：CRLF 计数 0） | `d9f727b6bb7d6d87f5449ccadbcbc986695e642d77c282f1d39b603d385a621b` | `review-annotations/sdd.yml`：`verdict: pass`、`blockers: []`、cycle 3 / attempt 1、`subject-sha256` 与本行逐字一致（评审 commit `a73f95b6`）+ `approval.yml#tech-design`（approver `OldBoy405`，`2026-09-13T21:37:13+08:00`，via `crctl-approve`，`target-status: tech-design-reviewed`，`evidence-digest 2d63772450a4a8dd83f6154050c8b609015625068e03c571fed8efd496bca5ca`） |
| `change-requests/CR-2026-064/prd.md` | commit `c5f90be7`（21507 B，纯 LF） | `4df6f1590e5c04bf2585bfe76bc21a496f702dcea17f2502b0e3584217176457` | 需求评审 PASS（`traceability.yml#reviews.requirement`）+ `approval.yml#requirement`（`evidence-digest 558deb7d…`，target-status `requirement-approved`） |
| CR status / 下一步 | — | — | 本节点入口：status = `tech-design-reviewed`、`gateBlockers: {}`、`crctl next CR-2026-064` = `write-dev-plan`（why：技术设计已审批，编写开发计划） |
| 上一轮评审记录 | `review-annotations/dev-plan.yml` | `subject-sha256 5fe937a16e6b016d570beab9463f7047846d726d77ee16be98849bec1d665ba3` | `verdict: block`、`repair-target: write-tech-design`（upstream 轨，`current-attempt 0`）；本计划重写后由 `review-dev-plan` 的独立 run 重评并原子刷新 |

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 TASK | 估时 |
|---|---|---|---|
| M1 设计冻结 | 需求审批 + SDD `6c5c9a11`（`review-tech-design` cycle 3 attempt 1 `pass`、blockers 0，评审 commit `a73f95b6`）+ 人工架构审批（`ab6f9347`，`evidence-digest 2d637724…`） | 已发生 | 0 |
| M2 计划与任务拆分 | 本 `plan.md`（整体重写）+ `tasks/TASK-01…04.md` 重生成 + `tasks/_index.yml`（`crctl task init --count-hint 4`）+ 推进 `task-breakdown` + 独立 `review-dev-plan` | 流程节点（非交付 TASK） | 0.5 人天 |
| M3 生产者与唯一构造器 | `lib/workspace-transactions.mjs`：新增 `buildRecovery`（约 12 行）+ 9 类场景 9 个生产者站点原位改为结构化 `recovery`；`mergeCr` 内局部名 `checkpointRecoverCommand` 归位 | CR-2026-064-TASK-01 | 16h |
| M4 CLI 投影与错误面 | `crctl.mjs`：`register` 双投影删除（单 `recovery`）、`gate --mode pre-review` 错配分支与 `review-loop reset` 提交失败分支结构化、`cmdRegister` 输出字段改名；`crIdForRecover` 占位符语义删除 | CR-2026-064-TASK-02 | 8h |
| M5 消费方与文档迁移 | 4 份 `tools` SKILL（crctl / cr-archive / push-progress / merge-feature-branch）+ `multica/cr-prompts-revised/delivery-agent.md` + `tools/README.md` 原位改读结构化合同；`openwiki/operations/crctl-transactions.md` 由既有生成步骤（`openwiki` + `openwiki code --update`，与 `openwiki-update.yml` 同源）重新生成并核对（D-7，不手工编辑） | CR-2026-064-TASK-03 | 12h |
| M6 测试迁移与退役保护 | 7 个既有测试文件改为结构与 argv 断言（含 6 类 reason 向量）+ `contract-scan.test.mjs` 扩展 `RETIRED_RECOVERY` / 整树派生扫描面 / 两项精确路径排除 / 八条代表性命中用例 + `shell: true`、`Invoke-Expression` 守卫断言；全部满足 §4.5-7 的「逐用例原位替换、只增不减、不新增该目录测试文件」硬约束 | CR-2026-064-TASK-04 | 16h |
| M7 评审与人工审批 | `review-code` → `approve --stage code`（`review-dev-plan` 通过后先经人工「确认进入代码开发」gate → `approve-dev-start`） | 流程节点 | 流程 |
| M8 发布与回写 | `merge-feature-branch` / `feature-writeback`（`specs/`、`delivery/`）/ `archive`；平台侧 Prompt 部署由 owner 在本 CR 落地后另行执行（不属本 CR，§9 `zero_diff`） | 流程控制节点 | 流程 |

**估算总工时 = 52h（= 6.5 人天）**。与 `crctl task init` 返回的 `totalEstimateHours` 交叉核对（§3 / `write-dev-tasks` Step 4 FR-23）。

## 2. 任务依赖图

```
CR-2026-064-TASK-01  生产者迁移：buildRecovery + 9 个生产者站点（tools/lib/workspace-transactions.mjs）
        │  产出：buildRecovery(args, {cwd, requiresTTY, promptFor}) → Recovery；9 类场景的结构化 recovery
        ▼
CR-2026-064-TASK-02  CLI 投影迁移：register 单投影、gate 错配、reset 失败分支、占位符 helper 删除（tools/crctl.mjs）
        │  消费：TASK-01 的构造器；产出：error.recovery / 顶层 recovery 的投影面
        ▼
CR-2026-064-TASK-03  消费方与文档迁移：4 份 SKILL + README + OpenWiki 生成页 + multica 交付 Agent 提示词
        │  消费：TASK-01/02 的字段与形状（提示词只引用字段名，不引用实现）
        ▼
CR-2026-064-TASK-04  测试迁移与契约退役保护：7 个测试文件 + contract-scan 扩展 + shell 逃逸守卫
           消费：TASK-01/02/03 全部产物（断言对象即前三者的输出与文本）
```

- 依赖为**严格串行单链**（`TASK-04` 亦依赖 `TASK-03`：扫描面覆盖提示词文本）；`depends-on` 字段与上图逐条一致，无环、无悬空引用。
- 同仓单写者：四个 TASK 均落在 `tools`（`TASK-03` 另含 `multica` 的 1 个 prompt 文件），按链路顺序执行，不存在并行写者。
- 变更组映射（`write-dev-tasks` Step 4「写入前组映射 preflight」的输入）：**G1 生产者 + 唯一构造器 → TASK-01；G2 CLI 投影与错误面 → TASK-02；G3 提示词/文档 + OpenWiki 生成 → TASK-03；G4 测试迁移与契约退役保护 → TASK-04**。每组恰一个 TASK、每个 TASK 恰属一组（4 组 ↔ 4 TASK）。

## 3. 资源与分工

| TASK | 估时 | 仓库 | 范围（SDD 落点） |
|---|---|---|---|
| CR-2026-064-TASK-01 | 16h | tools | `lib/workspace-transactions.mjs`：`buildRecovery` + §4.1 站点 1–9 + 局部名归位（单文件、单写者） |
| CR-2026-064-TASK-02 | 8h | tools | `crctl.mjs`：`buildRegisterResult` / `cmdRegister` / `cmdGate` / `cmdReviewLoopReset` / `crIdForRecover` 5 处（§4.2 + §3.3 站点 10/11） |
| CR-2026-064-TASK-03 | 12h | tools + multica | 4 份 `tools` SKILL + `README.md` + `openwiki/operations/crctl-transactions.md`（生成物）+ `multica/cr-prompts-revised/delivery-agent.md` |
| CR-2026-064-TASK-04 | 16h | tools | 7 个既有测试文件 + `contract-scan.test.mjs` 扩展 + `shell: true`/`Invoke-Expression` 守卫断言；受 §4.5-7 用例下限约束 |

分工与审批边界：`cr.md owners.development.id = Ray`（实现与开发期审批）、`owners.test.id = Ray`（测试报告与验证证据）。人工 gate（进入开发 / 代码审批）只能在交互式 TTY 由人执行，本计划不代签、不预置 grant。

## 4. 风险与回滚策略

### 4.0 回滚单元（唯一：整体回滚｜SDD FR-15 / AC-13）

**RU-ALL = 整体回滚本 CR 的全部四个 TASK**。依据 SDD §9：本迁移是单发布原子切换，**不存在**「部分生产者新合同 / 部分消费者旧合同」的合法状态。任一 TASK 失败或评审 blocker 无法在本 loop 内闭合 → 整体 revert（回退到上一完整 `tools` 版本 `81d31b8` 的口径），**不得**靠临时恢复 `recoverCommand` 让半迁移版本发布，**不得**引入双写兼容期、deprecated alias 或 migration shim。SDD 本身（`6c5c9a11`，人工作为审批目标绑定 `2d637724…`）不在回滚面内——本计划无权改 SDD。

### 4.1 风险表

| # | 风险 | 等级 | 应对 | 回滚 |
|---|---|---|---|---|
| R-01 | 迁移不彻底：遗漏站点，或测试标题/提示词/文档残留旧名 → 整树扫描面命中（`cmd-03` 零命中断言红、`cmd-01` 内 `contract-scan.test.mjs` 红） | 高 | `cmd-03` 按 SDD §4.4-2 同一枚举规则重放「整树 − 两项精确路径」零命中并打印命中清单；`cmd-01` 内八条代表性命中用例证明范围非恒真；TASK-01…04 的完成标志各自含「本 TASK 触达文件零命中」 | RU-ALL |
| R-02 | OpenWiki 生成环境不可用（无 provider key / 无网络） | 中 | 按 SDD D-7 第 4 步以**环境阻塞**上报（`ENVIRONMENT_MISMATCH`），**不得回退为手工编辑生成页**；三条证据缺一不可：生成命令、生成前后 diff、页面零命中（`cmd-06` 提供页面事实面） | RU-ALL |
| R-03 | CR-2026-041 的三个既有退役 Skill 名（代码常量名 `RETIRED`）被误并入整树扫描面 → 活跃文件（`lint-prompts.mjs` 禁止名单、`crctl.test.mjs` / `lint-prompts.test.mjs` 用例样本、`CUSTOM.md` 台账引述、`docs/` 历史报告与历史夹具）立刻误报 | 中 | 严格按 SDD §4.4-1「按名分范围」：既有名单保持既有显式 `ACTIVE_PATHS` 与既有断言**逐字不动**（CR-2026-041 范围），整树面只适用于两个恢复字段名；`cmd-01` 内既有 CR-2026-041 用例保持通过 | RU-ALL |
| R-04 | 测试文件自身含旧名字符串（用例标题、断言、`recover_command` 双投影用例）→ 整树扫描红 | 中 | TASK-04 逐文件迁移标题与断言（7 文件 + `crctl.test.mjs` 的 reset / gate / 成功结果字段集用例）；`cmd-03` 零命中兜底；**禁止靠「加排除」消红**——新增排除必须改 `assert.deepEqual(EXCLUDED, …)` 冻结值并被评审看见（SDD §4.4-3） | RU-ALL |
| R-05 | 站点 4（merge publication lag → `checkpoint`）的局部名 `checkpointRecoverCommand` 未随结构化一并改名，或改名后取值断裂 → 恢复方向丢失 | 中 | 按 SDD §11 计数口径原文把该局部名改写为新合同口径名（`checkpointRecovery`）；TASK-01 完成标志含两条：改写后区分大小写检索在 `tools` 仓零命中，且站点 4 的两个 `TxError` 的 `extra.recovery` 仍取该局部值（值类型由 shell string 变为 `buildRecovery(...)` 结果）；`cmd-01` 内 `merge-tx.test.mjs` 断言 `recovery.args` 指向 `checkpoint` 且 `cwd` 为 installRoot | RU-ALL |
| R-06 | reset 的 6 类 reason 向量在非 TTY 环境提前退出 → 用例恒真/恒假，AC-03 假绿 | 中 | 用既有 `runCrctlInTty` 包装（SDD §6.3 AC-03 可达性说明）；每类断言四件事：`args` 不含该值、`promptFor` 含 `reason`、`requiresTTY === true`、`JSON.stringify(recovery)` 中该值不出现（`cmd-01`） | RU-ALL |
| R-07 | 证据命令超出 `write-test-report` 节点 20 min 预算（`timeoutMinutes=20`） | 中 | `cmd-01` 是本节点实测 **786.5 s**（新基线，见 §5.3）的单条全量命令，`cmd-02` 1.2 s，`cmd-03…cmd-06` 各秒级 ⇒ 预计总时长 ≈ 800 s，预算内余量 ≈ 6.5 min；`cmd-01` 的 timeout 设 **1080 s**（< 节点预算），超时即 `block`（**不静默、不降级**）；套件自身的收敛上限是 30 min（`DEFAULT_MAX_RUNTIME_MS`），故 1080 s 是**更早**的失败闸。**不拆分套件**（按文件分组会让墙钟上升） | 非代码缺陷，不触发回滚 |
| R-08 | 删除 `register` 双投影后，既有「成功结果字段集与改造前一致」类断言变红 | 中 | 该断言属 FR-6 授权的迁移面：TASK-04 同步更新为「字段集含 `recovery`、不含 `recoverCommand`/`recover_command`」；`cmd-01` 内 `register-tx.test.mjs` 的单投影断言即证据；不得放宽为「不检查字段集」 | RU-ALL |
| R-09 | 整树扫描面在**新增**文件上误报（未来在本仓落历史迁移/changelog 文档） | 低 | 这是 SDD D-5 明示的**取舍**（新增排除是显式且被断言的评审动作），非本 CR 缺陷；本 CR 期间 `tools` 仓无此类文件，`cmd-03` 零命中即事实面 | RU-ALL |
| R-10 | 采集/扫描实现忽略行尾差异 → 跨行判定静默漏检（历史三次咬人点） | 中 | 全部读取先做 `CRLF → LF` 规范化；扫描面枚举为空、排除项不存在于磁盘、索引 0 条 active、Pipeline 索引与目录集合不相等一律**硬失败**（SDD §4.4-2 硬失败清单）；`cmd-03` 以扫描面规模下界（≥200）做空面哨兵 | RU-ALL |
| R-11 | `multica` 侧 `CUSTOM.md` 台账登记义务的边界判定 | 低 | SDD §1.1 的多仓变更边界只含 `cr-prompts-revised/delivery-agent.md`（提示词文本，非代码/迁移/自研包），本 CR 不改 `CUSTOM.md`：该台账第 75 行登记的事实（`cr-prompts-revised/` 是 `tools` 同名 Prompt 的对照快照、平台 DB 是部署投影）在本 CR 后仍成立。若 owner/reviewer 判定需补记，走上游 SDD 变更，不在 plan/TASK 内扩面 | 非代码缺陷，不触发回滚 |
| R-12 | 生成页与 README 被写进**第二套**合同描述（手工另写一段解释） | 低 | TASK-03 完成标志含「README 只原位改写既有条目、未新增恢复合同章节；OpenWiki 页不手工编辑」；`cmd-06` 断言页面与 README 旧字段零命中且含结构化字段名 | RU-ALL |
| R-13 | **测试迁移触碰合并后门禁的登记面下限**：`suite-gate.mjs:437-453` 对 `skills/shared/crctl/scripts/test/` 施加两条机器判定——磁盘（以及被真实 spawn 的）文件集合须 ≡ `manifest.files`（恰 **21** 个，`SUITE_MANIFEST_FILE_DRIFT`）、每文件顶层用例数不得低于 `manifest.cases`（`SUITE_MANIFEST_CASE_DROP`）。迁移中删/合并/重命名/跳过任一顶层用例，或新增该目录测试文件，都会让 `cmd-01` 红 | 高 | SDD §4.5-7 的三条硬约束逐条落进 TASK-04 的完成标志：字符串包含断言 → 结构断言**逐用例原位替换**；**不新增**该目录测试文件；**不改** `gate-registry.json` 的 `manifest.files` / `manifest.cases` / `exceptions`（唯一写入口是人类编辑 + git commit，不属本 CR `scope_in`，且本 CR 无例外通道）。本节点实测基线：`manifest.files` = 21、`manifest.cases` 合计 = 578、`exceptions: []`、磁盘测试文件集合 ≡ `manifest.files`；迁移的 8 个文件逐文件下限 = `archive-tx` 24 / `checkpoint-tx` 23 / `crctl` 224 / `merge-tx` 17 / `register-tx` 26 / `workspace-freshness` 32 / `writeback-tx` 33 / `contract-scan` 17（只增不减）。`cmd-01` 的 GREEN 即该约束的机器证据 | RU-ALL |
| R-14 | **冻结 skip 模式与证据命令的交互**：机器区 `skipped` 字段按冻结模式表（`workspace-transactions.mjs` 的 `FROZEN_SKIP_PATTERNS`，含 `/\bSKIPPED\b/i`）在 stdout/stderr 上判定；`node --test` 默认 spec reporter 的摘要行 `ℹ skipped 0` 会命中该模式 → 该命令在 `test-report.md` 机器区被记为 `skipped: true`（**本次实测**，见 §5.3），而真实 skip 数为 0 | 中 | `cmd-02` 的 `args` 在 SDD §6.3 AC-07 命令 2 之上**只增加** `--test-reporter=dot`（转录注记见 §6.2.1）：文件集合、断言、退出码语义均不变，仅为规避冻结模式的假命中（`write-test-report` Skill 对 node --test 命令的统一要求——「计划统一使用 `--test-reporter=dot` 保证 `skipped` 恒 false」）。`cmd-01` 无需该参数：`suite-gate.mjs` 的 stdout 报告按自身约定不含独立词 `skipped`（用 `skipped_cases` / `skipped_file_level`），并有 CR-2026-065 的禁词自测守护（本次实测零命中） | 非代码缺陷，不触发回滚 |
| R-15 | `write-test-report` 的 `cmd-02` 若被记为 `skipped`（见 R-14），`review-code` 只读该字段、不得自行解析输出 → 误判为「证据被跳过」而 BLOCK | 中 | 由 R-14 的转录消除根因；`test-report.md` 的分析段（`<!-- crctl:analysis-below -->` 以下，允许模型撰写）须逐字记录 `cmd-02` 的真实结果（13 pass / 0 fail / 0 skip）与 reporter 转录事实，供 `review-code` 对表 | 非代码缺陷，不触发回滚 |

## 5. 验收与发布策略

### 5.1 发布前 checklist（全部为机器可判或逐行可核）

- [ ] `cmd-01` exit 0：`verdict: pass`、`converged: true`、`files_executed = 21`、`cases_executed ≥ 578`、`failures` 空、`checks` 全 `ok`、`registry.exceptions_count = 0`（登记面 21 文件 / 578 用例下限不破）。
- [ ] `cmd-02` exit 0：writeback 单测全绿。
- [ ] `cmd-03` 零失败：整树扫描面旧名零命中；`EXCLUDED` 恰两项精确路径（无通配）；两项排除均含旧名（扫描器保存退役名单、历史夹具保存旧名）；`fixtures/` 在面内 3 个；扫描面 ≥ 200；`manifest.files` 恰 21 且 ≡ 磁盘集合、`exceptions: []`。
- [ ] `cmd-04` 零失败：`multica` 仓内旧名仅剩两个历史黄金数据文件；`cr-prompts-revised/**` 零命中；diff 仅 `cr-prompts-revised/delivery-agent.md`。
- [ ] `cmd-05` 零失败：`shell: true` / `Invoke-Expression` 在 `crctl.mjs` + `lib/*.mjs` 零命中；`tools` diff ⊆ SDD §1.1 白名单（`openwiki/**` 由生成器产出）；`zero_diff` 面（`ARCHITECTURE.md` / `dir-graph.yaml` / `gates.json` / `controlled-shell/rules.json` / `pipeline-templates/**` / `.github/workflows/**` / `agents/**` / `gate-registry.json`）零改动。
- [ ] `cmd-06` 零失败：README 与 OpenWiki 页旧名零命中且含结构化字段名；本 CR 产物无平台侧已生效的声称；KB diff ⊆ `change-requests/CR-2026-064/**` + `change-requests/_backlog.yml`。
- [ ] OpenWiki 生成闭环三证据齐备（生成命令 + 生成前后 diff + 页面零命中），缺一即按 R-02 以环境阻塞上报。
- [ ] 无 alias / shim / fallback：整树零命中断言（`cmd-03`）+ `register` 单投影断言（`cmd-01`）+ diff 面核对（`cmd-05`）三者并置。
- [ ] `tasks/_index.yml` 四个 TASK 全部 `done`（做完一个标一个，不积压到回写期）。

### 5.2 发布与观测

- 发布路径由 Pipeline 控制：`approve --stage dev-start` → `implement-code` → `write-test-report` → `review-code` → `approve --stage code` → `merge-feature-branch` → `feature-writeback` → `archive`。
- **不新增任何运行期观测**：本 CR 不引入使用量、失败率、SLO、迁移统计或持续观测机制（PRD §6 / FR-14 末句）；退役保护是既有静态测试的扩展，不新增 CI 步骤（`.github/workflows/**` 为 `zero_diff`）。
- 平台侧 Prompt 部署由 owner 在 `tools` 发布后另行执行（FR-16）；本 CR 只交付 owner 可复制版本，**不声称平台 DB 已生效**。

### 5.3 基线与既有事实（本节点在新基线上重新实测，非沿用上一版）

**新基线的三个 HEAD**：tools `81d31b8`、multica `dead9fe0`、KB `ab6f9347`（三仓 clean）。

**(a) AC-07 的两条命令（本节点实测，实测对象均为 tools CR worktree，cwd = 仓根）**

| 命令 | 实测结果 |
|---|---|
| `node skills/shared/crctl/scripts/test/suite-gate.mjs --run` | `verdict: pass`、`exit_code: 0`、`converged: true`、`duration_ms: 786516`（≈13.1 min）、`files_executed: 21`、`cases_executed: 578`、`failures: 0`、`checks: 13/13 ok`、`skipped_file_level: 0`、`registry.sha256 f8d983a04656d1fae05588af9daa14b128872bc124e5bcddfd155088b53bd5bf`、`registry.exceptions_count: 0`；`command = node --test --test-reporter=tap <21 files> (pool=15, availableParallelism=16)`；`platform = win32 / node 24.15.0`；`files[].state` 全 `ok`（`cases` 逐文件求和 = 578）。同 HEAD 的另一次独立测量（`…\Temp\suite-gate-CR-2026-064\suite-report.json`，20:58）为 `duration_ms 788986`、同样全绿 ⇒ **两次独立运行均 pass**，耗时稳定在 ≈13 min |
| `node --test skills/writeback/scripts/test/*.test.mjs` | `exit 0`、`tests 13 / pass 13 / fail 0 / skipped 0`、墙钟 **1226 ms**（node 24.15.0）。glob 以**字面字符串**作为独立 argv 元素传参（`shell:false`），由 node（≥22）自身展开；本节点实测该形态与 CI 的 bash 展开命中同一文件集合（`skills/writeback/scripts/test/writeback.test.mjs`） |

**旧基线（`tools@dddd0ad6`）的 5 条红已由 CR-2026-065 清除**：断言改为从真实载体与事实源派生、RED-7 改为真实崩溃窗口重放；登记面 `exceptions` 已清空 ⇒ AC-07 回到**「全绿」**口径、**无需任何例外授权**（SDD §6.3 AC-07 基线事实段）。本计划因此**不含**任何 skip 模式、例外授权或替代口径。

**(b) 门禁登记面（`gate-registry.json`，本节点实测）**：`manifest.files` 恰 **21** 个、与磁盘 `skills/shared/crctl/scripts/test/*.test.mjs` 集合**相等**；`manifest.cases` 合计 **578**；`exceptions: []`。迁移的 8 个文件逐文件用例下限见 R-13。

**(c) 旧字段盘点（SDD §11 唯一计数口径，本节点重跑）**

| repo | 文件数（`rg -l`） | 行数（`rg -c` 求和） | 匹配次数（`rg -o` 计数） |
|---|---|---|---|
| `tools@81d31b8` | **16** | **72** | **87** |
| `multica@dead9fe0` | **3** | **6** | **6** |

`tools` 侧逐文件分布见 §8；`multica` 侧为 `cr-prompts-revised/delivery-agent.md`（2/2）+ 两个历史黄金数据（2/2、2/2）。计数口径固定：大小写敏感、不加 `-w`、用 `rg` 默认的 `.git`/`.gitignore` 过滤、按「文件 / 行 / 次」三项分别给值、不混用。

**(d) 扫描面规模（SDD §4.4-2 同一枚举规则，本节点实测，报告值 + 结构性断言）**

- 枚举：`readdirSync(..., { withFileTypes: true, recursive: true })` 的非目录条目 **219** 个，其中 1 个是工作树的 `.git` **文件**（按路径段排除）⇒ 枚举 **218** 文件（= 该 commit 的 tracked 集合，工作树 clean）。
- 扫描面 = 218 − 扫描器自身 1 − 历史 traceability 精确路径 1 = **216 文件**。
- `skills/**` + `pipeline-templates/**` 递归 `.mjs` 共 **43**（活跃源码 **17** / 活跃测试 **26**；入扫描面 17 + 25 = **42**）。
- 三个 active 索引：Skill **56** / Agent **9** / Pipeline **8**，条目全部存在于磁盘（实现在 `contract-scan.test.mjs` 与 `check-skill-matrix.test.mjs` 内断言，随 `cmd-01` 执行）。
- `fixtures/` 目录 4 个文件：**3 个在面内**（`digest-vectors/**`，对两个退役名零命中）、**1 个被排除**（`traceability-191k.yml`）。

**(e) shell 逃逸守卫基线（AC-04）**：`crctl.mjs` + `lib/*.mjs`（5 个文件）中 `shell: true` **0** 处、`Invoke-Expression` **0** 处、`shell: false` **13** 处。

**(f) 冻结 skip 模式重放（R-14 的实测依据）**：以 `FROZEN_SKIP_PATTERNS` 五条正则重放两条 AC-07 命令的真实输出——`cmd-01` stdout（suite-gate 报告 + 人类摘要）**零命中**（suite-gate 自身的设计约定 + CR-2026-065 的禁词自测共同保证）；`cmd-02` 使用默认 reporter 时命中 `\bSKIPPED\b/i` 一次（摘要行 `ℹ skipped 0`），故 `cmd-02` 按 §6.2.1 增加 `--test-reporter=dot`。

### 5.4 证据命令集的预算说明（`write-test-report` 节点 `timeoutMinutes=20` ⇒ 1200 s）

| 命令 | 预期时长量级 | 依据 |
|---|---|---|
| `cmd-01` | **786.5 s**（本节点实测；同 HEAD 另一次 789.0 s） | 已计入预算：786.5 s < 1080 s（timeout）< 1200 s（节点预算） |
| `cmd-02` | 秒级（1.2 s） | 单文件 `writeback.test.mjs` |
| `cmd-03` / `cmd-04` / `cmd-05` / `cmd-06` | 各秒级（纯文件读 + 字符串判定 + 一次 `crctl git diff`） | 无子进程套件、无网络 |

预计总时长 ≈ 800 s，节点预算内余量 ≈ 6.5 min。`cmd-01` 的 timeout = 1080 s 是**比套件自身 30 min 收敛上限更早**的失败闸：超过即 `block`（不静默、不会假绿）。

### 5.5 与上一版计划的差异 / 上一版遗留待裁决项的收敛记录

| 上一版（`c0750ae5`）的项 | 本版处置 | 依据 |
|---|---|---|
| §5.3「基线红 5 条」清单与归因 | **整体删除**（5 条红已不存在） | CR-2026-065 合入 `tools@81d31b8`；SDD §6.3 AC-07 基线事实段 |
| §5.5-1「基线红例外是否沿用既有授权」（待评审判定项） | **已消失**：无红即无例外，无需授权 | 同上；`gate-registry.json#exceptions: []` |
| §5.5-2「`cmd-01` 去掉 SDD 明文要求的并发参数」（待评审判定项） | **已收敛**：SDD 修订已把 AC-07 的可观测结果定为 CI 的两条现有步骤；本计划按 SDD 逐字转录，不存在需要评审判定的参数取舍 | SDD §6.3 AC-07（含其「不采用旧字面并发命令」的三条理由段） |
| 标注「未在本 CR 的 SDD 中单独授权」的放宽口径 | **不存在**：AC-07 = 全绿 | 同上 |
| `cmd-01` 的 `--test-skip-pattern` 锚定例外与失败集合断言 | **整体删除**；`cmd-01` = SDD §6.3 AC-07 命令 1 逐字 | 同上 |
| `cmd-02` 的 dot reporter（上一版已有） | **保留**，并在 §6.2.1 补齐实测理由（R-14） | `write-test-report` Skill 的统一要求 + 本次冻结模式重放实测 |

**本版无待评审判定项、无例外、无 skip 模式、无并发参数、无「待人工裁决」占位。**

## 6. 两张稳定表（契约必填节，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 唯一恢复合同字段 `recovery`（AC-01、AC-10） | §2.1 字段表 + §3.1 类型 + §3.2 构造器（键序固定、可选性、恒定 `executable`）+ SDD-CLOSE-01 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02 的投影面） | cmd-01 | RU-ALL |
| FR-2 argv 边界与参数完整性（AC-01） | §4.1 拆 token 六步 + 11 站点 `args` 取值表 + SDD-CLOSE-02 | CR-2026-064-TASK-01 | cmd-01、cmd-03 | RU-ALL |
| FR-3 `executable` 安全约束（AC-10） | §3.2 保证 1–2（`'node'` 恒定 + `args[0]` 为脚本路径）+ §4.5 向量 6 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-04 的守卫断言） | cmd-01、cmd-05 | RU-ALL |
| FR-4 `promptFor[]` 人工输入行为（AC-03、SDD-CLOSE-03） | §3.4 值名 → CLI 入口映射 + §4.1 第 5 步（`reason` / `plan` / `CR-ID` 不进 `args`） | CR-2026-064-TASK-02（关联 CR-2026-064-TASK-04 的 6 类向量） | cmd-01 | RU-ALL |
| FR-5 全部已知生产者迁移（AC-01、AC-02） | §4.1 站点 1–9（9 类场景的构造）+ §3.3 载体表 + SDD-CLOSE-06 | CR-2026-064-TASK-01 | cmd-01、cmd-03 | RU-ALL |
| FR-6 CLI 投影迁移（AC-02） | §4.2 四步 + §3.3 站点 10/11（`gate` 错配、`reset` 提交失败）+ `register` 单投影 | CR-2026-064-TASK-02 | cmd-01 | RU-ALL |
| FR-7 全部活跃 Skill/Agent 消费者迁移（AC-05） | §4.3 消费方行 + §8 采纳完整性（5 处，无遗留采纳项）+ D-6 消费合同单一事实源 | CR-2026-064-TASK-03 | cmd-03、cmd-04、cmd-06 | RU-ALL |
| FR-8 文档迁移且不产生第二套合同（AC-05） | §4.3 `README.md` 行 + D-7 生成闭环（四步，不手工编辑生成页） | CR-2026-064-TASK-03 | cmd-03、cmd-06 | RU-ALL |
| FR-9 测试改为结构断言（AC-02、AC-07） | §4.5 结构断言模板 + 向量 3/4/5/6 + §4.5-7 用例下限硬约束 | CR-2026-064-TASK-04 | cmd-01 | RU-ALL |
| FR-10 旧字段同 CR 删除、不留兼容路径（AC-05） | §4.1 第 6 步（原位删除、不并排双写）+ §2.3 别名表（无 alias/shim/fallback）+ §9 `scope_out` | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02/03/04 的全量删除面） | cmd-03、cmd-04 | RU-ALL |
| FR-11 contract-scan 退役保护（AC-06、SDD-CLOSE-05） | §4.4 全节：分名名单 + 整树派生扫描面 + 两项精确路径排除 + 四条结构性断言 + 八条命中用例 + 不误报正反用例 | CR-2026-064-TASK-04 | cmd-01（`contract-scan.test.mjs` 在列）、cmd-03 | RU-ALL |
| FR-12 安全测试向量（AC-03、AC-10、AC-11） | §4.5 向量 3（参数边界）/ 4（6 类用户输入）/ 5（四类缺失）/ 6（shell 逃逸守卫） | CR-2026-064-TASK-04 | cmd-01、cmd-05 | RU-ALL |
| FR-13 既有语义零改变（AC-07、AC-08） | §2.2 不落盘 + §3.3 尾段（错误码/exit code/txId/rollback/files 不变）+ §4.2「只改载体」+ §6.3 AC-07 的两条 CI 命令 | CR-2026-064-TASK-04（关联 CR-2026-064-TASK-01、CR-2026-064-TASK-02 的回归面） | cmd-01、cmd-02、cmd-05 | RU-ALL |
| FR-14 实施前有界盘点（AC-12） | §11 依赖清单即基线盘点 + §4.3 逐文件清单；六类归档表见本计划 §8（plan 节点产物） | CR-2026-064-TASK-04（关联 CR-2026-064-TASK-01/02/03 的迁移面） | cmd-03、cmd-06 | RU-ALL |
| FR-15 整体回滚（AC-13） | §9 `scope_out` 与 §6.1 FR-15 + 本计划 §4.0（回滚单元唯一 = RU-ALL） | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02/03/04 同进退） | cmd-03（活跃面无半迁移态）、cmd-05 | RU-ALL |
| FR-16 回写与平台部署边界（AC-09、AC-14） | §1.1 范围表（不更新平台 DB）+ §8 平台部署边界 + §6.1 FR-16 | CR-2026-064-TASK-03（关联 CR-2026-064-TASK-04 的口径断言） | cmd-06 | RU-ALL |
| FR-17 合同确定性（AC-04、AC-11、SDD-CLOSE-04） | §2.4 指纹字段集 + §3.5 固定 5 步判定与四类错误闭包 + §3.1 零副作用 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02 构造、CR-2026-064-TASK-03 消费合同、CR-2026-064-TASK-04 守卫） | cmd-01、cmd-05 | RU-ALL |

覆盖校验：**17 行 = FR-1…FR-17 各恰一次**；`主责/关联TASK` 全部使用 canonical 完整 id（与 `tasks/_index.yml` 的 id 集一致）；`验收证据` 列出现的标识集合 = {`cmd-01`…`cmd-06`}，与 §6.2 双向唯一映射（无孤证、无表外引用）；回滚列唯一取值为 `RU-ALL`（§4.0）。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["skills/shared/crctl/scripts/test/suite-gate.mjs","--run"]` | 1080 |
| cmd-02 | tools | . | node | `["--test","--test-reporter=dot","skills/writeback/scripts/test/*.test.mjs"]` | 300 |
| cmd-03 | tools | . | node | `["-e","const fs=require('fs'),path=require('path');const R=process.cwd();const NL=String.fromCharCode(10);const NAMES=['recoverCommand','recover_command'];const SKIP=['.git','node_modules'];const SCANNER='skills/shared/crctl/scripts/test/contract-scan.test.mjs';const HIST='skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml';const EXCLUDED=[SCANNER,HIST];const rel=p=>path.relative(R,p).split(path.sep).join('/');const segs=p=>rel(p).split('/');const norm=t=>t.split(String.fromCharCode(13)+NL).join(NL);const all=[];const walk=d=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(segs(p).some(s=>SKIP.includes(s)))continue;if(e.isDirectory())walk(p);else all.push(rel(p));}};walk(R);const surface=all.filter(r=>EXCLUDED.includes(r)===false).sort();const hit=f=>{const t=norm(fs.readFileSync(path.join(R,f),'utf8'));return NAMES.some(n=>t.includes(n));};const hits=surface.filter(hit);const exHit=EXCLUDED.filter(hit);const fx=surface.filter(r=>r.startsWith('skills/shared/crctl/scripts/test/fixtures/'));const reg=JSON.parse(norm(fs.readFileSync('skills/shared/crctl/scripts/test/gate-registry.json','utf8')));const mf=reg.manifest.files.slice();const disk=all.filter(f=>f.startsWith('skills/shared/crctl/scripts/test/')&&f.endsWith('.test.mjs')).map(f=>f.split('/').pop()).sort();const bad=[];console.log('enumerated = '+all.length);console.log('scan surface = '+surface.length);console.log('retired-name hits in surface = '+hits.length);hits.forEach(h=>console.log('  HIT '+h));console.log('excluded = '+EXCLUDED.length+' (hit = '+exHit.length+')');exHit.forEach(h=>console.log('  EXCLUDED-HIT '+h));console.log('fixtures in surface = '+fx.length);fx.forEach(f=>console.log('  IN '+f));console.log('manifest.files = '+mf.length+' cases floor sum = '+Object.values(reg.manifest.cases).reduce((a,b)=>a+b,0)+' exceptions = '+reg.exceptions.length);if(hits.length>0)bad.push('surface hits = '+hits.length);if(EXCLUDED.length!==2)bad.push('excluded count = '+EXCLUDED.length);if(EXCLUDED.filter(e=>[e.includes('*'),e.includes('?')].some(x=>x)).length!==0)bad.push('excluded 含通配');if(EXCLUDED.includes(SCANNER)===false)bad.push('扫描器自身不在排除项');if(EXCLUDED.includes(HIST)===false)bad.push('历史 traceability 不在排除项');if(!EXCLUDED.every(hit))bad.push('excluded hit count = '+exHit.length);if(fx.length!==3)bad.push('fixtures in surface = '+fx.length);if(surface.length<200)bad.push('scan surface suspiciously small = '+surface.length);if(mf.length!==21)bad.push('manifest.files = '+mf.length);if(JSON.stringify(mf.slice().sort())!==JSON.stringify(disk))bad.push('manifest.files 与磁盘测试文件集合不相等');if(reg.exceptions.length!==0)bad.push('exceptions 非空 = '+reg.exceptions.length);if(bad.length>0){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);}console.log('scan-audit failures = 0');"]` | 300 |
| cmd-04 | multica | . | node | `["-e","const fs=require('fs'),path=require('path'),cp=require('child_process');const R=process.cwd();const NL=String.fromCharCode(10);const NAMES=['recoverCommand','recover_command'];const DIR='cr-prompts-revised';const GOLD=['server/internal/governance/testdata/traceability-golden.yml','server/internal/governance/testdata/traceability-golden.json'];const CRCTL='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-064/skills/shared/crctl/scripts/crctl.mjs';const SKIP=['.git','node_modules'];const rel=p=>path.relative(R,p).split(path.sep).join('/');const all=[];const walk=d=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(rel(p).split('/').some(s=>SKIP.includes(s)))continue;if(e.isDirectory())walk(p);else all.push(rel(p));}};walk(R);const hit=f=>{const t=fs.readFileSync(path.join(R,f),'utf8').split(String.fromCharCode(13)+NL).join(NL);return NAMES.some(n=>t.includes(n));};const remain=all.filter(hit).sort();const bad=[];const files=fs.readdirSync(path.join(R,DIR)).filter(f=>f.endsWith('.md'));const dhits=files.filter(f=>{const t=fs.readFileSync(path.join(R,DIR,f),'utf8');return NAMES.some(n=>t.includes(n));});console.log('multica files containing retired names = '+remain.length);remain.forEach(f=>console.log('  REMAIN '+f));console.log('cr-prompts-revised md files = '+files.length+' hits = '+dhits.length);dhits.forEach(h=>console.log('  HIT '+DIR+'/'+h));const dev=fs.readFileSync(path.join(R,DIR,'delivery-agent.md'),'utf8');if(dev.includes('recovery')===false)bad.push('delivery-agent.md 未改读结构化 recovery');if(NAMES.some(n=>dev.includes(n)))bad.push('delivery-agent.md 仍含退役字段名');for(const g of GOLD){const t=fs.readFileSync(path.join(R,g),'utf8');if(NAMES.some(n=>t.includes(n))===false)bad.push('历史黄金数据不含旧字段名（排除依据失效）: '+g);}if(dhits.length>0)bad.push('prompt hits = '+dhits.length);if(remain.length!==2)bad.push('multica 旧名残留文件数 = '+remain.length+'（应为 2 个历史黄金数据）');const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','dead9fe0d5a24118547a5be56d59241fdcc443a8','--cwd',R],{encoding:'utf8'});if(r.status!==0){bad.push('crctl git diff 失败');console.log(String(r.stderr).trim());}else{const parts=String(r.stdout).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const names=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);console.log('multica diff paths = '+names.length);names.forEach(f=>console.log('  '+f));const want=[DIR+'/delivery-agent.md'];for(const f of names)if(want.includes(f)===false)bad.push('multica diff 越界路径: '+f);for(const f of want)if(names.includes(f)===false)bad.push('multica diff 缺少应改文件: '+f);}if(bad.length>0){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);}console.log('multica-audit failures = 0');"]` | 300 |
| cmd-05 | tools | . | node | `["-e","const fs=require('fs'),path=require('path'),cp=require('child_process');const R=process.cwd();const NL=String.fromCharCode(10);const CRCTL=path.join(R,'skills/shared/crctl/scripts/crctl.mjs');const T='skills/shared/crctl/scripts/test/';const WL=['README.md','openwiki/operations/crctl-transactions.md','skills/shared/crctl/SKILL.md','skills/cr/cr-archive/SKILL.md','skills/sync/push-progress/SKILL.md','skills/writeback/merge-feature-branch/SKILL.md','skills/shared/crctl/scripts/crctl.mjs','skills/shared/crctl/scripts/lib/workspace-transactions.mjs'].concat(['archive-tx','checkpoint-tx','crctl','merge-tx','register-tx','workspace-freshness','writeback-tx','contract-scan'].map(n=>T+n+'.test.mjs'));const ZERO=['ARCHITECTURE.md','dir-graph.yaml','skills/shared/crctl/gates.json','skills/shared/controlled-shell/rules.json','skills/shared/crctl/scripts/test/gate-registry.json','skills/shared/crctl/scripts/lib/durable-tx.mjs','skills/shared/crctl/scripts/lib/yaml-subset.mjs','skills/_index.yml','agents/_index.yml'];const bad=[];const SKIPS=['.git','node_modules'];const walk=(d,out)=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);const r=path.relative(R,p).split(path.sep).join('/');if(e.isDirectory()){if(SKIPS.includes(e.name))continue;walk(p,out);}else if(r.endsWith('.mjs'))out.push(r);}};const lib=[];walk(path.join(R,'skills/shared/crctl/scripts/lib'),lib);const guard=['skills/shared/crctl/scripts/crctl.mjs'].concat(lib);const BADT=['shell: true','shell:true','Invoke-Expression'];const ZP=['pipeline-templates/','.github/workflows/','agents/'];let falseCount=0;for(const f of guard){const t=fs.readFileSync(path.join(R,f),'utf8');for(const s of BADT)if(t.includes(s))bad.push('shell 逃逸守卫命中: '+f+' 含 '+s);const mm=t.match(/shell:[ ]*false/g);if(mm!==null)falseCount+=mm.length;}console.log('guard files = '+guard.length+' shell:false = '+falseCount);if(falseCount<1)bad.push('argv 先例 shell:false 计数异常');const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','81d31b8b9d4c36cfef24cd076bf9fe635b67b2b6','--cwd',R],{encoding:'utf8'});if(r.status!==0){bad.push('crctl git diff 失败');console.log(String(r.stderr).trim());}else{const parts=String(r.stdout).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const names=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);console.log('tools diff paths = '+names.length);names.forEach(f=>console.log('  '+f));const inScope=f=>{if(f.startsWith('openwiki/'))return true;return WL.includes(f);};for(const f of names)if(inScope(f)===false)bad.push('tools diff 越界路径（不在 SDD §1.1 白名单）: '+f);for(const f of names){if(ZP.some(z=>f.startsWith(z)))bad.push('zero_diff 面被改动: '+f);if(ZERO.includes(f))bad.push('zero_diff 面被改动: '+f);}for(const f of WL)if(names.includes(f)===false)bad.push('tools diff 缺少应改文件: '+f);if(names.length===0)bad.push('tools diff 为空（实现未落盘？）');}if(bad.length>0){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);}console.log('tools-guard-audit failures = 0');"]` | 300 |
| cmd-06 | ai-first-platform-docs | . | node | `["-e","const fs=require('fs'),path=require('path'),cp=require('child_process');const R=process.cwd();const NL=String.fromCharCode(10);const CR='change-requests/CR-2026-064';const TOOLS='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-064';const NAMES=['recoverCommand','recover_command'];const CATS=['producer','code consumer','Prompt-Skill consumer','active test','active docs','historical evidence'];const CRCTL=path.join(TOOLS,'skills/shared/crctl/scripts/crctl.mjs');const bad=[];const plan=fs.readFileSync(path.join(R,CR,'plan.md'),'utf8');for(const c of CATS)if(plan.includes(c)===false)bad.push('plan.md 六类归档缺少类别: '+c);if(plan.includes('平台 DB')===false)bad.push('plan.md 未记录平台部署边界');const docs=['README.md','openwiki/operations/crctl-transactions.md'];for(const f of docs){const t=fs.readFileSync(path.join(TOOLS,f),'utf8');if(NAMES.some(n=>t.includes(n)))bad.push('活跃文档仍含退役字段名: '+f);}const page=fs.readFileSync(path.join(TOOLS,'openwiki/operations/crctl-transactions.md'),'utf8');for(const k of ['recovery','executable','args','promptFor'])if(page.includes(k)===false)bad.push('OpenWiki 页缺少结构化合同字段名: '+k);const claim=['平台 DB','已部署'].join('');const tdir=path.join(R,CR,'tasks');const arts=[path.join(R,CR,'plan.md')].concat(fs.existsSync(tdir)?fs.readdirSync(tdir).filter(f=>f.endsWith('.md')).map(f=>path.join(tdir,f)):[]);for(const a of arts){const t=fs.readFileSync(a,'utf8');if(t.includes(claim))bad.push('CR 产物出现部署声称: '+path.relative(R,a));}const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','ab6f9347','--cwd',R],{encoding:'utf8'});if(r.status!==0){bad.push('crctl git diff 失败');console.log(String(r.stderr).trim());}else{const parts=String(r.stdout).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const names=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);console.log('KB diff paths = '+names.length);names.forEach(f=>console.log('  '+f));for(const f of names)if(f.startsWith(CR+'/')===false&&f!=='change-requests/_backlog.yml')bad.push('KB diff 越界路径: '+f);}if(bad.length>0){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);}console.log('kb-audit failures = 0');"]` | 300 |

#### 6.2.1 `cmd-01` / `cmd-02` 的转录与注记（人读副本；权威文本以 §6.2 行内 `args` 为准）

- **`cmd-01`** = SDD §6.3 AC-07「可观测结果」第 1 条命令**逐字**：`node skills/shared/crctl/scripts/test/suite-gate.mjs --run`（= CI 步骤 `crctl full test suite`，`crctl-ci.yml:109-111`）。无参数增删。
- **`cmd-02`** = SDD §6.3 AC-07「可观测结果」第 2 条命令（= CI 步骤 `writeback unit tests`，`crctl-ci.yml:113-115`）**逐字 + 一个 reporter 参数**：`node --test --test-reporter=dot skills/writeback/scripts/test/*.test.mjs`。该参数**不改变**文件集合、断言与退出码语义，只消除 R-14 实测的冻结 skip 模式假命中；这是 `write-test-report` Skill 对 `node --test` 类证据命令的统一要求。若复评/协调人要求与 SDD 字面完全一致，可去掉 `--test-reporter=dot`——代价是 `test-report.md` 机器区把该命令记为 `skipped: true`（本次实测，真实 skip = 0）。
- **`cmd-03`…`cmd-06`** 是本计划自有的审计命令（非 SDD 命令）：均由 `cmd-03`/`cmd-01` 的同一口径派生（整树枚举 + 精确排除 + 行尾规范化 + diff 面白名单），只读不写，不新增第二套验收口径。

### 6.3 各命令覆盖的验收面（人读摘要；权威文本以 §6.2 行内为准）

| 证据ID | 覆盖的 FR / AC | 说明 |
|---|---|---|
| cmd-01 | AC-01、AC-02、AC-03、AC-05（测试面）、AC-06（扫描器在列）、AC-07（第一条）、AC-08、AC-10、AC-11、AC-13（无半迁移态的用例面） | 合并后 CI 入口：登记面 21 文件全部被真实 spawn、用例数不低于 `manifest.cases` 下限、`exceptions: []` |
| cmd-02 | AC-07（第二条）、FR-13（writeback 回归面） | writeback 单测（不在 `readTestFileSet` 的登记面内，可正常新增用例） |
| cmd-03 | FR-2、FR-5、FR-7（提示词面）、FR-8、FR-10、FR-11、FR-14、FR-15 | 整树扫描面零命中 + 排除面恰两项且无通配 + 两项排除均含旧名（扫描器保存退役名单、历史夹具保存旧名）+ `fixtures/` 在面 3 个 + 登记面文件集合与 `exceptions` 不变 |
| cmd-04 | FR-7、FR-10、FR-14 | `multica` 仓旧名仅剩两个历史黄金数据；diff 仅 `cr-prompts-revised/delivery-agent.md` |
| cmd-05 | FR-3、FR-12（向量 6）、FR-13、FR-15、FR-17（副作用段） | `shell: true` / `Invoke-Expression` 零命中 + `tools` diff ⊆ SDD §1.1 白名单 + `zero_diff` 面零改动 + 应改文件齐备 |
| cmd-06 | FR-7（README/生成页）、FR-8、FR-14、FR-16 | 活跃文档与生成页旧名零命中且含结构化字段名 + 六类归档在 plan.md + 无平台部署声称 + KB diff 面 |

## 7. AC/业务闭环覆盖矩阵（契约必填节，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-01 全部可恢复结果使用 `recovery`、`args[]` 逐参数且有序、无等价 shell string 备用入口 | §2.1 + §3.1 + §3.2 + §4.1 站点 1–9 | CR-2026-064-TASK-01 | cmd-01 |
| AC-02 八类恢复路径（register / workspace / merge / checkpoint / writeback / archive / test / reset）测试全绿且断言结构化 | §4.1 + §4.2 + §3.3 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02、CR-2026-064-TASK-04） | cmd-01 |
| AC-03 reason 不进 `args[]`、不进 shell string；`promptFor` 含 `reason`；6 类输入序列化后仍为数据 | §3.4 + §3.5 + §4.1 站点 11 + §4.5 向量 4 | CR-2026-064-TASK-02（关联 CR-2026-064-TASK-04） | cmd-01 |
| AC-04 代码消费者使用 argv 边界执行，无 `shell: true` / `Invoke-Expression` 用于恢复动作 | §3.5 副作用段 + §4.5 向量 6 | CR-2026-064-TASK-04 | cmd-05 |
| AC-05 活跃源码 / Skill / Agent / Pipeline / README / 活跃测试均不再消费旧字段；无 alias / shim / fallback | §4.3 逐文件清单 + §4.4 + D-7 + §8 采纳表 | CR-2026-064-TASK-03（关联 CR-2026-064-TASK-01、CR-2026-064-TASK-02、CR-2026-064-TASK-04） | cmd-03、cmd-04、cmd-06 |
| AC-06 旧字段仅存于历史证据 / 迁移文档 / 退役名单；扫描命中即失败、对允许排除面不误报 | §4.4-1/2/3/4 + SDD-CLOSE-05 | CR-2026-064-TASK-04 | cmd-01、cmd-03 |
| AC-07 crctl / ledger / freshness / merge / writeback / archive 全量测试通过（**全绿口径，无例外**） | §6.3 AC-07 的两条 CI 命令 + §2.2/§3.3 零语义变更 | CR-2026-064-TASK-04（关联 CR-2026-064-TASK-01、CR-2026-064-TASK-02） | cmd-01、cmd-02 |
| AC-08 未改变错误码 / 状态转换 / transaction id / rollback / files 语义 | §3.3 尾段 + §4.2「只改载体」+ §2.2 不落盘 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02） | cmd-01、cmd-05 |
| AC-09 平台侧 Prompt 采纳由 owner 在 CR 之后执行；本 CR 产物不出现平台侧已生效的声称 | §1.1 范围表 + §8 平台部署边界 | CR-2026-064-TASK-03 | cmd-06 |
| AC-10 `executable` 不含空格分隔参数与任何 shell 运算符；node 形态脚本路径在 `args[0]` | §3.2 保证 1–2 + §4.5 向量 3 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-04） | cmd-01 |
| AC-11 四类合同缺失场景停止并报错、零副作用、不回退旧字段；按固定顺序给出唯一结论 | §3.5 判定顺序 + D-6 消费合同 + §3.1 零副作用 | CR-2026-064-TASK-03（关联 CR-2026-064-TASK-01、CR-2026-064-TASK-04） | cmd-01、cmd-05 |
| AC-12 实施计划存在一次有界盘点的六类归档；未新增持续观测机制 | §11 依赖清单 + §4.3；归档表见本计划 §8 | CR-2026-064-TASK-04（关联 CR-2026-064-TASK-01/02/03） | cmd-03、cmd-06 |
| AC-13 交付分支不存在部分生产者新合同 / 部分消费者旧合同的中间态；回滚为整体回滚 | §9 `scope_out` + §6.1 FR-15 + 本计划 §4.0 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02/03/04） | cmd-03、cmd-05 |
| AC-14 正常 writeback 所需的 `specs/` 与 `delivery/` 更新包含在本 CR 内 | §9 `scope_in` + §6.1 FR-16（由 `feature-writeback` 节点产出） | CR-2026-064-TASK-03 | cmd-06 |

矩阵校验：14 条 AC 各一行；每条关键 AC 的 `验收证据` 均为稳定标识 `cmd-NN`（与 §6.1/§6.2 全等）；TASK owner 归属实际产生该结果的层（生产者在 TASK-01、投影在 TASK-02、提示词/文档在 TASK-03、测试与退役保护在 TASK-04、流程产物在对应流程节点）。

## 8. FR-14 有界盘点归档（六类，本节点产出；口径 = SDD §11 的唯一计数口径 + §5.3(c) 实测）

| 类别 | 文件（repo / path） | 行 / 次（本节点实测） | 本 CR 处置 |
|---|---|---|---|
| **producer**（构造恢复动作的代码） | `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 23 / 25 | 迁移：新增唯一构造器 `buildRecovery` + 站点 1–9 原位结构化 |
| **code consumer**（消费/投影恢复动作的代码） | `tools/skills/shared/crctl/scripts/crctl.mjs` | 6 / 10 | 迁移：双投影删除、`gate` 错配与 `reset` 失败分支结构化、字段改名、占位符 helper 删除 |
| **Prompt-Skill consumer**（提示词面消费方） | `tools/skills/cr/cr-archive/SKILL.md`、`tools/skills/sync/push-progress/SKILL.md`、`tools/skills/writeback/merge-feature-branch/SKILL.md`、`tools/skills/shared/crctl/SKILL.md`、`multica/cr-prompts-revised/delivery-agent.md` | 6/7、2/3、1/1、2/2（tools）；2/2（multica） | 迁移：改读 `recovery.executable/args/cwd/requiresTTY/promptFor`；`crctl/SKILL.md` 新增「`recovery` 消费合同」小节（单一事实源） |
| **active test**（活跃测试面） | `tools/skills/shared/crctl/scripts/test/{crctl,register-tx,archive-tx,merge-tx,checkpoint-tx,writeback-tx,workspace-freshness}.test.mjs` + 退役保护 `contract-scan.test.mjs` | 11/13、4/4、3/4、3/5、2/2、2/4、1/1；`contract-scan` 为扫描器自身（排除项，本节点在面外） | 迁移：字符串包含断言 → 结构/argv 断言（含 6 类 reason 向量与参数边界向量）；`contract-scan` 扩展退役名单/扫描面/正反用例；**全部逐用例原位替换、只增不减**（R-13） |
| **active docs**（活跃文档与生成页） | `tools/README.md`（1/1，原位迁移）、`tools/openwiki/operations/crctl-transactions.md`（3/3，**生成物**：由既有 `openwiki code --update` 从迁移后源码重新生成并核对，D-7） | 1 / 1；3 / 3 | 迁移：README 原位改读结构化合同；生成页不手工编辑 |
| **historical evidence（排除）** | `tools/skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`（2/2）、`multica/server/internal/governance/testdata/traceability-golden.yml`（2/2）、`.../traceability-golden.json`（2/2） | 2 / 2 每个 | 排除：本 CR 不改写（PRD FR-11 允许排除的历史 traceability / 历史黄金数据；`tools` 侧以**精确路径**排除，见 SDD §4.4-3） |

盘点口径说明：本表是 FR-14 要求的**一次性有界搜索**结果（口径固定为「大小写敏感 + `rg` 默认过滤 + 文件/行/次三项分列」），**不转化为持续观测机制**（AC-12）；`tools` 侧合计 16 文件 / 72 行 / 87 次、`multica` 侧合计 3 文件 / 6 行 / 6 次，与本表各行求和一致（16 = 1 + 1 + 4 + 8 + 2 中的在面文件数口径以 SDD §11 分布表为准；`contract-scan.test.mjs` 与历史夹具不计入迁移对象）。
