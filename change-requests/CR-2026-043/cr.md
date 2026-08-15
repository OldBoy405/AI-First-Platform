---
id: CR-2026-043
title: Workspace 基线新鲜度与 CR Worktree 同步治理
summary: "落实独立 workspace freshness 治理：对每个 active repository 比较 CR worktree HEAD 与 fetch 后的 origin/{trunk}，新增 fresh/behind-clean/diverged/unknown 分层分类；behind-clean 提供显式可审计 --ff-only 同步；implement-code 前与 review-code 前接入 freshness gate，评审 gate 失败复用既有 reviewLoop 重放；复用现有 workspace resolver、durable-tx workspace operation、lock/journal/audit 与原生 Git ancestry/merge --ff-only，不新增第二套事务框架。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-15T23:59:36+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-15T23:59:36+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-15T23:59:36+08:00"
target-version: tbd
source: docs/analysis/workspace-baseline-freshness-governance.md
status: requirement-approved
created: "2026-08-15T23:59:36+08:00"
updated: "2026-08-16T00:21:44+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-15T23:59:36+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-15T23:59:36+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-15T23:59:36+08:00", reason: initial-assignment }
handover-history: []
---
