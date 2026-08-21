---
id: CR-2026-050
title: Pipeline 流程优化 — 职责边界与契约漂移修复（先正确性后职责收敛，P0/P1/P2 单 CR）
summary: "对 ../tools/pipeline-templates/ 下 8 条 active Pipeline 的职责边界与契约漂移审计落地。P0：三条 CR Pipeline human approval 直接改受保护 review-annotations 指引；product-planning 竞品节点缺 updates-block/product-snapshot/confirmed；market-to-plan 的 planning-draft 缺必填 context/intent；competitive-radar 草稿不落盘却要求 reportPath 且 node-5 混调两 Skill。P1：approve/review/test/register/freshness 等节点复制 crctl 与 Skill 算法、遗漏 CR-ID 与 grant 模式。P2：章节清单/路径/索引/展示字段重复。单 CR 两阶段：阶段一修 P0 契约与受保护路径；阶段二收敛 P1/P2 重复（architecture-design→requirement-authoring→code-implementation→resume-cr→feature-writeback→规划类）。不新增事务框架、不改状态机/gates/crctl 深原语。最终建议与自检见 docs/analysis/pipeline流程优化.md §18-20。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-21T09:31:35+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-21T09:31:35+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-21T09:31:35+08:00"
target-version: tbd
source: "docs/analysis/pipeline流程优化.md"
origin: ""
status: tech-designing
created: "2026-08-21T09:31:35+08:00"
updated: "2026-08-21T11:25:52+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-21T09:31:35+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-21T09:31:35+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-21T09:31:35+08:00", reason: initial-assignment }
handover-history: []
---
