---
spec-id: ai-first-platform
version: "0.3"
id: CR-2026-030-TASK-04
type: TASK
cr-ref: CR-2026-030
plan-ref: "change-requests/CR-2026-030/plan.md"
sdd-ref: "change-requests/CR-2026-030/sdd.md"
title: 实现签名 reject 权威回退与幂等
slug: signed-reject-rollback
status: pending
estimate: 12h
depends-on: [CR-2026-030-TASK-03]
created: "2026-08-11T02:34:00+08:00"
---

# TASK-04 实现签名 reject 权威回退与幂等

## 1. 任务描述

落实 SDD §2.6、§3.7、§4.8～§4.10：approve/reject 共用 Ed25519 grant v1 完整验证；合法 reject 复用 `REJECT_ROLLBACK` 与状态机完成回退；仅权威 commit 成功后返回业务 decline。approve/reject 紧邻结果态重放必须再次验签并证明结果账本已在 HEAD。

## 2. 涉及文件 / 模块

- tools：`skills/shared/crctl/scripts/crctl.mjs`
- tools：`skills/shared/crctl/scripts/test/crctl.test.mjs`

## 3. 实现要点

- 提取 `validateGrantEnvelope()` 与不直接打印的 `performAdvance()`，保持 public dispatch 和 grant v1 envelope 不变。
- reject 跳过 approve passCondition，但仍校验 schema、decision、CR/stage、当前状态、evidence digest、key 与 signature。
- fresh reject 只在 `performAdvance()` 返回 `committed=true` 后输出 `APPROVAL_DECLINED_ROLLED_BACK/changed=true`；commit 失败为 `ADVANCE_COMMIT_FAILED` 且无 status outbox。
- `assertResultLedgersCommitted()` 使用无 audit 的受控只读 Git 状态：approve 检查 `approval.yml + cr.md`，reject 检查 `cr.md`。
- reject 不写 approval section，不传播未签名 reason，不输出 rerunHint 或下一 Skill 文案。

## 4. 验收条件

1. 四个 stage 的 approve grant 保持成功；四个 stage 的合法 reject 使用各自权威 trigger 回退并返回统一业务结果。
2. 伪造、跨 CR/stage、evidence drift、错误 key/signature/state 全部零业务写入。
3. 成功提交后的 approve/reject 重放返回 `changed=false`，且不重复 audit、commit 或 outbox。
4. approve/reject commit failure 后重放同 grant 返回 `GRANT_STATE_UNCOMMITTED`，不得误判幂等成功；HEAD/audit/outbox 不增加。
5. 非邻接状态或 approve 持久字段不一致返回 `GRANT_STATE_MISMATCH`。

## 5. 完成标志

TASK-01 中 AC-17～AC-22 对应测试全部转绿，TTY 既有成功/拒绝行为无回归，`tasks/_index.yml` 中 TASK-04 标记 `done`。

## 6. 接口契约

- **消费**：`REJECT_ROLLBACK[stage] -> {to, trigger}`；现有 evidence digest、trusted key 与 Ed25519 验签 helper。
- **产出**：内部 `validateGrantEnvelope(...)`、`performAdvance(...) -> {committed, ...}`、`assertResultLedgersCommitted(paths)`；业务错误 `APPROVAL_DECLINED_ROLLED_BACK`，技术错误 `ADVANCE_COMMIT_FAILED`、`GRANT_STATE_UNCOMMITTED`、`GRANT_STATE_MISMATCH`。
