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

## Team Agent 和 Private Ask 发送框 UI 优化（v0.35 · CR-2026-062）

## 1. 架构概览

### 1.1 目标与边界

将 Team Agent（`project-team-agent-chat.tsx`）与 Private Ask（`project-private-ask.tsx`）项目聊天发送框的布局与视觉语言对齐普通非项目聊天（`chat-input.tsx` 的 `ChatInput`/`ChatInputCore` + `chat-column.ts`），不改任何业务语义。

**改动面**（代码实施全部落在 multica 仓 `packages/views/`；治理台账 `multica/CUSTOM.md` 为仓库纪律 #10 强制 sidecar（见表格末行与 §9），不承载产品代码语义；本 CR 不新增/不修改 server、API、迁移、数据模型、store）：

| 文件 | 改动性质 | 内容 |
|---|---|---|
| `packages/views/chat/components/chat-input.tsx` | 修改（`ChatInputCore` 仅） | wrapper（外层）采用 `CHAT_GUTTER`；surface（内层）采用 `CHAT_COLUMN` + 与 `ChatInput` 一致的 chrome；底部工具栏由 absolute 改为 flow 布局（见 §4）；`SubmitButton` 调用补传 `ariaLabel`/`stopAriaLabel`；采纳 `ChatInputProps` 既有 `allowSubmitWhileRunning` 字段（签名不变，见 §3.2/§4.2） |
| `packages/views/chat/components/chat-column.ts` | 只读复用 | 不修改，复用 `CHAT_GUTTER`/`CHAT_COLUMN` |
| `packages/views/projects/components/project-team-agent-chat.tsx` | 修改 | composer wrapper 对齐（横幅区迁入「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层块）；`project-chat-model-row` 独立行及其 testid 锚点**一并移除**（§9 移除清单第 2 项，无替换锚点——断言改用内部四个 testid 位于 `project-chat-composer` 子树；内部 testid 随 `leftAdornment` 原样保留，见 §9 testid 保留/移除/替换清单），Model/Thinking 控件经 `leftAdornment` 进底部工具栏（只读值带 sr-only 类别标签）；`TeamAgentStreamView` 根容器改为「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层 DOM；新增运行中停止路径（§4.3.1/D-7：`sentTaskId`/`sentIssueId` + 任务时间线（task-runs）与 queue items 双源活动性，覆盖 running） |
| `packages/views/projects/components/project-private-ask.tsx` | 修改 | composer wrapper 对齐（pending-message 迁入「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层块）；`private-ask-model-row` 独立行及其 testid 锚点一并移除（§9 移除清单第 1 项，替换锚点为新 `private-ask-model-picker`），控件经 `leftAdornment` 进底部工具栏（带 sr-only 类别标签）；停止路径（`pendingTaskId → api.cancelTaskById`）原样不动 |
| `packages/views/projects/components/project-chat-panel.tsx` | 修改（一行类名） | `ModePane` 根加 `@container`（容器感知 gutter 的前提，见 §4.1） |
| `packages/views/projects/components/project-queue-bar.tsx` | 修改（最小） | 根 `px-4` 移除，内部内容改为「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层 DOM，与消息列/发送框边缘对齐（禁止单元素合并，见 §4.1 规则 5） |
| `packages/views/projects/components/project-chat-composer-layout-diff.md` | 新增 | 差异说明文档（完成标志交付物，见 §5.6/SDD-CLOSE-04） |
| `CUSTOM.md`（multica 仓根） | 修改（治理台账） | 按仓库纪律 #10 登记本 CR 新增/修改文件台账（编号顺延、原因含 CR 编号与 TASK）；无产品代码语义（governance sidecar，§9 scope_in 受控条目） |
| 组件测试与 e2e | 修改/新增 | 见 §6.9 与 AC 映射 |

**不动**：`ChatInput`（全局 composer）渲染结构与 props 签名、`ChatInputCore` props 签名、`SubmitButton`、`ChatAddMenu`、`ModelPicker`/`ThinkingPicker` 组件本体、draft adapter 接口、`useProjectChatStore`、`PATCH /chat/config` 端点、server 全部代码。

### 1.2 依赖图

```text
project-chat-panel.tsx (ModePane, 加 @container)
  ├─ project-team-agent-chat.tsx  TeamAgentStreamView ──────────┐
  │   外层 CHAT_GUTTER > 内层 CHAT_COLUMN 两层 DOM（原单元素 max-w-3xl/px-4）│
  ├─ project-queue-bar.tsx  根 border-t > 外层 CHAT_GUTTER > 内层 CHAT_COLUMN │
  ├─ project-team-agent-chat.tsx  TeamAgentComposer ────────────┤
  │   横幅区: 外层 CHAT_GUTTER > 内层 CHAT_COLUMN；                │
  │   ChatInputCore(leftAdornment=Model/Thinking 工具栏,         │
  │                 allowSubmitWhileRunning + onStop 停止路径 §4.3.1,│
  │                 运行态=task-runs 时间线 + queue items 双源)    │
  └─ project-private-ask.tsx  PrivateAskComposer ───────────────┤
      横幅区: 外层 CHAT_GUTTER > 内层 CHAT_COLUMN；                │
      ChatInputCore(leftAdornment=Model/Thinking 工具栏)         │
                                                                 ▼
chat-input.tsx ChatInputCore ── 复用 ──> chat-column.ts (CHAT_GUTTER / CHAT_COLUMN)
     │ 底层复用（不改）
     ├─ packages/ui submit-button / chat-add-menu
     ├─ packages/views/agents/.../model-picker / thinking-picker（chip variant）
     └─ packages/views/editor（ContentEditor：附件预览/上传态/内部滚动）
```

依赖方向保持 `views -> core + ui` 不变（multica ARCHITECTURE.md §4）；`chat-column.ts` 常量是唯一对齐事实源，本 CR 不复制第二份常量（PRD FR-1）。

**嵌套不变量（回修 B-001）**：所有对齐块都必须以**两个 DOM 层**嵌套——外层 `CHAT_GUTTER`、内层 `CHAT_COLUMN`。单元素同时携带两者会把 gutter padding 计入 `max-w-4xl` 封顶计算，重演 `chat-column.ts` 文件头点名的历史错位形态（内容边缘比 composer surface 内缩一个 gutter），故 §4.1 全部落地规则均按两层 DOM 给出。

### 1.3 关键流程（一屏）

```text
渲染：ModePane(@container) → 消息流/队列栏/横幅区/发送框各处均以「外层 CHAT_GUTTER > 内层 CHAT_COLUMN」两层 DOM 嵌套
     → 发送框 surface 边缘与消息列边缘对齐（B-001）
配置：ModelPicker/ThinkingPicker(chip) → 与现状完全相同的 persistModel/persistThinking
     → PATCH /api/projects/:id/chat/config（Team Agent）或
       PATCH /api/chat/sessions/:id/config（Private Ask）→ 不改 Agent 配置
发送：ContentEditor → handleSend（draftAdapter/附件引用/pendingUploads 门禁原样）
     → 宿主 onSend → pending-message 渲染（原样）
停止：Team Agent 运行中（task-runs 时间线 `tasks.find(task => task.id === sentTaskId)` 命中且 status∈active，或仍在 queue items
     ——§4.3.1 双源；时间线未命中回落 items-only）→ 草稿空/上传中时 SubmitButton 渲染 stop → onStop 取消该 task
     （useCancelProjectQueueTask，TSUG-007 三支语义）；草稿非空时按钮为发送（queue send，
     失败保草稿后即重试按钮，§4.2）；Private Ask → onStop 原样
```

### 1.4 与 crctl/guard 命令面关系

本 CR 不触及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支，也不触及 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`，故 Skill 第 8 节「Prompt 采纳影响」按规则省略（不适用）。

## 2. 数据模型

**N/A（本 CR 无数据模型变更）**。理由与边界：

- 不新增/修改 API、数据库字段、任务快照或数据模型（PRD FR-7，来源 FR-33）。
- 会话配置（model/thinking_level）继续存于既有 `project_chat_session`/`chat_session`（CR-2026-056 交付），本 CR 只改渲染层。
- 草稿/附件/项目隔离继续走 `useProjectChatStore`（Zustand，`drafts`/`draftAttachments`），`ChatInputCore` 只认 `ChatInputDraftAdapter` 接口，不接触 `useChatStore`——该结构事实被 `chat-input.test.tsx` 钉住，本 CR 保持。
- 不回滚项、无迁移、无 DDL：Skill「数据/schema 变更与写路径鉴权完整性」条件不触发，故本节无回滚/约束窗口条目。

## 3. 接口契约

**本 CR 不新增、不修改任何 HTTP API / IPC / 事件契约**（PRD 已声明契约确定性四查 N/A）。本节只固化两类既有契约的消费方式，供评审与测试核对。

### 3.1 既有服务端契约（只消费，不改）

| 契约 | 消费点 | 本 CR 行为 |
|---|---|---|
| `PATCH /api/projects/:id/chat/config`（body `{session_id, model?, thinking_level?}`，三态语义；owner/admin 服务端 403 `forbidden_chat_config`） | `packages/core/api/client.ts` `patchProjectChatConfig`（L3722） | Team Agent 工具栏 Model/Thinking 控件继续调用，路径/参数不变 |
| `PATCH /api/chat/sessions/:id/config`（creator-only 服务端 403） | `packages/core/api/client.ts` `patchChatSessionConfig`（L3783） | Private Ask 工具栏控件继续调用，路径/参数不变 |

### 3.2 组件级契约（ChatInputCore）

`ChatInputCoreProps extends ChatInputProps` 的 props 签名**全部保持不变**（含 `leftAdornment?: ReactNode`）。本 CR 只改内部渲染结构与类名。宿主传给 `leftAdornment` 的内容约定如下（TypeScript 片段，落在两个项目组件内）：

```tsx
// TeamAgentComposer（project-team-agent-chat.tsx）——三态分支与四个内部 testid 全部保留；
// 锚点口径（B-001 定点回修）：Fragment 根**不**携带 data-testid="project-chat-model-row"——
// 该锚点随独立行一并移除（§9 移除清单第 2 项，无替换锚点），断言以四个内部 testid 位于
// project-chat-composer 子树为准；可见文字 label 不再渲染，类别语义以 sr-only 保留（B-002）：
const toolbar = agent ? (
  <>
    {!canConfigure ? (
      <span data-testid="project-chat-model-readonly">
        <span className="sr-only">{t(($) => $.chat.stream.model_label)}</span>
        <ModelPicker runtimeId={agent.runtime_id} runtimeOnline={!!runtimeOnline}
          value={chatModel} canEdit={false} onChange={() => {}} />
      </span>
    ) : runtimeReady ? (
      <span data-testid="project-chat-model-picker">
        <span className="sr-only">{t(($) => $.chat.stream.model_label)}</span>
        <ModelPicker runtimeId={agent.runtime_id} runtimeOnline={!!runtimeOnline}
          value={chatModel} canEdit onChange={persistModel} />
      </span>
    ) : (
      <span data-testid="project-chat-model-runtime-guide">
        {t(($) => $.chat.stream.runtime_guide)}
      </span>
    )}
    {thinkingLevels.length > 0 && (
      <span data-testid="project-chat-thinking-picker" className="flex items-center gap-1">
        <span className="sr-only">{t(($) => $.chat.stream.thinking_label)}</span>
        <ThinkingPicker value={chatThinking} levels={thinkingLevels}
          canEdit={canConfigure} onChange={persistThinking} />
      </span>
    )}
  </>
) : undefined;

// PrivateAskComposer（project-private-ask.tsx）——creator-only 可编辑；
// testid 口径（B-001 定点回修）：private-ask-model-row 已移除，模型控件用新锚点
// private-ask-model-picker（§9 移除清单第 1 项/新增清单）；private-ask-thinking-picker 保留；
// 类别语义同样以 sr-only 保留（B-002）：
const toolbar = (
  <>
    {agent ? (
      <span data-testid="private-ask-model-picker">
        <span className="sr-only">{t(($) => $.chat.stream.model_label)}</span>
        <ModelPicker runtimeId={agent.runtime_id} runtimeOnline={!!runtimeOnline}
          value={model} canEdit onChange={persistModel} />
      </span>
    ) : null}
    {thinkingLevels.length > 0 && (
      <span data-testid="private-ask-thinking-picker" className="flex items-center gap-1">
        <span className="sr-only">{t(($) => $.chat.stream.thinking_label)}</span>
        <ThinkingPicker value={thinkingLevel} levels={thinkingLevels} canEdit onChange={persistThinking} />
      </span>
    )}
  </>
);
```

控件使用 `ModelPicker`/`ThinkingPicker` 现有 `chip` variant（默认值）：可编辑 chip 的触发按钮自带 `aria-label={triggerTitle}`（`pickers.model_tooltip`/`pickers.thinking_tooltip` 文案）与 tooltip；`canEdit=false` 只读 chip 是纯 `<span>`（值文本 + `title`），**没有类别可访问名称**——因此宿主工具栏分支（Team Agent 三态 + Private Ask）全部以 `sr-only` 类别标签（既有 `chat.stream.model_label`/`thinking_label` 文案）包裹，辅助技术读作「模型 <值>」「思考级别 <值>」（B-002 回修）。不在工具栏中新增文案 key（NFR-3）；工具栏内不再常驻渲染可见文字 label（差异文档记录）。

**ChatInputCore 侧两处最小改动（props 签名不变）**（B-002 回修）：

1. `SubmitButton` 调用补传 `ariaLabel={t(($) => $.input.send_tooltip)}`、`stopAriaLabel={t(($) => $.input.stop_tooltip)}`——与 `ChatInput`（全局，L778/L782）完全同 key 同语义，无新文案 key。`submit-button.tsx` 的 ArrowUp/Square 均 `aria-hidden`，不传则图标按钮无可访问名称，AC-7 的 role/name 断言无落点。
2. 采纳 `ChatInputProps` 中既有 `allowSubmitWhileRunning?: boolean` 字段（L102，`ChatInputCore` 此前未解构使用，签名零变化）：发送门禁与按钮 `running` 判定按 `ChatInput` 同款语义（§4.2/§4.3.1）；Team Agent 传 `true`（队列天然支持续发），Private Ask 不传（行为与现状逐位一致）。

## 4. 关键算法与流程

### 4.1 对齐几何（gutter → column 嵌套，复用唯一常量）

采用 `chat-column.ts` 的嵌套顺序语义（gutter 在 cap 外、按**容器**而非 viewport 缩放）：

```text
CHAT_GUTTER = "px-5 @2xl:px-8 @4xl:px-12"   // 容器感知，@ 变体需 @container 祖先
CHAT_COLUMN = "mx-auto w-full max-w-4xl"     // 居中、封顶、封顶下满宽
```

落地规则：

1. `ChatInputCore` wrapper（外层 gutter）：`"px-5 pb-3 pt-0"` → `cn(CHAT_GUTTER, "pb-3 pt-0", noAgent && "cursor-not-allowed")`。
2. `ChatInputCore` surface（内层 column，独立 DOM 节点）：`"relative mx-auto flex min-h-16 max-h-40 w-full max-w-4xl flex-col rounded-lg bg-card pb-9 border-1 border-border transition-colors focus-within:border-brand"` → `cn(CHAT_COLUMN, "relative flex min-h-16 max-h-40 flex-col rounded-lg border border-surface-border bg-surface transition-[border-color,box-shadow] focus-within:border-brand focus-within:ring-2 focus-within:ring-ring/20", noAgent && "pointer-events-none opacity-60")`，并补 `data-slot="chat-input-surface"`（与 `ChatInput` L651 对齐，供截图/测试共用选择器；`ChatInput` 与其测试均不受影响——两组件从不同时挂载）。wrapper 与 surface 本来就是两个 DOM 层，保持分层（B-001）。
3. Team Agent 消息流根容器：`"mx-auto flex w-full max-w-3xl flex-col gap-4 px-4 py-3"` 拆为**两个 DOM 层**（B-001 回修）：

   ```tsx
   <div className={cn(CHAT_GUTTER)}>                               {/* 外层：gutter 在 cap 之外 */}
     <div className={cn(CHAT_COLUMN, "flex flex-col gap-4 py-3")}> {/* 内层：阅读列 */}
       …no-earlier 分隔 + items…
     </div>
   </div>
   ```

   **禁止** `cn(CHAT_GUTTER, CHAT_COLUMN, …)` 单元素合并：gutter padding 会并入 `max-w-4xl` 封顶计算，使内容边缘比 composer surface 内缩一个 gutter（`chat-column.ts` 文件头点名的历史错误形态）；消息列与发送框边缘对齐（FR-1/AC-1）必须靠两层嵌套成立。
4. `ModePane` 根（project-chat-panel.tsx L199）：`"flex h-full flex-col p-4"` → 加 `@container`。项目面板宽窄由 ResizablePanel 决定，`@container` 使 `@2xl`/`@4xl` 按面板宽度生效（窄面板恒基态 px-5，不依赖 viewport——FR-1/AC-3）。
5. `ProjectQueueBar` 根：`"shrink-0 border-t px-4 py-2"` → 根保持 `shrink-0 border-t`，内部改为**两个 DOM 层**（B-001 回修）：

   ```tsx
   <div className="shrink-0 border-t" data-testid="project-queue-bar">
     <div className={cn(CHAT_GUTTER)}>            {/* 外层：gutter */}
       <div className={cn(CHAT_COLUMN, "py-2")}>  {/* 内层：阅读列 */}
         …toggle + expanded list（内容与交互零改动）…
       </div>
     </div>
   </div>
   ```

6. 两 composer 外层（project-team-agent-chat.tsx L864 / project-private-ask.tsx L392）：`"shrink-0 border-t px-4 py-3"` → `"shrink-0 border-t"`；横幅区（pending-message / presenter-required / queue-full / private-ask-pending-message）迁入**两个 DOM 层**块：外层 `cn(CHAT_GUTTER, "pt-3")`、内层 `cn(CHAT_COLUMN)`（无横幅时该块仍渲染，保留 pt-3 顶部间距）；`ChatInputCore` 的 wrapper（gutter + `pb-3`）继续提供底部间距与对齐。横幅右缘与 surface 右缘一致（pending-message `justify-end` 贴 column 右缘）。

### 4.2 底部工具栏（flow 布局，窄屏整体换行）

`ChatInputCore` 底栏由两处 absolute 行（现 L1128/L1137）改为 surface 内的普通流布局行，成为「输入区 → 底栏」两层结构：

```tsx
{/* 编辑器区：在普通聊天 flex-1 min-h-0 overflow-y-auto 基础上，以显式 min-h-8 作为
    底栏换行时的输入区地板（overflow-y-auto 已使 flex 自动最小尺寸为 0，无需同时声明
    min-h-0——两者同为 min-height 工具类，并写会产生样式层叠歧义） */}
<div className="flex-1 min-h-8 overflow-y-auto px-3 py-2">…ContentEditor…</div>
{/* 底栏：左组可换行，右组固定 */}
<div className="flex items-center justify-between gap-2 px-1.5 pb-1.5">
  {(uploadEnabled || leftAdornment) && (
    <div className="flex min-w-0 flex-1 flex-wrap items-center gap-1">
      {uploadEnabled && <ChatAddMenu onSelectFile={(f) => editorRef.current?.uploadFile(f)} />}
      {leftAdornment}
    </div>
  )}
  <div className="flex shrink-0 items-center gap-1">
    <SubmitButton
      onClick={handleSend}
      disabled={isEmpty || isSubmitting || !!disabled || !!noAgent || pendingUploads > 0}
      loading={isSubmitting}
      // 与 ChatInput 同款队列语义（B-003 回修）：allowSubmitWhileRunning 时运行中
      // 仍可发送（Queue Send），仅空输入/上传中回落为 Stop；未传时运行中只显示 Stop。
      // 推论（失败回流可见动作，§4.3.1/AC-5(h)）：发送失败保草稿（isEmpty=false）
      // ⇒ running=false，渲染发送/重试按钮；清空草稿后 stop 重新出现并可取消旧目标。
      running={!!isRunning && (!allowSubmitWhileRunning || isEmpty || pendingUploads > 0)}
      onStop={onStop}
      tooltip={sendShortcut
        ? `${t(($) => $.input.send_tooltip)} · ${formatShortcut(sendShortcut)}`
        : t(($) => $.input.send_tooltip)}
      ariaLabel={t(($) => $.input.send_tooltip)}       {/* B-002：发送可访问名称 */}
      stopTooltip={t(($) => $.input.stop_tooltip)}
      stopAriaLabel={t(($) => $.input.stop_tooltip)}   {/* B-002：停止可访问名称 */}
    />
  </div>
</div>
```

要点：

- surface 由 `pb-9`（为 absolute 行预留）改为 `pb-0`，底栏自身 `px-1.5 pb-1.5` 提供与普通聊天 absolute 行（`bottom-1.5 left-1.5` = 6px）同等的贴边距离；`max-h-40` 保留（差异文档条目 D-4）。
- 发送门禁与按钮状态同步采纳 `allowSubmitWhileRunning`（ChatInputProps 既有字段，`ChatInputCore` 此前未解构使用，本次补上，签名不变）：`handleSend` 门禁的 `isRunning` 项改为 `isRunning && !allowSubmitWhileRunning`；SubmitButton `running` 判定如上片段。Private Ask 不传该字段 → 行为与现状逐位一致；Team Agent 传 `true`（队列天然支持续发，见 D-7）。**可见动作口径（单一事实，§4.3.1/AC-5 以此为准）**：`trackedActive=true` 时，草稿非空且无上传中 → `running=false` → 渲染**发送（queue send；发送失败保草稿后即重试）按钮**；草稿为空或上传中 → `running=true` → 渲染 **stop**。因此失败回流后的可见动作是「保草稿 + 发送（重试）按钮」，**不是 stop**；保留的旧目标在清空草稿后由重新出现的 stop 取消（§4.3.1）。
- 左组 `flex-wrap`：窄屏（360px 浮窗/窄项目面板）时 Model chip、Thinking chip、添加菜单**在底栏内整体换行**，不与输入区重叠、不把发送/停止按钮顶出面板；右组 `shrink-0` 始终在右下角。
- 编辑器 `flex-1 min-h-8 overflow-y-auto` 保证长文本内部滚动（FR-2）；`min-h-8` 地板保证底栏换行最多占满时输入区仍可操作（FR-4「不挤压输入区」的落点解释，见 §4.4 术语硬化）。
- `leftAdornment` 为空且无上传时不渲染左组（现状条件 `uploadEnabled || leftAdornment` 不变）；仅右组时布局与普通聊天一致。
- 换行算法 = CSS flex-wrap 自身，无 JS 测量、无 ResizeObserver、无状态机。

### 4.3 视觉状态映射（不回归，AC-5）

| 状态 | 承载 | 本 CR |
|---|---|---|
| 附件预览/上传中 | `ContentEditor` attachments + `pendingUploads`（chat-input.tsx L870） | 不变 |
| 上传中禁发 | `SubmitButton disabled` 含 `pendingUploads > 0`（L1140）+ `handleSend` 内 `hasActiveUploads()` 门禁 | 不变 |
| 发送中 | `isSubmitting` → `SubmitButton loading` | 不变 |
| 运行中停止 | Team Agent：`isRunning`=最近一次发送 task 处于活动生命周期（queued/dispatched 由 queue items、running/waiting_local_directory 由任务时间线判定，§4.3.1 双源）；`onStop`=受权取消该 task（§4.3.1）；Private Ask：`running/pendingTaskId → onStop=api.cancelTaskById` 原样 | §4.3.1 |
| 失败重试 | 宿主 `onSend` 返回 false 保草稿 + toast（原样） | 不变；失败回流后草稿非空且 Team Agent `allowSubmitWhileRunning=true` ⇒ `running=false`，右下角为**发送（重试）按钮**；旧活动目标保留在 sent 状态，**清空草稿后 stop 重新出现**可取消（§4.3.1） |
| 空态 | placeholder（原样） | 不变 |

#### 4.3.1 Team Agent composer 运行中停止路径（B-003 回修 v2）

事实（multica@117fc6be）：`TeamAgentComposer` 当前 `isRunning={isPending}`（`useSendProjectChatMessage` 的本地入队窗口）且不传 `onStop`；`SubmitButton` 在 `running=true` 时把右下角按钮 `onClick` 直接绑定 `onStop`——当前渲染的是一个**无处理器的停止按钮**，且入队窗口结束后任务真正运行期间反而没有任何运行态。`ProjectQueueBar` 展开后的取消是另一入口，不能替代 composer 右下角动作。PRD FR-5/AC-5、来源 AC-33 与规则 5「右下角复用普通聊天的发送/停止按钮和 loading、上传中、运行中状态」要求该动作可用；同时规则 8 要求保留运行中停止。因此裁定：**接入可执行停止路径，而不是渲染不可用按钮或以队列栏替代**（「不渲染 stop」无需求授权）。

**B-003 v2 修正（上一轮语义错误）**：`projectQueueItemsOptions` 的 items 由服务端查询 `ListProjectPendingTasks`（server/pkg/db/queries/agent.sql L2947-2961）过滤为**仅 queued + dispatched**——任务进入 `running` 后离开该列表，因此 items 不能单独作为 `running` 的事实源。本设计改用**双源活动性判定**：queue items 覆盖 queued/dispatched 窗口，**容器 Issue 任务时间线**（Team Agent 消息流已读取的 task-runs 列表——`AgentTask[]` 数组，按 `task.id === sentTaskId` 唯一选取最近一次发送的 task，`AgentTask.status` 含 `running`/`waiting_local_directory`；列表为空/未命中回落 items-only）覆盖 running 及其后生命周期，两者取并、终态覆盖，闭合 queued→dispatched→running→terminal 全生命周期。零新增 API、零服务端契约变更（zero_diff）。

状态与动作（全部复用既有受权能力，零新增 API/状态管理；两个事实源复用既有 query 缓存，无新增请求）：

| 信号 | 来源 | 语义 |
|---|---|---|
| `sentTaskId` / `sentIssueId` | `useSendProjectChatMessage(...).mutateAsync()` 成功返回值 `ProjectChatSendResult.task_id` / `issue_id`（schemas.ts L1524-1529；组件内单条语句 `useState` 保存）。**确定性转移（cycle 2 回修）**：发送成功且返回 `task_id`/`issue_id` **任一无效（空）** → **原子清空两个 ID**（不留旧目标）；发送**失败**（mutation reject，`handleSend` catch 分支返回 false，setState 未执行）→ **保留**旧值。**失败回流的可见动作（cycle 2 attempt 2 回修）**：保留旧值 ≠ 立即渲染 stop——失败保草稿令 `isEmpty=false`，且 Team Agent 传 `allowSubmitWhileRunning=true`，§4.2 判定式得 `running=false`，右下角渲染**发送（重试）按钮**；用户**清空草稿**后 `isEmpty=true` → `running=true` → stop 重新出现，点击取消该保留的 task（草稿清空前也可经 ProjectQueueBar 既有入口取消） | 本 composer 最近一次成功入队的 task 与其容器 Issue |
| `taskInItems` | `useQuery(projectQueueItemsOptions(wsId, projectId)).data.items` 中是否存在 `task_id === sentTaskId`（items 服务端过滤 queued/dispatched，见依赖 #21；与 ProjectQueueBar 共用同一 query key 缓存，react-query 去重） | queued/dispatched 取消窗口 |
| `tasks`（task-runs 列表） | `useQuery({ queryKey: issueKeys.tasks(sentIssueId), queryFn: () => api.listTasksByIssue(sentIssueId), staleTime: 30_000, enabled: !!sentIssueId }).data`——`api.listTasksByIssue` 返回 **`Promise<AgentTask[]>`**（client.ts L2478；`AgentTaskListSchema = z.array(AgentTaskSchema)`，schemas.ts L2300，解析失败 fallback `[]`，依赖 #14），既有 `ProjectTeamAgentChat` 消息流即按数组消费（`const { data: tasks = [] }`，本文件 L98-102）；同一 query key（`["issues","tasks",issueId]`，issues/queries.ts L179），两者同时启用时收敛为同一缓存，**不产生重复请求**；查询未启用/加载中按 `[]` 处理 | 容器 Issue 全部任务时间线（**数组**，服务端缺省路径全量返回无分页截断，依赖 #14） |
| `taskEntry` | `tasks.find(task => task.id === sentTaskId)`（`AgentTask.id: string`，types/agent.ts L279）——按 id **唯一选取**最近一次发送的 task；列表为空或未命中（该 task 尚未进入时间线/查询 disabled/加载中/fallback `[]`）→ `undefined`，**不取 first、不按时间猜**，running/terminal 判定与最近一次发送任务唯一关联，绝不落到容器 Issue 其他 task 的状态 | 最近一次发送 task 的权威状态（含 running/waiting_local_directory 与终态） |
| `taskActive` | `taskEntry != null && ACTIVE.has(taskEntry.status)`，`ACTIVE = { queued, dispatched, waiting_local_directory, running }`（与 agent.ts L286-298 状态联合及「active vs done」分桶注释一致）；未命中 → `false` | 任务时间线判定的活动态（含真正的 running） |
| `taskTerminal` | `taskEntry != null && TERMINAL.has(taskEntry.status)`，`TERMINAL = { completed, failed, cancelled }`；未命中 → `false` | 任务时间线判定的终态 |
| `trackedActive` | `(taskInItems || taskActive) && !taskTerminal` | 运行态判定：任一源说活动即活动；任务时间线说终态即覆盖陈旧 items 残留 |
| `isRunning`（传 ChatInputCore） | `trackedActive` | 运行态：终态落地后自动回落 false，按钮回发送态 |
| `onStop` | `handleStop`：`cancelTask.mutateAsync(sentTaskId)`（`useCancelProjectQueueTask`，本文件 TaskExecutionCard 已使用） | 取消最近一次发送的 task |
| `allowSubmitWhileRunning`（传 ChatInputCore） | `true` | 运行中仍可续发（队列语义），与现状「入队完成后即可再发」一致（FR-7 不回归） |

生命周期闭合表（B-003 验收口径，测试计划 §6.9 逐行覆盖）：

| 阶段 | queue items（服务端过滤 queued+dispatched） | 任务时间线（`GET /api/issues/:id/task-runs` → `tasks.find(task => task.id === sentTaskId)` 命中后的 status） | `trackedActive` |
|---|---|---|---|
| queued | ✓ 含 sentTaskId | ✓ status=queued | true（两源均真） |
| dispatched | ✓ 含 sentTaskId | ✓ status=dispatched | true |
| running | ✗（离开 items） | ✓ status=running | true（任务时间线单独支撑） |
| waiting_local_directory | ✗ | ✓ status=waiting_local_directory（active 分桶） | true |
| completed / failed / cancelled | ✗ | ✓ status=terminal | false（`!taskTerminal` 覆盖陈旧 items 残留，不渲染死按钮） |
| 未命中/空列表（该 task 尚未进入时间线、查询 disabled/加载中、fallback `[]`） | 按实际：可能含、可能不含 | ✗（无命中 ⇒ `taskEntry=undefined`，不取其他 task 状态） | = items-only（items 含 sentTaskId → true，覆盖 queued/dispatched 窗口；items 也不含 → false，按钮回发送态） |

两个事实源的实时性由既有 WS 失效保障：`task:*` 前缀事件失效 `["issues","tasks"]`（use-realtime-sync.ts L926）与 `projectKeys.queueStatusAll(wsId)`（L902，items 键挂在同一前缀下）——composer 与消息流卡片、队列栏同一次刷新，无需新增订阅或轮询。

竞态与错误语义（沿用 TSUG-007 三支，与 TaskExecutionCard/ProjectQueueBar 完全一致）：

1. `res.status === "cancelled"` → 静默成功（含重复取消的幂等 200）；
2. 其他终态 → `toast.error(chat.stream.cancel_already_finished)`；
3. 抛 `ApiError`（403 等）→ `toast.error(e.message)`。

边界：

- **入队窗口**（mutation in-flight）：`isRunning=false`，ChatInputCore 内部 `isSubmitting` 显示 loading（不再显示无目标的 stop）；响应落地后 `sentTaskId`/`sentIssueId` 按确定性转移更新（有效则写入、任一空则原子清空，见「硬降级」）、任务时间线与 items 经 WS `task:*` 前缀失效刷新，短暂窗口内 `trackedActive` 可能滞后翻 true，可接受（与消息流/队列栏同一实时缓存口径）。
- **任务时间线未命中/空列表**（fallback `[]`、查询 disabled/加载中或 `tasks.find` 无命中——该 task 尚未进入时间线）：`taskEntry=undefined` ⇒ `taskActive=false`/`taskTerminal=false`，`trackedActive` 回落 **items-only**（queued/dispatched 窗口仍由 queue items 覆盖）；两源均无 → `trackedActive=false`、按钮回发送态。**绝不**因容器 Issue **其他** task 的状态误判 running/终态（`tasks` 是容器全部任务，选取必须按 `task.id === sentTaskId`）。
- **首次发送的容器绑定**：面板持有的 `chat.issue_id`（`projectChatOptions` 缓存，全局 staleTime=Infinity 且 send 成功路径不失效，见依赖 #15）可能在首次发送后短暂停留在旧值；composer **不依赖面板 props**，以发送响应自带的 `issue_id`（`ProjectChatSendResultSchema` L1531-1537 为 UUID 必填）键定任务时间线查询——首条消息的 running 覆盖不依赖面板刷新。面板缓存随后收敛为同一 issueId 时，两边 query key 相同、缓存自动去重。无容器（`sentIssueId` 为空：未发送/硬降级已清空）时查询 disabled，活动性回落 items-only（恒 false，因两个 sent ID 均已原子清空）。
- **续发**：`allowSubmitWhileRunning=true` 时，运行中 + 有内容 → 按钮为发送（queue send），空输入/上传中 → stop；再次发送成功后（返回 ID 有效）`sentTaskId`/`sentIssueId` 指向最新 task——**stop 只作用于最近一次**，其余任务仍由队列栏逐条取消；若该次返回空 ID，则按「硬降级」原子清空（无运行态），其余任务仍由队列栏逐条取消（差异文档记录）。
- **硬降级**：send 成功但 `parseWithFallback` 使返回的 `task_id=""` 或 `issue_id=""`（任一无效；成功 body 缺 `session_id`/`issue_id` 会把**整个结果**降级为空 fallback、`task_id` 缺失 default 为空串，schemas.ts L1519-1523/L1531-1537）→ **原子清空 `sentTaskId` 与 `sentIssueId`**（确定性转移：不留上一次的有效目标——否则 stop 会错误取消旧 task）；send **失败**（mutation reject → `handleSend` catch 返回 false 保草稿，成功行 setState 未执行）→ **保留**旧活动目标。**保留 ≠ 渲染 stop**：失败保草稿（`isEmpty=false`）+ `allowSubmitWhileRunning=true` ⇒ §4.2 判定式 `running=false`，右下角为**发送（重试）按钮**；**清空草稿后 stop 重新出现**并可取消该旧目标（AC-5(h)/§6.9(iii) 落点）。清空后 `trackedActive` 恒 false，composer 无运行态（不渲染死按钮）。
- **取消成功回流**：`useCancelProjectQueueTask.onSettled` 失效 `projectKeys.queueStatus` 前缀（含 items）+ WS `task:*` 事件失效任务时间线，`trackedActive` 翻 false、按钮回发送态。
- **权限**：取消权限由服务端 403 强制（originator 或 owner/admin）；本路径只取消本 composer 最近发送的 task（originator 恒为当前用户），不扩大权限面、不新增可写路径。

### 4.4 术语硬化（Step 2.5）

| PRD 术语 | 代码别名/落点 | 边界验证 |
|---|---|---|
| 「底部工具栏控件 / leftAdornment 或等价底部工具栏 slot」 | 选定现有 `ChatInputCore.leftAdornment` slot（**不**新建等价 slot/组件）；代码别名 `leftAdornment` | 360px 浮窗 + 长模型 ID：chip `min-w-0 truncate` 截断 + 左组 wrap，验证不横向溢出 |
| 「窄屏换行（不挤压输入区）」 | 解释 = 底栏整体在自身行带内换行、输入区永不与控件重叠；编辑区 `flex-1 min-h-8 overflow-y-auto` 地板 | 底栏两行场景：编辑器仍可聚焦、可滚动、发送按钮不被顶出 |
| 「运行中停止（Team Agent）」 | 解释 = composer 右下角 stop 作用于最近一次发送且处于活动生命周期的 task（queued/dispatched 由 queue items、running/waiting_local_directory 由任务时间线 `tasks.find(task => task.id === sentTaskId)` 唯一选取判定）；代码别名 `sentTaskId`/`sentIssueId`/`taskInItems`/`tasks`/`taskEntry`/`trackedActive`；可见动作（stop vs 发送/重试）由 §4.2 `running` 判定式唯一决定 | 边界验证：task 在任务时间线为终态（completed/failed/cancelled）→ stop 不渲染、按钮回发送态（终态覆盖陈旧 items）；running 且离开 items → 运行态仍真，草稿空/上传中渲染 stop、草稿非空渲染发送（queue send）；发送失败保草稿 → 发送（重试）、清空草稿后 stop 重新出现；重复点击 → 幂等静默（TSUG-007 分支 1）；任务时间线未命中/空列表 → 回落 items-only，不因容器 Issue 其他 task 状态误判 running/终态 |
| 「单一输入 surface」 | = `ChatInputCore` surface 采用与 `ChatInput` 相同的 border/bg/focus/圆角/内部滚动类名集合 | 焦点态：`focus-within:ring-2 ring-ring/20` 与普通聊天一致（组件测试断言） |

无语义冲突需需求负责人澄清，全部在 PRD 授权范围内裁定。

## 5. 技术选型与替代方案

### D-1 复用 chat-column.ts 常量（而非复制/新造常量）

- **Decision**：`ChatInputCore`、Team Agent 消息流、队列栏、两 composer wrapper 全部引用 `CHAT_GUTTER`/`CHAT_COLUMN` 单一事实源。
- **Context**：PRD FR-1 明令「不复制第二份常量」；`chat-column.ts` 文件头注释已说明嵌套顺序语义与容器感知原因。
- **Alternatives**：a) 复制常量到项目组件——PRD 明令禁止且埋下漂移风险；b) 保持 `mx-auto max-w-3xl px-4` 消息列不动、只改 composer——消息列与发送框边缘仍不对齐，AC-1 不过。
- **Consequences**：项目消息列宽度由 max-w-3xl 变 max-w-4xl（对齐普通聊天），属预期视觉变化，记录入差异文档。

### D-2 底栏 flow 布局（而非 absolute + wrap）

- **Decision**：`ChatInputCore` 底栏改为普通流布局（编辑区上方、底栏行下方）。
- **Context**：现有 absolute 行（L1128/L1137）在 360px 面板接入 Model/Thinking chip 后必然与编辑区/右组按钮重叠；FR-3/FR-4 要求「换行不挤压输入区、互不遮挡」。
- **Alternatives**：a) 保持 absolute，左组 `max-w-[calc(100%-3rem)] flex-wrap`——换行后向上长入编辑区（重叠，违反 FR-4）；b) 给 surface 加动态 padding（JS 测量底栏高度）——引入 ResizeObserver 与状态，违反「不引入新状态管理」精神。
- **Consequences**：一行态下与普通聊天视觉等价；`ChatInput`（全局）不动，普通聊天基线零变化（NFR-5）。

### D-3 控件用现有 chip variant 移入 leftAdornment（而非新工具栏组件）

- **Decision**：直接复用 `ModelPicker`/`ThinkingPicker` 默认 `chip` variant，宿主以 `leftAdornment` 传入。
- **Context**：chip variant 自带截断、tooltip、可访问名称、`canEdit=false` 只读形态，正是工具栏所需；PRD NFR-4 不引入新组件。
- **Alternatives**：a) 新建 `ProjectChatConfigToolbar` 组件——两份状态/样式逻辑，负抽象价值（两宿主差异仅在 canEdit 与 testid）；b) 保留 `*-model-row` 独立行——正是本 CR 要消除的第二套视觉体系。
- **Consequences**：Model/Thinking 文字 label（`model_label`/`thinking_label`）不再常驻显示，语义由 chip 文本 + tooltip 承载；写入差异文档。

### D-4 surface 高度封顶保留 max-h-40（不照搬普通聊天 max-h-96）

- **Decision**：`ChatInputCore` surface `max-h-40` 保留，不改为 `max-h-96`/`max-h-[50%]` 体系。
- **Context**：项目面板是短视口（消息流 + 队列栏 + 发送框共处），10rem 封顶是既有可用行为；AC-2 只要求「长文本内部滚动、发送按钮不被顶出」，max-h-40 + `overflow-y-auto` 已满足。
- **Alternatives**：照搬 `max-h-96`——项目面板内发送框可占满大半面板，挤压消息流，体验回退。
- **Consequences**：与普通聊天存在封顶值差异 → 必要差异，记入差异文档。

### D-5 @container 加在 ModePane 根

- **Decision**：`project-chat-panel.tsx` 的 `ModePane` 根 div 加 `@container`。
- **Context**：`@2xl:`/`@4xl:` 变体需要 `@container` 祖先；项目面板宽度由 ResizablePanel（可拖拽、含窄场景）决定。
- **Alternatives**：a) 加在 composer wrapper——只有发送框吃容器变体，消息列/队列栏吃不到，边缘再次错位；b) 不加——@ 变体永不生效，退回恒定 px-5（功能上不坏但丢失容器感知语义，与「复用 chat-column 语义」不符）。
- **Consequences**：Discussion 面板同用 ModePane，无 @ 变体使用方，零影响。

### D-6 差异说明文档落点

- **Decision**：新增 `packages/views/projects/components/project-chat-composer-layout-diff.md`（英文，随 multica 仓提交）。
- **Context**：来源文档把「与普通非项目聊天布局的差异说明，仅记录必要差异」列为主要交付物；就近放代码旁最易在 rebase/评审时被发现。
- **Alternatives**：a) 放 `apps/docs`——面向用户的产品文档站，不适合内部实现注记；b) 放 openwiki——生成物，禁手编。
- **Consequences**：实施期若差异变化，同 PR 内更新该文件。

### D-7 Team Agent 运行中停止路径（B-003 回修 v2）

- **Decision**：`isRunning` 采用**双源活动性判定**——queue items（服务端过滤 queued+dispatched，覆盖排队/派发窗口）∪ 容器 Issue 任务时间线（`issueKeys.tasks(sentIssueId)` 返回 `AgentTask[]`，`tasks.find(task => task.id === sentTaskId)` 唯一选取最近一次发送的 task，`AgentTask.status` 覆盖 running/waiting_local_directory 与终态；列表为空/未命中回落 items-only），并集后以任务时间线终态覆盖；`onStop` 复用 `useCancelProjectQueueTask` 取消 `sentTaskId`，并传 `allowSubmitWhileRunning=true` 保持运行中可续发；不渲染无处理器的 stop。
- **Context**：上一轮「items 含 sentTaskId ⇒ 排队/派发/运行」不成立——items 只含 queued/dispatched，任务 running 后离开列表、按钮会错误回发送态（B-003 复评指出）。任务时间线是 Team Agent 消息流已读取的既有事实源（同一 query key，缓存收敛去重），且 WS `task:*` 事件同时失效两个源（use-realtime-sync.ts L926/L902），生命周期闭合无需新契约。PRD FR-5/AC-5 与来源 AC-33 要求运行中停止可用；FR-7 要求 send/stop 业务行为不回归（取消端点、权限、TSUG-007 语义均复用现状）。
- **Alternatives**：a) 不渲染 stop、只留队列栏——违反来源规则 5「右下角复用发送/停止按钮和运行中状态」，无需求授权；b) `isRunning` 常 true 并锁发送直到 task 终态——改变现状「入队完成后即可再发」的发送行为，违反 FR-7；c) 给 ChatInputCore 新增独立 stop 槽位解耦——扩大共享组件契约面，超出「最小调整」；d) 修改 queue-items 服务端过滤或新增 API 返回 running——违反本 CR zero_diff（不新增/修改 API、服务端零改动）。
- **Consequences**：stop 只作用于最近一次 task（其余由队列栏逐条管理）；入队窗口短暂无运行态（loading）；running 期间（含离开 items 后）可见动作由 §4.2 判定式决定——草稿空/上传中 → stop，草稿非空 → 发送（queue send）；终态落地后回发送态。发送失败保草稿 → 发送（重试）按钮，清空草稿后 stop 重新出现并可取消保留的旧目标（可见动作与状态保留一致，无第二动作入口）。该语义与生命周期闭合表（§4.3.1）记入差异文档。

## 6. FR 到技术实现映射

| FR | 技术实现落点 | 验收入口 |
|---|---|---|
| FR-1 布局对齐 | `chat-input.tsx` ChatInputCore wrapper（外层 `CHAT_GUTTER`）/surface（内层 `CHAT_COLUMN`）；`project-team-agent-chat.tsx` 消息流根与横幅区、`project-queue-bar.tsx` 均为两层 DOM；`project-chat-panel.tsx` 加 `@container` | AC-1 |
| FR-2 单一输入 surface | ChatInputCore surface 类名集合 = ChatInput surface（border-surface-border/bg-surface/rounded-lg/focus-within ring/内部滚动）；分层结构 §4.2 | AC-2 |
| FR-3 控件入底部工具栏 | 两宿主构造 `leftAdornment`（§3.2），`persistModel`/`persistThinking` 原样；Team Agent 三态（可编辑/只读徽标/runtime guide）原样；Private Ask creator-only 原样 | AC-4 |
| FR-4 窄屏不溢出不遮挡 | §4.2 flow 布局 + wrap + `min-h-8` 地板；e2e 360px 回归 | AC-3 |
| FR-5 视觉状态一致 | §4.3 状态映射表逐项不变；`SubmitButton` 复用；Team Agent 运行中停止路径 §4.3.1（可执行，非死按钮；双源覆盖 queued→dispatched→running 全生命周期） | AC-5 |
| FR-6 可访问性保持 | ChatInputCore 传 `ariaLabel`/`stopAriaLabel`（B-002）；只读/可编辑配置控件带 sr-only 类别标签；chip variant 自带 aria-label/tooltip；键盘发送 Mod+Enter 由 ContentEditor `onSubmit` 原样承载 | AC-7 |
| FR-7 不新增数据与业务语义 | 改动清单仅渲染层（§1.1）；`zero_diff` 清单（§9） | AC-6/AC-8 |
| FR-8 共享组件适配与测试 | Web/Desktop 共享 `packages/views`；组件测试 + Playwright（§6.9）；差异文档（§5.6） | AC-7/AC-8 |

### AC 逐项设计与验收映射（Step 2.6）

- **AC-1** 设计落点：ChatInputCore wrapper/surface 两层 + Team Agent 消息流根两层 + 队列栏两层 + ModePane `@container`。可观测结果：组件测试断言两 composer wrapper（外层）含 `CHAT_GUTTER`、surface（内层）含 `CHAT_COLUMN` 且二者为**不同 DOM 节点**；消息流根为「外层 `CHAT_GUTTER`>内层 `CHAT_COLUMN`」两层；队列栏同两层（§4.1 规则 3/5/6）。Playwright 宽面板截图发送框边缘与消息列边缘对齐（差 < 1px 容差）。可达性：所有路径均为无状态静态类名，无查询/权限前置，挂载即成立。
- **AC-2** 设计落点：ChatInputCore surface 类名集合（§4.1-2）。可观测结果：组件测试对 surface 断言 `border-surface-border bg-surface rounded-lg focus-within:ring-2` 等 token；长文本注入后编辑器区 `overflow-y-auto` 生效、发送按钮仍在视口内。可达性：与 draft 内容长度解耦，测试直接驱动。
- **AC-3** 设计落点：§4.2 底栏 flow 布局 + `ModePane @container`。可观测结果：Playwright **真跑**（非 `--list`，见 §6.9-3 证据契约）在 360px 视口打开项目聊天面板，断言无横向溢出（`scrollWidth <= clientWidth`）且输入区/附件预览/配置控件/发送停止按钮无重叠（boundingBox 检查 + 截图基线）。可达性：面板宽度由 e2e 固定 viewport 决定，不依赖数据。
- **AC-4** 设计落点：两宿主 `leftAdornment` 内容（§3.2），`persistModel`/`persistThinking` 与 `patchProjectChatConfig`/`patchChatSessionConfig` 调用路径不变。可观测结果：组件测试沿用既有 `project-chat-model-picker`/`project-chat-model-readonly`/`project-chat-model-runtime-guide`/`project-chat-thinking-picker`/`private-ask-thinking-picker` testid 断言三态与渲染，并断言 Team Agent 四个控件 testid 位于 `project-chat-composer` 子树（**不再以 `project-chat-model-row` 为定位锚点**——该 testid 随独立行移除，§9 移除清单第 2 项）；Private Ask 模型控件以新 `private-ask-model-picker` testid 定位（`private-ask-model-row` 随行移除，§9 移除清单第 1 项）；mock api 断言 PATCH URL/body 与现状一致且无 `updateAgent` 调用。可达性：三态由 `canConfigure`/`runtimeReady` 分支决定，既有测试已覆盖全部三态路径。
- **AC-5** 设计落点：§4.3 映射表（`pendingUploads`/`isSubmitting`/运行态门禁）+ §4.3.1 Team Agent 停止路径（`sentTaskId`/`sentIssueId`/`taskInItems`/`tasks`/`taskEntry`/`trackedActive`/`handleStop`，双源）。可观测结果：既有 chat-input/项目聊天测试全绿；新增——（a）queued/dispatched 窗口：mock 发送返回 `task_id` 且 mock queue items 含该 task → stop 渲染（发送成功后 `commitInput` 已清空草稿、`isEmpty=true` ⇒ §4.2 判定式 `running=true`）、点击后 `cancelTaskById(task_id)` 被调用；（b）**running**：mock 发送返回 `task_id`+`issue_id`，mock `listTasksByIssue(issue_id)` 返回**数组**且 `tasks.find(task => task.id === sentTaskId)` 命中该 task、`status="running"`、mock items **不含**该 task → stop 仍渲染（发送成功后草稿已清空 ⇒ 满足 §4.2 判定式；证明运行中停止可达，不依赖 items）；（c）终态回流：task-runs 命中项该 task `status="completed"`（items 即使陈旧仍含该 task）→ 按钮回发送态（终态覆盖）；（d）`waiting_local_directory`（同上，草稿已清空）→ stop 渲染；（e）取消返回非 cancelled 终态 → `cancel_already_finished` toast；（f）硬降级：首次发送即返回空 `task_id`/`issue_id`（任一无效）→ 两个 sent ID 原子清空、不渲染死按钮；（g）**顺序分支**：先发送成功返回有效 `task_id`+`issue_id`（活动 A，stop 渲染）→ 下一次发送**成功但返回空 `task_id`** → 断言 stop 消失、按钮回发送态且**不调用 `cancelTaskById(A)`**（空 ID 分支不得取消旧 task）；（h）发送失败（mutation reject）→ 草稿保留、旧活动目标保留（sent 状态不变）；**可见动作与 §4.2 判定式一致**：草稿非空 + `allowSubmitWhileRunning=true` ⇒ `running=false`，右下角渲染**发送（重试）按钮**（非 stop）；随后清空草稿（`isEmpty=true`）→ stop 重新渲染、点击仍调用 `cancelTaskById(A)`；重试成功且返回有效 ID → `sentTaskId` 更新为新 task（stop 只作用于最近一次）；（i）**时间线未命中**：mock `listTasksByIssue(issue_id)` 返回非空数组但**不含** `sentTaskId`（含另一 task `status="running"`）→ stop 不渲染、按钮回发送态（`taskEntry=undefined`，**不得**以容器 Issue 其他 task 的状态误判 running/终态——running/terminal 判定与最近一次发送任务唯一关联）；随后 mock items 含 sentTaskId → stop 渲染（items-only 支撑 queued/dispatched 窗口）；（j）**空列表**：mock `listTasksByIssue` 返回 `[]`（`AgentTaskListSchema` fallback 语义）→ 同（i）口径：items 含 → stop 渲染、items 不含 → 按钮回发送态。可达性：状态由既有 hooks/query（queue items 缓存与 task-runs 缓存，WS `task:*` 失效）驱动，布局改动不参与状态机；task-runs 查询以发送响应自带的 `issue_id` 键定，不依赖面板 `chat.issue_id` 刷新（§4.3.1 边界）。
- **AC-6** 设计落点：`ChatInputCore` 仍只依赖 `draftAdapter`（接口不变）；两宿主 `useTeamAgentDraftAdapter`/`usePrivateAskDraftAdapter` 不变；pending-message 渲染迁入 gutter 对齐块但 testid/渲染条件不变。可观测结果：`chat-input.test.tsx` adapter isolation 套件全绿（`useChatStore` 零订阅）；项目组件测试断言 `project-chat-pending-message`/`private-ask-pending-message` 仍按原条件渲染。可达性：结构性事实，无前置过滤。
- **AC-7** 设计落点：ChatInputCore 传 `ariaLabel`/`stopAriaLabel`（send_tooltip/stop_tooltip 既有 key）+ 配置控件 sr-only 类别标签（model_label/thinking_label）+ chip 内建 aria-label/tooltip + Mod+Enter 原样。可观测结果：role/name 断言——发送按钮 accessible name=send_tooltip 文案、运行态停止按钮=stop_tooltip 文案、Team Agent 只读 model/thinking 值各有「模型/思考级别」类别 sr-only 标签；Playwright **真跑**（非 `--list`，见 §6.9-3 证据契约）键盘发送 + 运行中停止（§4.3.1）。可达性：不依赖平台（Web/Desktop 共享同一组件）。
- **AC-8** 设计落点：§1.1 改动清单闭合性。可观测结果：实施 diff 范围审查——受控 `crctl git diff --name-only <基线 SHA> --cwd <resources[].multica.worktreePath>`（原生 `git` 在 controlled-shell 下被 deny，白名单核对一律经 crctl git 受控执行，路径只取 `execution_context.resources`；基线为 `117fc6be`），核对改动文件 ∈ 白名单（§1.1 表 + 测试文件 + `e2e/project-chat-composer.spec.ts` + 差异文档 + 治理 sidecar `multica/CUSTOM.md` 受控例外），无 `server/`、无 `server/migrations/`、无 API 路由/数据模型变更；普通聊天截图基线对比（`ChatInput` 路径零 diff）；差异文档存在且每条有理由。可达性：范围由提交内容静态可查（命令口径为 plan 证据命令表一条稳定 cmd-NN）。

### 组件测试与 Playwright 计划（FR-8 细化）

1. `packages/views/chat/components/chat-input.test.tsx`：ChatInputCore 套件新增——wrapper（外层 GUTTER）/surface（内层 COLUMN）两层类名断言 + surface token、底栏流布局结构、`leftAdornment` 渲染于左组、`data-slot="chat-input-surface"`；a11y——发送按钮 accessible name=send_tooltip 文案、`running+onStop` 时停止按钮 accessible name=stop_tooltip 文案；`allowSubmitWhileRunning=true` 时运行中+有内容 → 发送可用且 handleSend 放行、空输入 → 停止；未传该字段 → 运行中发送被拦（现状行为，Private Ask 依赖）。
2. `packages/views/projects/components/project-team-agent-chat.test.tsx` / `project-private-ask.test.tsx`：断言模型/思考控件 testid 现在位于 composer 区域内（`project-chat-composer`/`private-ask-composer` 子树；**不再以 `project-chat-model-row`/`private-ask-model-row` 为定位锚点**——两锚点随独立行移除，§9 移除清单）；既有三态与 PATCH 断言保持；新增——sr-only 类别标签存在（model_label/thinking_label 文案）、Team Agent 消息流根/队列栏两层 DOM 结构（外层 GUTTER 节点与内层 COLUMN 节点分离）、Team Agent 停止路径双源矩阵（§4.3.1 生命周期闭合表逐行）：mock `listTasksByIssue` 返回 **`AgentTask[]` 数组**且 `tasks.find(task => task.id === sentTaskId)` 命中的 task-runs（queued / dispatched / **running** / waiting_local_directory / completed / failed / cancelled 七态各一例），mock queue items 按服务端过滤口径只放 queued/dispatched——断言 queued/dispatched 时 stop 出现（items 含；发送成功后草稿已清空、`isEmpty=true`）、**running 且 items 不含该 task 时 stop 仍出现**（任务时间线支撑，草稿已清空）、终态时按钮回发送态（终态覆盖陈旧 items 残留）、点击 stop 调用 `cancelTaskById(task_id)`、非 cancelled 终态 → `cancel_already_finished` toast；硬降级矩阵（cycle 2 回修）：（i）首次发送即返回空 `task_id`/`issue_id` → 不渲染死按钮；（ii）**顺序分支**：活动 A（有效 sent ID、stop 渲染）→ 下一次发送成功返回空 `task_id` → 断言 stop 消失、发送态恢复且**不调用 `cancelTaskById(A)`**（两个 sent ID 已原子清空）；（iii）发送失败（mutateAsync reject）→ 旧活动目标保留（sent 状态不变）、草稿保留；断言右下角渲染**发送（重试）按钮**（无 stop Square、无 stop_tooltip 名称——草稿非空 + allowSubmitWhileRunning=true ⇒ running=false，与 §4.2 判定式一致）；随后清空草稿 → stop 重新渲染、点击仍调用 `cancelTaskById(A)`。未命中矩阵（B-005 回修）：（iv）mock `listTasksByIssue` 返回 `[]`（fallback 语义）→ items 含 sentTaskId 时 stop 出现（items-only）、items 不含时按钮回发送态；（v）返回非空数组但**不含** `sentTaskId`（含另一 task `status="running"`）→ stop 不渲染（`taskEntry=undefined`，不得以容器 Issue 其他 task 状态误判 running/终态），items 含 sentTaskId 时仍 stop（items-only）。
3. e2e 新增 `e2e/project-chat-composer.spec.ts`（或并入既有 spec）：宽面板截图（发送框 vs 消息列边缘对齐、与普通聊天 surface 视觉一致）；窄面板 360px 回归（AC-3）；运行中停止交互（AC-5/§4.3.1）与键盘发送（AC-7）。**证据契约（B-002 上游回修）**：spec 必须**真跑**作为 AC-1/AC-3/AC-5/AC-7 的浏览器行为证据——实施期在 `FRONTEND_ORIGIN` 指向运行中的前端+服务端时真跑四组用例；环境无法建立时按 ENVIRONMENT_MISMATCH 技术中止（AC-3/AC-5/AC-7 的浏览器行为面不得记为完成，test-report 记录未执行原因）；`--list` 仅证明 spec 可解析/可发现，不得冒充浏览器行为证据；packages/views 全量 `vitest run` 与交付 diff 白名单核对（经受控 `crctl git diff`，见 AC-8）各登记为稳定证据命令（plan §6.2 cmd-NN）。
4. 差异文档：`packages/views/projects/components/project-chat-composer-layout-diff.md`。

## 7. 安全与性能考量

- **权限**：Model/Thinking 控件的可编辑性完全沿用现状分支（Team Agent `canConfigure` owner/admin；Private Ask creator-only），服务端 403 强制（CR-2026-056）不变；只读徽标/runtime guide 形态保留。布局改动不新增任何可写路径。
- **数据**：不新增请求——控件数据源沿用 `runtimeModelsOptions`、`projectChatOptions`、`projectPrivateChatOptions` 等既有 query；停止路径双源复用既有缓存：queue items 与 ProjectQueueBar 同 key、task-runs 与 TeamAgentStreamView 同 key（`issueKeys.tasks`），react-query 收敛去重；底栏换行纯 CSS，无测量/无新 state。
- **可访问性**：ChatInputCore 补传 `ariaLabel`/`stopAriaLabel`（send_tooltip/stop_tooltip，与 `ChatInput` 同 key，B-002）；只读 Model/Thinking 值带 sr-only 类别标签（model_label/thinking_label）；chip 控件自带 aria-label 与 tooltip；`aria-disabled`（noAgent）不变；焦点可见性（focus-within ring）与普通聊天一致（增强）。
- **边界**：窄面板 360px、长模型 ID（truncate）、thinkingLevels 为空（不渲染 thinking 控件）、agent 为 null（不渲染工具栏）、noAgent 置灰——逐一在 §4 设计中覆盖。
- **失败模式**：CSS 类名改动最坏结果为视觉回退，无数据/事务风险；无需回滚方案（无迁移）。停止路径失败按 TSUG-007 三支降级为 toast，无状态写入。

## 9. 批准范围（契约）

- **scope_in**（本 CR 必须交付）：
  - FR-1~FR-8 全部实现条目（§6 映射表），验收 AC-1~AC-8。
  - 改动文件白名单：§1.1 表列文件（含治理 sidecar `multica/CUSTOM.md`，见下）+ 上表测试文件 + `e2e/project-chat-composer.spec.ts` + `packages/views/projects/components/project-chat-composer-layout-diff.md`。
  - **testid 保留/移除/替换清单（唯一事实，B-001 定点回修，二选一闭合为「删除、不迁移」）**：被移除的独立行锚点一律随行删除、不迁移到新容器，不存在「保留并迁到 toolbar 容器」的并存读法；清单如下：
    - **移除（共 2 项，均随独立行删除）**：① `private-ask-model-row`（Private Ask 独立模型行，§1.1/§3.2/AC-4）→ 替换锚点为新增 `private-ask-model-picker`；② `project-chat-model-row`（Team Agent 独立模型行外层容器锚点）→ **无替换锚点**：断言改用其内部四个 testid 位于 `project-chat-composer` 子树（§6.9-2）；代码事实：multica `117fc6be` 中该 testid 仅 `project-team-agent-chat.tsx` L916 一处声明点，全仓无测试/e2e 引用（本轮实读核实）。
    - **新增（共 1 项）**：`private-ask-model-picker`（Private Ask 模型控件，随 `leftAdornment` 进底部工具栏）。
    - **保留（值不变，其余全部）**：Team Agent 内部四个 testid `project-chat-model-readonly`/`project-chat-model-picker`/`project-chat-model-runtime-guide`/`project-chat-thinking-picker` 随 `leftAdornment` 原样保留；其余 `project-chat-*`/`private-ask-*` 系列（含 `private-ask-thinking-picker`、`project-chat-pending-message`、`private-ask-pending-message`、`project-queue-bar`、`project-chat-composer`/`private-ask-composer`）逐一保留且值不变。
    - 测试/e2e 断言仅随上述两个移除锚点更新（`private-ask-model-row`→`private-ask-model-picker`；`project-chat-model-row`→内部四个 testid 的 composer 子树断言）。
  - **治理 sidecar（仓库纪律 #10 强制，B-001 上游回修）**：`multica/CUSTOM.md` 纳入批准范围——实施时按该文件当时实际结构登记本 CR 新增/修改文件台账（编号顺延、原因含 CR 编号与 TASK）；该文件为 governance 台账、不承载产品代码语义，AC-8 交付 diff 白名单核对将其列为唯一受控例外出口（不因此放宽 server/API/迁移/数据模型等其余白名单项）。
  - Team Agent composer 运行中停止路径（§4.3.1/D-7，双源：queue items + 容器 Issue 任务时间线（`issueKeys.tasks`/`api.listTasksByIssue` 只读复用，返回 `AgentTask[]`，按 `tasks.find(task => task.id === sentTaskId)` 唯一选取最近一次发送的 task，空列表/未命中回落 items-only），`onStop` 复用 `useCancelProjectQueueTask`，不新增 API）；ChatInputCore 的 `ariaLabel`/`stopAriaLabel` 补传与 `allowSubmitWhileRunning` 采纳（§3.2）。
- **scope_out**（明确排除）：server 任何代码；任何 API 变更；`server/migrations/`；任务快照逻辑；数据模型；`ChatInput`（全局）视觉基线与业务语义；`useProjectChatStore` 结构；Discussion UI；mobile；新 UI 组件库/新状态管理；`ModelPicker`/`ThinkingPicker`/`SubmitButton`/`ChatAddMenu` 组件本体；draft adapter 接口。
- **zero_diff**（不得改动）：`chat-input.tsx` 中 `ChatInput`（全局）函数体与 `ChatInputProps` 签名；`ChatInputCore` props 签名；`ChatInputDraftAdapter` 接口；`packages/core/api/client.ts` 全部（含 `listTasksByIssue`/`getProjectQueueItems`/`cancelTaskById`，只读消费）；`packages/core/issues/queries.ts`、`packages/core/chat/queries.ts`、`packages/core/projects/queries.ts`/`mutations.ts`、`packages/core/realtime/use-realtime-sync.ts` 全部（`issueKeys.tasks` 与失效路径只读复用）；`useProjectChatStore` 与其 adapter hook 的读写语义；`ContentEditor` 及 editor 包；`PATCH` 端点与三态 body 语义；server 任何代码（含 queue-items 过滤口径与 `/api/issues/:id/task-runs`）；`project-team-agent-chat.tsx` 中 `handleComposerUpload`/`persistModel`/`persistThinking` 函数体、`handleSend` 的业务语义（唯一新增一条语句：成功后记录 `sentTaskId`/`sentIssueId`，§4.3.1）；testid 保留/移除/替换清单按 scope_in 唯一执行（B-001 定点回修）——移除锚点 2 项（`private-ask-model-row`、`project-chat-model-row`）随独立行删除、不迁移；替换/新增仅 `private-ask-model-row`→`private-ask-model-picker` 一项；`project-chat-model-row` 无替换锚点；其余 `project-chat-*`/`private-ask-*` testid（含 Team Agent 内部四个 testid）一律不变；locale 文件（无新 key）；`ChatInputCore` props 签名与 `SubmitButton`/`ModelPicker`/`ThinkingPicker` 组件本体。
- **follow_up**（留给后续 CR）：Discussion 面板视觉对齐（CR 顺序边界明令不混入）；mobile 端；`ChatInputCore` 与 `ChatInput` 两套 composer 实现的结构性合并去重（本 CR 只做视觉对齐，不做大重构）。

## 既有实现依赖与事实

基线：multica worktree `117fc6be657f91d43df5892b52782a18329c7aed`（requirement/CR-2026-062 分支，已含 CR-A/CR-B/CR-C 合入产物）。以下全部在该 SHA 实读核实：

1. repo: multica
   relative path: packages/views/chat/components/chat-column.ts
   stable symbol/对象: `CHAT_GUTTER`（L27）、`CHAT_COLUMN`（L30）及文件头「gutter scales with the CONTAINER, never the viewport」语义注释
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 本 CR 对齐的唯一几何事实源；@ 变体需要宿主标记 `@container`。文件头明确 gutter 必须在 cap 之外、按**两层 DOM**（外层 GUTTER > 内层 COLUMN）嵌套；单元素合并会把 gutter 计入 `max-w-4xl` 封顶（历史错位形态）——B-001 回修依据。

2. repo: multica
   relative path: packages/views/chat/components/chat-input.tsx
   stable symbol/对象: `ChatInput`（全局）wrapper `cn(..., CHAT_GUTTER, ...)`（L638）、surface `data-slot="chat-input-surface"`（L651）+ `CHAT_COLUMN` + `border-surface-border bg-surface ... focus-within:ring-2`（L659-660）、底栏 absolute 行（L738/L753）、SubmitButton `running` 判定式（L758-767：`!!isRunning && (!allowSubmitWhileRunning || hasNothingToSend || gate.uploading)`，注释「an empty composer offers Stop, while live content swaps it to Queue Send」）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 视觉对齐基准；本 CR 不修改此函数。§4.2 可见动作口径的权威模板——Team Agent 传 `allowSubmitWhileRunning=true` 时与其同语义（草稿非空→发送/重试、草稿空/上传中→stop）。

3. repo: multica
   relative path: packages/views/chat/components/chat-input.tsx
   stable symbol/对象: `ChatInputCore` wrapper `"px-5 pb-3 pt-0"`（L1066）、surface `"relative mx-auto flex min-h-16 max-h-40 ... bg-card pb-9 border-1 border-border ..."`（L1077）、编辑器 `flex-1 min-h-0 overflow-y-auto px-3 py-2`（L1088）、底栏 absolute 行（L1128/L1137）、`leftAdornment?: ReactNode`（ChatInputProps L123）、`pendingUploads`（L870）、`SubmitButton disabled` 含 `pendingUploads > 0`（L1140）、`SubmitButton` 调用只传 `tooltip`/`stopTooltip` 未传 `ariaLabel`/`stopAriaLabel`（L1144-1147）、`running={isRunning}`（L1142）、`handleSend` 门禁含 `isRunning`（L958）、`handleSend` 失败不 commitInput 保草稿（catch L1039-1042 / `accepted === false` L1044-1046 均直接 return）、成功 `commitInput()` 清空编辑器并 `setIsEmpty(true)`（L1014）、未解构 `allowSubmitWhileRunning`（ChatInputProps L102 已有该字段）、「never touches useChatStore」注释（L856）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 本 CR 改造对象；props 签名与 draft 隔离事实保持；B-002/B-003 改动点（ariaLabel/stopAriaLabel 补传、allowSubmitWhileRunning 采纳）全部发生在 `ChatInputCore` 内部。失败保草稿（`isEmpty=false`）+ `allowSubmitWhileRunning=true` ⇒ `running=false` 是 AC-5(h) 可见动作（失败回流渲染发送/重试而非 stop）的代码事实基础。

4. repo: multica
   relative path: packages/views/projects/components/project-team-agent-chat.tsx
   stable symbol/对象: `TeamAgentStreamView` 根 `"mx-auto flex w-full max-w-3xl flex-col gap-4 px-4 py-3"`（L313）；`TeamAgentComposer` wrapper `"shrink-0 border-t px-4 py-3"`（L864）、`data-testid="project-chat-model-row"` 独立行（L916，含 `project-chat-model-readonly` L925 / `project-chat-model-picker` L935 / `project-chat-model-runtime-guide` L945 / `project-chat-thinking-picker` L951）、`ChatInputCore` 使用点（L968-973，只传 `isRunning={isPending}` 不传 `onStop`——B-003 事实）、`useSendProjectChatMessage` 解构 `{mutateAsync, isPending}`（L675）、`useCancelProjectQueueTask` 已在本文件 TaskExecutionCard 使用（L499，TSUG-007 三支 L514-520）；`persistModel`（L733）/`persistThinking`（L746）调用 `patchProjectChatConfig`；L686-692 注释「api.updateAgent 不得从聊天路径调用」；**任务时间线已读取**——`ProjectTeamAgentChat` 容器 `useQuery({ queryKey: issueKeys.tasks(issueId), queryFn: () => api.listTasksByIssue(issueId), staleTime: 30_000, enabled: hasContainer })`（L98-102，`const { data: tasks = [] }` 数组消费，L8 已 import `issueKeys`）；`taskStatusKind`（L445-457，queued/dispatched/waiting_local_directory/running → "running" kind）；`TaskExecutionCard.canStop = task.status === "running" && (isOriginator || canConfigure)`（L510，取消动作经同一 mutation L514）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: Team Agent 侧改造对象；三态分支、四个内部 testid、PATCH 路径全部保留（`project-chat-model-row` 锚点随独立行移除、无替换锚点，§9 移除清单第 2 项——全仓引用核实：该 testid 仅此处 L916 声明点，无测试/e2e 引用）；B-001（两层 DOM）、B-002（sr-only）改动点所在；B-003 v2 的任务时间线事实源（`issueKeys.tasks`）已由消息流读取，composer 以发送响应 `issue_id` 自键定同 key 复用，不产生重复请求。

5. repo: multica
   relative path: packages/views/projects/components/project-private-ask.tsx
   stable symbol/对象: `PrivateAskComposer` wrapper `"shrink-0 border-t px-4 py-3"`（L392）、`data-testid="private-ask-model-row"`（L405）与 `private-ask-thinking-picker`（L420）、`ChatInputCore` 使用点（L436，disabled=running/isRunning/onStop）；`persistModel`（L327）/`persistThinking`（L340）调用 `patchChatSessionConfig`
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: Private Ask 侧改造对象；creator-only 语义不变。

6. repo: multica
   relative path: packages/views/chat/components/chat-message-list.tsx
   stable symbol/对象: 既有消息列表的权威两层嵌套——外层容器 `cn("flex-1 overflow-y-auto", CHAT_GUTTER)`（L319）、内层 `cn(CHAT_COLUMN, ...)`（L325/L373/L406）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 两层 DOM 嵌套的权威基线（B-001 回修依据）；Private Ask 消息列已对齐（证明 chat-column 常量可安全用于项目面板）；Team Agent 自绘流容器需按同一形态对齐。

7. repo: multica
   relative path: packages/views/projects/components/project-chat-panel.tsx
   stable symbol/对象: `ModePane` 根 `"flex h-full flex-col p-4"`（L199），承载 Team Agent/Private Ask/Discussion 三面板
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: `@container` 的放置点；对 Discussion 零影响。

8. repo: multica
   relative path: packages/views/projects/components/project-queue-bar.tsx
   stable symbol/对象: 根 `"shrink-0 border-t px-4 py-2"`（L61），位于消息流与 composer 之间；展开列表取消经 `useCancelProjectQueueTask`（L33，TSUG-007 三支 L39-50）；items 来自 `projectQueueItemsOptions`（服务端过滤 queued/dispatched，见 #21）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 队列栏边缘参与「消息列↔发送框对齐」链，需两层 DOM 最小对齐（B-001）；其取消语义与停止路径复用同一 mutation；其 items 查询缓存与 composer 双源之一共用同一 query key（react-query 去重）。

9. repo: multica
   relative path: packages/core/api/client.ts
   stable symbol/对象: `patchProjectChatConfig`（L3722，`PATCH /api/projects/:id/chat/config`，session_id 必填、三态 body、owner/admin 403）、`patchChatSessionConfig`（L3783，`PATCH /api/chat/sessions/:id/config`，creator-only 403）
   commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
   依赖结论: 工具栏控件的唯一写路径（本 CR 不改）。

10. repo: multica
    relative path: packages/views/agents/components/inspector/model-picker.tsx / thinking-picker.tsx / chip.ts
    stable symbol/对象: `ModelPicker`/`ThinkingPicker` `variant="chip"`（默认）+ `CHIP_CLASS`（`group flex min-w-0 ... px-1.5 py-0.5 text-caption hover:bg-accent`）；可编辑 chip 触发按钮自带 `aria-label={triggerTitle}` 与 tooltip；`canEdit=false` 只读 chip 为纯 `<span>`（值文本 + `title`，无类别可访问名称）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 工具栏控件复用对象（不新建组件）；可编辑 chip 的可访问名称/tooltip 由组件内建承载；只读 chip 的类别语义必须由宿主 sr-only 标签补齐（B-002）。

11. repo: multica
    relative path: packages/ui/components/common/submit-button.tsx
    stable symbol/对象: `SubmitButton` props（loading/busy/running/onStop/tooltip/ariaLabel/stopTooltip/stopAriaLabel）；`running=true` 分支 `onClick={onStop}`、ArrowUp/Square 均 `aria-hidden`（无 ariaLabel/stopAriaLabel 时图标按钮无可访问名称）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 右下角发送/停止按钮复用对象（不修改）；B-002 要求调用方必须传 ariaLabel/stopAriaLabel、B-003 要求调用方必须传可执行 onStop。

12. repo: multica
    relative path: packages/views/locales/en/projects.json
    stable symbol/对象: `chat.stream.model_label`="Model"、`chat.stream.thinking_label`="Thinking"、`chat.stream.runtime_guide`（en/ja/ko/zh-Hans 四语目录均存在，parity.test.ts 覆盖）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 无新增文案 key（NFR-3）；runtime guide 文本继续复用。

13. repo: multica
    relative path: packages/core/api/schemas.ts
    stable symbol/对象: `ProjectChatSendResult`（L1524-1529，含 `task_id` 与 `issue_id`；`ProjectChatSendResultSchema` L1531-1537 二者为 UUID 必填，fallback 时整体降级为空串）；`QueueItem`（L1736，`task_id`/`status`/`originator`；items 由服务端过滤为 queued/dispatched）；`AgentTaskSchema.status: z.string().default("cancelled")`（L2261）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 双源数据事实源——停止目标（send 返回的 task_id）+ 容器 Issue id（send 返回的 issue_id）+ 两个活动性事实源（items 与 task-runs）的 schema 边界。

14. repo: multica
    relative path: packages/core/api/client.ts
    stable symbol/对象: `sendProjectChatMessage`（L3756，POST /api/projects/:id/chat/messages，返回 `ProjectChatSendResult`）；`cancelTaskById`（L3569，POST /api/tasks/:id/cancel，终态任务返回幂等 200 携带真实状态）；`listTasksByIssue`（L2478，GET /api/issues/:id/task-runs，返回 `Promise<AgentTask[]>`；`AgentTaskListSchema`（schemas.ts L2300，`z.array(AgentTaskSchema)`）解析失败 fallback `[]`；服务端缺省路径全量返回无分页截断）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 发送返回（task_id/issue_id）、取消端点与任务时间线端点的既有契约（本 CR 不改，只消费）。

15. repo: multica
    relative path: packages/core/projects/mutations.ts
    stable symbol/对象: `useSendProjectChatMessage`（L63-77，返回 `{mutateAsync, isPending}`，isPending=本地入队窗口；onError 仅 409 失效 `projectKeys.chat`——成功路径不失效）；`useCancelProjectQueueTask`（L93-106，`mutateAsync(taskId)`、onSettled 失效 `projectKeys.queueStatus` 前缀含 items；TSUG-007 三支语义）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 复用对象——停止路径与 TaskExecutionCard/ProjectQueueBar 同一 mutation、同一竞态/错误语义；无新增请求；`projectKeys.chat` 成功路径不失效（全局 staleTime=Infinity，query-client.ts）是 composer 用发送响应 `issue_id` 自键定任务时间线的依据（§4.3.1 边界）。

16. repo: multica
    relative path: packages/core/projects/queries.ts
    stable symbol/对象: `projectQueueItemsOptions`（L59，queryKey=`projectKeys.queueItems(wsId, id)`=queueStatus 前缀 + `"items"`，WS `task:*` 前缀失效；服务端过滤 queued/dispatched，见 #21）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: composer 双源之一（queued/dispatched 窗口）与 ProjectQueueBar 共用同一 query 缓存（react-query 去重），NFR-4「不新增重复请求」成立；items 不含 running 是 B-003 v2 引入任务时间线源的原因。

17. repo: multica
    relative path: packages/core/issues/queries.ts
    stable symbol/对象: `issueKeys.tasks(issueId)`=`["issues","tasks",issueId]`（L179）；`issueKeys.tasksAll()`（L177）注释「any task lifecycle event refreshes every per-issue list, regardless of which issue is currently mounted」
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 任务时间线事实源的 query key——composer 以发送响应的 `issue_id` 键定（`issueKeys.tasks(sentIssueId)`），与 TeamAgentStreamView 同 key 时收敛为同一缓存，不产生重复请求。

18. repo: multica
    relative path: packages/core/types/agent.ts
    stable symbol/对象: `AgentTask.id: string`（L279，任务唯一键）；`AgentTask.status` 联合：`"queued" | "dispatched" | "waiting_local_directory" | "running" | "completed" | "failed" | "cancelled"`（L291-298）；`waiting_local_directory` 注释「Treated as an active (non-terminal) state alongside queued/dispatched/running by every consumer that buckets tasks into "active vs done"」（L286-290）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: B-003 的 ACTIVE/TERMINAL 集合定义事实源——ACTIVE={queued,dispatched,waiting_local_directory,running}、TERMINAL={completed,failed,cancelled}，与既有 active-vs-done 分桶口径一致；`AgentTask.id` 是 `taskEntry = tasks.find(task => task.id === sentTaskId)` 唯一选取的键（B-005 回修依据）。

19. repo: multica
    relative path: packages/core/realtime/use-realtime-sync.ts
    stable symbol/对象: `task:` 前缀失效：`qc.invalidateQueries({ queryKey: ["issues","tasks"] })`（L926）与 `projectKeys.queueStatusAll(wsId)`（L902）；WS 断线重连时 `issueKeys.tasksAll()`（L683）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: 双源的实时性保障——任一 task 生命周期事件（含 task:running/task:completed）同时刷新任务时间线与 queue items，composer 无需新增订阅/轮询；B-003 v2 生命周期闭合的时效前提。

20. repo: multica
    relative path: server/internal/service/project_chat.go
    stable symbol/对象: `sendProjectChatCore` 经 `CreateAgentTask`（task.go L1655-1660）以 `IssueID: issue.ID`（容器 Issue）创建 Team Agent 任务；send 成功后广播 `EventCommentCreated`/`EventTaskQueued`（L557/L578）
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: Team Agent 任务**必然出现在容器 Issue 的 task-runs 列表**（`/api/issues/:id/task-runs`），且 task-runs 生命周期覆盖 queued→dispatched→running→terminal——B-003 v2 用任务时间线覆盖 running 的成立前提（服务端事实，本 CR 不改）。

21. repo: multica
    relative path: server/pkg/db/queries/agent.sql
    stable symbol/对象: `ListProjectPendingTasks`（L2947-2961）注释「identical pending reading (queued + dispatched on the project's issues)」，WHERE `i.project_id = $1`
    commit SHA: 117fc6be657f91d43df5892b52782a18329c7aed
    依赖结论: queue items 服务端过滤口径的权威事实——items 只含 queued+dispatched，任务 running 后离开列表；这是 B-003 v2 必须引入任务时间线作为 running 事实源的原因（服务端契约保持，zero_diff）。

## SDD-CLOSE 关闭记录

- **SDD-CLOSE-01** PRD §1.2 规则 3「输入区、附件预览、底部工具栏分层」→ 关闭：§4.2 flow 两层结构 + 编辑器 `overflow-y-auto`；附件预览仍由 ContentEditor 在编辑器区内承载（与普通聊天同构）。判定覆盖数据生产/消费与兼容降级：本项纯渲染分层，无数据生产/存储/传输/schema/降级层，无遗漏层。
- **SDD-CLOSE-02** PRD §1.2 规则 4「leftAdornment 或等价底部工具栏 slot」的机制选定 → 关闭：选定现有 `leftAdornment`（D-3），§3.2 给出两宿主构造契约。
- **SDD-CLOSE-03** PRD §1.2 规则 2/FR-1「复用单一输入 surface、对齐」的落地类名集合 → 关闭：§4.1-2 逐类名给出（border-surface-border/bg-surface/rounded-lg/focus-within ring），且全部对齐块均为外层 `CHAT_GUTTER` > 内层 `CHAT_COLUMN` 两层 DOM（B-001 回修）。
- **SDD-CLOSE-04** 来源完成标志「差异说明文档」的落点与内容 → 关闭：`packages/views/projects/components/project-chat-composer-layout-diff.md`（D-6）；最小内容大纲：a) 消息列/队列栏/发送框共用 CHAT_GUTTER+CHAT_COLUMN 两层嵌套的说明；b) 底栏 flow 布局与普通聊天 absolute 行的等价性；c) surface `max-h-40`（vs 普通聊天 `max-h-96`）保留理由；d) Model/Thinking 可见文字 label 不再常驻、chip+tooltip 承载，类别语义由 sr-only 标签保留；e) Team Agent composer 停止作用于最近一次发送 task 的语义（其余任务仍由队列栏逐条取消），含双源生命周期闭合表（queued/dispatched 由 queue items、running/waiting_local_directory 由任务时间线（`AgentTask[]`，`tasks.find(task => task.id === sentTaskId)` 唯一选取，未命中回落 items-only），终态覆盖）与失败回流可见动作口径（保草稿 → 发送/重试按钮，清空草稿 → stop 重新出现，§4.2 判定式）。每项均须给出「是否必要差异 + 理由」。

- **SDD-CLOSE-05** PRD FR-5/规则 5「右下角复用发送/停止按钮和 loading、上传中、运行中状态」在 Team Agent 侧的运行态来源与停止语义（PRD 未给落点）→ 关闭：§4.3.1/D-7（`sentTaskId`/`sentIssueId` + 双源活动性——queue items 覆盖 queued/dispatched、容器 Issue 任务时间线（`AgentTask[]`，`tasks.find(task => task.id === sentTaskId)` 唯一选取，未命中回落 items-only）覆盖 running/waiting_local_directory/终态，终态覆盖闭合 queued→dispatched→running 全生命周期 + `useCancelProjectQueueTask`；send/stop/retry 业务行为与权限不变，零新增 API；失败保草稿 → 发送（重试）按钮、清空草稿 → stop 重新出现，可见动作与 §4.2 `running` 判定式唯一一致（AC-5(h) 落点））。

## CR-P0 流程正确性止血 — `_context.md` 合同退役、Prompt 源/overlay 归位、委派合同收紧、crctl 原子性与错误可操作化（v0.36 · CR-2026-063）

## 0. 阅读约定

- 本 SDD 的技术输入是 `change-requests/CR-2026-063/prd.md`（修订 0.1.1，SHA256 `9247c107b1f87b72a5ee4ec5750f2f1da8be784aed04d23f47bb8d153eabda70`，已人工审批绑定）。**本 SDD 不改 `prd.md`**；所有措辞修正、口径补充、被 PRD 显式延后到 SDD 的设计项均只写在本文件。
- 正文对既有实现的引用一律以 `dep-N` 形式指向第 10 节「既有实现依赖与事实」的唯一定义（第 10 节按正文首次出现顺序编号）；正文不复述既有行为细节，避免第二份事实定义。
- 路径 authority：所有代码事实只按 `crctl workspace inspect CR-2026-063` 返回的 `resources[].worktreePath` 取（本 CR 三个资源见 §1.4），**不拼接** `.rayai-worktrees/...`，不回退主工作区。

## 1. 架构概览

### 1.1 变更性质：原位修订，不新增架构层

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

### 1.2 模块边界与依赖方向

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

### 1.3 关键流程

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

### 1.4 多仓边界与提交/checkpoint 口径

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

## 2. 数据模型

### 2.1 无 DDL / schema 变更（N/A + 理由）

本 CR 不涉及数据库 schema、迁移、迁移登记或写路径鉴权（PRD §1.3.3：本 CR 不新增 API、子命令、账本字段或账本条目；`reset` 的权限模型沿用既有"仅交互式 TTY 人类在环"约束）。因此**不触发** write-tech-design 的"数据/schema 变更与写路径鉴权完整性"条件节；不涉及 down migration、约束缺失窗口或 DDL 规范。

### 2.2 受影响的数据实体（全部为既有文件，结构不变）

| 实体 | 位置 | 本 CR 的影响 | 结构 |
|---|---|---|---|
| `review-loop.yml` | `change-requests/{CR-ID}/review-loop.yml` | 写入路径由"直写 + 无 CAS + 无 commit"改为"单文件 ledger 事务 + commit"；语义（`current-cycle+1`、`current-attempt=0`、`attempts[]` 保留）不变 | **不变**（仍由 `renderLoopText` 全量生成，LF-only，dep-11） |
| ledger journal | `{toolsRoot}/.crctl/transactions/ledger/{key}/{txId}` | `reset` 首次使用该域：键 `reset-{CR-ID}-{loopRef}`（`ledgerTxKey`，dep-3） | **不变**（沿用既有 envelope 与 write-set slot，dep-8） |
| `gate` 错配错误体 | stderr JSON | 新增两个字段 `contractDrift`、`recoverCommand` | 既有 `{error:{code,message,...extra}}` 形态不变（dep-1） |
| `CUSTOM.md` #75 行 | `multica/CUSTOM.md` | 第 3 列（职责/改动）单元格文本重写 | 表结构与列语义不变（dep-24） |
| 四类 Prompt/文档 | multica 3 个 prompt + tools 1 个 agent prompt + tools 5 处 SKILL.md | 段落级原位替换/补写 | 文件结构（章节、frontmatter、表格列）不变 |

无新增实体、无新增字段落到任何账本文件。

### 2.3 文件级回滚语义（`reset` 的数据变更回滚）

`reset` 是本 CR 唯一的"数据变更 + 回滚"复合改动，其回滚语义按既有机制族给出（dep-8、dep-3）：

| 阶段 | 崩溃/失败点 | 回滚依据 | 回滚后状态 |
|---|---|---|---|
| apply 完成、complete 前 | journal `phase=prepared`/`written` | `recoverLedgerTransaction` 读 journal payload 的 `beforeText` 逐条还原 | 文件回到执行前内容 |
| 提交隔离前置不成立（执行前已有 staged 变更） | 不进入 commit（步骤 12 判定） | 同下一行（不 commit 本身也是回滚理由） | 文件与 index 回到执行前；**外来 staged 变更不属本命令，不被回滚也不被夹带**（随后 clean 复核将不过 → `..._ROLLBACK_FAILED`） |
| commit 失败（进程内） | 事务对象仍在手 | `abortLedgerTransaction(tx)` + `syncLedgerIndex` | 文件与 index 都回到执行前（执行前 tracked-clean 时为完全 clean） |
| commit 成功后、complete 前 | HEAD 含 `AI-First-Tx: <txId>` | `recoverLedgerTransaction` 用 trailer 判定"已提交"，只清 journal | 保留已提交事实，不重复写入 |

部分状态语义：**不存在"文件已改但 index 未改"的可观测中间态**——失败路径先还原文件再 `git add -A -- <relpath>` 使 index 与还原后内容一致（dep-3 `syncLedgerIndex`）。**恢复链自身失败**（journal 还原遇第三值、index 恢复的 `git add` 失败等）不产生第三种中间态：它先落审计再以 `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED` 退出，**不得**以内部 `TX_*` 码对外（§3.2、§3.5、§4.2.1 步骤 13）。

## 3. 接口契约

### 3.1 `crctl gate --mode pre-review` 错配错误体（FR-7）

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

#### 3.1.1 `contractDrift` 恒为 `true` 的定位（PRD 显式延后到 SDD 的设计项）

- 本字段**不携带区分信息**：本 CR 只有一种错配形态（`--mode pre-review` 与非 requirement stage 组合），因此恒为 `true`。
- 它的语义是**固定提示**："该调用与版本化 Skill/Pipeline 的声明不一致，须复核权威 Skill/Pipeline"。它**不是**漂移类型分类器，调用方**不得**据此反推"漂移发生在本轮调用的哪一侧"。
- 调用方的正确处理：停止按当前参数重试 → 按 `recoverCommand`（`crctl workspace inspect <CR-ID>`）复核 workspace 与 resources → 回到对应 stage 的权威 Skill/Pipeline 声明的门禁入口。
- 结构化恢复合同（`recoverCommand` → `recovery`）属独立 CR-R（PRD §7），本 CR 只保证字段存在且值确定。

### 3.2 `crctl review-loop reset` 命令契约（FR-9）

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

### 3.3 `beginLedgerTransaction` 的 ledger write-set 前置条件（FR-9 第 3 条，内部契约）

| 项 | 改造前 | 改造后 |
|---|---|---|
| 前置条件 | `writes.length < 2` → `TX_WRITESET_INVALID`（dep-8） | `writes.length < 1` → `TX_WRITESET_INVALID` |
| 空 write-set | 由本前置条件与 `applyWriteSet` 双重拒绝（dep-8） | 仍被双重拒绝（行为不变） |
| 单文件 write-set | 被拒 | 接受，走同一 prepare/apply/rollback 路径 |
| 既有 4 个调用点（`approve`/`owner-set`/`version-set`/`review-record`，文件构成与行号见 dep-8） | 全部 ≥2 文件 | **零行为差异**（全部满足 `< 1` 判定） |
| journal / manifest 结构、`recover`/`abort`/`finish` 语义、导出面 | — | **零改动**（PRD §1.3.1 第 11 行"仅放宽前置条件"） |

### 3.4 非 CLI 契约

**A. `lint-prompts` R7 判定契约（FR-8）**

- 触发（行级，判定面与既有 R7 子判据一致，均为"段落内逐行"）：同一行同时满足 `\bgate\b` 与子串 `--mode pre-review`。
- 必要条件：同一行包含 `--for requirement-reviewing`。
- 违反输出：`rule = R7`，`level = CONTRADICTS`，`file:line` + why，**不新增规则编号**（不引入 R14 之类）。
- 豁免：沿用既有 `<!-- lint-prompts:ignore -->` ±1 行机制（dep-15）；`--mode report` 仍退出 0，`--mode enforce` 命中即 `LINT_DRIFT` 退出 1。
- 声明边界：本规则只防**版本化 Prompt 漂移**，不声称约束真实运行期评论（PRD FR-8 约束段）。

**B. Prompt 文本契约（FR-1/FR-3/FR-5/FR-6）**

- multica 两份部署副本：`_context.md` 段落被 §6 FR-1 给出的目标文本原位替换（该目标文本按 owner 授权**口径甲**落地：保留「不得创建或读取上下文副本」的禁止语义、**不写出文件名指称**；授权记录见 §6.5）；替换后两份文件均不出现 `_context.md` —— 该「不出现」按**文件级字面检索**判定（与 §4.5 同口径），判定面与 AC-1①/AC-2 均**未变**。
- coordinator overlay：三节的目标文本**逐字固化在本 SDD §6.2**（含三块的替换边界、旧块/替换块的逐块 `sha256`、LF 归一口径与来源文件 SHA256）；实现期**逐字复制，不得转述**，不得改写标点、空格、换行或代码标记（AC-5 的锚点因此落在 CR worktree 内，不再依赖 worktree 之外的来源副本）；**块 3 按 §6.2 的两行替换块固化（旧 bullet 逐字保留 + 行首两空格的插入行）**，不是“在节内找个位置插一段”的自由形式；其余四节与 frontmatter 保持原样。
- `tools/agents/dev-agent.md`：`## 委派路由合同（评审）` 内含六条要求（新 task/run、Runner、只传声明输入与 canonical 引用、不复述步骤/门禁/advance/修法、只读 `BAD_ARGS` 可恢复一次、版本化来源错误须同时报 `CONTRACT_DRIFT`）。
- `CUSTOM.md` #75 职责单元格含五要素（AC-3）。

**C. HTTP / REST 契约**：N/A。本 CR 不新增或修改任何 HTTP API，不触发 FR-08 的条件基线。

### 3.5 契约确定性四查（对应 PRD §1.3.3 的落点）

| 检查 | `gate --mode pre-review` 错配（FR-7） | `review-loop reset`（FR-9） |
|---|---|---|
| 幂等 | 只读路径，可任意重放，无副产物 | 以 expected hash 为前提；同命令残留按 journal 恢复；重复调用在"未耗尽"时拒绝（不产生第二个 cycle） |
| 权限 | 无权限面（零写入只读 CLI） | 既有 TTY 人类在环硬检查，无旁路；不改 `rules.json`（受控 git 仍按既有白名单三元组放行） |
| 错误闭包 | `BAD_ARGS` + `contractDrift` + `recoverCommand`（§3.1） | `NOT_TTY` / `BAD_ARGS` / `UNKNOWN_LOOP` / `LOOP_NOT_EXHAUSTED` / `CAS_CONFLICT`（事务内抖动）/ `REVIEW_LOOP_RESET_COMMIT_FAILED`（步骤 12 隔离断言不成立或 commit 命令失败）/ `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED`（步骤 13 恢复链任一环失败，镜像 dep-5）。**对外错误闭包到此为止**：恢复链内部抛出的 `TX_JOURNAL_INVALID` / `TX_RECOVERY_CONFLICT`（dep-8 的 journal 还原）与 `TX_GIT_FAILED`（dep-26 的 index 恢复）是**内部底层原因**，一律由步骤 13 的本地 catch 映射为上述唯一码后对外，不得以 `TX_*` 形式退出（§3.2「失败输出（回滚未完成）」行、§4.2.1 步骤 13） |
| 副作用 | 零写入 | 单文件 commit + 审计一条；**两条失败路径同样落审计**（`kind=review-loop-reset`、`result: commit-failed`，含 `fromCycle`/`toCycle`/`reason`/`by`，不新增字段）；无 outbox、无状态推进、无网络 |

## 4. 关键算法与流程

### 4.1 `cmdGate` pre-review 分支的错配返回（FR-7）

#### 4.1.1 `recoverCommand` 的取值算法（确定性 + 无自由输入）

```text
输入：cr（cmdGate 的位置参数，即被调用的 CR）
1. crId = /^CR-\d{4}-\d{3,}$/.test(String(cr)) ? String(cr) : '<CR-ID>'
2. recoverCommand = `crctl workspace inspect ${crId}`
```

- **为什么内插 CR**：PRD FR-7 第 3 条要求"`<cr_id>` 取自被调用的 CR"——恢复方向必须指向本次调用的对象，才是可执行方向。
- **为什么先做语法判定**：CR-ID 是本命令自身的位置参数（命令主语），不是自由文本；但 `requireCr()`（dep-6）只判"非空"，不判语法。加一层语法判定后，任何非规范形态的回退为占位符 `<CR-ID>`，从而保证恢复串**永不包含任意 argv 文本**，满足 NFR-3「不含任何用户输入」与 AC-7「固定字符串、不含任何用户输入」的严格读法。
- 占位符形态有既有先例：`crctl test` 的 `recoverCommand` 同样带 `<plan>` / `<worktree>` 占位符（dep-11）。
- 该 helper 供 FR-7 与 FR-9 共用（一处定义、两处调用，避免复制正则）。

#### 4.1.2 判定树

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

### 4.2 `cmdReviewLoopReset` 原子提交时序（FR-9）

#### 4.2.1 步骤

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

#### 4.2.2 崩溃/失败窗口真值表（AC-9① ② 与 FR-9 第 4 条的判定口径）

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

### 4.3 `lint-prompts.mjs` R7 配对判定算法（FR-8）

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

### 4.4 `_context.md` 退役后的 post-review 漂移判定（FR-1③）

删除 `allowed` 集合中的该条目后（dep-10），漂移判定保持既有算法不变：

```text
unexpected = changedPaths(reviewedSha..HEAD) \ (allowed ∪ review-annotations/ 前缀)
unexpected 非空 → bad('code', { reason:'post-review-path-drift', repo, unexpected })
```

删除后的语义 = `_context.md` 与任意其它非白名单文件同等处理（评审后新增或修改 → 拒绝）；**不新增** `crProcessCachePath()`，**不放宽** `classifyRepoWorkspace()` 的 dirty 语义（PRD FR-1③ 明文）。

### 4.5 AC-2 的检索核对算法（口径落地，PRD §1.5 已由人工审批确认）

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
## 期望：无输出（命中数 0）

Get-ChildItem -Path (Join-Path $repo 'skills\shared\crctl\scripts\test') -Recurse -File `
  | Select-String -Pattern '_context.md' -SimpleMatch
## 期望：仅退役测试的负向断言（测试名/断言字符串），无正例放行断言
```

判定与证据要求：

- 字面量检索不受行尾差异影响；命中清单仍须按工作区纪律 #1 报"检索命令 + 归一后行号"。
- 排除集合内的每一处命中都必须能读出「拒绝 `_context.md`」语义；出现任何「放行 `_context.md`」的正例断言即判不通过（AC-2）。
- 该判定是**人工逐条 + 命中清单证据**（S-5：机械化属新 lint/新规则范围，不在本 CR）。
- **口径注（口径甲，§6.5 授权记录）**：计入集合的判定为**文件级字面检索**（`-SimpleMatch`、无排除面、无语义豁免）；multica `cr-prompts-revised/dev-agent.md` 的替换段落按 §6 FR-1① 的**授权版**落地（不含该文件名指称、保留「不得创建或读取上下文副本」的禁止语义），因此「计入集合命中 0」与替换段落的禁止语义**不冲突**；本 CR **不采用**「禁止句不计入活跃合同引用」的语义口径（口径乙）。集合、阈值与判定方式均保持上文原样、未变。

### 4.6 验收证据命令契约（AC-12 全量回归分区 / `crctl test` 执行语义）

本节固定 canonical 证据命令（`plan.md` 证据命令表 → `cr-test-plan/v1` → `crctl test`）必须满足的契约；它是 AC-12 可达性的前提，也是本轮上游回修 B-04/B-05 的 SDD 侧落点（执行细节仍由 `write-test-report` 与 `crctl test` 承担，本 CR 不改它们）。

#### 4.6.1 执行语义（既有契约，不得假设其它语义；dep-28）

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

#### 4.6.2 AC-12 全量回归分区

- **全集定义（枚举，不断言计数）**：`tools/skills/shared/crctl/scripts/test/` 下全部 `*.test.mjs`（本轮枚举 **21** 个，逐文件清单见 §6.3）。该目录另有 1 个非测试辅助模块 `merge-fixture.mjs`（被测试 import、不含 `test()`）：plan 必须对其给出显式处置（纳入某条命令以证明可加载，或声明非测试文件并给出依据），**不得静默遗漏**；两类文件的并集 = 目录内全部 22 个文件（旧 plan 的"22 个"是目录文件总数；`*.test.mjs` 枚实为 21 个 —— 计数口径必须以枚举派生，不得写成断言）。
- **无重不漏分区**：全集必须被 canonical `cmd-NN` 的 args **恰好一次**覆盖——各命令的测试文件集合两两不相交，并集等于全集。不得把任何文件留在 `cmd-NN` 之外以"implement 期验证项"形式承载（那样没有 `sourceRevision`/日志绑定，也无固定证据）。
- **预算可达**：全集单跑实测 **857 s**（§6.3：21 个文件、dot reporter、exit=1 因 5 条登记基线红），加上 lint 与断言类命令后必须落在 `write-test-report` 节点 `timeoutMinutes=20` 的预算内；任一条命令的 `timeoutSeconds` 必须 ≥ 该命令实测时长。
- **例外锚定**：`--test-skip-pattern` 只准排除 §6.3 登记的 5 条**完整测试名**，模式必须是这些名字（正则元字符转义后）的**锚定交替**（`^(?:名字1|名字2|…)$`）；**禁止**未锚定片段（片段会连带静默跳过名字包含该片段的新用例 → 假绿）。fail-closed：例外拼写失效 → 该用例真跑 → 红 → exit 1。
- **`skipped` 语义**：全部命令统一 `--test-reporter=dot`（冻结模式表会把 node 默认 spec reporter 摘要中的 `skipped` 字样误判为 skip）；任一命令 `skipped=true` 不接受为通过。

## 5. 技术选型与替代方案

按 write-tech-design Step 2.5 的三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代）记录 3 条决策；不满足三判据的事项不记录（§5.4 列出未记录项及理由）。

### 5.1 D-1：单文件 write-set 走"原位放宽前置条件"

- **Decision**：`reset` 的 write-set 只含 `review-loop.yml`，把 `lib/durable-tx.mjs` 的 `writes.length < 2` 原位放宽为 `< 1`（dep-8）。
- **Context**：`reset` 唯一需要提交的账本文件是 `review-loop.yml`（`auditLog` 走 `.crctl/` 审计域，不进 git 事务）；既有 4 个 ledger 事务调用点全部 ≥2 文件，无单文件先例；该前置条件当前**无测试守卫**（dep-8 事实条目）。
- **Alternatives**：
  - (a) 原位放宽共享前置条件（采用）；
  - (b) write-set 中塞入一个内容不变的第二个文件：会让"commit 只包含 `review-loop.yml`"（FR-9 第 4 条）与 FR-11 的零无关改动口径变成假象；
  - (c) 绕开 `beginLedgerCommand` 自建写入路径：被 FR-9 第 7 条禁止，且单文件直写不提供崩溃可恢复与 index 回滚，无法满足 AC-9②。
- **Consequences**：单条目与多条目的 prepare/apply/rollback 路径同构（逐条 CAS、逐条 before 快照），故 4 个既有调用点零行为差异；空 write-set 仍被双重拒绝；代价是共享原语的边界值语义被放宽，风险由 AC-9⑥ 的可验断言 + 既有 4 调用点事务测试全绿兜住。

### 5.2 D-2：`reset` 提交失败使用 op-scoped 错误码

- **Decision**：新增 `REVIEW_LOOP_RESET_COMMIT_FAILED` / `REVIEW_LOOP_RESET_COMMIT_ROLLBACK_FAILED` 两个错误码，不改变 `BAD_ARGS`/`NOT_TTY`/`LOOP_NOT_EXHAUSTED` 三条既有码。
- **Context**：`reset` 改造后首次出现"提交失败但事务已回滚"这一可观测结果；调用方（人类在 TTY）需要区分"参数/状态不对"与"提交失败但不留中间态"。
- **Alternatives**：(a) 新增 op-scoped 码（采用，与 `OWNER_COMMIT_FAILED`/`VERSION_SET_COMMIT_FAILED` 同族，dep-5）；(b) 复用 `TX_GIT_FAILED`：该码语义是"回滚后 index 恢复失败"（dep-3），用它表达"提交失败已回滚"会丢失关键区分度；复用裸 `BAD_ARGS` 则完全丢失"已回滚"这一事实。
- **Consequences**：两个码各有唯一产生点（§4.2.1 步骤 12/13）：`..._COMMIT_FAILED` = 隔离断言不成立或 commit 命令失败；`..._ROLLBACK_FAILED` = 恢复到干净基线的恢复链未完成（含执行前已有 staged 变更时 clean 复核不过的情形）。CR-R 迁移结构化 `recovery` 时，这两个码与 `recoverCommand` 一并在同 CR 内替换（PRD §7 的 CR-R 边界）；错误码是新增的对外可观测面，属"错误闭包"的必要组成（PRD §1.3.3 已把 FR-9 列入四查面）。

### 5.3 D-3：`recoverCommand` 内插规范形态 CR-ID

- **Decision**：恢复串为 `crctl workspace inspect <CR-ID>` / `crctl review-loop reset <CR-ID> --loop <ref> --reason <reason>`；CR-ID 仅在匹配 `^CR-\d{4}-\d{3,}$` 时内插，否则回退占位符 `<CR-ID>`；`reason` 一律用占位符（§4.1.1）。
- **Context**：PRD FR-7 第 3 条要求 `<cr_id>` 取自被调用的 CR（可执行方向），而 FR-7/AC-7 与 NFR-3 同时要求"不含任何用户输入"（防止把用户文本拼进可被复制的命令）；两者在"CR-ID 是否是用户输入"上存在读法差异。
- **Alternatives**：(a) 语法判定后内插（采用）；(b) 一律输出纯字面模板 `crctl workspace inspect <CR-ID>`：绝对满足"固定字符串"，但丢失"取自被调用的 CR"、方向不可直接复制；(c) 无条件内插：把任意 argv 文本引入恢复串，直接违反 NFR-3 的立意。
- **Consequences**：正常 CR-ID（工作区唯一真实形态）得到可执行方向；畸形 argv 退化为占位符，恢复串在任何输入下都不含自由文本；代价是多一层 3 行语法判定（与既有 `archive` 的 `/^CR-\d{4}-\d{3,}$/` 校验形态一致）。

### 5.4 未记录为决策的事项（不满足三判据）

| 事项 | 不记录理由 |
|---|---|
| `contractDrift` 恒为 `true` | 不可逆性低、无真实替代方案（本 CR 只一种错配形态），按 §3.1.1 作为设计说明，不立决策 |
| R7 配对判据的行级判定粒度 | 与既有 R7 四类子判据同族，属同构选择，无实质权衡 |
| `_context.md` 退役的落地方式 | 已由来源文档 §1.2 与 PRD 拍板（删除为主，不迁移、不新增生成器），非本 SDD 待决项 |

## 6. FR 到技术实现映射

标注列含义：**落点** = 承载改动的仓/文件/位置；**原位落法** = 说明该改动是替换/删除/补写，而非追加第二套；**AC** = 覆盖该 FR 的验收标准。

### FR-1 `_context.md` 活跃合同退役

| # | 落点 | 原位落法 | 目标内容 | AC |
|---|---|---|---|---|
| ① | `multica` `cr-prompts-revised/dev-agent.md`（`## 环境与代码边界` 末段，基线 L45–49） | **整段替换**（不得"保留旧段 + 段后追加说明"） | 目标段落原文（保留反引号格式；**口径甲授权版：末句不含文件名指称**，见 §6.5 授权记录）：「不得手工修改受控账本、`review-annotations`、`review-loop`、`traceability` 或 `specs/`；对应写入必须经专用 Skill/crctl。恢复或返工时直接读取 `crctl status {cr_id}`、`crctl next {cr_id}`、`cr.md`、`review-loop.yml` 与 canonical review annotations；不得创建或读取上下文副本，也不得让缓存替代状态、评审证据或门禁。」 | AC-1① |
| ② | `multica` `cr-prompts-revised/quality-reviewer-agent.md`（`## 入口识别与证据` 首段，基线 L19） | 段内**删除** `_context.md` 引用并改写为 canonical 口径 | 首句保留"不凭评论文字猜阶段"；证据面改为 `dir-graph.yaml` + `crctl status/next` 返回 + 当前 CR canonical 产物 + 该 Skill 指定证据，并保留"canonical 事实优先于缓存、评论和执行方自报"（两处落点基线 dep-22） | AC-1② |
| ③ | `tools` `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（post-review `allowed` 集合，基线 L1317–1318） | 删除**条目 + 其上方注释**；不新增 `crProcessCachePath()`、不放宽 `classifyRepoWorkspace()` | 删除后判定见 §4.4（dep-10） | AC-1③ |
| ④ | `tools` `skills/shared/crctl/scripts/test/crctl.test.mjs`（CR-2026-057 白名单测试，基线 L4554 起） | 同一测试**原位改为退役合同测试**（禁止"保留原测试 + 旁边新增反向测试"） | 断言改为：① 评审后新增/修改 `_context.md` → `RELEASE_SUBJECT_DRIFT` / `reason=post-review-path-drift` 且 `approval.yml` 零写入；② `_context2.md` 非白名单断言保留（证明不存在前缀式放宽）（测试基线 dep-12） | AC-1④ |

**① 目标段落文本的口径授权（口径甲，§6.5）**：① 行的目标段落原文**不含 `_context.md` 文件名指称**，末句为「不得创建或读取上下文副本，也不得让缓存替代状态、评审证据或门禁」——禁止语义与需求来源 §3.1.1 的替换块一致，只去掉文件名指称；**判据不动**：AC-1① 的「两份副本文件内 `_context.md` 命中 0」与 §4.5/AC-2 的计入集合字面 grep 归零（含 multica `cr-prompts-revised/` 全文件）均按原样执行；`prd.md`（`9247c107…`）保持审批版本、不改动。裁决人/裁决时间/权威评论/授权范围与边界见 §6.5。

### FR-2 活跃引用全量核对

- 落点：**无代码改动**；交付物是"检索命令 + 命中清单"证据（§4.5）。
- 原位落法：不适用（核对项）。历史 CR 目录、历史 `traceability.yml`、归档 delivery 证据不改。
- AC：AC-2。

### FR-3 Prompt 事实源归位（`CUSTOM.md` #75）

- 落点：`multica` `CUSTOM.md` 第 387 行所在第 75 行，**第 3 列（`改动`，即该行职责单元格）**。
- 原位落法：**同一单元格内重写**，不新增登记行、不改表结构、不动其它行；第 5 列（`合并注意`）现有的"与 tools 仓实际生效 prompt 分叉时以 tools 仓为准并人工对齐"与新口径一致，无需改动；第 4 列（`原因 / 追溯`）记录的是该目录内容的来源提交（历史 provenance），不构成"公共副本是独立事实源"的声明，故不改动（最小 diff 面，满足 AC-3 的"其它行文字零 diff"）。
- 目标内容（五要素齐备）：公共 Agent Prompt 唯一事实源为 `tools/agents/`；`cr-prompts-revised/cr-coordinator-agent.md` 是 Multica 专属 overlay；目录内公共 Prompt 副本**不再独立演进**（原"仓库侧快照"定性由本单元格取代），owner 部署时以 tools 同名文件覆盖平台公共 Agent；DB 是部署投影、不是事实源（禁止把 DB/UI 临时编辑反向当规范）；`cr-coordinator-agent` 不进入 tools agent index。
- AC：AC-3。

### FR-4 矩阵与索引不改动（反向验收对象）

- 零改动清单：`tools/agents/_index.yml`（仍 9 个 agent）、`tools/agent-skill-matrix.yml`（保留 `cr-coordinator-agent` system actor 声明）、`multica/cr-prompts-revised/agent-skill-matrix.yml`。
- 原位落法：不适用（`zero_diff` 项，见 §9）。
- AC：AC-4。

### FR-5 Multica coordinator overlay 三处原位替换

- 落点：`multica` `cr-prompts-revised/cr-coordinator-agent.md` 的 `## 委派与评论`（基线 L38）、`## 评审闭环`（L45）、`## 失败与输出`（L63）；章节结构基线 dep-23。
- 目标文本的权威锚点 = **本 SDD §6.2**（三块逐字文本 + 替换边界 + 逐块 `sha256` + 来源文件 SHA256）；不再依赖 CR worktree 之外的来源副本，实现者与评审者均可在仓内逐字核对。
- 原位落法：**三处按 §6.2 逐字复制**（§3.3.1 整节含标题行替换；§3.3.2 仅替换标准评审入口段、保留既有 BLOCK/Suggestions/alignment 边界；§3.3.3 在既有失败 bullet 内插入给定段）；保留 `职责`、`事实源与读取`、`路由`、`平台层权限` 四节与 frontmatter；不整文件重写、不追加第五节。
  - §3.3.1：标准 Pipeline 节点只经既有 Runner 启动；计划外人工委派只传事实清单（CR-ID、节点/Skill 名、`crctl status/next` 返回、workspace/resources 原样值、canonical feedback 引用、当前责任 Agent）；不复述 Skill/Pipeline 步骤，不内联状态推进或 Git 命令，不把 blocker 正文改写成执行步骤，不声明未来节点已满足；`mention://agent/<id>` 是工作委派不是抄送；一条评论只 mention 一个当前目标；每次触发记录一次 squad activity。
  - §3.3.2：标准评审由 Runner 启动新的 reviewer task/run，协调者不得用评论重建 review Skill 步骤；BLOCK 按 `review-record` 返回的 `repair-target` 与 Pipeline `reviewLoop` 处理；介入条件限定为 repair target 无效、最大轮次耗尽、权限/事实冲突、技术失败或人工 gate。
  - §3.3.3：在 `## 失败与输出` 的**第 1 条**既有失败 bullet 后，按 §6.2 的两行替换块插入该段（内容 = 评论/Prompt 与当前 Skill/Pipeline 事实冲突时停止该次手工委派并报告 `CONTRACT_DRIFT` 与冲突两侧；来自 crctl 的恢复信息只逐字段转发、不改写成协调者自己的 Git/状态序列）；第 2 行行首恰两个半角空格，旧 bullet 行逐字保留、不加其它列表标记。
- 交付性质声明：这是 **Prompt 合同缓解**，不宣称平台新增运行时校验；owner 复制该文件到平台后才生效（部署不在本 CR 范围）。
- AC：AC-5。

### FR-6 公共 dev-agent 委派合同收紧

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

### FR-7 `gate --mode pre-review` 错配可操作化

- 落点：`tools` `skills/shared/crctl/scripts/crctl.mjs` `cmdGate()` 的 `--mode pre-review` 分支（基线 L957–960）+ 一个文件内 helper（§4.1.1）。
- 原位落法：**在原 `fail(...)` 调用上补 extra 字段**（不新增分支层级、不改 `--for requirement-reviewing` 的正常序列、不改 `fail()` 本身的输出协议）。
- 契约细节见 §3.1、算法见 §4.1；`contractDrift` 定位见 §3.1.1。
- AC：AC-7。

### FR-8 版本化 Prompt 的配对 lint

- 落点：`tools` `skills/shared/crctl/scripts/lint-prompts.mjs` R7 规则内（基线 L249–284）。
- 原位落法：在既有逐行循环内**新增一个子判据**（§4.3），不改既有四类子判据的判据与命中文本，不新增规则编号，不改 lint 的退出语义与豁免机制。
- AC：AC-8。

### FR-9 `review-loop reset` 原子提交

- 落点：`tools` `skills/shared/crctl/scripts/crctl.mjs` `cmdReviewLoopReset`（基线 L1821–1848）→ 改为 `async`；`tools` `skills/shared/crctl/scripts/lib/durable-tx.mjs` 前置条件一处数值（基线 L487）。既有符号与调用点见 dep-2 / dep-8 / dep-3 / dep-6。
- 原位落法：同一函数内**替换写入与返回段**（读参、TTY 检查、耗尽检查、审计字段与输出字段集不变）；`durable-tx.mjs` 只改一处比较数值。
- dispatcher（`case 'review-loop'`，dep-6）与调用形态**不改**：`return cmdReviewLoopReset(...)` 在 `async main()` 内已返回 Promise，`main().catch(...)` 已有统一兜底。
- 时序、崩溃窗口、错误码与契约见 §4.2 / §3.2；write-set 前置条件见 §3.3。
- AC：AC-9。

### FR-10 `review-record` payload 的 YAML 子集边界

- 落点（文档侧，5 处原位补写；dep-18、dep-19）：
  1. `tools` `skills/shared/crctl/SKILL.md` 的 `review-record` 行（基线 L34）：写明 `blockers`/`suggestions` 等值必须使用 YAML 子集支持的**单行标量**，不得使用多行引号标量或折叠块；依据是既有 `lib/yaml-subset.mjs` 的解析边界（块标量 `|`/`>` 仅保守拼接为文本；锚点/别名/tag/多文档不支持，dep-19）。
  2. `tools` `skills/requirement/review-requirement/SKILL.md`
  3. `tools` `skills/develop/review-tech-design/SKILL.md`
  4. `tools` `skills/develop/review-dev-plan/SKILL.md`
  5. `tools` `skills/develop/review-code/SKILL.md`
- 原位落法：在**既有 payload 示例处补同一约束注释**，不新增字段、不新增评审维度、不改示例结构（字段名与层级）。
- 约束：`lib/yaml-subset.mjs` 行为与实现**零改动**（不换解析器、不放宽边界）。
- AC：AC-10。

### FR-11 零新增与不修改边界

- 落点：无（交付 diff 的自洽性约束）。
- 原位落法：不适用；由 `zero_diff`（§9）与 AC-11 的 diff 核对承担。
- AC：AC-11。

### 6.1 AC 逐项设计与验收映射

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

**AC-1① 的口径注（口径甲，§6.5）**：① 的设计落点 = §6 FR-1① 的**授权版目标文本**（不含 `_context.md` 文件名指称、保留「不得创建或读取上下文副本」的禁止语义）；其可观测结果「两份副本文件内 `_context.md` 命中 0」与判定面**不变**（文件级字面检索；§4.5/AC-2 的计入集合含 multica `cr-prompts-revised/` 全文件，仍要求 0 命中）。即：替换段落自身不携带该文件名，是本条 AC 可达（grep = 0）的**前提**，不是对判据的放宽（本 CR 不采用「禁止句不计入活跃合同引用」的语义口径）。

**AC 反查结论**：逐条从 AC 回查正文——每条 AC 的设计落点均在 §1–§5 有对应设计（AC-1/2→§4.5、AC-3/5/6/10→§6 各行、AC-7→§3.1+§4.1、AC-8→§4.3、AC-9→§3.2+§4.2、AC-11→§9、AC-12→§4.6+§6.3）；无"设计落点缺失"、无"与 PRD 契约冲突"、无"结果不可观察"；关键前置（TTY 门槛、耗尽门槛、healthy workspace、CR-ID 语法判定）均不会过滤掉 AC 目标对象——其中 TTY 与耗尽门槛是 AC-9④ 的**被验对象**而非阻碍，CR-ID 语法判定的非常规分支正是 AC-7 的第二个向量。

### 6.2 coordinator overlay 三节逐字目标文本（权威锚点，AC-5）

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
### 委派与评论

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

### 6.3 既有测试基线红例外登记（AC-12 的绑定对象）

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

### 6.4 AC-12 口径授权记录（owner 显式授权 **选项 A**，已闭环）

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

### 6.5 FR-1① 目标段落文本口径授权记录（owner 显式授权 **口径甲**）

**授权记录（本 CR FR-1① 目标段落文本的唯一有效口径）**

| 项 | 值 |
|---|---|
| 裁决人 | `Ray`（需求 owner，本 CR `owners.requirement`） |
| 裁决 | **口径甲** —— 授权把 §6 FR-1① 的目标段落原文改写为**不含 `_context.md` 文件名指称**的禁用句：「…不得创建或读取上下文副本，也不得让缓存替代状态、评审证据或门禁」——禁止语义逐字保留，只去掉文件名指称 |
| 裁决时间 | `2026-09-11T15:36:12Z`（本地 `2026-09-11T23:36:12+08:00`） |
| 权威评论 | `01a0911c-b1ed-79bc-9164-99e611e2b51a`（Issue AIFI-24 线程；由 `cr-coordinator-agent` 以正式 mention 转派并留档于 `01a0911d-449e-7b0c-ae69-d9b9f5a01f8d`） |
| 授权范围 | **仅** §6 FR-1① 的目标段落文本（改写为不含文件名指称的禁用句）；同步落点 = §3.4-B、§6 FR-1①、§6.1（AC-1① 口径注）、§4.5（口径注）、§11 `SDD-CLOSE-08`、§13/`updated` |
| 授权边界 | **任何 AC 的判定面与阈值一律不动**（AC-1① 的「两份副本文件内 `_context.md` 命中 0」、AC-2 的计入/排除集合、§4.5 的字面 grep 与阈值均保持原样——这正是选甲的理由）；不改 `prd.md`（审批绑定 `9247c107…`）；不改 tools / multica 实现文件；不得自行改选口径乙 |
| 与人工 gate 的关系 | 下一步人工 gate `crctl approve --stage tech-design` 签的新版 SDD **包含**本口径；本授权决策项从此关闭，FR-1① 不再有第二种目标文本 |

**为何需要 owner 授权（事实，非 SDD 可自决项）**：需求来源 §3.1.1 的 `text` 替换块与 `prd.md` FR-1①（L155，审批绑定）**逐字含**「不得创建或读取 `_context.md` 等上下文副本」；而同一份已审批 PRD 的 §1.5（L132）/AC-1①（L276）与 SDD §4.5 的 multica 计入集合（`cr-prompts-revised/` 全文件、**字面 grep**）要求该文件名命中 0。两侧不可兼得：逐字含文件名的替换段落落在 `cr-prompts-revised/dev-agent.md` 内，其自身即命中 1 次 ⇒ AC-1①/AC-2 必红。SDD 无权自行改写已审批的需求契约（本节点在状态机上也**没有**回需求侧的转移边，见 §6.4 末段），故由 owner 明文裁决；owner 选择口径甲，本 SDD 按该唯一口径落地。

**偏离登记（本 SDD 相对来源/PRD 的授权偏离）**：§6 FR-1① 的授权版目标文本与来源 §3.1.1 的 `text` 块、`prd.md` FR-1① 引号内的逐字句**不相同**，差异**仅**为该文件名指称（禁止语义一致）；该偏离由 owner 明文授权（上表），`prd.md` 保持审批版本不变，AC 判定面不变。

**未采纳的口径乙（记录备查）**：保留替换块逐字（含文件名），把 §4.5 / §6.1 AC-1① 的 multica 判定改为语义口径（「不得创建或读取…」这类**禁止句不计入**「活跃合同引用」）。未采纳理由（owner 裁决判据）：① 口径甲不牺牲禁止语义（与来源 §3.1.1 语义一致）；② AC-1①/AC-2/§4.5 的判据保持**字面可机械验收**（grep = 0），不引入语义判定、不改写任何判据。口径乙若日后启用，须另经 owner 明文授权并同步改判据（本 CR 不做）。

**可达性不变式（本轮改动后）**：§6 FR-1① 授权版文本 + §6 FR-1②（reviewer 副本段内删引用）+ §6 FR-1③（tools `allowed` 条目删除）三处落地后，§4.5 的计入集合（tools 的 `agents/`/`skills/`/`pipeline-templates/` 全文件 + multica `cr-prompts-revised/` 全文件）字面 grep 命中 0 可达；本记录**不新增**任何排除面、不改 AC-1①/AC-2 的阈值，也不改 `prd.md`。

## 7. 安全与性能考量

### 7.1 安全控制点

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

### 7.2 性能与资源

- `reset` 的事务规模为**单文件单条目**，不存在多条目重放或大文件拷贝；`applyWriteSet` 对单条目只做一次 CAS 读 + 一次 blob 写 + 一次 rename。
- 无新增网络访问、无轮询、无后台任务；`gate` 错配路径与既有 `gate` 同量级（纯内存 + 一次 state machine 载入）。
- `lint-prompts` 新增子判据是既有循环内的一次正则与两次字符串包含，不改变文件遍历面（dep-15），不引入新的 IO。
- 验收证据命令的预算：AC-12 的全量回归按 §4.6.2 做无重不漏分区后纳入 `crctl test`，总时长（含 lint 与断言类命令）必须落在 `write-test-report` 节点 `timeoutMinutes=20` 的预算内；本 CR 不新增观测指标，节流手段是分区而非跳过用例。
- 无性能目标变更，不新增观测指标（PRD FR-11 / §7）。

## 8. Prompt 采纳影响（条件性小节）

**结论：N/A（本 CR 不触发该条件），应改为调用新能力/新命令的 skill 清单为空。**

触发判据是"diff 触及 `crctl.mjs` 的 dispatch 分支或 `rules.json#protectedPaths.deny`（crctl 命令面或 guard deny 面有新增/变更）"。逐项核验：

| 核验项 | 结论 | 证据 |
|---|---|---|
| 是否新增/变更 crctl 子命令或 dispatch 分支 | **否**：FR-9 只改 `cmdReviewLoopReset` 的函数体（同步→async），dispatcher 的 `case 'review-loop'` 行**不改**；`async main()` 与 `main().catch(...)` 已能接管 Promise | dep-6 |
| 是否变更 `protectedPaths.deny` / `rules.json` | **否**：`rules.json` 零 diff（AC-11） | dep-17 |
| 是否有 skill 需要改为调用新增/扩展子命令 | **无**：在 lint 的扫描面（`**/SKILL.md` + `*.pipeline.json` + `README.md` + `agents/*.md`，dep-15）上检索 `review-loop reset` 为 0 命中，因此没有 skill/agent 在描述既有的直写语义需要改写 | dep-15 |
| 是否有 prompt 与 FR-7/FR-8 的新判定冲突 | **无**：`gate --mode pre-review` 在扫描面内只有 1 行命中，且该行已同时声明 `--for requirement-reviewing`，FR-8 加入后不产生新 finding、也无需修改该 prompt 文本 | dep-21 |

因此本节不含采纳清单；若后续 CR 新增 crctl 子命令，再按该 CR 的 SDD 补本节。

## 9. 批准范围

### scope_in（当前 CR 必须交付）

- **FR-1 ~ FR-11** 与 **AC-1 ~ AC-12** 全部条目。
- 改动文件面：以 PRD §1.3.1 的 14 行「仓 + 文件」表为准（`tools/**` 为主：`crctl.mjs` × 2 处、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs`、`lint-prompts.mjs`、`agents/dev-agent.md`、`crctl/SKILL.md`、4 份 review SKILL、上述 4 个脚本的既有测试；`multica/**` 恰 4 个文件：`cr-prompts-revised/{dev-agent,quality-reviewer-agent,cr-coordinator-agent}.md` + `CUSTOM.md`）。
- 本 SDD 自身（`change-requests/CR-2026-063/sdd.md`）与实现期产生的新增测试用例。
- `tools` `skills/shared/crctl/scripts/test/crctl.test.mjs` 的**既有 reset 用例夹具迁移**（`makeWorkspace()` → `makeGitWorkspace()`，断言逐字不变）与新增 W2b / 恢复串向量用例 —— 属 PRD §1.3.1 第 14 行「上述 4 个脚本的既有测试」面。
- 交付证据：AC-2 的检索命令与命中清单；AC-12 的全量测试结果（按 §4.6 的分区命令，含 `sourceRevision` 与 `cmd-NN` 日志绑定）。

### scope_out（明确排除）

- 来源 §1.4/§7 与 PRD §7 的全部排除项：SLO / M1–M8 / P50-P90 / 连续 N 个 CR 统计 / 计数门禁 / 为新指标新增账本字段或 Prompt 要求；R14 委派 lint；更换或放宽 YAML 解析器；历史 CR 目录、历史 `traceability.yml`、归档 delivery 证据的批量迁移。
- 独立 CR（不得并入）：**CR-R**（`recoverCommand` → 结构化 `recovery` 原子迁移）、**CR-P1**（评审输入结构与回修闭合）、**CR-P2**（plan/TASK 返工成本与执行前提）。
- 部署面：平台 DB 的 Prompt 投影、`multica/aifirst/agent-import.mjs`、`multica agent update` 等部署动作（由 owner 在 CR 落地后执行）。
- 知识库文档：KB 的 `specs/`、`delivery/`、`docs/`（含主工作区 `docs/analysis/` 的未提交变动）。
- CR-P1 的 `dep-N` 结构化方案**不适用**于本 SDD：本 CR 尚未实施 CR-P1，因此本 SDD 仍按当前 `write-tech-design` 的"既有实现依赖与事实"固定结构逐项给出 repo/path/symbol/SHA/结论（第 10 节），不引入 `dep-N` 之外的第二套事实定义格式（正文只持引用）。

### zero_diff（明确不得改动）

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

### follow_up（发现但留给后续 CR）

1. `tools/skills/shared/crctl/SKILL.md` 的「写入」行仍写 `review-loop.yml`（仅 `attempt`），未包含 `review-loop reset`——本 CR 的 `scope_in` 只授权该文件的 `review-record` 行（§1.3.1 第 12 行），故不改；建议由后续 CR 或 CR-R 一并收口。
2. `multica/CUSTOM.md` #75 行的第 4 列（`原因 / 追溯`）保留"对照快照"这一历史 provenance 措辞；本 CR 按 AC-3"其它行零 diff"与 FR-3"不改变该表其它行"的最小 diff 原则不改，后续如需语义统一可单独修订。
3. AC-2 的"计入/排除"判定目前是人工逐条 + 命中清单证据（S-5）；机械化为检索 lint 属新规则范围，本 CR 不做。
4. CR-R：`recoverCommand`（`gate` 错配 + `reset` 失败）→ 结构化 `recovery` 的原子迁移，以及本 CR 新增的两个 `REVIEW_LOOP_RESET_COMMIT_*` 错误码的消费迁移，全部归 CR-R。
5. 历史 CR 目录内的既有 `_context.md` 不迁移、不清洗（随 CR 自然归档）。
6. **基线红 BR-2 / BR-3 / BR-4 的根因修复**：`checkpoint` 的 alignment reader 不读 `latest-checkpoint`（BR-2）；`dir-graph.yaml` 状态机声明数与既有断言口径（BR-3，测试断言 28 条声明、当前 31 条）；`write-requirement-prd/SKILL.md` Step 4 措辞（BR-4）。三者对象均在本 CR 的 `zero_diff` 或 `scope_out` 面，本 CR 不修（不扩大批准范围）；BR-1/BR-5 沿用 CR-2026-060 §5.3 的 follow_up。AC-12 的口径授权见 §6.4。
7. **AC-12 口径的需求侧记录**：owner 已显式采纳 §6.4 选项 A（接受 5 条已登记基线红，授权记录见 §6.4），该口径的需求侧记录随回写期 `specs/` 累积文档与后续需求 CR 承载；本 CR 内不改 `prd.md`（审批绑定 `9247c107…`），需求侧口径以 §6.4 授权记录为唯一依据。

## 10. 既有实现依赖与事实

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

## 11. SDD-CLOSE 关闭清单

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
            口径授权: multica 计入集合归零的可达前提 = §6 FR-1① 目标段落按 owner 授权口径甲落地（不含 `_context.md` 文件名指称、
            保留「不得创建或读取上下文副本」的禁止语义）；集合、阈值与判定方式不变（文件级字面 grep），授权记录见 §6.5。
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

## 12. 需求评审第 2 轮 carry-over 处理

| 项 | 状态 | 处理 |
|---|---|---|
| **S-6**：PRD §1.4 事实 10 括注把 `durable-tx.test.mjs` 说成"只测 write-set entry 校验与 journal 形状"，过窄 | **已处理**（落 SDD 事实） | 采纳 reviewer 建议的准确口径，写入 dep-8：该文件 9 个用例覆盖锁/竞争矩阵、journal 幂等加载、`applyWriteSet` redo/幂等/第三值冲突、kill-restart 恢复、`recoverWriteSet`、`cleanupTxBlobs`、checkpoint payload slot，其中**无 ledger write-set 规模断言**；`crctl.test.mjs:1432` 仅断言源码文本含 `beginLedgerCommand`。核心断言（无测试守卫 `≥2` 规则）成立，且因本 CR 放宽该规则，AC-9⑥ 明确要求新增该规则的可验断言。PRD 原文不改（审批绑定）。 | 
| **S-7**：PRD §1.4 事实 7 的 `recoverCommand` 出现面枚举漏 `crctl test`，且所列 `workspace-transactions.mjs:1074` 实属 `syncWorkspaceToTrunk` | **已处理**（落 SDD 事实） | 不再使用"只出现在"表述：dep-11 明确 `recoverCommand` 的出现面 = `register`/`checkpoint`/`merge`/`writeback`/`archive` 的事务返回与 `TxError` extra、`crctl test` 的 `buildTestResponse`（L4186）、`crctl workspace sync` 的 `syncWorkspaceToTrunk`（L1074）。结论（FR-7 沿用既有命名）不受影响。PRD 原文不改（审批绑定）。 |

两条均为**非阻塞项**，处理不扩大 scope_in、不改动范围（不据此新增或删除任何 FR/AC）。

## 13. 修订记录

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
- 修订 0.1.4（2026-09-11，dev-plan 上游 blocker R-13 → owner 口径甲裁决 → `write-tech-design`；承接评审注释记为 0.1.3 的 `ce51c168…` 版）：按 Issue AIFI-24 权威评论 `01a0911c-b1ed-79bc-9164-99e611e2b51a` 的 **口径甲**授权，把 §6 FR-1① 的目标段落原文改写为**不含 `_context.md` 文件名指称**的禁用句（禁止语义逐字保留），并同步 §3.4-B、§6.1（AC-1① 口径注）、§4.5（口径注）、§11 `SDD-CLOSE-08`；新增 **§6.5** 授权记录（裁决人 `Ray` / 时间 `2026-09-11T15:36:12Z` / 权威评论 / 授权范围 = 仅该目标段落文本 / 边界 = AC 判定面与阈值不动）。
  - **未动**：`prd.md`（`9247c107…`）、任何 AC 的判定面与阈值（AC-1①/AC-2/§4.5 的集合与 grep 判据原样）、§6.2 三块锚点（实测其覆盖面为 multica `cr-prompts-revised/cr-coordinator-agent.md`，与 FR-1①/§3.4-B/§6.1/§4.5/§11 无交集，**无哈希重算**）、plan/TASK、tools/multica 实现文件。
  - 说明：0.1.3（cycle 2 评审 B-02 契约半 + owner 选项 A 授权，落 §6.1/§6.3/§6.4/§9 `follow_up` 第 7 条/`SDD-CLOSE-13`）未在 §13 单列条目，本条按同一编号口径续编为 0.1.4。
- 结构规模：9 个 Skill 规定章节 + 既有实现依赖与事实（29 项，含本轮补条 dep-26~29）+ SDD-CLOSE 关闭清单 + carry-over 处理 + §4.6 证据命令契约 + §6.2 逐字锚点 + §6.3 基线红例外登记 + §6.4 AC-12 口径授权项 + §6.5 FR-1① 目标文本口径授权记录；FR 覆盖率 11/11，AC 覆盖率 12/12。

## CR-S：测试基线与门禁可信化 — 断言去硬编码、4 条基线漂移转绿、CI 全量步骤成为真门禁（v0.38 · CR-2026-065）

> 输入：`change-requests/CR-2026-065/prd.md`（sha256(LF) `467b5d47…`，已评审 PASS 并经人工审批）。
> 修订（`review-tech-design` attempt 1/3 BLOCK 后的定点回修）：**B-1** §4.4 BR-2 行——三词改为「否定辖域」机械判据、零命中面收缩为已核对为真的 `latest-checkpoint` / `checkpoints[]`；**B-2** §6.3 第 5 项拆为两项——按本机实测登记 `merge-fixture.mjs` 的真实导出，新增第 6 项承载 `archive-tx.test.mjs` 的文件内局部 helper；**B-3** §3.1/§4.3/§2.2 统一 VOLATILE 键空间（`OUTBOX_VOLATILE_PAYLOAD_KEYS`，payload 根下相对键）并补「投影闭合」不变量。本轮一并关闭 3 条 in-scope suggestions（S-1 非收敛例外的判读、S-2 恒真结构自检、S-3 显式钉 TAP reporter + 解析自测），逐条落点见 §6.5 `SDD-CLOSE-09`…`SDD-CLOSE-11`。
> 修订（`review-tech-design` attempt 2/3 BLOCK 后、由 `review-dev-plan` upstream 阻断（`review-annotations/dev-plan.yml`，`repair-target=write-tech-design`）触发的定点回修；本轮 = `review-tech-design` attempt 3/3）：**B-4（唯一 blocker）** 已批准 SDD 的 per-file 归属前提「TAP 文件名块 + file 级 plan」在**目标运行时不存在**（Node v24.15.0 与 CI 同版本 v20.20.2 均非此形态，§7.4 P1/P2 实跑探针）⇒ 归属机制改为「**逐文件 spawn + 逐文件观察**」：归属由 spawn 构造给出，**不读任何报告的块结构**；文件集合漂移改为对**磁盘事实源**（`readTestFileSet`）核对；每文件用例数改为「单文件顶层 plan / 顶层结果行数一致」并逐文件与 `manifest.cases` 比对。落点：§1.3/§1.4、§2.3、§2.4（新增 `files[]` / `observer`）、§3.2（**归属不变量 I1…I3 + 机制与替代**）、§4.2、TDEC-1/TDEC-4、§6.2（AC 可达性）、§6.4、§6.5（`SDD-CLOSE-11` 改写 + 新增 `SDD-CLOSE-12`）、§7.4（无证据的保证性陈述 → 两运行时实跑探针表）。**不变量未放宽**：真实执行 / 每文件用例数 ≥ 基线 / 解析失败硬失败仍是硬约束（§3.2 I1…I3）；证据面见 §7.4 与 §6.4。
> 目标代码仓：**`tools` 仓自身**（本 CR 改 `skills/`、`skills/shared/crctl/scripts/`、`.github/workflows/crctl-ci.yml`），故按 `write-tech-design` Step 1.2 的特殊分支读取 `tools/ARCHITECTURE.md`（**只读不改**，13562 B，已存在）。
> 本文档只描述设计与实现契约；实测证据（负控、收敛、耗时）由实施与测试期产出，格式由 §4.6 与 §3.2 固定。

---

### 1. 架构概览

#### 1.1 本 CR 在 tools 包中的位置

tools 包的分层（`tools/ARCHITECTURE.md` §4）：使用方仓库 → Pipeline → Skill → `crctl`。本 CR **不改 Pipeline 节点序列、不改 Skill 语义、不改状态机、不改错误码、不改事务语义**；它改的是三处「断言与门禁」：

1. **断言层**：`skills/shared/crctl/scripts/test/*.test.mjs` 中把「会随合理变更而变的既有事实」钉成快照的 4 条断言（BR-1…BR-4）+ 1 条构造失真的冻结向量（BR-5）。
2. **门禁层**：`.github/workflows/crctl-ci.yml:109-111` 的全量测试步骤（当前裸 `node --test --test-concurrency=2 …`）。
3. **最小产品面**：`crctl.mjs#emitOutboxEvent` 的去重比较字段契约从「注释里的口头约定」提为「可机器检查的声明」（FR-10）。

因此本 CR 不新增架构不变量，也不触碰 `ARCHITECTURE.md` §5 的 8 条不变量；相反，本 CR 让第 5 条（状态机口径唯一）与第 4 条（行尾与硬失败纪律）在**测试侧**第一次变成机器可查的。

#### 1.2 变更面总览（文件 → 动作 → 归属）

| 文件（相对 tools 仓根） | 动作 | 归属 FR | 性质 |
|---|---|---|---|
| `skills/shared/crctl/scripts/lib/outbox-contract.mjs` | **新增** | FR-8 / FR-10 | 产品面（最小） |
| `skills/shared/crctl/scripts/crctl.mjs` | 改 `emitOutboxEvent`：内联比较块 → 调用契约模块（注释合并，语义零变化） | FR-8 / FR-10 | 产品面（最小） |
| `skills/shared/crctl/scripts/test/assertion-sources.mjs` | **新增**（不匹配 `*.test.mjs`，不被 runner 当测试执行） | FR-1 / FR-3 / FR-6 | 测试辅助（只读） |
| `skills/shared/crctl/scripts/test/gate-registry.json` | **新增**（受控清单数据文件） | FR-3 / FR-6 / FR-14 | 治理数据（人工提交） |
| `skills/shared/crctl/scripts/test/suite-gate.mjs` | **新增**（全量套件门禁包装器，不匹配 `*.test.mjs`） | FR-11 / FR-12 / FR-14 | CI 门禁 |
| `.github/workflows/crctl-ci.yml` | 改第 109-111 步骤：调用 `suite-gate.mjs --run` | FR-11 / FR-12 | CI 配置 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 改 3 条断言（`:1337` BR-1、`:4777` BR-3、`:4989` BR-4） | FR-4 / FR-6 / FR-7 | 测试 |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 改 `:480` BR-2 断言 | FR-5 | 测试 |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | 改 `:373` RED-7 构造 + 新增「同名不同内容」用例 | FR-8 / FR-9 | 测试 |
| `skills/shared/crctl/scripts/test/trace-outbox.test.mjs` | 新增去重契约断言（含字段分类负例） | FR-10 | 测试 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | 新增受控清单 / 例外登记面 / 写入口静态断言 + `suite-gate` 报告解析自测（内联 TAP 片段，关闭 S-3） | FR-14 / FR-17 | 测试 |

**不新增测试文件**：`*.test.mjs` 文件集合保持基线 21 个（`AC-01` 的「21 个文件全部被真实执行」按此口径成立）。新增的两个 `.mjs` 都不匹配 `*.test.mjs`，不被 runner 采集。

#### 1.3 依赖方向（只朝下，且不新增第二写入口）

```
.github/workflows/crctl-ci.yml
        │  run: node .../test/suite-gate.mjs --run
        ▼
test/suite-gate.mjs ──读──▶ test/gate-registry.json        （只读；唯一写入口 = 人类编辑 + git commit）
        │
        │  spawn × N: node --test --test-reporter=tap <file>   （每文件一个子进程；文件清单由包装器展开，单一命令来源）
        ▼
*.test.mjs（21 个）──读──▶ test/assertion-sources.mjs ──▶ lib/yaml-subset.mjs（既有解析器）
        │
        └──读──▶ lib/outbox-contract.mjs ◀──用── crctl.mjs#emitOutboxEvent（唯一契约事实源）
```

- 断言一律**只读**：不改状态、不写 `cr.md` / `_backlog.yml` / `tasks/_index.yml` / `approval.yml`，不调用任何 crctl 写命令。
- 不新增 crctl 子命令或 flag（FR-17）；`gate-registry.json` 与 `suite-gate.mjs` 是仓库内 CI 面，不是用户可调用契约。
- 零新增第三方依赖：只用 Node 标准库与仓库既有 `lib/`（FR-15.6）。

#### 1.4 关键流程（一次门禁运行）

```text
CI step「crctl full test suite」
  └─ suite-gate --run
       1. 读 gate-registry.json（缺失/坏 schema → 硬失败，零静默）
       2. 按登记面清单**逐文件** spawn 全量子进程（池大小 = CONCURRENCY 常量），每个子进程的原始 TAP + 退出码落 --report-out（NDJSON）
       3. 逐文件解析该文件**自己的** TAP → 该文件用例数 / 失败用例名 / 文件级 skip；**归属由 spawn 构造给出，不读报告**（§3.2 I1）
            （任一文件解析失败 → SUITE_REPORT_UNPARSEABLE 硬失败，禁止降级为空结果；进程未自行结束的分支见 §3.2 非收敛口径）
       4. 受控清单核对（磁盘 `*.test.mjs` 集合 ≡ 登记集合；每文件用例数 ≥ 基线，逐项见报告 `files[]`）
       5. 例外面核对（schema / owner / 到期 / 与真实失败集合的双向匹配）
       6. 结论：退出码 0 当且仅当 §3.2 check code 表中无任一**未被抑制**的触发
            （正常收敛：失败集合差为空且 3/4/5 全过；非收敛分支：改判 `SUITE_NONCONVERGENCE` 行，不做 3/4 核对）
```

---

### 2. 数据模型

#### 2.1 术语硬化（Step 2.5）

只处理进入数据模型 / 接口契约且存在歧义或别名风险的术语。先验结论：**不存在需要需求负责人澄清的语义冲突**（SPRD 与本 CR 输入约束已给出唯一含义），因此未触发「首次 advance 前停止」；下表把 PRD canonical term 与代码落点一次性钉死，避免实现期两种读法。

| PRD canonical term | 代码落点 / 别名 | 边界规则（唯一读法） |
|---|---|---|
| 受控清单 | `test/gate-registry.json`（git 跟踪数据文件） | 是**清单**不是**账本**：不进 `crctl` 写路径，唯一变更入口 = 人类编辑 + `git commit`（审计 = git history）。与「受控账本」（`_backlog.yml` / `tasks/_index.yml` / `cr.md`，只能经 crctl 写）严格区分 |
| 例外 / 例外清单 | `gate-registry.json#exceptions` | 例外 = **对已知失败的、有主有期的容忍登记**；不是「跳过测试」、不是「放宽断言」。登记不替代执行：被容忍的失败仍必须由 runner 真实报告 |
| 到期 | `exceptions[].expires` | 只能是一个**带显式时区偏移的 ISO-8601 时间戳**（`YYYY-MM-DDTHH:MM:SS(Z|±HH:MM)`）；比较基准 = 门禁运行时的 UTC 瞬时（`Date.now()`）；`now >= expires` 即过期。不接受「日期或可判定的条件」这类开放形态（关闭 S-5） |
| 失败集合 | TAP 观测到的 `not ok` 用例名集合 | 口径 = 「本次运行实际报告的失败用例」，与文件级加载失败（不可例外化）分开计数 |
| 可推导的事实 | §6.6 表 D1…D6 | 由事实源结构推导，硬编码其快照 = 缺陷 |
| 必须钉死的目标值 | §6.6 表 P1…P7 | 显式登记；变更时必须在本 CR/本变更内显式更新登记值才允许转绿 |
| 漂移当场红 | §4.6 注入协议 | = 真实漂移注入后**全量命令**变红，且注入物不留在交付分支 |

#### 2.2 既有实体：outbox 事件对象（只归类，不改字段）

现网事件对象（`crctl.mjs#emitOutboxEvent` 构造，写入 `.crctl/outbox/<name>.json`）：

| 字段 | 是否参与去重比较 | 说明 |
|---|---|---|
| `v` / `event_kind` / `cr_id` / `from_status` / `to_status` / `trigger` / `commit_sha` / `actor` / `evidence` / `payload` | **参与** | 内容面；`payload` 逐键参与 |
| `occurred_at` | **不参与**（顶层易变） | 每次 `nowIso()` 重新生成；排除后同名文件重放不产生假冲突 |
| `payload.detected_at` | **不参与**（唯一登记的 payload 易变键） | 键名读法 = `payload` 根下的 `detected_at`（**相对键**，不是事件对象全路径），由 `OUTBOX_VOLATILE_PAYLOAD_KEYS` 枚举排除；CR-2026-052 TASK-08 语义：同一漂移在被采集前重复观测不产生 `OUTBOX_DEDUP_CONFLICT` |

语义不变（FR-8）：文件名存在且比较面**逐字段相等** → 视为已发送（返回文件名、不覆盖、不新增）；比较面**不等** → `OUTBOX_DEDUP_CONFLICT` → 调用方 `EMIT_FAILED` → 不覆盖、不静默去重。本 CR 只把上表从注释提为可检查声明（§3.1），**不改变任何字段语义**。

#### 2.3 新增实体 1：`gate-registry.json`（受控清单）

Schema `crctl-suite-gate/v1`（字段全部必填，缺 = 红）：

```json
{
  "schema": "crctl-suite-gate/v1",
  "manifest": {
    "files": ["archive-tx.test.mjs", "..."],
    "cases": { "archive-tx.test.mjs": 0, "crctl.test.mjs": 0 }
  },
  "stateMachine": {
    "namedStates": ["drafting", "..."],
    "wildcards": { "any-active": ["drafting", "..."] },
    "transitions": [{ "from": "(new)", "to": "drafting", "trigger": "requirement-register" }]
  },
  "exceptions": []
}
```

| 段 | 语义 | 谁读 | 变更后果 |
|---|---|---|---|
| `manifest.files` | 必须被执行的测试文件集合（仓库相对文件名） | `suite-gate`（执行面 + 核对面） | ① 磁盘上 `test/*.test.mjs` 的实际集合 ≠ 登记集合 → `SUITE_MANIFEST_FILE_DRIFT` 红；② 登记集合中任一文件未被真实 spawn、或未产出可判结论 → `SUITE_REPORT_UNPARSEABLE` / `SUITE_FILE_LOAD_FAILURE` 红（归属由 spawn 构造保证，§3.2 I1） |
| `manifest.cases` | 每文件用例数**基线**（实施期实测登记，见 FR-16）。计数单位 = 该文件在**独立子进程**中执行时其 TAP 的**顶层结果数**（顶层 plan `1..N` 与顶层 `ok`/`not ok` 行数一致；两目标运行时实测同形态，§7.4 P9） | `suite-gate` | 该文件实际顶层用例数 < 基线 → `SUITE_MANIFEST_CASE_DROP` 红（关闭 S-1：删用例换绿在门禁上留痕） |
| `stateMachine.namedStates` | 具名状态集合（15 个；注册前态 `(new)` 单列，不入集合） | 状态机断言 | 与推导集合不等 → 红（FR-6.2） |
| `stateMachine.wildcards` | wildcard 名 → 目标集合（当前 `any-active` → 12 个） | 状态机断言 | 增删目标即红（关闭 S-3） |
| `stateMachine.transitions` | 每条声明转换的稳定标识 `(from,to,trigger)`（当前 31 条） | 状态机断言 | 增删改名任一转换即红，除非显式更新登记值 |
| `exceptions` | 例外单一登记处；本 CR 交付态 = **空数组**（显式声明为空，非「文件不存在」） | `suite-gate` | 见 §3.2 错误码表 |

**登记值的初值来源**：`stateMachine.*` 由实施期从 `dir-graph.yaml` 推导后原样登记（当前实测：具名状态 15、声明转移 31、`from: any-active` 2 条、`any-active` 目标 12 个、展开 31−2+12×2 = **53**）；`manifest.cases` 由实施期在 5 条修复与新增用例落地后**逐文件**实测登记。登记后**不得**再由脚本自动改写（受控写入 = 人工提交）。

**归属与基线的事实源分工（B-4 修订）**：本段的 `manifest.*` 只承载**目标值**（§6.6 P5），不承载归属机制。「某条结果属于哪个文件」这一事实由**执行构造**给出 —— 每个登记文件一个独立 `node --test` 子进程，包装器在 spawn 时就已持有归属，**不解析任何报告即得**（§3.2 I1、§4.2）。于是归因链上唯一的报告解析面收缩为「单文件内取顶层用例数与失败名」，解析不符即 `SUITE_REPORT_UNPARSEABLE` 硬失败（工程纪律 #1），不存在静默降级；文件集合本身的事实源也改为**磁盘目录**（`readTestFileSet`），不再是「从一份多文件报告里读出来的实际执行集合」。

#### 2.4 新增实体 2：门禁运行报告（`suite-gate` 的固定字段，关闭 S-2）

`--json-out <path>` 落盘的报告模型（同时是人类可读摘要的输出源）：

```text
schema        "crctl-suite-gate-report/v1"
command       实际执行的命令模板与展开规模（含池大小常量，字符串；唯一命令来源仍是包装器，§3.2）
observer      本轮实际使用的每文件观察通道（"tap-per-file" = 本设计默认；替代通道见 §3.2「机制与替代」）
duration_ms   全量门禁耗时（整数；= 池式执行的整体墙钟，不是各文件耗时之和）
converged     全部子进程是否已自行结束（false = 触发 --max-runtime-ms 被终止，即停滞）
exit_code     全量结论退出码（全绿 0；被终止时为 null；逐文件退出码在 files[]）
files_executed / cases_executed / skipped_file_level
files[]       每文件观察记录 [{ file, state, exit_code, cases, failures[], skipped, todo, duration_ms }]；state ∈ ok|failed|file-load-failure|unfinished（unfinished = 停滞终止时仍在运行）
failures[]    失败用例名（全部文件的并集，去重）
checks[]      [{ code, ok, detail, suppressed_by?, not_evaluated? }] 逐项门禁结论（固定 check code；被例外抑制时 ok=false 且带 suppressed_by=<exception-id>；非收敛分支未做的核对项带 not_evaluated=true）
registry      { sha256, exceptions_count }
platform      { platform, node }
verdict       "pass" | "block"
```

字段名固定（S-2 要求「交付物字段写死」），实施期不得改名；`test-report` 的 `test-evidence/cmd-NN.log` 直接落该 JSON。
**本轮变更（B-4）**：新增 `files[]` 与 `observer` 两个字段。`files[]` 使「每文件用例数 ≥ 基线」这条不变量（I2）在证据面上**逐项可核**（`files[].cases` ↔ `manifest.cases`），不再需要二次解析报告；`observer` 登记实际观察通道，使「机制被替换过」这件事在证据里留痕（§3.2）。

**数据/schema 变更触发声明**：本 CR 不涉及数据库 schema、数据迁移或写路径鉴权（N/A，理由：断言只读 + 唯一新数据文件为 git 跟踪的受控清单，无事务/回滚语义）。故本节不含 down/回滚设计。

---

### 3. 接口契约

#### 3.1 `lib/outbox-contract.mjs`（产品面，FR-10 单一事实源）

```js
// 单一事实源：字段分类 + 投影函数。产品与测试共同 import，禁止第二份副本。
export const OUTBOX_COMPARED_FIELDS = Object.freeze([...]);      // 参与比较（§2.2 上半表）
export const OUTBOX_EXCLUDED_FIELDS = Object.freeze(['occurred_at']);          // 顶层不参与
export const OUTBOX_VOLATILE_PAYLOAD_KEYS = Object.freeze(['detected_at']);    // payload 根下键名（相对键）
export function buildOutboxEvent(input, nowIsoString) { /* 规范化事件对象 */ }
export function buildOutboxComparable(event) { /* 由上面三个声明驱动的投影 */ }
```

契约：

1. `crctl.mjs#emitOutboxEvent` 改用 `buildOutboxEvent` + `buildOutboxComparable`；`crctl.mjs` 中**不得**再出现字段枚举或 `detected_at` 的语义副本（只允许指向本模块的指针注释）。
2. 不变性（测试断言）：`Object.keys(buildOutboxEvent(sample, now)) ≡ OUTBOX_COMPARED_FIELDS ∪ OUTBOX_EXCLUDED_FIELDS`（集合相等）。⇒ 任何新增字段若未登记进两类之一，契约检查直接红（这就是 AC-09 负控的落点）。
3. 不变性：`OUTBOX_VOLATILE_PAYLOAD_KEYS` 只做**枚举排除**，不得实现为「按名字/类型自动排除所有时间类字段」；测试用反例证明：`payload.observed_at`（未登记）**仍参与比较**。
4. 不变性（投影闭合）：对任意入参，`Object.keys(buildOutboxComparable(ev).payload) ∩ OUTBOX_VOLATILE_PAYLOAD_KEYS = ∅` —— 登记键绝不出现在投影结果中；键缺失、`payload` 为空、嵌套对象三种边界同样成立。⇒ 常量与投影必须处于**同一键空间**（声明与实现同读法），否则本条直接红。
5. 不变性：投影只读不改入参（不得就地 delete 原事件字段）。
6. 行为等价：对同一比较面的事件重放仍视为已发送（返回文件名）；比较面不等仍抛 `OUTBOX_DEDUP_CONFLICT`（FR-8 语义零变化）。

#### 3.2 `test/suite-gate.mjs`（CI 门禁契约；「例外登记面」四查在此闭合）

**调用形态**

```text
node skills/shared/crctl/scripts/test/suite-gate.mjs --run [--report-out <ndjson>] [--json-out <json>]
                                                           [--max-runtime-ms <n>] [--cwd <tools-root>]
node skills/shared/crctl/scripts/test/suite-gate.mjs --report <ndjson> [--json-out <json>]
```

- `--run`（CI 与本地证据的唯一形态）：由包装器**自己**按登记面清单**逐文件** spawn 全量套件 —— 每文件一个 `node --test --test-reporter=tap <abs file>` 子进程，池大小由包装器内唯一常量 `CONCURRENCY` 决定（TDEC-4）；每行落一条 `{ file, exit_code, converged, tap }`（NDJSON）。
- `--report <ndjson>`：只做判定，不跑套件（负控与回归自测用）；输入与 `--run --report-out` **同一形状**，因此判定函数只有一份。

**归属不变量 I1…I3（必须为真，与机制无关；机制不得违反）**

| # | 不变量 | 承载点 |
|---|---|---|
| I1 | 登记清单里**每一个文件**都被真实执行，且「某条结果属于哪个文件」**可判** —— 不靠人工核对，也不靠报告的块结构猜 | 逐文件 spawn：归属在 spawn 时由包装器持有（§4.2）；登记集合 ≡ 磁盘集合（`readTestFileSet`，FR-3/D3） |
| I2 | 每个文件的执行规模（用例数）**可观测**，并与登记基线**逐文件**比较（`<` 即红） | 每文件自己的 TAP 顶层结果数；`files[].cases` ↔ `manifest.cases` 逐项比对（§2.4） |
| I3 | 任何使 I1/I2 **不可判**的输入（报告结构不符、文件缺失、子进程未产出可判结论）必须**硬失败（红）**，禁止降级为「全局口径」「零失败」或跳过 | `SUITE_REPORT_UNPARSEABLE` / `SUITE_FILE_LOAD_FAILURE` / `SUITE_MANIFEST_FILE_DRIFT`（见下表） |

**机制与替代（B-4：本次事故的根因是机制失效时设计里没有合法出口，本节把这个出口写死）**

- **当前选用的机制**：逐文件 spawn + **每文件 TAP**（`--test-reporter=tap` 显式钉死）。该机制的两个外部前提已由本轮实跑探针在两目标运行时上证伪/证实：① **归属不再依赖任何报告结构**（旧前提已证伪，§7.4 P1/P2）；② 单文件 TAP 的**顶层 plan 与顶层结果行数一致**在两运行时上逐字一致（§7.4 P9）。
- **失效时的允许替代（唯一，且不是「降级」）**：若某目标运行时的单文件 TAP 不满足解析前提，**禁止**降级为全局计数、禁止跳过该文件（必须红）。允许的替代只有一条：把**每文件的观察通道**换成**结构化事件流**（`--test-reporter=<本仓本地 reporter 模块>`：按 `test:pass|test:fail|test:skip|test:todo` 事件计数，事件自带 `file` 字段），且必须**同时**满足：① 在本机 v24.15.0 与 CI 同版本（Node 20）两种运行时各留一份实跑探针输出；② 在报告 `observer` 字段登记所用通道（§2.4）；③ 由本 CR 的 `review-code` 覆盖。任一条不满足，门禁保持红，替代不得落地。
- **反向要求**：不变量 I1…I3 不得为了适配任何机制而被放宽（工程纪律 #1）；已批准 SDD 中「降为全局口径」「删用例换绿」「不可判静默放过」三条仍是禁止项。

**四查（FR-17 对例外登记面的确定性要求）**

| 查 | 结论 |
|---|---|
| 幂等 | 同一稳定标识重复登记 → `EXCEPTION_DUPLICATE` 红（不产生重复条目）；同一例外在同一到期日内重复检查结论一致（判定只读登记值 + 运行时瞬时，不看检查次数）；`--report` 模式判定与 `--run` 判定同源同一函数 |
| 权限与写入边界 | 唯一写入口 = **人类编辑 `gate-registry.json` + git commit**（谁=commit author、何时=commit time、为什么=commit message；`git log -- gate-registry.json` 即审计）。不新增 crctl 子命令/flag（FR-17）；门禁与测试**只读**该文件；静态断言：仓库内不存在对该文件的写入调用（`writeFileSync`/`appendFileSync`/`rmSync`/`renameSync`/`truncate`），且 `suite-gate` 自身无写路径 |
| 错误闭包 | 见下表；每类 = 固定 check code + 非零退出（唯一例外：表中明列为「可抑制」的 `SUITE_NONCONVERGENCE` 在有匹配未到期例外时不产生非零退出）+ 零写入（门禁从不写登记面，故「零写入」恒成立） |
| 副作用 | 登记只影响**判定**，不改变执行：`--run` 永远先真实执行全量清单；即使失败被容忍，报告仍列出 `failures[]`（登记不得替代执行）。门禁不修改被测仓、不写 `gate-registry.json`、不写 `.crctl/` 受治理账本 |

**固定 check code（关闭 S-4：可机械核对的固定标识，风格与既有 crctl gate check code 一致）**

| check code | 触发条件 | 可否被例外容忍 |
|---|---|---|
| `SUITE_REGISTRY_MISSING` / `SUITE_REGISTRY_SCHEMA_INVALID` | 登记文件缺失 / schema 不符（含字段缺失、类型错误、`expires` 无时区偏移） | 否 |
| `SUITE_REPORT_UNPARSEABLE` | 某文件的 TAP 结构不符（无顶层 plan、plan 与顶层结果行数矛盾、缩进栈不成对）或未产出任何可判结论（硬失败，禁止降级为空结果） | 否 |
| `SUITE_FILE_LOAD_FAILURE` | 某文件整体加载/执行失败：该文件子进程非 0 退出，且（a）其 TAP 中只有一条顶层 `not ok`、其名字为该文件绝对路径或以该文件名结尾（两目标运行时实测形态，§7.4 P2）；或（b）非 0 退出且顶层结果数为 0 | 否（FR-11.2：文件必须被真实执行） |
| `SUITE_MANIFEST_FILE_DRIFT` | 磁盘 `test/*.test.mjs` 实际集合 ≠ `manifest.files`（新增/删除文件即红）；或登记集合中存在未被真实 spawn 的文件 | 否 |
| `SUITE_MANIFEST_CASE_DROP` | 某文件实际顶层用例数 < `manifest.cases` 基线 | 否 |
| `EXCEPTION_FIELD_MISSING` / `EXCEPTION_SCHEMA_INVALID` / `EXCEPTION_DUPLICATE` | 例外条目缺 id/kind/reason/owner/expires、kind 非枚举、重复 id | 否 |
| `EXCEPTION_EXPIRED` | `now >= expires`（UTC 瞬时，见 §2.1） | 否 |
| `EXCEPTION_NOT_OBSERVED` | 登记的例外在本次运行中**未出现**（陈旧登记） | 否 |
| `SUITE_FAILURES_UNREGISTERED` | 观测失败集合中存在未被未到期例外覆盖的失败 | 否（容忍在**触发条件内**实现：未到期例外覆盖的失败不计入本项，故已登记的失败不会触发本项；本项一旦触发即不可抑制） |
| `SUITE_NONCONVERGENCE` | `--run` 超过 `--max-runtime-ms` 仍未结束（被终止） | **可抑制（可绿）**：仅当存在一条未到期、`kind: suite-nonconvergence` 且稳定标识与本项匹配的登记例外；报告仍记 `converged: false` 与 `checks[SUITE_NONCONVERGENCE]`（事实永不隐藏）；无匹配例外 / 例外已过期 → 红 |

退出码：**0 当且仅当**上表无任一触发。例外的「容忍」只有两个确定落点（均已写死，不存在两读法）：

- `SUITE_FAILURES_UNREGISTERED`：容忍落在**触发条件内** —— 观测失败 − 未到期例外覆盖的失败；本项一旦触发即不可抑制；
- `SUITE_NONCONVERGENCE`：容忍落在**已触发项的退出码**上 —— 可抑制（可绿），条件 = 存在未到期、`kind: suite-nonconvergence` 且稳定标识匹配的登记例外（= PRD `FR-14` 示例「已知不收敛的配置」的落地形态）。

其余 check code（登记缺失 / schema 不符、报告不可解析、文件加载失败、清单漂移 / 用例数下降、例外面自身错误、陈旧例外登记）**一律不可容忍**。被抑制的项仍全程可见：`checks[]` 保留该 code（`ok:false` 且标注 `suppressed_by:<exception-id>`）、`failures[]` 与 `converged` 原样上报 —— 抑制只影响退出码，不影响事实面（关闭本轮 S-1）。

**非收敛分支的判定口径（关闭本轮 S-1 的两种读法）**：`converged = false`（`--max-runtime-ms` 到期仍有子进程未自行结束）时不做清单用例数核对与失败集合核对（报告记 `cases_executed = null` / `failures = []` 且不参与判定 / 相关 `checks[].not_evaluated = true`），只判定 `SUITE_NONCONVERGENCE` 与登记面自身错误（`EXCEPTION_*`）；但 `files[]` **必须原样保留每个文件的状态**（`ok|failed|file-load-failure|unfinished`）—— 「停滞时哪些文件仍在运行」是 FR-12 的收敛观测面，不得隐藏。`SUITE_REPORT_UNPARSEABLE` 只在「子进程已自行结束（`converged = true`）而 TAP 结构仍不完整」时触发 —— 终止导致的不完整是终止的后果，不是解析缺陷，两者不混算。
特例（本 CR 交付态）：`exceptions = []` ⇒ 退出码 0 当且仅当失败集合为空 —— 与 `AC-01` 逐字一致。

**`--run` 的两种失败粒度（新增，B-4）**：文件级失败（加载失败 / 实例未执行）与用例级失败（顶层 `not ok` 且名字是用例名）都进 `files[]`；`failures[]` 只收用例级失败名，文件级失败由 `SUITE_FILE_LOAD_FAILURE` 单独承载（与 §2.1 术语表一致：「与文件级加载失败分开计数」）。

#### 3.3 不新增用户可调用契约（FR-17）

不新增 crctl 子命令/flag、不新增 HTTP 端点、不改 Skill 参数契约、不新增受治理账本写路径。新增的 `suite-gate.mjs` / `assertion-sources.mjs` / `gate-registry.json` / `outbox-contract.mjs` 全部是仓库内部面（CI 与测试），使用方 workspace 不可调用。

#### 3.4 HTTP / REST 契约

N/A —— 本 CR 不新增或修改任何 HTTP API（PRD 无 HTTP 契约；tools 包无服务端）。

---

### 4. 关键算法与流程

#### 4.1 状态机推导（FR-1 / FR-3 / FR-6）

`assertion-sources.mjs#deriveStateMachine(toolsRoot)`：

```text
1. 读 dir-graph.yaml → 先做 \r\n → \n 规范化（工程纪律 #1）
2. doc = parseYaml(norm, { strict: true })                     // lib/yaml-subset.mjs（既有、零依赖）
3. sm = doc['change-request-track'].state_machine
   缺字段 / 结构不符 → throw（硬失败，禁止返回空集合）
4. declarations = sm.transitions                      // 每条 { from, to, trigger }
5. wildcards    = sm.wildcards || {}                  // 名 → 目标数组
6. namedStates  = 所有 from/to ∪ 所有 wildcard 目标，剔除 '(new)' 与 wildcard 名（按声明序去重）
7. expanded     = Σ declarations: wildcards[t.from]?.length ?? 1
   当前实测：31 条声明、2 条 from=any-active、any-active 12 个目标 → 31 − 2 + 12×2 = 53
8. identifiers  = declarations.map(t => `${t.from}|${t.to}|${t.trigger}`)（集合比较，抗行序变化）
9. 结构自检（推导侧；对同一批 declarations **恒真**，不作为覆盖率或断言项，只把「推导自身写错」暴露成异常）：
   - 每条声明的 from/to ∈ namedStates ∪ {'(new)'} ∪ wildcard 名
   - 每条 wildcard 的目标 ⊆ namedStates
   - namedStates ∩ wildcard 名 = ∅
```

断言（`crctl.test.mjs` BR-3 位置，替换 `:4789`/`:4792` 的 28/50）：

```text
推导集合 ≡ gate-registry.stateMachine.*（具名状态集合 / wildcard 目标集合 / 转换标识集合）
且 expanded 计数 ≡ 由登记集合自洽推出的值
⇒ 向 dir-graph.yaml 增删任意一条转换或 wildcard 目标，集合比较失败 → 本测试红（AC-06 负控）
```

**反恒真设计**：登记值不是「当前读到的值」（不是 `declared.length === declared.length` 型重述），而是**上一轮显式登记的目标值**；推导与登记是两条独立来源，二者相等才通过。承重断言只有上面三条集合/计数等价；**推导侧结构自检恒真、不计入覆盖**（关闭本轮 S-2，避免被读成检查项）。

#### 4.2 全量套件门禁（FR-11 / FR-12 / FR-14）

`suite-gate --run` 主干（伪代码）：

```text
registry = readJson(gateRegistryPath)          // 缺失/坏 → 硬失败（check code 表）
diskSet  = readTestFileSet(toolsRoot)          // 磁盘 `test/*.test.mjs` 升序文件名集合（空集合硬失败）
manifestSet = registry.manifest.files
diskSet ≠ manifestSet → SUITE_MANIFEST_FILE_DRIFT（立即红，不降级）

// 逐文件 spawn：归属在 spawn 时由包装器持有，不从任何报告读取（I1）——池大小 = CONCURRENCY 常量（TDEC-4）
for file of manifestSet（池并发 = CONCURRENCY，按登记面顺序取任务）:
    child = spawn(['node', '--test', '--test-reporter=tap', abs(file)], { cwd: toolsRoot, shell: false })
    捕获：该子进程 stdout（= 该文件的 TAP，不与他人混流） + 退出码 + 墙钟
池整体计时；超过 --max-runtime-ms 而仍子进程未自行结束 → killTree(仍在运行的子进程树) → converged = false（SUITE_NONCONVERGENCE）
records = manifestSet.map(f => ({ file: f, exit_code, converged, tap }))   // 落 NDJSON（--report-out）

files[] = records.map(r => parseFileTap(r))    // 单文件解析，见下方解析规则；失败 → SUITE_REPORT_UNPARSEABLE
  → 每项 { file, state, exit_code, cases: 顶层结果数, failures: 顶层 not ok 用例名, skipped, todo, duration_ms }
  文件级失败（SUITE_FILE_LOAD_FAILURE 判定成立）→ state = 'file-load-failure'（仍计入 files[]，从 failures[] 剔除）

checks = []
checks += manifestCheck(files, registry.manifest)    // 每文件 cases ≥ 基线；skipped_file_level = 顶层结果为 0 的文件数
checks += exceptionCheck(registry.exceptions, files, nowUtc)   // schema/到期/双向匹配
checks += failureCheck(union(files[].failures), rc, liveExceptionIds)    // 差集为空
print human summary (command / observer / duration_ms / converged / files / cases / failures / checks)
writeNdjson(--report-out) ; writeJson(--json-out)  → §2.4 报告模型
exit(checks.anyFail ? 1 : 0)
```

**单文件 TAP 解析规则（必须硬失败；B-4 修订）**：以**单个文件**为单位解析（不再是「一份多文件报告里的文件名块」）。该文件的 TAP 必须同时满足：① 恰有一条**顶层** plan `1..N`；② 顶层结果行（缩进 0 的 `ok` / `not ok`）数 = N；③ 缩进栈自洽（子块闭合，无孤立 `...`）。`# SKIP` / `# TODO` 后缀分别计入 skip / todo。任一不满足 → 抛 `SUITE_REPORT_UNPARSEABLE`。**任何解析异常都不得返回「零失败」结果**（工程纪律 #1：跨行解析失败必须硬失败）。
- **为什么单一文件就够**：归属已由 spawn 构造给出（I1），解析器不需从文本推断「这是哪个文件」；它只看一个进程的一份 TAP。旧规则里的「文件名块 + file 级 plan」整段删除（该形态在目标运行时不存在，§7.4 P1/P2），仅 `SUITE_FILE_LOAD_FAILURE` 的判定会参考「顶层 `not ok` 的名字等于该文件路径/文件名」这一实测形态。

**解析自测（关闭本轮 S-3）**：`contract-scan.test.mjs` 用**内联单文件 TAP 片段**（合法片段 + 三类畸形片段：无顶层 plan、plan 与顶层结果行数矛盾、缩进栈不成对）构造 `--report <ndjson>` 输入，断言合法片段判绿、三个畸形片段各自落 `SUITE_REPORT_UNPARSEABLE` 且退出非零；**并补一条归属自测**：两条记录（**同一用例名**、不同 `file`）必须分别归属到各自文件（证明归属不来自用例名或报告文本，I1 的机械证据）—— 不新增测试文件、不新增 fixture 目录（`*.test.mjs` 集合仍为 21）。

**收敛与停滞的可观测化**：`converged=false` 时 `duration_ms` 记池整体实际墙钟、`exit_code=null`、报告保留已结束子进程的 TAP 内容与每个文件的 `files[].state`（未结束者 = `unfinished`）；`--run` 的 stdout 打印固定字段（命令 / 观察通道 / 耗时 / 是否停滞 / 结论），使 AC-10 的证据无需人工回忆，并让 FR-12 的「停滞根因」可归因到**具体文件**（不再只有一句「父进程空闲、子进程停滞」）。

**进程树终止**：POSIX 用 `detached:true` + `process.kill(-pid, 'SIGKILL')`；Windows 用 `taskkill /PID <child.pid> /T /F`。**只终止本包装器自己 spawn 的 PID 树**，不按名字终止任何进程。

#### 4.3 去重比较投影（FR-8 / FR-10）

```text
buildOutboxEvent(input, now):
  返回 { v:1, event_kind, cr_id, from_status:'', to_status:'', trigger:'',
         commit_sha:'', actor:'', evidence:{}, payload:{}, occurred_at: now }
  （字段集合 = OUTBOX_COMPARED_FIELDS ∪ OUTBOX_EXCLUDED_FIELDS，顺序固定）

buildOutboxComparable(event):
  out = {}; for (f of OUTBOX_COMPARED_FIELDS) out[f] = event[f]
  payload = { ...event.payload }
  for (k of OUTBOX_VOLATILE_PAYLOAD_KEYS) delete payload[k]   // 'detected_at' = payload 根下键名（与 §3.1 常量同一键空间）
  out.payload = payload
  return out
```

判重不变（与现状逐字等价）：`exists(target) && comparable(existing) === comparable(event) → 命中`；否则不等 → `OUTBOX_DEDUP_CONFLICT`。

#### 4.4 文本语义断言（FR-2 / FR-4 / FR-5 / FR-7）

统一两步法：**先规范化行尾**（`replaceAll('\r\n','\n')`），再做「要素 + 零命中」两类断言；禁止把连接词、标点、语序、换行写进模式。

| 目标 | 机械断言（语义面） | 变红条件（负控） |
|---|---|---|
| BR-1 指令载体 | `skills/develop/write-dev-tasks/SKILL.md`：含 `crctl task init`；含对其受控账本 `tasks/_index.yml` 的「禁止手写」约束 | 删除任一要素 → 红 |
| BR-1 pipeline 语义 | `code-implementation.pipeline.json`：节点数 ≡ `pipeline-templates/_index.yml#code-implementation-v1.nodes`（跨文件投影）；所有节点 prompt 对受治理账本写指令零命中（命令面 `crctl (task init|task append|task done|advance|review-record|approve|owner-set|version-set)` 与账本文件名 `_index.yml` / `_backlog.yml`）；skill 节点 `ref` 存在 | 向任一 prompt 注入账本写指令 → 红 |
| BR-2 reader 事实源 | `skills/review/review-alignment/SKILL.md`：读取契约命中 `change-requests/_backlog.yml` 与 `cr.md`；`checkpoints[]` 零命中；`latest-checkpoint` **零命中**；`mtime` / `merge-commit` / `fingerprint` **不得作为事实源被读出**（机械判据见下方「否定辖域」） | 回退事实源（写回 `latest-checkpoint`、删 `_backlog.yml` 引用、或把 `mtime` / `merge-commit` / `fingerprint` 写成读取依据）→ 红 |
| BR-4 落盘校验语义 | `write-requirement-prd/SKILL.md`：定位含「重新读取」的校验句（先规范化行尾），断言该句内同时含三类对象——frontmatter 必填字段 / `七个章节` / `未替换占位符`；5 个禁用词零命中；`crctl validate` 与手工 commit 配方零命中 | 删除任一类对象或注入禁用词 → 红 |

> 「句内要素」判据：以中文句读（`。`/`；`/换行）切句后取命中断言锚点（`重新读取`）的那一句，再做要素包含判断。锚点本身就是被断言语义的一部分（该校验步骤的动词），不是措辞钉死对象。
> 「否定辖域」判据（BR-2 三词）：以**同一**句读切句后，对每个命中 `mtime` / `merge-commit` / `fingerprint` 的句子断言含否定锚点 `不读`；零命中同样满足。⇒ 把三词写成读取依据（非否定句）即红，而既有的「不读 mtime/merge-commit/fingerprint」表述不再被误判。**不对该文件要求零命中、也不回写该文件**：本机实测 `review-alignment/SKILL.md` 现共 2 处命中（`:33` 读取契约括号、`:51` 说明引用），均在含「不读」的否定句内。
> 现有实现提示：`write-requirement-prd/SKILL.md` 在 Windows 检出为 CRLF（本机实测失败输出含 `\r\n`），上述「先规范化」是硬要求。

#### 4.5 BR-5 构造修正（FR-8 / FR-9）

**构造 A：真实崩溃窗口（替换 RED-7 r2）**

```text
1. 正常跑一次 archive（r1）：归档 commit + archive 事件真实写入（内容 = 该 commit 的真实事件）
2. 定位 journal：<kb>/.crctl/transactions/archive/<cr>/<txId>/journal.json
   把 payload.outboxEmitted 置回 false（模拟「文件已写、journal 未标记」的崩溃窗口）；
   顺带确认 archive 事件文件仍在、内容未变
3. 重放 archive（r2，同一 spec-id）：
   断言 warnings = []、outbox = `archive-<cr>-<commit>.json`、事件文件数量仍为 1、
   文件字节内容与 r1 完全一致（不覆盖）、origin master commit 数不变、r3 重放不再生成事件
```

该构造不改任何产品语义与断言，只把「预写同名不同内容的占位文件」换成**内容确实与本事件一致的文件 + 未标记 journal**——即真实崩溃窗口。

**构造 B：同名但内容不同（新增用例）**

```text
1. r1 正常归档 → 事件文件 E 存在
2. 将 E 的内容替换为不同内容（例如 {"placeholder":true}），并把 journal 的 outboxEmitted 置回 false
3. 重放 archive：
   断言 warnings 含 EMIT_FAILED（event_kind=archive）；.crctl/audit.log 出现
   `OUTBOX_DEDUP_CONFLICT`（可见信号至少其一，二者此处同时具备）；
   E 的内容仍是步骤 2 写入的内容（未覆盖）；journal 的 payload.outboxEmitted !== true（保持 pending）
4. 删除冲突文件 → 再重放：outbox 返回 `archive-<cr>-<commit>.json`、warnings = []、
   origin master commit 数不变（零新 commit）、E 内容为真实 archive 事件、outboxEmitted === true（补发成功）
```

**回归保护**：CR-2026-052 TASK-08 的 `detected_at` 语义测试（`crctl.test.mjs` 既有 drift-audit 用例）必须保持绿（FR-8.3）。

#### 4.6 三类漂移负控协议（FR-13 / AC-11）

对每一类断言各做一次**真实注入**，注入后运行**全量命令**（`suite-gate --run`，即 CI 同款命令）记录非零退出与命中失败名，然后还原并确认重新变绿；注入物不得留在交付分支。

| # | 类别 | 注入动作（真实漂移） | 预期红点 | 还原 |
|---|---|---|---|---|
| N-1 | 状态机口径 | 向 `tools/dir-graph.yaml#state_machine.transitions` 增加一条真实转换（例如 `from: developing, to: developing, trigger: "crctl-test-injection"`） | `crctl.test.mjs` BR-3 用例（集合/计数不等） | 删除该行，`git status --short` 确认该文件干净 |
| N-2 | pipeline/Skill 文本语义 | 向 `write-requirement-prd/SKILL.md` 注入一个禁用词（例如 `validate-doc`）或删除「七个章节」要素 | `crctl.test.mjs` BR-4 用例 | 同上 |
| N-3 | 去重比较字段契约 | 在 `lib/outbox-contract.mjs#buildOutboxEvent` 增加一个未登记字段（例如 `observed_at`），或在 `OUTBOX_VOLATILE_PAYLOAD_KEYS` 增加未登记键 | `trace-outbox.test.mjs` 契约用例（字段分类不变性） | 同上 |

证据留存（S-2 固定字段）：每个注入点存 1 份 `test-evidence/cmd-NN.log`，内容 = 命令、`duration_ms`、`converged`、`exit_code`、失败名、注入 diff 摘要、还原后的重跑结论。**注意**：全量命令每轮耗时以实测为准（基线既有实测 894.8 s；本机名字过滤子集实测 23.8 s），负控总计需要 6 次全量运行（3 注入 + 3 还原），实施/测试期需按其预算排期。

---

### 5. 技术选型与替代方案

（决策记录仅在同时满足「难以逆转 + 无上下文会疑惑 + 有真实权衡替代」时记录，共 4 条。）

#### TDEC-1 门禁形态：包装器 + 逐文件子进程 + 单文件 TAP

- **Decision**：全量测试门禁由 `test/suite-gate.mjs` 包装（**逐文件** spawn `node --test --test-reporter=tap <file>`，池式并发）并解析**每文件自己的** TAP 后判定；CI 步骤只调用包装器。
- **Context**：FR-14 需要「登记但不得替代执行 + 到期即红 + 与真实失败集合双向匹配」，这些判定必须在**运行结果之上**做；FR-12 需要机械化的「耗时 / 是否停滞」证据；S-1 需要「每文件用例数」。上版把「每文件」寄望于单次多文件运行报告里的文件名块，已证伪（§7.4 P1/P2）——而归属一旦由 spawn 构造给出，这三个需求里最脆弱的一环（从文本推归属）就整个消失了。
- **Alternatives**：（a）全部塞进某个 `*.test.mjs`（否决：测试进程看不到其他文件的执行结果，且会让被测集合包含判定器本身）；（b）CI YAML 内联 shell+node 脚本（否决：命令与并发参数会同时出现在 CI 与文档两处，违反 FR-12.3「同一口径」）；（c）不引入包装器、只在测试里断言登记面（否决：残缺——无法覆盖「到期/集合差」语义）；（d）**单次多文件运行 + junit 的 `file` 属性**取归属（**否决，本机实测反例**：该属性在 v24.15.0 存在、在 CI 运行时 v20.20.2 不存在，§7.4 P3）；（e）单次多文件运行 + 自写自定义 reporter 的事件流（**不作为默认**：它把归属重新押在另一份外部报告 schema 上；已列入 §3.2 的**允许替代通道**之一，需双运行时探针 + `observer` 登记 + `review-code` 覆盖）。
- **Consequences**：多一个新脚本与单文件 TAP 解析面；外部耦合点从「TAP 的块结构」**收窄**为「单文件 TAP 的顶层 plan 与其顶层结果行数一致」（§7.4 P9 两运行时实测一致），且解析不符即硬失败；停滞可归因到具体文件（TDEC-4）；不再依赖 glob / 目录发现 / isolation 开关 / junit `file`（均已实测跨版本不一致，§7.4 P3、P5、P6、P7）。

#### TDEC-2 受控清单承载：仓库内 git 跟踪的 JSON 数据文件

- **Decision**：`test/gate-registry.json` 承载状态机登记值、测试清单基线与例外登记处；唯一变更入口 = 人类编辑 + commit。
- **Context**：需要「单一登记处」（FR-14.1）、「可审计的受控写入」（FR-17/S-4）、「测试代码不得自证绿」（FR-14.4），且不能新增 crctl 子命令（FR-17）。
- **Alternatives**：（a）新建 `crctl exceptions` 子命令（否决：直接违反 FR-17，且账本写路径违背本 CR「断言只读」边界）；（b）把清单写死在测试代码里（否决：测试文件被改与被测对象被删会在同一处，留痕弱；且门禁包装器需要读同一份清单）；（c）放 `docs/` 或 `.github/`（否决：与测试同生命周期、由同一批 CR 维护，放在测试目录最贴近消费方，但**不是** `*.test.mjs` 所以不被 runner 采集）。
- **Consequences**：登记值变更必须显式提交（这正是「漂移当场红、除非显式更新目标值」的实现方式）；数据文件 schema 校验必须硬失败。

#### TDEC-3 去重契约落点：库模块代码常量

- **Decision**：字段分类与投影函数落在 `lib/outbox-contract.mjs`，产品（`crctl.mjs`）与测试共同 import。
- **Context**：FR-10 要求「单一事实源，不得同时存在两份（注释一份、代码一份）」，并要能被测试断言。
- **Alternatives**：（a）运行时读 JSON 数据文件（否决：新增运行时 I/O 失败面，且 `emitOutboxEvent` 已在失败路径上，读文件失败会放大为业务失败）；（b）仅保留注释 + 测试内复制一份期望（否决：正是 FR-10 要消灭的双份）；（c）`gates.json` 加段（否决：该文件语义是状态/审批门禁映射，混入 outbox 契约会破坏其「运行时适配信息」定位）。
- **Consequences**：产品 import 面新增一个本地模块（零依赖、无副作用）；`crctl.mjs` 中原来的长注释收敛为指针，避免第二份语义描述。

#### TDEC-4 并发处置：包装器池大小常量（与 `--test-concurrency` 同语义），按有界实测协议定值

- **Decision**：逐文件 spawn 后，**并发度不再由 runner 参数控制，而由包装器内唯一常量 `CONCURRENCY`（池大小）控制**（与 Node `--test-concurrency=N` 的「N 个文件并行」同语义，§7.4 P8）；设计默认 = **runner 默认并发的等价物** `max(1, availableParallelism() - 1)`，候选集 = {默认、2、1}；若实测表明默认不收敛，则按 FR-12.2 降为 `1`（或 `2`）并同样留存证据。**不论哪个分支，交付必须带 §4.6 口径的实测证据。**
- **Context**：CR 输入约束（owner 转交）记录 `--test-concurrency=2` 下「本机 30+ 分钟不收敛（父进程空闲、子进程停滞）」；既有实测的全量 894.8 s（失败恰 5 条）未标注并发口径 —— 即：唯一有「不收敛」观测的配置就是 `=2`，没有任何观测支持必须保留它。本机名字过滤子集实测 23.8 s/22 用例，说明断言面本身并不慢，慢/挂来自全量并发调度。池式执行额外买到一个观测面：停滞时能指名**哪个文件**仍在跑（§2.4 `files[].state=unfinished`）。
- **Alternatives**：（a）原样保留多文件 + `=2` 并只补文档（否决：会把「已知不收敛观测」的配置固化成门禁，且 FR-12.1 要求「保留须有 CI 可收敛证据」，本地不可得）；（b）直接写死池 = 1（否决：无实测依据的顺序化可能使全量时间翻倍，且掩盖真正的停滞根因）；（c）不定值也不留测量（否决：AC-10 要求可复现证据）；（d）逐文件顺序跑（否决：与池 = 1 等价但不引入池的话便无法在保持归属的同时并行）。
- **Consequences**：CI 与本地同命令模板、池大小变更只改一个常量；由 `--max-runtime-ms`（默认 30 min）把「停滞」从「无限挂起」变为「可观测、可归因、可登记的非收敛」；耗时对比的口径必须在证据里写明（池 = 2 与旧多文件 `--test-concurrency=2` 同调度语义，§6.2 AC-14）。

---

### 6. FR 到技术实现映射

#### 6.1 FR 映射表

| FR | 技术方案条目 | 落点 |
|---|---|---|
| FR-1 计数类推导 | §4.1 状态机推导 + §4.6-D2/D3 跨文件投影与目录事实源 | `assertion-sources.mjs`、`crctl.test.mjs` BR-3、`suite-gate` 清单核对 |
| FR-2 文本类只查语义 | §4.4 两步法（规范化 + 要素/零命中） | BR-1/2/4 三条断言 |
| FR-3 反风险与归类 | §6.6 归类清单（D1…D6 / P1…P7）+ §4.1 反恒真设计 + 负控 | 本 SDD §6.6、`crctl.test.mjs` |
| FR-4 BR-1 对齐真实载体 | §4.4 第 1、2 行 | `crctl.test.mjs:1337` |
| FR-5 BR-2 对齐 reader 事实源 | §4.4 第 3 行 | `checkpoint-tx.test.mjs:480` |
| FR-6 BR-3 推导 + 登记 | §4.1 + §2.3 `stateMachine` 段 | `crctl.test.mjs:4777`、`gate-registry.json` |
| FR-7 BR-4 语义要素 | §4.4 第 4 行 | `crctl.test.mjs:4989` |
| FR-8 保留去重语义 | §3.1 行为等价 + §2.2 字段归类 | `lib/outbox-contract.mjs`、`crctl.mjs` |
| FR-9 冻结向量构造改对 + 真实冲突用例 | §4.5 构造 A / B | `archive-tx.test.mjs:373` 与新增用例 |
| FR-10 去重契约可检查 | §3.1 不变性（字段分类 / 枚举排除 / 投影闭合 / 只读投影） | `lib/outbox-contract.mjs` + `trace-outbox.test.mjs` |
| FR-11 CI 真门禁 | §4.2 全流程 + 清单核对（21 文件集合相等） | `suite-gate.mjs`、`crctl-ci.yml:109-111` |
| FR-12 并发收敛决定 | TDEC-4 + §3.2 报告字段 + §4.2 停滞可观测化 | `suite-gate.mjs`（常量 + `--max-runtime-ms`） |
| FR-13 漂移负控 | §4.6 协议（3 类注入 + 全量命令 + 证据字段） | 实施/测试期证据 `test-evidence/cmd-NN.log` |
| FR-14 例外治理 | §2.3 `exceptions` + §3.2 四查与 check code 表 | `gate-registry.json`、`suite-gate.mjs`、`contract-scan.test.mjs` |
| FR-15 最小改写 | §1.2 变更面（产品面仅 outbox 契约提级）+ §9 scope_in/out | 全 diff |
| FR-16 零回归 | §4.4/§4.5 的负控与回归保护 + §2.3 `manifest.cases` ≥ 基线 | 全量套件 |
| FR-17 契约面与四查 | §3.3 无新增用户可调用契约 + §3.2 四查结论 | 本 SDD §3.2/§3.3 |

#### 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-01 | `suite-gate --run`（§4.2）；`exceptions=[]` 时退出码 ≡ 失败集合为空 | CI 步骤退出码 0；报告 `failures=[]`、`files_executed=21`、`files[]`恰 21 条且全为 `state=ok`、`skipped_file_level=0`、`cases_executed>0` | 5 条红的修复（FR-4…FR-9）都在本 CR 内；`21` 由 `manifest.files` 登记并与**磁盘集合**核对；per-file 归属由逐文件 spawn 给出（I1，不依赖报告块结构）；不依赖任何 skip/删除 |
| AC-02 | §4.4 断言→事实源两列表 + §6.6 分类清单 | 交付内含映射表；每条可用命令复取事实源；负控 N-1/N-2 使其变红 | 映射覆盖 BR-1…BR-4 涉及的计数/文本/跨文件投影三类；负控为可重放命令 |
| AC-03 | §6.6（D/P 两张表）+ §4.1 反恒真 | 归类清单逐条；`stateMachine.*` 显式登记；无「等于文件行数」型重述 | P 表由登记值承载，D 表由推导承载，二者独立来源 → 恒真式不可能同时满足集合比较与负控 |
| AC-04 | §4.4 BR-1 两行 | `crctl.test.mjs:1337` 用例绿；pipeline 零账本写指令；`write-dev-tasks` 载体含指令 | 只改测试断言（FR-15.1），产品文本零 diff |
| AC-05 | §4.4 BR-2 行 | `checkpoint-tx.test.mjs:480` 绿；`review-alignment/SKILL.md` 未新增 `latest-checkpoint`；三词仅在否定句内出现 | 断言对象是**当前**事实源（`cr.md` + `_backlog.yml` 条目信息），不需要改 SKILL 文本——该文件对 `latest-checkpoint` / `checkpoints[]` 当前零命中，三词的 2 处既有命中均在含「不读」的否定句内（本机实测），故断言按事实源现状成立 |
| AC-06 | §4.1 + §2.3 | 状态机用例绿；声明/展开由推导得出；具名状态与转换标识集合显式登记；负控 N-1 变红 | 推导源（`dir-graph.yaml`）与登记源（registry）独立，承重断言 = 三条集合/计数等价；推导侧结构自检恒真、仅作诊断（不计入覆盖） |
| AC-07 | §4.4 BR-4 行 | `crctl.test.mjs:4989` 绿；5 禁用词零命中；负控 N-2 变红 | 句内要素检查覆盖「删除校验步骤语义」与「注入禁用词」两种注入 |
| AC-08 | §4.5 构造 A/B + 回归保护 | RED-7 绿且构造为「内容一致 + journal 未标记」；新用例断言 `EMIT_FAILED`/`OUTBOX_DEDUP_CONFLICT`、pending、补发成功零新 commit；BR-5 语义未变 | 构造只动测试与 fixture journal 状态；产品零语义变更（§3.1 契约等价），drift-audit 既有用例不在改写面内 |
| AC-09 | §3.1 不变性 2/3/4 + §4.3 | `trace-outbox` 契约用例绿；字段分类集合相等；`payload.observed_at` 反例证明非自动排除；投影结果与 `OUTBOX_VOLATILE_PAYLOAD_KEYS` 交集为空；负控 N-3 变红 | 新增字段必须登记进两个集合之一、新增易变键必须登记进 `OUTBOX_VOLATILE_PAYLOAD_KEYS`，否则集合相等 / 投影闭合断言直接失败（不依赖人工比对） |
| AC-10 | TDEC-4 + §3.2/§2.4 固定字段 | 交付含 `command/observer/duration_ms/converged/exit_code` 与结论；停滞时 `files[].state=unfinished` 指名停滞文件；CI 与文档同口径（命令只来自包装器常量） | 默认分支（池 = runner 默认等价物）与回退分支（池 = 1 或 2）都在包内可执行；`--max-runtime-ms` 保证「停滞」可产出证据而不是无限挂起 |
| AC-11 | §4.6 | N-1/N-2/N-3 各一次注入 → 全量命令红 → 还原后绿；命令与关键输出留 `test-evidence/` | 注入点全部在本 CR 的断言覆盖面上；注入物由 `git checkout -- <path>` 还原并核验干净 |
| AC-12 | §2.3 `exceptions` + §3.2 | 交付态 `exceptions: []`（显式空，非文件缺失）；构造到期条目 → `EXCEPTION_EXPIRED` 非零；登记面写入口仅人工提交；`contract-scan` 静态断言无代码写路径 | 到期判定只用运行时瞬时 + 登记时间戳，确定性；「不匹配即红」由双向集合比较实现 |
| AC-13 | §1.2 变更面 + §9 scope | diff 仅 tests / CI / `lib/outbox-contract.mjs` + `crctl.mjs` 的最小改点；BR-1…BR-4 产品面零 diff；无新增依赖/框架 | 产品面改点仅 `emitOutboxEvent` 的契约提级，`git diff --stat` 可逐条核 |
| AC-14 | §2.3 `manifest.cases` + §4.4/§4.5 | 全量 21 文件无新增红、无新增 skip（`skipped_file_level=0`）；交付含与 894.8 s 同口径的耗时对比 | 用例数 ≥ 基线为门禁硬约束（逐文件在 `files[].cases` 可核）；耗时对比的口径在证据里写明：894.8 s 基线 = 多文件 + `--test-concurrency=2`，池 = 2 与之同调度语义（TDEC-4） |
| AC-15 | §3.2 四查 + §3.3 + §8 | 交付声明无新增用户可调用契约；例外面四查逐条结论；未新增对外入口 | 本 CR 无 crctl dispatch/deny 面变更（§8 已核） |

#### 6.3 既有实现依赖与事实

按正文首次出现顺序登记（固定结构）。所有 `commit SHA` = `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`（本机实测 `git rev-parse HEAD`，CR worktree clean）。

```text
1. repo: tools
   relative path: dir-graph.yaml
   stable symbol/对象: change-request-track.state_machine.{transitions, wildcards.any-active, terminal}
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 推导的唯一事实源。本机实测（lib/yaml-subset.parseYaml 解析）：声明转移 31 条、
             其中 from=any-active 2 条、any-active 目标 12 个、结构推导展开数 31-2+12*2=53；
             具名状态 15 个，注册前态 (new)。本 CR 不改该文件，只把它读成推导输入。

2. repo: tools
   relative path: skills/shared/crctl/scripts/lib/yaml-subset.mjs
   stable symbol/对象: parseYaml(text, { strict })
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 零依赖 YAML 子集解析器，本机实测可正确解析上述状态机段（transitions/wildcards 结构完整）。
             本 CR 复用它做推导，避免新增解析依赖与第二套正则口径（ARCHITECTURE 不变量 3）。

3. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: emitOutboxEvent（:293 起）；内联比较块（:320-346，含 comparable() 与 payload.detected_at 特例）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 现状判重语义 = 逐字段内容相等（排除 payload.detected_at）；不等 → OUTBOX_DEDUP_CONFLICT →
             调用方 EMIT_FAILED。本 CR 保留该语义，仅把「哪些字段参与比较」从注释提为可检查声明（§3.1）。

4. repo: tools
   relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
   stable symbol/对象: archiveCr（:3449）/ emitArchiveIfNeeded（:3510 附近，payload.outboxEmitted 语义）/
                       archive 事件发送点（:3520）/ cleanup-pending 落盘（:3683, :3705）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: archive 事件在 origin confirmed 后、cleanup 前发送；发送失败只追加
             {code:'EMIT_FAILED'} warning、不改变 phase、且不置 payload.outboxEmitted；
             phase=complete 的历史 journal 重放仍会重试事件且不新增 commit。
             本 CR 的 RED-7 构造与「同名不同内容」用例据此断言 pending 与可补发（§4.5）。

5. repo: tools
   relative path: skills/shared/crctl/scripts/test/merge-fixture.mjs
   stable symbol/对象: 导出 `sha256`(:11) / `git`(:14) / `runCrctl`(:20) / `makeFixture`(:27) / `makeCodeApprovedFixture`(:95) / `originMasterCount`(:197)
                       （本机实测：该文件共 6 个 `export`，无其他导出形式）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 既有共享 fixture；本 CR 的 archive 用例与状态机用例沿用同一构造方式（`makeCodeApprovedFixture` 造 code-approved 场景，
             `git` / `runCrctl` / `sha256` / `originMasterCount` 做断言与计数），不新增 fixture 框架。

6. repo: tools
   relative path: skills/shared/crctl/scripts/test/archive-tx.test.mjs
   stable symbol/对象: 文件内局部 helper `makeWritebackFixture`(:14) 与 `archiveOutboxFiles`(:231)
                       （两者是本文件局部函数，**不在 `merge-fixture.mjs` 中**；本机实测）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: RED-7 所在文件的构造面——用例体（:374）用 `makeWritebackFixture` 造 kb 场景、:393 用
             `archiveOutboxFiles` 枚举 outbox 事件文件。本 CR 的 RED-7 构造改对与「同名不同内容」新用例
             沿用这两个局部 helper，**不上提**到共享 fixture（不扩大 diff、不影响其他测试文件）。

7. repo: tools
   relative path: .github/workflows/crctl-ci.yml
   stable symbol/对象: 步骤 `crctl full test suite`（:109-111）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: 现状命令 = `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs`
             （无例外、无 skip 白名单）。本 CR 把该步骤改为调用 suite-gate（§4.2），命令单一来源迁入包装器常量。

8. repo: tools
   relative path: skills/develop/write-dev-tasks/SKILL.md
   stable symbol/对象: `crctl task init` 指令（:106）与受控账本禁手写约束（:115）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: BR-1 断言对象的真实载体——该指令的权威落点是本 SKILL，而不是 pipeline JSON。

9. repo: tools
   relative path: pipeline-templates/code-implementation.pipeline.json
   stable symbol/对象: nodes[16]；`crctl task init` / `_index.yml` / 手写索引 指令均为零命中（本机实测）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: BR-1 的另一半断言对象（pipeline 只编排 Skill）。节点数的登记处 =
             pipeline-templates/_index.yml#code-implementation-v1.nodes（本机实测 = 16），
             断言以跨文件投影形式读取该值，不在测试里写第二份 16。

10. repo: tools
   relative path: skills/review/review-alignment/SKILL.md
   stable symbol/对象: 读取契约第 2 条（读 cr.md frontmatter + _backlog.yml 条目基本信息；不读 mtime/merge-commit/fingerprint；检查清单 AL-01…AL-06）
   commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
   依赖结论: BR-2 断言对象。本机实测该文件对 `checkpoint` 零命中；当前事实源是 cr.md + _backlog.yml 条目信息。

11. repo: tools
    relative path: skills/requirement/write-requirement-prd/SKILL.md
    stable symbol/对象: Step 4 落盘后重新读取校验句（:89）
    commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
    依赖结论: BR-4 断言对象。现文为「七个章节、未替换占位符」（连接词已由 AIFI-22 改为顿号），
              5 个禁用词零命中；本机实测该文件在 Windows 检出为 CRLF → 断言必须先做行尾规范化。

12. repo: tools
    relative path: skills/shared/crctl/scripts/test/*.test.mjs
    stable symbol/对象: 测试文件集合 = 21 个（本机实测目录计数）
    commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
    依赖结论: manifest 基线的登记对象；本 CR 不新增测试文件，交付后仍为 21 个。

13. repo: tools
    relative path: skills/shared/crctl/scripts/test/archive-tx.test.mjs
    stable symbol/对象: `TASK-01 RED-7`（:373）——当前构造预写「同名但内容不同」的占位文件
    commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
    依赖结论: owner 裁定「构造改对」的对象（§4.5）；原断言集合全部保留。

14. 基线红登记（本 CR 的起点事实，不是方案前提）
    repo: tools / commit SHA: dddd0ad63fb79bd7608314b4553f30e8ce7b7289
    本机实测（SDD 作者，2026-09-13，Windows / Node v24.15.0，CR worktree clean）：
      命令: node --test --test-name-pattern="CR-2026-037|checkpoint T05|TASK-06|CR-2026-042|RED-7"
            skills/shared/crctl/scripts/test/{crctl,checkpoint-tx,archive-tx}.test.mjs
      结果: exit 1；tests 22 / pass 17 / **fail 恰 5** / skipped 0；duration 23.8 s
            （其中 RED-7 单独 23.7 s）
      5 条失败与本 CR 的 BR 编号一一对应:
        BR-1 crctl.test.mjs:1337 `CR-2026-037 Prompt 采纳：Skill/Pipeline 调 task init 且不指导直写索引`（引入 14b4458）
        BR-2 checkpoint-tx.test.mjs:480 `checkpoint T05 contract：Pipeline 只编排 Skill，active alignment reader 不读旧 checkpoints[]`（引入 fc2b142）
        BR-3 crctl.test.mjs:4777 `TASK-06 ⑤: release-drift 单一回退转换 code-approved -> developing 合法；状态机口径 28 声明/50 展开（AC-3）`（实测 31 ≠ 登记 28；引入 bef1f4d + 2e4442d + 49c46dd）
        BR-4 crctl.test.mjs:4989 `CR-2026-042 静态合同：已知 Skill 越界文本零命中`（断言「和」措辞，现文为「、」；引入 fc797ed）
        BR-5 archive-tx.test.mjs:373 `TASK-01 RED-7：预存确定性 dedup 文件 → 命中同名补记，数量不增、内容不覆盖`（构造失真）
    既有实测（非本机本轮，来自 CR 输入与 PRD §1.3，作者与 reviewer 各自独立跑过一次）：
      全量 21 个 *.test.mjs（不带例外）= exit 1 / 894.8 s / 失败恰 5 条；
      CI `contracts` job 其余 5 步（lint-prompts / skill-matrix / agents-contract / pipeline JSON 结构 / writeback 单测）
      在本机（Windows / Node v24.15.0）逐步全绿，CI 平台为 ubuntu+windows / Node 20，跨平台差异未验证。
    依赖结论: 上述红是**既有事实**，本 CR 的交付目标正是把它清空（AC-01）。
              本 SDD 全文不把「CI 现在是绿的」作为前提或依赖断言；「绿」只作为本 CR 变更后的实测结论出现。
```

#### 6.4 待核实依赖

| 项 | 状态 | 处理 |
|---|---|---|
| `tools/ARCHITECTURE.md` §5 不变量 5 的「28 条声明、wildcard 展开 50 条」 | 与 `dir-graph.yaml` 当前内容（31 / 53）**不一致**（既有文档口径滞后，非本 CR 引入） | **不作为本 CR 方案前提**：本 CR 的登记目标值全部从 `dir-graph.yaml` 推导并登记到 `gate-registry.json`，方案不读该段文本；修正该段列入 §9 `follow_up`（ARCHITECTURE.md 对普通 CR 只读，其 §8 维护规则规定该类修订需独立触发） |
| CI（ubuntu+windows / Node 20）上的全量耗时与收敛性 | 本机不可得 | 按 S-2 口径：证据以「本机复现 + 可得时的 CI 运行」交付；AC-10 只要求「可复现证据」，不在本地伪造 CI 事实 |
| CI 平台（ubuntu）上单文件 TAP 的产物形态与池式并发行为 | 本机不可得（本轮回修只在本机 Windows 上跑探针） | 设计的外部耦合点（单文件 TAP 顶层 plan ↔ 顶层结果行数，§7.4 P9）已在**本机 v24.15.0 + CI 同版本 v20.20.2** 上验证（§7.4）；平台差异属实施/测试期证据面；解析不符即硬失败红（I3），不存在静默通过 |
| 包装器池大小（`CONCURRENCY`）的收敛性 | 需实测 | TDEC-4 的协议：候选 {runner 默认等价物、2、1} 各 ≥2 次连续运行；选中者写入包装器常量，且报告 `command` 记录展开规模与池值 |
| 全量 21 文件在**本机制**（逐文件 spawn + 池）下的耗时与停滞面 | 本机不可得（单次全量 ≈ 15 min 量级；本轮回修不重跑全量） | 交付期按 §4.6/§5.4 预算实测留证；本轮回修的证据范围仅到「两运行时单文件/双文件形态一致」（§7.4 P9/P10），不转述任何未跑的值 |

#### 6.5 SDD-CLOSE（PRD/评审显式延后到 SDD 的设计项，逐项关闭）

| 编号 | 来源 | 关闭结论 |
|---|---|---|
| SDD-CLOSE-01 | S-1（测试清单受控） | 关闭：`gate-registry.json#manifest`（文件集合相等 + 每文件用例数 ≥ 基线）由 `suite-gate` 在 CI 硬校验；「删测试换绿」必须同时改受控数据文件并在 diff 中留痕 |
| SDD-CLOSE-02 | S-2（证据口径与固定字段） | 关闭：口径 = 本机复现 + 可得时的 CI 运行；字段写死 = §2.4 报告模型（command/duration_ms/converged/exit_code/files/cases/failures/checks） |
| SDD-CLOSE-03 | S-3（any-active 目标集合并入受控清单） | 关闭：`gate-registry.json#stateMachine.wildcards`；目标增删即红（§4.1） |
| SDD-CLOSE-04 | S-4（受控写入入口 + 固定 check code） | 关闭：写入口 = 人类编辑 + git commit（审计 = `git log -- gate-registry.json`），无新 crctl 入口；check code 表见 §3.2 |
| SDD-CLOSE-05 | S-5（到期定义收紧） | 关闭：带时区偏移的 ISO-8601 时间戳，比较基准 = 门禁运行时 UTC 瞬时，`now >= expires` 即过期（§2.1） |
| SDD-CLOSE-06 | FR-14.4（不得自证绿） | 关闭：门禁只读登记面（无写路径）+ `contract-scan` 静态断言「仓库内无对登记文件的写调用」+ 登记不替代执行（失败始终上报） |
| SDD-CLOSE-07 | FR-10（契约落点） | 关闭：`lib/outbox-contract.mjs` 单一事实源（TDEC-3），产品与测试共同 import |
| SDD-CLOSE-08 | FR-17（契约面声明） | 关闭：不新增用户可调用契约（§3.3）；例外登记面四查逐条结论见 §3.2 |
| SDD-CLOSE-09 | 本轮评审 S-1（`SUITE_NONCONVERGENCE` 的可容忍性两读法） | 关闭：显式定为「可抑制（可绿）」，条件 = 未到期 + `kind: suite-nonconvergence` + 稳定标识匹配；事实面（`converged:false`、`checks[]`、`failures[]`）永不隐藏；非收敛分支不做清单/失败集合核对、不混算 `SUITE_REPORT_UNPARSEABLE`；其余 check code 一律不可容忍（§3.2 退出码段） |
| SDD-CLOSE-10 | 本轮评审 S-2（推导侧结构不变量恒真） | 关闭：§4.1 步 9 标注为「推导侧自检，恒真」并从断言块移出、不计入覆盖；承重断言只有三条集合/计数等价（§4.1、§6.2 AC-06） |
| SDD-CLOSE-11 | 本轮评审 S-3（TAP reporter 依赖未登记默认值） | 关闭：包装器的逐文件命令显式钉 `--test-reporter=tap`（§3.2/§4.2），并以**内联单文件 TAP 片段**在 `contract-scan.test.mjs` 做 `--report` 解析自测（合法 + 三类畸形），不新增测试文件（§4.2、§1.2）。**B-4 补充**：`--test-reporter=tap` 只负责「拿到一份扁平的 TAP」，**不再承担 per-file 归属**（归属改由 spawn 构造给出）—— 本项关闭不再依赖任何 reporter 的块结构 |
| SDD-CLOSE-12 | **B-4（本轮唯一 blocker，来自 `review-dev-plan` 的 upstream 阻断）**：已批准 SDD §3.4/§4.2 的 per-file 归属前提「TAP 文件名块 + file 级 plan」在目标运行时不存在 | 关闭：① 归属机制改为**逐文件 spawn + 逐文件观察**（§3.2 I1、§4.2）；② 文件集合漂移改为对**磁盘事实源**（`readTestFileSet`）核对，不再使用「从一份多文件报告里读出的实际执行集合」（§2.3、§3.2、§6.6 D3）；③ 每文件用例数 = 「单文件顶层 plan 与顶层结果行数一致」，逐文件与 `manifest.cases` 比对且写入报告 `files[]`（§2.3、§2.4、§4.2）；④ 机制失效时的**合法出口**写死在 §3.2「机制与替代」（替代通道唯一，需双运行时探针 + `observer` 登记 + `review-code` 覆盖，否则保持红）；⑤ §7.4 删除无证据的保证性陈述，代之以两目标运行时的实跑探针表（含命令形态差异 P1…P10），未在本机验证的部分进 §6.4。**不变量未放宽**：真实执行 / 每文件用例数 ≥ 基线 / 解析失败硬失败仍是硬约束 |

#### 6.6 FR-3 归类清单：可推导的事实 vs 必须钉死的目标值

**可推导的事实（硬编码其快照 = 缺陷）**

| # | 事实 | 事实源 | 推导方式 | 防恒真设计 |
|---|---|---|---|---|
| D1 | 状态机声明转移数 / 展开数 / wildcard 目标集合 | `dir-graph.yaml#state_machine` | `deriveStateMachine()`（parseYaml，硬失败） | 与显式登记的 P2/P3 集合比较；两条独立来源 |
| D2 | pipeline 节点数与节点结构 | `pipeline-templates/*.pipeline.json` ↔ `_index.yml#nodes` | 跨文件投影比较 | 任一侧单独漂移即红 |
| D3 | 测试文件集合与执行规模 | 磁盘目录集合（`readTestFileSet`）↔ `manifest.files`；每文件单进程 TAP 的顶层结果数 ↔ `manifest.cases` | 集合相等（新增/删文件即红）+ 逐文件计数 ≥ 基线 | 集合与计数都由**独立事实源**产出：磁盘目录（而非「runner 报告的实际执行集合」）+ 每文件自己的子进程；登记值由人工维护 |
| D4 | pipeline 是否指导直写受治理账本 | pipeline JSON prompt 文本 | 命令面/账本文件名扫描（零命中） | 注入即红（N-2 同类） |
| D5 | Skill 文本的禁用词与结构性载荷 | 相关 `SKILL.md` | 零命中 + 句内要素 | 注入/删除即红 |
| D6 | reader 事实源引用 | `review-alignment/SKILL.md` 读取契约段 | 命名标识在/不在 + 三词否定辖域（§4.4） | 回退事实源（写回 `latest-checkpoint` 或把三词写成读取依据）即红 |

**必须钉死的目标值（显式登记，不得由推导自动接受）**

| # | 目标值 | 登记处 | 变更纪律 |
|---|---|---|---|
| P1 | 具名状态集合（15 个；注册前 `(new)` 单列） | `gate-registry.json#stateMachine.namedStates` | 变更须显式更新登记值 |
| P2 | 每条声明转换的稳定标识 `(from,to,trigger)` | `#stateMachine.transitions` | 同上 |
| P3 | wildcard 名 → 目标集合（`any-active` → 12） | `#stateMachine.wildcards` | 同上 |
| P4 | pipeline 结构不变量（code-implementation 节点数 = 16） | `pipeline-templates/_index.yml#nodes`（既有登记处） | 变更须显式更新该字段 |
| P5 | 测试清单基线（文件集合 + 每文件用例数） | `#manifest` | 变更须在 diff 中显式提交 |
| P6 | 去重比较字段集合 + 必须排除的易变字段集合 | `lib/outbox-contract.mjs`（+ 测试中的钉死期望） | 变更须显式登记，否则字段分类不变性红 |
| P7 | 例外清单（交付态 = 空） | `#exceptions` | 逐条含 owner + 到期；到期未清即红 |

**不属本分类（fixture 局部计数，本 CR 不改动）**：测试自建 fixture 产生的计数断言（如 `events.length === 1`、`audits.length === 1`、`files.length === 1`、`repos.length === 3`）。判据：**被断言的数量由测试自身构造决定，不由仓库事实源读取**——这类断言随场景变化，硬编码是正确形态。属 `scope_out`（§9）。

---

### 7. 安全与性能考量

#### 7.1 边界条件与错误处理

- **行尾纪律**（ARCHITECTURE 不变量 4）：所有新断言与解析在 `replaceAll('\r\n','\n')` 之后进行（本机实测 `write-requirement-prd/SKILL.md` 为 CRLF 检出，BR-4 的失败输出即含 `\r\n`）。
- **解析硬失败**：状态机推导（结构不符）、**单文件 TAP 解析**（无顶层 plan / plan 与顶层结果行数矛盾 / 缩进栈不成对）、`gate-registry.json`（缺失 / schema 不符）一律抛错 → 非零退出，**禁止**降级为空集合或「零失败」；文件集合与磁盘不一致、文件未产出可判结论同样是硬失败（§3.2 I3）。唯一例外是登记面自身的可抑制项（§3.2）：子进程未自行结束时改判 `SUITE_NONCONVERGENCE`，且该分支不产生 `SUITE_REPORT_UNPARSEABLE`。
- **空集合必须显式**：`exceptions: []` 是显式声明；文件缺失是 `SUITE_REGISTRY_MISSING`（红），不是「无例外」。
- **不静默改写**：门禁判定全程只读；任何失败都不写 `gate-registry.json`、不写受治理账本、不改被测仓。
- **进程管理**：超时终止只针对本包装器自己的子进程树（POSIX 进程组 / Windows `taskkill /T`），不按进程名终止。

#### 7.2 安全控制点

- 例外登记面不得成为自证绿通道（FR-14.4）：写入口唯一（人工提交）、代码侧零写路径（静态断言）、失败始终上报。
- 断言不得被弱化为恒真（FR-3）：登记值与推导值独立来源 + 负控可重放。
- 断言只读：不改 `_backlog.yml` / `cr.md` / `approval.yml` / `tasks/_index.yml` 的写入路径（无新增写路径）。

#### 7.3 性能

- 推导与静态断言只读本地文件；**每个测试文件内不重复遍历全仓**——`assertion-sources.mjs` 对同一文件提供带缓存的读取；不引入网络与子进程风暴。
- 全量套件耗时：基线既有实测 894.8 s（失败恰 5 条）；本机名字过滤子集实测 23.8 s。TDEC-4 的协议要求交付同口径对比（`--run` 报告字段）。
- `--max-runtime-ms` 默认 30 min：把「停滞」从无限挂起变为可观测事件（`converged=false` + `SUITE_NONCONVERGENCE`）。
- 负控实验（§4.6）需 6 次全量运行，实施/测试期按实际耗时排期；不要求额外的基础设施。

#### 7.4 兼容性（外部运行时前提 = 本轮实跑探针，B-4）

> 上一版此处写的是「TAP 解析不依赖 Node 版本专有输出格式」—— 这是一句**无证据的保证性陈述**，且事实为假：已批准 SDD 的 per-file 归属前提正是押在它上面（§3.4/§4.2 旧文）。本节改为**两目标运行时的第一手实跑探针**；表内每一条均为本轮（2026-09-13，Windows 本机）实跑所得，**不转发任何转述值**。

**探针装置**：临时目录下四个文件 `a.test.mjs`（2 个通过用例）/ `b.test.mjs`（1 个）/ `c.test.mjs`（1 失败 + 1 通过）/ `d.test.mjs`（import 期抛错 = 整文件加载失败）；另用真实套件文件 `yaml-subset.test.mjs`（17 用例）/ `workspace-resolver.test.mjs`（7 用例）。
**运行时**：Node A = 本机 `v24.15.0`（`D:\Program Files (x86)\nodejs\node.exe`）；Node B = CI 同版本 **`v20.20.2`**（`.github/workflows/crctl-ci.yml:46-48` `node-version: 20`；取得方式 = 官方发行包 `node-v20.20.2-win-x64.zip` 本机解压），两者命令均**不经 shell**、同一份探针文件。

| # | 命令形态 | v24.15.0 实测 | v20.20.2 实测 | 对本设计的影响 |
|---|---|---|---|---|
| P1 | `node --test --test-reporter=tap <显式文件列表>`（正常文件） | 扁平：`# Subtest:` 全是**用例名**；全文唯一 plan = 全局 `1..3`；**无任何文件名块** | 逐字同形态 | **旧前提已证伪**（文件名块不存在）⇒ 归属不能从报告读 ⇒ 逐文件 spawn（I1） |
| P2 | 同上 + 整文件加载失败 | 文件级块只在此时出现：`# Subtest: d.test.mjs` + top-level `not ok 2 - d.test.mjs` | 同形态，但块名是**绝对路径**（`# Subtest: C:\…\d.test.mjs`） | 文件级块的**名字形态都随版本变** ⇒ 只作 `SUITE_FILE_LOAD_FAILURE` 的辅助判据，**不作归属来源** |
| P3 | `node --test --test-reporter=junit <文件列表>` | 每个 `<testcase>` 带 `file="<绝对路径>"`（通过/失败都有） | **无 `file` 属性**；仅加载失败那条的 `name` 是绝对路径 | 「junit 取归属」在 **CI 运行时不存在** ⇒ 已从 TDEC-1 备选里否决（P3 就是反例） |
| P4 | `node --test --test-reporter=tap`（目录发现，无位置参数） | 发现并执行 | 发现并执行 | 可用但**不可依赖**（见 P5/P6） |
| P5 | `node --test … .` / `… ./`（目录作位置参数） | **失败**：stderr `Could not find '.'` / `Could not find './'`，exit 1 | 成功发现并执行 | 目录参数形态跳版本不一致 ⇒ 包装器**自己**用 `readTestFileSet` 展开，不把发现交给 runner |
| P6 | `node --test … '**/*.test.mjs'`（glob 位置参数） | 成功（runner 展开 glob） | **失败**：`Could not find 'C:\…\**\*.test.mjs'`，exit 1 | 同上：glob 支持跳版本不一致 ⇒ 清单只来自登记面 + 磁盘集合 |
| P7 | `--test-isolation=none` | 接受（正常执行） | **拒绝**：`bad option: --test-isolation=none`，exit 9 | 设计**不使用**该开关（CI 运行时没有它） |
| P8 | `--test-concurrency=2` | 接受 | 接受 | 池大小常量与它同语义（文件级并发，TDEC-4） |
| P9 | **单文件** `node --test --test-reporter=tap <file>`（真实套件文件） | `yaml-subset` 顶层 plan `1..17`；`workspace-resolver` `1..7`（`# tests` 同值） | 逐字相同（17 / 7） | **本设计选用的机制**：真实文件上两运行时一致 ⇒ 每文件用例数可判（I2） |
| P10 | 两文件一次运行（P9 的两个文件） | 全局 plan `1..24`（= 17+7） | 全局 plan `1..24`（= 17+7） | 逐文件结果之和 ≡ 多文件结果 ⇒ 逐文件执行**不改变用例口径**（AC-01/AC-14 的计数基线可比） |

**关键原始输出（截取，逐字）**

```text
## P1 —— Node A（v24.15.0）：node --test --test-reporter=tap ./a.test.mjs ./b.test.mjs   [exit 0]
TAP version 13
## Subtest: alpha one
ok 1 - alpha one
## Subtest: alpha two
ok 2 - alpha two
## Subtest: beta one
ok 3 - beta one
1..3
## tests 3
## pass 3
## fail 0
   （注：# Subtest: 3 行全是用例名；以 .test.mjs 结尾的 # Subtest: = 0；唯一 plan = 全局 1..3）

## P2 —— 同一运行时，加一个 import 期抛错的 d.test.mjs（文件级块的唯一出现场景）
## Subtest: d.test.mjs
not ok 2 - d.test.mjs
  ---
  failureType: 'testCodeFailure'
  error: 'test failed'
  ...
1..3
## fail 2

## P2 —— Node B（v20.20.2）同一命令：块名变成绝对路径
## Subtest: C:\tmp\probe65\d.test.mjs
not ok 2 - C:\tmp\probe65\d.test.mjs

## P3 —— Node B（v20.20.2）：node --test --test-reporter=junit ./a.test.mjs ./b.test.mjs ./c.test.mjs ./d.test.mjs
<testcase name="alpha one" time="0.000965" classname="test"/>          ← 无 file 属性
<testcase name="beta one" time="0.000909" classname="test"/>
<testcase name="C:\tmp\probe65\d.test.mjs" time="0.044479" classname="test" failure="test failed">

## P3 —— Node A（v24.15.0）同一命令（对照）
<testcase name="alpha one" time="0.000515" classname="test" file="C:\tmp\probe65\a.test.mjs"/>

## P9 —— Node B（v20.20.2），真实套件文件：tail
1..17
## tests 17
## pass 17
## fail 0

## P10 —— Node B（v20.20.2），两个真实套件文件一次运行：tail
1..24
## tests 24
## pass 24
## fail 0
```

**保留的结论（有新证据支撑）**：单文件 TAP 的**顶层 plan 与顶层结果行数一致**这一形态，在本机 v24.15.0 与 CI 同版本 v20.20.2 上逐字一致（P9/P10），构成本设计唯一的外部耦合点；除此之外的一切格式/发现/isolation 假设（文件名块、junit `file`、目录参数、glob、`--test-isolation`）**已由探针证明随版本变化**，因此全部从承载前提上移除；解析不符即 `SUITE_REPORT_UNPARSEABLE` 硬失败（红），不存在静默通过。**未在本机验证的部分**：见 §6.4（CI 平台 ubuntu 侧形态、全量耗时与收敛性）。

**其余兼容性**：
- 双环境一致：命令与断言不依赖 shell 特性（`shell:false` spawn，文件清单由包装器从登记面展开，不经 shell/glob），Windows（本机 CR worktree，autocrlf 检出）与 CI（bash）同结论。
- Node 版本（修订）：只用 Node ≥ 18 标准库（本机 v24.15.0；CI 为 Node 20）；外部耦合点已收窄并带探针（P9）。
- 历史证据不改写：不动历史 CR 产物与归档；不改 `specs/`、`delivery/`。

---

### 8. Prompt 采纳影响

**判定：不适用（N/A）。** 本 CR 的 diff **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支（新增/变更子命令面），也**不触及** `skills/shared/controlled-shell/rules.json#protectedPaths.deny`；本 CR 不新增 crctl 子命令或 flag（FR-17/§3.3），因此不存在「crctl 新增了能力、某 skill 该采纳却还没采纳」的清单。

核查（实施期同款命令）：

```powershell
## 1) 本 CR 的 crctl.mjs 改点只在 emitOutboxEvent（非 dispatch 分支）
git diff --stat -- skills/shared/crctl/scripts/crctl.mjs
git diff -U0 -- skills/shared/crctl/scripts/crctl.mjs | Select-String '^\+' | Select-String 'emitOutboxEvent|outbox-contract'
## 2) rules.json 零 diff
git diff --stat -- skills/shared/controlled-shell/rules.json
## 3) 无新增子命令：dispatch 表未变
git diff -U0 -- skills/shared/crctl/scripts/crctl.mjs | Select-String 'case .(task|advance|approve|review-record|checkpoint|archive|merge|writeback-apply)'
```

---

### 9. 批准范围

#### `scope_in`（本 CR 必须交付）

- FR-1 / FR-2 / FR-3：断言去硬编码与归类清单（§4.1、§4.4、§6.6）。
- FR-4 / FR-5 / FR-6 / FR-7：BR-1…BR-4 四条断言按其事实源对齐转绿（`crctl.test.mjs:1337/4777/4989`、`checkpoint-tx.test.mjs:480`）。
- FR-8 / FR-9 / FR-10：BR-5 构造改对 + 新增「同名不同内容」用例 + 去重契约提为可检查声明（`lib/outbox-contract.mjs`、`crctl.mjs#emitOutboxEvent` 最小改点、`archive-tx.test.mjs`、`trace-outbox.test.mjs`）。
- FR-11 / FR-12：CI 全量步骤成为真门禁（`suite-gate.mjs` + `crctl-ci.yml:109-111`）与并发收敛决定 + 实测证据。
- FR-13：三类漂移负控注入的全量运行证据（`test-evidence/`）。
- FR-14：例外单一登记处 + owner + 到期 + 到期即红 + 不得自证绿（`gate-registry.json#exceptions`、`suite-gate.mjs`、`contract-scan.test.mjs` 静态断言）。
- FR-15 / FR-16 / FR-17：最小改写、零回归、契约面声明与四查。

#### `scope_out`（明确不做）

- 包 B：不改 `write-tech-design` / `review-tech-design` 的 SDD 评审合同（owner 已裁）。
- CR-2026-064 的恢复合同迁移本身（冻结在 `tech-design-review-pending`）；本 CR 不依赖也不改变 `recoverCommand` / `recover_command` 现状。
- 不改 5 条红的根因对象**本身**：pipeline 文本、状态机条目、`write-requirement-prd` 文本、alignment reader 合同、archive outbox 链路的业务语义（只对齐断言/构造）。
- 不改 CI 之外的交付/发布流程（push-progress / merge / archive / writeback 的算法与门禁语义）。
- 不含 multica 仓测试面；不新增测试框架或第三方依赖（含 YAML 解析依赖）。
- 不改写历史证据（历史 CR 产物、归档 traceability/delivery）。
- 不把 fixture 局部计数断言（§6.6 末段）纳入「必须推导」改造面——它们不是事实源快照。
- 不做平台 Prompt 部署（tools 侧文本变化在平台侧生效由 owner 另行执行）。

#### `zero_diff`（明确不得改动的调用点/签名）

- `crctl.mjs` 顶层 dispatch 与所有既有子命令的**签名、参数、错误码**零 diff（`emitOutboxEvent` 内部实现改点除外，且其返回语义不变）。
- `skills/shared/crctl/scripts/lib/yaml-subset.mjs`、`lib/durable-tx.mjs`、`lib/workspace-transactions.mjs` 零 diff。
- `skills/shared/controlled-shell/rules.json` 零 diff；`dir-graph.yaml` 零 diff；`pipeline-templates/*` 零 diff；所有 `SKILL.md` 零 diff。
- 状态机、错误码、事务语义、`reviewLoop` / archive / merge / checkpoint / writeback 业务算法零 diff。
- `approval.yml` / `cr.md` / `_backlog.yml` / `tasks/_index.yml` / `traceability.yml` / `review-annotations/**` 的写入路径零新增（断言只读）。
- 历史 CR 产物与 `specs/`、`delivery/` 零 diff。

#### `follow_up`（发现但留给后续 CR）

1. `tools/ARCHITECTURE.md` §5 不变量 5 的「28 条声明 / wildcard 展开 50 条」已滞后于 `dir-graph.yaml` 当前内容（31 / 53）；按该文档 §8 维护规则，属需独立触发的文档修订，不在本 CR 内改（本 CR 未改变状态机，登记目标值一律从 `dir-graph.yaml` 推导）。建议随下一次触及状态机口径的 CR 一并修正，或单开文档修订 CR。
2. 其余 pipeline 节点数硬编码断言（本轮评审 S-4，本机核对）未纳入本次「跨文件投影」改造：`crctl.test.mjs:4961`（读 `_index.yml#nodes` 后钉死 16）、`pipeline-structure.test.mjs:41`（`ids.length` 钉死 16；同文件 `:94-96` 已有同口径跨文件投影断言）、`pipeline-structure.test.mjs:183`（requirement-authoring 钉死 7）。三条当前均为绿；若后续 CR 触及 `_index.yml#nodes`，应在同一 CR 内一并改为投影断言（本 CR 只改 BR-1 触及处，避免扩大 diff）。
3. 例外登记面若在后续 CR 首次出现真实例外，需同步在 `test-report` 与回写产物中记录「例外 → owner → 到期」闭环；本 CR 交付态为空，未产生该流程的运行实例。
4. **门禁陈旧性（范围外观察，不阻塞本 CR，得留后续 CR）**：`crctl gate --for tech-design-reviewed` 只校 `review-annotations/sdd.yml` 的 `verdict=pass` + `blockers=[]` + `approval.yml#tech-design` 存在，**不校验 annotation 的 `subject-sha256` 是否等于当前 `sdd.md` 的哈希**。后果：「旧 pass annotation + 旧审批 + 已被修订的 SDD」也会报绿 —— 与本次「前提为假却一路绿到实现期」同源（同为「登记值与当前事实脱钩时不报警」）。本轮靠 pipeline 节点序（修订 → 重新评审 → 重新人工审批）挡住，不受影响；但该折扣落在 `crctl` 自身的门禁面，不在本 CR `scope_in`（本 CR 不新增 crctl 子命令/flag，FR-17；本次只把 per-file 归属这个具体断裂点修掉）。建议单开 CR，把「annotation 绑定的 `subject-sha256` 必须等于当前产物」收进门禁断言面。

## CR-R：结构化恢复合同原子迁移 — `recoverCommand`/`recover_command` 全量退役为结构化 `recovery`（v0.37 · CR-2026-064）

## CR-R：结构化恢复合同原子迁移 — 技术设计

> 输入：`change-requests/CR-2026-064/prd.md`（5 US / 17 FR / 14 AC，评审 PASS + 人工审批）。
> 本文只设计「把恢复动作从命令字符串改为结构化 `recovery`」的落点与算法；不改任何既有错误码语义、状态转换、事务边界与业务算法。
> 修订：`review-tech-design` attempt 1/3 判 BLOCK（TD-BL-1 扫描覆盖 / TD-BL-2 OpenWiki 生成闭环 / TD-BL-3 依赖事实与计数口径）后的定点回修；改动限于 §1.1、§4.3、§4.4、D-5、新增 D-7、§6.1–§6.4、§9、§11，方案主体未重写。
> 修订：`review-tech-design` attempt 2/3 判 BLOCK（TD-BL-1 未清：扫描面把「未列目录」默认为非活跃，漏掉 11 个活跃 MJS）后的定点回修；扫描面改为**整树派生 + 两项被断言排除**，改动限于 §1.1、§4.3、§4.4、D-5、§6.1、§6.3 AC-05/AC-06、SDD-CLOSE-05、§9、§11，合同字段、生产者改法、D-1…D-4/D-6/D-7 未重写。
> 修订（`review-tech-design` attempt 3/3 判 BLOCK 后的**新 cycle 定点回修**，`review-annotations/sdd.yml` 评审 commit `f4e6cfd`）：唯一残留点 TD-BL-1 —— 排除面把 `skills/shared/crctl/scripts/test/fixtures/**` 整目录排除，而该目录下三个 canonical digest 向量是活跃测试证据。排除面收窄为**扫描器自身 + `test/fixtures/traceability-191k.yml` 精确路径**两项，`fixtures/digest-vectors/**` 与今后新增夹具默认入面；扫描面 209 → **212**，代表性用例七条 → **八条**。改动限于 §4.4、D-5、§6.1、§6.3 AC-06、SDD-CLOSE-05、§9、§10、§11；合同字段、生产者改法、D-1…D-7 方案面未重写。
> 修订（`review-tech-design` cycle 2 attempt 3/3 判 BLOCK、合并 trunk 后的**新基线复评**：唯一 blocker = AC-07 的验收命令与「CI 同一命令」可达性依据在 `tools@81d31b8` 上已失效，CI 全量步骤已由 CR-2026-065 换为 `suite-gate.mjs --run`）：定点回修 §4.3、§4.4、§4.5、§6.3 AC-07、§9、§11 与本节修订记录；并记录事实变更——旧基线（`tools@dddd0ad6`）5 条红已由 CR-2026-065 修复，AC-07 回到「全绿」口径、**无需任何例外授权**。合同字段、生产者改法、D-1…D-7 方案面未重写。

### 1. 架构概览

#### 1.1 变更边界

| 仓 | 路径 | 变更性质 |
|---|---|---|
| `tools` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 生产者：9 类可恢复场景原位改为结构化 `recovery`；新增唯一构造器 `buildRecovery` |
| `tools` | `skills/shared/crctl/scripts/crctl.mjs` | 投影层：删除 `recoverCommand`/`recover_command` 双投影，2 处错误恢复改为结构化，注册结果单投影 |
| `tools` | `skills/shared/crctl/scripts/test/*.test.mjs` | 7 个既有测试文件由字符串包含断言改为结构与 argv 断言；`contract-scan.test.mjs` 扩展退役名单与扫描面 |
| `tools` | `skills/shared/crctl/SKILL.md`、`skills/cr/cr-archive/SKILL.md`、`skills/sync/push-progress/SKILL.md`、`skills/writeback/merge-feature-branch/SKILL.md` | 消费方提示词：改读 `recovery.executable/args/cwd/requiresTTY/promptFor` |
| `tools` | `README.md`（手工原位迁移）、`openwiki/operations/crctl-transactions.md`（**生成物**，不手工编辑） | README 原位改读结构化合同；OpenWiki 页面由既有生成步骤从迁移后的权威源码重新生成并核对（D-7），旧合同描述随之消失，不新增第二套描述 |
| `multica` | `cr-prompts-revised/delivery-agent.md` | 交付 Agent 提示词的 owner 可复制版本改读结构化结果（本 CR 不更新平台 DB） |
| 知识库 | `change-requests/CR-2026-064/sdd.md` + 后续 PLAN/TASK | 本 CR 产物 |

**不在本 CR 变更范围**：`tools/ARCHITECTURE.md`（已存在，只读引用；本 CR 不触发其 §8 修订条件）、`dir-graph.yaml`、`skills/shared/crctl/gates.json`、`skills/shared/controlled-shell/rules.json`、`pipeline-templates/**`（无旧字段引用，仅纳入退役扫描面）、`tools/agents/*.md`（无旧字段引用）、Multica 服务端与 importer。

#### 1.2 依赖方向（分层不变）

```
消费方：Skill 提示词 / Agent 提示词 / 平台 Prompt
        │  读取结构化 recovery（prompt 合同，非代码依赖；见 §3.5）
        ▼
crctl CLI：skills/shared/crctl/scripts/crctl.mjs      ← 唯一命令入口与投影层
        │  import（只朝下）
        ▼
lib/workspace-transactions.mjs   ← 生产者 + 唯一构造器 buildRecovery
        │
        ▼
lib/durable-tx.mjs（TxError/journal）、lib/yaml-subset.mjs
```

- `buildRecovery` 落在 **lib**（`workspace-transactions.mjs`）并由 CLI 向下 import；lib 不反向依赖 CLI（`tools/ARCHITECTURE.md` §4 规则、§5 不变量 2 保持）。
- 不新增命令、不新增状态/转换、不新增 Pipeline 节点、不新增账本写入通道；`.crctl/transactions/**` journal schema 不变（§2.2）。

#### 1.3 关键流程

1. **生产者构造**：任一可恢复场景（失败或可恢复中间态）由 `buildRecovery(args, { cwd, requiresTTY, promptFor })` 一次性构造出唯一 `recovery` 对象，直接作为返回值字段或 `TxError.extra.recovery`。
2. **CLI 投影**：成功结果把它放在**顶层** `recovery`；错误路径经 `fail(code, message, extra)` 落在 `error.recovery`；不再存在第二个同义字段。
3. **消费方判定**：消费方（Agent / Skill）按 §3.5 的固定 5 步顺序校验，全部满足才以非 shell 的 argv 方式执行；首个不满足即停止并报告合同错误，零执行副作用。

### 2. 数据模型

#### 2.1 核心实体：`recovery`

| 字段 | 类型 | 必填 | 规则 | 取值来源 |
|---|---|---|---|---|
| `executable` | string | ✅ | 非空；不含空格分隔参数、管道 `\|`、重定向 `>` `<`、分隔符 `;`、连接符 `&&`、命令替换 `$()`、反引号或任何 shell 展开 | 本 CR 全部生产者恒为字面量 `node`（决策 D-1） |
| `args` | string[] | ✅ | 每元素是**一个完整 argv**；不把多参数拼成单元素；顺序与目标 CLI 参数顺序一致；含空格路径不加引号即可传递 | `args[0]` = `crctl.mjs` 绝对路径（FR-3 node 规则）；其后为原命令 token |
| `cwd` | string（绝对路径） | 可选（本 CR 全量提供） | 仅当恢复动作必须位于特定 workspace 时返回；不得依赖调用方猜测 | 与该恢复动作的 `--workspace` 值同源（`gate`/`reset` 无 `--workspace` flag，取执行该命令时的工作区） |
| `requiresTTY` | boolean | ✅ | 是否必须在可信交互终端执行 | `review-loop reset` 为 `true`（CLI 自身非 TTY 一律 `NOT_TTY` 拒绝，证据见 §11-2）；其余 `false` |
| `promptFor` | string[] | ✅ | 执行时需重新获取的逻辑值名（按序）；这些值**不得**预先出现在 `args[]` 或任何 shell string 中 | 见 §3.4 三处 |

键序固定为 `executable` → `args` → `cwd`（存在时）→ `requiresTTY` → `promptFor`（构造器保序，FR-17 指纹与断言稳定性）。

#### 2.2 存储方案：不落盘

`recovery` 是**响应期数据**，仅存在于命令响应与 `TxError.extra` 两类载体中：

- **不入 journal**：`.crctl/transactions/{op}/{key}/{txId}/journal.json` 的 payload 字段集零变更（现有 producer 站点没有任何把恢复数据写入 journal 的代码路径，见 §11-3）；
- **不入账本**：`cr.md` / `_backlog.yml` / `_history.yml` / `_index.yml` / `approval.yml` / `review-annotations/*` / `traceability.yml` 零字段变更；
- **不入 Git 产物**：`specs/`、`delivery/`、`merge-commits.yml`、`test-report.md` 等不受影响。

因此本 CR **无数据迁移、无 schema 兼容窗口、无部分状态语义**（PRD 的 schema/写路径鉴权条件未触发）。

#### 2.3 命名与别名

| 名称 | 状态 | 处置 |
|---|---|---|
| `recovery` | 唯一活跃名（PRD canonical term） | 全部生产者/投影/消费方统一使用 |
| `recoverCommand` | 退役 | 本 CR 内删除，禁止 alias/shim/fallback |
| `recover_command` | 退役 | 同上（仅注册结果曾双投影） |

命名冲突记录（Step 2.5）：模块内既有 `recoverWriteSet` / `recoverLedgerTransaction` / `recoverLedgerCommand` 是**事务层内部恢复原语**，与响应字段 `recovery` 不同层、不同名空间，本 CR 不改名、不合并（§10）。
保留的其它 snake_case 镜像（`cr_id` / `tx_id` / `operational_workspace` …）**不在本 CR 变更范围**（`zero_diff`，§9）。

#### 2.4 幂等指纹字段集（FR-17）

指纹参与字段固定为：`executable` + `args[]`（有序）+ `cwd`（省略时不参与）+ `requiresTTY` + `promptFor[]`（有序）。构造器全部入参来自确定性事实（CR-ID、绝对路径、传入的业务参数、消息文本），**不含**时间戳、随机数、进程 id、`process.execPath`、环境变量或平台相关可变成分（决策 D-1）。重复求值逐元素相等；重复消费不改变其值，也不改变原事务的幂等结论。

### 3. 接口契约

#### 3.1 类型

```ts
interface Recovery {
  executable: string;    // 本 CR 恒为 'node'
  args: string[];        // args[0] = <toolsRoot>/skills/shared/crctl/scripts/crctl.mjs 绝对路径
  cwd?: string;          // 绝对路径；本 CR 全部生产者均提供
  requiresTTY: boolean;
  promptFor: string[];   // 逻辑值名，按序；对应 argv 元素不出现在 args
}
```

#### 3.2 唯一构造器

```js
// skills/shared/crctl/scripts/lib/workspace-transactions.mjs
const CRCTL_SCRIPT_PATH = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'crctl.mjs');

export function buildRecovery(args, { cwd, requiresTTY = false, promptFor = [] } = {}) {
  // 内部不变量守卫：仅由程序员错误触发，任何合法输入不可达（不改变既有 CLI 合同）
  if (!Array.isArray(args) || args.some((a) => typeof a !== 'string')) throw new TxError('RECOVERY_CONTRACT_INVALID', 'recovery.args 必须是字符串数组');
  if (cwd != null && !path.isAbsolute(cwd)) throw new TxError('RECOVERY_CONTRACT_INVALID', `recovery.cwd 必须是绝对路径: ${cwd}`);
  if (typeof requiresTTY !== 'boolean') throw new TxError('RECOVERY_CONTRACT_INVALID', 'recovery.requiresTTY 必须是 boolean');
  if (!Array.isArray(promptFor) || promptFor.some((v) => typeof v !== 'string')) throw new TxError('RECOVERY_CONTRACT_INVALID', 'recovery.promptFor 必须是字符串数组');
  return {
    executable: 'node',
    args: [CRCTL_SCRIPT_PATH, ...args],
    ...(cwd == null ? {} : { cwd }),
    requiresTTY,
    promptFor,
  };
}
```

契约保证（AC-01/AC-10/AC-11 的生产者侧落点）：

1. `executable` 由构造器恒定，FR-3 的安全约束按构造成立；
2. node 入口的脚本路径恒为 `args[0]`（FR-3 后半、AC-10）；
3. `args` 恒为字符串数组、`cwd` 恒为绝对路径；
4. `requiresTTY` / `promptFor` 由调用点显式声明，`false`/`[]` 也必须显式传入（形状统一，便于结构断言）；
5. 键序固定（§2.1），供 FR-17 指纹与测试断言使用。

`RECOVERY_CONTRACT_INVALID` 是**内部不变量守卫**，不属于消费者可见的四类错误闭包（§3.5），只在未来生产者改错时以 `INTERNAL_ERROR` 链路暴露，不改变任何既有错误码/退出码。

#### 3.3 命令面投影

| 命令 / 场景 | 现载体 | 新载体 | 站点 |
|---|---|---|---|
| `register` | 成功结果 `recoverCommand` **且** `recover_command`（双投影） | 成功结果 `recovery`（单投影） | `crctl.mjs#buildRegisterResult` + `cmdRegister` 输出对象 |
| `workspace sync` | 成功结果 `recoverCommand` | 成功结果 `recovery` | `syncWorkspaceToTrunk` 三条 return |
| `merge` | 成功结果 / `phase=release-drift` 结果 `recoverCommand` | 同名位置 → `recovery` | `mergeCr` 三条 return |
| `merge` publication lag（`MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED`） | `error.recoverCommand`（指向 `checkpoint`） | `error.recovery` | `mergeCr` 两个 TxError 的 `extra` |
| `checkpoint` | 成功结果 + 错误 `error.recoverCommand` | 同名位置 → `recovery` | `checkpointCr` 三条 return + catch 包装 |
| `writeback-apply` | 成功结果 `recoverCommand`（主路径 + traceability replay 两条构造） | 同名位置 → `recovery` | `applyWritebackAtomic` replay 两条 return + 主 literal + 主 return |
| `archive` | 成功/待清理/幂等固定返回 `recoverCommand` | 固定返回 `recovery` | `archiveCr` literal + `result()` 闭包 |
| `test` | 成功结果 `recoverCommand`（含 `{TOOLS_ROOT}` / `<plan>` / `<worktree>` 占位符的模板串） | 成功结果 `recovery`（结构化，`plan` 走 `promptFor`） | `buildTestResponse` + `testCr` 5 个调用点 |
| `review-loop reset`（提交失败） | `error.recoverCommand` | `error.recovery` | `crctl.mjs#cmdReviewLoopReset` |
| `gate --mode pre-review` 错配 | `error.recoverCommand` | `error.recovery` | `crctl.mjs#cmdGate` |

成功结果的其它字段与错误码、`exit code`、`txId`、`rollback`/`files` 语义一律不变（FR-13）。

#### 3.4 `promptFor` 解析约定

`promptFor` 的元素是**逻辑值名**；消费方须按该值名对应到目标 CLI 的既有入口取新值，且**不得**从旧错误消息、评论或日志中复用旧值：

| 值名 | 场景 | 目标 CLI 入口 | 是否从 `args` 省略 | 若被忽略（不取值直接执行） |
|---|---|---|---|---|
| `reason` | `review-loop reset` 提交失败 | `--reason <text>`（可信 TTY 中由人重新输入） | 是 | `BAD_ARGS`（`review-loop reset 需要 --reason …`），零写入 |
| `plan` | `test` 恢复 | `--plan <temp-json>` | 是 | `BAD_ARGS`（`test 需要 --plan …`），零写入 |
| `CR-ID` | `gate` 错配且位置参数非规范 `CR-YYYY-NNN` | 位置参数 `<cr_id>` | 是 | `BAD_ARGS`（`workspace 需要 CR-ID`），零写入 |

该约定同时给出**安全失败**性质：忽略 `promptFor` 的消费方不会静默执行一条语义不完整的命令，而是撞上目标 CLI 既有的入参校验（零副作用）。

#### 3.5 消费方判定顺序与错误闭包（FR-17）

固定顺序，**首个**不满足项即唯一结论（禁止「A 或 B」式并列）：

| # | 检查 | 不满足时 |
|---|---|---|
| 1 | `executable` 存在、非空 string、满足 FR-3 安全约束 | 停止执行 + 报告合同错误 |
| 2 | `args` 是数组且每元素为 string | 同上 |
| 3 | `cwd` 若存在则为绝对路径 | 同上 |
| 4 | `requiresTTY=true` ⇒ 当前环境具备可信 TTY | 停止执行 + 报告所需人类动作（不得在非 TTY 环境执行） |
| 5 | `promptFor` 非空 ⇒ 存在允许的人类/调用方输入入口（取值后方可执行） | 停止执行 + 报告所需人类动作 |

四类错误（合同字段缺失或类型错误 / `executable` 违反安全约束 / TTY 要求不满足 / `promptFor` 无输入入口）统一闭合为：**停止执行 + 报告合同错误 + 零执行副作用 + 明确的人类/调用方动作**；且：

- 不得自动回退旧字段 —— 旧字段已在本 CR 删除且无 alias/shim，**结构上不可回退**（FR-10）；
- 不得猜测恢复命令、不得降级为字符串执行；
- 人类界面若需显示命令，只能从 `recovery` 渲染，且显示结果不得反向作为执行输入。

消费方是提示词（Skill / Agent），不是本仓代码：本 CR 无任何代码路径执行 `recovery`（§10 边界说明、AC-11 映射）。

### 4. 关键算法与流程

#### 4.1 生产者迁移算法（FR-5）

对每个既有 `recoverCommand` 模板串，按固定六步原位改写：

1. **拆 token**：把模板串按「一个 token 一个元素」拆开，`--flag` 与它的值各占一个元素；`JSON.stringify(...)` 包裹的插值改为裸值元素（引号不再需要，也不得残留）；
2. **保顺序**：元素顺序与目标 CLI 参数顺序逐字一致（含 `--workspace` 位置）；
3. **保条件**：原串中「有才拼」的可选参数在新代码中保持同一条件（三元展开成 `...(cond ? [a, b] : [])`），不引入新条件也不丢条件；
4. **定 `cwd`**：原串内插的 workspace 路径同时作为 `cwd`（绝对路径）；`gate`/`reset` 无 workspace 参数，取执行时工作区；
5. **提 `promptFor`**：原本以占位符/旧值内插、且执行时必须重新获取的值（`reason`、`plan`、非规范 `CR-ID`）**从 `args` 移除**并列入 `promptFor`；该值不得出现在任何 shell string；
6. **删除旧字段**：在**同一位置**改为 `recovery: buildRecovery(...)` 或 `extra.recovery`；不并排双写、不留 fallback。错误消息文本中引用旧字段名的措辞（如「先执行 recoverCommand 再重跑 merge」）同步改为「先执行 `recovery` 指向的 checkpoint 再重跑 merge」。

逐个生产者的 `args` 取值（`args[0]` 由构造器注入）：

| # | 场景 | `args`（`args[0]` 之后） | `cwd` | `requiresTTY` | `promptFor` |
|---|---|---|---|---|---|
| 1 | `registerCr` | `register --registration-key <k> --title <t> --owner-requirement <r> --owner-development <d> --owner-test <e> (--summary <s>)? (--source <s>)? (--origin <o>)? (--target-version <v>)? --target-spec-id <id> --workspace <ws>` | `<ws>` = `input.workspace \|\| ctx.installRoot` | `false` | `[]` |
| 2 | `workspace sync` | `workspace sync <cr> --workspace <installRoot>` | `<installRoot>` | `false` | `[]` |
| 3 | `mergeCr`（成功 / `release-drift`） | `merge <cr> --workspace <ws>` | `<ws>` = `input.workspace \|\| ctx.installRoot` | `false` | `[]` |
| 4 | merge publication lag | `checkpoint <cr> --workspace <installRoot>` | `<installRoot>` | `false` | `[]` |
| 5 | `checkpointCr` | `checkpoint <cr> (--message <m>)? --workspace <ws>` | `<ws>` = `workspace \|\| ctx.installRoot` | `false` | `[]` |
| 6 | writeback traceability replay | `writeback-apply <cr> --stage traceability --spec-id <id> --target-version <v> (--milestone-file <f>)? --workspace <ws>` | `<ws>` | `false` | `[]` |
| 7 | writeback apply（主路径） | `writeback-apply <cr> --stage <stage> --spec-id <id> --target-version <v> (--milestone-name <n>)? (--brief <b>)? (--milestone-file <f>)? --workspace <ws>` | `<ws>` | `false` | `[]` |
| 8 | `archiveCr` | `archive <cr> (--spec-id <id>)? --workspace <ws>` | `<ws>` | `false` | `[]` |
| 9 | `testCr` | `test <cr> --workspace <worktree>`（`--plan` 走 `promptFor`） | `<worktree>`（`testCr` 的 `workspace` 入参，即 authority workspace） | `false` | `['plan']` |
| 10 | `gate --mode pre-review` 错配 | `workspace inspect <cr>`（非规范 CR-ID 时省略该元素） | 执行 `gate` 的工作区 | `false` | `[]` 或 `['CR-ID']` |
| 11 | `review-loop reset` 提交失败 | `review-loop reset <cr> --loop <loopRef>`（`--reason` 走 `promptFor`） | 执行 `reset` 的工作区 | `true` | `['reason']`（CR-ID 非规范时并含 `'CR-ID'`） |

站点 10/11 共用一个极小判定：规范 CR-ID（`^CR-\d{4}-\d{3,}$`）⇒ 作为独立 argv 元素；否则省略该元素并声明 `promptFor: ['CR-ID']`。既有 `crIdForRecover`（返回 `<CR-ID>` 占位符串）随之删除——占位符不再进入 `args`（决策 D-4）。

#### 4.2 CLI 投影迁移算法（FR-6）

1. `buildRegisterResult` 只保留 `recovery`；`cmdRegister` 输出对象从 `recoverCommand: r.recoverCommand, recover_command: r.recoverCommand` 改为 `recovery: r.recovery`（删除双投影，其它 snake_case 镜像不动）；
2. 各 `ok({ op: '<x>', ...result })` 站点无需改动（展开后字段名自动由 producer 决定），但**必须**核对 producer 侧已改名（`archive`/`checkpoint`/`merge`/`workspace-sync`/`writeback-apply`/`test`）；
3. `gate` 与 `review-loop reset` 的 `fail(..., { recovery })` 用 §4.1 站点 10/11 的构造；
4. CLI 层不得重新拼接任何 shell string：`recovery` 一经构造即透传。

#### 4.3 逐文件改法清单

> 行号为 `tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289` 上的参考位置；实施定位一律以实时 `rg "recoverCommand|recover_command"` 为准（PRD 明文），**禁止按行号盲改**。

| 文件 | 站点 | 改法 |
|---|---|---|
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | `registerCr`（`~L777`、`~L901`） | 引入 `buildRecovery`；literal → 结构化；return 字段改名 |
| 同上 | `syncWorkspaceToTrunk`（`~L1074`、`~L1118`、`~L1128`、`~L1158`） | 一个 `recovery` const 供三条 return 复用 |
| 同上 | `mergeCr`（`~L1512`、`~L1551`、`~L1555` 注释、`~L1557`、`~L1570`、`~L1573`、`~L1760`） | 两条 recovery（merge / checkpoint）；两个消息文本去旧字段名；`extra.recovery` |
| 同上 | `checkpointCr`（`~L1943`、`~L1990`、`~L2226`、`~L2231`） | literal → 结构化；catch 包装 `extra.recovery` |
| 同上 | `applyWritebackAtomic`（`~L2812`、`~L2819`、`~L2880`、`~L3127`） | 三条构造（replay×2 + 主）+ 三条承载 |
| 同上 | `archiveCr`（`~L3458`、`~L3504`） | literal → 结构化；`result()` 闭包字段改名 |
| 同上 | `buildTestResponse`（`~L4178`、`~L4184`）+ `testCr` 5 个调用点（`~L4246`、`~L4259`、`~L4265`、`~L4331` 等） | 入参增加 `workspace`；结构化 recovery + `promptFor: ['plan']` |
| `skills/shared/crctl/scripts/crctl.mjs` | `crIdForRecover`（`~L963`）+ `cmdGate`（`~L974`）+ `cmdReviewLoopReset`（`~L1906`、`~L1912` 注释）+ `buildRegisterResult`（`~L2753`）+ `cmdRegister` 输出（`~L3304`） | 占位符 helper → 规范 CR-ID 判定；两处 fail payload 结构化；单投影 |
| `skills/shared/crctl/SKILL.md` | `merge` 行、`archive` 行 | 「携 checkpoint recoverCommand」→「携 `recovery`（指向 checkpoint）」；固定返回字段列表改名 |
| `skills/cr/cr-archive/SKILL.md` | 步骤 2 说明、结果分类表 3 行、输出模板「恢复」行、错误处置表 | 改为「按 `recovery`（argv）续跑」；唯一续跑入口表述不变 |
| `skills/sync/push-progress/SKILL.md` | Step 2 错误分流行、错误表「其它事务错误」行 | 改为按 `recovery` 重跑同一命令 |
| `skills/writeback/merge-feature-branch/SKILL.md` | publication lag 行 | 「按 extra.recoverCommand 先 checkpoint」→「按 `error.recovery` 先 checkpoint」 |
| `README.md` | §7「中途失败」条 | 改为按输出的 `recovery`（结构化 argv）重跑同一命令 |
| `openwiki/operations/crctl-transactions.md` | frontmatter `invariants[1]`、正文「Durable Transaction Envelope → Recovery」条、「Change-Safety Guidance」第 3 条 | **生成物，不手工编辑**：源码迁移完成后由既有生成步骤（`openwiki code --update`，与 `openwiki-update.yml` 同源）重新生成该页，再核对三处旧合同断言归零（D-7） |
| `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | `TASK-01 RED-1` 标题、`L259`、`L317` | 结构断言（`executable`/`args`/`requiresTTY`/`promptFor`） |
| `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 测试标题、`L224` | 同上 |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 成功结果字段集用例、reset 双向量用例、rollback 用例、gate 双向量用例 | 同上；补 6 类 reason 向量与 `promptFor` 断言 |
| `skills/shared/crctl/scripts/test/merge-tx.test.mjs` | 测试标题、`L286`、`L301` | 断言 `recovery.args` 指向 `checkpoint` 且 `cwd` 为 installRoot |
| `skills/shared/crctl/scripts/test/register-tx.test.mjs` | `L143`、`L164`、`L637` 标题、`L650`（`recover_command`） | 同上；双投影用例改为单投影断言 |
| `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs` | `L269` | 同上 |
| `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | `L818` 标题、`L831` | 断言 `--target-version` 为独立元素且值正确 |
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | `FORBIDDEN` / `RETIRED` / `ACTIVE_PATHS`（既有）+ 新增 `RETIRED_RECOVERY`、整树扫描面与排除断言 | 见 §4.4（CR-2026-041 既有断言保持不动） |
| `multica/cr-prompts-revised/delivery-agent.md` | `L27`、`L44` | 「明确 `recoverCommand`」→「明确的结构化 `recovery`（argv）」；失败汇报项改名 |

#### 4.4 契约扫描算法（FR-11）

复用**既有**静态合同扫描机制（`contract-scan.test.mjs`，CR-2026-041 FR-06/07 建立），做三处扩展：退役名单、**扫描面**、判定与正反用例。

**1. 退役名单：按名分范围**

| 名单 | 名称 | 扫描范围 |
|---|---|---|
| `RETIRED_RECOVERY`（本 CR 新增） | `recoverCommand`、`recover_command` | 扫描面（§4.4-2） |
| `RETIRED`（CR-2026-041 既有；代码实际常量名，SDD 前几版按语义写作 `RETIRED_LEGACY`，本轮统一为实际名，见 §11-5） | `change-impact-analysis`、`feedback-writeback`、`feedback-writeback-done` | 保持既有显式 `ACTIVE_PATHS` 与既有断言，**本 CR 不改其名单与范围** |

分名分范围的事实依据（已在资源 HEAD 上核实，记录见 §11-5）：三个既有退役名在活跃面内**合法存在** —— `skills/shared/crctl/scripts/lint-prompts.mjs`（linter 的禁止名单）、`crctl.test.mjs` / `lint-prompts.test.mjs`（禁止名单的用例样本）、`CUSTOM.md`（台账引述）。把 `RETIRED` 并入整树扫描面会让 CR-2026-041 的断言立刻失败，而迁移这些名单不在本 CR 范围（§9 `zero_diff`）；PRD FR-11 要求加入退役清单的只有两个恢复字段名，故按名分范围。**整树扫描面只适用于两个恢复字段名**：它们在本 HEAD 的 `tools` 仓内除迁移对象与两项排除外零命中（下表的 216 文件扫描面成立），而三个既有退役名在 `docs/` 下的历史报告与历史夹具里合法存在（`rg -l` 本 HEAD 共 8 个文件，§11-5），套用整树扫描会立刻误报。

**2. 扫描面：整树派生 + 两项被断言的排除，不声明「哪些目录/扩展名算活跃」**

| 项 | 规则（唯一事实源） |
|---|---|
| 枚举根 | `tools` 仓库工作树根（`ROOT`）；`readdirSync(dir, { withFileTypes: true, recursive: true })` 递归枚举**全部文件**，只跳过两个被冻结的枚举边界 `.git` 与 `node_modules`（前者是版本库元数据、后者是 `.gitignore` 忽略的依赖目录，均非仓库跟踪内容；`SKIP_DIRS = ['.git', 'node_modules']` 由断言冻结，见 §4.4-3。按**路径段**判定，不区分文件/目录——`tools` 工作树里 `.git` 是文件，同样排除，故合并后基线的枚举数 218 与实现共用同一规则） |
| 扫描面 | 枚举结果 − 下表两项排除；两项排除都是**精确路径**（无目录/扩展名通配）；**不按目录、不按扩展名、不按文件名**推断活跃性 |
| 派生规模（**合并后基线** `tools@81d31b8` 重跑，与实现共用同一枚举；报告值，不冻结为等式） | 枚举 **218** 文件 − 扫描器自身 **1** − 历史 traceability 精确路径 **1** = **扫描面 216 文件**（`dddd0ad6` 基线对应 214 − 1 − 1 = 212） |
| 分类覆盖（同一扫描面内的核对，不缩小面） | active Skill **56**（`skills/_index.yml`）、active Agent **9**（`agents/_index.yml`）、Pipeline **8**（`pipeline-templates/_index.yml` 的 active `path` 去 `tools/` 前缀 ∩ `readdirSync('pipeline-templates')` 的 `*.pipeline.json`，集合必须相等）；`skills/**` + `pipeline-templates/**` 递归 `.mjs` 共 **43**，按路径是否含 `test/` 段二分 → 活跃源码 **17** / 活跃测试 **26**（进入扫描面 **25**，扣除扫描器自身） |

**为什么是整树而不是「活跃目录白名单」**：attempt 2 把活跃源码限定为 `skills/shared/crctl/scripts/**.mjs`、活跃测试限定为该目录 `scripts/test/**`，于是 `tools@dddd0ad6` 上另有 **11 个活跃 MJS 落在面外**——`pipeline-templates/emit-registry.mjs`、`skills/requirement/requirement-register/scripts/promotion-bind.mjs`（+ 其 `scripts/test/promotion-bind.test.mjs`）、`skills/shared/crctl/adapters/{claude-code,cursor}/hooks/*.mjs`（3 个）、`skills/writeback/scripts/{lib,writeback-prd-sdd,writeback-tasks,writeback-traceability}.mjs`（4 个）+ `skills/writeback/scripts/test/writeback.test.mjs`。这 11 个文件在本 HEAD 上对两个退役名零命中（已核实），**不是迁移对象**；纳入面内是防回流。同类盲区还有按 `.mjs` 白名单必然漏掉的 `skills/shared/engineering-docs/scripts/src/**`（16 个 `.ts` 活跃源码）。因此活跃性不再由「是否被列举」定义，而由「是否被显式排除」定义——未被排除即在面内。

**硬失败（不静默降级）**：索引解析出 0 条 active、目录枚举为空、active 索引条目在磁盘上不存在或落在排除项内、Pipeline 索引与目录枚举集合不相等——任一发生即硬失败（`check-skill-matrix.mjs` 已有「空结构守卫」先例，CR-2026-012 教训）。索引与文件读取一律先 `replaceAll('\r\n', '\n')` 再 `split(/\r?\n/)`（仓库行尾纪律）；扫描结果按路径排序输出，保证失败信息可复现。

**3. 可审计排除：恰两项，且被断言固定**

| 排除项 | 命中文件数（本 HEAD） | 理由 | 固定方式 |
|---|---|---|---|
| `skills/shared/crctl/scripts/test/contract-scan.test.mjs` | 1 | 扫描器自身的退役名单 —— 加入两个字段名后该文件必然含被扫字符串 | 断言其仍含退役名单文本、且不在被扫描集合内 |
| `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`（**精确路径，不用 `fixtures/**` 目录通配**） | 1 | 历史 traceability 证据，合法保留旧字段名 | 断言该精确路径含旧字段名、且只有它不在扫描面内 |

**为什么排除的夹具是精确路径而不是 `fixtures/**` 目录通配**（`review-tech-design` attempt 3 的 TD-BL-1 残留点，`sdd.yml` commit `f4e6cfd`）：同一目录下的 `digest-vectors/{expected.json,review-annotations-code.yml,test-report.md}` 不是历史证据，而是**活跃测试向量** —— `crctl.test.mjs`（`~L548-556`）直接读取它们做 canonical digest 一致性断言，`crctl.mjs`（`~L87`）把该目录声明为 Go 侧等价实现的固定共享向量（§11-2、§11-6）。它们不属于 PRD FR-11 允许排除的任何一类（历史 CR / 历史 traceability / 归档 delivery 证据 / changelog-migration 文档 / 扫描器自身名单）。目录级通配会把这三个活跃向量以及今后新增的任何活跃 fixture 一并排除，留下可扩张盲区；收窄为精确路径后，`fixtures/` 目录下除 `traceability-191k.yml` 外的全部文件默认在扫描面内（本 HEAD 共 3 个，对两个退役名零命中，见 §4.4-4 第 8 条）。

除上表两项外，扫描面不排除任何路径、目录或扩展名：`tools` 仓在本 HEAD 上没有含旧字段名的 changelog/migration 文档（PRD 允许的这几类排除在 `tools` 仓内只落为上述两项）；历史 CR 产物、历史 traceability 与归档 delivery 证据位于 KB 仓，不在 `tools` 整树枚举范围。

**排除面与枚举边界均被冻结**：`assert.deepEqual(EXCLUDED, [<扫描器自身>, 'skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml'])` 与 `assert.deepEqual(SKIP_DIRS, ['.git', 'node_modules'])`——两项排除都是精确路径、无任何模式匹配，因此**新增 fixture 文件不会被既有的某条排除顺手吞掉，默认入面**；反过来，任何新增排除或跳过目录都必须改测试并被评审看见，不存在「默默少扫一块」。

**4. 判定与正反用例**

- 纯谓词 `retiredHits(text, names)`（先 `\r\n → \n` 规范化，再大小写敏感的 `includes`）；`scanScope(files, names)` 返回命中文件列表。
- **零命中断言**：`scanScope(扫描面, RETIRED_RECOVERY)` 为空。
- **命中即失败的八条代表性用例**（每个派生根一条；取真实路径的真实文本，在内存中追加一行含 `recoverCommand` 的合成行，断言 `scanScope` 对同一路径判为命中）——第 2–6 行即 attempt 2 判 BLOCK 时落在面外的四个根（crctl adapter hook、requirement-register 生产/测试、writeback 生产/测试、`pipeline-templates/**`），第 7 行覆盖提示词面，第 8 行覆盖**本轮判 BLOCK 时被 `fixtures/**` 目录通配排除掉的活跃测试向量根**；既有迁移对象（`workspace-transactions.mjs`、`crctl.mjs`、7 个测试、4 份 SKILL.md）也在同一面内。证明范围不是恒真空断言，任一未列目录、未列扩展名的活跃文件回流旧名即失败：

| # | 派生根 | 代表性路径 |
|---|---|---|
| 1 | crctl 源码（含 `lib/`） | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` |
| 2 | crctl adapter hook | `skills/shared/crctl/adapters/claude-code/hooks/pretooluse-guard.mjs` |
| 3 | requirement-register 生产 | `skills/requirement/requirement-register/scripts/promotion-bind.mjs` |
| 4 | requirement-register 测试 | `skills/requirement/requirement-register/scripts/test/promotion-bind.test.mjs` |
| 5 | writeback 生产 + 测试 | `skills/writeback/scripts/writeback-prd-sdd.mjs`、`skills/writeback/scripts/test/writeback.test.mjs` |
| 6 | `pipeline-templates/**` | `pipeline-templates/emit-registry.mjs` |
| 7 | 活跃提示词（active Skill / active Agent） | `skills/cr/cr-archive/SKILL.md`、`agents/delivery-agent.md` |
| 8 | 活跃测试向量（`fixtures/` 内非历史文件） | `skills/shared/crctl/scripts/test/fixtures/digest-vectors/expected.json`、`skills/shared/crctl/scripts/test/fixtures/digest-vectors/review-annotations-code.yml`、`skills/shared/crctl/scripts/test/fixtures/digest-vectors/test-report.md` |

- **允许排除不误报**：唯一被排除的夹具文件（`traceability-191k.yml`）仍合法含旧名，断言 `retiredHits(排除项文本) === true` 且 `scanScope(扫描面)` 不含它；同目录其余三个文件断言相反（在面内且零命中）。两者并置才证明排除是刻意、精确且必要的，而不是「整目录一关了事」。
- **排除不隐形**：断言排除集合恰为上表两项精确路径 —— 新增排除必须改测试并被评审看见。
- **规模口径：报告值 + 结构性断言，不用脆弱等式**：不写 `scanSurface.length === 216`（日后任何新增文件都会造成假失败，反过来诱发「改数字了事」）；规模（216 / 43 / 17 / 26 / 56 / 9 / 8）写进断言消息作覆盖度报告，真实保证由四条结构性断言给出——(1) 三个 active 索引的全部条目存在于磁盘且在扫描面内、Pipeline 索引与目录枚举集合相等（索引条目落入排除项或缺失即硬失败）；(2) 八条代表性路径全部在扫描面内；(3) `EXCLUDED` 与 `SKIP_DIRS` 被 `deepEqual` 冻结（§4.4-3）；(4) 排除项恰为两条精确路径且不含任何通配，`fixtures/` 目录下未被排除的文件（本 HEAD 3 个 digest 向量）全部在扫描面内——**新增 fixture 默认入面，无需改测试即可被扫到**。

**跨仓边界（诚实口径）**：扫描运行在 `tools` 仓测试套件内，只能覆盖 `tools` 仓整树扫描面；`multica` 仓的 `cr-prompts-revised/delivery-agent.md` 与 KB 侧文档不在本扫描范围，其迁移由 §4.3 清单 + FR-14 有界盘点 + 本 CR 评审（`review-tech-design`/`review-code`）覆盖，不由工具机器证明。

#### 4.5 测试迁移算法（FR-9 / FR-12）

1. **结构断言模板**（替代 `includes('…')`）：

```js
const CRCTL_JS = path.resolve(import.meta.dirname, '..', 'crctl.mjs');   // 每个测试文件内一行
assert.equal(res.recovery.executable, 'node');
assert.deepEqual(res.recovery.args, [CRCTL_JS, 'checkpoint', cr, '--workspace', ws]);
assert.equal(res.recovery.cwd, ws);
assert.equal(res.recovery.requiresTTY, false);
assert.deepEqual(res.recovery.promptFor, []);
```

2. **不对完整 JSON 做脆弱快照**：只断言 `recovery` 内的确定字段与该生产者相关的其它字段，临时路径按元素与顺序断言；
3. **参数边界向量**（每类生产者至少一条）：CR-ID / workspace / branch-ref 各占独立元素；含空格的临时路径无需引号即正确传递；元素顺序与 CLI 合同一致；
4. **用户输入向量**（`review-loop reset`，6 类）：`normal reason`、含双引号、含分号、含换行、`$(substitution)`、反引号表达式 —— 每类断言：`args` 不含该值、`promptFor` 含 `reason`、`requiresTTY === true`、`JSON.stringify(recovery)` 中该值不出现（数据而非 shell command）；
5. **合同缺失向量**：四类场景（§3.5 表）由消费方提示词合同承接（§8），生产者侧对应保证是「构造器只产出合法形状 + 每类生产者结构断言」，不新增运行期校验代码；
6. **shell 逃逸守卫**：新增断言 `crctl.mjs` / `lib/*.mjs` 内不存在 `shell: true` / `Invoke-Expression`（AC-04），与既有 `spawnSync(..., { shell: false })` 事实一致（§11-4）。
7. **迁移不得减少任何登记文件的用例数（合并后门禁的硬约束）**：合并后 CI 全量步骤（`suite-gate.mjs --run`）对 `skills/shared/crctl/scripts/test/` 施加两条机器判定（`suite-gate.mjs:437-453`）：(a) 磁盘测试文件集合 ≡ `gate-registry.json#manifest.files`（恰 **21** 个文件，`SUITE_MANIFEST_FILE_DRIFT`），且**被真实 spawn 的文件集合**也须与之一致；(b) 每个文件的顶层用例数不得低于 `manifest.cases`（`SUITE_MANIFEST_CASE_DROP`，`suite-gate.mjs:452-453`）。本 CR 迁移的 7 个文件与 `contract-scan.test.mjs` 全部落在该目录内，因此：
   - 字符串包含断言 → 结构断言的改写**逐用例原位替换**，不得删除、合并、重命名或跳过任何顶层用例（新增用例允许，只增不减）；
   - **本 CR 不新增该目录下的测试文件**（会撞文件集合等式），也不改登记面 —— `gate-registry.json` 的 `manifest.files` / `manifest.cases` / `exceptions` 唯一写入口是人类编辑 + git commit（CR-2026-065 SDD TDEC-2），不属本 CR `scope_in`；因 `exceptions: []`，本 CR 内**没有可用例外通道**，迁移必须自证全绿（见 §6.3 AC-07）；
   - writeback 单测（`skills/writeback/scripts/test/*.test.mjs`）不在该登记面内（`readTestFileSet` 只枚举前者），可正常新增用例。

### 5. 技术选型与替代方案

#### D-1 `executable: 'node'` + `args[0]` = crctl 绝对路径（采用）

- **Context**：现字符串为两种形态——深原语写 `crctl <sub> …`（裸命令名），`test` 写 `node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs test …`。本机与沙箱实测裸 `crctl` 不在 PATH（KB `AGENTS.md` 规定的正式入口就是 `node <ToolsRoot>/skills/shared/crctl/scripts/crctl.mjs`）。
- **Decision**：统一为 `executable: 'node'`、`args[0]` = 模块相对解析出的 `crctl.mjs` 绝对路径。理由是合同的第一用户是「直接 spawn 的执行方」（US-1），不可执行的入口等于把问题从「字符串拼接」换成「入口不可用」；PRD FR-3 专门为 node 形态规定了 `args[0]` 规则，AC-10 也要求 `node` 形态的断言，说明该形态在批准范围内。
- **Alternatives**：① 保留裸 `crctl` —— 逐字保留现串，但恢复动作在新环境不可执行，且与 KB `AGENTS.md` 的规范入口冲突；② 用 `process.execPath` —— 更省事，但把环境相关值写入 `recovery`，与 FR-17「不得含环境相关的可变成分」冲突。
- **Consequences**：`args[0]` 为安装路径（与 `--workspace` 同类的稳定事实），指纹在单机可复现；消费方无须关心 PATH；测试需按同一规则计算 `CRCTL_JS`。

#### D-2 单一构造器 `buildRecovery`（采用）

- **Context**：11 个站点各写一份对象字面量会出现字段缺失、键序不一、`executable` 漂移三类隐患，且 FR-17 的指纹稳定性依赖同一构造规则。
- **Decision**：唯一构造器 + 输入守卫，全部站点经它构造。
- **Alternatives**：站点各自写字面量（少一处抽象，但 11 份形状靠人工保持一致，评审与未来改动成本更高）。
- **Consequences**：新增内部错误码 `RECOVERY_CONTRACT_INVALID`（仅程序员错误可达）；`buildRecovery` 成为合同唯一实现点。

#### D-3 构造器落在 `lib/workspace-transactions.mjs`，不新增 `lib/recovery.mjs` 模块（采用）

- **Context**：生产者与 CLI 都需要它；`tools/ARCHITECTURE.md` §3 以显式枚举方式描述 `lib/` 下的模块（`yaml-subset.mjs` / `workspace-transactions.mjs` / `durable-tx.mjs`），而本 CR 对该文档是**只读**（write-tech-design 步骤 1 禁止借道修订，其 §8 修订触发表也不含新增 lib 模块）。
- **Decision**：作为 `workspace-transactions.mjs` 的导出函数（该模块本就是这些恢复结果的产出层），CLI 向下 import。
- **Alternatives**：新建 `lib/recovery.mjs`（职责更纯，但会让 ARCHITECTURE.md 的模块枚举立刻失真，或迫使本 CR 越界改架构文档）。
- **Consequences**：零架构文档漂移；`workspace-transactions.mjs` 多一个小函数（约 12 行）。

#### D-4 `promptFor` 取代占位符（采用）

- **Context**：现串有三类不可确定值：`reset --reason`（必须人工重输）、`test --plan`（临时计划文件，调用方给定）、非规范 `CR-ID`（`gate` 错配场景的位置参数）。
- **Decision**：这三类值从 `args` 中移除并声明在 `promptFor`；`CR-ID` 规则同理（规范时作为独立元素，非规范时省略并列入 `promptFor`）。
- **Alternatives**：① 在 `args` 里保留 `<CR-ID>` / `<plan>` 哨兵 —— 与 FR-1「每元素是一个完整 argv」相抵，并把「该值必须重新获取」这一事实降级为字符串约定；② 非规范 CR-ID 场景干脆不返回恢复 —— 会丢失既有恢复方向（FR-13 要求保留原义）。
- **Consequences**：`args` 永不含占位符；忽略 `promptFor` 的消费方撞上目标 CLI 既有 `BAD_ARGS`（零副作用，§3.4）；`crIdForRecover` 的占位符语义被删除。

#### D-5 退役扫描复用既有机制 + 整树派生的扫描面（采用）

- **Context**：既有机制是 `node --test` 内的固定路径清单 + `includes` 断言；PRD FR-11 要求扫描范围为「活跃源码、活跃 Skill、活跃 Agent、Pipeline、活跃测试」，并允许排除历史证据/夹具/迁移文档/扫描器自身。该范围**已两次以同一方式咬人**：attempt 1 用手工清单，被「未覆盖其余活跃文件」判 BLOCK；attempt 2 改为按索引与活跃代码根派生，但把活跃源码限定为 crctl 的 7 个 `.mjs`、活跃测试限定为其 `scripts/test/**`，于是 `tools@dddd0ad6` 上另有 11 个活跃 MJS（`pipeline-templates/emit-registry.mjs`、requirement-register 的 production/test、3 个 crctl adapter hook、4 个 writeback production 脚本 + `writeback.test.mjs`）落在面外——「未列目录」被默认当成非活跃，漏项本身不可见。
- **Decision**：两个待退役字段名的扫描面改为**整树派生**（工作树全部文件，跳过 `.git` 与 `node_modules` 路径段）**减去恰两项被断言的精确路径排除**（扫描器自身、历史 traceability `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`），见 §4.4-2/§4.4-3；不再按目录或扩展名声明活跃性——**活跃性由「是否被显式排除」定义**。索引派生的 active Skill/Agent/Pipeline 集合降为一致性断言（条目必须存在于磁盘且落在扫描面内），规模只作覆盖度报告。`RETIRED`（CR-2026-041 的三个退役 Skill 名）保持既有显式范围不变（理由见 §4.4-1）。
- **Alternatives**：① 继续扩张手工清单 —— 已两次咬人，漏项不可见；② 只把代码面从 crctl 扩到 `skills/**/*.mjs` + `pipeline-templates/*.mjs`（评审给出的最小扩面）——仍是以扩展名/目录白名单声明活跃，同类盲区会重演（本仓已有 16 个活跃 `.ts` 不在 `.mjs` 白名单内，日后新增 `.js`/`.ps1` 或新目录同理）；③ 在 CI 里加 grep 步骤 —— 与既有测试机制并行成第二套扫描，违背「复用」。
- **Consequences**：新增活跃文件零成本进入面内，不因未列举而漏；排除用精确路径而非目录通配，故**同目录下的活跃向量与今后新增的 fixture 默认在面内**（这是 attempt 3 的唯一残留点，已收窄）；新增排除是显式且被断言的评审动作；代价是「零命中」从此覆盖整仓——今后若在 `tools` 落历史迁移/changelog 文档，必须显式加入排除表并被评审看见。历史 traceability 证据（精确路径一项）合法保留旧字段名（`RETIRED` 亦保留其显式范围）。

#### D-6 消费者侧四类检查落在提示词合同（采用）

- **Context**：本仓没有执行 `recovery` 的代码消费者 —— 消费者是 Skill / Agent / 平台 Prompt（PRD §1.1、US-1）。
- **Decision**：四类缺失检查与固定判定顺序写在 `skills/shared/crctl/SKILL.md` 的「`recovery` 消费合同」小节（单一事实源），四个消费 Skill 与 `delivery-agent.md` 只引用该合同并声明本节点动作；生产者侧由构造器与测试保证形状合法。
- **Alternatives**：新增一个 `validateRecovery()` 生产代码函数 —— 无任何生产调用点（死代码），只为测试存在，与本 CR「不新增通用命令执行框架」的边界相冲。
- **Consequences**：AC-11 的验证方式是「提示词文本逐条核对 + 生产者形状断言 + 旧字段结构上不可回退」，在 §6.3 显式写明，不以伪造的运行期测试冒充证据。

#### D-7 OpenWiki 页面由既有生成步骤产出，不手工编辑（采用）

- **Context**：`openwiki/operations/crctl-transactions.md` 是三处旧合同断言的活跃文档，其 frontmatter 的 `openwiki.source_paths` 恰好指向本 CR 迁移的四个源码文件；`tools/AGENTS.md` 的 OpenWiki 段明确「Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer updating source code/docs and letting OpenWiki regenerate」，`.github/workflows/openwiki-update.yml` 以 `openwiki code --update` 定时生成并开 PR（`add-paths: openwiki/AGENTS.md/CLAUDE.md/workflow`）。
- **Decision**：本 CR **不手工编辑**该页面。源码迁移与页面更新是同一个实施闭环：(1) 先改权威源码（§4.3）；(2) 在 `tools` 工作树内用同一生成命令（`openwiki` + `openwiki code --update`，provider/model 配置同 `openwiki-update.yml`）重新生成；(3) 核对生成结果——两个退役字段名零命中（按 §4.4 整树扫描面口径）+ 恢复合同描述为结构化 `recovery` + 生成 diff 不覆盖页面之外的人工内容；(4) 生成结果随本 CR 分支一并提交，生成命令与核对结论进入 `test-report.md` 证据。该步骤是 TASK 的完成条件；生成环境不可用（无 provider key / 无网络）时以环境阻塞上报，不得回退为手工编辑。
- **Alternatives**：① 手工改生成页 —— 违反 `tools/AGENTS.md` 约束，且下一次生成会覆盖，形成「手工维护 + 生成漂移」双源（本轮评审 BLOCK 的方案）；② 不迁移该页、只留 follow_up —— FR-8 要求文档单一事实源，旧合同描述留在活跃文档等于迁移不完整；③ 在 CI 加页面文本检查步骤 —— 与既有测试机制并行，且不能替代生成。
- **Consequences**：该页面回归「源码 → 生成器」单一回路；文档迁移结论由生成产物本身证明，不再有「手工迁移 + 后续漂移不算门槛」的降级口径；生成器对 `AGENTS.md`/`CLAUDE.md`/workflow 的附带改动不属本 CR 交付物（§9 `zero_diff` 优先，不纳入本 CR）。

### 6. FR 到技术实现映射

#### 6.1 FR 映射

| FR | 技术方案条目 | 落点 |
|---|---|---|
| FR-1 | §2.1 字段表 + §3.1 类型 + §3.2 构造器（键序/可选性/恒定 `executable`） | `workspace-transactions.mjs#buildRecovery` |
| FR-2 | §4.1 拆 token 六步（元素独立、顺序一致、含空格路径免引号、无备用 shell string） | 全部 9 类生产者 |
| FR-3 | §3.2 保证 1–2：`executable` 恒定 `'node'`，脚本路径恒在 `args[0]`；§4.5 守卫断言 | `buildRecovery` + 测试 |
| FR-4 | §3.4 `promptFor` 解析约定 + §4.1 第 5 步（值不进 `args`、`requiresTTY` 独立声明） | `cmdReviewLoopReset`、`testCr`、`cmdGate` |
| FR-5 | §4.1 逐个生产者 args 取值表（11 行，含条件参数保序） | `lib/workspace-transactions.mjs` 9 类场景 |
| FR-6 | §4.2 投影迁移四步（单投影、双投影删除、错误路径结构化、CLI 不拼串） | `crctl.mjs` 5 处 |
| FR-7 | §4.3 消费方四份 SKILL.md + `delivery-agent.md` 改法 | 5 个提示词文件 |
| FR-8 | §4.3 README 原位迁移 + OpenWiki 生成闭环（D-7，不手工编辑）；同一份源码即生成来源，不新增第二套描述 | `README.md`、`openwiki/operations/crctl-transactions.md`（生成） |
| FR-9 | §4.5 结构断言模板 + 6 类 reason 向量 + 反脆弱快照规则 | 7 个测试文件 |
| FR-10 | §4.1 第 6 步（原位删除、不并排双写）+ §2.3 别名表（无 alias/shim/fallback） | 全量站点 |
| FR-11 | §4.4 扫描算法（分名退役名单 + 整树派生扫描面 + 两项按精确路径冻结的可审计排除 + 八条代表性命中用例） | `contract-scan.test.mjs` |
| FR-12 | §4.5 向量 3/4/5/6（参数边界、6 类用户输入、四类缺失、`executable` 安全） | 测试 + 提示词合同 |
| FR-13 | §2.2 不落盘 + §3.3「其它字段与错误码/exit code/txId/rollback/files 不变」+ §4.2 只改载体 | 全量 diff 约束 |
| FR-14 | §11 既有实现依赖清单即基线盘点；六类归档口径在本表与 §4.3 已落形，正式归档表由 `write-dev-plan` 产出 | `plan.md`（下游节点） |
| FR-15 | §9 `scope_out` 明列「不做双写/不留半迁移」；回滚＝整体回滚（回退上一完整 `tools` 版本或回滚本 CR） | §9 + 流程约束 |
| FR-16 | §1.1 范围表「不更新平台 DB」+ §8 Prompt 采纳影响 | 本 SDD + 交付汇报口径 |
| FR-17 | §2.4 指纹字段集 + §3.5 固定判定顺序与错误闭包 + §3.1 零副作用（纯数据） | `buildRecovery` + 提示词合同 |

#### 6.2 复杂度与改动面

- 生产者 9 类 / 站点 11 处；CLI 投影 5 处；消费方提示词 5 个文件；文档 1 个（README 原位）+ 生成页 1 个（OpenWiki，由生成器产出，D-7）；测试 8 个文件。
- 净新增生产代码仅 `buildRecovery`（约 12 行）+ 站点改写（等价行数）；无新命令、无新状态、无新持久化。

#### 6.3 AC 逐项设计与验收映射

- **AC-01**（FR-1/FR-2）
  - 设计落点：`buildRecovery` + 11 个站点；`args` 元素由 §4.1 表逐条固定。
  - 可观测结果：每个生产者响应/错误中的 `recovery` 字段为固定 5 键、`args` 与 §4.1 表逐元素一致、无 `recoverCommand`/`recover_command`、无等价 shell string 备用入口。
  - 可达性说明：8 类恢复路径在既有测试中均有既有注入点（faultPoint / 预置 staged 变更 / 预提交钩子 / 非法入参），无权限或状态门禁过滤。
- **AC-02**（FR-5/FR-6）
  - 设计落点：`registerCr`、`syncWorkspaceToTrunk`、`mergeCr`、`checkpointCr`、`applyWritebackAtomic`、`archiveCr`、`testCr`、`cmdReviewLoopReset`。
  - 可观测结果：8 类恢复路径对应测试全绿，且断言的是结构化 `recovery`（非字符串包含）。
  - 可达性说明：`review-loop reset` 的失败分支由 `.githooks/pre-commit` 钩子触发（既有手法），其余由既有事务测试与故障注入覆盖。
- **AC-03**（FR-4/FR-12.2）
  - 设计落点：`cmdReviewLoopReset` 的 `recovery` 构造（`promptFor: ['reason']`、`requiresTTY: true`、`--reason` 不入 `args`）。
  - 可观测结果：6 类 reason 向量下 `args` 均不含该文本、`promptFor` 为 `['reason']`、`requiresTTY === true`、序列化结果为数据。
  - 可达性说明：reset 为 TTY 专用入口，测试用既有 `runCrctlInTty` 包装（已有工具函数），不因非 TTY 提前退出而不可达。
- **AC-04**（FR-17 副作用段）
  - 设计落点：全部执行点使用 argv 接口（既有 `spawnSync(..., { shell: false })`）；合同载体为纯数据。
  - 可观测结果：`crctl.mjs` 与 `lib/*.mjs` 内 `shell: true`、`Invoke-Expression` 零命中（新增守卫断言）。
  - 可达性说明：断言对象为活跃源码本身，无运行时前置条件。
- **AC-05**（FR-7/FR-8/FR-9/FR-10）
  - 设计落点：§4.3 逐文件改法清单（4 Skill + 1 Agent + 1 文档 + 7 测试）+ D-7 的 OpenWiki 生成闭环。
  - 可观测结果：扫描面内旧字段名零命中（扫描）；生成页由生成器从迁移后的源码产出且三处旧合同断言归零；`multica` overlay 逐条核对；无 alias/shim/fallback。
  - 可达性说明：`multica` 与 KB 侧不在 tools 扫描范围（§4.4 跨仓边界），由 §4.3 清单 + 评审比对 diff 覆盖；生成页的证据是「生成命令 + 生成前后 diff + 页面零命中」三条（D-7）。
- **AC-06**（FR-11）
  - 设计落点：§4.4 扫描算法（退役名单分名分范围、整树派生扫描面 + 两项精确路径排除、索引一致性硬失败、八条代表性命中用例）。
  - 可观测结果：扫描面内命中即测试失败（含 attempt 2 漏掉的 11 个活跃 MJS 与 16 个活跃 `.ts`，以及 attempt 3 被目录通配排除的 3 个 `digest-vectors` 活跃向量）；每个派生根的代表性注入用例证明范围非恒真；唯一被排除的 `traceability-191k.yml` 仍含旧名且被判为排除（不误报），同目录三个活跃向量在面内且零命中；索引/枚举空结构与索引条目缺失硬失败（不静默降级）。
  - 可达性说明：扫描是纯文件读 + 字符串判定，无环境依赖；整树枚举与三个索引均为仓内既有依赖（§11）。
- **AC-07**（FR-13）
  - 设计落点：零语义变更约束（§3.3）。
  - 可观测结果（两条命令逐字取自合并后基线的 `.github/workflows/crctl-ci.yml`，均为 CI 步骤）：
    1. `node skills/shared/crctl/scripts/test/suite-gate.mjs --run` —— `gate-registry.json#manifest` 登记的 **21** 个文件全部被真实 spawn（`--run` 按登记面逐文件 spawn，池大小 = `suite-gate.mjs` 的 `CONCURRENCY` 常量）、报告 `verdict: pass`、`failures` 空、`exceptions_count: 0`（`exceptions: []`）、退出码 0（`converged: true`）；
    2. `node --test skills/writeback/scripts/test/*.test.mjs` —— 全绿。
  - 可达性说明：两条命令分别是 `crctl-ci.yml:109-111`（`crctl full test suite`）与 `crctl-ci.yml:113-115`（`writeback unit tests`）的 CI 步骤，本机可复现；验收命令即 CI 门禁的判定入口，不存在「本地验收命令 ≠ CI 命令」的口径差。
  - 基线事实（本轮更新，CR-2026-065 已合入 trunk `tools@81d31b8`）：旧基线（`tools@dddd0ad6`）上的 5 条红已由 CR-2026-065 修复（断言改为从真实载体与事实源派生、RED-7 改为真实崩溃窗口重放），登记面 `exceptions` 已清空 ⇒ AC-07 回到**「全绿」**口径、**无需任何例外授权**（计划层原「失败集合恰等于登记 5 条」的例外口径由 `write-dev-plan` 节点按本项收敛，不属本 SDD 变更面）。
  - **不采用** `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs` 作为验收命令（本节点在 `tools@81d31b8` 上独立取证）：① 它不在 CI 中执行（`rg -n test-concurrency .github/workflows/` 零命中；CI 全量步骤已是 `suite-gate.mjs --run`）；② 同语义配置（文件级并发池 = 2，CR-2026-065 SDD TDEC-4）在合并后基线上无收敛与全绿证据——`change-requests/CR-2026-065/test-evidence/concurrency/conc2-run{1,2}.json` 与 `conc1-run{1,2}.json` 实测 `converged: false` / `exit_code: null`（`--max-runtime-ms` 1200 s 到期），而默认池两次 `converged: true` / `exit_code: 0`（783.4 s / 781.4 s）；③ 测试并发参数不属本 CR 变更面（`crctl-ci.yml` 与 `suite-gate.mjs#CONCURRENCY` 均不在 `scope_in`）。
- **AC-08**（FR-13）
  - 设计落点：diff 仅落在 `recovery` 载体与旧字段名措辞。
  - 可观测结果：既有错误码（`MERGE_SOURCE_MISSING`、`RELEASE_REMOTE_NOT_PUSHED`、`REVIEW_LOOP_RESET_COMMIT_FAILED`、`BAD_ARGS`…）、状态转换、`txId`、`rollback`/`files` 字段与事务测试未变部分全绿。
  - 可达性说明：逐项以既有测试 + `git diff --stat` 对照核对。
- **AC-09**（FR-16）
  - 设计落点：§8 采纳清单仅含 owner 可复制版本；平台 DB 部署在 CR 之外。
  - 可观测结果：本 CR 的 PLAN/TASK/交付汇报与 writeback 产物中无「平台 DB 已部署」表述，且显式记录 owner 部署动作。
  - 可达性说明：口径约束落在下游节点（`write-dev-plan`、交付汇报），节点粒度可见。
- **AC-10**（FR-3/FR-12.3）
  - 设计落点：构造器恒定 `executable: 'node'` + `args[0]` 为脚本路径。
  - 可观测结果：每类生产者的 `executable`/`args[0]` 断言；`executable` 不含空格与 shell 运算符（按构造）。
  - 可达性说明：断言直接读生产者输出，无前置过滤。
- **AC-11**（FR-12.4/FR-17）
  - 设计落点：`skills/shared/crctl/SKILL.md`「`recovery` 消费合同」（固定 5 步 + 四类闭包）为单一事实源；消费 Skill/Agent 引用之；生产者由构造器保证形状。
  - 可观测结果：提示词文本逐条可核对（顺序、停止、报告、零副作用、不猜测、不回退）；生产者输出形状断言全绿；旧字段无 alias ⇒ 回退在结构上不可达。
  - 可达性说明：消费方是提示词而非本仓代码，本 CR 无执行 `recovery` 的代码路径，故以「提示词合同 + 生产者形状断言」验证，不伪造运行期测试（D-6）。
- **AC-12**（FR-14）
  - 设计落点：六类归档口径（producer / code consumer / Prompt-Skill consumer / active test / active docs / historical evidence）+ §11 清单作为基线盘点；扫描范围本身由 §4.4 的派生规则从索引得出（与盘点口径一致）。
  - 可观测结果：`plan.md` 内存在一次有界搜索的六类归档表，且未新增持续观测机制。
  - 可达性说明：盘点在 `write-dev-plan` 节点执行；本 SDD 已按同一口径完成一次基线盘点（§4.3 + §11，行数/匹配次数口径见 §11 开头）。
- **AC-13**（FR-15）
  - 设计落点：单发布原子迁移（同 CR 内生产者 + 消费者 + 删除 + 扫描）。
  - 可观测结果：交付分支不存在「部分生产者新合同 / 部分消费者旧合同」；回滚方案为整体回滚（回退上一完整 `tools` 版本，不在当前版本双写）。
  - 可达性说明：由同一 CR 内全量迁移 + 全量测试保证；回滚口径记录在 §9。
- **AC-14**（FR-16）
  - 设计落点：正常 writeback（`specs/`、`delivery/`）在本 CR 流程内。
  - 可观测结果：writeback 产物存在且与 CR 结论一致。
  - 可达性说明：由 `feature-writeback` 节点产出，本 SDD 不预置。

#### 6.4 SDD-CLOSE 关闭结论

PRD 显式延后到 SDD 的设计项逐项关闭（覆盖数据生产、存储/传输、响应/schema、消费与兼容降级各层）：

- **SDD-CLOSE-01（恢复合同接口闭包）**：字段集、类型、必填性、键序、`cwd` 语义与可选性、命名冲突 → §2.1/§2.3/§3.1/§3.2 关闭。覆盖：生产（构造器）、传输（JSON 响应）、响应/schema（CLI 输出与 `error.extra`）、消费（提示词）、兼容降级（无 alias/shim，旧字段删除）四层。
- **SDD-CLOSE-02（argv 边界与 executable 规范化）**：token 拆分、顺序、含空格路径、node 形态 `args[0]` → §4.1/§3.2 关闭；同时关闭「`test` 恢复中的 `{TOOLS_ROOT}`/`<worktree>` 占位符」问题（改用真实路径）。
- **SDD-CLOSE-03（`promptFor` 解析约定）**：逻辑值名 → CLI 入口映射、从 `args` 省略、忽略时的安全失败 → §3.4 关闭；覆盖 `reason`/`plan`/`CR-ID` 三处生产点与消费侧取值要求。
- **SDD-CLOSE-04（错误闭包与判定顺序）**：固定 5 步顺序、四类缺失的停止/报告动作、零副作用、不回退旧字段、非 shell 执行 → §3.5 + §8 关闭（消费者侧文本合同 + 生产者侧形状保证 + 旧字段结构性删除）。
- **SDD-CLOSE-05（契约扫描实现方式）**：复用既有机制的扩展点、整树派生扫描面（不以目录/扩展名白名单声明活跃）、两项按精确路径冻结的可审计排除（`fixtures/` 目录内只有历史 `traceability-191k.yml` 被排除，其活跃 digest 向量与新增夹具默认入面）、八条命中即失败用例与不误报的正反用例、索引一致性硬失败、分名分范围的既有名单不变式、跨仓边界 → §4.4 关闭。
- **SDD-CLOSE-06（逐文件改法与文案口径）**：11 个生产者站点 + 5 个 CLI/投影点 + 5 个提示词 + 1 个文档（README 原位）+ 1 个生成页（OpenWiki 由生成器产出并核对，D-7）+ 8 个测试的改法；错误消息与展示文案不得引用退役字段名、显示文本只能从 `recovery` 渲染 → §4.3 关闭（含「消息文本去旧名」两条）。

无未关闭项；无遗留待办。

### 7. 安全与性能考量

#### 7.1 安全控制点

| 控制点 | 设计 | 验证 |
|---|---|---|
| 注入面闭合 | 用户可控输入（reason、路径、ref）只以独立 argv 元素承载，不进入任何被 shell 解释的字符串 | 6 类 reason 向量 + 无 shell string 断言 |
| 执行方式 | 消费方与非 shell 接口一致（`spawn`/`execFile` 语义）；`shell: true` / `Invoke-Expression` 零命中 | 守卫断言（AC-04） |
| 入口可信 | `executable` 恒定 `node`，脚本路径由模块位置解析（不接受外部注入） | 构造器 + 断言 |
| 人在环 | `requiresTTY`（reset）与 `promptFor`（reason/plan/CR-ID）只结构化声明既有要求，不削弱也不新增绕过路径 | 提示词合同 + 断言 |
| 显示与执行分离 | 人类可读文本只能从 `recovery` 渲染，且不得反向作为执行输入 | 提示词文本（§4.3） |
| 退役保护 | 旧字段名在活跃面命中即失败，防止回流 | §4.4 扫描 |

#### 7.2 性能

- `recovery` 是纯数据构造（对象字面量 + 一次数组拼接），无 I/O、无子进程、无解析；对既有事务路径的开销可忽略。
- 不新增常驻进程、扫描调度或流水线阶段；退役扫描沿用既有静态测试，不新增 CI 步骤（`crctl-ci.yml` 零改动）。

#### 7.3 边界条件

- `args` 为空候选值（`--stage traceability` 的 `--target-version` 为空串）仍作为合法 string 元素保留原样，由目标 CLI 既有校验判定（不新增本层校验）。
- 含空格/非 ASCII 的路径与文本（含中文 summary、含换行 reason）遵循同一 argv 规则，无引号处理分支。
- 同一 CR 的 `recovery` 在重复求值时逐元素相等（§2.4）。

### 8. Prompt 采纳影响

本 CR **确实触及** `crctl.mjs` 的结果合同（命令面输出/错误面字段改名），因此按 write-tech-design 步骤 2 第 8 节填写；`skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny` 未触及。

| Skill / Agent 提示词 | 现状 | 应改为 |
|---|---|---|
| `skills/shared/crctl/SKILL.md` | `merge`/`archive` 行描述 `recoverCommand`；无消费合同 | 「携 `recovery`（指向 checkpoint）」+ 新增「`recovery` 消费合同」小节（固定 5 步判定 + 四类闭包，单一事实源） |
| `skills/cr/cr-archive/SKILL.md` | 「只重跑 recoverCommand」 | 「按 `recovery`（argv）重跑同一 `crctl archive`」，唯一续跑入口表述不变 |
| `skills/sync/push-progress/SKILL.md` | 按 `recoverCommand` 分流/重跑 | 按 `recovery` 重跑同一命令 |
| `skills/writeback/merge-feature-branch/SKILL.md` | 「按 extra.recoverCommand 先 checkpoint」 | 「按 `error.recovery` 先 checkpoint 再重跑 merge」 |
| `multica/cr-prompts-revised/delivery-agent.md` | 「明确 `recoverCommand`」 | 「明确的结构化 `recovery`（argv）」；失败汇报项改名 |

**采纳完整性**：以上 5 处即本 CR 全部需要采纳新合同的活跃提示词（由 §11 的全文检索基线盘点确定，`rg "recoverCommand|recover_command"` 命中集合逐条落位）。
**无遗留采纳项**：本 CR 内同批迁移，不存在「crctl 已有新能力但某提示词尚未采纳」的后续项。
**平台部署边界**：`multica/cr-prompts-revised/*.md` 只是 owner 可复制的版本，平台 DB 内提示词由 owner 在 `tools` 发布后另行更新（FR-16）；本 CR 不更新平台 DB，也不声称已部署。

### 9. 批准范围

#### scope_in

- 唯一结构化恢复合同 `recovery`（`executable`/`args[]`/`cwd`/`requiresTTY`/`promptFor[]`）与唯一构造器 `buildRecovery`（§3.2）。
- 11 个生产者站点迁移（§4.1 表 1–9）与 5 处 CLI 投影/错误面迁移（§4.2），含 `register` 双投影删除。
- 旧字段 `recoverCommand` / `recover_command` 在本 CR 内删除，无 alias/shim/fallback。
- 5 个活跃提示词的消费方式迁移（§8）+ 1 个文档原位迁移（`README.md`）+ 1 个生成页由既有生成步骤产出并核对（`openwiki/operations/crctl-transactions.md`，D-7）+ `skills/shared/crctl/SKILL.md` 新增「`recovery` 消费合同」小节。
- 7 个既有测试文件的结构断言迁移 + `contract-scan.test.mjs` 的退役名单/扫描面/正反用例扩展 + `shell: true`/`Invoke-Expression` 守卫断言；上述文件（含 `contract-scan.test.mjs`）的顶层用例数**只增不减**（逐用例原位替换，`manifest.cases` 为下限，见 §4.5-7）。
- FR-1…FR-17、AC-01…AC-14 全部。

#### scope_out

- 不新增通用命令执行框架、shell parser、quoting library、跨 shell renderer。
- 不改 `reviewLoop` / `archive` / `merge` / `checkpoint` / `writeback` 业务算法，不改错误码/状态转换/门禁语义。
- 不做双写兼容期、deprecated alias、migration shim、第二个删除 CR。
- 不改写历史 CR、历史 traceability、归档 delivery 证据、历史夹具精确路径 `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml`（该目录下 `digest-vectors/**` 三个活跃测试向量不在此列：它们在扫描面内，本 CR 不改其内容、只让它们被扫描保护）。
- 不更新 Multica DB/平台 Prompt、不改 Multica API 或 importer（含 `aifirst/agent-import.mjs`）。
- 不新增使用量/失败率/SLO/迁移统计或持续观测机制。
- 不包含 AIFI-18 的 SDD review 规则、`_context.md` 删除、plan/TASK 增量回修、Pipeline 节点调整。
- 不新增 `skills/shared/crctl/scripts/test/*.test.mjs` 测试文件、不修改 `gate-registry.json` 的登记面（`manifest.files` / `manifest.cases` / `exceptions`）——其唯一写入口是人类编辑 + git commit（CR-2026-065 SDD TDEC-2），需 owner 授权；本 CR 内无例外通道（`exceptions: []`，见 §4.5-7），确需新增测试文件或例外时另开 CR。
- 不与 CR-P1 / CR-P2 合并为同一发布单元。

#### zero_diff

- `tools/ARCHITECTURE.md`、`dir-graph.yaml`、`skills/shared/crctl/gates.json`、`skills/shared/controlled-shell/rules.json`、`pipeline-templates/**`、`.github/workflows/**`：零改动。
- 既有公开错误码、`exit code`、`txId`、`status`/转换语义、`files`/`rollback` 字段、`.crctl/transactions/**` journal schema：零改动。
- 成功结果中除 `recoverCommand`/`recover_command` 外的其它字段（含 `cr_id`/`tx_id`/`operational_workspace` 等 snake_case 镜像）：零改动。
- 既有 `spawnSync(..., { shell: false })` 执行点、`recoverWriteSet`/`recoverLedgerTransaction` 等内部恢复原语名：零改动。
- `tools/agents/*.md`（含 `agents/delivery-agent.md`）：零改动（无旧字段引用，理由见 §11-13）。

#### follow_up

- `mergeCr` 的 `phase=release-drift` 结果仍携带「重跑 merge」方向的 `recovery`，但该分支已由深原语自动回退 `code-approved → developing`，重跑 merge 不会成功。本 CR 只做等价迁移（FR-13 零语义变更），方向修正留待后续 CR 评估。
- `tools/agents/delivery-agent.md`（方法论包内的 Agent 基底版）与 `multica/cr-prompts-revised/delivery-agent.md` 内容已不同步；本 CR 只迁移后者（PRD 指定），两者收敛留待后续 CR。

### 10. 术语硬化与边界场景验证

| 术语 | 进入哪一层 | 歧义/别名/边界风险 | 边界场景验证（至少一条） | 结论 |
|---|---|---|---|---|
| `recovery`（响应字段） | 接口契约 | 与内部恢复原语 `recoverWriteSet` / `recoverLedgerTransaction` / `recoverLedgerCommand`、与错误码 `TX_RECOVERY_CONFLICT` 同前缀不同层 | 构造器返回对象只含 5 个约定键；内部原语名零改动（`rg "recoverWriteSet"` 不变） | 命名冲突已记录：不合并、不改名；字段名指「恢复动作的结构化载体」 |
| `recoverCommand` → `recovery` | 接口契约 | PRD canonical term 与代码别名映射：旧名退役，无 alias | 活跃面扫描零命中（含 `fixtures/digest-vectors/**` 三个活跃向量）；唯一被排除的 `traceability-191k.yml` 仍含旧名且被判为排除 | 映射记录完毕；旧名为「已退役别名」，不保留读取路径 |
| `cwd` | 接口契约 | 与既有 `--workspace` / `ctx.installRoot` 语义重叠可能被误当作唯一权威 | ① 生产者侧的 `cwd` 与 `--workspace` 值同源（同一变量取两次，不各自计算）；② `buildRecovery` 省略 `cwd` 时对象不含该键（单测覆盖可选性边界） | `--workspace` 是 CLI 的权威解析入口（语义保留），`cwd` 是进程工作目录事实；二者不得出现不同来源 |
| `requiresTTY` | 接口契约 | 与既有错误码 `NOT_TTY` 的关系 | reset 恢复的 `requiresTTY === true`，非 TTY 下 CLI 自身 `NOT_TTY` 拒绝（既有行为不变） | 一致：`requiresTTY` 是「必须在可信交互终端执行」的结构化声明，不新增门禁 |
| `promptFor` | 接口契约 | 值名 vs CLI flag 名的映射歧义（`reason`/`plan`/`CR-ID`） | 三处取值名与目标入口在 §3.4 逐条固定；忽略时撞 `BAD_ARGS`（零副作用） | 规则已硬化：值名是逻辑名，按 §3.4 表映射到既有入口 |
| `executable` | 接口契约 | 与 `cr-test-plan/v1` 的 `executable` 同名词、不同对象 | 两处语义一致（均指非 shell 可执行入口），互为先例；测试计划 schema 零改动 | 同名同义，不构成冲突 |
| `args` | 接口契约 | 与 `cr-test-plan/v1` 的 `args` 同名词 | 同上；`recovery.args[0]` 为脚本路径（node 形态），测试计划 `args` 不含脚本路径 | 语义一致，形态差异在 §3.2 明确 |

**语义冲突裁决**：未发现 PRD canonical 语义与既有代码语义冲突的术语，无需在首次 `crctl advance` 前请求需求负责人澄清（本节点已完成该推进：`requirement-approved → tech-designing`）。

### 11. 既有实现依赖与事实

**计数口径（唯一，三个数字各自对应一条命令）**：在固定 HEAD 的仓库工作树根执行——

| 数字 | 命令 | 语义 |
|---|---|---|
| 文件数 | `rg -l "recoverCommand\|recover_command"` | 含 ≥1 次命中的 distinct 文件 |
| 行数 | `rg -c "recoverCommand\|recover_command"` 逐文件求和 | 含 ≥1 次命中的行（同一行多次命中只计 1） |
| 匹配次数 | `rg -o "recoverCommand\|recover_command"` 计数 | 全部 match 总数（同一行多次命中各计 1） |

口径固定项：大小写敏感（只退役响应字段名 `recoverCommand` / `recover_command`；内部局部变量 `checkpointRecoverCommand`（仅存在于 `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` 的 `mergeCr` 内，`~L1557`；`~L1570` / `~L1573` 取值）里的 `RecoverCommand` 不属退役名，随站点 4 结构化一并改写名称但不计入本盘点）、不加 `-w`、用 `rg` 默认的 `.git`/`.gitignore` 过滤（不用 `-uu`，不遍历被忽略目录与隐藏文件）。正文凡「X 文件 / Y 行 / Z 次」均按上表三项分别给值，不混用口径。计数文件集为该 commit 的 tracked 内容——在 CR 的 `tools` worktree（HEAD 同上、`git status` clean）上执行即为该集合；工作树内未跟踪文件不属该 commit，不计入（例：主检出里遗留的未跟踪 `skills/shared/crctl/scripts/reference/error-codes.md` 含 2 行 / 2 次，不进 16 / 72 / 87）。

另一套规模口径（§4.4-2 扫描面，同一枚举规则，**合并后基线** `tools@81d31b8` 重跑；报告值，不冻结为等式）：工作树枚举 **218** 文件（`readdirSync(..., { withFileTypes: true, recursive: true })` 返回的非目录条目共 219，其中 1 个是被本规则按路径段排除的 `.git` 文件；按规则排除后 = 该 commit 的 tracked 集合 218，工作树 clean）− 扫描器自身 1 − 历史 traceability 精确路径 `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml` 1 = **扫描面 216 文件**；`skills/**` + `pipeline-templates/**` 递归 `.mjs` 共 **43**（活跃源码 17 / 活跃测试 26，进入扫描面 25）；三个 active 索引条目数 **56 / 9 / 8**（条目全部存在于磁盘）；`fixtures/` 目录内 4 个文件中 **3 个在扫描面内**（`digest-vectors/**`，对两个退役名零命中）、**1 个被排除**（历史 `traceability-191k.yml`）。`dddd0ad6` 基线对应值为 214 / 212 / 40（16 / 24）。旧字段命中计数仍按上表三项口径，两者不混用。

盘点基线（本节开头口径重跑）：`tools@dddd0ad63fb79bd7608314b4553f30e8ce7b7289` = **16 文件 / 72 行 / 87 次**（合并后 HEAD `81d31b8` 上重跑同值——本 CR 至今未落实现代码，迁移对象集合不变）；`multica@ab9609483d17db12117cb8e9adb2d896f413917d` = **3 文件 / 6 行 / 6 次**（合并后 HEAD `dead9fe0d5a24118547a5be56d59241fdcc443a8` 上复核同值；其中 2 个文件是 `server/internal/governance/testdata/` 历史黄金数据，另 1 个是 `cr-prompts-revised/delivery-agent.md`）。本节清单中的 `commit SHA` 字段是该事实**首次核实**的基线，不随 trunk 合并改写；`review-tech-design` cycle 2 attempt 3 节点已在合并后基线（`tools@81d31b8`、`multica@dead9fe0`、KB `3b951289`）上逐项复核，除第 16 项（CI 全量步骤行为已变，本次修订更新）与两处规模口径（本次修订更新）外，其余各项的 `relative path` / `stable symbol` / 依赖结论在新 HEAD 上仍成立。以下为按正文首次出现顺序的依赖清单（D-7 与 §4.4 派生范围的事实源接在既有 17 项之后）：

1. repo: `tools`
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `registerCr` / `syncWorkspaceToTrunk` / `mergeCr` / `checkpointCr` / `applyWritebackAtomic` / `archiveCr` / `testCr` / `buildTestResponse` 的返回值与 `TxError.extra` 载体（本文件 23 行 / 25 次旧字段命中）；其中 `mergeCr` 内的局部名 `checkpointRecoverCommand`（`~L1557`，`~L1570` / `~L1573` 两个 `TxError` 的 `extra.recoverCommand` 取值来源）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 这些函数是全部恢复动作的生产者，其返回结构与 `extra` 字段名即本 CR 的迁移对象；`buildRecovery` 落在本文件内（D-3），因此本文件同时是唯一构造器的宿主。局部名 `checkpointRecoverCommand` 是站点 4（merge publication lag → `checkpoint`）的既有承载点：大小写敏感的退役名扫描对它零命中（不属退役名、不计入本盘点），但 `~L1570` / `~L1573` 两处 `extra.recoverCommand` 在本 CR 内同批改为 `extra.recovery`，该局部值随之由 shell string 改为 `buildRecovery(...)` 产出的结构化对象，旧名与旧串均不保留（§4.3 `mergeCr` 行同址）。
2. repo: `tools`
   relative path: `skills/shared/crctl/scripts/crctl.mjs`
   stable symbol/对象: `crIdForRecover`（`~L963`）、`cmdGate` pre-review 错配分支（`~L974`）、`cmdReviewLoopReset` 提交失败分支（`~L1906`）、`buildRegisterResult`（`~L2753`）、`cmdRegister` 输出对象双投影（`~L3304`）；同一文件内 `cmdReviewLoopReset` 的 `NOT_TTY` 前置校验（`~L1840`）与 `fail`/`ok` 输出信封契约（定义位置 `~L43`/`~L49`：错误 `{ error: {...} }` 走 stderr + exit 1，成功对象走 stdout）；`canonicalEvidenceDigest`（`~L87`）把 `test/fixtures/digest-vectors/` 声明为 Go 侧等价实现的固定共享测试向量（§4.4-3 排除收窄的事实依据）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: CLI 是唯一投影层；`error.recovery` 与顶层 `recovery` 的落点由 `fail()`/`ok()` 的既有形状决定（见 3）；`NOT_TTY` 校验是 `requiresTTY: true` 的事实依据。
3. repo: `tools`
   relative path: `skills/shared/crctl/scripts/lib/durable-tx.mjs`
   stable symbol/对象: `TxError`（`code`/`message`/`extra`）与 `loadOrCreateJournal`/`saveJournal` 的 journal payload 结构
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: `extra` 是错误面恢复数据的唯一传递通道；journal payload 不含恢复字段，是「不落盘、无 schema 迁移」（§2.2）的事实依据。
4. repo: `tools`
   relative path: `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
   stable symbol/对象: `parseTestPlan` / `runTestPlan` 的 argv 执行先例（`cmd.executable` + `cmd.args` + `spawnSync(..., { shell: false })`，`cr-test-plan/v1`）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 本仓既有代码已以 `executable` + `args` + `shell:false` 执行外部命令，`recovery` 合同沿用同一形态与命名，属仓内既有先例而非新范式（D-1、§10）。
5. repo: `tools`
   relative path: `skills/shared/crctl/scripts/test/contract-scan.test.mjs`
   stable symbol/对象: `FORBIDDEN` / `RETIRED` / `ACTIVE_PATHS` 既有静态扫描机制与 `readFileSync + replaceAll('\r\n','\n') + includes` 判定；`skills/_index.yml` / `agents/_index.yml` / `pipeline-templates/_index.yml` 的 active 条目（`status` + `path`）是 §4.4-2 索引一致性断言（条目必须存在于磁盘且落在扫描面内）的事实源
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: FR-11 要求复用既有静态合同扫描机制——该文件即既有机制，本 CR 在其上按名分范围追加 `RETIRED_RECOVERY` 与整树派生扫描面（§4.4），不新建扫描器。既有 `RETIRED` 三个名字在活跃面内**合法存在**（`lint-prompts.mjs` 禁止名单、`crctl.test.mjs` / `lint-prompts.test.mjs` 用例样本、`CUSTOM.md` 台账引述），另有 `docs/` 下两份历史报告与历史夹具亦含这些名字（`rg -l` 本 HEAD 共 8 个文件）——故其范围必须保持既有显式 `ACTIVE_PATHS` 不变（整树扫描会对历史报告误报）。
6. repo: `tools`
   relative path: `skills/shared/crctl/scripts/test/{archive-tx,checkpoint-tx,merge-tx,register-tx,workspace-freshness,writeback-tx,crctl}.test.mjs`
   stable symbol/对象: 旧字段字符串断言（`result.recoverCommand.includes(...)`、`assert.match(r.json.recoverCommand, …)`、`assert.equal(r.stderr.error.recoverCommand, …)`、`recover_command`）；`crctl.test.mjs` 的 digest-vectors 用例（`~L548-556`）直接读取 `test/fixtures/digest-vectors/{expected.json,review-annotations-code.yml,test-report.md}` 三个文件做 canonical digest 一致性断言——这三个文件因此是活跃测试向量而非历史证据（§4.4-3 排除收窄的事实依据）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 这些断言是 FR-9「改为结构断言」的迁移对象；同时它们是 AC-02/AC-03/AC-07 的既有证据通道（恢复路径已可达）。
7. repo: `tools`
   relative path: `skills/shared/crctl/SKILL.md`
   stable symbol/对象: 命令面表格（`merge` / `archive` 行）对恢复字段的消费说明
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: 该文件是 crctl 命令面的权威 Skill 文档，也是新增「`recovery` 消费合同」的落点（§8、D-6）。
8. repo: `tools`
   relative path: `skills/cr/cr-archive/SKILL.md`
   stable symbol/对象: Step 2/Step 3 结果分类表、输出模板「恢复」行、错误处置表（6 行 / 7 次旧字段命中）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: `archive` 的清理/补发续跑语义依赖恢复动作，提示词必须改读结构化 `recovery`（FR-7）。
9. repo: `tools`
   relative path: `skills/sync/push-progress/SKILL.md`
   stable symbol/对象: Step 2 错误分流与错误处置表（2 行 / 3 次旧字段命中）
   commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
   依赖结论: `checkpoint` 重跑口径依赖恢复动作（FR-7）。
10. repo: `tools`
    relative path: `skills/writeback/merge-feature-branch/SKILL.md`
    stable symbol/对象: `MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` 行（1 行 / 1 次旧字段命中）
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: publication lag 的恢复入口（`extra.recovery`）是该 Skill 的既定分支，字段名变更须同步（FR-7）。
11. repo: `tools`
    relative path: `README.md`（§7「恢复与 `crctl status/next`」第 2 条）
    stable symbol/对象: 「中途失败：按输出的 `recoverCommand` 重跑同一条命令」的合同描述
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 使用方仓库最先读到的恢复合同说明，必须与代码同批迁移且不得新增第二套描述（FR-8）。
12. repo: `tools`
    relative path: `openwiki/operations/crctl-transactions.md`
    stable symbol/对象: frontmatter `invariants[1]`、正文「Durable Transaction Envelope → Recovery」条、「Change-Safety Guidance」第 3 条（3 行 / 3 次旧字段命中）；`openwiki.source_paths` 指向本 CR 迁移的四个 crctl 源码
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 该页面是三处旧合同断言的活跃文档，且是**生成物**：权威输入是 `source_paths` 指向的源码（本 CR 同批迁移），页面按 `.github/workflows/openwiki-update.yml` 的既有生成步骤重新生成后核对（D-7）。本 CR 不手工维护该页，不存在第二套描述。
13. repo: `multica`
    relative path: `cr-prompts-revised/delivery-agent.md`
    stable symbol/对象: 交付纪律段（`L27`「明确 `recoverCommand`」、`L44` 失败汇报项）
    commit SHA: `ab9609483d17db12117cb8e9adb2d896f413917d`
    依赖结论: 交付 Agent 的 owner 可复制提示词是 FR-7 指定的活跃消费者之一；平台 DB 内版本由 owner 另行部署（FR-16）。
14. repo: `tools`
    relative path: `agents/delivery-agent.md` 与 `agents/*.md`
    stable symbol/对象: 方法论包内的 Agent 提示词全集
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 全量检索确认这些文件**不含**旧字段名（故列入 `zero_diff`，不可借机改动）；`agents/dev-agent.md` 的「按 crctl 明示的恢复方向恢复一次」措辞不绑定字段名，语义在新合同下仍成立。
15. repo: `tools`
    relative path: `skills/shared/engineering-docs/templates/SDD-template.md`、`skills/develop/write-tech-design/SKILL.md`
    stable symbol/对象: 本 SDD 的章节与范围章节契约
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 本 SDD 的章节结构、`target-version` 继承与 §9 四字段约束来自该模板与 Skill，落地时必须符合。
16. repo: `tools`
    relative path: `.github/workflows/crctl-ci.yml`
    stable symbol/对象: 全量测试步骤 `crctl full test suite` = `node skills/shared/crctl/scripts/test/suite-gate.mjs --run`（`:109-111`）、Pipeline JSON 结构步骤（`:68-70`，`readdirSync('pipeline-templates')` + 读 `skills/_index.yml` 求 active Skill 集合）、`writeback unit tests` 步骤 = `node --test skills/writeback/scripts/test/*.test.mjs`（`:113-115`）
    commit SHA: `81d31b8b9d4c36cfef24cd076bf9fe635b67b2b6`
    依赖结论: AC-07 的两条验收命令与 §4.4 索引一致性校验的既有先例（按索引求 active + 目录动态枚举）均来自该文件；本 CR 不改 CI 配置。全量步骤已由 CR-2026-065 从 `node --test --test-concurrency=2 …` 换为 `suite-gate.mjs --run`（`test-concurrency` 在 `.github/workflows/` 零命中），SDD 记录的验收入口随合并后事实更新（见 §6.3 AC-07）；Pipeline 索引动态枚举与 writeback 单测两步不变。
17. repo: `tools`
    relative path: `ARCHITECTURE.md`
    stable symbol/对象: §3 代码地图（`lib/` 模块枚举与 `crctl.mjs` 职责）、§4 分层规则、§5 不变量（状态单一写者、零依赖、行尾纪律、状态机口径）、§8 维护规则
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 本 CR 的设计必须不违反上述不变量（构造器下沉 lib、CLI 单向依赖、零第三方依赖、行尾规范化、无新状态），且因未触发 §8 修订条件而不修该文档（D-3）。

18. repo: `tools`
    relative path: `AGENTS.md`（`<!-- OPENWIKI:START -->` 段与「单一事实源」表）
    stable symbol/对象: OpenWiki 段约束「scheduled workflow refreshes the repository wiki. Do not hand-edit generated OpenWiki pages unless explicitly asked; prefer updating source code/docs and letting OpenWiki regenerate」；单一事实源表把 `skills/_index.yml`（Active Skill 清单）、`agents/_index.yml`（Active Agent 清单）、`pipeline-templates/_index.yml`（Active Pipeline 清单）指定为权威
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: D-7 的「不手工编辑生成页 + 由生成器产出并核对」与 §4.4-2 的「active 索引为唯一事实源」一致性断言均建立在该文件的两条约束上。
19. repo: `tools`
    relative path: `.github/workflows/openwiki-update.yml`
    stable symbol/对象: `Install OpenWiki`（`openwiki@0.2.3` + provider/model 环境变量）与 `Run OpenWiki`（`openwiki code --update --print`）两步；`add-paths: openwiki, AGENTS.md, CLAUDE.md, .github/workflows/openwiki-update.yml`
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: 既有生成命令即本 CR OpenWiki 页面迁移的实施路径（D-7 第 2 步）；生成范围含 `openwiki/**`（FR-8 的目标页在内），本 CR 只取该范围内的生成结果，`zero_diff` 优先。
20. repo: `tools`
    relative path: `skills/_index.yml`、`agents/_index.yml`、`pipeline-templates/_index.yml`
    stable symbol/对象: 三个索引的 `status: active` 条目及其 `path` 字段（本 HEAD：Skill 56 / Agent 9 / Pipeline 8；Pipeline 索引的 path 带 `tools/` 前缀，派生时去前缀）
    commit SHA: `dddd0ad63fb79bd7608314b4553f30e8ce7b7289`
    依赖结论: §4.4-2 索引一致性断言的唯一事实源（本 HEAD 实测 active 条目 56 / 9 / 8，条目全部存在于磁盘）；索引解析出 0 条 active 必须硬失败（不静默降级），Pipeline 索引与目录枚举集合不相等也硬失败。
21. repo: `ai-first-platform-docs`
    relative path: `AGENTS.md`（「tools 包的挂载方式」段与「读取顺序」）
    stable symbol/对象: crctl 规范入口 `node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs …`（Tools Root = `workspace.tools_package_path`，无回退）；「状态推进一律走 crctl」约束
    commit SHA: `7110880af2606d5a923dc99a1f355ceb2db19bc6`（本次修订落盘时的 `ai-first-platform-docs` worktree HEAD）
    依赖结论: D-1 选择 `node` + `args[0]` = 脚本绝对路径的对外依据（裸 `crctl` 不在 PATH，KB 侧规范入口就是 node 形式）；即 `recovery.args[0]` 的形态在知识库侧已有权威约定，不是本 CR 自创。

**旧字段命中分布（按本节开头口径重跑，用于复核上列条目）**：

| repo | path | 行 | 次 | 处置 |
|---|---|---|---|---|
| `tools` | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 23 | 25 | 迁移（生产者 + 构造器宿主） |
| `tools` | `skills/shared/crctl/scripts/crctl.mjs` | 6 | 10 | 迁移（投影 + 错误面） |
| `tools` | `skills/shared/crctl/scripts/test/crctl.test.mjs` | 11 | 13 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/register-tx.test.mjs` | 4 | 4 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | 3 | 4 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/merge-tx.test.mjs` | 3 | 5 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs` | 2 | 2 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | 2 | 4 | 迁移（测试） |
| `tools` | `skills/shared/crctl/scripts/test/workspace-freshness.test.mjs` | 1 | 1 | 迁移（测试） |
| `tools` | `skills/cr/cr-archive/SKILL.md` | 6 | 7 | 迁移（提示词） |
| `tools` | `skills/sync/push-progress/SKILL.md` | 2 | 3 | 迁移（提示词） |
| `tools` | `skills/writeback/merge-feature-branch/SKILL.md` | 1 | 1 | 迁移（提示词） |
| `tools` | `skills/shared/crctl/SKILL.md` | 2 | 2 | 迁移（提示词 + 新增消费合同） |
| `tools` | `README.md` | 1 | 1 | 迁移（文档，原位） |
| `tools` | `openwiki/operations/crctl-transactions.md` | 3 | 3 | 生成物：由生成器重新生成并核对（D-7） |
| `tools` | `skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml` | 2 | 2 | 排除（历史 traceability 精确路径，§4.4-3） |
| `multica` | `cr-prompts-revised/delivery-agent.md` | 2 | 2 | 迁移（提示词，owner 可复制版） |
| `multica` | `server/internal/governance/testdata/traceability-golden.yml` | 2 | 2 | 排除（历史黄金数据） |
| `multica` | `server/internal/governance/testdata/traceability-golden.json` | 2 | 2 | 排除（历史黄金数据） |

**待核实依赖**：无（上列各项均已按 repo / path / stable symbol / 结论在对应资源 HEAD 上核对；行数与匹配次数按本节开头的唯一口径重跑）。历史黄金数据 `multica/server/internal/governance/testdata/traceability-golden.{json,yml}` 与 `tools/skills/shared/crctl/scripts/test/fixtures/traceability-191k.yml` 属历史证据，按 FR-11 排除范围处理，不计入依赖。

## CR-P3：评审 PASS 发布与 checkpoint 委派收敛 — 阶段终点发布点前移、审批后 checkpoint 节点退役、归档后本地 trunk 同步（v0.39 · CR-2026-066）

## 1. 架构概览

### 1.1 设计目标与不变量

本 CR 的技术设计只做一件事：**把「阶段终点发布」从 pipeline 节点移进评审 Skill 的 PASS 分支，并删掉由此失去存在理由的节点与冗余发布点**；同时让归档自己把本地主 checkout 对齐 origin。设计遵守 PRD §1.3.3 与 NFR-4 的零新增面，落成四条设计不变量：

| # | 设计不变量 | 判据落点 |
|---|---|---|
| I1 | **发布只发生在三个被授权的位置**：① 评审 run 内（FR-1）；② 已排定的下一阶段委派**内**（同一 run）；③ `recovery` 指定的同 run 重跑。除此之外任何位置不得出现 `push-progress`/checkpoint | FR-6 / FR-7 / AC-6 |
| I2 | **全仓 `git add -A` 之前，必须先证明启动工作区是干净的**——发布者（评审者）在跑 `push-progress` 前复核全部 resources `healthy`（`healthy` ⇒ `dirty=false`，更强前置：还要求 worktree 已注册且 HEAD 在 CR 分支上，与 §4.2 同口径），不干净则不发布、不代提交 | FR-2 / FR-1 第 1 条 / AC-3 |
| I3 | **发布的必须是被评审的**——发布后用只读取证把「发布批次」绑定到「评审对象」；不成立即 `CONTRACT_DRIFT` 技术中止，不改 verdict、不改状态 | FR-3 / AC-3 |
| I4 | **归档是终态事务，其尾部 trunk 同步必须是 best-effort**：只 ff-only、永不破坏本地在途修改、逐仓失败只反映在返回行、不新增错误码、不改退出码 | FR-10 / AC-8 |

分层与依赖方向不变（`ARCHITECTURE.md` §4：Pipeline → Skill → crctl，依赖只朝下）。本 CR 不新增层级、不新增命令面、不新增账本文件。

### 1.2 变更面鸟瞰

三仓、29 个交付文件（tools 25 + multica 4；`sdd.md` 本身是本文档、不计入）。

```text
../tools（25）
  pipeline-templates/  requirement-authoring.pipeline.json      ← 删 2 节点 + 1 输入
                       architecture-design.pipeline.json       ← 删 1 节点
                       code-implementation.pipeline.json       ← 删 4 节点 + 1 输入 + replayNodes 1 项 + 1 句提示
                       _index.yml                              ← nodes 计数与 brief（3 条）
  skills/requirement/review-requirement/SKILL.md               ┐
  skills/develop/review-tech-design/SKILL.md                   │ 四个 review SKILL：
  skills/develop/review-dev-plan/SKILL.md                      │  + Step 1 clean 前置（FR-2）
  skills/develop/review-code/SKILL.md                          ┘  + PASS 分支发布与对账（FR-1/FR-3）
  skills/sync/push-progress/SKILL.md                           ← FR-09 口径重写
  agent-skill-matrix.yml ＋ AGENT-SKILL-MATRIX.md              ← reviewer 权限面（FR-8，三处载体之二）
  agents/dev-agent.md ＋ quality-reviewer-agent.md ＋ delivery-agent.md
                                                               ← 搭车硬规则 + 发布职责（FR-7）
  skills/shared/crctl/scripts/lib/workspace-transactions.mjs   ← archiveCr 返回 localTrunkSync（FR-10）
  skills/cr/cr-archive/SKILL.md                                ← 结果分类/输出块（FR-10.8）
  skills/writeback/merge-feature-branch/SKILL.md               ← publication lag 搭车语义（FR-6）
  README.md ＋ openwiki/pipelines/overview.md ＋ dir-graph.yaml ← FR-09 同一口径
  skills/shared/crctl/scripts/test/pipeline-structure.test.mjs ← AC-1/AC-2/AC-4 断言
  skills/shared/crctl/scripts/test/archive-tx.test.mjs         ← AC-8 用例
  skills/shared/crctl/scripts/test/contract-scan.test.mjs      ← AC-3/AC-4③ ＋ FR-7 静态文本断言
  skills/shared/crctl/scripts/test/crctl.test.mjs              ← 既有断言同步（node 删除连带，见 §6.4）
  skills/shared/crctl/scripts/test/checkpoint-tx.test.mjs      ← 既有断言同步（同上）

../multica（4，部署副本，owner 部署）
  cr-prompts-revised/{quality-reviewer-agent,dev-agent,delivery-agent,cr-coordinator-agent}.md
```

`../multica/cr-prompts-revised/agent-skill-matrix.yml` **不在改动面**（S-7 收口，见 D-6 与 §6.6）；`CUSTOM.md` 不改（#75 已定义该目录是 tools 的部署副本）；不改任何 Go/TS 代码、不改平台 DB、不改 `aifirst/agent-import.mjs`。

### 1.3 依赖方向与分层（不变）

```text
Pipeline（pipeline-templates/*.json）   编排 Skill 调用顺序
   ↓  （本 CR 后：pipeline 不再有「发布节点」这一形态）
Skill（review-* / push-progress / merge / cr-archive）  提示词合约
   ↓
crctl（crctl.mjs + lib/workspace-transactions.mjs）     状态与账本唯一写入执行器
```

三条对本设计的硬约束（来自 `ARCHITECTURE.md` §5 与 §4）：

- **状态单一写者**：评审者发布与归档 trunk 同步都**不得**写 CR status；本 CR 不新增任何状态写入口（评审者的发布动作只经 `push-progress` → `crctl checkpoint`，其状态守卫只检查「非终态」）。
- **账本单一写入通道**：`localTrunkSync` 只出现在 `archiveCr` 的**返回值**中，不落盘、不写 journal、不写账本（`reconcileLocalTrunks` 本身即零账本副作用）。
- **Skill 通用、约束归仓**：`reconcileLocalTrunks` 只处理 `dir-graph.yaml#repositories` 声明的主 checkout，不在 Skill 文本里硬编码任何仓库名或路径。

### 1.4 关键流程

#### 1.4.1 阶段终点发布点前移（FR-1/FR-2/FR-3）

```text
阶段 owner run（作者）                    评审 run（quality-reviewer-agent）
  register / write-*  ──┐                 ①FR-2 clean 前置：crctl workspace inspect
  （本地提交，不发布）   │                    └ 任一仓非 healthy → 不评审、不改任何账本
                        │                 ②既有评审动作（维度不变）
                        │                 ③crctl review-record → 提交 files[]
                        │                 ④该阶段既有 PASS advance（有则执行，见 §4.1）
                        │                 ⑤FR-1 发布前置：复查 resources 全 healthy
                        └─────────────────►⑥push-progress（message=<阶段>评审通过）
                                          ⑦FR-3 对账（发布批次 ≡ 评审对象）
                                          ⑧透传 phase/batchId/repositories/metadataCommit
```

人工审批（`crctl approve`）**不在发布路径上**：它是网络无关的本地账本事务（approval.yml + cr.md 同批提交）。审批提交由**下一阶段评审 PASS 的发布**带上远端；code 路径由 `merge` 的 publication preflight 同 run 兜底。

#### 1.4.2 搭车与兜底（FR-6）

```text
requirement 审批 ─┐
tech-design 审批 ─┼─► 本地提交（不上远端）─► 下一阶段评审 PASS 的 push-progress 一并带走
dev-start 审批  ──┘
code 审批 ───────► merge 首次 prepare 前 publication preflight：
                    远端 requirement/{cr} 缺失 → MERGE_SOURCE_MISSING
                    远端 requirement/{cr} 滞后 → RELEASE_REMOTE_NOT_PUSHED
                    两者都携 recovery = checkpoint argv（crctl checkpoint {cr} --workspace …）
                    → writeback run 就地执行 recovery 一次 → 同一 run 内重跑 merge
```

#### 1.4.3 归档尾部 trunk 同步（FR-10）

```text
crctl archive（终态事务，既有语义不变）
  … 四账本编辑 → commit → lease push → outbox → cleanup …
  └─► reconcileLocalTrunks(ctx)  ← 新增唯一调用点（既有函数、既有分类）
       每仓：symbolic-ref 判分支 → status 判 dirty → fetch --prune → ff-only
       返回行 { repo, trunk, before, remote, after, status, reason }
  └─► archive 返回值新增 localTrunkSync（与 recovery 同级）
```

### 1.5 与 PRD §1.5 五条裁定的承接

| PRD §1.5 | SDD 落点 |
|---|---|
| 第 1 条：FR-10 按实测 **6 个 reason**（含 `failed(trunk-unavailable)`） | §2.3 分类表、§4.6、AC-8② |
| 第 2 条：删除后 `ref=push-progress` 计数为 0（两条判据） | §4.4、AC-1 |
| 第 3 条：评审者走 `push-progress` Skill，`checkpoint` 仍留 `forbidden` | §3.3、D-3、AC-4①③ |
| 第 4 条：§1.1 的 6 次/3 次数字不进入验收面 | 本 SDD 全篇不引用该数字作为判据 |
| 第 5 条：**只读** `workspace inspect` 写入 reviewer 允许面（B-1） | §3.3、§4.2、AC-4②③、SDD-CLOSE-03 |

## 2. 数据模型

### 2.1 无新增实体、字段与账本（NFR-4 落点）

本 CR **不新增** pipeline 节点、评审维度、账本字段、观测指标、crctl 子命令、错误码、Skill 参数、落盘文件。因此第 2 节不定义新实体，只固定「既有结构在本 CR 中的精确形状」——这是实现唯一性的来源。

### 2.2 既有结构引用（只读，逐字沿用）

**(a) checkpoint 批次返回结构**（`push-progress` 的消费面，FR-1 第 3 条）

| 字段 | 形状 | 语义（本 CR 的对账依赖） |
|---|---|---|
| `phase` | `complete` \| 中间态 | 只有 `complete` 可进入对账 |
| `changed` | bool | `false` = 幂等重放（无新 commit），视为成功 |
| `batchId` | string | 批次 ID（写 `_backlog.yml#latest-checkpoint.batch-id`） |
| `repositories[]` | `{repo, sourceSha, remoteRef, confirmed}` | **KB 仓 `sourceSha` = metadata commit 的直接父**；非 KB 仓 `sourceSha` = 该仓 CR worktree HEAD = 远端分支 HEAD |
| `metadataCommit` | string | KB 仓的批次可见点（`_backlog.yml` latest-checkpoint 提交），= 发布后 KB worktree HEAD |

**(b) `localTrunkSync` 行结构**（FR-10.2/3，逐字沿用 merge 既有形状）

```text
{ repo: <dir-graph repository id>, trunk: <trunk 名>, before: <sha|null>, remote: <sha|null>, after: <sha|null>, status: null|unchanged|synced|skipped|failed, reason: null|wrong-branch|dirty|diverged|fetch-failed|trunk-unavailable|ff-only-failed }
```

**(c) `release-subjects`**（code 阶段对账的事实源，既有、不新增字段）

```text
{ version: 1,
  repositories: [{ repo, remote-ref, reviewed-source-sha }],   # = review-record --stage code 时刻各仓 CR worktree HEAD
  artifacts: { algorithm: sha256, canonicalization: crlf-to-lf+path-sort,
               files: [{ path, sha256 }],                       # prd.md/sdd.md/plan.md/tasks/_index.yml/TASK-*.md
               digest: sha256(files.map(f => `${path}:${sha256}`).join('\n')) } }
```

### 2.3 状态与门禁（不新增状态、不新增转换）

- 状态机口径不动（15 具名状态 + 注册前 `(new)`；28 条声明 / wildcard 展开 50 条，CR-2026-027 口径）。
- 本 CR 引用的四个「发布点状态」全部是**既有非终态**（`tech-design-review-pending` / `task-breakdown` / `code-reviewing` / `requirement-reviewing`），`crctl checkpoint` 的状态守卫只拒绝终态（`ILLEGAL_LEDGER_STATE`），故评审 PASS 时发布**不需要新增任何状态或转换**。
- `statusGates` 与 `gates.json` 零改动；`review-code.reviewLoop.replayNodes` 删除一项是本 CR 唯一触碰 `reviewLoop` 语义面的地方（PRD §7 已登记的例外）。

## 3. 接口契约

### 3.1 Skill 契约：四个 review SKILL（调用面与落盘面不变）

| 维度 | 现状 | 本 CR 后 |
|---|---|---|
| 参数 | 各 Skill 既有参数集 | **不变**（不新增参数；发布只用既有 `cr_id` + `message`） |
| 落盘 | `review-annotations/{requirement,sdd,dev-plan,code}.yml` + `review-loop.yml` + `traceability.yml` | **不变** |
| 状态转换 | 各 Skill 既有 `advance`（requirement/code 有，tech-design/dev-plan 无） | **不变**（新增发布步骤**不新增**任何 `advance`） |
| 新增动作 | — | Step 1 起始的只读 `crctl workspace inspect` 前置；PASS 分支内一次 `push-progress` + 一次对账 |

**PASS 发布步骤的合同（四个 SKILL 文本一致，逐字口径）**：

1. 触发顺序固定：`review-record` 成功落盘 → 按 `files[]` 提交（既有纪律）→ 该阶段既有 PASS `advance`（若该 Skill 有）→ 复查发布前工作区干净 → `push-progress`。
2. 发布调用：`push-progress`，`message = <阶段>评审通过`（`需求评审通过` / `技术设计评审通过` / `开发计划评审通过` / `代码评审通过`）。
3. 结果透传：`phase` / `batchId` / `repositories[]` / `metadataCommit` 逐字进入评审报告；`phase=complete ∧ changed=false` 视为成功。
4. BLOCK 分支：**不含**发布调用（回修中间态不上远端）。
5. 失败语义：verdict 与评审账本保持已落盘结果不变；不重评、不改 verdict、不代提交、不回退状态；报告原始错误码与 `recovery`，按 `recovery` 重试**同一个** `push-progress`；发布失败不阻塞任何本地门禁。

### 3.2 crctl CLI 契约：`archive` 返回新增 `localTrunkSync`

| 项 | 契约 |
|---|---|
| 新增字段 | `localTrunkSync`（与 `recovery` 同级），类型 = 上述行数组 |
| 既有字段 | `commit` / `lastCleanupError` / `remaining` / `preservedRefs` / `recovery` / `warnings` **逐字不变** |
| `phase` 分类 | `complete` / `cleanup-pending` **不变**；三个成功返回点（幂等重放早退 / `complete` / `cleanup-pending`）都带 `localTrunkSync` |
| 退出码 | **不变**（trunk 同步失败不改变退出码） |
| 错误码 | **不新增**（`fetch-failed` / `trunk-unavailable` / `ff-only-failed` 只出现在返回行的 `reason`） |
| 幂等重放 | `changed=false` 的 complete 重放路径同样返回 `localTrunkSync`（按当次实况），不产生新 commit；三个成功返回点（幂等重放早退 / `complete` / `cleanup-pending`）都带该字段 |

确定性四查：**幂等** = 重放按当次实况返回、零新 commit；**权限** = 只读 `git status/symbolic-ref` + best-effort `fetch`/`merge --ff-only`，不写账本、不动别的仓；**错误闭包** = 无新增错误码、退出码不变；**副作用** = 仅 `fetch --prune origin` 与 `merge --ff-only`（受控 `gitMust`，局部捕获）。

### 3.3 权限契约（FR-8 + B-1）

| Actor | 变更 | 约束 |
|---|---|---|
| `quality-reviewer-agent` | `forbidden` 移除 `push-progress`；`can-call` 增加 `push-progress` | 只在对应 review SKILL 的 PASS 分支内发布一次；不修改业务文件、不推进状态、不改 verdict |
| `quality-reviewer-agent` | crctl 允许面新增**只读** `workspace inspect` | 不新增子命令/错误码/写入面；`checkpoint` **仍留在** `forbidden` |

**允许面的四处载体（缺一即交付缺陷）**与断言落点：

| # | 载体文件 | 需出现的内容 | 位置（稳定节名） | 断言落点 |
|---|---|---|---|---|
| ① | `../tools/agent-skill-matrix.yml` | `quality-reviewer-agent` 块注释含只读 `workspace inspect` | 第 192–194 行的块注释（`can-call` 之下、`forbidden` 之上） | 断言 A（tools CI 可执行） |
| ② | `../tools/AGENT-SKILL-MATRIX.md` | 「本 CR 权限变更」节新增一行，**行内带 `CR-2026-066`** | 节名 `## 本 CR 权限变更`（L46），表格追加行（既有行为 L52，属既有 CR，不得混同） | 断言 A |
| ③a | `../tools/agents/quality-reviewer-agent.md` | 「权限事实源」节给出同一允许面声明（含 `workspace inspect`） | 节名 `## 权限事实源`（L35–L38） | 断言 A |
| ③b | `../multica/cr-prompts-revised/quality-reviewer-agent.md` | 「受限 crctl 权限」穷尽式白名单**新增只读 `workspace inspect`**；禁止面枚举保持含 `checkpoint` | 节名 `## 受限 crctl 权限`（L35–L46；允许面条目 L39–L42，禁止面枚举 L46） | 断言 B（交付证据，见 D-5） |

**部署时序**：平台 DB 与 Prompt 投影由 owner 在部署窗口执行；部署前 Multica 侧实际运行的仍是旧白名单（`workspace inspect` 未被列出）。本 CR 的机械断言只约束**仓库内文本**，不约束部署状态；部署动作不在本 CR 范围（PRD §1.3.2）。

### 3.4 错误语义

| 名称 | 归属 | 语义 | 本 CR 是否新增 |
|---|---|---|---|
| `CONTRACT_DRIFT` | **评审侧技术中止**（SKILL 文本定义，不是 crctl 错误码） | FR-3 对账不等：报告「期望值 vs 实际值」两侧原始 SHA 与复算内容来源；**不追加／不改写 annotation、不改 verdict、不回退状态（不改 status）、不重评**——review-record 已按 §4.1 步骤 ① 落盘，本中止发生在步骤 ⑥，只中止后续动作、不改写已落盘结果 | 新增**文本语义**，不新增 crctl 错误码 |
| `CHECKPOINT_SENSITIVE_PATH` / `CHECKPOINT_REMOTE_ADVANCED` / `CHECKPOINT_REMOTE_DIVERGED` / `CHECKPOINT_REMOTE_HISTORY_REWRITTEN` / `TX_*` | crctl 既有 | 评审发布失败时按 `recovery` 重试同一 `push-progress` | 否 |
| `MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` | crctl 既有 | publication lag；`recovery` = checkpoint argv；writeback 同 run 内执行 recovery 一次后重跑 merge | 否（只补 Skill 文本口径） |
| `ARCHIVE_*` | crctl 既有 | 归档前置/状态错误；本 CR 不新增、不改变 | 否 |

### 3.5 前端/HTTP 契约

N/A——本 CR 无 HTTP/REST 接口新增或修改（无 API 定义文件参与 diff）。按 `review-tech-design` 的条件基线（FR-08.2）本维度不适用。

## 4. 关键算法与流程

### 4.1 评审 PASS 发布序列（FR-1，四 SKILL 同构）

```text
publish_after_review_pass(stage):
  1  落盘：crctl review-record {cr} --stage {stage} [--bump-attempt]      # 既有步骤
  2  提交：git 提交 review-record 返回的 files[]                            # 既有纪律（评审者只提交账本文件）
  3  PASS 既有动作（按 stage 分派，逐字沿用现状）：
       requirement → crctl advance --to requirement-reviewing --trigger review-requirement
       code        → crctl advance --to code-reviewing --trigger review-code --expect developing
       tech-design → 无（保持 tech-design-review-pending）
       dev-plan    → 无（保持 task-breakdown）
  4  发布前置（等价于 FR-1 第 1 条的「工作树干净」判据）：
       r = crctl workspace inspect {cr}
       require ∀ resources: classification == healthy   # 零写入只读；dirty 即 abort，不发布
  5  发布：push-progress(cr_id={cr}, message="{stage}评审通过")
       require phase == complete                         # changed=false 亦成功
  6  对账：verify_release_batch(stage, r)                # §4.3；不等 → CONTRACT_DRIFT 中止
  7  报告：透传 phase / batchId / repositories[] / metadataCommit + 对账结论
```

设计要点：

- **步骤 4 复用 FR-2 的同一条只读判据**（`crctl workspace inspect` ⇔ 内部 `git status --porcelain` 的零写入封装），不使用裸 `git status`：这既满足 FR-1 第 1 条的「工作树干净」判据，又保持评审者的能力面不扩张（`workspace inspect` 正是 FR-8 已授权的只读子命令）。
- **步骤 3 的 stage 分派按事实源推导**：tech-design / dev-plan 的 PASS 分支**没有** `advance`（`review-tech-design` PASS 保持 `tech-design-review-pending`；`review-dev-plan` PASS 保持 `task-breakdown`），因此实现**不得**为「顺序」而给这两个 Skill 新造 `advance`（那会新增状态转换，违反 NFR-4）。SKILL 文本按 stage 写各自的 PASS 分支，不共用一个含 `advance` 的模板。
- **步骤 5 失败时步骤 1/2/3 的成果已落盘且不回退**（FR-1 第 5 条）：发布失败不触发第二次评审、不消耗 attempt。

### 4.2 FR-2 评审前置干净检查（四 SKILL Step 1 起始）

```text
pre_check(cr):
  r = crctl workspace inspect {cr}                       # 只读，零写入
  dirty_repos = [x ∈ r.resources : x.classification != "healthy"]     # healthy ⇒ dirty=false（更强前置：还要求 worktree 已注册且 HEAD 在 CR 分支）
  if dirty_repos ≠ ∅:
      报告（含逐仓 classification/dirty 事实与该仓未提交文件清单）
      给出「存在未提交内容，请作者先提交」
      → 不写临时 payload、不 review-record、不 advance、不改 status、不发布
      → 评审者不得对作者工作区做 git add / commit / stash / 清理
  else: 继续既有 Step（review-requirement 的 Step 1.5 pre-review 门禁顺位不变，仍在其后）
```

- 位置钉定：四个 SKILL 的 **Step 1 起始处**（`review-requirement` 的 Step 1.5 是其后的独立步骤，本前置不得插到 Step 1.5 之后）。
- 该前置**不新增** crctl 子命令、不新增错误码；输出复用既有 `workspace inspect` JSON 字段（`resources[].classification` / `dirty` / `worktreePath`）。`classification=healthy` **严格强于** `dirty=false`（`classifyRepoWorkspace` 还要求 worktree 已注册且 HEAD 在 `requirement/{cr}` 分支上，见 §6.3），故判据取 `classification`，不得写成二者等价——写反会漏掉 wrong-branch / path-unregistered 两类不干净工作区。
- **两侧必须同时存在**（B-1）：SKILL 文本含 `crctl workspace inspect` 前置 ∧ 四处载体含该允许面；缺任一侧由 AC-4 断言变红。

### 4.3 FR-3 发布与评审对象对账（`verify_release_batch`）

#### 4.3.1 取证链（先把「发布批次」绑定到「当前提交」）

`push-progress` 以 `git add -A` 提交、并以 lease push 到 `refs/heads/requirement/{cr}`，其批次事实由 checkpoint 合同确定。**KB 仓与非 KB 仓的绑定关系不同**（这是本设计的核心技术判断，见 D-4）：

| 仓类别 | checkpoint 保证（契约级） | 取证命令（受控只读） |
|---|---|---|
| **非 KB**（`../tools`、`../multica`） | `repositories[].sourceSha` = 该仓 CR worktree HEAD = 远端分支 HEAD（dirty 时 checkpoint 自己 commit，随后三方相等） | `crctl git rev-parse HEAD --cwd <resources[].worktreePath>` |
| **KB**（`ai-first-platform-docs`） | `repositories[].sourceSha` = **metadata commit 的直接父**（checkpoint 内部断言 `parent !== kbSourceSha → CHECKPOINT_SNAPSHOT_INVALID`）；metadata commit 的 staged set **恰为** `change-requests/_backlog.yml` 一项（否则 `CHECKPOINT_SNAPSHOT_INVALID`）；发布后 KB worktree HEAD = `metadataCommit` | `crctl git rev-parse HEAD` → 必须 = `metadataCommit`；`crctl git rev-parse --verify HEAD^` → 必须 = KB `sourceSha`；两边相等 ∧ `dirty=false` ⇒ KB 工作区中**除 `_backlog.yml` 外**的每个文件与 `sourceSha` 逐字节相同 |

因此：**KB 工作区里的 `prd.md` / `sdd.md` / `plan.md` / `tasks/**` 就是 `sourceSha` 的内容**（它们不是 metadata commit 触碰的唯一路径），可在其上复算哈希；非 KB 仓直接比 HEAD。

**禁止**：在两个 SHA 关系不成立时用工作区文件复算（等于用 `subject-sha256` 自证，对账失去意义）——此时按 `CONTRACT_DRIFT` 中止并报两侧 SHA。`git show` **不得**作为取证手段（`rules.json` 的 `show` 只向 `system-orchestrator` 放行 `review-annotations/*`，shape 不含业务文件）；`rev-parse` / `diff` / `log` 等只读命令可用。

#### 4.3.2 逐阶段对账判据

| stage | 评审对象事实（既有） | 对账判据 |
|---|---|---|
| requirement | `review-annotations/requirement.yml#subject-sha256` | KB `sourceSha` 内容上的 `prd.md` **LF-only sha256** 全等 |
| tech-design | `review-annotations/sdd.yml#subject-sha256` | KB `sourceSha` 内容上的 `sdd.md` LF-only sha256 全等 |
| dev-plan | `review-annotations/dev-plan.yml#subject-sha256`（composite） | plan.md + 全部 `TASK-*.md` 的 composite digest 同口径复算全等（集合、路径、排序、`path:sha256` 行序逐字一致） |
| code | `review-annotations/code.yml#release-subjects` | ① 非 KB 仓：`repositories[].sourceSha` 与 `reviewed-source-sha` **逐仓全等**（仓名一一对应）；② KB 仓：`reviewed-source-sha` 是当前 KB HEAD 的祖先 **且** 受控 artifact 逐文件 sha256 与文件集合、`artifacts.digest` 全等（= 既有 `verifyReleaseSubjects` 的 KB 语义：白名单外路径零漂移） |

- KB 仓不适用「逐仓 SHA 全等」的原因（**落点事实**）：code 阶段发布时，KB 仓必然比 `reviewed-source-sha` 多出评审记录/状态提交（`review-annotations/code.yml`、`review-loop.yml`、`traceability.yml`、`cr.md`、`_backlog.yml`），HEAD 前移是**设计使然**；既有 `approve-code`/`merge`/`writeback` 的复核同样是「KB 按受控 artifact + 祖先关系、非 KB 按 HEAD 全等」。SDD 采用同一语义，不新增判据。
- 复算遵循行尾纪律：读入先 `\r\n → \n`；跨行/逐行解析失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」。
- 判定不等 → `CONTRACT_DRIFT` 技术中止：**不改 verdict**、不重评、不回退状态；报告含期望值/实际值与复算内容来源。
- **不新增**账本字段、注解字段、哈希算法（沿用 `subject-sha256` / composite / `release-subjects` 三套既有事实源）。

### 4.4 FR-4 / FR-5 节点退役与连带面

#### 4.4.1 删除对象（对象级删除，不是开关）

| pipeline | 删除节点（id 后缀） | 同步删除 |
|---|---|---|
| requirement-authoring | `…0003`（PRD 草稿可选 checkpoint）、`…0007`（审批后强制 checkpoint） | 输入 `auto_push_after_prd` |
| architecture-design | `…0005`（审批后强制 checkpoint） | — |
| code-implementation | `…0003`（TASK 可选 checkpoint）、`…0008`（统一 checkpoint）、`…0012`（审批后强制 checkpoint）、`…0015`（评审后审批前 checkpoint） | 输入 `auto_push_after_task`；`review-code.reviewLoop.replayNodes` 的 `…0008` 项（5→4）；`…0010.approvalPrompt` 的「且评审后 checkpoint `phase=complete`」前提句 |

节点数 requirement **7→5**、architecture **5→4**、code **16→12**；删除后三份 JSON 中 `ref=push-progress` 的节点对象计数 = **0**。不新增替代节点、不重编号其它节点 id（`id` 不回收不复用）、不删 `workspace-freshness`（`…0016`/`…0017`）与 `code_generation` 节点。

#### 4.4.2 连带面清单（同一份 diff 内闭合）

1. `pipeline-templates/_index.yml`：三条 `nodes:` 计数改为 5 / 4 / 12；三条 `brief` 不再描述已删节点（新增一句「阶段终点发布发生在评审 PASS 的 review SKILL 内」）。
2. 删除节点的 prompt 中「阶段终点完成条件（CR-2026-044 FR-07）」与 `{{inputs.auto_push_*}}` 字面量随对象一并消失；**其余节点 prompt 不得残留** `auto_push_after_*` / `SKIPPED` 字面量。
3. **`node-N.md` 输出文件名：本 CR 不改名**。判定依据（事实观察）：`node-N.md` 的 N 取**节点 id 末段**而非位置序号——判别性证据是 code `…0016`（位置下标 6）写 `node-16.md`、`…0017`（下标 10）写 `node-17.md`、`…0009`（下标 11）写 `node-9.md`、`…0011`（下标 14）写 `node-11.md`；requirement/architecture 两份因 id 后缀与位置序恰好一致而不具判别力。既然 N 不依赖位置，删除节点**不改变任何既有名字**；`…0014`（review-dev-plan）写 `node-3.md` 属本 CR 之前已存在的命名不一致，登记为 `follow_up`（不扩大本 CR diff）。
4. **悬空引用核查（零命中）**：逐节点扫描 `node-\d+\.md` 后确认**没有任何存活节点读取已删节点的输出文件**——删掉的 `…0007`/`…0008`/`…0012`/`…0015` 与其 requirement 侧对应节点的输出名（`node-7.md`/`node-8.md`/`node-12.md`）只出现在**它们自身**的 prompt 里；`node-3.md` 另出现在 code `…0014` 的 prompt 中，但那是它**自己的输出文件名**（该 prompt 实际读取的是 `node-1.md` 与 `node-2.md` 两个存活节点），不构成引用；`…0009`（review-code）只读 `node-1.md`/`node-9.md`，与 `…0008` 的输出无关。删除 `…0003` 后 `…0014` 成为 `node-3.md` 的唯一写入者（此前的撞名随删除消失）。
5. **`node-N.md` 无任何运行时/生成器解析**：multica `server/internal/governance/**` 对 `node-\d+\.md` 零命中（`grep`），tools 侧唯一相关断言是 `pipeline-structure.test.mjs:229`（architecture 后续节点不得依赖 `node-1.md`）——本 CR 保持满足。
6. **既有测试面的连带改写**：见 §6.4（`pipeline-structure`、`contract-scan`、`crctl`、`checkpoint-tx` 四个文件；不改 `gate-registry.json`，`manifest.cases` 是下界、新增用例不需要改登记面）。

### 4.5 FR-6 搭车（同 run 内兜底，不得单开委派）

- **code 路径**：`merge` 的 publication preflight 语义不变；Skill 文本新增「写回 run 收到 `MERGE_SOURCE_MISSING`/`RELEASE_REMOTE_NOT_PUSHED` 时就地执行 `error.recovery`（结构化 argv，`shell:false`）**一次**，然后在**同一 run 内重跑 merge**；不得转成新委派/新 task」。
- **requirement / tech-design / dev-start 路径**：审批提交由下一阶段评审 PASS 的发布带上远端——这是设计取舍：审批是网络无关的本地账本事务，审批提交在下一阶段评审前只在本地，**换机恢复需重签一次**；交付说明必须明示该取舍。
- **禁止面**（写入四份 Agent 合同与 coordinator 副本）：checkpoint 只允许出现在 §1.1 I1 的三处；「为单个 `push-progress`/checkpoint 单独开 task/委派」次数 = 0（AC-6 观察项 ④）。
- 该硬规则**不新增**委派 lint 规则；由 `contract-scan.test.mjs` 面内一条同风格静态文本断言兜底（tools 三份 Prompt 均含硬规则文本）。
- `delivery-agent` 增量文本必须写明：① `recovery` argv 属于**被授权的同 run 重跑**，不受「不裸调 crctl 原语」约束；② 该例外**不**赋予独立发起 checkpoint 的权力。

### 4.6 FR-10 `archiveCr` 尾部 trunk 同步

#### 4.6.1 算法（最小侵入）

```text
archiveCr(ctx, input):
  …（既有事务主体：证据门 → journal → 四账本编辑 → commit → lease push → outbox → cleanup；一行不改）…
  + 局部包装（不导出、不新建模块，紧邻既有 result(...) 定义）：
      const resultWithTrunkSync = (phase, changed, warnings, outbox)
        => result(phase, changed, warnings, outbox, reconcileLocalTrunks(ctx));
  + 三个成功返回点改经该包装：① phase===complete 的幂等重放早退；② 末尾 phase=complete；③ 末尾 phase=cleanup-pending
```

- 调用点时序：**归档 push 与 cleanup 之后**计算（终态已发布，trunk 事实稳定）；幂等重放路径单独计算（不复用上次结果，符合 FR-10.7「按当次实况返回」）。
- 复用既有 `reconcileLocalTrunks(ctx)`：**不新写同步算法、不改其内部判据与分类**（唯一新增的是调用点与返回字段）。
- 返回值：`result()` 结果对象新增 `localTrunkSync` 字段（与 `recovery` 同级），其余字段逐字不变。
- 失败不阻断：`reconcileLocalTrunks` 全程 best-effort（自身已对 `fetch`/`merge --ff-only` 局部捕获、不抛错），因此归档退出码与 `phase` 分类不受影响；逐仓失败只反映在行内 `status/reason`。
- dirty 策略：主 checkout dirty ⇒ `skipped` + `reason=dirty`，**零改动**本地在途修改；报告给出逐条 `reason` 与人类可执行的补救说明（`fetch --prune origin` + `merge --ff-only origin/{trunk}`）。
- 只处理 `dir-graph.yaml#repositories` 的**主 checkout**；永不 `reset`/`clean`/`stash`/强推。

#### 4.6.2 返回面与文档同步

- `skills/cr/cr-archive/SKILL.md`：Step 3 结果分类表与「输出」块新增 `localTrunkSync`（含 4 状态 × 6 reason 的分类说明与补救指引）；`recovery` 语义与字段名不变。
- delivery-agent 的最终交付汇报面包含该字段（`localTrunkSync` 行摘要 + 未同步仓的补救说明）。

#### 4.6.3 拆分判定（承接 PRD FR-10.9）

**不拆**。见 SDD-CLOSE-01（尺寸判据与结论）。

### 4.7 FR-7 搭车硬规则的文本落点

| 仓 | 文件 | 修订 |
|---|---|---|
| `../tools` | `agents/quality-reviewer-agent.md` | 新增「评审 PASS 后发布」职责（FR-1 的 Skill 动作由本 Agent 执行）+ 搭车规则；「权限事实源」节给出同一允许面声明 |
| `../tools` | `agents/dev-agent.md` | 原位改写「先有代码、测试报告和统一 checkpoint 再由 reviewer 评审」与「checkpoint 未完成不进入后续人工审批」两句为「评审 PASS 即发布」口径 + 搭车规则 |
| `../tools` | `agents/delivery-agent.md` | 新增搭车规则（publication lag 同 run 局部处理；recovery 例外的双向边界） |
| `../multica` | `cr-prompts-revised/{quality-reviewer-agent,dev-agent,delivery-agent,cr-coordinator-agent}.md` | 同步上述文本；`cr-coordinator-agent` 新增「不得为 checkpoint 单开委派」显式禁止 |

硬规则文本（三份 tools Prompt 与四份 multica 副本同句；tools 侧 `agents/` 无 `cr-coordinator-agent.md`，该副本只在 multica，见 §6.3）：

> 跨人工 gate 的第一份委派必须显式携带上一阶段尚未闭合的发布动作（在同一 run 内执行、只回报结果）；禁止为单个 `push-progress` / checkpoint 节点单独开委派。

同批原位改写的事实句（`../multica/cr-prompts-revised/quality-reviewer-agent.md` L54 现有「本 Agent 不负责 push/checkpoint，后续发布由 Pipeline 中对应的同步节点完成」与本 CR FR-1 直接冲突，必须改写为「评审 PASS 后由本 Agent 发布，经 `push-progress` Skill；不直接调用 `crctl checkpoint`」）。

## 5. 技术选型与替代方案

以下六项同时满足决策记录三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代），故记录；其余实现细节不记录。

### D-1 发布点前移到评审 PASS，审批后不设 checkpoint 节点

- **Decision**：阶段终点发布由评审者在 PASS 分支执行（每阶段恰好一次）；审批后无节点，审批提交搭车（下一阶段评审发布 / `merge` publication preflight 同 run 兜底）。
- **Context**：门后节点在 agent 驱动模式下没有强制力（无 runtime 检查、`abort` 只是纸面强度），而跨 gate 必须重新唤醒；冗余发布点使「实现→评审→审批」窗口出现两次 checkpoint。
- **Alternatives**：① 保留门后 checkpoint 并接受单飞委派（被 CR-2026-063/064 的事实否证）；② 引入平台执行层做 approval-continuation（PRD §7 排除：tools 包不只在 Multica 使用，不接受平台耦合）；③ 仅删除冗余节点、保留门后节点（未消除根因）。
- **Consequences**：+ 阶段终点=评审 PASS 的 checkpoint，远端批次与 verdict 同源；− 实现→评审窗口不再有中途恢复点（取舍一）；− 审批提交在下一阶段评审前只在本地，换机需重签一次（取舍二）；回滚边界 = FR-1~FR-3 与 FR-4~FR-5 可分别回退。

### D-2 归档 trunk 同步复用 `reconcileLocalTrunks`，且失败不阻断归档

- **Decision**：`archiveCr` 复用 merge 既有函数与分类，只在返回值新增 `localTrunkSync`；best-effort、永不破坏本地。
- **Context**：归档是 CR 最后一个动作，此后无任何节点对齐主 checkout；而 merge 已经验证过同一函数（唯一既有调用点）。
- **Alternatives**：① 归档前要求主 checkout clean 否则拒绝归档（把可选收益变成硬前置，会让 dirty 主 checkout 卡死终态事务）；② 归档失败即中止（`crctl archive` 已是终态权威发布 + 资源清理两段语义，加硬失败会污染 `phase` 分类）；③ 新写一套 trunk 同步算法（违反零新增与单一算法源）。
- **Consequences**：+ 零新算法、零新错误码、退出码不变；+ dirty 如实报告不静默；− trunk 同步失败不阻断归档（与「只是便利设施」的定性一致，由报告面暴露）。

### D-3 评审者只放开 `push-progress` Skill，不放开 `crctl checkpoint` 原语

- **Decision**：`can-call` 增加 `push-progress`，`checkpoint` 留在 `forbidden`。
- **Context**：`push-progress` 是「一次调用 + 结果解释」的能力面；`crctl checkpoint` 是深原语，包含跨仓 Git 序列与 journal 语义。
- **Alternatives**：① 放开 `checkpoint`（评审者获得跨仓写序列能力，超出「发布自己刚评审的批次」所需）；② 让 `system-orchestrator` 发布（跨 gate 仍需唤醒，回到单飞问题）。
- **Consequences**：发布能力最小化；评审者的能力面仍收敛在「读 + 一次 Skill 调用 + 一次账本落盘 + 既有 advance」。

### D-4 KB 仓的对账判据采用 checkpoint 合同导出关系，而非 `HEAD == sourceSha` 等式

- **Decision**：非 KB 仓用 `HEAD == sourceSha`；KB 仓用 `HEAD == metadataCommit ∧ HEAD^ == sourceSha ∧ dirty=false` 绑定内容，再用 artifact 哈希/digest 与 annotation 全等（§4.3）。
- **Context**：实测 KB 批次中 `repositories[].sourceSha` 是 metadata commit 的**父**（本 CR 自身的批次即为例证：`_backlog.yml#latest-checkpoint` 的 KB `source-sha` = `f9dd6fc3…`，而 `metadataCommit` = `3a553e3b…`、`3a553e3b^ = f9dd6fc3`）；code 阶段 KB 仓必然比 `reviewed-source-sha` 多出评审记录提交，HEAD 全等不可能成立。
- **Alternatives**：① 直接比较 KB `HEAD == sourceSha`（在当前 checkpoint 合同下恒不成立，对账必然假红）；② 复算时用 `git show <sha>:<path>` 取内容（`rules.json` 不放行评审者读业务文件）；③ 新增只读 crctl 子命令返回批次内文件（违反 NFR-4 零新增）。
- **Consequences**：对账判据与既有 `verifyReleaseSubjects`（`approve-code`/`merge`/`writeback` 已在用）同源，实现唯一；代价是评审者需按 §4.3.1 的三步只读取证建立绑定关系（已写明命令）。

### D-5 断言落点分层：tools CI 可执行断言 + multica 交付证据

- **Decision**：AC-4② 的机械判据分两层——**断言 A**（`pipeline-structure.test.mjs`，单一断言内同时校验四处载体中的 tools 三处 + 四个 review SKILL 前置，缺任一侧即失败，随 CI 每轮执行）；**断言 B**（`../multica/cr-prompts-revised/quality-reviewer-agent.md` 的 `## 受限 crctl 权限` 节核对，作为本 CR 的 TASK 完成证据与 `test-report.md` 的 issue evidence，不落为长期 CI 面）。
- **Context**：tools CI（`.github/workflows/crctl-ci.yml`）只 checkout tools 仓，`../multica` 在工作区外、在 CI 中不存在；NFR-6 又明令本 CR 对 multica 只改 Prompt 文档、不写 Go/TS 代码，因此无法在 multica 侧新增测试承载该断言。
- **Alternatives**：① 在 tools 测试里「有 `../multica` 则断言、无则跳过」——静默降级，违反工程纪律 #1（跨行/跨面解析失败必须硬失败）；② 新增跨仓扫描脚本/CI job——扩大扫描面，与 NFR-4/scope_out 冲突；③ 把 multica 副本排除出载体清单——与 PRD FR-8 明确的四处载体冲突。
- **Consequences**：CI 可执行的判据覆盖四处载体中的三处（tools 侧全部）；multica 副本以一次性交付证据覆盖并登记在交付说明，重复执行成本可接受。

### D-6 S-7 第五份权限面副本：**排除**出改动面并写明理由

- **Decision**：`../multica/cr-prompts-revised/agent-skill-matrix.yml`（第 192–194 行 reviewer 块注释与 tools 同名文件逐字相同、同样未含 `workspace inspect`）**不纳入**本 CR 的 multica 改动清单（维持 4 文件），在 SDD 与交付说明中写明排除理由，并登记 `follow_up`。
- **Context**：该副本是 **deployment snapshot**——`CUSTOM.md#75` 定性为「对照快照，公共 Agent Prompt 的唯一事实源为 `tools/agents/`、目录内公共 Prompt 副本不再独立演进、与 tools 分叉时以 tools 为准并人工对齐」；实测无任何代码消费者（`grep -rn "cr-prompts-revised"` 在 `*.ts/*.tsx/*.mjs/*.js/*.go/*.md` 内只命中 `CUSTOM.md`），也不被任何静态校验解析。另一个决定性事实：PRD §1.3.1 第 14 行的注记**已明写**「不改 `cr-prompts-revised/agent-skill-matrix.yml` 部署副本」，属已审批、已冻结范围，SDD 不得反向扩大。
- **Alternatives**：① 纳入（4→5 文件）——与已审批 PRD 明文冲突，且 PRD 哈希已锁（改动即作废本次人工审批）；② 沉默不提——留下 FR-8「不得在同一份合同下留第二种读法」的未说明例外。
- **Consequences**：排除理由进入 SDD/交付说明（可核对）；一致性由 `CUSTOM.md#75` 的「以 tools 为准、人工对齐」机制承担，登记为 `follow_up` 的第一项。

## 6. FR 到技术实现映射

### 6.1 FR 逐条映射（FR-1~FR-11）

| FR | 技术方案条目 | 落点文件 | 可机械核对 |
|---|---|---|---|
| FR-1 | §4.1 发布序列 + §3.1 合同（四 SKILL 同构、stage 分派不同） | 四个 `review-*/SKILL.md` | AC-3；`pipeline-structure.test.mjs` 断言前置换行与发布步骤存在 |
| FR-2 | §4.2 前置算法（位置钉定在 Step 1 起始） | 同上 4 文件 + §3.3 四处载体 | AC-3、AC-4② |
| FR-3 | §4.3 取证链 + 逐阶段判据（含 KB/非 KB 分解） | 同上 4 文件 | AC-3；断言含 `CONTRACT_DRIFT` 与「不改 verdict」 |
| FR-4 | §4.4.1 删除表（requirement `…0007`、architecture `…0005`、code `…0012`） | 3 份 pipeline JSON | AC-1 |
| FR-5 | §4.4.1 删除表 + §4.4.2 连带面 1/2/4 | 3 份 JSON + `_index.yml` + 4 个测试文件 | AC-1、AC-2 |
| FR-6 | §4.5（code 同 run 重跑；审批搭车；禁止面） | `merge-feature-branch/SKILL.md` + 四份 Agent Prompt | AC-6（延期验证点）+ `contract-scan` 文本断言 |
| FR-7 | §4.7 硬规则文本 + delivery 例外双向边界 + 静态文本断言 | 3 份 tools Prompt + 4 份 multica 副本 + `contract-scan.test.mjs` | AC-6、AC-5 |
| FR-8 | §3.3 权限契约（矩阵/can-call/forbidden/四处载体/部署时序） | `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md`、tools+multica `quality-reviewer-agent.md` | AC-4①~④ |
| FR-9 | §6.5 口径改写清单（四处同口径 + `node-N.md`/replayNodes 例） | `push-progress/SKILL.md`、`README.md`、`openwiki/pipelines/overview.md`、`dir-graph.yaml` | AC-7 |
| FR-10 | §4.6 算法（复用 + 三返回点 + best-effort + 幂等 + 文档面） | `workspace-transactions.mjs`、`cr-archive/SKILL.md`、`delivery-agent.md` | AC-8 |
| FR-11 | §6.7 生成物登记（受影响映射清单 + Runner 保持禁用） | 交付说明（`test-report.md` / CR 交付评论） | AC-9 |

### 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §4.4 删除表（§1.2 三份 JSON） | 三份 JSON 节点数 5/4/12；不存在位于 `human_approval` 之后的 `ref=push-progress` 节点；`ref=push-progress` 计数 = 0；`_index.yml` nodes 与 JSON 一致；被删 id 零出现 | 两条判据都可由 JSON 自身求出（节点序与节点计数），不依赖运行时；删除后「0 个发布节点」与「无门后发布节点」同时成立 |
| AC-2 | §6.4 测试面改动清单 + §4.4.2-4 | `pipeline-structure.test.mjs` 全绿；新断言覆盖 AC-1 两条判据 + 「review SKILL 含发布步骤 + clean 前置」 | 断言从 JSON/`_index.yml`/SKILL 文本事实源推导（NFR-5），不钉死易漂移措辞；`suite-gate` 的 `manifest.cases` 是下界（`SUITE_MANIFEST_CASE_DROP` 只在减少时红），新增用例不需要改登记面 |
| AC-3 | §4.1/§4.2/§4.3（四 SKILL 文本） | 四个 SKILL 均含 clean 前置（`crctl workspace inspect` + `healthy` 判据 + 「请作者先提交」）、PASS 发布（`push-progress` + `message` + 四字段消费）、对账（`CONTRACT_DRIFT`）与失败语义；BLOCK 段落不含发布调用；四个 SKILL 不含 `recoverCommand`/`recover_command` | 文本事实可由文件读出；`RETIRED_RECOVERY` 整树扫描既有、本 CR 不引入旧字段名 |
| AC-4 | §3.3（四处载体 + 断言 A/B） | ① 矩阵 can-call 含 `push-progress`、forbidden 不含且仍含 `checkpoint`；② 断言 A 单条内同时校验 tools 三处载体与四个 SKILL 前置；③ 反向：SKILL 无 `crctl checkpoint`、两份副本权限块含 `workspace inspect`；④ `AGENT-SKILL-MATRIX.md` 本 CR 行；三脚本全绿 | tools 三处载体 + 四个 SKILL 的断言在 CI 内可执行（D-5）；multica 副本以交付证据覆盖（D-5），本 CR 的 TASK 完成标志即含该项；③ 的 tools 侧可直接断言，multica 侧与 ② 同批核对 |
| AC-5 | NFR-1；§6.4 | CI（Ubuntu+Windows）六个步骤全绿；不签例外 | 所有被删除节点牵连的断言都在 §6.4 登记并改写；`lint-prompts --mode enforce` 的风险面在 §7.1 说明（新增文本不得构成状态机副本/裸 git/下一步映射） |
| AC-6 | §4.5 + §6.6（延期验证点登记格式） | 交付说明登记：载体（交付后新注册的小体量演练 CR／次选 CR-P1 首链）、时点、观察项 ①~④、责任 agent、关闭触发条件 | 该演练在本 CR 交付时**不可能**产出证据（需另一个 CR 走完四阶段），故设计为「登记即达成、未登记即 AC-6 未通过」；观察项 ① 的判据（`confirmed=true` + `metadataCommit` 非空 + 对账通过）在本 CR 的四次发布中即可部分自证（本 CR 自身就是载体之一） |
| AC-7 | §6.5 四处口径改写 | 四处均出现「阶段终点完成条件 = 评审 PASS 的 checkpoint（评审者执行、每阶段一次）」与「审批后无 checkpoint 节点 / 搭车」；无「审批后的阶段终点 checkpoint 为强制完成条件」旧句 | 四处均为仓库内文本，可逐字核对；额外把 `openwiki/pipelines/overview.md` 的 replayNodes 例（现含 checkpoint）与 `/coding` mermaid 的两个 checkpoint 节点一并改准，避免同文件内出现第二套事实 |
| AC-8 | §4.6 | `archive-tx.test.mjs`：① 三个成功返回点（幂等重放早退 / `complete` / `cleanup-pending`，即 `phase` 两值）均含 `localTrunkSync`；② 4 状态 × 6 reason 分类正确；③ dirty ⇒ `skipped/dirty` 且本地逐字节未变；④ argv 级命令面白名单：零 `reset/clean/stash/--force/push` 且命令面恰为 7 项（判据见右）；⑤ `changed=false` 重放仍返回且零新 commit；⑥ SKILL 与 delivery 汇报面含该字段 | ④ 的「命令面断言」必须是 **argv 级**，文本级子串判据在 §9 明令零 diff 的函数体上恒假（`rows.push(row)` 含 `push`；git 命令以 argv 数组书写、无字面 `merge --ff-only`），故不采用。实现：抽 `export function reconcileLocalTrunks` 起至下一个顶层 `}` 的函数体文本 → 抽其中全部 `gitRun`/`gitMust` 的第二个实参 argv（实测 7 个调用点）→ 归一化签名（取首 token；argv 含 `--prune`/`--verify`/`--is-ancestor`/`--ff-only` 之一时并入该选项）去重后**恰为** `rev-parse`／`rev-parse --verify`／`symbolic-ref`／`status`／`fetch --prune`／`merge-base --is-ancestor`／`merge --ff-only`（无多无少），且全部 argv 元素不含 `reset`/`clean`/`stash`/`--force`/`push`——子串判据只作用于 argv 元素，**不作用于整段函数体文本**；函数体或 argv 抽取失败、调用点数 ≠ 7 ⇒ **硬失败**（不降级为空串/空集）。该断言与 §9 的函数体零 diff 约束相容（判据落在命令面而非文本），与 ③ 的字节比对互为独立证据 |
| AC-9 | §6.7 | 交付说明登记受影响映射清单（见 §6.7 表）且必有「重启生成前保持 Runner 禁用」或「已重生成」之一 | 映射清单由节点下标直接算出（可复算）；`ArchitectureRunnerEnabled()` 默认 false（`runner.go:56-63`）是既有事实；本 CR 不改 `gate_nodes_gen.go`，故只能走「保持禁用 + 登记」分支 |
| AC-10 | §9 批准范围（scope_in/scope_out/zero_diff） | ① diff 不含平台执行层/Runner/continuation、新节点/维度/账本字段/观测指标、事务层/状态机/错误码改动、`recovery` 字段名改动、`recoverCommand` 复活；② 不含 `onFail:skip` + 输入端开关形式的「审批后/评审后 checkpoint」；③ 在途 CR 唯一（066）、063/064/065 均 archived；④ 与 CR-P1/P2 的面零 diff | ③ 现成（`crctl status` 可查）；④ 由 zero_diff 清单 + 交付前 diff 复核保证；① 的 `recoverCommand` 面由 `contract-scan` 的 `RETIRED_RECOVERY` 整树扫描兜底 |

**反查（§6.2 → §4/§3 正文）**：每条 AC 的落点都能产出所写可观测结果；无「关键前置使目标不可达」的情形——唯一需要额外证成的是 AC-4② 的跨仓可执行性（已由 D-5 把判据拆为可执行层与交付证据层，未把目标过滤掉）与 AC-6 的时点（已由「登记即达成」定义解除不可达）；AC-8④ 的判据已按 argv 级重定义（见该行与 §7.1），与 §9 的函数体零 diff 约束相容，不再存在「文本级判据恒假」的不可达面。正文算法与接口契约均不与 PRD 明文要求冲突：唯一与 PRD 字面表述不同的一处是 FR-3 的 KB 取证等式，已在 §4.3.1/D-4 逐条给出事实与替代论证，且结论与 PRD 的「KB 受控 artifact 哈希与 release snapshot 一致」同向。

### 6.3 既有实现依赖与事实

正文存在但未列入本清单的同类事实引用视为漏列；本清单按仓与依赖面分组、组内按正文首次出现顺序排列（B-2 三轮回修与 S-10 的新增项都按其正文首现位置插入对应分组；0.4 版共 50 项）。

**收录判据（0.4 版起明写，口径单一）**：SDD 正文引用到的任一既有实现事实都必须入册——① 设计陈述或判据的成立前提（模块行为、返回形状、调用顺序、抽取锚点）；② 本 CR 直接修改的既有文本；③ §9 `zero_diff` 点名对象；④ SDD-CLOSE-0x 的证据。本轮新增三项（第 17 项 `cmdArchive`、第 22 项结构化 `recovery` 合同、第 25 项 `gitRun`/`gitMust`）均落在 ① 与 ③；据此把评审者点名的两个候选**一并登记**（第 22 项、第 25 项），不存在「同类候选不登记」的例外。

1. repo: tools
   relative path: ARCHITECTURE.md
   stable symbol/对象: `## 4. 分层与依赖方向`（L69-82：Pipeline → Skill → crctl「依赖只朝下」的图示与规则）与 `## 5. 硬不变量`（L83 起：不变量 1 状态单一写者、2 账本单一写入通道、4 行尾与硬失败纪律、8 Skill 通用约束归仓）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: §1.1 的「分层与依赖方向不变」与 §1.3 的三条硬约束均取自本文件（实读 L69-95，与声明一致）；I1~I4 四条设计不变量不得与之冲突，本 CR 不新增层级、写入口与账本文件。
2. repo: ai-first-platform-docs
   relative path: change-requests/_backlog.yml
   stable symbol/对象: `change-requests[].latest-checkpoint.{batch-id,repositories[].source-sha,remote-ref}`（批次快照结构）
   commit SHA: 3a553e3bd74e63e9c1d60cf692c7a579c638e996
   依赖结论: FR-3 对账的期望值来源是 checkpoint 返回批次；本文件当前条目实测「KB `source-sha` = `metadataCommit^`」，是本设计 KB 判据（D-4）的直接实证。
3. repo: ai-first-platform-docs
   relative path: change-requests/CR-2026-066/prd.md
   stable symbol/对象: PRD 文档本体（`sha256(LF)` = `9b43bbfafa3be7a82c7e86900b17f64c3e95365347c9ed8588883e8d53aef1db`，349 行 / 61,874 B / 零 CR（行数与 canonical `review-annotations/requirement.yml` 同口径））
   commit SHA: 3a553e3bd74e63e9c1d60cf692c7a579c638e996
   依赖结论: 本 SDD 的全部 FR/AC/§1.4 事实与 §1.5 裁定均以此冻结版本为输入，SDD 不得触碰该文件（改哈希即作废人工审批）。
4. repo: tools
   relative path: pipeline-templates/requirement-authoring.pipeline.json
   stable symbol/对象: `nodes[]`（7 节点：`…0001`/`…0002`/`…0003`/`…0004`/`…0005`/`…0006`/`…0007`）、`inputs[].key`（含 `auto_push_after_prd`）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: FR-4/FR-5 的删除对象（`…0003`/`…0007` 对象 + `auto_push_after_prd`）与 AC-1 的 5 节点终态。
5. repo: tools
   relative path: pipeline-templates/architecture-design.pipeline.json
   stable symbol/对象: `nodes[]`（5 节点，`…0005` 是唯一 push-progress，位于 `…0003` human_approval 之后）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: FR-4 删除 `…0005` ⇒ 4 节点；AC-1 与 FR-11 的 registry digest 变化均源于此。
6. repo: tools
   relative path: pipeline-templates/code-implementation.pipeline.json
   stable symbol/对象: `nodes[]`（16 节点；push-progress 位于下标 3/9/12/15）、`inputs[].key`（含 `auto_push_after_task`）、`nodes[11].reviewLoop.replayNodes`（5 项，第 3 项 `…0008`）、`nodes[13].approvalPrompt`（含「且评审后 checkpoint phase=complete」）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: FR-4/FR-5 的删除面与 §4.4.2 的连带面（输入、replayNodes 5→4、approvalPrompt 前提句）全部落在本文件的这些稳定符号上。
7. repo: tools
   relative path: pipeline-templates/_index.yml
   stable symbol/对象: `pipeline-templates[].nodes`（requirement 7 / architecture 5 / code 16）与三条 `brief`
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: `dir-graph.yaml#pipeline_templates.contract` 第 1 条要求「新增或修改 pipeline JSON 后同步 _index.yml 的 nodes 数量」；`pipeline-structure.test.mjs` 与 `crctl.test.mjs` 都以本文件为一致性事实源。
8. repo: tools
   relative path: skills/shared/crctl/gates.json
   stable symbol/对象: `approvalStages.*`（`to`/`trigger`/`expect`/`approvalSection`/`evidence`/`passCondition`；声明式映射，不复刻规则副本）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: §2.3 与 §9 的「`gates.json` 零改动」声明、SDD-CLOSE-02 第 7 项「门禁只读本地」结论的载体；评审 PASS 发布不新增审批段、不改门禁，故保持零 diff。
9. repo: tools
   relative path: skills/requirement/review-requirement/SKILL.md
   stable symbol/对象: 「调用时机」（L10，`第 4 节点（push-progress 之后）`）、Step 1「前置校验」（L32）、Step 1.5 pre-review 门禁（L37）、PASS 分支（L131 的既有 `advance`）
   commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
   依赖结论: FR-2 前置须插在 Step 1 起始（Step 1.5 之前）；FR-1 的发布须接在既有 PASS `advance` 之后；「调用时机」的 checkpoint 前提句需同步。
10. repo: tools
    relative path: skills/develop/review-tech-design/SKILL.md
    stable symbol/对象: Step 1「读取输入」（L38）、Step 4 分流（PASS 保持 `tech-design-review-pending`，无 `advance`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 该 Skill 的 PASS 分支**没有** `advance`，是 §4.1 按 stage 分派的直接依据（不得为该阶段新造 `advance`）。
11. repo: tools
    relative path: skills/develop/review-dev-plan/SKILL.md
    stable symbol/对象: Step 1「前置校验」（L33）、Step 4 路由「PASS 保持 task-breakdown」（L132）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 与 10 同理（PASS 无 `advance`）；其「调用时机」（L9）含「push-progress 之前」的旧前提句，需随 FR-5 改写。
12. repo: tools
    relative path: skills/develop/review-code/SKILL.md
    stable symbol/对象: 「调用时机」（L10 `第 8 节点（代码编写与统一 checkpoint 后）`）、用途句（L16「在开发者完成编码并推送统一 checkpoint 后…」）、Step 5 PASS 分支（L142 的既有 `advance --to code-reviewing`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 该 Skill 的两个「统一 checkpoint 前提句」在 FR-5 删除 `…0008` 后即失真，必须改写；其 PASS `advance` 是 §4.1 步骤 3 的唯一 code 阶段动作。
13. repo: tools
    relative path: skills/sync/push-progress/SKILL.md
    stable symbol/对象: 「调用时机」（L9 的「需求/架构/代码审批后的阶段终点 checkpoint 为强制完成条件」）、参数（`cr_id`/`message`）、Step 2 输出解释（`phase`/`changed`/`batchId`/`repositories[]`/`metadataCommit`）、Step 3 摘要、错误处理表
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-9 与 AC-7 的目标句落在此文件的「调用时机」；FR-1 的发布调用只用既有参数面（不新增参数）。
14. repo: tools
    relative path: skills/writeback/merge-feature-branch/SKILL.md
    stable symbol/对象: Step 3 结果分类表的 publication lag 行（L53：`MERGE_SOURCE_MISSING`/`RELEASE_REMOTE_NOT_PUSHED` → 「状态保持 `code-approved`，不回退；按 `error.recovery`（结构化 argv）先 checkpoint 再重跑 merge」）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-6 的落点文件；§3.4 与 §4.5 的「同一 run 内执行 `recovery` 一次后重跑 merge」以本行的既有语义为前提，本 CR 只补「同 run、不得转成新委派」的口径，不改其分类表结构。
15. repo: tools
    relative path: skills/cr/cr-archive/SKILL.md
    stable symbol/对象: Step 3 结果分类表（L56-84）与「输出」块（`commit`/`lastCleanupError`/`remaining`/`preservedRefs`/`recovery`/`warnings` 逐字透传）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-10.8 的落点文件；§4.6.2 要求其 Step 3 分类表与「输出」块新增 `localTrunkSync`，同时既有字段与分类语义逐字不变（AC-8⑥ 的文本断言面）。
16. repo: tools
    relative path: skills/shared/crctl/scripts/crctl.mjs
    stable symbol/对象: `cmdCheckpoint`（L2367-2393：status 读 KB CR worktree，仅拒绝终态 `ILLEGAL_LEDGER_STATE`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 评审 PASS 时的四个状态（`requirement-reviewing`/`tech-design-review-pending`/`task-breakdown`/`code-reviewing`）均非终态 ⇒ 发布不需要新增状态或转换（NFR-4）。
17. repo: tools
    relative path: skills/shared/crctl/scripts/crctl.mjs
    stable symbol/对象: `cmdArchive`（L3566 定义）＋ dispatch 分支（L3526 `case 'archive': return cmdArchive(ws, positional, flags)`）＋ 返回透传（L3640 `ok({ op: 'archive', ...result })`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §3.2（`archive` 返回新增 `localTrunkSync` 且既有字段逐字不变）、§8（`crctl.mjs` 的 dispatch 分支与 `cmdArchive` 返回透传「都已存在」⇒ `Prompt 采纳影响` 判 N/A）与 §9 `zero_diff`（`crctl.mjs` 全文件零 diff）三处声明的既有前提：新字段只经 `archiveCr` 的 `result()` 构造成员与本次 spread 透传，本 CR 不改该文件任何一行。与第 16 项同属该文件的 CLI 命令面（同文件、同级、兄弟已登记，唯它此前缺席）。
18. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `checkpointCr` 的 KB 合同（`payload.kbSourceSha` = metadata commit 直接父且受断言 `parent !== payload.kbSourceSha → CHECKPOINT_SNAPSHOT_INVALID`；metadata stage 集合必须恰为 `change-requests/_backlog.yml`，否则 `CHECKPOINT_SNAPSHOT_INVALID`；非 KB 仓 `sourceSha == 本地 HEAD == 远端 HEAD`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §4.3.1 的 KB 取证链与 D-4 的全部依据；也是对账判据能否成立的唯一事实源。
19. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `classifyRepoWorkspace`（L660-688：`localBranch`/`remoteBranch` 用本地 ref，`dirty` 用 `git status --porcelain`，**不 fetch、不 ls-remote**）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-2 前置与 FR-1 步骤 4 是网络无关的只读检查（评审者在离线环境亦可完成前置校验）；`classification=healthy ⇒ dirty=false`（更强前置：还要求 worktree 已注册且 HEAD 在 CR 分支上）判据成立。
20. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `buildReleaseSubjects`（L1216-1252）/`verifyReleaseSubjects`（L1283-1360 区域：非 KB `HEAD == reviewed-source-sha`、KB 祖先关系 + 受控 artifact 逐文件/集合/digest 重核）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §4.3.2 code 阶段判据与该既有复核语义同源（KB 不比 HEAD 全等），避免评审者自造第二套判据。
21. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `mergeCr(ctx, input)`（L1532 定义）的 publication preflight 块（L1583-1606：注释「新事务全仓 publication preflight——远端 requirement source 精确等于本地 HEAD 才允许首次 prepare」＋ `checkpointRecovery`（L1586）＋ `MERGE_SOURCE_MISSING`（L1599）＋ `RELEASE_REMOTE_NOT_PUSHED`（L1602））
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-6 code 路径兜底所依赖的既有语义（§4.5「`merge` 的 publication preflight 语义不变」）与 SDD-CLOSE-02 第 8 项「唯一远端相等要求」的证据；preflight 只在首次 prepare（`payload.repos` 为空）时执行，两个错误都携 `recovery`（checkpoint argv）⇒ writeback run 可就地执行一次并在同 run 重跑；§9 zero_diff 亦把其函数签名与 `checkpointCr`/`applyWriteback`/`registerCr` 并列。
22. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: 结构化 `recovery` 合同的构造与字段面——`buildRecovery(args, { cwd, requiresTTY = false, promptFor = [] })`（L26 定义，注释块 L20-25「recovery 合同（CR-2026-064 TASK-01）」；含 `RECOVERY_CONTRACT_INVALID` 契约守卫）与字段名 `executable`/`args`/`cwd`/`requiresTTY`/`promptFor`
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §9 `zero_diff` 点名「`recovery` 结构化合同字段名（`executable`/`args`/`cwd`/`requiresTTY`/`promptFor`）」零 diff；§3.4 的「按 `recovery` 重试同一 `push-progress`」、§4.5 的「就地执行 `error.recovery`（结构化 argv、`shell:false`）一次后同 run 内重跑 merge」与 §6.6 的失败汇报面都以该既有构造与字段面为前提（第 21 项 `mergeCr` 的 `checkpointRecovery`（L1586）即本函数的调用点）。本 CR 只消费该合同：不新增字段、不改构造、不复活 `recoverCommand`/`recover_command`（由 `contract-scan` 的 `RETIRED_RECOVERY` 整树扫描兜底）。
23. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `reconcileLocalTrunks(ctx)`（L1487-1530，即自 `export function reconcileLocalTrunks` 起至下一个顶层 `}`，与 AC-8④ 的抽取边界一致；行形状 `{repo,trunk,before,remote,after,status,reason}`；`status ∈ unchanged|synced|skipped|failed`；`reason ∈ wrong-branch|dirty|diverged|fetch-failed|trunk-unavailable|ff-only-failed`；仅 `fetch --prune origin` + `merge --ff-only`；全程局部捕获不抛错）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-10 复用对象；其分类与形状即 `localTrunkSync` 契约，也是 AC-8②③④ 的判据源。
24. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `reconcileLocalTrunks` 在 merge 的既有唯一调用点（L1786）与返回（L1791）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 证明「函数已被生产路径验证」且字段名已被消费；本 CR 只加第二个调用点与返回字段（FR-10.1/2）。
25. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `gitRun(cwd, args, opts)`（L378 导出；`spawnSync('git', args, { shell: false })`，返回 `{ status, stdout, stderr }`）与 `gitMust(cwd, args, opts)`（L383 导出；非零退出抛 `TX_GIT_FAILED`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: AC-8④ 的抽取锚点（§6.2 AC-8 行 ④、§6.4 `archive-tx.test.mjs` 行、§7.1）：判据从 `reconcileLocalTrunks` 函数体抽 `gitRun`/`gitMust` 的**第二实参** argv（实测 7 个调用点）再做命令面白名单与硬失败——「git 命令以 argv 数组形态书写、argv 恒为第二实参」这一既有调用形状是判据可实现的既有前提（§3.2 确定性四查的「受控 `gitMust`，局部捕获」亦引其名）。本 CR 不改两者签名与实现。
26. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `archiveCr(ctx, input)`（L3498 起）：`result()` 固定返回构造、三个成功返回点（L3597 幂等 complete 早退 / L3757 complete / L3759 cleanup-pending）、既有返回字段 `commit`/`lastCleanupError`/`remaining`/`preservedRefs`/`recovery`/`warnings`
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §4.6.1 的最小侵入点（三返回点 + 局部包装）；既有字段与 `phase` 分类不得改变（AC-8①、§3.2）。
27. repo: tools
    relative path: skills/shared/controlled-shell/rules.json
    stable symbol/对象: `git[]` 白名单（`rev-parse` → `callers:["*"]` 且含 `^--verify \S+$`；`show` → `callers:["system-orchestrator"]` 且只放行 `review-annotations/*`）、`protectedPaths.deny`（账本/审批/评审记录路径）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-3 的取证手段只能用 `rev-parse`（`HEAD`/`--verify HEAD^`）+ 文件只读；`git show` 不可用于业务文件；评审者不得写账本（deny 面不变）。
28. repo: tools
    relative path: agent-skill-matrix.yml
    stable symbol/对象: `quality-reviewer-agent`（L178-208：`can-call` 4 项、块注释 L192-194、`forbidden` 含 `push-progress` 与 `checkpoint`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-8 的改动对象与 AC-4① 的判据；注释扩容是本 CR 三处载体之一。
29. repo: tools
    relative path: AGENT-SKILL-MATRIX.md
    stable symbol/对象: `## 本 CR 权限变更` 节（L46）与既有数据行（L52，`quality-reviewer-agent`/`controlled-shell`，属既有 CR）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: S-8 要求本 CR 行内带 CR 编号以与既有行区分；`check-skill-matrix.mjs` 不校验 can-call/forbidden，故本表是人工可读的补充载体。
30. repo: tools
    relative path: agents/quality-reviewer-agent.md
    stable symbol/对象: `## 权限事实源` 节（L35-38：只声明「权限矩阵：agent-skill-matrix.yml」；文件 42 行、无 crctl 子命令清单）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: S-8③ 的「tools 侧不存在『受限 crctl 权限块』、对应节名是『权限事实源』」的事实源；本 CR 需在该节给出同一允许面声明（载体 ③a）。
31. repo: tools
    relative path: agents/dev-agent.md、agents/delivery-agent.md
    stable symbol/对象: `dev-agent.md` 的评审前置句（「先有代码、测试报告和统一 checkpoint…」「checkpoint 未完成时，不进入后续人工审批」在 tools 侧**实测不存在**——该两句仅存在于 multica 部署副本，tools 侧 dev-agent.md 现文为「委派路由合同（评审）」）；`delivery-agent.md` 的「不裸调 crctl 原语」句
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-7 的 tools 侧增量是**新增**搭车硬规则与发布职责，不是原位改写；原位改写的两个句子落在 multica 副本（见下条 multica 的 `cr-prompts-revised/dev-agent.md` 项）。**PRD §1.4 事实 12 的「multica dev-agent.md L23/L41」与 tools 侧现行文本的差异在此登记为已核实事实。**
32. repo: tools
    relative path: README.md、openwiki/pipelines/overview.md、dir-graph.yaml
    stable symbol/对象: `README.md` L61-75（第 6 节 checkpoint 行 L65）、`openwiki/pipelines/overview.md` L114/L116/L118（三段描述）、L120-140（`/coding` mermaid 的 `D8["checkpoint"]` 与 `D12["checkpoint (mandatory)"]`）、L73（replayNodes 例含 checkpoint）、L172（contract 第 9 条）、`dir-graph.yaml` L178（`pipeline_templates.contract` 第 5 条）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: FR-9/AC-7 的四处口径目标与两处连带（mermaid、replayNodes 例）都落在这些既有行上；`dir-graph.yaml` 第 5 条现文「按顺序列出修复、证据、checkpoint 与当前评审节点」必须改写。
33. repo: multica
    relative path: cr-prompts-revised/quality-reviewer-agent.md
    stable symbol/对象: `## 受限 crctl 权限` 节（L35-46：`仅限评审所需的以下子命令` + 四条允许项 L39-42 + 禁止面枚举 L46 含 `checkpoint`）、L54「本 Agent 不负责 push/checkpoint，后续发布由 Pipeline 中对应的同步节点完成」
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: B-1 事实源（`workspace inspect` 两侧均未出现）；L54 与 FR-1 直接冲突必须原位改写；载体 ③b 的断言 B 落点。
34. repo: multica
    relative path: cr-prompts-revised/dev-agent.md
    stable symbol/对象: L23「代码评审：先有代码、测试报告和统一 checkpoint，再由独立 reviewer 调用 `review-code`」、L41「评审 blocker 未清空、测试报告未 pass 或 checkpoint 未完成时，不进入后续人工审批」
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: FR-7 的两个「原位改写」句子实测在 multica 副本而非 tools 侧；改写为「评审 PASS 即发布」口径。
35. repo: multica
    relative path: cr-prompts-revised/delivery-agent.md
    stable symbol/对象: L27「本 Agent 只传业务输入、消费结构化结果和解释错误，不裸调 crctl 原语、不跨节点补跳」（FR-7 的 recovery 例外要在本句上开洞）与 L44 的归档终态汇报面（L44 原文：只有「归档返回 `complete` 或 Skill 明确的完成态」才发最终汇报，汇报项含「归档结果」；全文件 `cleanup-pending` 零命中——S-11 更正：原括注的 `cleanup-pending` 与汇报面 `localTrunkSync` 都是 §4.6.2／AC-8⑥ 的**设计目标**，不是既有事实）
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: FR-7 交付集的第四份 multica 副本（§1.2 树与 §4.7 表行都把它列为同步对象）；§4.5 要求其增量文本写明「`recovery` argv 属于被授权的同 run 重跑、不受『不裸调 crctl 原语』约束」且「该例外不赋予独立发起 checkpoint 的权力」，§4.6.2 要求其汇报面含 `localTrunkSync`。
36. repo: multica
    relative path: cr-prompts-revised/cr-coordinator-agent.md
    stable symbol/对象: L19/L60（`crctl` 仅只读 `status`/`next`，禁止 `advance`/`approve`/`checkpoint` 等写入型子命令）
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: 「门后节点只能被单独委派」的直接原因；FR-7 需在本文件增加「不得为 checkpoint 单开委派」的显式禁止（不改其 crctl 只读边界）。
37. repo: multica
    relative path: CUSTOM.md
    stable symbol/对象: 条目 75（表行，物理行 387）（`cr-prompts-revised/` 定性：公共 Prompt 唯一事实源为 `tools/agents/`、目录内副本不再独立演进、以 tools 为准人工对齐、`cr-coordinator-agent` 不进 tools agent index）
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: D-6（S-7 排除第五份副本）与 D-5（multica 侧不建 CI 断言）的治理依据；本 CR 不改 CUSTOM.md。
38. repo: tools
    relative path: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
    stable symbol/对象: AC-1/AC-2/AC-3 断言（L24-52、L91-99、L114-137）、CR-2026-044 段（L168-213）、CR-2026-050 FR-12.x 段（L304-380）、8 条 pipeline 节点数表（L516-530）、architecture registry 断言（L262-278）、L229（architecture 后续节点不得依赖 `node-1.md`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §6.4 中必须改写的断言清单来源；也是 AC-1/AC-2/AC-4 新断言的落点。
39. repo: tools
    relative path: skills/shared/crctl/scripts/test/archive-tx.test.mjs
    stable symbol/对象: 既有 fixture `makeWritebackFixture`（L17 定义）与 `makeNewModeArchiveFixture`（L86 定义）（文件 783 行；AC-8 六项新用例的落点）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: AC-8 六项用例的唯一落点（§1.2 树、§6.2 AC-8 行与 §6.4「文件与 fixture 既有」）；SDD-CLOSE-01 的「不拆」判据③直接以「复用既有 fixture、不新建夹具」为前提 ⇒ 两个 fixture 的既有形状是本 CR 测试面成立的前置事实。
40. repo: tools
    relative path: skills/shared/crctl/scripts/test/contract-scan.test.mjs
    stable symbol/对象: replayNodes 结构快照（L81-98）、`RETIRED_RECOVERY = ['recoverCommand','recover_command']` 整树扫描（L418-425 区域）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: replayNodes 快照含 `push-progress` ⇒ 必须随 FR-5 改写（§6.4）；FR-7 的静态文本断言按「同风格」落在此文件；`RETIRED_RECOVERY` 兜底 AC-3 的零命中判据。
41. repo: tools
    relative path: skills/shared/crctl/scripts/test/crctl.test.mjs、checkpoint-tx.test.mjs
    stable symbol/对象: `crctl.test.mjs` L5036（code pipeline inputs 逐字列表含 `auto_push_after_task`）、L5038（`ids.length === 16`）、L5040（`…0017` 是 `…0009` 的直接前驱；L5039 是 `…0013` 已删除断言）；`checkpoint-tx.test.mjs` L487-495（跨 4 份 pipeline 过滤 `push-progress`/`list-remote-checkpoints` 节点做 prompt 负向断言）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 这两处是 §1.3.1 第 13 行未列出、但会被 FR-4/FR-5 直接证伪的既有断言；`checkpoint-tx` 的 `filter` 形态在删除后集合退化为 1 项（resume-cr 的 `list-remote-checkpoints`），须改为显式枚举以杜绝「过滤为空 → 断言静默失效」。
42. repo: tools
    relative path: skills/shared/crctl/scripts/test/gate-registry.json、suite-gate.mjs
    stable symbol/对象: `manifest.files` / `manifest.cases`（下界语义：`SUITE_MANIFEST_CASE_DROP` 仅在用例数 `<` 基线时红）、`manifest.files` 磁盘集合等式
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 本 CR 只新增用例、不改测试文件集合 ⇒ **不需要**改 `gate-registry.json`（若新增文件则必须同步）。
43. repo: tools
    relative path: .github/workflows/crctl-ci.yml
    stable symbol/对象: 六个步骤（`lint-prompts --mode enforce`、`check-skill-matrix.mjs`、`check-agents-contract.mjs`、pipeline JSON 结构断言、`suite-gate.mjs --run`、writeback 单测）与 `paths` 触发面
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: AC-5 的判据面；其中 `lint-prompts` 的规则面（R1~R13）是本 CR 新增文本必须避让的约束（§7.1）。
44. repo: tools
    relative path: pipeline-templates/emit-registry.mjs
    stable symbol/对象: canonical JSON（`body.pipeline.nodes[].{id,kind,label,ref,prompt,approvalPrompt,onFail,reviewLoop}`）→ `digest = sha256(canonical)`；当前 digest `sha256:5454bfd990f88748fac3351e0abc1d044f14b490cdcef70ac6d627f5959c91cc`
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: 删除 architecture `…0005` 必然改变 digest（节点对象进入 canonical JSON）；FR-11 只需登记，不要求本 CR 重生成。
45. repo: multica
    relative path: server/internal/governance/gate_nodes_gen.go、server/internal/governance/runner.go、server/internal/governance/gen/generate-gate-nodes.mjs
    stable symbol/对象: `ApprovalGates`/`ReviewGates` 的 `{PipelineID,NodeID,Seq}` 映射（requirement `…0005`/Seq 5、`…0004`/Seq 4；tech-design `…0003`/Seq 3、`…0002`/Seq 2；dev-start `…0004`/Seq 5；code `…0010`/Seq 14、`…0009`/Seq 12）、`ArchitectureCoreRegistryJSON` 内嵌 registry、`ArchitectureRunnerEnabled()`（`AIFIRST_ARCHITECTURE_RUNNER` 未设 ⇒ false）、生成器 `--check`（对 `../tools` 做比较）
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: §6.7 受影响映射清单的来源；Runner 默认关闭 ⇒ 未重生成期间不影响运行；实测 multica `.github/workflows/*` 对 `gate-nodes`/`gate_nodes`/`governance` **零命中**，故未重生成不会让 multica CI 变红（`--check` 是人工/验证时动作）。
46. repo: multica
    relative path: cr-prompts-revised/agent-skill-matrix.yml
    stable symbol/对象: L192-194 reviewer 块注释（与 tools 同名文件逐字相同、未含 `workspace inspect`）
    commit SHA: 43848770bff13465de8ed9a0e28ecc7371716514
    依赖结论: S-7 的事实源；D-6 判定为 deployment snapshot（无代码消费者、无静态解析器，`grep -rn "cr-prompts-revised"` 只命中 `CUSTOM.md`），排除出本 CR 改动面。
47. repo: tools
    relative path: skills/sync/workspace-freshness/SKILL.md
    stable symbol/对象: 「用途」段（L13-15，关键句 L15）：「本 Skill 职责收敛为『远端 trunk 新鲜度预检』…fetch/sync 失败可中止当前 Pipeline 节点，但不改变 CR status、approval、review verdict 或 reviewLoop attempt」
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: SDD-CLOSE-02 第 2 项的证据：其 fetch 只用于感知 behind，本地 ahead 判定不依赖远端内容 ⇒ 与「审批提交只在本地」不冲突；其两个节点（code `…0016`/`…0017`）本 CR 不删。
48. repo: tools
    relative path: skills/shared/crctl/scripts/crctl.mjs
    stable symbol/对象: `approveAndAdvance`（L1095 定义；approval + status 原子提交核心，TTY 与 `--grant` 共用）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: SDD-CLOSE-02 第 3 项的证据：四个 `approve-*` 的输入面 = `approval.yml` + `review-annotations/*` + `gates.json`（code 阶段另经 `verifyReleaseSubjects`，不 fetch、不读 remote-tracking ref）⇒ 审批是网络无关的本地账本事务，支撑 FR-6 的搭车取舍。
49. repo: tools
    relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
    stable symbol/对象: `applyWriteback(ctx, input)`（L3182 定义；内部化 `applyWritebackAtomic`）
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: SDD-CLOSE-02 第 5 项的证据：writeback 只消费 txws 内 approval/release-subjects 与 traceability journal，不做 trunk 相等性校验 ⇒ 不引入远端前置；§9 zero_diff 亦把其签名与 `checkpointCr`/`mergeCr`/`registerCr` 并列。
50. repo: tools
    relative path: skills/shared/crctl/scripts/test/assertion-sources.mjs
    stable symbol/对象: 现有导出面（`readTextNormalized`（L17）/ `deriveStateMachine`（L36）/ `readTestFileSet`（L90）；文件 98 行，自述「测试辅助模块、不匹配 `*.test.mjs`」）——**不含**函数体文本／argv 抽取 helper
    commit SHA: 5d5a4ada96b882eb2c640e34bb72857a7073b668
    依赖结论: §9 `follow_up` 第 7 项的取舍依据（AC-8④ 的抽取 helper 在 `archive-tx.test.mjs` 内就地实现、不上移本模块）；本 CR 只读其现有导出，不新增导出、不改该文件。

### 6.4 既有测试面改动清单（连带闭合，逐断言）

| 文件 | 断言/用例 | 处置 |
|---|---|---|
| `pipeline-structure.test.mjs` | L24-30（review-code < checkpoint(…0015) < human_approval） | **删除**（`…0015` 已删）；替换为 AC-1 两条判据断言 |
| 同上 | L32-42（`…0015` onFail=abort/ref=push-progress；`ids.length === 16`） | **改写**：节点数改为事实源推导 12；删除 `…0015` 相关断言 |
| 同上 | L44-52（replayNodes 逐字 5 项） | **改写**：4 项（去掉 `…0008`），仍由 JSON 事实源推导 |
| 同上 | L70-72（`…0008` < `…0017` < `…0009` 的相邻关系） | **改写**：删除 `…0008` 参与的前置，保留 `…0017` < `…0009` |
| 同上 | L114-116、L135-137（`…0010.approvalPrompt` 含「评审后 checkpoint phase=complete」） | **改写为反向断言**：`…0010.approvalPrompt` **不含**该句（FR-5 的同步删除面） |
| 同上 | L168-183（CR-2026-044 AC-13：requirement 7 节点 + approve-requirement 后必有 push-progress + `_index.yml` nodes=7） | **改写**：5 节点；「approve-requirement 之后**不得**有 push-progress」；`_index.yml` nodes=5 |
| 同上 | L186-203（AC-14：architecture `push.length === 1`、5 节点） | **改写**：`push.length === 0`、4 节点；保留「prompt 无 `crctl checkpoint` 字面量」与 `<installation-workspace>` 负向断言（其对象消失后按事实源推导重写） |
| 同上 | L205-213（AC-13 code：审批结果 checkpoint 存在 + TASK checkpoint 可选 + 16 节点） | **改写**：`ref=push-progress` 计数 = 0 + 12 节点 + inputs 不含 `auto_push_after_task` |
| 同上 | L262-278（architecture registry：`nodePermissions.length === 4` + `byRef['push-progress'] === 'system-orchestrator'`） | **改写**：3 个 skill 节点；去掉 push-progress 行；digest 改为「与 `node pipeline-templates/emit-registry.mjs --pipeline architecture-design` 输出一致」或断言格式（不得钉死旧 digest） |
| 同上 | L306-320（FR-12.2：requirement 7 节点顺序 + `auto_push_after_prd` 分支保留） | **改写**：5 节点顺序 `[requirement-register, write-requirement-prd, review-requirement, human_approval, approve-requirement]`；删除草稿 checkpoint 断言 |
| 同上 | L341-375（FR-12.3 L341-363 的 replayNodes 5 项含 `…0008` ＋ FR-12.3b L365-375 的字面量保留断言：`auto_push_after_task`、审批结果 checkpoint） | **改写**：删除 `auto_push_*`/checkpoint label 断言；保留 gate 名与 task done 面 |
| 同上 | L516-530（8 条 pipeline 节点数 7/5/16） | **改写**：5/4/12（其余 5 条不变）；UUID 全局唯一保持不变 |
| 同上 | **新增** | AC-1 两条判据（无门后 push-progress + `ref=push-progress` 计数为 0）；`_index.yml` ≡ JSON（既有 L91-99 已覆盖，保留）；四个 review SKILL 含 clean 前置 token（`crctl workspace inspect` + `healthy`）与发布步骤 token（`push-progress` + 四消费字段）；AC-4② 的单条「四处载体 + 四 SKILL 前置」断言；AC-4③ 反向断言（四 SKILL 不含 `crctl checkpoint`） |
| `contract-scan.test.mjs` | L81-98（code replayNodes ref 快照含 `push-progress`） | **改写**：4 项 ref（去 `push-progress`） |
| 同上 | **新增** | FR-7 静态文本断言：tools 三份 Prompt（`agents/{dev,quality-reviewer,delivery}-agent.md`）均含搭车硬规则文本（token 级：`push-progress` + `单独开委派`/`同 run`，不断言整句） |
| `crctl.test.mjs` | L5036（inputs 逐字含 `auto_push_after_task`）、L5038（16 节点）、L5040（`…0017` 直接前驱 `…0009`；L5039 是 `…0013` 已删除断言） | **改写**：inputs = `['cr_id','target_version']`；节点数按事实源推导；保留 `…0017` 与 `…0009` 相邻关系（删除后仍相邻） |
| `checkpoint-tx.test.mjs` | L487-495（跨 4 份 pipeline 的 `filter(...)` 负向断言） | **改写**：改为显式枚举剩余节点集合（`resume-cr` 的 `list-remote-checkpoints`；`requirement/architecture/code` 三份为空集合）并断言该枚举非空 + 逐条负向断言；**禁止**保留会随删除退化为空集的 `filter` 形态 |
| `archive-tx.test.mjs` | **新增用例**（AC-8 六项；文件与 fixture 既有） | ① 三个成功返回点（幂等重放早退 / `complete` / `cleanup-pending`）均含 `localTrunkSync`；② 分类正确；③ dirty ⇒ `skipped/dirty` + 本地内容逐字节未变；④ 从函数体抽 `gitRun`/`gitMust` 的 argv（7 个调用点）→ 归一化签名集合恰为 `rev-parse`/`rev-parse --verify`/`symbolic-ref`/`status`/`fetch --prune`/`merge-base --is-ancestor`/`merge --ff-only`，且 argv 元素零 `reset/clean/stash/--force/push`（argv 级；抽取失败或调用点数 ≠ 7 硬失败；判据全文见 §6.2 AC-8 行）；⑤ `changed=false` 重放仍返回且零新 commit；⑥ SKILL/delivery 汇报面含字段（文本断言） |
| `gate-registry.json` | `manifest.files` / `manifest.cases` | **不改**（无新增测试文件；`cases` 是下界，新增用例无需登记） |

### 6.5 FR-9 口径改写清单（四处同口径 + 两处连带）

| 文件 | 现文（要点） | 目标口径 |
|---|---|---|
| `skills/sync/push-progress/SKILL.md` L9 | 「PRD 草稿与 TASK checkpoint 仍为可选节点；需求/架构/代码审批后的阶段终点 checkpoint 为强制完成条件」 | 「阶段终点完成条件 = 评审 PASS 的 checkpoint（由评审者执行，每阶段一次）；审批后不再有 checkpoint 节点，未发布的审批提交由下一阶段评审 checkpoint 或 `merge` 的 publication preflight 搭车承担；发布失败保持当前状态、重跑同一 checkpoint，不重新评审/不重新审批」 |
| `README.md` L65 | 「需求/架构/代码三个阶段审批后的阶段终点 checkpoint 是 Pipeline 完成条件…」 | 同上口径（一句话内）；保留 `crctl checkpoint` 的通用（随时可用）语义 |
| `openwiki/pipelines/overview.md` L114/L116/L118 | 「then a **mandatory approval checkpoint**」「mandatory approval checkpoint」 | 改为「then the review PASS publishes the stage batch (mandatory)」口径；`/coding` 段删除「unified checkpoint → code review」中的统一 checkpoint 前置 |
| `openwiki/pipelines/overview.md` L120-140（mermaid） | `D8["checkpoint"]`、`D12["checkpoint (mandatory)"]` | 删除 `D8`/`D12` 两个节点；`D9`（review-code）PASS 分支直接接 `D10`（human_approval） |
| `openwiki/pipelines/overview.md` L73（replayNodes 例）、L172（contract 第 9 条） | 例含 `checkpoint`；第 9 条为「approval-stage terminal checkpoints are mandatory」 | 例改为 `code fix → test report → baseline re-verify → re-review`；第 9 条改为「stage terminal completion = the review-PASS checkpoint（published by the reviewer once per stage）；no post-approval checkpoint nodes」 |
| `dir-graph.yaml` L178（`pipeline_templates.contract` 第 5 条） | 「按顺序列出修复、证据、checkpoint 与当前评审节点」 | 改为「按顺序列出修复、证据、基线重核与当前评审节点」（S-4）；第 1 条（同步 `_index.yml` counts）与 reviewLoop 重放清单约束保持不变 |

### 6.6 AC-6 延期验证点登记格式（交付说明必填块）

TASK/交付说明按下列字段逐项登记（缺任一项即 AC-6 未通过）：

```text
AC-6 延期验证点
  载体       : <本 CR 交付后新注册的小体量演练 CR-ID（首选）| CR-P1 首链（次选）>
  时点       : 载体走完四个阶段的评审发布与审批之后
  观察项 ①   : 每个 review PASS 后远端存在完整批次（repositories[].confirmed=true ∧ metadataCommit 非空 ∧ 对账通过）
  观察项 ②   : 审批动作不产生任何 checkpoint 委派（评审 PASS 之后的 checkpoint 次数 = 0）
  观察项 ③   : 审批未发布时 merge 给出 MERGE_SOURCE_MISSING/RELEASE_REMOTE_NOT_PUSHED + recovery，同 run 执行后可继续（或首次即通过）
  观察项 ④   : 「为单个 push-progress 单独开 task」次数 = 0
  责任 agent : delivery-agent（记录发布批次与 merge 兜底）；cr-coordinator-agent（记录委派计数）
  关闭触发   : 载体归档，或该链路首次走完
```

### 6.7 FR-11 受影响映射清单（交付说明登记用，可复算）

| 生成物 | 受影响项 | 现在 | 删除后 |
|---|---|---|---|
| `gate_nodes_gen.go#ApprovalGates` | requirement | `…0005` / Seq 5 | `…0005` / **Seq 4** |
| `gate_nodes_gen.go#ReviewGates` | requirement | `…0004` / Seq 4 | `…0004` / **Seq 3** |
| `gate_nodes_gen.go#ApprovalGates` | tech-design | `…0003` / Seq 3 | 不变 |
| `gate_nodes_gen.go#ReviewGates` | tech-design | `…0002` / Seq 2 | 不变 |
| `gate_nodes_gen.go#ApprovalGates` | dev-start | `…0004` / Seq 5 | `…0004` / **Seq 4** |
| `gate_nodes_gen.go#ApprovalGates` | code | `…0010` / Seq 14 | `…0010` / **Seq 11** |
| `gate_nodes_gen.go#ReviewGates` | code | `…0009` / Seq 12 | `…0009` / **Seq 10** |
| `gate_nodes_gen.go#ArchitectureCoreRegistryJSON`（含 `digest`） | 整块 | digest `sha256:5454bfd9…c91cc` | 必变（nodes 5→4） |
| `../tools` registry 输出（`emit-registry.mjs`） | digest | 同上 | 必变（同源） |

登记文本必须二选一（AC-9）：**①** 「已重生成」（含重生成后的 `Source:` SHA 与新 digest）；**②** 「未重生成 ⇒ 重新生成前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用」。本 CR 的实际分支 = ②（`runner.go:56-63` 未设 `AIFIRST_ARCHITECTURE_RUNNER` 即 false；`.github/workflows/*` 对 `gate-nodes` 零引用 ⇒ 未重生成不会让任一侧 CI 变红）。重生成归 owner 部署窗口（PRD §1.3.2），登记 `follow_up`。

## 7. 安全与性能考量

### 7.1 行尾纪律与硬失败（工程纪律 #1，NFR-3）

| 面 | 纪律 |
|---|---|
| FR-3 哈希复算 | 读入先 `\r\n → \n`；composite digest 的集合/排序/行序逐字一致；解析失败硬失败，禁止「匹配不到 → 空集 → 静默通过」 |
| AC-8④ 函数体 argv 抽取 | 抽 `export function reconcileLocalTrunks` 起至下一个顶层 `}` 的函数体文本，再抽其中全部 `gitRun`/`gitMust` 的 argv（第二实参）；函数体抽不到、argv 解析不到、或调用点数 ≠ 7 → 抛错（红），不得降级为空串/空集通过；命令面判据只作用于 argv 元素，**不得**对整段函数体文本做子串匹配 |
| FR-5 测试改写 | 断言一律从 JSON/`_index.yml`/SKILL 文本按行解析（`split(/\r?\n/)`），跨行正则失败即红 |
| 新增 SKILL/README 文本 | 必须通过 `lint-prompts --mode enforce`：不得出现裸 `git` 写命令（R2）、不得手写账本（R1）、不得在 Agent/README 同段出现 3+ 具名状态（R12）、不得手写「下一步」映射（R9）、不得出现退役字段名（R11/R10） |

### 7.2 权限与越权面

- 评审者的能力面**只增不改**：`+push-progress`（Skill）与 `+只读 workspace inspect`；`checkpoint` 与全部写入型子命令仍在 `forbidden`。发布不获得「改业务文件」或「改状态」的能力（`advance` 仅限各 review SKILL 既有要求）。
- 评审者不代作者提交：FR-2 前置失败即停；发布前的干净复查（FR-1 步骤 4）把「全仓 `git add -A`」的输入面锁死在「已验证干净」的初始状态。
- 账本写面不变：`protectedPaths.deny` 零改动；评审者仍只提交 `review-record` 返回的 `files[]`；发布只经 `push-progress`（其内部 `_backlog.yml` latest-checkpoint 由 crctl 独占写）。
- `CONTRACT_DRIFT` 是**技术中止**而非裁决：不改 verdict、不重评、不回退状态，避免对账失败被误用为「改判」通道。

### 7.3 best-effort 与「不可破坏本地」

`reconcileLocalTrunks` 的副作用面被两条规则夹住：① 只对 `dir-graph.yaml#repositories` 的**主 checkout** 操作（不碰 CR worktree、不碰他人分支）；② 只 `fetch --prune` + `merge --ff-only`，dirty/wrong-branch/diverged 一律跳过并如实报告。因此归档不会因为本地在途修改而失败，也不会悄悄丢弃本地内容（AC-8③ 用「逐字节未变」把这条钉死）。

### 7.4 性能与观测

- 调用量：本 CR 在每阶段**减少**一次 checkpoint 节点执行（删除 7 个节点、新增 4 次评审内发布，净减少 3 次节点级发布动作），并在归档尾部增加每仓一次 `fetch --prune`（3 仓、best-effort）。不需要新的性能预算或观测指标（NFR-4：不新增观测指标）。
- 网络面：评审前置与对账均只读本地；发布需要网络（与既有 checkpoint 相同）；`merge` 的 publication preflight 仍是 code 路径唯一的远端相等要求。
- 日志/审计：评审者发布经 `push-progress`，其 `crctl checkpoint` 的 audit/outbox 语义不变；归档新增字段不改 audit 行为。

## 8. Prompt 采纳影响

**N/A（本 CR 不触及触发面）。** 依据：本节按 `write-tech-design` 的条件触发判定——只有当 diff 触及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支或 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny` 时才必填。

- `crctl.mjs`：本 CR **不改**该文件。`crctl archive` 的 dispatch 分支（`case 'archive': return cmdArchive(...)`）与 `cmdArchive` 的返回透传（`ok({ op: 'archive', ...result })`）都已存在，新增字段 `localTrunkSync` 随既有 spread 自动透传；无新增子命令、无新增参数、无新增错误码。
- `rules.json`：`git[]` 白名单与 `protectedPaths.deny` **零改动**（FR-3 的取证只用既有 `rev-parse`；不改 guard deny 面）。因此不存在「crctl 新增能力而某 Skill 该采纳未采纳」的漂移面，本节按规则省略为 N/A。

## SDD-CLOSE 关闭项（PRD 显式延后到 SDD 的设计项）

### SDD-CLOSE-01 FR-10 是否需要拆出（PRD FR-10.9）

**结论：不拆，FR-10 留在本 CR。** 判据：① FR-10 的实现面 = `archiveCr` 三个返回点改经一个局部包装 + 返回值新增一个字段 + 一个既有函数的第二次调用，**代码改动 < 20 行**；② 文档面 = `cr-archive/SKILL.md` 一处分类/输出块 + delivery 汇报面一句，与 FR-1~FR-9 的文本修订同批同风格；③ 测试面 = `archive-tx.test.mjs` 六项用例，复用既有 fixture（`makeWritebackFixture`/`makeNewModeArchiveFixture`）不新建夹具；④ 与其余 FR 无耦合（FR-1~FR-9 零依赖 FR-10；FR-10 零依赖别的 FR）。拆出反而要求同步缩减 AC-8 与 §6 指标、并在交付说明登记拆分——成本高于收益。**不触发 PRD FR-10.9 的缩面动作。**（关闭层覆盖：数据生产/存储/响应 schema/消费/兼容降级五层——`localTrunkSync` 由归档事务尾部产生、只出现在 CLI 返回值与文档面、无持久化、消费方为 delivery-agent 汇报、既有字段兼容面不变。）

### SDD-CLOSE-02 PRD §1.4 事实 22 的 8 项「门禁只依赖本地事实」复核

**结论：8 项逐条复核完成，FR-6 的取舍不需要重新评估。** 逐项（证据均在 tools@`5d5a4ada`）：

| # | 检查项 | 结论 | 证据 |
|---|---|---|---|
| 1 | `crctl workspace inspect` | 只读本地 | `classifyRepoWorkspace`（L660-688）只用 `rev-parse --verify refs/heads|refs/remotes/origin`（本地 ref）+ `worktree list --porcelain` + `status --porcelain`；**无 fetch/ls-remote** |
| 2 | `workspace-freshness`（ahead-only=fresh） | 该 Skill 明确定位为「远端 trunk 新鲜度预检」，其 fetch 只用于**感知 behind**；本地 ahead 状态判定不依赖远端内容 ⇒ 与「审批提交只在本地」不冲突 | `workspace-freshness/SKILL.md`「用途」段（L15）；其节点（`…0016`/`…0017`）本 CR 不删 |
| 3 | 四个 `approve-*` → `crctl approve` | 只读本地 | `approveAndAdvance` 的输入面 = `approval.yml` + `review-annotations/*` + `gates.json`；`release-subjects` 复核走 `verifyReleaseSubjects`（注释明写「不 fetch、不读 remote-tracking ref」） |
| 4 | `review-record` | 只读本地 | `buildReleaseSubjects` 注释「CR-2026-044 FR-02：snapshot 只绑定本地事实，不 fetch、不读 remote-tracking ref」；要求 workspace `healthy` |
| 5 | `writeback-apply` | 只读本地 | 消费 txws 内的 approval/release-subjects（`verifyReleaseSubjects`）与 traceability journal，不做 trunk 相等性校验 |
| 6 | `cr-archive` | **部分依赖远端**（如实登记） | 归档本身必须 push 终态 commit；rejected/withdrawn 路径有 `git fetch origin`（L3616 区域）；本 CR **新增**的尾部 `reconcileLocalTrunks` 亦 fetch。**但归档不是 gate**：它不参与「审批能否完成」「评审能否完成」的判定，不改变 FR-6 的取舍 |
| 7 | `gates.json` | 只读本地 | 声明式文件 + `passCondition` 由 pipeline JSON/annotation 求值 |
| 8 | 唯一远端相等要求 = `merge` 的 publication preflight | 成立 | `mergeCr` L1587-1606：`MERGE_SOURCE_MISSING`/`RELEASE_REMOTE_NOT_PUSHED` 是唯一「远端 requirement ref == 本地 HEAD」判定，且携 `recovery`（checkpoint argv） |

⇒ PRD §1.4 事实 22 的残留面（「未逐条重跑」）**关闭**：唯一依赖远端的是归档（非 gate）与 merge 的 publication preflight（已由 FR-6 兜底）。本表引用的 `workspace-freshness/SKILL.md`、`approveAndAdvance`、`applyWriteback` 三项已按 B-2 回修补登 §6.3（第 47~49 项）。

### SDD-CLOSE-03 S-7：第五份权限面副本的收口（纳入 vs 排除）

**结论：排除，理由见 D-6**，并按 AC-9/交付说明登记 `follow_up` 第一项。收口证据链（三段，缺一不算关闭）：① 无消费者——`grep -rn "cr-prompts-revised"` 在 `*.ts/*.tsx/*.mjs/*.js/*.go/*.md` 面内只命中 `CUSTOM.md`；② 治理定性——`CUSTOM.md#75`：公共 Prompt 唯一事实源为 `tools/agents/`、目录内副本「不再独立演进」、分叉时「以 tools 为准并人工对齐」；③ 范围已冻结——PRD §1.3.1 第 14 行注记明写「不改 `cr-prompts-revised/agent-skill-matrix.yml` 部署副本」。FR-8 的「不得在同一份合同下留第二种读法」由「四处载体同步 + 断言 A/B」覆盖**运行时有效面**，第五份快照由上述人工对齐机制承担。

### SDD-CLOSE-04 S-8：AC-4②③④ 的可定位落点

**结论：逐项点名完成。**

| 项 | 结论 |
|---|---|
| 承载断言的文件 | AC-4②③ 的 tools 侧断言 → `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（单一新断言内同时校验四处载体中的 tools 三处 + 四个 review SKILL 前置）；FR-7 的静态文本断言 → `skills/shared/crctl/scripts/test/contract-scan.test.mjs`（S-3 指定）；AC-4④ → 同 `pipeline-structure.test.mjs`（读 `AGENT-SKILL-MATRIX.md` 的 `## 本 CR 权限变更` 节并断言本 CR 行含 `CR-2026-066` 与 `workspace inspect`） |
| 副本内小节名 | tools：`## 权限事实源`（**不是**「受限 crctl 权限块」——该块在 tools 侧实测不存在）；multica：`## 受限 crctl 权限`（第 35–46 行，允许项 L39–L42、禁止面枚举 L46） |
| 变更行按 CR 编号区分 | `AGENT-SKILL-MATRIX.md` 的 `## 本 CR 权限变更` 节现存数据行（L52）是既有 CR 的行；本 CR 追加行必须显式带 `CR-2026-066`，断言按该编号定位，不与既有行混同 |

### SDD-CLOSE-05 FR-8 的平台部署时序

**结论：登记完成。** 本 CR 只改仓库内文本（tools 三处载体 + multica 1 份副本的 `## 受限 crctl 权限` 节）；平台把 `push-progress` 绑定给 `quality-reviewer-agent`、Prompt 投影与 `gate_nodes_gen.go` 重生成均为 owner 部署动作（PRD §1.3.2 明写部署不在本 CR 范围）。部署前 Multica 侧运行的仍是**旧白名单**（不含 `workspace inspect`）：因此部署窗口必须与本 CR 的 tools 侧改动**成对生效**，否则 FR-2 前置在平台上仍会被旧合同误判（该风险由部署说明与 `follow_up` 登记，不在本 CR 代码面内消除）。

## 9. 批准范围

### scope_in（当前 CR 必须交付的 FR/AC）

- **FR-1~FR-11 全部**，按 §6.1 的落点表；AC-1~AC-10 全部按 §6.2 的映射验收。
- **文件面（29 个交付文件）**：`../tools` 25 个（§1.2 树；含 PRD §1.3.1 第 13 行两个测试文件，外加被 FR-4/FR-5 直接证伪而必须同批改写的 `crctl.test.mjs`、`checkpoint-tx.test.mjs`，以及 S-3 指定的 `contract-scan.test.mjs`——后三者的改写属「既有断言按新事实同步」（AC-2）与「CI 全绿不得签例外」（NFR-1/AC-5），不新增扫描面、不新增断言维度）；`../multica` 4 个 Prompt 部署副本。
- **KB 仓**：本 SDD（`change-requests/CR-2026-066/sdd.md`）与状态/评审记录；不改 KB 的 `specs/`、`delivery/`、`docs/`。
- 交付说明必须包含：AC-6 延期验证点登记块（§6.6）、FR-11 受影响映射与二选一登记（§6.7）、FR-6 取舍（审批提交在下一阶段评审前只在本地、换机需重签一次）、D-6 的 S-7 排除理由、SDD-CLOSE-05 的部署时序说明、**AC-4②③ 的断言 B 核对结论**（被核文件 `../multica/cr-prompts-revised/quality-reviewer-agent.md` 的 `## 受限 crctl 权限` 节，与命中的 token：允许面 `workspace inspect`、禁止面 `checkpoint`）。

### scope_out（明确排除的路径和能力）

- 不引入平台执行层（Runner / approval-continuation / 平台 API）做 checkpoint；不做「审批后可选 checkpoint」节点（不以 `onFail: skip` + 输入端开关变相恢复）。
- 不新增 pipeline 节点、评审维度、账本字段、观测指标（SLO/计数门禁）、crctl 子命令、错误码、Skill 参数、落盘文件。
- 不改 crctl 事务层、状态机、`reviewLoop` 语义（唯一例外：`review-code.reviewLoop.replayNodes` 删除 `…0008` 一项，5→4）。
- 不改 `merge`/`archive`/`writeback` 的业务算法；不改 `recovery` 合同（一切新文本使用结构化 `recovery`）；不复活 `recoverCommand`/`recover_command`。
- 不改 `../multica/cr-prompts-revised/agent-skill-matrix.yml`（S-7）、`../multica/CUSTOM.md`、`aifirst/**`、任何 Go/TS 代码、平台 DB；不重生成 `gate_nodes_gen.go`；不改 `emit-registry.mjs` 与 registry schema。
- 不新增委派 lint 规则或新扫描面；不在 tools 测试内新增跨仓（`../multica`）条件断言。
- 不触碰 `cr-prompts-revised/` 之外的 multica 目录；不改四个 review SKILL 的 Step 2.x 区块（归 CR-P1）、`quality-reviewer-agent#评审判断`（归 CR-P1）、code pipeline 的 dev-start 提示与 `review-dev-plan` 的 acceptance-verifiability 面（归 CR-P2）。

### zero_diff（明确不得改动的调用点/签名）

| 对象 | 零 diff 约束 |
|---|---|
| `crctl.mjs` | 全文件零 diff（不改 dispatch、不改 `cmdArchive`/`cmdCheckpoint`/`advance`/`gate`/`review-record`） |
| `skills/shared/controlled-shell/rules.json` | 零 diff（`git[]` 白名单与 `protectedPaths.deny` 都不动） |
| `dir-graph.yaml#change-request-track.state_machine` / `skills/shared/crctl/gates.json` | 零 diff（不新增状态、转移、门禁） |
| `checkpointCr` / `mergeCr` / `applyWriteback` / `registerCr` 的函数签名与内部逻辑 | 零 diff（FR-10 只加 `reconcileLocalTrunks` 的第二个调用点与 `archiveCr` 的返回字段） |
| `reconcileLocalTrunks(ctx)` 函数体 | 零 diff（不改判据、不改分类、不改行形状）；AC-8④ 的断言据此为 **argv 级**——函数体含 `rows.push(row)` 与 argv 数组形态的 git 命令，文本级子串判据在本行约束下恒假，不得使用 |
| `archiveCr` 既有返回字段与 `phase` 分类、`crctl archive` 退出码 | 零 diff |
| `recovery` 结构化合同字段名（`executable`/`args`/`cwd`/`requiresTTY`/`promptFor`） | 零 diff |
| `emit-registry.mjs`、`gate_nodes_gen.go`、`gate-registry.json` | 零 diff（只登记契约变化） |
| 四个 review SKILL 的参数表 / payload 结构 / 评审维度 / `passCondition` | 零 diff |
| `agent-skill-matrix.yml` 其它 actor 的 `owns`/`can-call`/`forbidden` | 零 diff（只改 `quality-reviewer-agent` 的 `can-call`/`forbidden` 与块注释） |
| KB `specs/`、`delivery/`、`docs/`（含主 checkout 既有 `docs/analysis/` 未提交变动） | 零 diff |
| `change-requests/CR-2026-066/prd.md` | 零 diff（已审批冻结，`sha256(LF)` = `9b43bbfa…`；改哈希即作废人工审批） |

### follow_up（发现但留给后续 CR / owner 的缺口）

1. **S-7 第五份权限面副本的部署窗口对齐**：`../multica/cr-prompts-revised/agent-skill-matrix.yml` L192-194 仍含旧注释（未含 `workspace inspect`）；按 `CUSTOM.md#75` 的「以 tools 为准人工对齐」机制在下一次部署/rebase 核对时处理（本 CR 不改）。
2. **`node-N.md` 命名不一致**：code `…0014`（review-dev-plan）写 `node-3.md`，与其余节点「`node-N.md` 的 N = 节点 id 末段」的惯例不一致（删除 `…0003` 后它成为 `node-3.md` 的唯一写入者，撞名随之消失）。建议后续 CR 统一为 `node-14.md`。
3. **多个 prompt 的 `node-N.md` 历史错位**（例如 code `…0009` 位于下标 11 却写 `node-9.md`）：本 CR 不改名以避免与 CR-P1/P2 的面重叠，登记待后续统一。
4. **四个 review SKILL 的「调用时机」节点序号**（如 `review-code` 写「第 8 节点」而实际位置为第 12 节点、删除后为第 10 节点）：已属本 CR 之前的历史漂移；本 CR 只改其中的 checkpoint 前提句，序号留给后续 CR（或改为不写死序号的措辞）。
5. **`gate_nodes_gen.go` 与 registry digest 的重生成**（§6.7）：owner 部署窗口执行；在此之前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用。
6. **KB `docs/analysis/done/` 的历史分析文档**（如 `tools-local-worktree-gates-remote-publication-boundary.md` 的「阶段终点 checkpoint 是完成合同」段）仍描述审批后阶段终点 checkpoint：属 CR-2026-044 当时的分析产物（`done/`），本 CR 不改写历史分析；如需标注「已被 CR-2026-066 取代」，另起文档 CR。
7. **CR-2026-065 之后的新口径复核（NFR-5 延伸）**：`assertion-sources.mjs` 尚未提供「函数体文本／argv 抽取」派生化 helper，本 CR 的 AC-8④ 在 `archive-tx.test.mjs` 内就地抽取 argv + 硬失败；若后续再有同类断言，可考虑上移为 `assertion-sources.mjs` 的派生函数（本 CR 不新增该 helper 以避免扩大测试支持面）。
8. **AC-6 演练载体的注册**：本 CR 交付后新注册的小体量演练 CR（首选）或 CR-P1 首链（次选）——由协调者按节奏排定。

---

### 修订记录

- 初稿（2026-09-14）：按 PRD（`a7cbd947`，`sha256(LF)` `9b43bbfa…`）与来源附件起草；基线事实在 tools@`5d5a4ada`、multica@`43848770`、KB worktree@`3a553e3b` 三个 HEAD 上逐条核实（初稿为「既有实现依赖与事实」36 项，B-2 回修后 43 项）。三条对 PRD 的技术性细化落点：① FR-3 的 KB 取证链（D-4，基于 checkpoint 的 `kbSourceSha`/metadata-staged-set 合同）；② FR-1 的发布前置复用 `crctl workspace inspect`（不引入裸 `git status`，保持评审者能力面不扩张）；③ FR-4/FR-5 的连带面（`node-N.md` 判定、`node-3.md` 悬空引用核查、四个测试文件的既有断言改写清单）。SDD-CLOSE-01~05 关闭 PRD 与需求评审转交的 5 项延后事项。
- 回修 0.2（2026-09-14，`review-tech-design` cycle 1 / attempt 1 BLOCK → 按 `repair-target=write-tech-design` 回修）：**B-1** 把 AC-8④ 由「函数体文本级子串断言」重定义为 **argv 级命令面白名单**（§6.2 AC-8 行 ④＋可达性、§6.4 `archive-tx.test.mjs` 行、§7.1、§9 zero_diff 同步）——原判据在 §9 明令零 diff 的函数体上恒假（`rows.push(row)` 含 `push`；git 命令为 argv 数组、无字面 `merge --ff-only`）；**B-2** 在 §6.3 补登 4 项正文同类既有事实（`ARCHITECTURE.md`、`skills/shared/crctl/gates.json`、`merge-feature-branch/SKILL.md`、`cr-archive/SKILL.md`），并按「补进清单」处理 SDD-CLOSE-02 引用的 3 项（`workspace-freshness/SKILL.md`、`approveAndAdvance`、`applyWriteback`），清单 36 → 43 项；同批采纳 S-1~S-6（§4.7 三份 tools Prompt、§3.4 CONTRACT_DRIFT 表述、§6.3 PRD 349 行口径、§9 交付说明补断言 B 结论、三处行号精度、§4.2 `healthy ⇒ dirty=false`）。基线事实仍为 tools@`5d5a4ada`、multica@`43848770`；PRD 零触碰（`sha256(LF)` `9b43bbfa…`）。
- 回修 0.3（2026-09-14，`review-tech-design` cycle 1 / attempt 2 BLOCK → 按 `repair-target=write-tech-design` 定点回修）：**B-2 收敛**在 §6.3 再补登 3 项正文同类既有事实——`skills/shared/crctl/scripts/test/archive-tx.test.mjs`（AC-8 六项用例落点与 SDD-CLOSE-01 判据③所据的既有 fixture，文件 783 行、`makeWritebackFixture` L17 / `makeNewModeArchiveFixture` L86）、`../multica/cr-prompts-revised/delivery-agent.md`（FR-7 交付集第四份副本）、`mergeCr`（FR-6 code 路径兜底所据的 publication preflight 语义，定义 L1532 / preflight 块 L1583-1606），并按 S-10 登记 `assertion-sources.mjs`（`follow_up` 第 7 项的取舍依据），清单 43 → **47 项**、全表重编号与两处数值互引同步（其中原「（见 29）」改为显式对象名，避免序号再漂移）；同批采纳 S-7（§1.1 I2 改「`healthy` ⇒ `dirty=false`，更强前置」）、S-8（§6.3 第 21 项行号区间改 L1487-1530）、S-9（§3.2／§6.2／§6.4 统一为「三个成功返回点」，即 `phase` 两值）。基线事实仍为 tools@`5d5a4ada`、multica@`43848770`；PRD 零触碰（`sha256(LF)` `9b43bbfa…`）。
- 回修 0.4（2026-09-14，`review-tech-design` cycle 1 / attempt 3 BLOCK → 协调者按人工出口重置 `review-loop` 后开启 cycle 2，仍按 `repair-target=write-tech-design` 定点回修）：**B-2 收尾**在 §6.3 补登 `cmdArchive`（`crctl.mjs` 定义 L3566 ＋ dispatch L3526 ＋ 透传 L3640；§3.2／§8／§9 三处声明的既有前提），并按评审者点名的两个候选**一并登记**第 22 项（结构化 `recovery` 合同的构造 `buildRecovery` L26 与字段面）与第 25 项（`gitRun` L378／`gitMust` L383，AC-8④ 的抽取锚点），清单 47 → **50 项**、全表重编号与数值互引同步（SDD-CLOSE-02 的「第 44~46 项」→「第 47~49 项」），并在节首明写**收录判据**（口径单一，取消「同类候选不登记」的例外）；同批采纳 **S-11**——第 35 项括注改按 `delivery-agent.md` L44 原文（只有「归档返回 `complete` 或 Skill 明确的完成态」才发最终汇报，汇报项含「归档结果」），把 `cleanup-pending` 与汇报面 `localTrunkSync` 明写为 §4.6.2／AC-8⑥ 的**设计目标**而非既有事实。基线事实仍为 tools@`5d5a4ada`、multica@`43848770`；PRD 零触碰（`sha256(LF)` `9b43bbfa…`）。

## CR-P1：评审输入结构与回修闭合（v0.40 · CR-2026-067）

## 1. 架构概览

### 1.1 设计目标与不变量

本 CR 的技术设计只做一件事：**把「SDD 既有实现事实」的表达与「评审闭合」的判据原位收紧到同一套可判定的承载体上**——事实用一个稳定标识 `dep-N` 唯一表达，判据用两侧同口径的关系式与自洽条件表述。设计遵守 PRD §1.3.1 / §7 的零新增面，落成四条设计不变量：

| # | 设计不变量 | 判据落点 |
|---|---|---|
| I1 | **既有实现事实只有一个定义点**：事实只在 `### 既有实现依赖与事实` 表内定义一次；SDD 正文只以「设计依赖 `dep-N`」引用，不重述当前代码行为。任何"重新陈述"都不再是"另一份口径"，而是判据明确禁止的形态 | FR-1.4 / AC-1② |
| I2 | **`dep-N` 是稳定标识，不是序号别名**：编号按正文首次出现顺序分配、只增不改（删除留空洞、编号不复用），因此正文增删一条事实不会引起整表漂移 | FR-1.2 / AC-1⑥ |
| I3 | **两侧对同一条事实只给一个强度**：`commit SHA` 写侧保持必填、评侧由「并可附」改必填；评侧判据是「引用必须已定义」的**关系式**，不再只是「是否漏列」的**集合比较** | FR-2.2 / FR-2.3 / FR-2.4 / AC-2②③④ |
| I4 | **闭合必须发生在 SDD 阶段**：状态链类 blocker 必须整体重证、批准范围四字段冲突必须在本阶段成为 blocker——不得把同根因问题推迟到 dev-plan | FR-4 / FR-5 / AC-4 / AC-5② |

四条不变量共同把「可判定的承载体」钉在**既有段落内部**（不新增小节、不重编号 Step、不新增任何结构件），这也正是本 CR 的边界（FR-7 / AC-7 / AC-9）。

### 1.2 变更面鸟瞰

**一段四文件的纯文本原位修订**，交付 diff 只有两个 SKILL + 一个既有测试文件 + 一个既有门禁登记文件：

```text
../tools（4 个交付文件；本 CR 的代码实施面全部在此）
  skills/develop/write-tech-design/SKILL.md                    ← FR-1 / FR-4 / FR-5（写侧：3 处段落 + 章节 9 末追加）
  skills/develop/review-tech-design/SKILL.md                   ← FR-2 / FR-5（评侧：Step 2.1 两段 + 批准范围前置块）
  skills/shared/crctl/scripts/test/pipeline-structure.test.mjs ← FR-6.1（L616 目标用例两组 term 原位改写）
  skills/shared/crctl/scripts/test/gate-registry.json          ← FR-6.2（manifest.cases["pipeline-structure.test.mjs"] 35 → 36）
ai-first-platform-docs（KB：只承载本 CR 过程产物，不改 specs/ delivery/ docs/）
  change-requests/CR-2026-067/{prd.md（冻结，零触碰）, sdd.md（本文档）, cr.md + _backlog.yml（crctl 独占写）}
../multica：零 diff（不改任何 Agent Prompt 部署副本、不改 Go/TS 代码、不改 CUSTOM.md）
```

**改动量上界**：写侧 3 处段落原位修订（Step 2.6 证据段 / `### 既有实现依赖与事实` 小节 / 回修模式句）＋ 章节 9 末追加一组判据；评侧 2 处段落原位修订（Step 2.1 两段 + Step 2 批准范围前置块末追加同一组判据）；测试 1 个既有用例的两组 term；门禁登记 1 个数值。**无新增文件、无删除文件、无新增小节、无 Step 重编号。**

### 1.3 依赖方向与分层（不变）

```text
Pipeline（pipeline-templates/*.pipeline.json）   编排 Skill 调用顺序（本 CR 零 diff）
   ↓
Skill（write-tech-design / review-tech-design）  提示词合约 ← 本 CR 唯一的改动层
   ↓
crctl（crctl.mjs + lib/**）                      状态与账本唯一写入执行器（本 CR 零 diff）
```

三条对本设计的硬约束（来自 `ARCHITECTURE.md` §4 与 §5，本轮逐条实读）：

- **Skill 通用、约束归仓（不变量 8）**：新增文本只描述通用写作/评审判据，不出现任何使用方仓库的产品专属约束（表结构、迁移框架、锁原语、DDL 规范）；本 CR 的两份 SKILL 不新增任何产品专属名词。
- **状态单一写者与账本单一写入通道（不变量 1、2）**：本 CR 不新增状态写入口、不新增账本字段；两份 SKILL 的写入仍唯一经 `crctl`（评审批注唯一经 `crctl review-record` 落盘），本 CR 只改判据文本，不改任何写入路径。
- **零第三方依赖（不变量 3）与行尾/硬失败纪律（不变量 4）**：测试改动保持既有 `readFileSync(...).replaceAll('\r\n', '\n')` 读取形态与 `assert.ok` 硬失败语义——断言不命中即红，不引入新依赖、不引入"匹配不到 → 静默通过"的降级。

### 1.4 关键流程

#### 1.4.1 写侧：`dep-N` 的分配、定义与引用（FR-1）

```text
作者写 SDD：
  ① 覆盖判定：断言命中「既有实现（仓库/路径/符号/配置键/接口·协议/数据库结构/模块行为/调用顺序/责任边界）且是方案成立前置条件」
  ② 两遍法：先按正文顺序识别事实 → 分配 dep-N（首轮 dep-1 起；回修轮取「表中现有最大编号 + 1」续编，不得复用空洞）
  ③ 表内定义一次（五要素齐全；commit SHA 为必填 40 位 SHA）
  ④ 正文该处改写成「设计依赖 dep-N」（不重述「当前代码已经如何工作」）
  ⑤ 自检关系式：正文出现的每个 dep-N 都已在表中定义；无法绑定字段的引用列入待核实依赖且不作为方案前提
判据落点：Step 2.6 证据段 + `### 既有实现依赖与事实` 小节（同一段落群内两处原位）
```

#### 1.4.2 评侧：关系式核验与诚实边界（FR-2）

```text
reviewer 核验（Step 2.1，五步，全部在既有段落内）：
  ① 小节存在且名为“既有实现依赖与事实”（显式小节）
  ② 逐项五要素核验（repo / relative path / stable symbol-对象 / commit SHA / 依赖结论），commit SHA 必填（缺失或与取证结果不符 → blocker）
  ③ 关系式：正文出现的 dep-N 必须在表中已定义 —— 未定义即事实引用无承载 → blocker
  ④ 反向：正文出现未被 dep-N 引用承载的当前实现事实 → blocker（集合比较升级为引用关系）
  ⑤ 取证边界不变：不扫描全仓库、不猜测未写出的依赖；取证只读（受控 rev-parse + 文件/稳定符号核验）、不执行 lint/build/test
诚实边界（写进 SKILL 文本）：这是 Prompt 合同，不宣称对自由文本事实的机械识别；不新增 crctl 校验面 / lint 规则 / annotation dimension
```

#### 1.4.3 回修：整体重证 + 不扩散（FR-4）

```text
blocker 触及「状态判定 / 活动性 / 事件顺序 / 空值 / 失败回流」
  → 必须重证该状态链的完整输入维度、分支、可见动作与对应 AC（不是只修被点名的一格）
  → 同一标识符 / 锚点 / testid 在全文只有一个裁决
与既有「不无理由重写已确认方案」的关系：两个方向同时约束——整体重证 ≠ 借重证之名重写无关设计
```

#### 1.4.4 批准范围四字段自洽（FR-5，写手与 reviewer 同判据）

```text
四字段（既有集合）= scope_in / scope_out / zero_diff / follow_up
冲突四型：
  ① scope_in 与 zero_diff 对同一对象同时要求「修改」与「不修改」
  ② 外部治理规则强制修改，未在 SDD 阶段纳入 scope_in / 修订 zero_diff / 给出已有合法出口
  ③ 用 scope_out 隐藏当前交付必须发生的治理修改
  ④ follow_up 承载当前 AC 的必要条件
两侧同判据（逐条同表述、同字段名）→ 评侧任一一型命中 = SDD 阶段 blocker
  （不得留到 dev-plan 再由 review-dev-plan 的 upstream-design-blocker 轨触发）
边界：只针对四字段之间的自相矛盾与必需条件错位，不针对详尽程度
```

#### 1.4.5 断言与门禁基线同步（FR-6）

```text
L616 目标用例：两组 term 原位改写（用例名保持、不新增第二个反向用例、顶层用例数 36 不变）
gate-registry.json#manifest.cases["pipeline-structure.test.mjs"]：35 → 36（与实测顶层用例数一致）
suite-gate 判据语义不变（f.cases < base 即 SUITE_MANIFEST_CASE_DROP），exceptions 保持 []
```

### 1.5 与 PRD §1.5 六条裁定的承接

| PRD §1.5 | SDD 落点 |
|---|---|
| 第 1 条：写侧 `commit SHA` 本就必填，真正收口在评侧 | §6.5-A 保留写侧必填并把依赖形态换成 `dep-N`；§4.2 与 §6.5-E1 把评侧「并可附 `commit SHA`」改为必填（本 CR 唯一的强度变化，兼容性见 §7.3） |
| 第 2 条：`manifest.cases` 登记 35 / 实测 36，采用同步口径 | §4.5、D-5、AC-6③；不在本 CR 改 `suite-gate.mjs` 的判据语义 |
| 第 3 条：`quality-reviewer-agent.md#评审判断` 不存在 ⇒ 该 Agent Prompt 零改动 | §9 `zero_diff`、AC-3②、依赖第 9 项 |
| 第 4 条：`dep-N` 稳定性口径（正文首次出现顺序分配、只增不改、删除留空洞不复用） | I2、§2.2、§4.1、AC-1⑥ |
| 第 5 条：反向 token 约束是**保持性**约束（四个 review SKILL 现状 0 命中）；`write-tech-design` 现存 1 处 `crctl checkpoint` 句**不删** | §4.6、§7.2、AC-2⑦、AC-8② |
| 第 6 条：FR-5 不得把 Step 2.3 的分级边界扩大为「不够详细即 blocker」 | §4.4 末句、AC-5①、依赖第 8 项 |

**附带项（非阻塞 S-1）的处理**：PRD §5 末段「来源 §5.5 的七条验收与上表一一对应」与来源 §5.5 实际的 8 条 bullet 不符。本 SDD **按实际 8 条理解**（AC-1~AC-8 覆盖完整：第 1 条拆为 AC-1/AC-2、第 6 条拆为 AC-7/AC-8，其余逐条对应），并**保留理由**：该处属需求文本、且 `prd.md` 已随需求审批冻结（改哈希即作废审批），修它超出本 CR 的设计范围；判据面不受影响（§6.2 的 AC 映射以 9 条 AC 为准）。

## 2. 数据模型

### 2.1 无新增实体、字段与账本（NFR-2 落点）

本 CR 不新增 pipeline 节点、评审维度名、账本字段、观测指标、crctl 子命令 / flag / 错误码、Skill 参数、落盘文件、lint 规则、CI step。第 2 节因此不定义新实体，只固定三处**既有结构在本 CR 中的精确形状**——它们是实现唯一性的来源，也是 AC-1 / AC-2 / AC-6 的观测面。

### 2.2 `dep-N` 条目（本 CR 唯一改动的"数据形状"）

这是**文本结构**（SKILL 文本内的条目形态），不是账本 / annotation / Skill 参数的字段变更，因此不与 NFR-2 的"零新增字段"冲突：

```text
dep-N                          ← 条目首行：稳定标识，N 为正整数，按正文首次出现顺序分配
  repo: <repository id>        ← 字段 1（必须匹配 resources[].repo）
  relative path: <path from repository root>   ← 字段 2
  stable symbol/对象: <symbol, key, interface, module, behavior, or responsibility>  ← 字段 3
  commit SHA: <40-character SHA>               ← 字段 4（必填）
  依赖结论: <verified current behavior required by this design>                       ← 字段 5
```

| 面 | 目标口径 |
|---|---|
| 标识 | `dep-N` 独立首行；旧 `1. repo: …` 的阿拉伯数字前缀**退役**（`1.` 不再是合法条目起始形态） |
| 字段名 | 五字段名与小节名 `### 既有实现依赖与事实` **逐字不变**（`repo` / `relative path` / `stable symbol/对象` / `commit SHA` / `依赖结论`） |
| 编号生命周期 | 分配（正文首次出现顺序）→ 定义（本节一次）→ 引用（正文「设计依赖 `dep-N`」）→ 删除（留空洞，编号不复用） |
| 排序 | 既有约束「按正文首次出现顺序」保留；表序 = 编号序 = 正文首现序 |
| 消费口径 | `sdd.explicit_existing_dependencies` 仍只指本节的**有序清单**，语义不变 |

### 2.3 既有结构引用（只读，逐字沿用）

| 既有结构 | 位置 | 本 CR 的处理 |
|---|---|---|
| `sdd.explicit_existing_dependencies` | `write-tech-design` 依赖小节 + `review-tech-design` Step 2.1 | 消费口径逐字不变（仍指有序清单） |
| 评审批注结构（`verdict` / `blockers` / `dimensions` / `suggestions`） | `review-annotations/sdd.yml`（经 `crctl review-record` 落盘） | 零改动；本 CR 不新增 dimension、不改 schema |
| `manifest.cases` / `exceptions` | `skills/shared/crctl/scripts/test/gate-registry.json` | 只改一个数值（35 → 36）；`exceptions` 保持 `[]` |
| 用例数下界判据 | `skills/shared/crctl/scripts/test/suite-gate.mjs` | 零改动（判据语义"低于登记值即红"保持） |

### 2.4 状态与门禁（不新增状态、不新增转换）

本 CR 只消费既有声明，不新增任何状态或转换（口径以 `../tools/dir-graph.yaml#change-request-track.state_machine` 为唯一事实源）：

```text
requirement-approved → tech-designing             trigger: write-tech-design
tech-designing       → tech-design-review-pending trigger: write-tech-design-complete
tech-design-review-pending → tech-designing        trigger: review-tech-design:block -> write-tech-design
tech-design-review-pending → tech-design-reviewed  trigger: approve-tech-design（人工，非本节点）
```

门禁事实（`skills/shared/crctl/gates.json`）：`tech-design-review-pending` 的门禁是 `sdd.md` 存在（`fileExists`）；`tech-designing` 的门禁是 `approval.yml#requirement`。本 CR 不改 `gates.json`，落盘 `sdd.md` 即满足待评门禁。

## 3. 接口契约

### 3.1 Skill 调用契约：零变化（PRD §1.3.3）

| 契约面 | `write-tech-design` | `review-tech-design` |
|---|---|---|
| 参数表 | `cr_id` / `tech_context` / `operational_workspace` / `resources` / `review_feedback` / `self_repair_attempt` 不变 | `cr_id` / `workspace` / `resources` / `reviewer` / `review_feedback` / `self_repair_attempt` 不变 |
| 落盘路径 | `change-requests/{cr_id}/sdd.md` 不变 | canonical 仍为 `review-annotations/sdd.yml`（`crctl review-record` 独占写） |
| 允许的状态转换 | `requirement-approved → tech-designing → tech-design-review-pending` 不变 | PASS 保持待评状态、BLOCK 回退 `tech-designing` 不变 |
| 失败码 / 与 crctl 的写入边界 | 不变 | 不变 |

本 CR 改的是两份 SKILL **正文内的写作与评审判据**（Prompt 合同），不是调用契约——因此 §1.3.3 的四查（幂等 / 权限 / 错误闭包 / 副作用）对本 CR 为 N/A 的结论不受本设计影响。

### 3.2 crctl CLI 契约：零变化

`skills/shared/crctl/scripts/crctl.mjs`、`scripts/lib/**`、`gates.json`、`rules.json` 零 diff：不新增/删除子命令与 flag，不改任何 JSON 输出形状、退出码、错误码与调用者约束。本 CR 自身的过程写入只用既有子命令（`crctl advance` / 既有受控 git 提交）。

### 3.3 文本合同面（本 CR 的"接口"）

本 CR 的"接口"是**两份 SKILL 的目标文本 + 一处既有断言**，全部为逐字可核对的文本合同，目标文本见 §6.5：

| 锚点 | 文件 | 目标（§6.5 编号） |
|---|---|---|
| Step 2.6 既有实现证据段 | `write-tech-design/SKILL.md` | A |
| `### 既有实现依赖与事实` 小节（含固定结构块） | 同上 | B |
| 回修模式句 | 同上 | C |
| Step 2 章节 9「批准范围」末追加 | 同上 | D |
| Step 2.1 既有实现依赖核验两段 | `review-tech-design/SKILL.md` | E1 |
| Step 2「批准范围前置」引用块末追加 | 同上 | E2 |
| L616 目标用例两组 term | `pipeline-structure.test.mjs` | F |
| `manifest.cases["pipeline-structure.test.mjs"]` | `gate-registry.json` | G |

### 3.4 错误语义

本 CR 不新增错误码、不改任何退出码。唯一与"错误语义"相关的既有面是**测试断言的硬失败语义**：term 不命中即 `assert.ok` 失败（红灯），不存在"匹配不到 → 空集 → 静默通过"的降级路径（NFR-5）；本 CR 的 term 改写保持这一形态。

### 3.5 HTTP / IPC / 事件契约：N/A

本 CR 不改任何 endpoint / request / response、不改 IPC、不改事件接口（与 PRD §1.3.3 的四查 N/A 结论一致）。

## 4. 关键算法与流程

### 4.1 写侧 `dep-N` 分配算法（FR-1.2 / FR-1.3）

```text
procedure assign_dep_ids(sdd_body, dep_table):
    next = max(id_of(entry) for entry in dep_table) + 1     # 首轮 dep_table 为空 → next = 1
    for fact_assertion in scan_in_body_order(sdd_body):     # 按正文顺序扫描，不去重跨段重复引用
        if not is_existing_implementation_fact(fact_assertion):
            continue                                        # 目标契约/新增能力设计不分配 dep-N
        if fact_assertion is already defined in dep_table:
            rewrite(fact_assertion, "设计依赖 dep-N_of(that_entry)")
            continue
        id = "dep-" + next; next = next + 1
        dep_table.append(entry(id, repo, relative_path, stable_symbol, commit_sha(40), conclusion))
        rewrite(fact_assertion, "设计依赖 " + id)            # 正文不重述「当前代码已经如何工作」
```

不变量（评审侧可判定）：

- `∀ ref ∈ dep_refs(body): ref ∈ ids(dep_table)`（引用必须已定义）；
- 回修轮只**续编**（`next = max + 1`），不重编号、不复用空洞——保证同一 `dep-N` 在全文只指向一条事实；
- 无法绑定五要素中任一项的引用 → 待核实依赖（不作方案前提）；`N/A` 只在两处均无依赖时可用。

### 4.2 评侧核验算法（FR-2）

```text
procedure verify_existing_dependencies(sdd, resources):
    section = find_explicit_section(sdd, "既有实现依赖与事实")
    if section is null: blocker("缺少显式依赖小节")            # 既有判据保持
    for entry in section.ordered_entries():
        assert_five_fields(entry)                              # repo / relative path / stable symbol-对象 / commit SHA / 依赖结论
        if entry.commit_sha is missing or not 40-hex:
            blocker("commit SHA 缺失或非 40 位")                # 旧「并可附」措辞零残留是本条的可机械核对面
        verify(entry.repo, entry.relative_path, entry.stable_symbol, entry.conclusion)  # 受控只读：rev-parse + 文件/符号核验
    for ref in dep_refs(sdd.body):
        if ref not in ids(section): blocker("正文引用的 dep-N 未定义")   # 关系式，新增
    for fact in existing_facts(sdd.body):
        if fact not carried_by_dep_ref(fact): blocker("正文出现未被 dep-N 引用承载的当前实现事实")  # 集合比较 → 关系式
    # 边界（保持）：不扫描全仓库、不猜测未写出的依赖、不执行 lint/build/test
    # 诚实边界：判定属评审判断，本规则是 Prompt 合同，不宣称对自由文本事实的机械识别
```

### 4.3 回修整体重证（FR-4）

触发面（blocker 文本命中任一）：状态判定 / 活动性 / 事件顺序 / 空值 / 失败回流。要求：

1. 重证该状态链的**完整输入维度、分支、可见动作与对应 AC**——不是只补被点名的那一格；
2. 同一标识符、锚点或 testid 在全文只有一个裁决（同对象不得两处裁决）；
3. 未受该根因影响的已确认方案不得重写（"不扩散"方向同时生效）。

与既有 `reviewLoop`（`maxAttempts=3`、`replayNodes=write-tech-design → review-tech-design`）的关系：本 CR **不改**轮次语义、不新增 blocker 计数或轮数门禁，只改回修动作的判据文本。

### 4.4 批准范围自洽（FR-5）

写手侧与 reviewer 侧使用**同一组判据、同一表述、同一字段名**（§6.5-D 与 §6.5-E2 的 ①~④ 逐字相同）。评侧命中任一一型即形成 blocker，且必须在本阶段形成：

```text
① scope_in ∩ zero_diff 对同一对象同时要求「修改」与「不修改」        → blocker
② 外部治理强制修改未纳入 scope_in / 未修订 zero_diff / 未给出已有出口 → blocker
③ scope_out 被用来隐藏必须发生的治理修改                            → blocker
④ follow_up 承载当前 AC 的必要条件                                  → blocker
禁止留到 dev-plan 的 review-dev-plan:upstream-design-blocker 轨
```

**边界（PRD §1.5 第 6 条）**：判据只针对四字段之间的自相矛盾与必需条件错位（可判定），**不**针对详尽程度——不得把 `review-tech-design` Step 2.3 的既有分级边界（"缺少里程碑 / TASK owner / 任务拆分 / 工时 / 完成标志 / `cmd-NN` / cwd-timeout / 具体测试文件或完整执行命令不得作为 blocker"）扩大为"范围字段写得不够详细即 blocker"。

### 4.5 测试断言与门禁基线同步（FR-6）

1. L616 目标用例的两组 term 原位改写（§6.5-F）：用例名保持 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确`，**不新增第二个反向用例**，顶层用例数保持 36；
2. `gate-registry.json` 的 `manifest.cases` 由 35 同步为 36（与实测一致，§6.5-G）；
3. `suite-gate.mjs` 判据语义（`f.cases < base` 即 `SUITE_MANIFEST_CASE_DROP`）**不改**，`exceptions` 保持 `[]`；
4. CI 六个 step（双平台）全绿；`contract-scan` 的 `RETIRED_RECOVERY` 整树零命中。

### 4.6 零 diff 面与保持性约束（FR-7 / AC-8）

- **零 diff 面**见 §9；其中 AC-8 的核心是"CR-2026-066 的既有断言未被放宽"：四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账四要素（`phase` / `batchId` / `repositories[]` / `metadataCommit`）、BLOCK 分支不发布、权限面四处载体全部逐字保留。
- **反向 token 保持性**：本 CR 在 `review-tech-design` 中的**新增文字**不得出现 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（现值四 token 各 0 命中，§6.5-E1/E2 逐字自查通过）；`write-tech-design` 现存 1 处 `crctl checkpoint` 提交口径句**不删**（不在 CR-2026-066 的 `REVIEW_SKILLS` 反向断言面内）。

## 5. 技术选型与替代方案

### D-1 承载体：原位收紧既有 Step 2.x 判据（选定）

- **Decision**：两组判据全部写进既有段落内部——写侧 Step 2.6 证据段、依赖小节、回修句、章节 9；评侧 Step 2.1 两段、批准范围前置块。
- **Context**：三项问题的共同根因是"判据缺一个可判定的承载体"；既有 Step 2.x 已是唯一被两侧消费的判据面（`review-tech-design` 只读 `sdd.explicit_existing_dependencies` 指向的有序清单）。
- **Alternatives**：（a）新增独立小节承载 `dep-N` 规则 → 否决：违反 FR-7.1/FR-7.4 与 NFR-3（会出现新旧两套判据并存）；（b）新增 annotation dimension 或 crctl 校验面把判据机械化 → 否决：FR-2.6 明写本规则是 Prompt 合同、不宣称机械识别，且违反 FR-7.3/FR-7.4；（c）把规则复制进 `tools/agents/quality-reviewer-agent.md` → 否决：FR-3.2 要求该 Prompt 零 diff（唯一事实源是 review SKILL）。
- **Consequences**：判据的"存在性"可由文本断言机械核对（AC-1/AC-2/AC-4/AC-5），"是否真命题"仍由 reviewer 判断——这正是 PRD 的取舍。

### D-2 标识形态：`dep-N` 独立首行（选定）

- **Decision**：条目以 `dep-N` 开头，五字段改为缩进两格；旧 `1. repo:` 前缀退役。
- **Context**：既有"位置序号"（`1.` `2.`）不是身份——正文增删一条即整表漂移，reviewer 无法用一个稳定 key 交叉核对。
- **Alternatives**：（a）保留 `1. repo:` 序号 + 另加 `dep-N` 别名 → 否决：两个编号面并存，漂移面翻倍，违反 NFR-3；（b）改成 `<dep-N> repo: …` 单行形态 → 否决：会改动字段名可见形态，扩大 diff 与断言面；（c）用 `D-1` / `DEP-001` 等别名 → 否决：与 PRD FR-1.3 明文形态冲突且无收益。
- **Consequences**：`dep-N` 成为全文唯一裁决点（AC-4③），测试 term 组新增 `dep-N`（AC-6①）。

### D-3 评侧判据：引用关系式（选定）

- **Decision**：判据从"正文同类事实是否漏列"的集合比较，升级为"正文引用是否由 `dep-N` 承载"的关系式；旧表述作为该关系式的退化面在新文本中显式保留（"判据从…升级为…"）。
- **Context**：集合比较缺一条可判定的关系式——同一份合同下，作者按写侧写、评审按评侧放宽，闭合无从机械判定。
- **Alternatives**：（a）只把评侧 `commit SHA` 改必填、不动判据形态 → 否决：解决不了"缺关系式"的根因（来源 §5.1.2）；（b）让 reviewer 做全仓扫描来发现漏列 → 否决：PRD 明确边界"不扫描全仓库、不猜测未写出的依赖"。
- **Consequences**：评侧新增两条可判定关系（引用已定义、事实被引用承载），并有明确的诚实边界（Prompt 合同、非机械门禁）。

### D-4 编号生命周期：只增不改 + 删除留空洞（选定）

- **Decision**：`dep-N` 按正文首次出现顺序分配、只增不改；删除的条目留空洞、编号不复用。
- **Context**：来源只写"稳定标识"，未写生命周期；不钉死则 `dep-N` 只是把"序号漂移"换成另一个编号面。
- **Alternatives**：（a）每次修订重编号 → 否决：重编号即漂移，与"稳定标识"意图相反；（b）回收空洞编号 → 否决：同一编号会在两次修订间指向不同事实，破坏评审可对比性；（c）追加式编号但允许重排序 → 否决：与既有"按正文首次出现顺序"排序约束冲突。
- **Consequences**：表序 = 编号序 = 正文首现序，评审可按序核对（AC-1⑥）。

### D-5 `manifest.cases` 收口方向：同步为实测值（选定）

- **Decision**：把 `manifest.cases["pipeline-structure.test.mjs"]` 由 35 同步为 36（与实际顶层用例数一致）。
- **Context**：`suite-gate` 的判据是下限（`f.cases < base` 才红，`manifest.cases` 只校验正整数），因此多出的 1 条用例（CR-2026-066 追加）不触发红灯，但登记值与实际不一致本身就是事实缺口；来源 §5.5 的验收写"已同步"。
- **Alternatives**：（a）保留 35 并注明语义是下界 → 否决：与来源验收的"已同步"相悖，且未来用例回落到 35 条时红灯的判据会变得不可解释；（b）把 `suite-gate.mjs` 判据改为严格相等 → 否决：FR-6.4 明写不改判据语义、不新增门禁机制。
- **Consequences**：交付 diff 增加一个数值改动（PRD §1.3.1 第 4 行已登记为条件性文件）。

### D-6 本 CR 自身 SDD 的依赖表形态：沿用实施前的编号列表（选定）

- **Decision**：本文档 §6.3 仍使用**实施前生效**的编号列表形态（`1. repo: …`，五要素齐全、`commit SHA` 必填），并在 §6.3 节首写明该取舍；正文以显式事实陈述引用，不采用尚未生效的 `dep-N` 引用式。
- **Context**：目标 `dep-N` 形态在本 CR **实施落地后**才成为合同；PRD §1.3.3 已确立"评审判据只对评审发生时的 SKILL 版本生效"。
- **Alternatives**：（a）提前使用 `dep-N` 形态 → 否决：会以尚未生效的合同自我验收，且正文若只写"设计依赖 `dep-N`"将无法陈述"当前文本是什么"这一本 CR 的核心输入；（b）不写依赖表 → 否决：现行 Step 2.6 明确要求，且 reviewer 会按现行合同核验。
- **Consequences**：本 SDD 与目标文本（§6.5 逐字给出）之间的差异是**合同的时序差**，不是判据并存：`dep-N` 形态自实施提交起对其后的 SDD 生效。

## 6. FR 到技术实现映射

### 6.1 FR 逐条映射

| FR | 设计落点 | 承载文件 | 对应 AC |
|---|---|---|---|
| FR-1 既有实现事实唯一表达 | §2.2 条目形状 + §4.1 分配算法 + §6.5-A/B | `write-tech-design/SKILL.md` | AC-1 |
| FR-2 评侧 `dep-N` 核验与两侧同口径 | §4.2 核验算法 + §6.5-E1 | `review-tech-design/SKILL.md` | AC-2 |
| FR-3 首轮全量检查保持原样 | §4.6 保持性约束 + §6.4 零改动核对清单 | `review-tech-design/SKILL.md` Step 2.2 / `agents/quality-reviewer-agent.md` | AC-3 |
| FR-4 状态链整体重证 | §4.3 + §6.5-C | `write-tech-design/SKILL.md` | AC-4 |
| FR-5 批准范围四字段自洽 | §4.4 + §6.5-D/E2 | 两侧 SKILL（同判据） | AC-5 |
| FR-6 测试断言与门禁基线同步 | §4.5 + §6.5-F/G | `pipeline-structure.test.mjs` / `gate-registry.json` | AC-6 |
| FR-7 边界与零新增 | §4.6 + §9（scope_out / zero_diff） | 交付 diff 面本身 | AC-7 / AC-9 |

### 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §6.5-A（Step 2.6 证据段）＋ §6.5-B（依赖小节固定结构） | 小节存在且采用 `dep-N` 固定结构（`dep-N` + 五字段齐全）；正文规则含"只写设计依赖 `dep-N`、不重述当前代码行为"与"事实只在该表定义一次"；`commit SHA` 为必填 40 位 SHA；无法绑定字段者列入待核实依赖且不得作为方案前提；`N/A` 仅在两处均无依赖时可用；编号稳定性口径（首次出现顺序分配、只增不改）已写明 | 六项判据全部落在**同一段落群**的文本上，可由文件读出直接核对；不依赖运行时状态；编号稳定性是写作侧机械规则（§4.1），不要求 reviewer 机械复核 |
| AC-2 | §6.5-E1（Step 2.1 两段） | ① 五要素核验在文；② 含"正文只能引用存在的 `dep-N`"；③ 含"未被 `dep-N` 引用承载的当前实现事实 → blocker"；④ `commit SHA` 必填且旧「并可附 `commit SHA`」措辞零残留；⑤ 保留"不扫描全仓/不猜测未写出的依赖"边界并写明 Prompt 合同、不宣称机械识别；⑥ Step 编号集（1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6）全部存在；⑦ 新增文字不含四个反向 token | ①~⑤ 为文本断言；④ 的"零残留"是全局替换判据（`grep -c '并可附'` 应为 0）；⑥⑦ 分别由节标题集合与 token 扫描核对；均可在 CI 内执行，无外层依赖 |
| AC-3 | §4.6 保持性清单 + §6.4 零改动面 | ① Step 2.2 首轮全量句逐字存在；② `agents/quality-reviewer-agent.md` 相对基线零 diff（`##` 小节集合仍为 7 个）；③ 交付物中不存在"首轮漏检"账本计数、`本轮新增：` 不作为流程质量统计、无评审轮数数字承诺 | ①② 是 CR-2026-066 既有断言的保持性核对（该文件不在本 CR diff 面内）；③ 由"本 CR 不新增任何账本字段/观测指标"（§2.1、§9 scope_out）保证 |
| AC-4 | §6.5-C（回修句原位扩写） | 该段同时含四项判据：状态链类 blocker 必须重证完整输入维度/分支/可见动作/对应 AC；不得只修被点名的一格；同一标识符/锚点/testid 全文只有一个裁决；未受根因影响的已确认方案不得重写 | 四项全部写进**同一句群**；既有"不无理由重写已确认方案"句保留作"不扩散"方向的判据，两方向同时成立 |
| AC-5 | §6.5-D（写侧章节 9）＋ §6.5-E2（评侧前置块） | ① 两侧均含四条同判据且表述与字段名一致；② 评侧要求冲突在 SDD 阶段成为 blocker、不留到 dev-plan upstream；③ 无第五字段、无新账本文件、无新评审维度名、无新状态 | ① 由两侧 ①~④ 段落**逐字相同**保证（可 diff 核对）；② 写在评侧同段；③ 由 §9 与交付 diff 面保证 |
| AC-6 | §6.5-F / §6.5-G + §4.5 | ① 目标用例仍在且两组 term 已改 `dep-N` 口径（写侧覆盖小节名 + `dep-N` 固定结构 + 五字段；评侧覆盖显式小节 + 有序清单 + `dep-N` 引用规则 + `commit SHA` 必填 + `sdd.explicit_existing_dependencies` + 正文漏列）；② 顶层用例数不减少（基线 36）、无第二个反向用例；③ `manifest.cases` 与该文件实际顶层用例数一致（36）；④ `suite-gate --run` 全绿、`exceptions` 为空数组；⑤ `RETIRED_RECOVERY` 整树零命中 | ①~③ 可由测试文件与登记文件直接读出；④ 由既有门禁运行；⑤ 由既有 `contract-scan` 用例运行；本 CR 不新增测试脚手架，全部复用既有入口 |
| AC-7 | §1.2 变更面 + §9（scope_in / scope_out / zero_diff） | ① diff 只含 4 个登记文件；② `crctl.mjs`/`lib/**`/`gates.json`/`pipeline-templates/**`/`agent-skill-matrix.yml`/`AGENT-SKILL-MATRIX.md`/`tools/agents/**`/`../multica/**` 零 diff；③ 无新 annotation dimension/账本字段/评审指标/Pipeline 节点/crctl 子命令·flag·错误码/Skill 参数/落盘文件 | ① 可用 `git diff --name-only` 枚举；② 为 §9 `zero_diff` 表的直接核对；③ 由变更面本身证明（diff 只有 4 文件） |
| AC-8 | §4.6 + §6.4 | CR-2026-066 既有断言实施后仍全绿且未被放宽：四个 review SKILL 的 Step 1.0 / Step 5 四要素逐字保留；四 SKILL 不含 `crctl checkpoint` 与三个 `push-progress`/`checkpoint` 短语；`REVIEW_SKILLS` 四处载体（clean 前置 / PASS 发布 / 对账 / BLOCK 不发布）零改动 | 全部由既有断言 A/B/C/D 覆盖（`pipeline-structure.test.mjs` L656 用例），本 CR 只改 L616 用例；"未放宽"体现为**断言未删未弱**（本 CR 不触碰该用例） |
| AC-9 | §9 + §6.6 | ① 交付 diff 不含 CR-P2 面（`write-dev-plan` / `write-dev-tasks` / `review-dev-plan` 与 `code-implementation.pipeline.json` 的 dev-start 提示）；② 实施与交付期 `_backlog.yml` 在途条目只有本 CR、CR-2026-063/064/065/066 均 `archived`；③ 只收紧不放宽：Step 2.1 的 AC 闭环伪码、Step 2.3 的分级边界与固定前缀句全部保留 | ① 由 diff 文件集枚举；② 由 `crctl status` 查询（可复算）；③ 由 §6.4 的零改动核对清单 + 交付前 diff 复核保证 |

**反查（§6.2 → §3/§4/§6.5 正文）**：每条 AC 的设计落点都能产出所写可观测结果，且不存在"关键前置条件提前过滤目标"的情形：

- AC-1/AC-2 的判据落在**同一文件的两处既有段落**上，不存在跨仓或运行时前置；`commit SHA` 必填的强度变化反向兼容（写侧本就必填，评侧只增不改）。
- AC-2⑥ 的 Step 编号集合是**静态文本事实**，不因本 CR 的段落增删而变（不新增标题层级）。
- AC-5① 用"两侧逐字相同"作为判据，规避了"同判据不同表述"的判定争议；AC-5③ 用"无第五字段/无新文件/无新维度名/无新状态"把扩大面挡在判据之外。
- AC-6④⑤ 依赖的既有门禁入口（`suite-gate --run`、`contract-scan`）在本 CR 中零 diff，不构成不可达前置。
- AC-9② 的"不并发"由已完成事实满足（063~066 均 `archived`，`_backlog.yml` 在途仅本 CR）；其证据在 KB，故列为过程核对项而非 tools 内断言。
- 唯一需要额外证成的是 AC-2④ 的"旧措辞零残留"——它是**全局**判据（`并可附` 计数为 0），可通过 §6.5-E1 的整段替换保证（替换的是包含该措辞的完整句子，不保留任何副本）。

### 6.3 既有实现依赖与事实

**收录判据（单一口径，与 CR-2026-066 SDD 同族）**：SDD 正文引用到的任一既有实现事实都必须入册——① 设计陈述或判据的成立前提（模块行为、文本形态、返回形状、调用顺序、抽取锚点）；② 本 CR 直接修改的既有文本；③ §9 `zero_diff` 中**设计所依赖的**既有实现文本（§9 其余零 diff 对象由该表自身与 AC-7②/AC-9① 的 diff 枚举直接核对，不逐项入册）；④ SDD-CLOSE 的证据。正文出现但未列入本清单的同类事实引用视为漏列。

**排序**：按仓与依赖面分组，组内按正文首次出现顺序排列。

**本 CR 自身依赖表的形态（D-6）**：本节使用**实施前生效**的编号列表形态（五要素齐全、`commit SHA` 必填）。目标 `dep-N` 形态（§6.5-B）自本 CR 实施提交起对其后的 SDD 生效；PRD §1.3.3 已确立"评审判据只对评审发生时的 SKILL 版本生效"，两者是合同的时序差，不是两套判据并存。

**SHA 取证口径**：`tools` 条目的 `commit SHA` = 本 CR tools worktree HEAD `7094e492822594b971699924478ba27ccf612c42`（= `tools` trunk）；`multica` 条目 = `5c1880f2125e73733b1a5bfc7501db310ab7f584`（= `multica` trunk）；KB（`ai-first-platform-docs`）条目 = 起草时 KB worktree HEAD `31db6d201f081d6e78a5fa73e6676d4fa55d319e`（与 CR-2026-066 SDD 的 KB 取证同口径），各 KB 过程产物的**引入提交**另在依赖结论中给出（`prd.md`→`d4f366fa`、评审三件套→`3b74b5ac`、`approval.yml`→`14c2b6c1`）。

1. repo: tools
   relative path: ARCHITECTURE.md
   stable symbol/对象: `## 4. 分层与依赖方向`（Pipeline → Skill → crctl「依赖只朝下」）与 `## 5. 硬不变量`（不变量 1 状态单一写者、2 账本单一写入通道、3 零第三方依赖、4 行尾与硬失败纪律、8 Skill 通用约束归仓）
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: §1.3 的三条硬约束与 §4.6 的保持性论证均取自本文件（本轮实读全文）；四条设计不变量不得与之冲突，本 CR 不新增层级、不新增写入口与账本文件。
2. repo: tools
   relative path: skills/develop/write-tech-design/SKILL.md
   stable symbol/对象: Step 2.6 既有实现证据段（L113）：五要素必填清单（含 `commit SHA`）、待核实依赖、`N/A` 可用条件、「核验必须覆盖正文所声称的实际行为」、「现有/既有/复用/无需新增」断言的前提资格约束
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-1.1 的「覆盖面不缩小」以该段为基线（§6.5-A 只在该段内插入三处判据，不改五要素清单与既有边界句）；也是 AC-1③ 强度口径的来源。
3. repo: tools
   relative path: skills/develop/write-tech-design/SKILL.md
   stable symbol/对象: `### 既有实现依赖与事实` 小节（L115-131）：固定结构块 `1. repo: …`（编号列表形态）、排序约束「正文首次出现顺序」、`sdd.explicit_existing_dependencies` 消费口径句、`N/A` 句、回修模式句（L129）、SDD-CLOSE 义务段（L131）
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-1.2/FR-1.3/FR-1.6/FR-1.7 与 FR-4 的修订面同在这一个小节内；§6.5-B（固定结构与消费口径句）与 §6.5-C（回修句）以它为基线，SDD-CLOSE 义务段保持零 diff。
4. repo: tools
   relative path: skills/develop/write-tech-design/SKILL.md
   stable symbol/对象: Step 2 章节 9「批准范围（契约必填章节，CR-2026-057 FR-5/FR-6）」（L88-90）：四字段承载与"空字段须写 `无`/`N/A`"的存在性判据、`approve-tech-design` 后只读、`review-dev-plan` 双轨回上游
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-5 写侧落点；§6.5-D 在该段末**原位追加**四条自洽判据，既有存在性判据与只读语义逐字保留（AC-9③ 的"只收紧不放宽"核对面之一）。
5. repo: tools
   relative path: skills/develop/write-tech-design/SKILL.md
   stable symbol/对象: Step 1 第 2 条提交口径句（L48，含 `crctl checkpoint` 的唯一 1 处）
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: §1.5 第 5 条与 AC-8② 的"不删该句"事实依据（实测 `grep -c 'crctl checkpoint'` = 1）；该句不在 CR-2026-066 的 `REVIEW_SKILLS` 反向断言面内（依赖第 12 项）。
6. repo: tools
   relative path: skills/develop/review-tech-design/SKILL.md
   stable symbol/对象: Step 2.1 既有实现依赖核验段（L87）：显式小节名、有序清单、四要素 + 旧措辞「并可附 `commit SHA`」、`sdd.explicit_existing_dependencies` 消费边界、「不扫描全仓库或临时猜测」、交叉检查「正文同类事实是否漏列」
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-2.1~FR-2.4 与 FR-2.6 的修订面；§6.5-E1 以该段为基线（旧「并可附」措辞在本 CR 后必须零残留）。
7. repo: tools
   relative path: skills/develop/review-tech-design/SKILL.md
   stable symbol/对象: Step 2.1 核验手段段（L89）：受控只读取证 `crctl git rev-parse HEAD`、文件/稳定符号核验、业务 blocker 的证据面（repo/SHA/path/symbol/conclusion）、资源缺失为技术失败、「正文存在但未列入依赖清单的同类事实引用形成 blocker」、`N/A` 句、「不执行 lint/build/test」
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-2.1/FR-2.3/FR-2.4 的取证与边界基线；§6.5-E1 只把其中的判据句升级为 `dep-N` 引用关系，取证手段与"不执行 lint/build/test"等边界逐字保留。
8. repo: tools
   relative path: skills/develop/review-tech-design/SKILL.md
   stable symbol/对象: Step 2 引用块「批准范围前置（CR-2026-057 FR-5/AC-5）」（L58）与 Step 2.3 分级段（L95-104）的固定前缀句
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-5 评侧落点（§6.5-E2 在 L58 引用块末原位追加同判据）；Step 2.3 的分级边界是 FR-5 判据的**上限**（§4.4 末句），零 diff。
9. repo: tools
   relative path: skills/develop/review-tech-design/SKILL.md
   stable symbol/对象: Step 2.2 首句（L93）与 Step 编号集合（Step 1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6）
   commit SHA: 7094e492822594b971699924478ba27ccf612c42
   依赖结论: FR-3.1 与 AC-3① 的零改动核对对象（逐字断言）；FR-7.2 与 AC-2⑥ 的编号核对面（本 CR 不重编号、不新增标题层级）。
10. repo: tools
    relative path: agents/quality-reviewer-agent.md
    stable symbol/对象: `##` 小节集合（7 个：角色定位 / 意图与路由 / 独立会话路径 / 人工决策边界 / 权限事实源 / 发布职责与搭车硬规则 / 约束）；`## 评审判断` 小节不存在
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: FR-3.2 与 AC-3② 的零 diff 判据与"判据唯一事实源 = review SKILL"的成立依据（§1.5 第 3 条复核结论）；`评审判断` 一词仅出现在 `## 意图与路由` 一句内，来源 §5.2 的删除锚点确实不存在。
11. repo: tools
    relative path: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
    stable symbol/对象: L616 目标用例 `CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确`（写侧 8 项 term / 评侧 4 项 term）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: FR-6.1 的原位改写对象；§6.5-F 给出两组 term 的目标形态，用例名与结构保持。
12. repo: tools
    relative path: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
    stable symbol/对象: 顶层用例计数（`^test(` 实测 36 条、TAP `1..36` 全绿）与 `REVIEW_SKILLS` 常量（L636-641，四个 review SKILL）+ CR-2026-066 断言用例（L656，A/B/C/D）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: AC-6② 的基线（不减少、不新增）与 AC-8 的保持性核对面；`write-tech-design` 不在 `REVIEW_SKILLS` 中，是该文件现存 `crctl checkpoint` 句不在反向断言面内的直接依据（依赖第 5 项）。
13. repo: tools
    relative path: skills/shared/crctl/scripts/test/gate-registry.json
    stable symbol/对象: `manifest.cases["pipeline-structure.test.mjs"] = 35`（L38）与 `exceptions: []`（L243）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: FR-6.2 的唯一改动点（35 → 36）与 FR-6.3 的零例外约束（本 CR 不签例外）。
14. repo: tools
    relative path: skills/shared/crctl/scripts/test/suite-gate.mjs
    stable symbol/对象: 用例数下界判据（L448-453：`f.cases < base` → `SUITE_MANIFEST_CASE_DROP`）与 `manifest.cases` 校验（L123-126：只校验"缺基线/非正整数"）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §4.5/D-5 的取舍依据——判据是**下限**，故多出的 1 条不触发红灯，登记值与实际不一致仍是事实缺口；本 CR 不改该判据语义。
15. repo: tools
    relative path: skills/shared/crctl/scripts/test/contract-scan.test.mjs
    stable symbol/对象: `RETIRED_RECOVERY = ['recoverCommand', 'recover_command']`（整树扫描命中即红）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: AC-6⑤ 与 AC-7③ 的"不复活旧字段名"扫描依据；§6.5 的目标文本不含这两个词。
16. repo: tools
    relative path: skills/shared/crctl/scripts/lint-prompts.mjs
    stable symbol/对象: R1~R13 规则集（R2 裸 git、R7 `crctl advance --to/--trigger` 与 backlog-set 白名单、R9「下一步」收敛 `crctl next`、R12 状态机副本、R13 backlog 状态推断）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §6.6/NFR-1 的 CI 门禁面；§6.5 的目标文本按这些规则逐条自查（无裸 git 命令、无同段 3 个以上具名状态、无"下一步"映射副本、无 guard-deny 文件的手写指示）。
17. repo: tools
    relative path: .github/workflows/crctl-ci.yml
    stable symbol/对象: 六个 step（lint-prompts enforce → check-skill-matrix → check-agents-contract → pipeline JSON 结构断言 → `suite-gate.mjs --run` → writeback 单测）与 ubuntu/windows 矩阵
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: NFR-1 与 AC-6④ 的"CI 全绿、不签例外"验证面；本 CR 不新增 CI step。
18. repo: tools
    relative path: dir-graph.yaml
    stable symbol/对象: `change-request-track.state_machine.transitions` 的三条相关声明（`requirement-approved → tech-designing` trigger `write-tech-design`；`tech-designing → tech-design-review-pending` trigger `write-tech-design-complete`；`tech-design-review-pending → tech-designing` trigger `review-tech-design:block -> write-tech-design`）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §2.4 的三条转换全部为既有声明，本 CR 不新增/不改动状态机；两次状态推进都复用既有 trigger。
19. repo: tools
    relative path: skills/shared/crctl/gates.json
    stable symbol/对象: `statusGates["tech-design-review-pending"] = [{type: fileExists, path: change-requests/{cr}/sdd.md}]`、`statusGates["tech-designing"] = [{type: approval, section: requirement}]`、`approvalStages.tech-design`
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §2.4/§3.1 的门禁事实——SDD 落盘是待评状态的唯一门禁条件，需求审批段是 `tech-designing` 的门禁；本 CR 不改门禁声明（§9 `zero_diff`）。
20. repo: tools
    relative path: skills/shared/crctl/scripts/crctl.mjs
    stable symbol/对象: 状态与账本的唯一写入执行器（`advance` / `review-record` / `checkpoint` / `approve` / `gate` 等子命令的 dispatch 与事务层）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §9 `zero_diff` 点名对象；本 CR 的过程写入只走既有子命令，不新增命令面、不改错误码（§3.2）。
21. repo: tools
    relative path: skills/shared/controlled-shell/rules.json
    stable symbol/对象: `protectedPaths.deny` 与 `git[]` 白名单
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §8「Prompt 采纳影响」判 N/A 的判据面（本 CR 不触及 deny 面与 crctl dispatch），以及 §9 `zero_diff` 的守护声明。
22. repo: tools
    relative path: pipeline-templates/architecture-design.pipeline.json
    stable symbol/对象: `nodes[]`（4 节点：write-tech-design → review-tech-design → human_approval → approve-tech-design）与 `reviewLoop`（`maxAttempts=3`、`replayNodes=[write-tech-design, review-tech-design]`）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §4.3 的"本 CR 不改轮次语义"依据与 §6.6 的节点面；AC-7②/AC-9① 的 zero_diff 对象。
23. repo: tools
    relative path: agent-skill-matrix.yml
    stable symbol/对象: Agent/Skill 权限矩阵（`owns` / `can-call` / `forbidden` 与 reviewer 的只读约束）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: AC-7② 的 zero_diff 点名对象（本 CR 不改任何 actor 的权限面、不新增 Skill）与 `AGENT-SKILL-MATRIX.md` 派生表同批约束。
24. repo: tools
    relative path: skills/develop/write-dev-plan/SKILL.md
    stable symbol/对象: plan 写作合同（回修与 `crctl task init` 口径面）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: AC-9① 与 §9 `scope_out` 的点名对象（plan/TASK 写作合同归 CR-P2）；本 CR 零 diff。
25. repo: tools
    relative path: skills/develop/write-dev-tasks/SKILL.md
    stable symbol/对象: TASK 拆分与 `crctl task init/append` 口径面
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: 同第 24 项（CR-P2 面；本 CR 零 diff）。
26. repo: tools
    relative path: skills/develop/review-dev-plan/SKILL.md
    stable symbol/对象: `upstream-design-blocker` 轨与 acceptance-verifiability 面
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: FR-5 的判据落点边界——本 CR 不在该 Skill 内新增判据，只把"范围冲突必须在本阶段拦下"写进 `review-tech-design`（§6.5-E2）；该文件零 diff（AC-9①）。
27. repo: tools
    relative path: skills/requirement/review-requirement/SKILL.md
    stable symbol/对象: 需求评审 Skill（七个评审维度与固定前缀句的事实源之一）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: §1.3.1「四个 review SKILL 中除 `review-tech-design` 外的三个零 diff」的点名对象；AC-8 的 `REVIEW_SKILLS` 四处载体之一。
28. repo: tools
    relative path: skills/develop/review-code/SKILL.md
    stable symbol/对象: 代码评审 Skill（PASS 分支与权限面载体）
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: 同第 27 项（零 diff 与 AC-8 保持性核对面）。
29. repo: tools
    relative path: skills/sync/push-progress/SKILL.md
    stable symbol/对象: `crctl checkpoint` 的发布语义与参数面（`cr_id` / `message`）、"审批之后不再有 checkpoint 节点，未发布的审批提交由下一阶段评审 checkpoint 搭车承担"的既有口径
    commit SHA: 7094e492822594b971699924478ba27ccf612c42
    依赖结论: 本节点开工前的"上一阶段未闭合发布动作"按该 Skill 的既有语义收口（需求审批提交 `14c2b6c1` 经一次 checkpoint 发布为 batch `0afd3f235aaf3cfb`）；本 CR 不改该文件、不改发布口径。
30. repo: ai-first-platform-docs
    relative path: change-requests/CR-2026-067/prd.md
    stable symbol/对象: 冻结 PRD 本体（285 行 / 51,864 B / LF-only / `sha256(LF)` = `efde31fd0ce727ee58c733de6f97b464b95e069dcdfc615c71488113cbeb0fea`；引入提交 `d4f366fa`）
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: 本 SDD 的全部 FR/AC/§1.5 裁定输入；本 CR 不得触碰该文件（改哈希即作废人工审批，§9 `zero_diff`）；S-1 附带项按"不改 prd.md、按实际 8 条理解"处理（§1.5 末段）。
31. repo: ai-first-platform-docs
    relative path: change-requests/CR-2026-067/cr.md
    stable symbol/对象: frontmatter（`status` / `target-version: 0.40` / `target-spec-id: ai-first-platform` / 三角色 owners = Ray）
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: SDD frontmatter 的 `cr-ref` / `target-version` 继承源与状态推进的唯一权威；本 CR 的 status 写入只经 `crctl advance`。
32. repo: ai-first-platform-docs
    relative path: change-requests/CR-2026-067/review-annotations/requirement.yml
    stable symbol/对象: 需求评审 canonical 记录（`verdict: pass`、`blockers: []`、`dimensions` 八维、`subject-sha256` = PRD 哈希、`review-loop.current-attempt: 1`；引入提交 `3b74b5ac`）
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: 本 SDD 的设计输入前提（需求评审 PASS 且 0 blocker，评审对象与被冻结 PRD 同哈希）；本 CR 不改评审记录。
33. repo: ai-first-platform-docs
    relative path: change-requests/CR-2026-067/approval.yml
    stable symbol/对象: `requirement` 段（`approver: OldBoy405`、`via: crctl-approve`、`target-status: requirement-approved`、`evidence-digest`；引入提交 `14c2b6c1`）
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: `tech-designing` 门禁（`statusGates["tech-designing"] = approval/requirement`）的满足依据，也是本节点开工的前提；本 CR 不改该文件。
34. repo: ai-first-platform-docs
    relative path: change-requests/_backlog.yml
    stable symbol/对象: 在途 CR 条目集合与 `change-requests[].latest-checkpoint` 批次快照结构
    commit SHA: 31db6d201f081d6e78a5fa73e6676d4fa55d319e
    依赖结论: AC-9② 的"在途只有本 CR、063~066 均 archived"核对面；本 CR 不手工编辑该账本（写入唯一经 crctl）。
35. repo: multica
    relative path: cr-prompts-revised/**
    stable symbol/对象: Agent Prompt 部署副本（`quality-reviewer-agent.md` / `dev-agent.md` 等）
    commit SHA: 5c1880f2125e73733b1a5bfc7501db310ab7f584
    依赖结论: AC-7② 与 §9 `zero_diff` 的点名对象（本 CR 不改任何部署副本；判据唯一事实源是 tools 侧 SKILL）。
36. repo: multica
    relative path: （Go/TS 代码与平台资产，如 `CUSTOM.md` / `aifirst/**`）
    stable symbol/对象: 产品代码与定制台账
    commit SHA: 5c1880f2125e73733b1a5bfc7501db310ab7f584
    依赖结论: §1.2/§9 的 multica 零 diff 声明；本 CR 不落任何 multica 代码，故不触发其 `CUSTOM.md` 登记义务。

### 6.4 既有测试面改动清单与零改动核对清单

**改动（1 个用例 + 1 个登记值）**：

| 位置 | 现状 | 目标 |
|---|---|---|
| `pipeline-structure.test.mjs` L616 写侧 term 组（8 项） | `['### 既有实现依赖与事实','正文首次出现顺序','repo:','relative path:','stable symbol/对象:','commit SHA:','依赖结论:','sdd.explicit_existing_dependencies']` | 追加 `'dep-N'`（其余 8 项逐字保留），见 §6.5-F |
| 同用例评侧 term 组（4 项） | `['名为“既有实现依赖与事实”的显式小节','有序清单','sdd.explicit_existing_dependencies','正文同类事实是否漏列']` | 原位改写为覆盖"显式小节 + 有序清单 + `dep-N` 引用规则 + `commit SHA` 必填 + `sdd.explicit_existing_dependencies` + 正文漏列"的 6 项，见 §6.5-F |
| `gate-registry.json` L38 | `"pipeline-structure.test.mjs": 35` | `36`（与实测顶层用例数一致） |

**零改动核对清单（AC-3 / AC-8 / AC-9③ 的核对面）**：

| 对象 | 零改动判据 |
|---|---|
| `review-tech-design` Step 2.2 首轮全量句 | 逐字存在（含"合并同根因问题、拆分不同根因问题"） |
| `review-tech-design` Step 2.1 AC 闭环伪码（缺设计落点 / 冲突 / 不可观察 / 不可达） | 逐字保留 |
| `review-tech-design` Step 2.3 分级边界与五个固定前缀 | 逐字保留，`本轮新增：` 仍只承担 blocker 文本分类 |
| 四个 review SKILL 的 Step 1.0 clean 前置 / Step 5 PASS 发布与对账四要素 / BLOCK 分支不发布 | 逐字保留（CR-2026-066 断言 A 覆盖） |
| `REVIEW_SKILLS` 四处载体的权限面（`agent-skill-matrix.yml` / `AGENT-SKILL-MATRIX.md` / `quality-reviewer-agent.md`） | 零 diff |
| `write-tech-design` Step 1 / 2.5 / 3 / 4 / 5 与 Step 2.6 的 AC 映射合同、AC 反查闭环、SDD-CLOSE 义务段 | 零 diff |
| `quality-reviewer-agent.md` 的 `##` 小节集合（7 个） | 零 diff（不新增小节、不复制判据） |

### 6.5 目标文本清单（实施时逐字写入）

> 说明：以下为**逐字目标文本**（设计产物）。`…` 表示"原文逐字不变、此处省略"；每处均为**原位替换或原位追加**，不新增小节、不重排 Step 编号。

#### 6.5-A `write-tech-design/SKILL.md` — Step 2.6 既有实现证据段（L113）

**替换目标（整段）**：

```text
涉及既有实现（现有仓库、文件路径、稳定符号、配置键、接口/协议、数据库结构、模块行为、调用顺序或责任边界，且是方案成立前置条件）的断言，必须逐项附证据：`repo`、`commit SHA`、`relative path`、`stable symbol/对象`、`conclusion`；每条事实在 `### 既有实现依赖与事实` 表中获得稳定标识 `dep-N`（N 为正整数），其中 `commit SHA` 为必填的 40 位 SHA，编号按正文首次出现顺序分配、只增不改（正文增删条目不重编号，被删除的条目留下空洞、编号不复用）；实现事实只在该表定义一次，SDD 正文只能写「设计依赖 `dep-N`」，不得在正文重新陈述「当前代码已经如何工作」。无法绑定这些字段的引用按待核实依赖列出，不得归入 N/A。无既有实现依赖时才明确写 `N/A（本 CR 无既有实现依赖）`，不得用 N/A 掩盖正文中的事实依赖。核验必须覆盖正文所声称的实际行为，不以「文件或符号存在」代替行为成立。正文中的「现有、既有、复用、无需新增」等断言若在当前资源 HEAD 上不成立，必须改为新增能力设计或列入待核实依赖，不得继续作为方案前提。
```

相对原文的唯一新增内容：`dep-N` 稳定标识句（含"`commit SHA` 为必填的 40 位 SHA"与编号生命周期）＋"事实只在该表定义一次 / 正文只能写设计依赖 `dep-N`"句。

#### 6.5-B `write-tech-design/SKILL.md` — `### 既有实现依赖与事实` 小节（L117-127）

**L117 句替换目标**：

```text
当方案依赖既有实现时，必须在本节按正文首次出现顺序列出每项依赖，每项以稳定标识 `dep-N`（N 为正整数）开头，使用以下固定结构：
```

**固定结构块替换目标**：

```text
dep-1
  repo: <repository id>
  relative path: <path from repository root>
  stable symbol/对象: <symbol, key, interface, module, behavior, or responsibility>
  commit SHA: <40-character SHA>
  依赖结论: <verified current behavior required by this design>
```

**结构块后一句替换目标**：

```text
`review-tech-design` 只将本节的有序清单作为 `sdd.explicit_existing_dependencies`，并按 `dep-N` 引用关系核验正文：正文出现的 `dep-N` 必须已在本节定义；正文出现未被 `dep-N` 引用承载的当前实现事实是事实引用无承载。无法绑定字段的引用必须列入待核实依赖；只有本节与正文均无既有实现依赖时，才写 `N/A（本 CR 无既有实现依赖）`。
```

#### 6.5-C `write-tech-design/SKILL.md` — 回修模式句（L129）

**替换目标（原位扩写为一句群）**：

```text
回修模式只按 blocker 和本轮变化定点修订，不无理由重写已确认方案。blocker 触及状态判定、活动性、事件顺序、空值或失败回流时，必须重证该状态链的完整输入维度、分支、可见动作与对应 AC，不得只修被点名的那一格；同一标识符、锚点或 testid 在全文只能有一个裁决；未受该根因影响的已确认方案不得重写——「整体重证」与「不扩散」两个方向同时约束，前者防止只修一格，后者防止借重证之名重写无关设计。
```

#### 6.5-D `write-tech-design/SKILL.md` — Step 2 章节 9「批准范围」段末追加

**在既有段落末尾（"代码阶段发现实际 diff 越界时只回 `implement-code`。"之后）原位追加**：

```text
四字段自洽判据（与 `review-tech-design` 的「批准范围前置」逐条同表述；判据只针对四字段之间的自相矛盾与必需条件错位，不针对详尽程度）：① `scope_in` 与 `zero_diff` 不得对同一对象同时要求「修改」与「不修改」；② 外部治理规则强制修改时，必须在 SDD 阶段把该对象纳入 `scope_in`、修订 `zero_diff`、或给出已有的合法出口；③ 不得用 `scope_out` 隐藏当前交付必须发生的治理修改；④ `follow_up` 不得承载当前 AC 的必要条件。不新增第五个字段、不新增独立 ledger 文件、不新增状态、不新增评审维度名。
```

#### 6.5-E1 `review-tech-design/SKILL.md` — Step 2.1 两段（L87 / L89）

**L87 段替换目标**：

```text
SDD 的既有实现依赖必须来自名为“既有实现依赖与事实”的显式小节。该小节按正文首次依赖出现顺序维护有序清单，每项以稳定标识 `dep-N`（N 为正整数）开头，固定包含 `repo`、`relative path`、`stable symbol/对象`、`commit SHA` 和“依赖结论”五要素，其中 `commit SHA` 为必填的 40 位 SHA（缺失或与取证结果不符形成 blocker）。`sdd.explicit_existing_dependencies` 仅指该清单，不由 reviewer 扫描全仓库或临时猜测；reviewer 还必须核验 `dep-N` 引用规则：正文出现的 `dep-N` 必须在表中已定义，判据从「正文同类事实是否漏列」的集合比较升级为「正文引用是否由 `dep-N` 承载」的关系式——正文出现未通过 `dep-N` 引用承载的当前实现事实形成 blocker。本规则是 Prompt 合同，不宣称对自由文本事实的机械识别——判定仍属评审判断，不新增 crctl 校验面、lint 规则或 annotation dimension。
```

**L89 段替换目标（仅核心句改写，取证边界逐字保留）**：

```text
只核验 SDD 明确写入且设计成立依赖的既有实现事实，不做全仓库无界扫描：对每项依赖按 `resources` 找到匹配 `repo`，用受控只读取证 `crctl git rev-parse HEAD` 取 commit SHA，并核验文件/稳定符号；事实缺失或行为不符形成业务 blocker（附 repo/SHA/path/symbol/conclusion 证据），资源缺失或不可读为技术失败且不写临时 payload。SDD 正文出现未被 `dep-N` 引用承载的当前实现事实形成 blocker；只有正文与依赖清单均无依赖时才记录 `N/A（本 CR 无既有实现依赖）`。行号只作辅助，不作唯一证据；评审不执行 lint/build/test。
```

#### 6.5-E2 `review-tech-design/SKILL.md` — Step 2「批准范围前置」引用块（L58）末追加

**在既有引用块（`> **批准范围前置（CR-2026-057 FR-5/AC-5）**：…统一生成 verdict。`）末原位追加**：

```text
四字段自洽判据（与 `write-tech-design` 章节 9 逐条同表述；判据只针对四字段之间的自相矛盾与必需条件错位，不针对详尽程度）：① `scope_in` 与 `zero_diff` 不得对同一对象同时要求「修改」与「不修改」；② 外部治理规则强制修改时，必须在 SDD 阶段把该对象纳入 `scope_in`、修订 `zero_diff`、或给出已有的合法出口；③ 不得用 `scope_out` 隐藏当前交付必须发生的治理修改；④ `follow_up` 不得承载当前 AC 的必要条件。任一一型命中 → blocker（`本轮新增：`），必须在 SDD 阶段形成，不得留到 dev-plan 再由 `review-dev-plan` 的 `upstream-design-blocker` 轨触发。
```

#### 6.5-F `pipeline-structure.test.mjs` — L616 目标用例两组 term

**替换目标（用例名与结构不变，仅两组 term 原位改写）**：

```javascript
test('CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确', () => {
  const writer = readFileSync(path.join(TOOLS_ROOT, 'skills/develop/write-tech-design/SKILL.md'), 'utf8').replaceAll('\r\n', '\n');
  for (const term of ['### 既有实现依赖与事实', '正文首次出现顺序', 'dep-N', 'repo:', 'relative path:', 'stable symbol/对象:', 'commit SHA:', '依赖结论:', 'sdd.explicit_existing_dependencies']) {
    assert.ok(writer.includes(term), `write-tech-design 合同含 ${term}`);
  }
  const reviewer = readFileSync(path.join(TOOLS_ROOT, 'skills/develop/review-tech-design/SKILL.md'), 'utf8').replaceAll('\r\n', '\n');
  for (const term of ['名为“既有实现依赖与事实”的显式小节', '有序清单', '`dep-N` 引用规则', '`commit SHA` 为必填的 40 位 SHA', 'sdd.explicit_existing_dependencies', '正文同类事实是否漏列']) {
    assert.ok(reviewer.includes(term), `review-tech-design 规则含 ${term}`);
  }
});
```

term 组的覆盖对照（PRD FR-6.1）：写侧 = 小节名（`### 既有实现依赖与事实`）＋ `dep-N` 固定结构（`dep-N`）＋ 五字段名（`repo:` / `relative path:` / `stable symbol/对象:` / `commit SHA:` / `依赖结论:`）＋ 排序与消费口径（`正文首次出现顺序` / `sdd.explicit_existing_dependencies`）；评侧 = 显式小节（`名为“既有实现依赖与事实”的显式小节`）＋ 有序清单（`有序清单`）＋ `dep-N` 引用规则（`` `dep-N` 引用规则 ``）＋ `commit SHA` 必填（`` `commit SHA` 为必填的 40 位 SHA ``）＋ 消费口径（`sdd.explicit_existing_dependencies`）＋ 正文漏列（`正文同类事实是否漏列`）。

#### 6.5-G `gate-registry.json` — L38

`"pipeline-structure.test.mjs": 35` → `"pipeline-structure.test.mjs": 36`（其余条目与 `exceptions: []` 不动）。

### 6.6 门禁与回归面（NFR-1 / NFR-5）

| 面 | 本 CR 的期望 | 依据 |
|---|---|---|
| `lint-prompts.mjs --mode enforce` | 绿（新增文本不含裸 git、状态机副本、下一步映射、deny 面手写指示） | §6.5 文本按 R1~R13 逐条自查 |
| `check-skill-matrix.mjs` / `check-agents-contract.mjs` | 绿（未改 Skill / Agent 集合、未改索引） | 依赖第 23、10 项 |
| pipeline JSON 结构断言 | 绿（`pipeline-templates/**` 零 diff） | 依赖第 22 项 |
| `suite-gate.mjs --run` | 全量绿；`exceptions` 保持 `[]` | FR-6.3/FR-6.4 |
| `pipeline-structure.test.mjs` | 36 条顶层用例全绿（含 L616 改写后的 term 组） | AC-6①③ |
| `contract-scan` | `RETIRED_RECOVERY` 整树零命中 | 依赖第 15 项 |
| 行尾纪律（NFR-5） | SKILL 与测试文件保持 LF 检出内容一致；测试读取仍先 `\r\n → \n` 归一 | ARCHITECTURE.md 不变量 4 |

## 7. 安全与性能考量

### 7.1 行尾纪律与硬失败（NFR-5）

- 本 CR 触及的测试文件对 target 文件做文本断言，读取路径仍是 `readFileSync(..., 'utf8').replaceAll('\r\n', '\n')`（既有形态，依赖第 11/12 项），Windows 检出不会造成假红或假绿；
- 断言失败即 `assert.ok` 抛出，**没有**"匹配不到 → 空集 → 静默通过"的分支——`dep-N` term 若在实施后从文本里消失，红灯是唯一结果；
- 本 CR 不新增解析器、不做跨行正则，故不引入新的归一化面。

### 7.2 边界与越权面

- **不新增判据副本**：`dep-N` 规则与批准范围自洽判据的唯一事实源分别是两份 SKILL 的既有段落；`tools/agents/quality-reviewer-agent.md` 零 diff（AC-3②）。
- **不动写入通道**：评审批注仍唯一经 `crctl review-record` 落盘，状态仍唯一经 `crctl advance`；本 CR 只改判据文本。
- **不放宽既有门禁**：Step 2.1 的 AC 闭环伪码、Step 2.3 的分级边界与固定前缀句、CR-2026-066 的发布与 clean 前置全部保留（AC-9③）。
- **反向 token 保持性**：本 CR 新增文字不含 `crctl checkpoint` / `push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`（AC-2⑦）；`write-tech-design` 现存 1 处 `crctl checkpoint` 句不删（§1.5 第 5 条）。

### 7.3 唯一强度变化的兼容性说明

评侧 `commit SHA` 由"并可附"改为必填，会让原本可通过的 SDD 在**新口径**下成为 blocker。该变化：

- 不改变任何 crctl 状态转换、错误码、参数或落盘路径（§3.1/§3.2）；
- 只改变 `review-tech-design` 的 blocker 判定输入；
- 对既有已归档 CR **无追溯效力**——判据只对评审发生时的 SKILL 版本生效（PRD §1.3.3，本 SDD 同样据此声明 D-6 的时序差）。

### 7.4 性能与观测

- 本 CR 不新增运行时开销：只改文本判据与一个既有断言的 term 组，测试执行规模不变（顶层用例数 36 不变）；
- 不新增观测指标 / SLO / 计数门禁 / 评审轮数承诺（NFR-2、FR-3.3）；`本轮新增：` 仍只承担 blocker 文本分类；
- 日志与审计面零变化（不新增 crctl 子命令、不改 audit/outbox 语义）。

## 8. Prompt 采纳影响

**N/A（本 CR 不触及触发面）。** 依据 `write-tech-design` Step 2 章节 8 的条件触发判定：只有当本 CR 的 diff 触及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支或 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny` 时才必填。

- `crctl.mjs`：本 CR **零 diff**（不新增/删除子命令、flag、错误码；不改任何 dispatch 分支）。
- `rules.json`：`protectedPaths.deny` 与 `git[]` 白名单 **零 diff**（§9 `zero_diff`，依赖第 21 项）。

因此不存在"crctl 新增了能力、某 Skill 该采纳却还没采纳"的漂移面，本节按规则省略为 N/A。

## 9. 批准范围

### scope_in（当前 CR 必须交付的 FR/AC）

- **FR-1 ~ FR-7 全部**，按 §6.1 的落点表；**AC-1 ~ AC-9 全部**按 §6.2 的映射验收（AC-9 为本 PRD 新增的边界与串行判据）。
- **文件面（4 个交付文件，全部在 `../tools`）**：
  1. `skills/develop/write-tech-design/SKILL.md`（§6.5-A/B/C/D 四处原位修订）；
  2. `skills/develop/review-tech-design/SKILL.md`（§6.5-E1/E2 两处原位修订）；
  3. `skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（L616 目标用例两组 term，§6.5-F）；
  4. `skills/shared/crctl/scripts/test/gate-registry.json`（`manifest.cases["pipeline-structure.test.mjs"]` 35 → 36，§6.5-G）。
- **KB 仓**：本 SDD（`change-requests/CR-2026-067/sdd.md`）与状态/评审记录；不改 KB 的 `specs/`、`delivery/`、`docs/`。

### scope_out（明确排除的路径和能力）

- **plan/TASK 写作合同**（`write-dev-plan` / `write-dev-tasks` / `review-dev-plan`、upstream 增量回修、TASK 依赖闭包、证据命令证明力、环境责任与 readiness、`code-implementation.pipeline.json` 的 dev-start 提示）→ 归 **CR-P2**（PRD §7）。
- **crctl 事务层与命令面**：`crctl.mjs`、`scripts/lib/**`、`gates.json`、状态机声明、`rules.json` 零 diff；不新增/删除子命令、flag、错误码。
- **不新增结构承载**：annotation dimension、账本字段、评审指标（SLO / 计数门禁 / 评审轮数承诺）、Pipeline 节点、Skill 参数、落盘文件、lint 规则、CI step。
- **不在 Agent Prompt 造第二份判据**：`tools/agents/quality-reviewer-agent.md` 零 diff（不新增小节、不复制 `dep-N` 规则与首轮全量判据）。
- **不重编号 Step**：`review-tech-design` 的 Step 1 / 1.0 / 2 / 2.1 / 2.2 / 2.3 / 3 / 4 / 5 / 6 与 `write-tech-design` 的 Step 1 / 2 / 2.5 / 2.6 / 3 / 4 / 5 全部保持编号不变。
- **不复活旧字段名**：不引入 `recoverCommand` / `recover_command`；不改结构化 `recovery` 合同（CR-2026-064 面）。
- **不改发布口径**：不为发布点前移或 checkpoint 语义做任何改动（CR-2026-066 已定；本 CR 不删 `write-tech-design` 现存 `crctl checkpoint` 句）。
- **不改 `suite-gate.mjs` 判据语义**，不签任何新例外。
- **`../multica/`**：零 diff（不改部署副本、不改 Go/TS 代码、不登记其 `CUSTOM.md`）。

### zero_diff（明确不得改动的调用点/签名）

| 对象 | 零 diff 约束 |
|---|---|
| `change-requests/CR-2026-067/prd.md` | 零 diff（已审批冻结，`sha256(LF)` = `efde31fd…`；改哈希即作废人工审批）。含 S-1 附带项：**不修**"七条"措辞 |
| `skills/shared/crctl/scripts/crctl.mjs`、`scripts/lib/**` | 全文件零 diff（不改 dispatch、不改事务层与状态/账本写入口） |
| `skills/shared/crctl/gates.json`、`../tools/dir-graph.yaml#change-request-track.state_machine` | 零 diff（不新增状态、转移、门禁） |
| `skills/shared/controlled-shell/rules.json` | 零 diff（`protectedPaths.deny` 与 `git[]` 白名单都不动） |
| `pipeline-templates/**`（含 8 个 pipeline JSON 与 `_index.yml` 的 nodes 计数） | 零 diff（不新增节点、不改 dev-start 提示） |
| `agent-skill-matrix.yml`、`AGENT-SKILL-MATRIX.md` | 零 diff（不改任何 actor 的 `owns`/`can-call`/`forbidden`、不新增 Skill） |
| `agents/quality-reviewer-agent.md`（及 `tools/agents/**`） | 零 diff（`##` 小节集合保持 7 个，无新增小节与判据副本） |
| `skills/develop/{write-dev-plan,write-dev-tasks,review-dev-plan}/SKILL.md` | 零 diff（CR-P2 面） |
| `skills/requirement/review-requirement/SKILL.md`、`skills/develop/{review-dev-plan,review-code}/SKILL.md` | 零 diff（四个 review SKILL 中除 `review-tech-design` 外的三个） |
| `review-tech-design` Step 1 / 1.0 / 2.2 / 2.3 / 3 / 4 / 5 / 6 与 `write-tech-design` Step 1 / 2.5 / 3 / 4 / 5 | 零 diff（含 Step 2.2 首轮全量句逐字保留、Step 2.3 分级边界与固定前缀句逐字保留） |
| `write-tech-design` Step 1 第 2 条的 `crctl checkpoint` 提交口径句 | 零 diff（本 CR 不删该句） |
| `skills/shared/crctl/scripts/test/suite-gate.mjs`、`contract-scan.test.mjs`、`lint-prompts.mjs`、`check-*.mjs` | 零 diff（不改判据语义、不新增扫描面） |
| `pipeline-structure.test.mjs` 除 L616 目标用例外的全部用例（含 L656 CR-2026-066 断言 A/B/C/D 与 `REVIEW_SKILLS` 常量） | 零 diff（不放宽任何既有断言） |
| `../multica/**`（含 `cr-prompts-revised/**`、`CUSTOM.md`、`aifirst/**`） | 零 diff |
| KB `specs/`、`delivery/`、`docs/`、`change-requests/CR-2026-067/{approval.yml,review-annotations/**,review-loop.yml,traceability.yml}` | 零 diff（受控账本，crctl 独占写） |

### follow_up（发现但留给后续 CR / owner 的缺口）

1. **S-1（PRD §5 末段"七条"与来源 §5.5 的 8 条不符）**：`prd.md` 已随需求审批冻结，本 CR 不改该文件；本 SDD 按实际 8 条理解（AC-1~AC-8 覆盖完整）。建议后续需求类 CR 或该 CR 回写期统一措辞（去计数或改为"八条"）。
2. **`dep-N` 形态的历史文档同步**：`docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md` 等分析文本仍按旧编号列表描述依赖表；本 CR 不改写历史分析文档，如需标注"已被 CR-2026-067 取代"另起文档 CR。
3. **`manifest.cases` 的下界语义**：本 CR 只把登记值同步为实测值，不改 `suite-gate` 的"低于登记值即红"语义；若后续需要"登记值 = 实际值"的严格校验，属独立门禁 CR。
4. **评侧 `commit SHA` 必填对新写 SDD 的即时影响**：新口径会拦下缺失 SHA 的 SDD；首个受影响对象是新口径生效后撰写 SDD 的 CR（本 CR 自身的 SDD 按 D-6 沿用实施前形态）。
5. **`review-loop` 达标后的重证质量**：本 CR 只提供回修判据文本（Prompt 合同），不提供机械校验；若后续出现"整体重证"被形式化执行的情况，需要新的观测面（本 CR 明确不新增观测指标）。
6. **PRD §1.4 事实 16 的计数偏差（`review-tech-design` attempt 1/3 的 `范围外` suggestion）**：`CR-2026-055` 相关用例实测为 5 条（`L568` / `L585` / `L602` / `L616` 之外，同文件 `L627` 另有 `test('CR-2026-055 blocker 修复: 权限解释文档同步新增 can-call 关系', ...)`），PRD 写作"4 条"。本 SDD 未继承该计数（§6.3 第 11/12 项只引用 L616 目标用例与顶层总数 36），设计唯一性与验收可达性不受影响；`prd.md` 已随需求审批冻结，本 CR 不改该文件，建议回写期或后续需求类 CR 与本列表第 1 项（S-1）一并修正措辞。

---

## SDD-CLOSE 关闭项（PRD 显式延后到 SDD 的设计项）

**扫描结论**：逐条扫描 PRD（§1.3.3、§1.5、§3 各 FR、§4、§5、§7）后确认——**PRD 中不存在显式延后到 SDD 的设计项**（无"待 SDD 定义/由 SDD 决定/延后到设计期"的表述）；PRD 的三处"需人工一并确认"（§1.5 第 1、2、4 条）已在需求人工审批时确认，不含设计缺口。为可核对，仍按 SDD 承接面逐项关闭如下。

### SDD-CLOSE-01 FR-1 的 `dep-N` 条目形态与编号生命周期（P0）

**结论：已关闭。** 条目形态 = §2.2 表（`dep-N` 首行 + 五字段缩进两格）；编号生命周期 = §4.1 算法（首次出现顺序分配、只增不改、删除留空洞不复用）。覆盖层：产生（写侧 Step 2.6 判据）→ 定义（依赖小节一次）→ 消费（本 SDD §6.3 与评侧 Step 2.1）→ 兼容降级（旧 `1. repo:` 前缀退役，五字段名与小节名不变，`sdd.explicit_existing_dependencies` 语义不变）。

### SDD-CLOSE-02 FR-2 的评侧判据闭包（P0）

**结论：已关闭。** 三条关系式（引用必须已定义 / 事实必须被引用承载 / SHA 必填且与取证一致）全部写进 Step 2.1 的同两段（§6.5-E1），并给出诚实边界（Prompt 合同、非机械门禁、不新增 crctl 校验面与 annotation dimension）。覆盖层：判据文本 → 断言面（§6.5-F 的评侧 6 项 term）→ 消费方（reviewer 的 blocker 判定）。

### SDD-CLOSE-03 FR-5 两侧同判据的"同表述"闭合（P1）

**结论：已关闭。** 四条判据的两侧文本在 §6.5-D 与 §6.5-E2 中**逐字相同**（仅引导句按角色不同），因此 AC-5① 的"表述与字段名一致"可直接 diff 核对；评侧的落点（SDD 阶段 blocker、不留 dev-plan）写在同段（§6.5-E2 末句）。

### SDD-CLOSE-04 FR-6 的断言与基线同步闭合（P1）

**结论：已关闭。** 目标用例的写侧/评侧 term 组逐项给出（§6.5-F），并逐条对照 PRD FR-6.1 的覆盖要求；`manifest.cases` 的收口方向与理由见 D-5（35 → 36）；`suite-gate.mjs` 判据语义与 `exceptions` 保持不动（§4.5）。覆盖层：断言文本 → 门禁登记值 → 门禁判据语义 → CI 回归面（§6.6）。

### SDD-CLOSE-05 本 CR 自身 SDD 与目标合同的时序差（P2）

**结论：已关闭（按 D-6 声明）。** 本 SDD §6.3 沿用实施前的编号列表形态，目标 `dep-N` 形态自实施提交起对其后的 SDD 生效；依据是 PRD §1.3.3 的"评审判据只对评审发生时的 SKILL 版本生效"，因此不构成 NFR-3 所禁止的"新旧两套判据并存"。

### SDD-CLOSE-06 S-1 附带项的处理（P2）

**结论：已处理（不改需求文本）。** 处理方式：设计期按来源 §5.5 实际 8 条理解（§6.2 以 AC-1~AC-9 为验收面，AC-1~AC-8 与 8 条一一对应）；**保留理由**：`prd.md` 已冻结（改哈希即作废需求审批），修它超出本 CR 的设计范围；改进建议登记为 `follow_up` 第 1 项。

---

### 修订记录

- 初稿（2026-09-15）：按冻结 PRD（`change-requests/CR-2026-067/prd.md`，285 行 / 51,864 B / LF-only / `sha256(LF)` `efde31fd…`，引入提交 `d4f366fa`）与来源附件 §5 起草；基线事实在 `tools@7094e492`、`multica@5c1880f2`、KB worktree@`31db6d20` 三个 HEAD 上逐条核实（§6.3 共 36 项依赖）。设计细化的三处落点：① 写侧 `dep-N` 的**分配算法**（§4.1，PRD 只给形态、未给流程）与条目形状表（§2.2）；② 评侧**关系式核验算法**（§4.2）与"集合比较 → 引用关系"的显式升级表述（§6.5-E1）；③ 批准范围四条判据在两侧的**逐字同表述**形态（§6.5-D/E2），使 AC-5① 可 diff 核对。六项 SDD-CLOSE 逐项关闭（其中 SDD-CLOSE-01/02 为 P0 设计项，03~06 为边界与时序项）。
- 本节点开工前的发布收口：上一阶段（需求审批）的本地提交 `14c2b6c1`（`approval.yml` + status）按 `push-progress` 既有语义一次发布为 batch `0afd3f235aaf3cfb`（`ai-first-platform-docs` 源提交 `14c2b6c1` confirmed、`multica` `5c1880f2`、`tools` `7094e492`，metadataCommit `31db6d201f081d6e78a5fa73e6676d4fa55d319e`）；本 SDD 不对发布口径做任何改动。
- 回修 1/3（2026-09-15，`review-tech-design` attempt 1/3 = BLOCK 定点修复，被修复版本 `sha256(LF)` = `b5d91ae3136670947a9e62ca8c80eaf0ea6bca640bb97ac89f184853624a3253`）：① 按 `tools@7094e492` 实测把 §6.3 第 27 项 `relative path` 与 §9 `zero_diff` 对应行中需求评审 SKILL 的仓内前缀由 `skills/develop/` 更正为 `skills/requirement/`（实测 `skills/develop/` 下无 `review-requirement`；该 SKILL 与 `pipeline-structure.test.mjs#REVIEW_SKILLS` 均写 `skills/requirement/review-requirement/SKILL.md`，同行的 `review-dev-plan` / `review-code` 仍在 `skills/develop/` 下，未改），修正后 §6.3 全部 36 项 `relative path` 与 §9 全部字面路径可解析；② 采纳本轮 suggestion，把 §6.3 收录判据 ③ 由「§9 `zero_diff` 点名对象」收窄为「§9 `zero_diff` 中设计所依赖的既有实现文本」，与清单实际收录面一致（§9 其余零 diff 对象由该表与 AC-7②/AC-9① 直接核对）；③ 本轮 `范围外` suggestion（PRD §1.4 事实 16 的计数）登记为 `follow_up` 第 6 项。除上述定点修订外，§6.5 目标文本、§9 其余行、D-1~D-6、SDD-CLOSE-01~06 均未改动。

## CR-P2：plan/TASK 返工成本与执行前提（v0.41 · CR-2026-068）

## 1. 架构概览

### 1.1 设计目标与不变量

本 CR 的技术设计只做一件事：**把「plan/TASK 回修」「证据命令证明力」「环境执行前提」三处合同缺的可判定承载体，原位补进既有 Skill 段落与一处 pipeline 人工审批提示文本**。设计输入是需求合同（`dep-1`：FR-1~FR-6 / AC-1~AC-9）与需求来源（`dep-2` §6.1~§6.7），设计边界由 `dep-1` §1.3.1 / §7 与 `dep-2` 边界段落钉定：**零新增结构承载**（无新节点、无新账本字段、无新评审维度、无新观测指标）。

落成六条设计不变量（供 `review-tech-design` 与 `plan/TASK` 逐条核对）：

| # | 设计不变量 | 判据落点 |
|---|---|---|
| I1 | **回修以 delta 为输入，不以「整轮」为输入**：upstream SDD 重新批准后，plan 与 TASK 两层都只重算受影响面（章节 / 稳定表行 / 证据 / 回滚 / 受影响 TASK 的下游依赖闭包），未受影响内容逐字保留 | FR-1 / FR-2、§4.1 / §4.2、AC-1 / AC-2 |
| I2 | **同一文件内不存在两套回修规则**：delta 语义只写在既有回修模式段落内部（`dep-3` / `dep-4` 所指段落），文件内不得并存「全量重建」与「delta 重算」两种规则 | FR-2.3、NFR-3、§4.2、AC-2③ |
| I3 | **证据命令的判据是「观测面 ≥ 声称面 + 形态在受控边界内」**，写侧与评侧使用同表述、同强度；既有概括反假绿句保留，不另立第二句概括 | FR-3、§4.3、AC-3 |
| I4 | **回滚单元 = 受影响下游消费者的依赖闭包**：共享改动的回滚不得声明为单点回滚，且与风险节逆拓扑顺序一致 | FR-4、§4.4、AC-4 |
| I5 | **环境前提分三层、各自单点**：plan 侧静态声明（owner / 建立方式 / 可获得性 / readiness / 缺失处置）、dev-start 侧只确认静态前提、implement 侧在首个环境依赖 TASK 前即时执行 readiness；动态健康不入人工审批、不入账本 | FR-5、§4.5、AC-5 / AC-6 |
| I6 | **零新增面无例外**：状态机、gate、reviewLoop / replayNodes、账本字段、评审维度名、`cmd-NN` 合同、`ENVIRONMENT_MISMATCH` 语义、pipeline 节点数（5/4/12）与全部既有测试断言保持 | FR-6、§4.6、§9 `zero_diff`、AC-7 / AC-8 / AC-9 |

### 1.2 变更面鸟瞰

**一批纯文本原位修订**：交付 diff 只含 5 个 tools 文件（其中 4 个 SKILL.md + 1 个 pipeline JSON 的一个字符串字段），共 7 处落点（计数单位 = §6.5 的逐字目标文本条款 `A`~`G`，一处落点可承载多个 FR）：

```text
../tools（本 CR 代码实施面全部在此；SHA 见 dep-5 取证口径）
  skills/develop/write-dev-plan/SKILL.md        ← FR-1（Step 2a upstream 轨）+ FR-3（两张稳定表说明）
                                                   + FR-4（交付覆盖表 `回滚` bullet）
                                                   + FR-5（章节 5「验收与发布策略」）      = 3 处（§6.5-A/B/C）
                                                   （按落点计：A 承载 FR-1，B 合并承载 FR-3 与 FR-4，C 承载 FR-5）
  skills/develop/write-dev-tasks/SKILL.md       ← FR-2（Step 2a 第 1 条原位改写）          = 1 处
  skills/develop/review-dev-plan/SKILL.md       ← FR-3 评侧（既有 acceptance-verifiability） = 1 处
  skills/develop/implement-code/SKILL.md        ← FR-5 implement 侧（既有环境节同节共生）   = 1 处
  pipeline-templates/code-implementation.pipeline.json ← FR-5 dev-start 侧（`…0004` approvalPrompt 值替换） = 1 处
ai-first-platform-docs（KB：只承载本 CR 过程产物；不改 specs/ delivery/ docs/）
  change-requests/CR-2026-068/{prd.md（冻结，零触碰）, sdd.md（本文档）}
../multica：零 diff（不改 Agent Prompt 部署副本、不改 Go/TS 代码、不改 CUSTOM.md）
```

**改动量上界**：4 处「既有段落内原位扩写 / 原位改写」＋ 2 处「既有 bullet 原位扩写」＋ 1 个 JSON 字符串值替换。**无新增文件、无删除文件、无新增章节、无 Step 重编号、无新增列、无新增枚举值。**

### 1.3 依赖方向与分层与多仓口径（不变）

```text
Pipeline（pipeline-templates/*.pipeline.json）   编排 Skill 调用顺序（本 CR 仅改 …0004 的提示文本，编排零变化）
   ↓
Skill（write-dev-plan / write-dev-tasks / review-dev-plan / implement-code）  提示词合约 ← 本 CR 改动层
   ↓
crctl（crctl.mjs + lib/**）                      状态与账本唯一写入执行器（本 CR 零 diff）
```

三条硬约束取自 `dep-5`（`## 4. 分层与依赖方向`、`## 5. 硬不变量`），本轮实读全文，本设计逐条不冲突：

- **不变量 1 / 2（状态与账本单一写入通道）**：本 CR 不新增任何状态写入口或账本写入口；plan/TASK 的产物仍是 KB 过程文档，任务索引刷新仍唯一经 `crctl`（`dep-6` 所指既有指引不动）。
- **不变量 3（零第三方依赖）**：本 CR 不新增依赖、不新增脚本、不改 `skills/shared/crctl/scripts/**`。
- **不变量 4（行尾与硬失败纪律）**：新增/改写文本读写前后一律 `\r\n → \n` 归一；跨行解析失败硬失败（§7.1）。
- **不变量 8（Skill 通用、约束归仓）**：四处新增文本只写通用写作/评审判据，不出现任何使用方仓库的产品专属约束（表结构、迁移框架、锁原语、DDL 规范）。

**多仓口径（FR-08.4 对应面）**：

| 项 | 本 CR 口径 |
|---|---|
| 路径 authority | 一切 worktree 路径只取 `crctl workspace inspect` 的 `operationalWorkspace` / `resources[].worktreePath` 原样值（`dep-1` 为 KB 过程文档权威路径；`dep-5` 指出的目标仓只按 `resources` 匹配 `repo` 取 `worktreePath`），不按 `.rayai-worktrees/{repo.id}/...` 目录命名拼接 |
| 跨仓依赖方向 | KB（需求/设计/任务文档）→ tools（被改文本）；`../multica` 不被依赖也不被修改；依赖只朝下，无反向依赖 |
| 各仓提交口径 | 按既有 FR-07.2 口径：文本改动在 `resources[].worktreePath` 各自提交，不要求同一 commit；阶段终点由 `review-tech-design` PASS 分支的既有 `push-progress`（`crctl checkpoint`）纳入同一批发布（本 Skill 不新增发布动作） |

### 1.4 关键流程

#### 1.4.1 upstream 后 plan 增量回修（FR-1）

```text
触发：review-dev-plan 走 UPSTREAM 轨（repair-target=write-tech-design，dep-7 所指既有双轨路由）
      → 人工修订 SDD → 重新评审（review-tech-design）→ 重新批准（approve-tech-design）
      → 按 pipeline 既有 reviewLoop.replayNodes 重放（dep-8 所指条目）
输入：① 新旧批准 SDD 的变更 delta；② 同轮未闭合 plan blockers（canonical feedback 引用）
动作（全部在 dep-3 所指既有 Step 2a 段落内原位扩写，不新增小节）：
  ① 既有普通轨三条逐字保留；
  ② upstream 轨：在同一份 plan.md 上只重算受影响章节、稳定表行（两张稳定表的行）、
     证据与回滚；未受影响内容逐字保留；
  ③ coordinator 只传 subject / delta / canonical feedback 引用，不指定具体行如何修改。
不改：review-route 枚举、repair-target 单值语义、Step 编号（Step 1/2/2a/3/4 不变）。
判据落点：§6.5-A
```

#### 1.4.2 TASK 及依赖闭包 delta 重算（FR-2）

```text
触发：write-dev-plan 完成 SDD→plan delta 后，pipeline 按既有顺序重放 write-dev-tasks（dep-8；dep-4 所指段落）
动作（在该段第 1 条内原位改写，不新增第 4 条、不在别处另写一段）：
  ① 继续执行 plan→TASK delta：重算「直接受影响 TASK」（普通轨 blockers 指向的 TASK + upstream delta 波及的 TASK）
     及其下游依赖闭包（depends-on 可达的传递闭包）；
  ② 同步更新受影响 TASK 的输入、输出、接口（接口契约节的消费/产出签名）、命令、depends-on、完成标志、回滚；
  ③ 未受影响 TASK 保留；被评审判废/删除的 TASK 从文件集移除；
  ④ crctl task init 只用于刷新 tasks/_index.yml 索引，不承担重算语义（索引刷新契约见 dep-7 / dep-6）。
禁止：只修 plan 而把旧 TASK 留给下一轮评审发现；文件内并存两套回修规则（I2）。
不改：节点集 / 节点数 / replayNodes 条目 / `purpose: regenerate-tasks` 标签文本（dep-8）。
判据落点：§6.5-D
```

#### 1.4.3 证据命令的观测面与受控形态（FR-3）

```text
写侧（dep-9 所指两张稳定表说明，原位扩写；既有概括反假绿句保留，不另立第二句概括）：
  ① 观测面 ≥ 声称面：每个 cmd-NN 必须能观测该表行声称的 AC 结果；
  ② 四类典型错配：--list 类命令不能证明浏览器行为；文件级 --name-only 不能证明符号级不变量；
     子集测试不能声称全量；涉 Git 的命令必须使用 rules.json 已允许的受控入口（dep-10，不新开裸面、不改列白名单）；
  ③ 命令算法唯一事实源 = 证据命令表行，不再通过委派评论补写命令算法。
评侧（dep-11 所指既有 acceptance-verifiability 增量维度内原位扩写同一判据）：
  观测面窄于声称面即 blocker；命令形态越受控边界即 blocker；不留到 implement 阶段才暴露。
不改：两张稳定表的表头 / 列集 / 「验收证据 ↔ 证据ID」双向唯一映射合同（dep-7 覆盖矩阵节机械核对）；
      八类维度表与四个增量维度名；不新增证据账本。
判据落点：§6.5-B（写侧）+ §6.5-E（评侧）
```

#### 1.4.4 回滚单元是依赖闭包（FR-4）

```text
目标：dep-9 所指交付覆盖表既有 `回滚` bullet（原位扩写，不新增列）
  ① 被其它 TASK 消费的共享改动，其回滚单元必须包含受影响下游消费者；
  ② 与 plan.md 第 4 章「风险与回滚策略」的逆拓扑顺序一致；
  ③ 单点 revert 会破坏下游时不得声明为单点回滚。
判据落点：§6.5-B
```

#### 1.4.5 环境责任与即时 readiness 三侧（FR-5）

```text
plan 侧（dep-12 所指 chapter 5「验收与发布策略」，原位扩写，不新增第八节）：
  证据依赖常驻服务 / 浏览器 / 数据库时，本节写明五要素：
    ① 环境 owner；② 建立方式；③ 可获得性；
    ④ readiness 证据 = 复用该环境所保障的那一行 FR 的既有 cmd-NN（证据ID 照抄证据命令表，不新增命令行）；
       两张稳定表双向唯一映射不放宽；无法复用 → 另立 CR（本 CR 不放开）；
    ⑤ 缺失时按既有 ENVIRONMENT_MISMATCH 标签与处置入口（只引用不复述，唯一详细事实源见 dep-13）。

dev-start 侧（dep-14 所指 `…0004` approvalPrompt，值原位替换）：
  只确认静态前提（owner / 建立方式 / 可获得性）；不要求审批时所有服务在线；动态健康状态不入人工审批；
  保留 ✅ / ❌ 两分支结构化决定；不得出现 git / journal 字样（dep-15 的既有零命中断言）；
  不得残留 review-annotations 路径与 reject_reason 引导；节点对象其余字段与节点集零变化。

implement 侧（dep-13 所指既有环境节，同节共生追加 bullets，不改写既有 bullets）：
  ① 在第一个依赖环境的 TASK 前执行 plan 指定的 readiness cmd-NN（属于既有「一次环境检查」的执行内容，
     不是新的反复探测；仍受「最多一次重跑」、timeout 与受控入口约束）；
  ② 失败按既有 ENVIRONMENT_MISMATCH 中止并报告所需建立动作；
  ③ 环境无关 TASK 不被提前阻断。
判据落点：§6.5-C（plan）+ §6.5-F（implement）+ §6.5-G（dev-start）
```

#### 1.4.6 零新增与门禁面（FR-6）

```text
零 diff 面（逐条见 §9 zero_diff）：skills/shared/crctl/scripts/**（含全部测试与 gate-registry.json）、
  write-tech-design / review-tech-design / review-code / write-test-report / coding-discipline、
  pipeline 节点集与 reviewLoop、tools/agents/**、agent-skill-matrix.yml、../multica/**、
  KB specs/ delivery/ docs/（来源文档只读）
计数面：节点数保持 5 / 4 / 12，与 dep-16 登记值一致
测试面：dep-15 / dep-17 / dep-18 / dep-19 全部既有断言保持；dep-20 的 manifest.cases 保持 36、exceptions 保持 []
  （本 CR 预期零测试改动，dep-1 §1.5 第 2 条）
账本面：不改 upstream attempts 账本、不新增 review-events、不改 traceability schema、不做聚合指标
旧字段：不复活 recoverCommand / recover_command（dep-18 整树零命中）
```

### 1.5 与 PRD §1.5 七条口径的承接

| PRD §1.5 | 性质 | SDD 落点 |
|---|---|---|
| 第 1 条（FR-3 写侧不是从零新增反假绿句） | 事实核对 | §6.5-B 只保留既有概括句并在其后追加判据，不另立第二句（AC-3① 末句） |
| 第 2 条（本 CR 预期零测试改动） | 事实核对 / 门禁 | §6.4、§6.6、§9 `zero_diff`；`manifest.cases` 保持 36（`dep-20`） |
| 第 3 条（`…0004` approvalPrompt 的「原位改为」落点） | 需人工确认 | §6.5-G 在既有拆分确认语境上扩写环境静态前提，保留 ✅/❌ 两分支 |
| 第 4 条（`ENVIRONMENT_MISMATCH` 单一事实源纪律） | 本 PRD 钉定 | §6.5-C ⑤ 只引用标签与处置入口；§6.5-F 新文字加在 `dep-13` 同节内、不改写既有 bullets |
| 第 5 条（「一次环境检查」与 readiness 的关系） | 需人工确认 | §1.4.5 implement 侧 ①：readiness 是既有一次检查的执行内容，不是反复探测 |
| 第 6 条（readiness 无法复用既有 `cmd-NN`） | 本 PRD 钉定 | §6.5-C ④ 硬边界 + §9 `follow_up` 第 1 项（另立 CR） |
| 第 7 条（`purpose: regenerate-tasks` 标签语义钉定） | 本 PRD 钉定 | §1.4.2 不改标签文本与 replayNodes；delta 语义只写在 `dep-4` 正文内 |

**需求期 canonical suggestion（`dep-21`：PRD §1.4 事实 21 的「cmp 逐字节一致 / 33,478 B」只在 EOL 归一后成立）的承接**：本设计**不依赖**该字节级断言——设计输入按「内容一致（EOL 归一后）」理解，且未在任何目标文本中写入 `cmp` / 逐字节 / 字节数口径；§7.1 同时约定新增文本的行尾纪律与硬失败（SDD-CLOSE-05）。该处属需求文本，本 CR 不改 `prd.md`（§9 `scope_out`）。

---

## 2. 数据模型

### 2.1 零新增实体、字段与账本（NFR-2 落点）

| 面 | 结论 |
|---|---|
| 新增实体 / 表 / schema | 无（本 CR 无数据库变更，见 §2.6） |
| 新增账本字段 / 文件 | 无：不改 `cr.md` / `_backlog.yml` / `_history.yml` / `tasks/_index.yml` / `traceability.yml` / `review-loop.yml` 的结构或字段集 |
| 新增稳定表列 | 无：交付覆盖表仍 5 列、证据命令表仍 6 列（`dep-9`） |
| 新增枚举值 | 无：review-route 枚举、`repair-target` 单值语义、状态机状态与转移全部不变 |
| 新增观测指标 | 无：不新增 SLO / 轮数承诺 / 计数门禁（`dep-2` §1.4「不增加观测指标」） |

### 2.2 本 CR 改动的「数据形状」（全部为既有文档的文本形状）

| # | 形状 | 承载 | 变化方式 |
|---|---|---|---|
| S1 | plan.md 章节 5 的**环境声明五要素**（owner / 建立方式 / 可获得性 / readiness 复用既有 `cmd-NN` / 缺失处置引用） | `dep-12` 所指章节项 | 在该项说明内原位扩写；章节数仍为 7 |
| S2 | 交付覆盖表 `验收证据` 列的**观测面判据**（观测面 ≥ 声称面 + 四类错配 + 命令算法唯一事实源） | `dep-9` 所指 bullet | 既有概括句保留、其后追加判据；列集不变 |
| S3 | 交付覆盖表 `回滚` 列的**闭包判据**（含下游消费者 + 逆拓扑一致 + 单点回滚禁令） | `dep-9` 所指 bullet | 原位扩写；列集不变 |
| S4 | **TASK 卡 delta 面**：受影响 TASK 的输入 / 输出 / 接口 / 命令 / `depends-on` / 完成标志 / 回滚同步更新 | `dep-4` 所指段落 + TASK 卡既有结构（`dep-6`） | 语义收紧；TASK frontmatter 与正文 6 节结构不变 |
| S5 | `…0004` approvalPrompt 的**静态前提确认内容** | `dep-14` 所指字符串值 | 值替换；JSON 结构与节点对象字段不变 |
| S6 | 现有实现事实的**单一表达点**（`dep-N` 表） | 本文档 §6.3 | 采用 `dep-N` 固定结构表达（写作合同载体见 §5 D-6） |

S4 的「依赖闭包」定义为 `depends-on` 有向边上的**传递闭包**（受影响 TASK 可达的全部下游 TASK）；口径与边界场景见 §2.4 的 `TERM-02`。S1~S5 均不引入新的可查询实体，因此不存在「字段完整性 / 迁移」问题。

### 2.3 既有结构引用（只读、逐字沿用）

以下既有结构在本 CR 中被引用但**零改动**，取证见 §6.3：两张稳定表的表头与列集、`验收证据 ↔ 证据ID` 双向唯一映射合同与覆盖矩阵节机械核对（`dep-7`、`dep-9`）、TASK 索引三步断言与受控账本指引（`dep-6`）、`ENVIRONMENT_MISMATCH` 标签语义与其唯一详细事实源地位（`dep-13`）、`rules.json` 的 git 白名单与 `protectedPaths.deny`（`dep-10`）、状态机与 gates（`dep-5`）、pipeline 节点集与 reviewLoop（`dep-8`、`dep-16`）。

### 2.4 术语预检（Step 2.5，结论）

预检范围：只处理进入「数据模型 / 状态机 / 接口契约」且存在歧义、别名或边界风险的术语。目标仓（`dep-5` 所指 tools 仓根）**无 `CONTEXT.md`、无术语表**（本轮实读：仓根与 `docs/` 均无该文件；`docs/` 下无覆盖本 CR 术语的定义），因此无既有权威定义可沿用、也不存在与既有口名的命名冲突。逐条结论（每个风险术语给出一个代表性边界场景）：

| 术语 | 结论 | 代表性边界场景（验证结果） |
|---|---|---|
| `TERM-01` **观测面 / 声称面** | 本 CR 新引入的判据对，不是既有概念别名；无需裁决，直接采用 `dep-1` FR-3 的表述 | 「声称面 = 交付覆盖表该行 FR/关键AC 的 AC 结果；观测面 = `cmd-NN` 实际能观测到的结果」→ 一条只跑单元测试的 `cmd-NN` 声称「浏览器交互可用」：观测面窄于声称面 → 判 blocker（不是「测试不够多」这类不可判定表述） |
| `TERM-02` **直接受影响 TASK / 下游依赖闭包** | 新引入的判定口径，与 `dep-2` §6.2 用词一致；无同名冲突 | TASK-02 直接受影响、TASK-05 经 `depends-on: [TASK-02]` 传递可达、TASK-07 与本链无关 → delta 重算集 = {TASK-02, TASK-05}，TASK-07 逐字保留（不被无理由重建） |
| `TERM-03` **readiness 证据** | 借用 `dep-2` §6.5 的用词；本 CR 把它钉为「复用既有 `cmd-NN`」，不新增第二套验证语义 | 环境 E 保障 FR-2 主路径：readiness 取该行既有 `cmd-NN`；若某 TASK 想为 readiness 另立命令 → 无 `cmd-NN` 下标、无 `test-evidence/cmd-NN.log`，不构成合法 `cmd-NN` → 判「另立 CR」而非本 CR 内放宽映射 |
| `TERM-04` **共享改动 / 受影响下游消费者** | 新引入的判定口径，与 `dep-2` §6.4 用词一致 | TASK-03 改签名的共享接口被 TASK-04 消费：回滚单元 = {TASK-03, TASK-04}，不得声明为「单点 revert TASK-03」 |

无术语语义冲突，**不需要**要求需求负责人澄清（若后续评审发现冲突，按既有「不自行裁决」规则停止并澄清）。本项不新增术语表文件、不新增 Skill 参数。

### 2.5 状态与门禁（零变化）

不新增状态、不新增转换、不改 `gates.json` 与目标 workspace 的 `dir-graph.yaml#change-request-track.state_machine`；本 CR 的状态链仍为既有 `tech-designing → tech-design-review-pending → tech-design-reviewed → task-breakdown → developing` 等既有路径。`upstream-design-blocker` 的重放路径完全复用既有转换（`dep-7`、`dep-8`）。

### 2.6 数据 / schema 变更与写路径鉴权完整性：N/A

**N/A（本 CR 无数据库 schema 变更、无数据迁移、无写路径鉴权改动）**。理由：本 CR 的 diff 只落在 4 个 Markdown 提示词文件与 1 个 pipeline JSON 的一个字符串字段；不新增表 / 列 / 索引 / 迁移，不触碰任何鉴权判定、事务边界或锁原语。`dep-5` §5 不变量 1/2 约束的「状态/账本写入通道」在本 CR 中零新增入口，因此不存在「约束缺失窗口」「回滚 down 脚本」「事务内鉴权复核」的适用面。

---

## 3. 接口契约

### 3.1 Skill 调用契约：零变化

`dep-1` §1.3.3 已钉定：本 CR 五份目标文件涉及的 Skill（write-dev-plan / write-dev-tasks / review-dev-plan / implement-code）的**必填参数、落盘路径、允许的状态转换、失败码、与 `crctl` 的唯一写入边界全部不变**。本 CR 改的是 SKILL 正文内的 Prompt 判据与 pipeline 人工审批提示文本，不新增/删除参数，不改参数类型或必填性。

### 3.2 crctl CLI 契约：零变化

不新增/删除子命令与 flag，不改任何 JSON 输出形状、退出码、错误码、调用者约束；`dep-10`（`git` 白名单与 `protectedPaths.deny`）零 diff；`skills/shared/crctl/scripts/**` 全量零 diff。

### 3.3 文本合同面（本 CR 的「接口」）

本 CR 的「接口」= 7 处文本判据（§6.5 给出逐字目标文本）。每处的可核对面 = 「必含判据」与「必须保持不变」两侧：

| # | 落点（`dep-N`） | 必含判据（设计产物） | 必须保持不变（保持性约束） |
|---|---|---|---|
| C1 | `dep-3`（write-dev-plan Step 2a） | upstream 轨四条（§6.5-A ②~⑤） | 普通轨三条逐字保留；Step 编号 1/2/2a/3/4 |
| C2 | `dep-9`（两张稳定表说明） | S2 六项观测面判据 + S3 三项回滚闭包判据 | 既有概括反假绿句；两张表表头 / 列集；双向唯一映射 |
| C3 | `dep-12`（plan 章节 5） | 环境五要素 | plan.md 章节数 7（不新增第八节）；不新增 `cmd-NN` |
| C4 | `dep-4`（write-dev-tasks Step 2a 第 1 条） | delta 重算 + 依赖闭包同步 + 未受影响保留 + `crctl task init` 只刷新索引 | 同节第 2、3 条；`tasks/_index.yml` 受控账本句；文件内无第二套回修规则 |
| C5 | `dep-11`（review-dev-plan `acceptance-verifiability`） | 两条 blocker 判据（同 C2 判据对） | 八类维度表与四个增量维度名；`dep-15` 的 S-13 三 token 零命中 |
| C6 | `dep-13`（implement-code 环境节） | readiness 即时性 + 失败标签 + 环境无关 TASK 不提前阻断 | 既有六个 bullets 原样；`ENVIRONMENT_MISMATCH` 唯一事实源地位 |
| C7 | `dep-14`（`…0004` approvalPrompt） | 静态前提确认 + 不要求服务在线 | ✅/❌ 两分支；无 `git`/`journal`；无 `review-annotations`/`reject_reason`；节点对象其余字段 |

### 3.4 错误语义：零新增

不新增错误码、不改变既有错误语义：`ENVIRONMENT_MISMATCH` 的语义与边界（不写 crctl 状态 / gate / 账本 / 评审 blocker / 测试证据 schema，由既有 `onFail=abort` 中止）逐字保留（`dep-13`）；`TASK_COUNT_MISMATCH`、`LOOP_EXHAUSTED`、`CONTRACT_DRIFT` 等既有码不受影响。

### 3.5 HTTP / REST / IPC / 事件契约：N/A

**N/A（本 CR 无任何 HTTP API、IPC 或事件契约新增/修改）**，故不编写 OpenAPI 片段（Skill Step 2.5「HTTP/REST 契约条件触发基线」不触发）。

---

## 4. 关键算法与流程

### 4.1 写侧：upstream delta 回修算法（FR-1，`dep-3`）

```text
输入：approvedSddOld, approvedSddNew, openPlanBlockers, canonicalFeedbackRef
① delta ← diff(approvedSddOld, approvedSddNew)        # 变更面，而非整份 SDD
② 输入集 ← delta ∪ openPlanBlockers                    # 同轮未闭合 blockers 与之并列
③ 受影响面 ← 由 ② 推导：受影响章节 / 受影响稳定表行 / 受影响证据 / 受影响回滚单元
④ for each 章节 in plan.md:
       if 受影响: 只重算该章节中与 ② 相关的行
       else: 逐字保留
⑤ for each 稳定表行: 仅 ② 命中行重算（新增行 / 修改行 / 删除行；其它行逐字保留）
⑥ for each 证据: 仅 ② 命中行重算 cmd-NN（保持双向唯一映射）
⑦ for each 回滚: 仅 ② 命中行重算（闭包判据见 4.4）
⑧ coordinator 合同：只传 subject / delta / canonicalFeedbackRef；不指定具体行如何修改
不变量：重写面 ∝ delta；route 枚举与 repair-target 单值语义不变
```

**边界**：若 ② 为空（无 delta、无未闭合 blocker），本轨不产生任何重写——由 `review-dev-plan` 既有 BLOCK 机制兜底，不空转（对应 `dep-3` 所指既有第 2 条）。

### 4.2 写侧：TASK 及依赖闭包 delta 重算算法（FR-2，`dep-4`）

```text
输入：planDelta（4.1 的产物）, taskGraph（depends-on 有向边）, openTaskBlockers
① direct ← {TASK | blockers 指向 ∪ planDelta 波及}          # 直接受影响
② closure ← 传递闭包(direct, taskGraph)                      # 下游消费者
③ for each T in closure:
       同步 T 的 输入 / 输出 / 接口（消费·产出签名）/ 命令 / depends-on / 完成标志 / 回滚
④ for each T ∉ closure: 逐字保留（不重建、不改 depends-on）
⑤ 文件集 ← 原集合 − 被评审判废/删除的 TASK
⑥ crctl task init → 仅刷新 tasks/_index.yml 索引（不承担重算语义；账本唯一写入通道不变）
禁止：只修 plan 不修 TASK；文件内并存「全量重建」规则
```

**边界（TERM-02 场景）**：闭包为空（无直接受影响 TASK）时，TASK 文件集与索引不变，仅刷新索引即可；闭包非空时，跨 TASK 的共享契约必须整体同步（不允许只改产出方而留下消费方旧签名）。

### 4.3 写侧 + 评侧：观测面判据（FR-3）

```text
写侧（dep-9，每个 cmd-NN 行级自查）：
  声称面(row) = 交付覆盖表该行「FR/关键AC」的 AC 结果
  观测面(cmd) = 该命令实际能观测到的结果
  判据：observable(cmd) ⊇ claimed(row)，否则必须换命令或调整声称（不得留下假绿）
  四类典型错配（判「窄」）：
    ① --list 类命令声称浏览器行为
    ② 文件级 --name-only 声称符号级不变量
    ③ 子集测试声称全量
    ④ 涉 Git 命令未走 rules.json 已允许的受控入口（dep-10）
  唯一事实源：命令算法写在证据命令表行内；不经委派评论补写
评侧（dep-11，同表述、同强度）：
  观测面窄于声称面 → blocker
  命令形态越受控边界 → blocker
  时机：在 dev-plan 阶段拦截，不留到 implement 阶段
不变量：两张稳定表表头/列集与双向唯一映射不被修改
```

### 4.4 回滚单元闭包算法（FR-4，`dep-9`）

```text
输入：riskSectionOrder（plan.md 第 4 章的风险与回滚策略）, taskGraph
① 若改动被其它 TASK 消费（共享改动）：
       回滚单元 ← {改动} ∪ 受影响下游消费者（依赖闭包，同 4.2 ②）
② 校验：回滚单元在风险节的执行顺序 = 逆拓扑顺序（先回滚下游消费者，再回滚上游改动）
③ 若单点 revert 会破坏下游 → 不得声明为单点回滚（必须写闭包回滚单元）
```

### 4.5 环境责任与即时 readiness 流程（FR-5，三侧）

```text
plan 侧（dep-12）：若证据依赖常驻服务/浏览器/数据库 →
   声明 {owner, 建立方式, 可获得性, readiness=复用该环境所保障行 FR 的既有 cmd-NN, 缺失处置=引用 ENVIRONMENT_MISMATCH}
   readinessMap：environment → cmd-NN（必须已存在于证据命令表且被交付覆盖表引用）
dev-start 侧（dep-14）：人工只确认上述静态前提 → 不要求服务在线（动态健康不入审批）
implement 侧（dep-13）：执行顺序
   for each TASK in topoOrder(tasks):
       若 TASK 依赖环境 E 且 E 尚未 readiness 验证:
           执行 plan 指定的 readinessMap[E]（既有「一次环境检查」的执行内容；最多一次重跑）
           fail → ENVIRONMENT_MISMATCH 中止 + 报告所需建立动作（不写账本/状态/评审 blocker）
       否则：照常执行（环境无关 TASK 不被提前阻断）
不变量：不新增环境 Pipeline 节点；coordinator 不启停共享服务
```

**边界**：环境无关 TASK 排在首位时先执行，不被环境依赖 TASK 的 readiness 阻塞；同一环境的 readiness 只验证一次（不反复探测），与 `dep-13` 既有「一次环境检查」bullet 一致。

### 4.6 零 diff 面与保持性约束（FR-6）

```text
diff(本 CR) ⊆ { dep-3, dep-9, dep-12 所在文件（write-dev-plan/SKILL.md）,
                dep-4 所在文件（write-dev-tasks/SKILL.md）,
                dep-11 所在文件（review-dev-plan/SKILL.md）,
                dep-13 所在文件（implement-code/SKILL.md）,
                dep-14 所在文件（code-implementation.pipeline.json 的 …0004 approvalPrompt 值）,
                KB 的 change-requests/CR-2026-068/** }
保持不变量：
  ① 节点数 5/4/12（dep-16）且 pipeline 节点集、reviewLoop.replayNodes、purpose 标签逐字不变（dep-8）
  ② dep-10 的 git 白名单与 deny 面零改动
  ③ dep-15 / dep-17 / dep-20 / dep-22 / dep-18 / dep-19 既有断言全部仍绿（§6.6）
  ④ 四个 review SKILL 的 Step 1.0 / Step 5 / Step 6 四要素与三 token 反向断言零命中（dep-15）
  ⑤ 不复活 recoverCommand / recover_command（dep-18）
```

---

## 5. 技术选型与替代方案

决策记录判据（三判据同时满足才记录）：难以逆转 + 无上下文会疑惑 + 有真实权衡替代。以下六项均满足；不伪造替代方案，不新增 ADR 文件或审批节点。

### D-1 承载体：原位改既有段落（选定）

- **Decision**：7 处改动全部落在既有段落/既有 bullet 内部（原位扩写或原位改写），不新增小节、不新增章节、不重编号 Step。
- **Context**：PRD §1.3.1 修订面表与 §7 明确「原位改四份 Skill 的既有段落 + 一处 pipeline 人工审批提示文本，零新增结构承载」；`dep-1` §8 规定普通 Skill 措辞调整不改 `ARCHITECTURE.md`。
- **Alternatives**：① 新增独立「增量回修」小节（否决：会与既有段落并存两套规则，直接违反 I2 与 NFR-3/AC-2③）；② 新增 plan.md 第八节承载环境声明（否决：违反 AC-5① 与 FR-5「不新增第八节」）。
- **Consequences**：改动面小、评审可逐字核对；代价是单段落变长，必须靠判据而非结构分隔可读性（由观测面判据与 blocker 强度兜底）。

### D-2 输入形态：新旧批准 SDD delta + 同轮未闭合 blockers（选定）

- **Decision**：upstream 轨的输入是「新旧批准 SDD 的变更 delta」与「同轮未闭合 plan blockers」，不把旧 plan 整轮作废。
- **Context**：PRD FR-1 第 2 条；`dep-2` §6.1「原文问题」指出全量重建是返工成本被放大的第一形态。
- **Alternatives**：把 canonical blockers 当作唯一输入（否决：upstream 轨的 blocker 来自 SDD 变更，不是 plan 评审意见）；要求 coordinator 传「受影响行清单」（否决：PRD §1.3.1 与 US-3 明确 coordinator 只传 subject/delta/canonical feedback 引用，不指定具体行）。
- **Consequences**：重写面与 delta 成正比；风险是 delta 判定依赖 SDD 两版对比，若 SDD 只有一处小改却影响大量稳定表行，仍会触发大范围重算——这是正确行为（影响面真实存在），不算回退。

### D-3 readiness 证据：复用既有 `cmd-NN`（选定）

- **Decision**：readiness 证据必须复用该环境所保障的那一行 FR 的既有 `cmd-NN`；无法复用时另立 CR。
- **Context**：PRD FR-5 第 4 条、AC-6；两张稳定表「验收证据 ↔ 证据ID」双向唯一映射合同（`dep-2` §6.5 已给出理由：不被交付覆盖表引用的命令行进表即 blocker，不进表则不构成合法 `cmd-NN`）。
- **Alternatives**：为 readiness 单独申请新 `cmd-NN`（否决：会放宽双向唯一映射，需改稳定表合同与评审判据，超出本 CR 边界）；用「非 `cmd-NN` 的自由命令」承载 readiness（否决：无 `executable`/`args`/`timeout` 与 `crctl test` 机器区下标，无法被既有机械核对覆盖，等于新增第二套验证语义）。
- **Consequences**：映射不破坏、环境声明可机械核对；代价是某些环境诉求被推迟到后续 CR（记入 `follow_up`）。

### D-4 索引刷新与重算语义分离（选定）

- **Decision**：`crctl task init` 只用于刷新 `tasks/_index.yml` 索引，不承担 delta 重算语义；重算语义写在 `dep-4` 所属 Skill 正文内。
- **Context**：`dep-7` / `dep-6` 的账本契约（受控账本唯一写入通道 + 三步断言）；PRD FR-2 第 1 条与 §1.5 第 7 条。
- **Alternatives**：让 `crctl task init` 承担「重算」语义（否决：CLI 契约零 diff 是本 CR 的 `zero_diff` 面，且账本写入口不应承担业务重算语义，会引入第二事实源）；新增 TASK append/rebuild 子命令（否决：新增子命令违反 FR-6③）。
- **Consequences**：`purpose: regenerate-tasks` 标签语义在 Skill 正文内明确，节点层零改动（不撞节点数与 `_index.yml` 断言）。

### D-5 dev-start 只确认静态前提（选定）

- **Decision**：`…0004` approvalPrompt 只确认环境 owner / 建立方式 / 可获得性等静态前提，不要求审批时所有服务在线。
- **Context**：PRD FR-5 第 6 条、US-5；`dep-2` §6.5 dev-start 侧。
- **Alternatives**：审批时要求环境全部在线（否决：把动态健康状态写成人工长期事实，审批会为瞬时状态背书，且会在 implement 之前制造伪阻塞）；把环境确认放进 implement 由 Agent 自证（否决：静态前提缺少人类确认点，环境 owner 与可获得性无人负责）。
- **Consequences**：静态与动态职责分离；风险是审批人可能误以为服务已在线——由提示文本显式写明「动态健康状态由 implement 侧即时验证、审批不为其背书」消解。

### D-6 本 CR 自身 SDD 的依赖表形态：`dep-N` 固定结构（选定）

- **Decision**：本文档 §6.3 采用 `dep-N` 固定结构（`repo` / `relative path` / `stable symbol/对象` / `40 位 commit SHA` / `依赖结论`）。
- **Context**：本文档 §6.3 的 `dep-N` 固定结构以 `dep-23` 为合同载体（`write-tech-design` 的「既有实现依赖与事实」合同段 + `review-tech-design` Step 2.1 引用核验规则），该合同自 CR-2026-067 合并起对后续 SDD 生效；CR-2026-067 SDD 的 `D-6` 因当时合同尚未生效而使用实施前的编号列表形态，本 CR 不适用该时序差。
- **Alternatives**：沿用编号列表形态（否决：与本 CR 生效中的写作合同冲突，会形成第二套形态）。
- **Consequences**：正文对既有实现事实只写「设计依赖 `dep-N`」；编号按正文首次出现顺序分配（KB 设计输入与 tools 实现事实混排，不按仓分组，同一仓的条目编号不保证连续），本 CR 共 23 项。

---

## 6. FR 到技术实现映射

### 6.1 FR 逐条映射

| FR | 技术方案条目 | 目标落点 | 验收证据（PRD AC） |
|---|---|---|---|
| FR-1 upstream 后 plan 增量回修 | §1.4.1（I1）、§4.1（算法）、§6.5-A（逐字文本）；普通轨三条保留、upstream 轨四条新增、路由面不变 | `dep-3`（write-dev-plan Step 2a） | AC-1①~⑤ |
| FR-2 TASK 及依赖闭包重算 | §1.4.2（I2）、§4.2（算法）、§6.5-D（逐字文本）；「重新生成」零残留、`crctl task init` 只刷新索引、节点层零改动 | `dep-4`（write-dev-tasks Step 2a 第 1 条） | AC-2①~⑤ |
| FR-3 证据命令可执行性与证明力 | §1.4.3、§4.3（判据算法）、§6.5-B（写侧六项）、§6.5-E（评侧两条 blocker 判据） | `dep-9`、`dep-11` | AC-3①~⑤ |
| FR-4 回滚单元是依赖闭包 | §1.4.4、§4.4（算法）、§6.5-B（`回滚` bullet 三项） | `dep-9` | AC-4①~④ |
| FR-5 环境责任与即时 readiness | §1.4.5、§4.5（三侧流程）、§6.5-C / §6.5-F / §6.5-G | `dep-12`、`dep-13`、`dep-14` | AC-5①~③、AC-6①~③ |
| FR-6 边界与零新增 | §1.4.6、§4.6（零 diff 面）、§6.4（改动/零改动清单）、§6.6（门禁回归面）、§9 `zero_diff` | 全量（无新增承载） | AC-7①~④、AC-8①~④、AC-9①~③ |

### 6.2 AC 逐项设计与验收映射

> 每条 AC 给出「设计落点 / 可观测结果 / 可达性说明」。设计落点中的 `dep-N` 指 §6.3 的既有实现事实；`§6.5-X` 指本文档的目标文本条款。

**AC-1（FR-1）**

- 设计落点：`§6.5-A` 对 `dep-3` 所指 Step 2a 段落原位扩写（既有三条之后追加 upstream 轨）。
- 可观测结果：该段落文本可逐条核对——普通轨三条逐字保留；含「以新旧批准 SDD 变更 delta + 同轮未闭合 plan blockers 为输入」「同一份 plan 上只重算受影响章节 / 稳定表行 / 证据 / 回滚」「未受影响内容保留」「coordinator 只传 subject / delta / canonical feedback 引用」；`review-route` 枚举与 `repair-target` 单值语义未被修改；Step 编号 1/2/2a/3/4 未变。
- 可达性说明：`dep-3` 所指段落是 `write-dev-plan` 唯一的回修模式承载点（同文件无第二处回修规则），改写不依赖任何前置状态或过滤条件；upstream 轨的触发路径（`dep-7` 双轨路由 + `dep-8` replayNodes）在既有状态机上已连通，不需要新增转换。

**AC-2（FR-2）**

- 设计落点：`§6.5-D` 对 `dep-4` 所指 Step 2a 第 1 条原位改写。
- 可观测结果：「重新生成」措辞零残留（同一文件全文可检索）；该段表达 delta 重算 + 下游依赖闭包同步 + 输入/输出/接口/命令/`depends-on`/完成标志/回滚同步 + 未受影响 TASK 保留；写明 `crctl task init` 只刷新索引；文件内无第二套回修规则；`dep-6` 的「禁止 Agent/Skill 手写」句仍在；节点集 / 节点数 / `replayNodes` / `purpose: regenerate-tasks` 标签文本未变。
- 可达性说明：`dep-17` 的 CR-2026-037 用例两条 match 断言与一条 doesNotMatch 断言分别落在该段与 `dep-6`；本设计的改写使 doesNotMatch 天然仍绿（删词而非改词），不引入需要新断言的取值；`dep-8` 的节点层条目不在 diff 面内。

**AC-3（FR-3）**

- 设计落点：`§6.5-B`（`dep-9` 两张稳定表说明）+ `§6.5-E`（`dep-11` 的 `acceptance-verifiability`）。
- 可观测结果：写侧六项判据齐备且既有概括反假绿句保留（未另立第二句概括）；评侧两条 blocker 判据齐备；八类维度表与四个增量维度名未变；`dep-15` 的 S-13 三 token（`push-progress 之前` / `push-progress 之后` / `统一 checkpoint 后`）在 `dep-11` 文件内零命中；两张稳定表列集与双向唯一映射未变。
- 可达性说明：写侧判据加在既有列说明的同一 bullet 内（不依赖新列）；评侧判据加在既有维度行内（不新增维度名、不新增账本）；`dep-11` 文件的既有 Step 5 发布段与 Step 1.0 前置段不在改动面内，反向断言不会被新文字命中。

**AC-4（FR-4）**

- 设计落点：`§6.5-B` 的 `回滚` bullet 原位扩写（`dep-9`）。
- 可观测结果：该 bullet 含「共享改动的回滚单元必须包含受影响下游消费者」「与第 4 章风险与回滚策略逆拓扑顺序一致」「单点 revert 会破坏下游时不得声明为单点回滚」；交付覆盖表列集仍为 5 列。
- 可达性说明：`回滚` 列在既有稳定表中已存在且每行必填（不存在空值旁路），判据只是收紧该列的写作口径，不依赖新前置；逆拓扑一致性由风险节既有章节（`dep-9` 所属文件的 plan.md 章节 4）承载，无需新章节。

**AC-5（FR-5）**

- 设计落点：`§6.5-C`（plan 章节 5，`dep-12`）+ `§6.5-F`（implement 环境节，`dep-13`）+ `§6.5-G`（`…0004` approvalPrompt，`dep-14`）。
- 可观测结果：① plan 章节 5 含环境五要素（owner / 建立方式 / 可获得性 / readiness 复用既有 `cmd-NN` / 缺失时 `ENVIRONMENT_MISMATCH` 处置引用），plan.md 章节数仍为 7；② 提示文本只确认静态前提、不要求服务在线、无 `git`/`journal` 字样、保留 ✅/❌ 两分支、无 `review-annotations`/`reject_reason` 残留，节点对象其余字段与节点集零变化；③ implement 环境节含 readiness 即时性、失败按既有标签中止并报告建立动作、环境无关 TASK 不被提前阻断，且既有 bullets 未改写。
- 可达性说明：三侧各自有唯一承载点（plan 章节 5 说明 / `…0004` approvalPrompt 值 / `dep-13` 环境节），互不覆盖；`dep-15` 的 git/journal 零命中断言是保持性断言（本设计通过不写这些字面量满足，不需新增断言）；`dep-13` 的六条既有 bullets 原样保留，新 bullets 同节共生。

**AC-6（FR-5，映射不破坏）**

- 设计落点：`§6.5-C` ④（readiness 复用既有 `cmd-NN`）+ §4.5 的 `readinessMap` + §9 `follow_up` 第 1 项。
- 可观测结果：两张稳定表「验收证据 ↔ 证据ID」双向唯一映射未被放宽或修改（`dep-7` 覆盖矩阵节机械核对判据原样保留）；全文无「为 readiness 单独申请新 `cmd-NN`」的形态文字；无法复用场景的文字指向「另立 CR」。
- 可达性说明：`dep-9` 的证据命令表要求每条命令有 `证据ID`/`executable`/`args`/`timeout` 且被交付覆盖表引用（`dep-7` 双向核对），因此「合法 `cmd-NN`」的定义域不含「仅 readiness 用」的命令行；本设计只引用既有行，不产生不可达的目标对象。

**AC-7（FR-6，零新增）**

- 设计落点：§4.6 的 diff 上界 + §6.4 的改动/零改动清单 + §9 `scope_in`/`zero_diff`。
- 可观测结果：交付 diff 只含 §1.3.1 表内 5 个文件（7 处落点）；`skills/shared/crctl/scripts/**`（含全部测试与 `gate-registry.json`）、`write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline`、pipeline 节点集与 reviewLoop、`tools/agents/**`、`agent-skill-matrix.yml`、`../multica/**`、KB `specs/`/`delivery/`/`docs/` 零 diff；节点数 5/4/12 与 `dep-16` 一致；账本字段 / 评审维度 / 观测指标 / crctl 子命令 / flag / 错误码零新增。
- 可达性说明：diff 面由 §6.5 的 7 处落点穷举（无第八处）；零 diff 面由 `dep-15` / `dep-17`~`dep-19` 的既有断言与 `dep-20` / `dep-22` 的门禁登记与 `dep-16` 的计数投影覆盖，不依赖人工记忆；`dep-16` 的节点计数是跨文件投影的唯一登记处，本设计不改该文件即可保持。

**AC-8（FR-1~FR-6，CR-2026-066 / 067 面零 diff）**

- 设计落点：§4.6 ④ + §6.4 零改动核对清单 + §9 `zero_diff`。
- 可观测结果：四个 review SKILL 的 Step 1.0 clean 前置与 Step 5 PASS 发布对账四要素（`phase` / `batchId` / `repositories[]` / `metadataCommit`）逐字保留；四 SKILL 不含 `crctl checkpoint`、不含三 token；`write-tech-design` / `review-tech-design` 零 diff；`dep-15`（CR-2026-043 / CR-2026-037 / 节点数 5/4/12）、`dep-17`（CR-2026-029）用例全部仍绿。
- 可达性说明：本设计的 diff 面不含这四个 SKILL 的 Step 1.0 / Step 5 / Step 6 与两份 CR-2026-067 目标文件，零 diff 是结构性结论（不是「未观察到」）；`dep-11` 文件的新增文字只进增量维度行，S-13 三 token 在新增文字中零出现（§6.5-E 逐字文本可直接核对）。

**AC-9（边界与串行）**

- 设计落点：§9 `scope_out` + §6.6 门禁回归面 + 本 CR 的串行事实（`dep-1` §7 顺序约束）。
- 可观测结果：实施与交付期间 `change-requests/_backlog.yml` 在途条目只有本 CR（CR-2026-063/064/065/066/067 均为 `archived`，`crctl status` 可核）；本 CR 在 CR-P1(067) 之后落地（本轮实读 067 = `archived` / terminal）；`suite-gate --run` 全量绿、`dep-20` 的 `manifest.cases` 与实际顶层用例数一致（36）、`exceptions` 为空数组。
- 可达性说明：串行与顺序是实施期可核事实（不属于本 SDD 的产物，由实施/交付期核对）；门禁面由 `dep-22` 的判据语义（`cases <` 登记值即红）机械判定，本设计预期零测试改动，故不存在「登记值需同步」的前置条件；若实施期用例数意外变化，按 `dep-1` §1.5 第 2 条同 CR 同步登记值、不签例外。

### 6.3 既有实现依赖与事实

**收录判据**：SDD 正文引用到的既有实现事实必须入册——① 设计判据的成立前提（文本形态、结构、调用顺序、断言面）；② 本 CR 直接修改的既有文本；③ §9 `zero_diff` 中设计所依赖的既有文本；④ SDD-CLOSE 的证据。**编号按正文首次出现顺序分配，只增不改；本文档无删除条目，故无编号空洞。**

**排序**：严格按正文首次出现顺序（不按仓分组）：编号即正文首次引用序，KB 设计输入与 tools 实现事实混排，因此同一仓的条目编号不保证连续；本文档无删除条目，故无编号空洞。正文对 `dep-1` 的 FR/AC 编号引用（如「FR-3」「AC-5」）是**需求合同标识引用**，不是既有实现事实。

**取证口径（SHA 三仓）**：

- `tools` 条目：`commit SHA` = 本 CR `tools` worktree HEAD `49fa37748d9b2fc7fc58fd53f839e2ed293bde17`（= `tools` trunk；`crctl workspace inspect` 实读 `head` 即该分支）。
- `ai-first-platform-docs`（KB）条目：`commit SHA` = 各过程产物的**引入提交**（本节逐条给出），KB worktree 起草时 HEAD = `a459fde8cb8af126cdb4edc5f89124acc0568c16`（`[cr] status CR-2026-068 requirement-approved -> tech-designing`），其前一步 `6e4d849bbc14ed0635f1053ae1d254daa6616acd` 为需求审批发布的 checkpoint metadata commit。
- `../multica` 条目：本 CR 无匹配依赖（零 diff，无常量事实被引用），故不登记；如需核对「未触碰」事实，以 `multica` worktree HEAD `d4a49e2b9ca7d83368737cd57d6a697d3bd042b4` 为基线。

```text
dep-1
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-068/prd.md
  stable symbol/对象: FR-1~FR-6、AC-1~AC-9、§1.3.1 修订面表与零 diff 清单、§1.3.3 契约说明（四查 N/A 的三条理由）、§1.4 事实 1~21、§1.5 七条口径、§7 范围排除
  commit SHA: bd86a82a50ad53f13d67d2a2dd7eb0e1a80c56e4
  依赖结论: 本 CR 的全部 FR/AC 与边界取自该需求合同（本轮实读全文 297 行）；SDD 的 §1.5 承接表、§6.4 零 diff 清单、§9 四字段均以它的明文为判据。其 §1.4 事实 21 的「cmp 逐字节一致 / 33,478 B」只在 EOL 归一后成立（该断言不构成本设计的任何前提，见 §1.5 末段与 SDD-CLOSE-05）。
```

```text
dep-2
  repo: ai-first-platform-docs
  relative path: docs/analysis/AIFI-18_SDD到planTASK_原位修订方案.md
  stable symbol/对象: §6（CR-P2，§6.1~§6.7 与边界段落）、§1.4「不增加观测指标」、§7「继续复用、不再造」清单、§8 实施顺序第 6 条
  commit SHA: 8c0df453ea1b59a38946515784538732249ad9f2
  依赖结论: 需求来源，钉定四项问题的根因与「原位改 + 零新增承载」的杠杆；本设计 §1.4.1~§1.4.5 的判据与 §5 的替代方案否决理由逐条对应该节原文。
```

```text
dep-3
  repo: tools
  relative path: skills/develop/write-dev-plan/SKILL.md
  stable symbol/对象: `### Step 2a — 回修模式（CR-2026-026 FR-8/FR-9）` 段落（普通轨三条；无 upstream 轨文字）与 TOC 的 Step 1 / Step 2 / Step 2a / Step 3 / Step 4 编号
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-1 的唯一修订面与不可破坏面（普通轨三条逐字保留、Step 编号不重编）；本设计在该段落内原位追加 upstream 轨，不新增小节。
```

```text
dep-4
  repo: tools
  relative path: skills/develop/write-dev-tasks/SKILL.md
  stable symbol/对象: `### Step 2a — 回修模式（CR-2026-026 FR-8/FR-9）` 第 1 条（现行「重新生成」段）与同节第 2、3 条
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-2 的唯一改写面；现行文字与 delta 语义直接矛盾（`重新生成` + `不保留旧 TASK`），本设计在同一段第 1 条内原位改写且保持 3 条结构，避免两套规则并存。
```

```text
dep-5
  repo: tools
  relative path: ARCHITECTURE.md
  stable symbol/对象: `## 4. 分层与依赖方向`（Pipeline → Skill → crctl 依赖只朝下）、`## 5. 硬不变量`（不变量 1 状态单一写者、2 账本单一写入通道、3 零第三方依赖、4 行尾与硬失败纪律、8 Skill 通用约束归仓）、`## 6. 刻意不做` 第 1 行、`## 8. 本文档的维护规则` 第 2 条（普通 Skill 措辞调整不需要改本文档）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: §1.3 的三条硬约束与多仓口径、§1.1 的 I1~I6 逐条取自本文件（本轮实读全文）；本 CR 不新增层级、不新增写入口与账本文件，且属「普通 Skill 措辞调整」故本文档零 diff。
```

```text
dep-6
  repo: tools
  relative path: skills/develop/write-dev-tasks/SKILL.md
  stable symbol/对象: `### Step 4 — TASK 数量三步断言与索引初始化`（三步断言 + `crctl task init --count-hint` + `TASK_COUNT_MISMATCH`）与「`tasks/_index.yml` 是受控账本，禁止 Agent/Skill 手写」句；Step 3 的 TASK frontmatter 与正文 6 节结构
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 索引刷新与账本写入通道的既有契约（也是 `dep-17` 用例的载体）；本设计只把 `crctl task init` 的角色钉为「只刷新索引」，不改其调用形态、不手写账本、不改 TASK 卡结构。
```

```text
dep-7
  repo: tools
  relative path: skills/develop/review-dev-plan/SKILL.md
  stable symbol/对象: `### Step 4 — 路由处理（双轨，CR-2026-026 FR-6/FR-6a/FR-6b）` 的 NORMAL / UPSTREAM 分支；`### 覆盖矩阵与流程控制核验` 的「两张稳定表同口径复核（CR-2026-060 AC-07）」双向唯一映射判据
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: upstream 轨的进入路径（`review-dev-plan:upstream-design-blocker` → `tech-design-review-pending`）与「验收证据 ↔ 证据ID」双向唯一映射的机械核对在该文件的既有段落内；本设计复用不修改（`zero_diff` 面），readiness 复用 `cmd-NN` 的硬边界以此为前提。
```

```text
dep-8
  repo: tools
  relative path: pipeline-templates/code-implementation.pipeline.json
  stable symbol/对象: 节点顺序 `…0001 write-dev-plan → …0002 write-dev-tasks → …0014 review-dev-plan → …0004 human_approval → …0005 approve-dev-start`；`…0014.reviewLoop.replayNodes` 三项（`repair-plan` / `purpose: regenerate-tasks` / `rerun-current-review`）与 `maxAttempts: 3`
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 「两个 authoring 节点 + 复审」的重放路径已存在，本 CR 只在 Skill 正文内明确 `purpose: regenerate-tasks` 的 delta 语义，节点集/顺序/replayNodes 逐字不变。
```

```text
dep-9
  repo: tools
  relative path: skills/develop/write-dev-plan/SKILL.md
  stable symbol/对象: `### Step 2 — 生成 plan.md` 的章节 6「两张稳定表」说明：交付覆盖表 5 列（`FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚`）与证据命令表 6 列；`验收证据` bullet（既有概括反假绿句）与 `回滚` bullet（现文「该 FR 的回滚单元（如 revert 某 TASK commit）」）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-3 写侧与 FR-4 的唯一修订面，也是两张稳定表列集与双向唯一映射的判据来源；本设计只在该说明的既有 bullets 内扩写，列集与表头不动。
```

```text
dep-10
  repo: tools
  relative path: skills/shared/controlled-shell/rules.json
  stable symbol/对象: `git` 白名单（子命令 + 形态 + 调用者三元）、`forbiddenFlags`、`protectedPaths.deny`（`change-requests/...`、`approval.yml`、`review-loop.yml`、`review-annotations/*.yml`）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-3 的「涉 Git 命令必须使用已允许的受控入口」以本文件为唯一事实源；本 CR 零 diff（不新开裸面、不放宽 deny），因此新文字只写「按 rules.json 既有允许面」而不复述规则细节。
```

```text
dep-11
  repo: tools
  relative path: skills/develop/review-dev-plan/SKILL.md
  stable symbol/对象: `### 增量职责与事实核验（CR-2026-055）` 的 `acceptance-verifiability` 行；`### Step 2 — 八类维度评审（FR-3）` 的「验收可验证性」行
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-3 评侧的唯一落点；现行文字只有概括判据（真实责任边界组合证明 AC、拒绝假绿短路），本设计在同一条内补齐两条可判定 blocker 判据，不新增维度名。
```

```text
dep-12
  repo: tools
  relative path: skills/develop/write-dev-plan/SKILL.md
  stable symbol/对象: `### Step 2 — 生成 plan.md` 的章节清单第 5 项「验收与发布策略」（现行说明仅「发布前 checklist / feature-flag 计划」）与章节总数 7
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-5 plan 侧的唯一修订面；本设计在该章节项说明内原位扩写环境五要素，章节总数保持 7（不新增第八节）。
```

```text
dep-13
  repo: tools
  relative path: skills/develop/implement-code/SKILL.md
  stable symbol/对象: `## 环境验证与 ENVIRONMENT_MISMATCH` 节（六条既有 bullets：一次环境检查 / 最多一次重跑 / timeout 与测试入口 / 标签不写 crctl 状态·gate·账本·评审 blocker·测试证据 schema / 临时隔离实例例外 / 受控建立归因）与「本 Skill 是有界验证与 ENVIRONMENT_MISMATCH 的唯一详细事实源」声明
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-5 implement 侧的唯一落点与该标签的单一事实源；本设计同节追加 readiness 即时性与「环境无关 TASK 不提前阻断」两条 bullets，既有六条逐字保留。
```

```text
dep-14
  repo: tools
  relative path: pipeline-templates/code-implementation.pipeline.json
  stable symbol/对象: 节点 `00000000-0000-0000-0015-000000000004`（kind=human_approval，label「确认进入代码开发」）的 `approvalPrompt` 现行值（拆分完成确认 + ✅ 通过 / ❌ 暂缓 两分支）与节点对象其余字段（id / kind / label / onFail / timeoutMinutes）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-5 dev-start 侧的唯一修订面；现行值不含环境内容，本设计只替换该字符串值（保留两分支、不写 git/journal、不残留 review-annotations 与 reject_reason），节点对象其余字段与节点集不变。
```

```text
dep-15
  repo: tools
  relative path: skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
  stable symbol/对象: CR-2026-043 用例（全部节点 `prompt` 与 `approvalPrompt` 对 `\bgit\b` / `\bjournal\b` 零命中）、CR-2026-050 FR-01 用例（human_approval 无 `review-annotations` / `reject_reason`、保留 approve/reject）、CR-2026-066 S-13 反向断言（四个 review SKILL 无 `crctl checkpoint` 与三 token）、节点数/顺序断言（12 节点、`…0014 < …0004 < …0005`）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 本 CR 新增文字的保持性约束来源（尤其 `…0004` approvalPrompt 的字面禁令与 `dep-11` 文件的三 token 禁令）；本设计通过约束写法满足这些断言，不新增/不修改测试。
```

```text
dep-16
  repo: tools
  relative path: pipeline-templates/_index.yml
  stable symbol/对象: `requirement-authoring-v1 nodes: 5`、`architecture-design-v1 nodes: 4`、`code-implementation-v1 nodes: 12` 三处计数（跨文件投影的唯一登记处）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 节点数口径 5/4/12 的唯一登记值与 CR-2026-066 的注释来源；本 CR 零 diff，故两侧计数天然一致（`dep-15` / `dep-17` 的等式断言仍绿）。
```

```text
dep-17
  repo: tools
  relative path: skills/shared/crctl/scripts/test/crctl.test.mjs
  stable symbol/对象: CR-2026-037 用例（`write-dev-tasks/SKILL.md` 必含 `crctl task init` 与 `禁止 Agent/Skill 手写`；不得含 `/重新生成.*TASK 与 `_index\.yml`/`；pipeline 节点数 ≡ `_index.yml`；节点 prompt 对受治理账本写指令零命中）与 CR-2026-029 用例（write-dev-tasks 与 pipeline 不含发布联调类 TASK 拆分指引）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: FR-2 改写后仍须满足的既有断言载体；本设计删除「重新生成」措辞使 doesNotMatch 天然仍绿，并保留两条 match 断言所需的字面量。
```

```text
dep-18
  repo: tools
  relative path: skills/shared/crctl/scripts/test/contract-scan.test.mjs
  stable symbol/对象: AC-1 扫描面（3 个 pipeline JSON + 11 个 SKILL.md 对 `repair-instructions` / `fixed-blockers` / `suggestion_policy` / `suggestion-policy` 零命中）与 RETIRED_RECOVERY（`recoverCommand` / `recover_command`）整树零命中
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 本 CR 新增文字不得引入退役字段名（`dep-1` FR-6 第 5 条）；该扫描面包含本 CR 的四个目标 SKILL 之一与 code-implementation pipeline，本设计零命中。
```

```text
dep-19
  repo: tools
  relative path: skills/shared/crctl/scripts/lint-prompts.mjs
  stable symbol/对象: R1~R13 规则集（R1 guard-deny 手写、R2 裸 git、R3~R5 字面黑名单、R7 crctl 参数形态、R9「下一步」收敛等）与 enforce 模式
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 新增文字在 Skill 内不得命中「手写受保护账本 / 裸 git / 手写 review-loop 记账 / 手写 test-report / 自造下一步映射」等规则；本设计的新文字只描述判据与写作口径，不出现裸 git 命令、不指示手写账本、不写状态映射副本。
```

```text
dep-20
  repo: tools
  relative path: skills/shared/crctl/scripts/test/gate-registry.json
  stable symbol/对象: `manifest.cases["pipeline-structure.test.mjs"] = 36` 与 `exceptions: []`（登记面）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 门禁登记值当前与实际一致（CR-2026-067 已同步）；本 CR 预期零测试改动，故不触碰该文件、不签任何例外。
```

```text
dep-21
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-068/review-annotations/requirement.yml
  stable symbol/对象: canonical 需求评审结论（verdict=pass / blockers=[] / suggestions 含「PRD §1.4 事实 21 的 EOL 事实」一条）与 review-loop.yml 的 attempt 记录
  commit SHA: 8895e9e6f48aad4a6c5ed54c074b78607799839a
  依赖结论: 需求期评审已闭合、无 blocker；该 suggestion 指明「字节级断言只在 EOL 归一后成立」，本设计据此按「内容一致（EOL 归一后）」理解来源对齐，且不在任何目标文本中写 `cmp`/字节数口径。
```

```text
dep-22
  repo: tools
  relative path: skills/shared/crctl/scripts/test/suite-gate.mjs
  stable symbol/对象: 门禁判据语义「每文件用例数 `<` `manifest.cases` 登记值即红（`SUITE_MANIFEST_CASE_DROP`）」，不变量 I1~I3（文件集合事实源、逐文件 TAP 归属、不可判即硬失败）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: AC-9③「suite-gate 全量绿 + 登记值一致 + 零例外」的判据来源；本 CR 不改该文件，改动面不新增用例也不删除用例。
```

```text
dep-23
  repo: tools
  relative path: skills/develop/write-tech-design/SKILL.md；skills/develop/review-tech-design/SKILL.md
  stable symbol/对象: `write-tech-design` `### Step 2.6 — AC 级输出合同与既有实现证据（CR-2026-055）` 内的「既有实现依赖与事实」合同段（`dep-N` 稳定标识、五要素固定结构、`commit SHA` 必填 40 位、编号按正文首次出现顺序分配且只增不改）与同名小节标题 `### 既有实现依赖与事实`；`review-tech-design` `### Step 2.1 — AC 闭环与既有实现依赖核验` 的 `dep-N` 引用核验规则（`sdd.explicit_existing_dependencies` 仅指该清单；正文出现未被 `dep-N` 引用承载的当前实现事实形成 blocker）
  commit SHA: 49fa37748d9b2fc7fc58fd53f839e2ed293bde17
  依赖结论: 本文档 §6.3 采用的 `dep-N` 固定结构以本条为唯一合同载体——`dep-5` 的 `ARCHITECTURE.md` 全文不含 `dep-N` /「既有实现依赖」字样，不承载该合同（本轮实读更正）；该合同由 CR-2026-067 实施提交引入并沿用至本次取证的 tools HEAD，自 CR-2026-067 合并起对后续 SDD 生效，本 CR 对这两个文件零 diff（§9 `zero_diff`），故合同面不发生变更；合同文本另由既有用例（`skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 的「CR-2026-055 blocker 修复: SDD 依赖清单输出与 reviewer 消费规则明确」）机械断言，属零改动保持面。
```
### 6.4 既有测试面改动清单与零改动核对清单

**改动清单：无。** 本 CR 预期不新增、不修改任何测试文件（`dep-1` §1.5 第 2 条）。逐条理由：

| 既有断言 | 与本次改动的关系 | 结论 |
|---|---|---|
| `dep-17` CR-2026-037 `doesNotMatch(/重新生成.*TASK 与 `_index\.yml`/)` | 「重新生成」措辞被删除 | 天然仍绿（删词不改结构） |
| `dep-17` CR-2026-037 两条 `match`（`crctl task init` / `禁止 Agent/Skill 手写`） | 两处字面量均在，`dep-6` 句未触碰 | 保持 |
| `dep-17` pipeline 节点数与受治理账本写指令零命中 | `…0004` 只改 approvalPrompt 值；新文本不含账本写指令；节点数不变 | 保持 |
| `dep-15` `\bgit\b` / `\bjournal\b` 零命中（全部节点 prompt + approvalPrompt） | 新 approvalPrompt 文本不使用这两个字面量 | 保持 |
| `dep-15` CR-2026-050 FR-01（human_approval 无 `review-annotations` / `reject_reason`，保留 approve/reject） | 新 approvalPrompt 保留 ✅/❌ 两分支、无违规残留 | 保持 |
| `dep-15` S-13 三 token 与 `crctl checkpoint` 零命中（四个 review SKILL） | `dep-11` 新文字不含这四个 token | 保持 |
| `dep-18` FORBIDDEN / RETIRED / RETIRED_RECOVERY 零命中 | 新文字不含这些字段名 | 保持 |
| `dep-20` `manifest.cases["pipeline-structure.test.mjs"] = 36`、`exceptions: []` | 零测试改动 | 保持（不签例外） |

**零 diff 核对清单（AC-7② / AC-8③ 的可核对形式）**：

| 零 diff 对象 | 核对方式 |
|---|---|
| `skills/shared/crctl/scripts/**`（含 `test/**`、`gate-registry.json`） | diff 面穷举（§6.5 无落点） |
| `write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline` | diff 面穷举（CR-2026-067 面） |
| 四个 review SKILL 的 Step 1.0 / Step 5 / Step 6 | `dep-15` 反向断言 + diff 面穷举 |
| `pipeline-templates/**` 除 `…0004` approvalPrompt 值以外 | diff 面穷举；节点集 / reviewLoop / 其余 prompt 与 `dep-8` 逐字一致 |
| `tools/agents/**`、`agent-skill-matrix.yml`、`dir-graph.yaml`、`ARCHITECTURE.md` | diff 面穷举 |
| `../multica/**` | diff 面穷举（不触碰该仓 worktree） |
| KB `specs/` / `delivery/` / `docs/` | diff 面穷举（`dep-2` 来源文档只读） |

**四字段自洽前置核对（`dep-7` / 评审 Step 2 的批准范围前置）**：① `scope_in` 与 `zero_diff` 无同对象冲突（§9 逐条比对：`scope_in` 的 7 处落点与 `zero_diff` 的零 diff 集合互斥）；② 无「外部治理规则强制修改」面——`dep-15` / `dep-17` / `dep-18` 对本 CR 的约束是**保持性**（不写某些字面量），不是强制修改，已在 §9 给出合法出口（约束写法而非改测试）；③ `scope_out` 未隐藏当前交付必须发生的修改（7 处落点全部列入 `scope_in`）；④ `follow_up` 未承载任何当前 AC 的必要条件。

### 6.5 目标文本清单（实施时逐字写入）

> 说明：以下为**逐字目标文本**（设计产物）。`…` 表示「原文逐字不变、此处省略」。7 处均为**原位替换或原位追加**：不新增小节、不新增章节、不重编号 Step、不新增列。目标文本内**不出现 `dep-N`**（`dep-N` 是 SDD 的引用形态，不进 Skill/pipeline 文本）。

#### 6.5-A `write-dev-plan/SKILL.md` — Step 2a 段落（`dep-3`）末尾原位追加 upstream 轨

**追加目标（既有三条之后，作为同节内的加粗小标题 + 四条，不另起 `###` 标题）**：

```text
**upstream 轨（SDD 重新批准后的增量回修）**：当回修输入来自 `review-dev-plan:upstream-design-blocker` 之后的 SDD 修订与重新批准（人工修订 → 重新评审 → 重新批准 → 按 pipeline 既有 reviewLoop 重放本节点）时：

1. 输入 = **新旧批准 SDD 的变更 delta** 与**同轮未闭合 plan blockers**；不把旧 plan 当作整轮作废。
2. 在**同一份 `plan.md`** 上只重算受影响章节、稳定表行、证据与回滚；未受影响内容逐字保留（重写面与 delta 成正比）。
3. coordinator 只传 subject、delta 与 canonical feedback 引用，**不指定具体行如何修改**。
4. 本轨不修改 review-route 枚举、不把 `repair-target` 改成多值：路由仍由既有 `review-dev-plan` Step 4 UPSTREAM 分支与状态机既有转换承载。
```

#### 6.5-B `write-dev-plan/SKILL.md` — 两张稳定表说明（`dep-9`）三处原位扩写

**（B-1）`验收证据` bullet：既有句逐字保留，其后追加三条子项**：

```text
   - `验收证据`：稳定标识 `cmd-NN`（两位十进制，与 `crctl test` 机器区 `commands` 1-based 下标及 `test-evidence/cmd-NN.log` 全等）；该命令必须实际覆盖本行所声称的验收面，不得只覆盖其中一部分造成假绿。
     - 观测面 ≥ 声称面：每个 `cmd-NN` 必须能观测该表行声称的 AC 结果；命令的可执行形态（`executable` / `args` / `cwd` / `timeout` 四项）沿用证据命令表 bullets 的既有口径，此处只引用不复述细节，不另立第二套形态判据。
     - 四类典型错配：`--list` 类命令不能证明浏览器行为；文件级 `--name-only` 不能证明符号级不变量；子集测试不能声称全量；涉及 Git 的命令必须使用 `rules.json` 已允许的受控入口（不新开裸面、不改 `rules.json`）。
     - 命令算法唯一事实源 = 证据命令表行；不得通过委派评论补写命令算法。
```

**（B-2）`回滚` bullet：既有句逐字保留，其后追加闭包判据**：

```text
   - `回滚`：该 FR 的回滚单元（如 revert 某 TASK commit）；被其它 TASK 消费的共享改动，其回滚单元必须包含受影响下游消费者，并与第 4 章「风险与回滚策略」的逆拓扑顺序一致；单点 revert 会破坏下游时不得声明为单点回滚。
```

**（B-3）证据命令表 bullets 之后追加一句（不改既有 bullets）**：

```text
   - 证据命令表的命令行是 `cmd-NN` 的唯一事实源：命令算法只写在表内（`executable` / `args` / `cwd` / `timeout`），不得另行改写或补写。
```

#### 6.5-C `write-dev-plan/SKILL.md` — 章节清单第 5 项（`dep-12`）原位扩写

**替换目标（该行说明整体替换；章节数保持 7、不新增第八节）**：

```text
5. **验收与发布策略** — 发布前 checklist / feature-flag 计划；若验收证据依赖常驻服务、浏览器或数据库，本节必须同时写明环境的静态前提与即时验证口径（不新增第八节）：
   - 环境 owner、建立方式、可获得性：责任人与获得途径，不写具体命令；
   - readiness 证据：必须复用**该环境所保障的那一行 FR 的既有 `cmd-NN`**（证据ID 照抄证据命令表，不新增命令行）。两张稳定表「验收证据 ↔ 证据ID」双向唯一映射不得放宽；确实无法复用时，该诉求超出本计划边界，**另立 CR** 修改稳定表合同与对应评审判据，本计划不放宽该映射；
   - 缺失时处置：按既有 `ENVIRONMENT_MISMATCH` 标签中止并报告所需建立动作（该标签的唯一详细事实源是 `implement-code`，此处只引用不复述）。
```

#### 6.5-D `write-dev-tasks/SKILL.md` — Step 2a 第 1 条（`dep-4`）原位改写

**替换目标（第 1 条整体替换；第 2、3 条逐字保留，条目数仍为 3）**：

```text
1. 逐条消费 blockers（每条内含可执行修复说明），并执行 plan→TASK delta 重算：`write-dev-plan` 完成 SDD→plan delta 后继续同步 plan→TASK；重算**直接受影响 TASK**（普通轨 blockers 指向的 TASK 与 SDD→plan delta 波及的 TASK 都是「直接受影响」的来源）及其**下游依赖闭包**（`depends-on` 可达的传递闭包），同步更新受影响 TASK 的输入、输出、接口（接口契约节的消费/产出签名）、命令、`depends-on`、完成标志与回滚；未受影响 TASK 保留；`crctl task init` 只用于刷新 `_index.yml` 索引，不承担重算语义（被评审判废/删除的 TASK 从文件集移除后由索引刷新反映）。
```

**保持项**：第 2 条（禁空转）与第 3 条（`tech-design-reviewed` 重放态）逐字保留；文件内不得出现第二套回修规则；`重新生成` 措辞在本文件内零残留。

#### 6.5-E `review-dev-plan/SKILL.md` — 增量维度 `acceptance-verifiability`（`dep-11`）同一条原位扩写

**替换目标（该 bullet 整体替换）**：

```text
- `acceptance-verifiability`：核对 TASK 验收步骤是否在真实责任边界组合证明 AC，拒绝无关依赖的假绿短路；同一判据覆盖证据命令的证明力——**观测面窄于声称面即 blocker**（命令无法观测该表行声称的 AC 结果、`--list` 类命令声称浏览器行为、文件级 `--name-only` 声称符号级不变量、子集测试声称全量），**命令形态越受控边界即 blocker**（涉及 Git 的命令未使用 `rules.json` 已允许的受控入口、命令算法只存在于委派评论而不在证据命令表行），不留到 implement 阶段才暴露。判据落在既有维度内，不新增维度名或证据账本。
```

#### 6.5-F `implement-code/SKILL.md` — 环境节（`dep-13`）末尾原位追加两条 bullets

**追加目标（既有六条 bullets 逐字保留，同节共生）**：

```text
- 即时 readiness：在**第一个依赖环境的 TASK 前**执行 plan 指定的 readiness `cmd-NN`；该命令是既有「一次环境检查」在环境依赖 TASK 上的执行内容（不是新的反复探测），仍受「最多一次重跑」、测试计划 timeout 与受控入口约束。
- 失败时按既有 `ENVIRONMENT_MISMATCH` 中止并报告所需建立动作；**环境无关 TASK 不被提前阻断**（readiness 未通过只阻断依赖该环境的 TASK）。
```

#### 6.5-G `code-implementation.pipeline.json` — 节点 `…0004` 的 `approvalPrompt` 值替换（`dep-14`）

**替换目标（JSON 字符串值；节点 id / kind / label / onFail / timeoutMinutes 不变，节点集不变）**：

```json
"approvalPrompt": "TASK 拆分已完成（change-requests/{{inputs.cr_id}}/plan.md 与 tasks/），当前应为 task-breakdown。请确认是否进入代码开发，并一并确认 plan.md「验收与发布策略」声明的环境静态前提：\n\n环境静态前提（只确认静态事实，不要求审批时所有服务在线）：环境 owner 已明确、建立方式已写明、可获得性已声明。动态健康状态由 implement-code 在第一个依赖环境的 TASK 前用 plan 指定的 readiness 证据即时验证，审批不为其背书。\n\n✅ 通过：勾选此 Todo，下一节点 approve-dev-start 会记录确认并推进到 developing\n❌ 暂缓：补充任务拆分意见或环境前提说明后，按缺口所属产物回到对应写作节点（plan 侧环境声明回 write-dev-plan、TASK 拆分侧回 write-dev-tasks）重新执行后再确认"
```

**字面量自查（逐条对应 `dep-15`）**：不含 `git` / `journal`（词边界、大小写不敏感均零命中）；不含 `review-annotations` / `reject_reason`；保留 ✅ 通过 / ❌ 暂缓两分支结构化决定。

### 6.6 门禁与回归面（NFR-1 / NFR-5）

| 项 | 结论 |
|---|---|
| 单元 / 集成测试改动 | **零**（§6.4）：既有断言全部为保持性关系，无一需要同步修改 |
| `dep-22` `suite-gate --run` | 期望全量绿；判据语义不变（`cases <` 登记值即红） |
| `dep-20` 登记面 | `manifest.cases` 保持 36、`exceptions` 保持 `[]`（不签任何新例外） |
| `dep-15` 字面禁令 | 新文本零命中（§6.5-G 自查；`dep-11` 新文字零命中三 token） |
| `dep-18` 退役字段 | 新文本零命中 |
| `dep-19` lint-prompts enforce | 新文本不得命中 R1~R13（不手写受保护账本、不裸 git、不手写 review-loop/test-report、不自造「下一步」映射） |
| CI | tools 仓既有 workflow 保持，无新增 step |
| 行尾 | 目标文件保持 LF 检出内容一致；读取方按既有 `readAllNormalized` / `replaceAll('\r\n','\n')` 归一（NFR-5、`dep-5` 不变量 4） |

### 6.7 SDD-CLOSE 关闭义务（CR-2026-060 AC-06）

**预检结论**：`dep-1` 全文（本轮实读 297 行）**未出现**「留待 SDD」「延后到设计」「设计期确定」类显式延后项（检索面：`dep-1`）；因此不存在「PRD 显式延后到 SDD 的设计项」这一义务来源。为便于 `review-tech-design` 机械核对，本 SDD 仍把四项需求期只给语义、需设计期钉定到可实施形态的事项逐项关闭（编号从 `SDD-CLOSE-01` 起：`SDD-CLOSE-01`~`04` 见本节表，`SDD-CLOSE-05` 见 §7.1）：

| 编号 | 事项（需求期状态） | 关闭结论 | 覆盖层（数据生产 / 存储·传输 / 响应·schema / 消费 / 兼容降级） |
|---|---|---|---|
| SDD-CLOSE-01 | plan 侧环境声明的**书写形态**（`dep-1` FR-5 只钉「不新增第八节」） | 关闭：写入章节清单第 5 项说明内的三条子项（§6.5-C），章节总数仍 7、不新增节、不新增表 | 生产 = 计划写作（Skill 正文）；存储·传输 = `plan.md` 章节 5 文本；schema = plan.md frontmatter 与章节集不变；消费 = `write-dev-tasks` / `implement-code` / dev-start 审批人；兼容降级 = 无 `cmd-NN` 复用 → 另立 CR |
| SDD-CLOSE-02 | `…0004` approvalPrompt 的**最终文字**（`dep-1` FR-5 第 6/7 条只给约束：保留两分支、无 git/journal、无 review-annotations/reject_reason） | 关闭：§6.5-G 给出逐字目标值并通过字面量自查；节点对象其余字段与节点集零变化 | 生产 = pipeline JSON 值替换；存储·传输 = `pipeline-templates/code-implementation.pipeline.json`；schema = 节点对象字段集不变；消费 = human_approval 节点展示 + `approve-dev-start`；兼容降级 = 无（纯文本） |
| SDD-CLOSE-03 | readiness 复用既有 `cmd-NN` 的**引用形态**（`dep-1` FR-5 第 4 条只给硬边界） | 关闭：§6.5-C 第二条子项——「证据ID 照抄证据命令表，不新增命令行」，且不放宽双向唯一映射；无法复用 → 另立 CR | 生产 = plan 章节 5 文本；存储·传输 = 同上；schema = 稳定表列集与证据ID空间不变；消费 = implement 侧 readiness 执行 + `review-dev-plan` 覆盖矩阵核对；兼容降级 = 另立 CR 出口 |
| SDD-CLOSE-04 | 「直接受影响 TASK」与「下游依赖闭包」的**判定口径**（`dep-1` FR-2 只给语义） | 关闭：§4.2 给出传递闭包口径（`depends-on` 可达），并由 §2.4 `TERM-02` 的边界场景验证（含无关 TASK 逐字保留） | 生产 = TASK 写作（Skill 正文）；存储·传输 = `tasks/TASK-*.md` 与 `tasks/_index.yml`；schema = TASK frontmatter 与 6 节结构不变；消费 = `review-dev-plan` 依赖拓扑维度与 `implement-code`；兼容降级 = 闭包为空时仅刷新索引 |

**未关闭项：无。** `dep-1` §7 明确交出的面（readiness 无法复用既有 `cmd-NN` 的诉求）已按需求合同落为 §9 `follow_up` 第 1 项（另立 CR），属需求期已钉定的出口，不是本 SDD 未关闭项。

**需求期 canonical suggestion 的承接（`dep-21`）**：`dep-1` §1.4 事实 21 的「`cmp` 逐字节一致 / 33,478 B」只在 EOL 归一后成立——本设计按「内容一致（EOL 归一后）」理解来源对齐，且**未在任何目标文本中写入 `cmp` / 逐字节 / 字节数口径**；该处属需求文本，本 CR 不改 `prd.md`（§9 `scope_out`）。相关行尾与硬失败纪律见 §7.1（SDD-CLOSE-05）。

---

## 7. 安全与性能考量

### 7.1 行尾纪律与硬失败（NFR-5）

- 新增/改写文本在四个 SKILL 与 pipeline JSON 中保持 **LF 检出内容一致**；实施期一次落盘后以二进制读取复核（不得出现混合 EOL）。
- 任何对仓库文件做哈希、跨行正则或逐行解析的步骤（含实施期的自查脚本）读入先 `\r\n → \n` 归一；跨行正则匹配失败**硬失败报错**，禁止「匹配不到 → 空集 → 静默通过」（`dep-5` 不变量 4）。
- **SDD-CLOSE-05**：本次不是新写解析器，而是新写文本；因此该纪律的落点是「实施后自查」：对 7 处落点做取证时，任何"以字节数或 `cmp` 判定一致"的做法都必须先归一行尾，或直接改用归一后文本比对——避免按字面字节复核产生假失败（`dep-21` 记录的需求期同类教训）。

### 7.2 边界与越权面

| 风险 | 控制 |
|---|---|
| 借 upstream 轨扩大重写面 | 只重算 `dep-1` 定义的受影响面；未受影响内容逐字保留（I1）；coordinator 不得指定具体行（`dep-3` 新文字第 3 条） |
| 借 delta 之名少修（漏修下游） | 依赖闭包强制同步（I2/§4.2）；`review-dev-plan` 既有依赖拓扑与 `acceptance-verifiability` 维度兜底 |
| 借「环境前提」新增账本/状态/节点 | §9 `zero_diff` 硬边界 + AC-7/AC-8 逐条核对；`ENVIRONMENT_MISMATCH` 不写账本、不写状态（`dep-13` 既有边界不变） |
| readiness 成为第二套验证语义 | 复用既有 `cmd-NN`（D-3）；write-dev-plan 侧只引用标签不复述语义（D-5、`dep-1` §1.5 第 4 条） |
| 新增文字触发既有 lint / 断言 | §6.6 逐条：字面量禁令自查 + lint-prompts R1~R13 面（`dep-19`） |
| 越权修改受保护文件 | 本 CR 不改 `_backlog.yml` / `cr.md` / `approval.yml` / `review-loop.yml` / `review-annotations/*`（`dep-10` deny 面）；状态推进唯一经 `crctl` |

### 7.3 唯一强度变化的兼容性说明

本 CR 的**唯一**语义强度变化是 `review-dev-plan` 的 `acceptance-verifiability` 判据收紧：观测面窄于声称面 → blocker；命令形态越受控边界 → blocker。该变化不改变任何 crctl 状态转换、错误码或 Skill 调用契约，只改变 `review-dev-plan` 的 blocker 判定输入；按 `dep-1` §1.3.3 第 4 条，评审判据只对评审发生时的 SKILL 版本生效，**对既有已归档 CR 无追溯效力**。其余六处改动均为表达与写作口径的原位扩写，不改变任何判定结果的目标集合（不新增维度名、不新增错误语义）。

### 7.4 性能与观测

- **性能**：本 CR 无运行时路径改动（纯提示词与人工审批文本），无性能目标面。
- **观测**：不新增任何观测指标 / SLO / 计数门禁（`dep-2` §1.4「不增加观测指标」）；`dep-1` §6 的成功指标是**实施后可统计的既有事实**（未受影响内容改写数 = 0、readiness 复用比例 = 100%、新增结构件 = 0 等），不落成新的账本字段或指标系统。

---

## 8. Prompt 采纳影响

**本节按条件性小节判定为「不适用」，理由（逐条对应条件）：**

- 本 CR 的 diff **不触及** `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支（该文件零 diff，§9 `zero_diff`）；
- 本 CR 的 diff **不触及** `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（`dep-10` 零 diff）；
- 因此不存在「crctl 新增/扩展子命令后某 skill 该采纳却未采纳」的清单面，无需列举应改调用方式的 skill。

（判定依据：`write-tech-design` 章节 8 的触发条件与 `review-tech-design` Step 2「Prompt 采纳影响」行；本 CR 的唯一 Skill 侧改动都是写作/评审判据，不涉及命令面采纳。）

---

## 9. 批准范围

### scope_in（当前 CR 必须交付的 FR/AC）

本 CR 必须交付 FR-1~FR-6 与 AC-1~AC-9，落为 **5 个 tools 文件、7 处原位落点**（逐字目标文本见 §6.5）：

1. `dep-3`：`write-dev-plan/SKILL.md` Step 2a 段落追加 upstream 轨四条（§6.5-A）
2. `dep-9`：同文件两张稳定表说明三处原位扩写（§6.5-B：`验收证据` 观测面判据 / `回滚` 闭包判据 / 证据命令表唯一事实源句）
3. `dep-12`：同文件章节清单第 5 项原位扩写环境五要素（§6.5-C）
4. `dep-4`：`write-dev-tasks/SKILL.md` Step 2a 第 1 条原位改写为 delta 重算 + 依赖闭包同步（§6.5-D）
5. `dep-11`：`review-dev-plan/SKILL.md` 既有 `acceptance-verifiability` 同条原位扩写两条 blocker 判据（§6.5-E）
6. `dep-13`：`implement-code/SKILL.md` 既有环境节末尾追加 readiness 即时性与环境无关 TASK 隔离两条 bullets（§6.5-F）
7. `dep-14`：`pipeline-templates/code-implementation.pipeline.json` 节点 `…0004` 的 `approvalPrompt` 值替换（§6.5-G）

### scope_out（明确排除的路径和能力）

- **不新增 Pipeline 环境节点**；不改节点集与节点数（保持 5/4/12）、不改 `…0014.reviewLoop.replayNodes` 条目、不改 `purpose: regenerate-tasks` 标签文本、不改 `review-route` 枚举、不把 `repair-target` 改成多值。
- **不做动态环境人工门禁**：dev-start 不要求审批时服务在线；不允许 coordinator 启停共享服务。
- **不新增评审观测指标**：无 SLO / 轮数承诺 / 计数门禁 / 聚合指标。
- **不改 upstream attempts 账本**：不把 upstream block 追加到 `attempts[]`、不新增 review-events、不改 `traceability.yml` schema。
- **不新增任何结构件**：账本字段 / 评审维度名 / crctl 子命令 / flag / 错误码 / Skill 参数 / 落盘文件 / lint 规则 / CI step 一律零新增。
- **零 diff 路径**：`skills/shared/crctl/scripts/**`（含全部测试与 `gate-registry.json`）；`write-tech-design` / `review-tech-design` / `review-code` / `write-test-report` / `coding-discipline`；`pipeline-templates/**` 中除 `…0004` approvalPrompt 值以外的全部内容；`tools/agents/**`；`agent-skill-matrix.yml`；`dir-graph.yaml`；`ARCHITECTURE.md`；`../multica/**`；KB 的 `specs/` / `delivery/` / `docs/`（`dep-2` 来源文档只读）；KB 的 `prd.md`（需求文本，含 `dep-21` 记录的事实 21 表述）。
- **交给后续 CR 的能力**：readiness 无法复用既有 `cmd-NN` 时的稳定表合同与评审判据修改（见 `follow_up` 第 1 项）。

### zero_diff（明确不得改动的调用点 / 签名）

| 对象 | 不得改动的理由 / 出口 |
|---|---|
| 两张稳定表的表头与列集（交付覆盖表 5 列、证据命令表 6 列）与「验收证据 ↔ 证据ID」双向唯一映射合同 | `dep-7` 覆盖矩阵节机械核对；本 CR 只改列内写作判据（AC-3⑤、AC-6①） |
| `tasks/_index.yml` 受控账本形状与 `crctl task init` / `task done` 的调用形态与契约 | `dep-6` / `dep-17`；账本写入唯一经 crctl（`dep-5` 不变量 2） |
| `ENVIRONMENT_MISMATCH` 标签语义与其「唯一详细事实源」地位（`dep-13` 节内既有六条 bullets 逐字保留） | `dep-1` §1.5 第 4 条；write-dev-plan 侧只引用不复述 |
| 四个 review SKILL 的 Step 1.0 clean 前置、Step 5 PASS 发布与对账四要素、Step 6 摘要 | CR-2026-066 面（`dep-15` 反向断言；AC-8①） |
| `skills/shared/crctl/scripts/**`（含 `gate-registry.json`）与 crctl CLI 契约 | AC-7②；`dep-10` 的 `protectedPaths.deny` 与 git 白名单 |
| `pipeline-templates/**` 的节点集 / reviewLoop / 其余 prompt / `_index.yml` 计数 | `dep-8` / `dep-16`；AC-7③ |
| 状态机与 gates 声明（`dir-graph.yaml#change-request-track.state_machine`、`gates.json`） | `dep-5` 不变量 1 / 5 |

### follow_up（发现但留给后续 CR 的缺口）

1. **readiness 无法复用既有 `cmd-NN` 的场景**：需修改两张稳定表「验收证据 ↔ 证据ID」双向唯一映射合同与对应评审判据（本 CR 不放宽该映射）；出口 = 另立 CR（`dep-1` FR-5 第 4 条、§7）。
2. **需求文本的 EOL 表述**：`dep-1` §1.4 事实 21 的「`cmp` 逐字节一致 / 33,478 B」建议在后续需求侧 revision 改写为「内容一致（EOL 归一后逐字节一致）」并注明结论不受影响（`dep-21` 的 canonical suggestion）；该处属需求文本、非本 CR 交付面。
3. **观测面判据的机械化**：本 CR 的判据以 Prompt 合同形式落在写侧与评侧，尚无可判定的机械校验面；若未来需要机械校验（如证据命令表行的静态扫描），需另立 CR 评估（本 CR 不新增 lint 规则 / crctl 校验面）。

---

## 修订记录

- 初稿（2026-09-15）：按冻结 PRD（`dep-1`，`sha256(LF)` = `5cb67f17d6d6e0e8076712873b186b3286734045ba11cf5cd57ad114d42f2596`）与需求来源（`dep-2` §6）起草；基线事实在 `tools@49fa3774`、`multica@d4a49e2b`、KB worktree@`a459fde8` 上逐条核实（§6.3 共 22 项依赖）。
- 回修 1/3（2026-09-15，`review-tech-design` attempt 1/3 = BLOCK 定点修复，被修复版本 `sha256(LF)` = `1eceb0575ade7f0aba534e149666d248d089e2d6f53b9e451e24a7e5bbac56bb`）：① 按 blocker 把 `dep-N` 合同的真实载体（`tools@49fa3774` 实读：`write-tech-design` 的「既有实现依赖与事实」合同段与 `review-tech-design` Step 2.1 引用核验规则）登记为 §6.3 `dep-23`，并把 D-6 Context 与 §2.2 `S6` 行中该合同对 `dep-5` 的错误归属改为指向 `dep-23`（`S6` 行经 §5 D-6 指向，以保持 §6.3「按正文首次出现顺序编号」）；§6.3 依赖项计数由 22 改为 23。② 采纳本轮四条 `范围外` suggestion：§6.7 的编号定义范围、§1.2 鸟瞰图的落点计数单位、§6.5-G `❌` 分支的修复路径、§6.5-B `B-1` 中命令形态的复述改为引用证据命令表 bullets 口径。③ 修正 §4.5 / §6.2 的 `readinesMap` 拼写为 `readinessMap`。除上述定点修订外，§6.5 其余目标文本、§9 四字段、D-1~D-5、SDD-CLOSE-01~05 均未改动。

## CR 流程降本提效首期：FR-8 成本基线 + FR-1 OutputGuard + FR-2 crctl 输出瘦身（v0.42 · CR-2026-069）

## 1. 架构概览

### 1.1 设计目标与不变量

本 CR 的技术设计只做一件事：**在「工具结果进入下一轮模型上下文之前」与「crctl 成功输出投影层」两个面上做减法，并用一份离线度量把「省了多少、有没有变差」变成可证伪的事实**。设计输入是需求合同（`dep-1`：FR-8 / FR-1 / FR-2、AC-1～AC-21）与需求来源（`dep-2` §5～§10）；设计边界由 `dep-1` §1.3.1 / §1.3.2 / §7 与 `dep-2` §2 / §3.1 / §11 钉定：**零新增治理结构**。

落成九条设计不变量（供 `review-tech-design`、plan/TASK 与 `implement-code` 逐条核对）：

| # | 设计不变量 | 判据落点 |
|---|---|---|
| I1 | **Core 无状态且确定性**：Core 是纯函数；同一决策指纹（`policyVersion` + 命中规则标识 + 规范化参数 + 规范化原始正文）在同一 policy 版本下必须产生逐字相同的模型可见结果与 trailer；跨调用零状态（不建授权文件、nonce、永久开关、"下一次调用"状态） | FR-1 第 1/6 项、§4.2、§4.4、AC-3 / AC-6 |
| I2 | **三份 JSON 各自唯一事实源**：`policy.json`＝阈值与命令族、`capabilities.json`＝Runtime 能力、`conformance.json`＝跨 Adapter 合同；代码、Prompt、Skill、README 一律不复刻其内容，只引用 | FR-1 第 1 项、NFR-2、§2.3 / §3.5、AC-3 / AC-13 |
| I3 | **seam 唯一**：裁剪只发生在「Runtime 原生工具调用 → Adapter → Core → 模型可见结果」这一条链上；下游 transcript / preview / daemon 展示层零改动 | FR-1 定位段、§1.3、AC-12 |
| I4 | **完整性与覆盖度诚实**：被裁剪结果必须标 `complete=false`；不可安全保持字段/结构则不裁剪并标 `coverage=unavailable`；`complete=false` 不得作为充分门禁证据；降级必须显式，不得静默假装生效 | FR-1 第 5/8 项、NFR-6、§4.2 / §4.5、AC-8 / AC-15 / AC-16 |
| I5 | **FR-2 只动呈现层**：唯一改动面是成功输出的投影层；退出码、错误码与错误体、字段语义、状态、门禁、审批、CAS、事务与 Git 行为逐一不变 | FR-2 第 3～5 项、§4.6、AC-10 / AC-11 |
| I6 | **度量只读且非权威**：FR-8 不推进 CR、不参与门禁、不写状态与账本；机器结果只有一份 JSON；口径与观测时刻随输出；样本数不硬编码 | FR-8 第 1/3/6 项、§4.7、AC-17 / AC-18 |
| I7 | **治理面零新增**：无新状态、门禁、审批、Pipeline 节点、账本、数据库、仪表盘、sidecar 日志、WAL、CAS 层、远程开关；跨仓写入一律复用既有事务与 checkpoint | NFR-1、§4.9、AC-1 / AC-2 |
| I8 | **同一 Release 原子发布 + 单点回滚**：Core + 三份 JSON + 五个 Adapter 属同一 Tools Release；单 Runtime 误伤只禁用该 Adapter（新会话生效） | FR-1 第 10/12 项、§3.4、AC-19 / AC-14 |
| I9 | **行尾与硬失败纪律**：任何对仓库文件或 session 文件做哈希、跨行正则、逐行解析的代码，读入先 `\r\n → \n`，解析用 `split(/\r?\n/)`，匹配失败硬失败报错（禁止"匹配不到 → 空集 → 静默通过"） | NFR-8、`dep-3` §5 不变量 4、§7.1 |

**本 CR 的核心架构判断**（三条，全部由 `dep-1` / `dep-2` 钉定，SDD 只做落点选择）：

1. **成本杠杆在"治理点位置"，不在"提示词自律"**：seam 必须在模型可见结果之前（I3）；因此 Adapter 必须挂在 Runtime 的**工具结果回填 hook**上，而不是在 daemon 的 transcript/preview 上做二次加工。
2. **裁剪必须是"确定性、非语义"的**：不调用 LLM、不做语义压缩，只做"唯一文件列表 / 连续行窗口 + 原始行号 / 头尾保留"三类机械变换（§4.3）；任何需要理解语义的收窄交回给模型（通过 trailer 提示下一次 `offset/limit` 或缩小范围写法）。
3. **降级必须是"显式 fail-open"且与 fail-closed 安全层正交**：OutputGuard 失效时原调用继续、结果不改（安全层不受影响）；crctl / Git / 账本 / 审批的 fail-closed 行为不因 OutputGuard 而改变（§7.2）。

### 1.2 变更面鸟瞰

本 CR 交付 diff = 三个仓的**新增为主 + 既有文件最小改动**，无删除文件、无新状态、无新节点、无新账本。计数单位：新增文件按"文件"计，既有文件按"落点"计。

```text
../tools（方法论包；本 CR 代码实施面主体）
  新增：
    output-guard/core.mjs                                     ← FR-1 纯函数 Core（无依赖，node 内建）
    output-guard/policy.json                                  ← FR-1 阈值/命令族唯一事实源（数值由 TASK-01 产出）
    output-guard/capabilities.json                            ← FR-1 Runtime 能力唯一事实源
    output-guard/conformance.json                             ← FR-1 跨 Adapter 共享测试向量
    output-guard/README.md                                    ← 模块总览 + 权威入口链接（不复制政策内容，AC-13）
    output-guard/adapters/pi/index.ts                         ← TASK-03（pi extension：tool_call + tool_result）
    output-guard/adapters/pi/README.md
    output-guard/adapters/claude/{pretooluse-guard.mjs,posttooluse-guard.mjs,settings.template.json,README.md}   ← TASK-04
    output-guard/adapters/codebuddy/{pretooluse-guard.mjs,posttooluse-guard.mjs,settings.template.json,README.md} ← TASK-05
    output-guard/adapters/qoder/{pretooluse-guard.mjs,posttooluse-guard.mjs,settings.template.json,README.md}     ← TASK-06
    output-guard/adapters/codex/{pretooluse-guard.mjs,posttooluse-guard.mjs,hooks.json.template,README.md}        ← TASK-07
    output-guard/scripts/check-install.mjs                    ← 启动检查：只报告缺失/损坏 + 明确修复命令（AC-19③）
    output-guard/test/{core.test.mjs,conformance.test.mjs,adapters-contract.test.mjs}   ← FR-1 回归面
    skills/shared/metrics/scripts/cr-cost.mjs                 ← FR-8 度量脚本（TASK-01 / TASK-10）
    skills/shared/metrics/scripts/lib/{sessions.mjs,aggregate.mjs,select.mjs,render.mjs}  ← FR-8 纯函数分层
    skills/shared/metrics/test/cr-cost.test.mjs               ← FR-8 回归面
    skills/shared/crctl/scripts/lib/summary-projectors.mjs    ← FR-2 独立 summary projector（TASK-08）
    skills/shared/crctl/scripts/test/crctl-summary.test.mjs   ← FR-2 summary/detail 合同测试（TASK-08）
    skills/shared/crctl/scripts/test/caller-contract.test.mjs ← FR-2 调用方扫描断言（AC-21①）
    skills/shared/crctl/scripts/test/golden/crctl-detail/*.json ← 改造前完整输出金样本（字段路径 + 稳定值）
  既有文件改动（落点逐个列明）：
    skills/shared/crctl/scripts/crctl.mjs                     ← 3 处：ok() 投影入口 / parseArgs 的 --detail 布尔化 / HELP 一行
    skills/shared/crctl/scripts/test/gate-registry.json       ← manifest.files + manifest.cases 同步（AC-21②）
    skills/shared/crctl/SKILL.md                              ← `--detail` 采纳（§8）
    skills/develop/review-{tech-design,code,dev-plan}/SKILL.md ← 取证完整性规则采纳（AC-16，§8）
    skills/requirement/review-requirement/SKILL.md            ← 同上（取证完整性规则 + 按 A10 表定点补 `--detail`；§9 scope_in 第 4 项）
    skills/{requirement/approve-requirement,develop/approve-tech-design,develop/approve-dev-start,develop/approve-code}/SKILL.md ← 按 A10 表定点补 `--detail`（§9 scope_in 第 4 项）
    skills/sync/**（A10 表命中项）                             ← 同上
    pipeline-templates/*.pipeline.json（**仅 prompt 文本**）    ← A10 表判定命中时定点补 `--detail`（零节点 / 零 reviewLoop 变化；§9 scope_in 第 4 项）
    agents/*.md（A10 表命中项）                                ← 同上
    README.md                                                 ← §8「权威事实源链接」增一行 + §4 一行导航（AC-13）
    ARCHITECTURE.md                                           ← §1 鸟瞰的组成面清单增一条（本包新增 Runtime 侧执行面 `output-guard/`）+ §3 代码地图增 output-guard / metrics 两条；§4/§5/§6 不改——依据 §8 维护规则：不新增 skills 顶层分组、无 Pipeline 结构性变化、crctl 未新增写入子命令、状态机口径未变、未推翻任何否决记录
    .github/workflows/crctl-ci.yml                            ← paths 增 output-guard/** + metrics/**；steps 增两条测试步骤
  明确零 diff（见 §9 zero_diff）：
    skills/shared/crctl/scripts/lib/durable-tx.mjs、lib/workspace-transactions.mjs、lib/outbox-contract.mjs、
    lib/yaml-subset.mjs、gates.json、dir-graph.yaml、
    pipeline-templates/*.pipeline.json 的**结构**（节点数 5/4/12、reviewLoop / replayNodes / maxAttempts；prompt 文本见上「既有文件改动」）、
    agent-skill-matrix.yml、skills/shared/controlled-shell/rules.json

../multica（平台底座；只做 Runtime 启动挂载，挂载先例与挂载点见 `dep-4`）
  新增：server/internal/daemon/execenv/outputguard_config.go   ← TASK-09 挂载解析 + claude 合成入参（不复制 policy）
  既有文件改动：server/internal/daemon/execenv/crguard_config.go ← 单写入点内合成 OutputGuard hooks（新增可空入参；**仅 provider=claude 分支**，见 §4.9）
              server/internal/daemon/execenv/*_test.go（同包回归测试）
              CUSTOM.md                                        ← 按其现状登记本次定制（AGENTS.md 纪律 10）：按 §9 scope_in 第 5 项**必须新增台账条目，不适用零 diff**
  明确零 diff：server/internal/daemon/tool_output_preview.go、server/internal/governance/runner.go、
              server/pkg/agent/pi.go（不新增/不放开任何 argv 面）、Provider 事件归一化实现

ai-first-platform-docs（KB：只承载本 CR 过程产物）
  变更：change-requests/CR-2026-069/{sdd.md（本文档）、evidence/fr8-baseline.json（TASK-01 / TASK-10 机器结果副本）、
        evidence/ac9-sampling.md（AC-9 的合法调用抽检清单与判定）、evidence/ac14-smoke.md（AC-14 的各 Runtime 冒烟记录 + 每个 Runtime 一行 check-install 输出）}
  零 diff：specs/、delivery/、docs/、四账本（cr.md 除 crctl 状态行外、_backlog.yml、traceability.yml、
          tasks/_index.yml）、prd.md（已随审批按 evidence-digest 钉住，本阶段不得改写）
```

**改动量上界**：`crctl.mjs` ≤ 6 行（不含新增导入）；`crguard_config.go` ≤ 40 行（新增入参 + hooks 合成，原行为在入参为 nil 时逐字不变）；其余既有文件均为"增行/加一段"，无既有语义改写。

### 1.3 依赖方向与分层与多仓口径（不变）

```text
Agent → Pipeline → Skill → crctl                         （治理链，本 CR 不动；AC-1）
Runtime 原生工具调用 → Runtime Adapter → OutputGuard Core → policy.json
                                                          （本 CR 新增的唯一裁剪链，FR-1）
离线度量脚本 → 既有 session / provider usage（只读）       （本 CR 新增的唯一读链，FR-8）
```

三条硬约束逐字取自 `dep-3`（§4 分层与依赖方向、§5 硬不变量、§6 刻意不做）：

- 依赖只朝下；Skill 不得绕过 crctl 直接改写账本（本 CR 不新增第二条账本通道；度量脚本零账本写入）。
- 「另一套独立 WAL/事务框架」是既有禁区（`dep-5` 是跨文件与跨仓写入的唯一实现）；本 CR 的新增代码不引入锁、journal、write-set、CAS 或提交框架。
- 「零第三方依赖」是 `dep-6` 所在层的既有不变量；`output-guard/` 与 `skills/shared/metrics/` 沿用同一口径（只用 `node:*` 内建模块，无 `package.json`、无构建步骤）。

**多仓路径 authority**（`dep-1` §1.3.2 的目标仓表 + `write-tech-design` Step 1）：本 SDD 的全部仓内路径只以 `crctl workspace inspect CR-2026-069` 返回的 `resources[].worktreePath` 为根，禁止按 `.rayai-worktrees/{repo}/requirement/{cr}` 目录命名拼接。三仓 worktree 事实（本轮 `workspace inspect` 实读，classification 均 `healthy`、`dirty=false`）：`ai-first-platform-docs`、`multica`、`tools`。

### 1.4 关键流程

#### 1.4.1 一次工具调用的完整决策链（FR-1）

```text
① Runtime 自身权限与既有安全控制（`dep-7` 白名单 / protected paths / 审批 / 账本写入控制）
      ↓ 先于 OutputGuard，且 OutputGuard 既不评估也不放宽
② Adapter Pre 侧（Pi: tool_call；Claude/CodeBuddy/Qoder/Codex: PreToolUse）
      → 取"原始命令首行"判定一次性逃生阀标记
      → 解析失败/畸形 → 视为"不存在该标记"（§4.1，不拒绝调用、不新增 action 取值）
      → 逃生阀合法 → action=passthrough，跳过全部封顶，仍受 ①
      → 命中命令族且可判定 → action=block（拒绝 + 可执行替代写法）
                             或 action=rewrite（对参数施加上限后执行）
      → 不确定（管道/重定向/脚本嵌套）→ 允许执行，进入 ③ 的统一封顶
③ 工具执行
④ Adapter Post 侧（Pi: tool_result；Claude/CodeBuddy/Qoder: PostToolUse.updatedToolOutput；Codex: PostToolUse feedback 路径）
      → 先做"可保持性检查"：Runtime 结果结构能否承载 toolName/toolCallId/isError/exitCode(若该 Runtime 有)
      → 不可保持 → action=unavailable，结果逐字不改，标 coverage=unavailable（§4.2）
      → 可保持 → Core 纯函数裁剪 → action=truncate，追加一行 trailer，标 complete=false
      → 未命中任何规则 → 不追加任何文本（§6.7 的"正常未触发调用不增加文本"）
⑤ 裁剪后的结果进入下一轮模型上下文 / session / transcript
```

终态取值集合固定为 `{block, rewrite, truncate, passthrough, unavailable}`，不新增第六个取值（`dep-1` FR-1 第 7 项）。

#### 1.4.2 降级与覆盖度派生（FR-1 → FR-8）

```text
安装期：output-guard/scripts/check-install.mjs  → 每个 Runtime 一行 output-guard runtime=… coverage=… policy=v1
        （只读检查：Adapter 是否被 Runtime 的配置面引用、policy/capabilities/conformance 是否可解析）
运行期：Adapter 加载失败/被禁用/bundle 损坏/policy 解析失败 → OUTPUT_GUARD_UNAVAILABLE runtime=… reason=<四值枚举>
        → 原调用继续、结果不改（fail-open）→ 该会话 coverage=unavailable，排除出完整覆盖样本
离线期：cr-cost.mjs 读取既有 session + 启动检查记录 + trailer，派生 coverage{runtime→full|partial|unavailable}
```

三级 scope（`dep-1` FR-1 第 10 项 / AC-19④）的落点与"谁来做安装"：

| scope | 配置面（各 Runtime 既有面） | 本 CR 的动作 | Adapter 是否由本 CR 自动写入 |
|---|---|---|---|
| Project | 目标 workspace 内的 `.claude/settings.json` / `.lingma/settings.json` / `.codebuddy/settings.json` / `.pi/extensions/`（或 `.pi/settings.json#extensions`） | 提供模板 + 安装说明 + 检查命令 | 否（人工安装一次） |
| User | `~/.claude/settings.json` / `~/.lingma/settings.json` / `~/.codebuddy/settings.json` / `~/.pi/agent/settings.json#extensions` | 同上 | 否（人工安装一次） |
| Managed | **必须区分两类对象**：① **记忆文件** —— daemon 每任务写入的 `CLAUDE.md` / `CODEBUDDY.md` / `AGENTS.md`（`dep-15`）；② **hooks 配置文件** —— daemon 侧的写点**只有 claude 一个**：`{workDir}/.claude/settings.json`（`dep-4`）。codebuddy / qoder **没有** hooks 写点（`dep-15` 对二者只写记忆文件与 `.codebuddy/skills/`） | claude：daemon 单写入点合成（TASK-09）；codebuddy / qoder：**显式安装一次**（项目级 `<project-root>/.codebuddy/settings.json` / `.lingma/settings.json`，或用户级 `~/.codebuddy/settings.json` / `~/.lingma/settings.json`）；Pi：宿主级 `~/.pi/agent/settings.json#extensions` 安装一次；Codex：宿主级 `.codex/hooks.json` + 信任步骤（partial） | **只有 claude**；其余四个 Runtime 人工安装一次（逐 provider 落点见 §4.9 第 3、4 步；生效性由 `check-install.mjs` 读数 + AC-14 真实任务冒烟判定，不由部署过程自证） |

#### 1.4.3 FR-2 成功输出投影（一次命令的呈现层）

```text
main() 取 cmd 与 flags
   → resolveProjection(cmd, flags)：
        flags.detail === true            → null（走原路径，逐字段完整输出）
        cmd 不在 SUMMARY_PROJECTORS 中    → null（未投影命令等价于现状）
        否则                              → 该命令的纯投影函数
   → 分发到 cmdXxx()
        → 成功出口 ok(obj)  ← 唯一投影点，未注册投影时空转
        → 失败出口 fail(code,msg,extra) ← 零改动（247 个出口全部不进投影）
```

#### 1.4.4 FR-8 两次执行与扩项判定

```text
改造前（TASK-01）：cr-cost.mjs baseline --out <path>
   → 读既有 session（只读）→ 样本筛选（目录/类型/时间窗/CR-ID 归属）→ 归一化指标 + crctl 命令聚合
   → 对历史 session 离线回放 OutputGuard policy（纯函数重算，不执行任何命令）
   → 输出唯一机器 JSON（字段集 ≡ PRD FR-8 第 3 项 / 来源 §5.4）+ stdout 人读摘要（同一对象渲染）
   → 选出"覆盖 ≥80% crctl 输出 token 的最小命令集合" → 交 TASK-08 落进 projector 注册表
部署后（TASK-10）：cr-cost.mjs after --window 14d
   → 只统计 coverage=full 且带 CR-ID 的完整 Pi CR
   → 目标桶 tokens/CR ≥20% 下降 ∧ 三项质量护栏全不恶化 → 才允许重新立项评估 FR-3～FR-9
   → 样本不足 → 输出 insufficient-sample，不产出成本结论、不延长本 CR
```

#### 1.4.5 本 CR 自身的交付顺序（十个 TASK 的依赖，不新增节点）

```text
TASK-01（FR-8 基线 + 命令聚合 + 历史回放）
   ├─→ TASK-02（Core / policy / capabilities / conformance）
   │        ├─→ TASK-03 Pi ─┐
   │        ├─→ TASK-04 Claude ─┤
   │        ├─→ TASK-05 CodeBuddy ─┼─→ TASK-09 Multica 挂载（daemon 单写入点：仅 claude）→ TASK-10 部署后复测
   │        ├─→ TASK-06 Qoder ─┤
   │        └─→ TASK-07 Codex ─┘
   └─→ TASK-08（FR-2 summary/detail + 调用方同步 + 棘轮登记）
```

启用顺序（部署顺序，不新增 CR 状态或 Pipeline 节点）：`Pi → Claude → CodeBuddy → Qoder → Codex(partial)`；每个 Runtime 以「conformance 通过 + 真实冒烟通过 + 降级验证通过」为下一项的前置（AC-20）。

#### 1.4.6 术语预检（Step 2.5 结论）

只对进入数据模型/接口契约且存在歧义风险的术语硬化，结论如下（不新增术语表文件，本节即载体）：

| 术语 | 歧义风险 | 本 SDD 的裁决（全文唯一口径） |
|---|---|---|
| `coverage` | `dep-1` 在两处使用：FR-1 的"路径/会话覆盖度标记"与 FR-8 输出的 `coverage{runtime→full\|partial\|unavailable}` | **三级正交定义**：`level`（Runtime 治理能力，声明于 `capabilities.json`，取值 full/partial/unavailable）/ `pathCoverage`（某条 Runtime 路径是否被治理，声明于 `capabilities.json.paths[]`）/ FR-8 输出的 `coverage[rt]`（**派生投影**：由 `level` + 窗口内是否观测到该 Runtime 的 `OUTPUT_GUARD_UNAVAILABLE` 与启动检查记录共同决定）。FR-8 的 `coverage` 永不作为声明源，只作派生值 |
| `complete` | trailer 的 `complete=false` 与 Runtime 自身的截断字段（如 Pi 的 `details.truncation`）可能被读成同一件事 | `complete` 只表示"**模型可见结果正文是否等于工具原始结果正文**"；Runtime 自身的截断字段语义不变、不被本 CR 改写（`V-3`）。两者同时出现时，`complete=false` 由 OutputGuard 产生，Runtime 字段保持原样 |
| `action` | `unavailable` 在 `dep-1` FR-1 第 7 项与第 5 项中来源不同 | `action` 是**单次调用的终态裁决**，取值闭包五值；`unavailable` 有两个合法来源：其一为第 8 项的 bundle/policy 降级面（连带 `OUTPUT_GUARD_UNAVAILABLE` 码），其二为第 5 项的"字段/结构不可安全保持"路径面（不产生错误码，只产生 trailer + `pathCoverage=unavailable`）。二者不合并、不新增取值（同时关闭 `dep-1` §1.5 第 5 条与需求评审 S-2） |
| `escape hatch` / 逃生阀 | 与"绕过安全控制"混读 | 逃生阀**只影响 OutputGuard 自身的封顶**（`action=passthrough`），对 `dep-7` 的 git 白名单 / protected paths / 审批 / 账本写入控制**零影响**（AC-6 四条负向测试） |
| `--detail` | 与"新增输出模式"混读 | `--detail` 是**布尔型呈现层开关**，只决定"成功输出是否被投影"；不参与状态判定、门禁、审批、CAS；未投影命令收到它是**布尔真但无投影函数 → 与现状等价**（同时关闭需求评审 S-1） |
| `policyVersion` | 被读成"多版本兼容/迁移" | 只表示**格式版本**；不建多版本兼容、不建迁移框架、不支持同时加载两版 policy（FR-1 第 10 项） |
| `k` | 被读成"真实账单节省" | `k = 计费金额来源值 ÷ 同区间工具结果 token`；**必须同时输出金额来源标识与分母 estimator 标识**；金额来源不可得时 `k=null` 且禁止任何金额宣称（FR-8 第 4 项、AC-18；需求评审 S-4 的计数口径类风险由 §3.6 的 `observedAt` + `rule` 义务关闭） |

**语义冲突结论**：以上裁决全部是对 `dep-1` 内部两处用词的对齐（`dep-2` 未与 `dep-1` 冲突），**不构成需要需求负责人澄清的语义冲突**，因此不阻塞首次状态推进（`crctl advance --to tech-designing` 已在草案落盘前执行）。

### 1.5 与 PRD §1.5 九条口径的承接

`dep-1` §1.5 的九条中：五条为需求侧钉定或更正（第 1、2、3、4、8 条）、三条标为"需人工一并确认"（第 5、6、7 条）、一条明确交 SDD 决定（第 9 条）。第 5/6/7 条由本 SDD 按 `dep-1` 的钉定实现，并在架构审批时随本 SDD 一并人工过目（本 SDD 未改写这三条的任何取值）。逐条承接如下（关闭项编号见 §6.5）：

| `dep-1` §1.5 | 本 SDD 的承接 |
|---|---|
| 第 1 条（Issue 标题 FR-0 不存在） | 只做 FR-8 / FR-1 / FR-2 三块；§9 `scope_out` 逐条排除 FR-3～FR-7、FR-9 |
| 第 2 条（FR 编号空洞刻意） | 全文不出现"缺 FR-N"式补全；TASK 编号与 FR 编号解耦（一个 TASK 可承载多 FR，见 §6.1） |
| 第 3 条（样本数不写成硬事实） | §3.6：样本数由脚本输出；代码/门禁中零硬编码样本常量；任何计数断言必须带口径与观测时刻（SDD-CLOSE-08） |
| 第 4 条（能力矩阵不由 PRD/SDD 复述为事实） | §2.4 `capabilities.json` 为声明载体；§6.3 的 `V-1`～`V-7` 列为待核实依赖；降级唯一合法动作与 AC-4 的联动见 §4.5 + SDD-CLOSE-05（同时关闭需求评审 S-3） |
| 第 5 条（逃生阀标记不合法 → 视为不存在） | §4.1 算法 A1：不合法标记 → `absent`，不拒绝调用、不新增 action 取值；若随后被裁剪仍输出 `action=truncate` trailer（SDD-CLOSE-04） |
| 第 6 条（`--detail` 与旧完整输出的等价定义） | §3.1 契约 + §4.6 合同测试：**字段集合等价**（逐字段路径）＋稳定值等价＋易变字段形态等价；禁止字节比对（SDD-CLOSE-02） |
| 第 7 条（棘轮登记同步义务） | §6.4：新增 `*.test.mjs` 即触发 `SUITE_MANIFEST_FILE_DRIFT`，因此 `manifest.files` + `manifest.cases` 必须同批更新；`exceptions` 保持空数组（SDD-CLOSE-03） |
| 第 8 条（Adapter 与既有 crctl 适配器的关系） | §3.4 + §6.5 SDD-CLOSE-01：两套职责分目录、各自模板、各自安装入口；`policy.json` 不进入 `skills/shared/crctl/adapters/`；唯一联合点是 Managed scope 下的 daemon 单写入点合成（**仅 claude**，§4.9） |
| 第 9 条（Plugin 打包形态交 SDD） | §5 决策 D-3：**不引入 plugin 打包形态**，沿用既有"模板 + 安装时物化绝对路径"先例；理由与替代方案见 D-3（SDD-CLOSE-06） |

---

## 2. 数据模型

### 2.1 零新增实体、字段与账本（NFR-1 落点）

本 CR **不新增任何数据库表、迁移、账本字段或状态**：三仓交付面全部是"新增目录/文件"与"既有文件增行"；KB 侧只写 `change-requests_{cr}/` 下的过程产物（与既有 CR 目录同构）。数据库/schema 变更与写路径鉴权完整性一节因此在 §2.6 显式记 `N/A`。

### 2.2 本 CR 新增的四个数据形状

四个形状全部是**纯 JSON 文件或纯函数返回值**，无运行时存储、无索引、无缓存持久化。

#### 2.2.1 `policy.json`（FR-1 阈值与规则唯一事实源）

```jsonc
{
  "policyVersion": "v1",                  // 只表示格式版本（见 §1.4.6）
  "families": [                            // 首期命令族（dep-1 FR-1 第 2 项钉定的三族五命令：grep|rg / find|Get-ChildItem / cat|Get-Content）
    { "id": "grep",   "kind": "search", "match": ["grep", "rg"] },
    { "id": "find",   "kind": "list",   "match": ["find", "Get-ChildItem"] },
    { "id": "read",   "kind": "read",   "match": ["cat", "Get-Content"] }
  ],
  "thresholds": {                          // ← 唯一数值面；全部由 TASK-01 基线产出，代码内零常量
    "resultTokensCap": 0, "lineWindow": 0, "maxHits": 0, "headLines": 0, "tailLines": 0
  },
  "truncation": { "search": {…}, "list": {…}, "read": {…}, "generic": {…} },
  "hints": { "narrow": "…", "nextOffset": "…", "omitted": "…" },   // 文案模板，唯一事实源
  "escapeHatch": { "marker": "# output-guard: full", "reasonMaxLength": 0, "singleLine": true }
}
```

规则：`thresholds` 的任一字段在 `core.mjs` 中**不得出现字面量**（AC-3 的判据：代码 diff 内无阈值常量、无第二份阈值副本）；`policy.json` 缺失或不可解析 → `POLICY_INVALID` 降级（§4.5）。

#### 2.2.2 `capabilities.json`（Runtime 能力唯一事实源）

```jsonc
{
  "schema": "output-guard/capabilities/v1",
  "enableOrder": ["pi", "claude", "codebuddy", "qoder", "codex"],   // 部署顺序，不新增 CR 状态
  "runtimes": {
    "pi": {
      "level": "full",                       // full | partial | unavailable（声明，由 conformance 验证）
      "preHook": "tool_call", "postHook": "tool_result",
      "preserve": { "toolName": "present", "toolCallId": "present", "isError": "present",
                    "exitCode": "absent-by-runtime" },   // 见 §4.2：absent-by-runtime 必须在 V-1/V-3 核实后落笔
      "startRecord": "extension-load",       // 会话启动记录的产生面
      "paths": [ { "id": "bash", "coverage": "full" }, { "id": "read", "coverage": "full" } ]
    },
    "claude":    { "level": "…", "paths": [ … ] },
    "codebuddy": { "level": "…", "paths": [ … ] },
    "qoder":     { "level": "…", "startRecord": "none", "paths": [ … ] },
    "codex":     { "level": "partial", "startRecord": "session-start",
                   "paths": [ { "id": "…", "coverage": "partial" },
                              { "id": "hosted-websearch", "coverage": "unavailable", "uncovered": true } ] }
  }
}
```

`preserve` 的取值闭包为 `{present, absent-by-runtime}`：`present` 表示该 Runtime 的结果结构确实承载该字段、Adapter 必须原样保留（丢失即不得裁剪，§4.2）；`absent-by-runtime` 表示该 Runtime **不存在**该字段（不是被丢弃），必须附证据链接（`V-1`/`V-3`），且该路径的 `coverage` 不得因此降级——否则 Pi/Claude 等路径会被形式上判死（需求评审 S-2 的延伸风险，本 SDD 显式裁决，见 §9 `follow_up`）。

#### 2.2.3 `conformance.json`（跨 Adapter 共享测试向量）

```jsonc
{
  "schema": "output-guard/conformance/v1",
  "vectors": [
    { "id": "esc-01", "kind": "escape-hatch", "input": { … }, "expect": { "action": "passthrough" } },
    { "id": "dec-01", "kind": "decision",     "input": { … }, "expect": { "action": "truncate", "complete": false } },
    { "id": "deg-01", "kind": "degradation",  "input": { … }, "expect": { "code": "OUTPUT_GUARD_UNAVAILABLE" } },
    { "id": "idem-01","kind": "idempotence",  "input": { … }, "expect": { "secondRunEqualsFirst": true } }
  ],
  "declaredVectorCount": 0        // 自棘轮：由 conformance.test.mjs 断言"实际执行向量数 == 声明值"
}
```

`declaredVectorCount` 是本 CR 内**唯一**用于新增测试面的计数棘轮（不新增账本、不写 `gate-registry.json` 之外的登记面）。四个 `kind` 与 AC-4 / AC-6 / AC-8 / AC-3 一一对应。

#### 2.2.4 trailer 与启动记录（唯一可观测面）

```text
裁剪：  [output-guard action=truncate complete=false original≈12k kept≈4k reason=output-cap]
不可保持：[output-guard action=unavailable complete=true coverage=unavailable path=<runtime>/<tool>]
启动：  output-guard runtime=pi coverage=full policy=v1
```

trailer 是**结果正文的追加行**（不新增文件、不新增 JSONL/sidecar/DB）；启动记录写到各 Runtime 既有的启动/stderr 面，由安装期检查或会话启动 hook 产生。字段闭包固定为 `action` / `complete` / `original≈` / `kept≈` / `reason=` / `coverage=` / `path=`，不新增字段名。

### 2.3 术语与既有结构的只读引用

- 状态机、门禁、审批、账本 schema 的术语与结构一律**只读沿用** `dep-3` / `dep-8` / `dep-1` 的既有表述，本 SDD 不复刻其内容（避免第二份事实源）。
- 本 CR 新引入的术语只有 §1.4.6 表中七个，全部给出唯一裁决。

### 2.4 声明 vs 核实：`capabilities.json` 的填写纪律

`capabilities.json` 的每个 `level` 都是**声明**，其真实性由 `conformance.json` 的 full 向量逐 Adapter 验证（AC-4）。因此：

1. **落笔前核实**（AGENTS.md 纪律 4）：TASK-04～TASK-07 在填 `level` 前必须先按 `V-4`～`V-7` 的核实命令读一次目标 Runtime 的真实 hook 文档；文档不支持结果回填的，直接填 `partial`/`unavailable`，不得先填 `full` 再"实现期再说"。
2. **降级即 AC-4 未达成**：任一 Runtime 由 full 降为 partial/unavailable，即视为 AC-4 未达成，必须回到人工确认（scope amendment）后重定 AC-4；**不得**把降级静默吸收为通过（关闭需求评审 S-3，SDD-CLOSE-05）。
3. 非 full 路径必须在 `paths[]` 里逐条列出 `uncovered: true`，且 FR-8 报告里该 Runtime 只报覆盖度与裁剪量、不参与 Pi 的成本外推（FR-8 第 4 项）。

### 2.5 状态与门禁（零变化）

`dep-8` 的 `tech-design-review-pending` 门禁判据（`fileExists change-requests/{cr}/sdd.md`）与 `approvalStages.tech-design` 的 passCondition 引用均不改动；本 CR 的 diff 不触及 `dep-9`（pipeline 节点数保持 5/4/12）与 `dep-8`。

### 2.6 数据库 schema / 写路径鉴权完整性：N/A

理由：本 CR 不新增/修改任何数据库表、迁移、DDL 或写路径鉴权（三仓交付面无 DB 面；`../multica` 的改动只写每任务 env 内的 Runtime 配置文件，不写数据库、不新增鉴权面）。因此 `write-tech-design` Step 2 的"数据/schema 变更与写路径鉴权完整性"条件未触发，本节记 `N/A`。

---

## 3. 接口契约

契约分四类：crctl CLI 面（3.1）、OutputGuard 模块与 hook 面（3.2～3.4）、只读与「不复刻」边界（3.5）、FR-8 脚本 CLI 面（3.6）。**HTTP / REST / IPC / 事件契约在本 CR 全部不适用**（3.7）。

### 3.1 `crctl <命令> [--detail]`（FR-2）

| 项 | 契约 |
|---|---|
| 形态 | `--detail` 是**布尔型**开关：出现即为真，**不消费后随 token**（`parseArgs` 对它走专用分支，避免 `crctl status --detail CR-2026-069` 被解析成 `flags.detail='CR-2026-069'` 并吃掉位置参数） |
| 默认面 | 命令在 `SUMMARY_PROJECTORS` 注册表内 → 成功出口输出 compact summary JSON；不在表内 → 与改造前逐字相同 |
| `--detail` 面 | 无论命令是否被投影，均输出改造前的完整字段集（等价性合同见 §4.6） |
| 未投影命令 + `--detail` | 语法接受、无投影函数 → 等价于现状（裁决见 §1.4.6；关闭需求评审 S-1） |
| 退出码 | 不变：成功 0；错误非 0（`fail()` 路径完全未改） |
| 错误面 | 不变：`dep-6` 的 247 个 `fail()` 出口零改动，不进投影 |
| 权限分支 | **无**：`--detail` 不参与任何状态判定、门禁、审批或 CAS 判定 |
| 幂等 | 同一命令在同一仓库状态下重复调用，`--detail` 输出恒等（纯呈现层，无时钟/随机源注入） |
| 平行开关 | 禁止新增：不新增 `--output json` / `--verbose` / `--pretty`（`dep-6` 对这四个 flag 全仓零命中） |

### 3.2 OutputGuard Core 模块接口（`output-guard/core.mjs`，ESM，零第三方依赖）

```ts
// 纯函数面（无 fs / 无时钟 / 无随机 / 无环境读取；Node 内建只在 Adapter 侧使用）
export function parsePolicy(text): Policy          // 解析失败抛 PolicyParseError，调用方转 POLICY_INVALID
export function normalizeText(s): string           // \r\n → \n（唯一规范化入口，I9）
export function parseCall(input: CallInput, policy): CallDecision
   // → { action:'block'|'rewrite'|'passthrough', ruleId, rewrittenInput?, hint?, reason? }
export function classifyFamily(cmdline, policy): FamilyDecision
   // → { family, determinate, limits }；不做 shell 解析：管道/重定向/脚本嵌套 → determinate=false
export function parseEscapeHatch(firstLine, policy): EscapeDecision
   // → { state:'valid', reason } | { state:'absent' }；不合法一律 absent（§4.1）
export function evaluateResult(input: ResultInput, policy): ResultDecision
   // → { action:'truncate'|'passthrough'|'unavailable', body, trailer, keptTokens, droppedTokens, ruleId }
export function fingerprint(input): string         // sha256 hex（§4.4）
export function renderTrailer(decision): string    // 字段闭包见 §2.2.4
```

**类型（结构化契约；实施时以 JSDoc 承载，不引入 TS 构建）**：

```ts
type CallInput   = { runtime, toolName, toolInput }
type ResultInput = { runtime, toolName, toolCallId, isError, exitCode?, body,
                     structure: 'text' | 'content-parts' }
type Policy      = { policyVersion, families[], thresholds{}, truncation{}, hints{}, escapeHatch{} }
```

三条实现约束（AC-3 的机械判据）：

1. `core.mjs` 内**不得出现任何阈值字面量**（数值只能来自入参 `policy`）；
2. 同一 `(policyVersion, ruleId, toolName, normalizedInput, normalizedBody)` 必须产生同一 `body` 与同一 `trailer`（合同测试逐字断言）；
3. Core 不读文件、不读环境变量、不调用子进程——policy 的读取是 Adapter 的职责。

### 3.3 Runtime hook 契约（五个 Adapter 的输入/输出映射）

统一形态：Adapter 从 stdin（Pi 为扩展事件回调）取 Runtime payload → 映射为 Core 输入 → 输出 Runtime 约定的 hook 结果；**Adapter 内不含阈值判断与裁剪算法**（I2）。五个 Adapter 都只通过**相对说明符** import 同一 Release 的 `core.mjs` 与读取同一 Release 的 `policy.json`（Pi 的 `.ts` 入口同理，不引入任何构建步骤或依赖）。

| Runtime | Pre 面 | Post 面 | 结果回填形态 | Adapter 文件 |
|---|---|---|---|---|
| Pi | `tool_call`（可阻断；`event.input` 可原地改写） | `tool_result`（可修改，返回 patch） | 返回 `{ content, details?, isError? }` 局部 patch（省略字段保持原值） | `output-guard/adapters/pi/index.ts` |
| Claude Code | `PreToolUse` | `PostToolUse` | `hookSpecificOutput.updatedToolOutput` | `adapters/claude/{pre,post}tooluse-guard.mjs` |
| CodeBuddy | `PreToolUse` | `PostToolUse` | `hookSpecificOutput.updatedToolOutput` | `adapters/codebuddy/…` |
| Qoder | `PreToolUse` | `PostToolUse` | 同 Claude（同一 hook 协议族，复用同一映射实现） | `adapters/qoder/…` |
| Codex | `PreToolUse`（managed） | `PostToolUse` block/feedback 路径 | 非透明替换；uncovered 路径逐条声明 | `adapters/codex/…` |

**Adapter 的 fail-open 契约（§4.5 的具体化）**：任一 Adapter 在「payload 不可解析 / policy 不可读或不可解析 / 结果结构不可安全保持 / 内部异常」四种情况下，**必须输出"无决策"**（不写任何替换字段、不禁用调用），并以非零退出码之外的方式在 stderr 打一行 `OUTPUT_GUARD_UNAVAILABLE runtime=<r> reason=<枚举>`；**不得**输出会误伤调用的 deny/block 决策。五种 Runtime 的 payload 字段名与输出协议以各自模板与 README 为落点，SDD 不复刻（I2）。

### 3.4 安装 / 挂载契约（目录归属与唯一写入点）

`dep-1` §1.5 第 8 条留给 SDD 的两项裁决（SDD-CLOSE-01）：

1. **目录归属**：OutputGuard 的 Adapter 一律落在 `output-guard/adapters/**`，**不进入** `skills/shared/crctl/adapters/**`；`policy.json` 不被复制到任何其它目录；两套适配器的配置文件不得合并成一份事实源。
2. **安装入口是否共用**：**不共用**。`dep-10`（Claude）/ `dep-11`（Qoder）/ `dep-12`（Codex）的既有模板治理"裸 git / 受控路径写入 / SessionStart 注入"，其安装动作是"把 hooks 段合并进目标 Runtime 的 settings"；OutputGuard 沿用**同一安装形态**（模板 + 安装时物化 `{TOOLS_ROOT}` 绝对路径），但模板文件各自独立，互不嵌套引用。
3. **唯一联合点（仅 claude）**：Managed scope（Multica 每任务 env）下，daemon 把两套 hooks 写进 claude 的**同一个**配置对象 `{workDir}/.claude/settings.json`（§4.9），写入点唯一，避免两个写者对同一文件互相 clobber。codebuddy / qoder 在 daemon 侧没有 hooks 写点（§4.9 第 4 步），两套 hooks 因此不共用安装入口，各自的安装动作由各自模板承担。

### 3.5 只读契约与「不复刻」边界

- 度量脚本对三仓与 session 目录**只读**；唯一写面是调用方显式指定的 `--out` 路径（`cr-cost.mjs` 的 `--out`，以及 TASK-01 把同一 JSON 复制进 KB CR evidence 目录的一次人工动作）。
- README / SKILL / 模板不得复刻 `policy.json` 的阈值、`capabilities.json` 的能力矩阵或 hook 细节，只能引用路径（AC-13）。**判据**：任一文档中出现 `thresholds` 的数值字面量或完整 `runtimes` 能力表 → fail。

### 3.6 FR-8 脚本 CLI 契约（`skills/shared/metrics/scripts/cr-cost.mjs`）

| 子命令 | 契约 |
|---|---|
| `baseline --out <path> [--sessions-root <dir>]... [--window <from>..<to>]` | 改造前唯一一次执行：产出唯一机器 JSON（字段集 ≡ `dep-1` FR-8 第 3 项 / `dep-2` §5.4）+ 对历史 session 离线回放 policy（纯函数重算）；stdout 打印同一对象渲染的人读摘要 |
| `after --out <path> --window 14d` | 部署后唯一一次执行：只统计 `coverage=full` 且带 CR-ID 的完整 Pi CR；样本不足 → `insufficient-sample`（不产出成本结论、不延长本 CR） |
| `replay --policy <path>` | 单独的历史回放（供抽检误伤使用），输出回放统计，不产出成本结论 |
| `verify-selection --baseline <path>` | AC-10 的机械核对入口：从 baseline 的 crctl 命令聚合重算最小集合，与 `SUMMARY_PROJECTORS` 注册表逐项比对，不一致即非零退出 |

**输出纪律（AC-17 / AC-18）**：① 机器结果只有一份 JSON，字段集固定，人读摘要由同一对象渲染（不写第二份产物文件）；② 每个计数字段必须携带 `observedAt`（ISO 时间）与 `rule`（可复现的筛选命令/口径），不合规即视为实现缺陷（同时关闭需求评审 S-4 的计数口径类风险）；③ 代码与门禁中不出现样本常量的硬编码（含 672 等值）；④ `k` 必须同时给出 `costSource`（取值闭包 `pi-session-usage` / `external-invoice` / `unavailable`）与 `tokenEstimator`（分母的估算口径标识）；`costSource=unavailable` 时 `k=null` 且输出中不出现任何金额宣称。

### 3.7 HTTP / REST / IPC / 事件契约：N/A

理由：本 CR 不新增或修改任何 HTTP endpoint、请求/响应结构、IPC 协议或事件总线契约（`dep-1` §1.3.3 的适用面判定）。OutputGuard 的 hook 面是 Runtime 进程内的本地调用（stdin/stdout 或扩展回调），不是网络契约；`crctl --detail` 是 CLI 呈现层，不是 endpoint。

### 3.8 错误语义：唯一新增降级码

```text
OUTPUT_GUARD_UNAVAILABLE runtime=<runtime> reason=<ADAPTER_MISSING|DISABLED|BUNDLE_INVALID|POLICY_INVALID>
```

- `reason` 为**四值闭包**，不新增第五值；
- 该码不进入 crctl 的错误码面（不影响 `dep-6` 的 `fail()` 出口语义）；
- 该码的唯一可见面是 Adapter stderr 一行 + 安装期检查输出；不写文件、不写账本、不写 JSONL/sidecar（错误路径零文件写入、零状态变更、无补偿事务）；
- `dep-7` 与 crctl 的 fail-closed 行为不受影响（§7.2）。

---

## 4. 关键算法与流程

九个算法块，逐块给出输入、步骤、终态与判据锚点。全部实现为纯函数或纯映射，不含时钟/随机/网络。

### 4.1 A1 — 逃生阀解析（FR-1 第 7 项②，SDD-CLOSE-04）

```text
输入：命令文本 commandText（含换行）
步骤：
  1. cmd ← normalizeText(commandText)                       // I9，先归一
  2. firstLine ← cmd.split('\n')[0]
  3. 若不是 shell 命令族（如 Pi 的 read 工具）→ absent       // 逃生阀只存在于 shell 首行
  4. m ← /^#\s*output-guard:\s*full\s+reason=(?<r>.*)$/.exec(firstLine)
     - 未命中 → absent
     - 命中但 r 为空 / 含换行 / r.length > policy.escapeHatch.reasonMaxLength
       → absent（**不合法一律视为不存在**，见下）
     - 否则 → valid(reason)
终态：{valid|absent}；无第三态、无错误码、不新增 action 取值
```

**不合法标记的处置**（`dep-1` §1.5 第 5 条）：视为不存在 → 该调用按普通路径参与判定；**不拒绝工具调用本身**；若随后被裁剪，仍按 §4.3 输出 `action=truncate` 的 trailer（模型因此可见"本次未获得完整结果"）。不新增第二套错误码、不引入授权文件（保持无状态）。

**逃生阀的边界**：`valid` 只让该次调用跳过 OutputGuard 的封顶（`action=passthrough`），**不参与** `dep-7` 的 git 白名单 / protected paths / 审批 / 账本写入控制的判定，也无法影响它们（四类各一条负向测试，AC-6）。

### 4.2 A2 — 决策顺序与终态裁决（FR-1 第 7 项）

固定顺序，每一步 **命中即终态**，无并列、无回溯：

```text
① Runtime 权限与既有安全控制   → 由 Runtime 自己裁决，OutputGuard 不评估、不放宽（在 Core 之外）
② parseEscapeHatch(firstLine)  → valid ⇒ action=passthrough（跳过封顶；仍受 ①）
③ classifyFamily(cmdline)      → determinate ∧ 命中规则 ⇒ action=block | action=rewrite(限流)
                                   !determinate ⇒ 放行，但对结果施加统一封顶
④ evaluateResult(body, policy) → 可保持 ∧ 超阈值 ⇒ action=truncate（complete=false + trailer）
                                  不可保持 ⇒ action=unavailable（不改结果 + coverage 标记）
⑤ 以上均未命中 ⇒ 不追加任何文本
```

**可保持性检查（步骤④的门）**——这是 I4 的机械落点，也是 AC-15 的唯一判据：

```text
输入：Runtime 的原始结果对象 R + capabilities[runtime].preserve
检查（全部通过才允许裁剪）：
  a. R 的 toolName / toolCallId / isError 三字段在 Runtime 结果结构中存在且可原样回填
  b. capabilities[runtime].preserve.exitCode
       == "present"           → R 中必须存在该字段且可原样回填
       == "absent-by-runtime" → 不做要求（该 Runtime 无此字段，缺失不是丢失）
  c. 结果结构可承载替换：R 的正文形态 ∈ {text, content-parts} 且替换后结构键集不变
不通过 ⇒ action=unavailable（结果逐字不改；标 pathCoverage=unavailable；trailer 一行）
```

**`exitCode` 的口径**（本 SDD 的显式裁决，`dep-1` FR-1 第 5 项的逐字对照见 §9 `follow_up`）：`dep-1` 要求"必须保留 … `exitCode` 与 Runtime 要求的结果结构"，其可执行含义是**"Runtime 结果结构中存在的字段不得丢失"**；对**结构上不存在**该字段的 Runtime（Pi 的 bash/read 工具结果只提供 `isError` 与状态文本，`V-1`/`V-3` 核实），`exitCode` 记 `absent-by-runtime`，**不因此降级该路径、也不触发 `unavailable`**。理由：若按"字段必须存在"的字面读法，Pi 与 Qoder 的首期主力路径会被形式上判死，与 FR-1 第 11 项"Pi 首个启用"直接冲突；两种读法不可同时成立，SDD 取值前者，并在 §9 `follow_up` 留下"若评审要求字面读法，需回到需求侧收窄该条"的显式出口。

**幂等与"跨调用零状态"**：决策不写入任何跨调用状态（无授权文件、无 nonce、无永久开关、无"下一次调用"记忆）；`action=passthrough` 不在会话中留下可被后续调用读取的痕迹。

### 4.3 A3 — 三类确定性裁剪（FR-1 第 4 项）

| 结果类型 | 算法 | 不变量 |
|---|---|---|
| 搜索（`grep`/`rg`） | 保留唯一文件列表 + 总命中数 + 可执行的缩小范围写法；同文件多命中折叠为一行的退出提示 | 命中数必须来自原始正文的机械统计，不得估算 |
| 列举（`find`/`Get-ChildItem`） | 保留唯一路径列表（去重、稳定排序）+ 总条目数 + 缩小范围写法 | 排序键固定（字典序），保证逐字可复现 |
| 读取（`cat`/`Get-Content` 与 Pi 的 read 工具） | 保留**连续行窗口** + 原始行号 + 下一次 `offset/limit` 的具体值 | 行号必须是原始文件行号（不得重编号）；窗口必须连续（不得拼接不相邻片段） |
| 普通 shell | 保留头部 N 行 + 尾部 M 行 + 中间省略量 | `N`/`M` 来自 `policy.json`，代码内零常量 |

所有文本处理先 `normalizeText`（I9：`\r\n → \n` 后再切行，`split('\n')`）；正文按 UTF-8 字节/字符边界切断时必须回退到整行边界（不得切断多字节字符）。裁剪结果**只保留正文**：被丢弃部分立即丢弃，不进 `details`、不写盘、不进任何日志（AC-7）。

### 4.4 A4 — 决策指纹与幂等证明（FR-1 第 6 项）

```text
fingerprint = sha256(
  policyVersion ‖ '\u0000' ‖ ruleId ‖ '\u0000' ‖ runtime ‖ '\u0000' ‖ toolName ‖ '\u0000'
  ‖ canonicalJson(normalizedInput)   // 键升序、EOL 归一、去除易变字段（时间戳/绝对路径前缀）
  ‖ '\u0000' ‖ normalizeText(body)
)
```

证明义务（合同测试）：同一 fingerprint 连续求值两次，`body` 与 `trailer` **逐字相等**（`conformance.json` 的 `idem-01` 向量）；跨 policyVersion 不做兼容承诺（`policyVersion` 只是格式版本）。

### 4.5 A5 — 降级与错误闭包（FR-1 第 8 项）

四种命中条件与唯一的降级码：

| 条件 | 触发面 | 结果 |
|---|---|---|
| Adapter 未被 Runtime 加载 / 无 Adapter | 安装期检查 + 运行期缺失 | fail-open，`reason=ADAPTER_MISSING` |
| Adapter 被显式禁用（安装配置移除即禁用；无远程开关） | 安装期检查 | fail-open，`reason=DISABLED` |
| bundle 损坏（文件缺失/哈希不符/接口版本不符） | Adapter 加载 | fail-open，`reason=BUNDLE_INVALID` |
| `policy.json` 不可读 / 不可解析 / `policyVersion` 不支持 | Adapter 加载 | fail-open，`reason=POLICY_INVALID` |

任一时：**原工具调用继续、结果不修改**；FR-8 侧该会话标 `coverage=unavailable` 并排除出完整覆盖样本；不静默假装生效；不让 Agent 退化为 Prompt 自觉；不影响 crctl / Git / 账本 / 审批的 fail-closed；错误路径零文件写入、零状态变更、无补偿事务。

### 4.6 A6 — FR-2 投影与等价性合同（SDD-CLOSE-02）

**投影入口（唯一改造点）**：

```text
main()：
  ACTIVE_PROJECTION ← resolveProjection(cmd, flags)     // 见 §1.4.3 三分支
  switch (cmd) → cmdXxx()
ok(obj)：
  const out = ACTIVE_PROJECTION ? ACTIVE_PROJECTION(obj) : obj
  process.stdout.write(JSON.stringify(out, null, 2) + '\n')
```

- **不在全局 `ok()` 删字段**：`ok()` 只是"若该命令注册了投影函数则调用它"，未注册命令逐字走原路径（`dep-1` FR-2 第 1 项末句）。
- **投影函数是每命令独立的纯函数**：输入成功出口的对象，输出 compact summary 对象；不得读取全局状态、不得访问文件系统。
- **输出格式化不新增模式**：summary 仍为 2 空格缩进 JSON——FR-2 的杠杆是**字段投影**而非空白压缩；不引入 `--pretty`/minified 第二形态（决策 D-2）。

**等价性合同（`dep-1` §1.5 第 6 条的落地）**：合同测试按三层比对，禁止字节比对：

| 层 | 判据 | 失败即 |
|---|---|---|
| ① 字段集合 | `fieldPaths(--detail 输出)` ≡ 改造前金样本的 `fieldPaths` | blocker 级实现缺陷 |
| ② 稳定值 | 金样本中标记为 `stable` 的字段路径，其值逐字相等 | 同上 |
| ③ 易变字段形态 | 金样本中标记为 `volatile`（时间戳 / 提交 SHA / 绝对路径）的字段路径，其值类型与形态（ISO 8601 / 40 hex / 绝对路径）匹配 | 同上 |

金样本（`skills/shared/crctl/scripts/test/golden/crctl-detail/*.json`）**必须在实现投影前**由未改造的 CLI 在既有 fixture 工作区上采集（TASK-08 第 1 步），随 CR 提交；采集脚本与 fixture 复用既有测试夹具（消费式引用 `dep-13`/`dep-14` 已在仓的夹具构造方式，不改其语义）。

**命令集合的选择（AC-10）**：见 A8。**调用方同步（AC-21①）**：见 A10。

### 4.7 A7 — FR-8 聚合与 `k`（FR-8 第 2～5 项）

```text
样本筛选（可复现，随输出）：
  roots  = [<multica pi-sessions 根>, <pi agent sessions 根>]（可 --sessions-root 覆盖）
  type   = *.jsonl；window = [from, to)
  crId   = 会话内出现 CR-<YYYY>-<NNN> 形式的标识（正则固定，随输出）
每会话聚合（只读）：
  toolResults = 每条 role=toolResult 的正文 token 估计（tokenEstimator 标识 + 原始字节/字符数）
  usage       = assistant 消息 usage 的 input / cachedInput(=cacheRead) / cacheWrite / output 四维
  buckets     = 按工具族归类（搜索 / 列举 / 打印 / crctl 命令输出 / 其它）
派生指标：tokensPerCR / sessionsPerCR / searchTokenRatio / fullReadRatio / bootstrapTokensPerSession
护栏指标：firstPassGateRate / reviewLoopsPerCR / reviewDefectsPerCR
k：分子 = costSource 对应的计费金额；分母 = 同区间工具结果 token（同 estimator）；不可得 ⇒ k=null
```

**关键口径与诚实性规则**：

1. `tokenEstimator` 必须显式写出（零第三方依赖的约束下不引入 BPE tokenizer；比值型结论不依赖 estimator 的绝对精度，但**金额型结论必须同时标注 estimator 与 costSource**）。
2. `cachedInput` 映射为既有 usage 的 `cacheRead`（`dep-1` FR-8 第 2 项用 `cachedInput|cacheRead` 双名，SDD 取 `dep-1` 的写法并在输出里保留原始键名）。
3. 护栏三项来自既有 Pipeline 与评审数据（门禁一次通过、`review-loop` 轮次、评审发现缺陷数），全部只读复用，不新增采集面。
4. `insufficient-sample` 是**终态之一**：样本不足即输出该状态并停止，不输出部分成本结论、不延长本 CR。

### 4.8 A8 — summary 命令集的选择算法（AC-10 的可机械核对面）

```text
输入：baseline JSON 的 crctlCommands[] = [{ command, tokens, calls }]
1. 按 tokens 降序；tokens 相等按 command 字典序（确定性 tie-break）
2. 贪心取前缀，直到累计份额 ≥ 80%
3. 输出 = 该前缀的命令集合（份额全为正 ⇒ 该前缀即"达到阈值的**最小基数**集合"；交换论证：任何更小的集合必然漏掉某个更大份额项，累计份额更低）
```

三条硬约束：

1. `SUMMARY_PROJECTORS` 的键集合必须**等于**该算法输出（`verify-selection` 子命令逐项比对，不一致即非零退出）；
2. 该命令集合与算法均**不写入 PRD/Prompt/Skill/门禁**，只活在 `summary-projectors.mjs` 与 baseline evidence 中；
3. 基线之前不得预设集合（TASK-08 的输入是 TASK-01 的输出，顺序不可颠倒）。

### 4.9 A9 — Managed 挂载的合成算法（TASK-09，`../multica`）

```text
输入：envRoot、workDir、provider、既有 dep-4 的 per-task 环境锻造流程
1. 读本地安装配置（一个显式环境变量指向 Tools Release 根；未配置 ⇒ 本次挂载整体跳过，既有行为逐字不变）
2. 解析 output-guard/adapters/<provider>/ 下的 hook 入口绝对路径与 policy 读取面
   （**只写路径引用，不复制 policy、不复制 Adapter 正文**）
3. provider 分支表（写入者唯一 = daemon；"目标文件"一律是可解析出的绝对路径）：
   provider    目标文件                        写入形态
   claude      {workDir}/.claude/settings.json  与该 provider 既有的 crctl 守卫 hooks **在同一个配置对象内合成**：
                                               同一 JSON 只写一次；hooks 数组按"既有段在前、OutputGuard 段在后"追加
   codebuddy   不写（见第 4 步）               —
   qoder       不写（见第 4 步）               —
   pi          不写（见第 4 步）               —
   codex       不写（见第 4 步）               —
4. "不写"是显式设计而不是"暂无实现"：daemon 的 Runtime hooks 写点**只有 claude 一个**（`dep-4`；`dep-15` 的每任务写入面对
   codebuddy / qoder 只有记忆文件与 skills 发现目录），给其余 Runtime 新开写点等于在平台层再造一个 Runtime hooks 配置面，
   超出 FR-1 的"挂载"范围（见 D-7 的"范围澄清"）。因此这四个 Runtime 的挂载面是**显式安装一次**：
   - codebuddy：项目级 `<project-root>/.codebuddy/settings.json`（可提交、团队共享）或用户级 `~/.codebuddy/settings.json`（`V-5`）
   - qoder：项目级 `<project-root>/.lingma/settings.json` 或用户级 `~/.lingma/settings.json`（`dep-11`）
   - pi：宿主级 `~/.pi/agent/settings.json#extensions`（或 `~/.pi/agent/extensions/`）——argv 面被 `dep-16` 封闭，不猜路径、不做 argv 注入
   - codex：宿主级 `.codex/hooks.json` + `/hooks` 信任步骤（`dep-12`），按 partial 处理、uncovered 路径逐条声明
   安装模板由 §3.4 的各自模板承担；生效性由 `check-install.mjs` 读数 + AC-14 的真实任务冒烟判定，不由部署过程自证。
5. claude 分支的不 clobber 判据：目标 `.claude/settings.json` **已存在**（用户自带配置 / local_directory 流）⇒ 不写、不合并、
   不覆盖，沿用 `dep-4` 的"存在即跳过并告警"；该次挂载记为未完成，由安装期检查显式报告（AC-19③，不静默假装生效）。
```

**边界（`dep-1` §1.3.2 的 multica 行 + AC-12）**：只做挂载与写出配置；不碰 `dep-15` 的责任边界以外的语义、不放开 `dep-16` 的 argv 白名单面、不改 `dep-17`（preview/transcript 层）、不新增远程开关、不新增安装框架、不在 CR 过程中安装任何东西（安装是部署动作）。claude 的挂载走 daemon 单写入点；Pi / CodeBuddy / Qoder / Codex 不走 daemon 写点（第 4 步），改由各自原生配置面显式安装一次（§1.4.2 的 Managed 行）。

### 4.10 A10 — 调用方同步扫描（AC-21① 的可机械核对面）

```text
扫描面：skills/**/SKILL.md、pipeline-templates/*.pipeline.json、agents/*.md、skills/**/*.mjs、README.md
提取：`crctl <子命令> [<子子命令>] [args]` 字面量（含 `node …/crctl.mjs …` 形态）
判定（逐条，写入测试内的显式表）：
  a. 子命令 ∉ 投影集合            → 无需动作（输出未变）
  b. 子命令 ∈ 投影集合 ∧ 该处消费的字段 ⊆ summary 字段集 → 无需动作
  c. 子命令 ∈ 投影集合 ∧ 该处需要 summary 之外的字段        → **必须显式补 `--detail`**
检查：caller-contract.test.mjs 断言扫描面内每一处 (b) 类调用与显式表一致、(c) 类调用都带 `--detail`；
     新增/改动调用点若与表不符即红（表是人工审过的白名单，断言是机械的）
扫描面之外的真实调用方（例：KB 仓 `.github/workflows/cr-guard.yml` 这类仓外 CI 调用；外部脚本、其它仓的 workflow 同理）
不因"在扫描面外"而豁免：逐条做同一字段消费检查，并把结论登记进同一张表（按仓标注）。判定为"只消费退出码、
不解析输出字段"的记 `无需动作`；判定为需要完整字段的按 (c) 类补 `--detail`。这样 AC-21① 的"全部真实既有调用方"
覆盖范围可核——口径按字段消费，不按调用次数或所在仓。
```

`summary` 的字段集**按"调用方充分性"设计**：先在 A10 的表里枚举每个被投影命令的既有消费字段，再据此定义 summary 必须保留的字段；只有确实无法进入 summary 的字段才用 `--detail` 兜住。这样 `--detail` 是"显式例外"，而不是"大面积补丁"。

---

## 5. 技术选型与替代方案

只记录同时满足三判据（难以逆转 + 无上下文会疑惑 + 有真实权衡替代）的决策；不伪造替代方案，不新增 ADR 文件或审批节点。

### D-1 seam 位置：Runtime 工具结果回填 hook（选定） vs daemon preview 层

- **Context**：`dep-1` §1.1 的第 1 条根因结论（治理点位置错）与 S11 的 seam 定义。
- **选定**：Adapter 挂在 Runtime 的 Pre/Post hook 上，在结果进入下一轮模型上下文之前裁剪。
- **替代**：在 `dep-17`（daemon 的 preview/transcript 层）做截断。
- **否决理由**：该层在模型上下文之后，降不了 token；且该文件被 `dep-1` 钉为**零 diff**（AC-12）。
- **不可逆性**：Adapter 的位置决定 policy 的读取面与安装模型，改位置等于重做发布/安装契约。

### D-2 summary 的输出形态：保持 2 空格缩进 JSON（选定） vs 单行/minified

- **Context**：FR-2 的默认面从"全量缩进 JSON"变成"compact summary JSON"；`dep-6` 的成功输出面只有一个 `ok()`。
- **选定**：summary 仍是 2 空格缩进的合法 JSON，只是字段被投影。
- **替代**：单行 minified JSON（更省 token）。
- **理由**：FR-2 的杠杆是字段投影而非空白；Skill/Agent 阅读 compact summary 的可读性直接决定后续动作质量；新增第二种格式化形态会与"不新增 `--pretty`/平行开关"的边界冲突，并让日志与 diff 排查退化。
- **不可逆性**：默认面是调用方契约，改形态等于二次破坏性变更。

### D-3 分发形态：模板 + 安装时物化绝对路径（选定） vs plugin 打包（SDD-CLOSE-06）

- **Context**：`dep-1` §1.5 第 9 条（tools 仓当前无 plugin 载体，是否引入交 SDD）。
- **选定**：沿用 `dep-10`～`dep-12` 的既有形态——提供各 Runtime 的配置模板 + 安装说明 + 启动检查，`{TOOLS_ROOT}` 在安装时物化为绝对路径。
- **替代**：引入 `.claude-plugin/plugin.json` 等 plugin 清单元数据 + 安装/升级框架。
- **否决理由**：仓内无既有载体；引入即需要新的安装入口、版本同步与信任语义，触碰"不新建安装框架 / 不建远程开关"的硬边界；且 `dep-1` 只钉"显式安装一次、三级 scope、启动只检查不修复、不得复制 policy"四项合同。
- **残留**：`dep-2` §6.10 的"Tools Plugin 携带 Skills 与 hooks"一句话在本 CR 不落地；本 SDD 不改写该句，只在 §9 `follow_up` 记录差异。

### D-4 逃生阀的识别面：shell 命令族首行注释（选定） vs 任意文本扫描

- **Context**：`dep-1` FR-1 第 2/7 项（不实现完整 parser）与 `dep-2` §6.6 的统一首行注释形态。
- **选定**：只在"命令族被识别为 shell 调用"时解析首行，且只解析首行。
- **替代**：在整段命令文本里搜索标记（含管道/重定向/脚本内部）。
- **否决理由**：会触发"必须解析任意嵌套"的不可判定面，与"不实现完整 Bash/PowerShell parser"直接冲突；且会把"注释"与"可执行语句"混淆。

### D-5 `unavailable` 也输出一行 trailer（选定） vs 完全静默

- **Context**：`dep-2` §6.7 字面只规定"发生拒绝或裁剪时"追加 trailer；而 FR-1 第 5/7 项的路径级 `unavailable` 与 NFR-6 的"降级显式"都要求该事实可见。
- **选定**：`action=unavailable` 追加一行 `[output-guard action=unavailable complete=true coverage=unavailable path=…]`。
- **替代**：不追加任何文本，只靠安装期检查记录。
- **理由**：`action=unavailable` 不是"未命中任何规则"（`dep-2` §6.7 的"正常未触发调用不增加文本"针对后者）；若完全静默，则"护栏在跑但拒绝裁剪"与"护栏根本没跑"在会话里不可区分，NFR-6 的"不静默假装生效"不能成立，FR-8 也无法把该会话排除出完整覆盖样本。
- **边界**：这是对 §6.7 的一次**紧读边界裁决**，随本 SDD 一并进入人工审批过目（§9 `follow_up` 保留了改为静默的退路）。

### D-6 `exitCode` 的语义：Runtime 结构存在才要求保留（选定） vs 字面要求必存在

见 §4.2 末段。选定前者；替代（字面读法）会让 Pi 判死，与 FR-1 第 11 项"Pi 首个启用"冲突。此裁决同样进入人工审批过目。

### D-7 Managed scope 的挂载方式：daemon 单写入点合成（选定） vs 纯手工安装

- **Context**：Multica 平台在每任务 env 内**已经**为 claude 写项目级 Runtime 配置（`dep-4`）；纯手工安装会与该写入点竞争同一文件。
- **选定**：在该写入点内合成（单写者、单次写），并把 OutputGuard 段落置于既有 hooks 之后。
- **替代**：要求运维在用户级/项目级各装一次，daemon 不参与。
- **否决理由**（只针对 claude）：claude 的项目级写入点（`dep-4`）会与用户自带配置竞争同一文件，而 AC-14 要求在真实 Multica 任务里冒烟 —— 纯手工安装下"是否真的生效"不可判定（等于把降级风险藏进部署过程）。
- **代价**：`../multica` 产生一处小改动（`dep-4` 文件 + 新文件），需按其 `dep-18` 登记定制。
- **范围澄清（回修 r1，适用范围只在 claude）**：本条只适用于 daemon **已有** hooks 写入点的 Runtime —— 当前只有 claude（`dep-4`；`dep-15` 的每任务写入面只覆盖记忆文件与 skills 发现目录）。codebuddy / qoder 在 daemon 侧没有 hooks 写点，本 CR **不**为它们在平台层新开写点：那会把"一次挂载"变成"为某个 Runtime 新造一个配置面"的架构动作，并会与用户自己的项目级配置竞争同一对象。二者的 Managed 挂载面因此是各自原生配置面 + 显式安装一次（§4.9 第 4 步），其"是否真的生效"由 `check-install.mjs` 读数 + AC-14 真实任务冒烟共同判定，不由部署过程自证。

### D-8 FR-8 的 token 估计：带标识的自研 estimator（选定） vs 引入 BPE tokenizer

- **Context**：`dep-2` §4 的口径用 o200k 编码；而 tools 包无依赖机制（`dep-3` §5 不变量 3 的零依赖口径）。
- **选定**：不引入第三方 tokenizer；输出显式 `tokenEstimator` 标识 + 原始字节/字符数（保证任何口径都能重算）；比值型结论（≥20% 下降）不依赖绝对精度；金额型结论必须同时标注 estimator 与 costSource。
- **替代**：引入 `o200k` BPE 依赖或自带词表 → 否决：破坏零依赖口径、引入随版本漂移的第三方资产。

### D-9 FR-2 投影入口：`main()` 内设定模块级 `ACTIVE_PROJECTION`（选定） vs 改 45 个 `ok()` 调用点

- **Context**：`dep-6` 的成功出口是单一 `ok(obj)`，共 45 个调用点，其中含 async 链（approve 系列）。
- **选定**：在 `main()` 里按 `(cmd, flags)` 一次性解析出投影函数挂到模块级变量，`ok()` 消费它；未注册即 null。
- **替代**：`ok(obj, cmd)` 显式传参（45 处改动）。
- **理由**：投影与命令名的绑定只有一个权威点（dispatch 入口），传参会把同一映射散布到 45 处、易漏且易漂移；`ACTIVE_PROJECTION` 的作用域严格限于一次进程内的单次命令执行（CLI 一次性进程），无并发写者。
- **代价**：模块级可变状态需要一条测试断言"未注册命令 + 未传 `--detail` 时输出与改造前逐字相同"（见 §6.4 的回归面）。

---

## 6. FR 到技术实现映射

### 6.1 FR 逐条映射

| FR | 技术方案落点 | 承载 TASK | 判据锚点 |
|---|---|---|---|
| FR-8 第 1 项（位置与执行次数） | `skills/shared/metrics/scripts/cr-cost.mjs` 的 `baseline` / `after` 两个子命令；不进 Pipeline/Skill/定时任务；机器 JSON 落 `--out` 与 KB `change-requests/CR-2026-069/evidence/` | TASK-01 / TASK-10 | §3.6、AC-17①④ |
| FR-8 第 2 项（输入只读复用） | `lib/sessions.mjs` 只读遍历（`V-2` 的 JSONL 形状）+ 既有 review/门禁数据只读读取 | TASK-01 | §4.7、AC-17② |
| FR-8 第 3 项（输出字段集） | `lib/aggregate.mjs` 产出固定字段集；`lib/render.mjs` 从同一对象渲染人读摘要（stdout，不写第二份文件） | TASK-01 | §2.2.1～§3.6、AC-17② |
| FR-8 第 4 项（`k` 与金额口径） | `lib/aggregate.mjs` 的 `k` 计算 + `costSource` / `tokenEstimator` 标注；非 Pi Runtime 只报覆盖度与裁剪量 | TASK-01 | §4.7、AC-18 |
| FR-8 第 5 项（窗口与扩项门槛） | `after --window 14d`；`insufficient-sample` 作为可测终态；三项护栏与 ≥20% 判定为脚本内纯函数 | TASK-10 | §4.7、AC-17⑤ |
| FR-8 第 6 项（可复现） | 筛选规则随输出（`rule` + `observedAt`）；比较只用归一化指标 | TASK-01 / TASK-10 | §3.6、AC-17②③ |
| FR-1 第 1 项（职责切分） | `core.mjs` 纯函数 + `policy.json` / `capabilities.json` / `conformance.json` 三份唯一源 + 五个 Adapter 只做映射 | TASK-02～TASK-07 | §3.2～§3.4、AC-3 |
| FR-1 第 2 项（首期命令族） | `policy.json#families` 三族五命令；`classifyFamily` 的不确定分支=放行但统一封顶 | TASK-02 | §4.2、§4.3、AC-5 |
| FR-1 第 3 项（阈值来源） | 阈值只在 `policy.json#thresholds`；由 TASK-01 产出后写入；代码/Prompt/Skill 零阈值 | TASK-01 → TASK-02 | §2.2.1、AC-3 |
| FR-1 第 4 项（裁剪策略） | `evaluateResult` 四类分支（搜索/列举/读取/普通 shell） | TASK-02 | §4.3、AC-5 |
| FR-1 第 5 项（门禁证据不变量） | 可保持性检查 + `complete=false` + trailer + 丢弃正文立即释放 | TASK-02 + 各 Adapter | §4.2、§4.3、AC-7 / AC-15 |
| FR-1 第 6 项（幂等） | `fingerprint` + 跨调用零状态 | TASK-02 | §4.4、AC-3 / AC-6 |
| FR-1 第 7 项（权限与顺序） | 五步固定顺序、五值终态闭包、逃生阀不影响安全层 | TASK-02 + 各 Adapter | §4.1、§4.2、AC-6 |
| FR-1 第 8 项（错误闭包） | `OUTPUT_GUARD_UNAVAILABLE` 四值 reason + fail-open 四场景 | TASK-02 + 各 Adapter | §3.8、§4.5、AC-8 |
| FR-1 第 9 项（副作用面） | 唯一可见副作用=正文 + 一行 trailer + 启动一行；无 JSONL/sidecar/DB | 全体 | §2.2.4、AC-7 |
| FR-1 第 10 项（发布与安装） | 同一 Release 相对路径读取；`check-install.mjs` 只报告不修复；三级 scope | TASK-02～TASK-09 | §1.4.2、§3.4、AC-19 |
| FR-1 第 11 项（启用顺序） | `capabilities.json#enableOrder` + 三前置证据链；不新增状态/节点 | TASK-03～TASK-09 | §1.4.5、AC-20 |
| FR-1 第 12 项（回滚粒度） | 单 Adapter=安装配置移除即禁用；Core/Policy=整体回退 Release；无远程开关 | TASK-03～TASK-09 | §7.3、AC-14 |
| FR-2 第 1 项（选择规则与 projector） | `summary-projectors.mjs` 独立投影器 + A8 选择算法；不在全局 `ok()` 删字段 | TASK-08 | §4.6、§4.8、AC-10 |
| FR-2 第 2 项（开关面收敛） | 只新增 `--detail`；不新增平行开关；调用方按 A10 补 `--detail` | TASK-08 | §3.1、§4.10、AC-21 |
| FR-2 第 3 项（幂等与无权限分支） | `--detail` 纯呈现层，无状态/门禁/审批/CAS 参与 | TASK-08 | §3.1、AC-11 |
| FR-2 第 4 项（错误闭包） | `fail()` 与错误体零改动 | TASK-08 | §3.1、§3.8、AC-11 |
| FR-2 第 5 项（不变量） | §4.6 三层等价性合同 + 既有测试全绿 + 新增合同测试 | TASK-08 | §4.6、AC-10 / AC-11 |
| FR-2 第 6 项（棘轮同步义务） | `manifest.files` + `manifest.cases` 同批更新；`exceptions` 保持空 | TASK-08 | §6.4、AC-21②③ |
| FR-2 第 7 项（不做） | 不优化运行时小文件读取、不建字段/错误码事实页（FR-9 候选） | — | §9 `scope_out` |

### 6.2 AC 逐项设计与验收映射

| AC | 设计落点 | 可观测结果 | 可达性说明 |
|---|---|---|---|
| AC-1 | §9 `zero_diff` 清单 + §6.4 零改动核对清单 | `crctl git diff --name-only <baseRef>..HEAD` 对清单内路径逐条为空；状态机/门禁/审批/账本/事务行为类文件零变化 | 本 CR 的改动面（`output-guard/**`、`skills/shared/metrics/**`、`crctl.mjs` 投影层、Prompt 采纳面（§9 `scope_in` 第 3、4 项）、CI/README/ARCHITECTURE、multica `execenv` 两文件 + `CUSTOM.md`）与清单无交集（`dep-6` 的 `crctl.mjs` 与 `dep-9` 的 pipeline JSON 按**落点** carve-out 切分：投影落点/命中的 prompt 文本在 `scope_in`、其余在 `zero_diff`），断言可机械执行 |
| AC-2 | §4.9/§6.4 + 新增代码的依赖纪律 | `dep-5` 的 lib 四文件零 diff；全 diff 无锁/journal/write-set/CAS/提交框架；无手写账本；passCondition/状态映射/reviewLoop 算法零复制 | 新增代码不写任何账本、不引入文件锁（度量脚本只写 `--out`，Adapter 只读 policy）；复制类漂移由既有 prompt 合同扫描 + 人工复核兜住 |
| AC-3 | §3.2 三条实现约束 + `policy.json` | 幂等向量逐字相等；`core.mjs` 内阈值字面量零命中；阈值第二副本零命中 | policy 由 Adapter 读入并以参数进 Core；thresholds 唯一出现在 `policy.json` |
| AC-4 | `capabilities.json` + `conformance.json` + 每 Adapter 的向量执行 | 测试输出能区分 full / partial / unavailable；Pi/Claude/CodeBuddy/Qoder 的 full 向量逐 Adapter 出结果；Codex 的 uncovered 路径逐条列示 | 若实测某 Runtime 不具备 full，按 §2.4 降级并触发 scope amendment（不静默吸收） |
| AC-5 | §4.3 + `policy.json#hints` | 每个命令族的替换结果含可执行替代写法：搜索/列举→唯一文件列表+命中数+缩小范围写法；读取→下一次 `offset/limit` 具体值 | 替代写法由 Core 从原始正文机械生成（不依赖模型、不依赖网络） |
| AC-6 | §4.1 + §3.3 | 逃生阀 valid/absent 两态向量；连续两次调用无跨调用状态；四条负向测试证明逃生阀不影响 git 白名单/受控路径/审批/账本写入 | OutputGuard 运行在 Runtime 权限与既有安全控制之后（① → ②），负向测试在 hook 层并列验证 |
| AC-7 | §4.3 末段 + `evaluateResult` 的正文替换 | sentinel 端到端用例：sentinel 不在模型可见 `tool_result`、不在 session 文件、不在 transcript、不在新增日志；无 sidecar/JSONL/DB 新增 | 裁剪只替换正文；`details` 不被写入丢弃正文；测试夹具把 payload 控制在 Runtime 自身截断阈值之下以隔离 `V-3` |
| AC-8 | §4.5 四场景 | 四场景各出 `OUTPUT_GUARD_UNAVAILABLE` 且 reason ∈ 四值；原调用继续、结果不改；无静默安装/修复（负向断言：不写任何文件） | 四场景可用可注入路径/损坏 bundle 在测试中复现（`BUNDLE_INVALID`/`POLICY_INVALID` 为纯函数可造） |
| AC-9 | §4.7 `replay` | `baseline.json` 含可复现筛选规则与实际样本数；离线回放完成；合法调用抽检清单与判定入证据 `change-requests/CR-2026-069/evidence/ac9-sampling.md`（§9 `scope_in` 第 7 项） | 回放是纯函数重算，不执行命令、不依赖网络 |
| AC-10 | §4.6 + §4.8 | 默认输出=compact summary；`verify-selection` 断言注册表 ≡ 基线最小集合；`--detail` 与金样本三层等价 | TASK-01 先于 TASK-08；baseline evidence 随 CR 提交，核对命令可复跑 |
| AC-11 | §3.1 + §6.4 | 逐命令退出码不变；错误码与错误体不变（`fail()` 出口零 diff）；既有测试全绿（CI 双平台）；状态/门禁/审批/CAS/事务/Git 代码零改动 | `fail()` 与各 `cmdXxx` 的非成功分支完全未改；投影只在 `ok()` 内生效 |
| AC-12 | §9 `zero_diff` | `crctl git diff --name-only` 对 `dep-17` 路径为空 | multica 改动只落在 `dep-4`/新增 `outputguard_config.go`/`dep-18` |
| AC-13 | §3.5 判据 | README 仅增导航与权威入口链接；`thresholds` 数值与完整能力矩阵在 README/Skill 中零命中 | 检查脚本以"数值字面量 + 能力表关键词"为模式，纳入 CI |
| AC-14 | §1.4.2 + TASK-03～TASK-07 / TASK-09 | 每个已启用 Runtime 至少一次真实冒烟，覆盖拒绝/裁剪/逃生/损坏降级四类行为；记录（含每个 Runtime 一行 `check-install.mjs` 输出）落 `change-requests/CR-2026-069/evidence/ac14-smoke.md` 作为交付证据 | 冒烟在 Multica 启动的真实任务环境执行；挂载面逐 provider 可区分（claude：daemon 自动写入；codebuddy/qoder：项目级/用户级配置文件已安装且**不被 daemon 触碰**；pi/codex：宿主级配置），因此"手工安装是否真的生效"由 `check-install.mjs` 读数 + 四类行为观测共同判定，不由部署过程自证；失败按 §2.4 记降级并触发 scope amendment |
| AC-15 | §4.2 可保持性检查 | sentinel 不在模型可见结果；`toolName`/`toolCallId`/`isError` 保留、`exitCode` 按其 Runtime 事实保留（`present` 必须保留 / `absent-by-runtime` 不作要求）；结果结构键集不变；任一 `present` 字段丢失即该路径不得裁剪并标 `unavailable` | 检查是 Core 的前置门，不通过的路径直接进入 `unavailable` 分支（不可能"裁了才发现"）；`exitCode` 口径（D-6）与 D-5 随本 SDD 进入人工审批显式确认（§9 `follow_up` F-3），plan/TASK 的 AC-15 取证判据按该口径（`present` 必保留 / `absent-by-runtime` 不作要求）取值，不按 `prd.md` 字面重开口径 |
| AC-16 | §2.2.4 trailer 指令 + §8 的 reviewer Skill 采纳 | 至少一条端到端用例：以 `complete=false` 结果提交门禁/审批判断时被要求继续切片取证或走逃生阀；trailer 指令文本为固定契约 | 无新门禁/新状态可用，拦截由"trailer 固定指令 + reviewer Skill 合同条款 + 端到端用例"三者共同承载；残余风险见 §7.4 |
| AC-17 | §3.6 + §4.7 | ① 执行次数恰为两次（evidence 目录两个 JSON）；② 字段集 ≡ `dep-1` FR-8 第 3 项（来源 §5.4）；③ 样本数由脚本输出、代码与门禁零硬编码常量；④ 报告以 KB evidence + Issue 附件存在、四账本零变化；⑤ 14 天窗口与 `insufficient-sample` 为可测函数 | 脚本 CLI 显式提供 `baseline`/`after --window 14d`/`--out`；evidence 目录随 CR 提交 |
| AC-18 | §4.7 `k` 段落 | 输出含 `costSource` + `tokenEstimator` + 分母 + 原始 usage 四维；`costSource=unavailable` ⇒ `k=null` 且无金额宣称；非 Pi 只报覆盖度与裁剪量 | 四维键名来自 `V-2` 的实读结构；Pi-only 由 `capabilities.level`/`coverage` 派生控制 |
| AC-19 | §1.4.2 + §3.4 + `check-install.mjs` | Adapter 以自身位置推导同一 Release 的相对 policy 路径（无复制目录）；无单独升级命令；启动检查只打印缺失/损坏与修复命令且不写任何文件；三级 scope 可区分 | 检查脚本只读 + 打印；scope 由参数与配置面路径显式区分 |
| AC-20 | §1.4.5 + `capabilities.enableOrder` | 启用顺序记录可核对：每个 Runtime 以"conformance 通过 + 真实冒烟通过 + 降级验证通过"为前置；CR 状态与 Pipeline 节点零新增；无长期 shadow mode | 顺序是部署顺序，落在 `capabilities.json` 与交付证据里，不进入状态机 |
| AC-21 | §4.10 + §6.4 | 扫描面内每处投影命令调用与显式表一致、需完整字段者带 `--detail`；`manifest.files`/`cases` 与实际一致；`exceptions` 保持空数组；`suite-gate --run` 同步前后均绿 | 新测试文件落在 `dep-13` 的磁盘集合内，未登记即 `SUITE_MANIFEST_FILE_DRIFT`（机械暴露，不靠自觉） |

### 6.3 既有实现依赖与事实

下表按**正文首次出现顺序**编号（`dep-1` 起，只增不改；新增条目只追加编号，删除条目留空洞不复用）。每项以稳定标识开头，固定五要素。正文只用 `dep-N` 引用承载实现事实，不重复陈述"当前代码已经如何工作"。

```text
dep-1
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-069/prd.md
  stable symbol/对象: PRD 全文（§1.3.1 范围原文前缀、§1.4 十六项落笔前核实事实、§1.5 九条口径、§3 三条 FR、§4 九条 NFR、§5 二十一条 AC）
  commit SHA: 926ef5399f9b3a29177484995fabd516417633fa
  依赖结论: 本 CR 的需求合同；blob 56626 B，在 926ef539 与当前 HEAD 之间逐字未变（已随人工审批按 evidence-digest 钉住）。本 SDD 只读引用，任何修订必须回到需求侧，不得由本阶段改写

dep-2
  repo: ai-first-platform-docs
  relative path: change-requests/CR-2026-069/sources/CR需求来源_CR流程降本提效_收敛版.md
  stable symbol/对象: 收敛版需求来源（§1 首期三项、§2 硬边界、§3.1/§3.2 既有基础设施、§5 FR-8、§6 FR-1、§7 FR-2、§8 十 TASK、§9.1 十六条硬验收、§10 回滚、§11 非目标、§12 候选 Backlog）
  commit SHA: a4e33ff50a6868608599b37119ba3011e0a155d8
  依赖结论: 本 CR 的范围权威；blob 26406 B，自引入提交起逐字未变。首期范围 = FR-8 + FR-1 + FR-2；FR-3～FR-7 与 FR-9 只是编号占位

dep-3
  repo: tools
  relative path: ARCHITECTURE.md
  stable symbol/对象: §3 代码地图、§4 分层与依赖方向、§5 硬不变量 1～8、§6 刻意不做（含"另一套独立 WAL/事务框架"与"独立账本操作脚本库"两条否决记录）、§8 维护规则
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 本设计的架构约束来源：依赖只朝下、账本单一写入通道、零第三方依赖、行尾与硬失败纪律、状态机口径唯一、Skill 通用约束归仓。本 CR 不新增也不修改这些不变量

dep-4
  repo: multica
  relative path: server/internal/daemon/execenv/crguard_config.go
  stable symbol/对象: prepareCRGuard / CRGuardResult（每任务 env 锻造：PATH shim + provider=claude 时写 {workDir}/.claude/settings.json；hook 脚本路径从 rules.json 位置派生；已存在则跳过并告警）
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: 本 CR 的挂载先例与挂载点：Runtime 启动接线在既有每任务 env 锻造流程内完成、且"派生路径而不是二次配置"是既有做法。该函数内**唯一的 Runtime hooks 写入分支是 provider=claude**（其余 provider 只走 PATH shim），daemon 对 codebuddy / qoder 不写任何 hooks 配置（二者的每任务写入面见 dep-15）。本 CR 只在 claude 分支内合成 OutputGuard hooks；挂载入参为空时该函数行为逐字不变

dep-5
  repo: tools
  relative path: skills/shared/crctl/scripts/lib/durable-tx.mjs、lib/workspace-transactions.mjs、lib/outbox-contract.mjs、lib/yaml-subset.mjs
  stable symbol/对象: durable-tx 的锁/journal envelope/recoverable write-set/CAS/nowIso/FAULT_POINTS；workspace-transactions 的仓库与 worktree 解析、候选 manifest 校验、受控 Git、原子提交、checkpointCr、release-subjects；outbox-contract 的事件可比字段；yaml-subset 的行级解析器
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 跨文件与跨仓写入的唯一既有实现（四个文件构成 lib 面）。本 CR 零 diff，只允许消费式 import；新增代码不得引入第二套锁/journal/CAS/提交框架

dep-6
  repo: tools
  relative path: skills/shared/crctl/scripts/crctl.mjs
  stable symbol/对象: ok(obj)（全量缩进打印、45 个调用点）、fail(code,message,extra)（247 个出口，写 stderr 并非零退出）、parseArgs（`--flag` 通用取值且对未知 flag 零校验）、main() 的 switch dispatch
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: FR-2 的事实基线：成功输出是单一漏斗、错误面与成功面完全分离、flag 解析无白名单。因此 `--detail` 既不会被既有实现拒绝，也不会因"未注册"而报错，但需要专用布尔分支以免吞掉后随 token

dep-7
  repo: tools
  relative path: skills/shared/controlled-shell/rules.json
  stable symbol/对象: git 白名单（sub/shapes）、forbiddenFlags、protectedPaths.deny（`cr.md` / `_backlog.yml` / `approval.yml` / `review-loop.yml` / `review-annotations/*.yml`）与 ask（`specs/`、`delivery/`、`test-report.md`）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 先于 OutputGuard 的既有安全控制面。逃生阀只影响 OutputGuard 的封顶，不得影响该面（AC-6 四条负向测试的对象）。本 CR 零 diff

dep-8
  repo: tools
  relative path: skills/shared/crctl/gates.json
  stable symbol/对象: statusGates（含 `tech-design-review-pending` = fileExists `change-requests/{cr}/sdd.md`）、approvalStages（含 `tech-design` 的 to/trigger/expect/approvalSection/passCondition）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 技术设计阶段的证据路径与审批声明唯一源；本 CR 零 diff

dep-9
  repo: tools
  relative path: pipeline-templates/*.pipeline.json、pipeline-templates/_index.yml、skills/_index.yml
  stable symbol/对象: `architecture-design` 的 4 节点与其 reviewLoop（repairNodeId/repairRef/replayNodes/maxAttempts=3/passCondition：verdict=pass ∧ blockers 为空）、`code-implementation` 的 12 节点；两个 `_index.yml` 的 active 条目集
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 节点数（5/4/12）与 reviewLoop 是既有合同；且 pipeline 的 skill 引用必须落在 `skills/_index.yml` 的 active 集内 —— 因此新增目录不得被注册为 skill

dep-10
  repo: tools
  relative path: skills/shared/crctl/adapters/claude-code/{settings.template.json,hooks/pretooluse-guard.mjs,README.md}
  stable symbol/对象: hooks 段模板（PreToolUse / SessionStart / UserPromptSubmit）+ `{TOOLS_ROOT}` 安装时物化为绝对路径的约定 + 三步安装说明
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: OutputGuard 的 Claude 安装形态与 README 结构沿用该先例；两套适配器各自持有模板文件、不共用一个事实源（§3.4）

dep-11
  repo: tools
  relative path: skills/shared/crctl/adapters/qoder/{settings.template.json,README.md}
  stable symbol/对象: `.lingma/settings.json` 三级配置面（用户级/项目级/项目本地）、格式与 Claude 一致、**无 SessionStart**（注入挂 UserPromptSubmit）、改配置需重启
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: Qoder 的安装面与 hook 协议族事实；OutputGuard 的 Qoder 适配器沿用同一映射，`capabilities.qoder.startRecord` 只能记 `none`

dep-12
  repo: tools
  relative path: skills/shared/crctl/adapters/codex/{hooks.json.template,README.md}
  stable symbol/对象: `.codex/hooks.json`（用户级/项目级）与 config.toml `[[hooks]]` 等效、matcher 为正则、非托管 command hook 有 `/hooks` 审查-信任（按哈希，脚本变更需重新信任）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: Codex 的安装面与"信任"前置；OutputGuard 的 Codex 适配器按 partial 处理，README 必须写明信任步骤

dep-13
  repo: tools
  relative path: skills/shared/crctl/scripts/test/{suite-gate.mjs,gate-registry.json,assertion-sources.mjs}
  stable symbol/对象: `readTestFileSet(toolsRoot)`（只收 `*.test.mjs`）；磁盘文件集合 ≡ `manifest.files`（`SUITE_MANIFEST_FILE_DRIFT`）；每文件顶层用例数 ≥ `manifest.cases` 基线（`SUITE_MANIFEST_CASE_DROP`）；`manifest.files` 当前 21 项、`exceptions` 为空数组
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 在被扫描目录内新增 `*.test.mjs` 会**立即**触发文件集合漂移红，因此登记同步是硬约束（AC-21②）；同时该目录外的测试文件不受此棘轮保护，必须有独立 CI 步骤

dep-14
  repo: tools
  relative path: skills/shared/crctl/scripts/test/{merge-fixture.mjs,fault-harness.test.mjs,assertion-sources.mjs}
  stable symbol/对象: 三 bare remote 的事务夹具构造、故障注入与恢复断言、状态机/索引断言工具
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 采集 `--detail` 金样本与构造 FR-8 测试样本时复用这些既有夹具构造方式（消费式引用），不得另造并行夹具体系

dep-15
  repo: multica
  relative path: server/internal/daemon/execenv/runtime_config.go
  stable symbol/对象: 每任务运行时配置与记忆文件的写入责任面（per-provider 的 `CLAUDE.md` / `CODEBUDDY.md` / `AGENTS.md` 与各 Runtime 的原生 skills 发现路径，含 Pi 的 `.pi/skills/`）
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: 每任务运行时资源写入的既有责任边界：该面写入的是 Prompt/记忆文件与各 Runtime 的原生 skills 发现路径，**不含任何 Runtime 的 hooks 配置文件**（hooks 写点只有 dep-4 的 claude 分支）。因此 codebuddy / qoder 的 OutputGuard 挂载不能落在此面；本 CR 不改动记忆文件的既有语义，也不为这两个 Runtime 新增写点（§4.9 第 4 步）

dep-16
  repo: multica
  relative path: server/pkg/agent/pi.go
  stable symbol/对象: buildPiArgs（`-p` / `--mode json` / `--session` / `--model` / `--thinking`）与 piBlockedArgs（`--extension`/`-e`/`--no-extensions`/`--session-dir` 等被阻断项）
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: Pi 的 argv 面不放开：用户 custom_args 不能注入扩展；因此 Pi 的 OutputGuard 挂载只能走宿主级配置面（`~/.pi/agent/settings.json#extensions` 或 `~/.pi/agent/extensions/`），不能靠 argv 注入

dep-17
  repo: multica
  relative path: server/internal/daemon/tool_output_preview.go
  stable symbol/对象: `toolOutputPreviewBudget = 8192` 与包注释 "It does not limit the full output consumed by the agent."
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: 该文件只限制展示/预览预算，不限制模型消费的完整输出，因此不是本 CR 的 seam。本 CR 零 diff（AC-12）

dep-18
  repo: multica
  relative path: CUSTOM.md
  stable symbol/对象: 「按 CR 里程碑归类」的二开台账（行号稳定 ID、合并注意列、核对口径 grep 命令）
  commit SHA: 947386318d52ecdb026a017f76220cde2ef7b94e
  依赖结论: 凡在 multica 仓落代码必须按其现状登记；TASK-09 的改动（`dep-4` 新增入参 + 新增 `outputguard_config.go`）必须新增台账条目

dep-19
  repo: tools
  relative path: .github/workflows/crctl-ci.yml
  stable symbol/对象: `on.push` / `on.pull_request` 的 `paths` 列表；`jobs.contracts.steps`（lint-prompts --mode enforce、check-skill-matrix、check-agents-contract、pipeline 结构断言、suite-gate --run、writeback 单测）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: `paths` 已含 `skills/**`，故新增的 `skills/shared/metrics/**` 本就在触发面内；`output-guard/**` 不在触发面内，不补则该新执行面的测试永不进入 CI。真正缺的是 `steps`：现有步骤里没有 metrics 与 output-guard 的测试步骤（动作结论不变：`paths` 增两项、`steps` 增两条；否则 NFR-7 的回归保护失效）

dep-20
  repo: tools
  relative path: skills/shared/crctl/scripts/lint-prompts.mjs
  stable symbol/对象: R7（advance --to/--trigger、backlog-set 字段白名单、--template subject 编号）、R8（inbox-emit 接口）、R9（下一步提示收敛 crctl next）、R10～R13（废弃接口/退役 Skill/状态机副本/backlog 状态推断）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: 规则集内**没有**"未知 flag"校验，因此在 Skill 文本中新增 `--detail` 不会触发 lint 漂移；同时该工具抓不到"crctl 新增能力但 Skill 未采纳"，该面只能由 §8 清单 + `caller-contract.test.mjs` 兜住

dep-21
  repo: tools
  relative path: skills/develop/review-tech-design/SKILL.md、skills/develop/review-code/SKILL.md、skills/develop/review-dev-plan/SKILL.md、skills/requirement/review-requirement/SKILL.md
  stable symbol/对象: 四个 reviewer Skill 的 crctl 调用面（status/next/gate/attempt/review-record）及其引用的输出字段（gateBlockers/reviewLoops/warnings/legalNext）
  commit SHA: 82e43dc53d51f69a799904c786900ea78e57ca12
  依赖结论: AC-21① 的真实调用方主体；投影命令集确定后必须逐条核对是否需要 `--detail`，并在其中新增 `complete=false` 取证完整性规则
```

#### 待核实依赖（`V-1`～`V-7`）

以下引用的外部事实**无法绑定** `repo` + 40 位 `commit SHA` 五要素（npm 全局安装的包、外部厂商文档），因此单列于此，正文只以 `V-N` 引用；每条给出可复跑的核实命令与"核实失败时的唯一合法动作"。**编号按语义分组（V-1～V-3 = Pi、V-4～V-7 = 各 Runtime 文档）而非首现顺序——顺序规则只适用于 `dep-N`。**

```text
V-1  Pi 扩展 API（@earendil-works/pi-coding-agent 0.85.1，本机全局安装）
  声明: `tool_call` 可阻断（返回 {block:true, reason?, terminate?}；event.input 可原地改写且不重新校验）；`tool_result` 可修改（返回 {content, details?, isError?, usage?} 局部 patch，省略字段保持原值；handlers 按加载顺序链式）；扩展发现面 = `~/.pi/agent/extensions/*.ts`、`.pi/extensions/*.ts`（及 */index.ts），额外路径可经 `settings.json#extensions[]` 声明；`PI_CODING_AGENT_DIR` 可覆盖配置目录（默认 `~/.pi/agent`）
  证据: docs/extensions.md（事件流 L304-306、tool_call L778-796、tool_result L842-855、扩展位置表 L113-135）、docs/environment-variables.md L81、dist/core/extensions/loader.js L572-573
  核实命令: PI_PKG="$(npm root -g)/@earendil-works/pi-coding-agent"; node -e "console.log(require(process.argv[1]+'/package.json').version)" "$PI_PKG"; sed -n '842,856p' "$PI_PKG/docs/extensions.md"; sed -n '110,136p' "$PI_PKG/docs/extensions.md"
  失败动作: 若结果回填不受支持 → `capabilities.pi.level` 降级为 partial/unavailable，按 SDD-CLOSE-05 走 scope amendment

V-2  Pi session JSONL 形状与规模
  声明: 每行一条 JSON 记录，`type` ∈ {session, model_change, thinking_level_change, message}；message 记录形如 {type:'message', id, parentId, timestamp, message}，`message.role` ∈ {user, assistant, toolResult}；assistant 的 `content[]` 含 {type:'toolCall', id, name, arguments}，`message.usage` 含 input/output/cacheRead/cacheWrite/reasoning/totalTokens 与 `cost.{input,output,cacheRead,cacheWrite,total}`；toolResult 含 {toolCallId, toolName, content[], isError, timestamp} 与可选 details
  口径与观测时刻: 本机 `~/.multica/pi-sessions` 直属 `*.jsonl` 共 585 个（观测 2026-09-17 15:35 CST；口径 = 该目录直属 *.jsonl、非递归）；抽样文件 20260825T102935.566100800.jsonl（1,707,218 B）内 role 计数 user=1 / assistant=47 / toolResult=109，toolName 直方图 {bash:945, read:349, write:45, edit:27}（样本 = 该目录前 30 个文件）
  核实命令: node -e "const fs=require('fs'),p=process.argv[1];const l=fs.readFileSync(p,'utf8').replaceAll(String.fromCharCode(13,10),String.fromCharCode(10)).split(String.fromCharCode(10)).filter(Boolean);const s={};for(const x of l){const o=JSON.parse(x);const k=o.type+(o.message?'/'+o.message.role:'');s[k]=(s[k]||0)+1}console.log(s)" "$HOME/.multica/pi-sessions/20260818T043049.725742100.jsonl"
  失败动作: 键名不同 → 只改 `lib/sessions.mjs` 的读取口径；`dep-1` FR-8 第 3 项的输出字段集是需求面，不改

V-3  Pi 内置工具截断行为
  声明: bash 工具的 toolResult.details 会带 `truncation`（含被丢弃正文片段）与 `fullOutputPath`（完整输出落盘路径）；read 工具的 details 带 `truncation`
  证据: `V-2` 同一抽样命令下实读到的 details 形状 + dist/core/tools/bash.js 的截断/退出码分支
  影响: AC-7 / AC-15 的 sentinel 用例必须把 payload 控制在 Pi 自身阈值以下，才能把"谁的丢弃"隔离干净（§7.4 R-4）
  失败动作: 若该行为已变 → 调整 sentinel 用例的 payload 控制策略；本 CR 不治理该既有行为（F-5）

V-4  Claude Code hooks 文档   来源 https://code.claude.com/docs/en/hooks
V-5  CodeBuddy Code hooks 文档   来源 https://www.codebuddy.ai/docs/cli/hooks
     本轮已实读的部分（2026-09-17，用于 §3.3/§3.4 的落点选择）: 配置面 `~/.codebuddy/settings.json`（用户）/ `<project-root>/.codebuddy/settings.json`（项目）/ `.codebuddy/settings.local.json`；多 scope 的 hooks 为**合并**而非覆盖；`PostToolUse` 支持 `hookSpecificOutput.updatedToolOutput` 替换工具结果（文档明示该能力用于压缩冗长输出）与 `additionalContext` 追加；`PreToolUse` 支持 `permissionDecision` / `modifiedInput`；Windows 下 hook command 强制 Git Bash；配置在会话启动时快照、改配置需重启；`/hooks` 面板审查
V-6  Qoder hooks 文档   来源 https://docs.qoder.com/en/cli/hooks
V-7  Codex hooks 文档   来源 https://developers.openai.com/codex/hooks
  声明（V-4～V-7 共用）: 各 Runtime 的 Pre/Post hook 事件名、结果回填能力（updatedToolOutput 或 block/feedback）、配置面路径、信任/审查前置、Windows shell 约束
  失败动作: 逐 Runtime 落 `capabilities.level`；任一 Runtime 由 full 降级即 AC-4 未达成（§2.4 + SDD-CLOSE-05），不得静默吸收
```

**依赖引用规则自查**：① 正文出现的每个 `dep-N` 均在本节有定义；② 本节编号按正文首现顺序分配（本轮自查：1～21 的首现序严格单调、无空洞、无未定义引用；行号随每次修订漂移，故不在此固化）；③ 无法绑定五要素的外部引用全部在"待核实依赖"单列，正文只以 `V-N` 引用；④ 本 CR 确有既有实现依赖，故本节不写 `N/A`。

### 6.4 既有测试面改动清单与零改动核对清单

**改动清单（全部为"增项"，不改既有断言语义）**：

| 面 | 动作 | 触发原因 |
|---|---|---|
| `dep-13` 的 `gate-registry.json` | `manifest.files` 增 `crctl-summary.test.mjs`、`caller-contract.test.mjs`；`manifest.cases` 增两条对应基线 | 磁盘测试文件集合 ≡ `manifest.files`（`SUITE_MANIFEST_FILE_DRIFT`），新增文件不登记即红 |
| `dep-13` 的 `gate-registry.json#exceptions` | **保持空数组**，不新增例外 | AC-21③ |
| `output-guard/test/*.test.mjs` | 新增，由 CI 新增步骤执行 | 不在 `dep-13` 的扫描目录内，因此**必须**有独立 CI 步骤，否则新合同无回归保护 |
| `skills/shared/metrics/test/cr-cost.test.mjs` | 新增，由 CI 新增步骤执行 | 同上 |
| `dep-19` 的 `.github/workflows/crctl-ci.yml` | `paths` 增 `output-guard/**`、`skills/shared/metrics/**`；`steps` 增 `output-guard` 与 `metrics` 两条测试步骤 | `paths` 已含 `skills/**`（metrics 仅在触发面内），但 `output-guard/**` 不在；且两类测试都没有对应 `steps` → 不增则新目录的测试不会执行（部署面裸奔） |

**零改动核对清单（提交前逐条 `git diff --name-only` 核对）**：`dep-5` 的 lib 四文件、`dep-7`、`dep-8`、`dir-graph.yaml`、`dep-9` 全部 pipeline JSON 的**结构**（节点数 5/4/12、reviewLoop / replayNodes / maxAttempts；prompt 文本按 §9 `scope_in` 第 4 项的判定，最多补 `--detail`）、`agent-skill-matrix.yml`；以及 multica 侧除本次落点（`dep-4` 文件 + 新增 `outputguard_config.go` + 同包测试 + `CUSTOM.md`）之外的运行时语义文件（**含 `dep-15` 的 `runtime_config.go`**、`dep-16`、`dep-17`）；`prd.md`、四账本（`cr.md` 的 status 行由 crctl 写入，不计入）、`specs/`、`delivery/`、`docs/`。

**`dep-18` 不在本清单内**：`../multica/CUSTOM.md` 按 §9 `scope_in` 第 5 项**必须**新增本次定制的台账条目，不适用零 diff（§1.2 的 multica 变更面已同步标注）。

### 6.5 SDD-CLOSE 关闭义务（CR-2026-060 AC-06）

`dep-1` 显式延后到 SDD 的设计项逐项关闭如下。每项覆盖该事项实际涉及的数据生产、存储/传输、消费与兼容降级层。

| 编号 | 待关闭项（来源） | 关闭结论 | 覆盖层 |
|---|---|---|---|
| SDD-CLOSE-01 | Adapter 目录归属与安装入口是否与既有 crctl 适配器共用（`dep-1` §1.5 第 8 条） | **分目录、分模板、分安装入口；唯一联合点是 Managed scope 下的 daemon 单写入点合成（仅 claude）**（§3.4、§4.9） | 生产（模板）／传输（安装物化）／消费（Runtime 配置）／降级（任一模板缺失只影响该 Runtime） |
| SDD-CLOSE-02 | `--detail` 与旧完整输出的"等价"定义（§1.5 第 6 条） | **三层等价性合同：字段集合 ≡ / 稳定值逐字 ≡ / 易变字段形态 ≡；禁止字节比对**（§4.6） | 生产（投影函数）／传输（stdout）／消费（调用方字段集合，§4.10）／降级（未投影命令等价现状） |
| SDD-CLOSE-03 | 新增合同测试的棘轮登记同步义务（§1.5 第 7 条） | **`manifest.files` + `manifest.cases` 同批更新；`exceptions` 保持空；新增目录另加独立 CI 步骤**（§6.4） | 生产（测试文件）／存储（登记面）／消费（suite-gate）／降级（不登记即红，不静默） |
| SDD-CLOSE-04 | 逃生阀标记不合法时的行为（§1.5 第 5 条） | **视为不存在（`absent`）**：不拒绝调用、不新增 action 取值；若随后被裁剪仍出 `action=truncate` trailer（§4.1） | 生产（解析）／传输（Pre hook 决策）／消费（执行与结果面）／降级（无第二套错误码） |
| SDD-CLOSE-05 | Runtime 能力不足时的降级路径与 AC-4 联动（§1.5 第 4 条 + 需求评审 S-3） | **降级唯一合法动作=改 `capabilities.json`；由 full 降级即视为 AC-4 未达成，须回人工确认（scope amendment）后重定 AC-4**（§2.4） | 生产（声明）／存储（capabilities.json）／消费（conformance 与 FR-8 覆盖度）／降级（partial/unavailable 显式） |
| SDD-CLOSE-06 | 是否引入 plugin 打包形态（§1.5 第 9 条） | **不引入**；沿用模板 + 安装时物化绝对路径（D-3、§3.4） | 生产（模板）／传输（安装动作）／消费（Runtime 配置加载）／降级（未安装＝未启用，检查脚本报告） |
| SDD-CLOSE-07 | FR-8 机器结果的落点与"不新增账本"的边界（`dep-1` FR-8 第 1/3 项与 AC-17④） | **机器 JSON：脚本 `--out` + KB `change-requests/CR-2026-069/evidence/` 副本 + Issue 附件；人读摘要只走 stdout（不写第二份产物文件）；四账本零变化**（§3.6） | 生产（聚合）／存储（evidence）／消费（TASK-08 选择 + TASK-10 复测）／降级（`insufficient-sample`） |
| SDD-CLOSE-08 | 计数类断言的"口径 + 观测时刻"义务（§1.5 第 3 条 + 需求评审 S-4） | **每个计数字段携带 `observedAt` 与 `rule`；脚本与门禁中零硬编码样本常量**（§3.6） | 生产（脚本输出）／存储（JSON 字段）／消费（评审与复算）／降级（口径缺失即实现缺陷） |
| SDD-CLOSE-09 | Managed scope 的挂载责任面（`dep-1` §1.3.2 multica 行） | **daemon 写点只有一个：claude 的 `{workDir}/.claude/settings.json`（单写入点合成）；codebuddy/qoder/pi/codex 走各自原生配置面的显式安装一次，daemon 不为其新增写点**；生效性由 `check-install.mjs` 读数 + AC-14 冒烟判定（§1.4.2、§3.4、§4.9） | 生产（挂载解析）／传输（每任务配置文件 vs 安装时物化模板）／消费（Runtime 加载）／降级（未配置即整体跳过，行为零变化；目标文件已存在即跳过并告警） |
| SDD-CLOSE-10 | `exitCode` 等"字段必须保留"的可执行化（`dep-1` FR-1 第 5 项） | **按 Runtime 结果结构的真实字段集判定：`present` 必保留，`absent-by-runtime` 不作要求且不因此降级**（§4.2、D-6） | 生产（可保持性检查）／传输（结果回填）／消费（门禁证据判定）／降级（不可保持 → `unavailable`） |

---

## 7. 安全与性能考量

### 7.1 行尾纪律与硬失败（I9）

任何读入仓库文件或 session 文件的代码（Adapter 读 policy、度量脚本读 JSONL、测试读金样本）**必须先 `\r\n → \n`**，逐行解析用 `split(/\r?\n/)`；跨行正则匹配失败必须硬失败报错，禁止"匹配不到 → 空集 → 静默通过"。落地判据：新增的解析函数全部经由 `core.mjs#normalizeText` 或同名等价入口，且失败路径抛错/非零退出。三处高风险面单独列出：

1. **金样本比对**（§4.6）：Layer ③ 的易变字段形态判定在 EOL 归一后执行，防止 Windows 检出差异造成假失败。
2. **session 遍历**（§4.7）：JSONL 逐行 `JSON.parse`，单行解析失败计入 `malformedLines` 并保留观测计数，**不得**整体静默跳过文件；文件级读失败必须计入 `unreadableFiles` 并在输出中可见。
3. **multica 挂载合成**（§4.9）：读取既有配置文件失败时按"存在即不 clobber"处理并告警，**不**写半成品文件。

### 7.2 安全边界（fail-open 与 fail-closed 正交）

| 面 | 失效行为 | 依据 |
|---|---|---|
| OutputGuard（Adapter / policy / Core） | **fail-open**：原调用继续、结果不改、显式标 `coverage=unavailable` | FR-1 第 8 项 |
| crctl / Git 白名单 / 受控路径 / 审批 / 账本写入 | **fail-closed 不变**：本 CR 不改其任何判定逻辑 | `dep-7`、NFR-6 |

四条不可跨越的边界（AC-6 与 AC-19 的负向面）：

1. 逃生阀只影响 OutputGuard 的封顶，**不影响** git 白名单 / protected paths / 审批 / 账本写入控制；
2. OutputGuard 不新增任何授权面（无授权文件、无 nonce、无"下一次调用"状态、无远程开关）；
3. 启动检查只读：**不**自动安装、**不**改写用户配置、**不**修复 Runtime；
4. 被丢弃正文不落盘、不进 transcript、不进任何日志；度量只记 token 数与计数，不存正文（隐私面）。

### 7.3 性能与可观测

| 面 | 目标 | 手段 |
|---|---|---|
| hook 延迟（每次工具调用） | 同数量级于"读一个小 JSON"；不引入外部进程、不做网络调用 | policy 读取后在同一次 hook 调用内复用；Core 为 O(n) 单遍扫描；无正则回溯风险模式（限长匹配） |
| 内存 | 被丢弃正文立即释放（不缓存、不堆积） | 只保留 kept 片段与计数；不保留 original |
| FR-2 收益 | 默认面 token 数下降（不设硬指标；由 FR-8 复测观察） | 字段投影 + 保持既有格式化（D-2） |
| FR-8 运行成本 | 离线、可重复、单次全量遍历；不进入 CR 门禁与 Pipeline | 只读遍历 + 纯函数聚合；不执行任何命令 |
| 可观测 | 只有两个可见面：一行 trailer、一行启动记录 | 不新增 JSONL/sidecar/DB/仪表盘（NFR-5） |

**回滚路径（FR-1 第 12 项）**：单 Runtime 误伤 → 移除该 Runtime 的安装配置（新会话生效，其它 Runtime 不受影响）；Core/Policy 共性错误 → 整体回退 Tools Release；阈值过严 → 改 `policy.json` 后随完整 Release 发布。三者都不需要补偿流程、不需要远程开关。

### 7.4 残余风险（需要在实施期被看见，而不是被假设掉）

| # | 风险 | 缓解与判据 |
|---|---|---|
| R-1 | AC-16 的"不得作为充分门禁证据"在"不新增门禁/状态"的约束下无法做成机器硬拦截 | 由"trailer 固定指令 + reviewer Skill 合同条款 + 至少一条端到端用例"三件套承载；残余风险如实登记（`follow_up` F-4） |
| R-2 | D-5（`unavailable` 也出 trailer）与 D-6（`exitCode` 按结构存在性）是对 `dep-2` §6.7 / `dep-1` FR-1 第 5 项的紧读边界裁决 | 两条裁决在 §9 `follow_up` 留了显式替代出口，并随本 SDD 进入人工审批过目；改动任一条会连带影响 AC-15 与启用顺序，必须在设计阶段决定 |
| R-3 | 某 Runtime 实测不具备 full 能力（`V-4`～`V-7` 待核实） | 按 §2.4 降级 + scope amendment；不得静默吸收（SDD-CLOSE-05） |
| R-4 | Runtime 自身的截断行为（`V-3`：Pi 把被丢弃正文放进 `details` 并写 `fullOutputPath`）会造成"谁的丢弃"混淆 | 测试夹具控制 payload 尺寸以隔离；该行为本 CR 不治理（F-5） |
| R-5 | Pi 的扩展加载面（`V-1`）与 Multica 的 argv 白名单（`dep-16`）共同决定 Pi 只能走宿主级安装 | 已在 §1.4.2 / D-7 落成显式设计；AC-14 冒烟必须在 Multica 启动的真实任务环境完成 |
| R-6 | codebuddy / qoder / pi / codex 的 Managed 挂载依赖**显式安装一次**，漏装即该 Runtime 静默无治理（会话里不会出现任何 trailer，与"未触发"不可区分） | 由 `check-install.mjs` 的逐 Runtime 读数（AC-19③）+ AC-20 的启用前置（conformance + 真实冒烟 + 降级验证）暴露；不新增远程开关、不做自动安装（AC-19③ 的负向面） |

---

## 8. Prompt 采纳影响

**触发判定**：本 CR 的 diff 触及 `dep-6`（`crctl.mjs`）的 dispatch 与成功输出投影层 → 本节必填。另需说明：「新增能力未被采纳」这类漂移是 `dep-20`（`lint-prompts` 的 R7～R13）**抓不到的**——它只校验参数形态、废弃接口与状态机副本一致性，不校验未知 flag，因此新增 `--detail` 本身不会触发 prompt 漂移，采纳与否只能由本节 + `caller-contract.test.mjs` 兜住。

**与典型情形的差别（关键）**：本 CR **不新增 crctl 子命令**，只新增一个布尔型呈现层开关 `--detail` 并改变被投影命令的**默认输出字段集**。因此本节的采纳义务不是"改用新子命令"，而是三件事：① 把 `--detail` 写进权威 Skill 文档；② 对"需要 summary 之外字段"的真实调用点显式补 `--detail`（A10 的机械扫描面）；③ reviewer 类 Skill 采纳 `complete=false` 的取证完整性规则（AC-16）。

| Skill / 文件 | 现状 | 应改为 |
|---|---|---|
| `skills/shared/crctl/SKILL.md` | 只描述子命令与参数形态，未提及任何输出投影开关；示例隐含"输出为完整 JSON" | 增一节（或并入既有"调用方式"段）：默认输出为 compact summary；需要完整字段时显式加 `--detail`；明确"未投影命令加 `--detail` 等价于现状"；不复刻任何字段清单（只指向 `summary-projectors.mjs`） |
| `dep-21`：`skills/develop/review-tech-design/SKILL.md`、`skills/develop/review-code/SKILL.md`、`skills/develop/review-dev-plan/SKILL.md`、`skills/requirement/review-requirement/SKILL.md` | 四份均已以 `crctl status` / `next` / `gate` / `attempt` / `review-record` 原样调用，并逐字引用 `gateBlockers` / `reviewLoops` / `warnings` / `legalNext` 等字段 | 按 A10 表：若涉及字段不在该命令 summary 内 → 调用改为带 `--detail`；同时增一条"以 `complete=false` 结果不得作最终判断，须继续切片取证或走逃生阀（AC-16）"的规则条款 |
| `skills/develop/approve-tech-design/SKILL.md`、`skills/develop/approve-dev-start/SKILL.md`、`skills/develop/approve-code/SKILL.md`、`skills/requirement/approve-requirement/SKILL.md` | 同样消费 `crctl status/gate` 的完整字段（证据摘要、`gateBlockers`） | 同上（按 A10 表定点补 `--detail`） |
| `skills/sync/**`（`push-progress` / `pull-progress` / `workspace-freshness` / `handover-cr` / `resume-from-remote`） | 消费 `crctl status` / `workspace inspect` / `workspace freshness` 的完整字段 | 同上（按 A10 表定点补 `--detail`） |
| `pipeline-templates/*.pipeline.json` 的 prompt 文本 | 含 `crctl <命令>` 示例调用 | A10 扫描面内逐条判定：命中（该步骤需要完整字段）→ **在同一 CR 内**定点补 `--detail`（§9 `scope_in` 第 4 项的同一义务）；不新增节点、不改 reviewLoop、不改其余结构 |
| `agents/*.md` 与 `README.md` | 含 `crctl` 调用叙述 | 同上（`agents/*.md` 命中即在本 CR 内补 `--detail`）；README 只增导航与权威入口（AC-13） |
| `output-guard/**` 文档（新增） | — | README/模板只允许写"路径 + 安装命令 + 检查命令"，禁止复制 `policy.json` 阈值与 `capabilities.json` 能力矩阵 |

**冻结机制**：A10 的显式表落成 `skills/shared/crctl/scripts/test/caller-contract.test.mjs` 的数据段。该表是**人工审过的白名单**，断言是机械的——任何调用点与表不符（缺 `--detail` 或声明与实际字段消费不一致）即红。因此 `dep-20` 抓不到的那一类漂移，在本 CR 里由该测试 + `review-dev-plan`/`review-code` 的 Prompt 采纳维度共同兜住。

---

## 9. 批准范围

### scope_in（当前 CR 必须交付的 FR/AC）

1. **FR-8 全量**：`skills/shared/metrics/scripts/cr-cost.mjs` + `scripts/lib/{sessions,aggregate,select,render}.mjs` + `test/cr-cost.test.mjs`；`baseline`/`after`/`replay`/`verify-selection` 四个子命令；TASK-01 的机器 JSON 副本落 `change-requests/CR-2026-069/evidence/`（AC-17 / AC-18 / AC-9）。
2. **FR-1 全量**：`output-guard/{core.mjs,policy.json,capabilities.json,conformance.json}` + 五个 Adapter 目录 + `scripts/check-install.mjs` + `test/*` + 各 Adapter README（AC-3～AC-8、AC-13～AC-16、AC-19、AC-20）。
3. **FR-2 全量**：`skills/shared/crctl/scripts/lib/summary-projectors.mjs`；`crctl.mjs` 的**三处改动**（`ok()` 投影入口、`parseArgs` 的 `--detail` 布尔分支、HELP 一行）；`test/crctl-summary.test.mjs`；`test/caller-contract.test.mjs`；`test/golden/crctl-detail/*.json`；`test/gate-registry.json` 的 `manifest.files` / `manifest.cases` 同步（AC-10、AC-11、AC-21）。
4. **Prompt 采纳面**（§8）：`skills/shared/crctl/SKILL.md`、四个 review Skill、四个 approve Skill、`skills/sync/**` 中 A10 表命中项的定点补 `--detail` 与 AC-16 规则条款；**同一义务覆盖 A10 扫描面内判定命中的 `pipeline-templates/*.pipeline.json` prompt 文本与 `agents/*.md` 落点**（只补 `--detail`，零节点/零结构变化——AC-21① 要求扫描面内全部真实调用方在同一 CR 内更新，故这些落点属于交付面而非后续项）。
5. **治理登记与 CI 面**：`dep-18`（`../multica/CUSTOM.md` 按其现状登记本次定制，**该对象按定义就要改，不适用零 diff**）；`dep-19`（`.github/workflows/crctl-ci.yml` 的 `paths` 增 `output-guard/**`、`skills/shared/metrics/**`，`steps` 增两条测试步骤）；`README.md` 增导航与权威入口；`ARCHITECTURE.md` 增 §1 鸟瞰一条组成面 + §3 代码地图 `output-guard/` 与 `skills/shared/metrics/` 两条（依据 §8 维护规则，§4/§5/§6 不改）。
6. **TASK-09 挂载（Managed scope）**：`../multica` 新增 `server/internal/daemon/execenv/outputguard_config.go`（挂载解析 + claude 合成入参）与 `crguard_config.go` 的单写入点合成（**仅 provider=claude 分支**）+ 同包回归测试；**不新增** codebuddy/qoder 的 daemon 写点（二者走各自原生配置面的显式安装一次，见 §4.9 第 4 步）（AC-14、AC-19、AC-20）。
7. **交付证据**（KB `change-requests/CR-2026-069/evidence/`）：TASK-01/TASK-10 的机器 JSON（`fr8-baseline.json` 等）、各 Runtime 的真实冒烟记录 + 每个 Runtime 一行 `check-install.mjs` 输出（`ac14-smoke.md`）、conformance 结果、调用方扫描表（`caller-contract.test.mjs` 内的显式表，含扫描面之外的真实调用方判定）、AC-9 的合法调用抽检清单与判定（`ac9-sampling.md`）、AC-10 的 `verify-selection` 输出。

### scope_out（明确排除的路径和能力）

- **FR-3 / FR-4 / FR-5 / FR-6 / FR-7 / FR-9**：候选 Backlog，编号保留、本 CR 不实施、不得借本 CR 顺手做（`dep-1` §7）。
- **`dep-17`（`tool_output_preview.go`）及其上游 daemon 展示/transcript 语义**：零 diff（AC-12）。
- **`../multica` 的 `server/internal/governance/runner.go`（固定 `architecture-design` 切片）与 Provider 事件归一化行为**：零 diff（AC-12）。
- **KB 的 `specs/` / `delivery/` / `docs/`**（含只读的历史分析文档）：零写入。
- **治理结构**：不新增状态、门禁、审批、CR 生命周期节点、Pipeline 节点、账本字段、数据库表、仪表盘、sidecar 日志、WAL、CAS 层、事务框架、远程动态开关、shadow mode。
- **实现手段**：不实现完整 Bash/PowerShell parser（管道/重定向/脚本嵌套不做解析）、不调用 LLM 做输出摘要、不做语义压缩、不优化 crctl 运行时小文件读取、不建 crctl 字段/错误码事实页、不引入 plugin 打包形态、不引入第三方 tokenizer 依赖。
- **运行环境**：不自动安装 Provider、不修复 Runtime、不重试失败工具调用、不改写任何用户配置文件。
- **历史数据**：不治理历史上从未读取的大文件；不通过合并相邻会话解决 bootstrap。

### zero_diff（明确不得改动的调用点 / 签名）

| 对象 | 约束 |
|---|---|
| `dep-6` 的 `crctl.mjs` 中除 `scope_in` 第 3 项列明的三处落点以外的全部代码（含 247 个 `fail()` 出口与全部状态/门禁/审批/CAS/事务/Git 分支） | 零修改（与 AC-1 的同一 carve-out） |
| `dep-5` 的 lib 四文件（`durable-tx.mjs` / `workspace-transactions.mjs` / `outbox-contract.mjs` / `yaml-subset.mjs`） | 零 diff 或仅消费式 `import`；不新增实现、不拆分、不重构 |
| `dep-8` 的 `gates.json` | 零 diff |
| `dir-graph.yaml`（含 `#change-request-track.state_machine`） | 零 diff（状态数与转移集不变） |
| `dep-9` 的全部 pipeline JSON 的**结构**（节点数保持 5/4/12、reviewLoop / replayNodes / maxAttempts 不变、不增删节点） | 零 diff；prompt 文本见 `scope_in` 第 4 项（A10 判定命中时最多补 `--detail`）——同一 carve-out 写法 |
| `agent-skill-matrix.yml` | 零 diff（不新增 Skill、不新增 actor/权限项） |
| `dep-7` 的 `controlled-shell/rules.json` | 零 diff（`protectedPaths.deny` 与 git 白名单面不变） |
| 既有测试文件的既有断言 | 语义零变化；只允许新增文件与新增用例，以及 `dep-13` 中 `manifest.files`/`manifest.cases` 的**增项** |
| `dep-15` 的 `server/internal/daemon/execenv/runtime_config.go`（每任务记忆文件与 skills 发现路径写入面） | 零 diff（不为 codebuddy / qoder 在该面新增 hooks 写点；§4.9 第 4 步、§6.4） |
| `../multica` 的 `server/internal/governance/runner.go`（固定 `architecture-design` 切片）与 Provider 事件归一化实现 | 零 diff |
| `dep-16` 的 argv 白名单面（`piBlockedArgs` 等既有清单） | 零 diff（不新增、不放开任何被阻断的 argv） |
| `dep-17`（`tool_output_preview.go`） | 零 diff（AC-12） |
| KB：`prd.md`（审批 evidence-digest 钉住）、`specs/`、`delivery/`、`docs/`、四账本手工编辑 | 零写入 |

（四字段自洽判据逐条自查：① 无对象同时出现在 `scope_in` 与 `zero_diff`——`dep-6` 按**落点**切分（三处投影落点在 `scope_in`、其余代码在 `zero_diff`），与 AC-1 的同一 carve-out 逐字一致；`dep-9` 的 pipeline JSON 同按落点切分（**结构**在 `zero_diff`、判定命中的 prompt 文本在 `scope_in` 第 4 项）；② 三处"外部规则强制修改"的对象——`dep-18` 的定制登记、`dep-13` 的棘轮登记同步、`dep-19` 的 CI 触发面——**全部已纳入 `scope_in`**，未留在 `zero_diff`；③ `scope_out` 未隐藏任何当前交付必须发生的治理修改；④ `follow_up` 各项均非当前 AC 的必要条件。）

### follow_up（发现但留给后续 CR 的缺口）

| 编号 | 缺口 | 为什么不在本 CR |
|---|---|---|
| F-1 | `dep-2` §6.10 的"Claude 由 Tools Plugin 携带 Skills 与 hooks"未落地（本 CR 按 D-3 走模板 + 安装时物化） | 引入 plugin 形态需要新的安装/版本/信任语义，属"不新建安装框架"边界外；需要独立 CR 决策 |
| F-2 | Qoder 无 SessionStart → 无会话启动记录（`startRecord: none`） | 属 Runtime 能力事实；厂商补齐后可把声明改为 `session-start` 以提升 FR-8 覆盖度派生精度，不影响当前 AC |
| F-3 | D-5 / D-6 两条紧读边界裁决的替代出口（若评审要求字面读法） | 本 SDD 已给出裁决；若人工审批改判，需连带重定 AC-15 与启用顺序（属 scope amendment，不在本 CR 内部消化） |
| F-4 | AC-16 无法在"不新增门禁/状态"的约束下做成机器硬拦截 | 升级为机器拦截需要扩展 `review-record` payload 或新增门禁维度，两者都被本 CR 的 `scope_out` 排除 |
| F-5 | Pi 内置截断把被丢弃正文写入 `details` 与 `fullOutputPath`（`V-3`） | 既有行为，不属于 OutputGuard 的副作用面；若 F-8 复测显示其仍是 token 大头，作为候选 FR 重新立项 |
| F-6 | Codex 的托管 hook 与 hosted `WebSearch` 等 uncovered 路径 | 首期只做声明与逐条标记，不追求全覆盖（`dep-2` §6.3 的限制明确如此） |
| F-7 | 后续新增 Runtime 的"字段存在性"口径 | 沿用 D-6：已有 `absent-by-runtime` 声明的 Runtime 不得被反向要求提供该字段；新 Runtime 必须按 `V-*` 核实后落笔 |

---

## 修订记录

- **初稿（2026-09-17）**：以 `dep-1`（已审批 PRD，冻结）与 `dep-2`（收敛版需求来源）为输入；按 `write-tech-design` 的九节骨架起草，条件触发的第 8 节（Prompt 采纳影响）因本 CR 触及 `crctl.mjs` dispatch 与成功输出投影层而必填。§6.3 的既有实现依赖表按正文首次出现顺序编号（`dep-1` 起），待核实依赖（`V-1` 起）单列于同节。关闭 `dep-1` 显式延后到 SDD 的 10 项（SDD-CLOSE-01～10）；对需求评审的 4 条非阻塞 suggestion 的处理：S-1 由 §1.4.6 与 §3.1 裁决（未投影命令 + `--detail` 等价现状）、S-2 由 §1.4.6 的 `action`/`coverage` 三级定义对齐、S-3 由 §2.4 + SDD-CLOSE-05 的 scope amendment 出口关闭、S-4 由 §3.6 的 `observedAt` + `rule` 义务关闭；**均未改写 `prd.md`**（该文件已随审批按 `evidence-digest` 钉住）。
- **回修 r1（2026-09-17）**：按 `review-tech-design` 第 1 轮（attempt 1/3、`verdict=block`）的 2 条 blocker 定点修订，未改写 `prd.md`、未逐 TASK 展开、未新增决策条目：
  1. **Managed scope 挂载契约（blocker 1）**：§1.4.2 的 Managed 行改为区分「记忆文件」与「hooks 配置文件」；§4.9 A9 由"与既有 hooks 单点合成"改为**逐 provider 分支表**（claude = daemon 单写入点合成并写出不 clobber 判据；codebuddy / qoder / pi / codex = 各自原生配置面的显式安装一次，daemon 不为其新增写点）；`dep-4` / `dep-15` 的依赖结论补上前提事实（"函数内唯一的 hooks 写入分支是 claude"、"该写入面不含任何 hooks 配置文件"）；同步 §3.4 第 3 项、§1.5 第 8 条、§1.4.5 交付顺序图、§6.5 SDD-CLOSE-01/09、§9 `scope_in` 第 6 项，D-7 增"范围澄清"，§7.4 增 R-6（漏装即静默无治理）。
  2. **变更面清单与 `scope_in` 自相矛盾（blocker 2）**：§6.4 把 `dep-18`（`../multica/CUSTOM.md`）从零改动清单移出并显式注明"按 §9 `scope_in` 第 5 项登记，不适用零 diff"；§1.2 的"既有文件改动（落点逐个列明）"补齐 `scope_in` 第 4 项点名的落点（`review-requirement`、四个 `approve-*`、`skills/sync/**`）以及 A10 判定命中的 `pipeline-templates/*.pipeline.json` prompt 文本与 `agents/*.md`（同时把 `dep-9` 的 zero_diff 收窄到"结构"，两侧按落点 carve-out，与 `dep-6` 同写法）；§6.4 的 `dep-19` 行与 `dep-19` 的依赖结论写准前提。
  3. **第 1 轮 7 条 suggestion 逐条处理**：S1 §6.3 自查行号改为"不固化"（只保留单调无空洞的结论）；S2 `dep-19` 写准 `paths` 已含 `skills/**`、真正缺的是 `steps`；S3 §2.2.1 统一为"三族五命令"；S4 D-5/D-6 的确认动作写入 §6.2 AC-15 可达性（随人工审批显式确认，plan/TASK 的取证判据按该口径）；S5 `ARCHITECTURE.md` 更新范围补 §8 维护规则判定依据（§1 + §3 增，§4/§5/§6 不改）；S6 AC-9 / AC-14 的证据落点定为 `evidence/ac9-sampling.md` / `evidence/ac14-smoke.md`（§1.2 与 §9 `scope_in` 第 7 项同步）；S7 §4.10 补扫描面之外真实调用方的判定口径（按字段消费，不按所在仓豁免）。
