---
id: CR-2026-045-TASK-12
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: "review-record 评审证据 outbox 同步"
slug: review-record-review-evidence-outbox
status: pending
estimate: 3h
depends-on:
  - CR-2026-045-TASK-11
created: 2026-08-18T18:39:17+08:00
---

# TASK-12 review-record 评审证据 outbox 同步

## 1. 任务描述

修复 `crctl review-record`：canonical review annotation 写入成功后，review outbox 事件必须携带当前 stage 声明的完整 evidence snapshot，使 daemon/server 投影和后续 signed grant 使用同一份评审证据。不得新增 digest 算法或让 Agent、Skill、Pipeline 重算证据。

## 2. 涉及文件 / 模块

- `skills/shared/crctl/scripts/crctl.mjs`
- `skills/shared/crctl/scripts/test/crctl.test.mjs`
- `server/internal/governance/crsync.go`（仅在现有接收契约缺测试时补测试）
- `server/internal/governance/approval_test.go` 或相关 crosscheck 测试

## 3. 实现要点

- 复用 `collectOutboxEvidence(ws, cr, gates.approvalStages[stage])`。
- `review-record` 的 event `evidence` 与 canonical annotation 使用同一 stage 配置和 CRLF 规范化规则。
- 保留现有 `commit_sha=gitHeadSha(ws)`、payload blocker/attempt/subject 字段和 review commit-scan parity。
- 事件证据缺失或读取失败时沿用现有确定性行为，不静默改用其他 stage 证据。

## 4. 验收条件

1. tech-design review-record outbox 包含 `change-requests/{cr}/review-annotations/sdd.yml` 的 `sha256:<hex>` evidence，requirement/dev-plan/code stage 不回归。
2. server 接收后 `cr_sync_event.evidence` 保留该 snapshot；真实 grant crosscheck 使用 sdd.yml evidence，不再因缺 evidence 回退到陈旧 requirement snapshot。
3. tools `crctl` 测试全量通过，Go governance crosscheck 通过。

## 5. 完成标志

review-record evidence 单元/黑盒测试、server ingestion/crosscheck 测试通过，且 outbox 事件字段与 status/approve 路径保持一致。

## 6. 接口契约

- 消费：TASK-03/TASK-10 已有 `collectOutboxEvidence`、review event schema 和 `cr_sync_event.evidence` 接收字段。
- 产出：`review-record` 产生 `{event_kind: "review", evidence: Record<string,string>}` 的 canonical outbox 事件。
