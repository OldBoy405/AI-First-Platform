---
id: CR-2026-008
title: P2 三模式聊天 CR-C — D5 Private Ask（chat_session 项目维度 + 项目内私聊面）
summary: >-
  Private Ask 面（交付切分 v2 的 CR-C，小后端 + 前端）：
  ① B2 后端：chat_session 加 nullable project_id 列 + 按 (project_id, creator_id)
  查询会话；Private Ask 会话按项目上下文隔离、与既有全局 1:1 chat 并存（迁移量小）。
  ② 前端第二 tab：绕开 use-chat-controller.ts（耦合全局 useChatStore 单例），直接组合
  纯 props 的 ChatMessageList + ChatInput + TaskStatusPill，sessionId 由
  project-chat-panel 自管。
  ③ 语义四差异沿设计稿 §4：个人独立队列、默认 Ask-only 只读（execenv 不给写）、
  仅本人可见、与 Team Agent 并行。
  隐私红线：单 socket 架构下消息永不进全工作区广播只能靠服务端 per-user 推送逻辑
  保证（前端过滤不算数，切分文档 §B WS 语义修正），是本 CR 首要验收对象；
  另需回归既有浮窗/全页 chat 不受 B2 迁移与新入口影响。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-02T10:00:39+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-02T10:00:39+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-02T10:00:39+08:00"
target-version: "0.15"
source: "docs/product/P2-三模式聊天窗口主体-交付切分.md v2（d7e4ece）CR-C"
status: requirement-approved
created: "2026-08-02T10:00:39+08:00"
updated: "2026-08-02T10:00:39+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-02T10:00:39+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-02T10:00:39+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-02T10:00:39+08:00"
    reason: initial-assignment
handover-history: []
---
