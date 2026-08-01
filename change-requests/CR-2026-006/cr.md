---
id: CR-2026-006
title: P2 三模式聊天 CR-A — 三 tab 窗口骨架 + Team Agent 消息流核心（D2+D3 核心）
summary: >-
  三模式项目群聊窗口的第一个 CR（交付切分 v2 的 CR-A，唯一硬前置）：
  ① D2 骨架——project-detail 主区新增 Issues|Chat 两个 tab（?tab= 深链），Chat tab 内为
  三模式 tab 条（Team Agent / Private Ask / Discussion，空态问候语 + 教程气泡），切换纯前端
  不重拉数据，输入草稿按 {projectId}:{mode} 独立持久化；Private Ask 与 Discussion 本 CR
  只交付空态占位（内容面归 CR-C/CR-D）。
  ② D3 核心——Team Agent 消息流最小闭环，落地 B1 方案甲：team-agent-chat 隐藏容器 Issue +
  薄发送端点（容量守卫→落 comment→enqueue，满队同步 429 project_queue_full，评论不落库）；
  消息渲染复用 issue-timeline/CommentCard/TimelineView（工具执行卡实时渲染），刷新后历史
  完整回放。队列条完整形态/停止/过滤开关留 CR-B。队列治理后端全量消费 CR-2026-004（D1）
  已交付能力，不再动。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-01T23:36:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-01T23:36:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-01T23:36:00+08:00"
target-version: "0.13"
source: "docs/product/P2-三模式聊天窗口主体-交付切分.md v2（d7e4ece）CR-A"
status: tech-design-review-pending
created: "2026-08-01T23:36:00+08:00"
updated: "2026-08-01T23:36:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-01T23:36:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-01T23:36:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-01T23:36:00+08:00"
    reason: initial-assignment
handover-history: []
---
