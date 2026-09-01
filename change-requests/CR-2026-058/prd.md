---
id: CR-2026-058-prd
type: PRD
cr-ref: CR-2026-058
title: writeback 版本守卫：cr.md unassigned + 真实版本放行并原子回灌
target-version: 0.30
owner: Ray
owner-role: requirement
status: draft
created: 2026-09-01T13:12:00+08:00
updated: 2026-09-01T13:20:00+08:00
---

# 1. 概述

## 1.1 问题陈述

CR-2026-057（P1-1 / FR-14）把 `crctl writeback-apply` 的版本守卫做成「任一侧规范化后为 `unassigned` → `WRITEBACK_VERSION_UNASSIGNED` 零写入」。该断言在 AIFI-15 上自撞：CR-2026-057 自身以 `unassigned` 注册并完成 merge（代码已合入主仓），`version-set` 在 `merging` 禁止，writeback 传入真实版本 `0.30` 被守卫拒绝，回写与归档停死。

同时，守卫经 `crWorktreePath` 读 cr.md，而 `merging` / `writing-back` 的 authority 是 Transaction Workspace（txws）。读取位置与 authority 不一致时，回灌或后续 stage 会把 worktree 与 txws 做成两份版本事实（AIFI-14 的 `tbd` / `0.29` 分叉翻版）。

CR-2026-057 的 AC-14「unassigned 拒绝」必须在测试层改写；不得靠旧版 tools、手改账本或绕过 writeback 完成 057 的回写。

## 1.2 解决方案摘要

只改 tools 仓既有 `guardWritebackVersion` 与 writeback 事务 write-set，以及对应回归与人读说明：

```text
cr.md=unassigned + 业务输入=真实版本 → 放行
writeback 事务内原子回灌 authority 的 cr.md 与 _backlog.yml 的 target-version
回灌只碰这两个评审后白名单文件，不碰冻结的 prd/sdd/plan/tasks
_backlog.yml 仅当条目唯一且前置值为 unassigned 或已等于输入真实版本时才回灌；另一真实版本 / 缺失 / 重复 → 拒绝且零写入
两侧 unassigned、输入 unassigned、两侧真实但不一致、任一侧非法 → 仍按既有错误码拒绝
读取与回灌的 cr.md 必须是 writeback authority 上的那一份（merging/writing-back = txws）
成功 CLI 固定 phase=complete；失败 envelope 保持既有 error.code + extra 扁平并入
```

本 CR 注册即为 `0.30`（承接 0.30 发布面），禁止 `unassigned`/`tbd`。合入主仓后，CR-2026-057 才以 `--target-version 0.30` 继续 writeback 直至归档；期间 057 保持 `merging`，本 CR 不推进 057 状态。

## 1.3 已拍板范围（采纳 cr.md summary，不重新定义）

CR-2026-057 follow-up（tools 仓）：修订 `guardWritebackVersion`——`cr.md=unassigned` + 业务输入=真实版本 → 放行，并在 writeback 事务内原子回灌 authority 的 cr.md/_backlog 的 target-version；回灌只碰这两个评审后白名单文件，不碰冻结的 prd/sdd/plan/tasks。修订 CR-2026-057 AC-14 的 unassigned 拒绝断言为「`cr.md=unassigned` + 输入=真实版本 → 放行并回灌；两侧 unassigned 仍拒绝」。守卫的 cr.md 读取/回灌位置必须与 writeback authority 一致（`merging`/`writing-back` 为 txws，不得用 `crWorktreePath` 造成版本事实分裂）。本 CR 承接 0.30 发布面。不含 version-set 放宽、不含改冻结产物、不含推进 CR-2026-057 状态。

目标仓：sibling `../tools/`。knowledge-base 只承载本 PRD；`../multica/` 无实施改动。

# 2. 用户故事

- **US-1 回写执行者**：作为 writeback 节点执行者，我希望对已 merge、账本仍为 `unassigned` 的 CR 传入真实 `--target-version` 时 writeback 能放行并把账本回灌为该版本，从而完成 baseline/tasks/traceability 与归档，而不是死锁在 `WRITEBACK_VERSION_UNASSIGNED`。
- **US-2 平台维护者**：作为平台维护者，我希望回灌只改 authority 上的 `cr.md` 与 `_backlog.yml`，冻结的评审快照（prd/sdd/plan/tasks）保持原样，从而不破坏评审后白名单与 release-subjects 哈希。
- **US-3 版本事实消费者**：作为后续 stage / archive / 查询方，我希望守卫读取与回灌都落在 writeback authority（txws）上，从而不会出现 worktree 一份版本、txws 另一份版本。
- **US-4 回归守护者**：作为测试维护者，我希望正负向量写进 `writeback-tx.test.mjs` 与 `crctl.test.mjs`，从而 CR-2026-057 AC-14 的过严拒绝不会再被当成绿灯契约。

# 3. 功能需求

规范化函数仍用 CR-2026-057 `normalizeTargetVersion`（值域、禁止同义值、`v`/`V` 前缀剥离不变）。本 CR 不改 register / version-set 的合法状态集。

## FR-1 修订 `guardWritebackVersion` 判定表

`crctl writeback-apply` 入口守卫（`skills/shared/crctl/scripts/lib/workspace-transactions.mjs#guardWritebackVersion`）在规范化后按下行判定。命令、调用者、非 TTY、三 stage 相同。

| cr.md 规范化值 | 输入规范化值 | 结果 | 错误码 |
|---|---|---|---|
| `unassigned` | 真实版本 | **放行**，进入既有 writeback；回灌见 FR-2 | （无版本错误） |
| 真实版本 A | 真实版本 A | 放行（与今日一致）；无需回灌 | （无） |
| 真实版本 A | 真实版本 B（A≠B） | 拒绝 | `WRITEBACK_VERSION_MISMATCH` |
| `unassigned` | `unassigned` | 拒绝 | `WRITEBACK_VERSION_UNASSIGNED` |
| 真实版本 | `unassigned` | 拒绝 | `WRITEBACK_VERSION_UNASSIGNED` |
| 任一侧规范化失败 | * | 拒绝 | `WRITEBACK_VERSION_INVALID` |

仍保留：版本错误优先于 `WRITEBACK_STATE_MISMATCH` 及其它后续错误。因此 `unassigned`+真实版本 **不再是版本错误**——非 txws authority 的夹具（如 `status=drafting` / `code-approved`）将落到既有 `WRITEBACK_STATE_MISMATCH`，而不是 `WRITEBACK_VERSION_UNASSIGNED`。其余版本错误（MISMATCH / INVALID / 两侧或输入侧 `unassigned`）仍必须抢先于 STATE_MISMATCH。

失败观察点（拒绝路径，三 stage 相同）沿用 CR-2026-057 AC-14：零 specs/delivery/traceability 变化、零 candidate 创建改写、零 writeback journal 创建改写、零 lock 残留、authority/`cr.md` status 不变、零 commit/push；同参重试同码无增量。

规范化值回灌（B-SDD-002）保留：放行后 `input.targetVersion` 使用规范化串。

## FR-2 writeback 事务内原子回灌账本版本

仅当 FR-1 放行且 authority cr.md 规范化值为 `unassigned`、输入为真实版本时，进入回灌分支。在 **既有 writeback recoverable write-set** 内把该真实版本写入：

1. authority 上 `change-requests/{CR-ID}/cr.md` 的 `target-version`
2. authority 上 `change-requests/_backlog.yml` 该 CR 条目的 `target-version`

约束：

- 回灌与当次 stage 的业务文件、以及 baseline 已有的 `cr.md` status 变迁（`merging→writing-back`）同一次 write-set / 同一次 commit。禁止先改版本再开 writeback，禁止守卫阶段抢先写盘。`cr.md` 不得出现两条 write-set 记录：status 与 `target-version` 必须合成同一次 `afterText`。
- 只碰上述两个路径。禁止改 `prd.md` / `sdd.md` / `plan.md` / `tasks/TASK-*.md` 的 `target-version`（评审冻结产物；二者已在 post-review 白名单，产物文件不在）。
- 幂等：authority cr.md 已是该真实版本时，不再改这两个文件（后续 stage 只写本 stage 业务文件）。
- 这 **不是** 新 CLI，也 **不是** `version-set` 的替代入口。`version-set` 仍禁止 `merging`/`writing-back`，仍同步六类产物。本回灌是 writeback 在冻结期对账本（非快照）的受控补齐，允许「评审快照仍为 `unassigned`、账本与 writeback 产物为真实版本」——这是本 CR 明确接受的不对称，用来避免触碰 release-subjects。

### FR-2.1 `_backlog.yml` 回灌前置值与冲突（零写入）

回灌分支在创建 journal / candidate / write-set **之前**，对 **同一** authority 上的 `_backlog.yml` 做预检。禁止静默覆盖另一真实版本，禁止缺失时插入新条目。

条目计数：authority `_backlog.yml` 中 `- id: {CR-ID}` 的命中次数（与既有 `matchEntryBlock` / merge 条目扫描同口径）。

| 命中次数 | 结果 | 错误码 |
|---|---|---|
| 0 | 拒绝 | `ENTRY_NOT_IN_BACKLOG`（复用既有码；`error.cr` = CR-ID） |
| >1 | 拒绝 | `WRITEBACK_BACKLOG_ENTRY_DUPLICATE`（本 CR 新增；`error.cr`、`error.count`） |
| 1 | 进入下表 | （无） |

恰好一条时，读该条目 `target-version` 并经 `normalizeTargetVersion`（`allowUnassigned=true`）：

| backlog 规范化值 | 结果 | 错误码 |
|---|---|---|
| `unassigned` | **允许回灌**：write-set 将该字段改为输入真实版本 | （无） |
| 与输入全等的真实版本 | **允许**：该字段不再改写（幂等）；若 cr.md 仍为 `unassigned`，仍须回灌 cr.md | （无） |
| 另一真实版本（≠ 输入） | 拒绝 | `WRITEBACK_BACKLOG_VERSION_MISMATCH`（本 CR 新增；`error.cr`、`error.crMd`、`error.backlog`、`error.input`） |
| 规范化失败（缺字段 / 非法 / 禁止同义值） | 拒绝 | `WRITEBACK_VERSION_INVALID`（与 FR-1「任一侧规范化失败」同码；`error.crMdReason` 或并列 `error.backlogReason` 区分来源） |

触发范围：

- **只在回灌分支**（authority cr.md=`unassigned` + 输入=真实版本）且 authority=`transaction-workspace` 时执行本预检。
- 非 txws：不读 backlog 写路径、不回灌，落到既有 `WRITEBACK_STATE_MISMATCH`（与 FR-3「此时不得回灌」一致）。
- 非回灌分支（两侧真实且全等）：不因 backlog 另值额外拒绝；本 CR 不把「账本已分裂但两侧真实」扩进范围。

优先级（回灌分支）：FR-1 版本守卫（cr.md vs 输入）> 本预检 > 后续 `WRITEBACK_STATE_MISMATCH` 以外错误。本预检失败视为版本/账本错误，必须抢先于 journal 创建。

拒绝路径观察点（三 stage 相同，与 CR-2026-057 AC-14 六项对齐并加 backlog 自身）：零 specs/delivery/traceability 变化、零 candidate 创建改写、零 writeback journal 创建改写、零 lock 残留、authority `cr.md` 的 status 与 `target-version` 不变、`_backlog.yml` 字节级不变、零 commit/push；同参重试同码无增量。

### FR-2.2 故障边界：回滚 vs 同参续跑（沿用既有 writeback 事务）

回灌条目进入与本 stage 业务文件 **同一个** `applyWriteSet` `entries[]`。语义对齐既有 writeback recoverable write-set（`durable-tx.mjs#applyWriteSet` / `recoverWriteSet`）：中断后 **向前恢复到计划 after**，不是 command-ledger 那种「commit 前整组滚回 before」。禁止再写「整组回滚」而不标明故障点。

绑定既有 `FAULT_POINTS`（不新增 fault-point 名称）：

| 边界 | 注入点 | 中断现场 | 同参重试预期 | 重试后不变量 |
|---|---|---|---|---|
| apply 后、commit 前 | `writeback-after-apply` | write-set 已把 after 映像落到 txws 工作区（含两账本版本行 + 本 stage 业务文件 + baseline 时 cr.md status 合成 afterText）；HEAD 仍为 writeback 前；journal **未** `committed` | `recoverWriteSet`：`complete` → 保 after no-op；`prepared`（rename 中断）→ redo 剩余条目到 after。然后补 `git add`+commit。**禁止**先把账本滚回 `unassigned` 再另造 after | 恰好一个 writeback commit；该 commit 同时含两账本目标版本与本 stage 业务文件；冻结产物字节级不变 |
| commit 后、push 前 | `writeback-after-commit` | 本地 commit 已存在；journal `committed=true`、`pushed=false` | **保留**该 commit 与 journal；续跑只做 lease push + complete；不新建 commit | origin 上该 stage 恰好一个 `writeback {stage}` commit；两账本版本行在该 commit 内；`changed=true` 仅该 journal 首次 `phase=complete` |
| push 后、complete 前 | `writeback-after-push` | origin 已确认该 commit；journal `pushed=true` | **保留**已发布 commit；续跑只完成剩余 outbox / `save('complete')`；不新增 commit、不改账本 | `phase=complete`；`commit` 与中断前相同；两账本版本行保持该 commit 映像 |

其它既有点（`writeback-after-journal-create`、`writeback-after-status-outbox`、`writeback-after-advance-audit`、`writeback-after-trace-intent`、`writeback-after-trace-outbox`）保持今日语义，本 CR 不改。`writeback-after-journal-create` 时尚无 write-set：重试继续同一 journal，不得已回灌账本。

半成品禁令的唯一口径：两账本与本 stage 业务文件同一次 `entries[]`，因此不允许出现「cr.md 已是真实版本而本 stage 业务文件未进同一 after/同一 commit」。这由 write-set 原子性保证，不是事后补偿写。

## FR-3 守卫读取与回灌位置必须等于 writeback authority

`merging` / `writing-back` 阶段 authority 是 txws（既有 `resolveOperationalWorkspace`：`source=transaction-workspace`）。

- 守卫比较所用的 cr.md，以及 FR-2 回灌的 cr.md/_backlog，必须是 **同一** authority 工作区上的文件。
- **禁止**继续用 `crWorktreePath`（requirement worktree）作为 `merging`/`writing-back` 的版本事实源：merge finalize 后 worktree 的 `cr.md` 仍可能是 `code-approved` + `unassigned`，与 txws 分裂。
- **禁止**为了取路径而在守卫里调用会抛 `WRITEBACK_STATE_MISMATCH` / `OPERATIONAL_WORKSPACE_*` 的完整 `resolveOperationalWorkspace`，以免破坏「版本错误优先」。允许新增窄只读路径解析：只回答「若 writeback 继续，authority 路径是哪」；txws / merge journal 不足以构成 post-finalize authority 时，退回 `crWorktreePath` **仅用于版本比较**，随后仍走既有 STATE_MISMATCH，且此时不得回灌。
- 设计文档（本 CR 的 SDD）必须写明该路径解析器与 `resolveOperationalWorkspace` 的差异，避免再出现 D-6/B-SDD-001 与本 FR 的口头冲突。

## FR-4 修订 AC-14 测试并补正负回归

CR-2026-057 已合入的测试契约以本 CR 为准改写，不回改 057 冻结 PRD/SDD 正文。

`skills/shared/crctl/scripts/test/writeback-tx.test.mjs`：

- 保留：两侧均为真实版本但不一致 → `WRITEBACK_VERSION_MISMATCH` + 六项零观察点；输入 `n/a` → `WRITEBACK_VERSION_INVALID`；输入 `unassigned`（含两侧均为 `unassigned`）→ `WRITEBACK_VERSION_UNASSIGNED`；同参重试同码。
- **删除或改写**「`cr.md=unassigned` + 输入真实版本 → `WRITEBACK_VERSION_UNASSIGNED`」的正向拒绝断言。
- **新增正向**：`makeMergedFixture` 且 authority `cr.md`/`_backlog` 为 `unassigned`，三 stage 传入真实版本（如 `0.30` 或夹具既有真实版本）→ stdout `phase` **必须**为 `"complete"`（见 FR-6，不允许其它成功口径替代）；authority `cr.md` 与 `_backlog` 该条目变为该规范化真实版本；同目录 `prd.md`/`sdd.md`/`plan.md`/`TASK-*.md` 的 `target-version` 字节级不变；后续同参数重跑幂等且不再改账本版本行。
- 版本错误优先：`status=code-approved`（或 drafting）夹具上，MISMATCH/INVALID/输入 `unassigned` 仍得 `WRITEBACK_VERSION_*`；`cr.md=unassigned` + 输入真实版本则允许落到 `WRITEBACK_STATE_MISMATCH`（零写入）。

`skills/shared/crctl/scripts/test/crctl.test.mjs`：为 `guardWritebackVersion`（或等价纯判定）补最小正负向量——上表每一行至少一条；不引入第二套测试框架。

## FR-5 人读说明与错误文案同步

`../tools/README.md` 中「writeback 两侧须为真实版本且全等才放行」的表述改为与 FR-1 判定表一致。守卫失败文案「需要两侧均为真实版本」改为能区分「两侧/输入侧 unassigned」与「cr.md unassigned 已放行」；不要求改 writeback Skill 的调用形态（仍只传 `--target-version`）。

## FR-6 回灌分支的 CLI 结构化输出契约

`crctl writeback-apply` 的 I/O 信封保持既有实现，本 CR **不改** `ok()` / `fail()` / `runTxAsync` 形态。回灌分支必须把下列字段写成可唯一断言的观察面。

### FR-6.1 成功（exit 0）

成功只写 stdout JSON，不写 stderr 错误信封。固定键（与今日 `ok({ op: 'writeback-apply', ...result })` 一致）：

| 字段 | 回灌首次成功（该 journal 第一次 complete） | 同参幂等重跑 |
|---|---|---|
| `op` | `"writeback-apply"` | 同左 |
| `phase` | **必须** `"complete"`。禁止 `"committed"` / `"pushed"` / 其它 stage 别名作为成功返回 | `"complete"` |
| `changed` | `true` | `false` |
| `status` | baseline：`"writing-back"`；tasks/traceability：authority 既有 status（baseline 已跑则为 `"writing-back"`） | 与首次 complete 相同 |
| `commit` | 40 位 hex；该 commit 的 tree 含两账本目标版本 + 本 stage 业务文件 | 与首次相同 |
| `files` | 字符串数组，**必须同时包含** `change-requests/{CR-ID}/cr.md` 与 `change-requests/_backlog.yml`（另含本 stage 既有业务路径）。这是回灌的 CLI 观察面，禁止只改磁盘、JSON 不列账本路径 | 与 journal 记录的 write-set 路径相同（仍含两账本路径） |
| `recoverCommand` | 同业务命令字符串，`--target-version` 为规范化真实版本 | 同左 |
| `txId` / `warnings` / 其它既有字段 | 保持既有契约；回灌成功且无投影失败时 `warnings` 为 `[]` | 保持既有 |

`files` 不得用「业务文件已含回灌」的隐含语义替代上述两路径。noop 既有成功（非回灌、`changed=false`、`commit=null`）不在本分支。

### FR-6.2 失败（exit 1）

失败走既有 `fail(code, message, extra)`：stderr 唯一 JSON `{ "error": { "code", "message", ...extra } }`；**没有**独立的 `error.details` 对象——`TxError.extra` 键扁平并入 `error`。stdout 无成功 JSON。本 CR 不改该信封。

回灌相关失败码与并列字段：

| `error.code` | 并列字段（扁平） |
|---|---|
| `WRITEBACK_VERSION_UNASSIGNED` / `WRITEBACK_VERSION_MISMATCH` / `WRITEBACK_VERSION_INVALID` | 保持既有 `cr` / `crMd` / `input` / `inputReason` / `crMdReason`；INVALID 来自 backlog 时增加 `backlogReason` |
| `WRITEBACK_BACKLOG_VERSION_MISMATCH` | `cr`、`crMd`、`backlog`、`input` |
| `WRITEBACK_BACKLOG_ENTRY_DUPLICATE` | `cr`、`count` |
| `ENTRY_NOT_IN_BACKLOG` | `cr` |
| 既有其它 writeback/Tx 码 | 保持既有 extra，本 CR 不改 |

失败信封默认 **不含** `recoverCommand`（既有 `fail()` 不写该键，除非某 extra 自带）。调用方以 `error.code` 与并列字段断言，不以 stdout `phase` 断言失败。

# 4. 非功能需求

- **NFR-1 回归**：既有 writeback / archive / register / version-set / merge 回归继续通过；仅 FR-1 改写的 AC-14 unassigned 拒绝向量按 FR-4 更新，不得误伤 MISMATCH/INVALID 与 version-set 禁止 merging 的断言。
- **NFR-2 兼容边界**：不新增 Agent、Pipeline、状态、转换、review ledger、事务框架、CLI 子命令；允许新增 `WRITEBACK_BACKLOG_VERSION_MISMATCH` / `WRITEBACK_BACKLOG_ENTRY_DUPLICATE` 错误码；不放宽 `version-set` 允许状态；不改 `../multica/`；不手改 `_backlog.yml`/`cr.md`。
- **NFR-3 行尾纪律**：回灌读写先 `\r\n→\n`；跨行正则失败硬失败。
- **NFR-4 性能**：路径解析与字段比较保持入口常数时间，不引入网络调用。
- **NFR-5 安全**：不新增绕过 `crctl` 的账本写路径；回灌不得扩大 post-review 白名单。
- **NFR-6 冻结快照**：回灌后 `verifyReleaseSubjects` 仍按既有白名单通过（cr.md/_backlog 本就允许评审后变更）。若实现导致 `WRITEBACK_RELEASE_SUBJECT_DRIFT`，视为本 CR 缺陷。

# 5. 验收标准

AC-n 验证 FR-n。AC-2 含 2.1–2.3 三个可独立断言的子项（对应 FR-2 回灌、FR-2.1 冲突、FR-2.2 故障边界）。

- **AC-1**：对 merged 夹具（authority=`transaction-workspace`）三 stage：
  1. `cr.md=unassigned` + `--target-version 0.30`（或规范化等价 `v0.30`）→ 非版本错误，writeback 按既有成功路径完成或进入既有后续错误（不得为 `WRITEBACK_VERSION_UNASSIGNED`）；
  2. `cr.md=unassigned` + `--target-version unassigned` → `WRITEBACK_VERSION_UNASSIGNED`，六项零观察点；
  3. `cr.md=0.2` + `--target-version unassigned` → `WRITEBACK_VERSION_UNASSIGNED`；
  4. `cr.md=0.2` + `--target-version 0.9` → `WRITEBACK_VERSION_MISMATCH`；
  5. `--target-version n/a` → `WRITEBACK_VERSION_INVALID`；
  6. `cr.md=0.2` + `--target-version 0.2` → 与今日一致放行，不改版本字段。
- **AC-2**：回灌原子性与冲突/故障（merged 夹具，authority=`transaction-workspace`）。baseline 必须走 2.1 成功回灌；tasks/traceability 在 baseline 已回灌后各跑一次，只断言版本行无新 diff（不要求这两 stage 从 `unassigned` 再回灌）。
  - **AC-2.1 成功回灌**：authority `cr.md` 与 `_backlog.yml` 该条均为 `unassigned`，`--target-version 0.30` → 两账本 `target-version` 等于规范化 `0.30`；`prd.md`/`sdd.md`/`plan.md`/`TASK-*.md` 哈希与调用前全等；baseline 的 status 变迁与版本回灌在同一次 writeback commit 内。第二 stage 重跑不产生新的版本行 diff。
  - **AC-2.2 backlog 冲突（B-01）**：在 AC-1.1 回灌前置条件下，分别构造并断言拒绝 + FR-2.1 零写入观察点（含 `_backlog.yml` 字节级不变）：
    1. 条目 `target-version` 已是另一真实版本（如 `0.29`）→ exit 1，`error.code=WRITEBACK_BACKLOG_VERSION_MISMATCH`，`error.backlog=0.29`，`error.input=0.30`；
    2. 删除该 CR 条目 → `error.code=ENTRY_NOT_IN_BACKLOG`；
    3. 复制该 CR 条目使命中次数 >1 → `error.code=WRITEBACK_BACKLOG_ENTRY_DUPLICATE` 且 `error.count>=2`；
    4. 条目存在但 `target-version` 非法（如 `n/a`）→ `error.code=WRITEBACK_VERSION_INVALID`；
    5. 条目已是输入真实版本 `0.30`、cr.md 仍为 `unassigned` → **放行**：只回灌 cr.md，backlog 版本行无 diff。
  - **AC-2.3 故障点（B-02）**：夹具两账本均为 `unassigned`。用既有 `CRCTL_FAULT_POINT`，禁止发明新注入点：
    1. `writeback-after-apply` → 首次 exit≠0、`error.code=FAULT_INJECTED`；HEAD 无 writeback commit；同参重试 exit 0、`phase=complete`、origin 上恰好一个 `writeback baseline` commit，该 commit 同时含两账本 `0.30` 与 baseline 业务文件；
    2. `writeback-after-commit` → 同参重试不新增 commit（`git log` 中 `writeback baseline` 恰好 1 条），`phase=complete`，两账本版本行在该唯一 commit 内；
    3. `writeback-after-push` → 同参重试 exit 0、`phase=complete`、`commit` 等于中断前 journal 已记录的 sha、origin 不新增 commit、两账本保持该 commit 映像（`changed` 沿用既有 `did && !wasComplete`，本项不以 `changed` 为唯一断言）。
- **AC-3**：构造「requirement worktree `cr.md` 与 txws `cr.md` 的 `target-version` 不一致」的 merged 夹具。守卫必须以 txws 值为准：若 txws=`unassigned` 且输入=真实版本则放行并只回灌 txws；worktree 文件内容不变。不得出现只改 worktree、txws 仍为 `unassigned`。`code-approved` 夹具上 MISMATCH 仍优先于 `WRITEBACK_STATE_MISMATCH`。
- **AC-4**：`writeback-tx.test.mjs` 不再断言「unassigned cr.md + 真实输入 → UNASSIGNED」；`crctl.test.mjs` 含 FR-1 表的正负向量且 `node --test` 通过。CR-2026-057 合入的其它 AC-14 观察点（candidate/journal 零痕迹）在拒绝路径上保持。
- **AC-5**：`README.md` 守卫描述与 FR-1 一致；`git grep` 在 tools 仓人读入口不再把「任一侧 unassigned 一律拒绝」写成现行规则（测试夹具字符串除外）。
- **AC-6**：CLI 信封（B-03）。公共 `crctl writeback-apply`（非仅库函数返回值）：
  1. AC-2.1 首次成功：exit 0；stdout JSON `op=writeback-apply`、`phase` 严格等于 `"complete"`、`changed=true`、`status=writing-back`（baseline）、`commit` 匹配 `^[0-9a-f]{40}$`；`files` 为数组且同时包含 `change-requests/{CR}/cr.md` 与 `change-requests/_backlog.yml`；`recoverCommand` 含规范化 `--target-version`；stderr 不可解析为 `{error:{code}}` 成功冲突信封；
  2. 同参第二次：exit 0，`phase=complete`，`changed=false`，`commit`/`files` 与首次相同（仍含两账本路径）；
  3. AC-2.2.1 失败：exit 1；stdout 无 `phase=complete` 成功对象；stderr `error.code=WRITEBACK_BACKLOG_VERSION_MISMATCH`，且 `error.backlog`/`error.input` 存在（扁平并入 `error`，不要求 `error.details`）。

# 6. 成功指标

上线后以 **CR-2026-057 一次完整 writeback→archive** 为第一度量（本 CR 合入主仓之后）：

1. `crctl writeback-apply CR-2026-057 --target-version 0.30` 三 stage 均不以 `WRITEBACK_VERSION_UNASSIGNED` 失败。
2. 057 归档后 authority/`cr.md`/`_backlog` 的 `target-version` 为 `0.30`；其冻结 prd/sdd/plan/tasks 仍为评审时的 `unassigned`。
3. 随后新注册且以真实版本登记的 CR，writeback 行为与本 CR 之前一致（两侧真实且全等即放行，无多余回灌）。

# 7. 范围排除

- 不把 `version-set` 放宽到 `merging`/`writing-back`，不允许真实版本互改或改回 `unassigned`。
- 不回灌、不改写冻结的 `prd.md`/`sdd.md`/`plan.md`/`TASK-*.md`。
- 不推进、不代跑 CR-2026-057 的 writeback/archive（057 保持 `merging` 直至本 CR 合入）。
- 不回写修复已归档 AIFI-14（CR-2026-056）历史产物。
- 不新增 Agent、Pipeline、状态机状态/转换、CLI 子命令、事务框架。允许 FR-2.1 两个新错误码。
- 不修改 `../multica/`。
- 不把 `docs/product/`、`docs/analysis/` 既有设计文档搬进 `specs/`。
- 不扩大 post-review 白名单，不放松 `verifyReleaseSubjects`。
- 不处理 AIFI-15 附件中除本拍板最小面以外的建议。
