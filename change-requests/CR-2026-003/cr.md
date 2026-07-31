---
id: CR-2026-003
title: P1 治理核心修补 — embedded 事件幂等键碰撞 + 归档 CR 失去自愈能力
summary: >-
  CR-2026-002 归档收尾核对时发现两个真缺陷：① cr_sync_event 幂等键
  (cr_id, commit_sha, event_kind) 在 --embedded 模式下因 commit_sha 为空串而互相碰撞，
  同一 CR 连续两次 embedded advance 时第二条 status 事件被 ON CONFLICT DO NOTHING 静默丢弃；
  ② reconcile 只读 change-requests/_backlog.yml，而归档的 CR 已被移出 backlog 进 _history.yml，
  导致 archived 状态的 CR 永久失去对账自愈能力（CR-2026-001/002 目前均卡在
  status=writing-back / needs_reconcile=true，与真实 archived 状态不符）。本 CR 修复这两处并
  收敛两条历史脏投影行。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-07-31T20:20:07+08:00"
  development:
    id: Ray
    assigned-at: "2026-07-31T20:20:07+08:00"
  test:
    id: Ray
    assigned-at: "2026-07-31T20:20:07+08:00"
target-version: "0.11.1"
source: "CR-2026-002 归档收尾核对（change-requests/CR-2026-002/traceability.yml process-deviations 之外的新发现）"
status: code-reviewing
created: "2026-07-31T20:20:07+08:00"
updated: "2026-07-31T20:20:07+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-07-31T20:20:07+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-07-31T20:20:07+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-07-31T20:20:07+08:00"
    reason: initial-assignment
handover-history: []
---
