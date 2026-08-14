---
id: CR-2026-016
title: P3 组织智能 CR-D — 场景工坊三视图（E8）
summary: >-
  P3 组织智能第四个 CR（依赖 CR-A 看板前端体系，E8 与 E2 同前端技术栈可并行）：
  场景工坊三视图——同一份数据按角色投影，零新增数据源，复用 packages/views 体系与
  既有 API。① 需求工坊 /workshop/requirement（PM/需求方）——我相关的 CR 按 16 态
  分组（cr 投影）+ 待我审批卡片（approval_record pending）+ PRD 快捷入口 +
  /需求 斜杠命令入口（P2 §6.1）。② 质量中心 /workshop/quality（QA/Tech Lead）——
  治理板块四+一指标（门禁一次通过率/证据漂移/追溯完整率/越权尝试）+ 当前 blocker
  列表（pipeline_node_run blocked）+ drift_finding 流（open 优先）+ 越权尝试趋势。
  ③ 效能驾驶舱 /workshop/dashboard（管理者）——即 CR-A 成熟度看板 + CR-B 交付效能
  板块 + AI 净价值叙事条（归入工坊概念，不重复开发）。设计约束：工坊是读侧 + 入口，
  一切写操作（审批、触发 pipeline）跳转到既有交互（审批卡、聊天窗），不开新的写通路
  ——保证权限与审计路径唯一。开发工坊 = 三模式聊天本身（P2 已交付，不重做）。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-04T06:54:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-04T06:54:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-04T06:54:00+08:00"
target-version: "0.23"
source: "docs/product/P3-组织智能设计.md §4（E8）"
status: withdrawn
created: "2026-08-04T06:54:00+08:00"
updated: "2026-08-04T06:54:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-04T06:54:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-04T06:54:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-04T06:54:00+08:00"
    reason: initial-assignment
handover-history: []
---
