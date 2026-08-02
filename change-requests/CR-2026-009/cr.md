---
id: CR-2026-009
title: P2 三模式聊天 CR-D — D6 Discussion（discussion 容器 Issue + 纯人类多人聊天）
summary: >-
  Discussion 面（交付切分 v2 的 CR-D，小后端 + 前端）：
  ① B3 后端：discussion 容器 Issue（项目首次打开 Discussion 面时 lazily 创建，
  复用 CR-2026-006 已落地的 origin_type 容器模式与列表/看板/搜索隐藏过滤基建，
  新增 discussion 类型值）。
  ② 前端第三 tab：纯人类多人聊天，复用 comment-card.tsx（ActorAvatar +
  ReadonlyContent + ReactionBar + 附件）、reply-input.tsx、@提及 + 通知 + 订阅
  基础设施；成员变更等行内系统条。输入区无模式/模型下拉、无上下文用量——纯人类
  输入仅留 @（CodeBanana 实证，切分文档 §0.1）。
  验收红线：Discussion 消息不产生任何 agent_task_queue 行（除非 CR-G 的 DC 被显式
  激活）；容器 Issue 不出现在 Issue 列表/看板。CR-G（DC + 合并转发）依赖本 CR。
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
target-version: "0.16"
source: "docs/product/P2-三模式聊天窗口主体-交付切分.md v2（d7e4ece）CR-D"
status: writing-back
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
