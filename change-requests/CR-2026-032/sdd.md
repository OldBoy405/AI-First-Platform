---
id: CR-2026-032-sdd
type: SDD
cr-ref: CR-2026-032
title: tools Archive 独立小修：cleanup 回显、正常归档 outbox、README 语义（TCA-010 收尾）技术设计
status: draft
created: "2026-08-13T09:38:00+08:00"
updated: "2026-08-13T09:44:00+08:00"
---

# SDD - tools Archive 独立小修

## 1. 架构概览

### 1.1 目标与约束

本设计承接 `CR-2026-032-prd`，只交付来源方案 Phase 1 / 分组 A / T02 的 ARC-03、ARC-04、ARC-05：

1. 将 archive journal 已有的 cleanup 错误与最终 commit 投影到固定返回契约；
2. 正常 `writing-back -> archived` 在 origin 确认后发送 Multica 已支持的 `archive` outbox；
3. 澄清终态 authority 发布与资源 cleanup 是两个阶段。

目标代码仓为 **tools 仓自身**。其 `ARCHITECTURE.md` 已存在，本 CR 直接引用，不修改。设计遵守以下硬不变量：

- `archiveCr()` 继续是 archive 发布、恢复和 cleanup 的单一深模块；不新增 archive 命令、事务框架或账本写入口；
- Git commit 与四账本是 authority，outbox 只是可重建投影；outbox/cleanup 失败不得反转已确认 commit；
- crctl 继续零第三方依赖，新增读入或摘要逻辑遵守 CRLF 规范化和硬失败纪律；
- cleanup 的 clean/dirty/unknown/ancestry/ref 保留算法不变；
- 不修改 `dir-graph.yaml`、`gates.json`、`controlled-shell/rules.json` 或 archive commit trailer；
- 不实施 ARC-02，不检查当前 CR milestone 的 tests/reviews/approval/merge 完整结构。

### 1.2 改动面与模块边界

| 仓库 | 文件 | 改动性质 | 职责 |
|---|---|---|---|
| tools | `skills/shared/crctl/scripts/lib/workspace-transactions.mjs` | 修改 | 固定 archive 返回字段；在 archive lock/journal 内协调首次 outbox 发送与恢复 |
| tools | `skills/shared/crctl/scripts/crctl.mjs` | 修改 | `cmdArchive()` 注入既有 `emitOutboxEvent()` adapter，构造 schema v1 archive 事件与 warning |
| tools | `skills/shared/crctl/scripts/test/archive-tx.test.mjs` | 修改 | archive 返回、事件、失败、幂等、提前终止和 ARC-02 排除的集成向量 |
| tools | `skills/cr/cr-archive/SKILL.md` | 修改 | 透传固定返回字段和 warning，不复制实现算法 |
| tools | `skills/shared/crctl/SKILL.md` | 条件性小修 | 用途表同步 archive 固定返回/outbox 语义，若现有一行已足够则不改 |
| tools | `README.md` | 修改 | 澄清 authority 已发布与 cleanup-pending 的业务语义 |
| multica | `server/internal/governance/crsync_test.go` | 修改 | 既有 schema 契约测试：archive 投影、run 完成、幂等 |
| multica | `CUSTOM.md` | 修改 | 按当前“代码改动”表顺延登记 CR-2026-032/TASK；测试文件也必须登记 |

Multica production code 保持零 diff。若实现期契约测试证明现有生产代码不能满足 FR-06，应停止并回到设计评审，不得在本 CR 静默扩展生产协议。

### 1.3 依赖方向

```text
cr-archive Skill / README
          |
          v
cmdArchive() in crctl.mjs
  |       \
  |        +--> emitOutboxEvent(ws, archive event v1)
  v
archiveCr(ctx, input, emitArchiveEvent)
  |
  +--> existing durable archive journal + archive lock
  +--> existing four-ledger write-set / commit / lease push
  +--> existing archiveCleanup()

.crctl/outbox/*.json
          |
          v
Multica daemon collector -> governance.SyncService
          |
          +--> cr_sync_event idempotency ledger
          +--> applyStatus(writing-back, archived, cr-archive)
          +--> complete feature-writeback pipeline_run
```

`workspace-transactions.mjs` 不反向依赖 CLI，也不导入 outbox 文件实现。它只接受一个由调用者提供的窄回调；具体 schema、identity、occurred_at、原子文件写仍留在 `crctl.mjs` 的既有 `emitOutboxEvent()` 中。

### 1.4 正常归档时序

```text
archiveCr acquire archive lock
  -> load/recover archive journal
  -> build/rebuild four-ledger archive commit
  -> lease push and confirm origin commit SHA
  -> if originalStatus == writing-back and outboxEmitted != true:
       emitArchiveEvent(final confirmed SHA)
       success -> journal.outboxEmitted=true; save journal
       failure -> append EMIT_FAILED warning; keep outboxEmitted=false
  -> archiveCleanup()
  -> return complete or cleanup-pending with the same fixed fields
```

事件发送位于 **origin confirmed 之后、cleanup 之前**。因此它不依赖可能被 cleanup 删除的 Transaction Workspace 或 CR worktree；唯一文件落点是传给 CLI 的 installation/knowledge-base workspace `.crctl/outbox/`。

## 2. 数据模型

### 2.1 Archive journal payload

在既有 `journal.archive` 上新增一个向后兼容布尔字段；旧 journal 缺失时按 false 解释：

```js
{
  cr: "CR-2026-032",
  phase: "pushed | cleanup-pending | cleanup-attempted | cleanup-failed | complete",
  status: "writing-back | rejected | withdrawn", // 原始状态，既有字段
  commit: "<final confirmed archive commit SHA>", // 既有字段，rebuild 时覆盖
  baseSha: "<lease base SHA>",                    // 既有字段
  pushed: true,                                   // 既有字段
  cleanupDone: false | true | null,               // 既有字段
  lastCleanupError: null | "<structured code>",   // 既有字段，当前未返回
  remaining: [],                                  // 既有字段
  preservedRefs: [],                              // 既有字段
  outboxEmitted: false | true                     // 新增
}
```

`outboxEmitted` 的语义是“本机 archive outbox 文件已由 `emitOutboxEvent()` 成功原子发布”，不是“Multica 已 ACK”。它只阻止同一 journal 在后续 cleanup 重放时主动生成第二份本地事件；服务端 exactly-once 仍由既有 `(cr_id, commit_sha, event_kind)` 唯一键保证。

约束：

- 仅原始 `payload.status === 'writing-back'` 使用该字段；rejected/withdrawn 永不发送且无需置 true；
- outbox 写失败保持 false，使下一次 `recoverCommand` 可重试；
- 远端前进触发 archive commit rebuild 时，在最终 SHA 确认前不得置 true；
- `phase=complete` 但 `outboxEmitted=false` 的历史/失败 journal，幂等重放仍应重试事件，然后固定返回，不新增 commit。

### 2.2 固定返回模型

所有 `phase=complete`、`phase=cleanup-pending` 和 complete 幂等重放统一返回：

```ts
type ArchiveWarning = {
  code: "EMIT_FAILED";
  event_kind: "archive";
};

type ArchiveRemaining = {
  kind: "txws" | "cr-worktree" | "remote-ref" | "local-ref";
  repo?: string;
  path?: string;
  ref?: string;
  why: "dirty" | "remove-failed" | "not-merged" | "delete-failed";
};

type ArchiveResult = {
  cr: string;
  txId: string;
  phase: "complete" | "cleanup-pending";
  status: "archived" | "rejected" | "withdrawn";
  changed: boolean;
  commit: string;
  lastCleanupError: string | null;
  remaining: ArchiveRemaining[];
  preservedRefs: string[];
  recoverCommand: string;
  warnings: ArchiveWarning[];
  outbox?: string; // 本次成功发送或命中确定性文件时的文件名；未发送/失败时省略
};
```

字段来源固定：

| 返回字段 | 唯一来源 |
|---|---|
| `commit` | `journal.archive.commit`，必须是 classify confirmed 后的最终 SHA |
| `lastCleanupError` | `journal.archive.lastCleanupError ?? null` |
| `remaining` | `journal.archive.remaining ?? []` |
| `preservedRefs` | `journal.archive.preservedRefs ?? []` |
| `recoverCommand` | `archiveCr()` 现有确定性命令生成 |
| `warnings` | 本轮 outbox adapter 返回失败时追加；其他路径为空数组 |
| `outbox` | 既有 `emitOutboxEvent()` 返回的文件名 |

不新增第二份 cleanup error 文件或事件 ledger。

### 2.3 Outbox schema v1

正常归档复用既有事件结构：

```json
{
  "v": 1,
  "event_kind": "archive",
  "cr_id": "CR-2026-032",
  "from_status": "writing-back",
  "to_status": "archived",
  "trigger": "cr-archive",
  "commit_sha": "<final confirmed archive commit SHA>",
  "actor": "<identity(ws)>",
  "evidence": {},
  "payload": {},
  "occurred_at": "<emitOutboxEvent generated time>"
}
```

文件名使用确定性 `dedup_name`：

```text
archive-<CR-ID>-<final-commit-sha>.json
```

SHA 已由 Git 约束为十六进制，不需要额外可逆编码。确定性文件名处理“文件写成功但 journal 标记前进程终止”的窗口：文件仍在时重放命中同名文件，不增加数量；文件已被 daemon ACK 删除时允许重建同名文件，Multica 的既有数据库唯一键消除重复投影。

### 2.4 Multica 持久化模型不变

不新增迁移或表字段。继续复用：

```text
cr_sync_event unique key = (cr_id, commit_sha, event_kind)
knownEventKinds["archive"] = true
apply("archive") -> applyStatus(...)
pipelineForStatus("writing-back" | "archived") = feature-writeback
archived -> completeRun(feature-writeback)
```

## 3. 接口契约

### 3.1 `archiveCr()` 内部接口

现有入口最小扩展为：

```ts
type EmitArchiveEvent = (input: {
  cr: string;
  commit: string;
}) => string | null;

archiveCr(
  ctx,
  {
    cr,
    specId?,
    workspace,
    emitArchiveEvent // 必需；cmdArchive 注入既有 emitOutboxEvent adapter
  }
): Promise<ArchiveResult>
```

实现可直接让回调返回 `string | null`，无需为单一 adapter 新建类、interface 文件或 factory。上面的类型仅用于冻结语义。

`archiveCr()` 在合法 CR-ID 校验之后、获取 archive lock/创建 journal 之前校验 `typeof emitArchiveEvent === 'function'`；缺失或非法以 `ARCHIVE_EMITTER_REQUIRED` 硬失败。该失败必须发生在 commit/push/账本/outbox 等任何 authority 或投影副作用之前。当前生产调用点仅 `cmdArchive()`，因此不保留“无 adapter 仍完成正常归档”的兼容分支。

调用顺序约束：

1. 入口 adapter 已通过 fail-fast 校验；
2. `payload.pushed === true` 且 origin classify confirmed；
3. `payload.status === 'writing-back'`；
4. `payload.outboxEmitted !== true`；
5. 回调参数中的 `commit` 必须等于当前 journal 最终 commit；
6. 回调成功返回非空文件名后，先写 `payload.outboxEmitted=true` 并 `save()`，再进入 cleanup；
7. 回调失败/抛错转换为 `warnings[{code:'EMIT_FAILED', event_kind:'archive'}]`，不抛出 archive 事务失败；
8. rejected/withdrawn 虽接收同一必需 adapter，但由原始状态条件保证不调用。

回调抛错也按发送失败处理，防止测试 adapter 或未来实现绕过 outbox 非阻断不变量。

### 3.2 `cmdArchive()` adapter

`cmdArchive()` 继续是唯一 CLI adapter：

```js
const result = await runTxAsync(archiveCr(ctx, {
  cr,
  specId,
  workspace: ws,
  emitArchiveEvent: ({ cr, commit }) => emitOutboxEvent(ws, {
    event_kind: 'archive',
    cr_id: cr,
    from_status: 'writing-back',
    to_status: 'archived',
    trigger: 'cr-archive',
    commit_sha: commit,
    actor: identity(ws),
    dedup_name: `archive-${cr}-${commit}.json`,
  }),
}));
```

`occurred_at` 继续由 `emitOutboxEvent()` 生成。`cmdArchive()` 不从已删除的 CR 文件读取 owner/status/commit，不自行解析 journal，也不重复判断 cleanup phase。

CLI 参数、dispatch、退出码保持不变：

```text
crctl archive <cr_id> [--spec-id <id>] --workspace <knowledge-base-main-checkout>
```

`warnings` 是 exit 0 的业务 warning，不新增错误码；cleanup-pending 仍 exit 0。

### 3.3 幂等与恢复契约

| 场景 | 事件行为 | 返回行为 |
|---|---|---|
| 首次正常 archive，发送成功 | 写一个确定性 archive 文件，journal 标记 true | complete/pending 固定字段，`warnings=[]` |
| cleanup-pending 续跑，已发送 | 不调用 adapter | 固定字段，不新增事件 |
| complete 幂等重放，已发送 | 不调用 adapter，不新增 commit | `changed=false`，固定字段 |
| outbox 写失败 | journal 保持 false | authority 不变，`warnings=[EMIT_FAILED]` |
| outbox 失败后重跑 | 重试同一确定性事件；成功后标 true | 不新增 archive commit |
| 文件写成、journal 标记前中断 | 重跑命中同名文件；若已被采集则服务端唯一键去重 | 不新增 authority commit |
| rejected/withdrawn | 永不调用 adapter | 固定字段，保留既有 `preservedRefs` |
| remote rebuild | 只在最终 confirmed SHA 上发 | `commit` 与事件 SHA 均为最终 SHA |

### 3.4 文档消费契约

`cr-archive/SKILL.md` 只列固定返回字段和动作：

- `commit`：已确认 authority SHA；
- `lastCleanupError`：cleanup 执行异常码或 null；
- `remaining` / `preservedRefs`：保守保留现场；
- `recoverCommand`：唯一允许的续跑入口；
- `warnings`：投影发送失败，不表示 archive authority 失败。

README 只表达业务阶段，不复制 journal phase、ref ancestry 或 clean 判定算法。

## 4. 关键算法与流程

### 4.1 统一返回构造

在 `archiveCr()` 内保留一个局部纯函数，所有成功/待清理返回路径复用：

```text
result(phase, changed, warnings=[], outbox=undefined):
  assert payload.commit is non-empty when payload.pushed/complete
  return {
    cr, txId,
    phase,
    status: payload.status == writing-back ? archived : payload.status,
    changed,
    commit: payload.commit,
    lastCleanupError: payload.lastCleanupError ?? null,
    remaining: payload.remaining ?? [],
    preservedRefs: payload.preservedRefs ?? [],
    recoverCommand,
    warnings,
    ...(outbox ? {outbox} : {})
  }
```

该 helper 只消除当前三个返回分支重复，不导出、不新建模块。`commit` 缺失属于 journal 形状损坏，必须以现有 `TxError` 风格硬失败，不得返回空字符串掩盖事实缺口。

### 4.2 Outbox 发送与 journal 标记

```text
emitArchiveIfNeeded():
  warnings = []
  outbox = undefined

  if payload.status != writing-back:
      return {warnings, outbox}
  if payload.outboxEmitted == true:
      return {warnings, outbox}
  if !payload.pushed or !payload.commit:
      hard fail TX_JOURNAL_INVALID

  try:
      outbox = emitArchiveEvent({cr, commit: payload.commit})
  catch:
      outbox = null

  if outbox:
      payload.outboxEmitted = true
      save(current phase) // 不改变 authority phase，只持久化标记
  else:
      warnings.push({code: EMIT_FAILED, event_kind: archive})

  return {warnings, outbox}
```

调用点有两个：

1. origin 首次 confirmed 后、`save('cleanup-pending')` 之前；
2. `payload.phase === 'complete'` 的早返回之前，用于恢复过去发送失败但 authority 已 complete 的事务。

cleanup-pending 重放会自然经过第一个调用点。发送失败不写 `outboxEmitted`，也不改变 `phase`。

### 4.3 Cleanup 返回

现有 cleanup 流程保持不动，只改变投影：

```text
before cleanup attempt:
  payload.lastCleanupError = null

archiveCleanup succeeds:
  payload.remaining = result.remaining
  payload.preservedRefs = result.preservedRefs

archiveCleanup/fault throws:
  payload.lastCleanupError = error.code || CLEANUP_FAILED
  save cleanup-failed

if remaining empty and lastCleanupError null:
  save complete
  return result(complete)
else:
  return result(cleanup-pending)
```

因此 dirty/unknown/ref-not-merged 只体现在 `remaining`，`lastCleanupError=null`；执行异常才产生非空错误码。下一次 cleanup attempt 开始前清空旧错误，成功后返回 null。

### 4.4 Outbox 失败注入

不新增生产 fault point。集成测试在 fixture installation workspace 中预建 `.crctl/outbox` 为普通文件，使既有 `fs.mkdirSync(dir, {recursive:true})` 失败，验证 `emitOutboxEvent()` 返回 null 和 audit `EMIT_FAILED`。测试结束后删除冲突文件并重跑同一 archive，验证事件补发且 commit 数量不变。

该方法覆盖真实文件系统失败路径，避免为一个测试新增环境变量或通用注入框架。既有 `archive-during-cleanup` fault point 继续覆盖 cleanup 异常。

### 4.5 Multica 契约测试流程

在 `governance/crsync_test.go` 复用当前数据库 fixture 和 `SyncService.ingest/apply` 测试模式：

```text
seed CR status=writing-back
seed active pipeline_run(pipeline_id=feature-writeback, status=running)
construct OutboxEvent v1:
  event_kind=archive
  from=writing-back
  to=archived
  trigger=cr-archive
  commit_sha=<fixed real-looking SHA>
ingest once
assert:
  cr.status == archived
  cr.projected_commit == commit SHA
  feature-writeback run == completed
  cr_sync_event count for key == 1
ingest same event again
assert event count still 1 and projection/run unchanged
```

必须在 `go test -v` 输出中看到目标测试实际 RUN/PASS；若 package `TestMain` 因数据库不可达整体 skip，不能把 exit 0 作为 AC-07 证据。

### 4.6 测试矩阵

| 向量 | 关键断言 | 覆盖 |
|---|---|---|
| tools adapter contract | 缺失/非函数 adapter 在 lock/journal/commit/push/outbox 前以 `ARCHIVE_EMITTER_REQUIRED` 零副作用失败 | FR-03, TD-BL-1 |
| tools happy path | 固定五字段；commit=origin trailer SHA；一个 archive outbox 字段精确 | AC-01/04 |
| tools preexisting dedup file | journal 标记 false 但确定性文件已存在时命中同名文件、补记 true，文件数量不增加 | AC-04, TD-SUG-1 |
| tools cleanup fault | pending、非空 lastCleanupError、真实 commit；重跑不增 commit/event | AC-02 |
| tools dirty worktree | remaining 有资源、lastCleanupError=null、现场保留；处理后 complete | AC-03 |
| tools outbox failure | exit 0；authority 已发布；warning 精确；重跑补发且零新 commit | AC-05 |
| tools complete replay | changed=false；固定字段；outbox 文件数量不增加 | AC-01/04 |
| tools rejected/withdrawn | 无 archive/status 新事件；preservedRefs 行为不变 | AC-06 |
| tools remote rebuild | 返回 commit 与事件 commit_sha 均等于最终 origin SHA | FR-01/03, R-03 |
| tools current trace fixture | 不新增严格 milestone 结构要求，既有可归档 fixture 继续通过 | AC-09 |
| Multica contract | known kind、合法转换、archived 投影、writeback run 完成、重复 key 幂等 | AC-07 |
| docs/contract | README/Skill 语义，无 cleanup 算法复制；lint-prompts enforce | AC-08/10 |
| Multica diff policy | production code diff 为空；CUSTOM.md 有 CR/TASK 追溯 | AC-11 |

## 5. 技术选型与替代方案

| 决策 | 采纳方案 | 否决方案 | 理由 |
|---|---|---|---|
| outbox 调用位置 | origin confirmed 后、cleanup 前 | cleanup 后在 `cmdArchive()` 发 | cleanup 可能已删 CR/transaction worktree；发送应依赖事务结果和 installation workspace |
| 发送依赖注入 | `archiveCr()` 接受一个必需的窄回调，入口 fail-fast | 可选回调或 lib 导入 CLI `emitOutboxEvent()` | 必需回调封闭 FR-03 不变量；同时保持 lib 不反向依赖 CLI，接口仍小 |
| 首次发送事实 | journal `outboxEmitted` + 确定性文件名 | 仅看 `result.changed` | cleanup 续跑也可能 changed；不能证明事件是否已发 |
| 端到端幂等 | 本地 journal/文件名 + Multica 既有唯一键 | 新建 outbox ACK ledger / exactly-once 协议 | 既有投影通道已接受 at-least-once，新增协议超范围 |
| 发送失败恢复 | warning + 重跑同一 archive | 回滚 archive commit或补偿 commit | 违反 Git authority 不变量，并可能制造更严重漂移 |
| cleanup 错误模型 | 返回 journal 既有错误码 | 新建 error 文件/错误表 | 第二事实源无必要 |
| Multica 验证 | 只加契约测试 | 新增 archive production 分支 | 现有 known kind、applyStatus、transition 和 run completion 已具备 |
| 测试 outbox 失败 | 文件系统冲突 fixture | 新生产 fault point | 用既有失败路径即可，最小改动 |
| ARC-02 | 保持现状 | 本 CR 同时收紧 traceability gate | generator 尚未产出完整结构，会阻断合法归档；按依赖留给 T10A |

## 6. FR 到技术实现映射

| FR | 技术落点 | 验证锚点 |
|---|---|---|
| FR-01 | §2.2 固定模型；§4.1 统一返回 helper | happy path、pending、complete replay、remote rebuild |
| FR-02 | §4.3 直接投影 `lastCleanupError`，区分异常与资源保留 | cleanup fault + dirty worktree |
| FR-03 | §2.3 schema v1；§3.1/3.2 adapter；§4.2 首次发送 | 正常 archive outbox 字段与 SHA、重放数量 |
| FR-04 | §3.3/§4.2 warning 和失败重试；authority 不回滚 | outbox 路径冲突 + 重跑补发 |
| FR-05 | §2.1 状态条件；§3.1 rejected/withdrawn 不调用回调 | 两类终态无 archive/第二 status 事件 |
| FR-06 | §2.4 既有模型；§4.5 Multica 契约测试 | archived 投影、run completion、数据库唯一键幂等 |
| FR-07 | §3.4 README/Skill 消费契约 | 文案评审 + lint-prompts |
| FR-08 | §1.1/§1.2 排除面；§4.6 当前 trace fixture | gates/generator 零 diff，既有归档 fixture 通过 |

覆盖率：8/8。

## 7. 安全、性能与兼容性

### 7.1 一致性与恢复

- archive lock 覆盖 outbox 判断、发送和 journal 标记，同进程并发不会双发；
- journal 保存使用既有原子 `saveJournal()`，不新建 WAL；
- “文件写成功、标记前崩溃”是 at-least-once 窗口，由确定性文件名和服务端唯一键共同闭合；
- outbox failure 不清除 journal，`recoverCommand` 可重试；
- `commit` 只在 confirmed 后暴露，remote rebuild 的旧 SHA 不进入事件；
- cleanup 删除条件完全不变，不因 outbox 成功而放宽资源删除安全条件。

### 7.2 安全

- 新事件不含 PRD、审批、路径、cleanup error 正文等敏感内容；只含既有 schema 字段；
- `actor` 继续由 `identity(ws)` 生成，不接受用户 flag；
- outbox 文件名只使用经 CR-ID/SHA 格式约束的值；
- 不修改审批、controlled-shell、状态机或 gate；
- Multica 测试代码和注释遵守英文规则，production code 零 diff。

### 7.3 性能

每个正常 archive 仅增加一次小 JSON 原子写和一次 journal 保存，复杂度 O(1)。幂等重放仅做布尔判断；不扫描 outbox 目录、不查询网络、不增加数据库调用。archive 主成本仍是现有 Git fetch/push/worktree cleanup。

### 7.4 兼容性

- CLI 命令和 flags 不变；返回只新增/固定字段，现有消费者可忽略；
- `archiveCr()` 是内部接口且当前只有 `cmdArchive()` 一个生产调用者；本 CR 要求该调用者同步传入必需 adapter，不提供无 adapter 兼容模式；
- 旧 archive journal 缺 `outboxEmitted` 时按 false，若为 writing-back complete journal，首次重放会补事件；
- rejected/withdrawn 结果也获得固定 `commit/lastCleanupError/warnings`，但事件行为不变；
- Multica schema v1、known kind、状态机、数据库结构不变；
- Node 标准库和现有 Go 测试工具链足够，不新增依赖。

## 8. 验证与交付边界

### 8.1 Tools 最小验证

```text
node --test skills/shared/crctl/scripts/test/archive-tx.test.mjs
node --test skills/shared/crctl/scripts/test/crctl.test.mjs
node skills/shared/crctl/scripts/check-skill-matrix.mjs
node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce
node -e "JSON.parse(require('node:fs').readFileSync('pipeline-templates/feature-writeback.pipeline.json','utf8'))"
```

实施期以仓库实际 package/script 名称为准；不得修改旧断言来掩盖失败。新增行为测试须先在旧实现上证明按预期失败，再实现至绿。

### 8.2 Multica 最小验证

```text
cd server
go test -count=1 -v ./internal/governance/ -run '<CR-2026-032 archive contract test name>'
```

必须确认输出含目标 test 的 `=== RUN` 与 `--- PASS`。随后按风险运行 governance/daemon 相关既有测试；数据库不可达导致 package skip 时记录为未验证，不得宣称通过。

### 8.3 Diff 守卫

- tools production diff 只允许 §1.2 列出的 archive 模块；
- Multica 只允许 `crsync_test.go`（或实现期核实后同职责的既有 governance test 文件）与 `CUSTOM.md`；
- Multica `server/internal/**/*.go` 非测试文件、migration、query/generated 文件 diff 必须为空；
- `gates.json`、`dir-graph.yaml`、writeback traceability generator diff 必须为空。

## 9. Prompt 采纳影响

本 CR 不新增或删除 `crctl.mjs` dispatch 分支，也不修改 `rules.json#protectedPaths.deny`，因此 `write-tech-design` 所定义的强制“Prompt 采纳影响”条件不触发。

仍需消除直接消费者的文案漂移：`skills/cr/cr-archive/SKILL.md` 输出补齐固定字段、warning 与 recoverCommand；这不是新命令采纳，而是既有 archive 接口文档同步。`feature-writeback.pipeline.json` 继续只调用同一 `cr-archive` Skill，无节点或参数变化。

## 10. 风险与残余

| 风险 | 控制 |
|---|---|
| R-01 cleanup 后工作树已删 | 事件在 cleanup 前从 journal 结果 + installation workspace 发送 |
| R-02 changed 导致重复发 | 不消费 changed；使用 `outboxEmitted` 与确定性文件名 |
| R-03 remote rebuild 使用旧 SHA | 只在 classify confirmed 后读取当前 `payload.commit` |
| R-04 commit-scan subject 不匹配 | 显式 outbox 是主路径；不改 commit subject，不依赖 fallback |
| R-05 Go package 假绿 | `-v` 核对目标 test 的 RUN/PASS；skip 记未验证 |
| outbox 文件被 ACK 后 journal 标记前崩溃 | 重跑可能重建同名文件，但数据库唯一键幂等，投影不重复；这是既有 at-least-once 边界 |
| journal 成功标记但 daemon 永久未消费文件 | daemon 保留/重试既有 outbox 文件；snapshot reconcile 是最终兜底，不在 archive 内另建 ACK 协议 |

残余工作明确归后续 CR：ARC-02/TRA-03/T10A、checkpoint、test record、traceability/feedback 和静态治理均不在本设计实施。

## 11. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-13 | v0.1.0 | Ray | 初始设计：冻结 archive 固定返回、journal `outboxEmitted`、origin-confirmed 后 cleanup 前显式 archive outbox、失败 warning/恢复、README/Skill 语义和 Multica test-only 契约；FR 覆盖 8/8，排除 ARC-02 |
| 2026-08-13 | v0.2.0 | Ray | 技术评审 attempt-1 回修 TD-BL-1：`emitArchiveEvent` 从可选改为必需，修正返回类型为 `string|null`，入口在任何副作用前以 `ARCHIVE_EMITTER_REQUIRED` fail-fast，删除静默跳过分支并补 adapter 零副作用测试；采纳 TD-SUG-1，增加确定性文件已存在但 journal 未标记的崩溃窗测试 |
