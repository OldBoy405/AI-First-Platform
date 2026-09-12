---
id: CR-2026-064-plan
type: PLAN
cr-ref: CR-2026-064
sdd-ref: "change-requests/CR-2026-064/sdd.md"
target-version: 0.37
status: draft
created: 2026-09-13T00:12:55+08:00
updated: 2026-09-13T00:12:55+08:00
---

# CR-2026-064 开发计划（CR-R：结构化恢复合同原子迁移 —— `recoverCommand`/`recover_command` 全量退役为结构化 `recovery`）

**权威输入（审批绑定，本计划不改其一个字节）**

| 输入 | 版本 | SHA256 | 绑定 |
|---|---|---|---|
| `change-requests/CR-2026-064/sdd.md` | commit `a5101d59`（`tech-design-reviewed`，纯 LF：CR 字节 0） | `72ea75eddf4c3d771aa85d329ec98c8968be35b6078478325afd2d15de8efe5d` | `review-annotations/sdd.yml`（`review-tech-design` cycle 2 / attempt 2，`verdict=pass`、`blockers=[]`，评审 commit `95bd360`，`subject-sha256` 与本行逐字一致）+ `approval.yml#tech-design`（approver `OldBoy405`，`2026-09-13T00:04:11+08:00`，via `crctl-approve`，target-status `tech-design-reviewed`，evidence-digest `824cf303…`） |
| `change-requests/CR-2026-064/prd.md` | 需求评审 PASS 版（14 AC / 17 FR） | `4df6f1590e5c04bf2585bfe76bc21a496f702dcea17f2502b0e3584217176457` | 需求人工审批 evidence（`approval.yml#requirement`，本 CR 注册阶段完成） |

- **两个硬边界**：①**不改 `sdd.md`**；②**不改 `prd.md`**。二者哈希均被人工审批绑定，任何正文修订都必须走上游轨（`review-tech-design` → 二次人工审批），不得在 plan/TASK 里静默改写设计。
- 目标版本 `0.37`：继承 `cr.md#target-version`（未改写、未标 `tbd`；CR-2026-057 FR-13）。
- 交付面白名单见 SDD §1.1 变更边界表与 §9 `scope_in`；`zero_diff` 清单见 SDD §9（本计划 §6.2 的 `cmd-03`～`cmd-06` 把其中可机器判定的部分做成判据）。

## 0. 基线与工作区事实（落笔实读，一次读，未轮询）

- status = `tech-design-reviewed`；`crctl next CR-2026-064` = `write-dev-plan`（`why: 技术设计已审批，编写开发计划`，`humanApproval=false`）。
- 架构阶段终点 checkpoint 已闭合：`phase=complete`、`batchId=2cfcb5eb7ca667e4`、三仓 `confirmed=true`、metadata commit `9079005f`（`[cr] checkpoint CR-2026-064 batch 2cfcb5eb7ca667e4`）。
- **`crctl workspace inspect CR-2026-064`（原样透传）**：

| repo | worktreePath | classification | dirty | localBranch / remoteBranch |
|---|---|---|---|---|
| `ai-first-platform-docs` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-064` | **healthy** | false | true / true |
| `multica` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-064` | **healthy** | false | true / true |
| `tools` | `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-064` | **healthy** | false | true / true |

`changed: false`、`operationalWorkspace: "C:\\Users\\GOBAO\\Downloads\\AI\\AI First Platform\\.rayai-worktrees\\knowledge-base\\requirement\\CR-2026-064"`（非空）、`operationalWorkspaceError: null`。三仓全 `healthy`，node-1 入口条件满足。

- 路径 authority（`resources[].worktreePath` 原样值，**不拼接、不回退主工作区**）：

| repo | worktreePath | HEAD（本计划落笔时刻） | 代码事实绑定 |
|---|---|---|---|
| `tools` | `…\.rayai-worktrees\tools\requirement\CR-2026-064` | `dddd0ad63fb79bd7608314b4553f30e8ce7b7289` | 本 CR 的**唯一代码变更仓**；§4.4 扫描面、§11 依赖清单、全部行号均绑此 SHA（`git status` clean） |
| `multica` | `…\.rayai-worktrees\multica\requirement\CR-2026-064` | `ab9609483d17db12117cb8e9adb2d896f413917d` | 只改 `cr-prompts-revised/delivery-agent.md`（2 行 / 2 次旧字段命中）；`server/internal/governance/testdata/traceability-golden.{json,yml}` 为历史黄金数据（排除，不改） |
| `ai-first-platform-docs` | `…\.rayai-worktrees\knowledge-base\requirement\CR-2026-064` | `9079005fa5b0a3c4be482b089dcd1ff86819d020` | 只承载本 CR 过程文档（plan / tasks / test-report / 证据）；**不写** `specs/`、`delivery/`、`docs/` |

- 无 DDL / 无迁移 / 无新增持久化（SDD §2.2：`recovery` 是响应期数据，journal payload 与五本账本零字段变更）；无新增子命令、状态、转换、Pipeline 节点、账本写入通道。
- 代码事实一律按 **stable symbol** 定位（SDD §11 的 21 项依赖已逐条绑定 repo / relative path / symbol / SHA）；本计划中的行号（`~L…`）只作参考，实施定位一律以实时 `rg "recoverCommand|recover_command"` 为准（PRD 明文禁止按行号盲改）。开工前每个 TASK 重跑 `crctl workspace freshness CR-2026-064`（gate=implement-start）。
- **行尾纪律**：本计划与全部 TASK 卡、扫描脚本一律按 LF 口径书写；任何读取仓库文件做哈希 / 跨行判定 / 逐行解析的实现，读入后必须先 `replaceAll('\r\n','\n')` 规范化；跨行匹配失败一律硬失败，禁止静默降级为「空集合」。

## 1. 交付里程碑

| 里程碑 | 内容 | 对应 TASK | 估时 |
|---|---|---|---|
| M1 设计冻结 | 需求审批 + SDD `a5101d59`（`review-tech-design` cycle 2 attempt 2 `pass`、blockers 0）+ 人工架构审批（`824cf303…`）+ 架构阶段终点 checkpoint（`batchId=2cfcb5eb7ca667e4`、`phase=complete`） | 已发生 | 0 |
| M2 计划与任务拆分 | 本 `plan.md` + `tasks/TASK-01…04.md` + `tasks/_index.yml`（`crctl task init --count-hint 4`）+ 推进 `task-breakdown` + 独立 `review-dev-plan` | 流程节点（非交付 TASK） | 0.5 人天 |
| M3 生产者与唯一构造器 | `lib/workspace-transactions.mjs`：新增 `buildRecovery`（约 12 行）+ 9 类场景的 9 个生产者站点原位改为结构化 `recovery`；`checkpointRecoverCommand` 局部值改由构造器产出 | CR-2026-064-TASK-01 | 16h |
| M4 CLI 投影与错误面 | `crctl.mjs`：`register` 双投影删除（单 `recovery`）、`gate --mode pre-review` 错配分支与 `review-loop reset` 提交失败分支结构化、`cmdRegister` 输出字段改名；`crIdForRecover` 占位符语义删除 | CR-2026-064-TASK-02 | 8h |
| M5 消费方与文档迁移 | 4 份 `tools` SKILL（crctl / cr-archive / push-progress / merge-feature-branch）+ `multica/cr-prompts-revised/delivery-agent.md` + `tools/README.md` 原位改读结构化合同；`openwiki/operations/crctl-transactions.md` 由既有生成步骤（`openwiki code --update`）重新生成并核对（D-7，不手工编辑） | CR-2026-064-TASK-03 | 12h |
| M6 测试迁移与退役保护 | 7 个既有测试文件改为结构与 argv 断言（含 6 类 reason 向量）+ `contract-scan.test.mjs` 扩展 `RETIRED_RECOVERY` / 整树派生扫描面 / 两项精确路径排除 / 八条代表性命中用例 + `shell: true`、`Invoke-Expression` 守卫断言 | CR-2026-064-TASK-04 | 16h |
| M7 评审与人工审批 | `review-dev-plan` → `approve --stage dev-start` → `implement-code` → `write-test-report`（`crctl test` 跑 §6.2 六条命令）→ `review-code` → `approve --stage code` | 流程节点 | 流程 |
| M8 发布 | `merge-feature-branch` / writeback / archive（平台侧 Prompt 部署由 owner 在本 CR 落地后另行执行，不属本 CR） | 流程控制节点 | 流程 |

**估算总工时（TASK 账本口径）= 52h**（16h + 8h + 12h + 16h），与 `tasks/_index.yml#totalEstimateHours` 一致（由 `crctl task init --count-hint 4` 的返回值交叉校验）。M2 的 0.5 人天与 M7/M8 是流程节点，不进 TASK 账本。发布经既有 CR merge 流程，**不建交付 TASK**（流程控制 TASK 禁止：完成边界必须落在 `developing` 内可被 `crctl task done` 登记的事件，见 `write-dev-tasks` Step 2 与 SDD §6.1 FR-15/AC-13）。

## 2. 任务依赖图

```text
TASK-01 (tools：lib/workspace-transactions.mjs
          + buildRecovery(args, {cwd, requiresTTY, promptFor}) 唯一构造器（约 12 行）
          + 9 类场景的 9 个生产者站点原位改为结构化 recovery（register / workspace sync /
            merge / merge publication lag / checkpoint / writeback replay /
            writeback apply / archive / test）
          + 消息文本去旧字段名；checkpointRecoverCommand 局部值改由构造器产出)
   │ 产出：buildRecovery（唯一契约构造点，键序固定）
   ▼
TASK-02 (tools：crctl.mjs
          + buildRegisterResult 单投影（删 recover_command 双投影）
          + cmdGate --mode pre-review 错配分支 → error.recovery
          + cmdReviewLoopReset 提交失败分支 → error.recovery（promptFor:['reason']、requiresTTY:true）
          + 删除 crIdForRecover 占位符语义（规范 CR-ID 独立 argv / 非规范入 promptFor）
          + cmdRegister 输出对象字段改名)
   │ 产出：CLI 顶层 recovery 与 error.recovery 的落点契约
   ▼
TASK-03 (tools + multica 文本层：tools/skills/shared/crctl/SKILL.md（含新增「recovery 消费合同」
          小节：固定 5 步判定 + 四类错误闭包）、cr-archive / push-progress /
          merge-feature-branch SKILL.md、README.md 原位迁移；
          openwiki/operations/crctl-transactions.md 由既有生成步骤重新生成并按 D-7 核对
          （不手工编辑）；multica/cr-prompts-revised/delivery-agent.md 改读结构化 recovery)
   │ 产出：活跃提示词/文档面单一一套合同描述；OpenWiki 生成页与权威源码同源
   ▼
TASK-04 (tools 测试面：7 个既有测试文件改结构断言（含 6 类 reason 向量、参数边界向量、
          合同缺失向量）、contract-scan.test.mjs 扩展 RETIRED_RECOVERY + 整树派生扫描面
          + 两项精确路径排除 + 八条代表性命中用例 + 不误报正反用例 + deepEqual 冻结，
          shell:true / Invoke-Expression 守卫断言)
```

- 依赖性质：TASK-02 消费 TASK-01 的 `buildRecovery`（SDD §3.2/§3.3 站点 10/11 在 CLI 侧构造）；TASK-03 的 OpenWiki 生成以「先改权威源码」为前置（SDD D-7 第 1–2 步）；TASK-04 的结构断言断言前三个 TASK 的最终形状，且其整树零命中面覆盖 TASK-03 迁移后的提示词与文档文件。
- 全部四个 TASK 都写 `tools` 仓（TASK-03 另加 `multica` 一个文件）→ **同仓单写者串行执行**，依赖声明与执行顺序一致。
- 无环、无悬空引用；`depends-on` 只声明真实产出/消费关系（TASK-01 为空）。
- **组映射（`write-dev-tasks` 三步断言的输入，`task_count_hint = 4`）**：G1 = 生产者 + 唯一构造器（FR-1、FR-2、FR-3、FR-5、FR-10 的代码侧、FR-13、FR-17 的构造面）→ TASK-01；G2 = CLI 投影与错误面（FR-4、FR-6）→ TASK-02；G3 = 活跃提示词与文档迁移 + OpenWiki 生成闭环（FR-7、FR-8、FR-16 的采纳口径）→ TASK-03；G4 = 测试迁移与契约退役保护（FR-9、FR-11、FR-12、FR-14 的完整性证明面）→ TASK-04。每组恰一个 TASK、每个 TASK 恰属一组，4 个 TASK 覆盖 SDD §6.2 的四个改动簇（生产者 11 站点 / CLI 5 处 / 提示词 5 + 文档 2 / 测试 8 文件）。

## 3. 资源与分工

- `cr.md` owners（权威）：requirement / development / test 均为 Ray（`assigned-at` 齐备，实施期从 `cr.md` 读取，不用本文件的缓存）。
- 实施执行：`dev-agent`（TASK-01…04）；测试报告由 `cr.md owners.test.id` 执行 `write-test-report` 并消费 `implement-code` 的真实验证结果；计划/代码评审由**新建的独立** `quality-reviewer-agent` task/run 执行（不自评、不复用作者会话）。
- 实施只写 `resources[].worktreePath` 指向的 worktree：tools 改动落 tools CR worktree，multica 改动落 multica CR worktree，过程文档落 KB worktree。

| TASK | 估时 | 仓库 | 说明 |
|---|---|---|---|
| CR-2026-064-TASK-01 | 16h | tools | `lib/workspace-transactions.mjs`：`buildRecovery` + 9 个生产者站点 + 局部名归位（单文件、单写者） |
| CR-2026-064-TASK-02 | 8h | tools | `crctl.mjs`：`buildRegisterResult` / `cmdRegister` / `cmdGate` / `cmdReviewLoopReset` / `crIdForRecover` 5 处 |
| CR-2026-064-TASK-03 | 12h | tools + multica | 4 份 tools SKILL + `README.md` + `openwiki/operations/crctl-transactions.md`（生成）+ multica `delivery-agent.md` |
| CR-2026-064-TASK-04 | 16h | tools | 7 个既有测试文件 + `contract-scan.test.mjs` 扩展 + 守卫断言 |

## 4. 风险与回滚策略

### 4.0 回滚单元（唯一：整体回滚，SDD §6.1 FR-15 / AC-13）

CR-R 是**单发布原子迁移**：生产者、消费者、旧字段删除与退役保护在同一个 CR 内完成。因此**回滚单元唯一 = 整个 CR**（`RU-ALL`）：

1. 合并前失败：revert 本 CR 全部四个 TASK commit（逆序 TASK-04 → 03 → 02 → 01），经**受控** `crctl git revert --no-edit <sha> --cwd <worktree>`（白名单形态 `^--no-edit (-m 1 )?\S+$`）。
2. 已发布版本若必须回退：回退到上一完整 `tools` 版本，**不得**在当前版本恢复旧字段双写。

**不提供部分回滚单元**：任何「部分生产者新合同 / 部分消费者旧合同」或「旧字段临时恢复」的分支状态都是 PRD FR-15 明确禁止的半迁移态。若实施期确认某 TASK 的 diff 完全独立（例如纯文本面），也仍需与整批同进退——该口径已在 SDD §9 `scope_out` 与 §6.1 FR-15 固定，本计划不新增第二种回滚定义。

### 4.1 风险表

| # | 风险 | 等级 | 应对 | 回滚 |
|---|---|---|---|---|
| R-01 | 迁移不彻底：遗漏站点或测试/提示词标题里的旧名残留 → 整树扫描面命中，`cmd-03` 与 `cmd-01` 内 contract-scan 用例红 | 高 | `cmd-03` 按 SDD §4.4-2 同一枚举重放「整树 − 两项精确路径」零命中断言并打印命中清单；`cmd-01` 内 `contract-scan.test.mjs` 的八条代表性命中用例证明范围非恒真；TASK-01…04 的完成标志各自含「本 TASK 触达文件零命中」 | RU-ALL |
| R-02 | OpenWiki 生成环境不可用（无 provider key / 无网络） | 中 | 按 SDD D-7 第 4 步：以**环境阻塞**上报（`ENVIRONMENT_MISMATCH`），**不得回退为手工编辑生成页**；生成命令 + 生成前后 diff + 页面零命中三条证据缺一不可（`cmd-06` 提供页面事实面）。是否由 owner 放宽前提由人工决定，不在本计划内自行降级 | RU-ALL |
| R-03 | `RETIRED_LEGACY`（CR-2026-041 的三个退役 Skill 名）被误并入整树扫描面 → 既有活跃文件（`lint-prompts.mjs` 禁止名单、`crctl.test.mjs` / `lint-prompts.test.mjs` 用例样本、`CUSTOM.md` 台账引述、`docs/` 历史报告、历史夹具）立刻误报 | 中 | 严格按 SDD §4.4-1「按名分范围」：`RETIRED_LEGACY` 保持既有显式 `ACTIVE_PATHS` 与既有断言**逐字不动**（CR-2026-041 的 `zero_diff` 范围），整树面只适用于两个恢复字段名；`cmd-01` 内既有两条 CR-2026-041 用例保持通过 | RU-ALL |
| R-04 | 测试文件自身含旧名字符串（用例标题、断言、`recover_command` 双投影用例）→ 全树扫描红 | 中 | TASK-04 逐文件迁移标题与断言（7 文件 + `crctl.test.mjs` 的 reset / gate / 成功结果字段集用例）；`cmd-03` 零命中兜底；禁止靠「加排除」消红（新增排除必须改 `deepEqual` 冻结值并被评审看见，SDD §4.4-3） | RU-ALL |
| R-05 | 站点 4（merge publication lag → `checkpoint`）的局部名 `checkpointRecoverCommand` 未随结构化一并改名，或改名后取值断裂 → 恢复方向丢失 | 中 | 按 SDD §11 计数口径原文（「随站点 4 结构化一并改写名称」）把该局部名改写为新合同口径名（`checkpointRecovery`）；TASK-01 完成标志含两条：改写后 `rg -n --case-sensitive "checkpointRecoverCommand"` 在 `tools` 仓**零命中**，且站点 4 的两个 `TxError` 的 `extra.recovery` 仍取该局部值（值类型由 shell string 变为 `buildRecovery(...)` 结果）；`cmd-01` 内 `merge-tx.test.mjs` 断言 `recovery.args` 指向 `checkpoint` 且 `cwd` 为 installRoot | RU-ALL |
| R-06 | reset 的 6 类 reason 向量在非 TTY 环境提前退出 → 用例恒真/恒假，AC-03 假绿 | 中 | 用既有 `runCrctlInTty` 包装（SDD §6.3 AC-03 可达性说明）；每类断言四件事：`args` 不含该值、`promptFor` 含 `reason`、`requiresTTY===true`、`JSON.stringify(recovery)` 中该值不出现（`cmd-01`） | RU-ALL |
| R-07 | 证据命令超出 `write-test-report` 节点 20 min 预算 | 中 | `cmd-01` 是 21 个 `*.test.mjs` 的**单条**全量命令（CR-2026-063 同仓同口径实测 848.2 s），加 `--test-concurrency=2 --test-reporter=dot`；`cmd-02`～`cmd-06` 均为秒级（见 §5.4）。**不拆分**套件：按文件分组会让墙钟上升（CR-2026-063 实测分组后 > 954 s） | 非代码缺陷，不触发回滚 |
| R-08 | 删除 `register` 双投影后，既有「成功结果字段集与改造前一致」类断言变红 | 中 | 该断言属 FR-6 授权的迁移面：TASK-04 同步更新为「字段集含 `recovery`、不含 `recoverCommand`/`recover_command`」；`cmd-01` 内 `register-tx.test.mjs` 的单投影断言即证据；不得放宽为「不检查字段集」 | RU-ALL |
| R-09 | 全树扫描面在**新增**文件上误报（未来在本仓落历史迁移/changelog 文档） | 低 | 这是 SDD D-5 明示的**取舍**（新增排除是显式且被断言的评审动作），非本 CR 的缺陷；本 CR 期间 `tools` 仓无此类文件，`cmd-03` 零命中即事实面 | RU-ALL |
| R-10 | 采集/扫描实现忽略行尾差异 → 跨行判定静默漏检（历史三次咬人点） | 中 | 全部读取先 `replaceAll('\r\n','\n')`；扫描面枚举为空、索引 0 条 active、索引与目录集合不相等一律**硬失败**（SDD §4.4-2 硬失败清单）；`cmd-03` 以扫描面规模下界（≥200）做空面哨兵 | RU-ALL |
| R-11 | `multica` 侧 `CUSTOM.md` 台账登记义务的边界判定 | 低 | SDD §1.1 的多仓变更边界只含 `cr-prompts-revised/delivery-agent.md`，本 CR 不改 `CUSTOM.md`：该文件行 `#75` 登记的事实（`cr-prompts-revised/` 是 tools 同名 Prompt 的对照快照、平台 DB 是部署投影）在本 CR 后仍然成立。若 owner/reviewer 判定需要补记，走上游 SDD 变更，不在 plan/TASK 内扩面 | 非代码缺陷，不触发回滚 |
| R-12 | 生成页与 README 被写进**第二套**合同描述（手工另写一段解释） | 低 | TASK-03 完成标志含「README 只原位改写既有条目、未新增恢复合同章节；OpenWiki 页不手工编辑」；`cmd-06` 断言页面与 README 的旧字段零命中且含结构化字段名 | RU-ALL |

无 DDL / 无 down 迁移 / 无数据回填语义（SDD §2.2：`recovery` 不落盘、不入 journal、不入账本）。回滚一律经受控 `crctl git` 形态执行。

## 5. 验收与发布策略

**估算总工时（TASK 账本口径）= 52h**（TASK-01 16h + TASK-02 8h + TASK-03 12h + TASK-04 16h）。

### 5.1 发布前 checklist

1. §6.2 的 cmd-01…cmd-06 逐条转录入 `cr-test-plan/v1` 并由 `crctl test` 执行且 **exit 0 且机器区每行 `skipped=false`**（cmd-NN 与 `test-evidence/cmd-NN.log` 一一对应，`sourceRevision` 绑定被测仓 HEAD）。
2. `write-test-report` `status=pass` 且 `blockers=[]`（命令集**只**来自 §6.2，不在 plan 之外另造命令；D-7 的生成命令与逐份核对结论写在 test-report 分析段，不冒充机器命令）。
3. 独立 `review-dev-plan` `verdict=pass`、`blockers=[]`（plan + TASK 合并评审）；`review-code` 同理。
4. `crctl approve --stage dev-start` 与 `--stage code` 均由人工（Ray）在交互式终端完成；**SDD 已被审批绑定，若实现期发现需改 SDD，必须走上游轨重新评审 + 二次人工审批**。
5. 交付 diff 在白名单内（§6.2 `cmd-05` tools 侧、`cmd-04` multica 侧、`cmd-06` KB 侧三条机器判据）；`zero_diff` 对象（SDD §9）零改动。
6. `multica` 侧只改 1 个文件；`CUSTOM.md` 台账边界见 R-11（本 CR 零改动 + 理由已记录）。
7. 无新增 SLO / 指标 / 计数门禁 / 账本字段 / Pipeline 节点 / 评审维度（PRD §6、§7；SDD §9 `scope_out`）。

### 5.2 发布与观测

- 无 feature-flag：本 CR 是原位迁移（字段改名 + 结构断言 + 退役扫描），不引入开关语义；不存在「新旧合同并存」的窗口（SDD §9 `scope_out` 明列不做双写）。
- **部署边界**：平台侧对 Agent / Skill 提示词的采纳由 owner 在本 CR 落地后另行执行（FR-16）；本 CR 只交付 owner 可复制版本（`multica/cr-prompts-revised/delivery-agent.md`），交付结论中不得出现平台侧已生效的声称。
- 发布经既有 CR merge 流程（merge / writeback / archive），不进交付 TASK；审计以 `approval.yml`、`merge-commits.yml`、checkpoint 元数据为准。
- 发布后按 PRD §6 成功指标核验（一次性事实，不引入运行期观测）：活跃范围内恢复结果字段名只剩 `recovery`；6 类 reason 向量全通过且 reason 不进 `args[]`；既有全量测试全绿且错误码/状态转换/txId/rollback/files 语义未变；contract-scan 命中即失败且对排除面不误报；盘点的六类无「已知调用方未迁移」遗留项；交付分支不存在半迁移中间态。

### 5.3 基线与既有事实

- 旧字段命中基线（唯一口径，SDD §11 开头：文件数 `rg -l`、行数 `rg -c` 逐文件求和、匹配次数 `rg -o` 计数；大小写敏感、不加 `-w`、用 rg 默认过滤、文件集为 commit 的 tracked 内容）：`tools@dddd0ad6` = **16 文件 / 72 行 / 87 次**；`multica@ab960948` = **3 文件 / 6 行 / 6 次**（其中 2 文件是历史黄金数据）。
- 扫描面规模口径（同一工作树枚举）：`tools@dddd0ad6` 枚举 **214** 文件 − 扫描器自身 **1** − 历史 traceability 精确路径 **1** = **扫描面 212**；`fixtures/` 内 4 个文件中 **3 个在面内**、1 个被排除。规模只作覆盖度报告写进断言消息，**不写脆弱等式**（SDD §4.4-4）。
- 无既有测试基线红：本 CR 触及的 21 个 `*.test.mjs` 与 `skills/writeback/scripts/test/writeback.test.mjs` 在 `tools@dddd0ad6` 上当前为全绿（本计划落笔时按 §5.4 在 tools CR worktree 实测，结果随本次汇报给出）；因此本计划**不登记任何基线红例外**，`cmd-01` / `cmd-02` 直接用 `--test-reporter=dot`，不加 `--test-skip-pattern`。

### 5.4 证据命令集的预算说明（`write-test-report` 节点 `timeoutMinutes=20`）

| 命令 | 预期时长量级 | 依据 |
|---|---|---|
| cmd-01 | 单条全量命令；CR-2026-063 同仓同规模实测 848.2 s（21 个 `*.test.mjs`），本次实测见 §5.3 | 已计入预算 |
| cmd-02 | 秒级～十秒级 | 单文件 `writeback.test.mjs` |
| cmd-03 / cmd-04 / cmd-05 / cmd-06 | 各秒级（纯文件读 + 字符串判定 + 一次 `crctl git diff`） | 无子进程套件、无网络 |

- 预算约束下**不允许**把 cmd-01 拆成多条顺序命令：拆分会让墙钟上升（CR-2026-063 实测 6 文件组 > 600 s、三组合计 > 954 s），全集单命令是唯一同时满足「无重不漏」与「≤ 20 min」的分区。
- 每条命令的 `timeoutSeconds` ≥ 该命令实测时长的安全倍数（cmd-01 声明 1500 s；其余 300 s / 120 s）。`timeoutSeconds` 是 kill-switch 上限，不参与预算比较。
- `cmd-03`～`cmd-06` 的 `-e` 脚本遵守既有转录纪律：单参数、脚本内不含双引号 / 反斜杠 / 换行 / `|`（需要这些字符时用 `String.fromCharCode(…)` 构造）、路径一律正斜杠化、可 `JSON.stringify` 往返逐字相同。

## 6. 两张稳定表（契约必填节，CR-2026-060 AC-07）

### 6.1 交付覆盖表（稳定表 1/2）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 唯一恢复合同字段 `recovery`（AC-01） | §2.1 字段表 + §3.1 类型 + §3.2 构造器（键序固定、可选性、恒定 `executable`）+ SDD-CLOSE-01 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02 的 CLI 投影面） | cmd-01 | RU-ALL |
| FR-2 argv 边界与参数完整性（AC-01） | §4.1 拆 token 六步 + 11 站点 `args` 取值表 + SDD-CLOSE-02 | CR-2026-064-TASK-01 | cmd-01（结构断言逐元素）、cmd-03（活跃面零命中） | RU-ALL |
| FR-3 `executable` 安全约束（AC-10） | §3.2 保证 1–2（`'node'` 恒定 + `args[0]` 为脚本路径）+ §4.5 守卫 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-04 的守卫断言） | cmd-01、cmd-05 | RU-ALL |
| FR-4 `promptFor[]` 人工输入行为（AC-03、SDD-CLOSE-03） | §3.4 值名 → CLI 入口映射 + §4.1 第 5 步（`reason` / `plan` / `CR-ID` 不进 `args`） | CR-2026-064-TASK-02（关联 CR-2026-064-TASK-04 的 6 类向量） | cmd-01 | RU-ALL |
| FR-5 全部已知生产者迁移（AC-01、AC-02） | §4.1 站点 1–9（9 处生产者构造）+ §3.3 载体表 + SDD-CLOSE-06 | CR-2026-064-TASK-01 | cmd-01、cmd-03 | RU-ALL |
| FR-6 CLI 投影迁移（AC-02） | §4.2 四步 + §3.3 站点 10/11（`gate` 错配、`reset` 提交失败）+ `register` 单投影 | CR-2026-064-TASK-02 | cmd-01 | RU-ALL |
| FR-7 全部活跃 Skill/Agent 消费者迁移（AC-05） | §4.3 消费方行 + §8 采纳完整性（5 处，无遗留采纳项）+ D-6 消费合同单一事实源 | CR-2026-064-TASK-03 | cmd-03、cmd-04、cmd-06 | RU-ALL |
| FR-8 文档迁移且不产生第二套合同（AC-05） | §4.3 `README.md` 行 + D-7 生成闭环（四步，不手工编辑生成页） | CR-2026-064-TASK-03 | cmd-03、cmd-06 | RU-ALL |
| FR-9 测试改为结构断言（AC-02、AC-07） | §4.5 结构断言模板 + 向量 3/4/5/6 + 反脆弱快照规则 | CR-2026-064-TASK-04 | cmd-01 | RU-ALL |
| FR-10 旧字段同 CR 删除、不留兼容路径（AC-05） | §4.1 第 6 步（原位删除、不并排双写）+ §2.3 别名表（无 alias/shim/fallback） | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02/03/04 的全量删除面） | cmd-03、cmd-04 | RU-ALL |
| FR-11 contract-scan 退役保护（AC-06、SDD-CLOSE-05） | §4.4 全节：分名名单 + 整树派生扫描面 + 两项精确路径排除 + 四条结构性断言 + 八条命中用例 + 不误报正反用例 | CR-2026-064-TASK-04 | cmd-01（`contract-scan.test.mjs` 在列）、cmd-03 | RU-ALL |
| FR-12 安全测试向量（AC-03、AC-10、AC-11） | §4.5 向量 3（参数边界）/ 4（6 类用户输入）/ 5（四类缺失）/ 6（shell 逃逸守卫） | CR-2026-064-TASK-04 | cmd-01、cmd-05 | RU-ALL |
| FR-13 既有语义零改变（AC-07、AC-08） | §2.2 不落盘 + §3.3 尾段（错误码/exit code/txId/rollback/files 不变）+ §4.2「只改载体」 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02 与 CR-2026-064-TASK-04 的回归面） | cmd-01、cmd-02、cmd-05 | RU-ALL |
| FR-14 实施前有界盘点（AC-12） | §11 依赖清单即基线盘点 + §4.3 逐文件清单；六类归档表见本计划 §8（plan 节点产物） | CR-2026-064-TASK-04（关联 CR-2026-064-TASK-01/02/03 的迁移面） | cmd-03、cmd-06 | RU-ALL |
| FR-15 整体回滚（AC-13） | §9 `scope_out` 与 §6.1 FR-15 + 本计划 §4.0（回滚单元唯一 = RU-ALL） | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02/03/04 同进退） | cmd-03（活跃面无半迁移态）、cmd-05 | RU-ALL |
| FR-16 回写与平台部署边界（AC-09、AC-14） | §1.1 范围表（不更新平台 DB）+ §8 平台部署边界 + §6.1 FR-16 | CR-2026-064-TASK-03（关联 CR-2026-064-TASK-04 的口径断言） | cmd-06 | RU-ALL |
| FR-17 合同确定性（AC-04、AC-11、SDD-CLOSE-04） | §2.4 指纹字段集 + §3.5 固定 5 步判定与四类错误闭包 + §3.1 零副作用 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02 构造、CR-2026-064-TASK-03 消费合同、CR-2026-064-TASK-04 守卫） | cmd-01、cmd-05 | RU-ALL |

**表注（防假绿）**

① 「验收证据」列按「主责命令在前」列出覆盖本行验收面的全部 `cmd-NN`；每个 `cmd-NN` 与 §6.2 证据命令表的 `证据ID`、`crctl test` 机器区 `commands` 1-based 下标、`test-evidence/cmd-NN.log` 三者全等。六个 `cmd-NN` 全部被本表引用；反向本表每个引用都在 §6.2 内有定义（双向可机械核对）。
② FR-14 的六类归档表是 **plan 节点产物**（本计划 §8），其完整性面的机器判据落在 CR-2026-064-TASK-04 的整树零命中扫描（`cmd-03`）与 CR 产物口径断言（`cmd-06`）——即「盘点声称的六类都已被同一口径的扫描面覆盖」，不是让 TASK 重新产出一份盘点表。
③ FR-15 的「回滚」列对该 CR 全部 FR 都是同一个 `RU-ALL`：PRD FR-15 / SDD §9 `scope_out` 禁止部分回滚与半迁移态，本计划不提供第二种回滚单元（§4.0）。
④ FR-16 的 `cmd-06` 只证明「本 CR 产物未声称平台侧已生效、KB 未提前产出 `specs/`/`delivery/`」；平台侧实际采纳动作不属本 CR 验收面（AC-09 的可达性说明）。
⑤ FR-7 的跨仓面（`multica`）由 `cmd-04` 覆盖，`tools` 整树扫描（`cmd-03`）不覆盖 `multica` 仓（SDD §4.4 跨仓边界为诚实口径：跨仓迁移由 §4.3 清单 + 有界盘点 + 本 CR 评审证明）。

### 6.2 证据命令表（稳定表 2/2）

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["--test","--test-concurrency=2","--test-reporter=dot","skills/shared/crctl/scripts/test/archive-tx.test.mjs","skills/shared/crctl/scripts/test/check-agents-contract.test.mjs","skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs","skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs","skills/shared/crctl/scripts/test/contract-scan.test.mjs","skills/shared/crctl/scripts/test/crctl.test.mjs","skills/shared/crctl/scripts/test/durable-tx.test.mjs","skills/shared/crctl/scripts/test/fault-harness.test.mjs","skills/shared/crctl/scripts/test/lint-prompts.test.mjs","skills/shared/crctl/scripts/test/merge-tx.test.mjs","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs","skills/shared/crctl/scripts/test/register-tx.test.mjs","skills/shared/crctl/scripts/test/test-cr.test.mjs","skills/shared/crctl/scripts/test/trace-outbox.test.mjs","skills/shared/crctl/scripts/test/trace-semantic.test.mjs","skills/shared/crctl/scripts/test/upgrade-check.test.mjs","skills/shared/crctl/scripts/test/version-set.test.mjs","skills/shared/crctl/scripts/test/workspace-freshness.test.mjs","skills/shared/crctl/scripts/test/workspace-resolver.test.mjs","skills/shared/crctl/scripts/test/writeback-tx.test.mjs","skills/shared/crctl/scripts/test/yaml-subset.test.mjs"]` | 1500 |
| cmd-02 | tools | . | node | `["--test","--test-reporter=dot","skills/writeback/scripts/test/writeback.test.mjs"]` | 600 |
| cmd-03 | tools | . | node | `["-e","const fs=require('fs'),path=require('path');;const R=process.cwd();;const NAMES=['recoverCommand','recover_command'];;const SKIP=['.git','node_modules'];;const EXCLUDED=['skills/shared/crctl/scripts/test/contract-scan.test.mjs','skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml'];;const rel=p=>path.relative(R,p).split(path.sep).join('/');;const walk=(d,out)=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);const r=rel(p);const seg=r.split('/');if(seg.some(s=>SKIP.includes(s)))continue;if(e.isDirectory())walk(p,out);else out.push(r);}};;const all=[];walk(R,all);;const surface=all.filter(r=>!EXCLUDED.includes(r)).sort();;const hit=(f)=>{const t=fs.readFileSync(path.join(R,f),'utf8').split(String.fromCharCode(13)+String.fromCharCode(10)).join(String.fromCharCode(10));return NAMES.some(n=>t.includes(n));};;const hits=surface.filter(hit);;console.log('enumerated = '+all.length);;console.log('scan surface = '+surface.length);;console.log('retired-name hits in surface = '+hits.length);;hits.forEach(h=>console.log('  HIT '+h));;const exHit=EXCLUDED.filter(hit);;console.log('excluded = '+EXCLUDED.length+' (of which hit = '+exHit.length+')');;exHit.forEach(h=>console.log('  EXCLUDED-HIT '+h));;const fx=surface.filter(r=>r.startsWith('skills/shared/crctl/scripts/test/fixtures/'));;console.log('fixtures in surface = '+fx.length);;fx.forEach(f=>console.log('  IN '+f));;const bad=[];;if(hits.length)bad.push('surface hits = '+hits.length);;if(EXCLUDED.length!==2)bad.push('excluded count = '+EXCLUDED.length);;if(exHit.length!==1)bad.push('excluded hit count = '+exHit.length);;if(fx.length!==3)bad.push('fixtures in surface = '+fx.length);;if(surface.length<200)bad.push('scan surface suspiciously small = '+surface.length);;if(bad.length){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);};console.log('scan-audit failures = 0');"]` | 300 |
| cmd-04 | multica | . | node | `["-e","const fs=require('fs'),path=require('path'),cp=require('child_process');;const R=process.cwd();;const NAMES=['recoverCommand','recover_command'];;const DIR='cr-prompts-revised';;const NL=String.fromCharCode(10);;const pick=(...v)=>{for(const x of v)if(x)return String(x);return '';};;const bad=[];;const files=fs.readdirSync(path.join(R,DIR)).filter(f=>f.endsWith('.md'));;const hits=files.filter(f=>{const t=fs.readFileSync(path.join(R,DIR,f),'utf8');return NAMES.some(n=>t.includes(n));});;console.log('cr-prompts-revised md files = '+files.length);;console.log('retired-name hits = '+hits.length);;hits.forEach(h=>console.log('  HIT '+DIR+'/'+h));;if(hits.length)bad.push('prompt hits = '+hits.length);;const dev=fs.readFileSync(path.join(R,DIR,'delivery-agent.md'),'utf8');;if(!dev.includes('recovery'))bad.push('delivery-agent.md 未改读结构化 recovery');;if(NAMES.some(n=>dev.includes(n)))bad.push('delivery-agent.md 仍含退役字段名');;const gold=['server/internal/governance/testdata/traceability-golden.yml','server/internal/governance/testdata/traceability-golden.json'];;for(const g of gold){const t=fs.readFileSync(path.join(R,g),'utf8');if(!NAMES.some(n=>t.includes(n)))bad.push('历史黄金数据不含旧字段名（排除依据失效）: '+g);};;const CRCTL='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-064/skills/shared/crctl/scripts/crctl.mjs';;const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','ab9609483d17db12117cb8e9adb2d896f413917d','--cwd',R],{encoding:'utf8'});;if(r.status!==0){bad.push('crctl git diff 失败: '+pick(r.stderr,r.stdout).trim());}else{const parts=String(pick(r.stdout)).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const names=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);;console.log('multica diff paths = '+names.length);;names.forEach(f=>console.log('  '+f));;const want=[DIR+'/delivery-agent.md'];;for(const f of names)if(!want.includes(f))bad.push('multica diff 越界路径: '+f);;for(const f of want)if(!names.includes(f))bad.push('multica diff 缺少应改文件: '+f);};;if(bad.length){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);};console.log('multica-audit failures = 0');"]` | 300 |
| cmd-05 | tools | . | node | `["-e","const fs=require('fs'),path=require('path'),cp=require('child_process');;const R=process.cwd();;const NL=String.fromCharCode(10);;const pick=(...v)=>{for(const x of v)if(x)return String(x);return '';};;const bad=[];;const SKIPS=['.git','node_modules'];;const walk=(d,out)=>{for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);const r=path.relative(R,p).split(path.sep).join('/');if(e.isDirectory()){if(SKIPS.includes(e.name))continue;walk(p,out);}else if(r.endsWith('.mjs'))out.push(r);}};;const lib=[];walk(path.join(R,'skills/shared/crctl/scripts/lib'),lib);;const guard=['skills/shared/crctl/scripts/crctl.mjs'].concat(lib);;const BAD=['shell: true','shell:true','Invoke-Expression'];;for(const f of guard){const t=fs.readFileSync(path.join(R,f),'utf8');for(const s of BAD)if(t.includes(s))bad.push('shell 逃逸守卫命中: '+f+' 含 '+s);};;const CRCTL=path.join(R,'skills/shared/crctl/scripts/crctl.mjs');;const r=cp.spawnSync(process.execPath,[CRCTL,'git','diff','--name-only','dddd0ad63fb79bd7608314b4553f30e8ce7b7289','--cwd',R],{encoding:'utf8'});;if(r.status!==0){bad.push('crctl git diff 失败: '+pick(r.stderr,r.stdout).trim());}else{const parts=String(pick(r.stdout)).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const names=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);;console.log('tools diff paths = '+names.length);;names.forEach(f=>console.log('  '+f));;const WL=['README.md','openwiki/operations/crctl-transactions.md','skills/shared/crctl/SKILL.md','skills/cr/cr-archive/SKILL.md','skills/sync/push-progress/SKILL.md','skills/writeback/merge-feature-branch/SKILL.md','skills/shared/crctl/scripts/crctl.mjs','skills/shared/crctl/scripts/lib/workspace-transactions.mjs','skills/shared/crctl/scripts/test/contract-scan.test.mjs'];;const inScope=f=>WL.includes(f)?true:['archive-tx','checkpoint-tx','crctl','merge-tx','register-tx','workspace-freshness','writeback-tx'].map(n=>'skills/shared/crctl/scripts/test/'+n+'.test.mjs').includes(f);;for(const f of names)if(!inScope(f))bad.push('tools diff 越界路径（不在 SDD §1.1 白名单）: '+f);};;if(bad.length){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);};console.log('tools-guard-audit failures = 0');"]` | 300 |
| cmd-06 | ai-first-platform-docs | . | node | `["-e","const fs=require('fs'),path=require('path'),cp=require('child_process');;const R=process.cwd();;const NL=String.fromCharCode(10);;const pick=(...v)=>{for(const x of v)if(x)return String(x);return '';};;const bad=[];;const CR='change-requests/CR-2026-064';;const plan=fs.readFileSync(path.join(R,CR,'plan.md'),'utf8');;const cats=['producer','code consumer','Prompt-Skill consumer','active test','active docs','historical evidence'];;for(const c of cats)if(!plan.includes(c))bad.push('plan.md 六类归档缺少类别: '+c);;const TOOLS='C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-064';;const NAMES=['recoverCommand','recover_command'];;for(const f of ['README.md','openwiki/operations/crctl-transactions.md']){const t=fs.readFileSync(path.join(TOOLS,f),'utf8');if(NAMES.some(n=>t.includes(n)))bad.push('活跃文档仍含退役字段名: '+f);};;const page=fs.readFileSync(path.join(TOOLS,'openwiki/operations/crctl-transactions.md'),'utf8');;for(const k of ['recovery','executable','args','promptFor'])if(!page.includes(k))bad.push('OpenWiki 页缺少结构化合同字段名: '+k);;const claim=['平台 DB','已部署'].join('');;const tdir=path.join(R,CR,'tasks');;const arts=[path.join(R,CR,'plan.md')].concat(fs.existsSync(tdir)?fs.readdirSync(tdir).filter(f=>f.endsWith('.md')).map(f=>path.join(tdir,f)):[]);;for(const a of arts){const t=fs.readFileSync(a,'utf8');if(t.includes(claim))bad.push('CR 产物出现部署声称: '+path.relative(R,a));};;const r=cp.spawnSync(process.execPath,['C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-064/skills/shared/crctl/scripts/crctl.mjs','git','diff','--name-only','9079005fa5b0a3c4be482b089dcd1ff86819d020','--cwd',R],{encoding:'utf8'});;if(r.status!==0){bad.push('crctl git diff 失败: '+pick(r.stderr,r.stdout).trim());}else{const parts=String(pick(r.stdout)).split(NL);const b=parts.findIndex(l=>l.trim()==='{');const names=parts.slice(0,b<0?parts.length:b).map(s=>s.trim()).filter(Boolean);;console.log('KB diff paths = '+names.length);;names.forEach(f=>console.log('  '+f));;for(const f of names)if(!(f.startsWith(CR+'/')?true:f==='change-requests/_backlog.yml'))bad.push('KB diff 越界路径: '+f);};;if(bad.length){bad.forEach(b=>console.log('FAIL '+b));process.exit(1);};console.log('kb-audit failures = 0');"]` | 300 |

**args 列口径（转录纪律，逐条可机械核对）**

① `args` 为 JSON token 数组，**直接就是 `cr-test-plan/v1` 的 `args` 字段原文**：`write-test-report` 逐字转录，不得重新排版、不得取消转义、不得改写引号。
② `cmd-03`～`cmd-06` 的 `-e` 脚本是**单参数**：脚本内不含双引号、反斜杠、换行与 `|`（需要 CRLF 常量与换行处用 `String.fromCharCode(13)`/`String.fromCharCode(10)` 拼接，需要 `|` 处一律改用多元素数组或 `includes`），因此 `JSON.stringify` 往返逐字相同。
③ **路径注入一律正斜杠化**（`C:/Users/…`），跨仓脚本用绝对路径；`cwd` 为对象仓 worktree 内的相对路径（本 CR 全部为 `.`），`repo` 列 = **验收对象仓**，即 `crctl test` 计算 `sourceRevision` 的绑定面。
④ **被读仓 revision 的绑定**：`cmd-01`/`cmd-02`/`cmd-03`/`cmd-05` 的 `repo=tools` 绑定 tools HEAD（`dddd0ad6`）；`cmd-04` 的 `repo=multica` 绑定 multica HEAD（`ab960948`），其内部经绝对路径执行 tools 的 `crctl.mjs`（`crctl git`）读取 multica worktree；`cmd-06` 的 `repo=ai-first-platform-docs` 绑定 KB HEAD，其内部读 tools worktree 与 KB worktree 两侧文件（tools 侧 revision 由同表 `cmd-03`/`cmd-05` 绑定）。跨仓断言的证据面 = 「对象仓 `sourceRevision`」+「被读仓 `sourceRevision`」两条记录的组合。
⑤ 无 shell 字符串、无 pipe/redirect、无 env、无 `command` 字段、无绝对 `cwd`、无 `continueOnError`；`executable` 直接可 spawn（`node`）。
⑥ `cmd-01` 的 21 个文件枚举 = `skills/shared/crctl/scripts/test/*.test.mjs` 全集，按文件名升序，每文件恰好一次（非测试辅助模块 `merge-fixture.mjs` 不在枚举内，它由 `merge-tx.test.mjs` import 而被真实执行）。
⑦ `cmd-03` 的扫描面枚举规则与 SDD §4.4-2 **共用同一规则**：整树递归、按路径段跳过 `.git`/`node_modules`、减两条精确路径排除；排除集合与 `SKIP_DIRS` 的 `deepEqual` 冻结在 `contract-scan.test.mjs` 内（`cmd-01`），`cmd-03` 只做同一口径的独立重放与命中清单输出。

### 6.3 各命令覆盖的验收面（人读摘要；权威文本以 §6.2 行内为准）

- **cmd-01（repo=tools）**：AC-01 五键结构与 `args` 逐元素断言、AC-02 八类恢复路径结构化、AC-03 6 类 reason 向量（`runCrctlInTty` 包装）、AC-04 部分（守卫断言随测试文件执行）、AC-06 八条命中用例 + 不误报正反用例 + `EXCLUDED`/`SKIP_DIRS` 冻结 + 索引一致性硬失败、AC-07/AC-08 全量回归、AC-10 `executable`/`args[0]` 断言、AC-11 生产者形状。
- **cmd-02（repo=tools）**：AC-07 的 writeback 侧回归面（`skills/writeback/scripts/test/writeback.test.mjs`，SDD §6.3 AC-07 的第二条命令）。
- **cmd-03（repo=tools）**：AC-05/AC-06/AC-13 的「活跃面零命中 + 排除恰好两项 + 排除必需（被排除的历史 traceability 仍含旧名）+ `fixtures/` 内 3 个活跃向量在面内 + 扫描面规模哨兵」事实面。
- **cmd-04（repo=multica）**：AC-05 的跨仓提示词面（`cr-prompts-revised/*.md` 零命中 + `delivery-agent.md` 已改读结构化 `recovery`）+ 历史黄金数据仍含旧名（排除依据未失效）+ multica diff 白名单（恰 1 文件）。
- **cmd-05（repo=tools）**：AC-04（`shell: true` / `Invoke-Expression` 在 `crctl.mjs` 与 `lib/*.mjs` 零命中）+ tools diff 白名单（9 个具名路径 + 7 个既有测试文件）。
- **cmd-06（repo=ai-first-platform-docs）**：AC-12（plan.md 六类归档齐备）+ AC-05 文档面（`README.md` 与 OpenWiki 页零旧名、页面含结构化字段名）+ AC-09/AC-14 的 KB 侧边界（无部署声称、KB diff 只落 CR 过程文档与 `_backlog.yml` 投影）。

## 7. AC/业务闭环覆盖矩阵（契约必填节，CR-2026-057 FR-8）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-01 全部可恢复结果使用 `recovery`、`args[]` 逐参数且有序、无等价 shell string 备用入口 | §2.1 + §3.1 + §3.2 + §4.1 站点 1–9 | CR-2026-064-TASK-01 | cmd-01 |
| AC-02 八类恢复路径（register / workspace / merge / checkpoint / writeback / archive / test / reset）测试全绿且断言结构化 | §4.1 + §4.2 + §3.3 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02、CR-2026-064-TASK-04） | cmd-01 |
| AC-03 reason 不进 `args[]`、不进 shell string；`promptFor` 含 `reason`；6 类输入序列化后仍为数据 | §3.4 + §3.5 + §4.1 站点 11 + §4.5 向量 4 | CR-2026-064-TASK-02（关联 CR-2026-064-TASK-04） | cmd-01 |
| AC-04 代码消费者使用 argv 边界执行，无 `shell: true` / `Invoke-Expression` 用于恢复动作 | §3.5 副作用段 + §4.5 向量 6 | CR-2026-064-TASK-04 | cmd-05 |
| AC-05 活跃源码 / Skill / Agent / Pipeline / README / 活跃测试均不再消费旧字段；无 alias / shim / fallback | §4.3 逐文件清单 + §4.4 + D-7 + §8 采纳表 | CR-2026-064-TASK-03（关联 CR-2026-064-TASK-01、CR-2026-064-TASK-02、CR-2026-064-TASK-04） | cmd-03、cmd-04、cmd-06 |
| AC-06 旧字段仅存于历史证据 / 迁移文档 / 退役名单；扫描命中即失败、对允许排除面不误报 | §4.4-1/2/3/4 + SDD-CLOSE-05 | CR-2026-064-TASK-04 | cmd-01、cmd-03 |
| AC-07 crctl / ledger / freshness / merge / writeback / archive 全量测试通过 | §6.3 AC-07 可达性（两条命令）+ §2.2/§3.3 零语义变更 | CR-2026-064-TASK-04（关联 CR-2026-064-TASK-01、CR-2026-064-TASK-02） | cmd-01、cmd-02 |
| AC-08 未改变错误码 / 状态转换 / transaction id / rollback / files 语义 | §3.3 尾段 + §4.2「只改载体」+ §2.2 不落盘 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02） | cmd-01、cmd-05 |
| AC-09 平台侧 Prompt 采纳由 owner 在 CR 之后执行；本 CR 产物不出现平台侧已生效的声称 | §1.1 范围表 + §8 平台部署边界 | CR-2026-064-TASK-03 | cmd-06 |
| AC-10 `executable` 不含空格分隔参数与任何 shell 运算符；node 形态脚本路径在 `args[0]` | §3.2 保证 1–2 + §4.5 向量 3 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-04） | cmd-01 |
| AC-11 四类合同缺失场景停止并报错、零副作用、不回退旧字段；按固定顺序给出唯一结论 | §3.5 判定顺序 + D-6 消费合同 + §3.1 零副作用 | CR-2026-064-TASK-03（关联 CR-2026-064-TASK-01、CR-2026-064-TASK-04） | cmd-01、cmd-05 |
| AC-12 实施计划存在一次有界盘点的六类归档；未新增持续观测机制 | §11 依赖清单 + §4.3；归档表见本计划 §8 | CR-2026-064-TASK-04（关联 CR-2026-064-TASK-01/02/03） | cmd-03、cmd-06 |
| AC-13 交付分支不存在部分生产者新合同 / 部分消费者旧合同的中间态；回滚为整体回滚 | §9 `scope_out` + §6.1 FR-15 + 本计划 §4.0 | CR-2026-064-TASK-01（关联 CR-2026-064-TASK-02/03/04） | cmd-03、cmd-05 |
| AC-14 正常 writeback 所需的 `specs/` 与 `delivery/` 更新包含在本 CR 内 | §9 `scope_in` + §6.1 FR-16（由 `feature-writeback` 节点产出） | CR-2026-064-TASK-03 | cmd-06 |

**矩阵表注**：① 关键 AC（影响主路径验收可达性，含成功/失败/隔离/幂等）共 14 条，逐行给出唯一 TASK owner；每行「验收证据」均为稳定标识 `cmd-NN`，与 §6.1/§6.2 全等。② AC-14 的可达性动作发生在 `feature-writeback` 节点，本阶段的证据面是 `cmd-06` 的 KB diff 白名单（本阶段**不得**提前产出 `specs/`、`delivery/`），不在本计划内伪造 writeback 产物。③ AC-11 的消费方是提示词而非本仓代码（SDD D-6）：其验证面是「提示词文本逐条可核对 + 生产者形状断言 + 旧字段结构上不可回退」，`cmd-01`/`cmd-05` 覆盖后两者，提示词文本面由 `review-code` 逐条比对（SDD §6.3 AC-11 可达性说明）。

## 8. FR-14 有界盘点归档（六类，本节点产出；口径 = SDD §11 的唯一计数口径）

> 本节即 AC-12 要求的「一次有界盘点」结果，按 producer / code consumer / Prompt-Skill consumer / active test / active docs / historical evidence（排除）六类归档。盘点在 `tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289`（tools CR worktree，clean、tracked 内容）与 `multica@ab9609483d17db12117cb8e9adb2d896f413917d` 上执行，命令为 `rg -l / rg -c / rg -o "recoverCommand|recover_command"`（大小写敏感、不加 `-w`、rg 默认过滤）。**不新增任何持续观测机制**（PRD FR-14 尾句）。

| 类别 | 文件（repo / path） | 行 / 次 | 本 CR 处置 |
|---|---|---|---|
| **producer**（构造恢复动作的代码） | `tools/skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 23 / 25 | 迁移：新增唯一构造器 `buildRecovery` + 11 个站点原位结构化 |
| **code consumer**（消费/投影恢复动作的代码） | `tools/skills/shared/crctl/scripts/crctl.mjs` | 6 / 10 | 迁移：双投影删除、`gate` 错配与 `reset` 失败分支结构化、字段改名 |
| **Prompt-Skill consumer**（提示词面消费方） | `tools/skills/cr/cr-archive/SKILL.md`、`tools/skills/sync/push-progress/SKILL.md`、`tools/skills/writeback/merge-feature-branch/SKILL.md`、`tools/skills/shared/crctl/SKILL.md`、`multica/cr-prompts-revised/delivery-agent.md` | 6/7、2/3、1/1、2/2（tools）；2/2（multica） | 迁移：改读 `recovery.executable/args/cwd/requiresTTY/promptFor`；`crctl/SKILL.md` 新增「`recovery` 消费合同」小节 |
| **active test**（活跃测试面） | `tools/skills/shared/crctl/scripts/test/{crctl,register-tx,archive-tx,merge-tx,checkpoint-tx,writeback-tx,workspace-freshness}.test.mjs` | 11/13、4/4、3/4、3/5、2/2、2/4、1/1 | 迁移：字符串包含断言 → 结构/argv 断言（含 6 类 reason 向量与参数边界向量） |
| **active docs**（活跃文档与生成页） | `tools/README.md`（1/1，原位迁移）、`tools/openwiki/operations/crctl-transactions.md`（3/3，**生成物**：由既有 `openwiki code --update` 从迁移后源码重新生成并核对，D-7） | 1 / 1；3 / 3 | 迁移：README 原位改读结构化合同；生成页不手工编辑 |
| **historical evidence（排除）** | `tools/skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`（2/2）、`multica/server/internal/governance/testdata/traceability-golden.yml`（2/2）、`.../traceability-golden.json`（2/2） | 2 / 2 每个 | 排除：本 CR 不改写（PRD FR-11 允许排除的历史 traceability / 历史黄金数据；`tools` 侧以**精确路径**排除，见 SDD §4.4-3） |

**盘点合计**：`tools` = 16 文件 / 72 行 / 87 次；`multica` = 3 文件 / 6 行 / 6 次。上表六类各含 ≥1 条记录，**无「已知调用方未迁移」遗留项**：producer（1）+ code consumer（1）+ Prompt-Skill consumer（5）+ active test（7）+ active docs（2）= 16 个迁移对象，与 `tools` 16 文件 / `multica` 1 文件的迁移集合逐条对应；其余 3 个命中文件全部归入 historical evidence（排除）。

**收口对照（本计划相对 SDD 的唯一增量）**：本计划不新增设计决策、不改 SDD 任何字节；相对 SDD 的增量仅为「把 SDD §4.3/§11 的清单与 §6.2 的改动簇翻译为四个 TASK、两条稳定表与一组可执行证据命令」。SDD 遗留的三处未闭合项全部按 SDD 口径承接：① D-7 的 OpenWiki 生成（TASK-03 完成条件 + R-02 环境阻塞口径）；② FR-14 的六类归档（本节，plan 节点产出）；③ §9 `follow_up` 两项（`release-drift` 重跑方向、`tools/agents/delivery-agent.md` 与 multica overlay 的不同步）**不在本 CR 内处置**，本计划不为其建 TASK。
