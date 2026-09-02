---
id: CR-2026-060-plan
type: PLAN
cr-ref: CR-2026-060
sdd-ref: "change-requests/CR-2026-060/sdd.md"
target-version: "0.33"
status: draft
created: 2026-09-03T00:35:00+08:00
updated: 2026-09-03T00:35:00+08:00
---

# 1. 交付里程碑

输入：已审批 PRD（FR-01～FR-06 / AC-01～AC-18，subject-sha256 `d74ac20a…87737586`）与已审批 SDD attempt 2（subject 基线 `24f860a`，tech-design PASS `a567d34`，人工审批已落盘）。全部实施改动落在 sibling `tools` 仓（tools CR worktree）；knowledge-base 只承载本 CR 过程文档与账本；`multica` 仓零改动（SDD §9 `zero_diff`）。本 CR 自身 `target-version: 0.33`，plan/TASK frontmatter 继承 cr.md 值，禁止 tbd/自行改写。

本 CR 为 legacy registration（两账本均无 `target-spec-id`），实施期不得回填自身字段（AC-02）。四个交付 TASK 与四变更组一一对应（PRD §3.4 / SDD §1.1）；账本 id 使用两位补零 `CR-2026-060-TASK-01`..`04`（对齐现行 `loadTaskCards` `/^TASK-\d{2}\.md$/` 与 `{cr}-TASK-{nn}`；PRD/SDD 口语「TASK-1..4」即本组四个交付 TASK，G3 的 `--count-hint` 校验必须沿用两位补零契约，不得另造单数字 id）。

| 里程碑 | 交付内容 | 预计工时 | 退出条件 |
|---|---|---:|---|
| M1 设计冻结 | PRD / SDD / 批准范围（SDD §9）+ tech-design 人工审批 | 0（已发生） | status=`tech-design-reviewed` |
| M2 计划与任务拆分 | 本 plan.md + TASK-01～TASK-04 + `tasks/_index.yml`（`crctl task init`）+ 推进至 `task-breakdown` | 0.5 人天 | 覆盖表四组各一 ID；`crctl next` 指向 review-dev-plan |
| M3 G1 注册与 authority | TASK-01：`--target-spec-id`、统一结果 builder、`registrationAt`、mode 唯一裁决、strict authority 解析器、pre-review gate、advance 层 guard | 16h | cmd-02/cmd-03 中本 TASK 新增向量全绿 |
| M4 G2 writer-reviewer | TASK-02：PRD/SDD 作者与 reviewer 六份 SKILL + 四个 `approve-*` 合同修订 | 8h | cmd-01 对相关 SKILL 零 CONTRADICTS；对称性可机械抽查 |
| M5 G3 PLAN/TASK/Coding/test/review | TASK-03：两张 PLAN 表合同、`task init --count-hint` 三步断言、workspace/证据/回修合同 | 12h | cmd-03 中 count-hint 正负向量全绿 |
| M6 G4 writeback/archive 与兼容 | TASK-04：new/legacy 双路径、tasks pending preflight、new traceability 分支、archive journal 重放、Pipeline prompt 收敛、规划/只读诊断对齐 | 18h | cmd-04/cmd-05 新增向量全绿；cmd-01 Pipeline 机器事实不漂移 |
| M7 评审与人工审批 | review-dev-plan → approve-dev-start → implement-code → write-test-report → review-code → approve-code | 流程节点 | 评审 blocker 清零后经人工审批 |
| M8 发布 | merge / writeback / archive | 流程控制节点 | 按状态机既有流程；本 CR 走 legacy writeback/archive（AC-02/AC-11） |

预计总工时：**54h**（TASK-01～TASK-04 合计；1 人天 = 8h，约 6.75 人天）。M4 可与 M5 在 TASK-01 合入后并行（文件不重叠）；M6 依赖 TASK-01 的 mode/strict 解析器与 TASK-03 对 `crctl.mjs` 的 count-hint 落点，串行于二者之后。M7/M8 为流程节点，不建交付 TASK（FR-10 / SDD §9）。

# 2. 任务依赖图

```text
TASK-01  G1 注册与 authority
           （resolveTargetSpecMode / resolveWritebackAuthorityStrict /
             buildRegisterResult / runPreReviewGateChecks /
             assertRequirementReviewAdvanceGuard / register 账本字段）
  ├──> TASK-02  G2 PRD/SDD writer-reviewer + 四个 approve-*
  ├──> TASK-03  G3 PLAN/TASK/Coding/test/review + cmdTaskInit --count-hint
  │         └──> TASK-04  G4 writeback/archive + new traceability + Pipeline/规划/只读诊断
  └──> TASK-04  （同时依赖 TASK-01 的 mode/strict 解析器）
```

- TASK-02 / TASK-03 均只依赖 TASK-01，文件集合不重叠，可并行。
- TASK-04 依赖 TASK-01（消费 mode/strict 签名）与 TASK-03（同文件 `crctl.mjs` 的 count-hint 已落点后再改 writeback/archive 入口）。
- 跨任务接口签名见各 TASK「接口契约」节；TASK-04 汇总核对消费方与产出方全等。

实施资源（`crctl workspace inspect CR-2026-060` 返回，实施期原样消费，不重拼路径）：

- knowledge-base（`ai-first-platform-docs`）：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\knowledge-base\requirement\CR-2026-060`，承载 plan/tasks/test-report/账本。
- tools：`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-060`，承载全部代码/Skill/Pipeline/测试改动。**实施基线 HEAD = `860288ce96d568ed31a86a8c478d1cfa7f1087e9`**（= SDD §10 记录点，评审时核验一致）。
- multica：无实施改动（SDD §9 `zero_diff`；inspect 已 healthy）。

# 3. 资源与分工

| 角色 | 工作内容 | 预计工时 |
|---|---|---:|
| 开发（owners.development=Ray） | TASK-01～TASK-04 全部实现与测试落地 | 54h |
| 测试（owners.test=Ray） | 各 TASK 验收命令 + 终态 `crctl test` 发布 test-report.md | 含于各 TASK 工时 |
| 评审 | review-dev-plan / review-code 由 quality-reviewer-agent 执行 | — |
| 人工审批 | approve-dev-start / approve-code 由 Ray 在交互式终端执行 | — |

TASK 工时明细：TASK-01 16h / TASK-02 8h / TASK-03 12h / TASK-04 18h = **54h**。任务完成即时经 `crctl task done` 登记（AGENTS.md 纪律 #8），不积压到回写期。

# 4. 风险与回滚策略

| 风险 | 影响 | 应对与回滚 |
|---|---|---|
| R-01 过度删除真实业务判断（PRD R-01） | Pipeline prompt 收敛误删业务输入/失败分类 | TASK-04 按 SDD §4.9 五类信息白名单删改；cmd-01 断言节点数量/reviewLoop/passCondition/checkpoint 不变（AC-15） |
| R-02 新旧合同兼容破坏（PRD R-02） | 本 CR 被误标 new 或被回填 `target-spec-id` | 禁止任何批量回填路径（D-03）；legacy = 两处字段均缺失；本 CR 自身走 legacy writeback/archive（AC-02/AC-11） |
| R-03 证据漂移漏检（PRD R-03） | review-code 放行漂移实现 | TASK-03 绑定 sourceRevision + 日志哈希；cmd-06 覆盖 test-cr 既有漂移向量（AC-09） |
| R-04 规划流程顺序破坏（PRD R-04） | competitive-radar 草稿/正式落盘顺序漂移 | TASK-04 只改 Skill 必填输入，不复制落盘算法；规划审批不改接 CR approve（AC-14） |
| R-05 跨仓路径误用（PRD R-05） | 多仓文件误认为同一 commit | 所有路径只消费 inspect 的 `resources[].worktreePath`；tools / knowledge-base 分别提交 |
| R-06 同文件串改（`crctl.mjs` / `workspace-transactions.mjs`） | TASK-01/03/04 互相覆盖 | 依赖图强制 01→03→04；每 TASK 只改 SDD 列明的符号；zero_diff 内核（`performAdvance` commit/outbox/audit、`cmdTaskInit` render/CAS、`applyWritebackAtomic` candidate/journal/push）禁止改动 |
| R-07 基线既有红 | AC-16「既有用例不失败」口径 | §5.3 例外表：BR-1/BR-2 于 tools HEAD `860288ce` 实测仍红；skip-pattern 逐条排除；红计数不增加 |
| R-08 流程控制被建成交付 TASK | AC-08/FR-10 blocker | 本 CR 恰四个交付 TASK；无 merge/writeback/archive 流程 TASK；TASK-04 完成边界 = 代码与测试落盘（developing 内可 `crctl task done`） |
| R-09 `--count-hint` 与现行两位补零 id 冲突 | `task init` 拒收或误报 `TASK_COUNT_MISMATCH` | G3 校验对齐 `loadTaskCards` 的 `{cr}-TASK-{nn}`（nn 两位）；本 plan 预分配即该契约 |

回滚策略：全部实施改动在 tools CR worktree 分支 `requirement/CR-2026-060`，逐 TASK 单 commit（`[cr] ` 前缀）；局部回滚 = revert 对应 TASK commit，整体回滚 = 分支重置到 `860288ce`。knowledge-base 侧仅文档/账本，账本写入全部经 crctl。无 feature-flag：改动随分支合并生效。`multica` 仓与 `gates.json`/`rules.json`/`durable-tx.mjs`/`cmdVersionSet`/`writeback-prd-sdd.mjs`/`writeback-tasks.mjs` 为 zero_diff，回滚面不涉及。

# 5. 验收与发布策略

## 5.1 证据命令表（稳定表 2/2，cmd-NN 与 `crctl test` 机器区 1-based 下标及 `test-evidence/cmd-NN.log` 全等）

cwd 默认 = tools CR worktree（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-060`）；`executable=node`；`shell:false`。`--test-reporter=dot` 避免默认 spec reporter 的 `skipped` 字样误命中 FR-16 模式表（先例 CR-2026-057）。JSON 侧 `args` 每个 token 为独立元素。

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---:|
| cmd-01 | tools | tools CR worktree | node | `["--test","--test-reporter=dot","skills/shared/crctl/scripts/test/lint-prompts.test.mjs","skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs","skills/shared/crctl/scripts/test/check-agents-contract.test.mjs","skills/shared/crctl/scripts/test/pipeline-structure.test.mjs","skills/shared/crctl/scripts/test/contract-scan.test.mjs"]` | 60 |
| cmd-02 | tools | tools CR worktree | node | `["--test","--test-reporter=dot","skills/shared/crctl/scripts/test/register-tx.test.mjs"]` | 120 |
| cmd-03 | tools | tools CR worktree | node | `["--test","--test-reporter=dot","--test-skip-pattern","CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引","skills/shared/crctl/scripts/test/crctl.test.mjs"]` | 120 |
| cmd-04 | tools | tools CR worktree | node | `["--test","--test-reporter=dot","skills/shared/crctl/scripts/test/writeback-tx.test.mjs"]` | 180 |
| cmd-05 | tools | tools CR worktree | node | `["--test","--test-reporter=dot","--test-skip-pattern","TASK-01 RED-7：预存确定性 dedup 文件","skills/shared/crctl/scripts/test/archive-tx.test.mjs"]` | 180 |
| cmd-06 | tools | tools CR worktree | node | `["--test","--test-reporter=dot","skills/shared/crctl/scripts/test/version-set.test.mjs","skills/shared/crctl/scripts/test/test-cr.test.mjs"]` | 120 |

关键测试：cmd-02～cmd-05 是覆盖矩阵中关键 AC 的主路径 CLI 证据。机器区 `skipped: true` 不得仅凭 exit 0 视为已验证。cmd-01/cmd-06 不是「唯一 CLI 信封」类关键 AC 的唯一证据，但是 AC-09/AC-15/AC-16 静态与既有回归的稳定标识。

## 5.2 发布前 checklist

1. 交付覆盖表（§6.1）每个 in-scope FR 只出现一次，且有唯一主责 TASK 与 `cmd-NN`。
2. 关键 AC 矩阵（§6.2）每条有且仅有一个 TASK owner，验收证据为 `cmd-NN`。
3. `tasks/_index.yml` 恰 4 条，id = `CR-2026-060-TASK-01`..`04`，与四组一一对应。
4. 机器区 status=pass：cmd-01～cmd-06 全部 exit 0 且 `skipped: false`；例外表与 skip-pattern 字面量逐条全等（§5.3）。
5. SDD §9 `zero_diff` 面零 diff：`gates.json`、`rules.json` deny/git 白名单、`cmdVersionSet`/`normalizeTargetVersion`/`cmdApprove`/`cmdReviewRecord`/`cmdTaskAppend`/`cmdTaskDone`、`durable-tx.mjs`、`writeback-prd-sdd.mjs`、`writeback-tasks.mjs`、`multica` 仓、`specs/`/`delivery/`。
6. 无流程控制交付 TASK（FR-10 自检）。
7. 本 CR 过程文档 frontmatter `target-version` 全等 `0.33`。

## 5.3 基线红例外登记表（R-07，于 tools HEAD `860288ce` 实测）

| BR-ID | 所在命令 | 测试文件 | 用例全名 | skip-pattern 字面量 | 基线证据（860288ce 实测） |
|---|---|---|---|---|---|
| BR-1 | cmd-03 | `skills/shared/crctl/scripts/test/crctl.test.mjs` | CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引 | `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引` | exit 1；断言 `expected: /crctl task init/` 不命中 `code-implementation.pipeline.json`（pipeline prompt 已 converge，本 CR 不把「把该字符串写回 pipeline JSON」当作修复——与 AC-15「prompt 不含算法副本」同向；根因修复属 follow_up） |
| BR-2 | cmd-05 | `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖 | `TASK-01 RED-7：预存确定性 dedup 文件` | exit 1；`actual: [{ code: EMIT_FAILED, event_kind: archive }]` vs `expected: []`——archive dedup 重放路径既有缺陷（本 CR 不改 archive 事件发射内核） |

判定规则（冻结）：

1. 例外表即权威清单；skip-pattern 必须包含用例全名且与上表全等。
2. 实施期发现任何新红一律 triage：本 CR 引入 → 修到绿；确认非本 CR 引入 → 不得当场扩表，回 `write-dev-plan` 修订例外表后再评审。
3. 通过口径 = 六命令经 skip-pattern 排除例外后全部 exit 0 → `status: pass`。不存在「block + 例外」通过口径。
4. 六命令统一 `--test-reporter=dot`，机器区 `skipped` 恒 false。
5. 红计数口径：实施 HEAD 上以 spec reporter、不带 skip-pattern 重跑 BR-1/BR-2 所在文件，失败用例集合与例外表逐条全等（红计数 = 2，不增加）。

## 5.4 估算总工时

**54h**（TASK-01～TASK-04 `estimate` 之和，与 `crctl task init` 返回的 `totalEstimateHours` 一致；FR-23 交叉校验基准）。

# 6. 交付覆盖表与 AC 矩阵

## 6.1 交付覆盖表（稳定表 1/2；new traceability 的 FR 行源；每个 in-scope FR 只出现一次）

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-01 注册合同与单一目标事实 | §2.1/§2.2/§2.4/§3.1 register 行/§4.1/§4.3/§4.7 | CR-2026-060-TASK-01 | cmd-02 | revert TASK-01 commit |
| FR-02 PRD/SDD 作者与 reviewer 标准对齐 | §3.2 前六行（write/review requirement 与 tech-design） | CR-2026-060-TASK-02 | cmd-01 | revert TASK-02 commit |
| FR-03 PLAN/TASK、Coding、测试与代码评审对齐 | §3.2 中段/§4.5 | CR-2026-060-TASK-03 | cmd-03 | revert TASK-03 commit |
| FR-04 回写成为确定性投影 | §3.1 writeback/archive 行/§4.4/§4.6/§4.8 | CR-2026-060-TASK-04 | cmd-04 | revert TASK-04 commit |
| FR-05 Pipeline、规划与审批输入契约对齐 | §4.9/§3.2 approve/规划/竞品/resume 段 | CR-2026-060-TASK-04（关联 TASK-02 的四个 approve-*） | cmd-01 | revert TASK-04（及 TASK-02 中 approve 段）commit |
| FR-06 兼容、变更组织与验证闭环 | §1.1 四组/§7/§9 | CR-2026-060-TASK-04（关联 TASK-01～03 的回归向量） | cmd-06 | 整体重置到 `860288ce` |

## 6.2 关键 AC 覆盖矩阵（唯一 TASK owner + 唯一 cmd-NN）

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-01 注册三层必填与幂等（含 registrationAt 三处相等、changed=false 同构、recover_command 含 `--target-spec-id`） | §4.3 / §6.2 AC-01 | CR-2026-060-TASK-01 | cmd-02 |
| AC-02 模式与目标事实（顶层唯一 `TARGET_SPEC_AUTHORITY_DRIFT`；本 CR 不被回填；new writeback 权威=strict txws） | §2.2 / §2.3 / §4.1 / D-06 | CR-2026-060-TASK-01 | cmd-02 |
| AC-03 版本门禁与评审顺序（pre-review + advance 直连零写入；version-set 零改动回归） | §4.2 / §4.7 / §3.1 version-set 行 | CR-2026-060-TASK-01 | cmd-03 |
| AC-04 PRD authority | §3.2 write-requirement-prd | CR-2026-060-TASK-02 | cmd-01 |
| AC-05 作者/reviewer 对称 | §3.2 review-requirement / write-tech-design / review-tech-design | CR-2026-060-TASK-02 | cmd-01 |
| AC-06 技术闭合 | §3.2 / §5 D-01..D-06（本 CR SDD 已 PASS，实施期不回退） | CR-2026-060-TASK-02 | cmd-01 |
| AC-07 工作区与计划（两张稳定表、FR 只出现一次、resources 透传） | §3.2 write-dev-plan / 本 plan §5.1/§6.1 | CR-2026-060-TASK-03 | cmd-01 |
| AC-08 任务账本与数量（恰四 TASK、`--count-hint 4` 写入前校验） | §4.5 | CR-2026-060-TASK-03 | cmd-03 |
| AC-09 代码证据（sourceRevision + 日志哈希 + review-code 五字段） | §3.2 implement-code / write-test-report / review-code | CR-2026-060-TASK-03 | cmd-06 |
| AC-10 回修与审批顺序（evidence-only 回修链、blocker 清空前不可达 human approval） | §3.2 review-code / 四个 approve-* | CR-2026-060-TASK-03 | cmd-01 |
| AC-11 new/legacy writeback 输入合同 | §4.4 / §2.2.3 | CR-2026-060-TASK-04 | cmd-04 |
| AC-12 确定性投影（tasks 零发布 + new traceability 引用链） | §4.6 / §4.8 | CR-2026-060-TASK-04 | cmd-04 |
| AC-13 归档边界（journal 重放、review-alignment 只读） | §2.2.4 / §4.4 archive 段 | CR-2026-060-TASK-04 | cmd-05 |
| AC-14 规划输入闭环 | §3.2 规划/竞品/resume 段 | CR-2026-060-TASK-04 | cmd-01 |
| AC-15 机器事实不漂移（8 条 Pipeline JSON） | §4.9 | CR-2026-060-TASK-04 | cmd-01 |
| AC-16 回归与边界 | §6.2 AC-16 / §7 | CR-2026-060-TASK-04 | cmd-06 |
| AC-17 交付组织（恰四 TASK、不新增状态/节点/账本） | §1.1 / §9 | CR-2026-060-TASK-04 | cmd-03 |
| AC-18 遗漏 Skill 与只读边界（四个 approve-* + 规划消费 + review-alignment） | §3.2 approve/规划/review-alignment | CR-2026-060-TASK-02 | cmd-01 |

AC-03 的 version-set 信封由 cmd-06 回归（zero_diff 消费，不在 TASK-01 改 `cmdVersionSet`）；主路径「unassigned 的 gate/advance 直连拒绝」以 cmd-03 为唯一证据。AC-10 的四个 approve 合同正文由 TASK-02 落盘，回修链路由由 TASK-03 落盘；唯一 owner 取回修链可达性（TASK-03）。

# 7. 冻结面与自检清单

## 7.1 批准范围对齐（SDD §9，只读翻译）

- **scope_in**：四个 TASK 恰为 G1..G4；`crctl.mjs` 的 register 新 flag/统一结果 builder、pre-review gate、preflightAdvance 只读 guard、writeback-apply/archive mode 分支与 strict authority、`cmdTaskInit --count-hint`；`workspace-transactions.mjs` 的 `target-spec-id`/`registrationAt`/inputDigest/recoverCommand、tasks preflight、traceability new 分支参数、archive journal payload；`writeback-traceability.mjs` new 分支（legacy 逐字节保留）；§3.2 列明 SKILL.md；8 条 Pipeline JSON 的 prompt 收敛；`review-alignment` 只读化；AC-16 测试与 lint。
- **scope_out**：不修改状态机/转换/approval grant/reviewLoop 规则/traceability evidence 结构；不新增 Pipeline 节点、Skill、Agent、状态、账本、事务层、Runner、contract-version、feature flag、迁移器、独立 ADR；不做历史 CR 批量回填；不实现新业务功能/UI/HTTP API。
- **zero_diff**：见 §5.2 第 5 条。已解除全冻结、改为精确冻结的内核：`performAdvance`（只允许 `preflightAdvance` 增只读分支）、`cmdTaskInit`（只允许 `--count-hint` 写入前校验）、`applyWritebackAtomic`（只允许入口参数来源、tasks preflight 与 traceability new 分支参数）、`writeback-traceability.mjs`（只允许新增 new 分支）。
- **follow_up**：`crctl upgrade-check` 删除计划；外部调用量优化；规划类审批是否迁移 CR 审批机制；BR-1/BR-2 根因修复。禁止把 follow_up 做成当前 TASK。

## 7.2 FR-10 自检

本 CR 的交付 TASK（TASK-01～TASK-04）不含 merge / writeback / archive /「完成于 merge 的发布准备」作为完成前置。TASK-04 实现的是 writeback/archive **代码与测试**（G4 变更组），完成边界 = 实现已落盘且 cmd-04/cmd-05 新增向量绿（developing 内可被 `crctl task done` 登记）。本 CR 自身的 merge/writeback/archive 走既有流程节点，审计事实以 `approval.yml`、`merge-commits.yml`、checkpoint 为准，不进 TASK ledger。
