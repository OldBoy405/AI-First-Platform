---
id: CR-2026-004
title: P2 三模式聊天 D1 — Team Agent 共享队列容量上限（容量校验 · owner/admin 插队 · 排队项撤回）
summary: >-
  P2 三模式聊天交互设计（docs/product/P2-三模式聊天交互设计.md）§11 唯一待建项 D1：
  agent_task_queue 表与 claim SQL 语义已有（P0），缺容量上限与插队规则这层业务逻辑。
  交付：① 队列达配置上限（默认 50）时非 owner/admin 入队被拒、前端输入区禁用提示；
  ② owner/admin 不受上限限制且 claim 时优先；③ 上限按 project 可配置；
  ④ 用户撤回自己的排队项（软删除留审计痕迹），槽位释放经既有 WS 通道实时广播。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-07-31T23:25:40+08:00"
  development:
    id: Ray
    assigned-at: "2026-07-31T23:25:40+08:00"
  test:
    id: Ray
    assigned-at: "2026-07-31T23:25:40+08:00"
target-version: "0.12"
source: "docs/product/P2-三模式聊天交互设计.md §11 交付切分 D1"
status: task-breakdown
created: "2026-07-31T23:25:40+08:00"
updated: "2026-07-31T23:25:40+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-07-31T23:25:40+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-07-31T23:25:40+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-07-31T23:25:40+08:00"
    reason: initial-assignment
handover-history: []
---
