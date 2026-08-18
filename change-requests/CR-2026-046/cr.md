---
id: CR-2026-046
title: CR 合并与新注册 Worktree 同步治理优化方案
summary: "修复两个缺口：新注册 CR 从远端 trunk 创建分支（missing 时 fetch 后重新分类），merge 完成后 best-effort 快进本地主 checkout。不做新事务框架/账本/状态分类。改动收敛于 crctl workspace-transactions.mjs + 两个测试文件。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-18T20:16:39+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-18T20:16:39+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-18T20:16:39+08:00"
target-version: tbd
source: "docs/analysis/CR合并与新注册Worktree同步治理优化方案.md"
status: tech-design-review-pending
created: "2026-08-18T20:16:39+08:00"
updated: "2026-08-18T20:39:08+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-18T20:16:39+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-18T20:16:39+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-18T20:16:39+08:00", reason: initial-assignment }
handover-history: []
---
