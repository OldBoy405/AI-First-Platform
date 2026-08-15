---
spec-id: ai-first-platform
version: "0.20.3"
id: CR-2026-041-TASK-04
type: TASK
cr-ref: CR-2026-041
plan-ref: "change-requests/CR-2026-041/plan.md"
sdd-ref: "change-requests/CR-2026-041/sdd.md"
title: archive 证据门适配与 pre-authority 分流
slug: archive-evidence-gate-adapter
status: pending
estimate: 6h
depends-on:
  - CR-2026-041-TASK-02
created: 2026-08-15T22:05:40+08:00
---

# TASK-04 archive 证据门适配与 pre-authority 分流

## 1. 任务描述

在 `workspace-transactions.mjs` 新增薄适配 `runFixedEvidenceValidator`，复用既有 `WRITEBACK_GENERATORS.traceability` 固定脚本路径调用 `writeback-traceability.mjs --validate-evidence`；并改造 `archiveCr` 在 journal 创建前完成 pre-authority 证据门分流。对应 FR-04。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/lib/workspace-transactions.mjs`（唯一改动文件）

## 3. 实现要点

- `runFixedEvidenceValidator({ editRoot, cr, specId }) -> { ok: true } | throw TxError`：
  - 复用 `WRITEBACK_GENERATORS.traceability` 与既有 `path.resolve(.../writeback/scripts/writeback-traceability.mjs)` 路径解析（对齐 `prepareWritebackCandidate`）。
  - 用 `spawnSync(process.execPath, [script, '--validate-evidence', '--workspace', editRoot, '--cr', cr, '--spec', specId], { cwd: editRoot, encoding: 'utf8', shell: false })`。
  - 非零退出或 stdout 非 JSON 时，把 generator 结构化 error 映射为 `ARCHIVE_EVIDENCE_MISSING` / `ARCHIVE_EVIDENCE_DUPLICATE` / `ARCHIVE_EVIDENCE_PATH_INVALID` / `ARCHIVE_EVIDENCE_DRIFT` / `ARCHIVE_EVIDENCE_STATE`（复用既有 `generatorError` 风格或直接按 error code 映射）。
  - 不传 candidate/manifest/generator 外部路径；不创建 journal、不写 authority、不新增 crctl 子命令。
- `archiveCr` 分流（SDD §3.3）：
  - `acquireLock` 后，先 `loadExistingJournal({ root: ctx.installRoot, op: 'archive', cr, key: cr, inputDigest: sha256(cr + '|' + (specId || '')) })`（只读，不创建）。
  - `needsEvidence = !existing || !(p && (p.committed || p.pushed || p.phase === 'cleanup-pending' || p.phase === 'complete'))`（`p = existing?.journal?.archive`）。
  - `needsEvidence` 时：`opWs = resolveOperationalWorkspace(ctx, cr)`；若 `opWs.phase === 'writing-back'`：无 `specId` → `ARCHIVE_SPEC_REQUIRED`；否则 `runFixedEvidenceValidator({ editRoot: opWs.path, cr, specId })`。
  - rejected/withdrawn 无 writing-back milestone，跳过证据门。
  - 通过后才 `loadOrCreateJournal(...)`，沿用既有四账本流程（内部 status 判定不变）。
- 保留既有 `ARCHIVE_TASKS_PENDING` / `ARCHIVE_TRACEABILITY_MISSING` / `ARCHIVE_APPROVAL_MISSING` 前置校验不变。
- 失败语义：证据门失败释放 lock，零 journal/authority/审计写入，可补齐后同一命令重试。

## 4. 验收条件

1. 证据齐全的 writing-back CR 归档成功；证据缺失/漂移/路径互换/verdict 非 pass 时归档失败且 `.crctl/transactions/archive-*` 无新 journal。
2. pre-authority 分流：已 commit/push 或 cleanup-pending/complete 的 journal 重放跳过证据门；rejected/withdrawn 跳过。

## 5. 完成标志

`node archive-tx.test.mjs`（证据门 + 分流用例）通过；手动归档一个证据缺失 CR 验证零 journal 残留。

## 6. 接口契约

- **消费**：TASK-02 的 `--validate-evidence` 模式；`durable-tx.mjs` 的 `acquireLock`/`loadExistingJournal`/`loadOrCreateJournal`/`saveJournal`；既有 `resolveOperationalWorkspace`、`WRITEBACK_GENERATORS`、`spawnSync`、`TxError`。
- **产出**：`runFixedEvidenceValidator({ editRoot, cr, specId }) -> { ok: true } | throw TxError(code)`（`archiveCr` 内部消费）。
