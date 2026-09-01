---
id: CR-2026-057
title: CR 全生命周期最小改造 — 评审闭合、范围冻结、覆盖矩阵与版本事实统一
summary: "基于 AIFI-14 全生命周期复盘，对现有 Skill / 模板 / crctl 做最小改造：优化 review 首轮完整性与 blocker 分级（P0-1）；SDD 审批后冻结批准范围供下游只读消费（P0-2）；PLAN 增加 AC/业务闭环覆盖矩阵（P0-3）；禁止把 merge/writeback/archive 建成交付 TASK（P0-4）；target_version 在注册阶段人工确定，禁止 tbd，未排期用 unassigned，writeback 只校验消费（P1-1）；收紧关键测试 skip 的 pass 语义（P1-2）；静态检查仅在同类问题重复失败且规则确定时下沉（P1-3）。不新增 Agent、Pipeline、状态、review ledger、事务框架。不含 AIFI-14 历史产物回写修复。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-31T17:13:10+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-31T17:13:10+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-31T17:13:10+08:00"
target-version: unassigned
source: AIFI-15
origin: ""
status: merging
created: "2026-08-31T17:13:10+08:00"
updated: "2026-09-01T21:55:03+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-31T17:13:10+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-31T17:13:10+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-31T17:13:10+08:00", reason: initial-assignment }
handover-history: []
---
