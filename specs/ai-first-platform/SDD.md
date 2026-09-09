---
id: CR-2026-060-sdd
type: SDD
cr-ref: CR-2026-060
title: CR 全生命周期合同对齐 技术设计
target-version: "0.33"
status: ga
created: 2026-09-02T20:40:38+08:00
updated: 2026-09-02T23:55:00+08:00
spec-id: ai-first-platform
version: v0.33
cr-history: "[CR-2026-060]"
---

## CR 全生命周期合同对齐（v0.33 · CR-2026-060）

> 本文件为 CR-2026-060 SDD 的 attempt-2 修订版（回修 `review-tech-design` attempt 1 的 B-SDD-01..09 全部 blocker）。修订点在各节以「[A2]」标注或直接改写，§10 的 SHA 语义已按评审要求显式标注。

## 1. 架构概览

### 1.1 变更边界与四个变更组

本 CR 的全部可交付代码与文档变更落在 `tools` 仓（方法论包），与 PRD §3.4 的四个 TASK 一一对应：

| 变更组 | TASK | 触及面 | 主文件 |
|---|---|---|---|
| G1 注册与 authority | TASK-1 | `crctl register` 新必填 flag、统一结果 builder（含 `registrationAt` 持久化）、双账本字段、pre-review gate、**advance 层零写入 guard**、`writeback-apply`/`archive` 的 mode 入口（strict authority） | `skills/shared/crctl/scripts/crctl.mjs`、`scripts/lib/workspace-transactions.mjs` |
| G2 PRD/SDD writer-reviewer | TASK-2 | 六个 SKILL.md 的参数/顺序/路由合同修订 | `skills/requirement/{write-requirement-prd,review-requirement,approve-requirement}/SKILL.md`、`skills/develop/{write-tech-design,review-tech-design}/SKILL.md` 及 PRD/SDD 相关模板引用 |
| G3 PLAN/TASK/Coding/test/review | TASK-3 | 两张 PLAN 表、恰四 TASK 断言（**写入前 preflight + `task init --count-hint` + init 后复核**）、workspace/证据/回修合同 | `skills/develop/{write-dev-plan,write-dev-tasks,review-dev-plan,implement-code,write-test-report,review-code}`、`crctl.mjs` 的 `cmdTaskInit` |
| G4 writeback/archive 与 legacy 兼容 | TASK-4 | new/legacy 双路径解析、三段 writeback stage、**new-mode traceability 确定性生成分支**、**tasks pending preflight**、archive 投影与 journal 重放 | `crctl.mjs` 的 `cmdWritebackApply`/`cmdArchive`、`lib/workspace-transactions.mjs`、`skills/writeback/scripts/writeback-traceability.mjs`（新增 new 分支）、`skills/writeback/{writeback-prd-sdd,writeback-tasks}/SKILL.md`、`skills/cr/cr-archive` |

跨组的横切项：FR-05 的 8 条 Pipeline prompt 收敛（`pipeline-templates/*.pipeline.json`）、`review-alignment` 只读化、规划/竞品/resume 消费 Skill 的输入对齐（`skills/planning/`、`skills/competitive/`、`skills/cr/cr-show`）。横切项不另建 TASK，归入四组中负责对应消费面的组（Pipeline prompt 与 review-alignment 归 TASK-4 前的 G4 兼容面或按其上游归属；具体落位见 PLAN 交付覆盖表）。

### 1.2 模块边界与依赖方向

沿用 tools 仓 `ARCHITECTURE.md` 的四层模型（Pipeline → Skill → crctl → 账本），本 CR 不新增层、不新增状态、不新增账本：

```text
pipeline-templates/*.pipeline.json    # 只保留节点顺序/参数传递/reviewLoop/失败路由
   ↓ 调用（只读参数 + 透传结构化结果）
skills/{组}/{skill}/SKILL.md          # 业务判断 + 落盘非受控产物 + 一次深原语调用
   ↓ 唯一写入入口
crctl.mjs（register/gate/advance/version-set/writeback-apply/archive/task）
   ├─ lib/workspace-transactions.mjs  # registerCr/buildRegistrationTexts/authority resolvers
   ├─ lib/durable-tx.mjs             # journal/CAS/recoverable write-set（不动）
   ├─ gates.json + tools dir-graph.yaml  # 状态机与门禁唯一事实源（本 CR 不新增状态/转换）
   └─ skills/writeback/scripts/      # 内容文件回写（traceability 新增 new 分支，其余不动）
```

- **G1 的写入点**：`buildRegistrationTexts`（cr.md 与 `_backlog.yml` 的生成器）新增 `target-spec-id` 字段行，且其全部时间字段（created/updated/owners assigned-at/owner-history at）改为消费单一 `registrationAt`（§2.4）；`registerCr` 的 `inputDigest` 纳入 `targetSpecId`，`recoverCommand` 纳入 `--target-spec-id`；`cmdRegister` 新增校验、统一结果 builder 与 JSON 键映射。
- **G1 的读取点（mode 唯一裁决）**：新增单一纯函数 `resolveTargetSpecMode(ctx, cr, { authority })`（放 `crctl.mjs`，与既有 `readCrMdTargetVersion`/`readBacklogTargetVersionField` 同层）。**函数自身不解析路径**——`authority`（`{path, source}` 快照）由调用方按其生命周期绑定传入（§2.2/§4.1）：pre-review gate 与 advance guard 传 CR worktree 快照；writeback-apply/archive 的 new 分支传 strict txws 快照（§2.2 的 `resolveWritebackAuthorityStrict`）。禁止任何消费方各自推断或自带回退。
- **G4 的 authority 来源（[A2] 修正）**：新增严格解析器 `resolveWritebackAuthorityStrict(ctx, cr)`（§2.2），new mode 的 spec/version authority 只从它返回的 txws 路径读取；txws 缺失/状态不自洽一律显式失败，**不消费**既有 `resolveWritebackAuthorityPath`（`workspace-transactions.mjs:245`，永不抛、回退 cr-worktree）——后者仅保留给 legacy 版本守卫定位（且既有第 5.5 步同源绑定已兜底，§4.4）。

### 1.3 关键流程总览

```text
[A 注册] requirement-authoring inputs（registration_key/target_spec_id/target_version 必填）
   → requirement-register → crctl register
   → 校验 --target-spec-id（缺失/空→REGISTER_TARGET_SPEC_ID_REQUIRED，非法→REGISTER_TARGET_SPEC_ID_INVALID，
      均先于 BAD_ARGS 与锁/journal/账本）
   → registerCr 双账本写入 target-spec-id（时间字段全部消费单一持久化 registrationAt）
   → 统一结果 builder：成功 JSON 顶层含 cr_id/target_spec_id/operational_workspace/
      tx_id/target_version/side_effects/recover_command/outbox/warnings（全 snake_case；
      changed=false 同构输出，outbox=null）
   → Skill 逐字透传 cr_id + operational_workspace 到 execution_context（不解析、不拼接、不持有 resources 快照）

[B 需求评审前门禁] review-requirement 先跑 crctl gate <cr> --for requirement-reviewing --mode pre-review
   → 只读 mode 判据 + cr.md.target-version（authority=CR worktree；不读 PRD/annotation/passCondition）
   → pass 才写临时 payload → crctl review-record → PASS record 后由 advance 消费完整 statusGates
   → guard block：route=version-set，零评审记录/零写入

[B' advance 层零写入 guard（[A2] 新增）] 公开 CLI 直接执行
   crctl advance <cr> --to requirement-reviewing --trigger review-requirement 时，
   preflightAdvance 在 runGateChecks 之前跑 assertRequirementReviewAdvanceGuard：
   new mode 且 target-version=unassigned → fail GATE_BLOCKED（check code=TARGET_VERSION_UNASSIGNED），
   零写入（无 cr.md 写/audit/commit/outbox/attempt）。pre-review 的存在不豁免公开入口（§4.7）。

[C 回写] code-approved → crctl merge（不变）→ writeback-apply（mode 分支）：
   new：spec/version 可省略，从 strict txws authority 读取；显式传值只做相等校验；milestone 参数=BAD_ARGS；
        stage=traceability 走 generator 的 new 分支：从冻结 PLAN/TASK/test-report/merge facts 确定性生成
        FR→SDD→TASK→repo@mergeSHA→cmd 引用链（§4.8）；stage=tasks 先跑 pending-task preflight（§4.6）
   legacy：spec/version/milestone-file 按现行行为必填（generator legacy 分支逐字节保留）
   → archive：new 可省 spec-id（writing-back 首跑读 strict authority 并持久化到 archive journal；
      清理后的幂等重放只读 journal payload，不重解析已删除路径）；legacy writing-back 必填

[D TASK 数量（[A2] 改写）] write-dev-tasks 传 task_count_hint=4 → plan.md 预分配四组各一 ID
   → Skill 写入前 preflight（四组映射 + 恰 4 文件，零 crctl 调用，失败回滚草稿）
   → crctl task init --count-hint 4（写入前校验，失败 TASK_COUNT_MISMATCH 零写入）
   → init 后防并发复核（索引 taskCount==4 + 磁盘文件集组映射重跑，失败保留现场重跑同命令）
```

## 2. 数据模型

### 2.1 新增字段：`target-spec-id`

| 面 | 键名 | 值约束 | 写入者 |
|---|---|---|---|
| CLI flag | `--target-spec-id` | 非空；匹配 `^[a-z0-9][a-z0-9._-]*$`；禁止 `/`、`\`、CR、LF、路径段 | `cmdRegister` 校验，`registerCr` 防御性复查（同码）并消费 |
| `cr.md` frontmatter | `target-spec-id` | 同上 | `buildRegistrationTexts`（register 事务内，registerCr） |
| `_backlog.yml` 条目 | `target-spec-id` | 同上，与 cr.md 全等 | 同上 |
| register 成功 JSON | `target_spec_id` | 账本值的唯一 JSON 映射 | `cmdRegister` 输出层（统一结果 builder） |
| register journal payload | `targetSpecId` | 同上（规范化值） | `registerCr`（与 `registrationAt` 同批持久化，重试只读） |

### 2.2 mode 判定与 authority 绑定（[A2] 改写：唯一裁决 + 生命周期绑定）

#### 2.2.1 `resolveTargetSpecMode(ctx, cr, { authority })`

纯读取函数，**不自行解析任何路径**；只在传入的 `authority.path`（`{ws}/change-requests/{cr}/cr.md` 与 `{ws}/change-requests/_backlog.yml`）内读取两处 `target-spec-id`。返回 `{mode:'new', targetSpecId}` 或 `{mode:'legacy'}`，或抛 `TARGET_SPEC_AUTHORITY_DRIFT`（唯一顶层失败码，`extra.kind ∈ {missing|invalid|mismatch}`，§2.3）：

1. 两处字段均缺失 → `legacy`（仅限本 CR 代码合入前由旧 register 产生的 CR；新注册因 flag 必填在结构上不可能产生缺失形态，故无需时间戳判据——PRD §3.1「不提供新的 legacy 注册入口」）。
2. 恰一处存在（单侧缺失）→ `TARGET_SPEC_AUTHORITY_DRIFT`（`kind:'missing'`，零写入，不猜模式）。
3. 两处均存在、至少一处非法 → `TARGET_SPEC_AUTHORITY_DRIFT`（`kind:'invalid'`）。
4. 两处均存在、均合法、值不一致 → `TARGET_SPEC_AUTHORITY_DRIFT`（`kind:'mismatch'`）。
5. 均合法且全等 → `new`。

顶层码唯一：AC-02「两处字段缺一、非法或不一致时返回 `TARGET_SPEC_AUTHORITY_DRIFT`」被字面实现；PRD §3.2 gate 行的 MISSING/INVALID/DRIFT 是 pre-review **check code**（GATE_BLOCKED 信封内），由 gate 将 `extra.kind` 一对一映射（§4.2）。`TARGET_SPEC_AUTHORITY_MISSING`/`_INVALID` **不作为顶层 fail() 码存在**（消除 §2.3 旧稿的双轨混淆）。

#### 2.2.2 authority 生命周期绑定（每个消费方的固定规则）

| 消费方 | 权威来源 | 绑定规则 |
|---|---|---|
| pre-review gate（§4.2） | CR worktree（`crWorktreePath(ctx, cr)`，source=`cr-worktree`） | drafting/requirement-reviewing 期只读 CR worktree；忽略 txws，永不读 post-finalize 源 |
| advance 层 guard（§4.7） | 同上 | 同上（guard 只读 mode 判据与 cr.md.target-version） |
| writeback-apply new 分支（§4.4） | strict txws（`resolveWritebackAuthorityStrict`） | 见下 |
| archive new 分支（§4.4.3） | writing-back 首跑=strict txws；**清理后的幂等重放=archive journal payload** | 见下 |
| legacy 版本守卫 | 既有 `resolveWritebackAuthorityPath`（永不抛） | 维持 CR-2026-058 行为；其 cr-worktree 回退**禁止**被 new-mode spec/version 消费（new mode 走 strict 解析器，无回退） |

#### 2.2.3 `resolveWritebackAuthorityStrict(ctx, cr)`（[A2] 新增，放 `crctl.mjs` 与 mode 函数同层）

- 只读、永不回退：读 CR worktree `cr.md` status 与 merge journal（语义同 `resolveWritebackAuthorityPath` 的输入，但失败语义相反）：
  - status ∈ post-finalize（merging/writing-back/archived）→ txws 必须存在且其 cr.md status ∈ post-finalize，否则抛 **`WRITEBACK_SPEC_REQUIRED`**（PRD §3.2 writeback 行冻结码「new authority 缺失」的唯一实现：权威读不到 spec。零写入；`extra` 带 cr/status/txws）。
  - merge journal `phase=complete` 且 `operationalWorkspace` 的 cr.md status ∈ post-finalize → 返回该 txws 快照（source=`transaction-workspace`）；journal 完整但 txws 不自洽 → 同上 `WRITEBACK_SPEC_REQUIRED`。
  - status 非 post-finalize 且 journal 无 complete 事实 → 抛既有 `WRITEBACK_STATE_MISMATCH`（同现有 opWs 检查口径）。
  - archive 消费本解析器时把 `WRITEBACK_SPEC_REQUIRED` 映射为既有 `ARCHIVE_SPEC_REQUIRED`（§4.4；archive 面只用既有码）。
- 返回 `{path, source:'transaction-workspace'}` 快照，**只**被 new-mode spec/version 读取与 `resolveTargetSpecMode` 的 authority 参数消费。
- 与既有永不抛 `resolveWritebackAuthorityPath` 的差异表：后者保留且仅用于 legacy 版本守卫定位与 CR-2026-058 第 5.5 步同源绑定的既有测试面；任何 new-mode 消费路径不得引用其回退结果（回退被 strict 解析器的显式失败取代，不再可能消费 stale cr-worktree）。

#### 2.2.4 archive 清理后的幂等重放来源（[A2] 新增）

- `archiveCr` 新建 journal 时把 `payload.mode`、`payload.specId`、`payload.targetSpecId` 与 authority 快照同批持久化（冻结；重试只读）。
- `archived` 之后 cleanup 可能删除 txws/CR worktree/本地分支；`crctl archive <cr>`（省略 `--spec-id`）的重放分支**只读 archive journal payload** 取 specId/mode：payload 缺 specId 且无显式 flag → `ARCHIVE_SPEC_REQUIRED`（禁止重新解析已删除路径，禁止 stale fallback）。
- writing-back 首跑（journal 不存在）才执行 strict authority 解析，解析值在 candidate/cleanup 前写入 payload。

### 2.3 错误码 delta（[A2] 收敛为唯一裁决）

**新增顶层错误码（`fail()`/TxError 第一参数）**：

| 码 | 唯一触发前提 | 附加约束 |
|---|---|---|
| `REGISTER_TARGET_SPEC_ID_REQUIRED` | register 缺/空 `--target-spec-id` | 优先且唯一，先于 BAD_ARGS 循环 |
| `REGISTER_TARGET_SPEC_ID_INVALID` | 值不匹配 §2.1 正则 | 同上 |
| `TARGET_SPEC_AUTHORITY_DRIFT` | mode 裁决失败（单侧/非法/不一致，§2.2.1） | **唯一** mode 失败顶层码；`extra.kind` 区分三类；零写入 |
| `WRITEBACK_SPEC_REQUIRED` | new 分支 strict authority（txws）缺失/状态不自洽，spec 无法读取（PRD「new authority 缺失」的唯一实现） | 零写入；禁止回退 cr-worktree；archive 面映射为既有 `ARCHIVE_SPEC_REQUIRED` |
| `WRITEBACK_SPEC_MISMATCH` | new 分支显式 `--spec-id` != authority targetSpecId（PRD「若提供必须与 authority 全等」） | candidate/journal 前 |
| `WRITEBACK_TASKS_PENDING` | stage=tasks 且无法证明全部 TASK done：索引缺失/空（`reason=index-missing`）、索引非法（畸形 YAML/重复 id/未知 status，`reason=index-invalid`，解析失败硬失败禁止静默降级）或存在非 done 条目（`reason=pending`，`extra.pending` 列 id） | 单一码覆盖三类，`extra.reason` 区分；零写入零发布（§4.6） |
| `TASK_COUNT_MISMATCH` | `task init --count-hint N` 写入前校验失败（§4.5） | 由 crctl 发出（本 CR 前仅在 Skill 文本出现，现在受控入口机器化） |

**pre-review gate / advance guard 内部 check code（`GATE_BLOCKED` 外层信封内 `checks[].code`，非顶层码）**：`TARGET_SPEC_AUTHORITY_MISSING`、`TARGET_SPEC_AUTHORITY_INVALID`、`TARGET_SPEC_AUTHORITY_DRIFT`、`TARGET_VERSION_MISSING`、`TARGET_VERSION_INVALID`、`TARGET_VERSION_UNASSIGNED`。映射：`extra.kind` missing→`_MISSING`、invalid→`_INVALID`、mismatch→`_DRIFT`（§4.2）；`_MISSING` 的唯一可达前提=单侧缺失（两处均缺失=legacy，不触发 target-spec 检查——PRD §3.2 明文）。

**复用既有码**：`WRITEBACK_VERSION_INVALID`/`WRITEBACK_VERSION_MISMATCH`/`WRITEBACK_VERSION_UNASSIGNED`（CR-2026-057 已存在）、`ARCHIVE_SPEC_REQUIRED`/`ARCHIVE_TASKS_PENDING` 等 `ARCHIVE_*`（已存在）、`BAD_ARGS`、`REGISTRATION_INPUT_MISMATCH`、`GATE_BLOCKED`、generator 内部 `STRUCTURE_MISMATCH`/`MERGE_COMMITS_MISSING`/`TRUNK_UNKNOWN`。不新增错误码族、不新增平行信封。

### 2.4 新增持久化字段：`registrationAt` 与 writeback authority 快照（[A2] 新增）

**`registrationAt`（register journal payload，B-SDD-04）**

- 语义：一次注册的**唯一**时间戳事实，跨重试复用；register 事务的全部时间投影（cr.md 的 `created`/`updated`/`owners.*.assigned-at`/`owner-history[].at`，`_backlog.yml` 条目的 `created`/`updated`/`owners.*.assigned-at`）与 `cmdRegister` 的 owners outbox 事件（`owners.*.assigned-at`、`changes[].at`）都必须且只能消费该值，禁止各自 `nowIso()`。
- 产生与持久化：`registerCr` 在 journal payload 首次分配（`payload.cr` 之前或同批）执行 `payload.registrationAt = payload.registrationAt || nowIso()`，随 `save('allocated')` 落盘冻结；roll-forward 重试只读 `payload.registrationAt`，不重生成。
- 传递：`buildRegistrationTexts({..., now: registrationAt})`；`registerCr` 结果携带 `registrationAt`；`cmdRegister` 的 owners outbox 原样消费 `result.registrationAt`（删除 `crctl.mjs:3103` 的第二个 `nowIso()`）。
- 断言：ledger `owners.*.assigned-at` === outbox payload `owners.*.assigned-at` === result.registrationAt（精确字符串相等，AC-01/AC-16 测试）；同 key 重试两次结果 registrationAt 相等。

**writeback/archive journal authority 快照**

- writeback journal 既有 payload 已持久化 `specId`/`targetVersion`；本 CR 补充：new 分支下 `payload.mode` 与 `payload.targetSpecId`（新建时冻结，found 重试只读，同 B-SDD-01 冻结协议）。
- archive journal payload 增加 `mode`/`specId`/`targetSpecId`（§2.2.4）。

## 3. 接口契约

HTTP API：`N/A`（本 CR 不新增或修改 HTTP endpoint/request/response/error/HTTP 权限契约；PRD §3.2 已冻结，需求评审 `HTTP_API契约闭包` 维度同判）。

### 3.1 CLI 契约实现映射（PRD §3.2 矩阵 → 代码落点，[A2] 修订）

| 契约行 | 实现落点 | 关键实现说明 |
|---|---|---|
| `register --target-spec-id` | `cmdRegister`（crctl.mjs:3080）+ `registerCr`（workspace-transactions.mjs:654） | 在既有必填 flag 循环**之前**先判 `--target-spec-id`：缺失/空→`REGISTER_TARGET_SPEC_ID_REQUIRED`（优先且唯一，不落 BAD_ARGS）；再按 §2.1 正则校验→`REGISTER_TARGET_SPEC_ID_INVALID`；`source` 单行 scalar 拒绝 CR/LF（复用既有 scalar 处理，注册期不解析路径）。`registerCr` 内防御性复查（同码，先于锁/journal）。`inputDigest`（:679）增加 `targetSpecId`（同 key 换 spec → `REGISTRATION_INPUT_MISMATCH`）；`recoverCommand`（:684）增加 ` --target-spec-id ${JSON.stringify(targetSpecId)}`（必填 flag，恒非空） |
| register 成功 JSON（统一结果 builder，B-SDD-05） | `registerCr` 出口 + `cmdRegister` 输出层 | **新增 `buildRegisterResult`**（§4.3.2）：成功/幂等/恢复重放共用，从 journal payload 组装 `cr/txId/phase/changed/targetVersion/targetSpecId/registrationAt/sideEffects/recoverCommand/operationalWorkspace`（`operational_workspace` 由 `resolveOperationalWorkspace(ctx, cr)` 生产，注册完成时 CR 处于 `drafting` 前 finalize 态 → 返回 cr-worktree 路径，source=`cr-worktree`）。`cmdRegister` 唯一映射点输出 snake_case：`op, cr_id, target_spec_id, operational_workspace, tx_id, phase, changed, target_version, side_effects, recover_command, outbox, warnings`；**删除 :3098 的 `if (!result.changed) return ok(...)` 早退**——`changed=false` 走同一 builder，`outbox=null`、`warnings=[]`（PRD：无新 commit/outbox/worktree）。`changed=true` 时 owners outbox 的 `assigned-at`/`changes[].at` 全部 = `result.registrationAt`（原样消费，不再 `nowIso()`） |
| `gate --for requirement-reviewing --mode pre-review` | `cmdGate`（crctl.mjs:956） | 新增分支：`flags.mode==='pre-review'` 且 `flags.for==='requirement-reviewing'` 时走新 `runPreReviewGateChecks(ws, cr)`，**不**走 `runGateChecks` 的 statusGates（绝不读 PRD/requirement annotation/passCondition）。其他 `--for` 配 `--mode pre-review` → `BAD_ARGS`。输出 `{cr, for, mode:'pre-review', pass, checks:[{type, code, ok, why}]}`；fail 时 exit 1 + stderr `{error:{code:'GATE_BLOCKED',...}}`，零写入（无 payload/annotation/review-loop/trace/status/outbox/journal/commit）。check code 由 §2.3 映射表固定（含 `_MISSING` 的可达前提）。真实版本且尚无 PASS annotation 时 `pass=true` |
| `advance --to requirement-reviewing --trigger review-requirement`（[A2] 从「不改」改为「新增零写入 guard」） | `preflightAdvance`（crctl.mjs:963）+ `assertRequirementReviewAdvanceGuard`（新函数） | **新增只读 guard**（§4.7）：`flags.to==='requirement-reviewing'` 时，在 `runGateChecks` 之前以 CR worktree 为 authority 跑 mode+version 判定；new mode `unassigned` → `fail('GATE_BLOCKED', …, {gate:{checks:[{code:'TARGET_VERSION_UNASSIGNED',…}]}})`。`preflightAdvance` 无任何写入 → 零副作用（无 cr.md 写/audit/commit/outbox/attempt）。`performAdvance` 的 commit/outbox/audit 内核与 passCondition 行为**不变**；legacy 零改动。pre-review 前置的存在**不豁免**公开 CLI 直连（PRD §3.2 advance 行 + AC-16） |
| `version-set` | 既有 `cmdVersionSet`（crctl.mjs:2623） | **零改动**；PRD §3.2 该行的成功/幂等/错误优先级语义已由 CR-2026-057 实现，本 CR 只消费 |
| `writeback-apply` new/legacy 分支（[A2] 修订：strict authority + tasks preflight + new traceability） | `cmdWritebackApply`（crctl.mjs:3401）+ `applyWritebackAtomic`（workspace-transactions.mjs:2641 起） | 顺序（§4.4 详述）：参数形态校验（stage/未知 flag/candidate 拒绝，BAD_ARGS）→ strict authority（失败→`WRITEBACK_SPEC_REQUIRED`）+ `resolveTargetSpecMode`（单侧/非法/不一致→`TARGET_SPEC_AUTHORITY_DRIFT`）→ milestone flag 拒绝（new→BAD_ARGS）→ spec/version 省略补全与显式相等校验（`WRITEBACK_SPEC_MISMATCH`/既有 `WRITEBACK_VERSION_*`）→ stage=tasks 的 pending-task preflight（§4.6，`WRITEBACK_TASKS_PENDING`）→ 既有 version guard/opWs/第 5.5 步同源绑定 → candidate/journal/manifest/commit/push（事务内核不动）。stage=traceability 且 new 时 generator 走 new 分支（§4.8），`--milestone-file`/`--milestone-name`/`--brief` 已先被 BAD_ARGS 拒绝；legacy 分支逐字节保留。`applyWriteback` 的 generator/candidate/manifest/journal 逻辑不动，仅入口参数来源与输入集不同 |
| `archive` new 可省 spec-id（[A2] 修订：journal 重放） | `cmdArchive`（crctl.mjs:3368）+ `archiveCr` | writing-back 首跑：new mode → `--spec-id` 省略时经 strict authority + `resolveTargetSpecMode` 读取；解析值在 candidate/cleanup 前持久化进 archive journal payload（`mode`/`specId`/`targetSpecId`）。**cleanup-pending 重放（清理后幂等重跑）**：只读 journal payload，不重新解析已删除的 txws/CR worktree；payload 缺 specId 且无 flag → `ARCHIVE_SPEC_REQUIRED`。legacy `writing-back`：必填（现行）。`ARCHIVE_SPEC_REQUIRED`/`ARCHIVE_TRACEABILITY_MISSING`/`ARCHIVE_TASKS_PENDING`/`ARCHIVE_TRACE_PENDING` 语义不变；不重放 generator、不重选 spec/version |

### 3.2 Skill 契约实现映射（PRD §3.3/§3.3.1 → SKILL.md 落点，[A2] 修正路径）

| Skill | 文件 | delta 要点 |
|---|---|---|
| `requirement-register` | `skills/requirement/requirement-register/SKILL.md` | 参数表 +`target_spec_id`（required）；Step 2 命令模板 +`--target-spec-id`；Step 3/4 改消费 snake_case 成功 JSON（`cr_id`/`operational_workspace`/`tx_id`/`recover_command`）；输出摘要含 `operational_workspace` 透传说明；错误表 +`REGISTER_TARGET_SPEC_ID_REQUIRED/INVALID` 行 |
| `write-requirement-prd` | `skills/requirement/write-requirement-prd/SKILL.md` | 明确 title/summary/source/target-version/owner 只从 cr.md 读，Pipeline 重复字段不得覆盖；source 路径 containment/existence 在 writer 阶段校验；七类章节 + 成功指标 + 范围排除 |
| `review-requirement` | `skills/requirement/review-requirement/SKILL.md` | Step 1 与 Step 2 之间插入**固定顺序**：先 `crctl gate <cr> --for requirement-reviewing --mode pre-review`；guard pass 才写临时 `.crctl/tmp/review-requirement.yml` → `crctl review-record`；record=pass 才 `crctl advance`；guard block（含 new mode `unassigned`）→ route=`version-set`，不记录评审、不改状态。**同时声明公开 CLI 直连 advance 也被 §4.7 的 advance 层 guard 拦截**（Skill 不复制该算法） |
| `write-tech-design` / `review-tech-design` | `skills/develop/write-tech-design/SKILL.md`、`skills/develop/review-tech-design/SKILL.md` | writer 参数表 required=`cr_id,operational_workspace,resources`；七维作者/reviewer 标准成对表述；`SDD-CLOSE-*` 逐项关闭义务；术语硬化与 HTTP 条件基线沿用现状表述 |
| `write-dev-plan` / `write-dev-tasks` / `review-dev-plan` | `skills/develop/write-dev-plan/SKILL.md`、`skills/develop/write-dev-tasks/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md` | plan 恰含两张稳定表（交付覆盖表：`FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`；证据命令表：`证据ID | repo | cwd | executable | args | timeout`）；tasks +`task_count_hint`（本 CR 固定 4）并**执行 §4.5 三步断言**（写入前 preflight → `crctl task init --count-hint 4` → init 后防并发复核），失败 `TASK_COUNT_MISMATCH` abort；review-dev-plan 同口径复核 |
| `implement-code` / `write-test-report` / `review-code` | `skills/develop/{implement-code,write-test-report,review-code}/SKILL.md` | 实现依据只取 SDD/PLAN/TASK/目标仓规范/`resources[].worktreePath`（PRD 非并列合同）；test-report 执行 PLAN 证据命令表 canonical 门禁并发布 `sourceRevision`+日志哈希；review 输出固定五字段、不重跑测试、不新增 aggregate digest |
| 四个 `approve-*`（[A2] 路径修正） | `skills/requirement/approve-requirement/SKILL.md`、`skills/develop/approve-tech-design/SKILL.md`、`skills/develop/approve-dev-start/SKILL.md`、`skills/develop/approve-code/SKILL.md` | required=`cr_id`；缺 approver 取对应 owner；只消费/返回 `crctl approve` 结构化结果；下一步统一「以 `crctl next {cr_id}` 为准」 |
| `writeback-prd-sdd` / `writeback-tasks` / `writeback-traceability` / `cr-archive` | `skills/writeback/{writeback-prd-sdd,writeback-tasks,writeback-traceability}/SKILL.md`、`skills/cr/cr-archive/SKILL.md` | new：spec/version 可省略（仅可重复校验），milestone 参数=N/A；**traceability 的 new 分支说明输入是冻结 PLAN/TASK/test-report/merge facts（§4.8），不要求 milestone-file**；tasks 的 Skill 步骤注明 pending preflight 失败码与恢复语义（§4.6）。legacy：spec/version（trace 加 milestone-file）必填。三者只输出一次 `crctl writeback-apply` 结果；archive 输出一次 `crctl archive` 结果，并注明清理后重跑无需 spec-id（journal 重放） |
| `review-alignment` | `skills/review/review-alignment/SKILL.md` | 任意状态按需只读：输出 `{skill,cr_id,spec_id,current-status,result,drifts,summary}`，不落盘、不写 traceability、不读 mtime/backlog merge-commit/fingerprint；不调用任何 crctl 写命令 |
| 规划/竞品/market/resume 消费面 | `skills/planning/…`、`skills/competitive/…`、`skills/cr/cr-show/SKILL.md` | 按 PRD §3.3.1 矩阵修必填输入（topic/context/intent/brief/updates-block/product-snapshot/confirmed/prev_outputs/review_feedback/self_repair_attempt/reportPath|reportDraft 二选一、competitor-id(s)+lookback-days）；resume-cr 展示节点调用 `cr-show(cr-id, section: all)` 并消费结构化详情 |

### 3.3 术语硬化（Step 2.5 预检结论）

| PRD canonical 术语 | 代码别名/映射 | 代表边界场景（已按 PRD §3.1/§3.2 验证） |
|---|---|---|
| `new mode` / `legacy mode` | `resolveTargetSpecMode` 返回 `mode:'new'|'legacy'` | 单侧 `target-spec-id`（cr.md 有、backlog 无）→ `TARGET_SPEC_AUTHORITY_DRIFT`（kind=`missing`）零写入，不猜模式 |
| `target-spec-id`（账本键）/ `--target-spec-id`（flag）/ `target_spec_id`（JSON 键） | 三面各自唯一，无第二别名 | register 成功 JSON 只含 `target_spec_id`；下游 Skill 不得读 `target-spec-id` 形式的 JSON 键 |
| `operational_workspace`（register JSON + execution_context，snake_case）vs `operationalWorkspace`（workspace inspect 只读输出，历史 camelCase） | 两键共存于不同表面，值同源（`resolveOperationalWorkspace`） | requirement-authoring 的 execution_context 只含 `operational_workspace`；coding 节点读 inspect 的 `operationalWorkspace` + `resources[].worktreePath`。任一节点不得按 `.rayai-worktrees/{repo}/requirement/{cr}` 拼路径 |
| `unassigned` | 既有 `normalizeTargetVersion` 语义 | new mode `unassigned` 被 pre-review（`TARGET_VERSION_UNASSIGNED`）与 **advance 层 guard（同码，§4.7）** 双处拒绝，只能先 `version-set` |
| `registrationAt`（[A2] 新增术语） | register journal payload 单一时间戳 | 所有注册时间投影（ledger + outbox + result）原样消费，禁止投影处各自 `nowIso()` |

PRD §3.1/§3.2 已对上述术语完成唯一裁决（含判据表与命名矩阵），SDD 不引入新裁决、无待澄清语义冲突。§2.2/§2.3 对「顶层码 vs check code」的映射收敛见 D-06。

## 4. 关键算法与流程

### 4.1 `resolveTargetSpecMode`（G1/G4 共用，伪代码，[A2] 含 authority 参数）

```text
resolveTargetSpecMode(ctx, cr, { authority })   # authority = { path, source }，调用方生命周期绑定（§2.2.2）
read {authority.path}/change-requests/{cr}/cr.md frontmatter field 'target-spec-id' -> A（缺 = missing）
read {authority.path}/change-requests/_backlog.yml 条目 field 'target-spec-id' -> B（缺 = missing）
if A missing and B missing: return { mode: 'legacy' }
if A missing xor B missing: fail TARGET_SPEC_AUTHORITY_DRIFT（extra.kind='missing'，零写入）
if not valid(A) or not valid(B): fail TARGET_SPEC_AUTHORITY_DRIFT（extra.kind='invalid'）
   # valid = ^[a-z0-9][a-z0-9._-]*$ 且无 / \ CR LF
if A != B: fail TARGET_SPEC_AUTHORITY_DRIFT（extra.kind='mismatch'）
return { mode: 'new', targetSpecId: A }
```

行尾纪律：读取一律 `\r\n→\n` 规范化后按行匹配；跨行正则匹配失败硬失败（复用既有 `readFrontmatter`/`matchEntryBlock` 的硬失败路径，不静默降级）。函数自身不解析 authority 路径、不读 status、不做回退——authority 的合法性由调用方经 §2.2.2 的绑定规则保证（pre-finalize 用 crWorktree 快照，post-finalize new 分支用 strict 快照）。

### 4.2 pre-review 检查序列（`runPreReviewGateChecks`，[A2] 含 kind→check code 映射）

```text
checks = []
authority = { path: crWorktreePath(ctx, cr), source: 'cr-worktree' }   # 绑定规则固定，禁止读 txws
try: mode = resolveTargetSpecMode(ctx, cr, { authority })
catch TxError e (code=TARGET_SPEC_AUTHORITY_DRIFT):
  checkCode = { missing:'TARGET_SPEC_AUTHORITY_MISSING',
                invalid:'TARGET_SPEC_AUTHORITY_INVALID',
                mismatch:'TARGET_SPEC_AUTHORITY_DRIFT' }[e.extra.kind]
  checks += { type:'target-spec-authority', code:checkCode, ok:false, why:e.message }
  mode = null
if mode?.mode == 'new':
  v = readCrMdTargetVersion(authority.path, cr)   # 既有行级读取器
  missing -> TARGET_VERSION_MISSING；normalize 失败 -> TARGET_VERSION_INVALID
  value == 'unassigned' -> TARGET_VERSION_UNASSIGNED（仅 new mode 阻断）
## legacy：两处均缺失按 3.1 判定，不触发 target-spec 检查；target-version 只做既有格式校验
pass = 全部 check.ok（无 check 亦 pass）
输出 {cr, for:'requirement-reviewing', mode:'pre-review', pass, checks}
pass=false -> stderr {error:{code:'GATE_BLOCKED', message, gate}}, exit 1, 零写入
```

可达性：`TARGET_SPEC_AUTHORITY_MISSING` 仅在单侧缺失时可达（两处均缺失=legacy 跳过）；`_INVALID` 仅在两处均在且至少一处非法时可达；`_DRIFT` 仅在均合法不一致时可达。三者顶层码同为 `TARGET_SPEC_AUTHORITY_DRIFT`（AC-02 字面），check code 区分供调用方路由（PRD §3.2 固定）。

### 4.3 register 校验顺序、统一结果 builder 与 `registrationAt`（[A2] 修订）

#### 4.3.1 校验顺序（错误优先级，PRD §3.2 冻结 + 新增项）

```text
1. --target-spec-id 缺失或空 -> REGISTER_TARGET_SPEC_ID_REQUIRED   # 优先且唯一，先于 BAD_ARGS 循环
2. 非法（正则/路径字符/CR/LF）-> REGISTER_TARGET_SPEC_ID_INVALID
3. 既有必填 flag 循环（registration-key/title/owner-*）-> BAD_ARGS
4. registerCr 内 --target-version 规范化 -> REGISTER_VERSION_INVALID（既有）
5. registerCr 内 targetSpecId 防御性复查（同 1/2 码）             # 先于锁/journal/账本
6. inputDigest = sha256({title, summary, source, origin, targetVersion, year, owners, targetSpecId})
   # [A2] targetSpecId 入 digest（:679）——同 key 换 spec -> REGISTRATION_INPUT_MISMATCH
7. recoverCommand 构造（:684）+ ` --target-spec-id ${JSON.stringify(targetSpecId)}`（恒非空必填）
8. registrationAt = payload.registrationAt || nowIso()；payload.registrationAt = registrationAt
   # 随 save('allocated') 落盘冻结；roll-forward 重试只读
9. journal（inputDigest 冲突 -> REGISTRATION_INPUT_MISMATCH）/锁/账本写（既有事务内核不动）
```

以上 1-8 全部在锁/journal/账本写入前；事务中断只重跑 recover_command（含 `--target-spec-id`，可过新必填校验）。

#### 4.3.2 统一结果 builder（B-SDD-05）

```text
buildRegisterResult(ctx, { cr, journal, payload, input }):          # registerCr 出口唯一构造，成功/幂等/恢复共用
  targetSpecId = payload.targetSpecId                               # 与 input.targetSpecId 相等；重试以 payload 为准
  registrationAt = payload.registrationAt
  sideEffects = payloadSideEffects(payload)                         # 既有（commit/push/worktrees 投影）
  recoverCommand = 既有构造 + --target-spec-id（见 4.3.1 第 7 步）
  operationalWorkspace = resolveOperationalWorkspace(ctx, cr).path  # 注册完成时 drafting（前 finalize）-> cr-worktree
  return { cr, txId: journal.txId, phase: payload.phase, changed, targetVersion: payload.targetVersion,
           targetSpecId, registrationAt, sideEffects, recoverCommand, operationalWorkspace }

cmdRegister 输出（唯一映射点；删除 :3098 早退，changed=true/false 同构）:
  ok({ op:'register', cr_id, target_spec_id, operational_workspace, tx_id, phase, changed,
       target_version, side_effects, recover_command, outbox, warnings })
  - changed=true：outbox = { status, owners }；owners 事件 payload 的 assigned-at/changes[].at 全部
    原样 = result.registrationAt（删除 :3103 的第二个 nowIso()）
  - changed=false：outbox = null、warnings = []（PRD：同键同输入无新 commit/outbox/worktree）；
    其余键与 changed=true 同构（含 target_spec_id/operational_workspace/recover_command）
  - auditLog 与 status/owners 事件发射的既有语义不变（EMIT_FAILED -> warnings）
```

### 4.4 writeback-apply mode 分支顺序（[A2] 修订）

```text
cmdWritebackApply 层（crctl.mjs:3401）:
1. stage/未知 flag/candidate 拒绝（既有）-> BAD_ARGS
2. ctx = resolveRepositories(ws)；strictAuth = resolveWritebackAuthorityStrict(ctx, cr)
   # 失败: WRITEBACK_STATE_MISMATCH（非 post-finalize）/ WRITEBACK_SPEC_REQUIRED（txws 缺或状态不自洽）
   # 零写入；禁止回退 cr-worktree（PRD「new authority 缺失」的唯一实现）
3. mode = resolveTargetSpecMode(ctx, cr, { authority: strictAuth })
   # 单侧/非法/不一致 -> TARGET_SPEC_AUTHORITY_DRIFT（PRD §3.1/AC-02 唯一顶层码，kind 进 extra）
   # 两处均缺失 -> legacy（见 5；legacy 缺参由 BAD_ARGS 拦截，与本 CR 自身兼容路径一致）
4. new：milestone 任一 flag 传入 -> BAD_ARGS（N/A）
   spec = flags['spec-id'] ?? mode.targetSpecId；显式传值 != mode.targetSpecId -> WRITEBACK_SPEC_MISMATCH
   version：flags['target-version'] 省略 -> 从 strictAuth.path 读 cr.md target-version（规范化）；
           显式传值 -> 交既有 guardWritebackVersion（相等校验 -> WRITEBACK_VERSION_MISMATCH，既有码）
5. legacy：现行路径（spec/version 必填=BAD_ARGS，traceability milestone-file 必填=BAD_ARGS，
   其余 milestone 限制既有）——与本 CR 自身（legacy）兼容，行为不变
6. stage == 'tasks'：pending-task preflight（§4.6）——在 candidate/journal 之前，零写入
7. 既有内核：guardWritebackVersion -> resolveOperationalWorkspace（须 transaction-workspace，否则
   WRITEBACK_STATE_MISMATCH）-> 第 5.5 步同源绑定 -> planVersionRefill -> business/candidate/manifest/
   journal/commit/push（全部不动）。strictAuth.path 与 opWs.path 由同源断言保证一致（既有 5.5 绑定）。
8. stage == 'traceability' && mode == 'new'：generator 走 new 分支（§4.8），无 milestone-file 入参；
   legacy：generator 走 legacy 分支（逐字节保留，:60-120 的 milestone 校验原样）。

archive（cmdArchive，crctl.mjs:3368）new 分支同源消费 strict 解析器：strictAuth 失败 -> 既有
ARCHIVE_SPEC_REQUIRED（§2.2.3 映射）；首跑解析值持久化 payload；清理后重放只读 payload（§2.2.4）。
```

失败路径全部在 candidate/journal 前，零写入；事务中间态只重跑 `recover_command`（new 分支的 recover command 含解析后的 spec/version，不含 milestone——见 applyWritebackAtomic 既有构造扩展：new traceability 的 recover command 不再含 `--milestone-file`）。

### 4.5 TASK 数量断言（G3，[A2] 改写：写入前 preflight + init 校验 + init 后复核）

```text
write-dev-tasks(cr_id, task_count_hint=4):
  [1] plan.md 已含四变更组各预分配一个 TASK ID（G1..G4 -> TASK-1..4，交付覆盖表「主责/关联TASK」列）
  [2] 写入前 preflight（Skill 内，零 crctl 调用）：
      解析 plan.md 交付覆盖表 -> 组映射（每 G 恰一个 TASK、每 TASK 恰属一组）
      生成 tasks/TASK-*.md 草稿后校验文件集：恰 4 个文件、frontmatter id = {cr}-TASK-1..4 连续无重复、
      组映射与 plan.md 一致
      失败 -> abort TASK_COUNT_MISMATCH：删除本轮生成的草稿 TASK-*.md（非受控草稿回滚），
              未调用任何 crctl、零账本/零状态推进；报错输出草稿路径清单与四组映射核对表
  [3] crctl task init <cr> --count-hint 4（cmdTaskInit，crctl.mjs:1732，[A2] 新增 flag 校验）：
      cmdTaskInit 在 renderTaskIndex/casWrite/createFileExclusive/audit 之前执行写入前校验：
      卡片数 == 4、id 唯一且与 {cr}-TASK-1..4 一一对应（缺号/重号/第五个/跨组 id 越界）
      -> 失败 fail TASK_COUNT_MISMATCH，零写入（不写 _index.yml、无 audit）
      --count-hint 缺省时行为与现行完全一致（既有 CR 不受影响）；幂等 CAS 刷新内核不变
  [4] init 后防并发复核（Skill）：
      以 init 返回 taskCount==4 为准；对磁盘 TASK 文件集重跑 [2] 的组映射 preflight
      （防 preflight 与 init 之间被并发增删文件）
      任一不一致 -> TASK_COUNT_MISMATCH abort；保留现场：
        - 不手工删除/编辑 tasks/_index.yml（受控账本）；
        - 修正 tasks/ 文件集后重跑 `crctl task init --count-hint 4`（CAS 幂等刷新）；
        - 复核通过前不得 advance --to task-breakdown
  review-dev-plan 同口径复核（评审时对 plan 表与索引双向核对）
```

「零推进」定义：未调用 crctl、未写 `tasks/_index.yml`、未推进 status、未 commit。草稿 TASK-*.md 属非受控产物，失败即回滚删除；受控账本一旦写入（init 成功后）只经同一命令幂等刷新，不手工编辑。

### 4.6 pending-task preflight（G4，B-SDD-03：[A2] 新增，stage=tasks 专用）

```text
preflightTasksAllDone(txws, cr)（applyWritebackAtomic 内，opWs 解析与第 5.5 步绑定之后、
prepareWritebackCandidate/journal/lock 之前）:
  p = {txws}/change-requests/{cr}/tasks/_index.yml
  不存在或空 -> fail WRITEBACK_TASKS_PENDING（extra.reason='index-missing'）
  读取 -> \r\n→\n 规范化 -> 严格解析（条目 id/status 必须成对；畸形 YAML、重复 id、
          未知 status 值 -> fail WRITEBACK_TASKS_PENDING，extra.reason='index-invalid'，
          硬失败禁止静默降级——纪律 #1）
  存在任一 status != 'done' -> fail WRITEBACK_TASKS_PENDING（extra.reason='pending'，
          extra.pending = 未完成 id 列表）
  全部 done -> 放行
```

- 单一码 `WRITEBACK_TASKS_PENDING` 覆盖三类（`extra.reason` 区分，§2.3）：语义统一为「无法证明全部 TASK done」，PRD AC-11 的唯一失败面。
- 位置保证零写入：preflight 先于 `prepareWritebackCandidate`（后者才 rm/mkdir candidate 目录并 spawn generator，`workspace-transactions.mjs:2371`）与 journal 创建——失败时无 candidate/journal/账本/commit/push，**不存在部分 delivery 发布**（writeback-tasks.mjs:45-60 的 done 子集筛选在 preflight 后恒等于全量，保留为防御性 no-op，legacy 分支不引入本 preflight 时行为不变）。
- 恢复语义：preflight 只读、幂等，重试前置条件 = `crctl task done` 补齐全部 TASK 后重跑同一 `crctl writeback-apply` 命令；无现场需手工清理（零写入失败）。
- 归档衔接：`ARCHIVE_TASKS_PENDING`（既有）语义不变；writeback 阶段已全 done 的事实由 task 账本与 writeback journal 共同证明。

### 4.7 advance 层零写入 guard（G1，B-SDD-01：[A2] 新增）

```text
assertRequirementReviewAdvanceGuard(ws, cr, ctx)：
调用点：preflightAdvance（crctl.mjs:963）内、findTransition 之后、runGateChecks 之前；
       仅当 flags.to === 'requirement-reviewing' 时执行。
  authority = { path: crWorktreePath(ctx, cr), source: 'cr-worktree' }   # drafting 期权威固定
  mode = resolveTargetSpecMode(ctx, cr, { authority })                   # 抛错 -> 原码零写入
  if mode.mode !== 'new': return                                         # legacy 零改动
  v = readCrMdTargetVersion(authority.path, cr)
  if v 规范化后 == 'unassigned':
    fail('GATE_BLOCKED', 'new mode unassigned 禁止直接 advance 到 requirement-reviewing（先 version-set）',
         { gate: { target:'requirement-reviewing', pass:false,
                   checks:[{ type:'target-version', code:'TARGET_VERSION_UNASSIGNED', ok:false, why }] } })
  # 只读 mode 判据与 cr.md.target-version；不读 PRD/annotation/passCondition
```

- 零写入保证：`preflightAdvance` 在 `updateCrMdStatus`/audit/commit/outbox 之前，且自身无任何写操作——失败时 cr.md、review-loop、traceability、status outbox、attempt、audit、commit 全部不变（PRD §3.2 advance 行 + AC-16 负向断言）。
- 与 pre-review 的关系：guard 覆盖**公开 CLI 直连**（review-requirement Skill 之外的调用者）；review-requirement 正常路径先被 pre-review 拦截，guard 是第二道不依赖调用方自觉的防线。两者检查内容相同但触发面不同（gate 命令 vs advance 命令），不互相豁免。
- 批准范围联动：`cmdAdvance`/`performAdvance` 不再列入 zero_diff 全冻结（§9 精确化）；`performAdvance` 的 commit/outbox/audit 内核仍冻结，只有 `preflightAdvance` 增加上述只读分支。

### 4.8 new traceability 确定性生成映射（G4，B-SDD-02：[A2] 新增）

#### 4.8.1 输入（全部冻结于 writing-back 的 strict txws 内，generator 只读）

| 输入 | 路径 | 用途 |
|---|---|---|
| PLAN 交付覆盖表 | `change-requests/{cr}/plan.md` | FR →（SDD交付项）→（主责/关联TASK）→（验收证据 ID）四列映射源 |
| PLAN 证据命令表 | `change-requests/{cr}/plan.md` | `cmd-NN` → repo/cwd/executable/args/timeout（供 test-report 交叉引用） |
| TASK 账本 | `change-requests/{cr}/tasks/_index.yml` | TASK id/status（§4.6 已保证全 done） |
| TASK 卡 | `change-requests/{cr}/tasks/TASK-*.md` | frontmatter `title`（frs[].tasks 的标签） |
| 测试报告 | `change-requests/{cr}/test-report.md` | `cmd-NN` 证据、sourceRevision、日志哈希（cross-check 证据命令表） |
| merge facts | `change-requests/{cr}/merge-commits.yml` | repo/mergeSha（trunk 取自 dir-graph.yaml#repositories，既有 `trunkOf` 逻辑） |

#### 4.8.2 确定性映射（generator new 分支，`writeback-traceability.mjs` 内新增；legacy 分支逐字节保留）

```text
segment:
  - cr: {cr}
    milestone: {target-version}                    # new mode 无 milestone-file；milestone 取权威 target-version
    target-version: {权威 target-version}
    merge-commits:                                  # 与 legacy 同形状（repo/trunk/sha/branch，来自 merge-commits.yml）
    frs:                                            # 每条 = PLAN 交付覆盖表一行（按 FR id 升序，确定性排序）
      - fr: {FR-id}
        title: {行内标题}
        sdd: {SDD交付项 列}                          # SDD 章节引用
        tasks: [{主责/关联TASK 列解析出的 TASK id}]     # 与 tasks/_index.yml 交叉校验存在且 done
        code: ["{repo}@{mergeSha12}" for merge-commits.yml 每个 repo]   # repo@mergeSHA 引用链
        evidence: [{验收证据 列解析出的 cmd-NN}]         # 与 test-report 的证据 ID 交叉校验存在
    evidence:                                      # 七项最小证据摘要（test/reviews×4/approval/merge）
      test / reviews / approval / merge            # 复用既有 readEvidenceInputs，零改动
```

- 引用链 `FR→SDD→TASK→repo@mergeSHA→cmd` 的生成路径：FR（覆盖表行）→ SDD（`SDD交付项` 列）→ TASK（`主责/关联TASK` 列 + 账本交叉校验）→ repo@mergeSHA（merge-commits.yml × dir-graph trunk）→ cmd（`验收证据` 列 × 证据命令表 × test-report 三方交叉校验）。
- 硬失败规则（纪律 #1，禁止静默降级）：plan.md 缺失或两张表不可解析 → `STRUCTURE_MISMATCH`；覆盖表出现无法映射到账本的 TASK id → `STRUCTURE_MISMATCH`；证据 ID 在证据命令表或 test-report 缺失 → `STRUCTURE_MISMATCH`；merge-commits 缺失 → 既有 `MERGE_COMMITS_MISSING`；test-report/七项证据缺失 → 既有 evidence 错误码。
- 事务边界：candidate-only 生成、manifest v2、allowlist `specs/{spec}/traceability.yml`、journal/CAS/commit/push 全部沿用既有 `applyWritebackAtomic`——new 分支只改变 generator 的输入集与 frs 构造，不新增账本/状态/事务。
- `prepareWritebackCandidate` 的 traceability 分支改动点：mode=new 时跳过 `milestoneFile` 必填断言（`workspace-transactions.mjs:2382` 附近），spawn 参数加 `--mode new`，不带 `--milestone-file`；mode=legacy 原样。
- 幂等：同冻结输入重复生成 → 既有 noop 判据（specs 侧已含 `- cr: {cr}` 段）保持；确定性 = 排序规则固定 + 输入全部来自冻结文件 + generator SHA 进 manifest（既有）。

#### 4.8.3 zero_diff 联动修订（§9）

`writeback-traceability.mjs` 从「完全冻结」修订为「legacy 分支逐字节保留 + 新增 new 分支」；`writeback-prd-sdd.mjs`、`writeback-tasks.mjs` 仍完全冻结（tasks 的零发布由 §4.6 入口 preflight 保证，不改 generator）。

### 4.9 Pipeline prompt 收敛检查清单（FR-05.1，8 条 JSON 全部适用）

每条 `kind=skill` 节点 prompt 只保留五类信息（调用哪个 Skill/传哪些参数/依赖哪个前序结构化输出/消费哪些结果/失败如何 abort|skip|reviewLoop）。删改后逐条机械断言：不出现账本文件手工编辑步骤、不出现 `crctl` 算法副本、不出现「status→节点」映射表（下一步只写「以 `crctl next {cr_id}` 为准」）、`node.ref` 全部为 active Skill、节点数量与 `_index.yml` 一致、reviewLoop 的 `maxAttempts`/`replayNodes`/`passCondition` 与 checkpoint 顺序不变（AC-15）。

## 5. 技术选型与替代方案（决策记录）

### D-01 pre-review guard 放代码而非 gates.json

- **Decision**：`--mode pre-review` 的检查序列实现为 `crctl.mjs` 内独立函数 `runPreReviewGateChecks`，不写入 `gates.json#statusGates`。
- **Context**：`gates.json#statusGates` 是状态转换门禁的声明源，被 `preflightAdvance` 在每次 `advance` 时消费；pre-review 是 review-record 的**前置守卫**而非状态转换门禁，两者消费时机与失败语义不同（guard 失败零评审记录，advance 门禁失败保留评审记录）。
- **Alternatives**：A) 在 `gates.json` 增加 `requirement-reviewing` 门禁条目并在 `advance` 消费——会把版本守卫错位到 PASS record 之后，与 PRD §3.3 固定顺序冲突，且 `advance` 的既有调用方语义会被改动；B) 新增独立 JSON 配置——增加第二事实源，违反「不新增平行资产」。
- **Consequences**：pre-review 契约存在于 `crctl.mjs` + PRD §3.2 矩阵；未来若需扩展其他 stage 的 pre-review，须回到本决策评估。

### D-02 mode 判定单函数共享 + authority 参数化（[A2] 修订）

- **Decision**：`resolveTargetSpecMode(ctx, cr, { authority })` 单一纯函数，pre-review gate / advance guard / writeback-apply / archive 四处共用；authority 由调用方按 §2.2.2 生命周期绑定传入，函数自身不解析路径。
- **Context**：PRD §3.1 明确「本节是本 CR 实施和评审使用的唯一模式裁决，不允许 Pipeline、Skill、CLI 各自推断」；四处消费若各自实现两字段比对，漂移修复将四处不同步。B-SDD-06 指出无 authority 参数时 pre-finalize/post-finalize 事实源无法区分，可能消费 stale source。
- **Alternatives**：A) 各命令内联判定——实现最短但违反 PRD 冻结的唯一裁决要求；B) 函数内自动解析 authority（读 status 自行选择路径）——把状态判定复制进 mode 函数，与 `resolveOperationalWorkspace`/strict 解析器产生第二套事实源判定。
- **Consequences**：新增字段读取逻辑集中一处；authority 选择规则集中 §2.2.2；写入方（`buildRegistrationTexts`）只写字面字段、不依赖判定函数。

### D-03 不提供 legacy 注册入口（结构强制而非时间戳判据）

- **Decision**：legacy 判定仅由「两处字段均缺失」+「该形态只能由旧 register 产生」结构保证；不新增时间戳/flag/迁移器判据。
- **Context**：新 register 对 `--target-spec-id` 必填且校验先于一切写入，因此合入后新注册在结构上不可能产生两处均缺失的 CR；历史 CR 才可能缺字段。
- **Alternatives**：A) 按注册时间戳判 legacy——引入新字段与迁移语义，且历史 CR 无可靠时间戳；B) 显式 `--legacy` 入口——PRD 明确禁止「不提供新的 legacy 注册入口」。
- **Consequences**：判定逻辑无时间依赖、无迁移器；AC-02 的「CR-2026-060 不能被自动补字段」由「本 CR 不运行任何批量回填」保证（本 CR 自身作为 legacy 只读兼容走完回写归档，不回写自身字段）。

### D-04 new traceability 走 generator 内 new 分支而非新 generator 文件（[A2] 新增，B-SDD-02）

- **Decision**：在既有 `skills/writeback/scripts/writeback-traceability.mjs` 内新增 `--mode new` 分支（输入=冻结 PLAN/TASK/test-report/merge facts，映射=§4.8.2），legacy 分支逐字节保留；不新建 generator 文件、不新增 candidate/manifest/journal 通道。
- **Context**：AC-12 要求 new traceability 生成 `FR→SDD→TASK→repo@mergeSHA→cmd` 引用链，而既有 generator 强制 milestone-file/fr-chain 且只从 fr-chain 生成 frs（`writeback-traceability.mjs:60-120、:185-199`），与「new milestone=N/A」矛盾；「generator 完全冻结」的旧 zero_diff 与此 AC 不可同时成立（评审维度「批准范围」BLOCK）。
- **Alternatives**：A) 新建第二个 traceability generator——引入平行资产，manifest `generator.id` 唯一性/allowlist/证据 validator 全部要双轨，违反「不新增平行资产」且 AC-13 的 `--validate-evidence` 适配复杂化；B) 在 crctl 内生成 frs 再喂给 generator——把内容投影逻辑搬进事务层，破坏「generator 是内容文件唯一生产点」的分层。
- **Consequences**：`generator.sha256` 变更由 manifest 冻结校验自然兜底（既有 `WRITEBACK_GENERATOR_MISMATCH`）；legacy 夹具逐字节回归防破坏；zero_diff 精确化为「legacy 分支冻结」（§9）。

### D-05 tasks 零发布前置在入口 preflight 而非改 generator（[A2] 新增，B-SDD-03）

- **Decision**：全部 TASK done 的强制在 `applyWritebackAtomic` 入口 preflight（§4.6），`writeback-tasks.mjs` 的 done 子集筛选保留为防御性 no-op；不改 generator 输出逻辑。
- **Context**：B-SDD-03 指出 generator 只筛 done 子集（`writeback-tasks.mjs:45-60`）会发布部分 delivery，而 `prepareWritebackCandidate` 在生成前就已创建 candidate 目录（`workspace-transactions.mjs:2371`）——在 generator 内拦截必然先留 candidate 痕迹。
- **Alternatives**：A) generator 内把「非全 done」改 fail——candidate 目录已创建、manifest 未生成，留下半成品且 legacy 夹具全变；B) 新增独立 preflight 命令供 Skill 调用——增加调用面与漏调风险。
- **Consequences**：失败零 candidate/journal/账本（§4.6 位置保证）；新错误码 3 个（§2.3）均失败零写入、重试条件明确；AC-11/AC-12 可机器断言。

### D-06 模式错误码收敛：顶层唯一 DRIFT + gate 内 kind 映射（[A2] 新增，B-SDD-07）

- **Decision**：顶层 fail()/TxError 码只有 `TARGET_SPEC_AUTHORITY_DRIFT`（`extra.kind ∈ {missing|invalid|mismatch}`，实现 AC-02 字面）；pre-review/advance 的 check code（GATE_BLOCKED 信封内）按 kind 一对一映射 `_MISSING`/`_INVALID`/`_DRIFT`（实现 PRD §3.2 gate 行固定码）。`_MISSING` 的可达前提=单侧缺失（§2.3）。
- **Context**：PRD §3.1/AC-02 把缺一/非法/不一致概括为 `TARGET_SPEC_AUTHORITY_DRIFT`，PRD §3.2 gate 行又固定三种 check code；旧稿 §2.2 选顶层 `_INVALID`、§6.2 写「DRIFT 或 _INVALID」，且伪代码使 `_MISSING` 无可达场景——评审要求先固定映射。
- **Alternatives**：A) 顶层码三分（MISSING/INVALID/DRIFT 平行）——与 AC-02 的字面「缺一、非法或不一致时返回 DRIFT」冲突，违反「PRD 是唯一契约基线」；B) check code 全部用 DRIFT——违反 PRD §3.2 的固定码冻结，调用方路由（version-set vs 人工修复）失去区分度。
- **Consequences**：产品结果未变（PRD 两份表各自字面满足）；实现与测试有唯一映射表（§2.3）；未来新增 mode 失败类别只扩展 kind 枚举。

## 6. FR 到技术实现映射与 AC 级输出合同

### 6.1 FR 映射总表

| FR | 技术方案落点（节） | 主要 TASK |
|---|---|---|
| FR-01 注册合同与单一目标事实 | §3.1 register 行、§4.1、§4.3、§4.7 | TASK-1 |
| FR-02 PRD/SDD 作者与 reviewer 标准对齐 | §3.2 前六行 | TASK-2 |
| FR-03 PLAN/TASK/Coding/测试/代码评审对齐 | §3.2 中段、§4.5 | TASK-3 |
| FR-04 回写成为确定性投影 | §3.1 writeback/archive 行、§4.4、§4.6、§4.8、§3.2 writeback 段 | TASK-4 |
| FR-05 Pipeline、规划与审批输入契约对齐 | §4.9、§3.2 approve/规划/竞品/resume 段 | TASK-1..4 横切（PLAN 覆盖表分配） |
| FR-06 兼容、变更组织与验证闭环 | §1.1 四组、§7、§9 | TASK-1..4 |

### 6.2 AC 逐项设计与验收映射（[A2] 同步修订）

**AC-01（注册三层必填与幂等）**
- 设计落点：`requirement-authoring.pipeline.json` inputs（+`registration_key`/`target_spec_id` required）、`requirement-register/SKILL.md` 参数表、`cmdRegister` 校验段 + 统一结果 builder（§4.3）。
- 可观测结果：缺失 `target_spec_id` 的三层各自 fail；成功注册的 `cr.md` 与 `_backlog.yml` 含相同 `target-spec-id`；同 key 同输入重跑 `changed=false` 无新 commit/outbox/worktree，**且结果 JSON 仍同构含 `cr_id/target_spec_id/operational_workspace/tx_id/target_version/recover_command`（outbox=null）**；同 key 漂移→`REGISTRATION_INPUT_MISMATCH` 零写入（digest 已含 targetSpecId）；**ledger 与 outbox 与 result 三处时间戳 = 同一 `registrationAt`（精确相等断言）；同 key 重试两次 registrationAt 相等；recover_command 含 `--target-spec-id` 可过新必填校验**。
- 可达性说明：校验置于 `BAD_ARGS` 循环与锁/journal 之前，合法输入不被前置过滤；幂等由既有 journal `inputDigest`（已纳入 `targetSpecId`）保证；结果组装删除 :3098 早退后由单一 builder 承担。

**AC-02（模式与目标事实）**
- 设计落点：`resolveTargetSpecMode`（§4.1）+ authority 绑定（§2.2.2）+ 错误码映射（§2.3/D-06）。
- 可观测结果：非法/单侧/不一致字段 → 顶层 `TARGET_SPEC_AUTHORITY_DRIFT`（唯一码，kind 进 extra）且零写入；CR-2026-060 自身两处均缺字段 → legacy，不被回填；pre-review check code 按 kind 唯一映射（§4.2）；**writeback 的 new 分支权威=strict txws，txws 缺失/不自洽→`WRITEBACK_SPEC_REQUIRED`（archive 面→`ARCHIVE_SPEC_REQUIRED`），禁止消费 cr-worktree 回退值**。
- 可达性说明：判定不依赖 CR-ID 特判与时间戳；本 CR 不含任何批量迁移/回填代码路径；`_MISSING` 可达前提=单侧缺失（两处均缺=legacy 跳过）。

**AC-03（版本门禁与评审顺序）**
- 设计落点：`runPreReviewGateChecks`（§4.2）+ `assertRequirementReviewAdvanceGuard`（§4.7）+ `review-requirement/SKILL.md` 固定顺序 + 既有 `cmdVersionSet`（零改动）。
- 可观测结果：new mode `unassigned` → pre-review `GATE_BLOCKED`/`TARGET_VERSION_UNASSIGNED`/exit 1 且临时 payload、annotation、review-loop、trace、outbox、journal、commit 全部不变；**公开 CLI 直连 `advance --to requirement-reviewing` 同码同零写入（无 cr.md 写/audit/commit/outbox/attempt）**；PASS record 后 `advance` 才跑完整 passCondition；`version-set` 的成功/幂等/错误优先级信封与 PRD §3.2 逐条一致。
- 可达性说明：guard 只读 mode 判据与 cr.md target-version，不依赖 PRD/annotation 存在性，故首次评审即可达；两处 guard（gate 命令面 + advance 命令面）都零写入，重复进入无副作用。

**AC-04（PRD authority）**：同 attempt-1（`write-requirement-prd/SKILL.md`；PRD frontmatter 与 cr.md 一致、source 校验、七类章节；本 CR 的 PRD 已 PASS，subject-sha256 `d74ac20a…`）。

**AC-05（作者/reviewer 对称）**：同 attempt-1（两 SKILL 共用七维标准表述；契约闭包表两份文档同表；`HTTP_API契约闭包=N/A` 已 PASS）。

**AC-06（技术闭合）**
- 设计落点：`write-tech-design`/`review-tech-design` SKILL 与本文档。
- 可观测结果：本 CR 的 PRD 未产生 `SDD-CLOSE-*` 延后项；术语硬化表见 §3.3；决策记录见 §5（D-01..D-06 均含 Alternatives 与 Consequences，其中 D-04/D-05/D-06 为本轮回修新增的三判据决策）；SDD 未改变 PRD 已批准的产品结果（D-06 的两表映射各自字面满足 PRD）。
- 可达性说明：评审者可对照 requirement.yml 的八个维度与本文档 §3/§5 核验；本轮 blocker 全部关闭后可复核。

**AC-07（工作区与计划）**：同 attempt-1（两张稳定表、FR 恰出现一次、证据 ID 稳定、resources 透传）。

**AC-08（任务账本与数量）**
- 设计落点：`write-dev-tasks/SKILL.md`（`task_count_hint=4` + §4.5 三步断言）+ `cmdTaskInit --count-hint`。
- 可观测结果：plan.md 预分配恰四 ID 与四组一一对应；**`task init --count-hint 4` 写入前校验失败→`TASK_COUNT_MISMATCH` 且 `_index.yml`/audit 零变化**；init 后复核通过才允许推进；缺失/重复/第五个/跨组 TASK 在写入前即被拦截；done 状态只经 `crctl task done`；`--count-hint` 缺省时既有 CR 行为不变。
- 可达性说明：断言前置到写入前（Skill preflight 与 crctl 写入前校验双点）+ init 后防并发复核（§4.5），不再依赖「事后发现」；失败保留/回滚语义明确（草稿回滚删除、账本只经同命令幂等刷新）。

**AC-09（代码证据）**：同 attempt-1（test-report 证据 canonical 门禁 + review-code 五字段输出）。

**AC-10（回修与审批顺序）**：同 attempt-1（evidence-only 回修路径、blocker 清空前不可达 human approval、approve 节点传完整 cr_id+approver、下一步统一 crctl next）。

**AC-11（new/legacy writeback 输入合同）**
- 设计落点：`cmdWritebackApply` mode 分支（§4.4）+ 三个 writeback SKILL 参数表 + strict authority（§2.2.3）。
- 可观测结果：new 省略 spec/version 时从 strict txws authority 读取；显式不一致在 candidate/journal 前 `WRITEBACK_SPEC_MISMATCH`/`WRITEBACK_VERSION_MISMATCH` 零写入；**txws 缺失/不自洽→`WRITEBACK_SPEC_REQUIRED`（不消费 cr-worktree 回退）**；new 传 milestone → `BAD_ARGS`/N/A；**stage=tasks 索引缺失/非法/存在 pending → `WRITEBACK_TASKS_PENDING`（reason 区分）零写入零发布（§4.6）**；legacy 行为不变且本 CR（legacy）仍可完成 writeback/archive。
- 可达性说明：authority 定位 new 分支=strict 解析器（永不回退），legacy 分支=既有 `resolveWritebackAuthorityPath`（CR-2026-058 行为不变）；第 5.5 步同源绑定对两种 mode 通用。

**AC-12（确定性投影）**
- 设计落点：`applyWriteback` 既有幂等内核 + §4.6 tasks preflight + §4.8 new traceability 生成分支。
- 可观测结果：同冻结 PRD/SDD 重复 baseline 为 noop；任一 TASK 未 done 时 tasks writeback 零写入零发布；new traceability 引用链 `FR→SDD→TASK→repo@mergeSHA→cmd` 由冻结 PLAN/TASK/test-report/merge facts 确定性生成，重复生成 noop，legacy 夹具逐字节不变。
- 可达性说明：引用链元素全部存在于冻结事实中（§4.8.1）；generator new 分支排序固定、输入只读、SHA 进 manifest；tasks 零发布由入口 preflight 保证（不改 generator）。

**AC-13（归档边界）**
- 设计落点：`cmdArchive`（mode 感知 spec-id + journal 重放）+ `cr-archive/SKILL.md` + `review-alignment/SKILL.md` 只读化。
- 可观测结果：archive 仅三段投影 complete 且无 pending trace 时成功；writeback 不重做业务评审；**new mode 省略 spec-id 的 writing-back 首跑从 strict authority 解析并持久化 payload（strict 失败→`ARCHIVE_SPEC_REQUIRED`）；清理后的幂等重放只读 journal payload，不解析已删除路径；payload 缺 spec-id→`ARCHIVE_SPEC_REQUIRED`**；review-alignment 不进入 feature-writeback Pipeline、不推进状态、不写 traceability、不读 mtime/merge-commit/fingerprint。
- 可达性说明：archive 前置门禁沿用既有 `ARCHIVE_*` 码，无新分支绕过；重放来源是持久化事实（journal），不依赖被清理的文件系统路径。

**AC-14（规划输入闭环）**：同 attempt-1（PRD §3.3.1 矩阵、规划审批不改接 CR approve、resume-cr 用 cr-show）。

**AC-15（机器事实不漂移）**：同 attempt-1（8 条 Pipeline JSON 机器断言、reviewLoop/passCondition/checkpoint 不变、prompt 不含算法副本）。

**AC-16（回归与边界）**
- 设计落点：`tools/skills/shared/crctl/scripts/test/` 与既有 lint/check 脚本。
- 可观测结果：`lint-prompts.mjs`、`check-skill-matrix.mjs`、`check-agents-contract.mjs`、`pipeline-structure.test.mjs` 通过；注册缺 spec/非法/单侧/不一致/同键漂移负向测试、**registrationAt 三处精确相等 + 重试稳定断言、changed=false 同构结果断言、recover_command 含 --target-spec-id 恢复测试**、new `unassigned` 的 gate/**advance 直连**拒绝、version-set 全系、new writeback 省略/漂移/legacy 缺参/milestone 非法、**txws 缺失零写入（WRITEBACK_SPEC_REQUIRED）、pending-task preflight 三类 reason、new traceability 确定性生成 + legacy 夹具逐字节回归 + archive journal 重放**、源码日志漂移/TASK 未完成/受保护写入负向测试全部通过。
- 可达性说明：新增测试沿用 `node --test` 与既有 `CRCTL_FAULT_POINT` 注入机制（零新框架）；受保护写入测试复用 `rules.json` deny 面（本 CR 不改该面，见 §7.1）。

**AC-17（交付组织）**：同 attempt-1（CR worktree 无未提交改动；`tasks/_index.yml` 恰 4 条全部 done；不新增状态/Pipeline 节点/事务框架/ledger/Runner/contract-version/feature flag/迁移器）。

**AC-18（遗漏 Skill 与只读边界）**：同 attempt-1（四个 approve-* 合同、规划消费面、review-alignment 任意状态只读验证）。

## 7. 安全与性能考量

### 7.1 安全控制点

- **路径与字段注入**：`--target-spec-id` 正则白名单（小写字母数字 `._-`）在 `cmdRegister`、`registerCr` 防御复查与 `resolveTargetSpecMode` 三处校验，天然拒绝路径穿越/CRLF 注入（NFR-06）；`source` 保持注册期不解析路径。
- **受保护账本**：本 CR 不修改 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny` 与 git 白名单（§9 zero_diff 明确冻结）；`cr.md`/`_backlog.yml` 的新字段写入只发生在 `registerCr` 的 write-set 内（既有 CAS + journal），无第二写入通道。
- **审批无旁路**：四个 `approve-*` 与 pre-review guard 及 advance 层 guard 均不改 TTY/grant/CAS 算法；两处 guard 零写入保证失败不留评审/状态残迹。
- **漂移硬失败**：`TARGET_SPEC_AUTHORITY_DRIFT`、`WRITEBACK_SPEC_REQUIRED`/`WRITEBACK_SPEC_MISMATCH`、`WRITEBACK_TASKS_PENDING` 等全部在 candidate/journal 前 fail，无部分账本（NFR-02）。
- **stale source 防护**：new-mode spec/version 只经 strict txws 解析（无回退）；archive 重放只读 journal payload；既有第 5.5 步同源绑定对版本守卫通用。

### 7.2 性能

- 新增逻辑均为 O(1) 或 O(文件行数) 的纯读取（frontmatter 行匹配、backlog 条目行匹配、plan 表行解析、task 索引解析），不引入网络调用；register/writeback 的既有锁与 journal 开销不变。
- pre-review gate、advance guard、mode 判定与 tasks preflight 是既有读取路径的常数级扩展，无缓存一致性负担（每次现读，符合「git 是权威」不变量）。

## 8. Prompt 采纳影响（必填节：本 CR 触及 `crctl.mjs` 命令面）

本 CR 新增/变更 `crctl.mjs` 的命令入口（`register --target-spec-id`、`gate --mode pre-review`、`advance` 的 requirement-reviewing guard、`writeback-apply`/`archive` 的 new-mode 参数语义、`task init --count-hint`）；`rules.json` 的 `protectedPaths.deny` 面零变更（§7.1）。以下 Skill/Pipeline 的 prompt 若仍按旧调用形态执行将失效，必须改为采纳新能力：

| Skill / Pipeline 路径（[A2] 路径修正） | 现状（旧调用形态） | 应改为的调用方式 |
|---|---|---|
| `skills/requirement/requirement-register/SKILL.md` | 调用 `crctl register` 不带 `--target-spec-id` | 必带 `--target-spec-id`；消费 snake_case 成功 JSON 的 `cr_id`/`operational_workspace`/`tx_id`/`recover_command`（changed=false 亦同构） |
| `skills/requirement/review-requirement/SKILL.md` | 直接写临时 payload → `crctl review-record` | 先 `crctl gate <cr> --for requirement-reviewing --mode pre-review`，pass 后才 review-record；guard block 路由 version-set；声明直连 advance 亦被 advance 层 guard 拦截 |
| `skills/writeback/writeback-prd-sdd/SKILL.md`、`skills/writeback/writeback-tasks/SKILL.md`、`skills/writeback/writeback-traceability/SKILL.md` | 始终显式传 `--spec-id`/`--target-version`/`--milestone-file` | new mode 省略 spec/version（显式值仅作相等校验）；traceability 的 milestone 参数在 new mode 为 N/A（生成输入=冻结 PLAN/TASK/test-report/merge facts）；tasks 注明 pending preflight 失败码与恢复 |
| `skills/cr/cr-archive/SKILL.md` | `crctl archive <cr> --spec-id <id>` 恒传 | new mode 可省略 `--spec-id`（writing-back 首跑从 strict authority 读取；清理后重跑经 journal 重放） |
| `skills/cr/cr-show/SKILL.md`（resume-cr 展示面） | Pipeline 内自建 CR 详情字段清单 | 只调用 `cr-show(cr-id, section: all)` 消费结构化详情，不复制字段清单 |
| `pipeline-templates/requirement-authoring.pipeline.json` 的 prompt（[A2] 路径修正） | 在 node-1 prompt 内写 execution_context YAML 模板（含 owners/knowledge_base_worktree 快照） | 只透传 register JSON 的 `cr_id + operational_workspace`；owners 事实从 cr.md 读取，不再持有 resources 快照 |
| `skills/develop/write-dev-tasks/SKILL.md` | 生成 TASK 文件后直接 `crctl task init` | 执行 §4.5 三步断言：写入前组映射 preflight → `crctl task init --count-hint 4` → init 后防并发复核 |

`review-tech-design` 与人工审批（`approve-tech-design`）须逐条核对本表：每项在新能力合入后是否有残留旧形态调用。

## 9. 批准范围（契约必填章节，[A2] 修订）

- **scope_in（本 CR 必须交付）**：PRD §3 的 FR-01..FR-06 与 AC-01..AC-18 所约束的全部 delta——`crctl.mjs`（register 新 flag/统一结果 builder、pre-review gate、**preflightAdvance 的 advance 层 guard**、writeback-apply/archive mode 分支与 strict authority、**cmdTaskInit 的 `--count-hint` 写入前校验**）、`workspace-transactions.mjs`（buildRegistrationTexts 的 target-spec-id/registrationAt、inputDigest/recoverCommand、**registrationAt 持久化**、**writeback tasks preflight**、**prepareWritebackCandidate 的 traceability new 分支参数**、archive journal payload 扩展）、`skills/writeback/scripts/writeback-traceability.mjs`（**new 分支**，legacy 分支逐字节保留）、§3.2 列明的全部 SKILL.md 合同修订、8 条 Pipeline JSON 的 prompt 收敛与参数映射修订、`review-alignment` 只读化、§6.2 与 AC-16 列明的测试与 lint 断言；四个 TASK 恰为 G1..G4 一一对应。
- **scope_out（明确排除）**：不修改状态机/转换/approval grant/reviewLoop 规则/traceability evidence 结构；不新增 Pipeline 节点、Skill、Agent、状态、账本、事务层、Runner、contract-version、feature flag、迁移器、独立 ADR；不做历史 CR 批量迁移/回填；不实现任何新业务功能/UI/HTTP API。
- **zero_diff（明确不得改动，[A2] 精确化）**：`gates.json` 的状态/转换/审批证据声明、`rules.json` 的 `protectedPaths.deny` 与 git 白名单、`cmdVersionSet`/`normalizeTargetVersion`/`cmdApprove`/`cmdReviewRecord`/`cmdTaskAppend`/`cmdTaskDone`、`durable-tx.mjs`、`writeback-prd-sdd.mjs` 与 `writeback-tasks.mjs` 两个 generator、`specs/`/`delivery/`/主工作区同名 CR 目录、`multica` 仓全部文件。**已解除全冻结、改为精确冻结的内核**：`performAdvance`（commit/outbox/audit 内核冻结，`preflightAdvance` 允许新增只读 guard 分支）、`cmdTaskInit`（render/CAS/审计内核冻结，允许新增 `--count-hint` 写入前校验）、`applyWritebackAtomic`（candidate/manifest/journal/commit/push 内核冻结，允许入口参数来源、tasks preflight 与 traceability new 分支参数）、`writeback-traceability.mjs`（legacy 分支逐字节冻结，允许新增 new 分支）。
- **follow_up（留给后续 CR）**：`crctl upgrade-check` 及其删除计划（CUSTOM-TODO-009，与本 CR 无关）；外部调用量优化目标（ARCHITECTURE.md §7a，观测指标，本 CR 不承诺达成）；规划类审批未来是否迁移 CR 审批机制（PRD 明确本 CR 不迁移）。

## 10. 既有实现依赖与事实（[A2] 修正路径并补齐 explicit dependencies）

**SHA 语义标注（B-SDD-08 要求显式）**：tools 仓全部依赖以 CR 分支当前 HEAD `860288ce96d568ed31a86a8c478d1cfa7f1087e9`（= tools 包 trunk 同 SHA，评审时核验一致）为准。knowledge-base 仓：`269ca7b3088abb0b7f9ff5f2689f627ba4a994db` 是 **PRD 起草/审批落盘基线**（commit `[cr] approve CR-2026-060 requirement approval+status -> requirement-approved`），**不是**当前资源 HEAD；本文件评审时的 kb CR 分支 HEAD = `8da5395e42c9cbc9d7a8c5a4b07251bfe80d7ef3`（其后含 `3f6fab3…` `[cr] update context`、评审记录 `d70a968` 与状态回退 `8da5395` 等非契约提交，不承载 PRD 内容）。PRD 契约以 subject-sha256 为准，与承载 commit 无关。

1. repo: tools
   relative path: `skills/shared/crctl/scripts/crctl.mjs`
   stable symbol/对象: `cmdRegister`（:3080，含 :3098 早退与 :3103 第二个 `nowIso()`，均为本 CR 删除点）、`cmdGate`/`runGateChecks`（:956/:550）、`preflightAdvance`（:963，advance guard 挂点）、`performAdvance`（:1002）、`cmdTaskInit`（:1732）、`loadTaskCards`（:1565）、`cmdWritebackApply`（:3401）、`cmdArchive`（:3368）、`cmdVersionSet`（:2623）、`normalizeTargetVersion`、`readCrMdTargetVersion`/`readBacklogTargetVersionField`（:2564）
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: 本 CR 的命令面变更全部挂接在这些既有函数上（新分支/新校验/新 JSON 键/新 guard）；version-set 与规范化函数零改动，是 pre-review 版本守卫与 writeback 版本校验的既有权威实现。

2. repo: tools
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `registerCr`（:654；inputDigest :679、recoverCommand :684、`nowIso()` 调用 :740）、`buildRegistrationTexts`（:347）、`resolveOperationalWorkspace`（:208）、`resolveWritebackAuthorityPath`（:245，永不抛回退解析器，本 CR 仅 legacy 保留）、`canonicalWritebackBusinessInput`（:2162）、`resolveWritebackCandidate`（:2180）、`prepareWritebackCandidate`（:2371）、`guardWritebackVersion`（:2497）、`applyWritebackAtomic`（:2641 起，第 5.5 步同源绑定）、`applyWriteback`（:2991）、`archiveCr`（:3307）
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: 双账本字段写入点（buildRegistrationTexts）与 journal inputDigest 位于 registerCr；registrationAt 持久化落 register journal payload；new-mode writeback/archive authority 新增 strict 解析器（失败码=PRD 表内 `WRITEBACK_SPEC_REQUIRED`/archive 面既有 `ARCHIVE_SPEC_REQUIRED`，与既有永不抛解析器并列，不修改后者）；tasks preflight 挂 applyWritebackAtomic 入口；archive journal payload 扩展在 archiveCr。

3. repo: tools
   relative path: `skills/shared/crctl/gates.json`、`dir-graph.yaml`
   stable symbol/对象: `statusGates`、`approvalStages`（evidence/passCondition/requireFiles 声明）
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: 状态机（15 具名状态 + `(new)`；28 声明转移、wildcard 展开 50 条）与门禁声明源零改动；pre-review 与 advance guard 均不走 statusGates（D-01/§4.7）。

4. repo: tools
   relative path: `pipeline-templates/requirement-authoring.pipeline.json` 等 8 条 + `pipeline-templates/_index.yml`
   stable symbol/对象: 节点 `reviewLoop`/`passCondition`/`replayNodes`/checkpoint 顺序、节点计数、`requirement-authoring` 的 inputs 必填项
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: FR-05 只收敛 prompt 文本与 inputs 必填项，机器事实字段（节点数量/reviewLoop 配置）是 AC-15 断言基线，不得漂移。注：正文早期引用 `skills/requirement/requirement-authoring` 为笔误，事实源是 `pipeline-templates/requirement-authoring.pipeline.json`（§8 已修正）。

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

7. repo: tools
   relative path: `skills/writeback/scripts/writeback-traceability.mjs`、`skills/writeback/scripts/writeback-tasks.mjs`、`skills/writeback/scripts/writeback-prd-sdd.mjs`、`skills/writeback/scripts/lib.mjs`
   stable symbol/对象: traceability 的 milestone 必填与 fr-chain 段构造（:60-120、:185-199 区间）、`readEvidenceInputs`、tasks 的 done 子集筛选（:45-60 区间）、`lib.mjs` 的 `parseArgs/fail/ok/sha256/writeCandidate`
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: traceability 新增 new 分支（输入与映射见 §4.8），legacy 分支逐字节保留；tasks/prd-sdd generator 完全冻结（tasks 零发布由 §4.6 入口 preflight 保证）。

8. repo: tools（正文直接依赖的 Skill 文件，逐项 explicit dependencies）
   relative path: `skills/requirement/{requirement-register,write-requirement-prd,review-requirement,approve-requirement}/SKILL.md`、`skills/develop/{write-tech-design,review-tech-design,write-dev-plan,write-dev-tasks,review-dev-plan,implement-code,write-test-report,review-code,approve-tech-design,approve-dev-start,approve-code}/SKILL.md`、`skills/writeback/{writeback-prd-sdd,writeback-tasks,writeback-traceability}/SKILL.md`、`skills/cr/{cr-archive,cr-show}/SKILL.md`、`skills/review/review-alignment/SKILL.md`、`skills/planning/*/SKILL.md`、`skills/competitive/*/SKILL.md`
   stable symbol/对象: 各 SKILL.md 的参数表（required/optional）、执行步骤序号（如 review-requirement 的 Step 1/2 之间插入 pre-review）、错误表
   commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
   依赖结论: §3.2 的 delta 全部落在这些文件的既有章节结构上；参数表/步骤/错误表的修改不新增 Skill、不移动目录。四个 approve Skill 的实际位置为 `approve-requirement` ∈ requirement 域、其余三个 ∈ develop 域（§3.2 已修正路径）。

9. repo: ai-first-platform-docs
   relative path: `change-requests/CR-2026-060/prd.md`
   stable symbol/对象: 契约基线（subject-sha256 `d74ac20a97dcaf92c4fbc3d957326a104a20d3e0befe91e0df37198687737586`）、§3.1 模式裁决表、§3.2 CLI 矩阵、§3.3/3.3.1 Skill 矩阵
   commit SHA: 269ca7b3088abb0b7f9ff5f2689f627ba4a994db（**起草/审批落盘基线**，非当前 HEAD；语义见本节目录标注）
   依赖结论: 本 SDD 的全部接口与范围以该 PRD 为唯一契约基线，禁止回退或扩大；PRD 评审 verdict=pass（`review-annotations/requirement.yml`）。

10. repo: tools
    relative path: `ARCHITECTURE.md`
    stable symbol/对象: §4 分层依赖方向、§5 七条硬不变量、§6 刻意不做
    commit SHA: 860288ce96d568ed31a86a8c478d1cfa7f1087e9
    依赖结论: 本 CR 不新增层/状态/账本通道，直接受不变量 1/2/4/7 约束；「独立账本操作脚本库」否决（§6）沿用。

11. repo: ai-first-platform-docs
    relative path: `change-requests/CR-2026-060/cr.md`、`change-requests/_backlog.yml`（本 CR 条目）
    stable symbol/对象: 两处均无 `target-spec-id` 字段（legacy registration 形态）
    commit SHA: 269ca7b3088abb0b7f9ff5f2689f627ba4a994db（注册形态基线；本 CR 工作分支后续 status/评审提交未改注册字段）
    依赖结论: AC-02 的「本 CR 不自动补字段」断言的事实依据；writeback 阶段本 CR 走 legacy 路径的触发形态。

## Discussion 无 Issue 共享会话（v0.32 · CR-2026-059）

> 输入：`change-requests/CR-2026-059/prd.md`（选项 A 定点修订后版本，cycle 3 复评 PASS）。成员口径 = 「项目成员 := 当前 workspace 成员」（PRD FR-25 成员口径段，选项 A 裁决，2026-09-03，AIFI-16）。
>
> 所有既有实现断言均按 multica 仓 CR-2026-059 requirement worktree HEAD `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d` 逐项核实，证据清单见第 10 节（`sdd.explicit_existing_dependencies`），正文引用按首次出现顺序编号 [D-xx]。

## 1. 架构概览

### 1.1 目标

把项目 Discussion 从隐藏 `project_discussion` Issue + comment 承载，切换为 `chat_session(kind='project_shared')` + `chat_message` 承载：打开/发送/附件/协办均不创建工作 Issue；协办任务是无 Issue 的 chat task；旧容器 Issue 只读回放、不双写。

### 1.2 模块边界与改动面（multica 仓；`../tools/` 零改动）

```text
server/migrations/            481–490（10 个新迁移，各有 down）
server/pkg/db/queries/        chat.sql（1 条收窄 + 若干新查询）、attachment.sql（1 条新绑定查询）、
                              idempotency.sql（新）、chat_message 相关插入查询扩展作者列
server/internal/service/      discussion_session.go（新：ensure/send/coordinator/投影/幂等）、
                              task.go（复用 mergeChatConfigContext / CreateChatTask 组合）、
                              chat_idempotency_cleanup.go（新 sweeper）、
                              project_chat.go（GET 不再调 EnsureProjectDiscussionIssue；merge-forward 消息路径）
server/internal/handler/      project_chat.go（GetProjectDiscussion 重写、merge-forward 扩展）、
                              chat.go（config/messages/send/list 按 kind 分流）、
                              project.go（coordinator settings 清除分支 + 锁内投影）、
                              file.go（已发送 shared 附件下载门禁扩展）、
                              daemon.go + handler.go（事件生产端 kind 标注）、
                              workspace_revoke.go（移出事务挂接退订）
server/internal/events/       bus.go（Event 增 ChatSessionKind 字段）
server/internal/realtime/     hub.go / broadcaster.go（新增 Broadcaster.DisconnectWorkspaceUser），
                              redis_relay.go / sharded_stream_relay.go / relay_lifecycle.go（控制帧分支与转发）
server/cmd/server/            listeners.go（kind 感知路由）、sweeper 接线
packages/core/api/            schemas.ts（Discussion 入口/消息/发送响应 schema）、client
packages/views/projects/      discussion-pane.tsx（session 身份重写）、locales 四语 key
```

依赖方向遵守 ARCHITECTURE.md §4：handler → service → db queries；实时路由在 `cmd/server` 组装层；前端 `views → core → ui`。

### 1.3 两张项目会话表的口径（防混淆）

- `project_chat_session`（迁移 472，CR-2026-056）：**Team Agent 群聊**专用表，本 CR **零改动**（NFR-7）。
- `chat_session(kind='project_shared')`：本 CR 的 **Discussion 共享会话**，与 Private Ask / 1:1 同表，靠 `kind` 分流（PRD FR-2、NFR-3「不复制 Discussion 消息表」）。

### 1.4 关键流程

```text
打开      GET /api/projects/{id}/discussion
            └─ EnsureProjectDiscussionSession：advisory + 部分唯一索引收敛 → session 行（不建 Issue）
               └─ 响应 session_id + legacy_issue_id(只读) + coordinator + 解析后配置

普通发送  POST /api/chat/sessions/{sid}/messages (kind=project_shared)
            └─ SendDiscussionMessage 事务：幂等预留 → 锁会话 → 写 chat_message(带作者)
               → 绑定草稿附件 →（无 task、无 Issue）→ 提交 → workspace 广播

协办发送  同上 + coordinator 触发（@mention 可路由 Coordinator 或 analyze/summarize）
            └─ 同事务追加 CreateChatTask(issue_id=NULL, chat_session_id=sid, context.chat_config 快照)
               → daemon 执行 → writeChatCompletionOutcome 把回复写回同一 session [D-11]

配置      PATCH /api/chat/sessions/{sid}/config（kind 分流：private=creator-only 不变；
          project_shared=owner/admin）→ 仅改 session override，绝不 UpdateAgent

协办绑定  PATCH /api/projects/{id}（settings.discussion_coordinator_agent_id）
            └─ 写权威 + 同事务项目锁内投影 session.agent_id（含清除/解绑分支，新增）

转投/转发  RouteDiscussionToTeamAgent / merge-forward：Discussion 侧入参适配，
          不改 sendProjectChatCore（NFR-7、zero_diff）
```

## 2. 数据模型

新迁移从 **481** 起（现最大编号 480 已核实 [D-03]）。编号 481–490 连续，每个文件一条主语句（索引类一律 `CREATE [UNIQUE] INDEX CONCURRENTLY`、一文件一条，PRD FR-21 / ARCHITECTURE 不变量 6 / CLAUDE.md「Database and Migration Rules」），不新增任何 FOREIGN KEY / REFERENCES（481 属「转换既有约束」，是唯一例外且由 PRD 明批——授权段落引注见 §2.1）。

### 2.1 M481 — `agent_id` 可空 + 既有 FK CASCADE→SET NULL（落地 FR-7/FR-21/FR-26）

> **授权引注（FR↔SDD 映射自证；cycle 3 attempt 2 blocker 定点回修）**：本节的 FK 转换（既有约束 `chat_session_agent_id_fkey` 由 `ON DELETE CASCADE` → `ON DELETE SET NULL`）属已批 PRD 的**显式授权范围**，非 SDD 新引入的设计变更：
>
> - **授权段落 1 — PRD FR-7**（`prd.md` `## FR-7`，§3 功能需求，L127/L129）：「列级 NOT NULL 与既有 CASCADE FK 的改动由 481 迁移落地（FR-21）：Coordinator Agent 被 hard-delete 时 session/message 行必须保留（不得级联删除）、`agent_id` 由 FK 置 NULL（AC-31/AC-32 验收）」；
> - **授权段落 2 — PRD FR-21**（`prd.md` `## FR-21`，§3 功能需求，L234–L249）：将 481 迁移定为「**唯一允许的既有 FK 生命周期改动**（这是『转换既有约束』，不是新增 FK）」（L236/L238），并给出完整 `up` SQL（L241–L246：`DROP NOT NULL` → `DROP CONSTRAINT` → `ADD CONSTRAINT ... ON DELETE SET NULL`），与下方本节 SQL **逐字一致**；
> - **基线区分（防误读）**：PRD L74 出现的 `agent_id UUID NOT NULL REFERENCES agent(id) ON DELETE CASCADE` 位于 `## 1.4 当前代码事实（落笔前核实）` 基线表内，是 `033_chat.up.sql` **现状实现的引用**（现有实现基线描述），不是目标态；目标态以上述两个授权段落为准，二者不构成矛盾。

`481_chat_session_agent_nullable_set_null.up.sql`（同文件按序，与 PRD FR-21 给出的 SQL 一致）：

```sql
ALTER TABLE chat_session ALTER COLUMN agent_id DROP NOT NULL;
ALTER TABLE chat_session DROP CONSTRAINT chat_session_agent_id_fkey;
ALTER TABLE chat_session ADD CONSTRAINT chat_session_agent_id_fkey
    FOREIGN KEY (agent_id) REFERENCES agent(id) ON DELETE SET NULL;
```

- 约束名沿用 PostgreSQL 对 `033_chat.up.sql:7` 内联 FK 的自动命名；全量迁移核查确认 033 之后**无任何迁移引用**该约束或改写 `chat_session.agent_id` [D-03]，转换前提成立。
- `ADD CONSTRAINT` 不自动建索引；基线该列亦无独立索引，本 CR 不新增（PRD FR-21）。
- Agent hard-delete 时 DB 把 `agent_id` 置 NULL，session/message 行保留（AC-31/AC-32）。
- `down`：`DROP CONSTRAINT` → 重建 `ON DELETE CASCADE` → `SET NOT NULL`；最后一步在存在 NULL 行时失败，注释写明「先清理 NULL 行再回滚」（数据依赖回滚，不静默吞错）。

### 2.2 M482 — `chat_session.kind`（落地 FR-2）

`482_chat_session_kind.up.sql`：

```sql
ALTER TABLE chat_session
    ADD COLUMN kind TEXT NOT NULL DEFAULT 'private'
    CHECK (kind IN ('private', 'project_shared'));
```

存量行（1:1 与 Private Ask）经列默认值成为 `private`；ADD COLUMN 带常量默认不重写表。新 Private Ask / 1:1 插入继续走默认或显式 `private`（既有 `CreateChatSession` 无需改签名，sqlc 参数缺省即默认值）。

- `down`（`482_chat_session_kind.down.sql`）：`ALTER TABLE chat_session DROP COLUMN kind;`——普通 ALTER、无 CONCURRENTLY、不登记任何钩子（§4.9）。**数据依赖（有损回滚，cycle 2 blocker B-MIG-3 回修）**：PostgreSQL 不为「仍存在 project_shared 行」设防，语句无条件成功；若回滚时仍有 shared 行，其 kind 区分被抹除、行退回 private 语义（旧代码将按 Private Ask 行处理）——回滚序（§4.9）要求先归档/清理 shared session 行再回滚，down 文件注释写明该损失边界，不静默吞错。

### 2.3 M483/M484 — Private Ask 唯一索引谓词收窄：先建新名再删旧（落地 FR-6/FR-5；cycle 1 blocker B-MIG-2 回修）

旧设计（483 先 DROP 旧索引 → 484 同名收窄重建）存在**无唯一约束窗口**：窗口内并发 Private Ask get-or-create 可插入重复 active 行，`ORDER BY ... LIMIT 1` 只能隐藏重复读，既不能阻止重复、也不能保证后续唯一索引构建成功（重复行会使构建失败）。现改为**先以新名称 `CONCURRENTLY` 建好收窄唯一索引，再 `CONCURRENTLY` 删除旧索引**——全程至少有一个唯一约束在位：

`483_chat_session_private_active_unique.up.sql`：

```sql
-- 旧宽谓词索引仍在强制执行时构建收窄索引：不存在无约束窗口。
CREATE UNIQUE INDEX CONCURRENTLY chat_session_private_creator_active_unique
    ON chat_session (project_id, creator_id)
    WHERE project_id IS NOT NULL AND status = 'active' AND kind = 'private';
```

`484_drop_chat_session_project_creator_active_unique.up.sql`：

```sql
DROP INDEX CONCURRENTLY IF EXISTS chat_session_project_creator_active_unique;
```

- **双强制窗口安全**：483 与 484 之间旧索引（宽谓词，不区分 kind）与新索引（`kind='private'`）并存，private 行须同时满足两者；旧约束对 private 行严格强于新约束（跨全部 kind 的唯一蕴含 private 子集内的唯一），故双强制不引入任何额外插入失败，也不存在无约束窗口。483 的构建本身在旧索引全面强制下进行：存量数据经 M482 全部为 `kind='private'`，且旧索引已排除 (project, creator) 重复，新谓词是其行子集，构建不会因数据违规失败；构建期的并发插入同样被旧索引兜住。
- **改名是刻意选择**（推翻旧决策 D-3，见 §5 D-3）：旧名 `chat_session_project_creator_active_unique` 在代码中仅 `chat.sql:16` 注释与 sqlc 生成文件对应注释引用 [D-04]（已核实无 `ON CONFLICT` 按名引用）；代码改动清单含同步更新该注释为新名（`make sqlc` 重新生成时更新生成注释）。新名携带 `private` 谓词语义，未来再增 kind 不会再次名实不符。
- **窗口内收敛**：483/484 同批窗口内 Private Ask get-or-create 仍由旧索引兜底（唯一收敛不变），AC-8 全程可达；483/484 由同一次 `cmd/migrate up` 按版本序逐条应用（迁移循环持会话级 advisory lock、服务启动前跑完——`server/cmd/migrate/main.go`、`server/internal/migrations.Files` [D-03]）。
- **up 登记**：483 为 CONCURRENTLY 构建 → 必须登记 `cmd/migrate` `concurrentIndexCleanups`（中断构建的 INVALID 残留清理；该 map 为 total 不变量，`TestEveryConcurrentUpBuildHasCleanup` 守护，见 §4.9）。
- **down**：`484.down` = `CREATE UNIQUE INDEX CONCURRENTLY chat_session_project_creator_active_unique ... WHERE project_id IS NOT NULL AND status = 'active'`（恢复旧宽谓词；CONCURRENTLY 构建 → 登记 `concurrentDownIndexCleanups`）；`483.down` = `DROP INDEX CONCURRENTLY IF EXISTS chat_session_private_creator_active_unique`。回滚序先 484.down 后 483.down，期间双索引同样并存（过约束但安全），双向均无无约束窗口。**down 数据依赖**：回滚时点若仍有 `project_shared` active 行与同 (project, creator) 的 Private Ask active 行并存，旧宽谓词索引构建会以唯一冲突**硬失败**（不静默吞错）——操作者须先归档/清理 shared session 再回滚（注释写明；kind 支持的回滚窗口按定义即 shared session 不应存在的窗口）。

### 2.4 M485 — shared session 每项目一个 active（落地 FR-3）

`485_chat_session_project_shared_active_unique.up.sql`：

```sql
CREATE UNIQUE INDEX CONCURRENTLY chat_session_project_shared_active_unique
    ON chat_session (workspace_id, project_id)
    WHERE kind = 'project_shared' AND status = 'active';
```

`chat_session.project_id` 为软引用（迁移 214，无 FK [D-05]），shared session 复用该列；项目删除走既有 `ClearChatSessionProjectByProject`（置 NULL）——置 NULL 行自动落出谓词，不产生悬挂唯一键。

- `down`（`485_chat_session_project_shared_active_unique.down.sql`）：`DROP INDEX CONCURRENTLY IF EXISTS chat_session_project_shared_active_unique;`——CONCURRENTLY **删除**、不构建索引，**无构建钩子**：不登记 `concurrentDownIndexCleanups`（该 map 只收 down 方向以 CONCURRENTLY 构建索引的迁移，§4.9）。**数据依赖（cycle 2 blocker B-MIG-3 回修）**：删除后「每项目一个 active shared」的 DB 唯一保证消失；若服务端 kind 分流代码未先回滚，并发首开可产生重复 active shared 行——回滚窗口契约 = 代码先于该 down 回滚（§4.9 逆序清单），down 文件注释写明。

### 2.5 M486 — `chat_message` 作者列（落地群聊展示与 merge-forward 署名）

`486_chat_message_author.up.sql`：

```sql
ALTER TABLE chat_message
    ADD COLUMN author_type TEXT,
    ADD COLUMN author_id UUID;
```

- 可空、无 FK（不变量 6：应用层校验）。存量 Private Ask / 1:1 行保持 NULL（creator-only 语义下作者恒为 creator，前端维持现状渲染，不回填）。
- 写入规则：`kind=project_shared` 的 `role=user` 消息写 `author_type='member', author_id=发送者`；assistant 回复（`writeChatCompletionOutcome` [D-11]）写 `author_type='agent', author_id=task.agent_id`；`kind=private` 路径**不写**（零行为变化，NFR-6）。
- merge-forward 署名直接读作者列；NULL 时退化为 `role` 字面（对齐 `commentAuthorDisplayName` 的 best-effort 语义 [D-20]）。
- **端到端消费契约（cycle 1 blocker B-AUTHOR-1 回修）**——作者列不是 merge-forward 专用，完整消费链逐层定义：
  - 服务端响应：`ChatMessageResponse` 增两个可空字段，`chatMessageToResponse` 直映 M486 列（§3.3）；两条列表查询为 `SELECT message.*`，`make sqlc` 重新生成后列自动进入 `db.ChatMessage`，无需逐查询改列清单；
  - core 契约：`ChatMessageSchema`/`ChatMessage` 增可空字段，malformed/legacy 独立降级（§3.3）；
  - 前端展示：`DiscussionPane` 消息气泡按作者字段解析展示，NULL/malformed 回退现状渲染（§3.3 回退表）；
  - 测试：服务端 NULL/private 行向量 + core malformed/legacy 向量 + pane 作者渲染/回退向量（§6.2 AC-6/AC-18 行）。

- `down`（`486_chat_message_author.down.sql`）：`ALTER TABLE chat_message DROP COLUMN author_type, DROP COLUMN author_id;`——普通 ALTER、无钩子登记（§4.9）。**数据依赖（有损回滚，cycle 2 blocker B-MIG-3 回修）**：已写 shared 消息的作者归属被不可逆抹除，回滚后展示退回本节所述 NULL 降级（role 字面）；private/旧行不受影响（其列本就 NULL）——down 文件注释写明该损失，操作者须知晓（回滚序见 §4.9）。

### 2.6 M487–M490 — 幂等记录表：建表不内联 PK，索引全 CONCURRENTLY（落地 FR-24；cycle 1 blocker B-MIG-1 回修）

> 旧设计在 `CREATE TABLE` 内声明复合 `PRIMARY KEY`，PostgreSQL 会为其隐式创建唯一索引，违反 CLAUDE.md「Database and Migration Rules」（L115 附近）与 ARCHITECTURE.md §5 不变量 6「每个新索引（含新表的索引）必须以 `CREATE [UNIQUE] INDEX CONCURRENTLY` 在独立单语句迁移中创建」。现改为：**487 建表不内联 PK → 488 CONCURRENTLY 建唯一索引 → 489 单语句 `USING INDEX` 挂 PK → 490 CONCURRENTLY 建辅助索引**。

`487_chat_idempotency.up.sql`（仅建表，无任何内联 PK/约束索引）：

```sql
CREATE TABLE chat_idempotency (
    workspace_id UUID NOT NULL,
    user_id      UUID NOT NULL,
    scope_type   TEXT NOT NULL CHECK (scope_type IN ('discussion_message', 'merge_forward_messages')),
    scope_id     UUID NOT NULL,      -- discussion_message: session_id; merge_forward_messages: project_id
    key          TEXT NOT NULL,      -- Idempotency-Key 原值（<=255B，入口已限长）
    fingerprint  TEXT NOT NULL,
    response_status INT NOT NULL,
    response_body   JSONB,           -- 事务提交前为占位（与消息/任务同事务写入）
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`488_chat_idempotency_scope_key_unique.up.sql`（CONCURRENTLY 建承载 PK 的唯一索引）：

```sql
CREATE UNIQUE INDEX CONCURRENTLY chat_idempotency_scope_key_uidx
    ON chat_idempotency (workspace_id, user_id, scope_type, scope_id, key);
```

`489_chat_idempotency_pkey.up.sql`（单语句挂 PK；PostgreSQL 挂接后索引更名为 `chat_idempotency_pkey`）：

```sql
ALTER TABLE chat_idempotency
    ADD CONSTRAINT chat_idempotency_pkey
    PRIMARY KEY USING INDEX chat_idempotency_scope_key_uidx;
```

`490_idx_chat_idempotency_created.up.sql`：

```sql
CREATE INDEX CONCURRENTLY idx_chat_idempotency_created ON chat_idempotency (created_at);
```

- 无 REFERENCES（不变量 6）；CHECK 是表级值约束、不创建索引，不受 CONCURRENTLY 条款约束。`USING INDEX` 要求目标索引唯一、非部分、列序匹配——488 全满足；挂 PK 取 ACCESS EXCLUSIVE 锁，但此时表为空（487 刚建、代码未上线），瞬时完成，不构成热表风险。
- 收敛语义不变：同一 (workspace, user, scope, key) 的并发请求在 PK 上串行；§4.2/§4.6 的冲突仲裁写为 `ON CONFLICT ON CONSTRAINT chat_idempotency_pkey DO NOTHING`——以约束名而非索引名为仲裁靶，索引更名/漂移不影响（决策 D-12）。
- `created_at` 普通索引供 24h sweeper 范围删（§4.6）。
- **down（逆序）**：`490.down` = `DROP INDEX IF EXISTS idx_chat_idempotency_created;`（普通 DROP，幂等表小无需 CONCURRENTLY）；`489.down` `DROP CONSTRAINT IF EXISTS chat_idempotency_pkey`（底层索引随约束一并删除）；`488.down` `DROP INDEX CONCURRENTLY IF EXISTS chat_idempotency_scope_key_uidx`（489 已回滚时为 no-op，仅对「488 已应用、489 未应用」的部分状态生效）；`487.down` `DROP TABLE chat_idempotency;`（删表即删幂等历史，有损、回滚即接受）。
- **登记**：488/490 登记 `concurrentIndexCleanups`；489 为普通 ALTER、484/483/488 的 CONCURRENTLY 删除均不构建索引，无需登记（total 不变量依据见 §4.9）。
- **编号影响**：迁移区间延伸到 **481–490**（PRD「481 起」的下界不变）。

## 3. 接口契约

HTTP 八项细节（精确状态码、错误体、幂等语义）以 PRD「Discussion HTTP 契约」「merge-forward HTTP 契约」为准（FR-22/FR-23 闭合口径）；本节给出服务端落点与类型。公共错误体沿用 `writeErrorCode`（`{code, error}`）[D-31]。

### 3.1 GET `/api/projects/{projectId}/discussion`（重写，落地 FR-1/FR-4/FR-16/FR-25/FR-26）

- 权限：`requireWorkspaceMember` [D-30]；非成员/已移出 → 403 `forbidden_project_discussion`（新 code，PRD FR-18 已列）；项目不在本 workspace → 404（现有 `project not found`，无 code）。
- 行为：`EnsureProjectDiscussionSession`（§4.1）创建或读取唯一 active `project_shared` session；**不调用** `EnsureProjectDiscussionIssue`（该服务函数保留但 GET 路径解除调用 [D-02]）。
- `legacy_issue_id`：`GetProjectDiscussionIssue` **只读**查询 [D-34]，有则 UUID，无则 `null`；GET 不插入、不补建。
- `coordinator_agent_id`：settings 原值（失效也回原 UUID；未配置为空串），规则见 §4.5。
- 配置字段：`ResolveChatConfig(base, override, agentDefault=pgtype.Text{})`——shared 路径恒传无效 `agentDefault`，`agent_default` source 不可能出现（FR-8/PRD GET 契约）[D-17]。

```go
type ProjectDiscussionResponse struct {
    SessionID           string  `json:"session_id"`
    IssueID             *string `json:"issue_id"`        // 恒 nil（JSON null）
    LegacyIssueID       *string `json:"legacy_issue_id"` // 只读回放身份
    CoordinatorAgentID  string  `json:"coordinator_agent_id"`
    Model               string  `json:"model"`
    ThinkingLevel       string  `json:"thinking_level"`
    ModelSource         string  `json:"model_source"`          // override|session_default|runtime_default
    ThinkingLevelSource string  `json:"thinking_level_source"`
}
```

### 3.2 PATCH `/api/chat/sessions/{sessionId}/config`（kind 分流，落地 FR-9/FR-5）

`PatchChatSessionConfig` [D-14] 加载 `GetChatSessionInWorkspace` 后按 `session.Kind` 分流：

- `kind=private`：**逐行保持**现行为（creator-only 403 `forbidden_chat_config`；无 `project_id` 的 1:1 → 404 `chat_session_not_found`；agent provider/catalog 校验）。
- `kind=project_shared`：
  - 门禁：当前 workspace 成员（否则 404 `chat_session_not_found`，FR-17）；PATCH 另需 `requireWorkspaceRole(owner|admin)` [D-30]，非 owner/admin 成员 → 403 `forbidden_chat_config`。
  - 会话状态：`status≠active` → 409 `chat_session_closed_or_changed`；kind/项目不符 → 404。
  - 校验（§4.4 **provider/catalog authority 阶梯**，cycle 1 blocker B-CONFIG-1 回修）：**L1** settings 配置了 Coordinator 且 agent 行存在（可路由或已归档）→ 按该 agent 行逐字走 `LoadChatCatalogForConfig` + `ValidateResolvedChatConfig`（与现 Private Ask 同一实现，禁止第二套 [D-17]；归档 → Blocked verdict → 400）；**L2** 未配置或 agent 行已 hard-delete → 以 workspace ready-runtime 并集 authority 校验（纯 sentinel 恒过；非空值须至少一个 ready runtime 的 catalog 接受，否则 400 `invalid_model_or_thinking_level`）。旧「无 Coordinator 不校验、推迟到入队」口径废除——它使非法配置可成功持久化、AC-10 PATCH 臂不可达（决策 D-6 已重写）。
  - 错误顺序：403/404/409 门禁先于 400 校验（与现 Private Ask BLOCK-003 顺序同构）；校验在服务侧 `LockChatSessionInWorkspace` [D-07] 锁内执行（catalog I/O 期间事务只持会话行锁，与 `SendDirectChatMessage` task.go L2530–2566 同构）。
  - **事务内成员资格复核（cycle 2 blocker B-AUTH-2 回修）**：shared 分支进入事务后、任何写入前，先取 `LockSubscriberWrites(workspace_id, caller)`（**第一把锁**，先于会话行锁——与 `revokeAndRemoveMember` 同一把 (workspace, user) advisory [D-27]，双方都以它为第一把锁 → 与移出串行、锁序一致、无死锁）；随后在事务内 `GetMemberByUserAndWorkspace` 复核成员行存在且 role ∈ {owner, admin}（读的是 advisory 持有下最新已提交状态）：已移出 → 404 `chat_session_not_found`、整个事务回滚、零写入（override 不落库）；advisory 持有至提交（owner/admin PATCH 低频；阻塞面仅同 (ws,user) 的移出，最坏一次 30s LiveLoad round 已封顶）。
  - 写入：`LockChatSessionInWorkspace` [D-07] 下三态写 override（复用 `parseChatConfigFieldPatch`）；无 Coordinator 不走「创建者 Agent」路径、绝不调用 `UpdateAgent`（FR-9）。
  - 已入队 task 不受影响（快照已在 `task.context`，FR-11/FR-26 表）。

### 3.3 GET 消息列表（落地 FR-22）

`ListChatMessages` 与 `ListChatMessagesPage` [D-16] 同样按 `kind` 分流：

- `kind=private`：裸数组 / 分页对象各自保持现状。
- `kind=project_shared`：两个 endpoint **同语义**，一律返回 `ChatMessagesPageResponse` 分页对象（`messages/limit/has_more/next_cursor`），绝不裸数组；门禁为成员级（非成员/错 kind/跨项目 → 404 `chat_session_not_found`）；已归档 session → **200 只读**。
- 分页解析复用 `parseChatMessagesPageParams`；shared 路径错误改为 `writeErrorCode(..., "invalid_cursor", ...)`（`limit` 越界、`before_created_at`/`before_id` 缺一半 → 400 `invalid_cursor`）。
- SQL 复用 `ListChatMessagesPage`（session 作用域 + `message_kind != 'channel_command'` + (created_at,id) 游标）[D-09]；页内反转保持时间正序（现有行为）。
- **消息响应的作者字段（cycle 1 blocker B-AUTHOR-1 回修）**：`ChatMessageResponse`（chat.go L2175 [D-13]）扩展：

```go
// Additive nullable fields; JSON null on private/legacy rows (M486 columns NULL).
AuthorType *string `json:"author_type"` // "member" | "agent"
AuthorID   *string `json:"author_id"`   // 作者 member/agent UUID
```

  `chatMessageToResponse`（~L2217）直映 M486 列（`textToPtr`/`uuidToPtr`），不做第二套解析；两条列表查询与 shared/private 分支共用同一响应映射（private/legacy 行列恒 NULL → JSON null，行为不变）。POST messages 成功体（§3.4 `DiscussionSendResponse`）不含消息对象，无需扩展。
- **core 可空契约**：`ChatMessageSchema`（schemas.ts L818，`.loose()` 体 [D-33]）新增：

```ts
author_type: z.enum(["member", "agent"]).nullable().catch(null).optional(),
author_id: z.string().nullable().catch(null).optional(),
```

  malformed（`author_type` 非枚举值 / `author_id` 非字符串）经 `catch` 落 null，**不毒化整条消息解析**（与 `quick_actions` 的「附加字段独立降级」策略同构）；`types/chat.ts` `ChatMessage` 接口同步增 `author_type?: "member" | "agent" | null; author_id?: string | null` [D-34 基线]。
- **DiscussionPane 作者解析/展示（FR-19 重写面 [D-34]）**：`role=user` 气泡：`author_type='member'` → 以 workspace 成员缓存解析显示名（与现 comment 作者渲染同一数据源），成员行已删（移出）→ 回退新 i18n 四语 key（「未知成员」语义，NFR-2 对称）；`author_type='agent'` → 既有 agent 缓存解析，缺失回退通用标签；`author_id` 为 NULL（private/legacy 行）或字段被降级 → **保持现状渲染**（不显示作者标签），零行为变化。assistant 气泡维持既有 task/agent 渲染。
- **测试向量**：① 服务端——shared 消息返回作者字段、private/legacy 行返回 null；② core `schemas.test.ts`——author_type 缺失/非枚举/非字符串 × 消息仍可解析；③ pane——member 作者显示、agent 作者显示、NULL/malformed 回退（映射 §6.2 AC-6/AC-18 行）。

### 3.4 POST `/api/chat/sessions/{sessionId}/messages`（kind 分流 + 幂等，落地 FR-10/FR-11/FR-15/FR-17/FR-24）

`SendChatMessage` [D-15] 前置加载后按 `kind` 分流；`kind=project_shared` 委托 `SendDiscussionMessage`（§4.2）。输入校验（400 `invalid_discussion_message`，零写入）：

- `content` trim 后为空 且 `attachment_ids` 缺省/空 → 拒绝；
- `attachment_ids` 重复 → 拒绝（不静默去重；重复 ID 进不了指纹，见 §4.6）；非 UUID → 现有 `parseUUIDSliceOrBadRequest` 400；
- `coordinator_request ∈ {none, mention, analyze, summarize}`，缺省 `none`，非法枚举拒绝；
- 缺 `Idempotency-Key` → 400 `idempotency_key_required`；>255B → 400（`MaxIdempotencyBytes` [D-29]）。
- **成员门禁双保险（cycle 2 blocker B-AUTH-2 回修）**：pre-tx 成员 fast-fail（非成员 → 404）之外，§4.2 事务内先取 `LockSubscriberWrites` 与 revoke 串行、再复核成员资格——pre-tx 通过后并发移出的请求在事务内 404、回滚零写入。

成功 **201**，响应体：

```go
type DiscussionSendResponse struct {
    SessionID string  `json:"session_id"`
    MessageID string  `json:"message_id"`
    IssueID   *string `json:"issue_id"` // 恒 nil
    TaskID    *string `json:"task_id"`  // 普通消息 nil；协办为 task UUID
}
```

### 3.5 POST `/api/projects/{id}/chat/merge-forward`（message_ids 扩展，落地 FR-13/FR-23/FR-24）

互斥/选择校验与错误码全按 PRD「merge-forward HTTP 契约」：`invalid_merge_forward_selection` / `invalid_message_selection` / legacy `invalid_comment_selection` 不变。实现：

- `message_ids` 路径：逐条 `GetChatMessageInWorkspace`（新 sqlc 查询：`id + workspace_id`）校验「同属本项目唯一 active/已归档 `project_shared` session」（跨 session/跨项目/`kind=private`/普通 Issue → 400）；重复 id 按首次出现去重（与 comment 路径一致）；去重后 1–50。
- 渲染：新增 `buildMergedForwardContentFromMessages(ctx, taskSvc, msgs []db.ChatMessage, registerCR bool)`——结构对齐 `buildMergedForwardContent`（Trigger message + Conversation history + 可选 registerCR 块）[D-20]，署名改读作者列（§2.5）；**不**抽公共接口泛化，legacy comment 路径保持字节级不变。
- 内核：仍调 `sendProjectChatCore`（零改动，NFR-7）；`message_ids` 路径要求 `Idempotency-Key`（scope_type=`merge_forward_messages`，scope_id=project_id），legacy `comment_ids` 路径不要求（PRD FR-24）。
- 权限：成员 + 既有 Team Agent 发送权限（presenter 规则在内核内，零改动）；非成员 → 403 `forbidden_project_discussion`。**移出竞态（cycle 2 blocker B-AUTH-2 回修）**：`message_ids` 路径在派发 `sendProjectChatCore` 前做一次即时成员复核（`GetMemberByUserAndWorkspace`，最新已提交行），内核自身 presenter 守卫 + `revokeAndRemoveMember` [D-27] 同事务回收 presenter grants 构成第二层。诚实注记：内核事务为 zero_diff、不接 advisory，若 revoke 在内核 presenter 检查后、内核提交前完成，该次转投仍会落一条 Team Agent 消息——与 legacy `comment_ids` 路径现状同语义，本 CR 不放大；已移出者随即失去全部读取权（FR-25）。

### 3.6 其余 session 级 endpoint 的 kind 闭合（接口闭包，SDD-CLOSE-04）

`/api/chat/sessions/{sessionId}/*` 现全部按 creator 门禁 [D-15]。`kind=project_shared` 统一规则：

| 类别 | endpoint | project_shared 行为 |
|---|---|---|
| 读 | `GET /`、`GET /pending-task`、`GET /draft-restores`、`POST /read` | 当前 workspace 成员（非成员 404 `chat_session_not_found`） |
| 轻量写 | `PATCH /`（title）、`PATCH /pin`、`PATCH /archive` | owner/admin（否则 403 `forbidden_chat_config`） |
| 删除 | `DELETE /` | 拒绝：403 `forbidden_chat_config`（「project shared session 不可删除」；历史保留是 FR-16 语义） |
| 其余 | `/quick-actions/*`、`/queued-tasks`、`/onboarding` | 不适用/不改：quick-actions 与 onboarding 是 Private Ask 面，shared 会话不产生该请求（前端不渲染）；`/queued-tasks` 成员可读 |

该表是 FR-17「不得落到 Private Ask 行上 / 不得静默另开 session」的完整闭包：任何携带 `kind=project_shared` 的请求都不进入 creator-only 分支，任何携带 `kind=private` 的请求都不进入成员分支。

### 3.7 实时事件契约（落地 FR-20）

`events.Event` 新增字段（`server/internal/events/bus.go` [D-25]）：

```go
// ChatSessionKind mirrors chat_session.kind at production time. Realtime
// routing uses it to fan shared-session events out to the workspace room.
// Producers MUST set it together with ChatSessionID; the bridge treats an
// empty value as private (fail-closed toward the narrower delivery).
ChatSessionKind string
```

- 路由规则（`listeners.go` [D-24]）：`ChatSessionID != ""` 时，`ChatSessionKind == "project_shared"` 且 `WorkspaceID != ""` → `BroadcastToWorkspace`；否则维持现状（要求 `ChatRecipientID`，`SendToUser`，缺失即丢弃并 ERROR 日志——fail-closed 不变）。
- 生产端：`publishChat` 增 kind 参（调用点 `chat.go`/`chat_title.go`/`mika_onboarding.go` 全部传 `private`，行为不变）[D-27]；`daemon.go` task 流式帧与 `service/task.go` 的 4 处任务事件按 session kind 填 [D-26][D-28]。kind 解析复用会话加载（各生产端本已读 session 行，无新增 DB 往返；`service/task.go` 的 `ChatSessionCreatorID` 辅助扩展为同时返回 kind）。

## 4. 关键算法与流程

### 4.1 EnsureProjectDiscussionSession（落地 FR-1/FR-3/FR-8/FR-16）

```text
tx begin
  LockIssueDuplicateKey("project-discussion-session|{ws}|{project}")   // 专用前缀，与 team-agent 前缀隔离（D-9）
  project ← GetProjectInWorkspace(锁内重读)
  coordinatorUUID ← settings.discussion_coordinator_agent_id
  session ← GetActiveProjectSharedSession(ws, project)                 // 新查询：kind+status 过滤
  if 无:
      base_model/base_thinking ← 可路由 Coordinator ? SnapshotAgentDefaults(agent) : NULL
      InsertProjectSharedSession(ws, project, agent_id=可路由?UUID:NULL,
                                 creator_id=caller, kind='project_shared', base_*)
      唯一索引冲突(并发首开) → 锁内 reselect（与 EnsureProjectChatSession 同构 [D-19]）
  legacyIssueID ← GetProjectDiscussionIssue(只读, 事务外亦可)
  view ← ResolveChatConfig(base, override, agentDefault=无效) + coordinator 原值
commit
```

- 并发 GET 收敛：advisory + M485 部分唯一索引双保险（与 436 注释描述的 Private Ask insert-conflict+reselect 模式同构）。
- 仅有已归档 shared session 时：本流程新建 active 行（M485 谓词含 `status='active'`，不冲突），不自动解档（PRD GET 契约幂等行）。
- 纯人类 Discussion：无 Coordinator 时 `agent_id=NULL` 合法（M481 后）；不要求任何 Agent 存在。

### 4.2 SendDiscussionMessage 事务（落地 FR-10/FR-11/FR-12/FR-15/FR-17/FR-24）

形态对齐 `SendDirectChatMessage`（事务内 task+消息+附件原子提交、提交后才通知/广播 [D-13]），但无 channel/quick-actions 分支：

```text
pre-tx: 头/体校验（§3.4）；成员门禁（非成员 → 404，fast-fail；权威复核在事务内，见下）
tx begin
  LockSubscriberWrites(ws, caller)                   // 第一把锁（B-AUTH-2）：与 revokeAndRemoveMember 同一
                                                     // (workspace, user) advisory [D-27]，双方都以它为第一把锁
                                                     // → 与移出串行、无死锁（锁序见块后段）
  member ← GetMemberByUserAndWorkspace(ws, caller)   // 事务内成员资格复核：advisory 持有下读到最新已提交状态；
      无行 → 404 chat_session_not_found             // pre-tx 通过后并发移出的请求在此拦截，回滚零写入
  advisory "project-discussion-session|{ws}|{project}"
  session ← LockChatSessionInWorkspace(sid, ws) FOR UPDATE [D-07]
      不存在/跨项目/kind≠project_shared → 404 chat_session_not_found
      status≠active → 409 chat_session_closed_or_changed
  idem ← INSERT chat_idempotency(fingerprint, response_body=NULL) ON CONFLICT DO NOTHING
      冲突 → 读赢家行（MVCC：并发未提交则 ON CONFLICT 阻塞至其提交/回滚）
          指纹同 → 直接返回其 response_body（201 重放，事务只读回滚）
          指纹异 → 409 idempotency_key_reused（零写入）
  trigger ← detectCoordinatorTrigger(content, coordinator_request, configured UUID(settings 解析值), 可路由 Coordinator)   // §4.3
      需要协办且未配置 → 409 discussion_coordinator_not_configured（零写入）
      已配置但不可路由（归档/hard-delete；含 @mention 命中失效 Coordinator）→ 409 discussion_coordinator_unavailable（零写入）
      需要协办且调用者无 invocation 权限 → 403（复用 canInvokeAgent/ReasonInvocationNotAllowed，不新造枚举）
  message ← InsertChatMessage(session, role=user, content, task_id=NULL,
                              author_type='member', author_id=caller)                    // M486
  if trigger.needTask:
      // —— 入队前配置校验（B-CONFIG-1 回修；AC-10 入队臂；事务边界：同一事务内、
      //    catalog I/O 只持会话行锁（与 SendDirectChatMessage 同构）；400 → 整个事务回滚 →
      //    消息/task/幂等预留行全部不提交、零写入，Idempotency-Key 因预留行随事务回滚而可复用 ——
      resolved ← ResolveChatConfig(session, agentDefault=无效)
      provider ← GetAgentRuntimeForWorkspace(coordinator.RuntimeID, ws).Provider   // 空 → 400（同 chat 路径）
      catalog ← LoadChatCatalogForConfig(ctx, qtx, port, coordinator)              // §4.4 L1 authority 逐字复用：
                                                                                   // 入队以可路由为前提 → 不可能命中归档 Blocked；cache/LiveLoad 按 §4.3 决策 [D-17]
      ValidateResolvedChatConfig(resolved.Model, resolved.ThinkingLevel, provider, catalog)
          → 失败 400 invalid_model_or_thinking_level
      context ← mergeChatConfigContext(nil, resolved.Model, resolved.ThinkingLevel)      // 单一 merge 缝 [D-10]
      task ← CreateChatTask(agent=可路由 Coordinator, runtime=其 runtime_id, issue_id=NULL,
                            priority=2, chat_session_id=sid, initiator/originator/accountable=caller,
                            originator_source/trigger_evidence 同 chat 路径签章, Context=context)  // [D-08]
      UPDATE chat_message SET task_id = task.id WHERE id = message.id
  attachments:
      LockUnboundDraftAttachments(ws, ids)            // 现有锁序 [D-10]
      bound ← BindDraftAttachmentsToChatMessage(ws, ids, session_id, message_id, task_id?) // 新查询，见下
      len(bound) < len(ids) → 409 attachment_already_bound
  UPDATE chat_session SET updated_at = now()
  UPDATE chat_idempotency SET response_body=…, response_status=201（同事务）
commit
post-commit: publishChat(EventChatMessage, kind=project_shared)（workspace 广播）
             协办时再发 task:queued（kind 标注）+ NotifyTaskEnqueued（daemon 唤醒）
```

**锁序与移出竞态（cycle 2 blocker B-AUTH-2 回修）**：

- 锁序（固定，禁止重排）：`LockSubscriberWrites(ws, caller)` → `project-discussion-session|{ws}|{project}` advisory → 会话行锁 → 幂等键/附件行锁。`revokeAndRemoveMember` 以 `LockSubscriberWrites` 为第一把锁（其后 member 删除与订阅清理，不触碰会话行）[D-27]；delegated auto-subscribe / autopilot 订阅路径同样以它为第一把锁，本事务不触碰 issue_subscriber/autopilot_subscriber——三方首锁一致、其余锁集合不相交，无死锁环。§3.2 shared PATCH 同序（advisory 先于会话行锁）。
- 竞态二择一（FR-25「请求时授权」）：**移出先提交** → revoke 先取 advisory、删 member 行并提交，本事务随后取锁、复核无行 → 404 回滚零写入（幂等预留行随回滚消失，Idempotency-Key 可复用）；**发送先锁** → 本事务复核通过、写完消息/task/附件并提交，revoke 随后删 member 并在提交后挂接 `DisconnectWorkspaceUser`（§4.7）断开其连接——落库消息是移除生效前最后一条合法消息，移除后新请求即时 404。
- 失败事务零残留：复核之后的任何一步失败 → 整体回滚，不留下幂等预留、chat_message、task 或附件绑定（幂等冲突分支除外，其自身有重放语义）。

新 sqlc 查询 `BindDraftAttachmentsToChatMessage`（`attachment.sql`）：对已锁行写 `chat_session_id/chat_message_id/task_id(可空)`，WHERE 保持五类绑定全空 + `source_context_id IS NULL` + uploader=调用者，`RETURNING id`——与 `BindUnboundDraftAttachments`（issue/comment/task 三靶）同构 [D-10]；不复用 `LinkAttachmentsToChatMessage`（其允许 `chat_session_id` 已等于目标且不写 `task_id`，语义不满足 FR-15 协办绑定）。

协办回复：`writeChatCompletionOutcome` 按 `task.ChatSessionID` 写 assistant 行 [D-11]——shared session 的回复**自动**落回同一 session（FR-12），仅需在该写路径补作者列（§2.5）；执行/重试读 `task.context.chat_config`（既有 claim 行为，零改动）。

### 4.3 detectCoordinatorTrigger（落地 FR-11；cycle 1 blocker B-COORD-1 回修）

旧设计只接收「可路由 Coordinator」：归档/hard-delete 后该值为空，对仍配置在 settings 中的失效 Coordinator 的 @mention 会落入「其它 Agent mention → 普通消息」，违反 AC-31/AC-32（要求 409 `discussion_coordinator_unavailable` 且零写入）。现改为：**同时携带 settings 配置 UUID 与可路由状态，先识别「对已配置 Coordinator 的 mention」，再区分未配置/已配置但不可路由**。

```text
输入: content, coordinator_request,
      configured(settings.discussion_coordinator_agent_id 解析 UUID, zero = 未配置),
      routable(当前可路由 Coordinator 行, nil = 不可路由；非 nil 时其 id 必等于 configured)
1. coordinator_request ∈ {analyze, summarize}（优先于 mention 推导）:
     routable ≠ nil                      → needTask=true
     routable = nil 且 configured ≠ zero → unavailable（调用方映射 409 discussion_coordinator_unavailable，零写入）
     routable = nil 且 configured = zero → not_configured（调用方映射 409 discussion_coordinator_not_configured，零写入）
2. 否则 mentions ← util.ParseMentions(content) [D-22]，先识别配置身份：
     configuredMention = type=agent 且 ID 与 configured 归一化（大小写不敏感、规范形式）比较相等的 mention
     configured ≠ zero 且命中 configuredMention:
         routable ≠ nil → needTask=true
         routable = nil → unavailable（409，零写入）——覆盖归档/hard-delete 向量：settings UUID 仍在，
                          hard-deleted agent 的 mention 链接仍携带原 UUID → 仍命中配置身份
     @mention 其它 Agent → 非协办（走普通消息，FR-11 末句；Coordinator 失效不影响其它 Agent mention）
3. coordinator_request=mention 且正文含可路由 Coordinator @mention → 仍只建一个 task（1/2 同源）
4. configured = zero 且 1/2 任一命中协办触发 → not_configured（由调用方映射）
```

- `ParseMentions` 返回去重后的 mentions；同一 configured Coordinator 的多个 mention 按一次计。
- 调用方映射即 §4.2 事务流程中的两个 409 分支，均发生在**任何写入之前**，零写入。

旧 comment 触发路径 `handleDiscussionContainerMentionTrigger` [D-23] **不删不改**：新消息不再写 comment，该路径对存量只读容器不再有新增触发面；保留以兼容任何遗留写入路径。

### 4.4 配置写入与校验：provider/catalog authority 阶梯（cycle 1 blocker B-CONFIG-1 回修）

旧设计「无 Coordinator 时接受任意 override、不校验、推迟到入队」与 PRD FR-9（PATCH 必须走解析/目录/runtime 校验）/ AC-10（不支持值 PATCH 必须 400）冲突——非法配置可成功持久化。本节定义**单一、确定的 provider/catalog authority 阶梯**，PATCH 与协办入队前校验共用，复用既有三函数、无第二套规则表：

```text
resolved ← ResolveChatConfig(base, override, agentDefault=无效)   // 纯解析，单一实现 [D-17]

L1  settings 配置了 Coordinator UUID 且 agent 行存在（可路由或已归档）:
    authority = 该 agent 行
    catalog ← LoadChatCatalogForConfig(ctx, q, port, agentRow)       // 逐字复用：可路由=cache/LiveLoad §4.3 决策；
                                                                       // 归档 → AgentReadiness=Blocked → ErrInvalidModelOrThinkingLevel
    provider ← agentRow.runtime 的 provider（GetAgentRuntimeForWorkspace）
    ValidateResolvedChatConfig(resolved.Model, resolved.ThinkingLevel, provider, catalog)
        → 失败 400 invalid_model_or_thinking_level

L2  settings 未配置 或 配置的 UUID 对应 agent 行已不存在（hard-deleted）:
    authority = workspace ready-runtime 并集（确定顺序）
    runtimes ← ListAgentRuntimes(workspace_id)（ORDER BY created_at ASC [D-39]）
    ready ← runtimeVerdict(rt).Ready() 过滤（复用 verdict 原语 [D-40]，无第二套 readiness 规则）
    if resolved.Model == "" 且 resolved.ThinkingLevel == "":
        通过（纯 sentinel = FR-8「有效值回退 runtime 默认」；空串合法性无需目录权威）
    else 按序扫描 ready runtimes:
        catalog ← port.CacheLoad(rt.ID) 快速路径；miss → 单次有界 LiveLoad（30s deadline，
                  与 LoadChatCatalogForConfig 同语义；fallback/空列表/不可缓存判为该 runtime miss）
                  ——单个 PATCH 至多 1 次 LiveLoad round（首个 cache-miss 的 ready runtime），
                  其余只读 cache，最坏延迟封顶为一次 30s round（与 Private Ask 现有体验同量级）
        ValidateResolvedChatConfig(resolved.Model, resolved.ThinkingLevel, rt.Provider, catalog)
            → 任一 runtime 接受 → 通过（短路）
    全部拒绝 / 零个 ready runtime / catalog 加载全部失败 → 400 invalid_model_or_thinking_level（fail-closed）
```

- **FR-8 与 AC-10 同时成立**：无 Coordinator 时「可保存」与「合法值校验」并存——值被接受当且仅当它是纯 sentinel 或被本 workspace 任一 ready runtime 的 catalog 接受；非法值永不落库（PATCH 即 400）。
- **AC-21 单一实现依据**：并集路径复用 `ResolveChatConfig`/`ValidateResolvedChatConfig`（即 `agent.ValidateChatConfig`）/`ChatCatalogPort`/`runtimeVerdict`，**不引入任何 model/thinking-level 规则表**（无第二套规则集）；`LoadChatCatalogForConfig` 在 L1 与入队点逐字调用（入队必有可路由 Coordinator，恒走 L1）。
- L2 残留语义说明：cache 为 last-known-good；一个只被「从未在本 workspace 报告过 model-list 的 runtime」支持的值判为「此处不支持」——与 `LoadChatCatalogForConfig` 的 cache 语义同向（fail-closed），不构成漏放。
- PATCH 错误顺序：403/404/409 门禁先于阶梯校验 400（§3.2）；校验与写入都在 `LockChatSessionInWorkspace` 锁内完成（与 `SendDirectChatMessage` 同构）。
- 协办入队前校验调用点：§4.2 `if trigger.needTask` 块（`LoadChatCatalogForConfig` + `ValidateResolvedChatConfig`，事务内、`CreateChatTask` 之前；400 → 事务回滚零写入）。

阶梯任何分支（L1/L2）都**不**调用 `UpdateAgent`、**不**改 Agent 行（AC-9）。

### 4.5 Coordinator 写权威、投影与生命周期（落地 FR-7/FR-26）

settings PATCH（`project.go` coordinator 分支 [D-18]）扩展：

```text
值类型分派（三态）:
  非空字符串 → 现有校验（本 workspace Agent 存在，否则 400）→ 绑定/替换
  null 或 ""  → 新增清除分支：从 settings bag 删除 key（FR-26 解绑）
  其它类型    → 400（现状）
绑定/替换/解绑统一走新服务函数
  UpdateProjectSettingsWithDiscussionCoordinator(ws, project, newUUID|空, patch):
    tx begin
      LockIssueDuplicateKey("project-discussion-session|{ws}|{project}")   // 与 GET/发送同一把锁
      写 settings（先写权威）
      session ← GetActiveProjectSharedSession(锁内)
      if session 存在:
          首次绑定且 base_* 全 NULL → 补写 SnapshotAgentDefaults(新 Agent)（FR-26 表）
          UPDATE session.agent_id = 新值或 NULL（投影；替换不重取 base_*，不清空）
    commit
```

- 与 Team Agent 的 `UpdateProjectSettingsWithTeamAgentRebind`（关旧会话建新的 [D-35]）**刻意不同**：Discussion 历史必须留在同一 session，投影 in-place（决策 D-5）。
- GET 侧自愈：`EnsureProjectDiscussionSession` 锁内发现 `session.agent_id` 与可路由解析不一致时，先修复再返回（FR-26 竞态规则 4）。
- Agent 归档/移出 workspace：settings 保留原 UUID、GET 原样回；投影为 NULL（不可路由）；新协办请求（`analyze`/`summarize`，或 @mention 命中该失效 Coordinator——§4.3 配置身份匹配）返回 409 `discussion_coordinator_unavailable`，零写入（AC-31；测试向量：归档后 @mention 失效 Coordinator → 409 零写入，@mention 其它 Agent 仍为普通消息）。
- Agent hard-delete：M481 FK `ON DELETE SET NULL` 在 DB 层置空 `session.agent_id`，session/message 保留；GET `coordinator_agent_id` 仍回 settings 原 UUID（AC-32）；新 @mention/analyze 同样 409 `discussion_coordinator_unavailable` 零写入——hard-deleted agent 的 mention 链接仍携带原 UUID，§4.3 配置身份匹配仍命中（测试向量：hard-delete 后 @mention → 409 零写入，历史回放 200）。

### 4.6 幂等收敛（落地 FR-24/NFR-4）

- 指纹（cycle 1 blocker B-IDEMP-1 回修；PRD POST 契约「稳定排序后的 `attachment_ids`」）：`POST messages` = trim(content) + **重复校验后稳定排序**的 `attachment_ids`（按 UUID 规范串升序，确定性；重复 ID 已在校验阶段 400，进不了指纹）+ `coordinator_request`；merge-forward = 去重后顺序保留的 `message_ids` + `register_cr`（PRD 明定保留顺序，不排序）。指纹为规范 JSON（字段顺序固定）的 sha256 hex。**顺序不变性向量**：同一附件集合仅请求顺序不同的两次请求 → 同指纹 → 201 重放（不得 409；§6.2 AC-26 行）。
- 并发：PK `(ws,user,scope,key)` + `ON CONFLICT ON CONSTRAINT chat_idempotency_pkey DO NOTHING`（仲裁靶为约束名，见 §2.6）；PostgreSQL 对唯一冲突的等待语义保证并发同 key 串行见到已提交赢家 → 同指纹重放 / 异指纹 409，**恰好一次提交**。
- 赢家事务回滚时其行不可见，输家插入成功——无死锁残留。
- 重放不重新执行副作用：直接回存储的 `{status, body}`，已绑定附件不再进入绑定路径（不会 409 `attachment_already_bound`，AC-26）。
- 保留：`SweepChatIdempotency` 每小时删 `created_at < now()-24h`（严格：恰好 24h 的行本轮保留，语义与 `SweepChatDraftAttachments` 的 168h 边界一致 [D-33]）。**口径澄清**：PRD FR-24「记录至少保留 24h」取**保留下限**语义——sweeper 只删严格超过 24h 的行，实际保留时长 ∈ [24h, 25h)（每小时清扫一次）；本 CR 实现为**固定 24h 阈值、不引入可配置保留期**，可配置化如有需要属后续事项（见 §9 follow_up ⑤）。

### 4.7 实时投递与移出退订（落地 FR-20/FR-25/AC-29；cycle 1 blocker B-REALTIME-1 回修）

- shared 事件走 `BroadcastToWorkspace`（hub 房间按连接建立时的成员资格进入，`HandleWebSocket` 逐连接 `MembershipChecker.IsMember` [D-28]）——「当前 workspace 成员可见」由连接级成员资格 + 请求级门禁共同成立。
- Private Ask 投递逐字节不变（kind 缺省 → 原 fail-closed recipient 路径）。

**跨节点断连控制（基线无此能力，本节为新契约）**：基线 `Broadcaster` 仅有消息广播四方法、`redis_relay.go:deliverEnvelope` 只向本地客户端 fanout、不存在任何服务端断连控制 [D-41][D-42]——旧稿「多服务器经既有 relay 广播断连指令」不成立，已废除。新契约：

1. **接口**：`Broadcaster` 增 `DisconnectWorkspaceUser(userID, workspaceID string)`（纯新增；既有四方法零 diff）。语义：断开该用户在该 workspace 的全部 WS 连接，房间清理走既有 `removeClient`。
2. **控制帧**：保留的服务端内部帧 `{"type":"realtime.control","action":"disconnect_workspace","workspace_id":"<uuid>"}`。该类型**绝不投递给客户端 socket**：`deliverEnvelope` 对保留类型加分支——`ev.EventType == "realtime.control"` → `hub.handleControlFrame`（解析 action → 本地 `DisconnectWorkspaceUser`），不再走 `fanoutUser` [D-42][D-43]。
3. **载体**：控制帧复用 scope `user:{userID}` 的既有按-scope 流（publish 路径与 `SendToUser` 同构）。依据：`Hub.Run` register 时自动为每个连接订阅 `user:{userID}` scope [D-26]，relay 消费者按订阅回调启停——**持有该用户 ≥1 连接的节点必然消费 user 流**，恰好覆盖需要断连的节点，无广播风暴。
4. **各模式消费矩阵 [D-44]**：

| Broadcaster 实现 | DisconnectWorkspaceUser 行为 |
|---|---|
| `*Hub`（单节点，无 Redis） | 直接本地断连 |
| `*RedisRelay`（legacy 模式） | XADD 控制信封到 user 流；本节点与所有持有该用户连接的节点各自消费、本地断连 |
| `*ShardedStreamRelay` | 同上（publish 经 shardFor 选定的分片流；消费侧 `deliverMessage`→`deliverEnvelope` 共享控制分支） |
| `*MirroredRelay`（dual 模式） | 转发 primary/mirror 两者，各自发布（两类流族都落控制帧，消费侧同一分支） |
| `*DualWriteBroadcaster`（各 Redis 模式的外层包装） | 本地 `hub.DisconnectWorkspaceUser` 立即执行 + `relay.PublishWithID(user scope, 控制帧)`；环回信封再执行一次，幂等无操作 |

5. **挂接点**：`revokeAndRemoveMember` [D-27] **事务提交后**调用 `broadcaster.DisconnectWorkspaceUser(userID, workspaceID)`，**独立于 `revocationResult.isEmpty()`**（被移出成员即使不拥有任何 runtime 也可能持有 WS 连接；`publishRevocation` 在空结果时提前返回，不能承载此步）。daemon 连接不在此面：由既有 revoke 的 token 吊销路径覆盖（零 diff）。
6. **重连与残留**：连接被断后重连走 `IsMember` → 拒绝；请求级成员门禁（member 行已删）即时阻断新读取。残留窗口：事务提交 → 断连完成（本地同步；跨节点 = 一次 XADD + 消费者唤醒，亚秒级）之间在途帧可能仍送达；XADD 失败记日志+指标并重试一次，仍失败仅记录（请求级门禁与重连拒绝是安全边界，WS 投递为信息面）。
7. **双节点验收向量（AC-29）**：用户 U 在节点 B 持连接；移出事务落节点 A → A 发布控制信封 → B 消费并关闭 U 的连接；其后 workspace 广播不达 U，成员 B（同在节点 B）不受影响。测试：`realtime` 包 hub 级单测（断连/房间清理）+ relay 级控制信封消费测（fake 流）+ handler 级挂接测（含 isEmpty 结果仍断连）；命令见 §6.2 AC-29 行。

### 4.8 已发送附件下载门禁（落地 FR-25 表）

`loadAttachmentForRequest` [D-32] 现按上传者门放行未绑定草稿；扩展：附件 `chat_session_id` 非空且所属 session `kind=project_shared` 时，放行条件改为「当前 workspace 成员」（非成员 → 404，不确认存在）；`kind=private` 与未绑定草稿行为不变。

读路径不产生写入、无需与移出事务串行：门禁读实时 `member` 表（与 §3.1 同源），移出提交后新请求即时 404（AC-28）；在途下载在移出后完成不构成后续写入面。shared 写路径的移出竞态由 §4.2/§3.2 的 `LockSubscriberWrites` 事务内复核关闭（B-AUTH-2）。

### 4.9 迁移与部署顺序

481 → 482 → 483 → 484 → 485 → 486 → 487 → 488 → 489 → 490（编号即部署序；每一步的单向安全性见 §2.3/§2.6：先建新名再删旧、建表→唯一索引→挂 PK→辅助索引）。服务端 kind 分流代码在 482 之后生效；482 落地但代码未上线期间不存在 `project_shared` 行（无创建者），窗口安全。代码在 490 之后上线（`ON CONFLICT ON CONSTRAINT chat_idempotency_pkey` 依赖 489 完成）。

**迁移运行器纪律（硬不变量；cycle 1 blocker B-MIG-1/B-MIG-2、cycle 2 blocker B-MIG-3 同源回修）**：运行器在事务外逐文件应用（`cmd/migrate` runMigrations，单连接会话级 advisory lock）以支持 CONCURRENTLY；**每个以 CONCURRENTLY 构建索引的 up 迁移必须登记 `concurrentIndexCleanups`**（重试前清理中断构建遗留的 INVALID 索引），**每个以 CONCURRENTLY 构建索引的 down 迁移必须登记 `concurrentDownIndexCleanups`**——两 map 均为 total 不变量，由 `TestEveryConcurrentUpBuildHasCleanup` 守护，漏登记直接挂 CI。本 CR 登记清单：up = 483（`chat_session_private_creator_active_unique`）、485（`chat_session_project_shared_active_unique`）、488（`chat_idempotency_scope_key_uidx`）、490（`idx_chat_idempotency_created`）；down = **仅 484.down**（旧宽谓词索引重建——十个 down 中唯一以 CONCURRENTLY 构建索引者）。484.up/483.down/485.down/488.down 为 CONCURRENTLY 删除（不构建）、481/482/486/487/489/490 为普通 ALTER/DROP，均不登记。

**down 全集（481–490，逆序回滚；cycle 2 blocker B-MIG-3 回修——§1.2「各有 down」在此逐条闭环）**：

| 迁移.down | 语句 | 类型 | 钩子登记 | 数据依赖 / 失败语义 |
|---|---|---|---|---|
| 490.down | `DROP INDEX IF EXISTS idx_chat_idempotency_created;` | 普通 DROP | 无 | 幂等表小，无需 CONCURRENTLY |
| 489.down | `DROP CONSTRAINT IF EXISTS chat_idempotency_pkey;` | 普通 ALTER（底层索引随约束删除） | 无 | 488.down 因此 no-op（§2.6 部分状态注记） |
| 488.down | `DROP INDEX CONCURRENTLY IF EXISTS chat_idempotency_scope_key_uidx;` | CONCURRENTLY 删除（不构建） | 无 | 仅对「488 已应用、489 未应用」部分状态生效 |
| 487.down | `DROP TABLE chat_idempotency;` | 普通 DROP | 无 | 删表即删幂等历史（有损，回滚即接受） |
| 486.down | `ALTER TABLE chat_message DROP COLUMN author_type, DROP COLUMN author_id;` | 普通 ALTER | 无 | **有损**：已写 shared 消息作者归属不可逆丢失，展示退回 NULL 降级（§2.5） |
| 485.down | `DROP INDEX CONCURRENTLY IF EXISTS chat_session_project_shared_active_unique;` | CONCURRENTLY 删除（不构建） | **无**（无构建钩子，§2.4） | 每项目单 active 的 DB 保证消失；代码未先回滚时并发首开可产生重复 active shared 行（§2.4） |
| 484.down | `CREATE UNIQUE INDEX CONCURRENTLY chat_session_project_creator_active_unique ...`（旧宽谓词） | CONCURRENTLY **构建** | **`concurrentDownIndexCleanups`（唯一）** | 仍存 project_shared active 行与同 (project, creator) private 行并存时构建**硬失败**（§2.3） |
| 483.down | `DROP INDEX CONCURRENTLY IF EXISTS chat_session_private_creator_active_unique;` | CONCURRENTLY 删除（不构建） | 无 | 回滚序先 484.down 后 483.down，双索引并存过约束但安全（§2.3） |
| 482.down | `ALTER TABLE chat_session DROP COLUMN kind;` | 普通 ALTER | 无 | **有损**：仍存 project_shared 行时 kind 区分被抹除、行退回 private 语义；无条件成功，注释写明损失（§2.2） |
| 481.down | `DROP CONSTRAINT` → 重建 `ON DELETE CASCADE` → `SET NOT NULL`（同文件按序三句，PRD FR-21 授权形态） | 普通 ALTER | 无 | 存在 NULL 行时 `SET NOT NULL` 失败（不静默吞错，§2.1） |

回滚序 = 编号逆序（490→481），`cmd/migrate down` 逐文件、事务外、同一运行器纪律；**代码与迁移回滚顺序**：服务端 kind 分流代码先于 485/482.down 回滚（否则 485.down 后并发首开可重复、482.down 抹除 kind 区分），与 up 方向「代码在 490 之后上线」对称。

sqlc：新/改查询后 `make sqlc` 再生成（不变量 5，生成文件不手改）。`CUSTOM.md` 登记（编号顺延）：481–490 迁移（含上述钩子登记）、`discussion_session.go`、handler kind 分流、settings 清除分支、事件 kind 字段与路由、Broadcaster 断连与 relay 控制分支、幂等表与 sweeper、新绑定查询、前端 discussion-pane、schema 与作者字段。

## 5. 技术选型与替代方案（决策记录）

**D-1 承载表：`chat_session` 加 `kind` vs 新建 `discussion_session` 表** — 选前者（PRD FR-2/NFR-3 已拍板）。替代方案需要第二套消息/附件/事件管道；代价是 `kind` 分流侵入既有 chat handler，以 §3.6 闭包表控制风险。

**D-2 FK 生命周期：CASCADE→SET NULL vs 删 FK+纯应用层校验** — 选 SET NULL（PRD FR-21 已按评审推荐拍板）。保留 DB 级引用完整性；应用层方案在 hard-delete 并发下需自己保证不悬挂。

**D-3 Private Ask 唯一索引：新名先建再删旧 vs 同名先删再建** — 新名 `chat_session_private_creator_active_unique` 先建、再删旧索引（§2.3；cycle 1 B-MIG-2 回修，**推翻原「同名」结论**）。同名先删再建存在无约束窗口（窗口内可插入重复行，重复行反过来使唯一索引重建失败）；先建新名保证全程至少一个唯一约束在位，双强制窗口只过约束不漏放。代价：代码注释（`chat.sql:16`）与 sqlc 生成注释需联动改名——这是索引名的全部引用（已核实无 `ON CONFLICT` 按名引用）。

**D-4 实时路由：生产端携带 `ChatSessionKind` vs listener 按 session_id 查库** — 生产端携带。listener 查库给每个事件加 DB 往返且与「事件层不重反序列化」的 scope-hint 设计相悖；fail-closed 缺省（kind 空 → 原 recipient 路径）保证漏填不泄漏。

**D-5 Coordinator 重绑：in-place 投影 vs Team Agent 式关旧建新** — in-place。Discussion 单一 session 承载全部历史（FR-16/FR-26 表），关旧建新会切断回放并违反「每项目一个 active」。

**D-6 无 Coordinator 配置校验：workspace ready-runtime 并集 authority（L2）vs 接受并推迟到入队校验 vs 拒绝非空保存** — 并集 authority（§4.4 authority 阶梯；cycle 1 B-CONFIG-1 回修，**推翻原「接受并推迟」结论**）。「接受并推迟」使非法配置可成功持久化，AC-10 的 PATCH 臂不可达；「拒绝非空保存」使 FR-8「仍可保存」对有意义值落空。并集 authority 使两者同时成立：值当且仅当被本 workspace 任一 ready runtime 的 catalog 接受（或为纯 sentinel）才通过，校验仍是既有三函数与 `runtimeVerdict` 的复用、无第二套规则表。代价：PATCH 最坏一次 30s LiveLoad round（与 Private Ask 现有 `modelListPendingTimeout` 体验同量级）；cache 冷启动的 workspace 对非空值 fail-closed。

**D-7 幂等存储：专用 `chat_idempotency` 表 vs 复用现有存储** — 专用表。现有仅头常量基建（无存储）[D-29]；内存方案不满足重启后 24h 保留。

**D-8 作者归属：`chat_message` 加可空作者列 vs 渲染期推导** — 加列。shared 会话多发送者，推导只能得到 session creator（错误归属）；列在插入时即真。

**D-9 Discussion advisory 前缀独立（`project-discussion-session`）vs 复用 team-agent 前缀** — 独立。两类会话生命周期无关，共用前缀会让无关操作互相串行。

**D-10 merge-forward 消息渲染：平行函数 `...FromMessages` vs 泛化公共接口** — 平行函数。legacy comment 路径字节级不变是 NFR-6 硬要求；泛化需同时改两路、扩大回归面。

**D-11 跨节点断连：user-scope 控制帧 vs 专用控制流 vs 成员资格周期重验** — user-scope 控制帧（§4.7；cycle 1 B-REALTIME-1 回修）。专用控制流需要独立的订阅注册与消费者生命周期（既有订阅回调只覆盖有本地订阅者的 scope）；成员资格周期重验给每个连接增加 DB 压力且拖慢投递。控制帧复用既有按-scope 流与「持有用户连接的节点必然消费 user 流」的事实，零新增订阅机制；代价：保留事件类型占用 `deliverEnvelope` 一个分支，控制帧永不到客户端。

**D-12 幂等表主键：CONCURRENTLY 建唯一索引后 `USING INDEX` 挂 PK vs 仅以唯一索引作 `ON CONFLICT` 仲裁** — 挂 PK（§2.6；cycle 1 B-MIG-1 回修）。裸唯一索引也能仲裁（`ON CONFLICT (columns)`）且省一个迁移，但表失去显式 PK 身份（pg 工具/sqlc 惯例对事实表均预期 PK）；挂 PK 后仲裁靶写为 `ON CONFLICT ON CONSTRAINT chat_idempotency_pkey`，稳定不依赖索引名漂移。代价：多一个单语句迁移 489（空表上瞬时完成）。

## 6. FR/AC 映射与 SDD-CLOSE

### 6.1 FR → 技术实现映射

| FR | 技术落点 |
|---|---|
| FR-1 | §3.1 GET 重写；`EnsureProjectDiscussionIssue` 解除调用 [D-02]；无其它 `origin_type='project_discussion'` 写入路径 |
| FR-2 | §2.2 M482 kind 列；CHECK 枚举；存量默认 `private` |
| FR-3 | §2.4 M485 部分唯一索引 + §4.1 advisory 收敛 |
| FR-4 | §3.1/§4.2 门禁一律成员资格；`creator_id` 仅审计列；消息查询不按 creator 过滤 |
| FR-5 | §2.3 M483/M484 谓词收窄 + `GetProjectChatSessionForCreator` 加 `kind='private'` 过滤（§6.3 SDD-CLOSE-09，三处调用点 [D-06] 语义全部保持）+ §3.6 闭包表 |
| FR-6 | §2.3（同 FR-5 的索引改写）+ §2.4 |
| FR-7 | §2.1 M481 + §4.1/§4.5 NULL 合法 + INNER JOIN agent 查询盘点：均为 agent 作用域路径（builder 列表/系统 runtime/creator 待办），不被 NULL 带崩、不参与 Discussion 查询 |
| FR-8 | §3.1 base_* 快照规则 + §4.4 无 Coordinator 分支 |
| FR-9 | §3.2 kind 分流；`ResolveChatConfig`/`ValidateResolvedChatConfig`/`LoadChatCatalogForConfig` 单一实现复用 [D-17]；无 Coordinator 校验 authority = §4.4 L2 workspace ready-runtime 并集（无第二套规则表，B-CONFIG-1 回修） |
| FR-10 | §4.2 普通消息只写 `chat_message`（无 task/Issue/comment） |
| FR-11 | §4.2/§4.3 触发判定 + `CreateChatTask(issue_id=NULL)` [D-08] + `mergeChatConfigContext` 快照 [D-12] + 两个 409 + invocation 403 复用 |
| FR-12 | §4.2 末：`writeChatCompletionOutcome` 按 `task.ChatSessionID` 写回 [D-11]；重试读 `context.chat_config`（既有 claim 行为） |
| FR-13 | §3.5 message_ids 路径 + `RouteDiscussionToTeamAgent` 触发源改为 shared 消息（入参适配，内核不动）[D-21]；KG-1/KG-2 明示不修 |
| FR-14 | 复用 CR-2026-056 草稿契约：五空上传、上传者门（`loadAttachmentForRequest` 不变部分）、168h sweeper 谓词不改 [D-33] |
| FR-15 | §4.2 同事务绑定（`BindDraftAttachmentsToChatMessage`）+ 失败零残留 + 草稿保留重试 |
| FR-16 | §3.1 `legacy_issue_id` 只读 [D-34]；不双写、不删除、不补建 |
| FR-17 | §3.2/§3.4/§3.6 固定状态映射表（404/409/200 只读）+ `LockChatSessionInWorkspace` 锁内复验 [D-07] |
| FR-18 | 全部 code 落点：§3.1–§3.5 + `writeErrorCode`/`writeProjectChatSendError` [D-24][D-18]；legacy `invalid_comment_selection` 不动 |
| FR-19 | 前端：schema 重写（`session_id` 硬降级只读）、discussion-pane session 身份、legacy 只读流、配置控件走 PATCH config（不 `UpdateAgent`） |
| FR-20 | §3.7 事件 kind 字段 + §4.7 路由与退订 |
| FR-21 | §2.1 M481（SQL 与 PRD 逐字一致）+ §4.9 编号/CONCURRENTLY/CUSTOM.md/英文注释 |
| FR-22 | §3.1–§3.4 八项闭合（精确状态 + code + 权限 + 幂等 + 副作用 + 观察点引 PRD 表） |
| FR-23 | §3.5 修改契约闭合（互斥/空/重复/顺序/跨 session/权限/幂等） |
| FR-24 | §2.6 M487–490（建表/唯一索引/挂 PK/辅助索引，全 CONCURRENTLY 合规）+ §4.6 收敛算法（指纹稳定排序）+ §3.4/§3.5 缺头/冲突错误 |
| FR-25 | §3.1/§3.2/§3.4 成员门禁 + §4.7 实时拒绝/退订 + §4.8 附件 404 + 草稿仍仅上传者 |
| FR-26 | §4.5 写权威/投影/读规则/竞态/归档/hard-delete 全表落地 |

### 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §3.1 GET 重写；`EnsureProjectDiscussionIssue` 调用移除 | GET 后 `issue` 表无新 `origin_type='project_discussion'` 行；响应 `issue_id=null`、无历史则 `legacy_issue_id=null` | GET 是面板唯一入口，无其它创建路径（代码级核查） |
| AC-2 | §4.2 事务无 Issue 写入；§4.5 绑定/解绑无 Issue | 四类操作后 `issue` 行计数不变 | 发送/绑定路径全部经新服务函数，无旁路 |
| AC-3 | §4.2 普通分支不调 `CreateChatTask` | 响应 `task_id=null`；`agent_task_queue` 无新行 | 触发判定为唯一 task 入口（§4.3） |
| AC-4 | §4.2/§4.3 task 参数 | `chat_session_id=sid`、`issue_id` NULL、`context.chat_config` 存在 | 协办分支在同一事务写，提交即可查 |
| AC-5 | §4.2 末 `writeChatCompletionOutcome` [D-11] | assistant `chat_message.chat_session_id=sid`；session 无对应 Issue | 回复路径只读 `task.ChatSessionID` |
| AC-6 | §4.2 成员门禁 + §3.6 闭包 + §3.2 private 分支不变 + §2.5/§3.3 作者契约 | 成员 B 见 A 的 shared 消息**且气泡经作者字段解析作者**（member 显示名；缺失回退）；B 的 Private Ask 对 A 403/404 不变 | 两条门禁互不交叉（kind 分流）；作者字段为附加可空字段，private 行为不变 |
| AC-7 | §3.1 只读查询 [D-34]；新消息不写 comment | 旧 Issue comment 流冻结在切换点 | 无任何双写代码路径 |
| AC-8 | §2.3/§2.4 索引 + §4.1 锁 | 并发首开仅 1 行 active shared；同 creator 的 Private Ask 并存 | 两个谓词互斥（`kind` 区分），并发由 advisory 串行 |
| AC-9 | §3.2 角色门禁 + §4.4 不调 `UpdateAgent` | 非 owner/admin 403 `forbidden_chat_config`；`agent.model/thinking_level` 不变 | 门禁在 provider 解析之前（错误序与现 Private Ask 一致） |
| AC-10 | §4.4 authority 阶梯（L1/L2，含无 Coordinator 的 L2 并集）+ §4.2 入队前校验（事务内，400 回滚零写入） | PATCH（可路由/归档/未配置/hard-deleted 四态）与协办入队对不支持值返回 400 `invalid_model_or_thinking_level`；已入队 `chat_config` 不变 | L1/L2 覆盖全部 Coordinator 状态，非法值无免校验持久化路径（B-CONFIG-1 回修）；命令 `go test ./server/internal/handler/ ./server/pkg/agent/ -count=1` |
| AC-11 | §4.3/§4.2 未绑定分支 | 409 `discussion_coordinator_not_configured`；无 task/Issue | 触发判定先于任何写入 |
| AC-12 | 复用 CR-2026-056 草稿门（§4.8 不变部分） | 非上传者下载/列表/流均不可见 | 未绑定行五空谓词不变 |
| AC-13 | §4.2 `BindDraftAttachmentsToChatMessage` | 成功行 `chat_session_id/chat_message_id`（+协办 `task_id`）非空；失败五空可重试 | 绑定与消息同事务，回滚即全空 |
| AC-14 | §2.1 M481 + §4.1/§4.5 | 无 Coordinator GET/发送成功、`agent_id` 空；绑定后可协办；解绑回空、历史可读 | NULL 合法贯穿查询（无 INNER JOIN 阻挡，FR-7 盘点） |
| AC-15 | §3.5 message_ids 路径 | 201 + Team Agent 侧一对 comment/task；源消息不动；legacy 路径与原 400 不变 | 两路径代码分离，legacy 字节级保留 |
| AC-16 | §3.5 内核复用 `sendProjectChatCore`（zero_diff） | 转投仍走既有内核；本 CR diff 不含该函数 | diff 审查 + 既有内核测试全绿 |
| AC-17 | 前端 schema 硬降级（`session_id` 缺失/空/非 UUID → 只读） | `packages/core/api/schemas.test.ts` 用例；`legacy_issue_id` 不参与发送 | schema 是响应唯一解析入口（NFR-8） |
| AC-18 | discussion-pane session 身份 + 四语 key + §3.3 作者展示/回退 | pane 不依赖可写 `issue_id`；user 气泡作者展示（member/agent 解析，NULL/已移出成员回退）；`parity.test.ts` 全绿 | 文案经 locales 单一出口；作者回退文案四语对称（B-AUTHOR-1 回修） |
| AC-19 | §2.1–§2.6 + §4.9（含 down 全集与逆序回滚清单） | `pg_get_constraintdef` 见 `ON DELETE SET NULL`；**up/down 往返全绿（481–490 十条 down 各自可执行，含 482/485/486.down）**；**每个新索引（含新表 PK 的隐式索引）均由独立单语句迁移 `CONCURRENTLY` 构建**（487 不内联 PK → 488 CONCURRENTLY 唯一索引 → 489 `USING INDEX` 挂 PK → 490）；`concurrentIndexCleanups`/`concurrentDownIndexCleanups` 登记完整且 down 侧**仅 484.down**（唯一 down 方向 CONCURRENTLY 构建；485.down 为 CONCURRENTLY 删除无构建钩子）；482/486 有损回滚注释存在；`CUSTOM.md` 登记 | 迁移测试直查约束定义与索引创建方式；481 前提已核（无后续引用 [D-03]）；命令 `go test ./server/cmd/migrate/ -count=1`（up/down 往返与登记完整性守护）；B-MIG-1/B-MIG-2/B-MIG-3 回修 |
| AC-20 | §3.2/§3.4 状态映射 + §3.3 归档只读 200 | 成员对归档 session PATCH/POST 409；错 kind/跨项目/非成员 404；列表仍 200 | 映射集中在一个分流函数，无二义分支 |
| AC-21 | §3.2/§4.2/§4.4 只调 `ResolveChatConfig`/`LoadChatCatalogForConfig`/`ValidateResolvedChatConfig` [D-17] | 测试不出现第二套规则表；L2 并集为同一组函数 + `runtimeVerdict` 的复用，无新增 model/thinking 规则 | 单一实现函数签名不变，新调用点只是新 caller（B-CONFIG-1 回修） |
| AC-22 | §3.6 闭包 + NFR-6/7 零改动面 | Team Agent GET 仍不建 Issue；Private Ask 夹具全绿；`go test ./server/internal/handler/ ./server/internal/service/ -count=1` 无新增无关失败 | private 分支逐行保留，回归基线可比 |
| AC-23 | §3.3 shared 恒分页对象 | 无 cursor 200 分页对象；`limit=0`/半截 cursor → 400 `invalid_cursor`；页内 `created_at` 非递减 | SQL 取降序窗、序列化前反转（现有 `ListChatMessagesPage` 行为） |
| AC-24 | §3.4 输入校验 | 空/重复/非法枚举 400 `invalid_discussion_message` 零写入；仅附件 201 且 `task_id=null`；成功恒 201 | 校验在事务前，拒绝即零副作用 |
| AC-25 | §3.5 互斥/选择校验 | 双非空 400 `invalid_merge_forward_selection` 且 Team Agent 侧零新行；跨源 400 `invalid_message_selection`；重复只合并一条 | 校验先于内核调用；去重与 comment 路径同语义 |
| AC-26 | §2.6/§4.6 | 缺头 400 零写入；同指纹重放两次 201 同 id、附件不 409、DB 单条；异指纹 409 零写入；**同一附件集合仅请求顺序不同 → 同指纹 → 201 重放（非 409）**；并发单次提交 | PK 冲突收敛由数据库唯一性保证（§4.6）；指纹的 `attachment_ids` 稳定排序（B-IDEMP-1 回修） |
| AC-27 | §3.5 message_ids 幂等 | 缺头 400；重放 201 同 `comment_id/task_id`；legacy 无头仍 201 | 幂等仅挂 message_ids 分支 |
| AC-28 | §3.1 403 + §3.2/§3.4 404 + §4.8 附件 404 + §4.2/§3.2 事务内复核（B-AUTH-2） | 非成员：项目路径 403 `forbidden_project_discussion`、session 路径 404、附件 404 无字节；移出 workspace 即时同效；**竞态向量：pre-tx 通过后并发移出先提交 → 发送/PATCH 事务内复核 404、零写入（无幂等/消息/task/附件残留）** | 门禁读 `member` 表实时资格，无历史缓存；写路径以 `LockSubscriberWrites` 与 revoke 串行后复核（B-AUTH-2） |
| AC-29 | §4.7 断连契约（`Broadcaster.DisconnectWorkspaceUser` + user-scope 控制帧 + 各模式消费矩阵）+ 拒绝重连 | 非成员/移出者订阅被拒；移出后不再收到；成员 B 不受影响；**双节点向量：U 连接在节点 B，移出事务落节点 A → B 关闭 U 连接且后续事件不达**；`go test ./server/internal/handler/ ./server/internal/service/ ./server/internal/realtime/ -count=1`（PRD 夹具口径「handler 或 realtime 测试」） | 断连挂接 `revokeAndRemoveMember` 事务提交后钩子、独立于 `revocationResult` 空否 [D-27][D-41–D-44]；B-REALTIME-1 回修；**移出与发送并发二择一（B-AUTH-2）：revoke 先提交 → 发送 404 零写入；发送先提交 → 消息落库后断连生效（§4.7）** |
| AC-30 | §4.5 投影事务 | 首绑 settings=session.agent_id 同值、空 `base_*` 补写；替换只动 `agent_id`、已入队不变；解绑回空、历史可读 | 写权威与投影同一事务同一锁，无分叉窗口 |
| AC-31 | §4.5 归档行 + §4.3 配置身份匹配 | GET 仍回原 UUID；新协办（analyze/summarize 或 @mention 命中失效 Coordinator）409 `discussion_coordinator_unavailable` 零写入；**归档向量：归档后 @mention 失效 Coordinator → 409 零写入，@mention 其它 Agent 仍为普通消息**；settings 不被 GET 清；并发后投影一致 | 读规则集中在一个解析函数；触发检测同时携带 settings UUID 与可路由状态（B-COORD-1 回修） |
| AC-32 | §2.1 SET NULL + §4.5 hard-delete 行 + §4.3 配置身份匹配 | agent 行删后 session/message 全保留、`agent_id` NULL、GET 回 settings 原值、回放 200、新 @mention/analyze 409 零写入；**hard-delete 向量：删除后 @mention 失效 Coordinator（mention 链接携原 UUID）→ 409 零写入** | FK 在 DB 层执行，无应用层竞态窗口；mention 匹配为 UUID 归一化比较、不依赖 agent 行存在（B-COORD-1 回修） |

### 6.3 SDD-CLOSE（PRD 延后项逐项关闭）

| 编号 | PRD 延后项 | 关闭结论 |
|---|---|---|
| SDD-CLOSE-01 | FR-24 幂等记录存储（「仅有头常量基建」） | §2.6 `chat_idempotency` 表（487–490：建表/唯一索引/挂 PK/辅助索引）+ §4.6 PK 冲突收敛 + 24h sweeper；指纹定义（稳定排序）、重放语义、并发收敛全部落地（B-MIG-1/B-IDEMP-1 回修） |
| SDD-CLOSE-02 | FR-20 kind 感知多成员实时投递（「设计工作」） | §3.7 `Event.ChatSessionKind` + §4.7 路由/断连；fail-closed 缺省保持 private 语义 |
| SDD-CLOSE-03 | 群聊作者归属（`chat_message` 无作者列） | §2.5 M486 作者列 + 写入规则（§2.5/§4.2）+ **端到端消费链（B-AUTHOR-1 回修）：服务端 `ChatMessageResponse` 可空字段 → core `ChatMessageSchema`/`ChatMessage` 可空契约（malformed catch 降级）→ `DiscussionPane` 作者解析/展示（member/agent/NULL 回退）→ merge-forward 署名（§3.5），附 malformed/legacy 测试向量** |
| SDD-CLOSE-04 | FR-17/FR-22 session 身份与接口闭包 | §3.1–§3.4 + §3.6 全 endpoint kind 分流表；固定错误映射无二义分支 |
| SDD-CLOSE-05 | FR-23 merge-forward 修改契约 | §3.5 + §4.2（幂等复用）；八项全闭合，legacy 零变化 |
| SDD-CLOSE-06 | FR-26 解绑/投影数据模型 | §4.5 settings 三态清除分支 + 锁内投影事务 + 归档/硬删生命周期 |
| SDD-CLOSE-07 | FR-8/FR-9 无 Coordinator 配置边界 | §4.4 authority 阶梯 + 决策 D-6（重写）：无 Coordinator 校验 authority = workspace ready-runtime 并集（L2），可保存与合法值校验同时成立；入队前校验与事务边界见 §4.2（B-CONFIG-1 回修） |
| SDD-CLOSE-08 | FR-21/FR-6 迁移序列 | §2.1–§2.6 + §4.9：481–490 全序列（先建新名再删旧、建表不内联 PK + CONCURRENTLY 唯一索引 + `USING INDEX` 挂 PK）、钩子登记清单、**down 全集与逆序回滚清单（482/485/486.down 已补）、down 数据依赖注记**（B-MIG-1/B-MIG-2/B-MIG-3 回修） |
| SDD-CLOSE-09 | FR-5 `GetProjectChatSessionForCreator` 泄漏点 | 查询加 `AND kind = 'private'`；三调用点（`project_chat.go:343/378`、`autopilot.go:990` [D-06]）语义全部保持——它们都只要 Private Ask |
| SDD-CLOSE-10 | FR-16 legacy 回放身份 | §3.1 `legacy_issue_id`（只读 `GetProjectDiscussionIssue`，不补建） |

## 7. 安全与性能考量

### 7.1 安全

- **授权模型**：请求时 `member` 表实时资格（无缓存旁路）；session 路径对非成员一律 404（不确认存在）；项目路径 403。`creator_id` 永不作 ACL（FR-4）。**写路径移出竞态关闭（cycle 2 blocker B-AUTH-2 回修）**：shared POST/PATCH 于事务内、首次写入前取与 `revokeAndRemoveMember` 相同的 `LockSubscriberWrites(ws, caller)` advisory 并复核成员行——复核失败整个事务回滚，幂等/消息/task/附件零残留（§4.2/§3.2）；锁序固定见 §4.2。
- **UUID 猜测**：`GetChatSessionInWorkspace` 强制 `workspace_id` 谓词 [D-07]；shared 附件下载 404；实时连接经 `IsMember` [D-28]。
- **fail-closed 实时**：kind 缺省/未知 → 维持 recipient-only 或丢弃（§3.7），漏填的最坏结果是少投递不是泄漏。
- **事务完整性**：发送/绑定/协办单事务零残留（§4.2）；settings 写权威与投影同事务（§4.5）。
- **越权面**：session 级未列举 endpoint 全部在 §3.6 表中显式定权（无默认放行）；`DELETE` shared 会话直接拒绝。
- **代码纪律**：multica 注释一律英文（CLAUDE.md）；`CUSTOM.md` 登记（§4.9）。

### 7.2 性能

- advisory 锁粒度 = 单项目（`{ws}|{project}`），跨项目无串行；锁内操作均为索引点查。
- 索引全部 `CONCURRENTLY`，部署不锁表；483/484 窗口语义见 §2.3（先建新名再删旧，无无约束窗口）；489 挂 PK 在空表上瞬时完成（§2.6）。
- 配置 PATCH 的 L2 并集 authority：一次 `ListAgentRuntimes` 查询 + cache 快速路径，最坏一次 30s LiveLoad round，owner/admin PATCH 低频（§4.4）。
- 幂等表按 PK 点查点写，`created_at` 辅助索引供范围删；行尺寸有界（响应体为小 JSON）。
- 实时：生产端填 kind 零新增 DB 往返（各生产端本已持有 session 行）；shared 广播复用既有 workspace fanout 基建，无新协议。
- sweeper 每小时、批量上限（对齐 `SweepChatDraftAttachments` 的 `maxPerTick` 形态 [D-33]）。
- `chat_session` 增列（`kind` 常量默认、可空作者列于 `chat_message`）均不重写表。

## 8. Prompt 采纳影响

**省略**——本 CR 目标仓为 multica，diff 不触及 `skills/shared/crctl/scripts/crctl.mjs` dispatch 分支与 `skills/shared/controlled-shell/rules.json` `protectedPaths.deny`（tools 仓零改动，PRD §7 范围排除）。

## 9. 批准范围

- **scope_in**（本 CR 必须交付）：FR-1–FR-26 / AC-1–AC-32 全量，即：481–490 迁移；`chat_session.kind` 与 shared session 生命周期；Discussion GET/PATCH config/GET messages/POST messages 的 kind 分流与成员门禁；协办触发/无 Issue chat task/回复写回；草稿附件原子绑定；merge-forward `message_ids` 扩展；`Idempotency-Key` 幂等；settings 解绑与投影；实时 kind 感知投递与移出退订；旧容器只读回放；前端 discussion-pane session 身份化与四语文案；`CUSTOM.md` 登记。
- **scope_out**（明确排除）：项目级成员模型（PRD §7 排除项，成员口径=当前 workspace 成员）；Discussion → Issue/CR 升级；历史 comment 全量迁移；Team Agent 配置与发送内核；CR-2026-056 KG-1/KG-2；`agent_task_queue` 模型/Thinking 专用列；`discussion_participant` 表；mobile；`../tools/` 改动；发送框视觉重构。
- **zero_diff**（不得改动的调用点/签名）：`sendProjectChatCore` 全函数（NFR-7）；`ResolveChatConfig`/`ValidateResolvedChatConfig`/`LoadChatCatalogForConfig`/`mergeChatConfigContext`/`SnapshotAgentDefaults` 签名与语义；`LockUnboundDraftAttachments`/`BindUnboundDraftAttachments`/`LinkAttachmentsToChatMessage` 既有查询；`CreateChatTask` 查询本身；`kind=private` 的 `PatchChatSessionConfig`/`SendChatMessage`/`ListChatMessages`/`GetChatSession` 行为（逐行保留）；`EnsureProjectChatSession`（Team Agent 表路径）；`handleDiscussionContainerMentionTrigger`（保留不删）；168h 草稿 sweeper 谓词；legacy merge-forward `comment_ids` 路径与 `invalid_comment_selection`；`Broadcaster` 既有四方法语义与 relay 的既有客户端 fanout 行为（`deliverEnvelope` 仅新增保留 `realtime.control` 类型的控制分支，既有 scope fanout 逐字节不变）。
- **follow_up**（发现但留给后续）：① 项目级成员模型引入后，FR-25 负向契约从 workspace 口径升级（KB 延期清单第 10 项）；② 客户端 scope 订阅落地后，shared 事件从 workspace fanout 迁到 `BroadcastToScope("chat", ...)`（`listeners.go` 现有注释已预留一行切换点）；③ `project_chat_session`（Team Agent）与 `chat_session(kind=project_shared)` 两表并存的长期收敛评估；④ Discussion 会话的主动归档/关闭管理面（本 CR 仅定义权限，不提供入口）；⑤ 幂等记录保留期可配置化（本 CR 固定 24h 阈值，口径见 §4.6 澄清）。

## 10. 既有实现依赖与事实

> 按正文首次出现顺序。repo 均为 `multica`，commit SHA 均为 `be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d`（本 CR requirement worktree HEAD）。
> 注：该 HEAD 为还原提交，树与 main `e8b25259` 逐字节一致（先前 wip 前推已对冲归零），§10 依赖事实不因 SHA 刷新而变。

1. repo: multica
   relative path: server/internal/handler/project_chat.go
   stable symbol/对象: GetProjectDiscussion (L224)、ProjectDiscussionResponse (L215)、L250 对 EnsureProjectDiscussionIssue 的调用
   commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
   依赖结论: GET 现行为即「懒创建隐藏 Issue」，本 CR 的改写对象与响应契约基线
2. repo: multica
   relative path: server/internal/service/project_chat.go
   stable symbol/对象: EnsureProjectDiscussionIssue (L55)、ensureContainerIssue 的 "project-discussion" advisory 前缀与 origin_type='project_discussion' 容器机制
   commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
   依赖结论: GET 解除调用后不得再有其它创建入口；函数保留供存量语义
3. repo: multica
   relative path: server/migrations/033_chat.up.sql
   stable symbol/对象: chat_session 表 L7 `agent_id UUID NOT NULL REFERENCES agent(id) ON DELETE CASCADE`（内联 FK，自动命名 chat_session_agent_id_fkey）；chat_message 基础列
   commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
   依赖结论: 481 转换的唯一目标约束；全量迁移核查确认其后无迁移引用/改写该约束
4. repo: multica
   relative path: server/migrations/436_chat_session_project.up.sql
   stable symbol/对象: chat_session_project_creator_active_unique（谓词 `project_id IS NOT NULL AND status='active'`，不区分 kind）
   commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
   依赖结论: FR-6 必须收窄的现存索引；代码仅注释引用其名（无 ON CONFLICT 按名引用；§2.3 采新名先建再删旧）
5. repo: multica
   relative path: server/migrations/214_chat_session_project.up.sql
   stable symbol/对象: chat_session.project_id（软引用，无 FK）
   commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
   依赖结论: shared session 复用该列；项目删除经 ClearChatSessionProjectByProject 置 NULL
6. repo: multica
   relative path: server/pkg/db/queries/chat.sql
   stable symbol/对象: GetProjectChatSessionForCreator (L12)；GetChatSessionInWorkspace、LockChatSessionInWorkspace（FOR UPDATE，L~40）；ListChatMessagesPage (L1065)；CreateChatTask (L1107, issue_id 恒 NULL)；chat_session_project_creator_active_unique 注释 (L16)
   commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
   依赖结论: 泄漏点收窄对象、会话锁读、分页复用、协办入队 INSERT、索引名引用盘点
7. repo: multica
   relative path: server/internal/handler/project_chat.go + server/internal/service/autopilot.go
   stable symbol/对象: GetProjectChatSessionForCreator 三处调用点（project_chat.go:343/378、autopilot.go:990）
   commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
   依赖结论: 加 `kind='private'` 过滤后三处语义全部保持（均只要 Private Ask）
8. repo: multica
   relative path: server/pkg/db/queries/attachment.sql
   stable symbol/对象: LockUnboundDraftAttachments (L188)、BindUnboundDraftAttachments (L205)、LinkAttachmentsToChatMessage (~L107)、DetachAttachmentsFromUserChatMessageByTask、CountUnboundChatAttachmentsForTask、BindChatAttachmentsToMessage
   commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
   依赖结论: 草稿锁序与既有绑定语义；新查询与其同构且不改动既有查询
9. repo: multica
   relative path: server/internal/service/task.go
   stable symbol/对象: writeChatCompletionOutcome (L5057)
   commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
   依赖结论: FR-12 回复按 task.ChatSessionID 自动写回同 session；仅需补作者列
10. repo: multica
    relative path: server/internal/service/task.go
    stable symbol/对象: mergeChatConfigContext (L1478)、其在 L1559（mention 路径）与 L2572（SendDirectChatMessage）的两处调用
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: chat_config 快照的单一 merge 缝，FR-11 直接复用，不新增第二套
11. repo: multica
    relative path: server/internal/service/task.go
    stable symbol/对象: EnqueueChatTask (L2069)、enqueueChatTaskTx (L2159)、SendDirectChatMessage (L2479) 的事务形态（CreateChatTask+Context、SetChatTaskInputOwnerSelf、提交后通知）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: Discussion 发送事务的结构模板与归因字段参照（priority=2、chat 路径签章）
12. repo: multica
    relative path: server/internal/handler/chat.go
    stable symbol/对象: PatchChatSessionConfig (L858)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: kind 分流的宿主；private 分支逐行保留
13. repo: multica
    relative path: server/internal/handler/chat.go
    stable symbol/对象: SendChatMessage (L955)、gatePublicChatSessionForUser (L306)、ListChatMessages (L1301)、ListChatMessagesPage (L1334)、parseChatMessagesPageParams (L1174)、ChatMessageResponse (L2175)、chatMessageToResponse (~L2217)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 消息/列表入口与门禁现状；kind 分流与 shared 分页对象化的基线；作者字段响应映射宿主（B-AUTHOR-1）
14. repo: multica
    relative path: server/internal/service/chat_config.go
    stable symbol/对象: ResolveChatConfig (L50)、resolveChatConfigValue 的四级优先、ValidateResolvedChatConfig (L88)、LoadChatCatalogForConfig (L125)、ChatConfigSource 枚举（含 agent_default 仅 legacy 语义）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 配置解析/校验单一实现；shared 路径以无效 agentDefault 杜绝 agent_default
15. repo: multica
    relative path: server/internal/handler/project.go
    stable symbol/对象: settings PATCH 分支 (L547 起)、discussion_coordinator 校验分支 (L592–613)、requireWorkspaceRole 门禁 (L549)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: FR-26 写权威入口；现无清除/解绑分支（非字符串即 400），本 CR 新增
16. repo: multica
    relative path: server/internal/service/project_chat_session.go
    stable symbol/对象: EnsureProjectChatSession、ProjectChatSessionAdvisoryPrefix ("project-chat-session")、LockIssueDuplicateKey advisory 用法、SnapshotAgentDefaults、insert-conflict+reselect 模式
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: Discussion ensure 的同构模板；advisory 前缀隔离的依据；Team Agent 表（project_chat_session）与本 CR 表不同
17. repo: multica
    relative path: server/internal/service/project_chat.go
    stable symbol/对象: SendProjectChatMessage、MergeForwardDiscussion (L176)、sendProjectChatCore、buildMergedForwardContent (L492)、commentAuthorDisplayName、错误契约注释（403/409/429/502 映射）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: FR-13 适配对象；内核零改动约束；消息渲染平行函数的结构参照
18. repo: multica
    relative path: server/internal/handler/project_chat.go
    stable symbol/对象: MergeForwardDiscussion handler（comment_ids 校验/去重/容器校验）、writeProjectChatSendError (L589)、PatchProjectChatConfig（owner/admin+三态 PATCH 参照）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: merge-forward 扩展宿主与错误映射复用
19. repo: multica
    relative path: server/internal/util/mention.go
    stable symbol/对象: Mention 结构、ParseMentions (L24)、MentionRe（`mention://agent/<id>` 语法）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: FR-11 @mention Coordinator 检测直接复用现有解析器
20. repo: multica
    relative path: server/internal/handler/comment.go
    stable symbol/对象: handleDiscussionContainerMentionTrigger (L2664)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 旧 comment 触发路径保留不删；新承载不经过它
21. repo: multica
    relative path: server/cmd/server/listeners.go
    stable symbol/对象: chat 事件路由（L253–270 区段：ChatSessionID 非空必须带 ChatRecipientID，SendToUser，缺失丢弃+ERROR 的 fail-closed 语义）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: FR-20 的改造点；private 语义与 fail-closed 缺省必须保持
22. repo: multica
    relative path: server/internal/events/bus.go
    stable symbol/对象: events.Event 的 TaskID/ChatSessionID/ChatRecipientID 字段与其契约注释（生产者必须同时设置、桥层 fail-closed）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 新增 ChatSessionKind 字段的宿主与既有契约边界
23. repo: multica
    relative path: server/internal/handler/daemon.go
    stable symbol/对象: task 流式帧的 chatSessionID/chatRecipientID 解析与 events.Event 发布（L4690–4800 区段）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 生产端 kind 标注改造点（其本已加载 session 行）
24. repo: multica
    relative path: server/internal/handler/handler.go
    stable symbol/对象: publishChat (L747)、requireWorkspaceMember (L923)、requireWorkspaceRole (L943)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 事件发布助手扩参；成员/角色门禁的唯一复用入口
25. repo: multica
    relative path: server/internal/service/task.go
    stable symbol/对象: ChatSessionCreatorID 的四处消费（L6938/L7249/L7327/L7447）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 任务事件生产端 kind 标注的扩展面（辅助函数同时返回 kind）
26. repo: multica
    relative path: server/internal/realtime/hub.go
    stable symbol/对象: MembershipChecker (L23–26)、HandleWebSocket (L775, L803/L835 IsMember)、BroadcastToWorkspace (L566)、SendToUser (L572)、Run() register 自动订阅 workspace+user scope (L321)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: workspace fanout 的成员资格前提；新增按 (user, workspace) 断连的宿主；user-scope 自动订阅是 §4.7 控制帧「持有连接的节点必然消费 user 流」的消费前提（B-REALTIME-1）
27. repo: multica
    relative path: server/internal/handler/workspace_revoke.go + server/internal/handler/subscriber.go + server/internal/handler/autopilot.go + server/pkg/db/queries/member.sql + server/pkg/db/queries/subscriber.sql
    stable symbol/对象: revokeAndRemoveMember (L43)、publishRevocation (L269)、LockSubscriberWrites 锁序（subscriber.sql L27 的 pg_advisory_xact_lock(hashtext(ws), hashtext(user))）；delegated auto-subscribe 路径 subscriber.go:239 / autopilot.go:841 同一把锁；member.sql GetMemberByUserAndWorkspace (L10)/DeleteMember (L24)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 「已被移出 workspace」的挂接点（AC-28/AC-29）；断连在事务提交后执行；B-AUTH-2 的共享串行锁（与 revoke 双方都以它为第一把锁）及事务内成员资格复核的查询宿主
28. repo: multica
    relative path: server/pkg/publicapi/v1/foundation.go
    stable symbol/对象: HeaderIdempotencyKey (L4)、MaxIdempotencyBytes=255 (L6)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: FR-24 头与长度约束的既有基建
29. repo: multica
    relative path: server/internal/handler/file.go
    stable symbol/对象: loadAttachmentForRequest (L728) 及其两处消费 (L650/L1299)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 已发送 shared 附件「非成员 404」的扩展点；草稿上传者门不变
30. repo: multica
    relative path: server/internal/service/chat_draft_attachment_cleanup.go
    stable symbol/对象: SweepChatDraftAttachments（168h、严格边界、maxPerTick）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 幂等 24h sweeper 的模式参照（谓词不改）
31. repo: multica
    relative path: server/pkg/db/queries/issue.sql
    stable symbol/对象: GetProjectDiscussionIssue (L622)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: legacy_issue_id 只读回放查询；无创建副作用
32. repo: multica
    relative path: server/internal/service/discussion_coordinator.go
    stable symbol/对象: ProjectSettingDiscussionCoordinatorID (L22)、RouteDiscussionToTeamAgent (L103)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: coordinator settings key 常量与转投路由的 Discussion 侧适配对象
33. repo: multica
    relative path: packages/core/api/schemas.ts
    stable symbol/对象: ProjectDiscussion/ProjectDiscussionSchema/EMPTY_PROJECT_DISCUSSION (L1400–1416)、parseWithFallback (client.ts:242/862)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: FR-19/NFR-8 的前端契约基线；新 schema 独立定义并硬降级；ChatMessageSchema 作者可空字段扩展点（malformed catch 降级，B-AUTHOR-1）
34. repo: multica
    relative path: packages/views/projects/components/discussion-pane.tsx
    stable symbol/对象: 以 discussion.issue_id 为可写身份的现结构（L80/L90 等）、useIssueTimeline、草稿 key 约定
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: FR-19 重写对象；草稿上传既有机制复用；作者解析/展示与回退宿主（B-AUTHOR-1）
35. repo: multica
    relative path: server/internal/service/project_chat_session.go
    stable symbol/对象: UpdateProjectSettingsWithTeamAgentRebind (L462)（换绑即关旧会话语义）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 决策 D-5 的对照项——Discussion 投影刻意不复制该「关旧建新」语义
36. repo: multica
    relative path: server/cmd/server/router.go
    stable symbol/对象: /api/chat/sessions/{sessionId} 路由块 (L2316–2344)、/api/projects/{id}/chat/merge-forward (L2014)、/api/projects/{id}/discussion (L2022)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 端点挂载现状；本 CR 不新增平行 URL（PRD 契约前言行）
37. repo: multica
    relative path: CUSTOM.md
    stable symbol/对象: 按 CR 里程碑分组、行号稳定 ID、合并核对口径的台账结构
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: FR-21 登记义务的结构基线（登记在代码实施期按其当时结构执行）
38. repo: multica
    relative path: server/migrations/472_project_chat_session.up.sql + server/pkg/db/queries/project_chat_session.sql
    stable symbol/对象: project_chat_session 表与 GetProjectChatSessionByID/LockProjectChatSessionByID
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 口径澄清——Team Agent 会话是独立表，本 CR 零改动，防与 chat_session(kind=project_shared) 混淆
39. repo: multica
    relative path: server/pkg/db/queries/runtime.sql
    stable symbol/对象: ListAgentRuntimes（workspace_id 单参，ORDER BY created_at ASC）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: §4.4 L2 并集 authority 的确定性枚举依据（顺序即扫描序）
40. repo: multica
    relative path: server/internal/service/agent_ready.go
    stable symbol/对象: AgentReadiness (L101) 与 runtimeVerdict（仅依赖 runtime 行的 verdict 原语：online=Available）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: §4.4 L2 ready 过滤复用 verdict 原语，无第二套 readiness 规则；L1 归档 Blocked 判定同源
41. repo: multica
    relative path: server/internal/realtime/broadcaster.go
    stable symbol/对象: Broadcaster interface (L23: BroadcastToScope/BroadcastToWorkspace/SendToUser/Broadcast 四方法，无任何断连控制)、ScopeUser 常量 (L8)
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 基线无服务端断连控制的事实依据（B-REALTIME-1）；DisconnectWorkspaceUser 的扩展宿主（纯新增方法，既有四方法零改动）
42. repo: multica
    relative path: server/internal/realtime/redis_relay.go
    stable symbol/对象: envelope/publishWithID（按-scope 流 XADD）、deliverEnvelope（仅本地客户端 fanout：global/user/default 三分支，无控制分支）、runConsumer 按 hub 订阅回调启停（消费组 "node:{nodeID}" 每节点各收一份）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: 控制信封的载体与消费路径；基线无断连指令的事实依据（B-REALTIME-1）；控制分支为 deliverEnvelope 的唯一新增分支
43. repo: multica
    relative path: server/internal/realtime/sharded_stream_relay.go + server/internal/realtime/relay_lifecycle.go
    stable symbol/对象: ShardedStreamRelay.deliverMessage → deliverEnvelope 共享分支；MirroredRelay 双 primary/mirror 转发（BroadcastToScope/PublishWithID 均双发）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: §4.7 控制帧全 relay 模式覆盖——一个 deliverEnvelope 分支即所有模式消费；镜像模式控制帧幂等重复执行无操作
44. repo: multica
    relative path: server/cmd/server/main.go
    stable symbol/对象: realtime 接线 L405–436（无 REDIS_URL → hub 单节点回退；legacy/dual/sharded 三模式 + DualWriteBroadcaster 外层包装）
    commit SHA: be6426a7c8d93ed58e6a69210e8a3d1d4357fe6d
    依赖结论: §4.7 各模式消费矩阵的穷举依据（部署可能出现的 Broadcaster 形态全列）

## Discussion 显式升级（v0.34 · CR-2026-061）

## Discussion 显式升级（CR-2026-061）技术设计

输入：已审批 PRD v0.3（A 口径）。基线：multica trunk `78e14082` / tools trunk `49c46dd` / docs（knowledge-base）CR 分支含 PRD v0.3 提交 `fc5c3fb` 及后续评审/审批提交。本 SDD 覆盖全部 13 FR、HTTP 契约、AC-13 跨仓消费契约，并逐条处理第 3 轮需求评审的 3 条非阻塞 suggestions（见 §11）。

---

### 0. 术语硬化与基线（Step 2.5 FR-08）

#### 0.1 术语表（只进入数据模型/接口契约且有歧义风险的术语）

| PRD canonical term | 代码别名（Go/TS/sqlc） | 硬化结论 |
|---|---|---|
| 升级（promotion） | `promotion` / `PromoteDiscussion` | 指 Discussion → 工作 Issue 的唯一显式出口，不是 merge-forward（那是转发到 Team Agent） |
| 预建 run（promotion 预建 pipeline run） | `promotion run` / `FindActiveRequirementRunForIssue` | `pipeline_run` 行：`pipeline_id='requirement-authoring'`、`cr_id=NULL`（绑定后为 CR-ID）、`issue_id=目标 Issue`、`status='running'`、`started_by=调用者`。**同一行**在绑定前后复用，不新建 |
| 目标 Issue | `target issue` / 响应 `issue_id` | promotion 创建或查重命中的正式工作 Issue（`origin_type` 不设置任何 Discussion 容器标签，避免与历史 `project_discussion` 混淆） |
| canonical fingerprint（FR-7） | `promotionFingerprint()` | 含 `upgrade_to_cr` 的幂等指纹，作用域 `(workspace,user,scope='discussion_promotion',scope_id=project,key)` |
| 查重键（FR-6） | `dedupe_key`（存于 `context_refs` 条目） | 仅由来源集合（session+message set+attachment set）推导，不含 `upgrade_to_cr`；与 fingerprint 是**两个不同摘要**，防止混淆（PRD FR-6/FR-7 分开定义） |
| 绑定（AC-13） | `BindPromotionRunToCR` / `multica cr bind-promotion-run` | 把预建 run 的 `cr_id` 由 NULL 更新为新 CR-ID 的唯一通道；绑定幂等、仅一次 |
| 来源引用 | `issue.context_refs` 条目 `kind='discussion_promotion'` | 规范化来源集合 + `dedupe_key` + `promoted_by/promoted_at`（+ `pipeline_run_id`） |

代表性边界场景验证：同源先普通升级、后 `upgrade_to_cr=true`（新 key）→ 指纹不同（含 `upgrade_to_cr`）所以 409 不触发；查重命中（dedupe_key 相同）→ 补建 run 并回写 `pipeline_run_id`，至多一条 run。该场景在 §4.3 完整推演。

#### 0.2 语义冲突检查

对照 PRD v0.3 与 multica `78e14082` 逐条核实，**未发现新的阻塞性语义冲突**（v0.2 的 FR-10 冲突已在 A 口径修订中解决）。第 3 轮评审 3 条 suggestions 均为非阻塞项，本 SDD 全部「已处理」（§11），无需退回需求侧。首次 `crctl advance` 前不设停步点。

#### 0.3 既有 CONTEXT.md 沿用

knowledge-base `CONTEXT.md` 与 multica `CONTEXT.md` 若存在均只读沿用；本 CR 不修订。

---

### 1. 架构概览

#### 1.1 模块边界

```text
packages/views/projects/components/discussion-pane.tsx   (多选 + 两个升级入口 UI)
  -> packages/core/api/client.ts promoteDiscussion()      (Idempotency-Key 客户端强制)
  -> POST /api/projects/{projectId}/discussion/promote
       server/internal/handler/promotion.go   PromoteProjectDiscussion
         -> server/internal/service/promotion.go  IssueService.PromoteDiscussion
              -> IssueService.createInTx(...)             [自 Create() 提取的既有事务内核，唯一 Issue 写入路径]
              -> db: promotion.sql (新 sqlc) + issue.sql/chat.sql/idempotency.sql 既有查询
              -> events.Bus (issue:created，提交后)

knowledge-base requirement-register Skill（tools 仓）
  -> crctl register（既有深原语，不改）
  -> multica cr bind-promotion-run <cr-id> --run-id <uuid>     [AC-13 消费]
       server/cmd/multica/cmd_cr.go (新子命令，薄转发)
       -> POST /api/crs/{crID}/bind-promotion-run
            server/internal/handler/cr_bind.go  HandleBindPromotionRun
              -> service/task.go TaskService.BindPromotionRunToCR

server/internal/governance/gate_projection.go                [不改：复用语义，见 §4.5]
```

依赖方向保持 ARCHITECTURE.md §4：handler → service → db；`packages/views` 只经 `core` 访问 API；governance 投影不新增写路径。

#### 1.2 关键流程总览

1. **升级**：成员 POST promote（固定判定顺序）→ 项目级 advisory lock 内「key 冲突检查 → 来源查重 → 创建/补建」单事务提交 → 提交后广播 `issue:created`。
2. **升级为 CR**：`upgrade_to_cr=true` 分支在同一事务追加预建 `pipeline_run` + 首节点 `pipeline_node_run`（无 `agent_task_queue`），响应携带 `run_id`。
3. **CR 注册消费（AC-13）**：knowledge-base `crctl register` 成功拿到 CR-ID 后，requirement-register 经 `multica cr bind-promotion-run` 绑定预建 run（`cr_id` NULL → CR-ID、`cr.shell_issue_id` 同步 CAS、首节点置 `passed`），之后 CR 状态事件投影 `findOrCreateRun` 按 `cr_id` 命中同一行复用。

#### 1.3 涉及仓库

| 仓 | 改动 |
|---|---|
| multica（`resources[].worktreePath` = `C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\multica\requirement\CR-2026-061`） | handler/service/sqlc/CLI/迁移 505–507/前端/测试 |
| tools（`C:\Users\GOBAO\Downloads\AI\AI First Platform\.rayai-worktrees\tools\requirement\CR-2026-061`） | `skills/requirement/requirement-register/SKILL.md` promotion 上下文与绑定步骤（FR-10 配套点）；`crctl.mjs` **零改动** |
| knowledge-base（operational workspace） | 本 sdd.md 与 `_context.md` 导航缓存；不改任何 CR 账本 |

---

### 2. 数据模型

#### 2.1 `issue.context_refs` 条目 schema（新写入语义）

```jsonc
// issue.context_refs 是 JSONB 数组；本 CR 追加的 promotion 条目：
{
  "kind": "discussion_promotion",          // 固定机器可读类型标记
  "session_id": "<小写 UUID>",
  "message_ids": ["<排序去重小写 UUID>"],   // 可为空数组
  "attachment_ids": ["<排序去重小写 UUID>"],
  "dedupe_key": "<sha256 hex>",            // FR-6 查重键，见 §4.1
  "promoted_by": "<调用者 UUID>",
  "promoted_at": "<RFC3339 UTC>",
  "pipeline_run_id": "<UUID>"              // 仅 upgrade_to_cr=true 分支，同事务回写
}
```

- 条目由服务端生成（NFR-5），前端不能提交任意 `context_refs`。
- `message_ids`/`attachment_ids` 排序去重（FR-4）。条目是唯一匹配锚点：查重/回写都按 `dedupe_key` 定位该条目。
- 追加语义：`UPDATE issue SET context_refs = context_refs || $jsonb`（幂等追加到数组尾部），不覆盖既有条目；升级不删除任何历史条目。

#### 2.2 `chat_idempotency` scope 扩展（迁移 505）

- `scope_type` CHECK 增加 `'discussion_promotion'`；`scope_id` 语义 = **project_id**（FR-7 作用域）。
- 复用既有四查询：`InsertChatIdempotencyReservation` / `GetChatIdempotencyByKey` / `FinalizeChatIdempotency` / `DeleteChatIdempotencyByKey`（`idempotency.sql`）。`response_status` 存 201，`response_body` 存完整成功响应 JSON（重放用）。
- 24h 清理（`SweepChatIdempotency`）自动覆盖新 scope，无需新清理器。

#### 2.3 预建 `pipeline_run` / `pipeline_node_run`（复用 451 表结构，新 sqlc INSERT）

| 字段 | 取值 | 依据 |
|---|---|---|
| `workspace_id` | 项目所属 workspace | tenant 隔离 |
| `pipeline_id` | `'requirement-authoring'` | 451 允许任意 pipeline 文本；模板已注册（gate_nodes_gen.go `PipelineIDs.RequirementAuthoring`） |
| `cr_id` | 创建时 **NULL**；绑定后 = 新 CR-ID（同一行） | 451 `cr_id TEXT` 可 NULL（规划类 pipeline 无 CR 的既有语义） |
| `issue_id` | 目标 Issue | 451 `ON DELETE SET NULL`；AC-13 识别键 |
| `status` | `'running'` | CHECK 允许；投影 `findOrCreateRun` 按 `status IN ('running','waiting_approval')` 命中 |
| `started_by` | 调用者 member UUID | 451 `started_by UUID NOT NULL` |
| `inputs` | 来源上下文：`{session_id, message_ids[], attachment_ids[], promoted_by, promoted_at}`（排序去重后） | FR-10；机器可读 |
| `execution_context` | §2.4 注册意图标记 | FR-10；幂等可重放（内容确定性生成） |

首节点 `pipeline_node_run`：`node_id='00000000-0000-0000-0011-000000000001'`（requirement-authoring 模板第 1 节点 requirement-register skill 节点，见 gate_nodes_gen.go `ArchitectureCoreRegistryJSON` 同族常量，ReviewGateNodes/ApprovalGateNodes 已证明该 ID 空间：审批节点 seq5、评审节点 seq4 均已注册）、`ref='requirement-register'`、`kind='skill'`、`seq=1`、`attempt=1`、`status='running'`、`started_at=now()`。不创建 `agent_task_queue` 行。

#### 2.4 `execution_context`（注册意图标记，机器可读 + 幂等可重放）

```json
{
  "intent": "discussion-promotion",
  "expect_bind": true,
  "bind_hint": { "endpoint": "POST /api/crs/{crID}/bind-promotion-run", "cli": "multica cr bind-promotion-run" },
  "source": { "project_id": "<UUID>", "session_id": "<UUID>",
              "message_ids": ["<UUID>"], "attachment_ids": ["<UUID>"] }
}
```

确定性：`project_id` 取 `project.id` 规范小写；`source.*` 与 `inputs` 同一规范化结果。重放时生成的 `run_id` 不参与内容（`run_id` 在行上，不在 JSON 里），因此同输入重放不产生内容漂移。

#### 2.5 新索引（迁移 506/507）与唯一性 guard

- **506 `idx_pipeline_run_promotion_active_issue`**：部分唯一索引
  `ON pipeline_run (workspace_id, issue_id) WHERE pipeline_id='requirement-authoring' AND status IN ('running','waiting_approval')`。
  作用：①「同一目标 Issue 至多一条 requirement-authoring 非终态 run」的 **DB 级保障**，覆盖绑定前（`cr_id IS NULL`）与绑定后（`cr_id=CR-ID`）同一行两个阶段——PRD「任何情况下同一 promotion 至多存在一条 run（始终同一行）」从应用锁升级为约束；②promotion 识别键查询（`workspace_id, issue_id` 前缀）的索引支撑，解决 suggestion-1（现有 `idx_pipeline_run_workspace_status` 弱覆盖）。`issue_id IS NULL` 的普通注册投影 run 不受影响（PG 唯一索引对 NULL 不冲突）。
- **507 `idx_issue_context_refs_gin`**：`CREATE INDEX ... ON issue USING GIN (context_refs jsonb_path_ops)`，支撑 §4.2 的 `@>` 查重。无新表（FR-12 默认路径）。

#### 2.6 迁移清单与 DDL 规范

| 迁移 | 内容 | 说明 |
|---|---|---|
| `505_chat_idempotency_promotion_scope` | 单条 `ALTER TABLE chat_idempotency DROP CONSTRAINT chat_idempotency_scope_type_check, ADD CONSTRAINT chat_idempotency_scope_type_check CHECK (scope_type IN ('discussion_message','merge_forward_messages','discussion_promotion'))` | 一条 ALTER 两动作原子完成，**无约束缺失窗口**；约束名是 PG 默认名 `{table}_{column}_check`，实施时先经 `pg_catalog`/测试夹具确认再 DROP。down：反向回旧枚举（前提：无 `discussion_promotion` 行，见 §13） |
| `506_pipeline_run_promotion_active_unique` | 单语句 `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS idx_pipeline_run_promotion_active_issue ...` | 并发建索引单文件单语句（CLAUDE.md 硬规则）；登记 `cmd/migrate concurrentIndexCleanups`（506 → `idx_pipeline_run_promotion_active_issue`），down 登记 `concurrentDownIndexCleanups` |
| `507_issue_context_refs_gin` | 单语句 `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_issue_context_refs_gin ON issue USING GIN (context_refs jsonb_path_ops)` | 同上登记两表；down `DROP INDEX CONCURRENTLY IF EXISTS` |

迁移号基线：当前最新 **504**，故 promotion 扩展取 **505/506/507**（PRD §1.4 已核实）。三个 up 各有对应 down；down 的数据依赖语义见 §13。

---

### 3. 接口契约

#### 3.1 `POST /api/projects/{projectId}/discussion/promote`

路由：`server/cmd/server/router.go` 项目路由块，紧邻 `GET /discussion` 之后注册（与 merge-forward 同处项目成员路由树）。

**请求**

```jsonc
// 头：Idempotency-Key（必填，≤255B，foundation.go HeaderIdempotencyKey/MaxIdempotencyBytes）
{
  "session_id": "<UUID>",                    // 必填
  "message_ids": ["<UUID>"],                 // 可空数组，无重复 UUID
  "attachment_ids": ["<UUID>"],              // 可空数组，无重复 UUID
  "title": "string ≤200",                    // 可选
  "description": "string ≤10000",            // 可选
  "upgrade_to_cr": true|false                // 可选，缺省 false；类型错误 → 400 invalid_request_body
}
```

**成功响应（201）**

```jsonc
{
  "issue_id": "<UUID>", "issue_number": 123,
  "session_id": "<UUID>",
  "source_refs": { "session_id": "<UUID>", "message_ids": ["<UUID>"], "attachment_ids": ["<UUID>"] },
  "created": true|false,
  "upgrade_to_cr": false,
  "run_id": "<UUID>|null"
}
```

- `created=false` 覆盖重放与查重命中两类；重放 = 存储响应回放且强制 `created=false`（其余字段与首次一致，PRD FR-7）。
- `run_id`：`upgrade_to_cr=true` 且 run 已创建/已存在时非空；查重命中补建后返回同一（唯一）run 的 id；`upgrade_to_cr=false` 恒为 null。

**错误闭包**：完全按 PRD「错误闭包」表实现（错误体 `{code, error}` 经 `writeErrorCode`），实现映射见 §4.4 与 §6 FR-13 行。状态码总集 201/400/403/404/409/500/502，无 200、无 402。

#### 3.2 `POST /api/crs/{crID}/bind-promotion-run`（AC-13 绑定端点，bind-current-task 同族）

- 路由：`r.Post("/api/crs/{crID}/bind-promotion-run", h.HandleBindPromotionRun)`，与 `bind-current-task` 相邻。
- 鉴权：**仅 task token（mat_）**，与 bind-current-task 同族口径（suggestion-2 已处理）：非 task_token → 401 `{"error":"TASK_CONTEXT_REQUIRED"}`；task/agent/workspace 由 auth 中间件服务端戳记，客户端不可指定。
- 请求体：`{"run_id":"<UUID>"}`（唯一输入；issue_id 由 run 行服务端派生，CR-ID 在路径）。

```jsonc
// 200 成功（幂等重放 changed=false）
{ "cr_id": "<CR-ID>", "run_id": "<UUID>", "issue_id": "<UUID>", "changed": true|false }
```

| 场景 | HTTP | code（错误体 `error` 字段） |
|---|---|---|
| 非 task_token | 401 | `TASK_CONTEXT_REQUIRED` |
| 请求体非法 / run_id 非 UUID | 400 | `INVALID_RUN_ID` |
| run 不存在于 token workspace / 非 promotion 形状（`pipeline_id≠requirement-authoring` 或 `issue_id IS NULL`）/ 已终态 | 404 | `RUN_NOT_FOUND` |
| CR 不存在于 token workspace | 404 | `CR_NOT_FOUND` |
| **run 已绑定到其它 CR（二次绑定，固定冲突响应）** | **409** | **`RUN_CR_CONFLICT`** |
| `cr.shell_issue_id` 已被其它 Issue 占用 | 409 | `CR_ISSUE_CONFLICT` |
| 其它失败（事务/审计） | 500 | `CR_BIND_FAILED` |

> **错误体形状（suggestion-2 已处理）**：本端点所有错误行沿用 bind-current-task 同族形状 `{"error":"<code>"}`（`writeJSON(w, ..., map[string]string{"error": ...})` / `writeError`，见 cr_bind.go L36/L61 与 handler.go `writeError`），**不经** `writeErrorCode` 的 `{code,error}` 形状族（那是 §3.1 promotion 端点的形状）。实施期不得误套 writeErrorCode；契约测试按 `{"error":"TASK_CONTEXT_REQUIRED"}` 等固定形状断言。

- **幂等语义**：同一 run + 同一 CR 重放 → 200 `changed=false`，零写入（CAS 判定来自锁内旧值，同 bind-current-task AC-B3 模式）。
- **二次绑定固定响应**（suggestion-2）：run 已绑定到**不同** CR → 409 `RUN_CR_CONFLICT`；绑定到**相同** CR → 幂等成功。两种结果确定、可测试。
- 绑定事务内同时：`pipeline_run.cr_id` NULL→CR-ID、`cr.shell_issue_id` NULL→run.issue_id（既有 `BindCrShellIssueIfNull` 复用）、首节点 `pipeline_node_run`（seq1）置 `passed`（§4.5）、`activity_log` 审计行（action=`promotion_run_bound`）。任一失败整体回滚。

#### 3.3 `multica cr bind-promotion-run <cr-id> --run-id <uuid>`（CLI 薄命令）

- `server/cmd/multica/cmd_cr.go` 新增子命令：只中继 mat_ task token 与 `{run_id}` 到 3.2 端点，透传结构化结果，无业务判断、无账本写入、无 body 构造（同 `bind-current-task` 实现契约）。`--output json|table`。
- knowledge-base 侧调用形态：`multica cr bind-promotion-run {cr_id} --run-id {run_id}`（requirement-register Skill 在 `crctl register` 成功后执行）。

#### 3.4 `IssueResponse.context_refs` 暴露（AC-7 可读性）

- Go：`IssueResponse` 增加 `ContextRefs []IssueContextRef \`json:"context_refs,omitempty"\``，`issueToResponse` 从 `i.ContextRefs` JSONB 解析（解析失败→空数组+日志，不回退 500——详情端点本身已有 source-context 的 500 先例，但 context_refs 是附加展示字段，按 API 兼容规则降级为空更安全，见 §7）。
- 其中 `IssueContextRef = { kind?, session_id?, message_ids?, attachment_ids?, pipeline_run_id?, promoted_by?, promoted_at? }`。
- TS：`packages/core/api/schemas.ts` `IssueSchema` 增 `context_refs`（`z.array(...).catch([])`），兼容旧后端缺字段（API 兼容规则：desktop 旧版本前端容忍新增字段，新前端对旧后端回退空数组）。`PromotionResultSchema` 新 schema + `parseWithFallback` + malformed-response 测试（CLAUDE.md API Compatibility）。

---

### 4. 关键算法与流程

#### 4.1 两个摘要（fingerprint 与 dedupe_key 分离）

```go
// service/promotion.go，纯函数，单元测试覆盖（含大小写、重复、乱序输入）
func canonicalUUIDs(ids []pgtype.UUID) []string          // 小写排序去重
func promotionFingerprint(projectID, sessionID pgtype.UUID, msg, att []pgtype.UUID, upgradeToCR bool) string
    // = SHA256(canonical JSON, 固定键序):
    // {"projectId":..,"session_id":..,"message_ids":[..],"attachment_ids":[..],"upgrade_to_cr":bool}
func promotionDedupeKey(sessionID pgtype.UUID, msg, att []pgtype.UUID) string
    // = SHA256({"session_id":..,"message_ids":[..],"attachment_ids":[..]}) —— 不含 projectId/upgrade_to_cr（FR-6）
```

`title`/`description` 不参与任何摘要（FR-7）。两摘要用途：fingerprint → `chat_idempotency.fingerprint`（同 key 冲突判定）；dedupe_key → `context_refs` 条目（跨 key 同源查重）。

#### 4.2 来源查重 SQL（`promotion.sql`）

```sql
-- name: FindPromotionDuplicateIssue :one
SELECT * FROM issue
WHERE workspace_id = $1
  AND context_refs @> jsonb_build_array(jsonb_build_object('dedupe_key', $2::text))
LIMIT 1;
```

JSONB 包含语义：右对象 `{"dedupe_key":K}` 匹配任何含同值该键的条目（条目可有额外字段），507 GIN 索引加速。命中后条目内 `pipeline_run_id` 是否已存在决定「直接返回」还是「补建」分支。

#### 4.3 `PromoteDiscussion` 主流程（service/promotion.go）

```
输入: workspaceID, projectID, sessionID, callerID, messageIDs[], attachmentIDs[],
      title*, description*, upgradeToCR, idempotencyKey   (* 可选，超限已在 handler 拒绝)

前置（handler，零写入，固定顺序 = PRD 判定顺序 1-6）:
 1) 请求形态校验（400 类，§3.1 request 表 + FR-3 形状项）
 2) projectId 解析与存在性（400/404）
 3) 成员门禁 getWorkspaceMember（403 forbidden_promotion）
 4) Issue 创建权限：CheckIssueCreateCapacity（issue_limit 既有口径，见 D-6）→ 超限 403 forbidden_promotion
 5) session 解析：GetActiveProjectSharedSession(ws,project) 且 == 请求 session_id，否则 404 chat_session_not_found
 6) 来源选择：每个 message 经 GetChatMessageInWorkspace + 会话 Join 校验属于该 session；
    每个 attachment 经 ListAttachmentsForPromotion（attachment JOIN chat_message ON chat_session_id）校验绑定该 session 消息；
    message/attachment 至少其一非空

事务（qtx）:
 7) qtx.LockIssueDuplicateKey(ctx, "project-discussion-promotion|{ws}|{project}")   // 项目级 advisory lock（新前缀，D-4）
 8) 锁内成员复核 GetMemberByUserAndWorkspace（鉴权复核在事务内、首次写入前，§13）→ 403
 9) InsertChatIdempotencyReservation(scope='discussion_promotion', scope_id=projectID, key, fingerprint)
    - 成功（本请求持有 key）→ 继续
    - ON CONFLICT → GetChatIdempotencyByKey:
        winner.Fingerprint != fingerprint        → 409 idempotency_key_reused（零写入，优先级先于查重）
        winner.ResponseBody != nil               → 重放：解析存储响应 + created=false，返回（不新建任何东西）
        winner.ResponseBody == nil               → 接管：上次执行中断，本请求以既有 reservation 行继续
10) dedupe 查重 FindPromotionDuplicateIssue(dedupe_key):
    - 未命中 → 创建分支：
        runID := upgradeToCR ? dbid.NewV7() : 无效
        entry := 构建 §2.1 条目（upgradeToCR 时含 pipeline_run_id=runID）
        s.createInTx(ctx, qtx, IssueCreateParams{..., AllowDuplicate:true, ProjectID:projectID,
                              ContextRefs: [entry], PromotionRun: upgradeToCR ? plan(runID, inputs, execCtx) : nil})
        // createInTx 复用既有 Issue 写入路径：duplicate guard（AllowDuplicate 跳过标题查重）、
        // status 校验、project 校验、labels、AllocateIssueNumber（限容权威判定）、
        // NextTopPosition、CreateIssue、AppendIssueContextRefs、CreatePipelineRun+CreatePipelineNodeRun
    - 命中 → 查重分支：
        issue := 既有 Issue；source_refs 从命中条目还原
        if upgradeToCR && 条目无 pipeline_run_id:
            runID := dbid.NewV7()；CreatePipelineRun+CreatePipelineNodeRun；
            SetIssueContextRefPipelineRun(issue, dedupe_key, runID)
            // 若并发补建触发 506 唯一冲突 → FindActiveRequirementRunForIssue 重读既有 run 并采用其 id（不报错）
        else if upgradeToCR: runID := 条目已有 pipeline_run_id
11) 组装响应 result（created 按分支）；FinalizeChatIdempotency(key, 201, body=result)（同一事务）
12) Commit

提交后（post-commit，失败不回滚已提交数据，NFR-4）:
  publishIssueCreated(issue, ..., opts)  // 既有 issue:created 事件；创建分支才发布
  captureCreatedAnalytics(...)
```

**并发收敛推演**（AC-5/AC-8 依赖）：同项目同源并发 → 步骤 7 串行化；第二个事务进入后先命中同 key（若同 key）或 dedupe 查重（异 key）；`upgrade_to_cr` 并发时第二个事务拿到的是**同一行 run**（条目已含 `pipeline_run_id`，或 506 唯一冲突后重读）。绑定与补建不可能交错：绑定只对已存在 run 发生，而已存在 run 意味着其创建事务已把 `pipeline_run_id` 写入条目（同一事务）——补建分支只会出现在「条目无 run」时，此时不存在可绑定的 run。

#### 4.4 错误闭包实现映射（FR-13）

| PRD 场景 | HTTP/code | 实现点 |
|---|---|---|
| JSON 非法 / `upgrade_to_cr` 类型错误 | 400 `invalid_request_body` | `json.Decoder` 失败或 `*bool` 解出 null（非指针 bool 无法区分缺省/错型，故用 `*bool`） |
| `projectId` 非 UUID | 400 `invalid_project_id` | `parseUUIDOrBadRequest`（路径参数） |
| project 不存在 | 404 `project_not_found` | `GetProjectInWorkspace` → ErrNoRows |
| session 形状错误 / 数组非法 / 双空 / 重复 | 400 `invalid_promotion_selection` | 形状校验器（纯函数 + 单测） |
| title/description 超限或非字符串 | 400 `invalid_promotion_title` / `invalid_promotion_description` | 形状校验器 |
| Idempotency-Key 缺失 / 非法 | 400 `idempotency_key_required` / `invalid_idempotency_key` | handler 头部校验（≤ `MaxIdempotencyBytes`，空白判定 `strings.TrimSpace`） |
| 非成员 | 403 `forbidden_promotion` | 步骤 3/8 |
| 无 Issue 创建权限（容量门禁） | 403 `forbidden_promotion` | 步骤 4 + 事务内 `AllocateIssueNumber` 的 `IssueLimitReachedError` 映射（D-6） |
| session 不存在/跨项目/非 project_shared/非 active | 404 `chat_session_not_found` | 步骤 5 |
| 消息/附件不属于该 session | 400 `invalid_promotion_selection` | 步骤 6 |
| 同 key 异指纹 | 409 `idempotency_key_reused` | 步骤 9 |
| 锁/死锁/连接/事务失败 | 500 `internal_error` | 事务错误捕获（deferred Rollback，零残留） |
| run 创建失败（含 506 冲突后重读也失败、execution_context 序列化失败） | 502 `pipeline_run_create_failed` | upgrade 分支任何 run/节点写入错误 → 整事务回滚 |
| 其它未预期 | 500 `internal_error` | 默认分支 |

500/502 均整体回滚（事务内无部分提交），原 key 重试幂等安全（同指纹重放或同 reservation 接管）。

#### 4.5 绑定与投影协作（suggestion-3 已处理）

```
BindPromotionRunToCR（service/task.go，同族 bind-current-task）:
  tx 开始
  1) FindUnboundPromotionRunByID(runID, workspace) FOR UPDATE   // 锁 run 行
       ErrNoRows → RUN_NOT_FOUND
       run.CrID.Valid && run.CrID != crID → RUN_CR_CONFLICT（固定冲突）
       run.CrID.Valid && == crID    → changed=false 幂等返回
  2) LockCrForCrBind(workspace, crID) → CR_NOT_FOUND
       cr.ShellIssueID.Valid && != run.IssueID → CR_ISSUE_CONFLICT
  3) BindPromotionRunIfNull(run.cr_id = crID)      // CAS：WHERE cr_id IS NULL
     BindCrShellIssueIfNull(cr.shell_issue_id = run.issue_id)   // 既有查询复用
     MarkPipelineNodePassed(run, node_id='...0011...0001')      // 首节点 seq1 running→passed
     CreateActivity(action='promotion_run_bound')               // 同事务审计
  commit；changed 时 publishCRUpdated（既有 cr:updated）
```

**与 `gate_projection` 的协作语义（不改投影代码）**：

- **注册完成前**（run 未绑定）：首节点 `status='running'` = 「注册意图在途」。投影对无 `cr_id` 的 run 无写入（`findOrCreateRun` 按 `cr_id` 查，查不到也不新建——只有 cr 状态事件才触发投影）。
- **绑定时**：`cr_id` 置 CR-ID + 首节点置 `passed`（注册事实落账）——同一事务，与 `cr.shell_issue_id`/审计原子。
- **绑定后**：CR 进入 `requirement-reviewing` 的状态事件 → `projectGateTransition` → `findOrCreateRun(ws, crID, 'requirement-authoring')` **命中绑定后的同一行**（status='running'）→ 复用，不新建；`upsertNodeRunning` 只写审批门节点（seq5），不触碰 seq1；review 事件 `applyReview` 只写 seq4 节点行。→ 满足 AC-13「pipeline_run 行数不增」。
- **护栏**：若 knowledge-base 违约在绑定前推进 `requirement-reviewing`，投影会按 `cr_id` 新建一条 `issue_id=NULL` 的 run（投影无权猜测 Issue）。该违约由 AC-13 在 knowledge-base 侧硬阻止（绑定失败即注册技术失败，不得推进）；SDD 将「绑定完成前不得推进 requirement-reviewing」列为本设计的不变量（§9 scope_in）。
- **违约后果与恢复路径（suggestion-1 已处理）**：投影新建行 `cr_id=CR-ID、pipeline_id='requirement-authoring'、status='running'`（`pipelineForStatus` 把 requirement-reviewing 映射到 requirement-authoring）会先占用 456 部分唯一索引 `(workspace_id,pipeline_id,cr_id)` 的槽位；此时 506 不冲突（506 谓词要求 `issue_id` 非空，投影行 `issue_id IS NULL`），但后续绑定的 `UPDATE pipeline_run SET cr_id=CR-ID WHERE id=<预建 run>` 将撞 456 唯一约束（SQLSTATE 23505）→ 绑定事务整体回滚，端点返回 500 `CR_BIND_FAILED`。恢复路径：按 `pipeline_id='requirement-authoring' AND cr_id=<CR-ID> AND issue_id IS NULL` 定位投影新建行，人工确认后删除（该行无任何绑定/Issue 语义挂靠），再重试绑定（CAS 幂等，重试安全）；绑定成功后再推进 CR 状态。推演依据见 §12 #31（456 谓词）与 §12 #4（pipelineForStatus 映射）。
- 未消费的预建 run：保持 `cr_id=NULL, status='running'`，不影响任何既有路径；过期清理不在本 CR（PRD 范围排除）。

#### 4.6 默认标题/描述生成（FR-4/AC-3）

- `title` 缺省：`Discussion promotion — {project.name} {YYYY-MM-DD HH:mm}`（服务端生成；project 名从 `GetProjectInWorkspace` 行读取）。
- `description` 缺省：来源消息摘要（每条 `作者: 摘要（≤120 rune）`，最多 5 条，超出加 `…`；复用 `chatMessageAuthorDisplayName` 与既有 merge-forward 摘要思路），并附来源标注块（session/消息/附件计数）。
- 两者只在创建分支生效；查重命中/重放不覆盖（FR-6）。

---

### 5. 技术选型与替代方案

#### D-1 promotion 单事务 reservation+finalize（vs merge-forward 的 reservation/kernel/finalize 三事务）

- Context：merge-forward 用三事务是因为 kernel（sendProjectChatCore）自带事务不可包裹；promotion 的全部副作用（Issue、context_refs、幂等记录、run 行）都在本服务事务内，PRD/NFR-4 明确要求同一事务。
- Decision：promotion 的 reservation、副作用、finalize 全部在一个事务。
- Consequences：崩溃窗口语义比 merge-forward 更干净（无「已提交未 finalize」窗口）；同 key 重试走「同 fingerprint + NULL body 接管」分支，不需要 `DeleteChatIdempotencyByKey` 释放路径（该查询仍被 merge-forward 使用，零改动）。

#### D-2 查重键存储与匹配（vs 逐元素全等比较 / 新建 promotion 表）

- Alternatives：A) SQL 逐元素比较 `jsonb_array_elements` 全等——O(n) 且不可索引；B) 新建 `discussion_promotion` 表——PRD FR-12 默认禁止。
- Decision：条目内置 `dedupe_key` + `@>` 包含匹配 + GIN 索引（507）。`dedupe_key` 是 PRD「条目至少含」集合之外的服务端附加字段，不改变 PRD 语义（FR-6 查重键 = 规范化来源集合的摘要形式）。
- Consequences：查重与审计同源（条目即审计）；`@>` 语义对并发键一致（摘要确定性）；代价是一条 GIN 索引（`issue` 表宽 JSONB，写入成本可接受，见 §7）。

#### D-3 绑定通道 = 服务端端点 + `multica cr` 薄命令（vs crctl 内嵌 Multica 调用）

- Alternatives：A) crctl register 直接写 Multica DB——跨仓越权，违背 authority 拆分；B) requirement-register 自行拼 HTTP——失去同族审计与错误闭包。
- Decision：`POST /api/crs/{crID}/bind-promotion-run`（task-token）+ `multica cr bind-promotion-run` 薄命令，完全复刻 bind-current-task 族（handler 零业务判断、服务端派生身份、CAS 幂等、activity_log 审计）。
- Consequences：knowledge-base 侧只有一条 shell 调用增量；错误码固定可重试；绑定审计在 Multica 侧可查。

#### D-4 独立 promotion 项目级锁前缀（vs 复用 discussion-session 锁）

- Context：send/GET/配置路径共用 `project-discussion-session|ws|project`；promotion 只读 session 行、不写，与发送事务无共享行冲突。
- Decision：新锁键 `project-discussion-promotion|ws|project`（同一 `LockIssueDuplicateKey` 原语，hashtextextended）。同项目 promotions 互斥（收敛到一次创建）；不把 promotion 与消息发送串行化。
- Consequences：并发窗口仅限同项目 promotion（这正是需要串行化的集合）；锁键表在 §7 固化，禁止重排。

#### D-5 首节点完成信号由绑定事务置 `passed`（vs 投影自动完成）

- Alternatives：A) 投影在首次 requirement-authoring 事件时补写 seq1——投影写节点状态越界（投影只写门/评审节点，且绑定未发生前投影根本找不到该 run）；B) 节点永留 running——状态失真。
- Decision：绑定事务置 `passed`（§4.5）。
- Consequences：预建节点生命周期 = 「running（在途）→ passed（绑定）」，与 run 行 `cr_id` 赋值同事务原子；投影零改动。

#### D-6 步骤 4 的「Issue 创建权限」口径 = 成员 + 既有容量门禁，映射 403

- Context：PRD FR-8 步骤 4 要求「沿用现有 Issue 权限口径，不新造权限模型」；现状 = 所有成员可创建 Issue，唯一硬门禁是 `ResolveIssueCountPolicy`/`CheckIssueCreateCapacity`/`AllocateIssueNumber`（`issue_limit.go`，超限现有路径映射 HTTP 402 `issue_limit_reached`）。
- Decision：promotion 前置 `CheckIssueCreateCapacity`（预检）+ 事务内 `AllocateIssueNumber`（权威）双查；失败统一映射 PRD 错误闭包的 403 `forbidden_promotion`（PRD 闭包表无 402，属 PRD 明示映射）。
- Consequences：不新造权限模型（AC-6 可测：limit 夹具 → 403）；与普通 CreateIssue 的 402 差异属端点级映射选择，在错误闭包表已固定，reviewer 可按 PRD 验收。

#### D-7 创建内核提取 `createInTx`（vs 另开 Issue 写入路径 / 回调钩子）

- Context：FR-2 禁止另建 Issue 写入路径；NFR-4 要求同一事务。
- Decision：把 `IssueService.Create` 的事务体机械提取为 `createInTx(ctx, qtx, p, opts)`；`Create` 保持原签名行为（Begin→createInTx→Commit→事件）；`PromoteDiscussion` 在同一事务内调用 `createInTx`，并通过 `IssueCreateParams` 两个新增可选字段（`ContextRefs json.RawMessage`、`PromotionRun *PromotionRunPlan`）注入 promotion 专属副作用。run id 在 Go 侧预生成（`dbid.NewV7()`），故条目可在创建前携带 `pipeline_run_id`。
- Consequences：唯一 Issue 写入路径不变；`IssueService.Create` 的既有调用方与测试全部不变（zero_diff 条目）；新字段零值时行为与今天逐字节一致。

#### D-8 506 部分唯一索引覆盖绑定前后两阶段（suggestion-1 已处理）

- Context：456 索引只覆盖 `cr_id IS NOT NULL`；预建 run 在 `cr_id IS NULL` 阶段无唯一性保障；promotion 识别键查询没有匹配索引。
- Decision：§2.5 的 506 索引（`workspace_id, issue_id` + pipeline/status 谓词）同时覆盖绑定前后同一行，并作为识别键查询索引。
- Consequences：跨项目/跨 Issue 互不冲突；普通注册 run（issue_id NULL）不受影响；projection 新建 run（issue_id NULL）不冲突。

---

### 6. FR 到技术实现映射与 AC 级输出合同

#### 6.1 FR 映射

| FR | 技术方案条目 |
|---|---|
| FR-1 只有显式升级才创建工作 Issue | 无任何懒创建调用改动；唯一新增 Issue 写入是 `PromoteDiscussion` 的创建分支（经 `createInTx`）；Discussion GET/发送/协办路径零改动（AC-1 以既有测试 + 新增断言覆盖） |
| FR-2 升级入口契约 | §3.1 端点 + `promotion.go` handler + `router.go` 注册；Issue 创建复用 `createInTx`（D-7），无第二写入路径 |
| FR-3 来源选择校验 | handler 形状校验（UUID 数组、去重、双空、标题/描述边界）+ 步骤 5/6 归属校验（`GetChatMessageInWorkspace`、`ListAttachmentsForPromotion`）；`session_id` 必须等于 `GetActiveProjectSharedSession` 结果 |
| FR-4 创建 Issue 并写入来源引用 | §2.1 条目 + `AppendIssueContextRefs`（创建分支同事务）；`pipeline_run_id` 回写见 §4.3；默认标题/描述 §4.6 |
| FR-5 原消息附件保持原归属 | promotion 事务对 `chat_message`/`attachment`/`chat_session` **零 UPDATE/DELETE/INSERT**（唯一读）；AC-4 以升级前后行全等断言 |
| FR-6 同源唯一 | `dedupe_key` + §4.2 查询 + 项目级锁串行；`title`/`description` 只在创建分支生效 |
| FR-7 幂等键 | `promotionFingerprint`（§4.1）+ `discussion_promotion` scope（505）+ reservation/replay/takeover/409 四分支（§4.3 步骤 9） |
| FR-8 权限边界 | 固定顺序 1–6 + 事务内成员复核（§4.3/§4.4）；403 口径 = CR-B 项目路径成员门禁；步骤 4 = D-6 |
| FR-9 可回溯 | §3.4 `context_refs` 暴露 + 前端「来自 Discussion」入口（跳转 DiscussionPane 并定位 session） |
| FR-10 升级为 CR | §2.3/§2.4 预建 run + 同事务 + 502 闭包 + 唯一 run 语义（506）+ 不写 CR 账本（Multica 零 `_backlog.yml`/`cr.md` 写入路径，AC-8 grep 断言）+ AC-13 消费契约（§4.5/§3.2/§3.3） |
| FR-11 前端交互 | §3.4 + discussion-pane 多选/两入口/结果链接/失败保留选择（复用 merge-forward 多选状态与错误分支模式） |
| FR-12 不新增表 | 无 `discussion_promotion` 表（迁移仅 CHECK 扩展 + 2 索引）；AC-10 断言 `server/migrations/` 无该命名迁移 |
| FR-13 可区分错误与零残留 | §4.4 错误闭包表逐条实现 + 前端按表恢复动作 |

#### 6.2 AC 级输出合同（每项：设计落点 / 可观测结果 / 可达性）

```text
AC-1
设计落点：promotion 是唯一新增 Issue 写入路径；Discussion GET/send/协办/merge-forward 代码零改动
可观测结果：打开 Discussion、发送、附件、协办后 issue 表行数不变（既有 origin 排除查询 + 新增断言）；promotion 201 后行数 +1
可达性：merge-forward 的 issue 写入是 Team Agent 容器（origin_type='project_chat'），与 promotion 目标 Issue 不重叠；断言按 workspace+origin 过滤

AC-2
设计落点：handler 形状校验器 + 步骤 5/6 归属校验
可观测结果：只选消息 / 只选附件 / 混合 → 201；空选择、重复 UUID、草稿附件（chat_message_id IS NULL）、他 session 消息 → 400 invalid_promotion_selection；非法 JSON → invalid_request_body；projectId 非 UUID → invalid_project_id；session_id 非 UUID → invalid_promotion_selection；标题/描述超限 → 各自 400；全部零写入（issue/context_refs/chat_idempotency 行数不变）
可达性：校验在事务外、任何写之前完成（§4.3 固定顺序），夹具可逐类注入

AC-3
设计落点：§2.1 条目构建（AppendIssueContextRefs）+ §4.6 默认标题/描述
可观测结果：context_refs 含 kind/session_id/排序去重数组/promoted_by/promoted_at/dedupe_key；缺省 title 含项目名与时间、description 含摘要
可达性：创建分支与条目写入同一事务（AppendIssueContextRefs 失败 → 整体回滚）；条目内容由纯函数构建，单测覆盖排序去重

AC-4
设计落点：FR-5 零写不变量
可观测结果：升级前后 chat_message 行数/内容、attachment.chat_session_id/chat_message_id 全等；Discussion 消息流渲染不变（既有组件测试）
可达性：promotion 事务内无任何针对 chat_* 表的写语句（结构测试 grep 断言：promotion.sql/service 不出现 UPDATE/DELETE chat_message|attachment|chat_session）

AC-5
设计落点：§4.1 摘要 + §4.3 四分支 + 项目级锁
可观测结果：同源两次 → 第二次 created=false 同 issue_id；同 key 同指纹 → 回放 created=false；同 key 异指纹（含先普通后升级）→ 409 零写入；换新 key upgrade → 同 Issue + 至多补建一条 run（run_id 一致）；缺 key/空 key/超长 key → 400 三码；并发同源（goroutine 夹具）→ 一个 Issue
可达性：reservation 唯一冲突路径有 pgx.ErrNoRows 分支；并发夹具走真实 DB（testutil），锁串行可观测（第二个事务返回 created=false）

AC-6
设计落点：§4.3 固定顺序 1–6 + 事务内成员复核
可观测结果：非成员/被移出 → 403 forbidden_promotion（不泄漏 session 存在性：顺序先于 session 解析）；无创建权限（limit 夹具）→ 403；session 不存在/跨项目/非 project_shared/归档 → 404 chat_session_not_found；project 不存在 → 404 project_not_found；全部零写入
可达性：固定顺序无分支依赖后续步骤结果（同输入唯一响应）；归档 session 经 GetActiveProjectSharedSession（status='active' 谓词）自然 404

AC-7
设计落点：§3.4 IssueResponse.context_refs + 前端来源入口
可观测结果：GET issue 响应可解析 session/message/attachment 引用；Issue 详情页展示「来自 Discussion」入口并可跳回 Discussion
可达性：context_refs 在 detail 响应透出（issueToResponse 解析 JSONB）；前端 schema fallback [] 保证旧后端不炸（兼容规则）

AC-8
设计落点：§2.3/§4.3 创建分支 + 502 闭包 + 506 唯一索引
可观测结果：upgrade 成功后同事务出现 pipeline_run（cr_id NULL、issue_id、started_by、inputs/execution_context）+ 首节点 + 无 agent_task_queue 行；响应 run_id；同 key 重放同 run_id；同源新 key 第二次不新建（补建一次）；注入夹具失败 → 502 pipeline_run_create_failed 且 issue/context_refs/chat_idempotency/pipeline_run/pipeline_node_run 零残留，原 key 重试成功且不重复；Multica 无 KB 账本写入调用（grep 零命中）
可达性：run 行与节点行与 Issue 同一事务（createInTx 内注入）；506 索引使「并发补建」收敛为唯一冲突重读；失败注入点 = CreatePipelineNodeRun 返回错误夹具

AC-9
设计落点：discussion-pane.tsx 多选与两入口 + 结果/失败状态
可观测结果：可选择消息与附件并触发「转为工作 Issue」「升级为 CR」；未配置 Coordinator 的 Discussion 同样可用（promotion 不依赖 Coordinator，FR-11）；成功后 Issue 链接可见、Discussion 内容不变；失败保留选择可重试
可达性：入口渲染不依赖 coordinator_agent_id 非空；成功回调只导航/展示，不重载 Discussion 流

AC-10
设计落点：迁移 505/506/507（无新表）
可观测结果：server/migrations/ 无 discussion_promotion 命名迁移；无 discussion_promotion 表（测试夹具查询 pg_catalog）
可达性：FR-12 默认路径成立（§2.5/§4.2 验证 context_refs+锁+幂等满足需求），无需走 FR-12 例外路径

AC-11
设计落点：§4.4 逐类映射 + 事务回滚
可观测结果：400/403/404/409/500/502 代表夹具各自零残留；错误体 code 与状态一一对应；500/502 后原 key 重试成功且 Issue/run 数不增；前端按错误类型保留选择或提示重试
可达性：所有写发生在单一事务；错误路径在 commit 前返回（deferred Rollback）；重试走同 fingerprint 重放/接管分支

AC-12
设计落点：locales 四语 + parity.test.ts + 兼容零改动
可观测结果：新增文案 en/ja/ko/zh-Hans 对称，parity 全绿；旧 project_discussion 只读回放不回归；CR-B Discussion GET/发送测试全绿
可达性：只新增 UI key，不改既有 key 与语义；旧容器路径代码零改动

AC-13（跨仓）
设计落点：§3.2 端点 + §3.3 CLI + tools requirement-register SKILL 绑定步骤 + §4.5 投影协作
可观测结果：requirement-register 按 issue_id+pipeline_id 定位 cr_id IS NULL、status=running 的 run 并绑定新 CR-ID（同一行复用；绑定幂等、仅一次——二次绑定异 CR → 409 RUN_CR_CONFLICT）；绑定后 CR 进入 requirement-reviewing 时投影复用同一 run（pipeline_run 行数不增）；绑定失败 → 注册技术失败、registration_key 幂等重试安全；普通注册不定位不绑定
可达性：定位键有 506 索引支撑；绑定 CAS 在锁内旧值判定（同 bind-current-task 模式）；tools 侧集成测试 + multica 侧投影断言（cr 状态事件夹具：绑定后注入 requirement-reviewing 事件 → 投影 findOrCreateRun 命中同一行）
```

#### 6.3 AC 反查结论

逐条从 AC 反查正文：AC-8 的「至多补建一次」依赖 §4.3 并发推演（补建与绑定不可交错）+ 506 唯一索引兜底；AC-13 的「行数不增」依赖 §4.5 投影按 `cr_id` 命中的既有逻辑（gate_projection.go `findOrCreateRun`）。权限、状态、空值、过滤与事件顺序均不与 PRD 明文冲突；未发现不可达目标场景。

---

### 7. 安全与性能考量

#### 7.1 安全控制点

- 固定判定顺序防泄漏：成员门禁先于 session 解析（非成员拿不到 session 存在性，与 CR-B 口径一致）。
- `context_refs` 只写服务端生成的规范化条目（NFR-5）；请求体不含任何可注入 `context_refs` 字段。
- 绑定端点 task-token 强制（401 fail-closed）；run/CR 全部按 token workspace 谓词校验（跨租户 404 而非存在性泄漏）。
- 事务内鉴权复核：promotion 在锁内、首次写入前复核 `GetMemberByUserAndWorkspace`；绑定端点的 run 行谓词自带 workspace（tenant 不变量 SQL 层保证，ARCHITECTURE.md 硬不变量 1）。
- 摘要算法无歧义：小写 UUID 规范化杜绝大小写变体绕过指纹/查重；`dedupe_key` 与 `fingerprint` 分离杜绝「先普通升级再同 key 升级」绕过（指纹含 `upgrade_to_cr` → 必 409，PRD 明示）。
- `writeErrorCode` 固定 `{code, error}` 形状（无内网细节泄漏）。

#### 7.2 性能

- 锁：`LockIssueDuplicateKey`（hashtextextended advisory xact lock）作用域为单项目；promotion 是低频用户动作，锁持有 = 单事务时长；与 Discussion 发送锁前缀分离（D-4）不互相排队。
- 索引：506 支撑识别键点查（workspace_id+issue_id 前缀）；507 GIN `jsonb_path_ops` 支撑 `@>` 查重（`context_refs` 每行条目数通常为个位数，写入放大可接受）。507 与既有 `issue_properties_gin` 模式一致（并发建索引 + cleanup 登记）。
- 查询：查重/归属校验均为 PK/索引点查 + `= ANY(uuid[])`；消息摘要构建最多 5 条截断（默认描述生成 O(选数) 封顶）。
- 重放路径零业务查询（直接解 `response_body`），省去重放时的归属校验。

#### 7.3 边界条件

- 消息/附件上限：PRD 未设上限；实施沿用 merge-forward 的 50 条 cap 作为防御（`mergeForwardMaxComments` 同值新常量 `promotionMaxItems=50`，超限 400 `invalid_promotion_selection`）——PRD 未禁止、属防御性边界，记入 scope_in。
- `context_refs` 解析失败：detail 响应降级空数组 + 日志（不 500），符合 API 兼容规则；服务端写侧从不产生不可解析内容。
- 旧 `project_discussion` 容器 Issue：promotion 只面向 shared session（FR-3 session 校验），旧容器不受影响。
- 空 `message_ids` + 空 `attachment_ids` → 400（FR-3）。
- `upgrade_to_cr` 与 Coordinator 配置无关：无 Coordinator 的项目 session 存在（InsertProjectSharedSession 允许 `agent_id=NULL`），promotion 照常。

---

### 8. Prompt 采纳影响

**结论：本节不适用（可省略），评审按省略处理。**

核验：本 CR 的 diff 不触及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支（crctl register/advance 等命令面零变更；binding 走 `multica cr bind-promotion-run` 薄命令与 HTTP 端点），也不触及 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（git 白名单零变更）。因此无「应改为调用新增子命令的 skill 清单」需要登记。requirement-register SKILL.md 的修改是**新增**调用步骤（`multica cr bind-promotion-run`），不是把 crctl 已接管的事改回手工操作，不构成 prompt 采纳缺口。

---

### 9. 批准范围（契约）

#### scope_in（本 CR 必须交付）

- multica：`POST /api/projects/{projectId}/discussion/promote` 全链路（handler/service/sqlc/错误闭包/幂等/查重/预建 run）；`POST /api/crs/{crID}/bind-promotion-run` + `multica cr bind-promotion-run` CLI；迁移 505/506/507（含 down、concurrentIndexCleanups/concurrentDownIndexCleanups 登记）；`IssueResponse.context_refs` 暴露；前端 client/schemas/discussion-pane/Issue 详情来源入口 + 四语文案 + parity；FR-1..FR-13 对应测试（AC-1..AC-12）。
- tools：`skills/requirement/requirement-register/SKILL.md` promotion 上下文（可选输入：issue_id+run_id，缺失按普通注册）与绑定步骤（`crctl register` 成功后 `multica cr bind-promotion-run`；失败=注册技术失败、`registration_key` 幂等重试、绑定完成前不得推进 requirement-reviewing）；tools 侧注册集成测试（AC-13）。
- knowledge-base：本 sdd.md 落盘与 `_context.md` 导航缓存刷新（随本 CR 工作流提交）。

#### scope_out（明确排除）

- 自动升级（任何定时/事件驱动）；原消息/附件移动删除复制；Multica 内 CR 注册/状态机/`_backlog.yml` 写入；历史 `project_discussion` comment 升级；Discussion 多主题/多 Agent 参与者模型与 `discussion_participant` 表；`discussion_promotion` 表（FR-12 例外路径未触发）；`agent_task_queue` 新列；Team Agent/Private Ask 内核改动；发送框重构；mobile；未消费预建 run 的过期/清理策略；把 `/compact` 当普通消息。
- `crctl.mjs`、`controlled-shell/rules.json`、`gate_projection.go`、`crsync.go` 的任何改动（suggestion-3 以「不改投影、契约协作」处理）。

#### zero_diff（不得改动的调用点/签名/行为）

- `IssueService.Create` 对既有调用方的公开行为与签名（内部提取 `createInTx` 后逐字节等价；新增的 `IssueCreateParams.ContextRefs`/`PromotionRun` 零值下无任何行为变化）。
- `sendProjectChatCore`、`MergeForwardDiscussion`（含 message/comment 双臂与 idempotency 三事务协议）、`EnsureProjectDiscussionSession`/`EnsureProjectDiscussionIssue`、`GetProjectDiscussion`、`CreateIssue` HTTP 行为。
- `chat_idempotency` 既有两个 scope 的记录语义与 24h 清理；`idempotency.sql` 四个既有查询的签名。
- 456/457 索引与 451 表结构；`findOrCreateRun`/`upsertNodeRunning`/`markNodePassed`/`applyReview` 投影 SQL 与语义。
- `bind-current-task` 端点/CLI/服务行为（新端点同族但独立，不触碰其分支）。
- `LockIssueDuplicateKey` 原语与既有锁键字符串（新前缀独立新增）。

#### follow_up（发现但留给后续 CR）

- 未消费 promotion 预建 run 的过期/清理/对账策略（含 cr_issue 绑定后 run 状态与 Issue 关闭的联动）。
- promotion 条目在 Issue 编辑/删除路径上的保留策略（Issue 删除时 context_refs 随行删除，审计靠历史事件——如需独立审计表，另开 CR）。
- `upgrade_to_cr` 后 requirement 注册入口的一键引导（前端从升级结果直达注册流程的深度集成）。
- promotion 选择上限的正式产品定义（本期防御性 50 条 cap）。

---

### 10. SDD-CLOSE 关闭记录（PRD 延后项逐项关闭）

- **SDD-CLOSE-01 `execution_context` 字段形状（PRD：「字段形状由 SDD 定，必须机器可读且幂等可重放」）**：已关闭 → §2.4。生产（§4.3 步骤 10）、存储（`pipeline_run.execution_context` JSONB）、传输（行内 JSON，无独立传输）、消费（§3.2 端点不读它；requirement-register 读取 promotion 上下文来自升级响应/Issue 条目而非解析 execution_context——消费路径为「可选输入」，兼容降级层 = 缺失时普通注册）逐层判定，关闭成立。
- **SDD-CLOSE-02 绑定端点与鉴权（PRD：「端点与鉴权由 SDD 设计」）**：已关闭 → §3.2/§3.3（task-token 同族、错误闭包、幂等/CAS、CLI）。生产（服务端派生身份）、传输（HTTP JSON）、消费（multica CLI → requirement-register）、兼容降级（任务无 token 环境 → 401，注册按技术失败停止，不降级直写）逐层覆盖。
- **SDD-CLOSE-03 首节点注册完成前的状态语义（suggestion-3）**：已关闭 → §4.5（running=在途 / 绑定置 passed / 投影复用不新建 / 违约护栏）。
- **SDD-CLOSE-04 默认标题/描述（FR-4：「未提供时服务端生成默认值」）**：已关闭 → §4.6。
- **SDD-CLOSE-05 事件通知提交后发出（FR-10/NFR-4）**：已关闭 → §4.3（commit 后 publishIssueCreated/captureCreatedAnalytics；失败不回滚已提交数据；升级为 CR 不新增事件类型）。
- **SDD-CLOSE-06 `context_refs` 响应暴露（FR-9/AC-7）**：已关闭 → §3.4（Go additive 字段 + TS schema fallback + malformed 测试）。
- **SDD-CLOSE-07 AC-13 knowledge-base 消费流程**：已关闭 → §4.5/§3.2/§3.3 + tools SKILL 增量（§9 scope_in）。
- **SDD-CLOSE-08 补建 run 与 `pipeline_run_id` 回写（FR-10 同源不同 key）**：已关闭 → §4.3 查重分支（`SetIssueContextRefPipelineRun` 按 `dedupe_key` 定位条目合并字段，同事务）+ 506 冲突重读。
- **SDD-CLOSE-09 错误闭包逐类实现点**：已关闭 → §4.4 表。

无未关闭项；`review-tech-design` 无需标记待办。

---

### 11. 第 3 轮需求评审 3 条 suggestions 的处理

| # | suggestion | 处置 | 落点 |
|---|---|---|---|
| 1 | 预建 run 识别键的索引设计（`idx_pipeline_run_workspace_status` 弱覆盖） | **已处理**：新增 506 部分唯一索引 `idx_pipeline_run_promotion_active_issue ON pipeline_run(workspace_id, issue_id) WHERE pipeline_id='requirement-authoring' AND status IN ('running','waiting_approval')`，同时承担「识别键点查索引」与「同一 Issue 至多一条非终态 run（绑定前后两阶段）」双重职责（D-8） | §2.5、§4.3、D-8 |
| 2 | AC-13 绑定端点沿用 bind-current-task 同族鉴权口径，并明确二次绑定的固定冲突响应 | **已处理**：绑定端点仅接受 task token（401 `TASK_CONTEXT_REQUIRED`，与 bind-current-task 完全同族）；二次绑定固定响应 = 绑定到不同 CR → 409 `RUN_CR_CONFLICT`；同 CR 重放 → 200 `changed=false` 幂等（CAS 锁内旧值判定，同 AC-B3 模式） | §3.2、§4.5 |
| 3 | 首节点 `pipeline_node_run` 在 CR 注册完成前的状态推进语义与 gate_projection 协作 | **已处理**：预建窗口内首节点 `status='running'`=「注册意图在途」；绑定事务同事务置 `passed`（投影不写 skill 节点，故完成信号由绑定端承担）；绑定后投影 `findOrCreateRun` 按 `cr_id` 命中同一行复用、`upsertNodeRunning`/`applyReview` 只写 seq5/seq4 节点不触碰 seq1；KB 侧「绑定完成前不得推进 requirement-reviewing」列为硬不变量，违约路径与护栏在 §4.5 明示 | §4.5、D-5、§9 |

#### 11.1 第 1 轮技术评审 3 条 suggestions 的处理（本次回修）

| # | suggestion | 处置 | 落点 |
|---|---|---|---|
| 1 | §4.5 违约护栏补明后果（投影 run 占用 456 槽位 → 绑定 23505 冲突 500 `CR_BIND_FAILED`）与恢复路径 | **已处理**：§4.5 新增「违约后果与恢复路径」条目（456 谓词 + pipelineForStatus 映射推演；恢复 = 定位 `issue_id IS NULL` 投影行人工确认删除后幂等重试） | §4.5、§12 #4/#31 |
| 2 | §3.2 错误表 401 行实际错误体 `{"error":"TASK_CONTEXT_REQUIRED"}`（bind-current-task 同族），与 promotion `{code,error}` 不同族 | **已处理**：§3.2 表后新增错误体形状注记（全表 `{"error":...}` 同族，不经 writeErrorCode；测试按固定形状断言） | §3.2、§12 #15/#16 |
| 3 | `ArchitectureCoreRegistryJSON` 与 `CreateActivity` 纳入清单或明确归属 | **已处理**：分别并入 §12 #10（gate_nodes_gen.go 符号）与 §12 #29（activity.sql 独立条目） | §12 #10/#29 |

---

### 12. 既有实现依赖清单（按正文首次出现顺序）

> v1.1（第 1 轮 review-tech-design 回修）：8 项漏列事实按正文首现顺序补入并全量重排为 35 项；#13 拆分为 handler/service 与 db queries 两条（现 #16/#17）；suggestion-3 的 `ArchitectureCoreRegistryJSON`/`CreateActivity` 分别并入 #10/#29；`rules.json`、`idx_pipeline_run_workspace_status`、`requirement-authoring.pipeline.json` 等正文事实一并锚定。

```text
1. repo: multica
   relative path: server/internal/service/issue.go
   stable symbol/对象: IssueService.Create / IssueCreateParams.AllowDuplicate / IssueCreateOpts.BroadcastPayload / publishIssueCreated / captureCreatedAnalytics / issueguard.LockAndFindActiveDuplicate
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: createInTx 提取的源（§1.1 唯一 Issue 写入路径的既有内核）；事件发布复用；promotion 以 AllowDuplicate=true 关闭标题查重（查重权威归 dedupe_key）

2. repo: tools
   relative path: skills/requirement/requirement-register/SKILL.md
   stable symbol/对象: crctl register 深原语（registration_key 幂等、CAS_CONFLICT 重跑续跑语义）
   commit SHA: 49c46dd9d77c0e7a5efb519c1cf8485692774f26
   依赖结论: AC-13 在注册成功后追加绑定步骤（§1.1 模块边界）；深原语本身零改动

3. repo: multica
   relative path: server/cmd/multica/cmd_cr.go
   stable symbol/对象: crBindCurrentTaskCmd / newAPIClient / cli.PrintJSON/PrintTable
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: bind-promotion-run 薄命令复刻同族实现（§3.3）

4. repo: multica
   relative path: server/internal/governance/gate_projection.go
   stable symbol/对象: findOrCreateRun（按 (workspace_id, cr_id, pipeline_id) 查 status IN ('running','waiting_approval')，无则新建）/ upsertNodeRunning / markNodePassed / applyReview / pipelineForStatus（requirement-reviewing/requirement-approved → PipelineIDs.RequirementAuthoring）
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: AC-13「投影复用同一 run 不新建」成立的前提（绑定后按 cr_id 命中）；pipelineForStatus 映射是 §4.5 违约后果推演的依据；本 CR 不改投影

5. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: register 深原语入口（--registration-key/--target-spec-id 校验）
   commit SHA: 49c46dd9d77c0e7a5efb519c1cf8485692774f26
   依赖结论: 绑定不进入 crctl 命令面（走 multica CLI），本节仅证明「不改」的边界（§8）

6. repo: multica
   relative path: server/pkg/db/queries/idempotency.sql
   stable symbol/对象: InsertChatIdempotencyReservation / GetChatIdempotencyByKey / FinalizeChatIdempotency / DeleteChatIdempotencyByKey
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: promotion 幂等四分支直接复用（新 scope），不需要新幂等表或查询

7. repo: multica
   relative path: server/internal/service/chat_idempotency_cleanup.go（L17 func）+ server/pkg/db/queries/idempotency.sql（L42 SweepChatIdempotency :execrows；L46 DELETE FROM chat_idempotency WHERE created_at < $1）
   stable symbol/对象: SweepChatIdempotency(ctx, q, cutoff)（service）+ db SweepChatIdempotency
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: 24h 清理按 created_at 全 scope 清理（无 scope_type 谓词），505 新增 'discussion_promotion' 行自动纳入清理，无需新清理器（§2.2）

8. repo: multica
   relative path: server/migrations/501_chat_idempotency.up.sql / 502 / 503 / 504
   stable symbol/对象: chat_idempotency 表 + CHECK scope_type('discussion_message','merge_forward_messages') + PK + created_at 索引
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: 505 扩展 CHECK 枚举；PK 约束名 chat_idempotency_pkey 是 ON CONFLICT 仲裁目标，扩展不得改名

9. repo: multica
   relative path: server/migrations/451_aifirst_pipeline_runs.up.sql
   stable symbol/对象: pipeline_run（cr_id TEXT NULL、issue_id UUID SET NULL、inputs/execution_context JSONB、started_by NOT NULL、status CHECK）/ pipeline_node_run（UNIQUE(run_id,node_id,attempt)、kind CHECK）/ idx_pipeline_run_workspace_status（workspace_id, status）
   commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
   依赖结论: 预建 run 行与首节点行完全落在既有 schema 内（§2.3），无 DDL 变更；idx_pipeline_run_workspace_status 即 suggestion-1 指涉的弱覆盖索引（无 issue_id 前缀），506 补齐识别键点查

10. repo: multica
    relative path: server/internal/governance/gate_nodes_gen.go
    stable symbol/对象: PipelineIDs.RequirementAuthoring（L15）/ ApprovalGateNodes["requirement"]（seq5）/ ReviewGateNodes["requirement"]（seq4）/ ArchitectureCoreRegistryJSON（L57，architecture-core registry 节点 id 空间常量，生成源声明于文件头）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 首节点 node_id 与门/评审节点 id 空间共存不冲突（seq 1/4/5 不同 id）；ArchitectureCoreRegistryJSON 证明同族 registry 常量维护该 id 空间（§2.3）

11. repo: tools
    relative path: pipeline-templates/requirement-authoring.pipeline.json
    stable symbol/对象: nodes[0].id = 00000000-0000-0000-0011-000000000001 / ref requirement-register / kind skill（seq=1 首节点）
    commit SHA: 49c46dd9d77c0e7a5efb519c1cf8485692774f26
    依赖结论: §2.3 首节点 node_id 的生成源（gate_nodes_gen.go 文件头声明生成源为 tools pipeline-templates），预建首节点与模板第 1 节点对齐

12. repo: multica
    relative path: server/cmd/migrate/main.go
    stable symbol/对象: concurrentIndexCleanups / concurrentDownIndexCleanups 登记表与总登记测试
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 506/507 必须登记，否则 `TestEveryConcurrentUpBuildHasCleanup` 类测试失败

13. repo: multica
    relative path: server/cmd/server/router.go
    stable symbol/对象: 项目路由树（GET /discussion、POST /chat/merge-forward 注册处）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: promotion 与 bind-promotion-run 路由注册位置

14. repo: multica
    relative path: server/pkg/publicapi/v1/foundation.go
    stable symbol/对象: HeaderIdempotencyKey / MaxIdempotencyBytes(255)
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 请求头常量与长度上限

15. repo: multica
    relative path: server/internal/handler/handler.go
    stable symbol/对象: writeErrorCode（{code,error}）/ writeError（{error}）/ writeJSON / parseUUIDOrBadRequest / parseUUIDSliceOrBadRequest / requireUserID / getWorkspaceMember
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: promotion 端点错误体（writeErrorCode）与解析/成员门禁辅助函数；writeError 是绑定端点 {error} 形状族（§3.2 形状注记）

16. repo: multica
    relative path: server/internal/handler/cr_bind.go + server/internal/service/task.go
    stable symbol/对象: HandleBindCurrentTask（X-Actor-Source=task_token 门禁，401 {"error":"TASK_CONTEXT_REQUIRED"}）/ BindCurrentTaskToCR / activity_log 审计模式 / publishCRUpdated
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 绑定端点/服务的同族模板（token 校验、CAS、冲突码、审计、刷新事件）；401 错误体形状与 bind-current-task 一致（§3.2 已注明）

17. repo: multica
    relative path: server/pkg/db/queries/agent.sql
    stable symbol/对象: LockCrForCrBind（L1128）/ BindCrShellIssueIfNull（L1146）/ LockAgentTaskForCrBind（L1100）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 绑定事务的 cr 行锁 CAS 与 shell_issue_id 复用的既有查询（§4.5 步骤 2/3），直接复用不新建

18. repo: multica
    relative path: server/internal/handler/issue.go
    stable symbol/对象: IssueResponse / issueToResponse / loadIssueForUser / GetIssue（L2225 起）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: context_refs 当前未透出（issueToResponse 无该字段），本 CR additive 暴露（§3.4）

19. repo: multica
    relative path: packages/views/projects/components/discussion-pane.tsx + packages/core/api/client.ts + packages/core/api/schemas.ts
    stable symbol/对象: DiscussionPane 多选/MergeForwardPreviewDialog 模式、mergeForwardDiscussion()（Idempotency-Key 客户端强制）、ProjectDiscussionSchema、parseWithFallback
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 前端入口复用既有面板与客户端模式；新 schema 走 parseWithFallback + malformed 测试

20. repo: multica
    relative path: server/internal/service/issue_limit.go
    stable symbol/对象: CheckIssueCreateCapacity（L67，只读预检）/ ResolveIssueCountPolicy（L34，policy 决议）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: D-6 步骤 4 预检口径依据（与事务内 AllocateIssueNumber 权威判定双查）；403 forbidden_promotion 映射的既有口径来源（普通 CreateIssue 映射 402 issue_limit_reached 是既有行为，promotion 按 PRD 闭包映射 403）

21. repo: multica
    relative path: server/internal/service/discussion_session.go
    stable symbol/对象: DiscussionSessionAdvisoryPrefix / chatSessionKindProjectShared / discussionIdempotencyScopeMessage / GetActiveProjectSharedSession 消费
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: session kind/active 判定口径与锁前缀命名风格；promotion 不占用 discussion-session 锁（D-4）

22. repo: multica
    relative path: server/pkg/db/queries/chat.sql
    stable symbol/对象: GetActiveProjectSharedSession（L1723，kind='project_shared' AND status='active' 唯一）/ GetChatMessageInWorkspace（L1748，workspace 谓词经 session JOIN）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: FR-3/FR-8 的 session 与消息归属校验查询，直接复用

23. repo: multica
    relative path: server/pkg/db/queries/attachment.sql
    stable symbol/对象: ListAttachmentsByChatMessage / BindDraftAttachmentsToChatMessage（attachment.chat_message_id 列语义）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 附件「已绑定 session 消息」判定（新增 promotion 专用 JOIN 查询，语义同 ListAttachmentsByChatMessage）

24. repo: multica
    relative path: server/pkg/db/queries/issue.sql
    stable symbol/对象: LockIssueDuplicateKey（pg_advisory_xact_lock(hashtextextended)）、CreateIssue、AllocateIssueNumber（issue_limit 服务）、FindActiveDuplicateIssue、CreateIssueWithOrigin
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 项目级锁原语、Issue 创建事务内核（D-7 提取自 Create）、AllowDuplicate 跳过标题查重、容量权威判定

25. repo: multica
    relative path: server/pkg/db/queries/member.sql
    stable symbol/对象: GetMemberByUserAndWorkspace（L15）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: §4.3 步骤 8 / §13.4 事务内鉴权复核查询（锁内、首次写入前，与并发撤销串行）

26. repo: multica
    relative path: server/internal/service/project_chat.go
    stable symbol/对象: projectChatSessionAdvisoryKey / LockIssueDuplicateKey 调用先例 / ErrIdempotencyKeyReused / mergeForwardMessageFingerprint
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 锁键先例与 409 语义先例（§4.3 步骤 9 idempotency_key_reused 同族）；promotion 使用新前缀但同原语（D-4）

27. repo: multica
    relative path: server/pkg/dbid/dbid.go
    stable symbol/对象: NewV7()（L51）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: runID Go 侧预生成，条目在创建前携带 pipeline_run_id（§4.3 步骤 10 / D-7）

28. repo: multica
    relative path: server/pkg/db/queries/project.sql
    stable symbol/对象: GetProjectInWorkspace（L8）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: §4.4 404 project_not_found 映射（ErrNoRows）与 §4.6 默认标题项目名读取（同一查询）

29. repo: multica
    relative path: server/pkg/db/queries/activity.sql
    stable symbol/对象: CreateActivity（L29）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: §4.5 绑定事务审计行（action='promotion_run_bound'）的既有写入查询

30. repo: multica
    relative path: server/internal/service/project_chat.go
    stable symbol/对象: chatMessageAuthorDisplayName（L739 调用 / L760 定义）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: §4.6 默认描述摘要的作者显示名复用，无需新实现

31. repo: multica
    relative path: server/migrations/456_pipeline_run_architecture_active_unique.up.sql
    stable symbol/对象: idx_pipeline_run_architecture_active_cr（(workspace_id,pipeline_id,cr_id) WHERE cr_id IS NOT NULL AND status IN ('running','waiting_approval')）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 绑定后（cr_id 非空）的防重复由 456 与投影 findOrCreateRun 双重保障；506 补齐 cr_id IS NULL 阶段（D-8）；§4.5 违约后果（456 槽位占用 → 绑定 23505 冲突）的推演依据

32. repo: multica
    relative path: server/migrations/192_issue_properties_gin_index.up.sql
    stable symbol/对象: idx_issue_properties_gin（ON issue USING GIN (properties jsonb_path_ops)）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: 507（context_refs GIN jsonb_path_ops + 并发建索引单文件单语句 + cleanup 登记）与既有模式一致（§7.2）

33. repo: multica
    relative path: server/internal/handler/project_chat.go
    stable symbol/对象: MergeForwardDiscussion（message_ids 臂的成员门禁、Idempotency-Key 校验、选择校验、409 映射）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: promotion handler 的校验顺序与错误映射先例；mergeForwardMaxComments=50 作为防御 cap 同值（§7.3）

34. repo: multica
    relative path: server/pkg/db/queries/chat.sql
    stable symbol/对象: InsertProjectSharedSession（L1731）
    commit SHA: 78e14082845f7fb19f33a356169349b07042c04b
    依赖结论: agent_id=NULL 时无 Coordinator 的 project_shared session 依然可建（481 起合法）——§7.3「promotion 与 Coordinator 配置无关」边界声明的依据

35. repo: tools
    relative path: skills/shared/controlled-shell/rules.json
    stable symbol/对象: protectedPaths（L28，deny 列表始于 L30；git 三元组白名单 + forbiddenFlags 的单一事实源）
    commit SHA: 49c46dd9d77c0e7a5efb519c1cf8485692774f26
    依赖结论: §8「不触及」判定与 §9 scope_out 边界的唯一事实源（本 CR 零变更）
```

无待核实依赖（以上 35 项均在 `78e14082`/`49c46dd` HEAD 上逐项核实；8 项补列、#16/#17 拆分与 3 条 suggestions 采纳项按第 1 轮评审 blocker/suggestions 完成）。

---

### 13. 数据/schema 变更与写路径鉴权完整性

#### 13.1 回滚（down）与数据依赖语义

| 变更 | down | 数据依赖 / 部分状态语义 |
|---|---|---|
| 505 CHECK 扩展 | 单条 `ALTER TABLE ... DROP CONSTRAINT chat_idempotency_scope_type_check, ADD CONSTRAINT ... CHECK (scope_type IN ('discussion_message','merge_forward_messages'))` | 前置：表内无 `discussion_promotion` 行（该行 24h 清理器会在一个保留窗口内自然消失；down 时若仍存在，ALTER 验证失败即回滚安全，**不静默删数据**——执行者需先确认保留窗口已过或按审批清理） |
| 506 部分唯一索引 | `DROP INDEX CONCURRENTLY IF EXISTS idx_pipeline_run_promotion_active_issue`（登记 concurrentDownIndexCleanups 的 down 清理钩子） | 无数据依赖；down 后失去唯一性兜底但应用锁仍工作（降级语义明示） |
| 507 GIN 索引 | `DROP INDEX CONCURRENTLY IF EXISTS idx_issue_context_refs_gin` | 无数据依赖；down 后查重回全表扫描（正确性不变） |

#### 13.2 无约束缺失窗口

- 505 用一条 `ALTER TABLE ... DROP CONSTRAINT ..., ADD CONSTRAINT ...` 原子完成（PG 对同一 ALTER 的多个 action 原子应用），不存在「CHECK 缺失」中间态。
- 506/507 是纯索引（非约束变更），应用锁 + 既有约束在索引构建期间持续生效；并发构建失败由 `concurrentIndexCleanups` 无效索引清理钩子兜底（MUL-5999/MUL-6288 机制，本 CR 登记即接入）。

#### 13.3 DDL 规范

- 新关系不加外键（CLAUDE.md 硬规则）：`pipeline_run.cr_id` 绑定用应用校验（CR 行存在性经 `LockCrForCrBind`），`issue_id` 沿用 451 既有 `ON DELETE SET NULL`（不加新 FK）。
- 所有新索引单语句单文件 `CREATE INDEX CONCURRENTLY` + migrate 登记（§2.6）。
- 不新建表、不以内联方式创建约束绕过迁移（505 的 CHECK 重建是显式迁移 DDL，且实施时经 `pg_catalog` 校验约束名）。

#### 13.4 写路径鉴权完整性

- **promotion**：固定顺序 1–6 全部零写入；事务内、首次写入前复核成员行（`GetMemberByUserAndWorkspace`）——与并发撤销串行（成员撤销路径持成员行锁，复核在 promotion 事务内读最新提交态）；容量门禁的权威判定（`AllocateIssueNumber`）在 Issue 行写入前、同一事务内。
- **bind-promotion-run**：task-token 在中间件验签（服务端戳记身份，客户端不可设）；run/CR 全部查询携带 token workspace 谓词；CAS 冲突检查与写入在锁内同一事务，任一失败整体回滚（含审计行，同 bind-current-task BLOCK-③ 模式）。
- 两者均无「先写后鉴权」路径；错误路径零残留由单事务保证（§4.3/§4.4）。

---

### 14. 测试设计

#### 14.1 multica Go 测试（`server/internal/handler/*_test.go` + `server/internal/service/*_test.go`，testutil/dbfx 夹具）

- 纯函数：`promotionFingerprint`/`promotionDedupeKey`/形状校验器（大小写、乱序、重复、`upgrade_to_cr` 差异矩阵）。
- handler 契约：AC-2（选择矩阵）、AC-5（重放/409/查重/并发）、AC-6（权限顺序与零写入）、AC-8（同事务 run/节点、无 agent_task_queue、502 夹具零残留、原 key 重试）、AC-11（逐类错误夹具）。
- service：createInTx 提取后既有 `IssueService.Create` 测试全绿（zero_diff 回归）；查重命中补建与 506 冲突重读（唯一索引竞态夹具）。
- 绑定：`BindPromotionRunToCR` 全错误码矩阵（401/400/404/409×2/幂等重放/审计行）；投影协作集成（绑定后注入 requirement-reviewing/review 事件 → `pipeline_run` 行数不增、seq5/seq4 节点正常投影、seq1 保持 passed）。
- 迁移：505 后新 scope 可插入；约束名断言；506/507 的 cleanup 登记测试（既有 total-invariant 测试自动覆盖）。

#### 14.2 前端测试

- `packages/core/api/schemas.ts`：`PromotionResultSchema` malformed-response 测试；`IssueSchema.context_refs` fallback。
- `packages/views/projects/components/discussion-pane.*.test.tsx`：多选、两入口、成功链接、失败保留选择（AC-9）。
- `packages/views/locales/parity.test.ts`：四语新 key 全绿（AC-12）。

#### 14.3 tools 侧测试（AC-13）

- requirement-register 集成测试：promotion 上下文存在 → 注册成功后调用绑定端点（fake/mock `multica` CLI 或受控集成夹具）→ 断言绑定幂等与「绑定完成前不推进」；无 promotion 上下文 → 不调用绑定（行为不变）。

#### 14.4 验证命令

```text
multica: cd server && go test ./internal/handler/ ./internal/service/ ./internal/governance/ ./cmd/migrate/ -count=1
前端: pnpm test --filter 相关包 + pnpm exec playwright test（讨论 pane 冒烟）
tools: 对应 SKILL 集成测试脚本
```

---

### 附：审查要点速览

1. promotion 唯一 Issue 写入路径 = `createInTx`（FR-2/NFR-4），无第二路径。
2. fingerprint 与 dedupe_key 是两个摘要，用途分离（FR-6/FR-7）。
3. 506 索引使「同一目标 Issue 至多一条 requirement-authoring 非终态 run」成为 DB 约束（绑定前后同一行）。
4. 绑定端点 = bind-current-task 同族（task-token/CAS/审计/固定冲突码），投影零改动即复用（AC-13）。
5. 迁移 505/506/507 全部满足并发索引单文件单语句 + 登记 + down 数据依赖语义。
6. 3 条 suggestions 全部「已处理」（§11），无未关闭的 PRD 延后项（§10）。
7. §12 既有实现依赖清单 v1.1 回修后 35 项，按正文首现顺序、全部绑定 repo/path/symbol/结论/commit SHA；第 1 轮技术评审 3 条 suggestions 亦全部「已处理」（§11.1）。
