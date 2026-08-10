---
id: CR-2026-027
title: tools 流程优化 Phase 0+1 — 基线事实统一与正确性修复（状态机口径 27/49、approve 原子提交、TASK 归档门禁、archive 原子化、终态查询、review-record 深化）
summary: >-
  按《tools流程步骤优化v2》（2026-08-09 质询拍板）仅实施 Phase 0 基线统一与 Phase 1
  正确性修复，Phase 2+ 均为候选路线须另行确认。Phase 0：状态机口径统一为 27 条声明
  /49 条 wildcard 展开（修正 workspace AGENTS.md、tools ARCHITECTURE.md 等 25/47
  旧表述）、确认 crctl 单文件边界、修订 crctl 与 Pipeline 依赖描述、archive
  _index.yml 全生命周期轻量目录语义落地、tools 加入 workspace repositories 并删除
  merge-feature-branch 隐藏特例、删除旧方案 command module 与通用上下文命令描述、
  建立优化指标基线。Phase 1：crctl approve 两文件 CAS + 单次提交原子化（TTY/grant
  共用 helper）、archived TASK 完成门禁（缺文件/空数组不得解释为 no-task）、
  archive 事件与 backlog/history/index 同一 CAS 原子移动（收件人复用三角色 owners、
  普通 inbox-emit 空 --to 硬失败）、终态只读 status/next 查询（不新增命令）、
  review-record 输出 files/attempt/route/repairTarget 并删除四个 review Skill 的
  traceability 二次读取。验证按 §6.6 五项最小清单（diff-check、pipeline JSON
  parse、crctl tests、lint-prompts enforce、两项 grep）。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-09T22:06:44+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-09T22:06:44+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-09T22:06:44+08:00"
target-version: tbd
source: "docs/analysis/tools流程步骤优化v2.md（质询：docs/analysis/tools流程步骤优化v2-质询记录.md）"
status: writing-back
created: "2026-08-09T22:06:44+08:00"
updated: "2026-08-09T22:06:44+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-09T22:06:44+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-09T22:06:44+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-09T22:06:44+08:00", reason: initial-assignment }
handover-history: []
---
