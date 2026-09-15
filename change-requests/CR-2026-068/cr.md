---
id: CR-2026-068
title: CR-P2：plan/TASK 返工成本与执行前提
summary: "降低 upstream 返工成本并提前声明执行前提：upstream SDD 重新批准后 write-dev-plan 以新旧 SDD delta 与同轮未闭合 plan blockers 为输入，在同一份 plan 上只重算受影响章节、稳定表行、证据与回滚（未受影响内容保留）；write-dev-tasks 的『重新生成』原位改写为 delta 重算 + 依赖闭包同步 + 未受影响 TASK 保留；证据命令必须可执行且观测面覆盖 AC 声称面；回滚单元必须包含受影响下游依赖闭包；plan 侧声明环境 owner、建立方式、可获得性与 readiness（复用既有 cmd-NN，不破坏两张稳定表双向唯一映射），dev-start 只确认静态前提，implement 侧在首个环境依赖 TASK 前执行即时 readiness。不新增 Pipeline 环境节点（节点数保持 5/4/12）、不改 review-route 枚举与 replayNodes、不改 upstream attempts 账本、不新增账本字段、评审维度或观测指标。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-09-15T19:58:42+08:00"
  development:
    id: Ray
    assigned-at: "2026-09-15T19:58:42+08:00"
  test:
    id: Ray
    assigned-at: "2026-09-15T19:58:42+08:00"
target-version: 0.41
target-spec-id: ai-first-platform
source: AIFI-31
origin: ""
status: tech-design-reviewed
created: "2026-09-15T19:58:42+08:00"
updated: "2026-09-15T22:00:30+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-09-15T19:58:42+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-09-15T19:58:42+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-09-15T19:58:42+08:00", reason: initial-assignment }
handover-history: []
---
