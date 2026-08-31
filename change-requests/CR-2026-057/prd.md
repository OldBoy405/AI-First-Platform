---
id: CR-2026-057-prd
type: PRD
cr-ref: CR-2026-057
title: CR 全生命周期最小改造 — 评审闭合、范围冻结、覆盖矩阵与版本事实统一
target-version: unassigned
owner: Ray
owner-role: requirement
status: draft
created: 2026-08-31T17:25:00+08:00
updated: 2026-08-31T17:50:00+08:00
---

# 1. 概述

## 1.1 问题陈述

AIFI-14（CR-2026-056）已归档，质量门槛本身多数正确，但没有在正确阶段以完整闭环和唯一事实源传递，导致：

1. PRD 首轮未按完整契约域检查，同一 API 契约的缺口分批暴露为后续 blocker。
2. SDD 在修复真实架构问题的同时，曾把 PRD 明确排除的路径重新纳入设计（范围回摆）。
3. PLAN/TASK 未先验证「AC/业务闭环 → 唯一 TASK owner → 证据」，关键闭环在评审后才补 TASK。
4. 流程控制步骤（merge / writeback / archive）被建成交付 TASK，与「归档前全部 TASK 必须 done」形成循环。
5. `cr.md` / PRD / PLAN 的 `target-version` 为 `tbd`，writeback 产物使用 `0.29`，版本事实分叉。
6. 关键测试被 SKIP 时，命令 exit 0 仍被机器区记为 pass，审批前缺少「未执行」标记。

来源：AIFI-15 附件《AIFI-14-CR全生命周期复盘与最小改造方案》定稿（对应 Issue AIFI-15）。本 CR 落实该附件 §7（P0-1～P1-3），验收对齐 §9。

## 1.2 解决方案摘要

只改现有 Skill 判断、文档模板、`crctl` 守卫/账本写入点和必要回归测试，不新增 Agent、Pipeline、状态机状态或转换、review ledger、事务框架或第二套 Git/账本机制。

```text
注册：人工确定 target_version（真实版本或 unassigned，禁止 tbd 及同义值）
PRD 评审：按完整契约域首轮一次闭合
SDD 审批后：冻结批准范围（scope_in / scope_out / zero_diff / follow_up）
PLAN：AC/业务闭环覆盖矩阵，关键 AC 必须有唯一 TASK owner
TASK：禁止把 merge/writeback/archive/「完成于 merge 的发布准备」建成交付 TASK
代码评审范围冲突：只回 implement-code（不新开上游设计轨）
测试：关键证据 SKIP ≠ pass；skip 以机器区 skipped 字段为准
版本更正：crctl version-set 单向 unassigned→真实版本，同步已有派生产物
Write-back：只校验并消费同一 target_version；版本失败在 candidate/journal 之前
```

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

基于 AIFI-14 全生命周期复盘，对现有 Skill / 模板 / crctl 做最小改造：优化 review 首轮完整性与 blocker 分级（P0-1）；SDD 审批后冻结批准范围供下游只读消费（P0-2）；PLAN 增加 AC/业务闭环覆盖矩阵（P0-3）；禁止把 merge/writeback/archive 建成交付 TASK（P0-4）；target_version 在注册阶段人工确定，禁止 tbd，未排期用 unassigned，writeback 只校验消费（P1-1）；收紧关键测试 skip 的 pass 语义（P1-2）；静态检查仅在同类问题重复失败且规则确定时下沉（P1-3）。不新增 Agent、Pipeline、状态、review ledger、事务框架。不含 AIFI-14 历史产物回写修复。

目标仓：sibling `../tools/`（Skill、模板、`crctl`、README、回归测试）。knowledge-base 只承载本 PRD；`../multica/` 无实施改动。

本 CR 自身 `target-version` 为 `unassigned`（发起人未排期，按 P1-1 新规则登记，不使用 `tbd`）。后续 PRD / SDD / PLAN / TASK 必须继承该值，不得自行改写。writeback 前若需发布，须经下方 FR-15 的 `crctl version-set` 改为真实版本，并同步已存在的派生产物。

## 1.4 当前代码事实（落笔前核实）

基线：tools 仓当前 `custom/main` 工作区；knowledge-base 归档点 `91d95de`（CR-2026-056）。本轮命令核实：

| 结论 | 证据 |
|---|---|
| `register` 缺 `--target-version` 时默认写入 `tbd` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` `targetVersion = input.targetVersion ?? 'tbd'` |
| `requirement-register` SKILL 将 `target_version` 标为可选 | `skills/requirement/requirement-register/SKILL.md` 参数表 |
| `requirement-authoring` Pipeline 已将 `target_version` 标为必填输入 | `pipeline-templates/requirement-authoring.pipeline.json` inputs |
| `writeback-apply` 要求非空 `targetVersion`，但不与 `cr.md` 比对，也不拒绝 `unassigned` | `workspace-transactions.mjs` `prepareWritebackCandidate`：仅 `WRITEBACK_VERSION_INVALID`（空值） |
| `prepareWritebackCandidate` 在 generator 前 `rmSync`+`mkdir` candidate 目录 | 同文件 `prepareWritebackCandidate` |
| `writeback-apply` 版本检查若放在 prepare 之后会留下 candidate | 同文件 `applyWritebackAtomic` 先 resolveOperationalWorkspace，后 prepare |
| 无 `crctl version-set` 子命令 | `crctl.mjs` help / switch |
| `write-dev-plan` 缺省仍写 `target-version: {target_version 或 tbd}` | `skills/develop/write-dev-plan/SKILL.md` |
| SDD 模板无「批准范围」四字段章节 | `skills/shared/engineering-docs/templates/SDD-template.md` 第 1–9 节 |
| `write-tech-design` 契约章节 1–8，无批准范围必填节 | `skills/develop/write-tech-design/SKILL.md` |
| `write-dev-plan` 无 AC→TASK owner 覆盖矩阵节 | 同 Skill 章节 1–5 |
| `write-dev-tasks` 未禁止 merge/writeback/archive 交付 TASK | `skills/develop/write-dev-tasks/SKILL.md` |
| `review-requirement` 首轮维度无完整契约域 | `skills/requirement/review-requirement/SKILL.md` Step 2：结构/可测试性/范围/规划对齐/依赖 |
| `review-tech-design` 已有首轮全量汇总与旧 blocker 回修复核 | 同 Skill Step 2.2；需推广到其余 review Skill 并补范围核对外壳 |
| `review-dev-plan` 有 SDD→plan 覆盖，无「关键 AC 唯一 TASK owner」硬规则；双轨已存在 | 同 Skill Step 2 / 增量职责；`repair-target` 枚举 `write-dev-plan` \| `write-tech-design` |
| `review-code` block 固定回 `implement-code`；schema 与 `REVIEW_REPAIR_TARGETS.code` 均无上游设计轨 | `skills/develop/review-code/SKILL.md` Step 5；`crctl.mjs` `REVIEW_REPAIR_TARGETS` |
| `review-code` 以 `test-report.status=pass`（命令 exit 0）为进入审批前提 | 同 Skill Step 1、Step 5 |
| `crctl test` 按计划下标生成 `test-evidence/cmd-NN.log`；机器区无 `skipped` 字段 | `workspace-transactions.mjs` `runTestPlan` / `renderTestMachineReport` |
| `crctl task done` 仅允许 `developing`；其它状态 `ILLEGAL_LEDGER_STATE` 零写 | `crctl.test.mjs`「task done：非 developing 态」 |
| CR-2026-039 已删除 canonical 字段 `fixed-blockers` / `repair-instructions` / `suggestion_policy`，`contract-scan.test.mjs` 对 11 个 SKILL 与 3 条 CR Pipeline 零命中 | `skills/shared/crctl/scripts/test/contract-scan.test.mjs` |
| 归档门禁已有 `deliveryIndexComplete` | `skills/shared/crctl/gates.json` |
| 本 CR 注册值 | `change-requests/CR-2026-057/cr.md`：`target-version: unassigned`，`status: drafting` |

# 2. 用户故事

- **US-1 需求评审人**：作为 `review-requirement` 执行者，我希望首轮按完整契约域一次报告同一契约的全部独立缺口，从而避免下一轮才把建议升级为 blocker。
- **US-2 技术设计作者**：作为 `write-tech-design` 执行者，我希望 SDD 用固定章节写明 scope-in / scope-out / zero_diff / follow_up，从而审批后下游不能把兼容性背景做成当前 TASK。
- **US-3 开发计划作者**：作为 `write-dev-plan` 执行者，我希望每条关键 AC 或业务闭环都有唯一 TASK owner 和验收证据，从而开发启动前就能发现覆盖空洞。
- **US-4 任务拆分作者**：作为 `write-dev-tasks` 执行者，我希望 merge / writeback / archive 不被建成交付 TASK，从而归档门禁不会和任务完成条件互相卡住。
- **US-5 需求发起人**：作为注册 CR 的人，我希望在注册时人工给出 `target_version`（或确认 `unassigned`），后续阶段只继承该值，从而 writeback 不会突然改成另一个版本。
- **US-6 代码评审人**：作为 `review-code` 执行者，我希望覆盖矩阵中的关键测试被 skip 时，审批前结果明确标成未执行，而不是因为 exit 0 被当成 pass。
- **US-7 平台维护者**：作为 tools 仓维护者，我希望只在同类失败再次出现且规则已确定时，才往现有脚本加小检查，从而不预先堆一套新的静态检查框架。

# 3. 功能需求

## 3.1 P0-1 优化现有 review Skill

**FR-1 首轮完整契约域**

各 review Skill 只改业务判断和输出约束，不改状态机、`review-record` schema 必填字段集、attempt 账本。

首轮必须在生成 verdict 前完成全部适用维度，同一契约域的独立缺口必须出现在同一轮 blockers，不得在首个 blocker 处提前结束。

契约域闭合清单（按科目选用，缺适用项须显式写 N/A 及原因）：

| 科目 | 必须一次检查的闭包 |
|---|---|
| HTTP API（PRD/SDD 新增或修改时） | endpoint、request、response、error、权限、幂等、状态、验收观察点 |
| crctl / CLI | 命令与 flag、输入约束、JSON/stdout 输出、错误码、调用者约束、幂等、状态副作用、验收观察点 |
| Skill 契约 | 必填参数、落盘路径、允许的状态转换、失败码、与 `crctl` 的唯一写入边界 |

具体落点：

- `review-requirement`：当 PRD 定义用户可调用契约（HTTP 或 CLI/Skill）时，按上表一次检查；同一契约域的独立缺口同轮列出。
- `review-tech-design`：先核对批准范围（FR-5），再检查真实 symbol、签名、调用者闭包、依赖方向、事务和锁序；保留现有 Step 2.2 首轮全量规则。
- `review-dev-plan`：先检查 `FR/AC → SDD 落点 → PLAN → TASK owner → evidence` 覆盖（FR-8），再检查单个任务细节。
- `review-code`：检查实际 diff、所有调用者和关键失败路径；区分测试未执行、测试失败和业务缺陷（与 FR-16 衔接）。

本 CR 自身引入的三条 CLI（`register --target-version`、`writeback-apply --target-version`、`version-set`）必须按上表「crctl / CLI」行一次闭合，规范见 FR-12 / FR-14 / FR-15，不得把错误码、幂等或负向向量留到 SDD 再发明。

**FR-2 blocker / suggestion 分级**

影响当前实现唯一性或当前验收可达性的缺口必须是 blocker。只影响表达、未来优化或后续 CR 的内容必须是 suggestion。不得把 suggestion 批量升级为 blocker，也不得把当前验收不可达的问题留作 suggestion。

**FR-3 每轮评审报告结构**

每轮 review 输出必须能让下一轮机械区分旧 blocker 状态、本轮新 blocker、范围外发现。承载方式复用现有临时 payload + `crctl review-record`（`verdict` / `blockers` / `dimensions` / `suggestions`）。

四个 review Skill（`review-requirement` / `review-tech-design` / `review-dev-plan` / `review-code`）的 `blockers[]` 与 `suggestions[]` 每条文本必须使用下列固定前缀之一（ASCII 全角冒号 `：`，前缀后可跟空格与正文；禁止自创同义前缀）：

| 前缀 | 含义 | 写入位置 |
|---|---|---|
| `已解决：` | 上一轮某条 blocker 本轮已关闭 | `suggestions`（关闭项不得再进入本轮 `blockers`） |
| `部分解决：` | 上一轮某条 blocker 仍有残留 | `blockers` |
| `未解决：` | 上一轮某条 blocker 本轮仍在 | `blockers` |
| `本轮新增：` | 本轮新发现的 blocker | `blockers` |
| `范围外：` | 不在本 CR 范围，留给后续 CR | `suggestions` |

机械核对规则：

1. 上一轮每条 blocker 必须在本轮 `blockers ∪ suggestions` 中恰好出现一次，且前缀为 `已解决：` / `部分解决：` / `未解决：` 之一；对照键为上一轮文本的稳定标识（若原文以 `B-` 开头取到第一个空白或 `]`，否则取原文）。
2. 本轮新 blocker 必须带 `本轮新增：`，不得伪装成旧 blocker 状态。
3. 首轮（无上一轮 blocker）全部 blocker 使用 `本轮新增：`。
4. 范围外发现只进 `suggestions`，前缀 `范围外：`。

**FR-4 回修必须可重验，且不恢复已删除 canonical 字段**

回修后再评必须按 FR-3 逐条给出旧 blocker 的解决状态，禁止只写「已修复」。

不得在 3 条 CR Pipeline JSON 与 `contract-scan.test.mjs` 扫描的 11 个 SKILL.md 中重新引入 `fixed-blockers`、`repair-instructions`、`suggestion_policy`、`suggestion-policy`。附件 §7 P0-1.7 的语义由 FR-3 的逐条状态句式满足。人读评论或会话回复可用「fixed-blockers」作小节标题，但不得成为 canonical YAML 字段名。

## 3.2 P0-2 冻结批准范围

**FR-5 SDD「批准范围」固定章节**

`SDD-template.md` 增设固定章节「批准范围」，承载且仅承载：

```text
scope_in: 当前 CR 必须交付的 FR/AC
scope_out: 明确排除的路径和能力
zero_diff: 明确不得改动的调用点/签名
follow_up: 发现但留给后续 CR 的缺口
```

不新增独立 ledger 文件，不新增状态。

**FR-6 写入与冻结时机**

- `write-tech-design`：该节为契约必填；空字段须显式写 `无` 或 `N/A` 加理由，不得省略章节。
- `approve-tech-design` 通过后，该节对 PLAN/TASK/code 只读。PLAN/TASK 发现与批准范围冲突时，只能经既有 `review-dev-plan` 双轨回到 `write-tech-design` 或 `write-dev-plan`（FR-7），不得在 PLAN/TASK 中静默扩大范围，也不得把 `follow_up` 或兼容性背景自动转成当前 TASK。
- 代码阶段发现实际 diff 越界时，只回 `implement-code`（FR-7），不得假装存在 code→设计 的状态转换。

**FR-7 下游评审先核对此节（分阶段可执行路由）**

`review-dev-plan` 与 `review-code` 必须先核对此节再执行其余评审。把 `follow_up` / `scope_out` / `zero_diff` 做成当前交付，一律判为 blocker。路由按下表，本 CR **不**新增状态或转换：

| 节点 | 冲突含义 | repair-target | 既有转换 / schema |
|---|---|---|---|
| `review-dev-plan` | plan/TASK 把批准范围译错，SDD 本身仍正确 | `write-dev-plan` | `review-dev-plan:block -> write-dev-plan`；annotation 顶层缺省值 |
| `review-dev-plan` | 批准范围/SDD 设计本身需改 | `write-tech-design` | 既有 upstream：`review-dev-plan:upstream-design-blocker`；`review-record` 已接受该枚举 |
| `review-code` | 实际 diff 触碰 `scope_out`、把 `follow_up` 做成当前交付、或改动 `zero_diff` 调用点 | `implement-code` | 既有 `review-code:block -> implement-code`；`REVIEW_REPAIR_TARGETS.code = implement-code` |

`review-code` 禁止把 `repair-target` 写成 `write-tech-design` 或 `write-dev-plan`。code stage 的 `review-record` schema、`code-implementation` reviewLoop replay 保持现状。implementer 必须撤回越界 diff。若批准范围本身错误：code 阶段不可路由回设计；合法出路仅为（1）撤回越界 diff 使本轮 code 评审通过，或（2）人工 `approve-code` reject / `cr-review-record:withdraw`，另开后续 CR 修订 SDD。不得为该出路新增状态转换。

## 3.3 P0-3 PLAN 轻量覆盖矩阵

**FR-8 plan.md 覆盖矩阵必填**

`write-dev-plan` 要求 `plan.md` 含「AC/业务闭环覆盖矩阵」节，每条关键 AC 或业务闭环一行：

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|

关键 AC 定义：PRD 中影响主路径验收可达性的 AC（含用户可观察的成功/失败/隔离/幂等）。非关键 AC 可合并行，但必须能从矩阵追溯到至少一条 TASK。

「验收证据」列对关键 AC 必须填写稳定标识 `cmd-NN`（NN 为两位十进制，与 FR-16 全等），不得只写散文命令。

**FR-9 无唯一 TASK owner 不得进入开发启动审批**

`review-dev-plan` 将「关键 AC 无唯一 TASK owner」判为 blocker。不向 `crctl` 或 `gates.json` 新增静态检查；`approve-dev-start` 继续消费既有 `passCondition`（verdict=pass 且 blockers 为空）。任一关键 AC 缺少唯一 TASK owner 时，不能得到 `review-dev-plan` PASS，因而不能进入开发启动审批。

## 3.4 P0-4 移除流程控制 TASK 循环

**FR-10 禁止流程控制交付 TASK**

`write-dev-tasks` 契约增加：不得把 Pipeline 控制步骤 `merge` / `writeback` / `archive` 建成交付 TASK（即 `tasks/TASK-*.md` + `_index.yml` 中的条目）。

附件 §7 P0-4 曾允许「审计用发布准备 TASK，完成边界截止于 merge」。该例外 **取消**：`crctl task done` 仅允许 `status=developing`（现有 `ILLEGAL_LEDGER_STATE`），merge 发生在 `code-approved` 之后，完成于 merge 的交付 TASK 无法合法标 done，会再次卡住 `deliveryIndexComplete`。本 CR 不扩展 `task done` 的合法状态。

因此：

- 不得创建完成前置包含 `code-reviewing` / `code-approved` / `merge` / `writeback` / `archive` 的交付 TASK（含标题或正文写成「发布准备」「merge 完成」之类）。
- merge / 审批 / checkpoint 的审计事实以既有 `approval.yml`、`merge-commits.yml`、checkpoint 元数据为准，不进 TASK ledger。
- 若需要「实现已就绪、可交评审」类 TASK，完成边界必须是 `developing` 内可被 `crctl task done` 登记的事件（例如实现已落盘、关键测试命令已写入 test plan）。

**FR-11 评审核验与归档门禁不变**

`review-dev-plan` 核验 FR-10。`deliveryIndexComplete` 归档门禁保持不变：真正的交付 TASK 在 archive 前必须全部 done。不增加人工豁免开关。

## 3.5 P1-1 统一版本事实（注册阶段确定）

版本规则：

```text
注册：确定 target_version（人工输入，不自动推导、不自增）
需求/架构/开发：继承并校验
更正：仅 crctl version-set，unassigned → 真实版本，同步已有派生产物
Write-back：校验一致性并消费
```

执法点三处，均在 `crctl`：`register`、`version-set`、`writeback-apply`。中间阶段各 pipeline 只传递 `cr.md` 的值，不加逐阶段版本门禁。三条命令共用下方值域与规范化函数（SDD 落同一纯函数，测试可单测）。

**版本值域与规范化（FR-12 / FR-14 / FR-15 共用）**

对原始 `--target-version` / `--to` 字符串：

1. 缺省或非 string → 非法。
2. Unicode trim（与 JS `String.prototype.trim` 相同）后空串 → 非法。
3. trim 后对 ASCII 字母 `toLowerCase` 得到 token。
4. token ∈ 禁止同义值集合 → 非法。集合冻结为：`tbd`、`n/a`、`na`、`n.a.`、`pending`、`none`、`unknown`、`todo`、`wip`、`null`、`undefined`。
5. token === `unassigned` → 合法未分配值；存储与全等比较一律用字面量 `unassigned`。
6. 否则为真实版本候选：若 trim 后（大小写折叠前）以单个 `v` 或 `V` 开头则剥掉恰好一个前缀；剩余必须整串匹配 `^(0|[1-9]\d*)\.(0|[1-9]\d*)(\.(0|[1-9]\d*))?$`。存储用剥前缀后的规范串（例：`v0.30` → `0.30`，`0.1.0` → `0.1.0`）。这与现有 writeback `startsWith('v')` 切片对齐，并收紧为一位主版本.次版本[.修订]、禁止前导零（`0` 本身除外）。
7. 其它一律非法，包括 `0.29-rc`、`latest`、`1`、`0.30.0.1`、内嵌空白。

**FR-12 `register` 硬校验 `--target-version`**

| 项 | 契约 |
|---|---|
| 命令 | `crctl register ... --target-version <v>`（既有子命令，flag 由可选改必填） |
| 输入 | `--target-version` 必填；按共用规范化 |
| 合法 | 规范化后为 `unassigned` 或真实版本 |
| 错误码 | `REGISTER_VERSION_INVALID`（缺省、空、禁止同义值、畸形真实版本）。非零退出 |
| 零写入 | 无 `cr.md`、无 `_backlog.yml` 新条目、无 worktree、无 register journal |
| 调用者 | 与现有 `register` 相同，非 TTY 限制 |
| 状态副作用 | 成功则 CR `drafting`（现有）；失败不创建 CR |
| 幂等 | 同 `--registration-key` 且规范化后版本相同 → 现有续跑；版本不同 → 现有输入漂移硬阻断，不另造错误码 |
| JSON/stdout | 成功对象必须含 `targetVersion` 等于规范化后的值；失败走现有 stderr `{error:{code,message}}` |
| 删除 | `targetVersion = input.targetVersion ?? 'tbd'` 默认值 |

发起时未排期：向用户确认后填 `unassigned`，沿用 `origin`「填写前确认、不自行推测」的先例。本 CR 已按该规则登记为 `unassigned`。

**FR-13 后续产物继承同一版本**

注册生成的 `cr.md`、以及本 CR 的 PRD、SDD、PLAN、TASK 沿用同一 `target-version` 值。`write-requirement-prd` / `write-tech-design` / `write-dev-plan` / `write-dev-tasks` 从 `cr.md` 读取，禁止写 `tbd`、禁止自行改写。`requirement-register` SKILL 输入表将 `target_version` 由可选改为必填。`README.md` 人读流程同步「目标版本在注册阶段确定」。

更正后的继承：`version-set` 成功后，已存在派生产物的 frontmatter 必须已与 `cr.md` 全等；其后新写的产物继续从 `cr.md` 读取（FR-15）。禁止出现「`cr.md` 已是真实版本、PRD/SDD/PLAN/TASK 仍为 `unassigned`」的分叉。

**FR-14 `writeback-apply` 一致性守卫**

命令：既有 `crctl writeback-apply <cr> --stage baseline\|tasks\|traceability --spec-id <id> --target-version <ver>`（traceability 另需 `--milestone-file`）。调用者与现有相同，非 TTY 限制。成功路径的状态副作用保持现状（baseline 可 `merging→writing-back`）；本 FR 只约束版本失败路径。

版本守卫时序（三 stage 相同）：在 `resolveOperationalWorkspace`、`prepareWritebackCandidate`、`loadOrCreateJournal` **之前**执行。规范化函数与 FR-12 共用。`--target-version` 与 `cr.md` 的 `target-version` 均先规范化再比较。

| 条件 | 错误码 | 退出 |
|---|---|---|
| 任一侧规范化失败（含空、禁止同义值、畸形） | `WRITEBACK_VERSION_INVALID` | 非零 |
| 规范化后任一侧为 `unassigned` | `WRITEBACK_VERSION_UNASSIGNED` | 非零 |
| 两侧均为真实版本但字符串不全等 | `WRITEBACK_VERSION_MISMATCH` | 非零 |
| 一致且为真实版本 | 进入现有 writeback 逻辑 | 现有 |

版本错误优先于 `WRITEBACK_STATE_MISMATCH`（authority 不是 Transaction Workspace）及其它后续错误。

失败观察点（三 stage 均适用）：

允许：stderr 结构化 JSON `error.code` 为上表之一；进程非零退出。

禁止（与调用前字节级比较）：

1. 目标 specs / delivery / traceability 文件内容变化。
2. `.crctl/candidates/{CR-ID}/{stage}/` 被创建、删除或改写（调用前不存在则仍不存在；调用前已有则内容不变）。本失败路径不得执行 `rmSync`/`mkdir`。
3. writeback journal 被创建或改写（含 phase / inputDigest / businessInputDigest）；不得留下可被后续同 stage 误认为「可恢复成功事务」的半成品。
4. transaction lock 残留。
5. operational workspace / authority 变化：`source`、path、`cr.md` status 与调用前相同。
6. git commit / origin push。

幂等 / 同参重试：对同一非法参数再调用一次，错误码相同，且上述禁止项仍成立（无增量痕迹）。改用合法真实版本且与 `cr.md` 一致后，才允许进入现有 candidate/journal 事务。

**FR-15 `unassigned` 更正为真实版本的唯一入口**

Pipeline 节点不得改写版本。将 `unassigned` 改为真实版本必须走：

```text
crctl version-set <cr_id> --to <real-version>
```

这是新的账本写入子命令，同构 `owner-set`（复用既有 durable write-set / CAS / 受控 git），**不是**新事务框架、不是新状态、不是新 Pipeline。

| 项 | 契约 |
|---|---|
| flag | `--to` 必填；按共用规范化，且结果必须是真实版本（不是 `unassigned`） |
| 正向 | 当前 `cr.md` 规范化值为 `unassigned` → 写入 `--to` 的规范真实版本 |
| 幂等 | `cr.md` 与全部已存在派生产物已经等于 `--to` → `changed=false`，exit 0，零新 commit |
| 非法 `--to` | `VERSION_SET_INVALID` |
| 当前不是 `unassigned` 且不等于 `--to` | `VERSION_SET_NOT_UNASSIGNED` |
| 状态不在允许集 | `VERSION_SET_STATE_INVALID` |
| 派生产物存在但其 `target-version` ≠ 当前 `cr.md` 值，或缺该字段 | `VERSION_SET_DERIVED_DRIFT` |
| 调用者 | 与 `owner-set` 相同，非 TTY 限制；identity 由 crctl 生成 |
| 状态副作用 | **不**改变 CR status |
| JSON/stdout 成功 | `{ op: "version-set", cr, from, to, changed, files: [<workspace-relative paths>] }` |
| 失败 | stderr `{error:{code,message}}`，零写入（cr.md / backlog / 派生产物 / git 均不变） |
| 重试 | 失败后重跑同一命令；无半成品 |

允许状态（非终态且 writeback 尚未开始）：`drafting`、`requirement-reviewing`、`requirement-approved`、`tech-designing`、`tech-design-review-pending`、`tech-design-reviewed`、`task-breakdown`、`developing`、`code-reviewing`、`code-approved`。

禁止状态：`merging`、`writing-back`、以及终态 `archived` / `rejected` / `withdrawn`。merge 一旦开始，版本冻结，只允许 writeback 消费。

原子写入集合（文件存在才纳入；不存在则跳过，不算漂移）：

1. `change-requests/{CR-ID}/cr.md` 的 `target-version`
2. `change-requests/_backlog.yml` 该 CR 条目的 `target-version`
3. `change-requests/{CR-ID}/prd.md` frontmatter `target-version`
4. `change-requests/{CR-ID}/sdd.md` frontmatter `target-version`
5. `change-requests/{CR-ID}/plan.md` frontmatter `target-version`
6. `change-requests/{CR-ID}/tasks/TASK-*.md` 各文件 frontmatter `target-version`

手改 `cr.md` 仍被既有保护拒绝，不为官方入口。不要求也不允许回写修复已归档的 AIFI-14 历史产物。不允许真实版本改到另一个真实版本，也不允许改回 `unassigned`。

## 3.6 P1-2 收紧关键测试的 pass 语义

**FR-16 关键测试 SKIP ≠ 完整通过**

关键测试定义：绑定 FR-8 覆盖矩阵中「作为某关键 AC 唯一验收证据」的命令，不由 reviewer 自由裁量。

稳定关联（`cmd-NN`）：

- NN 为两位十进制，等于该 CR 当前 `test-report.md` 机器区 `commands` 列表的 1-based 下标，并与 `test-evidence/cmd-NN.log` 文件名全等。
- 覆盖矩阵「验收证据」列对关键 AC 必须写该 `cmd-NN`。
- 「唯一验收证据」= 该关键 AC 行只引用一个 `cmd-NN`，且没有另一关键 AC 行把同一 `cmd-NN` 标成自己的唯一证据。

skip 的唯一证据来源：本 CR 为 `crctl test` 机器区每条 command 增加布尔字段 `skipped`（additive，不删现有字段）。计算规则冻结如下，实施期不得由 reviewer 增删模式：

- `exit-code == 0` 且对应 `cmd-NN.log` 在 `--- stdout ---` 与 `--- stderr ---` 两段（先 `\r\n`→`\n`）命中以下任一模式（大小写不敏感）：
  1. `(^|\n)# skip\b`
  2. `(^|\n)ok \d+ # skip\b`
  3. `\bskipped:\s*[1-9]\d*`
  4. `\bSKIPPED\b`
  5. `\bno tests to run\b`
- 否则 `skipped: false`（含 non-zero / timeout：那是失败，不是 skip）。

`review-code` 只读机器区 `skipped`、`exit-code`、`timed-out` 与覆盖矩阵的 `cmd-NN`，不得自行解析各测试框架输出。

行为：

- 关键测试 `skipped: true` 时，`review-code` 摘要必须明确「未执行 / 未测」，不得把单纯 exit 0 叙述成该 AC 已验证。
- 若该测试是当前 CR 某关键 AC 的唯一验收证据，则不能仅凭 `test-report` 机器区 `status=pass`（exit 0）进入代码审批：必须 blocker（`repair-target=implement-code`），或使用已有环境阻断/恢复语义中止（`ENVIRONMENT_MISMATCH` 技术中止不得写成代码 blocker，保持现有约定）。
- 不新增 coverage ledger 或测试指标系统。

环境不满足（无 Postgres、无 `node_modules` 等）可以作为未覆盖风险记录，但不能等价于关键验收已完成。

## 3.7 P1-3 静态检查按重复失败触发

**FR-17 下沉触发规则**

只有「同类问题再次出现」且「规则已确定到可写进现有版本化脚本或 validator」时，才向已有工具增加小检查。检查下沉到现有确定性工具（`crctl` / 已入库脚本 / 现有 test），不由 Agent 依赖提示词自觉完成，也不新增通用 Runner 或第二套 validator 框架。

本 CR **不**把附件 §7 P1-3 的举例清单一次性全部落地。下列举例仅作候选，实施期仅当再次失败且规则确定时才做：

- PLAN 引用的文件或 symbol 是否存在；
- TASK 命令 cwd 和 package path 是否有效；
- reviewLoop 的 repair 节点是否存在；
- writeback 前是否存在 pending 交付 TASK（归档门禁已覆盖「archive 前必须 done」，本项不重复造门禁）；
- writeback 版本参数与 CR 元数据是否一致（由 FR-14 本 CR 落地，因其已在 AIFI-14 实际分叉且规则已确定）。

本 CR 同步落地的确定性检查仅限：FR-12 / FR-14 / FR-15 版本守卫、FR-16 的 `skipped` 字段。其余举例仍不下沉。

# 4. 非功能需求

- **NFR-1 回归**：现有 `crctl` 状态机、CAS、审计、reviewLoop、writeback transaction 和 archive 门禁的既有回归测试继续通过。`crctl.test.mjs`（及既有 writeback/test 测试文件）为下列项补最小回归：FR-12 拒绝 `tbd`/空/`n/a`/`pending`、放行 `unassigned` 与真实版本；FR-14 不一致与 `unassigned` 在 candidate/journal/authority 零变化；FR-15 `version-set` 正向同步、漂移拒绝、非法状态、幂等；FR-16 `skipped` 字段对模式表的真/假。
- **NFR-2 兼容边界**：不新增 Agent、Pipeline JSON 文件、状态机状态或转换（沿用现有 15 个具名状态 + 注册前 `(new)` 口径；**不**把 `review-code` 接到 `write-tech-design`）、不新增 review ledger、不新增事务框架、不让 Agent 手写 `_backlog.yml` / `cr.md` / 审批记录。`crctl version-set` 与机器区 `skipped` 字段是现有 crctl 的增量，不计入「新框架」。
- **NFR-3 行尾纪律**：任何新增哈希或跨行解析必须先 `\r\n → \n`；跨行正则失败必须硬失败，禁止静默降级。
- **NFR-4 性能**：新增守卫为 register / version-set / writeback-apply 入口的常数时间字段比较，不得引入额外网络调用。
- **NFR-5 安全**：不改变现有审批 TTY/`--grant` 约束；不新增绕过 `crctl` 的账本写路径。
- **NFR-6 文档同步**：`requirement-register` SKILL 与 tools `README.md` 必须与 FR-12/FR-13/FR-15 一致；禁止只改代码不改人读说明，也禁止在 knowledge-base `dir-graph.yaml` 复刻状态机。

# 5. 验收标准

对应关系：AC-n 验证 FR-n；§9 条目在括号中标注。AC-1～AC-4 对四个 review 节点均适用，参数化矩阵如下；不得只改一个 Skill 即宣称通过。

| 节点 | 首轮闭合夹具（AC-1） | 分级夹具（AC-2） | 回修夹具（AC-3） |
|---|---|---|---|
| `review-requirement` | 含 HTTP 或 CLI 契约、同一契约域至少两个独立缺口的 PRD | 一条纯措辞问题 + 一条验收不可达 | 上一轮 2 条 blocker 修 1 留 1，另造一条范围外 |
| `review-tech-design` | 含调用者闭包缺口的 SDD（例如缺错误码与缺锁序） | 同上两类 | 同上结构 |
| `review-dev-plan` | 覆盖矩阵同时缺某一关键 AC 的 TASK owner 与缺另一关键 AC 的 `cmd-NN` | 同上两类 | 同上结构 |
| `review-code` | 实际 diff 同时缺一条关键失败路径处理、且触碰一处 `zero_diff` | 同上两类 | 同上结构；block 的 `repair-target` 必须为 `implement-code` |

- **AC-1**（§9.5）：对上表四个节点各跑一次首轮评审。每一节点必须在同一轮 `blockers` 中报告该夹具的至少两个独立缺口（前缀 `本轮新增：`），而不是只报其中一个、把另一个留到下一轮。证据：该轮对应 `review-annotations/{requirement\|sdd\|dev-plan\|code}.yml` 的 blockers 同时包含两条独立根因。
- **AC-2**：对四个节点各自构造「只影响措辞、不影响验收可达性」的问题，必须进入 `suggestions`；构造「当前验收不可达」的问题，必须进入 `blockers`。
- **AC-3**（§9.6）：对四个节点各自：上一轮 2 条 blocker 分别修复 1 条、保留 1 条后重评。输出必须能机械看到 `已解决：` 恰好 1 条（在 suggestions）、`未解决：` 或 `部分解决：` 恰好 1 条（在 blockers），并能单独列出一条 `范围外：`（suggestions）。payload 与 SKILL 正文不含 `fixed-blockers` 字段名。
- **AC-4**：同 AC-3 的回修轮；抽查 `contract-scan.test.mjs` 覆盖的 SKILL/Pipeline 对禁止字段零命中。四个 review Skill.md 均不得出现这些字段名。
- **AC-5**：按 `SDD-template.md` 新起草的 SDD 含「批准范围」四字段；缺章节时 `review-tech-design` 为 blocker。
- **AC-6**：SDD 审批后的 PLAN 若把 `follow_up` 写成当前 TASK，`review-dev-plan` 为 blocker，`repair-target` 为 `write-dev-plan` 或 `write-tech-design`（按 FR-7 双轨，不得发明第三值），且不得在 PLAN 内静默扩范围。
- **AC-7**：`review-dev-plan` / `review-code` 在其余维度之前先引用批准范围节。把 `zero_diff` 调用点改掉的 diff，`review-code` 为 blocker 且 `repair-target=implement-code`；`crctl next` 指向 `implement-code`，不得指向 `write-tech-design` / `write-dev-plan`。
- **AC-8**：`plan.md` 含覆盖矩阵节，且每条关键 AC 有 TASK owner 与 `cmd-NN` 证据列。
- **AC-9**（§9.3）：从合法 `plan.md` 删除某一关键 AC 的 TASK owner 后跑 `review-dev-plan`，verdict=block；`crctl next` 不得指向 `approve-dev-start` / `human_approval`。
- **AC-10**（§9.4）：构造描述含 writeback、archive、merge、code-approved 或「发布准备直至 merge」完成前置的 TASK，`review-dev-plan` 为 blocker；`write-dev-tasks` 契约含禁止条款。交付 ledger 中不存在必须在 `developing` 之后才能 `task done` 的条目。用非 `developing` 状态对合法交付 TASK 执行 `crctl task done` 仍为 `ILLEGAL_LEDGER_STATE`（回归，不放宽）。
- **AC-11**：`deliveryIndexComplete` 行为与本 CR 之前一致：交付 TASK 未 done 时 archive 仍阻断；无新增豁免 flag。
- **AC-12**（§9.1 注册侧）：`crctl register` 在下列输入下非零、零写入，错误码 `REGISTER_VERSION_INVALID`：缺 `--target-version`；值为空或仅空白；`tbd`；`TBD`；`n/a`；`pending`；`0.29-rc`。值为 `unassigned`、`0.30`、`v0.30`（写入 `0.30`）→ 成功，`cr.md` 与成功 JSON 的 `targetVersion` 为规范化值。本 CR 的 `cr.md` 已为 `unassigned` 可作为正向例。
- **AC-13**（§9.1 继承侧）：本 CR 的 PRD（本文）`target-version` 为 `unassigned`，与 `cr.md` 一致。后续 SDD/PLAN/TASK 必须同值；`write-dev-plan` 不得再回退到 `tbd`。对夹具 CR 执行 `version-set` 后，已存在的 PRD/SDD/PLAN/TASK frontmatter 必须与 `cr.md` 全等（与 AC-15 交叉）。
- **AC-14**（§9.2）：对测试 CR 的 `baseline` / `tasks` / `traceability` 三 stage 分别断言：
  1. `--target-version` 与 `cr.md` 不一致（两侧均为真实版本）→ `WRITEBACK_VERSION_MISMATCH`；
  2. `cr.md` 或传入值为 `unassigned` → `WRITEBACK_VERSION_UNASSIGNED`；
  3. 传入 `n/a` → `WRITEBACK_VERSION_INVALID`；
  4. 上述每次调用后：目标 specs/delivery/traceability 哈希不变；`.crctl/candidates/{CR}/{stage}` 不比调用前新增或改写；writeback journal 不比调用前新增或改写（phase 不变）；authority / `cr.md` status 不变；无 commit/push。
  5. 将（1）的同一参数立即重试，错误码相同且无增量痕迹。
  6. 夹具至少包含一条 `status=drafting` 的调用，证明版本错误优先于 `WRITEBACK_STATE_MISMATCH`。
- **AC-15**：`crctl version-set` 能把夹具 CR 的 `unassigned` 写成真实版本，并同时反映到 `cr.md`、`_backlog.yml` 与已存在的 PRD/SDD/PLAN/TASK frontmatter（文件不存在的跳过）。手改 `cr.md` 仍被既有保护拒绝或至少不为官方入口。负向：`--to unassigned` 或畸形值 → `VERSION_SET_INVALID` 零写；`status=merging` → `VERSION_SET_STATE_INVALID` 零写；PRD 仍为 `unassigned` 而 `cr.md` 已被手改成真实版本 → `VERSION_SET_DERIVED_DRIFT` 零写。成功 JSON 含 `from`/`to`/`files`。
- **AC-16**（§9.7）：覆盖矩阵中标记为某关键 AC 唯一证据的 `cmd-NN`，若机器区 `skipped: true`，`review-code` 不得仅因机器区 `status=pass` 进入 `code-reviewing`；摘要含「未执行」或等价字样；`repair-target=implement-code`。另用一条命中模式表的 log 夹具断言 `crctl test` 写出 `skipped: true`，用一条无模式的 exit 0 断言 `skipped: false`。
- **AC-17**：本 CR 的 diff 不含一次性落地的「PLAN symbol 存在性检查」等未再次失败的新 validator；FR-12/FR-14/FR-15 版本检查与 FR-16 `skipped` 除外（已确定且已失败过或本 CR 闭合所必需）。
- **AC-18**（§9.8 / NFR-1）：`node --test` 运行 `skills/shared/crctl/scripts/test/crctl.test.mjs` 及既有 writeback/archive/register/test-cr 相关测试，本 CR 引入的用例通过，既有用例不失败。

# 6. 成功指标

上线后以随后 **2 个完整走完 authoring→writeback 的 CR** 度量（不含本 CR 自身若仍为 `unassigned` 而未 writeback 的情况）：

1. 新注册 CR 的 `cr.md` 无 `tbd`；PRD/SDD/PLAN 与 `cr.md` 的 `target-version` 字符串全等。若中途 `version-set`，更正后全链仍全等。
2. writeback 未再出现「过程文档 `tbd`、baseline 另一个版本号」的分叉；版本失败不留下 candidate/journal 半成品。
3. `review-dev-plan` 首轮即能对缺 TASK owner 的关键 AC 给出 blocker；开发启动审批前矩阵无空 owner。
4. 交付 TASK ledger 中无完成条件依赖 merge/writeback/archive 的条目；archive 一次通过，无需为流程 TASK 补标。
5. 若 PRD 含可调用契约，需求评审首轮 blockers 覆盖该契约域的独立缺口，不再把同一契约的 residual 留到第 2 轮才升级。四个 review 节点的回修评论均能按 FR-3 前缀机械核对。

# 7. 范围排除

- 不新增 Agent、Pipeline、状态机状态/转换、review ledger、事务框架、通用 Runner、动态插件或第二套 Git/账本。尤其不把 `review-code` 接到 `write-tech-design` / `write-dev-plan`。
- 不为单个 CR 建立专用统计看板；不提高 `reviewLoop.maxAttempts`；不把全部 suggestion 强制改为 blocker。
- 不回写修复已归档 AIFI-14（CR-2026-056）的 `tbd` / `0.29` 历史产物。
- 不修改 `../multica/`（本 CR 无业务功能代码）。
- 不把 `docs/product/`、`docs/analysis/` 既有设计文档搬进 `specs/`。
- 不新增测试覆盖率系统、coverage ledger、或把非关键 SKIP 一律改为失败。
- 不增加 archive 人工豁免；不放宽 `deliveryIndexComplete`。
- 不扩展 `crctl task done` 的合法状态（保持仅 `developing`）。
- 不在 `gates.json` 为覆盖矩阵新增静态检查（FR-9）。
- 不一次性实现 P1-3 举例中除 FR-12/FR-14/FR-15/FR-16 以外的检查项。
- 不处理 AIFI-15 附件未列入 §7 的其它建议（例如审批卡直通 `requirement-approved`、取消 agent 委派）。
- Discussion / Team Agent 会话配置等业务功能不在本 CR 范围（属已归档的 CR-2026-056）。
- 不允许 `version-set` 把真实版本改成另一个真实版本或改回 `unassigned`。
