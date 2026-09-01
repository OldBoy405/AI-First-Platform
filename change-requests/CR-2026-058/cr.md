---
id: CR-2026-058
title: writeback 版本守卫：cr.md unassigned + 真实版本放行并原子回灌
summary: "CR-2026-057 follow-up（tools 仓）：修订 guardWritebackVersion——cr.md=unassigned + 业务输入=真实版本 → 放行，并在 writeback 事务内原子回灌 authority 的 cr.md/_backlog 的 target-version；回灌只碰这两个评审后白名单文件，不碰冻结的 prd/sdd/plan/tasks。修订 CR-2026-057 AC-14 的 unassigned 拒绝断言为「cr.md=unassigned + 输入=真实版本 → 放行并回灌；两侧 unassigned 仍拒绝」。守卫的 cr.md 读取/回灌位置必须与 writeback authority 一致（merging/writing-back 为 txws，不得用 crWorktreePath 造成版本事实分裂）。本 CR 承接 0.30 发布面。不含 version-set 放宽、不含改冻结产物、不含推进 CR-2026-057 状态。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-09-01T13:00:50+08:00"
  development:
    id: Ray
    assigned-at: "2026-09-01T13:00:50+08:00"
  test:
    id: Ray
    assigned-at: "2026-09-01T13:00:50+08:00"
target-version: 0.30
source: AIFI-15
origin: ""
status: tech-design-review-pending
created: "2026-09-01T13:00:50+08:00"
updated: "2026-09-01T14:56:20+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-09-01T13:00:50+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-09-01T13:00:50+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-09-01T13:00:50+08:00", reason: initial-assignment }
handover-history: []
---
