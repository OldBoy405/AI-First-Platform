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

