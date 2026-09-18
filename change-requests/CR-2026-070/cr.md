---
id: CR-2026-070
title: Agent Skill 路由与 Pi bash 默认超时：评审无限阻塞最小治理
summary: "针对 AIFI-32 / CR-2026-069 中两次质量评审因 Agent 未使用 Runtime 已发现 Skill、转而执行 find /，且 Pi bash 未显式传 timeout 时可无限等待的问题，实施两项最小治理：在 Multica 单一共享 Skills brief 中要求 Agent 直接使用 Runtime 原生发现的 Skill、缺失时技术中止；在 Pi 内置 bash 的现有 timeout 解析点增加 300 秒默认值，复用既有 setTimeout、AbortSignal、错误返回和跨平台 killProcessTree()。不新增 Skill Locator、Shell Guard/parser、错误码、metrics、数据库、sidecar、Pipeline 节点、账本或事务框架，不修改已归档 CR-2026-069 的 OutputGuard 合同。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-09-18T09:05:26+08:00"
  development:
    id: Ray
    assigned-at: "2026-09-18T09:05:26+08:00"
  test:
    id: Ray
    assigned-at: "2026-09-18T09:05:26+08:00"
target-version: 0.43
target-spec-id: ai-first-platform
source: AIFI-33
origin: ""
status: requirement-approved
created: "2026-09-18T09:05:26+08:00"
updated: "2026-09-18T10:05:43+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-09-18T09:05:26+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-09-18T09:05:26+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-09-18T09:05:26+08:00", reason: initial-assignment }
handover-history: []
---
