---
id: CR-2026-045-TASK-10
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: daemon commit-scan review payload parity
slug: daemon-commit-scan-review-parity
status: pending
estimate: 5h
depends-on:
  - CR-2026-045-TASK-03
created: 2026-08-17T20:39:31+08:00
---

# TASK-10 daemon commit-scan review payload parity

## 1. 任务描述

修复 daemon `buildReviewPayload` 的 commit-scan fallback，使其与 crctl outbox 产生同字段 review payload（B05 回修）：显式 stage→文件映射、CRLF→LF、scalar/结构化 blocker 归一化、digest/attempt 缺失硬失败。outbox 优先仍保留；两来源同一 commit 的 payload parity 由测试锁定。

## 2. 涉及文件 / 模块

- `server/internal/daemon/crevents.go`（`buildReviewPayload`：stage 映射、blocker 归一化、payload 字段补齐）
- `server/internal/daemon/crevents_test.go`（commit-scan-only、outbox-vs-scan parity、tech-design sdd.yml 取证）

## 3. 实现要点

- 显式 stage→文件映射：`requirement→requirement.yml`、`tech-design→sdd.yml`、`code→code.yml`（当前 fallback 按 `stage+".yml"` 取文件，tech-design 实际 canonical 文件是 `sdd.yml`）。
- 读取先 CRLF→LF，用现有安全 YAML 解析；blocker 兼容 canonical scalar 字符串与历史结构化对象，归一化为字符串列表。
- commit-scan 输出字段集合与 crctl outbox 完全一致：`stage/verdict/attempt/blockers/reviewer/reviewed_at/subject_sha256`。
- 旧 payload 缺任一 Core 字段时 projector 可维持旧 UI，但 Runner 以 `RUNNER_REVIEW_EVIDENCE_INCOMPLETE` fail closed（该判定在 TASK-07 消费侧）。

## 4. 验收条件

1. commit-scan-only 测试：tech-design 正确读取 `sdd.yml`，scalar 与 structured blockers 归一化一致。
2. outbox-only 与同一 commit 双来源 parity 测试通过，digest/attempt 缺失时硬失败不降级成空 review 或 pass。
3. 既有 review 投影回归测试不新增失败。

## 5. 完成标志

commit-scan 与 outbox payload parity 落地 + 三组断言通过 + 既有投影零回归。

## 6. 接口契约

- 消费：TASK-03 的 outbox payload 字段集合。
- 产出：daemon `buildReviewPayload` 输出与 crctl outbox 同字段的 review payload；TASK-07 的 review 后置条件消费 `attempt/blockers/reviewed_at/subject_sha256`，TASK-11 的 E2E 依赖可靠 review 证据。
