---
id: CR-2026-044
title: Tools 本地业务门禁、远端发布与人工审批确认方案
summary: "分离本地业务事实与远端发布事实：status/gate/review/approve 只读当前 Operational Workspace 与本地 CR worktree；checkpoint/merge/writeback/archive 才读取远端。merge 增加全仓 publication preflight，远端 requirement ref 缺失或滞后时保持 code-approved 并指向 checkpoint 恢复，真实本地漂移才回退 developing；四个 TTY 人工审批统一接受 trim 后大小写不敏感的 y|yes。不新增状态、账本、schema、公共命令、事务层或依赖。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-16T23:32:37+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-16T23:32:37+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-16T23:32:37+08:00"
target-version: tbd
source: docs/analysis/tools-local-worktree-gates-remote-publication-boundary.md
status: tech-design-review-pending
created: "2026-08-16T23:32:37+08:00"
updated: "2026-08-16T23:49:58+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-16T23:32:37+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-16T23:32:37+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-16T23:32:37+08:00", reason: initial-assignment }
handover-history: []
---
