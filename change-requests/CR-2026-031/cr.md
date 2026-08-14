---
id: CR-2026-031
title: crctl 执行层职责边界与 merge/workspace/writeback/archive 事务化（TCA-005/009/015/016 合并落地）
summary: "按 grilling 共识将 Agent/Pipeline/Skill/crctl/版本化脚本职责边界确立为架构不变量：crctl 独占状态/门禁/CAS/账本/审计与 Git 事务，新增 durable-tx 与 workspace-transactions 两个内部模块、公共 journal envelope、release snapshot、单一 register/merge/writeback-apply/archive 深原语；作为单一 CR 约 12 TASK 落地，本 CR 自身走旧流程，下一 CR 启用新协议。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-11T17:17:53+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-11T17:17:53+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-11T17:17:53+08:00"
target-version: tbd
source: docs/analysis/tools-tca-005-009-015-016-merge-workspace-optimization-plan.md
status: archived
created: "2026-08-11T17:17:53+08:00"
updated: "2026-08-11T17:17:53+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-11T17:17:53+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-11T17:17:53+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-11T17:17:53+08:00", reason: initial-assignment }
handover-history: []
---
