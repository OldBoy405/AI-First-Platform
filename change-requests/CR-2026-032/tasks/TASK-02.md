---
id: CR-2026-032-TASK-02
type: TASK
cr-ref: CR-2026-032
plan-ref: "change-requests/CR-2026-032/plan.md"
sdd-ref: "change-requests/CR-2026-032/sdd.md"
title: 实现 Archive 固定返回与幂等 Outbox
slug: archive-result-outbox
status: pending
estimate: 8h
depends-on: [CR-2026-032-TASK-01]
created: "2026-08-13T09:52:00+08:00"
---

# TASK-02 实现 Archive 固定返回与幂等 Outbox

## 1. 任务描述

实现 SDD v0.2.0 §2～§4 的 tools 核心能力，使 TASK-01 红测转绿。输入为现有 durable archive journal、`archiveCr()` 和 `emitOutboxEvent()`；输出为固定 `ArchiveResult`、必需 emitter fail-fast、origin confirmed 后 cleanup 前的 schema v1 archive outbox，以及失败 warning/幂等恢复。不得改 cleanup 删除算法、四账本内容、状态机、traceability gate 或 Multica 协议。

## 2. 涉及文件 / 模块

- tools：`skills/shared/crctl/scripts/lib/workspace-transactions.mjs`
- tools：`skills/shared/crctl/scripts/crctl.mjs`
- tools：`skills/shared/crctl/scripts/test/archive-tx.test.mjs`（仅完成 TASK-01 已冻结测试的实现适配）

## 3. 实现要点

- `archiveCr(ctx, input)` 在 CR-ID 校验后、获取 lock/创建 journal 前校验 `typeof input.emitArchiveEvent === 'function'`；缺失/非法抛 `TxError('ARCHIVE_EMITTER_REQUIRED', ...)`。
- 现有 `cmdArchive()` 是唯一生产调用点，必须传入：
  `emitArchiveEvent: ({cr, commit}) => emitOutboxEvent(ws, {event_kind:'archive', cr_id:cr, from_status:'writing-back', to_status:'archived', trigger:'cr-archive', commit_sha:commit, actor:identity(ws), dedup_name:'archive-'+cr+'-'+commit+'.json'})`。
- archive journal payload 新增 `outboxEmitted`，旧 journal 缺失按 false；仅原始 `payload.status==='writing-back'` 发送，rejected/withdrawn 不调用 emitter。
- 发送仅在 `payload.pushed===true`、origin classify confirmed 且 `payload.commit` 为最终 SHA 后进行，并位于 cleanup 前；remote rebuild 后读取更新后的 commit。
- emitter 返回非空文件名后将 `payload.outboxEmitted=true` 用现有 `saveJournal()` 持久化；返回 null 或抛错只追加 `{code:'EMIT_FAILED',event_kind:'archive'}` warning，保持 false 供 recoverCommand 重试。
- complete 早返回前也执行“如未发送则补发”判断，支持历史/失败 journal；cleanup-pending 续跑复用同一判断。
- 使用局部 `result(phase, changed, warnings, outbox)` helper 统一三个成功/待清理返回路径，字段固定取 journal：`commit`、`lastCleanupError??null`、`remaining??[]`、`preservedRefs??[]`、`recoverCommand`、`warnings`。
- `payload.pushed/complete` 但 commit 为空视为 journal 损坏，按既有 `TxError` 风格硬失败，不返回占位 SHA。
- 不新增 class/interface/factory、ACK ledger、topic、schema v2、第三方依赖或生产 fault point。

## 4. 验收条件

1. TASK-01 全部新增向量转绿，且 `node --test skills/shared/crctl/scripts/test/archive-tx.test.mjs` 退出 0。
2. 正常归档事件字段与 SDD §2.3 精确一致，commit 等于 origin 最终 archive SHA；remote rebuild 不留下旧 SHA 事件。
3. cleanup fault/dirty/outbox failure 都保持 authority 已发布；前两者按错误与资源保留区分，outbox failure 返回 warning 后可零新 commit 补发。
4. complete、cleanup-pending、预存 dedup 文件和 daemon 已采集后的重放不产生重复 Multica 投影；本地在待采集窗口至多保留一个确定性文件。
5. rejected/withdrawn 不调用 emitter，既有 `preservedRefs` 与 cleanup 行为无回归。
6. `git diff` 确认 `gates.json`、`dir-graph.yaml`、writeback traceability generator 和 Multica 仓均未改。

## 5. 完成标志

Archive 定向与受影响 crctl 测试通过；代码只落在三个白名单文件；接口和 journal 恢复语义与 SDD v0.2.0 一致；`tasks/_index.yml` 中 TASK-02 经 `crctl task done` 标记 done。

## 6. 接口契约

- **消费**：TASK-01 黑盒断言；现有 `archiveCr(ctx,input)`、`emitOutboxEvent(ws,event): string|null`、`saveJournal({path,journal})`。
- **产出**：
  - `archiveCr(ctx, {cr, specId?, workspace, emitArchiveEvent}) -> Promise<ArchiveResult>`；
  - `emitArchiveEvent({cr:string, commit:string}) -> string|null`；
  - `ArchiveResult` 字段精确为 SDD §2.2 所列固定集合，供 TASK-03 文档和 TASK-04 跨仓验证消费。
