---
id: CR-2026-060-sdd
type: SDD
cr-ref: CR-2026-060
title: CR 全生命周期合同对齐 技术设计
target-version: "0.33"
status: draft
created: 2026-09-02T20:40:38+08:00
updated: 2026-09-02T20:40:38+08:00
---

# 1. 架构概览

## 1.1 变更边界与四个变更组

本 CR 的全部可交付代码与文档变更落在 `tools` 仓（方法论包），与 PRD §3.4 的四个 TASK 一一对应：

| 变更组 | TASK | 触及面 | 主文件 |
|---|---|---|---|
| G1 注册与 authority | TASK-1 | `crctl register` 新必填 flag、双账本字段、成功 JSON 键、pre-review gate、`writeback-apply`/`archive` 的 mode 入口 | `skills/shared/crctl/scripts/crctl.mjs`、`scripts/lib/workspace-transactions.mjs` |
| G2 PRD/SDD writer-reviewer | TASK-2 | 六个 SKILL.md 的参数/顺序/路由合同修订 | `skills/requirement/{write-requirement-prd,review-requirement}`、`skills/develop/{write-tech-design,review-tech-design}` 及 PRD/SDD 相关模板引用 |
| G3 PLAN/TASK/Coding/test/review | TASK-3 | 两张 PLAN 表、恰四 TASK 断言、workspace/证据/回修合同 | `skills/develop/{write-dev-plan,write-dev-tasks,review-dev-plan,implement-code,write-test-report,review-code}` |
| G4 writeback/archive 与 legacy 兼容 | TASK-4 | new/legacy 双路径解析、三段 writeback stage、archive 投影 | `crctl.mjs` 的 `cmdWritebackApply`/`cmdArchive`、`skills/writeback/{writeback-prd-sdd,writeback-tasks,writeback-traceability}`、`skills/cr/cr-archive` |

跨组的横切项：FR-05 的 8 条 Pipeline prompt 收敛（`pipeline-templates/*.pipeline.json`）、`review-alignment` 只读化、规划/竞品/resume 消费 Skill 的输入对齐（`skills/planning/`、`skills/competitive/`、`skills/cr/cr-show`）。横切项不另建 TASK，归入四组中负责对应消费面的组（Pipeline prompt 与 review-alignment 归 TASK-4 前的 G4 兼容面或按其上游归属；具体落位见 PLAN 交付覆盖表）。

## 1.2 模块边界与依赖方向

沿用 tools 仓 `ARCHITECTURE.md` 的四层模型（Pipeline → Skill → crctl → 账本），本 CR 不新增层、不新增状态、不新增账本：

```text
pipeline-templates/*.pipeline.json    # 只保留节点顺序/参数传递/reviewLoop/失败路由
   ↓ 调用（只读参数 + 透传结构化结果）
skills/{组}/{skill}/SKILL.md          # 业务判断 + 落盘非受控产物 + 一次深原语调用
   ↓ 唯一写入入口
crctl.mjs（register/gate/version-set/writeback-apply/archive/task）
   ├─ lib/workspace-transactions.mjs  # registerCr/buildRegistrationTexts/authority resolver
   ├─ lib/durable-tx.mjs             # journal/CAS/recoverable write-set（不动）
   ├─ gates.json + tools dir-graph.yaml  # 状态机与门禁唯一事实源（本 CR 不新增状态/转换）
   └─ skills/writeback/scripts/      # 内容文件回写（不动，只消费新 mode 输入）
```

- **G1 的写入点**：`buildRegistrationTexts`（cr.md 与 `_backlog.yml` 的生成器）新增 `target-spec-id` 字段行；`registerCr` 的 `inputDigest` 纳入 `targetSpecId`；`cmdRegister` 新增校验与 JSON 键映射。
- **G1 的读取点**：新增单一纯函数 `resolveTargetSpecMode(ctx, cr)`（放 `crctl.mjs`，与既有 `readCrMdTargetVersion`/`readBacklogTargetVersionField` 同层），被 `cmdGate` 的 pre-review 分支、`cmdWritebackApply`、`cmdArchive` 三个消费方共享，禁止各自推断。
- **G4 的 authority 来源**：复用 CR-2026-058 已落地的 `resolveWritebackAuthorityPath`（窄只读、永不抛、回退 cr-worktree），new mode 的 spec/version authority 从它返回路径上的 `cr.md` + `_backlog.yml` 读取。

## 1.3 关键流程总览

```text
[A 注册] requirement-authoring inputs（registration_key/target_spec_id/target_version 必填）
   → requirement-register → crctl register
   → 校验 --target-spec-id（缺失/空→REGISTER_TARGET_SPEC_ID_REQUIRED，非法→REGISTER_TARGET_SPEC_ID_INVALID，
      均先于 BAD_ARGS 与锁/journal/账本）
   → registerCr 双账本写入 target-spec-id → 成功 JSON 顶层含 cr_id/target_spec_id/operational_workspace/
      tx_id/target_version/side_effects/recover_command（全 snake_case）
   → Skill 逐字透传 cr_id + operational_workspace 到 execution_context（不解析、不拼接、不持有 resources 快照）

[B 需求评审前门禁] review-requirement 先跑 crctl gate <cr> --for requirement-reviewing --mode pre-review
   → 只读 mode 判据 + cr.md.target-version（不读 PRD/annotation/passCondition）
   → pass 才写临时 payload → crctl review-record → PASS record 后由 advance 消费完整 statusGates
   → guard block：route=version-set，零评审记录/零写入

[C 回写] code-approved → crctl merge（不变）→ writeback-apply（mode 分支）：
   new：spec/version 可省略，从 txws authority 读取；显式传值只做相等校验；milestone 参数=BAD_ARGS
   legacy：spec/version/milestone-file 按现行行为必填
   → archive：new 可省 spec-id（读 authority），legacy writing-back 必填

[D TASK 数量] write-dev-tasks 传 task_count_hint=4 → plan.md 预分配四组各一 ID
   → crctl task init → Skill 断言索引恰 4 条且与四组一一对应，否则 TASK_COUNT_MISMATCH abort
```

# 2. 数据模型

## 2.1 新增字段：`target-spec-id`

| 面 | 键名 | 值约束 | 写入者 |
|---|---|---|---|
| CLI flag | `--target-spec-id` | 非空；匹配 `^[a-z0-9][a-z0-9._-]*$`；禁止 `/`、`\`、CR、LF、路径段 | `cmdRegister` 校验，`registerCr` 消费 |
| `cr.md` frontmatter | `target-spec-id` | 同上 | `buildRegistrationTexts`（register 事务内） |
| `_backlog.yml` 条目 | `target-spec-id` | 同上，与 cr.md 全等 | 同上 |
| register 成功 JSON | `target_spec_id` | 账本值的唯一 JSON 映射 | `cmdRegister` 输出层 |

## 2.2 mode 判定（唯一裁决的代码实现）

`resolveTargetSpecMode(ctx, cr)` 为纯读取函数，返回 `{mode:'new', targetSpecId}` 或 `{mode:'legacy'}`，或抛 TxError：

1. 两处字段均缺失 → `legacy`（仅限本 CR 代码合入前由旧 register 产生的 CR；新注册因 flag 必填在结构上不可能产生缺失形态，故无需时间戳判据——PRD §3.1「不提供新的 legacy 注册入口」）。
2. 仅一处存在 → `TARGET_SPEC_AUTHORITY_DRIFT`（硬失败，零写入，不猜模式）。
3. 两处均存在：任一非法 → `TARGET_SPEC_AUTHORITY_INVALID`；值不一致 → `TARGET_SPEC_AUTHORITY_DRIFT`；均合法且全等 → `new`。

该函数被 pre-review gate、writeback-apply、archive 共用；PRD §3.1 已禁止 Pipeline/Skill/CLI 各自推断，代码层由单一函数落实。

## 2.3 错误码 delta

新增顶层错误码（`fail()` 第一参数）：`REGISTER_TARGET_SPEC_ID_REQUIRED`、`REGISTER_TARGET_SPEC_ID_INVALID`、`TARGET_SPEC_AUTHORITY_DRIFT`、`WRITEBACK_SPEC_REQUIRED`、`WRITEBACK_SPEC_MISMATCH`。

pre-review gate 内部 check code（`GATE_BLOCKED` 外层信封内的 `checks[].code`，非顶层码）：`TARGET_SPEC_AUTHORITY_MISSING`、`TARGET_SPEC_AUTHORITY_INVALID`、`TARGET_SPEC_AUTHORITY_DRIFT`、`TARGET_VERSION_MISSING`、`TARGET_VERSION_INVALID`、`TARGET_VERSION_UNASSIGNED`。

复用既有码：`WRITEBACK_VERSION_INVALID`/`WRITEBACK_VERSION_MISMATCH`/`WRITEBACK_VERSION_UNASSIGNED`（CR-2026-057 已存在）、`ARCHIVE_SPEC_REQUIRED`（已存在）、`BAD_ARGS`、`REGISTRATION_INPUT_MISMATCH`、`GATE_BLOCKED`。不新增错误码族、不新增平行信封。

# 3. 接口契约

HTTP API：`N/A`（本 CR 不新增或修改 HTTP endpoint/request/response/error/HTTP 权限契约；PRD §3.2 已冻结，需求评审 `HTTP_API契约闭包` 维度同判）。

## 3.1 CLI 契约实现映射（PRD §3.2 矩阵 → 代码落点）

| 契约行 | 实现落点 | 关键实现说明 |
|---|---|---|
| `register --target-spec-id` | `cmdRegister`（crctl.mjs:3080） | 在既有必填 flag 循环**之前**先判 `--target-spec-id`：缺失/空→`REGISTER_TARGET_SPEC_ID_REQUIRED`（优先且唯一，不落 BAD_ARGS）；再按 §2.1 正则校验→`REGISTER_TARGET_SPEC_ID_INVALID`；`source` 单行 scalar 拒绝 CR/LF（复用既有 scalar 处理，注册期不解析路径）。`inputDigest` 增加 `targetSpecId`（同 key 换 spec → `REGISTRATION_INPUT_MISMATCH`） |
| register 成功 JSON | `cmdRegister` 输出层 + `registerCr` 结果 | 顶层键统一 snake_case：`op, cr_id, target_spec_id, operational_workspace, tx_id, phase, changed, target_version, side_effects, recover_command, outbox, warnings`。`operational_workspace` 由 `resolveOperationalWorkspace(ctx, cr)` 生产（注册完成时 CR 处于 `drafting` 前 finalize 态 → 返回 cr-worktree 路径，source=`cr-worktree`）；`recover_command` 由 `registerCr` 已有构造提升到结果字段 |
| `gate --for requirement-reviewing --mode pre-review` | `cmdGate`（crctl.mjs:956） | 新增分支：`flags.mode==='pre-review'` 且 `flags.for==='requirement-reviewing'` 时走新 `runPreReviewGateChecks(ws, cr)`，**不**走 `runGateChecks` 的 statusGates（绝不读 PRD/requirement annotation/passCondition）。其他 `--for` 配 `--mode pre-review` → `BAD_ARGS`。输出 `{cr, for, mode:'pre-review', pass, checks:[{type, code, ok, why}]}`；fail 时 exit 1 + stderr `{error:{code:'GATE_BLOCKED',...}}`，零写入（无 payload/annotation/review-loop/trace/status/outbox/journal/commit）。真实版本且尚无 PASS annotation 时 `pass=true` |
| `advance --to requirement-reviewing --trigger review-requirement` | 既有 `cmdAdvance` | 不改；new mode `unassigned` 的拒绝由 pre-review 前置承担（review-requirement Skill 在 review-record 前先跑 guard），advance 侧完整 passCondition 行为不变 |
| `version-set` | 既有 `cmdVersionSet`（crctl.mjs:2623） | **零改动**；PRD §3.2 该行的成功/幂等/错误优先级语义已由 CR-2026-057 实现，本 CR 只消费 |
| `writeback-apply` new/legacy 分支 | `cmdWritebackApply`（crctl.mjs:3401） | 参数形态校验（stage/未知 flag/candidate 拒绝）之后、任何读权威之前先 `resolveTargetSpecMode`。**new**：`--spec-id`/`--target-version` 可省略（省略=从 `resolveWritebackAuthorityPath` 定位的 txws/cr-worktree 权威读取）；显式传值在 candidate/journal 前与权威全等校验，不一致→`WRITEBACK_SPEC_MISMATCH`/`WRITEBACK_VERSION_MISMATCH`；权威缺失→`WRITEBACK_SPEC_REQUIRED`（版本缺/非法/`unassigned` 沿用既有 `WRITEBACK_VERSION_*` 码）；`--milestone-name/--brief/--milestone-file` 任一传入→`BAD_ARGS`。**legacy**：现行必填/`--milestone-file`（traceability）行为原样保留。`applyWriteback` 的 generator/candidate/manifest/journal 逻辑不动，仅入口参数来源不同 |
| `archive` new 可省 spec-id | `cmdArchive`（crctl.mjs:3368） | new mode：`--spec-id` 省略时从已完成 writeback authority 读取；legacy `writing-back`：必填（现行）。`ARCHIVE_SPEC_REQUIRED`/`ARCHIVE_TRACEABILITY_MISSING`/`ARCHIVE_TASKS_PENDING`/`ARCHIVE_TRACE_PENDING` 语义不变；不重放 generator、不重选 spec/version |

## 3.2 Skill 契约实现映射（PRD §3.3/§3.3.1 → SKILL.md 落点）

| Skill | 文件 | delta 要点 |
|---|---|---|
| `requirement-register` | `skills/requirement/requirement-register/SKILL.md` | 参数表 +`target_spec_id`（required）；Step 2 命令模板 +`--target-spec-id`；Step 3/4 改消费 snake_case 成功 JSON（`cr_id`/`operational_workspace`/`tx_id`/`recover_command`），输出摘要含 `operational_workspace` 透传说明；错误表 +`REGISTER_TARGET_SPEC_ID_REQUIRED/INVALID` 行 |
| `write-requirement-prd` | `skills/requirement/write-requirement-prd/SKILL.md` | 明确 title/summary/source/target-version/owner 只从 cr.md 读，Pipeline 重复字段不得覆盖；source 路径 containment/existence 在 writer 阶段校验；七类章节 + 成功指标 + 范围排除 |
| `review-requirement` | `skills/requirement/review-requirement/SKILL.md` | Step 1 与 Step 2 之间插入**固定顺序**：先 `crctl gate <cr> --for requirement-reviewing --mode pre-review`；guard pass 才写临时 `.crctl/tmp/review-requirement.yml` → `crctl review-record`；record=pass 才 `crctl advance`；guard block（含 new mode `unassigned`）→ route=`version-set`，不记录评审、不改状态 |
| `write-tech-design` / `review-tech-design` | `skills/develop/write-tech-design/SKILL.md`、`skills/develop/review-tech-design/SKILL.md` | writer 参数表 required=`cr_id,operational_workspace,resources`；七维作者/reviewer 标准成对表述；`SDD-CLOSE-*` 逐项关闭义务；术语硬化与 HTTP 条件基线沿用现状表述 |
| `write-dev-plan` / `write-dev-tasks` / `review-dev-plan` | `skills/develop/write-dev-plan/SKILL.md` 等 | plan 恰含两张稳定表（交付覆盖表：`FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`；证据命令表：`证据ID | repo | cwd | executable | args | timeout`）；tasks +`task_count_hint`（本 CR 固定 4），生成与 `crctl task init` 前后断言恰 4 且与四组一一对应，否则 `TASK_COUNT_MISMATCH` abort |
| `implement-code` / `write-test-report` / `review-code` | `skills/develop/…` | 实现依据只取 SDD/PLAN/TASK/目标仓规范/`resources[].worktreePath`（PRD 非并列合同）；test-report 执行 PLAN 证据命令表 canonical 门禁并发布 `sourceRevision`+日志哈希；review 输出固定五字段、不重跑测试、不新增 aggregate digest |
| 四个 `approve-*` | `skills/develop/approve-*.md` | required=`cr_id`；缺 approver 取对应 owner；只消费/返回 `crctl approve` 结构化结果；下一步统一「以 `crctl next {cr_id}` 为准」 |
| `writeback-prd-sdd` / `writeback-tasks` / `writeback-traceability` / `cr-archive` | `skills/writeback/…`、`skills/cr/cr-archive/SKILL.md` | new：spec/version 可省略（仅可重复校验），milestone 参数=N/A；legacy：spec/version（trace 加 milestone-file）必填。三者只输出一次 `crctl writeback-apply` 结果；archive 输出一次 `crctl archive` 结果 |
| `review-alignment` | `skills/review/review-alignment/SKILL.md` | 任意状态按需只读：输出 `{skill,cr_id,spec_id,current-status,result,drifts,summary}`，不落盘、不写 traceability、不读 mtime/backlog merge-commit/fingerprint；不调用任何 crctl 写命令 |
| 规划/竞品/market/resume 消费面 | `skills/planning/…`、`skills/competitive/…`、`skills/cr/cr-show/SKILL.md` | 按 PRD §3.3.1 矩阵修必填输入（topic/context/intent/brief/updates-block/product-snapshot/confirmed/prev_outputs/review_feedback/self_repair_attempt/reportPath|reportDraft 二选一、competitor-id(s)+lookback-days）；resume-cr 展示节点调用 `cr-show(cr-id, section: all)` 并消费结构化详情 |

## 3.3 术语硬化（Step 2.5 预检结论）

| PRD canonical 术语 | 代码别名/映射 | 代表边界场景（已按 PRD §3.1/§3.2 验证） |
|---|---|---|
| `new mode` / `legacy mode` | `resolveTargetSpecMode` 返回 `mode:'new'|'legacy'` | 单侧 `target-spec-id`（cr.md 有、backlog 无）→ `TARGET_SPEC_AUTHORITY_DRIFT` 零写入，不猜模式 |
| `target-spec-id`（账本键）/ `--target-spec-id`（flag）/ `target_spec_id`（JSON 键） | 三面各自唯一，无第二别名 | register 成功 JSON 只含 `target_spec_id`；下游 Skill 不得读 `target-spec-id` 形式的 JSON 键 |
| `operational_workspace`（register JSON + execution_context，snake_case）vs `operationalWorkspace`（workspace inspect 只读输出，历史 camelCase） | 两键共存于不同表面，值同源（`resolveOperationalWorkspace`） | requirement-authoring 的 execution_context 只含 `operational_workspace`；coding 节点读 inspect 的 `operationalWorkspace` + `resources[].worktreePath`。任一节点不得按 `.rayai-worktrees/{repo}/requirement/{cr}` 拼路径 |
| `unassigned` | 既有 `normalizeTargetVersion` 语义 | new mode `unassigned` 在 pre-review 被 `TARGET_VERSION_UNASSIGNED` 拒绝，只能先 `version-set` |

PRD §3.1/§3.2 已对上述术语完成唯一裁决（含判据表与命名矩阵），SDD 不引入新裁决、无待澄清语义冲突。

# 4. 关键算法与流程

## 4.1 `resolveTargetSpecMode`（G1/G4 共用，伪代码）

```text
read cr.md frontmatter field 'target-spec-id' -> A（缺 = missing）
read _backlog.yml 条目 field 'target-spec-id' -> B（缺 = missing）
if A missing and B missing: return { mode: 'legacy' }
if A missing xor B missing: fail TARGET_SPEC_AUTHORITY_DRIFT（零写入）
if not valid(A) or not valid(B): fail TARGET_SPEC_AUTHORITY_INVALID   # valid = ^[a-z0-9][a-z0-9._-]*$ 且无 / \ CR LF
if A != B: fail TARGET_SPEC_AUTHORITY_DRIFT
return { mode: 'new', targetSpecId: A }
```

行尾纪律：读取一律 `\r\n→\n` 规范化后按行匹配；跨行正则匹配失败硬失败（复用既有 `readFrontmatter`/`readBacklogTargetVersionField` 的硬失败路径，不静默降级）。

## 4.2 pre-review 检查序列（`runPreReviewGateChecks`）

```text
checks = []
mode = resolveTargetSpecMode(ctx, cr)            # legacy 时跳过 target-spec 三检查
if new mode:
  按 §4.1 的失败码映射为 check code：TARGET_SPEC_AUTHORITY_MISSING / _INVALID / _DRIFT
v = read cr.md target-version（既有 readCrMdTargetVersion）
  missing -> TARGET_VERSION_MISSING；normalize 失败 -> TARGET_VERSION_INVALID
  value == 'unassigned' -> TARGET_VERSION_UNASSIGNED（仅 new mode 阻断；legacy 只做既有格式校验）
pass = 全部 check.ok
输出 {cr, for:'requirement-reviewing', mode:'pre-review', pass, checks}
pass=false -> stderr {error:{code:'GATE_BLOCKED', message, gate}}，exit 1，零写入
```

## 4.3 register 校验顺序（错误优先级，PRD §3.2 冻结）

```text
1. --target-spec-id 缺失或空 -> REGISTER_TARGET_SPEC_ID_REQUIRED   # 优先且唯一，先于 BAD_ARGS
2. 非法（正则/路径字符/CR/LF）-> REGISTER_TARGET_SPEC_ID_INVALID
3. 既有必填 flag 循环 -> BAD_ARGS
4. registerCr 内 --target-version 规范化 -> REGISTER_VERSION_INVALID（既有）
5. journal inputDigest（含 targetSpecId）冲突 -> REGISTRATION_INPUT_MISMATCH（既有）
6. trunk dirty -> REGISTRATION_TRUNK_DIRTY（既有）
以上全部在锁/journal/账本写入前；事务中断只重跑 recover_command。
```

## 4.4 writeback-apply mode 分支顺序

```text
1. stage/未知 flag/candidate 拒绝（既有）-> BAD_ARGS
2. mode = resolveTargetSpecMode(ctx, cr)
3. new：milestone 任一 flag 传入 -> BAD_ARGS
   authority = resolveWritebackAuthorityPath(ctx, cr) 定位路径 -> 读 cr.md(target-version) + cr.md/_backlog(target-spec-id)
   省略 spec/version -> 取权威值；显式传值 != 权威 -> WRITEBACK_SPEC_MISMATCH / WRITEBACK_VERSION_MISMATCH
   权威缺失 -> WRITEBACK_SPEC_REQUIRED；版本缺/非法/unassigned -> 既有 WRITEBACK_VERSION_* 码
4. legacy：现行路径（spec/version 必填，traceability milestone-file 必填）
5. 以上全部通过后才进入 applyWriteback（candidate/journal/manifest/commit/push），失败零写入
```

## 4.5 TASK 数量断言（G3，Skill 级 abort，不新增 crctl 错误码）

```text
write-dev-tasks(cr_id, task_count_hint=4):
  plan.md 已含四变更组各预分配一个 TASK ID（G1..G4 -> TASK-1..4）
  生成 TASK-*.md -> crctl task init（既有 CAS）
  断言 tasks/_index.yml 条目数 == 4 且每个 TASK 与四组一一对应
  失败 -> abort TASK_COUNT_MISMATCH（零推进；review-dev-plan 同口径复核）
```

## 4.6 Pipeline prompt 收敛检查清单（FR-05.1，8 条 JSON 全部适用）

每条 `kind=skill` 节点 prompt 只保留五类信息（调用哪个 Skill/传哪些参数/依赖哪个前序结构化输出/消费哪些结果/失败如何 abort|skip|reviewLoop）。删改后逐条机械断言：不出现账本文件手工编辑步骤、不出现 `crctl` 算法副本、不出现「status→节点」映射表（下一步只写「以 `crctl next {cr_id}` 为准」）、`node.ref` 全部为 active Skill、节点数量与 `_index.yml` 一致、reviewLoop 的 `maxAttempts`/`replayNodes`/`passCondition` 与 checkpoint 顺序不变（AC-15）。

# 5. 技术选型与替代方案（决策记录）

## D-01 pre-review guard 放代码而非 gates.json

- **Decision**：`--mode pre-review` 的检查序列实现为 `crctl.mjs` 内独立函数 `runPreReviewGateChecks`，不写入 `gates.json#statusGates`。
- **Context**：`gates.json#statusGates` 是状态转换门禁的声明源，被 `preflightAdvance` 在每次 `advance` 时消费；pre-review 是 review-record 的**前置守卫**而非状态转换门禁，两者消费时机与失败语义不同（guard 失败零评审记录，advance 门禁失败保留评审记录）。
- **Alternatives**：A) 在 `gates.json` 增加 `requirement-reviewing` 门禁条目并在 `advance` 消费——会把版本守卫错位到 PASS record 之后，与 PRD §3.3 固定顺序冲突，且 `advance` 的既有调用方语义会被改动；B) 新增独立 JSON 配置——增加第二事实源，违反「不新增平行资产」。
- **Consequences**：pre-review 契约存在于 `crctl.mjs` + PRD §3.2 矩阵；未来若需扩展其他 stage 的 pre-review，须回到本决策评估。

## D-02 mode 判定单函数共享，禁止各消费端推断

- **Decision**：`resolveTargetSpecMode` 单一纯函数，pre-review gate / writeback-apply / archive 三处共用。
- **Context**：PRD §3.1 明确「本节是本 CR 实施和评审使用的唯一模式裁决，不允许 Pipeline、Skill、CLI 各自推断」；三处消费若各自实现两字段比对，漂移修复将三处不同步。
- **Alternatives**：A) 各命令内联判定——实现最短但违反 PRD 冻结的唯一裁决要求；B) 放入 `workspace-transactions.mjs` lib——可行，但三个消费方均在 `crctl.mjs`，就近放置减少跨文件依赖；写入方（`buildRegistrationTexts`）只写字面字段、不依赖判定函数。
- **Consequences**：新增字段读取逻辑集中一处；`TARGET_SPEC_AUTHORITY_*` 行为三面一致。

## D-03 不提供 legacy 注册入口（结构强制而非时间戳判据）

- **Decision**：legacy 判定仅由「两处字段均缺失」+「该形态只能由旧 register 产生」结构保证；不新增时间戳/flag/迁移器判据。
- **Context**：新 register 对 `--target-spec-id` 必填且校验先于一切写入，因此合入后新注册在结构上不可能产生两处均缺失的 CR；历史 CR 才可能缺字段。
- **Alternatives**：A) 按注册时间戳判 legacy——引入新字段与迁移语义，且历史 CR 无可靠时间戳；B) 显式 `--legacy` 入口——PRD 明确禁止「不提供新的 legacy 注册入口」。
- **Consequences**：判定逻辑无时间依赖、无迁移器；AC-02 的「CR-2026-060 不能被自动补字段」由「本 CR 不运行任何批量回填」保证（本 CR 自身作为 legacy 只读兼容走完回写归档，不回写自身字段）。

# 6. FR 到技术实现映射与 AC 级输出合同

## 6.1 FR 映射总表

| FR | 技术方案落点（节） | 主要 TASK |
|---|---|---|
| FR-01 注册合同与单一目标事实 | §3.1 register 行、§4.1、§4.3 | TASK-1 |
| FR-02 PRD/SDD 作者与 reviewer 标准对齐 | §3.2 前六行 | TASK-2 |
| FR-03 PLAN/TASK/Coding/测试/代码评审对齐 | §3.2 中段、§4.5 | TASK-3 |
| FR-04 回写成为确定性投影 | §3.1 writeback/archive 行、§4.4、§3.2 writeback 段 | TASK-4 |
| FR-05 Pipeline、规划与审批输入契约对齐 | §4.6、§3.2 approve/规划/竞品/resume 段 | TASK-1..4 横切（PLAN 覆盖表分配） |
| FR-06 兼容、变更组织与验证闭环 | §1.1 四组、§7、§9 | TASK-1..4 |

## 6.2 AC 逐项设计与验收映射

**AC-01（注册三层必填与幂等）**
- 设计落点：`requirement-authoring.pipeline.json` inputs（+`registration_key`/`target_spec_id` required）、`requirement-register/SKILL.md` 参数表、`cmdRegister` 校验段。
- 可观测结果：缺失 `target_spec_id` 的三层各自 fail；成功注册的 `cr.md` 与 `_backlog.yml` 含相同 `target-spec-id`；同 key 同输入重跑 `changed=false` 无新 commit/outbox/worktree；同 key 漂移→`REGISTRATION_INPUT_MISMATCH` 零写入。
- 可达性说明：校验置于 `BAD_ARGS` 循环与锁/journal 之前，合法输入不被前置过滤；幂等由既有 journal `inputDigest`（已纳入 `targetSpecId`）保证。

**AC-02（模式与目标事实）**
- 设计落点：`resolveTargetSpecMode`（§4.1）。
- 可观测结果：非法/单侧/不一致字段 → `TARGET_SPEC_AUTHORITY_DRIFT`（或 `_INVALID`）且零写入；CR-2026-060 自身两处均缺字段 → legacy，不被回填。
- 可达性说明：判定不依赖 CR-ID 特判与时间戳；本 CR 不含任何批量迁移/回填代码路径。

**AC-03（版本门禁与评审顺序）**
- 设计落点：`runPreReviewGateChecks`（§4.2）+ `review-requirement/SKILL.md` 固定顺序 + 既有 `cmdVersionSet`（零改动）。
- 可观测结果：new mode `unassigned` → `GATE_BLOCKED`/`TARGET_VERSION_UNASSIGNED`/exit 1 且临时 payload、annotation、review-loop、trace、outbox、journal、commit 全部不变；PASS record 后 `advance` 才跑完整 passCondition；`version-set` 的成功/幂等/错误优先级信封与 PRD §3.2 逐条一致。
- 可达性说明：guard 只读 mode 判据与 cr.md target-version，不依赖 PRD/annotation 存在性，故首次评审即可达；guard 零写入保证重复进入无副作用。

**AC-04（PRD authority）**
- 设计落点：`write-requirement-prd/SKILL.md`。
- 可观测结果：PRD frontmatter 的 title/summary/source/target-version/owner 与 cr.md 一致；source 为路径时 writer 阶段校验 containment/existence；七类章节齐全。
- 可达性说明：本 CR 的 PRD 已由需求期产出并评审 PASS（subject-sha256 `d74ac20a…`），本 AC 是 Skill 文本契约的回归项。

**AC-05（作者/reviewer 对称）**
- 设计落点：`write-requirement-prd`/`review-requirement` 两 SKILL 共用同一七维标准表述（FR-02.2）。
- 可观测结果：两 SKILL 的维度清单与 blocker/suggestion 分级规则文本一致；HTTP/CLI/Skill 契约首轮闭包清单（FR-02.3）两文档同表；本 CR 的 `HTTP_API契约闭包=N/A` 与 CLI/Skill 契约闭包已 PASS（requirement.yml）。
- 可达性说明：标准表是两份文档的共享文本，`lint-prompts.mjs` 可机械核对该表存在。

**AC-06（技术闭合）**
- 设计落点：`write-tech-design`/`review-tech-design` SKILL 与本文档。
- 可观测结果：本 CR 的 PRD 未产生 `SDD-CLOSE-*` 延后项（需求评审首轮已闭合适用契约域），本文档声明该项为空；术语硬化表见 §3.3；决策记录见 §5（含 Alternatives 与 Consequences）；SDD 未改变 PRD 已批准的产品结果。
- 可达性说明：评审者可对照 requirement.yml 的八个维度与本文档 §3/§5 核验。

**AC-07（工作区与计划）**
- 设计落点：`write-dev-plan/SKILL.md` 两张稳定表 + `write-tech-design`/`implement-code` 等 SKILL 的 `operational_workspace`/`resources` 参数合同。
- 可观测结果：plan.md 恰含两张表且每 FR 在覆盖表恰出现一次；每条验证命令有稳定证据 ID（`cmd-NN`）供 test-report 引用。
- 可达性说明：`resources[].worktreePath` 来自 `crctl workspace inspect` 原值透传，不拼接 `.rayai-worktrees` 固定路径。

**AC-08（任务账本与数量）**
- 设计落点：`write-dev-tasks/SKILL.md`（`task_count_hint=4` + 前后断言）+ §4.5。
- 可观测结果：plan.md 预分配恰四 ID 与四组一一对应；`crctl task init` 后索引恰 4 条；缺失/重复/第五个/跨组 → `TASK_COUNT_MISMATCH` 不推进开发启动；done 状态只经 `crctl task done`。
- 可达性说明：断言在 `task init` 后读索引做确定性计数，不依赖 agent 自觉。

**AC-09（代码证据）**
- 设计落点：`write-test-report/SKILL.md`（PLAN 证据命令表 canonical 门禁 + `sourceRevision`+日志哈希发布）与 `review-code/SKILL.md`（重算既有证据）。
- 可观测结果：源码/日志/命令漂移 → review-code block；review 输出恰含 `verdict/blockers/suggestions/dimensions/repair-target` 五字段，无新增 aggregate digest。
- 可达性说明：证据命令来自 PLAN 表（稳定 ID），test-report 与 review-code 引用同一 ID 集合。

**AC-10（回修与审批顺序）**
- 设计落点：四个 `approve-*` SKILL + code-implementation pipeline 的 reviewLoop/replayNodes（机器事实不变）。
- 可观测结果：evidence-only 回修路径 implement-code→test-report→checkpoint→freshness→review-code 保持；blocker 未清空不可达 human approval（既有 gates）；四个 approve 节点传完整 `cr_id`+approver；下一步提示统一 `crctl next`。
- 可达性说明：本 CR 不重排任何节点顺序与 passCondition（AC-15 同一断言）。

**AC-11（new/legacy writeback 输入合同）**
- 设计落点：`cmdWritebackApply` mode 分支（§4.4）+ 三个 writeback SKILL 参数表。
- 可观测结果：new 省略 spec/version 时从 txws authority 读取；显式不一致在 candidate/journal 前 `WRITEBACK_SPEC_MISMATCH`/`WRITEBACK_VERSION_MISMATCH` 零写入；new 传 milestone → `BAD_ARGS`/N/A；legacy 行为不变且本 CR（legacy）仍可完成 writeback/archive。
- 可达性说明：authority 定位复用 `resolveWritebackAuthorityPath`（既有，永不抛、回退 cr-worktree），finalize 后 txws 缺失时错误在权威读取层显式抛出而非静默降级。

**AC-12（确定性投影）**
- 设计落点：既有 `applyWriteback` generator 的幂等路径（同冻结输入 `changed=false`）+ TASK done 全量前置。
- 可观测结果：同冻结 PRD/SDD 重复 baseline 为 noop；任一 TASK 未 done 时 tasks writeback 零写入零发布；new traceability 引用链 `FR→SDD→TASK→repo@mergeSHA→cmd` 由冻结 PLAN/TASK/test-report/merge facts 生成。
- 可达性说明：本 CR 不改 generator 算法，只改输入来源与前置校验；引用链元素全部存在于冻结事实中。

**AC-13（归档边界）**
- 设计落点：`cmdArchive`（mode 感知 spec-id）+ `cr-archive/SKILL.md` + `review-alignment/SKILL.md` 只读化。
- 可观测结果：archive 仅三段投影 complete 且无 pending trace 时成功；writeback 不重做业务评审；review-alignment 不进入 feature-writeback Pipeline（现状已无该节点，保持）、不推进状态、不写 traceability、不读 mtime/merge-commit/fingerprint。
- 可达性说明：archive 前置门禁沿用既有 `ARCHIVE_*` 码，无新分支绕过。

**AC-14（规划输入闭环）**
- 设计落点：`product-planning.pipeline.json`、`market-to-plan.pipeline.json`、`competitive-radar.pipeline.json` 的节点参数映射 + 对应 SKILL 参数表（PRD §3.3.1）。
- 可观测结果：topic/context/intent/brief/updates-block/product-snapshot/confirmed/prev_outputs/review_feedback/self_repair_attempt/reportPath|reportDraft/competitor-id(s)+lookback-days 各按矩阵传入；规划审批只消费结构化 approve/reject+reason，不接 CR approve；resume-cr 展示节点调用 `cr-show(cr-id, section: all)`。
- 可达性说明：Pipeline prompt 只传参数名，参数校验在对应 SKILL；`node.ref` 有效性由 AC-15 的 `pipeline-structure.test.mjs` 断言。

**AC-15（机器事实不漂移）**
- 设计落点：8 条 Pipeline JSON 的 prompt 收敛（§4.6）+ 既有测试套件。
- 可观测结果：JSON 可解析、节点数与 `_index.yml` 一致、`node.ref` 全部 active Skill、顺序/reviewLoop/replayNodes/passCondition/checkpoint 前置保留；prompt 不含章节/账本/审批/测试/Git/generator 算法副本。
- 可达性说明：`lint-prompts.mjs`/`pipeline-structure.test.mjs` 作为回归断言在 TASK 收尾执行。

**AC-16（回归与边界）**
- 设计落点：`tools/skills/shared/crctl/scripts/test/` 与既有 lint/check 脚本。
- 可观测结果：`lint-prompts.mjs`、`check-skill-matrix.mjs`、`check-agents-contract.mjs`、`pipeline-structure.test.mjs` 通过；注册缺 spec/非法/单侧/不一致/同键漂移负向测试、new `unassigned` gate/advance 拒绝、version-set 全系、new writeback 省略/漂移/legacy 缺参/milestone 非法、源码日志漂移/TASK 未完成/受保护写入负向测试全部通过。
- 可达性说明：新增测试沿用 `node --test` 与既有 `CRCTL_FAULT_POINT` 注入机制（零新框架）；受保护写入测试复用 `rules.json` deny 面（本 CR 不改该面，见 §7.1）。

**AC-17（交付组织）**
- 设计落点：TASK-1..4 的提交边界与 `checkpoint` 收口。
- 可观测结果：CR worktree 无未提交改动；`tasks/_index.yml` 恰 4 条全部 done；multica 等未参与仓零 diff（本 CR 不改 multica 代码，见 §9 zero_diff）；不新增状态/Pipeline 节点/事务框架/ledger/Runner/contract-version/feature flag/迁移器。
- 可达性说明：变更面收敛在 tools 仓 `skills/`、`pipeline-templates/`、`scripts/`；knowledge-base 仓只有 `change-requests/CR-2026-060/` 文档。

**AC-18（遗漏 Skill 与只读边界）**
- 设计落点：§3.2 表格最后四行。
- 可观测结果：四个 `approve-*` 参数/状态/失败路由/crctl 独占写入按 PRD §3.3.1；规划消费面参数与落盘不漂移；`review-alignment` 任意状态只读调用验证（无 crctl 写命令、无 traceability/status/annotation/Git 写入、无 mtime/merge-commit/fingerprint 读取）。
- 可达性说明：`review-alignment` 只读性由其 SKILL 文本 + 静态 lint 断言（禁止写命令与写路径措辞）双重保证。

# 7. 安全与性能考量

## 7.1 安全控制点

- **路径与字段注入**：`--target-spec-id` 正则白名单（小写字母数字 `._-`）在 `cmdRegister` 与 `resolveTargetSpecMode` 双处校验，天然拒绝路径穿越/CRLF 注入（NFR-06）；`source` 保持注册期不解析路径。
- **受保护账本**：本 CR 不修改 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny` 与 git 白名单（§9 zero_diff 明确冻结）；`cr.md`/`_backlog.yml` 的新字段写入只发生在 `registerCr` 的 write-set 内（既有 CAS + journal），无第二写入通道。
- **审批无旁路**：四个 `approve-*` 与 pre-review guard 均不改 TTY/grant/CAS 算法；guard 零写入保证失败不留评审残迹。
- **漂移硬失败**：`TARGET_SPEC_AUTHORITY_*`、`WRITEBACK_SPEC_MISMATCH` 等全部在 candidate/journal 前 fail，无部分账本（NFR-02）。

## 7.2 性能

- 新增逻辑均为 O(1) 或 O(文件行数) 的纯读取（frontmatter 行匹配、backlog 条目行匹配），不引入网络调用；register/writeback 的既有锁与 journal 开销不变。
- pre-review gate 与 mode 判定是 `status`/`gate` 既有读取路径的常数级扩展，无缓存一致性负担（每次现读，符合「git 是权威」不变量）。

# 8. Prompt 采纳影响（必填节：本 CR 触及 `crctl.mjs` 命令面）

本 CR 新增/变更 `crctl.mjs` 的命令入口（`register --target-spec-id`、`gate --mode pre-review`、`writeback-apply`/`archive` 的 new-mode 参数语义）；`rules.json` 的 `protectedPaths.deny` 面零变更（§7.1）。以下 Skill 的 prompt 若仍按旧调用形态执行将失效，必须改为采纳新能力：

| Skill 路径 | 现状（旧调用形态） | 应改为的调用方式 |
|---|---|---|
| `skills/requirement/requirement-register/SKILL.md` | 调用 `crctl register` 不带 `--target-spec-id` | 必带 `--target-spec-id`；消费 snake_case 成功 JSON 的 `cr_id`/`operational_workspace`/`tx_id`/`recover_command` |
| `skills/requirement/review-requirement/SKILL.md` | 直接写临时 payload → `crctl review-record` | 先 `crctl gate <cr> --for requirement-reviewing --mode pre-review`，pass 后才 review-record；guard block 路由 version-set |
| `skills/writeback/writeback-prd-sdd/SKILL.md`、`writeback-tasks/SKILL.md`、`writeback-traceability/SKILL.md` | 始终显式传 `--spec-id`/`--target-version`/`--milestone-file` | new mode 省略 spec/version（显式值仅作相等校验）；traceability 的 milestone 参数在 new mode 为 N/A |
| `skills/cr/cr-archive/SKILL.md` | `crctl archive <cr> --spec-id <id>` 恒传 | new mode 可省略 `--spec-id`（从 writeback authority 读取） |
| `skills/cr/cr-show/SKILL.md`（resume-cr 展示面） | Pipeline 内自建 CR 详情字段清单 | 只调用 `cr-show(cr-id, section: all)` 消费结构化详情，不复制字段清单 |
| `skills/requirement/requirement-authoring` 相关 Pipeline prompt | 在 node-1 prompt 内写 execution_context YAML 模板（含 owners/knowledge_base_worktree 快照） | 只透传 register JSON 的 `cr_id + operational_workspace`；owners 事实从 cr.md 读取，不再持有 resources 快照 |

`review-tech-design` 与人工审批（`approve-tech-design`）须逐条核对本表：每项在新能力合入后是否有残留旧形态调用。

# 9. 批准范围（契约必填章节）

- **scope_in（本 CR 必须交付）**：PRD §3 的 FR-01..FR-06 与 AC-01..AC-18 所约束的全部 delta——`crctl.mjs`（register 新 flag/JSON 键、pre-review gate、writeback-apply/archive mode 分支）、`workspace-transactions.mjs`（buildRegistrationTexts/inputDigest）、§3.2 列明的全部 SKILL.md 合同修订、8 条 Pipeline JSON 的 prompt 收敛与参数映射修订、`review-alignment` 只读化、§6.2 与 AC-16 列明的测试与 lint 断言；四个 TASK 恰为 G1..G4 一一对应。
- **scope_out（明确排除）**：不修改状态机/转换/approval grant/reviewLoop 规则/traceability evidence 结构；不新增 Pipeline 节点、Skill、Agent、状态、账本、事务层、Runner、contract-version、feature flag、迁移器、独立 ADR；不做历史 CR 批量迁移/回填；不实现任何新业务功能/UI/HTTP API。
- **zero_diff（明确不得改动）**：`gates.json` 的状态/转换/审批证据声明、`rules.json` 的 `protectedPaths.deny` 与 git 白名单、`cmdVersionSet`/`normalizeTargetVersion`/`cmdAdvance`/`performAdvance`/`cmdApprove`/`cmdReviewRecord`/`cmdTask*`/`applyWriteback` 与 `archiveCr` 的事务/generator 内核（仅入口参数来源可改）、`durable-tx.mjs`、writeback scripts 的内容生成器、`multica` 仓全部文件、`specs/`/`delivery/`/主工作区同名 CR 目录。
- **follow_up（留给后续 CR）**：`crctl upgrade-check` 及其删除计划（CUSTOM-TODO-009，与本 CR 无关）；外部调用量优化目标（ARCHITECTURE.md §7a，观测指标，本 CR 不承诺达成）；规划类审批未来是否迁移 CR 审批机制（PRD 明确本 CR 不迁移）。

# 10. 既有实现依赖与事实

以下全部依赖均来自 tools 仓 `requirement/CR-2026-060` worktree，HEAD `860288ce96d568ed31a86a8c478d1cfa7f1087e9`（kb 仓 HEAD `269ca7b3088abb0b7f9ff5f2689f627ba4a994db`）；无待核实依赖。

1. repo: tools
   relative path: `skills/shared/crctl/scripts/crctl.mjs`
   stable symbol/对象: `cmdRegister`（:3080）、`cmdGate`/`runGateChecks`（:956/:550）、`cmdWritebackApply`（:3401）、`cmdArchive`（:3368）、`cmdVersionSet`（:2623）、`normalizeTargetVersion`、`readCrMdTargetVersion`/`readBacklogTargetVersionField`（:2564）
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: 本 CR 的五个命令面变更全部挂接在这些既有函数上（新分支/新校验/新 JSON 键）；version-set 与规范化函数零改动，是 pre-review 版本守卫与 writeback 版本校验的既有权威实现。

2. repo: tools
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `registerCr`（:654）、`buildRegistrationTexts`（:347）、`resolveOperationalWorkspace`（:208）、`resolveWritebackAuthorityPath`（:236）
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: 双账本字段写入点（buildRegistrationTexts）与 journal inputDigest 位于 registerCr；register JSON 的 `operational_workspace` 与 new-mode writeback authority 均复用既有 resolver，不改其判定逻辑。

3. repo: tools
   relative path: `skills/shared/crctl/gates.json`、`dir-graph.yaml`
   stable symbol/对象: `statusGates`、`approvalStages`（evidence/passCondition/requireFiles 声明）
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: 状态机（15 具名状态 + `(new)`；28 声明转移、wildcard 展开 50 条）与门禁声明源零改动；pre-review 不走 statusGates（D-01）。

4. repo: tools
   relative path: `pipeline-templates/requirement-authoring.pipeline.json` 等 8 条 + `pipeline-templates/_index.yml`
   stable symbol/对象: 节点 `reviewLoop`/`passCondition`/`replayNodes`/checkpoint 顺序、节点计数
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: FR-05 只收敛 prompt 文本与 inputs 必填项，机器事实字段（节点数量/reviewLoop 配置）是 AC-15 断言基线，不得漂移。

5. repo: tools
   relative path: `skills/shared/controlled-shell/rules.json`
   stable symbol/对象: `protectedPaths.deny`、git 白名单 shapes
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: 本 CR 不新增受保护路径与 git 操作面；deny 面是 AC-16 受保护写入负向测试的既有权威源（zero_diff）。

6. repo: tools
   relative path: `skills/shared/crctl/scripts/test/`、`pipeline-templates/test/`、`skills/shared/crctl/scripts/{lint-prompts,check-skill-matrix,check-agents-contract}.mjs`
   stable symbol/对象: `node --test` 套件与 `CRCTL_FAULT_POINT` 故障注入机制
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: AC-16 的新增正反用例沿用既有测试入口与注入点；lint 脚本是 AC-15 的机器断言载体。

7. repo: ai-first-platform-docs
   relative path: `change-requests/CR-2026-060/prd.md`
   stable symbol/对象: 契约基线（subject-sha256 `d74ac20a97dcaf92c4fbc3d957326a104a20d3e0befe91e0df37198687737586`）、§3.1 模式裁决表、§3.2 CLI 矩阵、§3.3/3.3.1 Skill 矩阵
   commit SHA: 269ca7b3088abb0b7f9ff5f2689f627ba4a994db（审批落盘 commit 含本文件）
   依赖结论: 本 SDD 的全部接口与范围以该 PRD 为唯一契约基线，禁止回退或扩大；PRD 评审 verdict=pass（`review-annotations/requirement.yml`）。

8. repo: tools
   relative path: `ARCHITECTURE.md`
   stable symbol/对象: §4 分层依赖方向、§5 七条硬不变量、§6 刻意不做
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: 本 CR 不新增层/状态/账本通道，直接受不变量 1/2/4/7 约束；「独立账本操作脚本库」否决（§6）沿用。

9. repo: ai-first-platform-docs
   relative path: `change-requests/CR-2026-060/cr.md`、`change-requests/_backlog.yml`（本 CR 条目）
   stable symbol/对象: 两处均无 `target-spec-id` 字段（legacy registration 形态）
   commit SHA: 269ca7b3088abb0b7f9ff5f2689f627ba4a994db
   依赖结论: AC-02 的「本 CR 不自动补字段」断言的事实依据；writeback 阶段本 CR 走 legacy 路径的触发形态。
