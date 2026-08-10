---
id: CR-2026-030
title: tools TCA-001～004 最小优化 — cr-init 三 Owner 注册契约 + owner-set 正式移交 + grant reject 验证回退 + review-dev-plan 精确 trigger / R7 字面量校验
summary: "按《tools-tca-001-004-optimization-plan.md》（核对基线 ../tools@cab3663e224c7198d954b4d25bee5f4a8803a452、../multica@c8c96e56a4bae1a2fb84c5700cffec174631ef74）实施 TCA-001～004 最小修复，让现有入口兑现既有契约：① cr-init 显式接收并一次写入三角色 Owner，registration commit 成功后才以真实 SHA 产生 status+owners 注册事件，worktree-path 增加 canonical branch；② owner-set 收敛为正式移交受控账本原语，handover-cr 唯一业务入口，resume-from-remote 不再改 Owner，add/commit 失败按 CAS 快照回滚；③ 复用 v1 签名 grant，reject 完整验证后走状态机既有回退并返回 APPROVAL_DECLINED_ROLLED_BACK，approve/reject 紧邻结果态幂等；④ review-dev-plan 修正精确 trigger（review-dev-plan:block -> write-dev-plan / review-dev-plan:upstream-design-blocker）并让 Skill 独占状态命令、Pipeline 只保留路由与重放；⑤ R7 消费 dir-graph.yaml 权威转移声明静态拦截错误字面量。明确不做：不新增 owner-handover、Pipeline Runner、WAL、grant v2 或 rejection 文件；不改 Multica 源码；不删 inbox-emit；不改 CI workflow；不拆分 crctl.mjs。改动面：tools 包 crctl.mjs、五个 Skill、四个 pipeline 模板与人读契约。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-11T01:24:47+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-11T01:24:47+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-11T01:24:47+08:00"
target-version: tbd
source: docs/analysis/tools-tca-001-004-optimization-plan.md
status: tech-design-review-pending
created: "2026-08-11T01:24:47+08:00"
updated: "2026-08-11T01:24:47+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-11T01:24:47+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-11T01:24:47+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-11T01:24:47+08:00", reason: initial-assignment }
handover-history: []
---
