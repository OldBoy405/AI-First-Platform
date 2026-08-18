---
spec-id: ai-first-platform
version: "0.20.6"
id: CR-2026-045-TASK-03
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: crctl review outbox 确定性 payload 扩充
slug: crctl-review-outbox-deterministic-payload
status: pending
estimate: 4h
depends-on:
  - CR-2026-045-TASK-01
created: 2026-08-17T20:39:31+08:00
---

# TASK-03 crctl review outbox 确定性 payload 扩充

## 1. 任务描述

扩充 `crctl review-record` 成功后写入的 review outbox event payload，投影它刚刚原子持久化的 canonical 事实：`attempt`、`blockers`、`reviewed_at`、`subject_sha256`。这是 B04 回修的最小落点——不新增命令、状态、账本或业务判断，只让现有唯一写者把已持久化事实投影完整。转绿 TASK-01 的 outbox 红测试。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`（review-record 成功后扩充 outbox payload）
- `skills/shared/crctl/scripts/test/crctl.test.mjs`（转绿红测试 + 回归）

## 3. 实现要点

- `attempt` 取 `--bump-attempt` 后 canonical annotation 的当前 attempt；`blockers` 为归一化字符串列表；`reviewed_at` 取同一 recordedAt；`subject_sha256` 为 subject 文件 CRLF→LF 规范化后的 SHA-256（与 `review-annotations/{stage}.yml` 已记录的 digest 同一算法）。
- 复用 `review-record` 已有的 canonical digest 计算路径，不新写第二套 digest 算法。
- 字段随现有 `event_kind=review` outbox 一并写出；不改命令 dispatch、CLI 参数、gates 或状态机。

## 4. 验收条件

1. TASK-01 的 outbox 红测试转绿：payload 含 `attempt`/`blockers`/`reviewed_at`/`subject_sha256`，且 digest 与 annotation 记录一致。
2. 既有 review-record 回归测试不新增失败（attempt 记账、traceability 投影、review-loop 级联不变）。
3. 旧消费者读取旧 payload 的行为不因新增字段被破坏（新增字段为增量，不删旧字段）。

## 5. 完成标志

outbox payload 扩充落地 + 红测试转绿 + 既有回归零新增失败。

## 6. 接口契约

- 消费：TASK-01 产出的 outbox 测试名。
- 产出：`event_kind=review` payload 新增字段 `attempt:number`、`blockers:string[]`、`reviewed_at:string`、`subject_sha256:string`；TASK-07 的 review 后置条件消费这些字段，TASK-10 锁定与 commit-scan 的 parity。
