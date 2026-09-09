---
id: CR-2026-062
title: Team Agent 和 Private Ask 发送框 UI 优化
summary: "在不改变业务语义的前提下，将 Team Agent 与 Private Ask 项目聊天发送框的布局和视觉体验对齐普通非项目聊天：复用 CHAT_GUTTER/CHAT_COLUMN 对齐与单一输入 surface，Model Picker/Thinking Mode 控件作为底部工具栏控件接入（仍调用会话配置接口、不改 Agent 配置），附件预览/上传中/发送中/停止/失败/空态视觉一致，Web 与 Desktop 共享组件适配；不新增 API、数据库字段、任务快照或数据模型，不改变 draft/attachment/send/stop/retry 业务行为。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-09-09T15:11:07+08:00"
  development:
    id: Ray
    assigned-at: "2026-09-09T15:11:07+08:00"
  test:
    id: Ray
    assigned-at: "2026-09-09T15:11:07+08:00"
target-version: 0.35
target-spec-id: ai-first-platform
source: AIFI-18
origin: ""
status: tech-design-review-pending
created: "2026-09-09T15:11:07+08:00"
updated: "2026-09-09T21:42:14+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-09-09T15:11:07+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-09-09T15:11:07+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-09-09T15:11:07+08:00", reason: initial-assignment }
handover-history: []
---
