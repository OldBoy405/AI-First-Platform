---
id: CR-2026-027-TASK-03
type: TASK
cr-ref: CR-2026-027
plan-ref: "change-requests/CR-2026-027/plan.md"
sdd-ref: "change-requests/CR-2026-027/sdd.md"
title: approve 原子提交（approveAndAdvance + evidence override seam + assertCandidateStatus）
slug: approve-atomic-commit
status: pending
estimate: 12h
depends-on: ["CR-2026-027-TASK-01"]
created: "2026-08-09T23:35:00+08:00"
---

# TASK-03 — approve 原子提交（FR-8）

## 任务描述

将 `crctl approve` 的 approval 与 status 写入收敛为单次原子提交：TTY 与 `--grant` 共用内部 helper，候选证据在内存中完成 gate 复核与 cr.md 校验，任何失败零文件写入。

## 涉及文件 / 模块

- tools `skills/shared/crctl/scripts/crctl.mjs`（cmdApprove / approveWithGrant / casWriteMulti / controlledGit）
- tools `skills/shared/crctl/scripts/test/crctl.test.mjs`

## 实现要点（SDD §3.1）

1. 新增内部 `approveAndAdvance(ws, cr, gates, stage, stageCfg, opts)`：预检（state/transition/evidence/签名/passCondition/requireFiles）→ 内存生成 approval.yml 文本（复用 `writeApprovalSection` 行级生成）与 cr.md 新文本（status → `stageCfg.to`）→ 目标 gate 复核 → 两文件 `casWriteMulti` → `controlledGit` add 两文件 → 单次 commit → commit 成功后 `emitOutboxEvent(status)` → `auditLog`
2. evidence override seam：`readEvidenceDoc(ws, cr, rel, overrides)` 增加第 4 参；**key 用含 `{cr}` 占位符的规范相对路径，匹配发生在路径展开前**；`runGateChecks` 的 `opts` 增加 `evidence` 字段并透传给所有 readEvidenceDoc 调用点；`approveAndAdvance` 只传 `change-requests/{cr}/approval.yml`
3. 候选 cr.md 独立校验：新增 `assertCandidateStatus(crMdText, expectStatus)`——解析 frontmatter `status`，≠ `stageCfg.to` → `CANDIDATE_STATUS_MISMATCH` 硬失败（零写入）；**不假设 gate checker 消费 cr.md**
4. 调用顺序固定：内存生成 → runGateChecks(evidence 仅 approval.yml) → assertCandidateStatus → casWriteMulti
5. TTY 路径与 approveWithGrant 尾部收敛到 approveAndAdvance；拒绝路径不写批准段，继续走既有 REJECT_ROLLBACK 转换
6. 错误边界：预检失败零写入；CAS 冲突两文件均不写；commit 失败两文件共同留存、不发 status outbox、返回结构化恢复信息

## 验收条件

1. 四 stage（requirement/tech-design/dev-start/code）approve 后 approval.yml 与 cr.md 在**同一 commit**（`git show --stat <commit>` 含两文件）
2. 候选 approval 缺 `via`/签名 → `GATE_BLOCKED` 且零文件写入（断言工作区与 HEAD 无变化）
3. 候选 cr.md status ≠ 目标态 → `CANDIDATE_STATUS_MISMATCH` 且零文件写入
4. CAS 冲突（构造 hash 漂移）→ 两文件均不写
5. 拒绝路径走 reject 转换，不写批准段（AC-10）

## 完成标志

crctl.test.mjs 新增用例全绿（一次提交/GATE_BLOCKED/CANDIDATE_STATUS_MISMATCH/CAS/commit 失败/reject）；既有 approve 相关用例不回归（AC-8/AC-9/AC-10）。

## 接口契约

- 消费：TASK-01 产出的 tools worktree
- 产出：`approveAndAdvance(ws, cr, gates, stage, stageCfg, opts)`、`assertCandidateStatus(crMdText, expectStatus)`（错误码 `CANDIDATE_STATUS_MISMATCH`）、`readEvidenceDoc(ws, cr, rel, overrides)` 第 4 参、`runGateChecks` `opts.evidence`（TASK-06 的 archive 路径复用 casWriteMulti 不变；TASK-10 回归基于本产出）
