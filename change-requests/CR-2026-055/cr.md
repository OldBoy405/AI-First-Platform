---
id: CR-2026-055
title: 评审分层最小改造 — 技术设计评审前移 AC 可达性与可观测验收、SDD 自引用代码事实核验、plan 评审翻译增量职责、reviewer 受控只读取证授权
summary: "合并《技术设计评审提速最小优化方案》与《SDD评审前移校验方案》为一个最小改造 CR，实施范围仅 ../tools/ 8 个文件：review-tech-design、review-dev-plan、write-tech-design、controlled-shell 四个 SKILL.md，agent-skill-matrix.yml，architecture-design 与 code-implementation 两条 pipeline JSON，pipeline-structure.test.mjs。核心规则：(1) review-tech-design 首轮全量 8 维度完成后统一 verdict，回修优先上一轮 blocker 与本轮变化，AC 设计落点/可达性/可观测验收与 SDD 自引用既有代码事实前移核验；(2) review-dev-plan 聚焦 SDD/AC→plan/TASK 翻译增量，核 TASK 新造代码事实、真实责任边界与无关短路假绿，保留双轨路由与 UPSTREAM 安全网；(3) Pipeline 原样传递 workspace/resources/review_feedback/self_repair_attempt，reviewer 通过受控只读能力取证（quality-reviewer-agent.can-call 增补 controlled-shell）；(4) 不新增状态、节点、账本、索引、digest、事务框架或评审 Agent，不修改 crctl.mjs/gates.json/rules.json/状态机；历史 CR 不迁移不重审，CR-2026-054 不追溯。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-29T21:58:51+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-29T21:58:51+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-29T21:58:51+08:00"
target-version: tbd
source: "docs/product/评审分层最小改造方案.md"
origin: ""
status: developing
created: "2026-08-29T21:58:51+08:00"
updated: "2026-08-30T00:31:10+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-29T21:58:51+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-29T21:58:51+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-29T21:58:51+08:00", reason: initial-assignment }
handover-history: []
---
