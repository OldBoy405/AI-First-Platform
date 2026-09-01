---
id: CR-2026-058-sdd
type: SDD
cr-ref: CR-2026-058
title: writeback 版本守卫：cr.md unassigned + 真实版本放行并原子回灌 技术设计
target-version: 0.30
status: draft
created: 2026-09-01T14:13:52+08:00
updated: 2026-09-01T15:19:05+08:00
---

# writeback 版本守卫：cr.md unassigned + 真实版本放行并原子回灌 技术设计

> 输入：已审批 `change-requests/CR-2026-058/prd.md`（US×4 / FR×6 / AC×6，target-version=`0.30`）。
> 目标代码仓：sibling `../tools/`（`resources[].repo=tools`）。knowledge-base 只承载本 SDD；`../multica/` **零实施改动**。
> 本文只补技术实现方案，不复述 PRD 需求语义。FR 映射见 §6，AC 级输出合同见 §6.2。
> 架构基线：`../tools/ARCHITECTURE.md` **已存在，直接引用**（§1.5 逐条核对），本 CR 不修订。

## 0. 术语预检（写状态推进前）

进入数据模型 / 接口契约、存在歧义或别名风险的术语如下。**无语义冲突**，不要求需求负责人澄清；命名冲突只记录映射。

| PRD canonical | 代码别名 / 既有符号 | 边界场景 | 结论 |
|---|---|---|---|
| writeback **authority** | `resolveOperationalWorkspace` 的 `source: 'transaction-workspace'` | merging/writing-back 阶段 authority=txws；本 CR 新增窄解析器 `resolveWritebackAuthorityPath` | 回灌/预检**只**在 `source='transaction-workspace'` 且 cr.md=`unassigned` 时发生；窄解析器与完整解析器的差异见 §4.1 |
| **回灌**（refill） | 代码内 `versionRefill`（journal payload 键） | PRD 用「回灌」，代码用 refill 命名 | `journal.writeback.versionRefill`，见 §2.2 |
| 业务输入 `--target-version` | `input.targetVersion` / `business.value.targetVersion` | 守卫放行后回灌为规范化串（B-SDD-002 保留） | `input.targetVersion = guard.value`，后续 business/digest/manifest/generator 全消费规范化串 |
| 条目命中次数 | merge 侧 `locateBacklogEntry` 的 `hits.length` | FR-2.1「与既有 matchEntryBlock / merge 条目扫描同口径」 | 预检用同一行级正则 `^([ \t]*)- id:\s*["']?([^\s"']+)["']?\s*$` 在 `backlogLines()` 上计数，见 §4.3 |
| 「两侧须为真实版本且全等才放行」 | PRD FR-5 引用的**语义表述**（README 实际行文为「`--target-version` 与 `cr.md` 规范化全等才放行」，见 §4.7/§6.3 证据 7） | FR-5 要求改写 | 改为 FR-1 判定表（§2.1），README 行 22/行 76 + 守卫错误文案三处同步 |
| 规范化失败 | `normalizeTargetVersion` 返回 `{ok:false, reason}` | backlog 侧失败与 cr.md 侧失败共码 `WRITEBACK_VERSION_INVALID` | 以 `error.crMdReason` / `error.backlogReason` 区分来源（FR-6.2） |
| **authority 快照**（B-SDD-02 绑定锚点） | `guard.authority = { path, source }` | 守卫采样的版本事实源路径，必须与后续 `resolveOperationalWorkspace` 的 opWs 同源同路径 | `applyWritebackAtomic` 第 5.5 步校验，不一致 → 复用既有 `WRITEBACK_STATE_MISMATCH`（新增 throw 位）零写入硬失败（§4.4；不新增公开错误码——B-SDD-04） |
| **语义复核**（B-SDD-02 内容绑定） | `planVersionRefill` 第 ③ 步对同源重读的 cr.md 重新规范化 | guard 首次读取与 plan 二次读取之间允许字节漂移，但**版本值**必须仍为 `unassigned` 或已等于输入真实版本 | 已等于输入 → 幂等（cr.md 不成条目）；另一真实版本 → `WRITEBACK_VERSION_MISMATCH`；非法 → `WRITEBACK_VERSION_INVALID`（§4.3） |

CONTEXT.md 无上述条目；本 CR 不改写跨 CR 术语表（与 CR-2026-056 同先例：只在平台级敲定时扩展）。

---

## 1. 架构概览

### 1.1 目标仓与改动面

全部实施在 `../tools/` 仓。改动面最小收敛：

| 文件 | 本 CR 变化 | 责任边界 |
|---|---|---|
| `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | ① 新增 `resolveWritebackAuthorityPath`（窄只读路径解析）；② 重写 `guardWritebackVersion` 判定表（返回 authority 快照，B-SDD-02 绑定源）；③ 新增 `planVersionRefill`（同源绑定 + backlog 预检 + 账本行级编辑）+ 两个行级编辑纯函数；④ `applyWritebackAtomic` 插入 authority 快照校验、回灌计划、journal payload 持久化与 write-set 条目合成 | 版本事实与回灌的唯一实现；**不**反向依赖 crctl.mjs；`durable-tx.mjs` 零改动 |
| `skills/shared/crctl/scripts/test/writeback-tx.test.mjs` | 改写 AC-14 unassigned 拒绝向量；新增回灌正向/冲突/故障点/FR-3 分叉夹具测试（§6.2） | 集成回归；`merge-fixture.mjs` 增加 unassigned 参数化（§6.2 证据 6） |
| `skills/shared/crctl/scripts/test/crctl.test.mjs` | 新增 `guardWritebackVersion` / 窄解析器纯判定正负向量（§6.2） | 单测层；import 模式与既有 `normalizeTargetVersion` 测试一致 |
| `README.md` | 行 22/行 76 两处 writeback 版本守卫表述改为 FR-1 判定表语义 +「唯一更正入口」加 writeback 事务限定（FR-5/§4.7） | 人读入口；`git grep` 不再出现「规范化全等才放行」作为现行规则（AC-5） |

**明确不改**：`crctl.mjs`（dispatch、`fail()`、`ok()`、`runTxAsync`、writeback-apply flag 面零改动——新错误码经 `TxError.extra` 扁平透传，FR-6.2）、`durable-tx.mjs`（`applyWriteSet`/`recoverWriteSet`/`FAULT_POINTS` 零改动）、`lib/yaml-subset.mjs`、writeback 三个 generator 脚本、writeback Skill 调用形态（仍只传 `--target-version`）、`skills/shared/controlled-shell/rules.json`、`version-set` 子命令、状态机/gates 声明。

### 1.2 依赖方向（不变）

```text
crctl.mjs（cmdWritebackApply：flag 解析 + callback 注入 + fail/ok 信封）
  → lib/workspace-transactions.mjs
      applyWritebackAtomic
        ├─ guardWritebackVersion（本 CR 重写）→ resolveWritebackAuthorityPath（本 CR 新增；只读，永不抛 STATE/OPERATIONAL_WORKSPACE 错误；返回 authority 快照供 B-SDD-02 绑定）
        ├─ resolveOperationalWorkspace（既有，零改动；唯一会抛 STATE_MISMATCH 的 authority 断言点）
        ├─ authority 快照绑定（本 CR 新增：guard.authority 与 opWs 同源同路径校验，失败零写入）
        ├─ planVersionRefill（本 CR 新增：同源语义复核 + backlog 预检 + crMd/backlog 行级编辑；纯读+纯文本变换）
        └─ durable-tx.mjs：applyWriteSet / recoverWriteSet / faultPoint（既有，零改动）
```

不变量核对（`tools/ARCHITECTURE.md` §5）：**状态单一写者**（本 CR 不改 status 写入通道；baseline status 变迁仍走既有 `statusTransition` 合成）、**账本单一写入通道**（回灌发生在 writeback-apply 既有 journal/锁/write-set 事务内，不开新 CLI、不经任何 Skill/脚本手改）、**零第三方依赖**（只用 `node:*` 与既有 lib 函数）、**行尾与硬失败纪律**（§4.3）、**git 是权威**（回灌随 writeback commit 进 git，outbox 投影失败不逆转）、**人工审批无旁路**（本 CR 无审批节点改动）。

### 1.3 关键流程（回灌分支）

```text
crctl writeback-apply CR-2026-057 --stage baseline --spec-id X --target-version 0.30
  1) guardWritebackVersion：窄解析器定 authority（merging/writing-back → txws）并返回快照 {path, source}
     cr.md(txws)=unassigned + 输入=0.30 → 放行，refill=true，value=0.30（回灌到 input.targetVersion）
  2) traceability complete-replay 分支（既有，零改动；无 journal 时 no-op）
  3) resolveOperationalWorkspace → source=transaction-workspace 断言（既有）
  3.5) authority 快照绑定（B-SDD-02）：guard.authority.path === opWs.path 且 source=transaction-workspace，
       不一致 → 复用既有 WRITEBACK_STATE_MISMATCH 零写入硬失败（先于 candidate/journal/lock；
       不新增错误码——B-SDD-04）
  4) planVersionRefill（仅 refill=true）：同一 authority 上重读 cr.md 并语义复核（仍为 unassigned 才继续；
     已变为输入版本 → crMd 幂等 null；另一真实版本 → WRITEBACK_VERSION_MISMATCH）＋ backlog 预检（条目
     唯一性 + 前置值）＋ 生成 crMd 行级 after 文本（baseline：status+version 同一条；tasks/traceability：
     version only 单独条目）＋ backlog 行级 after 文本（仅前置值为 unassigned 时；已等值 → null，幂等）
  5) candidate / journal / verifyReleaseSubjects / validateBaselineAdvance（既有，零改动）
  6) journal.writeback.versionRefill 持久化（完整 { inputVersion, crMd, backlog }；首次 save('start') 前写入）
  7) entries = snapshot.files + statusTransition + versionRefill 条目（cr.md 全局恰好一条；
     恢复时 crMd/backlog 条目只从 payload 重建，不依赖瞬时 refillPlan——B-SDD-01）
     applyWriteSet（既有 recoverable write-set：中断后向前恢复到 after，不回滚 before）
  8) git add（staged 精确集合断言）→ 单 commit → lease push → origin confirmed → 投影/complete
```

冻结快照约束：回灌只产生 `cr.md` + `_backlog.yml` 两条路径的 write-set 条目；`verifyReleaseSubjects` 的 KB post-review 白名单本就含这两个路径（`ARCHITECTURE.md` §3 与 `workspace-transactions.mjs#verifyReleaseSubjects` 既有实现），prd/sdd/plan/tasks 不进条目、字节级不变（NFR-6）。

### 1.4 模块边界（本 CR 新增符号）

| 符号 | 位置 | 可见性 | 说明 |
|---|---|---|---|
| `resolveWritebackAuthorityPath(ctx, cr)` | workspace-transactions.mjs | export | 窄只读路径解析（§4.1）；返回 `{ path, source }`，永不抛 STATE/OPERATIONAL_WORKSPACE 类错误 |
| `guardWritebackVersion(ctx, cr, inputTargetRaw)` | 同上 | export（签名不变） | 返回扩为 `{ ok, value, refill, authority: { path, source } }`；错误码判定表 §2.1；authority 快照是 B-SDD-02 绑定唯一事实源 |
| `planVersionRefill({ txws, authority, cr, stage, version })` | 同上 | 模块私有 | 同源绑定（⓪）+ backlog 预检（①）+ cr.md 语义复核（③）+ 行级编辑；产物 `{ inputVersion, crMd: entry/null, backlog: entry/null, crMdBase: {text, sha256}/null }` |
| `applyTargetVersionToCrMd(text, version)` | 同上 | 模块私有 | frontmatter 内 `^target-version:` 行级替换（幂等口径 + 硬失败纪律，§4.3） |
| `editBacklogEntryTargetVersion(text, cr, version)` | 同上 | 模块私有 | `_backlog.yml` 条目块内 `target-version` 行级替换（B-CODE-001 区间替换口径） |
| `journal.writeback.versionRefill` | journal payload | 持久化字段 | `{ inputVersion, crMd: {path,beforeSha256,afterSha256,afterText} \| null, backlog: {path,beforeSha256,afterSha256,afterText} \| null }`；crMd 仅 tasks/traceability 非 null；baseline 的 cr.md 侧并入 `statusTransition.afterText`（§2.2/§4.5） |

### 1.5 ARCHITECTURE.md 对照

已存在（`../tools/ARCHITECTURE.md`，取证对象 = `resources[repo=tools].worktreePath`：branch=`requirement/CR-2026-058`（本 CR 派生 worktree，非 trunk `custom/main`），HEAD=`2bb66294db30b116e0d53aea48990611017c75d6`（即 CR-2026-057 merge 提交，本 CR 分支自该点派生）；§6.3 证据已在该 worktree HEAD 重核），只读引用。本 CR 属于「单个 CR 的功能改动」，按 §8 维护规则**不需要修订**。逐条核对：§5.1 状态单一写者 ✓（回灌不改 status 通道）、§5.2 账本单一写入通道 ✓（回灌在 writeback-apply 事务内，非新通道）、§5.3 零第三方依赖 ✓、§5.4 行尾硬失败 ✓（§4.3）、§5.6 git 是权威 ✓（§4.6）、§5.7 人工审批无旁路 ✓（无关）；§6 Negative Space 无冲突（不新开脚本库、不新事务框架、不引 YAML 库）。

---

## 2. 数据模型

### 2.1 guardWritebackVersion 判定表（FR-1）

规范化仍用既有 `normalizeTargetVersion`（值域/禁止同义值/`v`/`V` 前缀剥离不变）。`a` = authority cr.md 规范化值（路径来自 §4.1 窄解析器），`b` = 输入规范化值：

| a（cr.md） | b（输入） | 结果 | 错误码 |
|---|---|---|---|
| `unassigned` | 真实版本 | **放行**：`{ ok, value: b, refill: true, authority }`（仅当 authority.source=transaction-workspace；窄解析器回退到 cr-worktree 时 refill=false，见下行） | 无 |
| `unassigned`（authority 为 cr-worktree 回退） | 真实版本 | 放行（refill=false）：后续落到 `WRITEBACK_STATE_MISMATCH`——opWs=cr-worktree 为既有 throw 位；opWs=txws 而快照=worktree 为本 CR 新增 throw 位（§4.4 第 5.5 步）。两处同码、均零写入 | 无（守卫内） |
| 真实 A | 真实 A | 放行：`{ ok, value: a, refill: false }`（今日行为） | 无 |
| 真实 A | 真实 B（≠） | 拒绝 | `WRITEBACK_VERSION_MISMATCH`（extra 既有 `cr`/`crMd`/`input`） |
| `unassigned` | `unassigned` | 拒绝 | `WRITEBACK_VERSION_UNASSIGNED` |
| 真实 | `unassigned` | 拒绝 | `WRITEBACK_VERSION_UNASSIGNED` |
| 任一侧规范化失败 | * | 拒绝 | `WRITEBACK_VERSION_INVALID`（extra 既有 `cr`/`input`/`inputReason`/`crMdReason`） |

- 错误优先级不变：版本错误（MISMATCH / INVALID / 两侧或输入侧 unassigned）> `WRITEBACK_STATE_MISMATCH`（既有 throw 位 + 本 CR 新增的 authority 快照绑定 throw 位，§4.4 第 5.5 步，零写入）> 其它。`unassigned`+真实**不再是版本错误**——非 txws authority 夹具（`status=drafting`/`code-approved`）落到既有 `WRITEBACK_STATE_MISMATCH`（零写入），回灌不发生。
- `WRITEBACK_VERSION_UNASSIGNED` 文案按 FR-5 改写：`writeback 版本守卫：两侧或输入侧为 unassigned 一律拒绝（cr.md=${a}，输入=${b}）；仅 cr.md=unassigned 且输入为真实版本时放行并回灌账本`。
- 放行后 `input.targetVersion = guard.value`（规范化串，B-SDD-002 保留），`canonicalWritebackBusinessInput` 的 `startsWith('v')` 剥离降为防御性 no-op。

### 2.2 journal.writeback.versionRefill（新持久化字段，envelope v1 不变）

写入 `{root}/.crctl/transactions/writeback/{cr}-{stage}/{txId}/journal.json` 的 `writeback` payload（`loadOrCreateJournal`/`saveJournal` 的 envelope 校验只要求 `writeback` 键非空、不枚举其内部字段——**durable-tx.mjs 零改动**，见既有 `assertEnvelope`/`saveJournal` 事实，§6.3 证据 2）：

```text
versionRefill = {
  inputVersion: "0.30",                    # 规范化真实版本（= guard.value）
  crMd: {                                  # cr.md write-set 条目：tasks/traceability 非 null；baseline null（并入 statusTransition）
    path: "change-requests/{CR-ID}/cr.md",
    beforeSha256: "<64hex>", afterSha256: "<64hex>", afterText: "<LF 全文>",
  } | null,
  backlog: {                               # 仅前置值=unassigned 时非 null
    path: "change-requests/_backlog.yml",
    beforeSha256: "<64hex>", afterSha256: "<64hex>", afterText: "<LF 全文>",
  } | null,
}
```

- **baseline 的 cr.md 侧不单独成条目**：`statusTransition.afterText` 已是「status=writing-back + target-version=真实版本」合成文本（§4.5），`crMd=null`；`inputVersion` 供合成与恢复重放。
- **tasks/traceability 的 cr.md 侧**：无 status 变迁（`statusTransition=null`），cr.md 的 write-set 条目由 `crMd` **完整持久化**（path/before/after 哈希 + after 文本随 payload 落盘，与 `statusTransition` 同口径）——**B-SDD-01**：`writeback-after-apply` 中断后重试时 guard 已读到真实版本（`refill=false`、`refillPlan=null`），entries 的 cr.md 条目**只从 `payload.versionRefill.crMd` 重建**，不依赖瞬时计划；`payload.files` 投影因此稳定包含 cr.md。
- 持久化时点：`created=true` 时写入完整 payload（含 crMd 与 backlog 条目全文），随 `save('start')` 落盘。**`payload.versionRefill` 一旦落盘即冻结：任何恢复路径（`created=false`）都不得重算、不得覆写**（B-SDD-01）。覆写的缺陷：write-set 在 rename 间中断时可能 backlog 已是 after、cr.md 仍为 `unassigned`，重算会把 backlog 条目降为 null，随后 `recoverWriteSet` 按原 manifest 补齐文件，却使 commit/`files` 丢 backlog 或触发 staged-set 不一致。恢复一律「保留首次 payload + 按 manifest 向前恢复」，现场用既有 write-set manifest/phase 区分（§4.4 第 9 步）：
  - manifest 缺失（尚未 apply：`writeback-after-journal-create` 中断，文件未动）→ entries 从 payload 持久化条目重建，`applyWriteSet` 首轮落盘；第 7 步重算的 plan 仅作纯读 fail-fast、不落入 payload（首次预检结果已随 save('start') 冻结；第三方改动由 applyWriteSet 的 before 哈希预检以 `TX_RECOVERY_CONFLICT` 拦截，零写入）；
  - manifest state=`prepared`（部分 apply：rename 间中断）→ `recoverWriteSet` 按 manifest 补齐 after；entries 从 payload 重建（与 manifest 同路径同哈希），`applyWriteSet` 全 skip，随后补 commit；
  - manifest state=`complete`（apply 已全量落盘、commit 前）→ entries 从 payload 重建，`applyWriteSet` 全 skip，补 `git add`+commit；
  - guard 已 `refill=false`（cr.md 已是真实版本）→ 校验 `payload.versionRefill.inputVersion === guard.value`，不一致 → `TX_INPUT_CONFLICT`（既有码，恢复协议硬阻断）；entries 只用 payload 持久化条目，不回算 after；
  - 防御：guard 仍 `refill=true` 但 payload **无** versionRefill——本 CR 语义下不可恢复（只可能来自部署前旧守卫创建的在途 journal，其 write-set 从未含回灌条目），`TX_INPUT_CONFLICT` 硬阻断、零写入，人工处置。
- 幂等语义：journal 完成后同参重跑，guard 因 cr.md 已是真实版本 → `refill=false`，不产生新版本行 diff（AC-2.1/AC-6.2）。

### 2.3 backlog 预检状态模型（FR-2.1）

仅在 `refill=true` 且 `source='transaction-workspace'` 时执行（applyWritebackAtomic 已断言 txws，见 §4.4）。读同一 authority 的 `change-requests/_backlog.yml`：

| 命中次数（`- id: {CR}` 行级正则计数） | 结果 | 错误码（extra） |
|---|---|---|
| 0 | 拒绝 | `ENTRY_NOT_IN_BACKLOG`（复用既有码；`{ cr }`） |
| >1 | 拒绝 | `WRITEBACK_BACKLOG_ENTRY_DUPLICATE`（本 CR 新增；`{ cr, count }`） |
| 1 | 读条目 `target-version` 经 `normalizeTargetVersion`（allowUnassigned=true）→ 下表 | — |

| backlog 规范化值 | 结果 | 错误码（extra） |
|---|---|---|
| `unassigned` | 允许回灌：write-set 改写该字段为输入真实版本 | 无 |
| 与输入全等真实版本 | 允许：backlog 条目 = null（幂等）；cr.md 仍 unassigned 则继续回灌 cr.md | 无 |
| 另一真实版本 | 拒绝 | `WRITEBACK_BACKLOG_VERSION_MISMATCH`（本 CR 新增；`{ cr, crMd: 'unassigned', backlog, input }`） |
| 规范化失败（缺字段/非法/同义值） | 拒绝 | `WRITEBACK_VERSION_INVALID`（共码；extra 在既有 `cr`/`input`/`inputReason`/`crMdReason` 基础上并列 `backlogReason`） |

- 优先级：FR-1 版本守卫（cr.md vs 输入）> 本预检 > 后续非 `WRITEBACK_STATE_MISMATCH` 错误；预检失败**先于** candidate 生成与 journal 创建，零 candidate/journal/lock/commit 痕迹（§4.4 时序）。
- 预检结果只在 fresh 运行（`created=true`）时随 `save('start')` 冻结进 payload；found 重试上第 7 步的重算仅作纯读 fail-fast（零写入），不落入 payload、不覆写 `payload.versionRefill`（§2.2 冻结规则）；账本在恢复期的漂移由 `applyWriteSet` 的 before/after 哈希分类与第三值 `TX_RECOVERY_CONFLICT` 拦截（零写入）。
- 非回灌分支（两侧真实且全等）**不**因 backlog 另值额外拒绝——「账本已分裂但两侧真实」不在本 CR 范围（PRD FR-2.1）。

### 2.4 故障边界状态模型（FR-2.2，沿用既有 writeback 事务）

回灌条目与 stage 业务文件进**同一个** `applyWriteSet` `entries[]`。语义对齐既有 recoverable write-set：中断后**向前恢复到计划 after**，不做 command-ledger 式「commit 前整组滚回 before」。

| 边界 | 注入点（既有） | 中断现场 | 同参重试预期 | 重试后不变量 |
|---|---|---|---|---|
| apply 后、commit 前 | `writeback-after-apply` | write-set 已把 after 映像落 txws（含两账本版本行 + 业务文件 + baseline cr.md 合成 afterText）；HEAD 未动；journal 未 `committed` | `recoverWriteSet`：manifest `complete` → after no-op；`prepared`（rename 中断）→ redo 剩余条目。再补 `git add`+commit。**禁止**先把账本滚回 `unassigned` | 恰好一个 writeback commit，同时含两账本目标版本与本 stage 业务文件；冻结产物字节级不变 |
| commit 后、push 前 | `writeback-after-commit` | 本地 commit 存在；journal `committed=true`、`pushed=false` | 保留 commit 与 journal；只 lease push + complete，不新建 commit | origin 上该 stage 恰好一个 `writeback {stage}` commit；两账本版本行在其内 |
| push 后、complete 前 | `writeback-after-push` | origin 已确认；journal `pushed=true` | 保留已发布 commit；只补投影 / `save('complete')`；不新增 commit、不改账本 | `phase=complete`；`commit` 与中断前相同 |

半成品禁令唯一口径：两账本与业务文件同一次 `entries[]` → 不存在「cr.md 已是真实版本而业务文件未进同一 after/commit」状态（write-set 原子性保证，非事后补偿写）。

---

## 3. 接口契约

本 CR 无 HTTP API（不新增 REST 契约）。契约面 = `crctl writeback-apply` 的回灌分支 I/O（FR-6）+ 新增/复用错误码的 stderr 信封。命令面、flag 面、`ok()`/`fail()`/`runTxAsync` 形态**零改动**。

### 3.1 成功信封（exit 0，FR-6.1）

| 字段 | 回灌首次成功（该 journal 第一次 complete） | 同参幂等重跑 |
|---|---|---|
| `op` | `"writeback-apply"` | 同左 |
| `phase` | **必须** `"complete"`（禁止 `"committed"`/`"pushed"` 等别名） | `"complete"` |
| `changed` | `true` | `false` |
| `status` | baseline：`"writing-back"`；tasks/traceability：authority 既有 status | 与首次 complete 相同 |
| `commit` | 40 位 hex；tree 含两账本目标版本 + 本 stage 业务文件 | 与首次相同 |
| `files` | 数组**必须同时包含** `change-requests/{CR-ID}/cr.md` 与 `change-requests/_backlog.yml`（另含 stage 既有业务路径）。来源 = `payload.files`（entries 全量投影，§4.4），禁止「业务文件已含回灌」的隐含语义替代 | 与 journal 记录的 write-set 路径相同（仍含两账本路径） |
| `recoverCommand` | 同业务命令，`--target-version` 为规范化真实版本（既有生成逻辑，`business.value.targetVersion` 已是规范化串） | 同左 |
| `txId`/`warnings` | 既有契约；回灌成功且无投影失败 `warnings=[]` | 保持既有 |

### 3.2 失败信封（exit 1，FR-6.2）

既有 `fail(code, message, extra)` → stderr 唯一 JSON `{"error":{"code","message",...extra}}`，**无**独立 `error.details`（`TxError.extra` 扁平并入，`runTxAsync` 既有行为）。stdout 无成功 JSON。

| `error.code` | 并列字段（扁平） |
|---|---|
| `WRITEBACK_VERSION_UNASSIGNED` / `WRITEBACK_VERSION_MISMATCH` / `WRITEBACK_VERSION_INVALID` | 保持既有 `cr`/`crMd`/`input`/`inputReason`/`crMdReason`；INVALID 来自 backlog 时并列 `backlogReason` |
| `WRITEBACK_BACKLOG_VERSION_MISMATCH` | `cr`、`crMd`、`backlog`、`input` |
| `WRITEBACK_BACKLOG_ENTRY_DUPLICATE` | `cr`、`count` |
| `ENTRY_NOT_IN_BACKLOG` | `cr` |
| 既有其它 writeback/Tx 码 | 保持既有 extra，本 CR 不改；其中 `WRITEBACK_STATE_MISMATCH` 新增一个 throw 位（authority 快照绑定，B-SDD-02），extra 保持既有 `{cr, phase}` 形状，guard 快照与 opWs 的路径证据进 `message` |

---

## 4. 关键算法与流程

### 4.1 resolveWritebackAuthorityPath（FR-3，窄只读路径解析）

```text
resolveWritebackAuthorityPath(ctx, cr):
  crWorktree = crWorktreePath(ctx, cr)              # 既有：repositories graph 纯路径反解
  status = readCrMdStatus(crWorktree, cr)           # 既有：单文件只读，缺失 → null
  if status ∈ POST_FINALIZE_STATUSES:               # merging/writing-back/archived
      txws = txWorkspacePath(ctx, cr)               # 既有：.crctl/transaction-workspaces/{cr}
      if txws 存在 && readCrMdStatus(txws, cr) ∈ POST_FINALIZE_STATUSES:
          return { path: txws, source: 'transaction-workspace' }
      return { path: crWorktree, source: 'cr-worktree' }   # 回退：仅版本比较，回灌禁用（§4.4 断言兜底）
  if status != null:
      ms = try { mergeStatus(ctx, cr) } catch { { phase: 'none' } }   # journal 损坏按无证据处理
      if ms.phase == 'complete' && ms.operationalWorkspace
         && readCrMdStatus(ms.operationalWorkspace, cr) ∈ POST_FINALIZE_STATUSES:
          return { path: ms.operationalWorkspace, source: 'transaction-workspace' }
  return { path: crWorktree, source: 'cr-worktree' }
```

与 `resolveOperationalWorkspace` 的**差异（PRD FR-3 要求 SDD 写明）**：

| 维度 | `resolveOperationalWorkspace`（既有，唯一 authority 断言） | `resolveWritebackAuthorityPath`（本 CR 新增） |
|---|---|---|
| 抛错 | 抛 `CR_WORKTREE_STATUS_MISSING` / `OPERATIONAL_WORKSPACE_MISSING` / `OPERATIONAL_WORKSPACE_INCONSISTENT` | **永不抛**；任何证据不足回退 `cr-worktree` 路径 |
| 用途 | applyWritebackAtomic 的 authority 断言（STATE_MISMATCH 唯一来源） | **仅** guard 版本比较的路径定位 |
| 不一致处理 | txws 状态不自洽 → 硬失败 | 视作「无 txws 证据」→ 用 worktree 值比较 |
| merge journal | 只读 `mergeStatus` | 同源，但包 try/catch（损坏按无证据） |

设计理由：守卫必须在 STATE_MISMATCH 之前返回版本错误（FR-1 优先级）。若守卫调用完整解析器，`OPERATIONAL_WORKSPACE_*` 会抢先于 `WRITEBACK_VERSION_*`——正是 CR-2026-057 B-SDD-001 划定的禁止面。窄解析器只回答「若 writeback 继续，版本事实源是哪」，不做 authority 合法性断言；真正的 authority 断言仍由后续 `resolveOperationalWorkspace` 完成，回退场景（txws 缺失等）随后落到既有 STATE_MISMATCH/OPERATIONAL_WORKSPACE 错误，且因 `refill` 只在 txws 断言通过后才消费，**此时不得回灌**天然成立。

### 4.2 guardWritebackVersion（FR-1 重写）

```text
guardWritebackVersion(ctx, cr, inputTargetRaw):
  b = normalizeTargetVersion(inputTargetRaw)
  auth = resolveWritebackAuthorityPath(ctx, cr)     # { path, source }；窄只读，永不抛 STATE/OPERATIONAL 错误
  r = readCrMdTargetVersion(auth.path, cr)          # 既有行级读取；先 \r\n→\n
  a = r.ok ? normalizeTargetVersion(r.raw) : { ok: false, reason: 'missing' }
  if !a.ok || !b.ok → throw WRITEBACK_VERSION_INVALID（extra: cr/input/inputReason/crMdReason）
  if a.value == 'unassigned' && b.value != 'unassigned' && auth.source == 'transaction-workspace'
      → return { ok: true, value: b.value, refill: true, authority: { path: auth.path, source: auth.source } }
  if a.value == 'unassigned' && b.value != 'unassigned'   # source=cr-worktree（窄解析器回退）
      → return { ok: true, value: b.value, refill: false, authority: { path: auth.path, source: auth.source } }
          # 回灌禁用；后续落到既有 WRITEBACK_STATE_MISMATCH（opWs=cr-worktree）
          # 或本 CR 新增的 WRITEBACK_STATE_MISMATCH throw 位（opWs=txws 而快照=worktree，§4.4 第 5.5 步），两处同码均零写入
  if a.value == 'unassigned' || b.value == 'unassigned'
      → throw WRITEBACK_VERSION_UNASSIGNED（FR-5 新文案；extra: cr/crMd/input）
  if a.value != b.value → throw WRITEBACK_VERSION_MISMATCH（extra 既有）
  return { ok: true, value: a.value, refill: false, authority: { path: auth.path, source: auth.source } }
```

纯判定 + 一次只读文件读取；常数时间、零网络（NFR-4）。无 journal/candidate/lock 痕迹（在 `loadExistingJournal`/`prepareWritebackCandidate`/`acquireLock` 之前，§4.4）。返回的 `authority` 快照是 **B-SDD-02 绑定唯一事实源**：后续 `applyWritebackAtomic` 第 5.5 步校验它与 opWs 同源同路径，`planVersionRefill` 以它为唯一回灌位置并在该位置上做语义复核。

### 4.3 planVersionRefill（FR-2/FR-2.1 唯一实现）

```text
planVersionRefill({ txws, authority, cr, stage, version }):
  # ⓪ 同源绑定（B-SDD-02）：调用方已在 §4.4 第 5.5 步校验，此处防御性重申
  if authority.source !== 'transaction-workspace' || authority.path !== txws
      → throw WRITEBACK_STATE_MISMATCH（复用既有码；message 载 authority-mismatch 与两侧路径；正常不可达，防未来重构漂移）
  # ① backlog 预检（FR-2.1；先于任何 write-set/journal/candidate 副作用）
  raw = read(txws/change-requests/_backlog.yml)      # 不可读 → ENTRY_NOT_IN_BACKLOG（{cr}）
  norm = raw.replaceAll('\r\n', '\n')
  lines = backlogLines(norm)                          # 既有行级切分（\r?\n 口径）
  hits = lines.filter(l => /^([ \t]*)- id:\s*["']?([^\s"']+)["']?\s*$/.test(l.text)
                            && l.text.match(...)[2] === cr)
  hits.length == 0  → throw ENTRY_NOT_IN_BACKLOG（{cr}）
  hits.length > 1   → throw WRITEBACK_BACKLOG_ENTRY_DUPLICATE（{cr, count}）
  blk = matchEntryBlock(norm, cr)                     # 既有 yaml-subset 函数（含 start/end）
  blk == null → throw ENTRY_NOT_IN_BACKLOG（防御性；正常不可达）
  line = blk.text.split('\n').find(l => /^[ \t]*target-version:/.test(l))
  line == null → throw WRITEBACK_VERSION_INVALID（{cr, backlogReason: 'missing'}）
  bv = normalizeTargetVersion(line 解析出的 raw)       # allowUnassigned=true
  !bv.ok → throw WRITEBACK_VERSION_INVALID（{cr, backlogReason: bv.reason}）
  backlogEntry = null
  if bv.value == 'unassigned':
      after = editBacklogEntryTargetVersion(norm, blk, version)   # ② 区间定点替换
      backlogEntry = { path: 'change-requests/_backlog.yml',
                       beforeSha256: sha256(raw), afterSha256: sha256(after), afterText: after }
  else if bv.value == version: backlogEntry = null     # 幂等：条目不改写
  else → throw WRITEBACK_BACKLOG_VERSION_MISMATCH（{cr, crMd: 'unassigned', backlog: bv.value, input: version}）
  # ③ cr.md 同源重读 + 语义复核（B-SDD-02：绑定 guard 首次采样与本次读取）
  rel = `change-requests/${cr}/cr.md`
  beforeRaw = read(txws/rel)                           # 与 guard 同一 authority 路径（⓪ 已断言）
  beforeRaw == null → throw WRITEBACK_VERSION_INVALID（{crMdReason:'missing'}）
  before = beforeRaw.replaceAll('\r\n', '\n')
  rv = 行级提取 before 的 target-version → normalizeTargetVersion   # 与 readCrMdTargetVersion 同口径
  !rv.ok → throw WRITEBACK_VERSION_INVALID（{crMdReason: rv.reason}）
  crMdEntry = null; crMdBase = null
  if rv.value == version:
      # 两次读取间漂移但已到达目标版本（幂等）：cr.md 不再成条目；baseline 仍记录复核文本供 §4.5 合成
      if stage != 'baseline' → crMdEntry = null
      else → crMdBase = { text: before, sha256: sha256(beforeRaw) }
  else if rv.value != 'unassigned':
      # guard 首次读为 unassigned、本次已是另一真实版本：版本事实在两次采样间漂移，拒绝，零写入
      throw WRITEBACK_VERSION_MISMATCH（{cr, crMd: rv.value, input: version}）
  else:
      # 语义复核通过：值仍为 unassigned（字节漂移不影响版本事实，行级编辑在复核文本上进行；
      # beforeSha256 锚定本次复核文本，applyWriteSet 预检会以 hash 分类发现此后任何漂移——末段 CAS）
      if stage == 'baseline':
          crMdBase = { text: before, sha256: sha256(beforeRaw) }
          crMdEntry = null    # cr.md 侧并入 statusTransition（§4.5），不单独成条目
      else:
          after = applyTargetVersionToCrMd(before, version)
          crMdEntry = { path: rel, beforeSha256: sha256(beforeRaw), afterSha256: sha256(after), afterText: after }
  return { inputVersion: version, crMd: crMdEntry, backlog: backlogEntry, crMdBase }
```

**行级编辑硬失败纪律（NFR-3/纪律 #1）**：

- `applyTargetVersionToCrMd(text, version)`：先 `\r\n→\n`；`matchFrontmatter` 失败 → 抛 `WRITEBACK_VERSION_INVALID`（`crMdReason:'missing'`）；frontmatter 内无 `^target-version:` 行 → 同码硬失败；命中行 `replace(/^(target-version:).*$/, '$1 ' + version)` 后，用 `norm.replace(fm.match, '---\n' + body + '\n---')` 重建，**必须校验替换结果**：替换前后文本不同 → 正常返回；相同（该行已等于目标版本）→ 幂等放行返回原文（AC-2.1 幂等语义，非错误）；禁止「匹配不到仍静默返回原文」的降级路径。
- `editBacklogEntryTargetVersion(text, cr, version)`：**B-CODE-001 口径**（与 crctl.mjs#editBacklogTargetVersionLine 同构，TxError 风格落 lib）：`span = norm.slice(blk.start, blk.end)` 单行定点替换 `^([ \t]*)target-version:.*$` → `${ind}target-version: ${version}`（版本恒为规范化真实版本，无需 yamlScalar 引号）；`replaced === spanText` → 硬失败；返回 `norm.slice(0, blk.start) + replaced + norm.slice(blk.end)`——**禁止**用 `block.text` split/join 重建（块尾换行不在 `block.text` 内，重建会破坏 YAML 分隔，CR-2026-057 B-CODE-001 先例）。
- 版本写入值恒为规范化串（`guard.value`），不含 `"`/空白，行级替换无转义风险。
- 语义复核（③）与预检（①）同为纯读+纯文本变换：无任何文件写入、无 journal/lock/candidate 副作用；未通过复核/预检的失败路径与 FR-2.1 六项零观察点一致（§4.4 时序）。

### 4.4 applyWritebackAtomic 插入点与时序（FR-2 原子性）

在既有函数上的**最小插入**（粗体为本 CR 新增；其余行零改动）：

```text
1   const versionGuard = guardWritebackVersion(ctx, cr, input.targetVersion)
2   input.targetVersion = versionGuard.value                 # B-SDD-002 保留
3   [traceability complete-replay 分支——既有，零改动]
4   const opWs = resolveOperationalWorkspace(ctx, cr)        # 既有；非 txws → WRITEBACK_STATE_MISMATCH
5   const txws = opWs.path
5.5 **if (versionGuard.authority.source !== 'transaction-workspace' || versionGuard.authority.path !== opWs.path)
       throw WRITEBACK_STATE_MISMATCH（复用既有码；extra 保持既有 {cr, phase} 形状，guardSource/guardPath/opPath
       证据进 message——不新增公开错误码，B-SDD-04）
       # B-SDD-02：守卫采样的版本权威必须与将被写入的 operational workspace 同源同路径；
       # 该检查先于 business/candidate/journal/lock，失败零写入**
6   **let refillPlan = null**
7   **if (versionGuard.refill) refillPlan = planVersionRefill({ txws, authority: versionGuard.authority, cr, stage, version: versionGuard.value })**
      # ← 同源绑定/预检/语义复核在 candidate 生成（prepareWritebackCandidate）与 journal 创建之前，FR-2.1 时序成立；
      #    found 重试（journal 已存在）时本步重算的 refillPlan 仅作纯读预检（零写入 fail-fast），不落入 payload——
      #    payload.versionRefill 一旦落盘即冻结（B-SDD-01，见第 9 步）
8   [business / resolveWritebackCandidate / loadExistingJournal / prepareWritebackCandidate——既有，零改动]
9   [found 分支] **payload 已含 versionRefill 时：保留首次 payload，禁止重算/覆写（B-SDD-01 冻结）。以既有
       write-set manifest/phase 区分现场并向前恢复（若 payload.statusTransition 已存在则保留其持久化文本，不重算）：
       a) manifest 缺失（尚未 apply：writeback-after-journal-create 中断，文件未动）→ entries 从 payload
          持久化条目重建，applyWriteSet 首轮落盘；第 7 步重算只作纯读 fail-fast、不覆写 payload（首次预检
          结果已随 save('start') 冻结；第三方改动由 applyWriteSet before 哈希预检以 TX_RECOVERY_CONFLICT
          拦截，零写入）；
       b) manifest state=prepared（部分 apply：rename 间中断，可能 backlog 已 after、cr.md 仍 unassigned）→
          recoverWriteSet 按 manifest 补齐 after；entries 从 payload 重建（与 manifest 同路径同哈希），
          applyWriteSet 全 skip；两账本路径保留在 entries/git add/files 内（不因本轮重算把 backlog 条目
          降为 null 而丢失，commit/files 不丢 backlog、不触发 staged-set 不一致）；
       c) manifest state=complete（apply 已全量落盘、commit 前）→ entries 从 payload 重建，applyWriteSet
          全 skip，补 git add+commit；
       d) 本轮 versionGuard.refill === false：另校验 payload.versionRefill.inputVersion === versionGuard.value，
          不一致 → TX_INPUT_CONFLICT（既有码，恢复协议硬阻断）；entries 只用 payload 持久化条目，不回算 after；
       e) 防御：guard 仍 refill=true 但 payload 无 versionRefill（只可能来自部署前旧守卫创建的在途 journal，
          其 write-set 从未含回灌条目）→ TX_INPUT_CONFLICT 硬阻断、零写入，人工处置**
10  [baseline advanceCandidate / verifyReleaseSubjects / origin 前置——既有，零改动]
11  loadOrCreateJournal（created=true 时）：
      **if (refillPlan) payload.versionRefill = { inputVersion: refillPlan.inputVersion,
          crMd: refillPlan.crMd && { path, beforeSha256, afterSha256, afterText },
          backlog: refillPlan.backlog && { path, beforeSha256, afterSha256, afterText } }
      await save('start')**                                  # 与既有 save('start') 合并，不新增 phase；
                                                             # created=false（found 重试）不触碰 payload.versionRefill（冻结，第 9 步）
12  [statusTransition 构建——既有；合成版本行见 §4.5]
13  entries = snapshot.files.map(...)                        # 既有
    if (payload.statusTransition) entries.push(...)          # 既有
    **if (payload.versionRefill?.backlog) entries.push({ path: backlog.path, beforeSha256: backlog.beforeSha256,
                                                              afterSha256: backlog.afterSha256, content: backlog.afterText })
    if (payload.versionRefill?.crMd) entries.push({ path: crMd.path, beforeSha256: crMd.beforeSha256,
                                                              afterSha256: crMd.afterSha256, content: crMd.afterText })**   # tasks/traceability；只依赖 payload，不依赖瞬时 refillPlan（B-SDD-01）
14  applyWriteSet → faultPoint('writeback-after-apply') → git add → staged 精确集合断言 → commit
    → faultPoint('writeback-after-commit') → push → faultPoint('writeback-after-push') → 投影 → complete
```

要点：

- **cr.md 全局恰好一条 write-set 记录**：baseline = `statusTransition` 条目（afterText 已含版本行）；tasks/traceability = `payload.versionRefill.crMd` 条目（无 status 变迁，`statusTransition=null`）。二者互斥，不存在两写。
- **恢复一致性（B-SDD-01）**：`payload.files = entries.map(...)`（既有第 13 步后逻辑零改动）→ `files` 自动含两账本路径（FR-6.1 落点）。`payload.versionRefill` 一旦随 `save('start')` 落盘即冻结，found 重试一律保留首次 payload 并按 manifest/phase 向前恢复：尚未 apply → `applyWriteSet` 首轮落盘；部分 apply（rename 间）→ `recoverWriteSet` 按 manifest 补齐，entries 从 payload 重建后全 skip；已 apply 未 commit → 补 commit。tasks/traceability 的 `writeback-after-apply` 中断后重试：guard 读 txws cr.md 已是真实版本 → `refill=false` → entries 的 cr.md 条目**只从 `payload.versionRefill.crMd`（持久化）重建**，backlog 条目从 `payload.versionRefill.backlog` 重建；`applyWriteSet` 按当前 hash 分类（=after → skip；=before → redo；第三值 → TX_RECOVERY_CONFLICT 零写入）→ 向前恢复成立，无需回滚账本；重试后的 commit 与 files 与中断前语义一致（两账本 + 本 stage 业务文件同 commit，files 含 cr.md）。
- **`writeback-after-journal-create` 中断**：文件未动、manifest 缺失；guard 仍 `refill=true`。重试保留首次 payload（versionRefill 已随 save('start') 落盘），entries 从 payload 重建，`applyWriteSet` 首轮落盘——第 7 步重算不落入 payload（首次预检已保证前置值；第三方改动由 applyWriteSet before 哈希预检以 TX_RECOVERY_CONFLICT 拦截，零写入）。
- **错误优先级**：预检抛出的 `ENTRY_NOT_IN_BACKLOG` / `WRITEBACK_BACKLOG_*` / INVALID(backlog) 均发生在 `resolveOperationalWorkspace` **之后**、candidate/journal 之前——非 txws 夹具先得 `WRITEBACK_STATE_MISMATCH`（FR-1 允许的落点），预检不会在错误 authority 上执行。authority 快照绑定（第 5.5 步，复用既有 `WRITEBACK_STATE_MISMATCH` 的新 throw 位）同样先于 candidate/journal，零写入。

### 4.5 baseline cr.md 单条目合成（status + target-version 同一条 afterText）

`applyWritebackAtomic` 既有 statusTransition 构建处，afterText 合成改为：

```text
let afterText, beforeSha256
if (payload.versionRefill && refillPlan) {                    # 回灌分支（fresh 运行；或 journal-create 中断后
    # statusTransition 尚未持久化的 baseline 重试——两者 guard refill=true 且本块未被持久化跳过）
    # 底本 = plan 语义复核过的文本（B-SDD-02 绑定：复核文本即 applyWriteSet 的 before 锚点）
    afterText = crMdStatusText(refillPlan.crMdBase.text, 'writing-back', { at: journal.createdAt })
    afterText = applyTargetVersionToCrMd(afterText, payload.versionRefill.inputVersion)
    beforeSha256 = refillPlan.crMdBase.sha256
} else {                                                      # 非回灌分支：与今日行为完全一致
    afterText = crMdStatusText(advanceCandidate.beforeText, 'writing-back', { at: journal.createdAt })
    beforeSha256 = advanceCandidate.beforeSha256
}
payload.statusTransition = { from: 'merging', to: 'writing-back', ..., beforeSha256, afterSha256: sha256(afterText), afterText }
```

理由：`crMdStatusText` 是既有纯函数（LF 输出、只改 status/updated 行），版本行替换在其输出上做一次行级替换即可；其返回 null（无 frontmatter）时既有 `WRITEBACK_STATUS_INVALID` 硬失败**保留**（回灌分支经 §4.3 ③ 语义复核已确保 frontmatter 存在，正常不可达，防御保留）；`advanceCandidate` 回调仍被执行（其 gate 检查副作用保留，`validateBaselineAdvance` 零改动），但回灌分支的 before/after 锚点改以 plan 语义复核文本为准——**若 `advanceCandidate.beforeText` 与复核文本不一致（两次读取间漂移），`applyWriteSet` 预检按 hash 分类必得 `TX_RECOVERY_CONFLICT`（第三值），零账本写入，不存在对漂移后真实版本的覆盖**。恢复时（`payload.statusTransition` 已持久化）零重算，`writeback-after-apply` 重试时该条目按 after 分类 skip。

### 4.6 故障边界实现落点（FR-2.2）

不新增 fault-point（`FAULT_POINTS` 全仓唯一登记表零改动）；回灌条目与业务文件同批 `entries[]` 天然落入既有三点语义：

- `writeback-after-apply`：第 13–14 步之间，write-set 已含两账本 + 业务文件 after 映像；重试走 `recoverWriteSet`（manifest `complete` → no-op / `prepared` → redo）+ 补 commit。**无**任何「先滚回 unassigned」代码路径。
- `writeback-after-commit`：`payload.committed=true` 短路第 13–14 步的 commit 段；只 push + complete。
- `writeback-after-push`：`payload.pushed=true` 短路 push 段；只补投影与 `save('complete')`。

其余既有点（`writeback-after-journal-create` 等）语义不变；`writeback-after-journal-create` 时尚无 write-set、manifest 缺失，重试保留首次 payload、entries 从 payload 重建并首轮 apply（§4.4 第 9a 步），不得「提前回灌账本」（versionRefill 只随 payload 持久化，文件写入只经 applyWriteSet）。

### 4.7 FR-5 人读文案落点

`../tools/README.md` 三处（已在 tools resource HEAD=`2bb66294` 重核实际行文，PRD FR-5 的「两侧须为真实版本且全等才放行」为语义表述，README 中不存在该字面串，实际改写对象如下）：

- 行 22：现行「…`crctl writeback-apply` 在入口做版本守卫：`--target-version` 与 `cr.md` 规范化全等才放行，版本错误零 candidate/journal 痕迹」改为 FR-1 判定表语义：**「`crctl writeback-apply` 入口版本守卫：cr.md=`unassigned` 且输入为真实版本时放行并在 writeback 事务内原子回灌 authority 的 cr.md/_backlog 该条目的 target-version（冻结的 prd/sdd/plan/tasks 不动）；其余版本错误（两侧/输入侧 unassigned、两侧真实但不一致、任一侧规范化失败）零 candidate/journal 痕迹」**。同行「把 `unassigned` 更正为真实版本的唯一入口是 `crctl version-set`」限定为**「writeback 事务之外」**：`version-set` 仍是唯一的非 writeback 更正入口（仍禁止 merging/writing-back、仍同步六类产物）；writeback 回灌只发生在 writeback 事务内、只碰两账本。
- 行 76：现行「`crctl writeback-apply` 的版本守卫保证版本错误在 candidate/journal 之前短路」保留，补一句回灌分支说明（与上一致）；同行「唯一更正入口」同样加 writeback 事务限定。
- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs#guardWritebackVersion` 错误文案（现行「`writeback 需要两侧均为真实版本：cr.md=${a}，输入=${b}`」）：改为 FR-5 口径——能区分「两侧/输入侧 unassigned」与「cr.md unassigned 已放行」：`writeback 版本守卫：两侧或输入侧为 unassigned 一律拒绝（cr.md=${a}，输入=${b}）；仅 cr.md=unassigned 且输入为真实版本时放行并回灌账本`。
- `crctl.mjs` HELP 文本无版本规则表述，零改动；writeback 三 Skill 调用形态（仍只传 `--target-version`）零改动（PRD FR-5 明确不要求改）。

---

## 5. 技术选型与替代方案

### 决策 D-1：守卫内新增窄只读解析器，而不是改造 `resolveOperationalWorkspace`

- **Context**：FR-3 要求守卫读 txws；但守卫必须让版本错误优先于 STATE_MISMATCH（FR-1），而 `resolveOperationalWorkspace` 的既有契约就是抛 `OPERATIONAL_WORKSPACE_*`/`CR_WORKTREE_STATUS_MISSING`。
- **Alternatives**：a) 守卫内 try/catch 调用完整解析器——错误优先级在 txws 缺失场景仍被 `OPERATIONAL_WORKSPACE_MISSING` 抢占，且 try/catch 吞错面不清；b) 给完整解析器加「静默模式」参数——把权威断言语义与只读探测语义耦合进同一函数，两个调用方各要一半行为，接口变坏。
- **Consequences**：新增 `resolveWritebackAuthorityPath`（§4.1），职责单点清晰：只回答路径、永不抛 STATE/OPERATIONAL 类错误；真正的 authority 断言仍唯一由 `resolveOperationalWorkspace` 承担。代价是两份路径判定逻辑并存，用 §4.1 差异表固化、测试双侧覆盖（AC-3）。

### 决策 D-2：回灌计划持久化进 journal payload（`versionRefill`），而不是每次重算或另立文件

- **Context**：`writeback-after-apply` 中断后，txws 的 cr.md 已是真实版本，重算回灌计划会得到「无需回灌」而把 `_backlog.yml` 变更遗留未提交——违反 FR-2.2 半成品禁令与 AC-2.3.1。
- **Alternatives**：a) 每次重算——上述缺陷；b) 另立独立 journal/ledger 文件——违反「账本单一写入通道」与 Negative Space（不新开事务文件面）。
- **Consequences**：与既有 `statusTransition` 同口径：before/after 哈希 + after 文本随 payload 落盘（crMd 与 backlog 条目均完整持久化，B-SDD-01）；**payload 落盘即冻结**，found 重试一律从 payload 重建并按 manifest/phase 向前恢复（尚未 apply / 部分 apply / 已 apply 三现场，§2.2/§4.4 第 9 步），不回算 after、不覆写计划；`durable-tx.mjs` envelope 校验只要求 payload 非空，零改动（§2.2）。

### 决策 D-3：回灌只经 recoverable write-set 向前恢复，不引入回滚

- **Context**：PRD FR-2.2 已定死（对齐既有 `applyWriteSet`/`recoverWriteSet`），本决策只是落点确认。
- **Alternatives**：command-ledger 式整组回滚（`rollbackLedgerPayload`）——与 writeback 既有语义冲突（commit 后无法回滚，只会制造 before/after 双版本事实）。
- **Consequences**：无新 fault-point、无新恢复原语；三点故障语义见 §2.4/§4.6。

### 决策 D-4：backlog 预检放在 `resolveOperationalWorkspace` 之后、candidate/journal 之前

- **Context**：FR-2.1 要求预检先于 journal/candidate/write-set，且只在 txws authority 执行。
- **Alternatives**：a) 预检放 guard 内——guard 是纯判定、不碰 `_backlog.yml`（写入面与读面分离），放进来会破坏其可单测性与错误面；b) 放 journal 创建后——违反 FR-2.1 时序。
- **Consequences**：预检在 txws 断言之后立即执行（§4.4 第 4–7 步），失败零 candidate/journal/lock 痕迹；非 txws 场景先得既有 `WRITEBACK_STATE_MISMATCH`，预检天然不触达。

---

## 6. FR 到技术实现映射

### 6.1 逐条 FR 映射

| FR | 实现条目 | 落点 |
|---|---|---|
| FR-1 | 判定表重写 + 文案改写（§2.1/§4.2） | `guardWritebackVersion`（workspace-transactions.mjs） |
| FR-2 | 回灌分支：payload 持久化 + entries 合成 + 幂等（§2.2/§4.4/§4.5） | `applyWritebackAtomic` + `planVersionRefill` |
| FR-2.1 | backlog 预检四错误码 + 零写入时序（§2.3/§4.3/§4.4） | `planVersionRefill` ① |
| FR-2.2 | 三故障点语义，无新注入点（§2.4/§4.6） | 既有 `applyWriteSet`/`faultPoint`，零改动 |
| FR-3 | 窄解析器 + 差异表 + authority 快照绑定 + 回退不回灌（§4.1/§4.4 第 5.5 步） | `resolveWritebackAuthorityPath`；guard 消费 |
| FR-4 | 测试向量改写与新增（§6.2） | `writeback-tx.test.mjs` + `crctl.test.mjs` + `merge-fixture.mjs` 参数化 |
| FR-5 | README 行 22/行 76 + UNASSIGNED 文案（§4.7） | `../tools/README.md` + `guardWritebackVersion` 文案 |
| FR-6 | CLI 信封契约（§3.1/§3.2；`payload.files` 投影零改动即满足） | `applyWritebackAtomic` 返回路径（零新增代码，靠 §4.4 第 13 步既有 `files` 投影） |

### 6.2 AC 逐项设计与验收映射

```text
AC-1（FR-1 判定表，merged 夹具 authority=txws）
设计落点：guardWritebackVersion 判定表 + 既有 STATE_MISMATCH 落点
可观测结果：六行向量各自的 exit/error.code（1: 放行并回灌或既有后续错误且 ≠UNASSIGNED；
           2/3: WRITEBACK_VERSION_UNASSIGNED；4: MISMATCH；5: INVALID；6: 与今日一致放行不改版本字段）
可达性说明：makeMergedFixture(unassigned) 参数化夹具（§6.2 证据 6）使 a=unassigned 可达；
           a=0.2 向量沿用既有 makeMergedFixture() 默认版本
AC-2.1（成功回灌原子性）
设计落点：planVersionRefill ⓪①③ + entries 合成 + 单 commit（§4.3/§4.4）
可观测结果：authority cr.md/_backlog 该条目 target-version=规范化 0.30；prd/sdd/plan/TASK-* 哈希
           与调用前全等；baseline status 变迁与版本回灌同一次 commit（git show 该 commit 同时含
           cr.md status=writing-back+版本行、_backlog 版本行、specs 三文件）；tasks/traceability
           重跑版本行无新 diff（git log --follow 两账本路径仅首 commit 含版本行变更）
可达性说明：refill 分支仅当 txws cr.md=unassigned（参数化夹具）+ 输入真实版本；baseline 首跑
           status=merging 满足 validateBaselineAdvance
AC-2.2（backlog 冲突五向量）
设计落点：planVersionRefill ①预检表（§2.3）
可观测结果：exit 1 + 对应 error.code/extra（1: WRITEBACK_BACKLOG_VERSION_MISMATCH {backlog:0.29,
           input:0.30}；2: ENTRY_NOT_IN_BACKLOG；3: WRITEBACK_BACKLOG_ENTRY_DUPLICATE {count>=2}；
           4: WRITEBACK_VERSION_INVALID {backlogReason}；5: 放行且只回灌 cr.md、backlog 行无 diff）；
           全部拒绝路径：specs/candidate/journal/lock/cr.md(status+target-version)/_backlog 字节级
           零变化、零 commit（snapshotSixPoints 扩展 _backlog 哈希）
可达性说明：五向量在 txws authority 上直接构造（改 txws 内 _backlog.yml），预检先于 candidate/journal
AC-2.3（三故障点 + B-SDD-01 部分 apply 冻结回归）
设计落点：既有 FAULT_POINTS + 持久化 versionRefill + manifest/phase 向前恢复（§2.4/§4.6/§4.4 第 9 步）
可观测结果：1: 首次 exit≠0 FAULT_INJECTED、HEAD 无 writeback commit；同参重试 exit 0、phase=complete、
           origin 恰好一个 writeback {stage} commit 且同时含两账本 0.30 与业务文件；
           [baseline 断言同前]；direct tasks/traceability 回灌夹具（txws status=writing-back + 两账本
           target-version=unassigned，不经 baseline 直接跑 tasks stage）：writeback-after-apply 后同参重试，
           guard 读 cr.md 已是真实版本（refill=false），cr.md 条目仅由 payload.versionRefill.crMd 重建，重试
           commit 含 cr.md 版本行 + _backlog 版本行 + 本 stage 业务文件，stdout files 含 cr.md 与 _backlog
           两路径（B-SDD-01 回归）；
           1b（部分 apply 冻结回归，B-SDD-01）：direct 夹具 + CRCTL_FAULT_POINT=tx-apply-between-rename →
           首次 exit≠0 FAULT_INJECTED、manifest state=prepared；随后夹具把 txws _backlog.yml 置为
           payload.versionRefill.backlog.afterText（构造「backlog 已 after、cr.md 仍 unassigned」的 rename
           间现场）；同参重试（不设 env）：payload.versionRefill 保持首次落盘值（不重算、backlog 条目不降为
           null），recoverWriteSet 按 manifest 补齐 cr.md，commit 同时含两账本 0.30 与业务文件，stdout
           files 含两账本路径；
           2: 同参重试不新增 commit（writeback {stage} 恰好 1 条）；3: 同参重试 exit 0、phase=complete、
           commit=中断前 sha、origin 不新增、两账本保持该 commit 映像
可达性说明：CRCTL_FAULT_POINT 既有入口校验（FAULT_POINTS 表未变，三点 + tx-apply-between-rename 全登记）；
           重试不设 env；direct tasks/traceability 回灌夹具 = txws 直接构造 status=writing-back + 两账本
           target-version=unassigned 的夹具（生成器前置只校验 cr.md status——§6.3 证据 5——writing-back
           即通过；该状态即旧守卫下 worktree/txws 版本分裂 CR 经 baseline 后的真实现场，本 CR 收编此类分裂）；
           merged（status=merging）夹具不满足 tasks/traceability 生成器前置，不可作 direct 夹具
AC-3（worktree 与 txws 版本分裂，FR-3）
设计落点：resolveWritebackAuthorityPath 的 txws 优先（§4.1）+ authority 快照绑定（§4.4 第 5.5 步）
可观测结果：requirement worktree cr.md 与 txws cr.md 版本不一致时，guard 以 txws 值为准（txws=
           unassigned+输入真实 → 放行且只回灌 txws，worktree 文件内容不变）；code-approved 夹具上
           MISMATCH 仍优先于 WRITEBACK_STATE_MISMATCH；窄解析器回退（source=cr-worktree）时
           refill=false，opWs=txws 的快照不一致路径 → WRITEBACK_STATE_MISMATCH 零写入
           （authority 快照绑定 throw 位，复用既有码；message 含 guardPath/opPath；单测层以
           planVersionRefill 同源断言 + guard source 条件向量覆盖，见 AC-4；运行时竞态窗口由
           第 5.5 步检查兜底）
可达性说明：merged 夹具 merge 后手改 worktree 副本的 target-version（不影响 txws）；code-approved
           夹具 = makeCodeApprovedFixture 未 merge（版本不一致向量）
AC-4（测试改写与回归）
设计落点：writeback-tx.test.mjs 删除/改写旧断言 + crctl.test.mjs 新增 guard/plan 向量
可观测结果：`node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 与
           `node --test skills/shared/crctl/scripts/test/writeback-tx.test.mjs` 通过；
           grep 确认不再断言「unassigned cr.md + 真实输入 → UNASSIGNED」；既有 AC-14 其它
           零观察点拒绝路径保持；crctl.test.mjs 另含：guard source 条件向量（txws 回灌 / worktree
           回退 refill=false 两分支）与 planVersionRefill 语义复核向量（仍 unassigned → 放行；
           已=输入 → 幂等 null；已=另一真实 → MISMATCH；非法 → INVALID）及同源断言向量
           （authority.path ≠ txws → WRITEBACK_STATE_MISMATCH，复用既有码、extra 保持既有形状）
可达性说明：crctl.test.mjs 已 import workspace-transactions 纯函数（既有模式）；guard 需要 ctx——
           用 resolveRepositories(kb)（fixture 内 kb 是 InstWS）；plan 向量用临时目录直接构造
           cr.md/_backlog 内容（不依赖完整夹具）
AC-5（人读文案）
设计落点：README 行 22/行 76 + guard 错误文案（§4.7）
可观测结果：`git grep -n "规范化全等才放行" ../tools/README.md` 零命中（FR-1 判定表语义替代）；
           README 行 22/行 76 的「唯一更正入口」均带 writeback 事务限定；guard 的
           WRITEBACK_VERSION_UNASSIGNED 文案能区分两侧/输入侧 unassigned 与已放行回灌分支；
           测试夹具字符串除外
AC-6（CLI 信封，B-03）
设计落点：既有 ok()/fail() 信封 + payload.files 投影（§3.1/§3.2）
可观测结果：1: stdout op=writeback-apply、phase 严格 "complete"、changed=true、status=writing-back、
           commit ^[0-9a-f]{40}$、files 同时含两账本路径、recoverCommand 含规范化 --target-version、
           stderr 不可解析为错误信封；2: 同参第二次 changed=false、commit/files 与首次相同；
           3: AC-2.2.1 失败 exit 1、stdout 无成功对象、stderr error.code=WRITEBACK_BACKLOG_VERSION_MISMATCH
           且 error.backlog/error.input 扁平并入
可达性说明：公共 CLI 断言（runCrctl spawn），非库函数返回值
```

### 6.3 既有实现依赖与事实

按正文首次出现顺序；commit SHA 均来自 tools 仓 resource worktree 当前 HEAD（`2bb66294db30b116e0d53aea48990611017c75d6`，即 CR-2026-057 merge 提交；已按 `resources[repo=tools].worktreePath` 受控执行 `crctl git rev-parse HEAD` 与 `crctl git branch --show-current --cwd <worktreePath>` 核实：HEAD=`2bb66294`，branch=`requirement/CR-2026-058`（本 CR 派生 worktree，非 trunk `custom/main`），七项 path/symbol/conclusion 均在该 worktree HEAD 重核）。

1. repo: tools
   relative path: skills/shared/crctl/scripts/lib/workspace-transactions.mjs
   stable symbol/对象: `resolveOperationalWorkspace`（唯一 authority 断言）/ `crWorktreePath` / `txWorkspacePath` / `readCrMdStatus`（模块私有）/ `readCrMdTargetVersion`（export）/ `mergeStatus` / `POST_FINALIZE_STATUSES`（merging/writing-back/archived）/ `normalizeTargetVersion` / `crMdStatusText` / `matchFrontmatter` / `canonicalWritebackBusinessInput` / `resolveWritebackCandidate` / `readPreparedCandidate`（snapshot.files 含 `blobText`；found 分支 `checkBefore:false`）/ `applyWritebackAtomic` / `writebackAllowlist` / `verifyReleaseSubjects`（KB post-review 白名单含 `change-requests/{cr}/cr.md` 与 `change-requests/_backlog.yml`）；现状 `guardWritebackVersion` 读 `crWorktreePath`（本 CR 改为窄解析器 + txws）
   commit SHA: 2bb66294db30b116e0d53aea48990611017c75d6
   依赖结论: 回灌分支完全寄生在既有 writeback 事务上；authority 断言、status 合成、entries/commit/push/journal 骨架全部复用，本 CR 只插入 guard 重写、窄解析器、authority 快照绑定与 versionRefill 计划（§1.1/§4.4）；`readPreparedCandidate` 的 `blobText` 即 §4.4 第 13 步 entry.content 来源

2. repo: tools
   relative path: skills/shared/crctl/scripts/lib/durable-tx.mjs
   stable symbol/对象: `applyWriteSet`（先全量预检再写：任何条目当前 hash 非 before 非 after → `TX_RECOVERY_CONFLICT` 整体中止零写入）/ `recoverWriteSet`（manifest `prepared` → redo）/ `faultPoint` / `FAULT_POINTS`（含三 writeback 点）/ `loadOrCreateJournal` / `saveJournal` / `assertEnvelope`（只要求 op 对应 payload 非空、不枚举内部字段，已核实 193-211 行）/ `TxError`
   commit SHA: 2bb66294db30b116e0d53aea48990611017c75d6
   依赖结论: FR-2.2 故障语义 = 既有 recoverable write-set 语义；versionRefill 新字段能落盘的前提是 envelope 校验不枚举 writeback payload 内部字段（零改动成立）；新错误码经 TxError.extra 扁平进 fail() 信封；§4.5 回灌分支的 before 锚点变更后，读取间漂移由 `applyWriteSet` 预检以 `TX_RECOVERY_CONFLICT` 暴露（零账本写入）

3. repo: tools
   relative path: skills/shared/crctl/scripts/lib/yaml-subset.mjs
   stable symbol/对象: `matchEntryBlock(text, id)`（返回 `{start, end, text, indent}`，已核实签名与返回结构）
   commit SHA: 2bb66294db30b116e0d53aea48990611017c75d6
   依赖结论: backlog 条目定位与区间定点替换依赖其 start/end 偏移（B-CODE-001 口径，§4.3 ②）；命中计数用与 merge 侧 `locateBacklogEntry` 相同的行级正则

4. repo: tools
   relative path: skills/shared/crctl/scripts/crctl.mjs
   stable symbol/对象: `cmdWritebackApply`（flag 面/`validateBaselineAdvance`/`emitStatusEvent`/`emitAdvanceAudit`/`emitTraceEvent` callbacks）/ `fail` / `ok` / `runTxAsync` / `preflightAdvance`（返回 `{ path, beforeText, beforeSha256: sha256(beforeText) }`；`beforeText` 为 `readFileChecked` 原文——utf8 未规范化，与 `readHashRaw` 磁盘字节口径一致）
   commit SHA: 2bb66294db30b116e0d53aea48990611017c75d6
   依赖结论: 本 CR 不改这些调用点与签名（zero_diff §9）；`validateBaselineAdvance` 回调仍被执行（gate 检查副作用保留），非回灌分支的 `beforeText/beforeSha256` 仍是 baseline cr.md 合成条目的 before 锚点（今日行为）；回灌分支改以 plan 语义复核文本为锚点（§4.5）

5. repo: tools
   relative path: skills/writeback/scripts/writeback-prd-sdd.mjs / writeback-tasks.mjs / writeback-traceability.mjs
   stable symbol/对象: 前置只校验 cr.md `status`（writeback-prd-sdd：`∈ {merging, writing-back}`；writeback-tasks / writeback-traceability：仅 `writing-back`），**三者均不读 cr.md target-version**；`--version` 直接进 manifest targetVersion
   commit SHA: 2bb66294db30b116e0d53aea48990611017c75d6
   依赖结论: txws cr.md=unassigned（status=merging/writing-back）时 generator 正常产出 candidate——回灌在 apply 期才发生，generator 无需感知（AC-1.1 可达性前提）

6. repo: tools
   relative path: skills/shared/crctl/scripts/test/merge-fixture.mjs
   stable symbol/对象: `makeFixture` / `makeCodeApprovedFixture`（已核实：cr.md `target-version: 0.2`、`_backlog.yml` 条目**无 target-version 行**）
   commit SHA: 2bb66294db30b116e0d53aea48990611017c75d6
   依赖结论: 回灌测试需参数化：`makeCodeApprovedFixture({ targetVersion = '0.2' })` 时在 cr.md 与 `_backlog.yml` 条目补 `target-version: <v>` 行（默认 0.2 保持既有行为、默认补行对既有断言无影响）；`writeback-tx.test.mjs#makeMergedFixture` 同步透传参数

7. repo: tools
   relative path: README.md（行 22、行 76）+ skills/shared/crctl/scripts/lib/workspace-transactions.mjs（`guardWritebackVersion` 错误文案）
   stable symbol/对象: 已在本 HEAD 重核实际行文：README 行 22 现行「`crctl writeback-apply` 在入口做版本守卫：`--target-version` 与 `cr.md` 规范化全等才放行，版本错误零 candidate/journal 痕迹」+「唯一更正入口」表述；行 76 现行「`crctl writeback-apply` 的版本守卫保证版本错误在 candidate/journal 之前短路」+「唯一更正入口」表述。README **不存在**「两侧须为真实版本且全等才放行」/「任一侧 unassigned」字面串（PRD FR-5 的引用为语义表述）；守卫文案改写目标在 `guardWritebackVersion`（现行「`writeback 需要两侧均为真实版本：cr.md=…，输入=…`」）
   commit SHA: 2bb66294db30b116e0d53aea48990611017c75d6
   依赖结论: FR-5/AC-5 改写对象 = §4.7 三处（README 两处 + 守卫文案一处）；「唯一更正入口」需限定为 writeback 事务之外（回灌只发生在 writeback 事务内、只碰两账本）

---

## 7. 安全与性能考量

- **边界条件**：authority cr.md 缺失/无 frontmatter/缺 `target-version` 行 → `WRITEBACK_VERSION_INVALID`（既有）；txws 缺失/状态不自洽 → 窄解析器回退 cr-worktree 比较、后续既有 STATE_MISMATCH/OPERATIONAL_WORKSPACE 兜底；guard 采样与 opWs 不同源同路径 → 复用既有 `WRITEBACK_STATE_MISMATCH` 零写入（§4.4 第 5.5 步新增 throw 位）；plan 二次读取语义复核（仍 unassigned / 已=输入幂等 / 另一真实 MISMATCH / 非法 INVALID，§4.3 ③）；backlog 条目缺行/非法/重复/缺失 → §2.3 四码，全部零写入；`writeback-after-apply` 后重试的 hash 分类（=after skip / =before redo / 第三值 `TX_RECOVERY_CONFLICT`）由既有 `applyWriteSet` 预检保证（回灌分支 before 锚点后的任何漂移均被第三值拦截，零账本写入）。
- **性能（NFR-4）**：guard/预检均为常数时间——一次 `readFileSync`（cr.md、backlog）+ 行级正则 + 纯函数文本变换；无网络调用（`mergeStatus` 只读本地 journal；`resolveWritebackAuthorityPath` 不 fetch）。
- **安全（NFR-5）**：不新增绕过 crctl 的账本写路径（回灌只经 `applyWriteSet` 既有通道、lock/journal/commit 全复用）；不扩大 post-review 白名单（回灌的两路径 `cr.md`/`_backlog.yml` 已在 `verifyReleaseSubjects` KB 白名单内，NFR-6 依赖 §6.3 证据 1 的既有实现）；版本写入值恒为规范化串（无引号/空白注入面）；`resolveWritebackAuthorityPath` 不做 authority 断言（不替代 `resolveOperationalWorkspace`），回退路径天然禁止回灌；B-SDD-02 双层绑定（路径同源断言 + 值级语义复核 + `applyWriteSet` 末段 hash CAS）保证「覆盖另一真实版本」不可能：路径不一致零写入硬失败，版本值在两次采样间漂移则 MISMATCH/INVALID 拒绝，漂移发生在复核之后则 `TX_RECOVERY_CONFLICT` 拦截。
- **行尾纪律（NFR-3）**：所有新增读文件先 `\r\n→\n`；行级解析用既有 `backlogLines`（`\r?\n` 口径）与 `split('\n')`；跨行/单行正则匹配失败一律硬失败（`ENTRY_NOT_IN_BACKLOG`/`WRITEBACK_VERSION_INVALID`/`WRITEBACK_STATUS_INVALID`/`LEDGER 类`），禁止静默返回原文（§4.3 两条编辑函数均带「替换未命中 → 硬失败」断言）。

---

## 8. Prompt 采纳影响

**N/A（本 CR 不触及）**：本 CR 的 diff 不涉及 `skills/shared/crctl/scripts/crctl.mjs` 的 dispatch 分支（无新增/变更子命令；writeback-apply 命令面与 flag 面零改动）与 `skills/shared/controlled-shell/rules.json` 的 `protectedPaths.deny`（无新路径/命令面）。新增的账本写入能力（回灌）是 `crctl writeback-apply` 既有子命令的内部行为，无需任何 Skill 改变调用形态（PRD FR-5 明确：仍只传 `--target-version`）。因此无需列出「应改为调用新增子命令的 skill 清单」——本节按 SDD 规范以 N/A 理由显式保留。

---

## 9. 批准范围

- **scope_in**：CR-2026-058 必须交付：FR-1（guardWritebackVersion 判定表与文案，含 authority 快照）、FR-2/FR-2.1/FR-2.2（回灌分支、backlog 预检、故障边界；journal payload 完整持久化 crMd/backlog 条目且落盘即冻结）、FR-3（窄解析器与 authority 对齐；authority 同源绑定与语义复核）、FR-4（writeback-tx.test.mjs 改写与 crctl.test.mjs 新增向量）、FR-5（README 行 22/行 76 + 守卫文案）、FR-6（CLI 信封观察面）；验收 AC-1～AC-6（§6.2）。新增错误码：仅 PRD FR-2.1 已允许的 `WRITEBACK_BACKLOG_VERSION_MISMATCH` / `WRITEBACK_BACKLOG_ENTRY_DUPLICATE` 两个（NFR-2/§7 上限）。B-SDD-02 同源绑定硬失败**复用既有 `WRITEBACK_STATE_MISMATCH`**（新增 throw 位、extra 保持既有 `{cr, phase}` 形状、guard 快照与 opWs 的证据进 message）——不新增第三个公开错误码（B-SDD-04：PRD FR-6.2 未列，SDD 不得单方面扩契约）。
- **scope_out**：不放宽 `version-set` 合法状态集（merging/writing-back 仍禁止）；不回灌/不改写冻结的 `prd.md`/`sdd.md`/`plan.md`/`TASK-*.md`；不推进、不代跑 CR-2026-057 的 writeback/archive（057 保持 `merging` 直至本 CR 合入主仓）；不回写修复已归档 AIFI-14（CR-2026-056）历史产物；不新增 Agent/Pipeline/状态机状态与转换/CLI 子命令/事务框架/fault-point（仅允许 FR-2.1 两个新错误码；authority 绑定复用既有 `WRITEBACK_STATE_MISMATCH`）；不修改 `../multica/`；不扩大 post-review 白名单、不放松 `verifyReleaseSubjects`；不处理 AIFI-15 附件中除本拍板最小面以外的建议。
- **zero_diff**：`crctl.mjs` 的 `cmdWritebackApply`（含 flag 面、callbacks）、`fail()`/`ok()`/`runTxAsync` 信封形态；`resolveOperationalWorkspace` 的签名与抛错契约（唯一 authority 断言点）；`durable-tx.mjs` 全部导出与 `FAULT_POINTS` 登记表；`lib/yaml-subset.mjs` 全部导出；writeback 三个 generator 脚本及其 manifest 格式（v1/v2 校验不变）；`guardWritebackVersion` 的**调用签名**（`(ctx, cr, inputTargetRaw)` 不变，仅返回值扩展）；`statusTransition` 既有字段结构与投影逻辑；`verifyReleaseSubjects` 白名单集合。
- **follow_up**：无。发现但留给后续 CR 的缺口：PRD FR-2.1 明确排除的「账本已分裂但两侧真实」（backlog 与 cr.md 均为真实版本但互不一致）的检核与自愈，本 CR 不扩进范围——若未来需要，应另开 CR 定义其判定与入口（不得在本 CR 实现期顺手扩展）。
