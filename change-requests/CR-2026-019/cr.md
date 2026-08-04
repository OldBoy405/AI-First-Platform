---
id: CR-2026-019
title: 治理工具链 — YAML 账本操作收敛为 crctl 子命令（P2：任务标 done / merge-commits 写入 / 归档移动）+ AC-9 演练入库
summary: >-
  CR-2026-012 收尾复盘 §3.2 的 P2 项（依附 T1-full 定型后立项）：当前任务 _index.yml 标 done、
  merge-commits[] 写入、backlog→history 归档移动这三个账本操作仍靠 Agent 手工编辑 YAML
  （转义事故高发区，CR-2026-012 一次坏脚本把 9 个冲突块提交进历史），本 CR 将其收敛为
  crctl 子命令（task done / merge-metadata / archive-move），保持 CAS + 审计日志 + 门禁的
  单一写入路径，不建独立脚本库。同时将 CR-2026-018 测试报告 §6 建议的 AC-9 merge-tree
  零冲突演练沉淀为入库测试（当前为会话内一次性脚本）。T1-full（CR-2026-018）已定型，
  前置依赖满足；主仓 _backlog.yml 已迁移 v2 布局，新 CR 天然新布局。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-04T16:00:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-04T16:00:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-04T16:00:00+08:00"
target-version: tbd
source: "docs/analysis/CR-2026-012-合并回写归档复盘.md §3.2 P2 + CR-2026-018 测试报告 §6"
status: requirement-approved
created: "2026-08-04T16:00:00+08:00"
updated: "2026-08-04T16:00:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-04T16:00:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-04T16:00:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-04T16:00:00+08:00"
    reason: initial-assignment
handover-history: []
---
