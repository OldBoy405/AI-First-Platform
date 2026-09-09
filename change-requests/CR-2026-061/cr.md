---
id: CR-2026-061
title: Discussion 显式升级
summary: "提供 Discussion 到正式工作 Issue 的显式升级出口：用户选择消息和附件并显式执行「转为工作 Issue」后创建正式 Issue，保存来源 session/消息/附件引用，原消息与附件保持原归属；以规范化来源集合与项目级并发锁保证重复升级不产生重复 Issue，重试返回既有目标 Issue。「升级为 CR」只准备来源上下文并进入现有 requirement-register 流程，Multica 不写 CR 账本。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-09-07T11:57:18+08:00"
  development:
    id: Ray
    assigned-at: "2026-09-07T11:57:18+08:00"
  test:
    id: Ray
    assigned-at: "2026-09-07T11:57:18+08:00"
target-version: 0.34
target-spec-id: ai-first-platform
source: AIFI-17
origin: ""
status: code-reviewing
created: "2026-09-07T11:57:18+08:00"
updated: "2026-09-09T10:50:43+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-09-07T11:57:18+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-09-07T11:57:18+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-09-07T11:57:18+08:00", reason: initial-assignment }
handover-history: []
---
