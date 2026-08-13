---
id: CR-2026-032-TASK-01
type: TASK
cr-ref: CR-2026-032
plan-ref: "change-requests/CR-2026-032/plan.md"
sdd-ref: "change-requests/CR-2026-032/sdd.md"
title: 建立 Archive 固定返回与 Outbox 失败优先测试
slug: archive-contract-red-tests
status: pending
estimate: 6h
depends-on: []
created: "2026-08-13T09:52:00+08:00"
---

# TASK-01 建立 Archive 固定返回与 Outbox 失败优先测试

## 1. 任务描述

按 SDD v0.2.0 §4.6 在 tools 既有 archive 集成测试中冻结 ARC-03/04 的黑盒契约。输入是当前 `archiveCr()`、`cmdArchive()` 与 `archive-tx.test.mjs` fixture；输出是在旧实现上稳定失败、且能精确定位缺口的测试向量。不得新增测试框架、生产 fault point、事件 schema 或 ARC-02 严格 gate 测试。

## 2. 涉及文件 / 模块

- tools：`skills/shared/crctl/scripts/test/archive-tx.test.mjs`
- tools：`skills/shared/crctl/scripts/test/crctl.test.mjs`（仅当 CLI JSON/outbox helper 的窄断言无法放在 archive fixture 时追加）

## 3. 实现要点

- 扩展 happy path：固定断言 `commit`、`lastCleanupError=null`、`remaining=[]`、`preservedRefs=[]`、`recoverCommand`、`warnings=[]`，并验证 commit 等于 origin 上带 `AI-First-Op: archive` trailer 的最终 SHA。
- 增加必需 adapter 测试：直接调用 `archiveCr(ctx, input)` 时缺失/非函数 emitter 必须以 `ARCHIVE_EMITTER_REQUIRED` 在 lock、journal、账本、commit、push、outbox 等任何副作用前失败；断言 archive journal 目录未创建。
- 正常 `writing-back -> archived` 只产生一个 `event_kind=archive` 文件，精确断言 schema v1 六个业务字段和真实 commit SHA。
- 覆盖 `archive-during-cleanup`：返回 pending、非空 `lastCleanupError`、真实 commit/recoverCommand，重跑只续 cleanup。
- 覆盖 dirty worktree：`remaining` 非空而 `lastCleanupError=null`，现场零删除。
- 用 `.crctl/outbox` 文件系统冲突制造 `emitOutboxEvent()` 失败，断言 exit 0、`warnings[{code:'EMIT_FAILED',event_kind:'archive'}]`、authority 不回滚；移除冲突后重跑补发且零新 commit。
- 覆盖确定性文件预先存在但 journal `outboxEmitted=false` 的窗口：重跑命中同名文件并补记，文件数量不增加。
- rejected/withdrawn 不产生 archive 或第二个 status 事件；complete replay 不新增 commit/outbox；remote rebuild 使用最终 confirmed SHA。
- 保留当前 traceability fixture，不增加 milestone tests/reviews/approval/merge 结构要求。

## 4. 验收条件

1. 新增向量在 TASK-02 实现前按预期失败，失败点分别对应固定返回、必需 emitter、正常 archive outbox、warning 或幂等缺口；既有测试仍可运行。
2. 每个事件断言读取实际 outbox JSON，验证 `event_kind/archive`、`from_status/writing-back`、`to_status/archived`、`trigger/cr-archive`、`commit_sha/final SHA`，不只检查文件数。
3. cleanup fault 与 dirty pending 能通过 `lastCleanupError` 的非空/null 精确区分，并都返回同一可执行 archive recoverCommand。
4. outbox failure/retry、complete replay 和预存 dedup 文件三类重放均断言 origin commit 数不增加。
5. rejected 与 withdrawn 均断言无 `archive`/第二终态 `status` 文件，`preservedRefs` 既有行为保持。

## 5. 完成标志

红测证据与 SDD 缺口一一对应，既有断言无删除或放宽，无 production 文件改动；`tasks/_index.yml` 中 TASK-01 经 `crctl task done` 标记 done。

## 6. 接口契约

- **消费**：现有 `makeWritebackFixture()`、`runCrctl()`、`originMasterCount()`、archive fault point `archive-during-cleanup`；SDD §2.2 `ArchiveResult` 与 §2.3 outbox schema v1。
- **产出**：供 TASK-02 转绿的黑盒测试；不导出 production 函数，不创建新的 fixture 框架。
